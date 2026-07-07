package main

import "core:testing"

@(test)
test_renderable_rect_uses_scene_camera_and_render_override :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity := make_render_camera_test_world(t, &world)

	default_options := Render_Options{width = 640, height = 480}
	default_rect, default_ok := render_renderable_rect_for_entity(world, entity, 640, 480, 0, default_options)
	testing.expect_value(t, default_ok, true)

	camera := render_options_camera(world, default_options)
	camera.position[0] = 1.0
	override_options := Render_Options{
		width = 640,
		height = 480,
		camera_override_enabled = true,
		camera_override = camera,
	}
	override_rect, override_ok := render_renderable_rect_for_entity(world, entity, 640, 480, 0, override_options)
	testing.expect_value(t, override_ok, true)
	testing.expect_value(t, override_rect.x < default_rect.x, true)

	scene_position, scene_position_err := runtime_world_get_vec3(world, entity, TRANSFORM_COMPONENT_ID, "position")
	testing.expect_value(t, scene_position_err, Runtime_Error.None)
	testing.expect_value(t, scene_position, [3]f32{0, 0, 0})
}

@(test)
test_editor_renderable_rect_uses_game_viewport :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity := make_render_camera_test_world(t, &world)
	options := Render_Options{width = 640, height = 480, editor = true}
	rect, rect_ok := render_renderable_rect_for_entity(world, entity, 640, 480, 0, options)
	testing.expect_value(t, rect_ok, true)

	viewport := render_scene_viewport(640, 480, true)
	center_x := f32(rect.x) + f32(rect.width) * 0.5
	center_y := f32(rect.y) + f32(rect.height) * 0.5
	testing.expect_value(t, center_x >= viewport.x, true)
	testing.expect_value(t, center_x <= viewport.x + viewport.width, true)
	testing.expect_value(t, center_y >= viewport.y, true)
	testing.expect_value(t, center_y <= viewport.y + viewport.height, true)
}

@(test)
test_wgpu_scene_vertices_use_render_camera_options :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	_ = make_render_camera_test_world(t, &world)

	default_vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(default_vertices)
	default_options := Render_Options{width = 640, height = 480}
	wgpu_collect_scene_vertices_with_options(&default_vertices, world, default_options)
	testing.expect_value(t, len(default_vertices), 6)

	camera := render_options_camera(world, default_options)
	camera.position[0] = 1.0
	override_vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(override_vertices)
	wgpu_collect_scene_vertices_with_options(&override_vertices, world, Render_Options{
		width = 640,
		height = 480,
		camera_override_enabled = true,
		camera_override = camera,
	})
	testing.expect_value(t, len(override_vertices), 6)
	testing.expect_value(t, override_vertices[0].position[0] < default_vertices[0].position[0], true)
}

make_render_camera_test_world :: proc(t: ^testing.T, world: ^Runtime_World) -> Entity_Handle {
	entity, entity_err := runtime_world_create_entity(world, "renderable", "Renderable")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(world, entity, TRANSFORM_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({0, 0, 0})},
		{name = "rotation", value = runtime_component_value_vec3({0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3({1, 1, 1})},
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "primitive", value = runtime_component_value_string("box")},
		{name = "segments", value = runtime_component_value_int(0)},
		{name = "rings", value = runtime_component_value_int(0)},
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(world, entity, SURFACE_MATERIAL_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "base_color", value = runtime_component_value_vec3({0, 0.56, 1})},
	}), Runtime_Error.None)

	camera, camera_err := runtime_world_create_entity(world, "camera", "Camera")
	testing.expect_value(t, camera_err, Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(world, camera, TRANSFORM_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({0, 0, 4.8})},
		{name = "rotation", value = runtime_component_value_vec3({0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3({1, 1, 1})},
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(world, camera, CAMERA_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "fov_y_degrees", value = runtime_component_value_float(48)},
		{name = "near", value = runtime_component_value_float(0.1)},
		{name = "far", value = runtime_component_value_float(100)},
	}), Runtime_Error.None)
	return entity
}
