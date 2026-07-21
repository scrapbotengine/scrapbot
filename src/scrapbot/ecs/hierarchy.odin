package ecs

import shared "../shared"

next_scene_order_index :: proc(world: ^World) -> int {
	if world == nil {
		return 0
	}
	return world.next_scene_order
}

ordered_non_editor_entity_indices :: proc(world: ^World) -> [dynamic]int {
	indices: [dynamic]int
	if world == nil {
		return indices
	}
	for entity, entity_index in world.entities {
		if entity.alive && entity.origin != .Editor {
			append(&indices, entity_index)
		}
	}
	sort_entity_indices_by_scene_order(world, indices[:])
	return indices
}

sort_entity_indices_by_scene_order :: proc(world: ^World, indices: []int) {
	if world == nil {
		return
	}
	if len(indices) < 2 {
		return
	}
	scratch: [dynamic]int
	defer delete(scratch)
	resize(&scratch, len(indices))
	for width := 1; width < len(indices); width *= 2 {
		for left := 0; left < len(indices); left += width * 2 {
			middle := min(left + width, len(indices))
			right := min(left + width * 2, len(indices))
			first, second := left, middle
			for output in left ..< right {
				use_first := second >= right
				if first < middle && second < right {
					first_entity := world.entities[indices[first]]
					second_entity := world.entities[indices[second]]
					use_first =
						first_entity.scene_order < second_entity.scene_order ||
						(first_entity.scene_order == second_entity.scene_order &&
								indices[first] < indices[second])
				}
				if use_first {
					scratch[output] = indices[first]
					first += 1
				} else {
					scratch[output] = indices[second]
					second += 1
				}
			}
		}
		copy(indices[:], scratch[:])
	}
}

entity_scene_order_index :: proc(world: ^World, entity_index: int) -> (int, bool) {
	if world == nil || !entity_is_alive(world, entity_index) {
		return -1, false
	}
	indices := ordered_non_editor_entity_indices(world)
	defer delete(indices)
	for candidate, order_index in indices {
		if candidate == entity_index {
			return order_index, true
		}
	}
	return -1, false
}

set_entity_scene_order_index :: proc(world: ^World, entity_index, requested_index: int) -> bool {
	if world == nil ||
	   !entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return false
	}
	indices := ordered_non_editor_entity_indices(world)
	defer delete(indices)
	current_index := -1
	for candidate, order_index in indices {
		if candidate == entity_index {
			current_index = order_index
			break
		}
	}
	if current_index < 0 {
		return false
	}
	ordered_remove(&indices, current_index)
	destination := clamp(requested_index, 0, len(indices))
	append(&indices, entity_index)
	for index := len(indices) - 1; index > destination; index -= 1 {
		indices[index] = indices[index - 1]
	}
	indices[destination] = entity_index
	for candidate, order_index in indices {
		world.entities[candidate].scene_order = order_index
	}
	return true
}

move_entity_scene_order :: proc(
	world: ^World,
	entity_index, target_index: int,
	after: bool,
) -> bool {
	if world == nil ||
	   entity_index == target_index ||
	   !entity_is_alive(world, entity_index) ||
	   !entity_is_alive(world, target_index) ||
	   world.entities[entity_index].origin == .Editor ||
	   world.entities[target_index].origin == .Editor {
		return false
	}
	indices := ordered_non_editor_entity_indices(world)
	defer delete(indices)
	source_order, target_order := -1, -1
	for candidate, order_index in indices {
		if candidate == entity_index {
			source_order = order_index
		}
		if candidate == target_index {
			target_order = order_index
		}
	}
	if source_order < 0 || target_order < 0 {
		return false
	}
	destination := target_order
	if after {
		destination += 1
	}
	if source_order < destination {
		destination -= 1
	}
	if source_order == destination {
		return false
	}
	return set_entity_scene_order_index(world, entity_index, destination)
}

entity_is_descendant_of_uuid :: proc(
	world: ^World,
	entity_index: int,
	ancestor: shared.Entity_UUID,
) -> bool {
	if world == nil ||
	   ancestor == (shared.Entity_UUID{}) ||
	   !entity_is_alive(world, entity_index) {
		return false
	}
	cursor := entity_index
	for _ in 0 ..< len(world.entities) {
		entity := world.entities[cursor]
		if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
			return false
		}
		parent := world.transforms[entity.transform_index].parent
		if parent == ancestor {
			return true
		}
		if parent == (shared.Entity_UUID{}) {
			return false
		}
		parent_index, found := entity_index_by_uuid(world, parent)
		if !found || parent_index == cursor {
			return false
		}
		cursor = parent_index
	}
	return false
}

move_entity_scene_order_subtree :: proc(
	world: ^World,
	entity_index, target_index: int,
	after: bool,
) -> bool {
	if world == nil ||
	   entity_index == target_index ||
	   !entity_is_alive(world, entity_index) ||
	   !entity_is_alive(world, target_index) {
		return false
	}
	ordered := ordered_non_editor_entity_indices(world)
	defer delete(ordered)
	source_uuid := world.entities[entity_index].uuid
	target_uuid := world.entities[target_index].uuid
	moving: [dynamic]int
	remaining: [dynamic]int
	defer delete(moving)
	defer delete(remaining)
	for candidate in ordered {
		if candidate == entity_index ||
		   entity_is_descendant_of_uuid(world, candidate, source_uuid) {
			append(&moving, candidate)
		} else {
			append(&remaining, candidate)
		}
	}
	if len(moving) == 0 {
		return false
	}
	destination := -1
	for candidate, order_index in remaining {
		if candidate == target_index {
			destination = order_index
			if !after {
				break
			}
		} else if after &&
		   destination >= 0 &&
		   !entity_is_descendant_of_uuid(world, candidate, target_uuid) {
			break
		}
		if after && destination >= 0 {
			destination = order_index + 1
		}
	}
	if destination < 0 {
		return false
	}
	result: [dynamic]int
	defer delete(result)
	for candidate, order_index in remaining {
		if order_index == destination {
			append(&result, ..moving[:])
		}
		append(&result, candidate)
	}
	if destination == len(remaining) {
		append(&result, ..moving[:])
	}
	if len(result) != len(ordered) {
		return false
	}
	changed := false
	for candidate, order_index in result {
		if candidate != ordered[order_index] {
			changed = true
		}
		world.entities[candidate].scene_order = order_index
	}
	return changed
}

begin_world_transform_resolution :: proc(world: ^World) {
	if world == nil {
		return
	}
	world.world_transform_resolution_epoch += 1
	if world.world_transform_resolution_epoch == 0 {
		world.world_transform_resolution_epoch = 1
		for &epoch in world.resolved_world_transform_epochs {
			epoch = 0
		}
		for &epoch in world.resolving_world_transform_epochs {
			epoch = 0
		}
	}
	for len(world.resolved_world_transforms) < len(world.entities) {
		append(&world.resolved_world_transforms, Transform_Component{})
		append(&world.resolved_world_transform_epochs, 0)
		append(&world.resolved_world_transform_valid, false)
		append(&world.resolving_world_transform_epochs, 0)
	}
}

resolve_world_transform :: proc(
	world: ^World,
	entity_index: int,
) -> (
	transform: Transform_Component,
	valid: bool,
) {
	if world == nil || !entity_is_alive(world, entity_index) {
		return {}, false
	}
	entity := world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		return {}, false
	}
	if world.world_transform_resolution_epoch == 0 ||
	   len(world.resolved_world_transforms) < len(world.entities) {
		begin_world_transform_resolution(world)
	}
	epoch := world.world_transform_resolution_epoch
	if world.resolved_world_transform_epochs[entity_index] == epoch {
		return world.resolved_world_transforms[entity_index],
			world.resolved_world_transform_valid[entity_index]
	}
	local := world.transforms[entity.transform_index]
	if world.resolving_world_transform_epochs[entity_index] == epoch {
		local.parent = {}
		return local, false
	}
	world.resolving_world_transform_epochs[entity_index] = epoch
	defer world.resolving_world_transform_epochs[entity_index] = 0
	result := local
	result.parent = {}
	valid = true
	if local.parent != (shared.Entity_UUID{}) {
		parent_index, parent_found := entity_index_by_uuid(world, local.parent)
		if !parent_found || parent_index == entity_index {
			valid = false
		} else {
			parent_entity := world.entities[parent_index]
			if parent_entity.transform_index >= 0 &&
			   parent_entity.transform_index < len(world.transforms) {
				parent, parent_valid := resolve_world_transform(world, parent_index)
				if parent_valid {
					result = shared.transform_combine(parent, local)
					result.parent = {}
				} else {
					valid = false
				}
			}
		}
	}
	world.resolved_world_transforms[entity_index] = result
	world.resolved_world_transform_epochs[entity_index] = epoch
	world.resolved_world_transform_valid[entity_index] = valid
	return result, valid
}

transform_parent_is_valid :: proc(
	world: ^World,
	entity_index: int,
	parent: shared.Entity_UUID,
) -> bool {
	if world == nil || !entity_is_alive(world, entity_index) {
		return false
	}
	if parent == (shared.Entity_UUID{}) {
		return true
	}
	parent_index, found := entity_index_by_uuid(world, parent)
	if !found || parent_index == entity_index {
		return false
	}
	steps := 0
	cursor := parent_index
	for cursor >= 0 {
		if cursor == entity_index {
			return false
		}
		steps += 1
		if steps > len(world.entities) {
			return false
		}
		candidate := world.entities[cursor]
		if candidate.transform_index < 0 || candidate.transform_index >= len(world.transforms) {
			break
		}
		next := world.transforms[candidate.transform_index].parent
		if next == (shared.Entity_UUID{}) {
			break
		}
		cursor, found = entity_index_by_uuid(world, next)
		if !found {
			return false
		}
	}
	return true
}

set_transform_parent :: proc(
	world: ^World,
	entity_index: int,
	parent: shared.Entity_UUID,
	preserve_world: bool = true,
) -> bool {
	if !transform_parent_is_valid(world, entity_index, parent) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		return false
	}
	local := world.transforms[entity.transform_index]
	if local.parent == parent {
		return true
	}
	world_value := local
	if preserve_world {
		begin_world_transform_resolution(world)
		world_value, _ = resolve_world_transform(world, entity_index)
	}
	local.parent = parent
	if preserve_world && parent != (shared.Entity_UUID{}) {
		parent_index, _ := entity_index_by_uuid(world, parent)
		parent_entity := world.entities[parent_index]
		if parent_entity.transform_index >= 0 &&
		   parent_entity.transform_index < len(world.transforms) {
			begin_world_transform_resolution(world)
			parent_world, parent_valid := resolve_world_transform(world, parent_index)
			if !parent_valid {
				return false
			}
			local = shared.transform_relative_to(parent_world, world_value)
		}
		local.parent = parent
	} else if preserve_world {
		local = world_value
		local.parent = {}
	}
	world.transforms[entity.transform_index] = local
	world.render_hierarchy_revision += 1
	mark_render_transform_dirty(world, entity_index)
	return true
}

detach_transform_children :: proc(world: ^World, parent_index: int) {
	if world == nil || !entity_is_alive(world, parent_index) {
		return
	}
	parent := world.entities[parent_index].uuid
	for entity, entity_index in world.entities {
		if !entity.alive ||
		   entity_index == parent_index ||
		   entity.transform_index < 0 ||
		   entity.transform_index >= len(world.transforms) {
			continue
		}
		if world.transforms[entity.transform_index].parent == parent {
			_ = set_transform_parent(world, entity_index, {}, true)
		}
	}
}
