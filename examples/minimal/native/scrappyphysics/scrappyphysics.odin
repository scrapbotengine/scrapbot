package scrappyphysics

import scrapbot "scrapbot:extension"

Spin_Component :: scrapbot.Component {
	name = "scrappyphysics.spin",
}
Spin_Angular_Velocity :: scrapbot.Vec3_Field {
	component = Spin_Component,
	name = "angular_velocity",
}

Rigidbody_Component :: scrapbot.Component {
	name = "scrappyphysics.rigidbody",
}
Rigidbody_Velocity :: scrapbot.Vec3_Field {
	component = Rigidbody_Component,
	name = "velocity",
}

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)

	spin_fields := [?]scrapbot.Field{scrapbot.vec3(Spin_Angular_Velocity)}
	scrapbot.component(&reg, Spin_Component, spin_fields[:])

	rigidbody_fields := [?]scrapbot.Field{scrapbot.vec3(Rigidbody_Velocity)}
	scrapbot.component(&reg, Rigidbody_Component, rigidbody_fields[:])

	spin_accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Spin_Component),
	}
	scrapbot.system(&reg, "scrappyphysics.spin", spin_accesses[:], spin_system)

	motion_accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Rigidbody_Component),
	}
	scrapbot.system(&reg, "scrappyphysics.motion", motion_accesses[:], motion_system)

	return scrapbot.err(&reg)
}

spin_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
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

motion_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component{scrapbot.Transform_Component, Rigidbody_Component}
	rigidbody_query := scrapbot.query(components[:])

	cursor: scrapbot.Query_Cursor
	for {
		entity, entity_ok := scrapbot.next(ctx, rigidbody_query, &cursor)
		if !entity_ok {
			break
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "failed to read transform"
		}

		velocity, velocity_ok := scrapbot.get(ctx, entity, Rigidbody_Velocity)
		if !velocity_ok {
			return "failed to read velocity"
		}

		transform.position.x += velocity.x * ctx.time.delta_time
		transform.position.y += velocity.y * ctx.time.delta_time
		transform.position.z += velocity.z * ctx.time.delta_time

		if !scrapbot.set(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}
