package ecs

import resources "../resources"
import shared "../shared"
import "core:fmt"

WORLD_INTEGRITY_CHECKS :: #config(SCRAPBOT_WORLD_INTEGRITY_CHECKS, false)

World_Integrity_Code :: enum {
	None,
	Entity_Identity,
	Entity_UUID_Map,
	Component_Index,
	Component_Aliasing,
	Free_Slot,
	Active_Set,
	Dirty_Queue,
	Custom_Component,
	Editor_Back_Reference,
	UI_Hierarchy,
	Resource_Reference,
	Render_List,
}

World_Integrity_Failure :: struct {
	code: World_Integrity_Code,
	entity_index: int,
	related_index: int,
	message: string,
}

@(private)
World_Component_Kind :: enum {
	Transform,
	Camera,
	Ambient_Light,
	Directional_Light,
	Point_Light,
	Mesh,
	Geometry,
	Material,
	Render_Instance,
	UI_Layout,
	UI_HStack,
	UI_VStack,
	UI_Scroll_Area,
	UI_Panel,
	UI_Table,
	UI_List,
	UI_Progress,
	UI_State,
	UI_Text,
	UI_Button,
	UI_Input,
	UI_Checkbox,
	Editor_Transform_Gizmo,
	Editor_UI,
}

@(private)
World_Component_Slot :: struct {
	kind: World_Component_Kind,
	index: int,
	capacity: int,
}

@(private)
World_Component_Slot_Key :: struct {
	kind: World_Component_Kind,
	index: int,
}

@(private)
World_Active_Set_Kind :: enum {
	Render,
	Camera,
	Ambient_Light,
	Directional_Light,
	Point_Light,
}

@(private)
world_integrity_ok :: proc() -> (World_Integrity_Failure, bool) {
	return {}, true
}

@(private)
world_integrity_failure :: proc(
	code: World_Integrity_Code,
	entity_index, related_index: int,
	message: string,
) -> (
	World_Integrity_Failure,
	bool,
) {
	return {
			code = code,
			entity_index = entity_index,
			related_index = related_index,
			message = message,
		},
		false
}

format_world_integrity_failure :: proc(failure: World_Integrity_Failure) -> string {
	if failure.code == .None {
		return ""
	}
	return fmt.tprintf(
		"WORLD_%s entity=%d related=%d: %s",
		failure.code,
		failure.entity_index,
		failure.related_index,
		failure.message,
	)
}

@(private)
world_entity_component_slots :: proc(
	world: ^World,
	entity: World_Entity,
) -> [24]World_Component_Slot {
	return {
		{.Transform, entity.transform_index, len(world.transforms)},
		{.Camera, entity.camera_index, len(world.cameras)},
		{.Ambient_Light, entity.ambient_light_index, len(world.ambient_lights)},
		{.Directional_Light, entity.directional_light_index, len(world.directional_lights)},
		{.Point_Light, entity.point_light_index, len(world.point_lights)},
		{.Mesh, entity.mesh_index, len(world.meshes)},
		{.Geometry, entity.geometry_index, len(world.geometries)},
		{.Material, entity.material_index, len(world.materials)},
		{.Render_Instance, entity.render_instance_index, len(world.render_instances)},
		{.UI_Layout, entity.ui_layout_index, len(world.ui_layouts)},
		{.UI_HStack, entity.ui_hstack_index, len(world.ui_hstacks)},
		{.UI_VStack, entity.ui_vstack_index, len(world.ui_vstacks)},
		{.UI_Scroll_Area, entity.ui_scroll_area_index, len(world.ui_scroll_areas)},
		{.UI_Panel, entity.ui_panel_index, len(world.ui_panels)},
		{.UI_Table, entity.ui_table_index, len(world.ui_tables)},
		{.UI_List, entity.ui_list_index, len(world.ui_lists)},
		{.UI_Progress, entity.ui_progress_index, len(world.ui_progresses)},
		{.UI_State, entity.ui_state_index, len(world.ui_states)},
		{.UI_Text, entity.ui_text_index, len(world.ui_texts)},
		{.UI_Button, entity.ui_button_index, len(world.ui_buttons)},
		{.UI_Input, entity.ui_input_index, len(world.ui_inputs)},
		{.UI_Checkbox, entity.ui_checkbox_index, len(world.ui_checkboxes)},
		{
			.Editor_Transform_Gizmo,
			entity.editor_transform_gizmo_index,
			len(world.editor_transform_gizmos),
		},
		{.Editor_UI, entity.editor_ui_index, len(world.editor_uis)},
	}
}

@(private)
world_active_index :: proc(entity: World_Entity, kind: World_Active_Set_Kind) -> int {
	switch kind {
		case .Render:
			return entity.render_active_index
		case .Camera:
			return entity.render_camera_active_index
		case .Ambient_Light:
			return entity.render_ambient_light_active_index
		case .Directional_Light:
			return entity.render_directional_light_active_index
		case .Point_Light:
			return entity.render_point_light_active_index
	}
	return INVALID_COMPONENT_INDEX
}

@(private)
world_active_membership_is_valid :: proc(
	world: ^World,
	entity_index: int,
	kind: World_Active_Set_Kind,
) -> bool {
	entity := world.entities[entity_index]
	switch kind {
		case .Render:
			return(
				entity.render_instance_index >= 0 &&
				entity.render_instance_index < len(world.render_instances) &&
				entity.transform_index >= 0 &&
				entity.transform_index < len(world.transforms) \
			)
		case .Camera:
			return(
				entity.camera_index >= 0 &&
				entity.camera_index < len(world.cameras) &&
				entity.transform_index >= 0 &&
				entity.transform_index < len(world.transforms) \
			)
		case .Ambient_Light:
			return(
				entity.ambient_light_index >= 0 &&
				entity.ambient_light_index < len(world.ambient_lights) \
			)
		case .Directional_Light:
			return(
				entity.directional_light_index >= 0 &&
				entity.directional_light_index < len(world.directional_lights) \
			)
		case .Point_Light:
			return(
				entity.point_light_index >= 0 &&
				entity.point_light_index < len(world.point_lights) &&
				entity.transform_index >= 0 &&
				entity.transform_index < len(world.transforms) \
			)
	}
	return false
}

@(private)
validate_world_active_set :: proc(
	world: ^World,
	entities: []int,
	kind: World_Active_Set_Kind,
) -> (
	World_Integrity_Failure,
	bool,
) {
	for entity_index, active_index in entities {
		if !entity_is_alive(world, entity_index) {
			return world_integrity_failure(
				.Active_Set,
				entity_index,
				active_index,
				fmt.tprintf("%s active set references a dead or missing entity", kind),
			)
		}
		if world_active_index(world.entities[entity_index], kind) != active_index {
			return world_integrity_failure(
				.Active_Set,
				entity_index,
				active_index,
				fmt.tprintf("%s active-set reverse index disagrees", kind),
			)
		}
		if !world_active_membership_is_valid(world, entity_index, kind) &&
		   !world.entities[entity_index].render_dirty {
			return world_integrity_failure(
				.Active_Set,
				entity_index,
				active_index,
				fmt.tprintf("%s active-set entity lacks its required components", kind),
			)
		}
	}
	for entity, entity_index in world.entities {
		active_index := world_active_index(entity, kind)
		if active_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if active_index < 0 || active_index >= len(entities) {
			return world_integrity_failure(
				.Active_Set,
				entity_index,
				active_index,
				fmt.tprintf("%s reverse index is out of range", kind),
			)
		}
		if entities[active_index] != entity_index {
			return world_integrity_failure(
				.Active_Set,
				entity_index,
				active_index,
				fmt.tprintf("%s reverse index points at another entity", kind),
			)
		}
	}
	return world_integrity_ok()
}

@(private)
validate_world_dirty_queue :: proc(
	world: ^World,
	entities: []int,
	render: bool,
	extract: bool = false,
	transform: bool = false,
) -> (
	World_Integrity_Failure,
	bool,
) {
	seen := make(map[int]bool)
	defer delete(seen)
	for entity_index, queue_index in entities {
		if entity_index < 0 || entity_index >= len(world.entities) {
			return world_integrity_failure(
				.Dirty_Queue,
				entity_index,
				queue_index,
				"dirty queue contains an out-of-range entity",
			)
		}
		if seen[entity_index] {
			return world_integrity_failure(
				.Dirty_Queue,
				entity_index,
				queue_index,
				"dirty queue contains the same entity more than once",
			)
		}
		seen[entity_index] = true
		entity := world.entities[entity_index]
		dirty := entity.ui_dirty
		if transform {
			dirty = entity.render_transform_dirty
		} else if extract {
			dirty = entity.render_extract_dirty
		} else if render {
			dirty = entity.render_dirty
		}
		if !dirty {
			return world_integrity_failure(
				.Dirty_Queue,
				entity_index,
				queue_index,
				"dirty queue contains an entity that is no longer marked dirty",
			)
		}
	}
	for entity, entity_index in world.entities {
		dirty := entity.ui_dirty
		if transform {
			dirty = entity.render_transform_dirty
		} else if extract {
			dirty = entity.render_extract_dirty
		} else if render {
			dirty = entity.render_dirty
		}
		if dirty && !seen[entity_index] {
			return world_integrity_failure(
				.Dirty_Queue,
				entity_index,
				INVALID_COMPONENT_INDEX,
				"entity is marked dirty but is absent from its queue",
			)
		}
	}
	return world_integrity_ok()
}

validate_render_list_integrity :: proc(
	world: ^World,
	list: ^Render_List,
) -> (
	World_Integrity_Failure,
	bool,
) {
	if world == nil || list == nil {
		return world_integrity_failure(
			.Render_List,
			INVALID_COMPONENT_INDEX,
			INVALID_COMPONENT_INDEX,
			"render-list state is unavailable",
		)
	}
	if !list.structure_initialized || list.world_uuid != world.instance_uuid {
		return world_integrity_failure(
			.Render_List,
			INVALID_COMPONENT_INDEX,
			INVALID_COMPONENT_INDEX,
			"render list is not initialized for the current world",
		)
	}
	if list.instance_slot_count != len(world.render_instances) {
		return world_integrity_failure(
			.Render_List,
			INVALID_COMPONENT_INDEX,
			list.instance_slot_count,
			"render-list slot count disagrees with world storage",
		)
	}
	for instance, list_index in list.instances {
		entity_index := int(instance.entity.id.index)
		if !entity_is_current(world, entity_index, instance.entity.id.generation) {
			return world_integrity_failure(
				.Render_List,
				entity_index,
				list_index,
				"render list retains a dead or stale entity generation",
			)
		}
		if instance.slot < 0 || instance.slot >= len(list.instance_index_by_slot) {
			return world_integrity_failure(
				.Render_List,
				entity_index,
				instance.slot,
				"render-list instance slot is out of range",
			)
		}
		if entity_index >= len(list.instance_index_by_entity) ||
		   list.instance_index_by_entity[entity_index] != list_index ||
		   list.instance_index_by_slot[instance.slot] != list_index ||
		   world.entities[entity_index].render_instance_index != instance.slot {
			return world_integrity_failure(
				.Render_List,
				entity_index,
				instance.slot,
				"render-list owner and reverse indices disagree",
			)
		}
	}
	for list_index, entity_index in list.instance_index_by_entity {
		if list_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if list_index < 0 ||
		   list_index >= len(list.instances) ||
		   int(list.instances[list_index].entity.id.index) != entity_index {
			return world_integrity_failure(
				.Render_List,
				entity_index,
				list_index,
				"render-list entity reverse index is stale",
			)
		}
	}
	for list_index, slot in list.instance_index_by_slot {
		if list_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if list_index < 0 ||
		   list_index >= len(list.instances) ||
		   list.instances[list_index].slot != slot {
			return world_integrity_failure(
				.Render_List,
				INVALID_COMPONENT_INDEX,
				slot,
				"render-list slot reverse index is stale",
			)
		}
	}
	return world_integrity_ok()
}

@(private)
validate_world_free_slots :: proc(
	free_slots: []int,
	capacity: int,
	kind: World_Component_Kind,
	claims: map[World_Component_Slot_Key]int,
) -> (
	World_Integrity_Failure,
	bool,
) {
	seen := make(map[int]bool)
	defer delete(seen)
	for slot, free_index in free_slots {
		if slot < 0 || slot >= capacity {
			return world_integrity_failure(
				.Free_Slot,
				INVALID_COMPONENT_INDEX,
				slot,
				fmt.tprintf("%s free slot is out of range", kind),
			)
		}
		if seen[slot] {
			return world_integrity_failure(
				.Free_Slot,
				INVALID_COMPONENT_INDEX,
				slot,
				fmt.tprintf("%s free slot appears more than once", kind),
			)
		}
		key := World_Component_Slot_Key {
			kind = kind,
			index = slot,
		}
		if owner, found := claims[key]; found {
			return world_integrity_failure(
				.Free_Slot,
				owner,
				slot,
				fmt.tprintf("%s free slot is still claimed by a live entity", kind),
			)
		}
		seen[slot] = true
		_ = free_index
	}
	return world_integrity_ok()
}

@(private)
validate_world_resource_references :: proc(
	world: ^World,
	registry: ^resources.Registry,
) -> (
	World_Integrity_Failure,
	bool,
) {
	if registry == nil {
		return world_integrity_ok()
	}
	for entity, entity_index in world.entities {
		if !entity.alive {
			continue
		}
		if entity.geometry_index >= 0 {
			_, alive := resources.get_geometry(
				registry,
				world.geometries[entity.geometry_index].handle,
			)
			if !alive {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.geometry_index,
					"geometry component contains a stale runtime handle",
				)
			}
		}
		if entity.geometry_resource != "" {
			expected, found := resources.geometry_by_name(registry, entity.geometry_resource)
			if resource_id, valid := shared.resource_uuid_parse(entity.geometry_resource); valid {
				expected, found = resources.geometry_by_uuid(registry, resource_id)
			}
			if !found {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.geometry_index,
					"authored geometry resource is unresolved",
				)
			}
			if entity.geometry_index >= 0 &&
			   world.geometries[entity.geometry_index].handle != expected {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.geometry_index,
					"authored geometry UUID/name and runtime handle disagree",
				)
			}
		}
		if entity.material_index >= 0 {
			_, alive := resources.get_material(
				registry,
				world.materials[entity.material_index].handle,
			)
			if !alive {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.material_index,
					"material component contains a stale runtime handle",
				)
			}
		}
		if entity.material_resource != "" {
			resource_id, valid := shared.resource_uuid_parse(entity.material_resource)
			if !valid {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.material_index,
					"authored material reference is not a UUID",
				)
			}
			expected, found := resources.material_by_uuid(registry, resource_id)
			if !found {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.material_index,
					"authored material resource is unresolved",
				)
			}
			if entity.material_index >= 0 &&
			   world.materials[entity.material_index].handle != expected {
				return world_integrity_failure(
					.Resource_Reference,
					entity_index,
					entity.material_index,
					"authored material UUID and runtime handle disagree",
				)
			}
		}
	}
	return world_integrity_ok()
}

validate_world_integrity :: proc(
	world: ^World,
	registry: ^resources.Registry = nil,
) -> (
	World_Integrity_Failure,
	bool,
) {
	if world == nil {
		return world_integrity_failure(
			.Entity_Identity,
			INVALID_COMPONENT_INDEX,
			INVALID_COMPONENT_INDEX,
			"world is unavailable",
		)
	}
	claims := make(map[World_Component_Slot_Key]int)
	defer delete(claims)
	live_count := 0
	for entity, entity_index in world.entities {
		if int(entity.id.index) != entity_index || entity.id.generation == 0 {
			return world_integrity_failure(
				.Entity_Identity,
				entity_index,
				int(entity.id.index),
				"entity handle does not identify its storage slot and generation",
			)
		}
		slots := world_entity_component_slots(world, entity)
		if !entity.alive {
			if entity.uuid != (shared.Entity_UUID{}) || entity.name != "" {
				return world_integrity_failure(
					.Entity_Identity,
					entity_index,
					INVALID_COMPONENT_INDEX,
					"dead entity retains UUID or name identity",
				)
			}
			for slot in slots {
				if slot.index != INVALID_COMPONENT_INDEX {
					return world_integrity_failure(
						.Component_Index,
						entity_index,
						slot.index,
						fmt.tprintf("dead entity retains %s component membership", slot.kind),
					)
				}
			}
			continue
		}
		live_count += 1
		if entity.uuid == (shared.Entity_UUID{}) || entity.component_revision == 0 {
			return world_integrity_failure(
				.Entity_Identity,
				entity_index,
				INVALID_COMPONENT_INDEX,
				"live entity lacks stable UUID or component revision",
			)
		}
		mapped_index, found := world.entity_by_uuid[entity.uuid]
		if !found || mapped_index != entity_index {
			return world_integrity_failure(
				.Entity_UUID_Map,
				entity_index,
				mapped_index,
				"live entity UUID map entry is missing or points elsewhere",
			)
		}
		for slot in slots {
			if slot.index == INVALID_COMPONENT_INDEX {
				continue
			}
			if slot.index < 0 || slot.index >= slot.capacity {
				return world_integrity_failure(
					.Component_Index,
					entity_index,
					slot.index,
					fmt.tprintf("%s component index is out of range", slot.kind),
				)
			}
			key := World_Component_Slot_Key {
				kind = slot.kind,
				index = slot.index,
			}
			if owner, claimed := claims[key]; claimed {
				return world_integrity_failure(
					.Component_Aliasing,
					entity_index,
					owner,
					fmt.tprintf("%s component slot is claimed by two entities", slot.kind),
				)
			}
			claims[key] = entity_index
		}
	}
	if len(world.entity_by_uuid) != live_count {
		return world_integrity_failure(
			.Entity_UUID_Map,
			INVALID_COMPONENT_INDEX,
			len(world.entity_by_uuid),
			"UUID map size differs from the live entity count",
		)
	}
	for id, entity_index in world.entity_by_uuid {
		if !entity_is_alive(world, entity_index) || world.entities[entity_index].uuid != id {
			return world_integrity_failure(
				.Entity_UUID_Map,
				entity_index,
				INVALID_COMPONENT_INDEX,
				"UUID map contains a stale or mismatched entry",
			)
		}
	}

	free_sets := []struct {
		slots: []int,
		capacity: int,
		kind: World_Component_Kind,
	} {
		{world.free_transform_indices[:], len(world.transforms), .Transform},
		{world.free_mesh_indices[:], len(world.meshes), .Mesh},
		{world.free_geometry_indices[:], len(world.geometries), .Geometry},
		{world.free_material_indices[:], len(world.materials), .Material},
		{world.free_render_instance_indices[:], len(world.render_instances), .Render_Instance},
		{world.free_ui_layout_indices[:], len(world.ui_layouts), .UI_Layout},
		{world.free_ui_hstack_indices[:], len(world.ui_hstacks), .UI_HStack},
		{world.free_ui_vstack_indices[:], len(world.ui_vstacks), .UI_VStack},
		{world.free_ui_scroll_area_indices[:], len(world.ui_scroll_areas), .UI_Scroll_Area},
		{world.free_ui_panel_indices[:], len(world.ui_panels), .UI_Panel},
		{world.free_ui_table_indices[:], len(world.ui_tables), .UI_Table},
		{world.free_ui_list_indices[:], len(world.ui_lists), .UI_List},
		{world.free_ui_progress_indices[:], len(world.ui_progresses), .UI_Progress},
		{world.free_ui_state_indices[:], len(world.ui_states), .UI_State},
		{world.free_ui_text_indices[:], len(world.ui_texts), .UI_Text},
		{world.free_ui_button_indices[:], len(world.ui_buttons), .UI_Button},
		{world.free_ui_input_indices[:], len(world.ui_inputs), .UI_Input},
		{world.free_ui_checkbox_indices[:], len(world.ui_checkboxes), .UI_Checkbox},
	}
	for free_set in free_sets {
		if failure, ok := validate_world_free_slots(
			free_set.slots,
			free_set.capacity,
			free_set.kind,
			claims,
		); !ok {
			return failure, false
		}
	}

	active_sets := []struct {
		entities: []int,
		kind: World_Active_Set_Kind,
	} {
		{world.render_active_entities[:], .Render},
		{world.render_active_camera_entities[:], .Camera},
		{world.render_active_ambient_light_entities[:], .Ambient_Light},
		{world.render_active_directional_light_entities[:], .Directional_Light},
		{world.render_active_point_light_entities[:], .Point_Light},
	}
	for active_set in active_sets {
		if failure, ok := validate_world_active_set(world, active_set.entities, active_set.kind);
		   !ok {
			return failure, false
		}
	}
	if failure, ok := validate_world_dirty_queue(world, world.render_dirty_entities[:], true);
	   !ok {
		return failure, false
	}
	if failure, ok := validate_world_dirty_queue(
		world,
		world.render_extract_dirty_entities[:],
		true,
		true,
	); !ok {
		return failure, false
	}
	if failure, ok := validate_world_dirty_queue(
		world,
		world.render_transform_dirty_entities[:],
		true,
		false,
		true,
	); !ok {
		return failure, false
	}
	if failure, ok := validate_world_dirty_queue(world, world.ui_dirty_entities[:], false); !ok {
		return failure, false
	}

	for renderable, renderable_index in world.renderables {
		if renderable.entity_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if !entity_is_alive(world, renderable.entity_index) {
			return world_integrity_failure(
				.Component_Index,
				renderable.entity_index,
				renderable_index,
				"renderable references a dead or missing entity",
			)
		}
		entity := world.entities[renderable.entity_index]
		if entity.transform_index != renderable.transform_index ||
		   entity.mesh_index != renderable.mesh_index {
			return world_integrity_failure(
				.Component_Index,
				renderable.entity_index,
				renderable_index,
				"renderable component indexes disagree with its entity",
			)
		}
	}
	for component, component_index in world.editor_transform_gizmos {
		if component.entity_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if !entity_is_alive(world, component.entity_index) ||
		   world.entities[component.entity_index].editor_transform_gizmo_index != component_index {
			return world_integrity_failure(
				.Editor_Back_Reference,
				component.entity_index,
				component_index,
				"transform gizmo does not agree with its entity",
			)
		}
	}
	for component, component_index in world.editor_uis {
		if component.entity_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if !entity_is_alive(world, component.entity_index) ||
		   world.entities[component.entity_index].editor_ui_index != component_index {
			return world_integrity_failure(
				.Editor_Back_Reference,
				component.entity_index,
				component_index,
				"editor UI binding does not agree with its entity",
			)
		}
	}
	for component, component_index in world.editor_scene_cameras {
		if component.entity_index == INVALID_COMPONENT_INDEX {
			continue
		}
		if !entity_is_alive(world, component.entity_index) {
			return world_integrity_failure(
				.Editor_Back_Reference,
				component.entity_index,
				component_index,
				"editor scene camera references a dead entity",
			)
		}
		entity := world.entities[component.entity_index]
		if entity.origin != .Editor || entity.transform_index < 0 || entity.camera_index < 0 {
			return world_integrity_failure(
				.Editor_Back_Reference,
				component.entity_index,
				component_index,
				"editor scene camera entity lacks its required components",
			)
		}
	}
	for storage, storage_index in world.custom_components {
		if storage.storage_index != storage_index {
			return world_integrity_failure(
				.Custom_Component,
				-1,
				storage_index,
				"custom component storage index does not match its world slot",
			)
		}
		seen_entities := make(map[int]bool)
		defer delete(seen_entities)
		for component, component_index in storage.components {
			if component.entity_index == INVALID_COMPONENT_INDEX {
				continue
			}
			if !entity_is_alive(world, component.entity_index) ||
			   component.component_id != storage.component_id ||
			   component.name != storage.name ||
			   seen_entities[component.entity_index] {
				return world_integrity_failure(
					.Custom_Component,
					component.entity_index,
					component_index,
					fmt.tprintf(
						"custom component storage %d has inconsistent membership",
						storage_index,
					),
				)
			}
			seen_entities[component.entity_index] = true
			if component_index >= len(storage.component_active_indices) {
				return world_integrity_failure(
					.Custom_Component,
					component.entity_index,
					component_index,
					"custom component slot omits its dense active index",
				)
			}
			active_index := storage.component_active_indices[component_index]
			if active_index < 0 ||
			   active_index >= len(storage.active_component_indices) ||
			   storage.active_component_indices[active_index] != component_index {
				return world_integrity_failure(
					.Custom_Component,
					component.entity_index,
					component_index,
					"custom component dense active index does not match storage slot",
				)
			}
			if component.entity_index >= len(storage.entity_component_indices) ||
			   storage.entity_component_indices[component.entity_index] != component_index {
				return world_integrity_failure(
					.Custom_Component,
					component.entity_index,
					component_index,
					"custom component reverse index does not match storage slot",
				)
			}
			membership_found := false
			for member_storage_index in world.entities[component.entity_index].custom_component_storage_indices {
				if member_storage_index == storage_index {
					membership_found = true
					break
				}
			}
			if !membership_found {
				return world_integrity_failure(
					.Custom_Component,
					component.entity_index,
					component_index,
					"entity custom component membership omits its storage",
				)
			}
		}
		for component_index, active_index in storage.active_component_indices {
			if component_index < 0 ||
			   component_index >= len(storage.components) ||
			   storage.components[component_index].entity_index == INVALID_COMPONENT_INDEX ||
			   component_index >= len(storage.component_active_indices) ||
			   storage.component_active_indices[component_index] != active_index {
				return world_integrity_failure(
					.Custom_Component,
					-1,
					component_index,
					"custom component active set references an invalid storage slot",
				)
			}
		}
	}
	for entity, entity_index in world.entities {
		for storage_index in entity.custom_component_storage_indices {
			if storage_index < 0 || storage_index >= len(world.custom_components) {
				return world_integrity_failure(
					.Custom_Component,
					entity_index,
					storage_index,
					"entity custom component membership references an invalid storage",
				)
			}
			_, found := custom_component_index_for_entity(
				&world.custom_components[storage_index],
				entity_index,
			)
			if !found {
				return world_integrity_failure(
					.Custom_Component,
					entity_index,
					storage_index,
					"entity custom component membership has no matching component",
				)
			}
		}
	}
	for entity, entity_index in world.entities {
		if !entity.alive || entity.ui_layout_index < 0 {
			continue
		}
		parent := world.ui_layouts[entity.ui_layout_index].parent
		for depth in 0 ..< len(world.entities) {
			if parent == (shared.Entity_UUID{}) {
				break
			}
			parent_index, found := entity_index_by_uuid(world, parent)
			if !found || world.entities[parent_index].ui_layout_index < 0 {
				return world_integrity_failure(
					.UI_Hierarchy,
					entity_index,
					parent_index,
					"UI parent is missing or does not have a layout",
				)
			}
			if parent_index == entity_index {
				return world_integrity_failure(
					.UI_Hierarchy,
					entity_index,
					parent_index,
					"UI hierarchy contains a cycle",
				)
			}
			parent = world.ui_layouts[world.entities[parent_index].ui_layout_index].parent
			_ = depth
		}
		if parent != (shared.Entity_UUID{}) {
			return world_integrity_failure(
				.UI_Hierarchy,
				entity_index,
				INVALID_COMPONENT_INDEX,
				"UI hierarchy exceeds the entity count and therefore contains a cycle",
			)
		}
	}
	return validate_world_resource_references(world, registry)
}
