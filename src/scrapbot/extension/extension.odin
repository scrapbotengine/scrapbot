package extension

import c "core:c"
import raw "scrapbot:extension_api"

TRANSFORM :: "scrapbot.transform"
MESH :: "scrapbot.mesh"
AMBIENT_LIGHT :: "scrapbot.ambient_light"
DIRECTIONAL_LIGHT :: "scrapbot.directional_light"
POINT_LIGHT :: "scrapbot.point_light"
SHADOW_CASTER :: "scrapbot.shadow_caster"
SHADOW_RECEIVER :: "scrapbot.shadow_receiver"

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

Number_Field :: struct {
	component: Component,
	name: cstring,
}

Vec2_Field :: struct {
	component: Component,
	name: cstring,
}

Vec4_Field :: struct {
	component: Component,
	name: cstring,
}

Color_Field :: distinct Vec4_Field

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
System_Proc :: #type proc "contextless" (ctx: ^System_Context) -> cstring
Transform :: raw.Transform
Time :: raw.Time
Mesh_Payload :: raw.Mesh_Payload
Geometry_Vertex :: raw.Geometry_Vertex
Geometry_Desc :: raw.Geometry_Desc
Material_Desc :: raw.Material_Desc
Resource_Handle :: raw.Resource_Handle
Vec2 :: raw.Vec2
Vec4 :: raw.Vec4
Vec3 :: raw.Vec3
Component_Vec3_Field :: raw.Component_Vec3_Field
Component_Number_Field :: raw.Component_Number_Field
Component_Vec2_Field :: raw.Component_Vec2_Field
Component_Vec4_Field :: raw.Component_Vec4_Field
Component_Payload :: raw.Component_Payload
Spawn_Options :: raw.Spawn_Options

Transform_Component :: Component {
	name = TRANSFORM,
}
Mesh_Component :: Component {
	name = MESH,
}
Ambient_Light_Component :: Component {
	name = AMBIENT_LIGHT,
}
Directional_Light_Component :: Component {
	name = DIRECTIONAL_LIGHT,
}
Point_Light_Component :: Component {
	name = POINT_LIGHT,
}
Shadow_Caster_Component :: Component {
	name = SHADOW_CASTER,
}
Shadow_Receiver_Component :: Component {
	name = SHADOW_RECEIVER,
}
MAX_QUERY_TERMS :: 16
MAX_SYSTEM_BINDINGS :: 64

System_Binding :: struct {
	callback: System_Proc,
	userdata: rawptr,
}

system_bindings: [MAX_SYSTEM_BINDINGS]System_Binding
system_binding_count: int

Generated_Geometry :: struct {
	vertices: [24]Geometry_Vertex,
	indices: [36]u32,
	vertex_count: int,
	index_count: int,
}

cube_geometry :: proc "contextless" (size: f32 = 1) -> Generated_Geometry {
	result: Generated_Geometry; h := size / 2
	positions := [8]Vec3 {
		{-h, -h, -h},
		{h, -h, -h},
		{h, h, -h},
		{-h, h, -h},
		{-h, -h, h},
		{h, -h, h},
		{h, h, h},
		{-h, h, h},
	}
	faces := [6][4]u32 {
		{4, 5, 6, 7},
		{1, 0, 3, 2},
		{0, 4, 7, 3},
		{5, 1, 2, 6},
		{3, 7, 6, 2},
		{0, 1, 5, 4},
	}
	normals := [6]Vec3{{0, 0, 1}, {0, 0, -1}, {-1, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}}
	uvs := [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	for face in 0 ..< 6 { for corner in 0 ..< 4 { result.vertices[face * 4 + corner] = {positions[faces[face][corner]], normals[face], uvs[corner]} } }
	for face in 0 ..< 6 { base := u32(face * 4); o := face * 6; values := [6]u32{base, base + 1, base + 2, base, base + 2, base + 3}; for v, i in values { result.indices[o + i] = v } }
	result.vertex_count = 24; result.index_count = 36; return result
}

plane_geometry :: proc "contextless" (width, depth: f32) -> Generated_Geometry {
	result: Generated_Geometry; w, d := width / 2, depth / 2
	result.vertices[0] = {
		{-w, 0, -d},
		{0, 1, 0},
		{0, 0},
	}; result.vertices[1] = {{w, 0, -d}, {0, 1, 0}, {1, 0}}
	result.vertices[2] = {
		{w, 0, d},
		{0, 1, 0},
		{1, 1},
	}; result.vertices[3] = {{-w, 0, d}, {0, 1, 0}, {0, 1}}
	values := [6]u32{0, 1, 2, 0, 2, 3}; for v, i in values { result.indices[i] = v }
	result.vertex_count = 4; result.index_count = 6; return result
}

register_generated_geometry :: proc "contextless" (
	reg: ^Registry,
	name: cstring,
	generated: ^Generated_Geometry,
) -> Resource_Handle {
	if generated == nil { record_err(reg, "generated geometry is not available"); return {} }
	return geometry(
		reg,
		name,
		generated.vertices[:generated.vertex_count],
		generated.indices[:generated.index_count],
	)
}

register :: proc "contextless" (api: ^raw.API, callback: Register_Proc) -> cstring {
	if api == nil {
		return "Scrapbot API is not available"
	}
	if callback == nil {
		return "Scrapbot extension register callback is not available"
	}
	system_bindings = {}
	system_binding_count = 0

	ctx := Context {
		api = api,
	}
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

number_by_name :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Number}
}

number_by_field :: proc "contextless" (field: Number_Field) -> Field {
	return number_by_name(field.name)
}

number :: proc {
	number_by_name,
	number_by_field,
}

number_draggable_by_name :: proc "contextless" (
	name: cstring,
	step: f32 = 0.1,
	minimum: Maybe(f32) = nil,
	maximum: Maybe(f32) = nil,
) -> Field {
	field := number(name)
	field.draggable = 1
	field.step = step
	if value, ok := minimum.?; ok {
		field.has_minimum = 1
		field.minimum = value
	}
	if value, ok := maximum.?; ok {
		field.has_maximum = 1
		field.maximum = value
	}
	return field
}

number_draggable_by_field :: proc "contextless" (
	field: Number_Field,
	step: f32 = 0.1,
	minimum: Maybe(f32) = nil,
	maximum: Maybe(f32) = nil,
) -> Field {
	return number_draggable_by_name(field.name, step, minimum, maximum)
}

number_draggable :: proc {
	number_draggable_by_name,
	number_draggable_by_field,
}

vec2_by_name :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Vec2}
}

vec2_by_field :: proc "contextless" (field: Vec2_Field) -> Field {
	return vec2_by_name(field.name)
}

vec2 :: proc {
	vec2_by_name,
	vec2_by_field,
}

vec4_by_name :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Vec4}
}

vec4_by_field :: proc "contextless" (field: Vec4_Field) -> Field {
	return vec4_by_name(field.name)
}

vec4 :: proc {
	vec4_by_name,
	vec4_by_field,
}

color_by_name :: proc "contextless" (name: cstring) -> Field {
	return Field{name = name, field_type = .Color}
}

color_by_field :: proc "contextless" (field: Color_Field) -> Field {
	descriptor := Vec4_Field(field)
	return color_by_name(descriptor.name)
}

color :: proc {
	color_by_name,
	color_by_field,
}

vec3_by_field :: proc "contextless" (field: Vec3_Field) -> Field {
	return vec3_by_name(field.name)
}

vec3 :: proc {
	vec3_by_name,
	vec3_by_field,
}

vec3_value :: proc "contextless" (field: Vec3_Field, value: Vec3) -> Component_Vec3_Field {
	return Component_Vec3_Field{name = field.name, value = value}
}

number_value :: proc "contextless" (field: Number_Field, value: f32) -> Component_Number_Field {
	return Component_Number_Field{name = field.name, value = value}
}

vec2_value :: proc "contextless" (field: Vec2_Field, value: Vec2) -> Component_Vec2_Field {
	return Component_Vec2_Field{name = field.name, value = value}
}

vec4_value :: proc "contextless" (field: Vec4_Field, value: Vec4) -> Component_Vec4_Field {
	return Component_Vec4_Field{name = field.name, value = value}
}

color_value :: proc "contextless" (field: Color_Field, value: Vec4) -> Component_Vec4_Field {
	descriptor := Vec4_Field(field)
	return Component_Vec4_Field{name = descriptor.name, value = value}
}

payload_by_name :: proc "contextless" (
	component: cstring,
	vec3_fields: []Component_Vec3_Field = nil,
	number_fields: []Component_Number_Field = nil,
	vec2_fields: []Component_Vec2_Field = nil,
	vec4_fields: []Component_Vec4_Field = nil,
) -> Component_Payload {
	return Component_Payload {
		component = component,
		number_fields = raw_data(number_fields),
		number_field_count = c.int(len(number_fields)),
		vec2_fields = raw_data(vec2_fields),
		vec2_field_count = c.int(len(vec2_fields)),
		vec3_fields = raw_data(vec3_fields),
		vec3_field_count = c.int(len(vec3_fields)),
		vec4_fields = raw_data(vec4_fields),
		vec4_field_count = c.int(len(vec4_fields)),
	}
}

payload_by_descriptor :: proc "contextless" (
	component: Component,
	vec3_fields: []Component_Vec3_Field = nil,
	number_fields: []Component_Number_Field = nil,
	vec2_fields: []Component_Vec2_Field = nil,
	vec4_fields: []Component_Vec4_Field = nil,
) -> Component_Payload {
	return payload_by_name(component.name, vec3_fields, number_fields, vec2_fields, vec4_fields)
}

payload :: proc {
	payload_by_name,
	payload_by_descriptor,
}

mesh :: proc "contextless" (primitive: cstring) -> Mesh_Payload {
	return Mesh_Payload{primitive = primitive}
}

component_by_name :: proc "contextless" (
	ctx: ^Context,
	name: cstring,
	fields: []Field,
) -> cstring {
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

component_by_descriptor :: proc "contextless" (
	ctx: ^Context,
	descriptor: Component,
	fields: []Field,
) -> cstring {
	return component_by_name(ctx, descriptor.name, fields)
}

component_with_registry :: proc "contextless" (
	reg: ^Registry,
	descriptor: Component,
	fields: []Field,
) {
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
	if callback == nil {
		return "Scrapbot system callback is not available"
	}
	if system_binding_count >= len(system_bindings) {
		return "too many Scrapbot system callback bindings"
	}
	binding := &system_bindings[system_binding_count]
	binding^ = System_Binding {
		callback = callback,
		userdata = userdata,
	}
	definition := raw.System_Definition {
		name = name,
		accesses = raw_data(accesses),
		access_count = c.int(len(accesses)),
		callback = system_trampoline,
		userdata = binding,
	}
	err := ctx.api.register_system(ctx.api, &definition)
	if err == nil { system_binding_count += 1 }
	return err
}

system_trampoline :: proc "c" (ctx: ^raw.System_Context) -> cstring {
	if ctx == nil ||
	   ctx.userdata == nil { return "Scrapbot system callback binding is not available" }
	binding := cast(^System_Binding)ctx.userdata
	if binding.callback == nil { return "Scrapbot system callback is not available" }
	ctx.userdata = binding.userdata
	return binding.callback(ctx)
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

geometry :: proc "contextless" (
	reg: ^Registry,
	name: cstring,
	vertices: []Geometry_Vertex,
	indices: []u32,
) -> Resource_Handle {
	handle: Resource_Handle
	if reg == nil || reg.err != nil { return handle }
	if reg.ctx == nil ||
	   reg.ctx.api == nil ||
	   reg.ctx.api.register_geometry ==
		   nil { record_err(reg, "Scrapbot geometry registration API is not available"); return handle }
	desc := Geometry_Desc {
		vertices = raw_data(vertices),
		vertex_count = c.int(len(vertices)),
		indices = raw_data(indices),
		index_count = c.int(len(indices)),
	}
	record_err(
		reg,
		reg.ctx.api.register_geometry(reg.ctx.api, name, &desc, &handle),
	); return handle
}

material :: proc "contextless" (
	reg: ^Registry,
	name: cstring,
	base_color: Vec4,
) -> Resource_Handle {
	handle: Resource_Handle
	if reg == nil || reg.err != nil { return handle }
	if reg.ctx == nil ||
	   reg.ctx.api == nil ||
	   reg.ctx.api.register_material ==
		   nil { record_err(reg, "Scrapbot material registration API is not available"); return handle }
	desc := Material_Desc {
		base_color = base_color,
	}; record_err(
		reg,
		reg.ctx.api.register_material(reg.ctx.api, name, &desc, &handle),
	); return handle
}

emissive_material :: proc "contextless" (
	reg: ^Registry,
	name: cstring,
	emissive: Vec3,
) -> Resource_Handle {
	handle: Resource_Handle
	if reg == nil || reg.err != nil {
		return handle
	}
	if reg.ctx == nil || reg.ctx.api == nil || reg.ctx.api.register_material == nil {
		record_err(reg, "Scrapbot material registration API is not available")
		return handle
	}
	desc := Material_Desc {
		base_color = {0, 0, 0, 1},
		emissive = emissive,
	}
	record_err(reg, reg.ctx.api.register_material(reg.ctx.api, name, &desc, &handle))
	return handle
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

terms_from_components :: proc "contextless" (
	components: []Component,
	buffer: []Query_Term,
) -> (
	[]Query_Term,
	bool,
) {
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

query_count_components :: proc "contextless" (
	ctx: ^System_Context,
	components: []Component,
) -> int {
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

query_entity_at :: proc "contextless" (
	ctx: ^System_Context,
	terms: []Query_Term,
	index: int,
) -> (
	Entity,
	bool,
) {
	if ctx == nil || ctx.query_entity_at == nil {
		return {}, false
	}
	entity := ctx.query_entity_at(ctx, raw_data(terms), c.int(len(terms)), c.int(index))
	return entity, entity.index >= 0
}

query_entity_at_components :: proc "contextless" (
	ctx: ^System_Context,
	components: []Component,
	index: int,
) -> (
	Entity,
	bool,
) {
	terms: [MAX_QUERY_TERMS]Query_Term
	term_slice, ok := terms_from_components(components, terms[:])
	if !ok {
		return {}, false
	}
	return query_entity_at(ctx, term_slice, index)
}

query_entity_at_descriptor :: proc "contextless" (
	ctx: ^System_Context,
	descriptor: Query,
	index: int,
) -> (
	Entity,
	bool,
) {
	return query_entity_at_components(ctx, descriptor.components, index)
}

entity_at :: proc {
	query_entity_at,
	query_entity_at_components,
	query_entity_at_descriptor,
}

Query_Cursor :: struct {
	next_entity_index: c.int,
}

query_next :: proc "contextless" (
	ctx: ^System_Context,
	terms: []Query_Term,
	cursor: ^Query_Cursor,
) -> (
	Entity,
	bool,
) {
	if ctx == nil || ctx.query_next == nil || cursor == nil {
		return {}, false
	}
	entity := ctx.query_next(ctx, raw_data(terms), c.int(len(terms)), &cursor.next_entity_index)
	return entity, entity.index >= 0
}

query_next_components :: proc "contextless" (
	ctx: ^System_Context,
	components: []Component,
	cursor: ^Query_Cursor,
) -> (
	Entity,
	bool,
) {
	terms: [MAX_QUERY_TERMS]Query_Term
	term_slice, ok := terms_from_components(components, terms[:])
	if !ok {
		return {}, false
	}
	return query_next(ctx, term_slice, cursor)
}

query_next_descriptor :: proc "contextless" (
	ctx: ^System_Context,
	descriptor: Query,
	cursor: ^Query_Cursor,
) -> (
	Entity,
	bool,
) {
	return query_next_components(ctx, descriptor.components, cursor)
}

next :: proc {
	query_next,
	query_next_components,
	query_next_descriptor,
}

get_transform :: proc "contextless" (ctx: ^System_Context, entity: Entity) -> (Transform, bool) {
	if ctx == nil || ctx.get_transform == nil {
		return {}, false
	}
	transform: Transform
	ok := ctx.get_transform(ctx, entity, &transform) != 0
	return transform, ok
}

get_transform_component :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: Component,
) -> (
	Transform,
	bool,
) {
	if component.name != TRANSFORM {
		return {}, false
	}
	return get_transform(ctx, entity)
}

set_transform :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	transform: Transform,
) -> bool {
	if ctx == nil || ctx.set_transform == nil {
		return false
	}
	next := transform
	return ctx.set_transform(ctx, entity, &next) != 0
}

set_transform_component :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: Component,
	transform: Transform,
) -> bool {
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
) -> (
	Vec3,
	bool,
) {
	if ctx == nil || ctx.get_vec3_field == nil {
		return {}, false
	}
	value: Vec3
	ok := ctx.get_vec3_field(ctx, entity, component, field, &value) != 0
	return value, ok
}

get_number_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Number_Field,
) -> (
	f32,
	bool,
) {
	if ctx == nil || ctx.get_number_field == nil {
		return 0, false
	}
	value: f32
	ok := ctx.get_number_field(ctx, entity, field.component.name, field.name, &value) != 0
	return value, ok
}

get_vec2_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec2_Field,
) -> (
	Vec2,
	bool,
) {
	if ctx == nil || ctx.get_vec2_field == nil {
		return {}, false
	}
	value: Vec2
	ok := ctx.get_vec2_field(ctx, entity, field.component.name, field.name, &value) != 0
	return value, ok
}

get_vec4_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec4_Field,
) -> (
	Vec4,
	bool,
) {
	if ctx == nil || ctx.get_vec4_field == nil {
		return {}, false
	}
	value: Vec4
	ok := ctx.get_vec4_field(ctx, entity, field.component.name, field.name, &value) != 0
	return value, ok
}

get_color_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Color_Field,
) -> (
	Vec4,
	bool,
) {
	return get_vec4_field(ctx, entity, Vec4_Field(field))
}

get_vec3_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec3_Field,
) -> (
	Vec3,
	bool,
) {
	return get_vec3(ctx, entity, field.component.name, field.name)
}

get :: proc {
	get_transform_component,
	get_number_field,
	get_vec2_field,
	get_vec3_field,
	get_vec4_field,
	get_color_field,
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

set_number_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Number_Field,
	value: f32,
) -> bool {
	if ctx == nil || ctx.set_number_field == nil {
		return false
	}
	next := value
	return ctx.set_number_field(ctx, entity, field.component.name, field.name, &next) != 0
}

set_vec2_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec2_Field,
	value: Vec2,
) -> bool {
	if ctx == nil || ctx.set_vec2_field == nil {
		return false
	}
	next := value
	return ctx.set_vec2_field(ctx, entity, field.component.name, field.name, &next) != 0
}

set_vec4_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec4_Field,
	value: Vec4,
) -> bool {
	if ctx == nil || ctx.set_vec4_field == nil {
		return false
	}
	next := value
	return ctx.set_vec4_field(ctx, entity, field.component.name, field.name, &next) != 0
}

set_color_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Color_Field,
	value: Vec4,
) -> bool {
	return set_vec4_field(ctx, entity, Vec4_Field(field), value)
}

set_vec3_field :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	field: Vec3_Field,
	value: Vec3,
) -> bool {
	return set_vec3(ctx, entity, field.component.name, field.name, value)
}

set :: proc {
	set_transform,
	set_transform_component,
	set_number_field,
	set_vec2_field,
	set_vec3_field,
	set_vec4_field,
	set_color_field,
}

spawn_options_basic :: proc "contextless" (
	name: cstring,
	transform: ^Transform = nil,
) -> Spawn_Options {
	return Spawn_Options{name = name, transform = transform}
}

spawn_options_with_components :: proc "contextless" (
	name: cstring,
	transform: ^Transform,
	components: []Component_Payload,
) -> Spawn_Options {
	return Spawn_Options {
		name = name,
		transform = transform,
		components = raw_data(components),
		component_count = c.int(len(components)),
	}
}

spawn_options_with_mesh :: proc "contextless" (
	name: cstring,
	transform: ^Transform,
	mesh: ^Mesh_Payload,
	components: []Component_Payload = nil,
) -> Spawn_Options {
	return Spawn_Options {
		name = name,
		transform = transform,
		mesh = mesh,
		components = raw_data(components),
		component_count = c.int(len(components)),
	}
}

spawn_options_renderable :: proc "contextless" (
	name: cstring,
	transform: ^Transform,
	geometry, material: ^Resource_Handle,
	components: []Component_Payload = nil,
) -> Spawn_Options {
	return Spawn_Options {
		name = name,
		transform = transform,
		geometry = geometry,
		material = material,
		components = raw_data(components),
		component_count = c.int(len(components)),
	}
}

spawn_options :: proc {
	spawn_options_basic,
	spawn_options_with_components,
	spawn_options_with_mesh,
	spawn_options_renderable,
}

spawn :: proc "contextless" (ctx: ^System_Context, options: ^Spawn_Options) -> cstring {
	if ctx == nil || ctx.spawn == nil {
		return "Scrapbot spawn API is not available"
	}
	return ctx.spawn(ctx, options)
}

despawn :: proc "contextless" (ctx: ^System_Context, entity: Entity) -> cstring {
	if ctx == nil || ctx.despawn == nil {
		return "Scrapbot despawn API is not available"
	}
	return ctx.despawn(ctx, entity)
}

add_transform :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	transform: Transform,
) -> cstring {
	if ctx == nil || ctx.add_transform == nil {
		return "Scrapbot add transform API is not available"
	}
	next := transform
	return ctx.add_transform(ctx, entity, &next)
}

add_mesh :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	mesh: Mesh_Payload,
) -> cstring {
	if ctx == nil || ctx.add_mesh == nil {
		return "Scrapbot add mesh API is not available"
	}
	next := mesh
	return ctx.add_mesh(ctx, entity, &next)
}

add_payload :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: ^Component_Payload,
) -> cstring {
	if ctx == nil || ctx.add_component == nil {
		return "Scrapbot add component API is not available"
	}
	return ctx.add_component(ctx, entity, component)
}

add :: proc {
	add_transform,
	add_mesh,
	add_payload,
}

remove_by_name :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
) -> cstring {
	if ctx == nil || ctx.remove_component == nil {
		return "Scrapbot remove component API is not available"
	}
	return ctx.remove_component(ctx, entity, component)
}

remove_by_descriptor :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: Component,
) -> cstring {
	return remove_by_name(ctx, entity, component.name)
}

remove :: proc {
	remove_by_name,
	remove_by_descriptor,
}
