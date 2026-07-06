package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

TEST_MANIFEST_NAME :: "test.scrapbot.toml"
TEST_DEFAULT_ROOT :: "tests/projects"
TEST_PENDING_EXECUTION_REASON :: "pending_odin_luau_native_bridge"

Test_Command_Error :: enum {
	None,
	Discovery_Failed,
	No_Test_Projects,
}

Test_Case_Status :: enum {
	Pending,
	Failed,
}

Test_Options :: struct {
	target_path: string,
	format:      Check_Output_Format,
}

Test_Manifest_Summary :: struct {
	frames:        int,
	delta_seconds: f32,
	expectations:  int,
	input_frames:  int,
}

Test_Case_Result :: struct {
	name:          string,
	path:          string,
	status:        Test_Case_Status,
	frames:        int,
	delta_seconds: f32,
	expectations:  int,
	input_frames:  int,
	error:         string,
}

Test_Suite_Summary :: struct {
	cases:              int,
	validated:          int,
	failed:             int,
	pending:            int,
	assertions:         int,
	pending_assertions: int,
}

Test_Command_Result :: struct {
	cases:   [dynamic]Test_Case_Result,
	summary: Test_Suite_Summary,
}

Test_Manifest_Section :: enum {
	Root,
	Expect_Field,
	Input_Frame,
}

Test_Manifest_Expectation_State :: struct {
	active:        bool,
	entity:        bool,
	component:     bool,
	field:         bool,
	equals_count: int,
}

Test_Manifest_Input_State :: struct {
	active: bool,
	frame:  bool,
}

parse_test_options :: proc(args: []string, emit_output: bool) -> (Test_Options, bool) {
	options := Test_Options{
		target_path = TEST_DEFAULT_ROOT,
		format = .Text,
	}
	i := 0
	for i < len(args) {
		arg := args[i]
		if strings.has_prefix(arg, "--format=") {
			parsed, ok := parse_output_format(arg[len("--format="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", arg[len("--format="):])
				}
				return options, false
			}
			options.format = parsed
			i += 1
			continue
		}
		if arg == "--format" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --format")
				}
				return options, false
			}
			parsed, ok := parse_output_format(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", args[i + 1])
				}
				return options, false
			}
			options.format = parsed
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return options, false
		}
		if options.target_path != TEST_DEFAULT_ROOT {
			if emit_output {
				fmt.eprintf("unexpected argument: %s\n", arg)
			}
			return options, false
		}
		options.target_path = arg
		i += 1
	}
	return options, true
}

run_test_command :: proc(options: Test_Options) -> (Test_Command_Result, Test_Command_Error) {
	result := Test_Command_Result{
		cases = make([dynamic]Test_Case_Result),
	}

	project_paths, discovery_err := collect_test_projects(options.target_path)
	defer free_string_list(project_paths)
	if discovery_err != .None {
		return result, discovery_err
	}
	if len(project_paths) == 0 {
		return result, .No_Test_Projects
	}

	for project_path in project_paths {
		case_result := run_pending_test_case(project_path)
		append(&result.cases, case_result)
		result.summary.cases += 1
		result.summary.assertions += case_result.expectations
		if case_result.status == .Failed {
			result.summary.failed += 1
		} else {
			result.summary.validated += 1
			result.summary.pending += 1
			result.summary.pending_assertions += case_result.expectations
		}
	}

	return result, .None
}

run_pending_test_case :: proc(project_path: string) -> Test_Case_Result {
	name := test_case_name_from_path(project_path)
	path := strings.clone(project_path)
	result := Test_Case_Result{
		name = name,
		path = path,
		status = .Pending,
	}

	manifest, manifest_ok := load_test_manifest_summary(project_path)
	if !manifest_ok {
		result.status = .Failed
		result.error = strings.clone("invalid test manifest")
		return result
	}
	result.frames = manifest.frames
	result.delta_seconds = manifest.delta_seconds
	result.expectations = manifest.expectations
	result.input_frames = manifest.input_frames

	check := check_project(project_path)
	defer free_check_result(check)
	if check.err != .None {
		result.status = .Failed
		result.error = strings.clone(project_error_message(check.err))
		return result
	}

	return result
}

collect_test_projects :: proc(target_path: string) -> ([dynamic]string, Test_Command_Error) {
	projects := make([dynamic]string)
	if is_test_project_path(target_path) {
		append(&projects, strings.clone(target_path))
		return projects, .None
	}

	entries, read_err := os.read_all_directory_by_path(target_path, context.allocator)
	if read_err != nil {
		return projects, .Discovery_Failed
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.type != .Directory {
			continue
		}
		child_path, join_err := filepath.join([]string{target_path, entry.name})
		if join_err != nil {
			free_string_list(projects)
			return nil, .Discovery_Failed
		}
		if is_test_project_path(child_path) {
			append(&projects, strings.clone(child_path))
		}
		delete(child_path)
	}

	sort_strings(projects[:])
	return projects, .None
}

is_test_project_path :: proc(path: string) -> bool {
	metadata_name := project_metadata_file_name(path)
	if metadata_name == "" {
		return false
	}
	manifest_path := project_relative_path(path, TEST_MANIFEST_NAME)
	defer delete(manifest_path)
	return os.exists(manifest_path)
}

load_test_manifest_summary :: proc(project_path: string) -> (Test_Manifest_Summary, bool) {
	manifest_path := project_relative_path(project_path, TEST_MANIFEST_NAME)
	defer delete(manifest_path)
	contents, read_err := os.read_entire_file(manifest_path, context.allocator)
	if read_err != nil {
		return {}, false
	}
	defer delete(contents)
	return parse_test_manifest_summary(string(contents))
}

parse_test_manifest_summary :: proc(contents: string) -> (Test_Manifest_Summary, bool) {
	summary := Test_Manifest_Summary{
		frames = DEFAULT_STEP_FRAMES,
		delta_seconds = DEFAULT_STEP_DELTA_SECONDS,
	}
	section := Test_Manifest_Section.Root
	expect := Test_Manifest_Expectation_State{}
	input := Test_Manifest_Input_State{}

	finish_expect := proc(expect: ^Test_Manifest_Expectation_State) -> bool {
		if !expect.active {
			return true
		}
		ok := expect.entity && expect.component && expect.field && expect.equals_count == 1
		expect^ = {}
		return ok
	}
	finish_input := proc(input: ^Test_Manifest_Input_State) -> bool {
		if !input.active {
			return true
		}
		ok := input.frame
		input^ = {}
		return ok
	}

	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if trimmed == "[[expect.field]]" || trimmed == "[[expect]]" {
			if !finish_expect(&expect) || !finish_input(&input) {
				return summary, false
			}
			section = .Expect_Field
			expect.active = true
			summary.expectations += 1
			continue
		}
		if trimmed == "[[input.frame]]" {
			if !finish_expect(&expect) || !finish_input(&input) {
				return summary, false
			}
			section = .Input_Frame
			input.active = true
			summary.input_frames += 1
			continue
		}
		if strings.has_prefix(trimmed, "[") {
			return summary, false
		}

		key, value, key_ok := read_manifest_key_value(trimmed)
		if !key_ok {
			return summary, false
		}
		switch section {
		case .Root:
			if !parse_test_manifest_root_key(&summary, key, value) {
				return summary, false
			}
		case .Expect_Field:
			if !parse_test_manifest_expect_key(&expect, key, value) {
				return summary, false
			}
		case .Input_Frame:
			if !parse_test_manifest_input_key(&input, key, value) {
				return summary, false
			}
		}
	}

	if !finish_expect(&expect) || !finish_input(&input) {
		return summary, false
	}
	if summary.frames <= 0 || summary.delta_seconds <= 0 || summary.expectations == 0 {
		return summary, false
	}
	return summary, true
}

parse_test_manifest_root_key :: proc(summary: ^Test_Manifest_Summary, key, value: string) -> bool {
	switch key {
	case "frames":
		frames, ok := parse_positive_int(value)
		if !ok {
			return false
		}
		summary.frames = frames
		return true
	case "dt", "delta_seconds":
		delta_seconds, ok := parse_positive_f32(value)
		if !ok {
			return false
		}
		summary.delta_seconds = delta_seconds
		return true
	}
	return false
}

parse_test_manifest_expect_key :: proc(expect: ^Test_Manifest_Expectation_State, key, value: string) -> bool {
	switch key {
	case "entity", "component", "field":
		parsed, ok := parse_basic_string(value)
		if !ok || parsed == "" {
			return false
		}
		switch key {
		case "entity":
			expect.entity = true
		case "component":
			expect.component = true
		case "field":
			expect.field = true
		}
		return true
	case "equals_bool":
		if value != "true" && value != "false" {
			return false
		}
		expect.equals_count += 1
		return true
	case "equals_int":
		_, ok := strconv.parse_int(value, 10)
		if !ok {
			return false
		}
		expect.equals_count += 1
		return true
	case "equals_float":
		if !parse_test_manifest_float(value) {
			return false
		}
		expect.equals_count += 1
		return true
	case "equals_vec3":
		if !parse_scene_vec3(value) {
			return false
		}
		expect.equals_count += 1
		return true
	case "equals_string":
		_, ok := parse_basic_string(value)
		if !ok {
			return false
		}
		expect.equals_count += 1
		return true
	}
	return false
}

parse_test_manifest_input_key :: proc(input: ^Test_Manifest_Input_State, key, value: string) -> bool {
	switch key {
	case "frame":
		_, ok := parse_positive_int(value)
		if !ok {
			return false
		}
		input.frame = true
		return true
	case "viewport", "pointer", "wheel_delta":
		return parse_test_manifest_vec2(value)
	case "primary_down", "primary_held", "primary_pressed", "primary_released", "debug_overlay_visible":
		return value == "true" || value == "false"
	case "system_profile_count_hint":
		_, ok := parse_positive_int(value)
		return ok
	}
	return false
}

parse_test_manifest_float :: proc(value: string) -> bool {
	parsed, ok := strconv.parse_f32(value)
	if !ok || parsed != parsed || parsed > 3.4028234663852886e38 || parsed < -3.4028234663852886e38 {
		return false
	}
	return true
}

parse_test_manifest_vec2 :: proc(value: string) -> bool {
	if len(value) < 5 || value[0] != '[' || value[len(value) - 1] != ']' {
		return false
	}
	count := 0
	inner := value[1:len(value) - 1]
	remaining := inner
	for part in strings.split_iterator(&remaining, ",") {
		if count >= 2 {
			return false
		}
		trimmed := strings.trim_space(part)
		if trimmed == "" || !parse_test_manifest_float(trimmed) {
			return false
		}
		count += 1
	}
	return count == 2
}

read_manifest_key_value :: proc(line: string) -> (string, string, bool) {
	eq_index := strings.index_byte(line, '=')
	if eq_index < 0 {
		return "", "", false
	}
	key := strings.trim_space(line[:eq_index])
	value := strings.trim_space(line[eq_index + 1:])
	return key, value, key != "" && value != ""
}

test_case_name_from_path :: proc(path: string) -> string {
	_, base := filepath.split(path)
	if base == "" || base == "." {
		return strings.clone(path)
	}
	return strings.clone(base)
}

sort_strings :: proc(values: []string) {
	for i := 1; i < len(values); i += 1 {
		current := values[i]
		j := i
		for j > 0 && strings.compare(current, values[j - 1]) < 0 {
			values[j] = values[j - 1]
			j -= 1
		}
		values[j] = current
	}
}

free_test_command_result :: proc(result: Test_Command_Result) {
	for case_result in result.cases {
		if case_result.name != "" {
			delete(case_result.name)
		}
		if case_result.path != "" {
			delete(case_result.path)
		}
		if case_result.error != "" {
			delete(case_result.error)
		}
	}
	delete(result.cases)
}

free_string_list :: proc(values: [dynamic]string) {
	for value in values {
		if value != "" {
			delete(value)
		}
	}
	delete(values)
}

print_test_command_result :: proc(result: Test_Command_Result, format: Check_Output_Format) {
	switch format {
	case .Text:
		for case_result in result.cases {
			switch case_result.status {
			case .Pending:
				fmt.printf(
					"PENDING %s: %d frames, dt %g, %d expectations, %d input frames (%s)\n",
					case_result.name,
					case_result.frames,
					case_result.delta_seconds,
					case_result.expectations,
					case_result.input_frames,
					TEST_PENDING_EXECUTION_REASON,
				)
			case .Failed:
				fmt.printf("FAIL %s: %s\n", case_result.name, case_result.error)
			}
		}
		fmt.printf(
			"Test projects: %d, validated: %d, failed: %d, pending: %d, assertions pending: %d\n",
			result.summary.cases,
			result.summary.validated,
			result.summary.failed,
			result.summary.pending,
			result.summary.pending_assertions,
		)
		if result.summary.pending > 0 {
			fmt.println("Execution: pending Luau/native Odin bridge")
		}
	case .JSON:
		fmt.print(`{"ok":`)
		if result.summary.failed == 0 {
			fmt.print(`true`)
		} else {
			fmt.print(`false`)
		}
		fmt.print(`,"execution":"`)
		json_print(TEST_PENDING_EXECUTION_REASON, false)
		fmt.print(`","tests":[`)
		for case_result, index in result.cases {
			if index > 0 {
				fmt.print(`,`)
			}
			fmt.print(`{"name":"`)
			json_print(case_result.name, false)
			fmt.print(`","path":"`)
			json_print(case_result.path, false)
			fmt.print(`","status":"`)
			print_test_case_status_json(case_result.status)
			fmt.printf(`","frames":%d,"dt":%g,"expectations":%d,"input_frames":%d`, case_result.frames, case_result.delta_seconds, case_result.expectations, case_result.input_frames)
			if case_result.error != "" {
				fmt.print(`,"error":"`)
				json_print(case_result.error, false)
				fmt.print(`"`)
			}
			fmt.print(`}`)
		}
		fmt.print(`],"summary":{`)
		fmt.printf(
			`"cases":%d,"validated":%d,"failed":%d,"pending":%d,"assertions":%d,"pending_assertions":%d`,
			result.summary.cases,
			result.summary.validated,
			result.summary.failed,
			result.summary.pending,
			result.summary.assertions,
			result.summary.pending_assertions,
		)
		fmt.println(`}}`)
	}
}

print_test_case_status_json :: proc(status: Test_Case_Status) {
	switch status {
	case .Pending:
		fmt.print(`pending`)
	case .Failed:
		fmt.print(`failed`)
	}
}

print_test_command_error :: proc(err: Test_Command_Error, target_path: string, format: Check_Output_Format) {
	message := test_command_error_message(err)
	switch format {
	case .Text:
		fmt.eprintf("%s: %s\n", target_path, message)
	case .JSON:
		fmt.eprint(`{"ok":false,"error":"`)
		json_print(test_command_error_code(err), true)
		fmt.eprint(`","message":"`)
		json_print(message, true)
		fmt.eprint(`","root":"`)
		json_print(target_path, true)
		fmt.eprintln(`"}`)
	}
}

test_command_error_message :: proc(err: Test_Command_Error) -> string {
	switch err {
	case .None:
		return "ok"
	case .Discovery_Failed:
		return "failed to discover Scrapbot test projects"
	case .No_Test_Projects:
		return "no Scrapbot test projects found"
	}
	return "unknown test command error"
}

test_command_error_code :: proc(err: Test_Command_Error) -> string {
	switch err {
	case .None:
		return "None"
	case .Discovery_Failed:
		return "DiscoveryFailed"
	case .No_Test_Projects:
		return "NoTestProjects"
	}
	return "Unknown"
}
