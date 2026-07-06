package main

import "core:os"
import "core:strconv"
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
	registry:           Runtime_Component_Registry,
	entity_open:        bool,
	entity_has_id:      bool,
	entity_has_name:    bool,
	entity_components:  int,
	active_component:   string,
	active_field_names: [dynamic]string,
	entity_ids:         [dynamic]string,
}

load_scene_file :: proc(path: string, registry: Runtime_Component_Registry) -> (Scene, Project_Error) {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return Scene{}, .Missing_Default_Scene
	}

	scene, parse_err := parse_scene(string(contents), registry)
	if parse_err != .None {
		delete(contents)
		return scene, parse_err
	}

	scene.storage = contents
	return scene, .None
}

parse_scene :: proc(contents: string, registry: Runtime_Component_Registry) -> (Scene, Project_Error) {
	name, name_ok := read_required_root_string(contents, "name")
	if !name_ok || name == "" {
		return Scene{}, .Invalid_Scene
	}
	version, version_ok := read_required_root_int(contents, "version")
	if !version_ok || version != 1 {
		return Scene{}, .Unsupported_Scene_Version
	}

	parser := Scene_Parser{scene = Scene{name = name}, registry = registry}
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
			component_flush_err := flush_scene_component(&parser)
			if component_flush_err != .None {
				free_scene_parser(&parser)
				return Scene{}, component_flush_err
			}
			component_id, ok := parse_component_table_header(trimmed)
			if !ok || component_id == "" || !scene_component_can_be_authored(component_id) {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			if _, found := runtime_find_component(parser.registry, component_id); !found {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			parser.active_component = component_id
			clear(&parser.active_field_names)
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

		key, value, ok := read_key_value_parts(trimmed)
		if !ok {
			free_scene_parser(&parser)
			return Scene{}, .Invalid_Scene
		}

		if parser.active_component != "" {
			field_err := read_scene_component_field(&parser, key, value)
			if field_err != .None {
				free_scene_parser(&parser)
				return Scene{}, field_err
			}
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
	if parser.active_field_names != nil {
		delete(parser.active_field_names)
	}
	if parser.entity_ids != nil {
		delete(parser.entity_ids)
	}
}

flush_scene_entity :: proc(parser: ^Scene_Parser) -> Project_Error {
	if !parser.entity_open {
		return .None
	}
	component_err := flush_scene_component(parser)
	if component_err != .None {
		return component_err
	}
	if !parser.entity_has_id || !parser.entity_has_name || parser.entity_components == 0 {
		return .Invalid_Scene
	}
	parser.scene.entity_count += 1
	parser.entity_open = false
	parser.active_component = ""
	return .None
}

flush_scene_component :: proc(parser: ^Scene_Parser) -> Project_Error {
	if parser.active_component == "" {
		return .None
	}
	if !scene_component_has_required_fields(parser.registry, parser.active_component, parser.active_field_names[:]) {
		return .Invalid_Scene
	}
	parser.active_component = ""
	clear(&parser.active_field_names)
	return .None
}

read_scene_component_field :: proc(parser: ^Scene_Parser, key, value: string) -> Project_Error {
	if has_scene_component_field(parser.active_field_names[:], key) {
		return .Invalid_Scene
	}
	field_definition, field_ok := scene_component_field_definition(parser.registry, parser.active_component, key)
	if !field_ok || !scene_component_value_has_runtime_type(value, field_definition.value_type) {
		return .Invalid_Scene
	}
	if !scene_component_value_is_allowed(parser.active_component, key, value) {
		return .Invalid_Scene
	}
	append(&parser.active_field_names, key)
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

has_scene_component_field :: proc(fields: []string, name: string) -> bool {
	for existing in fields {
		if existing == name {
			return true
		}
	}
	return false
}

scene_component_can_be_authored :: proc(component_id: string) -> bool {
	if scene_component_is_runtime_only(component_id) {
		return false
	}
	if scene_component_is_known_engine_authored(component_id) {
		return true
	}
	return !strings.has_prefix(component_id, "scrapbot.")
}

scene_component_is_runtime_only :: proc(component_id: string) -> bool {
	switch component_id {
	case "scrapbot.input.pointer",
	     "scrapbot.input.keyboard",
	     "scrapbot.input.frame",
	     "scrapbot.ui.command_event":
		return true
	}
	return false
}

scene_component_is_known_engine_authored :: proc(component_id: string) -> bool {
	if scene_component_is_runtime_only(component_id) {
		return false
	}
	switch component_id {
	case "scrapbot.transform",
	     "scrapbot.render.cube",
	     "scrapbot.geometry.primitive",
	     "scrapbot.material.surface",
	     "scrapbot.renderer",
	     "scrapbot.camera",
	     "scrapbot.light.directional",
	     "scrapbot.shadow.caster",
	     "scrapbot.shadow.receiver",
	     "scrapbot.ui.canvas",
	     "scrapbot.ui.rect",
	     "scrapbot.ui.border",
	     "scrapbot.ui.text",
	     "scrapbot.ui.button",
	     "scrapbot.ui.hit_area",
	     "scrapbot.ui.command",
	     "scrapbot.ui.scroll_view",
	     "scrapbot.ui.vgroup",
	     "scrapbot.ui.hgroup",
	     "scrapbot.ui.table",
	     "scrapbot.ui.stack",
	     "scrapbot.ui.layout.item",
	     "scrapbot.ui.spacer",
	     "scrapbot.ui.text_block",
	     "scrapbot.ui.toggle",
	     "scrapbot.ui.progress_bar",
	     "scrapbot.ui.separator":
		return true
	}
	return false
}

scene_component_has_required_fields :: proc(registry: Runtime_Component_Registry, component_id: string, fields: []string) -> bool {
	switch component_id {
	case "scrapbot.transform":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "rotation") &&
		       has_scene_component_field(fields, "scale")
	case "scrapbot.render.cube":
		return has_scene_component_field(fields, "color")
	case "scrapbot.geometry.primitive":
		return has_scene_component_field(fields, "primitive") &&
		       has_scene_component_field(fields, "segments") &&
		       has_scene_component_field(fields, "rings")
	case "scrapbot.material.surface":
		return has_scene_component_field(fields, "base_color")
	case "scrapbot.renderer":
		return true
	case "scrapbot.camera":
		return has_scene_component_field(fields, "fov_y_degrees") &&
		       has_scene_component_field(fields, "near") &&
		       has_scene_component_field(fields, "far")
	case "scrapbot.light.directional":
		return has_scene_component_field(fields, "direction") &&
		       has_scene_component_field(fields, "color") &&
		       has_scene_component_field(fields, "intensity") &&
		       has_scene_component_field(fields, "ambient")
	case "scrapbot.shadow.caster", "scrapbot.shadow.receiver", "scrapbot.ui.button":
		return true
	case "scrapbot.ui.canvas":
		return true
	case "scrapbot.ui.rect":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "color")
	case "scrapbot.ui.border":
		return has_scene_component_field(fields, "color") &&
		       has_scene_component_field(fields, "thickness")
	case "scrapbot.ui.text":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "color") &&
		       has_scene_component_field(fields, "value")
	case "scrapbot.ui.hit_area":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size")
	case "scrapbot.ui.command":
		return has_scene_component_field(fields, "command")
	case "scrapbot.ui.scroll_view":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "content_offset")
	case "scrapbot.ui.vgroup", "scrapbot.ui.hgroup":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "spacing") &&
		       has_scene_component_field(fields, "padding")
	case "scrapbot.ui.table":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size")
	case "scrapbot.ui.stack":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "spacing") &&
		       has_scene_component_field(fields, "direction") &&
		       has_scene_component_field(fields, "padding")
	case "scrapbot.ui.layout.item":
		return has_scene_component_field(fields, "parent") &&
		       has_scene_component_field(fields, "order")
	case "scrapbot.ui.spacer":
		return has_scene_component_field(fields, "size")
	case "scrapbot.ui.text_block":
		return has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "horizontal_align") &&
		       has_scene_component_field(fields, "vertical_align")
	case "scrapbot.ui.toggle":
		return has_scene_component_field(fields, "checked")
	case "scrapbot.ui.progress_bar":
		return has_scene_component_field(fields, "value") &&
		       has_scene_component_field(fields, "max") &&
		       has_scene_component_field(fields, "fill_color")
	case "scrapbot.ui.separator":
		return has_scene_component_field(fields, "position") &&
		       has_scene_component_field(fields, "size") &&
		       has_scene_component_field(fields, "color")
	}
	definition, found := runtime_find_component(registry, component_id)
	if !found {
		return false
	}
	for field in definition.fields {
		if !has_scene_component_field(fields, field.name) {
			return false
		}
	}
	return true
}

scene_component_field_definition :: proc(
	registry: Runtime_Component_Registry,
	component_id, field_name: string,
) -> (Runtime_Component_Field_Definition, bool) {
	definition, found := runtime_find_component(registry, component_id)
	if !found {
		return Runtime_Component_Field_Definition{}, false
	}
	for field in definition.fields {
		if field.name == field_name {
			return field, true
		}
	}
	return Runtime_Component_Field_Definition{}, false
}

scene_field_name_is_one_of :: proc(field_name: string, candidates: []string) -> bool {
	for candidate in candidates {
		if field_name == candidate {
			return true
		}
	}
	return false
}

scene_component_value_has_runtime_type :: proc(value: string, field_type: Runtime_Field_Type) -> bool {
	switch field_type {
	case .Boolean:
		return value == "true" || value == "false"
	case .Int:
		return parse_scene_int(value)
	case .Float:
		return parse_scene_float(value)
	case .Vec3:
		return parse_scene_vec3(value)
	case .String:
		_, ok := parse_basic_string(value)
		return ok
	}
	return false
}

scene_component_value_is_allowed :: proc(component_id, field_name, value: string) -> bool {
	if component_id != "scrapbot.renderer" {
		return true
	}
	switch field_name {
	case "tone_mapping":
		parsed, ok := parse_basic_string(value)
		return ok && scene_field_name_is_one_of(parsed, []string{"none", "reinhard", "aces"})
	case "antialiasing":
		parsed, ok := parse_basic_string(value)
		return ok && scene_field_name_is_one_of(parsed, []string{"none", "fxaa"})
	case "exposure":
		return parse_scene_finite_float_in_range(value, 0.0, false)
	case "bloom_threshold",
	     "bloom_intensity",
	     "bloom_radius",
	     "vignette_strength",
	     "chromatic_aberration_strength":
		return parse_scene_finite_float_in_range(value, 0.0, true)
	case "vignette_radius":
		return parse_scene_finite_float_in_range(value, 0.0001, true)
	}
	return true
}

parse_scene_int :: proc(value: string) -> bool {
	_, ok := strconv.parse_int(value, 10)
	return ok
}

parse_scene_float :: proc(value: string) -> bool {
	_, ok := parse_scene_float_value(value)
	return ok
}

parse_scene_float_value :: proc(value: string) -> (f32, bool) {
	return strconv.parse_f32(value)
}

parse_scene_finite_float_in_range :: proc(value: string, min_value: f32, has_min: bool) -> bool {
	parsed, ok := parse_scene_float_value(value)
	if !ok || parsed != parsed || parsed > 3.4028234663852886e38 || parsed < -3.4028234663852886e38 {
		return false
	}
	if has_min && parsed < min_value {
		return false
	}
	return true
}

parse_scene_vec3 :: proc(value: string) -> bool {
	if len(value) < 5 || value[0] != '[' || value[len(value) - 1] != ']' {
		return false
	}
	inner := value[1:len(value) - 1]
	count := 0
	remaining := inner
	for part in strings.split_iterator(&remaining, ",") {
		if count >= 3 {
			return false
		}
		trimmed := strings.trim_space(part)
		if trimmed == "" || !parse_scene_float(trimmed) {
			return false
		}
		count += 1
	}
	return count == 3
}
