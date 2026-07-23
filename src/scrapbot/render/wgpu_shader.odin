package render

WGPU_RENDER_SHADER :: `
struct Render_Uniform {
	mvp: array<mat4x4<f32>, 64>,
	model: array<mat4x4<f32>, 64>,
	normal_model: array<mat4x4<f32>, 64>,
	shadow_mvp: array<mat4x4<f32>, 64>,
	color: array<vec4<f32>, 64>,
	emissive: array<vec4<f32>, 64>,
	shadow_flags: array<vec4<f32>, 64>,
	ambient: vec4<f32>,
	directional_direction_intensity: array<vec4<f32>, 4>,
	directional_color: array<vec4<f32>, 4>,
	point_position_range: array<vec4<f32>, 16>,
	point_color_intensity: array<vec4<f32>, 16>,
	light_counts: vec4<u32>,
	camera_position: vec4<f32>,
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

@group(0) @binding(0)
var<uniform> render: Render_Uniform;
@group(0) @binding(1) var shadow_map: texture_depth_2d;
@group(0) @binding(2) var shadow_sampler: sampler_comparison;
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
	@location(0) color: vec3<f32>,
	@location(1) world_position: vec3<f32>,
	@location(2) world_normal: vec3<f32>,
	@location(3) shadow_position: vec4<f32>,
	@location(4) shadow_receiver: f32,
	@location(5) uv: vec2<f32>,
	@location(6) emissive: vec3<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
	var output: Vertex_Output;
	output.position = render.mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.world_position = (render.model[instance_index] * vec4<f32>(input.position, 1.0)).xyz;
	output.world_normal = normalize((render.normal_model[instance_index] * vec4<f32>(input.normal, 0.0)).xyz);
	output.color = render.color[instance_index].rgb;
	output.emissive = render.emissive[instance_index].rgb;
	output.shadow_position = render.shadow_mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.shadow_receiver = render.shadow_flags[instance_index].y;
	output.uv = input.uv;
	return output;
}

@vertex
fn shadow_vs(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> @builtin(position) vec4<f32> {
	if (render.shadow_flags[instance_index].x < 0.5) {
		return vec4<f32>(2.0, 2.0, 2.0, 1.0);
	}
	return render.shadow_mvp[instance_index] * vec4<f32>(input.position, 1.0);
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

fn mapped_normal(input: Vertex_Output) -> vec3<f32> {
	let geometric = normalize(input.world_normal);
	var sampled = textureSample(normal_texture, normal_sampler, input.uv).xyz * 2.0 - 1.0;
	sampled = normalize(vec3<f32>(sampled.xy * material.pbr_factors.z, sampled.z));
	let position_dx = dpdx(input.world_position);
	let position_dy = dpdy(input.world_position);
	let uv_dx = dpdx(input.uv);
	let uv_dy = dpdy(input.uv);
	let determinant = uv_dx.x * uv_dy.y - uv_dx.y * uv_dy.x;
	if (abs(determinant) < 0.000001) {
		return geometric;
	}
	let tangent = normalize((position_dx * uv_dy.y - position_dy * uv_dx.y) / determinant);
	let bitangent = normalize((-position_dx * uv_dy.x + position_dy * uv_dx.x) / determinant);
	return normalize(mat3x3<f32>(tangent, bitangent, geometric) * sampled);
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

@fragment
fn fs_main(input: Vertex_Output) -> @location(0) vec4<f32> {
	let normal = mapped_normal(input);
	let view = normalize(render.camera_position.xyz - input.world_position);
	let texture_color = textureSample(base_color_texture, base_color_sampler, input.uv).rgb;
	let legacy_factor = pow(max(input.color, vec3<f32>(0.0)), vec3<f32>(2.2));
	let color_factor = mix(legacy_factor, input.color, material.flags.y);
	let base_color = texture_color * color_factor;
	let packed = textureSample(metallic_roughness_texture, metallic_roughness_sampler, input.uv);
	let metallic = clamp(packed.b * material.pbr_factors.x, 0.0, 1.0);
	let roughness = clamp(packed.g * material.pbr_factors.y, 0.045, 1.0);
	let occlusion_sample = textureSample(occlusion_texture, occlusion_sampler, input.uv).r;
	let occlusion = mix(1.0, occlusion_sample, material.pbr_factors.w);
	let f0 = mix(vec3<f32>(0.04), base_color, metallic);
	var color = vec3<f32>(0.0);
	var shadow = 1.0;
	if (input.shadow_receiver > 0.5 && render.light_counts.x > 0u && input.shadow_position.w > 0.0) {
		let projected = input.shadow_position.xyz / input.shadow_position.w;
		let uv = vec2<f32>(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
		if (all(uv >= vec2<f32>(0.0)) && all(uv <= vec2<f32>(1.0)) && projected.z >= 0.0 && projected.z <= 1.0) {
			shadow = textureSampleCompare(shadow_map, shadow_sampler, uv, projected.z - 0.002);
		}
	}
	for (var i: u32 = 0u; i < render.light_counts.x; i = i + 1u) {
		let directional = render.directional_direction_intensity[i];
		let light = -normalize(directional.xyz);
		let radiance = render.directional_color[i].rgb * directional.w * shadow;
		color += evaluate_light(normal, view, light, radiance, base_color, metallic, roughness, f0);
	}
	for (var i: u32 = 0u; i < render.light_counts.y; i = i + 1u) {
		let point = render.point_position_range[i];
		let offset = point.xyz - input.world_position;
		let distance = length(offset);
		if (distance < point.w && distance > 0.0001) {
			let light = offset / distance;
			let range_fade = max(1.0 - distance / point.w, 0.0);
			let attenuation = range_fade * range_fade / (1.0 + distance * distance);
			let point_color = render.point_color_intensity[i];
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
`

WGPU_POST_PROCESS_SHADER :: `
@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var destination_texture: texture_storage_2d<rgba16float, write>;

fn tent_sample(uv: vec2<f32>) -> vec3<f32> {
	let texel = 1.0 / vec2<f32>(textureDimensions(source_texture));
	var color = textureSampleLevel(source_texture, linear_sampler, uv, 0.0).rgb * 4.0;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>( 1.0, -1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>(-1.0,  1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>( 1.0,  1.0), 0.0).rgb;
	return color * 0.125;
}

fn destination_uv(pixel: vec2<u32>) -> vec2<f32> {
	return (vec2<f32>(pixel) + vec2<f32>(0.5)) / vec2<f32>(textureDimensions(destination_texture));
}

@compute @workgroup_size(8, 8)
fn bright_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(destination_texture);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let color = tent_sample(destination_uv(invocation.xy));
	let brightness = max(color.r, max(color.g, color.b));
	let knee = 0.5;
	let soft = clamp(brightness - 1.0 + knee, 0.0, 2.0 * knee);
	let contribution = max(brightness - 1.0, soft * soft / (4.0 * knee + 0.0001));
	let result = color * contribution / max(brightness, 0.0001);
	textureStore(destination_texture, vec2<i32>(invocation.xy), vec4<f32>(result, 1.0));
}

@compute @workgroup_size(8, 8)
fn downsample_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(destination_texture);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let uv = destination_uv(invocation.xy);
	let texel = 1.5 / vec2<f32>(textureDimensions(source_texture));
	var color = textureSampleLevel(source_texture, linear_sampler, uv, 0.0).rgb * 0.20;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.08;
	textureStore(destination_texture, vec2<i32>(invocation.xy), vec4<f32>(color, 1.0));
}
`

WGPU_TEMPORAL_AA_SHADER :: `
struct Temporal_AA_Uniform {
	previous_view_projection: mat4x4<f32>,
	inverse_view: mat4x4<f32>,
	projection: vec4<f32>,
	previous_projection: vec4<f32>,
	viewport: vec4<f32>,
	parameters: vec4<f32>,
};

@group(0) @binding(0) var current_color: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var current_depth: texture_depth_2d;
@group(0) @binding(3) var history_color: texture_2d<f32>;
@group(0) @binding(4) var history_depth: texture_2d<f32>;
@group(0) @binding(5) var resolved_color: texture_storage_2d<rgba16float, write>;
@group(0) @binding(6) var resolved_depth: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var<uniform> temporal: Temporal_AA_Uniform;
@group(0) @binding(8) var ambient_occlusion: texture_2d<f32>;

fn viewport_minimum() -> vec2<i32> {
	return vec2<i32>(floor(temporal.viewport.xy));
}

fn viewport_maximum() -> vec2<i32> {
	return vec2<i32>(ceil(temporal.viewport.xy + temporal.viewport.zw)) - vec2<i32>(1);
}

fn inside_viewport(pixel: vec2<i32>) -> bool {
	return all(pixel >= viewport_minimum()) && all(pixel <= viewport_maximum());
}

fn reconstruct_view_position(pixel: vec2<i32>, depth: f32) -> vec3<f32> {
	let sample_position = vec2<f32>(pixel) + vec2<f32>(0.5);
	let viewport_uv = (sample_position - temporal.viewport.xy) / temporal.viewport.zw;
	let ndc = viewport_uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
	let view_z = -temporal.projection.w / (depth + temporal.projection.z);
	return vec3<f32>(
		(ndc.x + temporal.parameters.x) * -view_z / temporal.projection.x,
		(ndc.y + temporal.parameters.y) * -view_z / temporal.projection.y,
		view_z,
	);
}

fn current_color_at(pixel: vec2<i32>) -> vec3<f32> {
	let dimensions = vec2<f32>(textureDimensions(resolved_color));
	let uv = (vec2<f32>(pixel) + vec2<f32>(0.5)) / dimensions;
	let visibility = textureSampleLevel(ambient_occlusion, linear_sampler, uv, 0.0).r;
	return textureLoad(current_color, pixel, 0).rgb * visibility;
}

fn current_neighborhood(pixel: vec2<i32>) -> array<vec3<f32>, 2> {
	var minimum = vec3<f32>(1e20);
	var maximum = vec3<f32>(-1e20);
	for (var y = -1; y <= 1; y += 1) {
		for (var x = -1; x <= 1; x += 1) {
			let sample_pixel = clamp(
				pixel + vec2<i32>(x, y),
				viewport_minimum(),
				viewport_maximum(),
			);
			let color = current_color_at(sample_pixel);
			minimum = min(minimum, color);
			maximum = max(maximum, color);
		}
	}
	return array<vec3<f32>, 2>(minimum, maximum);
}

@compute @workgroup_size(8, 8)
fn temporal_aa_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(resolved_color);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let pixel = vec2<i32>(invocation.xy);
	let color = current_color_at(pixel);
	let depth = textureLoad(current_depth, pixel, 0);
	var result = color;
	if (
		inside_viewport(pixel) &&
		depth < 0.999999 &&
		temporal.parameters.z > 0.5
	) {
		let view_position = reconstruct_view_position(pixel, depth);
		let world_position = temporal.inverse_view * vec4<f32>(view_position, 1.0);
		let previous_clip = temporal.previous_view_projection * world_position;
		if (previous_clip.w > 0.0001) {
			let previous_ndc = previous_clip.xy / previous_clip.w;
			let previous_viewport_uv =
				previous_ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
			let previous_pixel =
				temporal.viewport.xy + previous_viewport_uv * temporal.viewport.zw;
			let previous_full_uv =
				previous_pixel / vec2<f32>(dimensions);
			let previous_pixel_i = vec2<i32>(floor(previous_pixel));
			if (
				all(previous_viewport_uv >= vec2<f32>(0.0)) &&
				all(previous_viewport_uv <= vec2<f32>(1.0)) &&
				inside_viewport(previous_pixel_i)
			) {
				let stored_depth = textureLoad(history_depth, previous_pixel_i, 0).r;
				let stored_linear_depth =
					temporal.previous_projection.w /
					(stored_depth + temporal.previous_projection.z);
				let expected_linear_depth = previous_clip.w;
				let depth_tolerance = max(0.002, expected_linear_depth * 0.0005);
				if (
					stored_depth < 0.999999 &&
					abs(stored_linear_depth - expected_linear_depth) <= depth_tolerance
				) {
					let bounds = current_neighborhood(pixel);
					let history = clamp(
						textureSampleLevel(
							history_color,
							linear_sampler,
							previous_full_uv,
							0.0,
						).rgb,
						bounds[0],
						bounds[1],
					);
					let motion_pixels = length(
						(previous_pixel - (vec2<f32>(pixel) + vec2<f32>(0.5))),
					);
					let history_weight = mix(
						temporal.parameters.w,
						0.72,
						clamp(motion_pixels / 8.0, 0.0, 1.0),
					);
					result = mix(color, history, history_weight);
				}
			}
		}
	}
	textureStore(resolved_color, pixel, vec4<f32>(result, 1.0));
	textureStore(resolved_depth, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
`

WGPU_AMBIENT_OCCLUSION_SHADER :: `
struct Ambient_Occlusion_Uniform {
	projection: vec4<f32>,
	viewport: vec4<f32>,
	dimensions: vec4<f32>,
	parameters: vec4<f32>,
};

@group(0) @binding(0) var scene_depth: texture_depth_2d;
@group(0) @binding(1) var source_occlusion: texture_2d<f32>;
@group(0) @binding(2) var destination_occlusion: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform> settings: Ambient_Occlusion_Uniform;

fn viewport_minimum() -> vec2<i32> {
	return vec2<i32>(floor(settings.viewport.xy));
}

fn viewport_maximum() -> vec2<i32> {
	return vec2<i32>(ceil(settings.viewport.xy + settings.viewport.zw)) - vec2<i32>(1);
}

fn clamp_full_pixel(pixel: vec2<i32>) -> vec2<i32> {
	return clamp(pixel, viewport_minimum(), viewport_maximum());
}

fn full_pixel_from_ao(pixel: vec2<i32>) -> vec2<i32> {
	return clamp_full_pixel(pixel * 2 + vec2<i32>(1));
}

fn depth_at(pixel: vec2<i32>) -> f32 {
	return textureLoad(scene_depth, clamp_full_pixel(pixel), 0);
}

fn view_position(pixel: vec2<i32>, depth: f32) -> vec3<f32> {
	let sample_position = vec2<f32>(pixel) + vec2<f32>(0.5);
	let viewport_uv = (sample_position - settings.viewport.xy) / settings.viewport.zw;
	let ndc = viewport_uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
	let view_z = -settings.projection.w / (depth + settings.projection.z);
	return vec3<f32>(
		(ndc.x + settings.dimensions.z) * -view_z / settings.projection.x,
		(ndc.y + settings.dimensions.w) * -view_z / settings.projection.y,
		view_z,
	);
}

fn closest_difference(
	center: vec3<f32>,
	negative: vec3<f32>,
	positive: vec3<f32>,
) -> vec3<f32> {
	let to_negative = center - negative;
	let to_positive = positive - center;
	return select(to_positive, to_negative, abs(to_negative.z) < abs(to_positive.z));
}

fn view_normal(pixel: vec2<i32>, center: vec3<f32>) -> vec3<f32> {
	let left_pixel = clamp_full_pixel(pixel + vec2<i32>(-1, 0));
	let right_pixel = clamp_full_pixel(pixel + vec2<i32>(1, 0));
	let up_pixel = clamp_full_pixel(pixel + vec2<i32>(0, -1));
	let down_pixel = clamp_full_pixel(pixel + vec2<i32>(0, 1));
	let left = view_position(left_pixel, depth_at(left_pixel));
	let right = view_position(right_pixel, depth_at(right_pixel));
	let up = view_position(up_pixel, depth_at(up_pixel));
	let down = view_position(down_pixel, depth_at(down_pixel));
	let horizontal = closest_difference(center, left, right);
	let vertical = closest_difference(center, up, down);
	var normal = normalize(cross(horizontal, vertical));
	if (normal.z < 0.0) {
		normal = -normal;
	}
	return normal;
}

const SAMPLE_DIRECTIONS = array<vec2<f32>, 12>(
	vec2<f32>( 1.0000,  0.0000),
	vec2<f32>( 0.5000,  0.8660),
	vec2<f32>(-0.5000,  0.8660),
	vec2<f32>(-1.0000,  0.0000),
	vec2<f32>(-0.5000, -0.8660),
	vec2<f32>( 0.5000, -0.8660),
	vec2<f32>( 0.9239,  0.3827),
	vec2<f32>( 0.1305,  0.9914),
	vec2<f32>(-0.7934,  0.6088),
	vec2<f32>(-0.9239, -0.3827),
	vec2<f32>(-0.1305, -0.9914),
	vec2<f32>( 0.7934, -0.6088),
);

@compute @workgroup_size(8, 8)
fn ambient_occlusion_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(destination_occlusion);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let ao_pixel = vec2<i32>(invocation.xy);
	let pixel = full_pixel_from_ao(ao_pixel);
	let depth = depth_at(pixel);
	if (depth >= 0.999999) {
		textureStore(destination_occlusion, ao_pixel, vec4<f32>(1.0));
		return;
	}
	let center = view_position(pixel, depth);
	let normal = view_normal(pixel, center);
	let radius = settings.parameters.x;
	let bias = settings.parameters.y;
	let projected_radius = clamp(
		radius * settings.projection.y * settings.viewport.w / max(-center.z, 0.001) * 0.5,
		2.0,
		96.0,
	);
	var occlusion = 0.0;
	for (var index = 0u; index < 12u; index += 1u) {
		let ring = 0.20 + 0.80 * (f32(index) + 0.5) / 12.0;
		let offset = vec2<i32>(round(SAMPLE_DIRECTIONS[index] * projected_radius * ring));
		let sample_pixel = clamp_full_pixel(pixel + offset);
		let sample_depth = depth_at(sample_pixel);
		if (sample_depth >= 0.999999) {
			continue;
		}
		let sample_position = view_position(sample_pixel, sample_depth);
		let difference = sample_position - center;
		let distance = length(difference);
		if (distance <= 0.0001 || distance >= radius) {
			continue;
		}
		let horizon = max(dot(normal, difference / distance) - bias, 0.0);
		occlusion += horizon * (1.0 - distance / radius);
	}
	let amount = clamp(
		occlusion * settings.parameters.z * (3.0 / 12.0),
		0.0,
		1.0,
	);
	let visibility = pow(1.0 - amount, settings.parameters.w);
	textureStore(
		destination_occlusion,
		ao_pixel,
		vec4<f32>(visibility, visibility, visibility, 1.0),
	);
}

fn linear_view_depth(pixel: vec2<i32>) -> f32 {
	let depth = depth_at(pixel);
	if (depth >= 0.999999) {
		return 100000.0;
	}
	return -view_position(pixel, depth).z;
}

fn bilateral_blur(pixel: vec2<i32>, axis: vec2<i32>) -> f32 {
	let dimensions = vec2<i32>(textureDimensions(source_occlusion));
	let center_full_pixel = full_pixel_from_ao(pixel);
	let center_depth = linear_view_depth(center_full_pixel);
	var total = 0.0;
	var weight_total = 0.0;
	for (var offset = -2; offset <= 2; offset += 1) {
		let sample_pixel = clamp(pixel + axis * offset, vec2<i32>(0), dimensions - vec2<i32>(1));
		let sample_full_pixel = full_pixel_from_ao(sample_pixel);
		let sample_depth = linear_view_depth(sample_full_pixel);
		var spatial_weight = 0.40;
		if (abs(offset) == 1) {
			spatial_weight = 0.24;
		} else if (abs(offset) == 2) {
			spatial_weight = 0.06;
		}
		let depth_weight = 1.0 / (1.0 + abs(sample_depth - center_depth) * 8.0);
		let weight = spatial_weight * depth_weight;
		total += textureLoad(source_occlusion, sample_pixel, 0).r * weight;
		weight_total += weight;
	}
	return total / max(weight_total, 0.0001);
}

fn store_blur(invocation: vec3<u32>, axis: vec2<i32>) {
	let dimensions = textureDimensions(destination_occlusion);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let pixel = vec2<i32>(invocation.xy);
	let visibility = bilateral_blur(pixel, axis);
	textureStore(
		destination_occlusion,
		pixel,
		vec4<f32>(visibility, visibility, visibility, 1.0),
	);
}

@compute @workgroup_size(8, 8)
fn blur_horizontal_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	store_blur(invocation, vec2<i32>(1, 0));
}

@compute @workgroup_size(8, 8)
fn blur_vertical_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	store_blur(invocation, vec2<i32>(0, 1));
}
`

WGPU_COMPOSITE_SHADER :: `
@group(0) @binding(0) var hdr_texture: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var bloom_0: texture_2d<f32>;
@group(0) @binding(3) var bloom_1: texture_2d<f32>;
@group(0) @binding(4) var bloom_2: texture_2d<f32>;
@group(0) @binding(5) var bloom_3: texture_2d<f32>;
@group(0) @binding(6) var bloom_4: texture_2d<f32>;

struct Fullscreen_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
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
	output.uv = output.position.xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
	return output;
}

fn aces(color: vec3<f32>) -> vec3<f32> {
	return clamp(
		(color * (2.51 * color + vec3<f32>(0.03))) /
		(color * (2.43 * color + vec3<f32>(0.59)) + vec3<f32>(0.14)),
		vec3<f32>(0.0),
		vec3<f32>(1.0),
	);
}

@fragment
fn composite_fs(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	var bloom = textureSample(bloom_0, linear_sampler, input.uv).rgb * 0.34;
	bloom += textureSample(bloom_1, linear_sampler, input.uv).rgb * 0.26;
	bloom += textureSample(bloom_2, linear_sampler, input.uv).rgb * 0.20;
	bloom += textureSample(bloom_3, linear_sampler, input.uv).rgb * 0.13;
	bloom += textureSample(bloom_4, linear_sampler, input.uv).rgb * 0.07;
	let hdr = textureSample(hdr_texture, linear_sampler, input.uv).rgb + bloom * 0.8;
	return vec4<f32>(aces(hdr), 1.0);
}
`

WGPU_UI_SHADER :: `
@group(0) @binding(0) var font_texture: texture_2d_array<f32>;
@group(0) @binding(1) var font_sampler: sampler;
@group(0) @binding(2) var viewport_texture_0: texture_2d<f32>;
@group(0) @binding(3) var viewport_texture_1: texture_2d<f32>;
@group(0) @binding(4) var viewport_texture_2: texture_2d<f32>;
@group(0) @binding(5) var viewport_texture_3: texture_2d<f32>;
@group(0) @binding(6) var viewport_texture_4: texture_2d<f32>;
@group(0) @binding(7) var viewport_texture_5: texture_2d<f32>;
@group(0) @binding(8) var viewport_texture_6: texture_2d<f32>;
@group(0) @binding(9) var viewport_texture_7: texture_2d<f32>;
struct Input {@location(0) position:vec2<f32>,@location(1) uv:vec2<f32>,@location(2) color:vec4<f32>,@location(3) kind:f32,@location(4) size_radius:vec3<f32>,@location(5) clip:vec4<f32>,@location(6) border_color:vec4<f32>,@location(7) border_width:f32,@location(8) font_layer:f32};
struct Output {@builtin(position) position:vec4<f32>,@location(0) uv:vec2<f32>,@location(1) color:vec4<f32>,@location(2) kind:f32,@location(3) size_radius:vec3<f32>,@location(4) @interpolate(flat) clip:vec4<f32>,@location(5) border_color:vec4<f32>,@location(6) border_width:f32,@location(7) @interpolate(flat) font_layer:f32};
@vertex fn ui_vs(input:Input)->Output {var output:Output;output.position=vec4<f32>(input.position,0.0,1.0);output.uv=input.uv;output.color=input.color;output.kind=input.kind;output.size_radius=input.size_radius;output.clip=input.clip;output.border_color=input.border_color;output.border_width=input.border_width;output.font_layer=input.font_layer;return output;}
fn median(value:vec3<f32>)->f32{return max(min(value.r,value.g),min(max(value.r,value.g),value.b));}
fn font_screen_pixel_range(uv:vec2<f32>)->f32{let unit_range=vec2<f32>(8.0)/vec2<f32>(textureDimensions(font_texture));let screen_texture_size=vec2<f32>(1.0)/fwidth(uv);return max(0.5*dot(unit_range,screen_texture_size),1.0);}
fn segment_distance(point:vec2<f32>,a:vec2<f32>,b:vec2<f32>)->f32{let segment=b-a;let projection=clamp(dot(point-a,segment)/max(dot(segment,segment),0.0001),0.0,1.0);return length(point-(a+segment*projection));}
fn sample_viewport(layer:i32,uv:vec2<f32>)->vec4<f32>{switch layer{case 0:{return textureSample(viewport_texture_0,font_sampler,uv);}case 1:{return textureSample(viewport_texture_1,font_sampler,uv);}case 2:{return textureSample(viewport_texture_2,font_sampler,uv);}case 3:{return textureSample(viewport_texture_3,font_sampler,uv);}case 4:{return textureSample(viewport_texture_4,font_sampler,uv);}case 5:{return textureSample(viewport_texture_5,font_sampler,uv);}case 6:{return textureSample(viewport_texture_6,font_sampler,uv);}default:{return textureSample(viewport_texture_7,font_sampler,uv);}}}
@fragment fn ui_fs(input:Output)->@location(0) vec4<f32>{if input.position.x<input.clip.x||input.position.y<input.clip.y||input.position.x>=input.clip.z||input.position.y>=input.clip.w{discard;}if input.kind>5.5{return sample_viewport(i32(input.font_layer),input.uv)*input.color;}if input.kind>4.5 {let size=max(input.size_radius.xy,vec2<f32>(0.001));let point=input.uv*size;let a=vec2<f32>(size.x*0.08,size.y*0.48);let b=vec2<f32>(size.x*0.38,size.y*0.78);let c=vec2<f32>(size.x*0.92,size.y*0.18);let distance=min(segment_distance(point,a,b),segment_distance(point,b,c));let edge=distance-input.size_radius.z*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>3.5 {let size=max(input.size_radius.xy,vec2<f32>(0.001));let point=input.uv*size;var a=vec2<f32>(size.x*0.30,size.y*0.18);var b=vec2<f32>(size.x*0.70,size.y*0.50);var c=vec2<f32>(size.x*0.30,size.y*0.82);if input.size_radius.z<0.0 {a=vec2<f32>(size.x*0.18,size.y*0.30);b=vec2<f32>(size.x*0.50,size.y*0.70);c=vec2<f32>(size.x*0.82,size.y*0.30);}let distance=min(segment_distance(point,a,b),segment_distance(point,b,c));let edge=distance-abs(input.size_radius.z)*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>2.5 {let half_size=max(input.size_radius.xy*0.5,vec2<f32>(0.001));let point=(input.uv*2.0-1.0)*half_size;let k0=length(point/half_size);let k1=max(length(point/(half_size*half_size)),0.0001);let distance=k0*(k0-0.92)/k1;let edge=abs(distance)-input.size_radius.z*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>1.5{return input.color;}if input.kind>0.5 {let distance=median(textureSample(font_texture,font_sampler,input.uv,i32(input.font_layer)).rgb);let screen_distance=font_screen_pixel_range(input.uv)*(distance-0.5);let coverage=clamp(screen_distance+0.5,0.0,1.0);return vec4<f32>(input.color.rgb,input.color.a*coverage);}let radius=min(input.size_radius.z,min(input.size_radius.x,input.size_radius.y)*0.5);let point=input.uv*input.size_radius.xy-input.size_radius.xy*0.5;let q=abs(point)-(input.size_radius.xy*0.5-vec2<f32>(radius));let distance=length(max(q,vec2<f32>(0.0)))+min(max(q.x,q.y),0.0)-radius;let smoothing=max(fwidth(distance),0.75);let coverage=1.0-smoothstep(-smoothing,smoothing,distance);let border_mix=smoothstep(-input.border_width-smoothing,-input.border_width+smoothing,distance)*step(0.001,input.border_width)*input.border_color.a;let surface=mix(input.color,input.border_color,border_mix);return vec4<f32>(surface.rgb,surface.a*coverage);}
`

WGPU_VIEWPORT_TEXTURE_SHADER :: `
@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;
struct Output {@builtin(position) position:vec4<f32>,@location(0) uv:vec2<f32>};
@vertex fn vs_main(@builtin(vertex_index) index:u32)->Output{var positions=array<vec2<f32>,3>(vec2<f32>(-1.0,-1.0),vec2<f32>(3.0,-1.0),vec2<f32>(-1.0,3.0));var output:Output;output.position=vec4<f32>(positions[index],0.0,1.0);output.uv=positions[index]*vec2<f32>(0.5,-0.5)+vec2<f32>(0.5,0.5);return output;}
@fragment fn fs_main(input:Output)->@location(0) vec4<f32>{return textureSample(source_texture,source_sampler,input.uv);}
`
