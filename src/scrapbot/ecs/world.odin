package ecs

import resources "../resources"
import shared "../shared"
import "core:strings"

Scene :: shared.Scene
World :: shared.World
World_Entity :: shared.World_Entity
Entity :: shared.Entity
Render_Frame :: shared.Render_Frame
Renderable :: shared.Renderable
Render_Instance :: shared.Render_Instance
Camera_Instance :: shared.Camera_Instance
Render_List :: shared.Render_List
Custom_Component :: shared.Custom_Component
Custom_Component_Storage :: shared.Custom_Component_Storage
Component_ID :: shared.Component_ID
Vec3 :: shared.Vec3
Named_Vec3 :: shared.Named_Vec3
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
UI_Text_Component :: shared.UI_Text_Component
UI_Button_Component :: shared.UI_Button_Component
UI_Input_Component :: shared.UI_Input_Component
UI_Checkbox_Component :: shared.UI_Checkbox_Component

INVALID_COMPONENT_INDEX :: -1
MAX_QUERY_TERMS :: 8

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
		delete(entity.name)
		delete(entity.geometry_resource)
		delete(entity.material_resource)
	}
	for mesh in world.meshes {
		delete(mesh.primitive)
	}
	for panel in world.ui_panels { delete(panel.title); delete(panel.font) }
	for text in world.ui_texts { delete(text.text); delete(text.font) }
	for button in world.ui_buttons { delete(button.text); delete(button.font) }
	for input in world.ui_inputs { delete(input.text); delete(input.font) }
	for &storage in world.custom_components {
		delete(storage.name)
		for &component in storage.components {
			delete(component.name)
			for field in component.vec3_fields {
				delete(field.name)
			}
			delete(component.vec3_fields)
		}
		delete(storage.components)
	}
	delete(world.entities)
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
	delete(world.free_transform_indices)
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
	delete(world.ui_texts)
	delete(world.ui_buttons)
	delete(world.ui_inputs)
	delete(world.ui_checkboxes)
	delete(world.editor_transform_gizmos)
	delete(world.editor_scene_cameras)
	delete(world.editor_uis)
	delete(world.custom_components)
	delete(world.ui_dirty_entities)
	world^ = {}
}

build_world :: proc(scene: ^Scene) -> World {
	world: World
	world.instance_uuid = shared.entity_uuid_generate()
	world.entity_by_uuid = make(map[shared.Entity_UUID]int)
	for entity in scene.entities {
		id := Entity {
			index = u32(len(world.entities)),
			generation = 1,
		}
		world_entity := World_Entity {
			id = id,
			uuid = entity.id,
			alive = true,
			origin = .Scene,
			name = clone_world_string(entity.name),
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
			ui_text_index = INVALID_COMPONENT_INDEX,
			ui_button_index = INVALID_COMPONENT_INDEX,
			ui_input_index = INVALID_COMPONENT_INDEX,
			ui_checkbox_index = INVALID_COMPONENT_INDEX,
			editor_transform_gizmo_index = INVALID_COMPONENT_INDEX,
			editor_ui_index = INVALID_COMPONENT_INDEX,
			geometry_resource = clone_world_string(entity.geometry_resource),
			material_resource = clone_world_string(entity.material_resource),
			has_shadow_caster = entity.has_shadow_caster,
			has_shadow_receiver = entity.has_shadow_receiver,
		}

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
		if entity.has_ui_panel { world_entity.ui_panel_index = len(world.ui_panels); panel := entity.ui_panel; panel.title = clone_world_string(panel.title); panel.font = clone_world_string(panel.font); append(&world.ui_panels, panel) }
		if entity.has_ui_table { world_entity.ui_table_index = len(world.ui_tables); append(&world.ui_tables, entity.ui_table) }
		if entity.has_ui_text { world_entity.ui_text_index = len(world.ui_texts); text := entity.ui_text; text.text = clone_world_string(text.text); text.font = clone_world_string(text.font); append(&world.ui_texts, text) }
		if entity.has_ui_button { world_entity.ui_button_index = len(world.ui_buttons); button := entity.ui_button; button.text = clone_world_string(button.text); button.font = clone_world_string(button.font); append(&world.ui_buttons, button) }
		if entity.has_ui_input { world_entity.ui_input_index = len(world.ui_inputs); input := entity.ui_input; input.text = clone_world_string(input.text); input.font = clone_world_string(input.font); append(&world.ui_inputs, input) }
		if entity.has_ui_checkbox { world_entity.ui_checkbox_index = len(world.ui_checkboxes); append(&world.ui_checkboxes, entity.ui_checkbox) }
		if entity.has_mesh {
			world_entity.mesh_index = len(world.meshes)
			mesh := entity.mesh
			mesh.primitive = clone_world_string(entity.mesh.primitive)
			append(&world.meshes, mesh)
		}
		for component in entity.custom_components {
			add_scene_custom_component(&world, int(id.index), component)
		}

		append(&world.entities, world_entity)
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

mark_ui_entity_dirty :: proc(world: ^World, entity_index: int) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	entity := &world.entities[entity_index]
	if !entity.ui_dirty {
		entity.ui_dirty = true
		append(&world.ui_dirty_entities, entity_index)
		mark_ui_structure_changed(world)
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
	if entity.render_dirty {
		return
	}
	entity.render_dirty = true
	append(&world.render_dirty_entities, entity_index)
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
		primitive = clone_world_string(primitive),
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
	delete(world.meshes[index].primitive)
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
	delete(entity.geometry_resource); entity.geometry_resource = ""
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
	delete(entity.material_resource); entity.material_resource = ""
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
		if entity.geometry_index < 0 && entity.mesh_index >= 0 {
			if handle, found := resources.geometry_by_name(registry, "cube");
			   found { add_geometry(world, entity_index, handle) }
		}
		if entity.material_index < 0 && entity.mesh_index >= 0 {
			if handle, found := resources.material_by_name(registry, "default");
			   found { add_material(world, entity_index, handle) }
		}
		if entity.geometry_index < 0 && entity.geometry_resource != "" {
			if handle, found := resources.geometry_by_name(registry, entity.geometry_resource);
			   found { add_geometry(world, entity_index, handle) }
		}
		if entity.material_index < 0 && entity.material_resource != "" {
			if handle, found := resources.material_by_name(registry, entity.material_resource);
			   found { add_material(world, entity_index, handle) }
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
	if len(world.render_dirty_entities) > 0 {
		reconcile_render_instances(world, registry)
	}
	list.camera, list.has_camera = active_camera_instance(world, use_editor_camera)
	extract_lights(world, &list)
	for entity_index in world.render_active_entities {
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive ||
		   entity.render_instance_index < 0 ||
		   entity.render_instance_index >= len(world.render_instances) { continue }
		if entity.transform_index < 0 ||
		   entity.transform_index >= len(world.transforms) { continue }
		internal := world.render_instances[entity.render_instance_index]
		append(
			&list.instances,
			Render_Instance {
				entity = entity,
				transform = world.transforms[entity.transform_index],
				geometry = Geometry_Component{handle = internal.geometry},
				material = Material_Component{handle = internal.material},
				shadow_caster = entity.has_shadow_caster,
				shadow_receiver = entity.has_shadow_receiver,
			},
		)
	}
	return list
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
		list.directional_lights[list.directional_light_count] = {
			light = world.directional_lights[entity.directional_light_index],
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
		list.point_lights[list.point_light_count] = {
			position = world.transforms[entity.transform_index].position,
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

clone_world_string :: proc(value: string) -> string {
	if value == "" {
		return ""
	}
	cloned, err := strings.clone(value)
	if err != nil {
		return ""
	}
	return cloned
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
	list.camera, list.has_camera = first_camera_instance(world)

	for renderable in world.renderables {
		if !entity_is_alive(world, renderable.entity_index) {
			continue
		}
		instance, ok := render_instance_from_renderable(world, renderable)
		if !ok {
			continue
		}
		append(&list.instances, instance)
	}

	return list
}

destroy_render_list :: proc(list: ^Render_List) {
	delete(list.instances)
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
	return Camera_Instance {
			entity = entity,
			transform = world.transforms[entity.transform_index],
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
	return Camera_Instance {
			entity = entity,
			transform = world.transforms[entity.transform_index],
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

	entity := &world.entities[entity_index]
	if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
		world.transforms[entity.transform_index] = transform
		return
	}

	entity.transform_index = allocate_transform_slot(world, transform)
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
		delete(world.meshes[entity.mesh_index].primitive)
		world.meshes[entity.mesh_index].primitive = clone_world_string(primitive)
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
		name = clone_world_string(name),
	}
	for i in 0 ..< command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		append(
			&world_component.vec3_fields,
			Named_Vec3 {
				name = clone_world_string(command_field_name(command_field)),
				value = command_field.value,
			},
		)
	}
	storage := ensure_custom_component_storage(world, component_id, name)
	for &component in storage.components {
		if component.entity_index != INVALID_COMPONENT_INDEX {
			continue
		}
		component = world_component
		bump_component_revision(world, entity_index)
		return
	}
	append(&storage.components, world_component)
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
	removed := false
	for &world_component in storage.components {
		if world_component.entity_index != entity_index {
			continue
		}
		delete(world_component.name)
		world_component.name = ""
		world_component.entity_index = INVALID_COMPONENT_INDEX
		world_component.component_id = shared.INVALID_COMPONENT_ID
		for field in world_component.vec3_fields {
			delete(field.name)
		}
		delete(world_component.vec3_fields)
		world_component.vec3_fields = nil
		removed = true
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
	world_component := Custom_Component {
		entity_index = entity_index,
		component_id = shared.INVALID_COMPONENT_ID,
		name = clone_world_string(scene_component.name),
	}
	for field in scene_component.vec3_fields {
		world_field := field
		world_field.name = clone_world_string(field.name)
		append(&world_component.vec3_fields, world_field)
	}
	append(&storage.components, world_component)
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
		Custom_Component_Storage{component_id = component_id, name = clone_world_string(name)},
	)
	return &world.custom_components[len(world.custom_components) - 1]
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
	for entity, entity_index in world.entities {
		if !entity.alive {
			continue
		}
		if query_matches_entity(world, query, entity_index) {
			count += 1
		}
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

	current := 0
	for entity, index in world.entities {
		if !entity.alive {
			continue
		}
		if !query_matches_entity(world, query, index) {
			continue
		}
		if current == visible_index {
			return index, true
		}
		current += 1
	}
	return -1, false
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
	for &component in storage.components {
		if component.entity_index == entity_index &&
		   entity_is_alive(world, component.entity_index) {
			return &component, true
		}
	}
	return nil, false
}
