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
	@location(3) tangent: vec4<f32>,
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
	@location(7) world_tangent: vec4<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
	var output: Vertex_Output;
	output.position = render.mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.world_position = (render.model[instance_index] * vec4<f32>(input.position, 1.0)).xyz;
	output.world_normal = normalize((render.normal_model[instance_index] * vec4<f32>(input.normal, 0.0)).xyz);
	output.world_tangent = vec4<f32>(
		(render.model[instance_index] * vec4<f32>(input.tangent.xyz, 0.0)).xyz,
		input.tangent.w,
	);
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

fn mapped_normal(input: Vertex_Output) -> vec3<f32> {
	let geometric = normalize(input.world_normal);
	var sampled = textureSample(normal_texture, normal_sampler, input.uv).xyz * 2.0 - 1.0;
	sampled = normalize(vec3<f32>(sampled.xy * material.pbr_factors.z, sampled.z));
	let authored_tangent_length = length(input.world_tangent.xyz);
	if (authored_tangent_length > 0.0001) {
		let tangent = normalize(
			input.world_tangent.xyz -
			geometric * dot(geometric, input.world_tangent.xyz),
		);
		let bitangent = normalize(cross(geometric, tangent)) * input.world_tangent.w;
		return normalize(mat3x3<f32>(tangent, bitangent, geometric) * sampled);
	}
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
			let texel = 1.0 / vec2<f32>(textureDimensions(shadow_map));
			shadow = 0.0;
			for (var y: i32 = -1; y <= 1; y = y + 1) {
				for (var x: i32 = -1; x <= 1; x = x + 1) {
					let weight =
						select(1.0, 2.0, x == 0) *
						select(1.0, 2.0, y == 0);
					shadow += weight * textureSampleCompare(
						shadow_map,
						shadow_sampler,
						uv + vec2<f32>(f32(x), f32(y)) * texel * 1.5,
						projected.z - 0.002,
					);
				}
			}
			shadow /= 16.0;
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
		color += diffuse_ibl * occlusion * environment.intensity;
		color +=
			specular_ibl *
			environment.intensity *
			environment.reflection_intensity;
	} else {
		color += render.ambient.rgb * ambient_diffuse * occlusion;
		if (environment.background_max_specular_lod < 0.0) {
			let procedural_irradiance = procedural_environment_radiance(normal, 1.0);
			let procedural_specular = procedural_environment_radiance(reflection, roughness);
			color +=
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
	return vec4<f32>((color + emissive) * environment.exposure, 1.0);
}
`

WGPU_POST_PROCESS_SHADER :: `
@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var destination_texture: texture_storage_2d<rgba16float, write>;
struct Automatic_Exposure_State {
	values: vec4<f32>,
};
@group(0) @binding(3) var<storage, read> automatic_exposure: Automatic_Exposure_State;

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
	let color = tent_sample(destination_uv(invocation.xy)) * automatic_exposure.values.x;
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

WGPU_AUTOMATIC_EXPOSURE_SHADER :: `
struct Automatic_Exposure_Settings {
	viewport: vec4<f32>,
	parameters: vec4<f32>,
	control: vec4<f32>,
};

struct Automatic_Exposure_State {
	values: vec4<f32>,
};

@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var<uniform> settings: Automatic_Exposure_Settings;
@group(0) @binding(2) var<storage, read_write> exposure: Automatic_Exposure_State;

var<workgroup> log_luminance_samples: array<f32, 256>;

@compute @workgroup_size(256)
fn automatic_exposure_cs(
	@builtin(local_invocation_index) local_index: u32,
) {
	let grid = vec2<u32>(local_index & 15u, local_index >> 4u);
	let grid_uv = (vec2<f32>(grid) + vec2<f32>(0.5)) / 16.0;
	let dimensions = vec2<i32>(textureDimensions(source_texture));
	let sample_position = clamp(
		vec2<i32>(settings.viewport.xy + grid_uv * settings.viewport.zw),
		vec2<i32>(0),
		dimensions - vec2<i32>(1),
	);
	let color = max(textureLoad(source_texture, sample_position, 0).rgb, vec3<f32>(0.0));
	let luminance = max(dot(color, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0001);
	log_luminance_samples[local_index] = clamp(log2(luminance), -16.0, 16.0);
	workgroupBarrier();

	var stride = 128u;
	loop {
		if (local_index < stride) {
			log_luminance_samples[local_index] +=
				log_luminance_samples[local_index + stride];
		}
		workgroupBarrier();
		if (stride == 1u) {
			break;
		}
		stride = stride >> 1u;
	}

	if (local_index == 0u) {
		let average_luminance = exp2(log_luminance_samples[0] / 256.0);
		let target_exposure = clamp(
			settings.control.w * settings.control.y / max(average_luminance, 0.0001),
			settings.parameters.x,
			settings.parameters.y,
		);
		let reset = settings.control.z > 0.5;
		let adaptation =
			1.0 - exp(-settings.parameters.z * max(settings.parameters.w, 0.0));
		let adapted = select(
			mix(exposure.values.x, target_exposure, adaptation),
			target_exposure,
			reset,
		);
		exposure.values = vec4<f32>(adapted, average_luminance, target_exposure, 1.0);
	}
}
`

WGPU_SCREEN_SPACE_REFLECTIONS_SHADER :: `
struct Reflection_Uniform {
	projection: vec4<f32>,
	viewport: vec4<f32>,
	parameters: vec4<f32>,
	padding: vec4<f32>,
};

@group(0) @binding(0) var scene_color: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var scene_depth: texture_depth_2d;
@group(0) @binding(3) var surface_data: texture_2d<f32>;
@group(0) @binding(4) var reflection_output: texture_storage_2d<rgba16float, write>;
@group(0) @binding(5) var<uniform> reflection: Reflection_Uniform;

fn octahedral_decode(encoded: vec2<f32>) -> vec3<f32> {
	let value = encoded * 2.0 - vec2<f32>(1.0);
	var normal = vec3<f32>(value, 1.0 - abs(value.x) - abs(value.y));
	if (normal.z < 0.0) {
		let folded = (vec2<f32>(1.0) - abs(normal.yx)) * sign(normal.xy);
		normal = vec3<f32>(folded, normal.z);
	}
	return normalize(normal);
}

fn reconstruct_view_position(pixel: vec2<i32>, depth: f32) -> vec3<f32> {
	let viewport_uv =
		(vec2<f32>(pixel) + vec2<f32>(0.5) - reflection.viewport.xy) /
		reflection.viewport.zw;
	let ndc = viewport_uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
	let view_z = -reflection.projection.w / (depth + reflection.projection.z);
	return vec3<f32>(
		(ndc.x + reflection.padding.x) * -view_z / reflection.projection.x,
		(ndc.y + reflection.padding.y) * -view_z / reflection.projection.y,
		view_z,
	);
}

fn project_view_position(position: vec3<f32>) -> vec2<f32> {
	let inverse_depth = 1.0 / max(-position.z, 0.0001);
	let ndc = vec2<f32>(
		position.x * reflection.projection.x * inverse_depth - reflection.padding.x,
		position.y * reflection.projection.y * inverse_depth - reflection.padding.y,
	);
	return reflection.viewport.xy +
		(ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5)) * reflection.viewport.zw;
}

fn inside_viewport(position: vec2<f32>) -> bool {
	return all(position >= reflection.viewport.xy + vec2<f32>(1.0)) &&
		all(position <= reflection.viewport.xy + reflection.viewport.zw - vec2<f32>(2.0));
}

@compute @workgroup_size(8, 8)
fn screen_space_reflections_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(reflection_output);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let pixel = vec2<i32>(invocation.xy);
	let pixel_center = vec2<f32>(pixel) + vec2<f32>(0.5);
	if (!inside_viewport(pixel_center)) {
		textureStore(reflection_output, pixel, vec4<f32>(0.0));
		return;
	}
	let depth = textureLoad(scene_depth, pixel, 0);
	let surface = textureLoad(surface_data, pixel, 0);
	let roughness = surface.z;
	if (depth >= 0.999999 || roughness >= reflection.parameters.w) {
		textureStore(reflection_output, pixel, vec4<f32>(0.0));
		return;
	}
	let origin = reconstruct_view_position(pixel, depth);
	let normal = octahedral_decode(surface.xy);
	let incident = normalize(origin);
	let direction = normalize(reflect(incident, normal));
	if (direction.z >= -0.001) {
		textureStore(reflection_output, pixel, vec4<f32>(0.0));
		return;
	}
	let maximum_distance = reflection.parameters.x;
	let thickness = max(reflection.parameters.y, -origin.z * 0.0015);
	let maximum_steps = clamp(u32(reflection.padding.z + 0.5), 1u, 64u);
	let stride_scale = max(reflection.padding.w, 1.0);
	let stride = max(reflection.parameters.z, -origin.z * 0.002) * stride_scale;
	var distance = stride * 2.0;
	var hit_uv = vec2<f32>(0.0);
	var hit = false;
	for (var step = 0u; step < 64u; step = step + 1u) {
		if (step >= maximum_steps) {
			break;
		}
		let ray_position = origin + direction * distance;
		if (distance > maximum_distance || ray_position.z >= -0.001) {
			break;
		}
		let sample_position = project_view_position(ray_position);
		if (!inside_viewport(sample_position)) {
			break;
		}
		let sample_pixel = vec2<i32>(floor(sample_position));
		let sample_depth = textureLoad(scene_depth, sample_pixel, 0);
		if (sample_depth < 0.999999) {
			let scene_position = reconstruct_view_position(sample_pixel, sample_depth);
			let delta = ray_position.z - scene_position.z;
			if (delta <= 0.0 && delta >= -thickness) {
				hit_uv = sample_position / vec2<f32>(dimensions);
				hit = true;
				break;
			}
		}
		distance += stride * (1.0 + f32(step) * 0.035);
	}
	if (!hit) {
		textureStore(reflection_output, pixel, vec4<f32>(0.0));
		return;
	}
	let viewport_uv = (hit_uv * vec2<f32>(dimensions) - reflection.viewport.xy) /
		reflection.viewport.zw;
	let edge_distance = min(
		min(viewport_uv.x, 1.0 - viewport_uv.x),
		min(viewport_uv.y, 1.0 - viewport_uv.y),
	);
	let edge_fade = smoothstep(0.0, 0.08, edge_distance);
	let distance_fade = 1.0 - clamp(distance / maximum_distance, 0.0, 1.0);
	let roughness_fade = 1.0 - smoothstep(0.15, reflection.parameters.w, roughness);
	let grazing = pow(1.0 - max(dot(-incident, normal), 0.0), 3.0);
	let dielectric = mix(0.04, 1.0, surface.w);
	let fresnel = dielectric + (1.0 - dielectric) * grazing;
	let confidence = edge_fade * distance_fade * roughness_fade * fresnel;
	let color = textureSampleLevel(scene_color, linear_sampler, hit_uv, 0.0).rgb;
	textureStore(reflection_output, pixel, vec4<f32>(color * confidence, confidence));
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
	features: vec4<f32>,
	reflections: vec4<f32>,
	fog_color_density: vec4<f32>,
	fog_height_distance: vec4<f32>,
	fog_lighting: vec4<f32>,
};

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

@group(0) @binding(0) var current_color: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var current_depth: texture_depth_2d;
@group(0) @binding(3) var history_color: texture_2d<f32>;
@group(0) @binding(4) var history_depth: texture_2d<f32>;
@group(0) @binding(5) var resolved_color: texture_storage_2d<rgba16float, write>;
@group(0) @binding(6) var resolved_depth: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var<uniform> temporal: Temporal_AA_Uniform;
@group(0) @binding(8) var ambient_occlusion: texture_2d<f32>;
@group(0) @binding(9) var screen_space_reflections: texture_2d<f32>;
@group(0) @binding(10) var surface_data: texture_2d<f32>;
@group(0) @binding(11) var indirect_diffuse: texture_2d<f32>;
@group(0) @binding(12) var<uniform> render: Render_Uniform;
@group(0) @binding(13) var shadow_map: texture_depth_2d_array;
@group(0) @binding(14) var shadow_sampler: sampler_comparison;
@group(0) @binding(15) var volumetric_fog: texture_2d<f32>;
@group(0) @binding(16) var volumetric_fog_output: texture_storage_2d<rgba16float, write>;
@group(1) @binding(0) var<storage, read> point_lights: array<Point_Light>;
@group(1) @binding(1) var<storage, read_write> cluster_light_counts: array<u32>;
@group(1) @binding(2) var<storage, read_write> cluster_light_indices: array<u32>;
@group(1) @binding(3) var<uniform> cluster: Cluster_Uniform;

const FOG_STEP_COUNT: u32 = 64u;
const FOG_PHASE_NORMALIZATION: f32 = 0.07957747155;
const TEMPORAL_WORKGROUP_WIDTH: u32 = 8u;
const TEMPORAL_TILE_WIDTH: u32 = TEMPORAL_WORKGROUP_WIDTH + 2u;
const TEMPORAL_TILE_SIZE: u32 = TEMPORAL_TILE_WIDTH * TEMPORAL_TILE_WIDTH;

var<workgroup> current_color_tile: array<vec4<f32>, TEMPORAL_TILE_SIZE>;

fn octahedral_decode(encoded: vec2<f32>) -> vec3<f32> {
	let value = encoded * 2.0 - vec2<f32>(1.0);
	var normal = vec3<f32>(value, 1.0 - abs(value.x) - abs(value.y));
	if (normal.z < 0.0) {
		let folded = (vec2<f32>(1.0) - abs(normal.yx)) * sign(normal.xy);
		normal = vec3<f32>(folded, normal.z);
	}
	return normalize(normal);
}

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

fn linear_view_depth(pixel: vec2<i32>) -> f32 {
	let depth = textureLoad(current_depth, pixel, 0);
	if (depth >= 0.999999) {
		return 100000.0;
	}
	return -reconstruct_view_position(pixel, depth).z;
}

fn ambient_occlusion_at(pixel: vec2<i32>) -> f32 {
	let full_dimensions = vec2<i32>(textureDimensions(resolved_color));
	let ao_dimensions = vec2<i32>(textureDimensions(ambient_occlusion));
	let ao_position =
		(vec2<f32>(pixel) + vec2<f32>(0.5)) *
		vec2<f32>(ao_dimensions) /
		vec2<f32>(full_dimensions) -
		vec2<f32>(0.5);
	let base = vec2<i32>(floor(ao_position));
	let fraction = fract(ao_position);
	let center_depth = linear_view_depth(pixel);
	let center_normal = octahedral_decode(textureLoad(surface_data, pixel, 0).xy);
	var visibility = 0.0;
	var weight_total = 0.0;
	for (var y = 0; y <= 1; y += 1) {
		for (var x = 0; x <= 1; x += 1) {
			let offset = vec2<i32>(x, y);
			let ao_pixel = clamp(base + offset, vec2<i32>(0), ao_dimensions - vec2<i32>(1));
			let representative_position =
				(vec2<f32>(ao_pixel) + vec2<f32>(0.5)) *
				vec2<f32>(full_dimensions) /
				vec2<f32>(ao_dimensions);
			let representative_pixel = clamp(
				vec2<i32>(representative_position),
				viewport_minimum(),
				viewport_maximum(),
			);
			let sample_depth = linear_view_depth(representative_pixel);
			let sample_normal = octahedral_decode(
				textureLoad(surface_data, representative_pixel, 0).xy,
			);
			let bilinear = mix(1.0 - fraction.x, fraction.x, f32(x)) *
				mix(1.0 - fraction.y, fraction.y, f32(y));
			let depth_sigma = max(0.01, center_depth * 0.002);
			let depth_delta = sample_depth - center_depth;
			let depth_weight = exp(
				-(depth_delta * depth_delta) /
					max(2.0 * depth_sigma * depth_sigma, 0.000001),
			);
			let normal_weight = pow(max(dot(center_normal, sample_normal), 0.0), 8.0);
			let weight = bilinear * depth_weight * normal_weight;
			visibility += textureLoad(ambient_occlusion, ao_pixel, 0).r * weight;
			weight_total += weight;
		}
	}
	if (weight_total <= 0.0001) {
		let nearest = clamp(
			vec2<i32>(round(ao_position)),
			vec2<i32>(0),
			ao_dimensions - vec2<i32>(1),
		);
		return textureLoad(ambient_occlusion, nearest, 0).r;
	}
	return visibility / weight_total;
}

fn ambient_visibility_at(pixel: vec2<i32>) -> f32 {
	if (temporal.features.z > 0.5) {
		return ambient_occlusion_at(pixel);
	}
	return 1.0;
}

fn current_color_at(pixel: vec2<i32>) -> vec3<f32> {
	var reflection_color = vec3<f32>(0.0);
	if (temporal.reflections.x > 0.5) {
		reflection_color = textureLoad(screen_space_reflections, pixel, 0).rgb;
	}
	let source_color = textureLoad(current_color, pixel, 0).rgb;
	let source_indirect_diffuse = textureLoad(indirect_diffuse, pixel, 0).rgb;
	return source_color -
		source_indirect_diffuse +
		source_indirect_diffuse * ambient_visibility_at(pixel) +
		reflection_color;
}

const VIRTUAL_TRANSITION_MARKER: f32 = 0.25;
const VIRTUAL_TRANSITION_MARKER_WITH_BLOOM: f32 = 0.75;

fn virtual_transition_reactive(value: f32) -> bool {
	return abs(value - VIRTUAL_TRANSITION_MARKER) < 0.0625 ||
		abs(value - VIRTUAL_TRANSITION_MARKER_WITH_BLOOM) < 0.0625;
}

fn fog_shadow_cascade(world_position: vec3<f32>, cascade_index: u32) -> f32 {
	let shadow_position =
		render.shadow_view_projections[cascade_index] * vec4<f32>(world_position, 1.0);
	if (shadow_position.w <= 0.0) {
		return 1.0;
	}
	let projected = shadow_position.xyz / shadow_position.w;
	let uv = vec2<f32>(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
	if (
		any(uv < vec2<f32>(0.0)) ||
		any(uv > vec2<f32>(1.0)) ||
		projected.z < 0.0 ||
		projected.z > 1.0
	) {
		return 1.0;
	}
	let uv_scale = render.shadow_map_parameters.x;
	let texel = render.shadow_map_parameters.y;
	let atlas_uv = uv * uv_scale;
	let half_texel = texel * 0.5;
	let uv_min = vec2<f32>(half_texel);
	let uv_max = vec2<f32>(uv_scale - half_texel);
	var visibility = 0.0;
	for (var y = 0u; y < 2u; y += 1u) {
		for (var x = 0u; x < 2u; x += 1u) {
			let offset = (vec2<f32>(f32(x), f32(y)) - vec2<f32>(0.5)) * texel;
			visibility += textureSampleCompareLevel(
				shadow_map,
				shadow_sampler,
				clamp(atlas_uv + offset, uv_min, uv_max),
				i32(cascade_index),
				projected.z - 0.0007,
			);
		}
	}
	return visibility * 0.25;
}

fn fog_shadow_visibility(world_position: vec3<f32>, view_depth: f32) -> f32 {
	if (render.light_counts.x == 0u) {
		return 0.0;
	}
	var cascade_index = 3u;
	if (view_depth <= render.shadow_cascade_splits.x) {
		cascade_index = 0u;
	} else if (view_depth <= render.shadow_cascade_splits.y) {
		cascade_index = 1u;
	} else if (view_depth <= render.shadow_cascade_splits.z) {
		cascade_index = 2u;
	}
	let visibility = fog_shadow_cascade(world_position, cascade_index);
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
		next_visibility = fog_shadow_cascade(world_position, cascade_index + 1u);
	}
	return mix(visibility, next_visibility, transition);
}

fn fog_phase(cosine: f32, anisotropy: f32) -> f32 {
	let g = clamp(anisotropy, -0.9, 0.9);
	let g2 = g * g;
	return FOG_PHASE_NORMALIZATION * (1.0 - g2) /
		max(pow(1.0 + g2 - 2.0 * g * cosine, 1.5), 0.001);
}

fn fog_cluster_index(position: vec2<f32>, view_depth: f32) -> u32 {
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

fn fog_point_light_radiance(
	screen_position: vec2<f32>,
	world_position: vec3<f32>,
	view_depth: f32,
	world_direction: vec3<f32>,
) -> vec3<f32> {
	if (temporal.fog_lighting.z <= 0.0 || cluster.counts.w == 0u) {
		return vec3<f32>(0.0);
	}
	let cluster_index = fog_cluster_index(screen_position, view_depth);
	let light_count = min(cluster_light_counts[cluster_index], u32(cluster.z_parameters.w));
	var radiance = vec3<f32>(0.0);
	for (var index = 0u; index < light_count; index += 1u) {
		let light_index =
			cluster_light_indices[cluster_index * u32(cluster.z_parameters.w) + index];
		let point_light = point_lights[light_index];
		let offset = point_light.position_range.xyz - world_position;
		let distance = length(offset);
		let range = point_light.position_range.w;
		if (distance >= range || distance <= 0.0001) {
			continue;
		}
		let light_direction = offset / distance;
		let range_fade = max(1.0 - distance / range, 0.0);
		let attenuation = range_fade * range_fade / (1.0 + distance * distance);
		let phase = fog_phase(
			dot(world_direction, light_direction),
			temporal.fog_height_distance.w,
		);
		radiance +=
			point_light.color_intensity.rgb *
			point_light.color_intensity.w *
			attenuation *
			phase;
	}
	return radiance *
		temporal.fog_color_density.rgb *
		temporal.fog_lighting.z;
}

fn fog_sample_phase(fog_texel: vec2<u32>, frame: u32) -> f32 {
	var value =
		fog_texel.x * 0x9e3779b9u ^
		fog_texel.y * 0x85ebca6bu ^
		frame * 0xc2b2ae35u;
	value ^= value >> 16u;
	value *= 0x7feb352du;
	value ^= value >> 15u;
	value *= 0x846ca68bu;
	value ^= value >> 16u;
	return f32(value & 0x00ffffffu) / 16777216.0;
}

fn integrate_volumetric_fog(
	fog_texel: vec2<u32>,
	pixel: vec2<i32>,
	depth: f32,
) -> vec4<f32> {
	let base_density = temporal.fog_color_density.w;
	if (base_density <= 0.0 || !inside_viewport(pixel)) {
		return vec4<f32>(0.0, 0.0, 0.0, 1.0);
	}
	let maximum_distance = max(temporal.fog_height_distance.z, 0.1);
	var ray_distance = maximum_distance;
	if (depth < 0.999999) {
		ray_distance = min(length(reconstruct_view_position(pixel, depth)), maximum_distance);
	}
	if (ray_distance <= 0.0001) {
		return vec4<f32>(0.0, 0.0, 0.0, 1.0);
	}
	let sample_position = vec2<f32>(pixel) + vec2<f32>(0.5);
	let viewport_uv = (sample_position - temporal.viewport.xy) / temporal.viewport.zw;
	let ndc = viewport_uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
	let view_direction = normalize(vec3<f32>(
		(ndc.x + temporal.parameters.x) / temporal.projection.x,
		(ndc.y + temporal.parameters.y) / temporal.projection.y,
		-1.0,
	));
	let world_direction = normalize((temporal.inverse_view * vec4<f32>(view_direction, 0.0)).xyz);
	let camera_position = temporal.inverse_view[3].xyz;
	let active_step_count = clamp(u32(temporal.fog_lighting.w), 4u, FOG_STEP_COUNT);
	let step_length = ray_distance / f32(active_step_count);
	// Scramble both fog texel and a long frame sequence. This turns low-sample
	// error into unstructured variance that finite-depth and sky history can
	// integrate, without the short-cycle lattice left by interleaved gradients.
	// Without valid TAA history, fall back to stable midpoint quadrature.
	let temporal_phase = fog_sample_phase(fog_texel, u32(temporal.reflections.y));
	let integration_phase = select(
		0.5,
		temporal_phase,
		temporal.features.x > 0.5 && temporal.parameters.z > 0.5,
	);
	var directional_radiance = vec3<f32>(0.0);
	if (render.light_counts.x > 0u) {
		let light_direction = normalize(-render.directional_direction_intensity[0].xyz);
		let directional_phase = fog_phase(
			dot(world_direction, light_direction),
			temporal.fog_height_distance.w,
		);
		directional_radiance =
			render.directional_color[0].rgb *
			temporal.fog_color_density.rgb *
			render.directional_direction_intensity[0].w *
			temporal.fog_lighting.y *
			directional_phase;
	}
	let ambient_radiance =
		temporal.fog_color_density.rgb *
		temporal.fog_lighting.x;
	var transmittance = 1.0;
	var scattering = vec3<f32>(0.0);
	for (var step = 0u; step < active_step_count; step += 1u) {
		let distance = (f32(step) + integration_phase) * step_length;
		let world_position = camera_position + world_direction * distance;
		let height_offset = world_position.y - temporal.fog_height_distance.x;
		let height_density = clamp(
			exp(-height_offset * temporal.fog_height_distance.y),
			0.0,
			8.0,
		);
		let optical_depth = base_density * height_density * step_length;
		let step_transmittance = exp(-optical_depth);
		let view_position = render.view * vec4<f32>(world_position, 1.0);
		let view_depth = max(-view_position.z, 0.0);
		let shadow = fog_shadow_visibility(world_position, view_depth);
		let point_radiance = fog_point_light_radiance(
			sample_position,
			world_position,
			view_depth,
			world_direction,
		);
		let incident = ambient_radiance + directional_radiance * shadow + point_radiance;
		scattering += transmittance * (1.0 - step_transmittance) * incident;
		transmittance *= step_transmittance;
	}
	return vec4<f32>(scattering, transmittance);
}

fn volumetric_fog_at(pixel: vec2<i32>) -> vec4<f32> {
	let full_dimensions = vec2<i32>(textureDimensions(resolved_color));
	let fog_dimensions = vec2<i32>(textureDimensions(volumetric_fog));
	let fog_position =
		(vec2<f32>(pixel) + vec2<f32>(0.5)) *
		vec2<f32>(fog_dimensions) /
		vec2<f32>(full_dimensions) -
		vec2<f32>(0.5);
	let base = vec2<i32>(floor(fog_position));
	let fraction = fract(fog_position);
	let center_depth = linear_view_depth(pixel);
	var accumulated = vec4<f32>(0.0);
	var total_weight = 0.0;
	for (var y = 0; y < 2; y += 1) {
		for (var x = 0; x < 2; x += 1) {
			let fog_pixel = clamp(
				base + vec2<i32>(x, y),
				vec2<i32>(0),
				fog_dimensions - vec2<i32>(1),
			);
			let full_position =
				(vec2<f32>(fog_pixel) + vec2<f32>(0.5)) *
				vec2<f32>(full_dimensions) /
				vec2<f32>(fog_dimensions);
			let full_pixel = min(
				vec2<i32>(full_position),
				full_dimensions - vec2<i32>(1),
			);
			let sample_depth = linear_view_depth(full_pixel);
			let depth_scale = max(min(center_depth, sample_depth), 1.0);
			let depth_weight = exp(-abs(center_depth - sample_depth) / depth_scale * 24.0);
			let spatial_weight =
				select(1.0 - fraction.x, fraction.x, x == 1) *
				select(1.0 - fraction.y, fraction.y, y == 1);
			let weight = max(spatial_weight, 0.0001) * depth_weight;
			accumulated += textureLoad(volumetric_fog, fog_pixel, 0) * weight;
			total_weight += weight;
		}
	}
	if (total_weight <= 0.0001) {
		let nearest = clamp(
			vec2<i32>(round(fog_position)),
			vec2<i32>(0),
			fog_dimensions - vec2<i32>(1),
		);
		return textureLoad(volumetric_fog, nearest, 0);
	}
	return accumulated / total_weight;
}

fn apply_volumetric_fog(
	pixel: vec2<i32>,
	source_color: vec3<f32>,
) -> vec3<f32> {
	if (temporal.fog_color_density.w <= 0.0 || !inside_viewport(pixel)) {
		return source_color;
	}
	let fog = volumetric_fog_at(pixel);
	return source_color * fog.a + fog.rgb;
}

fn temporal_tile_color(position: vec2<i32>) -> vec3<f32> {
	let index = u32(position.y) * TEMPORAL_TILE_WIDTH + u32(position.x);
	return current_color_tile[index].rgb;
}

fn fast_antialias(local_pixel: vec2<u32>) -> vec3<f32> {
	let tile_pixel = vec2<i32>(local_pixel) + vec2<i32>(1);
	let north = temporal_tile_color(tile_pixel + vec2<i32>(0, -1));
	let south = temporal_tile_color(tile_pixel + vec2<i32>(0, 1));
	let west = temporal_tile_color(tile_pixel + vec2<i32>(-1, 0));
	let east = temporal_tile_color(tile_pixel + vec2<i32>(1, 0));
	let center = temporal_tile_color(tile_pixel);
	let luma = vec3<f32>(0.299, 0.587, 0.114);
	let center_luma = dot(center, luma);
	let north_luma = dot(north, luma);
	let south_luma = dot(south, luma);
	let west_luma = dot(west, luma);
	let east_luma = dot(east, luma);
	let minimum_luma = min(center_luma, min(min(north_luma, south_luma), min(west_luma, east_luma)));
	let maximum_luma = max(center_luma, max(max(north_luma, south_luma), max(west_luma, east_luma)));
	let contrast = maximum_luma - minimum_luma;
	if (contrast < max(0.0312, maximum_luma * 0.125)) {
		return center;
	}
	let horizontal = abs(west_luma - east_luma);
	let vertical = abs(north_luma - south_luma);
	if (horizontal >= vertical) {
		return center * 0.5 + (west + east) * 0.25;
	}
	return center * 0.5 + (north + south) * 0.25;
}

fn rgb_to_ycocg(color: vec3<f32>) -> vec3<f32> {
	return vec3<f32>(
		color.r * 0.25 + color.g * 0.5 + color.b * 0.25,
		color.r * 0.5 - color.b * 0.5,
		-color.r * 0.25 + color.g * 0.5 - color.b * 0.25,
	);
}

fn ycocg_to_rgb(color: vec3<f32>) -> vec3<f32> {
	return vec3<f32>(
		color.x + color.y - color.z,
		color.x + color.z,
		color.x - color.y - color.z,
	);
}

fn current_neighborhood_from_tile(local_pixel: vec2<u32>) -> array<vec3<f32>, 2> {
	var minimum = vec3<f32>(1e20);
	var maximum = vec3<f32>(-1e20);
	var first_moment = vec3<f32>(0.0);
	var second_moment = vec3<f32>(0.0);
	for (var y = -1; y <= 1; y += 1) {
		for (var x = -1; x <= 1; x += 1) {
			let tile_pixel = vec2<i32>(
				i32(local_pixel.x) + x + 1,
				i32(local_pixel.y) + y + 1,
			);
			let color = rgb_to_ycocg(temporal_tile_color(tile_pixel));
			minimum = min(minimum, color);
			maximum = max(maximum, color);
			first_moment += color;
			second_moment += color * color;
		}
	}
	let mean = first_moment / 9.0;
	let deviation = sqrt(max(second_moment / 9.0 - mean * mean, vec3<f32>(0.0)));
	let variance_minimum = mean - deviation * 2.5;
	let variance_maximum = mean + deviation * 2.5;
	return array<vec3<f32>, 2>(
		max(minimum, variance_minimum),
		min(maximum, variance_maximum),
	);
}

fn volumetric_fog_history_coordinate(pixel: vec2<i32>, depth: f32) -> vec3<f32> {
	let dimensions = vec2<i32>(textureDimensions(current_depth));
	var world_position = vec4<f32>(0.0);
	if (depth < 0.999999) {
		let view_position = reconstruct_view_position(pixel, depth);
		world_position = temporal.inverse_view * vec4<f32>(view_position, 1.0);
	} else {
		let sample_position = vec2<f32>(pixel) + vec2<f32>(0.5);
		let viewport_uv = (sample_position - temporal.viewport.xy) / temporal.viewport.zw;
		let ndc = viewport_uv * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
		let view_direction = normalize(vec3<f32>(
			(ndc.x + temporal.parameters.x) / temporal.projection.x,
			(ndc.y + temporal.parameters.y) / temporal.projection.y,
			-1.0,
		));
		let world_direction = normalize(
			(temporal.inverse_view * vec4<f32>(view_direction, 0.0)).xyz,
		);
		// Fog is a finite medium, not an infinitely distant sky. Reproject a
		// representative point inside the integrated ray so translation moves
		// history instead of dragging old lighting through the viewport.
		let history_distance = max(temporal.fog_height_distance.z * 0.5, 1.0);
		world_position = vec4<f32>(
			temporal.inverse_view[3].xyz + world_direction * history_distance,
			1.0,
		);
	}
	let previous_clip = temporal.previous_view_projection * world_position;
	if (previous_clip.w <= 0.0001) {
		return vec3<f32>(0.0);
	}
	let previous_ndc = previous_clip.xy / previous_clip.w;
	let previous_viewport_uv = previous_ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
	if (
		any(previous_viewport_uv < vec2<f32>(0.0)) ||
		any(previous_viewport_uv > vec2<f32>(1.0))
	) {
		return vec3<f32>(0.0);
	}
	let previous_projected_pixel =
		temporal.viewport.xy + previous_viewport_uv * temporal.viewport.zw;
	let jitter_motion = vec2<f32>(
		temporal.parameters.x * temporal.viewport.z * 0.5,
		-temporal.parameters.y * temporal.viewport.w * 0.5,
	);
	let previous_pixel = previous_projected_pixel - jitter_motion;
	let previous_pixel_i = vec2<i32>(floor(previous_pixel));
	if (!inside_viewport(previous_pixel_i)) {
		return vec3<f32>(0.0);
	}
	let stored_depth = textureLoad(history_depth, previous_pixel_i, 0).r;
	if (depth >= 0.999999) {
		if (stored_depth < 0.999999) {
			return vec3<f32>(0.0);
		}
	} else {
		if (stored_depth >= 0.999999) {
			return vec3<f32>(0.0);
		}
		let expected_linear_depth = previous_clip.w;
		let stored_linear_depth =
			temporal.previous_projection.w /
			(stored_depth + temporal.previous_projection.z);
		let depth_tolerance = max(0.02, expected_linear_depth * 0.02);
		if (abs(stored_linear_depth - expected_linear_depth) > depth_tolerance) {
			return vec3<f32>(0.0);
		}
	}
	return vec3<f32>(previous_pixel / vec2<f32>(dimensions), 1.0);
}

fn resolve_volumetric_fog_history(
	fog_texel: vec2<u32>,
	pixel: vec2<i32>,
	depth: f32,
	current: vec4<f32>,
) -> vec4<f32> {
	if (
		temporal.features.x <= 0.5 ||
		temporal.parameters.z <= 0.5 ||
		temporal.reflections.z <= 0.5
	) {
		return current;
	}
	let history_coordinate = volumetric_fog_history_coordinate(pixel, depth);
	if (history_coordinate.z <= 0.5) {
		return current;
	}
	let history = textureSampleLevel(
		volumetric_fog,
		linear_sampler,
		history_coordinate.xy,
		0.0,
	);
	let fog_dimensions = vec2<f32>(textureDimensions(volumetric_fog_output));
	let history_texel = history_coordinate.xy * fog_dimensions;
	let motion_pixels = length(history_texel - (vec2<f32>(fog_texel) + vec2<f32>(0.5)));
	let scattering_scale = max(length(current.rgb) + length(history.rgb), 0.1);
	let scattering_change = length(history.rgb - current.rgb) / scattering_scale;
	let transmission_change = abs(history.a - current.a) * 2.0;
	let shading_change = max(scattering_change, transmission_change);

	// Rectification limits how much stale radiance can survive even when the
	// reprojected coordinate is geometrically valid. The confidence terms then
	// shorten history under motion and lighting change instead of applying one
	// global, trail-prone weight to every fog sample.
	let scattering_span = max(vec3<f32>(0.015), abs(current.rgb) * 0.2);
	let rectified_history = vec4<f32>(
		clamp(history.rgb, current.rgb - scattering_span, current.rgb + scattering_span),
		clamp(history.a, current.a - 0.025, current.a + 0.025),
	);
	let motion_confidence = exp2(-motion_pixels * 0.5);
	let shading_confidence = exp2(-shading_change * 6.0);
	let history_weight = 0.94 * motion_confidence * shading_confidence;
	return mix(current, rectified_history, history_weight);
}

@compute @workgroup_size(8, 8)
fn volumetric_fog_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(volumetric_fog_output);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let full_dimensions = vec2<i32>(textureDimensions(current_depth));
	let sample_position =
		(vec2<f32>(invocation.xy) + vec2<f32>(0.5)) *
		vec2<f32>(full_dimensions) /
		vec2<f32>(dimensions);
	let pixel = min(
		vec2<i32>(sample_position),
		full_dimensions - vec2<i32>(1),
	);
	let depth = textureLoad(current_depth, pixel, 0);
	let current = integrate_volumetric_fog(invocation.xy, pixel, depth);
	textureStore(
		volumetric_fog_output,
		vec2<i32>(invocation.xy),
		resolve_volumetric_fog_history(invocation.xy, pixel, depth, current),
	);
}

@compute @workgroup_size(8, 8)
fn temporal_aa_cs(
	@builtin(global_invocation_id) invocation: vec3<u32>,
	@builtin(local_invocation_id) local_invocation: vec3<u32>,
	@builtin(local_invocation_index) local_index: u32,
) {
	let dimensions = textureDimensions(resolved_color);
	let workgroup_origin =
		vec2<i32>(invocation.xy) -
		vec2<i32>(local_invocation.xy) -
		vec2<i32>(1);
	for (
		var tile_index = local_index;
		tile_index < TEMPORAL_TILE_SIZE;
		tile_index += TEMPORAL_WORKGROUP_WIDTH * TEMPORAL_WORKGROUP_WIDTH
	) {
		let tile_position = vec2<i32>(
			i32(tile_index % TEMPORAL_TILE_WIDTH),
			i32(tile_index / TEMPORAL_TILE_WIDTH),
		);
		let sample_pixel = clamp(
			workgroup_origin + tile_position,
			viewport_minimum(),
			viewport_maximum(),
		);
		current_color_tile[tile_index] = vec4<f32>(current_color_at(sample_pixel), 1.0);
	}
	workgroupBarrier();
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let pixel = vec2<i32>(invocation.xy);
	let local_pixel = local_invocation.xy;
	var color = current_color_at(pixel);
	if (inside_viewport(pixel)) {
		color = temporal_tile_color(vec2<i32>(local_pixel) + vec2<i32>(1));
	}
	let depth = textureLoad(current_depth, pixel, 0);
	let fogged_color = apply_volumetric_fog(pixel, color);
	var result = fogged_color;
	if (
		inside_viewport(pixel) &&
		temporal.features.x <= 0.5 &&
		temporal.features.y > 0.5
	) {
		result = apply_volumetric_fog(pixel, fast_antialias(local_pixel));
	}
	if (
		inside_viewport(pixel) &&
		depth < 0.999999 &&
		temporal.features.x > 0.5 &&
		temporal.parameters.z > 0.5
	) {
		let view_position = reconstruct_view_position(pixel, depth);
		let world_position = temporal.inverse_view * vec4<f32>(view_position, 1.0);
		let previous_clip = temporal.previous_view_projection * world_position;
		if (previous_clip.w > 0.0001) {
			let previous_ndc = previous_clip.xy / previous_clip.w;
			let previous_viewport_uv =
				previous_ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
			let previous_projected_pixel =
				temporal.viewport.xy + previous_viewport_uv * temporal.viewport.zw;
			let jitter_motion = vec2<f32>(
				temporal.parameters.x * temporal.viewport.z * 0.5,
				-temporal.parameters.y * temporal.viewport.w * 0.5,
			);
			// The reconstructed surface point comes from the current jittered
			// sample ray. Remove that sample offset from the reprojected
			// coordinate because history itself lives on the stable output grid.
			let previous_pixel = previous_projected_pixel - jitter_motion;
			let previous_full_uv =
				previous_pixel / vec2<f32>(dimensions);
			let previous_pixel_i = vec2<i32>(floor(previous_pixel));
			if (
				all(previous_viewport_uv >= vec2<f32>(0.0)) &&
				all(previous_viewport_uv <= vec2<f32>(1.0)) &&
				inside_viewport(previous_pixel_i)
			) {
				let expected_linear_depth = previous_clip.w;
				let history_sample = textureSampleLevel(
					history_color,
					linear_sampler,
					previous_full_uv,
					0.0,
				);
				let transition_reactive =
					virtual_transition_reactive(textureLoad(current_color, pixel, 0).a) ||
					virtual_transition_reactive(history_sample.a);
				let depth_tolerance_scale = select(0.01, 0.12, transition_reactive);
				let depth_tolerance = max(0.01, expected_linear_depth * depth_tolerance_scale);
				var stored_depth = textureLoad(history_depth, previous_pixel_i, 0).r;
				var stored_linear_depth =
					temporal.previous_projection.w /
					(stored_depth + temporal.previous_projection.z);
				var closest_depth_delta =
					abs(stored_linear_depth - expected_linear_depth);
				// Reprojection commonly lands between four history texels.
				// The ordinary interior path needs one load; search the other
				// candidates only when that first surface does not match.
				if (stored_depth >= 0.999999 || closest_depth_delta > depth_tolerance) {
					for (var depth_y = 0; depth_y <= 1; depth_y += 1) {
						for (var depth_x = 0; depth_x <= 1; depth_x += 1) {
							let depth_pixel = clamp(
								previous_pixel_i + vec2<i32>(depth_x, depth_y),
								viewport_minimum(),
								viewport_maximum(),
							);
							let candidate_depth = textureLoad(history_depth, depth_pixel, 0).r;
							if (candidate_depth >= 0.999999) {
								continue;
							}
							let candidate_linear_depth =
								temporal.previous_projection.w /
								(candidate_depth + temporal.previous_projection.z);
							let candidate_delta =
								abs(candidate_linear_depth - expected_linear_depth);
							if (candidate_delta < closest_depth_delta) {
								stored_depth = candidate_depth;
								stored_linear_depth = candidate_linear_depth;
								closest_depth_delta = candidate_delta;
							}
						}
					}
				}
				if (
					stored_depth < 0.999999 &&
					abs(stored_linear_depth - expected_linear_depth) <= depth_tolerance
				) {
					let source_bounds = current_neighborhood_from_tile(local_pixel);
					// History contains resolved fog, while the inexpensive
					// neighborhood samples are pre-fog. Translate the bounds
					// into the same radiometric space before clipping history.
					let fog_offset_ycocg = rgb_to_ycocg(fogged_color) -
						rgb_to_ycocg(color);
					let history_ycocg = clamp(
						rgb_to_ycocg(history_sample.rgb),
						source_bounds[0] + fog_offset_ycocg,
						source_bounds[1] + fog_offset_ycocg,
					);
					let history = ycocg_to_rgb(history_ycocg);
					let motion_pixels = length(
						previous_pixel -
							(vec2<f32>(pixel) + vec2<f32>(0.5)),
					);
					var history_weight = mix(
						temporal.parameters.w,
						0.72,
						clamp(motion_pixels / 8.0, 0.0, 1.0),
					);
					if (transition_reactive) {
						history_weight = max(history_weight, 0.9);
					}
					result = mix(fogged_color, history, history_weight);
				}
			}
		}
	}
	textureStore(
		resolved_color,
		pixel,
		vec4<f32>(
			result,
			select(
				temporal.features.w,
				VIRTUAL_TRANSITION_MARKER + temporal.features.w * 0.5,
				virtual_transition_reactive(textureLoad(current_color, pixel, 0).a),
			),
		),
	);
	textureStore(resolved_depth, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
`

WGPU_AMBIENT_OCCLUSION_SHADER :: `
struct Ambient_Occlusion_Uniform {
	projection: vec4<f32>,
	viewport: vec4<f32>,
	dimensions: vec4<f32>,
	parameters: vec4<f32>,
	visibility_parameters: vec4<f32>,
};

@group(0) @binding(0) var scene_depth: texture_depth_2d;
@group(0) @binding(1) var source_occlusion: texture_2d<f32>;
@group(0) @binding(2) var destination_occlusion: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var surface_data: texture_2d<f32>;
@group(0) @binding(4) var<uniform> settings: Ambient_Occlusion_Uniform;

const PI: f32 = 3.14159265359;
const HALF_PI: f32 = 1.57079632679;
const SECTOR_COUNT: u32 = 32u;

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
	let full_dimensions = vec2<f32>(textureDimensions(scene_depth));
	let ao_dimensions = vec2<f32>(textureDimensions(destination_occlusion));
	let sample_position =
		(vec2<f32>(pixel) + vec2<f32>(0.5)) * full_dimensions / ao_dimensions;
	return clamp_full_pixel(vec2<i32>(sample_position));
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

fn octahedral_decode(encoded: vec2<f32>) -> vec3<f32> {
	let value = encoded * 2.0 - vec2<f32>(1.0);
	var normal = vec3<f32>(value, 1.0 - abs(value.x) - abs(value.y));
	if (normal.z < 0.0) {
		let folded = (vec2<f32>(1.0) - abs(normal.yx)) * sign(normal.xy);
		normal = vec3<f32>(folded, normal.z);
	}
	return normalize(normal);
}

fn view_normal(pixel: vec2<i32>) -> vec3<f32> {
	return octahedral_decode(textureLoad(surface_data, clamp_full_pixel(pixel), 0).xy);
}

fn spatial_rotation(pixel: vec2<i32>) -> f32 {
	var value =
		u32(pixel.x) * 0x8da6b343u ^
		u32(pixel.y) * 0xd8163841u;
	value ^= value >> 16u;
	value *= 0x7feb352du;
	value ^= value >> 15u;
	return f32(value & 0xffffu) * (6.28318530718 / 65536.0);
}

fn fast_acos(value: f32) -> f32 {
	let x = abs(clamp(value, -1.0, 1.0));
	var result = -0.0187293 * x + 0.0742610;
	result = result * x - 0.2121144;
	result = result * x + 1.5707288;
	result *= sqrt(max(1.0 - x, 0.0));
	return select(PI - result, result, value >= 0.0);
}

fn sector_mask(minimum_horizon: f32, maximum_horizon: f32) -> u32 {
	let minimum_sector = min(
		u32(floor(clamp(minimum_horizon, 0.0, 1.0) * f32(SECTOR_COUNT))),
		SECTOR_COUNT - 1u,
	);
	let covered_sectors = min(
		u32(round(
			max(maximum_horizon - minimum_horizon, 0.0) *
			f32(SECTOR_COUNT),
		)),
		SECTOR_COUNT,
	);
	if (covered_sectors == 0u) {
		return 0u;
	}
	let low_bits = select(
		0xffffffffu >> (SECTOR_COUNT - covered_sectors),
		0xffffffffu,
		covered_sectors == SECTOR_COUNT,
	);
	return low_bits << minimum_sector;
}

fn accumulate_visibility_sectors(
	center: vec3<f32>,
	view_direction: vec3<f32>,
	sample_pixel: vec2<i32>,
	radius: f32,
	thickness: f32,
	sampling_direction: f32,
	normal_angle: f32,
	occluded_sectors: u32,
) -> u32 {
	let sample_depth = depth_at(sample_pixel);
	if (sample_depth >= 0.999999) {
		return occluded_sectors;
	}
	let sample_position = view_position(sample_pixel, sample_depth);
	let difference = sample_position - center;
	let distance = length(difference);
	if (distance <= 0.0001 || distance >= radius) {
		return occluded_sectors;
	}
	let back_difference = difference - view_direction * thickness;
	let back_distance = length(back_difference);
	if (back_distance <= 0.0001) {
		return occluded_sectors;
	}
	let front_angle = fast_acos(clamp(
		dot(difference / distance, view_direction),
		-1.0,
		1.0,
	));
	let back_angle = fast_acos(clamp(
		dot(back_difference / back_distance, view_direction),
		-1.0,
		1.0,
	));
	let front_horizon = clamp(
		(sampling_direction * -front_angle - normal_angle + HALF_PI) / PI,
		0.0,
		1.0,
	);
	let back_horizon = clamp(
		(sampling_direction * -back_angle - normal_angle + HALF_PI) / PI,
		0.0,
		1.0,
	);
	return occluded_sectors | sector_mask(
		min(front_horizon, back_horizon),
		max(front_horizon, back_horizon),
	);
}

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
	let normal = view_normal(pixel);
	let view_direction = normalize(-center);
	let radius = settings.parameters.x;
	let thickness = settings.visibility_parameters.x;
	let projected_radius = clamp(
		radius * settings.projection.y * settings.viewport.w / max(-center.z, 0.001) * 0.5,
		2.0,
		128.0,
	);
	let rotation = spatial_rotation(ao_pixel);
	let sample_jitter = fract(rotation * 0.15915494309);
	let quality = clamp(settings.parameters.w, 0.25, 1.0);
	var slice_count = 2u;
	var steps_per_side = 4u;
	if (quality < 0.375) {
		steps_per_side = 2u;
	} else if (quality >= 0.875) {
		slice_count = 3u;
		steps_per_side = 6u;
	} else if (quality >= 0.625) {
		slice_count = 3u;
	}
	var visibility = 0.0;
	for (var slice = 0u; slice < slice_count; slice += 1u) {
		let angle = rotation + (f32(slice) + 0.5) * PI / f32(slice_count);
		let screen_direction = vec2<f32>(cos(angle), sin(angle));
		let slice_direction = vec3<f32>(screen_direction, 0.0);
		let slice_normal = normalize(cross(slice_direction, view_direction));
		let projected_normal = normal - slice_normal * dot(normal, slice_normal);
		let projected_normal_length = length(projected_normal);
		if (projected_normal_length <= 0.0001) {
			visibility += 1.0;
			continue;
		}
		let normalized_projected_normal = projected_normal / projected_normal_length;
		let cos_normal = clamp(
			dot(normalized_projected_normal, view_direction),
			-1.0,
			1.0,
		);
		let slice_tangent = normalize(cross(view_direction, slice_normal));
		let normal_sign = select(
			-1.0,
			1.0,
			dot(projected_normal, slice_tangent) >= 0.0,
		);
		let normal_angle = -normal_sign * acos(cos_normal);
		var occluded_sectors = 0u;
		for (var step = 0u; step < steps_per_side; step += 1u) {
			let normalized_step =
				(f32(step) + 0.35 + sample_jitter * 0.3) /
				f32(steps_per_side);
			let sample_distance = max(
				1.0,
				projected_radius * normalized_step * normalized_step,
			);
			let offset = vec2<i32>(round(screen_direction * sample_distance));
			occluded_sectors = accumulate_visibility_sectors(
				center,
				view_direction,
				clamp_full_pixel(pixel - offset),
				radius,
				thickness,
				-1.0,
				normal_angle,
				occluded_sectors,
			);
			occluded_sectors = accumulate_visibility_sectors(
				center,
				view_direction,
				clamp_full_pixel(pixel + offset),
				radius,
				thickness,
				1.0,
				normal_angle,
				occluded_sectors,
			);
		}
		visibility +=
			1.0 -
			f32(countOneBits(occluded_sectors)) / f32(SECTOR_COUNT);
	}
	visibility = clamp(
		visibility / f32(slice_count),
		0.0,
		1.0,
	);
	visibility = pow(visibility, settings.parameters.y);
	visibility = mix(1.0, visibility, settings.parameters.z);
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
	let center_normal = view_normal(center_full_pixel);
	var total = 0.0;
	var weight_total = 0.0;
	for (var offset = -2; offset <= 2; offset += 1) {
		let sample_pixel = clamp(pixel + axis * offset, vec2<i32>(0), dimensions - vec2<i32>(1));
		let sample_full_pixel = full_pixel_from_ao(sample_pixel);
		let sample_depth = linear_view_depth(sample_full_pixel);
		let sample_normal = view_normal(sample_full_pixel);
		var spatial_weight = 0.40;
		if (abs(offset) == 1) {
			spatial_weight = 0.24;
		} else if (abs(offset) == 2) {
			spatial_weight = 0.06;
		}
		let depth_sigma = max(0.01, center_depth * 0.002);
		let depth_delta = sample_depth - center_depth;
		let depth_weight = exp(
			-(depth_delta * depth_delta) /
				max(2.0 * depth_sigma * depth_sigma, 0.000001),
		);
		let normal_weight = pow(max(dot(center_normal, sample_normal), 0.0), 8.0);
		let weight = spatial_weight * depth_weight * normal_weight;
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
struct Automatic_Exposure_State {
	values: vec4<f32>,
};
@group(0) @binding(7) var<storage, read> automatic_exposure: Automatic_Exposure_State;

struct Post_Effects {
	vignette_color_intensity: vec4<f32>,
	vignette_center_shape: vec4<f32>,
	flare_tint_intensity: vec4<f32>,
	flare_ghosts: vec4<f32>,
	flare_optics: vec4<f32>,
	dirt_tint_intensity: vec4<f32>,
	dirt_parameters: vec4<f32>,
	editor_feedback: vec4<f32>,
};
@group(0) @binding(8) var<uniform> post_effects: Post_Effects;
@group(0) @binding(9) var editor_feedback_mask: texture_2d<f32>;

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

fn linear_to_srgb(color: vec3<f32>) -> vec3<f32> {
	return select(
		1.055 * pow(color, vec3<f32>(1.0 / 2.4)) - vec3<f32>(0.055),
		12.92 * color,
		color <= vec3<f32>(0.0031308),
	);
}

fn srgb_to_linear(color: vec3<f32>) -> vec3<f32> {
	return select(
		pow((color + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4)),
		color / 12.92,
		color <= vec3<f32>(0.04045),
	);
}

fn presentation_dither(color: vec3<f32>, pixel: vec2<f32>) -> vec3<f32> {
	// Fixed screen-space interleaved gradient noise breaks up 8-bit display
	// bands without adding a temporally changing pattern for TAA to chase.
	let noise = fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715)))) - 0.5;
	let encoded = clamp(
		linear_to_srgb(color) + vec3<f32>(noise / 255.0),
		vec3<f32>(0.0),
		vec3<f32>(1.0),
	);
	return srgb_to_linear(encoded);
}

fn hash12(point: vec2<f32>) -> f32 {
	let p = fract(point * vec2<f32>(123.34, 456.21));
	return fract((p.x + p.y) * (p.x + p.y + 45.32));
}

fn value_noise(point: vec2<f32>, seed: f32) -> f32 {
	let cell = floor(point);
	let local = fract(point);
	let blend = local * local * (3.0 - 2.0 * local);
	let offset = vec2<f32>(seed * 0.137, seed * 0.271);
	let a = hash12(cell + offset);
	let b = hash12(cell + vec2<f32>(1.0, 0.0) + offset);
	let c = hash12(cell + vec2<f32>(0.0, 1.0) + offset);
	let d = hash12(cell + vec2<f32>(1.0, 1.0) + offset);
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

fn procedural_lens_dirt(uv: vec2<f32>) -> f32 {
	if (post_effects.dirt_tint_intensity.w <= 0.0) {
		return 0.0;
	}
	let dimensions = vec2<f32>(textureDimensions(hdr_texture));
	let aspect = dimensions.x / max(dimensions.y, 1.0);
	let scale = post_effects.dirt_parameters.x;
	let seed = post_effects.dirt_parameters.z;
	let point = vec2<f32>(uv.x * aspect, uv.y) * scale;
	let broad = value_noise(point, seed);
	let medium = value_noise(point * 3.17 + vec2<f32>(4.1, 8.7), seed + 19.0);
	let fine = value_noise(point * 11.3 + vec2<f32>(1.7, 2.9), seed + 43.0);
	let haze = smoothstep(0.38, 0.82, broad * 0.55 + medium * 0.45);
	let dust = smoothstep(0.78, 0.98, fine) * (0.35 + broad * 0.65);
	return pow(clamp(haze * 0.72 + dust, 0.0, 1.0), post_effects.dirt_parameters.y);
}

fn flare_source(uv: vec2<f32>, radial: vec2<f32>) -> vec3<f32> {
	let aberration = post_effects.flare_optics.z;
	let red_uv = clamp(uv + radial * aberration, vec2<f32>(0.0), vec2<f32>(1.0));
	let blue_uv = clamp(uv - radial * aberration, vec2<f32>(0.0), vec2<f32>(1.0));
	let red = textureSampleLevel(bloom_1, linear_sampler, red_uv, 0.0).r +
		textureSampleLevel(bloom_2, linear_sampler, red_uv, 0.0).r * 0.5;
	let green = textureSampleLevel(bloom_1, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g +
		textureSampleLevel(bloom_2, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g * 0.5;
	let blue = textureSampleLevel(bloom_1, linear_sampler, blue_uv, 0.0).b +
		textureSampleLevel(bloom_2, linear_sampler, blue_uv, 0.0).b * 0.5;
	let source = vec3<f32>(red, green, blue);
	let luminance = dot(source, vec3<f32>(0.2126, 0.7152, 0.0722));
	let threshold = post_effects.flare_ghosts.x;
	return source * max(luminance - threshold, 0.0) / max(luminance, 0.0001);
}

fn lens_flare(uv: vec2<f32>) -> vec3<f32> {
	if (post_effects.flare_tint_intensity.w <= 0.0) {
		return vec3<f32>(0.0);
	}
	let to_center = vec2<f32>(0.5) - uv;
	let radial_distance = length(to_center);
	let radial = to_center / max(radial_distance, 0.0001);
	let quality_count = max(1.0, floor(post_effects.flare_ghosts.y * post_effects.flare_ghosts.w + 0.5));
	var ghosts = vec3<f32>(0.0);
	var weight_sum = 0.0;
	for (var index = 0; index < 8; index += 1) {
		if (f32(index) >= quality_count) {
			continue;
		}
		let distance = (f32(index) + 1.0) * post_effects.flare_ghosts.z;
		let sample_uv = uv + to_center * distance;
		let edge = smoothstep(0.0, 0.08, min(min(sample_uv.x, sample_uv.y), min(1.0 - sample_uv.x, 1.0 - sample_uv.y)));
		let weight = (1.0 - f32(index) / max(quality_count, 1.0)) * edge;
		ghosts += flare_source(sample_uv, radial) * weight;
		weight_sum += weight;
	}
	ghosts /= max(weight_sum, 1.0);

	let halo_uv = uv + radial * post_effects.flare_optics.y;
	let halo_edge = smoothstep(0.0, 0.08, min(min(halo_uv.x, halo_uv.y), min(1.0 - halo_uv.x, 1.0 - halo_uv.y)));
	let halo = flare_source(halo_uv, radial) * post_effects.flare_optics.x * halo_edge;
	return (ghosts + halo) * post_effects.flare_tint_intensity.rgb * post_effects.flare_tint_intensity.w;
}

fn apply_vignette(color: vec3<f32>, uv: vec2<f32>) -> vec3<f32> {
	let intensity = post_effects.vignette_color_intensity.w;
	if (intensity <= 0.0) {
		return color;
	}
	let dimensions = vec2<f32>(textureDimensions(hdr_texture));
	let aspect = dimensions.x / max(dimensions.y, 1.0);
	var point = (uv - post_effects.vignette_center_shape.xy) * 2.0;
	point.x *= mix(1.0, aspect, post_effects.vignette_center_shape.w);
	let distance = length(point);
	let mask = smoothstep(1.0 - post_effects.vignette_center_shape.z, 1.0, distance);
	return mix(color, post_effects.vignette_color_intensity.rgb, mask * intensity);
}

fn editor_feedback_at(pixel: vec2<i32>, dimensions: vec2<i32>) -> vec2<f32> {
	let sample_pixel = clamp(pixel, vec2<i32>(0), dimensions - vec2<i32>(1));
	return step(vec2<f32>(0.5), textureLoad(editor_feedback_mask, sample_pixel, 0).rg);
}

fn editor_feedback_outline(uv: vec2<f32>) -> vec2<f32> {
	let dimensions = vec2<i32>(textureDimensions(editor_feedback_mask));
	let pixel = clamp(
		vec2<i32>(uv * vec2<f32>(dimensions)),
		vec2<i32>(0),
		dimensions - vec2<i32>(1),
	);
	let center = editor_feedback_at(pixel, dimensions);
	var neighbor = vec2<f32>(0.0);
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(-2, 0), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(2, 0), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(0, -2), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(0, 2), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(-2, -2), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(2, -2), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(-2, 2), dimensions));
	neighbor = max(neighbor, editor_feedback_at(pixel + vec2<i32>(2, 2), dimensions));
	return neighbor * (vec2<f32>(1.0) - center);
}

fn selection_dash_coverage(uv: vec2<f32>) -> f32 {
	if (post_effects.editor_feedback.y < 0.5) {
		return 1.0;
	}
	let dimensions = vec2<i32>(textureDimensions(editor_feedback_mask));
	let pixel = clamp(
		vec2<i32>(uv * vec2<f32>(dimensions)),
		vec2<i32>(0),
		dimensions - vec2<i32>(1),
	);
	let horizontal =
		editor_feedback_at(pixel + vec2<i32>(2, 0), dimensions).r -
		editor_feedback_at(pixel + vec2<i32>(-2, 0), dimensions).r;
	let vertical =
		editor_feedback_at(pixel + vec2<i32>(0, 2), dimensions).r -
		editor_feedback_at(pixel + vec2<i32>(0, -2), dimensions).r;
	let pixel_position = vec2<f32>(pixel);
	var coordinate = pixel_position.x * select(-1.0, 1.0, vertical >= 0.0);
	if (abs(horizontal) > abs(vertical)) {
		coordinate = pixel_position.y * select(1.0, -1.0, horizontal >= 0.0);
	}
	let dash_length = post_effects.editor_feedback.z;
	let gap_length = post_effects.editor_feedback.w;
	let period = dash_length + gap_length;
	let offset = post_effects.editor_feedback.x * 28.0;
	let phase = fract((coordinate + offset) / period) * period;
	let center_distance = abs(phase - dash_length * 0.5);
	let wrapped_distance = min(center_distance, period - center_distance);
	let edge_width = max(fwidth(coordinate), 0.75);
	return 1.0 - smoothstep(
		dash_length * 0.5 - edge_width,
		dash_length * 0.5 + edge_width,
		wrapped_distance,
	);
}

@fragment
fn composite_fs(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	var bloom = textureSample(bloom_0, linear_sampler, input.uv).rgb * 0.34;
	bloom += textureSample(bloom_1, linear_sampler, input.uv).rgb * 0.26;
	bloom += textureSample(bloom_2, linear_sampler, input.uv).rgb * 0.20;
	bloom += textureSample(bloom_3, linear_sampler, input.uv).rgb * 0.13;
	bloom += textureSample(bloom_4, linear_sampler, input.uv).rgb * 0.07;
	let resolved = textureSample(hdr_texture, linear_sampler, input.uv);
	let feedback = textureSample(editor_feedback_mask, linear_sampler, input.uv).rg;
	let feedback_outline = editor_feedback_outline(input.uv);
	let selection_outline = feedback_outline.r * selection_dash_coverage(input.uv);
	let preview_fill = smoothstep(0.1, 0.9, feedback.g) * 0.28;
	let preview_outline = feedback_outline.g;
	let selection_color = vec3<f32>(1.0, 0.42, 0.06);
	let preview_color = vec3<f32>(1.0, 0.68, 0.22);
	if (automatic_exposure.values.w > 1.5) {
		var presented = clamp(resolved.rgb, vec3<f32>(0.0), vec3<f32>(1.0));
		presented = mix(
			presented,
			preview_color,
			preview_fill,
		);
		presented = mix(presented, preview_color, preview_outline);
		presented = mix(
			presented,
			selection_color,
			selection_outline,
		);
		return vec4<f32>(
			presentation_dither(presented, input.position.xy),
			1.0,
		);
	}
	let bloom_enabled = step(0.5, resolved.a);
	let flare = lens_flare(input.uv) * bloom_enabled;
	let dirt = procedural_lens_dirt(input.uv) * post_effects.dirt_tint_intensity.w;
	let optical = (bloom * 0.8 + flare) *
		(vec3<f32>(1.0) + post_effects.dirt_tint_intensity.rgb * dirt) * bloom_enabled;
	let hdr = resolved.rgb * automatic_exposure.values.x + optical;
	var graded = apply_vignette(aces(hdr), input.uv);
	graded = mix(
		graded,
		preview_color,
		preview_fill,
	);
	graded = mix(graded, preview_color, preview_outline);
	graded = mix(
		graded,
		selection_color,
		selection_outline,
	);
	return vec4<f32>(presentation_dither(graded, input.position.xy), 1.0);
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
