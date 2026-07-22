package project

import shared "../shared"
import "core:fmt"
import "core:math"
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

parse_project_resource :: proc(
	source: string,
) -> (
	resource: shared.Project_Resource,
	result: Parse_Result,
) {
	resource.texture.color_space = .SRGB
	resource.texture.generate_mipmaps = true
	resource.material.base_color = {1, 1, 1, 1}
	resource.geometry_lod.radius = 0.5
	section := ""
	type_name := ""
	geometry_screen_radius_count := 0
	text := source
	for raw_line in strings.split_lines_iterator(&text) {
		line := strip_comment(strings.trim_space(raw_line))
		if line == "" {
			continue
		}
		if line == "[material]" {
			section = "material"
			continue
		}
		if line == "[texture]" {
			section = "texture"
			continue
		}
		if line == "[model]" {
			section = "model"
			continue
		}
		if line == "[environment]" {
			section = "environment"
			continue
		}
		if line == "[geometry_lod]" {
			section = "geometry_lod"
			continue
		}
		if len(line) > 0 && line[0] == '[' {
			return resource, fail(
				.Invalid_Syntax,
				fmt.tprintf("unknown resource section '%s'", line),
			)
		}
		key, value, found := split_assignment(line)
		if !found {
			return resource, fail(
				.Invalid_Syntax,
				fmt.tprintf("expected key/value assignment, got '%s'", line),
			)
		}
		if section == "texture" {
			switch key {
				case "source":
					resource.texture.source, found = parse_basic_string(value)
					if found && !valid_resource_texture_path(resource.texture.source) {
						return resource, fail(
							.Invalid_Path,
							"texture.source must be a safe .png path under assets/",
						)
					}
				case "color_space":
					color_space: string
					color_space, found = parse_basic_string(value)
					if found {
						switch color_space {
							case "srgb":
								resource.texture.color_space = .SRGB
							case "linear":
								resource.texture.color_space = .Linear
							case:
								found = false
						}
					}
				case "generate_mipmaps":
					resource.texture.generate_mipmaps, found = parse_bool(value)
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown texture field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid texture.%s", key))
			}
			continue
		}
		if section == "model" {
			switch key {
				case "source":
					resource.model.source, found = parse_basic_string(value)
					if found && !valid_resource_model_path(resource.model.source) {
						return resource, fail(
							.Invalid_Path,
							"model.source must be a safe .gltf or .glb path under assets/",
						)
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown model field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid model.%s", key))
			}
			continue
		}
		if section == "environment" {
			switch key {
				case "source":
					resource.environment.source, found = parse_basic_string(value)
					if found && !valid_resource_environment_path(resource.environment.source) {
						return resource, fail(
							.Invalid_Path,
							"environment.source must be a safe .hdr path under assets/",
						)
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown environment field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid environment.%s", key))
			}
			continue
		}
		if section == "material" {
			switch key {
				case "base_color":
					resource.material.base_color, found = parse_vec4(value)
				case "emissive":
					resource.material.emissive, found = parse_vec3(value)
				case "texture":
					raw_texture: string
					raw_texture, found = parse_basic_string(value)
					if found {
						resource.material.texture, found = shared.resource_uuid_parse(raw_texture)
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown material field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid material.%s", key))
			}
			continue
		}
		if section == "geometry_lod" {
			switch key {
				case "radius":
					resource.geometry_lod.radius, found = parse_f32(value)
				case "subdivisions":
					resource.geometry_lod.lod_count, found = parse_fixed_int_list(
						value,
						&resource.geometry_lod.subdivisions,
					)
				case "screen_radii":
					geometry_screen_radius_count, found = parse_fixed_f32_list(
						value,
						&resource.geometry_lod.screen_radii,
					)
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown geometry_lod field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid geometry_lod.%s", key))
			}
			continue
		}
		switch key {
			case "id":
				raw_id, string_ok := parse_basic_string(value)
				if string_ok {
					resource.id, found = shared.resource_uuid_parse(raw_id)
				} else {
					found = false
				}
			case "type":
				type_name, found = parse_basic_string(value)
			case "name":
				resource.name, found = parse_basic_string(value)
			case:
				return resource, fail(
					.Invalid_Field,
					fmt.tprintf("unknown resource field '%s'", key),
				)
		}
		if !found {
			return resource, fail(.Invalid_Field, fmt.tprintf("invalid resource.%s", key))
		}
	}
	if resource.id == (shared.Resource_UUID{}) {
		return resource, fail(.Missing_Field, "resource is missing id")
	}
	if type_name == "" {
		return resource, fail(.Missing_Field, "resource is missing type")
	}
	switch type_name {
		case "scrapbot.texture":
			resource.kind = .Texture
		case "scrapbot.model":
			resource.kind = .Model
		case "scrapbot.environment":
			resource.kind = .Environment
		case "scrapbot.material":
			resource.kind = .Material
		case "scrapbot.geometry_lod":
			resource.kind = .Geometry_LOD
		case:
			return resource, fail(
				.Invalid_Field,
				fmt.tprintf("unsupported resource type '%s'", type_name),
			)
	}
	if resource.name == "" {
		return resource, fail(.Missing_Field, "resource is missing name")
	}
	if resource.kind == .Texture {
		if resource.texture.source == "" {
			return resource, fail(.Missing_Field, "texture.source is required")
		}
	} else if resource.kind == .Model {
		if resource.model.source == "" {
			return resource, fail(.Missing_Field, "model.source is required")
		}
	} else if resource.kind == .Environment {
		if resource.environment.source == "" {
			return resource, fail(.Missing_Field, "environment.source is required")
		}
	} else if resource.kind == .Material {
		if !finite_vec4(resource.material.base_color) {
			return resource, fail(.Invalid_Field, "material.base_color must be finite")
		}
		if !finite_vec3(resource.material.emissive) ||
		   resource.material.emissive.x < 0 ||
		   resource.material.emissive.y < 0 ||
		   resource.material.emissive.z < 0 {
			return resource, fail(
				.Invalid_Field,
				"material.emissive must be finite and non-negative",
			)
		}
	} else {
		geometry := resource.geometry_lod
		if math.is_nan(geometry.radius) || math.is_inf(geometry.radius) || geometry.radius <= 0 {
			return resource, fail(
				.Invalid_Field,
				"geometry_lod.radius must be positive and finite",
			)
		}
		if geometry.lod_count < 1 {
			return resource, fail(
				.Missing_Field,
				"geometry_lod.subdivisions must contain at least one level",
			)
		}
		if geometry_screen_radius_count != geometry.lod_count - 1 {
			return resource, fail(
				.Invalid_Field,
				"geometry_lod.screen_radii must contain one threshold between each pair of levels",
			)
		}
		for subdivision in geometry.subdivisions[:geometry.lod_count] {
			if subdivision < 0 || subdivision > 4 {
				return resource, fail(
					.Invalid_Field,
					"geometry_lod.subdivisions must be between 0 and 4",
				)
			}
		}
		previous := f32(3.402823e38)
		for radius in geometry.screen_radii[:geometry.lod_count - 1] {
			if math.is_nan(radius) || math.is_inf(radius) || radius <= 0 || radius >= previous {
				return resource, fail(
					.Invalid_Field,
					"geometry_lod.screen_radii must be positive and strictly descending",
				)
			}
			previous = radius
		}
	}
	return resource, ok()
}

ok :: proc() -> Parse_Result {
	return {}
}

fail :: proc(err: Parse_Error, message: string) -> Parse_Result {
	return Parse_Result{err = err, message = message}
}

parse_project_config :: proc(source: string) -> (config: Project_Config, result: Parse_Result) {
	config.window = {
		width = shared.DEFAULT_WINDOW_WIDTH,
		height = shared.DEFAULT_WINDOW_HEIGHT,
	}
	config.render.environment_intensity = 1
	config.render.exposure = 1
	config.render.background_intensity = 1
	config.render.background_exposure = 1
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
		if line == "[window]" {
			section = "window"
			current_native_extension = nil
			current_font = nil
			continue
		}
		if line == "[render]" {
			section = "render"
			current_native_extension = nil
			current_font = nil
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
		if section == "window" {
			switch key {
				case "width":
					config.window.width, found = parse_int(value)
				case "height":
					config.window.height, found = parse_int(value)
				case:
					return config, fail(
						.Invalid_Field,
						fmt.tprintf("unknown window field '%s'", key),
					)
			}
			if !found ||
			   config.window.width <= 0 ||
			   config.window.height <= 0 ||
			   config.window.width > 16_384 ||
			   config.window.height > 16_384 {
				return config, fail(
					.Invalid_Field,
					"window width and height must be positive integers no greater than 16384",
				)
			}
			continue
		}
		if section == "render" {
			switch key {
				case "environment":
					raw_environment: string
					raw_environment, found = parse_basic_string(value)
					if found {
						config.render.environment, found = shared.resource_uuid_parse(
							raw_environment,
						)
					}
				case "environment_intensity":
					config.render.environment_intensity, found = parse_f32(value)
				case "environment_rotation":
					config.render.environment_rotation, found = parse_f32(value)
				case "exposure":
					config.render.exposure, found = parse_f32(value)
				case "background_visible":
					config.render.background_visible, found = parse_bool(value)
				case "background_environment":
					raw_background_environment: string
					raw_background_environment, found = parse_basic_string(value)
					if found {
						config.render.background_environment, found = shared.resource_uuid_parse(
							raw_background_environment,
						)
					}
				case "background_intensity":
					config.render.background_intensity, found = parse_f32(value)
				case "background_rotation":
					config.render.background_rotation, found = parse_f32(value)
				case "background_exposure":
					config.render.background_exposure, found = parse_f32(value)
				case "background_blur":
					config.render.background_blur, found = parse_f32(value)
				case:
					return config, fail(
						.Invalid_Field,
						fmt.tprintf("unknown render field '%s'", key),
					)
			}
			if !found ||
			   !finite_render_config(config.render) ||
			   config.render.environment_intensity < 0 ||
			   config.render.exposure <= 0 ||
			   config.render.background_intensity < 0 ||
			   config.render.background_exposure <= 0 ||
			   config.render.background_blur < 0 ||
			   config.render.background_blur > 1 {
				return config, fail(
					.Invalid_Field,
					"render values must be finite; intensities must be non-negative, exposures positive, and background blur between 0 and 1",
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
			current.scene_order = len(scene.entities) - 1
			section = "entity"
			continue
		}

		if line == "[entities.transform]" ||
		   line == "[entities.camera]" ||
		   line == "[entities.world_environment]" ||
		   line == "[entities.mesh]" ||
		   line == "[entities.geometry]" ||
		   line == "[entities.material]" ||
		   line == "[entities.model]" ||
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
		   line == "[entities.ui_list]" ||
		   line == "[entities.ui_progress]" ||
		   line == "[entities.ui_viewport]" ||
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
			if section == "world_environment" {
				current.has_world_environment = true
				current.world_environment = shared.world_environment_default()
			}
			if section == "shadow_receiver" { current.has_shadow_receiver = true }
			if section == "ui_layout" { current.has_ui_layout = true }
			if section == "ui_hstack" { current.has_ui_hstack = true }
			if section == "ui_vstack" { current.has_ui_vstack = true }
			if section == "ui_scroll_area" {
				current.has_ui_scroll_area = true
				current.ui_scroll_area = shared.ui_scroll_area_default()
			}
			if section == "ui_panel" {
				current.has_ui_panel = true
				current.ui_panel = shared.ui_panel_default()
			}
			if section == "ui_table" {
				current.has_ui_table = true
				current.ui_table = shared.ui_table_default()
			}
			if section == "ui_list" {
				current.has_ui_list = true
				current.ui_list = shared.ui_list_default()
			}
			if section == "ui_progress" {
				current.has_ui_progress = true
				current.ui_progress = shared.ui_progress_default()
			}
			if section == "ui_viewport" {
				current.has_ui_viewport = true
				current.ui_viewport = shared.ui_viewport_default()
			}
			if section == "ui_text" {
				current.has_ui_text = true
				current.ui_text = shared.ui_text_default()
			}
			if section == "ui_button" {
				current.has_ui_button = true
				current.ui_button = shared.ui_button_default()
			}
			if section == "ui_input" {
				current.has_ui_input = true
				current.ui_input = shared.ui_input_default()
			}
			if section == "ui_checkbox" {
				current.has_ui_checkbox = true
				current.ui_checkbox = shared.ui_checkbox_default()
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
					case "parent":
						raw_parent, string_ok := parse_basic_string(value)
						if string_ok {
							current.transform.parent, found = shared.entity_uuid_parse(raw_parent)
						} else {
							found = false
						}
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
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid transform.%s", key))
				}
			case "camera":
				if !current.has_camera {
					current.camera.exposure = 1
				}
				current.has_camera = true
				switch key {
					case "fov":
						current.camera.fov, found = parse_f32(value)
					case "near":
						current.camera.near, found = parse_f32(value)
					case "far":
						current.camera.far, found = parse_f32(value)
					case "exposure":
						current.camera.exposure, found = parse_f32(value)
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
			case "world_environment":
				current.has_world_environment = true
				switch key {
					case "lighting":
						current.world_environment.lighting, found = parse_basic_string(value)
					case "lighting_intensity":
						current.world_environment.lighting_intensity, found = parse_f32(value)
					case "lighting_rotation":
						current.world_environment.lighting_rotation, found = parse_f32(value)
					case "exposure":
						current.world_environment.exposure, found = parse_f32(value)
					case "background_visible":
						current.world_environment.background_visible, found = parse_bool(value)
					case "background":
						current.world_environment.background, found = parse_basic_string(value)
					case "background_intensity":
						current.world_environment.background_intensity, found = parse_f32(value)
					case "background_rotation":
						current.world_environment.background_rotation, found = parse_f32(value)
					case "background_exposure":
						current.world_environment.background_exposure, found = parse_f32(value)
					case "background_blur":
						current.world_environment.background_blur, found = parse_f32(value)
					case "sky_tint":
						current.world_environment.sky_tint, found = parse_vec3(value)
					case "ground_color":
						current.world_environment.ground_color, found = parse_vec3(value)
					case "turbidity":
						current.world_environment.turbidity, found = parse_f32(value)
					case "atmosphere_thickness":
						current.world_environment.atmosphere_thickness, found = parse_f32(value)
					case "horizon_softness":
						current.world_environment.horizon_softness, found = parse_f32(value)
					case "sun_size":
						current.world_environment.sun_size, found = parse_f32(value)
					case "sun_glow":
						current.world_environment.sun_glow, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown world_environment field '%s'", key),
						)
				}
				if !found || !valid_world_environment(current.world_environment) {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("invalid world_environment.%s", key),
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
			case "model":
				current.has_model = true
				if key !=
				   "resource" { return scene, fail(.Invalid_Field, "model only supports resource") }
				current.model_resource, found = parse_basic_string(value)
				if !found || current.model_resource == "" {
					return scene, fail(
						.Invalid_Field,
						"model.resource must be a non-empty resource UUID",
					)
				}
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
					case "min_size":
						current.ui_layout.min_size, found = parse_vec2(value)
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
					case "fill_width":
						current.ui_layout.fill_width, found = parse_bool(value)
					case "fill_height":
						current.ui_layout.fill_height, found = parse_bool(value)
					case "fit_content_width":
						current.ui_layout.fit_content_width, found = parse_bool(value)
					case "fit_content_height":
						current.ui_layout.fit_content_height, found = parse_bool(value)
					case "fixed_in_fill":
						current.ui_layout.fixed_in_fill, found = parse_bool(value)
					case "tree_item":
						current.ui_layout.tree_item, found = parse_bool(value)
					case "tree_parent":
						raw_parent, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_layout.tree_parent, found = shared.entity_uuid_parse(
								raw_parent,
							)
						} else {
							found = false
						}
					case "tree_order":
						current.ui_layout.tree_order, found = parse_int(value)
					case "tree_collapsed":
						current.ui_layout.tree_collapsed, found = parse_bool(value)
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
				switch key {
					case "scroll_speed":
						current.ui_scroll_area.scroll_speed, found = parse_f32(value)
					case "smoothness":
						current.ui_scroll_area.smoothness, found = parse_f32(value)
					case "scrollbar_width":
						current.ui_scroll_area.scrollbar_width, found = parse_f32(value)
					case "scrollbar_right":
						current.ui_scroll_area.scrollbar_right, found = parse_f32(value)
					case "scrollbar_vertical_inset":
						current.ui_scroll_area.scrollbar_vertical_inset, found = parse_f32(value)
					case "minimum_thumb_size":
						current.ui_scroll_area.minimum_thumb_size, found = parse_f32(value)
					case "scrollbar_corner_radius":
						current.ui_scroll_area.scrollbar_corner_radius, found = parse_f32(value)
					case "scrollbar_track_color":
						current.ui_scroll_area.scrollbar_track_color, found = parse_vec4(value)
					case "scrollbar_thumb_color":
						current.ui_scroll_area.scrollbar_thumb_color, found = parse_vec4(value)
					case:
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
					case "disclosure_size":
						current.ui_panel.disclosure_size, found = parse_f32(value)
					case "disclosure_margin":
						current.ui_panel.disclosure_margin, found = parse_f32(value)
					case "disclosure_gap":
						current.ui_panel.disclosure_gap, found = parse_f32(value)
					case "disclosure_corner_radius":
						current.ui_panel.disclosure_corner_radius, found = parse_f32(value)
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
					case "proportional_columns":
						current.ui_table.proportional_columns, found = parse_bool(value)
					case "resizable_columns":
						current.ui_table.resizable_columns, found = parse_bool(value)
					case "min_column_width":
						current.ui_table.min_column_width, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_table field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_table.%s", key)) }
			case "ui_list":
				current.has_ui_list = true
				switch key {
					case "selected":
						raw_selected: string
						raw_selected, found = parse_basic_string(value)
						if found {
							current.ui_list.selected, found = shared.entity_uuid_parse(
								raw_selected,
							)
						}
					case "gap":
						current.ui_list.gap, found = parse_f32(value)
					case "selection_background":
						current.ui_list.selection_background, found = parse_vec4(value)
					case "hover_background":
						current.ui_list.hover_background, found = parse_vec4(value)
					case "active_background":
						current.ui_list.active_background, found = parse_vec4(value)
					case "draggable":
						current.ui_list.draggable, found = parse_bool(value)
					case "drag_threshold":
						current.ui_list.drag_threshold, found = parse_f32(value)
					case "drop_edge_fraction":
						current.ui_list.drop_edge_fraction, found = parse_f32(value)
					case "drop_target_background":
						current.ui_list.drop_target_background, found = parse_vec4(value)
					case "drop_indicator_color":
						current.ui_list.drop_indicator_color, found = parse_vec4(value)
					case "drop_indicator_thickness":
						current.ui_list.drop_indicator_thickness, found = parse_f32(value)
					case "drop_indicator_inset":
						current.ui_list.drop_indicator_inset, found = parse_f32(value)
					case "tree_enabled":
						current.ui_list.tree_enabled, found = parse_bool(value)
					case "tree_indent":
						current.ui_list.tree_indent, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_list field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_list.%s", key)) }
			case "ui_progress":
				current.has_ui_progress = true
				switch key {
					case "value":
						current.ui_progress.value, found = parse_f32(value)
					case "maximum":
						current.ui_progress.maximum, found = parse_f32(value)
					case "fill_color":
						current.ui_progress.fill_color, found = parse_vec4(value)
					case "background_color":
						current.ui_progress.background_color, found = parse_vec4(value)
					case "inset":
						current.ui_progress.inset, found = parse_vec4(value)
					case "corner_radius":
						current.ui_progress.corner_radius, found = parse_f32(value)
					case "right_to_left":
						current.ui_progress.right_to_left, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_progress field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_progress.%s", key))
				}
			case "ui_viewport":
				current.has_ui_viewport = true
				switch key {
					case "camera":
						raw: string
						raw, found = parse_basic_string(value)
						if found {
							current.ui_viewport.camera, found = shared.entity_uuid_parse(raw)
						}
					case "root":
						raw: string
						raw, found = parse_basic_string(value)
						if found {
							current.ui_viewport.root, found = shared.entity_uuid_parse(raw)
						}
					case "resource":
						raw: string
						raw, found = parse_basic_string(value)
						if found {
							current.ui_viewport.resource, found = shared.resource_uuid_parse(raw)
						}
					case "orbit":
						current.ui_viewport.orbit, found = parse_vec2(value)
					case "distance":
						current.ui_viewport.distance, found = parse_f32(value)
					case "clear_color":
						current.ui_viewport.clear_color, found = parse_vec4(value)
					case "interactive":
						current.ui_viewport.interactive, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_viewport field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_viewport.%s", key))
				}
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
						current.ui_button.size, found = parse_f32(value); case "alignment":
						current.ui_button.alignment, found = parse_ui_text_alignment(
							value,
						); case "hover_background":
						current.ui_button.hover_background, found = parse_vec4(
							value,
						); case "active_background":
						current.ui_button.active_background, found = parse_vec4(
							value,
						); case "hover_color":
						current.ui_button.hover_color, found = parse_vec4(
							value,
						); case "active_color":
						current.ui_button.active_color, found = parse_vec4(value); case "icon":
						current.ui_button.icon, found = parse_ui_icon(value); case "icon_inset":
						current.ui_button.icon_inset, found = parse_f32(value); case "icon_stroke":
						current.ui_button.icon_stroke, found = parse_f32(
							value,
						); case "panel_action":
						current.ui_button.panel_action, found = parse_bool(value); case:
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
					case "prefix":
						current.ui_input.prefix, found = parse_basic_string(value)
					case "color":
						current.ui_input.color, found = parse_vec4(value)
					case "prefix_color":
						current.ui_input.prefix_color, found = parse_vec4(value)
					case "prefix_background":
						current.ui_input.prefix_background, found = parse_vec4(value)
					case "size":
						current.ui_input.size, found = parse_f32(value)
					case "prefix_width":
						current.ui_input.prefix_width, found = parse_f32(value)
					case "selection_background":
						current.ui_input.selection_background, found = parse_vec4(value)
					case "focus_border_color":
						current.ui_input.focus_border_color, found = parse_vec4(value)
					case "invalid_border_color":
						current.ui_input.invalid_border_color, found = parse_vec4(value)
					case "caret_color":
						current.ui_input.caret_color, found = parse_vec4(value)
					case "number":
						current.ui_input.number, found = parse_f32(value)
					case "step":
						current.ui_input.step, found = parse_f32(value)
					case "minimum":
						current.ui_input.minimum, found = parse_f32(value)
					case "maximum":
						current.ui_input.maximum, found = parse_f32(value)
					case "prefix_gap":
						current.ui_input.prefix_gap, found = parse_f32(value)
					case "prefix_corner_radius":
						current.ui_input.prefix_corner_radius, found = parse_f32(value)
					case "prefix_text_padding":
						current.ui_input.prefix_text_padding, found = parse_f32(value)
					case "selection_corner_radius":
						current.ui_input.selection_corner_radius, found = parse_f32(value)
					case "focus_border_width":
						current.ui_input.focus_border_width, found = parse_f32(value)
					case "invalid_border_width":
						current.ui_input.invalid_border_width, found = parse_f32(value)
					case "caret_width":
						current.ui_input.caret_width, found = parse_f32(value)
					case "caret_inset":
						current.ui_input.caret_inset, found = parse_f32(value)
					case "read_only":
						current.ui_input.read_only, found = parse_bool(value)
					case "numeric":
						current.ui_input.numeric, found = parse_bool(value)
					case "draggable":
						current.ui_input.draggable, found = parse_bool(value)
					case "has_minimum":
						current.ui_input.has_minimum, found = parse_bool(value)
					case "has_maximum":
						current.ui_input.has_maximum, found = parse_bool(value)
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
					case "corner_radius":
						current.ui_checkbox.corner_radius, found = parse_f32(value)
					case "border_width":
						current.ui_checkbox.border_width, found = parse_f32(value)
					case "check_inset":
						current.ui_checkbox.check_inset, found = parse_f32(value)
					case "check_corner_radius":
						current.ui_checkbox.check_corner_radius, found = parse_f32(value)
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
				if number, number_found := parse_f32(value); number_found {
					append(
						&current_component.number_fields,
						Named_Number{name = key, value = number},
					)
					continue
				}
				if vec2, vec2_found := parse_vec2(value); vec2_found {
					append(&current_component.vec2_fields, Named_Vec2{name = key, value = vec2})
					continue
				}
				if vec3, vec3_found := parse_vec3(value); vec3_found {
					append(&current_component.vec3_fields, Named_Vec3{name = key, value = vec3})
					continue
				}
				if vec4, vec4_found := parse_vec4(value); vec4_found {
					append(&current_component.vec4_fields, Named_Vec4{name = key, value = vec4})
					continue
				}
				{
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf(
							"%s.%s must be a number, vec2, vec3, or vec4 value",
							current_component.name,
							key,
						),
					)
				}
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
	entity_indices := make(map[shared.Entity_UUID]int, len(scene.entities))
	defer delete(entity_indices)
	for entity, index in scene.entities {
		if entity.id == (shared.Entity_UUID{}) {
			return scene, fail(.Missing_Field, fmt.tprintf("entity %d is missing id", index))
		}
		if entity.name == "" {
			return scene, fail(.Missing_Field, fmt.tprintf("entity %d is missing name", index))
		}
		if _, duplicate := entity_indices[entity.id]; duplicate {
			return scene, fail(.Invalid_Field, fmt.tprintf("entity %d has a duplicate id", index))
		}
		entity_indices[entity.id] = index
		if entity.has_transform && entity.transform.scale == (Vec3{}) {
			scene.entities[index].transform.scale = Vec3{1, 1, 1}
		}
		if entity.has_camera {
			exposure := entity.camera.exposure
			if math.is_nan(exposure) || math.is_inf(exposure) || exposure <= 0 {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"camera exposure on '%s' must be finite and positive",
						entity.name,
					),
				)
			}
		}
		if (entity.has_ui_text ||
			   entity.has_ui_button ||
			   entity.has_ui_hstack ||
			   entity.has_ui_vstack ||
			   entity.has_ui_scroll_area ||
			   entity.has_ui_panel ||
			   entity.has_ui_table ||
			   entity.has_ui_list ||
			   entity.has_ui_progress ||
			   entity.has_ui_viewport ||
			   entity.has_ui_input ||
			   entity.has_ui_checkbox) &&
		   !entity.has_ui_layout { return scene, fail(.Invalid_Field, fmt.tprintf("UI component on '%s' requires ui_layout", entity.name)) }
		if entity.has_ui_layout && !shared.ui_layout_is_valid(entity.ui_layout) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI entity '%s' requires positive size and non-negative margin, padding, border width, and corner radius",
					entity.name,
				),
			)
		}
		container_count := 0
		if entity.has_ui_hstack { container_count += 1 }
		if entity.has_ui_vstack { container_count += 1 }
		if entity.has_ui_table { container_count += 1 }
		if entity.has_ui_list { container_count += 1 }
		if container_count >
		   1 { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' can only use one of ui_hstack, ui_vstack, ui_table, or ui_list", entity.name)) }
		if (entity.has_ui_hstack && !shared.ui_stack_is_valid(entity.ui_hstack)) ||
		   (entity.has_ui_vstack && !shared.ui_stack_is_valid(entity.ui_vstack)) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI stack '%s' requires non-negative gap/min_size and draggable requires fill",
					entity.name,
				),
			)
		}
		if entity.has_ui_scroll_area && !shared.ui_scroll_area_is_valid(entity.ui_scroll_area) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI scroll area '%s' requires positive scroll_speed and smoothness",
					entity.name,
				),
			)
		}
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
		if entity.has_ui_panel && !shared.ui_panel_is_valid(entity.ui_panel) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI panel '%s' has invalid title-action geometry", entity.name),
			)
		}
		if entity.has_ui_table && !shared.ui_table_is_valid(entity.ui_table) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI table '%s' requires 1..64 columns, non-negative gaps and minimum width, and proportional columns when resizable",
					entity.name,
				),
			)
		}
		if entity.has_ui_list && !shared.ui_list_is_valid(entity.ui_list) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI list '%s' requires non-negative gap and drag geometry",
					entity.name,
				),
			)
		}
		if entity.has_ui_progress && !shared.ui_progress_is_valid(entity.ui_progress) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI progress '%s' requires a positive maximum and non-negative inset/corner radius",
					entity.name,
				),
			)
		}
		if entity.has_ui_viewport && !shared.ui_viewport_is_valid(entity.ui_viewport) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("ui_viewport on '%s' is invalid", entity.name),
			)
		}
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
		if entity.has_ui_button && !shared.ui_button_is_valid(entity.ui_button) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI button entity '%s' requires text or an icon and valid sizing",
					entity.name,
				),
			)
		}
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
		if entity.has_transform && entity.transform.parent != (shared.Entity_UUID{}) {
			parent_index, found_parent := entity_indices[entity.transform.parent]
			if !found_parent {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("transform parent for '%s' does not exist", entity.name),
				)
			}
			if entity.transform.parent == entity.id {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("entity '%s' cannot parent itself", entity.name),
				)
			}
		}
	}
	visit_state := make([]u8, len(scene.entities))
	defer delete(visit_state)
	visit_path := make([dynamic]int, 0, len(scene.entities))
	defer delete(visit_path)
	for _, start_index in scene.entities {
		if !scene.entities[start_index].has_transform || visit_state[start_index] == 2 {
			continue
		}
		clear(&visit_path)
		cursor := start_index
		for {
			if visit_state[cursor] == 2 {
				break
			}
			if visit_state[cursor] == 1 {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"transform hierarchy containing '%s' has a cycle",
						scene.entities[start_index].name,
					),
				)
			}
			visit_state[cursor] = 1
			append(&visit_path, cursor)
			parent := scene.entities[cursor].transform.parent
			if parent == (shared.Entity_UUID{}) {
				break
			}
			cursor, _ = entity_indices[parent]
			if !scene.entities[cursor].has_transform {
				break
			}
		}
		for index in visit_path {
			visit_state[index] = 2
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

parse_ui_icon :: proc(value: string) -> (out: shared.UI_Icon, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .None, false
	}
	switch text {
		case "", "none":
			return .None, true
		case "close":
			return .Close, true
		case "plus":
			return .Plus, true
		case "chevron_right":
			return .Chevron_Right, true
		case "chevron_down":
			return .Chevron_Down, true
	}
	return .None, false
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

parse_fixed_int_list :: proc(
	value: string,
	out: ^[shared.MAX_GEOMETRY_LODS]int,
) -> (
	count: int,
	ok: bool,
) {
	if out == nil {
		return 0, false
	}
	text := strings.trim_space(value)
	if len(text) < 2 || text[0] != '[' || text[len(text) - 1] != ']' {
		return 0, false
	}
	body := strings.trim_space(text[1:len(text) - 1])
	if body == "" {
		return 0, true
	}
	parts := strings.split(body, ",")
	defer delete(parts)
	if len(parts) > len(out^) {
		return 0, false
	}
	for part, index in parts {
		out[index], ok = parse_int(part)
		if !ok {
			return 0, false
		}
	}
	return len(parts), true
}

parse_fixed_f32_list :: proc(
	value: string,
	out: ^[shared.MAX_GEOMETRY_LODS - 1]f32,
) -> (
	count: int,
	ok: bool,
) {
	if out == nil {
		return 0, false
	}
	text := strings.trim_space(value)
	if len(text) < 2 || text[0] != '[' || text[len(text) - 1] != ']' {
		return 0, false
	}
	body := strings.trim_space(text[1:len(text) - 1])
	if body == "" {
		return 0, true
	}
	parts := strings.split(body, ",")
	defer delete(parts)
	if len(parts) > len(out^) {
		return 0, false
	}
	for part, index in parts {
		out[index], ok = parse_f32(part)
		if !ok {
			return 0, false
		}
	}
	return len(parts), true
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

valid_resource_texture_path :: proc(path: string) -> bool {
	return(
		strings.has_prefix(path, "assets/") &&
		strings.has_suffix(path, ".png") &&
		is_safe_relative_path(path) \
	)
}

valid_resource_model_path :: proc(path: string) -> bool {
	if !strings.has_prefix(path, "assets/") || !is_safe_relative_path(path) {
		return false
	}
	if !strings.has_suffix(path, ".gltf") && !strings.has_suffix(path, ".glb") {
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

valid_resource_environment_path :: proc(path: string) -> bool {
	return(
		strings.has_prefix(path, "assets/") &&
		strings.has_suffix(path, ".hdr") &&
		is_safe_relative_path(path) \
	)
}

finite_render_config :: proc(value: shared.Project_Render_Config) -> bool {
	return(
		!math.is_nan(value.environment_intensity) &&
		!math.is_inf(value.environment_intensity) &&
		!math.is_nan(value.environment_rotation) &&
		!math.is_inf(value.environment_rotation) &&
		!math.is_nan(value.exposure) &&
		!math.is_inf(value.exposure) &&
		!math.is_nan(value.background_intensity) &&
		!math.is_inf(value.background_intensity) &&
		!math.is_nan(value.background_rotation) &&
		!math.is_inf(value.background_rotation) &&
		!math.is_nan(value.background_exposure) &&
		!math.is_inf(value.background_exposure) &&
		!math.is_nan(value.background_blur) &&
		!math.is_inf(value.background_blur) \
	)
}

valid_world_environment :: proc(value: shared.World_Environment_Component) -> bool {
	return shared.world_environment_is_valid(value)
}

finite_vec3 :: proc(value: Vec3) -> bool {
	return(
		!math.is_nan(value.x) &&
		!math.is_inf(value.x) &&
		!math.is_nan(value.y) &&
		!math.is_inf(value.y) &&
		!math.is_nan(value.z) &&
		!math.is_inf(value.z) \
	)
}

finite_vec4 :: proc(value: Vec4) -> bool {
	return(
		finite_vec3({value.x, value.y, value.z}) &&
		!math.is_nan(value.w) &&
		!math.is_inf(value.w) \
	)
}
