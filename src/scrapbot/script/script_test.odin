package script

import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_project_without_luau_initializes_native_command_storage :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-native-only-*", context.allocator)
	if !testing.expect(t, root_err == nil) {
		return
	}
	defer delete(root)
	defer os.remove_all(root)
	world: ecs.World
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	runtime: Runtime
	defer destroy_runtime(&runtime)

	result := run_project_script_with_registry(&runtime, root, &world, &registry, {})
	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "")
	testing.expect(t, runtime.commands.commands != nil)
}

@(test)
test_luau_system_receives_time_resource :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	clock_entity, clock_ok := ecs.create_world_entity(&world, "Clock", {}, .Scene)
	testing.expect(t, clock_ok)
	clock := shared.Custom_Component {
		name = "scrapbot.clock",
	}
	append(&clock.number_fields, shared.Named_Number{name = "speed", value = 0.5})
	defer delete(clock.number_fields)
	ecs.add_scene_custom_component(&world, clock_entity, clock)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
scrapbot.system(function(time: ScrapbotTime)
	assert(time.delta_time == 0.0625)
	assert(time.smooth_delta_time == 0.0625)
	assert(time.elapsed_time == 0.0625)
	assert(time.frame_index == 1)
end)
`,
		"=time-test",
		&world,
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expectf(t, step_runtime(&runtime, &world, 0.125) == "", "time system failed")
}

@(test)
test_luau_reads_injected_ecs_input_snapshot :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	frame: shared.Input_Frame
	frame.keyboard.available = true
	shared.input_button_set(&frame.keyboard.buttons.down, int(shared.Input_Key.W))
	shared.input_button_set(&frame.keyboard.buttons.pressed, int(shared.Input_Key.Space))
	frame.pointer.available = true
	frame.pointer.position = {640, 360}
	shared.input_button_set(&frame.pointer.buttons.down, int(shared.Input_Pointer_Button.Primary))
	testing.expect(t, ecs.update_input(&world, frame))
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
scrapbot.system({
	name = "input",
	reads = { scrapbot.keyboard_input, scrapbot.pointer_input },
}, function()
	assert(scrapbot.input.key_down("w"))
	assert(scrapbot.input.key_pressed("space"))
	assert(not scrapbot.input.key_released("space"))
	local pointer = scrapbot.input.pointer()
	assert(pointer.available and pointer.position.x == 640 and pointer.position.y == 360)
	local down, pressed, released = scrapbot.input.pointer_button("primary")
	assert(down and not pressed and not released)
end)
`,
		"=input-test",
		&world,
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expectf(t, step_runtime(&runtime, &world, 1.0 / 60.0) == "", "input system failed")
}

@(test)
test_luau_input_system_can_spawn_entity_with_declared_component_writes :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	frame: shared.Input_Frame
	frame.keyboard.available = true
	shared.input_button_set(&frame.keyboard.buttons.pressed, int(shared.Input_Key.Space))
	testing.expect(t, ecs.update_input(&world, frame))
	registry: component.Registry
	component.init_registry(&registry)
	resource_registry: resources.Registry
	resources.init_registry(&resource_registry)
	defer resources.destroy_registry(&resource_registry)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source_with_registry(
		&runtime,
		`
local Velocity = scrapbot.component("velocity", { value = scrapbot.vec3 })
local Bullet = scrapbot.component("bullet", { age = scrapbot.number })
local Asteroid = scrapbot.component("asteroid", { radius = scrapbot.number })
local geometry = scrapbot.geometry.cylinder("test-bullet", 0.1, 0.5, 8)
local material = scrapbot.material.emissive("test-bullet", 0.1, 0.8, 1.0, 2.0)
local fired = false

scrapbot.spawn({
	name = "Target",
	components = {
		["scrapbot.transform"] = { position = { x = 0, y = 1, z = 0 }, scale = { x = 1, y = 1, z = 1 } },
		asteroid = { radius = 0.5 },
	},
})

scrapbot.system({
	name = "fire",
	reads = { scrapbot.keyboard_input },
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
		Velocity,
		Bullet,
	},
}, function()
	if fired or not scrapbot.input.key_pressed("space") then return end
	fired = true
	scrapbot.spawn({
		name = "Test Bullet",
		components = {
			["scrapbot.transform"] = { position = { x = 0, y = 1, z = 0 }, scale = { x = 1, y = 1, z = 1 } },
			["scrapbot.geometry"] = { resource = geometry, geometry_mode = "virtual" },
			["scrapbot.material"] = material,
			velocity = { value = { x = 0, y = 10, z = 0 } },
			bullet = { age = 0 },
		},
	})
end)

local Asteroids = scrapbot.query(scrapbot.transform, Asteroid)
local Bullets = scrapbot.query(scrapbot.transform, Bullet)
scrapbot.system(Bullets, {
	name = "collide",
	writes = { Bullet },
	reads = { scrapbot.transform, Asteroid },
}, function(_time, bullet_entity, bullet_transform, _bullet)
	for _, item in scrapbot.view(Asteroids) do
		local asteroid_transform = item.components[1]
		local asteroid = item.components[2]
		local dx = bullet_transform.position.x - asteroid_transform.position.x
		local dy = bullet_transform.position.y - asteroid_transform.position.y
		if dx * dx + dy * dy <= asteroid.radius * asteroid.radius then
			scrapbot.despawn(bullet_entity)
			scrapbot.despawn(item.entity)
		end
	end
end)
`,
		"=input-spawn-test",
		&world,
		&registry,
		Source_Options{resource_registry = &resource_registry},
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	if result.err != "" {
		return
	}
	testing.expectf(
		t,
		step_runtime(&runtime, &world, 1.0 / 60.0) == "",
		"input spawn system failed",
	)
	testing.expect_value(t, ecs.alive_entity_count(&world), 2)
	if len(world.entities) == 0 {
		return
	}
	entity := world.entities[1]
	testing.expect(t, entity.alive)
	testing.expect(t, entity.transform_index >= 0)
	testing.expect(t, entity.geometry_index >= 0)
	if entity.geometry_index >= 0 {
		testing.expect_value(
			t,
			world.geometries[entity.geometry_index].geometry_mode,
			shared.Geometry_Mode.Virtual,
		)
	}
	testing.expect(t, entity.material_index >= 0)
	testing.expect_value(t, len(entity.custom_component_storage_indices), 2)
	testing.expectf(t, step_runtime(&runtime, &world, 1.0 / 60.0) == "", "collision system failed")
	testing.expect_value(t, ecs.alive_entity_count(&world), 0)
}

@(test)
test_luau_rejects_write_access_to_input_singletons :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`scrapbot.system({ name = "invalid-input-writer", writes = { scrapbot.keyboard_input } }, function() end)`,
		"=input-write-test",
		&world,
	)
	testing.expectf(
		t,
		strings.contains(
			result.err,
			"system write access cannot target an engine-derived component",
		),
		"unexpected registration error: %s",
		result.err,
	)
}

@(test)
test_luau_creates_full_geometry_material_and_renderable_entity :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(
		&runtime,
		`
local triangle = scrapbot.geometry.create("triangle", {
  vertices = {
    { position = {x=-1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0,y=0} },
    { position = {x=1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=1,y=0} },
    { position = {x=0,y=1,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0.5,y=1} },
  }, indices = {0,1,2},
})
local red = scrapbot.material.unlit("red", 1, 0, 0, 1, true)
scrapbot.material.emissive("neon", 0.25, 0.5, 1, 8)
scrapbot.spawn({components = {
  ["scrapbot.transform"] = {position={x=0,y=0,z=0}, scale={x=1,y=1,z=1}},
  ["scrapbot.geometry"] = triangle,
  ["scrapbot.material"] = red,
}})
`,
		"=geometry-test",
		&world,
		&registry,
		Source_Options{resource_registry = &resource_registry},
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expect(t, ecs.apply_commands(&world, &runtime.commands) == "")
	ecs.reconcile_render_instances(&world, &resource_registry)
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, world.entities[0].render_instance_index >= 0)
	geometry, ok := resources.geometry_by_name(&resource_registry, "triangle")
	testing.expect(t, ok)
	geometry_data, valid := resources.get_geometry(&resource_registry, geometry)
	testing.expect(t, valid && len(geometry_data.indices) == 3)
	red, found_red := resources.material_by_name(&resource_registry, "red")
	testing.expect(t, found_red)
	red_data, valid_red := resources.get_material(&resource_registry, red)
	testing.expect(t, valid_red && red_data.desc.double_sided)
	neon, found_neon := resources.material_by_name(&resource_registry, "neon")
	testing.expect(t, found_neon)
	neon_data, valid_neon := resources.get_material(&resource_registry, neon)
	testing.expect(t, valid_neon)
	if valid_neon {
		testing.expect_value(t, neon_data.desc.emissive, shared.Vec3{2, 4, 8})
	}
}
@(test)
test_luau_registers_generated_geometry_primitives :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(
		&runtime,
		`
scrapbot.geometry.icosphere("ico", 1, 1)
scrapbot.geometry.sphere("sphere", 1, 12, 8)
scrapbot.geometry.pyramid("pyramid", 2, 3, 2)
scrapbot.geometry.cylinder("cylinder", 1, 2, 12)
scrapbot.geometry.voxel_surface("voxel", {
	origin = { x = -1, y = -1, z = -1 },
	voxel_size = 1,
	cells = { x = 2, y = 2, z = 2 },
	densities = { -1, -1, -1, -1, 1, -1, -1, -1, -1, 1, -1, 1, 2, 1, -1, 1, -1, 1, -1, -1, -1, -1, 1, -1, -1, -1, -1 },
})
`,
		"=primitive-test",
		&world,
		&registry,
		Source_Options{resource_registry = &resource_registry},
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	names := [?]string{"ico", "sphere", "pyramid", "cylinder", "voxel"}
	for name in names {
		_, ok := resources.geometry_by_name(&resource_registry, name)
		testing.expectf(t, ok, "expected geometry %s", name)
	}
}

@(test)
test_luau_voxel_surface_rejects_non_finite_cells_before_integer_conversion :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	resource_registry: resources.Registry
	resources.init_registry(&resource_registry)
	defer resources.destroy_registry(&resource_registry)
	sources := [?]string {
		`scrapbot.geometry.voxel_surface("nan", { origin = { x = 0, y = 0, z = 0 }, voxel_size = 1, cells = { x = 0 / 0, y = 1, z = 1 }, densities = {} })`,
		`scrapbot.geometry.voxel_surface("infinity", { origin = { x = 0, y = 0, z = 0 }, voxel_size = 1, cells = { x = math.huge, y = 1, z = 1 }, densities = {} })`,
	}
	for source, index in sources {
		runtime: Runtime
		result := run_source_with_registry(
			&runtime,
			source,
			"=voxel-cell-validation-test",
			&world,
			&registry,
			Source_Options{resource_registry = &resource_registry},
		)
		testing.expectf(t, result.err != "", "non-finite voxel cell case %d was accepted", index)
		destroy_runtime(&runtime)
	}
}

@(test)
test_luau_script_can_read_ecs_counts :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(project.default_scene_template())
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
type Vec3 = {
	x: number,
	y: number,
	z: number,
}

type Component<T> = {
	name: string,
}

type Autorotate = {
	velocity: Vec3,
}

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: Component<Autorotate>

assert(scrapbot.entity_count() == 2)
assert(scrapbot.renderable_count() == 1)
`,
		"=test",
		&world,
	)

	testing.expect(t, result.ran)
	testing.expect(t, result.err == "")
}

@(test)
test_luau_script_reports_runtime_errors :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `error("boom")`, "=test", nil)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err != "")
}
