package ecs

import component "../component"
import shared "../shared"
import "core:strings"

Entity_Snapshot :: struct {
	entity: shared.Scene_Entity,
	origin: shared.Entity_Origin,
}

clone_entity_snapshot :: proc(source: ^Entity_Snapshot) -> (^Entity_Snapshot, bool) {
	if source == nil {
		return nil, false
	}
	result := new(Entity_Snapshot)
	result^ = source^
	entity := &result.entity
	entity.name = clone_snapshot_string(entity.name)
	entity.geometry.resource = clone_snapshot_string(entity.geometry.resource)
	entity.material_resource = clone_snapshot_string(entity.material_resource)
	entity.model.resource = clone_snapshot_string(entity.model.resource)
	entity.mesh.primitive = clone_snapshot_string(entity.mesh.primitive)
	entity.world_environment.lighting = clone_snapshot_string(entity.world_environment.lighting)
	entity.world_environment.background = clone_snapshot_string(
		entity.world_environment.background,
	)
	entity.ui_panel.title = clone_snapshot_string(entity.ui_panel.title)
	entity.ui_panel.font = clone_snapshot_string(entity.ui_panel.font)
	entity.ui_dock_space.font = clone_snapshot_string(entity.ui_dock_space.font)
	entity.ui_dock_item.title = clone_snapshot_string(entity.ui_dock_item.title)
	entity.ui_text.text = clone_snapshot_string(entity.ui_text.text)
	entity.ui_text.font = clone_snapshot_string(entity.ui_text.font)
	entity.ui_icon.icon = clone_snapshot_string(entity.ui_icon.icon)
	entity.ui_button.text = clone_snapshot_string(entity.ui_button.text)
	entity.ui_button.font = clone_snapshot_string(entity.ui_button.font)
	entity.ui_button.icon = clone_snapshot_string(entity.ui_button.icon)
	entity.ui_input.text = clone_snapshot_string(entity.ui_input.text)
	entity.ui_input.font = clone_snapshot_string(entity.ui_input.font)
	entity.ui_input.prefix = clone_snapshot_string(entity.ui_input.prefix)
	entity.ui_input.icon = clone_snapshot_string(entity.ui_input.icon)
	entity.ui_action.action = clone_snapshot_string(entity.ui_action.action)
	entity.ui_action.payload = clone_snapshot_string(entity.ui_action.payload)
	entity.custom_components = nil
	for component in source.entity.custom_components {
		copy := shared.Custom_Component {
			component_id = component.component_id,
			name = clone_snapshot_string(component.name),
		}
		for field in component.number_fields {
			append(
				&copy.number_fields,
				shared.Named_Number{name = clone_snapshot_string(field.name), value = field.value},
			)
		}
		for field in component.vec2_fields {
			append(
				&copy.vec2_fields,
				shared.Named_Vec2{name = clone_snapshot_string(field.name), value = field.value},
			)
		}
		for field in component.vec3_fields {
			append(
				&copy.vec3_fields,
				shared.Named_Vec3{name = clone_snapshot_string(field.name), value = field.value},
			)
		}
		for field in component.vec4_fields {
			append(
				&copy.vec4_fields,
				shared.Named_Vec4{name = clone_snapshot_string(field.name), value = field.value},
			)
		}
		append(&entity.custom_components, copy)
	}
	return result, true
}

Registered_Component_Snapshot :: struct {
	component_id: component.Component_ID,
	name: string,
	storage_kind: component.Storage_Kind,
	present: bool,
	value: shared.Scene_Entity,
}

capture_registered_component_snapshot :: proc(
	world: ^World,
	entity_index: int,
	definition: ^component.Definition,
) -> (
	Registered_Component_Snapshot,
	bool,
) {
	if world == nil ||
	   definition == nil ||
	   !component.definition_is_authorable(definition^) ||
	   !entity_is_alive(world, entity_index) {
		return {}, false
	}
	snapshot := Registered_Component_Snapshot {
		component_id = definition.id,
		name = clone_snapshot_string(definition.name),
		storage_kind = definition.storage_kind,
		present = registered_component_is_present(world, entity_index, definition),
		value = {id = world.entities[entity_index].uuid},
	}
	if !snapshot.present {
		return snapshot, true
	}
	entity := world.entities[entity_index]
	value := &snapshot.value
	switch definition.storage_kind {
		case .Custom:
			custom, found := custom_component_for_entity_ref(
				world,
				entity_index,
				definition.id,
				definition.name,
			)
			if !found {
				destroy_registered_component_snapshot(&snapshot)
				return {}, false
			}
			copy := shared.Custom_Component {
				component_id = custom.component_id,
				name = clone_snapshot_string(custom.name),
			}
			for field in custom.number_fields {
				append(
					&copy.number_fields,
					shared.Named_Number {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in custom.vec2_fields {
				append(
					&copy.vec2_fields,
					shared.Named_Vec2 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in custom.vec3_fields {
				append(
					&copy.vec3_fields,
					shared.Named_Vec3 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in custom.vec4_fields {
				append(
					&copy.vec4_fields,
					shared.Named_Vec4 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			append(&value.custom_components, copy)
		case .Transform:
			value.has_transform = true
			value.transform = world.transforms[entity.transform_index]
		case .Camera:
			value.has_camera = true
			value.camera = world.cameras[entity.camera_index]
		case .World_Environment:
			value.has_world_environment = true
			value.world_environment = world.world_environments[entity.world_environment_index]
			value.world_environment.lighting = clone_snapshot_string(
				value.world_environment.lighting,
			)
			value.world_environment.background = clone_snapshot_string(
				value.world_environment.background,
			)
		case .Ambient_Light:
			value.has_ambient_light = true
			value.ambient_light = world.ambient_lights[entity.ambient_light_index]
		case .Directional_Light:
			value.has_directional_light = true
			value.directional_light = world.directional_lights[entity.directional_light_index]
		case .Point_Light:
			value.has_point_light = true
			value.point_light = world.point_lights[entity.point_light_index]
		case .Mesh:
			value.has_mesh = true
			value.mesh = world.meshes[entity.mesh_index]
			value.mesh.primitive = clone_snapshot_string(value.mesh.primitive)
		case .Geometry:
			value.has_geometry = true
			value.geometry.resource = clone_snapshot_string(entity.geometry_resource)
			value.geometry.geometry_mode = entity.geometry_mode
		case .Material:
			value.has_material = true
			value.material_resource = clone_snapshot_string(entity.material_resource)
		case .Model:
			value.has_model = true
			value.model.resource = clone_snapshot_string(entity.model_resource)
			value.model.geometry_mode = entity.geometry_mode
		case .Shadow_Caster:
			value.has_shadow_caster = true
		case .Shadow_Receiver:
			value.has_shadow_receiver = true
		case .UI_Layout:
			value.has_ui_layout = true
			value.ui_layout = world.ui_layouts[entity.ui_layout_index]
		case .UI_Canvas:
			value.has_ui_canvas = true
			value.ui_canvas = world.ui_canvases[entity.ui_canvas_index]
		case .UI_HStack:
			value.has_ui_hstack = true
			value.ui_hstack = world.ui_hstacks[entity.ui_hstack_index]
		case .UI_VStack:
			value.has_ui_vstack = true
			value.ui_vstack = world.ui_vstacks[entity.ui_vstack_index]
		case .UI_Scroll_Area:
			value.has_ui_scroll_area = true
			value.ui_scroll_area = world.ui_scroll_areas[entity.ui_scroll_area_index]
		case .UI_Panel:
			value.has_ui_panel = true
			value.ui_panel = world.ui_panels[entity.ui_panel_index]
			value.ui_panel.title = clone_snapshot_string(value.ui_panel.title)
			value.ui_panel.font = clone_snapshot_string(value.ui_panel.font)
		case .UI_Dock_Space:
			value.has_ui_dock_space = true
			value.ui_dock_space = world.ui_dock_spaces[entity.ui_dock_space_index]
			value.ui_dock_space.font = clone_snapshot_string(value.ui_dock_space.font)
		case .UI_Dock_Item:
			value.has_ui_dock_item = true
			value.ui_dock_item = world.ui_dock_items[entity.ui_dock_item_index]
			value.ui_dock_item.title = clone_snapshot_string(value.ui_dock_item.title)
		case .UI_Table:
			value.has_ui_table = true
			value.ui_table = world.ui_tables[entity.ui_table_index]
		case .UI_List:
			value.has_ui_list = true
			value.ui_list = world.ui_lists[entity.ui_list_index]
		case .UI_Progress:
			value.has_ui_progress = true
			value.ui_progress = world.ui_progresses[entity.ui_progress_index]
		case .UI_Viewport:
			value.has_ui_viewport = true
			value.ui_viewport = world.ui_viewports[entity.ui_viewport_index]
		case .UI_Text:
			value.has_ui_text = true
			value.ui_text = world.ui_texts[entity.ui_text_index]
			value.ui_text.text = clone_snapshot_string(value.ui_text.text)
			value.ui_text.font = clone_snapshot_string(value.ui_text.font)
		case .UI_Icon:
			value.has_ui_icon = true
			value.ui_icon = world.ui_icons[entity.ui_icon_index]
			value.ui_icon.icon = clone_snapshot_string(value.ui_icon.icon)
		case .UI_Button:
			value.has_ui_button = true
			value.ui_button = world.ui_buttons[entity.ui_button_index]
			value.ui_button.text = clone_snapshot_string(value.ui_button.text)
			value.ui_button.font = clone_snapshot_string(value.ui_button.font)
			value.ui_button.icon = clone_snapshot_string(value.ui_button.icon)
		case .UI_Input:
			value.has_ui_input = true
			value.ui_input = world.ui_inputs[entity.ui_input_index]
			value.ui_input.text = clone_snapshot_string(value.ui_input.text)
			value.ui_input.font = clone_snapshot_string(value.ui_input.font)
			value.ui_input.prefix = clone_snapshot_string(value.ui_input.prefix)
			value.ui_input.icon = clone_snapshot_string(value.ui_input.icon)
		case .UI_Checkbox:
			value.has_ui_checkbox = true
			value.ui_checkbox = world.ui_checkboxes[entity.ui_checkbox_index]
		case .UI_Color_Picker:
			value.has_ui_color_picker = true
			value.ui_color_picker = world.ui_color_pickers[entity.ui_color_picker_index]
		case .UI_Action:
			value.has_ui_action = true
			value.ui_action = world.ui_actions[entity.ui_action_index]
			value.ui_action.action = clone_snapshot_string(value.ui_action.action)
			value.ui_action.payload = clone_snapshot_string(value.ui_action.payload)
		case .UI_State,
		     .Keyboard_Input,
		     .Pointer_Input,
		     .Render_Instance,
		     .Editor_Transform_Gizmo,
		     .Derived:
			destroy_registered_component_snapshot(&snapshot)
			return {}, false
	}
	return snapshot, true
}

destroy_registered_component_snapshot :: proc(snapshot: ^Registered_Component_Snapshot) {
	if snapshot == nil {
		return
	}
	delete(snapshot.name)
	entity_snapshot := Entity_Snapshot {
		entity = snapshot.value,
	}
	destroy_entity_snapshot(&entity_snapshot)
	snapshot^ = {}
}

apply_registered_component_snapshot :: proc(
	world: ^World,
	entity_index: int,
	snapshot: ^Registered_Component_Snapshot,
) -> bool {
	if world == nil || snapshot == nil || !entity_is_alive(world, entity_index) {
		return false
	}
	definition := component.Definition {
		id = snapshot.component_id,
		name = snapshot.name,
		storage_kind = snapshot.storage_kind,
		lifecycle = .Authored,
	}
	currently_present := registered_component_is_present(world, entity_index, &definition)
	if !snapshot.present {
		return(
			currently_present &&
			set_registered_component_membership(world, entity_index, &definition, false) \
		)
	}
	if !currently_present &&
	   !set_registered_component_membership(world, entity_index, &definition, true) {
		return false
	}
	value := &snapshot.value
	switch snapshot.storage_kind {
		case .Custom:
			if len(value.custom_components) != 1 {
				return false
			}
			remove_custom_component(world, entity_index, snapshot.component_id, snapshot.name)
			custom := value.custom_components[0]
			storage := ensure_custom_component_storage(world, snapshot.component_id, snapshot.name)
			copy := Custom_Component {
				entity_index = entity_index,
				component_id = snapshot.component_id,
				name = clone_world_string(world, custom.name),
			}
			for field in custom.number_fields {
				append(
					&copy.number_fields,
					Named_Number {
						name = clone_world_string(world, field.name),
						value = field.value,
					},
				)
			}
			for field in custom.vec2_fields {
				append(
					&copy.vec2_fields,
					Named_Vec2{name = clone_world_string(world, field.name), value = field.value},
				)
			}
			for field in custom.vec3_fields {
				append(
					&copy.vec3_fields,
					Named_Vec3{name = clone_world_string(world, field.name), value = field.value},
				)
			}
			for field in custom.vec4_fields {
				append(
					&copy.vec4_fields,
					Named_Vec4{name = clone_world_string(world, field.name), value = field.value},
				)
			}
			ensure_custom_component_entity_capacity(storage, entity_index + 1)
			component_index := INVALID_COMPONENT_INDEX
			for &slot, slot_index in storage.components {
				if slot.entity_index != INVALID_COMPONENT_INDEX {
					continue
				}
				slot = copy
				activate_custom_component_slot(storage, slot_index)
				component_index = slot_index
				break
			}
			if component_index == INVALID_COMPONENT_INDEX {
				append(&storage.components, copy)
				component_index = len(storage.components) - 1
				activate_custom_component_slot(storage, component_index)
			}
			storage.entity_component_indices[entity_index] = component_index
			append_entity_custom_storage(world, entity_index, storage.storage_index)
			bump_component_revision(world, entity_index)
		case .Transform:
			add_transform(world, entity_index, value.transform)
		case .Camera:
			set_optional_camera(world, entity_index, true, value.camera)
			mark_render_entity_dirty(world, entity_index)
		case .World_Environment:
			set_optional_world_environment(world, entity_index, true, value.world_environment)
			bump_component_revision(world, entity_index)
		case .Ambient_Light:
			set_optional_ambient_light(world, entity_index, true, value.ambient_light)
			mark_render_entity_dirty(world, entity_index)
		case .Directional_Light:
			set_optional_directional_light(world, entity_index, true, value.directional_light)
			mark_render_entity_dirty(world, entity_index)
		case .Point_Light:
			set_optional_point_light(world, entity_index, true, value.point_light)
			mark_render_entity_dirty(world, entity_index)
		case .Mesh:
			add_mesh(world, entity_index, value.mesh.primitive, value.mesh.geometry_mode)
		case .Geometry:
			set_entity_geometry_mode(world, entity_index, value.geometry.geometry_mode)
			set_entity_resource(world, entity_index, true, value.geometry.resource)
			mark_render_entity_dirty(world, entity_index)
		case .Material:
			set_entity_resource(world, entity_index, false, value.material_resource)
			mark_render_entity_dirty(world, entity_index)
		case .Model:
			set_entity_geometry_mode(world, entity_index, value.model.geometry_mode)
			set_entity_model_resource(world, entity_index, value.model.resource)
		case .Shadow_Caster:
			world.entities[entity_index].has_shadow_caster = true
			mark_render_entity_dirty(world, entity_index)
		case .Shadow_Receiver:
			world.entities[entity_index].has_shadow_receiver = true
			mark_render_entity_dirty(world, entity_index)
		case .UI_Layout:
			_ = set_ui_layout(world, entity_index, value.ui_layout)
		case .UI_Canvas:
			_ = set_ui_canvas(world, entity_index, value.ui_canvas)
		case .UI_HStack:
			_ = set_ui_hstack(world, entity_index, value.ui_hstack)
		case .UI_VStack:
			_ = set_ui_vstack(world, entity_index, value.ui_vstack)
		case .UI_Scroll_Area:
			_ = set_ui_scroll_area(world, entity_index, value.ui_scroll_area)
		case .UI_Panel:
			_ = set_ui_panel(world, entity_index, value.ui_panel)
		case .UI_Dock_Space:
			_ = set_ui_dock_space(world, entity_index, value.ui_dock_space)
		case .UI_Dock_Item:
			_ = set_ui_dock_item(world, entity_index, value.ui_dock_item)
		case .UI_Table:
			_ = set_ui_table(world, entity_index, value.ui_table)
		case .UI_List:
			_ = set_ui_list(world, entity_index, value.ui_list)
		case .UI_Progress:
			_ = set_ui_progress(world, entity_index, value.ui_progress)
		case .UI_Viewport:
			_ = set_ui_viewport(world, entity_index, value.ui_viewport)
		case .UI_Text:
			_ = set_ui_text(world, entity_index, value.ui_text)
		case .UI_Icon:
			_ = set_ui_icon(world, entity_index, value.ui_icon)
		case .UI_Button:
			_ = set_ui_button(world, entity_index, value.ui_button)
		case .UI_Input:
			_ = set_ui_input(world, entity_index, value.ui_input)
		case .UI_Checkbox:
			_ = set_ui_checkbox(world, entity_index, value.ui_checkbox)
		case .UI_Color_Picker:
			_ = set_ui_color_picker(world, entity_index, value.ui_color_picker)
		case .UI_Action:
			_ = set_ui_action(world, entity_index, value.ui_action)
		case .UI_State,
		     .Keyboard_Input,
		     .Pointer_Input,
		     .Render_Instance,
		     .Editor_Transform_Gizmo,
		     .Derived:
			return false
	}
	return registered_component_is_present(world, entity_index, &definition)
}

capture_entity_snapshot :: proc(world: ^World, entity_index: int) -> (Entity_Snapshot, bool) {
	if !entity_is_alive(world, entity_index) {
		return {}, false
	}

	source := world.entities[entity_index]
	snapshot := Entity_Snapshot {
		origin = source.origin,
		entity = {
			id = source.uuid,
			name = clone_snapshot_string(source.name),
			scene_order = source.scene_order,
			has_shadow_caster = source.has_shadow_caster,
			has_shadow_receiver = source.has_shadow_receiver,
			geometry = {
				resource = clone_snapshot_string(source.geometry_resource),
				geometry_mode = source.geometry_mode,
			},
			material_resource = clone_snapshot_string(source.material_resource),
			model = {
				resource = clone_snapshot_string(source.model_resource),
				geometry_mode = source.geometry_mode,
			},
		},
	}
	entity := &snapshot.entity
	entity.has_model = source.model_resource != ""

	if source.transform_index >= 0 && source.transform_index < len(world.transforms) {
		entity.has_transform = true
		entity.transform = world.transforms[source.transform_index]
	}
	if source.camera_index >= 0 && source.camera_index < len(world.cameras) {
		entity.has_camera = true
		entity.camera = world.cameras[source.camera_index]
	}
	if source.world_environment_index >= 0 &&
	   source.world_environment_index < len(world.world_environments) {
		entity.has_world_environment = true
		entity.world_environment = world.world_environments[source.world_environment_index]
		entity.world_environment.lighting = clone_snapshot_string(
			entity.world_environment.lighting,
		)
		entity.world_environment.background = clone_snapshot_string(
			entity.world_environment.background,
		)
	}
	if source.ambient_light_index >= 0 && source.ambient_light_index < len(world.ambient_lights) {
		entity.has_ambient_light = true
		entity.ambient_light = world.ambient_lights[source.ambient_light_index]
	}
	if source.directional_light_index >= 0 &&
	   source.directional_light_index < len(world.directional_lights) {
		entity.has_directional_light = true
		entity.directional_light = world.directional_lights[source.directional_light_index]
	}
	if source.point_light_index >= 0 && source.point_light_index < len(world.point_lights) {
		entity.has_point_light = true
		entity.point_light = world.point_lights[source.point_light_index]
	}
	if source.mesh_index >= 0 && source.mesh_index < len(world.meshes) {
		entity.has_mesh = true
		entity.mesh = world.meshes[source.mesh_index]
		entity.mesh.primitive = clone_snapshot_string(entity.mesh.primitive)
	}
	entity.has_geometry = source.geometry_resource != ""
	entity.has_material = source.material_resource != ""
	entity.has_model = source.model_resource != ""

	capture_ui_components(world, source, entity)
	for storage in world.custom_components {
		for component in storage.components {
			if component.entity_index != entity_index {
				continue
			}
			copy: shared.Custom_Component
			copy.component_id = component.component_id
			copy.name = clone_snapshot_string(component.name)
			for field in component.number_fields {
				append(
					&copy.number_fields,
					shared.Named_Number {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in component.vec2_fields {
				append(
					&copy.vec2_fields,
					shared.Named_Vec2 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in component.vec3_fields {
				append(
					&copy.vec3_fields,
					shared.Named_Vec3 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			for field in component.vec4_fields {
				append(
					&copy.vec4_fields,
					shared.Named_Vec4 {
						name = clone_snapshot_string(field.name),
						value = field.value,
					},
				)
			}
			append(&entity.custom_components, copy)
		}
	}
	return snapshot, true
}

destroy_entity_snapshot :: proc(snapshot: ^Entity_Snapshot) {
	if snapshot == nil {
		return
	}
	entity := &snapshot.entity
	delete(entity.name)
	delete(entity.geometry.resource)
	delete(entity.material_resource)
	delete(entity.model.resource)
	delete(entity.mesh.primitive)
	delete(entity.world_environment.lighting)
	delete(entity.world_environment.background)
	delete(entity.ui_panel.title)
	delete(entity.ui_panel.font)
	delete(entity.ui_dock_space.font)
	delete(entity.ui_dock_item.title)
	delete(entity.ui_text.text)
	delete(entity.ui_text.font)
	delete(entity.ui_icon.icon)
	delete(entity.ui_button.text)
	delete(entity.ui_button.font)
	delete(entity.ui_button.icon)
	delete(entity.ui_input.text)
	delete(entity.ui_input.font)
	delete(entity.ui_input.prefix)
	delete(entity.ui_input.icon)
	delete(entity.ui_action.action)
	delete(entity.ui_action.payload)
	for &component in entity.custom_components {
		delete(component.name)
		for field in component.number_fields {
			delete(field.name)
		}
		delete(component.number_fields)
		for field in component.vec2_fields {
			delete(field.name)
		}
		delete(component.vec2_fields)
		for field in component.vec3_fields {
			delete(field.name)
		}
		delete(component.vec3_fields)
		for field in component.vec4_fields {
			delete(field.name)
		}
		delete(component.vec4_fields)
	}
	delete(entity.custom_components)
	snapshot^ = {}
}

registered_component_is_present :: proc(
	world: ^World,
	entity_index: int,
	definition: ^component.Definition,
) -> bool {
	if world == nil || definition == nil || !entity_is_alive(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if definition.storage_kind == .Geometry && entity.geometry_resource != "" {
		return true
	}
	if definition.storage_kind == .Material && entity.material_resource != "" {
		return true
	}
	if definition.storage_kind == .Model && entity.model_resource != "" {
		return true
	}
	return entity_has_component(world, entity_index, definition.id, definition.name)
}

set_registered_component_membership :: proc(
	world: ^World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if world == nil ||
	   definition == nil ||
	   !component.definition_is_authorable(definition^) ||
	   !entity_is_alive(world, entity_index) ||
	   registered_component_is_present(world, entity_index, definition) == present {
		return false
	}
	switch definition.storage_kind {
		case .Custom:
			if present {
				value := Custom_Component {
					entity_index = entity_index,
					component_id = definition.id,
					name = clone_world_string(world, definition.name),
				}
				for field in definition.fields[:definition.field_count] {
					switch field.field_type {
						case .Number:
							append(
								&value.number_fields,
								Named_Number{name = clone_world_string(world, field.name)},
							)
						case .Vec2:
							append(
								&value.vec2_fields,
								Named_Vec2{name = clone_world_string(world, field.name)},
							)
						case .Vec3:
							append(
								&value.vec3_fields,
								Named_Vec3{name = clone_world_string(world, field.name)},
							)
						case .Vec4, .Color:
							append(
								&value.vec4_fields,
								Named_Vec4{name = clone_world_string(world, field.name)},
							)
						case .Bool, .String:
					}
				}
				storage := ensure_custom_component_storage(world, definition.id, definition.name)
				ensure_custom_component_entity_capacity(storage, entity_index + 1)
				component_index := INVALID_COMPONENT_INDEX
				for &slot, slot_index in storage.components {
					if slot.entity_index != INVALID_COMPONENT_INDEX {
						continue
					}
					slot = value
					activate_custom_component_slot(storage, slot_index)
					component_index = slot_index
					break
				}
				if component_index == INVALID_COMPONENT_INDEX {
					append(&storage.components, value)
					component_index = len(storage.components) - 1
					activate_custom_component_slot(storage, component_index)
				}
				storage.entity_component_indices[entity_index] = component_index
				append_entity_custom_storage(world, entity_index, storage.storage_index)
				bump_component_revision(world, entity_index)
			} else {
				remove_custom_component(world, entity_index, definition.id, definition.name)
			}
		case .Transform:
			if present {
				add_transform(world, entity_index, Transform_Component{scale = {1, 1, 1}})
			} else {
				remove_transform(world, entity_index)
			}
		case .Camera:
			set_optional_camera(world, entity_index, present, shared.camera_defaults())
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .World_Environment:
			if present {
				for candidate, candidate_index in world.entities {
					if candidate_index != entity_index &&
					   candidate.alive &&
					   candidate.world_environment_index >= 0 &&
					   candidate.world_environment_index < len(world.world_environments) {
						return false
					}
				}
			}
			set_optional_world_environment(
				world,
				entity_index,
				present,
				shared.world_environment_default(),
			)
			bump_component_revision(world, entity_index)
		case .Ambient_Light:
			set_optional_ambient_light(
				world,
				entity_index,
				present,
				{color = {1, 1, 1}, intensity = 0.1},
			)
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Directional_Light:
			set_optional_directional_light(
				world,
				entity_index,
				present,
				{direction = {0, -1, 0}, color = {1, 1, 1}, intensity = 1},
			)
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Point_Light:
			set_optional_point_light(
				world,
				entity_index,
				present,
				{color = {1, 1, 1}, intensity = 1, range = 10},
			)
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Mesh:
			if present {
				add_mesh(world, entity_index, "cube")
			} else {
				remove_mesh(world, entity_index)
			}
		case .Geometry:
			value := ""
			if present {
				value = "cube"
			}
			set_entity_resource(world, entity_index, true, value)
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Material:
			value := ""
			if present {
				value = "default"
			}
			set_entity_resource(world, entity_index, false, value)
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Model:
			value := ""
			set_entity_model_resource(world, entity_index, value)
		case .Shadow_Caster:
			world.entities[entity_index].has_shadow_caster = present
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .Shadow_Receiver:
			world.entities[entity_index].has_shadow_receiver = present
			bump_component_revision(world, entity_index)
			mark_render_entity_dirty(world, entity_index)
		case .UI_Layout:
			if present {
				_ = set_ui_layout(world, entity_index, shared.ui_layout_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Canvas:
			if present {
				_ = set_ui_canvas(world, entity_index, shared.ui_canvas_default())
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_HStack:
			if present {
				_ = set_ui_hstack(world, entity_index, shared.ui_stack_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_VStack:
			if present {
				_ = set_ui_vstack(world, entity_index, shared.ui_stack_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Scroll_Area:
			if present {
				_ = set_ui_scroll_area(world, entity_index, shared.ui_scroll_area_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Panel:
			if present {
				_ = set_ui_panel(world, entity_index, shared.ui_panel_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Dock_Space:
			if present {
				_ = set_ui_dock_space(world, entity_index, shared.ui_dock_space_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Dock_Item:
			if present {
				value := shared.ui_dock_item_default()
				value.title = "Dock Item"
				_ = set_ui_dock_item(world, entity_index, value)
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Table:
			if present {
				_ = set_ui_table(world, entity_index, shared.ui_table_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_List:
			if present {
				_ = set_ui_list(world, entity_index, shared.ui_list_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Progress:
			if present {
				_ = set_ui_progress(world, entity_index, shared.ui_progress_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Viewport:
			if present {
				_ = set_ui_viewport(world, entity_index, shared.ui_viewport_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Text:
			if present {
				_ = set_ui_text(world, entity_index, shared.ui_text_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Icon:
			if present {
				_ = set_ui_icon(world, entity_index, shared.ui_icon_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Button:
			if present {
				_ = set_ui_button(world, entity_index, shared.ui_button_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Input:
			if present {
				_ = set_ui_input(world, entity_index, shared.ui_input_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Checkbox:
			if present {
				_ = set_ui_checkbox(world, entity_index, shared.ui_checkbox_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Color_Picker:
			if present {
				_ = set_ui_color_picker(world, entity_index, shared.ui_color_picker_default())
				bump_component_revision(world, entity_index)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_Action:
			if present {
				value := shared.ui_action_default()
				value.action = "action"
				_ = set_ui_action(world, entity_index, value)
			} else {
				_ = remove_ui_component(world, entity_index, definition.name)
			}
		case .UI_State,
		     .Keyboard_Input,
		     .Pointer_Input,
		     .Render_Instance,
		     .Editor_Transform_Gizmo,
		     .Derived:
			return false
	}
	return registered_component_is_present(world, entity_index, definition) == present
}

set_optional_world_environment :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: World_Environment_Component,
) {
	if world == nil || !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	was_present :=
		entity.world_environment_index >= 0 &&
		entity.world_environment_index < len(world.world_environments)
	if entity.world_environment_index >= 0 &&
	   entity.world_environment_index < len(world.world_environments) {
		current := &world.world_environments[entity.world_environment_index]
		delete(current.lighting, world.string_allocator)
		delete(current.background, world.string_allocator)
		if present {
			current^ = value
			current.lighting = clone_world_string(world, value.lighting)
			current.background = clone_world_string(world, value.background)
		} else {
			current^ = {}
			entity.world_environment_index = INVALID_COMPONENT_INDEX
		}
	} else if present {
		entity.world_environment_index = len(world.world_environments)
		copy := value
		copy.lighting = clone_world_string(world, value.lighting)
		copy.background = clone_world_string(world, value.background)
		append(&world.world_environments, copy)
	}
	if was_present != present {
		world.world_environment_revision += 1
		if world.world_environment_revision == 0 {
			world.world_environment_revision = 1
		}
	}
}

apply_entity_snapshot :: proc(world: ^World, snapshot: ^Entity_Snapshot) -> (int, bool) {
	if world == nil || snapshot == nil || snapshot.entity.id == (shared.Entity_UUID{}) {
		return -1, false
	}
	entity_index, found := entity_index_by_uuid(world, snapshot.entity.id)
	if !found {
		entity_index, found = create_world_entity(
			world,
			snapshot.entity.name,
			snapshot.entity.id,
			snapshot.origin,
			true,
		)
		if !found {
			return -1, false
		}
	}

	value := &snapshot.entity
	entity := &world.entities[entity_index]
	_ = set_entity_origin(world, entity_index, snapshot.origin)
	set_entity_scene_order_index(world, entity_index, value.scene_order)
	set_entity_name(world, entity_index, value.name)
	set_optional_transform(world, entity_index, value.has_transform, value.transform)
	set_optional_camera(world, entity_index, value.has_camera, value.camera)
	set_optional_world_environment(
		world,
		entity_index,
		value.has_world_environment,
		value.world_environment,
	)
	set_optional_ambient_light(world, entity_index, value.has_ambient_light, value.ambient_light)
	set_optional_directional_light(
		world,
		entity_index,
		value.has_directional_light,
		value.directional_light,
	)
	set_optional_point_light(world, entity_index, value.has_point_light, value.point_light)
	if value.has_mesh {
		add_mesh(world, entity_index, value.mesh.primitive, value.mesh.geometry_mode)
	} else {
		remove_mesh(world, entity_index)
	}
	set_entity_geometry_mode(
		world,
		entity_index,
		shared.geometry_mode_override(
			value.mesh.geometry_mode,
			value.geometry.geometry_mode,
			value.model.geometry_mode,
		),
	)
	set_entity_resource(world, entity_index, true, value.geometry.resource)
	set_entity_resource(world, entity_index, false, value.material_resource)
	set_entity_model_resource(world, entity_index, value.model.resource)
	entity.has_shadow_caster = value.has_shadow_caster
	entity.has_shadow_receiver = value.has_shadow_receiver
	apply_ui_snapshot(world, entity_index, value)
	replace_custom_components(world, entity_index, value.custom_components[:])
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
	if entity.ui_layout_index >= 0 {
		mark_ui_subtree_dirty(world, entity_index)
	}
	return entity_index, true
}

delete_entity_by_uuid :: proc(world: ^World, id: shared.Entity_UUID) -> bool {
	entity_index, found := entity_index_by_uuid(world, id)
	if !found {
		return false
	}
	despawn_entity(world, entity_index, world.entities[entity_index].id.generation)
	return true
}

set_entity_name :: proc(world: ^World, entity_index: int, name: string) -> bool {
	if !entity_is_alive(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.name == name {
		return true
	}
	next := clone_world_string(world, name)
	delete_world_string(world, entity.name)
	entity.name = next
	return true
}

promote_entity_to_scene :: proc(world: ^World, entity_index: int) -> bool {
	if !entity_is_alive(world, entity_index) {
		return false
	}
	return set_entity_origin(world, entity_index, .Scene)
}

clone_snapshot_string :: proc(value: string) -> string {
	result, _ := strings.clone(value)
	return result
}

capture_ui_components :: proc(world: ^World, source: World_Entity, entity: ^shared.Scene_Entity) {
	if source.ui_layout_index >= 0 && source.ui_layout_index < len(world.ui_layouts) {
		entity.has_ui_layout = true
		entity.ui_layout = world.ui_layouts[source.ui_layout_index]
	}
	if source.ui_canvas_index >= 0 && source.ui_canvas_index < len(world.ui_canvases) {
		entity.has_ui_canvas = true
		entity.ui_canvas = world.ui_canvases[source.ui_canvas_index]
	}
	if source.ui_hstack_index >= 0 && source.ui_hstack_index < len(world.ui_hstacks) {
		entity.has_ui_hstack = true
		entity.ui_hstack = world.ui_hstacks[source.ui_hstack_index]
	}
	if source.ui_vstack_index >= 0 && source.ui_vstack_index < len(world.ui_vstacks) {
		entity.has_ui_vstack = true
		entity.ui_vstack = world.ui_vstacks[source.ui_vstack_index]
	}
	if source.ui_scroll_area_index >= 0 &&
	   source.ui_scroll_area_index < len(world.ui_scroll_areas) {
		entity.has_ui_scroll_area = true
		entity.ui_scroll_area = world.ui_scroll_areas[source.ui_scroll_area_index]
	}
	if source.ui_panel_index >= 0 && source.ui_panel_index < len(world.ui_panels) {
		entity.has_ui_panel = true
		entity.ui_panel = world.ui_panels[source.ui_panel_index]
		entity.ui_panel.title = clone_snapshot_string(entity.ui_panel.title)
		entity.ui_panel.font = clone_snapshot_string(entity.ui_panel.font)
	}
	if source.ui_dock_space_index >= 0 && source.ui_dock_space_index < len(world.ui_dock_spaces) {
		entity.has_ui_dock_space = true
		entity.ui_dock_space = world.ui_dock_spaces[source.ui_dock_space_index]
		entity.ui_dock_space.font = clone_snapshot_string(entity.ui_dock_space.font)
	}
	if source.ui_dock_item_index >= 0 && source.ui_dock_item_index < len(world.ui_dock_items) {
		entity.has_ui_dock_item = true
		entity.ui_dock_item = world.ui_dock_items[source.ui_dock_item_index]
		entity.ui_dock_item.title = clone_snapshot_string(entity.ui_dock_item.title)
	}
	if source.ui_table_index >= 0 && source.ui_table_index < len(world.ui_tables) {
		entity.has_ui_table = true
		entity.ui_table = world.ui_tables[source.ui_table_index]
	}
	if source.ui_list_index >= 0 && source.ui_list_index < len(world.ui_lists) {
		entity.has_ui_list = true
		entity.ui_list = world.ui_lists[source.ui_list_index]
	}
	if source.ui_progress_index >= 0 && source.ui_progress_index < len(world.ui_progresses) {
		entity.has_ui_progress = true
		entity.ui_progress = world.ui_progresses[source.ui_progress_index]
	}
	if source.ui_viewport_index >= 0 && source.ui_viewport_index < len(world.ui_viewports) {
		entity.has_ui_viewport = true
		entity.ui_viewport = world.ui_viewports[source.ui_viewport_index]
	}
	if source.ui_text_index >= 0 && source.ui_text_index < len(world.ui_texts) {
		entity.has_ui_text = true
		entity.ui_text = world.ui_texts[source.ui_text_index]
		entity.ui_text.text = clone_snapshot_string(entity.ui_text.text)
		entity.ui_text.font = clone_snapshot_string(entity.ui_text.font)
	}
	if source.ui_icon_index >= 0 && source.ui_icon_index < len(world.ui_icons) {
		entity.has_ui_icon = true
		entity.ui_icon = world.ui_icons[source.ui_icon_index]
		entity.ui_icon.icon = clone_snapshot_string(entity.ui_icon.icon)
	}
	if source.ui_button_index >= 0 && source.ui_button_index < len(world.ui_buttons) {
		entity.has_ui_button = true
		entity.ui_button = world.ui_buttons[source.ui_button_index]
		entity.ui_button.text = clone_snapshot_string(entity.ui_button.text)
		entity.ui_button.font = clone_snapshot_string(entity.ui_button.font)
		entity.ui_button.icon = clone_snapshot_string(entity.ui_button.icon)
	}
	if source.ui_input_index >= 0 && source.ui_input_index < len(world.ui_inputs) {
		entity.has_ui_input = true
		entity.ui_input = world.ui_inputs[source.ui_input_index]
		entity.ui_input.text = clone_snapshot_string(entity.ui_input.text)
		entity.ui_input.font = clone_snapshot_string(entity.ui_input.font)
		entity.ui_input.prefix = clone_snapshot_string(entity.ui_input.prefix)
		entity.ui_input.icon = clone_snapshot_string(entity.ui_input.icon)
	}
	if source.ui_checkbox_index >= 0 && source.ui_checkbox_index < len(world.ui_checkboxes) {
		entity.has_ui_checkbox = true
		entity.ui_checkbox = world.ui_checkboxes[source.ui_checkbox_index]
	}
	if source.ui_color_picker_index >= 0 &&
	   source.ui_color_picker_index < len(world.ui_color_pickers) {
		entity.has_ui_color_picker = true
		entity.ui_color_picker = world.ui_color_pickers[source.ui_color_picker_index]
	}
	if source.ui_action_index >= 0 && source.ui_action_index < len(world.ui_actions) {
		entity.has_ui_action = true
		entity.ui_action = world.ui_actions[source.ui_action_index]
		entity.ui_action.action = clone_snapshot_string(entity.ui_action.action)
		entity.ui_action.payload = clone_snapshot_string(entity.ui_action.payload)
	}
}

set_optional_transform :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: Transform_Component,
) {
	if present {
		add_transform(world, entity_index, value)
	} else {
		remove_transform(world, entity_index)
	}
}

set_optional_camera :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: shared.Camera_Component,
) {
	entity := &world.entities[entity_index]
	if present {
		if entity.camera_index >= 0 && entity.camera_index < len(world.cameras) {
			world.cameras[entity.camera_index] = value
		} else {
			entity.camera_index = reusable_camera_slot(world)
			if entity.camera_index >= 0 { world.cameras[entity.camera_index] = value } else {
				entity.camera_index = len(world.cameras)
				append(&world.cameras, value)
			}
		}
	} else {
		entity.camera_index = INVALID_COMPONENT_INDEX
	}
}

set_optional_ambient_light :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: Ambient_Light_Component,
) {
	entity := &world.entities[entity_index]
	if present {
		if entity.ambient_light_index >= 0 &&
		   entity.ambient_light_index < len(world.ambient_lights) {
			world.ambient_lights[entity.ambient_light_index] = value
		} else {
			entity.ambient_light_index = reusable_ambient_light_slot(world)
			if entity.ambient_light_index >=
			   0 { world.ambient_lights[entity.ambient_light_index] = value } else {
				entity.ambient_light_index = len(world.ambient_lights)
				append(&world.ambient_lights, value)
			}
		}
	} else {
		entity.ambient_light_index = INVALID_COMPONENT_INDEX
	}
}

set_optional_directional_light :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: Directional_Light_Component,
) {
	entity := &world.entities[entity_index]
	if present {
		if entity.directional_light_index >= 0 &&
		   entity.directional_light_index < len(world.directional_lights) {
			world.directional_lights[entity.directional_light_index] = value
		} else {
			entity.directional_light_index = reusable_directional_light_slot(world)
			if entity.directional_light_index >=
			   0 { world.directional_lights[entity.directional_light_index] = value } else {
				entity.directional_light_index = len(world.directional_lights)
				append(&world.directional_lights, value)
			}
		}
	} else {
		entity.directional_light_index = INVALID_COMPONENT_INDEX
	}
}

set_optional_point_light :: proc(
	world: ^World,
	entity_index: int,
	present: bool,
	value: Point_Light_Component,
) {
	entity := &world.entities[entity_index]
	if present {
		if entity.point_light_index >= 0 && entity.point_light_index < len(world.point_lights) {
			world.point_lights[entity.point_light_index] = value
		} else {
			entity.point_light_index = reusable_point_light_slot(world)
			if entity.point_light_index >=
			   0 { world.point_lights[entity.point_light_index] = value } else {
				entity.point_light_index = len(world.point_lights)
				append(&world.point_lights, value)
			}
		}
	} else {
		entity.point_light_index = INVALID_COMPONENT_INDEX
	}
}

reusable_camera_slot :: proc(world: ^World) -> int {
	for index in 0 ..< len(world.cameras) {
		used := false
		for entity in world.entities { if entity.alive && entity.camera_index == index { used = true; break } }
		if !used { return index }
	}
	return -1
}

reusable_ambient_light_slot :: proc(world: ^World) -> int {
	for index in 0 ..< len(world.ambient_lights) {
		used := false
		for entity in world.entities { if entity.alive && entity.ambient_light_index == index { used = true; break } }
		if !used { return index }
	}
	return -1
}

reusable_directional_light_slot :: proc(world: ^World) -> int {
	for index in 0 ..< len(world.directional_lights) {
		used := false
		for entity in world.entities { if entity.alive && entity.directional_light_index == index { used = true; break } }
		if !used { return index }
	}
	return -1
}

reusable_point_light_slot :: proc(world: ^World) -> int {
	for index in 0 ..< len(world.point_lights) {
		used := false
		for entity in world.entities { if entity.alive && entity.point_light_index == index { used = true; break } }
		if !used { return index }
	}
	return -1
}

set_entity_resource :: proc(world: ^World, entity_index: int, geometry: bool, value: string) {
	entity := &world.entities[entity_index]
	if geometry {
		if entity.geometry_resource == value {
			return
		}
		delete_world_string(world, entity.geometry_resource)
		entity.geometry_resource = clone_world_string(world, value)
		remove_geometry(world, entity_index)
	} else {
		if entity.material_resource == value {
			return
		}
		delete_world_string(world, entity.material_resource)
		entity.material_resource = clone_world_string(world, value)
		remove_material(world, entity_index)
	}
}

set_entity_model_resource :: proc(world: ^World, entity_index: int, value: string) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.model_resource == value {
		return
	}
	despawn_model_instance_entities(world, entity.uuid)
	delete_world_string(world, entity.model_resource)
	entity.model_resource = clone_world_string(world, value)
	world.model_instance_revision += 1
	if world.model_instance_revision == 0 {
		world.model_instance_revision = 1
	}
	bump_component_revision(world, entity_index)
}

set_entity_geometry_mode :: proc(
	world: ^World,
	entity_index: int,
	geometry_mode: shared.Geometry_Mode,
) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.geometry_mode == geometry_mode {
		return
	}
	entity.geometry_mode = geometry_mode
	if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		world.geometries[entity.geometry_index].geometry_mode = geometry_mode
	}
	if entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes) {
		world.meshes[entity.mesh_index].geometry_mode = geometry_mode
	}
	if entity.model_resource != "" {
		despawn_model_instance_entities(world, entity.uuid)
		world.model_instance_revision += 1
		if world.model_instance_revision == 0 {
			world.model_instance_revision = 1
		}
	}
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

apply_ui_snapshot :: proc(world: ^World, entity_index: int, value: ^shared.Scene_Entity) {
	if value.has_ui_layout { _ = set_ui_layout(world, entity_index, value.ui_layout) } else { remove_ui_component(world, entity_index, "scrapbot.ui_layout") }
	if value.has_ui_canvas { _ = set_ui_canvas(world, entity_index, value.ui_canvas) } else { remove_ui_component(world, entity_index, "scrapbot.ui_canvas") }
	if value.has_ui_hstack { _ = set_ui_hstack(world, entity_index, value.ui_hstack) } else { remove_ui_component(world, entity_index, "scrapbot.ui_hstack") }
	if value.has_ui_vstack { _ = set_ui_vstack(world, entity_index, value.ui_vstack) } else { remove_ui_component(world, entity_index, "scrapbot.ui_vstack") }
	if value.has_ui_scroll_area { _ = set_ui_scroll_area(world, entity_index, value.ui_scroll_area) } else { remove_ui_component(world, entity_index, "scrapbot.ui_scroll_area") }
	if value.has_ui_panel { _ = set_ui_panel(world, entity_index, value.ui_panel) } else { remove_ui_component(world, entity_index, "scrapbot.ui_panel") }
	if value.has_ui_dock_space { _ = set_ui_dock_space(world, entity_index, value.ui_dock_space) } else { remove_ui_component(world, entity_index, "scrapbot.ui_dock_space") }
	if value.has_ui_dock_item { _ = set_ui_dock_item(world, entity_index, value.ui_dock_item) } else { remove_ui_component(world, entity_index, "scrapbot.ui_dock_item") }
	if value.has_ui_table { _ = set_ui_table(world, entity_index, value.ui_table) } else { remove_ui_component(world, entity_index, "scrapbot.ui_table") }
	if value.has_ui_list { _ = set_ui_list(world, entity_index, value.ui_list) } else { remove_ui_component(world, entity_index, "scrapbot.ui_list") }
	if value.has_ui_progress { _ = set_ui_progress(world, entity_index, value.ui_progress) } else { remove_ui_component(world, entity_index, "scrapbot.ui_progress") }
	if value.has_ui_viewport { _ = set_ui_viewport(world, entity_index, value.ui_viewport) } else { remove_ui_component(world, entity_index, "scrapbot.ui_viewport") }
	if value.has_ui_text { _ = set_ui_text(world, entity_index, value.ui_text) } else { remove_ui_component(world, entity_index, "scrapbot.ui_text") }
	if value.has_ui_icon { _ = set_ui_icon(world, entity_index, value.ui_icon) } else { remove_ui_component(world, entity_index, "scrapbot.ui_icon") }
	if value.has_ui_button { _ = set_ui_button(world, entity_index, value.ui_button) } else { remove_ui_component(world, entity_index, "scrapbot.ui_button") }
	if value.has_ui_input { _ = set_ui_input(world, entity_index, value.ui_input) } else { remove_ui_component(world, entity_index, "scrapbot.ui_input") }
	if value.has_ui_checkbox { _ = set_ui_checkbox(world, entity_index, value.ui_checkbox) } else { remove_ui_component(world, entity_index, "scrapbot.ui_checkbox") }
	if value.has_ui_color_picker { _ = set_ui_color_picker(world, entity_index, value.ui_color_picker) } else { remove_ui_component(world, entity_index, "scrapbot.ui_color_picker") }
	if value.has_ui_action { _ = set_ui_action(world, entity_index, value.ui_action) } else { remove_ui_component(world, entity_index, "scrapbot.ui_action") }
}

replace_custom_components :: proc(
	world: ^World,
	entity_index: int,
	components: []shared.Custom_Component,
) {
	if entity_index >= 0 && entity_index < len(world.entities) {
		for len(world.entities[entity_index].custom_component_storage_indices) > 0 {
			storage_index := world.entities[entity_index].custom_component_storage_indices[0]
			if storage_index < 0 || storage_index >= len(world.custom_components) {
				unordered_remove(&world.entities[entity_index].custom_component_storage_indices, 0)
				continue
			}
			storage := &world.custom_components[storage_index]
			remove_custom_component(world, entity_index, storage.component_id, storage.name)
		}
	}
	for component in components {
		add_scene_custom_component(world, entity_index, component)
	}
}
