package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"
import "core:testing"

light_gizmo_test_camera :: proc() -> shared.Camera_Instance {
	return {
		transform = {position = {0, 0, 8}, scale = {1, 1, 1}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
}

@(test)
test_selected_point_light_draws_range_sphere_and_commits_one_drag :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Lamp",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 2},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_has_selection = true
	state.editor_selected_entity = world.entities[0].id
	viewport := ui.Rect{0, 0, 800, 600}
	camera := light_gizmo_test_camera()

	editor_light_gizmo_system(state, &world, {}, viewport, camera, true)
	testing.expect(t, state.editor_light_gizmo_visible)
	testing.expect_value(t, state.editor_light_gizmo_kind, ui.Editor_Light_Gizmo_Kind.Point_Range)
	testing.expect_value(
		t,
		state.editor_light_gizmo_segment_count,
		3 * EDITOR_LIGHT_GIZMO_RING_POINTS,
	)
	start := state.editor_light_gizmo_handle
	editor_light_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_light_gizmo_active && state.editor_light_gizmo_captures_pointer)
	editor_light_gizmo_system(
		state,
		&world,
		{
			position = {
				state.editor_light_gizmo_origin.x + 300,
				state.editor_light_gizmo_origin.y,
			},
			primary_down = true,
			available = true,
		},
		viewport,
		camera,
		true,
	)
	point_index := world.entities[0].point_light_index
	changed := world.point_lights[point_index].range
	testing.expect(t, changed > 2)
	editor_light_gizmo_system(
		state,
		&world,
		{position = state.editor_light_gizmo_handle, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(
		t,
		!state.editor_light_gizmo_active && !state.editor_light_gizmo_captures_pointer,
	)
	testing.expect_value(t, state.editor_history_count, 1)
	testing.expect_value(t, state.editor_history_cursor, 1)
	testing.expect(t, ui.editor_undo(state, &world))
	testing.expect(t, math.abs(world.point_lights[point_index].range - 2) < 0.001)
	testing.expect(t, ui.editor_redo(state, &world))
	testing.expect(t, math.abs(world.point_lights[point_index].range - changed) < 0.001)
}

@(test)
test_point_light_range_drag_escape_restores_without_history :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Lamp",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 3},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_has_selection = true
	state.editor_selected_entity = world.entities[0].id
	viewport := ui.Rect{0, 0, 800, 600}
	camera := light_gizmo_test_camera()
	editor_light_gizmo_system(state, &world, {}, viewport, camera, true)
	handle := state.editor_light_gizmo_handle
	editor_light_gizmo_system(state, &world, {handle, 0, true, true}, viewport, camera, true)
	editor_light_gizmo_system(state, &world, {{700, 300}, 0, true, true}, viewport, camera, true)
	editor_light_gizmo_system(
		state,
		&world,
		{{700, 300}, 0, true, true},
		viewport,
		camera,
		true,
		{escape = true},
	)
	testing.expect(t, state.editor_keyboard_escape_consumed)
	testing.expect(
		t,
		math.abs(world.point_lights[world.entities[0].point_light_index].range - 3) < 0.001,
	)
	testing.expect_value(t, state.editor_history_count, 0)
}

@(test)
test_directional_light_gizmo_edits_normalized_direction_and_cancels_when_hidden :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Sun",
			has_directional_light = true,
			directional_light = {direction = {1, 0, 0}, color = {1, 1, 1}, intensity = 1},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_has_selection = true
	state.editor_selected_entity = world.entities[0].id
	viewport := ui.Rect{0, 0, 800, 600}
	camera := light_gizmo_test_camera()
	editor_light_gizmo_system(state, &world, {}, viewport, camera, true)
	testing.expect_value(
		t,
		state.editor_light_gizmo_kind,
		ui.Editor_Light_Gizmo_Kind.Directional_Direction,
	)
	testing.expect_value(t, state.editor_light_gizmo_segment_count, 1)
	handle := state.editor_light_gizmo_handle
	editor_light_gizmo_system(state, &world, {handle, 0, true, true}, viewport, camera, true)
	target, projected := editor_project_world({0, 1, 0}, viewport, camera, true)
	testing.expect(t, projected)
	editor_light_gizmo_system(state, &world, {target, 0, true, true}, viewport, camera, true)
	light := world.directional_lights[world.entities[0].directional_light_index]
	testing.expect(t, math.abs(vec3_dot(light.direction, light.direction) - 1) < 0.001)
	testing.expect(t, light.direction != shared.Vec3{1, 0, 0})

	state.editor_visible = false
	editor_light_gizmo_system(state, &world, {}, viewport, camera, true)
	light = world.directional_lights[world.entities[0].directional_light_index]
	testing.expect_value(t, light.direction, shared.Vec3{1, 0, 0})
	testing.expect(t, !state.editor_light_gizmo_active && !state.editor_light_gizmo_visible)
}
