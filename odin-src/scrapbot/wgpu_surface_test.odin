package main

import "core:os"
import "core:testing"

@(test)
test_wgpu_surface_choose_format_uses_capability_when_available :: proc(t: ^testing.T) {
	formats := [?]WGPU_Texture_Format{WGPU_TEXTURE_FORMAT_RGBA8_UNORM, WGPU_DEFAULT_TARGET_FORMAT}
	capabilities := WGPU_Surface_Capabilities{
		format_count = 2,
		formats = &formats[0],
	}
	testing.expect_value(t, wgpu_surface_choose_format(capabilities), WGPU_TEXTURE_FORMAT_RGBA8_UNORM)
}

@(test)
test_wgpu_surface_choose_modes_prefer_fifo_and_auto_when_supported :: proc(t: ^testing.T) {
	present_modes := [?]WGPU_Present_Mode{WGPU_PRESENT_MODE_IMMEDIATE, WGPU_PRESENT_MODE_FIFO}
	alpha_modes := [?]WGPU_Composite_Alpha_Mode{WGPU_COMPOSITE_ALPHA_MODE_OPAQUE, WGPU_COMPOSITE_ALPHA_MODE_AUTO}
	capabilities := WGPU_Surface_Capabilities{
		present_mode_count = 2,
		present_modes = &present_modes[0],
		alpha_mode_count = 2,
		alpha_modes = &alpha_modes[0],
	}
	testing.expect_value(t, wgpu_surface_choose_present_mode(capabilities), WGPU_PRESENT_MODE_FIFO)
	testing.expect_value(t, wgpu_surface_choose_alpha_mode(capabilities), WGPU_COMPOSITE_ALPHA_MODE_AUTO)
}

@(test)
test_wgpu_surface_choose_modes_fall_back_to_first_supported_value :: proc(t: ^testing.T) {
	present_modes := [?]WGPU_Present_Mode{WGPU_PRESENT_MODE_MAILBOX, WGPU_PRESENT_MODE_IMMEDIATE}
	alpha_modes := [?]WGPU_Composite_Alpha_Mode{WGPU_COMPOSITE_ALPHA_MODE_OPAQUE, WGPU_COMPOSITE_ALPHA_MODE_PREMULTIPLIED}
	capabilities := WGPU_Surface_Capabilities{
		present_mode_count = 2,
		present_modes = &present_modes[0],
		alpha_mode_count = 2,
		alpha_modes = &alpha_modes[0],
	}
	testing.expect_value(t, wgpu_surface_choose_present_mode(capabilities), WGPU_PRESENT_MODE_MAILBOX)
	testing.expect_value(t, wgpu_surface_choose_alpha_mode(capabilities), WGPU_COMPOSITE_ALPHA_MODE_OPAQUE)
}

@(test)
test_wgpu_surface_texture_presentable_statuses_are_explicit :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_surface_texture_status_is_presentable(WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL), true)
	testing.expect_value(t, wgpu_surface_texture_status_is_presentable(WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL), true)
	testing.expect_value(t, wgpu_surface_texture_status_is_presentable(WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED), false)
	testing.expect_value(t, wgpu_surface_texture_status_label(WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_DEVICE_LOST), "device-lost")
}

@(test)
test_wgpu_surface_context_presents_scene_frames_and_reconfigures :: proc(t: ^testing.T) {
	resolver_context := WGPU_Test_Resolver_Context{}
	procs, missing, procs_ok := wgpu_resolve_offscreen_procs(wgpu_test_symbol_resolver, rawptr(&resolver_context))
	testing.expect_value(t, procs_ok, true)
	testing.expect_value(t, missing, "")

	root := make_test_project_root(t, "wgpu-surface-context-scene")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "WGPU Surface Context"), Project_Error.None)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)

	surface_ctx, init_error, init_ok := wgpu_surface_context_init(procs, (^WGPU_Surface_Descriptor)(nil), 640, 480)
	defer wgpu_surface_context_deinit(&surface_ctx)
	testing.expect_value(t, init_ok, true)
	testing.expect_value(t, init_error, "")
	testing.expect_value(t, surface_ctx.configured, true)
	testing.expect_value(t, surface_ctx.width, u32(640))
	testing.expect_value(t, surface_ctx.height, u32(480))

	report, present_error, present_ok := wgpu_surface_context_present_scene_frame(&surface_ctx, result.scene.world, 320, 240)
	testing.expect_value(t, present_ok, true)
	testing.expect_value(t, present_error, "")
	testing.expect_value(t, report.width, u32(320))
	testing.expect_value(t, report.height, u32(240))
	testing.expect_value(t, report.renderable_count, 1)
	testing.expect_value(t, report.overlay_count, 0)
	testing.expect_value(t, surface_ctx.width, u32(320))
	testing.expect_value(t, surface_ctx.height, u32(240))

	overlay_report, overlay_error, overlay_ok := wgpu_surface_context_present_scene_frame(&surface_ctx, result.scene.world, 320, 240, true)
	testing.expect_value(t, overlay_ok, true)
	testing.expect_value(t, overlay_error, "")
	testing.expect_value(t, overlay_report.renderable_count, 1)
	testing.expect_value(t, overlay_report.overlay_count > 0, true)
}

@(test)
test_wgpu_editor_chrome_vertices_append_overlay_rects :: proc(t: ^testing.T) {
	vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(vertices)

	count := wgpu_append_editor_chrome_vertices(&vertices, 640, 480)
	testing.expect_value(t, count > 0, true)
	testing.expect_value(t, len(vertices), count * 6)

	zero_count := wgpu_append_editor_chrome_vertices(&vertices, 0, 480)
	testing.expect_value(t, zero_count, 0)
}

@(test)
test_wgpu_editor_selected_inspector_vertices_append_typed_controls :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-editor-selected-inspector-vertices")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "WGPU Editor Selected Inspector Vertices"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Controls = ecs.component("controls", {
  fields = ecs.fields({
    enabled = "boolean",
    count = "int",
    speed = "float",
    label = "string",
    tint = "vec3",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Typed Inspector Controls"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.controls]
enabled = true
count = 2
speed = 1.5
label = "alpha"
tint = [1.0, 0.5, 0.25]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)

	base_vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(base_vertices)
	base_count := wgpu_append_editor_chrome_vertices(&base_vertices, 320, 240)

	vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(vertices)
	selected_count := wgpu_append_editor_chrome_vertices_for_selection(&vertices, result.scene.world, 320, 240, "target")
	testing.expect_value(t, selected_count > base_count, true)
	testing.expect_value(t, len(vertices), selected_count * 6)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_SELECTION_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_BOOL_ON_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_TOGGLE_KNOB_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_STRING_CONTROL_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_VEC3_X_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_VEC3_Y_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_CHROME_INSPECTOR_VEC3_Z_COLOR)
}

@(test)
test_wgpu_editor_selected_vertices_append_gizmo_axes :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-editor-selected-gizmo-vertices")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "WGPU Editor Gizmo Vertices"), Project_Error.None)
	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)

	vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(vertices)
	count := wgpu_append_editor_chrome_vertices_for_selection(&vertices, result.scene.world, 320, 240, "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001", 0, .Y)
	testing.expect_value(t, count > 0, true)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_GIZMO_AXIS_X_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_GIZMO_AXIS_ACTIVE_COLOR)
	expect_wgpu_vertex_color(t, vertices[:], EDITOR_GIZMO_AXIS_Z_COLOR)

	hover_vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(hover_vertices)
	hover_count := wgpu_append_editor_chrome_vertices_for_selection(&hover_vertices, result.scene.world, 320, 240, "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001", 0, .None, .Z)
	testing.expect_value(t, hover_count > 0, true)
	expect_wgpu_vertex_color(t, hover_vertices[:], EDITOR_GIZMO_AXIS_HOVER_COLOR)

	entity, entity_ok := runtime_world_find_entity_by_id(result.scene.world, "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001")
	testing.expect_value(t, entity_ok, true)
	set_err := runtime_world_set_component_field_value(&result.scene.world, entity, TRANSFORM_COMPONENT_ID, "rotation", runtime_component_value_vec3([3]f32{0, 0, 1.5707964}))
	testing.expect_value(t, set_err, Runtime_Error.None)
	local_vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(local_vertices)
	local_count := wgpu_append_editor_chrome_vertices_for_selection(&local_vertices, result.scene.world, 320, 240, "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001", 0, .X, .None, true)
	testing.expect_value(t, local_count > 0, true)
	x_span, y_span, span_ok := wgpu_vertex_color_position_span(local_vertices[:], EDITOR_GIZMO_AXIS_ACTIVE_COLOR)
	testing.expect_value(t, span_ok, true)
	testing.expect_value(t, y_span > x_span * 1.5, true)
}

expect_wgpu_vertex_color :: proc(t: ^testing.T, vertices: []WGPU_Scene_Vertex, color: [3]u8) {
	expected := [3]f32{f32(color[0]) / 255.0, f32(color[1]) / 255.0, f32(color[2]) / 255.0}
	for vertex in vertices {
		if wgpu_vertex_color_equal(vertex.color, expected) {
			return
		}
	}
	testing.fail_now(t, "expected WebGPU overlay vertex color not found")
}

wgpu_vertex_color_equal :: proc(actual, expected: [3]f32) -> bool {
	epsilon := f32(0.0001)
	return wgpu_f32_close(actual[0], expected[0], epsilon) &&
	       wgpu_f32_close(actual[1], expected[1], epsilon) &&
	       wgpu_f32_close(actual[2], expected[2], epsilon)
}

wgpu_vertex_color_position_span :: proc(vertices: []WGPU_Scene_Vertex, color: [3]u8) -> (x_span, y_span: f32, ok: bool) {
	expected := [3]f32{f32(color[0]) / 255.0, f32(color[1]) / 255.0, f32(color[2]) / 255.0}
	min_x := f32(0)
	max_x := f32(0)
	min_y := f32(0)
	max_y := f32(0)
	found := false
	for vertex in vertices {
		if !wgpu_vertex_color_equal(vertex.color, expected) {
			continue
		}
		if !found {
			min_x = vertex.position[0]
			max_x = vertex.position[0]
			min_y = vertex.position[1]
			max_y = vertex.position[1]
			found = true
			continue
		}
		min_x = min_f32(min_x, vertex.position[0])
		max_x = max_f32(max_x, vertex.position[0])
		min_y = min_f32(min_y, vertex.position[1])
		max_y = max_f32(max_y, vertex.position[1])
	}
	if !found {
		return 0, 0, false
	}
	return max_x - min_x, max_y - min_y, true
}

wgpu_f32_close :: proc(actual, expected, epsilon: f32) -> bool {
	diff := actual - expected
	if diff < 0 {
		diff = -diff
	}
	return diff <= epsilon
}
