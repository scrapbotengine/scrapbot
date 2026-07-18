package ui

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:math"
import "core:strconv"
import "core:strings"

set_inspector_vec3_axis :: proc(
	value: ^shared.Vec3,
	axis: shared.Editor_Inspector_Axis,
	number: f32,
) -> bool {
	if value == nil { return false }
	switch axis {
		case .X:
			value.x = number
		case .Y:
			value.y = number
		case .Z:
			value.z = number
		case .None, .W:
			return false
	}
	return true
}


inspector_target :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	^shared.World_Entity,
	int,
	bool,
) {
	target_index := int(binding.target.index)
	if target_index < 0 || target_index >= len(world.entities) { return nil, -1, false }
	target := &world.entities[target_index]
	if !target.alive || target.id != binding.target { return nil, -1, false }
	return target, target_index, true
}

read_inspector_numeric :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	f32,
	bool,
) {
	target, target_index, ok := inspector_target(world, binding)
	if !ok { return 0, false }
	axis_value := proc(value: shared.Vec3, axis: shared.Editor_Inspector_Axis) -> (f32, bool) {
		switch axis {
			case .X:
				return value.x, true
			case .Y:
				return value.y, true
			case .Z:
				return value.z, true
			case .None, .W:
				return 0, false
		}
		return 0, false
	}
	#partial switch binding.inspector_field {
		case .Transform_Position, .Transform_Rotation, .Transform_Scale:
			if target.transform_index < 0 ||
			   target.transform_index >= len(world.transforms) { return 0, false }
			value := world.transforms[target.transform_index]
			#partial switch binding.inspector_field {
				case .Transform_Position:
					return axis_value(value.position, binding.inspector_axis)
				case .Transform_Rotation:
					return axis_value(value.rotation, binding.inspector_axis)
				case .Transform_Scale:
					return axis_value(value.scale, binding.inspector_axis)
			}
		case .Camera_Fov, .Camera_Near, .Camera_Far:
			if target.camera_index < 0 ||
			   target.camera_index >= len(world.cameras) { return 0, false }
			value := world.cameras[target.camera_index]
			#partial switch binding.inspector_field {
				case .Camera_Fov:
					return value.fov, true
				case .Camera_Near:
					return value.near, true
				case .Camera_Far:
					return value.far, true
			}
		case .Ambient_Color, .Ambient_Intensity:
			if target.ambient_light_index < 0 ||
			   target.ambient_light_index >= len(world.ambient_lights) { return 0, false }
			value := world.ambient_lights[target.ambient_light_index]
			if binding.inspector_field ==
			   .Ambient_Color { return axis_value(value.color, binding.inspector_axis) }
			return value.intensity, true
		case .Directional_Direction, .Directional_Color, .Directional_Intensity:
			if target.directional_light_index < 0 ||
			   target.directional_light_index >= len(world.directional_lights) { return 0, false }
			value := world.directional_lights[target.directional_light_index]
			#partial switch binding.inspector_field {
				case .Directional_Direction:
					return axis_value(value.direction, binding.inspector_axis)
				case .Directional_Color:
					return axis_value(value.color, binding.inspector_axis)
				case .Directional_Intensity:
					return value.intensity, true
			}
		case .Point_Color, .Point_Intensity, .Point_Range:
			if target.point_light_index < 0 ||
			   target.point_light_index >= len(world.point_lights) { return 0, false }
			value := world.point_lights[target.point_light_index]
			#partial switch binding.inspector_field {
				case .Point_Color:
					return axis_value(value.color, binding.inspector_axis)
				case .Point_Intensity:
					return value.intensity, true
				case .Point_Range:
					return value.range, true
			}
		case .Custom_Vec3:
			if binding.custom_storage_index < 0 ||
			   binding.custom_storage_index >= len(world.custom_components) { return 0, false }
			storage := &world.custom_components[binding.custom_storage_index]
			for &component in storage.components {
				if component.entity_index != target_index ||
				   binding.custom_field_index < 0 ||
				   binding.custom_field_index >= len(component.vec3_fields) { continue }
				return axis_value(
					component.vec3_fields[binding.custom_field_index].value,
					binding.inspector_axis,
				)
			}
	}
	return 0, false
}

write_inspector_numeric :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	number: f32,
) -> bool {
	if math.is_nan(number) || math.is_inf(number) { return false }
	target, target_index, ok := inspector_target(world, binding)
	if !ok { return false }
	written := false
	#partial switch binding.inspector_field {
		case .Transform_Position, .Transform_Rotation, .Transform_Scale:
			if target.transform_index < 0 ||
			   target.transform_index >= len(world.transforms) { return false }
			#partial switch binding.inspector_field {
				case .Transform_Position:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].position,
						binding.inspector_axis,
						number,
					)
				case .Transform_Rotation:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].rotation,
						binding.inspector_axis,
						number,
					)
				case .Transform_Scale:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].scale,
						binding.inspector_axis,
						number,
					)
			}
		case .Camera_Fov, .Camera_Near, .Camera_Far:
			if target.camera_index < 0 ||
			   target.camera_index >= len(world.cameras) { return false }
			camera := &world.cameras[target.camera_index]
			if binding.inspector_field == .Camera_Near && number >= camera.far { return false }
			if binding.inspector_field == .Camera_Far && number <= camera.near { return false }
			#partial switch binding.inspector_field {
				case .Camera_Fov:
					camera.fov = number
				case .Camera_Near:
					camera.near = number
				case .Camera_Far:
					camera.far = number
			}
			written = true
		case .Ambient_Color, .Ambient_Intensity:
			if target.ambient_light_index < 0 ||
			   target.ambient_light_index >= len(world.ambient_lights) { return false }
			if binding.inspector_field == .Ambient_Color {
				written = set_inspector_vec3_axis(
					&world.ambient_lights[target.ambient_light_index].color,
					binding.inspector_axis,
					number,
				)
			} else {world.ambient_lights[target.ambient_light_index].intensity = number
				written = true}
		case .Directional_Direction, .Directional_Color, .Directional_Intensity:
			if target.directional_light_index < 0 ||
			   target.directional_light_index >= len(world.directional_lights) { return false }
			#partial switch binding.inspector_field {
				case .Directional_Direction:
					written = set_inspector_vec3_axis(
						&world.directional_lights[target.directional_light_index].direction,
						binding.inspector_axis,
						number,
					)
				case .Directional_Color:
					written = set_inspector_vec3_axis(
						&world.directional_lights[target.directional_light_index].color,
						binding.inspector_axis,
						number,
					)
				case .Directional_Intensity:
					world.directional_lights[target.directional_light_index].intensity = number
					written = true
			}
		case .Point_Color, .Point_Intensity, .Point_Range:
			if target.point_light_index < 0 ||
			   target.point_light_index >= len(world.point_lights) { return false }
			#partial switch binding.inspector_field {
				case .Point_Color:
					written = set_inspector_vec3_axis(
						&world.point_lights[target.point_light_index].color,
						binding.inspector_axis,
						number,
					)
				case .Point_Intensity:
					world.point_lights[target.point_light_index].intensity = number; written = true
				case .Point_Range:
					world.point_lights[target.point_light_index].range = number; written = true
			}
		case .Custom_Vec3:
			if binding.custom_storage_index < 0 ||
			   binding.custom_storage_index >= len(world.custom_components) { return false }
			storage := &world.custom_components[binding.custom_storage_index]
			for &component in storage.components {
				if component.entity_index != target_index ||
				   binding.custom_field_index < 0 ||
				   binding.custom_field_index >= len(component.vec3_fields) { continue }
				written = set_inspector_vec3_axis(
					&component.vec3_fields[binding.custom_field_index].value,
					binding.inspector_axis,
					number,
				)
				break
			}
	}
	if written && state != nil {
		editor_mark_scene_dirty(state, target)
	}
	return written
}

read_inspector_bool :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	bool,
	bool,
) {
	target, _, ok := inspector_target(world, binding)
	if !ok { return false, false }
	#partial switch binding.inspector_field {
		case .UI_Layout_Hidden:
			if target.ui_layout_index >= 0 && target.ui_layout_index < len(world.ui_layouts) {
				return world.ui_layouts[target.ui_layout_index].hidden, true
			}
		case .UI_HStack_Fill, .UI_HStack_Draggable:
			if target.ui_hstack_index >= 0 && target.ui_hstack_index < len(world.ui_hstacks) {
				stack := world.ui_hstacks[target.ui_hstack_index]
				if binding.inspector_field == .UI_HStack_Fill { return stack.fill, true }
				return stack.draggable, true
			}
		case .UI_VStack_Fill, .UI_VStack_Draggable:
			if target.ui_vstack_index >= 0 && target.ui_vstack_index < len(world.ui_vstacks) {
				stack := world.ui_vstacks[target.ui_vstack_index]
				if binding.inspector_field == .UI_VStack_Fill { return stack.fill, true }
				return stack.draggable, true
			}
		case .UI_Panel_Collapsible, .UI_Panel_Collapsed:
			if target.ui_panel_index >= 0 && target.ui_panel_index < len(world.ui_panels) {
				panel := world.ui_panels[target.ui_panel_index]
				if binding.inspector_field ==
				   .UI_Panel_Collapsible { return panel.collapsible, true }
				return panel.collapsed, true
			}
		case .UI_Input_Read_Only:
			if target.ui_input_index >= 0 && target.ui_input_index < len(world.ui_inputs) {
				return world.ui_inputs[target.ui_input_index].read_only, true
			}
		case .UI_Checkbox_Checked, .UI_Checkbox_Read_Only:
			if target.ui_checkbox_index >= 0 &&
			   target.ui_checkbox_index < len(world.ui_checkboxes) {
				checkbox := world.ui_checkboxes[target.ui_checkbox_index]
				if binding.inspector_field ==
				   .UI_Checkbox_Checked { return checkbox.checked, true }
				return checkbox.read_only, true
			}
	}
	return false, false
}

write_inspector_bool :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	value: bool,
) -> bool {
	target, target_index, ok := inspector_target(world, binding)
	if !ok { return false }
	written := false
	#partial switch binding.inspector_field {
		case .UI_Layout_Hidden:
			if target.ui_layout_index >= 0 && target.ui_layout_index < len(world.ui_layouts) {
				world.ui_layouts[target.ui_layout_index].hidden = value
				ecs.mark_ui_subtree_dirty(world, target_index)
				written = true
			}
		case .UI_HStack_Fill, .UI_HStack_Draggable:
			if target.ui_hstack_index >= 0 && target.ui_hstack_index < len(world.ui_hstacks) {
				stack := &world.ui_hstacks[target.ui_hstack_index]
				if binding.inspector_field == .UI_HStack_Fill {
					stack.fill = value
					if !value { stack.draggable = false }
				} else {
					stack.draggable = value
					if value { stack.fill = true }
				}
				written = true
			}
		case .UI_VStack_Fill, .UI_VStack_Draggable:
			if target.ui_vstack_index >= 0 && target.ui_vstack_index < len(world.ui_vstacks) {
				stack := &world.ui_vstacks[target.ui_vstack_index]
				if binding.inspector_field == .UI_VStack_Fill {
					stack.fill = value
					if !value { stack.draggable = false }
				} else {
					stack.draggable = value
					if value { stack.fill = true }
				}
				written = true
			}
		case .UI_Panel_Collapsible, .UI_Panel_Collapsed:
			if target.ui_panel_index >= 0 && target.ui_panel_index < len(world.ui_panels) {
				panel := &world.ui_panels[target.ui_panel_index]
				if binding.inspector_field == .UI_Panel_Collapsible {
					panel.collapsible = value
					if !value { panel.collapsed = false }
				} else if panel.collapsible || !value {
					panel.collapsed = value
				} else {
					return false
				}
				written = true
			}
		case .UI_Input_Read_Only:
			if target.ui_input_index >= 0 && target.ui_input_index < len(world.ui_inputs) {
				world.ui_inputs[target.ui_input_index].read_only = value
				written = true
			}
		case .UI_Checkbox_Checked, .UI_Checkbox_Read_Only:
			if target.ui_checkbox_index >= 0 &&
			   target.ui_checkbox_index < len(world.ui_checkboxes) {
				checkbox := &world.ui_checkboxes[target.ui_checkbox_index]
				if binding.inspector_field == .UI_Checkbox_Checked {
					checkbox.checked = value
				} else {
					checkbox.read_only = value
				}
				written = true
			}
	}
	if written && state != nil {
		state.editor_snapshot_valid = false
		editor_mark_scene_dirty(state, target)
	}
	return written
}

editor_history_push :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	before, after: f32,
) {
	if state == nil || world == nil { return }
	if before == after {
		editor_recompute_scene_dirty(state)
		return
	}
	target, _, found := inspector_target(world, binding)
	if !found { return }
	transaction: Editor_Edit_Transaction
	transaction.changes[0] = {
		target_uuid = target.uuid,
		component_revision = target.component_revision,
		field = binding.inspector_field,
		axis = binding.inspector_axis,
		custom_storage_index = binding.custom_storage_index,
		custom_field_index = binding.custom_field_index,
		kind = .Number,
		before_number = before,
		after_number = after,
	}
	transaction.change_count = 1
	editor_history_push_transaction(state, transaction)
}

editor_history_push_bool :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	before, after: bool,
) {
	if state == nil || world == nil { return }
	if before == after {
		editor_recompute_scene_dirty(state)
		return
	}
	target, _, found := inspector_target(world, binding)
	if !found { return }
	transaction: Editor_Edit_Transaction
	transaction.changes[0] = {
		target_uuid = target.uuid,
		component_revision = target.component_revision,
		field = binding.inspector_field,
		axis = binding.inspector_axis,
		custom_storage_index = binding.custom_storage_index,
		custom_field_index = binding.custom_field_index,
		kind = .Boolean,
		before_boolean = before,
		after_boolean = after,
	}
	transaction.change_count = 1
	editor_history_push_transaction(state, transaction)
}

editor_history_begin_bool_transaction :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	Editor_Edit_Transaction,
	bool,
) {
	if world == nil {
		return {}, false
	}
	target, _, found := inspector_target(world, binding)
	if !found {
		return {}, false
	}
	fields := [2]shared.Editor_Inspector_Field{binding.inspector_field, binding.inspector_field}
	field_count := 1
	#partial switch binding.inspector_field {
		case .UI_HStack_Fill, .UI_HStack_Draggable:
			fields = {.UI_HStack_Fill, .UI_HStack_Draggable}
			field_count = 2
		case .UI_VStack_Fill, .UI_VStack_Draggable:
			fields = {.UI_VStack_Fill, .UI_VStack_Draggable}
			field_count = 2
		case .UI_Panel_Collapsible, .UI_Panel_Collapsed:
			fields = {.UI_Panel_Collapsible, .UI_Panel_Collapsed}
			field_count = 2
		case:
	}
	transaction: Editor_Edit_Transaction
	for field, index in fields[:field_count] {
		field_binding := binding
		field_binding.inspector_field = field
		value, available := read_inspector_bool(world, field_binding)
		if !available {
			return {}, false
		}
		transaction.changes[index] = {
			target_uuid = target.uuid,
			component_revision = target.component_revision,
			field = field,
			axis = binding.inspector_axis,
			custom_storage_index = binding.custom_storage_index,
			custom_field_index = binding.custom_field_index,
			kind = .Boolean,
			before_boolean = value,
		}
	}
	transaction.change_count = field_count
	return transaction, true
}

editor_history_finish_bool_transaction :: proc(
	state: ^State,
	world: ^shared.World,
	transaction: Editor_Edit_Transaction,
) {
	if state == nil || world == nil {
		return
	}
	completed: Editor_Edit_Transaction
	changes := transaction.changes
	for change in changes[:transaction.change_count] {
		entity_index, found := ecs.entity_index_by_uuid(world, change.target_uuid)
		if !found {
			continue
		}
		binding := shared.Editor_UI_Component {
			target = world.entities[entity_index].id,
			inspector_field = change.field,
			inspector_axis = change.axis,
			custom_storage_index = change.custom_storage_index,
			custom_field_index = change.custom_field_index,
		}
		after, available := read_inspector_bool(world, binding)
		if !available || after == change.before_boolean {
			continue
		}
		next := change
		next.after_boolean = after
		completed.changes[completed.change_count] = next
		completed.change_count += 1
	}
	editor_history_push_transaction(state, completed)
}

editor_history_push_transform :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	field: shared.Editor_Inspector_Field,
	before, after: shared.Vec3,
) {
	if state == nil || world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	target := &world.entities[entity_index]
	if !target.alive { return }
	transaction: Editor_Edit_Transaction
	before_values := [3]f32{before.x, before.y, before.z}
	after_values := [3]f32{after.x, after.y, after.z}
	axes := [3]shared.Editor_Inspector_Axis{.X, .Y, .Z}
	for before_value, index in before_values {
		if before_value == after_values[index] { continue }
		change_index := transaction.change_count
		transaction.changes[change_index] = {
			target_uuid = target.uuid,
			component_revision = target.component_revision,
			field = field,
			axis = axes[index],
			kind = .Number,
			before_number = before_value,
			after_number = after_values[index],
		}
		transaction.change_count += 1
	}
	editor_history_push_transaction(state, transaction)
}

editor_history_push_transaction :: proc(state: ^State, transaction: Editor_Edit_Transaction) {
	if state == nil { return }
	if !state.editor_simulation_stopped {
		discarded := transaction
		editor_history_destroy_transaction(&discarded)
		return
	}
	if transaction.change_count <= 0 &&
	   transaction.resource_change_count <= 0 &&
	   transaction.structural == nil &&
	   transaction.component_structural == nil &&
	   transaction.resource_structural == nil {
		editor_recompute_scene_dirty(state)
		return
	}
	if state.editor_history_clean_valid &&
	   state.editor_history_clean_cursor > state.editor_history_cursor {
		state.editor_history_clean_valid = false
	}
	for index in state.editor_history_cursor ..< state.editor_history_count {
		editor_history_destroy_transaction(&state.editor_history[index])
	}
	state.editor_history_count = state.editor_history_cursor
	if state.editor_history_count >= EDITOR_HISTORY_CAPACITY {
		if state.editor_history_clean_valid {
			if state.editor_history_clean_cursor == 0 {
				state.editor_history_clean_valid = false
			} else {
				state.editor_history_clean_cursor -= 1
			}
		}
		editor_history_destroy_transaction(&state.editor_history[0])
		copy(state.editor_history[0:EDITOR_HISTORY_CAPACITY - 1], state.editor_history[1:])
		state.editor_history[EDITOR_HISTORY_CAPACITY - 1] = {}
		state.editor_history_count = EDITOR_HISTORY_CAPACITY - 1
		state.editor_history_cursor = state.editor_history_count
	}
	state.editor_history[state.editor_history_count] = transaction
	state.editor_history_count += 1
	state.editor_history_cursor = state.editor_history_count
	editor_recompute_scene_dirty(state)
}

editor_history_remove :: proc(state: ^State, index: int) {
	if state == nil || index < 0 || index >= state.editor_history_count { return }
	if state.editor_history_clean_valid && state.editor_history_clean_cursor > index {
		state.editor_history_clean_cursor -= 1
	}
	editor_history_destroy_transaction(&state.editor_history[index])
	if index + 1 < state.editor_history_count {
		copy(
			state.editor_history[index:state.editor_history_count - 1],
			state.editor_history[index + 1:state.editor_history_count],
		)
	}
	state.editor_history_count -= 1
	state.editor_history[state.editor_history_count] = {}
	if state.editor_history_cursor > index { state.editor_history_cursor -= 1 }
	state.editor_history_cursor = clamp(state.editor_history_cursor, 0, state.editor_history_count)
	editor_recompute_scene_dirty(state)
}

editor_history_apply :: proc(state: ^State, world: ^shared.World, redo: bool) -> bool {
	if state == nil || world == nil { return false }
	for {
		index := state.editor_history_cursor
		if !redo { index -= 1 }
		if index < 0 || index >= state.editor_history_count { return false }
		transaction := state.editor_history[index]
		if transaction.resource_structural != nil {
			change := transaction.resource_structural
			desired := change.before
			if redo {
				desired = change.after
			}
			if resources.apply_project_material_snapshot(
				   state.resource_registry,
				   change.resource_id,
				   desired,
			   ) ==
			   "" {
				editor_mark_resource_dirty(state, change.resource_id)
				state.editor_has_resource_selection = desired != nil
				if desired != nil {
					state.editor_selected_resource = change.resource_id
				}
				if redo {
					state.editor_history_cursor = index + 1
				} else {
					state.editor_history_cursor = index
				}
				editor_recompute_scene_dirty(state)
				return true
			}
			editor_history_remove(state, index)
			continue
		}
		if transaction.structural != nil {
			change := transaction.structural
			desired := change.before
			if redo { desired = change.after }
			applied := false
			deleting_selected := false
			selected: shared.Entity
			if desired == nil {
				if entity_index, found := ecs.entity_index_by_uuid(world, change.target_uuid);
				   found {
					deleting_selected =
						state.editor_has_selection &&
						state.editor_selected_entity == world.entities[entity_index].id
				}
				applied = ecs.delete_entity_by_uuid(world, change.target_uuid)
			} else if entity_index, ok := ecs.apply_entity_snapshot(world, desired); ok {
				applied = true
				selected = world.entities[entity_index].id
			}
			if applied {
				editor_mark_scene_uuid_dirty(state, change.target_uuid)
				if desired == nil {
					if deleting_selected {
						state.editor_has_selection = false
					}
				} else {
					state.editor_selected_entity = selected
					state.editor_has_selection = true
				}
				if redo { state.editor_history_cursor = index + 1 } else { state.editor_history_cursor = index }
				editor_recompute_scene_dirty(state)
				return true
			}
			editor_history_remove(state, index)
			continue
		}
		if transaction.component_structural != nil {
			change := transaction.component_structural
			desired := change.before
			if redo {
				desired = change.after
			}
			entity_index, found := ecs.entity_index_by_uuid(world, change.target_uuid)
			if found &&
			   desired != nil &&
			   ecs.apply_registered_component_snapshot(world, entity_index, desired) {
				editor_mark_scene_uuid_dirty(state, change.target_uuid)
				state.editor_selected_entity = world.entities[entity_index].id
				state.editor_has_selection = true
				if redo {
					state.editor_history_cursor = index + 1
				} else {
					state.editor_history_cursor = index
				}
				editor_recompute_scene_dirty(state)
				return true
			}
			editor_history_remove(state, index)
			continue
		}
		if transaction.resource_change_count > 0 {
			applied := true
			for change in transaction.resource_changes[:transaction.resource_change_count] {
				binding := shared.Editor_UI_Component {
					resource_id = change.resource_id,
					inspector_field = change.field,
					inspector_axis = change.axis,
				}
				value := change.before_number
				if redo {
					value = change.after_number
				}
				applied = editor_resource_write_number(state, binding, value) && applied
			}
			if applied {
				if redo {
					state.editor_history_cursor = index + 1
				} else {
					state.editor_history_cursor = index
				}
				editor_recompute_scene_dirty(state)
				return true
			}
			editor_history_remove(state, index)
			continue
		}
		valid := true
		for change in transaction.changes[:transaction.change_count] {
			entity_index, found := ecs.entity_index_by_uuid(world, change.target_uuid)
			if !found ||
			   entity_index < 0 ||
			   entity_index >= len(world.entities) ||
			   !world.entities[entity_index].alive ||
			   world.entities[entity_index].component_revision != change.component_revision {
				valid = false
				break
			}
		}
		if valid {
			applied := true
			for change in transaction.changes[:transaction.change_count] {
				entity_index, _ := ecs.entity_index_by_uuid(world, change.target_uuid)
				binding := shared.Editor_UI_Component {
					target = world.entities[entity_index].id,
					inspector_field = change.field,
					inspector_axis = change.axis,
					custom_storage_index = change.custom_storage_index,
					custom_field_index = change.custom_field_index,
				}
				switch change.kind {
					case .Number:
						value := change.before_number
						if redo { value = change.after_number }
						applied = write_inspector_numeric(state, world, binding, value) && applied
					case .Boolean:
						value := change.before_boolean
						if redo { value = change.after_boolean }
						applied = write_inspector_bool(state, world, binding, value) && applied
				}
			}
			if applied {
				if redo { state.editor_history_cursor = index + 1 } else { state.editor_history_cursor = index }
				editor_recompute_scene_dirty(state)
				return true
			}
		}
		editor_history_remove(state, index)
	}
}

editor_history_destroy_transaction :: proc(transaction: ^Editor_Edit_Transaction) {
	if transaction == nil {
		return
	}
	if transaction.structural != nil {
		change := transaction.structural
		if change.before != nil {
			ecs.destroy_entity_snapshot(change.before)
			free(change.before)
		}
		if change.after != nil {
			ecs.destroy_entity_snapshot(change.after)
			free(change.after)
		}
		free(change)
	}
	if transaction.component_structural != nil {
		change := transaction.component_structural
		if change.before != nil {
			ecs.destroy_registered_component_snapshot(change.before)
			free(change.before)
		}
		if change.after != nil {
			ecs.destroy_registered_component_snapshot(change.after)
			free(change.after)
		}
		free(change)
	}
	if transaction.resource_structural != nil {
		change := transaction.resource_structural
		if change.before != nil {
			resources.destroy_project_material_snapshot(change.before)
			free(change.before)
		}
		if change.after != nil {
			resources.destroy_project_material_snapshot(change.after)
			free(change.after)
		}
		free(change)
	}
	transaction^ = {}
}

editor_history_clear :: proc(state: ^State) {
	if state == nil {
		return
	}
	for index in 0 ..< state.editor_history_count {
		editor_history_destroy_transaction(&state.editor_history[index])
	}
	state.editor_history_count = 0
	state.editor_history_cursor = 0
	state.editor_history_clean_cursor = 0
	state.editor_history_clean_valid = true
}

focused_input_binding :: proc(
	state: ^State,
	world: ^shared.World,
) -> (
	shared.Editor_UI_Component,
	int,
	bool,
) {
	if state == nil || world == nil || !state.has_focused_input { return {}, -1, false }
	entity_index := int(state.focused_input.index)
	if entity_index < 0 || entity_index >= len(world.entities) { return {}, -1, false }
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != state.focused_input ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) { return {}, -1, false }
	return world.editor_uis[entity.editor_ui_index], entity_index, true
}

validate_focused_editor_input :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || !state.has_focused_input || !state.focused_input_editor {
		return
	}
	binding, input_entity, found := focused_input_binding(state, world)
	available := found && !ui_entity_or_ancestor_hidden(world, input_entity)
	if available && binding.role == .Inspector_Input {
		if binding.resource_id != (shared.Resource_UUID{}) {
			_, available = editor_resource_number(state, binding)
		} else {
			_, _, available = inspector_target(world, binding)
			if available && binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
				_, available = editor_reflected_definition(state, binding)
			} else if available {
				entity := world.entities[input_entity]
				if entity.ui_input_index >= 0 &&
				   entity.ui_input_index < len(world.ui_inputs) &&
				   world.ui_inputs[entity.ui_input_index].numeric {
					_, available = read_inspector_numeric(world, binding)
				}
			}
		}
	}
	if !available { clear_input_focus(state) }
}
