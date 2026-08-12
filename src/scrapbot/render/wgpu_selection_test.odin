package render

import shared "../shared"
import ui "../ui"
import "core:testing"

@(test)
test_gpu_selection_request_maps_output_viewport_into_render_target :: proc(t: ^testing.T) {
	state := new(ui.State)
	defer free(state)
	state.editor_box_select_requested = true
	state.editor_box_select_request_rect = {300, 200, 200, 100}
	state.editor_box_select_request_toggle_selection = true
	request, marquee, toggle, found := wgpu_selection_request_rect(
		state,
		{100, 50, 800, 600},
		400,
		300,
	)
	testing.expect(t, found)
	testing.expect(t, marquee)
	testing.expect(t, toggle)
	testing.expect_value(t, request, ui.Rect{100, 75, 100, 50})

	state.editor_box_select_requested = false
	state.editor_pick_requested = true
	state.editor_pick_position = {500, 350}
	request, marquee, _, found = wgpu_selection_request_rect(state, {100, 50, 800, 600}, 800, 600)
	testing.expect(t, found)
	testing.expect(t, !marquee)
	testing.expect_value(t, request, ui.Rect{399, 299, 3, 3})
}

@(test)
test_gpu_marquee_visibility_intersects_identity_with_contained_roots :: proc(t: ^testing.T) {
	inside, _ := shared.entity_uuid_parse("a7000000-0000-4000-8000-000000000061")
	outside, _ := shared.entity_uuid_parse("a7000000-0000-4000-8000-000000000062")
	readback := WGPU_Selection_Readback {
		marquee = true,
	}
	defer delete(readback.contained_uuids)
	append(&readback.contained_uuids, inside)
	testing.expect(t, wgpu_selection_uuid_allowed(&readback, inside))
	testing.expect(t, !wgpu_selection_uuid_allowed(&readback, outside))
	readback.marquee = false
	testing.expect(t, wgpu_selection_uuid_allowed(&readback, outside))
}
