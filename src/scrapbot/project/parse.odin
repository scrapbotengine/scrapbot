package project

import "core:fmt"
import "core:strconv"
import "core:strings"
import shared "../shared"

Parse_Error :: enum {
	None,
	Missing_Field,
	Invalid_Field,
	Invalid_Syntax,
	Invalid_Path,
}

Parse_Result :: struct {
	err:     Parse_Error,
	message: string,
}

ok :: proc() -> Parse_Result {
	return {}
}

fail :: proc(err: Parse_Error, message: string) -> Parse_Result {
	return Parse_Result{err = err, message = message}
}

parse_project_config :: proc(source: string) -> (config: Project_Config, result: Parse_Result) {
	text := source
	for raw_line in strings.split_lines_iterator(&text) {
		line := strip_comment(strings.trim_space(raw_line))
		if line == "" {
			continue
		}
		key, value, found := split_assignment(line)
		if !found {
			return config, fail(.Invalid_Syntax, fmt.tprintf("expected key/value assignment, got '%s'", line))
		}

		switch key {
		case "name":
			config.name, found = parse_basic_string(value)
			if !found {
				return config, fail(.Invalid_Field, "project name must be a basic string")
			}
		case "default_scene":
			config.default_scene, found = parse_basic_string(value)
			if !found || !is_safe_relative_path(config.default_scene) {
				return config, fail(.Invalid_Path, "default_scene must be a safe relative path")
			}
		case:
			return config, fail(.Invalid_Field, fmt.tprintf("unknown project field '%s'", key))
		}
	}

	if config.name == "" {
		return config, fail(.Missing_Field, "project.toml is missing name")
	}
	if config.default_scene == "" {
		return config, fail(.Missing_Field, "project.toml is missing default_scene")
	}
	return config, ok()
}

parse_scene :: proc(source: string) -> (scene: Scene, result: Parse_Result) {
	section := ""
	current: ^Scene_Entity
	current_component: ^Custom_Component

	text := source
	for raw_line in strings.split_lines_iterator(&text) {
		line := strip_comment(strings.trim_space(raw_line))
		if line == "" {
			continue
		}

		if line == "[[entities]]" {
			append(&scene.entities, Scene_Entity{})
			current = &scene.entities[len(scene.entities) - 1]
			section = "entity"
			continue
		}

		if line == "[entities.transform]" || line == "[entities.camera]" || line == "[entities.mesh]" {
			if current == nil {
				return scene, fail(.Invalid_Syntax, fmt.tprintf("%s appears before [[entities]]", line))
			}
			section = line[10:len(line) - 1]
			current_component = nil
			continue
		}

		component_name, is_component_section := parse_component_section(line)
		if is_component_section {
			if current == nil {
				return scene, fail(.Invalid_Syntax, fmt.tprintf("%s appears before [[entities]]", line))
			}
			if !shared.component_name_is_valid(component_name) {
				return scene, fail(.Invalid_Field, fmt.tprintf("invalid component name '%s'", component_name))
			}
			append(&current.custom_components, Custom_Component{name = component_name})
			current_component = &current.custom_components[len(current.custom_components) - 1]
			section = "component"
			continue
		}

		if current == nil {
			return scene, fail(.Invalid_Syntax, "scene fields must appear under [[entities]]")
		}

		key, value, found := split_assignment(line)
		if !found {
			return scene, fail(.Invalid_Syntax, fmt.tprintf("expected key/value assignment, got '%s'", line))
		}

		switch section {
		case "entity":
			if key != "name" {
				return scene, fail(.Invalid_Field, fmt.tprintf("unknown entity field '%s'", key))
			}
			current.name, found = parse_basic_string(value)
			if !found {
				return scene, fail(.Invalid_Field, "entity name must be a basic string")
			}
		case "transform":
			current.has_transform = true
			switch key {
			case "position":
				current.transform.position, found = parse_vec3(value)
			case "rotation":
				current.transform.rotation, found = parse_vec3(value)
			case "scale":
				current.transform.scale, found = parse_vec3(value)
			case:
				return scene, fail(.Invalid_Field, fmt.tprintf("unknown transform field '%s'", key))
			}
			if !found {
				return scene, fail(.Invalid_Field, fmt.tprintf("transform.%s must be a vec3 array", key))
			}
		case "camera":
			current.has_camera = true
			switch key {
			case "fov":
				current.camera.fov, found = parse_f32(value)
			case "near":
				current.camera.near, found = parse_f32(value)
			case "far":
				current.camera.far, found = parse_f32(value)
			case:
				return scene, fail(.Invalid_Field, fmt.tprintf("unknown camera field '%s'", key))
			}
			if !found {
				return scene, fail(.Invalid_Field, fmt.tprintf("camera.%s must be a number", key))
			}
		case "mesh":
			current.has_mesh = true
			if key != "primitive" {
				return scene, fail(.Invalid_Field, fmt.tprintf("unknown mesh field '%s'", key))
			}
			current.mesh.primitive, found = parse_basic_string(value)
			if !found || current.mesh.primitive == "" {
				return scene, fail(.Invalid_Field, "mesh.primitive must be a non-empty basic string")
			}
		case "component":
			if current_component == nil {
				return scene, fail(.Invalid_Syntax, "component fields must appear under [entities.components.<name>]")
			}
			if !shared.component_token_is_valid(key) {
				return scene, fail(.Invalid_Field, fmt.tprintf("invalid component field '%s'", key))
			}
			vec: Vec3
			vec, found = parse_vec3(value)
			if !found {
				return scene, fail(.Invalid_Field, fmt.tprintf("%s.%s must be a vec3 array", current_component.name, key))
			}
			append(&current_component.vec3_fields, Named_Vec3{name = key, value = vec})
		case:
			return scene, fail(.Invalid_Syntax, fmt.tprintf("unknown scene section '%s'", section))
		}
	}

	if len(scene.entities) == 0 {
		return scene, fail(.Missing_Field, "scene must contain at least one entity")
	}
	for entity, index in scene.entities {
		if entity.name == "" {
			return scene, fail(.Missing_Field, fmt.tprintf("entity %d is missing name", index))
		}
		if entity.has_transform && entity.transform.scale == (Vec3{}) {
			scene.entities[index].transform.scale = Vec3{1, 1, 1}
		}
	}

	return scene, ok()
}

parse_component_section :: proc(line: string) -> (name: string, ok: bool) {
	prefix :: "[entities.components."
	if !strings.has_prefix(line, prefix) || !strings.has_suffix(line, "]") {
		return "", false
	}
	name = line[len(prefix):len(line) - 1]
	return name, true
}

strip_comment :: proc(line: string) -> string {
	in_string := false
	for c, index in line {
		if c == '"' {
			in_string = !in_string
		}
		if c == '#' && !in_string {
			return strings.trim_space(line[:index])
		}
	}
	return line
}

split_assignment :: proc(line: string) -> (key, value: string, found: bool) {
	index := strings.index_byte(line, '=')
	if index < 0 {
		return "", "", false
	}
	key = strings.trim_space(line[:index])
	value = strings.trim_space(line[index + 1:])
	return key, value, key != "" && value != ""
}

parse_basic_string :: proc(value: string) -> (out: string, ok: bool) {
	if len(value) < 2 || value[0] != '"' || value[len(value) - 1] != '"' {
		return "", false
	}
	body := value[1:len(value) - 1]
	if !is_basic_string_body(body) {
		return "", false
	}
	return body, true
}

is_basic_string_body :: proc(body: string) -> bool {
	return !strings.contains_any(body, "\\\"\n\r")
}

parse_vec3 :: proc(value: string) -> (out: Vec3, ok: bool) {
	text := strings.trim_space(value)
	if len(text) < 5 || text[0] != '[' || text[len(text) - 1] != ']' {
		return out, false
	}
	body := text[1:len(text) - 1]
	parts := strings.split(body, ",")
	defer delete(parts)
	if len(parts) != 3 {
		return out, false
	}

	if out.x, ok = parse_f32(parts[0]); !ok {
		return out, false
	}
	if out.y, ok = parse_f32(parts[1]); !ok {
		return out, false
	}
	if out.z, ok = parse_f32(parts[2]); !ok {
		return out, false
	}
	return out, true
}

parse_f32 :: proc(value: string) -> (out: f32, ok: bool) {
	return strconv.parse_f32(strings.trim_space(value))
}

is_safe_relative_path :: proc(path: string) -> bool {
	if path == "" {
		return false
	}
	if strings.contains(path, "\\") || strings.contains(path, "\x00") {
		return false
	}
	if strings.contains(path, "//") || strings.contains(path, "/../") {
		return false
	}
	if strings.has_prefix(path, "/") || strings.has_prefix(path, "../") || strings.has_suffix(path, "/..") {
		return false
	}
	if path == "." || path == ".." || strings.contains(path, "./") {
		return false
	}
	return true
}
