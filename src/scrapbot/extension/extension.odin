package extension

import c "core:c"
import raw "scrapbot:extension_api"

ABI_VERSION :: raw.ABI_VERSION
TRANSFORM :: "scrapbot.transform"

Context :: struct {
	api: ^raw.API,
}

API :: raw.API
Register_Proc :: #type proc "contextless" (ctx: ^Context) -> cstring

Field :: raw.Field_Definition
Access :: raw.System_Access
Access_Mode :: raw.Access_Mode
Entity :: raw.Entity
Query_Term :: raw.Query_Term
System_Context :: raw.System_Context
System_Proc :: raw.System_Proc
Transform :: raw.Transform
Vec3 :: raw.Vec3

register :: proc "contextless" (api: ^raw.API, callback: Register_Proc) -> cstring {
	if api == nil {
		return "Scrapbot API is not available"
	}
	if api.abi_version != raw.ABI_VERSION {
		return "unsupported Scrapbot extension ABI"
	}
	if callback == nil {
		return "Scrapbot extension register callback is not available"
	}

	ctx := Context{api = api}
	return callback(&ctx)
}

vec3 :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Vec3}
}

component :: proc "contextless" (ctx: ^Context, name: cstring, fields: []Field) -> cstring {
	if ctx == nil || ctx.api == nil || ctx.api.register_library_component == nil {
		return "Scrapbot component registration API is not available"
	}
	definition := raw.Component_Definition {
		name = name,
		fields = raw_data(fields),
		field_count = c.int(len(fields)),
	}
	return ctx.api.register_library_component(ctx.api, &definition)
}

read :: proc "contextless" (component: cstring) -> Access {
	return Access{component = component, mode = .Read}
}

write :: proc "contextless" (component: cstring) -> Access {
	return Access{component = component, mode = .Write}
}

system :: proc "contextless" (
	ctx: ^Context,
	name: cstring,
	accesses: []Access,
	callback: System_Proc,
	userdata: rawptr = nil,
) -> cstring {
	if ctx == nil || ctx.api == nil || ctx.api.register_system == nil {
		return "Scrapbot system registration API is not available"
	}
	definition := raw.System_Definition {
		name = name,
		accesses = raw_data(accesses),
		access_count = c.int(len(accesses)),
		callback = callback,
		userdata = userdata,
	}
	return ctx.api.register_system(ctx.api, &definition)
}

term :: proc "contextless" (component: cstring) -> Query_Term {
	return Query_Term{component = component}
}

query_count :: proc "contextless" (ctx: ^System_Context, terms: []Query_Term) -> int {
	if ctx == nil || ctx.query_count == nil {
		return -1
	}
	return int(ctx.query_count(ctx, raw_data(terms), c.int(len(terms))))
}

query_entity_at :: proc "contextless" (ctx: ^System_Context, terms: []Query_Term, index: int) -> (Entity, bool) {
	if ctx == nil || ctx.query_entity_at == nil {
		return {}, false
	}
	entity := ctx.query_entity_at(ctx, raw_data(terms), c.int(len(terms)), c.int(index))
	return entity, entity.index >= 0
}

get_transform :: proc "contextless" (ctx: ^System_Context, entity: Entity) -> (Transform, bool) {
	if ctx == nil || ctx.get_transform == nil {
		return {}, false
	}
	transform: Transform
	ok := ctx.get_transform(ctx, entity, &transform) != 0
	return transform, ok
}

set_transform :: proc "contextless" (ctx: ^System_Context, entity: Entity, transform: Transform) -> bool {
	if ctx == nil || ctx.set_transform == nil {
		return false
	}
	next := transform
	return ctx.set_transform(ctx, entity, &next) != 0
}

get_vec3 :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
) -> (Vec3, bool) {
	if ctx == nil || ctx.get_vec3_field == nil {
		return {}, false
	}
	value: Vec3
	ok := ctx.get_vec3_field(ctx, entity, component, field, &value) != 0
	return value, ok
}

set_vec3 :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: Vec3,
) -> bool {
	if ctx == nil || ctx.set_vec3_field == nil {
		return false
	}
	next := value
	return ctx.set_vec3_field(ctx, entity, component, field, &next) != 0
}
