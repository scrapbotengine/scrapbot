package showcase

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
}
Emitter_State :: scrapbot.Vec3_Field {
	component = Emitter_Component,
	name = "state",
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

	emitter_fields := [?]scrapbot.Field{scrapbot.vec3(Emitter_State)}
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

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, spin_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read transform"
		}

		angular_velocity, velocity_ok := scrapbot.get(ctx, entity, Spin_Angular_Velocity)
		if !velocity_ok {
			return "failed to read angular velocity"
		}

		transform.rotation.x += angular_velocity.x * ctx.time.delta_time
		transform.rotation.y += angular_velocity.y * ctx.time.delta_time
		transform.rotation.z += angular_velocity.z * ctx.time.delta_time

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
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

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, lifetime_query, &cursor)
		if !entity_ok {
			break
		}

		timer, timer_ok := scrapbot.get(ctx, entity, Lifetime_Timer)
		if !timer_ok {
			return "failed to read lifetime"
		}

		timer.x += ctx.time.delta_time
		if timer.x >= timer.y {
			if err := scrapbot.despawn(ctx, entity); err != nil {
				return err
			}
			continue
		}

		if !scrapbot.set(ctx, entity, Lifetime_Timer, timer) {
			return "failed to write lifetime"
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

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, velocity_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read transform"
		}

		velocity, velocity_ok := scrapbot.get(ctx, entity, Velocity_Value)
		if !velocity_ok {
			return "failed to read velocity"
		}

		transform.position.x += velocity.x * ctx.time.delta_time
		transform.position.y += velocity.y * ctx.time.delta_time
		transform.position.z += velocity.z * ctx.time.delta_time

		velocity.y -= 4.8 * ctx.time.delta_time
		velocity.x *= 0.996
		velocity.z *= 0.996

		if transform.position.y < -1.6 {
			if err := scrapbot.despawn(ctx, entity); err != nil {
				return err
			}
			continue
		}

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
		}
		if !scrapbot.set(ctx, entity, Velocity_Value, velocity) {
			return "failed to write velocity"
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

		state, state_ok := scrapbot.get(ctx, entity, Emitter_State)
		if !state_ok {
			return "failed to read emitter state"
		}
		spawn_rate_value, spawn_rate_ok := scrapbot.get(ctx, entity, Fountain_Spawn_Rate)
		burst_limit_value, burst_limit_ok := scrapbot.get(ctx, entity, Fountain_Burst_Limit)
		launch_speed_value, launch_speed_ok := scrapbot.get(ctx, entity, Fountain_Launch_Speed)
		if !spawn_rate_ok || !burst_limit_ok || !launch_speed_ok {
			return "failed to read fountain emission settings"
		}

		state.x += ctx.time.delta_time
		spawn_rate := max(spawn_rate_value, 0)
		if spawn_rate <= 0 {
			state.x = 0
			if !scrapbot.set(ctx, entity, Emitter_State, state) {
				return "failed to write emitter state"
			}
			continue
		}
		spawn_interval := 1 / spawn_rate
		burst_limit := clamp(i32(burst_limit_value), i32(1), i32(64))
		launch_speed := max(launch_speed_value, 0)
		spawn_count := 0
		for state.x >= spawn_interval && spawn_count < int(burst_limit) {
			state.x -= spawn_interval
			if err := spawn_fountain_cube(ctx, transform, i32(state.z), launch_speed); err != nil {
				return err
			}
			state.z += 1
			spawn_count += 1
		}

		if !scrapbot.set(ctx, entity, Emitter_State, state) {
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
		scrapbot.payload(scrapbot.Shadow_Caster_Component, nil),
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
