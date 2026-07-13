package schedule

import "core:os"
import "core:thread"

MAX_SYSTEMS :: 64
MAX_SYSTEM_ACCESSES :: 16

Access_Mode :: enum {
	Read,
	Write,
}

Access :: struct {
	component: string,
	mode:      Access_Mode,
}

System :: struct {
	accesses: [MAX_SYSTEM_ACCESSES]Access,
	access_count: int,
}

Batch :: struct {
	system_indices: [MAX_SYSTEMS]int,
	system_count: int,
}

Plan :: struct {
	batches: [MAX_SYSTEMS]Batch,
	batch_count: int,
}

Work_Proc :: #type proc(data: rawptr)

Work :: struct {
	procedure: Work_Proc,
	data:      rawptr,
}

Executor :: struct {
	pool:        thread.Pool,
	initialized: bool,
	worker_count: int,
	parallel_stages: int,
	max_parallel_width: int,
}

Work_Context :: struct {
	work: Work,
}

build_plan :: proc(systems: []System) -> Plan {
	plan: Plan

	for system, system_index in systems {
		batch_index := 0
		for previous_index in 0..<system_index {
			if systems_conflict(systems[previous_index], system) {
				previous_batch := system_batch_index(plan, previous_index)
				batch_index = max(batch_index, previous_batch + 1)
			}
		}

		append_system_to_batch(&plan.batches[batch_index], system_index)
		if batch_index >= plan.batch_count {
			plan.batch_count = batch_index + 1
		}
	}

	return plan
}

system_batch_index :: proc(plan: Plan, system_index: int) -> int {
	for batch_index in 0..<plan.batch_count {
		batch := plan.batches[batch_index]
		for i in 0..<batch.system_count {
			if batch.system_indices[i] == system_index {
				return batch_index
			}
		}
	}
	return -1
}

systems_conflict :: proc(a, b: System) -> bool {
	if a.access_count == 0 || b.access_count == 0 {
		return true
	}
	for a_index in 0..<a.access_count {
		a_access := a.accesses[a_index]
		for b_index in 0..<b.access_count {
			b_access := b.accesses[b_index]
			if accesses_conflict(a_access, b_access) {
				return true
			}
		}
	}
	return false
}

accesses_conflict :: proc(a, b: Access) -> bool {
	if a.component != b.component {
		return false
	}
	return a.mode == .Write || b.mode == .Write
}

append_system_to_batch :: proc(batch: ^Batch, system_index: int) {
	if batch.system_count >= MAX_SYSTEMS {
		return
	}
	batch.system_indices[batch.system_count] = system_index
	batch.system_count += 1
}

init_executor :: proc(executor: ^Executor, worker_count := 0) {
	if executor == nil || executor.initialized {
		return
	}
	count := worker_count
	if count <= 0 {
		count = max(os.get_processor_core_count() - 1, 1)
	}
	count = min(count, MAX_SYSTEMS)
	thread.pool_init(&executor.pool, os.heap_allocator(), count)
	thread.pool_start(&executor.pool)
	executor.worker_count = count
	executor.initialized = true
}

destroy_executor :: proc(executor: ^Executor) {
	if executor == nil || !executor.initialized {
		return
	}
	thread.pool_join(&executor.pool)
	thread.pool_destroy(&executor.pool)
	executor^ = {}
}

run_parallel :: proc(executor: ^Executor, work: []Work) {
	if len(work) == 0 {
		return
	}
	if len(work) == 1 {
		if work[0].procedure != nil {
			work[0].procedure(work[0].data)
		}
		return
	}
	if executor == nil {
		for item in work {
			if item.procedure != nil {
				item.procedure(item.data)
			}
		}
		return
	}
	executor.parallel_stages += 1
	executor.max_parallel_width = max(executor.max_parallel_width, len(work))
	if !executor.initialized {
		init_executor(executor)
	}

	contexts: [MAX_SYSTEMS]Work_Context
	for item, index in work {
		contexts[index] = Work_Context{work = item}
		thread.pool_add_task(
			&executor.pool,
			os.heap_allocator(),
			run_work,
			&contexts[index],
		)
	}
	completed := 0
	for completed < len(work) {
		if _, ok := thread.pool_pop_done(&executor.pool); ok {
			completed += 1
		} else {
			thread.yield()
		}
	}
}

run_work :: proc(task: thread.Task) {
	work_context := cast(^Work_Context)task.data
	if work_context.work.procedure != nil {
		work_context.work.procedure(work_context.work.data)
	}
}
