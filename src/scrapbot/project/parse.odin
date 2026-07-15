package project

import shared "../shared"
import "core:fmt"
import "core:strconv"
import "core:strings"

Parse_Error :: enum {
	None,
	Missing_Field,
	Invalid_Field,
	Invalid_Syntax,
	Invalid_Path,
}

Parse_Result :: struct {
	err: Parse_Error,
	message: string,
}

ok :: proc() -> Parse_Result {
	return {}
}

fail :: proc(err: Parse_Error, message: string) -> Parse_Result {
	return Parse_Result{err = err, message = message}
}

parse_project_config :: proc(source: string) -> (config: Project_Config, result: Parse_Result) {
	section := ""
	current_native_extension: ^shared.Native_Extension_Target
	current_font: ^shared.Project_Font

	text := source
	for raw_line in strings.split_lines_iterator(&text) {
		line := strip_comment(strings.trim_space(raw_line))
		if line == "" {
			continue
		}

		if line == "[[native_extensions]]" {
			append(&config.native_extensions, shared.Native_Extension_Target{})
			current_native_extension = &config.native_extensions[len(config.native_extensions) - 1]
			section = "native_extension"
			continue
		}
		if line == "[[fonts]]" {
			append(&config.fonts, shared.Project_Font{})
			current_font = &config.fonts[len(config.fonts) - 1]
			section = "font"
			continue
		}

		key, value, found := split_assignment(line)
		if !found {
			return config, fail(
				.Invalid_Syntax,
				fmt.tprintf("expected key/value assignment, got '%s'", line),
			)
		}

		if section == "native_extension" {
			if current_native_extension == nil {
				return config, fail(
					.Invalid_Syntax,
					"native extension fields must appear under [[native_extensions]]",
				)
			}
			switch key {
				case "name":
					current_native_extension.name, found = parse_basic_string(value)
					if !found || !shared.component_token_is_valid(current_native_extension.name) {
						return config, fail(
							.Invalid_Field,
							"native extension name must be an identifier string",
						)
					}
				case "source":
					current_native_extension.source, found = parse_basic_string(value)
					if !found || !is_safe_relative_path(current_native_extension.source) {
						return config, fail(
							.Invalid_Path,
							"native extension source must be a safe relative path",
						)
					}
				case:
					return config, fail(
						.Invalid_Field,
						fmt.tprintf("unknown native extension field '%s'", key),
					)
			}
			continue
		}
		if section == "font" {
			if current_font == nil {
				return config, fail(.Invalid_Syntax, "font fields must appear under [[fonts]]")
			}
			switch key {
				case "name":
					current_font.name, found = parse_basic_string(value)
					if !found || !shared.component_token_is_valid(current_font.name) {
						return config, fail(
							.Invalid_Field,
							"font name must be an identifier string",
						)
					}
				case "source":
					current_font.source, found = parse_basic_string(value)
					if !found || !valid_font_source_path(current_font.source) {
						return config, fail(
							.Invalid_Path,
							"font source must be a safe .ttf or .otf path under assets/",
						)
					}
				case:
					return config, fail(
						.Invalid_Field,
						fmt.tprintf("unknown font field '%s'", key),
					)
			}
			continue
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
					return config, fail(
						.Invalid_Path,
						"default_scene must be a safe relative path",
					)
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
	for extension, index in config.native_extensions {
		if extension.name == "" {
			return config, fail(
				.Missing_Field,
				fmt.tprintf("native extension %d is missing name", index),
			)
		}
		if extension.source == "" {
			return config, fail(
				.Missing_Field,
				fmt.tprintf("native extension %d is missing source", index),
			)
		}
	}
	if len(config.fonts) > shared.MAX_PROJECT_FONTS {
		return config, fail(
			.Invalid_Field,
			fmt.tprintf("project supports at most %d fonts", shared.MAX_PROJECT_FONTS),
		)
	}
	for font, index in config.fonts {
		if font.name == "" {
			return config, fail(.Missing_Field, fmt.tprintf("font %d is missing name", index))
		}
		if font.source == "" {
			return config, fail(.Missing_Field, fmt.tprintf("font %d is missing source", index))
		}
		for previous in config.fonts[:index] {
			if previous.name == font.name {
				return config, fail(
					.Invalid_Field,
					fmt.tprintf("font '%s' is declared twice", font.name),
				)
			}
		}
	}
	return config, ok()
}

valid_font_source_path :: proc(path: string) -> bool {
	if !is_safe_relative_path(path) || !strings.has_prefix(path, "assets/") || len(path) < 4 {
		return false
	}
	extension := path[len(path) - 4:]
	return strings.equal_fold(extension, ".ttf") || strings.equal_fold(extension, ".otf")
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

		if line == "[entities.transform]" ||
		   line == "[entities.camera]" ||
		   line == "[entities.mesh]" ||
		   line == "[entities.geometry]" ||
		   line == "[entities.material]" ||
		   line == "[entities.ambient_light]" ||
		   line == "[entities.directional_light]" ||
		   line == "[entities.point_light]" ||
		   line == "[entities.shadow_caster]" ||
		   line == "[entities.shadow_receiver]" ||
		   line == "[entities.ui_layout]" ||
		   line == "[entities.ui_hstack]" ||
		   line == "[entities.ui_vstack]" ||
		   line == "[entities.ui_scroll_area]" ||
		   line == "[entities.ui_panel]" ||
		   line == "[entities.ui_table]" ||
		   line == "[entities.ui_text]" ||
		   line == "[entities.ui_button]" ||
		   line == "[entities.ui_input]" ||
		   line == "[entities.ui_checkbox]" {
			if current == nil {
				return scene, fail(
					.Invalid_Syntax,
					fmt.tprintf("%s appears before [[entities]]", line),
				)
			}
			section = line[10:len(line) - 1]
			if section == "shadow_caster" { current.has_shadow_caster = true }
			if section == "shadow_receiver" { current.has_shadow_receiver = true }
			if section == "ui_layout" { current.has_ui_layout = true }
			if section == "ui_hstack" { current.has_ui_hstack = true }
			if section == "ui_vstack" { current.has_ui_vstack = true }
			if section ==
			   "ui_scroll_area" {current.has_ui_scroll_area = true; current.ui_scroll_area = {
					scroll_speed = 48,
					smoothness = 14,
				}}
			if section == "ui_panel" {current.has_ui_panel = true; current.ui_panel = {
					title_color = {1, 1, 1, 1},
					title_size = 12,
					title_height = 32,
				}}
			if section == "ui_table" { current.has_ui_table = true; current.ui_table.columns = 1 }
			if section ==
			   "ui_text" { current.has_ui_text = true; current.ui_text.color = {1, 1, 1, 1}; current.ui_text.size = 16 }
			if section ==
			   "ui_button" { current.has_ui_button = true; current.ui_button.color = {1, 1, 1, 1}; current.ui_button.size = 16 }
			if section == "ui_input" {
				current.has_ui_input = true
				current.ui_input = {
					color = {1, 1, 1, 1},
					size = 16,
					selection_background = {0.15, 0.45, 0.40, 0.55},
					focus_border_color = {0.15, 0.85, 0.72, 1},
				}
			}
			if section == "ui_checkbox" {
				current.has_ui_checkbox = true
				current.ui_checkbox = {
					box_size = 18,
					background = {0.025, 0.030, 0.040, 1},
					checked_background = {0.08, 0.55, 0.46, 1},
					border_color = {0.24, 0.27, 0.32, 1},
					check_color = {0.95, 0.97, 0.98, 1},
					hover_background = {0.12, 0.64, 0.54, 1},
					active_background = {0.06, 0.42, 0.36, 1},
				}
			}
			current_component = nil
			continue
		}

		component_name, is_component_section := parse_component_section(line)
		if is_component_section {
			if current == nil {
				return scene, fail(
					.Invalid_Syntax,
					fmt.tprintf("%s appears before [[entities]]", line),
				)
			}
			if !shared.component_name_is_valid(component_name) {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("invalid component name '%s'", component_name),
				)
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
			return scene, fail(
				.Invalid_Syntax,
				fmt.tprintf("expected key/value assignment, got '%s'", line),
			)
		}

		switch section {
			case "entity":
				switch key {
					case "id":
						raw_id, string_ok := parse_basic_string(value)
						if string_ok {
							current.id, found = shared.entity_uuid_parse(raw_id)
						} else {
							found = false
						}
						if !found {
							return scene, fail(
								.Invalid_Field,
								"entity id must be a non-zero UUID string",
							)
						}
					case "name":
						current.name, found = parse_basic_string(value)
						if !found {
							return scene, fail(
								.Invalid_Field,
								"entity name must be a basic string",
							)
						}
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown entity field '%s'", key),
						)
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
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown transform field '%s'", key),
						)
				}
				if !found {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("transform.%s must be a vec3 array", key),
					)
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
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown camera field '%s'", key),
						)
				}
				if !found {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("camera.%s must be a number", key),
					)
				}
			case "ambient_light":
				current.has_ambient_light = true
				switch key {case "color":
						current.ambient_light.color, found = parse_vec3(value); case "intensity":
						current.ambient_light.intensity, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ambient_light field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ambient_light.%s", key)) }
			case "directional_light":
				current.has_directional_light = true
				switch key {case "direction":
						current.directional_light.direction, found = parse_vec3(
							value,
						); case "color":
						current.directional_light.color, found = parse_vec3(
							value,
						); case "intensity":
						current.directional_light.intensity, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown directional_light field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid directional_light.%s", key)) }
			case "point_light":
				current.has_point_light = true
				switch key {case "color":
						current.point_light.color, found = parse_vec3(value); case "intensity":
						current.point_light.intensity, found = parse_f32(value); case "range":
						current.point_light.range, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown point_light field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid point_light.%s", key)) }
			case "mesh":
				current.has_mesh = true
				if key != "primitive" {
					return scene, fail(.Invalid_Field, fmt.tprintf("unknown mesh field '%s'", key))
				}
				current.mesh.primitive, found = parse_basic_string(value)
				if !found || current.mesh.primitive == "" {
					return scene, fail(
						.Invalid_Field,
						"mesh.primitive must be a non-empty basic string",
					)
				}
			case "geometry":
				current.has_geometry = true
				if key !=
				   "resource" { return scene, fail(.Invalid_Field, "geometry only supports resource") }
				current.geometry_resource, found = parse_basic_string(value)
				if !found ||
				   current.geometry_resource ==
					   "" { return scene, fail(.Invalid_Field, "geometry.resource must be a non-empty basic string") }
			case "material":
				current.has_material = true
				if key !=
				   "resource" { return scene, fail(.Invalid_Field, "material only supports resource") }
				current.material_resource, found = parse_basic_string(value)
				if !found ||
				   current.material_resource ==
					   "" { return scene, fail(.Invalid_Field, "material.resource must be a non-empty basic string") }
			case "shadow_caster", "shadow_receiver":
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("%s is a marker component and has no fields", section),
				)
			case "ui_layout":
				current.has_ui_layout = true
				switch key {
					case "parent":
						raw_parent, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_layout.parent, found = shared.entity_uuid_parse(raw_parent)
						} else {
							found = false
						}
					case "position":
						current.ui_layout.position, found = parse_vec2(value)
					case "size":
						current.ui_layout.size, found = parse_vec2(value)
					case "margin":
						current.ui_layout.margin, found = parse_vec4(value)
					case "padding":
						current.ui_layout.padding, found = parse_vec4(value)
					case "background":
						current.ui_layout.background, found = parse_vec4(value)
					case "border_color":
						current.ui_layout.border_color, found = parse_vec4(value)
					case "border_width":
						current.ui_layout.border_width, found = parse_f32(value)
					case "corner_radius":
						current.ui_layout.corner_radius, found = parse_f32(value)
					case "hidden":
						current.ui_layout.hidden, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_layout field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_layout.%s", key)) }
			case "ui_hstack":
				current.has_ui_hstack = true
				switch key {case "gap":
						current.ui_hstack.gap, found = parse_f32(value); case "fill":
						current.ui_hstack.fill, found = parse_bool(value); case "draggable":
						current.ui_hstack.draggable, found = parse_bool(value); case "min_size":
						current.ui_hstack.min_size, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_hstack field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_hstack.%s", key)) }
			case "ui_vstack":
				current.has_ui_vstack = true
				switch key {case "gap":
						current.ui_vstack.gap, found = parse_f32(value); case "fill":
						current.ui_vstack.fill, found = parse_bool(value); case "draggable":
						current.ui_vstack.draggable, found = parse_bool(value); case "min_size":
						current.ui_vstack.min_size, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_vstack field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_vstack.%s", key)) }
			case "ui_scroll_area":
				current.has_ui_scroll_area = true
				switch key {case "scroll_speed":
						current.ui_scroll_area.scroll_speed, found = parse_f32(
							value,
						); case "smoothness":
						current.ui_scroll_area.smoothness, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_scroll_area field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_scroll_area.%s", key)) }
			case "ui_panel":
				current.has_ui_panel = true
				switch key {
					case "title":
						current.ui_panel.title, found = parse_basic_string(value)
					case "font":
						current.ui_panel.font, found = parse_basic_string(value)
					case "title_color":
						current.ui_panel.title_color, found = parse_vec4(value)
					case "title_background":
						current.ui_panel.title_background, found = parse_vec4(value)
					case "title_size":
						current.ui_panel.title_size, found = parse_f32(value)
					case "title_height":
						current.ui_panel.title_height, found = parse_f32(value)
					case "collapsible":
						current.ui_panel.collapsible, found = parse_bool(value)
					case "collapsed":
						current.ui_panel.collapsed, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_panel field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_panel.%s", key)) }
			case "ui_table":
				current.has_ui_table = true
				switch key {
					case "columns":
						current.ui_table.columns, found = parse_int(value)
					case "column_gap":
						current.ui_table.column_gap, found = parse_f32(value)
					case "row_gap":
						current.ui_table.row_gap, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_table field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_table.%s", key)) }
			case "ui_text":
				current.has_ui_text = true
				switch key {case "text":
						current.ui_text.text, found = parse_basic_string(value); case "font":
						current.ui_text.font, found = parse_basic_string(value); case "color":
						current.ui_text.color, found = parse_vec4(value); case "size":
						current.ui_text.size, found = parse_f32(value); case "alignment":
						current.ui_text.alignment, found = parse_ui_text_alignment(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_text field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_text.%s", key)) }
			case "ui_button":
				current.has_ui_button = true
				switch key {case "text":
						current.ui_button.text, found = parse_basic_string(value); case "font":
						current.ui_button.font, found = parse_basic_string(value); case "color":
						current.ui_button.color, found = parse_vec4(value); case "size":
						current.ui_button.size, found = parse_f32(value); case "hover_background":
						current.ui_button.hover_background, found = parse_vec4(
							value,
						); case "active_background":
						current.ui_button.active_background, found = parse_vec4(
							value,
						); case "hover_color":
						current.ui_button.hover_color, found = parse_vec4(
							value,
						); case "active_color":
						current.ui_button.active_color, found = parse_vec4(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_button field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_button.%s", key)) }
			case "ui_input":
				current.has_ui_input = true
				switch key {
					case "text":
						current.ui_input.text, found = parse_basic_string(value)
					case "font":
						current.ui_input.font, found = parse_basic_string(value)
					case "color":
						current.ui_input.color, found = parse_vec4(value)
					case "size":
						current.ui_input.size, found = parse_f32(value)
					case "selection_background":
						current.ui_input.selection_background, found = parse_vec4(value)
					case "focus_border_color":
						current.ui_input.focus_border_color, found = parse_vec4(value)
					case "read_only":
						current.ui_input.read_only, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_input field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_input.%s", key)) }
			case "ui_checkbox":
				current.has_ui_checkbox = true
				switch key {
					case "checked":
						current.ui_checkbox.checked, found = parse_bool(value)
					case "box_size":
						current.ui_checkbox.box_size, found = parse_f32(value)
					case "background":
						current.ui_checkbox.background, found = parse_vec4(value)
					case "checked_background":
						current.ui_checkbox.checked_background, found = parse_vec4(value)
					case "border_color":
						current.ui_checkbox.border_color, found = parse_vec4(value)
					case "check_color":
						current.ui_checkbox.check_color, found = parse_vec4(value)
					case "hover_background":
						current.ui_checkbox.hover_background, found = parse_vec4(value)
					case "active_background":
						current.ui_checkbox.active_background, found = parse_vec4(value)
					case "read_only":
						current.ui_checkbox.read_only, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_checkbox field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_checkbox.%s", key)) }
			case "component":
				if current_component == nil {
					return scene, fail(
						.Invalid_Syntax,
						"component fields must appear under [entities.components.<name>]",
					)
				}
				if !shared.component_token_is_valid(key) {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("invalid component field '%s'", key),
					)
				}
				vec: Vec3
				vec, found = parse_vec3(value)
				if !found {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("%s.%s must be a vec3 array", current_component.name, key),
					)
				}
				append(&current_component.vec3_fields, Named_Vec3{name = key, value = vec})
			case:
				return scene, fail(
					.Invalid_Syntax,
					fmt.tprintf("unknown scene section '%s'", section),
				)
		}
	}

	if len(scene.entities) == 0 {
		return scene, fail(.Missing_Field, "scene must contain at least one entity")
	}
	for entity, index in scene.entities {
		if entity.id == (shared.Entity_UUID{}) {
			return scene, fail(.Missing_Field, fmt.tprintf("entity %d is missing id", index))
		}
		if entity.name == "" {
			return scene, fail(.Missing_Field, fmt.tprintf("entity %d is missing name", index))
		}
		for previous in scene.entities[:index] {
			if previous.id == entity.id {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("entity %d has a duplicate id", index),
				)
			}
		}
		if entity.has_transform && entity.transform.scale == (Vec3{}) {
			scene.entities[index].transform.scale = Vec3{1, 1, 1}
		}
		if (entity.has_ui_text ||
			   entity.has_ui_button ||
			   entity.has_ui_hstack ||
			   entity.has_ui_vstack ||
			   entity.has_ui_scroll_area ||
			   entity.has_ui_panel ||
			   entity.has_ui_table ||
			   entity.has_ui_input ||
			   entity.has_ui_checkbox) &&
		   !entity.has_ui_layout { return scene, fail(.Invalid_Field, fmt.tprintf("UI component on '%s' requires ui_layout", entity.name)) }
		if entity.has_ui_layout &&
		   (entity.ui_layout.size.x <= 0 ||
				   entity.ui_layout.size.y <= 0 ||
				   entity.ui_layout.border_width < 0 ||
				   entity.ui_layout.corner_radius < 0 ||
				   !vec4_is_non_negative(entity.ui_layout.margin) ||
				   !vec4_is_non_negative(
						   entity.ui_layout.padding,
					   )) { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' requires positive size and non-negative margin, padding, border width, and corner radius", entity.name)) }
		container_count := 0
		if entity.has_ui_hstack { container_count += 1 }
		if entity.has_ui_vstack { container_count += 1 }
		if entity.has_ui_table { container_count += 1 }
		if container_count >
		   1 { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' can only use one of ui_hstack, ui_vstack, or ui_table", entity.name)) }
		if (entity.has_ui_hstack &&
			   (entity.ui_hstack.gap < 0 ||
					   entity.ui_hstack.min_size < 0 ||
					   entity.ui_hstack.draggable && !entity.ui_hstack.fill)) ||
		   (entity.has_ui_vstack &&
				   (entity.ui_vstack.gap < 0 ||
						   entity.ui_vstack.min_size < 0 ||
						   entity.ui_vstack.draggable &&
							   !entity.ui_vstack.fill)) { return scene, fail(.Invalid_Field, fmt.tprintf("UI stack '%s' requires non-negative gap/min_size and draggable requires fill", entity.name)) }
		if entity.has_ui_scroll_area &&
		   (entity.ui_scroll_area.scroll_speed <= 0 ||
				   entity.ui_scroll_area.smoothness <=
					   0) { return scene, fail(.Invalid_Field, fmt.tprintf("UI scroll area '%s' requires positive scroll_speed and smoothness", entity.name)) }
		if entity.has_ui_panel &&
		   entity.ui_panel.title != "" &&
		   (entity.ui_panel.title_size <= 0 ||
				   entity.ui_panel.title_height <=
					   0) { return scene, fail(.Invalid_Field, fmt.tprintf("UI panel '%s' requires positive title_size/title_height when titled", entity.name)) }
		if entity.has_ui_panel &&
		   entity.ui_panel.collapsible &&
		   entity.ui_panel.title ==
			   "" { return scene, fail(.Invalid_Field, fmt.tprintf("collapsible UI panel '%s' requires a title", entity.name)) }
		if entity.has_ui_panel &&
		   entity.ui_panel.collapsed &&
		   !entity.ui_panel.collapsible { return scene, fail(.Invalid_Field, fmt.tprintf("collapsed UI panel '%s' must be collapsible", entity.name)) }
		if entity.has_ui_table &&
		   (entity.ui_table.columns < 1 ||
				   entity.ui_table.columns > 64 ||
				   entity.ui_table.column_gap < 0 ||
				   entity.ui_table.row_gap <
					   0) { return scene, fail(.Invalid_Field, fmt.tprintf("UI table '%s' requires 1..64 columns and non-negative gaps", entity.name)) }
		content_count := 0
		if entity.has_ui_text { content_count += 1 }
		if entity.has_ui_button { content_count += 1 }
		if entity.has_ui_input { content_count += 1 }
		if entity.has_ui_checkbox { content_count += 1 }
		if content_count >
		   1 { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' can only use one of ui_text, ui_button, ui_input, or ui_checkbox", entity.name)) }
		if entity.has_ui_text &&
		   (entity.ui_text.text == "" ||
				   entity.ui_text.size <=
					   0) { return scene, fail(.Invalid_Field, fmt.tprintf("UI text entity '%s' requires text and positive size", entity.name)) }
		if entity.has_ui_button &&
		   (entity.ui_button.text == "" ||
				   entity.ui_button.size <=
					   0) { return scene, fail(.Invalid_Field, fmt.tprintf("UI button entity '%s' requires text and positive size", entity.name)) }
		if entity.has_ui_input && entity.ui_input.size <= 0 {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI input entity '%s' requires positive size", entity.name),
			)
		}
		if entity.has_ui_checkbox && entity.ui_checkbox.box_size <= 0 {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI checkbox entity '%s' requires positive box_size", entity.name),
			)
		}
	}
	for entity in scene.entities {
		if !entity.has_ui_layout || entity.ui_layout.parent == (shared.Entity_UUID{}) {
			continue
		}
		found_parent := false
		for candidate in scene.entities {
			if candidate.id == entity.ui_layout.parent && candidate.has_ui_layout {
				found_parent = true
				break
			}
		}
		if !found_parent {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI parent for '%s' does not exist", entity.name),
			)
		}
		if entity.ui_layout.parent == entity.id {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI entity '%s' cannot parent itself", entity.name),
			)
		}
	}
	for entity in scene.entities {
		if !entity.has_ui_layout {
			continue
		}
		parent := entity.ui_layout.parent
		steps := 0
		for parent != (shared.Entity_UUID{}) {
			steps += 1
			if steps > len(scene.entities) {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("UI hierarchy containing '%s' has a cycle", entity.name),
				)
			}
			next: shared.Entity_UUID
			for candidate in scene.entities {
				if candidate.id == parent && candidate.has_ui_layout {
					next = candidate.ui_layout.parent
					break
				}
			}
			parent = next
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

vec4_is_non_negative :: proc(value: Vec4) -> bool {
	return value.x >= 0 && value.y >= 0 && value.z >= 0 && value.w >= 0
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

parse_ui_text_alignment :: proc(value: string) -> (out: shared.UI_Text_Alignment, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .Left, false
	}
	switch text {
		case "left":
			return .Left, true
		case "center":
			return .Center, true
		case "right":
			return .Right, true
		case:
			return .Left, false
	}
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

parse_vec2 :: proc(value: string) -> (out: Vec2, ok: bool) {
	parts, valid := parse_number_array(
		value,
		2,
	); if !valid { return out, false }; defer delete(parts)
	out.x, ok = parse_f32(
		parts[0],
	); if !ok { return out, false }; out.y, ok = parse_f32(parts[1]); return out, ok
}

parse_vec4 :: proc(value: string) -> (out: Vec4, ok: bool) {
	parts, valid := parse_number_array(
		value,
		4,
	); if !valid { return out, false }; defer delete(parts)
	out.x, ok = parse_f32(
		parts[0],
	); if !ok { return out, false }; out.y, ok = parse_f32(parts[1]); if !ok { return out, false }; out.z, ok = parse_f32(parts[2]); if !ok { return out, false }; out.w, ok = parse_f32(parts[3]); return out, ok
}

parse_number_array :: proc(value: string, count: int) -> ([]string, bool) {text :=
		strings.trim_space(value)
	if len(text) < 3 || text[0] != '[' || text[len(text) - 1] != ']' { return nil, false }
	parts := strings.split(text[1:len(text) - 1], ",")
	if len(parts) != count { delete(parts); return nil, false }
	return parts, true}

parse_f32 :: proc(value: string) -> (out: f32, ok: bool) {
	return strconv.parse_f32(strings.trim_space(value))
}

parse_int :: proc(value: string) -> (out: int, ok: bool) {
	number, parsed := parse_f32(value)
	if !parsed { return 0, false }
	out = int(number)
	return out, f32(out) == number
}

parse_bool :: proc(value: string) -> (out: bool, ok: bool) {
	text := strings.trim_space(value)
	if text == "true" { return true, true }
	if text == "false" { return false, true }
	return false, false
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
	if strings.has_prefix(path, "/") ||
	   strings.has_prefix(path, "../") ||
	   strings.has_suffix(path, "/..") {
		return false
	}
	if path == "." || path == ".." || strings.contains(path, "./") {
		return false
	}
	return true
}
