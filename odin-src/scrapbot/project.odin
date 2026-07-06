package main

import "core:os"
import "core:path/filepath"
import "core:strings"

PROJECT_FILE_NAME :: "project.toml"
LEGACY_PROJECT_FILE_NAME :: "project.scrapbot.toml"

Check_Output_Format :: enum {
	Text,
	JSON,
}

Project_Error :: enum {
	None,
	Already_Exists,
	Io_Error,
	Missing_Project_File,
	Invalid_Project_Name,
	Unsupported_Project_Version,
	Invalid_Default_Scene,
	Missing_Default_Scene,
	Unsupported_Scene_Version,
	Invalid_Scene,
	Duplicate_Scene_Entity_ID,
	Missing_Scene_Content,
	Invalid_Script,
	Missing_Script,
	Invalid_Native,
	Missing_Native,
	Invalid_Native_Artifact,
	Missing_Native_Artifact,
	Invalid_Build_Output,
}

Project :: struct {
	root_path:        string,
	metadata_path:    string,
	name:             string,
	default_scene:    string,
	scripts:          []string,
	native:           string,
	native_artifact:  string,
	name_storage:     string,
	metadata_storage: []byte,
}

Project_Check_Result :: struct {
	project:               Project,
	registry:              Runtime_Component_Registry,
	script_program:        Script_Program,
	scene:                 Scene,
	startup_schedule:      Runtime_System_Schedule,
	update_schedule:       Runtime_System_Schedule,
	fixed_update_schedule: Runtime_System_Schedule,
	render_schedule:       Runtime_System_Schedule,
	diagnostic:            Script_Diagnostic,
	err:                   Project_Error,
}

check_project :: proc(root_path: string) -> Project_Check_Result {
	project, err := load_project(root_path)
	if err != .None {
		return Project_Check_Result{err = err}
	}

	default_scene_path := project_relative_path(project.root_path, project.default_scene)
	defer delete(default_scene_path)
	if !os.exists(default_scene_path) {
		return Project_Check_Result{project = project, err = .Missing_Default_Scene}
	}

	registry := Runtime_Component_Registry{}
	keep_registry := false
	defer {
		if !keep_registry {
			runtime_registry_free(&registry)
		}
	}
	engine_err := runtime_register_engine_components(&registry)
	if engine_err != .None {
		return Project_Check_Result{project = project, err = .Invalid_Scene}
	}

	script_program := Script_Program{}
	keep_script_program := false
	defer {
		if !keep_script_program {
			script_program_free(&script_program)
		}
	}
	if len(project.scripts) > 0 {
		program, diagnostic, program_ok := script_program_init()
		if !program_ok {
			return Project_Check_Result{project = project, diagnostic = diagnostic, err = .Invalid_Script}
		}
		script_program = program
	}

	for script_path in project.scripts {
		full_path := project_relative_path(project.root_path, script_path)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Script}
		}
		script_result := script_program_load_file(&script_program, &registry, full_path, script_path)
		if script_result.err != .None {
			return Project_Check_Result{project = project, diagnostic = script_result.diagnostic, err = script_result.err}
		}
	}

	if project.native != "" {
		full_path := project_relative_path(project.root_path, project.native)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Native}
		}
		native_err := register_native_components_from_file(&registry, full_path)
		if native_err != .None {
			return Project_Check_Result{project = project, err = native_err}
		}
		native_exec_err := script_program_load_native_file(&script_program, full_path, project.native)
		if native_exec_err != .None {
			return Project_Check_Result{project = project, err = native_exec_err}
		}
	}

	if project.native_artifact != "" {
		full_path := project_relative_path(project.root_path, project.native_artifact)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Native_Artifact}
		}
	}

	scene, scene_err := load_scene_file(default_scene_path, registry)
	if scene_err != .None {
		return Project_Check_Result{project = project, scene = scene, err = scene_err}
	}

	startup_schedule, startup_schedule_err := runtime_build_system_schedule(registry, .Startup)
	if startup_schedule_err != .None {
		return Project_Check_Result{
			project = project,
			scene = scene,
			diagnostic = script_schedule_diagnostic(.Startup, "failed to build script schedule"),
			err = .Invalid_Script,
		}
	}
	update_schedule, update_schedule_err := runtime_build_system_schedule(registry, .Update)
	if update_schedule_err != .None {
		runtime_system_schedule_free(startup_schedule)
		return Project_Check_Result{
			project = project,
			scene = scene,
			diagnostic = script_schedule_diagnostic(.Update, "failed to build script schedule"),
			err = .Invalid_Script,
		}
	}
	fixed_update_schedule, fixed_update_schedule_err := runtime_build_system_schedule(registry, .Fixed_Update)
	if fixed_update_schedule_err != .None {
		runtime_system_schedule_free(update_schedule)
		runtime_system_schedule_free(startup_schedule)
		return Project_Check_Result{
			project = project,
			scene = scene,
			diagnostic = script_schedule_diagnostic(.Fixed_Update, "failed to build script schedule"),
			err = .Invalid_Script,
		}
	}
	render_schedule, render_schedule_err := runtime_build_system_schedule(registry, .Render)
	if render_schedule_err != .None {
		runtime_system_schedule_free(fixed_update_schedule)
		runtime_system_schedule_free(update_schedule)
		runtime_system_schedule_free(startup_schedule)
		return Project_Check_Result{
			project = project,
			scene = scene,
			diagnostic = script_schedule_diagnostic(.Render, "failed to build script schedule"),
			err = .Invalid_Script,
		}
	}

	keep_registry = true
	keep_script_program = true
	return Project_Check_Result{
		project = project,
		registry = registry,
		script_program = script_program,
		scene = scene,
		startup_schedule = startup_schedule,
		update_schedule = update_schedule,
		fixed_update_schedule = fixed_update_schedule,
		render_schedule = render_schedule,
	}
}

load_project :: proc(root_path: string) -> (Project, Project_Error) {
	metadata_name := project_metadata_file_name(root_path)
	if metadata_name == "" {
		return Project{}, .Missing_Project_File
	}

	metadata_path := project_relative_path(root_path, metadata_name)
	defer delete(metadata_path)
	contents, read_err := os.read_entire_file(metadata_path, context.allocator)
	if read_err != nil {
		return Project{}, .Missing_Project_File
	}

	text := string(contents)
	name, name_storage, name_ok := read_required_owned_string(text, "name")
	keep_name_storage := false
	defer {
		if !keep_name_storage && name_storage != "" {
			delete(name_storage)
		}
	}
	if !name_ok || name == "" {
		delete(contents)
		return Project{}, .Invalid_Project_Name
	}

	default_scene, default_scene_ok := read_required_string(text, "default_scene")
	if !default_scene_ok || !is_safe_project_relative_path(default_scene) {
		delete(contents)
		return Project{}, .Invalid_Default_Scene
	}

	version, version_ok := read_required_int(text, "version")
	if !version_ok || version != 1 {
		delete(contents)
		return Project{}, .Unsupported_Project_Version
	}

	scripts, scripts_ok := read_optional_string_array(text, "scripts")
	if !scripts_ok {
		delete(contents)
		return Project{}, .Invalid_Script
	}
	for script_path in scripts {
		if !is_safe_project_relative_path(script_path) {
			delete(scripts)
			delete(contents)
			return Project{}, .Invalid_Script
		}
	}

	native, native_ok := read_optional_string(text, "native")
	if !native_ok || (native != "" && !is_safe_project_relative_path(native)) {
		delete(scripts)
		delete(contents)
		return Project{}, .Invalid_Native
	}

	native_artifact, native_artifact_ok := read_optional_string(text, "native_artifact")
	if !native_artifact_ok || (native_artifact != "" && !is_safe_project_relative_path(native_artifact)) {
		delete(scripts)
		delete(contents)
		return Project{}, .Invalid_Native_Artifact
	}

	keep_name_storage = true
	return Project{
		root_path = root_path,
		metadata_path = metadata_name,
		name = name,
		default_scene = default_scene,
		scripts = scripts,
		native = native,
		native_artifact = native_artifact,
		name_storage = name_storage,
		metadata_storage = contents,
	}, .None
}

free_project :: proc(project: Project) {
	if project.scripts != nil {
		delete(project.scripts)
	}
	if project.name_storage != "" {
		delete(project.name_storage)
	}
	if project.metadata_storage != nil {
		delete(project.metadata_storage)
	}
}

free_check_result :: proc(result: Project_Check_Result) {
	diagnostic := result.diagnostic
	script_diagnostic_free(&diagnostic)
	script_program := result.script_program
	script_program_free(&script_program)
	registry := result.registry
	runtime_registry_free(&registry)
	free_project(result.project)
	free_scene(result.scene)
	runtime_system_schedule_free(result.startup_schedule)
	runtime_system_schedule_free(result.update_schedule)
	runtime_system_schedule_free(result.fixed_update_schedule)
	runtime_system_schedule_free(result.render_schedule)
}

project_metadata_file_name :: proc(root_path: string) -> string {
	canonical := project_relative_path(root_path, PROJECT_FILE_NAME)
	defer delete(canonical)
	if os.exists(canonical) {
		return PROJECT_FILE_NAME
	}
	legacy := project_relative_path(root_path, LEGACY_PROJECT_FILE_NAME)
	defer delete(legacy)
	if os.exists(legacy) {
		return LEGACY_PROJECT_FILE_NAME
	}
	return ""
}

project_relative_path :: proc(root_path, relative_path: string) -> string {
	joined, err := filepath.join([]string{root_path, relative_path})
	if err != nil {
		return ""
	}
	return joined
}

read_required_string :: proc(contents, key: string) -> (string, bool) {
	value, ok := read_optional_string(contents, key)
	return value, ok && value != ""
}

read_required_owned_string :: proc(contents, key: string) -> (value: string, owned: string, ok: bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		raw_value, found := read_key_value(line, key)
		if !found {
			continue
		}
		value, owned, ok = parse_basic_string_unescaped(raw_value)
		return value, owned, ok && value != ""
	}
	return "", "", false
}

read_optional_string :: proc(contents, key: string) -> (string, bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		value, found := read_key_value(line, key)
		if !found {
			continue
		}
		return parse_basic_string(value)
	}
	return "", true
}

read_optional_string_array :: proc(contents, key: string) -> ([]string, bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		value, found := read_key_value(line, key)
		if !found {
			continue
		}
		return parse_basic_string_array(value)
	}
	return nil, true
}

read_required_int :: proc(contents, key: string) -> (int, bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		value, found := read_key_value(line, key)
		if !found {
			continue
		}
		return parse_manifest_int(value)
	}
	return 0, false
}

parse_manifest_int :: proc(value: string) -> (int, bool) {
	result := 0
	if value == "" {
		return 0, false
	}
	for c in value {
		if c < '0' || c > '9' {
			return 0, false
		}
		result = result * 10 + int(c - '0')
	}
	return result, true
}

read_key_value :: proc(line, key: string) -> (string, bool) {
	without_comment := strip_line_comment(line)
	trimmed := strings.trim_space(without_comment)
	if trimmed == "" {
		return "", false
	}
	eq_index := strings.index_byte(trimmed, '=')
	if eq_index < 0 {
		return "", false
	}
	found_key := strings.trim_space(trimmed[:eq_index])
	if found_key != key {
		return "", false
	}
	return strings.trim_space(trimmed[eq_index + 1:]), true
}

strip_line_comment :: proc(line: string) -> string {
	in_string := false
	escaped := false
	for c, i in line {
		if escaped {
			escaped = false
			continue
		}
		if in_string && c == '\\' {
			escaped = true
			continue
		}
		if c == '"' {
			in_string = !in_string
			continue
		}
		if !in_string && c == '#' {
			return line[:i]
		}
	}
	return line
}

parse_basic_string :: proc(value: string) -> (string, bool) {
	if len(value) < 2 || value[0] != '"' || value[len(value) - 1] != '"' {
		return "", false
	}

	inner := value[1:len(value) - 1]
	escaped := false
	for c in inner {
		if escaped {
			switch c {
			case '"', '\\', 'n', 'r', 't':
				escaped = false
				continue
			case:
				return "", false
			}
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == '"' {
			return "", false
		}
	}
	return inner, !escaped
}

parse_basic_string_array :: proc(value: string) -> ([]string, bool) {
	if len(value) < 2 || value[0] != '[' || value[len(value) - 1] != ']' {
		return nil, false
	}

	inner := strings.trim_space(value[1:len(value) - 1])
	if inner == "" {
		return []string{}, true
	}

	items := make([dynamic]string)
	remaining := inner
	for {
		remaining = strings.trim_space(remaining)
		if remaining == "" {
			break
		}
		if remaining[0] != '"' {
			delete(items)
			return nil, false
		}
		end := string_end_index(remaining)
		if end < 0 {
			delete(items)
			return nil, false
		}
		item, ok := parse_basic_string(remaining[:end + 1])
		if !ok {
			delete(items)
			return nil, false
		}
		append(&items, item)
		remaining = strings.trim_space(remaining[end + 1:])
		if remaining == "" {
			break
		}
		if remaining[0] != ',' {
			delete(items)
			return nil, false
		}
		remaining = remaining[1:]
	}
	return items[:], true
}

string_end_index :: proc(value: string) -> int {
	escaped := false
	for c, i in value[1:] {
		real_index := i + 1
		if escaped {
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == '"' {
			return real_index
		}
	}
	return -1
}

is_safe_project_relative_path :: proc(path: string) -> bool {
	if path == "" || filepath.is_abs(path) || strings.contains(path, "\\") {
		return false
	}
	remaining := path
	for part in strings.split_iterator(&remaining, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

parse_basic_string_unescaped :: proc(value: string) -> (parsed: string, owned: string, ok: bool) {
	inner, valid := parse_basic_string(value)
	if !valid {
		return "", "", false
	}
	if !strings.contains(inner, "\\") {
		return inner, "", true
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	escaped := false
	for c in inner {
		if escaped {
			switch c {
			case '"':
				strings.write_rune(&builder, '"')
			case '\\':
				strings.write_rune(&builder, '\\')
			case 'n':
				strings.write_rune(&builder, '\n')
			case 'r':
				strings.write_rune(&builder, '\r')
			case 't':
				strings.write_rune(&builder, '\t')
			case:
				return "", "", false
			}
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		strings.write_rune(&builder, c)
	}
	if escaped {
		return "", "", false
	}
	owned = strings.clone(strings.to_string(builder))
	return owned, owned, true
}

project_error_message :: proc(err: Project_Error) -> string {
	switch err {
	case .None:
		return "ok"
	case .Already_Exists:
		return "project already exists"
	case .Io_Error:
		return "i/o error"
	case .Missing_Project_File:
		return "missing project.toml"
	case .Invalid_Project_Name:
		return "invalid project name"
	case .Unsupported_Project_Version:
		return "unsupported project version"
	case .Invalid_Default_Scene:
		return "invalid default scene"
	case .Missing_Default_Scene:
		return "missing default scene"
	case .Unsupported_Scene_Version:
		return "unsupported scene version"
	case .Invalid_Scene:
		return "invalid scene"
	case .Duplicate_Scene_Entity_ID:
		return "duplicate scene entity id"
	case .Missing_Scene_Content:
		return "missing scene content"
	case .Invalid_Script:
		return "invalid script path"
	case .Missing_Script:
		return "missing script"
	case .Invalid_Native:
		return "invalid native source path"
	case .Missing_Native:
		return "missing native source"
	case .Invalid_Native_Artifact:
		return "invalid native artifact path"
	case .Missing_Native_Artifact:
		return "missing native artifact"
	case .Invalid_Build_Output:
		return "invalid build output path"
	}
	return "unknown project error"
}
