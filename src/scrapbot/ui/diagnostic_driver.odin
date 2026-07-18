package ui

import shared "../shared"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

DIAGNOSTIC_DRIVER_SCHEMA_VERSION :: 1
DIAGNOSTIC_DRIVER_DEFAULT_TIMEOUT_FRAMES :: 120

Diagnostic_Target :: struct {
	uuid: string,
	name: string,
	text: string,
	origin: string,
	part: string,
	occurrence: int,
}

Diagnostic_Action :: struct {
	action: string,
	target: Diagnostic_Target,
	expect: string,
	text: string,
	key: string,
	frames: int,
	wheel_y: f32,
	delta_x: f32,
	delta_y: f32,
	padding: f32,
}

Diagnostic_Script :: struct {
	schema_version: int,
	timeout_frames: int,
	actions: []Diagnostic_Action,
}

Diagnostic_Driver :: struct {
	script: Diagnostic_Script,
	source: []u8,
	action_index: int,
	phase: int,
	wait_remaining: int,
	missing_frames: int,
	complete: bool,
	last_pointer: Pointer_Input,
	has_capture_target: bool,
	capture_target: Diagnostic_Target,
	capture_padding: f32,
	drawable_width: f32,
	drawable_height: f32,
}

Diagnostic_Rect :: struct {
	x, y, width, height: f32,
}

Diagnostic_Node_Dump :: struct {
	uuid: string,
	name: string,
	origin: string,
	role: int,
	parent_uuid: string,
	text: string,
	logical_rect: Diagnostic_Rect,
	screen_rect: Diagnostic_Rect,
	visible_screen_rect: Diagnostic_Rect,
	clip: Diagnostic_Rect,
	paint_order: int,
	visible: bool,
	hovered: bool,
	active: bool,
	focused: bool,
	has_layout: bool,
	has_hstack: bool,
	has_vstack: bool,
	has_scroll_area: bool,
	has_panel: bool,
	has_table: bool,
	has_list: bool,
	has_progress: bool,
	has_text: bool,
	has_button: bool,
	has_input: bool,
	has_checkbox: bool,
}

Diagnostic_Tree_Dump :: struct {
	schema_version: int,
	drawable_width: f32,
	drawable_height: f32,
	editor_visible: bool,
	driver_action_index: int,
	driver_action_count: int,
	driver_action: string,
	driver_target: Diagnostic_Target,
	driver_complete: bool,
	nodes: []Diagnostic_Node_Dump,
}

diagnostic_driver_load :: proc(driver: ^Diagnostic_Driver, path: string) -> string {
	if driver == nil {
		return "UI diagnostic driver is unavailable"
	}
	diagnostic_driver_destroy(driver)
	source, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read UI diagnostic script %q: %v", path, read_err)
	}
	driver.source = source
	if unmarshal_err := json.unmarshal(source, &driver.script); unmarshal_err != nil {
		diagnostic_driver_destroy(driver)
		return fmt.tprintf("failed to parse UI diagnostic script %q", path)
	}
	if driver.script.schema_version != DIAGNOSTIC_DRIVER_SCHEMA_VERSION {
		diagnostic_driver_destroy(driver)
		return fmt.tprintf(
			"unsupported UI diagnostic script schema_version %d",
			driver.script.schema_version,
		)
	}
	if len(driver.script.actions) == 0 {
		diagnostic_driver_destroy(driver)
		return "UI diagnostic script must contain at least one action"
	}
	if driver.script.timeout_frames <= 0 {
		driver.script.timeout_frames = DIAGNOSTIC_DRIVER_DEFAULT_TIMEOUT_FRAMES
	}
	for action, index in driver.script.actions {
		if !diagnostic_action_is_valid(action) {
			diagnostic_driver_destroy(driver)
			return fmt.tprintf("UI diagnostic action %d is invalid", index)
		}
	}
	return ""
}

diagnostic_driver_destroy :: proc(driver: ^Diagnostic_Driver) {
	if driver == nil {
		return
	}
	if driver.script.actions != nil {
		for action in driver.script.actions {
			delete(action.action)
			delete(action.target.uuid)
			delete(action.target.name)
			delete(action.target.text)
			delete(action.target.origin)
			delete(action.target.part)
			delete(action.expect)
			delete(action.text)
			delete(action.key)
		}
		delete(driver.script.actions)
	}
	if driver.source != nil {
		delete(driver.source)
	}
	driver^ = {}
}

diagnostic_action_is_valid :: proc(action: Diagnostic_Action) -> bool {
	switch action.action {
		case "click", "hover", "scroll", "type", "capture":
			return diagnostic_target_is_valid(action.target)
		case "drag":
			return diagnostic_target_is_valid(action.target) && action.frames >= 0
		case "expect":
			return(
				diagnostic_target_is_valid(action.target) &&
				diagnostic_expectation_is_valid(action.expect) \
			)
		case "wait":
			return action.frames > 0
		case "key":
			return diagnostic_key_is_valid(action.key)
	}
	return false
}

diagnostic_target_is_valid :: proc(target: Diagnostic_Target) -> bool {
	if target.occurrence < 0 {
		return false
	}
	if target.origin != "" &&
	   target.origin != "scene" &&
	   target.origin != "runtime" &&
	   target.origin != "editor" {
		return false
	}
	if target.part != "" && target.part != "panel_action" {
		return false
	}
	if target.uuid != "" {
		_, uuid_ok := shared.entity_uuid_parse(target.uuid)
		if !uuid_ok {
			return false
		}
	}
	return target.uuid != "" || target.name != "" || target.text != ""
}

diagnostic_expectation_is_valid :: proc(expect: string) -> bool {
	switch expect {
		case "visible", "hovered", "active", "focused", "text", "inside_parent":
			return true
	}
	return false
}

diagnostic_key_is_valid :: proc(key: string) -> bool {
	switch key {
		case "left",
		     "right",
		     "up",
		     "down",
		     "home",
		     "end",
		     "backspace",
		     "delete",
		     "tab",
		     "enter",
		     "escape",
		     "select_all",
		     "save",
		     "undo",
		     "redo",
		     "editor_toggle",
		     "run_stop",
		     "pause_step":
			return true
	}
	return false
}

diagnostic_driver_input :: proc(
	driver: ^Diagnostic_Driver,
	state: ^State,
	world: ^shared.World,
	drawable_width, drawable_height: f32,
) -> (
	Pointer_Input,
	Keyboard_Input,
	string,
) {
	if driver == nil {
		return {}, {}, ""
	}
	driver.drawable_width = drawable_width
	driver.drawable_height = drawable_height
	if driver.complete {
		return driver.last_pointer, {}, ""
	}
	if state != nil && world != nil && state.ui_world_uuid != world.instance_uuid {
		// Runtime Stop/Revert can replace the world between input and UI reconciliation.
		// Let the retained tree bind to the new world before resolving semantic targets.
		return driver.last_pointer, {}, ""
	}
	if driver.action_index < 0 || driver.action_index >= len(driver.script.actions) {
		driver.complete = true
		return driver.last_pointer, {}, ""
	}
	action := driver.script.actions[driver.action_index]
	pointer := driver.last_pointer
	keyboard: Keyboard_Input

	switch action.action {
		case "wait":
			if driver.wait_remaining <= 0 {
				driver.wait_remaining = action.frames
			}
			driver.wait_remaining -= 1
			if driver.wait_remaining <= 0 {
				diagnostic_driver_advance(driver)
			}
			return pointer, keyboard, ""
		case "key":
			diagnostic_keyboard_set(&keyboard, action.key)
			diagnostic_driver_advance(driver)
			return pointer, keyboard, ""
		case "expect":
			node_index, found := diagnostic_find_target(state, world, action.target)
			if !found {
				return diagnostic_driver_missing_target(driver, action)
			}
			if err := diagnostic_expect(state, world, node_index, action.expect, action.text);
			   err != "" {
				return {}, {}, fmt.tprintf("UI diagnostic action %d failed: %s", driver.action_index, err)
			}
			diagnostic_driver_advance(driver)
			return pointer, keyboard, ""
	}

	if action.action == "click" && driver.phase == 1 {
		pointer.primary_down = false
		driver.last_pointer = pointer
		diagnostic_driver_advance(driver)
		return pointer, keyboard, ""
	}
	if action.action == "drag" {
		if driver.phase == 1 {
			steps := max(action.frames, 1)
			pointer.position.x += action.delta_x / f32(steps)
			pointer.position.y += action.delta_y / f32(steps)
			pointer.primary_down = true
			driver.last_pointer = pointer
			driver.wait_remaining += 1
			if driver.wait_remaining >= steps {
				driver.phase = 2
			}
			return pointer, keyboard, ""
		}
		if driver.phase == 2 {
			pointer.primary_down = false
			driver.last_pointer = pointer
			diagnostic_driver_advance(driver)
			return pointer, keyboard, ""
		}
	}
	if action.action == "type" {
		if driver.phase == 1 {
			pointer.primary_down = false
			driver.last_pointer = pointer
			driver.phase = 2
			return pointer, keyboard, ""
		}
		if driver.phase == 2 {
			keyboard.text = action.text
			diagnostic_driver_advance(driver)
			return pointer, keyboard, ""
		}
	}

	node_index, found := diagnostic_find_target(state, world, action.target)
	if !found {
		return diagnostic_driver_missing_target(driver, action)
	}
	visible_rect, target_rect_ok := diagnostic_target_rect(state, world, node_index, action.target)
	if !target_rect_ok {
		return diagnostic_driver_missing_target(driver, action)
	}
	if visible_rect.width <= 0 || visible_rect.height <= 0 {
		if diagnostic_reveal_target(state, world, node_index) {
			driver.missing_frames = 0
			return driver.last_pointer, {}, ""
		}
		return diagnostic_driver_missing_target(driver, action)
	}
	driver.missing_frames = 0
	rect := diagnostic_rect_to_screen(
		state,
		state.nodes[node_index],
		visible_rect,
		drawable_width,
		drawable_height,
	)
	pointer = {
		position = {rect.x + rect.width * 0.5, rect.y + rect.height * 0.5},
		available = true,
	}

	switch action.action {
		case "click":
			pointer.primary_down = true
			driver.phase = 1
		case "hover":
			diagnostic_driver_advance(driver)
		case "scroll":
			pointer.wheel_y = action.wheel_y
			diagnostic_driver_advance(driver)
		case "type":
			pointer.primary_down = true
			driver.phase = 1
		case "drag":
			pointer.primary_down = true
			driver.phase = 1
		case "capture":
			driver.has_capture_target = true
			driver.capture_target = action.target
			driver.capture_padding = max(action.padding, 0)
			diagnostic_driver_advance(driver)
	}
	driver.last_pointer = pointer
	return pointer, keyboard, ""
}

diagnostic_driver_missing_target :: proc(
	driver: ^Diagnostic_Driver,
	action: Diagnostic_Action,
) -> (
	Pointer_Input,
	Keyboard_Input,
	string,
) {
	driver.missing_frames += 1
	if driver.missing_frames < driver.script.timeout_frames {
		return driver.last_pointer, {}, ""
	}
	return {}, {}, fmt.tprintf("UI diagnostic action %d timed out waiting for %s", driver.action_index, diagnostic_target_description(action.target))
}

diagnostic_driver_advance :: proc(driver: ^Diagnostic_Driver) {
	driver.action_index += 1
	driver.phase = 0
	driver.wait_remaining = 0
	driver.missing_frames = 0
	driver.last_pointer.wheel_y = 0
	driver.last_pointer.primary_down = false
	if driver.action_index >= len(driver.script.actions) {
		driver.complete = true
	}
}

diagnostic_driver_is_complete :: proc(driver: ^Diagnostic_Driver) -> bool {
	return driver == nil || driver.complete
}

diagnostic_find_target :: proc(
	state: ^State,
	world: ^shared.World,
	target: Diagnostic_Target,
) -> (
	int,
	bool,
) {
	if state == nil || world == nil {
		return -1, false
	}
	wanted_uuid: shared.Entity_UUID
	has_uuid := false
	if target.uuid != "" {
		wanted_uuid, has_uuid = shared.entity_uuid_parse(target.uuid)
		if !has_uuid {
			return -1, false
		}
	}
	wanted_occurrence := max(target.occurrence, 0)
	occurrence := 0
	for node, node_index in state.nodes[:state.node_count] {
		entity_index := int(node.entity.index)
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive || entity.id != node.entity || !node.laid_out {
			continue
		}
		if has_uuid && entity.uuid != wanted_uuid {
			continue
		}
		if target.name != "" && entity.name != target.name {
			continue
		}
		if target.text != "" && diagnostic_node_text(world, node) != target.text {
			continue
		}
		if target.origin != "" && diagnostic_origin_name(entity.origin) != target.origin {
			continue
		}
		if occurrence == wanted_occurrence {
			return node_index, true
		}
		occurrence += 1
	}
	return -1, false
}

diagnostic_node_text :: proc(world: ^shared.World, node: Node) -> string {
	if node.button_index >= 0 && node.button_index < len(world.ui_buttons) {
		return world.ui_buttons[node.button_index].text
	}
	if node.text_index >= 0 && node.text_index < len(world.ui_texts) {
		return world.ui_texts[node.text_index].text
	}
	if node.input_index >= 0 && node.input_index < len(world.ui_inputs) {
		return world.ui_inputs[node.input_index].text
	}
	if node.panel_index >= 0 && node.panel_index < len(world.ui_panels) {
		return world.ui_panels[node.panel_index].title
	}
	return ""
}

diagnostic_origin_name :: proc(origin: shared.Entity_Origin) -> string {
	switch origin {
		case .Scene:
			return "scene"
		case .Runtime:
			return "runtime"
		case .Editor:
			return "editor"
	}
	return "unknown"
}

diagnostic_node_screen_rect :: proc(
	state: ^State,
	node: Node,
	drawable_width, drawable_height: f32,
) -> Rect {
	return diagnostic_rect_to_screen(state, node, node.rect, drawable_width, drawable_height)
}

diagnostic_rect_to_screen :: proc(
	state: ^State,
	node: Node,
	rect: Rect,
	drawable_width, drawable_height: f32,
) -> Rect {
	if node.origin == .Editor {
		scale := max(state.editor_pixel_density, 1)
		return {rect.x * scale, rect.y * scale, rect.width * scale, rect.height * scale}
	}
	viewport := editor_viewport(state, drawable_width, drawable_height)
	scale_x := viewport.width / 1280
	scale_y := viewport.height / 720
	return {
		viewport.x + rect.x * scale_x,
		viewport.y + rect.y * scale_y,
		rect.width * scale_x,
		rect.height * scale_y,
	}
}

diagnostic_node_visible_rect :: proc(node: Node) -> Rect {
	if node.has_clip {
		return rect_intersection(node.rect, node.clip)
	}
	return node.rect
}

diagnostic_target_rect :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	target: Diagnostic_Target,
) -> (
	Rect,
	bool,
) {
	if state == nil || world == nil || node_index < 0 || node_index >= state.node_count {
		return {}, false
	}
	node := state.nodes[node_index]
	if target.part == "panel_action" {
		panel_entity_index := int(node.entity.index)
		for &child in state.nodes[:state.node_count] {
			if child.parent_entity_index != panel_entity_index ||
			   !node_is_panel_action(world, &child) {
				continue
			}
			rect := diagnostic_node_visible_rect(child)
			return rect, rect.width > 0 && rect.height > 0
		}
		return {}, false
	}
	rect := diagnostic_node_visible_rect(node)
	return rect, rect.width > 0 && rect.height > 0
}

diagnostic_reveal_target :: proc(state: ^State, world: ^shared.World, node_index: int) -> bool {
	if state == nil || world == nil || node_index < 0 || node_index >= state.node_count {
		return false
	}
	target := state.nodes[node_index].rect
	ancestor_entity_index := state.nodes[node_index].parent_entity_index
	for ancestor_entity_index >= 0 {
		ancestor_node_index := find_node_by_entity_index(state, ancestor_entity_index)
		if ancestor_node_index < 0 {
			break
		}
		ancestor := &state.nodes[ancestor_node_index]
		if ancestor.scroll_area_index >= 0 &&
		   ancestor.scroll_area_index < len(world.ui_scroll_areas) {
			layout := world.ui_layouts[ancestor.layout_index]
			viewport_top := ancestor.rect.y + layout.padding.x
			viewport_bottom := ancestor.rect.y + ancestor.rect.height - layout.padding.z
			delta := f32(0)
			if target.y < viewport_top {
				delta = target.y - viewport_top
			} else if target.y + target.height > viewport_bottom {
				delta = target.y + target.height - viewport_bottom
			}
			if delta != 0 {
				ancestor.scroll_target = clamp(
					ancestor.scroll_target + delta,
					0,
					ancestor.scroll_max,
				)
				ancestor.scroll_offset = ancestor.scroll_target
				state.ui_layout_valid = false
				return true
			}
		}
		ancestor_entity_index = ancestor.parent_entity_index
	}
	return false
}

diagnostic_expect :: proc(
	state: ^State,
	world: ^shared.World,
	node_index: int,
	expect, value: string,
) -> string {
	node := state.nodes[node_index]
	switch expect {
		case "visible":
			if !node.laid_out {
				return "target is not visible"
			}
		case "hovered":
			if !node.hovered {
				return "target is not hovered"
			}
		case "active":
			if !node.active {
				return "target is not active"
			}
		case "focused":
			if !state.has_focused_input || state.focused_input != node.entity {
				return "target is not focused"
			}
		case "text":
			actual := diagnostic_node_text(world, node)
			if actual != value {
				return fmt.tprintf("target text is %q, expected %q", actual, value)
			}
		case "inside_parent":
			parent_index := find_node_by_entity_index(state, node.parent_entity_index)
			if parent_index < 0 ||
			   !diagnostic_rect_contains_rect(state.nodes[parent_index].rect, node.rect) {
				return "target rectangle is outside its parent"
			}
		case:
			return fmt.tprintf("unknown expectation %q", expect)
	}
	return ""
}

diagnostic_keyboard_set :: proc(keyboard: ^Keyboard_Input, key: string) {
	switch key {
		case "left":
			keyboard.left = true
		case "right":
			keyboard.right = true
		case "up":
			keyboard.up = true
		case "down":
			keyboard.down = true
		case "home":
			keyboard.home = true
		case "end":
			keyboard.end = true
		case "backspace":
			keyboard.backspace = true
		case "delete":
			keyboard.delete_forward = true
		case "tab":
			keyboard.tab = true
		case "enter":
			keyboard.enter = true
		case "escape":
			keyboard.escape = true
		case "select_all":
			keyboard.select_all = true
		case "save":
			keyboard.save = true
		case "undo":
			keyboard.undo = true
		case "redo":
			keyboard.redo = true
		case "editor_toggle":
			keyboard.editor_toggle = true
		case "run_stop":
			keyboard.run_stop = true
		case "pause_step":
			keyboard.pause_step = true
	}
}

diagnostic_rect_contains_rect :: proc(outer, inner: Rect) -> bool {
	return(
		inner.x >= outer.x &&
		inner.y >= outer.y &&
		inner.x + inner.width <= outer.x + outer.width &&
		inner.y + inner.height <= outer.y + outer.height \
	)
}

diagnostic_target_description :: proc(target: Diagnostic_Target) -> string {
	if target.uuid != "" {
		return fmt.tprintf("UUID %q", target.uuid)
	}
	if target.name != "" {
		return fmt.tprintf("name %q", target.name)
	}
	return fmt.tprintf("text %q", target.text)
}

diagnostic_driver_capture_rect :: proc(
	driver: ^Diagnostic_Driver,
	state: ^State,
	world: ^shared.World,
	drawable_width, drawable_height: f32,
) -> (
	Rect,
	bool,
) {
	if driver == nil || !driver.has_capture_target {
		return {}, false
	}
	node_index, found := diagnostic_find_target(state, world, driver.capture_target)
	if !found {
		return {}, false
	}
	visible_rect, rect_ok := diagnostic_target_rect(
		state,
		world,
		node_index,
		driver.capture_target,
	)
	if !rect_ok {
		return {}, false
	}
	rect := diagnostic_rect_to_screen(
		state,
		state.nodes[node_index],
		visible_rect,
		drawable_width,
		drawable_height,
	)
	padding := driver.capture_padding
	return {
			rect.x - padding,
			rect.y - padding,
			rect.width + padding * 2,
			rect.height + padding * 2,
		},
		true
}

diagnostic_driver_write_dump :: proc(
	path: string,
	state: ^State,
	world: ^shared.World,
	drawable_width, drawable_height: f32,
	driver: ^Diagnostic_Driver = nil,
) -> string {
	if path == "" {
		return ""
	}
	if state == nil || world == nil {
		return "cannot dump an unavailable UI tree"
	}
	nodes := make([dynamic]Diagnostic_Node_Dump, 0, state.node_count)
	owned_strings := make([dynamic]string, 0, state.node_count * 2)
	defer {
		for value in owned_strings {
			delete(value)
		}
		delete(owned_strings)
		delete(nodes)
	}
	for node in state.nodes[:state.node_count] {
		entity_index := int(node.entity.index)
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive || entity.id != node.entity {
			continue
		}
		uuid_buffer: [36]u8
		uuid := strings.clone(shared.entity_uuid_to_string(entity.uuid, uuid_buffer[:]))
		append(&owned_strings, uuid)
		parent_uuid := ""
		if node.parent_entity_index >= 0 && node.parent_entity_index < len(world.entities) {
			parent_buffer: [36]u8
			parent_uuid = strings.clone(
				shared.entity_uuid_to_string(
					world.entities[node.parent_entity_index].uuid,
					parent_buffer[:],
				),
			)
			append(&owned_strings, parent_uuid)
		}
		screen_rect := diagnostic_node_screen_rect(state, node, drawable_width, drawable_height)
		visible_screen_rect := diagnostic_rect_to_screen(
			state,
			node,
			diagnostic_node_visible_rect(node),
			drawable_width,
			drawable_height,
		)
		append(
			&nodes,
			Diagnostic_Node_Dump {
				uuid = uuid,
				name = entity.name,
				origin = diagnostic_origin_name(entity.origin),
				role = int(node.editor_role),
				parent_uuid = parent_uuid,
				text = diagnostic_node_text(world, node),
				logical_rect = diagnostic_rect(node.rect),
				screen_rect = diagnostic_rect(screen_rect),
				visible_screen_rect = diagnostic_rect(visible_screen_rect),
				clip = diagnostic_rect(node.clip),
				paint_order = node.paint_order,
				visible = node.laid_out,
				hovered = node.hovered,
				active = node.active,
				focused = state.has_focused_input && state.focused_input == node.entity,
				has_layout = node.layout_index >= 0,
				has_hstack = node.hstack_index >= 0,
				has_vstack = node.vstack_index >= 0,
				has_scroll_area = node.scroll_area_index >= 0,
				has_panel = node.panel_index >= 0,
				has_table = node.table_index >= 0,
				has_list = node.list_index >= 0,
				has_progress = node.progress_index >= 0,
				has_text = node.text_index >= 0,
				has_button = node.button_index >= 0,
				has_input = node.input_index >= 0,
				has_checkbox = node.checkbox_index >= 0,
			},
		)
	}
	dump := Diagnostic_Tree_Dump {
		schema_version = DIAGNOSTIC_DRIVER_SCHEMA_VERSION,
		drawable_width = drawable_width,
		drawable_height = drawable_height,
		editor_visible = state.editor_visible,
		nodes = nodes[:],
	}
	if driver != nil {
		dump.driver_action_index = driver.action_index
		dump.driver_action_count = len(driver.script.actions)
		dump.driver_complete = driver.complete
		if driver.action_index >= 0 && driver.action_index < len(driver.script.actions) {
			action := driver.script.actions[driver.action_index]
			dump.driver_action = action.action
			dump.driver_target = action.target
		}
	}
	data, marshal_err := json.marshal(dump)
	if marshal_err != nil {
		return fmt.tprintf("failed to encode UI tree dump: %v", marshal_err)
	}
	defer delete(data)
	if write_err := os.write_entire_file(path, data); write_err != nil {
		return fmt.tprintf("failed to write UI tree dump %q: %v", path, write_err)
	}
	return ""
}

diagnostic_rect :: proc(rect: Rect) -> Diagnostic_Rect {
	return {rect.x, rect.y, rect.width, rect.height}
}
