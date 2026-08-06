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
	render_flags: vec4<f32>,
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

fn transform_preserves_meshlet_cones(scale: vec3<f32>) -> bool {
	let minimum = min(scale.x, min(scale.y, scale.z));
	let maximum = max(scale.x, max(scale.y, scale.z));
	return minimum > 0.000001 && maximum <= minimum * 1.001;
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
	instances[slot].render_flags.z = select(
		0.0,
		1.0,
		transform_preserves_meshlet_cones(transform.scale.xyz),
	);
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
	shadow_cascade_texel_sizes: vec4<f32>,
	shadow_map_parameters: vec4<f32>,
	debug: vec4<u32>,
	camera_clip: vec4<f32>,
	virtual_geometry: vec4<f32>,
	virtual_geometry_epoch: vec4<u32>,
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
	shader_parameters: array<vec4<f32>, 4>,
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
	reflection_intensity: f32,
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
	render_flags: vec4<f32>,
	bounds: vec4<f32>,
	batch_indices: array<u32, 4>,
	lod_screen_radii: array<f32, 4>,
	lod_count: u32,
	enabled: u32,
	padding: vec2<u32>,
};

struct Meshlet_Info {
	bounds: vec4<f32>,
	cone_axis_cutoff: vec4<f32>,
	group_bounds: vec4<f32>,
	refined_bounds: vec4<f32>,
	visible_offset: u32,
	visible_capacity: u32,
	flags: u32,
	group_depth: u32,
	group_error: f32,
	refined_error: f32,
	max_depth: u32,
	virtual_geometry: u32,
	first_index: u32,
	base_vertex: u32,
	triangle_count: u32,
	identity: u32,
	page_resident: u32,
	refined_resident: u32,
	request_geometry_index: u32,
	request_geometry_generation: u32,
	group_index: u32,
	request_group_index: u32,
	request_enabled: u32,
	batch_index: u32,
	transition_start: u32,
	refined_transition_start: u32,
	has_coarse_parent: u32,
	padding: u32,
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
@group(0) @binding(10) var<storage, read> meshlet_identities: array<u32>;
@group(0) @binding(11) var<storage, read> geometry_vertices: array<u32>;
@group(0) @binding(12) var<storage, read> geometry_indices: array<u32>;
@group(0) @binding(13) var<storage, read> meshlets: array<Meshlet_Info>;
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
	@location(3) tangent: vec4<f32>,
};

struct Compact_Input {
	@location(4) instance_slot: u32,
	@location(5) meshlet_index: u32,
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
	@location(7) world_tangent: vec4<f32>,
	@location(8) @interpolate(flat) meshlet_identity: u32,
	@location(9) @interpolate(flat) lod_level: u32,
	@location(10) @interpolate(flat) virtual_transition: vec2<f32>,
};

fn selected_lod(instance: GPU_Instance) -> u32 {
	if (instance.lod_count == 0u) {
		return 0u;
	}
	let clip = render.view_projection * vec4<f32>(instance.bounds.xyz, 1.0);
	if (clip.w <= 0.0001) {
		return 0u;
	}
	let screen_radius = abs(instance.bounds.w * render.view_projection[1][1] / clip.w) * 0.5;
	var level = 0u;
	for (
		var threshold_index = 0u;
		threshold_index < instance.lod_count;
		threshold_index = threshold_index + 1u
	) {
		if (screen_radius < instance.lod_screen_radii[threshold_index]) {
			level = threshold_index + 1u;
		}
	}
	return level;
}

fn load_geometry_vertex(vertex_index: u32) -> Vertex_Input {
	let base = vertex_index * 12u;
	var vertex: Vertex_Input;
	vertex.position = bitcast<vec3<f32>>(vec3<u32>(
		geometry_vertices[base],
		geometry_vertices[base + 1u],
		geometry_vertices[base + 2u],
	));
	vertex.normal = bitcast<vec3<f32>>(vec3<u32>(
		geometry_vertices[base + 3u],
		geometry_vertices[base + 4u],
		geometry_vertices[base + 5u],
	));
	vertex.uv = bitcast<vec2<f32>>(vec2<u32>(
		geometry_vertices[base + 6u],
		geometry_vertices[base + 7u],
	));
	vertex.tangent = bitcast<vec4<f32>>(vec4<u32>(
		geometry_vertices[base + 8u],
		geometry_vertices[base + 9u],
		geometry_vertices[base + 10u],
		geometry_vertices[base + 11u],
	));
	return vertex;
}

fn compact_source_vertex_index(record: Compact_Input, vertex_index: u32) -> u32 {
	let meshlet = meshlets[record.meshlet_index];
	let local_index = select(0u, vertex_index, vertex_index < meshlet.triangle_count * 3u);
	let source_index = geometry_indices[meshlet.first_index + local_index];
	return meshlet.base_vertex + source_index;
}

fn load_compact_position(record: Compact_Input, vertex_index: u32) -> vec3<f32> {
	let source_vertex = compact_source_vertex_index(record, vertex_index);
	let base = source_vertex * 12u;
	return bitcast<vec3<f32>>(vec3<u32>(
		geometry_vertices[base],
		geometry_vertices[base + 1u],
		geometry_vertices[base + 2u],
	));
}

fn load_compact_vertex(record: Compact_Input, vertex_index: u32) -> Vertex_Input {
	return load_geometry_vertex(compact_source_vertex_index(record, vertex_index));
}

fn virtual_transition_progress(start_token: u32) -> f32 {
	if (start_token == 0u) {
		return 1.0;
	}
	let start = start_token - 1u;
	let current = render.virtual_geometry_epoch.x;
	let duration = f32(max(render.virtual_geometry_epoch.y, 1u));
	return clamp(f32(current - start) / duration, 0.0, 1.0);
}

fn render_virtual_projected_error(
	instance: GPU_Instance,
	bounds: vec4<f32>,
	error: f32,
) -> f32 {
	if (error > 1.0e30) {
		return error;
	}
	let center = instance.model * vec4<f32>(bounds.xyz, 1.0);
	let scale = max(
		max(length(instance.model[0].xyz), length(instance.model[1].xyz)),
		length(instance.model[2].xyz),
	);
	let world_radius = bounds.w * scale;
	let distance = max(
		length(center.xyz - render.camera_position.xyz) - world_radius,
		0.0001,
	);
	return error * scale / distance * abs(render.view_projection[1][1]) *
		0.5 * render.virtual_geometry.y;
}

fn virtual_lod_progress(
	instance: GPU_Instance,
	bounds: vec4<f32>,
	error: f32,
	error_pixels: f32,
) -> f32 {
	if (error <= 0.0) {
		return 0.0;
	}
	let projected = render_virtual_projected_error(instance, bounds, error);
	let low = error_pixels * render.virtual_geometry.z;
	let high = max(error_pixels * render.virtual_geometry.w, low + 0.0001);
	return smoothstep(low, high, projected);
}

fn virtual_coverage_for_error(
	instance: GPU_Instance,
	meshlet: Meshlet_Info,
	error_pixels: f32,
) -> vec2<f32> {
	if (meshlet.virtual_geometry == 0u) {
		return vec2<f32>(0.0, 1.0);
	}
	var fade_in = 1.0;
	if (meshlet.has_coarse_parent != 0u) {
		fade_in = virtual_lod_progress(
			instance,
			meshlet.group_bounds,
			meshlet.group_error,
			error_pixels,
		);
	}
	var fade_out = 0.0;
	if (meshlet.refined_resident != 0u || meshlet.refined_transition_start != 0u) {
		fade_out = virtual_lod_progress(
			instance,
			meshlet.refined_bounds,
			meshlet.refined_error,
			error_pixels,
		);
	}
	if (meshlet.transition_start != 0u) {
		fade_in = min(fade_in, virtual_transition_progress(meshlet.transition_start));
	}
	if (meshlet.refined_transition_start != 0u) {
		fade_out = min(
			fade_out,
			virtual_transition_progress(meshlet.refined_transition_start),
		);
	}
	return vec2<f32>(fade_out, fade_in);
}

fn virtual_coverage_for(instance: GPU_Instance, meshlet: Meshlet_Info) -> vec2<f32> {
	return virtual_coverage_for_error(instance, meshlet, render.virtual_geometry.x);
}

fn render_virtual_shadow_error(cascade_index: u32) -> f32 {
	let multipliers = array<f32, 4>(8.0, 32.0, 128.0, 512.0);
	return render.virtual_geometry.x * multipliers[min(cascade_index, 3u)] /
		max(render.shadow_map_parameters.x, 0.01);
}

fn transform_vertex(
	input: Vertex_Input,
	instance: GPU_Instance,
	meshlet_identity: u32,
	virtual_transition: vec2<f32>,
) -> Vertex_Output {
	var output: Vertex_Output;
	let local_position = vec4<f32>(input.position, 1.0);
	output.position = render.view_projection * instance.model * local_position;
	output.world_position = (instance.model * local_position).xyz;
	output.world_normal = normalize((instance.normal_model * vec4<f32>(input.normal, 0.0)).xyz);
	output.world_tangent = vec4<f32>(
		(instance.model * vec4<f32>(input.tangent.xyz, 0.0)).xyz,
		input.tangent.w,
	);
	output.color = instance.color;
	output.emissive = instance.emissive.rgb;
	output.view_depth = -(render.view * instance.model * local_position).z;
	output.shadow_receiver = instance.render_flags.y;
	output.uv = input.uv;
	output.meshlet_identity = meshlet_identity;
	output.lod_level = select(0u, selected_lod(instance), render.debug.x == 7u);
	output.virtual_transition = virtual_transition;
	return output;
}

fn discarded_vertex_output() -> Vertex_Output {
	var output: Vertex_Output;
	output.position = vec4<f32>(2.0, 2.0, 2.0, 1.0);
	output.color = vec4<f32>(0.0);
	output.world_position = vec3<f32>(0.0);
	output.world_normal = vec3<f32>(0.0);
	output.view_depth = 0.0;
	output.shadow_receiver = 0.0;
	output.uv = vec2<f32>(0.0);
	output.emissive = vec3<f32>(0.0);
	output.world_tangent = vec4<f32>(0.0);
	output.meshlet_identity = 0u;
	output.lod_level = 0u;
	output.virtual_transition = vec2<f32>(0.0, 1.0);
	return output;
}

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Vertex_Output {
	let instance = instances[visible_instances[visible_index]];
	let packed_identity = meshlet_identities[visible_index];
	var identity = 0u;
	if ((render.debug.x == 6u || render.debug.x == 8u || render.debug.x == 11u) && render.debug.y != 0u) {
		identity = packed_identity;
	}
	var transition = vec2<f32>(0.0, 1.0);
	let meshlet_token = packed_identity & 0x003fffffu;
	if (meshlet_token != 0u) {
		transition = virtual_coverage_for(instance, meshlets[meshlet_token - 1u]);
	}
	return transform_vertex(input, instance, identity, transition);
}

@vertex
fn compact_vs(record: Compact_Input, @builtin(vertex_index) vertex_index: u32) -> Vertex_Output {
	let instance = instances[record.instance_slot];
	let meshlet = meshlets[record.meshlet_index];
	if (vertex_index >= meshlet.triangle_count * 3u) {
		return discarded_vertex_output();
	}
	return transform_vertex(
		load_compact_vertex(record, vertex_index),
		instance,
		meshlet.identity,
		virtual_coverage_for(instance, meshlet),
	);
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

fn environment_specular_response(
	f0: vec3<f32>,
	n_dot_v: f32,
	roughness: f32,
) -> vec3<f32> {
	let brdf = environment_brdf(n_dot_v, roughness);
	let fresnel = fresnel_schlick_roughness(n_dot_v, f0, roughness);
	let single_scattering = fresnel * brdf.x + brdf.y;
	let single_scattering_energy = clamp(brdf.x + brdf.y, 0.0, 1.0);
	let multiple_scattering_energy = 1.0 - single_scattering_energy;
	let average_fresnel = f0 + (vec3<f32>(1.0) - f0) / 21.0;
	let multiple_scattering =
		single_scattering *
		average_fresnel /
		max(
			vec3<f32>(1.0) - multiple_scattering_energy * average_fresnel,
			vec3<f32>(0.001),
		);
	return single_scattering + multiple_scattering * multiple_scattering_energy;
}

fn specular_ambient_occlusion(n_dot_v: f32, occlusion: f32, roughness: f32) -> f32 {
	return clamp(
		pow(n_dot_v + occlusion, exp2(-16.0 * roughness - 1.0)) - 1.0 + occlusion,
		0.0,
		1.0,
	);
}

fn environment_horizon_occlusion(
	reflection: vec3<f32>,
	geometric_normal: vec3<f32>,
) -> f32 {
	let horizon = clamp(1.0 + dot(reflection, geometric_normal), 0.0, 1.0);
	return horizon * horizon;
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

fn filtered_roughness(normal: vec3<f32>, roughness: f32) -> f32 {
	let normal_dx = dpdx(normal);
	let normal_dy = dpdy(normal);
	let variance = min(
		0.25 * (dot(normal_dx, normal_dx) + dot(normal_dy, normal_dy)),
		0.25,
	);
	return clamp(sqrt(roughness * roughness + variance), 0.045, 1.0);
}

fn mapped_normal(input: Vertex_Output, front_facing: bool) -> vec3<f32> {
	let geometric = normalize(input.world_normal);
	let flip = material.flags.w > 0.5 && !front_facing;
	var sampled = textureSample(normal_texture, normal_sampler, input.uv).xyz * 2.0 - 1.0;
	sampled = normalize(vec3<f32>(sampled.xy * material.pbr_factors.z, sampled.z));
	let authored_tangent_length = length(input.world_tangent.xyz);
	if (authored_tangent_length > 0.0001) {
		let tangent = normalize(
			input.world_tangent.xyz -
			geometric * dot(geometric, input.world_tangent.xyz),
		);
		let bitangent = normalize(cross(geometric, tangent)) * input.world_tangent.w;
		let mapped = normalize(mat3x3<f32>(tangent, bitangent, geometric) * sampled);
		return select(mapped, -mapped, flip);
	}
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

fn procedural_environment_radiance(sample_direction: vec3<f32>, roughness: f32) -> vec3<f32> {
	if (environment.background_max_specular_lod >= 0.0) {
		return vec3<f32>(0.0);
	}
	let direction = normalize(sample_direction);
	let sky_tint = environment.atmosphere_sky_tint.rgb;
	let ground_tint = environment.atmosphere_ground_color.rgb;
	let turbidity = clamp(environment.atmosphere_parameters.x, 0.0, 10.0);
	let atmosphere_thickness = clamp(environment.atmosphere_parameters.y, 0.1, 5.0);
	let horizon_softness = clamp(environment.atmosphere_parameters.z, 0.1, 5.0);
	let sun_size = clamp(environment.atmosphere_parameters.w, 0.1, 10.0);
	let planet_radius = 1.0;
	let observer_radius = 1.00012;
	let horizon_elevation = -sqrt(
		1.0 - (planet_radius * planet_radius) / (observer_radius * observer_radius)
	);
	let atmosphere_elevation = clamp(direction.y, -1.0, 1.0) - horizon_elevation;
	let daylight = procedural_daylight();
	let sky_height = pow(
		clamp(atmosphere_elevation / (1.0 - horizon_elevation), 0.0, 1.0),
		0.35,
	);
	let ground_depth = pow(
		clamp(-atmosphere_elevation / (1.0 + horizon_elevation), 0.0, 1.0),
		0.45,
	);
	let sky_horizon = mix(
		vec3<f32>(0.004, 0.008, 0.025),
		vec3<f32>(0.30, 0.58, 0.88),
		daylight,
	) * sky_tint;
	let sky_zenith = mix(
		vec3<f32>(0.0004, 0.0012, 0.008),
		vec3<f32>(0.018, 0.095, 0.34),
		daylight,
	) * sky_tint;
	var sky_color = mix(sky_horizon, sky_zenith, sky_height);
	let haze_warmth = clamp((turbidity - 2.0) / 8.0, 0.0, 1.0);
	let day_haze_color = mix(
		vec3<f32>(0.68, 0.82, 0.94),
		vec3<f32>(0.94, 0.70, 0.46),
		haze_warmth,
	);
	let haze_color = mix(
		vec3<f32>(0.006, 0.010, 0.026),
		day_haze_color,
		daylight,
	) * sky_tint;
	let aerial_haze = exp(
		-abs(atmosphere_elevation) * 13.0 / atmosphere_thickness,
	);
	sky_color = mix(
		sky_color,
		haze_color,
		aerial_haze * clamp(0.38 + turbidity * 0.10, 0.0, 0.9),
	);
	let ground_daylight = mix(0.018, 1.0, daylight);
	let ground_horizon = ground_tint * ground_daylight;
	let ground_nadir = ground_tint * vec3<f32>(0.23, 0.21, 0.20) * ground_daylight;
	let ground_color = mix(ground_horizon, ground_nadir, ground_depth);
	let sky_mask = smoothstep(
		-0.004 * horizon_softness,
		0.006 * horizon_softness,
		atmosphere_elevation,
	);
	var radiance = mix(ground_color, sky_color, sky_mask);
	let blur = roughness * roughness;
	let average_sky = mix(
		vec3<f32>(0.003, 0.006, 0.018),
		vec3<f32>(0.16, 0.29, 0.46) * sky_tint,
		daylight,
	);
	let average_ground = ground_tint * mix(0.012, 0.32, daylight);
	let average_environment = mix(average_ground, average_sky, 0.62);
	radiance = mix(radiance, average_environment, blur * 0.65);
	let sun_direction_length = length(environment.sun_direction_intensity.xyz);
	if (
		sun_direction_length > 0.0001 &&
		environment.sun_direction_intensity.w > 0.0
	) {
		let sun_direction = environment.sun_direction_intensity.xyz / sun_direction_length;
		let sun_visibility = smoothstep(
			-0.02,
			0.02,
			sun_direction.y - horizon_elevation,
		);
		let alignment = max(dot(direction, sun_direction), 0.0);
		let sun_exponent = mix(1024.0, 4.0, blur) / sun_size;
		let sun_lobe = pow(alignment, sun_exponent);
		let sun_energy = mix(6.0, 0.18, blur);
		radiance +=
			environment.sun_color.rgb *
			environment.sun_direction_intensity.w *
			sun_lobe *
			sun_energy *
			sun_visibility;
	}
	return max(radiance, vec3<f32>(0.0));
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

fn directional_shadow_cascade(
	world_position: vec3<f32>,
	world_normal: vec3<f32>,
	cascade_index: u32,
) -> f32 {
	let light = -normalize(render.directional_direction_intensity[0].xyz);
	let normal_light = clamp(dot(world_normal, light), 0.0, 1.0);
	let normal_bias = render.shadow_cascade_texel_sizes[cascade_index] *
		mix(1.5, 0.25, normal_light);
	let biased_position = world_position + world_normal * normal_bias;
	let shadow_position = render.shadow_view_projections[cascade_index] *
		vec4<f32>(biased_position, 1.0);
	if (shadow_position.w <= 0.0) {
		return 1.0;
	}
	let projected = shadow_position.xyz / shadow_position.w;
	let uv = vec2<f32>(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
	if (any(uv < vec2<f32>(0.0)) || any(uv > vec2<f32>(1.0)) || projected.z < 0.0 || projected.z > 1.0) {
		return 1.0;
	}
	let uv_scale = render.shadow_map_parameters.x;
	let texel = render.shadow_map_parameters.y;
	let atlas_uv = uv * uv_scale;
	let half_texel = texel * 0.5;
	let uv_min = vec2<f32>(half_texel);
	let uv_max = vec2<f32>(uv_scale - half_texel);
	var visibility = 0.0;
	for (var y: i32 = -1; y <= 1; y = y + 1) {
		for (var x: i32 = -1; x <= 1; x = x + 1) {
			let weight =
				select(1.0, 2.0, x == 0) *
				select(1.0, 2.0, y == 0);
			visibility += weight * textureSampleCompare(
				shadow_map,
				shadow_sampler,
				clamp(
					atlas_uv + vec2<f32>(f32(x), f32(y)) * texel * 1.5,
					uv_min,
					uv_max,
				),
				i32(cascade_index),
				projected.z - 0.00035,
			);
		}
	}
	return visibility / 16.0;
}

fn directional_shadow(
	world_position: vec3<f32>,
	world_normal: vec3<f32>,
	view_depth: f32,
) -> f32 {
	let cascade_index = shadow_cascade_index(view_depth);
	let visibility = directional_shadow_cascade(
		world_position,
		world_normal,
		cascade_index,
	);
	var previous_split = cluster.z_parameters.x;
	if (cascade_index > 0u) {
		previous_split = render.shadow_cascade_splits[cascade_index - 1u];
	}
	let current_split = render.shadow_cascade_splits[cascade_index];
	let transition_width = max((current_split - previous_split) * 0.1, 0.001);
	let transition = smoothstep(
		current_split - transition_width,
		current_split,
		view_depth,
	);
	if (transition <= 0.0) {
		return visibility;
	}
	var next_visibility = 1.0;
	if (cascade_index < 3u) {
		next_visibility = directional_shadow_cascade(
			world_position,
			world_normal,
			cascade_index + 1u,
		);
	}
	return mix(visibility, next_visibility, transition);
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

struct Fragment_Output {
	@location(0) color: vec4<f32>,
	@location(1) surface: vec4<f32>,
	@location(2) indirect_diffuse: vec4<f32>,
};

fn octahedral_encode(direction: vec3<f32>) -> vec2<f32> {
	let denominator = abs(direction.x) + abs(direction.y) + abs(direction.z);
	var encoded = direction.xy / max(denominator, 0.000001);
	if (direction.z < 0.0) {
		encoded = (vec2<f32>(1.0) - abs(encoded.yx)) * sign(encoded);
	}
	return encoded;
}

fn meshlet_debug_color(identity: u32) -> vec3<f32> {
	var value = identity * 747796405u + 2891336453u;
	value = ((value >> ((value >> 28u) + 4u)) ^ value) * 277803737u;
	value = (value >> 22u) ^ value;
	let hue = f32(value & 1023u) / 1023.0;
	return 0.42 + 0.58 * cos(
		6.28318530718 * (hue + vec3<f32>(0.0, 0.67, 0.33)),
	);
}

const VIRTUAL_TRANSITION_MARKER: f32 = 0.25;

fn apply_virtual_transition(position: vec4<f32>, transition: vec2<f32>, epoch: u32) {
	// Adjacent simplifications can have different silhouettes and coverage,
	// especially for thin photogrammetry sheets. Complementary stochastic
	// discard exposes the background wherever only one side covers a pixel.
	// Keep both opaque sides complete and let the depth buffer select the
	// nearest sample. The interval remains available to the temporal marker.
}

fn virtual_transition_marker(transition: vec2<f32>) -> f32 {
	return select(
		1.0,
		VIRTUAL_TRANSITION_MARKER,
		transition.x > 0.0 || transition.y < 1.0,
	);
}

@fragment
fn fs_main(
	input: Vertex_Output,
	@builtin(front_facing) front_facing: bool,
) -> Fragment_Output {
	let transition_epoch = select(
		0u,
		render.virtual_geometry_epoch.x,
		render.virtual_geometry_epoch.z != 0u,
	);
	apply_virtual_transition(input.position, input.virtual_transition, transition_epoch);
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
	let roughness = filtered_roughness(
		normal,
		clamp(packed.g * material.pbr_factors.y, 0.045, 1.0),
	);
	let occlusion_sample = textureSample(occlusion_texture, occlusion_sampler, input.uv).r;
	let occlusion = mix(1.0, occlusion_sample, material.pbr_factors.w);
	if (render.debug.x != 0u) {
		var debug_color = vec3<f32>(0.0);
		switch render.debug.x {
			case 1u: {
				debug_color = base_color;
			}
			case 2u: {
				debug_color = normal * 0.5 + vec3<f32>(0.5);
			}
			case 3u: {
				debug_color = vec3<f32>(roughness);
			}
			case 4u: {
				debug_color = vec3<f32>(metallic);
			}
			case 5u: {
				let near_plane = max(render.camera_clip.x, 0.0001);
				let far_plane = max(render.camera_clip.y, near_plane + 0.0001);
				let normalized_depth = clamp(
					log2(max(input.view_depth / near_plane, 1.0)) /
						max(log2(far_plane / near_plane), 0.0001),
					0.0,
					1.0,
				);
				debug_color = vec3<f32>(1.0 - normalized_depth);
			}
			case 6u: {
				if (render.debug.y != 0u && input.meshlet_identity != 0u) {
					debug_color = meshlet_debug_color(input.meshlet_identity);
				} else {
					let checker = u32(input.position.x / 12.0) ^ u32(input.position.y / 12.0);
					debug_color = select(
						vec3<f32>(0.08, 0.09, 0.11),
						vec3<f32>(0.48, 0.12, 0.24),
						(checker & 1u) != 0u,
					);
				}
			}
			case 7u: {
				let lod_colors = array<vec3<f32>, 4>(
					vec3<f32>(0.22, 0.86, 0.62),
					vec3<f32>(0.20, 0.58, 1.0),
					vec3<f32>(0.76, 0.40, 1.0),
					vec3<f32>(1.0, 0.42, 0.18),
				);
				debug_color = lod_colors[min(input.lod_level, 3u)];
			}
			case 8u: {
				if (render.debug.y != 0u && input.meshlet_identity != 0u) {
					debug_color = vec3<f32>(0.18, 0.82, 0.48);
				} else {
					let checker = u32(input.position.x / 12.0) ^ u32(input.position.y / 12.0);
					debug_color = select(
						vec3<f32>(0.08, 0.09, 0.11),
						vec3<f32>(0.48, 0.12, 0.24),
						(checker & 1u) != 0u,
					);
				}
			}
			case 10u: {
				if (render.debug.y != 0u) {
					debug_color = base_color * 0.22 + vec3<f32>(0.018, 0.022, 0.03);
				} else {
					let checker = u32(input.position.x / 12.0) ^ u32(input.position.y / 12.0);
					debug_color = select(
						vec3<f32>(0.08, 0.09, 0.11),
						vec3<f32>(0.48, 0.12, 0.24),
						(checker & 1u) != 0u,
					);
				}
			}
			case 11u: {
				if (render.debug.y != 0u && input.meshlet_identity != 0u) {
					let level = f32(input.meshlet_identity >> 24u) / 255.0;
					let refinement_missing = (input.meshlet_identity & 0x00800000u) != 0u;
					let prefetched = (input.meshlet_identity & 0x00400000u) != 0u;
					let level_color = mix(
						vec3<f32>(0.18, 0.82, 0.68),
						vec3<f32>(1.0, 0.26, 0.56),
						level,
					);
					let cluster_color = meshlet_debug_color(
						input.meshlet_identity & 0x003fffffu,
					);
					debug_color = mix(level_color, cluster_color, 0.38);
					if (prefetched) {
						debug_color = mix(debug_color, vec3<f32>(0.12, 0.72, 1.0), 0.78);
					}
					if (refinement_missing) {
						debug_color = mix(debug_color, vec3<f32>(1.0, 0.48, 0.08), 0.72);
					}
				} else {
					debug_color = vec3<f32>(0.05, 0.055, 0.07);
				}
			}
			default: {}
		}
		var output: Fragment_Output;
		output.color = vec4<f32>(debug_color, virtual_transition_marker(input.virtual_transition));
		output.indirect_diffuse = vec4<f32>(0.0, 0.0, 0.0, 1.0);
		let view_normal = normalize((render.view * vec4<f32>(normal, 0.0)).xyz);
		output.surface = vec4<f32>(
			octahedral_encode(view_normal) * 0.5 + vec2<f32>(0.5),
			roughness,
			metallic,
		);
		return output;
	}
	let f0 = mix(vec3<f32>(0.04), base_color, metallic);
	var color = vec3<f32>(0.0);
	var indirect_diffuse = vec3<f32>(0.0);
	var shadow = 1.0;
	if (input.shadow_receiver > 0.5 && render.light_counts.x > 0u) {
		let shadow_normal = normalize(
			select(input.world_normal, -input.world_normal, !front_facing),
		);
		shadow = directional_shadow(input.world_position, shadow_normal, input.view_depth);
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
	let geometric_normal_unoriented = normalize(input.world_normal);
	let geometric_normal = select(
		-geometric_normal_unoriented,
		geometric_normal_unoriented,
		dot(geometric_normal_unoriented, normal) >= 0.0,
	);
	let reflection = reflect(-view, normal);
	let horizon_visibility = select(
		1.0,
		environment_horizon_occlusion(reflection, geometric_normal),
		material.alpha.y > 0.5,
	);
	let specular_visibility =
		specular_ambient_occlusion(n_dot_v, occlusion, roughness) *
		horizon_visibility;
	if (environment.enabled > 0.5) {
		let irradiance = textureSampleLevel(irradiance_cube, environment_sampler, rotate_environment(normal), 0.0).rgb;
		let prefiltered = textureSampleLevel(
			specular_cube,
			environment_sampler,
			rotate_environment(reflection),
			roughness * environment.max_specular_lod,
		).rgb;
		let diffuse_ibl = ambient_diffuse * irradiance;
		let specular_ibl =
			prefiltered *
			environment_specular_response(f0, n_dot_v, roughness) *
			specular_visibility;
		indirect_diffuse += diffuse_ibl * occlusion * environment.intensity;
		color +=
			specular_ibl *
			environment.intensity *
			environment.reflection_intensity;
	} else {
		indirect_diffuse += render.ambient.rgb * ambient_diffuse * occlusion;
		if (environment.background_max_specular_lod < 0.0) {
			let procedural_irradiance = procedural_environment_radiance(normal, 1.0);
			let procedural_specular = procedural_environment_radiance(reflection, roughness);
			indirect_diffuse +=
				ambient_diffuse *
				procedural_irradiance *
				occlusion *
				environment.intensity;
			color +=
				procedural_specular *
				environment_specular_response(f0, n_dot_v, roughness) *
				specular_visibility *
				environment.intensity *
				environment.reflection_intensity;
		}
	}
	let emissive_map = textureSample(emissive_texture, emissive_sampler, input.uv).rgb;
	let emissive = mix(input.emissive, input.emissive * emissive_map, material.flags.x);
	var output: Fragment_Output;
	output.color = vec4<f32>(
		(color + indirect_diffuse + emissive) * environment.exposure,
		virtual_transition_marker(input.virtual_transition),
	);
	output.indirect_diffuse = vec4<f32>(
		indirect_diffuse * environment.exposure,
		1.0,
	);
	let view_normal = normalize((render.view * vec4<f32>(normal, 0.0)).xyz);
	output.surface = vec4<f32>(
		octahedral_encode(view_normal) * 0.5 + vec2<f32>(0.5),
		roughness,
		metallic,
	);
	return output;
}

struct Mask_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
	@location(1) alpha: f32,
	@location(2) @interpolate(flat) virtual_transition: vec2<f32>,
	@location(3) @interpolate(flat) virtual_transition_epoch: u32,
};

fn discarded_mask_output() -> Mask_Output {
	var output: Mask_Output;
	output.position = vec4<f32>(2.0, 2.0, 2.0, 1.0);
	output.uv = vec2<f32>(0.0);
	output.alpha = 0.0;
	output.virtual_transition = vec2<f32>(0.0, 1.0);
	output.virtual_transition_epoch = 0u;
	return output;
}

fn visible_virtual_transition(instance: GPU_Instance, visible_index: u32) -> vec2<f32> {
	let meshlet_token = meshlet_identities[visible_index] & 0x003fffffu;
	if (meshlet_token == 0u) {
		return vec2<f32>(0.0, 1.0);
	}
	return virtual_coverage_for(instance, meshlets[meshlet_token - 1u]);
}

fn visible_virtual_shadow_transition(
	instance: GPU_Instance,
	visible_index: u32,
	cascade_index: u32,
) -> vec2<f32> {
	let meshlet_token = meshlet_identities[visible_index] & 0x003fffffu;
	if (meshlet_token == 0u) {
		return vec2<f32>(0.0, 1.0);
	}
	return virtual_coverage_for_error(
		instance,
		meshlets[meshlet_token - 1u],
		render_virtual_shadow_error(cascade_index),
	);
}

@vertex
fn shadow_vs(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Mask_Output {
	let instance = instances[visible_instances[visible_index]];
	var output: Mask_Output;
	output.position = render.shadow_view_projections[shadow_cascade.index] * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	// Shadow overlap is depth-only, so retaining both hierarchy levels is
	// conservative and avoids stochastic light leaks where simplified
	// silhouettes do not cover exactly the same texels.
	output.virtual_transition = vec2<f32>(0.0, 1.0);
	output.virtual_transition_epoch = 0u;
	return output;
}

@vertex
fn compact_shadow_vs(
	record: Compact_Input,
	@builtin(vertex_index) vertex_index: u32,
) -> Mask_Output {
	let instance = instances[record.instance_slot];
	if (vertex_index >= meshlets[record.meshlet_index].triangle_count * 3u) {
		return discarded_mask_output();
	}
	let input = load_compact_vertex(record, vertex_index);
	var output: Mask_Output;
	output.position = render.shadow_view_projections[shadow_cascade.index] * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	output.virtual_transition = vec2<f32>(0.0, 1.0);
	output.virtual_transition_epoch = 0u;
	return output;
}

struct Compact_Depth_Only_Output {
	@builtin(position) position: vec4<f32>,
};

@vertex
fn compact_shadow_depth_only_vs(
	record: Compact_Input,
	@builtin(vertex_index) vertex_index: u32,
) -> Compact_Depth_Only_Output {
	let instance = instances[record.instance_slot];
	if (vertex_index >= meshlets[record.meshlet_index].triangle_count * 3u) {
		return Compact_Depth_Only_Output(vec4<f32>(2.0, 2.0, 2.0, 1.0));
	}
	let position = load_compact_position(record, vertex_index);
	return Compact_Depth_Only_Output(
		render.shadow_view_projections[shadow_cascade.index] *
		instance.model * vec4<f32>(position, 1.0),
	);
}

@vertex
fn depth_vs(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Mask_Output {
	let instance = instances[visible_instances[visible_index]];
	var output: Mask_Output;
	output.position = render.view_projection * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	output.virtual_transition = visible_virtual_transition(instance, visible_index);
	output.virtual_transition_epoch = select(
		0u,
		render.virtual_geometry_epoch.x,
		render.virtual_geometry_epoch.z != 0u,
	);
	return output;
}

@vertex
fn compact_depth_vs(
	record: Compact_Input,
	@builtin(vertex_index) vertex_index: u32,
) -> Mask_Output {
	let instance = instances[record.instance_slot];
	if (vertex_index >= meshlets[record.meshlet_index].triangle_count * 3u) {
		return discarded_mask_output();
	}
	let input = load_compact_vertex(record, vertex_index);
	var output: Mask_Output;
	output.position = render.view_projection * instance.model * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.alpha = instance.color.a;
	output.virtual_transition = virtual_coverage_for(instance, meshlets[record.meshlet_index]);
	output.virtual_transition_epoch = select(
		0u,
		render.virtual_geometry_epoch.x,
		render.virtual_geometry_epoch.z != 0u,
	);
	return output;
}

@vertex
fn compact_depth_only_vs(
	record: Compact_Input,
	@builtin(vertex_index) vertex_index: u32,
) -> Compact_Depth_Only_Output {
	let instance = instances[record.instance_slot];
	if (vertex_index >= meshlets[record.meshlet_index].triangle_count * 3u) {
		return Compact_Depth_Only_Output(vec4<f32>(2.0, 2.0, 2.0, 1.0));
	}
	let position = load_compact_position(record, vertex_index);
	return Compact_Depth_Only_Output(render.view_projection * instance.model * vec4<f32>(position, 1.0));
}

@fragment
fn mask_fs(input: Mask_Output) {
	apply_virtual_transition(
		input.position,
		input.virtual_transition,
		input.virtual_transition_epoch,
	);
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
	render_flags: vec4<f32>,
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
	meshlet_offset: u32,
	meshlet_count: u32,
	submission_mode: u32,
	compact_command_index: u32,
	compact_visible_offset: u32,
	compact_visible_capacity: u32,
	compact_shadow_pages: u32,
};

struct Meshlet_Info {
	bounds: vec4<f32>,
	cone_axis_cutoff: vec4<f32>,
	group_bounds: vec4<f32>,
	refined_bounds: vec4<f32>,
	visible_offset: u32,
	visible_capacity: u32,
	flags: u32,
	group_depth: u32,
	group_error: f32,
	refined_error: f32,
	max_depth: u32,
	virtual_geometry: u32,
	first_index: u32,
	base_vertex: u32,
	triangle_count: u32,
	identity: u32,
	page_resident: u32,
	refined_resident: u32,
	request_geometry_index: u32,
	request_geometry_generation: u32,
	group_index: u32,
	request_group_index: u32,
	request_enabled: u32,
	batch_index: u32,
	transition_start: u32,
	refined_transition_start: u32,
	has_coarse_parent: u32,
	padding: u32,
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
	predictive_camera_planes: array<vec4<f32>, 6>,
	shadow_planes: array<array<vec4<f32>, 6>, 4>,
	view_projection: mat4x4<f32>,
	hiz_view_projection: mat4x4<f32>,
	viewport: vec4<f32>,
	camera_position: vec4<f32>,
	predictive_camera_position: vec4<f32>,
	slot_count: u32,
	batch_count: u32,
	hiz_mip_count: u32,
	hiz_enabled: u32,
	shadow_visible_stride: u32,
	meshlet_enabled: u32,
	meshlet_shadow_visible_stride: u32,
	meshlet_debug_record_offset: u32,
	debug_view: u32,
	meshlet_force_enabled: u32,
	virtual_error_pixels: f32,
	projection_y: f32,
	virtual_feedback_epoch: u32,
	virtual_transition_frames: u32,
	virtual_prefetch_enabled: u32,
	meshlet_count: u32,
	occlusion_depth_scale: f32,
	occlusion_world_bias: f32,
	virtual_blend_low_scale: f32,
	virtual_blend_high_scale: f32,
	virtual_shadow_error_pixels: vec4<f32>,
};

struct Virtual_Page_Feedback {
	geometry_index: u32,
	geometry_generation: u32,
	group_index: u32,
	priority: f32,
	flags: u32,
};

struct Visibility_Counters {
	visible_instances: atomic<u32>,
	shadow_visible_instances: atomic<u32>,
	frustum_candidates: atomic<u32>,
	frustum_culled_instances: atomic<u32>,
	occlusion_culled_instances: atomic<u32>,
	lod_visible_instances: array<atomic<u32>, 4>,
	visible_meshlets: atomic<u32>,
	shadow_visible_meshlets: atomic<u32>,
	candidate_record_overflow: atomic<u32>,
	visible_record_overflow: atomic<u32>,
	shadow_record_overflow: atomic<u32>,
	frustum_culled_meshlets: atomic<u32>,
	cone_culled_meshlets: atomic<u32>,
	occlusion_culled_meshlets: atomic<u32>,
	meshlet_debug_records: atomic<u32>,
	meshlet_debug_record_overflow: atomic<u32>,
	visible_batches: atomic<u32>,
	visible_meshlet_draws: atomic<u32>,
	visible_virtual_clusters: atomic<u32>,
	visible_virtual_blend_clusters: atomic<u32>,
	virtual_rejected_clusters: atomic<u32>,
	virtual_page_request_count: atomic<u32>,
	virtual_page_prefetch_count: atomic<u32>,
	virtual_page_demand_feedback_count: atomic<u32>,
	virtual_page_touch_feedback_count: atomic<u32>,
	virtual_page_prefetch_feedback_count: atomic<u32>,
	virtual_page_demand_feedback_overflow: atomic<u32>,
	virtual_page_touch_feedback_overflow: atomic<u32>,
	virtual_page_prefetch_feedback_overflow: atomic<u32>,
	shadow_visible_meshlets_by_cascade: array<atomic<u32>, 4>,
	virtual_page_demand_feedback: array<Virtual_Page_Feedback, 32768>,
	virtual_page_touch_feedback: array<Virtual_Page_Feedback, 4096>,
	virtual_page_prefetch_feedback: array<Virtual_Page_Feedback, 4096>,
	visible_batch_words: array<atomic<u32>, 16384>,
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
@group(0) @binding(9) var<storage, read> meshlets: array<Meshlet_Info>;

fn render_debug_is_occlusion_queries() -> bool {
	return cull.debug_view == 10u;
}

fn batch_submission_mode(batch: Batch_Info) -> u32 {
	if (cull.meshlet_enabled == 0u) {
		return 0u;
	}
	if (cull.meshlet_force_enabled != 0u) {
		return 1u;
	}
	return batch.submission_mode;
}

fn batch_uses_meshlets(batch: Batch_Info) -> bool {
	return batch_submission_mode(batch) != 0u;
}

fn mark_visible_batch(batch_index: u32) -> bool {
	let word_index = batch_index >> 5u;
	let bit = 1u << (batch_index & 31u);
	let previous = atomicOr(&counters.visible_batch_words[word_index], bit);
	if ((previous & bit) == 0u) {
		atomicAdd(&counters.visible_batches, 1u);
	}
	return (previous & bit) == 0u;
}

fn world_meshlet_bounds(instance: GPU_Instance, meshlet: Meshlet_Info) -> vec4<f32> {
	let center = instance.model * vec4<f32>(meshlet.bounds.xyz, 1.0);
	let scale = max(
		max(length(instance.model[0].xyz), length(instance.model[1].xyz)),
		length(instance.model[2].xyz),
	);
	return vec4<f32>(center.xyz, meshlet.bounds.w * scale);
}

fn world_virtual_bounds(instance: GPU_Instance, bounds: vec4<f32>) -> vec4<f32> {
	let center = instance.model * vec4<f32>(bounds.xyz, 1.0);
	let scale = max(
		max(length(instance.model[0].xyz), length(instance.model[1].xyz)),
		length(instance.model[2].xyz),
	);
	return vec4<f32>(center.xyz, bounds.w * scale);
}

fn virtual_projected_error(
	instance: GPU_Instance,
	bounds: vec4<f32>,
	error: f32,
) -> f32 {
	return virtual_projected_error_from(
		instance,
		bounds,
		error,
		cull.camera_position.xyz,
	);
}

fn virtual_projected_error_from(
	instance: GPU_Instance,
	bounds: vec4<f32>,
	error: f32,
	camera_position: vec3<f32>,
) -> f32 {
	if (error > 1.0e30) {
		return error;
	}
	let world_bounds = world_virtual_bounds(instance, bounds);
	let scale = max(
		max(length(instance.model[0].xyz), length(instance.model[1].xyz)),
		length(instance.model[2].xyz),
	);
	let distance = max(
		length(world_bounds.xyz - camera_position) - world_bounds.w,
		0.0001,
	);
	return error * scale / distance * abs(cull.projection_y) * 0.5 * cull.viewport.w;
}

fn append_virtual_page_feedback(
	meshlet: Meshlet_Info,
	group_index: u32,
	priority: f32,
	flags: u32,
) {
	var feedback_index = 0u;
	if ((flags & 1u) != 0u) {
		feedback_index = atomicAdd(&counters.virtual_page_demand_feedback_count, 1u);
		if (feedback_index < 32768u) {
			counters.virtual_page_demand_feedback[feedback_index] = Virtual_Page_Feedback(
				meshlet.request_geometry_index,
				meshlet.request_geometry_generation,
				group_index,
				priority,
				flags,
			);
		} else {
			atomicAdd(&counters.virtual_page_demand_feedback_overflow, 1u);
		}
	} else if ((flags & 2u) != 0u) {
		feedback_index = atomicAdd(&counters.virtual_page_touch_feedback_count, 1u);
		if (feedback_index < 4096u) {
			counters.virtual_page_touch_feedback[feedback_index] = Virtual_Page_Feedback(
				meshlet.request_geometry_index,
				meshlet.request_geometry_generation,
				group_index,
				priority,
				flags,
			);
		} else {
			atomicAdd(&counters.virtual_page_touch_feedback_overflow, 1u);
		}
	} else {
		feedback_index = atomicAdd(&counters.virtual_page_prefetch_feedback_count, 1u);
		if (feedback_index < 4096u) {
			counters.virtual_page_prefetch_feedback[feedback_index] = Virtual_Page_Feedback(
			meshlet.request_geometry_index,
			meshlet.request_geometry_generation,
			group_index,
			priority,
			flags,
		);
		} else {
			atomicAdd(&counters.virtual_page_prefetch_feedback_overflow, 1u);
		}
	}
}

fn virtual_page_touch_sample(meshlet: Meshlet_Info, instance_slot: u32) -> bool {
	let identity_hash =
		meshlet.request_geometry_index * 1664525u ^
		meshlet.request_geometry_generation * 1013904223u ^
		meshlet.group_index * 747796405u ^
		instance_slot * 2891336453u;
	return ((identity_hash + cull.virtual_feedback_epoch) & 15u) == 0u;
}

fn virtual_frontier_progress(
	instance: GPU_Instance,
	bounds: vec4<f32>,
	error: f32,
	error_pixels: f32,
) -> f32 {
	if (error <= 0.0) {
		return 0.0;
	}
	let projected = virtual_projected_error(instance, bounds, error);
	return smoothstep(
		error_pixels * cull.virtual_blend_low_scale,
		error_pixels * cull.virtual_blend_high_scale,
		projected,
	);
}

fn cull_virtual_transition_progress(start_token: u32) -> f32 {
	if (start_token == 0u) {
		return 1.0;
	}
	let start = start_token - 1u;
	let duration = f32(max(cull.virtual_transition_frames, 1u));
	return clamp(f32(cull.virtual_feedback_epoch - start) / duration, 0.0, 1.0);
}

fn virtual_cluster_selected(
	instance: GPU_Instance,
	meshlet: Meshlet_Info,
	emit_feedback: bool,
) -> bool {
	if (meshlet.virtual_geometry == 0u) {
		return true;
	}
	if (meshlet.page_resident == 0u) {
		return false;
	}
	let group_progress = virtual_frontier_progress(
		instance,
		meshlet.group_bounds,
		meshlet.group_error,
		cull.virtual_error_pixels,
	);
	let refined_progress = virtual_frontier_progress(
		instance,
		meshlet.refined_bounds,
		meshlet.refined_error,
		cull.virtual_error_pixels,
	);
	if (group_progress > 0.0 && refined_progress > 0.0 && meshlet.refined_resident == 0u) {
		if (emit_feedback && meshlet.request_enabled != 0u) {
			atomicAdd(&counters.virtual_page_request_count, 1u);
			append_virtual_page_feedback(
				meshlet,
				meshlet.request_group_index,
				virtual_projected_error(
					instance,
					meshlet.refined_bounds,
					meshlet.refined_error,
				),
				1u,
			);
		}
		return true;
	}
	// Residency starts a bounded admission handoff; it does not immediately
	// make the coarse side expendable. Keep that parent drawable until the
	// child transition completes so the fragment shader's complementary
	// coverage intervals always have both halves available.
	return group_progress > 0.0 &&
		(refined_progress < 1.0 ||
			(meshlet.refined_transition_start != 0u &&
				cull_virtual_transition_progress(meshlet.refined_transition_start) < 1.0));
}

fn virtual_shadow_error_pixels(cascade_index: u32) -> f32 {
	return cull.virtual_shadow_error_pixels[min(cascade_index, 3u)];
}

fn virtual_shadow_cluster_selected(
	instance: GPU_Instance,
	meshlet: Meshlet_Info,
	cascade_index: u32,
) -> bool {
	if (meshlet.virtual_geometry == 0u) {
		return true;
	}
	if (meshlet.page_resident == 0u) {
		return false;
	}
	let error_pixels = virtual_shadow_error_pixels(cascade_index);
	let group_progress = virtual_frontier_progress(
		instance,
		meshlet.group_bounds,
		meshlet.group_error,
		error_pixels,
	);
	let refined_progress = virtual_frontier_progress(
		instance,
		meshlet.refined_bounds,
		meshlet.refined_error,
		error_pixels,
	);
	if (group_progress > 0.0 && refined_progress > 0.0 && meshlet.refined_resident == 0u) {
		return true;
	}
	return group_progress > 0.0 &&
		(refined_progress < 1.0 ||
			(meshlet.refined_transition_start != 0u &&
				cull_virtual_transition_progress(meshlet.refined_transition_start) < 1.0));
}

fn virtual_cluster_blended(instance: GPU_Instance, meshlet: Meshlet_Info) -> bool {
	if (meshlet.virtual_geometry == 0u) {
		return false;
	}
	if (
		(meshlet.transition_start != 0u &&
			cull_virtual_transition_progress(meshlet.transition_start) < 1.0) ||
		(meshlet.refined_transition_start != 0u &&
			cull_virtual_transition_progress(meshlet.refined_transition_start) < 1.0)
	) {
		return true;
	}
	let group_progress = virtual_frontier_progress(
		instance,
		meshlet.group_bounds,
		meshlet.group_error,
		cull.virtual_error_pixels,
	);
	let refined_progress = virtual_frontier_progress(
		instance,
		meshlet.refined_bounds,
		meshlet.refined_error,
		cull.virtual_error_pixels,
	);
	return (meshlet.has_coarse_parent != 0u && group_progress > 0.0 && group_progress < 1.0) ||
		(meshlet.refined_resident != 0u && refined_progress > 0.0 && refined_progress < 1.0);
}

fn prefetch_virtual_cluster(
	instance: GPU_Instance,
	meshlet: Meshlet_Info,
	current_frontier: bool,
) {
	if (
		cull.virtual_prefetch_enabled == 0u ||
		meshlet.virtual_geometry == 0u ||
		meshlet.page_resident == 0u ||
		meshlet.refined_resident != 0u ||
		meshlet.request_enabled == 0u ||
		meshlet.refined_error <= 0.0
	) {
		return;
	}
	if (current_frontier &&
		virtual_projected_error(instance, meshlet.refined_bounds, meshlet.refined_error) >
		cull.virtual_error_pixels
	) {
		return;
	}
	let group_over_threshold = virtual_projected_error_from(
		instance,
		meshlet.group_bounds,
		meshlet.group_error,
		cull.predictive_camera_position.xyz,
	) > cull.virtual_error_pixels;
	let predicted_error = virtual_projected_error_from(
		instance,
		meshlet.refined_bounds,
		meshlet.refined_error,
		cull.predictive_camera_position.xyz,
	);
	if (
		group_over_threshold &&
		// Start asynchronous page IO before the predicted frontier reaches the
		// visible selection threshold. The readback, file read, upload, and GPU
		// metadata refresh span several frames; waiting until 75% leaves too
		// little runway for ordinary camera motion and exposes coarse-to-fine
		// topology snaps in the current view.
		predicted_error > cull.virtual_error_pixels * 0.5 &&
		predictive_sphere_visible(world_virtual_bounds(instance, meshlet.refined_bounds))
	) {
		atomicAdd(&counters.virtual_page_prefetch_count, 1u);
		append_virtual_page_feedback(
			meshlet,
			meshlet.request_group_index,
			predicted_error,
			4u,
		);
	}
}

fn meshlet_cone_culled(
	instance: GPU_Instance,
	meshlet: Meshlet_Info,
	bounds: vec4<f32>,
) -> bool {
	if (
		instance.render_flags.z < 0.5 ||
		(meshlet.flags & 1u) != 0u ||
		meshlet.cone_axis_cutoff.w >= 1.0
	) {
		return false;
	}
	let axis = normalize(
		(instance.normal_model * vec4<f32>(meshlet.cone_axis_cutoff.xyz, 0.0)).xyz,
	);
	let camera_offset = bounds.xyz - cull.camera_position.xyz;
	let distance = length(camera_offset);
	return dot(camera_offset, axis) >=
		meshlet.cone_axis_cutoff.w * distance + bounds.w;
}

fn camera_sphere_visible(bounds: vec4<f32>) -> bool {
	for (var plane_index: u32 = 0u; plane_index < 6u; plane_index = plane_index + 1u) {
		let plane = cull.camera_planes[plane_index];
		if (dot(plane.xyz, bounds.xyz) + plane.w < -bounds.w) {
			return false;
		}
	}
	return true;
}

fn predictive_sphere_visible(bounds: vec4<f32>) -> bool {
	for (var plane_index: u32 = 0u; plane_index < 6u; plane_index = plane_index + 1u) {
		let plane = cull.predictive_camera_planes[plane_index];
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

struct Occlusion_Result {
	occluded: u32,
	tested: u32,
	mip: u32,
	padding: u32,
	query_rect: vec4<f32>,
	depths: vec4<f32>,
};

const OCCLUSION_FLOATING_POINT_BIAS = 9.536743e-7;

fn camera_sphere_occlusion(bounds: vec4<f32>) -> Occlusion_Result {
	var result: Occlusion_Result;
	if (cull.hiz_enabled == 0u || cull.hiz_mip_count == 0u) {
		return result;
	}
	let camera_offset = bounds.xyz - cull.camera_position.xyz;
	let conservative_distance = bounds.w * 4.0;
	if (dot(camera_offset, camera_offset) <= conservative_distance * conservative_distance) {
		return result;
	}
	// Project the eight corners of a cube containing the sphere. Center-plus-
	// radius projection is not conservative for large off-axis bounds: its
	// screen rectangle can miss a visible part of a cluster while sampling an
	// occluder near the center. The enclosing cube is deliberately a little
	// wider, but it guarantees that Hi-Z can only reject the complete sphere.
	var ndc_low = vec2<f32>(1.0e30);
	var ndc_high = vec2<f32>(-1.0e30);
	var nearest_depth = 1.0;
	var nearest_view_depth = 1.0e30;
	for (var corner_index = 0u; corner_index < 8u; corner_index = corner_index + 1u) {
		let corner = bounds.xyz + vec3<f32>(
			select(-bounds.w, bounds.w, (corner_index & 1u) != 0u),
			select(-bounds.w, bounds.w, (corner_index & 2u) != 0u),
			select(-bounds.w, bounds.w, (corner_index & 4u) != 0u),
		);
		let corner_clip = cull.hiz_view_projection * vec4<f32>(corner, 1.0);
		if (corner_clip.w <= 0.0001) {
			return result;
		}
		let corner_ndc = corner_clip.xyz / corner_clip.w;
		ndc_low = min(ndc_low, corner_ndc.xy);
		ndc_high = max(ndc_high, corner_ndc.xy);
		nearest_depth = min(nearest_depth, corner_ndc.z);
		nearest_view_depth = min(nearest_view_depth, corner_clip.w);
	}
	let low_px_full = cull.viewport.xy + vec2<f32>(
		(ndc_low.x * 0.5 + 0.5) * cull.viewport.z,
		(0.5 - ndc_high.y * 0.5) * cull.viewport.w,
	) - vec2<f32>(1.0);
	let high_px_full = cull.viewport.xy + vec2<f32>(
		(ndc_high.x * 0.5 + 0.5) * cull.viewport.z,
		(0.5 - ndc_low.y * 0.5) * cull.viewport.w,
	) + vec2<f32>(1.0);
	let extent = max(max(high_px_full.x - low_px_full.x, high_px_full.y - low_px_full.y), 1.0);
	let mip = min(u32(max(ceil(log2(extent)), 0.0)), cull.hiz_mip_count - 1u);
	let mip_size = vec2<i32>(textureDimensions(hiz_depth, i32(mip)));
	let scale = exp2(f32(mip));
	let low = clamp(vec2<i32>(floor(low_px_full / scale)), vec2<i32>(0), mip_size - vec2<i32>(1));
	let high = clamp(vec2<i32>(floor(high_px_full / scale)), vec2<i32>(0), mip_size - vec2<i32>(1));
	var farthest_occluder = textureLoad(hiz_depth, low, i32(mip)).x;
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, vec2<i32>(high.x, low.y), i32(mip)).x);
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, vec2<i32>(low.x, high.y), i32(mip)).x);
	farthest_occluder = max(farthest_occluder, textureLoad(hiz_depth, high, i32(mip)).x);
	let low_px = vec2<f32>(low) * scale;
	let high_px = (vec2<f32>(high) + vec2<f32>(1.0)) * scale;
	result.tested = 1u;
	result.mip = mip;
	result.query_rect = vec4<f32>(
		(low_px.x - cull.viewport.x) / cull.viewport.z * 2.0 - 1.0,
		1.0 - (low_px.y - cull.viewport.y) / cull.viewport.w * 2.0,
		(high_px.x - cull.viewport.x) / cull.viewport.z * 2.0 - 1.0,
		1.0 - (high_px.y - cull.viewport.y) / cull.viewport.w * 2.0,
	);
	result.depths = vec4<f32>(nearest_depth, farthest_occluder, f32(mip), 0.0);
	// Express the safety margin in world space, then project it at the query depth.
	// A fixed nonlinear-depth epsilon changes meaning with the camera near plane and
	// previously disabled useful occlusion when the editor camera used a 0.01 near plane.
	let world_bias = max(cull.occlusion_world_bias, bounds.w * 0.01);
	let view_depth = max(nearest_view_depth, 0.0001);
	let projected_bias =
		cull.occlusion_depth_scale * world_bias / (view_depth * view_depth);
	let depth_bias = max(projected_bias, OCCLUSION_FLOATING_POINT_BIAS);
	result.occluded = select(0u, 1u, nearest_depth > farthest_occluder + depth_bias);
	return result;
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

fn append_debug_record(
	bounds: vec4<f32>,
	query_rect: vec4<f32>,
	query_depths: vec4<f32>,
	classification: u32,
	lod_level: u32,
	meshlet_identity: u32,
) {
	if (cull.meshlet_debug_record_offset == 0u) {
		return;
	}
	let record_index = atomicAdd(&counters.meshlet_debug_records, 1u);
	let base = record_index * 16u;
	if (base + 15u >= arrayLength(&visible_instances)) {
		atomicSub(&counters.meshlet_debug_records, 1u);
		atomicAdd(&counters.meshlet_debug_record_overflow, 1u);
		return;
	}
	visible_instances[base] = bitcast<u32>(bounds.x);
	visible_instances[base + 1u] = bitcast<u32>(bounds.y);
	visible_instances[base + 2u] = bitcast<u32>(bounds.z);
	visible_instances[base + 3u] = bitcast<u32>(bounds.w);
	visible_instances[base + 4u] = bitcast<u32>(query_rect.x);
	visible_instances[base + 5u] = bitcast<u32>(query_rect.y);
	visible_instances[base + 6u] = bitcast<u32>(query_rect.z);
	visible_instances[base + 7u] = bitcast<u32>(query_rect.w);
	visible_instances[base + 8u] = bitcast<u32>(query_depths.x);
	visible_instances[base + 9u] = bitcast<u32>(query_depths.y);
	visible_instances[base + 10u] = bitcast<u32>(query_depths.z);
	visible_instances[base + 11u] = bitcast<u32>(query_depths.w);
	visible_instances[base + 12u] = classification;
	visible_instances[base + 13u] = lod_level;
	visible_instances[base + 14u] = meshlet_identity;
	visible_instances[base + 15u] = 0u;
}

fn append_captured_debug_record(
	bounds: vec4<f32>,
	query_rect: vec4<f32>,
	query_depths: vec4<f32>,
	classification: u32,
	lod_level: u32,
	meshlet_identity: u32,
) {
	let record_index = atomicAdd(&counters.meshlet_debug_records, 1u);
	let base = record_index * 16u;
	if (base + 15u >= arrayLength(&visible_instances)) {
		atomicSub(&counters.meshlet_debug_records, 1u);
		atomicAdd(&counters.meshlet_debug_record_overflow, 1u);
		return;
	}
	visible_instances[base] = bitcast<u32>(bounds.x);
	visible_instances[base + 1u] = bitcast<u32>(bounds.y);
	visible_instances[base + 2u] = bitcast<u32>(bounds.z);
	visible_instances[base + 3u] = bitcast<u32>(bounds.w);
	visible_instances[base + 4u] = bitcast<u32>(query_rect.x);
	visible_instances[base + 5u] = bitcast<u32>(query_rect.y);
	visible_instances[base + 6u] = bitcast<u32>(query_rect.z);
	visible_instances[base + 7u] = bitcast<u32>(query_rect.w);
	visible_instances[base + 8u] = bitcast<u32>(query_depths.x);
	visible_instances[base + 9u] = bitcast<u32>(query_depths.y);
	visible_instances[base + 10u] = bitcast<u32>(query_depths.z);
	visible_instances[base + 11u] = bitcast<u32>(query_depths.w);
	visible_instances[base + 12u] = classification;
	visible_instances[base + 13u] = lod_level;
	visible_instances[base + 14u] = meshlet_identity;
	visible_instances[base + 15u] = 0u;
}

fn append_meshlet_debug(
	bounds: vec4<f32>,
	classification: u32,
	lod_level: u32,
	meshlet_identity: u32,
) {
	append_debug_record(
		bounds,
		vec4<f32>(0.0),
		vec4<f32>(0.0),
		classification,
		lod_level,
		meshlet_identity,
	);
}

fn append_occlusion_debug(
	bounds: vec4<f32>,
	result: Occlusion_Result,
	lod_level: u32,
	meshlet_identity: u32,
) {
	if (result.tested == 0u) {
		return;
	}
	append_debug_record(
		bounds,
		result.query_rect,
		result.depths,
		select(7u, 8u, result.occluded != 0u),
		lod_level,
		meshlet_identity,
	);
}

fn append_batch_meshlet_debug(
	instance: GPU_Instance,
	batch: Batch_Info,
	classification: u32,
	lod_level: u32,
) {
	if (cull.meshlet_debug_record_offset == 0u || !batch_uses_meshlets(batch)) {
		return;
	}
	for (
		var local_meshlet = 0u;
		local_meshlet < batch.meshlet_count;
		local_meshlet = local_meshlet + 1u
	) {
		let meshlet_index = batch.meshlet_offset + local_meshlet;
		if (!virtual_cluster_selected(instance, meshlets[meshlet_index], false)) {
			continue;
		}
		append_meshlet_debug(
			world_meshlet_bounds(instance, meshlets[meshlet_index]),
			classification,
			lod_level,
			meshlet_index + 1u,
		);
	}
}

const COMPACT_CANDIDATE_CAMERA = 1u;
const COMPACT_CANDIDATE_PREDICTIVE = 2u;
const COMPACT_CANDIDATE_SHADOW_BASE = 4u;

fn cull_compact_candidate(invocation: vec3<u32>) {
	let slot = invocation.x;
	if (slot >= cull.slot_count) {
		return;
	}
	let instance = instances[slot];
	let lod_level = select_lod(instance);
	let batch_index = instance.batch_indices[lod_level];
	if (instance.enabled == 0u || batch_index >= cull.batch_count) {
		return;
	}
	let batch = batches[batch_index];
	if (batch_submission_mode(batch) != 2u) {
		return;
	}
	var flags = 0u;
	let camera_visible = camera_sphere_visible(instance.bounds);
	let predictive_visible =
		cull.virtual_prefetch_enabled != 0u &&
		predictive_sphere_visible(instance.bounds);
	if (camera_visible) {
		atomicAdd(&counters.frustum_candidates, 1u);
		let instance_occlusion = camera_sphere_occlusion(instance.bounds);
		if (instance_occlusion.occluded != 0u) {
			atomicAdd(&counters.occlusion_culled_instances, 1u);
			if (render_debug_is_occlusion_queries()) {
				append_occlusion_debug(instance.bounds, instance_occlusion, lod_level, 0u);
			} else if (cull.debug_view != 0u) {
				append_batch_meshlet_debug(instance, batch, 3u, lod_level);
			}
		} else {
			flags = flags | COMPACT_CANDIDATE_CAMERA;
			mark_visible_batch(batch_index);
			atomicAdd(&counters.visible_instances, 1u);
			atomicAdd(&counters.lod_visible_instances[lod_level], 1u);
		}
	} else {
		atomicAdd(&counters.frustum_culled_instances, 1u);
		if (cull.debug_view != 0u) {
			append_batch_meshlet_debug(instance, batch, 2u, lod_level);
		}
	}
	if (predictive_visible) {
		flags = flags | COMPACT_CANDIDATE_PREDICTIVE;
	}
	if (instance.render_flags.x > 0.5) {
		for (var cascade_index = 0u; cascade_index < 4u; cascade_index = cascade_index + 1u) {
			if (shadow_sphere_visible(instance.bounds, cascade_index)) {
				flags = flags | (COMPACT_CANDIDATE_SHADOW_BASE << cascade_index);
				atomicAdd(&counters.shadow_visible_instances, 1u);
			}
		}
	}
	if (flags == 0u) {
		return;
	}
	let candidate_index = atomicAdd(&shadow_indirect[batch_index].instance_count, 1u);
	if (candidate_index < batch.visible_capacity) {
		visible_instances[batch.visible_offset + candidate_index] =
			(slot & 0x00ffffffu) | (flags << 24u);
	} else {
		atomicAdd(&counters.candidate_record_overflow, 1u);
	}
}

fn cull_compact_camera_meshlet(
	instance: GPU_Instance,
	slot: u32,
	batch: Batch_Info,
	meshlet: Meshlet_Info,
	meshlet_index: u32,
	lod_level: u32,
	predictive_visible: bool,
) {
	if (!virtual_cluster_selected(instance, meshlet, true)) {
		if (meshlet.virtual_geometry != 0u) {
			atomicAdd(&counters.virtual_rejected_clusters, 1u);
			let rejected_bounds = world_meshlet_bounds(instance, meshlet);
			if (camera_sphere_visible(rejected_bounds)) {
				append_meshlet_debug(
					rejected_bounds,
					9u,
					lod_level,
					meshlet_index + 1u,
				);
			}
		}
		return;
	}
	if (predictive_visible) {
		prefetch_virtual_cluster(instance, meshlet, true);
	}
	let bounds = world_meshlet_bounds(instance, meshlet);
	if (!camera_sphere_visible(bounds)) {
		atomicAdd(&counters.frustum_culled_meshlets, 1u);
		append_meshlet_debug(bounds, 4u, lod_level, meshlet_index + 1u);
		return;
	}
	if (meshlet_cone_culled(instance, meshlet, bounds)) {
		atomicAdd(&counters.cone_culled_meshlets, 1u);
		append_meshlet_debug(bounds, 5u, lod_level, meshlet_index + 1u);
		return;
	}
	let meshlet_occlusion = camera_sphere_occlusion(bounds);
	if (render_debug_is_occlusion_queries()) {
		append_occlusion_debug(bounds, meshlet_occlusion, lod_level, meshlet_index + 1u);
	}
	if (meshlet_occlusion.occluded != 0u) {
		atomicAdd(&counters.occlusion_culled_meshlets, 1u);
		if (!render_debug_is_occlusion_queries()) {
			append_meshlet_debug(bounds, 6u, lod_level, meshlet_index + 1u);
		}
		return;
	}
	if (
		meshlet.virtual_geometry != 0u &&
		virtual_page_touch_sample(meshlet, slot)
	) {
		append_virtual_page_feedback(
			meshlet,
			meshlet.group_index,
			virtual_projected_error(instance, meshlet.group_bounds, meshlet.group_error),
			2u,
		);
	}
	let local_index = atomicAdd(
		&indirect[batch.compact_command_index].instance_count,
		1u,
	);
	if (local_index == 0u) {
		atomicAdd(&counters.visible_meshlet_draws, 1u);
	}
	if (meshlet.virtual_geometry != 0u) {
		atomicAdd(&counters.visible_virtual_clusters, 1u);
		if (virtual_cluster_blended(instance, meshlet)) {
			atomicAdd(&counters.visible_virtual_blend_clusters, 1u);
		}
	}
	let record_offset = batch.compact_visible_offset + local_index;
	if (local_index < batch.compact_visible_capacity) {
		visible_instances[record_offset * 2u] = slot;
		visible_instances[record_offset * 2u + 1u] = meshlet_index;
		atomicAdd(&counters.visible_meshlets, 1u);
	} else {
		atomicAdd(&counters.visible_record_overflow, 1u);
	}
}

fn cull_compact_shadow_meshlet(
	instance: GPU_Instance,
	slot: u32,
	batch: Batch_Info,
	meshlet: Meshlet_Info,
	meshlet_index: u32,
	cascade_index: u32,
) {
	if (!virtual_shadow_cluster_selected(instance, meshlet, cascade_index)) {
		return;
	}
	let bounds = world_meshlet_bounds(instance, meshlet);
	if (!shadow_sphere_visible(bounds, cascade_index)) {
		return;
	}
	let indirect_index = cascade_index * cull.batch_count + batch.compact_command_index;
	let local_index = atomicAdd(&indirect[indirect_index].instance_count, 1u);
	let record_offset =
		cascade_index * cull.meshlet_shadow_visible_stride +
		batch.compact_visible_offset + local_index;
	if (local_index < batch.compact_visible_capacity) {
		visible_instances[record_offset * 2u] = slot;
		visible_instances[record_offset * 2u + 1u] = meshlet_index;
		atomicAdd(&counters.shadow_visible_meshlets, 1u);
		atomicAdd(&counters.shadow_visible_meshlets_by_cascade[cascade_index], 1u);
	} else {
		atomicAdd(&counters.shadow_record_overflow, 1u);
	}
}

fn compact_cluster_batch(meshlet_index: u32) -> u32 {
	if (meshlet_index >= cull.meshlet_count) {
		return cull.batch_count;
	}
	return meshlets[meshlet_index].batch_index;
}

fn cull_compact_camera_clusters(invocation: vec3<u32>) {
	let meshlet_index = invocation.x;
	let batch_index = compact_cluster_batch(meshlet_index);
	if (batch_index >= cull.batch_count) {
		return;
	}
	let meshlet = meshlets[meshlet_index];
	let batch = batches[batch_index];
	if (batch_submission_mode(batch) != 2u) {
		return;
	}
	let candidate_count = min(
		atomicLoad(&shadow_indirect[batch_index].instance_count),
		batch.visible_capacity,
	);
	for (var candidate_index = 0u; candidate_index < candidate_count; candidate_index = candidate_index + 1u) {
		let candidate = shadow_visible_instances[batch.visible_offset + candidate_index];
		let slot = candidate & 0x00ffffffu;
		let flags = candidate >> 24u;
		let instance = instances[slot];
		let lod_level = select_lod(instance);
		if (instance.batch_indices[lod_level] != batch_index) {
			continue;
		}
		let camera_visible = (flags & COMPACT_CANDIDATE_CAMERA) != 0u;
		let predictive_visible = (flags & COMPACT_CANDIDATE_PREDICTIVE) != 0u;
		if (camera_visible) {
			cull_compact_camera_meshlet(
				instance,
				slot,
				batch,
				meshlet,
				meshlet_index,
				lod_level,
				predictive_visible,
			);
		} else if (predictive_visible) {
			prefetch_virtual_cluster(instance, meshlet, false);
		}
	}
}

fn cull_compact_shadow_clusters(invocation: vec3<u32>) {
	let meshlet_index = invocation.x;
	let cascade_index = invocation.y;
	let batch_index = compact_cluster_batch(meshlet_index);
	if (batch_index >= cull.batch_count || cascade_index >= 4u) {
		return;
	}
	let meshlet = meshlets[meshlet_index];
	let batch = batches[batch_index];
	if (batch_submission_mode(batch) != 2u || batch.compact_shadow_pages == 0u) {
		return;
	}
	let candidate_count = min(
		atomicLoad(&shadow_indirect[batch_index].instance_count),
		batch.visible_capacity,
	);
	for (var candidate_index = 0u; candidate_index < candidate_count; candidate_index = candidate_index + 1u) {
		let candidate = shadow_visible_instances[batch.visible_offset + candidate_index];
		let slot = candidate & 0x00ffffffu;
		let flags = candidate >> 24u;
		let instance = instances[slot];
		let lod_level = select_lod(instance);
		if (instance.batch_indices[lod_level] != batch_index) {
			continue;
		}
		let shadow_flag = COMPACT_CANDIDATE_SHADOW_BASE << cascade_index;
		if ((flags & shadow_flag) != 0u) {
			cull_compact_shadow_meshlet(
				instance,
				slot,
				batch,
				meshlet,
				meshlet_index,
				cascade_index,
			);
		}
	}
}

fn cull_instances(invocation: vec3<u32>, submission_mode: u32) {
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
	let active_submission_mode = batch_submission_mode(batch);
	let compact_shadow_fallback =
		batch.compact_shadow_pages == 0u &&
		submission_mode == 0u &&
		active_submission_mode == 2u;
	if (active_submission_mode != submission_mode && !compact_shadow_fallback) {
		return;
	}
	var current_camera_visible = false;
	var predictive_instance_visible = false;
	if (cascade_index == 0u) {
		current_camera_visible = camera_sphere_visible(instance.bounds);
		predictive_instance_visible =
			cull.virtual_prefetch_enabled != 0u &&
			predictive_sphere_visible(instance.bounds);
	}
	if (
		cascade_index == 0u &&
		active_submission_mode == submission_mode &&
		predictive_instance_visible &&
		!current_camera_visible &&
		batch_uses_meshlets(batch)
	) {
		for (
			var local_meshlet = 0u;
			local_meshlet < batch.meshlet_count;
			local_meshlet = local_meshlet + 1u
		) {
			prefetch_virtual_cluster(
				instance,
				meshlets[batch.meshlet_offset + local_meshlet],
				false,
			);
		}
	}
	let owns_camera = active_submission_mode == submission_mode;
	if (owns_camera && cascade_index == 0u && current_camera_visible) {
		atomicAdd(&counters.frustum_candidates, 1u);
		let instance_occlusion = camera_sphere_occlusion(instance.bounds);
		if (instance_occlusion.occluded != 0u) {
			atomicAdd(&counters.occlusion_culled_instances, 1u);
			if (render_debug_is_occlusion_queries()) {
				append_occlusion_debug(instance.bounds, instance_occlusion, lod_level, 0u);
			} else {
				append_batch_meshlet_debug(instance, batch, 3u, lod_level);
			}
		} else if (batch_uses_meshlets(batch)) {
			mark_visible_batch(batch_index);
			for (
				var local_meshlet = 0u;
				local_meshlet < batch.meshlet_count;
				local_meshlet = local_meshlet + 1u
			) {
				let meshlet_index = batch.meshlet_offset + local_meshlet;
				let meshlet = meshlets[meshlet_index];
				if (!virtual_cluster_selected(instance, meshlet, true)) {
					if (meshlet.virtual_geometry != 0u) {
						atomicAdd(&counters.virtual_rejected_clusters, 1u);
						let rejected_bounds = world_meshlet_bounds(instance, meshlet);
						if (camera_sphere_visible(rejected_bounds)) {
							append_meshlet_debug(
								rejected_bounds,
								9u,
								lod_level,
								meshlet_index + 1u,
							);
						}
					}
					continue;
				}
				if (predictive_instance_visible) {
					prefetch_virtual_cluster(instance, meshlet, true);
				}
				let bounds = world_meshlet_bounds(instance, meshlet);
				if (!camera_sphere_visible(bounds)) {
					atomicAdd(&counters.frustum_culled_meshlets, 1u);
					append_meshlet_debug(bounds, 4u, lod_level, meshlet_index + 1u);
					continue;
				}
				if (meshlet_cone_culled(instance, meshlet, bounds)) {
					atomicAdd(&counters.cone_culled_meshlets, 1u);
					append_meshlet_debug(bounds, 5u, lod_level, meshlet_index + 1u);
					continue;
				}
				let meshlet_occlusion = camera_sphere_occlusion(bounds);
				if (render_debug_is_occlusion_queries()) {
					append_occlusion_debug(
						bounds,
						meshlet_occlusion,
						lod_level,
						meshlet_index + 1u,
					);
				}
				if (meshlet_occlusion.occluded != 0u) {
					atomicAdd(&counters.occlusion_culled_meshlets, 1u);
					if (!render_debug_is_occlusion_queries()) {
						append_meshlet_debug(bounds, 6u, lod_level, meshlet_index + 1u);
					}
					continue;
				}
				if (
					meshlet.virtual_geometry != 0u &&
					virtual_page_touch_sample(meshlet, slot)
				) {
					append_virtual_page_feedback(
						meshlet,
						meshlet.group_index,
						virtual_projected_error(
							instance,
							meshlet.group_bounds,
							meshlet.group_error,
						),
						2u,
					);
				}
				var local_index = 0u;
				if (submission_mode == 2u) {
					local_index = atomicAdd(
						&indirect[batch.compact_command_index].instance_count,
						1u,
					);
				} else {
					local_index = atomicAdd(&indirect[meshlet_index].instance_count, 1u);
				}
				if (local_index == 0u) {
					atomicAdd(&counters.visible_meshlet_draws, 1u);
					if (submission_mode != 2u && meshlet.virtual_geometry != 0u) {
						atomicAdd(&counters.visible_virtual_clusters, 1u);
						if (virtual_cluster_blended(instance, meshlet)) {
							atomicAdd(&counters.visible_virtual_blend_clusters, 1u);
						}
					}
				}
				if (submission_mode == 2u && meshlet.virtual_geometry != 0u) {
					atomicAdd(&counters.visible_virtual_clusters, 1u);
					if (virtual_cluster_blended(instance, meshlet)) {
						atomicAdd(&counters.visible_virtual_blend_clusters, 1u);
					}
				}
				if (submission_mode == 2u) {
					let record_offset = batch.compact_visible_offset + local_index;
					if (local_index < batch.compact_visible_capacity) {
						visible_instances[record_offset * 2u] = slot;
						visible_instances[record_offset * 2u + 1u] = meshlet_index;
						atomicAdd(&counters.visible_meshlets, 1u);
					} else {
						atomicAdd(&counters.visible_record_overflow, 1u);
					}
				} else if (local_index < meshlet.visible_capacity) {
					visible_instances[meshlet.visible_offset + local_index] = slot;
					atomicAdd(&counters.visible_meshlets, 1u);
				} else {
					atomicAdd(&counters.visible_record_overflow, 1u);
				}
			}
			atomicAdd(&counters.visible_instances, 1u);
			atomicAdd(&counters.lod_visible_instances[lod_level], 1u);
		} else {
			let local_index = atomicAdd(&indirect[batch_index].instance_count, 1u);
			mark_visible_batch(batch_index);
			if (local_index < batch.visible_capacity) {
				visible_instances[batch.visible_offset + local_index] = slot;
				atomicAdd(&counters.visible_instances, 1u);
				atomicAdd(&counters.lod_visible_instances[lod_level], 1u);
			} else {
				atomicAdd(&counters.visible_record_overflow, 1u);
			}
		}
	} else if (owns_camera && cascade_index == 0u) {
		atomicAdd(&counters.frustum_culled_instances, 1u);
		if (cull.debug_view != 0u) {
			append_batch_meshlet_debug(instance, batch, 2u, lod_level);
		}
	}
	let owns_shadow = active_submission_mode != 2u || compact_shadow_fallback ||
		(batch.compact_shadow_pages != 0u && active_submission_mode == 2u);
	if (owns_shadow && instance.render_flags.x > 0.5 && shadow_sphere_visible(instance.bounds, cascade_index)) {
		if (batch_uses_meshlets(batch) && !compact_shadow_fallback) {
			for (
				var local_meshlet = 0u;
				local_meshlet < batch.meshlet_count;
				local_meshlet = local_meshlet + 1u
			) {
				let meshlet_index = batch.meshlet_offset + local_meshlet;
				let meshlet = meshlets[meshlet_index];
				if (!virtual_shadow_cluster_selected(instance, meshlet, cascade_index)) {
					continue;
				}
				let bounds = world_meshlet_bounds(instance, meshlet);
				if (!shadow_sphere_visible(bounds, cascade_index)) {
					continue;
				}
				var indirect_index = cascade_index * arrayLength(&meshlets) + meshlet_index;
				if (submission_mode == 2u) {
					indirect_index =
						cascade_index * cull.batch_count + batch.compact_command_index;
				}
				let local_index = atomicAdd(&shadow_indirect[indirect_index].instance_count, 1u);
				if (submission_mode == 2u) {
					let record_offset =
						cascade_index * cull.meshlet_shadow_visible_stride +
						batch.compact_visible_offset + local_index;
					if (local_index < batch.compact_visible_capacity) {
						shadow_visible_instances[record_offset * 2u] = slot;
						shadow_visible_instances[record_offset * 2u + 1u] = meshlet_index;
						atomicAdd(&counters.shadow_visible_meshlets, 1u);
						atomicAdd(&counters.shadow_visible_meshlets_by_cascade[cascade_index], 1u);
					} else {
						atomicAdd(&counters.shadow_record_overflow, 1u);
					}
				} else if (local_index < meshlet.visible_capacity) {
					shadow_visible_instances[
						cascade_index * cull.meshlet_shadow_visible_stride +
						meshlet.visible_offset + local_index
					] = slot;
					atomicAdd(&counters.shadow_visible_meshlets, 1u);
					atomicAdd(&counters.shadow_visible_meshlets_by_cascade[cascade_index], 1u);
				} else {
					atomicAdd(&counters.shadow_record_overflow, 1u);
				}
			}
			atomicAdd(&counters.shadow_visible_instances, 1u);
		} else {
			let indirect_index = cascade_index * cull.batch_count + batch_index;
			let local_index = atomicAdd(&shadow_indirect[indirect_index].instance_count, 1u);
			if (local_index < batch.visible_capacity) {
				shadow_visible_instances[
					cascade_index * cull.shadow_visible_stride + batch.visible_offset + local_index
				] = slot;
				atomicAdd(&counters.shadow_visible_instances, 1u);
			} else {
				atomicAdd(&counters.shadow_record_overflow, 1u);
			}
		}
	}
}

fn capture_meshlet_debug(invocation: vec3<u32>) {
	let slot = invocation.x;
	if (slot >= cull.slot_count) {
		return;
	}
	let instance = instances[slot];
	let lod_level = select_lod(instance);
	let batch_index = instance.batch_indices[lod_level];
	if (instance.enabled == 0u || batch_index >= cull.batch_count) {
		return;
	}
	let batch = batches[batch_index];
	if (!batch_uses_meshlets(batch)) {
		return;
	}
	let instance_visible = camera_sphere_visible(instance.bounds);
	if (!instance_visible && cull.debug_view == 0u) {
		return;
	}
	let instance_occlusion = camera_sphere_occlusion(instance.bounds);
	for (
		var local_meshlet = 0u;
		local_meshlet < batch.meshlet_count;
		local_meshlet = local_meshlet + 1u
	) {
		let meshlet_index = batch.meshlet_offset + local_meshlet;
		let meshlet = meshlets[meshlet_index];
		let bounds = world_meshlet_bounds(instance, meshlet);
		if (!instance_visible) {
			if (virtual_cluster_selected(instance, meshlet, false)) {
				append_captured_debug_record(
					bounds,
					vec4<f32>(0.0),
					vec4<f32>(0.0),
					2u,
					lod_level,
					meshlet_index + 1u,
				);
			}
			continue;
		}
		if (instance_occlusion.occluded != 0u) {
			if (virtual_cluster_selected(instance, meshlet, false)) {
				append_captured_debug_record(
					bounds,
					instance_occlusion.query_rect,
					instance_occlusion.depths,
					select(3u, 8u, render_debug_is_occlusion_queries()),
					lod_level,
					meshlet_index + 1u,
				);
			}
			continue;
		}
		if (!virtual_cluster_selected(instance, meshlet, true)) {
			if (meshlet.virtual_geometry != 0u && camera_sphere_visible(bounds)) {
				append_captured_debug_record(
					bounds,
					vec4<f32>(0.0),
					vec4<f32>(0.0),
					9u,
					lod_level,
					meshlet_index + 1u,
				);
			}
			continue;
		}
		if (!camera_sphere_visible(bounds)) {
			append_captured_debug_record(
				bounds,
				vec4<f32>(0.0),
				vec4<f32>(0.0),
				4u,
				lod_level,
				meshlet_index + 1u,
			);
			continue;
		}
		if (meshlet_cone_culled(instance, meshlet, bounds)) {
			append_captured_debug_record(
				bounds,
				vec4<f32>(0.0),
				vec4<f32>(0.0),
				5u,
				lod_level,
				meshlet_index + 1u,
			);
			continue;
		}
		let meshlet_occlusion = camera_sphere_occlusion(bounds);
		if (render_debug_is_occlusion_queries() || meshlet_occlusion.occluded != 0u) {
			append_captured_debug_record(
				bounds,
				meshlet_occlusion.query_rect,
				meshlet_occlusion.depths,
				select(6u, select(7u, 8u, meshlet_occlusion.occluded != 0u), render_debug_is_occlusion_queries()),
				lod_level,
				meshlet_index + 1u,
			);
		}
	}
}

@compute @workgroup_size(64)
fn cull_classic_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	cull_instances(invocation, 0u);
}

@compute @workgroup_size(64)
fn capture_meshlet_debug_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	capture_meshlet_debug(invocation);
}

@compute @workgroup_size(64)
fn cull_meshlet_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	cull_instances(invocation, 1u);
}

@compute @workgroup_size(64)
fn cull_compact_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	cull_compact_candidate(invocation);
}

@compute @workgroup_size(64)
fn cull_compact_cluster_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	cull_compact_camera_clusters(invocation);
}

@compute @workgroup_size(64)
fn cull_compact_shadow_cluster_instances(@builtin(global_invocation_id) invocation: vec3<u32>) {
	cull_compact_shadow_clusters(invocation);
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

WGPU_HIZ_DEBUG_SHADER :: `
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
	shadow_cascade_texel_sizes: vec4<f32>,
	shadow_map_parameters: vec4<f32>,
	debug: vec4<u32>,
	camera_clip: vec4<f32>,
};

@group(0) @binding(0) var<uniform> render: Render_Uniform;
@group(0) @binding(1) var hiz_depth: texture_2d<f32>;

struct Fullscreen_Output {
	@builtin(position) position: vec4<f32>,
};

@vertex
fn fullscreen_vs(@builtin(vertex_index) index: u32) -> Fullscreen_Output {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(3.0, -1.0),
		vec2<f32>(-1.0, 3.0),
	);
	var output: Fullscreen_Output;
	output.position = vec4<f32>(positions[index], 0.0, 1.0);
	return output;
}

fn depth_color(depth: f32) -> vec3<f32> {
	let near_weight = pow(clamp(1.0 - depth, 0.0, 1.0), 0.35);
	let far_color = vec3<f32>(0.015, 0.025, 0.055);
	let middle_color = vec3<f32>(0.08, 0.38, 0.52);
	let near_color = vec3<f32>(0.44, 1.0, 0.72);
	return mix(
		mix(far_color, middle_color, min(near_weight * 2.0, 1.0)),
		near_color,
		max(near_weight * 2.0 - 1.0, 0.0),
	);
}

@fragment
fn hiz_debug_fs(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	let mip_count = textureNumLevels(hiz_depth);
	let mip = min(render.debug.z, mip_count - 1u);
	let scale = 1u << mip;
	let mip_size = vec2<u32>(textureDimensions(hiz_depth, i32(mip)));
	let pixel = min(vec2<u32>(input.position.xy) / scale, mip_size - vec2<u32>(1u));
	let depth = textureLoad(hiz_depth, vec2<i32>(pixel), i32(mip)).x;
	var color = depth_color(depth);
	if (mip > 0u) {
		let local = vec2<u32>(input.position.xy) & vec2<u32>(scale - 1u);
		let edge = local.x == 0u || local.y == 0u;
		color = select(color, color * 0.42, edge);
	}
	return vec4<f32>(color, 1.0);
}
`

WGPU_MESHLET_DEBUG_SHADER :: `
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
	shadow_cascade_texel_sizes: vec4<f32>,
	shadow_map_parameters: vec4<f32>,
	debug: vec4<u32>,
	camera_clip: vec4<f32>,
};

struct Meshlet_Debug_Record {
	bounds: vec4<f32>,
	query_rect: vec4<f32>,
	query_depths: vec4<f32>,
	classification: u32,
	lod_level: u32,
	meshlet_identity: u32,
	padding: u32,
};

@group(0) @binding(0) var<uniform> render: Render_Uniform;
@group(0) @binding(1) var<storage, read> records: array<Meshlet_Debug_Record>;

struct Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) @interpolate(flat) classification: u32,
};

@vertex
fn debug_vs(
	@builtin(vertex_index) vertex_index: u32,
	@builtin(instance_index) instance_index: u32,
) -> Vertex_Output {
	let record = records[instance_index];
	var output: Vertex_Output;
	output.classification = record.classification;
	if (render.debug.x == 10u) {
		if (vertex_index < 144u) {
			output.position = vec4<f32>(-2.0, -2.0, 0.0, 1.0);
			return output;
		}
		let rectangle_vertex = vertex_index - 144u;
		let corner_indices = array<u32, 8>(0u, 1u, 1u, 2u, 2u, 3u, 3u, 0u);
		let corner = corner_indices[rectangle_vertex];
		let x = select(record.query_rect.x, record.query_rect.z, corner == 1u || corner == 2u);
		let y = select(record.query_rect.y, record.query_rect.w, corner >= 2u);
		output.position = vec4<f32>(x, y, 0.0, 1.0);
		return output;
	}
	if (vertex_index >= 144u) {
		output.position = vec4<f32>(-2.0, -2.0, 0.0, 1.0);
		return output;
	}
	let circle_vertex = vertex_index % 48u;
	let circle = vertex_index / 48u;
	let segment = circle_vertex / 2u;
	let endpoint = circle_vertex & 1u;
	let angle = 6.28318530718 * f32(segment + endpoint) / 24.0;
	let sine = sin(angle);
	let cosine = cos(angle);
	var unit = vec3<f32>(cosine, sine, 0.0);
	if (circle == 1u) {
		unit = vec3<f32>(cosine, 0.0, sine);
	} else if (circle == 2u) {
		unit = vec3<f32>(0.0, cosine, sine);
	}
	output.position = render.view_projection *
		vec4<f32>(record.bounds.xyz + unit * record.bounds.w, 1.0);
	return output;
}

@fragment
fn debug_fs(input: Vertex_Output) -> @location(0) vec4<f32> {
	var color = vec3<f32>(1.0, 0.18, 0.18);
	switch input.classification {
		case 2u: {
			color = vec3<f32>(1.0, 0.22, 0.16);
		}
		case 3u: {
			color = vec3<f32>(0.78, 0.25, 1.0);
		}
		case 4u: {
			color = vec3<f32>(1.0, 0.62, 0.12);
		}
		case 5u: {
			color = vec3<f32>(0.14, 0.72, 1.0);
		}
		case 6u: {
			color = vec3<f32>(1.0, 0.18, 0.68);
		}
		case 7u: {
			color = vec3<f32>(0.24, 0.95, 0.68);
		}
		case 8u: {
			color = vec3<f32>(1.0, 0.18, 0.58);
		}
		default: {}
	}
	return vec4<f32>(color, 1.0);
}
`
