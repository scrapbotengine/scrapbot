package extension_api

import c "core:c"

MAX_COMPONENT_FIELDS :: 16
MAX_SYSTEM_ACCESSES :: 16
MAX_QUERY_TERMS :: 8
MAX_QUERY_CHUNK_ENTITIES :: 64
MAX_QUERY_CHUNK_BINDINGS :: 16
MAX_UI_TEXT_BYTES :: 1024
MAX_UI_FONT_BYTES :: 256
MAX_UI_PREFIX_BYTES :: 64

Field_Type :: enum c.int {
	Vec3 = 1,
	Number,
	Vec2,
	Vec4,
	Color,
}

Access_Mode :: enum c.int {
	Read  = 1,
	Write = 2,
}

Query_Chunk_Value_Type :: enum c.int {
	Transform = 1,
	Number,
	Vec2,
	Vec3,
	Vec4,
}

Field_Definition :: struct {
	name: cstring,
	field_type: Field_Type,
	draggable: c.int,
	step: f32,
	has_minimum: c.int,
	minimum: f32,
	has_maximum: c.int,
	maximum: f32,
}

Component_Definition :: struct {
	name: cstring,
	fields: [^]Field_Definition,
	field_count: c.int,
	advanced: c.int,
}

System_Access :: struct {
	component: cstring,
	mode: Access_Mode,
}

Entity :: struct {
	index: c.int,
	generation: u32,
}

Vec3 :: struct {
	x, y, z: f32,
}
Vec2 :: struct {
	x, y: f32,
}
Vec4 :: struct {
	x, y, z, w: f32,
}
UUID :: struct {
	bytes: [16]u8,
}
Resource_Handle :: struct {
	index, generation: u32,
}
Geometry_Vertex :: struct {
	position, normal: Vec3,
	uv: Vec2,
}
Geometry_Desc :: struct {
	vertices: [^]Geometry_Vertex,
	vertex_count: c.int,
	indices: [^]u32,
	index_count: c.int,
}
Material_Desc :: struct {
	base_color: Vec4,
	emissive: Vec3,
}

Transform :: struct {
	position: Vec3,
	rotation: Vec3,
	scale: Vec3,
	parent: UUID,
}

Time :: struct {
	delta_time: f32,
	smooth_delta_time: f32,
	elapsed_time: f64,
	frame_index: u64,
}

Mesh_Payload :: struct {
	primitive: cstring,
}

Component_Vec3_Field :: struct {
	name: cstring,
	value: Vec3,
}

Component_Number_Field :: struct {
	name: cstring,
	value: f32,
}

Component_Vec2_Field :: struct {
	name: cstring,
	value: Vec2,
}

Component_Vec4_Field :: struct {
	name: cstring,
	value: Vec4,
}

Component_Payload :: struct {
	component: cstring,
	number_fields: [^]Component_Number_Field,
	number_field_count: c.int,
	vec2_fields: [^]Component_Vec2_Field,
	vec2_field_count: c.int,
	vec3_fields: [^]Component_Vec3_Field,
	vec3_field_count: c.int,
	vec4_fields: [^]Component_Vec4_Field,
	vec4_field_count: c.int,
}

UI_Text_Alignment :: enum c.int {
	Left   = 0,
	Center = 1,
	Right  = 2,
}

UI_Icon :: enum c.int {
	None          = 0,
	Close         = 1,
	Plus          = 2,
	Chevron_Right = 3,
	Chevron_Down  = 4,
}

UI_Layout_Payload :: struct {
	parent: UUID,
	position: Vec2,
	size: Vec2,
	min_size: Vec2,
	margin: Vec4,
	padding: Vec4,
	background: Vec4,
	border_color: Vec4,
	border_width: f32,
	corner_radius: f32,
	hidden: c.int,
	fill_width: c.int,
	fill_height: c.int,
	fit_content_width: c.int,
	fit_content_height: c.int,
	fixed_in_fill: c.int,
	tree_item: c.int,
	tree_parent: UUID,
	tree_order: c.int,
	tree_collapsed: c.int,
}

UI_Stack_Payload :: struct {
	gap: f32,
	fill: c.int,
	draggable: c.int,
	min_size: f32,
}

UI_Scroll_Area_Payload :: struct {
	scroll_speed: f32,
	smoothness: f32,
	scrollbar_width: f32,
	scrollbar_right: f32,
	scrollbar_vertical_inset: f32,
	minimum_thumb_size: f32,
	scrollbar_corner_radius: f32,
	scrollbar_track_color: Vec4,
	scrollbar_thumb_color: Vec4,
}

UI_Panel_Payload :: struct {
	title_color: Vec4,
	title_background: Vec4,
	title_size: f32,
	title_height: f32,
	disclosure_size: f32,
	disclosure_margin: f32,
	disclosure_gap: f32,
	disclosure_corner_radius: f32,
	collapsible: c.int,
	collapsed: c.int,
}

UI_Table_Payload :: struct {
	columns: c.int,
	column_gap: f32,
	row_gap: f32,
	proportional_columns: c.int,
	resizable_columns: c.int,
	min_column_width: f32,
}

UI_List_Payload :: struct {
	selected: UUID,
	gap: f32,
	selection_background: Vec4,
	hover_background: Vec4,
	active_background: Vec4,
	draggable: c.int,
	drag_threshold: f32,
	drop_edge_fraction: f32,
	drop_target_background: Vec4,
	drop_indicator_color: Vec4,
	drop_indicator_thickness: f32,
	drop_indicator_inset: f32,
	tree_enabled: c.int,
	tree_indent: f32,
}

UI_Drop_Placement :: enum c.int {
	None,
	Before,
	Into,
	After,
}

UI_Progress_Payload :: struct {
	value: f32,
	maximum: f32,
	fill_color: Vec4,
	background_color: Vec4,
	inset: Vec4,
	corner_radius: f32,
	right_to_left: c.int,
}

UI_Text_Payload :: struct {
	color: Vec4,
	size: f32,
	alignment: UI_Text_Alignment,
}

UI_Button_Payload :: struct {
	color: Vec4,
	size: f32,
	alignment: UI_Text_Alignment,
	hover_background: Vec4,
	active_background: Vec4,
	hover_color: Vec4,
	active_color: Vec4,
	icon: UI_Icon,
	icon_inset: f32,
	icon_stroke: f32,
	panel_action: c.int,
}

UI_Input_Payload :: struct {
	color: Vec4,
	prefix_color: Vec4,
	prefix_background: Vec4,
	size: f32,
	prefix_width: f32,
	selection_background: Vec4,
	focus_border_color: Vec4,
	invalid_border_color: Vec4,
	caret_color: Vec4,
	number: f32,
	step: f32,
	minimum: f32,
	maximum: f32,
	prefix_gap: f32,
	prefix_corner_radius: f32,
	prefix_text_padding: f32,
	selection_corner_radius: f32,
	focus_border_width: f32,
	invalid_border_width: f32,
	caret_width: f32,
	caret_inset: f32,
	read_only: c.int,
	numeric: c.int,
	draggable: c.int,
	has_minimum: c.int,
	has_maximum: c.int,
}

UI_Checkbox_Payload :: struct {
	checked: c.int,
	box_size: f32,
	background: Vec4,
	checked_background: Vec4,
	border_color: Vec4,
	check_color: Vec4,
	hover_background: Vec4,
	active_background: Vec4,
	corner_radius: f32,
	border_width: f32,
	check_inset: f32,
	check_corner_radius: f32,
	read_only: c.int,
}

UI_State_Payload :: struct {
	hovered: c.int,
	active: c.int,
	focused: c.int,
	activated: c.int,
	changed: c.int,
	valid: c.int,
	submitted: c.int,
	cancelled: c.int,
	dragging: c.int,
	drag_source: UUID,
	drop_target: UUID,
	drop_placement: UI_Drop_Placement,
	activation_revision: u64,
	change_revision: u64,
	submit_revision: u64,
	cancel_revision: u64,
	drop_revision: u64,
}

UI_Component_Payload :: struct {
	component: cstring,
	layout: UI_Layout_Payload,
	stack: UI_Stack_Payload,
	scroll_area: UI_Scroll_Area_Payload,
	panel: UI_Panel_Payload,
	table: UI_Table_Payload,
	list: UI_List_Payload,
	progress: UI_Progress_Payload,
	text: UI_Text_Payload,
	button: UI_Button_Payload,
	input: UI_Input_Payload,
	checkbox: UI_Checkbox_Payload,
	state: UI_State_Payload,
	text_bytes: [MAX_UI_TEXT_BYTES]u8,
	text_len: c.int,
	font_bytes: [MAX_UI_FONT_BYTES]u8,
	font_len: c.int,
	prefix_bytes: [MAX_UI_PREFIX_BYTES]u8,
	prefix_len: c.int,
}

Spawn_Options :: struct {
	name: cstring,
	transform: ^Transform,
	mesh: ^Mesh_Payload,
	geometry: ^Resource_Handle,
	material: ^Resource_Handle,
	components: [^]Component_Payload,
	component_count: c.int,
	ui_components: [^]UI_Component_Payload,
	ui_component_count: c.int,
	out_uuid: ^UUID,
}

Query_Term :: struct {
	component: cstring,
}

Query_Chunk_Binding :: struct {
	component: cstring,
	field: cstring,
	value_type: Query_Chunk_Value_Type,
	access: Access_Mode,
	values: rawptr,
	write_mask: u64,
}

Query_Chunk :: struct {
	terms: [^]Query_Term,
	term_count: c.int,
	// Opaque host-owned compiled-plan handle. Extensions must initialize these
	// fields to zero and otherwise leave them untouched.
	plan_slot: c.int,
	plan_generation: u32,
	next_entity_index: c.int,
	entities: [^]Entity,
	capacity: c.int,
	count: c.int,
	bindings: [^]Query_Chunk_Binding,
	binding_count: c.int,
}

System_Context :: struct {
	userdata: rawptr,
	host: rawptr,
	time: Time,
	query_count: Query_Count_Proc,
	query_entity_at: Query_Entity_At_Proc,
	query_next: Query_Next_Proc,
	query_chunk_next: Query_Chunk_Next_Proc,
	query_chunk_commit: Query_Chunk_Commit_Proc,
	get_transform: Get_Transform_Proc,
	set_transform: Set_Transform_Proc,
	get_number_field: Get_Number_Field_Proc,
	set_number_field: Set_Number_Field_Proc,
	get_vec2_field: Get_Vec2_Field_Proc,
	set_vec2_field: Set_Vec2_Field_Proc,
	get_vec3_field: Get_Vec3_Field_Proc,
	set_vec3_field: Set_Vec3_Field_Proc,
	get_vec4_field: Get_Vec4_Field_Proc,
	set_vec4_field: Set_Vec4_Field_Proc,
	get_ui_component: Get_UI_Component_Proc,
	set_ui_component: Set_UI_Component_Proc,
	spawn: Spawn_Proc,
	despawn: Despawn_Proc,
	add_transform: Add_Transform_Proc,
	add_mesh: Add_Mesh_Proc,
	add_component: Add_Component_Proc,
	remove_component: Remove_Component_Proc,
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

Register_System_Proc :: #type proc "c" (api: ^API, definition: ^System_Definition) -> cstring
Register_Geometry_Proc :: #type proc "c" (
	api: ^API,
	name: cstring,
	desc: ^Geometry_Desc,
	out_handle: ^Resource_Handle,
) -> cstring
Register_Material_Proc :: #type proc "c" (
	api: ^API,
	name: cstring,
	desc: ^Material_Desc,
	out_handle: ^Resource_Handle,
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

Query_Next_Proc :: #type proc "c" (
	ctx: ^System_Context,
	terms: [^]Query_Term,
	term_count: c.int,
	next_entity_index: ^c.int,
) -> Entity

Query_Chunk_Next_Proc :: #type proc "c" (ctx: ^System_Context, chunk: ^Query_Chunk) -> cstring

Query_Chunk_Commit_Proc :: #type Query_Chunk_Next_Proc

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

Get_Number_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^f32,
) -> c.int

Set_Number_Field_Proc :: #type Get_Number_Field_Proc

Get_Vec2_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^Vec2,
) -> c.int

Set_Vec2_Field_Proc :: #type Get_Vec2_Field_Proc

Set_Vec3_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^Vec3,
) -> c.int

Get_Vec4_Field_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	field: cstring,
	value: ^Vec4,
) -> c.int

Set_Vec4_Field_Proc :: #type Get_Vec4_Field_Proc

Get_UI_Component_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
	payload: ^UI_Component_Payload,
) -> c.int

Set_UI_Component_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	payload: ^UI_Component_Payload,
) -> cstring

Spawn_Proc :: #type proc "c" (ctx: ^System_Context, options: ^Spawn_Options) -> cstring

Despawn_Proc :: #type proc "c" (ctx: ^System_Context, entity: Entity) -> cstring

Add_Transform_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	transform: ^Transform,
) -> cstring

Add_Mesh_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	mesh: ^Mesh_Payload,
) -> cstring

Add_Component_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	payload: ^Component_Payload,
) -> cstring

Remove_Component_Proc :: #type proc "c" (
	ctx: ^System_Context,
	entity: Entity,
	component: cstring,
) -> cstring

API :: struct {
	userdata: rawptr,
	register_library_component: Register_Library_Component_Proc,
	register_system: Register_System_Proc,
	register_geometry: Register_Geometry_Proc,
	register_material: Register_Material_Proc,
}

Register_Proc :: #type proc "c" (api: ^API) -> cstring
