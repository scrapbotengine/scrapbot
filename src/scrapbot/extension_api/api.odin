package extension_api

import c "core:c"

ABI_VERSION :: u32(2)
MAX_COMPONENT_FIELDS :: 16
MAX_SYSTEM_ACCESSES :: 16
MAX_QUERY_TERMS :: 8

Field_Type :: enum c.int {
	Vec3 = 1,
}

Access_Mode :: enum c.int {
	Read  = 1,
	Write = 2,
}

Field_Definition :: struct {
	name: cstring,
	field_type: Field_Type,
}

Component_Definition :: struct {
	name: cstring,
	fields: [^]Field_Definition,
	field_count: c.int,
}

System_Access :: struct {
	component: cstring,
	mode:      Access_Mode,
}

Entity :: struct {
	index:      c.int,
	generation: u32,
}

Vec3 :: struct {
	x, y, z: f32,
}

Transform :: struct {
	position: Vec3,
	rotation: Vec3,
	scale:    Vec3,
}

Query_Term :: struct {
	component: cstring,
}

System_Context :: struct {
	abi_version: u32,
	userdata: rawptr,
	host: rawptr,
	delta_seconds: f32,

	query_count: Query_Count_Proc,
	query_entity_at: Query_Entity_At_Proc,
	get_transform: Get_Transform_Proc,
	set_transform: Set_Transform_Proc,
	get_vec3_field: Get_Vec3_Field_Proc,
	set_vec3_field: Set_Vec3_Field_Proc,
}

System_Proc :: #type proc "c" (ctx: ^System_Context) -> cstring

System_Definition :: struct {
	name: cstring,
	accesses: [^]System_Access,
	access_count: c.int,
	callback: System_Proc,
	userdata: rawptr,
}

Register_Library_Component_Proc :: #type proc "c" (
	api: ^API,
	definition: ^Component_Definition,
) -> cstring

Register_System_Proc :: #type proc "c" (
	api: ^API,
	definition: ^System_Definition,
) -> cstring

Query_Count_Proc :: #type proc "c" (
	ctx: ^System_Context,
	terms: [^]Query_Term,
	term_count: c.int,
) -> c.int

Query_Entity_At_Proc :: #type proc "c" (
	ctx: ^System_Context,
	terms: [^]Query_Term,
	term_count: c.int,
	visible_index: c.int,
) -> Entity

Get_Transform_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	transform: ^Transform,
) -> c.int

Set_Transform_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	transform: ^Transform,
) -> c.int

Get_Vec3_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^Vec3,
) -> c.int

Set_Vec3_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^Vec3,
) -> c.int

API :: struct {
	abi_version: u32,
	userdata: rawptr,
	register_library_component: Register_Library_Component_Proc,
	register_system: Register_System_Proc,
}

Register_Proc :: #type proc "c" (api: ^API) -> cstring
