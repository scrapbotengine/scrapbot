package ecs

import "core:strings"
import resources "../resources"
import shared "../shared"

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
UI_Text_Component :: shared.UI_Text_Component
UI_Button_Component :: shared.UI_Button_Component

INVALID_COMPONENT_INDEX :: -1
MAX_QUERY_TERMS :: 8

Query_View :: struct {
	storage: ^Custom_Component_Storage,
}

Query_Term :: struct {
	component_id: Component_ID,
	name:         string,
}

Query :: struct {
	terms:      [MAX_QUERY_TERMS]Query_Term,
	term_count: int,
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
	for layout in world.ui_layouts {delete(layout.parent)}
	for text in world.ui_texts {delete(text.text)}
	for button in world.ui_buttons {delete(button.text)}
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
	delete(world.ui_layouts)
	delete(world.ui_hstacks)
	delete(world.ui_vstacks)
	delete(world.ui_texts)
	delete(world.ui_buttons)
	delete(world.editor_transform_gizmos)
	delete(world.custom_components)
	world^ = {}
}

build_world :: proc(scene: ^Scene) -> World {
	world: World
	for entity in scene.entities {
		id := Entity{index = u32(len(world.entities)), generation = 1}
		world_entity := World_Entity {
			id              = id,
			alive           = true,
			origin          = .Scene,
			name            = clone_world_string(entity.name),
			transform_index = INVALID_COMPONENT_INDEX,
			camera_index    = INVALID_COMPONENT_INDEX,
			ambient_light_index = INVALID_COMPONENT_INDEX,
			directional_light_index = INVALID_COMPONENT_INDEX,
			point_light_index = INVALID_COMPONENT_INDEX,
			mesh_index      = INVALID_COMPONENT_INDEX,
			geometry_index  = INVALID_COMPONENT_INDEX,
			material_index  = INVALID_COMPONENT_INDEX,
			render_instance_index = INVALID_COMPONENT_INDEX,
			ui_layout_index = INVALID_COMPONENT_INDEX,
			ui_hstack_index = INVALID_COMPONENT_INDEX,
			ui_vstack_index = INVALID_COMPONENT_INDEX,
			ui_text_index = INVALID_COMPONENT_INDEX,
			ui_button_index = INVALID_COMPONENT_INDEX,
			editor_transform_gizmo_index = INVALID_COMPONENT_INDEX,
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
		if entity.has_ambient_light {world_entity.ambient_light_index=len(world.ambient_lights); append(&world.ambient_lights,entity.ambient_light)}
		if entity.has_directional_light {world_entity.directional_light_index=len(world.directional_lights); append(&world.directional_lights,entity.directional_light)}
		if entity.has_point_light {world_entity.point_light_index=len(world.point_lights); append(&world.point_lights,entity.point_light)}
		if entity.has_ui_layout {world_entity.ui_layout_index=len(world.ui_layouts); layout:=entity.ui_layout; layout.parent=clone_world_string(layout.parent); append(&world.ui_layouts,layout)}
		if entity.has_ui_hstack {world_entity.ui_hstack_index=len(world.ui_hstacks); append(&world.ui_hstacks,entity.ui_hstack)}
		if entity.has_ui_vstack {world_entity.ui_vstack_index=len(world.ui_vstacks); append(&world.ui_vstacks,entity.ui_vstack)}
		if entity.has_ui_text {world_entity.ui_text_index=len(world.ui_texts); text:=entity.ui_text; text.text=clone_world_string(text.text); append(&world.ui_texts,text)}
		if entity.has_ui_button {world_entity.ui_button_index=len(world.ui_buttons); button:=entity.ui_button; button.text=clone_world_string(button.text); append(&world.ui_buttons,button)}
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
		if world_entity.transform_index != INVALID_COMPONENT_INDEX &&
		   world_entity.mesh_index != INVALID_COMPONENT_INDEX {
			append(
				&world.renderables,
				Renderable {
					entity_index    = int(id.index),
					transform_index = world_entity.transform_index,
					mesh_index      = world_entity.mesh_index,
				},
			)
		}
	}
	return world
}

add_geometry :: proc(world: ^World, entity_index: int, handle: shared.Geometry_Handle) {
	if !entity_is_alive(world, entity_index) {return}
	entity := &world.entities[entity_index]
	delete(entity.geometry_resource); entity.geometry_resource = ""
	if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		world.geometries[entity.geometry_index].handle = handle
		return
	}
	entity.geometry_index = len(world.geometries)
	append(&world.geometries, Geometry_Component{handle = handle})
}

add_material :: proc(world: ^World, entity_index: int, handle: shared.Material_Handle) {
	if !entity_is_alive(world, entity_index) {return}
	entity := &world.entities[entity_index]
	delete(entity.material_resource); entity.material_resource = ""
	if entity.material_index >= 0 && entity.material_index < len(world.materials) {
		world.materials[entity.material_index].handle = handle
		return
	}
	entity.material_index = len(world.materials)
	append(&world.materials, Material_Component{handle = handle})
}

remove_geometry :: proc(world: ^World, entity_index: int) {
	if entity_is_alive(world, entity_index) {world.entities[entity_index].geometry_index = INVALID_COMPONENT_INDEX}
}

remove_material :: proc(world: ^World, entity_index: int) {
	if entity_is_alive(world, entity_index) {world.entities[entity_index].material_index = INVALID_COMPONENT_INDEX}
}

reconcile_render_instances :: proc(world: ^World, registry: ^resources.Registry) {
	if world == nil || registry == nil {return}
	for &entity in world.entities {
		if entity.geometry_index < 0 && entity.mesh_index >= 0 {
			if handle, found := resources.geometry_by_name(registry, "cube"); found {add_geometry(world, int(entity.id.index), handle)}
		}
		if entity.material_index < 0 && entity.mesh_index >= 0 {
			if handle, found := resources.material_by_name(registry, "default"); found {add_material(world, int(entity.id.index), handle)}
		}
		if entity.geometry_index < 0 && entity.geometry_resource != "" {
			if handle, found := resources.geometry_by_name(registry, entity.geometry_resource); found {add_geometry(world, int(entity.id.index), handle)}
		}
		if entity.material_index < 0 && entity.material_resource != "" {
			if handle, found := resources.material_by_name(registry, entity.material_resource); found {add_material(world, int(entity.id.index), handle)}
		}
		eligible := entity.alive &&
			entity.transform_index >= 0 && entity.transform_index < len(world.transforms) &&
			entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) &&
			entity.material_index >= 0 && entity.material_index < len(world.materials)
		if eligible {
			geometry := world.geometries[entity.geometry_index]
			material := world.materials[entity.material_index]
			_, geometry_ok := resources.get_geometry(registry, geometry.handle)
			_, material_ok := resources.get_material(registry, material.handle)
			eligible = geometry_ok && material_ok
			if eligible {
				instance := Render_Instance_Component{geometry = geometry.handle, material = material.handle}
				if entity.render_instance_index >= 0 && entity.render_instance_index < len(world.render_instances) {
					world.render_instances[entity.render_instance_index] = instance
				} else {
					entity.render_instance_index = len(world.render_instances)
					append(&world.render_instances, instance)
				}
			}
		}
		if !eligible {entity.render_instance_index = INVALID_COMPONENT_INDEX}
	}
}

build_resource_render_list :: proc(world: ^World, registry: ^resources.Registry) -> Render_List {
	list: Render_List
	list.camera, list.has_camera = first_camera_instance(world)
	extract_lights(world, &list)
	reconcile_render_instances(world, registry)
	for entity in world.entities {
		if !entity.alive || entity.render_instance_index < 0 || entity.render_instance_index >= len(world.render_instances) {continue}
		if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {continue}
		internal := world.render_instances[entity.render_instance_index]
		append(&list.instances, Render_Instance {
			entity = entity,
			transform = world.transforms[entity.transform_index],
			geometry = Geometry_Component{handle = internal.geometry},
			material = Material_Component{handle = internal.material},
			shadow_caster = entity.has_shadow_caster,
			shadow_receiver = entity.has_shadow_receiver,
		})
	}
	return list
}

extract_lights :: proc(world: ^World, list: ^Render_List) {
	for entity in world.entities {
		if !entity.alive {continue}
		if entity.ambient_light_index >= 0 && entity.ambient_light_index < len(world.ambient_lights) {
			light:=world.ambient_lights[entity.ambient_light_index]; list.ambient.x += light.color.x*light.intensity; list.ambient.y += light.color.y*light.intensity; list.ambient.z += light.color.z*light.intensity
		}
		if entity.directional_light_index >= 0 && entity.directional_light_index < len(world.directional_lights) && list.directional_light_count < len(list.directional_lights) {
			list.directional_lights[list.directional_light_count]={light=world.directional_lights[entity.directional_light_index]}; list.directional_light_count += 1
		}
		if entity.point_light_index >= 0 && entity.point_light_index < len(world.point_lights) && entity.transform_index >= 0 && entity.transform_index < len(world.transforms) && list.point_light_count < len(list.point_lights) {
			list.point_lights[list.point_light_count]={position=world.transforms[entity.transform_index].position,light=world.point_lights[entity.point_light_index]}; list.point_light_count += 1
		}
	}
}

render_batch_count :: proc(list: ^Render_List) -> int {
	if list == nil {return 0}
	count := 0
	for instance, index in list.instances {
		first := true
		for previous in list.instances[:index] {
			if previous.geometry.handle == instance.geometry.handle && previous.material.handle == instance.material.handle {first=false; break}
		}
		if first {count += 1}
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
		entity_count     = alive_entity_count(world),
		camera_count     = alive_camera_count(world),
		mesh_count       = alive_mesh_count(world),
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
	return entity_is_alive(world, entity_index) && world.entities[entity_index].id.generation == generation
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

alive_renderable_count :: proc "c" (world: ^World) -> int {
	count := 0
	for entity in world.entities {if entity.alive && entity.render_instance_index >= 0 && entity.render_instance_index < len(world.render_instances) {count += 1}}
	if count > 0 || len(world.geometries) > 0 || len(world.materials) > 0 {return count}
	for renderable in world.renderables {
		if _, ok := render_instance_from_renderable(world, renderable); ok {
			count += 1
		}
	}
	return count
}

alive_camera_count :: proc(world: ^World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive && entity.camera_index >= 0 {
			count += 1
		}
	}
	return count
}

alive_mesh_count :: proc(world: ^World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive && entity.geometry_index >= 0 {count += 1; continue}
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

render_instance_from_renderable :: proc "c" (world: ^World, renderable: Renderable) -> (instance: Render_Instance, ok: bool) {
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
		entity    = world.entities[renderable.entity_index],
		transform = world.transforms[renderable.transform_index],
		mesh      = world.meshes[renderable.mesh_index],
	}, true
}

first_camera_instance :: proc(world: ^World) -> (instance: Camera_Instance, ok: bool) {
	for entity in world.entities {
		if !entity.alive {
			continue
		}
		if entity.camera_index < 0 || entity.camera_index >= len(world.cameras) {
			continue
		}
		if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
			continue
		}

		return Camera_Instance {
			entity    = entity,
			transform = world.transforms[entity.transform_index],
			camera    = world.cameras[entity.camera_index],
		}, true
	}
	return {}, false
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

	entity.transform_index = len(world.transforms)
	append_soa(&world.transforms, transform)
	if entity.mesh_index >= 0 {
		append(
			&world.renderables,
			Renderable {
				entity_index    = entity_index,
				transform_index = entity.transform_index,
				mesh_index      = entity.mesh_index,
			},
		)
	}
}

remove_transform :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	world.entities[entity_index].transform_index = INVALID_COMPONENT_INDEX
}

add_mesh :: proc(world: ^World, entity_index: int, primitive: string) {
	if !entity_is_alive(world, entity_index) {
		return
	}

	entity := &world.entities[entity_index]
	entity.mesh_index = len(world.meshes)
	append(
		&world.meshes,
		shared.Mesh_Component {
			primitive = clone_world_string(primitive),
		},
	)
	if entity.transform_index >= 0 {
		append(
			&world.renderables,
			Renderable {
				entity_index    = entity_index,
				transform_index = entity.transform_index,
				mesh_index      = entity.mesh_index,
			},
		)
	}
}

remove_mesh :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}
	world.entities[entity_index].mesh_index = INVALID_COMPONENT_INDEX
}

add_custom_component :: proc(world: ^World, entity_index: int, command_component: ^Command_Component) {
	if !entity_is_alive(world, entity_index) {
		return
	}

	name := command_component_name(command_component)
	component_id := command_component.component_id
	remove_custom_component(world, entity_index, component_id, name)

	world_component := Custom_Component {
		entity_index = entity_index,
		component_id = component_id,
		name         = clone_world_string(name),
	}
	for i in 0..<command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		append(
			&world_component.vec3_fields,
			Named_Vec3 {
				name  = clone_world_string(command_field_name(command_field)),
				value = command_field.value,
			},
		)
	}
	storage := ensure_custom_component_storage(world, component_id, name)
	append(&storage.components, world_component)
}

remove_custom_component :: proc(world: ^World, entity_index: int, component_id: Component_ID, name: string) {
	storage := find_custom_component_storage(world, component_id, name)
	if storage == nil {
		return
	}
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
	}
}

add_scene_custom_component :: proc(world: ^World, entity_index: int, scene_component: Custom_Component) {
	storage := ensure_custom_component_storage(world, shared.INVALID_COMPONENT_ID, scene_component.name)
	world_component := Custom_Component {
		entity_index = entity_index,
		component_id = shared.INVALID_COMPONENT_ID,
		name         = clone_world_string(scene_component.name),
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
		if storage.component_id == shared.INVALID_COMPONENT_ID && component_id != shared.INVALID_COMPONENT_ID {
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
			component_id = component_id,
			name         = clone_world_string(name),
		},
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

bind_custom_component_storage :: proc(
	world: ^World,
	name: string,
	component_id: Component_ID,
) {
	storage := ensure_custom_component_storage(world, component_id, name)
	storage.component_id = component_id
	for &component in storage.components {
		component.component_id = component_id
	}
}

query_view :: proc "c" (
	world: ^World,
	component_id: Component_ID,
	name: string,
) -> Query_View {
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
) -> (component: Custom_Component, ok: bool) {
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
) -> (entity_index: int, ok: bool) {
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
	if !entity_is_alive(world, entity_index) {
		return false
	}
	for i in 0..<query.term_count {
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
	case "scrapbot.ambient_light": return entity.ambient_light_index >= 0 && entity.ambient_light_index < len(world.ambient_lights)
	case "scrapbot.directional_light": return entity.directional_light_index >= 0 && entity.directional_light_index < len(world.directional_lights)
	case "scrapbot.point_light": return entity.point_light_index >= 0 && entity.point_light_index < len(world.point_lights)
	case "scrapbot.shadow_caster": return entity.has_shadow_caster
	case "scrapbot.shadow_receiver": return entity.has_shadow_receiver
	case "scrapbot.ui_layout": return entity.ui_layout_index>=0&&entity.ui_layout_index<len(world.ui_layouts)
	case "scrapbot.ui_hstack": return entity.ui_hstack_index>=0&&entity.ui_hstack_index<len(world.ui_hstacks)
	case "scrapbot.ui_vstack": return entity.ui_vstack_index>=0&&entity.ui_vstack_index<len(world.ui_vstacks)
	case "scrapbot.ui_text": return entity.ui_text_index>=0&&entity.ui_text_index<len(world.ui_texts)
	case "scrapbot.ui_button": return entity.ui_button_index>=0&&entity.ui_button_index<len(world.ui_buttons)
	case "scrapbot.mesh":
		return entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes)
	case "scrapbot.geometry":
		return entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries)
	case "scrapbot.material":
		return entity.material_index >= 0 && entity.material_index < len(world.materials)
	case "scrapbot.internal.render_instance":
		return entity.render_instance_index >= 0 && entity.render_instance_index < len(world.render_instances)
	}

	_, ok := custom_component_for_entity(world, entity_index, component_id, name)
	return ok
}

custom_component_for_entity :: proc "c" (
	world: ^World,
	entity_index: int,
	component_id: Component_ID,
	name: string,
) -> (component: Custom_Component, ok: bool) {
	component_ref, found := custom_component_for_entity_ref(world, entity_index, component_id, name)
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
) -> (component: ^Custom_Component, ok: bool) {
	storage := find_custom_component_storage(world, component_id, name)
	if storage == nil {
		return nil, false
	}
	for &component in storage.components {
		if component.entity_index == entity_index && entity_is_alive(world, component.entity_index) {
			return &component, true
		}
	}
	return nil, false
}
