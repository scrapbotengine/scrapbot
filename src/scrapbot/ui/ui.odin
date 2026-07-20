package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:strconv"
import "core:strings"

MAX_NODES :: 4096
MAX_PAINT_COMMANDS :: 16384
MAX_EDITOR_OVERLAY_PAINT_COMMANDS :: 1024
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
	primary_down, available: bool,
}
Pointer_Cursor :: enum {
	Default,
	Horizontal_Resize,
	Vertical_Resize,
}
Keyboard_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, shift, fine, enter, escape, select_all, save, undo, redo: bool,
	editor_toggle, run_stop, pause_step: bool,
}
Paint_Kind :: enum {
	Panel,
	Glyph,
	Line,
	Triangle,
	Ring,
	Disclosure,
	Checkmark,
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
	clip: Rect,
	has_clip: bool,
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

Editor_Camera_Mesh_Segment :: struct {
	entity: shared.Entity,
	start, end: shared.Vec2,
	color: shared.Vec4,
	thickness: f32,
}

Font_Atlas :: struct {
	glyphs: ^[FONT_CHAR_COUNT]shared.Font_Glyph,
	ascender: f32,
	layer: f32,
	ready: bool,
}
Split_Handle :: struct {
	rect: Rect,
	before_node, after_node: int,
	min_size: f32,
	horizontal: bool,
	editor: bool,
	hovered, active: bool,
}
Node :: struct {
	entity: shared.Entity,
	origin: shared.Entity_Origin,
	editor_role: shared.Editor_UI_Role,
	layout_index, hstack_index, vstack_index, scroll_area_index, panel_index, table_index, list_index, progress_index, text_index, button_index, input_index, checkbox_index, parent_entity_index: int,
	parent_node_index, first_child_node, next_sibling_node: int,
	rect, clip: Rect,
	resolved_size: shared.Vec2,
	fill_available_size: shared.Vec2,
	paint_order: int,
	scroll_offset, scroll_target, scroll_max, scroll_content_height: f32,
	split_weight: f32,
	split_parent: shared.Entity,
	tree_depth: int,
	split_weight_valid: bool,
	seen, laid_out, hovered, active, has_clip: bool,
	resolved_width_valid, resolved_height_valid: bool,
	fill_width_valid, fill_height_valid: bool,
}
EDITOR_HISTORY_CAPACITY :: 128
MAX_UI_EVENTS :: 256
UI_Event_Kind :: enum {
	Activated,
	Changed,
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
EDITOR_TRANSACTION_MAX_CHANGES :: 3
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
Editor_Edit_Transaction :: struct {
	changes: [EDITOR_TRANSACTION_MAX_CHANGES]Editor_Edit_Change,
	change_count: int,
	resource_changes: [4]Editor_Resource_Change,
	resource_change_count: int,
	structural: ^Editor_Structural_Change,
	component_structural: ^Editor_Component_Structural_Change,
	resource_structural: ^Editor_Resource_Structural_Change,
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
	ui_project_paint_revision: u64,
	ui_editor_paint_revision: u64,
	ui_layout_valid: bool,
	ui_project_viewport: Rect,
	ui_editor_viewport: Rect,
	ui_structure_sync_count: u64,
	ui_hierarchy_rebuild_count: u64,
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
	next_paint_order: int,
	layout_size_changed: bool,
	split_handles: [MAX_NODES]Split_Handle,
	split_handle_count, active_split_handle: int,
	split_previous_primary_down: bool,
	editor_split_previous_primary_down: bool,
	active_split_editor: bool,
	split_drag_pointer: f32,
	pointer_cursor: Pointer_Cursor,
	editor_visible: bool,
	editor_simulation_playing: bool,
	editor_simulation_stopped: bool,
	editor_simulation_step_requested: bool,
	editor_playback_begin_requested: bool,
	editor_playback_stop_requested: bool,
	editor_scene_save_requested: bool,
	editor_scene_revert_requested: bool,
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
	editor_has_selection: bool,
	editor_selected_resource: shared.Resource_UUID,
	editor_has_resource_selection: bool,
	editor_snapshot_elapsed: f32,
	editor_snapshot_valid: bool,
	editor_snapshot_was_visible: bool,
	editor_snapshot_has_selection: bool,
	editor_snapshot_selected_entity: shared.Entity,
	editor_snapshot_refresh_count: u64,
	editor_browser_snapshot_valid: bool,
	editor_browser_snapshot_has_selection: bool,
	editor_browser_snapshot_selected_entity: shared.Entity,
	editor_inspector_snapshot_valid: bool,
	editor_inspector_snapshot_entity: shared.Entity,
	editor_inspector_snapshot_component_revision: u64,
	editor_inspector_snapshot_has_resource: bool,
	editor_inspector_snapshot_resource: shared.Resource_UUID,
	editor_inspector_snapshot_resource_version: u32,
	editor_inspector_snapshot_stopped: bool,
	editor_inspector_snapshot_refresh_count: u64,
	editor_component_menu_open: bool,
	editor_resource_menu_open: bool,
	editor_layout_invalidated: bool,
	editor_transport_visual_state: Editor_Transport_Visual_State,
	editor_transport_visual_valid: bool,
	editor_gizmo_toolbar_visual_state: Editor_Gizmo_Toolbar_Visual_State,
	editor_gizmo_toolbar_visual_valid: bool,
	system_profile: ^shared.System_Profile,
	editor_system_profile_revision: u64,
	performance_diagnostics: ^shared.Performance_Diagnostics,
	editor_performance_diagnostics_revision: u64,
	editor_previous_primary_down: bool,
	focused_input: shared.Entity,
	has_focused_input: bool,
	focused_input_editor: bool,
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
	editor_scene_camera_captures_input: bool,
	editor_camera_mesh_segments: [EDITOR_CAMERA_MESH_MAX_SEGMENTS]Editor_Camera_Mesh_Segment,
	editor_camera_mesh_segment_count: int,
	editor_gizmo_visible: bool,
	editor_gizmo_mode: shared.Editor_Gizmo_Mode,
	editor_gizmo_space: shared.Editor_Gizmo_Space,
	editor_gizmo_origin: shared.Vec2,
	editor_gizmo_endpoints: [3]shared.Vec2,
	editor_gizmo_plane_points: [3][4]shared.Vec2,
	editor_gizmo_ring_points: [3][EDITOR_GIZMO_RING_POINT_COUNT]shared.Vec2,
	editor_gizmo_hovered_handle: Editor_Gizmo_Handle,
	editor_gizmo_active_handle: Editor_Gizmo_Handle,
	editor_gizmo_captures_pointer: bool,
	editor_gizmo_drag_pointer: shared.Vec2,
	editor_gizmo_drag_last_pointer: shared.Vec2,
	editor_gizmo_drag_angle: f32,
	editor_gizmo_drag_position: shared.Vec3,
	editor_gizmo_drag_rotation: shared.Vec3,
	editor_gizmo_drag_scale: shared.Vec3,
	editor_gizmo_drag_world_transform: shared.Transform_Component,
	editor_gizmo_drag_direction: shared.Vec2,
	editor_gizmo_drag_screen_axes: [3]shared.Vec2,
	editor_gizmo_drag_world_axes: [3]shared.Vec3,
	editor_gizmo_drag_camera_right: shared.Vec3,
	editor_gizmo_drag_camera_up: shared.Vec3,
	editor_gizmo_drag_pixels: f32,
	editor_gizmo_drag_world_scale: f32,
	err: string,
}

append_ui_event :: proc(state: ^State, event: UI_Event) {
	if state == nil || state.event_count >= MAX_UI_EVENTS {
		return
	}
	state.events[state.event_count] = event
	state.event_count += 1
}

ui_events :: proc(state: ^State) -> []UI_Event {
	if state == nil {
		return nil
	}
	return state.events[:state.event_count]
}

init :: proc(state: ^State) -> string {
	state^ = {}
	state.editor_pixel_density = 1
	state.editor_simulation_playing = true
	state.editor_history_clean_valid = true
	state.active_split_handle = -1
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
	state.editor_visible = !state.editor_visible
	if !state.editor_visible {
		editor_play(state)
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
	if state == nil { return }
	if state.editor_simulation_stopped {
		state.editor_playback_begin_requested = true
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

editor_world_restored :: proc(
	state: ^State,
	world: ^shared.World,
	selected_uuid: shared.Entity_UUID,
	had_selection: bool,
) {
	if state == nil || world == nil {
		return
	}
	state.editor_has_selection = false
	if had_selection {
		if entity_index, found := ecs.entity_index_by_uuid(world, selected_uuid); found {
			state.editor_selected_entity = world.entities[entity_index].id
			state.editor_has_selection = true
		}
	}
	state.editor_snapshot_valid = false
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false
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

destroy :: proc(state: ^State) {
	if state == nil { return }
	editor_history_clear(state)
	delete(state.input_original_text)
	delete(state.editor_dirty_entities)
	delete(state.editor_dirty_entity_lookup)
	delete(state.editor_dirty_resources)
	delete(state.editor_dirty_resource_lookup)
	delete(state.editor_collapsed_entities)
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
		clear_input_focus(state)
		state.active_entity = {}
		state.has_active_entity = false
		state.previous_primary_down = false
		state.editor_ui_active_entity = {}
		state.editor_ui_has_active_entity = false
		state.editor_previous_primary_down = false
		state.active_split_handle = -1
		state.split_previous_primary_down = false
		state.editor_split_previous_primary_down = false
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
		node.entity = entity.id
		node.origin = entity.origin
		node.editor_role = .None
		if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
			node.editor_role = world.editor_uis[entity.editor_ui_index].role
		}
		node.layout_index = entity.ui_layout_index
		node.hstack_index = entity.ui_hstack_index
		node.vstack_index = entity.ui_vstack_index
		node.scroll_area_index = entity.ui_scroll_area_index
		node.panel_index = entity.ui_panel_index
		node.table_index = entity.ui_table_index
		node.list_index = entity.ui_list_index
		node.progress_index = entity.ui_progress_index
		node.text_index = entity.ui_text_index
		node.button_index = entity.ui_button_index
		node.input_index = entity.ui_input_index
		node.checkbox_index = entity.ui_checkbox_index
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
	clear(&world.ui_dirty_entities)
	state.ui_structure_revision = world.ui_structure_revision
	state.ui_structure_synced = true
	state.ui_structure_sync_count += 1
	return ""
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
) -> string {
	if state == nil || world == nil { return "UI state or world is unavailable" }
	state.event_count = 0
	editor_ui_handle_shortcuts(state, keyboard)
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
	editor_scale := max(state.editor_pixel_density, 1)
	editor_width := surface_width / editor_scale
	editor_height := surface_height / editor_scale
	reconcile_editor_ui_world(state, world)
	if err := sync_ui_structure(state, world); err != "" { return err }
	editor_ui_anchor_component_menu(state, world, editor_width, editor_height)
	editor_ui_anchor_resource_menu(state, world, editor_width, editor_height)
	project_layout := Rect{0, 0, width, height}
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
	); if state.editor_gizmo_captures_pointer { project_pointer = {} }
	editor_pointer := pointer
	if editor_pointer.available { editor_pointer.position.x /= editor_scale; editor_pointer.position.y /= editor_scale }
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
	if state.active_split_handle >= 0 { project_pointer = {}; editor_pointer = {} }
	if update_scroll_areas(
		state,
		world,
		project_pointer,
		delta_seconds,
		false,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err } }
	if update_scroll_areas(
		state,
		world,
		editor_pointer,
		delta_seconds,
		true,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err } }
	project_press_started :=
		project_pointer.available && project_pointer.primary_down && !state.previous_primary_down
	project_press_released :=
		project_pointer.available && !project_pointer.primary_down && state.previous_primary_down
	editor_press_started :=
		editor_pointer.available &&
		editor_pointer.primary_down &&
		!state.editor_previous_primary_down
	editor_press_released :=
		editor_pointer.available &&
		!editor_pointer.primary_down &&
		state.editor_previous_primary_down
	project_pressed, project_pressed_ok := update_interaction(state, project_pointer, false)
	component_menu_was_open := state.editor_component_menu_open
	resource_menu_was_open := state.editor_resource_menu_open
	pressed, pressed_ok := update_interaction(state, editor_pointer, true)
	if project_press_started && project_pressed_ok {
		list_drag_begin(state, world, project_pressed, project_pointer.position, false)
	}
	if editor_press_started && pressed_ok {
		list_drag_begin(state, world, pressed, editor_pointer.position, true)
	}
	list_drag_update(state, world, project_pointer, project_press_released, false)
	list_drag_update(state, world, editor_pointer, editor_press_released, true)
	if state.pointer_cursor == .Default {
		state.pointer_cursor = numeric_input_pointer_cursor(state, world)
	}
	sync_ui_interaction_states(state, world)
	panel_changed := false
	if pressed_ok {
		_ = ecs.mark_ui_activated(world, int(pressed.index))
		append_ui_event(
			state,
			{kind = .Activated, entity = pressed, position = editor_pointer.position},
		)
		_ = handle_list_press(world, pressed)
		editor_ui_prepare_input_focus(state, world, int(pressed.index))
		handle_input_press(state, world, pressed, editor_pointer.position)
		checkbox_changed := handle_checkbox_press(state, world, pressed)
		if checkbox_changed {
			append_ui_event(state, {kind = .Changed, entity = pressed})
		}
		panel_changed = checkbox_changed || panel_changed
		panel_title_changed := handle_panel_title_press(
			state,
			world,
			pressed,
			editor_pointer.position,
		)
		if panel_title_changed {
			append_ui_event(state, {kind = .Changed, part = .Panel_Title, entity = pressed})
		}
		panel_changed = panel_title_changed || panel_changed
	}
	if component_menu_was_open &&
	   editor_press_started &&
	   (!pressed_ok || !editor_ui_component_menu_contains(world, pressed)) {
		editor_ui_close_component_menu(state, world)
		panel_changed = true
	}
	if state.editor_component_menu_open && keyboard.escape {
		editor_ui_close_component_menu(state, world)
		panel_changed = true
	}
	if resource_menu_was_open &&
	   editor_press_started &&
	   (!pressed_ok || !editor_ui_resource_menu_contains(world, pressed)) {
		editor_ui_close_resource_menu(state, world)
		panel_changed = true
	}
	if state.editor_resource_menu_open && keyboard.escape {
		editor_ui_close_resource_menu(state, world)
		panel_changed = true
	}
	if project_pressed_ok {
		_ = ecs.mark_ui_activated(world, int(project_pressed.index))
		append_ui_event(
			state,
			{kind = .Activated, entity = project_pressed, position = project_pointer.position},
		)
		_ = handle_list_press(world, project_pressed)
		handle_input_press(state, world, project_pressed, project_pointer.position)
		checkbox_changed := handle_checkbox_press(state, world, project_pressed)
		if checkbox_changed {
			append_ui_event(state, {kind = .Changed, entity = project_pressed})
		}
		panel_changed = checkbox_changed || panel_changed
		panel_title_changed := handle_panel_title_press(
			state,
			world,
			project_pressed,
			project_pointer.position,
		)
		if panel_title_changed {
			append_ui_event(
				state,
				{kind = .Changed, part = .Panel_Title, entity = project_pressed},
			)
		}
		panel_changed = panel_title_changed || panel_changed
	}
	panel_changed = editor_ui_consume_events(state, world) || panel_changed
	sync_ui_interaction_states(state, world)
	if panel_changed {
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
		keyboard.save
	editor_history_shortcut :=
		state.editor_visible &&
		(!state.has_focused_input || state.focused_input_editor) &&
		(keyboard.undo || keyboard.redo)
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
	if state.editor_has_selection {
		index := int(state.editor_selected_entity.index)
		if index < 0 ||
		   index >= len(world.entities) ||
		   !world.entities[index].alive ||
		   world.entities[index].origin == .Editor ||
		   world.entities[index].id.generation !=
			   state.editor_selected_entity.generation { editor_clear_selection(state) }
	}
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
	if state.editor_pick_requested { state.editor_pick_position.x *= editor_scale; state.editor_pick_position.y *= editor_scale }
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
	return ""
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
	if available.width <= 0 ||
	   available.height <=
		   0 { return {available.x, available.y, max(available.width, 0), max(available.height, 0)} }
	return available
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
	viewport := editor_viewport(state, surface_width, surface_height, width, height)
	if !rect_contains(viewport, pointer.position) { return {} }
	return {
		position = {
			(pointer.position.x - viewport.x) / viewport.width * width,
			(pointer.position.y - viewport.y) / viewport.height * height,
		},
		wheel_y = pointer.wheel_y,
		primary_down = pointer.primary_down,
		available = true,
	}
}

Popup_Placement :: struct {
	minimum_width: f32,
	maximum_width: f32,
	maximum_height: f32,
	viewport_margin: f32,
	gap: f32,
	viewport_top: f32,
	viewport_bottom: f32,
}

popup_contains_entity :: proc(
	world: ^shared.World,
	entity: shared.Entity,
	anchor_entity_index, popup_entity_index: int,
) -> bool {
	if world == nil || !ecs.entity_is_alive(world, int(entity.index)) {
		return false
	}
	index := int(entity.index)
	origin := world.entities[index].origin
	for _ in 0 ..< MAX_NODES {
		if index == anchor_entity_index || index == popup_entity_index {
			return true
		}
		value := world.entities[index]
		if value.ui_layout_index < 0 || value.ui_layout_index >= len(world.ui_layouts) {
			break
		}
		parent := world.ui_layouts[value.ui_layout_index].parent
		if parent == (shared.Entity_UUID{}) {
			break
		}
		index = find_parent_entity(world, parent, origin)
		if index < 0 {
			break
		}
	}
	return false
}

place_popup :: proc(
	state: ^State,
	world: ^shared.World,
	popup_entity_index, anchor_entity_index: int,
	content_height, viewport_width, viewport_height: f32,
	placement: Popup_Placement,
) -> bool {
	if state == nil ||
	   world == nil ||
	   !ecs.entity_is_alive(world, popup_entity_index) ||
	   !ecs.entity_is_alive(world, anchor_entity_index) {
		return false
	}
	popup := world.entities[popup_entity_index]
	if popup.ui_layout_index < 0 || popup.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	anchor_node := find_node_by_entity_index(state, anchor_entity_index)
	if anchor_node < 0 || !state.nodes[anchor_node].laid_out {
		return false
	}
	anchor := state.nodes[anchor_node].rect
	if anchor.width <= 0 {
		return false
	}
	margin := max(placement.viewport_margin, 0)
	gap := max(placement.gap, 0)
	bottom := viewport_height - margin - max(placement.viewport_bottom, 0)
	top := margin + max(placement.viewport_top, 0)
	layout := &world.ui_layouts[popup.ui_layout_index]
	layout.size.x = clamp(anchor.width, placement.minimum_width, placement.maximum_width)
	layout.size.y = min(content_height, min(placement.maximum_height, max(bottom - top, 0)))
	layout.position.x = clamp(
		anchor.x,
		margin,
		max(viewport_width - layout.size.x - margin, margin),
	)
	layout.position.y = anchor.y + anchor.height + gap
	if layout.position.y + layout.size.y > bottom {
		layout.position.y = max(anchor.y - layout.size.y - gap, top)
	}
	return true
}

editor_clear_selection :: proc(state: ^State) {if state == nil { return }
	state.editor_has_selection = false
	state.editor_snapshot_valid = false
	for &node in state.nodes[:state.node_count] { if node.editor_role == .Inspector_Scroll { node.scroll_offset = 0; node.scroll_target = 0 } }
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false
	state.editor_gizmo_visible = false}

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

editor_select_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity: shared.Entity,
	height: f32,
) -> bool {
	_ = height
	if state == nil || world == nil { return false }; index := int(entity.index)
	if index < 0 ||
	   index >= len(world.entities) ||
	   !world.entities[index].alive ||
	   world.entities[index].origin == .Editor ||
	   world.entities[index].id.generation != entity.generation { return false }
	if !state.editor_has_selection ||
	   state.editor_selected_entity !=
		   entity { for &node in state.nodes[:state.node_count] { if node.editor_role == .Inspector_Scroll { node.scroll_offset = 0; node.scroll_target = 0 } } }
	if !state.editor_has_selection ||
	   state.editor_selected_entity !=
		   entity { state.editor_gizmo_active_handle = .None; state.editor_gizmo_captures_pointer = false }
	state.editor_selected_entity = entity
	state.editor_has_selection = true
	state.editor_has_resource_selection = false
	state.editor_snapshot_valid = false
	row_slot := -1
	for component in world.editor_uis { if (component.role == .Browser_Row || component.role == .Browser_Row_Label) && component.target == entity { row_slot = component.slot; break } }
	if row_slot >=
	   0 { for &node in state.nodes[:state.node_count] { if node.editor_role != .Browser_Scroll { continue }; row_top := f32(row_slot) * EDITOR_ENTITY_ROW_HEIGHT; row_bottom := row_top + EDITOR_ENTITY_ROW_HEIGHT; if row_top < node.scroll_target { node.scroll_target = row_top } else if row_bottom > node.scroll_target + node.rect.height { node.scroll_target = row_bottom - node.rect.height }; break } }
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
	if index, found := ecs.entity_index_by_uuid(world, id);
	   found && world.entities[index].origin == origin {
		return index
	}
	return -1
}

layout_all :: proc(
	state: ^State,
	world: ^shared.World,
	project_viewport, editor_viewport: Rect,
	layout_project := true,
	layout_editor := true,
) -> string {
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
			if err := layout_node(state, world, i, viewport, {}, false, {}, false, {}, false, 0);
			   err != "" {
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

node_is_panel_action :: proc(world: ^shared.World, node: ^Node) -> bool {
	return(
		world != nil &&
		node != nil &&
		node.button_index >= 0 &&
		node.button_index < len(world.ui_buttons) &&
		world.ui_buttons[node.button_index].panel_action \
	)
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
) {
	if node_index < 0 || node_index >= state.node_count || visit[node_index] != 0 {
		return
	}
	visit[node_index] = 1
	if output_count^ < MAX_NODES {
		output[output_count^] = node_index
		state.nodes[node_index].tree_depth = depth
		output_count^ += 1
	}
	layout := world.ui_layouts[state.nodes[node_index].layout_index]
	if !layout.tree_collapsed && !layout.hidden {
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
		} else {
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
			)
		}
	}
	return output_count
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
	if node.parent_entity_index < 0 {
		if layout.fill_width {
			layout_size.x = max(
				parent.width - layout.position.x - layout.margin.w - layout.margin.y,
				layout.min_size.x,
			)
		}
		if layout.fill_height {
			layout_size.y = max(
				parent.height - layout.position.y - layout.margin.x - layout.margin.z,
				layout.min_size.y,
			)
		}
		node.rect = {
			layout.position.x + layout.margin.w,
			layout.position.y + layout.margin.x,
			layout_size.x,
			layout_size.y,
		}
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
		node.rect = {
			parent.x + parent_padding.w + layout.position.x + layout.margin.w,
			parent.y + parent_padding.x + layout.position.y + layout.margin.x,
			layout_size.x,
			layout_size.y,
		}
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
	is_table := node.table_index >= 0 && node.table_index < len(world.ui_tables)
	is_list := node.list_index >= 0 && node.list_index < len(world.ui_lists)
	panel: shared.UI_Panel_Component
	table: shared.UI_Table_Component
	list: shared.UI_List_Component
	if is_panel { panel = world.ui_panels[node.panel_index] }
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
	if is_panel && panel.title != "" {
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
	if is_panel && panel.collapsible && panel.collapsed {
		node.scroll_offset = 0
		node.scroll_target = 0
		node.scroll_max = 0
		node.scroll_content_height = 0
		return ""
	}
	child_clip := inherited_clip; child_has_clip := has_inherited_clip
	if is_scroll_area { if child_has_clip { child_clip = rect_intersection(child_clip, content) } else { child_clip = content }; child_has_clip = true }
	scroll_offset := node.scroll_offset
	content_bottom := f32(0)
	content_right := f32(0)
	children: [MAX_NODES]int
	child_count := 0
	total_margins := f32(0)
	total_weight := f32(0)
	fixed_main_size := f32(0)
	flex_child_count := 0
	fixed_children: [MAX_NODES]bool
	if ((is_hstack || is_vstack) && stack.fill) || is_table {
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
	}
	available_main := content.height; if is_hstack { available_main = content.width }
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
	list_flow_children: [MAX_NODES]int
	list_flow_count := 0
	if is_list && list.tree_enabled {
		list_flow_count = tree_list_flow(state, world, node_index, &list_flow_children)
	}
	child_index := node.first_child_node
	if is_list && list.tree_enabled {
		child_index = -1
		if list_flow_count > 0 {
			child_index = list_flow_children[0]
		}
	}
	list_flow_ordinal := 0
	for child_index >= 0 {
		when ODIN_TEST {
			state.layout_child_edge_visit_count += 1
		}
		child := &state.nodes[child_index]
		next_child_index := child.next_sibling_node
		if is_list && list.tree_enabled {
			next_child_index = -1
			if list_flow_ordinal + 1 < list_flow_count {
				next_child_index = list_flow_children[list_flow_ordinal + 1]
			}
			list_flow_ordinal += 1
		}
		child_layout := world.ui_layouts[child.layout_index]
		if child_layout.hidden || is_panel && node_is_panel_action(world, child) {
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
		if (is_hstack || is_vstack) &&
		   stack.fill { main_size := child_main_sizes[child_ordinal]; if is_hstack { child_size = {main_size, max(content.height - child_layout.margin.x - child_layout.margin.z, 0)} } else { child_size = {max(content.width - child_layout.margin.w - child_layout.margin.y, 0), main_size} }; has_child_size = true }
		if is_table {
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
			position = {
				content.x + child_layout.margin.w,
				content.y + cursor + child_layout.margin.x,
			}
			cursor += child_layout.margin.x + child_size.y + child_layout.margin.z + list.gap
			has_child_size = true
			child_flowed = true
		} else if is_hstack {position = {content.x + cursor + child_layout.margin.w, content.y + child_layout.margin.x}; cursor += child_layout.margin.w + child_size.x + child_layout.margin.y; if stack.draggable && child_ordinal < child_count - 1 && state.split_handle_count < MAX_NODES {handle_rect := Rect{content.x + cursor, content.y, max(gap, 8), content.height}; handle_rect.x += (gap - handle_rect.width) * 0.5; state.split_handles[state.split_handle_count] = {
					rect = handle_rect,
					before_node = child_index,
					after_node = children[child_ordinal + 1],
					horizontal = true,
					editor = node.origin == .Editor,
					min_size = stack.min_size,
				}; state.split_handle_count += 1}; cursor += gap; child_flowed = true} else if is_vstack {position = {content.x + child_layout.margin.w, content.y + cursor + child_layout.margin.x}; cursor += child_layout.margin.x + child_size.y + child_layout.margin.z; if stack.draggable && child_ordinal < child_count - 1 && state.split_handle_count < MAX_NODES {handle_rect := Rect{content.x, content.y + cursor, content.width, max(gap, 8)}; handle_rect.y += (gap - handle_rect.height) * 0.5; state.split_handles[state.split_handle_count] = {
					rect = handle_rect,
					before_node = child_index,
					after_node = children[child_ordinal + 1],
					horizontal = false,
					editor = node.origin == .Editor,
					min_size = stack.min_size,
				}; state.split_handle_count += 1}; cursor += gap; child_flowed = true}
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
		unscrolled_bottom :=
			state.nodes[child_index].rect.y +
			state.nodes[child_index].rect.height +
			child_layout.margin.z
		if is_scroll_area { unscrolled_bottom += scroll_offset }
		content_bottom = max(content_bottom, unscrolled_bottom - content.y)
		unscrolled_right :=
			state.nodes[child_index].rect.x +
			state.nodes[child_index].rect.width +
			child_layout.margin.y
		content_right = max(content_right, unscrolled_right - content.x)
		child_ordinal += 1
		child_index = next_child_index
	}
	if is_table &&
	   child_count > 0 { content_bottom = max(content_bottom, table_y + table_row_height) }
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
	for node in state.nodes[:state.node_count] {
		if !node.hovered {
			continue
		}
		entity_index := int(node.entity.index)
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive ||
		   entity.id != node.entity ||
		   entity.ui_input_index < 0 ||
		   entity.ui_input_index >= len(world.ui_inputs) {
			continue
		}
		input := world.ui_inputs[entity.ui_input_index]
		if input.numeric && input.draggable && !input.read_only {
			return .Horizontal_Resize
		}
	}
	return .Default
}

current_pointer_cursor :: proc(state: ^State) -> Pointer_Cursor {
	if state == nil { return .Default }
	return state.pointer_cursor
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
	just_pressed := pointer.primary_down && !previous_down
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

has_text_focus :: proc(state: ^State) -> bool {
	return state != nil && state.has_focused_input
}

clear_input_focus :: proc(state: ^State) {
	if state == nil { return }
	delete(state.input_original_text)
	state.input_original_text = ""
	state.has_focused_input = false
	state.focused_input = {}
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
	index := int(pressed.index)
	if index < 0 || index >= len(world.entities) { return }
	entity := world.entities[index]
	if !entity.alive || entity.id != pressed || entity.ui_input_index < 0 {
		blur_input_edit(state, world)
		return
	}
	if state.has_focused_input {
		if state.focused_input == pressed {
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
			_ = ecs.mark_ui_changed(world, entity_index)
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
	_ = ecs.mark_ui_submitted(world, entity_index)
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
	_ = ecs.mark_ui_cancelled(world, entity_index)
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
				_ = ecs.mark_ui_changed(world, entity_index)
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
	_ = ecs.mark_ui_changed(world, entity_index)
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
			case .None:
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

handle_list_press :: proc(world: ^shared.World, pressed: shared.Entity) -> bool {
	if world == nil { return false }
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
			_ = ecs.mark_ui_changed(world, parent_index)
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
) {
	for &node in state.nodes[:state.node_count] { if (node.origin == .Editor) == editor { node.hovered = false; node.active = false } }
	previous_down := state.previous_primary_down
	has_active := state.has_active_entity
	active_entity := state.active_entity
	if editor { previous_down = state.editor_previous_primary_down; has_active = state.editor_ui_has_active_entity; active_entity = state.editor_ui_active_entity }
	if !pointer.available {
		if editor { state.editor_ui_has_active_entity = false; state.editor_previous_primary_down = false } else { state.has_active_entity = false; state.previous_primary_down = false }
		return {}, false
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
	if pointer.primary_down && !previous_down {
		has_active = hit >= 0
		if hit >=
		   0 { active_entity = state.nodes[hit].entity; pressed = active_entity; pressed_ok = true }
	}
	if pointer.primary_down && has_active {
		if active_index := find_node(state, active_entity);
		   active_index >=
		   0 { mark_interaction_chain(state, active_index, true) } else { has_active = false }
	} else if !pointer.primary_down { has_active = false }
	if editor { state.editor_ui_has_active_entity = has_active; state.editor_ui_active_entity = active_entity; state.editor_previous_primary_down = pointer.primary_down } else { state.has_active_entity = has_active; state.active_entity = active_entity; state.previous_primary_down = pointer.primary_down }
	return pressed, pressed_ok
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
	_ = ecs.mark_ui_changed(world, int(node.entity.index))
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
	_ = ecs.mark_ui_changed(world, entity_index)
	return true
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
	border_color := layout.border_color
	border_width := layout.border_width
	if node.parent_entity_index >= 0 && node.parent_entity_index < len(world.entities) {
		parent := world.entities[node.parent_entity_index]
		if parent.ui_list_index >= 0 && parent.ui_list_index < len(world.ui_lists) {
			list := world.ui_lists[parent.ui_list_index]
			selected := list.selected == world.entities[int(node.entity.index)].uuid
			if selected && list.selection_background.w > 0 {
				background = list.selection_background
			}
			if !selected && node.hovered && list.hover_background.w > 0 {
				background = list.hover_background
			}
			if node.active && list.active_background.w > 0 {
				background = list.active_background
			}
			if parent.ui_state_index >= 0 && parent.ui_state_index < len(world.ui_states) {
				interaction := world.ui_states[parent.ui_state_index]
				if interaction.dragging &&
				   interaction.drop_placement == .Into &&
				   interaction.drop_target == world.entities[int(node.entity.index)].uuid &&
				   list.drop_target_background.w > 0 {
					background = list.drop_target_background
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
				corner_radius = layout.corner_radius,
				border_color = border_color,
				border_width = border_width,
			},
		); err != "" { return err }
	}
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		panel := world.ui_panels[node.panel_index]
		if panel.title != "" {
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
				if err := append_paint(
					state,
					{
						kind = .Disclosure,
						rect = disclosure_rect,
						color = panel.title_color,
						corner_radius = panel.disclosure_corner_radius,
						disclosure_expanded = !panel.collapsed,
					},
				); err != "" { return err }
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
	if node.text_index >= 0 &&
	   node.text_index <
		   len(
			   world.ui_texts,
		   ) { text := world.ui_texts[node.text_index]; select_font(state, text.font); if err := append_text(state, text.text, text.color, text.size, node.rect, layout.padding, text.alignment); err != "" { return err } }
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
	if node.button_index >= 0 && node.button_index < len(world.ui_buttons) {
		button := world.ui_buttons[node.button_index]
		select_font(state, button.font)
		color := button.color
		if node.active && button.active_color.w > 0 {
			color = button.active_color
		} else if node.hovered && button.hover_color.w > 0 {
			color = button.hover_color
		}
		if button.icon != .None {
			inset := min(button.icon_inset, min(node.rect.width, node.rect.height) * 0.5)
			icon := Rect {
				node.rect.x + inset,
				node.rect.y + inset,
				max(node.rect.width - inset * 2, 0),
				max(node.rect.height - inset * 2, 0),
			}
			painted_disclosure := false
			if button.icon == .Chevron_Right || button.icon == .Chevron_Down {
				if err := append_paint(
					state,
					{
						kind = .Disclosure,
						rect = icon,
						color = color,
						disclosure_expanded = button.icon == .Chevron_Down,
						corner_radius = 0,
					},
				); err != "" {
					return err
				}
				painted_disclosure = true
			}
			if !painted_disclosure {
				lines: [2][2]shared.Vec2
				switch button.icon {
					case .Close:
						lines = {
							{{icon.x, icon.y}, {icon.x + icon.width, icon.y + icon.height}},
							{{icon.x + icon.width, icon.y}, {icon.x, icon.y + icon.height}},
						}
					case .Plus:
						lines = {
							{
								{icon.x, icon.y + icon.height * 0.5},
								{icon.x + icon.width, icon.y + icon.height * 0.5},
							},
							{
								{icon.x + icon.width * 0.5, icon.y},
								{icon.x + icon.width * 0.5, icon.y + icon.height},
							},
						}
					case .None, .Chevron_Right, .Chevron_Down:
				}
				for line in lines {
					if err := append_paint(
						state,
						{
							kind = .Line,
							color = color,
							line_start = line[0],
							line_end = line[1],
							line_thickness = button.icon_stroke,
						},
					); err != "" {
						return err
					}
				}
			}
		} else if err := append_centered_text(
			state,
			button.text,
			color,
			button.size,
			node.rect,
			layout.padding,
			button.alignment,
		); err != "" {
			return err
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
	if err := append_editor_gizmo(state); err != "" {
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

append_editor_gizmo :: proc(state: ^State) -> string {
	if !state.editor_gizmo_visible { return "" }
	scale := max(state.editor_pixel_density, 1)
	colors := [3]shared.Vec4{{0.95, 0.20, 0.24, 1}, {0.28, 0.88, 0.42, 1}, {0.24, 0.48, 1, 1}}
	labels := [3]string{"X", "Y", "Z"}
	if state.editor_gizmo_mode == .Rotate {
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

entity_component_count :: proc(world: ^shared.World, entity_index: int) -> int {
	if entity_index < 0 || entity_index >= len(world.entities) {
		return 0
	}
	entity := world.entities[entity_index]
	count := 0
	indices := [16]int {
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
) -> string {
	content_x := rect.x + padding.w
	content_width := max(rect.width - padding.w - padding.y, 0)
	baseline := rect.y + padding.x + state.font.ascender * size
	line_start := 0
	bytes := transmute([]u8)text
	for byte, index in bytes {
		if byte != '\n' {
			continue
		}
		if err := append_aligned_text_line(
			state,
			text[line_start:index],
			color,
			size,
			content_x,
			content_width,
			baseline,
			alignment,
		); err != "" {
			return err
		}
		line_start = index + 1
		baseline += size
	}
	return append_aligned_text_line(
		state,
		text[line_start:],
		color,
		size,
		content_x,
		content_width,
		baseline,
		alignment,
	)
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
