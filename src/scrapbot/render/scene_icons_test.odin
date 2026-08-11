package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:testing"

@(test)
test_editor_scene_icons_cover_project_cameras_and_lights :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Project Camera",
			has_transform = true,
			transform = {position = {-2, 0, 0}, scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 100},
		},
		shared.Scene_Entity {
			name = "Sun",
			has_directional_light = true,
			directional_light = {direction = {0, -1, 0}, color = {1, 1, 1}, intensity = 1},
		},
		shared.Scene_Entity {
			name = "Lamp",
			has_transform = true,
			transform = {position = {2, 0, 0}, scale = {1, 1, 1}},
			has_point_light = true,
			point_light = {color = {1, 0.5, 0.25}, intensity = 2, range = 8},
		},
		shared.Scene_Entity {
			name = "Camera Lamp",
			has_transform = true,
			transform = {position = {0, 2, 0}, scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 100},
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 4},
		},
		shared.Scene_Entity {
			name = "Transformless Lamp",
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 4},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	ecs.editor_scene_camera_system(&world, {}, 0, true)

	state := new(ui.State)
	defer free(state)
	state.editor_visible = true
	state.editor_pixel_density = 1
	state.editor_has_selection = true
	state.editor_selected_entity = world.entities[2].id
	view_camera := shared.Camera_Instance {
		transform = {position = {0, 0, 8}, scale = {1, 1, 1}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	viewport := ui.Rect{20, 30, 800, 600}

	editor_scene_icon_system(state, &world, viewport, view_camera, true, true)

	testing.expect_value(t, state.editor_scene_icon_count, 4)
	testing.expect_value(t, state.editor_scene_icons[0].kind, ui.Editor_Scene_Icon_Kind.Camera)
	testing.expect_value(
		t,
		state.editor_scene_icons[2].kind,
		ui.Editor_Scene_Icon_Kind.Directional_Light,
	)
	testing.expect_value(
		t,
		state.editor_scene_icons[3].kind,
		ui.Editor_Scene_Icon_Kind.Point_Light,
	)
	testing.expect(t, state.editor_scene_icons[3].selected)
	for icon in state.editor_scene_icons[:state.editor_scene_icon_count] {
		testing.expect_value(t, icon.clip, viewport)
		testing.expect(
			t,
			icon.center.x >= viewport.x && icon.center.x <= viewport.x + viewport.width,
		)
		testing.expect(
			t,
			icon.center.y >= viewport.y && icon.center.y <= viewport.y + viewport.height,
		)
	}

	picked, found := editor_pick_scene_icon(state, state.editor_scene_icons[3].center)
	testing.expect(t, found && picked == world.entities[2].id)
	_, found = editor_pick_scene_icon(state, {viewport.x - 1, viewport.y - 1})
	testing.expect(t, !found)

	editor_scene_icon_system(state, &world, viewport, view_camera, true, false)
	testing.expect_value(t, state.editor_scene_icon_count, 0)
}

@(test)
test_editor_scene_icon_projection_keeps_constant_screen_size_data :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Near Lamp",
			has_transform = true,
			transform = {position = {-1, 0, 4}, scale = {1, 1, 1}},
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 4},
		},
		shared.Scene_Entity {
			name = "Far Lamp",
			has_transform = true,
			transform = {position = {1, 0, -20}, scale = {1, 1, 1}},
			has_point_light = true,
			point_light = {color = {1, 1, 1}, intensity = 1, range = 4},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	state.editor_visible = true
	state.editor_pixel_density = 2
	view_camera := shared.Camera_Instance {
		transform = {position = {0, 0, 8}, scale = {1, 1, 1}},
		camera = {fov = 60, near = 0.1, far = 100},
	}

	editor_scene_icon_system(state, &world, {0, 0, 800, 600}, view_camera, true, true)
	testing.expect_value(t, state.editor_scene_icon_count, 2)
	radius := EDITOR_SCENE_ICON_PICK_RADIUS * state.editor_pixel_density
	for icon in state.editor_scene_icons[:state.editor_scene_icon_count] {
		_, found := editor_pick_scene_icon(state, {icon.center.x + radius - 0.1, icon.center.y})
		testing.expect(t, found)
	}
}
