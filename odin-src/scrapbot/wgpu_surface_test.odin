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
	testing.expect_value(t, surface_ctx.width, u32(320))
	testing.expect_value(t, surface_ctx.height, u32(240))
}
