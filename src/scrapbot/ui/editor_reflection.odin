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
		return definition, true
	}
	return nil, false
}

editor_reflected_snapshot_component_value :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
) -> (
	any,
	bool,
) {
	if entity == nil || definition == nil {
		return nil, false
	}
	if definition.storage_kind == .Custom {
		for &custom in entity.custom_components {
			if custom.component_id == definition.id || custom.name == definition.name {
				return any{rawptr(&custom), typeid_of(shared.Custom_Component)}, true
			}
		}
		return nil, false
	}
	switch definition.storage_kind {
		case .Transform:
			if entity.has_transform {
				return any{rawptr(&entity.transform), typeid_of(shared.Transform_Component)}, true
			}
		case .Camera:
			if entity.has_camera {
				return any{rawptr(&entity.camera), typeid_of(shared.Camera_Component)}, true
			}
		case .World_Environment:
			if entity.has_world_environment {
				return any {
						rawptr(&entity.world_environment),
						typeid_of(shared.World_Environment_Component),
					},
					true
			}
		case .Ambient_Light:
			if entity.has_ambient_light {
				return any {
						rawptr(&entity.ambient_light),
						typeid_of(shared.Ambient_Light_Component),
					},
					true
			}
		case .Directional_Light:
			if entity.has_directional_light {
				return any {
						rawptr(&entity.directional_light),
						typeid_of(shared.Directional_Light_Component),
					},
					true
			}
		case .Point_Light:
			if entity.has_point_light {
				return any{rawptr(&entity.point_light), typeid_of(shared.Point_Light_Component)},
					true
			}
		case .Mesh:
			if entity.has_mesh {
				return any{rawptr(&entity.mesh), typeid_of(shared.Mesh_Component)}, true
			}
		case .Geometry:
			if entity.has_geometry {
				return any{rawptr(&entity.geometry), typeid_of(shared.Scene_Geometry_Component)},
					true
			}
		case .Material:
			if entity.has_material {
				return any{rawptr(&entity.material_resource), typeid_of(string)}, true
			}
		case .Model:
			if entity.has_model {
				return any{rawptr(&entity.model), typeid_of(shared.Scene_Model_Component)}, true
			}
		case .Shadow_Caster:
			return nil, entity.has_shadow_caster
		case .Shadow_Receiver:
			return nil, entity.has_shadow_receiver
		case .UI_Layout:
			if entity.has_ui_layout {
				return any{rawptr(&entity.ui_layout), typeid_of(shared.UI_Layout_Component)}, true
			}
		case .UI_Canvas:
			if entity.has_ui_canvas {
				return any{rawptr(&entity.ui_canvas), typeid_of(shared.UI_Canvas_Component)}, true
			}
		case .UI_HStack:
			if entity.has_ui_hstack {
				return any{rawptr(&entity.ui_hstack), typeid_of(shared.UI_Stack_Component)}, true
			}
		case .UI_VStack:
			if entity.has_ui_vstack {
				return any{rawptr(&entity.ui_vstack), typeid_of(shared.UI_Stack_Component)}, true
			}
		case .UI_Scroll_Area:
			if entity.has_ui_scroll_area {
				return any {
						rawptr(&entity.ui_scroll_area),
						typeid_of(shared.UI_Scroll_Area_Component),
					},
					true
			}
		case .UI_Panel:
			if entity.has_ui_panel {
				return any{rawptr(&entity.ui_panel), typeid_of(shared.UI_Panel_Component)}, true
			}
		case .UI_Dock_Space:
			if entity.has_ui_dock_space {
				return any {
						rawptr(&entity.ui_dock_space),
						typeid_of(shared.UI_Dock_Space_Component),
					},
					true
			}
		case .UI_Dock_Item:
			if entity.has_ui_dock_item {
				return any{rawptr(&entity.ui_dock_item), typeid_of(shared.UI_Dock_Item_Component)},
					true
			}
		case .UI_Table:
			if entity.has_ui_table {
				return any{rawptr(&entity.ui_table), typeid_of(shared.UI_Table_Component)}, true
			}
		case .UI_List:
			if entity.has_ui_list {
				return any{rawptr(&entity.ui_list), typeid_of(shared.UI_List_Component)}, true
			}
		case .UI_Progress:
			if entity.has_ui_progress {
				return any{rawptr(&entity.ui_progress), typeid_of(shared.UI_Progress_Component)},
					true
			}
		case .UI_Viewport:
			if entity.has_ui_viewport {
				return any{rawptr(&entity.ui_viewport), typeid_of(shared.UI_Viewport_Component)},
					true
			}
		case .UI_Text:
			if entity.has_ui_text {
				return any{rawptr(&entity.ui_text), typeid_of(shared.UI_Text_Component)}, true
			}
		case .UI_Icon:
			if entity.has_ui_icon {
				return any{rawptr(&entity.ui_icon), typeid_of(shared.UI_Icon_Component)}, true
			}
		case .UI_Button:
			if entity.has_ui_button {
				return any{rawptr(&entity.ui_button), typeid_of(shared.UI_Button_Component)}, true
			}
		case .UI_Input:
			if entity.has_ui_input {
				return any{rawptr(&entity.ui_input), typeid_of(shared.UI_Input_Component)}, true
			}
		case .UI_Checkbox:
			if entity.has_ui_checkbox {
				return any{rawptr(&entity.ui_checkbox), typeid_of(shared.UI_Checkbox_Component)},
					true
			}
		case .UI_Color_Picker:
			if entity.has_ui_color_picker {
				return any {
						rawptr(&entity.ui_color_picker),
						typeid_of(shared.UI_Color_Picker_Component),
					},
					true
			}
		case .UI_Action:
			if entity.has_ui_action {
				return any{rawptr(&entity.ui_action), typeid_of(shared.UI_Action_Component)}, true
			}
		case .UI_State,
		     .Keyboard_Input,
		     .Pointer_Input,
		     .Render_Instance,
		     .Editor_Transform_Gizmo,
		     .Derived,
		     .Custom:
	}
	return nil, false
}

editor_reflected_live_component_value :: proc(
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
) -> (
	any,
	bool,
) {
	if world == nil || definition == nil || !ecs.entity_is_alive(world, entity_index) {
		return nil, false
	}
	entity := &world.entities[entity_index]
	if definition.storage_kind == .Custom {
		custom, found := ecs.custom_component_for_entity_ref(
			world,
			entity_index,
			definition.id,
			definition.name,
		)
		if !found {
			return nil, false
		}
		return any{rawptr(custom), typeid_of(shared.Custom_Component)}, true
	}
	switch definition.storage_kind {
		case .Transform:
			// Transform storage is SoA; authorable inspection uses the captured AoS snapshot.
			return nil, false
		case .Camera:
			return any {
					rawptr(&world.cameras[entity.camera_index]),
					typeid_of(shared.Camera_Component),
				},
				true
		case .World_Environment:
			return any {
					rawptr(&world.world_environments[entity.world_environment_index]),
					typeid_of(shared.World_Environment_Component),
				},
				true
		case .Ambient_Light:
			return any {
					rawptr(&world.ambient_lights[entity.ambient_light_index]),
					typeid_of(shared.Ambient_Light_Component),
				},
				true
		case .Directional_Light:
			return any {
					rawptr(&world.directional_lights[entity.directional_light_index]),
					typeid_of(shared.Directional_Light_Component),
				},
				true
		case .Point_Light:
			return any {
					rawptr(&world.point_lights[entity.point_light_index]),
					typeid_of(shared.Point_Light_Component),
				},
				true
		case .Mesh:
			return any{rawptr(&world.meshes[entity.mesh_index]), typeid_of(shared.Mesh_Component)},
				true
		case .Geometry:
			return any{rawptr(&entity.geometry_resource), typeid_of(string)}, true
		case .Material:
			return any{rawptr(&entity.material_resource), typeid_of(string)}, true
		case .Model:
			return any{rawptr(&entity.model_resource), typeid_of(string)}, true
		case .Shadow_Caster, .Shadow_Receiver:
			return nil, true
		case .UI_Layout:
			return any {
					rawptr(&world.ui_layouts[entity.ui_layout_index]),
					typeid_of(shared.UI_Layout_Component),
				},
				true
		case .UI_Canvas:
			return any {
					rawptr(&world.ui_canvases[entity.ui_canvas_index]),
					typeid_of(shared.UI_Canvas_Component),
				},
				true
		case .UI_HStack:
			return any {
					rawptr(&world.ui_hstacks[entity.ui_hstack_index]),
					typeid_of(shared.UI_Stack_Component),
				},
				true
		case .UI_VStack:
			return any {
					rawptr(&world.ui_vstacks[entity.ui_vstack_index]),
					typeid_of(shared.UI_Stack_Component),
				},
				true
		case .UI_Scroll_Area:
			return any {
					rawptr(&world.ui_scroll_areas[entity.ui_scroll_area_index]),
					typeid_of(shared.UI_Scroll_Area_Component),
				},
				true
		case .UI_Panel:
			return any {
					rawptr(&world.ui_panels[entity.ui_panel_index]),
					typeid_of(shared.UI_Panel_Component),
				},
				true
		case .UI_Dock_Space:
			return any {
					rawptr(&world.ui_dock_spaces[entity.ui_dock_space_index]),
					typeid_of(shared.UI_Dock_Space_Component),
				},
				true
		case .UI_Dock_Item:
			return any {
					rawptr(&world.ui_dock_items[entity.ui_dock_item_index]),
					typeid_of(shared.UI_Dock_Item_Component),
				},
				true
		case .UI_Table:
			return any {
					rawptr(&world.ui_tables[entity.ui_table_index]),
					typeid_of(shared.UI_Table_Component),
				},
				true
		case .UI_List:
			return any {
					rawptr(&world.ui_lists[entity.ui_list_index]),
					typeid_of(shared.UI_List_Component),
				},
				true
		case .UI_Progress:
			return any {
					rawptr(&world.ui_progresses[entity.ui_progress_index]),
					typeid_of(shared.UI_Progress_Component),
				},
				true
		case .UI_Viewport:
			return any {
					rawptr(&world.ui_viewports[entity.ui_viewport_index]),
					typeid_of(shared.UI_Viewport_Component),
				},
				true
		case .UI_State:
			return any {
					rawptr(&world.ui_states[entity.ui_state_index]),
					typeid_of(shared.UI_State_Component),
				},
				true
		case .UI_Text:
			return any {
					rawptr(&world.ui_texts[entity.ui_text_index]),
					typeid_of(shared.UI_Text_Component),
				},
				true
		case .UI_Icon:
			return any {
					rawptr(&world.ui_icons[entity.ui_icon_index]),
					typeid_of(shared.UI_Icon_Component),
				},
				true
		case .UI_Button:
			return any {
					rawptr(&world.ui_buttons[entity.ui_button_index]),
					typeid_of(shared.UI_Button_Component),
				},
				true
		case .UI_Input:
			return any {
					rawptr(&world.ui_inputs[entity.ui_input_index]),
					typeid_of(shared.UI_Input_Component),
				},
				true
		case .UI_Checkbox:
			return any {
					rawptr(&world.ui_checkboxes[entity.ui_checkbox_index]),
					typeid_of(shared.UI_Checkbox_Component),
				},
				true
		case .UI_Color_Picker:
			return any {
					rawptr(&world.ui_color_pickers[entity.ui_color_picker_index]),
					typeid_of(shared.UI_Color_Picker_Component),
				},
				true
		case .UI_Action:
			return any {
					rawptr(&world.ui_actions[entity.ui_action_index]),
					typeid_of(shared.UI_Action_Component),
				},
				true
		case .Render_Instance:
			return any {
					rawptr(&world.render_instances[entity.render_instance_index]),
					typeid_of(shared.Render_Instance_Component),
				},
				true
		case .Editor_Transform_Gizmo:
			return any {
					rawptr(&world.editor_transform_gizmos[entity.editor_transform_gizmo_index]),
					typeid_of(shared.Editor_Transform_Gizmo_Component),
				},
				true
		case .Keyboard_Input, .Pointer_Input, .Derived, .Custom:
	}
	return nil, false
}

editor_reflected_field_count :: proc(value: any, definition: ^component.Definition) -> int {
	if definition == nil {
		return 0
	}
	if definition.storage_kind == .Custom {
		return definition.field_count
	}
	if value == nil {
		return 0
	}
	if value.id == typeid_of(string) {
		return 1
	}
	return reflect.struct_field_count(value.id)
}

editor_reflected_field_definition :: proc(
	value: any,
	definition: ^component.Definition,
	field_index: int,
) -> (
	component.Field_Definition,
	bool,
) {
	if definition == nil || field_index < 0 {
		return {}, false
	}
	if definition.storage_kind == .Custom {
		if field_index >= definition.field_count {
			return {}, false
		}
		return definition.fields[field_index], true
	}
	if value == nil {
		return {}, false
	}
	if value.id == typeid_of(string) {
		if field_index != 0 {
			return {}, false
		}
		return component.Field_Definition{name = "resource", field_type = .String}, true
	}
	field := reflect.struct_field_at(value.id, field_index)
	if field.name == "" {
		return {}, false
	}
	result := component.Field_Definition {
		name = field.name,
		field_type = .String,
	}
	field_value := reflect.struct_field_value(value, field)
	switch field_value.id {
		case typeid_of(bool):
			result.field_type = .Bool
		case typeid_of(f32), typeid_of(int), typeid_of(u32), typeid_of(u64):
			result.field_type = .Number
		case typeid_of(shared.Vec2):
			result.field_type = .Vec2
		case typeid_of(shared.Vec3):
			result.field_type = .Vec3
		case typeid_of(shared.Vec4):
			result.field_type = .Vec4
	}
	for public_field in definition.fields[:definition.field_count] {
		if public_field.name == result.name {
			result.field_type = public_field.field_type
			result.editor = public_field.editor
			break
		}
	}
	return result, true
}

editor_reflected_value_is_writable :: proc(value: any) -> bool {
	if value == nil {
		return false
	}
	if len(reflect.enum_field_names(value.id)) > 0 {
		return true
	}
	switch value.id {
		case typeid_of(bool),
		     typeid_of(f32),
		     typeid_of(int),
		     typeid_of(u32),
		     typeid_of(string),
		     typeid_of(shared.Entity_UUID),
		     typeid_of(shared.Vec2),
		     typeid_of(shared.Vec3),
		     typeid_of(shared.Vec4),
		     typeid_of(shared.UI_Text_Alignment):
			return true
	}
	return false
}

editor_reflected_value_is_enum :: proc(value: any) -> bool {
	return value != nil && len(reflect.enum_field_names(value.id)) > 0
}

editor_reflected_enum_display_name :: proc(value: any) -> (string, bool) {
	if !editor_reflected_value_is_enum(value) {
		return "", false
	}
	if name, found := reflect.enum_name_from_value_any(value); found {
		return name, true
	}
	if raw, found := reflect.as_i64(value); found {
		return fmt.tprintf("<unknown: %d>", raw), false
	}
	return "<unknown>", false
}

editor_reflected_set_enum_value :: proc(value: any, name: string) -> (bool, bool) {
	if !editor_reflected_value_is_enum(value) {
		return false, false
	}
	trimmed := strings.trim_space(name)
	canonical := ""
	for option in reflect.enum_field_names(value.id) {
		if strings.equal_fold(option, trimmed) {
			canonical = option
			break
		}
	}
	if canonical == "" {
		return false, false
	}
	next, found := reflect.enum_from_name_any(value.id, canonical)
	if !found {
		return false, false
	}
	current, current_found := reflect.as_i64(value)
	if !current_found {
		return false, false
	}
	changed := current != i64(next)
	switch type_info_of(value.id).size {
		case 1:
			(cast(^i8)value.data)^ = i8(next)
		case 2:
			(cast(^i16)value.data)^ = i16(next)
		case 4:
			(cast(^i32)value.data)^ = i32(next)
		case 8:
			(cast(^i64)value.data)^ = i64(next)
		case:
			return false, false
	}
	return changed, true
}

editor_reflected_field_value :: proc(
	component_value: any,
	definition: ^component.Definition,
	field_index: int,
) -> (
	any,
	bool,
) {
	if definition == nil || field_index < 0 {
		return nil, false
	}
	field, described := editor_reflected_field_definition(component_value, definition, field_index)
	if !described {
		return nil, false
	}
	if definition.storage_kind == .Custom {
		if component_value == nil || component_value.id != typeid_of(shared.Custom_Component) {
			return nil, false
		}
		custom := cast(^shared.Custom_Component)component_value.data
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
		return nil, false
	}
	if component_value != nil && component_value.id == typeid_of(string) {
		return component_value, field_index == 0
	}
	field_value := reflect.struct_field_value_by_name(component_value, field.name)
	return field_value, field_value != nil
}

editor_reflected_container_count :: proc(value: any) -> (int, bool) {
	if value == nil {
		return 0, false
	}
	if count := reflect.struct_field_count(value.id); count > 0 {
		return count, true
	}
	info := reflect.type_info_base(type_info_of(value.id))
	#partial switch container in info.variant {
		case reflect.Type_Info_Array:
			return container.count, true
	}
	return 0, false
}

editor_reflected_container_child :: proc(value: any, index: int) -> (any, bool) {
	if value == nil || index < 0 {
		return nil, false
	}
	if count := reflect.struct_field_count(value.id); count > 0 {
		if index >= count {
			return nil, false
		}
		field := reflect.struct_field_at(value.id, index)
		child := reflect.struct_field_value(value, field)
		return child, child != nil
	}
	iterator := 0
	for child, child_index in reflect.iterate_array(value, &iterator) {
		if child_index == index {
			return child, true
		}
	}
	return nil, false
}

editor_reflected_container_child_name :: proc(value: any, index: int) -> (string, bool) {
	if value == nil || index < 0 {
		return "", false
	}
	if count := reflect.struct_field_count(value.id); count > 0 {
		if index >= count {
			return "", false
		}
		field := reflect.struct_field_at(value.id, index)
		return field.name, field.name != ""
	}
	if count, found := editor_reflected_container_count(value); found && index < count {
		return fmt.tprintf("[%d]", index), true
	}
	return "", false
}

editor_reflected_nested_value :: proc(value: any, path: [8]int, path_count: int) -> (any, bool) {
	if value == nil || path_count < 0 || path_count > len(path) {
		return nil, false
	}
	path_value := path
	current := value
	for index in path_value[:path_count] {
		next, found := editor_reflected_container_child(current, index)
		if !found {
			return nil, false
		}
		current = next
	}
	return current, true
}

editor_reflected_binding_value :: proc(
	component_value: any,
	definition: ^component.Definition,
	binding: shared.Editor_UI_Component,
) -> (
	any,
	bool,
) {
	value, found := editor_reflected_field_value(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !found {
		return nil, false
	}
	return editor_reflected_nested_value(
		value,
		binding.reflected_path,
		binding.reflected_path_count,
	)
}

editor_reflected_value_field_type :: proc(value: any) -> (component.Field_Type, bool) {
	if value == nil {
		return .String, false
	}
	if editor_reflected_value_is_enum(value) {
		return .String, true
	}
	switch value.id {
		case typeid_of(bool):
			return .Bool, true
		case typeid_of(f32), typeid_of(int), typeid_of(u32), typeid_of(u64):
			return .Number, true
		case typeid_of(string),
		     typeid_of(shared.Entity_UUID),
		     typeid_of(shared.Resource_UUID),
		     typeid_of(shared.UI_Text_Alignment):
			return .String, true
		case typeid_of(shared.Vec2):
			return .Vec2, true
		case typeid_of(shared.Vec3):
			return .Vec3, true
		case typeid_of(shared.Vec4):
			return .Vec4, true
	}
	return .String, false
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
	if value.id == typeid_of(u32) {
		return f32((cast(^u32)value.data)^), axis == .None
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
	component_value: any,
	definition: ^component.Definition,
	field_index: int,
	uuid_buffer: []u8,
	values: ^[4]string,
) -> (
	int,
	bool,
) {
	field_value, found := editor_reflected_field_value(component_value, definition, field_index)
	if !found {
		return 0, false
	}
	field, described := editor_reflected_field_definition(component_value, definition, field_index)
	if !described {
		return 0, false
	}
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
			if name, ok := reflect.enum_name_from_value_any(field_value); ok {
				values[0] = name
				return 1, true
			}
			values[0] = fmt.tprintf("%v", field_value)
			return 1, true
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

editor_reflected_value_texts :: proc(
	value: any,
	field_type: component.Field_Type,
	uuid_buffer: []u8,
	values: ^[4]string,
) -> (
	int,
	bool,
) {
	if value == nil || values == nil {
		return 0, false
	}
	if editor_reflected_value_is_enum(value) {
		name, found := editor_reflected_enum_display_name(value)
		values[0] = name
		return 1, found
	}
	switch field_type {
		case .Bool:
			if value.id == typeid_of(bool) {
				values[0] = fmt.tprintf("%v", (cast(^bool)value.data)^)
				return 1, true
			}
		case .Number:
			if value.id == typeid_of(u64) {
				values[0] = fmt.tprintf("%d", (cast(^u64)value.data)^)
				return 1, true
			}
			if value.id == typeid_of(u32) {
				values[0] = fmt.tprintf("%d", (cast(^u32)value.data)^)
				return 1, true
			}
			if value.id == typeid_of(int) {
				values[0] = fmt.tprintf("%d", (cast(^int)value.data)^)
				return 1, true
			}
			if number, found := editor_reflected_axis_number(value, .None); found {
				values[0] = fmt.tprintf("%.2f", number)
				return 1, true
			}
		case .String:
			if value.id == typeid_of(string) {
				values[0] = (cast(^string)value.data)^
				return 1, true
			}
			if value.id == typeid_of(shared.Entity_UUID) {
				id := (cast(^shared.Entity_UUID)value.data)^
				values[0] = "none"
				if id != (shared.Entity_UUID{}) {
					values[0] = shared.entity_uuid_to_string(id, uuid_buffer)
				}
				return 1, true
			}
			if value.id == typeid_of(shared.Resource_UUID) {
				id := (cast(^shared.Resource_UUID)value.data)^
				values[0] = "none"
				if id != (shared.Resource_UUID{}) {
					values[0] = shared.resource_uuid_to_string(id, uuid_buffer)
				}
				return 1, true
			}
			values[0] = fmt.tprintf("%v", value)
			return 1, true
		case .Vec2, .Vec3, .Vec4, .Color:
			axes := [4]shared.Editor_Inspector_Axis{.X, .Y, .Z, .W}
			count := 2
			if field_type == .Vec3 {
				count = 3
			} else if field_type == .Vec4 || field_type == .Color {
				count = 4
			}
			for axis, index in axes[:count] {
				number, found := editor_reflected_axis_number(value, axis)
				if !found {
					return 0, false
				}
				values[index] = fmt.tprintf("%.2f", number)
			}
			return count, true
	}
	return 0, false
}

editor_reflected_field_bool :: proc(
	component_value: any,
	definition: ^component.Definition,
	field_index: int,
) -> (
	bool,
	bool,
) {
	value, found := editor_reflected_field_value(component_value, definition, field_index)
	if !found || value.id != typeid_of(bool) {
		return false, false
	}
	return (cast(^bool)value.data)^, true
}

editor_component_definition_by_id :: proc(
	state: ^State,
	before, after: ^ecs.Registered_Component_Snapshot,
) -> ^component.Definition {
	if state == nil || state.component_registry == nil {
		return nil
	}
	id := shared.INVALID_COMPONENT_ID
	name := ""
	if before != nil {
		id = before.component_id
		name = before.name
	} else if after != nil {
		id = after.component_id
		name = after.name
	}
	for index in 0 ..< state.component_registry.definition_count {
		definition := &state.component_registry.definitions[index]
		if definition.id == id || (name != "" && definition.name == name) {
			return definition
		}
	}
	return nil
}

editor_reflected_values_equal :: proc(a, b: any) -> bool {
	if a == nil || b == nil || a.id != b.id {
		return false
	}
	switch a.id {
		case typeid_of(bool):
			return (cast(^bool)a.data)^ == (cast(^bool)b.data)^
		case typeid_of(f32):
			return (cast(^f32)a.data)^ == (cast(^f32)b.data)^
		case typeid_of(int):
			return (cast(^int)a.data)^ == (cast(^int)b.data)^
		case typeid_of(u64):
			return (cast(^u64)a.data)^ == (cast(^u64)b.data)^
		case typeid_of(string):
			return (cast(^string)a.data)^ == (cast(^string)b.data)^
		case typeid_of(shared.Entity_UUID):
			return (cast(^shared.Entity_UUID)a.data)^ == (cast(^shared.Entity_UUID)b.data)^
		case typeid_of(shared.Vec2):
			return (cast(^shared.Vec2)a.data)^ == (cast(^shared.Vec2)b.data)^
		case typeid_of(shared.Vec3):
			return (cast(^shared.Vec3)a.data)^ == (cast(^shared.Vec3)b.data)^
		case typeid_of(shared.Vec4):
			return (cast(^shared.Vec4)a.data)^ == (cast(^shared.Vec4)b.data)^
		case typeid_of(shared.UI_Text_Alignment):
			return(
				(cast(^shared.UI_Text_Alignment)a.data)^ ==
				(cast(^shared.UI_Text_Alignment)b.data)^ \
			)
	}
	return fmt.tprintf("%v", a) == fmt.tprintf("%v", b)
}

editor_registered_component_snapshots_equal :: proc(
	a, b: ^ecs.Registered_Component_Snapshot,
	definition: ^component.Definition,
) -> bool {
	if a == nil || b == nil || definition == nil {
		return false
	}
	if a.component_id != b.component_id ||
	   a.storage_kind != b.storage_kind ||
	   a.present != b.present {
		return false
	}
	if !a.present {
		return true
	}
	a_value, a_found := editor_reflected_snapshot_component_value(&a.value, definition)
	b_value, b_found := editor_reflected_snapshot_component_value(&b.value, definition)
	if !a_found || !b_found {
		return false
	}
	field_count := editor_reflected_field_count(a_value, definition)
	if field_count != editor_reflected_field_count(b_value, definition) {
		return false
	}
	for field_index in 0 ..< field_count {
		a_field, a_ok := editor_reflected_field_value(a_value, definition, field_index)
		b_field, b_ok := editor_reflected_field_value(b_value, definition, field_index)
		if !a_ok || !b_ok || !editor_reflected_values_equal(a_field, b_field) {
			return false
		}
	}
	return true
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
	if value.id == typeid_of(u32) && axis == .None {
		integer := u32(number)
		if number < 0 || f32(integer) != number {
			return false, false
		}
		pointer := cast(^u32)value.data
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
	if editor_reflected_value_is_enum(value) {
		return editor_reflected_set_enum_value(value, text)
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
			resolution_scale := entity.camera.resolution_scale
			if resolution_scale == 0 {
				resolution_scale = 1
			}
			dynamic_resolution_min_scale := entity.camera.dynamic_resolution_min_scale
			if dynamic_resolution_min_scale == 0 {
				dynamic_resolution_min_scale = 0.5
			}
			dynamic_resolution_target_ms := entity.camera.dynamic_resolution_target_ms
			if dynamic_resolution_target_ms == 0 {
				dynamic_resolution_target_ms = 16.667
			}
			adaptive_quality_minimum := entity.camera.adaptive_quality_minimum
			if adaptive_quality_minimum == 0 {
				adaptive_quality_minimum = 0.25
			}
			exposure := shared.camera_exposure(entity.camera)
			automatic_exposure_min := shared.camera_automatic_exposure_min(entity.camera)
			automatic_exposure_max := shared.camera_automatic_exposure_max(entity.camera)
			automatic_exposure_speed := shared.camera_automatic_exposure_speed(entity.camera)
			return(
				entity.camera.fov >= 1 &&
				entity.camera.fov <= 179 &&
				entity.camera.near > 0 &&
				entity.camera.far > entity.camera.near &&
				!math.is_nan(resolution_scale) &&
				!math.is_inf(resolution_scale) &&
				resolution_scale >= 0.5 &&
				resolution_scale <= 1 &&
				!math.is_nan(dynamic_resolution_min_scale) &&
				!math.is_inf(dynamic_resolution_min_scale) &&
				dynamic_resolution_min_scale >= 0.5 &&
				dynamic_resolution_min_scale <= resolution_scale &&
				!math.is_nan(dynamic_resolution_target_ms) &&
				!math.is_inf(dynamic_resolution_target_ms) &&
				dynamic_resolution_target_ms >= 1 &&
				dynamic_resolution_target_ms <= 100 &&
				!math.is_nan(adaptive_quality_minimum) &&
				!math.is_inf(adaptive_quality_minimum) &&
				adaptive_quality_minimum >= 0.25 &&
				adaptive_quality_minimum <= 1 &&
				!math.is_nan(exposure) &&
				!math.is_inf(exposure) &&
				exposure > 0 &&
				!math.is_nan(automatic_exposure_min) &&
				!math.is_inf(automatic_exposure_min) &&
				automatic_exposure_min > 0 &&
				!math.is_nan(automatic_exposure_max) &&
				!math.is_inf(automatic_exposure_max) &&
				automatic_exposure_max >= automatic_exposure_min &&
				!math.is_nan(automatic_exposure_speed) &&
				!math.is_inf(automatic_exposure_speed) &&
				automatic_exposure_speed > 0 \
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
		case "scrapbot.world_environment":
			lighting_valid := entity.world_environment.lighting == ""
			if !lighting_valid {
				_, lighting_valid = shared.resource_uuid_parse(entity.world_environment.lighting)
			}
			background_valid := entity.world_environment.background == ""
			if !background_valid {
				_, background_valid = shared.resource_uuid_parse(
					entity.world_environment.background,
				)
			}
			return(
				lighting_valid &&
				background_valid &&
				shared.world_environment_is_valid(entity.world_environment) \
			)
		case "scrapbot.mesh":
			return entity.mesh.primitive != ""
		case "scrapbot.geometry":
			return entity.geometry.resource != ""
		case "scrapbot.material":
			return entity.material_resource != ""
		case "scrapbot.model":
			return entity.model.resource != ""
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
		case "scrapbot.ui_viewport":
			return shared.ui_viewport_is_valid(entity.ui_viewport)
		case "scrapbot.ui_text":
			return shared.ui_text_is_valid(entity.ui_text)
		case "scrapbot.ui_button":
			return shared.ui_button_is_valid(entity.ui_button)
		case "scrapbot.ui_input":
			return shared.ui_input_is_valid(entity.ui_input)
		case "scrapbot.ui_checkbox":
			return shared.ui_checkbox_is_valid(entity.ui_checkbox)
		case "scrapbot.ui_color_picker":
			return shared.ui_color_picker_is_valid(entity.ui_color_picker)
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
	component_value, component_found := editor_reflected_snapshot_component_value(
		entity,
		definition,
	)
	if !component_found {
		return false, false
	}
	field_value, found := editor_reflected_field_value(component_value, definition, field_index)
	if !found {
		return false, false
	}
	field, described := editor_reflected_field_definition(component_value, definition, field_index)
	if !described {
		return false, false
	}
	changed, parsed := false, false
	if editor_reflected_value_is_enum(field_value) {
		changed, parsed = editor_reflected_set_enum_value(field_value, text)
	} else {
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
	component_value, component_found := editor_reflected_snapshot_component_value(
		entity,
		definition,
	)
	if !component_found {
		return false, false
	}
	field_value, found := editor_reflected_field_value(component_value, definition, field_index)
	if !found || field_value.id != typeid_of(bool) {
		return false, false
	}
	pointer := cast(^bool)field_value.data
	changed := pointer^ != checked
	pointer^ = checked
	field, described := editor_reflected_field_definition(component_value, definition, field_index)
	if !described {
		return false, false
	}
	editor_reflected_normalize(entity, definition.name, field.name)
	return changed, editor_reflected_component_valid(entity, definition.name)
}

editor_reflected_set_binding_text :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	binding: shared.Editor_UI_Component,
	text: string,
) -> (
	bool,
	bool,
) {
	if binding.reflected_path_count == 0 {
		return editor_reflected_set_field_text(
			entity,
			definition,
			binding.reflected_field_index,
			binding.inspector_axis,
			text,
		)
	}
	component_value, component_found := editor_reflected_snapshot_component_value(
		entity,
		definition,
	)
	if !component_found {
		return false, false
	}
	value, found := editor_reflected_binding_value(component_value, definition, binding)
	if !found {
		return false, false
	}
	field_type, described := editor_reflected_value_field_type(value)
	if !described {
		return false, false
	}
	changed, parsed := false, false
	if editor_reflected_value_is_enum(value) {
		changed, parsed = editor_reflected_set_enum_value(value, text)
	} else {
		switch field_type {
			case .Number, .Vec2, .Vec3, .Vec4, .Color:
				number, ok := strconv.parse_f32(strings.trim_space(text))
				if !ok {
					return false, false
				}
				changed, parsed = editor_reflected_set_number(
					value,
					binding.inspector_axis,
					number,
				)
			case .String:
				changed, parsed = editor_reflected_set_text_value(value, text)
			case .Bool:
				return false, false
		}
	}
	if !parsed {
		return false, false
	}
	top_field, top_found := editor_reflected_field_definition(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !top_found {
		return false, false
	}
	editor_reflected_normalize(entity, definition.name, top_field.name)
	return changed, editor_reflected_component_valid(entity, definition.name)
}

editor_reflected_set_binding_bool :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	binding: shared.Editor_UI_Component,
	checked: bool,
) -> (
	bool,
	bool,
) {
	if binding.reflected_path_count == 0 {
		return editor_reflected_set_field_bool(
			entity,
			definition,
			binding.reflected_field_index,
			checked,
		)
	}
	component_value, component_found := editor_reflected_snapshot_component_value(
		entity,
		definition,
	)
	if !component_found {
		return false, false
	}
	value, found := editor_reflected_binding_value(component_value, definition, binding)
	if !found || value.id != typeid_of(bool) {
		return false, false
	}
	pointer := cast(^bool)value.data
	changed := pointer^ != checked
	pointer^ = checked
	top_field, top_found := editor_reflected_field_definition(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !top_found {
		return false, false
	}
	editor_reflected_normalize(entity, definition.name, top_field.name)
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
	_, valid := editor_reflected_set_binding_text(&snapshot.entity, definition, binding, text)
	return valid && target.uuid == snapshot.entity.id
}

editor_reflected_apply_component_snapshot :: proc(
	state: ^State,
	world: ^shared.World,
	target_index: int,
	before, after: ^ecs.Registered_Component_Snapshot,
) -> bool {
	if !ecs.entity_is_alive(world, target_index) {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	target := &world.entities[target_index]
	target_uuid := target.uuid
	target_origin := target.origin
	if !ecs.apply_registered_component_snapshot(world, target_index, after) {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	if state.editor_simulation_stopped && target_origin == .Scene {
		push_component_structural_change(state, target_uuid, before, after)
	} else {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
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
	changed, valid := editor_reflected_set_binding_text(
		&snapshot.value,
		definition,
		binding,
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
	before := capture_component_snapshot_pointer(world, target_index, definition)
	after := capture_component_snapshot_pointer(world, target_index, definition)
	if before == nil || after == nil {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_binding_text(
		&before.value,
		definition,
		binding,
		fmt.tprintf("%.9g", before_number),
	)
	if !valid || !changed {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		editor_recompute_scene_dirty(state)
		return valid
	}
	if state.editor_simulation_stopped && world.entities[target_index].origin == .Scene {
		push_component_structural_change(state, world.entities[target_index].uuid, before, after)
	} else {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
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
	before := capture_component_snapshot_pointer(world, target_index, definition)
	after := capture_component_snapshot_pointer(world, target_index, definition)
	if before == nil || after == nil {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_binding_text(&after.value, definition, binding, text)
	if !valid || !changed {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return valid
	}
	return editor_reflected_apply_component_snapshot(state, world, target_index, before, after)
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
	before := capture_component_snapshot_pointer(world, target_index, definition)
	after := capture_component_snapshot_pointer(world, target_index, definition)
	if before == nil || after == nil {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_binding_bool(&after.value, definition, binding, checked)
	if !valid || !changed {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return valid
	}
	return editor_reflected_apply_component_snapshot(state, world, target_index, before, after)
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
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.entity,
		definition,
	)
	if !component_found {
		return false, false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found || field_value.id != typeid_of(bool) {
		return false, false
	}
	return (cast(^bool)field_value.data)^, true
}

editor_reflected_enum_option_name :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	option_index: int,
) -> (
	string,
	bool,
) {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return "", false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return "", false
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return "", false
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return "", false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found || !editor_reflected_value_is_enum(field_value) {
		return "", false
	}
	names := reflect.enum_field_names(field_value.id)
	if option_index < 0 || option_index >= len(names) {
		return "", false
	}
	return names[option_index], true
}

editor_reflected_read_number :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	f32,
	bool,
) {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return 0, false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return 0, false
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return 0, false
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return 0, false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found {
		return 0, false
	}
	return editor_reflected_axis_number(field_value, binding.inspector_axis)
}

editor_reflected_entity_reference :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	shared.Entity_UUID,
	bool,
) {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return {}, false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return {}, false
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return {}, false
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return {}, false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found || field_value.id != typeid_of(shared.Entity_UUID) {
		return {}, false
	}
	return (cast(^shared.Entity_UUID)field_value.data)^, true
}

editor_reflected_set_snapshot_entity_reference :: proc(
	snapshot: ^ecs.Registered_Component_Snapshot,
	definition: ^component.Definition,
	binding: shared.Editor_UI_Component,
	value: shared.Entity_UUID,
) -> bool {
	if snapshot == nil || definition == nil {
		return false
	}
	component_value, found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !found {
		return false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found || field_value.id != typeid_of(shared.Entity_UUID) {
		return false
	}
	(cast(^shared.Entity_UUID)field_value.data)^ = value
	field, described := editor_reflected_field_definition(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !described {
		return false
	}
	editor_reflected_normalize(&snapshot.value, definition.name, field.name)
	return editor_reflected_component_valid(&snapshot.value, definition.name)
}

editor_reflected_ui_parent_candidate_valid :: proc(
	world: ^shared.World,
	target_index, candidate_index: int,
) -> bool {
	if !ecs.entity_is_alive(world, target_index) ||
	   !ecs.entity_is_alive(world, candidate_index) ||
	   target_index == candidate_index {
		return false
	}
	target := world.entities[target_index]
	candidate := world.entities[candidate_index]
	if target.origin != candidate.origin ||
	   candidate.ui_layout_index < 0 ||
	   candidate.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	cursor := candidate_index
	for _ in 0 ..< len(world.entities) {
		if cursor == target_index {
			return false
		}
		layout_index := world.entities[cursor].ui_layout_index
		if layout_index < 0 || layout_index >= len(world.ui_layouts) {
			return false
		}
		parent := world.ui_layouts[layout_index].parent
		if parent == (shared.Entity_UUID{}) {
			return true
		}
		next, found := ecs.entity_index_by_uuid(world, parent)
		if !found || world.entities[next].origin != target.origin {
			return false
		}
		cursor = next
	}
	return false
}

editor_reflected_tree_parent_candidate_valid :: proc(
	world: ^shared.World,
	target_index, candidate_index: int,
) -> bool {
	if !ecs.entity_is_alive(world, target_index) ||
	   !ecs.entity_is_alive(world, candidate_index) ||
	   target_index == candidate_index {
		return false
	}
	target := world.entities[target_index]
	candidate := world.entities[candidate_index]
	if target.origin != candidate.origin ||
	   target.ui_layout_index < 0 ||
	   target.ui_layout_index >= len(world.ui_layouts) ||
	   candidate.ui_layout_index < 0 ||
	   candidate.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	target_layout := world.ui_layouts[target.ui_layout_index]
	candidate_layout := world.ui_layouts[candidate.ui_layout_index]
	if !target_layout.tree_item ||
	   !candidate_layout.tree_item ||
	   target_layout.parent != candidate_layout.parent {
		return false
	}
	cursor := candidate_index
	for _ in 0 ..< len(world.entities) {
		if cursor == target_index {
			return false
		}
		layout := world.ui_layouts[world.entities[cursor].ui_layout_index]
		if layout.tree_parent == (shared.Entity_UUID{}) {
			return true
		}
		next, found := ecs.entity_index_by_uuid(world, layout.tree_parent)
		if !found {
			return false
		}
		cursor = next
	}
	return false
}

editor_reflected_entity_reference_candidate_valid :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	candidate: shared.Entity_UUID,
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
	if !editor_reflected_set_snapshot_entity_reference(&snapshot, definition, binding, candidate) {
		return false
	}
	if candidate == (shared.Entity_UUID{}) {
		return true
	}
	candidate_index, candidate_found := ecs.entity_index_by_uuid(world, candidate)
	if !candidate_found || world.entities[candidate_index].origin == .Editor {
		return false
	}
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return false
	}
	field, field_found := editor_reflected_field_definition(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !field_found {
		return false
	}
	target := world.entities[target_index]
	candidate_entity := world.entities[candidate_index]
	#partial switch definition.storage_kind {
		case .Transform:
			return(
				field.name != "parent" ||
				ecs.transform_parent_is_valid(world, target_index, candidate) \
			)
		case .UI_Layout:
			switch field.name {
				case "parent":
					return editor_reflected_ui_parent_candidate_valid(
						world,
						target_index,
						candidate_index,
					)
				case "popup_anchor":
					return(
						target.origin == candidate_entity.origin &&
						candidate_entity.ui_layout_index >= 0 &&
						target_index != candidate_index \
					)
				case "tree_parent":
					return editor_reflected_tree_parent_candidate_valid(
						world,
						target_index,
						candidate_index,
					)
			}
		case .UI_List:
			switch field.name {
				case "selected":
					return(
						candidate_entity.ui_layout_index >= 0 &&
						world.ui_layouts[candidate_entity.ui_layout_index].parent == target.uuid \
					)
				case "filter_input":
					return(
						target.origin == candidate_entity.origin &&
						candidate_entity.ui_input_index >= 0 \
					)
			}
		case .UI_Viewport:
			switch field.name {
				case "camera":
					return candidate_entity.camera_index >= 0
				case "root":
					return target.origin == candidate_entity.origin
			}
		case .UI_Button:
			if field.name == "popup" {
				return(
					target.origin == candidate_entity.origin &&
					candidate_entity.ui_layout_index >= 0 &&
					world.ui_layouts[candidate_entity.ui_layout_index].popup \
				)
			}
		case:
	}
	return target.origin == candidate_entity.origin
}

editor_reflected_apply_entity_reference :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	value: shared.Entity_UUID,
) -> bool {
	if !editor_reflected_entity_reference_candidate_valid(state, world, binding, value) {
		return false
	}
	text := "none"
	buffer: [36]u8
	if value != (shared.Entity_UUID{}) {
		text = shared.entity_uuid_to_string(value, buffer[:])
	}
	return editor_reflected_apply_text(state, world, binding, text)
}

editor_color_component :: proc "contextless" (value: shared.Vec4, index: int) -> f32 {
	switch index {
		case 0:
			return value.x
		case 1:
			return value.y
		case 2:
			return value.z
		case:
			return value.w
	}
}

editor_color_set_component :: proc(value: ^shared.Vec4, index: int, number: f32) {
	if value == nil {
		return
	}
	switch index {
		case 0:
			value.x = number
		case 1:
			value.y = number
		case 2:
			value.z = number
		case 3:
			value.w = number
	}
}

editor_reflected_read_color :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	shared.Vec4,
	int,
	bool,
) {
	definition, found := editor_reflected_definition(state, binding)
	if !found {
		return {}, 0, false
	}
	_, target_index, target_ok := inspector_target(world, binding)
	if !target_ok {
		return {}, 0, false
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return {}, 0, false
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return {}, 0, false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found {
		return {}, 0, false
	}
	result := shared.Vec4{0, 0, 0, 1}
	axes := [4]shared.Editor_Inspector_Axis{.X, .Y, .Z, .W}
	count := 0
	for axis, index in axes {
		number, available := editor_reflected_axis_number(field_value, axis)
		if !available {
			break
		}
		editor_color_set_component(&result, index, number)
		count += 1
	}
	return result, count, count == 3 || count == 4
}

editor_reflected_set_snapshot_color :: proc(
	snapshot: ^ecs.Registered_Component_Snapshot,
	definition: ^component.Definition,
	binding: shared.Editor_UI_Component,
	value: shared.Vec4,
	component_count: int,
) -> bool {
	if snapshot == nil || definition == nil || component_count < 3 || component_count > 4 {
		return false
	}
	component_value, found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !found {
		return false
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found {
		return false
	}
	axes := [4]shared.Editor_Inspector_Axis{.X, .Y, .Z, .W}
	for axis, index in axes[:component_count] {
		_, parsed := editor_reflected_set_number(
			field_value,
			axis,
			editor_color_component(value, index),
		)
		if !parsed {
			return false
		}
	}
	return true
}

editor_reflected_preview_color :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	value: shared.Vec4,
	component_count: int,
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
	if !editor_reflected_set_snapshot_color(
		&snapshot,
		definition,
		binding,
		value,
		component_count,
	) {
		return false
	}
	if !ecs.apply_registered_component_snapshot(world, target_index, &snapshot) {
		return false
	}
	if ecs.entity_is_alive(world, target_index) {
		editor_mark_scene_dirty(state, &world.entities[target_index])
	}
	return true
}

editor_reflected_finish_color :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	before_value, after_value: shared.Vec4,
	component_count: int,
) -> bool {
	if before_value == after_value {
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
	before := capture_component_snapshot_pointer(world, target_index, definition)
	after := capture_component_snapshot_pointer(world, target_index, definition)
	if before == nil || after == nil {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	if !editor_reflected_set_snapshot_color(
		before,
		definition,
		binding,
		before_value,
		component_count,
	) {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	if state.editor_simulation_stopped && world.entities[target_index].origin == .Scene {
		push_component_structural_change(state, world.entities[target_index].uuid, before, after)
	} else {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		state.editor_snapshot_valid = false
	}
	return true
}
