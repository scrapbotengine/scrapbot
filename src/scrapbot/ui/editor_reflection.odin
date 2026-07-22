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
				return any{rawptr(&entity.geometry_resource), typeid_of(string)}, true
			}
		case .Material:
			if entity.has_material {
				return any{rawptr(&entity.material_resource), typeid_of(string)}, true
			}
		case .Model:
			if entity.has_model {
				return any{rawptr(&entity.model_resource), typeid_of(string)}, true
			}
		case .Shadow_Caster:
			return nil, entity.has_shadow_caster
		case .Shadow_Receiver:
			return nil, entity.has_shadow_receiver
		case .UI_Layout:
			if entity.has_ui_layout {
				return any{rawptr(&entity.ui_layout), typeid_of(shared.UI_Layout_Component)}, true
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
		case typeid_of(f32), typeid_of(int), typeid_of(u64):
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
	switch value.id {
		case typeid_of(bool),
		     typeid_of(f32),
		     typeid_of(int),
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
			exposure := shared.camera_exposure(entity.camera)
			return(
				entity.camera.fov >= 1 &&
				entity.camera.fov <= 179 &&
				entity.camera.near > 0 &&
				entity.camera.far > entity.camera.near &&
				!math.is_nan(exposure) &&
				!math.is_inf(exposure) &&
				exposure > 0 \
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
		case "scrapbot.model":
			return entity.model_resource != ""
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
	before := capture_component_snapshot_pointer(world, target_index, definition)
	after := capture_component_snapshot_pointer(world, target_index, definition)
	if before == nil || after == nil {
		destroy_component_snapshot_pointer(before)
		destroy_component_snapshot_pointer(after)
		return false
	}
	changed, valid := editor_reflected_set_field_text(
		&before.value,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
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
	changed, valid := editor_reflected_set_field_text(
		&after.value,
		definition,
		binding.reflected_field_index,
		binding.inspector_axis,
		text,
	)
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
	changed, valid := editor_reflected_set_field_bool(
		&after.value,
		definition,
		binding.reflected_field_index,
		checked,
	)
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
	return editor_reflected_field_bool(component_value, definition, binding.reflected_field_index)
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
	field_value, field_found := editor_reflected_field_value(
		component_value,
		definition,
		binding.reflected_field_index,
	)
	if !field_found {
		return 0, false
	}
	return editor_reflected_axis_number(field_value, binding.inspector_axis)
}
