package showcase

import "base:intrinsics"
import "core:math"
import scrapbot "scrapbot:extension"

Spin_Component :: scrapbot.Component {
	name = "showcase.spin",
}
Spin_Angular_Velocity :: scrapbot.Vec3_Field {
	component = Spin_Component,
	name = "angular_velocity",
}

Lifetime_Component :: scrapbot.Component {
	name = "showcase.lifetime",
}
Lifetime_Timer :: scrapbot.Vec3_Field {
	component = Lifetime_Component,
	name = "timer",
}

Velocity_Component :: scrapbot.Component {
	name = "showcase.velocity",
}
Velocity_Value :: scrapbot.Vec3_Field {
	component = Velocity_Component,
	name = "value",
}

Emitter_Component :: scrapbot.Component {
	name = "showcase.emitter",
	advanced = true,
}
Emitter_Elapsed :: scrapbot.Number_Field {
	component = Emitter_Component,
	name = "elapsed",
}
Emitter_Sequence :: scrapbot.Number_Field {
	component = Emitter_Component,
	name = "sequence",
}

Fountain_Component :: scrapbot.Component {
	name = "showcase.fountain",
}
Fountain_Spawn_Rate :: scrapbot.Number_Field {
	component = Fountain_Component,
	name = "spawn_rate",
}
Fountain_Burst_Limit :: scrapbot.Number_Field {
	component = Fountain_Component,
	name = "burst_limit",
}
Fountain_Launch_Speed :: scrapbot.Number_Field {
	component = Fountain_Component,
	name = "launch_speed",
}

Light_Orbit_Component :: scrapbot.Component {
	name = "showcase.light_orbit",
}
Light_Orbit_Settings :: scrapbot.Vec3_Field {
	component = Light_Orbit_Component,
	name = "settings",
}

Fountain_Geometry: scrapbot.Resource_Handle
Fountain_Material: scrapbot.Resource_Handle

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)
	generated_cube := scrapbot.cube_geometry(2)
	Fountain_Geometry = scrapbot.register_generated_geometry(&reg, "cube", &generated_cube)
	Fountain_Material = scrapbot.material(&reg, "fountain", {0.95, 0.38, 0.18, 1})

	spin_fields := [?]scrapbot.Field{scrapbot.vec3(Spin_Angular_Velocity)}
	scrapbot.component(&reg, Spin_Component, spin_fields[:])

	lifetime_fields := [?]scrapbot.Field{scrapbot.vec3(Lifetime_Timer)}
	scrapbot.component(&reg, Lifetime_Component, lifetime_fields[:])

	velocity_fields := [?]scrapbot.Field{scrapbot.vec3(Velocity_Value)}
	scrapbot.component(&reg, Velocity_Component, velocity_fields[:])

	emitter_fields := [?]scrapbot.Field {
		scrapbot.number(Emitter_Elapsed),
		scrapbot.number(Emitter_Sequence),
	}
	scrapbot.component(&reg, Emitter_Component, emitter_fields[:])

	fountain_fields := [?]scrapbot.Field {
		scrapbot.number_draggable(Fountain_Spawn_Rate, 0.25, 0),
		scrapbot.number_draggable(Fountain_Burst_Limit, 1, 1, 64),
		scrapbot.number_draggable(Fountain_Launch_Speed, 0.1, 0),
	}
	scrapbot.component(&reg, Fountain_Component, fountain_fields[:])

	light_orbit_fields := [?]scrapbot.Field{scrapbot.vec3(Light_Orbit_Settings)}
	scrapbot.component(&reg, Light_Orbit_Component, light_orbit_fields[:])

	spin_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Spin_Component),
	}
	scrapbot.system(&reg, "autorotate", spin_accesses[:], autorotate_system)

	lifetime_accesses := [?]scrapbot.Access {
		scrapbot.read(Lifetime_Component),
		scrapbot.write(Lifetime_Component),
	}
	scrapbot.system(&reg, "lifetime", lifetime_accesses[:], lifetime_system)

	velocity_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Lifetime_Component),
		scrapbot.read(Velocity_Component),
		scrapbot.write(Velocity_Component),
	}
	scrapbot.system(&reg, "rigidbody", velocity_accesses[:], rigidbody_system)

	emitter_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Component{name = "scrapbot.geometry"}),
		scrapbot.write(scrapbot.Component{name = "scrapbot.material"}),
		scrapbot.write(scrapbot.Shadow_Caster_Component),
		scrapbot.read(Emitter_Component),
		scrapbot.write(Emitter_Component),
		scrapbot.read(Fountain_Component),
		scrapbot.write(Lifetime_Component),
		scrapbot.write(Velocity_Component),
		scrapbot.write(Spin_Component),
	}
	scrapbot.system(&reg, "emit", emitter_accesses[:], emit_system)

	light_orbit_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(scrapbot.Point_Light_Component),
		scrapbot.read(Light_Orbit_Component),
	}
	scrapbot.system(&reg, "orbit", light_orbit_accesses[:], orbit_system)

	return scrapbot.err(&reg)
}

autorotate_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component{scrapbot.Transform_Component, Spin_Component}
	spin_query := scrapbot.query(components[:])
	chunk: scrapbot.Query_Chunk
	if !scrapbot.init_query_chunk(&chunk, spin_query) {
		return "failed to initialize autorotate chunk"
	}
	transforms: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Transform
	angular_velocities: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Vec3
	transform_binding, transform_ok := scrapbot.bind_transform(&chunk, transforms[:], .Write)
	_, velocity_ok := scrapbot.bind_vec3(&chunk, Spin_Angular_Velocity, angular_velocities[:])
	if !transform_ok || !velocity_ok {
		return "failed to bind autorotate chunk"
	}
	delta_time := scrapbot.F32x4(ctx.time.delta_time)
	for {
		count, err := scrapbot.next_chunk(ctx, &chunk)
		if err != nil {
			return err
		}
		if count == 0 {
			break
		}
		lane := 0
		for lane + 4 <= count {
			rotation := scrapbot.load_transform_rotations_x4(transforms[:], lane)
			velocity := scrapbot.load_vec3x4(angular_velocities[:], lane)
			rotation.x = intrinsics.fused_mul_add(velocity.x, delta_time, rotation.x)
			rotation.y = intrinsics.fused_mul_add(velocity.y, delta_time, rotation.y)
			rotation.z = intrinsics.fused_mul_add(velocity.z, delta_time, rotation.z)
			scrapbot.store_transform_rotations_x4(transforms[:], rotation, lane)
			lane += 4
		}
		for lane < count {
			transforms[lane].rotation.x += angular_velocities[lane].x * ctx.time.delta_time
			transforms[lane].rotation.y += angular_velocities[lane].y * ctx.time.delta_time
			transforms[lane].rotation.z += angular_velocities[lane].z * ctx.time.delta_time
			lane += 1
		}
		scrapbot.chunk_write_all(&chunk, transform_binding)
		if err := scrapbot.commit_chunk(ctx, &chunk); err != nil {
			return err
		}
	}

	return nil
}

orbit_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		scrapbot.Point_Light_Component,
		Light_Orbit_Component,
	}
	light_query := scrapbot.query(components[:])

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, light_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		settings, settings_ok := scrapbot.get(ctx, entity, Light_Orbit_Settings)
		if !transform_ok || !settings_ok {
			return "failed to read orbiting point light"
		}

		transform.rotation.y += settings.y * ctx.time.delta_time
		transform.position.x = math.cos(transform.rotation.y) * settings.x
		transform.position.y = settings.z
		transform.position.z = math.sin(transform.rotation.y) * settings.x
		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write orbiting point light transform"
		}
	}

	return nil
}

lifetime_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component{Lifetime_Component}
	lifetime_query := scrapbot.query(components[:])
	chunk: scrapbot.Query_Chunk
	if !scrapbot.init_query_chunk(&chunk, lifetime_query) {
		return "failed to initialize lifetime chunk"
	}
	timers: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Vec3
	timer_binding, timer_ok := scrapbot.bind_vec3(&chunk, Lifetime_Timer, timers[:], .Write)
	if !timer_ok {
		return "failed to bind lifetime chunk"
	}
	delta_time := scrapbot.F32x4(ctx.time.delta_time)
	for {
		count, err := scrapbot.next_chunk(ctx, &chunk)
		if err != nil {
			return err
		}
		if count == 0 {
			break
		}
		expired_mask: u64
		lane := 0
		for lane + 4 <= count {
			timer := scrapbot.load_vec3x4(timers[:], lane)
			timer.x = intrinsics.simd_add(timer.x, delta_time)
			expired := intrinsics.simd_lanes_ge(timer.x, timer.y)
			expired_mask |= scrapbot.simd_mask_bits(expired) << u64(lane)
			scrapbot.store_vec3x4(timers[:], timer, lane)
			lane += 4
		}
		for lane < count {
			timers[lane].x += ctx.time.delta_time
			if timers[lane].x >= timers[lane].y {
				expired_mask |= u64(1) << u64(lane)
			}
			lane += 1
		}
		scrapbot.chunk_write_mask(&chunk, timer_binding, ~expired_mask)
		if err := scrapbot.commit_chunk(ctx, &chunk); err != nil {
			return err
		}
		for lane in 0 ..< count {
			if expired_mask & (u64(1) << u64(lane)) == 0 {
				continue
			}
			if err := scrapbot.despawn(ctx, chunk.entities[lane]); err != nil {
				return err
			}
		}
	}

	return nil
}

rigidbody_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Velocity_Component,
		Lifetime_Component,
	}
	velocity_query := scrapbot.query(components[:])
	chunk: scrapbot.Query_Chunk
	if !scrapbot.init_query_chunk(&chunk, velocity_query) {
		return "failed to initialize rigidbody chunk"
	}
	transforms: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Transform
	velocities: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Vec3
	transform_binding, transform_ok := scrapbot.bind_transform(&chunk, transforms[:], .Write)
	velocity_binding, velocity_ok := scrapbot.bind_vec3(
		&chunk,
		Velocity_Value,
		velocities[:],
		.Write,
	)
	if !transform_ok || !velocity_ok {
		return "failed to bind rigidbody chunk"
	}
	delta_time := scrapbot.F32x4(ctx.time.delta_time)
	gravity := scrapbot.F32x4(4.8 * ctx.time.delta_time)
	damping := scrapbot.F32x4(0.996)
	minimum_y := scrapbot.F32x4(-1.6)
	for {
		count, err := scrapbot.next_chunk(ctx, &chunk)
		if err != nil {
			return err
		}
		if count == 0 {
			break
		}
		removed_mask: u64
		lane := 0
		for lane + 4 <= count {
			position := scrapbot.load_transform_positions_x4(transforms[:], lane)
			velocity := scrapbot.load_vec3x4(velocities[:], lane)
			position.x = intrinsics.fused_mul_add(velocity.x, delta_time, position.x)
			position.y = intrinsics.fused_mul_add(velocity.y, delta_time, position.y)
			position.z = intrinsics.fused_mul_add(velocity.z, delta_time, position.z)
			velocity.y = intrinsics.simd_sub(velocity.y, gravity)
			velocity.x = intrinsics.simd_mul(velocity.x, damping)
			velocity.z = intrinsics.simd_mul(velocity.z, damping)
			removed := intrinsics.simd_lanes_lt(position.y, minimum_y)
			removed_mask |= scrapbot.simd_mask_bits(removed) << u64(lane)
			scrapbot.store_transform_positions_x4(transforms[:], position, lane)
			scrapbot.store_vec3x4(velocities[:], velocity, lane)
			lane += 4
		}
		for lane < count {
			transforms[lane].position.x += velocities[lane].x * ctx.time.delta_time
			transforms[lane].position.y += velocities[lane].y * ctx.time.delta_time
			transforms[lane].position.z += velocities[lane].z * ctx.time.delta_time
			velocities[lane].y -= 4.8 * ctx.time.delta_time
			velocities[lane].x *= 0.996
			velocities[lane].z *= 0.996
			if transforms[lane].position.y < -1.6 {
				removed_mask |= u64(1) << u64(lane)
			}
			lane += 1
		}
		active_mask := ~removed_mask
		scrapbot.chunk_write_mask(&chunk, transform_binding, active_mask)
		scrapbot.chunk_write_mask(&chunk, velocity_binding, active_mask)
		if err := scrapbot.commit_chunk(ctx, &chunk); err != nil {
			return err
		}
		for lane in 0 ..< count {
			if removed_mask & (u64(1) << u64(lane)) == 0 {
				continue
			}
			if err := scrapbot.despawn(ctx, chunk.entities[lane]); err != nil {
				return err
			}
		}
	}

	return nil
}

emit_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Emitter_Component,
		Fountain_Component,
	}
	emitter_query := scrapbot.query(components[:])

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, emitter_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read emitter transform"
		}

		elapsed, elapsed_ok := scrapbot.get(ctx, entity, Emitter_Elapsed)
		sequence, sequence_ok := scrapbot.get(ctx, entity, Emitter_Sequence)
		if !elapsed_ok || !sequence_ok {
			return "failed to read emitter state"
		}
		spawn_rate_value, spawn_rate_ok := scrapbot.get(ctx, entity, Fountain_Spawn_Rate)
		burst_limit_value, burst_limit_ok := scrapbot.get(ctx, entity, Fountain_Burst_Limit)
		launch_speed_value, launch_speed_ok := scrapbot.get(ctx, entity, Fountain_Launch_Speed)
		if !spawn_rate_ok || !burst_limit_ok || !launch_speed_ok {
			return "failed to read fountain emission settings"
		}

		elapsed += ctx.time.delta_time
		spawn_rate := max(spawn_rate_value, 0)
		if spawn_rate <= 0 {
			elapsed = 0
			if !scrapbot.set(ctx, entity, Emitter_Elapsed, elapsed) {
				return "failed to write emitter state"
			}
			continue
		}
		spawn_interval := 1 / spawn_rate
		burst_limit := clamp(i32(burst_limit_value), i32(1), i32(64))
		launch_speed := max(launch_speed_value, 0)
		spawn_count := 0
		for elapsed >= spawn_interval && spawn_count < int(burst_limit) {
			elapsed -= spawn_interval
			if err := spawn_fountain_cube(ctx, transform, i32(sequence), launch_speed);
			   err != nil {
				return err
			}
			sequence += 1
			spawn_count += 1
		}
		if spawn_count == int(burst_limit) && elapsed >= spawn_interval {
			// The burst limit is backpressure, not a debt that must be repaid forever.
			elapsed = 0
		}

		if !scrapbot.set(ctx, entity, Emitter_Elapsed, elapsed) ||
		   !scrapbot.set(ctx, entity, Emitter_Sequence, sequence) {
			return "failed to write emitter state"
		}
	}

	return nil
}

spawn_fountain_cube :: proc "contextless" (
	ctx: ^scrapbot.System_Context,
	emitter: scrapbot.Transform,
	sequence: i32,
	launch_speed: f32,
) -> cstring {
	angle := f32(sequence) * 2.3999631
	ring := f32(sequence % 7) / 6.0
	speed := 0.9 + ring * 0.55
	lifetime := 2.4 + ring * 0.7
	scale := 0.16 + ring * 0.08

	transform := scrapbot.Transform {
		position = emitter.position,
		rotation = {angle, angle * 0.5, 0},
		scale = {scale, scale, scale},
	}
	velocity := scrapbot.Vec3 {
		x = math.cos(angle) * speed,
		y = launch_speed + ring * 0.9,
		z = math.sin(angle) * speed,
	}
	spin := scrapbot.Vec3 {
		x = 1.4 + ring,
		y = 2.2 + ring * 1.3,
		z = 0.8 + ring * 0.7,
	}

	lifetime_fields := [?]scrapbot.Component_Vec3_Field {
		scrapbot.vec3_value(Lifetime_Timer, {0, lifetime, 0}),
	}
	velocity_fields := [?]scrapbot.Component_Vec3_Field {
		scrapbot.vec3_value(Velocity_Value, velocity),
	}
	spin_fields := [?]scrapbot.Component_Vec3_Field {
		scrapbot.vec3_value(Spin_Angular_Velocity, spin),
	}

	payloads := [?]scrapbot.Component_Payload {
		scrapbot.payload(Lifetime_Component, lifetime_fields[:]),
		scrapbot.payload(Velocity_Component, velocity_fields[:]),
		scrapbot.payload(Spin_Component, spin_fields[:]),
	}
	spawn := scrapbot.spawn_options(
		"Fountain Cube",
		&transform,
		&Fountain_Geometry,
		&Fountain_Material,
		payloads[:],
	)
	return scrapbot.spawn(ctx, &spawn)
}
