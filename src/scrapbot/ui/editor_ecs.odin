package ui

import ecs "../ecs"
import shared "../shared"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

EDITOR_UI_ROOT_NAME :: "__scrapbot_editor_root"
EDITOR_UI_TOP_NAME :: "__scrapbot_editor_top"
EDITOR_UI_TRANSPORT_NAME :: "__scrapbot_editor_transport"
EDITOR_UI_WORKSPACE_NAME :: "__scrapbot_editor_workspace"
EDITOR_UI_LEFT_NAME :: "__scrapbot_editor_left"
EDITOR_UI_LEFT_CONTENT_NAME :: "__scrapbot_editor_left_content"
EDITOR_UI_SYSTEMS_NAME :: "__scrapbot_editor_systems"
EDITOR_UI_SCENE_NAME :: "__scrapbot_editor_scene"
EDITOR_UI_VIEWPORT_NAME :: "__scrapbot_editor_viewport"
EDITOR_UI_RIGHT_NAME :: "__scrapbot_editor_right"
EDITOR_UI_RIGHT_CONTENT_NAME :: "__scrapbot_editor_right_content"
EDITOR_UI_INSPECTOR_HEADER_NAME :: "__scrapbot_editor_inspector_header"
EDITOR_UI_STATUS_NAME :: "__scrapbot_editor_status"
EDITOR_SIDEBAR_PADDING :: f32(10)
EDITOR_SIDEBAR_SECTION_GAP :: f32(6)
EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT :: f32(618)
EDITOR_SECTION_TITLE_HEIGHT :: f32(34)
EDITOR_SECTION_BACKGROUND :: shared.Vec4{0.019, 0.024, 0.032, 1}
EDITOR_LIST_BACKGROUND :: shared.Vec4{0.010, 0.014, 0.020, 1}
EDITOR_SECTION_TITLE_BACKGROUND :: shared.Vec4{0.027, 0.035, 0.046, 1}
EDITOR_SECTION_BORDER :: shared.Vec4{0.055, 0.067, 0.088, 1}
EDITOR_SECTION_TITLE_COLOR :: shared.Vec4{0.86, 0.88, 0.92, 1}
EDITOR_RUNTIME_ENTITY_COLOR :: shared.Vec4{0.42, 0.45, 0.51, 1}
EDITOR_SECTION_RADIUS :: f32(5)

editor_ui_entity :: proc(
	world: ^shared.World,
	role: shared.Editor_UI_Role,
	slot: int = 0,
) -> (
	int,
	bool,
) {
	for component, component_index in world.editor_uis {
		if component.role != role || component.slot != slot { continue }
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive ||
		   entity.origin != .Editor ||
		   entity.editor_ui_index != component_index { continue }
		return component.entity_index, true
	}
	return -1, false
}

editor_ui_handle_activation :: proc(
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
					if editor_select_entity(state, world, component.target, 0) {
						state.editor_snapshot_valid = false
					}
					return
				case .Transport_Play:
					editor_play(state)
					return
				case .Transport_Stop:
					editor_stop(state)
					return
				case .Transport_Step:
					editor_step(state)
					return
				case .Viewport:
					if !state.editor_gizmo_captures_pointer {
						state.editor_pick_requested = true
						state.editor_pick_position = position
					}
					return
				case .None,
				     .Root,
				     .Systems_Scroll,
				     .Systems_Row,
				     .Systems_Name,
				     .Systems_Time,
				     .Systems_Origin,
				     .Browser_Scroll,
				     .Inspector_Header,
				     .Inspector_Scroll,
				     .Inspector_Content,
				     .Inspector_Panel,
				     .Inspector_Table,
				     .Inspector_Cell,
				     .Inspector_Input,
				     .Inspector_Checkbox,
				     .Status:
			}
		}
		layout_index := entity.ui_layout_index
		if layout_index < 0 || layout_index >= len(world.ui_layouts) {
			return
		}
		entity_index = find_parent_entity(world, world.ui_layouts[layout_index].parent, .Editor)
	}
}

editor_ui_handle_checkbox_change :: proc(
	state: ^State,
	world: ^shared.World,
	changed: shared.Entity,
) {
	if state == nil || world == nil { return }
	entity_index := int(changed.index)
	if entity_index < 0 || entity_index >= len(world.entities) { return }
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != changed ||
	   entity.origin != .Editor ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) ||
	   entity.ui_checkbox_index < 0 ||
	   entity.ui_checkbox_index >= len(world.ui_checkboxes) { return }
	binding := world.editor_uis[entity.editor_ui_index]
	if binding.role != .Inspector_Checkbox { return }
	checkbox := world.ui_checkboxes[entity.ui_checkbox_index]
	if write_inspector_bool(state, world, binding, checkbox.checked) { return }
	if reflected, ok := read_inspector_bool(world, binding); ok {
		checkbox.checked = reflected
		_ = ecs.set_ui_checkbox(world, entity_index, checkbox)
	}
}

editor_ui_handle_panel_change :: proc(
	state: ^State,
	world: ^shared.World,
	changed: shared.Entity,
) {
	if state == nil || world == nil { return }
	entity_index := int(changed.index)
	if entity_index < 0 || entity_index >= len(world.entities) { return }
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.id != changed ||
	   entity.origin != .Editor ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) { return }
	if world.editor_uis[entity.editor_ui_index].role == .Inspector_Panel {
		refresh_editor_ecs_snapshot(state, world)
	}
}

editor_ui_create_box :: proc(
	world: ^shared.World,
	name: string,
	parent: string,
	role: shared.Editor_UI_Role,
	layout: shared.UI_Layout_Component,
	slot: int = 0,
) -> int {
	layout_value := layout
	if parent != "" {
		layout_value.parent = shared.entity_uuid_from_engine_name(parent)
	}
	entity_uuid := shared.entity_uuid_from_engine_name(name)
	entity_index, created := ecs.create_world_entity(world, name, entity_uuid, .Editor, false)
	if !created {
		return -1
	}
	role_index := len(world.editor_uis)
	append(
		&world.editor_uis,
		shared.Editor_UI_Component {
			entity_index = entity_index,
			role = role,
			slot = slot,
			custom_storage_index = -1,
			custom_field_index = -1,
		},
	)
	world.entities[entity_index].editor_ui_index = role_index
	_ = ecs.set_ui_layout(world, entity_index, layout_value)
	return entity_index
}

editor_ui_add_text :: proc(
	world: ^shared.World,
	entity_index: int,
	text: string,
	color: shared.Vec4,
	size: f32,
) {
	_ = ecs.set_ui_text(world, entity_index, {text = text, color = color, size = size})
}

editor_ui_add_button :: proc(world: ^shared.World, entity_index: int) {
	value := shared.ui_button_default()
	value.text = " "
	value.color = {0, 0, 0, 0}
	value.size = 1
	value.hover_background = {0.020, 0.027, 0.036, 1}
	value.active_background = {0.030, 0.041, 0.054, 1}
	_ = ecs.set_ui_button(world, entity_index, value)
}

editor_ui_create_transport_button :: proc(
	world: ^shared.World,
	name, parent, label: string,
	role: shared.Editor_UI_Role,
) -> int {
	button := editor_ui_create_box(
		world,
		name,
		parent,
		role,
		{
			size = {58, 30},
			background = {0.017, 0.022, 0.030, 1},
			border_color = {0.055, 0.067, 0.088, 1},
			border_width = 1,
			corner_radius = 4,
		},
	)
	editor_ui_add_button(world, button)
	value := world.ui_buttons[world.entities[button].ui_button_index]
	value.text = label
	value.color = {0.64, 0.67, 0.73, 1}
	value.size = EDITOR_TEXT_SIZE
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_add_input :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Input_Component,
) {
	_ = ecs.set_ui_input(world, entity_index, value)
}

editor_ui_add_checkbox :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Checkbox_Component,
) {
	_ = ecs.set_ui_checkbox(world, entity_index, value)
}

editor_ui_add_hstack :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Stack_Component,
) {
	_ = ecs.set_ui_hstack(world, entity_index, value)
}

editor_ui_add_vstack :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Stack_Component,
) {
	_ = ecs.set_ui_vstack(world, entity_index, value)
}

editor_ui_add_scroll :: proc(world: ^shared.World, entity_index: int) {
	value := shared.ui_scroll_area_default()
	value.scroll_speed = EDITOR_SCROLL_SPEED
	value.smoothness = EDITOR_SCROLL_SMOOTHNESS
	_ = ecs.set_ui_scroll_area(world, entity_index, value)
}

editor_ui_add_panel :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Panel_Component,
) {
	_ = ecs.set_ui_panel(world, entity_index, value)
}

editor_ui_section_layout :: proc(size: shared.Vec2) -> shared.UI_Layout_Component {
	return {
		size = size,
		padding = {10, 12, 12, 12},
		background = EDITOR_SECTION_BACKGROUND,
		border_color = EDITOR_SECTION_BORDER,
		border_width = 1,
		corner_radius = EDITOR_SECTION_RADIUS,
		fill_width = true,
	}
}

editor_ui_list_section_layout :: proc(size: shared.Vec2) -> shared.UI_Layout_Component {
	return {
		size = size,
		background = EDITOR_LIST_BACKGROUND,
		border_color = EDITOR_SECTION_BORDER,
		border_width = 1,
		corner_radius = EDITOR_SECTION_RADIUS,
		fill_width = true,
	}
}

editor_ui_add_section_panel :: proc(world: ^shared.World, entity_index: int, title: string) {
	value := shared.ui_panel_default()
	value.title = title
	value.title_color = EDITOR_SECTION_TITLE_COLOR
	value.title_background = EDITOR_SECTION_TITLE_BACKGROUND
	value.title_size = EDITOR_TEXT_SIZE
	value.title_height = EDITOR_SECTION_TITLE_HEIGHT
	value.collapsible = true
	editor_ui_add_panel(world, entity_index, value)
}

editor_ui_add_table :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Table_Component,
) {
	_ = ecs.set_ui_table(world, entity_index, value)
}

editor_ui_add_list :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_List_Component,
) {
	_ = ecs.set_ui_list(world, entity_index, value)
}

editor_ui_set_text :: proc(world: ^shared.World, entity_index: int, value: string) {
	_ = ecs.set_ui_text_value(world, entity_index, value)
}

editor_ui_set_parent :: proc(world: ^shared.World, entity_index: int, value: string) {
	parent: shared.Entity_UUID
	if value != "" {
		parent = shared.entity_uuid_from_engine_name(value)
	}
	_ = ecs.set_ui_parent(world, entity_index, parent)
}

editor_ui_set_hidden :: proc(world: ^shared.World, entity_index: int, hidden: bool) {
	_ = ecs.set_ui_hidden(world, entity_index, hidden)
}

editor_ui_set_panel_title :: proc(world: ^shared.World, entity_index: int, value: string) {
	_ = ecs.set_ui_panel_title(world, entity_index, value)
}

editor_ui_create_shell :: proc(world: ^shared.World) {
	if _, found := editor_ui_entity(world, .Root); found { return }
	text := shared.Vec4{0.82, 0.85, 0.90, 1}
	muted := shared.Vec4{0.42, 0.45, 0.51, 1}
	mint := shared.Vec4{0.06, 0.72, 0.63, 1}
	void := shared.Vec4{0.004, 0.005, 0.007, 1}
	rule := shared.Vec4{0.055, 0.067, 0.088, 1}
	root := editor_ui_create_box(
		world,
		EDITOR_UI_ROOT_NAME,
		"",
		.Root,
		{size = {1280, 720}, fill_width = true, fill_height = true},
	)
	editor_ui_add_vstack(world, root, {fill = true})
	top := editor_ui_create_box(
		world,
		EDITOR_UI_TOP_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{
			size = {1280, EDITOR_TOP_BAR_HEIGHT},
			fixed_in_fill = true,
			padding = {11, 14, 11, 14},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_hstack(world, top, {gap = 16})
	brand := editor_ui_create_box(
		world,
		"__scrapbot_editor_brand",
		EDITOR_UI_TOP_NAME,
		.None,
		{size = {340, 30}},
	)
	editor_ui_add_text(world, brand, "SCRAPBOT", text, EDITOR_TEXT_SIZE)
	transport := editor_ui_create_box(
		world,
		EDITOR_UI_TRANSPORT_NAME,
		EDITOR_UI_TOP_NAME,
		.None,
		{size = {182, 30}},
	)
	editor_ui_add_hstack(world, transport, {gap = 4})
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_play",
		EDITOR_UI_TRANSPORT_NAME,
		"PLAY",
		.Transport_Play,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_stop",
		EDITOR_UI_TRANSPORT_NAME,
		"PAUSE",
		.Transport_Stop,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_step",
		EDITOR_UI_TRANSPORT_NAME,
		"STEP",
		.Transport_Step,
	)
	workspace := editor_ui_create_box(
		world,
		EDITOR_UI_WORKSPACE_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{size = {1280, 638}},
	)
	editor_ui_add_hstack(
		world,
		workspace,
		{gap = 1, fill = true, draggable = true, min_size = EDITOR_SIDEBAR_MIN_WIDTH},
	)
	left := editor_ui_create_box(
		world,
		EDITOR_UI_LEFT_NAME,
		EDITOR_UI_WORKSPACE_NAME,
		.None,
		{
			size = {EDITOR_LEFT_SIDEBAR_WIDTH, 638},
			padding = {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_scroll(world, left)
	left_content := editor_ui_create_box(
		world,
		EDITOR_UI_LEFT_CONTENT_NAME,
		EDITOR_UI_LEFT_NAME,
		.None,
		{
			size = {
				EDITOR_LEFT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
		},
	)
	editor_ui_add_vstack(
		world,
		left_content,
		{gap = EDITOR_SIDEBAR_SECTION_GAP, fill = true, draggable = true, min_size = 160},
	)
	systems := editor_ui_create_box(
		world,
		EDITOR_UI_SYSTEMS_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.Systems_Scroll,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 178}),
	)
	editor_ui_add_section_panel(world, systems, "SYSTEMS / 0")
	editor_ui_add_list(
		world,
		systems,
		{
			gap = 2,
			selection_background = {0.040, 0.088, 0.098, 1},
			hover_background = {0.028, 0.038, 0.050, 1},
			active_background = {0.050, 0.067, 0.088, 1},
		},
	)
	editor_ui_add_scroll(world, systems)
	scene := editor_ui_create_box(
		world,
		EDITOR_UI_SCENE_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.Browser_Scroll,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 434}),
	)
	editor_ui_add_section_panel(world, scene, "SCENE")
	editor_ui_add_list(
		world,
		scene,
		{
			selection_background = {0.040, 0.088, 0.098, 1},
			hover_background = {0.028, 0.038, 0.050, 1},
			active_background = {0.050, 0.067, 0.088, 1},
		},
	)
	editor_ui_add_scroll(world, scene)

	_ = editor_ui_create_box(
		world,
		EDITOR_UI_VIEWPORT_NAME,
		EDITOR_UI_WORKSPACE_NAME,
		.Viewport,
		{size = {660, 638}, border_color = rule, border_width = 1},
	)

	right := editor_ui_create_box(
		world,
		EDITOR_UI_RIGHT_NAME,
		EDITOR_UI_WORKSPACE_NAME,
		.Inspector_Scroll,
		{
			size = {EDITOR_RIGHT_SIDEBAR_WIDTH, 638},
			padding = {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_scroll(world, right)
	right_content := editor_ui_create_box(
		world,
		EDITOR_UI_RIGHT_CONTENT_NAME,
		EDITOR_UI_RIGHT_NAME,
		.Inspector_Content,
		{
			size = {
				EDITOR_RIGHT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
			fit_content_height = true,
		},
	)
	editor_ui_add_vstack(world, right_content, {gap = INSPECTOR_PANEL_GAP})
	right_header := editor_ui_create_box(
		world,
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		EDITOR_UI_RIGHT_CONTENT_NAME,
		.None,
		editor_ui_section_layout({EDITOR_RIGHT_SIDEBAR_WIDTH, 110}),
	)
	editor_ui_add_section_panel(world, right_header, "INSPECTOR")
	inspector_header := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_identity",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Header,
		{position = {0, 34}, size = {2000, 58}},
	)
	editor_ui_add_text(
		world,
		inspector_header,
		"Select an entity to inspect",
		muted,
		EDITOR_TEXT_SIZE,
	)

	status := editor_ui_create_box(
		world,
		EDITOR_UI_STATUS_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{
			size = {1280, EDITOR_STATUS_BAR_HEIGHT},
			fixed_in_fill = true,
			padding = {6, 14, 6, 14},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_hstack(world, status, {gap = 8})
	status_text := editor_ui_create_box(
		world,
		"__scrapbot_editor_status_text",
		EDITOR_UI_STATUS_NAME,
		.Status,
		{size = {300, 18}},
	)
	editor_ui_add_text(world, status_text, "RUNNING", mint, EDITOR_TEXT_SIZE)
}

editor_ui_ensure_row :: proc(world: ^shared.World, slot: int) -> (int, int) {
	row, row_found := editor_ui_entity(world, .Browser_Row, slot)
	label, label_found := editor_ui_entity(world, .Browser_Row_Label, slot)
	if row_found && label_found { return row, label }
	row_name := fmt.tprintf("__scrapbot_editor_row_%d", slot)
	label_name := fmt.tprintf("__scrapbot_editor_row_label_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_SCENE_NAME,
		.Browser_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}},
		slot,
	)
	label = editor_ui_create_box(
		world,
		label_name,
		row_name,
		.Browser_Row_Label,
		{position = {11, 0}, size = {1900, EDITOR_ENTITY_ROW_HEIGHT}, padding = {8, 0, 6, 0}},
		slot,
	)
	editor_ui_add_text(world, label, "", {0.82, 0.84, 0.88, 1}, EDITOR_TEXT_SIZE)
	return row, label
}

SYSTEM_PROFILE_CELL_HEIGHT :: f32(26)
SYSTEM_PROFILE_BAR_MAX_NANOSECONDS :: f64(10_000_000)

system_profile_origin_color :: proc(kind: shared.System_Profile_Kind) -> shared.Vec4 {
	switch kind {
		case .Engine:
			return {0.22, 0.78, 0.69, 1}
		case .Project_Odin:
			return {0.35, 0.62, 0.94, 1}
		case .Luau:
			return {0.91, 0.61, 0.24, 1}
	}
	return {}
}

editor_ui_ensure_system_cells :: proc(world: ^shared.World, slot: int) -> (int, int) {
	row, row_found := editor_ui_entity(world, .Systems_Row, slot)
	name_cell, name_found := editor_ui_entity(world, .Systems_Name, slot)
	time_cell, time_found := editor_ui_entity(world, .Systems_Time, slot)
	if row_found && name_found && time_found {
		return name_cell, time_cell
	}
	row_name := fmt.tprintf("__scrapbot_editor_system_row_%d", slot)
	name := fmt.tprintf("__scrapbot_editor_system_name_%d", slot)
	timing := fmt.tprintf("__scrapbot_editor_system_time_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_SYSTEMS_NAME,
		.Systems_Row,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {0, 8, 0, 8}},
		slot,
	)
	editor_ui_add_hstack(world, row, {gap = 8, fill = true})
	_ = ecs.set_ui_progress(
		world,
		row,
		{
			maximum = f32(SYSTEM_PROFILE_BAR_MAX_NANOSECONDS),
			fill_color = system_profile_origin_color(.Engine),
			inset = {19, 0, 9, 0},
			corner_radius = 1,
			right_to_left = true,
		},
	)
	name_cell = editor_ui_create_box(
		world,
		name,
		row_name,
		.Systems_Name,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {5, 3, 3, 16}},
		slot,
	)
	editor_ui_add_text(world, name_cell, "", {0.82, 0.85, 0.90, 1}, EDITOR_TEXT_SIZE)
	origin_name := fmt.tprintf("__scrapbot_editor_system_origin_%d", slot)
	_ = editor_ui_create_box(
		world,
		origin_name,
		name,
		.Systems_Origin,
		{
			position = {-15, 3},
			size = {8, 8},
			background = system_profile_origin_color(.Engine),
			corner_radius = 4,
		},
		slot,
	)
	time_cell = editor_ui_create_box(
		world,
		timing,
		row_name,
		.Systems_Time,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {5, 3, 3, 3}},
		slot,
	)
	editor_ui_add_text(world, time_cell, "--", {0.42, 0.45, 0.51, 1}, EDITOR_TEXT_SIZE)
	world.ui_texts[world.entities[time_cell].ui_text_index].alignment = .Right
	return name_cell, time_cell
}

editor_ui_set_system_visuals :: proc(
	world: ^shared.World,
	slot: int,
	kind: shared.System_Profile_Kind,
) {
	color := system_profile_origin_color(kind)
	if origin, found := editor_ui_entity(world, .Systems_Origin, slot); found {
		layout := &world.ui_layouts[world.entities[origin].ui_layout_index]
		layout.background = color
	}
	row, row_found := editor_ui_entity(world, .Systems_Row, slot)
	if !row_found { return }
	entity := world.entities[row]
	if entity.ui_progress_index < 0 || entity.ui_progress_index >= len(world.ui_progresses) {
		return
	}
	progress := world.ui_progresses[entity.ui_progress_index]
	progress.fill_color = color
	_ = ecs.set_ui_progress(world, row, progress)
}

format_system_profile_time :: proc(average_nanoseconds: f64, sampled: bool) -> string {
	if !sampled {
		return "--"
	}
	return fmt.tprintf("%.3f ms", average_nanoseconds / 1_000_000)
}

editor_ui_update_transport :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil { return }
	for component in world.editor_uis {
		if component.role != .Transport_Play &&
		   component.role != .Transport_Stop &&
		   component.role != .Transport_Step { continue }
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) ||
		   entity.ui_button_index < 0 ||
		   entity.ui_button_index >= len(world.ui_buttons) { continue }
		selected :=
			component.role == .Transport_Play && state.editor_simulation_playing ||
			component.role == .Transport_Stop && !state.editor_simulation_playing
		layout := &world.ui_layouts[entity.ui_layout_index]
		button := &world.ui_buttons[entity.ui_button_index]
		layout.background = {0.017, 0.022, 0.030, 1}
		layout.border_color = {0.055, 0.067, 0.088, 1}
		button.color = {0.64, 0.67, 0.73, 1}
		button.hover_background = {0.026, 0.034, 0.045, 1}
		button.active_background = {0.010, 0.014, 0.020, 1}
		if selected && component.role == .Transport_Play {
			layout.background = {0.025, 0.120, 0.105, 1}
			layout.border_color = {0.06, 0.72, 0.63, 0.8}
			button.color = {0.42, 0.92, 0.82, 1}
			button.hover_background = {0.032, 0.165, 0.142, 1}
			button.active_background = {0.018, 0.090, 0.078, 1}
		} else if selected {
			layout.background = {0.135, 0.035, 0.045, 1}
			layout.border_color = {0.78, 0.20, 0.27, 0.85}
			button.color = {0.96, 0.55, 0.59, 1}
			button.hover_background = {0.180, 0.045, 0.058, 1}
			button.active_background = {0.100, 0.025, 0.034, 1}
		}
	}
	if status, found := editor_ui_entity(world, .Status); found {
		entity := world.entities[status]
		if entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts) {
			world.ui_texts[entity.ui_text_index].color = {0.96, 0.55, 0.59, 1}
			if state.editor_simulation_playing {
				world.ui_texts[entity.ui_text_index].color = {0.06, 0.72, 0.63, 1}
			}
		}
	}
}

editor_ui_refresh_system_profile :: proc(state: ^State, world: ^shared.World) {
	entry_count := 0
	if state.system_profile != nil {
		entry_count = state.system_profile.entry_count
		luau_index := 0
		for index in 0 ..< entry_count {
			entry := &state.system_profile.entries[index]
			name_cell, time_cell := editor_ui_ensure_system_cells(world, index)
			if row, found := editor_ui_entity(world, .Systems_Row, index); found {
				editor_ui_set_hidden(world, row, false)
			}
			editor_ui_set_hidden(world, name_cell, false)
			editor_ui_set_hidden(world, time_cell, false)
			name := string(entry.name[:entry.name_length])
			if entry.kind == .Luau {
				luau_index += 1
				if name == "" {
					name = fmt.tprintf("Luau System %d", luau_index)
				}
			}
			editor_ui_set_text(world, name_cell, name)
			editor_ui_set_system_visuals(world, index, entry.kind)
			if row, found := editor_ui_entity(world, .Systems_Row, index); found {
				row_entity := world.entities[row]
				if row_entity.ui_progress_index >= 0 &&
				   row_entity.ui_progress_index < len(world.ui_progresses) {
					progress := world.ui_progresses[row_entity.ui_progress_index]
					progress.value = f32(entry.average_nanoseconds)
					_ = ecs.set_ui_progress(world, row, progress)
				}
			}
			editor_ui_set_text(
				world,
				time_cell,
				format_system_profile_time(
					entry.average_nanoseconds,
					state.system_profile.sample_frames > 0,
				),
			)
		}
	}
	for component in world.editor_uis {
		if (component.role == .Systems_Row ||
			   component.role == .Systems_Name ||
			   component.role == .Systems_Time) &&
		   component.slot >= entry_count {
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
	if systems, found := editor_ui_entity(world, .Systems_Scroll); found {
		editor_ui_set_panel_title(world, systems, fmt.tprintf("SYSTEMS / %d", entry_count))
	}
	if state.system_profile != nil {
		state.editor_system_profile_revision = state.system_profile.revision
	}
}

INSPECTOR_PANEL_TITLE_HEIGHT :: EDITOR_SECTION_TITLE_HEIGHT
INSPECTOR_CELL_HEIGHT :: f32(28)
INSPECTOR_TABLE_ROW_GAP :: f32(3)
INSPECTOR_PANEL_GAP :: f32(10)

editor_ui_ensure_inspector_panel :: proc(world: ^shared.World, slot: int) -> (int, int) {
	panel, panel_found := editor_ui_entity(world, .Inspector_Panel, slot)
	table, table_found := editor_ui_entity(world, .Inspector_Table, slot)
	if panel_found && table_found { return panel, table }
	panel_name := fmt.tprintf("__scrapbot_editor_inspector_panel_%d", slot)
	table_name := fmt.tprintf("__scrapbot_editor_inspector_table_%d", slot)
	panel = editor_ui_create_box(
		world,
		panel_name,
		EDITOR_UI_RIGHT_CONTENT_NAME,
		.Inspector_Panel,
		editor_ui_section_layout({332, 70}),
		slot,
	)
	world.ui_layouts[world.entities[panel].ui_layout_index].fit_content_height = true
	editor_ui_add_section_panel(world, panel, "COMPONENT")
	editor_ui_add_vstack(world, panel, {})
	table = editor_ui_create_box(
		world,
		table_name,
		panel_name,
		.Inspector_Table,
		{size = {308, INSPECTOR_CELL_HEIGHT}, fill_width = true, fit_content_height = true},
		slot,
	)
	editor_ui_add_table(
		world,
		table,
		{columns = 2, column_gap = 10, row_gap = INSPECTOR_TABLE_ROW_GAP},
	)
	return panel, table
}

editor_ui_ensure_inspector_cell :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
	value_cell: bool,
) -> int {
	if cell, found := editor_ui_entity(world, .Inspector_Cell, slot); found {
		editor_ui_set_parent(world, cell, parent)
		return cell
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_cell_%d", slot)
	cell := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Cell,
		{size = {144, INSPECTOR_CELL_HEIGHT}, padding = {5, 3, 3, 3}},
		slot,
	)
	if value_cell {
		layout := &world.ui_layouts[world.entities[cell].ui_layout_index]
		layout.padding = {}
		editor_ui_add_hstack(world, cell, {gap = 6, fill = true})
	} else {
		editor_ui_add_text(world, cell, "", {0.46, 0.49, 0.55, 1}, EDITOR_TEXT_SIZE)
	}
	return cell
}

editor_ui_ensure_inspector_input :: proc(world: ^shared.World, slot: int, parent: string) -> int {
	if input, found := editor_ui_entity(world, .Inspector_Input, slot); found {
		editor_ui_set_parent(world, input, parent)
		return input
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_input_%d", slot)
	input := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Input,
		{
			size = {1, INSPECTOR_CELL_HEIGHT},
			padding = {5, 5, 4, 5},
			background = {0.013, 0.018, 0.025, 1},
			border_color = {0.075, 0.090, 0.115, 1},
			border_width = 1,
			corner_radius = 4,
		},
		slot,
	)
	value := shared.ui_input_default()
	value.color = {0.82, 0.84, 0.88, 1}
	value.size = EDITOR_TEXT_SIZE
	value.selection_background = {0.08, 0.48, 0.40, 0.48}
	value.focus_border_color = {0.12, 0.78, 0.66, 1}
	editor_ui_add_input(world, input, value)
	return input
}

editor_ui_ensure_inspector_checkbox :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
) -> int {
	if checkbox, found := editor_ui_entity(world, .Inspector_Checkbox, slot); found {
		editor_ui_set_parent(world, checkbox, parent)
		return checkbox
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_checkbox_%d", slot)
	checkbox := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Checkbox,
		{size = {1, INSPECTOR_CELL_HEIGHT}},
		slot,
	)
	value := shared.ui_checkbox_default()
	value.background = {0.013, 0.018, 0.025, 1}
	editor_ui_add_checkbox(world, checkbox, value)
	return checkbox
}

Inspector_ECS_Builder :: struct {
	state: ^State,
	world: ^shared.World,
	target: shared.Entity,
	content_entity: int,
	panel_entity: int,
	table_entity: int,
	panel_count: int,
	cell_count: int,
	input_count: int,
	checkbox_count: int,
	row_count: int,
}

editor_ui_set_numeric_metadata :: proc(
	input: ^shared.UI_Input_Component,
	field: shared.Editor_Inspector_Field,
) {
	if input == nil { return }
	input.numeric = field != .None
	input.step = 0.1
	input.minimum = 0
	input.maximum = 0
	input.has_minimum = false
	input.has_maximum = false
	#partial switch field {
		case .Transform_Rotation, .Transform_Scale:
			input.step = 0.01
		case .Camera_Fov:
			input.step = 1
			input.minimum = 1
			input.maximum = 179
			input.has_minimum = true
			input.has_maximum = true
		case .Camera_Near, .Camera_Far:
			input.step = 0.1
			input.minimum = 0.001
			input.has_minimum = true
		case .Ambient_Color, .Directional_Color, .Point_Color:
			input.step = 0.01
			input.minimum = 0
			input.maximum = 1
			input.has_minimum = true
			input.has_maximum = true
		case .Ambient_Intensity, .Directional_Intensity, .Point_Intensity, .Point_Range:
			input.minimum = 0
			input.has_minimum = true
	}
}

editor_ui_finish_inspector_component :: proc(builder: ^Inspector_ECS_Builder) {
	if builder.panel_entity < 0 { return }
	if builder.row_count == 0 {
		editor_ui_set_hidden(builder.world, builder.table_entity, true)
	} else {
		editor_ui_set_hidden(builder.world, builder.table_entity, false)
	}
}

editor_ui_begin_inspector_component :: proc(builder: ^Inspector_ECS_Builder, title: string) {
	editor_ui_finish_inspector_component(builder)
	panel, table := editor_ui_ensure_inspector_panel(builder.world, builder.panel_count)
	builder.panel_entity = panel
	builder.table_entity = table
	builder.row_count = 0
	builder.panel_count += 1
	panel_layout := &builder.world.ui_layouts[builder.world.entities[panel].ui_layout_index]
	table_layout := &builder.world.ui_layouts[builder.world.entities[table].ui_layout_index]
	editor_ui_set_hidden(builder.world, panel, false)
	editor_ui_set_hidden(builder.world, table, false)
	editor_ui_set_panel_title(builder.world, panel, title)
}

editor_ui_inspector_field_values :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	values: []string,
	field: shared.Editor_Inspector_Field = .None,
	custom_storage_index: int = -1,
	custom_field_index: int = -1,
) {
	if builder.table_entity < 0 { return }
	parent := builder.world.entities[builder.table_entity].name
	label_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, false)
	builder.cell_count += 1
	value_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, true)
	builder.cell_count += 1
	cells := [2]int{label_cell, value_cell}
	for cell in cells {
		layout := &builder.world.ui_layouts[builder.world.entities[cell].ui_layout_index]
		editor_ui_set_hidden(builder.world, cell, false)
		layout.size.y = INSPECTOR_CELL_HEIGHT
	}
	label_text := &builder.world.ui_texts[builder.world.entities[label_cell].ui_text_index]
	label_text.color = {0.46, 0.49, 0.55, 1}
	editor_ui_set_text(builder.world, label_cell, label)
	value_parent := builder.world.entities[value_cell].name
	for value, value_index in values {
		input_entity := editor_ui_ensure_inspector_input(
			builder.world,
			builder.input_count,
			value_parent,
		)
		builder.input_count += 1
		layout := &builder.world.ui_layouts[builder.world.entities[input_entity].ui_layout_index]
		editor_ui_set_hidden(builder.world, input_entity, false)
		layout.size = {1, INSPECTOR_CELL_HEIGHT}
		value_input := &builder.world.ui_inputs[builder.world.entities[input_entity].ui_input_index]
		value_input.read_only = field == .None
		if builder.state == nil ||
		   !builder.state.has_focused_input ||
		   builder.state.focused_input != builder.world.entities[input_entity].id {
			_ = ecs.set_ui_input_value(builder.world, input_entity, value)
		}
		role := &builder.world.editor_uis[builder.world.entities[input_entity].editor_ui_index]
		role.target = builder.target
		role.inspector_field = field
		role.inspector_axis = .None
		if len(values) == 3 { role.inspector_axis = shared.Editor_Inspector_Axis(value_index + 1) }
		role.custom_storage_index = custom_storage_index
		role.custom_field_index = custom_field_index
		editor_ui_set_numeric_metadata(value_input, field)
		_ = ecs.set_ui_input_prefix(builder.world, input_entity, "")
		value_input.prefix_width = 0
		value_input.scrubbable = false
		if role.inspector_axis != .None {
			value_input.prefix_width = UI_INPUT_PREFIX_WIDTH
			value_input.scrubbable = true
			prefix := "X"
			value_input.prefix_color = {0.92, 0.30, 0.32, 1}
			if role.inspector_axis == .Y {
				prefix = "Y"
				value_input.prefix_color = {0.34, 0.82, 0.42, 1}
			} else if role.inspector_axis == .Z {
				prefix = "Z"
				value_input.prefix_color = {0.34, 0.55, 0.96, 1}
			}
			_ = ecs.set_ui_input_prefix(builder.world, input_entity, prefix)
			value_input.prefix_background = {
				value_input.prefix_color.x,
				value_input.prefix_color.y,
				value_input.prefix_color.z,
				0.12,
			}
		}
		if value_input.numeric &&
		   (builder.state == nil ||
				   !builder.state.has_focused_input ||
				   builder.state.focused_input != builder.world.entities[input_entity].id) {
			if number, ok := strconv.parse_f32(strings.trim_space(value)); ok {
				value_input.number = number
			}
		}
	}
	builder.row_count += 1
}

editor_ui_inspector_field :: proc(
	builder: ^Inspector_ECS_Builder,
	label, value: string,
	field: shared.Editor_Inspector_Field = .None,
) {
	values := [1]string{value}
	editor_ui_inspector_field_values(builder, label, values[:], field)
}

editor_ui_inspector_bool :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: bool,
	field: shared.Editor_Inspector_Field = .None,
) {
	if builder.table_entity < 0 { return }
	parent := builder.world.entities[builder.table_entity].name
	label_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, false)
	builder.cell_count += 1
	value_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, true)
	builder.cell_count += 1
	cells := [2]int{label_cell, value_cell}
	for cell in cells {
		layout := &builder.world.ui_layouts[builder.world.entities[cell].ui_layout_index]
		editor_ui_set_hidden(builder.world, cell, false)
		layout.size.y = INSPECTOR_CELL_HEIGHT
	}
	label_text := &builder.world.ui_texts[builder.world.entities[label_cell].ui_text_index]
	label_text.color = {0.46, 0.49, 0.55, 1}
	editor_ui_set_text(builder.world, label_cell, label)
	checkbox_entity := editor_ui_ensure_inspector_checkbox(
		builder.world,
		builder.checkbox_count,
		builder.world.entities[value_cell].name,
	)
	builder.checkbox_count += 1
	editor_ui_set_hidden(builder.world, checkbox_entity, false)
	checkbox := &builder.world.ui_checkboxes[builder.world.entities[checkbox_entity].ui_checkbox_index]
	checkbox.checked = value
	checkbox.read_only = field == .None
	role := &builder.world.editor_uis[builder.world.entities[checkbox_entity].editor_ui_index]
	role.target = builder.target
	role.inspector_field = field
	role.inspector_axis = .None
	builder.row_count += 1
}

editor_ui_inspector_vec3 :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: shared.Vec3,
	field: shared.Editor_Inspector_Field,
	custom_storage_index: int = -1,
	custom_field_index: int = -1,
) {
	values := [3]string {
		fmt.tprintf("%.2f", value.x),
		fmt.tprintf("%.2f", value.y),
		fmt.tprintf("%.2f", value.z),
	}
	editor_ui_inspector_field_values(
		builder,
		label,
		values[:],
		field,
		custom_storage_index,
		custom_field_index,
	)
}

editor_ui_finish_inspector :: proc(builder: ^Inspector_ECS_Builder) {
	editor_ui_finish_inspector_component(builder)
	for component in builder.world.editor_uis {
		if component.entity_index < 0 ||
		   component.entity_index >= len(builder.world.entities) { continue }
		entity := builder.world.entities[component.entity_index]
		if !entity.alive ||
		   entity.origin != .Editor ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(builder.world.ui_layouts) { continue }
		#partial switch component.role {
			case .Inspector_Panel, .Inspector_Table:
				if component.slot >=
				   builder.panel_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Cell:
				if component.slot >=
				   builder.cell_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Input:
				if component.slot >=
				   builder.input_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Checkbox:
				if component.slot >=
				   builder.checkbox_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case:
		}
	}
}

editor_ui_build_inspector_panels :: proc(
	state: ^State,
	world: ^shared.World,
	content_entity, entity_index: int,
) {
	builder := Inspector_ECS_Builder {
		state = state,
		world = world,
		content_entity = content_entity,
		panel_entity = -1,
		table_entity = -1,
	}
	if entity_index < 0 || entity_index >= len(world.entities) {
		editor_ui_finish_inspector(&builder)
		return
	}
	entity := world.entities[entity_index]
	builder.target = entity.id
	if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
		value := world.transforms[entity.transform_index]
		editor_ui_begin_inspector_component(&builder, "TRANSFORM")
		editor_ui_inspector_vec3(&builder, "position", value.position, .Transform_Position)
		editor_ui_inspector_vec3(&builder, "rotation", value.rotation, .Transform_Rotation)
		editor_ui_inspector_vec3(&builder, "scale", value.scale, .Transform_Scale)
	}
	if entity.camera_index >= 0 && entity.camera_index < len(world.cameras) {
		value := world.cameras[entity.camera_index]
		editor_ui_begin_inspector_component(&builder, "CAMERA")
		editor_ui_inspector_field(&builder, "fov", fmt.tprintf("%.2f", value.fov), .Camera_Fov)
		editor_ui_inspector_field(&builder, "near", fmt.tprintf("%.3f", value.near), .Camera_Near)
		editor_ui_inspector_field(&builder, "far", fmt.tprintf("%.2f", value.far), .Camera_Far)
	}
	if entity.ambient_light_index >= 0 && entity.ambient_light_index < len(world.ambient_lights) {
		value := world.ambient_lights[entity.ambient_light_index]
		editor_ui_begin_inspector_component(&builder, "AMBIENT LIGHT")
		editor_ui_inspector_vec3(&builder, "color", value.color, .Ambient_Color)
		editor_ui_inspector_field(
			&builder,
			"intensity",
			fmt.tprintf("%.2f", value.intensity),
			.Ambient_Intensity,
		)
	}
	if entity.directional_light_index >= 0 &&
	   entity.directional_light_index < len(world.directional_lights) {
		value := world.directional_lights[entity.directional_light_index]
		editor_ui_begin_inspector_component(&builder, "DIRECTIONAL LIGHT")
		editor_ui_inspector_vec3(&builder, "direction", value.direction, .Directional_Direction)
		editor_ui_inspector_vec3(&builder, "color", value.color, .Directional_Color)
		editor_ui_inspector_field(
			&builder,
			"intensity",
			fmt.tprintf("%.2f", value.intensity),
			.Directional_Intensity,
		)
	}
	if entity.point_light_index >= 0 && entity.point_light_index < len(world.point_lights) {
		value := world.point_lights[entity.point_light_index]
		editor_ui_begin_inspector_component(&builder, "POINT LIGHT")
		editor_ui_inspector_vec3(&builder, "color", value.color, .Point_Color)
		editor_ui_inspector_field(
			&builder,
			"intensity",
			fmt.tprintf("%.2f", value.intensity),
			.Point_Intensity,
		)
		editor_ui_inspector_field(
			&builder,
			"range",
			fmt.tprintf("%.2f", value.range),
			.Point_Range,
		)
	}
	if entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes) {
		editor_ui_begin_inspector_component(&builder, "MESH")
		editor_ui_inspector_field(&builder, "primitive", world.meshes[entity.mesh_index].primitive)
	}
	if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		value := world.geometries[entity.geometry_index]
		editor_ui_begin_inspector_component(&builder, "GEOMETRY")
		editor_ui_inspector_field(
			&builder,
			"handle",
			format_handle(value.handle.index, value.handle.generation),
		)
	}
	if entity.material_index >= 0 && entity.material_index < len(world.materials) {
		value := world.materials[entity.material_index]
		editor_ui_begin_inspector_component(&builder, "MATERIAL")
		editor_ui_inspector_field(
			&builder,
			"handle",
			format_handle(value.handle.index, value.handle.generation),
		)
	}
	if entity.render_instance_index >= 0 &&
	   entity.render_instance_index < len(world.render_instances) {
		value := world.render_instances[entity.render_instance_index]
		editor_ui_begin_inspector_component(&builder, "RENDER INSTANCE")
		editor_ui_inspector_field(
			&builder,
			"geometry",
			format_handle(value.geometry.index, value.geometry.generation),
		)
		editor_ui_inspector_field(
			&builder,
			"material",
			format_handle(value.material.index, value.material.generation),
		)
	}
	if entity.editor_transform_gizmo_index >= 0 &&
	   entity.editor_transform_gizmo_index < len(world.editor_transform_gizmos) {
		value := world.editor_transform_gizmos[entity.editor_transform_gizmo_index]
		mode := "translate"
		switch value.mode {case .Translate:; case .Rotate:
				mode = "rotate"; case .Scale:
				mode = "scale"}
		editor_ui_begin_inspector_component(&builder, "EDITOR TRANSFORM GIZMO")
		editor_ui_inspector_field(&builder, "mode", mode)
	}
	if entity.has_shadow_caster {
		editor_ui_begin_inspector_component(&builder, "SHADOW CASTER")
		editor_ui_inspector_bool(&builder, "enabled", true)
	}
	if entity.has_shadow_receiver {
		editor_ui_begin_inspector_component(&builder, "SHADOW RECEIVER")
		editor_ui_inspector_bool(&builder, "enabled", true)
	}
	if entity.ui_layout_index >= 0 && entity.ui_layout_index < len(world.ui_layouts) {
		value := world.ui_layouts[entity.ui_layout_index]
		editor_ui_begin_inspector_component(&builder, "UI LAYOUT")
		parent_text := "none"
		parent_buffer: [36]u8
		if value.parent != (shared.Entity_UUID{}) {
			parent_text = shared.entity_uuid_to_string(value.parent, parent_buffer[:])
		}
		editor_ui_inspector_field(&builder, "parent", parent_text)
		editor_ui_inspector_field(&builder, "position", format_vec2(value.position))
		editor_ui_inspector_field(&builder, "size", format_vec2(value.size))
		editor_ui_inspector_field(&builder, "margin", format_vec4(value.margin))
		editor_ui_inspector_field(&builder, "padding", format_vec4(value.padding))
		editor_ui_inspector_field(&builder, "background", format_vec4(value.background))
		editor_ui_inspector_field(&builder, "border", format_vec4(value.border_color))
		editor_ui_inspector_field(
			&builder,
			"border width",
			fmt.tprintf("%.2f", value.border_width),
		)
		editor_ui_inspector_field(&builder, "radius", fmt.tprintf("%.2f", value.corner_radius))
		editor_ui_inspector_bool(&builder, "hidden", value.hidden, .UI_Layout_Hidden)
	}
	if entity.ui_hstack_index >= 0 && entity.ui_hstack_index < len(world.ui_hstacks) {
		value := world.ui_hstacks[entity.ui_hstack_index]
		editor_ui_begin_inspector_component(&builder, "UI HSTACK")
		editor_ui_inspector_field(&builder, "gap", fmt.tprintf("%.2f", value.gap))
		editor_ui_inspector_bool(&builder, "fill", value.fill, .UI_HStack_Fill)
		editor_ui_inspector_bool(&builder, "draggable", value.draggable, .UI_HStack_Draggable)
		editor_ui_inspector_field(&builder, "min size", fmt.tprintf("%.2f", value.min_size))
	}
	if entity.ui_vstack_index >= 0 && entity.ui_vstack_index < len(world.ui_vstacks) {
		value := world.ui_vstacks[entity.ui_vstack_index]
		editor_ui_begin_inspector_component(&builder, "UI VSTACK")
		editor_ui_inspector_field(&builder, "gap", fmt.tprintf("%.2f", value.gap))
		editor_ui_inspector_bool(&builder, "fill", value.fill, .UI_VStack_Fill)
		editor_ui_inspector_bool(&builder, "draggable", value.draggable, .UI_VStack_Draggable)
		editor_ui_inspector_field(&builder, "min size", fmt.tprintf("%.2f", value.min_size))
	}
	if entity.ui_scroll_area_index >= 0 &&
	   entity.ui_scroll_area_index < len(world.ui_scroll_areas) {
		value := world.ui_scroll_areas[entity.ui_scroll_area_index]
		editor_ui_begin_inspector_component(&builder, "UI SCROLL AREA")
		editor_ui_inspector_field(
			&builder,
			"scroll speed",
			fmt.tprintf("%.2f", value.scroll_speed),
		)
		editor_ui_inspector_field(&builder, "smoothness", fmt.tprintf("%.2f", value.smoothness))
		editor_ui_inspector_field(
			&builder,
			"bar width",
			fmt.tprintf("%.2f", value.scrollbar_width),
		)
		editor_ui_inspector_field(
			&builder,
			"bar right",
			fmt.tprintf("%.2f", value.scrollbar_right),
		)
		editor_ui_inspector_field(
			&builder,
			"bar inset",
			fmt.tprintf("%.2f", value.scrollbar_vertical_inset),
		)
		editor_ui_inspector_field(
			&builder,
			"thumb min",
			fmt.tprintf("%.2f", value.minimum_thumb_size),
		)
		editor_ui_inspector_field(
			&builder,
			"bar radius",
			fmt.tprintf("%.2f", value.scrollbar_corner_radius),
		)
		editor_ui_inspector_field(
			&builder,
			"track color",
			format_vec4(value.scrollbar_track_color),
		)
		editor_ui_inspector_field(
			&builder,
			"thumb color",
			format_vec4(value.scrollbar_thumb_color),
		)
	}
	if entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels) {
		value := world.ui_panels[entity.ui_panel_index]
		editor_ui_begin_inspector_component(&builder, "UI PANEL")
		editor_ui_inspector_field(&builder, "title", value.title)
		font := value.font; if font == "" { font = "Inter (default)" }
		editor_ui_inspector_field(&builder, "font", font)
		editor_ui_inspector_field(&builder, "title color", format_vec4(value.title_color))
		editor_ui_inspector_field(
			&builder,
			"title background",
			format_vec4(value.title_background),
		)
		editor_ui_inspector_field(&builder, "title size", fmt.tprintf("%.2f", value.title_size))
		editor_ui_inspector_field(
			&builder,
			"title height",
			fmt.tprintf("%.2f", value.title_height),
		)
		editor_ui_inspector_field(
			&builder,
			"arrow size",
			fmt.tprintf("%.2f", value.disclosure_size),
		)
		editor_ui_inspector_field(
			&builder,
			"arrow margin",
			fmt.tprintf("%.2f", value.disclosure_margin),
		)
		editor_ui_inspector_field(&builder, "arrow gap", fmt.tprintf("%.2f", value.disclosure_gap))
		editor_ui_inspector_field(
			&builder,
			"arrow radius",
			fmt.tprintf("%.2f", value.disclosure_corner_radius),
		)
		editor_ui_inspector_bool(&builder, "collapsible", value.collapsible, .UI_Panel_Collapsible)
		editor_ui_inspector_bool(&builder, "collapsed", value.collapsed, .UI_Panel_Collapsed)
	}
	if entity.ui_table_index >= 0 && entity.ui_table_index < len(world.ui_tables) {
		value := world.ui_tables[entity.ui_table_index]
		editor_ui_begin_inspector_component(&builder, "UI TABLE")
		editor_ui_inspector_field(&builder, "columns", fmt.tprintf("%d", value.columns))
		editor_ui_inspector_field(&builder, "column gap", fmt.tprintf("%.2f", value.column_gap))
		editor_ui_inspector_field(&builder, "row gap", fmt.tprintf("%.2f", value.row_gap))
	}
	if entity.ui_list_index >= 0 && entity.ui_list_index < len(world.ui_lists) {
		value := world.ui_lists[entity.ui_list_index]
		editor_ui_begin_inspector_component(&builder, "UI LIST")
		selected := "none"
		selected_buffer: [36]u8
		if value.selected != (shared.Entity_UUID{}) {
			selected = shared.entity_uuid_to_string(value.selected, selected_buffer[:])
		}
		editor_ui_inspector_field(&builder, "selected", selected)
		editor_ui_inspector_field(&builder, "gap", fmt.tprintf("%.2f", value.gap))
		editor_ui_inspector_field(
			&builder,
			"selection background",
			format_vec4(value.selection_background),
		)
		editor_ui_inspector_field(
			&builder,
			"hover background",
			format_vec4(value.hover_background),
		)
		editor_ui_inspector_field(
			&builder,
			"active background",
			format_vec4(value.active_background),
		)
	}
	if entity.ui_progress_index >= 0 && entity.ui_progress_index < len(world.ui_progresses) {
		value := world.ui_progresses[entity.ui_progress_index]
		editor_ui_begin_inspector_component(&builder, "UI PROGRESS")
		editor_ui_inspector_field(&builder, "value", fmt.tprintf("%.3f", value.value))
		editor_ui_inspector_field(&builder, "maximum", fmt.tprintf("%.3f", value.maximum))
		editor_ui_inspector_field(&builder, "fill color", format_vec4(value.fill_color))
		editor_ui_inspector_field(
			&builder,
			"background color",
			format_vec4(value.background_color),
		)
		editor_ui_inspector_field(&builder, "inset", format_vec4(value.inset))
		editor_ui_inspector_field(&builder, "radius", fmt.tprintf("%.2f", value.corner_radius))
		editor_ui_inspector_bool(&builder, "right to left", value.right_to_left)
	}
	if entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts) {
		value := world.ui_texts[entity.ui_text_index]
		editor_ui_begin_inspector_component(&builder, "UI TEXT")
		editor_ui_inspector_field(&builder, "text", value.text)
		font := value.font; if font == "" { font = "Inter (default)" }
		editor_ui_inspector_field(&builder, "font", font)
		editor_ui_inspector_field(&builder, "color", format_vec4(value.color))
		editor_ui_inspector_field(&builder, "size", fmt.tprintf("%.2f", value.size))
		alignment := "left"
		switch value.alignment {
			case .Left:
			case .Center:
				alignment = "center"
			case .Right:
				alignment = "right"
		}
		editor_ui_inspector_field(&builder, "alignment", alignment)
	}
	if entity.ui_button_index >= 0 && entity.ui_button_index < len(world.ui_buttons) {
		value := world.ui_buttons[entity.ui_button_index]
		editor_ui_begin_inspector_component(&builder, "UI BUTTON")
		editor_ui_inspector_field(&builder, "text", value.text)
		font := value.font; if font == "" { font = "Inter (default)" }
		editor_ui_inspector_field(&builder, "font", font)
		editor_ui_inspector_field(&builder, "color", format_vec4(value.color))
		editor_ui_inspector_field(&builder, "size", fmt.tprintf("%.2f", value.size))
		alignment := "left"
		if value.alignment == .Center {
			alignment = "center"
		} else if value.alignment == .Right {
			alignment = "right"
		}
		editor_ui_inspector_field(&builder, "alignment", alignment)
		editor_ui_inspector_field(
			&builder,
			"hover background",
			format_vec4(value.hover_background),
		)
		editor_ui_inspector_field(
			&builder,
			"active background",
			format_vec4(value.active_background),
		)
	}
	if entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs) {
		value := world.ui_inputs[entity.ui_input_index]
		editor_ui_begin_inspector_component(&builder, "UI INPUT")
		editor_ui_inspector_field(&builder, "text", value.text)
		font := value.font; if font == "" { font = "Inter (default)" }
		editor_ui_inspector_field(&builder, "font", font)
		editor_ui_inspector_field(&builder, "color", format_vec4(value.color))
		editor_ui_inspector_field(&builder, "size", fmt.tprintf("%.2f", value.size))
		editor_ui_inspector_field(&builder, "prefix", value.prefix)
		editor_ui_inspector_field(&builder, "prefix color", format_vec4(value.prefix_color))
		editor_ui_inspector_field(
			&builder,
			"prefix background",
			format_vec4(value.prefix_background),
		)
		editor_ui_inspector_field(
			&builder,
			"prefix width",
			fmt.tprintf("%.2f", value.prefix_width),
		)
		editor_ui_inspector_field(&builder, "prefix gap", fmt.tprintf("%.2f", value.prefix_gap))
		editor_ui_inspector_field(
			&builder,
			"prefix radius",
			fmt.tprintf("%.2f", value.prefix_corner_radius),
		)
		editor_ui_inspector_field(&builder, "selection", format_vec4(value.selection_background))
		editor_ui_inspector_field(
			&builder,
			"selection radius",
			fmt.tprintf("%.2f", value.selection_corner_radius),
		)
		editor_ui_inspector_field(&builder, "focus border", format_vec4(value.focus_border_color))
		editor_ui_inspector_field(
			&builder,
			"invalid border",
			format_vec4(value.invalid_border_color),
		)
		editor_ui_inspector_field(&builder, "caret color", format_vec4(value.caret_color))
		editor_ui_inspector_field(&builder, "caret width", fmt.tprintf("%.2f", value.caret_width))
		editor_ui_inspector_bool(&builder, "numeric", value.numeric)
		editor_ui_inspector_bool(&builder, "scrubbable", value.scrubbable)
		editor_ui_inspector_bool(&builder, "read only", value.read_only, .UI_Input_Read_Only)
	}
	if entity.ui_checkbox_index >= 0 && entity.ui_checkbox_index < len(world.ui_checkboxes) {
		value := world.ui_checkboxes[entity.ui_checkbox_index]
		editor_ui_begin_inspector_component(&builder, "UI CHECKBOX")
		editor_ui_inspector_bool(&builder, "checked", value.checked, .UI_Checkbox_Checked)
		editor_ui_inspector_field(&builder, "box size", fmt.tprintf("%.2f", value.box_size))
		editor_ui_inspector_field(&builder, "background", format_vec4(value.background))
		editor_ui_inspector_field(
			&builder,
			"checked background",
			format_vec4(value.checked_background),
		)
		editor_ui_inspector_field(&builder, "border", format_vec4(value.border_color))
		editor_ui_inspector_field(&builder, "check", format_vec4(value.check_color))
		editor_ui_inspector_field(&builder, "radius", fmt.tprintf("%.2f", value.corner_radius))
		editor_ui_inspector_field(
			&builder,
			"border width",
			fmt.tprintf("%.2f", value.border_width),
		)
		editor_ui_inspector_field(&builder, "check inset", fmt.tprintf("%.2f", value.check_inset))
		editor_ui_inspector_field(
			&builder,
			"check radius",
			fmt.tprintf("%.2f", value.check_corner_radius),
		)
		editor_ui_inspector_bool(&builder, "read only", value.read_only, .UI_Checkbox_Read_Only)
	}
	for storage, storage_index in world.custom_components {
		for component in storage.components {
			if component.entity_index != entity_index { continue }
			editor_ui_begin_inspector_component(&builder, storage.name)
			for field, field_index in component.vec3_fields {
				editor_ui_inspector_vec3(
					&builder,
					field.name,
					field.value,
					.Custom_Vec3,
					storage_index,
					field_index,
				)
			}
			break
		}
	}
	editor_ui_finish_inspector(&builder)
}

refresh_editor_ecs_snapshot :: proc(state: ^State, world: ^shared.World) {
	editor_ui_refresh_system_profile(state, world)
	visible_count := 0
	selected_row: shared.Entity_UUID
	entity_count := len(world.entities)
	for entity_index in 0 ..< entity_count {
		entity := world.entities[entity_index]
		if !entity.alive || entity.origin == .Editor { continue }
		row, label := editor_ui_ensure_row(world, visible_count)
		world.entities[row].alive = true
		world.entities[label].alive = true
		editor_ui_set_hidden(world, row, false)
		editor_ui_set_hidden(world, label, false)
		world.editor_uis[world.entities[row].editor_ui_index].target = entity.id
		world.editor_uis[world.entities[label].editor_ui_index].target = entity.id
		if state.editor_has_selection && state.editor_selected_entity == entity.id {
			selected_row = world.entities[row].uuid
		}
		label_text := &world.ui_texts[world.entities[label].ui_text_index]
		label_text.color = {0.82, 0.85, 0.90, 1}
		if entity.origin == .Runtime { label_text.color = EDITOR_RUNTIME_ENTITY_COLOR }
		editor_ui_set_text(world, label, entity.name)
		visible_count += 1
	}
	for component in world.editor_uis {
		if (component.role == .Browser_Row || component.role == .Browser_Row_Label) &&
		   component.slot >= visible_count {
			if component.entity_index < 0 ||
			   component.entity_index >= len(world.entities) { continue }
			entity := world.entities[component.entity_index]
			if !entity.alive ||
			   entity.origin != .Editor ||
			   entity.ui_layout_index < 0 ||
			   entity.ui_layout_index >= len(world.ui_layouts) { continue }
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
	if scene, found := editor_ui_entity(world, .Browser_Scroll); found {
		entity := world.entities[scene]
		if entity.ui_list_index >= 0 && entity.ui_list_index < len(world.ui_lists) {
			world.ui_lists[entity.ui_list_index].selected = selected_row
		}
	}
	if status, found := editor_ui_entity(world, .Status); found {
		mode := "PAUSED"
		if state.editor_simulation_playing { mode = "RUNNING" }
		editor_ui_set_text(world, status, mode)
	}

	if header, found := editor_ui_entity(world, .Inspector_Header); found {
		if !state.editor_has_selection { editor_ui_set_text(world, header, "Select an entity to inspect") } else {
			index := int(state.editor_selected_entity.index)
			if index >= 0 && index < len(world.entities) {
				entity := world.entities[index]
				origin := "SCENE ENTITY"
				if entity.origin == .Runtime { origin = "RUNTIME ENTITY" }
				id_buffer: [36]u8
				id := shared.entity_uuid_to_string(entity.uuid, id_buffer[:])
				editor_ui_set_text(
					world,
					header,
					fmt.tprintf("%s\n%s  /  %s", entity.name, origin, id),
				)
			}
		}
	}
	if content, found := editor_ui_entity(world, .Inspector_Content); found {
		selected_index := -1
		if state.editor_has_selection { selected_index = int(state.editor_selected_entity.index) }
		editor_ui_build_inspector_panels(state, world, content, selected_index)
	}
	state.editor_snapshot_elapsed = 0
	state.editor_snapshot_valid = true
	state.editor_snapshot_has_selection = state.editor_has_selection
	state.editor_snapshot_selected_entity = state.editor_selected_entity
	state.editor_snapshot_refresh_count += 1
}

reconcile_editor_ui_world :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || !state.editor_visible { return }
	editor_ui_create_shell(world)
	editor_ui_update_transport(state, world)
	if !state.editor_snapshot_valid ||
	   !state.editor_snapshot_was_visible { refresh_editor_ecs_snapshot(state, world) }
}

editor_ui_input_binding :: proc(
	world: ^shared.World,
	entity_index: int,
) -> (
	^shared.Editor_UI_Component,
	^shared.UI_Input_Component,
	bool,
) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return {}, nil, false
	}
	entity := world.entities[entity_index]
	if !entity.alive ||
	   entity.origin != .Editor ||
	   entity.editor_ui_index < 0 ||
	   entity.editor_ui_index >= len(world.editor_uis) ||
	   entity.ui_input_index < 0 ||
	   entity.ui_input_index >= len(world.ui_inputs) {
		return {}, nil, false
	}
	binding := &world.editor_uis[entity.editor_ui_index]
	if binding.role != .Inspector_Input {
		return {}, nil, false
	}
	return binding, &world.ui_inputs[entity.ui_input_index], true
}

editor_ui_prepare_input_focus :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	binding, input, found := editor_ui_input_binding(world, entity_index)
	if !found || !input.numeric {
		return
	}
	if number, ok := read_inspector_numeric(world, binding^); ok {
		set_numeric_input_text(state, world, entity_index, input, number)
		binding.input_original_number = number
		binding.input_has_original_number = true
	}
}

editor_ui_consume_input_state :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	binding, input, found := editor_ui_input_binding(world, entity_index)
	if !found || !input.numeric {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_state_index < 0 || entity.ui_state_index >= len(world.ui_states) {
		return
	}
	interaction := world.ui_states[entity.ui_state_index]
	if (interaction.changed || interaction.submitted || interaction.cancelled) &&
	   !binding.input_has_original_number {
		if number, ok := read_inspector_numeric(world, binding^); ok {
			binding.input_original_number = number
			binding.input_has_original_number = true
		}
	}
	if interaction.changed && interaction.valid {
		_ = write_inspector_numeric(state, world, binding^, input.number)
	}
	if interaction.cancelled {
		_ = write_inspector_numeric(state, world, binding^, input.number)
		binding.input_has_original_number = false
	}
	if interaction.submitted {
		_ = write_inspector_numeric(state, world, binding^, input.number)
		if binding.input_has_original_number {
			editor_history_push(
				state,
				world,
				binding^,
				binding.input_original_number,
				input.number,
			)
		}
		binding.input_has_original_number = false
	}
}

editor_ui_handle_history_shortcut :: proc(
	state: ^State,
	world: ^shared.World,
	keyboard: Keyboard_Input,
) -> bool {
	if state == nil ||
	   world == nil ||
	   !state.editor_visible ||
	   (state.has_focused_input && !state.focused_input_editor) ||
	   (!keyboard.undo && !keyboard.redo) {
		return false
	}
	if state.has_focused_input {
		entity_index := int(state.focused_input.index)
		if !finish_input_edit(state, world) {
			cancel_input_edit(state, world)
		}
		sync_ui_interaction_states(state, world)
		editor_ui_consume_input_state(state, world, entity_index)
		clear_input_focus(state)
	}
	_ = editor_history_apply(state, world, keyboard.redo)
	return true
}
