package ui

import component "../component"
import ecs "../ecs"
import file_browser "../file_browser"
import resources "../resources"
import shared "../shared"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

MAX_NODES :: 4096
MAX_PAINT_COMMANDS :: 16384
MAX_EDITOR_OVERLAY_PAINT_COMMANDS :: 4096
MAX_EMBEDDED_VIEWPORTS :: 8
MAX_RESOURCE_THUMBNAILS :: 256
MAX_TEXT_LINES :: 256
FONT_FIRST_CHAR :: shared.FONT_FIRST_CHAR
FONT_CHAR_COUNT :: shared.FONT_CHAR_COUNT
FONT_ATLAS_SIZE :: shared.FONT_ATLAS_SIZE
FONT_ASCENDER :: f32(0.96875)
FONT_ATLAS_DATA :: #load("assets/inter_mtsdf.bin")
Font_Glyph :: shared.Font_Glyph

EDITOR_TOP_BAR_HEIGHT :: f32(52)
EDITOR_STATUS_BAR_HEIGHT :: f32(30)
EDITOR_LEFT_SIDEBAR_WIDTH :: f32(260)
EDITOR_RIGHT_SIDEBAR_WIDTH :: f32(420)
EDITOR_SIDEBAR_MIN_WIDTH :: f32(180)
EDITOR_VIEWPORT_MIN_WIDTH :: f32(320)
EDITOR_VIEWPORT_INSET :: f32(4)
EDITOR_ENTITY_ROW_HEIGHT :: f32(32)
EDITOR_RESOURCE_ROW_HEIGHT :: f32(54)
EDITOR_TEXT_SIZE :: f32(13)
UI_INPUT_PREFIX_WIDTH :: f32(16)
UI_INPUT_PREFIX_GAP :: f32(3)
EDITOR_SCROLL_SPEED :: f32(48)
EDITOR_SCROLL_SMOOTHNESS :: f32(18)
EDITOR_SNAPSHOT_INTERVAL :: f32(0.2)

Rect :: struct {
	x, y, width, height: f32,
}
Pointer_Input :: struct {
	position: shared.Vec2,
	wheel_y: f32,
	primary_down, primary_pressed, primary_released: bool,
	edges_authoritative: bool,
	available: bool,
}
Pointer_Cursor :: enum {
	Default,
	Pointer,
	Text_Edit,
	Horizontal_Resize,
	Vertical_Resize,
	Move,
	Not_Allowed,
}
Keyboard_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, shift, fine, enter, escape, select_all: bool,
	actions: Editor_Actions,
}

Editor_Action :: enum {
	Toggle_Editor,
	Toggle_Left_Sidebar,
	Toggle_Right_Sidebar,
	Transport_Play,
	Transport_Pause,
	Transport_Stop,
	Transport_Step,
	Save,
	Undo,
	Redo,
	Duplicate_Entity,
	Delete_Entity,
	Focus_Selected,
	Gizmo_Translate,
	Gizmo_Rotate,
	Transform_Translate,
	Transform_Rotate,
	Transform_Scale,
	Transform_Axis_X,
	Transform_Axis_Y,
	Transform_Axis_Z,
}

Editor_Actions :: bit_set[Editor_Action]

editor_action_requested :: proc(input: Keyboard_Input, action: Editor_Action) -> bool {
	return action in input.actions
}

pointer_press_started :: proc(pointer: Pointer_Input, previous_down: bool) -> bool {
	if !pointer.available {
		return false
	}
	if pointer.edges_authoritative {
		return pointer.primary_pressed
	}
	return pointer.primary_down && !previous_down
}

pointer_press_released :: proc(pointer: Pointer_Input, previous_down: bool) -> bool {
	if !pointer.available {
		return false
	}
	if pointer.edges_authoritative {
		return pointer.primary_released
	}
	return !pointer.primary_down && previous_down
}

Interaction_Event_Kind :: enum {
	Pointer_Activate,
	Keyboard,
}

Interaction_Event :: struct {
	kind: Interaction_Event_Kind,
	target: shared.Entity,
	current_target: shared.Entity,
	position: shared.Vec2,
	cancelled: bool,
}

cancel_interaction_event :: proc(event: ^Interaction_Event) {
	if event != nil {
		event.cancelled = true
	}
}

consume_editor_pointer_activation :: proc(state: ^State, pointer: Pointer_Input) {
	if state == nil || !pointer.available || !pointer.primary_down {
		return
	}
	event := Interaction_Event {
		kind = .Pointer_Activate,
		position = pointer.position,
	}
	cancel_interaction_event(&event)
	if event.cancelled {
		// Preserve the physical press edge through editor reconciliation. The
		// release clears this normally, so a consumed press cannot become a
		// delayed activation on the following frame.
		state.editor_previous_primary_down = true
		state.editor_pointer_activation_consumed = true
	}
}

editor_consumed_pointer_input :: proc(pointer: Pointer_Input) -> Pointer_Input {
	if !pointer.available {
		return pointer
	}
	// Keep the physical button state synchronized while moving the editor hit
	// point outside every retained node. Clearing availability would reset the
	// previous-button baseline and could turn the held confirmation press into a
	// fresh activation on the following frame.
	return {
		position = {-1, -1},
		primary_down = pointer.primary_down,
		available = true,
		edges_authoritative = pointer.edges_authoritative,
	}
}

editor_world_tool_captures_pointer :: proc(state: ^State) -> bool {
	return(
		state != nil &&
		(state.editor_gizmo_captures_pointer || state.editor_light_gizmo_captures_pointer) \
	)
}
Paint_Kind :: enum {
	Panel,
	Glyph,
	Icon,
	Line,
	Triangle,
	Ring,
	Disclosure,
	Checkmark,
	Viewport,
	Thumbnail,
}
Paint_Command :: struct {
	kind: Paint_Kind,
	rect: Rect,
	color: shared.Vec4,
	uv: shared.Vec4,
	corner_radius: f32,
	border_color: shared.Vec4,
	border_width: f32,
	line_start, line_end: shared.Vec2,
	line_thickness: f32,
	triangle: [3]shared.Vec2,
	ring_center, ring_axis_x, ring_axis_y: shared.Vec2,
	ring_thickness: f32,
	disclosure_expanded: bool,
	font_layer: f32,
	resource: shared.Resource_UUID,
	clip: Rect,
	has_clip: bool,
	gradient: bool,
	corner_colors: [4]shared.Vec4,
}
Editor_Gizmo_Handle :: enum {
	None,
	X,
	Y,
	Z,
	XY,
	XZ,
	YZ,
	Center,
}
EDITOR_GIZMO_RING_POINT_COUNT :: 64
EDITOR_CAMERA_MESH_MAX_SEGMENTS :: 512
EDITOR_SCENE_ICON_MAX_COUNT :: 256

Editor_Camera_Mesh_Segment :: struct {
	entity: shared.Entity,
	start, end: shared.Vec2,
	color: shared.Vec4,
	thickness: f32,
}

Editor_Scene_Icon_Kind :: enum {
	Camera,
	Directional_Light,
	Point_Light,
}

Editor_Scene_Icon :: struct {
	entity: shared.Entity,
	kind: Editor_Scene_Icon_Kind,
	center: shared.Vec2,
	clip: Rect,
	selected: bool,
}

EDITOR_LIGHT_GIZMO_MAX_SEGMENTS :: 192

Editor_Light_Gizmo_Kind :: enum {
	None,
	Point_Range,
	Directional_Direction,
}

Editor_Light_Gizmo_Segment :: struct {
	start, end: shared.Vec2,
}

Font_Atlas :: struct {
	glyphs: ^[FONT_CHAR_COUNT]shared.Font_Glyph,
	ascender: f32,
	layer: f32,
	ready: bool,
}
Text_Line :: struct {
	start, end: int,
	advance: f32,
}
Split_Handle :: struct {
	rect: Rect,
	before_node, after_node: int,
	min_size: f32,
	horizontal: bool,
	editor: bool,
	hovered, active: bool,
}
Dock_Tab :: struct {
	rect: Rect,
	space_node, item_node: int,
	editor: bool,
	hovered, active, drop_target: bool,
}
Stack_Drag_Interaction :: struct {
	stack: shared.Entity,
	source: shared.Entity,
	target_stack: shared.Entity,
	target_dock_space: shared.Entity,
	target: shared.Entity,
	start: shared.Vec2,
	placement: shared.UI_Drop_Placement,
	armed: bool,
	dragging: bool,
	title_handle: bool,
}
Node :: struct {
	entity: shared.Entity,
	origin: shared.Entity_Origin,
	editor_role: shared.Editor_UI_Role,
	layout_index, canvas_index, hstack_index, vstack_index, scroll_area_index, panel_index, dock_space_index, dock_item_index, table_index, list_index, progress_index, viewport_index, icon_index, text_index, button_index, input_index, checkbox_index, color_picker_index, parent_entity_index: int,
	parent_node_index, first_child_node, next_sibling_node: int,
	rect, clip: Rect,
	resolved_size: shared.Vec2,
	fill_available_size: shared.Vec2,
	paint_order: int,
	scroll_offset, scroll_target, scroll_max, scroll_content_height: f32,
	split_weight: f32,
	split_parent: shared.Entity,
	tree_depth: int,
	list_flow_offset, list_flow_count: int,
	viewport_layer: int,
	split_weight_valid: bool,
	seen, laid_out, hovered, active, has_clip: bool,
	resolved_width_valid, resolved_height_valid: bool,
	fill_width_valid, fill_height_valid: bool,
}

Viewport_Surface :: struct {
	entity: shared.Entity,
	rect: Rect,
	clip: Rect,
	has_clip: bool,
	component: shared.UI_Viewport_Component,
	editor: bool,
}
Thumbnail_Surface :: struct {
	entity: shared.Entity,
	component: shared.UI_Viewport_Component,
}
EDITOR_HISTORY_CAPACITY :: 128
MAX_UI_EVENTS :: shared.MAX_UI_EVENTS
UI_Event_Kind :: enum {
	Activated,
	Changed,
	Submitted,
	Cancelled,
	Dropped,
}
UI_Event_Part :: enum {
	Control,
	Panel_Title,
}
UI_Event :: struct {
	kind: UI_Event_Kind,
	part: UI_Event_Part,
	entity: shared.Entity,
	source: shared.Entity,
	target: shared.Entity,
	drop_placement: shared.UI_Drop_Placement,
	position: shared.Vec2,
}
Color_Picker_Part :: enum {
	None,
	Saturation_Value,
	Hue,
	Alpha,
	Exposure,
}
List_Drag_Interaction :: struct {
	list: shared.Entity,
	source: shared.Entity,
	target: shared.Entity,
	start: shared.Vec2,
	armed: bool,
	dragging: bool,
	drop_valid: bool,
	placement: shared.UI_Drop_Placement,
}
Action_Drag_Interaction :: struct {
	source: shared.Entity,
	target: shared.Entity,
	start: shared.Vec2,
	position: shared.Vec2,
	armed: bool,
	dragging: bool,
}
EDITOR_TRANSACTION_MAX_CHANGES :: 6
Editor_Edit_Value_Kind :: enum {
	Number,
	Boolean,
}
Editor_Edit_Change :: struct {
	target_uuid: shared.Entity_UUID,
	component_revision: u64,
	field: shared.Editor_Inspector_Field,
	axis: shared.Editor_Inspector_Axis,
	custom_storage_index: int,
	custom_field_index: int,
	kind: Editor_Edit_Value_Kind,
	before_number: f32,
	after_number: f32,
	before_boolean: bool,
	after_boolean: bool,
}
Editor_Resource_Change :: struct {
	resource_id: shared.Resource_UUID,
	field: shared.Editor_Inspector_Field,
	axis: shared.Editor_Inspector_Axis,
	before_number: f32,
	after_number: f32,
}
Editor_Structural_Change :: struct {
	target_uuid: shared.Entity_UUID,
	before: ^ecs.Entity_Snapshot,
	after: ^ecs.Entity_Snapshot,
	before_order: [dynamic]shared.Entity_UUID,
	after_order: [dynamic]shared.Entity_UUID,
}
Editor_Structural_Batch_Change :: struct {
	items: [dynamic]Editor_Structural_Change,
	before_order: [dynamic]shared.Entity_UUID,
	after_order: [dynamic]shared.Entity_UUID,
	before_selection: [dynamic]shared.Entity_UUID,
	after_selection: [dynamic]shared.Entity_UUID,
}
Editor_Component_Structural_Change :: struct {
	target_uuid: shared.Entity_UUID,
	before: ^ecs.Registered_Component_Snapshot,
	after: ^ecs.Registered_Component_Snapshot,
}
Editor_Resource_Structural_Change :: struct {
	resource_id: shared.Resource_UUID,
	before: ^resources.Project_Material_Snapshot,
	after: ^resources.Project_Material_Snapshot,
}
Editor_Transform_Batch_Item :: struct {
	target_uuid: shared.Entity_UUID,
	component_revision: u64,
	before: shared.Transform_Component,
	after: shared.Transform_Component,
}
Editor_Transform_Batch_Change :: struct {
	items: [dynamic]Editor_Transform_Batch_Item,
}
Editor_Edit_Transaction :: struct {
	changes: [EDITOR_TRANSACTION_MAX_CHANGES]Editor_Edit_Change,
	change_count: int,
	resource_changes: [4]Editor_Resource_Change,
	resource_change_count: int,
	structural: ^Editor_Structural_Change,
	structural_batch: ^Editor_Structural_Batch_Change,
	component_structural: ^Editor_Component_Structural_Change,
	resource_structural: ^Editor_Resource_Structural_Change,
	transform_batch: ^Editor_Transform_Batch_Change,
}

Editor_Gizmo_Transform_Snapshot :: struct {
	target: shared.Entity,
	target_uuid: shared.Entity_UUID,
	component_revision: u64,
	local: shared.Transform_Component,
	world: shared.Transform_Component,
}

Editor_Transport_Visual_State :: struct {
	playing: bool,
	stopped: bool,
	dirty: bool,
	save_failed: bool,
	revert_failed: bool,
	history_cursor: int,
	history_count: int,
}

Editor_Gizmo_Toolbar_Visual_State :: struct {
	visible: bool,
	space: shared.Editor_Gizmo_Space,
	pivot: shared.Editor_Gizmo_Pivot,
}

Editor_Sidebar_Visual_State :: struct {
	world_uuid: shared.Entity_UUID,
	left_visible: bool,
	right_visible: bool,
}

Editor_Model_Placement_Request :: struct {
	resource: shared.Resource_UUID,
	parent: shared.Entity_UUID,
	pointer: shared.Vec2,
	has_pointer: bool,
}

State :: struct {
	events: [MAX_UI_EVENTS]UI_Event,
	event_count: int,
	nodes: [MAX_NODES]Node,
	node_count: int,
	paint: [MAX_PAINT_COMMANDS]Paint_Command,
	paint_count: int,
	editor_paint_cache: [MAX_PAINT_COMMANDS]Paint_Command,
	editor_paint_cache_count: int,
	editor_overlay_paint: [MAX_EDITOR_OVERLAY_PAINT_COMMANDS]Paint_Command,
	editor_overlay_paint_count: int,
	editor_overlay_compare_count: int,
	editor_overlay_rebuild_changed: bool,
	paint_editor_overlay: bool,
	editor_paint_end: int,
	project_paint_signature, editor_paint_signature: u64,
	project_paint_signature_valid, editor_paint_signature_valid: bool,
	project_paint_output_revision: u64,
	editor_paint_output_revision: u64,
	editor_overlay_paint_output_revision: u64,
	font: Font_Atlas,
	resource_registry: ^resources.Registry,
	component_registry: ^component.Registry,
	component_menu_cached_registry: ^component.Registry,
	component_menu_registry_revision: u64,
	component_menu_definition_indices: [component.MAX_COMPONENTS]int,
	component_menu_definition_count: int,
	ui_world_uuid: shared.Entity_UUID,
	ui_structure_revision: u64,
	ui_structure_synced: bool,
	ui_project_layout_revision: u64,
	ui_editor_layout_revision: u64,
	project_canvas_entity_index: int,
	project_canvas: shared.UI_Canvas_Component,
	project_canvas_valid: bool,
	ui_project_paint_revision: u64,
	ui_editor_paint_revision: u64,
	viewport_surfaces: [MAX_EMBEDDED_VIEWPORTS]Viewport_Surface,
	thumbnail_surfaces: [MAX_RESOURCE_THUMBNAILS]Thumbnail_Surface,
	thumbnail_surface_count: int,
	viewport_surface_count: int,
	viewport_node_indices: [MAX_NODES]int,
	viewport_node_count: int,
	viewport_drag_entity: shared.Entity,
	viewport_drag_editor: bool,
	viewport_drag_active: bool,
	viewport_drag_position: shared.Vec2,
	ui_layout_valid: bool,
	ui_project_viewport: Rect,
	ui_editor_viewport: Rect,
	ui_structure_sync_count: u64,
	ui_hierarchy_rebuild_count: u64,
	ui_project_list_flow_revision: u64,
	ui_editor_list_flow_revision: u64,
	ui_project_list_flow_structure_revision: u64,
	ui_editor_list_flow_structure_revision: u64,
	ui_project_list_flow_rebuild_count: u64,
	ui_editor_list_flow_rebuild_count: u64,
	ui_project_list_flow_nodes: [MAX_NODES]int,
	ui_editor_list_flow_nodes: [MAX_NODES]int,
	ui_project_list_flow_count: int,
	ui_editor_list_flow_count: int,
	layout_node_visit_count: u64,
	layout_child_edge_visit_count: u64,
	paint_node_visit_count: u64,
	paint_child_edge_visit_count: u64,
	ui_editor_visible: bool,
	active_entity: shared.Entity,
	has_active_entity: bool,
	previous_primary_down: bool,
	editor_ui_active_entity: shared.Entity,
	editor_ui_has_active_entity: bool,
	list_drags: [2]List_Drag_Interaction,
	action_drags: [2]Action_Drag_Interaction,
	stack_drags: [2]Stack_Drag_Interaction,
	next_paint_order: int,
	layout_size_changed: bool,
	split_handles: [MAX_NODES]Split_Handle,
	split_handle_count, active_split_handle: int,
	split_previous_primary_down: bool,
	editor_split_previous_primary_down: bool,
	active_split_editor: bool,
	split_drag_pointer: f32,
	dock_tabs: [MAX_NODES]Dock_Tab,
	dock_tab_count, active_dock_tab: int,
	dock_previous_primary_down, editor_dock_previous_primary_down: bool,
	active_dock_editor: bool,
	dock_drag_start: shared.Vec2,
	dock_dragging: bool,
	dock_drop_space_node: int,
	dock_drop_space_placement: shared.UI_Drop_Placement,
	dock_drop_stack_node: int,
	dock_drop_stack_target: shared.Entity,
	dock_drop_stack_placement: shared.UI_Drop_Placement,
	pointer_cursor: Pointer_Cursor,
	editor_visible: bool,
	editor_left_sidebar_visible: bool,
	editor_right_sidebar_visible: bool,
	editor_simulation_playing: bool,
	editor_simulation_stopped: bool,
	editor_simulation_step_requested: bool,
	editor_playback_begin_requested: bool,
	editor_playback_stop_requested: bool,
	editor_scene_save_requested: bool,
	editor_scene_revert_requested: bool,
	editor_focus_selected_requested: bool,
	editor_resource_reimport_requested: bool,
	editor_resource_reimport_all_requested: bool,
	editor_resource_reimport_id: shared.Resource_UUID,
	editor_resource_reimport_result_id: shared.Resource_UUID,
	editor_resource_reimport_failed: bool,
	editor_resource_reimport_message: string,
	editor_scene_dirty: bool,
	editor_scene_save_failed: bool,
	editor_scene_revert_failed: bool,
	editor_dirty_entities: [dynamic]shared.Entity_UUID,
	editor_dirty_entity_lookup: map[shared.Entity_UUID]bool,
	editor_dirty_resources: [dynamic]shared.Resource_UUID,
	editor_dirty_resource_lookup: map[shared.Resource_UUID]bool,
	editor_collapsed_entities: map[shared.Entity_UUID]bool,
	editor_pixel_density: f32,
	editor_paint_start: int,
	editor_selected_entity: shared.Entity,
	editor_selected_uuids: [dynamic]shared.Entity_UUID,
	editor_selection_revision: u64,
	editor_selection_toggle_modifier: bool,
	editor_has_selection: bool,
	editor_selected_resource: shared.Resource_UUID,
	editor_has_resource_selection: bool,
	editor_resource_browser: file_browser.State,
	editor_resource_browser_initialized: bool,
	editor_resource_browser_ready: bool,
	editor_resource_browser_error: string,
	editor_snapshot_elapsed: f32,
	editor_snapshot_valid: bool,
	editor_snapshot_was_visible: bool,
	editor_snapshot_has_selection: bool,
	editor_snapshot_selected_entity: shared.Entity,
	editor_snapshot_refresh_count: u64,
	editor_browser_snapshot_valid: bool,
	editor_browser_snapshot_selection_revision: u64,
	editor_inspector_snapshot_valid: bool,
	editor_inspector_snapshot_entity: shared.Entity,
	editor_inspector_snapshot_selection_revision: u64,
	editor_inspector_snapshot_component_revision: u64,
	editor_inspector_snapshot_has_resource: bool,
	editor_inspector_snapshot_resource: shared.Resource_UUID,
	editor_inspector_snapshot_resource_version: u32,
	editor_inspector_snapshot_stopped: bool,
	editor_inspector_snapshot_refresh_count: u64,
	editor_layout_invalidated: bool,
	editor_transport_visual_state: Editor_Transport_Visual_State,
	editor_transport_visual_valid: bool,
	editor_gizmo_toolbar_visual_state: Editor_Gizmo_Toolbar_Visual_State,
	editor_gizmo_toolbar_visual_valid: bool,
	editor_sidebar_visual_state: Editor_Sidebar_Visual_State,
	editor_sidebar_visual_valid: bool,
	system_profile: ^shared.System_Profile,
	editor_system_profile_revision: u64,
	performance_diagnostics: ^shared.Performance_Diagnostics,
	editor_performance_diagnostics_revision: u64,
	editor_previous_primary_down: bool,
	editor_pointer_activation_consumed: bool,
	focused_input: shared.Entity,
	has_focused_input: bool,
	focused_input_editor: bool,
	focused_editor_input_binding: shared.Editor_UI_Component,
	has_focused_editor_input_binding: bool,
	input_cursor, input_anchor: int,
	input_scroll_x: f32,
	input_blink_elapsed: f32,
	input_original_text: string,
	input_original_number: f32,
	input_has_original_number: bool,
	input_valid: bool,
	input_scrub_armed: bool,
	input_scrubbing: bool,
	input_scrub_start_x: f32,
	input_scrub_start_number: f32,
	editor_history: [EDITOR_HISTORY_CAPACITY]Editor_Edit_Transaction,
	editor_history_count: int,
	editor_history_cursor: int,
	editor_history_clean_cursor: int,
	editor_history_clean_valid: bool,
	editor_pick_requested: bool,
	editor_pick_position: shared.Vec2,
	editor_pick_toggle_selection: bool,
	editor_box_select_armed: bool,
	editor_box_select_active: bool,
	editor_box_select_start, editor_box_select_current: shared.Vec2,
	editor_box_select_clip: Rect,
	editor_box_select_toggle_selection: bool,
	editor_box_select_requested: bool,
	editor_box_select_request_rect: Rect,
	editor_box_select_request_toggle_selection: bool,
	editor_model_placement_requested: bool,
	editor_model_placement_request: Editor_Model_Placement_Request,
	editor_model_placement_preview_visible: bool,
	editor_model_placement_preview_resource: shared.Resource_UUID,
	editor_model_placement_preview_position: shared.Vec3,
	editor_model_placement_preview_contact: shared.Vec2,
	editor_model_placement_preview_origin: shared.Vec2,
	editor_model_placement_preview_clip: Rect,
	editor_placement_snap_step: f32,
	editor_rotation_snap_step: f32,
	editor_scale_snap_step: f32,
	editor_scene_camera_captures_input: bool,
	editor_camera_mesh_segments: [EDITOR_CAMERA_MESH_MAX_SEGMENTS]Editor_Camera_Mesh_Segment,
	editor_camera_mesh_segment_count: int,
	editor_scene_icons: [EDITOR_SCENE_ICON_MAX_COUNT]Editor_Scene_Icon,
	editor_scene_icon_count: int,
	editor_light_gizmo_segments: [EDITOR_LIGHT_GIZMO_MAX_SEGMENTS]Editor_Light_Gizmo_Segment,
	editor_light_gizmo_segment_count: int,
	editor_light_gizmo_kind: Editor_Light_Gizmo_Kind,
	editor_light_gizmo_entity: shared.Entity,
	editor_light_gizmo_origin, editor_light_gizmo_handle: shared.Vec2,
	editor_light_gizmo_clip: Rect,
	editor_light_gizmo_visible: bool,
	editor_light_gizmo_hovered: bool,
	editor_light_gizmo_active: bool,
	editor_light_gizmo_captures_pointer: bool,
	editor_light_gizmo_drag_range: f32,
	editor_light_gizmo_drag_direction: shared.Vec3,
	editor_light_gizmo_drag_origin: shared.Vec3,
	editor_light_gizmo_drag_world_size: f32,
	editor_light_gizmo_drag_pixels_per_world: f32,
	editor_gizmo_visible: bool,
	editor_gizmo_mode: shared.Editor_Gizmo_Mode,
	editor_gizmo_space: shared.Editor_Gizmo_Space,
	editor_gizmo_pivot: shared.Editor_Gizmo_Pivot,
	editor_gizmo_bounds_center: shared.Vec3,
	editor_gizmo_bounds_selection_revision: u64,
	editor_gizmo_bounds_world_uuid: shared.Entity_UUID,
	editor_gizmo_bounds_render_topology_revision: u64,
	editor_gizmo_bounds_render_hierarchy_revision: u64,
	editor_gizmo_bounds_geometry_topology_revision: u64,
	editor_gizmo_bounds_valid: bool,
	editor_render_debug_view_override: bool,
	editor_render_debug_view: shared.Render_Debug_View,
	editor_render_debug_hiz_mip: u32,
	editor_render_debug_occlusion_frozen: bool,
	editor_gizmo_origin: shared.Vec2,
	editor_gizmo_endpoints: [3]shared.Vec2,
	editor_gizmo_plane_points: [3][4]shared.Vec2,
	editor_gizmo_ring_points: [3][EDITOR_GIZMO_RING_POINT_COUNT]shared.Vec2,
	editor_gizmo_hovered_handle: Editor_Gizmo_Handle,
	editor_gizmo_active_handle: Editor_Gizmo_Handle,
	editor_gizmo_captures_pointer: bool,
	editor_transform_chord_mode: shared.Editor_Gizmo_Mode,
	editor_gizmo_keyboard_active: bool,
	editor_keyboard_escape_consumed: bool,
	editor_gizmo_drag_pointer: shared.Vec2,
	editor_gizmo_drag_last_pointer: shared.Vec2,
	editor_gizmo_drag_virtual_pointer: shared.Vec2,
	editor_gizmo_drag_visual_origin: shared.Vec2,
	editor_gizmo_drag_visual_start_pointer: shared.Vec2,
	editor_gizmo_drag_angle: f32,
	editor_gizmo_drag_waits_for_rotation_radius: bool,
	editor_gizmo_drag_position: shared.Vec3,
	editor_gizmo_drag_rotation: shared.Vec3,
	editor_gizmo_drag_scale: shared.Vec3,
	editor_gizmo_drag_world_transform: shared.Transform_Component,
	editor_gizmo_drag_selection: [dynamic]Editor_Gizmo_Transform_Snapshot,
	editor_gizmo_drag_pivot: shared.Vec3,
	editor_gizmo_drag_direction: shared.Vec2,
	editor_gizmo_drag_screen_axes: [3]shared.Vec2,
	editor_gizmo_drag_world_axes: [3]shared.Vec3,
	editor_gizmo_drag_view_axis: shared.Vec3,
	editor_gizmo_drag_pixels: f32,
	editor_gizmo_drag_world_scale: f32,
	err: string,
	color_picker_drag_entity: shared.Entity,
	color_picker_drag_part: Color_Picker_Part,
	color_picker_drag_editor: bool,
	color_picker_drag_active: bool,
}

effective_render_debug_hiz_mip :: proc "contextless" (
	state: ^State,
	camera: shared.Camera_Component,
) -> u32 {
	if state != nil &&
	   state.editor_visible &&
	   state.editor_render_debug_view_override &&
	   state.editor_render_debug_view == .HiZ {
		return state.editor_render_debug_hiz_mip
	}
	return shared.camera_debug_hiz_mip(camera)
}

effective_render_debug_occlusion_freeze :: proc "contextless" (
	state: ^State,
	camera: shared.Camera_Component,
) -> bool {
	if state != nil &&
	   state.editor_visible &&
	   state.editor_render_debug_view_override &&
	   state.editor_render_debug_view == .Occlusion_Queries {
		return state.editor_render_debug_occlusion_frozen
	}
	return camera.debug_occlusion_freeze
}

effective_render_debug_view :: proc "contextless" (
	state: ^State,
	camera: shared.Camera_Component,
) -> shared.Render_Debug_View {
	if state != nil && state.editor_visible && state.editor_render_debug_view_override {
		return state.editor_render_debug_view
	}
	return camera.debug_view
}

append_ui_event :: proc(state: ^State, event: UI_Event) {
	if state == nil || state.event_count >= MAX_UI_EVENTS {
		return
	}
	state.events[state.event_count] = event
	state.event_count += 1
}

mark_ui_event :: proc(
	state: ^State,
	world: ^shared.World,
	kind: UI_Event_Kind,
	entity: shared.Entity,
	position: shared.Vec2 = {},
	part: UI_Event_Part = .Control,
	paint_changed: bool = true,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	entity_index := int(entity.index)
	marked := false
	switch kind {
		case .Activated:
			marked = ecs.mark_ui_activated(world, entity_index)
		case .Changed:
			marked = ecs.mark_ui_changed(world, entity_index, paint_changed)
		case .Submitted:
			marked = ecs.mark_ui_submitted(world, entity_index, paint_changed)
		case .Cancelled:
			marked = ecs.mark_ui_cancelled(world, entity_index)
		case .Dropped:
			return false
	}
	if marked {
		append_ui_event(state, {kind = kind, part = part, entity = entity, position = position})
	}
	return marked
}

ui_events :: proc(state: ^State) -> []UI_Event {
	if state == nil {
		return nil
	}
	return state.events[:state.event_count]
}

publish_ui_events :: proc(state: ^State, world: ^shared.World, start_index: int = 0) {
	if state == nil || world == nil {
		return
	}
	events := ui_events(state)
	if start_index < 0 || start_index > len(events) {
		return
	}
	for event in events[start_index:] {
		entity_index := int(event.entity.index)
		if !ecs.entity_is_alive(world, entity_index) ||
		   world.entities[entity_index].id != event.entity {
			continue
		}
		entity := world.entities[entity_index]
		action_entity, action, payload := ecs.ui_action_for_entity(world, entity_index)
		public_event := shared.UI_Event {
			kind = shared.UI_Event_Kind(event.kind),
			part = shared.UI_Event_Part(event.part),
			origin = entity.origin,
			entity = entity.uuid,
			action_entity = action_entity,
			action = action,
			payload = payload,
			drop_placement = event.drop_placement,
			position = event.position,
		}
		source_index := int(event.source.index)
		if ecs.entity_is_alive(world, source_index) &&
		   world.entities[source_index].id == event.source {
			public_event.drag_source = world.entities[source_index].uuid
		}
		target_index := int(event.target.index)
		if ecs.entity_is_alive(world, target_index) &&
		   world.entities[target_index].id == event.target {
			public_event.drop_target = world.entities[target_index].uuid
		}
		ecs.append_ui_event(world, public_event)
	}
}

init :: proc(state: ^State) -> string {
	state^ = {}
	state.editor_pixel_density = 1
	state.editor_left_sidebar_visible = true
	state.editor_right_sidebar_visible = true
	state.editor_simulation_playing = true
	state.editor_history_clean_valid = true
	state.editor_placement_snap_step = 0.5
	state.editor_rotation_snap_step = math.to_radians(f32(15))
	state.editor_scale_snap_step = 0.1
	state.active_split_handle = -1
	state.active_dock_tab = -1
	state.dock_drop_space_node = -1
	state.dock_drop_space_placement = .None
	state.dock_drop_stack_node = -1
	state.project_canvas_entity_index = -1
	state.font.glyphs = &FONT_GLYPHS
	state.font.ascender = FONT_ASCENDER
	state.font.layer = 0
	state.font.ready = true
	return ""
}

select_font :: proc(state: ^State, name: string) {
	state.font.glyphs = &FONT_GLYPHS
	state.font.ascender = FONT_ASCENDER
	state.font.layer = 0
	if name == "" || state.resource_registry == nil { return }
	handle, found := resources.font_by_name(state.resource_registry, name)
	if !found { return }
	font, alive := resources.get_font(state.resource_registry, handle)
	if !alive || handle.index >= shared.MAX_PROJECT_FONTS { return }
	state.font.glyphs = &font.desc.glyphs
	state.font.ascender = font.desc.ascender
	state.font.layer = f32(handle.index + 1)
}

editor_play :: proc(state: ^State) {
	if state == nil { return }
	if state.editor_simulation_playing && !state.editor_simulation_stopped {
		return
	}
	if state.editor_simulation_stopped {
		state.editor_playback_begin_requested = true
	}
	state.editor_simulation_playing = true
	state.editor_simulation_stopped = false
	state.editor_simulation_step_requested = false
	state.editor_snapshot_valid = false
}

editor_pause :: proc(state: ^State) {
	if state == nil || state.editor_simulation_stopped { return }
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = false
	state.editor_simulation_step_requested = false
	state.editor_snapshot_valid = false
}

editor_stop :: proc(state: ^State) {
	if state == nil || state.editor_simulation_stopped { return }
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_simulation_step_requested = false
	state.editor_playback_begin_requested = false
	state.editor_playback_stop_requested = true
	state.editor_scene_save_requested = false
	state.editor_scene_save_failed = false
	state.editor_scene_revert_failed = false
	state.editor_snapshot_valid = false
}

editor_toggle :: proc(state: ^State) {
	if state == nil {
		return
	}
	opening := !state.editor_visible
	state.editor_visible = opening
	if opening {
		editor_pause(state)
	} else {
		editor_play(state)
		state.editor_light_gizmo_visible = false
	}
	state.editor_snapshot_valid = false
}

editor_save :: proc(state: ^State) {
	if state == nil || !state.editor_simulation_stopped || !state.editor_scene_dirty {
		return
	}
	state.editor_scene_save_requested = true
	state.editor_scene_save_failed = false
	state.editor_scene_revert_failed = false
}

editor_revert :: proc(state: ^State) {
	if state == nil || !state.editor_simulation_stopped || !state.editor_scene_dirty {
		return
	}
	state.editor_scene_revert_requested = true
	state.editor_scene_revert_failed = false
	state.editor_scene_save_failed = false
}

editor_undo :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || !state.editor_simulation_stopped || state.editor_history_cursor <= 0 {
		return false
	}
	return editor_history_apply(state, world, false)
}

editor_redo :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil ||
	   !state.editor_simulation_stopped ||
	   state.editor_history_cursor >= state.editor_history_count {
		return false
	}
	return editor_history_apply(state, world, true)
}

editor_mark_scene_dirty :: proc(state: ^State, entity: ^shared.World_Entity) {
	if state == nil ||
	   entity == nil ||
	   !state.editor_simulation_stopped ||
	   entity.origin != .Scene {
		return
	}
	if state.editor_dirty_entity_lookup == nil {
		state.editor_dirty_entity_lookup = make(map[shared.Entity_UUID]bool)
	}
	if !state.editor_dirty_entity_lookup[entity.uuid] {
		state.editor_dirty_entity_lookup[entity.uuid] = true
		append(&state.editor_dirty_entities, entity.uuid)
	}
	state.editor_scene_dirty = true
	state.editor_scene_save_failed = false
	state.editor_scene_revert_failed = false
}

editor_mark_scene_uuid_dirty :: proc(state: ^State, id: shared.Entity_UUID) {
	if state == nil || !state.editor_simulation_stopped || id == (shared.Entity_UUID{}) {
		return
	}
	if state.editor_dirty_entity_lookup == nil {
		state.editor_dirty_entity_lookup = make(map[shared.Entity_UUID]bool)
	}
	if !state.editor_dirty_entity_lookup[id] {
		state.editor_dirty_entity_lookup[id] = true
		append(&state.editor_dirty_entities, id)
	}
	state.editor_scene_dirty = true
	state.editor_scene_save_failed = false
	state.editor_scene_revert_failed = false
	state.editor_snapshot_valid = false
}

editor_step :: proc(state: ^State) {
	if state == nil || state.editor_simulation_playing || state.editor_simulation_stopped {
		return
	}
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = false
	state.editor_simulation_step_requested = true
	state.editor_snapshot_valid = false
}

consume_playback_begin_request :: proc(state: ^State) -> bool {
	if state == nil || !state.editor_playback_begin_requested {
		return false
	}
	state.editor_playback_begin_requested = false
	return true
}

consume_playback_stop_request :: proc(state: ^State) -> bool {
	if state == nil || !state.editor_playback_stop_requested {
		return false
	}
	state.editor_playback_stop_requested = false
	return true
}

consume_editor_focus_selected_request :: proc(state: ^State) -> bool {
	if state == nil || !state.editor_focus_selected_requested {
		return false
	}
	state.editor_focus_selected_requested = false
	return true
}

editor_selected_uuid :: proc(state: ^State, world: ^shared.World) -> (shared.Entity_UUID, bool) {
	if state == nil || world == nil || !state.editor_has_selection {
		return {}, false
	}
	entity_index := int(state.editor_selected_entity.index)
	if !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].id != state.editor_selected_entity {
		return {}, false
	}
	return world.entities[entity_index].uuid, true
}

editor_entity_selected :: proc(state: ^State, id: shared.Entity_UUID) -> bool {
	if state == nil || id == (shared.Entity_UUID{}) {
		return false
	}
	for selected in state.editor_selected_uuids {
		if selected == id {
			return true
		}
	}
	return false
}

editor_selection_count :: proc(state: ^State) -> int {
	if state == nil {
		return 0
	}
	return len(state.editor_selected_uuids)
}

editor_selection_uuids :: proc(state: ^State) -> []shared.Entity_UUID {
	if state == nil {
		return nil
	}
	return state.editor_selected_uuids[:]
}

editor_selection_changed :: proc(state: ^State) {
	if state == nil {
		return
	}
	state.editor_selection_revision += 1
	state.editor_has_selection = len(state.editor_selected_uuids) > 0
	state.editor_snapshot_valid = false
	state.editor_browser_snapshot_valid = false
	state.editor_inspector_snapshot_valid = false
	state.editor_gizmo_bounds_valid = false
}

editor_sync_selection :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil {
		return
	}
	changed := false
	if len(state.editor_selected_uuids) == 0 && state.editor_has_selection {
		active_index := int(state.editor_selected_entity.index)
		if ecs.entity_is_alive(world, active_index) &&
		   world.entities[active_index].id == state.editor_selected_entity &&
		   world.entities[active_index].origin != .Editor {
			append(&state.editor_selected_uuids, world.entities[active_index].uuid)
			changed = true
		}
	}
	write_index := 0
	for id in state.editor_selected_uuids {
		entity_index, found := ecs.entity_index_by_uuid(world, id)
		if !found || world.entities[entity_index].origin == .Editor {
			changed = true
			continue
		}
		state.editor_selected_uuids[write_index] = id
		write_index += 1
	}
	if write_index != len(state.editor_selected_uuids) {
		resize(&state.editor_selected_uuids, write_index)
	}
	if write_index > 0 {
		active_uuid := state.editor_selected_uuids[write_index - 1]
		active_index, _ := ecs.entity_index_by_uuid(world, active_uuid)
		active := world.entities[active_index].id
		if state.editor_selected_entity != active {
			state.editor_selected_entity = active
			changed = true
		}
	} else if state.editor_has_selection {
		state.editor_selected_entity = {}
		changed = true
	}
	if changed {
		editor_selection_changed(state)
	} else {
		state.editor_has_selection = write_index > 0
	}
}

editor_world_restored :: proc(
	state: ^State,
	world: ^shared.World,
	selected_uuid: shared.Entity_UUID = {},
	had_selection: bool = false,
) {
	if state == nil || world == nil {
		return
	}
	if len(state.editor_selected_uuids) == 0 &&
	   had_selection &&
	   selected_uuid != (shared.Entity_UUID{}) {
		append(&state.editor_selected_uuids, selected_uuid)
	}
	editor_sync_selection(state, world)
	state.editor_snapshot_valid = false
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_light_gizmo_active = false
	state.editor_light_gizmo_captures_pointer = false
	state.editor_transport_visual_valid = false
	state.editor_sidebar_visual_valid = false
	clear_input_focus(state)
}

consume_scene_save_request :: proc(state: ^State) -> bool {
	if state == nil || !state.editor_scene_save_requested {
		return false
	}
	state.editor_scene_save_requested = false
	return true
}

consume_scene_revert_request :: proc(state: ^State) -> bool {
	if state == nil || !state.editor_scene_revert_requested {
		return false
	}
	state.editor_scene_revert_requested = false
	return true
}

editor_request_resource_reimport :: proc(
	state: ^State,
	id: shared.Resource_UUID,
	all: bool = false,
) {
	if state == nil || (!all && id == (shared.Resource_UUID{})) {
		return
	}
	state.editor_resource_reimport_requested = true
	state.editor_resource_reimport_all_requested = all
	state.editor_resource_reimport_id = id
	state.editor_resource_reimport_result_id = id
	state.editor_resource_reimport_failed = false
	delete(state.editor_resource_reimport_message)
	state.editor_resource_reimport_message = ""
}

consume_resource_reimport_request :: proc(
	state: ^State,
) -> (
	id: shared.Resource_UUID,
	all: bool,
	requested: bool,
) {
	if state == nil || !state.editor_resource_reimport_requested {
		return
	}
	state.editor_resource_reimport_requested = false
	return state.editor_resource_reimport_id, state.editor_resource_reimport_all_requested, true
}

complete_resource_reimport :: proc(state: ^State, message: string) {
	if state == nil {
		return
	}
	state.editor_resource_reimport_failed = message != ""
	delete(state.editor_resource_reimport_message)
	state.editor_resource_reimport_message, _ = strings.clone(message)
	state.editor_inspector_snapshot_valid = false
	state.editor_browser_snapshot_valid = false
	state.editor_snapshot_valid = false
}

editor_recompute_scene_dirty :: proc(state: ^State) {
	if state == nil || !state.editor_simulation_stopped {
		return
	}
	state.editor_scene_dirty =
		!state.editor_history_clean_valid ||
		state.editor_history_cursor != state.editor_history_clean_cursor
	if !state.editor_scene_dirty {
		clear(&state.editor_dirty_entities)
		clear(&state.editor_dirty_entity_lookup)
		clear(&state.editor_dirty_resources)
		clear(&state.editor_dirty_resource_lookup)
		state.editor_scene_save_failed = false
		state.editor_scene_revert_failed = false
	}
	state.editor_snapshot_valid = false
}

complete_scene_save :: proc(state: ^State, ok: bool) {
	if state == nil {
		return
	}
	state.editor_scene_save_failed = !ok
	if ok {
		state.editor_scene_dirty = false
		clear(&state.editor_dirty_entities)
		clear(&state.editor_dirty_entity_lookup)
		clear(&state.editor_dirty_resources)
		clear(&state.editor_dirty_resource_lookup)
		state.editor_history_clean_cursor = state.editor_history_cursor
		state.editor_history_clean_valid = true
		state.editor_scene_revert_failed = false
	}
	state.editor_snapshot_valid = false
}

complete_scene_revert :: proc(state: ^State, ok: bool) {
	if state == nil {
		return
	}
	state.editor_scene_revert_failed = !ok
	if ok {
		editor_history_clear(state)
		state.editor_has_resource_selection = false
		state.editor_scene_dirty = false
		clear(&state.editor_dirty_entities)
		clear(&state.editor_dirty_entity_lookup)
		clear(&state.editor_dirty_resources)
		clear(&state.editor_dirty_resource_lookup)
		state.editor_scene_save_failed = false
	}
	state.editor_snapshot_valid = false
}

consume_simulation_delta :: proc(state: ^State, delta_seconds: f32) -> (f32, bool) {
	if state == nil || state.editor_simulation_playing {
		return delta_seconds, true
	}
	if state.editor_simulation_step_requested {
		state.editor_simulation_step_requested = false
		return 1.0 / 60.0, true
	}
	return 0, false
}

editor_play_mode_active :: proc(state: ^State) -> bool {
	return state != nil && !state.editor_simulation_stopped
}

destroy :: proc(state: ^State) {
	if state == nil { return }
	editor_history_clear(state)
	delete(state.input_original_text)
	delete(state.editor_dirty_entities)
	delete(state.editor_dirty_entity_lookup)
	delete(state.editor_dirty_resources)
	delete(state.editor_dirty_resource_lookup)
	delete(state.editor_selected_uuids)
	delete(state.editor_gizmo_drag_selection)
	delete(state.editor_collapsed_entities)
	delete(state.editor_resource_reimport_message)
	if state.editor_resource_browser_initialized && state.editor_resource_browser_ready {
		file_browser.destroy(&state.editor_resource_browser)
	}
	delete(state.editor_resource_browser_error)
	state^ = {}
}

remove_ui_node :: proc(state: ^State, node_index: int) {
	if state == nil || node_index < 0 || node_index >= state.node_count {
		return
	}
	for index in node_index ..< state.node_count - 1 {
		state.nodes[index] = state.nodes[index + 1]
	}
	state.node_count -= 1
	state.nodes[state.node_count] = {}
}

insert_ui_node :: proc(state: ^State, entity_index: int) -> int {
	insert_index := state.node_count
	for node, node_index in state.nodes[:state.node_count] {
		if int(node.entity.index) > entity_index {
			insert_index = node_index
			break
		}
	}
	for node_index := state.node_count; node_index > insert_index; node_index -= 1 {
		state.nodes[node_index] = state.nodes[node_index - 1]
	}
	state.node_count += 1
	state.nodes[insert_index] = {}
	return insert_index
}

sync_ui_structure :: proc(state: ^State, world: ^shared.World) -> string {
	world_changed := !state.ui_structure_synced || state.ui_world_uuid != world.instance_uuid
	if world_changed {
		state.node_count = 0
		state.ui_world_uuid = world.instance_uuid
		state.ui_layout_valid = false
		clear_input_focus(state)
		state.active_entity = {}
		state.has_active_entity = false
		state.editor_ui_active_entity = {}
		state.editor_ui_has_active_entity = false
		state.active_split_handle = -1
		state.split_previous_primary_down = false
		state.editor_split_previous_primary_down = false
		state.active_dock_tab = -1
		state.dock_previous_primary_down = false
		state.editor_dock_previous_primary_down = false
		state.dock_dragging = false
		state.dock_drop_space_node = -1
		state.dock_drop_space_placement = .None
		state.dock_drop_stack_node = -1
		state.dock_drop_stack_target = {}
		state.dock_drop_stack_placement = .None
		for entity, entity_index in world.entities {
			if entity.alive && entity.ui_layout_index >= 0 {
				ecs.mark_ui_entity_dirty(world, entity_index)
			}
		}
	}
	if world_changed || state.ui_editor_visible != state.editor_visible {
		if state.editor_visible {
			for component in world.editor_uis {
				entity_index := component.entity_index
				if entity_index < 0 || entity_index >= len(world.entities) {
					continue
				}
				entity := world.entities[entity_index]
				if entity.alive && entity.origin == .Editor && entity.ui_layout_index >= 0 {
					ecs.mark_ui_entity_dirty(world, entity_index)
				}
			}
		} else {
			for node in state.nodes[:state.node_count] {
				if node.origin == .Editor {
					ecs.mark_ui_entity_dirty(world, int(node.entity.index))
				}
			}
		}
		state.ui_editor_visible = state.editor_visible
	}
	if state.ui_structure_synced &&
	   state.ui_structure_revision == world.ui_structure_revision &&
	   len(world.ui_dirty_entities) == 0 {
		return ""
	}

	dirty_cursor := 0
	hierarchy_changed := world_changed
	viewport_membership_changed := world_changed
	canvas_membership_changed := world_changed
	for dirty_cursor < len(world.ui_dirty_entities) {
		entity_index := world.ui_dirty_entities[dirty_cursor]
		dirty_cursor += 1
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := &world.entities[entity_index]
		entity.ui_dirty = false
		node_index := find_node_by_entity_index(state, entity_index)
		eligible :=
			entity.alive &&
			(entity.origin != .Editor || state.editor_visible) &&
			entity.ui_layout_index >= 0 &&
			entity.ui_layout_index < len(world.ui_layouts) &&
			!ui_entity_or_ancestor_hidden(world, entity_index)
		if !eligible {
			if node_index >= 0 {
				if state.nodes[node_index].canvas_index >= 0 {
					canvas_membership_changed = true
				}
				remove_ui_node(state, node_index)
				hierarchy_changed = true
			}
			continue
		}
		if node_index >= 0 && state.nodes[node_index].entity != entity.id {
			remove_ui_node(state, node_index)
			node_index = -1
			hierarchy_changed = true
		}
		if node_index < 0 {
			if state.node_count >= MAX_NODES {
				return "too many UI entities"
			}
			node_index = insert_ui_node(state, entity_index)
			hierarchy_changed = true
		}
		_ = ecs.ensure_ui_state(world, entity_index)
		node := &state.nodes[node_index]
		had_viewport := node.entity == entity.id && node.viewport_index >= 0
		had_canvas := node.entity == entity.id && node.canvas_index >= 0
		node.viewport_layer = -1
		node.entity = entity.id
		node.origin = entity.origin
		node.editor_role = .None
		if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
			node.editor_role = world.editor_uis[entity.editor_ui_index].role
		}
		node.layout_index = entity.ui_layout_index
		node.canvas_index = entity.ui_canvas_index
		if had_canvas != (node.canvas_index >= 0) {
			canvas_membership_changed = true
		}
		node.hstack_index = entity.ui_hstack_index
		node.vstack_index = entity.ui_vstack_index
		node.scroll_area_index = entity.ui_scroll_area_index
		node.panel_index = entity.ui_panel_index
		node.dock_space_index = entity.ui_dock_space_index
		node.dock_item_index = entity.ui_dock_item_index
		node.table_index = entity.ui_table_index
		node.list_index = entity.ui_list_index
		node.progress_index = entity.ui_progress_index
		node.viewport_index = entity.ui_viewport_index
		if had_viewport != (node.viewport_index >= 0) {
			viewport_membership_changed = true
		}
		node.icon_index = entity.ui_icon_index
		node.text_index = entity.ui_text_index
		node.button_index = entity.ui_button_index
		node.input_index = entity.ui_input_index
		node.checkbox_index = entity.ui_checkbox_index
		node.color_picker_index = entity.ui_color_picker_index
		parent_entity_index := find_parent_entity(
			world,
			world.ui_layouts[entity.ui_layout_index].parent,
			entity.origin,
		)
		if node.parent_entity_index != parent_entity_index {
			hierarchy_changed = true
		}
		node.parent_entity_index = parent_entity_index
	}
	if hierarchy_changed {
		if err := rebuild_ui_node_hierarchy(state); err != "" {
			return err
		}
	}
	if hierarchy_changed || viewport_membership_changed {
		rebuild_viewport_node_indices(state)
	}
	if hierarchy_changed || canvas_membership_changed {
		state.project_canvas_entity_index = -1
		state.project_canvas_valid = false
		for node in state.nodes[:state.node_count] {
			if node.origin == .Editor ||
			   node.canvas_index < 0 ||
			   node.canvas_index >= len(world.ui_canvases) {
				continue
			}
			state.project_canvas_entity_index = int(node.entity.index)
			state.project_canvas = world.ui_canvases[node.canvas_index]
			state.project_canvas_valid = true
			break
		}
	}
	clear(&world.ui_dirty_entities)
	state.ui_structure_revision = world.ui_structure_revision
	state.ui_structure_synced = true
	state.ui_structure_sync_count += 1
	return ""
}

rebuild_viewport_node_indices :: proc(state: ^State) {
	state.viewport_node_count = 0
	for &node, node_index in state.nodes[:state.node_count] {
		if node.viewport_index < 0 {
			continue
		}
		state.viewport_node_indices[state.viewport_node_count] = node_index
		state.viewport_node_count += 1
	}
}

UI_Paint_Signature_Key :: struct {
	world_uuid: shared.Entity_UUID,
	editor: bool,
	has_focused_input: bool,
	focused_input: shared.Entity,
	input_cursor, input_anchor: int,
	input_scroll_x: f32,
	input_blink_phase: int,
	input_valid: bool,
	editor_pixel_density: f32,
	world_paint_revision: u64,
	state_paint_revision: u64,
}

ui_paint_signature_add_memory :: proc(signature: u64, data: rawptr, size: int) -> u64 {
	if data == nil || size <= 0 {
		return signature
	}
	bytes := (cast([^]byte)data)[:size]
	return hash.fnv64a(bytes, signature)
}

ui_paint_input_signature :: proc(state: ^State, world: ^shared.World, editor: bool) -> u64 {
	focused_in_domain := state.has_focused_input && state.focused_input_editor == editor
	key := UI_Paint_Signature_Key {
		world_uuid = state.ui_world_uuid,
		editor = editor,
		has_focused_input = focused_in_domain,
	}
	if focused_in_domain {
		key.focused_input = state.focused_input
		key.input_cursor = state.input_cursor
		key.input_anchor = state.input_anchor
		key.input_scroll_x = state.input_scroll_x
		key.input_blink_phase = int(state.input_blink_elapsed * 2) % 2
		key.input_valid = state.input_valid
	}
	if editor {
		key.editor_pixel_density = state.editor_pixel_density
		key.world_paint_revision = world.ui_editor_paint_revision
		key.state_paint_revision = state.ui_editor_paint_revision
	} else {
		key.world_paint_revision = world.ui_project_paint_revision
		key.state_paint_revision = state.ui_project_paint_revision
	}
	signature := hash.fnv64a((cast([^]byte)&key)[:size_of(key)])
	if state.resource_registry != nil {
		icon_set_revision := state.resource_registry.icon_set_revision
		signature = ui_paint_signature_add_memory(
			signature,
			&icon_set_revision,
			size_of(icon_set_revision),
		)
		for &font in state.resource_registry.fonts {
			alive := u32(0)
			if font.alive {
				alive = 1
			}
			font_key := [3]u32{font.generation, font.version, alive}
			signature = ui_paint_signature_add_memory(signature, &font_key, size_of(font_key))
		}
	}
	return signature
}

reconcile :: proc(
	state: ^State,
	world: ^shared.World,
	width, height: f32,
	pointer: Pointer_Input = {},
	drawable_width: f32 = 0,
	drawable_height: f32 = 0,
	delta_seconds: f32 = 1.0 / 60.0,
	keyboard: Keyboard_Input = {},
	resource_registry: ^resources.Registry = nil,
	project_root: string = "",
) -> string {
	if state == nil || world == nil { return "UI state or world is unavailable" }
	state.event_count = 0
	world.ui_events.latest_pass_after_sequence = ecs.ui_event_latest_sequence(world)
	state.editor_selection_toggle_modifier = keyboard.shift
	editor_ui_handle_shortcuts(state, world, keyboard)
	when ODIN_TEST {
		state.layout_node_visit_count = 0
		state.layout_child_edge_visit_count = 0
		state.paint_node_visit_count = 0
		state.paint_child_edge_visit_count = 0
	}
	for entity_id in world.ui_transient_state_entities {
		entity_index := int(entity_id.index)
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive || entity.id.generation != entity_id.generation {
			continue
		}
		state_index := entity.ui_state_index
		if state_index < 0 || state_index >= len(world.ui_states) {
			continue
		}
		interaction := &world.ui_states[state_index]
		interaction.activated = false
		interaction.changed = false
		interaction.submitted = false
		interaction.cancelled = false
	}
	clear(&world.ui_transient_state_entities)
	surface_width := drawable_width; if surface_width <= 0 { surface_width = width }
	surface_height := drawable_height; if surface_height <= 0 { surface_height = height }
	if !state.font.ready { if err := init(state); err != "" { return err } }
	state.resource_registry = resource_registry
	if state.editor_visible && !state.editor_resource_browser_initialized && project_root != "" {
		state.editor_resource_browser_initialized = true
		resource_root, join_err := filepath.join({project_root, shared.PROJECT_RESOURCES_DIR})
		if join_err == nil {
			filter := file_browser.default_filter()
			filter.extensions = []string{".resource.toml"}
			browser_err := file_browser.init(&state.editor_resource_browser, resource_root, filter)
			delete(resource_root)
			if browser_err == "" {
				state.editor_resource_browser_ready = true
				state.editor_browser_snapshot_valid = false
			} else {
				delete(state.editor_resource_browser_error)
				state.editor_resource_browser_error, _ = strings.clone(browser_err)
			}
		} else {
			state.editor_resource_browser_error = "failed to resolve project resource directory"
		}
	}
	editor_scale := max(state.editor_pixel_density, 1)
	editor_width := surface_width / editor_scale
	editor_height := surface_height / editor_scale
	reconcile_editor_ui_world(state, world)
	if err := sync_ui_structure(state, world); err != "" { return err }
	if state.project_canvas_valid {
		entity_index := state.project_canvas_entity_index
		if entity_index >= 0 && entity_index < len(world.entities) {
			canvas_index := world.entities[entity_index].ui_canvas_index
			if canvas_index >= 0 && canvas_index < len(world.ui_canvases) {
				state.project_canvas = world.ui_canvases[canvas_index]
			} else {
				state.project_canvas_valid = false
				state.project_canvas_entity_index = -1
			}
		}
	}
	project_transform := project_canvas_transform(
		state,
		surface_width,
		surface_height,
		width,
		height,
	)
	project_layout := project_transform.logical_viewport
	editor_layout := Rect{0, 0, editor_width, editor_height}
	fresh_pointer_press :=
		pointer.available &&
		pointer.primary_down &&
		!state.previous_primary_down &&
		!state.editor_previous_primary_down
	if !state.editor_visible && state.has_focused_input && state.focused_input_editor {
		blur_input_edit(state, world)
	}
	validate_focused_editor_input(state, world)
	project_pointer := project_pointer_input(
		state,
		pointer,
		width,
		height,
		surface_width,
		surface_height,
	); if editor_world_tool_captures_pointer(state) {
		project_pointer = {}
	}
	editor_pointer := pointer
	if editor_pointer.available { editor_pointer.position.x /= editor_scale; editor_pointer.position.y /= editor_scale }
	if editor_world_tool_captures_pointer(state) || state.editor_pointer_activation_consumed {
		editor_pointer = editor_consumed_pointer_input(editor_pointer)
	}
	layout_project :=
		!state.ui_layout_valid ||
		state.ui_project_layout_revision != world.ui_project_layout_revision ||
		state.ui_project_viewport != project_layout ||
		fresh_pointer_press
	layout_editor :=
		!state.ui_layout_valid ||
		state.ui_editor_layout_revision != world.ui_editor_layout_revision ||
		state.ui_editor_viewport != editor_layout ||
		fresh_pointer_press
	if layout_project || layout_editor {
		if err := layout_all(
			state,
			world,
			project_layout,
			editor_layout,
			layout_project,
			layout_editor,
		); err != "" {
			return err
		}
	}
	project_dock_changed, project_dock_captured := update_dock_interaction(
		state,
		world,
		project_pointer,
		false,
	)
	if project_dock_changed {
		if err := sync_ui_structure(state, world); err != "" {
			return err
		}
		if err := layout_all(state, world, project_layout, editor_layout); err != "" {
			return err
		}
	}
	editor_dock_changed, editor_dock_captured := update_dock_interaction(
		state,
		world,
		editor_pointer,
		true,
	)
	if editor_dock_changed {
		if err := sync_ui_structure(state, world); err != "" {
			return err
		}
		if err := layout_all(state, world, project_layout, editor_layout); err != "" {
			return err
		}
	}
	if project_dock_captured {
		project_pointer = {}
	}
	if editor_dock_captured {
		editor_pointer = {}
	}
	if update_split_interaction(
		state,
		project_pointer,
		false,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }; _ = update_split_interaction(state, project_pointer, false) }
	if update_split_interaction(state, editor_pointer, true) {
		if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }
		_ = update_split_interaction(state, editor_pointer, true)
	}
	state.pointer_cursor = split_pointer_cursor(state)
	if state.pointer_cursor == .Default {
		for tab in state.dock_tabs[:state.dock_tab_count] {
			if tab.hovered ||
			   state.active_dock_tab >= 0 &&
				   state.active_dock_tab < state.dock_tab_count &&
				   state.dock_tabs[state.active_dock_tab].item_node == tab.item_node {
				state.pointer_cursor = .Pointer
				if dock_item_movable(world, state.nodes[tab.item_node]) {
					state.pointer_cursor = .Move
				}
				break
			}
		}
	}
	if state.active_split_handle >= 0 { project_pointer = {}; editor_pointer = {} }
	project_viewport_wheel := update_viewport_interaction(state, world, project_pointer, false)
	editor_viewport_wheel := update_viewport_interaction(state, world, editor_pointer, true)
	project_scroll_pointer := project_pointer
	if project_viewport_wheel {
		project_scroll_pointer.wheel_y = 0
	}
	editor_scroll_pointer := editor_pointer
	if editor_viewport_wheel {
		editor_scroll_pointer.wheel_y = 0
	}
	if update_scroll_areas(
		state,
		world,
		project_scroll_pointer,
		delta_seconds,
		false,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err } }
	if update_scroll_areas(
		state,
		world,
		editor_scroll_pointer,
		delta_seconds,
		true,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err } }
	project_press_started := pointer_press_started(project_pointer, state.previous_primary_down)
	project_press_released := pointer_press_released(project_pointer, state.previous_primary_down)
	editor_press_started := pointer_press_started(
		editor_pointer,
		state.editor_previous_primary_down,
	)
	editor_press_released := pointer_press_released(
		editor_pointer,
		state.editor_previous_primary_down,
	)
	project_pressed, project_pressed_ok, project_released, project_released_ok, project_released_inside, project_hit :=
		update_interaction(state, project_pointer, false)
	pressed, pressed_ok, released, released_ok, released_inside, editor_hit := update_interaction(
		state,
		editor_pointer,
		true,
	)
	panel_changed := false
	project_stack_drag_armed := false
	editor_stack_drag_armed := false
	if project_press_started && project_pressed_ok {
		action_drag_begin(state, world, project_pressed, project_pointer.position, false)
		list_drag_begin(state, world, project_pressed, project_pointer.position, false)
		project_stack_drag_armed = stack_drag_begin(
			state,
			world,
			project_pressed,
			project_pointer.position,
			false,
		)
	}
	if editor_press_started && pressed_ok {
		action_drag_begin(state, world, pressed, editor_pointer.position, true)
		list_drag_begin(state, world, pressed, editor_pointer.position, true)
		editor_stack_drag_armed = stack_drag_begin(
			state,
			world,
			pressed,
			editor_pointer.position,
			true,
		)
	}
	list_drag_update(state, world, project_pointer, project_press_released, false)
	list_drag_update(state, world, editor_pointer, editor_press_released, true)
	action_drag_update(state, world, project_pointer, project_press_released, false)
	action_drag_update(state, world, editor_pointer, editor_press_released, true)
	stack_layout_changed, stack_title_clicked := stack_drag_update(
		state,
		world,
		project_pointer,
		project_press_released,
		false,
	)
	panel_changed = stack_layout_changed || stack_title_clicked || panel_changed
	stack_layout_changed, stack_title_clicked = stack_drag_update(
		state,
		world,
		editor_pointer,
		editor_press_released,
		true,
	)
	panel_changed = stack_layout_changed || stack_title_clicked || panel_changed
	if drag_cursor := workspace_drag_pointer_cursor(state); drag_cursor != .Default {
		state.pointer_cursor = drag_cursor
	}
	if drag_cursor := action_drag_pointer_cursor(state); drag_cursor != .Default {
		state.pointer_cursor = drag_cursor
	}
	update_color_picker_interaction(
		state,
		world,
		project_pointer,
		project_pressed,
		project_press_started,
		project_press_released,
		false,
	)
	update_color_picker_interaction(
		state,
		world,
		editor_pointer,
		pressed,
		editor_press_started,
		editor_press_released,
		true,
	)
	if state.pointer_cursor == .Default {
		state.pointer_cursor = numeric_input_pointer_cursor(state, world)
	}
	if state.pointer_cursor == .Default {
		state.pointer_cursor = control_pointer_cursor(
			state,
			world,
			project_hit,
			project_pointer.position,
		)
	}
	if state.pointer_cursor == .Default {
		state.pointer_cursor = control_pointer_cursor(
			state,
			world,
			editor_hit,
			editor_pointer.position,
		)
	}
	sync_ui_interaction_states(state, world)
	if pressed_ok && !entity_is_ui_button(world, pressed) {
		_ = mark_ui_event(state, world, .Activated, pressed, editor_pointer.position)
		panel_changed = handle_popup_press(state, world, pressed) || panel_changed
		list_changed := handle_list_press(state, world, pressed)
		if list_changed {
			panel_changed = close_selection_popup(state, world, pressed) || panel_changed
		}
		editor_ui_prepare_input_focus(state, world, int(pressed.index))
		handle_input_press(state, world, pressed, editor_pointer.position)
		checkbox_changed := handle_checkbox_press(state, world, pressed)
		panel_changed = checkbox_changed || panel_changed
		if !editor_stack_drag_armed {
			panel_title_changed := handle_panel_title_press(
				state,
				world,
				pressed,
				editor_pointer.position,
			)
			panel_changed = panel_title_changed || panel_changed
		}
	}
	if project_pressed_ok && !entity_is_ui_button(world, project_pressed) {
		_ = mark_ui_event(state, world, .Activated, project_pressed, project_pointer.position)
		panel_changed = handle_popup_press(state, world, project_pressed) || panel_changed
		list_changed := handle_list_press(state, world, project_pressed)
		if list_changed {
			panel_changed = close_selection_popup(state, world, project_pressed) || panel_changed
		}
		handle_input_press(state, world, project_pressed, project_pointer.position)
		checkbox_changed := handle_checkbox_press(state, world, project_pressed)
		panel_changed = checkbox_changed || panel_changed
		if !project_stack_drag_armed {
			panel_title_changed := handle_panel_title_press(
				state,
				world,
				project_pressed,
				project_pointer.position,
			)
			panel_changed = panel_title_changed || panel_changed
		}
	}
	if released_ok && entity_is_ui_button(world, released) {
		if released_inside {
			_ = mark_ui_event(state, world, .Activated, released, editor_pointer.position)
			panel_changed = handle_popup_press(state, world, released) || panel_changed
			list_changed := handle_list_press(state, world, released)
			if list_changed {
				panel_changed = close_selection_popup(state, world, released) || panel_changed
			}
		} else {
			_ = mark_ui_event(state, world, .Cancelled, released, editor_pointer.position)
		}
	}
	if project_released_ok && entity_is_ui_button(world, project_released) {
		if project_released_inside {
			_ = mark_ui_event(state, world, .Activated, project_released, project_pointer.position)
			panel_changed = handle_popup_press(state, world, project_released) || panel_changed
			list_changed := handle_list_press(state, world, project_released)
			if list_changed {
				panel_changed =
					close_selection_popup(state, world, project_released) || panel_changed
			}
		} else {
			_ = mark_ui_event(state, world, .Cancelled, project_released, project_pointer.position)
		}
	}
	if editor_press_started && !pressed_ok {
		panel_changed = close_popups_on_escape(state, world, true, false) || panel_changed
	}
	if project_press_started && !project_pressed_ok {
		panel_changed = close_popups_on_escape(state, world, false, true) || panel_changed
	}
	if keyboard.escape {
		panel_changed = close_popups_on_escape(state, world) || panel_changed
	}
	if editor_action_requested(keyboard, .Toggle_Editor) {
		panel_changed = close_popups_on_escape(state, world, true, false) || panel_changed
	}
	publish_ui_events(state, world)
	published_event_count := state.event_count
	panel_changed =
		editor_ui_consume_events(state, world, world.ui_events.latest_pass_after_sequence) ||
		panel_changed
	editor_ui_update_transport(state, world)
	editor_box_select_update(state, editor_pointer, editor_scale)
	sync_ui_interaction_states(state, world)
	if panel_changed {
		if err := sync_ui_structure(state, world); err != "" {
			return err
		}
		if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }
	}
	if editor_press_started &&
	   !pressed_ok &&
	   state.has_focused_input &&
	   state.focused_input_editor {
		blur_input_edit(state, world)
	}
	if project_press_started &&
	   !project_pressed_ok &&
	   state.has_focused_input &&
	   !state.focused_input_editor {
		blur_input_edit(state, world)
	}
	editor_save_shortcut :=
		state.editor_visible &&
		(!state.has_focused_input || state.focused_input_editor) &&
		editor_action_requested(keyboard, .Save)
	editor_history_shortcut :=
		state.editor_visible &&
		(!state.has_focused_input || state.focused_input_editor) &&
		(editor_action_requested(keyboard, .Undo) || editor_action_requested(keyboard, .Redo))
	input_event_entity_index := -1
	if state.has_focused_input {
		input_event_entity_index = int(state.focused_input.index)
	}
	editor_save_handled :=
		editor_save_shortcut && editor_ui_handle_save_shortcut(state, world, keyboard)
	editor_history_handled :=
		!editor_save_handled &&
		editor_history_shortcut &&
		editor_ui_handle_history_shortcut(state, world, keyboard)
	if !editor_save_handled && !editor_history_handled {
		update_focused_input(state, world, keyboard, delta_seconds)
		scrub_pointer := project_pointer
		if state.focused_input_editor {
			scrub_pointer = editor_pointer
		}
		update_input_scrub(state, world, scrub_pointer, keyboard)
	} else {
		input_event_entity_index = -1
	}
	sync_ui_interaction_states(state, world)
	if input_event_entity_index >= 0 {
		editor_ui_consume_input_state(state, world, input_event_entity_index)
	}
	editor_sync_selection(state, world)
	if state.editor_visible {
		state.editor_snapshot_elapsed += max(delta_seconds, 0)
		system_profile_changed :=
			state.system_profile != nil &&
			state.editor_system_profile_revision != state.system_profile.revision
		performance_diagnostics_changed :=
			state.performance_diagnostics != nil &&
			state.editor_performance_diagnostics_revision != state.performance_diagnostics.revision
		if performance_diagnostics_changed && !state.input_scrubbing {
			editor_ui_refresh_performance_diagnostics(state, world)
		}
		if system_profile_changed && !state.input_scrubbing {
			editor_ui_refresh_system_profile(state, world)
		}
		selection_changed :=
			state.editor_snapshot_has_selection != state.editor_has_selection ||
			(state.editor_has_selection &&
					state.editor_snapshot_selected_entity != state.editor_selected_entity)
		snapshot_due :=
			!state.editor_snapshot_valid ||
			state.editor_snapshot_elapsed >= EDITOR_SNAPSHOT_INTERVAL
		if selection_changed || (!state.input_scrubbing && snapshot_due) {
			refresh_editor_ecs_snapshot(state, world)
		}
	}
	validate_focused_editor_input(state, world)
	state.editor_snapshot_was_visible = state.editor_visible
	collect_viewport_surfaces(
		state,
		world,
		surface_width,
		surface_height,
		width,
		height,
		editor_scale,
	)
	project_paint_signature := ui_paint_input_signature(state, world, false)
	editor_paint_signature := ui_paint_input_signature(state, world, true)
	rebuild_project_paint :=
		!state.project_paint_signature_valid ||
		state.project_paint_signature != project_paint_signature
	rebuild_editor_paint :=
		!state.editor_paint_signature_valid ||
		state.editor_paint_signature != editor_paint_signature
	if rebuild_project_paint {
		state.paint_count = 0
		for i in 0 ..< state.node_count {
			if state.nodes[i].origin != .Editor && state.nodes[i].parent_entity_index < 0 {
				if err := paint_node(state, world, i, 0); err != "" { return err }
			}
		}
		if err := append_split_handles(state, false); err != "" { return err }
		state.editor_paint_start = state.paint_count
		state.project_paint_signature = project_paint_signature
		state.project_paint_signature_valid = true
		state.project_paint_output_revision += 1
		if state.project_paint_output_revision == 0 {
			state.project_paint_output_revision = 1
		}
	} else {
		state.paint_count = state.editor_paint_start
	}
	if state.editor_visible {
		if rebuild_editor_paint {
			for i in 0 ..< state.node_count {
				if state.nodes[i].origin == .Editor && state.nodes[i].parent_entity_index < 0 {
					if err := paint_node(state, world, i, 0); err != "" { return err }
				}
			}
			if err := append_split_handles(state, true); err != "" { return err }
			if editor_scale != 1 {
				for i in state.editor_paint_start ..< state.paint_count {
					scale_paint_command(&state.paint[i], editor_scale)
				}
			}
			state.editor_paint_end = state.paint_count
			state.editor_paint_cache_count = state.editor_paint_end - state.editor_paint_start
			copy(
				state.editor_paint_cache[:state.editor_paint_cache_count],
				state.paint[state.editor_paint_start:state.editor_paint_end],
			)
			state.editor_paint_signature = editor_paint_signature
			state.editor_paint_signature_valid = true
			state.editor_paint_output_revision += 1
			if state.editor_paint_output_revision == 0 {
				state.editor_paint_output_revision = 1
			}
		} else {
			if state.editor_paint_start + state.editor_paint_cache_count > MAX_PAINT_COMMANDS {
				return "too many retained editor UI paint commands"
			}
			copy(
				state.paint[state.editor_paint_start:state.editor_paint_start +
				state.editor_paint_cache_count],
				state.editor_paint_cache[:state.editor_paint_cache_count],
			)
			state.paint_count = state.editor_paint_start + state.editor_paint_cache_count
			state.editor_paint_end = state.paint_count
		}
	} else {
		editor_output_changed := state.editor_paint_end != state.paint_count
		state.editor_paint_end = state.paint_count
		state.editor_paint_signature_valid = false
		if editor_output_changed {
			state.editor_paint_output_revision += 1
			if state.editor_paint_output_revision == 0 {
				state.editor_paint_output_revision = 1
			}
		}
	}
	publish_ui_events(state, world, published_event_count)
	state.editor_pointer_activation_consumed = false
	return ""
}

collect_viewport_surfaces :: proc(
	state: ^State,
	world: ^shared.World,
	surface_width, surface_height, project_width, project_height, editor_scale: f32,
) {
	state.viewport_surface_count = 0
	state.thumbnail_surface_count = 0
	for node_index in state.viewport_node_indices[:state.viewport_node_count] {
		node := &state.nodes[node_index]
		node.viewport_layer = -1
	}
	project_transform := project_canvas_transform(
		state,
		surface_width,
		surface_height,
		project_width,
		project_height,
	)
	// Live targets are reserved for interactive surfaces. Passive resource
	// previews are immutable thumbnail requests served by the renderer cache.
	for interactive_pass in 0 ..< 1 {
		interactive := true
		for node_index in state.viewport_node_indices[:state.viewport_node_count] {
			node := &state.nodes[node_index]
			if !node.laid_out ||
			   node.viewport_index < 0 ||
			   node.viewport_index >= len(world.ui_viewports) ||
			   world.ui_viewports[node.viewport_index].interactive != interactive {
				continue
			}
			if state.viewport_surface_count >= MAX_EMBEDDED_VIEWPORTS {
				break
			}
			rect := node.rect
			clip := node.clip
			has_clip := node.has_clip
			if node.origin == .Editor {
				rect = {
					rect.x * editor_scale,
					rect.y * editor_scale,
					rect.width * editor_scale,
					rect.height * editor_scale,
				}
				clip = {
					clip.x * editor_scale,
					clip.y * editor_scale,
					clip.width * editor_scale,
					clip.height * editor_scale,
				}
			} else {
				rect = {
					project_transform.viewport.x + rect.x * project_transform.scale.x,
					project_transform.viewport.y + rect.y * project_transform.scale.y,
					rect.width * project_transform.scale.x,
					rect.height * project_transform.scale.y,
				}
				clip = {
					project_transform.viewport.x + clip.x * project_transform.scale.x,
					project_transform.viewport.y + clip.y * project_transform.scale.y,
					clip.width * project_transform.scale.x,
					clip.height * project_transform.scale.y,
				}
				if has_clip {
					clip = rect_intersection(clip, project_transform.clip)
				} else {
					clip = project_transform.clip
					has_clip = true
				}
			}
			if has_clip {
				rect = rect_intersection(rect, clip)
			}
			if rect.width <= 0 || rect.height <= 0 {
				continue
			}
			state.viewport_surfaces[state.viewport_surface_count] = {
				entity = node.entity,
				rect = rect,
				clip = clip,
				has_clip = has_clip,
				component = world.ui_viewports[node.viewport_index],
				editor = node.origin == .Editor,
			}
			node.viewport_layer = state.viewport_surface_count
			state.viewport_surface_count += 1
		}
	}
	for node_index in state.viewport_node_indices[:state.viewport_node_count] {
		node := &state.nodes[node_index]
		if !node.laid_out ||
		   node.viewport_index < 0 ||
		   node.viewport_index >= len(world.ui_viewports) {
			continue
		}
		component := world.ui_viewports[node.viewport_index]
		if component.interactive || component.resource == (shared.Resource_UUID{}) {
			continue
		}
		if node.has_clip {
			visible := rect_intersection(node.rect, node.clip)
			if visible.width <= 0 || visible.height <= 0 {
				continue
			}
		}
		if state.thumbnail_surface_count >= MAX_RESOURCE_THUMBNAILS {
			break
		}
		state.thumbnail_surfaces[state.thumbnail_surface_count] = {
			entity = node.entity,
			component = component,
		}
		state.thumbnail_surface_count += 1
	}
}

ui_entity_or_ancestor_hidden :: proc(world: ^shared.World, entity_index: int) -> bool {
	index := entity_index
	for depth in 0 ..< MAX_NODES {
		if index < 0 || index >= len(world.entities) { return false }
		entity := world.entities[index]
		if entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) { return false }
		layout := world.ui_layouts[entity.ui_layout_index]
		if layout.hidden { return true }
		if layout.parent == (shared.Entity_UUID{}) { return false }
		index = find_parent_entity(world, layout.parent, entity.origin)
		if index < 0 { return false }
	}
	return false
}

editor_viewport :: proc(
	state: ^State,
	drawable_width, drawable_height: f32,
	project_width: f32 = 1280,
	project_height: f32 = 720,
) -> Rect {
	scale := f32(
		1,
	); if state != nil && state.editor_pixel_density > 0 { scale = state.editor_pixel_density }
	return editor_viewport_for_scale(state, drawable_width, drawable_height, scale)
}

Project_Canvas_Transform :: struct {
	viewport: Rect,
	clip: Rect,
	logical_viewport: Rect,
	scale: shared.Vec2,
}

project_canvas_scale :: proc(
	drawable_width, drawable_height: f32,
	project_width: f32 = 1280,
	project_height: f32 = 720,
) -> f32 {
	scale := f32(1)
	if project_width > 0 && project_height > 0 {
		scale = min(drawable_width / project_width, drawable_height / project_height)
	}
	if scale <= 0 {
		return 1
	}
	return scale
}

ui_alignment_offset :: proc "contextless" (available: f32, alignment: shared.UI_Alignment) -> f32 {
	switch alignment {
		case .Center:
			return available * 0.5
		case .End:
			return available
		case .Start, .Stretch:
			return 0
	}
	return 0
}

ui_canvas_alignment_offset :: proc "contextless" (
	available: f32,
	alignment: shared.UI_Canvas_Alignment,
) -> f32 {
	switch alignment {
		case .Center:
			return available * 0.5
		case .End:
			return available
		case .Start:
			return 0
	}
	return 0
}

clamp_canvas_scale :: proc "contextless" (scale, minimum, maximum: f32) -> f32 {
	result := scale
	if minimum > 0 {
		result = max(result, minimum)
	}
	if maximum > 0 {
		result = min(result, maximum)
	}
	return max(result, 0.0001)
}

project_canvas_transform :: proc(
	state: ^State,
	drawable_width, drawable_height: f32,
	project_width: f32 = 1280,
	project_height: f32 = 720,
) -> Project_Canvas_Transform {
	host := editor_viewport(state, drawable_width, drawable_height)
	return project_canvas_transform_in_host(state, host, project_width, project_height)
}

project_canvas_transform_in_host :: proc(
	state: ^State,
	host: Rect,
	project_width: f32 = 1280,
	project_height: f32 = 720,
) -> Project_Canvas_Transform {
	canvas := shared.UI_Canvas_Component {
		reference_size = {project_width, project_height},
		scale_mode = .Fit,
	}
	if state != nil && state.project_canvas_valid {
		canvas = state.project_canvas
	}
	reference := canvas.reference_size
	if reference.x <= 0 || reference.y <= 0 {
		reference = {max(project_width, 1), max(project_height, 1)}
	}
	scale := shared.Vec2{1, 1}
	logical_size := reference
	switch canvas.scale_mode {
		case .Fit, .Expand:
			uniform := min(host.width / reference.x, host.height / reference.y)
			uniform = clamp_canvas_scale(uniform, canvas.min_scale, canvas.max_scale)
			scale = {uniform, uniform}
			if canvas.scale_mode == .Expand {
				logical_size = {host.width / uniform, host.height / uniform}
			}
		case .Fill:
			uniform := max(host.width / reference.x, host.height / reference.y)
			uniform = clamp_canvas_scale(uniform, canvas.min_scale, canvas.max_scale)
			scale = {uniform, uniform}
		case .Stretch:
			scale = {
				clamp_canvas_scale(host.width / reference.x, canvas.min_scale, canvas.max_scale),
				clamp_canvas_scale(host.height / reference.y, canvas.min_scale, canvas.max_scale),
			}
		case .Pixel_Perfect:
			fit := min(host.width / reference.x, host.height / reference.y)
			uniform := fit
			if fit >= 1 {
				uniform = max(math.floor(fit), 1)
			}
			uniform = clamp_canvas_scale(uniform, canvas.min_scale, canvas.max_scale)
			scale = {uniform, uniform}
		case .None:
			density := f32(1)
			if state != nil {
				density = max(state.editor_pixel_density, 1)
			}
			density = clamp_canvas_scale(density, canvas.min_scale, canvas.max_scale)
			scale = {density, density}
			logical_size = {host.width / density, host.height / density}
	}
	output_size := shared.Vec2{logical_size.x * scale.x, logical_size.y * scale.y}
	offset := shared.Vec2 {
		ui_canvas_alignment_offset(host.width - output_size.x, canvas.horizontal_alignment),
		ui_canvas_alignment_offset(host.height - output_size.y, canvas.vertical_alignment),
	}
	return {
		viewport = {host.x + offset.x, host.y + offset.y, output_size.x, output_size.y},
		clip = host,
		logical_viewport = {0, 0, logical_size.x, logical_size.y},
		scale = scale,
	}
}

editor_viewport_for_scale :: proc(
	state: ^State,
	drawable_width, drawable_height, scale: f32,
) -> Rect {
	available := Rect{0, 0, drawable_width, drawable_height}
	if state != nil && state.editor_visible {
		found := false
		for node in state.nodes[:state.node_count] {
			if node.origin != .Editor || node.editor_role != .Viewport { continue }
			available = {
				node.rect.x * scale,
				node.rect.y * scale,
				node.rect.width * scale,
				node.rect.height * scale,
			}
			found = true
			break
		}
		if !found { available = {(EDITOR_LEFT_SIDEBAR_WIDTH + EDITOR_VIEWPORT_INSET) * scale, EDITOR_TOP_BAR_HEIGHT * scale, drawable_width - (EDITOR_LEFT_SIDEBAR_WIDTH + EDITOR_RIGHT_SIDEBAR_WIDTH + EDITOR_VIEWPORT_INSET * 2) * scale, drawable_height - (EDITOR_TOP_BAR_HEIGHT + EDITOR_STATUS_BAR_HEIGHT) * scale} }
	}
	target_width := max(drawable_width, 0)
	target_height := max(drawable_height, 0)
	x0 := clamp(available.x, 0, target_width)
	y0 := clamp(available.y, 0, target_height)
	x1 := clamp(available.x + max(available.width, 0), x0, target_width)
	y1 := clamp(available.y + max(available.height, 0), y0, target_height)
	return {x0, y0, x1 - x0, y1 - y0}
}

project_pointer_input :: proc(
	state: ^State,
	pointer: Pointer_Input,
	width, height: f32,
	drawable_width: f32 = 0,
	drawable_height: f32 = 0,
) -> Pointer_Input {
	if state == nil || !pointer.available { return pointer }
	surface_width := drawable_width; if surface_width <= 0 { surface_width = width }
	surface_height := drawable_height; if surface_height <= 0 { surface_height = height }
	transform := project_canvas_transform(state, surface_width, surface_height, width, height)
	if !rect_contains(transform.clip, pointer.position) { return {} }
	return {
		position = {
			(pointer.position.x - transform.viewport.x) / transform.scale.x,
			(pointer.position.y - transform.viewport.y) / transform.scale.y,
		},
		wheel_y = pointer.wheel_y,
		primary_down = pointer.primary_down,
		primary_pressed = pointer.primary_pressed,
		primary_released = pointer.primary_released,
		edges_authoritative = pointer.edges_authoritative,
		available = true,
	}
}

editor_clear_selection :: proc(state: ^State) {if state == nil { return }
	if len(state.editor_selected_uuids) == 0 && !state.editor_has_selection { return }
	clear(&state.editor_selected_uuids)
	state.editor_selected_entity = {}
	editor_selection_changed(state)
	for &node in state.nodes[:state.node_count] { if node.editor_role == .Inspector_Scroll { node.scroll_offset = 0; node.scroll_target = 0 } }
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_gizmo_visible = false
	state.editor_light_gizmo_active = false
	state.editor_light_gizmo_captures_pointer = false
	state.editor_light_gizmo_visible = false}

editor_set_entity_selection :: proc(
	state: ^State,
	world: ^shared.World,
	entities: []shared.Entity,
	toggle: bool = false,
) {
	if state == nil || world == nil {
		return
	}
	if !toggle {
		clear(&state.editor_selected_uuids)
	}
	for entity in entities {
		entity_index := int(entity.index)
		if !ecs.entity_is_alive(world, entity_index) ||
		   world.entities[entity_index].id != entity ||
		   world.entities[entity_index].origin == .Editor {
			continue
		}
		selected_entity := entity
		if model_owner := world.entities[entity_index].model_owner;
		   model_owner != (shared.Entity_UUID{}) {
			if owner_index, found := ecs.entity_index_by_uuid(world, model_owner);
			   found && world.entities[owner_index].origin != .Editor {
				selected_entity = world.entities[owner_index].id
			}
		}
		selected_index := int(selected_entity.index)
		selected_uuid := world.entities[selected_index].uuid
		selected_at := -1
		for id, selection_index in state.editor_selected_uuids {
			if id == selected_uuid {
				selected_at = selection_index
				break
			}
		}
		if toggle && selected_at >= 0 {
			ordered_remove(&state.editor_selected_uuids, selected_at)
			continue
		}
		if selected_at < 0 {
			append(&state.editor_selected_uuids, selected_uuid)
		}
	}
	if len(state.editor_selected_uuids) > 0 {
		active_uuid := state.editor_selected_uuids[len(state.editor_selected_uuids) - 1]
		active_index, _ := ecs.entity_index_by_uuid(world, active_uuid)
		state.editor_selected_entity = world.entities[active_index].id
		state.editor_has_resource_selection = false
	} else {
		state.editor_selected_entity = {}
	}
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_light_gizmo_active = false
	state.editor_light_gizmo_captures_pointer = false
	editor_selection_changed(state)
}

editor_restore_selection_uuids :: proc(
	state: ^State,
	world: ^shared.World,
	ids: []shared.Entity_UUID,
) {
	if state == nil || world == nil {
		return
	}
	entities: [dynamic]shared.Entity
	defer delete(entities)
	for id in ids {
		if entity_index, found := ecs.entity_index_by_uuid(world, id);
		   found && world.entities[entity_index].origin != .Editor {
			append(&entities, world.entities[entity_index].id)
		}
	}
	editor_set_entity_selection(state, world, entities[:])
}

editor_box_select_update :: proc(state: ^State, pointer: Pointer_Input, scale: f32) {
	if state == nil || !state.editor_box_select_armed {
		return
	}
	if pointer.available {
		state.editor_box_select_current = pointer.position
	}
	delta := shared.Vec2 {
		state.editor_box_select_current.x - state.editor_box_select_start.x,
		state.editor_box_select_current.y - state.editor_box_select_start.y,
	}
	if pointer.primary_down &&
	   !state.editor_box_select_active &&
	   delta.x * delta.x + delta.y * delta.y >= 16 {
		state.editor_box_select_active = true
	}
	if pointer.primary_down {
		return
	}
	if state.editor_box_select_active {
		x0 := min(state.editor_box_select_start.x, state.editor_box_select_current.x)
		y0 := min(state.editor_box_select_start.y, state.editor_box_select_current.y)
		x1 := max(state.editor_box_select_start.x, state.editor_box_select_current.x)
		y1 := max(state.editor_box_select_start.y, state.editor_box_select_current.y)
		selection := rect_intersection(
			Rect{x0, y0, x1 - x0, y1 - y0},
			state.editor_box_select_clip,
		)
		state.editor_box_select_requested = selection.width > 0 && selection.height > 0
		state.editor_box_select_request_rect = Rect {
			selection.x * scale,
			selection.y * scale,
			selection.width * scale,
			selection.height * scale,
		}
		state.editor_box_select_request_toggle_selection = state.editor_box_select_toggle_selection
	} else {
		state.editor_pick_requested = true
		state.editor_pick_position = {
			state.editor_box_select_current.x * scale,
			state.editor_box_select_current.y * scale,
		}
		state.editor_pick_toggle_selection = state.editor_box_select_toggle_selection
	}
	state.editor_box_select_armed = false
	state.editor_box_select_active = false
}

editor_remove_selection_uuid :: proc(state: ^State, world: ^shared.World, id: shared.Entity_UUID) {
	if state == nil || id == (shared.Entity_UUID{}) {
		return
	}
	for selected, selection_index in state.editor_selected_uuids {
		if selected != id { continue }
		ordered_remove(&state.editor_selected_uuids, selection_index)
		if world != nil && len(state.editor_selected_uuids) > 0 {
			active_uuid := state.editor_selected_uuids[len(state.editor_selected_uuids) - 1]
			if active_index, found := ecs.entity_index_by_uuid(world, active_uuid); found {
				state.editor_selected_entity = world.entities[active_index].id
			}
		} else if len(state.editor_selected_uuids) == 0 {
			state.editor_selected_entity = {}
		}
		editor_selection_changed(state)
		return
	}
}

editor_set_gizmo_mode :: proc(state: ^State, mode: shared.Editor_Gizmo_Mode) {
	if state == nil || state.editor_gizmo_mode == mode { return }
	state.editor_gizmo_mode = mode
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_hovered_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_snapshot_valid = false
}

editor_set_gizmo_space :: proc(state: ^State, space: shared.Editor_Gizmo_Space) {
	if state == nil || state.editor_gizmo_space == space { return }
	state.editor_gizmo_space = space
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_hovered_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_snapshot_valid = false
}

editor_set_gizmo_pivot :: proc(state: ^State, pivot: shared.Editor_Gizmo_Pivot) {
	if state == nil || state.editor_gizmo_pivot == pivot { return }
	state.editor_gizmo_pivot = pivot
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_hovered_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_gizmo_bounds_valid = false
	state.editor_snapshot_valid = false
}

editor_pointer_over_gizmo_toolbar :: proc(state: ^State, pointer: Pointer_Input) -> bool {
	if state == nil || !pointer.available {
		return false
	}
	point := pointer.position
	scale := max(state.editor_pixel_density, 1)
	point.x /= scale
	point.y /= scale
	for node in state.nodes[:state.node_count] {
		if node.origin != .Editor || node.editor_role != .Gizmo_Toolbar || !node.laid_out {
			continue
		}
		return node_pointer_contains(node, point)
	}
	return false
}

editor_pointer_consumed_by_chrome :: proc(state: ^State, pointer: Pointer_Input) -> bool {
	if state == nil || !pointer.available {
		return false
	}
	point := pointer.position
	scale := max(state.editor_pixel_density, 1)
	point.x /= scale
	point.y /= scale
	hit := pointer_hit_node(state, point, true)
	for hit >= 0 && hit < state.node_count {
		node := state.nodes[hit]
		if node.button_index >= 0 ||
		   node.input_index >= 0 ||
		   node.checkbox_index >= 0 ||
		   node.color_picker_index >= 0 {
			return true
		}
		if node.editor_role == .Viewport {
			return false
		}
		hit = node.parent_node_index
	}
	return true
}

editor_select_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity: shared.Entity,
	height: f32,
	toggle: bool = false,
) -> bool {
	_ = height
	if state == nil || world == nil { return false }; index := int(entity.index)
	if index < 0 ||
	   index >= len(world.entities) ||
	   !world.entities[index].alive ||
	   world.entities[index].origin == .Editor ||
	   world.entities[index].id.generation != entity.generation { return false }
	selected_entity := entity
	model_owner := world.entities[index].model_owner
	if model_owner != (shared.Entity_UUID{}) {
		if owner_index, found := ecs.entity_index_by_uuid(world, model_owner);
		   found &&
		   owner_index >= 0 &&
		   owner_index < len(world.entities) &&
		   world.entities[owner_index].alive &&
		   world.entities[owner_index].origin != .Editor {
			selected_entity = world.entities[owner_index].id
		}
	}
	selected_index := int(selected_entity.index)
	selected_uuid := world.entities[selected_index].uuid
	already_selected := editor_entity_selected(state, selected_uuid)
	if toggle && already_selected {
		for id, selection_index in state.editor_selected_uuids {
			if id != selected_uuid { continue }
			ordered_remove(&state.editor_selected_uuids, selection_index)
			break
		}
		if len(state.editor_selected_uuids) > 0 {
			active_uuid := state.editor_selected_uuids[len(state.editor_selected_uuids) - 1]
			active_index, _ := ecs.entity_index_by_uuid(world, active_uuid)
			state.editor_selected_entity = world.entities[active_index].id
		} else {
			state.editor_selected_entity = {}
		}
		editor_selection_changed(state)
		return true
	}
	selection_replaced := !toggle && (len(state.editor_selected_uuids) != 1 || !already_selected)
	active_changed := state.editor_selected_entity != selected_entity
	if selection_replaced || active_changed {
		for &node in state.nodes[:state.node_count] { if node.editor_role == .Inspector_Scroll { node.scroll_offset = 0; node.scroll_target = 0 } }
	}
	if selection_replaced || active_changed || !already_selected {
		state.editor_gizmo_active_handle = .None
		state.editor_gizmo_captures_pointer = false
		state.editor_light_gizmo_active = false
		state.editor_light_gizmo_captures_pointer = false
	}
	if !toggle {
		clear(&state.editor_selected_uuids)
	}
	if !already_selected || !toggle {
		append(&state.editor_selected_uuids, selected_uuid)
	} else if active_changed {
		for id, selection_index in state.editor_selected_uuids {
			if id != selected_uuid { continue }
			ordered_remove(&state.editor_selected_uuids, selection_index)
			append(&state.editor_selected_uuids, selected_uuid)
			break
		}
	}
	state.editor_selected_entity = selected_entity
	state.editor_has_resource_selection = false
	if selection_replaced || active_changed || !already_selected {
		editor_selection_changed(state)
	}
	row_slot := -1
	for component in world.editor_uis { if (component.role == .Browser_Row || component.role == .Browser_Row_Label) && component.target == selected_entity { row_slot = component.slot; break } }
	if row_slot >=
	   0 { for &node in state.nodes[:state.node_count] { if node.editor_role != .Browser_Scroll { continue }; row_top := f32(row_slot) * EDITOR_ENTITY_ROW_HEIGHT; row_bottom := row_top + EDITOR_ENTITY_ROW_HEIGHT; if row_top < node.scroll_target { node.scroll_target = row_top } else if row_bottom > node.scroll_target + node.rect.height { node.scroll_target = row_bottom - node.rect.height }; break } }
	return true
}

editor_activate_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity: shared.Entity,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_alive(world, entity_index) || world.entities[entity_index].id != entity {
		return false
	}
	id := world.entities[entity_index].uuid
	if !editor_entity_selected(state, id) {
		return editor_select_entity(state, world, entity, 0)
	}
	for selected, selection_index in state.editor_selected_uuids {
		if selected != id { continue }
		ordered_remove(&state.editor_selected_uuids, selection_index)
		append(&state.editor_selected_uuids, id)
		break
	}
	state.editor_selected_entity = entity
	editor_selection_changed(state)
	return true
}

find_node :: proc(state: ^State, entity: shared.Entity) -> int {
	if state == nil {
		return -1
	}
	index := find_node_by_entity_index(state, int(entity.index))
	if index >= 0 && state.nodes[index].entity == entity {
		return index
	}
	return -1
}

find_node_by_entity_index :: proc(state: ^State, index: int) -> int {
	if state == nil || index < 0 {
		return -1
	}
	left := 0
	right := state.node_count
	for left < right {
		middle := left + (right - left) / 2
		entity_index := int(state.nodes[middle].entity.index)
		if entity_index < index {
			left = middle + 1
		} else {
			right = middle
		}
	}
	if left < state.node_count && int(state.nodes[left].entity.index) == index {
		return left
	}
	return -1
}

rebuild_ui_node_hierarchy :: proc(state: ^State) -> string {
	if state == nil {
		return ""
	}
	state.ui_hierarchy_rebuild_count += 1
	last_children: [MAX_NODES]int
	visit_states: [MAX_NODES]u8
	path: [MAX_NODES]int
	for index in 0 ..< state.node_count {
		state.nodes[index].parent_node_index = -1
		state.nodes[index].first_child_node = -1
		state.nodes[index].next_sibling_node = -1
		last_children[index] = -1
	}
	for index in 0 ..< state.node_count {
		node := &state.nodes[index]
		if node.parent_entity_index < 0 {
			continue
		}
		parent_index := find_node_by_entity_index(state, node.parent_entity_index)
		if parent_index < 0 {
			continue
		}
		node.parent_node_index = parent_index
	}
	for start in 0 ..< state.node_count {
		if visit_states[start] == 2 {
			continue
		}
		path_count := 0
		index := start
		for index >= 0 {
			if visit_states[index] == 1 {
				return "UI hierarchy contains a cycle"
			}
			if visit_states[index] == 2 {
				break
			}
			visit_states[index] = 1
			path[path_count] = index
			path_count += 1
			index = state.nodes[index].parent_node_index
		}
		for path_index in 0 ..< path_count {
			visit_states[path[path_index]] = 2
		}
	}
	for index in 0 ..< state.node_count {
		node := &state.nodes[index]
		parent_index := node.parent_node_index
		if parent_index < 0 {
			continue
		}
		if state.nodes[parent_index].first_child_node < 0 {
			state.nodes[parent_index].first_child_node = index
		} else {
			state.nodes[last_children[parent_index]].next_sibling_node = index
		}
		last_children[parent_index] = index
	}
	return ""
}

find_parent_entity :: proc(
	world: ^shared.World,
	id: shared.Entity_UUID,
	origin: shared.Entity_Origin,
) -> int {
	if id == (shared.Entity_UUID{}) {
		return -1
	}
	if index, found := ecs.entity_index_by_uuid(world, id); found {
		parent_origin := world.entities[index].origin
		if parent_origin == origin || parent_origin != .Editor && origin != .Editor {
			return index
		}
	}
	return -1
}

ui_layout_is_popup :: proc "contextless" (layout: shared.UI_Layout_Component) -> bool {
	return layout.popup
}

layout_popup_root :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	viewport: Rect,
) -> string {
	node := &state.nodes[node_index]
	layout := world.ui_layouts[node.layout_index]
	if !layout.popup_open {
		return ""
	}
	anchor_entity_index, anchor_found := ecs.entity_index_by_uuid(world, layout.popup_anchor)
	if !anchor_found || world.entities[anchor_entity_index].origin != node.origin {
		_ = set_popup_open(world, int(node.entity.index), false)
		return ""
	}
	anchor_node_index := find_node_by_entity_index(state, anchor_entity_index)
	if anchor_node_index < 0 || !state.nodes[anchor_node_index].laid_out {
		_ = set_popup_open(world, int(node.entity.index), false)
		return ""
	}
	anchor := state.nodes[anchor_node_index].rect
	margin := max(layout.popup_viewport_margin, 0)
	gap := max(layout.popup_gap, 0)
	top := viewport.y + margin
	bottom := viewport.y + viewport.height - margin
	size := node_layout_size(world, node^, layout)
	if layout.popup_min_width > 0 {
		size.x = max(size.x, layout.popup_min_width)
	}
	if layout.popup_max_width > 0 {
		size.x = min(size.x, layout.popup_max_width)
	}
	size.x = min(size.x, max(viewport.width - margin * 2, 0))
	available_height := max(bottom - top, 0)
	if layout.popup_max_height > 0 {
		available_height = min(available_height, layout.popup_max_height)
	}
	size.y = min(size.y, available_height)
	position := shared.Vec2 {
		clamp(
			anchor.x,
			viewport.x + margin,
			max(viewport.x + viewport.width - size.x - margin, viewport.x + margin),
		),
		anchor.y + anchor.height + gap,
	}
	if position.y + size.y > bottom {
		position.y = max(anchor.y - size.y - gap, top)
	}
	return layout_node(
		state,
		world,
		node_index,
		viewport,
		position,
		true,
		size,
		true,
		{},
		false,
		0,
	)
}

layout_all :: proc(
	state: ^State,
	world: ^shared.World,
	project_viewport, editor_viewport: Rect,
	layout_project := true,
	layout_editor := true,
) -> string {
	if layout_project &&
	   (state.ui_project_list_flow_revision != world.ui_project_layout_revision ||
			   state.ui_project_list_flow_structure_revision != world.ui_structure_revision) {
		rebuild_list_flow_cache(state, world, false)
	}
	if layout_editor &&
	   (state.ui_editor_list_flow_revision != world.ui_editor_layout_revision ||
			   state.ui_editor_list_flow_structure_revision != world.ui_structure_revision) {
		rebuild_list_flow_cache(state, world, true)
	}
	for _ in 0 ..< 4 {
		state.next_paint_order = 0
		preserved_handle_count := 0
		for handle in state.split_handles[:state.split_handle_count] {
			if (handle.editor && !layout_editor) || (!handle.editor && !layout_project) {
				state.split_handles[preserved_handle_count] = handle
				preserved_handle_count += 1
			}
		}
		state.split_handle_count = preserved_handle_count
		preserved_dock_tab_count := 0
		for tab in state.dock_tabs[:state.dock_tab_count] {
			if (tab.editor && !layout_editor) || (!tab.editor && !layout_project) {
				state.dock_tabs[preserved_dock_tab_count] = tab
				preserved_dock_tab_count += 1
			}
		}
		state.dock_tab_count = preserved_dock_tab_count
		state.layout_size_changed = false
		for &node in state.nodes[:state.node_count] {
			if (node.origin == .Editor && !layout_editor) ||
			   (node.origin != .Editor && !layout_project) {
				continue
			}
			node.laid_out = false
			node.fill_width_valid = false
			node.fill_height_valid = false
		}
		for i in 0 ..< state.node_count {
			if state.nodes[i].parent_entity_index >= 0 {
				continue
			}
			if (state.nodes[i].origin == .Editor && !layout_editor) ||
			   (state.nodes[i].origin != .Editor && !layout_project) {
				continue
			}
			viewport := project_viewport
			if state.nodes[i].origin == .Editor {
				viewport = editor_viewport
			}
			layout := world.ui_layouts[state.nodes[i].layout_index]
			if ui_layout_is_popup(layout) {
				continue
			}
			if err := layout_node(state, world, i, viewport, {}, false, {}, false, {}, false, 0);
			   err != "" {
				return err
			}
		}
		for i in 0 ..< state.node_count {
			if state.nodes[i].parent_entity_index >= 0 {
				continue
			}
			if (state.nodes[i].origin == .Editor && !layout_editor) ||
			   (state.nodes[i].origin != .Editor && !layout_project) {
				continue
			}
			layout := world.ui_layouts[state.nodes[i].layout_index]
			if !ui_layout_is_popup(layout) {
				continue
			}
			viewport := project_viewport
			if state.nodes[i].origin == .Editor {
				viewport = editor_viewport
			}
			if err := layout_popup_root(state, world, i, viewport); err != "" {
				return err
			}
		}
		if !state.layout_size_changed {
			break
		}
	}
	if layout_project {
		state.ui_project_layout_revision = world.ui_project_layout_revision
		state.ui_project_viewport = project_viewport
		state.ui_project_paint_revision += 1
		if state.ui_project_paint_revision == 0 {
			state.ui_project_paint_revision = 1
		}
	}
	if layout_editor {
		state.ui_editor_layout_revision = world.ui_editor_layout_revision
		state.ui_editor_viewport = editor_viewport
		state.ui_editor_paint_revision += 1
		if state.ui_editor_paint_revision == 0 {
			state.ui_editor_paint_revision = 1
		}
	}
	state.ui_layout_valid = true
	return ""
}

node_panel_collapsed :: proc(world: ^shared.World, node: Node) -> bool {
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		panel := world.ui_panels[node.panel_index]
		return panel.collapsible && panel.collapsed && panel.title != ""
	}
	return false
}

node_layout_size :: proc(
	world: ^shared.World,
	node: Node,
	layout: shared.UI_Layout_Component,
) -> shared.Vec2 {
	size := layout.size
	size.x = max(size.x, layout.min_size.x)
	size.y = max(size.y, layout.min_size.y)
	if layout.fit_content_width && node.resolved_width_valid {
		size.x = max(node.resolved_size.x, layout.min_size.x)
	}
	if layout.fit_content_height && node.resolved_height_valid {
		size.y = max(node.resolved_size.y, layout.min_size.y)
	}
	if node_panel_collapsed(world, node) {
		panel := world.ui_panels[node.panel_index]
		size.y = min(max(panel.title_height, 0), size.y)
	}
	return size
}

node_intrinsic_content_size :: proc(
	state: ^State,
	world: ^shared.World,
	node: ^Node,
	available_width: f32,
) -> shared.Vec2 {
	if state == nil || world == nil || node == nil {
		return {}
	}
	if node.text_index >= 0 && node.text_index < len(world.ui_texts) {
		text := world.ui_texts[node.text_index]
		select_font(state, text.font)
		lines: [MAX_TEXT_LINES]Text_Line
		line_count := text_layout_lines(
			state,
			text.text,
			text.size,
			available_width,
			text.wrap,
			&lines,
		)
		width := f32(0)
		for line in lines[:line_count] {
			width = max(width, line.advance)
		}
		line_height := text.size
		if text.line_height > 0 {
			line_height = text.line_height
		}
		return {width, line_height * f32(line_count)}
	}
	if node.button_index >= 0 && node.button_index < len(world.ui_buttons) {
		button := world.ui_buttons[node.button_index]
		select_font(state, button.font)
		width := text_advance_to(state, button.text, button.size, len(button.text))
		height := button.size
		if button.icon_set != (shared.Resource_UUID{}) && button.icon != "" {
			icon_size := button.icon_size
			if icon_size <= 0 {
				icon_size = button.size * 1.25
			}
			width += icon_size
			height = max(height, icon_size)
			if button.text != "" {
				width += button.icon_gap
			}
		}
		return {width, height}
	}
	return {}
}

node_is_panel_action :: proc(world: ^shared.World, node: ^Node) -> bool {
	return(
		world != nil &&
		node != nil &&
		node.button_index >= 0 &&
		node.button_index < len(world.ui_buttons) &&
		world.ui_buttons[node.button_index].panel_action \
	)
}

sort_stack_nodes :: proc(
	state: ^State,
	world: ^shared.World,
	values: ^[MAX_NODES]int,
	count: int,
) {
	for index in 1 ..< count {
		value := values[index]
		order := world.ui_layouts[state.nodes[value].layout_index].stack_order
		cursor := index
		for cursor > 0 {
			previous := values[cursor - 1]
			previous_order := world.ui_layouts[state.nodes[previous].layout_index].stack_order
			if previous_order < order ||
			   previous_order == order &&
				   state.nodes[previous].entity.index < state.nodes[value].entity.index {
				break
			}
			values[cursor] = previous
			cursor -= 1
		}
		values[cursor] = value
	}
}

tree_node_less :: proc(state: ^State, world: ^shared.World, left_index, right_index: int) -> bool {
	left := state.nodes[left_index]
	right := state.nodes[right_index]
	left_layout := world.ui_layouts[left.layout_index]
	right_layout := world.ui_layouts[right.layout_index]
	if left_layout.tree_order != right_layout.tree_order {
		return left_layout.tree_order < right_layout.tree_order
	}
	return left.entity.index < right.entity.index
}

sort_tree_nodes :: proc(state: ^State, world: ^shared.World, values: ^[MAX_NODES]int, count: int) {
	if count < 2 {
		return
	}
	buffer: [MAX_NODES]int
	width := 1
	for width < count {
		start := 0
		for start < count {
			middle := min(start + width, count)
			end := min(start + width * 2, count)
			left := start
			right := middle
			output := start
			for output < end {
				if right >= end ||
				   left < middle && tree_node_less(state, world, values[left], values[right]) {
					buffer[output] = values[left]
					left += 1
				} else {
					buffer[output] = values[right]
					right += 1
				}
				output += 1
			}
			start = end
		}
		for index in 0 ..< count {
			values[index] = buffer[index]
		}
		width *= 2
	}
}

mark_tree_branch_hidden :: proc(
	node_index: int,
	first_child: ^[MAX_NODES]int,
	next_sibling: ^[MAX_NODES]int,
	visit: ^[MAX_NODES]u8,
) {
	if node_index < 0 || node_index >= MAX_NODES || visit[node_index] != 0 {
		return
	}
	visit[node_index] = 2
	child := first_child[node_index]
	for child >= 0 {
		mark_tree_branch_hidden(child, first_child, next_sibling, visit)
		child = next_sibling[child]
	}
}

ascii_fold_byte :: proc "contextless" (value: u8) -> u8 {
	if value >= 'A' && value <= 'Z' {
		return value + ('a' - 'A')
	}
	return value
}

string_contains_folded_ascii :: proc "contextless" (value, query: string) -> bool {
	if len(query) == 0 {
		return true
	}
	if len(query) > len(value) {
		return false
	}
	for start in 0 ..= len(value) - len(query) {
		matches := true
		for offset in 0 ..< len(query) {
			if ascii_fold_byte(value[start + offset]) != ascii_fold_byte(query[offset]) {
				matches = false
				break
			}
		}
		if matches {
			return true
		}
	}
	return false
}

node_contains_filter_text :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	filter: string,
	depth: int = 0,
) -> bool {
	if state == nil ||
	   world == nil ||
	   node_index < 0 ||
	   node_index >= state.node_count ||
	   depth > MAX_NODES {
		return false
	}
	node := state.nodes[node_index]
	if node.text_index >= 0 &&
	   node.text_index < len(world.ui_texts) &&
	   string_contains_folded_ascii(world.ui_texts[node.text_index].text, filter) {
		return true
	}
	if node.button_index >= 0 &&
	   node.button_index < len(world.ui_buttons) &&
	   string_contains_folded_ascii(world.ui_buttons[node.button_index].text, filter) {
		return true
	}
	if node.input_index >= 0 &&
	   node.input_index < len(world.ui_inputs) &&
	   string_contains_folded_ascii(world.ui_inputs[node.input_index].text, filter) {
		return true
	}
	child := node.first_child_node
	for child >= 0 {
		if node_contains_filter_text(state, world, child, filter, depth + 1) {
			return true
		}
		child = state.nodes[child].next_sibling_node
	}
	return false
}

list_filter_text :: proc(state: ^State, world: ^shared.World, list_node_index: int) -> string {
	if state == nil || world == nil || list_node_index < 0 || list_node_index >= state.node_count {
		return ""
	}
	list_node := state.nodes[list_node_index]
	if list_node.list_index < 0 || list_node.list_index >= len(world.ui_lists) {
		return ""
	}
	filter_input := world.ui_lists[list_node.list_index].filter_input
	if filter_input == (shared.Entity_UUID{}) {
		return ""
	}
	entity_index, found := world.entity_by_uuid[filter_input]
	if !found ||
	   entity_index < 0 ||
	   entity_index >= len(world.entities) ||
	   !world.entities[entity_index].alive ||
	   world.entities[entity_index].origin != list_node.origin {
		return ""
	}
	input_index := world.entities[entity_index].ui_input_index
	if input_index < 0 || input_index >= len(world.ui_inputs) {
		return ""
	}
	return world.ui_inputs[input_index].text
}

mark_tree_filter_matches :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	filter: string,
	first_child: ^[MAX_NODES]int,
	next_sibling: ^[MAX_NODES]int,
	suppressed: ^[MAX_NODES]bool,
	keep: ^[MAX_NODES]bool,
	visit: ^[MAX_NODES]u8,
) -> bool {
	if node_index < 0 || node_index >= state.node_count || suppressed[node_index] {
		return false
	}
	if visit[node_index] == 1 {
		return false
	}
	if visit[node_index] == 2 {
		return keep[node_index]
	}
	visit[node_index] = 1
	matches := node_contains_filter_text(state, world, node_index, filter)
	child := first_child[node_index]
	for child >= 0 {
		matches =
			mark_tree_filter_matches(
				state,
				world,
				child,
				filter,
				first_child,
				next_sibling,
				suppressed,
				keep,
				visit,
			) ||
			matches
		child = next_sibling[child]
	}
	keep[node_index] = matches
	visit[node_index] = 2
	return matches
}

append_tree_branch :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	depth: int,
	first_child: ^[MAX_NODES]int,
	next_sibling: ^[MAX_NODES]int,
	visit: ^[MAX_NODES]u8,
	output: ^[MAX_NODES]int,
	output_count: ^int,
	filter_active: bool,
	keep: ^[MAX_NODES]bool,
) {
	if node_index < 0 || node_index >= state.node_count || visit[node_index] != 0 {
		return
	}
	if filter_active && !keep[node_index] {
		visit[node_index] = 2
		return
	}
	visit[node_index] = 1
	if output_count^ < MAX_NODES {
		output[output_count^] = node_index
		state.nodes[node_index].tree_depth = depth
		output_count^ += 1
	}
	layout := world.ui_layouts[state.nodes[node_index].layout_index]
	if (!layout.tree_collapsed || filter_active) && !layout.hidden {
		child := first_child[node_index]
		for child >= 0 {
			append_tree_branch(
				state,
				world,
				child,
				depth + 1,
				first_child,
				next_sibling,
				visit,
				output,
				output_count,
				filter_active,
				keep,
			)
			child = next_sibling[child]
		}
	} else {
		child := first_child[node_index]
		for child >= 0 {
			mark_tree_branch_hidden(child, first_child, next_sibling, visit)
			child = next_sibling[child]
		}
	}
	visit[node_index] = 2
}

tree_list_flow :: proc(
	state: ^State,
	world: ^shared.World,
	list_node_index: int,
	output: ^[MAX_NODES]int,
) -> int {
	filter := list_filter_text(state, world, list_node_index)
	filter_active := len(filter) > 0
	candidates: [MAX_NODES]int
	candidate_count := 0
	output_count := 0
	child := state.nodes[list_node_index].first_child_node
	for child >= 0 {
		next := state.nodes[child].next_sibling_node
		layout := world.ui_layouts[state.nodes[child].layout_index]
		state.nodes[child].tree_depth = 0
		if layout.tree_item {
			candidates[candidate_count] = child
			candidate_count += 1
		} else if !filter_active || node_contains_filter_text(state, world, child, filter) {
			output[output_count] = child
			output_count += 1
		}
		child = next
	}
	sort_tree_nodes(state, world, &candidates, candidate_count)
	is_candidate: [MAX_NODES]bool
	first_child: [MAX_NODES]int
	last_child: [MAX_NODES]int
	next_sibling: [MAX_NODES]int
	for index in 0 ..< MAX_NODES {
		first_child[index] = -1
		last_child[index] = -1
		next_sibling[index] = -1
	}
	for index in 0 ..< candidate_count {
		is_candidate[candidates[index]] = true
	}
	roots: [MAX_NODES]int
	suppressed: [MAX_NODES]bool
	root_count := 0
	list_entity_index := int(state.nodes[list_node_index].entity.index)
	list_uuid := world.entities[list_entity_index].uuid
	for index in 0 ..< candidate_count {
		node_index := candidates[index]
		layout := world.ui_layouts[state.nodes[node_index].layout_index]
		parent_node := -1
		if entity_index, found := world.entity_by_uuid[layout.tree_parent]; found {
			parent_node = find_node_by_entity_index(state, entity_index)
			parent_entity := world.entities[entity_index]
			if parent_entity.ui_layout_index >= 0 &&
			   parent_entity.ui_layout_index < len(world.ui_layouts) {
				parent_layout := world.ui_layouts[parent_entity.ui_layout_index]
				if parent_layout.tree_item &&
				   parent_layout.parent == list_uuid &&
				   parent_layout.hidden {
					suppressed[node_index] = true
					continue
				}
			}
		}
		if parent_node < 0 || parent_node >= MAX_NODES || !is_candidate[parent_node] {
			roots[root_count] = node_index
			root_count += 1
			continue
		}
		if first_child[parent_node] < 0 {
			first_child[parent_node] = node_index
		} else {
			next_sibling[last_child[parent_node]] = node_index
		}
		last_child[parent_node] = node_index
	}
	visit: [MAX_NODES]u8
	for index in 0 ..< candidate_count {
		if suppressed[candidates[index]] {
			mark_tree_branch_hidden(candidates[index], &first_child, &next_sibling, &visit)
		}
	}
	keep: [MAX_NODES]bool
	if filter_active {
		filter_visit: [MAX_NODES]u8
		for index in 0 ..< root_count {
			_ = mark_tree_filter_matches(
				state,
				world,
				roots[index],
				filter,
				&first_child,
				&next_sibling,
				&suppressed,
				&keep,
				&filter_visit,
			)
		}
		for index in 0 ..< candidate_count {
			node_index := candidates[index]
			if filter_visit[node_index] == 0 {
				_ = mark_tree_filter_matches(
					state,
					world,
					node_index,
					filter,
					&first_child,
					&next_sibling,
					&suppressed,
					&keep,
					&filter_visit,
				)
			}
		}
	}
	for index in 0 ..< root_count {
		append_tree_branch(
			state,
			world,
			roots[index],
			0,
			&first_child,
			&next_sibling,
			&visit,
			output,
			&output_count,
			filter_active,
			&keep,
		)
	}
	// Malformed cycles are still rendered deterministically as roots rather than hanging layout.
	for index in 0 ..< candidate_count {
		if visit[candidates[index]] == 0 {
			append_tree_branch(
				state,
				world,
				candidates[index],
				0,
				&first_child,
				&next_sibling,
				&visit,
				output,
				&output_count,
				filter_active,
				&keep,
			)
		}
	}
	return output_count
}

flat_list_flow :: proc(
	state: ^State,
	world: ^shared.World,
	list_node_index: int,
	output: ^[MAX_NODES]int,
) -> int {
	filter := list_filter_text(state, world, list_node_index)
	filter_active := len(filter) > 0
	output_count := 0
	child := state.nodes[list_node_index].first_child_node
	for child >= 0 {
		if !filter_active || node_contains_filter_text(state, world, child, filter) {
			output[output_count] = child
			output_count += 1
		}
		child = state.nodes[child].next_sibling_node
	}
	return output_count
}

rebuild_list_flow_cache :: proc(state: ^State, world: ^shared.World, editor: bool) {
	if state == nil || world == nil {
		return
	}
	cache := &state.ui_project_list_flow_nodes
	cache_count := &state.ui_project_list_flow_count
	if editor {
		cache = &state.ui_editor_list_flow_nodes
		cache_count = &state.ui_editor_list_flow_count
		state.ui_editor_list_flow_rebuild_count += 1
	} else {
		state.ui_project_list_flow_rebuild_count += 1
	}
	cache_count^ = 0
	for &node, node_index in state.nodes[:state.node_count] {
		if (node.origin == .Editor) != editor ||
		   node.list_index < 0 ||
		   node.list_index >= len(world.ui_lists) {
			continue
		}
		flow: [MAX_NODES]int
		flow_count := 0
		list := world.ui_lists[node.list_index]
		if list.tree_enabled {
			flow_count = tree_list_flow(state, world, node_index, &flow)
		} else {
			flow_count = flat_list_flow(state, world, node_index, &flow)
		}
		node.list_flow_offset = cache_count^
		node.list_flow_count = min(flow_count, MAX_NODES - cache_count^)
		for index in 0 ..< node.list_flow_count {
			cache[cache_count^] = flow[index]
			cache_count^ += 1
		}
	}
	if editor {
		state.ui_editor_list_flow_revision = world.ui_editor_layout_revision
		state.ui_editor_list_flow_structure_revision = world.ui_structure_revision
	} else {
		state.ui_project_list_flow_revision = world.ui_project_layout_revision
		state.ui_project_list_flow_structure_revision = world.ui_structure_revision
	}
}

resolve_aligned_axis :: proc "contextless" (
	parent_start, parent_extent, authored_size, minimum_size, authored_position: f32,
	margin_start, margin_end: f32,
	alignment: shared.UI_Alignment,
	fill: bool,
) -> (
	position, size: f32,
) {
	available := max(parent_extent - margin_start - margin_end, 0)
	size = max(authored_size, minimum_size)
	if fill || alignment == .Stretch {
		size = max(available - max(authored_position, 0), minimum_size)
		position = parent_start + margin_start + authored_position
		return
	}
	switch alignment {
		case .Start, .Stretch:
			position = parent_start + margin_start + authored_position
		case .Center:
			position = parent_start + margin_start + (available - size) * 0.5 + authored_position
		case .End:
			position = parent_start + parent_extent - margin_end - size - authored_position
	}
	return
}

layout_node :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	parent: Rect,
	flow_position: shared.Vec2,
	flowed: bool,
	flow_size: shared.Vec2,
	has_flow_size: bool,
	inherited_clip: Rect,
	has_inherited_clip: bool,
	depth: int,
) -> string {
	if depth > MAX_NODES { return "UI hierarchy contains a cycle" }
	when ODIN_TEST {
		state.layout_node_visit_count += 1
	}
	node := &state.nodes[node_index]; layout := world.ui_layouts[node.layout_index]
	node.laid_out = true
	layout_size := node_layout_size(world, node^, layout)
	if node.parent_entity_index < 0 && flowed {
		size := layout_size
		if has_flow_size {
			size = flow_size
		}
		node.rect = {flow_position.x, flow_position.y, size.x, size.y}
	} else if node.parent_entity_index < 0 {
		x, resolved_width := resolve_aligned_axis(
			parent.x,
			parent.width,
			layout_size.x,
			layout.min_size.x,
			layout.position.x,
			layout.margin.w,
			layout.margin.y,
			layout.horizontal_alignment,
			layout.fill_width,
		)
		y, resolved_height := resolve_aligned_axis(
			parent.y,
			parent.height,
			layout_size.y,
			layout.min_size.y,
			layout.position.y,
			layout.margin.x,
			layout.margin.z,
			layout.vertical_alignment,
			layout.fill_height,
		)
		node.rect = {x, y, resolved_width, resolved_height}
	} else if flowed {
		size := layout_size
		if has_flow_size { size = flow_size }
		if layout_size.y < layout.size.y { size.y = layout_size.y }
		node.rect = {flow_position.x, flow_position.y, size.x, size.y}
	} else {
		parent_padding: shared.Vec4
		parent_entity := world.entities[node.parent_entity_index]
		if parent_entity.ui_layout_index >= 0 &&
		   parent_entity.ui_layout_index < len(world.ui_layouts) {
			parent_padding = world.ui_layouts[parent_entity.ui_layout_index].padding
		}
		if node.origin != .Editor &&
		   state.project_canvas_valid &&
		   node.parent_entity_index == state.project_canvas_entity_index {
			safe_area := state.project_canvas.safe_area
			parent_padding = {
				parent_padding.x + safe_area.x,
				parent_padding.y + safe_area.y,
				parent_padding.z + safe_area.z,
				parent_padding.w + safe_area.w,
			}
		}
		content_parent := Rect {
			parent.x + parent_padding.w,
			parent.y + parent_padding.x,
			max(parent.width - parent_padding.w - parent_padding.y, 0),
			max(parent.height - parent_padding.x - parent_padding.z, 0),
		}
		x, resolved_width := resolve_aligned_axis(
			content_parent.x,
			content_parent.width,
			layout_size.x,
			layout.min_size.x,
			layout.position.x,
			layout.margin.w,
			layout.margin.y,
			layout.horizontal_alignment,
			layout.fill_width,
		)
		y, resolved_height := resolve_aligned_axis(
			content_parent.y,
			content_parent.height,
			layout_size.y,
			layout.min_size.y,
			layout.position.y,
			layout.margin.x,
			layout.margin.z,
			layout.vertical_alignment,
			layout.fill_height,
		)
		node.rect = {x, y, resolved_width, resolved_height}
	}
	node.paint_order = state.next_paint_order; state.next_paint_order += 1
	node.clip = inherited_clip; node.has_clip = has_inherited_clip
	cursor := f32(0)
	gap := f32(
		0,
	); stack := shared.UI_Stack_Component{}; is_hstack := node.hstack_index >= 0 && node.hstack_index < len(world.ui_hstacks); is_vstack := node.vstack_index >= 0 && node.vstack_index < len(world.ui_vstacks)
	is_scroll_area :=
		node.scroll_area_index >= 0 && node.scroll_area_index < len(world.ui_scroll_areas)
	is_panel := node.panel_index >= 0 && node.panel_index < len(world.ui_panels)
	is_dock_space :=
		node.dock_space_index >= 0 && node.dock_space_index < len(world.ui_dock_spaces)
	is_table := node.table_index >= 0 && node.table_index < len(world.ui_tables)
	is_list := node.list_index >= 0 && node.list_index < len(world.ui_lists)
	panel: shared.UI_Panel_Component
	dock_space: shared.UI_Dock_Space_Component
	table: shared.UI_Table_Component
	list: shared.UI_List_Component
	if is_panel { panel = world.ui_panels[node.panel_index] }
	if is_dock_space { dock_space = world.ui_dock_spaces[node.dock_space_index] }
	if is_table { table = world.ui_tables[node.table_index] }
	if is_list { list = world.ui_lists[node.list_index] }
	if is_hstack { stack = world.ui_hstacks[node.hstack_index]; gap = stack.gap }
	if is_vstack { stack = world.ui_vstacks[node.vstack_index]; gap = stack.gap }
	content := Rect {
		node.rect.x + layout.padding.w,
		node.rect.y + layout.padding.x,
		max(node.rect.width - layout.padding.w - layout.padding.y, 0),
		max(node.rect.height - layout.padding.x - layout.padding.z, 0),
	}
	if node.origin != .Editor &&
	   state.project_canvas_valid &&
	   int(node.entity.index) == state.project_canvas_entity_index {
		safe_area := state.project_canvas.safe_area
		content.x += safe_area.w
		content.y += safe_area.x
		content.width = max(content.width - safe_area.w - safe_area.y, 0)
		content.height = max(content.height - safe_area.x - safe_area.z, 0)
	}
	dock_active_node := -1
	if is_dock_space {
		first_item_node := -1
		child_index := node.first_child_node
		for child_index >= 0 {
			child := &state.nodes[child_index]
			child_layout := world.ui_layouts[child.layout_index]
			_, is_dock_item := dock_item_title(world, child^)
			if !child_layout.hidden && is_dock_item {
				if first_item_node < 0 {
					first_item_node = child_index
				}
				if world.entities[int(child.entity.index)].uuid == dock_space.active {
					dock_active_node = child_index
				}
			}
			child_index = child.next_sibling_node
		}
		if dock_active_node < 0 {
			dock_active_node = first_item_node
		}
		select_font(state, dock_space.font)
		tab_x := content.x
		child_index = node.first_child_node
		for child_index >= 0 && state.dock_tab_count < MAX_NODES {
			child := &state.nodes[child_index]
			child_layout := world.ui_layouts[child.layout_index]
			title, is_dock_item := dock_item_title(world, child^)
			if !child_layout.hidden && is_dock_item {
				text_bounds, has_ink := measure_text_ink(state, title, dock_space.tab_size)
				text_width := f32(0)
				if has_ink {
					text_width = text_bounds.width
				}
				tab_width := clamp(
					text_width + dock_space.tab_padding * 2,
					dock_space.tab_min_width,
					dock_space.tab_max_width,
				)
				state.dock_tabs[state.dock_tab_count] = {
					rect = {tab_x, content.y, tab_width, dock_space.tab_height},
					space_node = node_index,
					item_node = child_index,
					editor = node.origin == .Editor,
					active = child_index == dock_active_node,
				}
				state.dock_tab_count += 1
				tab_x += tab_width + dock_space.tab_gap
			}
			child_index = child.next_sibling_node
		}
		content.y += dock_space.tab_height
		content.height = max(content.height - dock_space.tab_height, 0)
		content.x += dock_space.content_padding.w
		content.y += dock_space.content_padding.x
		content.width = max(
			content.width - dock_space.content_padding.w - dock_space.content_padding.y,
			0,
		)
		content.height = max(
			content.height - dock_space.content_padding.x - dock_space.content_padding.z,
			0,
		)
	}
	child_parent_rect := node.rect
	if layout.tree_item && node.parent_node_index >= 0 {
		parent_node := state.nodes[node.parent_node_index]
		if parent_node.list_index >= 0 && parent_node.list_index < len(world.ui_lists) {
			parent_list := world.ui_lists[parent_node.list_index]
			if parent_list.tree_enabled {
				indent := parent_list.tree_indent * f32(node.tree_depth)
				content.x += indent
				content.width = max(content.width - indent, 0)
				child_parent_rect.x += indent
				child_parent_rect.width = max(child_parent_rect.width - indent, 0)
			}
		}
	}
	panel_title_height := f32(0)
	panel_docked := is_panel && node_is_docked_panel(state, world, node_index)
	if is_panel && !panel_docked && panel.title != "" {
		panel_title_height = min(max(panel.title_height, 0), content.height)
		content.y += panel_title_height
		content.height -= panel_title_height
	}
	if is_panel && panel_title_height > 0 {
		action_right := node.rect.x + node.rect.width - 5
		child_index := node.first_child_node
		for child_index >= 0 {
			child := &state.nodes[child_index]
			next_child_index := child.next_sibling_node
			child_layout := world.ui_layouts[child.layout_index]
			if !child_layout.hidden && node_is_panel_action(world, child) {
				child_size := node_layout_size(world, child^, child_layout)
				child_size.x = min(child_size.x, max(panel_title_height, 0))
				child_size.y = min(child_size.y, max(panel_title_height, 0))
				position := shared.Vec2 {
					action_right - child_layout.margin.y - child_size.x,
					node.rect.y +
					(panel_title_height - child_size.y) * 0.5 +
					child_layout.margin.x -
					child_layout.margin.z,
				}
				if err := layout_node(
					state,
					world,
					child_index,
					node.rect,
					position,
					true,
					child_size,
					true,
					inherited_clip,
					has_inherited_clip,
					depth + 1,
				); err != "" {
					return err
				}
				action_right = position.x - child_layout.margin.w
			}
			child_index = next_child_index
		}
	}
	if is_panel && !panel_docked && panel.collapsible && panel.collapsed {
		node.scroll_offset = 0
		node.scroll_target = 0
		node.scroll_max = 0
		node.scroll_content_height = 0
		return ""
	}
	child_clip := inherited_clip; child_has_clip := has_inherited_clip
	if is_scroll_area { if child_has_clip { child_clip = rect_intersection(child_clip, content) } else { child_clip = content }; child_has_clip = true }
	scroll_offset := node.scroll_offset
	intrinsic_size := node_intrinsic_content_size(state, world, node, content.width)
	content_bottom := intrinsic_size.y
	content_right := intrinsic_size.x
	children: [MAX_NODES]int
	child_count := 0
	total_margins := f32(0)
	total_weight := f32(0)
	fixed_main_size := f32(0)
	flex_child_count := 0
	fixed_children: [MAX_NODES]bool
	explicit_flex := false
	if is_hstack || is_vstack || is_table {
		child_index := node.first_child_node
		for child_index >= 0 {
			when ODIN_TEST {
				state.layout_child_edge_visit_count += 1
			}
			child := &state.nodes[child_index]
			next_child_index := child.next_sibling_node
			child_layout := world.ui_layouts[child.layout_index]
			if child_layout.hidden || is_panel && node_is_panel_action(world, child) {
				child_index = next_child_index
				continue
			}
			ordinal := child_count
			children[ordinal] = child_index
			child_count += 1
			if is_table {
				child_index = next_child_index
				continue
			}
			if child_layout.basis > 0 || child_layout.grow > 0 || child_layout.shrink > 0 {
				explicit_flex = true
			}
			if is_hstack {
				total_margins += child_layout.margin.w + child_layout.margin.y
			} else {
				total_margins += child_layout.margin.x + child_layout.margin.z
			}
			if child_layout.fixed_in_fill || (is_vstack && node_panel_collapsed(world, child^)) {
				fixed_children[ordinal] = true
				fixed_size := node_layout_size(world, child^, child_layout)
				fixed_child_main_size := fixed_size.y
				if is_hstack {
					fixed_child_main_size = fixed_size.x
				}
				fixed_main_size += fixed_child_main_size
				child_index = next_child_index
				continue
			}
			flex_child_count += 1
			if !child.split_weight_valid || child.split_parent != node.entity {
				child.split_weight = max(child_layout.size.y, 1)
				if is_hstack { child.split_weight = max(child_layout.size.x, 1) }
				child.split_parent = node.entity
				child.split_weight_valid = true
			}
			total_weight += child.split_weight
			child_index = next_child_index
		}
		if is_hstack || is_vstack {
			sort_stack_nodes(state, world, &children, child_count)
		}
	}
	available_main := content.height; if is_hstack { available_main = content.width }
	flex_available_main := available_main
	available_main = max(
		available_main - total_margins - gap * f32(max(child_count - 1, 0)) - fixed_main_size,
		0,
	)
	child_main_sizes: [MAX_NODES]f32
	if (is_hstack || is_vstack) && stack.fill && child_count > 0 {
		resolved: [MAX_NODES]bool
		remaining_size := available_main
		remaining_weight := total_weight
		remaining_count := flex_child_count
		effective_min := min(stack.min_size, available_main / f32(max(flex_child_count, 1)))
		for ordinal in 0 ..< child_count {
			if !fixed_children[ordinal] { continue }
			resolved[ordinal] = true
			child := state.nodes[children[ordinal]]
			child_layout := world.ui_layouts[child.layout_index]
			fixed_size := node_layout_size(world, child, child_layout)
			child_main_sizes[ordinal] = fixed_size.y
			if is_hstack {
				child_main_sizes[ordinal] = fixed_size.x
			}
		}
		for _ in 0 ..< child_count {
			resolved_one := false
			for ordinal in 0 ..< child_count {
				if resolved[ordinal] { continue }
				weight := state.nodes[children[ordinal]].split_weight
				proposed := remaining_size / f32(max(remaining_count, 1))
				if remaining_weight > 0 { proposed = remaining_size * weight / remaining_weight }
				if proposed >= effective_min { continue }
				child_main_sizes[ordinal] = effective_min
				resolved[ordinal] = true
				remaining_size = max(remaining_size - effective_min, 0)
				remaining_weight = max(remaining_weight - weight, 0)
				remaining_count -= 1
				resolved_one = true
			}
			if !resolved_one { break }
		}
		for ordinal in 0 ..< child_count {
			if resolved[ordinal] { continue }
			weight := state.nodes[children[ordinal]].split_weight
			child_main_sizes[ordinal] = remaining_size / f32(max(remaining_count, 1))
			if remaining_weight >
			   0 { child_main_sizes[ordinal] = remaining_size * weight / remaining_weight }
		}
	}
	use_flex_flow :=
		(is_hstack || is_vstack) && !stack.fill && (stack.wrap || explicit_flex) && child_count > 0
	flex_positions: [MAX_NODES]shared.Vec2
	flex_sizes: [MAX_NODES]shared.Vec2
	if use_flex_flow {
		base_sizes: [MAX_NODES]shared.Vec2
		line_starts, line_ends: [MAX_NODES]int
		line_cross_sizes: [MAX_NODES]f32
		line_count := 0
		line_start := 0
		line_main := f32(0)
		line_cross := f32(0)
		for ordinal in 0 ..< child_count {
			child := state.nodes[children[ordinal]]
			child_layout := world.ui_layouts[child.layout_index]
			size := node_layout_size(world, child, child_layout)
			if child_layout.basis > 0 {
				if is_hstack {
					size.x = child_layout.basis
				} else {
					size.y = child_layout.basis
				}
			}
			base_sizes[ordinal] = size
			main_margin := child_layout.margin.x + child_layout.margin.z
			cross_margin := child_layout.margin.w + child_layout.margin.y
			main_size := size.y
			cross_size := size.x
			if is_hstack {
				main_margin = child_layout.margin.w + child_layout.margin.y
				cross_margin = child_layout.margin.x + child_layout.margin.z
				main_size = size.x
				cross_size = size.y
			}
			next_main := main_margin + main_size
			if ordinal > line_start {
				next_main += stack.gap
			}
			if stack.wrap && ordinal > line_start && line_main + next_main > flex_available_main {
				line_starts[line_count] = line_start
				line_ends[line_count] = ordinal
				line_cross_sizes[line_count] = line_cross
				line_count += 1
				line_start = ordinal
				line_main = main_margin + main_size
				line_cross = cross_margin + cross_size
			} else {
				line_main += next_main
				line_cross = max(line_cross, cross_margin + cross_size)
			}
		}
		line_starts[line_count] = line_start
		line_ends[line_count] = child_count
		line_cross_sizes[line_count] = line_cross
		line_count += 1
		line_cross_cursor := f32(0)
		for line_index in 0 ..< line_count {
			start := line_starts[line_index]
			end := line_ends[line_index]
			used_main := stack.gap * f32(max(end - start - 1, 0))
			total_grow := f32(0)
			total_shrink := f32(0)
			for ordinal in start ..< end {
				child := state.nodes[children[ordinal]]
				child_layout := world.ui_layouts[child.layout_index]
				main_size := base_sizes[ordinal].y
				main_margin := child_layout.margin.x + child_layout.margin.z
				if is_hstack {
					main_size = base_sizes[ordinal].x
					main_margin = child_layout.margin.w + child_layout.margin.y
				}
				used_main += main_size + main_margin
				total_grow += child_layout.grow
				total_shrink += child_layout.shrink * max(main_size, 1)
			}
			free_main := flex_available_main - used_main
			resolved_main: [MAX_NODES]f32
			for ordinal in start ..< end {
				child := state.nodes[children[ordinal]]
				child_layout := world.ui_layouts[child.layout_index]
				main_size := base_sizes[ordinal].y
				if is_hstack {
					main_size = base_sizes[ordinal].x
				}
				if free_main > 0 && total_grow > 0 {
					main_size += free_main * child_layout.grow / total_grow
				}
				resolved_main[ordinal] = main_size
			}
			if free_main < 0 && total_shrink > 0 {
				shrink_resolved: [MAX_NODES]bool
				remaining_reduction := -free_main
				remaining_weight := total_shrink
				for _ in start ..< end {
					resolved_one := false
					for ordinal in start ..< end {
						if shrink_resolved[ordinal] {
							continue
						}
						child := state.nodes[children[ordinal]]
						child_layout := world.ui_layouts[child.layout_index]
						main_size := resolved_main[ordinal]
						min_main := child_layout.min_size.y
						if is_hstack {
							min_main = child_layout.min_size.x
						}
						weight := child_layout.shrink * max(main_size, 1)
						if weight <= 0 {
							shrink_resolved[ordinal] = true
							resolved_one = true
							continue
						}
						proposed_reduction := remaining_reduction * weight / remaining_weight
						if main_size - proposed_reduction >= min_main {
							continue
						}
						actual_reduction := max(main_size - min_main, 0)
						resolved_main[ordinal] = min_main
						shrink_resolved[ordinal] = true
						remaining_reduction = max(remaining_reduction - actual_reduction, 0)
						remaining_weight = max(remaining_weight - weight, 0)
						resolved_one = true
					}
					if !resolved_one {
						break
					}
				}
				for ordinal in start ..< end {
					if shrink_resolved[ordinal] {
						continue
					}
					child := state.nodes[children[ordinal]]
					child_layout := world.ui_layouts[child.layout_index]
					weight := child_layout.shrink * max(resolved_main[ordinal], 1)
					if remaining_weight > 0 {
						resolved_main[ordinal] -= remaining_reduction * weight / remaining_weight
					}
				}
			}
			for ordinal in start ..< end {
				main_size := resolved_main[ordinal]
				if is_hstack {
					base_sizes[ordinal].x = main_size
				} else {
					base_sizes[ordinal].y = main_size
				}
			}
			cross_extent := line_cross_sizes[line_index]
			if !stack.wrap {
				cross_extent = content.width
				if is_hstack {
					cross_extent = content.height
				}
			}
			main_cursor := f32(0)
			for ordinal in start ..< end {
				child := state.nodes[children[ordinal]]
				child_layout := world.ui_layouts[child.layout_index]
				size := base_sizes[ordinal]
				if is_hstack {
					y, height := resolve_aligned_axis(
						content.y + line_cross_cursor,
						cross_extent,
						size.y,
						child_layout.min_size.y,
						child_layout.position.y,
						child_layout.margin.x,
						child_layout.margin.z,
						child_layout.vertical_alignment,
						child_layout.fill_height || child_layout.vertical_alignment == .Stretch,
					)
					size.y = height
					flex_positions[ordinal] = {content.x + main_cursor + child_layout.margin.w, y}
					main_cursor += child_layout.margin.w + size.x + child_layout.margin.y
				} else {
					x, width := resolve_aligned_axis(
						content.x + line_cross_cursor,
						cross_extent,
						size.x,
						child_layout.min_size.x,
						child_layout.position.x,
						child_layout.margin.w,
						child_layout.margin.y,
						child_layout.horizontal_alignment,
						child_layout.fill_width || child_layout.horizontal_alignment == .Stretch,
					)
					size.x = width
					flex_positions[ordinal] = {x, content.y + main_cursor + child_layout.margin.x}
					main_cursor += child_layout.margin.x + size.y + child_layout.margin.z
				}
				if ordinal + 1 < end {
					main_cursor += stack.gap
				}
				flex_sizes[ordinal] = size
			}
			line_cross_cursor += cross_extent
			if line_index + 1 < line_count {
				line_cross_cursor += stack.line_gap
			}
		}
	}
	child_ordinal := 0
	table_y, table_row_height := f32(0), f32(0)
	table_columns := max(table.columns, 1)
	table_column_widths: [MAX_NODES]f32
	table_column_offsets: [MAX_NODES]f32
	table_available_width := max(
		content.width - table.column_gap * f32(max(table_columns - 1, 0)),
		0,
	)
	table_total_weight := f32(table_columns)
	if is_table && table.proportional_columns {
		table_total_weight = 0
		for column in 0 ..< table_columns {
			weight := f32(1)
			if column < child_count {
				column_node := &state.nodes[children[column]]
				column_layout := world.ui_layouts[column_node.layout_index]
				if !column_node.split_weight_valid || column_node.split_parent != node.entity {
					column_node.split_weight = max(column_layout.size.x, 1)
					column_node.split_parent = node.entity
					column_node.split_weight_valid = true
				}
				weight = column_node.split_weight
			}
			table_column_widths[column] = weight
			table_total_weight += weight
		}
	}
	table_offset := f32(0)
	for column in 0 ..< table_columns {
		if table.proportional_columns {
			table_column_widths[column] =
				table_available_width * table_column_widths[column] / max(table_total_weight, 1)
		} else {
			table_column_widths[column] = table_available_width / f32(table_columns)
		}
		table_column_offsets[column] = table_offset
		table_offset += table_column_widths[column] + table.column_gap
	}
	list_flow_children := &state.ui_project_list_flow_nodes
	if node.origin == .Editor {
		list_flow_children = &state.ui_editor_list_flow_nodes
	}
	list_flow_offset := node.list_flow_offset
	list_flow_count := node.list_flow_count
	list_flow_start := 0
	list_flow_end := list_flow_count
	virtual_content_height := f32(0)
	if is_list && list.virtualized {
		stride := list.item_height + list.gap
		if list_flow_count > 0 {
			virtual_content_height =
				f32(list_flow_count) * list.item_height + f32(list_flow_count - 1) * list.gap
		}
		virtual_scroll_max := max(virtual_content_height - content.height, 0)
		node.scroll_target = clamp(node.scroll_target, 0, virtual_scroll_max)
		node.scroll_offset = clamp(node.scroll_offset, 0, virtual_scroll_max)
		scroll_offset = node.scroll_offset
		if stride > 0 {
			list_flow_start = max(int(math.floor(scroll_offset / stride)) - list.overscan, 0)
			list_flow_end = min(
				int(math.ceil((scroll_offset + content.height) / stride)) + list.overscan,
				list_flow_count,
			)
		}
		cursor = f32(list_flow_start) * stride
	}
	child_index := node.first_child_node
	if (is_hstack || is_vstack) && child_count > 0 {
		child_index = children[0]
	}
	if is_list {
		child_index = -1
		if list_flow_start < list_flow_end {
			child_index = list_flow_children[list_flow_offset + list_flow_start]
		}
	}
	list_flow_ordinal := list_flow_start
	for child_index >= 0 {
		when ODIN_TEST {
			state.layout_child_edge_visit_count += 1
		}
		child := &state.nodes[child_index]
		next_child_index := child.next_sibling_node
		if is_hstack || is_vstack {
			next_child_index = -1
			if child_ordinal + 1 < child_count {
				next_child_index = children[child_ordinal + 1]
			}
		}
		if is_list {
			next_child_index = -1
			if list_flow_ordinal + 1 < list_flow_end {
				next_child_index = list_flow_children[list_flow_offset + list_flow_ordinal + 1]
			}
			list_flow_ordinal += 1
		}
		child_layout := world.ui_layouts[child.layout_index]
		_, child_is_dock_item := dock_item_title(world, child^)
		if child_layout.hidden ||
		   is_panel && node_is_panel_action(world, child) ||
		   is_dock_space && child_is_dock_item && child_index != dock_active_node {
			child_index = next_child_index
			continue
		}
		position: shared.Vec2
		child_flowed := false
		child_size := node_layout_size(world, child^, child_layout)
		has_child_size := false
		if child_layout.fill_width {
			child.fill_available_size.x = max(
				content.width - child_layout.margin.w - child_layout.margin.y,
				child_layout.min_size.x,
			)
			child.fill_width_valid = true
			child_size.x = child.fill_available_size.x
			if child_layout.fit_content_width && child.resolved_width_valid {
				child_size.x = max(child_size.x, child.resolved_size.x)
			}
			has_child_size = true
		}
		if child_layout.fill_height {
			child.fill_available_size.y = max(
				content.height - child_layout.margin.x - child_layout.margin.z,
				child_layout.min_size.y,
			)
			child.fill_height_valid = true
			child_size.y = child.fill_available_size.y
			if child_layout.fit_content_height && child.resolved_height_valid {
				child_size.y = max(child_size.y, child.resolved_size.y)
			}
			has_child_size = true
		}
		if is_dock_space && child_is_dock_item && child_index == dock_active_node {
			child_size = {
				max(
					content.width - child_layout.margin.w - child_layout.margin.y,
					child_layout.min_size.x,
				),
				max(
					content.height - child_layout.margin.x - child_layout.margin.z,
					child_layout.min_size.y,
				),
			}
			if child_layout.fit_content_width && child.resolved_width_valid {
				child_size.x = max(child_size.x, child.resolved_size.x)
			}
			if child_layout.fit_content_height && child.resolved_height_valid {
				child_size.y = max(child_size.y, child.resolved_size.y)
			}
			position = {content.x + child_layout.margin.w, content.y + child_layout.margin.x}
			has_child_size = true
			child_flowed = true
		} else if (is_hstack || is_vstack) && stack.fill {
			main_size := child_main_sizes[child_ordinal]
			if is_hstack {
				child_size.x = main_size
				if child_layout.vertical_alignment == .Start ||
				   child_layout.vertical_alignment == .Stretch {
					child_size.y = max(
						content.height - child_layout.margin.x - child_layout.margin.z,
						0,
					)
				}
			} else {
				child_size.y = main_size
				if child_layout.horizontal_alignment == .Start ||
				   child_layout.horizontal_alignment == .Stretch {
					child_size.x = max(
						content.width - child_layout.margin.w - child_layout.margin.y,
						0,
					)
				}
			}
			has_child_size = true
		}
		if use_flex_flow {
			child_size = flex_sizes[child_ordinal]
			position = flex_positions[child_ordinal]
			has_child_size = true
			child_flowed = true
		} else if is_table {
			column := child_ordinal % table_columns
			if column == 0 && child_ordinal > 0 {
				table_y += table_row_height + table.row_gap
				table_row_height = 0
			}
			child_size = {
				max(
					table_column_widths[column] - child_layout.margin.w - child_layout.margin.y,
					0,
				),
				child_size.y,
			}
			position = {
				content.x + table_column_offsets[column] + child_layout.margin.w,
				content.y + table_y + child_layout.margin.x,
			}
			if table.resizable_columns &&
			   child_ordinal < table_columns - 1 &&
			   child_ordinal < child_count - 1 &&
			   state.split_handle_count < MAX_NODES {
				handle_width := max(table.column_gap, 8)
				handle_rect := Rect {
					content.x + table_column_offsets[column] + table_column_widths[column],
					content.y,
					handle_width,
					content.height,
				}
				handle_rect.x += (table.column_gap - handle_width) * 0.5
				state.split_handles[state.split_handle_count] = {
					rect = handle_rect,
					before_node = child_index,
					after_node = children[child_ordinal + 1],
					horizontal = true,
					editor = node.origin == .Editor,
					min_size = table.min_column_width,
				}
				state.split_handle_count += 1
			}
			table_row_height = max(
				table_row_height,
				child_layout.margin.x + child_size.y + child_layout.margin.z,
			)
			has_child_size = true
			child_flowed = true
		} else if is_list {
			child_size.x = max(content.width - child_layout.margin.w - child_layout.margin.y, 0)
			if list.virtualized {
				child_size.y = max(
					list.item_height - child_layout.margin.x - child_layout.margin.z,
					0,
				)
			}
			position = {
				content.x + child_layout.margin.w,
				content.y + cursor + child_layout.margin.x,
			}
			if list.virtualized {
				cursor += list.item_height + list.gap
			} else {
				cursor += child_layout.margin.x + child_size.y + child_layout.margin.z + list.gap
			}
			has_child_size = true
			child_flowed = true
		} else if is_hstack {
			y, resolved_height := resolve_aligned_axis(
				content.y,
				content.height,
				child_size.y,
				child_layout.min_size.y,
				child_layout.position.y,
				child_layout.margin.x,
				child_layout.margin.z,
				child_layout.vertical_alignment,
				child_layout.fill_height ||
				(stack.fill &&
						(child_layout.vertical_alignment == .Start ||
								child_layout.vertical_alignment == .Stretch)),
			)
			child_size.y = resolved_height
			position = {content.x + cursor + child_layout.margin.w, y}
			cursor += child_layout.margin.w + child_size.x + child_layout.margin.y
			if stack.draggable &&
			   child_ordinal < child_count - 1 &&
			   state.split_handle_count < MAX_NODES {
				handle_rect := Rect{content.x + cursor, content.y, max(gap, 8), content.height}
				handle_rect.x += (gap - handle_rect.width) * 0.5
				state.split_handles[state.split_handle_count] = {
					rect = handle_rect,
					before_node = child_index,
					after_node = children[child_ordinal + 1],
					horizontal = true,
					editor = node.origin == .Editor,
					min_size = stack.min_size,
				}
				state.split_handle_count += 1
			}
			cursor += gap
			child_flowed = true
		} else if is_vstack {
			x, resolved_width := resolve_aligned_axis(
				content.x,
				content.width,
				child_size.x,
				child_layout.min_size.x,
				child_layout.position.x,
				child_layout.margin.w,
				child_layout.margin.y,
				child_layout.horizontal_alignment,
				child_layout.fill_width ||
				(stack.fill &&
						(child_layout.horizontal_alignment == .Start ||
								child_layout.horizontal_alignment == .Stretch)),
			)
			child_size.x = resolved_width
			position = {x, content.y + cursor + child_layout.margin.x}
			cursor += child_layout.margin.x + child_size.y + child_layout.margin.z
			if stack.draggable &&
			   child_ordinal < child_count - 1 &&
			   state.split_handle_count < MAX_NODES {
				handle_rect := Rect{content.x, content.y + cursor, content.width, max(gap, 8)}
				handle_rect.y += (gap - handle_rect.height) * 0.5
				state.split_handles[state.split_handle_count] = {
					rect = handle_rect,
					before_node = child_index,
					after_node = children[child_ordinal + 1],
					horizontal = false,
					editor = node.origin == .Editor,
					min_size = stack.min_size,
				}
				state.split_handle_count += 1
			}
			cursor += gap
			child_flowed = true
		}
		if is_scroll_area { position = {position.x, position.y - scroll_offset}; if !child_flowed { position = {node.rect.x + layout.padding.w + child_layout.position.x + child_layout.margin.w, content.y + child_layout.position.y + child_layout.margin.x - scroll_offset}; child_flowed = true } }
		err := layout_node(
			state,
			world,
			child_index,
			child_parent_rect,
			position,
			child_flowed,
			child_size,
			has_child_size,
			child_clip,
			child_has_clip,
			depth + 1,
		)
		if err != "" { return err }
		resolved_child_size := node_layout_size(world, state.nodes[child_index], child_layout)
		unscrolled_bottom :=
			state.nodes[child_index].rect.y +
			max(state.nodes[child_index].rect.height, resolved_child_size.y) +
			child_layout.margin.z
		if is_scroll_area { unscrolled_bottom += scroll_offset }
		content_bottom = max(content_bottom, unscrolled_bottom - content.y)
		unscrolled_right :=
			state.nodes[child_index].rect.x +
			max(state.nodes[child_index].rect.width, resolved_child_size.x) +
			child_layout.margin.y
		content_right = max(content_right, unscrolled_right - content.x)
		child_ordinal += 1
		child_index = next_child_index
	}
	if is_table &&
	   child_count > 0 { content_bottom = max(content_bottom, table_y + table_row_height) }
	if is_list && list.virtualized {
		content_bottom = max(content_bottom, virtual_content_height)
	}
	if is_scroll_area { node.scroll_content_height = max(content.height, content_bottom); node.scroll_max = max(node.scroll_content_height - content.height, 0); node.scroll_target = clamp(node.scroll_target, 0, node.scroll_max); node.scroll_offset = clamp(node.scroll_offset, 0, node.scroll_max) }
	if layout.fit_content_width || layout.fit_content_height {
		next_size := node.resolved_size
		if layout.fit_content_width {
			next_size.x = max(
				content_right + layout.padding.w + layout.padding.y,
				layout.min_size.x,
			)
			if layout.fill_width && node.fill_width_valid {
				next_size.x = max(next_size.x, node.fill_available_size.x)
			}
		}
		if layout.fit_content_height {
			next_size.y = max(
				content_bottom + layout.padding.x + layout.padding.z + panel_title_height,
				layout.min_size.y,
			)
			if layout.fill_height && node.fill_height_valid {
				next_size.y = max(next_size.y, node.fill_available_size.y)
			}
		}
		width_changed :=
			layout.fit_content_width &&
			(!node.resolved_width_valid || math.abs(node.resolved_size.x - next_size.x) > 0.01)
		height_changed :=
			layout.fit_content_height &&
			(!node.resolved_height_valid || math.abs(node.resolved_size.y - next_size.y) > 0.01)
		if width_changed || height_changed {
			node.resolved_size = next_size
			node.resolved_width_valid = node.resolved_width_valid || layout.fit_content_width
			node.resolved_height_valid = node.resolved_height_valid || layout.fit_content_height
			state.layout_size_changed = true
		}
	}
	return ""
}

scroll_target_after_wheel :: proc(target, wheel_y, speed, max_scroll: f32) -> f32 {
	return clamp(target - wheel_y * speed, 0, max_scroll)
}

smooth_scroll_step :: proc(offset, target, smoothness, delta_seconds: f32) -> f32 {
	alpha := f32(1) - math.exp(-smoothness * clamp(delta_seconds, 0, f32(0.25)))
	next := offset + (target - offset) * alpha
	if math.abs(target - next) < 0.02 { return target }
	return next
}

split_handle_pointer_cursor :: proc(handle: Split_Handle) -> Pointer_Cursor {
	if handle.horizontal { return .Horizontal_Resize }
	return .Vertical_Resize
}

split_pointer_cursor :: proc(state: ^State) -> Pointer_Cursor {
	if state == nil { return .Default }
	if state.active_split_handle >= 0 && state.active_split_handle < state.split_handle_count {
		return split_handle_pointer_cursor(state.split_handles[state.active_split_handle])
	}
	for handle in state.split_handles[:state.split_handle_count] {
		if handle.hovered { return split_handle_pointer_cursor(handle) }
	}
	return .Default
}

numeric_input_pointer_cursor :: proc(state: ^State, world: ^shared.World) -> Pointer_Cursor {
	if state == nil || world == nil {
		return .Default
	}
	if state.input_scrub_armed || state.input_scrubbing {
		return .Horizontal_Resize
	}
	return .Default
}

control_pointer_cursor :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	position: shared.Vec2,
) -> Pointer_Cursor {
	if state == nil || world == nil {
		return .Default
	}
	current := node_index
	for current >= 0 {
		node := state.nodes[current]
		entity_index := int(node.entity.index)
		if ecs.entity_is_alive(world, entity_index) &&
		   world.entities[entity_index].id == node.entity {
			entity := world.entities[entity_index]
			if entity.ui_action_index >= 0 &&
			   entity.ui_action_index < len(world.ui_actions) &&
			   world.ui_actions[entity.ui_action_index].drag_source {
				return .Move
			}
			if entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs) {
				if !world.ui_inputs[entity.ui_input_index].read_only {
					return .Text_Edit
				}
			} else if entity.ui_button_index >= 0 &&
			   entity.ui_button_index < len(world.ui_buttons) {
				return .Pointer
			} else if entity.ui_checkbox_index >= 0 &&
			   entity.ui_checkbox_index < len(world.ui_checkboxes) {
				if !world.ui_checkboxes[entity.ui_checkbox_index].read_only {
					return .Pointer
				}
			} else if entity.ui_color_picker_index >= 0 &&
			   entity.ui_color_picker_index < len(world.ui_color_pickers) {
				if !world.ui_color_pickers[entity.ui_color_picker_index].read_only {
					return .Pointer
				}
			} else if entity.ui_viewport_index >= 0 &&
			   entity.ui_viewport_index < len(world.ui_viewports) {
				if world.ui_viewports[entity.ui_viewport_index].interactive {
					return .Pointer
				}
			}
			parent_node_index := node.parent_node_index
			if parent_node_index >= 0 {
				parent := state.nodes[parent_node_index]
				parent_entity_index := int(parent.entity.index)
				if ecs.entity_is_alive(world, parent_entity_index) &&
				   world.entities[parent_entity_index].id == parent.entity {
					parent_entity := world.entities[parent_entity_index]
					if parent_entity.ui_list_index >= 0 &&
					   parent_entity.ui_list_index < len(world.ui_lists) {
						return .Pointer
					}
				}
			}
			if entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels) {
				panel := world.ui_panels[entity.ui_panel_index]
				title_height := min(max(panel.title_height, 0), node.rect.height)
				title_rect := Rect{node.rect.x, node.rect.y, node.rect.width, title_height}
				if panel.title != "" &&
				   rect_contains(title_rect, position) &&
				   (panel.movable || panel.collapsible) {
					if panel.movable {
						return .Move
					}
					return .Pointer
				}
			}
		}
		current = node.parent_node_index
	}
	return .Default
}

workspace_drag_pointer_cursor :: proc(state: ^State) -> Pointer_Cursor {
	if state == nil {
		return .Default
	}
	if state.dock_dragging {
		if state.dock_drop_space_node >= 0 || state.dock_drop_stack_node >= 0 {
			return .Move
		}
		return .Not_Allowed
	}
	for drag in state.stack_drags {
		if !drag.armed {
			continue
		}
		if !drag.dragging ||
		   drag.target_stack != (shared.Entity{}) ||
		   drag.target_dock_space != (shared.Entity{}) {
			return .Move
		}
		return .Not_Allowed
	}
	return .Default
}

current_pointer_cursor :: proc(state: ^State) -> Pointer_Cursor {
	if state == nil { return .Default }
	return state.pointer_cursor
}

dock_tab_visual_signature :: proc(state: ^State, editor: bool) -> u64 {
	signature := u64(14695981039346656037)
	for tab, index in state.dock_tabs[:state.dock_tab_count] {
		if tab.editor != editor {
			continue
		}
		value := u64(index + 1) << 3
		if tab.hovered {
			value |= 1
		}
		if tab.active {
			value |= 2
		}
		if tab.drop_target {
			value |= 4
		}
		signature = hash.fnv64a((cast([^]byte)&value)[:size_of(value)], signature)
	}
	if state.dock_drop_space_node >= 0 &&
	   state.dock_drop_space_node < state.node_count &&
	   (state.nodes[state.dock_drop_space_node].origin == .Editor) == editor {
		value := u64(state.dock_drop_space_node + 1) + (u64(state.dock_drop_space_placement) << 32)
		signature = hash.fnv64a((cast([^]byte)&value)[:size_of(value)], signature)
	}
	if state.dock_drop_stack_node >= 0 &&
	   state.dock_drop_stack_node < state.node_count &&
	   (state.nodes[state.dock_drop_stack_node].origin == .Editor) == editor {
		value: u64 =
			u64(state.dock_drop_stack_node + 1) + (u64(state.dock_drop_stack_placement) << 32)
		signature = hash.fnv64a((cast([^]byte)&value)[:size_of(value)], signature)
	}
	return signature
}

update_dock_paint_revision :: proc(state: ^State, editor: bool, previous_signature: u64) {
	if dock_tab_visual_signature(state, editor) == previous_signature {
		return
	}
	revision := &state.ui_project_paint_revision
	if editor {
		revision = &state.ui_editor_paint_revision
	}
	revision^ += 1
	if revision^ == 0 {
		revision^ = 1
	}
}

dock_space_content_rect :: proc "contextless" (
	node: Node,
	value: shared.UI_Dock_Space_Component,
) -> Rect {
	return {
		node.rect.x,
		node.rect.y + value.tab_height,
		node.rect.width,
		max(node.rect.height - value.tab_height, 0),
	}
}

dock_space_sheet_rect :: proc "contextless" (
	node: Node,
	layout: shared.UI_Layout_Component,
	value: shared.UI_Dock_Space_Component,
) -> Rect {
	return {
		node.rect.x + layout.padding.w,
		node.rect.y + layout.padding.x + value.tab_height,
		max(node.rect.width - layout.padding.w - layout.padding.y, 0),
		max(node.rect.height - layout.padding.x - layout.padding.z - value.tab_height, 0),
	}
}

dock_space_tab_strip_rect :: proc "contextless" (
	node: Node,
	layout: shared.UI_Layout_Component,
	value: shared.UI_Dock_Space_Component,
) -> Rect {
	return {
		node.rect.x + layout.padding.w,
		node.rect.y + layout.padding.x,
		max(node.rect.width - layout.padding.w - layout.padding.y, 0),
		min(value.tab_height, max(node.rect.height - layout.padding.x - layout.padding.z, 0)),
	}
}

dock_space_drop_placement :: proc(
	node: Node,
	value: shared.UI_Dock_Space_Component,
	position: shared.Vec2,
) -> shared.UI_Drop_Placement {
	content := dock_space_content_rect(node, value)
	if !rect_contains(content, position) || content.width <= 0 || content.height <= 0 {
		return .Into
	}
	best := value.split_edge_fraction + 1
	placement := shared.UI_Drop_Placement.Into
	if value.split_horizontal && content.width >= value.split_min_size * 2 + value.split_gap {
		left := (position.x - content.x) / content.width
		if left <= value.split_edge_fraction && left < best {
			best = left
			placement = .Left
		}
		right := (content.x + content.width - position.x) / content.width
		if right <= value.split_edge_fraction && right < best {
			best = right
			placement = .Right
		}
	}
	if value.split_vertical && content.height >= value.split_min_size * 2 + value.split_gap {
		above := (position.y - content.y) / content.height
		if above <= value.split_edge_fraction && above < best {
			best = above
			placement = .Above
		}
		below := (content.y + content.height - position.y) / content.height
		if below <= value.split_edge_fraction && below < best {
			placement = .Below
		}
	}
	return placement
}

dock_space_split_preview_rect :: proc "contextless" (
	node: Node,
	value: shared.UI_Dock_Space_Component,
	placement: shared.UI_Drop_Placement,
) -> Rect {
	content := dock_space_content_rect(node, value)
	switch placement {
		case .Left, .Right:
			available := max(content.width - value.split_gap, 0)
			extent := clamp(
				available * value.split_ratio,
				value.split_min_size,
				max(available - value.split_min_size, value.split_min_size),
			)
			if placement == .Left {
				content.width = extent
			} else {
				content.x += content.width - extent
				content.width = extent
			}
		case .Above, .Below:
			available := max(content.height - value.split_gap, 0)
			extent := clamp(
				available * value.split_ratio,
				value.split_min_size,
				max(available - value.split_min_size, value.split_min_size),
			)
			if placement == .Above {
				content.height = extent
			} else {
				content.y += content.height - extent
				content.height = extent
			}
		case .None, .Before, .Into, .After:
	}
	return content
}

update_dock_interaction :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	editor: bool,
) -> (
	layout_changed, captured: bool,
) {
	previous_signature := dock_tab_visual_signature(state, editor)
	for &tab in state.dock_tabs[:state.dock_tab_count] {
		if tab.editor == editor {
			tab.hovered = false
			tab.drop_target = false
		}
	}
	previous_down := state.dock_previous_primary_down
	if editor {
		previous_down = state.editor_dock_previous_primary_down
	}
	if !pointer.available {
		if state.active_dock_tab >= 0 && state.active_dock_editor == editor {
			state.active_dock_tab = -1
			state.dock_dragging = false
			state.dock_drop_space_node = -1
			state.dock_drop_space_placement = .None
			state.dock_drop_stack_node = -1
			state.dock_drop_stack_target = {}
			state.dock_drop_stack_placement = .None
		}
		if editor {
			state.editor_dock_previous_primary_down = false
		} else {
			state.dock_previous_primary_down = false
		}
		update_dock_paint_revision(state, editor, previous_signature)
		return
	}
	hit := -1
	for tab, index in state.dock_tabs[:state.dock_tab_count] {
		if tab.editor == editor && rect_contains(tab.rect, pointer.position) {
			hit = index
		}
	}
	if hit >= 0 {
		state.dock_tabs[hit].hovered = true
	}
	just_pressed := pointer_press_started(pointer, previous_down)
	if just_pressed && hit >= 0 {
		tab := state.dock_tabs[hit]
		space := &state.nodes[tab.space_node]
		item := state.nodes[tab.item_node]
		if space.dock_space_index >= 0 && space.dock_space_index < len(world.ui_dock_spaces) {
			value := world.ui_dock_spaces[space.dock_space_index]
			item_index := int(item.entity.index)
			if item_index >= 0 && item_index < len(world.entities) {
				item_uuid := world.entities[item_index].uuid
				if value.active != item_uuid {
					value.active = item_uuid
					layout_changed = ecs.set_ui_dock_space(world, int(space.entity.index), value)
				}
				_ = mark_ui_event(state, world, .Activated, item.entity, pointer.position)
			}
		}
		state.active_dock_tab = hit
		state.active_dock_editor = editor
		state.dock_drag_start = pointer.position
		state.dock_dragging = false
		captured = true
	}
	if pointer.primary_down &&
	   state.active_dock_editor == editor &&
	   state.active_dock_tab >= 0 &&
	   state.active_dock_tab < state.dock_tab_count {
		active_tab := &state.dock_tabs[state.active_dock_tab]
		active_tab.hovered = true
		item := state.nodes[active_tab.item_node]
		movable := dock_item_movable(world, item)
		delta := shared.Vec2 {
			pointer.position.x - state.dock_drag_start.x,
			pointer.position.y - state.dock_drag_start.y,
		}
		if movable && delta.x * delta.x + delta.y * delta.y >= 25 {
			state.dock_dragging = true
		}
		if state.dock_dragging {
			target_space := -1
			target_space_placement := shared.UI_Drop_Placement.Into
			target_stack := -1
			target_stack_item: shared.Entity
			target_stack_placement := shared.UI_Drop_Placement.None
			target_paint_order := -1
			for &candidate, candidate_index in state.nodes[:state.node_count] {
				if (candidate.origin == .Editor) != editor ||
				   !candidate.laid_out ||
				   !rect_contains(candidate.rect, pointer.position) ||
				   candidate.paint_order < target_paint_order {
					continue
				}
				if candidate.dock_space_index >= 0 &&
				   candidate.dock_space_index < len(world.ui_dock_spaces) &&
				   world.ui_dock_spaces[candidate.dock_space_index].draggable {
					target_space = candidate_index
					target_space_placement = dock_space_drop_placement(
						candidate,
						world.ui_dock_spaces[candidate.dock_space_index],
						pointer.position,
					)
					target_stack = -1
					target_paint_order = candidate.paint_order
					continue
				}
				if item.panel_index < 0 || item.panel_index >= len(world.ui_panels) {
					continue
				}
				if target_space >= 0 &&
				   ui_dock_split_is_directional(target_space_placement) &&
				   ui_node_descends_from(state, candidate_index, target_space) {
					continue
				}
				candidate_stack, horizontal, stack_ok := stack_component_for_node(world, candidate)
				if !stack_ok ||
				   !candidate_stack.reorderable ||
				   candidate.panel_index >= 0 &&
					   !node_is_docked_panel(state, world, candidate_index) {
					continue
				}
				target_space = -1
				target_stack = candidate_index
				target_stack_item = {}
				target_stack_placement = .After
				target_paint_order = candidate.paint_order
				child := candidate.first_child_node
				for child >= 0 {
					stack_item := state.nodes[child]
					if stack_item.entity != item.entity &&
					   stack_item.laid_out &&
					   rect_contains(stack_item.rect, pointer.position) {
						target_stack_item = stack_item.entity
						target_stack_placement = .Before
						if horizontal &&
							   pointer.position.x >=
								   stack_item.rect.x + stack_item.rect.width * 0.5 ||
						   !horizontal &&
							   pointer.position.y >=
								   stack_item.rect.y + stack_item.rect.height * 0.5 {
							target_stack_placement = .After
						}
						break
					}
					child = stack_item.next_sibling_node
				}
			}
			if target_space >= 0 &&
			   target_space_placement == .Into &&
			   item.panel_index >= 0 &&
			   item.panel_index < len(world.ui_panels) {
				tab_stack := dock_tab_reorderable_stack_at_pointer(
					state,
					world,
					target_space,
					pointer.position,
					active_tab.item_node,
					true,
				)
				if tab_stack >= 0 {
					target_space = -1
					target_space_placement = .None
					target_stack = tab_stack
					target_stack_item = {}
					target_stack_placement = .After
				}
			}
			state.dock_drop_space_node = target_space
			state.dock_drop_space_placement = target_space_placement
			state.dock_drop_stack_node = target_stack
			state.dock_drop_stack_target = target_stack_item
			state.dock_drop_stack_placement = target_stack_placement
			if target_space >= 0 && target_space_placement == .Into {
				for &tab in state.dock_tabs[:state.dock_tab_count] {
					if tab.space_node == target_space {
						tab.drop_target = true
					}
				}
			}
		}
		captured = true
	} else if !pointer.primary_down &&
	   state.active_dock_editor == editor &&
	   state.active_dock_tab >= 0 &&
	   state.active_dock_tab < state.dock_tab_count {
		active_tab := state.dock_tabs[state.active_dock_tab]
		if state.dock_dragging &&
		   state.dock_drop_space_node >= 0 &&
		   ui_dock_split_is_directional(state.dock_drop_space_placement) {
			source_space := state.nodes[active_tab.space_node]
			target_space := state.nodes[state.dock_drop_space_node]
			item := state.nodes[active_tab.item_node]
			layout_changed =
				apply_dock_split_drop(
					state,
					world,
					item.entity,
					target_space.entity,
					{},
					source_space.entity,
					state.dock_drop_space_placement,
					pointer.position,
				) ||
				layout_changed
		} else if state.dock_dragging &&
		   state.dock_drop_space_node >= 0 &&
		   state.dock_drop_space_placement == .Into {
			source_space := state.nodes[active_tab.space_node]
			target_space := state.nodes[state.dock_drop_space_node]
			item := state.nodes[active_tab.item_node]
			if target_space.entity != source_space.entity {
				item_entity_index := int(item.entity.index)
				target_entity_index := int(target_space.entity.index)
				source_entity_index := int(source_space.entity.index)
				if item_entity_index >= 0 &&
				   item_entity_index < len(world.entities) &&
				   target_entity_index >= 0 &&
				   target_entity_index < len(world.entities) {
					item_uuid := world.entities[item_entity_index].uuid
					layout := world.ui_layouts[item.layout_index]
					layout.parent = world.entities[target_entity_index].uuid
					if ecs.set_ui_layout(world, item_entity_index, layout) {
						target_value := world.ui_dock_spaces[target_space.dock_space_index]
						target_value.active = item_uuid
						_ = ecs.set_ui_dock_space(world, target_entity_index, target_value)
						if source_entity_index >= 0 && source_entity_index < len(world.entities) {
							source_value := world.ui_dock_spaces[source_space.dock_space_index]
							source_value.active = {}
							_ = ecs.set_ui_dock_space(world, source_entity_index, source_value)
						}
						interaction := ecs.ensure_ui_state(world, target_entity_index)
						if interaction != nil {
							interaction.changed = true
							interaction.change_revision += 1
							interaction.drag_source = item_uuid
							interaction.drop_target = world.entities[target_entity_index].uuid
							interaction.drop_placement = .Into
							interaction.drop_revision += 1
							ecs.mark_ui_state_transient(world, target_entity_index)
						}
						append_ui_event(
							state,
							{
								kind = .Dropped,
								entity = target_space.entity,
								source = item.entity,
								target = target_space.entity,
								drop_placement = .Into,
								position = pointer.position,
							},
						)
					}
				}
			}
		} else if state.dock_dragging && state.dock_drop_stack_node >= 0 {
			source_space := state.nodes[active_tab.space_node]
			target_stack := state.nodes[state.dock_drop_stack_node]
			item := state.nodes[active_tab.item_node]
			item_entity_index := int(item.entity.index)
			target_entity_index := int(target_stack.entity.index)
			source_entity_index := int(source_space.entity.index)
			if item.panel_index >= 0 &&
			   item.panel_index < len(world.ui_panels) &&
			   item_entity_index >= 0 &&
			   item_entity_index < len(world.entities) &&
			   target_entity_index >= 0 &&
			   target_entity_index < len(world.entities) {
				item_uuid := world.entities[item_entity_index].uuid
				layout := world.ui_layouts[item.layout_index]
				layout.parent = world.entities[target_entity_index].uuid
				if ecs.set_ui_layout(world, item_entity_index, layout) {
					layout_changed =
						normalize_stack_order(
							state,
							world,
							state.dock_drop_stack_node,
							item.entity,
							state.dock_drop_stack_target,
							state.dock_drop_stack_placement,
						) ||
						layout_changed
					if source_entity_index >= 0 && source_entity_index < len(world.entities) {
						source_value := world.ui_dock_spaces[source_space.dock_space_index]
						source_value.active = {}
						_ = ecs.set_ui_dock_space(world, source_entity_index, source_value)
					}
					interaction := ecs.ensure_ui_state(world, target_entity_index)
					if interaction != nil {
						interaction.changed = true
						interaction.change_revision += 1
						interaction.drag_source = item_uuid
						interaction.drop_target = world.entities[target_entity_index].uuid
						interaction.drop_placement = state.dock_drop_stack_placement
						interaction.drop_revision += 1
						ecs.mark_ui_state_transient(world, target_entity_index)
					}
					append_ui_event(
						state,
						{
							kind = .Dropped,
							entity = target_stack.entity,
							source = item.entity,
							target = state.dock_drop_stack_target,
							drop_placement = state.dock_drop_stack_placement,
							position = pointer.position,
						},
					)
				}
			}
		}
		state.active_dock_tab = -1
		state.dock_dragging = false
		state.dock_drop_space_node = -1
		state.dock_drop_space_placement = .None
		state.dock_drop_stack_node = -1
		state.dock_drop_stack_target = {}
		state.dock_drop_stack_placement = .None
		captured = true
	}
	if editor {
		state.editor_dock_previous_primary_down = pointer.primary_down
	} else {
		state.dock_previous_primary_down = pointer.primary_down
	}
	update_dock_paint_revision(state, editor, previous_signature)
	return
}

update_split_interaction :: proc(state: ^State, pointer: Pointer_Input, editor: bool) -> bool {
	previous_visual_signature := split_handle_visual_signature(state, editor)
	for &handle in state.split_handles[:state.split_handle_count] { if handle.editor == editor { handle.hovered = false; handle.active = false } }
	changed := false
	if !pointer.available {
		if state.active_split_handle >= 0 &&
		   state.active_split_editor == editor { state.active_split_handle = -1 }
		if editor { state.editor_split_previous_primary_down = false } else { state.split_previous_primary_down = false }
		update_split_handle_paint_revision(state, editor, previous_visual_signature)
		return false
	}
	hit := -1
	for handle, index in state.split_handles[:state.split_handle_count] { if handle.editor == editor && rect_contains(handle.rect, pointer.position) { hit = index } }
	if hit >= 0 { state.split_handles[hit].hovered = true }
	previous_down := state.split_previous_primary_down
	if editor { previous_down = state.editor_split_previous_primary_down }
	just_pressed := pointer_press_started(pointer, previous_down)
	if just_pressed && hit >= 0 {
		state.active_split_handle = hit
		state.active_split_editor = editor
		handle := state.split_handles[hit]
		parent := state.nodes[handle.before_node].split_parent
		for &node in state.nodes[:state.node_count] {
			if !node.split_weight_valid || node.split_parent != parent { continue }
			node.split_weight = node.rect.height
			if handle.horizontal { node.split_weight = node.rect.width }
		}
		state.split_drag_pointer =
			pointer.position.y; if handle.horizontal { state.split_drag_pointer = pointer.position.x }
	}
	if pointer.primary_down &&
	   state.active_split_editor == editor &&
	   state.active_split_handle >= 0 &&
	   state.active_split_handle < state.split_handle_count {
		handle := &state.split_handles[state.active_split_handle]; handle.active = true
		position := pointer.position.y; if handle.horizontal { position = pointer.position.x }
		delta := position - state.split_drag_pointer
		before := &state.nodes[handle.before_node]; after := &state.nodes[handle.after_node]
		before_size :=
			before.rect.height; after_size := after.rect.height; if handle.horizontal { before_size = before.rect.width; after_size = after.rect.width }
		min_size := max(handle.min_size, 1)
		applied := clamp(delta, -before_size + min_size, after_size - min_size)
		if math.abs(applied) >
		   0.0001 { before.split_weight = max(before_size + applied, min_size); after.split_weight = max(after_size - applied, min_size); state.split_drag_pointer += applied; changed = true }
	} else if !pointer.primary_down &&
	   state.active_split_editor == editor { state.active_split_handle = -1 }
	if editor { state.editor_split_previous_primary_down = pointer.primary_down } else { state.split_previous_primary_down = pointer.primary_down }
	update_split_handle_paint_revision(state, editor, previous_visual_signature)
	return changed
}

split_handle_visual_signature :: proc(state: ^State, editor: bool) -> u64 {
	if state == nil {
		return 0
	}
	signature := u64(14695981039346656037)
	for handle, index in state.split_handles[:state.split_handle_count] {
		if handle.editor != editor {
			continue
		}
		value := u64(index + 1) << 2
		if handle.hovered {
			value |= 1
		}
		if handle.active {
			value |= 2
		}
		signature = hash.fnv64a((cast([^]byte)&value)[:size_of(value)], signature)
	}
	return signature
}

update_split_handle_paint_revision :: proc(state: ^State, editor: bool, previous_signature: u64) {
	if state == nil || split_handle_visual_signature(state, editor) == previous_signature {
		return
	}
	revision := &state.ui_project_paint_revision
	if editor {
		revision = &state.ui_editor_paint_revision
	}
	revision^ += 1
	if revision^ == 0 {
		revision^ = 1
	}
}

append_split_handles :: proc(state: ^State, editor: bool) -> string {
	for handle in state.split_handles[:state.split_handle_count] {
		if handle.editor != editor { continue }
		if !handle.hovered && !handle.active { continue }
		color := shared.Vec4 {
			0.42,
			0.46,
			0.54,
			0.55,
		}; if handle.active { color = {0.12, 0.74, 0.62, 0.8} }
		rect := handle.rect
		if handle.horizontal { rect.x = rect.x + rect.width * 0.5 - 0.75; rect.width = 1.5 } else { rect.y = rect.y + rect.height * 0.5 - 0.75; rect.height = 1.5 }
		if err := append_paint(state, {kind = .Panel, rect = rect, color = color});
		   err != "" { return err }
	}
	return ""
}

update_scroll_areas :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	delta_seconds: f32,
	editor: bool,
) -> bool {
	changed := false
	if pointer.available && pointer.wheel_y != 0 {
		hit := -1; highest_order := -1
		for node, index in state.nodes[:state.node_count] {
			if (node.origin == .Editor) != editor { continue }
			if !node.laid_out { continue }
			if node.scroll_area_index < 0 ||
			   node.scroll_area_index >= len(world.ui_scroll_areas) ||
			   node.scroll_max <= 0 { continue }
			if node_pointer_contains(node, pointer.position) &&
			   node.paint_order >= highest_order { hit = index; highest_order = node.paint_order }
		}
		if hit >=
		   0 { node := &state.nodes[hit]; component := world.ui_scroll_areas[node.scroll_area_index]; node.scroll_target = scroll_target_after_wheel(node.scroll_target, pointer.wheel_y, component.scroll_speed, node.scroll_max) }
	}
	for &node in state.nodes[:state.node_count] {
		if (node.origin == .Editor) != editor { continue }
		if !node.laid_out { continue }
		if node.scroll_area_index < 0 ||
		   node.scroll_area_index >= len(world.ui_scroll_areas) { continue }
		component := world.ui_scroll_areas[node.scroll_area_index]
		next := smooth_scroll_step(
			node.scroll_offset,
			node.scroll_target,
			component.smoothness,
			delta_seconds,
		)
		if math.abs(next - node.scroll_offset) >
		   0.0001 { node.scroll_offset = next; changed = true }
	}
	return changed
}

viewport_node_at_pointer :: proc(
	state: ^State,
	world: ^shared.World,
	point: shared.Vec2,
	editor: bool,
) -> int {
	hit := -1
	highest_order := -1
	for index in state.viewport_node_indices[:state.viewport_node_count] {
		node := state.nodes[index]
		if (node.origin == .Editor) != editor ||
		   !node.laid_out ||
		   node.viewport_index < 0 ||
		   node.viewport_index >= len(world.ui_viewports) {
			continue
		}
		component := world.ui_viewports[node.viewport_index]
		if component.interactive &&
		   node_pointer_contains(node, point) &&
		   node.paint_order >= highest_order {
			hit = index
			highest_order = node.paint_order
		}
	}
	return hit
}

update_viewport_interaction :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	editor: bool,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	previous_down := state.previous_primary_down
	if editor {
		previous_down = state.editor_previous_primary_down
	}
	hit := -1
	if pointer.available {
		hit = viewport_node_at_pointer(state, world, pointer.position, editor)
	}
	wheel_consumed := hit >= 0 && pointer.wheel_y != 0
	if wheel_consumed {
		node := &state.nodes[hit]
		component := world.ui_viewports[node.viewport_index]
		component.distance *= math.exp(pointer.wheel_y * -0.12)
		component.distance = clamp(component.distance, f32(1.1), f32(20))
		_ = ecs.set_ui_viewport(world, int(node.entity.index), component)
		_ = mark_ui_event(
			state,
			world,
			.Changed,
			node.entity,
			pointer.position,
			paint_changed = false,
		)
		_ = mark_ui_event(
			state,
			world,
			.Submitted,
			node.entity,
			pointer.position,
			paint_changed = false,
		)
	}
	if pointer_press_started(pointer, previous_down) && hit >= 0 {
		node := state.nodes[hit]
		state.viewport_drag_entity = node.entity
		state.viewport_drag_editor = editor
		state.viewport_drag_active = true
		state.viewport_drag_position = pointer.position
	}
	if state.viewport_drag_active && state.viewport_drag_editor == editor {
		if !pointer.available || !pointer.primary_down {
			_ = mark_ui_event(
				state,
				world,
				.Submitted,
				state.viewport_drag_entity,
				pointer.position,
				paint_changed = false,
			)
			state.viewport_drag_active = false
			state.viewport_drag_entity = {}
		} else {
			node_index := find_node(state, state.viewport_drag_entity)
			if node_index < 0 {
				state.viewport_drag_active = false
				state.viewport_drag_entity = {}
			} else {
				node := &state.nodes[node_index]
				if node.viewport_index >= 0 && node.viewport_index < len(world.ui_viewports) {
					delta := shared.Vec2 {
						pointer.position.x - state.viewport_drag_position.x,
						pointer.position.y - state.viewport_drag_position.y,
					}
					if delta.x != 0 || delta.y != 0 {
						component := world.ui_viewports[node.viewport_index]
						component.orbit.x = clamp(
							component.orbit.x + delta.y * 0.012,
							f32(-1.45),
							f32(1.45),
						)
						component.orbit.y += delta.x * 0.012
						_ = ecs.set_ui_viewport(world, int(node.entity.index), component)
						_ = mark_ui_event(
							state,
							world,
							.Changed,
							node.entity,
							pointer.position,
							paint_changed = false,
						)
					}
					state.viewport_drag_position = pointer.position
				}
			}
		}
	}
	return wheel_consumed
}

color_picker_rgb_to_hsv :: proc(rgb: shared.Vec3) -> shared.Vec3 {
	maximum := max(rgb.x, max(rgb.y, rgb.z))
	minimum := min(rgb.x, min(rgb.y, rgb.z))
	delta := maximum - minimum
	hue := f32(0)
	if delta > 0.000001 {
		if maximum == rgb.x {
			hue = (rgb.y - rgb.z) / delta
			if hue < 0 {
				hue += 6
			}
		} else if maximum == rgb.y {
			hue = (rgb.z - rgb.x) / delta + 2
		} else {
			hue = (rgb.x - rgb.y) / delta + 4
		}
		hue /= 6
	}
	saturation := f32(0)
	if maximum > 0 {
		saturation = delta / maximum
	}
	return {hue, saturation, maximum}
}

color_picker_hsv_to_rgb :: proc(hsv: shared.Vec3) -> shared.Vec3 {
	hue := hsv.x - math.floor(hsv.x)
	sector := hue * 6
	index := int(math.floor(sector))
	fraction := sector - f32(index)
	p := hsv.z * (1 - hsv.y)
	q := hsv.z * (1 - hsv.y * fraction)
	t := hsv.z * (1 - hsv.y * (1 - fraction))
	switch index % 6 {
		case 0:
			return {hsv.z, t, p}
		case 1:
			return {q, hsv.z, p}
		case 2:
			return {p, hsv.z, t}
		case 3:
			return {p, q, hsv.z}
		case 4:
			return {t, p, hsv.z}
		case:
			return {hsv.z, p, q}
	}
}

color_picker_rects :: proc(
	rect: Rect,
	picker: shared.UI_Color_Picker_Component,
) -> (
	sv, hue, alpha, exposure: Rect,
) {
	track_count := 1
	if picker.show_alpha {
		track_count += 1
	}
	if picker.hdr && picker.maximum_exposure > 0 {
		track_count += 1
	}
	tracks_height := f32(track_count) * picker.track_height
	gaps_height := f32(track_count) * picker.gap
	sv_height := max(rect.height - tracks_height - gaps_height, picker.track_height)
	sv = {rect.x, rect.y, rect.width, sv_height}
	y := sv.y + sv.height + picker.gap
	hue = {rect.x, y, rect.width, picker.track_height}
	y += picker.track_height + picker.gap
	if picker.show_alpha {
		alpha = {rect.x, y, rect.width, picker.track_height}
		y += picker.track_height + picker.gap
	}
	if picker.hdr && picker.maximum_exposure > 0 {
		exposure = {rect.x, y, rect.width, picker.track_height}
	}
	return
}

color_picker_part_at :: proc(
	rect: Rect,
	picker: shared.UI_Color_Picker_Component,
	position: shared.Vec2,
) -> Color_Picker_Part {
	sv, hue, alpha, exposure := color_picker_rects(rect, picker)
	if rect_contains(sv, position) {
		return .Saturation_Value
	}
	if rect_contains(hue, position) {
		return .Hue
	}
	if picker.show_alpha && rect_contains(alpha, position) {
		return .Alpha
	}
	if picker.hdr && picker.maximum_exposure > 0 && rect_contains(exposure, position) {
		return .Exposure
	}
	return .None
}

update_color_picker_value :: proc(
	world: ^shared.World,
	node: ^Node,
	part: Color_Picker_Part,
	position: shared.Vec2,
) -> bool {
	if node == nil ||
	   node.color_picker_index < 0 ||
	   node.color_picker_index >= len(world.ui_color_pickers) {
		return false
	}
	picker := world.ui_color_pickers[node.color_picker_index]
	if picker.read_only {
		return false
	}
	sv, hue_rect, alpha_rect, exposure_rect := color_picker_rects(node.rect, picker)
	scale := math.pow(f32(2), picker.exposure)
	base := shared.Vec3{picker.value.x / scale, picker.value.y / scale, picker.value.z / scale}
	hsv := color_picker_rgb_to_hsv(base)
	switch part {
		case .Saturation_Value:
			hsv.y = clamp((position.x - sv.x) / max(sv.width, 1), f32(0), f32(1))
			hsv.z = 1 - clamp((position.y - sv.y) / max(sv.height, 1), f32(0), f32(1))
		case .Hue:
			hsv.x = clamp(
				(position.x - hue_rect.x) / max(hue_rect.width, 1),
				f32(0),
				f32(0.999999),
			)
		case .Alpha:
			picker.value.w = clamp(
				(position.x - alpha_rect.x) / max(alpha_rect.width, 1),
				f32(0),
				f32(1),
			)
		case .Exposure:
			picker.exposure =
				clamp(
					(position.x - exposure_rect.x) / max(exposure_rect.width, 1),
					f32(0),
					f32(1),
				) *
				picker.maximum_exposure
			scale = math.pow(f32(2), picker.exposure)
		case .None:
			return false
	}
	if part == .Saturation_Value || part == .Hue || part == .Exposure {
		rgb := color_picker_hsv_to_rgb(hsv)
		picker.value.x = rgb.x * scale
		picker.value.y = rgb.y * scale
		picker.value.z = rgb.z * scale
	}
	if picker == world.ui_color_pickers[node.color_picker_index] {
		return false
	}
	entity_index := int(node.entity.index)
	if !ecs.set_ui_color_picker(world, entity_index, picker) {
		return false
	}
	_ = ecs.mark_ui_changed(world, entity_index)
	return true
}

update_color_picker_interaction :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	pressed: shared.Entity,
	press_started, press_released, editor: bool,
) {
	if state == nil || world == nil {
		return
	}
	if press_started && pressed != (shared.Entity{}) {
		node_index := find_node(state, pressed)
		if node_index >= 0 {
			node := &state.nodes[node_index]
			if node.color_picker_index >= 0 &&
			   node.color_picker_index < len(world.ui_color_pickers) {
				picker := world.ui_color_pickers[node.color_picker_index]
				part := color_picker_part_at(node.rect, picker, pointer.position)
				if !picker.read_only && part != .None {
					state.color_picker_drag_entity = pressed
					state.color_picker_drag_part = part
					state.color_picker_drag_editor = editor
					state.color_picker_drag_active = true
				}
			}
		}
	}
	if !state.color_picker_drag_active || state.color_picker_drag_editor != editor {
		return
	}
	node_index := find_node(state, state.color_picker_drag_entity)
	if node_index < 0 || !pointer.available {
		state.color_picker_drag_active = false
		state.color_picker_drag_entity = {}
		state.color_picker_drag_part = .None
		return
	}
	if pointer.primary_down {
		if update_color_picker_value(
			world,
			&state.nodes[node_index],
			state.color_picker_drag_part,
			pointer.position,
		) {
			append_ui_event(state, {kind = .Changed, entity = state.color_picker_drag_entity})
		}
	}
	if press_released {
		_ = mark_ui_event(
			state,
			world,
			.Submitted,
			state.color_picker_drag_entity,
			pointer.position,
		)
		state.color_picker_drag_active = false
		state.color_picker_drag_entity = {}
		state.color_picker_drag_part = .None
	}
}

has_text_focus :: proc(state: ^State) -> bool {
	return state != nil && state.has_focused_input
}

clear_input_focus :: proc(state: ^State) {
	if state == nil { return }
	delete(state.input_original_text)
	state.input_original_text = ""
	state.has_focused_input = false
	state.focused_input = {}
	state.focused_input_editor = false
	state.focused_editor_input_binding = {}
	state.has_focused_editor_input_binding = false
	state.input_cursor = 0
	state.input_anchor = 0
	state.input_scroll_x = 0
	state.input_has_original_number = false
	state.input_valid = true
	state.input_scrub_armed = false
	state.input_scrubbing = false
}

blur_input_edit :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || !state.has_focused_input {
		return
	}
	entity_index := int(state.focused_input.index)
	if entity_index >= 0 && entity_index < len(world.entities) {
		entity := world.entities[entity_index]
		if entity.alive &&
		   entity.id == state.focused_input &&
		   entity.ui_input_index >= 0 &&
		   entity.ui_input_index < len(world.ui_inputs) {
			input := world.ui_inputs[entity.ui_input_index]
			if input.numeric {
				if input.text != state.input_original_text {
					cancel_input_edit(state, world)
				}
			} else if !finish_input_edit(state, world) {
				cancel_input_edit(state, world)
			}
		}
	}
	clear_input_focus(state)
}

focus_input :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	if state == nil || world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) { return }
	delete(state.input_original_text)
	state.input_original_text, _ = strings.clone(world.ui_inputs[entity.ui_input_index].text)
	state.focused_input = entity.id
	state.has_focused_input = true
	state.focused_input_editor = entity.origin == .Editor
	state.focused_editor_input_binding = {}
	state.has_focused_editor_input_binding = false
	if state.focused_input_editor &&
	   entity.editor_ui_index >= 0 &&
	   entity.editor_ui_index < len(world.editor_uis) {
		state.focused_editor_input_binding = world.editor_uis[entity.editor_ui_index]
		state.has_focused_editor_input_binding = true
	}
	state.input_anchor = 0
	state.input_cursor = len(world.ui_inputs[entity.ui_input_index].text)
	state.input_scroll_x = 0
	state.input_blink_elapsed = 0
	state.input_valid = true
	state.input_scrub_armed = false
	state.input_scrubbing = false
	state.input_has_original_number = false
	input := world.ui_inputs[entity.ui_input_index]
	if input.numeric {
		state.input_original_number = input.number
		state.input_has_original_number = true
	}
}

handle_input_press :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
) {
	input_entity := pressed
	index := int(pressed.index)
	if index < 0 || index >= len(world.entities) { return }
	entity := world.entities[index]
	if !entity.alive || entity.id != pressed {
		blur_input_edit(state, world)
		return
	}
	for entity.ui_input_index < 0 {
		if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
			blur_input_edit(state, world)
			return
		}
		parent := world.ui_layouts[entity.ui_layout_index].parent
		parent_index := find_parent_entity(world, parent, entity.origin)
		if parent_index < 0 || parent_index >= len(world.entities) {
			blur_input_edit(state, world)
			return
		}
		index = parent_index
		entity = world.entities[index]
		input_entity = entity.id
	}
	if state.has_focused_input {
		if state.focused_input == input_entity {
			state.input_anchor = 0
			state.input_cursor = len(world.ui_inputs[entity.ui_input_index].text)
			input := world.ui_inputs[entity.ui_input_index]
			if input.numeric && input.draggable && !input.read_only {
				state.input_scrub_armed = state.input_has_original_number
				state.input_scrub_start_x = position.x
				state.input_scrub_start_number = state.input_original_number
			}
			return
		}
		blur_input_edit(state, world)
	}
	focus_input(state, world, index)
	input := world.ui_inputs[entity.ui_input_index]
	node_index := find_node(state, entity.id)
	if input.numeric && input.draggable && !input.read_only && node_index >= 0 {
		state.input_scrub_armed = state.input_has_original_number
		state.input_scrub_start_x = position.x
		state.input_scrub_start_number = state.input_original_number
	}
}

input_selection :: proc(state: ^State) -> (start, end: int) {
	return min(state.input_anchor, state.input_cursor), max(state.input_anchor, state.input_cursor)
}

replace_input_selection :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	input: ^shared.UI_Input_Component,
	replacement: string,
) -> bool {
	start, end := input_selection(state)
	start = clamp(start, 0, len(input.text))
	end = clamp(end, start, len(input.text))
	parts := [3]string{input.text[:start], replacement, input.text[end:]}
	next, err := strings.concatenate(parts[:])
	if err != nil { return false }
	value := input^
	value.text = next
	if !ecs.set_ui_input(world, entity_index, value) {
		delete(next)
		return false
	}
	delete(next)
	state.input_cursor = start + len(replacement)
	state.input_anchor = state.input_cursor
	state.input_blink_elapsed = 0
	return true
}

single_line_ascii :: proc(value: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for byte in transmute([]u8)value {
		if byte >= 32 && byte <= 126 { strings.write_byte(&builder, byte) }
	}
	result, _ := strings.clone(strings.to_string(builder))
	return result
}

ui_numeric_valid :: proc(input: shared.UI_Input_Component, number: f32) -> bool {
	if !input.numeric || math.is_nan(number) || math.is_inf(number) {
		return false
	}
	if input.has_minimum && number < input.minimum {
		return false
	}
	if input.has_maximum && number > input.maximum {
		return false
	}
	return true
}

numeric_input_text_valid :: proc(input: shared.UI_Input_Component) -> bool {
	number, ok := strconv.parse_f32(strings.trim_space(input.text))
	return ok && ui_numeric_valid(input, number)
}

apply_numeric_input :: proc(state: ^State, world: ^shared.World, entity_index: int) -> bool {
	if entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) {
		return false
	}
	input := &world.ui_inputs[entity.ui_input_index]
	number, ok := strconv.parse_f32(strings.trim_space(input.text))
	if !ok || !ui_numeric_valid(input^, number) {
		return false
	}
	input.number = number
	return true
}

finish_input_edit :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || world == nil || !state.has_focused_input {
		return true
	}
	entity_index := int(state.focused_input.index)
	if entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != state.focused_input ||
	   entity.ui_input_index < 0 ||
	   entity.ui_input_index >= len(world.ui_inputs) {
		return false
	}
	input := &world.ui_inputs[entity.ui_input_index]
	if input.numeric {
		number, ok := strconv.parse_f32(strings.trim_space(input.text))
		if !ok || !ui_numeric_valid(input^, number) {
			state.input_valid = false
			if interaction := ecs.ensure_ui_state(world, entity_index); interaction != nil {
				interaction.valid = false
			}
			return false
		}
		changed := !state.input_has_original_number || number != state.input_original_number
		input.number = number
		if changed && !state.input_scrubbing {
			_ = mark_ui_event(state, world, .Changed, entity.id)
		}
		state.input_original_number = number
		state.input_has_original_number = true
	}
	if entity.origin == .Editor &&
	   entity.editor_ui_index >= 0 &&
	   entity.editor_ui_index < len(world.editor_uis) {
		binding := world.editor_uis[entity.editor_ui_index]
		if binding.role == .Inspector_Input &&
		   binding.reflected_component_id != shared.INVALID_COMPONENT_ID &&
		   !editor_reflected_input_valid(state, world, binding, input.text) {
			state.input_valid = false
			if interaction := ecs.ensure_ui_state(world, entity_index); interaction != nil {
				interaction.valid = false
			}
			return false
		}
		if (binding.role == .Inspector_Resource_Name ||
			   binding.role == .Inspector_Resource_Source) &&
		   state.resource_registry != nil &&
		   state.editor_has_resource_selection {
			handle, found := resources.material_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			)
			if found {
				material, alive := resources.get_material(state.resource_registry, handle)
				if alive {
					name := material.name
					source := material.source
					if binding.role == .Inspector_Resource_Name {
						name = input.text
					} else {
						source = input.text
					}
					if resources.validate_project_material_identity(
						   state.resource_registry,
						   state.editor_selected_resource,
						   name,
						   source,
					   ) !=
					   "" {
						state.input_valid = false
						if interaction := ecs.ensure_ui_state(world, entity_index);
						   interaction != nil {
							interaction.valid = false
						}
						return false
					}
				}
			}
		}
	}
	_ = mark_ui_event(state, world, .Submitted, entity.id)
	delete(state.input_original_text)
	state.input_original_text, _ = strings.clone(input.text)
	state.input_valid = true
	if interaction := ecs.ensure_ui_state(world, entity_index); interaction != nil {
		interaction.valid = true
	}
	return true
}

cancel_input_edit :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || !state.has_focused_input {
		return
	}
	entity_index := int(state.focused_input.index)
	if entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs) {
		input := &world.ui_inputs[entity.ui_input_index]
		_ = ecs.set_ui_input_value(world, entity_index, state.input_original_text)
		if input.numeric && state.input_has_original_number {
			input.number = state.input_original_number
		}
		state.input_cursor = len(input.text)
		state.input_anchor = 0
	}
	_ = mark_ui_event(state, world, .Cancelled, entity.id)
	state.input_valid = true
	if interaction := ecs.ensure_ui_state(world, entity_index); interaction != nil {
		interaction.valid = true
	}
}

move_input_focus :: proc(state: ^State, world: ^shared.World, backwards: bool) {
	current_order := -1
	for node in state.nodes[:state.node_count] {
		if node.entity == state.focused_input { current_order = node.paint_order; break }
	}
	best_index, wrap_index := -1, -1
	best_order := 1 << 30
	wrap_order := 1 << 30
	if backwards { best_order = -1; wrap_order = -1 }
	for node, node_index in state.nodes[:state.node_count] {
		if node.input_index < 0 ||
		   node.input_index >= len(world.ui_inputs) ||
		   !node.laid_out ||
		   (node.origin == .Editor) != state.focused_input_editor ||
		   ui_entity_or_ancestor_hidden(world, int(node.entity.index)) { continue }
		order := node.paint_order
		if (!backwards && order > current_order && order < best_order) ||
		   (backwards && order < current_order && order > best_order) {
			best_index = node_index
			best_order = order
		}
		if (!backwards && order < wrap_order) || (backwards && order > wrap_order) {
			wrap_index = node_index
			wrap_order = order
		}
	}
	if best_index < 0 { best_index = wrap_index }
	if best_index >= 0 { focus_input(state, world, int(state.nodes[best_index].entity.index)) }
}

set_numeric_input_text :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	input: ^shared.UI_Input_Component,
	number: f32,
) {
	if input == nil { return }
	formatted := fmt.tprintf("%.3f", number)
	trimmed := strings.trim_right(formatted, "0")
	if strings.has_suffix(trimmed, ".") { trimmed = trimmed[:len(trimmed) - 1] }
	_ = ecs.set_ui_input_value(world, entity_index, trimmed)
	state.input_anchor = 0
	state.input_cursor = len(input.text)
	state.input_blink_elapsed = 0
}

numeric_modifier :: proc(keyboard: Keyboard_Input) -> f32 {
	factor := f32(1)
	if keyboard.shift { factor *= 10 }
	if keyboard.fine { factor *= 0.1 }
	return factor
}

update_focused_input :: proc(
	state: ^State,
	world: ^shared.World,
	keyboard: Keyboard_Input,
	delta_seconds: f32,
) {
	if !state.has_focused_input { return }
	entity_index := int(state.focused_input.index)
	if entity_index < 0 || entity_index >= len(world.entities) {
		clear_input_focus(state)
		return
	}
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != state.focused_input ||
	   entity.ui_input_index < 0 ||
	   entity.ui_input_index >= len(world.ui_inputs) {
		clear_input_focus(state)
		return
	}
	input := &world.ui_inputs[entity.ui_input_index]
	numeric := input.numeric
	state.input_cursor = clamp(state.input_cursor, 0, len(input.text))
	state.input_anchor = clamp(state.input_anchor, 0, len(input.text))
	state.input_blink_elapsed += max(delta_seconds, 0)
	if keyboard.select_all {
		state.input_anchor = 0
		state.input_cursor = len(input.text)
		state.input_blink_elapsed = 0
	}
	if keyboard.home || keyboard.end || keyboard.left || keyboard.right {
		start, end := input_selection(state)
		next := state.input_cursor
		if keyboard.home { next = 0 }
		if keyboard.end { next = len(input.text) }
		if keyboard.left { next = max(state.input_cursor - 1, 0); if !keyboard.shift && start != end { next = start } }
		if keyboard.right { next = min(state.input_cursor + 1, len(input.text)); if !keyboard.shift && start != end { next = end } }
		state.input_cursor = next
		if !keyboard.shift { state.input_anchor = next }
		state.input_blink_elapsed = 0
	}
	if !input.read_only {
		edited := false
		start, end := input_selection(state)
		if keyboard.backspace {
			if start != end || start > 0 {
				if start == end { state.input_anchor = start - 1 }
				edited = replace_input_selection(state, world, entity_index, input, "") || edited
			}
		}
		start, end = input_selection(state)
		if keyboard.delete_forward {
			if start != end || end < len(input.text) {
				if start == end { state.input_cursor = end + 1 }
				edited = replace_input_selection(state, world, entity_index, input, "") || edited
			}
		}
		if keyboard.text != "" {
			filtered := single_line_ascii(keyboard.text)
			if filtered != "" {
				edited =
					replace_input_selection(state, world, entity_index, input, filtered) || edited
			}
			delete(filtered)
		}
		if numeric && (keyboard.up || keyboard.down) {
			current, ok := strconv.parse_f32(strings.trim_space(input.text))
			if !ok || !ui_numeric_valid(input^, current) {
				current = input.number
				ok = ui_numeric_valid(input^, current)
			}
			if ok {
				direction := f32(1)
				if keyboard.down { direction = -1 }
				next := current + direction * input.step * numeric_modifier(keyboard)
				if input.has_minimum { next = max(next, input.minimum) }
				if input.has_maximum { next = min(next, input.maximum) }
				set_numeric_input_text(state, world, entity_index, input, next)
				edited = true
			}
		}
		if edited {
			if numeric {
				state.input_valid = numeric_input_text_valid(input^)
			} else {
				_ = mark_ui_event(state, world, .Changed, entity.id)
				state.input_valid = true
			}
		}
	}
	if keyboard.escape {
		if !input.read_only { cancel_input_edit(state, world) }
		clear_input_focus(state)
		return
	}
	if keyboard.enter {
		if finish_input_edit(state, world) { clear_input_focus(state) }
		return
	}
	if keyboard.tab {
		if input.numeric {
			cancel_input_edit(state, world)
			move_input_focus(state, world, keyboard.shift)
		} else if finish_input_edit(state, world) {
			move_input_focus(state, world, keyboard.shift)
		}
	}
}

update_input_scrub :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	keyboard: Keyboard_Input,
) {
	if state == nil || !state.input_scrub_armed { return }
	entity_index := int(state.focused_input.index)
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		state.input_scrub_armed = false
		state.input_scrubbing = false
		return
	}
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != state.focused_input ||
	   entity.ui_input_index < 0 ||
	   entity.ui_input_index >= len(world.ui_inputs) {
		state.input_scrub_armed = false
		state.input_scrubbing = false
		return
	}
	input := &world.ui_inputs[entity.ui_input_index]
	if !input.numeric || input.read_only {
		state.input_scrub_armed = false
		state.input_scrubbing = false
		return
	}
	if !pointer.available || !pointer.primary_down {
		if state.input_scrubbing { _ = finish_input_edit(state, world) }
		state.input_scrub_armed = false
		state.input_scrubbing = false
		return
	}
	delta := pointer.position.x - state.input_scrub_start_x
	if !state.input_scrubbing && math.abs(delta) >= 3 { state.input_scrubbing = true }
	if !state.input_scrubbing { return }
	next := state.input_scrub_start_number + delta / 4 * input.step * numeric_modifier(keyboard)
	if input.has_minimum { next = max(next, input.minimum) }
	if input.has_maximum { next = min(next, input.maximum) }
	set_numeric_input_text(state, world, entity_index, input, next)
	_ = mark_ui_event(state, world, .Changed, entity.id, pointer.position)
	state.input_valid = apply_numeric_input(state, world, entity_index)
}

mark_interaction_chain :: proc(state: ^State, node_index: int, active: bool) {
	index := node_index
	for index >= 0 {
		if active { state.nodes[index].active = true } else { state.nodes[index].hovered = true }
		index = state.nodes[index].parent_node_index
	}
}

sync_ui_interaction_states :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil {
		return
	}
	for &node in state.nodes[:state.node_count] {
		entity_index := int(node.entity.index)
		interaction := ecs.ensure_ui_state(world, entity_index)
		if interaction == nil {
			continue
		}
		was_hovered := interaction.hovered
		was_active := interaction.active
		was_focused := interaction.focused
		was_valid := interaction.valid
		interaction.hovered = node.hovered
		interaction.active = node.active
		interaction.focused = state.has_focused_input && state.focused_input == node.entity
		if interaction.focused {
			interaction.valid = state.input_valid
		}
		if was_hovered != interaction.hovered ||
		   was_active != interaction.active ||
		   was_focused != interaction.focused ||
		   was_valid != interaction.valid {
			ecs.mark_ui_paint_changed(world, entity_index)
		}
	}
}

list_item_for_node :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
) -> (
	list: shared.Entity,
	item: shared.Entity,
	found: bool,
) {
	if state == nil || world == nil || node_index < 0 || node_index >= state.node_count {
		return {}, {}, false
	}
	current := node_index
	for current >= 0 {
		parent_index := state.nodes[current].parent_node_index
		if parent_index < 0 {
			break
		}
		parent := state.nodes[parent_index]
		parent_entity_index := int(parent.entity.index)
		if ecs.entity_is_alive(world, parent_entity_index) &&
		   world.entities[parent_entity_index].id == parent.entity {
			parent_entity := world.entities[parent_entity_index]
			if parent_entity.ui_list_index >= 0 &&
			   parent_entity.ui_list_index < len(world.ui_lists) {
				return parent.entity, state.nodes[current].entity, true
			}
		}
		current = parent_index
	}
	return {}, {}, false
}

pointer_hit_node :: proc(state: ^State, position: shared.Vec2, editor: bool) -> int {
	if state == nil {
		return -1
	}
	hit := -1
	highest_order := -1
	for node, index in state.nodes[:state.node_count] {
		if (node.origin == .Editor) != editor ||
		   !node.laid_out ||
		   !node_pointer_contains(node, position) {
			continue
		}
		if node.paint_order >= highest_order {
			hit = index
			highest_order = node.paint_order
		}
	}
	return hit
}

stack_for_panel_title :: proc(
	state: ^State,
	world: ^shared.World,
	hit_node: int,
	position: shared.Vec2,
) -> (
	stack: shared.Entity,
	panel: shared.Entity,
	found: bool,
) {
	if state == nil || world == nil || hit_node < 0 || hit_node >= state.node_count {
		return
	}
	if node_is_panel_action(world, &state.nodes[hit_node]) {
		return
	}
	current := hit_node
	for current >= 0 {
		node := &state.nodes[current]
		if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
			value := world.ui_panels[node.panel_index]
			title := Rect{node.rect.x, node.rect.y, node.rect.width, value.title_height}
			parent_index := node.parent_node_index
			if value.movable &&
			   value.title != "" &&
			   rect_contains(title, position) &&
			   parent_index >= 0 {
				parent := state.nodes[parent_index]
				stack_index := parent.hstack_index
				if stack_index < 0 {
					stack_index = parent.vstack_index
				}
				storage := world.ui_hstacks[:]
				if parent.vstack_index >= 0 {
					storage = world.ui_vstacks[:]
				}
				if stack_index >= 0 &&
				   stack_index < len(storage) &&
				   storage[stack_index].reorderable {
					return parent.entity, node.entity, true
				}
			}
		}
		current = node.parent_node_index
	}
	return
}

stack_drag_begin :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
	editor: bool,
) -> bool {
	node_index := find_node(state, pressed)
	stack, panel, found := stack_for_panel_title(state, world, node_index, position)
	if !found {
		return false
	}
	slot := 0
	if editor {
		slot = 1
	}
	state.stack_drags[slot] = {
		stack = stack,
		source = panel,
		start = position,
		armed = true,
		title_handle = true,
	}
	return true
}

stack_component_for_node :: proc(
	world: ^shared.World,
	node: Node,
) -> (
	shared.UI_Stack_Component,
	bool,
	bool,
) {
	if node.hstack_index >= 0 && node.hstack_index < len(world.ui_hstacks) {
		return world.ui_hstacks[node.hstack_index], true, true
	}
	if node.vstack_index >= 0 && node.vstack_index < len(world.ui_vstacks) {
		return world.ui_vstacks[node.vstack_index], false, true
	}
	return {}, false, false
}

dock_item_title :: proc(world: ^shared.World, node: Node) -> (string, bool) {
	if node.dock_item_index >= 0 && node.dock_item_index < len(world.ui_dock_items) {
		return world.ui_dock_items[node.dock_item_index].title, true
	}
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		panel := world.ui_panels[node.panel_index]
		if panel.title != "" {
			return panel.title, true
		}
	}
	return "", false
}

dock_item_movable :: proc(world: ^shared.World, node: Node) -> bool {
	if node.dock_item_index >= 0 && node.dock_item_index < len(world.ui_dock_items) {
		return world.ui_dock_items[node.dock_item_index].movable
	}
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		return world.ui_panels[node.panel_index].movable
	}
	return false
}

dock_item_reorderable_stack_node :: proc(
	state: ^State,
	world: ^shared.World,
	item_node_index: int,
) -> int {
	if state == nil || world == nil || item_node_index < 0 || item_node_index >= state.node_count {
		return -1
	}
	queue: [MAX_NODES]int
	queue[0] = item_node_index
	cursor := 0
	count := 1
	for cursor < count {
		node_index := queue[cursor]
		cursor += 1
		stack, _, is_stack := stack_component_for_node(world, state.nodes[node_index])
		if is_stack && stack.reorderable {
			return node_index
		}
		child := state.nodes[node_index].first_child_node
		for child >= 0 && count < MAX_NODES {
			queue[count] = child
			count += 1
			child = state.nodes[child].next_sibling_node
		}
	}
	return -1
}

dock_tab_reorderable_stack_at_pointer :: proc(
	state: ^State,
	world: ^shared.World,
	space_node_index: int,
	position: shared.Vec2,
	excluded_item_node: int = -1,
	mark_drop_target: bool = false,
) -> int {
	if state == nil || world == nil || space_node_index < 0 {
		return -1
	}
	for &tab in state.dock_tabs[:state.dock_tab_count] {
		if tab.space_node == space_node_index &&
		   tab.item_node != excluded_item_node &&
		   rect_contains(tab.rect, position) {
			stack_node := dock_item_reorderable_stack_node(state, world, tab.item_node)
			if stack_node >= 0 && mark_drop_target {
				tab.drop_target = true
			}
			return stack_node
		}
	}
	return -1
}

node_is_docked_panel :: proc(state: ^State, world: ^shared.World, node_index: int) -> bool {
	if state == nil || world == nil || node_index < 0 || node_index >= state.node_count {
		return false
	}
	node := state.nodes[node_index]
	if node.panel_index < 0 || node.panel_index >= len(world.ui_panels) {
		return false
	}
	parent_index := node.parent_node_index
	if parent_index < 0 ||
	   parent_index >= state.node_count ||
	   state.nodes[parent_index].dock_space_index < 0 {
		return false
	}
	_, eligible := dock_item_title(world, node)
	return eligible
}

normalize_stack_order :: proc(
	state: ^State,
	world: ^shared.World,
	stack_node_index: int,
	source: shared.Entity = {},
	target: shared.Entity = {},
	placement: shared.UI_Drop_Placement = .None,
) -> bool {
	if stack_node_index < 0 || stack_node_index >= state.node_count {
		return false
	}
	nodes: [MAX_NODES]int
	count := 0
	child := state.nodes[stack_node_index].first_child_node
	for child >= 0 {
		if state.nodes[child].entity != source {
			nodes[count] = child
			count += 1
		}
		child = state.nodes[child].next_sibling_node
	}
	sort_stack_nodes(state, world, &nodes, count)
	insert := count
	if target != (shared.Entity{}) {
		for index in 0 ..< count {
			if state.nodes[nodes[index]].entity == target {
				insert = index
				if placement == .After {
					insert += 1
				}
				break
			}
		}
	}
	ordered: [MAX_NODES]shared.Entity
	ordered_count := 0
	for index in 0 ..< insert {
		ordered[ordered_count] = state.nodes[nodes[index]].entity
		ordered_count += 1
	}
	if source != (shared.Entity{}) {
		ordered[ordered_count] = source
		ordered_count += 1
	}
	for index in insert ..< count {
		ordered[ordered_count] = state.nodes[nodes[index]].entity
		ordered_count += 1
	}
	changed := false
	for order in 0 ..< ordered_count {
		entity_index := int(ordered[order].index)
		if !ecs.entity_is_alive(world, entity_index) ||
		   world.entities[entity_index].id != ordered[order] {
			continue
		}
		layout_index := world.entities[entity_index].ui_layout_index
		if layout_index < 0 || layout_index >= len(world.ui_layouts) {
			continue
		}
		value := world.ui_layouts[layout_index]
		if value.stack_order == order {
			continue
		}
		value.stack_order = order
		changed = ecs.set_ui_layout(world, entity_index, value) || changed
	}
	return changed
}

apply_stack_drop :: proc(
	state: ^State,
	world: ^shared.World,
	drag: Stack_Drag_Interaction,
	position: shared.Vec2,
) -> bool {
	source_node := find_node(state, drag.source)
	source_stack_node := find_node(state, drag.stack)
	target_stack_node := find_node(state, drag.target_stack)
	if source_node < 0 || source_stack_node < 0 || target_stack_node < 0 {
		return false
	}
	source_index := int(drag.source.index)
	target_stack_index := int(drag.target_stack.index)
	if !ecs.entity_is_alive(world, source_index) ||
	   !ecs.entity_is_alive(world, target_stack_index) {
		return false
	}
	layout := world.ui_layouts[state.nodes[source_node].layout_index]
	layout.parent = world.entities[target_stack_index].uuid
	layout_changed := ecs.set_ui_layout(world, source_index, layout)
	layout_changed =
		normalize_stack_order(
			state,
			world,
			target_stack_node,
			drag.source,
			drag.target,
			drag.placement,
		) ||
		layout_changed
	if drag.stack != drag.target_stack {
		layout_changed =
			normalize_stack_order(state, world, source_stack_node, drag.source) || layout_changed
	}
	interaction := ecs.ensure_ui_state(world, target_stack_index)
	if interaction != nil {
		interaction.changed = true
		interaction.change_revision += 1
		interaction.drag_source = world.entities[source_index].uuid
		interaction.drop_target = world.entities[target_stack_index].uuid
		interaction.drop_placement = drag.placement
		interaction.drop_revision += 1
		ecs.mark_ui_state_transient(world, target_stack_index)
	}
	append_ui_event(
		state,
		{
			kind = .Dropped,
			entity = drag.target_stack,
			source = drag.source,
			target = drag.target,
			drop_placement = drag.placement,
			position = position,
		},
	)
	return layout_changed
}

ui_dock_split_is_directional :: proc "contextless" (placement: shared.UI_Drop_Placement) -> bool {
	return placement == .Left || placement == .Right || placement == .Above || placement == .Below
}

ui_node_descends_from :: proc "contextless" (
	state: ^State,
	node_index, ancestor_index: int,
) -> bool {
	if state == nil || node_index < 0 || ancestor_index < 0 {
		return false
	}
	for current := node_index; current >= 0; current = state.nodes[current].parent_node_index {
		if current == ancestor_index {
			return true
		}
	}
	return false
}

dock_split_outer_layout :: proc "contextless" (
	value: shared.UI_Layout_Component,
) -> shared.UI_Layout_Component {
	return {
		parent = value.parent,
		position = value.position,
		size = value.size,
		min_size = value.min_size,
		margin = value.margin,
		hidden = value.hidden,
		fill_width = value.fill_width,
		fill_height = value.fill_height,
		fixed_in_fill = value.fixed_in_fill,
		basis = value.basis,
		grow = value.grow,
		shrink = value.shrink,
		horizontal_alignment = value.horizontal_alignment,
		vertical_alignment = value.vertical_alignment,
		stack_order = value.stack_order,
	}
}

dock_split_child_layout :: proc "contextless" (
	value: shared.UI_Layout_Component,
	parent: shared.Entity_UUID,
	size: shared.Vec2,
	min_size: f32,
	order: int,
	horizontal: bool,
) -> shared.UI_Layout_Component {
	result := value
	result.parent = parent
	result.position = {}
	result.size = size
	result.min_size = {1, 1}
	if horizontal {
		result.min_size.x = min_size
	} else {
		result.min_size.y = min_size
	}
	result.margin = {}
	result.hidden = false
	result.fill_width = true
	result.fill_height = true
	result.fixed_in_fill = false
	result.basis = 0
	result.grow = 0
	result.shrink = 0
	result.horizontal_alignment = .Stretch
	result.vertical_alignment = .Stretch
	result.stack_order = order
	return result
}

apply_dock_split_drop :: proc(
	state: ^State,
	world: ^shared.World,
	source, target_space, source_stack, source_space: shared.Entity,
	placement: shared.UI_Drop_Placement,
	position: shared.Vec2,
) -> bool {
	if state == nil ||
	   world == nil ||
	   !ui_dock_split_is_directional(placement) ||
	   state.node_count + 2 > MAX_NODES {
		return false
	}
	source_node_index := find_node(state, source)
	target_node_index := find_node(state, target_space)
	if source_node_index < 0 || target_node_index < 0 {
		return false
	}
	source_node := state.nodes[source_node_index]
	target_node := state.nodes[target_node_index]
	source_index := int(source.index)
	target_index := int(target_space.index)
	if !ecs.entity_is_alive(world, source_index) ||
	   !ecs.entity_is_alive(world, target_index) ||
	   world.entities[source_index].id != source ||
	   world.entities[target_index].id != target_space ||
	   source_node.layout_index < 0 ||
	   source_node.layout_index >= len(world.ui_layouts) ||
	   target_node.layout_index < 0 ||
	   target_node.layout_index >= len(world.ui_layouts) ||
	   target_node.dock_space_index < 0 ||
	   target_node.dock_space_index >= len(world.ui_dock_spaces) {
		return false
	}
	dock_value := world.ui_dock_spaces[target_node.dock_space_index]
	horizontal := placement == .Left || placement == .Right
	if horizontal && !dock_value.split_horizontal || !horizontal && !dock_value.split_vertical {
		return false
	}
	content := dock_space_content_rect(target_node, dock_value)
	main_extent := content.height
	if horizontal {
		main_extent = content.width
	}
	available := main_extent - dock_value.split_gap
	if available < dock_value.split_min_size * 2 {
		return false
	}
	new_extent := clamp(
		available * dock_value.split_ratio,
		dock_value.split_min_size,
		available - dock_value.split_min_size,
	)
	existing_extent := available - new_extent
	target_size := shared.Vec2{target_node.rect.width, target_node.rect.height}
	new_size := target_size
	if horizontal {
		target_size.x = existing_extent
		new_size.x = new_extent
	} else {
		target_size.y = existing_extent
		new_size.y = new_extent
	}
	new_first := placement == .Left || placement == .Above
	target_order := 0
	new_order := 1
	if new_first {
		target_order = 1
		new_order = 0
	}

	parent_siblings: [MAX_NODES]int
	parent_sibling_count := 0
	target_parent_is_stack := false
	if target_node.parent_node_index >= 0 {
		_, _, target_parent_is_stack = stack_component_for_node(
			world,
			state.nodes[target_node.parent_node_index],
		)
		if target_parent_is_stack {
			for child := state.nodes[target_node.parent_node_index].first_child_node;
			    child >= 0;
			    child = state.nodes[child].next_sibling_node {
				parent_siblings[parent_sibling_count] = child
				parent_sibling_count += 1
			}
			sort_stack_nodes(state, world, &parent_siblings, parent_sibling_count)
		}
	}

	origin := shared.Entity_Origin.Runtime
	if target_node.origin == .Editor {
		origin = .Editor
	}
	branch_index, branch_created := ecs.create_world_entity(world, "UI Dock Split", {}, origin)
	if !branch_created {
		return false
	}
	branch_alive := true
	defer if branch_alive {
		ecs.despawn_entity(world, branch_index, world.entities[branch_index].id.generation)
	}
	old_target_layout := world.ui_layouts[target_node.layout_index]
	branch_layout := dock_split_outer_layout(old_target_layout)
	if target_parent_is_stack {
		for order in 0 ..< parent_sibling_count {
			if parent_siblings[order] == target_node_index {
				branch_layout.stack_order = order
				break
			}
		}
	}
	if !ecs.set_ui_layout(world, branch_index, branch_layout) {
		return false
	}
	split_stack := shared.ui_stack_default()
	split_stack.gap = dock_value.split_gap
	split_stack.fill = true
	split_stack.draggable = true
	split_stack.min_size = dock_value.split_min_size
	stack_set := false
	if horizontal {
		stack_set = ecs.set_ui_hstack(world, branch_index, split_stack)
	} else {
		stack_set = ecs.set_ui_vstack(world, branch_index, split_stack)
	}
	if !stack_set {
		return false
	}

	new_space_index, new_space_created := ecs.create_world_entity(
		world,
		"UI Dock Split Pane",
		{},
		origin,
	)
	if !new_space_created {
		return false
	}
	new_space_alive := true
	defer if new_space_alive {
		ecs.despawn_entity(world, new_space_index, world.entities[new_space_index].id.generation)
	}
	branch_uuid := world.entities[branch_index].uuid
	new_space_uuid := world.entities[new_space_index].uuid
	new_layout := dock_split_child_layout(
		old_target_layout,
		branch_uuid,
		new_size,
		dock_value.split_min_size,
		new_order,
		horizontal,
	)
	if !ecs.set_ui_layout(world, new_space_index, new_layout) {
		return false
	}
	new_dock_value := dock_value
	new_dock_value.active = world.entities[source_index].uuid
	if !ecs.set_ui_dock_space(world, new_space_index, new_dock_value) {
		return false
	}

	target_layout := dock_split_child_layout(
		old_target_layout,
		branch_uuid,
		target_size,
		dock_value.split_min_size,
		target_order,
		horizontal,
	)
	if !ecs.set_ui_layout(world, target_index, target_layout) {
		return false
	}
	old_source_layout := world.ui_layouts[source_node.layout_index]
	source_layout := old_source_layout
	source_layout.parent = new_space_uuid
	if !ecs.set_ui_layout(world, source_index, source_layout) {
		_ = ecs.set_ui_layout(world, target_index, old_target_layout)
		return false
	}
	branch_alive = false
	new_space_alive = false

	layout_changed := true
	if target_parent_is_stack {
		for order in 0 ..< parent_sibling_count {
			child := parent_siblings[order]
			entity_index := branch_index
			if child != target_node_index {
				entity_index = int(state.nodes[child].entity.index)
			}
			layout_index := world.entities[entity_index].ui_layout_index
			if layout_index < 0 || layout_index >= len(world.ui_layouts) {
				continue
			}
			value := world.ui_layouts[layout_index]
			value.stack_order = order
			layout_changed = ecs.set_ui_layout(world, entity_index, value) || layout_changed
		}
	}
	source_stack_node := find_node(state, source_stack)
	if source_stack_node >= 0 {
		layout_changed =
			normalize_stack_order(state, world, source_stack_node, source) || layout_changed
	}
	source_space_index := int(source_space.index)
	if source_space != (shared.Entity{}) &&
	   ecs.entity_is_alive(world, source_space_index) &&
	   world.entities[source_space_index].id == source_space {
		source_space_component := world.entities[source_space_index].ui_dock_space_index
		if source_space_component >= 0 && source_space_component < len(world.ui_dock_spaces) {
			source_value := world.ui_dock_spaces[source_space_component]
			source_value.active = {}
			layout_changed =
				ecs.set_ui_dock_space(world, source_space_index, source_value) || layout_changed
		}
	}
	interaction := ecs.ensure_ui_state(world, target_index)
	if interaction != nil {
		interaction.changed = true
		interaction.change_revision += 1
		interaction.drag_source = world.entities[source_index].uuid
		interaction.drop_target = world.entities[target_index].uuid
		interaction.drop_placement = placement
		interaction.drop_revision += 1
		ecs.mark_ui_state_transient(world, target_index)
	}
	append_ui_event(
		state,
		{
			kind = .Dropped,
			entity = target_space,
			source = source,
			target = target_space,
			drop_placement = placement,
			position = position,
		},
	)
	return layout_changed
}

apply_panel_dock_drop :: proc(
	state: ^State,
	world: ^shared.World,
	drag: Stack_Drag_Interaction,
	position: shared.Vec2,
) -> bool {
	source_node := find_node(state, drag.source)
	source_stack_node := find_node(state, drag.stack)
	target_space_node := find_node(state, drag.target_dock_space)
	if source_node < 0 || source_stack_node < 0 || target_space_node < 0 {
		return false
	}
	source_index := int(drag.source.index)
	target_index := int(drag.target_dock_space.index)
	if !ecs.entity_is_alive(world, source_index) || !ecs.entity_is_alive(world, target_index) {
		return false
	}
	target_node := state.nodes[target_space_node]
	if target_node.dock_space_index < 0 ||
	   target_node.dock_space_index >= len(world.ui_dock_spaces) ||
	   !world.ui_dock_spaces[target_node.dock_space_index].draggable {
		return false
	}
	layout := world.ui_layouts[state.nodes[source_node].layout_index]
	layout.parent = world.entities[target_index].uuid
	layout_changed := ecs.set_ui_layout(world, source_index, layout)
	layout_changed =
		normalize_stack_order(state, world, source_stack_node, drag.source) || layout_changed
	target_value := world.ui_dock_spaces[target_node.dock_space_index]
	target_value.active = world.entities[source_index].uuid
	layout_changed = ecs.set_ui_dock_space(world, target_index, target_value) || layout_changed
	interaction := ecs.ensure_ui_state(world, target_index)
	if interaction != nil {
		interaction.changed = true
		interaction.change_revision += 1
		interaction.drag_source = world.entities[source_index].uuid
		interaction.drop_target = world.entities[target_index].uuid
		interaction.drop_placement = .Into
		interaction.drop_revision += 1
		ecs.mark_ui_state_transient(world, target_index)
	}
	append_ui_event(
		state,
		{
			kind = .Dropped,
			entity = drag.target_dock_space,
			source = drag.source,
			target = drag.target_dock_space,
			drop_placement = .Into,
			position = position,
		},
	)
	return layout_changed
}

stack_drag_update :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	released: bool,
	editor: bool,
) -> (
	layout_changed: bool,
	title_clicked: bool,
) {
	slot := 0
	if editor {
		slot = 1
	}
	drag := &state.stack_drags[slot]
	if !drag.armed {
		return
	}
	if !pointer.available {
		drag^ = {}
		return
	}
	source_stack_node := find_node(state, drag.stack)
	if source_stack_node < 0 {
		drag^ = {}
		return
	}
	stack, _, stack_ok := stack_component_for_node(world, state.nodes[source_stack_node])
	if !stack_ok {
		drag^ = {}
		return
	}
	if pointer.primary_down {
		delta := shared.Vec2{pointer.position.x - drag.start.x, pointer.position.y - drag.start.y}
		if delta.x * delta.x + delta.y * delta.y >= stack.drag_threshold * stack.drag_threshold {
			drag.dragging = true
		}
		if drag.dragging {
			drag.target_stack = {}
			drag.target_dock_space = {}
			drag.target = {}
			drag.placement = .None
			best_order := -1
			for candidate, candidate_index in state.nodes[:state.node_count] {
				if (candidate.origin == .Editor) != editor ||
				   !candidate.laid_out ||
				   !rect_contains(candidate.rect, pointer.position) ||
				   candidate.paint_order < best_order {
					continue
				}
				if candidate.dock_space_index >= 0 &&
				   candidate.dock_space_index < len(world.ui_dock_spaces) &&
				   world.ui_dock_spaces[candidate.dock_space_index].draggable {
					drag.target_dock_space = candidate.entity
					best_order = candidate.paint_order
					drag.placement = dock_space_drop_placement(
						candidate,
						world.ui_dock_spaces[candidate.dock_space_index],
						pointer.position,
					)
					continue
				}
				target_dock_node := find_node(state, drag.target_dock_space)
				if target_dock_node >= 0 &&
				   ui_dock_split_is_directional(drag.placement) &&
				   ui_node_descends_from(state, candidate_index, target_dock_node) {
					continue
				}
				candidate_stack, horizontal, ok := stack_component_for_node(world, candidate)
				if !ok ||
				   !candidate_stack.reorderable ||
				   candidate.panel_index >= 0 &&
					   !node_is_docked_panel(state, world, candidate_index) {
					continue
				}
				drag.target_dock_space = {}
				drag.target_stack = candidate.entity
				best_order = candidate.paint_order
				child := candidate.first_child_node
				for child >= 0 {
					item := state.nodes[child]
					if item.entity != drag.source &&
					   item.laid_out &&
					   rect_contains(item.rect, pointer.position) {
						drag.target = item.entity
						if horizontal {
							drag.placement = .Before
							if pointer.position.x >= item.rect.x + item.rect.width * 0.5 {
								drag.placement = .After
							}
						} else {
							drag.placement = .Before
							if pointer.position.y >= item.rect.y + item.rect.height * 0.5 {
								drag.placement = .After
							}
						}
						break
					}
					child = item.next_sibling_node
				}
				if drag.target == (shared.Entity{}) {
					drag.placement = .After
				}
			}
			if drag.target_dock_space != (shared.Entity{}) && drag.placement == .Into {
				target_space_node := find_node(state, drag.target_dock_space)
				target_stack_node := dock_tab_reorderable_stack_at_pointer(
					state,
					world,
					target_space_node,
					pointer.position,
					-1,
					true,
				)
				if target_stack_node >= 0 {
					drag.target_dock_space = {}
					drag.target_stack = state.nodes[target_stack_node].entity
					drag.target = {}
					drag.placement = .After
				}
			}
			ecs.mark_ui_paint_changed(world, int(drag.stack.index))
			if drag.target_stack != (shared.Entity{}) {
				ecs.mark_ui_paint_changed(world, int(drag.target_stack.index))
			}
			if drag.target_dock_space != (shared.Entity{}) {
				ecs.mark_ui_paint_changed(world, int(drag.target_dock_space.index))
			}
		}
		return
	}
	if released {
		if drag.dragging && drag.target_stack != (shared.Entity{}) && drag.placement != .None {
			layout_changed = apply_stack_drop(state, world, drag^, pointer.position)
		} else if drag.dragging &&
		   drag.target_dock_space != (shared.Entity{}) &&
		   ui_dock_split_is_directional(drag.placement) {
			layout_changed = apply_dock_split_drop(
				state,
				world,
				drag.source,
				drag.target_dock_space,
				drag.stack,
				{},
				drag.placement,
				pointer.position,
			)
		} else if drag.dragging &&
		   drag.target_dock_space != (shared.Entity{}) &&
		   drag.placement == .Into {
			layout_changed = apply_panel_dock_drop(state, world, drag^, pointer.position)
		} else if drag.title_handle && !drag.dragging {
			title_clicked = handle_panel_title_press(state, world, drag.source, drag.start)
		}
		drag^ = {}
	}
	return
}

action_entity_for_node :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	drag_source: bool,
) -> (
	shared.Entity,
	^shared.UI_Action_Component,
	bool,
) {
	if state == nil || world == nil {
		return {}, nil, false
	}
	current := node_index
	for current >= 0 {
		node := state.nodes[current]
		entity_index := int(node.entity.index)
		if ecs.entity_is_alive(world, entity_index) &&
		   world.entities[entity_index].id == node.entity {
			component_index := world.entities[entity_index].ui_action_index
			if component_index >= 0 && component_index < len(world.ui_actions) {
				value := &world.ui_actions[component_index]
				accepted := value.drop_target
				if drag_source {
					accepted = value.drag_source
				}
				if accepted {
					return node.entity, value, true
				}
			}
		}
		current = node.parent_node_index
	}
	return {}, nil, false
}

action_drag_begin :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
	editor: bool,
) {
	if state == nil || world == nil {
		return
	}
	source, _, found := action_entity_for_node(state, world, find_node(state, pressed), true)
	if !found {
		return
	}
	slot := 0
	if editor {
		slot = 1
	}
	state.action_drags[slot] = {
		source = source,
		start = position,
		position = position,
		armed = true,
	}
}

action_drag_reset :: proc(state: ^State, world: ^shared.World, slot: int) {
	if state == nil || slot < 0 || slot >= len(state.action_drags) {
		return
	}
	drag := &state.action_drags[slot]
	source_index := int(drag.source.index)
	if world != nil &&
	   ecs.entity_is_alive(world, source_index) &&
	   world.entities[source_index].id == drag.source {
		interaction := ecs.ensure_ui_state(world, source_index)
		if interaction != nil {
			paint_changed :=
				interaction.dragging || interaction.drop_target != (shared.Entity_UUID{})
			interaction.dragging = false
			interaction.drag_source = {}
			interaction.drop_target = {}
			interaction.drop_placement = .None
			if paint_changed {
				ecs.mark_ui_paint_changed(world, source_index)
			}
		}
	}
	drag^ = {}
}

action_drag_update :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	released: bool,
	editor: bool,
) {
	if state == nil || world == nil {
		return
	}
	slot := 0
	if editor {
		slot = 1
	}
	drag := &state.action_drags[slot]
	if !drag.armed {
		return
	}
	drag.position = pointer.position
	source_index := int(drag.source.index)
	if !ecs.entity_is_alive(world, source_index) ||
	   world.entities[source_index].id != drag.source {
		action_drag_reset(state, world, slot)
		return
	}
	action_index := world.entities[source_index].ui_action_index
	if action_index < 0 || action_index >= len(world.ui_actions) {
		action_drag_reset(state, world, slot)
		return
	}
	action := world.ui_actions[action_index]
	if pointer.primary_down && !drag.dragging {
		delta_x := pointer.position.x - drag.start.x
		delta_y := pointer.position.y - drag.start.y
		if delta_x * delta_x + delta_y * delta_y >= action.drag_threshold * action.drag_threshold {
			drag.dragging = true
		}
	}
	drag.target = {}
	if drag.dragging && pointer.available {
		hit := pointer_hit_node(state, pointer.position, editor)
		if target, _, found := action_entity_for_node(state, world, hit, false);
		   found && target != drag.source {
			drag.target = target
		}
	}
	interaction := ecs.ensure_ui_state(world, source_index)
	if interaction != nil {
		was_dragging := interaction.dragging
		was_target := interaction.drop_target
		interaction.dragging = drag.dragging
		interaction.drag_source = world.entities[source_index].uuid
		interaction.drop_target = {}
		interaction.drop_placement = .None
		if drag.target != (shared.Entity{}) {
			target_index := int(drag.target.index)
			if ecs.entity_is_alive(world, target_index) &&
			   world.entities[target_index].id == drag.target {
				interaction.drop_target = world.entities[target_index].uuid
				interaction.drop_placement = .Into
			}
		}
		if was_dragging != interaction.dragging || was_target != interaction.drop_target {
			ecs.mark_ui_paint_changed(world, source_index)
		}
	}
	if !released {
		if !pointer.available {
			action_drag_reset(state, world, slot)
		}
		return
	}
	if drag.dragging && drag.target != (shared.Entity{}) {
		target_index := int(drag.target.index)
		if ecs.entity_is_alive(world, target_index) &&
		   world.entities[target_index].id == drag.target {
			target_interaction := ecs.ensure_ui_state(world, target_index)
			if target_interaction != nil {
				target_interaction.drag_source = world.entities[source_index].uuid
				target_interaction.drop_target = world.entities[target_index].uuid
				target_interaction.drop_placement = .Into
				target_interaction.drop_revision += 1
				target_interaction.changed = true
				target_interaction.change_revision += 1
				ecs.mark_ui_paint_changed(world, target_index)
			}
			append_ui_event(
				state,
				{
					kind = .Dropped,
					entity = drag.target,
					source = drag.source,
					target = drag.target,
					drop_placement = .Into,
					position = pointer.position,
				},
			)
		}
	}
	action_drag_reset(state, world, slot)
}

action_drag_pointer_cursor :: proc(state: ^State) -> Pointer_Cursor {
	if state == nil {
		return .Default
	}
	for drag in state.action_drags {
		if !drag.armed {
			continue
		}
		if !drag.dragging || drag.target != (shared.Entity{}) {
			return .Move
		}
		return .Not_Allowed
	}
	return .Default
}

action_drop_target_active :: proc(state: ^State, entity: shared.Entity) -> bool {
	if state == nil {
		return false
	}
	for drag in state.action_drags {
		if drag.dragging && drag.target == entity {
			return true
		}
	}
	return false
}

list_drag_begin :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
	editor: bool,
) {
	if state == nil || world == nil {
		return
	}
	node_index := find_node(state, pressed)
	list, item, found := list_item_for_node(state, world, node_index)
	if !found {
		return
	}
	list_index := int(list.index)
	if !ecs.entity_is_alive(world, list_index) || world.entities[list_index].id != list {
		return
	}
	component_index := world.entities[list_index].ui_list_index
	if component_index < 0 ||
	   component_index >= len(world.ui_lists) ||
	   !world.ui_lists[component_index].draggable {
		return
	}
	slot := 0
	if editor {
		slot = 1
	}
	if state.action_drags[slot].armed {
		return
	}
	state.list_drags[slot] = {
		list = list,
		source = item,
		start = position,
		armed = true,
	}
}

list_drag_reset :: proc(state: ^State, world: ^shared.World, slot: int) {
	if state == nil || slot < 0 || slot >= len(state.list_drags) {
		return
	}
	drag := &state.list_drags[slot]
	list_index := int(drag.list.index)
	if world != nil &&
	   ecs.entity_is_alive(world, list_index) &&
	   world.entities[list_index].id == drag.list {
		interaction := ecs.ensure_ui_state(world, list_index)
		if interaction != nil {
			paint_changed := interaction.dragging
			interaction.dragging = false
			if paint_changed {
				ecs.mark_ui_paint_changed(world, list_index)
			}
		}
	}
	drag^ = {}
}

tree_list_item_layout :: proc(
	state: ^State,
	world: ^shared.World,
	list_node_index: int,
	item: shared.Entity,
) -> (
	^shared.UI_Layout_Component,
	int,
	bool,
) {
	node_index := find_node(state, item)
	if node_index < 0 || state.nodes[node_index].parent_node_index != list_node_index {
		return nil, -1, false
	}
	entity_index := int(item.index)
	if !ecs.entity_is_alive(world, entity_index) || world.entities[entity_index].id != item {
		return nil, -1, false
	}
	layout_index := world.entities[entity_index].ui_layout_index
	if layout_index < 0 || layout_index >= len(world.ui_layouts) {
		return nil, -1, false
	}
	layout := &world.ui_layouts[layout_index]
	return layout, entity_index, layout.tree_item
}

tree_list_would_cycle :: proc(
	state: ^State,
	world: ^shared.World,
	list_node_index: int,
	source_uuid, parent_uuid: shared.Entity_UUID,
) -> bool {
	cursor := parent_uuid
	for _ in 0 ..< MAX_NODES {
		if cursor == (shared.Entity_UUID{}) {
			return false
		}
		if cursor == source_uuid {
			return true
		}
		entity_index, found := world.entity_by_uuid[cursor]
		if !found {
			return false
		}
		node_index := find_node_by_entity_index(state, entity_index)
		if node_index < 0 || state.nodes[node_index].parent_node_index != list_node_index {
			return false
		}
		layout_index := world.entities[entity_index].ui_layout_index
		if layout_index < 0 || layout_index >= len(world.ui_layouts) {
			return false
		}
		cursor = world.ui_layouts[layout_index].tree_parent
	}
	return true
}

tree_list_apply_drop :: proc(
	state: ^State,
	world: ^shared.World,
	list_node_index: int,
	source, target: shared.Entity,
	placement: shared.UI_Drop_Placement,
) -> bool {
	source_layout, source_index, source_ok := tree_list_item_layout(
		state,
		world,
		list_node_index,
		source,
	)
	if !source_ok {
		return false
	}
	new_parent: shared.Entity_UUID
	insert_index := -1
	target_uuid: shared.Entity_UUID
	if target != (shared.Entity{}) {
		target_layout, target_index, target_ok := tree_list_item_layout(
			state,
			world,
			list_node_index,
			target,
		)
		if !target_ok {
			return false
		}
		target_uuid = world.entities[target_index].uuid
		switch placement {
			case .Into:
				new_parent = target_uuid
			case .Before, .After:
				new_parent = target_layout.tree_parent
			case .None, .Left, .Right, .Above, .Below:
				return false
		}
	} else if placement != .Into {
		return false
	}
	source_uuid := world.entities[source_index].uuid
	old_parent := source_layout.tree_parent
	if tree_list_would_cycle(state, world, list_node_index, source_uuid, new_parent) {
		return false
	}
	siblings: [MAX_NODES]int
	sibling_count := 0
	child := state.nodes[list_node_index].first_child_node
	for child >= 0 {
		next := state.nodes[child].next_sibling_node
		entity_index := int(state.nodes[child].entity.index)
		if entity_index != source_index &&
		   ecs.entity_is_alive(world, entity_index) &&
		   world.entities[entity_index].ui_layout_index >= 0 &&
		   world.entities[entity_index].ui_layout_index < len(world.ui_layouts) {
			layout := world.ui_layouts[world.entities[entity_index].ui_layout_index]
			if layout.tree_item && layout.tree_parent == new_parent {
				siblings[sibling_count] = child
				sibling_count += 1
			}
		}
		child = next
	}
	sort_tree_nodes(state, world, &siblings, sibling_count)
	if target != (shared.Entity{}) && placement != .Into {
		for index in 0 ..< sibling_count {
			if state.nodes[siblings[index]].entity == target {
				insert_index = index
				if placement == .After {
					insert_index += 1
				}
				break
			}
		}
		if insert_index < 0 {
			return false
		}
	}
	if insert_index < 0 {
		insert_index = sibling_count
	}
	ordered: [MAX_NODES]int
	ordered_count := 0
	for index in 0 ..< insert_index {
		ordered[ordered_count] = siblings[index]
		ordered_count += 1
	}
	ordered[ordered_count] = find_node(state, source)
	ordered_count += 1
	for index in insert_index ..< sibling_count {
		ordered[ordered_count] = siblings[index]
		ordered_count += 1
	}
	for order in 0 ..< ordered_count {
		item_node := state.nodes[ordered[order]]
		entity_index := int(item_node.entity.index)
		layout_index := world.entities[entity_index].ui_layout_index
		value := world.ui_layouts[layout_index]
		value.tree_parent = new_parent
		value.tree_order = order
		if !ecs.set_ui_layout(world, entity_index, value) {
			return false
		}
	}
	if old_parent != new_parent {
		old_siblings: [MAX_NODES]int
		old_sibling_count := 0
		child = state.nodes[list_node_index].first_child_node
		for child >= 0 {
			next := state.nodes[child].next_sibling_node
			entity_index := int(state.nodes[child].entity.index)
			if entity_index != source_index &&
			   ecs.entity_is_alive(world, entity_index) &&
			   world.entities[entity_index].ui_layout_index >= 0 &&
			   world.entities[entity_index].ui_layout_index < len(world.ui_layouts) {
				layout := world.ui_layouts[world.entities[entity_index].ui_layout_index]
				if layout.tree_item && layout.tree_parent == old_parent {
					old_siblings[old_sibling_count] = child
					old_sibling_count += 1
				}
			}
			child = next
		}
		sort_tree_nodes(state, world, &old_siblings, old_sibling_count)
		for order in 0 ..< old_sibling_count {
			item_node := state.nodes[old_siblings[order]]
			entity_index := int(item_node.entity.index)
			layout_index := world.entities[entity_index].ui_layout_index
			value := world.ui_layouts[layout_index]
			value.tree_order = order
			if !ecs.set_ui_layout(world, entity_index, value) {
				return false
			}
		}
	}
	return true
}

list_drag_update :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	released: bool,
	editor: bool,
) {
	if state == nil || world == nil {
		return
	}
	slot := 0
	if editor {
		slot = 1
	}
	drag := &state.list_drags[slot]
	if !drag.armed {
		return
	}
	list_index := int(drag.list.index)
	if !ecs.entity_is_alive(world, list_index) || world.entities[list_index].id != drag.list {
		list_drag_reset(state, world, slot)
		return
	}
	component_index := world.entities[list_index].ui_list_index
	if component_index < 0 || component_index >= len(world.ui_lists) {
		list_drag_reset(state, world, slot)
		return
	}
	list := world.ui_lists[component_index]
	if pointer.primary_down && !drag.dragging {
		delta_x := pointer.position.x - drag.start.x
		delta_y := pointer.position.y - drag.start.y
		if delta_x * delta_x + delta_y * delta_y >= list.drag_threshold * list.drag_threshold {
			drag.dragging = true
		}
	}
	list_node_index := find_node(state, drag.list)
	inside_list :=
		pointer.available &&
		list_node_index >= 0 &&
		node_pointer_contains(state.nodes[list_node_index], pointer.position)
	drag.target = {}
	drag.drop_valid = false
	drag.placement = .None
	if drag.dragging && inside_list {
		hit := pointer_hit_node(state, pointer.position, editor)
		if target_list, target, found := list_item_for_node(state, world, hit);
		   found && target_list == drag.list {
			if target != drag.source {
				drag.target = target
				target_node_index := find_node(state, target)
				if target_node_index >= 0 {
					target_node := state.nodes[target_node_index]
					edge_height := target_node.rect.height * list.drop_edge_fraction
					if pointer.position.y < target_node.rect.y + edge_height {
						drag.placement = .Before
					} else if pointer.position.y >
					   target_node.rect.y + target_node.rect.height - edge_height {
						drag.placement = .After
					} else {
						drag.placement = .Into
					}
				}
				drag.drop_valid = true
			}
		} else {
			drag.placement = .Into
			drag.drop_valid = true
		}
	}
	interaction := ecs.ensure_ui_state(world, list_index)
	if interaction != nil {
		was_dragging := interaction.dragging
		was_source := interaction.drag_source
		was_target := interaction.drop_target
		was_placement := interaction.drop_placement
		interaction.dragging = drag.dragging
		interaction.drag_source = {}
		source_index := int(drag.source.index)
		if ecs.entity_is_alive(world, source_index) &&
		   world.entities[source_index].id == drag.source {
			interaction.drag_source = world.entities[source_index].uuid
		} else {
			list_drag_reset(state, world, slot)
			return
		}
		interaction.drop_target = {}
		interaction.drop_placement = drag.placement
		if drag.target != (shared.Entity{}) {
			target_index := int(drag.target.index)
			if ecs.entity_is_alive(world, target_index) &&
			   world.entities[target_index].id == drag.target {
				interaction.drop_target = world.entities[target_index].uuid
			}
		}
		if was_dragging != interaction.dragging ||
		   was_source != interaction.drag_source ||
		   was_target != interaction.drop_target ||
		   was_placement != interaction.drop_placement {
			ecs.mark_ui_paint_changed(world, list_index)
		}
	}
	if !released {
		if !pointer.available {
			list_drag_reset(state, world, slot)
		}
		return
	}
	if drag.dragging && inside_list && drag.drop_valid {
		if list.tree_enabled &&
		   !tree_list_apply_drop(
				   state,
				   world,
				   list_node_index,
				   drag.source,
				   drag.target,
				   drag.placement,
			   ) {
			list_drag_reset(state, world, slot)
			return
		}
		if interaction != nil {
			interaction.drop_revision += 1
			interaction.changed = true
			interaction.change_revision += 1
		}
		append_ui_event(
			state,
			{
				kind = .Dropped,
				entity = drag.list,
				source = drag.source,
				target = drag.target,
				drop_placement = drag.placement,
				position = pointer.position,
			},
		)
	}
	list_drag_reset(state, world, slot)
}

set_popup_open :: proc(world: ^shared.World, entity_index: int, open: bool) -> bool {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	layout := world.ui_layouts[entity.ui_layout_index]
	if !ui_layout_is_popup(layout) || layout.popup_open == open {
		return false
	}
	layout.popup_open = open
	if !ecs.set_ui_layout(world, entity_index, layout) {
		return false
	}
	return true
}

set_popup_open_from_interaction :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	open: bool,
) -> bool {
	if !set_popup_open(world, entity_index, open) {
		return false
	}
	_ = mark_ui_event(state, world, .Changed, world.entities[entity_index].id)
	return true
}

popup_contains_node :: proc(state: ^State, popup_node_index, node_index: int) -> bool {
	if state == nil || popup_node_index < 0 || node_index < 0 {
		return false
	}
	for index := node_index; index >= 0; index = state.nodes[index].parent_node_index {
		if index == popup_node_index {
			return true
		}
	}
	return false
}

handle_popup_press :: proc(state: ^State, world: ^shared.World, pressed: shared.Entity) -> bool {
	if state == nil || world == nil {
		return false
	}
	pressed_node_index := find_node(state, pressed)
	pressed_entity_index := int(pressed.index)
	if pressed_entity_index < 0 || pressed_entity_index >= len(world.entities) {
		return false
	}
	pressed_entity := world.entities[pressed_entity_index]
	changed := false
	toggle_node_index := -1
	popup_target: shared.Entity_UUID
	if pressed_entity.ui_button_index >= 0 &&
	   pressed_entity.ui_button_index < len(world.ui_buttons) {
		popup_target = world.ui_buttons[pressed_entity.ui_button_index].popup
	}
	for node, node_index in state.nodes[:state.node_count] {
		if (node.origin == .Editor) != (pressed_entity.origin == .Editor) {
			continue
		}
		layout := world.ui_layouts[node.layout_index]
		if !ui_layout_is_popup(layout) {
			continue
		}
		if popup_target != (shared.Entity_UUID{}) &&
		   world.entities[int(node.entity.index)].uuid == popup_target {
			toggle_node_index = node_index
			continue
		}
		if layout.popup_open && !popup_contains_node(state, node_index, pressed_node_index) {
			changed =
				set_popup_open_from_interaction(state, world, int(node.entity.index), false) ||
				changed
		}
	}
	if toggle_node_index >= 0 {
		node := state.nodes[toggle_node_index]
		layout := world.ui_layouts[node.layout_index]
		if layout.popup_anchor != pressed_entity.uuid {
			layout.popup_anchor = pressed_entity.uuid
			_ = ecs.set_ui_layout(world, int(node.entity.index), layout)
		}
		changed =
			set_popup_open_from_interaction(
				state,
				world,
				int(node.entity.index),
				!layout.popup_open,
			) ||
			changed
	}
	return changed
}

close_selection_popup :: proc(
	state: ^State,
	world: ^shared.World,
	selected: shared.Entity,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	for node_index := find_node(state, selected);
	    node_index >= 0;
	    node_index = state.nodes[node_index].parent_node_index {
		node := state.nodes[node_index]
		layout := world.ui_layouts[node.layout_index]
		if ui_layout_is_popup(layout) && layout.popup_open && layout.popup_close_on_selection {
			return set_popup_open_from_interaction(state, world, int(node.entity.index), false)
		}
	}
	return false
}

close_popups_on_escape :: proc(
	state: ^State,
	world: ^shared.World,
	editor_only := false,
	project_only := false,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	changed := false
	for node in state.nodes[:state.node_count] {
		if editor_only && node.origin != .Editor {
			continue
		}
		if project_only && node.origin == .Editor {
			continue
		}
		layout := world.ui_layouts[node.layout_index]
		if ui_layout_is_popup(layout) && layout.popup_open {
			changed =
				set_popup_open_from_interaction(state, world, int(node.entity.index), false) ||
				changed
		}
	}
	return changed
}

handle_list_press :: proc(state: ^State, world: ^shared.World, pressed: shared.Entity) -> bool {
	if state == nil || world == nil { return false }
	item_index := int(pressed.index)
	for item_index >= 0 && item_index < len(world.entities) {
		item := world.entities[item_index]
		if item.ui_layout_index < 0 || item.ui_layout_index >= len(world.ui_layouts) {
			return false
		}
		parent_index := find_parent_entity(
			world,
			world.ui_layouts[item.ui_layout_index].parent,
			item.origin,
		)
		if parent_index < 0 || parent_index >= len(world.entities) { return false }
		parent := world.entities[parent_index]
		if parent.ui_list_index >= 0 && parent.ui_list_index < len(world.ui_lists) {
			list := world.ui_lists[parent.ui_list_index]
			if list.selected == item.uuid { return false }
			list.selected = item.uuid
			_ = ecs.set_ui_list(world, parent_index, list)
			_ = mark_ui_event(state, world, .Changed, parent.id)
			return true
		}
		item_index = parent_index
	}
	return false
}

update_interaction :: proc(
	state: ^State,
	pointer: Pointer_Input,
	editor: bool,
) -> (
	shared.Entity,
	bool,
	shared.Entity,
	bool,
	bool,
	int,
) {
	for &node in state.nodes[:state.node_count] { if (node.origin == .Editor) == editor { node.hovered = false; node.active = false } }
	previous_down := state.previous_primary_down
	has_active := state.has_active_entity
	active_entity := state.active_entity
	if editor { previous_down = state.editor_previous_primary_down; has_active = state.editor_ui_has_active_entity; active_entity = state.editor_ui_active_entity }
	if !pointer.available {
		if editor { state.editor_ui_has_active_entity = false; state.editor_previous_primary_down = false } else { state.has_active_entity = false; state.previous_primary_down = false }
		return {}, false, {}, false, false, -1
	}
	hit := -1
	highest_order := -1
	for node, index in state.nodes[:state.node_count] {
		if (node.origin == .Editor) != editor { continue }
		if !node.laid_out { continue }
		if node_pointer_contains(node, pointer.position) &&
		   node.paint_order >= highest_order { hit = index; highest_order = node.paint_order }
	}
	if hit >= 0 { mark_interaction_chain(state, hit, false) }
	pressed, pressed_ok := shared.Entity{}, false
	released, released_ok, released_inside := shared.Entity{}, false, false
	if pointer_press_started(pointer, previous_down) {
		has_active = hit >= 0
		if hit >=
		   0 { active_entity = state.nodes[hit].entity; pressed = active_entity; pressed_ok = true }
	}
	if pointer.primary_down && has_active {
		if active_index := find_node(state, active_entity);
		   active_index >=
		   0 { mark_interaction_chain(state, active_index, true) } else { has_active = false }
	} else if pointer_press_released(pointer, previous_down) {
		if has_active {
			released = active_entity
			released_ok = true
			if active_index := find_node(state, active_entity); active_index >= 0 {
				released_inside = node_pointer_contains(
					state.nodes[active_index],
					pointer.position,
				)
			}
		}
		has_active = false
	} else if !pointer.primary_down {
		has_active = false
	}
	if editor { state.editor_ui_has_active_entity = has_active; state.editor_ui_active_entity = active_entity; state.editor_previous_primary_down = pointer.primary_down } else { state.has_active_entity = has_active; state.active_entity = active_entity; state.previous_primary_down = pointer.primary_down }
	return pressed, pressed_ok, released, released_ok, released_inside, hit
}

entity_is_ui_button :: proc(world: ^shared.World, entity: shared.Entity) -> bool {
	if world == nil {
		return false
	}
	entity_index := int(entity.index)
	return(
		entity_index >= 0 &&
		entity_index < len(world.entities) &&
		world.entities[entity_index].alive &&
		world.entities[entity_index].id == entity &&
		world.entities[entity_index].ui_button_index >= 0 \
	)
}

node_pointer_contains :: proc(node: Node, point: shared.Vec2) -> bool {return(
		rect_contains(node.rect, point) &&
		(!node.has_clip || rect_contains(node.clip, point)) \
	)}
rect_intersection :: proc(a, b: Rect) -> Rect {x0 := max(a.x, b.x); y0 := max(a.y, b.y); x1 := min(
		a.x + a.width,
		b.x + b.width,
	)
	y1 := min(a.y + a.height, b.y + b.height)
	return{x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}}

handle_panel_title_press :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
) -> bool {
	if state == nil || world == nil { return false }
	node_index := find_node(state, pressed)
	if node_index < 0 { return false }
	node := &state.nodes[node_index]
	if !node.laid_out ||
	   node.panel_index < 0 ||
	   node.panel_index >= len(world.ui_panels) { return false }
	panel := world.ui_panels[node.panel_index]
	if !panel.collapsible || panel.title == "" { return false }
	title_height := min(max(panel.title_height, 0), node.rect.height)
	title_rect := Rect{node.rect.x, node.rect.y, node.rect.width, title_height}
	if !rect_contains(title_rect, position) ||
	   node.has_clip && !rect_contains(node.clip, position) { return false }
	panel.collapsed = !panel.collapsed
	_ = ecs.set_ui_panel(world, int(node.entity.index), panel)
	_ = mark_ui_event(state, world, .Changed, node.entity, position, .Panel_Title)
	return true
}

handle_checkbox_press :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
) -> bool {
	if state == nil || world == nil { return false }
	node_index := find_node(state, pressed)
	if node_index < 0 { return false }
	node := &state.nodes[node_index]
	if !node.laid_out ||
	   node.checkbox_index < 0 ||
	   node.checkbox_index >= len(world.ui_checkboxes) { return false }
	checkbox := world.ui_checkboxes[node.checkbox_index]
	if checkbox.read_only { return false }
	entity_index := int(node.entity.index)
	checkbox.checked = !checkbox.checked
	if !ecs.set_ui_checkbox(world, entity_index, checkbox) { return false }
	_ = mark_ui_event(state, world, .Changed, node.entity)
	return true
}

append_ui_gradient :: proc(
	state: ^State,
	rect: Rect,
	top_left, top_right, bottom_right, bottom_left: shared.Vec4,
	corner_radius: f32 = 0,
) -> string {
	return append_paint(
		state,
		{
			kind = .Panel,
			rect = rect,
			color = top_left,
			corner_radius = corner_radius,
			gradient = true,
			corner_colors = {top_left, top_right, bottom_right, bottom_left},
		},
	)
}

color_picker_display_color :: proc(value: shared.Vec3) -> shared.Vec4 {
	return {value.x / (1 + value.x), value.y / (1 + value.y), value.z / (1 + value.z), 1}
}

append_color_picker_thumb :: proc(
	state: ^State,
	center: shared.Vec2,
	picker: shared.UI_Color_Picker_Component,
) -> string {
	radius := picker.thumb_radius
	return append_paint(
		state,
		{
			kind = .Panel,
			rect = {center.x - radius, center.y - radius, radius * 2, radius * 2},
			color = picker.thumb_color,
			corner_radius = radius,
			border_color = picker.thumb_border_color,
			border_width = picker.thumb_border_width,
		},
	)
}

paint_color_picker :: proc(
	state: ^State,
	node: Node,
	picker: shared.UI_Color_Picker_Component,
) -> string {
	sv, hue_rect, alpha_rect, exposure_rect := color_picker_rects(node.rect, picker)
	scale := math.pow(f32(2), picker.exposure)
	base := shared.Vec3{picker.value.x / scale, picker.value.y / scale, picker.value.z / scale}
	hsv := color_picker_rgb_to_hsv(base)
	hue_rgb := color_picker_hsv_to_rgb({hsv.x, 1, 1})
	hue_color := shared.Vec4{hue_rgb.x, hue_rgb.y, hue_rgb.z, 1}
	if err := append_ui_gradient(state, sv, {1, 1, 1, 1}, hue_color, hue_color, {1, 1, 1, 1});
	   err != "" {
		return err
	}
	if err := append_ui_gradient(
		state,
		sv,
		{0, 0, 0, 0},
		{0, 0, 0, 0},
		{0, 0, 0, 1},
		{0, 0, 0, 1},
	); err != "" {
		return err
	}
	hue_colors := [7]shared.Vec4 {
		{1, 0, 0, 1},
		{1, 1, 0, 1},
		{0, 1, 0, 1},
		{0, 1, 1, 1},
		{0, 0, 1, 1},
		{1, 0, 1, 1},
		{1, 0, 0, 1},
	}
	for index in 0 ..< 6 {
		x0 := hue_rect.x + hue_rect.width * f32(index) / 6
		x1 := hue_rect.x + hue_rect.width * f32(index + 1) / 6
		if err := append_ui_gradient(
			state,
			{x0, hue_rect.y, x1 - x0, hue_rect.height},
			hue_colors[index],
			hue_colors[index + 1],
			hue_colors[index + 1],
			hue_colors[index],
		); err != "" {
			return err
		}
	}
	if picker.show_alpha {
		cell := max(alpha_rect.height * 0.5, f32(2))
		column_count := int(math.ceil(alpha_rect.width / cell))
		for column in 0 ..< column_count {
			for row in 0 ..< 2 {
				color := picker.checker_light
				if (column + row) % 2 != 0 {
					color = picker.checker_dark
				}
				x := alpha_rect.x + f32(column) * cell
				y := alpha_rect.y + f32(row) * cell
				if err := append_paint(
					state,
					{
						kind = .Panel,
						rect = {
							x,
							y,
							min(cell, alpha_rect.x + alpha_rect.width - x),
							min(cell, alpha_rect.y + alpha_rect.height - y),
						},
						color = color,
					},
				); err != "" {
					return err
				}
			}
		}
		display := color_picker_display_color({picker.value.x, picker.value.y, picker.value.z})
		transparent := display
		transparent.w = 0
		if err := append_ui_gradient(
			state,
			alpha_rect,
			transparent,
			display,
			display,
			transparent,
		); err != "" {
			return err
		}
	}
	if picker.hdr && picker.maximum_exposure > 0 {
		segments := 8
		for index in 0 ..< segments {
			x0 := exposure_rect.x + exposure_rect.width * f32(index) / f32(segments)
			x1 := exposure_rect.x + exposure_rect.width * f32(index + 1) / f32(segments)
			exposure0 := picker.maximum_exposure * f32(index) / f32(segments)
			exposure1 := picker.maximum_exposure * f32(index + 1) / f32(segments)
			rgb0 := color_picker_hsv_to_rgb({hsv.x, hsv.y, hsv.z})
			rgb1 := rgb0
			scale0 := math.pow(f32(2), exposure0)
			scale1 := math.pow(f32(2), exposure1)
			left := color_picker_display_color({rgb0.x * scale0, rgb0.y * scale0, rgb0.z * scale0})
			right := color_picker_display_color(
				{rgb1.x * scale1, rgb1.y * scale1, rgb1.z * scale1},
			)
			if err := append_ui_gradient(
				state,
				{x0, exposure_rect.y, x1 - x0, exposure_rect.height},
				left,
				right,
				right,
				left,
			); err != "" {
				return err
			}
		}
	}
	if err := append_color_picker_thumb(
		state,
		{sv.x + hsv.y * sv.width, sv.y + (1 - hsv.z) * sv.height},
		picker,
	); err != "" {
		return err
	}
	if err := append_color_picker_thumb(
		state,
		{hue_rect.x + hsv.x * hue_rect.width, hue_rect.y + hue_rect.height * 0.5},
		picker,
	); err != "" {
		return err
	}
	if picker.show_alpha {
		if err := append_color_picker_thumb(
			state,
			{
				alpha_rect.x + picker.value.w * alpha_rect.width,
				alpha_rect.y + alpha_rect.height * 0.5,
			},
			picker,
		); err != "" {
			return err
		}
	}
	if picker.hdr && picker.maximum_exposure > 0 {
		if err := append_color_picker_thumb(
			state,
			{
				exposure_rect.x + picker.exposure / picker.maximum_exposure * exposure_rect.width,
				exposure_rect.y + exposure_rect.height * 0.5,
			},
			picker,
		); err != "" {
			return err
		}
	}
	return ""
}

paint_node :: proc(state: ^State, world: ^shared.World, node_index, depth: int) -> string {
	if depth > MAX_NODES { return "UI hierarchy contains a cycle" }
	when ODIN_TEST {
		state.paint_node_visit_count += 1
	}
	node := &state.nodes[node_index]; layout := world.ui_layouts[node.layout_index]
	if !node.laid_out { return "" }
	if node.has_clip {
		visible := rect_intersection(node.rect, node.clip)
		if visible.width <= 0 || visible.height <= 0 { return "" }
	}
	paint_start := state.paint_count
	background := layout.background
	background_corner_radius := layout.corner_radius
	border_color := layout.border_color
	border_width := layout.border_width
	if node.viewport_index >= 0 && node.viewport_index < len(world.ui_viewports) {
		background = {}
	}
	entity_index := int(node.entity.index)
	if action_drop_target_active(state, node.entity) &&
	   ecs.entity_is_alive(world, entity_index) &&
	   world.entities[entity_index].id == node.entity {
		action_index := world.entities[entity_index].ui_action_index
		if action_index >= 0 && action_index < len(world.ui_actions) {
			action := world.ui_actions[action_index]
			if action.drop_target && action.drop_background.w > 0 {
				background = action.drop_background
			}
		}
	}
	if node.parent_entity_index >= 0 && node.parent_entity_index < len(world.entities) {
		parent := world.entities[node.parent_entity_index]
		if parent.ui_list_index >= 0 && parent.ui_list_index < len(world.ui_lists) {
			list := world.ui_lists[parent.ui_list_index]
			selected := list.selected == world.entities[int(node.entity.index)].uuid
			if selected && list.selection_background.w > 0 {
				background = list.selection_background
				background_corner_radius = list.highlight_corner_radius
			}
			if !selected && node.hovered && list.hover_background.w > 0 {
				background = list.hover_background
				background_corner_radius = list.highlight_corner_radius
			}
			if node.active && list.active_background.w > 0 {
				background = list.active_background
				background_corner_radius = list.highlight_corner_radius
			}
			if parent.ui_state_index >= 0 && parent.ui_state_index < len(world.ui_states) {
				interaction := world.ui_states[parent.ui_state_index]
				if interaction.dragging &&
				   interaction.drop_placement == .Into &&
				   interaction.drop_target == world.entities[int(node.entity.index)].uuid &&
				   list.drop_target_background.w > 0 {
					background = list.drop_target_background
					background_corner_radius = list.highlight_corner_radius
				}
			}
		}
	}
	if node.button_index >= 0 && node.button_index < len(world.ui_buttons) {
		button := world.ui_buttons[node.button_index]
		if node.active &&
		   button.active_background.w >
			   0 { background = button.active_background } else if node.hovered && button.hover_background.w > 0 { background = button.hover_background }
	}
	if node.input_index >= 0 &&
	   node.input_index < len(world.ui_inputs) &&
	   state.has_focused_input &&
	   state.focused_input == node.entity {
		input := world.ui_inputs[node.input_index]
		if !state.input_valid {
			border_color = input.invalid_border_color
			border_width = max(border_width, input.invalid_border_width)
		} else if input.focus_border_color.w > 0 {
			border_color = input.focus_border_color
			border_width = max(border_width, input.focus_border_width)
		}
	}
	if background.w > 0 || border_color.w > 0 && border_width > 0 {
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = node.rect,
				color = background,
				corner_radius = background_corner_radius,
				border_color = border_color,
				border_width = border_width,
			},
		); err != "" { return err }
	}
	if node.viewport_layer >= 0 && node.viewport_layer < state.viewport_surface_count {
		if err := append_paint(
			state,
			{
				kind = .Viewport,
				rect = node.rect,
				color = {1, 1, 1, 1},
				uv = {0, 0, 1, 1},
				font_layer = f32(node.viewport_layer),
			},
		); err != "" {
			return err
		}
	} else if node.viewport_index >= 0 && node.viewport_index < len(world.ui_viewports) {
		viewport := world.ui_viewports[node.viewport_index]
		if !viewport.interactive && viewport.resource != (shared.Resource_UUID{}) {
			if err := append_paint(
				state,
				{
					kind = .Thumbnail,
					rect = node.rect,
					color = {1, 1, 1, 1},
					uv = {0, 0, 1, 1},
					font_layer = -1,
					resource = viewport.resource,
				},
			); err != "" {
				return err
			}
		}
	}
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		panel := world.ui_panels[node.panel_index]
		if panel.title != "" && !node_is_docked_panel(state, world, node_index) {
			select_font(state, panel.font)
			title_height := min(max(panel.title_height, 0), node.rect.height)
			title_rect := Rect{node.rect.x, node.rect.y, node.rect.width, title_height}
			if panel.title_background.w > 0 {
				if err := append_paint(
					state,
					{
						kind = .Panel,
						rect = title_rect,
						color = panel.title_background,
						corner_radius = layout.corner_radius,
					},
				); err != "" { return err }
			}
			text_left := panel.disclosure_margin
			if panel.collapsible {
				disclosure_size := min(
					panel.disclosure_size,
					max(title_height - panel.disclosure_margin, 0),
				)
				disclosure_rect := Rect {
					title_rect.x + panel.disclosure_margin,
					title_rect.y + (title_height - disclosure_size) * 0.5,
					disclosure_size,
					disclosure_size,
				}
				disclosure_icon := shared.UI_Icon_Component {
					icon_set = shared.builtin_icon_set_uuid(),
					icon = panel.collapsed ? "caret-right" : "caret-down",
					color = panel.title_color,
					inset = panel.disclosure_inset,
				}
				if err := append_icon(state, disclosure_icon, disclosure_rect, {}); err != "" {
					return err
				}
				text_left = panel.disclosure_margin + disclosure_size + panel.disclosure_gap
			}
			text_right := f32(10)
			text_rect := Rect {
				title_rect.x + text_left,
				title_rect.y + max((title_height - panel.title_size * 1.25) * 0.5, 0),
				max(title_rect.width - text_left - text_right, 0),
				panel.title_size * 1.5,
			}
			if err := append_text(
				state,
				panel.title,
				panel.title_color,
				panel.title_size,
				text_rect,
				{},
			); err != "" { return err }
		}
	}
	if node.progress_index >= 0 && node.progress_index < len(world.ui_progresses) {
		progress := world.ui_progresses[node.progress_index]
		track := Rect {
			node.rect.x + progress.inset.w,
			node.rect.y + progress.inset.x,
			max(node.rect.width - progress.inset.w - progress.inset.y, 0),
			max(node.rect.height - progress.inset.x - progress.inset.z, 0),
		}
		if track.width > 0 && track.height > 0 {
			if progress.background_color.w > 0 {
				if err := append_paint(
					state,
					{
						kind = .Panel,
						rect = track,
						color = progress.background_color,
						corner_radius = progress.corner_radius,
					},
				); err != "" { return err }
			}
			ratio := clamp(progress.value / progress.maximum, f32(0), f32(1))
			fill := track
			fill.width *= ratio
			if progress.right_to_left {
				fill.x = track.x + track.width - fill.width
			}
			if fill.width > 0 && progress.fill_color.w > 0 {
				if err := append_paint(
					state,
					{
						kind = .Panel,
						rect = fill,
						color = progress.fill_color,
						corner_radius = min(progress.corner_radius, fill.width * 0.5),
					},
				); err != "" { return err }
			}
		}
	}
	if node.icon_index >= 0 && node.icon_index < len(world.ui_icons) {
		if err := append_icon(state, world.ui_icons[node.icon_index], node.rect, layout.padding);
		   err != "" { return err }
	}
	if node.text_index >= 0 &&
	   node.text_index <
		   len(
			   world.ui_texts,
		   ) { text := world.ui_texts[node.text_index]; select_font(state, text.font); if err := append_text(state, text.text, text.color, text.size, node.rect, layout.padding, text.alignment, text.wrap, text.line_height); err != "" { return err } }
	if node.input_index >= 0 && node.input_index < len(world.ui_inputs) {
		select_font(state, world.ui_inputs[node.input_index].font)
		if err := append_input(
			state,
			world,
			world.ui_inputs[node.input_index],
			node^,
			layout.padding,
		); err != "" { return err }
	}
	if node.checkbox_index >= 0 && node.checkbox_index < len(world.ui_checkboxes) {
		checkbox := world.ui_checkboxes[node.checkbox_index]
		box_size := min(max(checkbox.box_size, 1), min(node.rect.width, node.rect.height))
		box_rect := Rect {
			node.rect.x + layout.padding.w,
			node.rect.y + (node.rect.height - box_size) * 0.5,
			box_size,
			box_size,
		}
		box_background := checkbox.background
		if checkbox.checked { box_background = checkbox.checked_background }
		if !checkbox.read_only {
			if node.active && checkbox.active_background.w > 0 {
				box_background = checkbox.active_background
			} else if node.hovered && checkbox.hover_background.w > 0 {
				box_background = checkbox.hover_background
			}
		}
		corner_radius := checkbox.corner_radius
		if corner_radius < 0 {
			corner_radius = min(box_size * 0.22, 4)
		}
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = box_rect,
				color = box_background,
				corner_radius = corner_radius,
				border_color = checkbox.border_color,
				border_width = checkbox.border_width,
			},
		); err != "" { return err }
		if checkbox.checked {
			inset := checkbox.check_inset
			if inset < 0 {
				inset = max(box_size * 0.22, 3)
			}
			check_corner_radius := checkbox.check_corner_radius
			if check_corner_radius < 0 {
				check_corner_radius = max(box_size * 0.12, 1.25)
			}
			if err := append_paint(
				state,
				{
					kind = .Checkmark,
					rect = {
						box_rect.x + inset,
						box_rect.y + inset,
						max(box_rect.width - inset * 2, 0),
						max(box_rect.height - inset * 2, 0),
					},
					color = checkbox.check_color,
					corner_radius = check_corner_radius,
				},
			); err != "" { return err }
		}
	}
	if node.color_picker_index >= 0 && node.color_picker_index < len(world.ui_color_pickers) {
		if err := paint_color_picker(
			state,
			node^,
			world.ui_color_pickers[node.color_picker_index],
		); err != "" {
			return err
		}
	}
	if node.button_index >= 0 && node.button_index < len(world.ui_buttons) {
		button := world.ui_buttons[node.button_index]
		select_font(state, button.font)
		color := button.color
		if node.active && button.active_color.w > 0 {
			color = button.active_color
		} else if node.hovered && button.hover_color.w > 0 {
			color = button.hover_color
		}
		if err := append_button_content(state, button, color, node.rect, layout.padding);
		   err != "" {
			return err
		}
	}
	if node.dock_space_index >= 0 && node.dock_space_index < len(world.ui_dock_spaces) {
		dock_space := world.ui_dock_spaces[node.dock_space_index]
		if dock_space.tab_strip_background.w > 0 {
			if err := append_paint(
				state,
				{
					kind = .Panel,
					rect = dock_space_tab_strip_rect(node^, layout, dock_space),
					color = dock_space.tab_strip_background,
				},
			); err != "" {
				return err
			}
		}
		if dock_space.content_background.w > 0 {
			if err := append_paint(
				state,
				{
					kind = .Panel,
					rect = dock_space_sheet_rect(node^, layout, dock_space),
					color = dock_space.content_background,
					corner_radius = dock_space.content_corner_radius,
				},
			); err != "" {
				return err
			}
		}
	}
	apply_paint_clip(state, paint_start, state.paint_count, node.clip, node.has_clip)
	child_index := node.first_child_node
	for child_index >= 0 {
		when ODIN_TEST {
			state.paint_child_edge_visit_count += 1
		}
		next_child_index := state.nodes[child_index].next_sibling_node
		if err := paint_node(state, world, child_index, depth + 1); err != "" {
			return err
		}
		child_index = next_child_index
	}
	if node.dock_space_index >= 0 && node.dock_space_index < len(world.ui_dock_spaces) {
		dock_space := world.ui_dock_spaces[node.dock_space_index]
		select_font(state, dock_space.font)
		panel_drag := state.stack_drags[0]
		if node.origin == .Editor {
			panel_drag = state.stack_drags[1]
		}
		drop_placement := shared.UI_Drop_Placement.None
		if state.dock_drop_space_node == node_index {
			drop_placement = state.dock_drop_space_placement
		} else if panel_drag.dragging && panel_drag.target_dock_space == node.entity {
			drop_placement = panel_drag.placement
		}
		if (state.dock_drop_space_node == node_index ||
			   panel_drag.dragging && panel_drag.target_dock_space == node.entity) &&
		   dock_space.drop_background.w > 0 {
			drop_rect := dock_space_content_rect(node^, dock_space)
			if ui_dock_split_is_directional(drop_placement) {
				drop_rect = dock_space_split_preview_rect(node^, dock_space, drop_placement)
			}
			if err := append_paint(
				state,
				{
					kind = .Panel,
					rect = drop_rect,
					color = dock_space.drop_background,
					corner_radius = dock_space.tab_corner_radius,
				},
			); err != "" {
				return err
			}
		}
		for tab in state.dock_tabs[:state.dock_tab_count] {
			if tab.space_node != node_index {
				continue
			}
			item_node := state.nodes[tab.item_node]
			title, is_dock_item := dock_item_title(world, item_node)
			if !is_dock_item {
				continue
			}
			background := dock_space.tab_background
			color := dock_space.tab_color
			if tab.active {
				background = dock_space.tab_active_background
				color = dock_space.tab_active_color
			} else if tab.hovered {
				background = dock_space.tab_hover_background
			}
			if tab.drop_target {
				background = dock_space.drop_background
			}
			if background.w > 0 {
				if err := append_paint(
					state,
					{
						kind = .Panel,
						rect = tab.rect,
						color = background,
						corner_radius = dock_space.tab_corner_radius,
					},
				); err != "" {
					return err
				}
				if tab.active && dock_space.tab_connection_height > 0 {
					connection_height := min(dock_space.tab_connection_height, tab.rect.height)
					if err := append_paint(
						state,
						{
							kind = .Panel,
							rect = {
								tab.rect.x,
								tab.rect.y + tab.rect.height - connection_height,
								tab.rect.width,
								connection_height + dock_space.tab_content_overlap,
							},
							color = background,
						},
					); err != "" {
						return err
					}
				}
			}
			if err := append_centered_text(
				state,
				title,
				color,
				dock_space.tab_size,
				tab.rect,
				{},
				.Center,
			); err != "" {
				return err
			}
		}
	}
	stack_drag := state.stack_drags[0]
	if node.origin == .Editor {
		stack_drag = state.stack_drags[1]
	}
	indicator_stack := stack_drag.target_stack
	indicator_target := stack_drag.target
	indicator_placement := stack_drag.placement
	indicator_dragging := stack_drag.dragging
	if state.dock_dragging && state.dock_drop_stack_node >= 0 {
		indicator_stack = state.nodes[state.dock_drop_stack_node].entity
		indicator_target = state.dock_drop_stack_target
		indicator_placement = state.dock_drop_stack_placement
		indicator_dragging = true
	}
	if indicator_dragging && indicator_stack != (shared.Entity{}) {
		target_stack_node := find_node(state, indicator_stack)
		if target_stack_node >= 0 {
			target_stack, horizontal, ok := stack_component_for_node(
				world,
				state.nodes[target_stack_node],
			)
			draw_indicator :=
				indicator_target == node.entity ||
				indicator_target == (shared.Entity{}) && indicator_stack == node.entity
			if ok &&
			   draw_indicator &&
			   target_stack.drop_indicator_color.w > 0 &&
			   target_stack.drop_indicator_thickness > 0 {
				indicator_rect := node.rect
				if indicator_target == (shared.Entity{}) {
					indicator_rect = state.nodes[target_stack_node].rect
				}
				start := state.paint_count
				line_start, line_end: shared.Vec2
				if horizontal {
					x := indicator_rect.x
					if indicator_placement == .After {
						x += indicator_rect.width
					}
					inset := min(target_stack.drop_indicator_inset, indicator_rect.height * 0.5)
					line_start = {x, indicator_rect.y + inset}
					line_end = {x, indicator_rect.y + indicator_rect.height - inset}
				} else {
					y := indicator_rect.y
					if indicator_placement == .After {
						y += indicator_rect.height
					}
					inset := min(target_stack.drop_indicator_inset, indicator_rect.width * 0.5)
					line_start = {indicator_rect.x + inset, y}
					line_end = {indicator_rect.x + indicator_rect.width - inset, y}
				}
				if err := append_paint(
					state,
					{
						kind = .Line,
						color = target_stack.drop_indicator_color,
						line_start = line_start,
						line_end = line_end,
						line_thickness = target_stack.drop_indicator_thickness,
					},
				); err != "" {
					return err
				}
				apply_paint_clip(state, start, state.paint_count, node.clip, node.has_clip)
			}
		}
	}
	if node.parent_entity_index >= 0 && node.parent_entity_index < len(world.entities) {
		parent := world.entities[node.parent_entity_index]
		if parent.ui_list_index >= 0 &&
		   parent.ui_list_index < len(world.ui_lists) &&
		   parent.ui_state_index >= 0 &&
		   parent.ui_state_index < len(world.ui_states) {
			list := world.ui_lists[parent.ui_list_index]
			interaction := world.ui_states[parent.ui_state_index]
			entity_index := int(node.entity.index)
			if interaction.dragging &&
			   entity_index >= 0 &&
			   entity_index < len(world.entities) &&
			   interaction.drop_target == world.entities[entity_index].uuid &&
			   (interaction.drop_placement == .Before || interaction.drop_placement == .After) &&
			   list.drop_indicator_color.w > 0 &&
			   list.drop_indicator_thickness > 0 {
				start := state.paint_count
				x0 := node.rect.x + min(list.drop_indicator_inset, node.rect.width * 0.5)
				x1 :=
					node.rect.x +
					node.rect.width -
					min(list.drop_indicator_inset, node.rect.width * 0.5)
				y := node.rect.y
				if interaction.drop_placement == .After {
					y += node.rect.height
				}
				if err := append_paint(
					state,
					{
						kind = .Line,
						color = list.drop_indicator_color,
						line_start = {x0, y},
						line_end = {x1, y},
						line_thickness = list.drop_indicator_thickness,
					},
				); err != "" {
					return err
				}
				apply_paint_clip(state, start, state.paint_count, node.clip, node.has_clip)
			}
		}
	}
	if node.scroll_area_index >= 0 &&
	   node.scroll_area_index < len(world.ui_scroll_areas) &&
	   node.scroll_max > 0 {
		scroll_area := world.ui_scroll_areas[node.scroll_area_index]
		track := Rect {
			node.rect.x +
			node.rect.width -
			scroll_area.scrollbar_right -
			scroll_area.scrollbar_width,
			node.rect.y + scroll_area.scrollbar_vertical_inset,
			scroll_area.scrollbar_width,
			max(node.rect.height - scroll_area.scrollbar_vertical_inset * 2, 0),
		}
		thumb_height := max(
			track.height * track.height / max(node.scroll_content_height, track.height),
			scroll_area.minimum_thumb_size,
		)
		thumb_y :=
			track.y + (track.height - thumb_height) * node.scroll_offset / max(node.scroll_max, 1)
		start := state.paint_count
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = track,
				color = scroll_area.scrollbar_track_color,
				corner_radius = scroll_area.scrollbar_corner_radius,
			},
		); err != "" { return err }
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {track.x, thumb_y, track.width, thumb_height},
				color = scroll_area.scrollbar_thumb_color,
				corner_radius = scroll_area.scrollbar_corner_radius,
			},
		); err != "" { return err }
		apply_paint_clip(state, start, state.paint_count, node.clip, node.has_clip)
	}
	return ""
}

apply_paint_clip :: proc(state: ^State, start, end: int, clip: Rect, has_clip: bool) {
	if !has_clip { return }
	for &command in state.paint[start:end] {
		if command.has_clip {
			command.clip = rect_intersection(command.clip, clip)
		} else {
			command.clip = clip
		}
		command.has_clip = true
	}
}

rect_contains :: proc(rect: Rect, point: shared.Vec2) -> bool {return(
		point.x >= rect.x &&
		point.y >= rect.y &&
		point.x < rect.x + rect.width &&
		point.y < rect.y + rect.height \
	)}

scale_paint_command :: proc(command: ^Paint_Command, scale: f32) {
	command.rect = {
		command.rect.x * scale,
		command.rect.y * scale,
		command.rect.width * scale,
		command.rect.height * scale,
	}
	command.corner_radius *= scale
	command.border_width *= scale
	command.line_start.x *=
		scale; command.line_start.y *= scale; command.line_end.x *= scale; command.line_end.y *= scale; command.line_thickness *= scale
	for &point in command.triangle { point.x *= scale; point.y *= scale }
	command.ring_center.x *=
		scale; command.ring_center.y *= scale; command.ring_axis_x.x *= scale; command.ring_axis_x.y *= scale; command.ring_axis_y.x *= scale; command.ring_axis_y.y *= scale; command.ring_thickness *= scale
	if command.has_clip { command.clip = {command.clip.x * scale, command.clip.y * scale, command.clip.width * scale, command.clip.height * scale} }
}

rebuild_editor_world_overlay :: proc(state: ^State) -> string {
	if state == nil {
		return ""
	}
	state.editor_overlay_compare_count = state.editor_overlay_paint_count
	state.editor_overlay_rebuild_changed = false
	state.editor_overlay_paint_count = 0
	state.paint_editor_overlay = true
	defer state.paint_editor_overlay = false
	select_font(state, "")
	if err := append_editor_camera_mesh(state); err != "" {
		return err
	}
	if err := append_editor_scene_icons(state); err != "" {
		return err
	}
	if err := append_editor_light_gizmo(state); err != "" {
		return err
	}
	if err := append_editor_gizmo(state); err != "" {
		return err
	}
	if err := append_editor_model_placement_preview(state); err != "" {
		return err
	}
	if err := append_editor_box_selection(state); err != "" {
		return err
	}
	if state.editor_overlay_rebuild_changed ||
	   state.editor_overlay_compare_count != state.editor_overlay_paint_count {
		state.editor_overlay_paint_output_revision += 1
		if state.editor_overlay_paint_output_revision == 0 {
			state.editor_overlay_paint_output_revision = 1
		}
	}
	return ""
}

append_editor_box_selection :: proc(state: ^State) -> string {
	if state == nil || !state.editor_box_select_active {
		return ""
	}
	scale := max(state.editor_pixel_density, 1)
	x0 := min(state.editor_box_select_start.x, state.editor_box_select_current.x) * scale
	y0 := min(state.editor_box_select_start.y, state.editor_box_select_current.y) * scale
	x1 := max(state.editor_box_select_start.x, state.editor_box_select_current.x) * scale
	y1 := max(state.editor_box_select_start.y, state.editor_box_select_current.y) * scale
	clip := Rect {
		state.editor_box_select_clip.x * scale,
		state.editor_box_select_clip.y * scale,
		state.editor_box_select_clip.width * scale,
		state.editor_box_select_clip.height * scale,
	}
	return append_paint(
		state,
		Paint_Command {
			kind = .Panel,
			rect = {x0, y0, x1 - x0, y1 - y0},
			color = {0.15, 0.52, 0.68, 0.12},
			border_color = {0.38, 0.78, 0.92, 0.9},
			border_width = max(scale, 1),
			corner_radius = 1 * scale,
			clip = clip,
			has_clip = true,
		},
	)
}

append_editor_model_placement_preview :: proc(state: ^State) -> string {
	if state == nil || !state.editor_model_placement_preview_visible {
		return ""
	}
	scale := max(state.editor_pixel_density, 1)
	contact := state.editor_model_placement_preview_contact
	origin := state.editor_model_placement_preview_origin
	color := shared.Vec4{1, 0.68, 0.22, 0.96}
	soft := color
	soft.w = 0.52
	clip := state.editor_model_placement_preview_clip
	commands := [5]Paint_Command {
		{
			kind = .Ring,
			color = color,
			ring_center = contact,
			ring_axis_x = {11 * scale, 0},
			ring_axis_y = {0, 11 * scale},
			ring_thickness = 2 * scale,
			has_clip = true,
			clip = clip,
		},
		{
			kind = .Line,
			color = color,
			line_start = {contact.x - 16 * scale, contact.y},
			line_end = {contact.x - 6 * scale, contact.y},
			line_thickness = 2 * scale,
			has_clip = true,
			clip = clip,
		},
		{
			kind = .Line,
			color = color,
			line_start = {contact.x + 6 * scale, contact.y},
			line_end = {contact.x + 16 * scale, contact.y},
			line_thickness = 2 * scale,
			has_clip = true,
			clip = clip,
		},
		{
			kind = .Line,
			color = color,
			line_start = {contact.x, contact.y - 16 * scale},
			line_end = {contact.x, contact.y + 16 * scale},
			line_thickness = 2 * scale,
			has_clip = true,
			clip = clip,
		},
		{
			kind = .Line,
			color = soft,
			line_start = contact,
			line_end = origin,
			line_thickness = 1.5 * scale,
			has_clip = true,
			clip = clip,
		},
	}
	for command, index in commands {
		if index == len(commands) - 1 {
			delta := shared.Vec2{origin.x - contact.x, origin.y - contact.y}
			if delta.x * delta.x + delta.y * delta.y < 16 * scale * scale {
				continue
			}
		}
		if err := append_paint(state, command); err != "" {
			return err
		}
	}
	return ""
}

append_editor_camera_mesh :: proc(state: ^State) -> string {
	if state == nil || state.editor_camera_mesh_segment_count <= 0 {
		return ""
	}
	count := min(state.editor_camera_mesh_segment_count, len(state.editor_camera_mesh_segments))
	for segment in state.editor_camera_mesh_segments[:count] {
		if err := append_paint(
			state,
			{
				kind = .Line,
				color = segment.color,
				line_start = segment.start,
				line_end = segment.end,
				line_thickness = segment.thickness,
				corner_radius = segment.thickness * 0.5,
			},
		); err != "" {
			return err
		}
	}
	return ""
}

append_editor_scene_icons :: proc(state: ^State) -> string {
	if state == nil || state.editor_scene_icon_count <= 0 {
		return ""
	}
	scale := max(state.editor_pixel_density, 1)
	count := min(state.editor_scene_icon_count, len(state.editor_scene_icons))
	for icon in state.editor_scene_icons[:count] {
		color := shared.Vec4{0.38, 0.72, 0.96, 1}
		switch icon.kind {
			case .Camera:
			case .Directional_Light:
				color = {1, 0.78, 0.28, 1}
			case .Point_Light:
				color = {1, 0.58, 0.22, 1}
		}
		if icon.selected {
			color = {1, 0.68, 0.22, 1}
		}
		center := icon.center
		size := f32(32) * scale
		line_width := f32(1.75) * scale
		if icon.selected {
			line_width = 2.25 * scale
		}
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {center.x - size * 0.5, center.y - size * 0.5, size, size},
				color = {0.035, 0.04, 0.05, 0.82},
				corner_radius = 7 * scale,
				border_color = color,
				border_width = (1.25 if icon.selected else 0.75) * scale,
				has_clip = true,
				clip = icon.clip,
			},
		); err != "" {
			return err
		}
		switch icon.kind {
			case .Camera:
				if err := append_editor_camera_icon(
					state,
					center,
					color,
					line_width,
					scale,
					icon.clip,
				); err != "" {
					return err
				}
			case .Directional_Light:
				if err := append_editor_directional_light_icon(
					state,
					center,
					color,
					line_width,
					scale,
					icon.clip,
				); err != "" {
					return err
				}
			case .Point_Light:
				if err := append_editor_point_light_icon(
					state,
					center,
					color,
					line_width,
					scale,
					icon.clip,
				); err != "" {
					return err
				}
		}
	}
	return ""
}

append_editor_light_gizmo :: proc(state: ^State) -> string {
	if state == nil || !state.editor_light_gizmo_visible {
		return ""
	}
	scale := max(state.editor_pixel_density, 1)
	color := shared.Vec4{1, 0.68, 0.22, 0.72}
	line_width := f32(1.4) * scale
	count := min(state.editor_light_gizmo_segment_count, len(state.editor_light_gizmo_segments))
	for segment in state.editor_light_gizmo_segments[:count] {
		if err := append_paint(
			state,
			{
				kind = .Line,
				color = color,
				line_start = segment.start,
				line_end = segment.end,
				line_thickness = line_width,
				has_clip = true,
				clip = state.editor_light_gizmo_clip,
			},
		); err != "" {
			return err
		}
	}
	if state.editor_light_gizmo_kind == .Directional_Direction {
		delta := shared.Vec2 {
			state.editor_light_gizmo_handle.x - state.editor_light_gizmo_origin.x,
			state.editor_light_gizmo_handle.y - state.editor_light_gizmo_origin.y,
		}
		length := math.sqrt(delta.x * delta.x + delta.y * delta.y)
		if length > 0.001 {
			direction := shared.Vec2{delta.x / length, delta.y / length}
			perpendicular := shared.Vec2{-direction.y, direction.x}
			back := shared.Vec2 {
				state.editor_light_gizmo_handle.x - direction.x * 12 * scale,
				state.editor_light_gizmo_handle.y - direction.y * 12 * scale,
			}
			signs := [2]f32{-1, 1}
			for sign in signs {
				if err := append_paint(
					state,
					{
						kind = .Line,
						color = color,
						line_start = state.editor_light_gizmo_handle,
						line_end = {
							back.x + perpendicular.x * sign * 6 * scale,
							back.y + perpendicular.y * sign * 6 * scale,
						},
						line_thickness = line_width,
						has_clip = true,
						clip = state.editor_light_gizmo_clip,
					},
				); err != "" {
					return err
				}
			}
		}
	}
	handle_color := shared.Vec4{1, 0.68, 0.22, 0.95}
	handle_radius := f32(5) * scale
	if state.editor_light_gizmo_hovered || state.editor_light_gizmo_active {
		handle_color = {1, 0.86, 0.48, 1}
		handle_radius = 7 * scale
	}
	return append_paint(
		state,
		{
			kind = .Ring,
			color = handle_color,
			ring_center = state.editor_light_gizmo_handle,
			ring_axis_x = {handle_radius, 0},
			ring_axis_y = {0, handle_radius},
			ring_thickness = 2 * scale,
			has_clip = true,
			clip = state.editor_light_gizmo_clip,
		},
	)
}

append_editor_icon_line :: proc(
	state: ^State,
	center, start, end: shared.Vec2,
	color: shared.Vec4,
	thickness, scale: f32,
	clip: Rect,
) -> string {
	return append_paint(
		state,
		{
			kind = .Line,
			color = color,
			line_start = {center.x + start.x * scale, center.y + start.y * scale},
			line_end = {center.x + end.x * scale, center.y + end.y * scale},
			line_thickness = thickness,
			corner_radius = thickness * 0.5,
			has_clip = true,
			clip = clip,
		},
	)
}

append_editor_camera_icon :: proc(
	state: ^State,
	center: shared.Vec2,
	color: shared.Vec4,
	thickness, scale: f32,
	clip: Rect,
) -> string {
	lines := [7][2]shared.Vec2 {
		{{-9, -6}, {4, -6}},
		{{4, -6}, {4, 6}},
		{{4, 6}, {-9, 6}},
		{{-9, 6}, {-9, -6}},
		{{4, -3.5}, {10, -7}},
		{{10, -7}, {10, 7}},
		{{10, 7}, {4, 3.5}},
	}
	for line in lines {
		if err := append_editor_icon_line(
			state,
			center,
			line[0],
			line[1],
			color,
			thickness,
			scale,
			clip,
		); err != "" {
			return err
		}
	}
	return ""
}

append_editor_directional_light_icon :: proc(
	state: ^State,
	center: shared.Vec2,
	color: shared.Vec4,
	thickness, scale: f32,
	clip: Rect,
) -> string {
	if err := append_paint(
		state,
		{
			kind = .Ring,
			color = color,
			ring_center = center,
			ring_axis_x = {5 * scale, 0},
			ring_axis_y = {0, 5 * scale},
			ring_thickness = thickness,
			has_clip = true,
			clip = clip,
		},
	); err != "" {
		return err
	}
	rays := [8][2]shared.Vec2 {
		{{0, -8}, {0, -11}},
		{{0, 8}, {0, 11}},
		{{-8, 0}, {-11, 0}},
		{{8, 0}, {11, 0}},
		{{-5.7, -5.7}, {-7.8, -7.8}},
		{{5.7, -5.7}, {7.8, -7.8}},
		{{-5.7, 5.7}, {-7.8, 7.8}},
		{{5.7, 5.7}, {7.8, 7.8}},
	}
	for ray in rays {
		if err := append_editor_icon_line(
			state,
			center,
			ray[0],
			ray[1],
			color,
			thickness,
			scale,
			clip,
		); err != "" {
			return err
		}
	}
	return ""
}

append_editor_point_light_icon :: proc(
	state: ^State,
	center: shared.Vec2,
	color: shared.Vec4,
	thickness, scale: f32,
	clip: Rect,
) -> string {
	bulb_center := shared.Vec2{center.x, center.y - 3 * scale}
	if err := append_paint(
		state,
		{
			kind = .Ring,
			color = color,
			ring_center = bulb_center,
			ring_axis_x = {6 * scale, 0},
			ring_axis_y = {0, 6 * scale},
			ring_thickness = thickness,
			has_clip = true,
			clip = clip,
		},
	); err != "" {
		return err
	}
	lines := [4][2]shared.Vec2 {
		{{-4, 2}, {-3, 6}},
		{{4, 2}, {3, 6}},
		{{-3, 6}, {3, 6}},
		{{-2, 9}, {2, 9}},
	}
	for line in lines {
		if err := append_editor_icon_line(
			state,
			center,
			line[0],
			line[1],
			color,
			thickness,
			scale,
			clip,
		); err != "" {
			return err
		}
	}
	return ""
}

append_editor_gizmo :: proc(state: ^State) -> string {
	if !state.editor_gizmo_visible { return "" }
	scale := max(state.editor_pixel_density, 1)
	colors := [3]shared.Vec4{{0.95, 0.20, 0.24, 1}, {0.28, 0.88, 0.42, 1}, {0.24, 0.48, 1, 1}}
	labels := [3]string{"X", "Y", "Z"}
	if state.editor_gizmo_mode == .Rotate {
		if state.editor_gizmo_captures_pointer && state.editor_gizmo_active_handle != .None {
			guide_color := editor_gizmo_guide_color(state.editor_gizmo_active_handle, colors)
			if err := append_paint(
				state,
				{
					kind = .Line,
					color = guide_color,
					line_start = state.editor_gizmo_origin,
					line_end = state.editor_gizmo_drag_last_pointer,
					line_thickness = 1.25 * scale,
					corner_radius = 0.625 * scale,
				},
			); err != "" {
				return err
			}
		}
		for ring, index in state.editor_gizmo_ring_points {
			axis := Editor_Gizmo_Handle(
				index + 1,
			); active := state.editor_gizmo_hovered_handle == axis || state.editor_gizmo_active_handle == axis
			color :=
				colors[index]; if state.editor_gizmo_active_handle != .None && state.editor_gizmo_active_handle != axis { color.w = 0.30 }
			if active { color.x = min(color.x + 0.20, 1); color.y = min(color.y + 0.20, 1); color.z = min(color.z + 0.20, 1) }
			thickness := f32(1.35) * scale; if active { thickness = 2.75 * scale }
			p0, p1, p2, p3 :=
				ring[0], ring[len(ring) / 4], ring[len(ring) / 2], ring[len(ring) * 3 / 4]
			center := shared.Vec2 {
				(p0.x + p1.x + p2.x + p3.x) * 0.25,
				(p0.y + p1.y + p2.y + p3.y) * 0.25,
			}
			axis_x := shared.Vec2 {
				(p0.x - p2.x) * 0.5,
				(p0.y - p2.y) * 0.5,
			}; axis_y := shared.Vec2{(p1.x - p3.x) * 0.5, (p1.y - p3.y) * 0.5}
			length_x := math.sqrt(
				axis_x.x * axis_x.x + axis_x.y * axis_x.y,
			); length_y := math.sqrt(axis_y.x * axis_y.x + axis_y.y * axis_y.y)
			major, minor := axis_x, length_y
			major_length := length_x
			if length_y > length_x { major = axis_y; major_length = length_y; minor = length_x }
			projected_minor :=
				math.abs(axis_x.x * axis_y.y - axis_x.y * axis_y.x) / max(major_length, f32(0.001))
			if min(minor, projected_minor) < max(f32(1.5) * scale, major_length * 0.025) {
				if err := append_paint(
					state,
					{
						kind = .Line,
						color = color,
						line_start = {center.x - major.x, center.y - major.y},
						line_end = {center.x + major.x, center.y + major.y},
						line_thickness = thickness,
						corner_radius = thickness * 0.5,
					},
				); err != "" { return err }
			} else if err := append_paint(
				state,
				{
					kind = .Ring,
					color = color,
					ring_center = center,
					ring_axis_x = axis_x,
					ring_axis_y = axis_y,
					ring_thickness = thickness,
				},
			); err != "" { return err }
		}
		if err := append_gizmo_center(state, state.editor_gizmo_origin, scale);
		   err != "" { return err }
		return ""
	}
	plane_handles := [3]Editor_Gizmo_Handle{.XY, .XZ, .YZ}
	plane_colors := [3]shared.Vec4 {
		{0.82, 0.84, 0.18, 0.28},
		{0.82, 0.28, 0.68, 0.28},
		{0.18, 0.76, 0.78, 0.28},
	}
	if state.editor_gizmo_captures_pointer && state.editor_gizmo_active_handle != .None {
		guide_color := editor_gizmo_guide_color(state.editor_gizmo_active_handle, colors)
		guide_start := state.editor_gizmo_drag_visual_origin
		guide_end := state.editor_gizmo_origin
		if state.editor_gizmo_mode == .Scale {
			guide_end = state.editor_gizmo_drag_virtual_pointer
		}
		if err := append_paint(
			state,
			{
				kind = .Line,
				color = guide_color,
				line_start = guide_start,
				line_end = guide_end,
				line_thickness = 1.25 * scale,
				corner_radius = 0.625 * scale,
			},
		); err != "" {
			return err
		}
		if state.editor_gizmo_mode == .Scale {
			marker_color := guide_color
			marker_color.w *= 0.72
			if err := append_paint(
				state,
				{
					kind = .Ring,
					color = marker_color,
					ring_center = state.editor_gizmo_drag_visual_start_pointer,
					ring_axis_x = {3.5 * scale, 0},
					ring_axis_y = {0, 3.5 * scale},
					ring_thickness = 1.1 * scale,
				},
			); err != "" {
				return err
			}
		}
	}
	for plane, index in state.editor_gizmo_plane_points {
		handle :=
			plane_handles[index]; active := state.editor_gizmo_hovered_handle == handle || state.editor_gizmo_active_handle == handle
		color := plane_colors[index]
		if state.editor_gizmo_active_handle != .None &&
		   state.editor_gizmo_active_handle != handle { color.w = 0.10 }
		if active { color.w = 0.64; color.x = min(color.x + 0.12, 1); color.y = min(color.y + 0.12, 1); color.z = min(color.z + 0.12, 1) }
		if err := append_paint(
			state,
			{kind = .Triangle, color = color, triangle = {plane[0], plane[1], plane[2]}},
		); err != "" { return err }
		if err := append_paint(
			state,
			{kind = .Triangle, color = color, triangle = {plane[0], plane[2], plane[3]}},
		); err != "" { return err }
	}
	for endpoint, index in state.editor_gizmo_endpoints {
		axis := Editor_Gizmo_Handle(
			index + 1,
		); active := editor_gizmo_handle_contains_axis(state.editor_gizmo_hovered_handle, axis) || editor_gizmo_handle_contains_axis(state.editor_gizmo_active_handle, axis)
		color :=
			colors[index]; if state.editor_gizmo_active_handle != .None && !editor_gizmo_handle_contains_axis(state.editor_gizmo_active_handle, axis) { color.w = 0.30 }
		if active { color.x = min(color.x + 0.20, 1); color.y = min(color.y + 0.20, 1); color.z = min(color.z + 0.20, 1) }
		delta := shared.Vec2 {
			endpoint.x - state.editor_gizmo_origin.x,
			endpoint.y - state.editor_gizmo_origin.y,
		}; length := math.sqrt(delta.x * delta.x + delta.y * delta.y)
		if length <= 0.001 { continue }
		direction := shared.Vec2 {
			delta.x / length,
			delta.y / length,
		}; perpendicular := shared.Vec2{-direction.y, direction.x}
		thickness := f32(3) * scale; if active { thickness = 5 * scale }
		terminal_back :=
			f32(13) * scale; if state.editor_gizmo_mode == .Scale { terminal_back = 6 * scale }
		shaft_end := shared.Vec2 {
			endpoint.x - direction.x * terminal_back,
			endpoint.y - direction.y * terminal_back,
		}
		if err := append_paint(
			state,
			{
				kind = .Line,
				color = color,
				line_start = state.editor_gizmo_origin,
				line_end = shaft_end,
				line_thickness = thickness,
				corner_radius = thickness * 0.5,
			},
		); err != "" { return err }
		if state.editor_gizmo_mode == .Translate {
			triangle := [3]shared.Vec2 {
				endpoint,
				{
					endpoint.x - direction.x * 15 * scale + perpendicular.x * 7 * scale,
					endpoint.y - direction.y * 15 * scale + perpendicular.y * 7 * scale,
				},
				{
					endpoint.x - direction.x * 15 * scale - perpendicular.x * 7 * scale,
					endpoint.y - direction.y * 15 * scale - perpendicular.y * 7 * scale,
				},
			}
			if err := append_paint(state, {kind = .Triangle, color = color, triangle = triangle});
			   err != "" { return err }
		} else {
			if err := append_paint(
				state,
				{
					kind = .Panel,
					rect = {
						endpoint.x - 6 * scale,
						endpoint.y - 6 * scale,
						12 * scale,
						12 * scale,
					},
					color = color,
					corner_radius = 1.5 * scale,
				},
			); err != "" { return err }
		}
		label_center := shared.Vec2 {
			endpoint.x + direction.x * 12 * scale,
			endpoint.y + direction.y * 12 * scale,
		}
		if err := append_centered_text(
			state,
			labels[index],
			color,
			EDITOR_TEXT_SIZE * scale,
			{label_center.x - 9 * scale, label_center.y - 9 * scale, 18 * scale, 18 * scale},
			{},
		); err != "" { return err }
	}
	center_active :=
		state.editor_gizmo_hovered_handle == .Center || state.editor_gizmo_active_handle == .Center
	center_size := f32(11) * scale; if center_active { center_size = 15 * scale }
	center_color := shared.Vec4 {
		0.82,
		0.86,
		0.92,
		0.84,
	}; if center_active { center_color = {1, 1, 1, 1} } else if state.editor_gizmo_active_handle != .None { center_color.w = 0.30 }
	if err := append_paint(
		state,
		{
			kind = .Panel,
			rect = {
				state.editor_gizmo_origin.x - center_size * 0.5,
				state.editor_gizmo_origin.y - center_size * 0.5,
				center_size,
				center_size,
			},
			color = center_color,
			corner_radius = 2 * scale,
		},
	); err != "" { return err }
	return ""
}

editor_gizmo_guide_color :: proc(
	handle: Editor_Gizmo_Handle,
	axis_colors: [3]shared.Vec4,
) -> shared.Vec4 {
	color := shared.Vec4{0.92, 0.94, 0.98, 0.72}
	switch handle {
		case .X:
			color = axis_colors[0]
		case .Y:
			color = axis_colors[1]
		case .Z:
			color = axis_colors[2]
		case .XY:
			color = {0.82, 0.84, 0.18, 0.72}
		case .XZ:
			color = {0.82, 0.28, 0.68, 0.72}
		case .YZ:
			color = {0.18, 0.76, 0.78, 0.72}
		case .None, .Center:
	}
	color.w = 0.72
	return color
}

editor_gizmo_handle_contains_axis :: proc(handle, axis: Editor_Gizmo_Handle) -> bool {
	if handle == axis || handle == .Center { return true }
	switch handle {case .XY:
			return axis == .X || axis == .Y; case .XZ:
			return axis == .X || axis == .Z; case .YZ:
			return axis == .Y || axis == .Z; case .None, .X, .Y, .Z, .Center:
			return false}
	return false
}

append_gizmo_center :: proc(state: ^State, origin: shared.Vec2, scale: f32) -> string {
	return append_paint(
		state,
		{
			kind = .Panel,
			rect = {origin.x - 2.5 * scale, origin.y - 2.5 * scale, 5 * scale, 5 * scale},
			color = {0.88, 0.92, 0.98, 0.92},
			corner_radius = 2.5 * scale,
		},
	)
}

append_button_content :: proc(
	state: ^State,
	button: shared.UI_Button_Component,
	color: shared.Vec4,
	rect: Rect,
	padding: shared.Vec4,
) -> string {
	has_icon := button.icon_set != (shared.Resource_UUID{}) && button.icon != ""
	if !has_icon {
		return append_centered_text(
			state,
			button.text,
			color,
			button.size,
			rect,
			padding,
			button.alignment,
		)
	}
	content := Rect {
		rect.x + padding.w,
		rect.y + padding.x,
		max(rect.width - padding.w - padding.y, 0),
		max(rect.height - padding.x - padding.z, 0),
	}
	icon_size := button.icon_size
	if icon_size <= 0 {
		icon_size = min(button.size * 1.25, min(content.width, content.height))
	}
	icon_size = min(icon_size, min(content.width, content.height))
	icon_rect := Rect {
		content.x + (content.width - icon_size) * 0.5,
		content.y + (content.height - icon_size) * 0.5,
		icon_size,
		icon_size,
	}
	if button.text == "" {
		return append_icon(
			state,
			{
				icon_set = button.icon_set,
				icon = button.icon,
				color = color,
				inset = button.icon_inset,
			},
			icon_rect,
			{},
		)
	}
	text_bounds, has_text_ink := measure_text_ink(state, button.text, button.size)
	text_width := text_bounds.width
	if !has_text_ink {
		text_width = 0
	}
	total_width := min(icon_size + button.icon_gap + text_width, content.width)
	group_x := content.x
	switch button.alignment {
		case .Center:
			group_x += (content.width - total_width) * 0.5
		case .Right:
			group_x += content.width - total_width
		case .Left:
	}
	text_rect := Rect {
		group_x,
		content.y,
		max(total_width - icon_size - button.icon_gap, 0),
		content.height,
	}
	if button.icon_position == .Leading {
		icon_rect.x = group_x
		text_rect.x = group_x + icon_size + button.icon_gap
	} else {
		text_rect.x = group_x
		icon_rect.x = group_x + text_rect.width + button.icon_gap
	}
	if err := append_icon(
		state,
		{icon_set = button.icon_set, icon = button.icon, color = color, inset = button.icon_inset},
		icon_rect,
		{},
	); err != "" { return err }
	return append_centered_text(state, button.text, color, button.size, text_rect, {}, .Center)
}

append_icon :: proc(
	state: ^State,
	value: shared.UI_Icon_Component,
	rect: Rect,
	padding: shared.Vec4,
) -> string {
	if state == nil || state.resource_registry == nil || value.color.w <= 0 {
		return ""
	}
	handle, found := resources.icon_set_handle_by_uuid(state.resource_registry, value.icon_set)
	if !found || handle.index >= shared.MAX_ICON_SETS {
		return ""
	}
	icon_set, alive := resources.get_icon_set(state.resource_registry, handle)
	if !alive {
		return ""
	}
	symbol, symbol_found := resources.icon_symbol(icon_set, value.icon)
	if !symbol_found {
		return ""
	}
	content := Rect {
		rect.x + padding.w + value.inset,
		rect.y + padding.x + value.inset,
		max(rect.width - padding.w - padding.y - value.inset * 2, 0),
		max(rect.height - padding.x - padding.z - value.inset * 2, 0),
	}
	size := min(content.width, content.height)
	if size <= 0 {
		return ""
	}
	plane_width := math.abs(symbol.plane[2] - symbol.plane[0])
	plane_height := math.abs(symbol.plane[1] - symbol.plane[3])
	plane_extent := max(plane_width, plane_height)
	if plane_extent <= 0 {
		return ""
	}
	icon_width := size * plane_width / plane_extent
	icon_height := size * plane_height / plane_extent
	return append_paint(
		state,
		{
			kind = .Icon,
			rect = {
				content.x + (content.width - icon_width) * 0.5,
				content.y + (content.height - icon_height) * 0.5,
				icon_width,
				icon_height,
			},
			color = value.color,
			uv = {symbol.uv[0], symbol.uv[1], symbol.uv[2], symbol.uv[3]},
			font_layer = f32(shared.MAX_PROJECT_FONTS + 1 + int(handle.index)),
		},
	)
}

entity_component_count :: proc(world: ^shared.World, entity_index: int) -> int {
	if entity_index < 0 || entity_index >= len(world.entities) {
		return 0
	}
	entity := world.entities[entity_index]
	count := 0
	indices := [17]int {
		entity.transform_index,
		entity.camera_index,
		entity.ambient_light_index,
		entity.directional_light_index,
		entity.point_light_index,
		entity.mesh_index,
		entity.geometry_index,
		entity.material_index,
		entity.render_instance_index,
		entity.ui_layout_index,
		entity.ui_scroll_area_index,
		entity.ui_panel_index,
		entity.ui_table_index,
		entity.ui_list_index,
		entity.ui_progress_index,
		entity.ui_icon_index,
		entity.ui_text_index,
	}
	for index in indices {
		if index >= 0 { count += 1 }
	}
	if entity.ui_hstack_index >= 0 { count += 1 }
	if entity.ui_vstack_index >= 0 { count += 1 }
	if entity.ui_button_index >= 0 { count += 1 }
	if entity.ui_input_index >= 0 { count += 1 }
	if entity.ui_checkbox_index >= 0 { count += 1 }
	if entity.ui_color_picker_index >= 0 { count += 1 }
	if entity.editor_transform_gizmo_index >= 0 &&
	   entity.editor_transform_gizmo_index < len(world.editor_transform_gizmos) &&
	   world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index ==
		   entity_index { count += 1 }
	for camera in world.editor_scene_cameras { if camera.entity_index == entity_index { count += 1; break } }
	if entity.has_shadow_caster { count += 1 }; if entity.has_shadow_receiver { count += 1 }
	for storage in world.custom_components { for component in storage.components { if component.entity_index == entity_index { count += 1; break } } }
	return count
}

format_vec2 :: proc(value: shared.Vec2) -> string {return fmt.tprintf(
		"(%.2f, %.2f)",
		value.x,
		value.y,
	)}
format_vec3 :: proc(value: shared.Vec3) -> string {return fmt.tprintf(
		"(%.2f, %.2f, %.2f)",
		value.x,
		value.y,
		value.z,
	)}
format_vec4 :: proc(value: shared.Vec4) -> string {return fmt.tprintf(
		"(%.2f, %.2f, %.2f, %.2f)",
		value.x,
		value.y,
		value.z,
		value.w,
	)}
format_handle :: proc(index, generation: u32) -> string {return fmt.tprintf(
		"#%d:%d",
		index,
		generation,
	)}

append_text :: proc(
	state: ^State,
	text: string,
	color: shared.Vec4,
	size: f32,
	rect: Rect,
	padding: shared.Vec4,
	alignment: shared.UI_Text_Alignment = .Left,
	wrap := false,
	authored_line_height := f32(0),
) -> string {
	content_x := rect.x + padding.w
	content_width := max(rect.width - padding.w - padding.y, 0)
	baseline := rect.y + padding.x + state.font.ascender * size
	line_height := size
	if authored_line_height > 0 {
		line_height = authored_line_height
	}
	lines: [MAX_TEXT_LINES]Text_Line
	line_count := text_layout_lines(state, text, size, content_width, wrap, &lines)
	for line in lines[:line_count] {
		if err := append_aligned_text_line(
			state,
			text[line.start:line.end],
			color,
			size,
			content_x,
			content_width,
			baseline,
			alignment,
		); err != "" {
			return err
		}
		baseline += line_height
	}
	return ""
}

append_aligned_text_line :: proc(
	state: ^State,
	text: string,
	color: shared.Vec4,
	size, content_x, content_width, baseline: f32,
	alignment: shared.UI_Text_Alignment,
) -> string {
	advance := text_advance_to(state, text, size, len(text))
	x := content_x
	switch alignment {
		case .Left:
		case .Center:
			x += max((content_width - advance) * 0.5, 0)
		case .Right:
			x += max(content_width - advance, 0)
	}
	return append_text_at(state, text, color, size, x, baseline, x)
}

text_advance_to :: proc(state: ^State, text: string, size: f32, byte_index: int) -> f32 {
	x := f32(0)
	limit := clamp(byte_index, 0, len(text))
	for byte, index in transmute([]u8)text {
		if index >= limit { break }
		code := int(byte)
		if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT {
			code = int('?')
		}
		x += state.font.glyphs^[code - FONT_FIRST_CHAR].advance * size
	}
	return x
}

text_layout_lines :: proc(
	state: ^State,
	text: string,
	size, max_width: f32,
	wrap: bool,
	lines: ^[MAX_TEXT_LINES]Text_Line,
) -> int {
	if lines == nil {
		return 0
	}
	count := 0
	paragraph_start := 0
	for paragraph_end := 0; paragraph_end <= len(text); paragraph_end += 1 {
		if paragraph_end < len(text) && text[paragraph_end] != '\n' {
			continue
		}
		if !wrap || max_width <= 0 {
			if count < MAX_TEXT_LINES {
				lines[count] = {
					start = paragraph_start,
					end = paragraph_end,
					advance = text_advance_to(
						state,
						text[paragraph_start:paragraph_end],
						size,
						paragraph_end - paragraph_start,
					),
				}
				count += 1
			}
		} else if paragraph_start == paragraph_end {
			if count < MAX_TEXT_LINES {
				lines[count] = {
					start = paragraph_start,
					end = paragraph_end,
				}
				count += 1
			}
		} else {
			line_start := paragraph_start
			for line_start < paragraph_end && count < MAX_TEXT_LINES {
				for line_start < paragraph_end &&
				    (text[line_start] == ' ' || text[line_start] == '\t') {
					line_start += 1
				}
				if line_start >= paragraph_end {
					break
				}
				line_end := line_start
				last_break := -1
				advance := f32(0)
				advance_at_break := f32(0)
				for cursor := line_start; cursor < paragraph_end; cursor += 1 {
					code := int(text[cursor])
					if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT {
						code = int('?')
					}
					next_advance :=
						advance + state.font.glyphs^[code - FONT_FIRST_CHAR].advance * size
					if next_advance > max_width && cursor > line_start {
						break
					}
					advance = next_advance
					line_end = cursor + 1
					if text[cursor] == ' ' || text[cursor] == '\t' {
						last_break = cursor
						advance_at_break =
							advance - state.font.glyphs^[code - FONT_FIRST_CHAR].advance * size
					}
					if next_advance > max_width {
						break
					}
				}
				if line_end < paragraph_end && last_break >= line_start {
					line_end = last_break
					advance = advance_at_break
				}
				if line_end <= line_start {
					line_end = min(line_start + 1, paragraph_end)
					advance = text_advance_to(
						state,
						text[line_start:line_end],
						size,
						line_end - line_start,
					)
				}
				trimmed_end := line_end
				for trimmed_end > line_start &&
				    (text[trimmed_end - 1] == ' ' || text[trimmed_end - 1] == '\t') {
					trimmed_end -= 1
				}
				if trimmed_end != line_end {
					advance = text_advance_to(
						state,
						text[line_start:trimmed_end],
						size,
						trimmed_end - line_start,
					)
				}
				lines[count] = {
					start = line_start,
					end = trimmed_end,
					advance = advance,
				}
				count += 1
				line_start = line_end
			}
		}
		paragraph_start = paragraph_end + 1
	}
	if count == 0 {
		lines[0] = {}
		return 1
	}
	return count
}

append_input :: proc(
	state: ^State,
	world: ^shared.World,
	input: shared.UI_Input_Component,
	node: Node,
	padding: shared.Vec4,
) -> string {
	content := Rect {
		node.rect.x + padding.w,
		node.rect.y + padding.x,
		max(node.rect.width - padding.w - padding.y, 0),
		max(node.rect.height - padding.x - padding.z, 0),
	}
	if content.width <= 0 || content.height <= 0 { return "" }
	_ = world
	prefix_content := content
	prefix_width := f32(0)
	if input.prefix != "" && input.prefix_width > 0 {
		prefix_width = min(input.prefix_width, content.width)
		content.x += prefix_width + input.prefix_gap
		content.width = max(content.width - prefix_width - input.prefix_gap, 0)
	}
	has_icon := input.icon_set != (shared.Resource_UUID{}) && input.icon != ""
	icon_rect: Rect
	if has_icon && content.width > 0 {
		icon_size := input.icon_size
		if icon_size <= 0 {
			icon_size = min(input.size * 1.25, min(content.width, content.height))
		}
		icon_size = min(icon_size, min(content.width, content.height))
		icon_gap := min(input.icon_gap, max(content.width - icon_size, 0))
		icon_rect = {
			content.x,
			content.y + (content.height - icon_size) * 0.5,
			icon_size,
			icon_size,
		}
		if input.icon_position == .Leading {
			content.x += icon_size + icon_gap
		} else {
			icon_rect.x = content.x + content.width - icon_size
		}
		content.width = max(content.width - icon_size - icon_gap, 0)
	}
	focused := state.has_focused_input && state.focused_input == node.entity
	cursor := len(input.text)
	anchor := cursor
	scroll_x := f32(0)
	if focused {
		cursor = clamp(state.input_cursor, 0, len(input.text))
		anchor = clamp(state.input_anchor, 0, len(input.text))
		caret_x := text_advance_to(state, input.text, input.size, cursor)
		scroll_x = max(state.input_scroll_x, 0)
		if caret_x - scroll_x > content.width - 2 {
			scroll_x = caret_x - content.width + 2
		}
		if caret_x - scroll_x < 0 { scroll_x = caret_x }
		state.input_scroll_x = max(scroll_x, 0)
	}
	prefix_start := state.paint_count
	if input.prefix != "" && prefix_width > 0 {
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {prefix_content.x, prefix_content.y, prefix_width, prefix_content.height},
				color = input.prefix_background,
				corner_radius = input.prefix_corner_radius,
			},
		); err != "" { return err }
		if err := append_text_at(
			state,
			input.prefix,
			input.prefix_color,
			input.size,
			prefix_content.x + input.prefix_text_padding,
			prefix_content.y +
			max((prefix_content.height - input.size) * 0.5, 0) +
			state.font.ascender * input.size,
			prefix_content.x + input.prefix_text_padding,
		); err != "" { return err }
	}
	prefix_clip := prefix_content
	if node.has_clip { prefix_clip = rect_intersection(prefix_clip, node.clip) }
	apply_paint_clip(state, prefix_start, state.paint_count, prefix_clip, true)
	icon_start := state.paint_count
	if has_icon && icon_rect.width > 0 {
		if err := append_icon(
			state,
			{
				icon_set = input.icon_set,
				icon = input.icon,
				color = input.icon_color,
				inset = input.icon_inset,
			},
			icon_rect,
			{},
		); err != "" { return err }
	}
	icon_clip := icon_rect
	if node.has_clip { icon_clip = rect_intersection(icon_clip, node.clip) }
	apply_paint_clip(state, icon_start, state.paint_count, icon_clip, true)
	clip := content
	if node.has_clip { clip = rect_intersection(clip, node.clip) }
	start := state.paint_count
	selection_start := min(cursor, anchor)
	selection_end := max(cursor, anchor)
	if focused && selection_start != selection_end && input.selection_background.w > 0 {
		x0 :=
			content.x + text_advance_to(state, input.text, input.size, selection_start) - scroll_x
		x1 := content.x + text_advance_to(state, input.text, input.size, selection_end) - scroll_x
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {x0, content.y, max(x1 - x0, 0), content.height},
				color = input.selection_background,
				corner_radius = input.selection_corner_radius,
			},
		); err != "" { return err }
	}
	baseline :=
		content.y + max((content.height - input.size) * 0.5, 0) + state.font.ascender * input.size
	if err := append_text_at(
		state,
		input.text,
		input.color,
		input.size,
		content.x - scroll_x,
		baseline,
		content.x - scroll_x,
	); err != "" { return err }
	if focused && int(state.input_blink_elapsed * 2) % 2 == 0 {
		caret_x := content.x + text_advance_to(state, input.text, input.size, cursor) - scroll_x
		caret_color := input.caret_color
		if caret_color.w <= 0 {
			caret_color = input.color
		}
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {
					caret_x,
					content.y + input.caret_inset,
					input.caret_width,
					max(content.height - input.caret_inset * 2, 0),
				},
				color = caret_color,
			},
		); err != "" { return err }
	}
	apply_paint_clip(state, start, state.paint_count, clip, true)
	return ""
}

append_text_clipped :: proc(
	state: ^State,
	text: string,
	color: shared.Vec4,
	size: f32,
	rect: Rect,
) -> string {
	x := rect.x; baseline := rect.y + state.font.ascender * size
	for character in text {
		code := int(
			character,
		); if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT { code = int('?') }; glyph := state.font.glyphs^[code - FONT_FIRST_CHAR]
		width :=
			(glyph.plane.z - glyph.plane.x) *
			size; height := (glyph.plane.w - glyph.plane.y) * size; glyph_x := x + glyph.plane.x * size
		if glyph_x + width > rect.x + rect.width { return "" }
		if width > 0 &&
		   height >
			   0 { if err := append_paint(state, {kind = .Glyph, rect = {glyph_x, baseline + glyph.plane.y * size, width, height}, color = color, uv = glyph.uv}); err != "" { return err } }
		x += glyph.advance * size
	}
	return ""
}

append_centered_text :: proc(
	state: ^State,
	text: string,
	color: shared.Vec4,
	size: f32,
	rect: Rect,
	padding: shared.Vec4,
	alignment: shared.UI_Text_Alignment = .Center,
) -> string {
	bounds, has_ink := measure_text_ink(state, text, size)
	if !has_ink { return "" }
	content := Rect {
		rect.x + padding.w,
		rect.y + padding.x,
		rect.width - padding.w - padding.y,
		rect.height - padding.x - padding.z,
	}
	x := content.x - bounds.x
	switch alignment {
		case .Left:
		case .Center:
			x += (content.width - bounds.width) * 0.5
		case .Right:
			x += content.width - bounds.width
	}
	baseline := content.y + (content.height - bounds.height) * 0.5 - bounds.y
	return append_text_at(state, text, color, size, x, baseline, x)
}

append_text_at :: proc(
	state: ^State,
	text: string,
	color: shared.Vec4,
	size, x_start, baseline_start, line_start: f32,
) -> string {
	x := x_start; baseline := baseline_start
	for character in text {
		if character == '\n' { x = line_start; baseline += size; continue }
		code := int(
			character,
		); if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT { code = int('?') }
		glyph := state.font.glyphs^[code - FONT_FIRST_CHAR]
		width :=
			(glyph.plane.z - glyph.plane.x) *
			size; height := (glyph.plane.w - glyph.plane.y) * size
		if width > 0 &&
		   height >
			   0 { if err := append_paint(state, {kind = .Glyph, rect = {x + glyph.plane.x * size, baseline + glyph.plane.y * size, width, height}, color = color, uv = glyph.uv}); err != "" { return err } }
		x += glyph.advance * size
	}
	return ""
}

measure_text_ink :: proc(state: ^State, text: string, size: f32) -> (Rect, bool) {
	x := f32(0); min_x, min_y, max_x, max_y := f32(0), f32(0), f32(0), f32(0); has_ink := false
	for character in text {
		if character == '\n' { break }
		code := int(
			character,
		); if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT { code = int('?') }
		glyph := state.font.glyphs^[code - FONT_FIRST_CHAR]
		x0 :=
			x +
			glyph.plane.x *
				size; y0 := glyph.plane.y * size; x1 := x + glyph.plane.z * size; y1 := glyph.plane.w * size
		if x1 > x0 &&
		   y1 >
			   y0 { if !has_ink { min_x = x0; min_y = y0; max_x = x1; max_y = y1; has_ink = true } else { min_x = min(min_x, x0); min_y = min(min_y, y0); max_x = max(max_x, x1); max_y = max(max_y, y1) } }
		x += glyph.advance * size
	}
	return {min_x, min_y, max_x - min_x, max_y - min_y}, has_ink
}

append_paint :: proc(state: ^State, command_value: Paint_Command) -> string {
	if state.paint_editor_overlay {
		if state.editor_overlay_paint_count >= MAX_EDITOR_OVERLAY_PAINT_COMMANDS {
			return "too many editor overlay paint commands"
		}
		command := command_value
		if command.kind == .Glyph {
			command.font_layer = state.font.layer
		}
		if state.editor_overlay_paint_count >= state.editor_overlay_compare_count ||
		   state.editor_overlay_paint[state.editor_overlay_paint_count] != command {
			state.editor_overlay_rebuild_changed = true
		}
		state.editor_overlay_paint[state.editor_overlay_paint_count] = command
		state.editor_overlay_paint_count += 1
		return ""
	}
	if state.paint_count >= MAX_PAINT_COMMANDS { return "too many UI paint commands" }
	command := command_value
	if command.kind == .Glyph { command.font_layer = state.font.layer }
	state.paint[state.paint_count] = command
	state.paint_count += 1
	return ""
}
