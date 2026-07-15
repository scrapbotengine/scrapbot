package project

import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_project_config_requires_safe_scene_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo"
default_scene = "../outside.scene.toml"
`,
	)
	testing.expect(t, result.err == .Invalid_Path)
	testing.expect(t, config.default_scene == "../outside.scene.toml")
}

@(test)
test_project_config_accepts_project_toml_shape :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo #1" # comments are allowed outside strings
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .None)
	testing.expect(t, config.name == "Demo #1")
	testing.expect(t, config.default_scene == "scenes/main.scene.toml")
	testing.expect(t, len(config.native_extensions) == 1)
	testing.expect(t, config.native_extensions[0].name == "scrappyphysics")
	testing.expect(t, config.native_extensions[0].source == "native/scrappyphysics")
}

@(test)
test_project_config_accepts_project_fonts :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"

[[fonts]]
name = "display"
source = "assets/fonts/display.otf"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .None)
	testing.expect(t, len(config.fonts) == 1)
	if len(config.fonts) == 1 {
		testing.expect(t, config.fonts[0].name == "display")
		testing.expect(t, config.fonts[0].source == "assets/fonts/display.otf")
	}
}

@(test)
test_project_config_rejects_unsafe_or_duplicate_fonts :: proc(t: ^testing.T) {
	unsafe, unsafe_result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"
[[fonts]]
name = "display"
source = "../display.ttf"
`,
	)
	defer destroy_project_config(&unsafe)
	testing.expect(t, unsafe_result.err == .Invalid_Path)

	duplicate, duplicate_result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"
[[fonts]]
name = "display"
source = "assets/fonts/first.ttf"
[[fonts]]
name = "display"
source = "assets/fonts/second.ttf"
`,
	)
	defer destroy_project_config(&duplicate)
	testing.expect(t, duplicate_result.err == .Invalid_Field)
}

@(test)
test_scene_font_references_must_be_declared_by_the_project :: proc(t: ^testing.T) {
	config := shared.Project_Config{}
	defer destroy_project_config(&config)
	append(&config.fonts, shared.Project_Font{name = "display", source = "assets/display.ttf"})
	scene := shared.Scene{}
	defer destroy_scene(&scene)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Title",
			has_ui_layout = true,
			has_ui_text = true,
			ui_text = {text = "Hello", font = "missing"},
		},
	)
	testing.expect(t, validate_scene_font_references(&scene, &config) != "")
	scene.entities[0].ui_text.font = "display"
	testing.expect(t, validate_scene_font_references(&scene, &config) == "")
}

@(test)
test_project_config_rejects_unescaped_string_bodies :: proc(t: ^testing.T) {
	_, result := parse_project_config(
		"name = \"Bad \\ Game\"\ndefault_scene = \"scenes/main.scene.toml\"\n",
	)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_project_config_requires_safe_native_extension_source_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "faststuff"
source = "../faststuff"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .Invalid_Path)
}

@(test)
test_default_scene_template_mints_fresh_entity_ids :: proc(t: ^testing.T) {
	first_source := default_scene_template()
	second_source := default_scene_template()
	first, first_result := parse_scene(first_source)
	defer destroy_scene(&first)
	second, second_result := parse_scene(second_source)
	defer destroy_scene(&second)
	testing.expect(t, first_result.err == .None && second_result.err == .None)
	testing.expect(t, len(first.entities) == 2 && len(second.entities) == 2)
	if len(first.entities) == 2 && len(second.entities) == 2 {
		testing.expect(t, first.entities[0].id != first.entities[1].id)
		testing.expect(t, first.entities[0].id != second.entities[0].id)
		testing.expect(t, first.entities[1].id != second.entities[1].id)
	}
}

@(test)
test_scene_accepts_namespaced_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000001"
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, len(scene.entities[0].custom_components) == 1)
	testing.expect(t, scene.entities[0].custom_components[0].name == "scrappyphysics.rigidbody")
}

@(test)
test_scene_rejects_malformed_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000002"
name = "Body"

[entities.components.scrappyphysics..rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_requires_valid_unique_entity_ids :: proc(t: ^testing.T) {
	missing_scene, missing_result := parse_scene(`[[entities]]
name = "Missing ID"
`)
	defer destroy_scene(&missing_scene)
	testing.expect(t, missing_result.err == .Missing_Field)

	invalid_scene, invalid_result := parse_scene(
		`[[entities]]
id = "not-a-uuid"
name = "Invalid ID"
`,
	)
	defer destroy_scene(&invalid_scene)
	testing.expect(t, invalid_result.err == .Invalid_Field)

	duplicate_scene, duplicate_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000020"
name = "First"

[[entities]]
id = "a6000000-0000-4000-8000-000000000020"
name = "Second"
`,
	)
	defer destroy_scene(&duplicate_scene)
	testing.expect(t, duplicate_result.err == .Invalid_Field)
}

@(test)
test_scene_component_fields_are_single_tokens :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000003"
name = "Body"

[entities.components.autorotate]
rotation.velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_parses_engine_light_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000004"
name = "Ambient"
[entities.ambient_light]
color = [0.2, 0.3, 0.4]
intensity = 0.5

[[entities]]
id = "a6000000-0000-4000-8000-000000000005"
name = "Sun"
[entities.directional_light]
direction = [-1, -2, -3]
color = [1, 0.9, 0.8]
intensity = 1.25

[[entities]]
id = "a6000000-0000-4000-8000-000000000006"
name = "Lamp"
[entities.point_light]
color = [0.1, 0.4, 1]
intensity = 8
range = 12
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 3)
	testing.expect(t, scene.entities[0].has_ambient_light)
	testing.expect(t, scene.entities[0].ambient_light.color.z == 0.4)
	testing.expect(t, scene.entities[1].has_directional_light)
	testing.expect(t, scene.entities[1].directional_light.direction.y == -2)
	testing.expect(t, scene.entities[2].has_point_light)
	testing.expect(t, scene.entities[2].point_light.intensity == 8)
	testing.expect(t, scene.entities[2].point_light.range == 12)
}

@(test)
test_scene_parses_shadow_marker_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000007"
name = "Cube"
[entities.shadow_caster]
[entities.shadow_receiver]
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, scene.entities[0].has_shadow_caster)
	testing.expect(t, scene.entities[0].has_shadow_receiver)
}

@(test)
test_project_check_accepts_registered_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000008"
name = "Body"

[entities.components.scrapbot.transform]
position = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, validate_namespaced_scene_components(&scene) == "")
}

@(test)
test_project_check_rejects_unknown_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000009"
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(
		t,
		validate_namespaced_scene_components(&scene) ==
		`scene component "scrappyphysics.rigidbody" is not registered`,
	)
}

@(test)
test_init_project_writes_luau_lsp_metadata :: proc(t: ^testing.T) {
	parent, temp_err := os.make_directory_temp("", "scrapbot-init-*", context.temp_allocator)
	testing.expect(t, temp_err == nil)
	defer os.remove_all(parent)

	root, join_root_err := filepath.join({parent, "project"})
	testing.expect(t, join_root_err == nil)
	defer delete(root)
	defer os.remove_all(root)

	init_err := init_project(root, "Typed Demo")
	testing.expect(t, init_err == "")

	types_path, join_types_err := filepath.join({root, DEFAULT_LUAU_TYPES})
	testing.expect(t, join_types_err == nil)
	defer delete(types_path)
	settings_path, join_settings_err := filepath.join({root, DEFAULT_VSCODE_SETTINGS})
	testing.expect(t, join_settings_err == nil)
	defer delete(settings_path)

	types_bytes, types_err := os.read_entire_file(types_path, context.temp_allocator)
	testing.expect(t, types_err == nil)
	expected_types := default_luau_types_template()
	defer delete(expected_types)
	testing.expect(t, string(types_bytes) == expected_types)

	settings_bytes, settings_err := os.read_entire_file(settings_path, context.temp_allocator)
	testing.expect(t, settings_err == nil)
	testing.expect(t, string(settings_bytes) == default_vscode_settings_template())
}
@(test)
test_scene_parses_ecs_ui_hierarchy :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000a"
name = "HUD"
[entities.ui_layout]
position = [20, 30]
size = [400, 200]
padding = [12, 12, 12, 12]
background = [0.1, 0.2, 0.3, 0.9]
border_color = [0.4, 0.5, 0.6, 1.0]
border_width = 2
corner_radius = 6
hidden = true
[entities.ui_vstack]
gap = 8
fill = true
draggable = true
min_size = 72
[entities.ui_panel]
title = "METRICS"
title_color = [0.9, 0.9, 0.9, 1]
title_background = [0.12, 0.13, 0.14, 1]
title_size = 11
title_height = 28
collapsible = true
collapsed = true
[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 12
[[entities]]
id = "a6000000-0000-4000-8000-00000000000b"
name = "Title"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000a"
size = [300, 40]
[entities.ui_text]
text = "HELLO"
color = [1, 0.8, 0.2, 1]
size = 24
alignment = "right"
[[entities]]
id = "a6000000-0000-4000-8000-00000000000c"
name = "Stats"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000a"
size = [300, 80]
[entities.ui_table]
columns = 3
column_gap = 6
row_gap = 4
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 3)
	testing.expect(t, scene.entities[0].has_ui_vstack)
	testing.expect(t, scene.entities[0].ui_vstack.gap == 8)
	testing.expect(t, scene.entities[0].ui_vstack.fill)
	testing.expect(t, scene.entities[0].ui_vstack.draggable)
	testing.expect(t, scene.entities[0].ui_vstack.min_size == 72)
	testing.expect(t, scene.entities[0].has_ui_scroll_area)
	testing.expect(t, scene.entities[0].ui_scroll_area.scroll_speed == 64)
	testing.expect(t, scene.entities[0].ui_scroll_area.smoothness == 12)
	testing.expect(t, scene.entities[0].has_ui_panel)
	testing.expect(t, scene.entities[0].ui_panel.title == "METRICS")
	testing.expect(t, scene.entities[0].ui_panel.title_size == 11)
	testing.expect(t, scene.entities[0].ui_panel.title_height == 28)
	testing.expect(t, scene.entities[0].ui_panel.collapsible)
	testing.expect(t, scene.entities[0].ui_panel.collapsed)
	testing.expect(t, scene.entities[0].ui_layout.border_color == Vec4{0.4, 0.5, 0.6, 1})
	testing.expect(t, scene.entities[0].ui_layout.border_width == 2)
	testing.expect(t, scene.entities[0].ui_layout.corner_radius == 6)
	testing.expect(t, scene.entities[0].ui_layout.hidden)
	hud_id, hud_id_ok := shared.entity_uuid_parse("a6000000-0000-4000-8000-00000000000a")
	testing.expect(t, hud_id_ok && scene.entities[1].ui_layout.parent == hud_id)
	testing.expect(t, scene.entities[1].ui_text.text == "HELLO")
	testing.expect(t, scene.entities[1].ui_text.alignment == .Right)
	testing.expect(t, scene.entities[2].has_ui_table)
	testing.expect(t, scene.entities[2].ui_table.columns == 3)
	testing.expect(t, scene.entities[2].ui_table.column_gap == 6)
	testing.expect(t, scene.entities[2].ui_table.row_gap == 4)
}

@(test)
test_scene_rejects_collapsed_panel_without_collapsible_opt_in :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000010"
name = "Invalid Panel"
[entities.ui_layout]
size = [200, 100]
[entities.ui_panel]
title = "INVALID"
collapsed = true
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_parses_single_line_ui_input :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000d"
name = "Name Input"
[entities.ui_layout]
size = [240, 32]
[entities.ui_input]
text = "Scrapbot"
color = [0.9, 0.9, 0.9, 1]
size = 13
selection_background = [0.1, 0.5, 0.4, 0.5]
focus_border_color = [0.1, 0.8, 0.7, 1]
read_only = false
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	input := scene.entities[0].ui_input
	testing.expect(t, scene.entities[0].has_ui_input)
	testing.expect(t, input.text == "Scrapbot")
	testing.expect(t, input.size == 13)
	testing.expect(t, input.selection_background == Vec4{0.1, 0.5, 0.4, 0.5})
	testing.expect(t, input.focus_border_color == Vec4{0.1, 0.8, 0.7, 1})
}

@(test)
test_scene_parses_ui_checkbox :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000021"
name = "Enabled"
[entities.ui_layout]
size = [32, 32]
[entities.ui_checkbox]
checked = true
box_size = 20
checked_background = [0.1, 0.6, 0.5, 1]
read_only = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	checkbox := scene.entities[0].ui_checkbox
	testing.expect(t, scene.entities[0].has_ui_checkbox)
	testing.expect(t, checkbox.checked)
	testing.expect(t, checkbox.box_size == 20)
	testing.expect(t, checkbox.checked_background == Vec4{0.1, 0.6, 0.5, 1})
	testing.expect(t, checkbox.read_only)
}

@(test)
test_scene_rejects_ui_parent_cycles :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000e"
name = "A"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000f"
size = [10, 10]
[[entities]]
id = "a6000000-0000-4000-8000-00000000000f"
name = "B"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000e"
size = [10, 10]
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .Invalid_Field)
}
