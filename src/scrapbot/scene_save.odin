package scrapbot

import ecs "./ecs"
import project "./project"
import shared "./shared"
import "core:fmt"
import "core:os"
import "core:strings"

save_scene_world :: proc(scene_path: string, world: ^shared.World) -> string {
	if world == nil {
		return "cannot save an unavailable scene world"
	}
	loaded := project.load_scene_file(scene_path)
	defer project.destroy_scene_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	source_bytes, read_err := os.read_entire_file(scene_path, context.temp_allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read %s: %v", scene_path, read_err)
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	entity_ordinal := -1
	section := ""
	custom_component := ""
	seen_keys: [8]string
	seen_key_count := 0
	source := string(source_bytes)
	for raw_line in strings.split_lines_iterator(&source) {
		clean := project.strip_comment(strings.trim_space(raw_line))
		is_entity_header := clean == "[[entities]]"
		is_component_header :=
			strings.has_prefix(clean, "[entities.") && strings.has_suffix(clean, "]")
		if is_entity_header || is_component_header {
			write_missing_scene_fields(
				&builder,
				world,
				&loaded.scene,
				entity_ordinal,
				section,
				custom_component,
				seen_keys[:seen_key_count],
			)
			seen_key_count = 0
		}
		if is_entity_header {
			entity_ordinal += 1
			section = "entity"
			custom_component = ""
		} else if is_component_header {
			if component_name, custom := project.parse_component_section(clean); custom {
				section = "component"
				custom_component = component_name
			} else {
				section = clean[len("[entities."):len(clean) - 1]
				custom_component = ""
			}
		}

		replacement := ""
		replace := false
		if entity_ordinal >= 0 && entity_ordinal < len(loaded.scene.entities) {
			if key, _, assignment := project.split_assignment(clean); assignment {
				if seen_key_count < len(seen_keys) {
					seen_keys[seen_key_count] = key
					seen_key_count += 1
				}
				scene_entity := loaded.scene.entities[entity_ordinal]
				if entity_index, found := ecs.entity_index_by_uuid(world, scene_entity.id); found {
					entity := &world.entities[entity_index]
					if entity.alive && entity.origin == .Scene {
						replacement, replace = scene_world_field_value(
							world,
							entity_index,
							section,
							custom_component,
							key,
						)
					}
				}
			}
		}
		if replace {
			write_replaced_scene_line(&builder, raw_line, replacement)
		} else {
			strings.write_string(&builder, raw_line)
		}
		strings.write_rune(&builder, '\n')
	}
	write_missing_scene_fields(
		&builder,
		world,
		&loaded.scene,
		entity_ordinal,
		section,
		custom_component,
		seen_keys[:seen_key_count],
	)

	temp_path, clone_err := strings.concatenate({scene_path, ".scrapbot-save.tmp"})
	if clone_err != nil {
		return "failed to allocate temporary scene path"
	}
	defer delete(temp_path)
	defer os.remove(temp_path)
	if write_err := os.write_entire_file(temp_path, strings.to_string(builder)); write_err != nil {
		return fmt.tprintf("failed to write temporary scene: %v", write_err)
	}
	if rename_err := os.rename(temp_path, scene_path); rename_err != nil {
		return fmt.tprintf("failed to replace scene file: %v", rename_err)
	}
	return ""
}

write_missing_scene_fields :: proc(
	builder: ^strings.Builder,
	world: ^shared.World,
	scene: ^shared.Scene,
	entity_ordinal: int,
	section, custom_component: string,
	seen_keys: []string,
) {
	if builder == nil ||
	   world == nil ||
	   scene == nil ||
	   entity_ordinal < 0 ||
	   entity_ordinal >= len(scene.entities) {
		return
	}
	entity_index, found := ecs.entity_index_by_uuid(world, scene.entities[entity_ordinal].id)
	if !found || world.entities[entity_index].origin != .Scene {
		return
	}
	keys: [3]string
	key_count := 0
	switch section {
		case "transform":
			keys = {"position", "rotation", "scale"}
			key_count = 3
		case "camera":
			keys = {"fov", "near", "far"}
			key_count = 3
		case "ambient_light":
			keys = {"color", "intensity", ""}
			key_count = 2
		case "directional_light":
			keys = {"direction", "color", "intensity"}
			key_count = 3
		case "point_light":
			keys = {"color", "intensity", "range"}
			key_count = 3
		case "ui_layout":
			keys = {"hidden", "", ""}
			key_count = 1
		case "ui_hstack", "ui_vstack":
			keys = {"fill", "draggable", ""}
			key_count = 2
		case "ui_panel":
			keys = {"collapsible", "collapsed", ""}
			key_count = 2
		case "ui_input":
			keys = {"read_only", "", ""}
			key_count = 1
		case "ui_checkbox":
			keys = {"checked", "read_only", ""}
			key_count = 2
		case:
			return
	}
	for key in keys[:key_count] {
		seen := false
		for seen_key in seen_keys {
			if seen_key == key {
				seen = true
				break
			}
		}
		if seen {
			continue
		}
		value, available := scene_world_field_value(
			world,
			entity_index,
			section,
			custom_component,
			key,
		)
		if !available {
			continue
		}
		strings.write_string(builder, key)
		strings.write_string(builder, " = ")
		strings.write_string(builder, value)
		strings.write_rune(builder, '\n')
	}
}

write_replaced_scene_line :: proc(builder: ^strings.Builder, raw_line, replacement: string) {
	equals := strings.index_byte(raw_line, '=')
	if equals < 0 {
		strings.write_string(builder, raw_line)
		return
	}
	comment := scene_comment_index(raw_line, equals + 1)
	strings.write_string(builder, raw_line[:equals + 1])
	strings.write_rune(builder, ' ')
	strings.write_string(builder, replacement)
	if comment >= 0 {
		strings.write_rune(builder, ' ')
		strings.write_string(builder, raw_line[comment:])
	}
}

scene_comment_index :: proc(line: string, start: int) -> int {
	in_string := false
	for byte, index in line {
		if index < start {
			continue
		}
		if byte == '"' {
			in_string = !in_string
		}
		if byte == '#' && !in_string {
			return index
		}
	}
	return -1
}

scene_f32 :: proc(value: f32) -> string {
	return fmt.tprintf("%.9g", value)
}

scene_vec3 :: proc(value: shared.Vec3) -> string {
	return fmt.tprintf("[%.9g, %.9g, %.9g]", value.x, value.y, value.z)
}

scene_bool :: proc(value: bool) -> string {
	if value {
		return "true"
	}
	return "false"
}

scene_world_field_value :: proc(
	world: ^shared.World,
	entity_index: int,
	section, custom_component, key: string,
) -> (
	string,
	bool,
) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return "", false
	}
	entity := world.entities[entity_index]
	switch section {
		case "transform":
			if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
				return "", false
			}
			value := world.transforms[entity.transform_index]
			switch key {
				case "position":
					return scene_vec3(value.position), true
				case "rotation":
					return scene_vec3(value.rotation), true
				case "scale":
					return scene_vec3(value.scale), true
			}
		case "camera":
			if entity.camera_index < 0 || entity.camera_index >= len(world.cameras) {
				return "", false
			}
			value := world.cameras[entity.camera_index]
			switch key {
				case "fov":
					return scene_f32(value.fov), true
				case "near":
					return scene_f32(value.near), true
				case "far":
					return scene_f32(value.far), true
			}
		case "ambient_light":
			if entity.ambient_light_index < 0 ||
			   entity.ambient_light_index >= len(world.ambient_lights) {
				return "", false
			}
			value := world.ambient_lights[entity.ambient_light_index]
			if key == "color" {
				return scene_vec3(value.color), true
			}
			if key == "intensity" {
				return scene_f32(value.intensity), true
			}
		case "directional_light":
			if entity.directional_light_index < 0 ||
			   entity.directional_light_index >= len(world.directional_lights) {
				return "", false
			}
			value := world.directional_lights[entity.directional_light_index]
			switch key {
				case "direction":
					return scene_vec3(value.direction), true
				case "color":
					return scene_vec3(value.color), true
				case "intensity":
					return scene_f32(value.intensity), true
			}
		case "point_light":
			if entity.point_light_index < 0 ||
			   entity.point_light_index >= len(world.point_lights) {
				return "", false
			}
			value := world.point_lights[entity.point_light_index]
			switch key {
				case "color":
					return scene_vec3(value.color), true
				case "intensity":
					return scene_f32(value.intensity), true
				case "range":
					return scene_f32(value.range), true
			}
		case "ui_layout":
			if key == "hidden" &&
			   entity.ui_layout_index >= 0 &&
			   entity.ui_layout_index < len(world.ui_layouts) {
				return scene_bool(world.ui_layouts[entity.ui_layout_index].hidden), true
			}
		case "ui_hstack":
			if entity.ui_hstack_index >= 0 && entity.ui_hstack_index < len(world.ui_hstacks) {
				value := world.ui_hstacks[entity.ui_hstack_index]
				if key == "fill" {
					return scene_bool(value.fill), true
				}
				if key == "draggable" {
					return scene_bool(value.draggable), true
				}
			}
		case "ui_vstack":
			if entity.ui_vstack_index >= 0 && entity.ui_vstack_index < len(world.ui_vstacks) {
				value := world.ui_vstacks[entity.ui_vstack_index]
				if key == "fill" {
					return scene_bool(value.fill), true
				}
				if key == "draggable" {
					return scene_bool(value.draggable), true
				}
			}
		case "ui_panel":
			if entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels) {
				value := world.ui_panels[entity.ui_panel_index]
				if key == "collapsible" {
					return scene_bool(value.collapsible), true
				}
				if key == "collapsed" {
					return scene_bool(value.collapsed), true
				}
			}
		case "ui_input":
			if key == "read_only" &&
			   entity.ui_input_index >= 0 &&
			   entity.ui_input_index < len(world.ui_inputs) {
				return scene_bool(world.ui_inputs[entity.ui_input_index].read_only), true
			}
		case "ui_checkbox":
			if entity.ui_checkbox_index >= 0 &&
			   entity.ui_checkbox_index < len(world.ui_checkboxes) {
				value := world.ui_checkboxes[entity.ui_checkbox_index]
				if key == "checked" {
					return scene_bool(value.checked), true
				}
				if key == "read_only" {
					return scene_bool(value.read_only), true
				}
			}
		case "component":
			for storage in world.custom_components {
				if storage.name != custom_component {
					continue
				}
				for component in storage.components {
					if component.entity_index != entity_index {
						continue
					}
					for field in component.vec3_fields {
						if field.name == key {
							return scene_vec3(field.value), true
						}
					}
				}
			}
	}
	return "", false
}
