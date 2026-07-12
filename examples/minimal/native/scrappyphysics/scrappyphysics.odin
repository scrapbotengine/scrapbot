package scrappyphysics

import scrapbot "scrapbot:extension"

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	spin_fields := [?]scrapbot.Field {
		scrapbot.vec3("angular_velocity"),
	}
	if err := scrapbot.component(ctx, "scrappyphysics.spin", spin_fields[:]); err != nil {
		return err
	}

	rigidbody_fields := [?]scrapbot.Field {
		scrapbot.vec3("velocity"),
	}
	if err := scrapbot.component(ctx, "scrappyphysics.rigidbody", rigidbody_fields[:]); err != nil {
		return err
	}

	accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.TRANSFORM),
		scrapbot.write(scrapbot.TRANSFORM),
		scrapbot.read("scrappyphysics.spin"),
	}
	return scrapbot.system(ctx, "scrappyphysics.spin", accesses[:], spin_system)
}

spin_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	terms := [?]scrapbot.Query_Term {
		scrapbot.term(scrapbot.TRANSFORM),
		scrapbot.term("scrappyphysics.spin"),
	}

	count := scrapbot.query_count(ctx, terms[:])
	if count < 0 {
		return "failed to query spinning entities"
	}

	for i in 0..<count {
		entity, entity_ok := scrapbot.query_entity_at(ctx, terms[:], i)
		if !entity_ok {
			continue
		}

		transform, transform_ok := scrapbot.get_transform(ctx, entity)
		if !transform_ok {
			return "failed to read transform"
		}

		angular_velocity, velocity_ok := scrapbot.get_vec3(ctx, entity, "scrappyphysics.spin", "angular_velocity")
		if !velocity_ok {
			return "failed to read angular velocity"
		}

		transform.rotation.x += angular_velocity.x * ctx.delta_seconds
		transform.rotation.y += angular_velocity.y * ctx.delta_seconds
		transform.rotation.z += angular_velocity.z * ctx.delta_seconds

		if !scrapbot.set_transform(ctx, entity, transform) {
			return "failed to write transform"
		}
	}

	return nil
}
