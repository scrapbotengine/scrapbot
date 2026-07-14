package ui

import shared "../shared"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

MAX_NODES :: 4096
MAX_PAINT_COMMANDS :: 16384
FONT_FIRST_CHAR :: 32
FONT_CHAR_COUNT :: 95
FONT_ATLAS_SIZE :: 512
FONT_ASCENDER :: f32(0.96875)
FONT_ATLAS_DATA :: #load("assets/inter_mtsdf.bin")

EDITOR_TOP_BAR_HEIGHT :: f32(48)
EDITOR_STATUS_BAR_HEIGHT :: f32(28)
EDITOR_LEFT_SIDEBAR_WIDTH :: f32(240)
EDITOR_RIGHT_SIDEBAR_WIDTH :: f32(300)
EDITOR_SIDEBAR_MIN_WIDTH :: f32(150)
EDITOR_VIEWPORT_MIN_WIDTH :: f32(320)
EDITOR_VIEWPORT_INSET :: f32(4)
EDITOR_ENTITY_ROW_HEIGHT :: f32(28)
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
Keyboard_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, shift, fine, enter, escape, select_all, undo, redo: bool,
}
Paint_Kind :: enum {
	Panel,
	Glyph,
	Line,
	Triangle,
	Ring,
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
Font_Glyph :: struct {
	advance: f32,
	plane, uv: shared.Vec4,
}
Font_Atlas :: struct {
	glyphs: [FONT_CHAR_COUNT]Font_Glyph,
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
	layout_index, hstack_index, vstack_index, scroll_area_index, panel_index, table_index, text_index, button_index, input_index, parent_entity_index: int,
	rect, clip: Rect,
	paint_order: int,
	scroll_offset, scroll_target, scroll_max, scroll_content_height: f32,
	split_weight: f32,
	split_parent: shared.Entity,
	split_weight_valid: bool,
	seen, hovered, active, has_clip: bool,
}
EDITOR_HISTORY_CAPACITY :: 128
Editor_Edit_Command :: struct {
	target: shared.Entity,
	component_revision: u64,
	field: shared.Editor_Inspector_Field,
	axis: shared.Editor_Inspector_Axis,
	custom_storage_index: int,
	custom_field_index: int,
	before: f32,
	after: f32,
}
State :: struct {
	nodes: [MAX_NODES]Node,
	node_count: int,
	paint: [MAX_PAINT_COMMANDS]Paint_Command,
	paint_count: int,
	font: Font_Atlas,
	active_entity: shared.Entity,
	has_active_entity: bool,
	previous_primary_down: bool,
	editor_ui_active_entity: shared.Entity,
	editor_ui_has_active_entity: bool,
	next_paint_order: int,
	split_handles: [MAX_NODES]Split_Handle,
	split_handle_count, active_split_handle: int,
	split_previous_primary_down: bool,
	editor_split_previous_primary_down: bool,
	active_split_editor: bool,
	split_drag_pointer: f32,
	editor_visible: bool,
	editor_pixel_density: f32,
	editor_paint_start: int,
	editor_selected_entity: shared.Entity,
	editor_has_selection: bool,
	editor_snapshot_elapsed: f32,
	editor_snapshot_valid: bool,
	editor_snapshot_was_visible: bool,
	editor_snapshot_has_selection: bool,
	editor_snapshot_selected_entity: shared.Entity,
	editor_snapshot_refresh_count: u64,
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
	editor_history: [EDITOR_HISTORY_CAPACITY]Editor_Edit_Command,
	editor_history_count: int,
	editor_history_cursor: int,
	editor_pick_requested: bool,
	editor_pick_position: shared.Vec2,
	editor_scene_camera_captures_input: bool,
	editor_gizmo_visible: bool,
	editor_gizmo_mode: shared.Editor_Gizmo_Mode,
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
	editor_gizmo_drag_direction: shared.Vec2,
	editor_gizmo_drag_screen_axes: [3]shared.Vec2,
	editor_gizmo_drag_camera_right: shared.Vec3,
	editor_gizmo_drag_camera_up: shared.Vec3,
	editor_gizmo_drag_pixels: f32,
	editor_gizmo_drag_world_scale: f32,
	editor_gizmo_paint_start: int,
	editor_gizmo_paint_end: int,
	err: string,
}

init :: proc(state: ^State) -> string {
	state^ = {}
	state.editor_pixel_density = 1
	state.active_split_handle = -1
	state.font.glyphs = FONT_GLYPHS
	state.font.ready = true
	return ""
}

destroy :: proc(state: ^State) {
	if state == nil { return }
	delete(state.input_original_text)
	state^ = {}
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
) -> string {
	if state == nil || world == nil { return "UI state or world is unavailable" }
	surface_width := drawable_width; if surface_width <= 0 { surface_width = width }
	surface_height := drawable_height; if surface_height <= 0 { surface_height = height }
	if !state.font.ready { if err := init(state); err != "" { return err } }
	editor_scale := max(state.editor_pixel_density, 1)
	editor_width := surface_width / editor_scale
	editor_height := surface_height / editor_scale
	reconcile_editor_ui_world(state, world, editor_width, editor_height)
	for &node in state.nodes[:state.node_count] { node.seen = false }
	for &entity in world.entities {
		if !entity.alive ||
		   (entity.origin == .Editor && !state.editor_visible) ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) ||
		   ui_entity_or_ancestor_hidden(world, int(entity.id.index)) { continue }
		index := find_node(state, entity.id)
		if index <
		   0 { if state.node_count >= MAX_NODES { return "too many UI entities" }; index = state.node_count; state.node_count += 1; state.nodes[index] = {} }
		node := &state.nodes[index]; node.entity = entity.id; node.origin = entity.origin; node.editor_role = .None; if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) { node.editor_role = world.editor_uis[entity.editor_ui_index].role }; node.layout_index = entity.ui_layout_index; node.hstack_index = entity.ui_hstack_index; node.vstack_index = entity.ui_vstack_index; node.scroll_area_index = entity.ui_scroll_area_index; node.panel_index = entity.ui_panel_index; node.table_index = entity.ui_table_index; node.text_index = entity.ui_text_index; node.button_index = entity.ui_button_index; node.input_index = entity.ui_input_index; node.parent_entity_index = find_parent_entity(world, world.ui_layouts[entity.ui_layout_index].parent, entity.origin); node.seen = true
	}
	for i := 0;
	    i <
	    state.node_count; { if state.nodes[i].seen { i += 1 } else { state.node_count -= 1; state.nodes[i] = state.nodes[state.node_count] } }
	project_layout := Rect{0, 0, width, height}
	editor_layout := Rect{0, 0, editor_width, editor_height}
	if !state.editor_visible && state.has_focused_input && state.focused_input_editor {
		if !finish_input_edit(state, world) { cancel_input_edit(state, world) }
		clear_input_focus(state)
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
	if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }
	if editor_ui_fit_inspector_width(state, world) {
		if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }
	}
	if update_split_interaction(
		state,
		project_pointer,
		false,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }; _ = update_split_interaction(state, project_pointer, false) }
	if update_split_interaction(
		state,
		editor_pointer,
		true,
	) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err }; if editor_ui_fit_inspector_width(state, world) { if err := layout_all(state, world, project_layout, editor_layout); err != "" { return err } }; _ = update_split_interaction(state, editor_pointer, true) }
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
	editor_press_started :=
		editor_pointer.available &&
		editor_pointer.primary_down &&
		!state.editor_previous_primary_down
	project_pressed, project_pressed_ok := update_interaction(state, project_pointer, false)
	pressed, pressed_ok := update_interaction(state, editor_pointer, true)
	if pressed_ok { handle_input_press(state, world, pressed, editor_pointer.position); handle_editor_ecs_press(state, world, pressed, editor_pointer.position) }
	if project_pressed_ok { handle_input_press(state, world, project_pressed, project_pointer.position) }
	if editor_press_started &&
	   !pressed_ok &&
	   state.has_focused_input &&
	   state.focused_input_editor {
		if !finish_input_edit(state, world) { cancel_input_edit(state, world) }
		clear_input_focus(state)
	}
	if project_press_started &&
	   !project_pressed_ok &&
	   state.has_focused_input &&
	   !state.focused_input_editor {
		if !finish_input_edit(state, world) { cancel_input_edit(state, world) }
		clear_input_focus(state)
	}
	editor_history_shortcut :=
		state.editor_visible &&
		(!state.has_focused_input || state.focused_input_editor) &&
		(keyboard.undo || keyboard.redo)
	if editor_history_shortcut {
		if state.has_focused_input {
			if !finish_input_edit(state, world) { cancel_input_edit(state, world) }
			clear_input_focus(state)
		}
		_ = editor_history_apply(state, world, keyboard.redo)
	} else {
		update_focused_input(state, world, keyboard, delta_seconds)
		update_input_scrub(state, world, editor_pointer, keyboard)
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
		selection_changed :=
			state.editor_snapshot_has_selection != state.editor_has_selection ||
			(state.editor_has_selection &&
					state.editor_snapshot_selected_entity != state.editor_selected_entity)
		if !state.editor_snapshot_valid ||
		   selection_changed ||
		   state.editor_snapshot_elapsed >= EDITOR_SNAPSHOT_INTERVAL {
			refresh_editor_ecs_snapshot(state, world)
		}
	}
	validate_focused_editor_input(state, world)
	state.editor_snapshot_was_visible = state.editor_visible
	if state.editor_pick_requested { state.editor_pick_position.x *= editor_scale; state.editor_pick_position.y *= editor_scale }
	state.paint_count = 0
	for i in 0 ..< state.node_count { if state.nodes[i].origin != .Editor && state.nodes[i].parent_entity_index < 0 { if err := paint_node(state, world, i, 0); err != "" { return err } } }
	if err := append_split_handles(state, false); err != "" { return err }
	state.editor_paint_start = state.paint_count
	if state.editor_visible {
		for i in 0 ..< state.node_count { if state.nodes[i].origin == .Editor && state.nodes[i].parent_entity_index < 0 { if err := paint_node(state, world, i, 0); err != "" { return err } } }
		if err := append_split_handles(state, true); err != "" { return err }
		if editor_scale !=
		   1 { for i in state.editor_paint_start ..< state.paint_count { scale_paint_command(&state.paint[i], editor_scale) } }
		state.editor_gizmo_paint_start = state.paint_count
		if err := append_editor_gizmo(state); err != "" { return err }
		state.editor_gizmo_paint_end = state.paint_count
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
		if layout.parent == "" { return false }
		index = find_parent_entity(world, layout.parent, entity.origin)
		if index < 0 { return false }
	}
	return true
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
	state.editor_selected_entity =
		entity; state.editor_has_selection = true; state.editor_snapshot_valid = false
	row_slot := -1
	for component in world.editor_uis { if (component.role == .Browser_Row || component.role == .Browser_Row_Label) && component.target == entity { row_slot = component.slot; break } }
	if row_slot >=
	   0 { for &node in state.nodes[:state.node_count] { if node.editor_role != .Browser_Scroll { continue }; row_top := f32(row_slot) * EDITOR_ENTITY_ROW_HEIGHT; row_bottom := row_top + EDITOR_ENTITY_ROW_HEIGHT; if row_top < node.scroll_target { node.scroll_target = row_top } else if row_bottom > node.scroll_target + node.rect.height { node.scroll_target = row_bottom - node.rect.height }; break } }
	return true
}

find_node :: proc(state: ^State, entity: shared.Entity) -> int {
	for node, i in state.nodes[:state.node_count] {
		if node.entity == entity { return i }
	}
	return -1
}

find_node_by_entity_index :: proc(state: ^State, index: int) -> int {
	for node, i in state.nodes[:state.node_count] {
		if int(node.entity.index) == index { return i }
	}
	return -1
}

find_parent_entity :: proc(
	world: ^shared.World,
	name: string,
	origin: shared.Entity_Origin,
) -> int {
	if name == "" { return -1 }
	for entity in world.entities {
		if entity.alive &&
		   entity.origin == origin &&
		   entity.name == name { return int(entity.id.index) }
	}
	return -1
}

handle_editor_ecs_press :: proc(
	state: ^State,
	world: ^shared.World,
	pressed: shared.Entity,
	position: shared.Vec2,
) {
	entity_index := int(pressed.index)
	for entity_index >= 0 && entity_index < len(world.entities) {
		entity := world.entities[entity_index]
		if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
			component := world.editor_uis[entity.editor_ui_index]
			switch component.role {
				case .Browser_Row, .Browser_Row_Label:
					if editor_select_entity(
						state,
						world,
						component.target,
						0,
					) { state.editor_snapshot_valid = false }
					return
				case .Viewport:
					if !state.editor_gizmo_captures_pointer { state.editor_pick_requested = true; state.editor_pick_position = position }
					return
				case .None,
				     .Root,
				     .Browser_Scroll,
				     .Browser_Header,
				     .Inspector_Header,
				     .Inspector_Scroll,
				     .Inspector_Content,
				     .Inspector_Panel,
				     .Inspector_Table,
				     .Inspector_Cell,
				     .Inspector_Input,
				     .Status:
			}
		}
		layout_index := entity.ui_layout_index
		if layout_index < 0 || layout_index >= len(world.ui_layouts) { return }
		entity_index = find_parent_entity(world, world.ui_layouts[layout_index].parent, .Editor)
	}
}

layout_all :: proc(
	state: ^State,
	world: ^shared.World,
	project_viewport, editor_viewport: Rect,
) -> string {
	state.next_paint_order = 0
	state.split_handle_count = 0
	for i in 0 ..< state.node_count { if state.nodes[i].parent_entity_index < 0 { viewport := project_viewport; if state.nodes[i].origin == .Editor { viewport = editor_viewport }; if err := layout_node(state, world, i, viewport, {}, false, {}, false, {}, false, 0); err != "" { return err } } }
	return ""
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
	node := &state.nodes[node_index]; layout := world.ui_layouts[node.layout_index]
	if node.parent_entity_index < 0 {
		node.rect = {
			layout.position.x + layout.margin.w,
			layout.position.y + layout.margin.x,
			layout.size.x,
			layout.size.y,
		}
	} else if flowed {
		size := layout.size
		if has_flow_size { size = flow_size }
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
			layout.size.x,
			layout.size.y,
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
	panel: shared.UI_Panel_Component
	table: shared.UI_Table_Component
	if is_panel { panel = world.ui_panels[node.panel_index] }
	if is_table { table = world.ui_tables[node.table_index] }
	if is_hstack { stack = world.ui_hstacks[node.hstack_index]; gap = stack.gap }
	if is_vstack { stack = world.ui_vstacks[node.vstack_index]; gap = stack.gap }
	content := Rect {
		node.rect.x + layout.padding.w,
		node.rect.y + layout.padding.x,
		max(node.rect.width - layout.padding.w - layout.padding.y, 0),
		max(node.rect.height - layout.padding.x - layout.padding.z, 0),
	}
	if is_panel && panel.title != "" {
		title_height := min(max(panel.title_height, 0), content.height)
		content.y += title_height
		content.height -= title_height
	}
	child_clip := inherited_clip; child_has_clip := has_inherited_clip
	if is_scroll_area { if child_has_clip { child_clip = rect_intersection(child_clip, content) } else { child_clip = content }; child_has_clip = true }
	scroll_offset := node.scroll_offset
	content_bottom := f32(0)
	children: [MAX_NODES]int
	child_count := 0
	total_margins := f32(0)
	total_weight := f32(0)
	if ((is_hstack || is_vstack) && stack.fill) || is_table {
		for child_index in 0 ..< state.node_count {
			child := &state.nodes[child_index]
			if child.parent_entity_index != int(node.entity.index) { continue }
			children[child_count] = child_index
			child_count += 1
			if is_table { continue }
			child_layout := world.ui_layouts[child.layout_index]
			if is_hstack {
				total_margins += child_layout.margin.w + child_layout.margin.y
			} else {
				total_margins += child_layout.margin.x + child_layout.margin.z
			}
			if !child.split_weight_valid || child.split_parent != node.entity {
				child.split_weight = max(child_layout.size.y, 1)
				if is_hstack { child.split_weight = max(child_layout.size.x, 1) }
				child.split_parent = node.entity
				child.split_weight_valid = true
			}
			total_weight += child.split_weight
		}
	}
	available_main := content.height; if is_hstack { available_main = content.width }
	available_main = max(available_main - total_margins - gap * f32(max(child_count - 1, 0)), 0)
	child_main_sizes: [MAX_NODES]f32
	if (is_hstack || is_vstack) && stack.fill && child_count > 0 {
		resolved: [MAX_NODES]bool
		remaining_size := available_main
		remaining_weight := total_weight
		effective_min := min(stack.min_size, available_main / f32(child_count))
		for _ in 0 ..< child_count {
			resolved_one := false
			for ordinal in 0 ..< child_count {
				if resolved[ordinal] { continue }
				weight := state.nodes[children[ordinal]].split_weight
				proposed := remaining_size / f32(max(child_count, 1))
				if remaining_weight > 0 { proposed = remaining_size * weight / remaining_weight }
				if proposed >= effective_min { continue }
				child_main_sizes[ordinal] = effective_min
				resolved[ordinal] = true
				remaining_size = max(remaining_size - effective_min, 0)
				remaining_weight = max(remaining_weight - weight, 0)
				resolved_one = true
			}
			if !resolved_one { break }
		}
		for ordinal in 0 ..< child_count {
			if resolved[ordinal] { continue }
			weight := state.nodes[children[ordinal]].split_weight
			child_main_sizes[ordinal] = remaining_size / f32(max(child_count, 1))
			if remaining_weight >
			   0 { child_main_sizes[ordinal] = remaining_size * weight / remaining_weight }
		}
	}
	child_ordinal := 0
	table_y, table_row_height := f32(0), f32(0)
	table_columns := max(table.columns, 1)
	table_column_width := max(
		(content.width - table.column_gap * f32(max(table_columns - 1, 0))) / f32(table_columns),
		0,
	)
	for child_index in 0 ..< state.node_count {
		child := &state.nodes[child_index]; if child.parent_entity_index != int(node.entity.index) { continue }
		child_layout := world.ui_layouts[child.layout_index]
		position: shared.Vec2; child_flowed := false; child_size := child_layout.size; has_child_size := false
		if (is_hstack || is_vstack) &&
		   stack.fill { main_size := child_main_sizes[child_ordinal]; if is_hstack { child_size = {main_size, max(content.height - child_layout.margin.x - child_layout.margin.z, 0)} } else { child_size = {max(content.width - child_layout.margin.w - child_layout.margin.y, 0), main_size} }; has_child_size = true }
		if is_table {
			column := child_ordinal % table_columns
			if column == 0 && child_ordinal > 0 {
				table_y += table_row_height + table.row_gap
				table_row_height = 0
			}
			child_size = {
				max(table_column_width - child_layout.margin.w - child_layout.margin.y, 0),
				child_layout.size.y,
			}
			position = {
				content.x +
				f32(column) * (table_column_width + table.column_gap) +
				child_layout.margin.w,
				content.y + table_y + child_layout.margin.x,
			}
			table_row_height = max(
				table_row_height,
				child_layout.margin.x + child_size.y + child_layout.margin.z,
			)
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
			node.rect,
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
		child_ordinal += 1
	}
	if is_table &&
	   child_count > 0 { content_bottom = max(content_bottom, table_y + table_row_height) }
	if is_scroll_area { node.scroll_content_height = max(content.height, content_bottom); node.scroll_max = max(node.scroll_content_height - content.height, 0); node.scroll_target = clamp(node.scroll_target, 0, node.scroll_max); node.scroll_offset = clamp(node.scroll_offset, 0, node.scroll_max) }
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

update_split_interaction :: proc(state: ^State, pointer: Pointer_Input, editor: bool) -> bool {
	for &handle in state.split_handles[:state.split_handle_count] { if handle.editor == editor { handle.hovered = false; handle.active = false } }
	changed := false
	if !pointer.available {
		if state.active_split_handle >= 0 &&
		   state.active_split_editor == editor { state.active_split_handle = -1 }
		if editor { state.editor_split_previous_primary_down = false } else { state.split_previous_primary_down = false }
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
	return changed
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
	if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
		binding := world.editor_uis[entity.editor_ui_index]
		if binding.numeric {
			state.input_original_number, state.input_has_original_number = read_inspector_numeric(
				world,
				binding,
			)
		}
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
		if !finish_input_edit(state, world) { cancel_input_edit(state, world) }
		clear_input_focus(state)
		return
	}
	if state.has_focused_input {
		if state.focused_input == pressed {
			if !finish_input_edit(state, world) {
				state.input_anchor = 0
				state.input_cursor = len(world.ui_inputs[entity.ui_input_index].text)
				return
			}
		} else if !finish_input_edit(state, world) {
			cancel_input_edit(state, world)
		}
	}
	focus_input(state, world, index)
	if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
		binding := world.editor_uis[entity.editor_ui_index]
		node_index := find_node(state, entity.id)
		if binding.numeric &&
		   binding.inspector_axis != .None &&
		   node_index >= 0 &&
		   position.x <= state.nodes[node_index].rect.x + 15 {
			state.input_scrub_armed = state.input_has_original_number
			state.input_scrub_start_x = position.x
			state.input_scrub_start_number = state.input_original_number
		}
	}
}

input_selection :: proc(state: ^State) -> (start, end: int) {
	return min(state.input_anchor, state.input_cursor), max(state.input_anchor, state.input_cursor)
}

replace_input_selection :: proc(
	state: ^State,
	input: ^shared.UI_Input_Component,
	replacement: string,
) -> bool {
	start, end := input_selection(state)
	start = clamp(start, 0, len(input.text))
	end = clamp(end, start, len(input.text))
	parts := [3]string{input.text[:start], replacement, input.text[end:]}
	next, err := strings.concatenate(parts[:])
	if err != nil { return false }
	delete(input.text)
	input.text = next
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

set_inspector_vec3_axis :: proc(
	value: ^shared.Vec3,
	axis: shared.Editor_Inspector_Axis,
	number: f32,
) -> bool {
	if value == nil { return false }
	switch axis {
		case .X:
			value.x = number
		case .Y:
			value.y = number
		case .Z:
			value.z = number
		case .None:
			return false
	}
	return true
}

inspector_numeric_valid :: proc(binding: shared.Editor_UI_Component, number: f32) -> bool {
	if !binding.numeric || math.is_nan(number) || math.is_inf(number) { return false }
	if binding.numeric_has_min && number < binding.numeric_min { return false }
	if binding.numeric_has_max && number > binding.numeric_max { return false }
	return true
}

inspector_target :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	^shared.World_Entity,
	int,
	bool,
) {
	target_index := int(binding.target.index)
	if target_index < 0 || target_index >= len(world.entities) { return nil, -1, false }
	target := &world.entities[target_index]
	if !target.alive || target.id != binding.target { return nil, -1, false }
	return target, target_index, true
}

read_inspector_numeric :: proc(
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) -> (
	f32,
	bool,
) {
	target, target_index, ok := inspector_target(world, binding)
	if !ok { return 0, false }
	axis_value := proc(value: shared.Vec3, axis: shared.Editor_Inspector_Axis) -> (f32, bool) {
		switch axis {
			case .X:
				return value.x, true
			case .Y:
				return value.y, true
			case .Z:
				return value.z, true
			case .None:
				return 0, false
		}
		return 0, false
	}
	#partial switch binding.inspector_field {
		case .Transform_Position, .Transform_Rotation, .Transform_Scale:
			if target.transform_index < 0 ||
			   target.transform_index >= len(world.transforms) { return 0, false }
			value := world.transforms[target.transform_index]
			#partial switch binding.inspector_field {
				case .Transform_Position:
					return axis_value(value.position, binding.inspector_axis)
				case .Transform_Rotation:
					return axis_value(value.rotation, binding.inspector_axis)
				case .Transform_Scale:
					return axis_value(value.scale, binding.inspector_axis)
			}
		case .Camera_Fov, .Camera_Near, .Camera_Far:
			if target.camera_index < 0 ||
			   target.camera_index >= len(world.cameras) { return 0, false }
			value := world.cameras[target.camera_index]
			#partial switch binding.inspector_field {
				case .Camera_Fov:
					return value.fov, true
				case .Camera_Near:
					return value.near, true
				case .Camera_Far:
					return value.far, true
			}
		case .Ambient_Color, .Ambient_Intensity:
			if target.ambient_light_index < 0 ||
			   target.ambient_light_index >= len(world.ambient_lights) { return 0, false }
			value := world.ambient_lights[target.ambient_light_index]
			if binding.inspector_field ==
			   .Ambient_Color { return axis_value(value.color, binding.inspector_axis) }
			return value.intensity, true
		case .Directional_Direction, .Directional_Color, .Directional_Intensity:
			if target.directional_light_index < 0 ||
			   target.directional_light_index >= len(world.directional_lights) { return 0, false }
			value := world.directional_lights[target.directional_light_index]
			#partial switch binding.inspector_field {
				case .Directional_Direction:
					return axis_value(value.direction, binding.inspector_axis)
				case .Directional_Color:
					return axis_value(value.color, binding.inspector_axis)
				case .Directional_Intensity:
					return value.intensity, true
			}
		case .Point_Color, .Point_Intensity, .Point_Range:
			if target.point_light_index < 0 ||
			   target.point_light_index >= len(world.point_lights) { return 0, false }
			value := world.point_lights[target.point_light_index]
			#partial switch binding.inspector_field {
				case .Point_Color:
					return axis_value(value.color, binding.inspector_axis)
				case .Point_Intensity:
					return value.intensity, true
				case .Point_Range:
					return value.range, true
			}
		case .Custom_Vec3:
			if binding.custom_storage_index < 0 ||
			   binding.custom_storage_index >= len(world.custom_components) { return 0, false }
			storage := &world.custom_components[binding.custom_storage_index]
			for &component in storage.components {
				if component.entity_index != target_index ||
				   binding.custom_field_index < 0 ||
				   binding.custom_field_index >= len(component.vec3_fields) { continue }
				return axis_value(
					component.vec3_fields[binding.custom_field_index].value,
					binding.inspector_axis,
				)
			}
	}
	return 0, false
}

write_inspector_numeric :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	number: f32,
) -> bool {
	if !inspector_numeric_valid(binding, number) { return false }
	target, target_index, ok := inspector_target(world, binding)
	if !ok { return false }
	written := false
	#partial switch binding.inspector_field {
		case .Transform_Position, .Transform_Rotation, .Transform_Scale:
			if target.transform_index < 0 ||
			   target.transform_index >= len(world.transforms) { return false }
			#partial switch binding.inspector_field {
				case .Transform_Position:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].position,
						binding.inspector_axis,
						number,
					)
				case .Transform_Rotation:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].rotation,
						binding.inspector_axis,
						number,
					)
				case .Transform_Scale:
					written = set_inspector_vec3_axis(
						&world.transforms[target.transform_index].scale,
						binding.inspector_axis,
						number,
					)
			}
		case .Camera_Fov, .Camera_Near, .Camera_Far:
			if target.camera_index < 0 ||
			   target.camera_index >= len(world.cameras) { return false }
			camera := &world.cameras[target.camera_index]
			if binding.inspector_field == .Camera_Near && number >= camera.far { return false }
			if binding.inspector_field == .Camera_Far && number <= camera.near { return false }
			#partial switch binding.inspector_field {
				case .Camera_Fov:
					camera.fov = number
				case .Camera_Near:
					camera.near = number
				case .Camera_Far:
					camera.far = number
			}
			written = true
		case .Ambient_Color, .Ambient_Intensity:
			if target.ambient_light_index < 0 ||
			   target.ambient_light_index >= len(world.ambient_lights) { return false }
			if binding.inspector_field == .Ambient_Color {
				written = set_inspector_vec3_axis(
					&world.ambient_lights[target.ambient_light_index].color,
					binding.inspector_axis,
					number,
				)
			} else {world.ambient_lights[target.ambient_light_index].intensity = number
				written = true}
		case .Directional_Direction, .Directional_Color, .Directional_Intensity:
			if target.directional_light_index < 0 ||
			   target.directional_light_index >= len(world.directional_lights) { return false }
			#partial switch binding.inspector_field {
				case .Directional_Direction:
					written = set_inspector_vec3_axis(
						&world.directional_lights[target.directional_light_index].direction,
						binding.inspector_axis,
						number,
					)
				case .Directional_Color:
					written = set_inspector_vec3_axis(
						&world.directional_lights[target.directional_light_index].color,
						binding.inspector_axis,
						number,
					)
				case .Directional_Intensity:
					world.directional_lights[target.directional_light_index].intensity = number
					written = true
			}
		case .Point_Color, .Point_Intensity, .Point_Range:
			if target.point_light_index < 0 ||
			   target.point_light_index >= len(world.point_lights) { return false }
			#partial switch binding.inspector_field {
				case .Point_Color:
					written = set_inspector_vec3_axis(
						&world.point_lights[target.point_light_index].color,
						binding.inspector_axis,
						number,
					)
				case .Point_Intensity:
					world.point_lights[target.point_light_index].intensity = number; written = true
				case .Point_Range:
					world.point_lights[target.point_light_index].range = number; written = true
			}
		case .Custom_Vec3:
			if binding.custom_storage_index < 0 ||
			   binding.custom_storage_index >= len(world.custom_components) { return false }
			storage := &world.custom_components[binding.custom_storage_index]
			for &component in storage.components {
				if component.entity_index != target_index ||
				   binding.custom_field_index < 0 ||
				   binding.custom_field_index >= len(component.vec3_fields) { continue }
				written = set_inspector_vec3_axis(
					&component.vec3_fields[binding.custom_field_index].value,
					binding.inspector_axis,
					number,
				)
				break
			}
	}
	if written && state != nil { state.editor_snapshot_valid = false }
	return written
}

apply_inspector_input :: proc(state: ^State, world: ^shared.World, entity_index: int) -> bool {
	if entity_index < 0 || entity_index >= len(world.entities) { return false }
	entity := world.entities[entity_index]
	if entity.origin != .Editor ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) ||
	   entity.ui_input_index < 0 ||
	   entity.ui_input_index >= len(world.ui_inputs) { return false }
	binding := world.editor_uis[entity.editor_ui_index]
	number, ok := strconv.parse_f32(
		strings.trim_space(world.ui_inputs[entity.ui_input_index].text),
	)
	if !ok { return false }
	return write_inspector_numeric(state, world, binding, number)
}

editor_history_push :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
	before, after: f32,
) {
	if state == nil || world == nil || before == after { return }
	target, _, found := inspector_target(world, binding)
	if !found { return }
	command := Editor_Edit_Command {
		target = binding.target,
		component_revision = target.component_revision,
		field = binding.inspector_field,
		axis = binding.inspector_axis,
		custom_storage_index = binding.custom_storage_index,
		custom_field_index = binding.custom_field_index,
		before = before,
		after = after,
	}
	state.editor_history_count = state.editor_history_cursor
	if state.editor_history_count >= EDITOR_HISTORY_CAPACITY {
		copy(state.editor_history[0:EDITOR_HISTORY_CAPACITY - 1], state.editor_history[1:])
		state.editor_history_count = EDITOR_HISTORY_CAPACITY - 1
		state.editor_history_cursor = state.editor_history_count
	}
	state.editor_history[state.editor_history_count] = command
	state.editor_history_count += 1
	state.editor_history_cursor = state.editor_history_count
}

editor_history_remove :: proc(state: ^State, index: int) {
	if state == nil || index < 0 || index >= state.editor_history_count { return }
	if index + 1 < state.editor_history_count {
		copy(
			state.editor_history[index:state.editor_history_count - 1],
			state.editor_history[index + 1:state.editor_history_count],
		)
	}
	state.editor_history_count -= 1
	if state.editor_history_cursor > index { state.editor_history_cursor -= 1 }
	state.editor_history_cursor = clamp(state.editor_history_cursor, 0, state.editor_history_count)
}

editor_history_apply :: proc(state: ^State, world: ^shared.World, redo: bool) -> bool {
	if state == nil || world == nil { return false }
	for {
		index := state.editor_history_cursor
		if !redo { index -= 1 }
		if index < 0 || index >= state.editor_history_count { return false }
		command := state.editor_history[index]
		binding := shared.Editor_UI_Component {
			target = command.target,
			inspector_field = command.field,
			inspector_axis = command.axis,
			custom_storage_index = command.custom_storage_index,
			custom_field_index = command.custom_field_index,
			numeric = true,
		}
		target, _, found := inspector_target(world, binding)
		value := command.before
		if redo { value = command.after }
		if found &&
		   target.component_revision == command.component_revision &&
		   write_inspector_numeric(state, world, binding, value) {
			if redo { state.editor_history_cursor = index + 1 } else { state.editor_history_cursor = index }
			return true
		}
		editor_history_remove(state, index)
	}
}

focused_input_binding :: proc(
	state: ^State,
	world: ^shared.World,
) -> (
	shared.Editor_UI_Component,
	int,
	bool,
) {
	if state == nil || world == nil || !state.has_focused_input { return {}, -1, false }
	entity_index := int(state.focused_input.index)
	if entity_index < 0 || entity_index >= len(world.entities) { return {}, -1, false }
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != state.focused_input ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) { return {}, -1, false }
	return world.editor_uis[entity.editor_ui_index], entity_index, true
}

validate_focused_editor_input :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || !state.has_focused_input || !state.focused_input_editor {
		return
	}
	binding, input_entity, found := focused_input_binding(state, world)
	available := found && !ui_entity_or_ancestor_hidden(world, input_entity)
	if available && binding.role == .Inspector_Input {
		_, _, available = inspector_target(world, binding)
		if available && binding.numeric {
			_, available = read_inspector_numeric(world, binding)
		}
	}
	if !available { clear_input_focus(state) }
}

finish_input_edit :: proc(state: ^State, world: ^shared.World) -> bool {
	binding, entity_index, found := focused_input_binding(state, world)
	if !found || !binding.numeric { return true }
	entity := world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) { return false }
	input := &world.ui_inputs[entity.ui_input_index]
	number, ok := strconv.parse_f32(strings.trim_space(input.text))
	if !ok || !inspector_numeric_valid(binding, number) {
		state.input_valid = false
		return false
	}
	if !write_inspector_numeric(state, world, binding, number) {
		state.input_valid = false
		return false
	}
	if state.input_has_original_number {
		editor_history_push(state, world, binding, state.input_original_number, number)
	}
	state.input_original_number = number
	state.input_has_original_number = true
	delete(state.input_original_text)
	state.input_original_text, _ = strings.clone(input.text)
	state.input_valid = true
	return true
}

cancel_input_edit :: proc(state: ^State, world: ^shared.World) {
	binding, entity_index, found := focused_input_binding(state, world)
	if !found { return }
	entity := world.entities[entity_index]
	if entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs) {
		input := &world.ui_inputs[entity.ui_input_index]
		delete(input.text)
		input.text, _ = strings.clone(state.input_original_text)
		state.input_cursor = len(input.text)
		state.input_anchor = 0
	}
	if binding.numeric && state.input_has_original_number {
		_ = write_inspector_numeric(state, world, binding, state.input_original_number)
	}
	state.input_valid = true
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

set_numeric_input_text :: proc(state: ^State, input: ^shared.UI_Input_Component, number: f32) {
	if input == nil { return }
	formatted := fmt.tprintf("%.3f", number)
	trimmed := strings.trim_right(formatted, "0")
	if strings.has_suffix(trimmed, ".") { trimmed = trimmed[:len(trimmed) - 1] }
	delete(input.text)
	input.text, _ = strings.clone(trimmed)
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
	binding, _, has_binding := focused_input_binding(state, world)
	numeric := has_binding && binding.numeric
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
				edited = replace_input_selection(state, input, "") || edited
			}
		}
		start, end = input_selection(state)
		if keyboard.delete_forward {
			if start != end || end < len(input.text) {
				if start == end { state.input_cursor = end + 1 }
				edited = replace_input_selection(state, input, "") || edited
			}
		}
		if keyboard.text != "" {
			filtered := single_line_ascii(keyboard.text)
			if filtered != "" {
				edited = replace_input_selection(state, input, filtered) || edited
			}
			delete(filtered)
		}
		if numeric && (keyboard.up || keyboard.down) {
			current, ok := strconv.parse_f32(strings.trim_space(input.text))
			if !ok || !inspector_numeric_valid(binding, current) {
				current, ok = read_inspector_numeric(world, binding)
			}
			if ok {
				direction := f32(1)
				if keyboard.down { direction = -1 }
				next := current + direction * binding.numeric_step * numeric_modifier(keyboard)
				if binding.numeric_has_min { next = max(next, binding.numeric_min) }
				if binding.numeric_has_max { next = min(next, binding.numeric_max) }
				set_numeric_input_text(state, input, next)
				edited = true
			}
		}
		if edited {
			if numeric {
				state.input_valid = apply_inspector_input(state, world, entity_index)
			} else {
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
		if finish_input_edit(state, world) { move_input_focus(state, world, keyboard.shift) }
	}
}

update_input_scrub :: proc(
	state: ^State,
	world: ^shared.World,
	pointer: Pointer_Input,
	keyboard: Keyboard_Input,
) {
	if state == nil || !state.input_scrub_armed { return }
	binding, entity_index, found := focused_input_binding(state, world)
	if !found || !binding.numeric || binding.inspector_axis == .None {
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
	next :=
		state.input_scrub_start_number +
		delta / 4 * binding.numeric_step * numeric_modifier(keyboard)
	if binding.numeric_has_min { next = max(next, binding.numeric_min) }
	if binding.numeric_has_max { next = min(next, binding.numeric_max) }
	entity := world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) { return }
	set_numeric_input_text(state, &world.ui_inputs[entity.ui_input_index], next)
	state.input_valid = apply_inspector_input(state, world, entity_index)
}

mark_interaction_chain :: proc(state: ^State, node_index: int, active: bool) {
	index := node_index
	for index >= 0 {
		if active { state.nodes[index].active = true } else { state.nodes[index].hovered = true }
		index = find_node_by_entity_index(state, state.nodes[index].parent_entity_index)
	}
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

paint_node :: proc(state: ^State, world: ^shared.World, node_index, depth: int) -> string {
	if depth > MAX_NODES { return "UI hierarchy contains a cycle" }
	node := &state.nodes[node_index]; layout := world.ui_layouts[node.layout_index]
	if node.has_clip {
		visible := rect_intersection(node.rect, node.clip)
		if visible.width <= 0 || visible.height <= 0 { return "" }
	}
	paint_start := state.paint_count
	background := layout.background
	border_color := layout.border_color
	border_width := layout.border_width
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
			border_color = {0.92, 0.24, 0.28, 1}
			border_width = max(border_width, 1.5)
		} else if input.focus_border_color.w > 0 {
			border_color = input.focus_border_color
			border_width = max(border_width, 1)
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
			text_rect := Rect {
				title_rect.x + 10,
				title_rect.y + max((title_height - panel.title_size * 1.25) * 0.5, 0),
				max(title_rect.width - 20, 0),
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
	if node.text_index >= 0 &&
	   node.text_index <
		   len(
			   world.ui_texts,
		   ) { text := world.ui_texts[node.text_index]; if err := append_text(state, text.text, text.color, text.size, node.rect, layout.padding); err != "" { return err } }
	if node.input_index >= 0 && node.input_index < len(world.ui_inputs) {
		if err := append_input(
			state,
			world,
			world.ui_inputs[node.input_index],
			node^,
			layout.padding,
		); err != "" { return err }
	}
	if node.button_index >= 0 &&
	   node.button_index <
		   len(
			   world.ui_buttons,
		   ) { button := world.ui_buttons[node.button_index]; color := button.color; if node.active && button.active_color.w > 0 { color = button.active_color } else if node.hovered && button.hover_color.w > 0 { color = button.hover_color }; if err := append_centered_text(state, button.text, color, button.size, node.rect, layout.padding); err != "" { return err } }
	apply_paint_clip(state, paint_start, state.paint_count, node.clip, node.has_clip)
	for child_index in 0 ..< state.node_count { if state.nodes[child_index].parent_entity_index == int(node.entity.index) { if err := paint_node(state, world, child_index, depth + 1); err != "" { return err } } }
	if node.scroll_area_index >= 0 &&
	   node.scroll_area_index < len(world.ui_scroll_areas) &&
	   node.scroll_max > 0 {
		track := Rect {
			node.rect.x + node.rect.width - 7,
			node.rect.y + 5,
			3,
			max(node.rect.height - 10, 0),
		}
		thumb_height := max(
			track.height * track.height / max(node.scroll_content_height, track.height),
			18,
		)
		thumb_y :=
			track.y + (track.height - thumb_height) * node.scroll_offset / max(node.scroll_max, 1)
		start := state.paint_count
		if err := append_paint(
			state,
			{kind = .Panel, rect = track, color = {0.08, 0.09, 0.11, 0.78}, corner_radius = 1.5},
		); err != "" { return err }
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {track.x, thumb_y, track.width, thumb_height},
				color = {0.34, 0.37, 0.42, 0.92},
				corner_radius = 1.5,
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
			9 * scale,
			{label_center.x - 7 * scale, label_center.y - 7 * scale, 14 * scale, 14 * scale},
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
	indices := [14]int {
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
		entity.ui_text_index,
	}
	for index in indices {
		if index >= 0 { count += 1 }
	}
	if entity.ui_hstack_index >= 0 { count += 1 }
	if entity.ui_vstack_index >= 0 { count += 1 }
	if entity.ui_button_index >= 0 { count += 1 }
	if entity.ui_input_index >= 0 { count += 1 }
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
) -> string {
	x := rect.x + padding.w; baseline := rect.y + padding.x + FONT_ASCENDER * size
	return append_text_at(state, text, color, size, x, baseline, rect.x + padding.w)
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
		x += state.font.glyphs[code - FONT_FIRST_CHAR].advance * size
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
	axis := shared.Editor_Inspector_Axis.None
	if world != nil {
		entity_index := int(node.entity.index)
		if entity_index >= 0 && entity_index < len(world.entities) {
			entity := world.entities[entity_index]
			if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
				axis = world.editor_uis[entity.editor_ui_index].inspector_axis
			}
		}
	}
	axis_content := content
	axis_width := f32(0)
	if axis != .None {
		axis_width = min(f32(13), content.width)
		content.x += axis_width + 2
		content.width = max(content.width - axis_width - 2, 0)
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
	axis_start := state.paint_count
	if axis != .None {
		axis_text := "X"
		axis_color := shared.Vec4{0.92, 0.30, 0.32, 1}
		if axis == .Y { axis_text = "Y"; axis_color = {0.34, 0.82, 0.42, 1} }
		if axis == .Z { axis_text = "Z"; axis_color = {0.34, 0.55, 0.96, 1} }
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {axis_content.x, axis_content.y, axis_width, axis_content.height},
				color = {axis_color.x, axis_color.y, axis_color.z, 0.12},
				corner_radius = 2,
			},
		); err != "" { return err }
		if err := append_text_at(
			state,
			axis_text,
			axis_color,
			max(input.size - 1, 7),
			axis_content.x + 3,
			axis_content.y +
			max((axis_content.height - input.size) * 0.5, 0) +
			FONT_ASCENDER * input.size,
			axis_content.x + 3,
		); err != "" { return err }
	}
	axis_clip := axis_content
	if node.has_clip { axis_clip = rect_intersection(axis_clip, node.clip) }
	apply_paint_clip(state, axis_start, state.paint_count, axis_clip, true)
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
				corner_radius = 2,
			},
		); err != "" { return err }
	}
	baseline :=
		content.y + max((content.height - input.size) * 0.5, 0) + FONT_ASCENDER * input.size
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
		if err := append_paint(
			state,
			{
				kind = .Panel,
				rect = {caret_x, content.y + 2, 1, max(content.height - 4, 0)},
				color = input.color,
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
	x := rect.x; baseline := rect.y + FONT_ASCENDER * size
	for character in text {
		code := int(
			character,
		); if code < FONT_FIRST_CHAR || code >= FONT_FIRST_CHAR + FONT_CHAR_COUNT { code = int('?') }; glyph := state.font.glyphs[code - FONT_FIRST_CHAR]
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
) -> string {
	bounds, has_ink := measure_text_ink(state, text, size)
	if !has_ink { return "" }
	content := Rect {
		rect.x + padding.w,
		rect.y + padding.x,
		rect.width - padding.w - padding.y,
		rect.height - padding.x - padding.z,
	}
	x := content.x + (content.width - bounds.width) * 0.5 - bounds.x
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
		glyph := state.font.glyphs[code - FONT_FIRST_CHAR]
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
		glyph := state.font.glyphs[code - FONT_FIRST_CHAR]
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

append_paint :: proc(state: ^State, command: Paint_Command) -> string {if state.paint_count >=
	   MAX_PAINT_COMMANDS { return "too many UI paint commands" }
	state.paint[state.paint_count] = command
	state.paint_count += 1
	return ""}
