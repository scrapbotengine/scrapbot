package scrapbot

import component "./component"
import ecs "./ecs"
import native "./native"
import project "./project"
import schedule "./schedule"
import script "./script"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_frame_system_cache_reuses_buffers_and_rebuilds_only_for_topology_changes :: proc(
	t: ^testing.T,
) {
	cache: Frame_System_Cache
	defer destroy_frame_system_cache(&cache)
	systems: [2]schedule.System
	systems[0].accesses[0] = {
		component = "position",
		mode = .Read,
	}
	systems[0].access_count = 1
	systems[1].accesses[0] = {
		component = "velocity",
		mode = .Write,
	}
	systems[1].access_count = 1

	first := prepare_frame_system_cache(&cache, systems[:], 2)
	testing.expect(t, first != nil && first.batch_count == 1)
	testing.expect(t, cache.plan_build_count == 1)
	testing.expect(t, cache.native_command_count == 2)
	testing.expect(t, cap(cache.native_commands[0].commands) == 4)
	first_buffer := raw_data(cache.native_commands[0].commands)

	second := prepare_frame_system_cache(&cache, systems[:], 2)
	testing.expect(t, second == first)
	testing.expect(t, cache.plan_build_count == 1)
	testing.expect(t, raw_data(cache.native_commands[0].commands) == first_buffer)

	systems[1].accesses[0].component = "position"
	_ = prepare_frame_system_cache(&cache, systems[:], 1)
	testing.expect(t, cache.plan_build_count == 2)
	testing.expect(t, cache.plan.batch_count == 2)
	testing.expect(t, cache.native_command_count == 1)
}

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
	testing.expectf(
		t,
		extension_load.err == "",
		"load_project_extensions failed: %s",
		extension_load.err,
	)
	testing.expect(t, extensions.system_count == 2)
	testing.expect(t, extensions.systems[0].declaration.access_count == 6)
	marker_definition, marker_found := component.find_definition(&registry, "nativespin.marker")
	testing.expect(t, marker_found)
	testing.expect(t, marker_definition.advanced)

	frame_runtime := new(Frame_Runtime)
	defer free(frame_runtime)
	defer destroy_frame_runtime(frame_runtime)
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

	step_err := step_frame_runtime(frame_runtime, &world, 1.0)
	testing.expectf(t, step_err == "", "step_frame_runtime failed: %s", step_err)
	testing.expectf(
		t,
		world.transforms[1].rotation.y > 1.5,
		"rotation.y=%v",
		world.transforms[1].rotation.y,
	)
	testing.expectf(
		t,
		world.transforms[3].rotation.y == 0,
		"masked rotation.y=%v",
		world.transforms[3].rotation.y,
	)
	testing.expect(t, !ecs.entity_has_component(&world, 1, ecs.Component_ID(0), "nativespin.spin"))
	testing.expect(
		t,
		ecs.entity_has_component(&world, 1, ecs.Component_ID(0), "nativespin.marker"),
	)
	testing.expect(t, len(world.entities) == 6)
	testing.expect(t, !world.entities[2].alive)
	testing.expect(t, world.entities[3].alive)
	testing.expect(
		t,
		ecs.entity_has_component(&world, 4, ecs.Component_ID(0), "nativespin.marker"),
	)
	testing.expect(t, ecs.entity_has_component(&world, 4, ecs.Component_ID(0), "scrapbot.mesh"))
	testing.expect(t, ecs.entity_has_component(&world, 5, ecs.Component_ID(0), "scrapbot.mesh"))
	testing.expect(t, ecs.alive_renderable_count(&world) == 4)
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
	write_project_err := os.write_entire_file(
		project_path,
		`name = "Native System Test"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "nativespin"
source = "native/nativespin"
`,
	)
	testing.expect(t, write_project_err == nil)

	scene_path := join_native_system_test_path(t, root, DEFAULT_SCENE)
	defer delete(scene_path)
	write_scene_err := os.write_entire_file(
		scene_path,
		`[[entities]]
id = "a4000000-0000-4000-8000-000000000001"
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
id = "a4000000-0000-4000-8000-000000000002"
name = "Cube"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.nativespin.spin]
angular_velocity = [0, 1.5707963, 0]

[[entities]]
id = "a4000000-0000-4000-8000-000000000003"
name = "Temporary"

[entities.components.nativespin.despawn]
value = [0, 0, 0]

[[entities]]
id = "a4000000-0000-4000-8000-000000000004"
name = "Masked Cube"

[entities.transform]
position = [1, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.nativespin.spin]
angular_velocity = [0, 1.5707963, 0]
`,
	)
	testing.expect(t, write_scene_err == nil)

	script_path := join_native_system_test_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_script_err := os.write_entire_file(
		script_path,
		`
local SpinComponent = scrapbot.component_handle("nativespin.spin") :: NativespinSpinComponent
local MarkerComponent = scrapbot.component_handle("nativespin.marker") :: NativespinMarkerComponent
local DespawnComponent = scrapbot.component_handle("nativespin.despawn") :: NativespinDespawnComponent
assert(SpinComponent.name == "nativespin.spin")
assert(MarkerComponent.name == "nativespin.marker")
assert(DespawnComponent.name == "nativespin.despawn")
`,
	)
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
Marker_Component :: scrapbot.Component{name = "nativespin.marker", advanced = true}
Marker_Value :: scrapbot.Vec3_Field{component = Marker_Component, name = "value"}
Despawn_Component :: scrapbot.Component{name = "nativespin.despawn"}
Despawn_Value :: scrapbot.Vec3_Field{component = Despawn_Component, name = "value"}

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

	marker_fields := [?]scrapbot.Field {
		scrapbot.vec3(Marker_Value),
	}
	scrapbot.component(&reg, Marker_Component, marker_fields[:])

	despawn_fields := [?]scrapbot.Field {
		scrapbot.vec3(Despawn_Value),
	}
	scrapbot.component(&reg, Despawn_Component, despawn_fields[:])

	accesses := [?]scrapbot.Access {
		scrapbot.read(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Transform_Component),
		scrapbot.write(scrapbot.Mesh_Component),
		scrapbot.read(Spin_Component),
		scrapbot.write(Spin_Component),
		scrapbot.write(Marker_Component),
	}
	scrapbot.system(&reg, "nativespin.spin", accesses[:], spin_system)

	cleanup_accesses := [?]scrapbot.Access {
		scrapbot.read(Despawn_Component),
	}
	scrapbot.system(&reg, "nativespin.cleanup", cleanup_accesses[:], cleanup_system)

	return scrapbot.err(&reg)
}

spin_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		scrapbot.Transform_Component,
		Spin_Component,
	}
	spin_query := scrapbot.query(components[:])
	chunk: scrapbot.Query_Chunk
	if !scrapbot.init_query_chunk(&chunk, spin_query) {
		return "chunk initialization failed"
	}
	transforms: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Transform
	velocities: [scrapbot.MAX_QUERY_CHUNK_ENTITIES]scrapbot.Vec3
	transform_binding, transform_ok := scrapbot.bind_transform(&chunk, transforms[:], .Write)
	_, velocity_ok := scrapbot.bind_vec3(&chunk, Spin_Angular_Velocity, velocities[:])
	if !transform_ok || !velocity_ok {
		return "chunk binding failed"
	}

	for {
		count, next_err := scrapbot.next_chunk(ctx, &chunk)
		if next_err != nil {
			return next_err
		}
		if count == 0 {
			break
		}
		for lane in 0 ..< count {
			transforms[lane].rotation.y += velocities[lane].y * ctx.time.delta_time
		}
		// Commit only the first lane; the integration test verifies that the second stays unchanged.
		scrapbot.chunk_write_mask(&chunk, transform_binding, 1)
		if commit_err := scrapbot.commit_chunk(ctx, &chunk); commit_err != nil {
			return commit_err
		}

		for entity in scrapbot.chunk_entities(&chunk) {
			marker_fields := [?]scrapbot.Component_Vec3_Field {
				scrapbot.vec3_value(Marker_Value, {1, 2, 3}),
			}
			marker_payload := scrapbot.payload(Marker_Component, marker_fields[:])
			if err := scrapbot.add(ctx, entity, &marker_payload); err != nil {
				return err
			}
			if err := scrapbot.remove(ctx, entity, Spin_Component); err != nil {
				return err
			}

			spawn_transform := scrapbot.Transform {
				position = {2, 0, 0},
				rotation = {},
				scale = {1, 1, 1},
			}
			spawn_payloads := [?]scrapbot.Component_Payload {
				marker_payload,
			}
			spawn_mesh := scrapbot.mesh("cube")
			spawn := scrapbot.spawn_options("Native Spawned", &spawn_transform, &spawn_mesh, spawn_payloads[:])
			if err := scrapbot.spawn(ctx, &spawn); err != nil {
				return err
			}
		}
	}
	return nil
}

cleanup_system :: proc "contextless" (ctx: ^scrapbot.System_Context) -> cstring {
	components := [?]scrapbot.Component {
		Despawn_Component,
	}
	despawn_query := scrapbot.query(components[:])

	count := scrapbot.count(ctx, despawn_query)
	if count < 0 {
		return "cleanup query failed"
	}
	for i in 0..<count {
		entity, entity_ok := scrapbot.entity_at(ctx, despawn_query, i)
		if !entity_ok {
			continue
		}
		if err := scrapbot.despawn(ctx, entity); err != nil {
			return err
		}
	}
	return nil
}
`
