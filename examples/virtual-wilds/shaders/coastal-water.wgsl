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

fn coastal_rotate_domain(value: vec2<f32>, angle: f32) -> vec2<f32> {
	let cosine = cos(angle);
	let sine = sin(angle);
	return vec2<f32>(
		cosine * value.x - sine * value.y,
		sine * value.x + cosine * value.y,
	);
}

fn coastal_foam_multifractal(position: vec2<f32>, time: f32, ridged: bool) -> f32 {
	var domain = position;
	var transport = vec2<f32>(time * 0.034, -time * 0.016);
	var influence = 0.65;
	var product = 1.0;
	for (var octave = 0u; octave < 4u; octave = octave + 1u) {
		let octave_index = f32(octave);
		let sample = coastal_psrdnoise(
			domain + transport,
			vec2<f32>(0.0),
			0.37 + octave_index * 1.71 + time * (0.006 + octave_index * 0.003),
		).value;
		var signal = sample * 0.5 + 0.5;
		if (ridged) {
			let ridge = 1.0 - abs(sample);
			signal = ridge * ridge;
		}
		// Each octave erodes the structure left by the preceding octave. This
		// preserves broad foam islands while finer bands punch progressively
		// smaller holes instead of averaging into one cloudy noise texture.
		product *= mix(1.0, signal, influence);
		domain = coastal_rotate_domain(
			domain * 2.07 + vec2<f32>(7.13, -4.91),
			1.12,
		);
		transport = coastal_rotate_domain(transport * 1.43, -0.74 - octave_index * 0.11);
		influence *= 0.58;
	}
	return product;
}

struct Coastal_Spectral_Surface {
	displacement: vec3<f32>,
	normal: vec3<f32>,
};

struct Coastal_Gerstner_Wave {
	displacement: vec3<f32>,
	normal_delta: vec3<f32>,
	phase_sine: f32,
	phase: f32,
};

struct Coastal_Gerstner_Bank {
	displacement: vec3<f32>,
	normal: vec3<f32>,
	crest: f32,
	tip: f32,
};

fn coastal_spectral_slope(normal: vec3<f32>) -> vec2<f32> {
	return normal.xz / max(normal.y, 0.08);
}

fn coastal_gerstner_wave(
	world_position: vec2<f32>,
	direction: vec2<f32>,
	wavelength: f32,
	amplitude: f32,
	q: f32,
	phase_offset: f32,
) -> Coastal_Gerstner_Wave {
	let wave_number = 6.28318530718 / wavelength;
	let angular_frequency = sqrt(9.81 * wave_number);
	let phase = wave_number * dot(direction, world_position) -
		angular_frequency * scrapbot_time_seconds() + phase_offset;
	let sine = sin(phase);
	let cosine = cos(phase);
	let horizontal = direction * (q * amplitude * cosine);
	let height = amplitude * sine;
	let normal_delta = vec3<f32>(
		-direction.x * amplitude * wave_number * cosine,
		-q * amplitude * wave_number * sine,
		-direction.y * amplitude * wave_number * cosine,
	);
	return Coastal_Gerstner_Wave(
		vec3<f32>(horizontal.x, height, horizontal.y),
		normal_delta,
		sine,
		phase,
	);
}

fn coastal_wave_domain(world_position: vec2<f32>) -> vec2<f32> {
	let warp = coastal_psrdnoise(world_position * 0.018, vec2<f32>(0.0), 0.73);
	return world_position + vec2<f32>(warp.value, warp.gradient.x * 0.45 + warp.gradient.y * 0.2) * 2.8;
}

fn coastal_gerstner_bank(
	world_position: vec2<f32>,
	crest_footprint: f32,
) -> Coastal_Gerstner_Bank {
	let wave_count = 8u;
	let global_steepness = 0.78;
	let wind_angle = atan2(0.34, 0.94);
	var wavelength = 42.0;
	var amplitude = 0.32;
	var displacement = vec3<f32>(0.0);
	var normal = vec3<f32>(0.0, 1.0, 0.0);
	var crest_ridges = 0.0;
	var tip = 0.0;
	var detail_interference = 0.0;
	var detail_weight = 0.0;

	for (var octave = 0u; octave < wave_count; octave = octave + 1u) {
		let octave_index = f32(octave);
		let octave_fraction = octave_index / f32(wave_count - 1u);
		let directional_spread = mix(0.08, 0.68, octave_fraction);
		let direction_angle = wind_angle +
			sin(octave_index * 2.39996323 + 0.61) * directional_spread;
		let direction = vec2<f32>(cos(direction_angle), sin(direction_angle));
		let wave_number = 6.28318530718 / wavelength;
		// GPU Gems distributes one authored steepness budget over the complete
		// wave set. The sum of Q*k*A therefore remains bounded and cannot fold
		// the surface even as shorter, steeper octaves are added.
		let q = global_steepness /
			max(wave_number * amplitude * f32(wave_count), 0.0001);
		let phase_offset = fract(sin((octave_index + 1.0) * 91.3458) * 47453.5453) *
			6.28318530718;
		let wave = coastal_gerstner_wave(
			world_position,
			direction,
			wavelength,
			amplitude,
			q,
			phase_offset,
		);
		displacement += wave.displacement;
		normal += wave.normal_delta;
		// The broad positive phase is a thin, sun-transmitting wave tip rather
		// than white foam. Keep it on the geometric bands so backlighting reveals
		// the displaced surface volume instead of painting unrelated highlights.
		if (octave < 5u) {
			let tip_band = smoothstep(0.48, 0.96, wave.phase_sine);
			tip = max(tip, tip_band * mix(0.72, 0.2, octave_fraction));
		}
		// Build soft constant-world-width streaks at useful positive peaks. Their
		// projected width never collapses below roughly two pixels; a bright
		// subpixel center reads as a specular scratch rather than aerated water.
		if (octave >= 2u && octave < 7u) {
			let authored_half_width = mix(0.11, 0.045, octave_fraction);
			let filtered_half_width = max(authored_half_width, crest_footprint * 1.15);
			let ridge_threshold = cos(min(wave_number * filtered_half_width, 1.2));
			let along_crest = dot(world_position, vec2<f32>(-direction.y, direction.x));
			let across_crest = dot(world_position, direction);
			let crest_warp = coastal_psrdnoise(
				vec2<f32>(across_crest * 0.075, along_crest * 0.31) +
					vec2<f32>(scrapbot_time_seconds() * 0.012, octave_index * 4.37),
				vec2<f32>(0.0),
				1.19 + octave_index * 0.47,
			).value * mix(0.12, 0.28, octave_fraction);
			let ridge_signal = sin(wave.phase + crest_warp);
			let ridge_feather = max(
				wave_number * crest_footprint * 1.35,
				(1.0 - ridge_threshold) * 0.42,
			);
			let ridge = smoothstep(
				ridge_threshold - ridge_feather,
				ridge_threshold + ridge_feather,
				ridge_signal,
			);
			let ridge_visibility = 1.0 - smoothstep(
				wavelength * 0.055,
				wavelength * 0.16,
				crest_footprint,
			);
			let ridge_strength = mix(0.62, 0.32, octave_fraction) * ridge_visibility;
			let segment_pixel_frequency = 1.0 / max(crest_footprint * 42.0, 0.001);
			let segment_frequency_a = min(
				max(mix(0.82, 1.65, octave_fraction), segment_pixel_frequency),
				24.0,
			);
			let segment_frequency_b = min(
				max(mix(1.7, 3.1, octave_fraction), segment_pixel_frequency * 1.5),
				40.0,
			);
			let segment_noise_a = coastal_psrdnoise(
				vec2<f32>(
					along_crest * segment_frequency_a + octave_index * 3.17,
					scrapbot_time_seconds() * 0.018 + octave_index * 7.13,
				),
				vec2<f32>(0.0),
				0.73 + octave_index * 0.61,
			).value * 0.5 + 0.5;
			let segment_noise_b = coastal_psrdnoise(
				vec2<f32>(
					along_crest * segment_frequency_b - octave_index * 5.41,
					scrapbot_time_seconds() * -0.011 + octave_index * 2.89,
				),
				vec2<f32>(0.0),
				-0.91 - octave_index * 0.38,
			).value * 0.5 + 0.5;
			let segment_a = smoothstep(0.32, 0.64, segment_noise_a);
			let segment_b = smoothstep(0.27, 0.7, segment_noise_b);
			let fine_segment_visibility = 1.0 - smoothstep(0.08, 0.42, crest_footprint);
			let segment = segment_a * mix(1.0, mix(0.22, 1.0, segment_b), fine_segment_visibility);
			crest_ridges = max(
				crest_ridges,
				ridge * ridge_strength * segment,
			);
		}
		if (octave >= 2u) {
			let interference_weight = mix(0.32, 0.08, octave_fraction);
			detail_interference += wave.phase_sine * interference_weight;
			detail_weight += interference_weight;
		}
		wavelength *= 0.62;
		amplitude *= 0.58;
	}

	let compression = clamp(1.0 - normal.y, 0.0, 1.0);
	let breakup = smoothstep(
		-0.28,
		0.42,
		detail_interference / max(detail_weight, 0.0001),
	);
	// Higher octaves and aggregate compression vary ridge intensity, but never
	// replace the ridge topology with an unrelated patch-shaped threshold.
	let crest = crest_ridges *
		mix(0.58, 1.0, breakup) *
		mix(0.82, 1.0, smoothstep(0.015, 0.3, compression));
	return Coastal_Gerstner_Bank(displacement, normalize(normal), crest, tip);
}

// Reserve the FFT field for broad, low-frequency energy. Fine structure comes
// from independent Gerstner directions and non-periodic psrdnoise below; using
// rotated copies of one small FFT tile only disguises repetition for a moment.
fn coastal_spectral_surface(world_position: vec2<f32>) -> Coastal_Spectral_Surface {
	let broad = scrapbot_spectral_surface(world_position);
	var displacement = broad.displacement * 0.52;
	var normal_xz = coastal_spectral_slope(broad.normal) * 0.52;
	let bank = coastal_gerstner_bank(coastal_wave_domain(world_position), 0.0);
	displacement += bank.displacement;
	normal_xz += coastal_spectral_slope(bank.normal);
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
	let direction_a = normalize(vec2<f32>(0.94, 0.34));
	let tangent_a = vec2<f32>(-direction_a.y, direction_a.x);
	let direction_b = normalize(vec2<f32>(-0.43, 0.9));
	let tangent_b = vec2<f32>(-direction_b.y, direction_b.x);
	let domain_a = vec2<f32>(dot(position, direction_a), dot(position, tangent_a));
	let domain_b = vec2<f32>(dot(position, direction_b), dot(position, tangent_b));
	let broad_scale = vec2<f32>(0.24, 0.34);
	let ripple_scale = vec2<f32>(0.72, 0.96);
	let capillary_scale = vec2<f32>(1.55, 2.05);
	let broad = coastal_psrdnoise(
		domain_a * broad_scale + vec2<f32>(time * 0.045, -time * 0.02),
		vec2<f32>(0.0),
		0.31,
	);
	let ripples = coastal_psrdnoise(
		domain_b * ripple_scale + vec2<f32>(-time * 0.16, time * 0.06),
		vec2<f32>(0.0),
		-0.83,
	);
	let capillary = coastal_psrdnoise(
		domain_a * capillary_scale + vec2<f32>(time * 0.34, time * 0.12),
		vec2<f32>(0.0),
		1.47,
	);
	let footprint = max(length(fwidth(position)), 0.001);
	let ripple_visibility = 1.0 - smoothstep(0.3, 1.1, footprint);
	let capillary_visibility = 1.0 - smoothstep(0.09, 0.42, footprint);
	let broad_gradient =
		direction_a * broad.gradient.x * broad_scale.x +
		tangent_a * broad.gradient.y * broad_scale.y;
	let ripple_gradient =
		direction_b * ripples.gradient.x * ripple_scale.x +
		tangent_b * ripples.gradient.y * ripple_scale.y;
	let capillary_gradient =
		direction_a * capillary.gradient.x * capillary_scale.x +
		tangent_a * capillary.gradient.y * capillary_scale.y;
	let slope = (
		broad_gradient * 0.075 +
		ripple_gradient * (0.028 * ripple_visibility) +
		capillary_gradient * (0.006 * capillary_visibility)
	) * strength;
	return normalize(geometric_normal + vec3<f32>(-slope.x, 0.0, -slope.y));
}

struct Coastal_Foam_Layers {
	intersection: f32,
	crest: f32,
	tip: f32,
};

fn coastal_foam_layers(
	input: Scrapbot_Fragment,
	water_column_depth: f32,
	foam_width: f32,
	foam_animation_speed: f32,
) -> Coastal_Foam_Layers {
	let project_time = scrapbot_time_seconds();
	let time = project_time * max(foam_animation_speed, 0.0);
	let position = input.world_position.xz;
	let wind = normalize(vec2<f32>(0.94, 0.34));
	let crosswind = vec2<f32>(-wind.y, wind.x);
	let flow = vec2<f32>(dot(position, wind), dot(position, crosswind));
	let shore_warp = coastal_psrdnoise(
		flow * vec2<f32>(0.065, 0.11) + vec2<f32>(time * 0.018, -time * 0.009),
		vec2<f32>(0.0),
		0.59,
	);
	let warped_flow = flow + vec2<f32>(
		shore_warp.value,
		shore_warp.gradient.x * 0.42 + shore_warp.gradient.y * 0.24,
	) * 2.1;
	let foam_mass = coastal_foam_multifractal(warped_flow * vec2<f32>(0.12, 0.2), time, false);
	let foam_lace = coastal_foam_multifractal(
		coastal_rotate_domain(warped_flow, -0.63) * vec2<f32>(0.34, 0.52) + vec2<f32>(11.7, -3.4),
		time * 1.27,
		true,
	);

	// Use the center ray's exact world-space water column. Refraction's
	// conservative neighbor depth intentionally expands foreground silhouettes
	// and must never drive a metric shoreline band.
	let normalized_depth = water_column_depth / max(foam_width, 0.05);
	let depth_gradient = fwidth(water_column_depth) / max(foam_width, 0.05);
	let warped_depth = max(
		normalized_depth +
			(foam_mass - 0.5) * 0.46 +
			(foam_lace - 0.5) * 0.12,
		0.0,
	);
	// A steep depth discontinuity is an object silhouette, not a shoreline.
	// Reject it and place the visible foam slightly inside stable shallow water
	// so open photogrammetry shells never acquire a white cutout border.
	let depth_confidence = 1.0 - smoothstep(0.32, 0.82, depth_gradient);
	let depth_envelope = smoothstep(0.06, 0.18, warped_depth) *
		(1.0 - smoothstep(0.38, 0.82, warped_depth)) * depth_confidence;
	let shore_envelope = depth_envelope;

	// Screen-space depth can locate contact churn, but it cannot infer a wave
	// travelling up a beach. Keep the depth envelope stationary and carry the
	// visible motion in two independently advected foam layers. Their product
	// forms irregular connected patches instead of a white contour ribbon.
	let foam_pattern = smoothstep(0.18, 0.5, foam_mass * mix(0.58, 1.3, foam_lace));
	let shore_footprint = max(length(fwidth(position)), 0.001);
	let shore_bubble_visibility = 1.0 - smoothstep(0.07, 0.5, shore_footprint);
	let bubbles = smoothstep(0.72, 0.9, foam_lace) * shore_bubble_visibility * shore_envelope;
	let intersection = clamp(
		shore_envelope * mix(0.015, 1.0, foam_pattern) + bubbles * 0.12,
		0.0,
		1.0,
	);

	let compression = max(scrapbot_spectral_crest(position), 0.0);
	let spectral_crest = smoothstep(0.095, 0.3, compression);
	let persistent_spectral_foam = smoothstep(
		0.015,
		0.38,
		scrapbot_spectral_foam(position),
	);
	let wave_position = coastal_wave_domain(position);
	let foam_footprint = max(length(fwidth(position)), 0.001);
	let wave_bank = coastal_gerstner_bank(wave_position, foam_footprint);
	let crest_ridges = wave_bank.crest;

	// Breaking crests follow the wave solution, but the breakup pattern represents
	// passive foam and must drift much more slowly than a deep-water phase. The
	// material setting is converted to a bounded world-space transport speed.
	let foam_drift_speed = max(foam_animation_speed, 0.0) * 0.35;
	let transported_flow = vec2<f32>(
		dot(position, wind) - project_time * foam_drift_speed,
		dot(position, crosswind) + sin(time * 0.17) * 0.24,
	);
	let packet = coastal_psrdnoise(
		transported_flow * vec2<f32>(0.17, 0.42),
		vec2<f32>(0.0),
		0.31,
	).value * 0.5 + 0.5;
	let filament_domain = vec2<f32>(
		transported_flow.x * 0.29 + transported_flow.y * 0.11,
		transported_flow.y * 0.54 - transported_flow.x * 0.07,
	);
	let filament = coastal_psrdnoise(
		filament_domain,
		vec2<f32>(0.0),
		-0.57,
	).value;
	let tear_domain = vec2<f32>(
		transported_flow.y * 0.43 - transported_flow.x * 0.16,
		transported_flow.x * 0.37 + transported_flow.y * 0.09,
	);
	let tear = coastal_psrdnoise(
		tear_domain,
		vec2<f32>(0.0),
		1.37,
	).value;
	let micro = coastal_psrdnoise(
		transported_flow * vec2<f32>(1.35, 4.8),
		vec2<f32>(0.0),
		1.02,
	).value * 0.5 + 0.5;
	let filament_visibility = 1.0 - smoothstep(0.32, 1.4, foam_footprint);
	let micro_visibility = 1.0 - smoothstep(0.08, 0.48, foam_footprint);
	let filament_field = filament * 0.68 + tear * 0.32;
	let filament_breakup = smoothstep(0.42, 0.7, filament_field * 0.5 + 0.5) *
		filament_visibility;
	let breaking_packet = smoothstep(0.5, 0.76, packet);
	let breaking_memory = max(spectral_crest, persistent_spectral_foam);
	// Keep simulation foam on thin crest ridges. Noise changes brightness and
	// continuity only; it never expands a ridge into a detached foam island.
	let peak_line = crest_ridges *
		mix(0.65, 1.0, breaking_packet) *
		mix(0.7, 1.0, filament_breakup) *
		mix(0.72, 1.0, breaking_memory);
	let trailing_foam = crest_ridges * filament_breakup *
		(1.0 - breaking_packet * 0.42);
	let crest_bubbles = smoothstep(0.7, 0.9, micro) * micro_visibility *
		crest_ridges * breaking_packet * 0.035;
	// Retained FFT history spans three resolutions. It may control the life and
	// opacity of resolved Gerstner crest ribbons, but it must never become visible
	// topology of its own: thresholding a simulation grid produces close-range
	// contour scribbles that water must avoid.
	let passive_history = persistent_spectral_foam * crest_ridges *
		mix(0.22, 1.0, filament_breakup) *
		(1.0 - breaking_packet * 0.48);
	let crest = clamp(
		peak_line * 0.72 + trailing_foam * 0.08 + crest_bubbles * 0.22 +
			passive_history * 0.42,
		0.0,
		0.58,
	);
	return Coastal_Foam_Layers(intersection, crest, wave_bank.tip);
}

fn coastal_fresnel(normal: vec3<f32>, view: vec3<f32>) -> f32 {
	let water_f0 = 0.02037;
	let facing = clamp(dot(normal, view), 0.0, 1.0);
	return water_f0 + (1.0 - water_f0) * pow(1.0 - facing, 5.0);
}

fn coastal_schlick_phase_relative(cosine_theta: f32, anisotropy: f32) -> f32 {
	let g = clamp(anisotropy, -0.95, 0.95);
	let k = 1.55 * g - 0.55 * g * g * g;
	let denominator = max(1.0 + k * cosine_theta, 0.04);
	// Omit 1/(4*pi): returning phase relative to isotropic scattering makes
	// the authored light intensity remain useful without a hidden radiometric
	// unit conversion.
	return clamp((1.0 - k * k) / (denominator * denominator), 0.0, 8.0);
}

fn coastal_direct_scattering(
	world_position: vec3<f32>,
	view_depth: f32,
	normal: vec3<f32>,
	view: vec3<f32>,
	medium_albedo: vec3<f32>,
	path_scatter: vec3<f32>,
	wave_tip: f32,
	shore_presence: f32,
) -> vec3<f32> {
	let sun_vector = scrapbot_environment.sun_direction_intensity.xyz;
	let sun_length = length(sun_vector);
	let sun_intensity = scrapbot_environment.sun_direction_intensity.w;
	if (sun_length <= 0.0001 || sun_intensity <= 0.0) {
		return vec3<f32>(0.0);
	}

	let sun_direction = sun_vector / sun_length;
	let sun_visibility = smoothstep(-0.03, 0.08, sun_direction.y);
	// sun_direction points from the surface to the sun. A transmitted photon
	// travels in the opposite direction, so forward scattering peaks when the
	// view direction approaches -sun_direction (a backlit wave).
	let phase = coastal_schlick_phase_relative(
		clamp(dot(sun_direction, view), -1.0, 1.0),
		0.72,
	);
	let shadow_visibility = scrapbot_directional_shadow_visibility(world_position, view_depth);
	let sun_radiance = scrapbot_environment.sun_color.rgb *
		sun_intensity * sun_visibility * shadow_visibility;
	let body = sun_radiance * medium_albedo * path_scatter * phase * 0.038;
	let grazing = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 1.6);
	let tip = sun_radiance * medium_albedo *
		(wave_tip * shore_presence * grazing * min(phase, 4.0) * 0.13);
	return body + tip;
}

// Caustics are evaluated on the opaque receiver visible through this water
// fragment. The wave field refracts the sun ray according to Snell's law; the
// area change of that mapping estimates photon concentration without painting
// an unrelated animated texture over the seabed.
fn coastal_caustic_wave_normal(world_position: vec2<f32>) -> vec3<f32> {
	let wave_count = 11u;
	let global_steepness = 0.78;
	let wind_angle = atan2(0.34, 0.94);
	let domain = coastal_wave_domain(world_position);
	let broad_normal = scrapbot_spectral_normal(world_position);
	var normal = vec3<f32>(
		coastal_spectral_slope(broad_normal).x * 0.52,
		1.0,
		coastal_spectral_slope(broad_normal).y * 0.52,
	);
	var wavelength = 42.0;
	var amplitude = 0.32;
	for (var octave = 0u; octave < wave_count; octave = octave + 1u) {
		let octave_index = f32(octave);
		let octave_fraction = octave_index / 10.0;
		let directional_spread = mix(0.22, 1.35, octave_fraction);
		let direction_angle = wind_angle +
			sin(octave_index * 2.39996323 + 0.61) * directional_spread;
		let direction = vec2<f32>(cos(direction_angle), sin(direction_angle));
		let wave_number = 6.28318530718 / wavelength;
		let q = global_steepness /
			max(wave_number * amplitude * f32(wave_count), 0.0001);
		let phase_offset = fract(sin((octave_index + 1.0) * 91.3458) * 47453.5453) *
			6.28318530718;
		let wave = coastal_gerstner_wave(
			domain,
			direction,
			wavelength,
			amplitude,
			q,
			phase_offset,
		);
		normal += wave.normal_delta * mix(0.35, 1.35, octave_fraction);
		wavelength *= 0.62;
		amplitude *= 0.58;
	}
	return normalize(normal);
}

fn coastal_caustic_receiver(
	entry_position: vec2<f32>,
	water_height: f32,
	receiver_height: f32,
	sun_direction: vec3<f32>,
) -> vec2<f32> {
	let surface_normal = coastal_caustic_wave_normal(entry_position);
	let transmitted = refract(-sun_direction, surface_normal, 1.0 / 1.333);
	let travel_distance = max(
		(receiver_height - water_height) / min(transmitted.y, -0.04),
		0.0,
	);
	return entry_position + transmitted.xz * travel_distance;
}

fn coastal_projected_caustics(
	input: Scrapbot_Fragment,
	scene_view_depth: f32,
	extinction: vec3<f32>,
) -> vec3<f32> {
	let sun_vector = scrapbot_environment.sun_direction_intensity.xyz;
	let sun_length = length(sun_vector);
	let sun_intensity = scrapbot_environment.sun_direction_intensity.w;
	if (sun_length <= 0.0001 || sun_intensity <= 0.0) {
		return vec3<f32>(0.0);
	}

	let sun_direction = sun_vector / sun_length;
	let sun_presence = smoothstep(0.015, 0.12, sun_direction.y);
	if (sun_presence <= 0.0) {
		return vec3<f32>(0.0);
	}

	let receiver_position = scrapbot_world_position_on_fragment_ray(input, scene_view_depth);
	let water_column = max(input.world_position.y - receiver_position.y, 0.0);
	let depth_presence = smoothstep(0.12, 0.45, water_column) *
		(1.0 - smoothstep(11.0, 24.0, water_column));

	// One inverse-map correction is sufficient because the undisplaced mapping
	// is identity. It keeps the caustic attached to the receiving rock instead
	// of sliding in screen space as the camera moves.
	let initial_normal = coastal_caustic_wave_normal(receiver_position.xz);
	let initial_transmitted = refract(-sun_direction, initial_normal, 1.0 / 1.333);
	let initial_travel = max(
		(receiver_position.y - input.world_position.y) /
			min(initial_transmitted.y, -0.04),
		0.0,
	);
	var entry_position = receiver_position.xz - initial_transmitted.xz * initial_travel;
	let projected_receiver = coastal_caustic_receiver(
		entry_position,
		input.world_position.y,
		receiver_position.y,
		sun_direction,
	);
	entry_position -= projected_receiver - receiver_position.xz;

	// A finite ray differential measures the projected area change. Grow its
	// baseline with the receiver footprint so distant caustics filter instead of
	// sparkling under TAA.
	let receiver_footprint = max(length(fwidth(receiver_position.xz)), 0.001);
	let differential = clamp(max(0.05, receiver_footprint * 0.7), 0.05, 0.7);
	let mapped_center = coastal_caustic_receiver(
		entry_position,
		input.world_position.y,
		receiver_position.y,
		sun_direction,
	);
	let mapped_x = coastal_caustic_receiver(
		entry_position + vec2<f32>(differential, 0.0),
		input.world_position.y,
		receiver_position.y,
		sun_direction,
	);
	let mapped_z = coastal_caustic_receiver(
		entry_position + vec2<f32>(0.0, differential),
		input.world_position.y,
		receiver_position.y,
		sun_direction,
	);
	let derivative_x = (mapped_x - mapped_center) / differential;
	let derivative_z = (mapped_z - mapped_center) / differential;
	let area_jacobian = abs(
		derivative_x.x * derivative_z.y - derivative_x.y * derivative_z.x,
	);
	// Photon density is the inverse mapped area. Suppress the unfocused unit
	// baseline, then use a nonlinear shoulder so several differently oriented
	// short-wave bands form connected luminous cells instead of isolated dots.
	let focused_flux = 1.0 / max(area_jacobian, 0.08);
	let focused_excess = max(focused_flux - 1.0, 0.0);
	let caustic_signal = smoothstep(0.04, 0.9, focused_excess);
	let focus = pow(caustic_signal, 1.6) * min(focused_excess * 0.65, 2.2);

	let receiver_dx = dpdx(receiver_position);
	let receiver_dy = dpdy(receiver_position);
	var receiver_normal = normalize(cross(receiver_dy, receiver_dx));
	let receiver_view = normalize(render.camera_position.xyz - receiver_position);
	if (dot(receiver_normal, receiver_view) < 0.0) {
		receiver_normal = -receiver_normal;
	}
	// The opaque depth buffer has no receiver-normal channel. Reconstructed
	// derivatives are reliable on coherent surfaces but can flip on thin or
	// open scanned shells, so use the two-sided cosine with a low diffuse floor.
	// The floor also approximates light scattered back onto near-vertical rock.
	let receiver_incidence = sqrt(clamp(abs(dot(receiver_normal, sun_direction)), 0.06, 1.0));
	let depth_discontinuity = fwidth(scene_view_depth) / max(water_column, 0.2);
	let receiver_confidence = 1.0 - smoothstep(0.65, 2.4, depth_discontinuity);
	let shadow_visibility = scrapbot_directional_shadow_visibility(
		receiver_position,
		scene_view_depth,
	);
	let transmitted_path = water_column / max(-initial_transmitted.y, 0.08);
	let sunlight_transmittance = exp(-extinction * transmitted_path);
	return scrapbot_environment.sun_color.rgb * sunlight_transmittance *
		(focus * sun_intensity * 2.0 * sun_presence * depth_presence *
			receiver_incidence * receiver_confidence * shadow_visibility);
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
	let water_column_depth = scrapbot_water_column_depth(input, geometric_normal);
	// Apply a second smooth attenuation so the final metre clears much faster
	// than ordinary Beer-Lambert extinction alone.
	let shore_body_presence = smoothstep(0.03, 3.0, water_column_depth);
	let shore_optical_presence = shore_body_presence * shore_body_presence * shore_body_presence;
	let optical_depth = min(water_thickness, max(scattering.w, 0.01)) * shore_optical_presence;
	let water_footprint = max(length(fwidth(input.world_position.xz)), 0.001);
	// A distant glossy normal field aliases into hard bands. Production water
	// systems expose separate distant smoothness for the same reason: broaden
	// the reflection lobe as the projected surface footprint grows.
	let distance_roughness = smoothstep(0.22, 1.5, water_footprint);
	let water_roughness = mix(max(settings.x, 0.01), 0.14, distance_roughness);

	let refraction_pixels = max(absorption.w, 0.0);
	let refraction_amount = (1.0 - exp(-optical_depth * 0.45)) / max(input.view_depth * 0.08, 1.0);
	let candidate_uv = stable_scene_uv + normal.xz * scrapbot_scene_pixel_size() * refraction_pixels * refraction_amount;
	let stable_candidate_uv = scrapbot_scene_stable_uv(candidate_uv);
	let candidate_depth = scrapbot_scene_view_depth(stable_candidate_uv);
	let refraction_valid = scrapbot_scene_uv_valid(candidate_uv) && candidate_depth > input.view_depth + 0.025;
	let refraction_uv = select(stable_scene_uv, stable_candidate_uv, refraction_valid);
	var behind = scrapbot_scene_color(refraction_uv);

	let scattering_coefficient = max(scattering.rgb, vec3<f32>(0.0));
	let absorption_coefficient = max(absorption.rgb, vec3<f32>(0.0001));
	let extinction = scattering_coefficient + absorption_coefficient;
	let caustic_modulation = coastal_projected_caustics(
		input,
		scene_view_depth,
		extinction,
	);
	behind *= vec3<f32>(1.0) + caustic_modulation;
	let transmittance = exp(-extinction * optical_depth);
	let path_scatter = vec3<f32>(1.0) - transmittance;
	let medium_albedo = scattering_coefficient / max(extinction, vec3<f32>(0.0001));
	let ambient_incident = scrapbot_environment_reflection(vec3<f32>(0.0, 1.0, 0.0), 1.0);
	var body = behind * transmittance + ambient_incident * medium_albedo * path_scatter * 0.24;
	let fresnel = coastal_fresnel(normal, input.view_direction);
	let reflection_direction = reflect(-input.view_direction, normal);
	let environment_reflection = scrapbot_environment_reflection(reflection_direction, water_roughness);
	let screen_reflection = scrapbot_screen_space_reflection(
		input,
		normal,
		min(90.0, max(input.view_depth * 1.6, 18.0)),
		max(0.16, input.view_depth * 0.012),
	);
	let reflection = mix(
		environment_reflection,
		screen_reflection.rgb,
		screen_reflection.a * (1.0 - water_roughness) * 0.86,
	);
	// Face-on shallow water becomes almost completely transmissive, but retain
	// Fresnel at grazing angles where even a thin water film remains reflective.
	let detail_facing = clamp(dot(normal, input.view_direction), 0.0, 1.0);
	let grazing_preservation = pow(1.0 - detail_facing, 3.0);
	let shallow_reflection_presence = mix(
		shore_body_presence,
		1.0,
		grazing_preservation,
	);
	let foam_width = max(foam.w, 0.05);
	let foam_layers = coastal_foam_layers(input, water_column_depth, foam_width, settings.z);
	body += coastal_direct_scattering(
		input.world_position,
		input.view_depth,
		normal,
		input.view_direction,
		medium_albedo,
		path_scatter,
		foam_layers.tip,
		shore_body_presence,
	);
	var color = mix(body, reflection, fresnel * shallow_reflection_presence);

	let shore_foam = foam_layers.intersection * settings.w;
	let crest_foam = smoothstep(0.035, 0.46, foam_layers.crest) * 0.52;
	let foam_mask = clamp(1.0 - (1.0 - shore_foam) * (1.0 - crest_foam), 0.0, 0.68);
	let foam_color = foam.rgb * 0.62 + reflection * 0.045;
	color = mix(color, foam_color, foam_mask);

	// This hook has already composited transmission, scattering, reflection, and
	// foam over the opaque scene. Alpha one prevents the transparent pass from
	// blending the opaque scene into that result a second time.
	return Scrapbot_Surface(
		vec4<f32>(color, 1.0),
		normal,
		mix(water_roughness, 0.58, foam_mask),
		vec3<f32>(0.0),
		0.0,
	);
}
