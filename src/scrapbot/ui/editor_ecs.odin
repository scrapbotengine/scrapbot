package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strconv"
import "core:strings"

EDITOR_UI_ROOT_NAME :: "__scrapbot_editor_root"
EDITOR_UI_TOP_NAME :: "__scrapbot_editor_top"
EDITOR_UI_TRANSPORT_NAME :: "__scrapbot_editor_transport"
EDITOR_UI_WORKSPACE_NAME :: "__scrapbot_editor_workspace"
EDITOR_UI_LEFT_NAME :: "__scrapbot_editor_left"
EDITOR_UI_LEFT_DOCK_ITEM_NAME :: "__scrapbot_editor_left_dock_item"
EDITOR_UI_LEFT_CONTENT_NAME :: "__scrapbot_editor_left_content"
EDITOR_UI_DIAGNOSTICS_NAME :: "__scrapbot_editor_diagnostics"
EDITOR_UI_DIAGNOSTICS_TABLE_NAME :: "__scrapbot_editor_diagnostics_table"
EDITOR_UI_SYSTEMS_NAME :: "__scrapbot_editor_systems"
EDITOR_UI_SYSTEMS_FILTER_NAME :: "__scrapbot_editor_systems_filter"
EDITOR_UI_SYSTEMS_LIST_NAME :: "__scrapbot_editor_systems_list"
EDITOR_UI_SCENE_NAME :: "__scrapbot_editor_scene"
EDITOR_UI_SCENE_FILTER_NAME :: "__scrapbot_editor_scene_filter"
EDITOR_UI_SCENE_LIST_NAME :: "__scrapbot_editor_scene_list"
EDITOR_UI_SCENE_TOOLS_NAME :: "__scrapbot_editor_scene_tools"
EDITOR_UI_RESOURCES_NAME :: "__scrapbot_editor_resources"
EDITOR_UI_RESOURCES_FILTER_NAME :: "__scrapbot_editor_resources_filter"
EDITOR_UI_RESOURCES_LIST_NAME :: "__scrapbot_editor_resources_list"
EDITOR_UI_RESOURCE_TOOLS_NAME :: "__scrapbot_editor_resource_tools"
EDITOR_UI_VIEWPORT_NAME :: "__scrapbot_editor_viewport"
EDITOR_UI_VIEWPORT_DOCK_NAME :: "__scrapbot_editor_viewport_dock"
EDITOR_UI_VIEWPORT_TAB_NAME :: "__scrapbot_editor_viewport_tab"
EDITOR_UI_GIZMO_TOOLBAR_NAME :: "__scrapbot_editor_gizmo_toolbar"
EDITOR_UI_PLACEMENT_TOOLBAR_NAME :: "__scrapbot_editor_placement_toolbar"
EDITOR_UI_PLACEMENT_SNAP_NAME :: "__scrapbot_editor_placement_snap"
EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME :: "__scrapbot_editor_debug_view_toolbar"
EDITOR_UI_DEBUG_VIEW_BUTTON_NAME :: "__scrapbot_editor_debug_view_button"
EDITOR_UI_DEBUG_VIEW_MENU_NAME :: "__scrapbot_editor_debug_view_menu"
EDITOR_UI_DEBUG_VIEW_MENU_CONTENT_NAME :: "__scrapbot_editor_debug_view_menu_content"
EDITOR_UI_DEBUG_HIZ_MIP_DECREASE_NAME :: "__scrapbot_editor_debug_hiz_mip_decrease"
EDITOR_UI_DEBUG_HIZ_MIP_LABEL_NAME :: "__scrapbot_editor_debug_hiz_mip_label"
EDITOR_UI_DEBUG_HIZ_MIP_INCREASE_NAME :: "__scrapbot_editor_debug_hiz_mip_increase"
EDITOR_UI_DEBUG_OCCLUSION_FREEZE_NAME :: "__scrapbot_editor_debug_occlusion_freeze"
EDITOR_UI_RIGHT_NAME :: "__scrapbot_editor_right"
EDITOR_UI_RIGHT_DOCK_ITEM_NAME :: "__scrapbot_editor_right_dock_item"
EDITOR_UI_RIGHT_CONTENT_NAME :: "__scrapbot_editor_right_content"
EDITOR_UI_INSPECTOR_HEADER_NAME :: "__scrapbot_editor_inspector_header"
EDITOR_UI_STATUS_NAME :: "__scrapbot_editor_status"
EDITOR_UI_ENUM_MENU_NAME :: "__scrapbot_editor_enum_menu"
EDITOR_UI_ENUM_MENU_CONTENT_NAME :: "__scrapbot_editor_enum_menu_content"
EDITOR_UI_ENTITY_MENU_NAME :: "__scrapbot_editor_entity_menu"
EDITOR_UI_ENTITY_MENU_FILTER_NAME :: "__scrapbot_editor_entity_menu_filter"
EDITOR_UI_ENTITY_MENU_CONTENT_NAME :: "__scrapbot_editor_entity_menu_content"
EDITOR_UI_COMPONENT_MENU_NAME :: "__scrapbot_editor_component_menu"
EDITOR_UI_COMPONENT_MENU_FILTER_NAME :: "__scrapbot_editor_component_menu_filter"
EDITOR_UI_COMPONENT_MENU_CONTENT_NAME :: "__scrapbot_editor_component_menu_content"
EDITOR_UI_RESOURCE_MENU_NAME :: "__scrapbot_editor_resource_menu"
EDITOR_UI_RESOURCE_MENU_CONTENT_NAME :: "__scrapbot_editor_resource_menu_content"
EDITOR_SIDEBAR_PADDING :: f32(8)
EDITOR_SIDEBAR_SECTION_GAP :: f32(4)
EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT :: f32(780)
EDITOR_DOCK_TAB_HEIGHT :: f32(28)
EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT :: EDITOR_SIDEBAR_CONTENT_MIN_HEIGHT - EDITOR_DOCK_TAB_HEIGHT
EDITOR_SECTION_TITLE_HEIGHT :: f32(28)
EDITOR_BROWSER_FILTER_HEIGHT :: f32(32)
EDITOR_BROWSER_TEXT_INSET :: f32(20)
EDITOR_ACTION_RESOURCE_MODEL :: "editor.resource.model"
EDITOR_ACTION_DROP_VIEWPORT :: "editor.drop.viewport"
EDITOR_ACTION_DROP_SCENE_ROOT :: "editor.drop.scene-root"
EDITOR_ACTION_DROP_SCENE_PARENT :: "editor.drop.scene-parent"

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
				case .Placement_Snap:
					switch state.editor_placement_snap_step {
						case 0:
							state.editor_placement_snap_step = 0.25
						case 0.25:
							state.editor_placement_snap_step = 0.5
						case 0.5:
							state.editor_placement_snap_step = 1
						case:
							state.editor_placement_snap_step = 0
					}
					editor_ui_update_placement_snap_button(state, world)
					return
				case .Debug_View_Item:
					if binding.slot < 0 {
						state.editor_render_debug_view_override = false
					} else if binding.slot <= int(shared.Render_Debug_View.World_Distance_Field) {
						state.editor_render_debug_view_override = true
						state.editor_render_debug_view = shared.Render_Debug_View(binding.slot)
					}
					editor_ui_update_debug_view_button(state, world)
					return
				case .Debug_HiZ_Mip_Decrease:
					if state.editor_render_debug_hiz_mip > 0 {
						state.editor_render_debug_hiz_mip -= 1
					}
					editor_ui_update_debug_view_button(state, world)
					return
				case .Debug_HiZ_Mip_Increase:
					state.editor_render_debug_hiz_mip = min(
						state.editor_render_debug_hiz_mip + 1,
						15,
					)
					editor_ui_update_debug_view_button(state, world)
					return
				case .Debug_Occlusion_Freeze:
					state.editor_render_debug_occlusion_frozen = !state.editor_render_debug_occlusion_frozen
					editor_ui_update_debug_view_button(state, world)
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
				case .Inspector_Enum_Menu_Button:
					if binding.read_only {
						return
					}
					if menu, found := editor_ui_entity(world, .Inspector_Enum_Menu); found {
						layout := world.ui_layouts[world.entities[menu].ui_layout_index]
						if layout.popup_open {
							editor_ui_build_enum_menu(state, world, binding)
						}
					}
					return
				case .Inspector_Enum_Menu_Item:
					if name, found := editor_reflected_enum_option_name(
						state,
						world,
						binding,
						binding.slot,
					); found {
						_ = editor_reflected_apply_text(state, world, binding, name)
					}
					return
				case .Inspector_Entity_Menu_Button:
					if binding.read_only {
						return
					}
					if menu, found := editor_ui_entity(world, .Inspector_Entity_Menu); found {
						layout := world.ui_layouts[world.entities[menu].ui_layout_index]
						if layout.popup_open {
							editor_ui_build_entity_menu(state, world, binding)
						}
					}
					return
				case .Inspector_Entity_Menu_Item:
					if !binding.read_only {
						_ = editor_reflected_apply_entity_reference(
							state,
							world,
							binding,
							binding.entity_reference,
						)
					}
					return
				case .Inspector_Container_Disclosure:
					role := &world.editor_uis[entity.editor_ui_index]
					role.expanded = !role.expanded
					state.editor_snapshot_valid = false
					return
				case .Inspector_Component_Menu_Button:
					if menu, found := editor_ui_entity(world, .Inspector_Component_Menu); found {
						layout := world.ui_layouts[world.entities[menu].ui_layout_index]
						if layout.popup_open {
							state.editor_snapshot_valid = false
							if selected, ok := editor_selected_world_index(state, world); ok {
								editor_ui_build_component_menu(state, world, selected)
							}
						}
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
				case .Inspector_Preview_Place:
					if state.editor_has_resource_selection {
						editor_request_model_placement(state, state.editor_selected_resource)
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
					if menu, found := editor_ui_entity(world, .Inspector_Component_Menu); found {
						_ = set_popup_open(world, menu, false)
					}
					return
				case .Inspector_Resource_Menu_Button:
					if !state.editor_simulation_stopped {
						return
					}
					if menu, found := editor_ui_entity(world, .Inspector_Resource_Menu); found {
						layout := world.ui_layouts[world.entities[menu].ui_layout_index]
						if layout.popup_open {
							state.editor_snapshot_valid = false
							editor_ui_build_resource_menu(state, world)
						}
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
				     .Placement_Toolbar,
				     .Debug_View_Toolbar,
				     .Debug_View_Button,
				     .Debug_View_Menu,
				     .Debug_View_Menu_Content,
				     .Debug_HiZ_Mip_Label,
				     .Diagnostics_Panel,
				     .Diagnostics_Label,
				     .Diagnostics_Value,
				     .Systems_Scroll,
				     .Systems_Row,
				     .Systems_Name,
				     .Systems_Time,
				     .Systems_Origin,
				     .Browser_Filter,
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
				     .Inspector_Color_Button,
				     .Inspector_Color_Picker,
				     .Inspector_Enum_Menu,
				     .Inspector_Enum_Menu_Content,
				     .Inspector_Entity_Menu,
				     .Inspector_Entity_Menu_Filter,
				     .Inspector_Entity_Menu_Content,
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

editor_resource_drag_source :: proc(
	world: ^shared.World,
	source: shared.Entity_UUID,
) -> (
	shared.Resource_UUID,
	bool,
) {
	if world == nil {
		return {}, false
	}
	entity_index, found := ecs.entity_index_by_uuid(world, source)
	if !found {
		return {}, false
	}
	entity := world.entities[entity_index]
	if entity.editor_ui_index < 0 || entity.editor_ui_index >= len(world.editor_uis) {
		return {}, false
	}
	binding := world.editor_uis[entity.editor_ui_index]
	if binding.role != .Project_Resource_Row {
		return {}, false
	}
	return binding.resource_id, true
}

editor_ui_consume_events :: proc(
	state: ^State,
	world: ^shared.World,
	after_sequence: u64,
) -> bool {
	if state == nil || world == nil {
		return false
	}
	layout_changed := false
	event_count := ecs.ui_event_count_after(world, after_sequence)
	for event_index in 0 ..< event_count {
		event, found := ecs.ui_event_after_at(world, after_sequence, event_index)
		if !found || event.origin != .Editor {
			continue
		}
		entity_index, entity_found := ecs.entity_index_by_uuid(world, event.entity)
		if !entity_found {
			continue
		}
		entity := world.entities[entity_index].id
		switch event.kind {
			case .Activated:
				editor_ui_handle_activation(state, world, entity, event.position)
			case .Changed:
				if event.part == .Panel_Title {
					editor_ui_handle_panel_change(state, world, entity)
				} else {
					editor_ui_handle_checkbox_change(state, world, entity)
				}
			case .Dropped:
				if event.action == EDITOR_ACTION_DROP_VIEWPORT ||
				   event.action == EDITOR_ACTION_DROP_SCENE_ROOT ||
				   event.action == EDITOR_ACTION_DROP_SCENE_PARENT {
					if resource_id, resource_found := editor_resource_drag_source(
						world,
						event.drag_source,
					); resource_found {
						parent: shared.Entity_UUID
						if event.action == EDITOR_ACTION_DROP_SCENE_PARENT {
							parent_entity, parent_found := editor_hierarchy_binding_target(
								world,
								world.entities[entity_index].id,
								true,
							)
							if !parent_found {
								continue
							}
							parent_index := int(parent_entity.index)
							if !ecs.entity_is_alive(world, parent_index) ||
							   world.entities[parent_index].id != parent_entity {
								continue
							}
							parent = world.entities[parent_index].uuid
						}
						if event.action == EDITOR_ACTION_DROP_VIEWPORT {
							editor_request_model_placement(
								state,
								resource_id,
								parent,
								event.position,
							)
						} else {
							editor_request_model_placement(state, resource_id, parent)
						}
						layout_changed = true
						continue
					}
				}
				list_index := entity_index
				if !ecs.entity_is_alive(world, list_index) ||
				   world.entities[list_index].editor_ui_index < 0 ||
				   world.entities[list_index].editor_ui_index >= len(world.editor_uis) ||
				   world.editor_uis[world.entities[list_index].editor_ui_index].role !=
					   .Browser_Scroll {
					continue
				}
				source_ui_index, source_uuid_found := ecs.entity_index_by_uuid(
					world,
					event.drag_source,
				)
				if !source_uuid_found {
					continue
				}
				source, source_found := editor_hierarchy_binding_target(
					world,
					world.entities[source_ui_index].id,
				)
				if !source_found {
					continue
				}
				source_index := int(source.index)
				if event.drop_placement == .Before || event.drop_placement == .After {
					target_ui_index, target_uuid_found := ecs.entity_index_by_uuid(
						world,
						event.drop_target,
					)
					if !target_uuid_found {
						continue
					}
					target, target_found := editor_hierarchy_binding_target(
						world,
						world.entities[target_ui_index].id,
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
				if event.drop_target != (shared.Entity_UUID{}) {
					target_ui_index, target_uuid_found := ecs.entity_index_by_uuid(
						world,
						event.drop_target,
					)
					if !target_uuid_found {
						continue
					}
					target, target_found := editor_hierarchy_binding_target(
						world,
						world.entities[target_ui_index].id,
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
			case .Submitted, .Cancelled:
				editor_ui_consume_input_state(state, world, entity_index)
		}
	}
	for &binding in world.editor_uis {
		if binding.role != .Inspector_Color_Picker {
			continue
		}
		editor_ui_consume_color_picker_state(state, world, &binding)
	}
	layout_changed = state.editor_layout_invalidated || layout_changed
	state.editor_layout_invalidated = false
	return layout_changed
}

editor_ui_consume_color_picker_state :: proc(
	state: ^State,
	world: ^shared.World,
	binding: ^shared.Editor_UI_Component,
) {
	if state == nil ||
	   world == nil ||
	   binding == nil ||
	   binding.entity_index < 0 ||
	   binding.entity_index >= len(world.entities) {
		return
	}
	entity := world.entities[binding.entity_index]
	if !entity.alive ||
	   entity.ui_color_picker_index < 0 ||
	   entity.ui_color_picker_index >= len(world.ui_color_pickers) ||
	   entity.ui_state_index < 0 ||
	   entity.ui_state_index >= len(world.ui_states) {
		return
	}
	interaction := world.ui_states[entity.ui_state_index]
	if !interaction.changed && !interaction.submitted && !interaction.cancelled {
		return
	}
	picker := world.ui_color_pickers[entity.ui_color_picker_index]
	if interaction.changed && !binding.color_has_original {
		original: shared.Vec4
		component_count := binding.color_component_count
		found := false
		if binding.resource_id != (shared.Resource_UUID{}) {
			original, component_count, found = editor_resource_color(state, binding^)
		} else if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
			original, component_count, found = editor_reflected_read_color(state, world, binding^)
		}
		if found {
			binding.color_original = original
			binding.color_component_count = component_count
			binding.color_has_original = true
		}
	}
	if interaction.changed {
		if binding.resource_id != (shared.Resource_UUID{}) {
			_ = editor_resource_write_color(state, binding^, picker.value)
		} else if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
			_ = editor_reflected_preview_color(
				state,
				world,
				binding^,
				picker.value,
				binding.color_component_count,
			)
		}
	}
	if interaction.cancelled && binding.color_has_original {
		if binding.resource_id != (shared.Resource_UUID{}) {
			_ = editor_resource_write_color(state, binding^, binding.color_original)
		} else if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
			_ = editor_reflected_preview_color(
				state,
				world,
				binding^,
				binding.color_original,
				binding.color_component_count,
			)
		}
		editor_recompute_scene_dirty(state)
		binding.color_has_original = false
	}
	if interaction.submitted {
		if binding.color_has_original {
			if binding.resource_id != (shared.Resource_UUID{}) {
				editor_history_push_resource_color(
					state,
					binding^,
					binding.color_original,
					picker.value,
					binding.color_component_count,
				)
			} else if binding.reflected_component_id != shared.INVALID_COMPONENT_ID {
				_ = editor_reflected_finish_color(
					state,
					world,
					binding^,
					binding.color_original,
					picker.value,
					binding.color_component_count,
				)
			}
		}
		binding.color_has_original = false
	}
}

editor_ui_handle_shortcuts :: proc(state: ^State, keyboard: Keyboard_Input) {
	if state == nil {
		return
	}
	if keyboard.editor_toggle {
		editor_toggle(state)
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
	theme := reduced_dark_theme()
	_, value := theme_button(theme, .Quiet)
	value.text = " "
	value.color = {0, 0, 0, 0}
	value.size = 1
	_ = ecs.set_ui_button(world, entity_index, value)
}

editor_ui_create_transport_button :: proc(
	world: ^shared.World,
	name, parent, label: string,
	role: shared.Editor_UI_Role,
	icon: string = "",
) -> int {
	theme := reduced_dark_theme()
	layout, value := theme_button(theme, .Quiet)
	layout.size = {58, theme.metrics.control_height}
	if icon != "" {
		layout.size.x = 74
	}
	button := editor_ui_create_box(world, name, parent, role, layout)
	value.text = label
	if icon != "" {
		value.icon_set = shared.builtin_icon_set_uuid()
		value.icon = icon
		value.icon_size = 16
		value.icon_gap = 5
		value.icon_inset = 1
	}
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

editor_ui_add_color_picker :: proc(
	world: ^shared.World,
	entity_index: int,
	value: shared.UI_Color_Picker_Component,
) {
	_ = ecs.set_ui_color_picker(world, entity_index, value)
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
	value := theme_scroll_area(reduced_dark_theme())
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

editor_ui_add_dock_space :: proc(
	world: ^shared.World,
	entity_index: int,
	theme: shared.UI_Theme,
	draggable: bool = true,
	split_horizontal: bool = false,
	split_vertical: bool = false,
	content_sheet: bool = true,
) {
	value := shared.ui_dock_space_default()
	value.font = theme.font
	value.tab_height = EDITOR_DOCK_TAB_HEIGHT
	value.tab_min_width = 84
	value.tab_max_width = 180
	value.tab_gap = 2
	value.tab_padding = 10
	value.tab_size = theme.metrics.small_text_size
	value.tab_corner_radius = theme.metrics.radius_small
	value.tab_connection_height = 4
	value.tab_content_overlap = 1
	value.tab_strip_background = theme.palette.region
	value.content_background = theme.palette.panel
	if !content_sheet {
		value.content_background.w = 0
	}
	value.content_corner_radius = theme.metrics.radius_small
	value.content_padding = {
		theme.metrics.gap_small,
		theme.metrics.gap_small,
		theme.metrics.gap_small,
		theme.metrics.gap_small,
	}
	value.tab_color = theme.palette.text_secondary
	value.tab_active_color = theme.palette.text
	value.tab_background = {
		theme.palette.region.x,
		theme.palette.region.y,
		theme.palette.region.z,
		0,
	}
	value.tab_hover_background = theme.palette.hover
	value.tab_active_background = theme.palette.panel
	value.drop_background = {
		theme.palette.accent.x,
		theme.palette.accent.y,
		theme.palette.accent.z,
		0.22,
	}
	value.draggable = draggable
	value.split_horizontal = split_horizontal
	value.split_vertical = split_vertical
	value.split_gap = EDITOR_SIDEBAR_SECTION_GAP
	value.split_min_size = 120
	_ = ecs.set_ui_dock_space(world, entity_index, value)
}

editor_ui_add_dock_item :: proc(
	world: ^shared.World,
	entity_index: int,
	title: string,
	movable: bool = true,
) {
	value := shared.ui_dock_item_default()
	value.title = title
	value.movable = movable
	_ = ecs.set_ui_dock_item(world, entity_index, value)
}

editor_ui_section_layout :: proc(size: shared.Vec2) -> shared.UI_Layout_Component {
	theme := reduced_dark_theme()
	layout, _ := theme_panel(theme)
	layout.size = size
	layout.fill_width = true
	layout.background = theme.palette.region
	layout.corner_radius = theme.metrics.radius_small
	return layout
}

editor_ui_list_section_layout :: proc(size: shared.Vec2) -> shared.UI_Layout_Component {
	theme := reduced_dark_theme()
	layout := shared.UI_Layout_Component {
		size = size,
		fill_width = true,
		background = theme.palette.region,
		border_color = theme.palette.border,
		corner_radius = theme.metrics.radius_small,
	}
	return layout
}

editor_ui_add_section_panel :: proc(
	world: ^shared.World,
	entity_index: int,
	title: string,
	movable: bool = false,
) {
	theme := reduced_dark_theme()
	_, value := theme_panel(theme)
	value.title = title
	value.title_background = theme.palette.control
	value.title_height = EDITOR_SECTION_TITLE_HEIGHT
	value.collapsible = true
	value.movable = movable
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

editor_ui_create_browser_filter :: proc(
	world: ^shared.World,
	name, parent: string,
	slot: int,
	role: shared.Editor_UI_Role = .Browser_Filter,
) -> int {
	theme := reduced_dark_theme()
	layout, value := theme_input(theme)
	layout.size = {1, EDITOR_BROWSER_FILTER_HEIGHT}
	layout.margin = {2, 0, 2, 0}
	layout.fill_width = true
	layout.fixed_in_fill = true
	entity_index := editor_ui_create_box(world, name, parent, role, layout, slot)
	value.prefix = ""
	value.prefix_width = 0
	value.icon_set = shared.builtin_icon_set_uuid()
	value.icon = "magnifying-glass"
	value.icon_size = 14
	value.icon_inset = 0
	editor_ui_add_input(world, entity_index, value)
	return entity_index
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
	theme := reduced_dark_theme()
	text := theme.palette.text
	muted := theme.palette.text_muted
	mint := theme.palette.accent
	root := editor_ui_create_box(
		world,
		EDITOR_UI_ROOT_NAME,
		"",
		.Root,
		{size = {1280, 720}, fill_width = true, fill_height = true},
	)
	editor_ui_add_vstack(world, root, {fill = true})
	top_layout := theme_chrome_bar(theme)
	top_layout.size = {1280, EDITOR_TOP_BAR_HEIGHT}
	top_layout.fixed_in_fill = true
	top_layout.padding = {11, 14, 11, 14}
	top := editor_ui_create_box(world, EDITOR_UI_TOP_NAME, EDITOR_UI_ROOT_NAME, .None, top_layout)
	editor_ui_add_hstack(world, top, {gap = 16})
	brand := editor_ui_create_box(
		world,
		"__scrapbot_editor_brand",
		EDITOR_UI_TOP_NAME,
		.None,
		{size = {180, 30}},
	)
	editor_ui_add_text(world, brand, "Scrapbot", text, EDITOR_TEXT_SIZE)
	transport := editor_ui_create_box(
		world,
		EDITOR_UI_TRANSPORT_NAME,
		EDITOR_UI_TOP_NAME,
		.None,
		{size = {566, 30}},
	)
	editor_ui_add_hstack(world, transport, {gap = 4})
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_play",
		EDITOR_UI_TRANSPORT_NAME,
		"PLAY",
		.Transport_Play,
		"play",
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_pause",
		EDITOR_UI_TRANSPORT_NAME,
		"PAUSE",
		.Transport_Pause,
		"pause",
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_stop",
		EDITOR_UI_TRANSPORT_NAME,
		"STOP",
		.Transport_Stop,
		"stop",
	)
	_ = editor_ui_create_transport_button(
		world,
		"__scrapbot_editor_step",
		EDITOR_UI_TRANSPORT_NAME,
		"STEP",
		.Transport_Step,
		"skip-forward",
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
			background = theme.palette.region,
		},
	)
	editor_ui_add_dock_space(world, left, theme)
	editor_ui_add_scroll(world, left)
	left_dock_item := editor_ui_create_box(
		world,
		EDITOR_UI_LEFT_DOCK_ITEM_NAME,
		EDITOR_UI_LEFT_NAME,
		.None,
		{
			size = {
				EDITOR_LEFT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
			fit_content_height = true,
			background = theme.palette.region,
		},
	)
	editor_ui_add_dock_item(world, left_dock_item, "BROWSE")
	left_content := editor_ui_create_box(
		world,
		EDITOR_UI_LEFT_CONTENT_NAME,
		EDITOR_UI_LEFT_DOCK_ITEM_NAME,
		.None,
		{
			size = {
				EDITOR_LEFT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
		},
	)
	editor_ui_add_vstack(
		world,
		left_content,
		{
			gap = EDITOR_SIDEBAR_SECTION_GAP,
			fill = true,
			draggable = true,
			min_size = 120,
			reorderable = true,
			drag_threshold = 5,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
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
	diagnostics_layout.min_size.y = 120
	diagnostics_layout.stack_order = 0
	editor_ui_add_section_panel(world, diagnostics, "PERFORMANCE", true)
	editor_ui_add_vstack(
		world,
		diagnostics,
		{
			fill = true,
			reorderable = true,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	diagnostics_table := editor_ui_create_box(
		world,
		EDITOR_UI_DIAGNOSTICS_TABLE_NAME,
		EDITOR_UI_DIAGNOSTICS_NAME,
		.None,
		{size = {100, 208}, min_size = {1, 1}, fill_width = true, fill_height = true},
	)
	editor_ui_add_table(
		world,
		diagnostics_table,
		{columns = 2, column_gap = 8, row_gap = 0, proportional_columns = true},
	)
	editor_ui_add_scroll(world, diagnostics_table)
	diagnostic_labels := [?]string {
		"FPS",
		"CPU FRAME",
		"GPU FRAME",
		"GPU SCENE",
		"RENDER SCALE",
		"SHADOW MAP",
		"POST QUALITY",
		"ENTITIES",
		"RETAINED BATCHES",
		"VISIBLE BATCHES",
		"VISIBLE MESHLET DRAWS",
		"HI-Z CULLING",
		"FRUSTUM CULLED",
		"OBJECT OCCLUSION",
		"MESHLET OCCLUSION",
	}
	for label_text, slot in diagnostic_labels {
		label_name := fmt.tprintf("__scrapbot_editor_diagnostics_label_%d", slot)
		label := editor_ui_create_box(
			world,
			label_name,
			EDITOR_UI_DIAGNOSTICS_TABLE_NAME,
			.Diagnostics_Label,
			{size = {1, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {4, 3, 3, 4}},
			slot,
		)
		editor_ui_add_text(
			world,
			label,
			label_text,
			theme.palette.text_secondary,
			EDITOR_TEXT_SIZE,
		)
		value_name := fmt.tprintf("__scrapbot_editor_diagnostics_value_%d", slot)
		value := editor_ui_create_box(
			world,
			value_name,
			EDITOR_UI_DIAGNOSTICS_TABLE_NAME,
			.Diagnostics_Value,
			{size = {1, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {4, 3, 3, 4}},
			slot,
		)
		editor_ui_add_text(world, value, "--", theme.palette.text, EDITOR_TEXT_SIZE)
		world.ui_texts[world.entities[value].ui_text_index].alignment = .Right
	}
	systems := editor_ui_create_box(
		world,
		EDITOR_UI_SYSTEMS_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.None,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 178}),
	)
	world.ui_layouts[world.entities[systems].ui_layout_index].stack_order = 1
	editor_ui_add_section_panel(world, systems, "SYSTEMS / 0", true)
	editor_ui_add_vstack(
		world,
		systems,
		{
			fill = true,
			reorderable = true,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	systems_filter := editor_ui_create_browser_filter(
		world,
		EDITOR_UI_SYSTEMS_FILTER_NAME,
		EDITOR_UI_SYSTEMS_NAME,
		2,
	)
	systems_list := editor_ui_create_box(
		world,
		EDITOR_UI_SYSTEMS_LIST_NAME,
		EDITOR_UI_SYSTEMS_NAME,
		.Systems_Scroll,
		{size = {2000, 110}, fill_width = true},
	)
	systems_list_value := theme_list(theme)
	systems_list_value.filter_input = world.entities[systems_filter].uuid
	systems_list_value.gap = 2
	systems_list_value.virtualized = true
	systems_list_value.item_height = SYSTEM_PROFILE_CELL_HEIGHT
	systems_list_value.overscan = 2
	editor_ui_add_list(world, systems_list, systems_list_value)
	editor_ui_add_scroll(world, systems_list)
	scene := editor_ui_create_box(
		world,
		EDITOR_UI_SCENE_NAME,
		EDITOR_UI_LEFT_CONTENT_NAME,
		.None,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 434}),
	)
	world.ui_layouts[world.entities[scene].ui_layout_index].stack_order = 2
	editor_ui_add_section_panel(world, scene, "SCENE", true)
	editor_ui_add_vstack(
		world,
		scene,
		{
			fill = true,
			reorderable = true,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	scene_filter := editor_ui_create_browser_filter(
		world,
		EDITOR_UI_SCENE_FILTER_NAME,
		EDITOR_UI_SCENE_NAME,
		0,
	)
	scene_tools := editor_ui_create_box(
		world,
		EDITOR_UI_SCENE_TOOLS_NAME,
		EDITOR_UI_SCENE_NAME,
		.None,
		{
			size = {2000, 34},
			padding = {2, 6, 2, 6},
			background = theme.palette.panel,
			fixed_in_fill = true,
		},
	)
	editor_ui_add_hstack(world, scene_tools, {gap = 4})
	scene_list := editor_ui_create_box(
		world,
		EDITOR_UI_SCENE_LIST_NAME,
		EDITOR_UI_SCENE_NAME,
		.Browser_Scroll,
		{size = {2000, 332}, fill_width = true},
	)
	scene_list_value := theme_list(theme)
	scene_list_value.filter_input = world.entities[scene_filter].uuid
	scene_list_value.draggable = true
	scene_list_value.tree_enabled = true
	scene_list_value.virtualized = true
	scene_list_value.item_height = EDITOR_ENTITY_ROW_HEIGHT
	scene_list_value.overscan = 2
	editor_ui_add_list(world, scene_list, scene_list_value)
	editor_ui_add_scroll(world, scene_list)
	_ = ecs.set_ui_action(
		world,
		scene_list,
		{
			action = EDITOR_ACTION_DROP_SCENE_ROOT,
			drop_target = true,
			drag_threshold = 5,
			drop_background = {
				theme.palette.accent.x,
				theme.palette.accent.y,
				theme.palette.accent.z,
				0.18,
			},
		},
	)
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
		.None,
		editor_ui_list_section_layout({EDITOR_LEFT_SIDEBAR_WIDTH, 240}),
	)
	world.ui_layouts[world.entities[resource_browser].ui_layout_index].stack_order = 3
	editor_ui_add_section_panel(world, resource_browser, "RESOURCES / 0", true)
	editor_ui_add_vstack(
		world,
		resource_browser,
		{
			fill = true,
			reorderable = true,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	resource_filter := editor_ui_create_browser_filter(
		world,
		EDITOR_UI_RESOURCES_FILTER_NAME,
		EDITOR_UI_RESOURCES_NAME,
		1,
	)
	resource_tools := editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCE_TOOLS_NAME,
		EDITOR_UI_RESOURCES_NAME,
		.None,
		{
			size = {2000, 34},
			padding = {2, 6, 2, 6},
			background = theme.palette.panel,
			fixed_in_fill = true,
		},
	)
	editor_ui_add_hstack(world, resource_tools, {gap = 4})
	resource_list := editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCES_LIST_NAME,
		EDITOR_UI_RESOURCES_NAME,
		.Project_Resources_Scroll,
		{size = {2000, 140}, fill_width = true},
	)
	resource_list_value := theme_list(theme)
	resource_list_value.filter_input = world.entities[resource_filter].uuid
	resource_list_value.virtualized = true
	resource_list_value.item_height = EDITOR_ENTITY_ROW_HEIGHT
	resource_list_value.overscan = 2
	editor_ui_add_list(world, resource_list, resource_list_value)
	editor_ui_add_scroll(world, resource_list)
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

	viewport_dock := editor_ui_create_box(
		world,
		EDITOR_UI_VIEWPORT_DOCK_NAME,
		EDITOR_UI_WORKSPACE_NAME,
		.None,
		{size = {660, 638}},
	)
	editor_ui_add_dock_space(
		world,
		viewport_dock,
		theme,
		split_horizontal = true,
		split_vertical = true,
		content_sheet = false,
	)
	viewport_tab := editor_ui_create_box(
		world,
		EDITOR_UI_VIEWPORT_TAB_NAME,
		EDITOR_UI_VIEWPORT_DOCK_NAME,
		.None,
		{size = {660, 606}, min_size = {1, 120}, fill_width = true, fill_height = true},
	)
	editor_ui_add_dock_item(world, viewport_tab, "GAME", false)
	editor_ui_add_vstack(
		world,
		viewport_tab,
		{
			gap = EDITOR_SIDEBAR_SECTION_GAP,
			fill = true,
			draggable = true,
			min_size = 120,
			reorderable = true,
			drag_threshold = 5,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	viewport := editor_ui_create_box(
		world,
		EDITOR_UI_VIEWPORT_NAME,
		EDITOR_UI_VIEWPORT_TAB_NAME,
		.Viewport,
		{
			size = {660, 606},
			min_size = {1, 120},
			fill_width = true,
			fill_height = true,
			stack_order = 0,
		},
	)
	_ = ecs.set_ui_action(
		world,
		viewport,
		{
			action = EDITOR_ACTION_DROP_VIEWPORT,
			drop_target = true,
			drag_threshold = 5,
			drop_background = {
				theme.palette.accent.x,
				theme.palette.accent.y,
				theme.palette.accent.z,
				0.18,
			},
		},
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
			background = theme.palette.overlay,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = theme.metrics.radius,
			hidden = true,
		},
	)
	debug_view_menu := editor_ui_create_box(
		world,
		EDITOR_UI_DEBUG_VIEW_MENU_NAME,
		"",
		.Debug_View_Menu,
		{
			size = {220, 294},
			padding = {5, 5, 5, 5},
			background = theme.palette.overlay,
			corner_radius = theme.metrics.radius_large,
			popup = true,
			popup_close_on_selection = true,
			popup_gap = 4,
			popup_min_width = 220,
			popup_max_width = 260,
			popup_max_height = 310,
			popup_viewport_margin = 8,
		},
	)
	editor_ui_add_vstack(world, debug_view_menu, {fill = true})
	debug_view_menu_content := editor_ui_create_box(
		world,
		EDITOR_UI_DEBUG_VIEW_MENU_CONTENT_NAME,
		EDITOR_UI_DEBUG_VIEW_MENU_NAME,
		.Debug_View_Menu_Content,
		{size = {180, 1}, fill_width = true},
	)
	debug_view_list := theme_list(theme)
	debug_view_list.gap = 1
	editor_ui_add_list(world, debug_view_menu_content, debug_view_list)
	editor_ui_add_scroll(world, debug_view_menu_content)
	debug_view_names := [?]string {
		"CAMERA",
		"LIT",
		"BASE COLOR",
		"WORLD NORMALS",
		"ROUGHNESS",
		"METALLIC",
		"DEPTH",
		"MESHLETS",
		"LOD",
		"MESHLET VISIBILITY",
		"HI-Z",
		"OCCLUSION QUERIES",
		"VIRTUAL GEOMETRY",
		"DISTANCE FIELD",
		"WORLD DISTANCE FIELD",
	}
	for label, index in debug_view_names {
		slot := index - 1
		item := editor_ui_create_box(
			world,
			fmt.tprintf("__scrapbot_editor_debug_view_item_%d", index),
			EDITOR_UI_DEBUG_VIEW_MENU_CONTENT_NAME,
			.Debug_View_Item,
			{size = {1, 28}, padding = {4, 9, 4, 9}, corner_radius = 3, fill_width = true},
			slot,
		)
		item_button := shared.ui_button_default()
		item_button.text = label
		item_button.size = EDITOR_TEXT_SIZE
		item_button.alignment = .Left
		item_button.color = theme.palette.text
		item_button.hover_background = theme.palette.hover
		item_button.active_background = theme.palette.active
		_ = ecs.set_ui_button(world, item, item_button)
	}
	debug_view_toolbar := editor_ui_create_box(
		world,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		EDITOR_UI_VIEWPORT_NAME,
		.Debug_View_Toolbar,
		{position = {0, 10}, size = {1, 34}, padding = {2, 10, 2, 10}, fill_width = true},
	)
	editor_ui_add_hstack(world, debug_view_toolbar, {fill = true})
	world.ui_layouts[world.entities[debug_view_toolbar].ui_layout_index].horizontal_alignment = .End
	debug_view_button := editor_ui_create_box(
		world,
		EDITOR_UI_DEBUG_VIEW_BUTTON_NAME,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		.Debug_View_Button,
		{
			size = {210, 30},
			padding = {4, 10, 4, 10},
			background = theme.palette.overlay,
			corner_radius = theme.metrics.radius,
			fixed_in_fill = true,
		},
	)
	debug_button := shared.ui_button_default()
	debug_button.text = "VIEW / CAMERA"
	debug_button.size = EDITOR_TEXT_SIZE
	debug_button.alignment = .Left
	debug_button.color = theme.palette.text
	debug_button.hover_background = theme.palette.hover
	debug_button.active_background = theme.palette.active
	debug_button.popup = world.entities[debug_view_menu].uuid
	_ = ecs.set_ui_button(world, debug_view_button, debug_button)
	hiz_mip_decrease := editor_ui_create_transport_button(
		world,
		EDITOR_UI_DEBUG_HIZ_MIP_DECREASE_NAME,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		"",
		.Debug_HiZ_Mip_Decrease,
		"minus",
	)
	hiz_mip_label := editor_ui_create_box(
		world,
		EDITOR_UI_DEBUG_HIZ_MIP_LABEL_NAME,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		.Debug_HiZ_Mip_Label,
		{
			size = {58, 30},
			padding = {4, 8, 4, 8},
			background = theme.palette.overlay,
			corner_radius = theme.metrics.radius,
			fixed_in_fill = true,
			hidden = true,
		},
	)
	editor_ui_add_text(world, hiz_mip_label, "MIP 0", theme.palette.text, EDITOR_TEXT_SIZE)
	hiz_mip_increase := editor_ui_create_transport_button(
		world,
		EDITOR_UI_DEBUG_HIZ_MIP_INCREASE_NAME,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		"",
		.Debug_HiZ_Mip_Increase,
		"plus",
	)
	hiz_mip_buttons := [?]int{hiz_mip_decrease, hiz_mip_increase}
	for item in hiz_mip_buttons {
		layout := &world.ui_layouts[world.entities[item].ui_layout_index]
		layout.size.x = 30
		layout.fill_width = false
		layout.fixed_in_fill = true
		layout.hidden = true
	}
	occlusion_freeze := editor_ui_create_transport_button(
		world,
		EDITOR_UI_DEBUG_OCCLUSION_FREEZE_NAME,
		EDITOR_UI_DEBUG_VIEW_TOOLBAR_NAME,
		"FREEZE",
		.Debug_Occlusion_Freeze,
	)
	occlusion_freeze_layout := &world.ui_layouts[world.entities[occlusion_freeze].ui_layout_index]
	occlusion_freeze_layout.size.x = 68
	occlusion_freeze_layout.fill_width = false
	occlusion_freeze_layout.fixed_in_fill = true
	occlusion_freeze_layout.hidden = true
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
	placement_toolbar := editor_ui_create_box(
		world,
		EDITOR_UI_PLACEMENT_TOOLBAR_NAME,
		EDITOR_UI_VIEWPORT_NAME,
		.Placement_Toolbar,
		{
			position = {10, 52},
			size = {104, 34},
			padding = {2, 2, 2, 2},
			background = theme.palette.overlay,
			corner_radius = theme.metrics.radius,
		},
	)
	editor_ui_add_hstack(world, placement_toolbar, {gap = 2})
	placement_snap := editor_ui_create_transport_button(
		world,
		EDITOR_UI_PLACEMENT_SNAP_NAME,
		EDITOR_UI_PLACEMENT_TOOLBAR_NAME,
		"SNAP 0.5",
		.Placement_Snap,
	)
	world.ui_layouts[world.entities[placement_snap].ui_layout_index].size.x = 100

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
			background = theme.palette.region,
		},
	)
	editor_ui_add_dock_space(world, right, theme)
	editor_ui_add_scroll(world, right)
	right_dock_item := editor_ui_create_box(
		world,
		EDITOR_UI_RIGHT_DOCK_ITEM_NAME,
		EDITOR_UI_RIGHT_NAME,
		.None,
		{
			size = {
				EDITOR_RIGHT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
			fit_content_height = true,
			background = theme.palette.region,
		},
	)
	editor_ui_add_dock_item(world, right_dock_item, "INSPECT")
	right_content := editor_ui_create_box(
		world,
		EDITOR_UI_RIGHT_CONTENT_NAME,
		EDITOR_UI_RIGHT_DOCK_ITEM_NAME,
		.Inspector_Content,
		{
			size = {
				EDITOR_RIGHT_SIDEBAR_WIDTH - EDITOR_SIDEBAR_PADDING * 2,
				EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT,
			},
			min_size = {1, EDITOR_SIDEBAR_DOCK_ITEM_MIN_HEIGHT},
			fill_width = true,
			fill_height = true,
			fit_content_height = true,
		},
	)
	editor_ui_add_vstack(
		world,
		right_content,
		{
			gap = INSPECTOR_PANEL_GAP,
			reorderable = true,
			drag_threshold = 5,
			drop_indicator_color = theme.palette.accent,
			drop_indicator_thickness = 2,
			drop_indicator_inset = 8,
		},
	)
	right_header := editor_ui_create_box(
		world,
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		EDITOR_UI_RIGHT_CONTENT_NAME,
		.None,
		editor_ui_section_layout({EDITOR_RIGHT_SIDEBAR_WIDTH, 132}),
	)
	world.ui_layouts[world.entities[right_header].ui_layout_index].stack_order = 0
	editor_ui_add_section_panel(world, right_header, "INSPECTOR")
	identity_input_layout, name_value := theme_input(theme)
	identity_input_layout.position = {10, 42}
	identity_input_layout.size = {2000, 28}
	identity_input_layout.fill_width = true
	name_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_entity_name",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Entity_Name,
		identity_input_layout,
	)
	name_value.text = ""
	editor_ui_add_input(world, name_input, name_value)
	resource_name_layout := identity_input_layout
	resource_name_layout.hidden = true
	resource_name_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_resource_name",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Resource_Name,
		resource_name_layout,
	)
	resource_name_value := name_value
	editor_ui_add_input(world, resource_name_input, resource_name_value)
	_ = ecs.set_ui_input_prefix(world, resource_name_input, "NAME")
	world.ui_inputs[world.entities[resource_name_input].ui_input_index].prefix_width = 52
	resource_source_layout := identity_input_layout
	resource_source_layout.position = {10, 78}
	resource_source_layout.hidden = true
	resource_source_input := editor_ui_create_box(
		world,
		"__scrapbot_editor_inspector_resource_source",
		EDITOR_UI_INSPECTOR_HEADER_NAME,
		.Inspector_Resource_Source,
		resource_source_layout,
	)
	resource_source_value := name_value
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

	status_layout := theme_chrome_bar(theme)
	status_layout.size = {1280, EDITOR_STATUS_BAR_HEIGHT}
	status_layout.fixed_in_fill = true
	status_layout.padding = {6, 14, 6, 14}
	status := editor_ui_create_box(
		world,
		EDITOR_UI_STATUS_NAME,
		EDITOR_UI_ROOT_NAME,
		.None,
		status_layout,
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
	theme := reduced_dark_theme()
	row_name := fmt.tprintf("__scrapbot_editor_row_%d", slot)
	disclosure_name := fmt.tprintf("__scrapbot_editor_row_disclosure_%d", slot)
	label_name := fmt.tprintf("__scrapbot_editor_row_label_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_SCENE_LIST_NAME,
		.Browser_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}},
		slot,
	)
	_ = ecs.set_ui_action(
		world,
		row,
		{
			action = EDITOR_ACTION_DROP_SCENE_PARENT,
			drop_target = true,
			drag_threshold = 5,
			drop_background = {
				theme.palette.accent.x,
				theme.palette.accent.y,
				theme.palette.accent.z,
				0.18,
			},
		},
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
	disclosure_button.icon_set = shared.builtin_icon_set_uuid()
	disclosure_button.icon = "caret-down"
	disclosure_button.icon_inset = 6
	disclosure_button.color = theme.palette.text_secondary
	disclosure_button.hover_background = theme.palette.hover
	disclosure_button.active_background = theme.palette.active
	_ = ecs.set_ui_button(world, disclosure, disclosure_button)
	label = editor_ui_create_box(
		world,
		label_name,
		row_name,
		.Browser_Row_Label,
		{position = {26, 0}, size = {1874, EDITOR_ENTITY_ROW_HEIGHT}, padding = {8, 0, 6, 0}},
		slot,
	)
	editor_ui_add_text(world, label, "", theme.palette.text, EDITOR_TEXT_SIZE)
	return row, disclosure, label
}

editor_ui_ensure_resource_row :: proc(world: ^shared.World, slot: int) -> (int, int) {
	row, row_found := editor_ui_entity(world, .Project_Resource_Row, slot)
	label, label_found := editor_ui_entity(world, .Project_Resource_Row_Label, slot)
	if row_found && label_found {
		return row, label
	}
	theme := reduced_dark_theme()
	row_name := fmt.tprintf("__scrapbot_editor_resource_row_%d", slot)
	label_name := fmt.tprintf("__scrapbot_editor_resource_row_label_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_RESOURCES_LIST_NAME,
		.Project_Resource_Row,
		{size = {2000, EDITOR_ENTITY_ROW_HEIGHT}},
		slot,
	)
	_ = ecs.set_ui_action(world, row, {action = EDITOR_ACTION_RESOURCE_MODEL, drag_threshold = 5})
	label = editor_ui_create_box(
		world,
		label_name,
		row_name,
		.Project_Resource_Row_Label,
		{
			position = {EDITOR_BROWSER_TEXT_INSET, 0},
			size = {1900, EDITOR_ENTITY_ROW_HEIGHT},
			padding = {8, 0, 6, 0},
		},
		slot,
	)
	editor_ui_add_text(world, label, "", theme.palette.text, EDITOR_TEXT_SIZE)
	return row, label
}

editor_ui_set_resource_drag_source :: proc(world: ^shared.World, row: int, draggable: bool) {
	if world == nil || !ecs.entity_is_alive(world, row) {
		return
	}
	entity := world.entities[row]
	if entity.ui_action_index < 0 || entity.ui_action_index >= len(world.ui_actions) {
		return
	}
	value := world.ui_actions[entity.ui_action_index]
	value.drag_source = draggable
	_ = ecs.set_ui_action(world, row, value)
}

SYSTEM_PROFILE_CELL_HEIGHT :: f32(26)
SYSTEM_PROFILE_BAR_MAX_NANOSECONDS :: f64(10_000_000)

system_profile_origin_color :: proc(kind: shared.System_Profile_Kind) -> shared.Vec4 {
	theme := reduced_dark_theme()
	switch kind {
		case .Engine:
			return theme.palette.data_engine
		case .Project_Odin:
			return theme.palette.data_native
		case .Luau:
			return theme.palette.data_script
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
	theme := reduced_dark_theme()
	row_name := fmt.tprintf("__scrapbot_editor_system_row_%d", slot)
	name := fmt.tprintf("__scrapbot_editor_system_name_%d", slot)
	timing := fmt.tprintf("__scrapbot_editor_system_time_%d", slot)
	row = editor_ui_create_box(
		world,
		row_name,
		EDITOR_UI_SYSTEMS_LIST_NAME,
		.Systems_Row,
		{size = {100, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {0, 4, 0, 4}},
		slot,
	)
	editor_ui_add_hstack(world, row, {gap = 4, fill = true})
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
		{
			size = {100, SYSTEM_PROFILE_CELL_HEIGHT},
			padding = {5, 3, 3, EDITOR_BROWSER_TEXT_INSET - 4},
		},
		slot,
	)
	editor_ui_add_text(world, name_cell, "", theme.palette.text, EDITOR_TEXT_SIZE)
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
		{size = {55, SYSTEM_PROFILE_CELL_HEIGHT}, padding = {5, 1, 3, 1}, fixed_in_fill = true},
		slot,
	)
	editor_ui_add_text(world, time_cell, "--", theme.palette.text_muted, EDITOR_TEXT_SIZE)
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
	hiz_status := shared.hiz_occlusion_status_name(diagnostics.hiz_occlusion_status)
	if diagnostics.hiz_occlusion_status == .Below_Threshold {
		hiz_status = fmt.tprintf("BELOW %d", diagnostics.hiz_instance_threshold)
	}
	shadow_resolution := "--"
	if diagnostics.shadow_resolution > 0 {
		shadow_resolution = fmt.tprintf("%d²", diagnostics.shadow_resolution)
	}
	values := [15]string {
		fmt.tprintf("%.1f", diagnostics.fps),
		fmt.tprintf("%.2f ms", diagnostics.frame_ms),
		"--",
		"--",
		fmt.tprintf("%.0f%%", diagnostics.render_scale * 100),
		shadow_resolution,
		fmt.tprintf("%.0f%%", diagnostics.adaptive_post_quality * 100),
		fmt.tprintf("%d", diagnostics.entity_count),
		fmt.tprintf("%d", diagnostics.retained_batches),
		fmt.tprintf("%d", diagnostics.visible_batches),
		fmt.tprintf("%d", diagnostics.visible_meshlet_draws),
		hiz_status,
		fmt.tprintf("%d", diagnostics.frustum_culled_instances),
		fmt.tprintf("%d", diagnostics.occlusion_culled_instances),
		fmt.tprintf("%d", diagnostics.occlusion_culled_meshlets),
	}
	if diagnostics.gpu_timestamps_valid {
		values[2] = fmt.tprintf("%.2f ms", diagnostics.gpu_frame_ms)
		values[3] = fmt.tprintf("%.2f ms", diagnostics.gpu_scene_ms)
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
	theme := reduced_dark_theme()
	chrome := theme_chrome_bar(theme)
	if top, found := ecs.entity_index_by_uuid(
		world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_TOP_NAME),
	); found {
		layout := &world.ui_layouts[world.entities[top].ui_layout_index]
		layout.background = chrome.background
		layout.border_color = chrome.border_color
		layout.border_width = chrome.border_width
		layout.corner_radius = chrome.corner_radius
	}
	if viewport, found := editor_ui_entity(world, .Viewport); found {
		layout := &world.ui_layouts[world.entities[viewport].ui_layout_index]
		layout.border_color = {}
		layout.border_width = 0
		if playback {
			frame := theme_warning_frame(theme)
			layout.border_color = frame.border_color
			layout.border_width = frame.border_width
		}
	}
	if status_bar, found := ecs.entity_index_by_uuid(
		world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_STATUS_NAME),
	); found {
		layout := &world.ui_layouts[world.entities[status_bar].ui_layout_index]
		layout.background = chrome.background
		layout.border_color = chrome.border_color
		layout.border_width = chrome.border_width
		layout.corner_radius = chrome.corner_radius
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
		base_layout, base_button := theme_button(theme, .Quiet)
		layout.background = base_layout.background
		layout.border_color = base_layout.border_color
		layout.border_width = base_layout.border_width
		button.color = base_button.color
		button.hover_background = base_button.hover_background
		button.active_background = base_button.active_background
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
			button.color = theme.palette.text_muted
			button.hover_background = layout.background
			button.active_background = layout.background
			continue
		}
		if component.role == .Transport_Save && state.editor_scene_dirty {
			warning_layout, warning_button := theme_button(theme, .Warning)
			layout.background = warning_layout.background
			layout.border_color = warning_layout.border_color
			layout.border_width = warning_layout.border_width
			button.color = warning_button.color
			button.hover_background = warning_button.hover_background
			button.active_background = warning_button.active_background
			continue
		}
		if component.role == .Transport_Revert && state.editor_scene_dirty {
			destructive_layout, destructive_button := theme_button(theme, .Destructive)
			layout.background = destructive_layout.background
			layout.border_color = destructive_layout.border_color
			layout.border_width = destructive_layout.border_width
			button.color = destructive_button.color
			button.hover_background = destructive_button.hover_background
			button.active_background = destructive_button.active_background
			continue
		}
		if selected && component.role == .Transport_Play {
			primary_layout, primary_button := theme_button(theme, .Primary)
			layout.background = primary_layout.background
			layout.border_color = primary_layout.border_color
			layout.border_width = primary_layout.border_width
			button.color = primary_button.color
			button.hover_background = primary_button.hover_background
			button.active_background = primary_button.active_background
		} else if selected {
			selected_layout, selected_button := theme_button(theme, .Selected)
			layout.background = selected_layout.background
			layout.border_color = selected_layout.border_color
			layout.border_width = selected_layout.border_width
			button.color = selected_button.color
			button.hover_background = selected_button.hover_background
			button.active_background = selected_button.active_background
		}
	}
	if status, found := editor_ui_entity(world, .Status); found {
		entity := world.entities[status]
		if entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts) {
			world.ui_texts[entity.ui_text_index].color = theme.palette.accent
			if playback {
				world.ui_texts[entity.ui_text_index].color = theme.palette.warning
			}
		}
	}
	if root, found := editor_ui_entity(world, .Root); found {
		ecs.mark_ui_paint_changed(world, root)
	}
}

editor_ui_update_gizmo_toolbar :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil { return }
	theme := reduced_dark_theme()
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
		base_layout, base_button := theme_button(theme, .Quiet)
		layout.background = base_layout.background
		layout.border_color = base_layout.border_color
		layout.border_width = base_layout.border_width
		button.color = base_button.color
		if selected {
			selected_layout, selected_button := theme_button(theme, .Primary)
			layout.background = selected_layout.background
			layout.border_color = selected_layout.border_color
			layout.border_width = selected_layout.border_width
			button.color = selected_button.color
		}
	}
	if root, found := editor_ui_entity(world, .Root); found {
		ecs.mark_ui_paint_changed(world, root)
	}
}

editor_ui_update_placement_snap_button :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil {
		return
	}
	entity_index, found := editor_ui_entity(world, .Placement_Snap)
	if !found {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_button_index < 0 || entity.ui_button_index >= len(world.ui_buttons) {
		return
	}
	button := world.ui_buttons[entity.ui_button_index]
	switch state.editor_placement_snap_step {
		case 0:
			button.text = "SNAP OFF"
		case 0.25:
			button.text = "SNAP 0.25"
		case 0.5:
			button.text = "SNAP 0.5"
		case:
			button.text = "SNAP 1"
	}
	_ = ecs.set_ui_button(world, entity_index, button)
}

editor_ui_update_debug_view_button :: proc(state: ^State, world: ^shared.World) {
	if state == nil || world == nil {
		return
	}
	button_index, found := editor_ui_entity(world, .Debug_View_Button)
	if !found {
		return
	}
	entity := world.entities[button_index]
	if entity.ui_button_index < 0 || entity.ui_button_index >= len(world.ui_buttons) {
		return
	}
	label := "CAMERA"
	if state.editor_render_debug_view_override {
		switch state.editor_render_debug_view {
			case .Lit:
				label = "LIT"
			case .Base_Color:
				label = "BASE COLOR"
			case .World_Normals:
				label = "WORLD NORMALS"
			case .Roughness:
				label = "ROUGHNESS"
			case .Metallic:
				label = "METALLIC"
			case .Depth:
				label = "DEPTH"
			case .Meshlets:
				label = "MESHLETS"
			case .LOD:
				label = "LOD"
			case .Meshlet_Visibility:
				label = "MESHLET VISIBILITY"
			case .HiZ:
				label = "HI-Z"
			case .Occlusion_Queries:
				label = "OCCLUSION QUERIES"
			case .Virtual_Geometry:
				label = "VIRTUAL GEOMETRY"
			case .Distance_Field:
				label = "DISTANCE FIELD"
			case .World_Distance_Field:
				label = "WORLD DISTANCE FIELD"
		}
	}
	value := world.ui_buttons[entity.ui_button_index]
	next_text := fmt.tprintf("VIEW / %s", label)
	if value.text != next_text {
		value.text = next_text
		_ = ecs.set_ui_button(world, button_index, value)
	}
	show_hiz_mip :=
		state.editor_render_debug_view_override && state.editor_render_debug_view == .HiZ
	hiz_mip_roles := [?]shared.Editor_UI_Role {
		.Debug_HiZ_Mip_Decrease,
		.Debug_HiZ_Mip_Label,
		.Debug_HiZ_Mip_Increase,
	}
	for role in hiz_mip_roles {
		if index, ok := editor_ui_entity(world, role); ok {
			layout := world.ui_layouts[world.entities[index].ui_layout_index]
			if layout.hidden == show_hiz_mip {
				layout.hidden = !show_hiz_mip
				_ = ecs.set_ui_layout(world, index, layout)
			}
		}
	}
	if mip_label, ok := editor_ui_entity(world, .Debug_HiZ_Mip_Label); ok {
		mip_entity := world.entities[mip_label]
		if mip_entity.ui_text_index >= 0 && mip_entity.ui_text_index < len(world.ui_texts) {
			text := world.ui_texts[mip_entity.ui_text_index]
			next_mip_text := fmt.tprintf("MIP %d", state.editor_render_debug_hiz_mip)
			if text.text != next_mip_text {
				text.text = next_mip_text
				_ = ecs.set_ui_text(world, mip_label, text)
			}
		}
	}
	show_occlusion_freeze :=
		state.editor_render_debug_view_override &&
		state.editor_render_debug_view == .Occlusion_Queries
	if freeze_button, ok := editor_ui_entity(world, .Debug_Occlusion_Freeze); ok {
		layout := world.ui_layouts[world.entities[freeze_button].ui_layout_index]
		if layout.hidden == show_occlusion_freeze {
			layout.hidden = !show_occlusion_freeze
		}
		layout.background =
			reduced_dark_theme().palette.active if state.editor_render_debug_occlusion_frozen else {}
		_ = ecs.set_ui_layout(world, freeze_button, layout)
		button := world.ui_buttons[world.entities[freeze_button].ui_button_index]
		next_freeze_text := "FROZEN" if state.editor_render_debug_occlusion_frozen else "FREEZE"
		if button.text != next_freeze_text {
			button.text = next_freeze_text
			_ = ecs.set_ui_button(world, freeze_button, button)
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
	if systems, found := ecs.entity_index_by_uuid(
		world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_SYSTEMS_NAME),
	); found {
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
INSPECTOR_PANEL_GAP :: f32(4)
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
	panel_layout.stack_order = 1000 + slot
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
	theme := reduced_dark_theme()
	layout, button := theme_button(theme, .Quiet)
	layout.size = {22, 22}
	layout.margin = {5, 5, 5, 5}
	layout.fixed_in_fill = true
	action := editor_ui_create_box(world, name, parent, .Inspector_Panel_Action, layout, slot)
	button.icon_set = shared.builtin_icon_set_uuid()
	button.icon = "x"
	button.panel_action = true
	button.color = theme.palette.text_secondary
	_, destructive_button := theme_button(theme, .Destructive)
	button.hover_background = theme.palette.danger_soft
	button.active_background = destructive_button.active_background
	button.icon_inset = 6
	_ = ecs.set_ui_button(world, action, button)
	return action
}

editor_ui_ensure_inspector_cell :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
	value_cell: bool,
) -> int {
	theme := reduced_dark_theme()
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
				editor_ui_add_text(world, cell, "", theme.palette.text_muted, EDITOR_TEXT_SIZE)
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
		editor_ui_add_text(world, cell, "", theme.palette.text_muted, EDITOR_TEXT_SIZE)
	}
	return cell
}

editor_ui_ensure_inspector_input :: proc(world: ^shared.World, slot: int, parent: string) -> int {
	if input, found := editor_ui_entity(world, .Inspector_Input, slot); found {
		editor_ui_set_parent(world, input, parent)
		return input
	}
	name := fmt.tprintf("__scrapbot_editor_inspector_input_%d", slot)
	theme := reduced_dark_theme()
	layout, value := theme_input(theme)
	layout.size = {1, INSPECTOR_CONTROL_HEIGHT}
	layout.padding = {5, 5, 4, 5}
	input := editor_ui_create_box(world, name, parent, .Inspector_Input, layout, slot)
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
	theme := reduced_dark_theme()
	checkbox := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Checkbox,
		{size = {1, INSPECTOR_CONTROL_HEIGHT}},
		slot,
	)
	value := theme_checkbox(theme)
	editor_ui_add_checkbox(world, checkbox, value)
	return checkbox
}

editor_ui_ensure_inspector_color :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
) -> (
	button, picker: int,
) {
	if existing_button, button_found := editor_ui_entity(world, .Inspector_Color_Button, slot);
	   button_found {
		existing_picker, picker_found := editor_ui_entity(world, .Inspector_Color_Picker, slot)
		if picker_found {
			editor_ui_set_parent(world, existing_button, parent)
			return existing_button, existing_picker
		}
	}
	picker_name := fmt.tprintf("__scrapbot_editor_inspector_color_picker_%d", slot)
	theme := reduced_dark_theme()
	picker = editor_ui_create_box(
		world,
		picker_name,
		"",
		.Inspector_Color_Picker,
		{
			size = {280, 232},
			background = theme.palette.panel,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = 6,
			popup = true,
			popup_close_on_selection = false,
			popup_gap = 6,
			popup_viewport_margin = 8,
		},
		slot,
	)
	editor_ui_add_color_picker(world, picker, theme_color_picker(theme))
	button_name := fmt.tprintf("__scrapbot_editor_inspector_color_button_%d", slot)
	button = editor_ui_create_box(
		world,
		button_name,
		parent,
		.Inspector_Color_Button,
		{
			size = {1, INSPECTOR_CONTROL_HEIGHT},
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = 4,
		},
		slot,
	)
	value := shared.ui_button_default()
	value.text = " "
	value.size = 1
	value.popup = world.entities[picker].uuid
	value.hover_background = theme.palette.light_overlay
	value.active_background = theme.palette.dark_overlay
	_ = ecs.set_ui_button(world, button, value)
	return
}

editor_ui_ensure_choice_menu_button :: proc(
	world: ^shared.World,
	role: shared.Editor_UI_Role,
	slot: int,
	name, parent, label: string,
	popup: shared.Entity_UUID,
	read_only: bool,
) -> int {
	button, found := editor_ui_entity(world, role, slot)
	if !found {
		theme := reduced_dark_theme()
		layout, themed_button := theme_button(theme)
		layout.size = {1, INSPECTOR_CONTROL_HEIGHT}
		layout.padding = {5, 8, 4, 8}
		button = editor_ui_create_box(world, name, parent, role, layout, slot)
		_ = ecs.set_ui_button(world, button, themed_button)
	} else {
		editor_ui_set_parent(world, button, parent)
	}
	value := world.ui_buttons[world.entities[button].ui_button_index]
	value.text = label
	value.popup = popup
	value.size = EDITOR_TEXT_SIZE
	value.alignment = .Left
	theme := reduced_dark_theme()
	value.color = theme.palette.text
	if read_only {
		value.hover_background = {}
		value.active_background = {}
		value.hover_color = value.color
		value.active_color = value.color
	} else {
		value.hover_background = theme.palette.hover
		value.active_background = theme.palette.active
		value.hover_color = theme.palette.accent_text
		value.active_color = theme.palette.accent_text
	}
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_ensure_inspector_enum_button :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	popup: shared.Entity_UUID,
	read_only: bool,
) -> int {
	return editor_ui_ensure_choice_menu_button(
		world,
		.Inspector_Enum_Menu_Button,
		slot,
		fmt.tprintf("__scrapbot_editor_inspector_enum_%d", slot),
		parent,
		label,
		popup,
		read_only,
	)
}

editor_ui_ensure_enum_menu :: proc(world: ^shared.World) -> (int, int) {
	menu, menu_found := editor_ui_entity(world, .Inspector_Enum_Menu)
	content, content_found := editor_ui_entity(world, .Inspector_Enum_Menu_Content)
	if menu_found && content_found {
		return menu, content
	}
	theme := reduced_dark_theme()
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_ENUM_MENU_NAME,
		"",
		.Inspector_Enum_Menu,
		{
			size = {220, 120},
			padding = {5, 5, 5, 5},
			background = theme.palette.overlay,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = theme.metrics.radius_large,
			popup = true,
			popup_close_on_selection = true,
			popup_gap = 4,
			popup_min_width = 220,
			popup_max_width = 420,
			popup_max_height = 260,
			popup_viewport_margin = 4,
		},
	)
	editor_ui_add_vstack(world, menu, {fill = true})
	content = editor_ui_create_box(
		world,
		EDITOR_UI_ENUM_MENU_CONTENT_NAME,
		EDITOR_UI_ENUM_MENU_NAME,
		.Inspector_Enum_Menu_Content,
		{size = {210, 1}, fill_width = true},
	)
	list := theme_list(theme)
	list.gap = 1
	editor_ui_add_list(world, content, list)
	editor_ui_add_scroll(world, content)
	return menu, content
}

editor_ui_ensure_choice_menu_item :: proc(
	world: ^shared.World,
	role: shared.Editor_UI_Role,
	slot: int,
	name, parent, label: string,
) -> int {
	theme := reduced_dark_theme()
	item, found := editor_ui_entity(world, role, slot)
	if !found {
		item = editor_ui_create_box(
			world,
			name,
			parent,
			role,
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
	value.color = theme.palette.text
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
	_ = ecs.set_ui_button(world, item, value)
	return item
}

editor_ui_ensure_enum_menu_item :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	binding: shared.Editor_UI_Component,
) -> int {
	item := editor_ui_ensure_choice_menu_item(
		world,
		.Inspector_Enum_Menu_Item,
		slot,
		fmt.tprintf("__scrapbot_editor_enum_menu_item_%d", slot),
		parent,
		label,
	)
	role := &world.editor_uis[world.entities[item].editor_ui_index]
	role.target = binding.target
	role.reflected_component_id = binding.reflected_component_id
	role.reflected_field_index = binding.reflected_field_index
	role.reflected_path = binding.reflected_path
	role.reflected_path_count = binding.reflected_path_count
	return item
}

editor_ui_build_enum_menu :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) {
	menu, content := editor_ui_ensure_enum_menu(world)
	for component in world.editor_uis {
		if component.role == .Inspector_Enum_Menu_Item {
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
	if state == nil {
		return
	}
	menu_layout := &world.ui_layouts[world.entities[menu].ui_layout_index]
	if !menu_layout.popup_open {
		return
	}
	menu_binding := &world.editor_uis[world.entities[menu].editor_ui_index]
	menu_binding.target = binding.target
	menu_binding.reflected_component_id = binding.reflected_component_id
	menu_binding.reflected_field_index = binding.reflected_field_index
	menu_binding.reflected_path = binding.reflected_path
	menu_binding.reflected_path_count = binding.reflected_path_count
	definition, definition_found := editor_reflected_definition(state, binding)
	_, target_index, target_found := inspector_target(world, binding)
	if !definition_found || !target_found {
		return
	}
	snapshot, captured := ecs.capture_registered_component_snapshot(
		world,
		target_index,
		definition,
	)
	if !captured {
		return
	}
	defer ecs.destroy_registered_component_snapshot(&snapshot)
	component_value, component_found := editor_reflected_snapshot_component_value(
		&snapshot.value,
		definition,
	)
	if !component_found {
		return
	}
	field_value, field_found := editor_reflected_binding_value(
		component_value,
		definition,
		binding,
	)
	if !field_found || !editor_reflected_value_is_enum(field_value) {
		return
	}
	current, _ := reflect.enum_name_from_value_any(field_value)
	parent := world.entities[content].name
	selected: shared.Entity_UUID
	names := reflect.enum_field_names(field_value.id)
	for name, slot in names {
		item := editor_ui_ensure_enum_menu_item(world, slot, parent, name, binding)
		editor_ui_set_hidden(world, item, false)
		if name == current {
			selected = world.entities[item].uuid
		}
	}
	content_layout := &world.ui_layouts[world.entities[content].ui_layout_index]
	content_layout.size.y = max(f32(len(names) * 31), 1)
	menu_layout.size.y = content_layout.size.y + 10
	list := world.ui_lists[world.entities[content].ui_list_index]
	list.selected = selected
	_ = ecs.set_ui_list(world, content, list)
}

editor_ui_ensure_entity_menu_button :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	popup: shared.Entity_UUID,
	read_only: bool,
) -> int {
	return editor_ui_ensure_choice_menu_button(
		world,
		.Inspector_Entity_Menu_Button,
		slot,
		fmt.tprintf("__scrapbot_editor_inspector_entity_%d", slot),
		parent,
		label,
		popup,
		read_only,
	)
}

editor_ui_ensure_entity_menu :: proc(world: ^shared.World) -> (menu, filter, content: int) {
	menu_found, filter_found, content_found: bool
	menu, menu_found = editor_ui_entity(world, .Inspector_Entity_Menu)
	filter, filter_found = editor_ui_entity(world, .Inspector_Entity_Menu_Filter)
	content, content_found = editor_ui_entity(world, .Inspector_Entity_Menu_Content)
	if menu_found && filter_found && content_found {
		return
	}
	theme := reduced_dark_theme()
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_ENTITY_MENU_NAME,
		"",
		.Inspector_Entity_Menu,
		{
			size = {340, 320},
			padding = {5, 5, 5, 5},
			background = theme.palette.overlay,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = theme.metrics.radius_large,
			popup = true,
			popup_close_on_selection = true,
			popup_gap = 4,
			popup_min_width = 260,
			popup_max_width = 460,
			popup_max_height = 360,
			popup_viewport_margin = 4,
		},
	)
	editor_ui_add_vstack(world, menu, {gap = 5, fill = true})
	filter = editor_ui_create_browser_filter(
		world,
		EDITOR_UI_ENTITY_MENU_FILTER_NAME,
		EDITOR_UI_ENTITY_MENU_NAME,
		0,
		.Inspector_Entity_Menu_Filter,
	)
	filter_layout := &world.ui_layouts[world.entities[filter].ui_layout_index]
	filter_layout.fill_width = true
	filter_layout.fixed_in_fill = true
	filter_value := world.ui_inputs[world.entities[filter].ui_input_index]
	filter_value.prefix = "Find"
	_ = ecs.set_ui_input(world, filter, filter_value)
	content = editor_ui_create_box(
		world,
		EDITOR_UI_ENTITY_MENU_CONTENT_NAME,
		EDITOR_UI_ENTITY_MENU_NAME,
		.Inspector_Entity_Menu_Content,
		{size = {330, 271}, fill_width = true, fill_height = true},
	)
	list := theme_list(theme)
	list.filter_input = world.entities[filter].uuid
	list.gap = 1
	list.virtualized = true
	list.item_height = 30
	list.overscan = 3
	editor_ui_add_list(world, content, list)
	editor_ui_add_scroll(world, content)
	return
}

editor_ui_ensure_entity_menu_item :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	entity_reference: shared.Entity_UUID,
	binding: shared.Editor_UI_Component,
) -> int {
	item := editor_ui_ensure_choice_menu_item(
		world,
		.Inspector_Entity_Menu_Item,
		slot,
		fmt.tprintf("__scrapbot_editor_entity_menu_item_%d", slot),
		parent,
		label,
	)
	role := &world.editor_uis[world.entities[item].editor_ui_index]
	role.target = binding.target
	role.reflected_component_id = binding.reflected_component_id
	role.reflected_field_index = binding.reflected_field_index
	role.reflected_path = binding.reflected_path
	role.reflected_path_count = binding.reflected_path_count
	role.entity_reference = entity_reference
	role.read_only = false
	return item
}

editor_entity_menu_label :: proc(world: ^shared.World, reference: shared.Entity_UUID) -> string {
	if reference == (shared.Entity_UUID{}) {
		return "None"
	}
	if index, found := ecs.entity_index_by_uuid(world, reference); found {
		return world.entities[index].name
	}
	buffer: [36]u8
	return fmt.tprintf("Missing [%s]", shared.entity_uuid_to_string(reference, buffer[:]))
}

editor_entity_menu_candidate_label :: proc(entity: shared.World_Entity) -> string {
	buffer: [36]u8
	uuid := shared.entity_uuid_to_string(entity.uuid, buffer[:])
	return fmt.tprintf("%s  [%s]", entity.name, uuid[:8])
}

editor_ui_build_entity_menu :: proc(
	state: ^State,
	world: ^shared.World,
	binding: shared.Editor_UI_Component,
) {
	menu, filter, content := editor_ui_ensure_entity_menu(world)
	for component in world.editor_uis {
		if component.role == .Inspector_Entity_Menu_Item {
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
	if state == nil {
		return
	}
	menu_layout := &world.ui_layouts[world.entities[menu].ui_layout_index]
	if !menu_layout.popup_open {
		return
	}
	menu_binding := &world.editor_uis[world.entities[menu].editor_ui_index]
	menu_binding.target = binding.target
	menu_binding.reflected_component_id = binding.reflected_component_id
	menu_binding.reflected_field_index = binding.reflected_field_index
	menu_binding.reflected_path = binding.reflected_path
	menu_binding.reflected_path_count = binding.reflected_path_count
	filter_value := world.ui_inputs[world.entities[filter].ui_input_index]
	filter_value.text = ""
	_ = ecs.set_ui_input(world, filter, filter_value)
	parent := world.entities[content].name
	current, current_found := editor_reflected_entity_reference(state, world, binding)
	selected: shared.Entity_UUID
	slot := 0
	none_item := editor_ui_ensure_entity_menu_item(world, slot, parent, "None", {}, binding)
	editor_ui_set_hidden(world, none_item, false)
	if current_found && current == (shared.Entity_UUID{}) {
		selected = world.entities[none_item].uuid
	}
	slot += 1
	indices: [dynamic]int
	defer delete(indices)
	for entity, entity_index in world.entities {
		if !entity.alive || entity.origin != .Scene {
			continue
		}
		if !editor_reflected_entity_reference_candidate_valid(state, world, binding, entity.uuid) {
			continue
		}
		append(&indices, entity_index)
	}
	for index in 1 ..< len(indices) {
		value := indices[index]
		cursor := index
		for cursor > 0 {
			left := world.entities[indices[cursor - 1]]
			right := world.entities[value]
			if left.name < right.name ||
			   (left.name == right.name && left.scene_order <= right.scene_order) {
				break
			}
			indices[cursor] = indices[cursor - 1]
			cursor -= 1
		}
		indices[cursor] = value
	}
	for entity_index in indices {
		entity := world.entities[entity_index]
		item := editor_ui_ensure_entity_menu_item(
			world,
			slot,
			parent,
			editor_entity_menu_candidate_label(entity),
			entity.uuid,
			binding,
		)
		editor_ui_set_hidden(world, item, false)
		if current_found && current == entity.uuid {
			selected = world.entities[item].uuid
		}
		slot += 1
	}
	if current_found && current != (shared.Entity_UUID{}) && selected == (shared.Entity_UUID{}) {
		item := editor_ui_ensure_entity_menu_item(
			world,
			slot,
			parent,
			editor_entity_menu_label(world, current),
			current,
			binding,
		)
		editor_ui_set_hidden(world, item, false)
		selected = world.entities[item].uuid
		slot += 1
	}
	content_layout := &world.ui_layouts[world.entities[content].ui_layout_index]
	content_layout.size.y = max(f32(slot * 31), 1)
	list := world.ui_lists[world.entities[content].ui_list_index]
	list.selected = selected
	_ = ecs.set_ui_list(world, content, list)
	for component in world.editor_uis {
		if component.role == .Inspector_Entity_Menu_Item && component.slot >= slot {
			editor_ui_set_hidden(world, component.entity_index, true)
		}
	}
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
	color_count: int,
	enum_button_count: int,
	entity_button_count: int,
	container_disclosure_count: int,
	row_count: int,
	component_menu_visible: bool,
	resource_menu_visible: bool,
}

editor_ui_ensure_resource_menu_button :: proc(
	world: ^shared.World,
	parent, label: string,
	enabled: bool,
) -> int {
	theme := reduced_dark_theme()
	button, found := editor_ui_entity(world, .Inspector_Resource_Menu_Button)
	if !found {
		layout, _ := theme_button(theme)
		layout.size = {1, INSPECTOR_CONTROL_HEIGHT}
		layout.padding = {5, 8, 4, 8}
		layout.fill_width = true
		button = editor_ui_create_box(
			world,
			"__scrapbot_editor_resource_menu_button",
			parent,
			.Inspector_Resource_Menu_Button,
			layout,
		)
		editor_ui_add_button(world, button)
	} else {
		editor_ui_set_parent(world, button, parent)
	}
	value := world.ui_buttons[world.entities[button].ui_button_index]
	value.text = label
	menu, _ := editor_ui_ensure_resource_menu(world)
	value.popup = {}
	if enabled {
		value.popup = world.entities[menu].uuid
	} else {
		_ = set_popup_open(world, menu, false)
	}
	value.size = EDITOR_TEXT_SIZE
	value.alignment = .Left
	value.color = theme.palette.text
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_ensure_resource_menu :: proc(world: ^shared.World) -> (int, int) {
	menu, menu_found := editor_ui_entity(world, .Inspector_Resource_Menu)
	content, content_found := editor_ui_entity(world, .Inspector_Resource_Menu_Content)
	if menu_found && content_found {
		return menu, content
	}
	theme := reduced_dark_theme()
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_RESOURCE_MENU_NAME,
		"",
		.Inspector_Resource_Menu,
		{
			size = {320, 240},
			padding = {5, 5, 5, 5},
			background = theme.palette.overlay,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = theme.metrics.radius_large,
			popup = true,
			popup_close_on_selection = true,
			popup_gap = 4,
			popup_min_width = 220,
			popup_max_width = 420,
			popup_max_height = 300,
			popup_viewport_margin = 4,
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
	list := theme_list(theme)
	list.gap = 1
	editor_ui_add_list(world, content, list)
	return menu, content
}

editor_ui_ensure_resource_menu_item :: proc(
	world: ^shared.World,
	slot: int,
	parent, label: string,
	resource_id: shared.Resource_UUID,
) -> int {
	theme := reduced_dark_theme()
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
	value.color = theme.palette.text
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
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
		builder.state.editor_simulation_stopped,
	)
	editor_ui_set_hidden(builder.world, button, false)
	role := &builder.world.editor_uis[builder.world.entities[button].editor_ui_index]
	role.target = builder.target
	builder.resource_menu_visible = true
	builder.row_count += 1
}

editor_ui_build_resource_menu :: proc(state: ^State, world: ^shared.World) {
	menu, content := editor_ui_ensure_resource_menu(world)
	if state == nil || !world.ui_layouts[world.entities[menu].ui_layout_index].popup_open {
		return
	}
	count := 0
	if state.resource_registry != nil {
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
	menu_layout := &world.ui_layouts[world.entities[menu].ui_layout_index]
	menu_layout.size.y = content_layout.size.y + 10
	for binding in world.editor_uis {
		if binding.role == .Inspector_Resource_Menu_Item && binding.slot >= count {
			editor_ui_set_hidden(world, binding.entity_index, true)
		}
	}
}

editor_ui_ensure_component_menu_button :: proc(world: ^shared.World, parent: string) -> int {
	theme := reduced_dark_theme()
	button, found := editor_ui_entity(world, .Inspector_Component_Menu_Button)
	if found {
		editor_ui_set_parent(world, button, parent)
	} else {
		layout, _ := theme_button(theme)
		layout.size = {1, 30}
		layout.fill_width = true
		button = editor_ui_create_box(
			world,
			"__scrapbot_editor_component_menu_button",
			parent,
			.Inspector_Component_Menu_Button,
			layout,
		)
		editor_ui_add_button(world, button)
	}
	value := world.ui_buttons[world.entities[button].ui_button_index]
	menu, _ := editor_ui_ensure_component_menu(world)
	value.text = "Add Component"
	value.popup = world.entities[menu].uuid
	value.size = EDITOR_TEXT_SIZE
	value.color = theme.palette.text_secondary
	value.alignment = .Center
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
	value.hover_color = theme.palette.accent_text
	value.active_color = theme.palette.accent_text
	_ = ecs.set_ui_button(world, button, value)
	return button
}

editor_ui_ensure_component_menu :: proc(world: ^shared.World) -> (int, int) {
	menu, menu_found := editor_ui_entity(world, .Inspector_Component_Menu)
	content, content_found := editor_ui_entity(world, .Inspector_Component_Menu_Content)
	if menu_found && content_found {
		return menu, content
	}
	theme := reduced_dark_theme()
	menu = editor_ui_create_box(
		world,
		EDITOR_UI_COMPONENT_MENU_NAME,
		"",
		.Inspector_Component_Menu,
		{
			size = {320, 320},
			padding = {5, 5, 5, 5},
			background = theme.palette.overlay,
			border_color = theme.palette.border_strong,
			border_width = 0,
			corner_radius = theme.metrics.radius_large,
			popup = true,
			popup_gap = 4,
			popup_min_width = 220,
			popup_max_width = 420,
			popup_max_height = 360,
			popup_viewport_margin = 4,
		},
	)
	editor_ui_add_vstack(world, menu, {fill = true})
	filter := editor_ui_create_browser_filter(
		world,
		EDITOR_UI_COMPONENT_MENU_FILTER_NAME,
		EDITOR_UI_COMPONENT_MENU_NAME,
		3,
	)
	content = editor_ui_create_box(
		world,
		EDITOR_UI_COMPONENT_MENU_CONTENT_NAME,
		EDITOR_UI_COMPONENT_MENU_NAME,
		.Inspector_Component_Menu_Content,
		{size = {310, 276}, fill_width = true},
	)
	list := theme_list(theme)
	list.filter_input = world.entities[filter].uuid
	list.gap = 1
	editor_ui_add_list(world, content, list)
	editor_ui_add_scroll(world, content)
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
	theme := reduced_dark_theme()
	group := editor_ui_create_box(
		world,
		name,
		parent,
		.Inspector_Component_Menu_Group,
		{size = {1, 24}, padding = {5, 0, 5, f32(10 + depth * 12)}, fill_width = true},
		slot,
	)
	editor_ui_add_text(world, group, label, theme.palette.text_muted, EDITOR_TEXT_SIZE)
	return group
}

editor_ui_ensure_component_menu_item :: proc(
	world: ^shared.World,
	definition_index, depth: int,
	parent, label: string,
) -> int {
	theme := reduced_dark_theme()
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
	value.color = theme.palette.text
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
	value.hover_color = theme.palette.accent_text
	value.active_color = theme.palette.accent_text
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
		case .Material_Metallic, .Material_Roughness:
			input.step = 0.01
			input.minimum = 0
			input.maximum = 1
			input.has_minimum = true
			input.has_maximum = true
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

editor_ui_set_reflected_path :: proc(binding: ^shared.Editor_UI_Component, path: []int) {
	if binding == nil {
		return
	}
	binding.reflected_path = {}
	binding.reflected_path_count = min(len(path), len(binding.reflected_path))
	copy(
		binding.reflected_path[:binding.reflected_path_count],
		path[:binding.reflected_path_count],
	)
}

editor_ui_reflected_path_equal :: proc(binding: ^shared.Editor_UI_Component, path: []int) -> bool {
	if binding == nil || binding.reflected_path_count != len(path) {
		return false
	}
	for value, index in path {
		if binding.reflected_path[index] != value {
			return false
		}
	}
	return true
}

editor_ui_reflected_bindings_same_path :: proc(a, b: shared.Editor_UI_Component) -> bool {
	if a.reflected_path_count != b.reflected_path_count {
		return false
	}
	for index in 0 ..< a.reflected_path_count {
		if a.reflected_path[index] != b.reflected_path[index] {
			return false
		}
	}
	return true
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
	reflected_path: []int = nil,
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
	label_text.color = reduced_dark_theme().palette.text_muted
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
				   !editor_ui_reflected_path_equal(role, reflected_path) ||
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
		editor_ui_set_reflected_path(role, reflected_path)
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
			theme := reduced_dark_theme()
			value_input.prefix_color = theme.palette.axis_x
			if role.inspector_axis == .Y {
				prefix = "Y"
				value_input.prefix_color = theme.palette.axis_y
			} else if role.inspector_axis == .Z {
				prefix = "Z"
				value_input.prefix_color = theme.palette.axis_z
			} else if role.inspector_axis == .W {
				prefix = "W"
				value_input.prefix_color = theme.palette.axis_w
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
	reflected_path: []int = nil,
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
	label_text.color = reduced_dark_theme().palette.text_muted
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
	editor_ui_set_reflected_path(role, reflected_path)
	builder.row_count += 1
}

editor_ui_inspector_enum :: proc(
	builder: ^Inspector_ECS_Builder,
	label, value: string,
	reflected_component_id: shared.Component_ID,
	reflected_field_index: int,
	read_only: bool,
	reflected_path: []int = nil,
) {
	if builder == nil || builder.table_entity < 0 {
		return
	}
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
	editor_ui_set_text(builder.world, label_cell, label)
	menu, _ := editor_ui_ensure_enum_menu(builder.world)
	popup: shared.Entity_UUID
	if !read_only {
		popup = builder.world.entities[menu].uuid
	}
	button := editor_ui_ensure_inspector_enum_button(
		builder.world,
		builder.enum_button_count,
		builder.world.entities[value_cell].name,
		value,
		popup,
		read_only,
	)
	builder.enum_button_count += 1
	editor_ui_set_hidden(builder.world, button, false)
	role := &builder.world.editor_uis[builder.world.entities[button].editor_ui_index]
	role.target = builder.target
	role.reflected_component_id = reflected_component_id
	role.reflected_field_index = reflected_field_index
	editor_ui_set_reflected_path(role, reflected_path)
	role.read_only = read_only
	builder.row_count += 1
}

editor_ui_inspector_entity_reference :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: shared.Entity_UUID,
	reflected_component_id: shared.Component_ID,
	reflected_field_index: int,
	read_only: bool,
	reflected_path: []int = nil,
) {
	if builder == nil || builder.table_entity < 0 {
		return
	}
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
	editor_ui_set_text(builder.world, label_cell, label)
	menu, _, _ := editor_ui_ensure_entity_menu(builder.world)
	popup: shared.Entity_UUID
	if !read_only {
		popup = builder.world.entities[menu].uuid
	}
	button := editor_ui_ensure_entity_menu_button(
		builder.world,
		builder.entity_button_count,
		builder.world.entities[value_cell].name,
		editor_entity_menu_label(builder.world, value),
		popup,
		read_only,
	)
	builder.entity_button_count += 1
	editor_ui_set_hidden(builder.world, button, false)
	role := &builder.world.editor_uis[builder.world.entities[button].editor_ui_index]
	role.target = builder.target
	role.reflected_component_id = reflected_component_id
	role.reflected_field_index = reflected_field_index
	editor_ui_set_reflected_path(role, reflected_path)
	role.entity_reference = value
	role.read_only = read_only
	builder.row_count += 1
}

editor_ui_nested_label :: proc(label: string, depth: int) -> string {
	indent := "                "
	count := min(max(depth, 0) * 2, len(indent))
	return fmt.tprintf("%s%s", indent[:count], label)
}

editor_ui_ensure_container_disclosure :: proc(
	world: ^shared.World,
	slot: int,
	parent: string,
) -> int {
	button, found := editor_ui_entity(world, .Inspector_Container_Disclosure, slot)
	if !found {
		button = editor_ui_create_box(
			world,
			fmt.tprintf("__scrapbot_editor_inspector_container_%d", slot),
			parent,
			.Inspector_Container_Disclosure,
			{size = {INSPECTOR_CONTROL_HEIGHT, INSPECTOR_CONTROL_HEIGHT}, corner_radius = 3},
			slot,
		)
		editor_ui_add_button(world, button)
	} else {
		editor_ui_set_parent(world, button, parent)
	}
	layout := &world.ui_layouts[world.entities[button].ui_layout_index]
	layout.size = {INSPECTOR_CONTROL_HEIGHT, INSPECTOR_CONTROL_HEIGHT}
	layout.fill_width = false
	layout.fixed_in_fill = true
	return button
}

editor_ui_inspector_container :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	item_count: int,
	is_array: bool,
	reflected_component_id: shared.Component_ID,
	reflected_field_index: int,
	reflected_path: []int,
	depth: int,
) -> bool {
	if builder == nil || builder.table_entity < 0 {
		return false
	}
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
	kind := "fields"
	if is_array {
		kind = "items"
	}
	editor_ui_set_text(
		builder.world,
		label_cell,
		fmt.tprintf("%s (%d %s)", editor_ui_nested_label(label, depth), item_count, kind),
	)
	button := editor_ui_ensure_container_disclosure(
		builder.world,
		builder.container_disclosure_count,
		builder.world.entities[value_cell].name,
	)
	builder.container_disclosure_count += 1
	editor_ui_set_hidden(builder.world, button, false)
	binding := &builder.world.editor_uis[builder.world.entities[button].editor_ui_index]
	same_binding :=
		binding.target == builder.target &&
		binding.reflected_component_id == reflected_component_id &&
		binding.reflected_field_index == reflected_field_index &&
		editor_ui_reflected_path_equal(binding, reflected_path)
	if !same_binding {
		binding.expanded = false
	}
	binding.target = builder.target
	binding.reflected_component_id = reflected_component_id
	binding.reflected_field_index = reflected_field_index
	editor_ui_set_reflected_path(binding, reflected_path)
	value := builder.world.ui_buttons[builder.world.entities[button].ui_button_index]
	value.text = " "
	value.icon_set = shared.builtin_icon_set_uuid()
	value.icon = "caret-right"
	if binding.expanded {
		value.icon = "caret-down"
	}
	value.icon_inset = 6
	theme := reduced_dark_theme()
	value.color = theme.palette.text_secondary
	value.hover_background = theme.palette.hover
	value.active_background = theme.palette.active
	_ = ecs.set_ui_button(builder.world, button, value)
	builder.row_count += 1
	return binding.expanded
}

editor_ui_inspector_reflected_value :: proc(
	builder: ^Inspector_ECS_Builder,
	definition: ^component.Definition,
	label: string,
	value: any,
	field: component.Field_Definition,
	field_index: int,
	path: [8]int,
	path_count: int,
	depth: int,
) {
	if builder == nil || definition == nil || value == nil {
		return
	}
	display_label := editor_ui_nested_label(label, depth)
	read_only := definition.lifecycle != .Authored || !editor_reflected_value_is_writable(value)
	path_value := path
	path_slice := path_value[:path_count]
	if editor_reflected_value_is_enum(value) {
		display, valid := editor_reflected_enum_display_name(value)
		editor_ui_inspector_enum(
			builder,
			display_label,
			display,
			definition.id,
			field_index,
			read_only || !valid,
			path_slice,
		)
		return
	}
	if value.id == typeid_of(shared.Entity_UUID) {
		editor_ui_inspector_entity_reference(
			builder,
			display_label,
			(cast(^shared.Entity_UUID)value.data)^,
			definition.id,
			field_index,
			read_only,
			path_slice,
		)
		return
	}
	field_type, leaf := editor_reflected_value_field_type(value)
	if path_count == 0 {
		field_type = field.field_type
	}
	if !leaf {
		item_count, container := editor_reflected_container_count(value)
		if container {
			info := reflect.type_info_base(type_info_of(value.id))
			_, is_array := info.variant.(reflect.Type_Info_Array)
			if !editor_ui_inspector_container(
				builder,
				label,
				item_count,
				is_array,
				definition.id,
				field_index,
				path_slice,
				depth,
			) {
				return
			}
			if path_count >= len(path) {
				return
			}
			for child_index in 0 ..< item_count {
				child, child_found := editor_reflected_container_child(value, child_index)
				child_name, name_found := editor_reflected_container_child_name(value, child_index)
				if !child_found || !name_found {
					continue
				}
				child_path := path
				child_path[path_count] = child_index
				child_field := component.Field_Definition {
					name = child_name,
					field_type = .String,
				}
				if child_type, described := editor_reflected_value_field_type(child); described {
					child_field.field_type = child_type
				}
				editor_ui_inspector_reflected_value(
					builder,
					definition,
					child_name,
					child,
					child_field,
					field_index,
					child_path,
					path_count + 1,
					depth + 1,
				)
			}
			return
		}
	}
	if field_type == .Bool {
		editor_ui_inspector_bool(
			builder,
			display_label,
			(cast(^bool)value.data)^,
			.None,
			definition.id,
			field_index,
			read_only,
			path_slice,
		)
		return
	}
	if field_type == .Color || field.editor.color {
		result := shared.Vec4{0, 0, 0, 1}
		axes := [4]shared.Editor_Inspector_Axis{.X, .Y, .Z, .W}
		component_count := 0
		for axis, axis_index in axes {
			number, found := editor_reflected_axis_number(value, axis)
			if !found {
				break
			}
			editor_color_set_component(&result, axis_index, number)
			component_count += 1
		}
		if component_count == 3 || component_count == 4 {
			hdr := !field.editor.has_maximum || field.editor.maximum > 1
			editor_ui_inspector_color(
				builder,
				display_label,
				result,
				component_count,
				hdr,
				definition.id,
				field_index,
				{},
				.None,
				read_only,
				path_slice,
			)
		}
		return
	}
	values: [4]string
	uuid_buffer: [36]u8
	count, found := editor_reflected_value_texts(value, field_type, uuid_buffer[:], &values)
	if !found {
		return
	}
	editor_ui_inspector_field_values(
		builder,
		display_label,
		values[:count],
		.None,
		-1,
		-1,
		definition.id,
		field_index,
		field_type,
		{},
		field.editor,
		read_only,
		path_slice,
	)
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
	editor_ui_inspector_reflected_value(
		builder,
		definition,
		field.name,
		field_value,
		field,
		field_index,
		{},
		0,
		0,
	)
}

editor_ui_inspector_color :: proc(
	builder: ^Inspector_ECS_Builder,
	label: string,
	value: shared.Vec4,
	component_count: int,
	hdr: bool,
	reflected_component_id: shared.Component_ID = shared.INVALID_COMPONENT_ID,
	reflected_field_index: int = -1,
	resource_id: shared.Resource_UUID = {},
	field: shared.Editor_Inspector_Field = .None,
	read_only: bool = false,
	reflected_path: []int = nil,
) {
	if builder == nil || builder.table_entity < 0 {
		return
	}
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
	editor_ui_set_text(builder.world, label_cell, label)
	button, picker_entity := editor_ui_ensure_inspector_color(
		builder.world,
		builder.color_count,
		builder.world.entities[value_cell].name,
	)
	builder.color_count += 1
	editor_ui_set_hidden(builder.world, button, false)
	editor_ui_set_hidden(builder.world, picker_entity, false)
	display := color_picker_display_color({value.x, value.y, value.z})
	display.w = value.w
	button_layout := &builder.world.ui_layouts[builder.world.entities[button].ui_layout_index]
	button_layout.background = display
	picker_index := builder.world.entities[picker_entity].ui_color_picker_index
	picker := builder.world.ui_color_pickers[picker_index]
	binding := &builder.world.editor_uis[builder.world.entities[picker_entity].editor_ui_index]
	same_open_binding :=
		binding.target == builder.target &&
		binding.inspector_field == field &&
		binding.reflected_component_id == reflected_component_id &&
		binding.reflected_field_index == reflected_field_index &&
		editor_ui_reflected_path_equal(binding, reflected_path) &&
		binding.resource_id == resource_id &&
		builder.world.ui_layouts[builder.world.entities[picker_entity].ui_layout_index].popup_open
	picker.value = value
	picker.hdr = hdr
	picker.show_alpha = component_count == 4
	picker.read_only = read_only
	if !hdr {
		picker.exposure = 0
	} else if !same_open_binding {
		maximum := max(value.x, max(value.y, value.z))
		picker.exposure = 0
		if maximum > 1 {
			picker.exposure = clamp(math.log2(maximum), f32(0), picker.maximum_exposure)
		}
	}
	_ = ecs.set_ui_color_picker(builder.world, picker_entity, picker)
	binding.target = builder.target
	binding.inspector_field = field
	binding.reflected_component_id = reflected_component_id
	binding.reflected_field_index = reflected_field_index
	editor_ui_set_reflected_path(binding, reflected_path)
	binding.resource_id = resource_id
	binding.color_component_count = component_count
	binding.read_only = read_only
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
			case .Inspector_Color_Button, .Inspector_Color_Picker:
				if component.slot >=
				   builder.color_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Enum_Menu_Button:
				if component.slot >=
				   builder.enum_button_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Entity_Menu_Button:
				if component.slot >=
				   builder.entity_button_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
			case .Inspector_Container_Disclosure:
				if component.slot >=
				   builder.container_disclosure_count { editor_ui_set_hidden(builder.world, component.entity_index, true) }
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
	if menu, found := editor_ui_entity(builder.world, .Inspector_Enum_Menu); found {
		menu_entity := builder.world.entities[menu]
		layout := builder.world.ui_layouts[menu_entity.ui_layout_index]
		if layout.popup_open {
			binding_valid := false
			if anchor, anchor_found := ecs.entity_index_by_uuid(
				builder.world,
				layout.popup_anchor,
			); anchor_found {
				anchor_entity := builder.world.entities[anchor]
				if anchor_entity.editor_ui_index >= 0 &&
				   anchor_entity.editor_ui_index < len(builder.world.editor_uis) &&
				   menu_entity.editor_ui_index >= 0 &&
				   menu_entity.editor_ui_index < len(builder.world.editor_uis) {
					anchor_binding := builder.world.editor_uis[anchor_entity.editor_ui_index]
					menu_binding := builder.world.editor_uis[menu_entity.editor_ui_index]
					binding_valid =
						anchor_binding.role == .Inspector_Enum_Menu_Button &&
						anchor_binding.slot < builder.enum_button_count &&
						anchor_binding.target == menu_binding.target &&
						anchor_binding.reflected_component_id ==
							menu_binding.reflected_component_id &&
						anchor_binding.reflected_field_index ==
							menu_binding.reflected_field_index &&
						editor_ui_reflected_bindings_same_path(anchor_binding, menu_binding)
				}
			}
			if !binding_valid {
				_ = set_popup_open(builder.world, menu, false)
			}
		}
	}
	if menu, found := editor_ui_entity(builder.world, .Inspector_Entity_Menu); found {
		menu_entity := builder.world.entities[menu]
		layout := builder.world.ui_layouts[menu_entity.ui_layout_index]
		if layout.popup_open {
			binding_valid := false
			if anchor, anchor_found := ecs.entity_index_by_uuid(
				builder.world,
				layout.popup_anchor,
			); anchor_found {
				anchor_entity := builder.world.entities[anchor]
				if anchor_entity.editor_ui_index >= 0 &&
				   anchor_entity.editor_ui_index < len(builder.world.editor_uis) &&
				   menu_entity.editor_ui_index >= 0 &&
				   menu_entity.editor_ui_index < len(builder.world.editor_uis) {
					anchor_binding := builder.world.editor_uis[anchor_entity.editor_ui_index]
					menu_binding := builder.world.editor_uis[menu_entity.editor_ui_index]
					binding_valid =
						anchor_binding.role == .Inspector_Entity_Menu_Button &&
						anchor_binding.slot < builder.entity_button_count &&
						anchor_binding.target == menu_binding.target &&
						anchor_binding.reflected_component_id ==
							menu_binding.reflected_component_id &&
						anchor_binding.reflected_field_index ==
							menu_binding.reflected_field_index &&
						editor_ui_reflected_bindings_same_path(anchor_binding, menu_binding)
				}
			}
			if !binding_valid {
				_ = set_popup_open(builder.world, menu, false)
			}
		}
	}
	if !builder.component_menu_visible {
		if menu, found := editor_ui_entity(builder.world, .Inspector_Component_Menu); found {
			_ = set_popup_open(builder.world, menu, false)
		}
	}
	if !builder.resource_menu_visible {
		if menu, found := editor_ui_entity(builder.world, .Inspector_Resource_Menu); found {
			_ = set_popup_open(builder.world, menu, false)
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
	for binding in world.editor_uis {
		if binding.role != .Inspector_Component_Menu_Group &&
		   binding.role != .Inspector_Component_Menu_Item {
			continue
		}
		editor_ui_set_hidden(world, binding.entity_index, true)
	}
	if state == nil ||
	   state.component_registry == nil ||
	   !world.ui_layouts[world.entities[menu].ui_layout_index].popup_open {
		return
	}
	registry := state.component_registry
	editor_ui_refresh_component_menu_cache(state)
	group_slot := 0
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
	}
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
	if icon_set_handle, icon_set_found := resources.icon_set_handle_by_uuid(
		state.resource_registry,
		id,
	); icon_set_found {
		icon_set, alive := resources.get_icon_set(state.resource_registry, icon_set_handle)
		if alive && icon_set.authored {
			editor_ui_begin_inspector_component(&builder, "ICON SET")
			editor_ui_inspector_field(&builder, "source directory", icon_set.asset_source)
			editor_ui_inspector_field(
				&builder,
				"symbols",
				fmt.tprintf("%d", len(icon_set.desc.symbols)),
			)
			editor_ui_inspector_field(
				&builder,
				"atlas",
				fmt.tprintf("%d x %d", icon_set.desc.width, icon_set.desc.height),
			)
			editor_ui_begin_inspector_component(&builder, "IMPORT")
			editor_ui_inspector_field(&builder, "status", editor_resource_import_status(state, id))
			editor_ui_inspector_field(&builder, "dependency", icon_set.asset_source)
			editor_ui_inspector_field(&builder, "product", "RGBA8 MTSDF atlas + symbol metadata")
			editor_ui_inspector_field(
				&builder,
				"product size",
				editor_format_byte_count(icon_set.import_byte_count),
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
	if theme, theme_found := resources.get_ui_theme_by_id(state.resource_registry, id);
	   theme_found {
		editor_ui_begin_inspector_component(&builder, "UI THEME")
		editor_ui_inspector_field(&builder, "font", theme.value.font)
		editor_ui_inspector_field(
			&builder,
			"text sizes",
			fmt.tprintf(
				"%.0f / %.0f px",
				theme.value.metrics.text_size,
				theme.value.metrics.small_text_size,
			),
		)
		editor_ui_inspector_field(
			&builder,
			"radii",
			fmt.tprintf(
				"%.0f / %.0f / %.0f px",
				theme.value.metrics.radius_small,
				theme.value.metrics.radius,
				theme.value.metrics.radius_large,
			),
		)
		editor_ui_inspector_field(&builder, "resolution", "Composition time")
		editor_ui_inspector_field(&builder, "renderer state", "None")
		editor_ui_finish_inspector(&builder)
		return
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
	editor_ui_inspector_color(
		&builder,
		"base color",
		shared.Vec4(material.desc.base_color),
		4,
		false,
		shared.INVALID_COMPONENT_ID,
		-1,
		material.id,
		.Material_Base_Color,
	)
	editor_ui_inspector_color(
		&builder,
		"emissive",
		{material.desc.emissive.x, material.desc.emissive.y, material.desc.emissive.z, 1},
		3,
		true,
		shared.INVALID_COMPONENT_ID,
		-1,
		material.id,
		.Material_Emissive,
	)
	editor_ui_inspector_resource_values(
		&builder,
		"metallic",
		[]string{fmt.tprintf("%.2f", material.desc.metallic_factor)},
		.Material_Metallic,
		material.id,
	)
	editor_ui_inspector_resource_values(
		&builder,
		"roughness",
		[]string{fmt.tprintf("%.2f", material.desc.roughness_factor)},
		.Material_Roughness,
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
		   binding.role == .Inspector_Preview_Place ||
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
	editor_ui_inspector_preview_surface(builder, model.id, true, true)
}

editor_ui_inspector_preview_surface :: proc(
	builder: ^Inspector_ECS_Builder,
	resource: shared.Resource_UUID,
	interactive := true,
	placeable := false,
) {
	theme := reduced_dark_theme()
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
				border_color = theme.palette.border,
				border_width = 0,
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
		editor_ui_add_hstack(builder.world, toolbar, {gap = 8})
	} else {
		editor_ui_set_parent(builder.world, toolbar, panel_name)
		editor_ui_set_hidden(builder.world, toolbar, !interactive)
	}
	editor_ui_set_hidden(builder.world, toolbar, !interactive)
	toolbar_name := builder.world.entities[toolbar].name
	place, place_found := editor_ui_entity(builder.world, .Inspector_Preview_Place, panel_slot)
	if !place_found {
		place_layout, place_button := theme_button(theme, .Primary)
		place_layout.size = {128, 28}
		place_layout.basis = 128
		place = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_place_%d", panel_slot),
			toolbar_name,
			.Inspector_Preview_Place,
			place_layout,
			panel_slot,
		)
		button := place_button
		button.text = "ADD TO SCENE"
		button.size = EDITOR_TEXT_SIZE
		_ = ecs.set_ui_button(builder.world, place, button)
	} else {
		editor_ui_set_parent(builder.world, place, toolbar_name)
	}
	editor_ui_set_hidden(
		builder.world,
		place,
		!interactive || !placeable || !builder.state.editor_simulation_stopped,
	)
	reset, reset_found := editor_ui_entity(builder.world, .Inspector_Preview_Reset, panel_slot)
	if !reset_found {
		reset_layout, reset_button := theme_button(theme, .Quiet)
		reset_layout.size = {64, 28}
		reset_layout.basis = 64
		reset = editor_ui_create_box(
			builder.world,
			fmt.tprintf("__scrapbot_editor_asset_preview_reset_%d", panel_slot),
			toolbar_name,
			.Inspector_Preview_Reset,
			reset_layout,
			panel_slot,
		)
		button := reset_button
		button.text = "RESET"
		button.color = theme.palette.text_muted
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
			{size = {200, 28}, basis = 200, grow = 1, shrink = 1},
			panel_slot,
		)
		editor_ui_add_text(
			builder.world,
			hint,
			"DRAG TO ORBIT  /  SCROLL TO ZOOM",
			theme.palette.text_muted,
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
		theme := reduced_dark_theme()
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
			label_text.color = theme.palette.text
			if entity.origin == .Runtime { label_text.color = theme.palette.text_muted }
			disclosure_layout := &world.ui_layouts[world.entities[disclosure].ui_layout_index]
			disclosure_layout.position.x = 6
			label_layout := &world.ui_layouts[world.entities[label].ui_layout_index]
			label_layout.position.x = 26
			button := &world.ui_buttons[world.entities[disclosure].ui_button_index]
			icon := "caret-down"
			if state.editor_collapsed_entities != nil &&
			   state.editor_collapsed_entities[entity.uuid] {
				icon = "caret-right"
			}
			if button.icon != icon {
				value := button^
				value.icon_set = shared.builtin_icon_set_uuid()
				value.icon = icon
				_ = ecs.set_ui_button(world, disclosure, value)
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
			editor_ui_set_resource_drag_source(world, row, false)
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
			editor_ui_set_resource_drag_source(world, row, false)
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
			editor_ui_set_resource_drag_source(world, row, false)
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
			editor_ui_set_resource_drag_source(world, row, true)
			if state.editor_has_resource_selection && state.editor_selected_resource == model.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, model.name)
			resource_count += 1
		}
		for icon_set in state.resource_registry.icon_sets {
			if !icon_set.alive || !icon_set.authored {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = icon_set.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = icon_set.id
			editor_ui_set_resource_drag_source(world, row, false)
			if state.editor_has_resource_selection &&
			   state.editor_selected_resource == icon_set.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, icon_set.name)
			resource_count += 1
		}
		for theme in state.resource_registry.ui_themes {
			if !theme.alive {
				continue
			}
			row, label := editor_ui_ensure_resource_row(world, resource_count)
			world.entities[row].alive = true
			world.entities[label].alive = true
			editor_ui_set_hidden(world, row, false)
			editor_ui_set_hidden(world, label, false)
			world.editor_uis[world.entities[row].editor_ui_index].resource_id = theme.id
			world.editor_uis[world.entities[label].editor_ui_index].resource_id = theme.id
			editor_ui_set_resource_drag_source(world, row, false)
			if state.editor_has_resource_selection && state.editor_selected_resource == theme.id {
				selected_resource_row = world.entities[row].uuid
			}
			editor_ui_set_text(world, label, theme.name)
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
		if panel, panel_found := ecs.entity_index_by_uuid(
			world,
			shared.entity_uuid_from_engine_name(EDITOR_UI_RESOURCES_NAME),
		); panel_found {
			editor_ui_set_panel_title(world, panel, fmt.tprintf("RESOURCES / %d", resource_count))
		}
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
		if handle, found := resources.icon_set_handle_by_uuid(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			if icon_set, alive := resources.get_icon_set(state.resource_registry, handle); alive {
				selected_resource_version = icon_set.version
			}
		}
		if theme, found := resources.get_ui_theme_by_id(
			state.resource_registry,
			state.editor_selected_resource,
		); found {
			selected_resource_version = theme.version
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
				_, icon_set_found := resources.icon_set_handle_by_uuid(
					state.resource_registry,
					state.editor_selected_resource,
				)
				importable = texture_found || model_found || environment_found || icon_set_found
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
			} else if icon_set_handle, icon_set_found := resources.icon_set_handle_by_uuid(
				state.resource_registry,
				state.editor_selected_resource,
			); icon_set_found {
				icon_set, alive := resources.get_icon_set(state.resource_registry, icon_set_handle)
				if alive && icon_set.authored {
					inputs := [2]int{resource_name, resource_source}
					values := [2]string{icon_set.name, icon_set.source}
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
			} else if theme, theme_found := resources.get_ui_theme_by_id(
				state.resource_registry,
				state.editor_selected_resource,
			); theme_found {
				inputs := [2]int{resource_name, resource_source}
				values := [2]string{theme.name, theme.source}
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
	   binding.role != .Inspector_Resource_Source &&
	   binding.role != .Inspector_Entity_Menu_Filter &&
	   binding.role != .Browser_Filter {
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
	if binding.role == .Browser_Filter || binding.role == .Inspector_Entity_Menu_Filter {
		return
	}
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
