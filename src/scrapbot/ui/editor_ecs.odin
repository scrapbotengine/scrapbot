package ui

import ecs "../ecs"
import shared "../shared"
import "core:fmt"
import "core:math"
import "core:strings"

EDITOR_UI_ROOT_NAME :: "__scrapbot_editor_root"
EDITOR_UI_TOP_NAME :: "__scrapbot_editor_top"
EDITOR_UI_WORKSPACE_NAME :: "__scrapbot_editor_workspace"
EDITOR_UI_LEFT_NAME :: "__scrapbot_editor_left"
EDITOR_UI_SYSTEMS_NAME :: "__scrapbot_editor_systems"
EDITOR_UI_BROWSER_HEADER_NAME :: "__scrapbot_editor_browser_header"
EDITOR_UI_BROWSER_NAME :: "__scrapbot_editor_browser"
EDITOR_UI_VIEWPORT_NAME :: "__scrapbot_editor_viewport"
EDITOR_UI_RIGHT_NAME :: "__scrapbot_editor_right"
EDITOR_UI_INSPECTOR_HEADER_NAME :: "__scrapbot_editor_inspector_header"
EDITOR_UI_INSPECTOR_NAME :: "__scrapbot_editor_inspector"
EDITOR_UI_INSPECTOR_CONTENT_NAME :: "__scrapbot_editor_inspector_content"
EDITOR_UI_STATUS_NAME :: "__scrapbot_editor_status"

editor_ui_clone_string :: proc(value: string) -> string {
	if value == "" { return "" }
	cloned, err := strings.clone(value)
	if err != nil { return "" }
	return cloned
}

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

editor_ui_create_box :: proc(
	world: ^shared.World,
	name: string,
	parent: string,
	role: shared.Editor_UI_Role,
	layout: shared.UI_Layout_Component,
	slot: int = 0,
) -> int {
	entity_index := len(world.entities)
	layout_index := len(world.ui_layouts)
	role_index := len(world.editor_uis)
	layout_value := layout
	if parent != "" {
		layout_value.parent = shared.entity_uuid_from_engine_name(parent)
	}
	entity_uuid := shared.entity_uuid_from_engine_name(name)
	append(&world.ui_layouts, layout_value)
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
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = u32(entity_index), generation = 1},
			uuid = entity_uuid,
			alive = true,
			origin = .Editor,
			name = editor_ui_clone_string(name),
			transform_index = -1,
			camera_index = -1,
			ambient_light_index = -1,
			directional_light_index = -1,
			point_light_index = -1,
			mesh_index = -1,
			geometry_index = -1,
			material_index = -1,
			render_instance_index = -1,
			render_active_index = -1,
			ui_layout_index = layout_index,
			ui_hstack_index = -1,
			ui_vstack_index = -1,
			ui_scroll_area_index = -1,
			ui_panel_index = -1,
			ui_table_index = -1,
			ui_text_index = -1,
			ui_button_index = -1,
			ui_input_index = -1,
			editor_transform_gizmo_index = -1,
			editor_ui_index = role_index,
		},
	)
	if world.entity_by_uuid == nil {
		world.entity_by_uuid = make(map[shared.Entity_UUID]int)
	}
	world.entity_by_uuid[entity_uuid] = entity_index
	ecs.mark_ui_entity_dirty(world, entity_index)
	return entity_index
}

editor_ui_add_text :: proc(
	world: ^shared.World,
	entity_index: int,
	text: string,
	color: shared.Vec4,
	size: f32,
) {
	entity := &world.entities[entity_index]
	entity.ui_text_index = len(world.ui_texts)
	append(
		&world.ui_texts,
		shared.UI_Text_Component{text = editor_ui_clone_string(text), color = color, size = size},
	)
}

editor_ui_add_button :: proc(world: ^shared.World, entity_index: int) {
	entity := &world.entities[entity_index]
	entity.ui_button_index = len(world.ui_buttons)
	append(
		&world.ui_buttons,
		shared.UI_Button_Component {
			text = editor_ui_clone_string(" "),
			color = {0, 0, 0, 0},
			size = 1,
			hover_background = {0.020, 0.027, 0.036, 1},
			active_background = {0.030, 0.041, 0.054, 1},
		},
	)
}

editor_ui_add_input :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Input_Component,
) {
	input := value
	input.text = editor_ui_clone_string(value.text)
	world.entities[entity_index].ui_input_index = len(world.ui_inputs)
	append(&world.ui_inputs, input)
}

editor_ui_add_hstack :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Stack_Component,
) {
	world.entities[entity_index].ui_hstack_index = len(world.ui_hstacks)
	append(&world.ui_hstacks, value)
}

editor_ui_add_vstack :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Stack_Component,
) {
	world.entities[entity_index].ui_vstack_index = len(world.ui_vstacks)
	append(&world.ui_vstacks, value)
}

editor_ui_add_scroll :: proc(world: ^shared.World, entity_index: int) {
	world.entities[entity_index].ui_scroll_area_index = len(world.ui_scroll_areas)
	append(
		&world.ui_scroll_areas,
		shared.UI_Scroll_Area_Component {
			scroll_speed = EDITOR_SCROLL_SPEED,
			smoothness = EDITOR_SCROLL_SMOOTHNESS,
		},
	)
}

editor_ui_add_panel :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Panel_Component,
) {
	panel := value
	panel.title = editor_ui_clone_string(value.title)
	world.entities[entity_index].ui_panel_index = len(world.ui_panels)
	append(&world.ui_panels, panel)
}

editor_ui_add_table :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Table_Component,
) {
	world.entities[entity_index].ui_table_index = len(world.ui_tables)
	append(&world.ui_tables, value)
}

editor_ui_set_text :: proc(world: ^shared.World, entity_index: int, value: string) {
	if entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	index := world.entities[entity_index].ui_text_index
	if index < 0 || index >= len(world.ui_texts) || world.ui_texts[index].text == value {
		return
	}
	delete(world.ui_texts[index].text)
	world.ui_texts[index].text = editor_ui_clone_string(value)
}

editor_ui_set_parent :: proc(world: ^shared.World, entity_index: int, value: string) {
	if entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	index := world.entities[entity_index].ui_layout_index
	parent: shared.Entity_UUID
	if value != "" {
		parent = shared.entity_uuid_from_engine_name(value)
	}
	if index < 0 || index >= len(world.ui_layouts) || world.ui_layouts[index].parent == parent {
		return
	}
	world.ui_layouts[index].parent = parent
	ecs.mark_ui_subtree_dirty(world, entity_index)
}

editor_ui_set_hidden :: proc(world: ^shared.World, entity_index: int, hidden: bool) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	layout_index := world.entities[entity_index].ui_layout_index
	if layout_index < 0 ||
	   layout_index >= len(world.ui_layouts) ||
	   world.ui_layouts[layout_index].hidden == hidden {
		return
	}
	world.ui_layouts[layout_index].hidden = hidden
	ecs.mark_ui_subtree_dirty(world, entity_index)
}

editor_ui_set_panel_title :: proc(world: ^shared.World, entity_index: int, value: string) {
	if entity_index < 0 || entity_index >= len(world.entities) { return }
	index := world.entities[entity_index].ui_panel_index
	if index < 0 ||
	   index >= len(world.ui_panels) ||
	   world.ui_panels[index].title == value { return }
	delete(world.ui_panels[index].title)
	world.ui_panels[index].title = editor_ui_clone_string(value)
}

editor_ui_create_shell :: proc(world: ^shared.World) {
	if _, found := editor_ui_entity(world, .Root); found { return }
	text := shared.Vec4{0.82, 0.85, 0.90, 1}
	muted := shared.Vec4{0.42, 0.45, 0.51, 1}
	quiet := shared.Vec4{0.28, 0.31, 0.36, 1}
	mint := shared.Vec4{0.06, 0.72, 0.63, 1}
	void := shared.Vec4{0.004, 0.005, 0.007, 1}
	panel := shared.Vec4{0.009, 0.012, 0.016, 1}
	raised := shared.Vec4{0.017, 0.022, 0.030, 1}
	rule := shared.Vec4{0.055, 0.067, 0.088, 1}
	top := editor_ui_create_box(
		world,
		EDITOR_UI_TOP_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{
			size = {1280, EDITOR_TOP_BAR_HEIGHT},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	_ = editor_ui_create_box(
		world,
		"__scrapbot_editor_signal_rail",
		EDITOR_UI_TOP_NAME,
		.None,
		{position = {14, 13}, size = {3, 26}, background = mint, corner_radius = 1.5},
	)
	brand := editor_ui_create_box(
		world,
		"__scrapbot_editor_brand",
		EDITOR_UI_TOP_NAME,
		.None,
		{position = {23, 10}, size = {110, 30}},
	)
	editor_ui_add_text(world, brand, "SCRAPBOT", text, EDITOR_TEXT_SIZE)
	subtitle := editor_ui_create_box(
		world,
		"__scrapbot_editor_subtitle",
		EDITOR_UI_TOP_NAME,
		.None,
		{position = {132, 14}, size = {240, 24}},
	)
	editor_ui_add_text(world, subtitle, "EDITOR  /  LIVE PROJECT", muted, EDITOR_TEXT_SIZE)
	tool_hint := editor_ui_create_box(
		world,
		"__scrapbot_editor_tool_hint",
		EDITOR_UI_TOP_NAME,
		.None,
		{
			position = {480, 11},
			size = {320, 30},
			padding = {8, 14, 6, 14},
			background = raised,
			border_color = rule,
			border_width = 1,
			corner_radius = 4,
		},
	)
	editor_ui_add_text(
		world,
		tool_hint,
		"W  MOVE     E  ROTATE     R  SCALE",
		muted,
		EDITOR_TEXT_SIZE,
	)
	_ = top

	workspace := editor_ui_create_box(
		world,
		EDITOR_UI_WORKSPACE_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{position = {0, EDITOR_TOP_BAR_HEIGHT}, size = {1280, 638}},
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
			background = panel,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_vstack(world, left, {fill = true})
	systems := editor_ui_create_box(
		world,
		EDITOR_UI_SYSTEMS_NAME,
		EDITOR_UI_LEFT_NAME,
		.Systems_Scroll,
		{
			size = {EDITOR_LEFT_SIDEBAR_WIDTH, 178},
			padding = {8, 10, 9, 10},
			background = panel,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_panel(
		world,
		systems,
		{
			title = "SYSTEMS / 0",
			title_color = text,
			title_background = raised,
			title_size = EDITOR_TEXT_SIZE,
			title_height = 34,
		},
	)
	editor_ui_add_table(world, systems, {columns = 2, column_gap = 8, row_gap = 2})
	editor_ui_add_scroll(world, systems)
	left_header := editor_ui_create_box(
		world,
		"__scrapbot_editor_left_header",
		EDITOR_UI_LEFT_NAME,
		.None,
		{
			size = {EDITOR_LEFT_SIDEBAR_WIDTH, 72},
			padding = {17, 18, 9, 18},
			background = raised,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_text(world, left_header, "SCENE", text, EDITOR_TEXT_SIZE)
	counts := editor_ui_create_box(
		world,
		EDITOR_UI_BROWSER_HEADER_NAME,
		"__scrapbot_editor_left_header",
		.Browser_Header,
		{position = {0, 31}, size = {2000, 18}},
	)
	editor_ui_add_text(world, counts, "0 SCENE / 0 LIVE", muted, EDITOR_TEXT_SIZE)
	// The count label deliberately has a generous authored width so it never
	// reflows, but the header must contain it when the sidebar is narrowed.
	editor_ui_add_scroll(world, left_header)
	browser := editor_ui_create_box(
		world,
		EDITOR_UI_BROWSER_NAME,
		EDITOR_UI_LEFT_NAME,
		.Browser_Scroll,
		{size = {EDITOR_LEFT_SIDEBAR_WIDTH, 388}, padding = {7, 9, 7, 9}, background = panel},
	)
	editor_ui_add_vstack(world, browser, {gap = 0})
	editor_ui_add_scroll(world, browser)

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
		.None,
		{
			size = {EDITOR_RIGHT_SIDEBAR_WIDTH, 638},
			background = panel,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_vstack(world, right, {fill = true})
	right_header := editor_ui_create_box(
		world,
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		EDITOR_UI_RIGHT_NAME,
		.None,
		{
			size = {EDITOR_RIGHT_SIDEBAR_WIDTH, 110},
			padding = {17, 18, 9, 18},
			background = raised,
			border_color = rule,
			border_width = 1,
		},
	)
	editor_ui_add_text(world, right_header, "INSPECTOR", text, EDITOR_TEXT_SIZE)
	inspector_header := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_identity",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Header,
		{position = {0, 35}, size = {2000, 58}},
	)
	editor_ui_add_text(
		world,
		inspector_header,
		"Select an entity to inspect",
		muted,
		EDITOR_TEXT_SIZE,
	)
	inspector := editor_ui_create_box(
		world,
		EDITOR_UI_INSPECTOR_NAME,
		EDITOR_UI_RIGHT_NAME,
		.Inspector_Scroll,
		{size = {EDITOR_RIGHT_SIDEBAR_WIDTH, 528}, padding = {12, 14, 12, 14}, background = panel},
	)
	editor_ui_add_scroll(world, inspector)
	content := editor_ui_create_box(
		world,
		EDITOR_UI_INSPECTOR_CONTENT_NAME,
		EDITOR_UI_INSPECTOR_NAME,
		.Inspector_Content,
		{size = {332, 500}},
	)
	editor_ui_add_vstack(world, content, {gap = 10})

	status := editor_ui_create_box(
		world,
		EDITOR_UI_STATUS_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		{
			position = {0, 692},
			size = {1280, EDITOR_STATUS_BAR_HEIGHT},
			background = void,
			border_color = rule,
			border_width = 1,
		},
	)
	status_text := editor_ui_create_box(
		world,
		"__scrapbot_editor_status_text",
		EDITOR_UI_STATUS_NAME,
		.Status,
		{position = {14, 7}, size = {600, 18}},
	)
	editor_ui_add_text(world, status_text, "RUNNING", mint, EDITOR_TEXT_SIZE)
	status_hint := editor_ui_create_box(
		world,
		"__scrapbot_editor_status_hint",
		EDITOR_UI_STATUS_NAME,
		.None,
		{position = {430, 7}, size = {520, 18}},
	)
	editor_ui_add_text(
		world,
		status_hint,
		"RMB + WASD / SPACE / CTRL  FLY     CTRL+ESC  CLOSE EDITOR",
		quiet,
		EDITOR_TEXT_SIZE,
	)
	_ = status
	_ = editor_ui_create_box(world, EDITOR_UI_ROOT_NAME, "", .Root, {size = {1280, 720}})
}

editor_ui_update_shell_size :: proc(world: ^shared.World, width, height: f32) {
	root, root_ok := editor_ui_entity(world, .Root)
	if !root_ok { return }
	world.ui_layouts[world.entities[root].ui_layout_index].size = {width, height}
	names := [3]string{EDITOR_UI_TOP_NAME, EDITOR_UI_WORKSPACE_NAME, EDITOR_UI_STATUS_NAME}
	for name in names {
		for &entity, entity_index in world.entities {
			if entity.name != name { continue }
			layout := &world.ui_layouts[entity.ui_layout_index]
			layout.size.x = width
			if name ==
			   EDITOR_UI_WORKSPACE_NAME { layout.size.y = max(height - EDITOR_TOP_BAR_HEIGHT - EDITOR_STATUS_BAR_HEIGHT, 0) }
			if name ==
			   EDITOR_UI_STATUS_NAME { layout.position.y = max(height - EDITOR_STATUS_BAR_HEIGHT, 0) }
			break
		}
	}
	responsive := [2]struct {
		name: string,
		minimum_width: f32,
	}{{"__scrapbot_editor_tool_hint", 900}, {"__scrapbot_editor_status_hint", 1000}}
	for item in responsive {
		for &entity, entity_index in world.entities {
			if !entity.alive || entity.origin != .Editor || entity.name != item.name { continue }
			if entity.ui_layout_index >= 0 && entity.ui_layout_index < len(world.ui_layouts) {
				editor_ui_set_hidden(world, entity_index, width < item.minimum_width)
			}
			break
		}
	}
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
		EDITOR_UI_BROWSER_NAME,
		.Browser_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}, corner_radius = 3},
		slot,
	)
	editor_ui_add_button(world, row)
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

SYSTEM_PROFILE_CELL_HEIGHT :: f32(24)

editor_ui_ensure_system_cells :: proc(world: ^shared.World, slot: int) -> (int, int) {
	name_cell, name_found := editor_ui_entity(world, .Systems_Name, slot)
	time_cell, time_found := editor_ui_entity(world, .Systems_Time, slot)
	if name_found && time_found {
		return name_cell, time_cell
	}
	name := fmt.tprintf("__scrapbot_editor_system_name_%d", slot)
	timing := fmt.tprintf("__scrapbot_editor_system_time_%d", slot)
	name_cell = editor_ui_create_box(
		world,
		name,
		EDITOR_UI_SYSTEMS_NAME,
		.Systems_Name,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {5, 3, 3, 3}},
		slot,
	)
	editor_ui_add_text(world, name_cell, "", {0.82, 0.85, 0.90, 1}, EDITOR_TEXT_SIZE)
	time_cell = editor_ui_create_box(
		world,
		timing,
		EDITOR_UI_SYSTEMS_NAME,
		.Systems_Time,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {5, 3, 3, 3}},
		slot,
	)
	editor_ui_add_text(world, time_cell, "--", {0.42, 0.45, 0.51, 1}, EDITOR_TEXT_SIZE)
	return name_cell, time_cell
}

format_system_profile_time :: proc(average_nanoseconds: f64, sampled: bool) -> string {
	if !sampled {
		return "--"
	}
	if average_nanoseconds >= 1_000_000 {
		return fmt.tprintf("%.2f ms", average_nanoseconds / 1_000_000)
	}
	if average_nanoseconds >= 1_000 {
		return fmt.tprintf("%.1f us", average_nanoseconds / 1_000)
	}
	return fmt.tprintf("%.0f ns", average_nanoseconds)
}

editor_ui_refresh_system_profile :: proc(state: ^State, world: ^shared.World) {
	entry_count := 0
	if state.system_profile != nil {
		entry_count = state.system_profile.entry_count
		luau_index := 0
		for index in 0 ..< entry_count {
			entry := &state.system_profile.entries[index]
			name_cell, time_cell := editor_ui_ensure_system_cells(world, index)
			editor_ui_set_hidden(world, name_cell, false)
			editor_ui_set_hidden(world, time_cell, false)
			name := string(entry.name[:entry.name_length])
			if entry.kind == .Luau {
				luau_index += 1
				name = fmt.tprintf("Luau System %d", luau_index)
			}
			editor_ui_set_text(world, name_cell, name)
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
		if (component.role == .Systems_Name || component.role == .Systems_Time) &&
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

INSPECTOR_PANEL_TITLE_HEIGHT :: f32(30)
INSPECTOR_CELL_HEIGHT :: f32(24)
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
		EDITOR_UI_INSPECTOR_CONTENT_NAME,
		.Inspector_Panel,
		{
			size = {332, 70},
			padding = {10, 12, 12, 12},
			background = {0.019, 0.024, 0.032, 1},
			border_color = {0.055, 0.067, 0.088, 1},
			border_width = 1,
			corner_radius = 5,
		},
		slot,
	)
	editor_ui_add_panel(
		world,
		panel,
		{
			title = "COMPONENT",
			title_color = {0.86, 0.88, 0.92, 1},
			title_background = {0.027, 0.035, 0.046, 1},
			title_size = EDITOR_TEXT_SIZE,
			title_height = INSPECTOR_PANEL_TITLE_HEIGHT,
		},
	)
	editor_ui_add_vstack(world, panel, {})
	table = editor_ui_create_box(
		world,
		table_name,
		panel_name,
		.Inspector_Table,
		{size = {308, INSPECTOR_CELL_HEIGHT}},
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
		editor_ui_add_hstack(world, cell, {gap = 4, fill = true})
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
	editor_ui_add_input(
		world,
		input,
		{
			color = {0.82, 0.84, 0.88, 1},
			size = EDITOR_TEXT_SIZE,
			selection_background = {0.08, 0.48, 0.40, 0.48},
			focus_border_color = {0.12, 0.78, 0.66, 1},
		},
	)
	return input
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
	row_count: int,
	content_height: f32,
}

editor_ui_set_numeric_metadata :: proc(
	role: ^shared.Editor_UI_Component,
	field: shared.Editor_Inspector_Field,
) {
	if role == nil { return }
	role.numeric = field != .None
	role.numeric_step = 0.1
	role.numeric_min = 0
	role.numeric_max = 0
	role.numeric_has_min = false
	role.numeric_has_max = false
	#partial switch field {
		case .Transform_Rotation, .Transform_Scale:
			role.numeric_step = 0.01
		case .Camera_Fov:
			role.numeric_step = 1
			role.numeric_min = 1
			role.numeric_max = 179
			role.numeric_has_min = true
			role.numeric_has_max = true
		case .Camera_Near, .Camera_Far:
			role.numeric_step = 0.1
			role.numeric_min = 0.001
			role.numeric_has_min = true
		case .Ambient_Color, .Directional_Color, .Point_Color:
			role.numeric_step = 0.01
			role.numeric_min = 0
			role.numeric_max = 1
			role.numeric_has_min = true
			role.numeric_has_max = true
		case .Ambient_Intensity, .Directional_Intensity, .Point_Intensity, .Point_Range:
			role.numeric_min = 0
			role.numeric_has_min = true
	}
}

editor_ui_finish_inspector_component :: proc(builder: ^Inspector_ECS_Builder) {
	if builder.panel_entity < 0 { return }
	table_layout := &builder.world.ui_layouts[builder.world.entities[builder.table_entity].ui_layout_index]
	panel_layout := &builder.world.ui_layouts[builder.world.entities[builder.panel_entity].ui_layout_index]
	if builder.row_count == 0 {
		editor_ui_set_hidden(builder.world, builder.table_entity, true)
		table_layout.size.y = 1
	} else {
		editor_ui_set_hidden(builder.world, builder.table_entity, false)
		table_layout.size.y =
			f32(builder.row_count) * INSPECTOR_CELL_HEIGHT +
			f32(max(builder.row_count - 1, 0)) * INSPECTOR_TABLE_ROW_GAP
	}
	panel_layout.size.y =
		panel_layout.padding.x +
		INSPECTOR_PANEL_TITLE_HEIGHT +
		table_layout.size.y +
		panel_layout.padding.z
	if builder.panel_count > 1 { builder.content_height += INSPECTOR_PANEL_GAP }
	builder.content_height += panel_layout.size.y
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
			if value_input.text != value {
				delete(value_input.text)
				value_input.text = editor_ui_clone_string(value)
			}
		}
		role := &builder.world.editor_uis[builder.world.entities[input_entity].editor_ui_index]
		role.target = builder.target
		role.inspector_field = field
		role.inspector_axis = .None
		if len(values) == 3 { role.inspector_axis = shared.Editor_Inspector_Axis(value_index + 1) }
		role.custom_storage_index = custom_storage_index
		role.custom_field_index = custom_field_index
		editor_ui_set_numeric_metadata(role, field)
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
			case:
		}
	}
	content_layout := &builder.world.ui_layouts[builder.world.entities[builder.content_entity].ui_layout_index]
	content_layout.size.y = max(builder.content_height, 1)
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
		editor_ui_inspector_field(&builder, "enabled", "true")
	}
	if entity.has_shadow_receiver {
		editor_ui_begin_inspector_component(&builder, "SHADOW RECEIVER")
		editor_ui_inspector_field(&builder, "enabled", "true")
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
		editor_ui_inspector_field(&builder, "hidden", fmt.tprintf("%v", value.hidden))
	}
	if entity.ui_hstack_index >= 0 && entity.ui_hstack_index < len(world.ui_hstacks) {
		value := world.ui_hstacks[entity.ui_hstack_index]
		editor_ui_begin_inspector_component(&builder, "UI HSTACK")
		editor_ui_inspector_field(&builder, "gap", fmt.tprintf("%.2f", value.gap))
		editor_ui_inspector_field(&builder, "fill", fmt.tprintf("%v", value.fill))
		editor_ui_inspector_field(&builder, "draggable", fmt.tprintf("%v", value.draggable))
		editor_ui_inspector_field(&builder, "min size", fmt.tprintf("%.2f", value.min_size))
	}
	if entity.ui_vstack_index >= 0 && entity.ui_vstack_index < len(world.ui_vstacks) {
		value := world.ui_vstacks[entity.ui_vstack_index]
		editor_ui_begin_inspector_component(&builder, "UI VSTACK")
		editor_ui_inspector_field(&builder, "gap", fmt.tprintf("%.2f", value.gap))
		editor_ui_inspector_field(&builder, "fill", fmt.tprintf("%v", value.fill))
		editor_ui_inspector_field(&builder, "draggable", fmt.tprintf("%v", value.draggable))
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
	}
	if entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels) {
		value := world.ui_panels[entity.ui_panel_index]
		editor_ui_begin_inspector_component(&builder, "UI PANEL")
		editor_ui_inspector_field(&builder, "title", value.title)
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
	}
	if entity.ui_table_index >= 0 && entity.ui_table_index < len(world.ui_tables) {
		value := world.ui_tables[entity.ui_table_index]
		editor_ui_begin_inspector_component(&builder, "UI TABLE")
		editor_ui_inspector_field(&builder, "columns", fmt.tprintf("%d", value.columns))
		editor_ui_inspector_field(&builder, "column gap", fmt.tprintf("%.2f", value.column_gap))
		editor_ui_inspector_field(&builder, "row gap", fmt.tprintf("%.2f", value.row_gap))
	}
	if entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts) {
		value := world.ui_texts[entity.ui_text_index]
		editor_ui_begin_inspector_component(&builder, "UI TEXT")
		editor_ui_inspector_field(&builder, "text", value.text)
		editor_ui_inspector_field(&builder, "color", format_vec4(value.color))
		editor_ui_inspector_field(&builder, "size", fmt.tprintf("%.2f", value.size))
	}
	if entity.ui_button_index >= 0 && entity.ui_button_index < len(world.ui_buttons) {
		value := world.ui_buttons[entity.ui_button_index]
		editor_ui_begin_inspector_component(&builder, "UI BUTTON")
		editor_ui_inspector_field(&builder, "text", value.text)
		editor_ui_inspector_field(&builder, "color", format_vec4(value.color))
		editor_ui_inspector_field(&builder, "size", fmt.tprintf("%.2f", value.size))
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
	scene_count, runtime_count, visible_count := 0, 0, 0
	entity_count := len(world.entities)
	for entity_index in 0 ..< entity_count {
		entity := world.entities[entity_index]
		if !entity.alive || entity.origin == .Editor { continue }
		if entity.origin == .Scene { scene_count += 1 } else { runtime_count += 1 }
		row, label := editor_ui_ensure_row(world, visible_count)
		world.entities[row].alive = true
		world.entities[label].alive = true
		editor_ui_set_hidden(world, row, false)
		editor_ui_set_hidden(world, label, false)
		world.editor_uis[world.entities[row].editor_ui_index].target = entity.id
		world.editor_uis[world.entities[label].editor_ui_index].target = entity.id
		row_layout := &world.ui_layouts[world.entities[row].ui_layout_index]
		row_layout.background = {}
		row_layout.border_color = {}
		row_layout.border_width = 0
		if state.editor_has_selection && state.editor_selected_entity == entity.id {
			row_layout.background = {0.025, 0.034, 0.045, 1}
			row_layout.border_color = {0.06, 0.72, 0.63, 0.75}
			row_layout.border_width = 1
		}
		label_text := &world.ui_texts[world.entities[label].ui_text_index]
		label_text.color = {0.82, 0.85, 0.90, 1}
		if entity.origin == .Runtime { label_text.color = {0.54, 0.57, 0.63, 1} }
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
	if header, found := editor_ui_entity(world, .Browser_Header);
	   found { editor_ui_set_text(world, header, fmt.tprintf("%d SCENE / %d LIVE", scene_count, runtime_count)) }
	if status, found := editor_ui_entity(world, .Status);
	   found { editor_ui_set_text(world, status, fmt.tprintf("RUNNING  /  %d ENTITIES", visible_count)) }

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

reconcile_editor_ui_world :: proc(state: ^State, world: ^shared.World, width, height: f32) {
	if state == nil || world == nil || !state.editor_visible { return }
	editor_ui_create_shell(world)
	editor_ui_update_shell_size(world, width, height)
	if !state.editor_snapshot_valid ||
	   !state.editor_snapshot_was_visible { refresh_editor_ecs_snapshot(state, world) }
}

editor_ui_fit_inspector_width :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || world == nil || !state.editor_visible { return false }
	inspector_width := f32(0)
	for node in state.nodes[:state.node_count] {
		if node.origin != .Editor || node.editor_role != .Inspector_Scroll { continue }
		layout := world.ui_layouts[node.layout_index]
		inspector_width = max(node.rect.width - layout.padding.w - layout.padding.y, 1)
		break
	}
	if inspector_width <= 0 { return false }
	changed := false
	for component in world.editor_uis {
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) { continue }
		layout := &world.ui_layouts[entity.ui_layout_index]
		width := layout.size.x
		#partial switch component.role {
			case .Inspector_Content, .Inspector_Panel:
				width = inspector_width
			case .Inspector_Table:
				parent_index := find_parent_entity(world, layout.parent, .Editor)
				if parent_index >= 0 {
					parent_layout := world.ui_layouts[world.entities[parent_index].ui_layout_index]
					width = max(
						inspector_width - parent_layout.padding.w - parent_layout.padding.y,
						1,
					)
				}
			case:
				continue
		}
		if math.abs(layout.size.x - width) > 0.01 { layout.size.x = width; changed = true }
	}
	return changed
}
