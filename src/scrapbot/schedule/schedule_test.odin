package schedule

import "core:testing"
import "core:sync"
import "core:time"
import "core:thread"

@(test)
test_scheduler_batches_read_only_systems_together :: proc(t: ^testing.T) {
	systems := [?]System {
		system_with_access("autorotate", .Read),
		system_with_access("autorotate", .Read),
	}

	plan := build_plan(systems[:])

	testing.expect(t, plan.batch_count == 1)
	testing.expect(t, plan.batches[0].system_count == 2)
	testing.expect(t, plan.batches[0].system_indices[0] == 0)
	testing.expect(t, plan.batches[0].system_indices[1] == 1)
}

@(test)
test_scheduler_splits_read_write_conflicts :: proc(t: ^testing.T) {
	systems := [?]System {
		system_with_access("autorotate", .Read),
		system_with_access("scrapbot.transform", .Write),
		system_with_access("scrapbot.transform", .Read),
	}

	plan := build_plan(systems[:])

	testing.expect(t, plan.batch_count == 2)
	testing.expect(t, plan.batches[0].system_count == 2)
	testing.expect(t, plan.batches[0].system_indices[0] == 0)
	testing.expect(t, plan.batches[0].system_indices[1] == 1)
	testing.expect(t, plan.batches[1].system_count == 1)
	testing.expect(t, plan.batches[1].system_indices[0] == 2)
}

@(test)
test_scheduler_splits_write_write_conflicts :: proc(t: ^testing.T) {
	systems := [?]System {
		system_with_access("scrapbot.transform", .Write),
		system_with_access("scrapbot.transform", .Write),
		system_with_access("autorotate", .Write),
	}

	plan := build_plan(systems[:])

	testing.expect(t, plan.batch_count == 2)
	testing.expect(t, plan.batches[0].system_count == 2)
	testing.expect(t, plan.batches[0].system_indices[0] == 0)
	testing.expect(t, plan.batches[0].system_indices[1] == 2)
	testing.expect(t, plan.batches[1].system_count == 1)
	testing.expect(t, plan.batches[1].system_indices[0] == 1)
}

@(test)
test_scheduler_serializes_systems_without_access_declarations :: proc(t: ^testing.T) {
	systems := [?]System {
		{},
		system_with_access("autorotate", .Read),
		{},
	}

	plan := build_plan(systems[:])

	testing.expect(t, plan.batch_count == 3)
	testing.expect(t, plan.batches[0].system_indices[0] == 0)
	testing.expect(t, plan.batches[1].system_indices[0] == 1)
	testing.expect(t, plan.batches[2].system_indices[0] == 2)
}

@(test)
test_scheduler_preserves_order_across_transitive_conflicts :: proc(t: ^testing.T) {
	systems := [?]System {
		system_with_access("a", .Write),
		system_with_access("b", .Write),
		system_with_access("a", .Write),
		system_with_access("b", .Write),
	}

	plan := build_plan(systems[:])

	testing.expect(t, plan.batch_count == 2)
	testing.expect(t, plan.batches[0].system_indices[0] == 0)
	testing.expect(t, plan.batches[0].system_indices[1] == 1)
	testing.expect(t, plan.batches[1].system_indices[0] == 2)
	testing.expect(t, plan.batches[1].system_indices[1] == 3)
}

Parallel_Test_Context :: struct {
	started: ^sync.Wait_Group,
	release: ^sync.Sema,
	completed: ^int,
}

parallel_test_work :: proc(data: rawptr) {
	ctx := cast(^Parallel_Test_Context)data
	sync.wait_group_done(ctx.started)
	sync.wait(ctx.release)
	sync.atomic_add(ctx.completed, 1)
}

@(test)
test_executor_runs_independent_work_concurrently :: proc(t: ^testing.T) {
	executor: Executor
	init_executor(&executor, 2)
	defer destroy_executor(&executor)

	started: sync.Wait_Group
	sync.wait_group_add(&started, 2)
	release: sync.Sema
	completed: int
	contexts := [2]Parallel_Test_Context {
		{started = &started, release = &release, completed = &completed},
		{started = &started, release = &release, completed = &completed},
	}
	work := [2]Work {
		{procedure = parallel_test_work, data = &contexts[0]},
		{procedure = parallel_test_work, data = &contexts[1]},
	}

	worker := thread.create_and_start_with_poly_data2(&executor, work[:], proc(executor: ^Executor, work: []Work) {
		run_parallel(executor, work)
	})
	testing.expect(t, sync.wait_group_wait_with_timeout(&started, time.Second))
	sync.post(&release, 2)
	thread.destroy(worker)
	testing.expect(t, sync.atomic_load(&completed) == 2)
	testing.expect(t, executor.parallel_stages == 1)
	testing.expect(t, executor.max_parallel_width == 2)
}

system_with_access :: proc(component: string, mode: Access_Mode) -> System {
	system: System
	system.accesses[0] = Access{component = component, mode = mode}
	system.access_count = 1
	return system
}
