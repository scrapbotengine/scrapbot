package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:slice"
import "core:strings"
import "vendor:wgpu"

WGPU_CUSTOM_SHADER_PRELUDE :: `
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
struct Material_Uniform {
	pbr_factors: vec4<f32>,
	flags: vec4<f32>,
	alpha: vec4<f32>,
	shader_parameters: array<vec4<f32>, 4>,
};
struct Shadow_Cascade_Uniform {
	index: u32,
	padding_0: u32,
	padding_1: u32,
	padding_2: u32,
};
struct Custom_Uniform {
	viewport: vec4<f32>,
	time: vec4<f32>,
};
struct Spectral_Surface_Uniform {
	parameters: vec4<f32>,
	wind_time: vec4<f32>,
	shape: vec4<f32>,
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
@group(0) @binding(0) var<uniform> render: Render_Uniform;
@group(0) @binding(3) var<storage, read> instances: array<GPU_Instance>;
@group(0) @binding(4) var<storage, read> visible_instances: array<u32>;
@group(0) @binding(9) var<uniform> shadow_cascade: Shadow_Cascade_Uniform;
@group(1) @binding(0) var base_color_texture: texture_2d<f32>;
@group(1) @binding(1) var base_color_sampler: sampler;
@group(1) @binding(6) var<uniform> material: Material_Uniform;
@group(2) @binding(1) var scrapbot_specular_environment: texture_cube<f32>;
@group(2) @binding(2) var scrapbot_environment_sampler: sampler;
@group(2) @binding(3) var<uniform> scrapbot_environment: Environment_Uniform;
@group(3) @binding(0) var scrapbot_opaque_color: texture_2d<f32>;
@group(3) @binding(1) var scrapbot_linear_sampler: sampler;
@group(3) @binding(2) var scrapbot_opaque_depth: texture_depth_2d;
@group(3) @binding(3) var<uniform> scrapbot_custom: Custom_Uniform;
@group(3) @binding(4) var<storage, read> scrapbot_spectral_field: array<vec4<f32>>;
@group(3) @binding(5) var<uniform> scrapbot_spectral: Spectral_Surface_Uniform;

struct Vertex_Input {
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
	@location(3) tangent: vec4<f32>,
};
struct Scrapbot_Vertex {
	position: vec3<f32>,
	normal: vec3<f32>,
	uv: vec2<f32>,
	tangent: vec4<f32>,
	model: mat4x4<f32>,
	normal_model: mat4x4<f32>,
};
struct Scrapbot_Fragment {
	world_position: vec3<f32>,
	world_normal: vec3<f32>,
	uv: vec2<f32>,
	screen_uv: vec2<f32>,
	scene_uv: vec2<f32>,
	view_direction: vec3<f32>,
	base_color: vec4<f32>,
	view_depth: f32,
	fragment_depth: f32,
	scene_depth: f32,
};
struct Scrapbot_Surface {
	color: vec4<f32>,
	normal: vec3<f32>,
	roughness: f32,
	indirect_diffuse: vec3<f32>,
	bloom: f32,
};

fn scrapbot_parameter(index: u32) -> vec4<f32> {
	return material.shader_parameters[min(index, 3u)];
}
fn scrapbot_time_seconds() -> f32 { return scrapbot_custom.time.x; }
fn scrapbot_delta_seconds() -> f32 { return scrapbot_custom.time.y; }
fn scrapbot_frame_index() -> f32 { return scrapbot_custom.time.z; }
struct Scrapbot_Spectral_Surface {
	displacement: vec3<f32>,
	normal: vec3<f32>,
	crest: f32,
};
fn scrapbot_spectral_sample_index(x: u32, y: u32) -> vec4<f32> {
	return scrapbot_spectral_field[((y & 63u) * 64u + (x & 63u)) * 2u];
}
fn scrapbot_spectral_normal_index(x: u32, y: u32) -> vec3<f32> {
	return scrapbot_spectral_field[((y & 63u) * 64u + (x & 63u)) * 2u + 1u].xyz;
}
fn scrapbot_spectral_sample(world_xz: vec2<f32>) -> vec4<f32> {
	if (scrapbot_spectral.parameters.x < 0.5) { return vec4<f32>(0.0); }
	let grid = fract(world_xz / max(scrapbot_spectral.parameters.y, 0.001)) * 64.0;
	let base = vec2<u32>(floor(grid));
	let blend = fract(grid);
	let s00 = scrapbot_spectral_sample_index(base.x, base.y);
	let s10 = scrapbot_spectral_sample_index(base.x + 1u, base.y);
	let s01 = scrapbot_spectral_sample_index(base.x, base.y + 1u);
	let s11 = scrapbot_spectral_sample_index(base.x + 1u, base.y + 1u);
	return mix(mix(s00, s10, blend.x), mix(s01, s11, blend.x), blend.y);
}
fn scrapbot_spectral_displacement(world_xz: vec2<f32>) -> vec3<f32> {
	return scrapbot_spectral_sample(world_xz).xyz;
}
fn scrapbot_spectral_normal(world_xz: vec2<f32>) -> vec3<f32> {
	if (scrapbot_spectral.parameters.x < 0.5) { return vec3<f32>(0.0, 1.0, 0.0); }
	let grid = fract(world_xz / max(scrapbot_spectral.parameters.y, 0.001)) * 64.0;
	let base = vec2<u32>(floor(grid));
	let blend = fract(grid);
	let n00 = scrapbot_spectral_normal_index(base.x, base.y);
	let n10 = scrapbot_spectral_normal_index(base.x + 1u, base.y);
	let n01 = scrapbot_spectral_normal_index(base.x, base.y + 1u);
	let n11 = scrapbot_spectral_normal_index(base.x + 1u, base.y + 1u);
	return normalize(mix(mix(n00, n10, blend.x), mix(n01, n11, blend.x), blend.y));
}
fn scrapbot_spectral_crest(world_xz: vec2<f32>) -> f32 {
	return scrapbot_spectral_sample(world_xz).w;
}
fn scrapbot_spectral_surface(world_xz: vec2<f32>) -> Scrapbot_Spectral_Surface {
	if (scrapbot_spectral.parameters.x < 0.5) {
		return Scrapbot_Spectral_Surface(vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0), 0.0);
	}
	let center = scrapbot_spectral_sample(world_xz);
	return Scrapbot_Spectral_Surface(center.xyz, scrapbot_spectral_normal(world_xz), center.w);
}
fn scrapbot_world_vector_to_object(input: Scrapbot_Vertex, world_vector: vec3<f32>) -> vec3<f32> {
	return (transpose(input.normal_model) * vec4<f32>(world_vector, 0.0)).xyz;
}
fn scrapbot_world_normal_to_object(input: Scrapbot_Vertex, world_normal: vec3<f32>) -> vec3<f32> {
	return normalize((transpose(input.model) * vec4<f32>(world_normal, 0.0)).xyz);
}
fn scrapbot_pixel_size() -> vec2<f32> { return vec2<f32>(1.0) / max(scrapbot_custom.viewport.zw, vec2<f32>(1.0)); }
fn scrapbot_scene_pixel_size() -> vec2<f32> {
	return vec2<f32>(1.0) / max(vec2<f32>(textureDimensions(scrapbot_opaque_depth)), vec2<f32>(1.0));
}
fn scrapbot_scene_uv(local_uv: vec2<f32>) -> vec2<f32> {
	return (scrapbot_custom.viewport.xy + local_uv * scrapbot_custom.viewport.zw) * scrapbot_scene_pixel_size();
}
fn scrapbot_scene_uv_valid(uv: vec2<f32>) -> bool {
	let pixel = scrapbot_scene_pixel_size();
	let minimum = scrapbot_custom.viewport.xy * pixel + pixel * 0.5;
	let maximum = (scrapbot_custom.viewport.xy + scrapbot_custom.viewport.zw) * pixel - pixel * 0.5;
	return all(uv >= minimum) && all(uv <= maximum);
}
fn scrapbot_scene_color(uv: vec2<f32>) -> vec3<f32> {
	return textureSampleLevel(scrapbot_opaque_color, scrapbot_linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}
fn scrapbot_scene_depth(uv: vec2<f32>) -> f32 {
	let dimensions = vec2<i32>(textureDimensions(scrapbot_opaque_depth));
	let pixel = clamp(vec2<i32>(uv * vec2<f32>(dimensions)), vec2<i32>(0), dimensions - vec2<i32>(1));
	return textureLoad(scrapbot_opaque_depth, pixel, 0);
}
fn scrapbot_scene_stable_uv(uv: vec2<f32>) -> vec2<f32> {
	let dimensions = vec2<i32>(textureDimensions(scrapbot_opaque_depth));
	let maximum = dimensions - vec2<i32>(1);
	let center = clamp(vec2<i32>(uv * vec2<f32>(dimensions)), vec2<i32>(0), maximum);
	let offsets = array<vec2<i32>, 4>(
		vec2<i32>(-1, 0),
		vec2<i32>(1, 0),
		vec2<i32>(0, -1),
		vec2<i32>(0, 1),
	);
	var nearest_pixel = center;
	var nearest_depth = textureLoad(scrapbot_opaque_depth, center, 0);
	for (var index = 0u; index < 4u; index = index + 1u) {
		let candidate = clamp(center + offsets[index], vec2<i32>(0), maximum);
		let candidate_depth = textureLoad(scrapbot_opaque_depth, candidate, 0);
		if (candidate_depth < nearest_depth) {
			nearest_depth = candidate_depth;
			nearest_pixel = candidate;
		}
	}
	return (vec2<f32>(nearest_pixel) + vec2<f32>(0.5)) / vec2<f32>(dimensions);
}
fn scrapbot_view_depth(device_depth: f32) -> f32 {
	let near_plane = max(render.camera_clip.x, 0.0001);
	let far_plane = max(render.camera_clip.y, near_plane + 0.0001);
	return near_plane * far_plane / max(far_plane - device_depth * (far_plane - near_plane), 0.0001);
}
fn scrapbot_scene_view_depth(uv: vec2<f32>) -> f32 {
	return scrapbot_view_depth(scrapbot_scene_depth(uv));
}
fn scrapbot_rotate_environment(direction: vec3<f32>) -> vec3<f32> {
	let c = cos(scrapbot_environment.rotation);
	let s = sin(scrapbot_environment.rotation);
	return vec3<f32>(c * direction.x - s * direction.z, direction.y, s * direction.x + c * direction.z);
}
fn scrapbot_environment_reflection(direction: vec3<f32>, roughness: f32) -> vec3<f32> {
	if (scrapbot_environment.enabled > 0.5) {
		return textureSampleLevel(
			scrapbot_specular_environment,
			scrapbot_environment_sampler,
			scrapbot_rotate_environment(normalize(direction)),
			clamp(roughness, 0.0, 1.0) * scrapbot_environment.max_specular_lod,
		).rgb * scrapbot_environment.intensity * scrapbot_environment.reflection_intensity;
	}
	let reflected_direction = normalize(direction);
	let roughness_blur = clamp(roughness * roughness, 0.0, 1.0);
	let horizon = pow(clamp(reflected_direction.y * 0.5 + 0.5, 0.0, 1.0), 0.35);
	let average_sky = mix(
		vec3<f32>(0.003, 0.006, 0.018),
		scrapbot_environment.atmosphere_sky_tint.rgb,
		0.62,
	);
	let average_ground = scrapbot_environment.atmosphere_ground_color.rgb * 0.32;
	var radiance = mix(
		scrapbot_environment.atmosphere_ground_color.rgb,
		scrapbot_environment.atmosphere_sky_tint.rgb,
		horizon,
	);
	radiance = mix(radiance, mix(average_ground, average_sky, 0.62), roughness_blur * 0.65);
	let sun_direction_length = length(scrapbot_environment.sun_direction_intensity.xyz);
	if (
		sun_direction_length > 0.0001 &&
		scrapbot_environment.sun_direction_intensity.w > 0.0
	) {
		let sun_direction = scrapbot_environment.sun_direction_intensity.xyz / sun_direction_length;
		let sun_size = clamp(scrapbot_environment.atmosphere_parameters.w, 0.1, 10.0);
		let sun_alignment = max(dot(reflected_direction, sun_direction), 0.0);
		let sun_exponent = mix(1024.0, 4.0, roughness_blur) / sun_size;
		let sun_energy = mix(6.0, 0.18, roughness_blur);
		radiance +=
			scrapbot_environment.sun_color.rgb *
			scrapbot_environment.sun_direction_intensity.w *
			pow(sun_alignment, sun_exponent) *
			sun_energy;
	}
	return max(radiance, vec3<f32>(0.0)) *
		render.ambient.w *
		scrapbot_environment.reflection_intensity;
}
`

WGPU_CUSTOM_SHADER_FOOTER :: `
struct Custom_Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) world_position: vec3<f32>,
	@location(1) world_normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
	@location(3) color: vec4<f32>,
	@location(4) view_depth: f32,
};
struct Custom_Fragment_Output {
	@location(0) color: vec4<f32>,
	@location(1) surface: vec4<f32>,
	@location(2) indirect_diffuse: vec4<f32>,
};
fn custom_vertex(input: Vertex_Input, instance: GPU_Instance) -> Scrapbot_Vertex {
	return scrapbot_vertex(Scrapbot_Vertex(input.position, input.normal, input.uv, input.tangent, instance.model, instance.normal_model));
}
fn custom_position(input: Vertex_Input, instance: GPU_Instance) -> vec4<f32> {
	let vertex = custom_vertex(input, instance);
	return instance.model * vec4<f32>(vertex.position, 1.0);
}
fn custom_vertex_output(input: Vertex_Input, instance: GPU_Instance) -> Custom_Vertex_Output {
	let vertex = custom_vertex(input, instance);
	let world = instance.model * vec4<f32>(vertex.position, 1.0);
	var output: Custom_Vertex_Output;
	output.position = render.view_projection * world;
	output.world_position = world.xyz;
	output.world_normal = normalize((instance.normal_model * vec4<f32>(vertex.normal, 0.0)).xyz);
	output.uv = vertex.uv;
	output.color = instance.color;
	output.view_depth = -(render.view * world).z;
	return output;
}
@vertex fn vs_main(input: Vertex_Input, @builtin(instance_index) visible_index: u32) -> Custom_Vertex_Output {
	return custom_vertex_output(input, instances[visible_instances[visible_index]]);
}
fn octahedral_encode(direction: vec3<f32>) -> vec2<f32> {
	let denominator = abs(direction.x) + abs(direction.y) + abs(direction.z);
	var encoded = direction.xy / max(denominator, 0.000001);
	if (direction.z < 0.0) { encoded = (vec2<f32>(1.0) - abs(encoded.yx)) * sign(encoded); }
	return encoded;
}
@fragment fn fs_main(input: Custom_Vertex_Output) -> Custom_Fragment_Output {
	let screen_uv = (input.position.xy - scrapbot_custom.viewport.xy) / scrapbot_custom.viewport.zw;
	let scene_uv = scrapbot_scene_uv(screen_uv);
	let texture_color = textureSample(base_color_texture, base_color_sampler, input.uv) * input.color;
	let fragment = Scrapbot_Fragment(
		input.world_position,
		normalize(input.world_normal),
		input.uv,
		screen_uv,
		scene_uv,
		normalize(render.camera_position.xyz - input.world_position),
		texture_color,
		input.view_depth,
		input.position.z,
		scrapbot_scene_depth(scene_uv),
	);
	let result = scrapbot_fragment(fragment);
	var output: Custom_Fragment_Output;
	output.color = vec4<f32>(result.color.rgb, select(clamp(result.bloom, 0.0, 1.0), clamp(result.color.a, 0.0, 1.0), material.alpha.z > 0.5));
	output.surface = vec4<f32>(octahedral_encode(normalize(result.normal)) * 0.5 + vec2<f32>(0.5), clamp(result.roughness, 0.0, 1.0), 1.0);
	output.indirect_diffuse = vec4<f32>(max(result.indirect_diffuse, vec3<f32>(0.0)), 1.0);
	return output;
}
`

WGPU_SPECTRAL_SURFACE_SIZE :: u32(64)
WGPU_SPECTRAL_SURFACE_TEXEL_COUNT :: u64(64 * 64)
WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT :: u64(2)

WGPU_SPECTRAL_SURFACE_SHADER :: `
struct Spectral_Surface_Uniform {
	parameters: vec4<f32>,
	wind_time: vec4<f32>,
	shape: vec4<f32>,
};
struct Spectral_Value {
	height: vec2<f32>,
	displacement_x: vec2<f32>,
	displacement_z: vec2<f32>,
	padding: vec2<f32>,
};
@group(0) @binding(0) var<uniform> spectral: Spectral_Surface_Uniform;
@group(0) @binding(1) var<storage, read_write> intermediate: array<Spectral_Value>;
@group(0) @binding(2) var<storage, read_write> spatial: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read_write> field: array<vec4<f32>>;

var<workgroup> fft_a: array<Spectral_Value, 64>;
var<workgroup> fft_b: array<Spectral_Value, 64>;

fn complex_multiply(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
	return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn spectral_add(a: Spectral_Value, b: Spectral_Value) -> Spectral_Value {
	return Spectral_Value(
		a.height + b.height,
		a.displacement_x + b.displacement_x,
		a.displacement_z + b.displacement_z,
		vec2<f32>(0.0),
	);
}

fn spectral_scale(value: Spectral_Value, scale: f32) -> Spectral_Value {
	return Spectral_Value(
		value.height * scale,
		value.displacement_x * scale,
		value.displacement_z * scale,
		vec2<f32>(0.0),
	);
}

fn spectral_twiddle(value: Spectral_Value, twiddle: vec2<f32>) -> Spectral_Value {
	return Spectral_Value(
		complex_multiply(value.height, twiddle),
		complex_multiply(value.displacement_x, twiddle),
		complex_multiply(value.displacement_z, twiddle),
		vec2<f32>(0.0),
	);
}

fn bit_reverse_6(value: u32) -> u32 {
	var result = 0u;
	for (var bit = 0u; bit < 6u; bit = bit + 1u) {
		result = (result << 1u) | ((value >> bit) & 1u);
	}
	return result;
}

fn hash_u32(value: u32) -> u32 {
	var result = value;
	result = (result ^ (result >> 16u)) * 2246822519u;
	result = (result ^ (result >> 13u)) * 3266489917u;
	return result ^ (result >> 16u);
}

fn gaussian(seed: u32) -> vec2<f32> {
	let first = max((f32(hash_u32(seed)) + 1.0) / 4294967297.0, 0.000001);
	let second = (f32(hash_u32(seed ^ 0x9e3779b9u)) + 0.5) / 4294967296.0;
	let radius = sqrt(-2.0 * log(first));
	let angle = 6.28318530718 * second;
	return radius * vec2<f32>(cos(angle), sin(angle));
}

fn signed_frequency(index: u32) -> f32 {
	return select(f32(index), f32(index) - 64.0, index > 32u);
}

fn initial_spectrum(x: u32, y: u32) -> vec2<f32> {
	let patch_size = max(spectral.parameters.y, 16.0);
	let wave = vec2<f32>(signed_frequency(x), signed_frequency(y)) *
		(6.28318530718 / patch_size);
	let wave_squared = dot(wave, wave);
	if (wave_squared < 0.000001) { return vec2<f32>(0.0); }
	let wave_length = sqrt(wave_squared);
	let direction = wave / wave_length;
	let wind = normalize(spectral.wind_time.xy);
	let largest_wave = spectral.parameters.z * spectral.parameters.z / 9.81;
	let alignment = dot(direction, wind);
	let opposing_attenuation = select(0.18, 1.0, alignment >= 0.0);
	let damping_length = largest_wave * spectral.wind_time.w;
	let phillips = 0.0005 * spectral.parameters.w *
		exp(-1.0 / max(wave_squared * largest_wave * largest_wave, 0.000001)) /
		(wave_squared * wave_squared) * alignment * alignment * opposing_attenuation *
		exp(-wave_squared * damping_length * damping_length);
	let delta_wave = 6.28318530718 / patch_size;
	return gaussian(x * 1664525u ^ y * 1013904223u ^ 0x7f4a7c15u) *
		sqrt(max(phillips, 0.0) * 0.5) * delta_wave;
}

fn evolved_spectrum(x: u32, y: u32) -> vec2<f32> {
	let patch_size = max(spectral.parameters.y, 16.0);
	let wave = vec2<f32>(signed_frequency(x), signed_frequency(y)) *
		(6.28318530718 / patch_size);
	let omega = sqrt(9.81 * length(wave));
	let phase = omega * spectral.wind_time.z;
	let rotation = vec2<f32>(cos(phase), sin(phase));
	let opposite_x = (64u - x) & 63u;
	let opposite_y = (64u - y) & 63u;
	let h0 = initial_spectrum(x, y);
	let h0_opposite = initial_spectrum(opposite_x, opposite_y);
	return complex_multiply(h0, rotation) +
		complex_multiply(vec2<f32>(h0_opposite.x, -h0_opposite.y), vec2<f32>(rotation.x, -rotation.y));
}

fn evolved_spectral_value(x: u32, y: u32) -> Spectral_Value {
	let height = evolved_spectrum(x, y);
	let wave = vec2<f32>(signed_frequency(x), signed_frequency(y)) *
		(6.28318530718 / max(spectral.parameters.y, 16.0));
	let wave_length = length(wave);
	var direction = vec2<f32>(0.0);
	if (wave_length > 0.000001) {
		direction = wave / wave_length;
	}
	// Frequency-domain horizontal orbital displacement is Tessendorf's
	// spectral counterpart to Gerstner-wave choppiness.
	let choppiness = clamp(spectral.shape.x, 0.0, 1.0);
	let displacement_x = complex_multiply(height, vec2<f32>(0.0, -direction.x * choppiness));
	let displacement_z = complex_multiply(height, vec2<f32>(0.0, -direction.y * choppiness));
	return Spectral_Value(height, displacement_x, displacement_z, vec2<f32>(0.0));
}

fn fft_stage(local_index: u32, stage: u32) {
	let span = 1u << (stage + 1u);
	let half_span = span >> 1u;
	let block = local_index / span;
	let lane = local_index & (span - 1u);
	let pair_lane = lane & (half_span - 1u);
	let even_index = block * span + pair_lane;
	let odd_index = even_index + half_span;
	let angle = 6.28318530718 * f32(pair_lane) / f32(span);
	let twiddle = vec2<f32>(cos(angle), sin(angle));
	var even: Spectral_Value;
	var odd: Spectral_Value;
	if ((stage & 1u) == 0u) {
		even = fft_a[even_index];
		odd = fft_a[odd_index];
		fft_b[local_index] = spectral_add(
			even,
			spectral_scale(spectral_twiddle(odd, twiddle), select(-1.0, 1.0, lane < half_span)),
		);
	} else {
		even = fft_b[even_index];
		odd = fft_b[odd_index];
		fft_a[local_index] = spectral_add(
			even,
			spectral_scale(spectral_twiddle(odd, twiddle), select(-1.0, 1.0, lane < half_span)),
		);
	}
}

@compute @workgroup_size(64)
fn horizontal(
	@builtin(local_invocation_id) local_id: vec3<u32>,
	@builtin(workgroup_id) group_id: vec3<u32>,
) {
	let local_index = local_id.x;
	let row = group_id.y;
	fft_a[local_index] = evolved_spectral_value(bit_reverse_6(local_index), row);
	workgroupBarrier();
	for (var stage = 0u; stage < 6u; stage = stage + 1u) {
		fft_stage(local_index, stage);
		workgroupBarrier();
	}
	intermediate[row * 64u + local_index] = fft_a[local_index];
}

@compute @workgroup_size(64)
fn vertical(
	@builtin(local_invocation_id) local_id: vec3<u32>,
	@builtin(workgroup_id) group_id: vec3<u32>,
) {
	let local_index = local_id.x;
	let column = group_id.x;
	fft_a[local_index] = intermediate[bit_reverse_6(local_index) * 64u + column];
	workgroupBarrier();
	for (var stage = 0u; stage < 6u; stage = stage + 1u) {
		fft_stage(local_index, stage);
		workgroupBarrier();
	}
	let value = fft_a[local_index];
	spatial[local_index * 64u + column] = vec4<f32>(
		value.displacement_x.x,
		value.height.x,
		value.displacement_z.x,
		0.0,
	);
}

fn spatial_sample(x: u32, y: u32) -> vec3<f32> {
	return spatial[(y & 63u) * 64u + (x & 63u)].xyz;
}

@compute @workgroup_size(8, 8)
fn finalize(@builtin(global_invocation_id) global_id: vec3<u32>) {
	if (global_id.x >= 64u || global_id.y >= 64u) { return; }
	let x = global_id.x;
	let y = global_id.y;
	let center = spatial_sample(x, y);
	let left = spatial_sample(x - 1u, y);
	let right = spatial_sample(x + 1u, y);
	let back = spatial_sample(x, y - 1u);
	let front = spatial_sample(x, y + 1u);
	let spacing = max(spectral.parameters.y, 16.0) / 64.0;
	let inverse_span = 1.0 / (2.0 * spacing);
	let displacement_x_x = (right.x - left.x) * inverse_span;
	let displacement_x_z = (front.x - back.x) * inverse_span;
	let displacement_z_x = (right.z - left.z) * inverse_span;
	let displacement_z_z = (front.z - back.z) * inverse_span;
	let jacobian =
		(1.0 + displacement_x_x) * (1.0 + displacement_z_z) -
		displacement_x_z * displacement_z_x;
	let crest = clamp(1.0 - jacobian, 0.0, 1.0);
	let tangent_x = vec3<f32>(
		2.0 * spacing + right.x - left.x,
		right.y - left.y,
		right.z - left.z,
	);
	let tangent_z = vec3<f32>(
		front.x - back.x,
		front.y - back.y,
		2.0 * spacing + front.z - back.z,
	);
	let normal = normalize(cross(tangent_z, tangent_x));
	let output_index = (y * 64u + x) * 2u;
	field[output_index] = vec4<f32>(center, crest);
	field[output_index + 1u] = vec4<f32>(normal, 0.0);
}
`

wgpu_custom_shader_source :: proc(shader: ^resources.Shader) -> (string, string) {
	if shader == nil {
		return "", "shader resource is unavailable"
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, WGPU_CUSTOM_SHADER_PRELUDE)
	strings.write_string(&builder, shader.wgsl)
	strings.write_string(&builder, WGPU_CUSTOM_SHADER_FOOTER)
	source, err := strings.clone(strings.to_string(builder))
	if err != nil {
		return "", "failed to compose custom shader source"
	}
	return source, ""
}

wgpu_custom_shader_cache_slot :: proc(
	cache: []WGPU_Custom_Shader_Cache,
	handle: shared.Shader_Handle,
) -> int {
	for item, index in cache {
		if item.handle == handle {
			return index
		}
	}
	return -1
}

wgpu_spectral_surface_uniform :: proc(
	config: shared.Shader_Spectral_Surface,
	time_seconds: f32,
) -> WGPU_Spectral_Surface_Uniform {
	return {
		parameters = {
			1 if config.enabled else 0,
			config.patch_size,
			config.wind_speed,
			config.amplitude,
		},
		wind_time = {
			config.wind_direction.x,
			config.wind_direction.y,
			time_seconds,
			config.small_wave_damping,
		},
		shape = {config.choppiness, 0, 0, 0},
	}
}

wgpu_create_spectral_surface_cache :: proc(
	renderer: ^WGPU_Renderer,
	entry: ^WGPU_Custom_Shader_Cache,
	config: shared.Shader_Spectral_Surface,
) -> string {
	if renderer == nil || entry == nil || !config.enabled {
		return ""
	}
	entry.spectral_intermediate_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Intermediate Buffer",
			usage = {.Storage},
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT * u64(size_of([8]f32)),
		},
	)
	entry.spectral_spatial_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Spatial Buffer",
			usage = {.Storage},
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT * u64(size_of([4]f32)),
		},
	)
	entry.spectral_field_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Field Buffer",
			usage = {.Storage},
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT *
			WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT *
			u64(size_of([4]f32)),
		},
	)
	entry.spectral_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Spectral_Surface_Uniform)),
		},
	)
	if entry.spectral_intermediate_buffer == nil ||
	   entry.spectral_spatial_buffer == nil ||
	   entry.spectral_field_buffer == nil ||
	   entry.spectral_uniform_buffer == nil {
		return "failed to create spectral surface buffers"
	}
	bind_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = entry.spectral_uniform_buffer,
			size = u64(size_of(WGPU_Spectral_Surface_Uniform)),
		},
		{
			binding = 1,
			buffer = entry.spectral_intermediate_buffer,
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT * u64(size_of([8]f32)),
		},
		{
			binding = 2,
			buffer = entry.spectral_spatial_buffer,
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT * u64(size_of([4]f32)),
		},
		{
			binding = 3,
			buffer = entry.spectral_field_buffer,
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT *
			WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT *
			u64(size_of([4]f32)),
		},
	}
	entry.spectral_compute_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Spectral Surface Compute Bind Group",
			layout = renderer.spectral_surface_bind_group_layout,
			entryCount = uint(len(bind_entries)),
			entries = raw_data(bind_entries[:]),
		},
	)
	if entry.spectral_compute_bind_group == nil {
		return "failed to create spectral surface compute bind group"
	}
	entry.spectral_surface = config
	entry.spectral_last_frame = ~u64(0)
	return ""
}

wgpu_release_custom_shader_cache_entry :: proc(entry: ^WGPU_Custom_Shader_Cache) {
	if entry == nil {
		return
	}
	if entry.render_bind_group != nil { wgpu.BindGroupRelease(entry.render_bind_group) }
	if entry.spectral_compute_bind_group != nil {
		wgpu.BindGroupRelease(entry.spectral_compute_bind_group)
	}
	if entry.spectral_uniform_buffer != nil { wgpu.BufferRelease(entry.spectral_uniform_buffer) }
	if entry.spectral_field_buffer != nil { wgpu.BufferRelease(entry.spectral_field_buffer) }
	if entry.spectral_spatial_buffer != nil { wgpu.BufferRelease(entry.spectral_spatial_buffer) }
	if entry.spectral_intermediate_buffer != nil {
		wgpu.BufferRelease(entry.spectral_intermediate_buffer)
	}
	if entry.blend_pipeline != nil { wgpu.RenderPipelineRelease(entry.blend_pipeline) }
	if entry.module != nil { wgpu.ShaderModuleRelease(entry.module) }
	entry^ = {}
}

wgpu_custom_shader_cache :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Shader_Handle,
) -> (
	^WGPU_Custom_Shader_Cache,
	string,
) {
	shader, alive := resources.get_shader(registry, handle)
	if !alive {
		return nil, "custom shader handle is stale"
	}
	index := wgpu_custom_shader_cache_slot(renderer.custom_shader_cache[:], handle)
	if index < 0 {
		index = len(renderer.custom_shader_cache)
		append(&renderer.custom_shader_cache, WGPU_Custom_Shader_Cache{})
	}
	entry := &renderer.custom_shader_cache[index]
	if entry.valid && entry.version == shader.version {
		return entry, ""
	}
	wgpu_release_custom_shader_cache_entry(entry)
	entry.handle = handle
	entry.version = shader.version
	if spectral_err := wgpu_create_spectral_surface_cache(
		renderer,
		entry,
		shader.spectral_surface,
	); spectral_err != "" {
		wgpu_release_custom_shader_cache_entry(entry)
		return nil, spectral_err
	}
	source, source_err := wgpu_custom_shader_source(shader)
	if source_err != "" {
		wgpu_release_custom_shader_cache_entry(entry)
		return nil, source_err
	}
	defer delete(source)
	chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = source,
	}
	entry.module = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &chain, label = "Scrapbot Project Shader"},
	)
	if entry.module == nil {
		wgpu_release_custom_shader_cache_entry(entry)
		return nil, fmt.tprintf("failed to compile shader '%s'", shader.name)
	}
	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
		{format = .Float32x4, offset = 32, shaderLocation = 3},
	}
	vertex_layout := wgpu.VertexBufferLayout {
		arrayStride = u64(size_of(resources.Vertex)),
		stepMode = .Vertex,
		attributeCount = uint(len(attributes)),
		attributes = raw_data(attributes[:]),
	}
	cull_mode := wgpu.CullMode.Back
	if shader.cull_mode == .None {
		cull_mode = .None
	}
	entry.blend_pipeline = wgpu_create_custom_world_pipeline(
		renderer,
		entry.module,
		&vertex_layout,
		cull_mode,
		true,
	)
	if entry.blend_pipeline == nil {
		wgpu_release_custom_shader_cache_entry(entry)
		return nil, fmt.tprintf("failed to create pipelines for shader '%s'", shader.name)
	}
	entry.valid = true
	return entry, ""
}

wgpu_create_custom_world_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	module: wgpu.ShaderModule,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	blended: bool,
) -> wgpu.RenderPipeline {
	blend := wgpu.BlendState {
		color = {operation = .Add, srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha},
		alpha = {operation = .Add, srcFactor = .Zero, dstFactor = .One},
	}
	write_all := wgpu.ColorWriteMaskFlags_All
	write_secondary := write_all
	if blended {
		write_secondary = {}
	}
	targets := [3]wgpu.ColorTargetState {
		{
			format = .RGBA16Float,
			blend = &blend if blended else nil,
			writeMask = wgpu.ColorWriteMaskFlags_All,
		},
		{format = .RGBA16Float, writeMask = write_secondary},
		{format = .RGBA16Float, writeMask = write_secondary},
	}
	fragment := wgpu.FragmentState {
		module = module,
		entryPoint = "fs_main",
		targetCount = 3,
		targets = raw_data(targets[:]),
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Custom Material Pipeline",
			layout = renderer.custom_shader_pipeline_layout,
			vertex = {
				module = module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = vertex_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False if blended else .True,
				depthCompare = .LessEqual,
			},
			multisample = {count = 1, mask = 0xffff_ffff},
			fragment = &fragment,
		},
	)
}

wgpu_create_spectral_surface_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_SPECTRAL_SURFACE_SHADER,
	}
	renderer.spectral_surface_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &source,
			label = "Scrapbot Spectral Surface Shader",
		},
	)
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Spectral_Surface_Uniform)),
			},
		},
		{binding = 1, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 2, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 3, visibility = {.Compute}, buffer = {type = .Storage}},
	}
	renderer.spectral_surface_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Spectral Surface Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.spectral_surface_shader == nil ||
	   renderer.spectral_surface_bind_group_layout == nil {
		return "failed to create spectral surface shader resources"
	}
	renderer.spectral_surface_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Spectral Surface Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.spectral_surface_bind_group_layout,
		},
	)
	renderer.spectral_surface_horizontal_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Spectral Surface Horizontal FFT Pipeline",
			layout = renderer.spectral_surface_pipeline_layout,
			compute = {module = renderer.spectral_surface_shader, entryPoint = "horizontal"},
		},
	)
	renderer.spectral_surface_vertical_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Spectral Surface Vertical FFT Pipeline",
			layout = renderer.spectral_surface_pipeline_layout,
			compute = {module = renderer.spectral_surface_shader, entryPoint = "vertical"},
		},
	)
	renderer.spectral_surface_finalize_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Spectral Surface Finalize Pipeline",
			layout = renderer.spectral_surface_pipeline_layout,
			compute = {module = renderer.spectral_surface_shader, entryPoint = "finalize"},
		},
	)
	renderer.spectral_surface_dummy_field_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Dummy Field Buffer",
			usage = {.Storage},
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT *
			WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT *
			u64(size_of([4]f32)),
		},
	)
	renderer.spectral_surface_dummy_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Spectral Surface Dummy Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Spectral_Surface_Uniform)),
		},
	)
	if renderer.spectral_surface_pipeline_layout == nil ||
	   renderer.spectral_surface_horizontal_pipeline == nil ||
	   renderer.spectral_surface_vertical_pipeline == nil ||
	   renderer.spectral_surface_finalize_pipeline == nil ||
	   renderer.spectral_surface_dummy_field_buffer == nil ||
	   renderer.spectral_surface_dummy_uniform_buffer == nil {
		return "failed to create spectral surface compute resources"
	}
	return ""
}

wgpu_create_custom_shader_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	if spectral_err := wgpu_create_spectral_surface_resources(renderer); spectral_err != "" {
		return spectral_err
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Custom_Shader_Uniform))},
		},
		{
			binding = 4,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT *
				WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT *
				u64(size_of([4]f32)),
			},
		},
		{
			binding = 5,
			visibility = {.Vertex, .Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Spectral_Surface_Uniform)),
			},
		},
	}
	renderer.custom_shader_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Custom Shader Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.custom_shader_bind_group_layout == nil {
		return "failed to create custom shader bind group layout"
	}
	layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_world_bind_group_layout,
		renderer.material_bind_group_layout,
		renderer.environment_bind_group_layout,
		renderer.custom_shader_bind_group_layout,
	}
	renderer.custom_shader_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Custom Shader Pipeline Layout",
			bindGroupLayoutCount = uint(len(layouts)),
			bindGroupLayouts = raw_data(layouts[:]),
		},
	)
	renderer.custom_shader_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Custom Shader Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Custom_Shader_Uniform)),
		},
	)
	renderer.transparent_visible_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Transparent Visible Instance Buffer",
			usage = {.Storage, .CopyDst},
			size = u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(u32)),
		},
	)
	renderer.custom_shader_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Custom Shader Scene Sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		},
	)
	if renderer.custom_shader_pipeline_layout == nil ||
	   renderer.custom_shader_uniform_buffer == nil ||
	   renderer.transparent_visible_buffer == nil ||
	   renderer.custom_shader_sampler == nil {
		return "failed to create custom shader renderer resources"
	}
	return ""
}

wgpu_release_custom_shader_resources :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil { return }
	for index in 0 ..< len(renderer.custom_shader_cache) {
		wgpu_release_custom_shader_cache_entry(&renderer.custom_shader_cache[index])
	}
	delete(renderer.custom_shader_cache)
	delete(renderer.transparent_draws)
	delete(renderer.transparent_visible_slots)
	wgpu_release_custom_shader_target(renderer)
	if renderer.transparent_world_bind_group !=
	   nil { wgpu.BindGroupRelease(renderer.transparent_world_bind_group) }
	renderer.transparent_world_bind_group = nil
	if renderer.transparent_visible_buffer !=
	   nil { wgpu.BufferRelease(renderer.transparent_visible_buffer) }
	renderer.transparent_visible_buffer = nil
	if renderer.custom_shader_uniform_buffer !=
	   nil { wgpu.BufferRelease(renderer.custom_shader_uniform_buffer) }
	renderer.custom_shader_uniform_buffer = nil
	if renderer.custom_shader_sampler !=
	   nil { wgpu.SamplerRelease(renderer.custom_shader_sampler) }
	renderer.custom_shader_sampler = nil
	if renderer.custom_shader_pipeline_layout !=
	   nil { wgpu.PipelineLayoutRelease(renderer.custom_shader_pipeline_layout) }
	renderer.custom_shader_pipeline_layout = nil
	if renderer.custom_shader_bind_group_layout !=
	   nil { wgpu.BindGroupLayoutRelease(renderer.custom_shader_bind_group_layout) }
	renderer.custom_shader_bind_group_layout = nil
	if renderer.spectral_surface_dummy_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.spectral_surface_dummy_uniform_buffer)
	}
	renderer.spectral_surface_dummy_uniform_buffer = nil
	if renderer.spectral_surface_dummy_field_buffer != nil {
		wgpu.BufferRelease(renderer.spectral_surface_dummy_field_buffer)
	}
	renderer.spectral_surface_dummy_field_buffer = nil
	if renderer.spectral_surface_vertical_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.spectral_surface_vertical_pipeline)
	}
	renderer.spectral_surface_vertical_pipeline = nil
	if renderer.spectral_surface_finalize_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.spectral_surface_finalize_pipeline)
	}
	renderer.spectral_surface_finalize_pipeline = nil
	if renderer.spectral_surface_horizontal_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.spectral_surface_horizontal_pipeline)
	}
	renderer.spectral_surface_horizontal_pipeline = nil
	if renderer.spectral_surface_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.spectral_surface_pipeline_layout)
	}
	renderer.spectral_surface_pipeline_layout = nil
	if renderer.spectral_surface_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.spectral_surface_bind_group_layout)
	}
	renderer.spectral_surface_bind_group_layout = nil
	if renderer.spectral_surface_shader != nil {
		wgpu.ShaderModuleRelease(renderer.spectral_surface_shader)
	}
	renderer.spectral_surface_shader = nil
}

wgpu_release_custom_shader_target :: proc(renderer: ^WGPU_Renderer) {
	for &entry in renderer.custom_shader_cache {
		if entry.render_bind_group != nil {
			wgpu.BindGroupRelease(entry.render_bind_group)
			entry.render_bind_group = nil
		}
		entry.render_target_generation = 0
	}
	if renderer.custom_shader_scene_view != nil {
		wgpu.TextureViewRelease(renderer.custom_shader_scene_view)
		renderer.custom_shader_scene_view = nil
	}
	if renderer.custom_shader_scene_texture != nil {
		wgpu.TextureRelease(renderer.custom_shader_scene_texture)
		renderer.custom_shader_scene_texture = nil
	}
	renderer.custom_shader_scene_width = 0
	renderer.custom_shader_scene_height = 0
	renderer.custom_shader_depth_view = nil
}

wgpu_ensure_custom_shader_target :: proc(
	renderer: ^WGPU_Renderer,
	width, height: u32,
	depth_view: wgpu.TextureView,
) -> string {
	if renderer.custom_shader_scene_width == width &&
	   renderer.custom_shader_scene_height == height &&
	   renderer.custom_shader_scene_view != nil &&
	   renderer.custom_shader_depth_view == depth_view {
		return ""
	}
	wgpu_release_custom_shader_target(renderer)
	renderer.custom_shader_scene_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Opaque Scene Copy",
			usage = {.CopyDst, .TextureBinding},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA16Float,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if renderer.custom_shader_scene_texture ==
	   nil { return "failed to create custom shader scene texture" }
	renderer.custom_shader_scene_view = wgpu.TextureCreateView(
		renderer.custom_shader_scene_texture,
	)
	if renderer.custom_shader_scene_view ==
	   nil { return "failed to create custom shader scene view" }
	renderer.custom_shader_scene_width = width
	renderer.custom_shader_scene_height = height
	renderer.custom_shader_depth_view = depth_view
	renderer.custom_shader_target_generation += 1
	if renderer.custom_shader_target_generation == 0 {
		renderer.custom_shader_target_generation = 1
	}
	return ""
}

wgpu_ensure_custom_shader_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	entry: ^WGPU_Custom_Shader_Cache,
) -> string {
	if renderer == nil ||
	   entry == nil ||
	   renderer.custom_shader_scene_view == nil ||
	   renderer.custom_shader_depth_view == nil {
		return "custom shader target is unavailable"
	}
	if entry.render_bind_group != nil &&
	   entry.render_target_generation == renderer.custom_shader_target_generation {
		return ""
	}
	if entry.render_bind_group != nil {
		wgpu.BindGroupRelease(entry.render_bind_group)
		entry.render_bind_group = nil
	}
	field_buffer := renderer.spectral_surface_dummy_field_buffer
	spectral_uniform_buffer := renderer.spectral_surface_dummy_uniform_buffer
	if entry.spectral_surface.enabled {
		field_buffer = entry.spectral_field_buffer
		spectral_uniform_buffer = entry.spectral_uniform_buffer
	}
	bind_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = renderer.custom_shader_scene_view},
		{binding = 1, sampler = renderer.custom_shader_sampler},
		{binding = 2, textureView = renderer.custom_shader_depth_view},
		{
			binding = 3,
			buffer = renderer.custom_shader_uniform_buffer,
			size = u64(size_of(WGPU_Custom_Shader_Uniform)),
		},
		{
			binding = 4,
			buffer = field_buffer,
			size = WGPU_SPECTRAL_SURFACE_TEXEL_COUNT *
			WGPU_SPECTRAL_SURFACE_FIELD_VALUE_COUNT *
			u64(size_of([4]f32)),
		},
		{
			binding = 5,
			buffer = spectral_uniform_buffer,
			size = u64(size_of(WGPU_Spectral_Surface_Uniform)),
		},
	}
	entry.render_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Custom Shader Bind Group",
			layout = renderer.custom_shader_bind_group_layout,
			entryCount = uint(len(bind_entries)),
			entries = raw_data(bind_entries[:]),
		},
	)
	if entry.render_bind_group == nil {
		return "failed to create custom shader bind group"
	}
	entry.render_target_generation = renderer.custom_shader_target_generation
	return ""
}

wgpu_encode_spectral_surface :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	entry: ^WGPU_Custom_Shader_Cache,
) -> string {
	if renderer == nil ||
	   entry == nil ||
	   !entry.spectral_surface.enabled ||
	   entry.spectral_last_frame == renderer.profile_frame_index {
		return ""
	}
	uniform := wgpu_spectral_surface_uniform(
		entry.spectral_surface,
		renderer.custom_shader_elapsed_seconds,
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		entry.spectral_uniform_buffer,
		0,
		&uniform,
		uint(size_of(uniform)),
	)
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor{label = "Scrapbot Spectral Surface FFT Pass"},
	)
	if pass == nil {
		return "failed to begin spectral surface FFT pass"
	}
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, entry.spectral_compute_bind_group)
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.spectral_surface_horizontal_pipeline)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, 1, WGPU_SPECTRAL_SURFACE_SIZE, 1)
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.spectral_surface_vertical_pipeline)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, WGPU_SPECTRAL_SURFACE_SIZE, 1, 1)
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.spectral_surface_finalize_pipeline)
	wgpu.ComputePassEncoderDispatchWorkgroups(
		pass,
		(WGPU_SPECTRAL_SURFACE_SIZE + 7) / 8,
		(WGPU_SPECTRAL_SURFACE_SIZE + 7) / 8,
		1,
	)
	wgpu.ComputePassEncoderEnd(pass)
	wgpu.ComputePassEncoderRelease(pass)
	entry.spectral_last_frame = renderer.profile_frame_index
	renderer.spectral_surface_dispatch_count += 3
	renderer.spectral_surface_active_count += 1
	return ""
}

wgpu_rebuild_transparent_world_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer.transparent_world_bind_group != nil {
		wgpu.BindGroupRelease(renderer.transparent_world_bind_group)
		renderer.transparent_world_bind_group = nil
	}
	if renderer.geometry_vertex_arena.buffer == nil ||
	   renderer.geometry_index_arena.buffer == nil {
		return ""
	}
	renderer.transparent_world_bind_group = wgpu_make_batch_bind_group(
		renderer,
		renderer.transparent_visible_buffer,
		0,
		WGPU_MAX_GPU_INSTANCES,
		"Scrapbot Transparent World Bind Group",
	)
	if renderer.transparent_world_bind_group ==
	   nil { return "failed to create transparent world bind group" }
	return ""
}

wgpu_prepare_transparent_draws :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	render_list: ^Render_List,
) {
	if renderer == nil || registry == nil || render_list == nil {
		return
	}
	clear(&renderer.transparent_draws)
	renderer.spectral_surface_active_count = 0
	eye := render_list.camera.transform.position
	for slot in 0 ..< min(renderer.gpu_slot_count, len(renderer.gpu_instance_sources)) {
		if slot >= len(renderer.gpu_instance_source_transforms) {
			continue
		}
		source := renderer.gpu_instance_sources[slot]
		material, material_ok := resources.get_material(registry, source.material)
		if !material_ok ||
		   material.desc.alpha_mode != .Blend ||
		   material.desc.shader == (shared.Shader_Handle{}) {
			continue
		}
		offset := vec3_sub(renderer.gpu_instance_source_transforms[slot].position, eye)
		append(
			&renderer.transparent_draws,
			WGPU_Transparent_Draw {
				instance_slot = u32(slot),
				geometry = source.geometry,
				material = source.material,
				distance_squared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z,
			},
		)
	}
	slice.sort_by(renderer.transparent_draws[:], proc(a, b: WGPU_Transparent_Draw) -> bool {
		return a.distance_squared > b.distance_squared
	})
}

wgpu_update_custom_shader_uniform :: proc(
	renderer: ^WGPU_Renderer,
	viewport: ui.Rect,
	delta_time: f32,
) {
	renderer.custom_shader_elapsed_seconds += max(delta_time, 0)
	uniform := WGPU_Custom_Shader_Uniform {
		viewport = {viewport.x, viewport.y, max(viewport.width, 1), max(viewport.height, 1)},
		time = {
			renderer.custom_shader_elapsed_seconds,
			delta_time,
			f32(renderer.profile_frame_index),
			0,
		},
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.custom_shader_uniform_buffer,
		0,
		&uniform,
		uint(size_of(uniform)),
	)
}

wgpu_encode_transparent_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	depth_view: wgpu.TextureView,
	registry: ^resources.Registry,
	viewport: ui.Rect,
) -> string {
	if len(renderer.transparent_draws) == 0 { return "" }
	if renderer.transparent_world_bind_group == nil {
		return "transparent renderer world bind group is unavailable"
	}
	for draw in renderer.transparent_draws {
		material, material_ok := resources.get_material(registry, draw.material)
		if !material_ok { return "transparent draw references an unavailable material" }
		custom, custom_err := wgpu_custom_shader_cache(renderer, registry, material.desc.shader)
		if custom_err != "" { return custom_err }
		if bind_err := wgpu_ensure_custom_shader_bind_group(renderer, custom); bind_err != "" {
			return bind_err
		}
		if spectral_err := wgpu_encode_spectral_surface(renderer, encoder, custom);
		   spectral_err != "" {
			return spectral_err
		}
	}
	resize(&renderer.transparent_visible_slots, len(renderer.transparent_draws))
	for draw, index in renderer.transparent_draws {
		renderer.transparent_visible_slots[index] = draw.instance_slot
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.transparent_visible_buffer,
		0,
		raw_data(renderer.transparent_visible_slots[:]),
		uint(len(renderer.transparent_visible_slots) * size_of(u32)),
	)
	wgpu.CommandEncoderCopyTextureToTexture(
		encoder,
		&wgpu.TexelCopyTextureInfo{texture = renderer.hdr_texture, aspect = .All},
		&wgpu.TexelCopyTextureInfo{texture = renderer.custom_shader_scene_texture, aspect = .All},
		&wgpu.Extent3D {
			width = renderer.custom_shader_scene_width,
			height = renderer.custom_shader_scene_height,
			depthOrArrayLayers = 1,
		},
	)
	color_attachments := [3]wgpu.RenderPassColorAttachment {
		{
			view = renderer.hdr_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Load,
			storeOp = .Store,
		},
		{
			view = renderer.surface_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Load,
			storeOp = .Store,
		},
		{
			view = renderer.indirect_diffuse_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Load,
			storeOp = .Store,
		},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = depth_view,
		depthLoadOp = .Undefined,
		depthStoreOp = .Undefined,
		depthClearValue = 1,
		depthReadOnly = true,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
		stencilReadOnly = true,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Transparent Material Pass",
			colorAttachmentCount = uint(len(color_attachments)),
			colorAttachments = raw_data(color_attachments[:]),
			depthStencilAttachment = &depth_attachment,
		},
	)
	if pass == nil { return "failed to begin transparent material pass" }
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		viewport.x,
		viewport.y,
		viewport.width,
		viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		u32(viewport.x),
		u32(viewport.y),
		u32(viewport.width),
		u32(viewport.height),
	)
	wgpu.RenderPassEncoderSetVertexBuffer(
		pass,
		0,
		renderer.geometry_vertex_arena.buffer,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		pass,
		renderer.geometry_index_arena.buffer,
		.Uint32,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.transparent_world_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, renderer.environment_bind_group)
	for draw, draw_index in renderer.transparent_draws {
		material, material_ok := resources.get_material(registry, draw.material)
		if !material_ok { return "transparent draw references an unavailable material" }
		geometry, geometry_err := wgpu_geometry_cache(renderer, registry, draw.geometry)
		if geometry_err != "" { return geometry_err }
		geometry_resource, geometry_ok := resources.get_geometry(registry, draw.geometry)
		if !geometry_ok { return "transparent draw references unavailable geometry" }
		custom, custom_err := wgpu_custom_shader_cache(renderer, registry, material.desc.shader)
		if custom_err != "" { return custom_err }
		material_cached, material_err := wgpu_material_cache(renderer, registry, draw.material)
		if material_err != "" { return material_err }
		wgpu.RenderPassEncoderSetPipeline(pass, custom.blend_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cached.bind_group)
		wgpu.RenderPassEncoderSetBindGroup(pass, 3, custom.render_bind_group)
		wgpu.RenderPassEncoderDrawIndexed(
			pass,
			u32(resources.geometry_fallback_index_count(geometry_resource)),
			1,
			u32(geometry.index_range.offset / u64(size_of(u32))),
			i32(geometry.vertex_range.offset / u64(size_of(resources.Vertex))),
			u32(draw_index),
		)
	}
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}
