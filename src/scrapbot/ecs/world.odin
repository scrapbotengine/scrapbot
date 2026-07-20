package ecs

import resources "../resources"
import shared "../shared"
import runtime "base:runtime"
import "core:strings"

Scene :: shared.Scene
World :: shared.World
World_Entity :: shared.World_Entity
Entity :: shared.Entity
Entity_UUID :: shared.Entity_UUID
Entity_Origin :: shared.Entity_Origin
Render_Frame :: shared.Render_Frame
Renderable :: shared.Renderable
Render_Instance :: shared.Render_Instance
Camera_Instance :: shared.Camera_Instance
Render_List :: shared.Render_List
Custom_Component :: shared.Custom_Component
Custom_Component_Storage :: shared.Custom_Component_Storage
Component_ID :: shared.Component_ID
Vec2 :: shared.Vec2
Vec3 :: shared.Vec3
Vec4 :: shared.Vec4
Named_Number :: shared.Named_Number
Named_Vec2 :: shared.Named_Vec2
Named_Vec3 :: shared.Named_Vec3
Named_Vec4 :: shared.Named_Vec4
Transform_Component :: shared.Transform_Component
Mesh_Component :: shared.Mesh_Component
Geometry_Component :: shared.Geometry_Component
Material_Component :: shared.Material_Component
Render_Instance_Component :: shared.Render_Instance_Component
Geometry_Handle :: shared.Geometry_Handle
Material_Handle :: shared.Material_Handle
Ambient_Light_Component :: shared.Ambient_Light_Component
Directional_Light_Component :: shared.Directional_Light_Component
Point_Light_Component :: shared.Point_Light_Component
UI_Layout_Component :: shared.UI_Layout_Component
UI_Stack_Component :: shared.UI_Stack_Component
UI_Scroll_Area_Component :: shared.UI_Scroll_Area_Component
UI_Panel_Component :: shared.UI_Panel_Component
UI_Table_Component :: shared.UI_Table_Component
UI_List_Component :: shared.UI_List_Component
UI_Progress_Component :: shared.UI_Progress_Component
UI_State_Component :: shared.UI_State_Component
UI_Text_Component :: shared.UI_Text_Component
UI_Button_Component :: shared.UI_Button_Component
UI_Input_Component :: shared.UI_Input_Component
UI_Checkbox_Component :: shared.UI_Checkbox_Component

INVALID_COMPONENT_INDEX :: -1
MAX_QUERY_TERMS :: 8

init_world_entity :: proc(
	world: ^World,
	entity_index: int,
	generation: u32,
	uuid: Entity_UUID,
	origin: Entity_Origin,
	name: string,
) -> World_Entity {
	return {
		id = {index = u32(entity_index), generation = generation},
		uuid = uuid,
		alive = true,
		origin = origin,
		name = clone_world_string(world, name),
		component_revision = 1,
		transform_index = INVALID_COMPONENT_INDEX,
		camera_index = INVALID_COMPONENT_INDEX,
		ambient_light_index = INVALID_COMPONENT_INDEX,
		directional_light_index = INVALID_COMPONENT_INDEX,
		point_light_index = INVALID_COMPONENT_INDEX,
		mesh_index = INVALID_COMPONENT_INDEX,
		geometry_index = INVALID_COMPONENT_INDEX,
		material_index = INVALID_COMPONENT_INDEX,
		render_instance_index = INVALID_COMPONENT_INDEX,
		render_active_index = INVALID_COMPONENT_INDEX,
		render_camera_active_index = INVALID_COMPONENT_INDEX,
		render_ambient_light_active_index = INVALID_COMPONENT_INDEX,
		render_directional_light_active_index = INVALID_COMPONENT_INDEX,
		render_point_light_active_index = INVALID_COMPONENT_INDEX,
		ui_layout_index = INVALID_COMPONENT_INDEX,
		ui_hstack_index = INVALID_COMPONENT_INDEX,
		ui_vstack_index = INVALID_COMPONENT_INDEX,
		ui_scroll_area_index = INVALID_COMPONENT_INDEX,
		ui_panel_index = INVALID_COMPONENT_INDEX,
		ui_table_index = INVALID_COMPONENT_INDEX,
		ui_list_index = INVALID_COMPONENT_INDEX,
		ui_progress_index = INVALID_COMPONENT_INDEX,
		ui_state_index = INVALID_COMPONENT_INDEX,
		ui_text_index = INVALID_COMPONENT_INDEX,
		ui_button_index = INVALID_COMPONENT_INDEX,
		ui_input_index = INVALID_COMPONENT_INDEX,
		ui_checkbox_index = INVALID_COMPONENT_INDEX,
		editor_transform_gizmo_index = INVALID_COMPONENT_INDEX,
		editor_ui_index = INVALID_COMPONENT_INDEX,
	}
}

@(private)
coalesce_dirty_entity_entries :: proc(entries: ^[dynamic]int, entity_index: int) -> bool {
	if entries == nil {
		return false
	}
	found := false
	entry_index := 0
	for entry_index < len(entries^) {
		if entries^[entry_index] != entity_index {
			entry_index += 1
			continue
		}
		if !found {
			found = true
			entry_index += 1
			continue
		}
		unordered_remove(entries, entry_index)
	}
	return found
}

create_world_entity :: proc(
	world: ^World,
	name: string,
	uuid: Entity_UUID = {},
	origin: Entity_Origin = .Runtime,
	reuse_dead_slot: bool = true,
) -> (
	entity_index: int,
	ok: bool,
) {
	if world == nil {
		return -1, false
	}
	if world.string_allocator.procedure == nil {
		world.string_allocator = runtime.heap_allocator()
	}
	if world.entity_by_uuid == nil {
		world.entity_by_uuid = make(map[Entity_UUID]int)
	}
	entity_uuid := uuid
	if entity_uuid == (Entity_UUID{}) {
		entity_uuid = shared.entity_uuid_generate()
		for {
			if _, found := world.entity_by_uuid[entity_uuid]; !found {
				break
			}
			entity_uuid = shared.entity_uuid_generate()
		}
	} else if _, found := world.entity_by_uuid[entity_uuid]; found {
		return -1, false
	}

	entity_index = len(world.entities)
	generation := u32(1)
	reusing_slot := false
	if reuse_dead_slot && len(world.free_entity_indices) > 0 {
		entity_index = pop(&world.free_entity_indices)
		if entity_index >= 0 && entity_index < len(world.entities) {
			generation = world.entities[entity_index].id.generation
			reusing_slot = true
		} else {
			entity_index = len(world.entities)
		}
	}
	entity := init_world_entity(world, entity_index, generation, entity_uuid, origin, name)
	entity.scene_order = next_scene_order_index(world)
	if reusing_slot {
		entity.custom_component_storage_indices =
			world.entities[entity_index].custom_component_storage_indices
		clear(&entity.custom_component_storage_indices)
		entity.render_dirty = coalesce_dirty_entity_entries(
			&world.render_dirty_entities,
			entity_index,
		)
		entity.render_extract_dirty = coalesce_dirty_entity_entries(
			&world.render_extract_dirty_entities,
			entity_index,
		)
		entity.ui_dirty = coalesce_dirty_entity_entries(&world.ui_dirty_entities, entity_index)
		world.entities[entity_index] = entity
	} else {
		append(&world.entities, entity)
	}
	world.entity_by_uuid[entity_uuid] = entity_index
	return entity_index, true
}

Query_View :: struct {
	storage: ^Custom_Component_Storage,
}

Query_Term :: struct {
	component_id: Component_ID,
	name: string,
}

Query :: struct {
	terms: [MAX_QUERY_TERMS]Query_Term,
	term_count: int,
}

World_Storage_Stats :: struct {
	live_entities: int,
	entity_slots: int,
	transform_slots: int,
	camera_slots: int,
	ambient_light_slots: int,
	directional_light_slots: int,
	point_light_slots: int,
	mesh_slots: int,
	renderable_slots: int,
	geometry_slots: int,
	material_slots: int,
	render_instance_slots: int,
	ui_layout_slots: int,
	ui_hstack_slots: int,
	ui_vstack_slots: int,
	ui_scroll_area_slots: int,
	ui_panel_slots: int,
	ui_table_slots: int,
	ui_list_slots: int,
	ui_progress_slots: int,
	ui_state_slots: int,
	ui_text_slots: int,
	ui_button_slots: int,
	ui_input_slots: int,
	ui_checkbox_slots: int,
	editor_transform_gizmo_slots: int,
	editor_scene_camera_slots: int,
	editor_ui_slots: int,
	custom_component_storages: int,
	custom_component_slots: int,
	total_component_slots: int,
}

destroy_world :: proc(world: ^World) {
	for entity in world.entities {
		delete_world_string(world, entity.name)
		delete_world_string(world, entity.geometry_resource)
		delete_world_string(world, entity.material_resource)
		delete(entity.custom_component_storage_indices)
	}
	for mesh in world.meshes {
		delete_world_string(world, mesh.primitive)
	}
	for panel in world.ui_panels { delete_world_string(world, panel.title); delete_world_string(world, panel.font) }
	for text in world.ui_texts { delete_world_string(world, text.text); delete_world_string(world, text.font) }
	for button in world.ui_buttons { delete_world_string(world, button.text); delete_world_string(world, button.font) }
	for input in world.ui_inputs {
		delete_world_string(world, input.text)
		delete_world_string(world, input.font)
		delete_world_string(world, input.prefix)
	}
	for &storage in world.custom_components {
		delete_world_string(world, storage.name)
		for &component in storage.components {
			delete_world_string(world, component.name)
			for field in component.number_fields { delete_world_string(world, field.name) }
			for field in component.vec2_fields { delete_world_string(world, field.name) }
			for field in component.vec3_fields {
				delete_world_string(world, field.name)
			}
			for field in component.vec4_fields { delete_world_string(world, field.name) }
			delete(component.number_fields)
			delete(component.vec2_fields)
			delete(component.vec3_fields)
			delete(component.vec4_fields)
		}
		delete(storage.components)
		delete(storage.entity_component_indices)
		delete(storage.active_component_indices)
		delete(storage.component_active_indices)
	}
	delete(world.entities)
	delete(world.free_entity_indices)
	delete(world.entity_by_uuid)
	delete(world.transforms)
	delete(world.cameras)
	delete(world.ambient_lights)
	delete(world.directional_lights)
	delete(world.point_lights)
	delete(world.meshes)
	delete(world.renderables)
	delete(world.geometries)
	delete(world.materials)
	delete(world.render_instances)
	delete(world.render_active_entities)
	delete(world.render_active_camera_entities)
	delete(world.render_active_ambient_light_entities)
	delete(world.render_active_directional_light_entities)
	delete(world.render_active_point_light_entities)
	delete(world.render_dirty_entities)
	delete(world.render_extract_dirty_entities)
	delete(world.free_transform_indices)
	delete(world.resolved_world_transforms)
	delete(world.resolved_world_transform_epochs)
	delete(world.resolved_world_transform_valid)
	delete(world.resolving_world_transform_epochs)
	delete(world.free_mesh_indices)
	delete(world.free_geometry_indices)
	delete(world.free_material_indices)
	delete(world.free_render_instance_indices)
	delete(world.ui_layouts)
	delete(world.ui_hstacks)
	delete(world.ui_vstacks)
	delete(world.ui_scroll_areas)
	delete(world.ui_panels)
	delete(world.ui_tables)
	delete(world.ui_lists)
	delete(world.ui_progresses)
	delete(world.ui_states)
	delete(world.ui_transient_state_entities)
	delete(world.ui_texts)
	delete(world.ui_buttons)
	delete(world.ui_inputs)
	delete(world.ui_checkboxes)
	delete(world.free_ui_layout_indices)
	delete(world.free_ui_hstack_indices)
	delete(world.free_ui_vstack_indices)
	delete(world.free_ui_scroll_area_indices)
	delete(world.free_ui_panel_indices)
	delete(world.free_ui_table_indices)
	delete(world.free_ui_list_indices)
	delete(world.free_ui_progress_indices)
	delete(world.free_ui_state_indices)
	delete(world.free_ui_text_indices)
	delete(world.free_ui_button_indices)
	delete(world.free_ui_input_indices)
	delete(world.free_ui_checkbox_indices)
	delete(world.editor_transform_gizmos)
	delete(world.editor_scene_cameras)
	delete(world.editor_uis)
	delete(world.editor_ui_by_role_slot)
	delete(world.custom_components)
	delete(world.ui_dirty_entities)
	world^ = {}
}

build_world :: proc(scene: ^Scene) -> World {
	world: World
	world.string_allocator = runtime.heap_allocator()
	world.instance_uuid = shared.entity_uuid_generate()
	world.entity_by_uuid = make(map[shared.Entity_UUID]int)
	for entity, scene_order in scene.entities {
		id := Entity {
			index = u32(len(world.entities)),
			generation = 1,
		}
		world_entity := init_world_entity(
			&world,
			int(id.index),
			id.generation,
			entity.id,
			.Scene,
			entity.name,
		)
		world_entity.scene_order = scene_order
		world_entity.geometry_resource = clone_world_string(&world, entity.geometry_resource)
		world_entity.material_resource = clone_world_string(&world, entity.material_resource)
		world_entity.has_shadow_caster = entity.has_shadow_caster
		world_entity.has_shadow_receiver = entity.has_shadow_receiver

		if entity.has_transform {
			world_entity.transform_index = len(world.transforms)
			append_soa(&world.transforms, entity.transform)
		}
		if entity.has_camera {
			world_entity.camera_index = len(world.cameras)
			append(&world.cameras, entity.camera)
		}
		if entity.has_ambient_light { world_entity.ambient_light_index = len(world.ambient_lights); append(&world.ambient_lights, entity.ambient_light) }
		if entity.has_directional_light { world_entity.directional_light_index = len(world.directional_lights); append(&world.directional_lights, entity.directional_light) }
		if entity.has_point_light { world_entity.point_light_index = len(world.point_lights); append(&world.point_lights, entity.point_light) }
		if entity.has_ui_layout {
			world_entity.ui_layout_index = len(world.ui_layouts)
			append(&world.ui_layouts, entity.ui_layout)
		}
		if entity.has_ui_hstack { world_entity.ui_hstack_index = len(world.ui_hstacks); append(&world.ui_hstacks, entity.ui_hstack) }
		if entity.has_ui_vstack { world_entity.ui_vstack_index = len(world.ui_vstacks); append(&world.ui_vstacks, entity.ui_vstack) }
		if entity.has_ui_scroll_area { world_entity.ui_scroll_area_index = len(world.ui_scroll_areas); append(&world.ui_scroll_areas, entity.ui_scroll_area) }
		if entity.has_ui_panel { world_entity.ui_panel_index = len(world.ui_panels); panel := entity.ui_panel; panel.title = clone_world_string(&world, panel.title); panel.font = clone_world_string(&world, panel.font); append(&world.ui_panels, panel) }
		if entity.has_ui_table { world_entity.ui_table_index = len(world.ui_tables); append(&world.ui_tables, entity.ui_table) }
		if entity.has_ui_list {
			world_entity.ui_list_index = len(world.ui_lists)
			append(&world.ui_lists, entity.ui_list)
		}
		if entity.has_ui_progress {
			world_entity.ui_progress_index = len(world.ui_progresses)
			append(&world.ui_progresses, entity.ui_progress)
		}
		if entity.has_ui_text { world_entity.ui_text_index = len(world.ui_texts); text := entity.ui_text; text.text = clone_world_string(&world, text.text); text.font = clone_world_string(&world, text.font); append(&world.ui_texts, text) }
		if entity.has_ui_button { world_entity.ui_button_index = len(world.ui_buttons); button := entity.ui_button; button.text = clone_world_string(&world, button.text); button.font = clone_world_string(&world, button.font); append(&world.ui_buttons, button) }
		if entity.has_ui_input {
			world_entity.ui_input_index = len(world.ui_inputs)
			input := entity.ui_input
			input.text = clone_world_string(&world, input.text)
			input.font = clone_world_string(&world, input.font)
			input.prefix = clone_world_string(&world, input.prefix)
			append(&world.ui_inputs, input)
		}
		if entity.has_ui_checkbox { world_entity.ui_checkbox_index = len(world.ui_checkboxes); append(&world.ui_checkboxes, entity.ui_checkbox) }
		if entity.has_mesh {
			world_entity.mesh_index = len(world.meshes)
			mesh := entity.mesh
			mesh.primitive = clone_world_string(&world, entity.mesh.primitive)
			append(&world.meshes, mesh)
		}
		append(&world.entities, world_entity)
		for component in entity.custom_components {
			add_scene_custom_component(&world, int(id.index), component)
		}
		sync_render_watch_memberships(&world, int(id.index))
		if world.entities[len(world.entities) - 1].uuid == (shared.Entity_UUID{}) {
			world.entities[len(world.entities) - 1].uuid = shared.entity_uuid_generate()
		}
		world.entity_by_uuid[world.entities[len(world.entities) - 1].uuid] = int(id.index)
		if world_entity.ui_layout_index >= 0 {
			mark_ui_entity_dirty(&world, int(id.index))
		}
		mark_render_entity_dirty(&world, int(id.index))
		if world_entity.transform_index != INVALID_COMPONENT_INDEX &&
		   world_entity.mesh_index != INVALID_COMPONENT_INDEX {
			append(
				&world.renderables,
				Renderable {
					entity_index = int(id.index),
					transform_index = world_entity.transform_index,
					mesh_index = world_entity.mesh_index,
				},
			)
		}
	}
	return world
}

entity_index_by_uuid :: proc(world: ^World, id: shared.Entity_UUID) -> (int, bool) {
	if world == nil || id == (shared.Entity_UUID{}) || world.entity_by_uuid == nil {
		return -1, false
	}
	index, found := world.entity_by_uuid[id]
	if !found || !entity_is_alive(world, index) || world.entities[index].uuid != id {
		return -1, false
	}
	return index, true
}

mark_ui_structure_changed :: proc(world: ^World) {
	if world == nil {
		return
	}
	world.ui_structure_revision += 1
	if world.ui_structure_revision == 0 {
		world.ui_structure_revision = 1
	}
}

mark_ui_paint_changed :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	revision := &world.ui_project_paint_revision
	if world.entities[entity_index].origin == .Editor {
		revision = &world.ui_editor_paint_revision
	}
	revision^ += 1
	if revision^ == 0 {
		revision^ = 1
	}
}

mark_ui_layout_changed :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	revision := &world.ui_project_layout_revision
	if world.entities[entity_index].origin == .Editor {
		revision = &world.ui_editor_layout_revision
	}
	revision^ += 1
	if revision^ == 0 {
		revision^ = 1
	}
	mark_ui_paint_changed(world, entity_index)
}

mark_ui_intrinsic_layout_changed :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := world.entities[entity_index]
	if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
		return
	}
	layout := world.ui_layouts[entity.ui_layout_index]
	if layout.fit_content_width || layout.fit_content_height {
		mark_ui_layout_changed(world, entity_index)
	}
}

mark_ui_entity_dirty :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := &world.entities[entity_index]
	if !entity.ui_dirty {
		entity.ui_dirty = true
		append(&world.ui_dirty_entities, entity_index)
		mark_ui_structure_changed(world)
		mark_ui_layout_changed(world, entity_index)
	}
}

mark_ui_subtree_dirty :: proc(world: ^World, root_entity_index: int) {
	if world == nil || root_entity_index < 0 || root_entity_index >= len(world.entities) {
		return
	}
	root_uuid := world.entities[root_entity_index].uuid
	mark_ui_entity_dirty(world, root_entity_index)
	if root_uuid == (shared.Entity_UUID{}) {
		return
	}
	for entity, entity_index in world.entities {
		if entity_index == root_entity_index ||
		   entity.ui_layout_index < 0 ||
		   entity.ui_layout_index >= len(world.ui_layouts) {
			continue
		}
		parent := world.ui_layouts[entity.ui_layout_index].parent
		for depth in 0 ..< len(world.entities) {
			if parent == root_uuid {
				mark_ui_entity_dirty(world, entity_index)
				break
			}
			parent_index, found := entity_index_by_uuid(world, parent)
			if !found {
				break
			}
			parent_entity := world.entities[parent_index]
			if parent_entity.ui_layout_index < 0 ||
			   parent_entity.ui_layout_index >= len(world.ui_layouts) {
				break
			}
			parent = world.ui_layouts[parent_entity.ui_layout_index].parent
		}
	}
}

mark_render_entity_dirty :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := &world.entities[entity_index]
	if !entity.render_dirty {
		entity.render_dirty = true
		append(&world.render_dirty_entities, entity_index)
	}
	mark_render_extract_entity_dirty(world, entity_index)
}

mark_render_extract_entity_dirty :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := &world.entities[entity_index]
	if !entity.render_extract_dirty {
		entity.render_extract_dirty = true
		append(&world.render_extract_dirty_entities, entity_index)
	}
}

mark_all_render_entities_dirty :: proc(world: ^World) {
	if world == nil {
		return
	}
	for entity, index in world.entities {
		if entity.alive {
			mark_render_entity_dirty(world, index)
		}
	}
}

take_free_slot :: proc(free_slots: ^[dynamic]int) -> (index: int, found: bool) {
	if len(free_slots^) == 0 {
		return INVALID_COMPONENT_INDEX, false
	}
	index = pop(free_slots)
	return index, true
}

bump_component_revision :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) { return }
	world.entities[entity_index].component_revision += 1
	if world.entities[entity_index].component_revision == 0 {
		world.entities[entity_index].component_revision = 1
	}
}

allocate_transform_slot :: proc(world: ^World, value: Transform_Component) -> int {
	if index, found := take_free_slot(&world.free_transform_indices); found {
		world.transforms[index] = value
		return index
	}
	index := len(world.transforms)
	append_soa(&world.transforms, value)
	return index
}

release_transform_slot :: proc(world: ^World, index: int) {
	if index < 0 || index >= len(world.transforms) { return }
	world.transforms[index] = {}
	append(&world.free_transform_indices, index)
}

allocate_mesh_slot :: proc(world: ^World, primitive: string) -> int {
	mesh := Mesh_Component {
		primitive = clone_world_string(world, primitive),
	}
	if index, found := take_free_slot(&world.free_mesh_indices); found {
		world.meshes[index] = mesh
		return index
	}
	index := len(world.meshes)
	append(&world.meshes, mesh)
	return index
}

release_mesh_slot :: proc(world: ^World, index: int) {
	if index < 0 || index >= len(world.meshes) { return }
	delete_world_string(world, world.meshes[index].primitive)
	world.meshes[index] = {}
	append(&world.free_mesh_indices, index)
}

allocate_geometry_slot :: proc(world: ^World, value: Geometry_Component) -> int {
	if index, found := take_free_slot(&world.free_geometry_indices); found {
		world.geometries[index] = value
		return index
	}
	index := len(world.geometries)
	append(&world.geometries, value)
	return index
}

release_geometry_slot :: proc(world: ^World, index: int) {
	if index < 0 || index >= len(world.geometries) { return }
	world.geometries[index] = {}
	append(&world.free_geometry_indices, index)
}

allocate_material_slot :: proc(world: ^World, value: Material_Component) -> int {
	if index, found := take_free_slot(&world.free_material_indices); found {
		world.materials[index] = value
		return index
	}
	index := len(world.materials)
	append(&world.materials, value)
	return index
}

release_material_slot :: proc(world: ^World, index: int) {
	if index < 0 || index >= len(world.materials) { return }
	world.materials[index] = {}
	append(&world.free_material_indices, index)
}

allocate_render_instance_slot :: proc(world: ^World, value: Render_Instance_Component) -> int {
	if index, found := take_free_slot(&world.free_render_instance_indices); found {
		world.render_instances[index] = value
		return index
	}
	index := len(world.render_instances)
	append(&world.render_instances, value)
	return index
}

release_entity_render_instance :: proc(world: ^World, entity: ^World_Entity) {
	remove_entity_from_active_render_set(world, int(entity.id.index))
	if entity.render_instance_index < 0 ||
	   entity.render_instance_index >= len(world.render_instances) {
		entity.render_instance_index = INVALID_COMPONENT_INDEX
		return
	}
	world.render_instances[entity.render_instance_index] = {}
	append(&world.free_render_instance_indices, entity.render_instance_index)
	entity.render_instance_index = INVALID_COMPONENT_INDEX
}

mark_render_topology_changed :: proc(world: ^World) {
	if world == nil {
		return
	}
	world.render_topology_revision += 1
	if world.render_topology_revision == 0 {
		world.render_topology_revision = 1
	}
}

remove_entity_from_active_render_set :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) { return }
	entity := &world.entities[entity_index]
	active_index := entity.render_active_index
	if active_index < 0 || active_index >= len(world.render_active_entities) {
		entity.render_active_index = INVALID_COMPONENT_INDEX
		return
	}
	last_index := len(world.render_active_entities) - 1
	moved_entity_index := world.render_active_entities[last_index]
	world.render_active_entities[active_index] = moved_entity_index
	pop(&world.render_active_entities)
	if active_index < len(world.render_active_entities) &&
	   moved_entity_index >= 0 &&
	   moved_entity_index < len(world.entities) {
		world.entities[moved_entity_index].render_active_index = active_index
	}
	entity.render_active_index = INVALID_COMPONENT_INDEX
}

ensure_entity_in_active_render_set :: proc(world: ^World, entity_index: int) {
	if world == nil || !entity_is_alive(world, entity_index) { return }
	entity := &world.entities[entity_index]
	if entity.render_active_index >= 0 &&
	   entity.render_active_index < len(world.render_active_entities) &&
	   world.render_active_entities[entity.render_active_index] == entity_index {
		return
	}
	entity.render_active_index = len(world.render_active_entities)
	append(&world.render_active_entities, entity_index)
}

Render_Watch_Kind :: enum {
	Camera,
	Ambient_Light,
	Directional_Light,
	Point_Light,
}

render_watch_entities :: proc(world: ^World, kind: Render_Watch_Kind) -> ^[dynamic]int {
	switch kind {
		case .Camera:
			return &world.render_active_camera_entities
		case .Ambient_Light:
			return &world.render_active_ambient_light_entities
		case .Directional_Light:
			return &world.render_active_directional_light_entities
		case .Point_Light:
			return &world.render_active_point_light_entities
	}
	return nil
}

render_watch_active_index :: proc(entity: ^World_Entity, kind: Render_Watch_Kind) -> ^int {
	switch kind {
		case .Camera:
			return &entity.render_camera_active_index
		case .Ambient_Light:
			return &entity.render_ambient_light_active_index
		case .Directional_Light:
			return &entity.render_directional_light_active_index
		case .Point_Light:
			return &entity.render_point_light_active_index
	}
	return nil
}

remove_entity_from_render_watch :: proc(
	world: ^World,
	entity_index: int,
	kind: Render_Watch_Kind,
) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) { return }
	entities := render_watch_entities(world, kind)
	active_index := render_watch_active_index(&world.entities[entity_index], kind)
	if entities == nil || active_index == nil { return }
	if active_index^ < 0 ||
	   active_index^ >= len(entities^) ||
	   entities^[active_index^] != entity_index {
		active_index^ = INVALID_COMPONENT_INDEX
		return
	}
	last_index := len(entities^) - 1
	moved_entity_index := entities^[last_index]
	entities^[active_index^] = moved_entity_index
	pop(entities)
	if active_index^ < len(entities^) &&
	   moved_entity_index >= 0 &&
	   moved_entity_index < len(world.entities) {
		moved_active_index := render_watch_active_index(&world.entities[moved_entity_index], kind)
		if moved_active_index != nil { moved_active_index^ = active_index^ }
	}
	active_index^ = INVALID_COMPONENT_INDEX
}

ensure_entity_in_render_watch :: proc(world: ^World, entity_index: int, kind: Render_Watch_Kind) {
	if world == nil || !entity_is_alive(world, entity_index) { return }
	entities := render_watch_entities(world, kind)
	active_index := render_watch_active_index(&world.entities[entity_index], kind)
	if entities == nil || active_index == nil { return }
	if active_index^ >= 0 &&
	   active_index^ < len(entities^) &&
	   entities^[active_index^] == entity_index { return }
	active_index^ = len(entities^)
	append(entities, entity_index)
}

sync_render_watch_memberships :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) { return }
	entity := world.entities[entity_index]
	watching := [4]bool {
		entity.alive &&
		entity.camera_index >= 0 &&
		entity.camera_index < len(world.cameras) &&
		entity.transform_index >= 0 &&
		entity.transform_index < len(world.transforms),
		entity.alive &&
		entity.ambient_light_index >= 0 &&
		entity.ambient_light_index < len(world.ambient_lights),
		entity.alive &&
		entity.directional_light_index >= 0 &&
		entity.directional_light_index < len(world.directional_lights),
		entity.alive &&
		entity.point_light_index >= 0 &&
		entity.point_light_index < len(world.point_lights) &&
		entity.transform_index >= 0 &&
		entity.transform_index < len(world.transforms),
	}
	for active, index in watching {
		kind := Render_Watch_Kind(index)
		if active {
			ensure_entity_in_render_watch(world, entity_index, kind)
		} else {
			remove_entity_from_render_watch(world, entity_index, kind)
		}
	}
}

invalidate_entity_renderables :: proc(world: ^World, entity_index: int) {
	for &renderable in world.renderables {
		if renderable.entity_index == entity_index {
			renderable.entity_index = INVALID_COMPONENT_INDEX
		}
	}
}

ensure_entity_renderable :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) { return }
	entity := world.entities[entity_index]
	if entity.transform_index < 0 || entity.mesh_index < 0 { return }
	for &renderable in world.renderables {
		if renderable.entity_index == entity_index {
			renderable.transform_index = entity.transform_index
			renderable.mesh_index = entity.mesh_index
			return
		}
	}
	value := Renderable {
		entity_index = entity_index,
		transform_index = entity.transform_index,
		mesh_index = entity.mesh_index,
	}
	for &renderable in world.renderables {
		if renderable.entity_index < 0 {
			renderable = value
			return
		}
	}
	append(&world.renderables, value)
}

add_geometry :: proc(world: ^World, entity_index: int, handle: shared.Geometry_Handle) {
	if !entity_is_alive(world, entity_index) { return }
	entity := &world.entities[entity_index]
	delete_world_string(world, entity.geometry_resource); entity.geometry_resource = ""
	if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		world.geometries[entity.geometry_index].handle = handle
		mark_render_entity_dirty(world, entity_index)
		return
	}
	entity.geometry_index = allocate_geometry_slot(world, Geometry_Component{handle = handle})
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

add_material :: proc(world: ^World, entity_index: int, handle: shared.Material_Handle) {
	if !entity_is_alive(world, entity_index) { return }
	entity := &world.entities[entity_index]
	delete_world_string(world, entity.material_resource); entity.material_resource = ""
	if entity.material_index >= 0 && entity.material_index < len(world.materials) {
		world.materials[entity.material_index].handle = handle
		mark_render_entity_dirty(world, entity_index)
		return
	}
	entity.material_index = allocate_material_slot(world, Material_Component{handle = handle})
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

resolve_geometry_reference :: proc(
	world: ^World,
	entity_index: int,
	handle: shared.Geometry_Handle,
) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		world.geometries[entity.geometry_index].handle = handle
		mark_render_entity_dirty(world, entity_index)
		return
	}
	entity.geometry_index = allocate_geometry_slot(world, Geometry_Component{handle = handle})
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

resolve_material_reference :: proc(
	world: ^World,
	entity_index: int,
	handle: shared.Material_Handle,
) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.material_index >= 0 && entity.material_index < len(world.materials) {
		world.materials[entity.material_index].handle = handle
		mark_render_entity_dirty(world, entity_index)
		return
	}
	entity.material_index = allocate_material_slot(world, Material_Component{handle = handle})
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

remove_geometry :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) { return }
	entity := &world.entities[entity_index]
	if entity.geometry_index < 0 || entity.geometry_index >= len(world.geometries) { return }
	release_geometry_slot(world, entity.geometry_index)
	entity.geometry_index = INVALID_COMPONENT_INDEX
	release_entity_render_instance(world, entity)
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

remove_material :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) { return }
	entity := &world.entities[entity_index]
	if entity.material_index < 0 || entity.material_index >= len(world.materials) { return }
	release_material_slot(world, entity.material_index)
	entity.material_index = INVALID_COMPONENT_INDEX
	release_entity_render_instance(world, entity)
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

reconcile_render_instances :: proc(world: ^World, registry: ^resources.Registry) {
	if world == nil || registry == nil || len(world.render_dirty_entities) == 0 {
		return
	}
	world.render_structure_sync_count += 1
	dirty_cursor := 0
	for dirty_cursor < len(world.render_dirty_entities) {
		entity_index := world.render_dirty_entities[dirty_cursor]
		dirty_cursor += 1
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := &world.entities[entity_index]
		entity.render_dirty = false
		sync_render_watch_memberships(world, entity_index)
		if entity.geometry_index < 0 && entity.mesh_index >= 0 && entity.geometry_resource == "" {
			if handle, found := resources.geometry_by_name(registry, "cube");
			   found { add_geometry(world, entity_index, handle) }
		}
		if entity.material_index < 0 && entity.mesh_index >= 0 && entity.material_resource == "" {
			if handle, found := resources.material_by_name(registry, "default");
			   found { add_material(world, entity_index, handle) }
		}
		if entity.geometry_index < 0 && entity.geometry_resource != "" {
			handle, found := resources.geometry_by_name(registry, entity.geometry_resource)
			if resource_id, valid := shared.resource_uuid_parse(entity.geometry_resource); valid {
				handle, found = resources.geometry_by_uuid(registry, resource_id)
			}
			if found {
				resolve_geometry_reference(world, entity_index, handle)
			}
		}
		if entity.material_index < 0 && entity.material_resource != "" {
			resource_id, valid := shared.resource_uuid_parse(entity.material_resource)
			if valid {
				if handle, found := resources.material_by_uuid(registry, resource_id); found {
					resolve_material_reference(world, entity_index, handle)
				}
			}
		}
		eligible :=
			entity.alive &&
			entity.transform_index >= 0 &&
			entity.transform_index < len(world.transforms) &&
			entity.geometry_index >= 0 &&
			entity.geometry_index < len(world.geometries) &&
			entity.material_index >= 0 &&
			entity.material_index < len(world.materials)
		if eligible {
			geometry := world.geometries[entity.geometry_index]
			material := world.materials[entity.material_index]
			_, geometry_ok := resources.get_geometry(registry, geometry.handle)
			_, material_ok := resources.get_material(registry, material.handle)
			eligible = geometry_ok && material_ok
			if eligible {
				instance := Render_Instance_Component {
					geometry = geometry.handle,
					material = material.handle,
				}
				if entity.render_instance_index >= 0 &&
				   entity.render_instance_index < len(world.render_instances) {
					previous := world.render_instances[entity.render_instance_index]
					if previous.geometry != instance.geometry ||
					   previous.material != instance.material {
						mark_render_topology_changed(world)
					}
					world.render_instances[entity.render_instance_index] = instance
				} else {
					entity.render_instance_index = allocate_render_instance_slot(world, instance)
				}
				ensure_entity_in_active_render_set(world, entity_index)
			}
		}
		if !eligible {
			release_entity_render_instance(world, entity)
		}
	}
	clear(&world.render_dirty_entities)
}

build_resource_render_list :: proc(
	world: ^World,
	registry: ^resources.Registry,
	use_editor_camera: bool = false,
) -> Render_List {
	list: Render_List
	populate_resource_render_list(world, registry, &list, use_editor_camera)
	return list
}

populate_resource_render_list :: proc(
	world: ^World,
	registry: ^resources.Registry,
	list: ^Render_List,
	use_editor_camera: bool = false,
) {
	if world == nil || list == nil {
		return
	}
	begin_world_transform_resolution(world)
	if len(world.render_dirty_entities) > 0 {
		reconcile_render_instances(world, registry)
	}
	sync_resource_render_instances(world, list)
	list.topology_revision = world.render_topology_revision
	list.camera, list.has_camera = active_camera_instance(world, use_editor_camera)
	list.ambient = {}
	list.directional_light_count = 0
	list.point_light_count = 0
	extract_lights(world, list)
}

fill_invalid_render_indices :: proc(indices: ^[dynamic]int, previous_count: int = 0) {
	for index in previous_count ..< len(indices^) {
		indices[index] = INVALID_COMPONENT_INDEX
	}
}

resource_render_instance_for_entity :: proc(
	world: ^World,
	entity_index: int,
) -> (
	instance: Render_Instance,
	ok: bool,
) {
	if !entity_is_alive(world, entity_index) {
		return {}, false
	}
	entity := world.entities[entity_index]
	if entity.render_instance_index < 0 ||
	   entity.render_instance_index >= len(world.render_instances) ||
	   entity.transform_index < 0 ||
	   entity.transform_index >= len(world.transforms) {
		return {}, false
	}
	internal := world.render_instances[entity.render_instance_index]
	world_transform, resolved := resolve_world_transform(world, entity_index)
	if !resolved {
		return {}, false
	}
	return Render_Instance {
			slot = entity.render_instance_index,
			entity = entity,
			local_parent = world.transforms[entity.transform_index].parent,
			transform = world_transform,
			geometry = Geometry_Component{handle = internal.geometry},
			material = Material_Component{handle = internal.material},
			shadow_caster = entity.has_shadow_caster,
			shadow_receiver = entity.has_shadow_receiver,
		},
		true
}

adjust_render_ancestor_counts :: proc(
	list: ^Render_List,
	world: ^World,
	parent: Entity_UUID,
	delta: int,
) {
	if list == nil || world == nil || parent == (Entity_UUID{}) || delta == 0 {
		return
	}
	ancestor := parent
	for _ in 0 ..< len(world.entities) {
		count := list.ancestor_counts[ancestor] + delta
		if count > 0 {
			list.ancestor_counts[ancestor] = count
		} else {
			delete_key(&list.ancestor_counts, ancestor)
		}
		parent_index, found := entity_index_by_uuid(world, ancestor)
		if !found {
			break
		}
		parent_entity := world.entities[parent_index]
		if parent_entity.transform_index < 0 ||
		   parent_entity.transform_index >= len(world.transforms) {
			break
		}
		ancestor = world.transforms[parent_entity.transform_index].parent
		if ancestor == (Entity_UUID{}) {
			break
		}
	}
}

rebuild_render_ancestor_counts :: proc(list: ^Render_List, world: ^World) {
	if list.ancestor_counts == nil {
		list.ancestor_counts = make(map[Entity_UUID]int)
	} else {
		clear(&list.ancestor_counts)
	}
	for &instance in list.instances {
		entity_index := int(instance.entity.id.index)
		if entity_is_alive(world, entity_index) {
			entity := world.entities[entity_index]
			if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
				instance.local_parent = world.transforms[entity.transform_index].parent
			}
		}
		adjust_render_ancestor_counts(list, world, instance.local_parent, 1)
	}
}

render_instance_descends_from :: proc(
	world: ^World,
	instance: Render_Instance,
	ancestor: Entity_UUID,
) -> bool {
	parent := instance.local_parent
	for _ in 0 ..< len(world.entities) {
		if parent == ancestor {
			return true
		}
		if parent == (Entity_UUID{}) {
			return false
		}
		parent_index, found := entity_index_by_uuid(world, parent)
		if !found {
			return false
		}
		parent_entity := world.entities[parent_index]
		if parent_entity.transform_index < 0 ||
		   parent_entity.transform_index >= len(world.transforms) {
			return false
		}
		parent = world.transforms[parent_entity.transform_index].parent
	}
	return false
}

mark_render_descendants_for_extraction :: proc(
	list: ^Render_List,
	world: ^World,
	entity_index: int,
) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	ancestor := world.entities[entity_index].uuid
	if list.ancestor_counts[ancestor] <= 0 {
		return
	}
	for instance in list.instances {
		if render_instance_descends_from(world, instance, ancestor) {
			mark_render_extract_entity_dirty(world, int(instance.entity.id.index))
		}
	}
}

render_list_remove_instance :: proc(list: ^Render_List, world: ^World, entity_index: int) {
	if entity_index < 0 || entity_index >= len(list.instance_index_by_entity) {
		return
	}
	list_index := list.instance_index_by_entity[entity_index]
	if list_index < 0 || list_index >= len(list.instances) {
		list.instance_index_by_entity[entity_index] = INVALID_COMPONENT_INDEX
		return
	}
	removed := list.instances[list_index]
	adjust_render_ancestor_counts(list, world, removed.local_parent, -1)
	removed_slot := list.instances[list_index].slot
	last_index := len(list.instances) - 1
	if list_index != last_index {
		moved := list.instances[last_index]
		list.instances[list_index] = moved
		moved_entity_index := int(moved.entity.id.index)
		if moved_entity_index >= 0 && moved_entity_index < len(list.instance_index_by_entity) {
			list.instance_index_by_entity[moved_entity_index] = list_index
		}
		if moved.slot >= 0 && moved.slot < len(list.instance_index_by_slot) {
			list.instance_index_by_slot[moved.slot] = list_index
		}
	}
	pop(&list.instances)
	list.instance_index_by_entity[entity_index] = INVALID_COMPONENT_INDEX
	if removed_slot >= 0 && removed_slot < len(list.instance_index_by_slot) {
		list.instance_index_by_slot[removed_slot] = INVALID_COMPONENT_INDEX
		append(&list.dirty_instance_slots, removed_slot)
	}
}

render_list_sync_entity :: proc(list: ^Render_List, world: ^World, entity_index: int) {
	list.instance_visit_count += 1
	if entity_index < 0 || entity_index >= len(list.instance_index_by_entity) {
		return
	}
	instance, active := resource_render_instance_for_entity(world, entity_index)
	list_index := list.instance_index_by_entity[entity_index]
	if !active {
		render_list_remove_instance(list, world, entity_index)
		return
	}
	if list_index >= 0 && list_index < len(list.instances) {
		previous_parent := list.instances[list_index].local_parent
		previous_slot := list.instances[list_index].slot
		list.instances[list_index] = instance
		if previous_parent != instance.local_parent {
			adjust_render_ancestor_counts(list, world, previous_parent, -1)
			adjust_render_ancestor_counts(list, world, instance.local_parent, 1)
		}
		if previous_slot != instance.slot &&
		   previous_slot >= 0 &&
		   previous_slot < len(list.instance_index_by_slot) {
			list.instance_index_by_slot[previous_slot] = INVALID_COMPONENT_INDEX
			append(&list.dirty_instance_slots, previous_slot)
		}
	} else {
		list_index = len(list.instances)
		append(&list.instances, instance)
		list.instance_index_by_entity[entity_index] = list_index
		adjust_render_ancestor_counts(list, world, instance.local_parent, 1)
	}
	if instance.slot >= 0 && instance.slot < len(list.instance_index_by_slot) {
		list.instance_index_by_slot[instance.slot] = list_index
		append(&list.dirty_instance_slots, instance.slot)
	}
}

sync_resource_render_instances :: proc(world: ^World, list: ^Render_List) {
	clear(&list.dirty_instance_slots)
	full_sync := list.world_uuid != world.instance_uuid || len(list.instance_index_by_entity) == 0
	previous_entity_count := len(list.instance_index_by_entity)
	previous_slot_count := len(list.instance_index_by_slot)
	if len(list.instance_index_by_entity) < len(world.entities) {
		resize(&list.instance_index_by_entity, len(world.entities))
		fill_invalid_render_indices(&list.instance_index_by_entity, previous_entity_count)
	}
	if len(list.instance_index_by_slot) < len(world.render_instances) {
		resize(&list.instance_index_by_slot, len(world.render_instances))
		fill_invalid_render_indices(&list.instance_index_by_slot, previous_slot_count)
	}
	if full_sync {
		clear(&list.instances)
		if list.ancestor_counts == nil {
			list.ancestor_counts = make(map[Entity_UUID]int)
		} else {
			clear(&list.ancestor_counts)
		}
		fill_invalid_render_indices(&list.instance_index_by_entity)
		fill_invalid_render_indices(&list.instance_index_by_slot)
		for entity_index in world.render_active_entities {
			render_list_sync_entity(list, world, entity_index)
		}
	} else {
		if list.hierarchy_revision != world.render_hierarchy_revision {
			rebuild_render_ancestor_counts(list, world)
		}
		for cursor := 0; cursor < len(world.render_extract_dirty_entities); cursor += 1 {
			entity_index := world.render_extract_dirty_entities[cursor]
			mark_render_descendants_for_extraction(list, world, entity_index)
			render_list_sync_entity(list, world, entity_index)
		}
	}
	for entity_index in world.render_extract_dirty_entities {
		if entity_index >= 0 && entity_index < len(world.entities) {
			world.entities[entity_index].render_extract_dirty = false
		}
	}
	clear(&world.render_extract_dirty_entities)
	list.world_uuid = world.instance_uuid
	list.hierarchy_revision = world.render_hierarchy_revision
	list.instance_slot_count = len(world.render_instances)
	list.full_instance_sync = full_sync
	list.instance_sync_count += 1
}

extract_lights :: proc(world: ^World, list: ^Render_List) {
	if world == nil || list == nil { return }
	for entity_index in world.render_active_ambient_light_entities {
		if !entity_is_alive(world, entity_index) { continue }
		entity := world.entities[entity_index]
		if entity.ambient_light_index < 0 ||
		   entity.ambient_light_index >= len(world.ambient_lights) { continue }
		light := world.ambient_lights[entity.ambient_light_index]
		list.ambient.x += light.color.x * light.intensity
		list.ambient.y += light.color.y * light.intensity
		list.ambient.z += light.color.z * light.intensity
	}
	for entity_index in world.render_active_directional_light_entities {
		if list.directional_light_count >= len(list.directional_lights) { break }
		if !entity_is_alive(world, entity_index) { continue }
		entity := world.entities[entity_index]
		if entity.directional_light_index < 0 ||
		   entity.directional_light_index >= len(world.directional_lights) { continue }
		light := world.directional_lights[entity.directional_light_index]
		if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
			world_transform, _ := resolve_world_transform(world, entity_index)
			light.direction = shared.transform_quaternion_rotate(
				shared.transform_quaternion_from_euler(world_transform.rotation),
				light.direction,
			)
		}
		list.directional_lights[list.directional_light_count] = {
			light = light,
		}
		list.directional_light_count += 1
	}
	for entity_index in world.render_active_point_light_entities {
		if list.point_light_count >= len(list.point_lights) { break }
		if !entity_is_alive(world, entity_index) { continue }
		entity := world.entities[entity_index]
		if entity.point_light_index < 0 ||
		   entity.point_light_index >= len(world.point_lights) ||
		   entity.transform_index < 0 ||
		   entity.transform_index >= len(world.transforms) { continue }
		world_transform, _ := resolve_world_transform(world, entity_index)
		list.point_lights[list.point_light_count] = {
			position = world_transform.position,
			light = world.point_lights[entity.point_light_index],
		}
		list.point_light_count += 1
	}
}

render_batch_count :: proc(list: ^Render_List) -> int {
	if list == nil { return 0 }
	count := 0
	for instance, index in list.instances {
		first := true
		for previous in list.instances[:index] {
			if previous.geometry.handle == instance.geometry.handle &&
			   previous.material.handle == instance.material.handle { first = false; break }
		}
		if first { count += 1 }
	}
	return count
}

clone_world_string :: proc(world: ^World, value: string) -> string {
	if value == "" {
		return ""
	}
	allocator := context.allocator
	if world != nil && world.string_allocator.procedure != nil {
		allocator = world.string_allocator
	}
	cloned, err := strings.clone(value, allocator)
	if err != nil {
		return ""
	}
	return cloned
}

delete_world_string :: proc(world: ^World, value: string) {
	if value == "" {
		return
	}
	allocator := context.allocator
	if world != nil && world.string_allocator.procedure != nil {
		allocator = world.string_allocator
	}
	delete(value, allocator)
}

render_frame_from_world :: proc(world: ^World) -> Render_Frame {
	return Render_Frame {
		entity_count = alive_entity_count(world),
		camera_count = alive_camera_count(world),
		mesh_count = alive_mesh_count(world),
		renderable_count = alive_renderable_count(world),
	}
}

entity_is_alive :: proc "c" (world: ^World, entity_index: int) -> bool {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	return world.entities[entity_index].alive
}

entity_is_current :: proc "c" (world: ^World, entity_index: int, generation: u32) -> bool {
	return(
		entity_is_alive(world, entity_index) &&
		world.entities[entity_index].id.generation == generation \
	)
}

alive_entity_count :: proc "c" (world: ^World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive {
			count += 1
		}
	}
	return count
}

world_storage_stats :: proc "c" (world: ^World) -> World_Storage_Stats {
	if world == nil {
		return {}
	}
	stats := World_Storage_Stats {
		live_entities = alive_entity_count(world),
		entity_slots = len(world.entities),
		transform_slots = len(world.transforms),
		camera_slots = len(world.cameras),
		ambient_light_slots = len(world.ambient_lights),
		directional_light_slots = len(world.directional_lights),
		point_light_slots = len(world.point_lights),
		mesh_slots = len(world.meshes),
		renderable_slots = len(world.renderables),
		geometry_slots = len(world.geometries),
		material_slots = len(world.materials),
		render_instance_slots = len(world.render_instances),
		ui_layout_slots = len(world.ui_layouts),
		ui_hstack_slots = len(world.ui_hstacks),
		ui_vstack_slots = len(world.ui_vstacks),
		ui_scroll_area_slots = len(world.ui_scroll_areas),
		ui_panel_slots = len(world.ui_panels),
		ui_table_slots = len(world.ui_tables),
		ui_list_slots = len(world.ui_lists),
		ui_progress_slots = len(world.ui_progresses),
		ui_state_slots = len(world.ui_states),
		ui_text_slots = len(world.ui_texts),
		ui_button_slots = len(world.ui_buttons),
		ui_input_slots = len(world.ui_inputs),
		ui_checkbox_slots = len(world.ui_checkboxes),
		editor_transform_gizmo_slots = len(world.editor_transform_gizmos),
		editor_scene_camera_slots = len(world.editor_scene_cameras),
		editor_ui_slots = len(world.editor_uis),
		custom_component_storages = len(world.custom_components),
	}
	for storage in world.custom_components {
		stats.custom_component_slots += len(storage.components)
	}
	stats.total_component_slots =
		stats.transform_slots +
		stats.camera_slots +
		stats.ambient_light_slots +
		stats.directional_light_slots +
		stats.point_light_slots +
		stats.mesh_slots +
		stats.geometry_slots +
		stats.material_slots +
		stats.render_instance_slots +
		stats.ui_layout_slots +
		stats.ui_hstack_slots +
		stats.ui_vstack_slots +
		stats.ui_scroll_area_slots +
		stats.ui_panel_slots +
		stats.ui_table_slots +
		stats.ui_list_slots +
		stats.ui_progress_slots +
		stats.ui_state_slots +
		stats.ui_text_slots +
		stats.ui_button_slots +
		stats.ui_input_slots +
		stats.ui_checkbox_slots +
		stats.editor_transform_gizmo_slots +
		stats.editor_scene_camera_slots +
		stats.editor_ui_slots +
		stats.custom_component_slots
	return stats
}

world_storage_stats_max :: proc "c" (a, b: World_Storage_Stats) -> World_Storage_Stats {
	return {
		live_entities = max(a.live_entities, b.live_entities),
		entity_slots = max(a.entity_slots, b.entity_slots),
		transform_slots = max(a.transform_slots, b.transform_slots),
		camera_slots = max(a.camera_slots, b.camera_slots),
		ambient_light_slots = max(a.ambient_light_slots, b.ambient_light_slots),
		directional_light_slots = max(a.directional_light_slots, b.directional_light_slots),
		point_light_slots = max(a.point_light_slots, b.point_light_slots),
		mesh_slots = max(a.mesh_slots, b.mesh_slots),
		renderable_slots = max(a.renderable_slots, b.renderable_slots),
		geometry_slots = max(a.geometry_slots, b.geometry_slots),
		material_slots = max(a.material_slots, b.material_slots),
		render_instance_slots = max(a.render_instance_slots, b.render_instance_slots),
		ui_layout_slots = max(a.ui_layout_slots, b.ui_layout_slots),
		ui_hstack_slots = max(a.ui_hstack_slots, b.ui_hstack_slots),
		ui_vstack_slots = max(a.ui_vstack_slots, b.ui_vstack_slots),
		ui_scroll_area_slots = max(a.ui_scroll_area_slots, b.ui_scroll_area_slots),
		ui_panel_slots = max(a.ui_panel_slots, b.ui_panel_slots),
		ui_table_slots = max(a.ui_table_slots, b.ui_table_slots),
		ui_list_slots = max(a.ui_list_slots, b.ui_list_slots),
		ui_progress_slots = max(a.ui_progress_slots, b.ui_progress_slots),
		ui_state_slots = max(a.ui_state_slots, b.ui_state_slots),
		ui_text_slots = max(a.ui_text_slots, b.ui_text_slots),
		ui_button_slots = max(a.ui_button_slots, b.ui_button_slots),
		ui_input_slots = max(a.ui_input_slots, b.ui_input_slots),
		ui_checkbox_slots = max(a.ui_checkbox_slots, b.ui_checkbox_slots),
		editor_transform_gizmo_slots = max(
			a.editor_transform_gizmo_slots,
			b.editor_transform_gizmo_slots,
		),
		editor_scene_camera_slots = max(a.editor_scene_camera_slots, b.editor_scene_camera_slots),
		editor_ui_slots = max(a.editor_ui_slots, b.editor_ui_slots),
		custom_component_storages = max(a.custom_component_storages, b.custom_component_storages),
		custom_component_slots = max(a.custom_component_slots, b.custom_component_slots),
		total_component_slots = max(a.total_component_slots, b.total_component_slots),
	}
}

project_entity_count :: proc "c" (world: ^World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive && entity.origin != .Editor {
			count += 1
		}
	}
	return count
}

alive_renderable_count :: proc "c" (world: ^World) -> int {
	count := 0
	for entity in world.entities { if entity.alive && entity.render_instance_index >= 0 && entity.render_instance_index < len(world.render_instances) { count += 1 } }
	if count > 0 || len(world.geometries) > 0 || len(world.materials) > 0 { return count }
	for renderable in world.renderables {
		if _, ok := render_instance_from_renderable(world, renderable); ok {
			count += 1
		}
	}
	return count
}

alive_camera_count :: proc(world: ^World) -> int {
	count := 0
	for entity_index in world.render_active_camera_entities {
		if !entity_is_alive(world, entity_index) { continue }
		entity := world.entities[entity_index]
		if entity.camera_index >= 0 && entity.camera_index < len(world.cameras) {
			count += 1
		}
	}
	return count
}

alive_mesh_count :: proc(world: ^World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive && entity.geometry_index >= 0 { count += 1; continue }
		if entity.alive && entity.mesh_index >= 0 {
			count += 1
		}
	}
	return count
}

build_render_list :: proc(world: ^World) -> Render_List {
	list: Render_List
	begin_world_transform_resolution(world)
	list.camera, list.has_camera = first_camera_instance(world)

	for renderable in world.renderables {
		if !entity_is_alive(world, renderable.entity_index) {
			continue
		}
		instance, ok := render_instance_from_renderable(world, renderable)
		if !ok {
			continue
		}
		instance.transform, _ = resolve_world_transform(world, renderable.entity_index)
		append(&list.instances, instance)
	}

	return list
}

destroy_render_list :: proc(list: ^Render_List) {
	delete(list.instances)
	delete(list.instance_index_by_entity)
	delete(list.instance_index_by_slot)
	delete(list.dirty_instance_slots)
	delete(list.ancestor_counts)
	list^ = {}
}

render_instance_from_renderable :: proc "c" (
	world: ^World,
	renderable: Renderable,
) -> (
	instance: Render_Instance,
	ok: bool,
) {
	if renderable.entity_index < 0 || renderable.entity_index >= len(world.entities) {
		return {}, false
	}
	if !world.entities[renderable.entity_index].alive {
		return {}, false
	}
	if world.entities[renderable.entity_index].transform_index != renderable.transform_index ||
	   world.entities[renderable.entity_index].mesh_index != renderable.mesh_index {
		return {}, false
	}
	if renderable.transform_index < 0 || renderable.transform_index >= len(world.transforms) {
		return {}, false
	}
	if renderable.mesh_index < 0 || renderable.mesh_index >= len(world.meshes) {
		return {}, false
	}

	return Render_Instance {
			entity = world.entities[renderable.entity_index],
			transform = world.transforms[renderable.transform_index],
			mesh = world.meshes[renderable.mesh_index],
		},
		true
}

first_camera_instance :: proc(world: ^World) -> (instance: Camera_Instance, ok: bool) {
	selected_entity_index := INVALID_COMPONENT_INDEX
	for entity_index in world.render_active_camera_entities {
		if entity_index < 0 || entity_index >= len(world.entities) { continue }
		entity := world.entities[entity_index]
		if !entity.alive || entity.origin == .Editor {
			continue
		}
		if entity.camera_index < 0 || entity.camera_index >= len(world.cameras) {
			continue
		}
		if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
			continue
		}

		if selected_entity_index < 0 || entity_index < selected_entity_index {
			selected_entity_index = entity_index
		}
	}
	if selected_entity_index < 0 { return {}, false }
	entity := world.entities[selected_entity_index]
	world_transform, _ := resolve_world_transform(world, selected_entity_index)
	return Camera_Instance {
			entity = entity,
			transform = world_transform,
			camera = world.cameras[entity.camera_index],
		},
		true
}

editor_scene_camera_instance :: proc(world: ^World) -> (instance: Camera_Instance, ok: bool) {
	entity_index, _, found := editor_scene_camera_entity(world)
	if !found {
		return {}, false
	}
	entity := world.entities[entity_index]
	if entity.camera_index < 0 ||
	   entity.camera_index >= len(world.cameras) ||
	   entity.transform_index < 0 ||
	   entity.transform_index >= len(world.transforms) {
		return {}, false
	}
	world_transform, _ := resolve_world_transform(world, entity_index)
	return Camera_Instance {
			entity = entity,
			transform = world_transform,
			camera = world.cameras[entity.camera_index],
		},
		true
}

active_camera_instance :: proc(
	world: ^World,
	use_editor_camera: bool,
) -> (
	instance: Camera_Instance,
	ok: bool,
) {
	begin_world_transform_resolution(world)
	if use_editor_camera {
		if editor_camera, found := editor_scene_camera_instance(world); found {
			return editor_camera, true
		}
	}
	return first_camera_instance(world)
}

add_transform :: proc(world: ^World, entity_index: int, transform: Transform_Component) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	if transform.parent != (shared.Entity_UUID{}) &&
	   !transform_parent_is_valid(world, entity_index, transform.parent) {
		return
	}

	entity := &world.entities[entity_index]
	if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
		if world.transforms[entity.transform_index].parent != transform.parent {
			world.render_hierarchy_revision += 1
		}
		world.transforms[entity.transform_index] = transform
		mark_render_entity_dirty(world, entity_index)
		return
	}

	entity.transform_index = allocate_transform_slot(world, transform)
	if transform.parent != (shared.Entity_UUID{}) {
		world.render_hierarchy_revision += 1
	}
	ensure_entity_renderable(world, entity_index)
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

remove_transform :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) { return }
	detach_transform_children(world, entity_index)
	release_transform_slot(world, entity.transform_index)
	entity.transform_index = INVALID_COMPONENT_INDEX
	invalidate_entity_renderables(world, entity_index)
	release_entity_render_instance(world, entity)
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

add_mesh :: proc(world: ^World, entity_index: int, primitive: string) {
	if !entity_is_alive(world, entity_index) {
		return
	}

	entity := &world.entities[entity_index]
	if entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes) {
		delete_world_string(world, world.meshes[entity.mesh_index].primitive)
		world.meshes[entity.mesh_index].primitive = clone_world_string(world, primitive)
	} else {
		entity.mesh_index = allocate_mesh_slot(world, primitive)
		bump_component_revision(world, entity_index)
	}
	ensure_entity_renderable(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

remove_mesh :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.mesh_index < 0 || entity.mesh_index >= len(world.meshes) { return }
	release_mesh_slot(world, entity.mesh_index)
	entity.mesh_index = INVALID_COMPONENT_INDEX
	invalidate_entity_renderables(world, entity_index)
	bump_component_revision(world, entity_index)
	mark_render_entity_dirty(world, entity_index)
}

add_custom_component :: proc(
	world: ^World,
	entity_index: int,
	command_component: ^Command_Component,
) {
	if !entity_is_alive(world, entity_index) {
		return
	}

	name := command_component_name(command_component)
	component_id := command_component.component_id
	remove_custom_component(world, entity_index, component_id, name)

	world_component := Custom_Component {
		entity_index = entity_index,
		component_id = component_id,
		name = clone_world_string(world, name),
	}
	for i in 0 ..< command_component.number_field_count {
		field := &command_component.number_fields[i]
		append(
			&world_component.number_fields,
			Named_Number {
				name = clone_world_string(world, command_number_field_name(field)),
				value = field.value,
			},
		)
	}
	for i in 0 ..< command_component.vec2_field_count {
		field := &command_component.vec2_fields[i]
		append(
			&world_component.vec2_fields,
			Named_Vec2 {
				name = clone_world_string(world, command_vec2_field_name(field)),
				value = field.value,
			},
		)
	}
	for i in 0 ..< command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		append(
			&world_component.vec3_fields,
			Named_Vec3 {
				name = clone_world_string(world, command_field_name(command_field)),
				value = command_field.value,
			},
		)
	}
	for i in 0 ..< command_component.vec4_field_count {
		field := &command_component.vec4_fields[i]
		append(
			&world_component.vec4_fields,
			Named_Vec4 {
				name = clone_world_string(world, command_vec4_field_name(field)),
				value = field.value,
			},
		)
	}
	storage := ensure_custom_component_storage(world, component_id, name)
	ensure_custom_component_entity_capacity(storage, entity_index + 1)
	for &component, component_index in storage.components {
		if component.entity_index != INVALID_COMPONENT_INDEX {
			continue
		}
		component = world_component
		activate_custom_component_slot(storage, component_index)
		storage.entity_component_indices[entity_index] = component_index
		append_entity_custom_storage(world, entity_index, storage.storage_index)
		bump_component_revision(world, entity_index)
		return
	}
	append(&storage.components, world_component)
	activate_custom_component_slot(storage, len(storage.components) - 1)
	storage.entity_component_indices[entity_index] = len(storage.components) - 1
	append_entity_custom_storage(world, entity_index, storage.storage_index)
	bump_component_revision(world, entity_index)
}

remove_custom_component :: proc(
	world: ^World,
	entity_index: int,
	component_id: Component_ID,
	name: string,
) {
	storage := find_custom_component_storage(world, component_id, name)
	if storage == nil {
		return
	}
	component_index, removed := custom_component_index_for_entity(storage, entity_index)
	if removed {
		release_custom_component_slot(world, storage, component_index)
		remove_entity_custom_storage(world, entity_index, storage.storage_index)
	}
	if removed { bump_component_revision(world, entity_index) }
}

add_scene_custom_component :: proc(
	world: ^World,
	entity_index: int,
	scene_component: Custom_Component,
) {
	storage := ensure_custom_component_storage(
		world,
		shared.INVALID_COMPONENT_ID,
		scene_component.name,
	)
	ensure_custom_component_entity_capacity(storage, entity_index + 1)
	world_component := Custom_Component {
		entity_index = entity_index,
		component_id = shared.INVALID_COMPONENT_ID,
		name = clone_world_string(world, scene_component.name),
	}
	for field in scene_component.number_fields {
		world_field := field
		world_field.name = clone_world_string(world, field.name)
		append(&world_component.number_fields, world_field)
	}
	for field in scene_component.vec2_fields {
		world_field := field
		world_field.name = clone_world_string(world, field.name)
		append(&world_component.vec2_fields, world_field)
	}
	for field in scene_component.vec3_fields {
		world_field := field
		world_field.name = clone_world_string(world, field.name)
		append(&world_component.vec3_fields, world_field)
	}
	for field in scene_component.vec4_fields {
		world_field := field
		world_field.name = clone_world_string(world, field.name)
		append(&world_component.vec4_fields, world_field)
	}
	component_index := -1
	for component, index in storage.components {
		if component.entity_index == INVALID_COMPONENT_INDEX {
			component_index = index
			break
		}
	}
	if component_index < 0 {
		component_index = len(storage.components)
		append(&storage.components, world_component)
	} else {
		storage.components[component_index] = world_component
	}
	activate_custom_component_slot(storage, component_index)
	storage.entity_component_indices[entity_index] = component_index
	append_entity_custom_storage(world, entity_index, storage.storage_index)
}

ensure_custom_component_entity_capacity :: proc(
	storage: ^Custom_Component_Storage,
	required: int,
) {
	if storage == nil || required <= len(storage.entity_component_indices) {
		return
	}
	previous := len(storage.entity_component_indices)
	resize(&storage.entity_component_indices, required)
	for index in previous ..< required {
		storage.entity_component_indices[index] = INVALID_COMPONENT_INDEX
	}
}

custom_component_index_for_entity :: proc "contextless" (
	storage: ^Custom_Component_Storage,
	entity_index: int,
) -> (
	int,
	bool,
) {
	if storage == nil ||
	   entity_index < 0 ||
	   entity_index >= len(storage.entity_component_indices) {
		return INVALID_COMPONENT_INDEX, false
	}
	component_index := storage.entity_component_indices[entity_index]
	if component_index < 0 ||
	   component_index >= len(storage.components) ||
	   storage.components[component_index].entity_index != entity_index {
		return INVALID_COMPONENT_INDEX, false
	}
	return component_index, true
}

append_entity_custom_storage :: proc(world: ^World, entity_index, storage_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	for existing in world.entities[entity_index].custom_component_storage_indices {
		if existing == storage_index {
			return
		}
	}
	append(&world.entities[entity_index].custom_component_storage_indices, storage_index)
}

remove_entity_custom_storage :: proc(world: ^World, entity_index, storage_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	storages := &world.entities[entity_index].custom_component_storage_indices
	for existing, index in storages^ {
		if existing == storage_index {
			unordered_remove(storages, index)
			return
		}
	}
}

activate_custom_component_slot :: proc(storage: ^Custom_Component_Storage, component_index: int) {
	if storage == nil || component_index < 0 || component_index >= len(storage.components) {
		return
	}
	previous := len(storage.component_active_indices)
	if previous <= component_index {
		resize(&storage.component_active_indices, len(storage.components))
		for index in previous ..< len(storage.component_active_indices) {
			storage.component_active_indices[index] = INVALID_COMPONENT_INDEX
		}
	}
	if storage.component_active_indices[component_index] >= 0 {
		return
	}
	storage.component_active_indices[component_index] = len(storage.active_component_indices)
	append(&storage.active_component_indices, component_index)
}

release_custom_component_slot :: proc(
	world: ^World,
	storage: ^Custom_Component_Storage,
	component_index: int,
) {
	if storage == nil || component_index < 0 || component_index >= len(storage.components) {
		return
	}
	component := &storage.components[component_index]
	entity_index := component.entity_index
	if component_index < len(storage.component_active_indices) {
		active_index := storage.component_active_indices[component_index]
		if active_index >= 0 && active_index < len(storage.active_component_indices) {
			last_active_index := len(storage.active_component_indices) - 1
			moved_component_index := storage.active_component_indices[last_active_index]
			storage.active_component_indices[active_index] = moved_component_index
			pop(&storage.active_component_indices)
			storage.component_active_indices[component_index] = INVALID_COMPONENT_INDEX
			if active_index < len(storage.active_component_indices) {
				storage.component_active_indices[moved_component_index] = active_index
			}
		}
	}
	delete_world_string(world, component.name)
	for field in component.number_fields { delete_world_string(world, field.name) }
	for field in component.vec2_fields { delete_world_string(world, field.name) }
	for field in component.vec3_fields {
		delete_world_string(world, field.name)
	}
	for field in component.vec4_fields { delete_world_string(world, field.name) }
	delete(component.number_fields)
	delete(component.vec2_fields)
	delete(component.vec3_fields)
	delete(component.vec4_fields)
	component^ = {
		entity_index = INVALID_COMPONENT_INDEX,
		component_id = shared.INVALID_COMPONENT_ID,
	}
	if entity_index >= 0 && entity_index < len(storage.entity_component_indices) {
		storage.entity_component_indices[entity_index] = INVALID_COMPONENT_INDEX
	}
}

ensure_custom_component_storage :: proc(
	world: ^World,
	component_id: Component_ID,
	name: string,
) -> ^Custom_Component_Storage {
	storage := find_custom_component_storage(world, component_id, name)
	if storage != nil {
		if storage.component_id == shared.INVALID_COMPONENT_ID &&
		   component_id != shared.INVALID_COMPONENT_ID {
			storage.component_id = component_id
			for &component in storage.components {
				component.component_id = component_id
			}
		}
		return storage
	}

	append(
		&world.custom_components,
		Custom_Component_Storage {
			storage_index = len(world.custom_components),
			component_id = component_id,
			name = clone_world_string(world, name),
		},
	)
	storage = &world.custom_components[len(world.custom_components) - 1]
	ensure_custom_component_entity_capacity(storage, len(world.entities))
	return storage
}

find_custom_component_storage :: proc "c" (
	world: ^World,
	component_id: Component_ID,
	name: string,
) -> ^Custom_Component_Storage {
	if world == nil {
		return nil
	}
	if component_id != shared.INVALID_COMPONENT_ID {
		for &storage in world.custom_components {
			if storage.component_id == component_id {
				return &storage
			}
		}
	}
	for &storage in world.custom_components {
		if storage.name == name {
			return &storage
		}
	}
	return nil
}

bind_custom_component_storage :: proc(world: ^World, name: string, component_id: Component_ID) {
	storage := ensure_custom_component_storage(world, component_id, name)
	storage.component_id = component_id
	for &component in storage.components {
		component.component_id = component_id
	}
}

query_view :: proc "c" (world: ^World, component_id: Component_ID, name: string) -> Query_View {
	return Query_View{storage = find_custom_component_storage(world, component_id, name)}
}

query_view_count :: proc "c" (world: ^World, view: Query_View) -> int {
	if view.storage == nil {
		return 0
	}

	count := 0
	for component in view.storage.components {
		if entity_is_alive(world, component.entity_index) {
			count += 1
		}
	}
	return count
}

query_view_component_at :: proc "c" (
	world: ^World,
	view: Query_View,
	visible_index: int,
) -> (
	component: Custom_Component,
	ok: bool,
) {
	if view.storage == nil || visible_index < 0 {
		return {}, false
	}

	current := 0
	for component in view.storage.components {
		if !entity_is_alive(world, component.entity_index) {
			continue
		}
		if current == visible_index {
			return component, true
		}
		current += 1
	}
	return {}, false
}

query_count :: proc "c" (world: ^World, query: Query) -> int {
	if world == nil || query.term_count == 0 {
		return 0
	}

	count := 0
	cursor := 0
	for {
		_, found := query_next(world, query, &cursor)
		if !found {
			break
		}
		count += 1
	}
	return count
}

query_entity_at :: proc "c" (
	world: ^World,
	query: Query,
	visible_index: int,
) -> (
	entity_index: int,
	ok: bool,
) {
	if world == nil || query.term_count == 0 || visible_index < 0 {
		return -1, false
	}

	cursor := 0
	for current := 0; current <= visible_index; current += 1 {
		index, found := query_next(world, query, &cursor)
		if !found {
			return -1, false
		}
		if current == visible_index {
			return index, true
		}
	}
	return -1, false
}

query_next :: proc "c" (
	world: ^World,
	query: Query,
	next_entity_index: ^int,
) -> (
	entity_index: int,
	ok: bool,
) {
	if world == nil || query.term_count == 0 || next_entity_index == nil {
		return -1, false
	}
	anchor := query_smallest_custom_storage(world, query)
	if anchor != nil {
		for candidate_index := max(next_entity_index^, 0);
		    candidate_index < len(anchor.active_component_indices);
		    candidate_index += 1 {
			when ODIN_TEST {
				world.query_candidate_visit_count += 1
			}
			next_entity_index^ = candidate_index + 1
			component_index := anchor.active_component_indices[candidate_index]
			entity_index := anchor.components[component_index].entity_index
			if query_matches_entity(world, query, entity_index) {
				return entity_index, true
			}
		}
		return -1, false
	}
	for entity_index := max(next_entity_index^, 0);
	    entity_index < len(world.entities);
	    entity_index += 1 {
		when ODIN_TEST {
			world.query_candidate_visit_count += 1
		}
		next_entity_index^ = entity_index + 1
		if query_matches_entity(world, query, entity_index) {
			return entity_index, true
		}
	}
	return -1, false
}

query_smallest_custom_storage :: proc "contextless" (
	world: ^World,
	query: Query,
) -> ^Custom_Component_Storage {
	if world == nil {
		return nil
	}
	best: ^Custom_Component_Storage
	for term_index in 0 ..< query.term_count {
		term := query.terms[term_index]
		storage := find_custom_component_storage(world, term.component_id, term.name)
		if storage == nil {
			continue
		}
		if best == nil ||
		   len(storage.active_component_indices) < len(best.active_component_indices) {
			best = storage
		}
	}
	return best
}

query_matches_entity :: proc "c" (world: ^World, query: Query, entity_index: int) -> bool {
	if !entity_is_alive(world, entity_index) || world.entities[entity_index].origin == .Editor {
		return false
	}
	for i in 0 ..< query.term_count {
		term := query.terms[i]
		if !entity_has_component(world, entity_index, term.component_id, term.name) {
			return false
		}
	}
	return true
}

entity_has_component :: proc "c" (
	world: ^World,
	entity_index: int,
	component_id: Component_ID,
	name: string,
) -> bool {
	if !entity_is_alive(world, entity_index) {
		return false
	}

	entity := world.entities[entity_index]
	switch name {
		case "scrapbot.transform":
			return entity.transform_index >= 0 && entity.transform_index < len(world.transforms)
		case "scrapbot.camera":
			return entity.camera_index >= 0 && entity.camera_index < len(world.cameras)
		case "scrapbot.ambient_light":
			return(
				entity.ambient_light_index >= 0 &&
				entity.ambient_light_index < len(world.ambient_lights) \
			)
		case "scrapbot.directional_light":
			return(
				entity.directional_light_index >= 0 &&
				entity.directional_light_index < len(world.directional_lights) \
			)
		case "scrapbot.point_light":
			return(
				entity.point_light_index >= 0 &&
				entity.point_light_index < len(world.point_lights) \
			)
		case "scrapbot.shadow_caster":
			return entity.has_shadow_caster
		case "scrapbot.shadow_receiver":
			return entity.has_shadow_receiver
		case "scrapbot.ui_layout":
			return entity.ui_layout_index >= 0 && entity.ui_layout_index < len(world.ui_layouts)
		case "scrapbot.ui_hstack":
			return entity.ui_hstack_index >= 0 && entity.ui_hstack_index < len(world.ui_hstacks)
		case "scrapbot.ui_vstack":
			return entity.ui_vstack_index >= 0 && entity.ui_vstack_index < len(world.ui_vstacks)
		case "scrapbot.ui_scroll_area":
			return(
				entity.ui_scroll_area_index >= 0 &&
				entity.ui_scroll_area_index < len(world.ui_scroll_areas) \
			)
		case "scrapbot.ui_panel":
			return entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels)
		case "scrapbot.ui_table":
			return entity.ui_table_index >= 0 && entity.ui_table_index < len(world.ui_tables)
		case "scrapbot.ui_list":
			return entity.ui_list_index >= 0 && entity.ui_list_index < len(world.ui_lists)
		case "scrapbot.ui_progress":
			return(
				entity.ui_progress_index >= 0 &&
				entity.ui_progress_index < len(world.ui_progresses) \
			)
		case "scrapbot.ui_state":
			return entity.ui_state_index >= 0 && entity.ui_state_index < len(world.ui_states)
		case "scrapbot.ui_text":
			return entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts)
		case "scrapbot.ui_button":
			return entity.ui_button_index >= 0 && entity.ui_button_index < len(world.ui_buttons)
		case "scrapbot.ui_input":
			return entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs)
		case "scrapbot.ui_checkbox":
			return(
				entity.ui_checkbox_index >= 0 &&
				entity.ui_checkbox_index < len(world.ui_checkboxes) \
			)
		case "scrapbot.mesh":
			return entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes)
		case "scrapbot.geometry":
			return entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries)
		case "scrapbot.material":
			return entity.material_index >= 0 && entity.material_index < len(world.materials)
		case "scrapbot.internal.render_instance":
			return(
				entity.render_instance_index >= 0 &&
				entity.render_instance_index < len(world.render_instances) \
			)
	}

	_, ok := custom_component_for_entity(world, entity_index, component_id, name)
	return ok
}

custom_component_for_entity :: proc "c" (
	world: ^World,
	entity_index: int,
	component_id: Component_ID,
	name: string,
) -> (
	component: Custom_Component,
	ok: bool,
) {
	component_ref, found := custom_component_for_entity_ref(
		world,
		entity_index,
		component_id,
		name,
	)
	if !found {
		return {}, false
	}
	return component_ref^, true
}

custom_component_for_entity_ref :: proc "c" (
	world: ^World,
	entity_index: int,
	component_id: Component_ID,
	name: string,
) -> (
	component: ^Custom_Component,
	ok: bool,
) {
	storage := find_custom_component_storage(world, component_id, name)
	if storage == nil {
		return nil, false
	}
	component_index, found := custom_component_index_for_entity(storage, entity_index)
	if !found || !entity_is_alive(world, entity_index) {
		return nil, false
	}
	return &storage.components[component_index], true
}
