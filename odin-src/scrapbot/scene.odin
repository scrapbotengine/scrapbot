package main

import "core:os"
import "core:strings"

Scene :: struct {
	name:                     string,
	entity_count:             int,
	component_instance_count: int,
	renderable_cube_count:    int,
	storage:                  []byte,
}

Scene_Parser :: struct {
	scene:              Scene,
	entity_open:        bool,
	entity_has_id:      bool,
	entity_has_name:    bool,
	entity_components:  int,
	active_component:   string,
	entity_ids:         [dynamic]string,
}

load_scene_file :: proc(path: string) -> (Scene, Project_Error) {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return Scene{}, .Missing_Default_Scene
	}

	scene, parse_err := parse_scene(string(contents))
	if parse_err != .None {
		delete(contents)
		return scene, parse_err
	}

	scene.storage = contents
	return scene, .None
}

parse_scene :: proc(contents: string) -> (Scene, Project_Error) {
	name, name_ok := read_required_root_string(contents, "name")
	if !name_ok || name == "" {
		return Scene{}, .Invalid_Scene
	}
	version, version_ok := read_required_root_int(contents, "version")
	if !version_ok || version != 1 {
		return Scene{}, .Unsupported_Scene_Version
	}

	parser := Scene_Parser{scene = Scene{name = name}}
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}

		if trimmed == "[[entities]]" {
			flush_err := flush_scene_entity(&parser)
			if flush_err != .None {
				free_scene_parser(&parser)
				return Scene{}, flush_err
			}
			parser.entity_open = true
			parser.entity_has_id = false
			parser.entity_has_name = false
			parser.entity_components = 0
			parser.active_component = ""
			continue
		}

		if strings.has_prefix(trimmed, "[") {
			if !parser.entity_open {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			component_id, ok := parse_component_table_header(trimmed)
			if !ok || component_id == "" {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			parser.active_component = component_id
			parser.entity_components += 1
			parser.scene.component_instance_count += 1
			if component_id == "scrapbot.render.cube" {
				parser.scene.renderable_cube_count += 1
			}
			continue
		}

		if !parser.entity_open {
			continue
		}

		key, _, ok := read_key_value_parts(trimmed)
		if !ok {
			free_scene_parser(&parser)
			return Scene{}, .Invalid_Scene
		}

		if parser.active_component != "" {
			continue
		}

		switch key {
		case "id":
			id, id_ok := read_scene_entity_string_value(trimmed)
			if !id_ok || id == "" || has_scene_entity_id(parser.entity_ids[:], id) {
				free_scene_parser(&parser)
				return Scene{}, .Duplicate_Scene_Entity_ID
			}
			append(&parser.entity_ids, id)
			parser.entity_has_id = true
		case "name":
			name_value, name_value_ok := read_scene_entity_string_value(trimmed)
			if !name_value_ok || name_value == "" {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			parser.entity_has_name = true
		case:
			free_scene_parser(&parser)
			return Scene{}, .Invalid_Scene
		}
	}

	flush_err := flush_scene_entity(&parser)
	if flush_err != .None {
		free_scene_parser(&parser)
		return Scene{}, flush_err
	}
	if parser.scene.entity_count == 0 {
		free_scene_parser(&parser)
		return Scene{}, .Missing_Scene_Content
	}

	scene := parser.scene
	free_scene_parser(&parser)
	return scene, .None
}

free_scene :: proc(scene: Scene) {
	if scene.storage != nil {
		delete(scene.storage)
	}
}

free_scene_parser :: proc(parser: ^Scene_Parser) {
	if parser.entity_ids != nil {
		delete(parser.entity_ids)
	}
}

flush_scene_entity :: proc(parser: ^Scene_Parser) -> Project_Error {
	if !parser.entity_open {
		return .None
	}
	if !parser.entity_has_id || !parser.entity_has_name || parser.entity_components == 0 {
		return .Invalid_Scene
	}
	parser.scene.entity_count += 1
	parser.entity_open = false
	parser.active_component = ""
	return .None
}

parse_component_table_header :: proc(header: string) -> (string, bool) {
	prefix :: "[entities.components."
	if !strings.has_prefix(header, prefix) || !strings.has_suffix(header, "]") {
		return "", false
	}
	raw_id := strings.trim_space(header[len(prefix):len(header) - 1])
	if len(raw_id) >= 2 && raw_id[0] == '"' && raw_id[len(raw_id) - 1] == '"' {
		id := raw_id[1:len(raw_id) - 1]
		if strings.contains(id, "\\") || strings.contains(id, "\"") {
			return "", false
		}
		return id, true
	}
	return raw_id, true
}

read_required_root_string :: proc(contents, key: string) -> (string, bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if strings.has_prefix(trimmed, "[") {
			break
		}
		found_key, value, ok := read_key_value_parts(trimmed)
		if ok && found_key == key {
			return parse_basic_string(value)
		}
	}
	return "", false
}

read_required_root_int :: proc(contents, key: string) -> (int, bool) {
	remaining := contents
	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		if trimmed == "" {
			continue
		}
		if strings.has_prefix(trimmed, "[") {
			break
		}
		found_key, value, ok := read_key_value_parts(trimmed)
		if ok && found_key == key {
			return parse_manifest_int(value)
		}
	}
	return 0, false
}

read_key_value_parts :: proc(line: string) -> (string, string, bool) {
	eq_index := strings.index_byte(line, '=')
	if eq_index < 0 {
		return "", "", false
	}
	key := strings.trim_space(line[:eq_index])
	value := strings.trim_space(line[eq_index + 1:])
	return key, value, true
}

read_scene_entity_string_value :: proc(line: string) -> (string, bool) {
	_, value, ok := read_key_value_parts(line)
	if !ok {
		return "", false
	}
	return parse_basic_string(value)
}

has_scene_entity_id :: proc(ids: []string, id: string) -> bool {
	for existing in ids {
		if existing == id {
			return true
		}
	}
	return false
}
