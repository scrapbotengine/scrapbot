package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"
import "core:testing"

gizmo_vec3_near :: proc(a, b: shared.Vec3, epsilon: f32 = 0.001) -> bool {
	return(
		math.abs(a.x - b.x) <= epsilon &&
		math.abs(a.y - b.y) <= epsilon &&
		math.abs(a.z - b.z) <= epsilon \
	)
}

@(test)
test_transform_gizmos_absorb_pointer_wrap_into_drag_anchors :: proc(t: ^testing.T) {
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state^ = ui.State {
		editor_gizmo_keyboard_active = true,
		editor_gizmo_captures_pointer = true,
		editor_gizmo_drag_pointer = {400, 300},
		editor_gizmo_drag_last_pointer = {900, 500},
	}
	editor_gizmo_apply_pointer_wrap(state, {-1200, 700})
	testing.expect(t, state.editor_gizmo_drag_pointer == shared.Vec2{-800, 1000})
	testing.expect(t, state.editor_gizmo_drag_last_pointer == shared.Vec2{-300, 1200})

	state.editor_gizmo_keyboard_active = false
	editor_gizmo_apply_pointer_wrap(state, {100, 100})
	testing.expect(t, state.editor_gizmo_drag_pointer == shared.Vec2{-700, 1100})
	testing.expect(t, state.editor_gizmo_drag_last_pointer == shared.Vec2{-200, 1300})

	state.editor_gizmo_captures_pointer = false
	editor_gizmo_apply_pointer_wrap(state, {100, 100})
	testing.expect(t, state.editor_gizmo_drag_pointer == shared.Vec2{-700, 1100})
}

@(test)
test_transform_chord_constraints_map_axes_and_excluded_planes :: proc(t: ^testing.T) {
	handle, ok := editor_gizmo_keyboard_handle(.Translate, {actions = {.Transform_Axis_X}})
	testing.expect(t, ok && handle == .X)
	handle, ok = editor_gizmo_keyboard_handle(
		.Scale,
		{shift = true, actions = {.Transform_Axis_X}},
	)
	testing.expect(t, ok && handle == .YZ)
	handle, ok = editor_gizmo_keyboard_handle(
		.Rotate,
		{shift = true, actions = {.Transform_Axis_Z}},
	)
	testing.expect(t, ok && handle == .Z)
	_, ok = editor_gizmo_keyboard_handle(.Translate, {})
	testing.expect(t, !ok)
}

@(test)
test_transform_snapping_quantizes_shared_gizmo_displacements :: proc(t: ^testing.T) {
	axes := [3]shared.Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	free := editor_gizmo_snap_displacement({0.37, -0.74, 1.26}, .Center, axes, 0.5)
	testing.expect(t, gizmo_vec3_near(free, {0.5, -0.5, 1.5}))

	axis := editor_gizmo_snap_displacement({0.37, -0.74, 1.26}, .X, axes, 0.5)
	testing.expect(t, gizmo_vec3_near(axis, {0.5, 0, 0}))

	plane := editor_gizmo_snap_displacement({0.37, -0.74, 1.26}, .XZ, axes, 0.5)
	testing.expect(t, gizmo_vec3_near(plane, {0.5, 0, 1.5}))
	testing.expect(
		t,
		math.abs(
			editor_gizmo_snap_scalar(math.to_radians(f32(22)), math.to_radians(f32(15))) -
			math.to_radians(f32(15)),
		) <
		0.001,
	)
	testing.expect(t, math.abs(editor_gizmo_snap_scale_factor(1.26, 0.1) - 1.3) < 0.001)

	testing.expect(t, editor_gizmo_effective_snap_step(0.5, 0.5, false) == 0.5)
	testing.expect(t, editor_gizmo_effective_snap_step(0.5, 0.5, true) == 0)
	testing.expect(t, editor_gizmo_effective_snap_step(0, 0.5, true) == 0.5)
}

@(test)
test_translation_handles_follow_cursor_rays_in_world_constraints :: proc(t: ^testing.T) {
	camera := shared.Camera_Instance {
		transform = {position = {}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{0, 0, 800, 600}
	axes := [3]shared.Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	origin := shared.Vec3{0, 0, -10}
	start, start_ok := editor_project_world(origin, viewport, camera, true)
	testing.expect(t, start_ok)

	view_target := shared.Vec3{2, 1.5, -10}
	view_pointer, view_ok := editor_project_world(view_target, viewport, camera, true)
	testing.expect(t, view_ok)
	view_position, view_solved := editor_gizmo_translation_position(
		origin,
		.Center,
		axes,
		start,
		view_pointer,
		viewport,
		camera,
		true,
	)
	testing.expect(t, view_solved)
	testing.expect(t, gizmo_vec3_near(view_position, view_target))

	axis_target := shared.Vec3{3, 0, -10}
	axis_pointer, axis_ok := editor_project_world(axis_target, viewport, camera, true)
	testing.expect(t, axis_ok)
	axis_position, axis_solved := editor_gizmo_translation_position(
		origin,
		.X,
		axes,
		start,
		axis_pointer,
		viewport,
		camera,
		true,
	)
	testing.expect(t, axis_solved)
	testing.expect(t, gizmo_vec3_near(axis_position, axis_target))

	plane_target := shared.Vec3{-2, 2.5, -10}
	plane_pointer, plane_ok := editor_project_world(plane_target, viewport, camera, true)
	testing.expect(t, plane_ok)
	plane_position, plane_solved := editor_gizmo_translation_position(
		origin,
		.XY,
		axes,
		start,
		plane_pointer,
		viewport,
		camera,
		true,
	)
	testing.expect(t, plane_solved)
	testing.expect(t, gizmo_vec3_near(plane_position, plane_target))
}

@(test)
test_center_pivot_rotation_and_scale_move_the_transform_origin :: proc(t: ^testing.T) {
	pivot := shared.Vec3{1, 0, 0}
	position := shared.Vec3{2, 0, 0}
	rotated := editor_gizmo_rotated_position(position, pivot, {0, 0, 1}, math.PI / 2)
	testing.expect(t, gizmo_vec3_near(rotated, {1, 1, 0}))

	axes := [3]shared.Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	scaled := editor_gizmo_scaled_position(position, pivot, axes, {2, 1, 1})
	testing.expect(t, gizmo_vec3_near(scaled, {3, 0, 0}))
	scaled = editor_gizmo_scaled_position({2, 2, 0}, pivot, axes, {2, 0.5, 1})
	testing.expect(t, gizmo_vec3_near(scaled, {3, 1, 0}))
}

@(test)
test_center_pivot_free_translation_preserves_origin_offset :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(
		&world.transforms,
		shared.Transform_Component{position = {2, 0, -10}, scale = {1, 1, 1}},
	)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	state.editor_gizmo_pivot = .Center
	state.editor_gizmo_bounds_valid = true
	state.editor_gizmo_bounds_center = {3, 0, -10}
	camera := shared.Camera_Instance {
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{0, 0, 800, 600}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	start := state.editor_gizmo_origin
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Translate}},
	)
	target, projected := editor_project_world({4, 1, -10}, viewport, camera, true)
	testing.expect(t, projected)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = target, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {3, 1, -10}))
}

@(test)
test_multi_selection_transforms_share_pivot_and_commit_one_history_transaction :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("multi-gizmo-a"),
			name = "A",
			has_transform = true,
			transform = {position = {-1, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("multi-gizmo-b"),
			name = "B",
			has_transform = true,
			transform = {position = {1, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	testing.expect(t, ui.init(state) == "")
	state.editor_simulation_stopped = true
	_ = ui.editor_select_entity(state, &world, world.entities[0].id, 0)
	_ = ui.editor_select_entity(state, &world, world.entities[1].id, 0, true)

	editor_gizmo_capture_selection(state, &world)
	state.editor_gizmo_drag_pivot = {}
	state.editor_gizmo_drag_world_axes = editor_gizmo_axes({}, .World)
	editor_gizmo_apply_selection_translation(state, &world, {2, 0, 0})
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {1, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {3, 0, 0}))
	ui.editor_history_push_transform_batch(state, &world, state.editor_gizmo_drag_selection[:])
	testing.expect_value(t, state.editor_history_count, 1)
	testing.expect(t, state.editor_history[0].transform_batch != nil)
	testing.expect_value(t, len(state.editor_history[0].transform_batch.items), 2)
	testing.expect(t, ui.editor_history_apply(state, &world, false))
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {-1, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {1, 0, 0}))
	testing.expect(t, ui.editor_history_apply(state, &world, true))
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {1, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {3, 0, 0}))

	editor_gizmo_restore_selection(state, &world)
	editor_gizmo_apply_selection_rotation(state, &world, {0, 0, 1}, math.PI / 2, true)
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {0, -1, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {0, 1, 0}))
	editor_gizmo_restore_selection(state, &world)
	editor_gizmo_apply_selection_scale(state, &world, {2, 1, 1}, true)
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {-2, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {2, 0, 0}))
}

@(test)
test_multi_selection_parent_and_child_transform_without_double_application :: proc(t: ^testing.T) {
	parent_id := shared.entity_uuid_from_engine_name("multi-parent")
	child_id := shared.entity_uuid_from_engine_name("multi-child")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_transform = true,
			transform = {position = {1, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_transform = true,
			transform = {position = {1, 0, 0}, scale = {1, 1, 1}, parent = parent_id},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	testing.expect(t, ui.init(state) == "")
	_ = ui.editor_select_entity(state, &world, world.entities[0].id, 0)
	_ = ui.editor_select_entity(state, &world, world.entities[1].id, 0, true)
	editor_gizmo_capture_selection(state, &world)
	editor_gizmo_apply_selection_translation(state, &world, {3, 0, 0})
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, {4, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world.transforms[1].position, {1, 0, 0}))
}

@(test)
test_transform_chord_g_starts_free_translation_then_x_constrains_it :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(
		&world.transforms,
		shared.Transform_Component{position = {0, 0, -10}, scale = {1, 1, 1}},
	)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	start := state.editor_gizmo_origin
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Translate}},
	)
	testing.expect(t, state.editor_gizmo_keyboard_active)
	testing.expect(t, state.editor_gizmo_active_handle == .Center)
	free_target := shared.Vec3{1, 1, -10}
	free_pointer, projected := editor_project_world(free_target, viewport, camera, true)
	testing.expect(t, projected)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = free_pointer, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, free_target))
	editor_transform_gizmo_system(
		state,
		&world,
		{position = free_pointer, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Axis_X}},
	)
	testing.expect(t, state.editor_gizmo_keyboard_active)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	expected, solved := editor_gizmo_translation_position(
		{0, 0, -10},
		.X,
		state.editor_gizmo_drag_world_axes,
		start,
		free_pointer,
		viewport,
		camera,
		true,
	)
	testing.expect(t, solved)
	testing.expect(t, gizmo_vec3_near(world.transforms[0].position, expected))
	editor_transform_gizmo_system(
		state,
		&world,
		{position = free_pointer, available = true},
		viewport,
		camera,
		true,
		{escape = true},
	)
	testing.expect(t, state.editor_keyboard_escape_consumed)
	testing.expect(t, world.transforms[0].position == shared.Vec3{0, 0, -10})
	testing.expect(t, !state.editor_gizmo_keyboard_active)
}

@(test)
test_transform_chord_r_starts_view_rotation_then_x_constrains_it :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(
		&world.transforms,
		shared.Transform_Component{position = {0, 0, -10}, scale = {1, 1, 1}},
	)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	start := shared.Vec2{state.editor_gizmo_origin.x + 40, state.editor_gizmo_origin.y}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Rotate}},
	)
	testing.expect(t, state.editor_gizmo_keyboard_active)
	testing.expect(t, state.editor_gizmo_active_handle == .Center)
	drag := shared.Vec2{state.editor_gizmo_origin.x, state.editor_gizmo_origin.y - 40}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, math.abs(world.transforms[0].rotation.z) > 0.1)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Axis_X}},
	)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	testing.expect(t, math.abs(world.transforms[0].rotation.x) > 0.1)
	testing.expect(t, math.abs(world.transforms[0].rotation.y) < 0.001)
	testing.expect(t, math.abs(world.transforms[0].rotation.z) < 0.001)
}

@(test)
test_transform_chord_s_starts_uniform_scale_then_x_constrains_it :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(&world.transforms, shared.Transform_Component{scale = {1, 1, 1}})
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		transform = {position = {0, 0, 10}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	start := state.editor_gizmo_origin
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Scale}},
	)
	testing.expect(t, state.editor_gizmo_keyboard_active)
	testing.expect(t, state.editor_gizmo_active_handle == .Center)
	drag := shared.Vec2{start.x + 30, start.y - 30}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, world.transforms[0].scale.x > 1)
	testing.expect(t, math.abs(world.transforms[0].scale.x - world.transforms[0].scale.y) < 0.001)
	testing.expect(t, math.abs(world.transforms[0].scale.y - world.transforms[0].scale.z) < 0.001)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
		{actions = {.Transform_Axis_X}},
	)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	testing.expect(t, world.transforms[0].scale.x > 1)
	testing.expect(t, math.abs(world.transforms[0].scale.y - 1) < 0.001)
	testing.expect(t, math.abs(world.transforms[0].scale.z - 1) < 0.001)
}

@(test)
test_keyboard_transform_click_commit_consumes_viewport_activation :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(&world.transforms, shared.Transform_Component{scale = {1, 1, 1}})
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	pointer := ui.Pointer_Input {
		position = state.editor_gizmo_origin,
		available = true,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		pointer,
		viewport,
		camera,
		true,
		{actions = {.Transform_Translate}},
	)
	testing.expect(t, state.editor_gizmo_keyboard_active)
	pointer.primary_down = true
	editor_transform_gizmo_system(state, &world, pointer, viewport, camera, true)
	testing.expect(t, !state.editor_gizmo_keyboard_active)
	testing.expect(t, state.editor_previous_primary_down)
}

@(test)
test_transform_gizmo_world_and_local_axes_follow_the_selected_space :: proc(t: ^testing.T) {
	rotation := shared.Vec3{0, 0, math.PI / 2}
	world_axes := editor_gizmo_axes(rotation, .World)
	local_axes := editor_gizmo_axes(rotation, .Local)
	testing.expect(t, gizmo_vec3_near(world_axes[0], {1, 0, 0}))
	testing.expect(t, gizmo_vec3_near(world_axes[1], {0, 1, 0}))
	testing.expect(t, gizmo_vec3_near(local_axes[0], {0, 1, 0}))
	testing.expect(t, gizmo_vec3_near(local_axes[1], {-1, 0, 0}))
	testing.expect(t, gizmo_vec3_near(local_axes[2], {0, 0, 1}))
}

@(test)
test_transform_gizmo_rotation_composes_in_selected_space :: proc(t: ^testing.T) {
	start := shared.Vec3{0, 0, math.PI / 2}
	local_rotation := editor_gizmo_rotated_euler(start, 0, math.PI / 2, .Local)
	world_rotation := editor_gizmo_rotated_euler(start, 0, math.PI / 2, .World)
	local_axes := editor_gizmo_axes(local_rotation, .Local)
	world_result_axes := editor_gizmo_axes(world_rotation, .Local)

	// Local X remains the object's already-rotated X axis. World X rotates that axis in world space.
	testing.expect(t, gizmo_vec3_near(local_axes[0], {0, 1, 0}))
	testing.expect(t, gizmo_vec3_near(world_result_axes[0], {0, 0, 1}))
}

@(test)
test_transform_gizmo_rotation_round_trips_arbitrary_world_and_local_composition :: proc(
	t: ^testing.T,
) {
	start := shared.Vec3{0.31, -0.47, 0.63}
	start_matrix := editor_gizmo_rotation_matrix(start)
	for axis in 0 ..< 3 {
		delta := mat4_identity()
		switch axis {
			case 0:
				delta = mat4_rotate_x(0.28)
			case 1:
				delta = mat4_rotate_y(0.28)
			case 2:
				delta = mat4_rotate_z(0.28)
		}
		for space in shared.Editor_Gizmo_Space {
			expected := mat4_mul(delta, start_matrix)
			if space == .Local {
				expected = mat4_mul(start_matrix, delta)
			}
			actual := editor_gizmo_rotation_matrix(
				editor_gizmo_rotated_euler(start, axis, 0.28, space),
			)
			for column in 0 ..< 3 {
				for row in 0 ..< 3 {
					index := column * 4 + row
					testing.expect(t, math.abs(actual[index] - expected[index]) < 0.001)
				}
			}
		}
	}
}

@(test)
test_transform_gizmo_local_x_translation_uses_and_freezes_the_rotated_axis :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(
		&world.transforms,
		shared.Transform_Component{rotation = {0, 0, math.PI / 2}, scale = {1, 1, 1}},
	)
	state := new(ui.State)
	defer free(state)
	defer ui.destroy(state)
	state.editor_visible = true
	state.editor_has_selection = true
	state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	state.editor_gizmo_space = .Local
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	_, gizmo, ok := ecs.editor_transform_gizmo_entity(&world)
	testing.expect(t, ok && gizmo.space == .Local)
	delta := screen_sub(state.editor_gizmo_endpoints[0], state.editor_gizmo_origin)
	length := screen_length(delta)
	start := shared.Vec2 {
		state.editor_gizmo_origin.x + delta.x * 0.65,
		state.editor_gizmo_origin.y + delta.y * 0.65,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
	)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	testing.expect(t, gizmo_vec3_near(state.editor_gizmo_drag_world_axes[0], {0, 1, 0}))

	// Changing the entity's orientation during the gesture must not move the active rail.
	world.transforms[0].rotation = {}
	state.editor_previous_primary_down = true
	drag := shared.Vec2 {
		start.x + state.editor_gizmo_drag_direction.x * length * 0.5,
		start.y + state.editor_gizmo_drag_direction.y * length * 0.5,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, math.abs(world.transforms[0].position.x) < 0.001)
	testing.expect(t, world.transforms[0].position.y > 0.1)
	testing.expect(t, math.abs(world.transforms[0].position.z) < 0.001)
}

@(test)
test_transform_gizmo_projects_hits_and_drags_world_x :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world); world.entity_by_uuid = make(map[shared.Entity_UUID]int)
	uuid := shared.entity_uuid_from_engine_name("gizmo-history-target")
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			uuid = uuid,
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	world.entity_by_uuid[uuid] = 0
	append_soa(&world.transforms, shared.Transform_Component{scale = {1, 1, 1}})
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_simulation_stopped = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = {500, 350}, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_visible)
	testing.expect(t, world.entities[0].editor_transform_gizmo_index >= 0)
	_, gizmo, has_gizmo := ecs.editor_transform_gizmo_entity(
		&world,
	); testing.expect(t, has_gizmo && gizmo.mode == .Translate)
	x_end :=
		state.editor_gizmo_endpoints[0]; x_delta := screen_sub(x_end, state.editor_gizmo_origin); x_length := screen_length(x_delta)
	testing.expect(t, x_length > 20)
	midpoint := shared.Vec2 {
		state.editor_gizmo_origin.x + x_delta.x * 0.6,
		state.editor_gizmo_origin.y + x_delta.y * 0.6,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = midpoint, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_hovered_handle == .X)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = midpoint, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(
		t,
		state.editor_gizmo_active_handle == .X && state.editor_gizmo_captures_pointer,
	)
	state.editor_previous_primary_down = true
	drag := shared.Vec2 {
		midpoint.x + state.editor_gizmo_drag_direction.x * x_length * 0.5,
		midpoint.y + state.editor_gizmo_drag_direction.y * x_length * 0.5,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, world.transforms[0].position.x > 0.1)
	testing.expect(t, world.transforms[0].position.y == 0 && world.transforms[0].position.z == 0)
	testing.expect(t, state.editor_scene_dirty)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(
		t,
		state.editor_gizmo_active_handle == .None && !state.editor_gizmo_captures_pointer,
	)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_history[0].change_count == 1)
	testing.expect(t, ui.editor_history_apply(state, &world, false))
	testing.expect(t, world.transforms[0].position == shared.Vec3{})
}

@(test)
test_transform_gizmo_hides_for_entities_without_transform :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world); append(&world.entities, shared.World_Entity{id = {index = 0, generation = 1}, alive = true, transform_index = -1, editor_transform_gizmo_index = -1})
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}; state.editor_gizmo_visible = true
	editor_transform_gizmo_system(state, &world, {}, ui.Rect{0, 0, 800, 600}, {}, false)
	testing.expect(t, !state.editor_gizmo_visible)
	testing.expect(t, len(world.editor_transform_gizmos) == 0)
}

@(test)
test_rotation_gizmo_projects_rings_and_rotates_one_axis :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(&world.transforms, shared.Transform_Component{scale = {1, 1, 1}})
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}; state.editor_gizmo_mode = .Rotate
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	testing.expect(t, state.editor_gizmo_visible)
	_, gizmo, ok := ecs.editor_transform_gizmo_entity(
		&world,
	); testing.expect(t, ok && gizmo.mode == .Rotate)

	start := shared.Vec2{}; found := false
	for candidate in state.editor_gizmo_ring_points[0] {
		if editor_gizmo_hit_handle(
			   candidate,
			   state.editor_gizmo_origin,
			   state.editor_gizmo_endpoints,
			   state.editor_gizmo_plane_points,
			   state.editor_gizmo_ring_points,
			   .Rotate,
			   true,
		   ) ==
		   .X { start = candidate; found = true; break }
	}
	testing.expect(t, found)
	if !found { return }
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
	)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	state.editor_previous_primary_down = true
	radial := screen_sub(start, state.editor_gizmo_origin)
	drag := shared.Vec2 {
		state.editor_gizmo_origin.x - radial.y,
		state.editor_gizmo_origin.y + radial.x,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	// Clockwise screen motion maps to negative Euler rotation because screen Y points down.
	testing.expect(
		t,
		world.transforms[0].rotation.x < -1.4 && world.transforms[0].rotation.x > -1.7,
	)
	testing.expect(t, world.transforms[0].rotation.y == 0 && world.transforms[0].rotation.z == 0)
}

@(test)
test_screen_rotation_delta_corrects_inverted_screen_y :: proc(t: ^testing.T) {
	clockwise := screen_rotation_delta({1, 0}, {0, 1})
	counterclockwise := screen_rotation_delta({0, 1}, {1, 0})
	testing.expect(t, clockwise < -1.5 && clockwise > -1.6)
	testing.expect(t, counterclockwise > 1.5 && counterclockwise < 1.6)
}

@(test)
test_scale_gizmo_drags_one_axis_without_moving_entity :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(
		&world.transforms,
		shared.Transform_Component{position = {2, 0, 0}, scale = {1, 1, 1}},
	)
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}; state.editor_gizmo_mode = .Scale
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	delta := screen_sub(
		state.editor_gizmo_endpoints[0],
		state.editor_gizmo_origin,
	); length := screen_length(delta)
	start := shared.Vec2 {
		state.editor_gizmo_origin.x + delta.x * 0.65,
		state.editor_gizmo_origin.y + delta.y * 0.65,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
	)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_active_handle == .X)
	state.editor_previous_primary_down = true
	drag := shared.Vec2 {
		start.x + state.editor_gizmo_drag_direction.x * length * 0.5,
		start.y + state.editor_gizmo_drag_direction.y * length * 0.5,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, world.transforms[0].scale.x > 1.4 && world.transforms[0].scale.x < 1.6)
	testing.expect(t, world.transforms[0].scale.y == 1 && world.transforms[0].scale.z == 1)
	testing.expect(t, world.transforms[0].position == shared.Vec3{2, 0, 0})
}

@(test)
test_transform_gizmo_plane_handles_translate_and_scale_two_axes :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(&world.transforms, shared.Transform_Component{scale = {2, 4, 8}})
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		transform = {position = {4, 4, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	xy :=
		state.editor_gizmo_plane_points[0]; start := shared.Vec2{(xy[0].x + xy[1].x + xy[2].x + xy[3].x) * 0.25, (xy[0].y + xy[1].y + xy[2].y + xy[3].y) * 0.25}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_hovered_handle == .XY)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_active_handle == .XY)
	state.editor_previous_primary_down = true
	drag := shared.Vec2 {
		start.x +
		state.editor_gizmo_drag_screen_axes[0].x * 0.3 +
		state.editor_gizmo_drag_screen_axes[1].x * 0.4,
		start.y +
		state.editor_gizmo_drag_screen_axes[0].y * 0.3 +
		state.editor_gizmo_drag_screen_axes[1].y * 0.4,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(
		t,
		world.transforms[0].position.x > 0 &&
		world.transforms[0].position.y > 0 &&
		world.transforms[0].position.z == 0,
	)

	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
	)
	state.editor_previous_primary_down = false; state.editor_gizmo_mode = .Scale
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	xz := state.editor_gizmo_plane_points[1]; start = {
		x = (xz[0].x + xz[1].x + xz[2].x + xz[3].x) * 0.25,
		y = (xz[0].y + xz[1].y + xz[2].y + xz[3].y) * 0.25,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_hovered_handle == .XZ)
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	state.editor_previous_primary_down = true
	drag = {
		start.x +
		state.editor_gizmo_drag_screen_axes[0].x * 0.25 +
		state.editor_gizmo_drag_screen_axes[2].x * 0.5,
		start.y +
		state.editor_gizmo_drag_screen_axes[0].y * 0.25 +
		state.editor_gizmo_drag_screen_axes[2].y * 0.5,
	}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, world.transforms[0].scale.x > 2.74 && world.transforms[0].scale.x < 2.76)
	testing.expect(t, world.transforms[0].scale.y == 4)
	testing.expect(t, world.transforms[0].scale.z > 10.99 && world.transforms[0].scale.z < 11.01)
	testing.expect(t, world.transforms[0].scale.z / world.transforms[0].scale.x == 4)
}

@(test)
test_transform_gizmo_center_handle_free_translates_and_uniformly_scales :: proc(t: ^testing.T) {
	world: shared.World; defer ecs.destroy_world(&world)
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
	)
	append_soa(&world.transforms, shared.Transform_Component{scale = {1, 1, 1}})
	state := new(
		ui.State,
	); defer free(state); defer ui.destroy(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}
	camera := shared.Camera_Instance {
		transform = {position = {0, 0, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{240, 48, 740, 644}
	editor_transform_gizmo_system(state, &world, {}, viewport, camera, true)
	start := state.editor_gizmo_origin
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, state.editor_gizmo_active_handle == .Center)
	state.editor_previous_primary_down = true; drag := shared.Vec2{start.x + 30, start.y - 20}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(
		t,
		world.transforms[0].position.x > 0 &&
		world.transforms[0].position.y > 0 &&
		world.transforms[0].position.z == 0,
	)

	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, available = true},
		viewport,
		camera,
		true,
	)
	state.editor_previous_primary_down = false; state.editor_gizmo_mode = .Scale
	editor_transform_gizmo_system(
		state,
		&world,
		{},
		viewport,
		camera,
		true,
	); start = state.editor_gizmo_origin
	editor_transform_gizmo_system(
		state,
		&world,
		{position = start, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	state.editor_previous_primary_down = true; drag = {start.x + 32, start.y - 32}
	editor_transform_gizmo_system(
		state,
		&world,
		{position = drag, primary_down = true, available = true},
		viewport,
		camera,
		true,
	)
	testing.expect(t, world.transforms[0].scale.x > 1.45 && world.transforms[0].scale.x < 1.55)
	testing.expect(
		t,
		world.transforms[0].scale.x == world.transforms[0].scale.y &&
		world.transforms[0].scale.y == world.transforms[0].scale.z,
	)
}
