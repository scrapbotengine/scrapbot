package showcase

import "core:math"
import scrapbot "scrapbot:extension"

Spin_Component :: scrapbot.Component{name = "showcase.spin"}
Spin_Angular_Velocity :: scrapbot.Vec3_Field{component = Spin_Component, name = "angular_velocity"}

Lifetime_Component :: scrapbot.Component{name = "showcase.lifetime"}
Lifetime_Timer :: scrapbot.Vec3_Field{component = Lifetime_Component, name = "timer"}

Velocity_Component :: scrapbot.Component{name = "showcase.velocity"}
Velocity_Value :: scrapbot.Vec3_Field{component = Velocity_Component, name = "value"}

Emitter_Component :: scrapbot.Component{name = "showcase.emitter"}
Emitter_State :: scrapbot.Vec3_Field{component = Emitter_Component, name = "state"}

Light_Orbit_Component :: scrapbot.Component{name = "showcase.light_orbit"}
Light_Orbit_Settings :: scrapbot.Vec3_Field{component = Light_Orbit_Component, name = "settings"}

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

	spin_fields := [?]scrapbot.Field {
		scrapbot.vec3(Spin_Angular_Velocity),
	}
	scrapbot.component(&reg, Spin_Component, spin_fields[:])

	lifetime_fields := [?]scrapbot.Field {
		scrapbot.vec3(Lifetime_Timer),
	}
	scrapbot.component(&reg, Lifetime_Component, lifetime_fields[:])

	velocity_fields := [?]scrapbot.Field {
		scrapbot.vec3(Velocity_Value),
	}
	scrapbot.component(&reg, Velocity_Component, velocity_fields[:])

	emitter_fields := [?]scrapbot.Field {
		scrapbot.vec3(Emitter_State),
	}
	scrapbot.component(&reg, Emitter_Component, emitter_fields[:])

	light_orbit_fields := [?]scrapbot.Field {
		scrapbot.vec3(Light_Orbit_Settings),
	}
	scrapbot.component(&reg, Light_Orbit_Component, light_orbit_fields[:])

	spin_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Spin_Component),
	}
	scrapbot.system(&reg, "showcase.spin", spin_accesses[:], spin_system)

	lifetime_accesses := [?]scrapbot.Access {
		scrapbot.read(Lifetime_Component),
		scrapbot.write(Lifetime_Component),
	}
	scrapbot.system(&reg, "showcase.lifetime", lifetime_accesses[:], lifetime_system)

	velocity_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Lifetime_Component),
		scrapbot.read(Velocity_Component),
		scrapbot.write(Velocity_Component),
	}
	scrapbot.system(&reg, "showcase.velocity", velocity_accesses[:], velocity_system)

	emitter_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Component{name="scrapbot.geometry"}),
		scrapbot.write(scrapbot.Component{name="scrapbot.material"}),
		scrapbot.write(scrapbot.Shadow_Caster_Component),
		scrapbot.read(Emitter_Component),
		scrapbot.write(Emitter_Component),
		scrapbot.write(Lifetime_Component),
		scrapbot.write(Velocity_Component),
		scrapbot.write(Spin_Component),
	}
	scrapbot.system(&reg, "showcase.fountain", emitter_accesses[:], fountain_system)

	light_orbit_accesses := [?]scrapbot.Access {
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(scrapbot.Point_Light_Component),
		scrapbot.read(Light_Orbit_Component),
	}
	scrapbot.system(&reg, "showcase.light_orbit", light_orbit_accesses[:], light_orbit_system)

	return scrapbot.err(&reg)
}

spin_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Spin_Component,
	}
	spin_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, spin_query)
	if count < 0 {
		return "failed to query showcase spinners"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, spin_query, i)
		if !entity_ok {
			continue
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

light_orbit_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		scrapbot.Point_Light_Component,
		Light_Orbit_Component,
	}
	light_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, light_query)
	if count < 0 {
		return "failed to query orbiting point lights"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, light_query, i)
		if !entity_ok {
			continue
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
	components := [?]scrapbot.Component {
		Lifetime_Component,
	}
	lifetime_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, lifetime_query)
	if count < 0 {
		return "failed to query lifetimes"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, lifetime_query, i)
		if !entity_ok {
			continue
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

velocity_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Velocity_Component,
		Lifetime_Component,
	}
	velocity_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, velocity_query)
	if count < 0 {
		return "failed to query fountain bodies"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, velocity_query, i)
		if !entity_ok {
			continue
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

fountain_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Emitter_Component,
	}
	emitter_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, emitter_query)
	if count < 0 {
		return "failed to query fountain emitters"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, emitter_query, i)
		if !entity_ok {
			continue
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read emitter transform"
		}

		state, state_ok := scrapbot.get(ctx, entity, Emitter_State)
		if !state_ok {
			return "failed to read emitter state"
		}

		state.x += ctx.time.delta_time
		spawn_count := 0
		for state.x >= state.y && spawn_count < 4 {
			state.x -= state.y
			if err := spawn_fountain_cube(ctx, transform, i32(state.z)); err != nil {
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
		y = 3.2 + ring * 0.9,
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
	spawn := scrapbot.spawn_options("Fountain Cube", &transform, &Fountain_Geometry, &Fountain_Material, payloads[:])
	return scrapbot.spawn(ctx, &spawn)
}
