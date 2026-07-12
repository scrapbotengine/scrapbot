package showcase

import scrapbot "scrapbot:extension"

Spin_Component :: scrapbot.Component{name = "showcase.spin"}
Spin_Angular_Velocity :: scrapbot.Vec3_Field{component = Spin_Component, name = "angular_velocity"}

Lifetime_Component :: scrapbot.Component{name = "showcase.lifetime"}
Lifetime_Timer :: scrapbot.Vec3_Field{component = Lifetime_Component, name = "timer"}

Promote_Component :: scrapbot.Component{name = "showcase.promote"}
Promote_Value :: scrapbot.Vec3_Field{component = Promote_Component, name = "value"}

Spawn_Once_Component :: scrapbot.Component{name = "showcase.spawn_once"}
Spawn_Once_Value :: scrapbot.Vec3_Field{component = Spawn_Once_Component, name = "value"}

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)

	spin_fields := [?]scrapbot.Field {
		scrapbot.vec3(Spin_Angular_Velocity),
	}
	scrapbot.component(&reg, Spin_Component, spin_fields[:])

	lifetime_fields := [?]scrapbot.Field {
		scrapbot.vec3(Lifetime_Timer),
	}
	scrapbot.component(&reg, Lifetime_Component, lifetime_fields[:])

	promote_fields := [?]scrapbot.Field {
		scrapbot.vec3(Promote_Value),
	}
	scrapbot.component(&reg, Promote_Component, promote_fields[:])

	spawn_once_fields := [?]scrapbot.Field {
		scrapbot.vec3(Spawn_Once_Value),
	}
	scrapbot.component(&reg, Spawn_Once_Component, spawn_once_fields[:])

	spin_accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Spin_Component),
	}
	scrapbot.system(&reg, "showcase.spin", spin_accesses[:], spin_system)

	lifetime_accesses := [?]scrapbot.Access {
		scrapbot.read(Lifetime_Component),
		scrapbot.write(Lifetime_Component),
	}
	scrapbot.system(&reg, "showcase.lifetime", lifetime_accesses[:], lifetime_system)

	promote_accesses := [?]scrapbot.Access {
		scrapbot.read(Promote_Component),
		scrapbot.write(Promote_Component),
		scrapbot.write(Lifetime_Component),
	}
	scrapbot.system(&reg, "showcase.promote", promote_accesses[:], promote_system)

	spawn_accesses := [?]scrapbot.Access {
		scrapbot.read(Spawn_Once_Component),
		scrapbot.write(Spawn_Once_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.write(Lifetime_Component),
	}
	scrapbot.system(&reg, "showcase.spawn_once", spawn_accesses[:], spawn_once_system)

	return scrapbot.err(&reg)
}

spin_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
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

		transform.rotation.x += angular_velocity.x * ctx.delta_seconds
		transform.rotation.y += angular_velocity.y * ctx.delta_seconds
		transform.rotation.z += angular_velocity.z * ctx.delta_seconds

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}

lifetime_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
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

		timer.x += ctx.delta_seconds
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

promote_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		Promote_Component,
	}
	promote_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, promote_query)
	if count < 0 {
		return "failed to query promoted entities"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, promote_query, i)
		if !entity_ok {
			continue
		}

		fields := [?]scrapbot.Component_Vec3_Field {
			scrapbot.vec3_value(Lifetime_Timer, {0, 8, 0}),
		}
		payload := scrapbot.payload(Lifetime_Component, fields[:])
		if err := scrapbot.add(ctx, entity, &payload); err != nil {
			return err
		}
		if err := scrapbot.remove(ctx, entity, Promote_Component); err != nil {
			return err
		}
	}

	return nil
}

spawn_once_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		Spawn_Once_Component,
	}
	spawn_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, spawn_query)
	if count < 0 {
		return "failed to query spawn-once entities"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, spawn_query, i)
		if !entity_ok {
			continue
		}

		transform := scrapbot.Transform {
			position = {0, -1.4, 0},
			rotation = {},
			scale = {1, 1, 1},
		}
		lifetime_fields := [?]scrapbot.Component_Vec3_Field {
			scrapbot.vec3_value(Lifetime_Timer, {0, 2, 0}),
		}
		lifetime_payload := scrapbot.payload(Lifetime_Component, lifetime_fields[:])
		payloads := [?]scrapbot.Component_Payload {
			lifetime_payload,
		}
		spawn := scrapbot.spawn_options("Native Spawned Event", &transform, payloads[:])
		if err := scrapbot.spawn(ctx, &spawn); err != nil {
			return err
		}
		if err := scrapbot.remove(ctx, entity, Spawn_Once_Component); err != nil {
			return err
		}
	}

	return nil
}
