package ui

import resources "../resources"
import shared "../shared"
import "core:math"
import "core:strings"

editor_resource_number :: proc(state: ^State, binding: shared.Editor_UI_Component) -> (f32, bool) {
	if state == nil ||
	   state.resource_registry == nil ||
	   binding.resource_id == (shared.Resource_UUID{}) {
		return 0, false
	}
	handle, found := resources.material_by_uuid(state.resource_registry, binding.resource_id)
	if !found {
		return 0, false
	}
	material, alive := resources.get_material(state.resource_registry, handle)
	if !alive {
		return 0, false
	}
	axis := int(binding.inspector_axis) - 1
	#partial switch binding.inspector_field {
		case .Material_Base_Color:
			values := [4]f32 {
				material.desc.base_color.x,
				material.desc.base_color.y,
				material.desc.base_color.z,
				material.desc.base_color.w,
			}
			if axis >= 0 && axis < len(values) {
				return values[axis], true
			}
		case .Material_Emissive:
			values := [3]f32 {
				material.desc.emissive.x,
				material.desc.emissive.y,
				material.desc.emissive.z,
			}
			if axis >= 0 && axis < len(values) {
				return values[axis], true
			}
		case .Material_Metallic:
			return material.desc.metallic_factor, true
		case .Material_Roughness:
			return material.desc.roughness_factor, true
	}
	return 0, false
}

editor_resource_write_number :: proc(
	state: ^State,
	binding: shared.Editor_UI_Component,
	number: f32,
) -> bool {
	if state == nil ||
	   state.resource_registry == nil ||
	   math.is_nan(number) ||
	   math.is_inf(number) {
		return false
	}
	handle, found := resources.material_by_uuid(state.resource_registry, binding.resource_id)
	if !found {
		return false
	}
	material, alive := resources.get_material(state.resource_registry, handle)
	if !alive || !material.authored {
		return false
	}
	axis := int(binding.inspector_axis) - 1
	written := false
	#partial switch binding.inspector_field {
		case .Material_Base_Color:
			if axis >= 0 && axis < 4 {
				values := [4]^f32 {
					&material.desc.base_color.x,
					&material.desc.base_color.y,
					&material.desc.base_color.z,
					&material.desc.base_color.w,
				}
				values[axis]^ = number
				written = true
			}
		case .Material_Emissive:
			if number < 0 {
				return false
			}
			if axis >= 0 && axis < 3 {
				values := [3]^f32 {
					&material.desc.emissive.x,
					&material.desc.emissive.y,
					&material.desc.emissive.z,
				}
				values[axis]^ = number
				written = true
			}
		case .Material_Metallic:
			if number < 0 || number > 1 {
				return false
			}
			material.desc.metallic_factor = number
			written = true
		case .Material_Roughness:
			if number < 0 || number > 1 {
				return false
			}
			material.desc.roughness_factor = number
			written = true
	}
	if written {
		_ = resources.touch_material(state.resource_registry, handle)
		editor_mark_resource_dirty(state, binding.resource_id)
	}
	return written
}

editor_mark_resource_dirty :: proc(state: ^State, id: shared.Resource_UUID) {
	if state == nil || !state.editor_simulation_stopped || id == (shared.Resource_UUID{}) {
		return
	}
	if state.editor_dirty_resource_lookup == nil {
		state.editor_dirty_resource_lookup = make(map[shared.Resource_UUID]bool)
	}
	if !state.editor_dirty_resource_lookup[id] {
		state.editor_dirty_resource_lookup[id] = true
		append(&state.editor_dirty_resources, id)
	}
	state.editor_scene_dirty = true
	state.editor_scene_save_failed = false
	state.editor_scene_revert_failed = false
}

editor_history_push_resource :: proc(
	state: ^State,
	binding: shared.Editor_UI_Component,
	before, after: f32,
) {
	if state == nil || before == after {
		editor_recompute_scene_dirty(state)
		return
	}
	transaction: Editor_Edit_Transaction
	transaction.resource_changes[0] = {
		resource_id = binding.resource_id,
		field = binding.inspector_field,
		axis = binding.inspector_axis,
		before_number = before,
		after_number = after,
	}
	transaction.resource_change_count = 1
	editor_history_push_transaction(state, transaction)
}

editor_resource_usage_count :: proc(world: ^shared.World, id: shared.Resource_UUID) -> int {
	if world == nil || id == (shared.Resource_UUID{}) {
		return 0
	}
	count := 0
	for entity in world.entities {
		if !entity.alive || entity.origin == .Editor || entity.material_resource == "" {
			continue
		}
		resource_id, valid := shared.resource_uuid_parse(entity.material_resource)
		if valid && resource_id == id {
			count += 1
		}
	}
	return count
}

editor_select_first_resource_usage :: proc(
	state: ^State,
	world: ^shared.World,
	id: shared.Resource_UUID,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	for entity, index in world.entities {
		if !entity.alive || entity.origin == .Editor || entity.material_resource == "" {
			continue
		}
		resource_id, valid := shared.resource_uuid_parse(entity.material_resource)
		if valid && resource_id == id {
			state.editor_selected_entity = world.entities[index].id
			state.editor_has_selection = true
			state.editor_has_resource_selection = false
			state.editor_snapshot_valid = false
			return true
		}
	}
	return false
}

editor_history_push_resource_structural :: proc(
	state: ^State,
	id: shared.Resource_UUID,
	before, after: ^resources.Project_Material_Snapshot,
) {
	change := new(Editor_Resource_Structural_Change)
	change.resource_id = id
	change.before = before
	change.after = after
	transaction: Editor_Edit_Transaction
	transaction.resource_structural = change
	editor_history_push_transaction(state, transaction)
}

editor_authoring_create_resource :: proc(state: ^State) -> bool {
	if state == nil || state.resource_registry == nil || !state.editor_simulation_stopped {
		return false
	}
	name, source := resources.unique_project_material_identity(
		state.resource_registry,
		"Material",
		"material.resource.toml",
	)
	defer delete(name)
	defer delete(source)
	if name == "" || source == "" {
		return false
	}
	id := shared.resource_uuid_generate()
	after := new(resources.Project_Material_Snapshot)
	after.id = id
	after.name, _ = strings.clone(name)
	after.source, _ = strings.clone(source)
	after.desc.base_color = {0.8, 0.8, 0.8, 1}
	after.desc.roughness_factor = 0.8
	if resources.apply_project_material_snapshot(state.resource_registry, id, after) != "" {
		resources.destroy_project_material_snapshot(after)
		free(after)
		return false
	}
	editor_history_push_resource_structural(state, id, nil, after)
	editor_mark_resource_dirty(state, id)
	state.editor_selected_resource = id
	state.editor_has_resource_selection = true
	state.editor_has_selection = false
	state.editor_snapshot_valid = false
	return true
}

editor_authoring_duplicate_resource :: proc(state: ^State) -> bool {
	if state == nil ||
	   state.resource_registry == nil ||
	   !state.editor_simulation_stopped ||
	   !state.editor_has_resource_selection {
		return false
	}
	source_snapshot, found := resources.capture_project_material(
		state.resource_registry,
		state.editor_selected_resource,
	)
	if !found {
		return false
	}
	defer {
		resources.destroy_project_material_snapshot(source_snapshot)
		free(source_snapshot)
	}
	name, source := resources.unique_project_material_identity(
		state.resource_registry,
		source_snapshot.name,
		source_snapshot.source,
	)
	defer delete(name)
	defer delete(source)
	after := resources.clone_project_material_snapshot(source_snapshot)
	after.id = shared.resource_uuid_generate()
	delete(after.name)
	delete(after.source)
	after.name, _ = strings.clone(name)
	after.source, _ = strings.clone(source)
	if resources.apply_project_material_snapshot(state.resource_registry, after.id, after) != "" {
		resources.destroy_project_material_snapshot(after)
		free(after)
		return false
	}
	editor_history_push_resource_structural(state, after.id, nil, after)
	editor_mark_resource_dirty(state, after.id)
	state.editor_selected_resource = after.id
	state.editor_snapshot_valid = false
	return true
}

editor_authoring_update_resource_identity :: proc(state: ^State, name, source: string) -> bool {
	if state == nil ||
	   state.resource_registry == nil ||
	   !state.editor_simulation_stopped ||
	   !state.editor_has_resource_selection {
		return false
	}
	id := state.editor_selected_resource
	before, found := resources.capture_project_material(state.resource_registry, id)
	if !found {
		return false
	}
	if before.name == name && before.source == source {
		resources.destroy_project_material_snapshot(before)
		free(before)
		return true
	}
	after := resources.clone_project_material_snapshot(before)
	delete(after.name)
	delete(after.source)
	after.name, _ = strings.clone(name)
	after.source, _ = strings.clone(source)
	if resources.apply_project_material_snapshot(state.resource_registry, id, after) != "" {
		resources.destroy_project_material_snapshot(before)
		free(before)
		resources.destroy_project_material_snapshot(after)
		free(after)
		return false
	}
	editor_history_push_resource_structural(state, id, before, after)
	editor_mark_resource_dirty(state, id)
	state.editor_snapshot_valid = false
	return true
}

editor_authoring_delete_resource :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil ||
	   state.resource_registry == nil ||
	   !state.editor_simulation_stopped ||
	   !state.editor_has_resource_selection ||
	   editor_resource_usage_count(world, state.editor_selected_resource) > 0 {
		return false
	}
	id := state.editor_selected_resource
	before, found := resources.capture_project_material(state.resource_registry, id)
	if !found {
		return false
	}
	if resources.apply_project_material_snapshot(state.resource_registry, id, nil) != "" {
		resources.destroy_project_material_snapshot(before)
		free(before)
		return false
	}
	editor_history_push_resource_structural(state, id, before, nil)
	editor_mark_resource_dirty(state, id)
	state.editor_has_resource_selection = false
	state.editor_snapshot_valid = false
	return true
}
