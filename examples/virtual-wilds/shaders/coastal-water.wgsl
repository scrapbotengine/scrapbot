fn wave_height(position: vec2<f32>, time: f32) -> f32 {
	let settings = scrapbot_parameter(3u);
	let scale = settings.x;
	let speed = settings.y;
	let first = sin(dot(position, vec2<f32>(0.82, 0.57)) * scale * 5.2 + time * speed);
	let second = sin(dot(position, vec2<f32>(-0.34, 0.94)) * scale * 8.7 - time * speed * 1.31);
	let swell = sin(dot(position, vec2<f32>(0.17, 0.98)) * scale * 2.4 + time * speed * 0.42);
	return first * 0.075 + second * 0.035 + swell * 0.11;
}

fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex {
	var output = input;
	let time = scrapbot_time_seconds();
	let position = input.position.xz * vec2<f32>(84.0, 300.0);
	let epsilon = 0.08;
	let center = wave_height(position, time);
	let dx = wave_height(position + vec2<f32>(epsilon, 0.0), time) - center;
	let dz = wave_height(position + vec2<f32>(0.0, epsilon), time) - center;
	output.position.y += center;
	output.normal = normalize(vec3<f32>(-dx / epsilon, 1.0, -dz / epsilon));
	return output;
}

fn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface {
	let shallow = scrapbot_parameter(0u);
	let deep = scrapbot_parameter(1u);
	let foam = scrapbot_parameter(2u);
	let settings = scrapbot_parameter(3u);
	let pixel = scrapbot_pixel_size();
	let neighbor_depth = min(
		min(scrapbot_scene_depth(input.screen_uv + vec2<f32>(pixel.x * 2.0, 0.0)), scrapbot_scene_depth(input.screen_uv - vec2<f32>(pixel.x * 2.0, 0.0))),
		min(scrapbot_scene_depth(input.screen_uv + vec2<f32>(0.0, pixel.y * 2.0)), scrapbot_scene_depth(input.screen_uv - vec2<f32>(0.0, pixel.y * 2.0)))
	);
	let depth_gap = max(min(input.scene_depth, neighbor_depth) - input.fragment_depth, 0.0);
	let water_depth = smoothstep(0.0008, 0.035, depth_gap);
	let foam_width = max(foam.w, 0.0002);
	let shore_foam = smoothstep(0.00003, foam_width * 0.35, depth_gap) * (1.0 - smoothstep(foam_width * 0.35, foam_width, depth_gap));
	let ripple = sin(dot(input.world_position.xz, vec2<f32>(0.61, -0.43)) * 2.7 + scrapbot_time_seconds() * 1.8);
	let crest = smoothstep(0.82, 1.0, ripple) * 0.04;
	let foam_mask = clamp((shore_foam + crest) * (0.82 + ripple * 0.18) * settings.w, 0.0, 1.0);
	let view_fresnel = pow(1.0 - clamp(dot(input.world_normal, input.view_direction), 0.0, 1.0), 4.0);
	let refract_uv = input.screen_uv + input.world_normal.xz * deep.w * (0.25 + water_depth * 0.75);
	let behind = scrapbot_scene_color(refract_uv);
	let body = mix(shallow.rgb, deep.rgb, water_depth);
	let transmitted = mix(behind, body, 0.82 + water_depth * 0.13);
	let reflected = mix(transmitted, vec3<f32>(0.28, 0.48, 0.58), view_fresnel * settings.z);
	let color = mix(reflected, foam.rgb, foam_mask);
	let alpha = clamp(shallow.a + water_depth * 0.16 + view_fresnel * 0.1 + foam_mask * 0.2, 0.0, 0.98);
	return Scrapbot_Surface(
		vec4<f32>(color, alpha),
		input.world_normal,
		mix(0.2, 0.05, foam_mask),
		color * 0.08,
		foam_mask * 0.08,
	);
}
