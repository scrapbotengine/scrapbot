package script

import "core:testing"
import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"

@(test)
test_luau_system_receives_time_resource :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.system(function(time: ScrapbotTime)
	assert(time.delta_time == 0.125)
	assert(time.smooth_delta_time == 0.125)
	assert(time.elapsed_time == 0.125)
	assert(time.frame_index == 1)
end)
`, "=time-test", &world)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expectf(t, step_runtime(&runtime, &world, 0.125) == "", "time system failed")
}

@(test)
test_luau_creates_full_geometry_material_and_renderable_entity :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(&runtime, `
local triangle = scrapbot.geometry.create("triangle", {
  vertices = {
    { position = {x=-1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0,y=0} },
    { position = {x=1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=1,y=0} },
    { position = {x=0,y=1,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0.5,y=1} },
  }, indices = {0,1,2},
})
local red = scrapbot.material.unlit("red", 1, 0, 0, 1)
scrapbot.spawn({components = {
  ["scrapbot.transform"] = {position={x=0,y=0,z=0}, scale={x=1,y=1,z=1}},
  ["scrapbot.geometry"] = triangle,
  ["scrapbot.material"] = red,
}})
`, "=geometry-test", &world, &registry, Source_Options{resource_registry=&resource_registry})
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expect(t, ecs.apply_commands(&world, &runtime.commands) == "")
	ecs.reconcile_render_instances(&world, &resource_registry)
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, world.entities[0].render_instance_index >= 0)
	geometry, ok := resources.geometry_by_name(&resource_registry, "triangle")
	testing.expect(t, ok)
	geometry_data, valid := resources.get_geometry(&resource_registry, geometry)
	testing.expect(t, valid && len(geometry_data.indices) == 3)
}
@(test)
test_luau_registers_generated_geometry_primitives :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(&runtime, `
scrapbot.geometry.icosphere("ico", 1, 1)
scrapbot.geometry.sphere("sphere", 1, 12, 8)
scrapbot.geometry.pyramid("pyramid", 2, 3, 2)
scrapbot.geometry.cylinder("cylinder", 1, 2, 12)
`, "=primitive-test", &world, &registry, Source_Options{resource_registry=&resource_registry})
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	names := [?]string{"ico","sphere","pyramid","cylinder"}
	for name in names {
		_, ok := resources.geometry_by_name(&resource_registry,name)
		testing.expectf(t,ok,"expected geometry %s",name)
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
	result := run_source(&runtime, `
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
`, "=test", &world)

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
