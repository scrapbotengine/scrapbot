package ecs

import "core:testing"
import project "../project"
import shared "../shared"

MULTI_CUBE_SCENE :: `[[entities]]
name = "Main Camera"

[entities.transform]
position = [0, 2, 6]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.camera]
fov = 60
near = 0.1
far = 100

[[entities]]
name = "Left Cube"

[entities.transform]
position = [-1.25, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 1.5707963, 0]

[[entities]]
name = "Right Cube"

[entities.transform]
position = [1.25, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, -1.5707963, 0]
`

@(test)
test_scene_builds_world_with_soa_transforms :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(project.default_scene_template())
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 2)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.entities) == 2)
	testing.expect(t, len(world.transforms) == 2)
	testing.expect(t, len(world.cameras) == 1)
	testing.expect(t, len(world.meshes) == 1)
	testing.expect(t, len(world.renderables) == 1)
	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, world.entities[0].camera_index == 0)
	testing.expect(t, world.entities[1].transform_index == 1)
	testing.expect(t, world.entities[1].mesh_index == 0)
	testing.expect(t, world.renderables[0].entity_index == 1)
	testing.expect(t, world.custom_components[0].entity_index == 1)
	testing.expect(t, world.custom_components[0].name == "autorotate")
	testing.expect(t, world.transforms[1].position == shared.Vec3{0, 0, 0})
}

@(test)
test_render_list_includes_multiple_cube_renderables :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 3)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.entities) == 3)
	testing.expect(t, len(world.transforms) == 3)
	testing.expect(t, len(world.meshes) == 2)
	testing.expect(t, len(world.renderables) == 2)
	testing.expect(t, len(world.custom_components) == 2)

	render_list := build_render_list(&world)
	defer destroy_render_list(&render_list)

	testing.expect(t, render_list.has_camera)
	testing.expect(t, len(render_list.instances) == 2)
	testing.expect(t, render_list.instances[0].entity.name == "Left Cube")
	testing.expect(t, render_list.instances[1].entity.name == "Right Cube")
}

@(test)
test_world_preserves_project_custom_components :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.custom_components) == 2)
	testing.expect(t, world.custom_components[0].entity_index == 1)
	testing.expect(t, world.custom_components[0].name == "autorotate")
	testing.expect(t, len(world.custom_components[0].vec3_fields) == 1)
	testing.expect(t, world.custom_components[0].vec3_fields[0].name == "velocity")
	testing.expect(t, world.custom_components[0].vec3_fields[0].value.y > 0)
	testing.expect(t, world.custom_components[1].entity_index == 2)
	testing.expect(t, world.custom_components[1].vec3_fields[0].value.y < 0)

	camera, camera_ok := first_camera_instance(&world)
	testing.expect(t, camera_ok)
	testing.expect(t, camera.camera.fov == 60)
}

@(test)
test_deferred_commands_spawn_entities_when_applied :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)

	commands: Command_Buffer
	err := queue_spawn(&commands, "Spawned")
	testing.expect(t, err == "")
	testing.expect(t, alive_entity_count(&world) == 0)

	apply_err := apply_commands(&world, &commands)
	testing.expect(t, apply_err == "")
	testing.expect(t, commands.command_count == 0)
	testing.expect(t, alive_entity_count(&world) == 1)
	testing.expect(t, world.entities[0].name == "Spawned")
}

@(test)
test_deferred_commands_despawn_entities_without_shifting_indices :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	commands: Command_Buffer
	err := queue_despawn(&commands, 1)
	testing.expect(t, err == "")
	testing.expect(t, alive_entity_count(&world) == 3)
	testing.expect(t, render_frame_from_world(&world).renderable_count == 2)

	apply_err := apply_commands(&world, &commands)
	testing.expect(t, apply_err == "")
	testing.expect(t, alive_entity_count(&world) == 2)
	testing.expect(t, !entity_is_alive(&world, 1))
	testing.expect(t, world.entities[2].id.index == 2)
	testing.expect(t, render_frame_from_world(&world).renderable_count == 1)
}
