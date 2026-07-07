package main

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
