// The psrdnoise implementation below is adapted from psrdnoise2.wgsl.
//
// Copyright (c) 2021-2022 Stefan Gustavson and Ian McEwan.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
// Source: https://github.com/stegu/psrdnoise/blob/419175a270862ce7ae692038fafafb42ec0427e9/src/psrdnoise2.wgsl

struct Coastal_Noise_Gradient {
	value: f32,
	gradient: vec2<f32>,
};

fn coastal_mod289(value: vec3<f32>) -> vec3<f32> {
	return value - floor(value / 289.0) * 289.0;
}

fn coastal_psrdnoise(position: vec2<f32>, period: vec2<f32>, rotation: f32) -> Coastal_Noise_Gradient {
	let skewed = vec2<f32>(position.x + position.y * 0.5, position.y);
	let cell_0 = floor(skewed);
	let local = skewed - cell_0;
	let corner = select(vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), local.x > local.y);
	let cell_1 = cell_0 + corner;
	let cell_2 = cell_0 + vec2<f32>(1.0);
	let vertex_0 = vec2<f32>(cell_0.x - cell_0.y * 0.5, cell_0.y);
	let vertex_1 = vec2<f32>(vertex_0.x + corner.x - corner.y * 0.5, vertex_0.y + corner.y);
	let vertex_2 = vec2<f32>(vertex_0.x + 0.5, vertex_0.y + 1.0);
	let offset_0 = position - vertex_0;
	let offset_1 = position - vertex_1;
	let offset_2 = position - vertex_2;

	var hash_x: vec3<f32>;
	var hash_y: vec3<f32>;
	if (any(period > vec2<f32>(0.0))) {
		var wrapped_x = vec3<f32>(vertex_0.x, vertex_1.x, vertex_2.x);
		var wrapped_y = vec3<f32>(vertex_0.y, vertex_1.y, vertex_2.y);
		if (period.x > 0.0) {
			wrapped_x -= floor(wrapped_x / period.x) * period.x;
		}
		if (period.y > 0.0) {
			wrapped_y -= floor(wrapped_y / period.y) * period.y;
		}
		hash_x = floor(wrapped_x + 0.5 * wrapped_y + 0.5);
		hash_y = floor(wrapped_y + 0.5);
	} else {
		hash_x = vec3<f32>(cell_0.x, cell_1.x, cell_2.x);
		hash_y = vec3<f32>(cell_0.y, cell_1.y, cell_2.y);
	}

	var hash = coastal_mod289(hash_x);
	hash = coastal_mod289((hash * 51.0 + 2.0) * hash + hash_y);
	hash = coastal_mod289((hash * 34.0 + 10.0) * hash);
	let angle = hash * 0.07482 + rotation;
	let gradient_0 = vec2<f32>(cos(angle.x), sin(angle.x));
	let gradient_1 = vec2<f32>(cos(angle.y), sin(angle.y));
	let gradient_2 = vec2<f32>(cos(angle.z), sin(angle.z));
	let weights = max(
		vec3<f32>(0.8) - vec3<f32>(dot(offset_0, offset_0), dot(offset_1, offset_1), dot(offset_2, offset_2)),
		vec3<f32>(0.0),
	);
	let weights_2 = weights * weights;
	let weights_4 = weights_2 * weights_2;
	let gradient_dot_offset = vec3<f32>(
		dot(gradient_0, offset_0),
		dot(gradient_1, offset_1),
		dot(gradient_2, offset_2),
	);
	let value = 10.9 * dot(weights_4, gradient_dot_offset);
	let derivative_weight = -8.0 * weights_2 * weights * gradient_dot_offset;
	let derivative = 10.9 * (
		weights_4.x * gradient_0 + derivative_weight.x * offset_0 +
		weights_4.y * gradient_1 + derivative_weight.y * offset_1 +
		weights_4.z * gradient_2 + derivative_weight.z * offset_2
	);
	return Coastal_Noise_Gradient(value, derivative);
}

struct Coastal_Spectral_Surface {
	displacement: vec3<f32>,
	normal: vec3<f32>,
};

struct Coastal_Gerstner_Wave {
	displacement: vec3<f32>,
	normal_xz: vec2<f32>,
};

fn coastal_rotate(value: vec2<f32>, cosine: f32, sine: f32) -> vec2<f32> {
	return vec2<f32>(
		value.x * cosine - value.y * sine,
		value.x * sine + value.y * cosine,
	);
}

fn coastal_spectral_slope(normal: vec3<f32>) -> vec2<f32> {
	return normal.xz / max(normal.y, 0.08);
}

fn coastal_gerstner_wave(
	world_position: vec2<f32>,
	direction: vec2<f32>,
	wavelength: f32,
	amplitude: f32,
	steepness: f32,
	phase_offset: f32,
) -> Coastal_Gerstner_Wave {
	let wave_number = 6.28318530718 / wavelength;
	let angular_frequency = sqrt(9.81 * wave_number);
	let phase = wave_number * dot(direction, world_position) -
		angular_frequency * scrapbot_time_seconds() + phase_offset;
	let sine = sin(phase);
	let cosine = cos(phase);
	let horizontal = direction * (steepness * amplitude * cosine);
	let height = amplitude * sine;
	let normal_xz = -direction * (amplitude * wave_number * cosine);
	return Coastal_Gerstner_Wave(vec3<f32>(horizontal.x, height, horizontal.y), normal_xz);
}

// Re-sample the engine's continuous spectral field through rotated domains.
// The bands share one FFT dispatch but break up the visibly periodic,
// single-direction silhouette of a lone Phillips spectrum.
fn coastal_spectral_surface(world_position: vec2<f32>) -> Coastal_Spectral_Surface {
	let broad = scrapbot_spectral_surface(world_position);
	let cross_cos = 0.7316889;
	let cross_sin = 0.6816388;
	let cross_scale = 0.57;
	let cross = scrapbot_spectral_surface(
		coastal_rotate(world_position, cross_cos, cross_sin) * cross_scale + vec2<f32>(37.0, 71.0),
	);
	let detail_cos = 0.4535961;
	let detail_sin = -0.8912074;
	let detail_scale = 1.72;
	let detail = scrapbot_spectral_surface(
		coastal_rotate(world_position, detail_cos, detail_sin) * detail_scale + vec2<f32>(-53.0, 19.0),
	);

	let cross_horizontal = coastal_rotate(cross.displacement.xz, cross_cos, -cross_sin);
	let detail_horizontal = coastal_rotate(detail.displacement.xz, detail_cos, -detail_sin);
	let spectral_horizontal = broad.displacement.xz * 0.42 + cross_horizontal * 0.18 + detail_horizontal * 0.045;
	let spectral_height = broad.displacement.y * 0.42 + cross.displacement.y * 0.18 + detail.displacement.y * 0.045;
	var displacement = vec3<f32>(spectral_horizontal.x, spectral_height, spectral_horizontal.y);

	let broad_slope = coastal_spectral_slope(broad.normal) * 0.42;
	let cross_slope = coastal_rotate(
		coastal_spectral_slope(cross.normal),
		cross_cos,
		-cross_sin,
	) * (0.18 * cross_scale);
	let detail_slope = coastal_rotate(
		coastal_spectral_slope(detail.normal),
		detail_cos,
		-detail_sin,
	) * (0.045 * detail_scale);
	var normal_xz = broad_slope + cross_slope + detail_slope;

	let swell = coastal_gerstner_wave(world_position, normalize(vec2<f32>(0.94, 0.34)), 31.0, 0.46, 0.72, 0.0);
	let cross_swell = coastal_gerstner_wave(world_position, normalize(vec2<f32>(-0.38, 0.925)), 18.0, 0.25, 0.58, 1.7);
	let chop = coastal_gerstner_wave(world_position, normalize(vec2<f32>(0.29, 0.957)), 9.5, 0.11, 0.46, 4.1);
	let cross_chop = coastal_gerstner_wave(world_position, normalize(vec2<f32>(-0.83, 0.558)), 6.2, 0.055, 0.34, 2.4);
	displacement += swell.displacement + cross_swell.displacement + chop.displacement + cross_chop.displacement;
	normal_xz += swell.normal_xz + cross_swell.normal_xz + chop.normal_xz + cross_chop.normal_xz;
	return Coastal_Spectral_Surface(displacement, normalize(vec3<f32>(normal_xz.x, 1.0, normal_xz.y)));
}

fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex {
	var output = input;
	let world_position = (input.model * vec4<f32>(input.position, 1.0)).xz;
	let wave = coastal_spectral_surface(world_position);
	output.position += scrapbot_world_vector_to_object(input, wave.displacement);
	output.normal = scrapbot_world_normal_to_object(input, wave.normal);
	return output;
}

fn coastal_detail_normal(
	input: Scrapbot_Fragment,
	geometric_normal: vec3<f32>,
	strength: f32,
) -> vec3<f32> {
	let time = scrapbot_time_seconds();
	let position = input.world_position.xz;
	let wind = normalize(vec2<f32>(0.94, 0.34));
	let crosswind = vec2<f32>(-wind.y, wind.x);
	let flow = vec2<f32>(dot(position, wind), dot(position, crosswind));
	let chop_wind = normalize(wind * 0.78 + crosswind * 0.62);
	let chop_crosswind = vec2<f32>(-chop_wind.y, chop_wind.x);
	let chop_flow = vec2<f32>(dot(position, chop_wind), dot(position, chop_crosswind));
	let swell_scale = vec2<f32>(0.12, 0.31);
	let chop_scale = vec2<f32>(0.38, 1.05);
	let ripple_scale = vec2<f32>(1.1, 3.4);
	let swell = coastal_psrdnoise(
		flow * swell_scale + vec2<f32>(time * 0.055, -time * 0.018),
		vec2<f32>(0.0),
		time * 0.035,
	);
	let chop = coastal_psrdnoise(
		chop_flow * chop_scale + vec2<f32>(time * 0.19, time * 0.045),
		vec2<f32>(0.0),
		-time * 0.11,
	);
	let ripples = coastal_psrdnoise(
		flow * ripple_scale + vec2<f32>(-time * 0.47, time * 0.16),
		vec2<f32>(0.0),
		time * 0.23,
	);
	let footprint = max(length(fwidth(position)), 0.001);
	let chop_visibility = 1.0 - smoothstep(0.18, 0.9, footprint);
	let ripple_visibility = 1.0 - smoothstep(0.045, 0.32, footprint);
	let swell_gradient =
		wind * swell.gradient.x * swell_scale.x +
		crosswind * swell.gradient.y * swell_scale.y;
	let chop_gradient =
		chop_wind * chop.gradient.x * chop_scale.x +
		chop_crosswind * chop.gradient.y * chop_scale.y;
	let ripple_gradient =
		wind * ripples.gradient.x * ripple_scale.x +
		crosswind * ripples.gradient.y * ripple_scale.y;
	let slope = (
		swell_gradient * 0.14 +
		chop_gradient * (0.055 * chop_visibility) +
		ripple_gradient * (0.009 * ripple_visibility)
	) * strength;
	return normalize(geometric_normal + vec3<f32>(-slope.x, 0.0, -slope.y));
}

struct Coastal_Foam_Layers {
	intersection: f32,
	crest: f32,
	combined: f32,
};

fn coastal_foam_layers(
	input: Scrapbot_Fragment,
	geometric_normal: vec3<f32>,
	water_thickness: f32,
	foam_width: f32,
) -> Coastal_Foam_Layers {
	let time = scrapbot_time_seconds();
	let position = input.world_position.xz;
	let wind = normalize(vec2<f32>(0.94, 0.34));
	let crosswind = vec2<f32>(-wind.y, wind.x);
	let flow = vec2<f32>(dot(position, wind), dot(position, crosswind));
	let coarse = coastal_psrdnoise(
		flow * vec2<f32>(0.09, 0.18) + vec2<f32>(time * 0.025, -time * 0.012),
		vec2<f32>(0.0),
		time * 0.025,
	).value * 0.5 + 0.5;
	let medium = coastal_psrdnoise(
		flow * vec2<f32>(0.31, 0.72) + vec2<f32>(-time * 0.075, time * 0.025),
		vec2<f32>(0.0),
		-time * 0.08,
	).value * 0.5 + 0.5;
	let fine = coastal_psrdnoise(
		flow * vec2<f32>(1.05, 2.7) + vec2<f32>(time * 0.21, time * 0.08),
		vec2<f32>(0.0),
		time * 0.16,
	).value * 0.5 + 0.5;

	// View-space depth grows dramatically at grazing angles. Project it onto
	// the water normal so the wash keeps a world-like width instead of drawing
	// a camera-dependent white silhouette around every intersecting mesh.
	let view_projection = max(dot(geometric_normal, input.view_direction), 0.08);
	let projected_depth = water_thickness * view_projection;
	let normalized_depth = projected_depth / max(foam_width, 0.05);
	let depth_aa = max(fwidth(projected_depth) / max(foam_width, 0.05), 0.015);
	let warped_depth = max(
		normalized_depth + (coarse - 0.5) * 0.42 + (medium - 0.5) * 0.13,
		0.0,
	);
	let shore_envelope = 1.0 - smoothstep(0.18, 1.35, warped_depth);
	let leading_center = 0.2 + (coarse - 0.5) * 0.08;
	let trailing_center = 0.58 + (medium - 0.5) * 0.12;
	let leading_ridge = 1.0 - smoothstep(
		0.055 + depth_aa,
		0.18 + depth_aa,
		abs(warped_depth - leading_center),
	);
	let trailing_ridge = 1.0 - smoothstep(
		0.07 + depth_aa,
		0.22 + depth_aa,
		abs(warped_depth - trailing_center),
	);
	let medium_lace = 1.0 - smoothstep(0.07, 0.24, abs(medium - 0.52));
	let fine_lace = 1.0 - smoothstep(0.045, 0.17, abs(fine - 0.56));
	let lace = clamp(medium_lace * 0.7 + fine_lace * 0.3, 0.0, 1.0) *
		smoothstep(0.2, 0.72, coarse);
	let bubbles = smoothstep(0.8, 0.95, fine) * shore_envelope;
	let intersection = clamp(
		(leading_ridge * 0.58 + trailing_ridge * 0.12) * lace * shore_envelope + bubbles * 0.08,
		0.0,
		1.0,
	);

	let compression = scrapbot_spectral_crest(position);
	let crest_shape = smoothstep(0.075, 0.34, compression);
	let crest_ridges = 1.0 - smoothstep(0.08, 0.3, abs(medium - 0.56));
	let crest_breakup = crest_ridges * smoothstep(0.34, 0.74, coarse * 0.6 + fine * 0.4);
	let crest = crest_shape * crest_breakup;
	let combined = 1.0 - (1.0 - intersection) * (1.0 - crest * 0.72);
	return Coastal_Foam_Layers(intersection, crest, clamp(combined, 0.0, 1.0));
}

fn coastal_fresnel(normal: vec3<f32>, view: vec3<f32>) -> f32 {
	let water_f0 = 0.02037;
	let facing = clamp(dot(normal, view), 0.0, 1.0);
	return water_f0 + (1.0 - water_f0) * pow(1.0 - facing, 5.0);
}

fn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface {
	let scattering = scrapbot_parameter(0u);
	let absorption = scrapbot_parameter(1u);
	let foam = scrapbot_parameter(2u);
	let settings = scrapbot_parameter(3u);
	let geometric_normal = normalize(input.world_normal);
	let normal = coastal_detail_normal(input, geometric_normal, max(settings.y, 0.01));
	let stable_scene_uv = scrapbot_scene_stable_uv(input.scene_uv);
	let scene_view_depth = scrapbot_scene_view_depth(input.scene_uv);
	let water_thickness = max(scene_view_depth - input.view_depth, 0.0);
	let optical_depth = min(water_thickness, max(scattering.w, 0.01));

	let refraction_pixels = max(absorption.w, 0.0);
	let refraction_amount = (1.0 - exp(-optical_depth * 0.45)) / max(input.view_depth * 0.08, 1.0);
	let candidate_uv = stable_scene_uv + normal.xz * scrapbot_scene_pixel_size() * refraction_pixels * refraction_amount;
	let stable_candidate_uv = scrapbot_scene_stable_uv(candidate_uv);
	let candidate_depth = scrapbot_scene_view_depth(stable_candidate_uv);
	let refraction_valid = scrapbot_scene_uv_valid(candidate_uv) && candidate_depth > input.view_depth + 0.025;
	let refraction_uv = select(stable_scene_uv, stable_candidate_uv, refraction_valid);
	let behind = scrapbot_scene_color(refraction_uv);

	let transmittance = exp(-max(absorption.rgb, vec3<f32>(0.0001)) * optical_depth);
	let body = behind * transmittance + scattering.rgb * (vec3<f32>(1.0) - transmittance);
	let fresnel = coastal_fresnel(normal, input.view_direction);
	let reflection_direction = reflect(-input.view_direction, normal);
	let reflection = scrapbot_environment_reflection(reflection_direction, max(settings.x, 0.01));
	var color = mix(body, reflection, clamp(fresnel * settings.z, 0.0, 1.0));

	let foam_width = max(foam.w, 0.05);
	let foam_layers = coastal_foam_layers(input, geometric_normal, water_thickness, foam_width);
	let foam_mask = clamp(foam_layers.combined * settings.w, 0.0, 0.82);
	color = mix(color, foam.rgb, foam_mask);

	// This hook has already composited transmission, scattering, reflection, and
	// foam over the opaque scene. Alpha one prevents the transparent pass from
	// blending the opaque scene into that result a second time.
	return Scrapbot_Surface(
		vec4<f32>(color, 1.0),
		normal,
		mix(max(settings.x, 0.01), 0.48, foam_mask),
		vec3<f32>(0.0),
		foam_mask * 0.035,
	);
}
