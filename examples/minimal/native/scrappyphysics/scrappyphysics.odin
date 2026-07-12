package scrappyphysics

import c "core:c"
import api "scrapbot:extension_api"

@(export)
scrapbot_extension_register :: proc "c" (scrapbot: ^api.API) -> cstring {
	if scrapbot == nil {
		return "Scrapbot API is not available"
	}
	if scrapbot.abi_version != api.ABI_VERSION {
		return "unsupported Scrapbot extension ABI"
	}

	spin_fields := [?]api.Field_Definition {
		{name = "angular_velocity", field_type = .Vec3},
	}
	spin_definition := api.Component_Definition {
		name = "scrappyphysics.spin",
		fields = raw_data(spin_fields[:]),
		field_count = c.int(len(spin_fields)),
	}
	if err := scrapbot.register_library_component(scrapbot, &spin_definition); err != nil {
		return err
	}

	rigidbody_fields := [?]api.Field_Definition {
		{name = "velocity", field_type = .Vec3},
	}
	rigidbody_definition := api.Component_Definition {
		name = "scrappyphysics.rigidbody",
		fields = raw_data(rigidbody_fields[:]),
		field_count = c.int(len(rigidbody_fields)),
	}
	if err := scrapbot.register_library_component(scrapbot, &rigidbody_definition); err != nil {
		return err
	}

	accesses := [?]api.System_Access {
		{component = "scrapbot.transform", mode = .Read},
		{component = "scrapbot.transform", mode = .Write},
		{component = "scrappyphysics.spin", mode = .Read},
	}
	system := api.System_Definition {
		name = "scrappyphysics.spin",
		accesses = raw_data(accesses[:]),
		access_count = c.int(len(accesses)),
		callback = spin_system,
	}
	return scrapbot.register_system(scrapbot, &system)
}

spin_system :: proc "c" (ctx: ^api.System_Context) -> cstring {
	terms := [?]api.Query_Term {
		{component = "scrapbot.transform"},
		{component = "scrappyphysics.spin"},
	}

	count := ctx.query_count(ctx, raw_data(terms[:]), c.int(len(terms)))
	if count < 0 {
		return "failed to query spinning entities"
	}

	for i in 0..<int(count) {
		entity := ctx.query_entity_at(ctx, raw_data(terms[:]), c.int(len(terms)), c.int(i))
		if entity.index < 0 {
			continue
		}

		transform: api.Transform
		if ctx.get_transform(ctx, entity, &transform) == 0 {
			return "failed to read transform"
		}

		angular_velocity: api.Vec3
		if ctx.get_vec3_field(ctx, entity, "scrappyphysics.spin", "angular_velocity", &angular_velocity) == 0 {
			return "failed to read angular velocity"
		}

		transform.rotation.x += angular_velocity.x * ctx.delta_seconds
		transform.rotation.y += angular_velocity.y * ctx.delta_seconds
		transform.rotation.z += angular_velocity.z * ctx.delta_seconds

		if ctx.set_transform(ctx, entity, &transform) == 0 {
			return "failed to write transform"
		}
	}

	return nil
}
