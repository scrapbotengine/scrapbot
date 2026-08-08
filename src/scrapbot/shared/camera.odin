package shared

import "core:math"

render_debug_view_name :: proc "contextless" (view: Render_Debug_View) -> string {
	switch view {
		case .Lit:
			return "lit"
		case .Base_Color:
			return "base_color"
		case .World_Normals:
			return "world_normals"
		case .Roughness:
			return "roughness"
		case .Metallic:
			return "metallic"
		case .Depth:
			return "depth"
		case .Meshlets:
			return "meshlets"
		case .LOD:
			return "lod"
		case .Meshlet_Visibility:
			return "meshlet_visibility"
		case .HiZ:
			return "hiz"
		case .Occlusion_Queries:
			return "occlusion_queries"
		case .Virtual_Geometry:
			return "virtual_geometry"
		case .Distance_Field:
			return "distance_field"
	}
	return "lit"
}

render_debug_view_from_name :: proc "contextless" (name: string) -> (Render_Debug_View, bool) {
	switch name {
		case "lit":
			return .Lit, true
		case "base_color":
			return .Base_Color, true
		case "world_normals":
			return .World_Normals, true
		case "roughness":
			return .Roughness, true
		case "metallic":
			return .Metallic, true
		case "depth":
			return .Depth, true
		case "meshlets":
			return .Meshlets, true
		case "lod":
			return .LOD, true
		case "meshlet_visibility":
			return .Meshlet_Visibility, true
		case "hiz":
			return .HiZ, true
		case "occlusion_queries":
			return .Occlusion_Queries, true
		case "virtual_geometry":
			return .Virtual_Geometry, true
		case "distance_field":
			return .Distance_Field, true
	}
	return .Lit, false
}

camera_defaults :: proc "contextless" () -> Camera_Component {
	return {
		fov = 60,
		near = 0.1,
		far = 1000,
		resolution_scale = 1,
		dynamic_resolution_min_scale = 0.5,
		dynamic_resolution_target_ms = 16.667,
		adaptive_quality_minimum = 0.25,
		exposure = 1,
		automatic_exposure_min = 0.125,
		automatic_exposure_max = 8,
		automatic_exposure_speed = 2,
		temporal_antialiasing = true,
		ambient_occlusion = true,
		ambient_occlusion_quality = 0.5,
		ambient_occlusion_resolution_scale = 0.25,
		screen_space_reflections = false,
		screen_space_reflections_quality = 0.5,
		bloom = true,
	}
}

camera_copy_render_features :: proc "contextless" (
	destination: ^Camera_Component,
	source: Camera_Component,
) {
	if destination == nil {
		return
	}
	destination.resolution_scale = source.resolution_scale
	destination.debug_view = source.debug_view
	destination.debug_hiz_mip = source.debug_hiz_mip
	destination.debug_occlusion_freeze = source.debug_occlusion_freeze
	destination.dynamic_resolution = source.dynamic_resolution
	destination.dynamic_resolution_min_scale = source.dynamic_resolution_min_scale
	destination.dynamic_resolution_target_ms = source.dynamic_resolution_target_ms
	destination.adaptive_quality_minimum = source.adaptive_quality_minimum
	destination.exposure = source.exposure
	destination.automatic_exposure = source.automatic_exposure
	destination.automatic_exposure_min = source.automatic_exposure_min
	destination.automatic_exposure_max = source.automatic_exposure_max
	destination.automatic_exposure_speed = source.automatic_exposure_speed
	destination.temporal_antialiasing = source.temporal_antialiasing
	destination.fast_antialiasing = source.fast_antialiasing
	destination.ambient_occlusion = source.ambient_occlusion
	destination.ambient_occlusion_quality = source.ambient_occlusion_quality
	destination.ambient_occlusion_resolution_scale = source.ambient_occlusion_resolution_scale
	destination.screen_space_reflections = source.screen_space_reflections
	destination.screen_space_reflections_quality = source.screen_space_reflections_quality
	destination.bloom = source.bloom
}

camera_debug_hiz_mip :: proc "contextless" (camera: Camera_Component) -> u32 {
	if math.is_nan(camera.debug_hiz_mip) || math.is_inf(camera.debug_hiz_mip) {
		return 0
	}
	return u32(math.floor(clamp(camera.debug_hiz_mip, 0, 15)))
}

hiz_occlusion_status_name :: proc "contextless" (status: HiZ_Occlusion_Status) -> string {
	switch status {
		case .Below_Threshold:
			return "BELOW THRESHOLD"
		case .Scene_Changed:
			return "SCENE CHANGED"
		case .Camera_Changed:
			return "CAMERA MOVED"
		case .Warming_Up:
			return "WARMING UP"
		case .Active:
			return "ACTIVE"
		case .Unavailable:
	}
	return "UNAVAILABLE"
}

camera_resolution_scale :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.resolution_scale == 0 {
		return 1
	}
	return clamp(camera.resolution_scale, 0.5, 1)
}

camera_dynamic_resolution_min_scale :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.dynamic_resolution_min_scale == 0 {
		return 0.5
	}
	return clamp(camera.dynamic_resolution_min_scale, 0.5, camera_resolution_scale(camera))
}

camera_dynamic_resolution_target_ms :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.dynamic_resolution_target_ms == 0 {
		return 16.667
	}
	return clamp(camera.dynamic_resolution_target_ms, 1, 100)
}

camera_adaptive_quality_minimum :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.adaptive_quality_minimum == 0 {
		return 0.25
	}
	return clamp(camera.adaptive_quality_minimum, 0.25, 1)
}

camera_exposure :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.exposure == 0 {
		return 1
	}
	return camera.exposure
}

camera_automatic_exposure_min :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.automatic_exposure_min <= 0 {
		return 0.125
	}
	return camera.automatic_exposure_min
}

camera_automatic_exposure_max :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.automatic_exposure_max <= 0 {
		return 8
	}
	return camera.automatic_exposure_max
}

camera_automatic_exposure_speed :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.automatic_exposure_speed <= 0 {
		return 2
	}
	return camera.automatic_exposure_speed
}

camera_ambient_occlusion_quality :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.ambient_occlusion_quality <= 0 {
		return 0.5
	}
	return clamp(camera.ambient_occlusion_quality, 0.25, 1)
}

camera_ambient_occlusion_resolution_scale :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.ambient_occlusion_resolution_scale <= 0 {
		return 0.25
	}
	return clamp(camera.ambient_occlusion_resolution_scale, 0.25, 1)
}

camera_ambient_occlusion_sample_count :: proc "contextless" (camera: Camera_Component) -> u32 {
	quality := camera_ambient_occlusion_quality(camera)
	if quality < 0.375 {
		return 8
	}
	if quality < 0.625 {
		return 16
	}
	if quality < 0.875 {
		return 24
	}
	return 36
}

camera_screen_space_reflections_quality :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.screen_space_reflections_quality <= 0 {
		return 0.5
	}
	return clamp(camera.screen_space_reflections_quality, 0.25, 1)
}

camera_screen_space_reflections_sample_count :: proc "contextless" (
	camera: Camera_Component,
) -> u32 {
	quality := camera_screen_space_reflections_quality(camera)
	if quality < 0.375 {
		return 16
	}
	if quality < 0.625 {
		return 32
	}
	if quality < 0.875 {
		return 48
	}
	return 64
}

camera_screen_space_reflections_stride_scale :: proc "contextless" (
	camera: Camera_Component,
) -> f32 {
	sample_count := f32(camera_screen_space_reflections_sample_count(camera))
	high_quality_distance := f32(2 + 64) + 0.035 * f32(64 * 63) * 0.5
	tier_distance := 2 + sample_count + 0.035 * sample_count * (sample_count - 1) * 0.5
	return high_quality_distance / tier_distance
}

camera_forward :: proc(rotation: Vec3) -> Vec3 {
	cos_pitch := math.cos(rotation.x)
	return {
		math.sin(rotation.y) * cos_pitch,
		math.sin(rotation.x),
		-math.cos(rotation.y) * cos_pitch,
	}
}

camera_right :: proc(rotation: Vec3) -> Vec3 {
	forward := camera_forward(rotation)
	base_right := camera_vec3_normalize(camera_vec3_cross(forward, {0, 1, 0}))
	base_up := camera_vec3_cross(base_right, forward)
	cos_roll, sin_roll := math.cos(rotation.z), math.sin(rotation.z)
	return camera_vec3_normalize(
		camera_vec3_add(camera_vec3_mul(base_right, cos_roll), camera_vec3_mul(base_up, sin_roll)),
	)
}

camera_up :: proc(rotation: Vec3) -> Vec3 {
	return camera_vec3_cross(camera_right(rotation), camera_forward(rotation))
}

camera_vec3_add :: proc(a, b: Vec3) -> Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

camera_vec3_mul :: proc(value: Vec3, scalar: f32) -> Vec3 {
	return {value.x * scalar, value.y * scalar, value.z * scalar}
}

camera_vec3_cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

camera_vec3_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

camera_vec3_normalize :: proc(value: Vec3) -> Vec3 {
	length := math.sqrt(camera_vec3_dot(value, value))
	if length <= 0.000001 {
		return {}
	}
	return {value.x / length, value.y / length, value.z / length}
}
