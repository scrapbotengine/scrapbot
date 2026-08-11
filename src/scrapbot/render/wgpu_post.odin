package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import "vendor:wgpu"

WGPU_Volumetric_Fog_Settings :: struct {
	color: shared.Vec3,
	resolution_scale: f32,
	density: f32,
	height: f32,
	height_falloff: f32,
	max_distance: f32,
	anisotropy: f32,
	ambient_intensity: f32,
	light_intensity: f32,
	point_light_intensity: f32,
}

WGPU_Water_Volume_Settings :: struct {
	enabled: bool,
	entity_index: int,
	surface_height: f32,
	surface_displacement_bound: f32,
	transition_size: f32,
	submersion: f32,
	max_distance: f32,
	absorption: shared.Vec3,
	scattering: shared.Vec3,
	ambient_intensity: f32,
	anisotropy: f32,
	distortion: f32,
	distortion_scale: f32,
	distortion_speed: f32,
	caustics_intensity: f32,
	caustics_scale: f32,
	caustics_speed: f32,
	caustics_max_depth: f32,
}

WGPU_Vignette_Settings :: struct {
	color: shared.Vec3,
	intensity: f32,
	center: shared.Vec2,
	smoothness: f32,
	roundness: f32,
}

WGPU_Lens_Flare_Settings :: struct {
	tint: shared.Vec3,
	intensity: f32,
	threshold: f32,
	ghost_count: f32,
	ghost_spacing: f32,
	halo_intensity: f32,
	halo_radius: f32,
	chromatic_aberration: f32,
}

WGPU_Lens_Dirt_Settings :: struct {
	tint: shared.Vec3,
	intensity: f32,
	scale: f32,
	contrast: f32,
	seed: f32,
}

WGPU_Post_Effects_Uniform :: struct {
	vignette_color_intensity: [4]f32,
	vignette_center_shape: [4]f32,
	flare_tint_intensity: [4]f32,
	flare_ghosts: [4]f32,
	flare_optics: [4]f32,
	dirt_tint_intensity: [4]f32,
	dirt_parameters: [4]f32,
	editor_feedback: [4]f32,
}

wgpu_editor_feedback_uniform :: proc(
	animation_time: f32,
	animate_selection_outline: bool,
) -> [4]f32 {
	if !animate_selection_outline {
		return {0, 0, 10, 7}
	}
	return {animation_time, 1, 10, 7}
}

wgpu_editor_selection_outline_uniform :: proc(
	engine_elapsed_time: f64,
	animate_selection_outline: bool,
) -> [4]f32 {
	if !animate_selection_outline {
		return wgpu_editor_feedback_uniform(0, false)
	}
	animation_time := f32(math.mod(engine_elapsed_time, 1024))
	return wgpu_editor_feedback_uniform(animation_time, true)
}

wgpu_store_post_effects_uniform :: proc(
	renderer: ^WGPU_Renderer,
	uniform: WGPU_Post_Effects_Uniform,
) -> bool {
	if renderer == nil ||
	   (renderer.post_effects_uniform_valid && renderer.post_effects_uniform == uniform) {
		return false
	}
	renderer.post_effects_uniform = uniform
	renderer.post_effects_uniform_valid = true
	return true
}

wgpu_post_component :: proc(world: ^shared.World, name: string) -> ^shared.Custom_Component {
	if world == nil {
		return nil
	}
	component: ^shared.Custom_Component
	best_scene_order := 0
	for &storage in world.custom_components {
		if storage.name != name {
			continue
		}
		for component_index in storage.active_component_indices {
			if component_index < 0 || component_index >= len(storage.components) {
				continue
			}
			candidate := &storage.components[component_index]
			entity_index := candidate.entity_index
			if entity_index < 0 ||
			   entity_index >= len(world.entities) ||
			   !world.entities[entity_index].alive {
				continue
			}
			scene_order := world.entities[entity_index].scene_order
			if component == nil || scene_order < best_scene_order {
				component = candidate
				best_scene_order = scene_order
			}
		}
		break
	}
	return component
}

wgpu_fog_number :: proc(component: ^shared.Custom_Component, name: string, fallback: f32) -> f32 {
	if component == nil {
		return fallback
	}
	for field in component.number_fields {
		if field.name == name {
			if math.is_nan(field.value) || math.is_inf(field.value) {
				return fallback
			}
			return field.value
		}
	}
	return fallback
}

wgpu_fog_vec3 :: proc(
	component: ^shared.Custom_Component,
	name: string,
	fallback: shared.Vec3,
) -> shared.Vec3 {
	if component == nil {
		return fallback
	}
	for field in component.vec3_fields {
		if field.name == name {
			value := field.value
			if math.is_nan(value.x) ||
			   math.is_inf(value.x) ||
			   math.is_nan(value.y) ||
			   math.is_inf(value.y) ||
			   math.is_nan(value.z) ||
			   math.is_inf(value.z) {
				return fallback
			}
			return value
		}
	}
	return fallback
}

wgpu_post_vec2 :: proc(
	component: ^shared.Custom_Component,
	name: string,
	fallback: shared.Vec2,
) -> shared.Vec2 {
	if component == nil {
		return fallback
	}
	for field in component.vec2_fields {
		if field.name == name {
			value := field.value
			if math.is_nan(value.x) ||
			   math.is_inf(value.x) ||
			   math.is_nan(value.y) ||
			   math.is_inf(value.y) {
				return fallback
			}
			return value
		}
	}
	return fallback
}

wgpu_water_volume_settings :: proc(
	world: ^shared.World,
	camera_position: shared.Vec3,
) -> WGPU_Water_Volume_Settings {
	settings := WGPU_Water_Volume_Settings {
		entity_index = -1,
		max_distance = 100,
		absorption = {0.11, 0.035, 0.015},
		scattering = {0.006, 0.025, 0.035},
		ambient_intensity = 0.5,
		anisotropy = 0.65,
		distortion = 1,
		distortion_scale = 0.16,
		distortion_speed = 0.08,
		caustics_intensity = 1,
		caustics_scale = 1,
		caustics_speed = 0.08,
		caustics_max_depth = 24,
		surface_displacement_bound = 4,
	}
	if world == nil {
		return settings
	}
	best_priority := f32(0)
	best_scene_order := 0
	for &storage in world.custom_components {
		if storage.name != "scrapbot.water_volume" {
			continue
		}
		ecs.begin_world_transform_resolution(world)
		for component_index in storage.active_component_indices {
			if component_index < 0 || component_index >= len(storage.components) {
				continue
			}
			component := &storage.components[component_index]
			entity_index := component.entity_index
			if entity_index < 0 ||
			   entity_index >= len(world.entities) ||
			   !world.entities[entity_index].alive {
				continue
			}
			transform, valid := ecs.resolve_world_transform(world, entity_index)
			if !valid {
				continue
			}
			extents := wgpu_post_vec2(component, "extents", {})
			extents.x = max(extents.x, 0)
			extents.y = max(extents.y, 0)
			if (extents.x > 0 && abs(camera_position.x - transform.position.x) > extents.x) ||
			   (extents.y > 0 && abs(camera_position.z - transform.position.z) > extents.y) {
				continue
			}
			depth := max(wgpu_fog_number(component, "depth", 100), f32(0.1))
			transition_size := max(wgpu_fog_number(component, "transition_size", 0.5), f32(0.01))
			surface_displacement_bound := max(
				wgpu_fog_number(component, "surface_displacement_bound", 4),
				f32(0),
			)
			surface_height := transform.position.y
			if camera_position.y > surface_height + transition_size + surface_displacement_bound ||
			   camera_position.y < surface_height - depth - surface_displacement_bound {
				continue
			}
			priority := wgpu_fog_number(component, "priority", 0)
			scene_order := world.entities[entity_index].scene_order
			if settings.enabled &&
			   (priority < best_priority ||
					   (priority == best_priority && scene_order >= best_scene_order)) {
				continue
			}
			settings.enabled = true
			settings.entity_index = entity_index
			settings.surface_height = surface_height
			settings.surface_displacement_bound = surface_displacement_bound
			settings.transition_size = transition_size
			settings.submersion = clamp(
				(surface_height + transition_size - camera_position.y) / (2 * transition_size),
				f32(0),
				f32(1),
			)
			settings.max_distance = clamp(
				wgpu_fog_number(component, "max_distance", settings.max_distance),
				f32(0.1),
				f32(10000),
			)
			settings.absorption = wgpu_fog_vec3(component, "absorption", settings.absorption)
			settings.scattering = wgpu_fog_vec3(component, "scattering", settings.scattering)
			settings.absorption.x = max(settings.absorption.x, 0)
			settings.absorption.y = max(settings.absorption.y, 0)
			settings.absorption.z = max(settings.absorption.z, 0)
			settings.scattering.x = max(settings.scattering.x, 0)
			settings.scattering.y = max(settings.scattering.y, 0)
			settings.scattering.z = max(settings.scattering.z, 0)
			settings.ambient_intensity = clamp(
				wgpu_fog_number(component, "ambient_intensity", settings.ambient_intensity),
				f32(0),
				f32(10),
			)
			settings.anisotropy = clamp(
				wgpu_fog_number(component, "anisotropy", settings.anisotropy),
				f32(-0.9),
				f32(0.9),
			)
			settings.distortion = clamp(
				wgpu_fog_number(component, "distortion", settings.distortion),
				f32(0),
				f32(8),
			)
			settings.distortion_scale = clamp(
				wgpu_fog_number(component, "distortion_scale", settings.distortion_scale),
				f32(0.001),
				f32(10),
			)
			settings.distortion_speed = clamp(
				wgpu_fog_number(component, "distortion_speed", settings.distortion_speed),
				f32(-10),
				f32(10),
			)
			settings.caustics_intensity = clamp(
				wgpu_fog_number(component, "caustics_intensity", settings.caustics_intensity),
				f32(0),
				f32(10),
			)
			settings.caustics_scale = clamp(
				wgpu_fog_number(component, "caustics_scale", settings.caustics_scale),
				f32(0.1),
				f32(10),
			)
			settings.caustics_speed = clamp(
				wgpu_fog_number(component, "caustics_speed", settings.caustics_speed),
				f32(-10),
				f32(10),
			)
			settings.caustics_max_depth = clamp(
				wgpu_fog_number(component, "caustics_max_depth", settings.caustics_max_depth),
				f32(0.1),
				f32(1000),
			)
			best_priority = priority
			best_scene_order = scene_order
		}
		break
	}
	return settings
}

wgpu_volumetric_fog_settings :: proc(world: ^shared.World) -> WGPU_Volumetric_Fog_Settings {
	settings := WGPU_Volumetric_Fog_Settings {
		color = {0.62, 0.72, 0.82},
		resolution_scale = WGPU_DEFAULT_VOLUMETRIC_FOG_RESOLUTION_SCALE,
		height_falloff = 0.2,
		max_distance = 100,
		anisotropy = 0.35,
		ambient_intensity = 0.15,
		light_intensity = 1,
	}
	if world == nil {
		return settings
	}
	component := wgpu_post_component(world, "scrapbot.volumetric_fog")
	if component == nil {
		return settings
	}
	settings.color = wgpu_fog_vec3(component, "color", settings.color)
	settings.color.x = max(settings.color.x, 0)
	settings.color.y = max(settings.color.y, 0)
	settings.color.z = max(settings.color.z, 0)
	settings.resolution_scale = clamp(
		wgpu_fog_number(component, "resolution_scale", settings.resolution_scale),
		f32(0.25),
		f32(1),
	)
	settings.density = clamp(wgpu_fog_number(component, "density", 0), f32(0), f32(1))
	settings.height = wgpu_fog_number(component, "height", 0)
	settings.height_falloff = clamp(
		wgpu_fog_number(component, "height_falloff", settings.height_falloff),
		f32(0),
		f32(10),
	)
	settings.max_distance = clamp(
		wgpu_fog_number(component, "max_distance", settings.max_distance),
		f32(0.1),
		f32(10000),
	)
	settings.anisotropy = clamp(
		wgpu_fog_number(component, "anisotropy", settings.anisotropy),
		f32(-0.9),
		f32(0.9),
	)
	settings.ambient_intensity = clamp(
		wgpu_fog_number(component, "ambient_intensity", settings.ambient_intensity),
		f32(0),
		f32(10),
	)
	settings.light_intensity = clamp(
		wgpu_fog_number(component, "light_intensity", settings.light_intensity),
		f32(0),
		f32(10),
	)
	settings.point_light_intensity = clamp(
		wgpu_fog_number(component, "point_light_intensity", settings.point_light_intensity),
		f32(0),
		f32(10),
	)
	return settings
}

wgpu_vignette_settings :: proc(world: ^shared.World) -> WGPU_Vignette_Settings {
	settings := WGPU_Vignette_Settings {
		color = {},
		center = {0.5, 0.5},
		smoothness = 0.35,
		roundness = 0.75,
	}
	component := wgpu_post_component(world, "scrapbot.vignette")
	if component == nil {
		return settings
	}
	settings.color = wgpu_fog_vec3(component, "color", settings.color)
	settings.color.x = max(settings.color.x, 0)
	settings.color.y = max(settings.color.y, 0)
	settings.color.z = max(settings.color.z, 0)
	settings.intensity = clamp(wgpu_fog_number(component, "intensity", 0.3), f32(0), f32(1))
	settings.center = wgpu_post_vec2(component, "center", settings.center)
	settings.center.x = clamp(settings.center.x, f32(0), f32(1))
	settings.center.y = clamp(settings.center.y, f32(0), f32(1))
	settings.smoothness = clamp(
		wgpu_fog_number(component, "smoothness", settings.smoothness),
		f32(0.01),
		f32(1),
	)
	settings.roundness = clamp(
		wgpu_fog_number(component, "roundness", settings.roundness),
		f32(0),
		f32(1),
	)
	return settings
}

wgpu_lens_flare_settings :: proc(world: ^shared.World) -> WGPU_Lens_Flare_Settings {
	settings := WGPU_Lens_Flare_Settings {
		tint = {1, 0.82, 0.62},
		threshold = 1,
		ghost_count = 5,
		ghost_spacing = 0.32,
		halo_intensity = 0.35,
		halo_radius = 0.48,
		chromatic_aberration = 0.006,
	}
	component := wgpu_post_component(world, "scrapbot.lens_flare")
	if component == nil {
		return settings
	}
	settings.tint = wgpu_fog_vec3(component, "tint", settings.tint)
	settings.tint.x = max(settings.tint.x, 0)
	settings.tint.y = max(settings.tint.y, 0)
	settings.tint.z = max(settings.tint.z, 0)
	settings.intensity = clamp(wgpu_fog_number(component, "intensity", 0.65), f32(0), f32(10))
	settings.threshold = clamp(
		wgpu_fog_number(component, "threshold", settings.threshold),
		f32(0),
		f32(100),
	)
	settings.ghost_count = clamp(
		wgpu_fog_number(component, "ghost_count", settings.ghost_count),
		f32(1),
		f32(8),
	)
	settings.ghost_spacing = clamp(
		wgpu_fog_number(component, "ghost_spacing", settings.ghost_spacing),
		f32(0.05),
		f32(1),
	)
	settings.halo_intensity = clamp(
		wgpu_fog_number(component, "halo_intensity", settings.halo_intensity),
		f32(0),
		f32(5),
	)
	settings.halo_radius = clamp(
		wgpu_fog_number(component, "halo_radius", settings.halo_radius),
		f32(0.05),
		f32(1),
	)
	settings.chromatic_aberration = clamp(
		wgpu_fog_number(component, "chromatic_aberration", settings.chromatic_aberration),
		f32(0),
		f32(0.05),
	)
	return settings
}

wgpu_lens_dirt_settings :: proc(world: ^shared.World) -> WGPU_Lens_Dirt_Settings {
	settings := WGPU_Lens_Dirt_Settings {
		tint = {1, 0.88, 0.72},
		scale = 3,
		contrast = 1.8,
		seed = 7,
	}
	component := wgpu_post_component(world, "scrapbot.lens_dirt")
	if component == nil {
		return settings
	}
	settings.tint = wgpu_fog_vec3(component, "tint", settings.tint)
	settings.tint.x = max(settings.tint.x, 0)
	settings.tint.y = max(settings.tint.y, 0)
	settings.tint.z = max(settings.tint.z, 0)
	settings.intensity = clamp(wgpu_fog_number(component, "intensity", 0.55), f32(0), f32(5))
	settings.scale = clamp(wgpu_fog_number(component, "scale", settings.scale), f32(0.25), f32(16))
	settings.contrast = clamp(
		wgpu_fog_number(component, "contrast", settings.contrast),
		f32(0.25),
		f32(8),
	)
	settings.seed = wgpu_fog_number(component, "seed", settings.seed)
	return settings
}

wgpu_create_post_process_pipelines :: proc(renderer: ^WGPU_Renderer) -> string {
	post_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_POST_PROCESS_SHADER,
	}
	renderer.post_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &post_chain, label = "Scrapbot Bloom Shader"},
	)
	if renderer.post_shader == nil {
		return "failed to create bloom shader"
	}

	temporal_aa_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_TEMPORAL_AA_SHADER,
	}
	renderer.temporal_aa_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &temporal_aa_chain,
			label = "Scrapbot Temporal AA Shader",
		},
	)
	if renderer.temporal_aa_shader == nil {
		return "failed to create temporal AA shader"
	}
	temporal_aa_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 6,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .R32Float, viewDimension = ._2D},
		},
		{
			binding = 7,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Temporal_AA_Uniform))},
		},
		{
			binding = 8,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 9,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 10,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 11,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 12,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 13,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2DArray},
		},
		{binding = 14, visibility = {.Compute}, sampler = {type = .Comparison}},
		{
			binding = 15,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 16,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 17,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 18,
			visibility = {.Compute},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_Water_Surface_Query_Result)),
			},
		},
	}
	renderer.temporal_aa_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Temporal AA Bind Group Layout",
			entryCount = uint(len(temporal_aa_layout_entries)),
			entries = raw_data(temporal_aa_layout_entries[:]),
		},
	)
	if renderer.temporal_aa_bind_group_layout == nil {
		return "failed to create temporal AA bind group layout"
	}
	temporal_aa_bind_group_layouts := [?]wgpu.BindGroupLayout {
		renderer.temporal_aa_bind_group_layout,
		renderer.gpu_cluster_bind_group_layout,
	}
	renderer.temporal_aa_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Temporal AA Pipeline Layout",
			bindGroupLayoutCount = uint(len(temporal_aa_bind_group_layouts)),
			bindGroupLayouts = raw_data(temporal_aa_bind_group_layouts[:]),
		},
	)
	if renderer.temporal_aa_pipeline_layout == nil {
		return "failed to create temporal AA pipeline layout"
	}
	renderer.temporal_aa_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Temporal AA Pipeline",
			layout = renderer.temporal_aa_pipeline_layout,
			compute = {module = renderer.temporal_aa_shader, entryPoint = "temporal_aa_cs"},
		},
	)
	if renderer.temporal_aa_pipeline == nil {
		return "failed to create temporal AA compute pipeline"
	}
	renderer.volumetric_fog_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Volumetric Fog Pipeline",
			layout = renderer.temporal_aa_pipeline_layout,
			compute = {module = renderer.temporal_aa_shader, entryPoint = "volumetric_fog_cs"},
		},
	)
	if renderer.volumetric_fog_pipeline == nil {
		return "failed to create volumetric fog compute pipeline"
	}
	renderer.temporal_aa_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Temporal AA Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Temporal_AA_Uniform)),
		},
	)
	if renderer.temporal_aa_uniform_buffer == nil {
		return "failed to create temporal AA uniform buffer"
	}

	ambient_occlusion_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_AMBIENT_OCCLUSION_SHADER,
	}
	renderer.ambient_occlusion_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &ambient_occlusion_chain,
			label = "Scrapbot Ambient Occlusion Shader",
		},
	)
	if renderer.ambient_occlusion_shader == nil {
		return "failed to create ambient occlusion shader"
	}
	ambient_occlusion_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 1,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 2,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA8Unorm, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
			},
		},
	}
	renderer.ambient_occlusion_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Ambient Occlusion Bind Group Layout",
			entryCount = uint(len(ambient_occlusion_layout_entries)),
			entries = raw_data(ambient_occlusion_layout_entries[:]),
		},
	)
	if renderer.ambient_occlusion_bind_group_layout == nil {
		return "failed to create ambient occlusion bind group layout"
	}
	renderer.ambient_occlusion_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Ambient Occlusion Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.ambient_occlusion_bind_group_layout,
		},
	)
	if renderer.ambient_occlusion_pipeline_layout == nil {
		return "failed to create ambient occlusion pipeline layout"
	}
	renderer.ambient_occlusion_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "ambient_occlusion_cs",
			},
		},
	)
	renderer.ambient_occlusion_blur_horizontal_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Horizontal Blur Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "blur_horizontal_cs",
			},
		},
	)
	renderer.ambient_occlusion_blur_vertical_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Vertical Blur Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "blur_vertical_cs",
			},
		},
	)
	if renderer.ambient_occlusion_pipeline == nil ||
	   renderer.ambient_occlusion_blur_horizontal_pipeline == nil ||
	   renderer.ambient_occlusion_blur_vertical_pipeline == nil {
		return "failed to create ambient occlusion compute pipelines"
	}
	renderer.ambient_occlusion_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Ambient Occlusion Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
		},
	)
	if renderer.ambient_occlusion_uniform_buffer == nil {
		return "failed to create ambient occlusion uniform buffer"
	}

	reflections_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_SCREEN_SPACE_REFLECTIONS_SHADER,
	}
	renderer.screen_space_reflections_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &reflections_chain,
			label = "Scrapbot Screen-Space Reflections Shader",
		},
	)
	if renderer.screen_space_reflections_shader == nil {
		return "failed to create screen-space reflections shader"
	}
	reflections_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
			},
		},
	}
	renderer.screen_space_reflections_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Screen-Space Reflections Bind Group Layout",
			entryCount = uint(len(reflections_layout_entries)),
			entries = raw_data(reflections_layout_entries[:]),
		},
	)
	if renderer.screen_space_reflections_bind_group_layout == nil {
		return "failed to create screen-space reflections bind group layout"
	}
	renderer.screen_space_reflections_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Screen-Space Reflections Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.screen_space_reflections_bind_group_layout,
		},
	)
	if renderer.screen_space_reflections_pipeline_layout == nil {
		return "failed to create screen-space reflections pipeline layout"
	}
	renderer.screen_space_reflections_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Screen-Space Reflections Pipeline",
			layout = renderer.screen_space_reflections_pipeline_layout,
			compute = {
				module = renderer.screen_space_reflections_shader,
				entryPoint = "screen_space_reflections_cs",
			},
		},
	)
	if renderer.screen_space_reflections_pipeline == nil {
		return "failed to create screen-space reflections pipeline"
	}
	renderer.screen_space_reflections_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Screen-Space Reflections Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
		},
	)
	if renderer.screen_space_reflections_uniform_buffer == nil {
		return "failed to create screen-space reflections uniform buffer"
	}

	automatic_exposure_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_AUTOMATIC_EXPOSURE_SHADER,
	}
	renderer.automatic_exposure_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &automatic_exposure_chain,
			label = "Scrapbot Automatic Exposure Shader",
		},
	)
	if renderer.automatic_exposure_shader == nil {
		return "failed to create automatic exposure shader"
	}
	automatic_exposure_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 1,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Automatic_Exposure_Settings)),
			},
		},
		{
			binding = 2,
			visibility = {.Compute, .Fragment},
			buffer = {
				type = .Storage,
				minBindingSize = u64(size_of(WGPU_Automatic_Exposure_State)),
			},
		},
	}
	renderer.automatic_exposure_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Automatic Exposure Bind Group Layout",
			entryCount = uint(len(automatic_exposure_layout_entries)),
			entries = raw_data(automatic_exposure_layout_entries[:]),
		},
	)
	if renderer.automatic_exposure_bind_group_layout == nil {
		return "failed to create automatic exposure bind group layout"
	}
	renderer.automatic_exposure_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Automatic Exposure Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.automatic_exposure_bind_group_layout,
		},
	)
	if renderer.automatic_exposure_pipeline_layout == nil {
		return "failed to create automatic exposure pipeline layout"
	}
	renderer.automatic_exposure_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Automatic Exposure Pipeline",
			layout = renderer.automatic_exposure_pipeline_layout,
			compute = {
				module = renderer.automatic_exposure_shader,
				entryPoint = "automatic_exposure_cs",
			},
		},
	)
	if renderer.automatic_exposure_pipeline == nil {
		return "failed to create automatic exposure pipeline"
	}
	renderer.automatic_exposure_settings_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Automatic Exposure Settings Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Automatic_Exposure_Settings)),
		},
	)
	renderer.automatic_exposure_state_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Automatic Exposure State Buffer",
			usage = {.Storage, .CopyDst},
			size = u64(size_of(WGPU_Automatic_Exposure_State)),
		},
	)
	if renderer.automatic_exposure_settings_buffer == nil ||
	   renderer.automatic_exposure_state_buffer == nil {
		return "failed to allocate automatic exposure buffers"
	}
	renderer.post_effects_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Post Effects Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Post_Effects_Uniform)),
		},
	)
	if renderer.post_effects_uniform_buffer == nil {
		return "failed to allocate post effects uniform buffer"
	}
	initial_exposure := WGPU_Automatic_Exposure_State {
		values = {1, 1, 1, 1},
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.automatic_exposure_state_buffer,
		0,
		&initial_exposure,
		size_of(initial_exposure),
	)

	bloom_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_Automatic_Exposure_State)),
			},
		},
	}
	renderer.bloom_compute_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Bloom Compute Bind Group Layout",
			entryCount = uint(len(bloom_layout_entries)),
			entries = raw_data(bloom_layout_entries[:]),
		},
	)
	if renderer.bloom_compute_bind_group_layout == nil {
		return "failed to create bloom compute bind group layout"
	}
	renderer.bloom_compute_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Bloom Compute Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.bloom_compute_bind_group_layout,
		},
	)
	if renderer.bloom_compute_pipeline_layout == nil {
		return "failed to create bloom compute pipeline layout"
	}

	renderer.bloom_bright_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Bloom Extract Compute Pipeline",
			layout = renderer.bloom_compute_pipeline_layout,
			compute = {module = renderer.post_shader, entryPoint = "bright_cs"},
		},
	)
	renderer.bloom_downsample_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Bloom Downsample Compute Pipeline",
			layout = renderer.bloom_compute_pipeline_layout,
			compute = {module = renderer.post_shader, entryPoint = "downsample_cs"},
		},
	)
	if renderer.bloom_bright_pipeline == nil || renderer.bloom_downsample_pipeline == nil {
		return "failed to create bloom compute pipelines"
	}
	composite_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_COMPOSITE_SHADER,
	}
	renderer.composite_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &composite_chain,
			label = "Scrapbot HDR Composite Shader",
		},
	)
	if renderer.composite_shader == nil {
		return "failed to create HDR composite shader"
	}
	composite_entries: [5 + WGPU_BLOOM_LEVELS]wgpu.BindGroupLayoutEntry
	composite_entries[0] = {
		binding = 0,
		visibility = {.Fragment},
		texture = {sampleType = .Float, viewDimension = ._2D},
	}
	composite_entries[1] = {
		binding = 1,
		visibility = {.Fragment},
		sampler = {type = .Filtering},
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		composite_entries[index + 2] = {
			binding = u32(index + 2),
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}
	}
	composite_entries[2 + WGPU_BLOOM_LEVELS] = {
		binding = u32(2 + WGPU_BLOOM_LEVELS),
		visibility = {.Fragment},
		buffer = {
			type = .ReadOnlyStorage,
			minBindingSize = u64(size_of(WGPU_Automatic_Exposure_State)),
		},
	}
	composite_entries[3 + WGPU_BLOOM_LEVELS] = {
		binding = u32(3 + WGPU_BLOOM_LEVELS),
		visibility = {.Fragment},
		buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Post_Effects_Uniform))},
	}
	composite_entries[4 + WGPU_BLOOM_LEVELS] = {
		binding = u32(4 + WGPU_BLOOM_LEVELS),
		visibility = {.Fragment},
		texture = {sampleType = .Float, viewDimension = ._2D},
	}
	renderer.composite_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot HDR Composite Bind Group Layout",
			entryCount = uint(len(composite_entries)),
			entries = raw_data(composite_entries[:]),
		},
	)
	if renderer.composite_bind_group_layout == nil {
		return "failed to create HDR composite bind group layout"
	}
	renderer.composite_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot HDR Composite Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.composite_bind_group_layout,
		},
	)
	if renderer.composite_pipeline_layout == nil {
		return "failed to create HDR composite pipeline layout"
	}
	renderer.composite_pipeline = wgpu_create_fullscreen_pipeline(
		renderer,
		renderer.composite_shader,
		renderer.composite_pipeline_layout,
		"composite_fs",
		renderer.format,
		"Scrapbot HDR Composite Pipeline",
	)
	if renderer.composite_pipeline == nil {
		return "failed to create HDR composite pipeline"
	}

	renderer.post_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Post Process Sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			maxAnisotropy = 1,
		},
	)
	if renderer.post_sampler == nil {
		return "failed to create post-process sampler"
	}
	return ""
}

wgpu_create_fullscreen_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	shader: wgpu.ShaderModule,
	layout: wgpu.PipelineLayout,
	fragment_entry: string,
	format: wgpu.TextureFormat,
	label: string,
) -> wgpu.RenderPipeline {
	target := wgpu.ColorTargetState {
		format = format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = shader,
		entryPoint = fragment_entry,
		targetCount = 1,
		targets = &target,
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = label,
			layout = layout,
			vertex = {module = shader, entryPoint = "fullscreen_vs"},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
}

wgpu_create_post_texture :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	width, height: u32,
	format: wgpu.TextureFormat,
	usage: wgpu.TextureUsageFlags,
) -> (
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	err: string,
) {
	texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = usage,
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if texture == nil {
		err = "failed to create retained post-process texture"
		return
	}
	view = wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		texture = nil
		err = "failed to create retained post-process texture view"
	}
	return
}

wgpu_release_post_targets :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_custom_shader_target(renderer)
	for index in 0 ..< len(renderer.temporal_color_textures) {
		if renderer.automatic_exposure_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.automatic_exposure_bind_groups[index])
			renderer.automatic_exposure_bind_groups[index] = nil
		}
		if renderer.composite_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.composite_bind_groups[index])
			renderer.composite_bind_groups[index] = nil
		}
		if renderer.temporal_aa_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.temporal_aa_bind_groups[index])
			renderer.temporal_aa_bind_groups[index] = nil
		}
		if renderer.temporal_color_views[index] != nil {
			wgpu.TextureViewRelease(renderer.temporal_color_views[index])
			renderer.temporal_color_views[index] = nil
		}
		if renderer.temporal_color_textures[index] != nil {
			wgpu.TextureRelease(renderer.temporal_color_textures[index])
			renderer.temporal_color_textures[index] = nil
		}
		if renderer.temporal_depth_views[index] != nil {
			wgpu.TextureViewRelease(renderer.temporal_depth_views[index])
			renderer.temporal_depth_views[index] = nil
		}
		if renderer.temporal_depth_textures[index] != nil {
			wgpu.TextureRelease(renderer.temporal_depth_textures[index])
			renderer.temporal_depth_textures[index] = nil
		}
	}
	for index in 0 ..< len(renderer.volumetric_fog_bind_groups) {
		if renderer.volumetric_fog_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.volumetric_fog_bind_groups[index])
			renderer.volumetric_fog_bind_groups[index] = nil
		}
	}
	for index in 0 ..< len(renderer.volumetric_fog_textures) {
		if renderer.volumetric_fog_views[index] != nil {
			wgpu.TextureViewRelease(renderer.volumetric_fog_views[index])
			renderer.volumetric_fog_views[index] = nil
		}
		if renderer.volumetric_fog_textures[index] != nil {
			wgpu.TextureRelease(renderer.volumetric_fog_textures[index])
			renderer.volumetric_fog_textures[index] = nil
		}
	}
	if renderer.volumetric_fog_dummy_view != nil {
		wgpu.TextureViewRelease(renderer.volumetric_fog_dummy_view)
		renderer.volumetric_fog_dummy_view = nil
	}
	if renderer.volumetric_fog_dummy_texture != nil {
		wgpu.TextureRelease(renderer.volumetric_fog_dummy_texture)
		renderer.volumetric_fog_dummy_texture = nil
	}
	for index in 0 ..< len(renderer.ambient_occlusion_bind_groups) {
		if renderer.ambient_occlusion_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.ambient_occlusion_bind_groups[index])
			renderer.ambient_occlusion_bind_groups[index] = nil
		}
		if renderer.ambient_occlusion_views[index] != nil {
			wgpu.TextureViewRelease(renderer.ambient_occlusion_views[index])
			renderer.ambient_occlusion_views[index] = nil
		}
		if renderer.ambient_occlusion_textures[index] != nil {
			wgpu.TextureRelease(renderer.ambient_occlusion_textures[index])
			renderer.ambient_occlusion_textures[index] = nil
		}
	}
	if renderer.screen_space_reflections_bind_group != nil {
		wgpu.BindGroupRelease(renderer.screen_space_reflections_bind_group)
		renderer.screen_space_reflections_bind_group = nil
	}
	if renderer.screen_space_reflections_view != nil {
		wgpu.TextureViewRelease(renderer.screen_space_reflections_view)
		renderer.screen_space_reflections_view = nil
	}
	if renderer.screen_space_reflections_texture != nil {
		wgpu.TextureRelease(renderer.screen_space_reflections_texture)
		renderer.screen_space_reflections_texture = nil
	}
	for temporal_index in 0 ..< len(renderer.bloom_compute_bind_groups) {
		for index in 0 ..< WGPU_BLOOM_LEVELS {
			if renderer.bloom_compute_bind_groups[temporal_index][index] != nil {
				wgpu.BindGroupRelease(renderer.bloom_compute_bind_groups[temporal_index][index])
				renderer.bloom_compute_bind_groups[temporal_index][index] = nil
			}
		}
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		if renderer.bloom_views[index] != nil {
			wgpu.TextureViewRelease(renderer.bloom_views[index])
			renderer.bloom_views[index] = nil
		}
		if renderer.bloom_textures[index] != nil {
			wgpu.TextureRelease(renderer.bloom_textures[index])
			renderer.bloom_textures[index] = nil
		}
	}
	if renderer.hdr_view != nil {
		wgpu.TextureViewRelease(renderer.hdr_view)
		renderer.hdr_view = nil
	}
	if renderer.hdr_texture != nil {
		wgpu.TextureRelease(renderer.hdr_texture)
		renderer.hdr_texture = nil
	}
	if renderer.surface_view != nil {
		wgpu.TextureViewRelease(renderer.surface_view)
		renderer.surface_view = nil
	}
	if renderer.surface_texture != nil {
		wgpu.TextureRelease(renderer.surface_texture)
		renderer.surface_texture = nil
	}
	if renderer.indirect_diffuse_view != nil {
		wgpu.TextureViewRelease(renderer.indirect_diffuse_view)
		renderer.indirect_diffuse_view = nil
	}
	if renderer.indirect_diffuse_texture != nil {
		wgpu.TextureRelease(renderer.indirect_diffuse_texture)
		renderer.indirect_diffuse_texture = nil
	}
	if renderer.custom_motion_view != nil {
		wgpu.TextureViewRelease(renderer.custom_motion_view)
		renderer.custom_motion_view = nil
	}
	if renderer.custom_motion_texture != nil {
		wgpu.TextureRelease(renderer.custom_motion_texture)
		renderer.custom_motion_texture = nil
	}
	if renderer.editor_feedback_mask_view != nil {
		wgpu.TextureViewRelease(renderer.editor_feedback_mask_view)
		renderer.editor_feedback_mask_view = nil
	}
	if renderer.editor_feedback_mask_texture != nil {
		wgpu.TextureRelease(renderer.editor_feedback_mask_texture)
		renderer.editor_feedback_mask_texture = nil
	}
	renderer.editor_feedback_mask_initialized = false
	renderer.editor_feedback_mask_active = false
	renderer.post_width = 0
	renderer.post_height = 0
	renderer.post_ambient_occlusion_resolution_scale = 0
	renderer.post_volumetric_fog_resolution_scale = 0
	renderer.post_depth_view = nil
	renderer.temporal_output_index = 0
	renderer.temporal_history_valid = false
	renderer.volumetric_fog_history_valid = false
	renderer.automatic_exposure_valid = false
}

wgpu_release_post_process :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_post_targets(renderer)
	wgpu_release_render_depth(renderer)
	if renderer.post_sampler != nil {
		wgpu.SamplerRelease(renderer.post_sampler)
	}
	if renderer.temporal_aa_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.temporal_aa_uniform_buffer)
	}
	if renderer.temporal_aa_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.temporal_aa_pipeline)
	}
	if renderer.volumetric_fog_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.volumetric_fog_pipeline)
	}
	if renderer.temporal_aa_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.temporal_aa_pipeline_layout)
	}
	if renderer.temporal_aa_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.temporal_aa_bind_group_layout)
	}
	if renderer.temporal_aa_shader != nil {
		wgpu.ShaderModuleRelease(renderer.temporal_aa_shader)
	}
	if renderer.ambient_occlusion_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.ambient_occlusion_uniform_buffer)
	}
	if renderer.ambient_occlusion_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_pipeline)
	}
	if renderer.ambient_occlusion_blur_horizontal_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_blur_horizontal_pipeline)
	}
	if renderer.ambient_occlusion_blur_vertical_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_blur_vertical_pipeline)
	}
	if renderer.ambient_occlusion_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.ambient_occlusion_pipeline_layout)
	}
	if renderer.ambient_occlusion_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.ambient_occlusion_bind_group_layout)
	}
	if renderer.ambient_occlusion_shader != nil {
		wgpu.ShaderModuleRelease(renderer.ambient_occlusion_shader)
	}
	if renderer.screen_space_reflections_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.screen_space_reflections_uniform_buffer)
	}
	if renderer.screen_space_reflections_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.screen_space_reflections_pipeline)
	}
	if renderer.screen_space_reflections_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.screen_space_reflections_pipeline_layout)
	}
	if renderer.screen_space_reflections_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.screen_space_reflections_bind_group_layout)
	}
	if renderer.screen_space_reflections_shader != nil {
		wgpu.ShaderModuleRelease(renderer.screen_space_reflections_shader)
	}
	if renderer.automatic_exposure_settings_buffer != nil {
		wgpu.BufferRelease(renderer.automatic_exposure_settings_buffer)
	}
	if renderer.automatic_exposure_state_buffer != nil {
		wgpu.BufferRelease(renderer.automatic_exposure_state_buffer)
	}
	if renderer.post_effects_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.post_effects_uniform_buffer)
		renderer.post_effects_uniform_buffer = nil
	}
	renderer.post_effects_uniform_valid = false
	if renderer.automatic_exposure_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.automatic_exposure_pipeline)
	}
	if renderer.automatic_exposure_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.automatic_exposure_pipeline_layout)
	}
	if renderer.automatic_exposure_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.automatic_exposure_bind_group_layout)
	}
	if renderer.automatic_exposure_shader != nil {
		wgpu.ShaderModuleRelease(renderer.automatic_exposure_shader)
	}
	if renderer.composite_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.composite_pipeline)
	}
	if renderer.composite_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.composite_pipeline_layout)
	}
	if renderer.composite_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.composite_bind_group_layout)
	}
	if renderer.composite_shader != nil {
		wgpu.ShaderModuleRelease(renderer.composite_shader)
	}
	if renderer.bloom_bright_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.bloom_bright_pipeline)
	}
	if renderer.bloom_downsample_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.bloom_downsample_pipeline)
	}
	if renderer.bloom_compute_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.bloom_compute_pipeline_layout)
	}
	if renderer.bloom_compute_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.bloom_compute_bind_group_layout)
	}
	if renderer.post_shader != nil {
		wgpu.ShaderModuleRelease(renderer.post_shader)
	}
}

wgpu_ensure_post_targets :: proc(
	renderer: ^WGPU_Renderer,
	width, height: u32,
	depth_view: wgpu.TextureView,
	ambient_occlusion_resolution_scale: f32,
	volumetric_fog_resolution_scale: f32,
) -> string {
	if renderer.post_width == width &&
	   renderer.post_height == height &&
	   renderer.post_depth_view == depth_view &&
	   renderer.post_ambient_occlusion_resolution_scale == ambient_occlusion_resolution_scale &&
	   renderer.post_volumetric_fog_resolution_scale == volumetric_fog_resolution_scale &&
	   renderer.hdr_view != nil {
		return ""
	}
	wgpu_release_post_targets(renderer)
	renderer.hdr_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot HDR Scene Texture",
			usage = {.RenderAttachment, .TextureBinding, .CopySrc},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA16Float,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if renderer.hdr_texture == nil {
		return "failed to create HDR scene texture"
	}
	renderer.hdr_view = wgpu.TextureCreateView(renderer.hdr_texture)
	if renderer.hdr_view == nil {
		return "failed to create HDR scene texture view"
	}
	if err := wgpu_ensure_custom_shader_target(renderer, width, height, depth_view); err != "" {
		return err
	}

	err: string
	renderer.surface_texture, renderer.surface_view, err = wgpu_create_post_texture(
		renderer,
		"Scrapbot Surface Data",
		width,
		height,
		.RGBA16Float,
		{.RenderAttachment, .TextureBinding},
	)
	if err != "" {
		return err
	}
	renderer.volumetric_fog_dummy_texture, renderer.volumetric_fog_dummy_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Volumetric Fog Unused Binding",
			1,
			1,
			.RGBA16Float,
			{.TextureBinding, .StorageBinding},
		)
	if err != "" {
		return err
	}
	renderer.indirect_diffuse_texture, renderer.indirect_diffuse_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Indirect Diffuse",
			width,
			height,
			.RGBA16Float,
			{.RenderAttachment, .TextureBinding},
		)
	if err != "" {
		return err
	}
	renderer.custom_motion_texture, renderer.custom_motion_view, err = wgpu_create_post_texture(
		renderer,
		"Scrapbot Custom Surface Motion",
		width,
		height,
		.RG16Float,
		{.RenderAttachment, .TextureBinding},
	)
	if err != "" {
		return err
	}
	renderer.editor_feedback_mask_texture, renderer.editor_feedback_mask_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Editor Feedback Mask",
			width,
			height,
			.RGBA8Unorm,
			{.RenderAttachment, .TextureBinding},
		)
	if err != "" {
		return err
	}
	renderer.screen_space_reflections_texture, renderer.screen_space_reflections_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Screen-Space Reflections",
			width,
			height,
			.RGBA16Float,
			{.TextureBinding, .StorageBinding},
		)
	if err != "" {
		return err
	}
	reflections_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = renderer.hdr_view},
		{binding = 1, sampler = renderer.post_sampler},
		{binding = 2, textureView = depth_view},
		{binding = 3, textureView = renderer.surface_view},
		{binding = 4, textureView = renderer.screen_space_reflections_view},
		{
			binding = 5,
			buffer = renderer.screen_space_reflections_uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
		},
	}
	renderer.screen_space_reflections_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Screen-Space Reflections Bind Group",
			layout = renderer.screen_space_reflections_bind_group_layout,
			entryCount = uint(len(reflections_entries)),
			entries = raw_data(reflections_entries[:]),
		},
	)
	if renderer.screen_space_reflections_bind_group == nil {
		return "failed to create screen-space reflections bind group"
	}
	for index in 0 ..< len(renderer.temporal_color_textures) {
		renderer.temporal_color_textures[index], renderer.temporal_color_views[index], err =
			wgpu_create_post_texture(
				renderer,
				"Scrapbot Temporal Color",
				width,
				height,
				.RGBA16Float,
				{.TextureBinding, .StorageBinding},
			)
		if err != "" {
			return err
		}
		renderer.temporal_depth_textures[index], renderer.temporal_depth_views[index], err =
			wgpu_create_post_texture(
				renderer,
				"Scrapbot Temporal Depth",
				width,
				height,
				.R32Float,
				{.TextureBinding, .StorageBinding, .CopySrc},
			)
		if err != "" {
			return err
		}
	}
	volumetric_fog_width := wgpu_post_scaled_dimension(width, volumetric_fog_resolution_scale)
	volumetric_fog_height := wgpu_post_scaled_dimension(height, volumetric_fog_resolution_scale)
	for index in 0 ..< len(renderer.volumetric_fog_textures) {
		renderer.volumetric_fog_textures[index], renderer.volumetric_fog_views[index], err =
			wgpu_create_post_texture(
				renderer,
				"Scrapbot Volumetric Fog History",
				volumetric_fog_width,
				volumetric_fog_height,
				.RGBA16Float,
				{.TextureBinding, .StorageBinding},
			)
		if err != "" {
			return err
		}
	}
	ambient_occlusion_width := wgpu_post_scaled_dimension(
		width,
		ambient_occlusion_resolution_scale,
	)
	ambient_occlusion_height := wgpu_post_scaled_dimension(
		height,
		ambient_occlusion_resolution_scale,
	)
	for index in 0 ..< len(renderer.ambient_occlusion_textures) {
		texture := wgpu.DeviceCreateTexture(
			renderer.device,
			&wgpu.TextureDescriptor {
				label = "Scrapbot Ambient Occlusion Texture",
				usage = {.TextureBinding, .StorageBinding},
				dimension = ._2D,
				size = {
					width = ambient_occlusion_width,
					height = ambient_occlusion_height,
					depthOrArrayLayers = 1,
				},
				format = .RGBA8Unorm,
				mipLevelCount = 1,
				sampleCount = 1,
			},
		)
		if texture == nil {
			return "failed to create ambient occlusion texture"
		}
		view := wgpu.TextureCreateView(texture)
		if view == nil {
			wgpu.TextureRelease(texture)
			return "failed to create ambient occlusion texture view"
		}
		renderer.ambient_occlusion_textures[index] = texture
		renderer.ambient_occlusion_views[index] = view
	}
	ambient_occlusion_sources := [?]wgpu.TextureView {
		renderer.ambient_occlusion_views[2],
		renderer.ambient_occlusion_views[0],
		renderer.ambient_occlusion_views[1],
	}
	ambient_occlusion_destinations := [?]wgpu.TextureView {
		renderer.ambient_occlusion_views[0],
		renderer.ambient_occlusion_views[1],
		renderer.ambient_occlusion_views[2],
	}
	for index in 0 ..< len(renderer.ambient_occlusion_bind_groups) {
		entries := [?]wgpu.BindGroupEntry {
			{binding = 0, textureView = depth_view},
			{binding = 1, textureView = ambient_occlusion_sources[index]},
			{binding = 2, textureView = ambient_occlusion_destinations[index]},
			{binding = 3, textureView = renderer.surface_view},
			{
				binding = 4,
				buffer = renderer.ambient_occlusion_uniform_buffer,
				offset = 0,
				size = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
			},
		}
		renderer.ambient_occlusion_bind_groups[index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Ambient Occlusion Bind Group",
				layout = renderer.ambient_occlusion_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
		if renderer.ambient_occlusion_bind_groups[index] == nil {
			return "failed to create ambient occlusion bind groups"
		}
	}
	temporal_entries: [19]wgpu.BindGroupEntry
	for output_index in 0 ..< len(renderer.temporal_color_views) {
		history_index := 1 - output_index
		temporal_entries = {
			{binding = 0, textureView = renderer.hdr_view},
			{binding = 1, sampler = renderer.post_sampler},
			{binding = 2, textureView = depth_view},
			{binding = 3, textureView = renderer.temporal_color_views[history_index]},
			{binding = 4, textureView = renderer.temporal_depth_views[history_index]},
			{binding = 5, textureView = renderer.temporal_color_views[output_index]},
			{binding = 6, textureView = renderer.temporal_depth_views[output_index]},
			{
				binding = 7,
				buffer = renderer.temporal_aa_uniform_buffer,
				offset = 0,
				size = u64(size_of(WGPU_Temporal_AA_Uniform)),
			},
			{binding = 8, textureView = renderer.ambient_occlusion_views[2]},
			{binding = 9, textureView = renderer.screen_space_reflections_view},
			{binding = 10, textureView = renderer.surface_view},
			{binding = 11, textureView = renderer.indirect_diffuse_view},
			{
				binding = 12,
				buffer = renderer.gpu_render_uniform_buffer,
				offset = 0,
				size = u64(size_of(WGPU_GPU_Render_Uniform)),
			},
			{binding = 13, textureView = renderer.shadow_array_view},
			{binding = 14, sampler = renderer.shadow_sampler},
			{binding = 15, textureView = renderer.volumetric_fog_views[output_index]},
			{binding = 16, textureView = renderer.volumetric_fog_dummy_view},
			{binding = 17, textureView = renderer.custom_motion_view},
			{
				binding = 18,
				buffer = renderer.water_surface_query_result_buffer,
				size = u64(size_of(WGPU_Water_Surface_Query_Result)),
			},
		}
		renderer.temporal_aa_bind_groups[output_index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Temporal AA Bind Group",
				layout = renderer.temporal_aa_bind_group_layout,
				entryCount = uint(len(temporal_entries)),
				entries = raw_data(temporal_entries[:]),
			},
		)
		if renderer.temporal_aa_bind_groups[output_index] == nil {
			return "failed to create temporal AA bind group"
		}
	}
	for output_index in 0 ..< len(renderer.volumetric_fog_views) {
		history_index := 1 - output_index
		volumetric_fog_entries := temporal_entries
		volumetric_fog_entries[3] = {
			binding = 3,
			textureView = renderer.temporal_color_views[history_index],
		}
		volumetric_fog_entries[4] = {
			binding = 4,
			textureView = renderer.temporal_depth_views[history_index],
		}
		volumetric_fog_entries[5] = {
			binding = 5,
			textureView = renderer.temporal_color_views[output_index],
		}
		volumetric_fog_entries[6] = {
			binding = 6,
			textureView = renderer.temporal_depth_views[output_index],
		}
		volumetric_fog_entries[15] = {
			binding = 15,
			textureView = renderer.volumetric_fog_views[history_index],
		}
		volumetric_fog_entries[16] = {
			binding = 16,
			textureView = renderer.volumetric_fog_views[output_index],
		}
		renderer.volumetric_fog_bind_groups[output_index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Volumetric Fog History Bind Group",
				layout = renderer.temporal_aa_bind_group_layout,
				entryCount = uint(len(volumetric_fog_entries)),
				entries = raw_data(volumetric_fog_entries[:]),
			},
		)
		if renderer.volumetric_fog_bind_groups[output_index] == nil {
			return "failed to create volumetric fog bind group"
		}
	}

	for temporal_index in 0 ..< len(renderer.temporal_color_views) {
		automatic_exposure_entries := [?]wgpu.BindGroupEntry {
			{binding = 0, textureView = renderer.temporal_color_views[temporal_index]},
			{
				binding = 1,
				buffer = renderer.automatic_exposure_settings_buffer,
				offset = 0,
				size = u64(size_of(WGPU_Automatic_Exposure_Settings)),
			},
			{
				binding = 2,
				buffer = renderer.automatic_exposure_state_buffer,
				offset = 0,
				size = u64(size_of(WGPU_Automatic_Exposure_State)),
			},
		}
		renderer.automatic_exposure_bind_groups[temporal_index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Automatic Exposure Bind Group",
				layout = renderer.automatic_exposure_bind_group_layout,
				entryCount = uint(len(automatic_exposure_entries)),
				entries = raw_data(automatic_exposure_entries[:]),
			},
		)
		if renderer.automatic_exposure_bind_groups[temporal_index] == nil {
			return "failed to create automatic exposure bind group"
		}
	}

	for index in 0 ..< WGPU_BLOOM_LEVELS {
		level_width := max(u32(1), width >> u32(index + 1))
		level_height := max(u32(1), height >> u32(index + 1))
		texture := wgpu.DeviceCreateTexture(
			renderer.device,
			&wgpu.TextureDescriptor {
				label = "Scrapbot Bloom Texture",
				usage = {.TextureBinding, .StorageBinding},
				dimension = ._2D,
				size = {width = level_width, height = level_height, depthOrArrayLayers = 1},
				format = .RGBA16Float,
				mipLevelCount = 1,
				sampleCount = 1,
			},
		)
		if texture == nil {
			return "failed to create bloom texture"
		}
		view := wgpu.TextureCreateView(texture)
		if view == nil {
			wgpu.TextureRelease(texture)
			return "failed to create bloom texture view"
		}
		renderer.bloom_textures[index] = texture
		renderer.bloom_views[index] = view
	}
	for temporal_index in 0 ..< len(renderer.temporal_color_views) {
		for index in 0 ..< WGPU_BLOOM_LEVELS {
			source := renderer.temporal_color_views[temporal_index]
			if index > 0 {
				source = renderer.bloom_views[index - 1]
			}
			entries := [?]wgpu.BindGroupEntry {
				{binding = 0, textureView = source},
				{binding = 1, sampler = renderer.post_sampler},
				{binding = 2, textureView = renderer.bloom_views[index]},
				{
					binding = 3,
					buffer = renderer.automatic_exposure_state_buffer,
					offset = 0,
					size = u64(size_of(WGPU_Automatic_Exposure_State)),
				},
			}
			renderer.bloom_compute_bind_groups[temporal_index][index] = wgpu.DeviceCreateBindGroup(
				renderer.device,
				&wgpu.BindGroupDescriptor {
					label = "Scrapbot Bloom Compute Bind Group",
					layout = renderer.bloom_compute_bind_group_layout,
					entryCount = uint(len(entries)),
					entries = raw_data(entries[:]),
				},
			)
			if renderer.bloom_compute_bind_groups[temporal_index][index] == nil {
				return "failed to create bloom bind groups"
			}
		}
	}
	for temporal_index in 0 ..< len(renderer.temporal_color_views) {
		composite_entries: [5 + WGPU_BLOOM_LEVELS]wgpu.BindGroupEntry
		composite_entries[0] = {
			binding = 0,
			textureView = renderer.temporal_color_views[temporal_index],
		}
		composite_entries[1] = {
			binding = 1,
			sampler = renderer.post_sampler,
		}
		for index in 0 ..< WGPU_BLOOM_LEVELS {
			composite_entries[index + 2] = {
				binding = u32(index + 2),
				textureView = renderer.bloom_views[index],
			}
		}
		composite_entries[2 + WGPU_BLOOM_LEVELS] = {
			binding = u32(2 + WGPU_BLOOM_LEVELS),
			buffer = renderer.automatic_exposure_state_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Automatic_Exposure_State)),
		}
		composite_entries[3 + WGPU_BLOOM_LEVELS] = {
			binding = u32(3 + WGPU_BLOOM_LEVELS),
			buffer = renderer.post_effects_uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Post_Effects_Uniform)),
		}
		composite_entries[4 + WGPU_BLOOM_LEVELS] = {
			binding = u32(4 + WGPU_BLOOM_LEVELS),
			textureView = renderer.editor_feedback_mask_view,
		}
		renderer.composite_bind_groups[temporal_index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot HDR Composite Bind Group",
				layout = renderer.composite_bind_group_layout,
				entryCount = uint(len(composite_entries)),
				entries = raw_data(composite_entries[:]),
			},
		)
		if renderer.composite_bind_groups[temporal_index] == nil {
			return "failed to create HDR composite bind group"
		}
	}
	renderer.temporal_output_index = 0
	renderer.post_width = width
	renderer.post_height = height
	renderer.post_ambient_occlusion_resolution_scale = ambient_occlusion_resolution_scale
	renderer.post_volumetric_fog_resolution_scale = volumetric_fog_resolution_scale
	renderer.post_depth_view = depth_view
	return ""
}

wgpu_post_scaled_dimension :: proc "contextless" (dimension: u32, scale: f32) -> u32 {
	return max(u32(1), u32(math.ceil(f32(dimension) * clamp(scale, 0.25, 1))))
}

wgpu_post_resolution_scales :: proc(
	renderer: ^WGPU_Renderer,
	world: ^shared.World,
	render_feature_overrides: Render_Feature_Overrides,
) -> (
	ambient_occlusion: f32,
	volumetric_fog: f32,
) {
	camera := shared.camera_defaults()
	if renderer != nil && renderer.render_list.has_camera {
		camera = renderer.render_list.camera.camera
	}
	camera = apply_render_feature_overrides(camera, render_feature_overrides)
	fog := wgpu_volumetric_fog_settings(world)
	return shared.camera_ambient_occlusion_resolution_scale(camera), fog.resolution_scale
}

wgpu_encode_fullscreen_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	view: wgpu.TextureView,
	pipeline: wgpu.RenderPipeline,
	bind_group: wgpu.BindGroup,
	label: string,
	timestamp_phase: WGPU_GPU_Timestamp_Phase,
	output_width, output_height: u32,
	output_viewport: ui.Rect,
) -> string {
	attachment := wgpu.RenderPassColorAttachment {
		view = view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {},
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, timestamp_phase)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = label,
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin post-process pass"
	}
	scissor := wgpu_output_viewport_scissor(output_width, output_height, output_viewport)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		output_viewport.x,
		output_viewport.y,
		output_viewport.width,
		output_viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(pass, scissor.x, scissor.y, scissor.width, scissor.height)
	wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, bind_group)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)
	return ""
}

wgpu_encode_bloom_and_composite :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	output_view: wgpu.TextureView,
	depth_view: wgpu.TextureView,
	width, height: u32,
	output_width, output_height: u32,
	output_viewport: ui.Rect,
	camera: shared.Camera_Component,
	has_camera: bool,
	world: ^shared.World,
	registry: ^resources.Registry,
	delta_time: f32,
	engine_elapsed_time: f64,
	animate_selection_outline: bool,
	render_feature_overrides: Render_Feature_Overrides,
) -> string {
	resolved_camera := camera
	if !has_camera {
		resolved_camera = shared.camera_defaults()
	}
	resolved_camera = apply_render_feature_overrides(resolved_camera, render_feature_overrides)
	adaptive_post_quality := f32(1)
	if renderer.dynamic_resolution.enabled {
		adaptive_post_quality = clamp(renderer.dynamic_resolution.effective_post_quality, 0.25, 1)
	}
	resolved_camera = camera_apply_adaptive_post_quality(resolved_camera, adaptive_post_quality)
	fog := wgpu_volumetric_fog_settings(world)
	if render_feature_overrides.disable_volumetric_fog {
		fog.density = 0
	}
	water: WGPU_Water_Volume_Settings
	if has_camera && renderer.render_list.has_camera {
		water = wgpu_water_volume_settings(world, renderer.render_list.camera.transform.position)
	}
	ambient_occlusion_resolution_scale := shared.camera_ambient_occlusion_resolution_scale(
		resolved_camera,
	)
	if err := wgpu_ensure_post_targets(
		renderer,
		width,
		height,
		depth_view,
		ambient_occlusion_resolution_scale,
		fog.resolution_scale,
	); err != "" {
		return err
	}
	if err := wgpu_encode_water_surface_query(
		renderer,
		encoder,
		registry,
		water,
		renderer.render_list.camera.transform.position,
	); err != "" {
		return err
	}
	debug_view := resolved_camera.debug_view != .Lit
	if debug_view {
		resolved_camera.automatic_exposure = false
		resolved_camera.temporal_antialiasing = false
		resolved_camera.fast_antialiasing = false
		resolved_camera.ambient_occlusion = false
		resolved_camera.screen_space_reflections = false
		resolved_camera.bloom = false
		water.enabled = false
		water.submersion = 0
	}
	// The CPU broad phase only chooses a candidate volume. It must not classify
	// the camera against the owner's mean Transform plane: the GPU surface query
	// below is the authority for air/water crossings on an animated surface.
	// Candidate changes still reject history because their optical coefficients
	// and surface query owner may change discontinuously.
	water_candidate_active := water.enabled
	if renderer.water_candidate_active != water_candidate_active ||
	   (water_candidate_active && renderer.water_candidate_entity_index != water.entity_index) {
		renderer.temporal_history_valid = false
		renderer.volumetric_fog_history_valid = false
	}
	renderer.water_candidate_active = water_candidate_active
	renderer.water_candidate_entity_index = water.entity_index
	if water.enabled {
		// Exact air/water medium selection happens in the temporal shader from the
		// custom surface query. Keep authored air fog available to that per-frame
		// classification instead of suppressing it from the mean plane here.
	}
	temporal_output_index := renderer.temporal_output_index
	ambient_occlusion_width := wgpu_post_scaled_dimension(
		width,
		ambient_occlusion_resolution_scale,
	)
	ambient_occlusion_height := wgpu_post_scaled_dimension(
		height,
		ambient_occlusion_resolution_scale,
	)
	volumetric_fog_width := wgpu_post_scaled_dimension(width, fog.resolution_scale)
	volumetric_fog_height := wgpu_post_scaled_dimension(height, fog.resolution_scale)
	projection := renderer.gpu_cluster_uniform.projection
	viewport := renderer.gpu_cluster_uniform.viewport
	history_valid := f32(0)
	if renderer.temporal_history_valid {
		history_valid = 1
	}
	if resolved_camera.ambient_occlusion {
		ambient_occlusion_uniform := WGPU_Ambient_Occlusion_Uniform {
			projection = {projection[0], projection[5], projection[10], projection[14]},
			viewport = viewport,
			dimensions = {f32(width), f32(height), projection[8], projection[9]},
			parameters = {
				WGPU_VISIBILITY_AO_RADIUS,
				WGPU_VISIBILITY_AO_POWER,
				WGPU_VISIBILITY_AO_STRENGTH,
				shared.camera_ambient_occlusion_quality(resolved_camera),
			},
			visibility_parameters = {WGPU_VISIBILITY_AO_THICKNESS, 0, 0, 0},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.ambient_occlusion_uniform_buffer,
			0,
			&ambient_occlusion_uniform,
			size_of(ambient_occlusion_uniform),
		)
		ambient_occlusion_timestamps, ambient_occlusion_timestamps_enabled :=
			wgpu_gpu_pass_timestamps(renderer, .Ambient_Occlusion)
		ambient_occlusion_timestamps_ptr: ^wgpu.PassTimestampWrites
		if ambient_occlusion_timestamps_enabled {
			ambient_occlusion_timestamps_ptr = &ambient_occlusion_timestamps
		}
		ambient_occlusion_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Ambient Occlusion Compute Pass",
				timestampWrites = ambient_occlusion_timestamps_ptr,
			},
		)
		if ambient_occlusion_pass == nil {
			return "failed to begin ambient occlusion compute pass"
		}
		ambient_occlusion_pipelines := [?]wgpu.ComputePipeline {
			renderer.ambient_occlusion_pipeline,
			renderer.ambient_occlusion_blur_horizontal_pipeline,
			renderer.ambient_occlusion_blur_vertical_pipeline,
		}
		for pipeline, index in ambient_occlusion_pipelines {
			wgpu.ComputePassEncoderSetPipeline(ambient_occlusion_pass, pipeline)
			wgpu.ComputePassEncoderSetBindGroup(
				ambient_occlusion_pass,
				0,
				renderer.ambient_occlusion_bind_groups[index],
			)
			wgpu.ComputePassEncoderDispatchWorkgroups(
				ambient_occlusion_pass,
				(ambient_occlusion_width + 7) / 8,
				(ambient_occlusion_height + 7) / 8,
				1,
			)
		}
		wgpu.ComputePassEncoderEnd(ambient_occlusion_pass)
		wgpu.ComputePassEncoderRelease(ambient_occlusion_pass)
	}
	if resolved_camera.screen_space_reflections {
		reflection_sample_count := shared.camera_screen_space_reflections_sample_count(
			resolved_camera,
		)
		reflections_uniform := WGPU_Screen_Space_Reflections_Uniform {
			projection = {projection[0], projection[5], projection[10], projection[14]},
			viewport = viewport,
			parameters = {40.0, 0.08, 0.10, 0.65},
			_padding = {
				projection[8],
				projection[9],
				f32(reflection_sample_count),
				shared.camera_screen_space_reflections_stride_scale(resolved_camera),
			},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.screen_space_reflections_uniform_buffer,
			0,
			&reflections_uniform,
			size_of(reflections_uniform),
		)
		reflections_timestamps, reflections_timestamps_enabled := wgpu_gpu_pass_timestamps(
			renderer,
			.Screen_Space_Reflections,
		)
		reflections_timestamps_ptr: ^wgpu.PassTimestampWrites
		if reflections_timestamps_enabled {
			reflections_timestamps_ptr = &reflections_timestamps
		}
		reflections_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Screen-Space Reflections Compute Pass",
				timestampWrites = reflections_timestamps_ptr,
			},
		)
		if reflections_pass == nil {
			return "failed to begin screen-space reflections compute pass"
		}
		wgpu.ComputePassEncoderSetPipeline(
			reflections_pass,
			renderer.screen_space_reflections_pipeline,
		)
		wgpu.ComputePassEncoderSetBindGroup(
			reflections_pass,
			0,
			renderer.screen_space_reflections_bind_group,
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(
			reflections_pass,
			(width + 7) / 8,
			(height + 7) / 8,
			1,
		)
		wgpu.ComputePassEncoderEnd(reflections_pass)
		wgpu.ComputePassEncoderRelease(reflections_pass)
	}
	temporal_uniform := WGPU_Temporal_AA_Uniform {
		previous_view_projection = renderer.temporal_previous_view_projection,
		inverse_view = renderer.temporal_inverse_view,
		projection = renderer.temporal_current_projection,
		previous_projection = renderer.temporal_previous_projection,
		viewport = viewport,
		parameters = {projection[8], projection[9], history_valid, 0.995},
		features = {
			1 if resolved_camera.temporal_antialiasing else 0,
			1 if resolved_camera.fast_antialiasing else 0,
			1 if resolved_camera.ambient_occlusion else 0,
			1 if resolved_camera.bloom else 0,
		},
		reflections = {
			1 if resolved_camera.screen_space_reflections else 0,
			f32(renderer.temporal_sample_index % 256),
			1 if renderer.volumetric_fog_history_valid else 0,
			f32(renderer.temporal_sample_index % 8),
		},
	}
	if render_feature_overrides.disable_volumetric_fog || debug_view {
		fog.density = 0
	}
	temporal_uniform.fog_color_density = {fog.color.x, fog.color.y, fog.color.z, fog.density}
	temporal_uniform.fog_height_distance = {
		fog.height,
		fog.height_falloff,
		fog.max_distance,
		fog.anisotropy,
	}
	temporal_uniform.fog_lighting = {
		fog.ambient_intensity,
		fog.light_intensity,
		fog.point_light_intensity,
		max(f32(16), f32(64) * adaptive_post_quality),
	}
	temporal_uniform.water_surface = {
		water.surface_height,
		water.max_distance,
		water.submersion,
		1 if water.enabled else 0,
	}
	temporal_uniform.water_absorption = {
		water.absorption.x,
		water.absorption.y,
		water.absorption.z,
		0,
	}
	temporal_uniform.water_scattering = {
		water.scattering.x,
		water.scattering.y,
		water.scattering.z,
		water.ambient_intensity,
	}
	temporal_uniform.water_optics = {
		water.distortion,
		water.distortion_scale,
		f32(math.mod(renderer.custom_shader_time.elapsed_time, 4096)) * water.distortion_speed,
		water.anisotropy,
	}
	temporal_uniform.water_caustics = {
		water.caustics_intensity,
		water.caustics_scale,
		f32(math.mod(renderer.custom_shader_time.elapsed_time, 4096)) * water.caustics_speed,
		water.caustics_max_depth,
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.temporal_aa_uniform_buffer,
		0,
		&temporal_uniform,
		size_of(temporal_uniform),
	)
	if fog.density > 0 {
		volumetric_fog_timestamps, volumetric_fog_timestamps_enabled := wgpu_gpu_pass_timestamps(
			renderer,
			.Volumetric_Fog,
		)
		volumetric_fog_timestamps_ptr: ^wgpu.PassTimestampWrites
		if volumetric_fog_timestamps_enabled {
			volumetric_fog_timestamps_ptr = &volumetric_fog_timestamps
		}
		volumetric_fog_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Volumetric Fog Compute Pass",
				timestampWrites = volumetric_fog_timestamps_ptr,
			},
		)
		if volumetric_fog_pass == nil {
			return "failed to begin volumetric fog compute pass"
		}
		wgpu.ComputePassEncoderSetPipeline(volumetric_fog_pass, renderer.volumetric_fog_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(
			volumetric_fog_pass,
			0,
			renderer.volumetric_fog_bind_groups[temporal_output_index],
		)
		wgpu.ComputePassEncoderSetBindGroup(
			volumetric_fog_pass,
			1,
			renderer.gpu_cluster_bind_group,
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(
			volumetric_fog_pass,
			(volumetric_fog_width + 7) / 8,
			(volumetric_fog_height + 7) / 8,
			1,
		)
		wgpu.ComputePassEncoderEnd(volumetric_fog_pass)
		wgpu.ComputePassEncoderRelease(volumetric_fog_pass)
	}
	temporal_timestamps, temporal_timestamps_enabled := wgpu_gpu_pass_timestamps(
		renderer,
		.Temporal_AA,
	)
	temporal_timestamps_ptr: ^wgpu.PassTimestampWrites
	if temporal_timestamps_enabled {
		temporal_timestamps_ptr = &temporal_timestamps
	}
	temporal_pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot Temporal AA Compute Pass",
			timestampWrites = temporal_timestamps_ptr,
		},
	)
	if temporal_pass == nil {
		return "failed to begin temporal AA compute pass"
	}
	wgpu.ComputePassEncoderSetPipeline(temporal_pass, renderer.temporal_aa_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(
		temporal_pass,
		0,
		renderer.temporal_aa_bind_groups[temporal_output_index],
	)
	wgpu.ComputePassEncoderSetBindGroup(temporal_pass, 1, renderer.gpu_cluster_bind_group)
	wgpu.ComputePassEncoderDispatchWorkgroups(temporal_pass, (width + 7) / 8, (height + 7) / 8, 1)
	wgpu.ComputePassEncoderEnd(temporal_pass)
	wgpu.ComputePassEncoderRelease(temporal_pass)
	if resolved_camera.automatic_exposure {
		automatic_exposure_settings := WGPU_Automatic_Exposure_Settings {
			viewport = viewport,
			parameters = {
				shared.camera_automatic_exposure_min(resolved_camera),
				shared.camera_automatic_exposure_max(resolved_camera),
				shared.camera_automatic_exposure_speed(resolved_camera),
				clamp(delta_time, f32(0), f32(0.25)),
			},
			control = {
				1,
				shared.camera_exposure(resolved_camera),
				1 if !renderer.automatic_exposure_valid else 0,
				0.18,
			},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.automatic_exposure_settings_buffer,
			0,
			&automatic_exposure_settings,
			size_of(automatic_exposure_settings),
		)
		automatic_exposure_timestamps, automatic_exposure_timestamps_enabled :=
			wgpu_gpu_pass_timestamps(renderer, .Automatic_Exposure)
		automatic_exposure_timestamps_ptr: ^wgpu.PassTimestampWrites
		if automatic_exposure_timestamps_enabled {
			automatic_exposure_timestamps_ptr = &automatic_exposure_timestamps
		}
		automatic_exposure_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Automatic Exposure Compute Pass",
				timestampWrites = automatic_exposure_timestamps_ptr,
			},
		)
		if automatic_exposure_pass == nil {
			return "failed to begin automatic exposure compute pass"
		}
		wgpu.ComputePassEncoderSetPipeline(
			automatic_exposure_pass,
			renderer.automatic_exposure_pipeline,
		)
		wgpu.ComputePassEncoderSetBindGroup(
			automatic_exposure_pass,
			0,
			renderer.automatic_exposure_bind_groups[temporal_output_index],
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(automatic_exposure_pass, 1, 1, 1)
		wgpu.ComputePassEncoderEnd(automatic_exposure_pass)
		wgpu.ComputePassEncoderRelease(automatic_exposure_pass)
		renderer.automatic_exposure_valid = true
		renderer.automatic_exposure_enabled = true
		renderer.automatic_exposure_debug_view = false
	} else if renderer.automatic_exposure_enabled ||
	   !renderer.automatic_exposure_valid ||
	   renderer.automatic_exposure_debug_view != debug_view {
		manual_exposure := WGPU_Automatic_Exposure_State {
			values = {1, 1, 1, 2 if debug_view else 1},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.automatic_exposure_state_buffer,
			0,
			&manual_exposure,
			size_of(manual_exposure),
		)
		renderer.automatic_exposure_valid = true
		renderer.automatic_exposure_enabled = false
		renderer.automatic_exposure_debug_view = debug_view
	}

	if resolved_camera.bloom {
		bloom_timestamps, bloom_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Bloom)
		bloom_timestamps_ptr: ^wgpu.PassTimestampWrites
		if bloom_timestamps_enabled {
			bloom_timestamps_ptr = &bloom_timestamps
		}
		pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Bloom Compute Pass",
				timestampWrites = bloom_timestamps_ptr,
			},
		)
		if pass == nil {
			return "failed to begin bloom compute pass"
		}
		for index in 0 ..< WGPU_BLOOM_LEVELS {
			pipeline := renderer.bloom_downsample_pipeline
			if index == 0 {
				pipeline = renderer.bloom_bright_pipeline
			}
			level_width := max(u32(1), width >> u32(index + 1))
			level_height := max(u32(1), height >> u32(index + 1))
			wgpu.ComputePassEncoderSetPipeline(pass, pipeline)
			wgpu.ComputePassEncoderSetBindGroup(
				pass,
				0,
				renderer.bloom_compute_bind_groups[temporal_output_index][index],
			)
			wgpu.ComputePassEncoderDispatchWorkgroups(
				pass,
				(level_width + 7) / 8,
				(level_height + 7) / 8,
				1,
			)
		}
		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}
	vignette := wgpu_vignette_settings(world)
	lens_flare := wgpu_lens_flare_settings(world)
	lens_dirt := wgpu_lens_dirt_settings(world)
	if debug_view {
		vignette.intensity = 0
		lens_flare.intensity = 0
		lens_dirt.intensity = 0
	}
	if !resolved_camera.bloom {
		lens_flare.intensity = 0
		lens_dirt.intensity = 0
	}
	post_effects_uniform := WGPU_Post_Effects_Uniform {
		vignette_color_intensity = {
			vignette.color.x,
			vignette.color.y,
			vignette.color.z,
			vignette.intensity,
		},
		vignette_center_shape = {
			vignette.center.x,
			vignette.center.y,
			vignette.smoothness,
			vignette.roundness,
		},
		flare_tint_intensity = {
			lens_flare.tint.x,
			lens_flare.tint.y,
			lens_flare.tint.z,
			lens_flare.intensity,
		},
		flare_ghosts = {
			lens_flare.threshold,
			lens_flare.ghost_count,
			lens_flare.ghost_spacing,
			adaptive_post_quality,
		},
		flare_optics = {
			lens_flare.halo_intensity,
			lens_flare.halo_radius,
			lens_flare.chromatic_aberration,
			0,
		},
		dirt_tint_intensity = {
			lens_dirt.tint.x,
			lens_dirt.tint.y,
			lens_dirt.tint.z,
			lens_dirt.intensity,
		},
		dirt_parameters = {lens_dirt.scale, lens_dirt.contrast, lens_dirt.seed, 0},
		editor_feedback = wgpu_editor_selection_outline_uniform(
			engine_elapsed_time,
			animate_selection_outline,
		),
	}
	if wgpu_store_post_effects_uniform(renderer, post_effects_uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.post_effects_uniform_buffer,
			0,
			&post_effects_uniform,
			size_of(post_effects_uniform),
		)
	}
	err := wgpu_encode_fullscreen_pass(
		renderer,
		encoder,
		output_view,
		renderer.composite_pipeline,
		renderer.composite_bind_groups[temporal_output_index],
		"Scrapbot HDR Composite Pass",
		.Composite,
		output_width,
		output_height,
		output_viewport,
	)
	if err != "" {
		return err
	}
	renderer.temporal_previous_view_projection = renderer.temporal_current_view_projection
	renderer.temporal_previous_projection = renderer.temporal_current_projection
	renderer.temporal_history_valid = resolved_camera.temporal_antialiasing
	renderer.volumetric_fog_history_valid =
		resolved_camera.temporal_antialiasing && fog.density > 0
	renderer.temporal_output_index = 1 - temporal_output_index
	if resolved_camera.temporal_antialiasing {
		renderer.temporal_sample_index += 1
	} else {
		renderer.temporal_sample_index = 0
	}
	return ""
}
