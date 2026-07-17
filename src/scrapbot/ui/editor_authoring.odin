package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"

Editor_Authoring_Component :: enum {
	Transform,
	Camera,
	Ambient_Light,
	Directional_Light,
	Point_Light,
	Mesh,
	Geometry,
	Material,
	Shadow_Caster,
	Shadow_Receiver,
	UI_Layout,
	UI_HStack,
	UI_VStack,
	UI_Scroll_Area,
	UI_Panel,
	UI_Table,
	UI_List,
	UI_Progress,
	UI_Text,
	UI_Button,
	UI_Input,
	UI_Checkbox,
}

editor_authoring_component_from_name :: proc(name: string) -> (Editor_Authoring_Component, bool) {
	switch name {
		case "scrapbot.transform":
			return .Transform, true
		case "scrapbot.camera":
			return .Camera, true
		case "scrapbot.ambient_light":
			return .Ambient_Light, true
		case "scrapbot.directional_light":
			return .Directional_Light, true
		case "scrapbot.point_light":
			return .Point_Light, true
		case "scrapbot.mesh":
			return .Mesh, true
		case "scrapbot.geometry":
			return .Geometry, true
		case "scrapbot.material":
			return .Material, true
		case "scrapbot.shadow_caster":
			return .Shadow_Caster, true
		case "scrapbot.shadow_receiver":
			return .Shadow_Receiver, true
		case "scrapbot.ui_layout":
			return .UI_Layout, true
		case "scrapbot.ui_hstack":
			return .UI_HStack, true
		case "scrapbot.ui_vstack":
			return .UI_VStack, true
		case "scrapbot.ui_scroll_area":
			return .UI_Scroll_Area, true
		case "scrapbot.ui_panel":
			return .UI_Panel, true
		case "scrapbot.ui_table":
			return .UI_Table, true
		case "scrapbot.ui_list":
			return .UI_List, true
		case "scrapbot.ui_progress":
			return .UI_Progress, true
		case "scrapbot.ui_text":
			return .UI_Text, true
		case "scrapbot.ui_button":
			return .UI_Button, true
		case "scrapbot.ui_input":
			return .UI_Input, true
		case "scrapbot.ui_checkbox":
			return .UI_Checkbox, true
	}
	return {}, false
}

editor_authoring_definition_is_supported :: proc(definition: ^component.Definition) -> bool {
	if definition == nil {
		return false
	}
	if _, found := editor_authoring_component_from_name(definition.name); found {
		return true
	}
	if definition.owner == .Engine {
		return false
	}
	for field in definition.fields[:definition.field_count] {
		if field.field_type != .Vec3 {
			return false
		}
	}
	return true
}

editor_authoring_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if definition == nil || !editor_authoring_definition_is_supported(definition) {
		return false
	}
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		destroy_snapshot_pointer(before)
		return false
	}
	if !set_snapshot_registered_component(&after.entity, definition, present) {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if state == nil || world == nil || definition == nil {
		return false
	}
	if state.editor_simulation_stopped {
		return editor_authoring_set_registered_component(
			state,
			world,
			entity_index,
			definition,
			present,
		)
	}
	if !editor_authoring_definition_is_supported(definition) ||
	   !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil || !set_snapshot_registered_component(&after.entity, definition, present) {
		destroy_snapshot_pointer(after)
		return false
	}
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(after)
		return false
	}
	destroy_snapshot_pointer(after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_component_membership_available :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if state == nil || world == nil || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	origin := world.entities[entity_index].origin
	if state.editor_simulation_stopped {
		return origin == .Scene
	}
	return origin != .Editor
}

editor_authoring_create_entity :: proc(
	state: ^State,
	world: ^shared.World,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) {
		return {}, false
	}
	snapshot := new(ecs.Entity_Snapshot)
	snapshot.origin = .Scene
	snapshot.entity.id = shared.entity_uuid_generate()
	snapshot.entity.name = ecs.clone_snapshot_string("New Entity")
	snapshot.entity.has_transform = true
	snapshot.entity.transform.scale = {1, 1, 1}
	entity_index, ok := ecs.apply_entity_snapshot(world, snapshot)
	if !ok {
		ecs.destroy_entity_snapshot(snapshot)
		free(snapshot)
		return {}, false
	}
	push_structural_change(state, snapshot.entity.id, nil, snapshot)
	editor_authoring_select(state, world, entity_index)
	return world.entities[entity_index].id, true
}

editor_authoring_duplicate_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return {}, false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		return {}, false
	}
	after.entity.id = shared.entity_uuid_generate()
	delete(after.entity.name)
	after.entity.name = ecs.clone_snapshot_string(
		fmt.tprintf("%s Copy", world.entities[entity_index].name),
	)
	after.origin = .Scene
	created_index, ok := ecs.apply_entity_snapshot(world, after)
	if !ok {
		destroy_snapshot_pointer(after)
		return {}, false
	}
	push_structural_change(state, after.entity.id, nil, after)
	editor_authoring_select(state, world, created_index)
	return world.entities[created_index].id, true
}

editor_authoring_delete_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id := before.entity.id
	if !ecs.delete_entity_by_uuid(world, id) {
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, id, before, nil)
	state.editor_has_selection = false
	state.editor_snapshot_valid = false
	return true
}

editor_authoring_rename_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	name: string,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   name == "" ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene || before.entity.name == name {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.set_entity_name(world, entity_index, name) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_set_material_resource :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	resource_id: shared.Resource_UUID,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   state.resource_registry == nil ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	if _, found := resources.material_by_uuid(state.resource_registry, resource_id); !found {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id_buffer: [36]u8
	value := shared.resource_uuid_to_string(resource_id, id_buffer[:])
	if before.entity.material_resource == value {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		destroy_snapshot_pointer(before)
		return false
	}
	delete(after.entity.material_resource)
	after.entity.material_resource = ecs.clone_snapshot_string(value)
	after.entity.has_material = true
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

resolve_snapshot_resource_names :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	snapshot: ^ecs.Entity_Snapshot,
) {
	if state == nil || state.resource_registry == nil || snapshot == nil {
		return
	}
	entity := world.entities[entity_index]
	if snapshot.entity.geometry_resource == "" &&
	   entity.geometry_index >= 0 &&
	   entity.geometry_index < len(world.geometries) {
		handle := world.geometries[entity.geometry_index].handle
		if int(handle.index) < len(state.resource_registry.geometries) {
			resource := state.resource_registry.geometries[handle.index]
			if resource.alive && resource.generation == handle.generation {
				snapshot.entity.has_geometry = true
				snapshot.entity.geometry_resource = ecs.clone_snapshot_string(resource.name)
			}
		}
	}
	if snapshot.entity.material_resource == "" &&
	   entity.material_index >= 0 &&
	   entity.material_index < len(world.materials) {
		handle := world.materials[entity.material_index].handle
		if int(handle.index) < len(state.resource_registry.materials) {
			resource := state.resource_registry.materials[handle.index]
			if resource.alive && resource.authored && resource.generation == handle.generation {
				id_buffer: [36]u8
				snapshot.entity.has_material = true
				snapshot.entity.material_resource = ecs.clone_snapshot_string(
					shared.resource_uuid_to_string(resource.id, id_buffer[:]),
				)
			}
		}
	}
}

editor_authoring_promote_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Runtime {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.promote_entity_to_scene(world, entity_index) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	resolve_snapshot_resource_names(state, world, entity_index, after)
	_, _ = ecs.apply_entity_snapshot(world, after)
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_set_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	component: Editor_Authoring_Component,
	present: bool,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil || !set_snapshot_component(&after.entity, component, present) {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_available :: proc(state: ^State, world: ^shared.World) -> bool {
	return state != nil && world != nil && state.editor_simulation_stopped
}

capture_snapshot_pointer :: proc(world: ^shared.World, entity_index: int) -> ^ecs.Entity_Snapshot {
	snapshot, ok := ecs.capture_entity_snapshot(world, entity_index)
	if !ok {
		return nil
	}
	result := new(ecs.Entity_Snapshot)
	result^ = snapshot
	return result
}

destroy_snapshot_pointer :: proc(snapshot: ^ecs.Entity_Snapshot) {
	if snapshot == nil {
		return
	}
	ecs.destroy_entity_snapshot(snapshot)
	free(snapshot)
}

push_structural_change :: proc(
	state: ^State,
	id: shared.Entity_UUID,
	before, after: ^ecs.Entity_Snapshot,
) {
	change := new(Editor_Structural_Change)
	change.target_uuid = id
	change.before = before
	change.after = after
	editor_history_push_transaction(state, {structural = change})
	editor_mark_scene_uuid_dirty(state, id)
}

editor_authoring_select :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	state.editor_selected_entity = world.entities[entity_index].id
	state.editor_has_selection = true
	state.editor_has_resource_selection = false
	state.editor_snapshot_valid = false
}

set_snapshot_component :: proc(
	entity: ^shared.Scene_Entity,
	component: Editor_Authoring_Component,
	present: bool,
) -> bool {
	switch component {
		case .Transform:
			if entity.has_transform == present { return false }
			entity.has_transform = present
			if present { entity.transform.scale = {1, 1, 1} }
		case .Camera:
			if entity.has_camera == present { return false }
			entity.has_camera = present
			if present {entity.camera = {
					fov = 60,
					near = 0.1,
					far = 1000,
				}}
		case .Ambient_Light:
			if entity.has_ambient_light == present { return false }
			entity.has_ambient_light = present
			if present {entity.ambient_light = {
					color = {1, 1, 1},
					intensity = 0.1,
				}}
		case .Directional_Light:
			if entity.has_directional_light == present { return false }
			entity.has_directional_light = present
			if present {entity.directional_light = {
					direction = {0, -1, 0},
					color = {1, 1, 1},
					intensity = 1,
				}}
		case .Point_Light:
			if entity.has_point_light == present { return false }
			entity.has_point_light = present
			if present {entity.point_light = {
					color = {1, 1, 1},
					intensity = 1,
					range = 10,
				}}
		case .Mesh:
			if entity.has_mesh == present { return false }
			entity.has_mesh = present
			if present { entity.mesh.primitive = ecs.clone_snapshot_string("cube") }
		case .Geometry:
			if entity.has_geometry == present { return false }
			entity.has_geometry = present
			delete(entity.geometry_resource)
			entity.geometry_resource = ""
			if present { entity.geometry_resource = ecs.clone_snapshot_string("cube") }
		case .Material:
			if entity.has_material == present { return false }
			entity.has_material = present
			delete(entity.material_resource)
			entity.material_resource = ""
			if present { entity.material_resource = ecs.clone_snapshot_string("default") }
		case .Shadow_Caster:
			if entity.has_shadow_caster == present { return false }
			entity.has_shadow_caster = present
		case .Shadow_Receiver:
			if entity.has_shadow_receiver == present { return false }
			entity.has_shadow_receiver = present
		case .UI_Layout:
			if entity.has_ui_layout == present { return false }
			entity.has_ui_layout = present
			if present { entity.ui_layout = shared.ui_layout_default() }
		case .UI_HStack:
			if entity.has_ui_hstack == present { return false }
			entity.has_ui_hstack = present
			if present { entity.ui_hstack = shared.ui_stack_default() }
		case .UI_VStack:
			if entity.has_ui_vstack == present { return false }
			entity.has_ui_vstack = present
			if present { entity.ui_vstack = shared.ui_stack_default() }
		case .UI_Scroll_Area:
			if entity.has_ui_scroll_area == present { return false }
			entity.has_ui_scroll_area = present
			if present { entity.ui_scroll_area = shared.ui_scroll_area_default() }
		case .UI_Panel:
			if entity.has_ui_panel == present { return false }
			entity.has_ui_panel = present
			if present { entity.ui_panel = shared.ui_panel_default() }
		case .UI_Table:
			if entity.has_ui_table == present { return false }
			entity.has_ui_table = present
			if present { entity.ui_table = shared.ui_table_default() }
		case .UI_List:
			if entity.has_ui_list == present { return false }
			entity.has_ui_list = present
			if present { entity.ui_list = shared.ui_list_default() }
		case .UI_Progress:
			if entity.has_ui_progress == present { return false }
			entity.has_ui_progress = present
			if present { entity.ui_progress = shared.ui_progress_default() }
		case .UI_Text:
			if entity.has_ui_text == present { return false }
			entity.has_ui_text = present
			if present { entity.ui_text = shared.ui_text_default() }
		case .UI_Button:
			if entity.has_ui_button == present { return false }
			entity.has_ui_button = present
			if present { entity.ui_button = shared.ui_button_default() }
		case .UI_Input:
			if entity.has_ui_input == present { return false }
			entity.has_ui_input = present
			if present { entity.ui_input = shared.ui_input_default() }
		case .UI_Checkbox:
			if entity.has_ui_checkbox == present { return false }
			entity.has_ui_checkbox = present
			if present { entity.ui_checkbox = shared.ui_checkbox_default() }
	}
	return true
}

set_snapshot_registered_component :: proc(
	entity: ^shared.Scene_Entity,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if entity == nil || definition == nil {
		return false
	}
	if builtin, found := editor_authoring_component_from_name(definition.name); found {
		return set_snapshot_component(entity, builtin, present)
	}
	found_index := -1
	for custom, index in entity.custom_components {
		if custom.name == definition.name {
			found_index = index
			break
		}
	}
	if (found_index >= 0) == present {
		return false
	}
	if present {
		value: shared.Custom_Component
		value.component_id = definition.id
		value.name = ecs.clone_snapshot_string(definition.name)
		for field in definition.fields[:definition.field_count] {
			append(
				&value.vec3_fields,
				shared.Named_Vec3{name = ecs.clone_snapshot_string(field.name)},
			)
		}
		append(&entity.custom_components, value)
		return true
	}
	value := &entity.custom_components[found_index]
	delete(value.name)
	for field in value.vec3_fields {
		delete(field.name)
	}
	delete(value.vec3_fields)
	ordered_remove(&entity.custom_components, found_index)
	return true
}
