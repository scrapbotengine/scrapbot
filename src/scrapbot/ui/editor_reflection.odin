package ui

import component "../component"
import ecs "../ecs"
import shared "../shared"
import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strconv"
import "core:strings"

editor_reflected_definition :: proc(
	state: ^State,
	binding: shared.Editor_UI_Component,
) -> (
	^component.Definition,
	bool,
) {
	if state == nil ||
	   state.component_registry == nil ||
	   binding.reflected_component_id == shared.INVALID_COMPONENT_ID {
		return nil, false
	}
	registry := state.component_registry
	for index in 0 ..< registry.definition_count {
		definition := &registry.definitions[index]
		if definition.id != binding.reflected_component_id {
			continue
		}
		if binding.reflected_field_index < 0 ||
		   binding.reflected_field_index >= definition.field_count {
			return nil, false
		}
		return definition, true
	}
	return nil, false
}

editor_reflected_component_value :: proc(
	entity: ^shared.Scene_Entity,
	name: string,
) -> (
	any,
	bool,
) {
	if entity == nil {
		return nil, false
	}
	switch name {
		case "scrapbot.transform":
			if entity.has_transform {
				return any{rawptr(&entity.transform), typeid_of(shared.Transform_Component)}, true
			}
		case "scrapbot.camera":
			if entity.has_camera {
				return any{rawptr(&entity.camera), typeid_of(shared.Camera_Component)}, true
			}
		case "scrapbot.ambient_light":
			if entity.has_ambient_light {
				return any {
						rawptr(&entity.ambient_light),
						typeid_of(shared.Ambient_Light_Component),
					},
					true
			}
		case "scrapbot.directional_light":
			if entity.has_directional_light {
				return any {
						rawptr(&entity.directional_light),
						typeid_of(shared.Directional_Light_Component),
					},
					true
			}
		case "scrapbot.point_light":
			if entity.has_point_light {
				return any{rawptr(&entity.point_light), typeid_of(shared.Point_Light_Component)},
					true
			}
		case "scrapbot.mesh":
			if entity.has_mesh {
				return any{rawptr(&entity.mesh), typeid_of(shared.Mesh_Component)}, true
			}
		case "scrapbot.ui_layout":
			if entity.has_ui_layout {
				return any{rawptr(&entity.ui_layout), typeid_of(shared.UI_Layout_Component)}, true
			}
		case "scrapbot.ui_hstack":
			if entity.has_ui_hstack {
				return any{rawptr(&entity.ui_hstack), typeid_of(shared.UI_Stack_Component)}, true
			}
		case "scrapbot.ui_vstack":
			if entity.has_ui_vstack {
				return any{rawptr(&entity.ui_vstack), typeid_of(shared.UI_Stack_Component)}, true
			}
		case "scrapbot.ui_scroll_area":
			if entity.has_ui_scroll_area {
				return any {
						rawptr(&entity.ui_scroll_area),
						typeid_of(shared.UI_Scroll_Area_Component),
					},
					true
			}
		case "scrapbot.ui_panel":
			if entity.has_ui_panel {
				return any{rawptr(&entity.ui_panel), typeid_of(shared.UI_Panel_Component)}, true
			}
		case "scrapbot.ui_table":
			if entity.has_ui_table {
				return any{rawptr(&entity.ui_table), typeid_of(shared.UI_Table_Component)}, true
			}
		case "scrapbot.ui_list":
			if entity.has_ui_list {
				return any{rawptr(&entity.ui_list), typeid_of(shared.UI_List_Component)}, true
			}
		case "scrapbot.ui_progress":
			if entity.has_ui_progress {
				return any{rawptr(&entity.ui_progress), typeid_of(shared.UI_Progress_Component)},
					true
			}
		case "scrapbot.ui_text":
			if entity.has_ui_text {
				return any{rawptr(&entity.ui_text), typeid_of(shared.UI_Text_Component)}, true
			}
		case "scrapbot.ui_button":
			if entity.has_ui_button {
				return any{rawptr(&entity.ui_button), typeid_of(shared.UI_Button_Component)}, true
			}
		case "scrapbot.ui_input":
			if entity.has_ui_input {
				return any{rawptr(&entity.ui_input), typeid_of(shared.UI_Input_Component)}, true
			}
		case "scrapbot.ui_checkbox":
			if entity.has_ui_checkbox {
				return any{rawptr(&entity.ui_checkbox), typeid_of(shared.UI_Checkbox_Component)},
					true
			}
	}
	return nil, false
}

editor_reflected_field_value :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	field_index: int,
) -> (
	any,
	bool,
) {
	if entity == nil ||
	   definition == nil ||
	   field_index < 0 ||
	   field_index >= definition.field_count {
		return nil, false
	}
	field := definition.fields[field_index]
	if definition.name == "scrapbot.geometry" && entity.has_geometry && field.name == "resource" {
		return any{rawptr(&entity.geometry_resource), typeid_of(string)}, true
	}
	if definition.name == "scrapbot.material" && entity.has_material && field.name == "resource" {
		return any{rawptr(&entity.material_resource), typeid_of(string)}, true
	}
	if definition.owner != .Engine {
		for &custom in entity.custom_components {
			if custom.name != definition.name {
				continue
			}
			for &custom_field in custom.number_fields {
				if custom_field.name == field.name {
					return any{rawptr(&custom_field.value), typeid_of(f32)}, true
				}
			}
			for &custom_field in custom.vec2_fields {
				if custom_field.name == field.name {
					return any{rawptr(&custom_field.value), typeid_of(shared.Vec2)}, true
				}
			}
			for &custom_field in custom.vec3_fields {
				if custom_field.name == field.name {
					return any{rawptr(&custom_field.value), typeid_of(shared.Vec3)}, true
				}
			}
			for &custom_field in custom.vec4_fields {
				if custom_field.name == field.name {
					return any{rawptr(&custom_field.value), typeid_of(shared.Vec4)}, true
				}
			}
		}
		return nil, false
	}
	value, found := editor_reflected_component_value(entity, definition.name)
	if !found {
		return nil, false
	}
	field_value := reflect.struct_field_value_by_name(value, field.name)
	return field_value, field_value != nil
}

editor_reflected_axis_number :: proc(
	value: any,
	axis: shared.Editor_Inspector_Axis,
) -> (
	f32,
	bool,
) {
	if value == nil {
		return 0, false
	}
	if value.id == typeid_of(f32) {
		return (cast(^f32)value.data)^, axis == .None
	}
	if value.id == typeid_of(int) {
		return f32((cast(^int)value.data)^), axis == .None
	}
	if value.id == typeid_of(shared.Vec2) {
		vector := (cast(^shared.Vec2)value.data)^
		switch axis {
			case .X:
				return vector.x, true
			case .Y:
				return vector.y, true
			case .None, .Z, .W:
		}
	}
	if value.id == typeid_of(shared.Vec3) {
		vector := (cast(^shared.Vec3)value.data)^
		switch axis {
			case .X:
				return vector.x, true
			case .Y:
				return vector.y, true
			case .Z:
				return vector.z, true
			case .None, .W:
		}
	}
	if value.id == typeid_of(shared.Vec4) {
		vector := (cast(^shared.Vec4)value.data)^
		switch axis {
			case .X:
				return vector.x, true
			case .Y:
				return vector.y, true
			case .Z:
				return vector.z, true
			case .W:
				return vector.w, true
			case .None:
		}
	}
	return 0, false
}

editor_reflected_field_texts :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	field_index: int,
	uuid_buffer: []u8,
	values: ^[4]string,
) -> (
	int,
	bool,
) {
	field_value, found := editor_reflected_field_value(entity, definition, field_index)
	if !found {
		return 0, false
	}
	field := definition.fields[field_index]
	switch field.field_type {
		case .Bool:
			if field_value.id != typeid_of(bool) {
				return 0, false
			}
			values[0] = fmt.tprintf("%v", (cast(^bool)field_value.data)^)
			return 1, true
		case .Number:
			if field_value.id == typeid_of(f32) {
				values[0] = fmt.tprintf("%.2f", (cast(^f32)field_value.data)^)
				return 1, true
			}
			if field_value.id == typeid_of(int) {
				values[0] = fmt.tprintf("%d", (cast(^int)field_value.data)^)
				return 1, true
			}
			if field_value.id == typeid_of(u64) {
				values[0] = fmt.tprintf("%d", (cast(^u64)field_value.data)^)
				return 1, true
			}
		case .String:
			if field_value.id == typeid_of(string) {
				values[0] = (cast(^string)field_value.data)^
				return 1, true
			}
			if field_value.id == typeid_of(shared.Entity_UUID) {
				id := (cast(^shared.Entity_UUID)field_value.data)^
				values[0] = "none"
				if id != (shared.Entity_UUID{}) {
					values[0] = shared.entity_uuid_to_string(id, uuid_buffer)
				}
				return 1, true
			}
			if field_value.id == typeid_of(shared.UI_Text_Alignment) {
				alignment := (cast(^shared.UI_Text_Alignment)field_value.data)^
				values[0] = "left"
				if alignment == .Center {
					values[0] = "center"
				} else if alignment == .Right {
					values[0] = "right"
				}
				return 1, true
			}
		case .Vec2, .Vec3, .Vec4, .Color:
			axes := [4]shared.Editor_Inspector_Axis{.X, .Y, .Z, .W}
			count := 2
			if field.field_type == .Vec3 {
				count = 3
			} else if field.field_type == .Vec4 || field.field_type == .Color {
				count = 4
			}
			for axis, index in axes[:count] {
				number, number_ok := editor_reflected_axis_number(field_value, axis)
				if !number_ok {
					return 0, false
				}
				values[index] = fmt.tprintf("%.2f", number)
			}
			return count, true
	}
	return 0, false
}

editor_reflected_field_bool :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	field_index: int,
) -> (
	bool,
	bool,
) {
	value, found := editor_reflected_field_value(entity, definition, field_index)
	if !found || value.id != typeid_of(bool) {
		return false, false
	}
	return (cast(^bool)value.data)^, true
}

editor_reflected_set_number :: proc(
	value: any,
	axis: shared.Editor_Inspector_Axis,
	number: f32,
) -> (
	bool,
	bool,
) {
	if value == nil || math.is_nan(number) || math.is_inf(number) {
		return false, false
	}
	if value.id == typeid_of(f32) && axis == .None {
		pointer := cast(^f32)value.data
		changed := pointer^ != number
		pointer^ = number
		return changed, true
	}
	if value.id == typeid_of(int) && axis == .None {
		integer := int(number)
		if f32(integer) != number {
			return false, false
		}
		pointer := cast(^int)value.data
		changed := pointer^ != integer
		pointer^ = integer
		return changed, true
	}
	if value.id == typeid_of(shared.Vec2) {
		pointer := cast(^shared.Vec2)value.data
		switch axis {
			case .X:
				changed := pointer.x != number
				pointer.x = number
				return changed, true
			case .Y:
				changed := pointer.y != number
				pointer.y = number
				return changed, true
			case .None, .Z, .W:
		}
	}
	if value.id == typeid_of(shared.Vec3) {
		pointer := cast(^shared.Vec3)value.data
		switch axis {
			case .X:
				changed := pointer.x != number
				pointer.x = number
				return changed, true
			case .Y:
				changed := pointer.y != number
				pointer.y = number
				return changed, true
			case .Z:
				changed := pointer.z != number
				pointer.z = number
				return changed, true
			case .None, .W:
		}
	}
	if value.id == typeid_of(shared.Vec4) {
		pointer := cast(^shared.Vec4)value.data
		switch axis {
			case .X:
				changed := pointer.x != number
				pointer.x = number
				return changed, true
			case .Y:
				changed := pointer.y != number
				pointer.y = number
				return changed, true
			case .Z:
				changed := pointer.z != number
				pointer.z = number
				return changed, true
			case .W:
				changed := pointer.w != number
				pointer.w = number
				return changed, true
			case .None:
		}
	}
	return false, false
}

editor_reflected_set_text_value :: proc(value: any, text: string) -> (bool, bool) {
	if value == nil {
		return false, false
	}
	if value.id == typeid_of(string) {
		pointer := cast(^string)value.data
		if pointer^ == text {
			return false, true
		}
		next := ecs.clone_snapshot_string(text)
		delete(pointer^)
		pointer^ = next
		return true, true
	}
	if value.id == typeid_of(shared.Entity_UUID) {
		trimmed := strings.trim_space(text)
		next: shared.Entity_UUID
		if trimmed != "" && trimmed != "none" {
			parsed, ok := shared.entity_uuid_parse(trimmed)
			if !ok {
				return false, false
			}
			next = parsed
		}
		pointer := cast(^shared.Entity_UUID)value.data
		changed := pointer^ != next
		pointer^ = next
		return changed, true
	}
	if value.id == typeid_of(shared.UI_Text_Alignment) {
		trimmed := strings.trim_space(text)
		next: shared.UI_Text_Alignment
		switch trimmed {
			case "left":
				next = .Left
			case "center":
				next = .Center
			case "right":
				next = .Right
			case:
				return false, false
		}
		pointer := cast(^shared.UI_Text_Alignment)value.data
		changed := pointer^ != next
		pointer^ = next
		return changed, true
	}
	return false, false
}

editor_reflected_normalize :: proc(
	entity: ^shared.Scene_Entity,
	definition_name, field_name: string,
) {
	if entity == nil {
		return
	}
	switch definition_name {
		case "scrapbot.ui_hstack":
			if field_name == "draggable" && entity.ui_hstack.draggable {
				entity.ui_hstack.fill = true
			} else if field_name == "fill" && !entity.ui_hstack.fill {
				entity.ui_hstack.draggable = false
			}
		case "scrapbot.ui_vstack":
			if field_name == "draggable" && entity.ui_vstack.draggable {
				entity.ui_vstack.fill = true
			} else if field_name == "fill" && !entity.ui_vstack.fill {
				entity.ui_vstack.draggable = false
			}
		case "scrapbot.ui_panel":
			if field_name == "collapsed" && entity.ui_panel.collapsed {
				entity.ui_panel.collapsible = true
			} else if field_name == "collapsible" && !entity.ui_panel.collapsible {
				entity.ui_panel.collapsed = false
			}
		case "scrapbot.ui_table":
			if field_name == "resizable_columns" && entity.ui_table.resizable_columns {
				entity.ui_table.proportional_columns = true
			} else if field_name == "proportional_columns" &&
			   !entity.ui_table.proportional_columns {
				entity.ui_table.resizable_columns = false
			}
	}
}

editor_reflected_component_valid :: proc(
	entity: ^shared.Scene_Entity,
	definition_name: string,
) -> bool {
	if entity == nil {
		return false
	}
	switch definition_name {
		case "scrapbot.camera":
			return(
				entity.camera.fov >= 1 &&
				entity.camera.fov <= 179 &&
				entity.camera.near > 0 &&
				entity.camera.far > entity.camera.near \
			)
		case "scrapbot.ambient_light":
			return(
				entity.ambient_light.intensity >= 0 &&
				entity.ambient_light.color.x >= 0 &&
				entity.ambient_light.color.x <= 1 &&
				entity.ambient_light.color.y >= 0 &&
				entity.ambient_light.color.y <= 1 &&
				entity.ambient_light.color.z >= 0 &&
				entity.ambient_light.color.z <= 1 \
			)
		case "scrapbot.directional_light":
			return(
				entity.directional_light.intensity >= 0 &&
				entity.directional_light.color.x >= 0 &&
				entity.directional_light.color.x <= 1 &&
				entity.directional_light.color.y >= 0 &&
				entity.directional_light.color.y <= 1 &&
				entity.directional_light.color.z >= 0 &&
				entity.directional_light.color.z <= 1 \
			)
		case "scrapbot.point_light":
			return(
				entity.point_light.intensity >= 0 &&
				entity.point_light.range >= 0 &&
				entity.point_light.color.x >= 0 &&
				entity.point_light.color.x <= 1 &&
				entity.point_light.color.y >= 0 &&
				entity.point_light.color.y <= 1 &&
				entity.point_light.color.z >= 0 &&
				entity.point_light.color.z <= 1 \
			)
		case "scrapbot.mesh":
			return entity.mesh.primitive != ""
		case "scrapbot.geometry":
			return entity.geometry_resource != ""
		case "scrapbot.material":
			return entity.material_resource != ""
		case "scrapbot.ui_layout":
			return(
				entity.ui_layout.parent != entity.id &&
				shared.ui_layout_is_valid(entity.ui_layout) \
			)
		case "scrapbot.ui_hstack":
			return shared.ui_stack_is_valid(entity.ui_hstack)
		case "scrapbot.ui_vstack":
			return shared.ui_stack_is_valid(entity.ui_vstack)
		case "scrapbot.ui_scroll_area":
			return shared.ui_scroll_area_is_valid(entity.ui_scroll_area)
		case "scrapbot.ui_panel":
			return shared.ui_panel_is_valid(entity.ui_panel)
		case "scrapbot.ui_table":
			return shared.ui_table_is_valid(entity.ui_table)
		case "scrapbot.ui_list":
			return shared.ui_list_is_valid(entity.ui_list)
		case "scrapbot.ui_progress":
			return shared.ui_progress_is_valid(entity.ui_progress)
		case "scrapbot.ui_text":
			return shared.ui_text_is_valid(entity.ui_text)
		case "scrapbot.ui_button":
			return shared.ui_button_is_valid(entity.ui_button)
		case "scrapbot.ui_input":
			return shared.ui_input_is_valid(entity.ui_input)
		case "scrapbot.ui_checkbox":
			return shared.ui_checkbox_is_valid(entity.ui_checkbox)
	}
	return true
}

editor_reflected_set_field_text :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	field_index: int,
	axis: shared.Editor_Inspector_Axis,
	text: string,
) -> (
	bool,
	bool,
) {
	field_value, found := editor_reflected_field_value(entity, definition, field_index)
	if !found {
		return false, false
	}
	field := definition.fields[field_index]
	changed, parsed := false, false
	switch field.field_type {
		case .Number, .Vec2, .Vec3, .Vec4, .Color:
			number, ok := strconv.parse_f32(strings.trim_space(text))
			if !ok {
				return false, false
			}
			changed, parsed = editor_reflected_set_number(field_value, axis, number)
		case .String:
			changed, parsed = editor_reflected_set_text_value(field_value, text)
		case .Bool:
			return false, false
	}
	if !parsed {
		return false, false
	}
	editor_reflected_normalize(entity, definition.name, field.name)
	return changed, editor_reflected_component_valid(entity, definition.name)
}

editor_reflected_set_field_bool :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	field_index: int,
	checked: bool,
) -> (
	bool,
	bool,
) {
	field_value, found := editor_reflected_field_value(entity, definition, field_index)
	if !found || field_value.id != typeid_of(bool) {
		return false, false
	}
	pointer := cast(^bool)field_value.data
	changed := pointer^ != checked
	pointer^ = checked
	editor_reflected_normalize(entity, definition.name, definition.fields[field_index].name)
	return changed, editor_reflected_component_valid(entity, definition.name)
}

editor_reflected_input_valid :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	text: string,
) -> bool {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false
	}
	target, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false
	}
	snapshot, captured := ecs.capture_entity_snapshot(world, target_index)
	if !captured {
		return false
	}
	defer ecs.destroy_entity_snapshot(&snapshot)
	_, valid := editor_reflected_set_field_text(
		&snapshot.entity,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
		text,
	)
	return valid && target.uuid == snapshot.entity.id
}

editor_reflected_apply_snapshot :: proc(
	state: ^State,
	world: ^shared.World,
	target_index: int,
	before, after: ^ecs.Entity_Snapshot,
) -> bool {
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	if state.editor_simulation_stopped && before.origin == .Scene {
		push_structural_change(state, before.entity.id, before, after)
	} else {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		state.editor_snapshot_valid = false
	}
	if ecs.entity_is_alive(world, target_index) {
		editor_authoring_select(state, world, target_index)
	}
	return true
}

editor_reflected_preview_number :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	number: f32,
) -> bool {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return false
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	changed, valid := editor_reflected_set_field_text(
		&snapshot.value,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
		fmt.tprintf("%.9g", number),
	)
	if !valid || !changed {
		return valid
	}
	if !ecs.apply_registered_component_snapshot(world, target_index, &snapshot) {
		return false
	}
	if ecs.entity_is_alive(world, target_index) {
		editor_mark_scene_dirty(state, &world.entities[target_index])
	}
	return true
}

editor_reflected_finish_number_scrub :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	before_number, after_number: f32,
	cancelled: bool,
) -> bool {
	if cancelled {
		result := editor_reflected_preview_number(state, world, binding, before_number)
		editor_recompute_scene_dirty(state)
		return result
	}
	if before_number == after_number {
		editor_recompute_scene_dirty(state)
		return true
	}
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false
	}
	before := capture_snapshot_pointer(world, target_index)
	after := capture_snapshot_pointer(world, target_index)
	if before == nil || after == nil {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_field_text(
		&before.entity,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
		fmt.tprintf("%.9g", before_number),
	)
	if !valid || !changed {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		editor_recompute_scene_dirty(state)
		return valid
	}
	if state.editor_simulation_stopped && before.origin == .Scene {
		push_structural_change(state, before.entity.id, before, after)
	} else {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		state.editor_snapshot_valid = false
	}
	return true
}

editor_reflected_apply_text :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	text: string,
) -> bool {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false
	}
	before := capture_snapshot_pointer(world, target_index)
	after := capture_snapshot_pointer(world, target_index)
	if before == nil || after == nil {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_field_text(
		&after.entity,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
		text,
	)
	if !valid || !changed {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return valid
	}
	return editor_reflected_apply_snapshot(state, world, target_index, before, after)
}

editor_reflected_apply_bool :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	checked: bool,
) -> bool {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false
	}
	before := capture_snapshot_pointer(world, target_index)
	after := capture_snapshot_pointer(world, target_index)
	if before == nil || after == nil {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_field_bool(
		&after.entity,
		definition,
		binding.reflected_field_index,
		checked,
	)
	if !valid || !changed {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return valid
	}
	return editor_reflected_apply_snapshot(state, world, target_index, before, after)
}

editor_reflected_read_bool :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	bool,
	bool,
) {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return false, false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return false, false
	}
	snapshot, captured := ecs.capture_entity_snapshot(world, target_index)
	if !captured {
		return false, false
	}
	defer ecs.destroy_entity_snapshot(&snapshot)
	return editor_reflected_field_bool(&snapshot.entity, definition, binding.reflected_field_index)
}
