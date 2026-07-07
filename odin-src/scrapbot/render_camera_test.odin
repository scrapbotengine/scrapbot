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
test_editor_gizmo_hit_testing_uses_frame_camera_override :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity := make_render_camera_test_world(t, &world)
	state := Editor_Test_Input_State{
		selected_entity = entity,
		has_selected_entity = true,
	}
	input := frame_input_default()
	input.viewport_width = 1280
	input.viewport_height = 720
	input.pointer.has_position = true

	scene_camera, scene_camera_ok := editor_test_camera_state(world)
	testing.expect_value(t, scene_camera_ok, true)
	override_camera := scene_camera
	override_camera.position[0] = 2.5

	entity_position := [3]f32{0, 0, 0}
	x_axis_end := editor_test_scale_vec3([3]f32{1, 0, 0}, EDITOR_TEST_GIZMO_AXIS_LENGTH)
	override_origin, override_origin_ok := editor_test_project_world_to_screen(entity_position, override_camera, input)
	testing.expect_value(t, override_origin_ok, true)
	override_x_end, override_x_end_ok := editor_test_project_world_to_screen(x_axis_end, override_camera, input)
	testing.expect_value(t, override_x_end_ok, true)
	input.pointer.position = {
		(override_origin[0] + override_x_end[0]) * 0.5,
		(override_origin[1] + override_x_end[1]) * 0.5,
	}
	testing.expect_value(t, editor_pointer_in_game_viewport(input), true)

	scene_origin, scene_origin_ok := editor_test_project_world_to_screen(entity_position, scene_camera, input)
	testing.expect_value(t, scene_origin_ok, true)
	scene_x_end, scene_x_end_ok := editor_test_project_world_to_screen(x_axis_end, scene_camera, input)
	testing.expect_value(t, scene_x_end_ok, true)
	scene_distance_sq := editor_test_distance_point_to_segment_sq(input.pointer.position, scene_origin, scene_x_end)
	pick_radius_sq := EDITOR_TEST_GIZMO_PICK_RADIUS_PX * EDITOR_TEST_GIZMO_PICK_RADIUS_PX
	testing.expect_value(t, scene_distance_sq > pick_radius_sq, true)
	_, default_ok := editor_gizmo_axis_at_pointer(world, state, input)
	testing.expect_value(t, default_ok, false)

	input.camera_override_enabled = true
	input.camera_override = override_camera
	axis, override_ok := editor_gizmo_axis_at_pointer(world, state, input)
	testing.expect_value(t, override_ok, true)
	testing.expect_value(t, axis, Editor_Test_Axis.X)
}

@(test)
test_editor_gizmo_drag_finish_pushes_grouped_undo :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity := make_render_camera_test_world(t, &world)
	state := Editor_Test_Input_State{
		selected_entity = entity,
		has_selected_entity = true,
		dragging_axis = .X,
	}
	defer editor_test_input_state_free(&state)

	begin_editor_gizmo_drag(&state, world)
	testing.expect_value(t, state.has_gizmo_drag_start_position, true)
	set_err := runtime_world_set_component_field_value(&world, entity, TRANSFORM_COMPONENT_ID, "position", runtime_component_value_vec3([3]f32{1.2, 0, 0}))
	testing.expect_value(t, set_err, Runtime_Error.None)
	testing.expect_value(t, finish_editor_gizmo_drag(&state, &world), true)
	testing.expect_value(t, state.undo_len, 1)
	testing.expect_value(t, state.has_pending_scene_edit, true)

	testing.expect_value(t, undo_editor_test_field_edit(&world, &state), true)
	position, position_err := runtime_world_get_vec3(world, entity, TRANSFORM_COMPONENT_ID, "position")
	testing.expect_value(t, position_err, Runtime_Error.None)
	testing.expect_value(t, position, [3]f32{0, 0, 0})
	testing.expect_value(t, redo_editor_test_field_edit(&world, &state), true)
	position, position_err = runtime_world_get_vec3(world, entity, TRANSFORM_COMPONENT_ID, "position")
	testing.expect_value(t, position_err, Runtime_Error.None)
	testing.expect_value(t, position, [3]f32{1.2, 0, 0})
}

@(test)
test_editor_gizmo_drag_release_routes_grouped_undo :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity := make_render_camera_test_world(t, &world)
	state := Editor_Test_Input_State{
		selected_entity = entity,
		has_selected_entity = true,
		dragging_axis = .X,
		captured_pointer = true,
		has_last_pointer = true,
		last_pointer = {660, 358},
	}
	defer editor_test_input_state_free(&state)
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	begin_editor_gizmo_drag(&state, world)

	drag_input := frame_input_default()
	drag_input.debug_overlay_visible = true
	drag_input.viewport_width = 1280
	drag_input.viewport_height = 720
	drag_input.pointer.has_position = true
	drag_input.pointer.position = {760, 358}
	drag_input.pointer.primary_down = true
	route_editor_test_input(&state, registry, &world, &drag_input)

	release_input := frame_input_default()
	release_input.debug_overlay_visible = true
	release_input.viewport_width = 1280
	release_input.viewport_height = 720
	release_input.pointer.has_position = true
	release_input.pointer.position = {760, 358}
	release_input.pointer.primary_released = true
	route_editor_test_input(&state, registry, &world, &release_input)
	testing.expect_value(t, state.undo_len, 1)
	testing.expect_value(t, state.has_pending_scene_edit, true)
	testing.expect_value(t, undo_editor_test_field_edit(&world, &state), true)
	position, position_err := runtime_world_get_vec3(world, entity, TRANSFORM_COMPONENT_ID, "position")
	testing.expect_value(t, position_err, Runtime_Error.None)
	testing.expect_value(t, position, [3]f32{0, 0, 0})
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
