package scrapbot

import component "./component"
import ecs "./ecs"
import project "./project"
import resources "./resources"
import shared "./shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

HOT_RELOAD_SCRIPT_SOURCE :: `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system(function(time)
	Autorotating:each(function(entity, autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += 3 * time.delta_time
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`

HOT_RELOAD_TWO_CUBE_SCENE :: `[[entities]]
id = "a3000000-0000-4000-8000-000000000001"
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
id = "a3000000-0000-4000-8000-000000000002"
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
id = "a3000000-0000-4000-8000-000000000003"
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

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)

	step_err := hot_reload_frame_system(state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.y > 1.5)

	script_path := join_hot_reload_path(t, root, project.DEFAULT_SCRIPT)
	defer delete(script_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(script_path, HOT_RELOAD_SCRIPT_SOURCE)
	testing.expect(t, write_err == nil)

	step_err = hot_reload_frame_system(state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.x > 2.9)
}

@(test)
test_hot_reload_checks_files_periodically :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)

	script_path := join_hot_reload_path(t, root, project.DEFAULT_SCRIPT)
	defer delete(script_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(script_path, HOT_RELOAD_SCRIPT_SOURCE)
	testing.expect(t, write_err == nil)

	step_err := hot_reload_frame_system(state, &world, HOT_RELOAD_CHECK_INTERVAL_SECONDS / 2)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.x == 0)

	step_err = hot_reload_frame_system(state, &world, HOT_RELOAD_CHECK_INTERVAL_SECONDS)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[1].rotation.x > 0.7)
}

@(test)
test_hot_reload_replaces_scene_world :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)
	defer ecs.destroy_world(&world)

	scene_path := join_hot_reload_path(t, root, project.DEFAULT_SCENE)
	defer delete(scene_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(scene_path, HOT_RELOAD_TWO_CUBE_SCENE)
	testing.expect(t, write_err == nil)

	step_err := hot_reload_frame_system(state, &world, HOT_RELOAD_CHECK_INTERVAL_SECONDS)
	testing.expectf(t, step_err == "", "hot_reload_frame_system failed: %s", step_err)
	testing.expect(t, len(world.entities) == 3)
	testing.expect(t, len(world.renderables) == 2)
	testing.expect(t, world.entities[1].name == "Left Cube")
	testing.expect(t, world.entities[2].name == "Right Cube")
}

@(test)
test_hot_reload_updates_project_material_without_changing_handle :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	testing.expect(t, len(loaded.resources) == 1)
	resource_id := loaded.resources[0].id
	material_path := join_hot_reload_path(
		t,
		root,
		fmt.tprintf("%s/%s", shared.PROJECT_RESOURCES_DIR, loaded.resources[0].source),
	)
	defer delete(material_path)
	world := ecs.build_world(&loaded.scene)

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)
	defer ecs.destroy_world(&world)

	before, before_found := resources.material_by_uuid(&state.resources, resource_id)
	testing.expect(t, before_found)
	id_buffer: [36]u8
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(
		material_path,
		fmt.tprintf(
			`id = "%s"
type = "scrapbot.material"
name = "Reloaded"

[material]
base_color = [0.125, 0.25, 0.5, 1]
emissive = [2, 1, 0]
`,
			shared.resource_uuid_to_string(resource_id, id_buffer[:]),
		),
	)
	testing.expect(t, write_err == nil)

	step_err := hot_reload_frame_system(state, &world, HOT_RELOAD_CHECK_INTERVAL_SECONDS)
	testing.expectf(t, step_err == "", "hot_reload_frame_system failed: %s", step_err)
	after, after_found := resources.material_by_uuid(&state.resources, resource_id)
	testing.expect(t, after_found)
	testing.expect_value(t, after, before)
	material, alive := resources.get_material(&state.resources, after)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.name, "Reloaded")
		testing.expect_value(t, material.desc.base_color.x, f32(0.125))
		testing.expect_value(t, material.desc.emissive.x, f32(2))
	}
}

@(test)
test_hot_reload_keeps_last_good_script_on_reload_error :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)
	defer ecs.destroy_world(&world)

	step_err := hot_reload_frame_system(state, &world, 1.0)
	testing.expect(t, step_err == "")
	before_reload_y := world.transforms[1].rotation.y
	testing.expect(t, before_reload_y > 1.5)
	testing.expect(t, state.runtime.system_count == 1)

	step_err = hot_reload_frame_system(state, &world, 1.0)
	testing.expect(t, step_err == "")
	second_frame_y := world.transforms[1].rotation.y
	testing.expectf(
		t,
		second_frame_y > before_reload_y + 1.5,
		"second frame did not advance: before=%v after=%v",
		before_reload_y,
		second_frame_y,
	)
	before_reload_y = second_frame_y

	script_path := join_hot_reload_path(t, root, project.DEFAULT_SCRIPT)
	defer delete(script_path)
	time.sleep(5 * time.Millisecond)
	write_err := os.write_entire_file(script_path, `error("reload failed")`)
	testing.expect(t, write_err == nil)

	reload_err := load_script_runtime(state, &world)
	testing.expect(t, reload_err != "")

	step_err = hot_reload_frame_system(state, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expectf(
		t,
		state.runtime.system_count == 1,
		"system_count=%d",
		state.runtime.system_count,
	)
	testing.expectf(
		t,
		world.transforms[1].rotation.y > before_reload_y + 1.5,
		"rotation.y did not advance from last good script: before=%v after=%v",
		before_reload_y,
		world.transforms[1].rotation.y,
	)
}

@(test)
test_hot_reload_rebuilds_native_extension_sources :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	write_hot_reload_native_extension_source(t, root, false)
	write_hot_reload_native_extension_project(t, root)

	build_err := build_project(root)
	testing.expectf(t, build_err == "", "build_project failed: %s", build_err)

	loaded := project.load_project(root)
	testing.expect(t, loaded.err == "")
	world := ecs.build_world(&loaded.scene)

	state := new(Hot_Reload_State)
	defer free(state)
	init_err := init_hot_reload_state(state, root, &loaded, &world)
	project.destroy_project_load_result(&loaded)
	testing.expect(t, init_err == "")
	defer destroy_hot_reload_state(state)
	defer ecs.destroy_world(&world)

	body, body_ok := component.find_definition(&state.runtime.registry, "scrapbotnative.body")
	testing.expect(t, body_ok)
	testing.expect(t, body.field_count == 1)
	testing.expect(t, body.fields[0].name == "velocity")

	time.sleep(5 * time.Millisecond)
	write_hot_reload_native_extension_source(t, root, true)

	step_err := hot_reload_frame_system(state, &world, HOT_RELOAD_CHECK_INTERVAL_SECONDS)
	testing.expectf(t, step_err == "", "hot_reload_frame_system failed: %s", step_err)

	body, body_ok = component.find_definition(&state.runtime.registry, "scrapbotnative.body")
	testing.expect(t, body_ok)
	testing.expectf(t, body.field_count == 2, "field_count=%d", body.field_count)
	testing.expect(t, body.fields[0].name == "velocity")
	testing.expect(t, body.fields[1].name == "acceleration")
}

@(test)
test_asset_stamp_detects_texture_changes :: proc(t: ^testing.T) {
	root, parent := make_hot_reload_test_project(t)
	defer delete(root); defer os.remove_all(parent)
	assets, join_err := filepath.join({root, "assets"})
	testing.expect(t, join_err == nil); if join_err != nil { return }; defer delete(assets)
	texture, texture_err := filepath.join({assets, "texture.png"})
	testing.expect(t, texture_err == nil); if texture_err != nil { return }; defer delete(texture)
	testing.expect(t, os.write_entire_file(texture, "first") == nil)
	first := asset_stamp(assets)
	testing.expect(t, os.write_entire_file(texture, "second-version") == nil)
	second := asset_stamp(assets)
	testing.expect(t, !asset_stamps_equal(first, second))
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

write_hot_reload_native_extension_project :: proc(t: ^testing.T, root: string) {
	project_path := join_hot_reload_path(t, root, PROJECT_FILE)
	defer delete(project_path)
	write_project_err := os.write_entire_file(
		project_path,
		`name = "Hot Reload Test"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "scrapbotnative"
source = "native/scrapbotnative"
`,
	)
	testing.expect(t, write_project_err == nil)

	scene_path := join_hot_reload_path(t, root, DEFAULT_SCENE)
	defer delete(scene_path)
	write_scene_err := os.write_entire_file(
		scene_path,
		`[[entities]]
id = "a3000000-0000-4000-8000-000000000004"
name = "Native Body"

[entities.components.scrapbotnative.body]
velocity = [0, 4, 0]
`,
	)
	testing.expect(t, write_scene_err == nil)

	script_path := join_hot_reload_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_script_err := os.write_entire_file(
		script_path,
		`
local BodyComponent = scrapbot.component_handle("scrapbotnative.body") :: ScrapbotnativeBodyComponent
local Bodies = scrapbot.query(BodyComponent)
assert(Bodies ~= nil)
`,
	)
	testing.expect(t, write_script_err == nil)
}

write_hot_reload_native_extension_source :: proc(
	t: ^testing.T,
	root: string,
	include_acceleration: bool,
) {
	source_dir, source_dir_err := filepath.join({root, "native", "scrapbotnative"})
	if !testing.expect(t, source_dir_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_dir)
	if !os.exists(source_dir) {
		make_source_dir_err := os.make_directory_all(source_dir)
		if !testing.expect(t, make_source_dir_err == nil) {
			testing.fail_now(t)
		}
	}

	source_path, source_path_err := filepath.join({source_dir, "scrapbotnative.odin"})
	if !testing.expect(t, source_path_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_path)

	source := HOT_RELOAD_NATIVE_EXTENSION_SOURCE
	if include_acceleration {
		source = HOT_RELOAD_NATIVE_EXTENSION_SOURCE_WITH_ACCELERATION
	}
	write_source_err := os.write_entire_file(source_path, source)
	if !testing.expect(t, write_source_err == nil) {
		testing.fail_now(t)
	}
}

HOT_RELOAD_NATIVE_EXTENSION_SOURCE :: `package scrapbotnative

import c "core:c"
import api "scrapbot:extension_api"

@(export)
scrapbot_extension_register :: proc "c" (scrapbot: ^api.API) -> cstring {
	if scrapbot == nil {
		return "Scrapbot API is not available"
	}

	fields := [?]api.Field_Definition {
		{name = "velocity", field_type = .Vec3},
	}
	definition := api.Component_Definition {
		name = "scrapbotnative.body",
		fields = raw_data(fields[:]),
		field_count = c.int(len(fields)),
	}
	return scrapbot.register_library_component(scrapbot, &definition)
}
`

HOT_RELOAD_NATIVE_EXTENSION_SOURCE_WITH_ACCELERATION :: `package scrapbotnative

import c "core:c"
import api "scrapbot:extension_api"

@(export)
scrapbot_extension_register :: proc "c" (scrapbot: ^api.API) -> cstring {
	if scrapbot == nil {
		return "Scrapbot API is not available"
	}

	fields := [?]api.Field_Definition {
		{name = "velocity", field_type = .Vec3},
		{name = "acceleration", field_type = .Vec3},
	}
	definition := api.Component_Definition {
		name = "scrapbotnative.body",
		fields = raw_data(fields[:]),
		field_count = c.int(len(fields)),
	}
	return scrapbot.register_library_component(scrapbot, &definition)
}
`
