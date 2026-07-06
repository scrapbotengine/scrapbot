package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

TEST_MANIFEST_NAME :: "test.scrapbot.toml"
TEST_DEFAULT_ROOT :: "tests/projects"
Test_Command_Error :: enum {
	None,
	Discovery_Failed,
	No_Test_Projects,
}

Test_Case_Status :: enum {
	Passed,
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

Test_Expected_Value :: struct {
	value_type:   Runtime_Field_Type,
	boolean:      bool,
	int_value:    int,
	float:        f32,
	vec3:         [3]f32,
	string_value: string,
}

Test_Expectation :: struct {
	entity:    string,
	component: string,
	field:     string,
	expected:  Test_Expected_Value,
}

Test_Editor_Expectation :: struct {
	selected_entity: string,
}

Test_Manifest :: struct {
	frames:              int,
	delta_seconds:       f32,
	input_frames:        [dynamic]Step_Input_Frame,
	expectations:        [dynamic]Test_Expectation,
	editor_expectations: [dynamic]Test_Editor_Expectation,
}

Test_Case_Result :: struct {
	name:              string,
	path:              string,
	status:            Test_Case_Status,
	frames:            int,
	completed_frames:  int,
	delta_seconds:     f32,
	expectations:      int,
	input_frames:      int,
	failed_assertions: int,
	error:             string,
	assertion_errors:  [dynamic]string,
}

Test_Suite_Summary :: struct {
	cases:              int,
	validated:          int,
	failed:             int,
	pending:            int,
	assertions:         int,
	failed_assertions:  int,
}

Test_Command_Result :: struct {
	cases:   [dynamic]Test_Case_Result,
	summary: Test_Suite_Summary,
}

Test_Manifest_Section :: enum {
	Root,
	Expect_Field,
	Expect_Editor,
	Input_Frame,
}

Test_Manifest_Expectation_State :: struct {
	active:        bool,
	entity:        string,
	component:     string,
	field:         string,
	expected:      Test_Expected_Value,
	has_expected:  bool,
}

Test_Manifest_Input_State :: struct {
	active: bool,
	frame:  int,
	input:  Frame_Input,
}

Test_Manifest_Editor_Expectation_State :: struct {
	active:          bool,
	selected_entity: string,
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
		case_result := run_test_case(project_path)
		append(&result.cases, case_result)
		result.summary.cases += 1
		result.summary.assertions += case_result.expectations
		result.summary.failed_assertions += case_result.failed_assertions
		if case_result.status == .Failed {
			result.summary.failed += 1
		} else {
			result.summary.validated += 1
		}
	}

	return result, .None
}

run_test_case :: proc(project_path: string) -> Test_Case_Result {
	name := test_case_name_from_path(project_path)
	path := strings.clone(project_path)
	result := Test_Case_Result{
		name = name,
		path = path,
		status = .Passed,
		assertion_errors = make([dynamic]string),
	}

	manifest, manifest_ok := load_test_manifest(project_path)
	defer free_test_manifest(manifest)
	if !manifest_ok {
		result.status = .Failed
		result.error = strings.clone("invalid test manifest")
		return result
	}
	result.frames = manifest.frames
	result.delta_seconds = manifest.delta_seconds
	result.expectations = len(manifest.expectations) + len(manifest.editor_expectations)
	result.input_frames = len(manifest.input_frames)

	check := check_project(project_path)
	defer free_check_result(check)
	if check.err != .None {
		result.status = .Failed
		result.error = strings.clone(project_error_message(check.err))
		return result
	}

	simulation := run_script_simulation_with_input(&check, manifest.frames, manifest.delta_seconds, manifest.input_frames[:])
	result.completed_frames = simulation.completed_frames
	if !simulation.ok {
		result.status = .Failed
		if simulation.diagnostic.message != "" {
			result.error = strings.clone(simulation.diagnostic.message)
		} else {
			result.error = strings.clone("runtime error")
		}
		return result
	}

	for expectation in manifest.expectations {
		if !test_expectation_matches(check.scene.world, expectation) {
			result.failed_assertions += 1
			append(&result.assertion_errors, test_expectation_failure_message(check.scene.world, expectation))
		}
	}
	for expectation in manifest.editor_expectations {
		if !test_editor_expectation_matches(check.scene.world, simulation.editor_state, expectation) {
			result.failed_assertions += 1
			append(&result.assertion_errors, test_editor_expectation_failure_message(check.scene.world, simulation.editor_state, expectation))
		}
	}
	if result.failed_assertions > 0 {
		result.status = .Failed
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
	manifest, ok := load_test_manifest(project_path)
	defer free_test_manifest(manifest)
	if !ok {
		return {}, false
	}
	return test_manifest_summary(manifest), true
}

load_test_manifest :: proc(project_path: string) -> (Test_Manifest, bool) {
	manifest_path := project_relative_path(project_path, TEST_MANIFEST_NAME)
	defer delete(manifest_path)
	contents, read_err := os.read_entire_file(manifest_path, context.allocator)
	if read_err != nil {
		return {}, false
	}
	defer delete(contents)
	return parse_test_manifest(string(contents))
}

test_manifest_summary :: proc(manifest: Test_Manifest) -> Test_Manifest_Summary {
	return Test_Manifest_Summary{
		frames = manifest.frames,
		delta_seconds = manifest.delta_seconds,
		expectations = len(manifest.expectations) + len(manifest.editor_expectations),
		input_frames = len(manifest.input_frames),
	}
}

parse_test_manifest_summary :: proc(contents: string) -> (Test_Manifest_Summary, bool) {
	manifest, ok := parse_test_manifest(contents)
	defer free_test_manifest(manifest)
	if !ok {
		return {}, false
	}
	return test_manifest_summary(manifest), true
}

parse_test_manifest :: proc(contents: string) -> (Test_Manifest, bool) {
	manifest := Test_Manifest{
		frames = DEFAULT_STEP_FRAMES,
		delta_seconds = DEFAULT_STEP_DELTA_SECONDS,
		input_frames = make([dynamic]Step_Input_Frame),
		expectations = make([dynamic]Test_Expectation),
		editor_expectations = make([dynamic]Test_Editor_Expectation),
	}
	section := Test_Manifest_Section.Root
	expect := Test_Manifest_Expectation_State{}
	input := Test_Manifest_Input_State{}
	editor_expect := Test_Manifest_Editor_Expectation_State{}

	finish_expect := proc(manifest: ^Test_Manifest, expect: ^Test_Manifest_Expectation_State) -> bool {
		if !expect.active {
			return true
		}
		ok := expect.entity != "" && expect.component != "" && expect.field != "" && expect.has_expected
		if ok {
			append(&manifest.expectations, Test_Expectation{
				entity = expect.entity,
				component = expect.component,
				field = expect.field,
				expected = expect.expected,
			})
		} else {
			free_test_expectation_state(expect^)
		}
		expect^ = {}
		return ok
	}
	finish_editor_expect := proc(manifest: ^Test_Manifest, expect: ^Test_Manifest_Editor_Expectation_State) -> bool {
		if !expect.active {
			return true
		}
		ok := expect.selected_entity != ""
		if ok {
			append(&manifest.editor_expectations, Test_Editor_Expectation{
				selected_entity = expect.selected_entity,
			})
		} else {
			free_test_editor_expectation_state(expect^)
		}
		expect^ = {}
		return ok
	}
	finish_input := proc(manifest: ^Test_Manifest, input: ^Test_Manifest_Input_State) -> bool {
		if !input.active {
			return true
		}
		ok := input.frame > 0
		if ok {
			for existing in manifest.input_frames {
				if existing.frame == input.frame {
					ok = false
					break
				}
			}
		}
		if ok {
			append(&manifest.input_frames, Step_Input_Frame{frame = input.frame, input = input.input})
		}
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
			if !finish_expect(&manifest, &expect) || !finish_editor_expect(&manifest, &editor_expect) || !finish_input(&manifest, &input) {
				free_test_manifest(manifest)
				return {}, false
			}
			section = .Expect_Field
			expect.active = true
			continue
		}
		if trimmed == "[[expect.editor]]" {
			if !finish_expect(&manifest, &expect) || !finish_editor_expect(&manifest, &editor_expect) || !finish_input(&manifest, &input) {
				free_test_manifest(manifest)
				return {}, false
			}
			section = .Expect_Editor
			editor_expect.active = true
			continue
		}
		if trimmed == "[[input.frame]]" {
			if !finish_expect(&manifest, &expect) || !finish_editor_expect(&manifest, &editor_expect) || !finish_input(&manifest, &input) {
				free_test_manifest(manifest)
				return {}, false
			}
			section = .Input_Frame
			input.active = true
			input.input = frame_input_default()
			continue
		}
		if strings.has_prefix(trimmed, "[") {
			free_test_manifest(manifest)
			return {}, false
		}

		key, value, key_ok := read_manifest_key_value(trimmed)
		if !key_ok {
			free_test_manifest(manifest)
			return {}, false
		}
		switch section {
		case .Root:
			if !parse_test_manifest_root_key(&manifest, key, value) {
				free_test_manifest(manifest)
				return {}, false
			}
		case .Expect_Field:
			if !parse_test_manifest_expect_key(&expect, key, value) {
				free_test_manifest(manifest)
				free_test_expectation_state(expect)
				free_test_editor_expectation_state(editor_expect)
				return {}, false
			}
		case .Expect_Editor:
			if !parse_test_manifest_editor_expect_key(&editor_expect, key, value) {
				free_test_manifest(manifest)
				free_test_expectation_state(expect)
				free_test_editor_expectation_state(editor_expect)
				return {}, false
			}
		case .Input_Frame:
			if !parse_test_manifest_input_key(&input, key, value) {
				free_test_manifest(manifest)
				free_test_expectation_state(expect)
				free_test_editor_expectation_state(editor_expect)
				return {}, false
			}
		}
	}

	if !finish_expect(&manifest, &expect) || !finish_editor_expect(&manifest, &editor_expect) || !finish_input(&manifest, &input) {
		free_test_manifest(manifest)
		return {}, false
	}
	if manifest.frames <= 0 || manifest.delta_seconds <= 0 || (len(manifest.expectations) + len(manifest.editor_expectations)) == 0 {
		free_test_manifest(manifest)
		return {}, false
	}
	return manifest, true
}

parse_test_manifest_root_key :: proc(manifest: ^Test_Manifest, key, value: string) -> bool {
	switch key {
	case "frames":
		frames, ok := parse_positive_int(value)
		if !ok {
			return false
		}
		manifest.frames = frames
		return true
	case "dt", "delta_seconds":
		delta_seconds, ok := parse_positive_f32(value)
		if !ok {
			return false
		}
		manifest.delta_seconds = delta_seconds
		return true
	}
	return false
}

parse_test_manifest_expect_key :: proc(expect: ^Test_Manifest_Expectation_State, key, value: string) -> bool {
	switch key {
	case "entity", "component", "field":
		parsed, owned, ok := parse_basic_string_unescaped(value)
		if !ok || parsed == "" {
			if owned != "" {
				delete(owned)
			}
			return false
			}
			cloned := ""
			if owned != "" {
				cloned = owned
			} else {
				clone_ok: bool
				cloned, clone_ok = clone_test_string(parsed)
				if !clone_ok {
					return false
				}
			}
		switch key {
		case "entity":
			if expect.entity != "" {
				delete(cloned)
				return false
			}
			expect.entity = cloned
		case "component":
			if expect.component != "" {
				delete(cloned)
				return false
			}
			expect.component = cloned
		case "field":
			if expect.field != "" {
				delete(cloned)
				return false
			}
			expect.field = cloned
		}
		return true
	case "equals_bool":
		if value != "true" && value != "false" {
			return false
		}
		if expect.has_expected {
			return false
		}
		expect.expected = Test_Expected_Value{value_type = .Boolean, boolean = value == "true"}
		expect.has_expected = true
		return true
	case "equals_int":
		parsed, ok := strconv.parse_int(value, 10)
		if !ok {
			return false
		}
		if expect.has_expected {
			return false
		}
		expect.expected = Test_Expected_Value{value_type = .Int, int_value = int(parsed)}
		expect.has_expected = true
		return true
	case "equals_float":
		parsed, ok := strconv.parse_f32(value)
		if !ok || !test_float_is_finite(parsed) {
			return false
		}
		if expect.has_expected {
			return false
		}
		expect.expected = Test_Expected_Value{value_type = .Float, float = parsed}
		expect.has_expected = true
		return true
	case "equals_vec3":
		parsed, ok := parse_test_manifest_vec3_value(value)
		if !ok {
			return false
		}
		if expect.has_expected {
			return false
		}
		expect.expected = Test_Expected_Value{value_type = .Vec3, vec3 = parsed}
		expect.has_expected = true
		return true
	case "equals_string":
		parsed, owned, ok := parse_basic_string_unescaped(value)
		if !ok {
			if owned != "" {
				delete(owned)
			}
			return false
		}
		if expect.has_expected {
			if owned != "" {
				delete(owned)
			}
			return false
		}
		expected := owned
		if expected == "" {
			clone_ok: bool
			expected, clone_ok = clone_test_string(parsed)
			if !clone_ok {
				return false
			}
		}
		expect.expected = Test_Expected_Value{value_type = .String, string_value = expected}
		expect.has_expected = true
		return true
	}
	return false
}

parse_test_manifest_editor_expect_key :: proc(expect: ^Test_Manifest_Editor_Expectation_State, key, value: string) -> bool {
	switch key {
	case "selected_entity":
		parsed, owned, ok := parse_basic_string_unescaped(value)
		if !ok || parsed == "" {
			if owned != "" {
				delete(owned)
			}
			return false
		}
		if expect.selected_entity != "" {
			if owned != "" {
				delete(owned)
			}
			return false
		}
		if owned != "" {
			expect.selected_entity = owned
		} else {
			clone_ok: bool
			expect.selected_entity, clone_ok = clone_test_string(parsed)
			if !clone_ok {
				return false
			}
		}
		return true
	}
	return false
}

parse_test_manifest_input_key :: proc(input: ^Test_Manifest_Input_State, key, value: string) -> bool {
	switch key {
	case "frame":
		frame, ok := parse_positive_int(value)
		if !ok {
			return false
		}
		if input.frame > 0 {
			return false
		}
		input.frame = frame
		return true
	case "ui_visible":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.ui_visible = parsed
		return true
	case "debug_overlay_visible", "editor_visible":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.debug_overlay_visible = parsed
		return true
	case "viewport":
		parsed, ok := parse_test_manifest_vec2_value(value)
		if !ok {
			return false
		}
		input.input.viewport_width = parsed[0]
		input.input.viewport_height = parsed[1]
		return true
	case "pixel_scale":
		parsed, ok := strconv.parse_f32(value)
		if !ok || !test_float_is_finite(parsed) || parsed <= 0 {
			return false
		}
		input.input.pixel_scale = parsed
		return true
	case "pointer", "pointer_position":
		parsed, ok := parse_test_manifest_vec2_value(value)
		if !ok {
			return false
		}
		input.input.pointer.position = parsed
		input.input.pointer.has_position = true
		return true
	case "pointer_delta", "delta":
		parsed, ok := parse_test_manifest_vec2_value(value)
		if !ok {
			return false
		}
		input.input.pointer.delta = parsed
		return true
	case "pointer_has_position":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.has_position = parsed
		return true
	case "wheel", "wheel_delta":
		parsed, ok := parse_test_manifest_vec2_value(value)
		if !ok {
			return false
		}
		input.input.pointer.wheel_delta = parsed
		return true
	case "primary_down", "primary_held":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.primary_down = parsed
		return true
	case "primary_pressed":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.primary_pressed = parsed
		return true
	case "primary_released":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.primary_released = parsed
		return true
	case "secondary_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.secondary_down = parsed
		return true
	case "secondary_pressed":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.secondary_pressed = parsed
		return true
	case "secondary_released":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.pointer.secondary_released = parsed
		return true
	case "ctrl_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.ctrl_down = parsed
		input.input.keyboard.move_down = parsed
		return true
	case "shift_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.shift_down = parsed
		return true
	case "alt_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.alt_down = parsed
		return true
	case "super_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.super_down = parsed
		return true
	case "move_forward":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_forward = parsed
		return true
	case "move_back":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_back = parsed
		return true
	case "move_left":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_left = parsed
		return true
	case "move_right":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_right = parsed
		return true
	case "move_up":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_up = parsed
		return true
	case "move_down":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.move_down = parsed
		return true
	case "editor_toggle_pressed":
		parsed, ok := parse_test_manifest_bool(value)
		if !ok {
			return false
		}
		input.input.keyboard.editor_toggle_pressed = parsed
		return true
	case "system_profile_count_hint":
		hint, ok := parse_positive_int(value)
		if !ok {
			return false
		}
		input.input.system_profile_count_hint = hint
		return ok
	}
	return false
}

parse_test_manifest_bool :: proc(value: string) -> (bool, bool) {
	if value == "true" {
		return true, true
	}
	if value == "false" {
		return false, true
	}
	return false, false
}

parse_test_manifest_float :: proc(value: string) -> bool {
	parsed, ok := strconv.parse_f32(value)
	if !ok || !test_float_is_finite(parsed) {
		return false
	}
	return true
}

parse_test_manifest_vec2_value :: proc(value: string) -> ([2]f32, bool) {
	if len(value) < 5 || value[0] != '[' || value[len(value) - 1] != ']' {
		return {}, false
	}
	result: [2]f32
	count := 0
	inner := value[1:len(value) - 1]
	remaining := inner
	for part in strings.split_iterator(&remaining, ",") {
		if count >= 2 {
			return {}, false
		}
		trimmed := strings.trim_space(part)
		parsed, ok := strconv.parse_f32(trimmed)
		if trimmed == "" || !ok || !test_float_is_finite(parsed) {
			return {}, false
		}
		result[count] = parsed
		count += 1
	}
	return result, count == 2
}

parse_test_manifest_vec3_value :: proc(value: string) -> ([3]f32, bool) {
	if len(value) < 7 || value[0] != '[' || value[len(value) - 1] != ']' {
		return {}, false
	}
	result: [3]f32
	count := 0
	inner := value[1:len(value) - 1]
	remaining := inner
	for part in strings.split_iterator(&remaining, ",") {
		if count >= 3 {
			return {}, false
		}
		trimmed := strings.trim_space(part)
		parsed, ok := strconv.parse_f32(trimmed)
		if trimmed == "" || !ok || !test_float_is_finite(parsed) {
			return {}, false
		}
		result[count] = parsed
		count += 1
	}
	return result, count == 3
}

test_float_is_finite :: proc(value: f32) -> bool {
	return value == value && value <= 3.4028234663852886e38 && value >= -3.4028234663852886e38
}

clone_test_string :: proc(value: string) -> (string, bool) {
	owned, err := strings.clone(value)
	if err != nil {
		return "", false
	}
	return owned, true
}

free_test_manifest :: proc(manifest: Test_Manifest) {
	for expectation in manifest.expectations {
		free_test_expectation(expectation)
	}
	for expectation in manifest.editor_expectations {
		free_test_editor_expectation(expectation)
	}
	if manifest.expectations != nil {
		delete(manifest.expectations)
	}
	if manifest.editor_expectations != nil {
		delete(manifest.editor_expectations)
	}
	if manifest.input_frames != nil {
		delete(manifest.input_frames)
	}
}

free_test_expectation :: proc(expectation: Test_Expectation) {
	if expectation.entity != "" {
		delete(expectation.entity)
	}
	if expectation.component != "" {
		delete(expectation.component)
	}
	if expectation.field != "" {
		delete(expectation.field)
	}
	free_test_expected_value(expectation.expected)
}

free_test_editor_expectation :: proc(expectation: Test_Editor_Expectation) {
	if expectation.selected_entity != "" {
		delete(expectation.selected_entity)
	}
}

free_test_expectation_state :: proc(expect: Test_Manifest_Expectation_State) {
	if expect.entity != "" {
		delete(expect.entity)
	}
	if expect.component != "" {
		delete(expect.component)
	}
	if expect.field != "" {
		delete(expect.field)
	}
	if expect.has_expected {
		free_test_expected_value(expect.expected)
	}
}

free_test_editor_expectation_state :: proc(expect: Test_Manifest_Editor_Expectation_State) {
	if expect.selected_entity != "" {
		delete(expect.selected_entity)
	}
}

free_test_expected_value :: proc(value: Test_Expected_Value) {
	if value.value_type == .String && value.string_value != "" {
		delete(value.string_value)
	}
}

test_expectation_matches :: proc(world: Runtime_World, expectation: Test_Expectation) -> bool {
	entity, entity_found := runtime_world_find_entity_by_id(world, expectation.entity)
	if !entity_found {
		return false
	}
	actual, actual_err := runtime_world_get_component_field_value(world, entity, expectation.component, expectation.field)
	if actual_err != .None {
		return false
	}
	return test_expected_value_matches(expectation.expected, actual)
}

test_editor_expectation_matches :: proc(world: Runtime_World, editor_state: Editor_Test_Input_State, expectation: Test_Editor_Expectation) -> bool {
	selected, selected_ok := editor_test_selected_entity_id(editor_state, world)
	return selected_ok && selected == expectation.selected_entity
}

test_expected_value_matches :: proc(expected: Test_Expected_Value, actual: Runtime_Component_Value) -> bool {
	if expected.value_type != actual.value_type {
		return false
	}
	switch expected.value_type {
	case .Boolean:
		return expected.boolean == actual.boolean
	case .Int:
		return expected.int_value == actual.int_value
	case .Float:
		return test_float_approx_equal(expected.float, actual.float)
	case .Vec3:
		return test_float_approx_equal(expected.vec3[0], actual.vec3[0]) &&
			test_float_approx_equal(expected.vec3[1], actual.vec3[1]) &&
			test_float_approx_equal(expected.vec3[2], actual.vec3[2])
	case .String:
		return expected.string_value == actual.string_value
	}
	return false
}

test_float_approx_equal :: proc(left, right: f32) -> bool {
	diff := left - right
	if diff < 0 {
		diff = -diff
	}
	return diff <= 0.0001
}

test_expectation_failure_message :: proc(world: Runtime_World, expectation: Test_Expectation) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, expectation.entity)
	strings.write_rune(&builder, '.')
	strings.write_string(&builder, expectation.component)
	strings.write_rune(&builder, '.')
	strings.write_string(&builder, expectation.field)
	strings.write_string(&builder, ": expected ")
	append_test_expected_value_text(&builder, expectation.expected)

	entity, entity_found := runtime_world_find_entity_by_id(world, expectation.entity)
	if !entity_found {
		strings.write_string(&builder, ", got UnknownEntity")
		return strings.clone(strings.to_string(builder))
	}
	actual, actual_err := runtime_world_get_component_field_value(world, entity, expectation.component, expectation.field)
	if actual_err != .None {
		strings.write_string(&builder, ", got ")
		strings.write_string(&builder, runtime_error_label(actual_err))
		return strings.clone(strings.to_string(builder))
	}
	strings.write_string(&builder, ", got ")
	append_test_component_value_text(&builder, actual)
	return strings.clone(strings.to_string(builder))
}

test_editor_expectation_failure_message :: proc(world: Runtime_World, editor_state: Editor_Test_Input_State, expectation: Test_Editor_Expectation) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "editor.selected_entity: expected \"")
	strings.write_string(&builder, expectation.selected_entity)
	strings.write_rune(&builder, '"')
	if actual, ok := editor_test_selected_entity_id(editor_state, world); ok {
		strings.write_string(&builder, ", got \"")
		strings.write_string(&builder, actual)
		strings.write_rune(&builder, '"')
	} else {
		strings.write_string(&builder, ", got none")
	}
	return strings.clone(strings.to_string(builder))
}

append_test_expected_value_text :: proc(builder: ^strings.Builder, value: Test_Expected_Value) {
	switch value.value_type {
	case .Boolean:
		if value.boolean {
			strings.write_string(builder, "true")
		} else {
			strings.write_string(builder, "false")
		}
	case .Int:
		append_test_format(builder, "%d", value.int_value)
	case .Float:
		append_test_format(builder, "%g", value.float)
	case .Vec3:
		strings.write_rune(builder, '[')
		append_test_format(builder, "%g", value.vec3[0])
		strings.write_string(builder, ", ")
		append_test_format(builder, "%g", value.vec3[1])
		strings.write_string(builder, ", ")
		append_test_format(builder, "%g", value.vec3[2])
		strings.write_rune(builder, ']')
	case .String:
		strings.write_rune(builder, '"')
		strings.write_string(builder, value.string_value)
		strings.write_rune(builder, '"')
	}
}

append_test_component_value_text :: proc(builder: ^strings.Builder, value: Runtime_Component_Value) {
	switch value.value_type {
	case .Boolean:
		if value.boolean {
			strings.write_string(builder, "true")
		} else {
			strings.write_string(builder, "false")
		}
	case .Int:
		append_test_format(builder, "%d", value.int_value)
	case .Float:
		append_test_format(builder, "%g", value.float)
	case .Vec3:
		strings.write_rune(builder, '[')
		append_test_format(builder, "%g", value.vec3[0])
		strings.write_string(builder, ", ")
		append_test_format(builder, "%g", value.vec3[1])
		strings.write_string(builder, ", ")
		append_test_format(builder, "%g", value.vec3[2])
		strings.write_rune(builder, ']')
	case .String:
		strings.write_rune(builder, '"')
		strings.write_string(builder, value.string_value)
		strings.write_rune(builder, '"')
	}
}

append_test_format :: proc(builder: ^strings.Builder, format: string, args: ..any) {
	buffer: [128]u8
	text := fmt.bprintf(buffer[:], format, ..args)
	strings.write_string(builder, text)
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
		for assertion_error in case_result.assertion_errors {
			if assertion_error != "" {
				delete(assertion_error)
			}
		}
		if case_result.assertion_errors != nil {
			delete(case_result.assertion_errors)
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
			case .Passed:
				fmt.printf("PASS %s (%d assertions)\n", case_result.name, case_result.expectations)
			case .Failed:
				if case_result.error != "" {
					fmt.printf("FAIL %s: %s\n", case_result.name, case_result.error)
				} else {
					fmt.printf("FAIL %s\n", case_result.name)
				}
				for assertion_error in case_result.assertion_errors {
					fmt.printf("  - %s\n", assertion_error)
				}
			}
		}
		fmt.printf(
			"Test projects: %d passed, %d failed, %d assertions",
			result.summary.validated,
			result.summary.failed,
			result.summary.assertions,
		)
		if result.summary.failed_assertions > 0 {
			fmt.printf(", %d failed", result.summary.failed_assertions)
		}
		fmt.println()
	case .JSON:
		fmt.print(`{"ok":`)
		if result.summary.failed == 0 {
			fmt.print(`true`)
		} else {
			fmt.print(`false`)
		}
		fmt.print(`,"execution":"odin_luau_systems","tests":[`)
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
			fmt.printf(`","frames":%d,"completed_frames":%d,"dt":%g,"expectations":%d,"failed_assertions":%d,"input_frames":%d`, case_result.frames, case_result.completed_frames, case_result.delta_seconds, case_result.expectations, case_result.failed_assertions, case_result.input_frames)
			if case_result.error != "" {
				fmt.print(`,"error":"`)
				json_print(case_result.error, false)
				fmt.print(`"`)
			}
			if len(case_result.assertion_errors) > 0 {
				fmt.print(`,"assertion_errors":[`)
				for assertion_error, error_index in case_result.assertion_errors {
					if error_index > 0 {
						fmt.print(`,`)
					}
					fmt.print(`"`)
					json_print(assertion_error, false)
					fmt.print(`"`)
				}
				fmt.print(`]`)
			}
			fmt.print(`}`)
		}
		fmt.print(`],"summary":{`)
		fmt.printf(
			`"cases":%d,"passed":%d,"failed":%d,"pending":%d,"assertions":%d,"failed_assertions":%d`,
			result.summary.cases,
			result.summary.validated,
			result.summary.failed,
			result.summary.pending,
			result.summary.assertions,
			result.summary.failed_assertions,
		)
		fmt.println(`}}`)
	}
}

print_test_case_status_json :: proc(status: Test_Case_Status) {
	switch status {
	case .Passed:
		fmt.print(`passed`)
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
