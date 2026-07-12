package scrapbot

import "core:os"
import "core:path/filepath"
import "core:testing"
import component "./component"
import ecs "./ecs"
import native "./native"
import project "./project"
import script "./script"

@(test)
test_native_extension_system_steps_world :: proc(t: ^testing.T) {
	root, parent := make_native_system_test_project(t)
	defer delete(root)
	defer delete(parent)
	defer os.remove_all(parent)

	write_native_system_test_extension(t, root)
	write_native_system_test_project(t, root)

	build_err := build_project(root)
	testing.expectf(t, build_err == "", "build_project failed: %s", build_err)

	loaded := project.load_project(root)
	testing.expectf(t, loaded.err == "", "load_project failed: %s", loaded.err)
	defer project.destroy_project_load_result(&loaded)

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	registry: component.Registry
	component.init_registry(&registry)

	extensions: native.Extension_Set
	defer native.destroy_extension_set(&extensions)
	extension_load := native.load_project_extensions(&extensions, root, &registry)
	testing.expectf(t, extension_load.err == "", "load_project_extensions failed: %s", extension_load.err)
	testing.expect(t, extensions.system_count == 1)
	testing.expect(t, extensions.systems[0].declaration.access_count == 3)

	frame_runtime: Frame_Runtime
	defer script.destroy_runtime(&frame_runtime.script_runtime)
	defer native.destroy_extension_set(&frame_runtime.native_extensions)
	frame_runtime.native_extensions = extensions
	extensions = {}

	script_result := script.run_project_script_with_registry(
		&frame_runtime.script_runtime,
		root,
		&world,
		&registry,
		script.Source_Options{},
	)
	testing.expectf(t, script_result.err == "", "script load failed: %s", script_result.err)

	step_err := step_frame_runtime(&frame_runtime, &world, 1.0)
	testing.expectf(t, step_err == "", "step_frame_runtime failed: %s", step_err)
	testing.expectf(t, world.transforms[1].rotation.y > 1.5, "rotation.y=%v", world.transforms[1].rotation.y)
}

make_native_system_test_project :: proc(t: ^testing.T) -> (string, string) {
	parent, temp_err := os.make_directory_temp("", "scrapbot-native-system-*", context.allocator)
	if !testing.expect(t, temp_err == nil) {
		testing.fail_now(t)
	}

	root, join_err := filepath.join({parent, "project"})
	if !testing.expect(t, join_err == nil) {
		testing.fail_now(t)
	}

	init_err := init_project(root, "Native System Test")
	if !testing.expectf(t, init_err == "", "init_project failed: %s", init_err) {
		testing.fail_now(t)
	}
	return root, parent
}

write_native_system_test_project :: proc(t: ^testing.T, root: string) {
	project_path := join_native_system_test_path(t, root, PROJECT_FILE)
	defer delete(project_path)
	write_project_err := os.write_entire_file(project_path, `name = "Native System Test"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "nativespin"
source = "native/nativespin"
`)
	testing.expect(t, write_project_err == nil)

	scene_path := join_native_system_test_path(t, root, DEFAULT_SCENE)
	defer delete(scene_path)
	write_scene_err := os.write_entire_file(scene_path, `[[entities]]
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
name = "Cube"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.nativespin.spin]
angular_velocity = [0, 1.5707963, 0]
`)
	testing.expect(t, write_scene_err == nil)

	script_path := join_native_system_test_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_script_err := os.write_entire_file(script_path, `
local SpinComponent = scrapbot.component_handle("nativespin.spin") :: NativespinSpinComponent
assert(SpinComponent.name == "nativespin.spin")
`)
	testing.expect(t, write_script_err == nil)
}

write_native_system_test_extension :: proc(t: ^testing.T, root: string) {
	source_dir, source_dir_err := filepath.join({root, "native", "nativespin"})
	if !testing.expect(t, source_dir_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_dir)
	make_source_dir_err := os.make_directory_all(source_dir)
	if !testing.expect(t, make_source_dir_err == nil) {
		testing.fail_now(t)
	}

	source_path, source_path_err := filepath.join({source_dir, "nativespin.odin"})
	if !testing.expect(t, source_path_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_path)
	write_source_err := os.write_entire_file(source_path, NATIVE_SYSTEM_TEST_EXTENSION_SOURCE)
	if !testing.expect(t, write_source_err == nil) {
		testing.fail_now(t)
	}
}

join_native_system_test_path :: proc(t: ^testing.T, root, path: string) -> string {
	out, join_err := filepath.join({root, path})
	testing.expect(t, join_err == nil)
	return out
}

NATIVE_SYSTEM_TEST_EXTENSION_SOURCE :: `package nativespin

import scrapbot "scrapbot:extension"

Spin_Component :: scrapbot.Component{name = "nativespin.spin"}
Spin_Angular_Velocity :: scrapbot.Vec3_Field{component = Spin_Component, name = "angular_velocity"}

@(export)
scrapbot_extension_register :: proc "c" (api: ^scrapbot.API) -> cstring {
	return scrapbot.register(api, register)
}

register :: proc "contextless" (ctx: ^scrapbot.Context) -> cstring {
	reg := scrapbot.registry(ctx)

	fields := [?]scrapbot.Field {
		scrapbot.vec3(Spin_Angular_Velocity),
	}
	scrapbot.component(&reg, Spin_Component, fields[:])

	accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.read(Spin_Component),
	}
	scrapbot.system(&reg, "nativespin.spin", accesses[:], spin_system)

	return scrapbot.err(&reg)
}

spin_system :: proc "c" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Spin_Component,
	}
	spin_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, spin_query)
	if count < 0 {
		return "query failed"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, spin_query, i)
		if !entity_ok {
			continue
		}

		transform, transform_ok := scrapbot.get(ctx, entity, scrapbot.Transform_Component)
		if !transform_ok {
			return "get_transform failed"
		}

		angular_velocity, velocity_ok := scrapbot.get(ctx, entity, Spin_Angular_Velocity)
		if !velocity_ok {
			return "get_vec3_field failed"
		}

		transform.rotation.y += angular_velocity.y * ctx.delta_seconds
		if !scrapbot.set(ctx, entity, transform) {
			return "set_transform failed"
		}
	}
	return nil
}
`
