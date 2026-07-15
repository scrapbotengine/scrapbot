package shared

import runtime "base:runtime"
import "core:math"

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
	has_ui_list: bool,
	ui_list: UI_List_Component,
	has_ui_progress: bool,
	ui_progress: UI_Progress_Component,
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
	min_size: Vec2,
	margin: Vec4,
	padding: Vec4,
	background: Vec4,
	border_color: Vec4,
	border_width: f32,
	corner_radius: f32,
	hidden: bool,
	fill_width: bool,
	fill_height: bool,
	fit_content_width: bool,
	fit_content_height: bool,
	fixed_in_fill: bool,
}
UI_Stack_Component :: struct {
	gap: f32,
	fill: bool,
	draggable: bool,
	min_size: f32,
}
UI_Scroll_Area_Component :: struct {
	scroll_speed, smoothness: f32,
	scrollbar_width: f32,
	scrollbar_right: f32,
	scrollbar_vertical_inset: f32,
	minimum_thumb_size: f32,
	scrollbar_corner_radius: f32,
	scrollbar_track_color: Vec4,
	scrollbar_thumb_color: Vec4,
}
UI_Panel_Component :: struct {
	title: string,
	font: string,
	title_color: Vec4,
	title_background: Vec4,
	title_size: f32,
	title_height: f32,
	disclosure_size: f32,
	disclosure_margin: f32,
	disclosure_gap: f32,
	disclosure_corner_radius: f32,
	collapsible: bool,
	collapsed: bool,
}
UI_Table_Component :: struct {
	columns: int,
	column_gap: f32,
	row_gap: f32,
	proportional_columns: bool,
	resizable_columns: bool,
	min_column_width: f32,
}
UI_List_Component :: struct {
	selected: Entity_UUID,
	gap: f32,
	selection_background: Vec4,
	hover_background: Vec4,
	active_background: Vec4,
}
UI_Progress_Component :: struct {
	value: f32,
	maximum: f32,
	fill_color: Vec4,
	background_color: Vec4,
	inset: Vec4,
	corner_radius: f32,
	right_to_left: bool,
}
UI_State_Component :: struct {
	hovered: bool,
	active: bool,
	focused: bool,
	activated: bool,
	changed: bool,
	valid: bool,
	submitted: bool,
	cancelled: bool,
	activation_revision: u64,
	change_revision: u64,
	submit_revision: u64,
	cancel_revision: u64,
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
	alignment: UI_Text_Alignment,
	hover_background: Vec4,
	active_background: Vec4,
	hover_color: Vec4,
	active_color: Vec4,
}
UI_Input_Component :: struct {
	text: string,
	font: string,
	prefix: string,
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
	read_only: bool,
	numeric: bool,
	has_minimum: bool,
	has_maximum: bool,
	scrubbable: bool,
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
	corner_radius: f32,
	border_width: f32,
	check_inset: f32,
	check_corner_radius: f32,
	read_only: bool,
}

ui_layout_default :: proc "contextless" () -> UI_Layout_Component {
	return {}
}

ui_stack_default :: proc "contextless" () -> UI_Stack_Component {
	return {}
}

ui_scroll_area_default :: proc "contextless" () -> UI_Scroll_Area_Component {
	return {
		scroll_speed = 48,
		smoothness = 14,
		scrollbar_width = 3,
		scrollbar_right = 4,
		scrollbar_vertical_inset = 5,
		minimum_thumb_size = 18,
		scrollbar_corner_radius = 1.5,
		scrollbar_track_color = {0.08, 0.09, 0.11, 0.78},
		scrollbar_thumb_color = {0.34, 0.37, 0.42, 0.92},
	}
}

ui_panel_default :: proc "contextless" () -> UI_Panel_Component {
	return {
		title_color = {1, 1, 1, 1},
		title_size = 12,
		title_height = 32,
		disclosure_size = 10,
		disclosure_margin = 10,
		disclosure_gap = 8,
		disclosure_corner_radius = 1.35,
	}
}

ui_table_default :: proc "contextless" () -> UI_Table_Component {
	return {columns = 1, min_column_width = 32}
}

ui_list_default :: proc "contextless" () -> UI_List_Component {
	return {
		selection_background = {0.045, 0.095, 0.105, 1},
		hover_background = {0.028, 0.038, 0.050, 1},
		active_background = {0.040, 0.055, 0.072, 1},
	}
}

ui_progress_default :: proc "contextless" () -> UI_Progress_Component {
	return {maximum = 1, fill_color = {1, 1, 1, 1}}
}

ui_text_default :: proc "contextless" () -> UI_Text_Component {
	return {color = {1, 1, 1, 1}, size = 16}
}

ui_button_default :: proc "contextless" () -> UI_Button_Component {
	return {color = {1, 1, 1, 1}, size = 16, alignment = .Center}
}

ui_input_default :: proc "contextless" () -> UI_Input_Component {
	return {
		color = {1, 1, 1, 1},
		prefix_color = {1, 1, 1, 1},
		size = 16,
		step = 1,
		prefix_gap = 3,
		prefix_corner_radius = 2,
		prefix_text_padding = 3,
		selection_corner_radius = 2,
		focus_border_width = 1,
		invalid_border_width = 1.5,
		caret_width = 1,
		caret_inset = 2,
		selection_background = {0.15, 0.45, 0.40, 0.55},
		focus_border_color = {0.15, 0.85, 0.72, 1},
		invalid_border_color = {0.92, 0.24, 0.28, 1},
	}
}

ui_checkbox_default :: proc "contextless" () -> UI_Checkbox_Component {
	return {
		box_size = 18,
		background = {0.025, 0.030, 0.040, 1},
		checked_background = {0.08, 0.55, 0.46, 1},
		border_color = {0.24, 0.27, 0.32, 1},
		check_color = {0.95, 0.97, 0.98, 1},
		hover_background = {0.12, 0.64, 0.54, 1},
		active_background = {0.06, 0.42, 0.36, 1},
		corner_radius = -1,
		border_width = 1,
		check_inset = -1,
		check_corner_radius = -1,
	}
}

ui_layout_is_valid :: proc "contextless" (value: UI_Layout_Component) -> bool {
	return(
		value.size.x > 0 &&
		value.size.y > 0 &&
		value.border_width >= 0 &&
		value.corner_radius >= 0 &&
		value.min_size.x >= 0 &&
		value.min_size.y >= 0 &&
		ui_vec4_is_non_negative(value.margin) &&
		ui_vec4_is_non_negative(value.padding) \
	)
}

ui_stack_is_valid :: proc "contextless" (value: UI_Stack_Component) -> bool {
	return value.gap >= 0 && value.min_size >= 0 && (!value.draggable || value.fill)
}

ui_scroll_area_is_valid :: proc "contextless" (value: UI_Scroll_Area_Component) -> bool {
	return(
		value.scroll_speed > 0 &&
		value.smoothness > 0 &&
		value.scrollbar_width >= 0 &&
		value.scrollbar_right >= 0 &&
		value.scrollbar_vertical_inset >= 0 &&
		value.minimum_thumb_size >= 0 &&
		value.scrollbar_corner_radius >= 0 \
	)
}

ui_panel_is_valid :: proc "contextless" (value: UI_Panel_Component) -> bool {
	if value.title != "" && (value.title_size <= 0 || value.title_height <= 0) {
		return false
	}
	if value.collapsible && value.title == "" {
		return false
	}
	if value.disclosure_size < 0 ||
	   value.disclosure_margin < 0 ||
	   value.disclosure_gap < 0 ||
	   value.disclosure_corner_radius < 0 {
		return false
	}
	return !value.collapsed || value.collapsible
}

ui_table_is_valid :: proc "contextless" (value: UI_Table_Component) -> bool {
	return(
		value.columns >= 1 &&
		value.columns <= 64 &&
		value.column_gap >= 0 &&
		value.row_gap >= 0 &&
		value.min_column_width >= 0 &&
		(!value.resizable_columns || value.proportional_columns) \
	)
}

ui_list_is_valid :: proc "contextless" (value: UI_List_Component) -> bool {
	return value.gap >= 0
}

ui_progress_is_valid :: proc "contextless" (value: UI_Progress_Component) -> bool {
	return value.maximum > 0 && value.corner_radius >= 0 && ui_vec4_is_non_negative(value.inset)
}

ui_text_is_valid :: proc "contextless" (value: UI_Text_Component) -> bool {
	return value.text != "" && value.size > 0
}

ui_button_is_valid :: proc "contextless" (value: UI_Button_Component) -> bool {
	return value.text != "" && value.size > 0
}

ui_input_is_valid :: proc "contextless" (value: UI_Input_Component) -> bool {
	if value.size <= 0 ||
	   value.prefix_width < 0 ||
	   value.prefix_gap < 0 ||
	   value.prefix_corner_radius < 0 ||
	   value.prefix_text_padding < 0 ||
	   value.selection_corner_radius < 0 ||
	   value.focus_border_width < 0 ||
	   value.invalid_border_width < 0 ||
	   value.caret_width < 0 ||
	   value.caret_inset < 0 {
		return false
	}
	if !value.numeric {
		return true
	}
	if math.is_nan(value.number) || math.is_inf(value.number) || value.step <= 0 {
		return false
	}
	if value.has_minimum && (math.is_nan(value.minimum) || math.is_inf(value.minimum)) {
		return false
	}
	if value.has_maximum && (math.is_nan(value.maximum) || math.is_inf(value.maximum)) {
		return false
	}
	if value.has_minimum && value.number < value.minimum {
		return false
	}
	if value.has_maximum && value.number > value.maximum {
		return false
	}
	return !value.has_minimum || !value.has_maximum || value.minimum <= value.maximum
}

ui_checkbox_is_valid :: proc "contextless" (value: UI_Checkbox_Component) -> bool {
	return(
		value.box_size > 0 &&
		value.corner_radius >= -1 &&
		value.border_width >= 0 &&
		value.check_inset >= -1 &&
		value.check_corner_radius >= -1 \
	)
}

ui_vec4_is_non_negative :: proc "contextless" (value: Vec4) -> bool {
	return value.x >= 0 && value.y >= 0 && value.z >= 0 && value.w >= 0
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
	Engine,
	Project_Odin,
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
	Systems_Row,
	Systems_Name,
	Systems_Time,
	Systems_Origin,
	Browser_Scroll,
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
	input_original_number: f32,
	input_has_original_number: bool,
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
	ui_list_index: int,
	ui_progress_index: int,
	ui_state_index: int,
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
	string_allocator: runtime.Allocator,
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
	ui_lists: [dynamic]UI_List_Component,
	ui_progresses: [dynamic]UI_Progress_Component,
	ui_states: [dynamic]UI_State_Component,
	ui_texts: [dynamic]UI_Text_Component,
	ui_buttons: [dynamic]UI_Button_Component,
	ui_inputs: [dynamic]UI_Input_Component,
	ui_checkboxes: [dynamic]UI_Checkbox_Component,
	free_ui_layout_indices: [dynamic]int,
	free_ui_hstack_indices: [dynamic]int,
	free_ui_vstack_indices: [dynamic]int,
	free_ui_scroll_area_indices: [dynamic]int,
	free_ui_panel_indices: [dynamic]int,
	free_ui_table_indices: [dynamic]int,
	free_ui_list_indices: [dynamic]int,
	free_ui_progress_indices: [dynamic]int,
	free_ui_state_indices: [dynamic]int,
	free_ui_text_indices: [dynamic]int,
	free_ui_button_indices: [dynamic]int,
	free_ui_input_indices: [dynamic]int,
	free_ui_checkbox_indices: [dynamic]int,
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
