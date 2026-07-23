package render

WGPU_GPU_TRANSFORM_SHADER :: `
struct GPU_Instance_Transform {
	position: vec4<f32>,
	rotation: vec4<f32>,
	scale: vec4<f32>,
	local_bounds: vec4<f32>,
};

struct GPU_Instance {
	model: mat4x4<f32>,
	normal_model: mat4x4<f32>,
	color: vec4<f32>,
	emissive: vec4<f32>,
	shadow_flags: vec4<f32>,
	bounds: vec4<f32>,
	batch_indices: array<u32, 4>,
	lod_screen_radii: array<f32, 4>,
	lod_count: u32,
	enabled: u32,
	padding: vec2<u32>,
};

@group(0) @binding(0) var<storage, read> transform_updates: array<GPU_Instance_Transform>;
@group(0) @binding(1) var<storage, read_write> instances: array<GPU_Instance>;

fn rotation_x(angle: f32) -> mat4x4<f32> {
	let c = cos(angle);
	let s = sin(angle);
	return mat4x4<f32>(
		vec4<f32>(1.0, 0.0, 0.0, 0.0),
		vec4<f32>(0.0, c, s, 0.0),
		vec4<f32>(0.0, -s, c, 0.0),
		vec4<f32>(0.0, 0.0, 0.0, 1.0)
	);
}

fn rotation_y(angle: f32) -> mat4x4<f32> {
	let c = cos(angle);
	let s = sin(angle);
	return mat4x4<f32>(
		vec4<f32>(c, 0.0, -s, 0.0),
		vec4<f32>(0.0, 1.0, 0.0, 0.0),
		vec4<f32>(s, 0.0, c, 0.0),
		vec4<f32>(0.0, 0.0, 0.0, 1.0)
	);
}

fn rotation_z(angle: f32) -> mat4x4<f32> {
	let c = cos(angle);
	let s = sin(angle);
	return mat4x4<f32>(
		vec4<f32>(c, s, 0.0, 0.0),
		vec4<f32>(-s, c, 0.0, 0.0),
		vec4<f32>(0.0, 0.0, 1.0, 0.0),
		vec4<f32>(0.0, 0.0, 0.0, 1.0)
	);
}

fn scale_matrix(value: vec3<f32>) -> mat4x4<f32> {
	return mat4x4<f32>(
		vec4<f32>(value.x, 0.0, 0.0, 0.0),
		vec4<f32>(0.0, value.y, 0.0, 0.0),
		vec4<f32>(0.0, 0.0, value.z, 0.0),
		vec4<f32>(0.0, 0.0, 0.0, 1.0)
	);
}

@compute @workgroup_size(64)
fn expand_transforms(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let update_count = u32(transform_updates[0].position.w);
	if (invocation.x >= update_count) {
		return;
	}
	let transform = transform_updates[invocation.x + 1u];
	let slot = u32(transform.position.w);
	let rotation = rotation_z(transform.rotation.z) *
		rotation_y(transform.rotation.y) *
		rotation_x(transform.rotation.x);
	let translation = mat4x4<f32>(
		vec4<f32>(1.0, 0.0, 0.0, 0.0),
		vec4<f32>(0.0, 1.0, 0.0, 0.0),
		vec4<f32>(0.0, 0.0, 1.0, 0.0),
		vec4<f32>(transform.position.xyz, 1.0)
	);
	let model = translation * rotation * scale_matrix(transform.scale.xyz);
	var inverse_scale = vec3<f32>(0.0);
	if (abs(transform.scale.x) > 0.000001) {
		inverse_scale.x = 1.0 / transform.scale.x;
	}
	if (abs(transform.scale.y) > 0.000001) {
		inverse_scale.y = 1.0 / transform.scale.y;
	}
	if (abs(transform.scale.z) > 0.000001) {
		inverse_scale.z = 1.0 / transform.scale.z;
	}
	let local_center = vec4<f32>(transform.local_bounds.xyz, 1.0);
	let world_center = model * local_center;
	let world_radius = transform.local_bounds.w * max(
		max(abs(transform.scale.x), abs(transform.scale.y)),
		abs(transform.scale.z)
	);
	instances[slot].model = model;
	instances[slot].normal_model = rotation * scale_matrix(inverse_scale);
	instances[slot].bounds = vec4<f32>(world_center.xyz, world_radius);
}
`

WGPU_GPU_DRIVEN_SHADER :: `
struct Render_Uniform {
	view_projection: mat4x4<f32>,
	view: mat4x4<f32>,
	shadow_view_projections: array<mat4x4<f32>, 4>,
	ambient: vec4<f32>,
	directional_direction_intensity: array<vec4<f32>, 4>,
	directional_color: array<vec4<f32>, 4>,
	light_counts: vec4<u32>,
	camera_position: vec4<f32>,
	shadow_cascade_splits: vec4<f32>,
};

struct Point_Light {
	position_range: vec4<f32>,
	color_intensity: vec4<f32>,
};

struct Cluster_Uniform {
	view: mat4x4<f32>,
	projection: mat4x4<f32>,
	viewport: vec4<f32>,
	z_parameters: vec4<f32>,
	counts: vec4<u32>,
};

struct Shadow_Cascade_Uniform {
	index: u32,
	padding_0: u32,
	padding_1: u32,
	padding_2: u32,
};

struct Material_Uniform {
	pbr_factors: vec4<f32>,
	flags: vec4<f32>,
	alpha: vec4<f32>,
};

struct Environment_Uniform {
	intensity: f32,
	rotation: f32,
	exposure: f32,
	enabled: f32,
	max_specular_lod: f32,
	background_intensity: f32,
	background_rotation: f32,
	background_exposure: f32,
	background_blur: f32,
	background_enabled: f32,
	background_max_specular_lod: f32,
	_padding: f32,
	sun_direction_intensity: vec4<f32>,
	sun_color: vec4<f32>,
	atmosphere_sky_tint: vec4<f32>,
	atmosphere_ground_color: vec4<f32>,
	atmosphere_parameters: vec4<f32>,
	atmosphere_sun: vec4<f32>,
};

struct GPU_Instance {
	model: mat4x4<f32>,
	normal_model: mat4x4<f32>,
	color: vec4<f32>,
	emissive: vec4<f32>,
	shadow_flags: vec4<f32>,
	bounds: vec4<f32>,
	batch_indices: array<u32, 4>,
	lod_screen_radii: array<f32, 4>,
	lod_count: u32,
	enabled: u32,
	padding: vec2<u32>,
};

@group(0) @binding(0) var<uniform> render: Render_Uniform;
@group(0) @binding(1) var shadow_map: texture_depth_2d_array;
@group(0) @binding(2) var shadow_sampler: sampler_comparison;
@group(0) @binding(3) var<storage, read> instances: array<GPU_Instance>;
@group(0) @binding(4) var<storage, read> visible_instances: array<u32>;
@group(0) @binding(5) var<storage, read> point_lights: array<Point_Light>;
@group(0) @binding(6) var<storage, read> cluster_light_counts: array<u32>;
@group(0) @binding(7) var<storage, read> cluster_light_indices: array<u32>;
@group(0) @binding(8) var<uniform> cluster: Cluster_Uniform;
@group(0) @binding(9) var<uniform> shadow_cascade: Shadow_Cascade_Uniform;
@group(1) @binding(0) var base_color_texture: texture_2d<f32>;
@group(1) @binding(1) var base_color_sampler: sampler;
@group(1) @binding(2) var metallic_roughness_texture: texture_2d<f32>;
@group(1) @binding(3) var normal_texture: texture_2d<f32>;
@group(1) @binding(4) var occlusion_texture: texture_2d<f32>;
@group(1) @binding(5) var emissive_texture: texture_2d<f32>;
@group(1) @binding(6) var<uniform> material: Material_Uniform;
@group(1) @binding(7) var metallic_roughness_sampler: sampler;
@group(1) @binding(8) var normal_sampler: sampler;
@group(1) @binding(9) var occlusion_sampler: sampler;
@group(1) @binding(10) var emissive_sampler: sampler;
@group(2) @binding(0) var irradiance_cube: texture_cube<f32>;
@group(2) @binding(1) var specular_cube: texture_cube<f32>;
@group(2) @binding(2) var environment_sampler: sampler;
@group(2) @binding(3) var<uniform> environment: Environment_Uniform;

struct Vertex_Input {
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
};

struct Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) color: vec4<f32>,
	@location(1) world_position: vec3<f32>,
	@location(2) world_normal: vec3<f32>,
	@location(3) view_depth: f32,
	@location(4) shadow_receiver: f32,
	@location(5) uv: vec2<f32>,
	@location(6) emissive: vec3<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Vertex_Output {
	let instance = instances[visible_instances[visible_index]];
	var output: Vertex_Output;
	let local_position = vec4<f32>(input.position, 1.0);
	output.position = render.view_projection * instance.model * local_position;
	output.world_position = (instance.model * local_position).xyz;
	output.world_normal = normalize((instance.normal_model * vec4<f32>(input.normal, 0.0)).xyz);
	output.color = instance.color;
	output.emissive = instance.emissive.rgb;
	output.view_depth = -(render.view * instance.model * local_position).z;
	output.shadow_receiver = instance.shadow_flags.y;
	output.uv = input.uv;
	return output;
}

const PI: f32 = 3.14159265359;

fn fresnel_schlick(cos_theta: f32, f0: vec3<f32>) -> vec3<f32> {
	return f0 + (vec3<f32>(1.0) - f0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

fn fresnel_schlick_roughness(cos_theta: f32, f0: vec3<f32>, roughness: f32) -> vec3<f32> {
	return f0 + (max(vec3<f32>(1.0 - roughness), f0) - f0) *
		pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

fn rotate_environment(direction: vec3<f32>) -> vec3<f32> {
	let c = cos(environment.rotation);
	let s = sin(environment.rotation);
	return vec3<f32>(c * direction.x - s * direction.z, direction.y, s * direction.x + c * direction.z);
}

fn environment_brdf(n_dot_v: f32, roughness: f32) -> vec2<f32> {
	let c0 = vec4<f32>(-1.0, -0.0275, -0.572, 0.022);
	let c1 = vec4<f32>(1.0, 0.0425, 1.04, -0.04);
	let r = roughness * c0 + c1;
	let a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
	return vec2<f32>(-1.04, 1.04) * a004 + r.zw;
}

fn distribution_ggx(normal: vec3<f32>, halfway: vec3<f32>, roughness: f32) -> f32 {
	let a = roughness * roughness;
	let a2 = a * a;
	let n_dot_h = max(dot(normal, halfway), 0.0);
	let denominator = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	return a2 / max(PI * denominator * denominator, 0.000001);
}

fn geometry_schlick_ggx(n_dot_v: f32, roughness: f32) -> f32 {
	let r = roughness + 1.0;
	let k = r * r / 8.0;
	return n_dot_v / max(n_dot_v * (1.0 - k) + k, 0.000001);
}

fn geometry_smith(normal: vec3<f32>, view: vec3<f32>, light: vec3<f32>, roughness: f32) -> f32 {
	return geometry_schlick_ggx(max(dot(normal, view), 0.0), roughness) *
		geometry_schlick_ggx(max(dot(normal, light), 0.0), roughness);
}

fn mapped_normal(input: Vertex_Output, front_facing: bool) -> vec3<f32> {
	let geometric = normalize(input.world_normal);
	let flip = material.flags.w > 0.5 && !front_facing;
	var sampled = textureSample(normal_texture, normal_sampler, input.uv).xyz * 2.0 - 1.0;
	sampled = normalize(vec3<f32>(sampled.xy * material.pbr_factors.z, sampled.z));
	let position_dx = dpdx(input.world_position);
	let position_dy = dpdy(input.world_position);
	let uv_dx = dpdx(input.uv);
	let uv_dy = dpdy(input.uv);
	let determinant = uv_dx.x * uv_dy.y - uv_dx.y * uv_dy.x;
	if (abs(determinant) < 0.000001) {
		return select(geometric, -geometric, flip);
	}
	let tangent = normalize((position_dx * uv_dy.y - position_dy * uv_dx.y) / determinant);
	let bitangent = normalize((-position_dx * uv_dy.x + position_dy * uv_dx.x) / determinant);
	let mapped = normalize(mat3x3<f32>(tangent, bitangent, geometric) * sampled);
	return select(mapped, -mapped, flip);
}

fn evaluate_light(
	normal: vec3<f32>,
	view: vec3<f32>,
	light: vec3<f32>,
	radiance: vec3<f32>,
	base_color: vec3<f32>,
	metallic: f32,
	roughness: f32,
	f0: vec3<f32>,
) -> vec3<f32> {
	let halfway = normalize(view + light);
	let fresnel = fresnel_schlick(max(dot(halfway, view), 0.0), f0);
	let distribution = distribution_ggx(normal, halfway, roughness);
	let geometry = geometry_smith(normal, view, light, roughness);
	let denominator = max(4.0 * max(dot(normal, view), 0.0) * max(dot(normal, light), 0.0), 0.0001);
	let specular = distribution * geometry * fresnel / denominator;
	let diffuse_weight = (vec3<f32>(1.0) - fresnel) * (1.0 - metallic);
	let n_dot_l = max(dot(normal, light), 0.0);
	return (diffuse_weight * base_color / PI + specular) * radiance * n_dot_l;
}

fn procedural_daylight() -> f32 {
	let direction_length = length(environment.sun_direction_intensity.xyz);
	if (environment.background_max_specular_lod >= 0.0 || direction_length <= 0.0001) {
		return 0.0;
	}
	let direction = environment.sun_direction_intensity.xyz / direction_length;
	let horizon_elevation = -sqrt(1.0 - 1.0 / (1.00012 * 1.00012));
	return smoothstep(-0.12, 0.05, direction.y - horizon_elevation);
}

fn shadow_cascade_index(view_depth: f32) -> u32 {
	if (view_depth <= render.shadow_cascade_splits.x) {
		return 0u;
	}
	if (view_depth <= render.shadow_cascade_splits.y) {
		return 1u;
	}
	if (view_depth <= render.shadow_cascade_splits.z) {
		return 2u;
	}
	return 3u;
}

fn directional_shadow(world_position: vec3<f32>, view_depth: f32) -> f32 {
	let cascade_index = shadow_cascade_index(view_depth);
	let shadow_position = render.shadow_view_projections[cascade_index] * vec4<f32>(world_position, 1.0);
	if (shadow_position.w <= 0.0) {
		return 1.0;
	}
	let projected = shadow_position.xyz / shadow_position.w;
	let uv = vec2<f32>(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
	if (any(uv < vec2<f32>(0.0)) || any(uv > vec2<f32>(1.0)) || projected.z < 0.0 || projected.z > 1.0) {
		return 1.0;
	}
	let dimensions = vec2<f32>(textureDimensions(shadow_map).xy);
	let texel = 1.0 / dimensions;
	var visibility = 0.0;
	for (var y: i32 = -1; y <= 1; y = y + 1) {
		for (var x: i32 = -1; x <= 1; x = x + 1) {
			visibility += textureSampleCompare(
				shadow_map,
				shadow_sampler,
				uv + vec2<f32>(f32(x), f32(y)) * texel,
				i32(cascade_index),
				projected.z - 0.0015,
			);
		}
	}
	return visibility / 9.0;
}

fn cluster_index(position: vec2<f32>, view_depth: f32) -> u32 {
	let viewport_position = clamp(
		position - cluster.viewport.xy,
		vec2<f32>(0.0),
		max(cluster.viewport.zw - vec2<f32>(0.0001), vec2<f32>(0.0)),
	);
	let tile_size = cluster.viewport.zw / vec2<f32>(cluster.counts.xy);
	let tile = min(
		vec2<u32>(viewport_position / tile_size),
		cluster.counts.xy - vec2<u32>(1u),
	);
	let near_plane = cluster.z_parameters.x;
	let far_plane = cluster.z_parameters.y;
	let depth = clamp(view_depth, near_plane, far_plane);
	let slice = min(
		u32(floor(log2(depth / near_plane) / cluster.z_parameters.z * f32(cluster.counts.z))),
		cluster.counts.z - 1u,
	);
	return tile.x + tile.y * cluster.counts.x + slice * cluster.counts.x * cluster.counts.y;
}

@fragment
fn fs_main(
	input: Vertex_Output,
	@builtin(front_facing) front_facing: bool,
) -> @location(0) vec4<f32> {
	let base_color_sample = textureSample(base_color_texture, base_color_sampler, input.uv);
	if (material.flags.z > 0.5 && base_color_sample.a * input.color.a < material.alpha.x) {
		discard;
	}
	let normal = mapped_normal(input, front_facing);
	let view = normalize(render.camera_position.xyz - input.world_position);
	let texture_color = base_color_sample.rgb;
	let legacy_factor = pow(max(input.color.rgb, vec3<f32>(0.0)), vec3<f32>(2.2));
	let color_factor = mix(legacy_factor, input.color.rgb, material.flags.y);
	let base_color = texture_color * color_factor;
	let packed = textureSample(metallic_roughness_texture, metallic_roughness_sampler, input.uv);
	let metallic = clamp(packed.b * material.pbr_factors.x, 0.0, 1.0);
	let roughness = clamp(packed.g * material.pbr_factors.y, 0.045, 1.0);
	let occlusion_sample = textureSample(occlusion_texture, occlusion_sampler, input.uv).r;
	let occlusion = mix(1.0, occlusion_sample, material.pbr_factors.w);
	let f0 = mix(vec3<f32>(0.04), base_color, metallic);
	var color = vec3<f32>(0.0);
	var shadow = 1.0;
	if (input.shadow_receiver > 0.5 && render.light_counts.x > 0u) {
		shadow = directional_shadow(input.world_position, input.view_depth);
	}
	for (var i: u32 = 0u; i < render.light_counts.x; i = i + 1u) {
		let directional = render.directional_direction_intensity[i];
		let light = -normalize(directional.xyz);
		let directional_shadow_factor = select(1.0, shadow, i == 0u);
		let radiance = render.directional_color[i].rgb * directional.w * directional_shadow_factor;
		color += evaluate_light(normal, view, light, radiance, base_color, metallic, roughness, f0);
	}
	let fragment_cluster = cluster_index(input.position.xy, input.view_depth);
	let clustered_light_count = min(cluster_light_counts[fragment_cluster], u32(cluster.z_parameters.w));
	for (var i: u32 = 0u; i < clustered_light_count; i = i + 1u) {
		let light_index = cluster_light_indices[fragment_cluster * u32(cluster.z_parameters.w) + i];
		let point_light = point_lights[light_index];
		let point = point_light.position_range;
		let offset = point.xyz - input.world_position;
		let distance = length(offset);
		if (distance < point.w && distance > 0.0001) {
			let light = offset / distance;
			let range_fade = max(1.0 - distance / point.w, 0.0);
			let attenuation = range_fade * range_fade / (1.0 + distance * distance);
			let point_color = point_light.color_intensity;
			let radiance = point_color.rgb * point_color.w * attenuation;
			color += evaluate_light(normal, view, light, radiance, base_color, metallic, roughness, f0);
		}
	}
	let n_dot_v = max(dot(normal, view), 0.0);
	let ambient_fresnel = fresnel_schlick_roughness(n_dot_v, f0, roughness);
	let ambient_diffuse = (vec3<f32>(1.0) - ambient_fresnel) * (1.0 - metallic) * base_color;
	let ambient_specular = ambient_fresnel * mix(0.9, 0.2, roughness);
	if (environment.enabled > 0.5) {
		let irradiance = textureSampleLevel(irradiance_cube, environment_sampler, rotate_environment(normal), 0.0).rgb;
		let reflection = reflect(-view, normal);
		let prefiltered = textureSampleLevel(
			specular_cube,
			environment_sampler,
			rotate_environment(reflection),
			roughness * environment.max_specular_lod,
		).rgb;
		let brdf = environment_brdf(n_dot_v, roughness);
		let diffuse_ibl = ambient_diffuse * irradiance;
		let specular_ibl = prefiltered * (ambient_fresnel * brdf.x + brdf.y);
		color += (diffuse_ibl + specular_ibl) * occlusion * environment.intensity;
	} else {
		color += render.ambient.rgb * (ambient_diffuse + ambient_specular) * occlusion;
		if (environment.background_max_specular_lod < 0.0) {
			let daylight = procedural_daylight();
			let hemisphere = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
			let sky_fill = mix(
				vec3<f32>(0.0005, 0.0012, 0.006),
				vec3<f32>(0.10, 0.18, 0.30) * environment.atmosphere_sky_tint.rgb,
				daylight,
			);
			let ground_fill = mix(
				vec3<f32>(0.0003, 0.0004, 0.0007),
				environment.atmosphere_ground_color.rgb * 0.08,
				daylight,
			);
			color += ambient_diffuse * mix(ground_fill, sky_fill, hemisphere) * occlusion;
		}
	}
	let emissive_map = textureSample(emissive_texture, emissive_sampler, input.uv).rgb;
	let emissive = mix(input.emissive, input.emissive * emissive_map, material.flags.x);
	return vec4<f32>((color + emissive) * environment.exposure, 1.0);
}

struct Mask_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
	@location(1) alpha: f32,
};

@vertex
fn shadow_vs(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Mask_Output {
	let instance = instances[visible_instances[visible_index]];
	var output: Mask_Output;
	output.position = render.shadow_view_projections[shadow_cascade.index] * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	return output;
}

@vertex
fn depth_vs(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Mask_Output {
	let instance = instances[visible_instances[visible_index]];
	var output: Mask_Output;
	output.position = render.view_projection * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	return output;
}

@fragment
fn mask_fs(input: Mask_Output) {
	let alpha = textureSample(base_color_texture, base_color_sampler, input.uv).a * input.alpha;
	if (alpha < material.alpha.x) {
		discard;
	}
}
`

WGPU_GPU_CULL_SHADER :: `
struct GPU_Instance {
	model: mat4x4<f32>,
	normal_model: mat4x4<f32>,
	color: vec4<f32>,
	emissive: vec4<f32>,
	shadow_flags: vec4<f32>,
	bounds: vec4<f32>,
	batch_indices: array<u32, 4>,
	lod_screen_radii: array<f32, 4>,
	lod_count: u32,
	enabled: u32,
	padding: vec2<u32>,
};

struct Batch_Info {
	visible_offset: u32,
	visible_capacity: u32,
	padding: vec2<u32>,
};

struct Draw_Indexed_Indirect {
	index_count: u32,
	instance_count: atomic<u32>,
	first_index: u32,
	base_vertex: i32,
	first_instance: u32,
};

struct Cull_Uniform {
	camera_planes: array<vec4<f32>, 6>,
	shadow_planes: array<array<vec4<f32>, 6>, 4>,
	view_projection: mat4x4<f32>,
	viewport: vec4<f32>,
	camera_position: vec4<f32>,
	slot_count: u32,
	batch_count: u32,
	hiz_mip_count: u32,
	hiz_enabled: u32,
	shadow_visible_stride: u32,
	padding_0: u32,
	padding_1: u32,
	padding_2: u32,
};

struct Visibility_Counters {
	visible_instances: atomic<u32>,
	shadow_visible_instances: atomic<u32>,
	frustum_candidates: atomic<u32>,
	frustum_culled_instances: atomic<u32>,
	occlusion_culled_instances: atomic<u32>,
	lod_visible_instances: array<atomic<u32>, 4>,
};

@group(0) @binding(0) var<storage, read> instances: array<GPU_Instance>;
@group(0) @binding(1) var<storage, read> batches: array<Batch_Info>;
@group(0) @binding(2) var<storage, read_write> visible_instances: array<u32>;
@group(0) @binding(3) var<storage, read_write> shadow_visible_instances: array<u32>;
@group(0) @binding(4) var<storage, read_write> indirect: array<Draw_Indexed_Indirect>;
@group(0) @binding(5) var<storage, read_write> shadow_indirect: array<Draw_Indexed_Indirect>;
@group(0) @binding(6) var<uniform> cull: Cull_Uniform;
@group(0) @binding(7) var hiz_depth: texture_2d<f32>;
@group(0) @binding(8) var<storage, read_write> counters: Visibility_Counters;

fn camera_sphere_visible(bounds: vec4<f32>) -> bool {
	for (var plane_index: u32 = 0u; plane_index < 6u; plane_index = plane_index + 1u) {
		let plane = cull.camera_planes[plane_index];
		if (dot(plane.xyz, bounds.xyz) + plane.w < -bounds.w) {
			return false;
		}
	}
	return true;
}

fn shadow_sphere_visible(bounds: vec4<f32>, cascade_index: u32) -> bool {
	for (var plane_index: u32 = 0u; plane_index < 6u; plane_index = plane_index + 1u) {
		let plane = cull.shadow_planes[cascade_index][plane_index];
		if (dot(plane.xyz, bounds.xyz) + plane.w < -bounds.w) {
			return false;
		}
	}
	return true;
}

fn camera_sphere_occluded(bounds: vec4<f32>) -> bool {
	if (cull.hiz_enabled == 0u || cull.hiz_mip_count == 0u) {
		return false;
	}
	let camera_offset = bounds.xyz - cull.camera_position.xyz;
	let conservative_distance = bounds.w * 4.0;
	if (dot(camera_offset, camera_offset) <= conservative_distance * conservative_distance) {
		return false;
	}
	let clip = cull.view_projection * vec4<f32>(bounds.xyz, 1.0);
	if (clip.w <= 0.0001) {
		return false;
	}
	let ndc = clip.xyz / clip.w;
	let radius_ndc = vec2<f32>(
		abs(bounds.w * cull.view_projection[0][0] / clip.w),
		abs(bounds.w * cull.view_projection[1][1] / clip.w)
	) * 1.05;
	let center_px = cull.viewport.xy + vec2<f32>(
		(ndc.x * 0.5 + 0.5) * cull.viewport.z,
		(0.5 - ndc.y * 0.5) * cull.viewport.w
	);
	let radius_px = radius_ndc * cull.viewport.zw * 0.5;
	let extent = max(max(radius_px.x * 2.0, radius_px.y * 2.0), 1.0);
	let mip = min(u32(max(ceil(log2(extent)), 0.0)), cull.hiz_mip_count - 1u);
	let mip_size = vec2<i32>(textureDimensions(hiz_depth, i32(mip)));
	let scale = exp2(f32(mip));
	let low = clamp(vec2<i32>(floor((center_px - radius_px) / scale)), vec2<i32>(0), mip_size - vec2<i32>(1));
	let high = clamp(vec2<i32>(floor((center_px + radius_px) / scale)), vec2<i32>(0), mip_size - vec2<i32>(1));
	var farthest_occluder = textureLoad(hiz_depth, low, i32(mip)).x;
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, vec2<i32>(high.x, low.y), i32(mip)).x);
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, vec2<i32>(low.x, high.y), i32(mip)).x);
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, high, i32(mip)).x);
	let toward_camera = normalize(cull.camera_position.xyz - bounds.xyz);
	let nearest_clip = cull.view_projection * vec4<f32>(bounds.xyz + toward_camera * bounds.w, 1.0);
	if (nearest_clip.w <= 0.0001) {
		return false;
	}
	let nearest_depth = nearest_clip.z / nearest_clip.w;
	return nearest_depth > farthest_occluder + 0.0015;
}

fn select_lod(instance: GPU_Instance) -> u32 {
	if (instance.lod_count == 0u) {
		return 0u;
	}
	let clip = cull.view_projection * vec4<f32>(instance.bounds.xyz, 1.0);
	if (clip.w <= 0.0001) {
		return 0u;
	}
	let screen_radius = abs(instance.bounds.w * cull.view_projection[1][1] / clip.w) * 0.5;
	var level = 0u;
	for (var threshold_index = 0u; threshold_index < instance.lod_count; threshold_index = threshold_index + 1u) {
		if (screen_radius < instance.lod_screen_radii[threshold_index]) {
			level = threshold_index + 1u;
		}
	}
	return level;
}

@compute @workgroup_size(64)
fn cull_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let slot = invocation.x;
	let cascade_index = invocation.y;
	if (slot >= cull.slot_count || cascade_index >= 4u) {
		return;
	}
	let instance = instances[slot];
	let lod_level = select_lod(instance);
	let batch_index = instance.batch_indices[lod_level];
	if (instance.enabled == 0u || batch_index >= cull.batch_count) {
		return;
	}
	let batch = batches[batch_index];
	if (cascade_index == 0u && camera_sphere_visible(instance.bounds)) {
		atomicAdd(&counters.frustum_candidates, 1u);
		if (camera_sphere_occluded(instance.bounds)) {
			atomicAdd(&counters.occlusion_culled_instances, 1u);
		} else {
			let local_index = atomicAdd(&indirect[batch_index].instance_count, 1u);
			if (local_index < batch.visible_capacity) {
				visible_instances[batch.visible_offset + local_index] = slot;
				atomicAdd(&counters.visible_instances, 1u);
				atomicAdd(&counters.lod_visible_instances[lod_level], 1u);
			}
		}
	} else if (cascade_index == 0u) {
		atomicAdd(&counters.frustum_culled_instances, 1u);
	}
	if (instance.shadow_flags.x > 0.5 && shadow_sphere_visible(instance.bounds, cascade_index)) {
		let indirect_index = cascade_index * cull.batch_count + batch_index;
		let local_index = atomicAdd(&shadow_indirect[indirect_index].instance_count, 1u);
		if (local_index < batch.visible_capacity) {
			shadow_visible_instances[
				cascade_index * cull.shadow_visible_stride + batch.visible_offset + local_index
			] = slot;
			atomicAdd(&counters.shadow_visible_instances, 1u);
		}
	}
}
`

WGPU_HIZ_COPY_SHADER :: `
@group(0) @binding(0) var source_depth: texture_depth_2d;
@group(0) @binding(1) var destination_depth: texture_storage_2d<r32float, write>;

@compute @workgroup_size(8, 8)
fn copy_depth(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let size = textureDimensions(destination_depth);
	if (any(invocation.xy >= size)) {
		return;
	}
	textureStore(destination_depth, invocation.xy, vec4<f32>(textureLoad(source_depth, vec2<i32>(invocation.xy), 0)));
}
`

WGPU_HIZ_DOWNSAMPLE_SHADER :: `
@group(0) @binding(0) var source_hiz: texture_2d<f32>;
@group(0) @binding(1) var destination_hiz: texture_storage_2d<r32float, write>;

@compute @workgroup_size(8, 8)
fn downsample_depth(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let size = textureDimensions(destination_hiz);
	if (any(invocation.xy >= size)) {
		return;
	}
	let source_size = vec2<i32>(textureDimensions(source_hiz));
	let base = vec2<i32>(invocation.xy * 2u);
	let limit = source_size - vec2<i32>(1);
	let a = textureLoad(source_hiz, min(base, limit), 0).x;
	let b = textureLoad(source_hiz, min(base + vec2<i32>(1, 0), limit), 0).x;
	let c = textureLoad(source_hiz, min(base + vec2<i32>(0, 1), limit), 0).x;
	let d = textureLoad(source_hiz, min(base + vec2<i32>(1, 1), limit), 0).x;
	textureStore(destination_hiz, invocation.xy, vec4<f32>(max(max(a, b), max(c, d))));
}
`
