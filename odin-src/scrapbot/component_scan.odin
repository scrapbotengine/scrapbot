package main

import "core:os"
import "core:strings"

register_script_components_from_file :: proc(registry: ^Runtime_Component_Registry, path: string) -> Project_Error {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return .Missing_Script
	}
	defer delete(contents)

	remaining := string(contents)
	for {
		component_index := strings.index(remaining, "ecs.component")
		if component_index < 0 {
			break
		}
		fragment := remaining[component_index:]
		open_index := strings.index_byte(fragment, '(')
		if open_index < 0 {
			return .Invalid_Script
		}
		after_open := strings.trim_space(fragment[open_index + 1:])
		component_id, id_len, id_ok := parse_quoted_prefix(after_open)
		if !id_ok {
			remaining = fragment[len("ecs.component"):]
			continue
		}
		if runtime_is_engine_type_id(component_id) {
			remaining = after_open[id_len:]
			continue
		}

		after_id := after_open[id_len:]
		fields_call_index := strings.index(after_id, "ecs.fields({")
		next_component_index := strings.index(after_id, "ecs.component")
		fields: []Runtime_Component_Field_Definition
		fields_owned := false
		next_remaining := after_id
		if fields_call_index >= 0 && (next_component_index < 0 || fields_call_index < next_component_index) {
			fields_fragment := after_id[fields_call_index + len("ecs.fields({"):]
			fields_end := strings.index(fields_fragment, "})")
			if fields_end < 0 {
				return .Invalid_Script
			}
			fields_ok: bool
			fields, fields_ok = parse_script_field_definitions(fields_fragment[:fields_end])
			if !fields_ok {
				return .Invalid_Script
			}
			fields_owned = true
			next_remaining = fields_fragment[fields_end + len("})"):]
		} else {
			fields = nil
		}

		err := runtime_register_project_component(registry, Runtime_Component_Definition{
			id = component_id,
			version = 1,
			fields = fields,
		})
		if fields_owned && fields != nil {
			delete(fields)
		}
		if err != .None {
			return .Invalid_Script
		}
		remaining = next_remaining
	}
	return .None
}

register_native_components_from_file :: proc(registry: ^Runtime_Component_Registry, path: string) -> Project_Error {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return .Missing_Native
	}
	defer delete(contents)

	remaining := string(contents)
	for {
		call_index := strings.index(remaining, "scrapbot.registerComponent")
		if call_index < 0 {
			break
		}
		fragment := remaining[call_index:]
		block_start := strings.index(fragment, ".{")
		if block_start < 0 {
			return .Invalid_Native
		}
		block_end := strings.index(fragment[block_start:], "})")
		if block_end < 0 {
			return .Invalid_Native
		}
		block := fragment[block_start:block_start + block_end]
		component_id, id_ok := parse_native_component_id(block)
		if !id_ok {
			return .Invalid_Native
		}
		field_array_name, fields_ref_ok := parse_native_component_fields_reference(block)
		if !fields_ref_ok {
			field_array_name = ""
		}
		fields: []Runtime_Component_Field_Definition
		fields_owned := false
		fields_ok := true
		if field_array_name == "" {
			fields = nil
		} else {
			fields, fields_ok = parse_native_field_array(string(contents), field_array_name)
			fields_owned = true
		}
		if !fields_ok {
			return .Invalid_Native
		}

		err := runtime_register_project_component(registry, Runtime_Component_Definition{
			id = component_id,
			version = 1,
			fields = fields,
		})
		if fields_owned && fields != nil {
			delete(fields)
		}
		if err != .None {
			return .Invalid_Native
		}
		remaining = fragment[block_start + block_end + len("})"):]
	}
	return .None
}

parse_script_field_definitions :: proc(body: string) -> ([]Runtime_Component_Field_Definition, bool) {
	fields := make([dynamic]Runtime_Component_Field_Definition)
	remaining := body
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if strings.has_suffix(trimmed, ",") {
			trimmed = strings.trim_space(trimmed[:len(trimmed) - 1])
		}
		name, value, ok := read_key_value_parts(trimmed)
		if !ok {
			delete(fields)
			return nil, false
		}
		field_type_text, type_ok := parse_basic_string(value)
		if !type_ok {
			delete(fields)
			return nil, false
		}
		field_type, field_type_ok := component_field_type_from_script(field_type_text)
		if !field_type_ok {
			delete(fields)
			return nil, false
		}
		append(&fields, Runtime_Component_Field_Definition{name = name, value_type = field_type})
	}
	out := make([]Runtime_Component_Field_Definition, len(fields))
	if out == nil && len(fields) > 0 {
		delete(fields)
		return nil, false
	}
	for field, index in fields {
		out[index] = field
	}
	delete(fields)
	return out, true
}

parse_native_field_array :: proc(contents, array_name: string) -> ([]Runtime_Component_Field_Definition, bool) {
	start := strings.index(contents, array_name)
	if start < 0 {
		return nil, false
	}
	after_name := contents[start + len(array_name):]
	type_marker := "scrapbot.ComponentField{"
	type_index := strings.index(after_name, type_marker)
	if type_index < 0 {
		return nil, false
	}
	body_fragment := after_name[type_index + len(type_marker):]
	end := strings.index(body_fragment, "};")
	if end < 0 {
		return nil, false
	}

	fields := make([dynamic]Runtime_Component_Field_Definition)
	remaining := body_fragment[:end]
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		name, name_ok := parse_assignment_string_value(trimmed, ".name")
		field_type_text, type_ok := parse_assignment_enum_value(trimmed, ".field_type")
		if !name_ok || !type_ok {
			delete(fields)
			return nil, false
		}
		field_type, field_type_ok := component_field_type_from_native(field_type_text)
		if !field_type_ok {
			delete(fields)
			return nil, false
		}
		append(&fields, Runtime_Component_Field_Definition{name = name, value_type = field_type})
	}
	out := make([]Runtime_Component_Field_Definition, len(fields))
	if out == nil && len(fields) > 0 {
		delete(fields)
		return nil, false
	}
	for field, index in fields {
		out[index] = field
	}
	delete(fields)
	return out, true
}

parse_native_component_id :: proc(block: string) -> (string, bool) {
	return parse_assignment_string_value(block, ".id")
}

parse_native_component_fields_reference :: proc(block: string) -> (string, bool) {
	field_key := strings.index(block, ".fields")
	if field_key < 0 {
		return "", false
	}
	after_key := block[field_key + len(".fields"):]
	eq_index := strings.index_byte(after_key, '=')
	if eq_index < 0 {
		return "", false
	}
	value := strings.trim_space(after_key[eq_index + 1:])
	if strings.has_suffix(value, ",") {
		value = strings.trim_space(value[:len(value) - 1])
	}
	slice_index := strings.index(value, "[0..]")
	if slice_index < 0 {
		return "", false
	}
	name := strings.trim_space(value[:slice_index])
	if name == "" {
		return "", false
	}
	return name, true
}

parse_assignment_string_value :: proc(text, key: string) -> (string, bool) {
	index := strings.index(text, key)
	if index < 0 {
		return "", false
	}
	after_key := text[index + len(key):]
	eq_index := strings.index_byte(after_key, '=')
	if eq_index < 0 {
		return "", false
	}
	value, _, ok := parse_quoted_prefix(strings.trim_space(after_key[eq_index + 1:]))
	return value, ok
}

parse_assignment_enum_value :: proc(text, key: string) -> (string, bool) {
	index := strings.index(text, key)
	if index < 0 {
		return "", false
	}
	after_key := text[index + len(key):]
	eq_index := strings.index_byte(after_key, '=')
	if eq_index < 0 {
		return "", false
	}
	value := strings.trim_space(after_key[eq_index + 1:])
	if !strings.has_prefix(value, ".") {
		return "", false
	}
	end := 1
	for end < len(value) {
		byte := value[end]
		if !((byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') || byte == '_') {
			break
		}
		end += 1
	}
	return value[1:end], end > 1
}

parse_quoted_prefix :: proc(text: string) -> (value: string, consumed: int, ok: bool) {
	if len(text) < 2 || text[0] != '"' {
		return "", 0, false
	}
	index := 1
	for index < len(text) {
		if text[index] == '\\' {
			return "", 0, false
		}
		if text[index] == '"' {
			return text[1:index], index + 1, true
		}
		index += 1
	}
	return "", 0, false
}

component_field_type_from_script :: proc(value: string) -> (Runtime_Field_Type, bool) {
	switch value {
	case "boolean", "bool":
		return .Boolean, true
	case "int", "i32":
		return .Int, true
	case "f32", "float", "number":
		return .Float, true
	case "vec3":
		return .Vec3, true
	case "string":
		return .String, true
	}
	return .String, false
}

component_field_type_from_native :: proc(value: string) -> (Runtime_Field_Type, bool) {
	switch value {
	case "boolean":
		return .Boolean, true
	case "int":
		return .Int, true
	case "float":
		return .Float, true
	case "vec3":
		return .Vec3, true
	case "string":
		return .String, true
	}
	return .String, false
}
