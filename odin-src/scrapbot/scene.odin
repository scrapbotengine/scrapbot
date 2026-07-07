package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Scene :: struct {
	name:                     string,
	entity_count:             int,
	component_instance_count: int,
	renderable_cube_count:    int,
	world:                    Runtime_World,
	storage:                  []byte,
}

Scene_Parser :: struct {
	scene:                 Scene,
	registry:              Runtime_Component_Registry,
	entity_open:           bool,
	entity_has_id:         bool,
	entity_has_name:       bool,
	entity_id:             string,
	entity_name:           string,
	active_component:      string,
	active_component_data: Scene_Component_Draft,
	entity_components:     [dynamic]Scene_Component_Draft,
	active_field_names:    [dynamic]string,
	entity_ids:            [dynamic]string,
}

Scene_Component_Draft :: struct {
	id:                   string,
	fields:               [dynamic]Runtime_Component_Field_Value,
	authored_field_names: [dynamic]string,
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

persist_editor_test_pending_scene_edit :: proc(project: Project, world: Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	command, ok := take_editor_test_pending_scene_edit(state)
	if !ok {
		return false
	}
	defer editor_test_field_command_free(&command)
	return persist_scene_component_field_edit(project.root_path, project.default_scene, world, &command)
}

persist_scene_component_field_edit :: proc(project_root, scene_relative_path: string, world: Runtime_World, command: ^Editor_Test_Field_Edit_Command) -> bool {
	entity, entity_err := runtime_world_entity(world, command.entity)
	if entity_err != .None || entity.provenance != .Authored {
		return false
	}
	component_id := editor_test_field_command_component(command)
	field_name := editor_test_field_command_field(command)
	if component_id == "" || field_name == "" {
		return false
	}

	scene_path := project_relative_path(project_root, scene_relative_path)
	defer delete(scene_path)
	if scene_path == "" {
		return false
	}
	contents, read_err := os.read_entire_file(scene_path, context.allocator)
	if read_err != nil {
		return false
	}
	defer delete(contents)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	remaining := string(contents)
	in_entity := false
	target_entity := false
	target_component := false
	updated := false

	for line in strings.split_lines_iterator(&remaining) {
		trimmed := strings.trim_space(strip_line_comment(line))
		next_line := line
		owned_next_line := ""

		if trimmed == "[[entities]]" {
			in_entity = true
			target_entity = false
			target_component = false
		} else if in_entity && strings.has_prefix(trimmed, "[") {
			component, ok := parse_component_table_header(trimmed)
			target_component = ok && target_entity && component == component_id
		} else if in_entity && !updated {
			key, value, ok := read_key_value_parts(trimmed)
			if ok && !target_component && key == "id" {
				id, id_ok := parse_basic_string(value)
				target_entity = id_ok && id == entity.id
			} else if ok && target_component && key == field_name {
				owned_next_line = scene_component_field_replacement_line(line, field_name, command.new_value)
				if owned_next_line == "" {
					return false
				}
				next_line = owned_next_line
				updated = true
			}
		}

		strings.write_string(&builder, next_line)
		strings.write_rune(&builder, '\n')
		if owned_next_line != "" {
			delete(owned_next_line)
		}
	}

	if !updated {
		return false
	}
	return os.write_entire_file(scene_path, strings.to_string(builder)) == nil
}

scene_component_field_replacement_line :: proc(line, field_name: string, value: Runtime_Component_Value) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for index := 0; index < len(line); index += 1 {
		if line[index] != ' ' && line[index] != '\t' {
			break
		}
		strings.write_rune(&builder, rune(line[index]))
	}
	strings.write_string(&builder, field_name)
	strings.write_string(&builder, " = ")
	if !write_scene_component_value(&builder, value) {
		return ""
	}
	out, err := strings.clone(strings.to_string(builder))
	if err != nil {
		return ""
	}
	return out
}

write_scene_component_value :: proc(builder: ^strings.Builder, value: Runtime_Component_Value) -> bool {
	switch value.value_type {
	case .Boolean:
		if value.boolean {
			strings.write_string(builder, "true")
		} else {
			strings.write_string(builder, "false")
		}
	case .Int:
		strings.write_string(builder, fmt.tprintf("%d", value.int_value))
	case .Float:
		strings.write_string(builder, fmt.tprintf("%g", value.float))
	case .Vec3:
		strings.write_string(builder, "[")
		strings.write_string(builder, fmt.tprintf("%g", value.vec3[0]))
		strings.write_string(builder, ", ")
		strings.write_string(builder, fmt.tprintf("%g", value.vec3[1]))
		strings.write_string(builder, ", ")
		strings.write_string(builder, fmt.tprintf("%g", value.vec3[2]))
		strings.write_string(builder, "]")
	case .String:
		strings.write_rune(builder, '"')
		if !write_toml_basic_string_contents(builder, value.string_value) {
			return false
		}
		strings.write_rune(builder, '"')
	}
	return true
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

	parser := Scene_Parser{scene = Scene{name = name, world = runtime_world_init()}, registry = registry}
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
			parser.entity_id = ""
			parser.entity_name = ""
			parser.active_component = ""
			clear(&parser.entity_components)
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
			component_draft, component_exists := take_scene_component_draft(&parser, component_id)
			parser.active_component = component_id
			parser.active_component_data = component_draft
			clear(&parser.active_field_names)
			for field_name in parser.active_component_data.authored_field_names {
				append(&parser.active_field_names, field_name)
			}
			if component_id == "scrapbot.render.cube" && !component_exists {
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
			parser.entity_id = id
			parser.entity_has_id = true
		case "name":
			name_value, name_value_ok := read_scene_entity_string_value(trimmed)
			if !name_value_ok || name_value == "" {
				free_scene_parser(&parser)
				return Scene{}, .Invalid_Scene
			}
			parser.entity_name = name_value
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
	if runtime_world_entity_count(parser.scene.world) == 0 {
		free_scene_parser(&parser)
		return Scene{}, .Missing_Scene_Content
	}
	if scene_world_component_instance_count(parser.scene.world, "scrapbot.renderer") > 1 {
		free_scene_parser(&parser)
		return Scene{}, .Invalid_Scene
	}

	parser.scene.entity_count = runtime_world_entity_count(parser.scene.world)
	parser.scene.component_instance_count = runtime_world_component_instance_count(parser.scene.world)
	scene := parser.scene
	parser.scene = Scene{}
	free_scene_parser(&parser)
	return scene, .None
}

free_scene :: proc(scene: Scene) {
	world := scene.world
	runtime_world_free(&world)
	if scene.storage != nil {
		delete(scene.storage)
	}
}

free_scene_parser :: proc(parser: ^Scene_Parser) {
	free_scene_component_draft(&parser.active_component_data)
	for &component in parser.entity_components {
		free_scene_component_draft(&component)
	}
	if parser.entity_components != nil {
		delete(parser.entity_components)
	}
	if parser.active_field_names != nil {
		delete(parser.active_field_names)
	}
	if parser.entity_ids != nil {
		delete(parser.entity_ids)
	}
	runtime_world_free(&parser.scene.world)
}

free_scene_component_draft :: proc(component: ^Scene_Component_Draft) {
	if component.fields != nil {
		delete(component.fields)
	}
	if component.authored_field_names != nil {
		delete(component.authored_field_names)
	}
	component.id = ""
	component.fields = nil
	component.authored_field_names = nil
}

flush_scene_entity :: proc(parser: ^Scene_Parser) -> Project_Error {
	if !parser.entity_open {
		return .None
	}
	component_err := flush_scene_component(parser)
	if component_err != .None {
		return component_err
	}
	if !parser.entity_has_id || !parser.entity_has_name || len(parser.entity_components) == 0 {
		return .Invalid_Scene
	}
	handle, entity_err := runtime_world_create_authored_entity(&parser.scene.world, parser.entity_id, parser.entity_name)
	if entity_err == .Duplicate_Entity_ID {
		return .Duplicate_Scene_Entity_ID
	}
	if entity_err != .None {
		return .Invalid_Scene
	}
	for &component in parser.entity_components {
		add_scene_component_defaults(&component)
		if !scene_component_has_required_fields(parser.registry, component.id, component.authored_field_names[:]) {
			return .Invalid_Scene
		}
		set_err := runtime_world_set_component(&parser.scene.world, handle, component.id, component.fields[:])
		if set_err != .None {
			return .Invalid_Scene
		}
	}
	parser.entity_open = false
	parser.active_component = ""
	for &component in parser.entity_components {
		free_scene_component_draft(&component)
	}
	clear(&parser.entity_components)
	return .None
}

flush_scene_component :: proc(parser: ^Scene_Parser) -> Project_Error {
	if parser.active_component == "" {
		return .None
	}
	append(&parser.entity_components, parser.active_component_data)
	parser.active_component_data = Scene_Component_Draft{}
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
	field_value, value_ok := read_scene_component_runtime_value(value, field_definition.value_type)
	if !value_ok {
		return .Invalid_Scene
	}
	append(&parser.active_component_data.fields, Runtime_Component_Field_Value{name = key, value = field_value})
	append(&parser.active_component_data.authored_field_names, key)
	append(&parser.active_field_names, key)
	return .None
}

take_scene_component_draft :: proc(parser: ^Scene_Parser, component_id: string) -> (Scene_Component_Draft, bool) {
	for component, index in parser.entity_components {
		if component.id == component_id {
			draft := component
			last_index := len(parser.entity_components) - 1
			for move_index := index; move_index < last_index; move_index += 1 {
				parser.entity_components[move_index] = parser.entity_components[move_index + 1]
			}
			pop(&parser.entity_components)
			return draft, true
		}
	}
	return Scene_Component_Draft{id = component_id}, false
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

add_scene_component_defaults :: proc(component: ^Scene_Component_Draft) {
	switch component.id {
	case "scrapbot.ui.canvas":
		add_scene_component_default_field(component, "design_size", runtime_component_value_vec3({0.0, 0.0, 0.0}))
		add_scene_component_default_field(component, "scale_mode", runtime_component_value_string("none"))
	case "scrapbot.ui.rect":
		add_scene_component_default_field(component, "corner_radius", runtime_component_value_float(0.0))
	case "scrapbot.ui.table":
		add_scene_component_default_field(component, "columns", runtime_component_value_int(2))
		add_scene_component_default_field(component, "row_height", runtime_component_value_float(1.0))
		add_scene_component_default_field(component, "column_gap", runtime_component_value_float(0.0))
		add_scene_component_default_field(component, "row_gap", runtime_component_value_float(0.0))
		add_scene_component_default_field(component, "padding", runtime_component_value_vec3({0.0, 0.0, 0.0}))
		add_scene_component_default_field(component, "first_column_ratio", runtime_component_value_float(0.5))
	case "scrapbot.ui.layout.item":
		add_scene_component_default_field(component, "min_size", runtime_component_value_vec3({0.0, 0.0, 0.0}))
		add_scene_component_default_field(component, "preferred_size", runtime_component_value_vec3({0.0, 0.0, 0.0}))
		add_scene_component_default_field(component, "max_size", runtime_component_value_vec3({0.0, 0.0, 0.0}))
		add_scene_component_default_field(component, "grow", runtime_component_value_float(0.0))
		add_scene_component_default_field(component, "shrink", runtime_component_value_float(0.0))
		add_scene_component_default_field(component, "align", runtime_component_value_string("start"))
		add_scene_component_default_field(component, "margin", runtime_component_value_vec3({0.0, 0.0, 0.0}))
	case "scrapbot.renderer":
		add_scene_component_default_field(component, "hdr", runtime_component_value_boolean(true))
		add_scene_component_default_field(component, "tone_mapping", runtime_component_value_string("aces"))
		add_scene_component_default_field(component, "exposure", runtime_component_value_float(0.0))
		add_scene_component_default_field(component, "postprocess_enabled", runtime_component_value_boolean(true))
		add_scene_component_default_field(component, "antialiasing", runtime_component_value_string("fxaa"))
		add_scene_component_default_field(component, "bloom_enabled", runtime_component_value_boolean(true))
		add_scene_component_default_field(component, "bloom_threshold", runtime_component_value_float(0.85))
		add_scene_component_default_field(component, "bloom_intensity", runtime_component_value_float(0.12))
		add_scene_component_default_field(component, "bloom_radius", runtime_component_value_float(1.0))
		add_scene_component_default_field(component, "vignette_enabled", runtime_component_value_boolean(true))
		add_scene_component_default_field(component, "vignette_strength", runtime_component_value_float(0.24))
		add_scene_component_default_field(component, "vignette_radius", runtime_component_value_float(0.82))
		add_scene_component_default_field(component, "chromatic_aberration_enabled", runtime_component_value_boolean(true))
		add_scene_component_default_field(component, "chromatic_aberration_strength", runtime_component_value_float(0.0025))
	}
}

add_scene_component_default_field :: proc(component: ^Scene_Component_Draft, name: string, value: Runtime_Component_Value) {
	for field in component.fields {
		if field.name == name {
			return
		}
	}
	append(&component.fields, Runtime_Component_Field_Value{name = name, value = value})
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
	_, ok := parse_scene_vec3_value(value)
	return ok
}

parse_scene_vec3_value :: proc(value: string) -> ([3]f32, bool) {
	if len(value) < 5 || value[0] != '[' || value[len(value) - 1] != ']' {
		return {}, false
	}
	inner := value[1:len(value) - 1]
	count := 0
	out: [3]f32
	remaining := inner
	for part in strings.split_iterator(&remaining, ",") {
		if count >= 3 {
			return {}, false
		}
		trimmed := strings.trim_space(part)
		parsed, ok := parse_scene_float_value(trimmed)
		if trimmed == "" || !ok {
			return {}, false
		}
		out[count] = parsed
		count += 1
	}
	return out, count == 3
}

read_scene_component_runtime_value :: proc(value: string, field_type: Runtime_Field_Type) -> (Runtime_Component_Value, bool) {
	switch field_type {
	case .Boolean:
		if value == "true" {
			return runtime_component_value_boolean(true), true
		}
		if value == "false" {
			return runtime_component_value_boolean(false), true
		}
	case .Int:
		parsed, ok := strconv.parse_int(value, 10)
		if ok {
			return runtime_component_value_int(parsed), true
		}
	case .Float:
		parsed, ok := parse_scene_float_value(value)
		if ok {
			return runtime_component_value_float(parsed), true
		}
	case .Vec3:
		parsed, ok := parse_scene_vec3_value(value)
		if ok {
			return runtime_component_value_vec3(parsed), true
		}
	case .String:
		parsed, ok := parse_basic_string(value)
		if ok {
			return runtime_component_value_string(parsed), true
		}
	}
	return Runtime_Component_Value{}, false
}

scene_world_component_instance_count :: proc(world: Runtime_World, component_id: string) -> int {
	table, found := runtime_world_find_component_table(world, component_id)
	if !found {
		return 0
	}
	return len(table.entities)
}
