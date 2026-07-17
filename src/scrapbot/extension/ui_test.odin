package extension

import raw "../extension_api"
import c "core:c"
import "core:testing"

UI_Test_Host :: struct {
	set_calls: int,
	spawn_calls: int,
	last_size: f32,
	last_text: [32]u8,
	last_text_len: int,
}

@(test)
test_ui_helpers_preserve_styles_and_use_the_shared_native_contract :: proc(t: ^testing.T) {
	layout := ui_layout_default()
	layout.size = {320, 180}
	layout.background = {0.02, 0.03, 0.04, 1}
	layout.border_width = 1
	layout.border_color = {0.2, 0.24, 0.3, 1}
	layout.corner_radius = 9
	layout_payload := ui_layout(layout)
	testing.expect(t, layout_payload.component == UI_LAYOUT)
	testing.expect(t, layout_payload.layout.corner_radius == 9)
	testing.expect(t, layout_payload.layout.background.w == 1)
	progress_style := ui_progress_default()
	progress_style.value = 4
	progress_style.maximum = 10
	progress_style.fill_color = {0.2, 0.8, 0.6, 1}
	progress_style.inset = {2, 3, 4, 5}
	progress_style.corner_radius = 2
	progress_style.right_to_left = 1
	progress_payload := ui_progress(progress_style)
	testing.expect(t, progress_payload.component == UI_PROGRESS)
	testing.expect(t, progress_payload.progress.maximum == 10)
	testing.expect(t, progress_payload.progress.corner_radius == 2)
	scroll_style := ui_scroll_area_default()
	testing.expect(t, scroll_style.scrollbar_width == 3)
	testing.expect(t, scroll_style.scrollbar_corner_radius == 1.5)
	scroll_style.scrollbar_corner_radius = 0
	scroll_payload := ui_scroll_area(scroll_style)
	testing.expect(t, scroll_payload.scroll_area.scrollbar_corner_radius == 0)
	table_style := ui_table_default()
	testing.expect(t, table_style.columns == 1)
	testing.expect(t, table_style.min_column_width == 32)
	table_style.columns = 2
	table_style.proportional_columns = 1
	table_style.resizable_columns = 1
	table_payload := ui_table(table_style)
	testing.expect(t, table_payload.component == UI_TABLE)
	testing.expect(t, table_payload.table.proportional_columns != 0)
	testing.expect(t, table_payload.table.resizable_columns != 0)
	panel_style := ui_panel_default()
	testing.expect(t, panel_style.action_size == 22)
	panel_style.action_enabled = 1
	panel_style.action_size = 20
	panel_style.action_icon_inset = 5
	panel_style.action_color = {0.8, 0.7, 0.6, 1}
	panel_payload, panel_ok := ui_panel(panel_style, "Closable", "Inter")
	testing.expect(t, panel_ok)
	testing.expect(t, panel_payload.panel.action_enabled != 0)
	testing.expect(t, panel_payload.panel.action_icon_inset == 5)
	testing.expect(t, panel_payload.panel.action_color.x == 0.8)

	text_style := ui_text_default()
	text_style.size = 13
	text_style.color = {0.8, 0.85, 0.9, 1}
	text_style.alignment = .Right
	text_payload, ok := ui_text(text_style, "Shared UI", "Inter")
	testing.expect(t, ok)
	testing.expect(t, ui_payload_text(&text_payload) == "Shared UI")
	testing.expect(t, ui_payload_font(&text_payload) == "Inter")
	testing.expect(t, text_payload.text.alignment == .Right)
	button_style := ui_button_default()
	testing.expect(t, button_style.alignment == .Center)
	button_style.alignment = .Right
	button_payload, button_ok := ui_button(button_style, "Aligned", "Inter")
	testing.expect(t, button_ok)
	testing.expect(t, button_payload.button.alignment == .Right)
	input_style := ui_input_default()
	input_style.prefix_width = 13
	input_style.number = 42
	input_style.step = 0.5
	input_style.minimum = 0
	input_style.maximum = 100
	input_style.numeric = 1
	input_style.has_minimum = 1
	input_style.has_maximum = 1
	input_style.prefix_gap = 4
	input_style.prefix_corner_radius = 0
	input_style.invalid_border_width = 3
	input_payload, input_ok := ui_input(input_style, "42", "Inter", "X")
	testing.expect(t, input_ok)
	testing.expect(t, ui_payload_text(&input_payload) == "42")
	testing.expect(t, ui_payload_prefix(&input_payload) == "X")
	testing.expect(t, input_payload.input.number == 42 && input_payload.input.step == 0.5)
	testing.expect(t, input_payload.input.prefix_gap == 4)
	testing.expect(t, input_payload.input.prefix_corner_radius == 0)
	checkbox_style := ui_checkbox_default()
	checkbox_style.corner_radius = 0
	checkbox_style.border_width = 2
	checkbox_payload := ui_checkbox(checkbox_style)
	testing.expect(t, checkbox_payload.checkbox.corner_radius == 0)
	testing.expect(t, checkbox_payload.checkbox.border_width == 2)

	host: UI_Test_Host
	ctx := System_Context {
		host = &host,
		get_ui_component = ui_test_get,
		set_ui_component = ui_test_set,
		spawn = ui_test_spawn,
	}
	entity := Entity {
		index = 4,
		generation = 2,
	}
	read_payload, found := get_ui(&ctx, entity, UI_Text_Component)
	testing.expect(t, found)
	testing.expect(t, ui_payload_text(&read_payload) == "Read through SDK")
	testing.expect(t, read_payload.text.size == 14)

	read_payload.text.size = 17
	testing.expect(t, ui_payload_set_strings(&read_payload, "Updated", "Project Font"))
	testing.expect(t, set_ui(&ctx, entity, &read_payload) == nil)
	testing.expect(t, host.set_calls == 1)
	testing.expect(t, host.last_size == 17)
	testing.expect(t, string(host.last_text[:host.last_text_len]) == "Updated")

	components := [?]UI_Component_Payload{layout_payload, text_payload}
	options := spawn_options_with_ui("SDK Spawn", components[:])
	uuid, err := spawn_with_uuid(&ctx, &options)
	testing.expect(t, err == nil)
	testing.expect(t, host.spawn_calls == 1)
	testing.expect(t, options.out_uuid == nil)
	testing.expect(t, uuid.bytes[0] == 0x53)
	testing.expect(t, uuid.bytes[15] == 0x42)
}

ui_test_get :: proc "c" (
	ctx: ^raw.System_Context,
	entity: raw.Entity,
	component: cstring,
	payload: ^raw.UI_Component_Payload,
) -> c.int {
	if ctx == nil ||
	   entity.index != 4 ||
	   entity.generation != 2 ||
	   component == nil ||
	   string(component) != UI_TEXT ||
	   payload == nil {
		return 0
	}
	payload^ = {}
	payload.component = UI_TEXT
	payload.text = ui_text_default()
	payload.text.size = 14
	if !ui_payload_set_strings(payload, "Read through SDK", "Inter") {
		return 0
	}
	return 1
}

ui_test_set :: proc "c" (
	ctx: ^raw.System_Context,
	entity: raw.Entity,
	payload: ^raw.UI_Component_Payload,
) -> cstring {
	if ctx == nil || ctx.host == nil || entity.index != 4 || payload == nil {
		return "invalid UI test set"
	}
	host := cast(^UI_Test_Host)ctx.host
	host.set_calls += 1
	host.last_size = payload.text.size
	value := ui_payload_text(payload)
	if len(value) > len(host.last_text) {
		return "UI test value is too long"
	}
	copy(host.last_text[:], transmute([]u8)value)
	host.last_text_len = len(value)
	return nil
}

ui_test_spawn :: proc "c" (ctx: ^raw.System_Context, options: ^raw.Spawn_Options) -> cstring {
	if ctx == nil ||
	   ctx.host == nil ||
	   options == nil ||
	   options.ui_components == nil ||
	   options.ui_component_count != 2 ||
	   options.out_uuid == nil {
		return "invalid UI test spawn"
	}
	host := cast(^UI_Test_Host)ctx.host
	host.spawn_calls += 1
	options.out_uuid.bytes[0] = 0x53
	options.out_uuid.bytes[15] = 0x42
	return nil
}
