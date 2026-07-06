package main

import "core:os"
import "core:strings"

Script_Component_Binding :: struct {
	name: string,
	id:   string,
}

Script_Query_Binding :: struct {
	name:          string,
	component_ids: []string,
}

register_script_components_from_file :: proc(registry: ^Runtime_Component_Registry, path: string) -> Project_Error {
	err, diagnostic := register_script_components_from_file_detailed(registry, path, path)
	script_diagnostic_free(&diagnostic)
	return err
}

register_script_components_from_file_detailed :: proc(
	registry: ^Runtime_Component_Registry,
	file_system_path: string,
	diagnostic_path: string,
) -> (Project_Error, Script_Diagnostic) {
	contents, read_err := os.read_entire_file(file_system_path, context.allocator)
	if read_err != nil {
		return .Missing_Script, Script_Diagnostic{}
	}
	defer delete(contents)

	component_bindings := make([dynamic]Script_Component_Binding)
	defer delete(component_bindings)
	query_bindings := make([dynamic]Script_Query_Binding)
	defer delete(query_bindings)
	defer free_script_query_bindings(query_bindings[:])

	remaining := string(contents)
	remaining_offset := 0
	for {
		component_index := strings.index(remaining, "ecs.component")
		if component_index < 0 {
			break
		}
		fragment := remaining[component_index:]
		open_index := strings.index_byte(fragment, '(')
		if open_index < 0 {
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, string(contents), remaining_offset + component_index, "ecs.component call is missing '('")
		}
		after_open := strings.trim_space(fragment[open_index + 1:])
		component_id, id_len, id_ok := parse_quoted_prefix(after_open)
		if !id_ok {
			remaining = fragment[len("ecs.component"):]
			remaining_offset += component_index + len("ecs.component")
			continue
		}
		if name, name_ok := parse_luau_assignment_name_before(string(contents), remaining_offset + component_index); name_ok {
			append(&component_bindings, Script_Component_Binding{name = name, id = component_id})
		}
		if runtime_is_engine_type_id(component_id) {
			remaining = after_open[id_len:]
			remaining_offset += component_index + open_index + 1 + len(fragment[open_index + 1:]) - len(after_open) + id_len
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
				return .Invalid_Script, script_registration_diagnostic(diagnostic_path, string(contents), remaining_offset + component_index, "ecs.fields table is missing closing '})'")
			}
			fields_ok: bool
			fields, fields_ok = parse_script_field_definitions(fields_fragment[:fields_end])
			if !fields_ok {
				return .Invalid_Script, script_registration_diagnostic(diagnostic_path, string(contents), remaining_offset + component_index, "ecs.fields contains an unsupported field declaration")
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
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, string(contents), remaining_offset + component_index, "script component declaration is invalid")
		}
		remaining_offset += len(string(contents)[remaining_offset:]) - len(next_remaining)
		remaining = next_remaining
	}

	query_err, query_diagnostic := register_script_query_bindings(string(contents), diagnostic_path, component_bindings[:], &query_bindings)
	if query_err != .None {
		return query_err, query_diagnostic
	}
	system_err, system_diagnostic := register_script_systems_from_contents(registry, string(contents), diagnostic_path, component_bindings[:], query_bindings[:])
	if system_err != .None {
		return system_err, system_diagnostic
	}
	return .None, Script_Diagnostic{}
}

register_native_components_from_file :: proc(registry: ^Runtime_Component_Registry, path: string) -> Project_Error {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return .Missing_Native
	}
	defer delete(contents)

	source := string(contents)
	if strings.index(source, "scrapbot.register_component") >= 0 || strings.index(source, "scrapbot.register_system") >= 0 {
		return register_odin_native_declarations_from_contents(registry, source)
	}

	remaining := source
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

register_odin_native_declarations_from_contents :: proc(registry: ^Runtime_Component_Registry, contents: string) -> Project_Error {
	component_err := register_odin_native_components_from_contents(registry, contents)
	if component_err != .None {
		return component_err
	}
	return register_odin_native_systems_from_contents(registry, contents)
}

register_odin_native_components_from_contents :: proc(registry: ^Runtime_Component_Registry, contents: string) -> Project_Error {
	remaining := contents
	for {
		call_index := strings.index(remaining, "scrapbot.register_component")
		if call_index < 0 {
			break
		}
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
			fields, fields_ok = parse_native_field_array(contents, field_array_name)
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

register_odin_native_systems_from_contents :: proc(registry: ^Runtime_Component_Registry, contents: string) -> Project_Error {
	remaining := contents
	native_runner_ref := u32(1)
	for {
		call_index := strings.index(remaining, "scrapbot.register_system")
		if call_index < 0 {
			break
		}
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
		phase := Runtime_System_Phase.Update
		if phase_text, phase_found, phase_ok := parse_native_enum_field(block, "phase"); phase_found {
			if !phase_ok {
				return .Invalid_Native
			}
			parsed_phase, parsed_phase_ok := parse_native_system_phase(phase_text)
			if !parsed_phase_ok {
				return .Invalid_Native
			}
			phase = parsed_phase
		}

		reads := make([dynamic]string)
		writes := make([dynamic]string)
		before := make([dynamic]string)
		after := make([dynamic]string)
		defer delete(reads)
		defer delete(writes)
		defer delete(before)
		defer delete(after)

		if !append_native_string_array_reference(&reads, contents, block, "reads") {
			return .Invalid_Native
		}
		if !append_native_string_array_reference(&writes, contents, block, "writes") {
			return .Invalid_Native
		}
		if !append_native_string_array_reference(&before, contents, block, "before") {
			return .Invalid_Native
		}
		if !append_native_string_array_reference(&after, contents, block, "after") {
			return .Invalid_Native
		}

		runtime_err := runtime_register_project_system(registry, Runtime_System_Definition{
			id = system_id,
			phase = phase,
			reads = reads[:],
			writes = writes[:],
			before = before[:],
			after = after[:],
			runner = Runtime_System_Runner{kind = .Native, ref = native_runner_ref},
		})
		if runtime_err != .None {
			return .Invalid_Native
		}
		native_runner_ref += 1
		remaining = fragment[block_start + block_end + len("})"):]
	}
	return .None
}

register_script_query_bindings :: proc(
	contents: string,
	diagnostic_path: string,
	component_bindings: []Script_Component_Binding,
	query_bindings: ^[dynamic]Script_Query_Binding,
) -> (Project_Error, Script_Diagnostic) {
	remaining := contents
	remaining_offset := 0
	for {
		query_index := strings.index(remaining, "ecs.query")
		if query_index < 0 {
			break
		}
		absolute_index := remaining_offset + query_index
		fragment := remaining[query_index:]
		open_index := strings.index_byte(fragment, '(')
		if open_index < 0 {
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, contents, absolute_index, "ecs.query call is missing '('")
		}
		after_open := fragment[open_index + 1:]
		close_index := strings.index_byte(after_open, ')')
		if close_index < 0 {
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, contents, absolute_index, "ecs.query call is missing ')'")
		}
		query_name, query_name_ok := parse_luau_assignment_name_before(contents, absolute_index)
		if query_name_ok {
			ids, ids_ok := parse_script_component_ref_list(after_open[:close_index], component_bindings)
			if !ids_ok {
				return .Invalid_Script, script_registration_diagnostic(diagnostic_path, contents, absolute_index, "ecs.query references an unknown or invalid component")
			}
			append(query_bindings, Script_Query_Binding{name = query_name, component_ids = ids})
		}
		remaining_offset = absolute_index + open_index + close_index + 2
		remaining = contents[remaining_offset:]
	}
	return .None, Script_Diagnostic{}
}

register_script_systems_from_contents :: proc(
	registry: ^Runtime_Component_Registry,
	contents: string,
	diagnostic_path: string,
	component_bindings: []Script_Component_Binding,
	query_bindings: []Script_Query_Binding,
) -> (Project_Error, Script_Diagnostic) {
	remaining := contents
	remaining_offset := 0
	for {
		system_index := strings.index(remaining, "ecs.system")
		if system_index < 0 {
			break
		}
		absolute_index := remaining_offset + system_index
		fragment := remaining[system_index:]
		open_index := strings.index_byte(fragment, '(')
		if open_index < 0 {
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, contents, absolute_index, "ecs.system call is missing '('")
		}
		after_open := strings.trim_space(fragment[open_index + 1:])
		system_id, id_len, id_ok := parse_quoted_prefix(after_open)
		if !id_ok {
			return .Invalid_Script, script_registration_diagnostic(diagnostic_path, contents, absolute_index, "ecs.system id must be a quoted string")
		}
		body_start_offset := absolute_index + open_index + 1 + len(fragment[open_index + 1:]) - len(after_open) + id_len
		after_id := contents[body_start_offset:]
		next_system_index := strings.index(after_id, "ecs.system")
		body := after_id
		if next_system_index >= 0 {
			body = after_id[:next_system_index]
		}

		err, diagnostic := register_script_system_from_body(registry, system_id, body, contents, diagnostic_path, absolute_index, component_bindings, query_bindings)
		if err != .None {
			return err, diagnostic
		}
		remaining_offset = body_start_offset + len(body)
		remaining = contents[remaining_offset:]
	}
	return .None, Script_Diagnostic{}
}

register_script_system_from_body :: proc(
	registry: ^Runtime_Component_Registry,
	system_id: string,
	body: string,
	contents: string,
	diagnostic_path: string,
	absolute_index: int,
	component_bindings: []Script_Component_Binding,
	query_bindings: []Script_Query_Binding,
) -> (Project_Error, Script_Diagnostic) {
	metadata_body := body
	if run_index := strings.index(body, "run ="); run_index >= 0 {
		metadata_body = body[:run_index]
	}

	phase := Runtime_System_Phase.Update
	if phase_value, phase_found, phase_ok := parse_script_string_field(metadata_body, "phase"); phase_found {
		if !phase_ok {
			return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system phase must be a quoted string")
		}
		parsed_phase, parsed_phase_ok := parse_script_system_phase(phase_value)
		if !parsed_phase_ok {
			return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system phase is not supported")
		}
		phase = parsed_phase
	}

	reads := make([dynamic]string)
	writes := make([dynamic]string)
	before := make([dynamic]string)
	after := make([dynamic]string)
	defer delete(reads)
	defer delete(writes)
	defer delete(before)
	defer delete(after)

	if ok := append_script_refs_field(&reads, metadata_body, "reads", component_bindings); !ok {
		return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system reads must use ecs.refs with known components")
	}
	if ok := append_script_refs_field(&writes, metadata_body, "writes", component_bindings); !ok {
		return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system writes must use ecs.refs with known components")
	}
	if ok := append_script_string_array_field(&before, metadata_body, "before"); !ok {
		return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system before list must contain quoted ids")
	}
	if ok := append_script_string_array_field(&after, metadata_body, "after"); !ok {
		return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system after list must contain quoted ids")
	}
	if query_name, query_found, query_ok := parse_script_identifier_field(metadata_body, "query"); query_found {
		if !query_ok {
			return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system query must reference a local query binding")
		}
		components, components_ok := script_query_components_for_name(query_bindings, query_name)
		if !components_ok {
			return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "system query references an unknown query binding")
		}
		for component_id in components {
			if !runtime_contains_string(reads[:], component_id) && !runtime_contains_string(writes[:], component_id) {
				append(&reads, component_id)
			}
		}
	}

	runtime_err := runtime_register_project_system(registry, Runtime_System_Definition{
		id = system_id,
		phase = phase,
		reads = reads[:],
		writes = writes[:],
		before = before[:],
		after = after[:],
		runner = Runtime_System_Runner{kind = .Luau, ref = 0},
	})
	if runtime_err != .None {
		return .Invalid_Script, script_system_registration_diagnostic(diagnostic_path, contents, absolute_index, system_id, "script system declaration is invalid")
	}
	return .None, Script_Diagnostic{}
}

free_script_query_bindings :: proc(bindings: []Script_Query_Binding) {
	for binding in bindings {
		if binding.component_ids != nil {
			delete(binding.component_ids)
		}
	}
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

parse_luau_assignment_name_before :: proc(contents: string, absolute_index: int) -> (string, bool) {
	if absolute_index <= 0 || absolute_index > len(contents) {
		return "", false
	}
	line_start := absolute_index
	for line_start > 0 && contents[line_start - 1] != '\n' {
		line_start -= 1
	}
	line := strings.trim_space(contents[line_start:absolute_index])
	if line == "" {
		return "", false
	}
	eq_index := -1
	for index := len(line) - 1; index >= 0; index -= 1 {
		if line[index] == '=' {
			eq_index = index
			break
		}
	}
	if eq_index < 0 {
		return "", false
	}
	left := strings.trim_space(line[:eq_index])
	if strings.has_prefix(left, "local ") {
		left = strings.trim_space(left[len("local "):])
	}
	end := len(left)
	for end > 0 && !is_script_identifier_byte(left[end - 1]) {
		end -= 1
	}
	start := end
	for start > 0 && is_script_identifier_byte(left[start - 1]) {
		start -= 1
	}
	if start == end || !is_script_identifier_start_byte(left[start]) {
		return "", false
	}
	return left[start:end], true
}

parse_script_component_ref_list :: proc(body: string, component_bindings: []Script_Component_Binding) -> ([]string, bool) {
	ids := make([dynamic]string)
	remaining := body
	for {
		token, consumed, found := parse_script_identifier_prefix(remaining)
		if !found {
			if strings.trim_space(remaining) != "" {
				delete(ids)
				return nil, false
			}
			break
		}
		component_id, component_ok := script_component_id_for_name(component_bindings, token)
		if !component_ok {
			delete(ids)
			return nil, false
		}
		append(&ids, component_id)
		remaining = remaining[consumed:]
		tail := strings.trim_space(remaining)
		if tail == "" {
			break
		}
		if tail[0] != ',' {
			delete(ids)
			return nil, false
		}
		remaining = tail[1:]
	}
	out := make([]string, len(ids))
	if out == nil && len(ids) > 0 {
		delete(ids)
		return nil, false
	}
	for id, index in ids {
		out[index] = id
	}
	delete(ids)
	return out, true
}

parse_script_string_field :: proc(body, key: string) -> (value: string, found: bool, ok: bool) {
	raw, raw_found := parse_script_field_line_value(body, key)
	if !raw_found {
		return "", false, true
	}
	parsed_value, _, quoted_ok := parse_quoted_prefix(strings.trim_space(raw))
	return parsed_value, true, quoted_ok
}

parse_script_identifier_field :: proc(body, key: string) -> (value: string, found: bool, ok: bool) {
	raw, raw_found := parse_script_field_line_value(body, key)
	if !raw_found {
		return "", false, true
	}
	identifier, _, identifier_ok := parse_script_identifier_prefix(raw)
	return identifier, true, identifier_ok
}

parse_script_field_line_value :: proc(body, key: string) -> (string, bool) {
	remaining := body
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if !strings.has_prefix(trimmed, key) {
			continue
		}
		after_key := strings.trim_space(trimmed[len(key):])
		if len(after_key) == 0 || after_key[0] != '=' {
			continue
		}
		value := strings.trim_space(after_key[1:])
		if strings.has_suffix(value, ",") {
			value = strings.trim_space(value[:len(value) - 1])
		}
		return value, true
	}
	return "", false
}

append_script_refs_field :: proc(
	out: ^[dynamic]string,
	body, key: string,
	component_bindings: []Script_Component_Binding,
) -> bool {
	raw, found := parse_script_field_line_value(body, key)
	if !found {
		return true
	}
	refs_index := strings.index(raw, "ecs.refs")
	if refs_index < 0 {
		return false
	}
	fragment := raw[refs_index:]
	open_index := strings.index_byte(fragment, '(')
	if open_index < 0 {
		return false
	}
	after_open := fragment[open_index + 1:]
	close_index := strings.index_byte(after_open, ')')
	if close_index < 0 {
		return false
	}
	ids, ids_ok := parse_script_component_ref_list(after_open[:close_index], component_bindings)
	if !ids_ok {
		return false
	}
	defer delete(ids)
	for id in ids {
		append(out, id)
	}
	return true
}

append_script_string_array_field :: proc(out: ^[dynamic]string, body, key: string) -> bool {
	raw, found := parse_script_field_line_value(body, key)
	if !found {
		return true
	}
	open_index := strings.index_byte(raw, '{')
	close_index := strings.index_byte(raw, '}')
	if open_index < 0 || close_index < open_index {
		return false
	}
	remaining := raw[open_index + 1:close_index]
	for {
		quoted_index := strings.index_byte(remaining, '"')
		if quoted_index < 0 {
			break
		}
		value, consumed, ok := parse_quoted_prefix(remaining[quoted_index:])
		if !ok {
			return false
		}
		append(out, value)
		remaining = remaining[quoted_index + consumed:]
	}
	return true
}

parse_script_system_phase :: proc(value: string) -> (Runtime_System_Phase, bool) {
	switch value {
	case "startup":
		return .Startup, true
	case "update":
		return .Update, true
	case "fixed_update":
		return .Fixed_Update, true
	case "render":
		return .Render, true
	}
	return .Update, false
}

script_component_id_for_name :: proc(bindings: []Script_Component_Binding, name: string) -> (string, bool) {
	for binding in bindings {
		if binding.name == name {
			return binding.id, true
		}
	}
	return "", false
}

script_query_components_for_name :: proc(bindings: []Script_Query_Binding, name: string) -> ([]string, bool) {
	for binding in bindings {
		if binding.name == name {
			return binding.component_ids, true
		}
	}
	return nil, false
}

parse_script_identifier_prefix :: proc(text: string) -> (value: string, consumed: int, ok: bool) {
	trimmed := strings.trim_space(text)
	trimmed_prefix_len := len(text) - len(trimmed)
	if len(trimmed) == 0 || !is_script_identifier_start_byte(trimmed[0]) {
		return "", 0, false
	}
	end := 1
	for end < len(trimmed) && is_script_identifier_byte(trimmed[end]) {
		end += 1
	}
	return trimmed[:end], trimmed_prefix_len + end, true
}

is_script_identifier_start_byte :: proc(byte: u8) -> bool {
	return (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') || byte == '_'
}

is_script_identifier_byte :: proc(byte: u8) -> bool {
	return is_script_identifier_start_byte(byte) || (byte >= '0' && byte <= '9')
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
		type_marker = "scrapbot.Component_Field{"
		type_index = strings.index(after_name, type_marker)
		if type_index < 0 {
			return nil, false
		}
	}
	body_fragment := after_name[type_index + len(type_marker):]

	fields := make([dynamic]Runtime_Component_Field_Definition)
	remaining := body_fragment
	closed := false
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if strings.has_prefix(trimmed, "}") {
			closed = true
			break
		}
		name, name_ok := parse_native_string_field_value(trimmed, "name")
		field_type_text, type_found, type_ok := parse_native_enum_field(trimmed, "field_type")
		if !name_ok || !type_found || !type_ok {
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
	if !closed {
		delete(fields)
		return nil, false
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
	return parse_native_string_field_value(block, "id")
}

parse_native_component_fields_reference :: proc(block: string) -> (string, bool) {
	field_key := native_assignment_key_index(block, "fields")
	if field_key < 0 {
		return "", false
	}
	after_key := block[field_key + len("fields"):]
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
		slice_index = strings.index(value, "[:]")
		if slice_index < 0 {
			return "", false
		}
	}
	name := strings.trim_space(value[:slice_index])
	if name == "" {
		return "", false
	}
	return name, true
}

parse_native_string_field_value :: proc(text, key: string) -> (string, bool) {
	index := native_assignment_key_index(text, key)
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

parse_native_enum_field :: proc(text, key: string) -> (value: string, found: bool, ok: bool) {
	index := native_assignment_key_index(text, key)
	if index < 0 {
		return "", false, true
	}
	after_key := text[index + len(key):]
	eq_index := strings.index_byte(after_key, '=')
	if eq_index < 0 {
		return "", true, false
	}
	raw := strings.trim_space(after_key[eq_index + 1:])
	if !strings.has_prefix(raw, ".") {
		return "", true, false
	}
	end := 1
	for end < len(raw) {
		byte := raw[end]
		if !is_script_identifier_byte(byte) {
			break
		}
		end += 1
	}
	return raw[1:end], true, end > 1
}

native_assignment_key_index :: proc(text, key: string) -> int {
	index := strings.index(text, key)
	for index >= 0 {
		if index == 0 || !is_script_identifier_byte(text[index - 1]) {
			after := index + len(key)
			if after >= len(text) || !is_script_identifier_byte(text[after]) {
				return index
			}
		}
		next_start := index + len(key)
		if next_start >= len(text) {
			break
		}
		next_index := strings.index(text[next_start:], key)
		if next_index < 0 {
			break
		}
		index = next_start + next_index
	}
	return -1
}

append_native_string_array_reference :: proc(out: ^[dynamic]string, contents, block, key: string) -> bool {
	array_name, found := parse_native_string_array_reference(block, key)
	if !found {
		return true
	}
	values, ok := parse_native_string_array(contents, array_name)
	if !ok {
		return false
	}
	defer delete(values)
	for value in values {
		append(out, value)
	}
	return true
}

parse_native_string_array_reference :: proc(block, key: string) -> (string, bool) {
	field_key := native_assignment_key_index(block, key)
	if field_key < 0 {
		return "", false
	}
	after_key := block[field_key + len(key):]
	eq_index := strings.index_byte(after_key, '=')
	if eq_index < 0 {
		return "", false
	}
	value := strings.trim_space(after_key[eq_index + 1:])
	if strings.has_suffix(value, ",") {
		value = strings.trim_space(value[:len(value) - 1])
	}
	slice_index := strings.index(value, "[:]")
	if slice_index < 0 {
		slice_index = strings.index(value, "[0..]")
		if slice_index < 0 {
			return "", false
		}
	}
	name := strings.trim_space(value[:slice_index])
	return name, name != ""
}

parse_native_string_array :: proc(contents, array_name: string) -> ([]string, bool) {
	start := strings.index(contents, array_name)
	if start < 0 {
		return nil, false
	}
	after_name := contents[start + len(array_name):]
	open_index := strings.index_byte(after_name, '{')
	if open_index < 0 {
		return nil, false
	}
	after_open := after_name[open_index + 1:]
	close_index := strings.index_byte(after_open, '}')
	if close_index < 0 {
		return nil, false
	}
	values := make([dynamic]string)
	remaining := after_open[:close_index]
	for {
		quoted_index := strings.index_byte(remaining, '"')
		if quoted_index < 0 {
			break
		}
		value, consumed, ok := parse_quoted_prefix(remaining[quoted_index:])
		if !ok {
			delete(values)
			return nil, false
		}
		append(&values, value)
		remaining = remaining[quoted_index + consumed:]
	}
	out := make([]string, len(values))
	if out == nil && len(values) > 0 {
		delete(values)
		return nil, false
	}
	for value, index in values {
		out[index] = value
	}
	delete(values)
	return out, true
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
		if !is_script_identifier_byte(byte) {
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
	case "boolean", "bool", "Boolean", "Bool":
		return .Boolean, true
	case "int", "i32", "Int", "I32":
		return .Int, true
	case "float", "f32", "Float", "F32":
		return .Float, true
	case "vec3", "Vec3":
		return .Vec3, true
	case "string", "String":
		return .String, true
	}
	return .String, false
}

parse_native_system_phase :: proc(value: string) -> (Runtime_System_Phase, bool) {
	switch value {
	case "startup", "Startup":
		return .Startup, true
	case "update", "Update":
		return .Update, true
	case "fixed_update", "Fixed_Update":
		return .Fixed_Update, true
	case "render", "Render":
		return .Render, true
	}
	return .Update, false
}
