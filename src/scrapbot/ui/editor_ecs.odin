package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
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
EDITOR_UI_DIAGNOSTICS_NAME :: "__scrapbot_editor_diagnostics"
EDITOR_UI_SYSTEMS_NAME :: "__scrapbot_editor_systems"
EDITOR_UI_SCENE_NAME :: "__scrapbot_editor_scene"
EDITOR_UI_SCENE_TOOLS_NAME :: "__scrapbot_editor_scene_tools"
EDITOR_UI_RESOURCES_NAME :: "__scrapbot_editor_resources"
EDITOR_UI_RESOURCE_TOOLS_NAME :: "__scrapbot_editor_resource_tools"
EDITOR_UI_VIEWPORT_NAME :: "__scrapbot_editor_viewport"
EDITOR_UI_GIZMO_TOOLBAR_NAME :: "__scrapbot_editor_gizmo_toolbar"
EDITOR_UI_RIGHT_NAME :: "__scrapbot_editor_right"
EDITOR_UI_RIGHT_CONTENT_NAME :: "__scrapbot_editor_right_content"
EDITOR_UI_INSPECTOR_HEADER_NAME :: "__scrapbot_editor_inspector_header"
EDITOR_UI_STATUS_NAME :: "__scrapbot_editor_status"
EDITOR_UI_COMPONENT_MENU_NAME :: "__scrapbot_editor_component_menu"
EDITOR_UI_COMPONENT_MENU_CONTENT_NAME :: "__scrapbot_editor_component_menu_content"
EDITOR_UI_RESOURCE_MENU_NAME :: "__scrapbot_editor_resource_menu"
EDITOR_UI_RESOURCE_MENU_CONTENT_NAME :: "__scrapbot_editor_resource_menu_content"
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
EDITOR_CHROME_BACKGROUND :: shared.Vec4{0.004, 0.005, 0.007, 1}
EDITOR_CHROME_BORDER :: shared.Vec4{0.055, 0.067, 0.088, 1}
EDITOR_PLAYBACK_TOP_BACKGROUND :: shared.Vec4{0.035, 0.018, 0.007, 1}
EDITOR_PLAYBACK_STATUS_BACKGROUND :: shared.Vec4{0.105, 0.046, 0.010, 1}
EDITOR_PLAYBACK_BORDER :: shared.Vec4{0.94, 0.46, 0.12, 1}
EDITOR_PLAYBACK_TEXT :: shared.Vec4{1.0, 0.73, 0.36, 1}

editor_ui_entity :: proc(
	world: ^shared.World,
	role: shared.Editor_UI_Role,
	slot: int = 0,
) -> (
	int,
	bool,
) {
	key := shared.Editor_UI_Lookup_Key {
		role = role,
		slot = slot,
	}
	if world.editor_ui_by_role_slot != nil {
		if entity_index, found := world.editor_ui_by_role_slot[key]; found {
			if entity_index >= 0 && entity_index < len(world.entities) {
				entity := world.entities[entity_index]
				if entity.alive &&
				   entity.origin == .Editor &&
				   entity.editor_ui_index >= 0 &&
				   entity.editor_ui_index < len(world.editor_uis) {
					component := world.editor_uis[entity.editor_ui_index]
					if component.entity_index == entity_index &&
					   component.role == role &&
					   component.slot == slot {
						return entity_index, true
					}
				}
			}
			delete_key(&world.editor_ui_by_role_slot, key)
		}
	}
	for component, component_index in world.editor_uis {
		if component.role != role || component.slot != slot { continue }
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive ||
		   entity.origin != .Editor ||
		   entity.editor_ui_index != component_index { continue }
		if world.editor_ui_by_role_slot == nil {
			world.editor_ui_by_role_slot = make(map[shared.Editor_UI_Lookup_Key]int)
		}
		world.editor_ui_by_role_slot[key] = component.entity_index
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
			binding := world.editor_uis[entity.editor_ui_index]
			switch binding.role {
				case .Browser_Row_Disclosure:
					if binding.target != (shared.Entity{}) {
						target_index := int(binding.target.index)
						if ecs.entity_is_alive(world, target_index) &&
						   world.entities[target_index].id == binding.target {
							if state.editor_collapsed_entities == nil {
								state.editor_collapsed_entities = make(map[shared.Entity_UUID]bool)
							}
							id := world.entities[target_index].uuid
							state.editor_collapsed_entities[id] = !state.editor_collapsed_entities[id]
							state.editor_snapshot_valid = false
						}
					}
					return
				case .Browser_Row, .Browser_Row_Label:
					_ = editor_select_entity(state, world, binding.target, 0)
					return
				case .Project_Resource_Row, .Project_Resource_Row_Label:
					if binding.resource_id != (shared.Resource_UUID{}) {
						state.editor_selected_resource = binding.resource_id
						state.editor_has_resource_selection = true
						state.editor_has_selection = false
						state.editor_snapshot_valid = false
					}
					return
				case .Project_Resource_Create:
					_ = editor_authoring_create_resource(state)
					return
				case .Project_Resource_Duplicate:
					_ = editor_authoring_duplicate_resource(state)
					return
				case .Project_Resource_Delete:
					_ = editor_authoring_delete_resource(state, world)
					return
				case .Project_Resource_Find_Usage:
					_ = editor_select_first_resource_usage(
						state,
						world,
						state.editor_selected_resource,
					)
					return
				case .Project_Resource_Reimport:
					editor_request_resource_reimport(state, state.editor_selected_resource)
					return
				case .Project_Resources_Reimport_All:
					editor_request_resource_reimport(state, {}, true)
					return
				case .Transport_Play:
					editor_play(state)
					return
				case .Transport_Pause:
					if state.editor_simulation_playing {
						editor_pause(state)
					} else if !state.editor_simulation_stopped {
						editor_play(state)
					}
					return
				case .Transport_Stop:
					editor_stop(state)
					return
				case .Transport_Step:
					editor_step(state)
					return
				case .Transport_Undo:
					_ = editor_undo(state, world)
					return
				case .Transport_Redo:
					_ = editor_redo(state, world)
					return
				case .Transport_Save:
					editor_save(state)
					return
				case .Transport_Revert:
					editor_revert(state)
					return
				case .Gizmo_Space_World:
					editor_set_gizmo_space(state, .World)
					return
				case .Gizmo_Space_Local:
					editor_set_gizmo_space(state, .Local)
					return
				case .Entity_Create:
					_, _ = editor_authoring_create_entity(state, world)
					return
				case .Entity_Duplicate:
					if selected, ok := editor_selected_world_index(state, world); ok {
						_, _ = editor_authoring_duplicate_entity(state, world, selected)
					}
					return
				case .Entity_Delete:
					if selected, ok := editor_selected_world_index(state, world); ok {
						_ = editor_authoring_delete_entity(state, world, selected)
					}
					return
				case .Entity_Promote:
					if selected, ok := editor_selected_world_index(state, world); ok {
						_ = editor_authoring_promote_entity(state, world, selected)
					}
					return
				case .Inspector_Component_Menu_Button:
					state.editor_component_menu_open = !state.editor_component_menu_open
					if state.editor_component_menu_open {
						state.editor_snapshot_valid = false
						if selected, ok := editor_selected_world_index(state, world); ok {
							editor_ui_build_component_menu(state, world, selected)
						}
					}
					state.editor_layout_invalidated = true
					if menu, found := editor_ui_entity(world, .Inspector_Component_Menu); found {
						editor_ui_set_hidden(world, menu, !state.editor_component_menu_open)
					}
					return
				case .Inspector_Preview_Reset:
					if viewport, found := editor_ui_entity(
						world,
						.Inspector_Preview_Surface,
						binding.slot,
					); found {
						entity := world.entities[viewport]
						if entity.ui_viewport_index >= 0 &&
						   entity.ui_viewport_index < len(world.ui_viewports) {
							resource := world.ui_viewports[entity.ui_viewport_index].resource
							value := shared.ui_viewport_default()
							value.resource = resource
							_ = ecs.set_ui_viewport(world, viewport, value)
						}
					}
					return
				case .Inspector_Panel_Action:
					if state.component_registry == nil ||
					   binding.reflected_component_id == shared.INVALID_COMPONENT_ID {
						return
					}
					definition, found := component.find_definition_by_id(
						state.component_registry,
						binding.reflected_component_id,
					)
					if found {
						target_index := int(binding.target.index)
						if ecs.entity_is_alive(world, target_index) &&
						   world.entities[target_index].id == binding.target {
							_ = editor_set_registered_component(
								state,
								world,
								target_index,
								&definition,
								false,
							)
						}
					}
					return
				case .Inspector_Component_Menu_Item:
					if selected, ok := editor_selected_world_index(state, world); ok {
						if state.component_registry != nil &&
						   binding.slot >= 0 &&
						   binding.slot < state.component_registry.definition_count {
							definition := &state.component_registry.definitions[binding.slot]
							_ = editor_set_registered_component(
								state,
								world,
								selected,
								definition,
								true,
							)
						}
					}
					state.editor_component_menu_open = false
					state.editor_layout_invalidated = true
					if menu, found := editor_ui_entity(world, .Inspector_Component_Menu); found {
						editor_ui_set_hidden(world, menu, true)
					}
					return
				case .Inspector_Resource_Menu_Button:
					if !state.editor_simulation_stopped {
						return
					}
					state.editor_resource_menu_open = !state.editor_resource_menu_open
					if state.editor_resource_menu_open {
						state.editor_snapshot_valid = false
						editor_ui_build_resource_menu(state, world)
					}
					state.editor_layout_invalidated = true
					if menu, found := editor_ui_entity(world, .Inspector_Resource_Menu); found {
						editor_ui_set_hidden(world, menu, !state.editor_resource_menu_open)
					}
					return
				case .Inspector_Resource_Menu_Item:
					if selected, ok := editor_selected_world_index(state, world); ok {
						_ = editor_authoring_set_material_resource(
							state,
							world,
							selected,
							binding.resource_id,
						)
					}
					state.editor_resource_menu_open = false
					state.editor_layout_invalidated = true
					if menu, found := editor_ui_entity(world, .Inspector_Resource_Menu); found {
						editor_ui_set_hidden(world, menu, true)
					}
					return
				case .Viewport:
					if !state.editor_gizmo_captures_pointer {
						state.editor_pick_requested = true
						state.editor_pick_position = position
					}
					return
				case .None,
				     .Root,
				     .Gizmo_Toolbar,
				     .Diagnostics_Panel,
				     .Diagnostics_Label,
				     .Diagnostics_Value,
				     .Systems_Scroll,
				     .Systems_Row,
				     .Systems_Name,
				     .Systems_Time,
				     .Systems_Origin,
				     .Browser_Scroll,
				     .Project_Resources_Scroll,
				     .Inspector_Header,
				     .Inspector_Entity_Name,
				     .Inspector_Resource_Name,
				     .Inspector_Resource_Source,
				     .Inspector_Scroll,
				     .Inspector_Content,
				     .Inspector_Panel,
				     .Inspector_Table,
				     .Inspector_Cell,
				     .Inspector_Preview_Surface,
				     .Inspector_Preview_Toolbar,
				     .Inspector_Preview_Hint,
				     .Inspector_Input,
				     .Inspector_Checkbox,
				     .Inspector_Component_Menu,
				     .Inspector_Component_Menu_Content,
				     .Inspector_Component_Menu_Group,
				     .Inspector_Resource_Menu,
				     .Inspector_Resource_Menu_Content,
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

editor_hierarchy_binding_target :: proc(
	world: ^shared.World,
	entity: shared.Entity,
	allow_disclosure: bool = false,
) -> (
	shared.Entity,
	bool,
) {
	index := int(entity.index)
	for index >= 0 && index < len(world.entities) {
		candidate := world.entities[index]
		if candidate.editor_ui_index >= 0 && candidate.editor_ui_index < len(world.editor_uis) {
			binding := world.editor_uis[candidate.editor_ui_index]
			if binding.role == .Browser_Row_Disclosure {
				if allow_disclosure {
					return binding.target, binding.target != (shared.Entity{})
				}
				return {}, false
			}
			if binding.role == .Browser_Row || binding.role == .Browser_Row_Label {
				return binding.target, binding.target != (shared.Entity{})
			}
		}
		if candidate.ui_layout_index < 0 || candidate.ui_layout_index >= len(world.ui_layouts) {
			break
		}
		parent := world.ui_layouts[candidate.ui_layout_index].parent
		index, _ = ecs.entity_index_by_uuid(world, parent)
	}
	return {}, false
}

editor_ui_consume_events :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || world == nil {
		return false
	}
	layout_changed := false
	for event in ui_events(state) {
		switch event.kind {
			case .Activated:
				editor_ui_handle_activation(state, world, event.entity, event.position)
			case .Changed:
				if event.part == .Panel_Title {
					editor_ui_handle_panel_change(state, world, event.entity)
				} else {
					editor_ui_handle_checkbox_change(state, world, event.entity)
				}
			case .Dropped:
				list_index := int(event.entity.index)
				if !ecs.entity_is_alive(world, list_index) ||
				   world.entities[list_index].id != event.entity ||
				   world.entities[list_index].editor_ui_index < 0 ||
				   world.entities[list_index].editor_ui_index >= len(world.editor_uis) ||
				   world.editor_uis[world.entities[list_index].editor_ui_index].role !=
					   .Browser_Scroll {
					continue
				}
				source, source_found := editor_hierarchy_binding_target(world, event.source)
				if !source_found {
					continue
				}
				source_index := int(source.index)
				if event.drop_placement == .Before || event.drop_placement == .After {
					if event.target == (shared.Entity{}) {
						continue
					}
					target, target_found := editor_hierarchy_binding_target(
						world,
						event.target,
						true,
					)
					if !target_found {
						continue
					}
					target_index := int(target.index)
					if editor_reorder_entity(
						state,
						world,
						source_index,
						target_index,
						event.drop_placement == .After,
					) {
						layout_changed = true
					}
					continue
				}
				if event.drop_placement != .Into {
					continue
				}
				parent: shared.Entity_UUID
				if event.target != (shared.Entity{}) {
					target, target_found := editor_hierarchy_binding_target(
						world,
						event.target,
						true,
					)
					if !target_found {
						continue
					}
					target_index := int(target.index)
					if !ecs.entity_is_alive(world, target_index) ||
					   world.entities[target_index].id != target {
						continue
					}
					parent = world.entities[target_index].uuid
				}
				if editor_reparent_entity(state, world, source_index, parent) {
					layout_changed = true
				}
		}
	}
	layout_changed = state.editor_layout_invalidated || layout_changed
	state.editor_layout_invalidated = false
	return layout_changed
}

editor_ui_resource_menu_contains :: proc(world: ^shared.World, entity: shared.Entity) -> bool {
	return editor_ui_popup_contains(
		world,
		entity,
		.Inspector_Resource_Menu_Button,
		.Inspector_Resource_Menu,
	)
}

editor_ui_component_menu_contains :: proc(world: ^shared.World, entity: shared.Entity) -> bool {
	return editor_ui_popup_contains(
		world,
		entity,
		.Inspector_Component_Menu_Button,
		.Inspector_Component_Menu,
	)
}

editor_ui_popup_contains :: proc(
	world: ^shared.World,
	entity: shared.Entity,
	button_role, menu_role: shared.Editor_UI_Role,
) -> bool {
	button, button_found := editor_ui_entity(world, button_role)
	menu, menu_found := editor_ui_entity(world, menu_role)
	return button_found && menu_found && popup_contains_entity(world, entity, button, menu)
}

editor_ui_handle_shortcuts :: proc(state: ^State, keyboard: Keyboard_Input) {
	if state == nil {
		return
	}
	if keyboard.editor_toggle {
		editor_toggle(state)
		if !state.editor_visible {
			state.editor_component_menu_open = false
			state.editor_resource_menu_open = false
		}
	}
	if !state.editor_visible ||
	   state.editor_scene_camera_captures_input ||
	   (state.has_focused_input && !state.focused_input_editor) {
		return
	}
	if keyboard.run_stop {
		if state.editor_simulation_playing {
			editor_stop(state)
		} else {
			editor_play(state)
		}
		return
	}
	if keyboard.pause_step {
		if state.editor_simulation_playing {
			editor_pause(state)
		} else {
			editor_step(state)
		}
	}
}

editor_ui_close_component_menu :: proc(state: ^State, world: ^shared.World) {
	if state == nil || !state.editor_component_menu_open {
		return
	}
	editor_ui_close_popup(
		state,
		world,
		&state.editor_component_menu_open,
		.Inspector_Component_Menu,
	)
}

editor_ui_close_resource_menu :: proc(state: ^State, world: ^shared.World) {
	if state == nil || !state.editor_resource_menu_open {
		return
	}
	editor_ui_close_popup(state, world, &state.editor_resource_menu_open, .Inspector_Resource_Menu)
}

editor_ui_close_popup :: proc(
	state: ^State,
	world: ^shared.World,
	open: ^bool,
	menu_role: shared.Editor_UI_Role,
) {
	if state == nil || world == nil || open == nil {
		return
	}
	open^ = false
	state.editor_layout_invalidated = true
	if menu, found := editor_ui_entity(world, menu_role); found {
		editor_ui_set_hidden(world, menu, true)
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
	if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
		if editor_reflected_apply_bool(state, world, binding, checkbox.checked) {
			return
		}
		if reflected, ok := editor_reflected_read_bool(state, world, binding); ok {
			checkbox.checked = reflected
			_ = ecs.set_ui_checkbox(world, entity_index, checkbox)
		}
		return
	}
	transaction, transaction_ok := editor_history_begin_bool_transaction(world, binding)
	if write_inspector_bool(state, world, binding, checkbox.checked) {
		if transaction_ok {
			editor_history_finish_bool_transaction(state, world, transaction)
		}
		return
	}
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
			reflected_field_index = -1,
		},
	)
	world.entities[entity_index].editor_ui_index = role_index
	if world.editor_ui_by_role_slot == nil {
		world.editor_ui_by_role_slot = make(map[shared.Editor_UI_Lookup_Key]int)
	}
	world.editor_ui_by_role_slot[shared.Editor_UI_Lookup_Key{role = role, slot = slot}] =
		entity_index
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
	void := EDITOR_CHROME_BACKGROUND
	rule := EDITOR_CHROME_BORDER
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
		{size = {180, 30}},
	)
	editor_ui_add_text(world, brand, "SCRAPBOT", text, EDITOR_TEXT_SIZE)
	transport := editor_ui_create_box(
		world,
		EDITOR_UI_TRANSPORT_NAME,
		EDITOR_UI_TOP_NAME,
		.None,
		{size = {502, 30}},
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
		"__scrapbot_editor_pause",
		EDITOR_UI_TRANSPORT_NAME,
		"PAUSE",
		.Transport_Pause,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_stop",
		EDITOR_UI_TRANSPORT_NAME,
		"STOP",
		.Transport_Stop,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_step",
		EDITOR_UI_TRANSPORT_NAME,
		"STEP",
		.Transport_Step,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_undo",
		EDITOR_UI_TRANSPORT_NAME,
		"UNDO",
		.Transport_Undo,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_redo",
		EDITOR_UI_TRANSPORT_NAME,
		"REDO",
		.Transport_Redo,
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_save",
		EDITOR_UI_TRANSPORT_NAME,
		"SAVE",
		.Transport_Save,
	)
	revert_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_revert",
		EDITOR_UI_TRANSPORT_NAME,
		"REVERT",
		.Transport_Revert,
	)
	world.ui_layouts[world.entities[revert_button].ui_layout_index].size.x = 68
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
	diagnostics := editor_ui_create_box(
		world,
		EDITOR_UI_DIAGNOSTICS_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.Diagnostics_Panel,
		editor_ui_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 258}),
	)
	diagnostics_layout := &world.ui_layouts[world.entities[diagnostics].ui_layout_index]
	diagnostics_layout.padding = {0, 8, 8, 8}
	diagnostics_layout.min_size.y = 258
	diagnostics_layout.fixed_in_fill = true
	diagnostics_layout.fit_content_height = true
	editor_ui_add_section_panel(world, diagnostics, "PERFORMANCE")
	editor_ui_add_vstack(world, diagnostics, {})
	diagnostics_table := editor_ui_create_box(
		world,
		"__scrapbot_editor_diagnostics_table",
		EDITOR_UI_DIAGNOSTICS_NAME,
		.None,
		{size = {100, 182}, fill_width = true, fit_content_height = true},
	)
	editor_ui_add_table(
		world,
		diagnostics_table,
		{columns = 2, column_gap = 8, row_gap = 0, proportional_columns = true},
	)
	diagnostic_labels := [?]string {
		"FPS",
		"FRAME",
		"GPU FRAME",
		"ENTITIES",
		"DRAW BATCHES",
		"FRUSTUM CULLED",
		"OCCLUSION CULLED",
	}
	for label_text, slot in diagnostic_labels {
		label_name := fmt.tprintf("__scrapbot_editor_diagnostics_label_%d", slot)
		label := editor_ui_create_box(
			world,
			label_name,
			"__scrapbot_editor_diagnostics_table",
			.Diagnostics_Label,
			{size = {1, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {4, 3, 3, 4}},
			slot,
		)
		editor_ui_add_text(world, label, label_text, {0.62, 0.65, 0.71, 1}, EDITOR_TEXT_SIZE)
		value_name := fmt.tprintf("__scrapbot_editor_diagnostics_value_%d", slot)
		value := editor_ui_create_box(
			world,
			value_name,
			"__scrapbot_editor_diagnostics_table",
			.Diagnostics_Value,
			{size = {1, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {4, 3, 3, 4}},
			slot,
		)
		editor_ui_add_text(world, value, "--", {0.82, 0.85, 0.90, 1}, EDITOR_TEXT_SIZE)
		world.ui_texts[world.entities[value].ui_text_index].alignment = .Right
	}
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
			draggable = true,
			drag_threshold = 5,
			drop_edge_fraction = 0.25,
			drop_target_background = {0.055, 0.12, 0.13, 1},
			drop_indicator_color = {0.42, 0.92, 0.84, 1},
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
			tree_enabled = true,
			tree_indent = 14,
		},
	)
	editor_ui_add_scroll(world, scene)
	scene_tools := editor_ui_create_box(
		world,
		EDITOR_UI_SCENE_TOOLS_NAME,
		EDITOR_UI_SCENE_NAME,
		.None,
		{size = {2000, 34}, padding = {2, 6, 2, 6}, background = EDITOR_SECTION_BACKGROUND},
	)
	editor_ui_add_hstack(world, scene_tools, {gap = 4})
	create_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_entity_create",
		EDITOR_UI_SCENE_TOOLS_NAME,
		"+",
		.Entity_Create,
	)
	world.ui_layouts[world.entities[create_button].ui_layout_index].size.x = 32
	duplicate_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_entity_duplicate",
		EDITOR_UI_SCENE_TOOLS_NAME,
		"DUP",
		.Entity_Duplicate,
	)
	world.ui_layouts[world.entities[duplicate_button].ui_layout_index].size.x = 48
	delete_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_entity_delete",
		EDITOR_UI_SCENE_TOOLS_NAME,
		"DEL",
		.Entity_Delete,
	)
	world.ui_layouts[world.entities[delete_button].ui_layout_index].size.x = 42
	promote_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_entity_promote",
		EDITOR_UI_SCENE_TOOLS_NAME,
		"KEEP",
		.Entity_Promote,
	)
	world.ui_layouts[world.entities[promote_button].ui_layout_index].size.x = 48

	resource_browser := editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCES_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.Project_Resources_Scroll,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 240}),
	)
	editor_ui_add_section_panel(world, resource_browser, "RESOURCES / 0")
	editor_ui_add_list(
		world,
		resource_browser,
		{
			selection_background = {0.040, 0.088, 0.098, 1},
			hover_background = {0.028, 0.038, 0.050, 1},
			active_background = {0.050, 0.067, 0.088, 1},
		},
	)
	editor_ui_add_scroll(world, resource_browser)
	resource_tools := editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		EDITOR_UI_RESOURCES_NAME,
		.None,
		{size = {2000, 34}, padding = {2, 6, 2, 6}, background = EDITOR_SECTION_BACKGROUND},
	)
	editor_ui_add_hstack(world, resource_tools, {gap = 4})
	resource_create := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_create",
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		"+",
		.Project_Resource_Create,
	)
	world.ui_layouts[world.entities[resource_create].ui_layout_index].size.x = 32
	resource_duplicate := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_duplicate",
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		"DUP",
		.Project_Resource_Duplicate,
	)
	world.ui_layouts[world.entities[resource_duplicate].ui_layout_index].size.x = 48
	resource_delete := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_delete",
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		"DEL",
		.Project_Resource_Delete,
	)
	world.ui_layouts[world.entities[resource_delete].ui_layout_index].size.x = 42
	resource_reimport_all := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_reimport_all",
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		"REIMPORT ALL",
		.Project_Resources_Reimport_All,
	)
	world.ui_layouts[world.entities[resource_reimport_all].ui_layout_index].size.x = 112

	_ = editor_ui_create_box(
		world,
		EDITOR_UI_VIEWPORT_NAME,
		EDITOR_UI_WORKSPACE_NAME,
		.Viewport,
		{size = {660, 638}, border_color = rule, border_width = 1},
	)
	gizmo_toolbar := editor_ui_create_box(
		world,
		EDITOR_UI_GIZMO_TOOLBAR_NAME,
		EDITOR_UI_VIEWPORT_NAME,
		.Gizmo_Toolbar,
		{
			position = {10, 10},
			size = {126, 34},
			padding = {2, 2, 2, 2},
			background = {0.006, 0.008, 0.012, 0.94},
			border_color = rule,
			border_width = 1,
			corner_radius = 5,
			hidden = true,
		},
	)
	editor_ui_add_hstack(world, gizmo_toolbar, {gap = 2})
	world_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_gizmo_world",
		EDITOR_UI_GIZMO_TOOLBAR_NAME,
		"WORLD",
		.Gizmo_Space_World,
	)
	local_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_gizmo_local",
		EDITOR_UI_GIZMO_TOOLBAR_NAME,
		"LOCAL",
		.Gizmo_Space_Local,
	)
	world.ui_layouts[world.entities[world_button].ui_layout_index].size.x = 60
	world.ui_layouts[world.entities[local_button].ui_layout_index].size.x = 60

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
		editor_ui_section_layout({EDITOR_RIGHT_SIDEBAR_WIDTH, 132}),
	)
	editor_ui_add_section_panel(world, right_header, "INSPECTOR")
	name_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_entity_name",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Entity_Name,
		{
			position = {10, 42},
			size = {2000, 28},
			background = {0.012, 0.017, 0.024, 1},
			border_color = EDITOR_SECTION_BORDER,
			border_width = 1,
			corner_radius = 4,
			fill_width = true,
		},
	)
	name_value := shared.ui_input_default()
	name_value.text = ""
	name_value.size = EDITOR_TEXT_SIZE
	editor_ui_add_input(world, name_input, name_value)
	resource_name_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_resource_name",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Resource_Name,
		{
			position = {10, 42},
			size = {2000, 28},
			background = {0.012, 0.017, 0.024, 1},
			border_color = EDITOR_SECTION_BORDER,
			border_width = 1,
			corner_radius = 4,
			fill_width = true,
			hidden = true,
		},
	)
	resource_name_value := shared.ui_input_default()
	resource_name_value.size = EDITOR_TEXT_SIZE
	editor_ui_add_input(world, resource_name_input, resource_name_value)
	_ = ecs.set_ui_input_prefix(world, resource_name_input, "NAME")
	world.ui_inputs[world.entities[resource_name_input].ui_input_index].prefix_width = 52
	resource_source_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_resource_source",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Resource_Source,
		{
			position = {10, 78},
			size = {2000, 28},
			background = {0.012, 0.017, 0.024, 1},
			border_color = EDITOR_SECTION_BORDER,
			border_width = 1,
			corner_radius = 4,
			fill_width = true,
			hidden = true,
		},
	)
	resource_source_value := shared.ui_input_default()
	resource_source_value.size = EDITOR_TEXT_SIZE
	editor_ui_add_input(world, resource_source_input, resource_source_value)
	_ = ecs.set_ui_input_prefix(world, resource_source_input, "PATH")
	world.ui_inputs[world.entities[resource_source_input].ui_input_index].prefix_width = 52
	find_usage_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_find_usage",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		"FIND USAGE",
		.Project_Resource_Find_Usage,
	)
	find_usage_layout := &world.ui_layouts[world.entities[find_usage_button].ui_layout_index]
	find_usage_layout.position = {10, 146}
	find_usage_layout.size = {110, 28}
	find_usage_layout.hidden = true
	reimport_button := editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_resource_reimport",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		"REIMPORT",
		.Project_Resource_Reimport,
	)
	reimport_layout := &world.ui_layouts[world.entities[reimport_button].ui_layout_index]
	reimport_layout.position = {130, 146}
	reimport_layout.size = {96, 28}
	reimport_layout.hidden = true
	inspector_header := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_identity",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Header,
		{position = {10, 82}, size = {2000, 36}},
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
		{size = {1200, 18}, fill_width = true},
	)
	editor_ui_add_text(world, status_text, "RUNNING", mint, EDITOR_TEXT_SIZE)
}

editor_ui_ensure_row :: proc(world: ^shared.World, slot: int) -> (int, int, int) {
	row, row_found := editor_ui_entity(world, .Browser_Row, slot)
	disclosure, disclosure_found := editor_ui_entity(world, .Browser_Row_Disclosure, slot)
	label, label_found := editor_ui_entity(world, .Browser_Row_Label, slot)
	if row_found && disclosure_found && label_found { return row, disclosure, label }
	row_name := fmt.tprintf("__scrapbot_editor_row_%d", slot)
	disclosure_name := fmt.tprintf("__scrapbot_editor_row_disclosure_%d", slot)
	label_name := fmt.tprintf("__scrapbot_editor_row_label_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_SCENE_NAME,
		.Browser_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}},
		slot,
	)
	disclosure = editor_ui_create_box(
		world,
		disclosure_name,
		row_name,
		.Browser_Row_Disclosure,
		{position = {6, 6}, size = {20, 20}, corner_radius = 3},
		slot,
	)
	editor_ui_add_button(world, disclosure)
	disclosure_button := shared.ui_button_default()
	disclosure_button.text = " "
	disclosure_button.size = 1
	disclosure_button.icon = .Chevron_Down
	disclosure_button.icon_inset = 6
	disclosure_button.icon_stroke = 1.5
	disclosure_button.color = {0.65, 0.68, 0.74, 1}
	disclosure_button.hover_background = {0.09, 0.11, 0.14, 1}
	disclosure_button.active_background = {0.13, 0.15, 0.19, 1}
	_ = ecs.set_ui_button(world, disclosure, disclosure_button)
	label = editor_ui_create_box(
		world,
		label_name,
		row_name,
		.Browser_Row_Label,
		{position = {26, 0}, size = {1874, EDITOR_ENTITY_ROW_HEIGHT}, padding = {8, 0, 6, 0}},
		slot,
	)
	editor_ui_add_text(world, label, "", {0.82, 0.84, 0.88, 1}, EDITOR_TEXT_SIZE)
	return row, disclosure, label
}

editor_ui_ensure_resource_row :: proc(world: ^shared.World, slot: int) -> (int, int) {
	row, row_found := editor_ui_entity(world, .Project_Resource_Row, slot)
	label, label_found := editor_ui_entity(world, .Project_Resource_Row_Label, slot)
	if row_found && label_found {
		return row, label
	}
	row_name := fmt.tprintf("__scrapbot_editor_resource_row_%d", slot)
	label_name := fmt.tprintf("__scrapbot_editor_resource_row_label_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_RESOURCES_NAME,
		.Project_Resource_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}},
		slot,
	)
	label = editor_ui_create_box(
		world,
		label_name,
		row_name,
		.Project_Resource_Row_Label,
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

editor_ui_refresh_performance_diagnostics :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil || state.performance_diagnostics == nil {
		return
	}
	diagnostics := state.performance_diagnostics
	values := [7]string {
		fmt.tprintf("%.1f", diagnostics.fps),
		fmt.tprintf("%.2f ms", diagnostics.frame_ms),
		"--",
		fmt.tprintf("%d", diagnostics.entity_count),
		fmt.tprintf("%d", diagnostics.draw_batches),
		fmt.tprintf("%d", diagnostics.frustum_culled_instances),
		fmt.tprintf("%d", diagnostics.occlusion_culled_instances),
	}
	if diagnostics.gpu_timestamps_valid {
		values[2] = fmt.tprintf("%.2f ms", diagnostics.gpu_frame_ms)
	}
	for value, slot in values {
		if cell, found := editor_ui_entity(world, .Diagnostics_Value, slot); found {
			editor_ui_set_text(world, cell, value)
		}
	}
	state.editor_performance_diagnostics_revision = diagnostics.revision
	if panel, found := editor_ui_entity(world, .Diagnostics_Panel); found {
		ecs.mark_ui_paint_changed(world, panel)
	}
}

editor_ui_update_transport :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil { return }
	visual_state := Editor_Transport_Visual_State {
		playing = state.editor_simulation_playing,
		stopped = state.editor_simulation_stopped,
		dirty = state.editor_scene_dirty,
		save_failed = state.editor_scene_save_failed,
		revert_failed = state.editor_scene_revert_failed,
		history_cursor = state.editor_history_cursor,
		history_count = state.editor_history_count,
	}
	if state.editor_transport_visual_valid && state.editor_transport_visual_state == visual_state {
		return
	}
	state.editor_transport_visual_state = visual_state
	state.editor_transport_visual_valid = true
	playback := !state.editor_simulation_stopped
	if top, found := ecs.entity_index_by_uuid(
		world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_TOP_NAME),
	); found {
		layout := &world.ui_layouts[world.entities[top].ui_layout_index]
		layout.background = EDITOR_CHROME_BACKGROUND
		layout.border_color = EDITOR_CHROME_BORDER
		if playback {
			layout.background = EDITOR_PLAYBACK_TOP_BACKGROUND
			layout.border_color = EDITOR_PLAYBACK_BORDER
		}
	}
	if viewport, found := editor_ui_entity(world, .Viewport); found {
		layout := &world.ui_layouts[world.entities[viewport].ui_layout_index]
		layout.border_color = EDITOR_CHROME_BORDER
		layout.border_width = 1
		if playback {
			layout.border_color = EDITOR_PLAYBACK_BORDER
			layout.border_width = 2
		}
	}
	if status_bar, found := ecs.entity_index_by_uuid(
		world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_STATUS_NAME),
	); found {
		layout := &world.ui_layouts[world.entities[status_bar].ui_layout_index]
		layout.background = EDITOR_CHROME_BACKGROUND
		layout.border_color = EDITOR_CHROME_BORDER
		if playback {
			layout.background = EDITOR_PLAYBACK_STATUS_BACKGROUND
			layout.border_color = EDITOR_PLAYBACK_BORDER
		}
	}
	for component in world.editor_uis {
		if component.role != .Transport_Play &&
		   component.role != .Transport_Pause &&
		   component.role != .Transport_Stop &&
		   component.role != .Transport_Step &&
		   component.role != .Transport_Undo &&
		   component.role != .Transport_Redo &&
		   component.role != .Transport_Save &&
		   component.role != .Transport_Revert { continue }
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) ||
		   entity.ui_button_index < 0 ||
		   entity.ui_button_index >= len(world.ui_buttons) { continue }
		selected :=
			component.role == .Transport_Play && state.editor_simulation_playing ||
			component.role == .Transport_Pause &&
				!state.editor_simulation_playing &&
				!state.editor_simulation_stopped ||
			component.role == .Transport_Stop && state.editor_simulation_stopped
		layout := &world.ui_layouts[entity.ui_layout_index]
		button := &world.ui_buttons[entity.ui_button_index]
		layout.background = {0.017, 0.022, 0.030, 1}
		layout.border_color = {0.055, 0.067, 0.088, 1}
		button.color = {0.64, 0.67, 0.73, 1}
		button.hover_background = {0.026, 0.034, 0.045, 1}
		button.active_background = {0.010, 0.014, 0.020, 1}
		available := true
		#partial switch component.role {
			case .Transport_Undo:
				available = state.editor_simulation_stopped && state.editor_history_cursor > 0
			case .Transport_Redo:
				available =
					state.editor_simulation_stopped &&
					state.editor_history_cursor < state.editor_history_count
			case .Transport_Save, .Transport_Revert:
				available = state.editor_simulation_stopped && state.editor_scene_dirty
			case .Transport_Stop:
				available = !state.editor_simulation_stopped
			case .Transport_Pause:
				available = !state.editor_simulation_stopped
			case .Transport_Play, .Transport_Step:
			case:
		}
		if !available {
			button.color = {0.27, 0.29, 0.34, 1}
			button.hover_background = layout.background
			button.active_background = layout.background
			continue
		}
		if component.role == .Transport_Save && state.editor_scene_dirty {
			layout.background = {0.100, 0.075, 0.020, 1}
			layout.border_color = {0.82, 0.58, 0.16, 0.9}
			button.color = {1.0, 0.82, 0.42, 1}
			button.hover_background = {0.145, 0.105, 0.026, 1}
			button.active_background = {0.075, 0.052, 0.014, 1}
			continue
		}
		if component.role == .Transport_Revert && state.editor_scene_dirty {
			layout.background = {0.095, 0.025, 0.032, 1}
			layout.border_color = {0.72, 0.16, 0.22, 0.85}
			button.color = {0.96, 0.55, 0.59, 1}
			button.hover_background = {0.145, 0.035, 0.045, 1}
			button.active_background = {0.070, 0.018, 0.024, 1}
			continue
		}
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
			world.ui_texts[entity.ui_text_index].color = {0.06, 0.72, 0.63, 1}
			if playback { world.ui_texts[entity.ui_text_index].color = EDITOR_PLAYBACK_TEXT }
		}
	}
	if root, found := editor_ui_entity(world, .Root); found {
		ecs.mark_ui_paint_changed(world, root)
	}
}

editor_ui_update_gizmo_toolbar :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil { return }
	toolbar, toolbar_found := editor_ui_entity(world, .Gizmo_Toolbar)
	if !toolbar_found { return }
	visible := false
	if selected, ok := editor_selected_world_index(state, world); ok {
		entity := world.entities[selected]
		visible = entity.transform_index >= 0 && entity.transform_index < len(world.transforms)
	}
	visual_state := Editor_Gizmo_Toolbar_Visual_State {
		visible = visible,
		space = state.editor_gizmo_space,
	}
	if state.editor_gizmo_toolbar_visual_valid &&
	   state.editor_gizmo_toolbar_visual_state == visual_state {
		return
	}
	state.editor_gizmo_toolbar_visual_state = visual_state
	state.editor_gizmo_toolbar_visual_valid = true
	editor_ui_set_hidden(world, toolbar, !visible)
	for component in world.editor_uis {
		if component.role != .Gizmo_Space_World && component.role != .Gizmo_Space_Local {
			continue
		}
		if component.entity_index < 0 || component.entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[component.entity_index]
		if entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) ||
		   entity.ui_button_index < 0 ||
		   entity.ui_button_index >= len(world.ui_buttons) {
			continue
		}
		selected :=
			component.role == .Gizmo_Space_World && state.editor_gizmo_space == .World ||
			component.role == .Gizmo_Space_Local && state.editor_gizmo_space == .Local
		layout := &world.ui_layouts[entity.ui_layout_index]
		button := &world.ui_buttons[entity.ui_button_index]
		layout.background = {0.017, 0.022, 0.030, 1}
		layout.border_color = {0.055, 0.067, 0.088, 1}
		button.color = {0.64, 0.67, 0.73, 1}
		if selected {
			layout.background = {0.025, 0.120, 0.105, 1}
			layout.border_color = {0.06, 0.72, 0.63, 0.8}
			button.color = {0.42, 0.92, 0.82, 1}
		}
	}
	if root, found := editor_ui_entity(world, .Root); found {
		ecs.mark_ui_paint_changed(world, root)
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
	if root, found := editor_ui_entity(world, .Root); found {
		ecs.mark_ui_paint_changed(world, root)
	}
}

INSPECTOR_PANEL_TITLE_HEIGHT :: EDITOR_SECTION_TITLE_HEIGHT
INSPECTOR_CELL_HEIGHT :: f32(32)
INSPECTOR_CONTROL_HEIGHT :: f32(28)
INSPECTOR_TABLE_ROW_GAP :: f32(3)
INSPECTOR_PANEL_GAP :: f32(10)
INSPECTOR_PANEL_PADDING :: shared.Vec4{}
INSPECTOR_LABEL_CELL_PADDING :: shared.Vec4{10, 8, 9, 12}
INSPECTOR_VALUE_CELL_PADDING :: shared.Vec4{2, 12, 2, 8}

editor_ui_ensure_inspector_panel :: proc(world: ^shared.World, slot: int) -> (int, int) {
	panel, panel_found := editor_ui_entity(world, .Inspector_Panel, slot)
	table, table_found := editor_ui_entity(world, .Inspector_Table, slot)
	if panel_found && table_found {
		world.ui_layouts[world.entities[panel].ui_layout_index].padding = INSPECTOR_PANEL_PADDING
		return panel, table
	}
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
	panel_layout := &world.ui_layouts[world.entities[panel].ui_layout_index]
	panel_layout.padding = INSPECTOR_PANEL_PADDING
	panel_layout.fit_content_height = true
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
		{
			columns = 2,
			column_gap = 0,
			row_gap = INSPECTOR_TABLE_ROW_GAP,
			proportional_columns = true,
			resizable_columns = true,
			min_column_width = 72,
		},
	)
	return panel, table
}

editor_ui_ensure_inspector_panel_action :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
) -> int {
	if action, found := editor_ui_entity(world, .Inspector_Panel_Action, slot); found {
		editor_ui_set_parent(world, action, parent)
		return action
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_panel_action_%d", slot)
	action := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Panel_Action,
		{size = {22, 22}, margin = {5, 5, 5, 5}, corner_radius = 4, fixed_in_fill = true},
		slot,
	)
	editor_ui_add_button(world, action)
	button := shared.ui_button_default()
	button.icon = .Close
	button.panel_action = true
	button.color = {0.76, 0.78, 0.82, 1}
	button.hover_background = {0.18, 0.20, 0.24, 1}
	button.active_background = {0.26, 0.10, 0.12, 1}
	button.icon_inset = 6
	button.icon_stroke = 1.5
	_ = ecs.set_ui_button(world, action, button)
	return action
}

editor_ui_ensure_inspector_cell :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
	value_cell: bool,
) -> int {
	if cell, found := editor_ui_entity(world, .Inspector_Cell, slot); found {
		editor_ui_set_parent(world, cell, parent)
		entity := &world.entities[cell]
		layout := &world.ui_layouts[world.entities[cell].ui_layout_index]
		layout.size.x = 1
		layout.padding = INSPECTOR_LABEL_CELL_PADDING
		if value_cell {
			layout.size.x = 2
			layout.padding = INSPECTOR_VALUE_CELL_PADDING
			if entity.ui_text_index >= 0 {
				ecs.remove_ui_component(world, cell, "scrapbot.ui_text")
			}
			if entity.ui_hstack_index < 0 {
				editor_ui_add_hstack(world, cell, {gap = 6, fill = true})
			}
		} else {
			if entity.ui_hstack_index >= 0 {
				ecs.remove_ui_component(world, cell, "scrapbot.ui_hstack")
			}
			if entity.ui_text_index < 0 {
				editor_ui_add_text(world, cell, "", {0.46, 0.49, 0.55, 1}, EDITOR_TEXT_SIZE)
			}
		}
		return cell
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_cell_%d", slot)
	cell := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Cell,
		{size = {1, INSPECTOR_CELL_HEIGHT}, padding = INSPECTOR_LABEL_CELL_PADDING},
		slot,
	)
	if value_cell {
		layout := &world.ui_layouts[world.entities[cell].ui_layout_index]
		layout.size.x = 2
		layout.padding = INSPECTOR_VALUE_CELL_PADDING
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
			size = {1, INSPECTOR_CONTROL_HEIGHT},
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
		{size = {1, INSPECTOR_CONTROL_HEIGHT}},
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
	component_menu_visible: bool,
	resource_menu_visible: bool,
}

editor_ui_ensure_resource_menu_button :: proc(world: ^shared.World, parent, label: string) -> int {
	button, found := editor_ui_entity(world, .Inspector_Resource_Menu_Button)
	if !found {
		button = editor_ui_create_box(
			world,
			"__scrapbot_editor_resource_menu_button",
			parent,
			.Inspector_Resource_Menu_Button,
			{
				size = {1, INSPECTOR_CONTROL_HEIGHT},
				padding = {5, 8, 4, 8},
				background = {0.013, 0.018, 0.025, 1},
				border_color = {0.075, 0.090, 0.115, 1},
				border_width = 1,
				corner_radius = 4,
				fill_width = true,
			},
		)
		editor_ui_add_button(world, button)
	} else {
		editor_ui_set_parent(world, button, parent)
	}
	value := world.ui_buttons[world.entities[button].ui_button_index]
	value.text = label
	value.size = EDITOR_TEXT_SIZE
	value.alignment = .Left
	value.color = {0.82, 0.84, 0.88, 1}
	value.hover_background = {0.030, 0.105, 0.092, 1}
	value.active_background = {0.018, 0.065, 0.057, 1}
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_ensure_resource_menu :: proc(world: ^shared.World) -> (int, int) {
	menu, menu_found := editor_ui_entity(world, .Inspector_Resource_Menu)
	content, content_found := editor_ui_entity(world, .Inspector_Resource_Menu_Content)
	if menu_found && content_found {
		return menu, content
	}
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCE_MENU_NAME,
		"",
		.Inspector_Resource_Menu,
		{
			size = {320, 240},
			padding = {5, 5, 5, 5},
			background = {0.009, 0.012, 0.017, 1},
			border_color = {0.11, 0.14, 0.18, 1},
			border_width = 1,
			corner_radius = 5,
			hidden = true,
		},
	)
	editor_ui_add_scroll(world, menu)
	content = editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCE_MENU_CONTENT_NAME,
		EDITOR_UI_RESOURCE_MENU_NAME,
		.Inspector_Resource_Menu_Content,
		{size = {310, 1}, fill_width = true},
	)
	editor_ui_add_vstack(world, content, {gap = 1})
	return menu, content
}

editor_ui_ensure_resource_menu_item :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	resource_id: shared.Resource_UUID,
) -> int {
	item, found := editor_ui_entity(world, .Inspector_Resource_Menu_Item, slot)
	if !found {
		item = editor_ui_create_box(
			world,
			fmt.tprintf("__scrapbot_editor_resource_menu_item_%d", slot),
			parent,
			.Inspector_Resource_Menu_Item,
			{size = {1, 30}, padding = {5, 10, 5, 10}, corner_radius = 3, fill_width = true},
			slot,
		)
		editor_ui_add_button(world, item)
	} else {
		editor_ui_set_parent(world, item, parent)
	}
	value := world.ui_buttons[world.entities[item].ui_button_index]
	value.text = label
	value.size = EDITOR_TEXT_SIZE
	value.alignment = .Left
	value.color = {0.82, 0.85, 0.90, 1}
	value.hover_background = {0.030, 0.105, 0.092, 1}
	value.active_background = {0.018, 0.065, 0.057, 1}
	_ = ecs.set_ui_button(world, item, value)
	role := &world.editor_uis[world.entities[item].editor_ui_index]
	role.resource_id = resource_id
	return item
}

editor_ui_inspector_resource_reference :: proc(
	builder: ^Inspector_ECS_Builder,
	label, resource_name: string,
) {
	parent := builder.world.entities[builder.table_entity].name
	label_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, false)
	builder.cell_count += 1
	value_cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, true)
	builder.cell_count += 1
	cells := [2]int{label_cell, value_cell}
	for cell in cells {
		editor_ui_set_hidden(builder.world, cell, false)
		builder.world.ui_layouts[builder.world.entities[cell].ui_layout_index].size.y =
			INSPECTOR_CELL_HEIGHT
	}
	editor_ui_set_text(builder.world, label_cell, label)
	button := editor_ui_ensure_resource_menu_button(
		builder.world,
		builder.world.entities[value_cell].name,
		resource_name,
	)
	editor_ui_set_hidden(builder.world, button, false)
	role := &builder.world.editor_uis[builder.world.entities[button].editor_ui_index]
	role.target = builder.target
	builder.resource_menu_visible = true
	builder.row_count += 1
}

editor_ui_build_resource_menu :: proc(state: ^State, world: ^shared.World) {
	menu, content := editor_ui_ensure_resource_menu(world)
	editor_ui_set_hidden(world, menu, state == nil || !state.editor_resource_menu_open)
	count := 0
	if state != nil && state.resource_registry != nil {
		parent := world.entities[content].name
		indices: [dynamic]int
		defer delete(indices)
		for material, index in state.resource_registry.materials {
			if !material.alive || !material.authored {
				continue
			}
			append(&indices, index)
		}
		for index in 1 ..< len(indices) {
			value := indices[index]
			cursor := index
			for cursor > 0 &&
			    state.resource_registry.materials[value].name <
				    state.resource_registry.materials[indices[cursor - 1]].name {
				indices[cursor] = indices[cursor - 1]
				cursor -= 1
			}
			indices[cursor] = value
		}
		for index in indices {
			material := state.resource_registry.materials[index]
			item := editor_ui_ensure_resource_menu_item(
				world,
				count,
				parent,
				material.name,
				material.id,
			)
			editor_ui_set_hidden(world, item, false)
			count += 1
		}
	}
	content_layout := &world.ui_layouts[world.entities[content].ui_layout_index]
	content_layout.size.y = max(f32(count * 31), 1)
	for binding in world.editor_uis {
		if binding.role == .Inspector_Resource_Menu_Item && binding.slot >= count {
			editor_ui_set_hidden(world, binding.entity_index, true)
		}
	}
}

editor_ui_ensure_component_menu_button :: proc(world: ^shared.World, parent: string) -> int {
	if button, found := editor_ui_entity(world, .Inspector_Component_Menu_Button); found {
		editor_ui_set_parent(world, button, parent)
		return button
	}
	button := editor_ui_create_box(
		world,
		"__scrapbot_editor_component_menu_button",
		parent,
		.Inspector_Component_Menu_Button,
		{
			size = {1, 30},
			background = {0.022, 0.029, 0.039, 1},
			border_color = {0.075, 0.090, 0.115, 1},
			border_width = 1,
			corner_radius = 4,
			fill_width = true,
		},
	)
	editor_ui_add_button(world, button)
	value := world.ui_buttons[world.entities[button].ui_button_index]
	value.text = "Add Component"
	value.size = EDITOR_TEXT_SIZE
	value.color = {0.70, 0.73, 0.78, 1}
	value.alignment = .Center
	value.hover_background = {0.030, 0.105, 0.092, 1}
	value.active_background = {0.018, 0.065, 0.057, 1}
	value.hover_color = {0.70, 0.95, 0.89, 1}
	value.active_color = {0.82, 1.00, 0.96, 1}
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_ensure_component_menu :: proc(world: ^shared.World) -> (int, int) {
	menu, menu_found := editor_ui_entity(world, .Inspector_Component_Menu)
	content, content_found := editor_ui_entity(world, .Inspector_Component_Menu_Content)
	if menu_found && content_found {
		return menu, content
	}
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_COMPONENT_MENU_NAME,
		"",
		.Inspector_Component_Menu,
		{
			size = {320, 320},
			padding = {5, 5, 5, 5},
			background = {0.009, 0.012, 0.017, 1},
			border_color = {0.11, 0.14, 0.18, 1},
			border_width = 1,
			corner_radius = 5,
			hidden = true,
		},
	)
	editor_ui_add_scroll(world, menu)
	content = editor_ui_create_box(
		world,
		EDITOR_UI_COMPONENT_MENU_CONTENT_NAME,
		EDITOR_UI_COMPONENT_MENU_NAME,
		.Inspector_Component_Menu_Content,
		{size = {310, 1}, fill_width = true},
	)
	editor_ui_add_vstack(world, content, {gap = 1})
	return menu, content
}

editor_ui_ensure_component_menu_group :: proc(
	world: ^shared.World,
	slot, depth: int,
	parent, label: string,
) -> int {
	if group, found := editor_ui_entity(world, .Inspector_Component_Menu_Group, slot); found {
		editor_ui_set_parent(world, group, parent)
		layout := &world.ui_layouts[world.entities[group].ui_layout_index]
		layout.padding.w = f32(10 + depth * 12)
		editor_ui_set_text(world, group, label)
		return group
	}
	name := fmt.tprintf("__scrapbot_editor_component_menu_group_%d", slot)
	group := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Component_Menu_Group,
		{size = {1, 24}, padding = {5, 0, 5, f32(10 + depth * 12)}, fill_width = true},
		slot,
	)
	editor_ui_add_text(world, group, label, {0.42, 0.45, 0.51, 1}, EDITOR_TEXT_SIZE)
	return group
}

editor_ui_ensure_component_menu_item :: proc(
	world: ^shared.World,
	definition_index, depth: int,
	parent, label: string,
) -> int {
	item, found := editor_ui_entity(world, .Inspector_Component_Menu_Item, definition_index)
	if !found {
		name := fmt.tprintf("__scrapbot_editor_component_menu_item_%d", definition_index)
		item = editor_ui_create_box(
			world,
			name,
			parent,
			.Inspector_Component_Menu_Item,
			{
				size = {1, 29},
				padding = {5, 0, 5, f32(10 + depth * 12)},
				corner_radius = 3,
				fill_width = true,
			},
			definition_index,
		)
		editor_ui_add_button(world, item)
	} else {
		editor_ui_set_parent(world, item, parent)
		layout := &world.ui_layouts[world.entities[item].ui_layout_index]
		layout.padding.w = f32(10 + depth * 12)
	}
	value := world.ui_buttons[world.entities[item].ui_button_index]
	value.text = label
	value.size = EDITOR_TEXT_SIZE
	value.alignment = .Left
	value.color = {0.82, 0.85, 0.90, 1}
	value.hover_background = {0.030, 0.105, 0.092, 1}
	value.active_background = {0.018, 0.065, 0.057, 1}
	value.hover_color = {0.70, 0.95, 0.89, 1}
	value.active_color = {0.82, 1.00, 0.96, 1}
	_ = ecs.set_ui_button(world, item, value)
	return item
}

editor_ui_set_numeric_metadata :: proc(
	input: ^shared.UI_Input_Component,
	field: shared.Editor_Inspector_Field,
) {
	if input == nil { return }
	input.numeric = field != .None
	input.draggable = input.numeric
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
		case .Camera_Near, .Camera_Far, .Camera_Exposure:
			input.step = 0.1
			input.minimum = 0.001
			input.has_minimum = true
		case .Ambient_Color, .Directional_Color, .Point_Color, .Material_Base_Color:
			input.step = 0.01
			input.minimum = 0
			input.maximum = 1
			input.has_minimum = true
			input.has_maximum = true
		case .Ambient_Intensity, .Directional_Intensity, .Point_Intensity, .Point_Range:
			input.minimum = 0
			input.has_minimum = true
		case .Material_Emissive:
			input.step = 0.1
			input.minimum = 0
			input.has_minimum = true
	}
}

editor_ui_set_reflected_numeric_metadata :: proc(
	input: ^shared.UI_Input_Component,
	field_type: component.Field_Type,
) {
	if input == nil {
		return
	}
	input.numeric =
		field_type == .Number ||
		field_type == .Vec2 ||
		field_type == .Vec3 ||
		field_type == .Vec4 ||
		field_type == .Color
	input.draggable = input.numeric
	input.step = 0.1
	input.minimum = 0
	input.maximum = 0
	input.has_minimum = false
	input.has_maximum = false
	if field_type == .Vec2 || field_type == .Vec3 || field_type == .Vec4 || field_type == .Color {
		input.step = 0.01
	}
}

editor_ui_set_custom_numeric_metadata :: proc(
	input: ^shared.UI_Input_Component,
	field_type: component.Field_Type,
	options: component.Field_Editor_Options,
) {
	editor_ui_set_reflected_numeric_metadata(input, field_type)
	if input == nil || !input.numeric {
		return
	}
	input.draggable = options.draggable
	if options.step > 0 {
		input.step = options.step
	}
	input.has_minimum = options.has_minimum
	input.minimum = options.minimum
	input.has_maximum = options.has_maximum
	input.maximum = options.maximum
	if field_type == .Color && !options.has_minimum && !options.has_maximum {
		input.has_minimum = true
		input.minimum = 0
		input.has_maximum = true
		input.maximum = 1
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

editor_ui_begin_inspector_component :: proc(
	builder: ^Inspector_ECS_Builder,
	title: string,
	definition: ^component.Definition = nil,
) {
	editor_ui_finish_inspector_component(builder)
	panel, table := editor_ui_ensure_inspector_panel(builder.world, builder.panel_count)
	builder.panel_entity = panel
	builder.table_entity = table
	builder.row_count = 0
	builder.panel_count += 1
	panel_layout := &builder.world.ui_layouts[builder.world.entities[panel].ui_layout_index]
	table_layout := &builder.world.ui_layouts[builder.world.entities[table].ui_layout_index]
	table_value := &builder.world.ui_tables[builder.world.entities[table].ui_table_index]
	table_value.columns = 2
	table_value.resizable_columns = true
	editor_ui_set_hidden(builder.world, panel, false)
	editor_ui_set_hidden(builder.world, table, false)
	panel_value := builder.world.ui_panels[builder.world.entities[panel].ui_panel_index]
	binding := &builder.world.editor_uis[builder.world.entities[panel].editor_ui_index]
	definition_id := shared.INVALID_COMPONENT_ID
	if definition != nil {
		definition_id = definition.id
	}
	if binding.target != builder.target || binding.reflected_component_id != definition_id {
		panel_value.collapsed =
			definition != nil && (definition.advanced || definition.lifecycle == .Derived)
	}
	can_remove :=
		definition != nil &&
		editor_authoring_definition_is_supported(definition) &&
		editor_component_membership_available(
			builder.state,
			builder.world,
			int(builder.target.index),
		)
	_ = ecs.set_ui_panel(builder.world, panel, panel_value)
	binding.target = builder.target
	binding.reflected_component_id = definition_id
	action := editor_ui_ensure_inspector_panel_action(
		builder.world,
		builder.panel_count - 1,
		builder.world.entities[panel].name,
	)
	editor_ui_set_hidden(builder.world, action, !can_remove)
	action_binding := &builder.world.editor_uis[builder.world.entities[action].editor_ui_index]
	action_binding.target = builder.target
	action_binding.reflected_component_id = shared.INVALID_COMPONENT_ID
	if can_remove {
		action_binding.reflected_component_id = definition.id
	}
	editor_ui_set_panel_title(builder.world, panel, title)
}

editor_ui_inspector_field_values :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	values: []string,
	field: shared.Editor_Inspector_Field = .None,
	custom_storage_index: int = -1,
	custom_field_index: int = -1,
	reflected_component_id: shared.Component_ID = shared.INVALID_COMPONENT_ID,
	reflected_field_index: int = -1,
	reflected_field_type: component.Field_Type = .String,
	resource_id: shared.Resource_UUID = {},
	custom_editor: component.Field_Editor_Options = {},
	read_only: bool = false,
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
		layout.size = {1, INSPECTOR_CONTROL_HEIGHT}
		value_input := &builder.world.ui_inputs[builder.world.entities[input_entity].ui_input_index]
		role := &builder.world.editor_uis[builder.world.entities[input_entity].editor_ui_index]
		next_axis: shared.Editor_Inspector_Axis = .None
		if len(values) > 1 {
			next_axis = shared.Editor_Inspector_Axis(value_index + 1)
		}
		if builder.state != nil &&
		   builder.state.has_focused_input &&
		   builder.state.focused_input == builder.world.entities[input_entity].id &&
		   (role.target != builder.target ||
				   role.reflected_component_id != reflected_component_id ||
				   role.reflected_field_index != reflected_field_index ||
				   role.inspector_axis != next_axis) {
			clear_input_focus(builder.state)
		}
		value_input.read_only =
			read_only ||
			(field == .None &&
					reflected_component_id == shared.INVALID_COMPONENT_ID &&
					resource_id == (shared.Resource_UUID{}))
		if builder.state == nil ||
		   !builder.state.has_focused_input ||
		   builder.state.focused_input != builder.world.entities[input_entity].id {
			_ = ecs.set_ui_input_value(builder.world, input_entity, value)
		}
		role.target = builder.target
		role.inspector_field = field
		role.inspector_axis = next_axis
		role.custom_storage_index = custom_storage_index
		role.custom_field_index = custom_field_index
		role.reflected_component_id = reflected_component_id
		role.reflected_field_index = reflected_field_index
		role.resource_id = resource_id
		editor_ui_set_numeric_metadata(value_input, field)
		if reflected_component_id != shared.INVALID_COMPONENT_ID {
			editor_ui_set_reflected_numeric_metadata(value_input, reflected_field_type)
		}
		if field == .Custom_Number ||
		   field == .Custom_Vec2 ||
		   field == .Custom_Vec3 ||
		   field == .Custom_Vec4 ||
		   field == .Custom_Color {
			editor_ui_set_custom_numeric_metadata(value_input, reflected_field_type, custom_editor)
		}
		_ = ecs.set_ui_input_prefix(builder.world, input_entity, "")
		value_input.prefix_width = 0
		if role.inspector_axis != .None {
			value_input.prefix_width = UI_INPUT_PREFIX_WIDTH
			prefix := "X"
			value_input.prefix_color = {0.92, 0.30, 0.32, 1}
			if role.inspector_axis == .Y {
				prefix = "Y"
				value_input.prefix_color = {0.34, 0.82, 0.42, 1}
			} else if role.inspector_axis == .Z {
				prefix = "Z"
				value_input.prefix_color = {0.34, 0.55, 0.96, 1}
			} else if role.inspector_axis == .W {
				prefix = "W"
				value_input.prefix_color = {0.84, 0.65, 0.30, 1}
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

editor_ui_inspector_resource_values :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	values: []string,
	field: shared.Editor_Inspector_Field,
	resource_id: shared.Resource_UUID,
) {
	editor_ui_inspector_field_values(
		builder,
		label,
		values,
		field,
		-1,
		-1,
		shared.INVALID_COMPONENT_ID,
		-1,
		.Number,
		resource_id,
	)
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
	reflected_component_id: shared.Component_ID = shared.INVALID_COMPONENT_ID,
	reflected_field_index: int = -1,
	read_only: bool = false,
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
	checkbox.read_only =
		read_only || (field == .None && reflected_component_id == shared.INVALID_COMPONENT_ID)
	role := &builder.world.editor_uis[builder.world.entities[checkbox_entity].editor_ui_index]
	role.target = builder.target
	role.inspector_field = field
	role.inspector_axis = .None
	role.reflected_component_id = reflected_component_id
	role.reflected_field_index = reflected_field_index
	builder.row_count += 1
}

editor_ui_inspector_reflected_field :: proc(
	builder: ^Inspector_ECS_Builder,
	component_value: any,
	definition: ^component.Definition,
	field_index: int,
) {
	if builder == nil || definition == nil {
		return
	}
	field, described := editor_reflected_field_definition(component_value, definition, field_index)
	if !described {
		return
	}
	field_value, found := editor_reflected_field_value(component_value, definition, field_index)
	if !found {
		return
	}
	read_only :=
		definition.lifecycle != .Authored || !editor_reflected_value_is_writable(field_value)
	if field.field_type == .Bool {
		value, found := editor_reflected_field_bool(component_value, definition, field_index)
		if found {
			editor_ui_inspector_bool(
				builder,
				field.name,
				value,
				.None,
				definition.id,
				field_index,
				read_only,
			)
		}
		return
	}
	values: [4]string
	uuid_buffer: [36]u8
	count: int
	count, found = editor_reflected_field_texts(
		component_value,
		definition,
		field_index,
		uuid_buffer[:],
		&values,
	)
	if !found {
		return
	}
	editor_ui_inspector_field_values(
		builder,
		field.name,
		values[:count],
		.None,
		-1,
		-1,
		definition.id,
		field_index,
		field.field_type,
		{},
		field.editor,
		read_only,
	)
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

editor_ui_inspector_custom_number :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: f32,
	storage_index, field_index: int,
	definition: component.Field_Definition,
) {
	values := [1]string{fmt.tprintf("%.3f", value)}
	editor_ui_inspector_field_values(
		builder,
		label,
		values[:],
		.Custom_Number,
		storage_index,
		field_index,
		shared.INVALID_COMPONENT_ID,
		-1,
		.Number,
		{},
		definition.editor,
	)
}

editor_ui_inspector_custom_vector :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: shared.Vec4,
	count: int,
	field: shared.Editor_Inspector_Field,
	storage_index, field_index: int,
	definition: component.Field_Definition,
) {
	values := [4]string {
		fmt.tprintf("%.3f", value.x),
		fmt.tprintf("%.3f", value.y),
		fmt.tprintf("%.3f", value.z),
		fmt.tprintf("%.3f", value.w),
	}
	editor_ui_inspector_field_values(
		builder,
		label,
		values[:count],
		field,
		storage_index,
		field_index,
		shared.INVALID_COMPONENT_ID,
		-1,
		definition.field_type,
		{},
		definition.editor,
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
				if component.slot >= builder.input_count {
					if builder.state != nil &&
					   builder.state.has_focused_input &&
					   builder.state.focused_input == entity.id {
						clear_input_focus(builder.state)
					}
					editor_ui_set_hidden(builder.world, component.entity_index, true)
				}
			case .Inspector_Checkbox:
				if component.slot >=
				   builder.checkbox_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Component_Menu_Button:
				editor_ui_set_hidden(
					builder.world,
					component.entity_index,
					!builder.component_menu_visible,
				)
			case .Inspector_Resource_Menu_Button:
				editor_ui_set_hidden(
					builder.world,
					component.entity_index,
					!builder.resource_menu_visible,
				)
			case:
		}
	}
	if !builder.component_menu_visible {
		builder.state.editor_component_menu_open = false
		if menu, found := editor_ui_entity(builder.world, .Inspector_Component_Menu); found {
			editor_ui_set_hidden(builder.world, menu, true)
		}
	}
	if !builder.resource_menu_visible {
		builder.state.editor_resource_menu_open = false
		if menu, found := editor_ui_entity(builder.world, .Inspector_Resource_Menu); found {
			editor_ui_set_hidden(builder.world, menu, true)
		}
	}
}

editor_ui_build_component_controls :: proc(builder: ^Inspector_ECS_Builder, entity_index: int) {
	editor_ui_begin_inspector_component(builder, "COMPONENTS")
	builder.component_menu_visible = true
	table := &builder.world.ui_tables[builder.world.entities[builder.table_entity].ui_table_index]
	table.columns = 1
	table.resizable_columns = false
	parent := builder.world.entities[builder.table_entity].name
	cell := editor_ui_ensure_inspector_cell(builder.world, builder.cell_count, parent, true)
	builder.cell_count += 1
	editor_ui_set_hidden(builder.world, cell, false)
	cell_layout := &builder.world.ui_layouts[builder.world.entities[cell].ui_layout_index]
	cell_layout.size.x = 1
	cell_layout.size.y = 46
	cell_layout.padding = {8, 12, 8, 12}
	button := editor_ui_ensure_component_menu_button(
		builder.world,
		builder.world.entities[cell].name,
	)
	editor_ui_set_hidden(builder.world, button, false)
	builder.row_count = 1
	editor_ui_build_component_menu(builder.state, builder.world, entity_index)
}

editor_component_definition_less :: proc(a, b: ^component.Definition) -> bool {
	a_local := shared.component_name_is_project_level(a.name)
	b_local := shared.component_name_is_project_level(b.name)
	if a_local != b_local {
		return a_local
	}
	return a.name < b.name
}

editor_ui_refresh_component_menu_cache :: proc(state: ^State) {
	if state == nil || state.component_registry == nil {
		return
	}
	registry := state.component_registry
	if state.component_menu_cached_registry == registry &&
	   state.component_menu_registry_revision == registry.revision {
		return
	}
	state.component_menu_definition_count = 0
	for index in 0 ..< registry.definition_count {
		definition := &registry.definitions[index]
		if !editor_authoring_definition_is_supported(definition) {
			continue
		}
		// Model instances need a resource choice, so they are authored from the
		// resource browser/scene data until the component menu has a resource picker.
		// Existing model components remain inspectable and removable.
		if definition.storage_kind == .Model {
			continue
		}
		state.component_menu_definition_indices[state.component_menu_definition_count] = index
		state.component_menu_definition_count += 1
	}
	for index in 1 ..< state.component_menu_definition_count {
		value := state.component_menu_definition_indices[index]
		cursor := index
		for cursor > 0 &&
		    editor_component_definition_less(
			    &registry.definitions[value],
			    &registry.definitions[state.component_menu_definition_indices[cursor - 1]],
		    ) {
			state.component_menu_definition_indices[cursor] =
				state.component_menu_definition_indices[cursor - 1]
			cursor -= 1
		}
		state.component_menu_definition_indices[cursor] = value
	}
	state.component_menu_cached_registry = registry
	state.component_menu_registry_revision = registry.revision
}

editor_ui_build_component_menu :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	menu, content := editor_ui_ensure_component_menu(world)
	editor_ui_set_hidden(world, menu, state == nil || !state.editor_component_menu_open)
	for binding in world.editor_uis {
		if binding.role != .Inspector_Component_Menu_Group &&
		   binding.role != .Inspector_Component_Menu_Item {
			continue
		}
		editor_ui_set_hidden(world, binding.entity_index, true)
	}
	if state == nil || state.component_registry == nil {
		return
	}
	registry := state.component_registry
	editor_ui_refresh_component_menu_cache(state)
	group_slot := 0
	row_count := 0
	project_group_emitted := false
	previous_tokens: [16]string
	previous_count := 0
	content_name := world.entities[content].name
	for definition_index in state.component_menu_definition_indices[:state.component_menu_definition_count] {
		definition := &registry.definitions[definition_index]
		if editor_entity_has_registered_component(world, entity_index, definition) {
			continue
		}
		tokens := definition.name_tokens[:definition.name_token_count]
		if len(tokens) == 1 {
			previous_count = 0
			if !project_group_emitted {
				group := editor_ui_ensure_component_menu_group(
					world,
					group_slot,
					0,
					content_name,
					"PROJECT",
				)
				group_slot += 1
				row_count += 1
				editor_ui_set_hidden(world, group, false)
				project_group_emitted = true
			}
		} else {
			common := 0
			for common < previous_count &&
			    common < len(tokens) - 1 &&
			    previous_tokens[common] == tokens[common] {
				common += 1
			}
			for depth in common ..< len(tokens) - 1 {
				label := tokens[depth]
				group := editor_ui_ensure_component_menu_group(
					world,
					group_slot,
					depth,
					content_name,
					label,
				)
				group_slot += 1
				row_count += 1
				editor_ui_set_hidden(world, group, false)
			}
			previous_count = min(len(tokens) - 1, len(previous_tokens))
			for index in 0 ..< previous_count {
				previous_tokens[index] = tokens[index]
			}
		}
		label := tokens[len(tokens) - 1]
		item := editor_ui_ensure_component_menu_item(
			world,
			definition_index,
			len(tokens),
			content_name,
			label,
		)
		editor_ui_set_hidden(world, item, false)
		row_count += 1
	}
	content_layout := &world.ui_layouts[world.entities[content].ui_layout_index]
	content_layout.size.y = max(f32(row_count * 30), 1)
}

editor_entity_has_registered_component :: proc(
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
) -> bool {
	return ecs.registered_component_is_present(world, entity_index, definition)
}

editor_component_title :: proc(name: string, buffer: []u8) -> string {
	value := name
	if strings.has_prefix(value, "scrapbot.") {
		value = value[len("scrapbot."):]
	}
	count := 0
	for byte in transmute([]u8)value {
		if count >= len(buffer) {
			break
		}
		if byte == '_' {
			buffer[count] = ' '
			count += 1
			continue
		}
		if byte == '.' {
			if count + 3 > len(buffer) {
				break
			}
			buffer[count] = ' '
			buffer[count + 1] = '/'
			buffer[count + 2] = ' '
			count += 3
			continue
		}
		next := byte
		if next >= 'a' && next <= 'z' {
			next -= 'a' - 'A'
		}
		buffer[count] = next
		count += 1
	}
	return string(buffer[:count])
}

editor_transform_parent_label :: proc(world: ^shared.World, parent: shared.Entity_UUID) -> string {
	if parent == (shared.Entity_UUID{}) {
		return "None"
	}
	if index, found := ecs.entity_index_by_uuid(world, parent); found {
		return world.entities[index].name
	}
	return "Missing parent"
}

editor_ui_build_type_inspected_component_panels :: proc(
	builder: ^Inspector_ECS_Builder,
	entity_index: int,
) -> bool {
	if builder == nil ||
	   builder.state == nil ||
	   builder.state.component_registry == nil ||
	   !ecs.entity_is_alive(builder.world, entity_index) {
		return false
	}
	snapshot, captured := ecs.capture_entity_snapshot(builder.world, entity_index)
	if !captured {
		return false
	}
	defer ecs.destroy_entity_snapshot(&snapshot)
	registry := builder.state.component_registry
	for lifecycle_pass in 0 ..< 2 {
		lifecycle: component.Lifecycle = .Authored
		if lifecycle_pass == 1 {
			lifecycle = .Derived
		}
		for definition_index in 0 ..< registry.definition_count {
			definition := &registry.definitions[definition_index]
			if definition.lifecycle != lifecycle ||
			   !editor_entity_has_registered_component(builder.world, entity_index, definition) {
				continue
			}
			component_value, found := editor_reflected_snapshot_component_value(
				&snapshot.entity,
				definition,
			)
			if definition.lifecycle == .Derived {
				component_value, found = editor_reflected_live_component_value(
					builder.world,
					entity_index,
					definition,
				)
			}
			if !found {
				continue
			}
			title_buffer: [128]u8
			title := editor_component_title(definition.name, title_buffer[:])
			editor_ui_begin_inspector_component(builder, title, definition)
			field_count := editor_reflected_field_count(component_value, definition)
			for field_index in 0 ..< field_count {
				editor_ui_inspector_reflected_field(
					builder,
					component_value,
					definition,
					field_index,
				)
			}
		}
	}
	if editor_component_membership_available(builder.state, builder.world, entity_index) {
		editor_ui_build_component_controls(builder, entity_index)
	}
	editor_ui_finish_inspector(builder)
	return true
}

editor_selected_world_index :: proc(state: ^State, world: ^shared.World) -> (int, bool) {
	if state == nil || world == nil || !state.editor_has_selection {
		return -1, false
	}
	index := int(state.editor_selected_entity.index)
	if !ecs.entity_is_alive(world, index) ||
	   world.entities[index].id != state.editor_selected_entity {
		return -1, false
	}
	return index, true
}

editor_ui_build_inspector_panels :: proc(
	state: ^State,
	world: ^shared.World,
	content_entity, entity_index: int,
) {
	editor_ui_hide_asset_preview(world)
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
	builder.target = world.entities[entity_index].id
	if !editor_ui_build_type_inspected_component_panels(&builder, entity_index) {
		editor_ui_finish_inspector(&builder)
	}
}
editor_ui_build_resource_inspector_panels :: proc(
	state: ^State,
	world: ^shared.World,
	content_entity: int,
	id: shared.Resource_UUID,
) {
	editor_ui_hide_asset_preview(world)
	builder := Inspector_ECS_Builder {
		state = state,
		world = world,
		content_entity = content_entity,
		panel_entity = -1,
		table_entity = -1,
	}
	if state == nil || state.resource_registry == nil {
		editor_ui_finish_inspector(&builder)
		return
	}
	if environment_handle, environment_found := resources.environment_handle_by_uuid(
		state.resource_registry,
		id,
	); environment_found {
		environment, alive := resources.get_environment(
			state.resource_registry,
			environment_handle,
		)
		if alive && environment.authored {
			editor_ui_begin_inspector_component(&builder, "ENVIRONMENT")
			editor_ui_inspector_field(&builder, "source asset", environment.asset_source)
			editor_ui_inspector_field(
				&builder,
				"sky panorama",
				fmt.tprintf("%d x %d", environment.desc.sky_width, environment.desc.sky_height),
			)
			editor_ui_inspector_field(
				&builder,
				"irradiance cube",
				fmt.tprintf(
					"%d x %d",
					environment.desc.irradiance_size,
					environment.desc.irradiance_size,
				),
			)
			editor_ui_inspector_field(
				&builder,
				"specular cube",
				fmt.tprintf(
					"%d x %d",
					environment.desc.specular_size,
					environment.desc.specular_size,
				),
			)
			editor_ui_inspector_field(
				&builder,
				"mip levels",
				fmt.tprintf("%d", environment.desc.specular_mip_count),
			)
			editor_ui_begin_inspector_component(&builder, "IMPORT")
			editor_ui_inspector_field(&builder, "status", editor_resource_import_status(state, id))
			editor_ui_inspector_field(&builder, "dependency", environment.asset_source)
			editor_ui_inspector_field(&builder, "product", "RGBA16F sky + IBL cubes")
			editor_ui_inspector_field(
				&builder,
				"product size",
				editor_format_byte_count(environment.import_byte_count),
			)
			editor_ui_inspector_field(&builder, "warnings", "None")
			if editor_resource_import_failed(state, id) {
				editor_ui_inspector_field(
					&builder,
					"error",
					state.editor_resource_reimport_message,
				)
			}
			editor_ui_finish_inspector(&builder)
			return
		}
	}
	if texture_handle, texture_found := resources.texture_handle_by_uuid(
		state.resource_registry,
		id,
	); texture_found {
		texture, alive := resources.get_texture(state.resource_registry, texture_handle)
		if alive && texture.authored {
			editor_ui_inspector_texture_preview(&builder, texture)
			editor_ui_begin_inspector_component(&builder, "TEXTURE")
			editor_ui_inspector_field(&builder, "source asset", texture.asset_source)
			editor_ui_inspector_field(
				&builder,
				"dimensions",
				fmt.tprintf("%d x %d", texture.desc.width, texture.desc.height),
			)
			editor_ui_inspector_field(
				&builder,
				"mip levels",
				fmt.tprintf("%d", texture.desc.mip_count),
			)
			color_space := "sRGB"
			if texture.desc.color_space == .Linear {
				color_space = "Linear"
			}
			editor_ui_inspector_field(&builder, "color space", color_space)
			editor_ui_begin_inspector_component(&builder, "IMPORT")
			status := editor_resource_import_status(state, id)
			editor_ui_inspector_field(&builder, "status", status)
			editor_ui_inspector_field(&builder, "dependency", texture.asset_source)
			editor_ui_inspector_field(&builder, "product", "RGBA8 mip chain")
			editor_ui_inspector_field(
				&builder,
				"product size",
				editor_format_byte_count(texture.import_byte_count),
			)
			editor_ui_inspector_field(&builder, "warnings", "None")
			if editor_resource_import_failed(state, id) {
				editor_ui_inspector_field(
					&builder,
					"error",
					state.editor_resource_reimport_message,
				)
			}
			editor_ui_finish_inspector(&builder)
			return
		}
	}
	if model_handle, model_found := resources.model_handle_by_uuid(state.resource_registry, id);
	   model_found {
		model, alive := resources.get_model(state.resource_registry, model_handle)
		if alive && model.authored {
			editor_ui_inspector_model_preview(&builder, state.resource_registry, model)
			primitive_count := 0
			for mesh in model.meshes {
				primitive_count += len(mesh.primitives)
			}
			editor_ui_begin_inspector_component(&builder, "MODEL")
			editor_ui_inspector_field(&builder, "source asset", model.asset_source)
			editor_ui_inspector_field(&builder, "nodes", fmt.tprintf("%d", len(model.nodes)))
			editor_ui_inspector_field(&builder, "meshes", fmt.tprintf("%d", len(model.meshes)))
			editor_ui_inspector_field(&builder, "primitives", fmt.tprintf("%d", primitive_count))
			editor_ui_inspector_field(
				&builder,
				"materials",
				fmt.tprintf("%d", len(model.material_handles)),
			)
			texture_count := 0
			for handle in model.material_handles {
				material, material_alive := resources.get_material(state.resource_registry, handle)
				if !material_alive {
					continue
				}
				if len(material.desc.texture_pixels) > 0 {
					texture_count += 1
				}
				images := [?]resources.Material_Image {
					material.desc.metallic_roughness_image,
					material.desc.normal_image,
					material.desc.occlusion_image,
					material.desc.emissive_image,
				}
				for image in images {
					if len(image.pixels) > 0 {
						texture_count += 1
					}
				}
			}
			editor_ui_inspector_field(
				&builder,
				"embedded textures",
				fmt.tprintf("%d", texture_count),
			)
			editor_ui_begin_inspector_component(&builder, "IMPORT")
			status := editor_resource_import_status(state, id)
			editor_ui_inspector_field(&builder, "status", status)
			editor_ui_inspector_field(&builder, "dependency", model.asset_source)
			editor_ui_inspector_field(&builder, "product", "Static glTF mesh data")
			editor_ui_inspector_field(
				&builder,
				"product size",
				editor_format_byte_count(model.import_byte_count),
			)
			warnings := "None"
			if model.ignored_texture_count > 0 {
				warnings = fmt.tprintf(
					"%d unsupported texture map(s) were ignored",
					model.ignored_texture_count,
				)
			}
			editor_ui_inspector_field(&builder, "warnings", warnings)
			if editor_resource_import_failed(state, id) {
				editor_ui_inspector_field(
					&builder,
					"error",
					state.editor_resource_reimport_message,
				)
			}
			editor_ui_finish_inspector(&builder)
			return
		}
	}
	handle, found := resources.material_by_uuid(state.resource_registry, id)
	if !found {
		editor_ui_finish_inspector(&builder)
		return
	}
	material, alive := resources.get_material(state.resource_registry, handle)
	if !alive || !material.authored {
		editor_ui_finish_inspector(&builder)
		return
	}
	editor_ui_inspector_preview_surface(&builder, material.id)
	editor_ui_begin_inspector_component(&builder, "MATERIAL")
	base_values := [4]string {
		fmt.tprintf("%.2f", material.desc.base_color.x),
		fmt.tprintf("%.2f", material.desc.base_color.y),
		fmt.tprintf("%.2f", material.desc.base_color.z),
		fmt.tprintf("%.2f", material.desc.base_color.w),
	}
	editor_ui_inspector_resource_values(
		&builder,
		"base color",
		base_values[:],
		.Material_Base_Color,
		material.id,
	)
	emissive_values := [3]string {
		fmt.tprintf("%.2f", material.desc.emissive.x),
		fmt.tprintf("%.2f", material.desc.emissive.y),
		fmt.tprintf("%.2f", material.desc.emissive.z),
	}
	editor_ui_inspector_resource_values(
		&builder,
		"emissive",
		emissive_values[:],
		.Material_Emissive,
		material.id,
	)
	texture := material.texture_asset
	if material.texture_id != (shared.Resource_UUID{}) {
		texture_buffer: [36]u8
		texture = shared.resource_uuid_to_string(material.texture_id, texture_buffer[:])
	} else if texture == "" {
		texture = "None"
	}
	editor_ui_inspector_field(&builder, "texture", texture)
	editor_ui_begin_inspector_component(&builder, "REFERENCES")
	usage_count := editor_resource_usage_count(world, id)
	editor_ui_inspector_field(&builder, "scene usages", fmt.tprintf("%d", usage_count))
	delete_status := "Blocked while referenced"
	if usage_count == 0 {
		delete_status = "Available"
	}
	editor_ui_inspector_field(&builder, "delete", delete_status)
	editor_ui_finish_inspector(&builder)
}

editor_ui_hide_asset_preview :: proc(world: ^shared.World) {
	if world == nil {
		return
	}
	for binding in world.editor_uis {
		if binding.role == .Inspector_Preview_Surface ||
		   binding.role == .Inspector_Preview_Toolbar ||
		   binding.role == .Inspector_Preview_Reset ||
		   binding.role == .Inspector_Preview_Hint {
			editor_ui_set_hidden(world, binding.entity_index, true)
		}
	}
}

editor_ui_inspector_texture_preview :: proc(
	builder: ^Inspector_ECS_Builder,
	texture: ^resources.Texture,
) {
	if builder == nil || texture == nil {
		return
	}
	editor_ui_inspector_preview_surface(builder, texture.id, false)
}

editor_ui_inspector_model_preview :: proc(
	builder: ^Inspector_ECS_Builder,
	registry: ^resources.Registry,
	model: ^resources.Model,
) {
	if builder == nil || registry == nil || model == nil {
		return
	}
	editor_ui_inspector_preview_surface(builder, model.id)
}

editor_ui_inspector_preview_surface :: proc(
	builder: ^Inspector_ECS_Builder,
	resource: shared.Resource_UUID,
	interactive := true,
) {
	editor_ui_begin_inspector_component(builder, "PREVIEW")
	editor_ui_set_hidden(builder.world, builder.table_entity, true)
	panel_slot := builder.panel_count - 1
	panel_name := builder.world.entities[builder.panel_entity].name
	viewport, found := editor_ui_entity(builder.world, .Inspector_Preview_Surface, panel_slot)
	if !found {
		viewport = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_%d", panel_slot),
			panel_name,
			.Inspector_Preview_Surface,
			{
				size = {2000, 220},
				margin = {8, 12, 4, 12},
				border_color = EDITOR_SECTION_BORDER,
				border_width = 1,
				corner_radius = 4,
				fill_width = true,
			},
			panel_slot,
		)
	} else {
		editor_ui_set_parent(builder.world, viewport, panel_name)
		editor_ui_set_hidden(builder.world, viewport, false)
	}
	value := shared.ui_viewport_default()
	entity := builder.world.entities[viewport]
	if entity.ui_viewport_index >= 0 &&
	   entity.ui_viewport_index < len(builder.world.ui_viewports) &&
	   builder.world.ui_viewports[entity.ui_viewport_index].resource == resource {
		value = builder.world.ui_viewports[entity.ui_viewport_index]
	} else {
		value.resource = resource
	}
	value.interactive = interactive
	_ = ecs.set_ui_viewport(builder.world, viewport, value)
	toolbar, toolbar_found := editor_ui_entity(
		builder.world,
		.Inspector_Preview_Toolbar,
		panel_slot,
	)
	if !toolbar_found {
		toolbar = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_toolbar_%d", panel_slot),
			panel_name,
			.Inspector_Preview_Toolbar,
			{size = {2000, 28}, margin = {4, 12, 12, 12}, fill_width = true},
			panel_slot,
		)
		editor_ui_add_hstack(builder.world, toolbar, {gap = 8, fill = true})
	} else {
		editor_ui_set_parent(builder.world, toolbar, panel_name)
		editor_ui_set_hidden(builder.world, toolbar, !interactive)
	}
	editor_ui_set_hidden(builder.world, toolbar, !interactive)
	toolbar_name := builder.world.entities[toolbar].name
	reset, reset_found := editor_ui_entity(builder.world, .Inspector_Preview_Reset, panel_slot)
	if !reset_found {
		reset = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_reset_%d", panel_slot),
			toolbar_name,
			.Inspector_Preview_Reset,
			{
				size = {64, 28},
				background = {0.017, 0.022, 0.030, 1},
				border_color = {0.055, 0.067, 0.088, 1},
				border_width = 1,
				corner_radius = 4,
				fixed_in_fill = true,
			},
			panel_slot,
		)
		editor_ui_add_button(builder.world, reset)
		button := builder.world.ui_buttons[builder.world.entities[reset].ui_button_index]
		button.text = "RESET"
		button.color = {0.46, 0.49, 0.55, 1}
		button.size = EDITOR_TEXT_SIZE
		_ = ecs.set_ui_button(builder.world, reset, button)
	} else {
		editor_ui_set_parent(builder.world, reset, toolbar_name)
		editor_ui_set_hidden(builder.world, reset, false)
	}
	hint, hint_found := editor_ui_entity(builder.world, .Inspector_Preview_Hint, panel_slot)
	if !hint_found {
		hint = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_hint_%d", panel_slot),
			toolbar_name,
			.Inspector_Preview_Hint,
			{size = {1, 28}, fill_width = true},
			panel_slot,
		)
		editor_ui_add_text(
			builder.world,
			hint,
			"DRAG TO ORBIT  /  SCROLL TO ZOOM",
			{0.46, 0.49, 0.55, 1},
			EDITOR_TEXT_SIZE,
		)
	} else {
		editor_ui_set_parent(builder.world, hint, toolbar_name)
		editor_ui_set_hidden(builder.world, hint, false)
	}
}

editor_resource_import_failed :: proc(state: ^State, id: shared.Resource_UUID) -> bool {
	return(
		state != nil &&
		state.editor_resource_reimport_failed &&
		(state.editor_resource_reimport_result_id == id ||
				state.editor_resource_reimport_all_requested) \
	)
}

editor_resource_import_status :: proc(state: ^State, id: shared.Resource_UUID) -> string {
	if editor_resource_import_failed(state, id) {
		return "Error"
	}
	if state != nil &&
	   (state.editor_resource_reimport_result_id == id ||
			   (state.editor_resource_reimport_all_requested &&
					   state.editor_resource_reimport_result_id == (shared.Resource_UUID{}))) {
		return "Reimported"
	}
	return "Up to date"
}

editor_format_byte_count :: proc(value: int) -> string {
	if value < 1024 {
		return fmt.tprintf("%d B", value)
	}
	if value < 1024 * 1024 {
		return fmt.tprintf("%.1f KiB", f64(value) / 1024.0)
	}
	return fmt.tprintf("%.1f MiB", f64(value) / (1024.0 * 1024.0))
}

editor_hierarchy_append_visible :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index, depth: int,
	first_child, next_sibling: ^[MAX_NODES]int,
	visited: ^[MAX_NODES]bool,
	indices, depths: ^[MAX_NODES]int,
	has_children: ^[MAX_NODES]bool,
	count: ^int,
) {
	if entity_index < 0 ||
	   entity_index >= MAX_NODES ||
	   visited[entity_index] ||
	   count^ >= MAX_NODES {
		return
	}
	visited[entity_index] = true
	slot := count^
	indices[slot] = entity_index
	depths[slot] = depth
	has_children[slot] = first_child[entity_index] >= 0
	count^ += 1
	child := first_child[entity_index]
	for child >= 0 {
		editor_hierarchy_append_visible(
			state,
			world,
			child,
			depth + 1,
			first_child,
			next_sibling,
			visited,
			indices,
			depths,
			has_children,
			count,
		)
		child = next_sibling[child]
	}
}

editor_hierarchy_visible_entities :: proc(
	state: ^State,
	world: ^shared.World,
	indices, depths: ^[MAX_NODES]int,
	has_children: ^[MAX_NODES]bool,
) -> int {
	limit := min(len(world.entities), MAX_NODES)
	first_child, last_child, next_sibling: [MAX_NODES]int
	root_first, root_last := -1, -1
	eligible: [MAX_NODES]bool
	for index in 0 ..< limit {
		first_child[index] = -1
		last_child[index] = -1
		next_sibling[index] = -1
		entity := world.entities[index]
		selected_runtime := state.editor_has_selection && state.editor_selected_entity == entity.id
		eligible[index] = entity.alive && (entity.origin == .Scene || selected_runtime)
	}
	ordered_indices: [dynamic]int
	defer delete(ordered_indices)
	for eligible_entity, index in eligible[:limit] {
		if eligible_entity {
			append(&ordered_indices, index)
		}
	}
	ecs.sort_entity_indices_by_scene_order(world, ordered_indices[:])
	for index in ordered_indices {
		if index < 0 || index >= limit {
			continue
		}
		if !eligible[index] {
			continue
		}
		parent_index := -1
		entity := world.entities[index]
		if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
			parent := world.transforms[entity.transform_index].parent
			if parent != (shared.Entity_UUID{}) {
				if candidate, found := ecs.entity_index_by_uuid(world, parent);
				   found && candidate >= 0 && candidate < limit && eligible[candidate] {
					parent_index = candidate
				}
			}
		}
		if parent_index >= 0 {
			if first_child[parent_index] < 0 {
				first_child[parent_index] = index
			} else {
				next_sibling[last_child[parent_index]] = index
			}
			last_child[parent_index] = index
		} else {
			if root_first < 0 {
				root_first = index
			} else {
				next_sibling[root_last] = index
			}
			root_last = index
		}
	}
	visited: [MAX_NODES]bool
	count := 0
	root := root_first
	for root >= 0 {
		editor_hierarchy_append_visible(
			state,
			world,
			root,
			0,
			&first_child,
			&next_sibling,
			&visited,
			indices,
			depths,
			has_children,
			&count,
		)
		root = next_sibling[root]
	}
	return count
}

refresh_editor_ecs_snapshot :: proc(state: ^State, world: ^shared.World) {
	editor_ui_refresh_performance_diagnostics(state, world)
	editor_ui_refresh_system_profile(state, world)
	refresh_browser :=
		!state.editor_browser_snapshot_valid ||
		!state.editor_snapshot_valid ||
		state.editor_browser_snapshot_has_selection != state.editor_has_selection ||
		(state.editor_has_selection &&
				state.editor_browser_snapshot_selected_entity != state.editor_selected_entity)
	if refresh_browser {
		hierarchy_indices, hierarchy_depths: [MAX_NODES]int
		hierarchy_has_children: [MAX_NODES]bool
		visible_count := editor_hierarchy_visible_entities(
			state,
			world,
			&hierarchy_indices,
			&hierarchy_depths,
			&hierarchy_has_children,
		)
		selected_row: shared.Entity_UUID
		row_uuid_by_entity: [MAX_NODES]shared.Entity_UUID
		for slot in 0 ..< visible_count {
			entity_index := hierarchy_indices[slot]
			entity := world.entities[entity_index]
			row, disclosure, label := editor_ui_ensure_row(world, slot)
			world.entities[row].alive = true
			world.entities[disclosure].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, disclosure, !hierarchy_has_children[slot])
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].target = entity.id
			world.editor_uis[world.entities[disclosure].editor_ui_index].target = entity.id
			world.editor_uis[world.entities[label].editor_ui_index].target = entity.id
			row_uuid_by_entity[entity_index] = world.entities[row].uuid
			row_layout := &world.ui_layouts[world.entities[row].ui_layout_index]
			row_layout.tree_item = true
			row_layout.tree_parent = {}
			row_layout.tree_order = entity.scene_order
			row_layout.tree_collapsed =
				state.editor_collapsed_entities != nil &&
				state.editor_collapsed_entities[entity.uuid]
			if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
				parent := world.transforms[entity.transform_index].parent
				if parent_index, found := ecs.entity_index_by_uuid(world, parent);
				   found && parent_index >= 0 && parent_index < len(row_uuid_by_entity) {
					row_layout.tree_parent = row_uuid_by_entity[parent_index]
				}
			}
			if state.editor_has_selection && state.editor_selected_entity == entity.id {
				selected_row = world.entities[row].uuid
			}
			label_text := &world.ui_texts[world.entities[label].ui_text_index]
			label_text.color = {0.82, 0.85, 0.90, 1}
			if entity.origin == .Runtime { label_text.color = EDITOR_RUNTIME_ENTITY_COLOR }
			disclosure_layout := &world.ui_layouts[world.entities[disclosure].ui_layout_index]
			disclosure_layout.position.x = 6
			label_layout := &world.ui_layouts[world.entities[label].ui_layout_index]
			label_layout.position.x = 26
			button := &world.ui_buttons[world.entities[disclosure].ui_button_index]
			button.icon = .Chevron_Down
			if state.editor_collapsed_entities != nil &&
			   state.editor_collapsed_entities[entity.uuid] {
				button.icon = .Chevron_Right
			}
			editor_ui_set_text(world, label, entity.name)
		}
		for component in world.editor_uis {
			if (component.role == .Browser_Row ||
				   component.role == .Browser_Row_Disclosure ||
				   component.role == .Browser_Row_Label) &&
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
		state.editor_browser_snapshot_valid = true
		state.editor_browser_snapshot_has_selection = state.editor_has_selection
		state.editor_browser_snapshot_selected_entity = state.editor_selected_entity
	}
	resource_count := 0
	selected_resource_row: shared.Entity_UUID
	if state.resource_registry != nil {
		for material in state.resource_registry.materials {
			if !material.alive || !material.authored {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = material.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = material.id
			if state.editor_has_resource_selection &&
			   state.editor_selected_resource == material.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, material.name)
			resource_count += 1
		}
		for texture in state.resource_registry.textures {
			if !texture.alive || !texture.authored {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = texture.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = texture.id
			if state.editor_has_resource_selection &&
			   state.editor_selected_resource == texture.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, texture.name)
			resource_count += 1
		}
		for environment in state.resource_registry.environments {
			if !environment.alive || !environment.authored {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = environment.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = environment.id
			if state.editor_has_resource_selection &&
			   state.editor_selected_resource == environment.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, environment.name)
			resource_count += 1
		}
		for model in state.resource_registry.models {
			if !model.alive || !model.authored {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = model.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = model.id
			if state.editor_has_resource_selection && state.editor_selected_resource == model.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, model.name)
			resource_count += 1
		}
	}
	for component in world.editor_uis {
		if (component.role == .Project_Resource_Row ||
			   component.role == .Project_Resource_Row_Label) &&
		   component.slot >= resource_count {
			if component.entity_index < 0 || component.entity_index >= len(world.entities) {
				continue
			}
			entity := world.entities[component.entity_index]
			if !entity.alive || entity.origin != .Editor {
				continue
			}
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
	if browser, found := editor_ui_entity(world, .Project_Resources_Scroll); found {
		editor_ui_set_panel_title(world, browser, fmt.tprintf("RESOURCES / %d", resource_count))
		if world.entities[browser].ui_list_index >= 0 &&
		   world.entities[browser].ui_list_index < len(world.ui_lists) {
			world.ui_lists[world.entities[browser].ui_list_index].selected = selected_resource_row
		}
	}
	if status, found := editor_ui_entity(world, .Status); found {
		mode := "PLAY MODE  /  PAUSED  /  CHANGES ARE TEMPORARY"
		if state.editor_simulation_playing {
			mode = "PLAY MODE  /  RUNNING  /  CHANGES ARE TEMPORARY"
		}
		if state.editor_simulation_stopped { mode = "STOPPED" }
		if state.editor_scene_dirty {
			if state.editor_simulation_playing {
				mode = "PLAY MODE  /  RUNNING  /  CHANGES ARE TEMPORARY  /  UNSAVED AUTHORING"
			} else if state.editor_simulation_stopped {
				mode = "STOPPED  /  UNSAVED"
			} else {
				mode = "PLAY MODE  /  PAUSED  /  CHANGES ARE TEMPORARY  /  UNSAVED AUTHORING"
			}
		}
		if state.editor_scene_save_failed { mode = "SAVE FAILED  /  UNSAVED" }
		if state.editor_scene_revert_failed { mode = "REVERT FAILED  /  UNSAVED" }
		editor_ui_set_text(world, status, mode)
	}

	selected_component_revision := u64(0)
	if state.editor_has_selection {
		selected_index := int(state.editor_selected_entity.index)
		if selected_index >= 0 && selected_index < len(world.entities) {
			selected_component_revision = world.entities[selected_index].component_revision
		}
	}
	selected_resource_version := u32(0)
	if state.editor_has_resource_selection && state.resource_registry != nil {
		if handle, found := resources.material_by_uuid(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			if material, alive := resources.get_material(state.resource_registry, handle); alive {
				selected_resource_version = material.version
			}
		}
		if handle, found := resources.texture_handle_by_uuid(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			if texture, alive := resources.get_texture(state.resource_registry, handle); alive {
				selected_resource_version = texture.version
			}
		}
		if handle, found := resources.model_handle_by_uuid(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			if model, alive := resources.get_model(state.resource_registry, handle); alive {
				selected_resource_version = model.version
			}
		}
		if handle, found := resources.environment_handle_by_uuid(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			if environment, alive := resources.get_environment(state.resource_registry, handle);
			   alive {
				selected_resource_version = environment.version
			}
		}
	}
	refresh_inspector :=
		!state.editor_snapshot_valid ||
		!state.editor_inspector_snapshot_valid ||
		(state.editor_simulation_playing &&
				state.editor_snapshot_elapsed >= EDITOR_SNAPSHOT_INTERVAL) ||
		state.editor_inspector_snapshot_entity != state.editor_selected_entity ||
		state.editor_inspector_snapshot_component_revision != selected_component_revision ||
		state.editor_inspector_snapshot_has_resource != state.editor_has_resource_selection ||
		state.editor_inspector_snapshot_resource != state.editor_selected_resource ||
		state.editor_inspector_snapshot_resource_version != selected_resource_version ||
		state.editor_inspector_snapshot_stopped != state.editor_simulation_stopped
	if refresh_inspector {
		if header, found := editor_ui_entity(world, .Inspector_Header); found {
			header_layout := &world.ui_layouts[world.entities[header].ui_layout_index]
			header_layout.position.y = 82
			if state.editor_has_resource_selection {
				header_layout.position.y = 114
				id_buffer: [36]u8
				editor_ui_set_text(
					world,
					header,
					shared.resource_uuid_to_string(state.editor_selected_resource, id_buffer[:]),
				)
			} else if !state.editor_has_selection {
				editor_ui_set_text(world, header, "Select an entity or resource to inspect")
			} else {
				index := int(state.editor_selected_entity.index)
				if index >= 0 && index < len(world.entities) {
					entity := world.entities[index]
					origin := "SCENE ENTITY"
					if entity.origin == .Runtime { origin = "RUNTIME ENTITY" }
					id_buffer: [36]u8
					id := shared.entity_uuid_to_string(entity.uuid, id_buffer[:])
					editor_ui_set_text(world, header, fmt.tprintf("%s  /  %s", origin, id))
				}
			}
		}
		if name_input, found := editor_ui_entity(world, .Inspector_Entity_Name); found {
			hidden := !state.editor_has_selection || state.editor_has_resource_selection
			editor_ui_set_hidden(world, name_input, hidden)
			if !hidden {
				selected_index := int(state.editor_selected_entity.index)
				if selected_index >= 0 && selected_index < len(world.entities) {
					input := &world.ui_inputs[world.entities[name_input].ui_input_index]
					input.read_only =
						!state.editor_simulation_stopped ||
						world.entities[selected_index].origin != .Scene
					if !state.has_focused_input ||
					   state.focused_input != world.entities[name_input].id {
						_ = ecs.set_ui_input_value(
							world,
							name_input,
							world.entities[selected_index].name,
						)
					}
				}
			}
		}
		resource_name, resource_name_found := editor_ui_entity(world, .Inspector_Resource_Name)
		resource_source, resource_source_found := editor_ui_entity(
			world,
			.Inspector_Resource_Source,
		)
		find_usage, find_usage_found := editor_ui_entity(world, .Project_Resource_Find_Usage)
		reimport, reimport_found := editor_ui_entity(world, .Project_Resource_Reimport)
		resource_selected :=
			state.editor_has_resource_selection &&
			state.resource_registry != nil &&
			resource_name_found &&
			resource_source_found
		if resource_name_found {
			editor_ui_set_hidden(world, resource_name, !resource_selected)
		}
		if resource_source_found {
			editor_ui_set_hidden(world, resource_source, !resource_selected)
		}
		if find_usage_found {
			editor_ui_set_hidden(
				world,
				find_usage,
				!resource_selected ||
				editor_resource_usage_count(world, state.editor_selected_resource) == 0,
			)
		}
		if reimport_found {
			importable := false
			if resource_selected {
				_, texture_found := resources.texture_handle_by_uuid(
					state.resource_registry,
					state.editor_selected_resource,
				)
				_, model_found := resources.model_handle_by_uuid(
					state.resource_registry,
					state.editor_selected_resource,
				)
				_, environment_found := resources.environment_handle_by_uuid(
					state.resource_registry,
					state.editor_selected_resource,
				)
				importable = texture_found || model_found || environment_found
			}
			editor_ui_set_hidden(world, reimport, !importable)
		}
		if resource_selected {
			handle, resource_found := resources.material_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			)
			if resource_found {
				material, alive := resources.get_material(state.resource_registry, handle)
				if alive {
					inputs := [2]int{resource_name, resource_source}
					values := [2]string{material.name, material.source}
					for input_entity, input_index in inputs {
						input := &world.ui_inputs[world.entities[input_entity].ui_input_index]
						input.read_only = !state.editor_simulation_stopped
						if !state.has_focused_input ||
						   state.focused_input != world.entities[input_entity].id {
							_ = ecs.set_ui_input_value(world, input_entity, values[input_index])
						}
					}
				} else {
					state.editor_has_resource_selection = false
				}
			} else if texture_handle, texture_found := resources.texture_handle_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			); texture_found {
				texture, alive := resources.get_texture(state.resource_registry, texture_handle)
				if alive {
					inputs := [2]int{resource_name, resource_source}
					values := [2]string{texture.name, texture.source}
					for input_entity, input_index in inputs {
						input := &world.ui_inputs[world.entities[input_entity].ui_input_index]
						input.read_only = true
						if !state.has_focused_input ||
						   state.focused_input != world.entities[input_entity].id {
							_ = ecs.set_ui_input_value(world, input_entity, values[input_index])
						}
					}
				} else {
					state.editor_has_resource_selection = false
				}
			} else if model_handle, model_found := resources.model_handle_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			); model_found {
				model, alive := resources.get_model(state.resource_registry, model_handle)
				if alive {
					inputs := [2]int{resource_name, resource_source}
					values := [2]string{model.name, model.source}
					for input_entity, input_index in inputs {
						input := &world.ui_inputs[world.entities[input_entity].ui_input_index]
						input.read_only = true
						if !state.has_focused_input ||
						   state.focused_input != world.entities[input_entity].id {
							_ = ecs.set_ui_input_value(world, input_entity, values[input_index])
						}
					}
				} else {
					state.editor_has_resource_selection = false
				}
			} else if environment_handle, environment_found :=
				resources.environment_handle_by_uuid(
					state.resource_registry,
					state.editor_selected_resource,
				); environment_found {
				environment, alive := resources.get_environment(
					state.resource_registry,
					environment_handle,
				)
				if alive {
					inputs := [2]int{resource_name, resource_source}
					values := [2]string{environment.name, environment.source}
					for input_entity, input_index in inputs {
						input := &world.ui_inputs[world.entities[input_entity].ui_input_index]
						input.read_only = true
						if !state.has_focused_input ||
						   state.focused_input != world.entities[input_entity].id {
							_ = ecs.set_ui_input_value(world, input_entity, values[input_index])
						}
					}
				} else {
					state.editor_has_resource_selection = false
				}
			} else {
				state.editor_has_resource_selection = false
			}
		}
		if header_entity := find_parent_entity(
			world,
			shared.entity_uuid_from_engine_name(EDITOR_UI_INSPECTOR_HEADER_NAME),
			.Editor,
		); header_entity >= 0 {
			header_layout := &world.ui_layouts[world.entities[header_entity].ui_layout_index]
			header_layout.size.y = 132
			if resource_selected {
				header_layout.size.y = 184
			}
		}
		if content, found := editor_ui_entity(world, .Inspector_Content); found {
			if state.editor_has_resource_selection {
				editor_ui_build_resource_inspector_panels(
					state,
					world,
					content,
					state.editor_selected_resource,
				)
			} else {
				selected_index := -1
				if state.editor_has_selection { selected_index = int(state.editor_selected_entity.index) }
				editor_ui_build_inspector_panels(state, world, content, selected_index)
			}
		}
		state.editor_inspector_snapshot_valid = true
		state.editor_inspector_snapshot_entity = state.editor_selected_entity
		state.editor_inspector_snapshot_component_revision = selected_component_revision
		state.editor_inspector_snapshot_has_resource = state.editor_has_resource_selection
		state.editor_inspector_snapshot_resource = state.editor_selected_resource
		state.editor_inspector_snapshot_resource_version = selected_resource_version
		state.editor_inspector_snapshot_stopped = state.editor_simulation_stopped
		state.editor_inspector_snapshot_refresh_count += 1
		if root, found := editor_ui_entity(world, .Root); found {
			ecs.mark_ui_layout_changed(world, root)
		}
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
	editor_ui_update_gizmo_toolbar(state, world)
	if !state.editor_snapshot_valid ||
	   !state.editor_snapshot_was_visible { refresh_editor_ecs_snapshot(state, world) }
}

editor_ui_anchor_component_menu :: proc(state: ^State, world: ^shared.World, width, height: f32) {
	editor_ui_anchor_popup(
		state,
		world,
		width,
		height,
		.Inspector_Component_Menu,
		.Inspector_Component_Menu_Button,
		.Inspector_Component_Menu_Content,
		120,
		360,
	)
}

editor_ui_anchor_resource_menu :: proc(state: ^State, world: ^shared.World, width, height: f32) {
	editor_ui_anchor_popup(
		state,
		world,
		width,
		height,
		.Inspector_Resource_Menu,
		.Inspector_Resource_Menu_Button,
		.Inspector_Resource_Menu_Content,
		100,
		300,
	)
}

editor_ui_anchor_popup :: proc(
	state: ^State,
	world: ^shared.World,
	width, height: f32,
	menu_role, button_role, content_role: shared.Editor_UI_Role,
	default_content_height, maximum_height: f32,
) {
	if state == nil || world == nil {
		return
	}
	menu, found := editor_ui_entity(world, menu_role)
	if !found {
		return
	}
	button, button_found := editor_ui_entity(world, button_role)
	if !button_found {
		return
	}
	content_height := default_content_height
	if content, content_found := editor_ui_entity(world, content_role); content_found {
		content_layout := world.ui_layouts[world.entities[content].ui_layout_index]
		content_height = content_layout.size.y + 10
	}
	_ = place_popup(
		state,
		world,
		menu,
		button,
		content_height,
		width,
		height,
		{220, 420, maximum_height, 10, 4, EDITOR_TOP_BAR_HEIGHT - 4, EDITOR_STATUS_BAR_HEIGHT - 4},
	)
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
	if binding.role != .Inspector_Input &&
	   binding.role != .Inspector_Entity_Name &&
	   binding.role != .Inspector_Resource_Name &&
	   binding.role != .Inspector_Resource_Source {
		return {}, nil, false
	}
	return binding, &world.ui_inputs[entity.ui_input_index], true
}

editor_ui_prepare_input_focus :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	if state != nil &&
	   world != nil &&
	   state.has_focused_input &&
	   entity_index >= 0 &&
	   entity_index < len(world.entities) &&
	   state.focused_input == world.entities[entity_index].id {
		return
	}
	binding, input, found := editor_ui_input_binding(world, entity_index)
	if !found || !input.numeric {
		return
	}
	if binding.resource_id != (shared.Resource_UUID{}) {
		if number, ok := editor_resource_number(state, binding^); ok {
			set_numeric_input_text(state, world, entity_index, input, number)
			binding.input_original_number = number
			binding.input_has_original_number = true
			binding.input_was_scrubbed = false
		}
		return
	}
	if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
		if number, ok := editor_reflected_read_number(state, world, binding^); ok {
			set_numeric_input_text(state, world, entity_index, input, number)
			binding.input_original_number = number
			binding.input_has_original_number = true
			binding.input_was_scrubbed = false
		}
		return
	}
	if number, ok := read_inspector_numeric(world, binding^); ok {
		set_numeric_input_text(state, world, entity_index, input, number)
		binding.input_original_number = number
		binding.input_has_original_number = true
		binding.input_was_scrubbed = false
	}
}

editor_ui_consume_input_state :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	binding, input, found := editor_ui_input_binding(world, entity_index)
	if !found {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_state_index < 0 || entity.ui_state_index >= len(world.ui_states) {
		return
	}
	interaction := world.ui_states[entity.ui_state_index]
	if binding.role == .Inspector_Entity_Name {
		if interaction.submitted {
			if selected, ok := editor_selected_world_index(state, world); ok {
				_ = editor_authoring_rename_entity(state, world, selected, input.text)
			}
		}
		return
	}
	if binding.role == .Inspector_Resource_Name || binding.role == .Inspector_Resource_Source {
		if interaction.submitted &&
		   state.editor_has_resource_selection &&
		   state.resource_registry != nil {
			handle, resource_found := resources.material_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			)
			if resource_found {
				material, alive := resources.get_material(state.resource_registry, handle)
				if alive {
					name := material.name
					source := material.source
					if binding.role == .Inspector_Resource_Name {
						name = input.text
					} else {
						source = input.text
					}
					_ = editor_authoring_update_resource_identity(state, name, source)
				}
			}
		}
		return
	}
	if binding.resource_id != (shared.Resource_UUID{}) {
		if (interaction.changed || interaction.submitted || interaction.cancelled) &&
		   !binding.input_has_original_number {
			if number, ok := editor_resource_number(state, binding^); ok {
				binding.input_original_number = number
				binding.input_has_original_number = true
			}
		}
		if interaction.changed && interaction.valid {
			_ = editor_resource_write_number(state, binding^, input.number)
			if state.input_scrubbing {
				binding.input_was_scrubbed = true
			}
		}
		if interaction.cancelled && binding.input_was_scrubbed {
			_ = editor_resource_write_number(state, binding^, input.number)
			editor_recompute_scene_dirty(state)
		}
		if interaction.cancelled {
			binding.input_has_original_number = false
			binding.input_was_scrubbed = false
		}
		if interaction.submitted {
			_ = editor_resource_write_number(state, binding^, input.number)
			if binding.input_has_original_number {
				editor_history_push_resource(
					state,
					binding^,
					binding.input_original_number,
					input.number,
				)
			}
			binding.input_has_original_number = false
			binding.input_was_scrubbed = false
		}
		return
	}
	if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
		if input.numeric && interaction.changed && interaction.valid && state.input_scrubbing {
			if editor_reflected_preview_number(state, world, binding^, input.number) {
				binding.input_was_scrubbed = true
			}
		}
		if interaction.cancelled && binding.input_was_scrubbed {
			_ = editor_reflected_finish_number_scrub(
				state,
				world,
				binding^,
				binding.input_original_number,
				input.number,
				true,
			)
			binding.input_has_original_number = false
			binding.input_was_scrubbed = false
		}
		if interaction.submitted {
			if input.numeric && binding.input_was_scrubbed {
				_ = editor_reflected_finish_number_scrub(
					state,
					world,
					binding^,
					binding.input_original_number,
					input.number,
					false,
				)
			} else {
				_ = editor_reflected_apply_text(state, world, binding^, input.text)
			}
			binding.input_has_original_number = false
			binding.input_was_scrubbed = false
		}
		return
	}
	if !input.numeric {
		return
	}
	if (interaction.changed || interaction.submitted || interaction.cancelled) &&
	   !binding.input_has_original_number {
		if number, ok := read_inspector_numeric(world, binding^); ok {
			binding.input_original_number = number
			binding.input_has_original_number = true
		}
	}
	if interaction.changed && interaction.valid {
		_ = write_inspector_numeric(state, world, binding^, input.number)
		if state.input_scrubbing {
			binding.input_was_scrubbed = true
		}
	}
	if interaction.cancelled && binding.input_was_scrubbed {
		_ = write_inspector_numeric(state, world, binding^, input.number)
		editor_recompute_scene_dirty(state)
	}
	if interaction.cancelled {
		binding.input_has_original_number = false
		binding.input_was_scrubbed = false
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
		binding.input_was_scrubbed = false
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
	   !state.editor_simulation_stopped ||
	   (state.has_focused_input && !state.focused_input_editor) ||
	   (!keyboard.undo && !keyboard.redo) {
		return false
	}
	if state.has_focused_input {
		entity_index := int(state.focused_input.index)
		entity := world.entities[entity_index]
		if entity.ui_input_index >= 0 &&
		   entity.ui_input_index < len(world.ui_inputs) &&
		   world.ui_inputs[entity.ui_input_index].numeric {
			blur_input_edit(state, world)
		} else {
			if !finish_input_edit(state, world) {
				cancel_input_edit(state, world)
			}
			sync_ui_interaction_states(state, world)
			editor_ui_consume_input_state(state, world, entity_index)
			clear_input_focus(state)
		}
	}
	if keyboard.redo {
		_ = editor_redo(state, world)
	} else {
		_ = editor_undo(state, world)
	}
	return true
}

editor_ui_handle_save_shortcut :: proc(
	state: ^State,
	world: ^shared.World,
	keyboard: Keyboard_Input,
) -> bool {
	if state == nil ||
	   world == nil ||
	   !state.editor_visible ||
	   (state.has_focused_input && !state.focused_input_editor) ||
	   !keyboard.save {
		return false
	}
	if state.has_focused_input {
		entity_index := int(state.focused_input.index)
		entity := world.entities[entity_index]
		if entity.ui_input_index >= 0 &&
		   entity.ui_input_index < len(world.ui_inputs) &&
		   world.ui_inputs[entity.ui_input_index].numeric {
			blur_input_edit(state, world)
		} else {
			if !finish_input_edit(state, world) {
				cancel_input_edit(state, world)
			}
			sync_ui_interaction_states(state, world)
			editor_ui_consume_input_state(state, world, entity_index)
			clear_input_focus(state)
		}
	}
	editor_save(state)
	return true
}
