package schedule

import "core:testing"

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

system_with_access :: proc(component: string, mode: Access_Mode) -> System {
	system: System
	system.accesses[0] = Access{component = component, mode = mode}
	system.access_count = 1
	return system
}
