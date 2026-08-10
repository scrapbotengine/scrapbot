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
	resource.model.generate_lods = true
	resource.model.geometry_mode = .Inherit
	resource.model.lod_ratios = {0.5, 0.25, 0.125}
	resource.model.lod_screen_radii = {0.18, 0.07, 0.025}
	resource.model.lod_count = shared.MAX_GEOMETRY_LODS - 1
	resource.shader.spectral_surface.patch_size = 192
	resource.shader.spectral_surface.wind_speed = 11
	resource.shader.spectral_surface.wind_direction = {0.94, 0.34}
	resource.shader.spectral_surface.amplitude = 0.55
	resource.shader.spectral_surface.small_wave_damping = 0.35
	resource.shader.spectral_surface.choppiness = 0.85
	resource.material.base_color = {1, 1, 1, 1}
	resource.material.roughness = 0.8
	resource.material.alpha_cutoff = 0.5
	resource.geometry_lod.radius = 0.5
	resource.ui_theme.theme = shared.ui_theme_reduced_dark()
	section := ""
	type_name := ""
	geometry_screen_radius_count := 0
	model_lod_ratio_count := shared.MAX_GEOMETRY_LODS - 1
	model_lod_screen_radius_count := shared.MAX_GEOMETRY_LODS - 1
	ui_theme_base_found := false
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
		if line == "[icon_set]" {
			section = "icon_set"
			continue
		}
		if line == "[shader]" {
			section = "shader"
			continue
		}
		if line == "[shader.spectral_surface]" {
			section = "shader.spectral_surface"
			continue
		}
		if line == "[geometry_lod]" {
			section = "geometry_lod"
			continue
		}
		if line == "[theme]" {
			section = "theme"
			continue
		}
		if line == "[theme.palette]" {
			section = "theme.palette"
			continue
		}
		if line == "[theme.metrics]" {
			section = "theme.metrics"
			continue
		}
		if line == "[theme.typography]" {
			section = "theme.typography"
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
				case "generate_lods":
					resource.model.generate_lods, found = parse_bool(value)
				case "geometry_mode":
					mode_name: string
					mode_name, found = parse_basic_string(value)
					if found {
						resource.model.geometry_mode, found = shared.geometry_mode_from_name(
							mode_name,
						)
						found = found && resource.model.geometry_mode != .Inherit
					}
				case "lod_ratios":
					model_lod_ratio_count, found = parse_fixed_f32_list(
						value,
						&resource.model.lod_ratios,
					)
					resource.model.lod_count = model_lod_ratio_count
				case "lod_screen_radii":
					model_lod_screen_radius_count, found = parse_fixed_f32_list(
						value,
						&resource.model.lod_screen_radii,
					)
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
		if section == "icon_set" {
			switch key {
				case "source":
					resource.icon_set.source, found = parse_basic_string(value)
					if found && !valid_resource_icon_set_path(resource.icon_set.source) {
						return resource, fail(
							.Invalid_Path,
							"icon_set.source must be a safe directory path under assets/",
						)
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown icon_set field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid icon_set.%s", key))
			}
			continue
		}
		if section == "shader" {
			switch key {
				case "source":
					resource.shader.source, found = parse_basic_string(value)
					if found && !valid_resource_shader_path(resource.shader.source) {
						return resource, fail(
							.Invalid_Path,
							"shader.source must be a safe .wgsl path under shaders/",
						)
					}
				case "cull_mode":
					mode: string
					mode, found = parse_basic_string(value)
					if found {
						switch mode {
							case "back":
								resource.shader.cull_mode = .Back
							case "none":
								resource.shader.cull_mode = .None
							case:
								found = false
						}
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown shader field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid shader.%s", key))
			}
			continue
		}
		if section == "shader.spectral_surface" {
			switch key {
				case "enabled":
					resource.shader.spectral_surface.enabled, found = parse_bool(value)
				case "patch_size":
					resource.shader.spectral_surface.patch_size, found = parse_f32(value)
				case "wind_speed":
					resource.shader.spectral_surface.wind_speed, found = parse_f32(value)
				case "wind_direction":
					resource.shader.spectral_surface.wind_direction, found = parse_vec2(value)
				case "amplitude":
					resource.shader.spectral_surface.amplitude, found = parse_f32(value)
				case "small_wave_damping":
					resource.shader.spectral_surface.small_wave_damping, found = parse_f32(value)
				case "choppiness":
					resource.shader.spectral_surface.choppiness, found = parse_f32(value)
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown shader.spectral_surface field '%s'", key),
					)
			}
			if !found {
				return resource, fail(
					.Invalid_Field,
					fmt.tprintf("invalid shader.spectral_surface.%s", key),
				)
			}
			continue
		}
		if section == "material" {
			switch key {
				case "base_color":
					resource.material.base_color, found = parse_vec4(value)
				case "emissive":
					resource.material.emissive, found = parse_vec3(value)
				case "metallic":
					resource.material.metallic, found = parse_f32(value)
				case "roughness":
					resource.material.roughness, found = parse_f32(value)
				case "texture":
					raw_texture: string
					raw_texture, found = parse_basic_string(value)
					if found {
						resource.material.texture, found = shared.resource_uuid_parse(raw_texture)
					}
				case "shader":
					raw_shader: string
					raw_shader, found = parse_basic_string(value)
					if found {
						resource.material.shader, found = shared.resource_uuid_parse(raw_shader)
					}
				case "shader_parameters":
					resource.material.shader_parameters, found = parse_shader_parameters(value)
				case "alpha_mode":
					mode: string
					mode, found = parse_basic_string(value)
					if found {
						switch mode {
							case "opaque":
								resource.material.alpha_mode = .Opaque
							case "mask":
								resource.material.alpha_mode = .Mask
							case "blend":
								resource.material.alpha_mode = .Blend
							case:
								found = false
						}
					}
				case "alpha_cutoff":
					resource.material.alpha_cutoff, found = parse_f32(value)
				case "double_sided":
					resource.material.double_sided, found = parse_bool(value)
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
		if section == "theme" {
			switch key {
				case "base":
					base_name: string
					base_name, found = parse_basic_string(value)
					if found {
						resource.ui_theme.base, found = shared.ui_theme_name_parse(base_name)
					}
					if found {
						ui_theme_base_found = true
					}
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown theme field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid theme.%s", key))
			}
			continue
		}
		if section == "theme.palette" {
			switch key {
				case "canvas":
					resource.ui_theme.theme.palette.canvas, found = parse_vec4(value)
				case "region":
					resource.ui_theme.theme.palette.region, found = parse_vec4(value)
				case "panel":
					resource.ui_theme.theme.palette.panel, found = parse_vec4(value)
				case "raised":
					resource.ui_theme.theme.palette.raised, found = parse_vec4(value)
				case "control":
					resource.ui_theme.theme.palette.control, found = parse_vec4(value)
				case "overlay":
					resource.ui_theme.theme.palette.overlay, found = parse_vec4(value)
				case "border":
					resource.ui_theme.theme.palette.border, found = parse_vec4(value)
				case "border_strong":
					resource.ui_theme.theme.palette.border_strong, found = parse_vec4(value)
				case "text":
					resource.ui_theme.theme.palette.text, found = parse_vec4(value)
				case "text_secondary":
					resource.ui_theme.theme.palette.text_secondary, found = parse_vec4(value)
				case "text_muted":
					resource.ui_theme.theme.palette.text_muted, found = parse_vec4(value)
				case "accent":
					resource.ui_theme.theme.palette.accent, found = parse_vec4(value)
				case "accent_text":
					resource.ui_theme.theme.palette.accent_text, found = parse_vec4(value)
				case "accent_soft":
					resource.ui_theme.theme.palette.accent_soft, found = parse_vec4(value)
				case "hover":
					resource.ui_theme.theme.palette.hover, found = parse_vec4(value)
				case "active":
					resource.ui_theme.theme.palette.active, found = parse_vec4(value)
				case "selection":
					resource.ui_theme.theme.palette.selection, found = parse_vec4(value)
				case "focus":
					resource.ui_theme.theme.palette.focus, found = parse_vec4(value)
				case "warning":
					resource.ui_theme.theme.palette.warning, found = parse_vec4(value)
				case "warning_soft":
					resource.ui_theme.theme.palette.warning_soft, found = parse_vec4(value)
				case "danger":
					resource.ui_theme.theme.palette.danger, found = parse_vec4(value)
				case "danger_soft":
					resource.ui_theme.theme.palette.danger_soft, found = parse_vec4(value)
				case "data_engine":
					resource.ui_theme.theme.palette.data_engine, found = parse_vec4(value)
				case "data_native":
					resource.ui_theme.theme.palette.data_native, found = parse_vec4(value)
				case "data_script":
					resource.ui_theme.theme.palette.data_script, found = parse_vec4(value)
				case "axis_x":
					resource.ui_theme.theme.palette.axis_x, found = parse_vec4(value)
				case "axis_y":
					resource.ui_theme.theme.palette.axis_y, found = parse_vec4(value)
				case "axis_z":
					resource.ui_theme.theme.palette.axis_z, found = parse_vec4(value)
				case "axis_w":
					resource.ui_theme.theme.palette.axis_w, found = parse_vec4(value)
				case "light_overlay":
					resource.ui_theme.theme.palette.light_overlay, found = parse_vec4(value)
				case "dark_overlay":
					resource.ui_theme.theme.palette.dark_overlay, found = parse_vec4(value)
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown theme.palette field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid theme.palette.%s", key))
			}
			continue
		}
		if section == "theme.metrics" {
			switch key {
				case "text_size":
					resource.ui_theme.theme.metrics.text_size, found = parse_f32(value)
				case "small_text_size":
					resource.ui_theme.theme.metrics.small_text_size, found = parse_f32(value)
				case "control_height":
					resource.ui_theme.theme.metrics.control_height, found = parse_f32(value)
				case "row_height":
					resource.ui_theme.theme.metrics.row_height, found = parse_f32(value)
				case "title_height":
					resource.ui_theme.theme.metrics.title_height, found = parse_f32(value)
				case "radius_small":
					resource.ui_theme.theme.metrics.radius_small, found = parse_f32(value)
				case "radius":
					resource.ui_theme.theme.metrics.radius, found = parse_f32(value)
				case "radius_large":
					resource.ui_theme.theme.metrics.radius_large, found = parse_f32(value)
				case "border_width":
					resource.ui_theme.theme.metrics.border_width, found = parse_f32(value)
				case "gap_small":
					resource.ui_theme.theme.metrics.gap_small, found = parse_f32(value)
				case "gap":
					resource.ui_theme.theme.metrics.gap, found = parse_f32(value)
				case "gap_large":
					resource.ui_theme.theme.metrics.gap_large, found = parse_f32(value)
				case "padding_small":
					resource.ui_theme.theme.metrics.padding_small, found = parse_vec4(value)
				case "padding_control":
					resource.ui_theme.theme.metrics.padding_control, found = parse_vec4(value)
				case "padding_panel":
					resource.ui_theme.theme.metrics.padding_panel, found = parse_vec4(value)
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown theme.metrics field '%s'", key),
					)
			}
			if !found {
				return resource, fail(.Invalid_Field, fmt.tprintf("invalid theme.metrics.%s", key))
			}
			continue
		}
		if section == "theme.typography" {
			switch key {
				case "font":
					resource.ui_theme.theme.font, found = parse_basic_string(value)
					found = found && resource.ui_theme.theme.font != ""
				case:
					return resource, fail(
						.Invalid_Field,
						fmt.tprintf("unknown theme.typography field '%s'", key),
					)
			}
			if !found {
				return resource, fail(
					.Invalid_Field,
					fmt.tprintf("invalid theme.typography.%s", key),
				)
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
		case "scrapbot.icon_set":
			resource.kind = .Icon_Set
		case "scrapbot.shader":
			resource.kind = .Shader
		case "scrapbot.material":
			resource.kind = .Material
		case "scrapbot.geometry_lod":
			resource.kind = .Geometry_LOD
		case "scrapbot.ui_theme":
			resource.kind = .UI_Theme
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
		if resource.model.generate_lods {
			if resource.model.lod_count < 1 ||
			   model_lod_ratio_count != model_lod_screen_radius_count {
				return resource, fail(
					.Invalid_Field,
					"model LOD ratios and screen radii must contain the same non-zero number of levels",
				)
			}
			previous_ratio := f32(1)
			previous_radius := f32(3.402823e38)
			for index in 0 ..< resource.model.lod_count {
				ratio := resource.model.lod_ratios[index]
				radius := resource.model.lod_screen_radii[index]
				if math.is_nan(ratio) ||
				   math.is_inf(ratio) ||
				   ratio <= 0 ||
				   ratio >= previous_ratio {
					return resource, fail(
						.Invalid_Field,
						"model.lod_ratios must be positive, less than one, and strictly descending",
					)
				}
				if math.is_nan(radius) ||
				   math.is_inf(radius) ||
				   radius <= 0 ||
				   radius >= previous_radius {
					return resource, fail(
						.Invalid_Field,
						"model.lod_screen_radii must be positive and strictly descending",
					)
				}
				previous_ratio = ratio
				previous_radius = radius
			}
		} else {
			resource.model.lod_count = 0
		}
	} else if resource.kind == .Environment {
		if resource.environment.source == "" {
			return resource, fail(.Missing_Field, "environment.source is required")
		}
	} else if resource.kind == .Icon_Set {
		if resource.icon_set.source == "" {
			return resource, fail(.Missing_Field, "icon_set.source is required")
		}
	} else if resource.kind == .Shader {
		if resource.shader.source == "" {
			return resource, fail(.Missing_Field, "shader.source is required")
		}
		if resource.shader.spectral_surface.enabled {
			spectral := resource.shader.spectral_surface
			wind_length_squared :=
				spectral.wind_direction.x * spectral.wind_direction.x +
				spectral.wind_direction.y * spectral.wind_direction.y
			if math.is_nan(spectral.patch_size) ||
			   math.is_inf(spectral.patch_size) ||
			   spectral.patch_size < 16 ||
			   spectral.patch_size > 4096 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.patch_size must be between 16 and 4096",
				)
			}
			if math.is_nan(spectral.wind_speed) ||
			   math.is_inf(spectral.wind_speed) ||
			   spectral.wind_speed <= 0 ||
			   spectral.wind_speed > 100 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.wind_speed must be greater than zero and at most 100",
				)
			}
			if !finite_vec2(spectral.wind_direction) || wind_length_squared < 0.0001 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.wind_direction must be finite and non-zero",
				)
			}
			if math.is_nan(spectral.amplitude) ||
			   math.is_inf(spectral.amplitude) ||
			   spectral.amplitude <= 0 ||
			   spectral.amplitude > 10 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.amplitude must be greater than zero and at most 10",
				)
			}
			if math.is_nan(spectral.small_wave_damping) ||
			   math.is_inf(spectral.small_wave_damping) ||
			   spectral.small_wave_damping < 0 ||
			   spectral.small_wave_damping > 10 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.small_wave_damping must be between zero and 10",
				)
			}
			if math.is_nan(spectral.choppiness) ||
			   math.is_inf(spectral.choppiness) ||
			   spectral.choppiness < 0 ||
			   spectral.choppiness > 1 {
				return resource, fail(
					.Invalid_Field,
					"shader.spectral_surface.choppiness must be between zero and one",
				)
			}
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
		if math.is_nan(resource.material.metallic) ||
		   math.is_inf(resource.material.metallic) ||
		   resource.material.metallic < 0 ||
		   resource.material.metallic > 1 {
			return resource, fail(
				.Invalid_Field,
				"material.metallic must be finite and between zero and one",
			)
		}
		if math.is_nan(resource.material.roughness) ||
		   math.is_inf(resource.material.roughness) ||
		   resource.material.roughness < 0 ||
		   resource.material.roughness > 1 {
			return resource, fail(
				.Invalid_Field,
				"material.roughness must be finite and between zero and one",
			)
		}
		if math.is_nan(resource.material.alpha_cutoff) ||
		   math.is_inf(resource.material.alpha_cutoff) ||
		   resource.material.alpha_cutoff < 0 ||
		   resource.material.alpha_cutoff > 1 {
			return resource, fail(
				.Invalid_Field,
				"material.alpha_cutoff must be finite and between zero and one",
			)
		}
		for parameter in resource.material.shader_parameters {
			if !finite_vec4(parameter) {
				return resource, fail(.Invalid_Field, "material.shader_parameters must be finite")
			}
		}
	} else if resource.kind == .Geometry_LOD {
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
	} else {
		if !ui_theme_base_found {
			return resource, fail(.Missing_Field, "theme.base is required")
		}
		if !valid_ui_theme(resource.ui_theme.theme) {
			return resource, fail(
				.Invalid_Field,
				"theme colors and metrics must be finite, colors must be non-negative with alpha between zero and one, and metrics must be non-negative",
			)
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
	config.render.geometry_mode = .Auto
	config.render.virtual_geometry_budget_mb = 64
	config.render.virtual_geometry_prefetch = true
	config.render.environment_reflection_intensity = 1
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
				case "geometry_mode":
					mode_name: string
					mode_name, found = parse_basic_string(value)
					if found {
						config.render.geometry_mode, found = shared.geometry_mode_from_name(
							mode_name,
						)
						found = found && config.render.geometry_mode != .Inherit
					}
				case "virtual_geometry_budget_mb", "virtual_geometry_index_budget_mb":
					config.render.virtual_geometry_budget_mb, found = parse_f32(value)
				case "virtual_geometry_prefetch":
					config.render.virtual_geometry_prefetch, found = parse_bool(value)
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
				case "environment_reflection_intensity":
					config.render.environment_reflection_intensity, found = parse_f32(value)
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
			   config.render.virtual_geometry_budget_mb < 0.015625 ||
			   config.render.virtual_geometry_budget_mb > 16_384 ||
			   !finite_render_config(config.render) ||
			   config.render.environment_intensity < 0 ||
			   config.render.environment_reflection_intensity < 0 ||
			   config.render.exposure <= 0 ||
			   config.render.background_intensity < 0 ||
			   config.render.background_exposure <= 0 ||
			   config.render.background_blur < 0 ||
			   config.render.background_blur > 1 {
				return config, fail(
					.Invalid_Field,
					"render values must be finite; the virtual geometry payload budget must be 0.015625..16384 MiB, intensities non-negative, exposures positive, and background blur between 0 and 1",
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

parse_scene :: proc(
	source: string,
	project_resources: []shared.Project_Resource = nil,
) -> (
	scene: Scene,
	result: Parse_Result,
) {
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
		   line == "[entities.ui_canvas]" ||
		   line == "[entities.ui_hstack]" ||
		   line == "[entities.ui_vstack]" ||
		   line == "[entities.ui_scroll_area]" ||
		   line == "[entities.ui_panel]" ||
		   line == "[entities.ui_dock_space]" ||
		   line == "[entities.ui_dock_item]" ||
		   line == "[entities.ui_table]" ||
		   line == "[entities.ui_list]" ||
		   line == "[entities.ui_progress]" ||
		   line == "[entities.ui_viewport]" ||
		   line == "[entities.ui_icon]" ||
		   line == "[entities.ui_text]" ||
		   line == "[entities.ui_button]" ||
		   line == "[entities.ui_input]" ||
		   line == "[entities.ui_checkbox]" ||
		   line == "[entities.ui_color_picker]" ||
		   line == "[entities.ui_action]" {
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
			if section == "ui_canvas" {
				current.has_ui_canvas = true
				current.ui_canvas = shared.ui_canvas_default()
			}
			if section == "ui_hstack" { current.has_ui_hstack = true }
			if section == "ui_vstack" { current.has_ui_vstack = true }
			if section == "ui_scroll_area" {
				if !current.has_ui_scroll_area {
					current.ui_scroll_area = shared.ui_scroll_area_default()
				}
				current.has_ui_scroll_area = true
			}
			if section == "ui_panel" {
				if !current.has_ui_panel {
					current.ui_panel = shared.ui_panel_default()
				}
				current.has_ui_panel = true
			}
			if section == "ui_dock_space" {
				current.has_ui_dock_space = true
				current.ui_dock_space = shared.ui_dock_space_default()
			}
			if section == "ui_dock_item" {
				current.has_ui_dock_item = true
				current.ui_dock_item = shared.ui_dock_item_default()
			}
			if section == "ui_table" {
				current.has_ui_table = true
				current.ui_table = shared.ui_table_default()
			}
			if section == "ui_list" {
				if !current.has_ui_list {
					current.ui_list = shared.ui_list_default()
				}
				current.has_ui_list = true
			}
			if section == "ui_progress" {
				current.has_ui_progress = true
				current.ui_progress = shared.ui_progress_default()
			}
			if section == "ui_viewport" {
				current.has_ui_viewport = true
				current.ui_viewport = shared.ui_viewport_default()
			}
			if section == "ui_icon" {
				if !current.has_ui_icon {
					current.ui_icon = shared.ui_icon_default()
				}
				current.has_ui_icon = true
			}
			if section == "ui_text" {
				if !current.has_ui_text {
					current.ui_text = shared.ui_text_default()
				}
				current.has_ui_text = true
			}
			if section == "ui_button" {
				if !current.has_ui_button {
					current.ui_button = shared.ui_button_default()
				}
				current.has_ui_button = true
			}
			if section == "ui_input" {
				if !current.has_ui_input {
					current.ui_input = shared.ui_input_default()
				}
				current.has_ui_input = true
			}
			if section == "ui_checkbox" {
				if !current.has_ui_checkbox {
					current.ui_checkbox = shared.ui_checkbox_default()
				}
				current.has_ui_checkbox = true
			}
			if section == "ui_color_picker" {
				if !current.has_ui_color_picker {
					current.ui_color_picker = shared.ui_color_picker_default()
				}
				current.has_ui_color_picker = true
			}
			if section == "ui_action" {
				if !current.has_ui_action {
					current.ui_action = shared.ui_action_default()
				}
				current.has_ui_action = true
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
					case "ui_theme":
						raw_theme, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_theme, found = shared.ui_theme_name_parse(raw_theme)
							if !found {
								current.ui_theme_resource, found = shared.resource_uuid_parse(
									raw_theme,
								)
								if found {
									_, found = project_ui_theme(
										project_resources,
										current.ui_theme_resource,
									)
								}
							}
						} else {
							found = false
						}
						if !found {
							return scene, fail(
								.Invalid_Field,
								"entity ui_theme must name a built-in theme or declared UI theme resource UUID",
							)
						}
						current.has_ui_theme = true
						if current.ui_theme_recipe_count > 0 {
							apply_scene_ui_theme(current, project_resources)
						}
					case "ui_recipes":
						current.ui_theme_recipe_count, found = parse_ui_theme_recipes(
							value,
							&current.ui_theme_recipes,
						)
						if !found {
							return scene, fail(
								.Invalid_Field,
								"entity ui_recipes must be a non-empty array of supported recipe names",
							)
						}
						if current.has_ui_theme {
							apply_scene_ui_theme(current, project_resources)
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
					current.camera = shared.camera_defaults()
				}
				current.has_camera = true
				switch key {
					case "fov":
						current.camera.fov, found = parse_f32(value)
					case "near":
						current.camera.near, found = parse_f32(value)
					case "far":
						current.camera.far, found = parse_f32(value)
					case "debug_view":
						name: string
						name, found = parse_basic_string(value)
						if found {
							current.camera.debug_view, found = shared.render_debug_view_from_name(
								name,
							)
						}
					case "debug_hiz_mip":
						current.camera.debug_hiz_mip, found = parse_f32(value)
					case "debug_occlusion_freeze":
						current.camera.debug_occlusion_freeze, found = parse_bool(value)
					case "resolution_scale":
						current.camera.resolution_scale, found = parse_f32(value)
					case "dynamic_resolution":
						current.camera.dynamic_resolution, found = parse_bool(value)
					case "dynamic_resolution_min_scale":
						current.camera.dynamic_resolution_min_scale, found = parse_f32(value)
					case "dynamic_resolution_target_ms":
						current.camera.dynamic_resolution_target_ms, found = parse_f32(value)
					case "adaptive_quality_minimum":
						current.camera.adaptive_quality_minimum, found = parse_f32(value)
					case "exposure":
						current.camera.exposure, found = parse_f32(value)
					case "automatic_exposure":
						current.camera.automatic_exposure, found = parse_bool(value)
					case "automatic_exposure_min":
						current.camera.automatic_exposure_min, found = parse_f32(value)
					case "automatic_exposure_max":
						current.camera.automatic_exposure_max, found = parse_f32(value)
					case "automatic_exposure_speed":
						current.camera.automatic_exposure_speed, found = parse_f32(value)
					case "temporal_antialiasing":
						current.camera.temporal_antialiasing, found = parse_bool(value)
					case "fast_antialiasing":
						current.camera.fast_antialiasing, found = parse_bool(value)
					case "ambient_occlusion":
						current.camera.ambient_occlusion, found = parse_bool(value)
					case "ambient_occlusion_quality":
						current.camera.ambient_occlusion_quality, found = parse_f32(value)
					case "ambient_occlusion_resolution_scale":
						current.camera.ambient_occlusion_resolution_scale, found = parse_f32(value)
					case "screen_space_reflections":
						current.camera.screen_space_reflections, found = parse_bool(value)
					case "screen_space_reflections_quality":
						current.camera.screen_space_reflections_quality, found = parse_f32(value)
					case "bloom":
						current.camera.bloom, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown camera field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid camera.%s", key))
				}
			case "world_environment":
				current.has_world_environment = true
				switch key {
					case "lighting":
						current.world_environment.lighting, found = parse_basic_string(value)
					case "lighting_intensity":
						current.world_environment.lighting_intensity, found = parse_f32(value)
					case "reflection_intensity":
						current.world_environment.reflection_intensity, found = parse_f32(value)
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
					case "sun_direction":
						current.world_environment.sun_direction, found = parse_vec3(value)
					case "sun_color":
						current.world_environment.sun_color, found = parse_vec3(value)
					case "sun_intensity":
						current.world_environment.sun_intensity, found = parse_f32(value)
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
				switch key {
					case "primitive":
						current.mesh.primitive, found = parse_basic_string(value)
						if !found || current.mesh.primitive == "" {
							return scene, fail(
								.Invalid_Field,
								"mesh.primitive must be a non-empty basic string",
							)
						}
					case "geometry_mode":
						mode_name: string
						mode_name, found = parse_basic_string(value)
						if found {
							current.mesh.geometry_mode, found = shared.geometry_mode_from_name(
								mode_name,
							)
						}
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown mesh field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid mesh.%s", key))
				}
			case "geometry":
				current.has_geometry = true
				switch key {
					case "resource":
						current.geometry.resource, found = parse_basic_string(value)
						if !found || current.geometry.resource == "" {
							return scene, fail(
								.Invalid_Field,
								"geometry.resource must be a non-empty basic string",
							)
						}
					case "geometry_mode":
						mode_name: string
						mode_name, found = parse_basic_string(value)
						if found {
							current.geometry.geometry_mode, found = shared.geometry_mode_from_name(
								mode_name,
							)
						}
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown geometry field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid geometry.%s", key))
				}
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
				switch key {
					case "resource":
						current.model.resource, found = parse_basic_string(value)
						if !found || current.model.resource == "" {
							return scene, fail(
								.Invalid_Field,
								"model.resource must be a non-empty resource UUID",
							)
						}
					case "geometry_mode":
						mode_name: string
						mode_name, found = parse_basic_string(value)
						if found {
							current.model.geometry_mode, found = shared.geometry_mode_from_name(
								mode_name,
							)
						}
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown model field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid model.%s", key))
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
					case "popup_anchor":
						raw_anchor, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_layout.popup_anchor, found = shared.entity_uuid_parse(
								raw_anchor,
							)
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
					case "basis":
						current.ui_layout.basis, found = parse_f32(value)
					case "grow":
						current.ui_layout.grow, found = parse_f32(value)
					case "shrink":
						current.ui_layout.shrink, found = parse_f32(value)
					case "horizontal_alignment":
						current.ui_layout.horizontal_alignment, found = parse_ui_alignment(value)
					case "vertical_alignment":
						current.ui_layout.vertical_alignment, found = parse_ui_alignment(value)
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
					case "stack_order":
						current.ui_layout.stack_order, found = parse_int(value)
					case "popup":
						current.ui_layout.popup, found = parse_bool(value)
					case "popup_open":
						current.ui_layout.popup_open, found = parse_bool(value)
					case "popup_close_on_selection":
						current.ui_layout.popup_close_on_selection, found = parse_bool(value)
					case "popup_gap":
						current.ui_layout.popup_gap, found = parse_f32(value)
					case "popup_min_width":
						current.ui_layout.popup_min_width, found = parse_f32(value)
					case "popup_max_width":
						current.ui_layout.popup_max_width, found = parse_f32(value)
					case "popup_max_height":
						current.ui_layout.popup_max_height, found = parse_f32(value)
					case "popup_viewport_margin":
						current.ui_layout.popup_viewport_margin, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_layout field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_layout.%s", key)) }
			case "ui_canvas":
				current.has_ui_canvas = true
				switch key {
					case "reference_size":
						current.ui_canvas.reference_size, found = parse_vec2(value)
					case "scale_mode":
						current.ui_canvas.scale_mode, found = parse_ui_canvas_scale_mode(value)
					case "horizontal_alignment":
						current.ui_canvas.horizontal_alignment, found = parse_ui_canvas_alignment(
							value,
						)
					case "vertical_alignment":
						current.ui_canvas.vertical_alignment, found = parse_ui_canvas_alignment(
							value,
						)
					case "safe_area":
						current.ui_canvas.safe_area, found = parse_vec4(value)
					case "min_scale":
						current.ui_canvas.min_scale, found = parse_f32(value)
					case "max_scale":
						current.ui_canvas.max_scale, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_canvas field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_canvas.%s", key))
				}
			case "ui_hstack":
				current.has_ui_hstack = true
				switch key {case "gap":
						current.ui_hstack.gap, found = parse_f32(value); case "fill":
						current.ui_hstack.fill, found = parse_bool(value); case "draggable":
						current.ui_hstack.draggable, found = parse_bool(value); case "min_size":
						current.ui_hstack.min_size, found = parse_f32(value); case "reorderable":
						current.ui_hstack.reorderable, found = parse_bool(
							value,
						); case "drag_threshold":
						current.ui_hstack.drag_threshold, found = parse_f32(
							value,
						); case "drop_indicator_color":
						current.ui_hstack.drop_indicator_color, found = parse_vec4(
							value,
						); case "drop_indicator_thickness":
						current.ui_hstack.drop_indicator_thickness, found = parse_f32(
							value,
						); case "drop_indicator_inset":
						current.ui_hstack.drop_indicator_inset, found = parse_f32(
							value,
						); case "wrap":
						current.ui_hstack.wrap, found = parse_bool(value); case "line_gap":
						current.ui_hstack.line_gap, found = parse_f32(value); case:
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
						current.ui_vstack.min_size, found = parse_f32(value); case "reorderable":
						current.ui_vstack.reorderable, found = parse_bool(
							value,
						); case "drag_threshold":
						current.ui_vstack.drag_threshold, found = parse_f32(
							value,
						); case "drop_indicator_color":
						current.ui_vstack.drop_indicator_color, found = parse_vec4(
							value,
						); case "drop_indicator_thickness":
						current.ui_vstack.drop_indicator_thickness, found = parse_f32(
							value,
						); case "drop_indicator_inset":
						current.ui_vstack.drop_indicator_inset, found = parse_f32(
							value,
						); case "wrap":
						current.ui_vstack.wrap, found = parse_bool(value); case "line_gap":
						current.ui_vstack.line_gap, found = parse_f32(value); case:
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
					case "disclosure_inset":
						current.ui_panel.disclosure_inset, found = parse_f32(value)
					case "collapsible":
						current.ui_panel.collapsible, found = parse_bool(value)
					case "collapsed":
						current.ui_panel.collapsed, found = parse_bool(value)
					case "movable":
						current.ui_panel.movable, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_panel field '%s'", key),
						)
				}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_panel.%s", key)) }
			case "ui_dock_space":
				current.has_ui_dock_space = true
				switch key {
					case "active":
						raw_active, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_dock_space.active, found = shared.entity_uuid_parse(
								raw_active,
							)
						} else {
							found = false
						}
					case "font":
						current.ui_dock_space.font, found = parse_basic_string(value)
					case "tab_height":
						current.ui_dock_space.tab_height, found = parse_f32(value)
					case "tab_min_width":
						current.ui_dock_space.tab_min_width, found = parse_f32(value)
					case "tab_max_width":
						current.ui_dock_space.tab_max_width, found = parse_f32(value)
					case "tab_gap":
						current.ui_dock_space.tab_gap, found = parse_f32(value)
					case "tab_padding":
						current.ui_dock_space.tab_padding, found = parse_f32(value)
					case "tab_size":
						current.ui_dock_space.tab_size, found = parse_f32(value)
					case "tab_corner_radius":
						current.ui_dock_space.tab_corner_radius, found = parse_f32(value)
					case "tab_connection_height":
						current.ui_dock_space.tab_connection_height, found = parse_f32(value)
					case "tab_content_overlap":
						current.ui_dock_space.tab_content_overlap, found = parse_f32(value)
					case "tab_strip_background":
						current.ui_dock_space.tab_strip_background, found = parse_vec4(value)
					case "content_background":
						current.ui_dock_space.content_background, found = parse_vec4(value)
					case "content_corner_radius":
						current.ui_dock_space.content_corner_radius, found = parse_f32(value)
					case "content_padding":
						current.ui_dock_space.content_padding, found = parse_vec4(value)
					case "tab_color":
						current.ui_dock_space.tab_color, found = parse_vec4(value)
					case "tab_active_color":
						current.ui_dock_space.tab_active_color, found = parse_vec4(value)
					case "tab_background":
						current.ui_dock_space.tab_background, found = parse_vec4(value)
					case "tab_hover_background":
						current.ui_dock_space.tab_hover_background, found = parse_vec4(value)
					case "tab_active_background":
						current.ui_dock_space.tab_active_background, found = parse_vec4(value)
					case "drop_background":
						current.ui_dock_space.drop_background, found = parse_vec4(value)
					case "draggable":
						current.ui_dock_space.draggable, found = parse_bool(value)
					case "split_horizontal":
						current.ui_dock_space.split_horizontal, found = parse_bool(value)
					case "split_vertical":
						current.ui_dock_space.split_vertical, found = parse_bool(value)
					case "split_ratio":
						current.ui_dock_space.split_ratio, found = parse_f32(value)
					case "split_edge_fraction":
						current.ui_dock_space.split_edge_fraction, found = parse_f32(value)
					case "split_gap":
						current.ui_dock_space.split_gap, found = parse_f32(value)
					case "split_min_size":
						current.ui_dock_space.split_min_size, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_dock_space field '%s'", key),
						)
				}
				if !found {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("invalid ui_dock_space.%s", key),
					)
				}
			case "ui_dock_item":
				current.has_ui_dock_item = true
				switch key {
					case "title":
						current.ui_dock_item.title, found = parse_basic_string(value)
					case "movable":
						current.ui_dock_item.movable, found = parse_bool(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_dock_item field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_dock_item.%s", key))
				}
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
					case "filter_input":
						raw_filter_input: string
						raw_filter_input, found = parse_basic_string(value)
						if found {
							current.ui_list.filter_input, found = shared.entity_uuid_parse(
								raw_filter_input,
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
					case "highlight_corner_radius":
						current.ui_list.highlight_corner_radius, found = parse_f32(value)
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
					case "virtualized":
						current.ui_list.virtualized, found = parse_bool(value)
					case "item_height":
						current.ui_list.item_height, found = parse_f32(value)
					case "overscan":
						current.ui_list.overscan, found = parse_int(value)
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
						current.ui_text.alignment, found = parse_ui_text_alignment(
							value,
						); case "wrap":
						current.ui_text.wrap, found = parse_bool(value); case "line_height":
						current.ui_text.line_height, found = parse_f32(value); case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_text field '%s'", key),
						)}
				if !found { return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_text.%s", key)) }
			case "ui_icon":
				current.has_ui_icon = true
				switch key {
					case "icon_set":
						raw, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_icon.icon_set, found = shared.resource_uuid_parse(raw)
						} else {
							found = false
						}
					case "icon":
						current.ui_icon.icon, found = parse_basic_string(value)
					case "color":
						current.ui_icon.color, found = parse_vec4(value)
					case "inset":
						current.ui_icon.inset, found = parse_f32(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_icon field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_icon.%s", key))
				}
			case "ui_button":
				current.has_ui_button = true
				switch key {case "text":
						current.ui_button.text, found = parse_basic_string(value); case "font":
						current.ui_button.font, found = parse_basic_string(value)
					case "popup":
						raw_popup, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_button.popup, found = shared.entity_uuid_parse(raw_popup)
						} else {
							found = false
						}
					case "color":
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
						current.ui_button.active_color, found = parse_vec4(value)
					case "icon_set":
						raw, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_button.icon_set, found = shared.resource_uuid_parse(raw)
						} else {
							found = false
						}
					case "icon":
						current.ui_button.icon, found = parse_basic_string(value)
					case "icon_position":
						current.ui_button.icon_position, found = parse_ui_icon_position(value)
					case "icon_size":
						current.ui_button.icon_size, found = parse_f32(value)
					case "icon_gap":
						current.ui_button.icon_gap, found = parse_f32(value)
					case "icon_inset":
						current.ui_button.icon_inset, found = parse_f32(value)
					case "panel_action":
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
					case "icon_set":
						raw, string_ok := parse_basic_string(value)
						if string_ok {
							current.ui_input.icon_set, found = shared.resource_uuid_parse(raw)
						} else {
							found = false
						}
					case "icon":
						current.ui_input.icon, found = parse_basic_string(value)
					case "icon_position":
						current.ui_input.icon_position, found = parse_ui_icon_position(value)
					case "color":
						current.ui_input.color, found = parse_vec4(value)
					case "icon_color":
						current.ui_input.icon_color, found = parse_vec4(value)
					case "prefix_color":
						current.ui_input.prefix_color, found = parse_vec4(value)
					case "prefix_background":
						current.ui_input.prefix_background, found = parse_vec4(value)
					case "size":
						current.ui_input.size, found = parse_f32(value)
					case "icon_size":
						current.ui_input.icon_size, found = parse_f32(value)
					case "icon_gap":
						current.ui_input.icon_gap, found = parse_f32(value)
					case "icon_inset":
						current.ui_input.icon_inset, found = parse_f32(value)
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
			case "ui_color_picker":
				current.has_ui_color_picker = true
				switch key {
					case "value":
						current.ui_color_picker.value, found = parse_vec4(value)
					case "hdr":
						current.ui_color_picker.hdr, found = parse_bool(value)
					case "show_alpha":
						current.ui_color_picker.show_alpha, found = parse_bool(value)
					case "read_only":
						current.ui_color_picker.read_only, found = parse_bool(value)
					case "exposure":
						current.ui_color_picker.exposure, found = parse_f32(value)
					case "maximum_exposure":
						current.ui_color_picker.maximum_exposure, found = parse_f32(value)
					case "track_height":
						current.ui_color_picker.track_height, found = parse_f32(value)
					case "gap":
						current.ui_color_picker.gap, found = parse_f32(value)
					case "thumb_radius":
						current.ui_color_picker.thumb_radius, found = parse_f32(value)
					case "thumb_color":
						current.ui_color_picker.thumb_color, found = parse_vec4(value)
					case "thumb_border_color":
						current.ui_color_picker.thumb_border_color, found = parse_vec4(value)
					case "thumb_border_width":
						current.ui_color_picker.thumb_border_width, found = parse_f32(value)
					case "checker_light":
						current.ui_color_picker.checker_light, found = parse_vec4(value)
					case "checker_dark":
						current.ui_color_picker.checker_dark, found = parse_vec4(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_color_picker field '%s'", key),
						)
				}
				if !found {
					return scene, fail(
						.Invalid_Field,
						fmt.tprintf("invalid ui_color_picker.%s", key),
					)
				}
			case "ui_action":
				current.has_ui_action = true
				switch key {
					case "action":
						current.ui_action.action, found = parse_basic_string(value)
					case "payload":
						current.ui_action.payload, found = parse_basic_string(value)
					case "drag_source":
						current.ui_action.drag_source, found = parse_bool(value)
					case "drop_target":
						current.ui_action.drop_target, found = parse_bool(value)
					case "drag_threshold":
						current.ui_action.drag_threshold, found = parse_f32(value)
					case "drop_background":
						current.ui_action.drop_background, found = parse_vec4(value)
					case:
						return scene, fail(
							.Invalid_Field,
							fmt.tprintf("unknown ui_action field '%s'", key),
						)
				}
				if !found {
					return scene, fail(.Invalid_Field, fmt.tprintf("invalid ui_action.%s", key))
				}
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
	canvas_count := 0
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
		if entity.has_ui_theme != (entity.ui_theme_recipe_count > 0) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"entity '%s' must declare ui_theme and ui_recipes together",
					entity.name,
				),
			)
		}
		if entity.has_transform && entity.transform.scale == (Vec3{}) {
			scene.entities[index].transform.scale = Vec3{1, 1, 1}
		}
		if entity.has_camera {
			exposure := entity.camera.exposure
			resolution_scale := entity.camera.resolution_scale
			if resolution_scale == 0 {
				resolution_scale = 1
			}
			dynamic_resolution_min_scale := entity.camera.dynamic_resolution_min_scale
			dynamic_resolution_target_ms := entity.camera.dynamic_resolution_target_ms
			adaptive_quality_minimum := entity.camera.adaptive_quality_minimum
			automatic_exposure_min := shared.camera_automatic_exposure_min(entity.camera)
			automatic_exposure_max := shared.camera_automatic_exposure_max(entity.camera)
			automatic_exposure_speed := shared.camera_automatic_exposure_speed(entity.camera)
			ambient_occlusion_quality := entity.camera.ambient_occlusion_quality
			ambient_occlusion_resolution_scale := entity.camera.ambient_occlusion_resolution_scale
			screen_space_reflections_quality := entity.camera.screen_space_reflections_quality
			if math.is_nan(exposure) ||
			   math.is_inf(exposure) ||
			   exposure <= 0 ||
			   math.is_nan(resolution_scale) ||
			   math.is_inf(resolution_scale) ||
			   resolution_scale < 0.5 ||
			   resolution_scale > 1 ||
			   math.is_nan(dynamic_resolution_min_scale) ||
			   math.is_inf(dynamic_resolution_min_scale) ||
			   dynamic_resolution_min_scale < 0.5 ||
			   dynamic_resolution_min_scale > resolution_scale ||
			   math.is_nan(dynamic_resolution_target_ms) ||
			   math.is_inf(dynamic_resolution_target_ms) ||
			   dynamic_resolution_target_ms < 1 ||
			   dynamic_resolution_target_ms > 100 ||
			   math.is_nan(adaptive_quality_minimum) ||
			   math.is_inf(adaptive_quality_minimum) ||
			   adaptive_quality_minimum < 0.25 ||
			   adaptive_quality_minimum > 1 ||
			   math.is_nan(entity.camera.debug_hiz_mip) ||
			   math.is_inf(entity.camera.debug_hiz_mip) ||
			   entity.camera.debug_hiz_mip < 0 ||
			   entity.camera.debug_hiz_mip > 15 ||
			   math.is_nan(automatic_exposure_min) ||
			   math.is_inf(automatic_exposure_min) ||
			   automatic_exposure_min <= 0 ||
			   math.is_nan(automatic_exposure_max) ||
			   math.is_inf(automatic_exposure_max) ||
			   automatic_exposure_max < automatic_exposure_min ||
			   math.is_nan(automatic_exposure_speed) ||
			   math.is_inf(automatic_exposure_speed) ||
			   automatic_exposure_speed <= 0 ||
			   math.is_nan(ambient_occlusion_quality) ||
			   math.is_inf(ambient_occlusion_quality) ||
			   ambient_occlusion_quality < 0.25 ||
			   ambient_occlusion_quality > 1 ||
			   math.is_nan(ambient_occlusion_resolution_scale) ||
			   math.is_inf(ambient_occlusion_resolution_scale) ||
			   ambient_occlusion_resolution_scale < 0.25 ||
			   ambient_occlusion_resolution_scale > 1 ||
			   math.is_nan(screen_space_reflections_quality) ||
			   math.is_inf(screen_space_reflections_quality) ||
			   screen_space_reflections_quality < 0.25 ||
			   screen_space_reflections_quality > 1 {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"camera exposure and render-quality settings on '%s' are invalid",
						entity.name,
					),
				)
			}
		}
		if (entity.has_ui_icon ||
			   entity.has_ui_text ||
			   entity.has_ui_button ||
			   entity.has_ui_hstack ||
			   entity.has_ui_vstack ||
			   entity.has_ui_scroll_area ||
			   entity.has_ui_panel ||
			   entity.has_ui_dock_space ||
			   entity.has_ui_dock_item ||
			   entity.has_ui_table ||
			   entity.has_ui_list ||
			   entity.has_ui_progress ||
			   entity.has_ui_viewport ||
			   entity.has_ui_input ||
			   entity.has_ui_checkbox ||
			   entity.has_ui_color_picker ||
			   entity.has_ui_action ||
			   entity.has_ui_canvas) &&
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
		if entity.has_ui_canvas {
			canvas_count += 1
			if canvas_count > 1 {
				return scene, fail(.Invalid_Field, "a scene may declare only one ui_canvas")
			}
			if entity.ui_layout.parent != (shared.Entity_UUID{}) {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("UI canvas entity '%s' must be a layout root", entity.name),
				)
			}
			if !shared.ui_canvas_is_valid(entity.ui_canvas) {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"UI canvas entity '%s' has invalid scaling or safe-area values",
						entity.name,
					),
				)
			}
		}
		container_count := 0
		if entity.has_ui_hstack { container_count += 1 }
		if entity.has_ui_vstack { container_count += 1 }
		if entity.has_ui_table { container_count += 1 }
		if entity.has_ui_list { container_count += 1 }
		if entity.has_ui_dock_space { container_count += 1 }
		if container_count >
		   1 { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' can only use one of ui_hstack, ui_vstack, ui_table, ui_list, or ui_dock_space", entity.name)) }
		if (entity.has_ui_hstack && !shared.ui_stack_is_valid(entity.ui_hstack)) ||
		   (entity.has_ui_vstack && !shared.ui_stack_is_valid(entity.ui_vstack)) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI stack '%s' requires non-negative gaps/min_size; draggable requires fill, while wrap excludes both",
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
		if entity.has_ui_dock_space && !shared.ui_dock_space_is_valid(entity.ui_dock_space) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI dock space '%s' has invalid tab geometry", entity.name),
			)
		}
		if entity.has_ui_dock_item && !shared.ui_dock_item_is_valid(entity.ui_dock_item) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI dock item '%s' requires a title", entity.name),
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
		if entity.has_ui_icon { content_count += 1 }
		if entity.has_ui_text { content_count += 1 }
		if entity.has_ui_button { content_count += 1 }
		if entity.has_ui_input { content_count += 1 }
		if entity.has_ui_checkbox { content_count += 1 }
		if entity.has_ui_color_picker { content_count += 1 }
		if content_count >
		   1 { return scene, fail(.Invalid_Field, fmt.tprintf("UI entity '%s' can only use one of ui_icon, ui_text, ui_button, ui_input, ui_checkbox, or ui_color_picker", entity.name)) }
		if entity.has_ui_icon && !shared.ui_icon_is_valid(entity.ui_icon) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI icon entity '%s' requires an icon set UUID, symbol name, finite color, and non-negative inset",
					entity.name,
				),
			)
		}
		if entity.has_ui_text && !shared.ui_text_is_valid(entity.ui_text) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI text entity '%s' requires text, positive size, and non-negative line_height",
					entity.name,
				),
			)
		}
		if entity.has_ui_button && !shared.ui_button_is_valid(entity.ui_button) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI button entity '%s' requires text or an icon and valid sizing",
					entity.name,
				),
			)
		}
		if entity.has_ui_input && !shared.ui_input_is_valid(entity.ui_input) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI input entity '%s' has invalid content or sizing", entity.name),
			)
		}
		if entity.has_ui_checkbox && entity.ui_checkbox.box_size <= 0 {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI checkbox entity '%s' requires positive box_size", entity.name),
			)
		}
		if entity.has_ui_color_picker && !shared.ui_color_picker_is_valid(entity.ui_color_picker) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf("UI color picker entity '%s' is invalid", entity.name),
			)
		}
		if entity.has_ui_action && !shared.ui_action_is_valid(entity.ui_action) {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI action entity '%s' requires a non-empty action of at most %d bytes and a payload of at most %d bytes",
					entity.name,
					shared.UI_ACTION_MAX_BYTES,
					shared.UI_ACTION_PAYLOAD_MAX_BYTES,
				),
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
		if !entity.has_ui_layout {
			continue
		}
		if entity.ui_layout.parent == (shared.Entity_UUID{}) {
			if entity.has_ui_dock_item {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"UI dock item '%s' must be a direct child of a ui_dock_space",
						entity.name,
					),
				)
			}
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
		if entity.has_ui_dock_item {
			parent_index := entity_indices[entity.ui_layout.parent]
			if !scene.entities[parent_index].has_ui_dock_space {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf(
						"UI dock item '%s' must be a direct child of a ui_dock_space",
						entity.name,
					),
				)
			}
		}
	}
	for entity in scene.entities {
		if !entity.has_ui_dock_space || entity.ui_dock_space.active == (shared.Entity_UUID{}) {
			continue
		}
		active_index, found_active := entity_indices[entity.ui_dock_space.active]
		active := scene.entities[active_index] if found_active else shared.Scene_Entity{}
		active_is_dock_item := found_active && active.has_ui_dock_item
		active_is_panel := found_active && active.has_ui_panel && active.ui_panel.title != ""
		if !found_active ||
		   (!active_is_dock_item && !active_is_panel) ||
		   !active.has_ui_layout ||
		   active.ui_layout.parent != entity.id {
			return scene, fail(
				.Invalid_Field,
				fmt.tprintf(
					"UI dock space '%s' active item must name one of its direct dock-item or titled-panel children",
					entity.name,
				),
			)
		}
	}
	for entity in scene.entities {
		if entity.has_ui_layout && entity.ui_layout.popup_anchor != (shared.Entity_UUID{}) {
			anchor_found := false
			for candidate in scene.entities {
				if candidate.id == entity.ui_layout.popup_anchor && candidate.has_ui_layout {
					anchor_found = true
					break
				}
			}
			if !anchor_found || entity.ui_layout.popup_anchor == entity.id {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("UI popup anchor for '%s' is invalid", entity.name),
				)
			}
		}
		if entity.has_ui_button && entity.ui_button.popup != (shared.Entity_UUID{}) {
			popup_found := false
			for candidate in scene.entities {
				if candidate.id == entity.ui_button.popup &&
				   candidate.has_ui_layout &&
				   candidate.ui_layout.popup {
					popup_found = true
					break
				}
			}
			if !popup_found || entity.ui_button.popup == entity.id {
				return scene, fail(
					.Invalid_Field,
					fmt.tprintf("UI button popup for '%s' is invalid", entity.name),
				)
			}
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

parse_ui_theme_recipes :: proc(
	value: string,
	out: ^[shared.UI_THEME_RECIPE_CAPACITY]shared.UI_Theme_Recipe,
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
		return 0, false
	}
	parts := strings.split(body, ",")
	defer delete(parts)
	if len(parts) > len(out^) {
		return 0, false
	}
	for part, index in parts {
		name, parsed := parse_basic_string(strings.trim_space(part))
		if !parsed {
			return 0, false
		}
		out[index], parsed = shared.ui_theme_recipe_parse(name)
		if !parsed {
			return 0, false
		}
	}
	return len(parts), true
}

project_ui_theme :: proc(
	resources: []shared.Project_Resource,
	id: shared.Resource_UUID,
) -> (
	shared.UI_Theme,
	bool,
) {
	for resource in resources {
		if resource.kind == .UI_Theme && resource.id == id {
			return resource.ui_theme.theme, true
		}
	}
	return {}, false
}

apply_scene_ui_theme :: proc(
	entity: ^Scene_Entity,
	project_resources: []shared.Project_Resource = nil,
) {
	if entity == nil || !entity.has_ui_theme || entity.ui_theme_recipe_count <= 0 {
		return
	}
	theme := shared.ui_theme_builtin(entity.ui_theme)
	if entity.ui_theme_resource != (shared.Resource_UUID{}) {
		found: bool
		theme, found = project_ui_theme(project_resources, entity.ui_theme_resource)
		if !found {
			return
		}
	}
	resolved := shared.ui_theme_resolve_value(
		theme,
		entity.ui_theme_recipes[:entity.ui_theme_recipe_count],
	)
	if resolved.has_layout {
		entity.has_ui_layout = true
		entity.ui_layout = resolved.layout
	}
	if resolved.has_scroll_area {
		entity.has_ui_scroll_area = true
		entity.ui_scroll_area = resolved.scroll_area
	}
	if resolved.has_panel {
		entity.has_ui_panel = true
		entity.ui_panel = resolved.panel
	}
	if resolved.has_list {
		entity.has_ui_list = true
		entity.ui_list = resolved.list
	}
	if resolved.has_text {
		entity.has_ui_text = true
		entity.ui_text = resolved.text
	}
	if resolved.has_button {
		entity.has_ui_button = true
		entity.ui_button = resolved.button
	}
	if resolved.has_input {
		entity.has_ui_input = true
		entity.ui_input = resolved.input
	}
	if resolved.has_checkbox {
		entity.has_ui_checkbox = true
		entity.ui_checkbox = resolved.checkbox
	}
	if resolved.has_color_picker {
		entity.has_ui_color_picker = true
		entity.ui_color_picker = resolved.color_picker
	}
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

parse_ui_alignment :: proc(value: string) -> (out: shared.UI_Alignment, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .Start, false
	}
	switch text {
		case "", "start":
			return .Start, true
		case "center":
			return .Center, true
		case "end":
			return .End, true
		case "stretch":
			return .Stretch, true
		case:
			return .Start, false
	}
}

parse_ui_canvas_scale_mode :: proc(value: string) -> (out: shared.UI_Canvas_Scale_Mode, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .Fit, false
	}
	switch text {
		case "fit":
			return .Fit, true
		case "fill":
			return .Fill, true
		case "expand":
			return .Expand, true
		case "stretch":
			return .Stretch, true
		case "pixel_perfect":
			return .Pixel_Perfect, true
		case "none":
			return .None, true
		case:
			return .Fit, false
	}
}

parse_ui_canvas_alignment :: proc(value: string) -> (out: shared.UI_Canvas_Alignment, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .Start, false
	}
	switch text {
		case "", "start":
			return .Start, true
		case "center":
			return .Center, true
		case "end":
			return .End, true
		case:
			return .Start, false
	}
}

parse_ui_icon_position :: proc(value: string) -> (out: shared.UI_Icon_Position, ok: bool) {
	text, parsed := parse_basic_string(value)
	if !parsed {
		return .Leading, false
	}
	switch text {
		case "", "leading":
			return .Leading, true
		case "trailing":
			return .Trailing, true
	}
	return .Leading, false
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

valid_resource_icon_set_path :: proc(path: string) -> bool {
	if !strings.has_prefix(path, "assets/") || !is_safe_relative_path(path) {
		return false
	}
	if strings.has_suffix(path, "/") {
		return false
	}
	return true
}

valid_resource_shader_path :: proc(path: string) -> bool {
	return(
		strings.has_prefix(path, "shaders/") &&
		strings.has_suffix(path, ".wgsl") &&
		is_safe_relative_path(path) \
	)
}

parse_shader_parameters :: proc(value: string) -> (result: [4]shared.Vec4, ok: bool) {
	parts, parsed := parse_number_array(value, 16)
	if !parsed {
		return result, false
	}
	defer delete(parts)
	for part, index in parts {
		component, component_ok := parse_f32(part)
		if !component_ok {
			return result, false
		}
		parameter := &result[index / 4]
		switch index % 4 {
			case 0:
				parameter.x = component
			case 1:
				parameter.y = component
			case 2:
				parameter.z = component
			case 3:
				parameter.w = component
		}
	}
	return result, true
}

finite_render_config :: proc(value: shared.Project_Render_Config) -> bool {
	return(
		!math.is_nan(value.virtual_geometry_budget_mb) &&
		!math.is_inf(value.virtual_geometry_budget_mb) &&
		!math.is_nan(value.environment_intensity) &&
		!math.is_inf(value.environment_intensity) &&
		!math.is_nan(value.environment_reflection_intensity) &&
		!math.is_inf(value.environment_reflection_intensity) &&
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

finite_vec2 :: proc(value: shared.Vec2) -> bool {
	return(
		!math.is_nan(value.x) &&
		!math.is_inf(value.x) &&
		!math.is_nan(value.y) &&
		!math.is_inf(value.y) \
	)
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

valid_ui_theme_color :: proc(value: Vec4) -> bool {
	return(
		finite_vec4(value) &&
		value.x >= 0 &&
		value.y >= 0 &&
		value.z >= 0 &&
		value.w >= 0 &&
		value.w <= 1 \
	)
}

valid_ui_theme :: proc(theme: shared.UI_Theme) -> bool {
	palette := theme.palette
	colors := [?]Vec4 {
		palette.canvas,
		palette.region,
		palette.panel,
		palette.raised,
		palette.control,
		palette.overlay,
		palette.border,
		palette.border_strong,
		palette.text,
		palette.text_secondary,
		palette.text_muted,
		palette.accent,
		palette.accent_text,
		palette.accent_soft,
		palette.hover,
		palette.active,
		palette.selection,
		palette.focus,
		palette.warning,
		palette.warning_soft,
		palette.danger,
		palette.danger_soft,
		palette.data_engine,
		palette.data_native,
		palette.data_script,
		palette.axis_x,
		palette.axis_y,
		palette.axis_z,
		palette.axis_w,
		palette.light_overlay,
		palette.dark_overlay,
	}
	for color in colors {
		if !valid_ui_theme_color(color) {
			return false
		}
	}
	metrics := theme.metrics
	numbers := [?]f32 {
		metrics.text_size,
		metrics.small_text_size,
		metrics.control_height,
		metrics.row_height,
		metrics.title_height,
		metrics.radius_small,
		metrics.radius,
		metrics.radius_large,
		metrics.border_width,
		metrics.gap_small,
		metrics.gap,
		metrics.gap_large,
		metrics.padding_small.x,
		metrics.padding_small.y,
		metrics.padding_small.z,
		metrics.padding_small.w,
		metrics.padding_control.x,
		metrics.padding_control.y,
		metrics.padding_control.z,
		metrics.padding_control.w,
		metrics.padding_panel.x,
		metrics.padding_panel.y,
		metrics.padding_panel.z,
		metrics.padding_panel.w,
	}
	for value in numbers {
		if math.is_nan(value) || math.is_inf(value) || value < 0 {
			return false
		}
	}
	return(
		theme.font != "" &&
		metrics.text_size > 0 &&
		metrics.small_text_size > 0 &&
		metrics.control_height > 0 &&
		metrics.row_height > 0 &&
		metrics.title_height > 0 \
	)
}
