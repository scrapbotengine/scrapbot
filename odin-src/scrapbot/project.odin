package main

import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

PROJECT_FILE_NAME :: "project.toml"
LEGACY_PROJECT_FILE_NAME :: "project.scrapbot.toml"

Check_Output_Format :: enum {
	Text,
	JSON,
}

Project_Error :: enum {
	None,
	Missing_Project_File,
	Invalid_Project_Name,
	Unsupported_Project_Version,
	Invalid_Default_Scene,
	Missing_Default_Scene,
	Invalid_Script,
	Missing_Script,
	Invalid_Native,
	Missing_Native,
	Invalid_Native_Artifact,
	Missing_Native_Artifact,
}

Project :: struct {
	root_path:        string,
	metadata_path:    string,
	name:             string,
	default_scene:    string,
	scripts:          []string,
	native:           string,
	native_artifact:  string,
	metadata_storage: []byte,
}

Project_Check_Result :: struct {
	project: Project,
	err:     Project_Error,
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

	for script_path in project.scripts {
		full_path := project_relative_path(project.root_path, script_path)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Script}
		}
	}

	if project.native != "" {
		full_path := project_relative_path(project.root_path, project.native)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Native}
		}
	}

	if project.native_artifact != "" {
		full_path := project_relative_path(project.root_path, project.native_artifact)
		defer delete(full_path)
		if !os.exists(full_path) {
			return Project_Check_Result{project = project, err = .Missing_Native_Artifact}
		}
	}

	return Project_Check_Result{project = project}
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
	name, name_ok := read_required_string(text, "name")
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

	return Project{
		root_path = root_path,
		metadata_path = metadata_name,
		name = name,
		default_scene = default_scene,
		scripts = scripts,
		native = native,
		native_artifact = native_artifact,
		metadata_storage = contents,
	}, .None
}

free_project :: proc(project: Project) {
	if project.scripts != nil {
		delete(project.scripts)
	}
	if project.metadata_storage != nil {
		delete(project.metadata_storage)
	}
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
		parsed, ok := strconv.parse_int(value, 10)
		return parsed, ok
	}
	return 0, false
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
	if strings.contains(inner, "\\") || strings.contains(inner, "\"") {
		return "", false
	}
	return inner, true
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
			return nil, false
		}
		end := string_end_index(remaining)
		if end < 0 {
			return nil, false
		}
		item, ok := parse_basic_string(remaining[:end + 1])
		if !ok {
			return nil, false
		}
		append(&items, item)
		remaining = strings.trim_space(remaining[end + 1:])
		if remaining == "" {
			break
		}
		if remaining[0] != ',' {
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

project_error_message :: proc(err: Project_Error) -> string {
	switch err {
	case .None:
		return "ok"
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
	}
	return "unknown project error"
}
