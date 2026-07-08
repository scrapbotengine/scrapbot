package scrapbot

import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"
import ecs "./ecs"
import project "./project"

HOT_RELOAD_SCRIPT_SOURCE :: `
scrapbot.component("autorotate", {
	velocity = "vec3",
})

scrapbot.system(function(delta_seconds)
	scrapbot.query(scrapbot.component("autorotate", {
		velocity = "vec3",
	}), function(entity, autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += 3 * delta_seconds
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`

HOT_RELOAD_TWO_CUBE_SCENE :: `[[entities]]
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
velocity = [0, 1, 0]

[[entities]]
name = "Right Cube"

[entities.transform]
position = [1.25, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, -1, 0]
`

@(test)
test_hot_reload_replaces_luau_script_systems :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	state: Hot_Reload_State
	init_err := init_hot_reload_state(&state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(&state)

	step_err := hot_reload_frame_system(cast(rawptr)&state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.y > 1.5)

	script_path := join_hot_reload_path(t, root, project.DEFAULT_SCRIPT)
	defer delete(script_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(script_path, HOT_RELOAD_SCRIPT_SOURCE)
	testing.expect(t, write_err == nil)

	step_err = hot_reload_frame_system(cast(rawptr)&state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.x > 2.9)
}

@(test)
test_hot_reload_replaces_scene_world :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)

	state: Hot_Reload_State
	init_err := init_hot_reload_state(&state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(&state)
	defer ecs.destroy_world(&world)

	scene_path := join_hot_reload_path(t, root, project.DEFAULT_SCENE)
	defer delete(scene_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(scene_path, HOT_RELOAD_TWO_CUBE_SCENE)
	testing.expect(t, write_err == nil)

	step_err := hot_reload_frame_system(cast(rawptr)&state, &world, 0)
	testing.expect(t, step_err == "")
	testing.expect(t, len(world.entities) == 3)
	testing.expect(t, len(world.renderables) == 2)
	testing.expect(t, world.entities[1].name == "Left Cube")
	testing.expect(t, world.entities[2].name == "Right Cube")
}

@(test)
test_hot_reload_keeps_last_good_script_on_reload_error :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)

	state: Hot_Reload_State
	init_err := init_hot_reload_state(&state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(&state)
	defer ecs.destroy_world(&world)

	step_err := hot_reload_frame_system(cast(rawptr)&state, &world, 1.0)
	testing.expect(t, step_err == "")
	before_reload_y := world.transforms[1].rotation.y
	testing.expect(t, before_reload_y > 1.5)
	testing.expect(t, state.runtime.system_count == 1)

	step_err = hot_reload_frame_system(cast(rawptr)&state, &world, 1.0)
	testing.expect(t, step_err == "")
	second_frame_y := world.transforms[1].rotation.y
	testing.expectf(t, second_frame_y > before_reload_y + 1.5, "second frame did not advance: before=%v after=%v", before_reload_y, second_frame_y)
	before_reload_y = second_frame_y

	script_path := join_hot_reload_path(t, root, project.DEFAULT_SCRIPT)
	defer delete(script_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(script_path, `error("reload failed")`)
	testing.expect(t, write_err == nil)

	step_err = hot_reload_frame_system(cast(rawptr)&state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expectf(t, state.runtime.system_count == 1, "system_count=%d", state.runtime.system_count)
	testing.expectf(
		t,
		world.transforms[1].rotation.y > before_reload_y + 1.5,
		"rotation.y did not advance from last good script: before=%v after=%v",
		before_reload_y,
		world.transforms[1].rotation.y,
	)
}

make_hot_reload_test_project :: proc(t: ^testing.T) -> (string, string) {
	parent, temp_err := os.make_directory_temp("", "scrapbot-hot-reload-*", context.temp_allocator)
	if !testing.expect(t, temp_err == nil) {
		testing.fail_now(t)
	}

	root, join_err := filepath.join({parent, "project"})
	if !testing.expect(t, join_err == nil) {
		testing.fail_now(t)
	}

	init_err := init_project(root, "Hot Reload Test")
	if !testing.expectf(t, init_err == "", "init_project failed: %s", init_err) {
		testing.fail_now(t)
	}
	return root, parent
}

join_hot_reload_path :: proc(t: ^testing.T, root, path: string) -> string {
	out, join_err := filepath.join({root, path})
	testing.expect(t, join_err == nil)
	return out
}
