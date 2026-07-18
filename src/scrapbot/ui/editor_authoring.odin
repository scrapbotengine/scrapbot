package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"

editor_authoring_definition_is_supported :: proc(definition: ^component.Definition) -> bool {
	return definition != nil && component.definition_is_authorable(definition^)
}

editor_authoring_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if definition == nil || !editor_authoring_definition_is_supported(definition) {
		return false
	}
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	if world.entities[entity_index].origin != .Scene {
		return false
	}
	before := capture_component_snapshot_pointer(world, entity_index, definition)
	if before == nil {
		return false
	}
	if !ecs.set_registered_component_membership(world, entity_index, definition, present) {
		destroy_component_snapshot_pointer(before)
		return false
	}
	after := capture_component_snapshot_pointer(world, entity_index, definition)
	if after == nil {
		_ = ecs.apply_registered_component_snapshot(world, entity_index, before)
		destroy_component_snapshot_pointer(before)
		return false
	}
	push_component_structural_change(state, world.entities[entity_index].uuid, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if state == nil || world == nil || definition == nil {
		return false
	}
	if state.editor_simulation_stopped {
		return editor_authoring_set_registered_component(
			state,
			world,
			entity_index,
			definition,
			present,
		)
	}
	if !editor_authoring_definition_is_supported(definition) ||
	   !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return false
	}
	if !ecs.set_registered_component_membership(world, entity_index, definition, present) {
		return false
	}
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_component_membership_available :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if state == nil || world == nil || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	origin := world.entities[entity_index].origin
	if state.editor_simulation_stopped {
		return origin == .Scene
	}
	return origin != .Editor
}

editor_authoring_create_entity :: proc(
	state: ^State,
	world: ^shared.World,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) {
		return {}, false
	}
	snapshot := new(ecs.Entity_Snapshot)
	snapshot.origin = .Scene
	snapshot.entity.id = shared.entity_uuid_generate()
	snapshot.entity.name = ecs.clone_snapshot_string("New Entity")
	snapshot.entity.has_transform = true
	snapshot.entity.transform.scale = {1, 1, 1}
	entity_index, ok := ecs.apply_entity_snapshot(world, snapshot)
	if !ok {
		ecs.destroy_entity_snapshot(snapshot)
		free(snapshot)
		return {}, false
	}
	push_structural_change(state, snapshot.entity.id, nil, snapshot)
	editor_authoring_select(state, world, entity_index)
	return world.entities[entity_index].id, true
}

editor_authoring_duplicate_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return {}, false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		return {}, false
	}
	after.entity.id = shared.entity_uuid_generate()
	delete(after.entity.name)
	after.entity.name = ecs.clone_snapshot_string(
		fmt.tprintf("%s Copy", world.entities[entity_index].name),
	)
	after.origin = .Scene
	created_index, ok := ecs.apply_entity_snapshot(world, after)
	if !ok {
		destroy_snapshot_pointer(after)
		return {}, false
	}
	push_structural_change(state, after.entity.id, nil, after)
	editor_authoring_select(state, world, created_index)
	return world.entities[created_index].id, true
}

editor_authoring_delete_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id := before.entity.id
	if !ecs.delete_entity_by_uuid(world, id) {
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, id, before, nil)
	state.editor_has_selection = false
	state.editor_snapshot_valid = false
	return true
}

editor_authoring_rename_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	name: string,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   name == "" ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene || before.entity.name == name {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.set_entity_name(world, entity_index, name) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_set_material_resource :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	resource_id: shared.Resource_UUID,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   state.resource_registry == nil ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	if _, found := resources.material_by_uuid(state.resource_registry, resource_id); !found {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id_buffer: [36]u8
	value := shared.resource_uuid_to_string(resource_id, id_buffer[:])
	if before.entity.material_resource == value {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		destroy_snapshot_pointer(before)
		return false
	}
	delete(after.entity.material_resource)
	after.entity.material_resource = ecs.clone_snapshot_string(value)
	after.entity.has_material = true
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

resolve_snapshot_resource_names :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	snapshot: ^ecs.Entity_Snapshot,
) {
	if state == nil || state.resource_registry == nil || snapshot == nil {
		return
	}
	entity := world.entities[entity_index]
	if snapshot.entity.geometry_resource == "" &&
	   entity.geometry_index >= 0 &&
	   entity.geometry_index < len(world.geometries) {
		handle := world.geometries[entity.geometry_index].handle
		if int(handle.index) < len(state.resource_registry.geometries) {
			resource := state.resource_registry.geometries[handle.index]
			if resource.alive && resource.generation == handle.generation {
				snapshot.entity.has_geometry = true
				snapshot.entity.geometry_resource = ecs.clone_snapshot_string(resource.name)
			}
		}
	}
	if snapshot.entity.material_resource == "" &&
	   entity.material_index >= 0 &&
	   entity.material_index < len(world.materials) {
		handle := world.materials[entity.material_index].handle
		if int(handle.index) < len(state.resource_registry.materials) {
			resource := state.resource_registry.materials[handle.index]
			if resource.alive && resource.authored && resource.generation == handle.generation {
				id_buffer: [36]u8
				snapshot.entity.has_material = true
				snapshot.entity.material_resource = ecs.clone_snapshot_string(
					shared.resource_uuid_to_string(resource.id, id_buffer[:]),
				)
			}
		}
	}
}

editor_authoring_promote_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Runtime {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.promote_entity_to_scene(world, entity_index) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	resolve_snapshot_resource_names(state, world, entity_index, after)
	_, _ = ecs.apply_entity_snapshot(world, after)
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_available :: proc(state: ^State, world: ^shared.World) -> bool {
	return state != nil && world != nil && state.editor_simulation_stopped
}

capture_snapshot_pointer :: proc(world: ^shared.World, entity_index: int) -> ^ecs.Entity_Snapshot {
	snapshot, ok := ecs.capture_entity_snapshot(world, entity_index)
	if !ok {
		return nil
	}
	result := new(ecs.Entity_Snapshot)
	result^ = snapshot
	return result
}

destroy_snapshot_pointer :: proc(snapshot: ^ecs.Entity_Snapshot) {
	if snapshot == nil {
		return
	}
	ecs.destroy_entity_snapshot(snapshot)
	free(snapshot)
}

capture_component_snapshot_pointer :: proc(
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
) -> ^ecs.Registered_Component_Snapshot {
	snapshot, ok := ecs.capture_registered_component_snapshot(world, entity_index, definition)
	if !ok {
		return nil
	}
	result := new(ecs.Registered_Component_Snapshot)
	result^ = snapshot
	return result
}

destroy_component_snapshot_pointer :: proc(snapshot: ^ecs.Registered_Component_Snapshot) {
	if snapshot == nil {
		return
	}
	ecs.destroy_registered_component_snapshot(snapshot)
	free(snapshot)
}

push_structural_change :: proc(
	state: ^State,
	id: shared.Entity_UUID,
	before, after: ^ecs.Entity_Snapshot,
) {
	change := new(Editor_Structural_Change)
	change.target_uuid = id
	change.before = before
	change.after = after
	editor_history_push_transaction(state, {structural = change})
	editor_mark_scene_uuid_dirty(state, id)
}

push_component_structural_change :: proc(
	state: ^State,
	id: shared.Entity_UUID,
	before, after: ^ecs.Registered_Component_Snapshot,
) {
	change := new(Editor_Component_Structural_Change)
	change.target_uuid = id
	change.before = before
	change.after = after
	editor_history_push_transaction(state, {component_structural = change})
	editor_mark_scene_uuid_dirty(state, id)
}

editor_authoring_select :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	state.editor_selected_entity = world.entities[entity_index].id
	state.editor_has_selection = true
	state.editor_has_resource_selection = false
	state.editor_snapshot_valid = false
}
