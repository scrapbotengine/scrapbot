package shared

PROJECT_FILE :: "project.toml"
DEFAULT_SCENE :: "scenes/main.scene.toml"
DEFAULT_SCRIPT :: "scripts/main.luau"
DEFAULT_LUAU_TYPES :: "types/scrapbot.d.luau"
DEFAULT_VSCODE_SETTINGS :: ".vscode/settings.json"

VERSION :: "0.1.0-dev"

FONT_FIRST_CHAR :: 32
FONT_CHAR_COUNT :: 95
FONT_ATLAS_SIZE :: 512
MAX_PROJECT_FONTS :: 15
PROJECT_FONT_BUILD_DIR :: "build/fonts"

Vec3 :: struct {
	x, y, z: f32,
}
Vec2 :: struct {
	x, y: f32,
}
Vec4 :: struct {
	x, y, z, w: f32,
}

Renderer_Backend :: enum {
	Null,
	WGPU,
}

Project_Config :: struct {
	name: string,
	default_scene: string,
	native_extensions: [dynamic]Native_Extension_Target,
	fonts: [dynamic]Project_Font,
}

Native_Extension_Target :: struct {
	name: string,
	source: string,
}

Project_Font :: struct {
	name: string,
	source: string,
}

Scene :: struct {
	entities: [dynamic]Scene_Entity,
}

Scene_Entity :: struct {
	id: Entity_UUID,
	name: string,
	has_transform: bool,
	transform: Transform_Component,
	has_camera: bool,
	camera: Camera_Component,
	has_ambient_light: bool,
	ambient_light: Ambient_Light_Component,
	has_directional_light: bool,
	directional_light: Directional_Light_Component,
	has_point_light: bool,
	point_light: Point_Light_Component,
	has_mesh: bool,
	mesh: Mesh_Component,
	has_geometry: bool,
	geometry_resource: string,
	has_material: bool,
	material_resource: string,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,
	has_ui_layout: bool,
	ui_layout: UI_Layout_Component,
	has_ui_hstack: bool,
	ui_hstack: UI_Stack_Component,
	has_ui_vstack: bool,
	ui_vstack: UI_Stack_Component,
	has_ui_scroll_area: bool,
	ui_scroll_area: UI_Scroll_Area_Component,
	has_ui_panel: bool,
	ui_panel: UI_Panel_Component,
	has_ui_table: bool,
	ui_table: UI_Table_Component,
	has_ui_text: bool,
	ui_text: UI_Text_Component,
	has_ui_button: bool,
	ui_button: UI_Button_Component,
	has_ui_input: bool,
	ui_input: UI_Input_Component,
	has_ui_checkbox: bool,
	ui_checkbox: UI_Checkbox_Component,
	custom_components: [dynamic]Custom_Component,
}

Entity :: struct {
	index: u32,
	generation: u32,
}

Entity_Origin :: enum {
	Scene,
	Runtime,
	Editor,
}

Component_ID :: int
INVALID_COMPONENT_ID :: Component_ID(0)

Geometry_Handle :: struct {
	index, generation: u32,
}
Material_Handle :: struct {
	index, generation: u32,
}
Font_Handle :: struct {
	index, generation: u32,
}

Time_Resource :: struct {
	delta_time: f32,
	smooth_delta_time: f32,
	elapsed_time: f64,
	frame_index: u64,
}

Transform_Component :: struct {
	position: Vec3,
	rotation: Vec3,
	scale: Vec3,
}

Camera_Component :: struct {
	fov: f32,
	near: f32,
	far: f32,
}

Editor_Scene_Camera_Component :: struct {
	entity_index: int,
	move_speed: f32,
	look_sensitivity: f32,
}

Editor_Fly_Camera_Input :: struct {
	movement: Vec3,
	look_delta: Vec2,
	look_active: bool,
}

Ambient_Light_Component :: struct {
	color: Vec3,
	intensity: f32,
}
Directional_Light_Component :: struct {
	direction, color: Vec3,
	intensity: f32,
}
Point_Light_Component :: struct {
	color: Vec3,
	intensity, range: f32,
}

UI_Layout_Component :: struct {
	parent: Entity_UUID,
	position: Vec2,
	size: Vec2,
	margin: Vec4,
	padding: Vec4,
	background: Vec4,
	border_color: Vec4,
	border_width: f32,
	corner_radius: f32,
	hidden: bool,
}
UI_Stack_Component :: struct {
	gap: f32,
	fill: bool,
	draggable: bool,
	min_size: f32,
}
UI_Scroll_Area_Component :: struct {
	scroll_speed, smoothness: f32,
}
UI_Panel_Component :: struct {
	title: string,
	font: string,
	title_color: Vec4,
	title_background: Vec4,
	title_size: f32,
	title_height: f32,
	collapsible: bool,
	collapsed: bool,
}
UI_Table_Component :: struct {
	columns: int,
	column_gap: f32,
	row_gap: f32,
}
UI_Text_Alignment :: enum {
	Left,
	Center,
	Right,
}
UI_Text_Component :: struct {
	text: string,
	font: string,
	color: Vec4,
	size: f32,
	alignment: UI_Text_Alignment,
}
UI_Button_Component :: struct {
	text: string,
	font: string,
	color: Vec4,
	size: f32,
	hover_background: Vec4,
	active_background: Vec4,
	hover_color: Vec4,
	active_color: Vec4,
}
UI_Input_Component :: struct {
	text: string,
	font: string,
	color: Vec4,
	size: f32,
	selection_background: Vec4,
	focus_border_color: Vec4,
	read_only: bool,
}

Font_Glyph :: struct {
	advance: f32,
	plane, uv: Vec4,
}
UI_Checkbox_Component :: struct {
	checked: bool,
	box_size: f32,
	background: Vec4,
	checked_background: Vec4,
	border_color: Vec4,
	check_color: Vec4,
	hover_background: Vec4,
	active_background: Vec4,
	read_only: bool,
}

Editor_Inspector_Field :: enum {
	None,
	Transform_Position,
	Transform_Rotation,
	Transform_Scale,
	Camera_Fov,
	Camera_Near,
	Camera_Far,
	Ambient_Color,
	Ambient_Intensity,
	Directional_Direction,
	Directional_Color,
	Directional_Intensity,
	Point_Color,
	Point_Intensity,
	Point_Range,
	Custom_Vec3,
	UI_Layout_Hidden,
	UI_HStack_Fill,
	UI_HStack_Draggable,
	UI_VStack_Fill,
	UI_VStack_Draggable,
	UI_Panel_Collapsible,
	UI_Panel_Collapsed,
	UI_Input_Read_Only,
	UI_Checkbox_Checked,
	UI_Checkbox_Read_Only,
}

Editor_Inspector_Axis :: enum {
	None,
	X,
	Y,
	Z,
}

Editor_Gizmo_Mode :: enum {
	Translate,
	Rotate,
	Scale,
}
Editor_Transform_Gizmo_Component :: struct {
	entity_index: int,
	mode: Editor_Gizmo_Mode,
}

MAX_SYSTEM_PROFILE_ENTRIES :: 64
SYSTEM_PROFILE_NAME_CAPACITY :: 96

System_Profile_Kind :: enum {
	Native,
	Luau,
}

System_Profile_Entry :: struct {
	name: [SYSTEM_PROFILE_NAME_CAPACITY]u8,
	name_length: int,
	kind: System_Profile_Kind,
	average_nanoseconds: f64,
}

System_Profile :: struct {
	entries: [MAX_SYSTEM_PROFILE_ENTRIES]System_Profile_Entry,
	entry_count: int,
	sample_frames: int,
	revision: u64,
}

Editor_UI_Role :: enum {
	None,
	Root,
	Viewport,
	Transport_Play,
	Transport_Stop,
	Transport_Step,
	Systems_Scroll,
	Systems_Name,
	Systems_Time,
	Browser_Scroll,
	Browser_Header,
	Browser_Row,
	Browser_Row_Label,
	Inspector_Header,
	Inspector_Scroll,
	Inspector_Content,
	Inspector_Panel,
	Inspector_Table,
	Inspector_Cell,
	Inspector_Input,
	Inspector_Checkbox,
	Status,
}

Editor_UI_Component :: struct {
	entity_index: int,
	role: Editor_UI_Role,
	target: Entity,
	slot: int,
	inspector_field: Editor_Inspector_Field,
	inspector_axis: Editor_Inspector_Axis,
	custom_storage_index: int,
	custom_field_index: int,
	numeric: bool,
	numeric_step: f32,
	numeric_min: f32,
	numeric_max: f32,
	numeric_has_min: bool,
	numeric_has_max: bool,
}

Mesh_Component :: struct {
	primitive: string,
}

Geometry_Component :: struct {
	handle: Geometry_Handle,
}
Material_Component :: struct {
	handle: Material_Handle,
}
Render_Instance_Component :: struct {
	geometry: Geometry_Handle,
	material: Material_Handle,
}

Named_Vec3 :: struct {
	name: string,
	value: Vec3,
}

Custom_Component :: struct {
	entity_index: int,
	component_id: Component_ID,
	name: string,
	vec3_fields: [dynamic]Named_Vec3,
}

Custom_Component_Storage :: struct {
	component_id: Component_ID,
	name: string,
	components: [dynamic]Custom_Component,
}

World_Entity :: struct {
	id: Entity,
	uuid: Entity_UUID,
	alive: bool,
	origin: Entity_Origin,
	name: string,
	component_revision: u64,
	transform_index: int,
	camera_index: int,
	ambient_light_index: int,
	directional_light_index: int,
	point_light_index: int,
	mesh_index: int,
	geometry_index: int,
	material_index: int,
	render_instance_index: int,
	render_active_index: int,
	render_camera_active_index: int,
	render_ambient_light_active_index: int,
	render_directional_light_active_index: int,
	render_point_light_active_index: int,
	render_dirty: bool,
	ui_dirty: bool,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,
	ui_layout_index: int,
	ui_hstack_index: int,
	ui_vstack_index: int,
	ui_scroll_area_index: int,
	ui_panel_index: int,
	ui_table_index: int,
	ui_text_index: int,
	ui_button_index: int,
	ui_input_index: int,
	ui_checkbox_index: int,
	editor_transform_gizmo_index: int,
	editor_ui_index: int,
	geometry_resource: string,
	material_resource: string,
}

Renderable :: struct {
	entity_index: int,
	transform_index: int,
	mesh_index: int,
}

Render_Instance :: struct {
	entity: World_Entity,
	transform: Transform_Component,
	mesh: Mesh_Component,
	geometry: Geometry_Component,
	material: Material_Component,
	shadow_caster: bool,
	shadow_receiver: bool,
}

Camera_Instance :: struct {
	entity: World_Entity,
	transform: Transform_Component,
	camera: Camera_Component,
}

Directional_Light_Instance :: struct {
	light: Directional_Light_Component,
}
Point_Light_Instance :: struct {
	position: Vec3,
	light: Point_Light_Component,
}

MAX_DIRECTIONAL_LIGHTS :: 4
MAX_POINT_LIGHTS :: 16

Render_List :: struct {
	instances: [dynamic]Render_Instance,
	camera: Camera_Instance,
	has_camera: bool,
	ambient: Vec3,
	directional_lights: [MAX_DIRECTIONAL_LIGHTS]Directional_Light_Instance,
	directional_light_count: int,
	point_lights: [MAX_POINT_LIGHTS]Point_Light_Instance,
	point_light_count: int,
}

World :: struct {
	instance_uuid: Entity_UUID,
	time: Time_Resource,
	entities: [dynamic]World_Entity,
	entity_by_uuid: map[Entity_UUID]int,
	transforms: #soa[dynamic]Transform_Component,
	cameras: [dynamic]Camera_Component,
	ambient_lights: [dynamic]Ambient_Light_Component,
	directional_lights: [dynamic]Directional_Light_Component,
	point_lights: [dynamic]Point_Light_Component,
	meshes: [dynamic]Mesh_Component,
	renderables: [dynamic]Renderable,
	geometries: [dynamic]Geometry_Component,
	materials: [dynamic]Material_Component,
	render_instances: [dynamic]Render_Instance_Component,
	render_active_entities: [dynamic]int,
	render_active_camera_entities: [dynamic]int,
	render_active_ambient_light_entities: [dynamic]int,
	render_active_directional_light_entities: [dynamic]int,
	render_active_point_light_entities: [dynamic]int,
	render_dirty_entities: [dynamic]int,
	render_structure_sync_count: u64,
	free_transform_indices: [dynamic]int,
	free_mesh_indices: [dynamic]int,
	free_geometry_indices: [dynamic]int,
	free_material_indices: [dynamic]int,
	free_render_instance_indices: [dynamic]int,
	ui_layouts: [dynamic]UI_Layout_Component,
	ui_hstacks: [dynamic]UI_Stack_Component,
	ui_vstacks: [dynamic]UI_Stack_Component,
	ui_scroll_areas: [dynamic]UI_Scroll_Area_Component,
	ui_panels: [dynamic]UI_Panel_Component,
	ui_tables: [dynamic]UI_Table_Component,
	ui_texts: [dynamic]UI_Text_Component,
	ui_buttons: [dynamic]UI_Button_Component,
	ui_inputs: [dynamic]UI_Input_Component,
	ui_checkboxes: [dynamic]UI_Checkbox_Component,
	editor_transform_gizmos: [dynamic]Editor_Transform_Gizmo_Component,
	editor_scene_cameras: [dynamic]Editor_Scene_Camera_Component,
	editor_uis: [dynamic]Editor_UI_Component,
	custom_components: [dynamic]Custom_Component_Storage,
	ui_structure_revision: u64,
	ui_dirty_entities: [dynamic]int,
}

Render_Frame :: struct {
	entity_count: int,
	camera_count: int,
	mesh_count: int,
	renderable_count: int,
}

component_name_is_valid :: proc "c" (name: string) -> bool {
	if name == "" {
		return false
	}

	token_start := 0
	for c, index in name {
		if c == '.' {
			if !component_token_is_valid(name[token_start:index]) {
				return false
			}
			token_start = index + 1
		}
	}

	return component_token_is_valid(name[token_start:])
}

component_name_is_project_level :: proc "c" (name: string) -> bool {
	return component_name_is_valid(name) && !component_name_is_namespaced(name)
}

component_name_is_namespaced :: proc "c" (name: string) -> bool {
	for c in name {
		if c == '.' {
			return true
		}
	}
	return false
}

component_token_is_valid :: proc "c" (token: string) -> bool {
	if token == "" {
		return false
	}
	for c in token {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			continue
		}
		return false
	}
	return true
}
