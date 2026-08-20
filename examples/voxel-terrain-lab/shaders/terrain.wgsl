fn terrain_hash(position: vec3<f32>) -> f32 {
	return fract(sin(dot(position, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

fn terrain_noise(position: vec3<f32>) -> f32 {
	let cell = floor(position);
	let local = fract(position);
	let blend = local * local * (vec3<f32>(3.0) - 2.0 * local);
	let x00 = mix(terrain_hash(cell), terrain_hash(cell + vec3<f32>(1.0, 0.0, 0.0)), blend.x);
	let x10 = mix(terrain_hash(cell + vec3<f32>(0.0, 1.0, 0.0)), terrain_hash(cell + vec3<f32>(1.0, 1.0, 0.0)), blend.x);
	let x01 = mix(terrain_hash(cell + vec3<f32>(0.0, 0.0, 1.0)), terrain_hash(cell + vec3<f32>(1.0, 0.0, 1.0)), blend.x);
	let x11 = mix(terrain_hash(cell + vec3<f32>(0.0, 1.0, 1.0)), terrain_hash(cell + vec3<f32>(1.0, 1.0, 1.0)), blend.x);
	let y0 = mix(x00, x10, blend.y);
	let y1 = mix(x01, x11, blend.y);
	return mix(y0, y1, blend.z);
}

fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex {
	return input;
}

fn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface {
	let deep_grass = scrapbot_parameter(0u);
	let sunlit_grass = scrapbot_parameter(1u);
	let weathered_rock = scrapbot_parameter(2u);
	let exposed_soil = scrapbot_parameter(3u);
	let geometric_normal = normalize(input.world_normal);
	let lighting_normal = select(-geometric_normal, geometric_normal, dot(geometric_normal, input.view_direction) >= 0.0);

	let broad_noise = terrain_noise(input.world_position * max(deep_grass.w, 0.01));
	let detail = terrain_noise(input.world_position * 2.35);
	let variation = (broad_noise - 0.5) * 2.0 * exposed_soil.w + (detail - 0.5) * 0.08;
	let grass = mix(deep_grass.rgb, sunlit_grass.rgb, clamp(broad_noise * 0.72 + detail * 0.28, 0.0, 1.0));
	let mineral = mix(exposed_soil.rgb, weathered_rock.rgb, smoothstep(0.28, 0.76, detail + geometric_normal.y * 0.16));
	let upward = clamp(geometric_normal.y, 0.0, 1.0);
	let grass_mask = smoothstep(weathered_rock.w, sunlit_grass.w, upward + variation * 0.18);
	let color = max(mix(mineral, grass, grass_mask) * (1.0 + variation), vec3<f32>(0.0));
	let roughness = mix(0.96, 1.0, clamp(broad_noise * 0.65 + (1.0 - grass_mask) * 0.35, 0.0, 1.0));

	return Scrapbot_Surface(
		vec4<f32>(color, 1.0),
		lighting_normal,
		roughness,
		vec3<f32>(0.0),
		0.0,
	);
}
