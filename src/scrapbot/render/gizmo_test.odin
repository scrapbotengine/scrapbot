package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:testing"

@(test)
test_transform_gizmo_projects_hits_and_drags_world_x :: proc(t: ^testing.T) {
	world: shared.World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos); world.entity_by_uuid = make(map[shared.Entity_UUID]int); defer delete(world.entity_by_uuid)
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
	world: shared.World; defer delete(world.entities); defer delete(world.editor_transform_gizmos); append(&world.entities, shared.World_Entity{id = {index = 0, generation = 1}, alive = true, transform_index = -1, editor_transform_gizmo_index = -1})
	state := new(
		ui.State,
	); defer free(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
		index = 0,
		generation = 1,
	}; state.editor_gizmo_visible = true
	editor_transform_gizmo_system(state, &world, {}, ui.Rect{0, 0, 800, 600}, {}, false)
	testing.expect(t, !state.editor_gizmo_visible)
	testing.expect(t, len(world.editor_transform_gizmos) == 0)
}

@(test)
test_rotation_gizmo_projects_rings_and_rotates_one_axis :: proc(t: ^testing.T) {
	world: shared.World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos)
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
	); defer free(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
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
	world: shared.World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos)
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
	); defer free(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
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
	world: shared.World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos)
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
	); defer free(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
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
	testing.expect(t, world.transforms[0].scale.x > 1.24 && world.transforms[0].scale.x < 1.26)
	testing.expect(t, world.transforms[0].scale.y == 1)
	testing.expect(t, world.transforms[0].scale.z > 1.49 && world.transforms[0].scale.z < 1.51)
}

@(test)
test_transform_gizmo_center_handle_free_translates_and_uniformly_scales :: proc(t: ^testing.T) {
	world: shared.World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos)
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
	); defer free(state); state.editor_visible = true; state.editor_has_selection = true; state.editor_selected_entity = {
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
