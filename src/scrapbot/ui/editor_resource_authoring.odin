package ui

import resources "../resources"
import shared "../shared"
import "core:math"

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
	}
	if written {
		material.version += 1
		editor_mark_resource_dirty(state, binding.resource_id)
		state.editor_snapshot_valid = false
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
