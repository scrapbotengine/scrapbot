package main

import "core:os"
import "core:strings"

Native_System_Operation_Kind :: enum {
	None,
	Set_Field,
}

Native_System_Operation :: struct {
	system_id:    string,
	path:         string,
	line:         int,
	runner_ref:   u32,
	kind:         Native_System_Operation_Kind,
	entity_id:    string,
	component_id: string,
	field_name:   string,
	value_text:   string,
}

script_program_load_native_file :: proc(program: ^Script_Program, file_system_path, diagnostic_path: string) -> Project_Error {
	contents, read_err := os.read_entire_file(file_system_path, context.allocator)
	if read_err != nil {
		return .Missing_Native
	}
	defer delete(contents)
	return script_program_load_native_contents(program, string(contents), diagnostic_path)
}

script_program_load_native_contents :: proc(program: ^Script_Program, contents, diagnostic_path: string) -> Project_Error {
	remaining := contents
	remaining_offset := 0
	native_runner_ref := u32(1)
	for {
		call_index := strings.index(remaining, "scrapbot.register_system")
		if call_index < 0 {
			break
		}
		absolute_index := remaining_offset + call_index
		fragment := remaining[call_index:]
		block_start := strings.index_byte(fragment, '{')
		if block_start < 0 {
			return .Invalid_Native
		}
		block_end := strings.index(fragment[block_start:], "})")
		if block_end < 0 {
			return .Invalid_Native
		}
		block := fragment[block_start:block_start + block_end]
		system_id, id_ok := parse_native_component_id(block)
		if !id_ok {
			return .Invalid_Native
		}
		line := line_number_for_offset(contents, absolute_index)
		if !script_program_append_system_origin(program, system_id, diagnostic_path, line, native_runner_ref) {
			return .Invalid_Native
		}
		if operation, found, ok := parse_native_execute_operation(block, system_id, diagnostic_path, line, native_runner_ref); !ok {
			return .Invalid_Native
		} else if found {
			append(&program.native_operations, operation)
		}
		native_runner_ref += 1
		advance := block_start + block_end + len("})")
		remaining = fragment[advance:]
		remaining_offset = absolute_index + advance
	}
	return .None
}

parse_native_execute_operation :: proc(
	block, system_id, diagnostic_path: string,
	line: int,
	runner_ref: u32,
) -> (Native_System_Operation, bool, bool) {
	execute_key := native_assignment_key_index(block, "execute")
	if execute_key < 0 {
		return {}, false, true
	}
	open_offset := strings.index_byte(block[execute_key:], '{')
	if open_offset < 0 {
		return {}, false, false
	}
	execute_start := execute_key + open_offset
	execute_end, execute_ok := matching_brace_index(block, execute_start)
	if !execute_ok {
		return {}, false, false
	}
	execute_block := block[execute_start:execute_end + 1]

	entity_id, entity_ok := parse_native_string_field_value(execute_block, "entity")
	component_id, component_ok := parse_native_string_field_value(execute_block, "component")
	field_name, field_ok := parse_native_string_field_value(execute_block, "field")
	value_text, value_ok := parse_native_execute_value_text(execute_block, "value")
	if !entity_ok || !component_ok || !field_ok || !value_ok {
		return {}, false, false
	}

	operation := Native_System_Operation{
		line = line,
		runner_ref = runner_ref,
		kind = .Set_Field,
	}
	if !clone_native_operation_string(&operation.system_id, system_id) ||
	   !clone_native_operation_string(&operation.path, diagnostic_path) ||
	   !clone_native_operation_string(&operation.entity_id, entity_id) ||
	   !clone_native_operation_string(&operation.component_id, component_id) ||
	   !clone_native_operation_string(&operation.field_name, field_name) ||
	   !clone_native_operation_string(&operation.value_text, value_text) {
		native_system_operation_free(operation)
		return {}, false, false
	}
	return operation, true, true
}

parse_native_execute_value_text :: proc(block, key: string) -> (string, bool) {
	key_index := native_assignment_key_index(block, key)
	if key_index < 0 {
		return "", false
	}
	eq_index := strings.index_byte(block[key_index:], '=')
	if eq_index < 0 {
		return "", false
	}
	raw := strings.trim_space(block[key_index + eq_index + 1:])
	if raw == "" {
		return "", false
	}
	if raw[0] == '"' {
		_, consumed, ok := parse_quoted_prefix(raw)
		if !ok {
			return "", false
		}
		return raw[:consumed], true
	}
	if raw[0] == '[' {
		close_index := strings.index_byte(raw, ']')
		if close_index < 0 {
			return "", false
		}
		return strings.trim_space(raw[:close_index + 1]), true
	}
	end := 0
	for end < len(raw) {
		byte := raw[end]
		if byte == ',' || byte == '\n' || byte == '\r' || byte == '}' {
			break
		}
		end += 1
	}
	value := strings.trim_space(raw[:end])
	return value, value != ""
}

matching_brace_index :: proc(text: string, open_index: int) -> (int, bool) {
	if open_index < 0 || open_index >= len(text) || text[open_index] != '{' {
		return -1, false
	}
	depth := 0
	for index := open_index; index < len(text); index += 1 {
		switch text[index] {
		case '{':
			depth += 1
		case '}':
			depth -= 1
			if depth == 0 {
				return index, true
			}
		}
	}
	return -1, false
}

script_program_run_native_system :: proc(
	program: ^Script_Program,
	registry: ^Runtime_Component_Registry,
	world: ^Runtime_World,
	system: Runtime_Scheduled_System,
) -> Script_Run_Result {
	operation, operation_ok := script_program_find_native_operation(program^, system)
	if !operation_ok {
		path, line := script_program_origin_for_system(program^, system.id, system.runner.ref)
		return Script_Run_Result{
			ok = false,
			diagnostic = script_runtime_diagnostic(path, system.id, line, "native Odin system execution is not ported yet"),
		}
	}
	switch operation.kind {
	case .Set_Field:
		return script_program_run_native_set_field(program, registry, world, system, operation)
	case .None:
	}
	return Script_Run_Result{
		ok = false,
		diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, "native Odin system operation is not supported"),
	}
}

script_program_run_native_set_field :: proc(
	program: ^Script_Program,
	registry: ^Runtime_Component_Registry,
	world: ^Runtime_World,
	system: Runtime_Scheduled_System,
	operation: Native_System_Operation,
) -> Script_Run_Result {
	if !runtime_scheduled_system_allows_write(registry^, system, operation.component_id) {
		message := strings.clone("native Odin system tried to write a component it did not declare")
		defer if message != "" do delete(message)
		return Script_Run_Result{ok = false, diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, message)}
	}
	entity, entity_ok := runtime_world_find_entity_by_id(world^, operation.entity_id)
	if !entity_ok {
		return Script_Run_Result{ok = false, diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, "native Odin system target entity was not found")}
	}
	current, current_err := runtime_world_get_component_field_value(world^, entity, operation.component_id, operation.field_name)
	if current_err != .None {
		return Script_Run_Result{ok = false, diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, runtime_error_label(current_err))}
	}
	value, value_ok := read_scene_component_runtime_value(operation.value_text, current.value_type)
	if !value_ok {
		return Script_Run_Result{ok = false, diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, "native Odin system value does not match target field type")}
	}
	set_err := runtime_world_set_component_field_value(world, entity, operation.component_id, operation.field_name, value)
	if set_err != .None {
		return Script_Run_Result{ok = false, diagnostic = script_runtime_diagnostic(operation.path, system.id, operation.line, runtime_error_label(set_err))}
	}
	return Script_Run_Result{ok = true}
}

runtime_scheduled_system_allows_write :: proc(
	registry: Runtime_Component_Registry,
	system: Runtime_Scheduled_System,
	component_id: string,
) -> bool {
	if system.registry_index < 0 || system.registry_index >= len(registry.systems) {
		return false
	}
	definition := registry.systems[system.registry_index]
	return runtime_contains_string(definition.writes, component_id)
}

script_program_find_native_operation :: proc(program: Script_Program, system: Runtime_Scheduled_System) -> (Native_System_Operation, bool) {
	for operation in program.native_operations {
		if (system.runner.ref != 0 && operation.runner_ref == system.runner.ref) || operation.system_id == system.id {
			return operation, true
		}
	}
	return {}, false
}

script_program_origin_for_system :: proc(program: Script_Program, system_id: string, runner_ref: u32) -> (string, int) {
	if origin, ok := script_program_find_system_origin(program, system_id, runner_ref); ok {
		return origin.path, origin.line
	}
	return "", 0
}

line_number_for_offset :: proc(contents: string, offset: int) -> int {
	line := 1
	limit := native_min_int(offset, len(contents))
	for index := 0; index < limit; index += 1 {
		if contents[index] == '\n' {
			line += 1
		}
	}
	return line
}

native_min_int :: proc(left, right: int) -> int {
	if left < right {
		return left
	}
	return right
}

clone_native_operation_string :: proc(target: ^string, value: string) -> bool {
	owned, err := strings.clone(value)
	if err != nil {
		return false
	}
	target^ = owned
	return true
}

native_system_operations_free :: proc(operations: []Native_System_Operation) {
	for operation in operations {
		native_system_operation_free(operation)
	}
}

native_system_operation_free :: proc(operation: Native_System_Operation) {
	if operation.system_id != "" do delete(operation.system_id)
	if operation.path != "" do delete(operation.path)
	if operation.entity_id != "" do delete(operation.entity_id)
	if operation.component_id != "" do delete(operation.component_id)
	if operation.field_name != "" do delete(operation.field_name)
	if operation.value_text != "" do delete(operation.value_text)
}
