package schedule

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

build_plan :: proc(systems: []System) -> Plan {
	plan: Plan

	for system, system_index in systems {
		placed := false
		for batch_index in 0..<plan.batch_count {
			if batch_accepts_system(plan.batches[batch_index], system, systems) {
				append_system_to_batch(&plan.batches[batch_index], system_index)
				placed = true
				break
			}
		}

		if !placed {
			batch := &plan.batches[plan.batch_count]
			append_system_to_batch(batch, system_index)
			plan.batch_count += 1
		}
	}

	return plan
}

batch_accepts_system :: proc(batch: Batch, candidate: System, systems: []System) -> bool {
	for i in 0..<batch.system_count {
		existing_index := batch.system_indices[i]
		if systems_conflict(systems[existing_index], candidate) {
			return false
		}
	}
	return true
}

systems_conflict :: proc(a, b: System) -> bool {
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
