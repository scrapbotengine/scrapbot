package extension

import c "core:c"
import raw "scrapbot:extension_api"

ABI_VERSION :: raw.ABI_VERSION
TRANSFORM :: "scrapbot.transform"

Context :: struct {
	api: ^raw.API,
}

Registry :: struct {
	ctx: ^Context,
	err: cstring,
}

Component :: struct {
	name: cstring,
}

Vec3_Field :: struct {
	component: Component,
	name: cstring,
}

Query :: struct {
	components: []Component,
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

Transform_Component :: Component{name = TRANSFORM}
MAX_QUERY_TERMS :: 16

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

registry :: proc "contextless" (ctx: ^Context) -> Registry {
	return Registry{ctx = ctx}
}

err :: proc "contextless" (reg: ^Registry) -> cstring {
	if reg == nil {
		return "Scrapbot extension registry is not available"
	}
	return reg.err
}

record_err :: proc "contextless" (reg: ^Registry, next: cstring) {
	if reg != nil && reg.err == nil && next != nil {
		reg.err = next
	}
}

component_name :: proc "contextless" (component: Component) -> cstring {
	return component.name
}

vec3_by_name :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Vec3}
}

vec3_by_field :: proc "contextless" (field: Vec3_Field) -> Field {
	return vec3_by_name(field.name)
}

vec3 :: proc {
	vec3_by_name,
	vec3_by_field,
}

component_by_name :: proc "contextless" (ctx: ^Context, name: cstring, fields: []Field) -> cstring {
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

component_by_descriptor :: proc "contextless" (ctx: ^Context, descriptor: Component, fields: []Field) -> cstring {
	return component_by_name(ctx, descriptor.name, fields)
}

component_with_registry :: proc "contextless" (reg: ^Registry, descriptor: Component, fields: []Field) {
	if reg == nil || reg.err != nil {
		return
	}
	record_err(reg, component_by_descriptor(reg.ctx, descriptor, fields))
}

component :: proc {
	component_by_name,
	component_by_descriptor,
	component_with_registry,
}

read_by_name :: proc "contextless" (component: cstring) -> Access {
	return Access{component = component, mode = .Read}
}

read_by_descriptor :: proc "contextless" (component: Component) -> Access {
	return read_by_name(component.name)
}

read :: proc {
	read_by_name,
	read_by_descriptor,
}

write_by_name :: proc "contextless" (component: cstring) -> Access {
	return Access{component = component, mode = .Write}
}

write_by_descriptor :: proc "contextless" (component: Component) -> Access {
	return write_by_name(component.name)
}

write :: proc {
	write_by_name,
	write_by_descriptor,
}

system_by_name :: proc "contextless" (
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

system_with_registry :: proc "contextless" (
	reg: ^Registry,
	name: cstring,
	accesses: []Access,
	callback: System_Proc,
	userdata: rawptr = nil,
) {
	if reg == nil || reg.err != nil {
		return
	}
	record_err(reg, system_by_name(reg.ctx, name, accesses, callback, userdata))
}

system :: proc {
	system_by_name,
	system_with_registry,
}

term_by_name :: proc "contextless" (component: cstring) -> Query_Term {
	return Query_Term{component = component}
}

term_by_descriptor :: proc "contextless" (component: Component) -> Query_Term {
	return term_by_name(component.name)
}

term :: proc {
	term_by_name,
	term_by_descriptor,
}

query :: proc "contextless" (components: []Component) -> Query {
	return Query{components = components}
}

terms_from_components :: proc "contextless" (components: []Component, buffer: []Query_Term) -> ([]Query_Term, bool) {
	if len(components) > len(buffer) {
		return {}, false
	}
	for component, index in components {
		buffer[index] = term(component)
	}
	return buffer[:len(components)], true
}

query_count :: proc "contextless" (ctx: ^System_Context, terms: []Query_Term) -> int {
	if ctx == nil || ctx.query_count == nil {
		return -1
	}
	return int(ctx.query_count(ctx, raw_data(terms), c.int(len(terms))))
}

query_count_components :: proc "contextless" (ctx: ^System_Context, components: []Component) -> int {
	terms: [MAX_QUERY_TERMS]Query_Term
	term_slice, ok := terms_from_components(components, terms[:])
	if !ok {
		return -1
	}
	return query_count(ctx, term_slice)
}

query_count_descriptor :: proc "contextless" (ctx: ^System_Context, descriptor: Query) -> int {
	return query_count_components(ctx, descriptor.components)
}

count :: proc {
	query_count,
	query_count_components,
	query_count_descriptor,
}

query_entity_at :: proc "contextless" (ctx: ^System_Context, terms: []Query_Term, index: int) -> (Entity, bool) {
	if ctx == nil || ctx.query_entity_at == nil {
		return {}, false
	}
	entity := ctx.query_entity_at(ctx, raw_data(terms), c.int(len(terms)), c.int(index))
	return entity, entity.index >= 0
}

query_entity_at_components :: proc "contextless" (ctx: ^System_Context, components: []Component, index: int) -> (Entity, bool) {
	terms: [MAX_QUERY_TERMS]Query_Term
	term_slice, ok := terms_from_components(components, terms[:])
	if !ok {
		return {}, false
	}
	return query_entity_at(ctx, term_slice, index)
}

query_entity_at_descriptor :: proc "contextless" (ctx: ^System_Context, descriptor: Query, index: int) -> (Entity, bool) {
	return query_entity_at_components(ctx, descriptor.components, index)
}

entity_at :: proc {
	query_entity_at,
	query_entity_at_components,
	query_entity_at_descriptor,
}

get_transform :: proc "contextless" (ctx: ^System_Context, entity: Entity) -> (Transform, bool) {
	if ctx == nil || ctx.get_transform == nil {
		return {}, false
	}
	transform: Transform
	ok := ctx.get_transform(ctx, entity, &transform) != 0
	return transform, ok
}

get_transform_component :: proc "contextless" (ctx: ^System_Context, entity: Entity, component: Component) -> (Transform, bool) {
	if component.name != TRANSFORM {
		return {}, false
	}
	return get_transform(ctx, entity)
}

set_transform :: proc "contextless" (ctx: ^System_Context, entity: Entity, transform: Transform) -> bool {
	if ctx == nil || ctx.set_transform == nil {
		return false
	}
	next := transform
	return ctx.set_transform(ctx, entity, &next) != 0
}

set_transform_component :: proc "contextless" (ctx: ^System_Context, entity: Entity, component: Component, transform: Transform) -> bool {
	if component.name != TRANSFORM {
		return false
	}
	return set_transform(ctx, entity, transform)
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

get_vec3_field :: proc "contextless" (ctx: ^System_Context, entity: Entity, field: Vec3_Field) -> (Vec3, bool) {
	return get_vec3(ctx, entity, field.component.name, field.name)
}

get :: proc {
	get_transform_component,
	get_vec3_field,
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

set_vec3_field :: proc "contextless" (ctx: ^System_Context, entity: Entity, field: Vec3_Field, value: Vec3) -> bool {
	return set_vec3(ctx, entity, field.component.name, field.name, value)
}

set :: proc {
	set_transform,
	set_transform_component,
	set_vec3_field,
}
