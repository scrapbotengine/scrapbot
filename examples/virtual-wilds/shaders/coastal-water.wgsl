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

fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex {
	var output = input;
	let world_position = (input.model * vec4<f32>(input.position, 1.0)).xz;
	let wave = scrapbot_spectral_surface(world_position);
	output.position.y += wave.x;
	output.normal = normalize(vec3<f32>(-wave.y, 1.0, -wave.z));
	return output;
}

fn coastal_detail_normal(input: Scrapbot_Fragment, geometric_normal: vec3<f32>) -> vec3<f32> {
	let time = scrapbot_time_seconds();
	let position = input.world_position.xz;
	let agitation = coastal_psrdnoise(position * 0.42 + vec2<f32>(time * 0.12, -time * 0.08), vec2<f32>(0.0), time * 0.08);
	let ripples = coastal_psrdnoise(position * 1.65 + vec2<f32>(-time * 0.31, time * 0.24), vec2<f32>(0.0), -time * 0.17);
	let footprint = max(length(fwidth(position)), 0.001);
	let ripple_visibility = 1.0 - smoothstep(0.12, 0.55, footprint);
	let slope = agitation.gradient * 0.075 + ripples.gradient * (0.018 * ripple_visibility);
	return normalize(geometric_normal + vec3<f32>(-slope.x, 0.0, -slope.y));
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
	let normal = coastal_detail_normal(input, geometric_normal);
	let stable_scene_uv = scrapbot_scene_stable_uv(input.scene_uv);
	let scene_view_depth = scrapbot_scene_view_depth(stable_scene_uv);
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
	let reflection = scrapbot_environment_reflection(reflection_direction, 0.08);
	var color = mix(body, reflection, clamp(fresnel * settings.z, 0.0, 1.0));

	let foam_width = max(foam.w, 0.05);
	let foam_noise = coastal_psrdnoise(
		input.world_position.xz * 0.38 + vec2<f32>(scrapbot_time_seconds() * 0.08, -scrapbot_time_seconds() * 0.045),
		vec2<f32>(0.0),
		scrapbot_time_seconds() * 0.04,
	).value * 0.5 + 0.5;
	let shoreline = 1.0 - smoothstep(max(fwidth(water_thickness) * 1.5, 0.025), foam_width, water_thickness);
	let broken_shore = shoreline * smoothstep(0.16, 0.68, foam_noise + shoreline * 0.24);
	let wave = scrapbot_spectral_surface(input.world_position.xz);
	let steepness = length(wave.yz);
	let crest = smoothstep(0.18, 0.72, wave.x + steepness * 0.42) * smoothstep(0.48, 0.78, foam_noise);
	let foam_mask = clamp((broken_shore + crest * 0.32) * settings.w, 0.0, 0.88);
	color = mix(color, foam.rgb, foam_mask);

	// This hook has already composited transmission, scattering, reflection, and
	// foam over the opaque scene. Alpha one prevents the transparent pass from
	// blending the opaque scene into that result a second time.
	return Scrapbot_Surface(
		vec4<f32>(color, 1.0),
		normal,
		mix(0.08, 0.32, foam_mask),
		vec3<f32>(0.0),
		foam_mask * 0.035,
	);
}
