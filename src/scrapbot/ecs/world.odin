package ecs

import shared "../shared"

Scene :: shared.Scene
World :: shared.World
World_Entity :: shared.World_Entity
Entity :: shared.Entity
Render_Frame :: shared.Render_Frame

destroy_world :: proc(world: ^World) {
	delete(world.entities)
	delete(world.transforms)
	delete(world.cameras)
	delete(world.meshes)
	world^ = {}
}

build_world :: proc(scene: ^Scene) -> World {
	world: World
	for entity in scene.entities {
		id := Entity{index = u32(len(world.entities)), generation = 1}
		append(&world.entities, World_Entity{id = id, name = entity.name})

		if entity.has_transform {
			append_soa(&world.transforms, entity.transform)
		}
		if entity.has_camera {
			append(&world.cameras, entity.camera)
		}
		if entity.has_mesh {
			append(&world.meshes, entity.mesh)
		}
	}
	return world
}

render_frame_from_world :: proc(world: ^World) -> Render_Frame {
	return Render_Frame {
		entity_count = len(world.entities),
		camera_count = len(world.cameras),
		mesh_count = len(world.meshes),
	}
}
