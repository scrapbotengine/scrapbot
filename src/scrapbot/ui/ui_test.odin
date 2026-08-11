package ui

import asset_import "../asset_import"
import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"
import "core:math"
import "core:testing"

UI_Test_U8_Enum :: enum u8 {
	Low  = 1,
	High = 240,
}

UI_Test_I16_Enum :: enum i16 {
	Negative = -7,
	Positive = 32000,
}

@(test)
test_project_canvas_modes_resolve_logical_viewports_and_exact_inverse_pointer_mapping :: proc(
	t: ^testing.T,
) {
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	state.project_canvas_valid = true
	state.project_canvas = shared.ui_canvas_default()
	state.project_canvas.reference_size = {1280, 720}
	state.project_canvas.scale_mode = .Expand

	expanded := project_canvas_transform(state, 1920, 720)
	testing.expect_value(t, expanded.scale, shared.Vec2{1, 1})
	testing.expect_value(t, expanded.logical_viewport, Rect{0, 0, 1920, 720})
	pointer := project_pointer_input(
		state,
		{position = {1500, 360}, available = true},
		1280,
		720,
		1920,
		720,
	)
	testing.expect_value(t, pointer.position, shared.Vec2{1500, 360})

	state.project_canvas.scale_mode = .Fit
	state.project_canvas.reference_size = {1000, 500}
	fitted := project_canvas_transform(state, 1000, 1000)
	testing.expect_value(t, fitted.scale, shared.Vec2{1, 1})
	testing.expect_value(t, fitted.viewport, Rect{0, 250, 1000, 500})
	pointer = project_pointer_input(
		state,
		{position = {500, 500}, available = true},
		1280,
		720,
		1000,
		1000,
	)
	testing.expect_value(t, pointer.position, shared.Vec2{500, 250})

	state.project_canvas.scale_mode = .Stretch
	stretched := project_canvas_transform(state, 2000, 500)
	testing.expect_value(t, stretched.scale, shared.Vec2{2, 1})
	testing.expect_value(t, stretched.viewport, Rect{0, 0, 2000, 500})

	state.project_canvas.scale_mode = .Pixel_Perfect
	pixel_perfect := project_canvas_transform(state, 2500, 1500)
	testing.expect_value(t, pixel_perfect.scale, shared.Vec2{2, 2})
	testing.expect_value(t, pixel_perfect.viewport, Rect{250, 250, 2000, 1000})
}

@(test)
test_canvas_safe_area_and_per_axis_alignment_share_generic_layout :: proc(t: ^testing.T) {
	root_id := ui_test_id("Responsive Canvas")
	centered_id := ui_test_id("Centered Control")
	stretched_id := ui_test_id("Safe Stretch")
	scene: shared.Scene
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Responsive Canvas",
			has_ui_layout = true,
			ui_layout = {size = {800, 600}, fill_width = true, fill_height = true},
			has_ui_canvas = true,
			ui_canvas = {
				reference_size = {800, 600},
				scale_mode = .Expand,
				horizontal_alignment = .Center,
				vertical_alignment = .Center,
				safe_area = {20, 30, 40, 10},
			},
		},
		shared.Scene_Entity {
			id = centered_id,
			name = "Centered Control",
			has_ui_layout = true,
			ui_layout = {
				parent = root_id,
				size = {100, 50},
				horizontal_alignment = .Center,
				vertical_alignment = .End,
			},
		},
		shared.Scene_Entity {
			id = stretched_id,
			name = "Safe Stretch",
			has_ui_layout = true,
			ui_layout = {
				parent = root_id,
				size = {1, 1},
				horizontal_alignment = .Stretch,
				vertical_alignment = .Stretch,
			},
		},
	)
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 800, 600) == "")

	centered_index := find_node_by_entity_index(state, int(world.entities[1].id.index))
	stretched_index := find_node_by_entity_index(state, int(world.entities[2].id.index))
	testing.expect(t, centered_index >= 0)
	testing.expect(t, stretched_index >= 0)
	if centered_index >= 0 {
		testing.expect_value(t, state.nodes[centered_index].rect, Rect{340, 510, 100, 50})
	}
	if stretched_index >= 0 {
		testing.expect_value(t, state.nodes[stretched_index].rect, Rect{10, 20, 760, 540})
	}
}

@(test)
test_theme_recipes_resolve_to_ordinary_overridable_ui_values :: proc(t: ^testing.T) {
	theme := reduced_dark_theme()
	testing.expect_value(t, theme.metrics.radius_small, f32(2))
	testing.expect_value(t, theme.metrics.radius, f32(3))
	testing.expect_value(t, theme.metrics.radius_large, f32(6))
	testing.expect_value(t, theme.metrics.padding_small, shared.Vec4{4, 8, 4, 8})
	testing.expect_value(t, theme.metrics.padding_control, shared.Vec4{6, 8, 6, 8})
	testing.expect_value(t, theme.metrics.padding_panel, shared.Vec4{8, 8, 8, 8})
	testing.expect_value(t, theme.palette.region.x, theme.palette.region.y)
	testing.expect_value(t, theme.palette.region.y, theme.palette.region.z)
	testing.expect_value(t, theme.palette.control.x, theme.palette.control.y)
	layout, button := theme_button(theme, .Primary)
	button.text = "Launch"
	layout.size.x = 240
	testing.expect_value(t, button.text, "Launch")
	testing.expect_value(t, layout.size.x, f32(240))
	testing.expect(t, button.color == theme.palette.accent_text)
	testing.expect(t, layout.background == theme.palette.accent_soft)
	testing.expect(t, shared.ui_layout_is_valid(layout))
	testing.expect(t, shared.ui_button_is_valid(button))
	incomplete_icon := button
	incomplete_icon.icon = "play"
	testing.expect(t, !shared.ui_button_is_valid(incomplete_icon))
	incomplete_icon = button
	incomplete_icon.icon_set = shared.builtin_icon_set_uuid()
	testing.expect(t, !shared.ui_button_is_valid(incomplete_icon))

	parent := ui_test_id("Theme Parent")
	custom := theme
	custom.palette.panel = {0.72, 0.08, 0.64, 1}
	custom.metrics.radius = 0
	surface := shared.UI_Layout_Component {
		parent = parent,
		position = {12, 18},
		size = {320, 180},
		fill_width = true,
	}
	theme_apply_surface(&surface, custom, .Panel, true)
	testing.expect_value(t, surface.parent, parent)
	testing.expect_value(t, surface.position, shared.Vec2{12, 18})
	testing.expect_value(t, surface.size, shared.Vec2{320, 180})
	testing.expect(t, surface.fill_width)
	testing.expect(t, surface.background == custom.palette.panel)
	testing.expect_value(t, surface.corner_radius, f32(0))
	testing.expect_value(t, surface.border_width, custom.metrics.border_width)

	chrome_recipes := [?]shared.UI_Theme_Recipe{.Chrome_Bar, .Warning_Frame}
	chrome := shared.ui_theme_resolve(.Reduced_Dark, chrome_recipes[:])
	testing.expect(t, chrome.has_layout)
	testing.expect(t, chrome.layout.background == theme.palette.region)
	testing.expect(t, chrome.layout.border_color == theme.palette.warning_soft)
	testing.expect_value(t, chrome.layout.border_width, f32(2))
	testing.expect_value(t, chrome.layout.corner_radius, f32(0))
	parsed_chrome, parsed_chrome_ok := shared.ui_theme_recipe_parse("chrome_bar")
	testing.expect(t, parsed_chrome_ok && parsed_chrome == .Chrome_Bar)
	parsed_warning, parsed_warning_ok := shared.ui_theme_recipe_parse("warning_button")
	testing.expect(t, parsed_warning_ok && parsed_warning == .Warning_Button)

	selected_layout, selected_button := theme_button(theme, .Selected)
	testing.expect(t, selected_layout.background == theme.palette.raised)
	testing.expect(t, selected_button.color == theme.palette.text)
	warning_layout, warning_button := theme_button(theme, .Warning)
	testing.expect(t, warning_layout.background == theme.palette.warning_soft)
	testing.expect(t, warning_button.color == theme.palette.warning)
	list := theme_list(theme)
	testing.expect(t, list.highlight_corner_radius == theme.metrics.radius_small)
}

@(test)
test_project_material_edits_use_resource_history_and_dirty_tracking :: proc(t: ^testing.T) {
	scene: shared.Scene
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	resource_id, valid := shared.resource_uuid_parse("a3000000-0000-4000-8000-000000000001")
	testing.expect(t, valid)
	_, register_err := resources.register_project_material(
		&registry,
		resource_id,
		"Editable",
		"editable.resource.toml",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, register_err == "")
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.resource_registry = &registry
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		resource_id = resource_id,
		inspector_field = .Material_Base_Color,
		inspector_axis = .X,
	}
	before_material_revision := registry.material_revision
	testing.expect(t, editor_resource_write_number(state, binding, 0.25))
	testing.expect(t, registry.material_revision > before_material_revision)
	editor_history_push_resource(state, binding, 1, 0.25)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect_value(t, len(state.editor_dirty_resources), 1)
	testing.expect(t, editor_undo(state, &world))
	value, read_ok := editor_resource_number(state, binding)
	testing.expect(t, read_ok)
	testing.expect_value(t, value, f32(1))
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, editor_redo(state, &world))
	value, read_ok = editor_resource_number(state, binding)
	testing.expect(t, read_ok)
	testing.expect_value(t, value, f32(0.25))

	metallic_binding := shared.Editor_UI_Component {
		resource_id = resource_id,
		inspector_field = .Material_Metallic,
	}
	testing.expect(t, editor_resource_write_number(state, metallic_binding, 0.75))
	metallic, metallic_ok := editor_resource_number(state, metallic_binding)
	testing.expect(t, metallic_ok)
	testing.expect_value(t, metallic, f32(0.75))
	testing.expect(t, !editor_resource_write_number(state, metallic_binding, 1.1))

	roughness_binding := shared.Editor_UI_Component {
		resource_id = resource_id,
		inspector_field = .Material_Roughness,
	}
	testing.expect(t, editor_resource_write_number(state, roughness_binding, 0.35))
	roughness, roughness_ok := editor_resource_number(state, roughness_binding)
	testing.expect(t, roughness_ok)
	testing.expect_value(t, roughness, f32(0.35))
	testing.expect(t, !editor_resource_write_number(state, roughness_binding, -0.1))
}

@(test)
test_resource_manager_lifecycle_is_reference_aware_undoable_and_reusable_ui :: proc(
	t: ^testing.T,
) {
	resource_id, valid := shared.resource_uuid_parse("a3000000-0000-4000-8000-000000000021")
	testing.expect(t, valid)
	id_text := "a3000000-0000-4000-8000-000000000021"
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Resource User"),
			name = "Resource User",
			has_material = true,
			material_resource = id_text,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	_, register_err := resources.register_project_material(
		&registry,
		resource_id,
		"Original",
		"original.resource.toml",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, register_err == "")
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.resource_registry = &registry
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_selected_resource = resource_id
	state.editor_has_resource_selection = true

	testing.expect(
		t,
		editor_authoring_update_resource_identity(state, "Renamed", "library/moved.resource.toml"),
	)
	handle, found := resources.material_by_uuid(&registry, resource_id)
	testing.expect(t, found)
	material, alive := resources.get_material(&registry, handle)
	testing.expect(t, alive)
	testing.expect_value(t, material.name, "Renamed")
	testing.expect_value(t, material.source, "library/moved.resource.toml")
	testing.expect(t, editor_undo(state, &world))
	handle, _ = resources.material_by_uuid(&registry, resource_id)
	material, _ = resources.get_material(&registry, handle)
	testing.expect_value(t, material.name, "Original")
	testing.expect_value(t, material.source, "original.resource.toml")
	testing.expect(t, editor_redo(state, &world))

	testing.expect_value(t, editor_resource_usage_count(&world, resource_id), 1)
	testing.expect(t, !editor_authoring_delete_resource(state, &world))
	testing.expect(t, editor_select_first_resource_usage(state, &world, resource_id))
	testing.expect(t, state.editor_has_selection)
	testing.expect(t, !state.editor_has_resource_selection)

	testing.expect(t, editor_authoring_create_resource(state))
	created_id := state.editor_selected_resource
	testing.expect(t, created_id != resource_id)
	testing.expect(t, editor_authoring_duplicate_resource(state))
	duplicate_id := state.editor_selected_resource
	testing.expect(t, duplicate_id != created_id)
	testing.expect(t, editor_authoring_delete_resource(state, &world))
	_, duplicate_alive := resources.material_by_uuid(&registry, duplicate_id)
	testing.expect(t, !duplicate_alive)
	testing.expect(t, editor_undo(state, &world))
	_, duplicate_alive = resources.material_by_uuid(&registry, duplicate_id)
	testing.expect(t, duplicate_alive)
	testing.expect(t, state.editor_has_resource_selection)

	testing.expect(t, reconcile(state, &world, 1280, 720, resource_registry = &registry) == "")
	resource_rows := 0
	for binding in world.editor_uis {
		if binding.role == .Project_Resource_Row &&
		   binding.entity_index >= 0 &&
		   !world.ui_layouts[world.entities[binding.entity_index].ui_layout_index].hidden {
			resource_rows += 1
		}
	}
	testing.expect_value(t, resource_rows, 3)
	resource_label, resource_label_found := editor_ui_entity(
		&world,
		.Project_Resource_Row_Label,
		0,
	)
	testing.expect(t, resource_label_found)
	if resource_label_found {
		resource_label_layout := world.ui_layouts[world.entities[resource_label].ui_layout_index]
		testing.expect_value(t, resource_label_layout.position.x, EDITOR_BROWSER_TEXT_INSET)
	}
	browser, browser_found := editor_ui_entity(&world, .Project_Resources_Scroll)
	testing.expect(t, browser_found)
	filter, filter_found := editor_ui_entity(&world, .Browser_Filter, 1)
	testing.expect(t, filter_found)
	panel, panel_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_RESOURCES_NAME),
	)
	testing.expect(t, panel_found)
	if browser_found && filter_found && panel_found {
		browser_entity := world.entities[browser]
		panel_entity := world.entities[panel]
		filter_entity := world.entities[filter]
		testing.expect(t, browser_entity.ui_list_index >= 0)
		testing.expect(t, browser_entity.ui_scroll_area_index >= 0)
		testing.expect(t, browser_entity.ui_panel_index < 0)
		testing.expect(t, panel_entity.ui_panel_index >= 0)
		testing.expect(t, panel_entity.ui_vstack_index >= 0)
		list := world.ui_lists[browser_entity.ui_list_index]
		testing.expect_value(t, list.filter_input, world.entities[filter].uuid)
		testing.expect(t, list.virtualized)
		testing.expect_value(t, list.item_height, EDITOR_ENTITY_ROW_HEIGHT)
		testing.expect_value(t, list.overscan, 2)
		browser_layout := world.ui_layouts[browser_entity.ui_layout_index]
		testing.expect_value(t, browser_layout.parent, panel_entity.uuid)
		filter_layout := world.ui_layouts[filter_entity.ui_layout_index]
		filter_value := world.ui_inputs[filter_entity.ui_input_index]
		testing.expect(t, filter_layout.margin == shared.Vec4{2, 0, 2, 0})
		testing.expect(t, filter_layout.fill_width)
		testing.expect_value(
			t,
			filter_layout.padding.w,
			reduced_dark_theme().metrics.padding_control.w,
		)
		testing.expect_value(t, filter_value.prefix, "")
		testing.expect_value(t, filter_value.prefix_width, 0)
		testing.expect_value(t, filter_value.icon_set, shared.builtin_icon_set_uuid())
		testing.expect_value(t, filter_value.icon, "magnifying-glass")
		testing.expect_value(t, filter_value.icon_size, f32(14))

		testing.expect(t, ecs.set_ui_input_value(&world, filter, "renamed"))
		testing.expect(t, reconcile(state, &world, 1280, 720, resource_registry = &registry) == "")
		laid_out_resource_rows := 0
		for binding in world.editor_uis {
			if binding.role != .Project_Resource_Row || binding.entity_index < 0 {
				continue
			}
			node_index := find_node_by_entity_index(state, binding.entity_index)
			if node_index >= 0 && state.nodes[node_index].laid_out {
				laid_out_resource_rows += 1
			}
		}
		testing.expect_value(t, laid_out_resource_rows, 1)
		browser_node := find_node_by_entity_index(state, browser)
		testing.expect(t, browser_node >= 0)
		if browser_node >= 0 {
			testing.expect_value(t, state.nodes[browser_node].list_flow_count, 1)
		}
		testing.expect(t, ecs.set_ui_input_value(&world, filter, ""))
		testing.expect(t, reconcile(state, &world, 1280, 720, resource_registry = &registry) == "")
	}
	_, resource_name_found := editor_ui_entity(&world, .Inspector_Resource_Name)
	testing.expect(t, resource_name_found)

	// Entity selection is a single shared transition whether it comes from the
	// scene list or renderer picking. It must replace resource inspection.
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 720))
	testing.expect(t, !state.editor_has_resource_selection)
	testing.expect(t, reconcile(state, &world, 1280, 720, resource_registry = &registry) == "")
	resource_name, resource_name_still_found := editor_ui_entity(&world, .Inspector_Resource_Name)
	testing.expect(t, resource_name_still_found)
	if resource_name_still_found {
		resource_name_layout := world.entities[resource_name].ui_layout_index
		testing.expect(t, resource_name_layout >= 0)
		if resource_name_layout >= 0 {
			testing.expect(t, world.ui_layouts[resource_name_layout].hidden)
		}
	}
	entity_name, entity_name_found := editor_ui_entity(&world, .Inspector_Entity_Name)
	testing.expect(t, entity_name_found)
	if entity_name_found {
		entity_name_layout := world.entities[entity_name].ui_layout_index
		testing.expect(t, entity_name_layout >= 0)
		if entity_name_layout >= 0 {
			testing.expect(t, !world.ui_layouts[entity_name_layout].hidden)
		}
	}
}

@(test)
test_project_material_runtime_edits_preview_without_authoring_history :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	resource_id, valid := shared.resource_uuid_parse("a3000000-0000-4000-8000-000000000002")
	testing.expect(t, valid)
	_, register_err := resources.register_project_material(
		&registry,
		resource_id,
		"Runtime Preview",
		"runtime-preview.resource.toml",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, register_err == "")
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.resource_registry = &registry
	binding := shared.Editor_UI_Component {
		resource_id = resource_id,
		inspector_field = .Material_Base_Color,
		inspector_axis = .X,
	}
	testing.expect(t, editor_resource_write_number(state, binding, 0.4))
	editor_history_push_resource(state, binding, 1, 0.4)
	value, read_ok := editor_resource_number(state, binding)
	testing.expect(t, read_ok)
	testing.expect_value(t, value, f32(0.4))
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect_value(t, state.editor_history_count, 0)
}

@(test)
test_project_material_reference_switch_is_structural_and_undoable :: proc(t: ^testing.T) {
	first_id, first_valid := shared.resource_uuid_parse("a3000000-0000-4000-8000-000000000011")
	second_id, second_valid := shared.resource_uuid_parse("a3000000-0000-4000-8000-000000000012")
	testing.expect(t, first_valid && second_valid)
	first_text := "a3000000-0000-4000-8000-000000000011"
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Resource Target"),
			name = "Resource Target",
			has_material = true,
			material_resource = first_text,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	first_handle, first_err := resources.register_project_material(
		&registry,
		first_id,
		"First",
		"first.resource.toml",
		{base_color = {1, 0, 0, 1}},
	)
	second_handle, second_err := resources.register_project_material(
		&registry,
		second_id,
		"Second",
		"second.resource.toml",
		{base_color = {0, 1, 0, 1}},
	)
	testing.expect(t, first_err == "" && second_err == "")
	ecs.reconcile_render_instances(&world, &registry)
	testing.expect_value(t, world.materials[world.entities[0].material_index].handle, first_handle)

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.resource_registry = &registry
	state.editor_simulation_stopped = true
	testing.expect(t, editor_authoring_set_material_resource(state, &world, 0, second_id))
	ecs.reconcile_render_instances(&world, &registry)
	testing.expect_value(
		t,
		world.materials[world.entities[0].material_index].handle,
		second_handle,
	)
	testing.expect(t, editor_undo(state, &world))
	ecs.reconcile_render_instances(&world, &registry)
	testing.expect_value(t, world.materials[world.entities[0].material_index].handle, first_handle)
}

ui_test_id :: proc(name: string) -> shared.Entity_UUID {
	return shared.entity_uuid_from_engine_name(name)
}

find_editor_role_node :: proc(state: ^State, role: shared.Editor_UI_Role) -> int {
	for node, index in state.nodes[:state.node_count] { if node.origin == .Editor && node.editor_role == role { return index } }
	return -1
}

find_editor_name_node :: proc(state: ^State, world: ^shared.World, name: string) -> int {
	for node, index in state.nodes[:state.node_count] {
		entity_index := int(node.entity.index)
		if node.origin == .Editor &&
		   entity_index >= 0 &&
		   entity_index < len(world.entities) &&
		   world.entities[entity_index].name == name {
			return index
		}
	}
	return -1
}

editor_browser_row_count :: proc(world: ^shared.World) -> int {
	count := 0
	for component in world.editor_uis {
		if component.role != .Browser_Row ||
		   component.entity_index < 0 ||
		   component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if entity.alive &&
		   entity.ui_layout_index >= 0 &&
		   !world.ui_layouts[entity.ui_layout_index].hidden { count += 1 }
	}
	return count
}

@(test)
test_embedded_mtsdf_font_has_expected_atlas_and_proportional_metrics :: proc(t: ^testing.T) {
	testing.expect(t, len(FONT_ATLAS_DATA) == FONT_ATLAS_SIZE * FONT_ATLAS_SIZE * 4)
	i := FONT_GLYPHS[int('I') - FONT_FIRST_CHAR]
	w := FONT_GLYPHS[int('W') - FONT_FIRST_CHAR]
	testing.expect(t, i.advance > 0)
	testing.expect(t, w.advance > i.advance)
	testing.expect(t, w.uv.z > w.uv.x && w.uv.w > w.uv.y)
}

@(test)
test_progress_paints_overridable_track_and_right_anchored_fill :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Progress"),
			name = "Progress",
			has_ui_layout = true,
			ui_layout = {position = {20, 20}, size = {200, 20}},
			has_ui_progress = true,
			ui_progress = {
				value = 25,
				maximum = 100,
				fill_color = {0.2, 0.8, 0.6, 1},
				background_color = {0.1, 0.1, 0.1, 1},
				inset = {4, 10, 4, 10},
				corner_radius = 3,
				right_to_left = true,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 120) == "")
	testing.expect(t, state.paint_count == 2)
	if state.paint_count == 2 {
		track := state.paint[0]
		fill := state.paint[1]
		testing.expect(t, track.kind == .Panel)
		testing.expect(t, track.rect == (Rect{30, 24, 180, 12}))
		testing.expect(t, track.color == (shared.Vec4{0.1, 0.1, 0.1, 1}))
		testing.expect(t, track.corner_radius == 3)
		testing.expect(t, fill.rect == (Rect{165, 24, 45, 12}))
		testing.expect(t, fill.color == (shared.Vec4{0.2, 0.8, 0.6, 1}))
		testing.expect(t, fill.corner_radius == 3)
	}
	structure_sync_count := state.ui_structure_sync_count
	progress := world.ui_progresses[world.entities[0].ui_progress_index]
	progress.value = 50
	testing.expect(t, ecs.set_ui_progress(&world, 0, progress))
	testing.expect(t, reconcile(state, &world, 320, 120) == "")
	testing.expect(t, state.ui_structure_sync_count == structure_sync_count)
	testing.expect(t, state.paint_count == 2)
	if state.paint_count == 2 {
		testing.expect(t, state.paint[1].rect == (Rect{120, 24, 90, 12}))
	}
}

@(test)
test_layout_fill_and_fit_content_are_reusable_and_ignore_hidden_children :: proc(t: ^testing.T) {
	root_id := ui_test_id("Responsive Root")
	content_id := ui_test_id("Responsive Content")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Responsive Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}, padding = {10, 10, 10, 10}},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
		},
		shared.Scene_Entity {
			id = content_id,
			name = "Responsive Content",
			has_ui_layout = true,
			ui_layout = {
				parent = root_id,
				size = {10, 10},
				min_size = {120, 80},
				fill_width = true,
				fill_height = true,
				fit_content_height = true,
			},
			has_ui_vstack = true,
			ui_vstack = {gap = 5},
		},
		shared.Scene_Entity {
			id = ui_test_id("Responsive Child A"),
			name = "Responsive Child A",
			has_ui_layout = true,
			ui_layout = {parent = content_id, size = {40, 60}},
		},
		shared.Scene_Entity {
			id = ui_test_id("Responsive Child B"),
			name = "Responsive Child B",
			has_ui_layout = true,
			ui_layout = {parent = content_id, size = {40, 60}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	content_layout := world.ui_layouts[world.entities[1].ui_layout_index]
	content_node := find_node_by_entity_index(state, 1)
	testing.expectf(
		t,
		content_layout.size.y == 10,
		"authored height changed during layout: %.2f",
		content_layout.size.y,
	)
	testing.expectf(
		t,
		content_node >= 0 && state.nodes[content_node].rect.height == 125,
		"expected fitted height 125, got %.2f",
		state.nodes[content_node].rect.height,
	)
	testing.expect(t, content_node >= 0 && state.nodes[content_node].rect.width == 180)
	root_node := find_node_by_entity_index(state, 0)
	testing.expectf(
		t,
		root_node >= 0 && state.nodes[root_node].scroll_max == 45,
		"expected scroll max 45, got %.2f",
		state.nodes[root_node].scroll_max,
	)

	testing.expect(t, ecs.set_ui_hidden(&world, 3, true))
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	content_layout = world.ui_layouts[world.entities[1].ui_layout_index]
	testing.expect(t, content_layout.size.y == 10)
	testing.expect(t, state.nodes[content_node].rect.height == 80)
	testing.expect(t, state.nodes[root_node].scroll_max == 0)
}

@(test)
test_wrapped_text_intrinsically_measures_and_paints_the_resolved_lines :: proc(t: ^testing.T) {
	text_value := shared.UI_Text_Component {
		text = "alpha beta gamma delta",
		size = 12,
		wrap = true,
		line_height = 18,
	}
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Wrapped Text"),
			name = "Wrapped Text",
			has_ui_layout = true,
			ui_layout = {size = {72, 4}, fit_content_height = true},
			has_ui_text = true,
			ui_text = text_value,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	lines: [MAX_TEXT_LINES]Text_Line
	line_count := text_layout_lines(state, text_value.text, text_value.size, 72, true, &lines)
	testing.expect(t, line_count >= 2)
	for line in lines[:line_count] {
		testing.expect(t, line.advance <= 72.001)
	}
	testing.expect(t, reconcile(state, &world, 200, 160) == "")
	node_index := find_node_by_entity_index(state, 0)
	testing.expect(t, node_index >= 0)
	testing.expectf(
		t,
		node_index >= 0 &&
		math.abs(state.nodes[node_index].rect.height - f32(line_count) * 18) < 0.01,
		"expected %d wrapped lines at 18px, got %.2fpx",
		line_count,
		state.nodes[node_index].rect.height,
	)
	min_y, max_y := f32(10000), f32(-10000)
	for command in state.paint[:state.paint_count] {
		if command.kind != .Glyph {
			continue
		}
		min_y = min(min_y, command.rect.y)
		max_y = max(max_y, command.rect.y)
	}
	testing.expect(t, max_y - min_y >= 17)
}

@(test)
test_wrapping_stack_uses_basis_grow_shrink_and_cross_axis_alignment :: proc(t: ^testing.T) {
	wrap_root := ui_test_id("Flex Wrap Root")
	shrink_root := ui_test_id("Flex Shrink Root")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = wrap_root,
			name = "Flex Wrap Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}},
			has_ui_hstack = true,
			ui_hstack = {gap = 10, wrap = true, line_gap = 8},
		},
	)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Flex A"),
			name = "A",
			has_ui_layout = true,
			ui_layout = {
				parent = wrap_root,
				size = {10, 20},
				basis = 120,
				vertical_alignment = .Center,
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Flex B"),
			name = "B",
			has_ui_layout = true,
			ui_layout = {
				parent = wrap_root,
				size = {10, 20},
				basis = 100,
				vertical_alignment = .Center,
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Flex C"),
			name = "C",
			has_ui_layout = true,
			ui_layout = {
				parent = wrap_root,
				size = {10, 20},
				basis = 60,
				grow = 1,
				vertical_alignment = .Center,
			},
		},
	)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shrink_root,
			name = "Flex Shrink Root",
			has_ui_layout = true,
			ui_layout = {position = {0, 110}, size = {150, 40}},
			has_ui_hstack = true,
			ui_hstack = {gap = 10},
		},
	)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Flex D"),
			name = "D",
			has_ui_layout = true,
			ui_layout = {
				parent = shrink_root,
				size = {100, 20},
				min_size = {80, 0},
				basis = 100,
				shrink = 1,
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Flex E"),
			name = "E",
			has_ui_layout = true,
			ui_layout = {parent = shrink_root, size = {100, 20}, basis = 100, shrink = 1},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 180) == "")

	a := state.nodes[find_node_by_entity_index(state, 1)].rect
	b := state.nodes[find_node_by_entity_index(state, 2)].rect
	c := state.nodes[find_node_by_entity_index(state, 3)].rect
	d := state.nodes[find_node_by_entity_index(state, 5)].rect
	e := state.nodes[find_node_by_entity_index(state, 6)].rect
	testing.expect_value(t, a, Rect{0, 0, 120, 20})
	testing.expect_value(t, b, Rect{0, 28, 100, 20})
	testing.expect_value(t, c, Rect{110, 28, 90, 20})
	testing.expect_value(t, d, Rect{0, 110, 80, 20})
	testing.expect_value(t, e, Rect{90, 110, 60, 20})
}

@(test)
test_dock_spaces_select_and_transfer_public_dock_items :: proc(t: ^testing.T) {
	root_id := ui_test_id("Dock Root")
	left_id := ui_test_id("Dock Left")
	right_id := ui_test_id("Dock Right")
	first_id := ui_test_id("Dock First")
	second_id := ui_test_id("Dock Second")
	third_id := ui_test_id("Dock Third")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Dock Root",
			has_ui_layout = true,
			ui_layout = {size = {440, 180}},
		},
		shared.Scene_Entity {
			id = left_id,
			name = "Dock Left",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {210, 180}},
			has_ui_dock_space = true,
			ui_dock_space = shared.ui_dock_space_default(),
		},
		shared.Scene_Entity {
			id = right_id,
			name = "Dock Right",
			has_ui_layout = true,
			ui_layout = {parent = root_id, position = {230, 0}, size = {210, 180}},
			has_ui_dock_space = true,
			ui_dock_space = shared.ui_dock_space_default(),
		},
		shared.Scene_Entity {
			id = first_id,
			name = "Dock First",
			has_ui_layout = true,
			ui_layout = {parent = left_id, size = {100, 100}},
			has_ui_dock_item = true,
			ui_dock_item = {title = "FIRST", movable = true},
		},
		shared.Scene_Entity {
			id = second_id,
			name = "Dock Second",
			has_ui_layout = true,
			ui_layout = {parent = left_id, size = {100, 100}},
			has_ui_dock_item = true,
			ui_dock_item = {title = "SECOND", movable = true},
		},
		shared.Scene_Entity {
			id = third_id,
			name = "Dock Third",
			has_ui_layout = true,
			ui_layout = {parent = right_id, size = {100, 100}},
			has_ui_dock_item = true,
			ui_dock_item = {title = "THIRD", movable = true},
		},
	)
	scene.entities[1].ui_dock_space.tab_strip_background = {0.03, 0.04, 0.05, 1}
	scene.entities[2].ui_dock_space.tab_strip_background = {0.03, 0.04, 0.05, 1}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 440, 180) == "")
	first_node := find_node_by_entity_index(state, 3)
	second_node := find_node_by_entity_index(state, 4)
	third_node := find_node_by_entity_index(state, 5)
	testing.expect(t, state.nodes[first_node].laid_out)
	testing.expect(t, !state.nodes[second_node].laid_out)
	testing.expect(t, state.nodes[third_node].laid_out)
	testing.expect_value(t, state.nodes[first_node].rect, Rect{0, 32, 210, 148})
	testing.expect_value(t, state.dock_tab_count, 3)
	active_connections := 0
	dock_style := shared.ui_dock_space_default()
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == dock_style.tab_active_background &&
		   command.corner_radius == 0 &&
		   command.rect.height ==
			   dock_style.tab_connection_height + dock_style.tab_content_overlap {
			active_connections += 1
		}
	}
	testing.expect_value(t, active_connections, 2)
	content_sheets := 0
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == dock_style.content_background &&
		   command.corner_radius == dock_style.content_corner_radius &&
		   command.rect.height == 148 {
			content_sheets += 1
		}
	}
	testing.expect_value(t, content_sheets, 2)
	tab_strips := 0
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == (shared.Vec4{0.03, 0.04, 0.05, 1}) &&
		   command.rect.height == dock_style.tab_height {
			tab_strips += 1
		}
	}
	testing.expect_value(t, tab_strips, 2)

	second_tab := state.dock_tabs[1].rect
	second_tab_center := shared.Vec2 {
		second_tab.x + second_tab.width * 0.5,
		second_tab.y + second_tab.height * 0.5,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			440,
			180,
			{position = second_tab_center, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.nodes[second_node].laid_out)
	testing.expect(t, !state.nodes[first_node].laid_out)
	testing.expect_value(
		t,
		world.ui_dock_spaces[world.entities[1].ui_dock_space_index].active,
		second_id,
	)

	target := shared.Vec2{330, 90}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			440,
			180,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.dock_dragging)
	testing.expect(
		t,
		reconcile(state, &world, 440, 180, {position = target, available = true}) == "",
	)
	testing.expect_value(t, world.ui_layouts[world.entities[4].ui_layout_index].parent, right_id)
	testing.expect_value(
		t,
		world.ui_dock_spaces[world.entities[2].ui_dock_space_index].active,
		second_id,
	)
	testing.expect_value(
		t,
		world.ui_states[world.entities[2].ui_state_index].drop_revision,
		u64(1),
	)
	events := ui_events(state)
	dropped := false
	for event in events {
		if event.kind == .Dropped &&
		   event.source == world.entities[4].id &&
		   event.target == world.entities[2].id {
			dropped = true
		}
	}
	testing.expect(t, dropped)
	testing.expect(t, reconcile(state, &world, 440, 180) == "")
	testing.expect(t, reconcile(state, &world, 440, 180) == "")
	testing.expect(t, state.layout_node_visit_count == 0)
	testing.expect(t, state.layout_child_edge_visit_count == 0)
	testing.expect(t, state.paint_node_visit_count == 0)
	testing.expect(t, state.paint_child_edge_visit_count == 0)
	testing.expect_value(t, state.dock_tab_count, 3)
}

@(test)
test_dock_space_edge_drop_builds_public_resizable_split_topology :: proc(t: ^testing.T) {
	root_id := ui_test_id("Split Root")
	stack_id := ui_test_id("Split Source Stack")
	dock_id := ui_test_id("Split Target Dock")
	game_id := ui_test_id("Split Game")
	scene_panel_id := ui_test_id("Split Scene")
	tail_id := ui_test_id("Split Tail")
	dock_style := shared.ui_dock_space_default()
	dock_style.split_horizontal = true
	dock_style.split_ratio = 0.4
	dock_style.split_gap = 6
	dock_style.split_min_size = 120
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Split Root",
			has_ui_layout = true,
			ui_layout = {size = {760, 260}},
			has_ui_hstack = true,
			ui_hstack = {},
		},
		shared.Scene_Entity {
			id = stack_id,
			name = "Split Source Stack",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {180, 260}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true, drag_threshold = 5},
		},
		shared.Scene_Entity {
			id = dock_id,
			name = "Split Target Dock",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {500, 260}},
			has_ui_dock_space = true,
			ui_dock_space = dock_style,
		},
		shared.Scene_Entity {
			id = game_id,
			name = "Split Game",
			has_ui_layout = true,
			ui_layout = {parent = dock_id, size = {500, 228}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true, drag_threshold = 5},
			has_ui_dock_item = true,
			ui_dock_item = {title = "GAME", movable = false},
		},
		shared.Scene_Entity {
			id = scene_panel_id,
			name = "Split Scene",
			has_ui_layout = true,
			ui_layout = {parent = stack_id, size = {180, 260}},
			has_ui_panel = true,
			ui_panel = {title = "SCENE", title_height = 32, movable = true},
		},
		shared.Scene_Entity {
			id = tail_id,
			name = "Split Tail",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {80, 260}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 760, 260) == "")
	panel_node := find_node_by_entity_index(state, 4)
	initial_target_node := find_node_by_entity_index(state, 2)
	initial_tail_node := find_node_by_entity_index(state, 5)
	testing.expect(t, initial_target_node >= 0 && initial_tail_node >= 0)
	target_preceded_tail :=
		state.nodes[initial_target_node].rect.x < state.nodes[initial_tail_node].rect.x
	start := shared.Vec2{state.nodes[panel_node].rect.x + 60, state.nodes[panel_node].rect.y + 16}
	right_edge := shared.Vec2{670, 130}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			760,
			260,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			760,
			260,
			{position = right_edge, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.stack_drags[0].dragging)
	testing.expect_value(t, state.stack_drags[0].placement, shared.UI_Drop_Placement.Right)
	preview_found := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == dock_style.drop_background &&
		   command.rect.x > 470 &&
		   command.rect.width > 190 {
			preview_found = true
			break
		}
	}
	testing.expect(t, preview_found)
	testing.expect(
		t,
		reconcile(state, &world, 760, 260, {position = right_edge, available = true}) == "",
	)
	testing.expect(t, len(world.entities) == 8)
	branch_index := 6
	new_dock_index := 7
	testing.expect(t, world.entities[branch_index].alive)
	testing.expect(t, world.entities[branch_index].origin == .Runtime)
	testing.expect(t, world.entities[branch_index].ui_hstack_index >= 0)
	testing.expect(t, world.entities[new_dock_index].ui_dock_space_index >= 0)
	testing.expect_value(
		t,
		world.ui_layouts[world.entities[2].ui_layout_index].parent,
		world.entities[branch_index].uuid,
	)
	testing.expect_value(
		t,
		world.ui_layouts[world.entities[new_dock_index].ui_layout_index].parent,
		world.entities[branch_index].uuid,
	)
	testing.expect_value(
		t,
		world.ui_layouts[world.entities[4].ui_layout_index].parent,
		world.entities[new_dock_index].uuid,
	)
	testing.expect_value(
		t,
		world.ui_states[world.entities[2].ui_state_index].drop_placement,
		shared.UI_Drop_Placement.Right,
	)
	testing.expect_value(
		t,
		world.ui_states[world.entities[2].ui_state_index].drop_revision,
		u64(1),
	)
	testing.expect(t, reconcile(state, &world, 760, 260) == "")
	target_node := find_node_by_entity_index(state, 2)
	new_dock_node := find_node_by_entity_index(state, new_dock_index)
	branch_node := find_node_by_entity_index(state, branch_index)
	tail_node := find_node_by_entity_index(state, 5)
	testing.expect(t, target_node >= 0 && new_dock_node >= 0)
	testing.expect(t, branch_node >= 0 && tail_node >= 0)
	if target_node >= 0 && new_dock_node >= 0 && branch_node >= 0 && tail_node >= 0 {
		testing.expect(t, state.nodes[target_node].rect.x < state.nodes[new_dock_node].rect.x)
		testing.expect(
			t,
			state.nodes[target_node].rect.width > state.nodes[new_dock_node].rect.width,
		)
		testing.expectf(
			t,
			(state.nodes[branch_node].rect.x < state.nodes[tail_node].rect.x) ==
			target_preceded_tail,
			"split branch x=%v order=%v and tail x=%v order=%v must preserve the target's sibling position",
			state.nodes[branch_node].rect.x,
			world.ui_layouts[world.entities[branch_index].ui_layout_index].stack_order,
			state.nodes[tail_node].rect.x,
			world.ui_layouts[world.entities[5].ui_layout_index].stack_order,
		)
	}
	testing.expect(t, state.split_handle_count >= 1)
	testing.expect(t, reconcile(state, &world, 760, 260) == "")
	testing.expect(t, state.layout_node_visit_count == 0)
	testing.expect(t, state.layout_child_edge_visit_count == 0)
	testing.expect(t, state.paint_node_visit_count == 0)
	testing.expect(t, state.paint_child_edge_visit_count == 0)
}

@(test)
test_reorderable_stack_moves_panels_by_title_and_keeps_stable_frames_idle :: proc(t: ^testing.T) {
	root_id := ui_test_id("Panel Stack")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Panel Stack",
			has_ui_layout = true,
			ui_layout = {size = {240, 300}},
			has_ui_vstack = true,
			ui_vstack = {
				gap = 4,
				fill = true,
				draggable = true,
				min_size = 40,
				reorderable = true,
				drag_threshold = 5,
				drop_indicator_color = {0.2, 1.4, 1.1, 1},
				drop_indicator_thickness = 2,
				drop_indicator_inset = 8,
			},
		},
	)
	titles := [?]string{"ONE", "TWO", "THREE"}
	for title, index in titles {
		append(
			&scene.entities,
			shared.Scene_Entity {
				id = ui_test_id(title),
				name = title,
				has_ui_layout = true,
				ui_layout = {parent = root_id, size = {240, 96}, stack_order = index},
				has_ui_panel = true,
				ui_panel = {
					title = title,
					title_size = 12,
					title_height = 28,
					collapsible = true,
					movable = true,
				},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 300) == "")
	first_node := find_node_by_entity_index(state, 1)
	third_node := find_node_by_entity_index(state, 3)
	start := shared.Vec2{state.nodes[first_node].rect.x + 40, state.nodes[first_node].rect.y + 14}
	target := shared.Vec2 {
		state.nodes[third_node].rect.x + 40,
		state.nodes[third_node].rect.y + state.nodes[third_node].rect.height * 0.75,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			240,
			300,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			240,
			300,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.stack_drags[0].dragging)
	testing.expect(t, current_pointer_cursor(state) == .Move)
	testing.expect(
		t,
		reconcile(state, &world, 240, 300, {position = target, available = true}) == "",
	)
	testing.expect_value(t, world.ui_layouts[world.entities[2].ui_layout_index].stack_order, 0)
	testing.expect_value(t, world.ui_layouts[world.entities[3].ui_layout_index].stack_order, 1)
	testing.expect_value(t, world.ui_layouts[world.entities[1].ui_layout_index].stack_order, 2)
	testing.expect_value(
		t,
		world.ui_states[world.entities[0].ui_state_index].drop_revision,
		u64(1),
	)
	testing.expect(t, reconcile(state, &world, 240, 300) == "")
	first_node = find_node_by_entity_index(state, 1)
	third_node = find_node_by_entity_index(state, 3)
	testing.expect(t, state.nodes[first_node].rect.y > state.nodes[third_node].rect.y)
	testing.expect(t, reconcile(state, &world, 240, 300) == "")
	testing.expect(t, state.layout_node_visit_count == 0)
	testing.expect(t, state.layout_child_edge_visit_count == 0)
	testing.expect(t, state.paint_node_visit_count == 0)
	testing.expect(t, state.paint_child_edge_visit_count == 0)
}

@(test)
test_panel_drag_released_without_a_destination_does_not_toggle_collapse :: proc(t: ^testing.T) {
	stack_id := ui_test_id("Cancelled Panel Stack")
	panel_id := ui_test_id("Cancelled Panel")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = stack_id,
			name = "Cancelled Panel Stack",
			has_ui_layout = true,
			ui_layout = {size = {220, 180}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true, drag_threshold = 5},
		},
		shared.Scene_Entity {
			id = panel_id,
			name = "Cancelled Panel",
			has_ui_layout = true,
			ui_layout = {parent = stack_id, size = {220, 180}},
			has_ui_panel = true,
			ui_panel = {
				title = "CANCEL ME",
				title_height = 28,
				collapsible = true,
				movable = true,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 220, 180) == "")
	start := shared.Vec2{40, 14}
	outside := shared.Vec2{320, 90}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			400,
			180,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			400,
			180,
			{position = outside, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.stack_drags[0].dragging)
	testing.expect(t, current_pointer_cursor(state) == .Not_Allowed)
	testing.expect(
		t,
		reconcile(state, &world, 400, 180, {position = outside, available = true}) == "",
	)
	panel := world.ui_panels[world.entities[1].ui_panel_index]
	testing.expect(t, !panel.collapsed)
	testing.expect_value(
		t,
		world.ui_states[world.entities[0].ui_state_index].drop_revision,
		u64(0),
	)
}

@(test)
test_movable_panel_transfers_between_reorderable_stack_and_dock_space :: proc(t: ^testing.T) {
	root_id := ui_test_id("Panel Workspace Root")
	stack_id := ui_test_id("Panel Workspace Stack")
	dock_id := ui_test_id("Panel Workspace Dock")
	panel_id := ui_test_id("Panel Workspace Panel")
	placeholder_id := ui_test_id("Panel Workspace Placeholder")
	content_id := ui_test_id("Panel Workspace Content")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Panel Workspace Root",
			has_ui_layout = true,
			ui_layout = {size = {500, 240}},
		},
		shared.Scene_Entity {
			id = stack_id,
			name = "Panel Workspace Stack",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {220, 240}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true, drag_threshold = 5},
		},
		shared.Scene_Entity {
			id = dock_id,
			name = "Panel Workspace Dock",
			has_ui_layout = true,
			ui_layout = {parent = root_id, position = {250, 0}, size = {250, 240}},
			has_ui_dock_space = true,
			ui_dock_space = shared.ui_dock_space_default(),
		},
		shared.Scene_Entity {
			id = panel_id,
			name = "Panel Workspace Panel",
			has_ui_layout = true,
			ui_layout = {parent = stack_id, size = {220, 240}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true},
			has_ui_panel = true,
			ui_panel = {title = "TOOLS", title_height = 28, collapsible = true, movable = true},
		},
		shared.Scene_Entity {
			id = placeholder_id,
			name = "Panel Workspace Placeholder",
			has_ui_layout = true,
			ui_layout = {parent = dock_id, size = {250, 208}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true},
			has_ui_dock_item = true,
			ui_dock_item = {title = "GAME", movable = false},
		},
		shared.Scene_Entity {
			id = content_id,
			name = "Panel Workspace Content",
			has_ui_layout = true,
			ui_layout = {parent = panel_id, size = {220, 40}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 500, 240) == "")
	panel_node := find_node_by_entity_index(state, 3)
	start := shared.Vec2{state.nodes[panel_node].rect.x + 40, state.nodes[panel_node].rect.y + 14}
	dock_target := shared.Vec2{490, 16}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = dock_target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect_value(t, state.stack_drags[0].target_dock_space, world.entities[2].id)
	testing.expect(
		t,
		reconcile(state, &world, 500, 240, {position = dock_target, available = true}) == "",
	)
	testing.expect_value(t, world.ui_layouts[world.entities[3].ui_layout_index].parent, dock_id)
	testing.expect_value(
		t,
		world.ui_dock_spaces[world.entities[2].ui_dock_space_index].active,
		panel_id,
	)
	testing.expect(t, reconcile(state, &world, 500, 240) == "")
	testing.expect_value(t, state.dock_tab_count, 2)
	panel_node = find_node_by_entity_index(state, 3)
	content_node := find_node_by_entity_index(state, 5)
	testing.expect_value(t, state.nodes[panel_node].rect, Rect{250, 32, 250, 208})
	testing.expect_value(t, state.nodes[content_node].rect.y, f32(32))
	testing.expect_value(
		t,
		dock_item_reorderable_stack_node(state, &world, panel_node),
		panel_node,
	)

	panel_tab := -1
	placeholder_tab := -1
	for tab, index in state.dock_tabs[:state.dock_tab_count] {
		if tab.item_node == panel_node {
			panel_tab = index
		}
		if tab.item_node == find_node_by_entity_index(state, 4) {
			placeholder_tab = index
		}
	}
	testing.expect(t, panel_tab >= 0 && placeholder_tab >= 0)
	tab_rect := state.dock_tabs[panel_tab].rect
	tab_start := shared.Vec2{tab_rect.x + tab_rect.width * 0.5, tab_rect.y + tab_rect.height * 0.5}
	placeholder_rect := state.dock_tabs[placeholder_tab].rect
	placeholder_target := shared.Vec2 {
		placeholder_rect.x + placeholder_rect.width * 0.5,
		placeholder_rect.y + placeholder_rect.height * 0.5,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = tab_start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = placeholder_target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.dock_dragging)
	testing.expect_value(t, state.dock_drop_stack_node, find_node_by_entity_index(state, 4))
	testing.expect(t, state.dock_tabs[placeholder_tab].drop_target)
	testing.expect(t, current_pointer_cursor(state) == .Move)
	invalid_target := shared.Vec2{235, 120}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = invalid_target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Not_Allowed)
	testing.expect(
		t,
		reconcile(state, &world, 500, 240, {position = invalid_target, available = true}) == "",
	)

	panel_tab = -1
	for tab, index in state.dock_tabs[:state.dock_tab_count] {
		if tab.item_node == panel_node {
			panel_tab = index
			break
		}
	}
	testing.expect(t, panel_tab >= 0)
	tab_rect = state.dock_tabs[panel_tab].rect
	tab_start = {tab_rect.x + tab_rect.width * 0.5, tab_rect.y + tab_rect.height * 0.5}
	stack_target := shared.Vec2{110, 120}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = tab_start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = stack_target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.dock_dragging)
	testing.expect_value(t, state.dock_drop_stack_node, find_node_by_entity_index(state, 1))
	testing.expect(
		t,
		reconcile(state, &world, 500, 240, {position = stack_target, available = true}) == "",
	)
	testing.expect_value(t, world.ui_layouts[world.entities[3].ui_layout_index].parent, stack_id)
	testing.expect_value(
		t,
		world.ui_states[world.entities[1].ui_state_index].drop_revision,
		u64(1),
	)
}

@(test)
test_panel_drop_on_dock_tab_routes_into_the_tabs_reorderable_stack :: proc(t: ^testing.T) {
	root_id := ui_test_id("Tab Stack Root")
	source_stack_id := ui_test_id("Tab Stack Source")
	dock_id := ui_test_id("Tab Stack Dock")
	tab_id := ui_test_id("Tab Stack Item")
	panel_id := ui_test_id("Tab Stack Panel")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Tab Stack Root",
			has_ui_layout = true,
			ui_layout = {size = {500, 240}},
		},
		shared.Scene_Entity {
			id = source_stack_id,
			name = "Tab Stack Source",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {220, 240}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true},
		},
		shared.Scene_Entity {
			id = dock_id,
			name = "Tab Stack Dock",
			has_ui_layout = true,
			ui_layout = {parent = root_id, position = {250, 0}, size = {250, 240}},
			has_ui_dock_space = true,
			ui_dock_space = shared.ui_dock_space_default(),
		},
		shared.Scene_Entity {
			id = tab_id,
			name = "Tab Stack Item",
			has_ui_layout = true,
			ui_layout = {parent = dock_id, size = {250, 208}},
			has_ui_vstack = true,
			ui_vstack = {fill = true, reorderable = true},
			has_ui_dock_item = true,
			ui_dock_item = {title = "TOOLS", movable = true},
		},
		shared.Scene_Entity {
			id = panel_id,
			name = "Tab Stack Panel",
			has_ui_layout = true,
			ui_layout = {parent = source_stack_id, size = {220, 240}},
			has_ui_panel = true,
			ui_panel = {title = "PERFORMANCE", title_height = 28, movable = true},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 500, 240) == "")
	panel_node := find_node_by_entity_index(state, 4)
	start := shared.Vec2{state.nodes[panel_node].rect.x + 40, state.nodes[panel_node].rect.y + 14}
	tab := state.dock_tabs[0].rect
	target := shared.Vec2{tab.x + tab.width * 0.5, tab.y + tab.height * 0.5}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			500,
			240,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect_value(t, state.stack_drags[0].target_stack, world.entities[3].id)
	testing.expect(t, state.stack_drags[0].target_dock_space == (shared.Entity{}))
	testing.expect(t, state.dock_tabs[0].drop_target)
	testing.expect(t, current_pointer_cursor(state) == .Move)
	testing.expect(
		t,
		reconcile(state, &world, 500, 240, {position = target, available = true}) == "",
	)
	testing.expect_value(t, world.ui_layouts[world.entities[4].ui_layout_index].parent, tab_id)
	testing.expect_value(
		t,
		world.ui_dock_spaces[world.entities[2].ui_dock_space_index].active,
		shared.Entity_UUID{},
	)
	testing.expect_value(t, state.dock_tab_count, 1)
	testing.expect_value(
		t,
		world.ui_states[world.entities[3].ui_state_index].drop_revision,
		u64(1),
	)
}

@(test)
test_fill_stack_can_keep_fixed_children_while_siblings_grow :: proc(t: ^testing.T) {
	root_id := ui_test_id("Fixed Fill Root")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Fixed Fill Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 150}},
			has_ui_vstack = true,
			ui_vstack = {fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Fixed Fill Header"),
			name = "Fixed Fill Header",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {200, 20}, fixed_in_fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Fixed Fill Body"),
			name = "Fixed Fill Body",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {200, 80}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	header := find_node_by_entity_index(state, 1)
	body := find_node_by_entity_index(state, 2)
	testing.expect(t, header >= 0 && state.nodes[header].rect.height == 20)
	testing.expect(t, body >= 0 && state.nodes[body].rect.height == 130)
}

@(test)
test_checkbox_paints_sdf_mark_and_toggles_unless_read_only :: proc(t: ^testing.T) {
	checkbox_style := shared.ui_checkbox_default()
	checkbox_style.checked = true
	checkbox_style.box_size = 20
	checkbox_style.background = {0.02, 0.03, 0.04, 1}
	checkbox_style.checked_background = {0.08, 0.55, 0.46, 1}
	checkbox_style.border_color = {0.24, 0.27, 0.32, 1}
	checkbox_style.check_color = {1, 1, 1, 1}
	checkbox_style.corner_radius = 0
	checkbox_style.border_width = 2
	checkbox_style.check_inset = 5
	checkbox_style.check_corner_radius = 0
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Checkbox"),
			name = "Checkbox",
			has_ui_layout = true,
			ui_layout = {position = {20, 20}, size = {80, 32}},
			has_ui_checkbox = true,
			ui_checkbox = checkbox_style,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	checkbox_state := &world.ui_states[world.entities[0].ui_state_index]
	found_checkmark := false
	found_square_box := false
	for command in state.paint[:state.paint_count] {
		found_checkmark = found_checkmark || command.kind == .Checkmark
		found_square_box =
			found_square_box ||
			(command.kind == .Panel && command.corner_radius == 0 && command.border_width == 2)
	}
	testing.expect(t, found_checkmark)
	testing.expect(t, found_square_box)
	pointer := Pointer_Input {
		position = {30, 30},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, current_pointer_cursor(state) == .Pointer)
	testing.expect(t, !world.ui_checkboxes[0].checked)
	testing.expect(t, checkbox_state.changed && checkbox_state.change_revision == 1)
	testing.expect_value(t, len(world.ui_transient_state_entities), 1)
	pointer.primary_down = false
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, !checkbox_state.changed)
	testing.expect_value(t, len(world.ui_transient_state_entities), 0)
	world.ui_checkboxes[0].read_only = true
	pointer.primary_down = true
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, !world.ui_checkboxes[0].checked)
}

@(test)
test_selectable_list_lays_out_full_width_rows_and_selects_direct_child :: proc(t: ^testing.T) {
	list_id := ui_test_id("List")
	first_id := ui_test_id("First")
	second_id := ui_test_id("Second")
	selection_color := shared.Vec4{0.1, 0.5, 0.4, 1}
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = list_id,
			name = "List",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}},
			has_ui_list = true,
			ui_list = {
				gap = 3,
				selection_background = selection_color,
				hover_background = {0.2, 0.2, 0.2, 1},
				active_background = {0.3, 0.3, 0.3, 1},
				highlight_corner_radius = 7,
			},
		},
		shared.Scene_Entity {
			id = first_id,
			name = "First",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {40, 30}},
			has_ui_text = true,
			ui_text = {text = "First", color = {1, 1, 1, 1}, size = 12},
		},
		shared.Scene_Entity {
			id = second_id,
			name = "Second",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {60, 30}},
			has_ui_text = true,
			ui_text = {text = "Second", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 100) == "")
	first_node := find_node_by_entity_index(state, 1)
	second_node := find_node_by_entity_index(state, 2)
	testing.expect(t, first_node >= 0 && second_node >= 0)
	if first_node < 0 || second_node < 0 { return }
	testing.expect(t, state.nodes[first_node].rect.width == 200)
	testing.expect(t, state.nodes[second_node].rect.width == 200)
	testing.expect(t, state.nodes[second_node].rect.y == 33)
	point := shared.Vec2 {
		state.nodes[second_node].rect.x + 20,
		state.nodes[second_node].rect.y + 15,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, world.ui_lists[0].selected == second_id)
	list_state := world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, list_state.changed && list_state.change_revision == 1)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {position = point, available = true}) == "",
	)
	testing.expect(t, current_pointer_cursor(state) == .Pointer)
	selected_painted := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.rect == state.nodes[second_node].rect &&
		   command.color == selection_color &&
		   command.corner_radius == 7 {
			selected_painted = true
		}
	}
	testing.expect(t, selected_painted)
}

@(test)
test_ui_action_drag_source_drops_on_generic_target_with_feedback :: proc(t: ^testing.T) {
	source_id := ui_test_id("Action Drag Source")
	target_id := ui_test_id("Action Drop Target")
	drop_color := shared.Vec4{0.2, 0.6, 0.5, 0.8}
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = source_id,
			name = "Source",
			has_ui_layout = true,
			ui_layout = {position = {0, 0}, size = {80, 40}},
			has_ui_action = true,
			ui_action = {
				action = "inventory.item",
				payload = "healing-potion",
				drag_source = true,
				drag_threshold = 5,
			},
		},
		shared.Scene_Entity {
			id = target_id,
			name = "Target",
			has_ui_layout = true,
			ui_layout = {position = {100, 0}, size = {80, 40}},
			has_ui_action = true,
			ui_action = {
				action = "inventory.slot",
				drop_target = true,
				drag_threshold = 5,
				drop_background = drop_color,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 80) == "")
	start := shared.Vec2{20, 20}
	target := shared.Vec2{120, 20}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			80,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			80,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	interaction := world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, interaction.dragging)
	testing.expect_value(t, interaction.drag_source, source_id)
	testing.expect_value(t, interaction.drop_target, target_id)
	testing.expect_value(t, interaction.drop_placement, shared.UI_Drop_Placement.Into)
	testing.expect_value(t, current_pointer_cursor(state), Pointer_Cursor.Move)
	found_feedback := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel && command.color == drop_color {
			found_feedback = true
		}
	}
	testing.expect(t, found_feedback)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {position = target, available = true}) == "",
	)
	interaction = world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, !interaction.dragging)
	target_interaction := world.ui_states[world.entities[1].ui_state_index]
	testing.expect_value(t, target_interaction.drop_revision, u64(1))
	testing.expect_value(t, target_interaction.drag_source, source_id)
	event, found := ecs.ui_event_after_at(&world, 0, 1)
	if !found {
		event, found = ecs.ui_event_after_at(&world, 0, 0)
	}
	testing.expect(t, found)
	if found {
		testing.expect(t, event.kind == .Dropped)
		testing.expect_value(t, event.entity, target_id)
		testing.expect_value(t, event.action, "inventory.slot")
		testing.expect_value(t, event.drag_source, source_id)
		testing.expect_value(t, event.drop_target, target_id)
	}
}

@(test)
test_draggable_list_exposes_direct_child_drop_and_paints_lander_line :: proc(t: ^testing.T) {
	list_id := ui_test_id("Draggable List")
	first_id := ui_test_id("Draggable First")
	second_id := ui_test_id("Draggable Second")
	indicator_color := shared.Vec4{0.25, 0.9, 0.75, 1}
	target_color := shared.Vec4{0.1, 0.3, 0.4, 1}
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = list_id,
			name = "List",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}},
			has_ui_list = true,
			ui_list = {
				draggable = true,
				drag_threshold = 5,
				drop_edge_fraction = 0.25,
				drop_target_background = target_color,
				drop_indicator_color = indicator_color,
				drop_indicator_thickness = 3,
				drop_indicator_inset = 7,
			},
		},
		shared.Scene_Entity {
			id = first_id,
			name = "First",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {200, 30}},
			has_ui_text = true,
			ui_text = {text = "First", color = {1, 1, 1, 1}, size = 12},
		},
		shared.Scene_Entity {
			id = second_id,
			name = "Second",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {200, 30}},
			has_ui_text = true,
			ui_text = {text = "Second", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 100) == "")
	first_node := find_node_by_entity_index(state, 1)
	second_node := find_node_by_entity_index(state, 2)
	start := shared.Vec2{state.nodes[first_node].rect.x + 20, state.nodes[first_node].rect.y + 15}
	target := shared.Vec2 {
		state.nodes[second_node].rect.x + 20,
		state.nodes[second_node].rect.y + 29,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	list_state := world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, list_state.dragging)
	testing.expect_value(t, list_state.drag_source, first_id)
	testing.expect_value(t, list_state.drop_target, second_id)
	testing.expect_value(t, list_state.drop_placement, shared.UI_Drop_Placement.After)
	found_indicator := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Line &&
		   command.color == indicator_color &&
		   command.line_thickness == 3 {
			found_indicator = true
		}
	}
	testing.expect(t, found_indicator)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {position = target, available = true}) == "",
	)
	list_state = world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, !list_state.dragging)
	testing.expect_value(t, list_state.drop_revision, u64(1))
	dropped := false
	for event in ui_events(state) {
		if event.kind == .Dropped &&
		   event.entity == world.entities[0].id &&
		   event.source == world.entities[1].id &&
		   event.target == world.entities[2].id &&
		   event.drop_placement == .After {
			dropped = true
		}
	}
	testing.expect(t, dropped)
	center_target := shared.Vec2 {
		state.nodes[second_node].rect.x + 20,
		state.nodes[second_node].rect.y + 15,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = center_target, primary_down = true, available = true},
		) ==
		"",
	)
	list_state = world.ui_states[world.entities[0].ui_state_index]
	testing.expect_value(t, list_state.drop_placement, shared.UI_Drop_Placement.Into)
	found_target_background := false
	found_center_indicator := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.rect == state.nodes[second_node].rect &&
		   command.color == target_color {
			found_target_background = true
		}
		if command.kind == .Line && command.color == indicator_color {
			found_center_indicator = true
		}
	}
	testing.expect(t, found_target_background)
	testing.expect(t, !found_center_indicator)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {position = center_target, available = true}) == "",
	)
	list_state = world.ui_states[world.entities[0].ui_state_index]
	testing.expect_value(t, list_state.drop_revision, u64(2))
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {position = start, available = true}) == "",
	)
	list_state = world.ui_states[world.entities[0].ui_state_index]
	testing.expect_value(t, list_state.drop_revision, u64(2))
}

@(test)
test_tree_list_flattens_indents_collapses_and_moves_subtrees :: proc(t: ^testing.T) {
	list_id := ui_test_id("Tree List")
	toolbar_id := ui_test_id("Tree Toolbar")
	root_id := ui_test_id("Tree Root")
	child_id := ui_test_id("Tree Child")
	last_id := ui_test_id("Tree Last")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = list_id,
			name = "Tree List",
			has_ui_layout = true,
			ui_layout = {size = {200, 120}},
			has_ui_list = true,
			ui_list = {
				draggable = true,
				drag_threshold = 1,
				drop_edge_fraction = 0.25,
				tree_enabled = true,
				tree_indent = 12,
			},
		},
		shared.Scene_Entity {
			id = toolbar_id,
			name = "Toolbar",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {200, 20}},
		},
		shared.Scene_Entity {
			id = root_id,
			name = "Root",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {200, 20}, tree_item = true, tree_order = 0},
		},
		shared.Scene_Entity {
			id = ui_test_id("Tree Root Label"),
			name = "Root Label",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {80, 20}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_ui_layout = true,
			ui_layout = {
				parent = list_id,
				size = {200, 20},
				tree_item = true,
				tree_parent = root_id,
				tree_order = 0,
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Tree Child Label"),
			name = "Child Label",
			has_ui_layout = true,
			ui_layout = {parent = child_id, size = {80, 20}},
		},
		shared.Scene_Entity {
			id = last_id,
			name = "Last",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {200, 20}, tree_item = true, tree_order = 1},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	root_node := find_node_by_entity_index(state, 2)
	root_label := find_node_by_entity_index(state, 3)
	child_node := find_node_by_entity_index(state, 4)
	child_label := find_node_by_entity_index(state, 5)
	last_node := find_node_by_entity_index(state, 6)
	testing.expect(t, state.nodes[root_node].rect.y == 20)
	testing.expect(t, state.nodes[child_node].rect.y == 40)
	testing.expect(t, state.nodes[last_node].rect.y == 60)
	testing.expect(t, state.nodes[root_node].rect.x == state.nodes[child_node].rect.x)
	testing.expect(t, state.nodes[child_label].rect.x == state.nodes[root_label].rect.x + 12)

	root_layout := world.ui_layouts[world.entities[2].ui_layout_index]
	root_layout.tree_collapsed = true
	testing.expect(t, ecs.set_ui_layout(&world, 2, root_layout))
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	testing.expect(t, !state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[last_node].rect.y == 40)

	root_layout.tree_collapsed = false
	testing.expect(t, ecs.set_ui_hidden(&world, 2, true))
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	testing.expect(t, find_node_by_entity_index(state, 2) < 0)
	child_node = find_node_by_entity_index(state, 4)
	testing.expect(t, child_node >= 0)
	if child_node >= 0 {
		testing.expect(t, !state.nodes[child_node].laid_out)
	}
	testing.expect(t, ecs.set_ui_hidden(&world, 2, false))
	testing.expect(t, ecs.set_ui_layout(&world, 2, root_layout))
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	root_node = find_node_by_entity_index(state, 2)
	root_label = find_node_by_entity_index(state, 3)
	child_node = find_node_by_entity_index(state, 4)
	child_label = find_node_by_entity_index(state, 5)
	last_node = find_node_by_entity_index(state, 6)
	start := shared.Vec2{state.nodes[child_node].rect.x + 20, state.nodes[child_node].rect.y + 10}
	target := shared.Vec2{state.nodes[last_node].rect.x + 20, state.nodes[last_node].rect.y + 1}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			120,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			120,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 120, {position = target, available = true}) == "",
	)
	child_layout := world.ui_layouts[world.entities[4].ui_layout_index]
	last_layout := world.ui_layouts[world.entities[6].ui_layout_index]
	testing.expect_value(t, child_layout.tree_parent, shared.Entity_UUID{})
	testing.expect(t, child_layout.tree_order < last_layout.tree_order)
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	testing.expect(t, state.nodes[child_label].rect.x == state.nodes[root_label].rect.x)
	testing.expect(
		t,
		tree_list_apply_drop(state, &world, 0, world.entities[4].id, world.entities[2].id, .Into),
	)
	testing.expect(
		t,
		!tree_list_apply_drop(state, &world, 0, world.entities[2].id, world.entities[4].id, .Into),
	)
}

@(test)
test_list_filter_keeps_matching_tree_ancestors_and_temporarily_reveals_collapsed_branches :: proc(
	t: ^testing.T,
) {
	root_id := ui_test_id("Filtered Tree Root")
	filter_id := ui_test_id("Filtered Tree Input")
	list_id := ui_test_id("Filtered Tree List")
	parent_id := ui_test_id("Filtered Tree Parent")
	child_id := ui_test_id("Filtered Tree Child")
	other_id := ui_test_id("Filtered Tree Other")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {240, 160}},
			has_ui_vstack = true,
			ui_vstack = {},
		},
		shared.Scene_Entity {
			id = filter_id,
			name = "Filter",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {240, 28}},
			has_ui_input = true,
			ui_input = {text = "needle", size = 14},
		},
		shared.Scene_Entity {
			id = list_id,
			name = "List",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {240, 132}},
			has_ui_list = true,
			ui_list = {filter_input = filter_id, tree_enabled = true, tree_indent = 12},
		},
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_ui_layout = true,
			ui_layout = {
				parent = list_id,
				size = {240, 24},
				tree_item = true,
				tree_collapsed = true,
			},
			has_ui_text = true,
			ui_text = {text = "Parent", size = 14},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_ui_layout = true,
			ui_layout = {
				parent = list_id,
				size = {240, 24},
				tree_item = true,
				tree_parent = parent_id,
			},
			has_ui_text = true,
			ui_text = {text = "Needle Child", size = 14},
		},
		shared.Scene_Entity {
			id = other_id,
			name = "Other",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {240, 24}, tree_item = true, tree_order = 1},
			has_ui_text = true,
			ui_text = {text = "Other", size = 14},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 160) == "")

	list_node := find_node_by_entity_index(state, 2)
	parent_node := find_node_by_entity_index(state, 3)
	child_node := find_node_by_entity_index(state, 4)
	other_node := find_node_by_entity_index(state, 5)
	testing.expect(t, list_node >= 0)
	testing.expect(t, parent_node >= 0 && state.nodes[parent_node].laid_out)
	testing.expect(t, child_node >= 0 && state.nodes[child_node].laid_out)
	testing.expect(t, other_node >= 0 && !state.nodes[other_node].laid_out)
	if list_node >= 0 {
		testing.expect_value(t, state.nodes[list_node].list_flow_count, 2)
	}
	if parent_node >= 0 && child_node >= 0 {
		testing.expect_value(t, state.nodes[parent_node].tree_depth, 0)
		testing.expect_value(t, state.nodes[child_node].tree_depth, 1)
	}
	parent_layout := world.ui_layouts[world.entities[3].ui_layout_index]
	testing.expect(t, parent_layout.tree_collapsed)

	testing.expect(t, ecs.set_ui_input_value(&world, 1, ""))
	testing.expect(t, reconcile(state, &world, 240, 160) == "")
	testing.expect(t, state.nodes[parent_node].laid_out)
	testing.expect(t, !state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[other_node].laid_out)
	if list_node >= 0 {
		testing.expect_value(t, state.nodes[list_node].list_flow_count, 2)
	}
	parent_layout = world.ui_layouts[world.entities[3].ui_layout_index]
	testing.expect(t, parent_layout.tree_collapsed)
}

@(test)
test_virtualized_list_reuses_filtered_flow_cache_while_scrolling :: proc(t: ^testing.T) {
	list_id := ui_test_id("Virtualized List")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = list_id,
			name = "List",
			has_ui_layout = true,
			ui_layout = {size = {240, 80}},
			has_ui_list = true,
			ui_list = {virtualized = true, item_height = 20, overscan = 1},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
		},
	)
	for index in 0 ..< 100 {
		append(
			&scene.entities,
			shared.Scene_Entity {
				id = ui_test_id(fmt.tprintf("Virtualized Row %d", index)),
				name = fmt.tprintf("Row %d", index),
				has_ui_layout = true,
				ui_layout = {parent = list_id, size = {240, 20}},
				has_ui_text = true,
				ui_text = {text = fmt.tprintf("Row %d", index), size = 14},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 80) == "")

	list_node := find_node_by_entity_index(state, 0)
	testing.expect(t, list_node >= 0)
	if list_node < 0 {
		return
	}
	testing.expect_value(t, state.nodes[list_node].list_flow_count, 100)
	testing.expect(t, math.abs(state.nodes[list_node].scroll_content_height - 2000) < 0.01)
	initial_rebuilds := state.ui_project_list_flow_rebuild_count
	initial_layout_visits := state.layout_child_edge_visit_count
	testing.expect(t, initial_layout_visits < 20)
	testing.expect(t, !state.nodes[find_node_by_entity_index(state, 100)].laid_out)

	state.nodes[list_node].scroll_offset = 1000
	state.nodes[list_node].scroll_target = 1000
	state.ui_layout_valid = false
	testing.expect(t, reconcile(state, &world, 240, 80) == "")
	testing.expect_value(t, state.ui_project_list_flow_rebuild_count, initial_rebuilds)
	testing.expect(t, state.layout_child_edge_visit_count < 20)
	testing.expect(t, state.nodes[find_node_by_entity_index(state, 51)].laid_out)
	testing.expect(t, !state.nodes[find_node_by_entity_index(state, 1)].laid_out)

	layout_visits := state.layout_node_visit_count
	testing.expect(t, reconcile(state, &world, 240, 80) == "")
	testing.expect_value(t, state.ui_project_list_flow_rebuild_count, initial_rebuilds)
	testing.expect(t, layout_visits > 0)
	testing.expect_value(t, state.layout_node_visit_count, u64(0))
}

@(test)
test_reconcile_tracks_ui_entity_appearance_and_disappearance :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {
				size = {300, 160},
				padding = {10, 10, 10, 10},
				background = {0.1, 0.2, 0.3, 1},
			},
			has_ui_vstack = true,
			ui_vstack = {gap = 0},
		},
		shared.Scene_Entity {
			name = "Label",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {200, 40}},
			has_ui_text = true,
			ui_text = {text = "HELLO", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	ecs.delete_world_string(&world, world.entities[0].name)
	world.entities[0].name = ecs.clone_world_string(&world, "Renamed Root Label")
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 2)
	root_node := find_node_by_entity_index(state, 0)
	label_node := find_node_by_entity_index(state, 1)
	testing.expect(t, root_node >= 0 && label_node >= 0)
	if root_node >= 0 && label_node >= 0 {
		testing.expect(t, state.nodes[label_node].parent_entity_index == 0)
		testing.expect(t, state.nodes[label_node].parent_node_index == root_node)
		testing.expect(t, state.nodes[root_node].first_child_node == label_node)
		testing.expect(t, state.nodes[label_node].next_sibling_node == -1)
	}
	testing.expect(t, state.paint_count > 2)
	testing.expect(t, state.ui_structure_sync_count == 1)
	testing.expect_value(t, state.ui_hierarchy_rebuild_count, u64(1))
	project_output_revision := state.project_paint_output_revision
	editor_output_revision := state.editor_paint_output_revision
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == 1)
	testing.expect_value(t, state.project_paint_output_revision, project_output_revision)
	testing.expect_value(t, state.editor_paint_output_revision, editor_output_revision)
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect_value(t, state.ui_structure_sync_count, u64(2))
	testing.expect_value(t, state.ui_hierarchy_rebuild_count, u64(1))
	world.ui_layouts[world.entities[0].ui_layout_index].hidden = true
	ecs.mark_ui_subtree_dirty(&world, 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 0)
	testing.expect(t, state.ui_structure_sync_count == 3)
	testing.expect_value(t, state.ui_hierarchy_rebuild_count, u64(2))
	testing.expect(t, state.project_paint_output_revision > project_output_revision)
	world.ui_layouts[world.entities[0].ui_layout_index].hidden = false
	ecs.mark_ui_subtree_dirty(&world, 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 2)
	testing.expect(t, state.ui_structure_sync_count == 4)
	world.entities[1].alive = false
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 1)
	testing.expect(t, state.paint_count == 1)
	testing.expect(t, state.ui_structure_sync_count == 5)
}

@(test)
test_column_layout_places_children_in_order :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {300, 200}, padding = {10, 10, 10, 10}},
			has_ui_vstack = true,
			ui_vstack = {gap = 5},
		},
		shared.Scene_Entity {
			name = "A",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
		shared.Scene_Entity {
			name = "B",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 30}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	a := find_node_by_entity_index(state, 1); b := find_node_by_entity_index(state, 2)
	testing.expect(t, a >= 0 && b >= 0)
	if a >= 0 &&
	   b >=
		   0 { testing.expect(t, state.nodes[a].rect.y == 10); testing.expect(t, state.nodes[b].rect.y == 35) }
	world.entities[1].alive = false
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	b = find_node_by_entity_index(state, 2)
	testing.expect(t, b >= 0 && state.nodes[b].rect.y == 10)
	world.entities[1].alive = true
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	a = find_node_by_entity_index(state, 1)
	b = find_node_by_entity_index(state, 2)
	testing.expect(t, a >= 0 && b >= 0)
	if a >= 0 && b >= 0 {
		testing.expect(t, state.nodes[a].rect.y == 10)
		testing.expect(t, state.nodes[b].rect.y == 35)
		root := find_node_by_entity_index(state, 0)
		testing.expect(t, root >= 0)
		if root >= 0 {
			testing.expect(t, state.nodes[root].first_child_node == a)
			testing.expect(t, state.nodes[a].next_sibling_node == b)
			testing.expect(t, state.nodes[b].next_sibling_node == -1)
		}
	}
}

@(test)
test_retained_hierarchy_links_follow_reparenting :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	left_id := ui_test_id("Left Root")
	right_id := ui_test_id("Right Root")
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = left_id,
			name = "Left Root",
			has_ui_layout = true,
			ui_layout = {size = {100, 100}},
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			id = right_id,
			name = "Right Root",
			has_ui_layout = true,
			ui_layout = {position = {200, 0}, size = {100, 100}},
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = left_id, size = {40, 20}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	left := find_node_by_entity_index(state, 0)
	right := find_node_by_entity_index(state, 1)
	child := find_node_by_entity_index(state, 2)
	testing.expect(t, left >= 0 && right >= 0 && child >= 0)
	if left < 0 || right < 0 || child < 0 {
		return
	}
	testing.expect(t, state.nodes[child].parent_node_index == left)
	testing.expect(t, state.nodes[left].first_child_node == child)
	testing.expect(t, state.nodes[right].first_child_node == -1)
	testing.expect(t, state.nodes[child].rect.x == 0)

	layout := world.ui_layouts[world.entities[2].ui_layout_index]
	layout.parent = right_id
	testing.expect(t, ecs.set_ui_layout(&world, 2, layout))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	left = find_node_by_entity_index(state, 0)
	right = find_node_by_entity_index(state, 1)
	child = find_node_by_entity_index(state, 2)
	testing.expect(t, state.nodes[child].parent_node_index == right)
	testing.expect(t, state.nodes[left].first_child_node == -1)
	testing.expect(t, state.nodes[right].first_child_node == child)
	testing.expect(t, state.nodes[child].rect.x == 200)
}

@(test)
test_table_layout_uses_equal_width_columns_and_wraps_rows :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Table"),
			name = "Table",
			has_ui_layout = true,
			ui_layout = {size = {320, 100}, padding = {10, 10, 10, 10}},
			has_ui_table = true,
			ui_table = {columns = 3, column_gap = 10, row_gap = 4},
		},
	)
	for _ in 0 ..< 5 {
		append(
			&scene.entities,
			shared.Scene_Entity {
				name = "Cell",
				has_ui_layout = true,
				ui_layout = {parent = ui_test_id("Table"), size = {1, 20}},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 100) == "")
	cell_width := f32(280) / 3
	for ordinal in 0 ..< 5 {
		node_index := find_node_by_entity_index(state, ordinal + 1)
		testing.expect(t, node_index >= 0)
		if node_index < 0 { continue }
		column := ordinal % 3
		row := ordinal / 3
		rect := state.nodes[node_index].rect
		testing.expect(t, math.abs(rect.width - cell_width) < 0.01)
		testing.expect(t, math.abs(rect.x - (10 + f32(column) * (cell_width + 10))) < 0.01)
		testing.expect(t, rect.y == 10 + f32(row) * 24)
	}
}

@(test)
test_table_layout_uses_first_row_proportions_and_draggable_separators :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Proportional Table"),
			name = "Proportional Table",
			has_ui_layout = true,
			ui_layout = {size = {320, 100}, padding = {10, 10, 10, 10}},
			has_ui_table = true,
			ui_table = {
				columns = 2,
				column_gap = 10,
				proportional_columns = true,
				resizable_columns = true,
				min_column_width = 48,
			},
		},
	)
	for ordinal in 0 ..< 4 {
		width := f32(1)
		if ordinal % 2 == 1 { width = 2 }
		append(
			&scene.entities,
			shared.Scene_Entity {
				name = "Cell",
				has_ui_layout = true,
				ui_layout = {parent = ui_test_id("Proportional Table"), size = {width, 20}},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 100) == "")
	first := find_node_by_entity_index(state, 1)
	second := find_node_by_entity_index(state, 2)
	third := find_node_by_entity_index(state, 3)
	fourth := find_node_by_entity_index(state, 4)
	testing.expect(t, first >= 0 && second >= 0 && third >= 0 && fourth >= 0)
	testing.expect(t, state.split_handle_count == 1)
	if first < 0 || second < 0 || third < 0 || fourth < 0 { return }
	testing.expect(t, math.abs(state.nodes[first].rect.width - 290.0 / 3.0) < 0.01)
	testing.expect(t, math.abs(state.nodes[second].rect.width - 580.0 / 3.0) < 0.01)
	testing.expect(
		t,
		math.abs(state.nodes[third].rect.width - state.nodes[first].rect.width) < 0.01,
	)
	testing.expect(
		t,
		math.abs(state.nodes[fourth].rect.width - state.nodes[second].rect.width) < 0.01,
	)
	handle := state.split_handles[0]
	point := shared.Vec2{handle.rect.x + handle.rect.width * 0.5, handle.rect.y + 20}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			320,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x += 30
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			320,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.nodes[first].rect.width > 120)
	testing.expect(t, state.nodes[second].rect.width < 180)
	testing.expect(
		t,
		math.abs(state.nodes[third].rect.width - state.nodes[first].rect.width) < 0.01,
	)
	testing.expect(
		t,
		math.abs(state.nodes[fourth].rect.width - state.nodes[second].rect.width) < 0.01,
	)
}

@(test)
test_panel_title_reserves_child_space_and_paints_a_title_band :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Panel"),
			name = "Panel",
			has_ui_layout = true,
			ui_layout = {
				size = {240, 100},
				padding = {8, 8, 8, 8},
				background = {0.05, 0.06, 0.07, 1},
			},
			has_ui_panel = true,
			ui_panel = {
				title = "TRANSFORM",
				title_color = {1, 1, 1, 1},
				title_background = {0.12, 0.13, 0.14, 1},
				title_size = 10,
				title_height = 24,
			},
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Panel"), size = {100, 20}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 100) == "")
	child := find_node_by_entity_index(state, 1)
	testing.expect(t, child >= 0)
	if child >= 0 { testing.expect(t, state.nodes[child].rect.y == 32) }
	found_title_band := false
	title_background := shared.Vec4{0.12, 0.13, 0.14, 1}
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == title_background &&
		   command.rect.height == 24 {
			found_title_band = true
			break
		}
	}
	testing.expect(t, found_title_band)
}

@(test)
test_collapsible_panel_title_toggles_content_layout_and_disclosure :: proc(t: ^testing.T) {
	panel_style := shared.ui_panel_default()
	panel_style.title = "TRANSFORM"
	panel_style.title_color = {1, 1, 1, 1}
	panel_style.title_size = 10
	panel_style.title_height = 24
	panel_style.disclosure_size = 9
	panel_style.disclosure_inset = 0
	panel_style.collapsible = true
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {240, 200}},
			has_ui_vstack = true,
			ui_vstack = {fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Panel"),
			name = "Panel",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {240, 100}},
			has_ui_panel = true,
			ui_panel = panel_style,
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			id = ui_test_id("Panel Child"),
			name = "Panel Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Panel"), size = {200, 30}},
		},
		shared.Scene_Entity {
			id = ui_test_id("Sibling"),
			name = "Sibling",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {240, 100}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 200, resource_registry = &registry) == "")
	panel_node := find_node_by_entity_index(state, 1)
	child_node := find_node_by_entity_index(state, 2)
	sibling_node := find_node_by_entity_index(state, 3)
	testing.expect(t, panel_node >= 0 && child_node >= 0 && sibling_node >= 0)
	if panel_node < 0 || child_node < 0 || sibling_node < 0 { return }
	testing.expect(t, state.nodes[panel_node].rect.height == 100)
	testing.expect(t, state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 100)

	press := Pointer_Input {
		position = {5, 5},
		primary_down = true,
		available = true,
	}
	testing.expect(
		t,
		reconcile(state, &world, 240, 200, press, resource_registry = &registry) == "",
	)
	testing.expect(t, world.ui_panels[0].collapsed)
	testing.expect(t, state.nodes[panel_node].rect.height == 24)
	testing.expect(t, !state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 24)
	testing.expect(t, state.nodes[sibling_node].rect.height == 176)
	found_collapsed_disclosure := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Icon &&
		   command.rect.height == 9 &&
		   command.font_layer == shared.MAX_PROJECT_FONTS + 1 {
			found_collapsed_disclosure = true
			break
		}
	}
	testing.expect(t, found_collapsed_disclosure)

	release := Pointer_Input {
		position = {5, 5},
		available = true,
	}
	testing.expect(
		t,
		reconcile(state, &world, 240, 200, release, resource_registry = &registry) == "",
	)
	testing.expect(
		t,
		reconcile(state, &world, 240, 200, press, resource_registry = &registry) == "",
	)
	testing.expect(t, !world.ui_panels[0].collapsed)
	testing.expect(t, state.nodes[panel_node].rect.height == 100)
	testing.expect(t, state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 100)
}

@(test)
test_panel_hosts_reusable_icon_button_actions :: proc(t: ^testing.T) {
	panel_id := ui_test_id("Composable Action Panel")
	panel := shared.ui_panel_default()
	panel.title = "COMPOSABLE"
	panel.collapsible = true
	button := shared.ui_button_default()
	button.icon_set = shared.builtin_icon_set_uuid()
	button.icon = "x"
	button.panel_action = true
	button.hover_background = {0.2, 0.3, 0.4, 1}
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = panel_id,
			name = "Composable Action Panel",
			has_ui_layout = true,
			ui_layout = {size = {240, 100}},
			has_ui_panel = true,
			ui_panel = panel,
		},
		shared.Scene_Entity {
			id = ui_test_id("Composable Close Action"),
			name = "Composable Close Action",
			has_ui_layout = true,
			ui_layout = {parent = panel_id, size = {22, 22}, margin = {5, 5, 5, 5}},
			has_ui_button = true,
			ui_button = button,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 100, resource_registry = &registry) == "")
	action_node := find_node_by_entity_index(state, 1)
	testing.expect(t, action_node >= 0)
	if action_node < 0 {
		return
	}
	action_rect := state.nodes[action_node].rect
	testing.expect(
		t,
		action_rect.x > 200 && action_rect.y >= 0 && action_rect.y < panel.title_height,
	)
	pointer := Pointer_Input {
		position = {
			action_rect.x + action_rect.width * 0.5,
			action_rect.y + action_rect.height * 0.5,
		},
		primary_down = true,
		available = true,
	}
	testing.expect(
		t,
		reconcile(state, &world, 240, 100, pointer, resource_registry = &registry) == "",
	)
	testing.expect(t, !world.ui_panels[0].collapsed)
	testing.expect(t, world.ui_states[world.entities[1].ui_state_index].activated)
	events := ui_events(state)
	testing.expect(t, len(events) == 1)
	if len(events) == 1 {
		testing.expect(t, events[0].kind == .Activated)
		testing.expect(t, events[0].entity == world.entities[1].id)
	}
	icon_count := 0
	for command in state.paint[:state.paint_count] {
		if command.kind == .Icon &&
		   command.color == button.color &&
		   command.rect.x >= action_rect.x &&
		   command.rect.x + command.rect.width <= action_rect.x + action_rect.width {
			icon_count += 1
		}
	}
	testing.expect(t, icon_count == 1)
}

@(test)
test_single_line_input_selects_edits_navigates_and_tabs_in_paint_order :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_ui_layout = true,
			ui_layout = {
				position = {10, 10},
				size = {160, 28},
				padding = {6, 8, 5, 8},
				background = {0.02, 0.03, 0.04, 1},
				border_color = {0.1, 0.1, 0.1, 1},
				border_width = 1,
			},
			has_ui_input = true,
			ui_input = {
				text = "alpha",
				color = {1, 1, 1, 1},
				size = 12,
				selection_background = {0.1, 0.5, 0.4, 0.5},
				focus_border_color = {0.1, 0.8, 0.7, 1},
			},
		},
		shared.Scene_Entity {
			name = "Second",
			has_ui_layout = true,
			ui_layout = {
				position = {10, 48},
				size = {160, 28},
				padding = {6, 8, 5, 8},
				hidden = true,
			},
			has_ui_input = true,
			ui_input = {text = "second", color = {1, 1, 1, 1}, size = 12},
		},
		shared.Scene_Entity {
			name = "Third",
			has_ui_layout = true,
			ui_layout = {position = {10, 48}, size = {160, 28}, padding = {6, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {text = "third", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = {30, 20}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.has_focused_input && state.focused_input == world.entities[0].id)
	testing.expect(t, state.input_anchor == 0 && state.input_cursor == 5)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {text = "beta"}) == "",
	)
	testing.expect(t, world.ui_inputs[0].text == "beta")
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {home = true}) == "",
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {right = true, shift = true}) ==
		"",
	)
	testing.expect(t, state.input_anchor == 0 && state.input_cursor == 1)
	testing.expect(t, reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {text = "B"}) == "")
	testing.expect(t, world.ui_inputs[0].text == "Beta")
	testing.expect(t, reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {tab = true}) == "")
	testing.expect(t, state.focused_input == world.entities[2].id)
	testing.expect(
		t,
		state.input_anchor == 0 && state.input_cursor == len(world.ui_inputs[2].text),
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {tab = true, shift = true}) == "",
	)
	testing.expect(t, state.focused_input == world.entities[0].id)
}

@(test)
test_numeric_input_exposes_reusable_validation_submit_cancel_and_scrub_state :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Numeric Input",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {160, 28}, padding = {6, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {
				text = "1",
				prefix = "X",
				color = {1, 1, 1, 1},
				prefix_color = {0.9, 0.3, 0.3, 1},
				prefix_background = {0.9, 0.3, 0.3, 0.12},
				size = 12,
				prefix_width = UI_INPUT_PREFIX_WIDTH,
				prefix_gap = 4,
				prefix_corner_radius = 0,
				prefix_text_padding = 2,
				selection_corner_radius = 0,
				focus_border_width = 2,
				invalid_border_width = 3,
				caret_width = 2,
				caret_inset = 3,
				number = 1,
				step = 0.5,
				minimum = 0,
				maximum = 2,
				numeric = true,
				draggable = true,
				has_minimum = true,
				has_maximum = true,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	press := Pointer_Input {
		position = {40, 20},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	found_square_prefix := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == world.ui_inputs[0].prefix_background &&
		   command.corner_radius == 0 {
			found_square_prefix = true
			break
		}
	}
	testing.expect(t, found_square_prefix)
	testing.expect(t, reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {up = true}) == "")
	input := &world.ui_inputs[world.entities[0].ui_input_index]
	interaction := &world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, input.number == 1 && input.text == "1.5")
	testing.expect(t, !interaction.changed && interaction.change_revision == 0)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {enter = true}) == "",
	)
	testing.expect(t, input.number == 1.5 && input.text == "1.5")
	testing.expect(t, interaction.changed && interaction.change_revision == 1)
	testing.expect(t, interaction.submitted && interaction.submit_revision == 1)
	testing.expect(t, interaction.valid)

	// Keyboard edits remain staged until Enter and Escape restores the committed value.
	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {text = "1.75"}) == "",
	)
	testing.expect(t, input.text == "1.75" && input.number == 1.5)
	testing.expect(t, interaction.change_revision == 1)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {escape = true}) == "",
	)
	testing.expect(t, input.text == "1.5" && input.number == 1.5)
	testing.expect(t, interaction.cancelled && interaction.cancel_revision == 1)

	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {text = "bad"}) == "",
	)
	testing.expect(t, !interaction.valid)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {escape = true}) == "",
	)
	testing.expect(t, input.text == "1.5" && input.number == 1.5)
	testing.expect(t, interaction.cancelled && interaction.cancel_revision == 2)
	testing.expect(t, interaction.valid)

	// Draggable numeric inputs scrub from their complete surface.
	drag_start := Pointer_Input {
		position = {120, 20},
		primary_down = true,
		available = true,
	}
	hover := drag_start
	hover.primary_down = false
	testing.expect(t, reconcile(state, &world, 200, 80, hover) == "")
	testing.expect(t, current_pointer_cursor(state) == .Text_Edit)
	testing.expect(t, reconcile(state, &world, 200, 80, drag_start) == "")
	testing.expect(t, current_pointer_cursor(state) == .Text_Edit)
	drag := drag_start
	drag.position.x += 8
	testing.expect(t, reconcile(state, &world, 200, 80, drag) == "")
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	testing.expect(t, input.number == 2 && input.text == "2")
	drag.primary_down = false
	testing.expect(t, reconcile(state, &world, 200, 80, drag) == "")
	testing.expect(t, interaction.submitted && interaction.submit_revision == 2)
}

@(test)
test_numeric_input_only_scrubs_when_draggable_is_enabled :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Numeric Input",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {160, 28}},
			has_ui_input = true,
			ui_input = {text = "1", number = 1, step = 0.5, numeric = true},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	press := Pointer_Input {
		position = {80, 20},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	testing.expect(t, current_pointer_cursor(state) == .Text_Edit)
	drag := press
	drag.position.x += 20
	testing.expect(t, reconcile(state, &world, 200, 80, drag) == "")
	testing.expect(t, world.ui_inputs[0].number == 1)
	testing.expect(t, !state.input_scrubbing)
}

@(test)
test_color_picker_edits_direct_linear_hdr_rgba_and_submits_once :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "HDR Color",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {200, 180}},
			has_ui_color_picker = true,
			ui_color_picker = shared.ui_color_picker_default(),
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	press := Pointer_Input {
		position = {110, 180},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 240, 220, press) == "")
	testing.expect(t, current_pointer_cursor(state) == .Pointer)
	picker := &world.ui_color_pickers[world.entities[0].ui_color_picker_index]
	interaction := &world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, math.abs(picker.exposure - 8) < 0.001)
	testing.expect(t, math.abs(picker.value.x - 256) < 0.01)
	testing.expect(t, picker.value == shared.Vec4{256, 256, 256, 1})
	testing.expect(t, interaction.changed && interaction.change_revision == 1)

	release := press
	release.primary_down = false
	testing.expect(t, reconcile(state, &world, 240, 220, release) == "")
	testing.expect(t, interaction.submitted && interaction.submit_revision == 1)

	testing.expect(t, reconcile(state, &world, 240, 220, {}) == "")
	stable_revision := world.ui_editor_paint_revision + world.ui_project_paint_revision
	testing.expect(t, reconcile(state, &world, 240, 220, {}) == "")
	testing.expect(
		t,
		world.ui_editor_paint_revision + world.ui_project_paint_revision == stable_revision,
	)
}

@(test)
test_fill_stack_allocates_available_space_and_drags_between_adjacent_panes :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {600, 200}, padding = {10, 10, 10, 10}},
			has_ui_hstack = true,
			ui_hstack = {gap = 6, fill = true, draggable = true, min_size = 80},
		},
		shared.Scene_Entity {
			name = "Left",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
		shared.Scene_Entity {
			name = "Center",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {200, 20}},
		},
		shared.Scene_Entity {
			name = "Right",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 600, 200) == "")
	left := find_node_by_entity_index(
		state,
		1,
	); center := find_node_by_entity_index(state, 2); right := find_node_by_entity_index(state, 3)
	testing.expect(t, left >= 0 && center >= 0 && right >= 0 && state.split_handle_count == 2)
	if left >= 0 && center >= 0 && right >= 0 {
		testing.expect(t, math.abs(state.nodes[left].rect.width - 142) < 0.01)
		testing.expect(t, math.abs(state.nodes[center].rect.width - 284) < 0.01)
		testing.expect(t, math.abs(state.nodes[right].rect.width - 142) < 0.01)
		testing.expect(
			t,
			state.nodes[left].rect.height == 180 && state.nodes[center].rect.height == 180,
		)
		handle := state.split_handles[0]
		point := shared.Vec2{handle.rect.x + handle.rect.width * 0.5, handle.rect.y + 20}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				600,
				200,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
		point.x += 40
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				600,
				200,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(
			t,
			state.nodes[left].rect.width > 180 && state.nodes[center].rect.width < 250,
		)
		testing.expect(t, math.abs(state.nodes[right].rect.width - 142) < 0.1)
	}
}

@(test)
test_vertical_fill_stack_drags_and_fills_the_cross_axis :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 400}, padding = {10, 10, 10, 10}},
			has_ui_vstack = true,
			ui_vstack = {gap = 8, fill = true, draggable = true, min_size = 100},
		},
		shared.Scene_Entity {
			name = "Top",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {20, 100}},
		},
		shared.Scene_Entity {
			name = "Bottom",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {20, 100}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 400) == "")
	top := find_node_by_entity_index(state, 1)
	bottom := find_node_by_entity_index(state, 2)
	testing.expect(t, top >= 0 && bottom >= 0 && state.split_handle_count == 1)
	if top >= 0 && bottom >= 0 {
		testing.expect(t, state.nodes[top].rect == Rect{10, 10, 180, 186})
		handle := state.split_handles[0]
		point := shared.Vec2{handle.rect.x + 20, handle.rect.y + handle.rect.height * 0.5}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				200,
				400,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
		point.y += 30
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				200,
				400,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, math.abs(state.nodes[top].rect.height - 216) < 0.01)
		testing.expect(t, math.abs(state.nodes[bottom].rect.height - 156) < 0.01)
	}
}

@(test)
test_ui_text_right_alignment_uses_the_padded_content_edge :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Timing",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}, padding = {4, 7, 3, 5}},
			has_ui_text = true,
			ui_text = {text = "12", color = {1, 1, 1, 1}, size = 12, alignment = .Right},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60) == "")
	advance := text_advance_to(state, "12", 12, 2)
	expected_start := f32(10 + 100 - 7) - advance
	first_glyph := -1
	for command, index in state.paint[:state.paint_count] {
		if command.kind == .Glyph {
			first_glyph = index
			break
		}
	}
	testing.expect(t, first_glyph >= 0)
	if first_glyph >= 0 {
		glyph := state.font.glyphs^[int('1') - FONT_FIRST_CHAR]
		expected_ink_x := expected_start + glyph.plane.x * 12
		testing.expect(t, math.abs(state.paint[first_glyph].rect.x - expected_ink_x) < 0.001)
	}
}

@(test)
test_ui_button_alignment_uses_the_padded_content_edge :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Action",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}, padding = {4, 7, 3, 5}},
			has_ui_button = true,
			ui_button = {text = "GO", color = {1, 1, 1, 1}, size = 12, alignment = .Right},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60) == "")
	rightmost_ink := f32(-10000)
	for command in state.paint[:state.paint_count] {
		if command.kind == .Glyph {
			rightmost_ink = max(rightmost_ink, command.rect.x + command.rect.width)
		}
	}
	testing.expect(t, math.abs(rightmost_ink - 103) < 0.001)
}

@(test)
test_ui_icon_uses_the_builtin_catalog_layer :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Play",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {32, 32}},
			has_ui_icon = true,
			ui_icon = {
				icon_set = shared.builtin_icon_set_uuid(),
				icon = "play",
				color = {1, 1, 1, 1},
				inset = 2,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 64, 64, resource_registry = &registry) == "")
	found := false
	for command in state.paint[:state.paint_count] {
		if command.kind != .Icon {
			continue
		}
		found = true
		testing.expect(t, command.font_layer == shared.MAX_PROJECT_FONTS + 1)
		testing.expect(t, command.rect.width > 0 && command.rect.height > 0)
	}
	testing.expect(t, found)
}

@(test)
test_ui_input_icons_reserve_content_on_either_edge :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Leading",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {120, 30}, padding = {5, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {
				text = "find",
				icon_set = shared.builtin_icon_set_uuid(),
				icon = "magnifying-glass",
				icon_position = .Leading,
				color = {1, 1, 1, 1},
				icon_color = {0.5, 0.6, 0.7, 1},
				size = 12,
				icon_size = 14,
				icon_gap = 5,
			},
		},
		shared.Scene_Entity {
			name = "Trailing",
			has_ui_layout = true,
			ui_layout = {position = {10, 50}, size = {120, 30}, padding = {5, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {
				text = "find",
				icon_set = shared.builtin_icon_set_uuid(),
				icon = "magnifying-glass",
				icon_position = .Trailing,
				color = {1, 1, 1, 1},
				icon_color = {0.5, 0.6, 0.7, 1},
				size = 12,
				icon_size = 14,
				icon_gap = 5,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 160, 100, resource_registry = &registry) == "")

	leading_icon_x, trailing_icon_x := f32(-1), f32(-1)
	leading_glyph_x, trailing_glyph_x := f32(-1), f32(-1)
	for command in state.paint[:state.paint_count] {
		if command.kind == .Icon {
			if command.rect.y < 40 {
				leading_icon_x = command.rect.x
			} else {
				trailing_icon_x = command.rect.x
			}
		}
		if command.kind == .Glyph {
			if command.rect.y < 40 && leading_glyph_x < 0 {
				leading_glyph_x = command.rect.x
			}
			if command.rect.y >= 40 && trailing_glyph_x < 0 {
				trailing_glyph_x = command.rect.x
			}
		}
	}
	testing.expect(t, leading_icon_x >= 18 && leading_icon_x < 32)
	testing.expect(t, leading_glyph_x > leading_icon_x + 10)
	testing.expect(t, trailing_glyph_x < trailing_icon_x)
	testing.expect(t, trailing_icon_x > 100 && trailing_icon_x < 122)
}

@(test)
test_ui_text_selects_a_project_font_atlas_layer :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	pixels := make([]u8, FONT_ATLAS_SIZE * FONT_ATLAS_SIZE * 4)
	defer delete(pixels)
	desc := resources.Font_Desc {
		pixels = pixels,
		width = FONT_ATLAS_SIZE,
		height = FONT_ATLAS_SIZE,
		ascender = 0.8,
	}
	desc.glyphs[int('A') - FONT_FIRST_CHAR] = {
		advance = 0.75,
		plane = {0, -0.8, 0.7, 0.2},
		uv = {0, 0, 0.1, 0.1},
	}
	_, font_err := resources.register_font(&registry, "display", desc)
	testing.expect(t, font_err == "")

	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Title",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}},
			has_ui_text = true,
			ui_text = {text = "A", font = "display", color = {1, 1, 1, 1}, size = 10},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60, {}, 0, 0, 1.0 / 60.0, {}, &registry) == "")

	glyph_found := false
	for command in state.paint[:state.paint_count] {
		if command.kind != .Glyph { continue }
		glyph_found = true
		testing.expect(t, command.font_layer == 1)
		break
	}
	testing.expect(t, glyph_found)
}

@(test)
test_box_model_applies_margins_padding_and_rounded_button_paint :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {position = {20, 30}, size = {300, 120}, padding = {10, 10, 10, 10}},
			has_ui_hstack = true,
			ui_hstack = {gap = 6},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				size = {100, 40},
				margin = {2, 3, 4, 5},
				padding = {8, 8, 8, 8},
				background = {0.2, 0.4, 0.8, 1},
				border_color = {0.7, 0.8, 1, 1},
				border_width = 2,
				corner_radius = 12,
			},
			has_ui_button = true,
			ui_button = {text = "GO", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	button := find_node_by_entity_index(state, 1); testing.expect(t, button >= 0)
	if button >=
	   0 { testing.expect(t, state.nodes[button].rect.x == 35); testing.expect(t, state.nodes[button].rect.y == 42) }
	testing.expect(t, state.paint_count >= 3)
	if state.paint_count > 0 {
		testing.expect(t, state.paint[0].corner_radius == 12)
		testing.expect(t, state.paint[0].border_color == shared.Vec4{0.7, 0.8, 1, 1})
		testing.expect(t, state.paint[0].border_width == 2)
	}
}

@(test)
test_hidden_ui_box_removes_its_entire_subtree_without_despawning_entities :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}, hidden = true},
		},
		shared.Scene_Entity {
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 40}},
			has_ui_text = true,
			ui_text = {text = "Hidden", color = {1, 1, 1, 1}, size = 14},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 0)
	testing.expect(t, world.entities[0].alive && world.entities[1].alive)
}

@(test)
test_pointer_states_belong_to_elements_and_buttons_consume_them :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {300, 120}},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				position = {20, 20},
				size = {100, 40},
				background = {0.1, 0.2, 0.3, 1},
			},
			has_ui_button = true,
			ui_button = {
				text = "GO",
				color = {1, 1, 1, 1},
				size = 16,
				alignment = .Center,
				hover_background = {0.2, 0.4, 0.6, 1},
				active_background = {0.05, 0.1, 0.15, 1},
			},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	button := 1

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {30, 30}, available = true}) == "",
	)
	testing.expect(t, current_pointer_cursor(state) == .Pointer)
	testing.expect(t, state.nodes[button].hovered && !state.nodes[button].active)
	button_state := &world.ui_states[world.entities[button].ui_state_index]
	testing.expect(t, button_state.hovered && !button_state.active && !button_state.activated)
	testing.expect(t, state.paint[0].color == shared.Vec4{0.2, 0.4, 0.6, 1})
	ink_min_x, ink_min_y, ink_max_x, ink_max_y := f32(10000), f32(10000), f32(-10000), f32(-10000)
	for command in state.paint[:state.paint_count] { if command.kind == .Glyph { ink_min_x = min(ink_min_x, command.rect.x); ink_min_y = min(ink_min_y, command.rect.y); ink_max_x = max(ink_max_x, command.rect.x + command.rect.width); ink_max_y = max(ink_max_y, command.rect.y + command.rect.height) } }
	delta_x := (ink_min_x + ink_max_x) * 0.5 - 70; if delta_x < 0 { delta_x = -delta_x }
	delta_y := (ink_min_y + ink_max_y) * 0.5 - 40; if delta_y < 0 { delta_y = -delta_y }
	testing.expect(t, delta_x < 0.001 && delta_y < 0.001)

	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {30, 30}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.nodes[button].hovered && state.nodes[button].active)
	testing.expect(t, button_state.hovered && button_state.active && button_state.activated)
	testing.expect(t, button_state.activation_revision == 1)
	testing.expect(t, state.paint[0].color == shared.Vec4{0.05, 0.1, 0.15, 1})

	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {500, 500}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, !state.nodes[button].hovered && state.nodes[button].active)
	testing.expect(t, !button_state.hovered && button_state.active && !button_state.activated)

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {500, 500}, available = true}) == "",
	)
	testing.expect(t, !state.nodes[button].hovered && !state.nodes[button].active)
}

@(test)
test_scroll_area_clips_descendants_and_smoothly_approaches_wheel_target :: proc(t: ^testing.T) {
	scroll_style := shared.ui_scroll_area_default()
	scroll_style.scroll_speed = 60
	scroll_style.smoothness = 12
	scroll_style.scrollbar_width = 5
	scroll_style.scrollbar_corner_radius = 0
	scroll_style.scrollbar_thumb_color = {0.7, 0.8, 0.9, 1}
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Scroll"),
			name = "Scroll",
			has_ui_layout = true,
			ui_layout = {
				position = {20, 20},
				size = {200, 100},
				padding = {10, 10, 10, 10},
				background = {0.08, 0.09, 0.11, 1},
			},
			has_ui_scroll_area = true,
			ui_scroll_area = scroll_style,
		},
		shared.Scene_Entity {
			id = ui_test_id("Pane"),
			name = "Pane",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Scroll"),
				size = {180, 300},
				background = {0.12, 0.13, 0.15, 1},
			},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Pane"),
				position = {10, 75},
				size = {150, 40},
				background = {0.2, 0.3, 0.4, 1},
			},
			has_ui_button = true,
			ui_button = {text = "CLIPPED", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)

	// The button occupies this point geometrically, but the scroll viewport clips it.
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {40, 115}, available = true}) == "",
	)
	scroll := find_node_by_entity_index(
		state,
		0,
	); pane := find_node_by_entity_index(state, 1); button := find_node_by_entity_index(state, 2)
	testing.expect(t, scroll >= 0 && pane >= 0 && button >= 0)
	if scroll >= 0 && pane >= 0 && button >= 0 {
		testing.expect(t, state.nodes[scroll].scroll_max == 220)
		testing.expect(t, state.nodes[pane].clip == Rect{30, 30, 180, 80})
		testing.expect(t, !state.nodes[button].hovered)
	}
	clipped_paint := false
	expected_clip := Rect{30, 30, 180, 80}
	for command in state.paint[:state.paint_count] { if command.has_clip && command.clip == expected_clip { clipped_paint = true; break } }
	testing.expect(t, clipped_paint)
	found_custom_thumb := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == scroll_style.scrollbar_thumb_color &&
		   command.rect.width == 5 &&
		   command.corner_radius == 0 {
			found_custom_thumb = true
			break
		}
	}
	testing.expect(t, found_custom_thumb)

	initial_pane_y := state.nodes[pane].rect.y
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {40, 40}, wheel_y = -1, available = true},
			0,
			0,
			1.0 / 60.0,
		) ==
		"",
	)
	testing.expect(t, state.nodes[scroll].scroll_target == 60)
	testing.expect(
		t,
		state.nodes[scroll].scroll_offset > 0 && state.nodes[scroll].scroll_offset < 60,
	)
	testing.expect(t, state.nodes[pane].rect.y < initial_pane_y)
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0) == "") }
	testing.expect(t, math.abs(state.nodes[scroll].scroll_offset - 60) < 0.02)

	// A later entity occupying a released retained-node slot starts at the top.
	for &entity, entity_index in world.entities {
		entity.alive = false
		ecs.mark_ui_entity_dirty(&world, entity_index)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	for &entity, entity_index in world.entities {
		entity.alive = true
		ecs.mark_ui_entity_dirty(&world, entity_index)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	scroll = find_node_by_entity_index(state, 0)
	testing.expect(
		t,
		scroll >= 0 &&
		state.nodes[scroll].scroll_offset == 0 &&
		state.nodes[scroll].scroll_target == 0,
	)
}

@(test)
test_editor_shell_is_an_editor_origin_ecs_ui_tree :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Game UI",
			has_ui_layout = true,
			ui_layout = {size = {100, 40}, background = {0.2, 0.3, 0.4, 1}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	root := find_editor_role_node(state, .Root)
	viewport_node := find_editor_role_node(state, .Viewport)
	testing.expect(t, root >= 0 && viewport_node >= 0)
	viewport_dock, viewport_dock_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_VIEWPORT_DOCK_NAME),
	)
	testing.expect(t, viewport_dock_found)
	if viewport_dock_found {
		dock_entity := world.entities[viewport_dock]
		testing.expect(t, dock_entity.ui_dock_space_index >= 0)
		testing.expect(t, dock_entity.ui_layout_index >= 0)
		if dock_entity.ui_layout_index >= 0 {
			testing.expect(t, world.ui_layouts[dock_entity.ui_layout_index].background.w == 0)
		}
		if dock_entity.ui_dock_space_index >= 0 {
			dock_space := world.ui_dock_spaces[dock_entity.ui_dock_space_index]
			testing.expect(t, dock_space.content_background.w == 0)
			testing.expect(t, dock_space.tab_active_background.w > 0)
			testing.expect_value(
				t,
				dock_space.tab_active_background,
				reduced_dark_theme().palette.panel,
			)
			testing.expect_value(t, dock_space.content_padding, shared.Vec4{})
		}
	}
	if viewport_node >= 0 {
		viewport_entity := world.entities[int(state.nodes[viewport_node].entity.index)]
		testing.expect(t, viewport_entity.ui_layout_index >= 0)
		if viewport_entity.ui_layout_index >= 0 {
			testing.expect(t, world.ui_layouts[viewport_entity.ui_layout_index].background.w == 0)
			testing.expect_value(
				t,
				world.ui_layouts[viewport_entity.ui_layout_index].parent,
				shared.entity_uuid_from_engine_name(EDITOR_UI_VIEWPORT_TAB_NAME),
			)
		}
	}
	viewport_tab, viewport_tab_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_VIEWPORT_TAB_NAME),
	)
	testing.expect(t, viewport_tab_found)
	if viewport_tab_found {
		tab_entity := world.entities[viewport_tab]
		testing.expect(t, tab_entity.ui_dock_item_index >= 0)
		testing.expect(t, tab_entity.ui_vstack_index >= 0)
		if tab_entity.ui_dock_item_index >= 0 {
			testing.expect(t, !world.ui_dock_items[tab_entity.ui_dock_item_index].movable)
		}
		if tab_entity.ui_vstack_index >= 0 {
			testing.expect(t, world.ui_vstacks[tab_entity.ui_vstack_index].reorderable)
		}
	}
	testing.expect(t, len(world.editor_uis) > 0)
	for component, component_index in world.editor_uis {
		testing.expect(
			t,
			component.entity_index >= 0 && component.entity_index < len(world.entities),
		)
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive)
		testing.expect(t, entity.origin == .Editor)
		testing.expect(t, entity.editor_ui_index == component_index)
		testing.expect(t, entity.ui_layout_index >= 0)
		if entity.ui_text_index >= 0 {
			testing.expect(t, world.ui_texts[entity.ui_text_index].size == EDITOR_TEXT_SIZE)
		}
	}
	if root >= 0 {
		entity := world.entities[int(state.nodes[root].entity.index)]
		testing.expect(t, entity.origin == .Editor && entity.ui_layout_index >= 0)
	}
	viewport := editor_viewport(state, 1280, 720)
	if viewport_node >= 0 { testing.expect(t, viewport == state.nodes[viewport_node].rect) }
	testing.expect(t, state.editor_paint_start == 1)
	testing.expect(t, state.paint_count > state.editor_paint_start)
	project_revision := state.project_paint_output_revision
	editor_revision := state.editor_paint_output_revision
	editor_command_count := state.editor_paint_end - state.editor_paint_start
	project_layout := world.ui_layouts[world.entities[0].ui_layout_index]
	project_layout.background = {0.7, 0.2, 0.1, 1}
	testing.expect(t, ecs.set_ui_layout(&world, 0, project_layout))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.project_paint_output_revision > project_revision)
	testing.expect_value(t, state.editor_paint_output_revision, editor_revision)
	testing.expect_value(
		t,
		state.editor_paint_end - state.editor_paint_start,
		editor_command_count,
	)
	pointer := project_pointer_input(
		state,
		{
			position = {viewport.x + viewport.width * 0.5, viewport.y + viewport.height * 0.5},
			available = true,
		},
		1280,
		720,
	)
	project_transform := project_canvas_transform(state, 1280, 720)
	testing.expect(
		t,
		pointer.available &&
		math.abs(pointer.position.x - viewport.width * 0.5 / project_transform.scale.x) < 0.01 &&
		math.abs(pointer.position.y - viewport.height * 0.5 / project_transform.scale.y) < 0.01,
	)
	testing.expect(
		t,
		!project_pointer_input(state, {position = {20, 100}, available = true}, 1280, 720).available,
	)

	// ECS layout components and the derived viewport follow the full available drawable.
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 2048, 1096) == "")
	viewport = editor_viewport(state, 2048, 1096)
	viewport_node = find_editor_role_node(state, .Viewport)
	testing.expect(t, viewport_node >= 0 && viewport == state.nodes[viewport_node].rect)
	testing.expect(t, viewport.width > 980 && viewport.height > 900)
	testing.expect(t, state.paint[state.editor_paint_start].rect.width == 2048)
	pointer = project_pointer_input(
		state,
		{
			position = {viewport.x + viewport.width * 0.5, viewport.y + viewport.height * 0.5},
			available = true,
		},
		1280,
		720,
		2048,
		1096,
	)
	project_transform = project_canvas_transform(state, 2048, 1096)
	testing.expect(
		t,
		pointer.available &&
		math.abs(pointer.position.x - viewport.width * 0.5 / project_transform.scale.x) < 0.01 &&
		math.abs(pointer.position.y - viewport.height * 0.5 / project_transform.scale.y) < 0.01,
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{
				position = {viewport.x + 100, viewport.y + 100},
				primary_down = true,
				available = true,
			},
			2048,
			1096,
		) ==
		"",
	)
	testing.expect(t, state.editor_pick_requested)
	testing.expect(
		t,
		state.editor_pick_position == shared.Vec2{viewport.x + 100, viewport.y + 100},
	)

	// Native-density windows keep the same logical chrome size while painting at 2x resolution.
	state.editor_pixel_density = 2
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 2560, 1440) == "")
	viewport = editor_viewport(state, 2560, 1440)
	viewport_node = find_editor_role_node(state, .Viewport)
	if viewport_node >=
	   0 { testing.expect(t, viewport == Rect{state.nodes[viewport_node].rect.x * 2, state.nodes[viewport_node].rect.y * 2, state.nodes[viewport_node].rect.width * 2, state.nodes[viewport_node].rect.height * 2}) }
	testing.expect(
		t,
		state.paint[state.editor_paint_start].rect == Rect{0, 0, 2560, EDITOR_TOP_BAR_HEIGHT * 2},
	)

	// The chrome is composed from the same ECS stack components as project UI.
	state.editor_pixel_density = 1
	testing.expect(t, reconcile(state, &world, 760, 720, {}, 760, 720) == "")
	top_index, status_index := -1, -1
	for entity, entity_index in world.entities {
		switch entity.name {
			case EDITOR_UI_TOP_NAME:
				top_index = entity_index
			case EDITOR_UI_STATUS_NAME:
				status_index = entity_index
			case "__scrapbot_editor_signal_rail",
			     "__scrapbot_editor_subtitle",
			     "__scrapbot_editor_tool_hint",
			     "__scrapbot_editor_status_hint":
				testing.expect(t, false)
		}
	}
	testing.expect(t, top_index >= 0 && world.entities[top_index].ui_hstack_index >= 0)
	testing.expect(t, status_index >= 0 && world.entities[status_index].ui_hstack_index >= 0)
}

@(test)
test_editor_gizmo_space_toolbar_is_ecs_ui_and_follows_selection :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Rotated Cube",
			has_transform = true,
			transform = {rotation = {0, 0, math.PI / 2}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	toolbar, toolbar_found := editor_ui_entity(&world, .Gizmo_Toolbar)
	world_button, world_found := editor_ui_entity(&world, .Gizmo_Space_World)
	local_button, local_found := editor_ui_entity(&world, .Gizmo_Space_Local)
	testing.expect(t, toolbar_found && world_found && local_found)
	if !toolbar_found || !world_found || !local_found {
		return
	}
	toolbar_layout := world.entities[toolbar].ui_layout_index
	testing.expect(t, toolbar_layout >= 0 && world.ui_layouts[toolbar_layout].hidden)

	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 0))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	toolbar_node := find_editor_role_node(state, .Gizmo_Toolbar)
	viewport_node := find_editor_role_node(state, .Viewport)
	world_button_node := find_node_by_entity_index(state, world_button)
	testing.expect(t, toolbar_node >= 0 && viewport_node >= 0)
	testing.expect(t, !world.ui_layouts[toolbar_layout].hidden)
	if toolbar_node >= 0 {
		point := shared.Vec2 {
			state.nodes[toolbar_node].rect.x + state.nodes[toolbar_node].rect.width * 0.5,
			state.nodes[toolbar_node].rect.y + state.nodes[toolbar_node].rect.height * 0.5,
		}
		testing.expect(
			t,
			editor_pointer_over_gizmo_toolbar(state, {position = point, available = true}),
		)
	}
	if world_button_node >= 0 {
		button_point := shared.Vec2 {
			state.nodes[world_button_node].rect.x +
			state.nodes[world_button_node].rect.width * 0.5,
			state.nodes[world_button_node].rect.y +
			state.nodes[world_button_node].rect.height * 0.5,
		}
		testing.expect(
			t,
			editor_pointer_consumed_by_chrome(state, {position = button_point, available = true}),
		)
	}
	if viewport_node >= 0 {
		viewport_point := shared.Vec2 {
			state.nodes[viewport_node].rect.x + state.nodes[viewport_node].rect.width * 0.5,
			state.nodes[viewport_node].rect.y + state.nodes[viewport_node].rect.height * 0.5,
		}
		testing.expect(
			t,
			!editor_pointer_over_gizmo_toolbar(
				state,
				{position = viewport_point, available = true},
			),
		)
		testing.expect(
			t,
			!editor_pointer_consumed_by_chrome(
				state,
				{position = viewport_point, available = true},
			),
		)
	}

	state.editor_gizmo_active_handle = .X
	state.editor_gizmo_captures_pointer = true
	state.editor_snapshot_valid = true
	editor_ui_handle_activation(state, &world, world.entities[local_button].id, {})
	testing.expect(t, state.editor_gizmo_space == .Local)
	testing.expect(t, state.editor_gizmo_active_handle == .None)
	testing.expect(t, !state.editor_gizmo_captures_pointer && !state.editor_snapshot_valid)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	local_layout := world.entities[local_button].ui_layout_index
	world_layout := world.entities[world_button].ui_layout_index
	testing.expect(
		t,
		world.ui_layouts[local_layout].background.y > world.ui_layouts[world_layout].background.y,
	)

	editor_clear_selection(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, world.ui_layouts[toolbar_layout].hidden)
}

@(test)
test_editor_game_view_debug_selector_is_transient_public_ui :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Camera",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_camera = true,
			camera = shared.camera_defaults(),
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	button, button_found := editor_ui_entity(&world, .Debug_View_Button)
	menu, menu_found := editor_ui_entity(&world, .Debug_View_Menu)
	meshlets, meshlets_found := editor_ui_entity(
		&world,
		.Debug_View_Item,
		int(shared.Render_Debug_View.Meshlets),
	)
	visibility, visibility_found := editor_ui_entity(
		&world,
		.Debug_View_Item,
		int(shared.Render_Debug_View.Meshlet_Visibility),
	)
	hiz, hiz_found := editor_ui_entity(&world, .Debug_View_Item, int(shared.Render_Debug_View.HiZ))
	occlusion, occlusion_found := editor_ui_entity(
		&world,
		.Debug_View_Item,
		int(shared.Render_Debug_View.Occlusion_Queries),
	)
	distance_field, distance_field_found := editor_ui_entity(
		&world,
		.Debug_View_Item,
		int(shared.Render_Debug_View.Distance_Field),
	)
	world_distance_field, world_distance_field_found := editor_ui_entity(
		&world,
		.Debug_View_Item,
		int(shared.Render_Debug_View.World_Distance_Field),
	)
	hiz_increase, hiz_increase_found := editor_ui_entity(&world, .Debug_HiZ_Mip_Increase)
	hiz_label, hiz_label_found := editor_ui_entity(&world, .Debug_HiZ_Mip_Label)
	freeze, freeze_found := editor_ui_entity(&world, .Debug_Occlusion_Freeze)
	camera_item, camera_item_found := editor_ui_entity(&world, .Debug_View_Item, -1)
	testing.expect(
		t,
		button_found &&
		menu_found &&
		meshlets_found &&
		visibility_found &&
		hiz_found &&
		occlusion_found &&
		distance_field_found &&
		world_distance_field_found &&
		hiz_increase_found &&
		hiz_label_found &&
		freeze_found &&
		camera_item_found,
	)
	if !button_found ||
	   !menu_found ||
	   !meshlets_found ||
	   !visibility_found ||
	   !hiz_found ||
	   !occlusion_found ||
	   !distance_field_found ||
	   !world_distance_field_found ||
	   !hiz_increase_found ||
	   !hiz_label_found ||
	   !freeze_found ||
	   !camera_item_found {
		return
	}
	testing.expect(t, world.entities[button].ui_button_index >= 0)
	testing.expect(t, world.entities[menu].ui_layout_index >= 0)
	testing.expect(
		t,
		world.ui_buttons[world.entities[button].ui_button_index].popup ==
		world.entities[menu].uuid,
	)
	testing.expect(t, !state.editor_render_debug_view_override)
	state.editor_pick_requested = false
	editor_ui_handle_activation(state, &world, world.entities[button].id, {32, 24})
	testing.expect(t, !state.editor_pick_requested)
	project_camera := world.cameras[0]
	project_camera.debug_view = .Depth
	project_camera.debug_hiz_mip = 3
	project_camera.debug_occlusion_freeze = true
	testing.expect(t, effective_render_debug_view(state, project_camera) == .Depth)
	testing.expect_value(t, effective_render_debug_hiz_mip(state, project_camera), u32(3))
	testing.expect(t, effective_render_debug_occlusion_freeze(state, project_camera))

	editor_ui_handle_activation(state, &world, world.entities[meshlets].id, {})
	testing.expect(t, state.editor_render_debug_view_override)
	testing.expect(t, state.editor_render_debug_view == .Meshlets)
	testing.expect(t, effective_render_debug_view(state, project_camera) == .Meshlets)
	testing.expect_value(
		t,
		world.ui_buttons[world.entities[button].ui_button_index].text,
		"VIEW / MESHLETS",
	)
	testing.expect(t, world.cameras[0].debug_view == .Lit)

	editor_ui_handle_activation(state, &world, world.entities[visibility].id, {})
	testing.expect(t, state.editor_render_debug_view == .Meshlet_Visibility)
	testing.expect_value(
		t,
		world.ui_buttons[world.entities[button].ui_button_index].text,
		"VIEW / MESHLET VISIBILITY",
	)

	editor_ui_handle_activation(state, &world, world.entities[hiz].id, {})
	testing.expect(t, state.editor_render_debug_view == .HiZ)
	testing.expect(t, !world.ui_layouts[world.entities[hiz_label].ui_layout_index].hidden)
	editor_ui_handle_activation(state, &world, world.entities[hiz_increase].id, {})
	editor_ui_handle_activation(state, &world, world.entities[hiz_increase].id, {})
	testing.expect_value(t, effective_render_debug_hiz_mip(state, project_camera), u32(2))
	testing.expect_value(t, world.ui_texts[world.entities[hiz_label].ui_text_index].text, "MIP 2")

	editor_ui_handle_activation(state, &world, world.entities[occlusion].id, {})
	testing.expect(t, state.editor_render_debug_view == .Occlusion_Queries)
	testing.expect(t, world.ui_layouts[world.entities[hiz_label].ui_layout_index].hidden)
	testing.expect(t, !world.ui_layouts[world.entities[freeze].ui_layout_index].hidden)
	testing.expect(t, !effective_render_debug_occlusion_freeze(state, project_camera))
	editor_ui_handle_activation(state, &world, world.entities[freeze].id, {})
	testing.expect(t, effective_render_debug_occlusion_freeze(state, project_camera))
	testing.expect_value(
		t,
		world.ui_buttons[world.entities[freeze].ui_button_index].text,
		"FROZEN",
	)

	editor_ui_handle_activation(state, &world, world.entities[distance_field].id, {})
	testing.expect(t, state.editor_render_debug_view == .Distance_Field)
	testing.expect_value(
		t,
		world.ui_buttons[world.entities[button].ui_button_index].text,
		"VIEW / DISTANCE FIELD",
	)

	editor_ui_handle_activation(state, &world, world.entities[world_distance_field].id, {})
	testing.expect(t, state.editor_render_debug_view == .World_Distance_Field)
	testing.expect_value(
		t,
		world.ui_buttons[world.entities[button].ui_button_index].text,
		"VIEW / WORLD DISTANCE FIELD",
	)

	editor_ui_handle_activation(state, &world, world.entities[camera_item].id, {})
	testing.expect(t, !state.editor_render_debug_view_override)
	testing.expect(t, effective_render_debug_view(state, project_camera) == .Depth)
	testing.expect(t, world.ui_layouts[world.entities[hiz_label].ui_layout_index].hidden)
	testing.expect(t, world.ui_layouts[world.entities[freeze].ui_layout_index].hidden)
	testing.expect_value(t, effective_render_debug_hiz_mip(state, project_camera), u32(3))
	testing.expect(t, effective_render_debug_occlusion_freeze(state, project_camera))
}

@(test)
test_editor_transport_buttons_preserve_unsaved_authoring_across_playback :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	play := find_editor_role_node(state, .Transport_Play)
	pause := find_editor_role_node(state, .Transport_Pause)
	stop := find_editor_role_node(state, .Transport_Stop)
	step := find_editor_role_node(state, .Transport_Step)
	undo := find_editor_role_node(state, .Transport_Undo)
	redo := find_editor_role_node(state, .Transport_Redo)
	save := find_editor_role_node(state, .Transport_Save)
	revert := find_editor_role_node(state, .Transport_Revert)
	status := find_editor_role_node(state, .Status)
	viewport := find_editor_role_node(state, .Viewport)
	testing.expect(
		t,
		play >= 0 &&
		pause >= 0 &&
		stop >= 0 &&
		step >= 0 &&
		undo >= 0 &&
		redo >= 0 &&
		save >= 0 &&
		revert >= 0 &&
		status >= 0 &&
		viewport >= 0,
	)
	if play < 0 ||
	   pause < 0 ||
	   stop < 0 ||
	   step < 0 ||
	   undo < 0 ||
	   redo < 0 ||
	   save < 0 ||
	   revert < 0 ||
	   status < 0 ||
	   viewport < 0 {
		return
	}
	pause_entity := world.entities[int(state.nodes[pause].entity.index)]
	testing.expect(t, world.ui_buttons[pause_entity.ui_button_index].text == "PAUSE")
	stop_entity := world.entities[int(state.nodes[stop].entity.index)]
	testing.expect(t, world.ui_buttons[stop_entity.ui_button_index].text == "STOP")
	save_entity := world.entities[int(state.nodes[save].entity.index)]
	testing.expect(t, world.ui_buttons[save_entity.ui_button_index].text == "SAVE")
	undo_entity := world.entities[int(state.nodes[undo].entity.index)]
	testing.expect(t, world.ui_buttons[undo_entity.ui_button_index].text == "UNDO")
	redo_entity := world.entities[int(state.nodes[redo].entity.index)]
	testing.expect(t, world.ui_buttons[redo_entity.ui_button_index].text == "REDO")
	revert_entity := world.entities[int(state.nodes[revert].entity.index)]
	testing.expect(t, world.ui_buttons[revert_entity.ui_button_index].text == "REVERT")
	status_entity := world.entities[int(state.nodes[status].entity.index)]
	testing.expect(
		t,
		world.ui_texts[status_entity.ui_text_index].text ==
		"PLAY MODE  /  RUNNING  /  CHANGES ARE TEMPORARY",
	)
	playback_warning_index, playback_warning_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_PLAYBACK_WARNING_NAME),
	)
	playback_warning_badge_index, playback_warning_badge_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_PLAYBACK_WARNING_BADGE_NAME),
	)
	testing.expect(t, playback_warning_found && playback_warning_badge_found)
	if playback_warning_found && playback_warning_badge_found {
		testing.expect(
			t,
			!world.ui_layouts[world.entities[playback_warning_index].ui_layout_index].hidden,
		)
		testing.expect_value(
			t,
			world.ui_texts[world.entities[playback_warning_badge_index].ui_text_index].text,
			"PLAY MODE RUNNING  /  SCENE EDITS ARE NOT SAVED",
		)
	}
	top_index, top_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_TOP_NAME),
	)
	status_bar_index, status_bar_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_STATUS_NAME),
	)
	viewport_entity_index := int(state.nodes[viewport].entity.index)
	theme := reduced_dark_theme()
	testing.expect(t, top_found && status_bar_found)
	if top_found && status_bar_found {
		testing.expect(
			t,
			world.ui_layouts[world.entities[top_index].ui_layout_index].background ==
			theme.palette.region,
		)
		testing.expect(
			t,
			world.ui_layouts[world.entities[status_bar_index].ui_layout_index].background ==
			theme.palette.region,
		)
	}
	playback_viewport := world.ui_layouts[world.entities[viewport_entity_index].ui_layout_index]
	testing.expect(t, playback_viewport.border_color == theme.palette.warning_soft)
	testing.expect(t, playback_viewport.border_width == 2)

	press := proc(state: ^State, world: ^shared.World, node_index: int) {
		rect := state.nodes[node_index].rect
		point := shared.Vec2{rect.x + rect.width * 0.5, rect.y + rect.height * 0.5}
		_ = reconcile(
			state,
			world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		)
		_ = reconcile(state, world, 1280, 720, {position = point, available = true})
	}

	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, editor_play_mode_active(state))
	press(state, &world, pause)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, editor_play_mode_active(state))
	testing.expect(
		t,
		world.ui_texts[status_entity.ui_text_index].text ==
		"PLAY MODE  /  PAUSED  /  CHANGES ARE TEMPORARY",
	)
	if playback_warning_badge_found {
		testing.expect_value(
			t,
			world.ui_texts[world.entities[playback_warning_badge_index].ui_text_index].text,
			"PLAY MODE PAUSED  /  SCENE EDITS ARE NOT SAVED",
		)
	}
	delta, run := consume_simulation_delta(state, 0.2)
	testing.expect(t, !run && delta == 0)
	press(state, &world, pause)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(
		t,
		world.ui_texts[status_entity.ui_text_index].text ==
		"PLAY MODE  /  RUNNING  /  CHANGES ARE TEMPORARY",
	)
	delta, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, run && delta == 0.2)
	press(state, &world, pause)
	testing.expect(t, !state.editor_simulation_playing)

	press(state, &world, step)
	delta, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, run && delta == f32(1.0 / 60.0))
	_, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, !run)

	press(state, &world, play)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(
		t,
		world.ui_texts[status_entity.ui_text_index].text ==
		"PLAY MODE  /  RUNNING  /  CHANGES ARE TEMPORARY",
	)
	delta, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, run && delta == 0.2)

	press(state, &world, stop)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, !editor_play_mode_active(state))
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "STOPPED")
	if playback_warning_found {
		testing.expect(
			t,
			world.ui_layouts[world.entities[playback_warning_index].ui_layout_index].hidden,
		)
	}
	if top_found && status_bar_found {
		testing.expect(
			t,
			world.ui_layouts[world.entities[top_index].ui_layout_index].background ==
			theme.palette.region,
		)
		testing.expect(
			t,
			world.ui_layouts[world.entities[status_bar_index].ui_layout_index].background ==
			theme.palette.region,
		)
	}
	testing.expect(
		t,
		world.ui_layouts[world.entities[viewport_entity_index].ui_layout_index].border_color ==
		(shared.Vec4{}),
	)
	testing.expect(
		t,
		world.ui_layouts[world.entities[viewport_entity_index].ui_layout_index].border_width == 0,
	)
	testing.expect(t, consume_playback_stop_request(state))
	testing.expect(t, !consume_playback_stop_request(state))
	press(state, &world, stop)
	testing.expect(t, !consume_playback_stop_request(state))
	state.editor_scene_dirty = true
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "STOPPED  /  UNSAVED")
	press(state, &world, play)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, consume_playback_begin_request(state))
	testing.expect(t, !consume_playback_begin_request(state))
	press(state, &world, stop)
	testing.expect(t, consume_playback_stop_request(state))
	testing.expect(t, state.editor_scene_dirty)
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	press(state, &world, save)
	testing.expect(t, consume_scene_save_request(state))
	testing.expect(t, !consume_scene_save_request(state))
	complete_scene_save(state, true)
	testing.expect(t, !state.editor_scene_dirty)
	state.editor_scene_dirty = true
	state.editor_snapshot_valid = false
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {save = true}) == "",
	)
	testing.expect(t, consume_scene_save_request(state))
	complete_scene_save(state, true)
	testing.expect(t, !state.editor_scene_dirty)

	// Stopped authoring cannot accidentally transition to paused playback.
	editor_pause(state)
	testing.expect(t, state.editor_simulation_stopped)
}

@(test)
test_editor_command_shortcuts_toggle_shell_and_drive_transport :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {run_stop = true}) == "",
	)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, consume_playback_stop_request(state))
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {run_stop = true}) == "",
	)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, consume_playback_begin_request(state))

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {pause_step = true}) == "",
	)
	testing.expect(t, !state.editor_simulation_playing && !state.editor_simulation_stopped)
	_, run := consume_simulation_delta(state, 0.25)
	testing.expect(t, !run)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {pause_step = true}) == "",
	)
	delta: f32
	delta, run = consume_simulation_delta(state, 0.25)
	testing.expect(t, run && delta == f32(1.0 / 60.0))
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {run_stop = true}) == "",
	)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, !state.editor_simulation_stopped)
	testing.expect(t, !consume_playback_begin_request(state))
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {pause_step = true}) == "",
	)
	testing.expect(t, !state.editor_simulation_playing && !state.editor_simulation_stopped)

	state.has_focused_input = true
	state.focused_input_editor = false
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {run_stop = true}) == "",
	)
	testing.expect(t, !state.editor_simulation_playing && !state.editor_simulation_stopped)
	state.has_focused_input = false
	state.editor_scene_camera_captures_input = true
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {run_stop = true}) == "",
	)
	testing.expect(t, !state.editor_simulation_playing && !state.editor_simulation_stopped)
	state.editor_scene_camera_captures_input = false

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {editor_toggle = true}) == "",
	)
	testing.expect(t, !state.editor_visible)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {editor_toggle = true}) == "",
	)
	testing.expect(t, state.editor_visible)
	testing.expect(t, !state.editor_simulation_playing && !state.editor_simulation_stopped)
}

@(test)
test_editor_resource_reimport_requests_are_consumed_once :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	id, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000088")
	testing.expect(t, valid)
	editor_request_resource_reimport(state, id)
	requested_id, all, requested := consume_resource_reimport_request(state)
	testing.expect(t, requested)
	testing.expect(t, !all)
	testing.expect(t, requested_id == id)
	_, _, requested = consume_resource_reimport_request(state)
	testing.expect(t, !requested)
	complete_resource_reimport(state, "import failed")
	testing.expect(t, state.editor_resource_reimport_failed)
	testing.expect_value(t, state.editor_resource_reimport_message, "import failed")
	editor_request_resource_reimport(state, {}, true)
	requested_id, all, requested = consume_resource_reimport_request(state)
	testing.expect(t, requested)
	testing.expect(t, all)
	testing.expect(t, requested_id == (shared.Resource_UUID{}))
}

@(test)
test_editor_toggle_pauses_on_open_and_resumes_on_close :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	// Opening pauses a running game, and closing resumes it.
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {editor_toggle = true}) == "",
	)
	testing.expect(t, state.editor_visible)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, !state.editor_simulation_stopped)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {editor_toggle = true}) == "",
	)
	testing.expect(t, !state.editor_visible)
	testing.expect(t, state.editor_simulation_playing)

	// Opening preserves a pre-existing pause, while closing resumes it.
	editor_pause(state)
	editor_toggle(state)
	testing.expect(t, state.editor_visible)
	testing.expect(t, !state.editor_simulation_playing)
	editor_toggle(state)
	testing.expect(t, !state.editor_visible)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, !state.editor_simulation_stopped)

	// Opening preserves stopped authoring mode. Closing starts playback and requests its baseline.
	editor_stop(state)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, consume_playback_stop_request(state))
	editor_world_restored(state, &world, {}, false)
	editor_toggle(state)
	testing.expect(t, state.editor_visible)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, state.editor_simulation_stopped)
	editor_toggle(state)
	testing.expect(t, !state.editor_visible)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, !state.editor_simulation_stopped)
	testing.expect(t, consume_playback_begin_request(state))
}

@(test)
test_editor_sidebar_shortcuts_toggle_public_workspace_panes :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	left, left_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_LEFT_NAME),
	)
	right, right_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_RIGHT_NAME),
	)
	testing.expect(t, left_found && right_found)
	if !left_found || !right_found {
		return
	}
	left_layout := world.entities[left].ui_layout_index
	right_layout := world.entities[right].ui_layout_index
	testing.expect(t, !world.ui_layouts[left_layout].hidden)
	testing.expect(t, !world.ui_layouts[right_layout].hidden)

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {toggle_left_sidebar = true}) ==
		"",
	)
	testing.expect(t, !state.editor_left_sidebar_visible)
	testing.expect(t, world.ui_layouts[left_layout].hidden)
	testing.expect(t, !world.ui_layouts[right_layout].hidden)

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {toggle_right_sidebar = true}) ==
		"",
	)
	testing.expect(t, !state.editor_right_sidebar_visible)
	testing.expect(t, world.ui_layouts[left_layout].hidden)
	testing.expect(t, world.ui_layouts[right_layout].hidden)

	editor_toggle(state)
	testing.expect(t, !state.editor_visible)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{},
			0,
			0,
			1.0 / 60.0,
			{toggle_left_sidebar = true, toggle_right_sidebar = true},
		) ==
		"",
	)
	testing.expect(t, !state.editor_left_sidebar_visible && !state.editor_right_sidebar_visible)
}

@(test)
test_editor_scene_dirty_only_tracks_stopped_scene_entities :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	defer destroy(state)
	state.editor_simulation_stopped = true
	scene_entity := shared.World_Entity {
		uuid = shared.entity_uuid_from_engine_name("scene-dirty"),
		origin = .Scene,
	}
	runtime_entity := shared.World_Entity {
		origin = .Runtime,
	}
	editor_mark_scene_dirty(state, &runtime_entity)
	testing.expect(t, !state.editor_scene_dirty)
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 1)
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, len(state.editor_dirty_entities) == 1)
	state.editor_scene_dirty = false
	state.editor_simulation_stopped = false
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, !state.editor_scene_dirty)
}

@(test)
test_editor_sidebar_separators_resize_panes_and_preserve_the_center_fill :: proc(t: ^testing.T) {
	scene :=
		shared.Scene{}; defer delete(scene.entities); append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, current_pointer_cursor(state) == .Default)
	viewport := editor_viewport(state, 1280, 720)
	initial := viewport
	editor_handles := [2]int{-1, -1}
	handle_count := 0
	for handle, index in state.split_handles[:state.split_handle_count] { if handle.editor && handle.horizontal && handle_count < 2 { editor_handles[handle_count] = index; handle_count += 1 } }
	testing.expect(t, handle_count == 2)
	left_handle := state.split_handles[editor_handles[0]]
	point := shared.Vec2{left_handle.rect.x + left_handle.rect.width * 0.5, 200}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x += 80
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	viewport = editor_viewport(state, 1280, 720)
	testing.expect(t, math.abs(viewport.x - initial.x - 80) < 0.1)
	testing.expect(t, math.abs(viewport.width - initial.width + 80) < 0.1)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = point, available = true}) == "",
	)
	right_handle := state.split_handles[editor_handles[1]]
	point = {right_handle.rect.x + right_handle.rect.width * 0.5, 200}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x -= 60
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	final_viewport := editor_viewport(state, 1280, 720)
	testing.expect(t, math.abs(final_viewport.x - viewport.x) < 0.1)
	testing.expect(t, math.abs(final_viewport.width - viewport.width + 60) < 0.1)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {500, 500}, available = true}) == "",
	)
	testing.expect(t, current_pointer_cursor(state) == .Default)
}

@(test)
test_editor_systems_separator_resizes_profiler_and_scene_panes :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	systems := find_editor_role_node(state, .Systems_Scroll)
	browser := find_editor_role_node(state, .Browser_Scroll)
	vertical_handle := -1
	for handle, index in state.split_handles[:state.split_handle_count] {
		if handle.editor &&
		   !handle.horizontal &&
		   math.abs(
			   handle.rect.y - (state.nodes[systems].rect.y + state.nodes[systems].rect.height),
		   ) <
			   5 {
			vertical_handle = index
			break
		}
	}
	testing.expect(t, systems >= 0 && browser >= 0 && vertical_handle >= 0)
	if systems < 0 || browser < 0 || vertical_handle < 0 {
		return
	}
	handle := state.split_handles[vertical_handle]
	point := shared.Vec2 {
		handle.rect.x + handle.rect.width * 0.5,
		handle.rect.y + handle.rect.height * 0.5,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
	point.y += 60
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
}

@(test)
test_editor_sidebar_sections_share_collapsible_panel_styling :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	systems := find_editor_name_node(state, &world, EDITOR_UI_SYSTEMS_NAME)
	scene_panel := find_editor_name_node(state, &world, EDITOR_UI_SCENE_NAME)
	inspector := find_editor_name_node(state, &world, EDITOR_UI_INSPECTOR_HEADER_NAME)
	diagnostics := find_editor_role_node(state, .Diagnostics_Panel)
	sections := [4]int{diagnostics, systems, scene_panel, inspector}
	theme := reduced_dark_theme()
	expected_titles := [4]string{"PERFORMANCE", "SYSTEMS / 0", "SCENE", "INSPECTOR"}
	expected_backgrounds := [4]shared.Vec4 {
		theme.palette.region,
		theme.palette.region,
		theme.palette.region,
		theme.palette.region,
	}
	for node_index, section_index in sections {
		testing.expect(t, node_index >= 0)
		if node_index < 0 { continue }
		node := state.nodes[node_index]
		testing.expect(t, node.panel_index >= 0)
		if node.panel_index < 0 { continue }
		panel := world.ui_panels[node.panel_index]
		layout := world.ui_layouts[node.layout_index]
		testing.expect(t, panel.title == expected_titles[section_index])
		testing.expect(t, panel.collapsible)
		testing.expect(t, panel.title_height == EDITOR_SECTION_TITLE_HEIGHT)
		testing.expect(t, panel.title_color == theme.palette.text_secondary)
		testing.expect(t, panel.title_background == theme.palette.control)
		testing.expect(t, layout.background == expected_backgrounds[section_index])
		testing.expect(t, layout.border_color == theme.palette.border)
		testing.expect(t, layout.corner_radius == theme.metrics.radius_small)
	}

	if scene_panel >= 0 {
		node := state.nodes[scene_panel]
		point := shared.Vec2{node.rect.x + 18, node.rect.y + EDITOR_SECTION_TITLE_HEIGHT * 0.5}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {position = point, available = true}) == "",
		)
		testing.expect(t, world.ui_panels[node.panel_index].collapsed)
	}
}

@(test)
test_editor_nested_scroll_prefers_inner_panes_and_sidebar_padding_targets_outer :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	for _ in 0 ..< 25 {
		append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	profile: shared.System_Profile
	profile.entry_count = 10
	profile.revision = 1
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.system_profile = &profile
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 500) == "")
	left := find_editor_name_node(state, &world, EDITOR_UI_LEFT_NAME)
	right := find_editor_name_node(state, &world, EDITOR_UI_RIGHT_NAME)
	systems := find_editor_role_node(state, .Systems_Scroll)
	testing.expect(t, left >= 0 && right >= 0 && systems >= 0)
	if left < 0 || right < 0 || systems < 0 {
		return
	}
	testing.expect(t, state.nodes[left].scroll_max > 0)
	testing.expect(t, state.nodes[right].scroll_max > 0)
	left_layout := world.ui_layouts[state.nodes[left].layout_index]
	right_layout := world.ui_layouts[state.nodes[right].layout_index]
	testing.expect(
		t,
		left_layout.padding ==
		shared.Vec4 {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
	)
	testing.expect(
		t,
		right_layout.padding ==
		shared.Vec4 {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
	)

	system_rect := state.nodes[systems].rect
	system_visible_rect := rect_intersection(system_rect, state.nodes[systems].clip)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{
				position = {
					system_visible_rect.x + min(system_visible_rect.width * 0.5, 20),
					system_visible_rect.y + system_visible_rect.height * 0.5,
				},
				wheel_y = -1,
				available = true,
			},
			1280,
			500,
		) ==
		"",
	)
	testing.expectf(
		t,
		state.nodes[systems].scroll_target == EDITOR_SCROLL_SPEED,
		"systems scroll target %.2f (max %.2f), rect %+v, clip %+v",
		state.nodes[systems].scroll_target,
		state.nodes[systems].scroll_max,
		state.nodes[systems].rect,
		state.nodes[systems].clip,
	)
	testing.expect(t, state.nodes[left].scroll_target == 0)

	left_rect := state.nodes[left].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {left_rect.x + 2, left_rect.y + 20}, wheel_y = -1, available = true},
			1280,
			500,
		) ==
		"",
	)
	testing.expect(t, state.nodes[left].scroll_target == EDITOR_SCROLL_SPEED)

	right_rect := state.nodes[right].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {right_rect.x + 2, right_rect.y + 20}, wheel_y = -1, available = true},
			1280,
			500,
		) ==
		"",
	)
	testing.expect(t, state.nodes[right].scroll_target == EDITOR_SCROLL_SPEED)
}

@(test)
test_editor_scene_panel_is_a_flush_scrollable_selectable_list :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	for _ in 0 ..< 31 {
		append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 800, 500) == "")
	scene_node := find_editor_role_node(state, .Browser_Scroll)
	first_row, row_found := editor_ui_entity(&world, .Browser_Row, 0)
	testing.expect(t, scene_node >= 0 && row_found)
	if scene_node < 0 || !row_found { return }
	scene_panel := state.nodes[scene_node]
	panel_entity_index :=
		world.entity_by_uuid[shared.entity_uuid_from_engine_name(EDITOR_UI_SCENE_NAME)]
	panel_node := find_node_by_entity_index(state, panel_entity_index)
	row_node := find_node_by_entity_index(state, first_row)
	testing.expect(t, scene_panel.list_index >= 0)
	testing.expect(t, scene_panel.scroll_area_index >= 0)
	testing.expect(t, scene_panel.panel_index < 0)
	testing.expect(t, panel_node >= 0 && state.nodes[panel_node].panel_index >= 0)
	testing.expect(t, world.ui_layouts[scene_panel.layout_index].padding == shared.Vec4{})
	testing.expect(t, row_node >= 0)
	if row_node >= 0 {
		row := state.nodes[row_node]
		tools_node := find_node_by_entity_index(
			state,
			world.entity_by_uuid[shared.entity_uuid_from_engine_name(EDITOR_UI_SCENE_TOOLS_NAME)],
		)
		testing.expect(t, math.abs(row.rect.x - scene_panel.rect.x) < 0.01)
		testing.expect(t, math.abs(row.rect.width - scene_panel.rect.width) < 0.01)
		testing.expect(t, tools_node >= 0)
		if tools_node >= 0 {
			tools := state.nodes[tools_node]
			testing.expect(t, math.abs(row.rect.y - tools.rect.y - tools.rect.height) < 0.01)
		}
	}
}

@(test)
test_editor_entity_shortcuts_share_authoring_actions_and_select_duplicate :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{id = ui_test_id("Entity Shortcut Original"), name = "Original"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.editor_simulation_stopped = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 0))

	editor_ui_handle_shortcuts(state, &world, {duplicate_entity = true})
	testing.expect(t, state.editor_has_selection)
	duplicate := state.editor_selected_entity
	testing.expect(t, duplicate != world.entities[0].id)
	duplicate_index := int(duplicate.index)
	testing.expect(
		t,
		duplicate_index >= 0 &&
		duplicate_index < len(world.entities) &&
		world.entities[duplicate_index].alive &&
		world.entities[duplicate_index].name == "Original Copy",
	)

	state.has_focused_input = true
	editor_ui_handle_shortcuts(state, &world, {delete_entity = true})
	testing.expect(t, world.entities[duplicate_index].alive)
	state.has_focused_input = false
	editor_ui_handle_shortcuts(state, &world, {delete_entity = true})
	testing.expect(t, !world.entities[duplicate_index].alive)
	testing.expect(t, !state.editor_has_selection)

	stopped_history_count := state.editor_history_count
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 0))
	state.editor_simulation_playing = true
	state.editor_simulation_stopped = false
	editor_ui_handle_shortcuts(state, &world, {duplicate_entity = true})
	testing.expect(t, state.editor_has_selection)
	runtime_duplicate := state.editor_selected_entity
	runtime_duplicate_index := int(runtime_duplicate.index)
	testing.expect(
		t,
		runtime_duplicate_index >= 0 &&
		runtime_duplicate_index < len(world.entities) &&
		world.entities[runtime_duplicate_index].alive &&
		world.entities[runtime_duplicate_index].origin == .Runtime &&
		state.editor_history_count == stopped_history_count,
	)
	state.editor_simulation_playing = false
	editor_ui_handle_shortcuts(state, &world, {delete_entity = true})
	testing.expect(t, !world.entities[runtime_duplicate_index].alive)
	testing.expect(t, !state.editor_has_selection)
	testing.expect(t, state.editor_history_count == stopped_history_count)

	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 0))
	state.has_focused_input = true
	editor_ui_handle_shortcuts(state, &world, {escape = true})
	testing.expect(t, state.editor_has_selection)
	state.has_focused_input = false
	editor_ui_handle_shortcuts(state, &world, {escape = true})
	testing.expect(t, !state.editor_has_selection)

	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 0))
	popup_layout_index := len(world.ui_layouts)
	append(&world.ui_layouts, shared.UI_Layout_Component{popup = true, popup_open = true})
	state.node_count = 1
	state.nodes[0] = {
		origin = .Editor,
		layout_index = popup_layout_index,
	}
	editor_ui_handle_shortcuts(state, &world, {escape = true})
	testing.expect(t, state.editor_has_selection)
	world.ui_layouts[popup_layout_index].popup_open = false
	editor_ui_handle_shortcuts(state, &world, {escape = true})
	testing.expect(t, !state.editor_has_selection)
}

@(test)
test_editor_structural_authoring_is_uuid_addressed_and_undoable :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Structural Authoring"),
			name = "Original",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	registry: component.Registry
	component.init_registry(&registry)
	transform_definition, _ := component.find_definition(&registry, "scrapbot.transform")
	state.component_registry = &registry
	point_light_definition, point_light_found := component.find_definition(
		&registry,
		"scrapbot.point_light",
	)
	testing.expect(t, point_light_found)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true

	duplicate, duplicated := editor_authoring_duplicate_entity(state, &world, 0)
	testing.expect(t, duplicated)
	duplicate_index, duplicate_found := ecs.entity_index_by_uuid(
		&world,
		world.entities[duplicate.index].uuid,
	)
	testing.expect(t, duplicate_found && duplicate_index != 0)
	duplicate_uuid := world.entities[duplicate_index].uuid
	testing.expect(t, duplicate_uuid != world.entities[0].uuid)
	testing.expect(t, world.entities[duplicate_index].origin == .Scene)
	testing.expect(t, editor_history_apply(state, &world, false))
	_, duplicate_found = ecs.entity_index_by_uuid(&world, duplicate_uuid)
	testing.expect(t, !duplicate_found)
	testing.expect(t, !state.editor_has_selection)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 0)
	testing.expect(t, editor_history_apply(state, &world, true))
	duplicate_index, duplicate_found = ecs.entity_index_by_uuid(&world, duplicate_uuid)
	testing.expect(t, duplicate_found)
	testing.expect(t, state.editor_has_selection)
	testing.expect(t, state.editor_scene_dirty)

	testing.expect(t, editor_authoring_rename_entity(state, &world, duplicate_index, "Renamed"))
	testing.expect(t, world.entities[duplicate_index].name == "Renamed")
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, world.entities[duplicate_index].name == "Original Copy")
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.entities[duplicate_index].name == "Renamed")

	transform_index := world.entities[duplicate_index].transform_index
	testing.expect(
		t,
		editor_authoring_set_registered_component(
			state,
			&world,
			duplicate_index,
			&point_light_definition,
			true,
		),
	)
	testing.expect(t, world.entities[duplicate_index].point_light_index >= 0)
	testing.expect(t, world.entities[duplicate_index].transform_index == transform_index)
	testing.expect(
		t,
		state.editor_history[state.editor_history_cursor - 1].component_structural != nil,
	)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, world.entities[duplicate_index].point_light_index < 0)
	testing.expect(t, world.entities[duplicate_index].transform_index == transform_index)
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.entities[duplicate_index].point_light_index >= 0)
	testing.expect(t, world.entities[duplicate_index].transform_index == transform_index)
	point_light_index := world.entities[duplicate_index].point_light_index
	world.point_lights[point_light_index] = {
		color = {0.125, 0.5, 0.875},
		intensity = 7.25,
		range = 42,
	}
	point_light_before_remove := world.point_lights[point_light_index]
	testing.expect(
		t,
		editor_authoring_set_registered_component(
			state,
			&world,
			duplicate_index,
			&point_light_definition,
			false,
		),
	)
	testing.expect(t, world.entities[duplicate_index].point_light_index < 0)
	testing.expect(t, world.entities[duplicate_index].transform_index == transform_index)
	testing.expect(t, editor_history_apply(state, &world, false))
	point_light_index = world.entities[duplicate_index].point_light_index
	testing.expect(t, point_light_index >= 0)
	if point_light_index >= 0 {
		testing.expect(t, world.point_lights[point_light_index] == point_light_before_remove)
	}
	testing.expect(t, world.entities[duplicate_index].transform_index == transform_index)
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.entities[duplicate_index].point_light_index < 0)

	runtime_index, runtime_created := ecs.create_world_entity(&world, "Runtime", {}, .Runtime)
	testing.expect(t, runtime_created)
	runtime_uuid := world.entities[runtime_index].uuid
	testing.expect(t, editor_authoring_promote_entity(state, &world, runtime_index))
	testing.expect(t, world.entities[runtime_index].origin == .Scene)
	testing.expect(t, editor_history_apply(state, &world, false))
	runtime_index, runtime_created = ecs.entity_index_by_uuid(&world, runtime_uuid)
	testing.expect(t, runtime_created && world.entities[runtime_index].origin == .Runtime)
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.entities[runtime_index].origin == .Scene)

	testing.expect(t, editor_authoring_delete_entity(state, &world, duplicate_index))
	_, duplicate_found = ecs.entity_index_by_uuid(&world, duplicate_uuid)
	testing.expect(t, !duplicate_found)
	testing.expect(t, editor_history_apply(state, &world, false))
	_, duplicate_found = ecs.entity_index_by_uuid(&world, duplicate_uuid)
	testing.expect(t, duplicate_found)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 2)
}

@(test)
test_reflected_color_picker_preview_finishes_as_one_undoable_transaction :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Color History"),
			name = "Color History",
			has_ambient_light = true,
			ambient_light = {color = {1, 1, 1}, intensity = 1},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	definition, found := component.find_definition(&registry, "scrapbot.ambient_light")
	testing.expect(t, found)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		reflected_component_id = definition.id,
		reflected_field_index = 0,
	}
	before, component_count, read := editor_reflected_read_color(state, &world, binding)
	testing.expect(t, read && component_count == 3)
	after := shared.Vec4{0.2, 0.4, 0.6, 1}
	testing.expect(
		t,
		editor_reflected_preview_color(state, &world, binding, after, component_count),
	)
	testing.expect_value(t, world.ambient_lights[0].color, shared.Vec3{0.2, 0.4, 0.6})
	testing.expect(
		t,
		editor_reflected_finish_color(state, &world, binding, before, after, component_count),
	)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, editor_undo(state, &world))
	testing.expect_value(t, world.ambient_lights[0].color, shared.Vec3{1, 1, 1})
}

@(test)
test_editor_component_picker_uses_registry_hierarchy_and_structural_history :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Component Picker"),
			name = "Picker Target",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	register_err := component.register_project_component(
		&registry,
		{name = "floating", fields = {0 = {name = "offset", field_type = .Vec3}}, field_count = 1},
	)
	testing.expect(t, register_err == "")
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_selected_entity = world.entities[0].id
	state.editor_has_selection = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	button, button_found := editor_ui_entity(&world, .Inspector_Component_Menu_Button)
	menu, menu_found := editor_ui_entity(&world, .Inspector_Component_Menu)
	testing.expect(t, button_found && menu_found)
	if button_found {
		button_entity := world.entities[button]
		button_layout := world.ui_layouts[button_entity.ui_layout_index]
		button_value := world.ui_buttons[button_entity.ui_button_index]
		theme := reduced_dark_theme()
		testing.expect(t, button_layout.border_color == theme.palette.border)
		testing.expect(t, button_layout.border_width == 0)
		testing.expect(t, button_value.text == "Add Component")
		testing.expect(t, button_value.alignment == .Center)
		testing.expect(t, button_value.hover_color.w == 1)
	}
	if !menu_found {
		return
	}
	testing.expect(t, handle_popup_press(state, &world, world.entities[button].id))
	editor_ui_handle_activation(state, &world, world.entities[button].id, {})
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
	filter, filter_found := editor_ui_entity(&world, .Browser_Filter, 3)
	content, content_found := editor_ui_entity(&world, .Inspector_Component_Menu_Content)
	testing.expect(t, filter_found && content_found)
	if filter_found && content_found {
		menu_entity := world.entities[menu]
		content_entity := world.entities[content]
		testing.expect(t, menu_entity.ui_vstack_index >= 0)
		testing.expect(t, menu_entity.ui_scroll_area_index < 0)
		testing.expect(t, content_entity.ui_list_index >= 0)
		testing.expect(t, content_entity.ui_scroll_area_index >= 0)
		list := world.ui_lists[content_entity.ui_list_index]
		testing.expect_value(t, list.filter_input, world.entities[filter].uuid)
		testing.expect(t, !list.virtualized)
		testing.expect_value(
			t,
			world.ui_layouts[content_entity.ui_layout_index].parent,
			menu_entity.uuid,
		)

		testing.expect(t, ecs.set_ui_input_value(&world, filter, "camera"))
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
		laid_out_menu_items := 0
		for binding in world.editor_uis {
			if binding.role != .Inspector_Component_Menu_Item || binding.entity_index < 0 {
				continue
			}
			node_index := find_node_by_entity_index(state, binding.entity_index)
			if node_index >= 0 && state.nodes[node_index].laid_out {
				laid_out_menu_items += 1
			}
		}
		testing.expect_value(t, laid_out_menu_items, 1)
		content_node := find_node_by_entity_index(state, content)
		testing.expect(t, content_node >= 0)
		if content_node >= 0 {
			testing.expect_value(t, state.nodes[content_node].list_flow_count, 1)
		}
		testing.expect(t, ecs.set_ui_input_value(&world, filter, ""))
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	}
	project_group_found := false
	engine_group_found := false
	group_selection_checked := false
	for binding in world.editor_uis {
		if binding.role != .Inspector_Component_Menu_Group {
			continue
		}
		entity := world.entities[binding.entity_index]
		if world.ui_layouts[entity.ui_layout_index].hidden {
			continue
		}
		label := world.ui_texts[entity.ui_text_index].text
		project_group_found = project_group_found || label == "PROJECT"
		engine_group_found = engine_group_found || label == "scrapbot"
		if !group_selection_checked {
			testing.expect(t, handle_list_press(state, &world, entity.id))
			testing.expect(t, !close_selection_popup(state, &world, entity.id))
			testing.expect(t, world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
			group_selection_checked = true
		}
	}
	testing.expect(t, project_group_found && engine_group_found && group_selection_checked)
	for binding in world.editor_uis {
		if binding.role != .Inspector_Component_Menu_Item {
			continue
		}
		entity := world.entities[binding.entity_index]
		if world.ui_layouts[entity.ui_layout_index].hidden {
			continue
		}
		label := world.ui_buttons[entity.ui_button_index].text
		testing.expect(t, len(label) > 0)
		for index in 0 ..< len(label) {
			byte := label[index]
			testing.expect(t, byte >= 32 && byte <= 126)
		}
	}
	transform_index, transform_found := component.find_definition_index(
		&registry,
		"scrapbot.transform",
	)
	testing.expect(t, transform_found)
	if transform_item, found := editor_ui_entity(
		&world,
		.Inspector_Component_Menu_Item,
		transform_index,
	); found {
		testing.expect(t, world.ui_layouts[world.entities[transform_item].ui_layout_index].hidden)
	} else {
		testing.expect(t, true)
	}
	camera_index, camera_found := component.find_definition_index(&registry, "scrapbot.camera")
	if camera_found {
		if camera_item, camera_item_found := editor_ui_entity(
			&world,
			.Inspector_Component_Menu_Item,
			camera_index,
		); camera_item_found {
			camera_node_index := find_node(state, world.entities[camera_item].id)
			testing.expect(t, camera_node_index >= 0)
			if camera_node_index >= 0 {
				camera_rect := state.nodes[camera_node_index].rect
				pointer := Pointer_Input {
					position = {
						camera_rect.x + camera_rect.width * 0.5,
						camera_rect.y + camera_rect.height * 0.5,
					},
					available = true,
				}
				testing.expect(t, reconcile(state, &world, 1280, 720, pointer) == "")
				hover_paint_index := -1
				last_hover_glyph_index := -1
				for command, command_index in state.paint[:state.paint_count] {
					if command.kind == .Panel &&
					   command.color == reduced_dark_theme().palette.hover &&
					   command.rect == camera_rect {
						hover_paint_index = command_index
					}
					if command.kind == .Glyph {
						center := shared.Vec2 {
							command.rect.x + command.rect.width * 0.5,
							command.rect.y + command.rect.height * 0.5,
						}
						if rect_contains(camera_rect, center) {
							last_hover_glyph_index = command_index
						}
					}
				}
				testing.expect(t, hover_paint_index >= 0)
				testing.expect(t, last_hover_glyph_index > hover_paint_index)
			}
		}
	}
	definition_index, definition_found := component.find_definition_index(&registry, "floating")
	testing.expect(t, definition_found)
	if !definition_found {
		return
	}
	item, item_found := editor_ui_entity(&world, .Inspector_Component_Menu_Item, definition_index)
	testing.expect(t, item_found)
	if !item_found {
		return
	}
	testing.expect(t, handle_list_press(state, &world, world.entities[item].id))
	testing.expect(t, !close_selection_popup(state, &world, world.entities[item].id))
	editor_ui_handle_activation(state, &world, world.entities[item].id, {})
	testing.expect(
		t,
		ecs.entity_has_component(&world, 0, registry.definitions[definition_index].id, "floating"),
	)
	testing.expect(t, !world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	component_action := -1
	for binding in world.editor_uis {
		if binding.role == .Inspector_Panel_Action &&
		   binding.reflected_component_id == registry.definitions[definition_index].id {
			component_action = binding.entity_index
			break
		}
	}
	testing.expect(t, component_action >= 0)
	if component_action >= 0 {
		action_node_index := find_node(state, world.entities[component_action].id)
		testing.expect(t, action_node_index >= 0)
		if action_node_index >= 0 {
			action_rect := state.nodes[action_node_index].rect
			button := world.ui_buttons[world.entities[component_action].ui_button_index]
			testing.expect(t, button.panel_action && button.icon == "x")
			if action_rect.width > 0 && action_rect.height > 0 {
				action_pointer := Pointer_Input {
					position = {
						action_rect.x + action_rect.width * 0.5,
						action_rect.y + action_rect.height * 0.5,
					},
					primary_down = true,
					available = true,
				}
				testing.expect(t, reconcile(state, &world, 1280, 720, action_pointer) == "")
				action_pointer.primary_down = false
				testing.expect(t, reconcile(state, &world, 1280, 720, action_pointer) == "")
			}
		}
	}
	testing.expect(
		t,
		!ecs.entity_has_component(
			&world,
			0,
			registry.definitions[definition_index].id,
			"floating",
		),
	)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(
		t,
		ecs.entity_has_component(&world, 0, registry.definitions[definition_index].id, "floating"),
	)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(
		t,
		!ecs.entity_has_component(
			&world,
			0,
			registry.definitions[definition_index].id,
			"floating",
		),
	)
	if transform_found {
		transform_definition := &registry.definitions[transform_index]
		testing.expect(t, editor_authoring_definition_is_supported(transform_definition))
		testing.expect(
			t,
			editor_authoring_set_registered_component(
				state,
				&world,
				0,
				transform_definition,
				false,
			),
		)
		testing.expect(t, world.entities[0].transform_index < 0)
		testing.expect(t, editor_history_apply(state, &world, false))
		testing.expect(t, world.entities[0].transform_index >= 0)
	}
	internal_index, internal_found := component.find_definition_index(
		&registry,
		"scrapbot.internal.render_instance",
	)
	testing.expect(t, internal_found)
	if internal_found {
		testing.expect(
			t,
			!editor_authoring_definition_is_supported(&registry.definitions[internal_index]),
		)
	}
}

@(test)
test_component_menu_cache_tracks_registry_identity_and_revision :: proc(t: ^testing.T) {
	first_registry: component.Registry
	component.init_registry(&first_registry)
	testing.expect(t, component.register_project_component(&first_registry, {name = "zeta"}) == "")
	second_registry: component.Registry
	component.init_registry(&second_registry)
	testing.expect(
		t,
		component.register_project_component(&second_registry, {name = "alpha"}) == "",
	)
	testing.expect(t, first_registry.revision == second_registry.revision)

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &first_registry
	editor_ui_refresh_component_menu_cache(state)
	found_zeta := false
	for index in state.component_menu_definition_indices[:state.component_menu_definition_count] {
		found_zeta = found_zeta || first_registry.definitions[index].name == "zeta"
	}
	testing.expect(t, found_zeta)

	state.component_registry = &second_registry
	editor_ui_refresh_component_menu_cache(state)
	found_alpha := false
	found_stale_zeta := false
	for index in state.component_menu_definition_indices[:state.component_menu_definition_count] {
		name := second_registry.definitions[index].name
		found_alpha = found_alpha || name == "alpha"
		found_stale_zeta = found_stale_zeta || name == "zeta"
	}
	testing.expect(t, found_alpha)
	testing.expect(t, !found_stale_zeta)
}

@(test)
test_running_component_picker_changes_live_membership_without_authoring_history :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{id = ui_test_id("Running Component Picker"), name = "Running Target"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	register_err := component.register_project_component(
		&registry,
		{name = "floating", fields = {0 = {name = "offset", field_type = .Vec3}}, field_count = 1},
	)
	testing.expect(t, register_err == "")
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = true
	state.editor_simulation_stopped = false
	state.editor_selected_entity = world.entities[0].id
	state.editor_has_selection = true

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	button, button_found := editor_ui_entity(&world, .Inspector_Component_Menu_Button)
	testing.expect(t, button_found)
	if !button_found {
		return
	}
	testing.expect(t, handle_popup_press(state, &world, world.entities[button].id))
	editor_ui_handle_activation(state, &world, world.entities[button].id, {})
	menu, menu_found := editor_ui_entity(&world, .Inspector_Component_Menu)
	testing.expect(t, menu_found)
	if menu_found {
		testing.expect(t, world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
	}
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	camera_index, camera_found := component.find_definition_index(&registry, "scrapbot.camera")
	testing.expect(t, camera_found)
	if !camera_found {
		return
	}
	item, item_found := editor_ui_entity(&world, .Inspector_Component_Menu_Item, camera_index)
	testing.expect(t, item_found)
	if !item_found {
		return
	}
	editor_ui_handle_activation(state, &world, world.entities[item].id, {})
	testing.expect(t, world.entities[0].camera_index >= 0)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 0)
	testing.expect(t, state.editor_history_cursor == 0)
	failure, integrity_ok := ecs.validate_world_integrity(&world)
	testing.expectf(t, integrity_ok, "%s", ecs.format_world_integrity_failure(failure))

	state.editor_simulation_playing = false
	testing.expect(
		t,
		editor_set_registered_component(
			state,
			&world,
			0,
			&registry.definitions[camera_index],
			false,
		),
	)
	testing.expect(t, world.entities[0].camera_index < 0)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 0)

	runtime_index, runtime_created := ecs.create_world_entity(
		&world,
		"Runtime Component Target",
		{},
		.Runtime,
	)
	testing.expect(t, runtime_created)
	floating_index, floating_found := component.find_definition_index(&registry, "floating")
	testing.expect(t, floating_found)
	if runtime_created && floating_found {
		testing.expect(
			t,
			editor_set_registered_component(
				state,
				&world,
				runtime_index,
				&registry.definitions[floating_index],
				true,
			),
		)
		testing.expect(
			t,
			ecs.entity_has_component(
				&world,
				runtime_index,
				registry.definitions[floating_index].id,
				"floating",
			),
		)
	}
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 0)
}

@(test)
test_stopped_component_picker_cell_can_be_reused_by_new_entity_inspector :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{id = ui_test_id("Empty Authoring Entity"), name = "Empty"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_selected_entity = world.entities[0].id
	state.editor_has_selection = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	editor_stop(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	cell, cell_found := editor_ui_entity(&world, .Inspector_Cell, 0)
	testing.expect(t, cell_found)
	if !cell_found {
		return
	}
	testing.expect(t, world.entities[cell].ui_text_index < 0)
	_, created := editor_authoring_create_entity(state, &world)
	testing.expect(t, created)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	cell, cell_found = editor_ui_entity(&world, .Inspector_Cell, 0)
	testing.expect(t, cell_found && world.entities[cell].ui_text_index >= 0)
}

@(test)
test_resized_play_view_maps_pointer_back_to_project_canvas :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	viewport := editor_viewport(state, 2048, 1096)
	testing.expect(t, viewport == Rect{0, 0, 2048, 1096})
	pointer := project_pointer_input(
		state,
		{position = {1024, 548}, available = true},
		1280,
		720,
		2048,
		1096,
	)
	transform := project_canvas_transform(state, 2048, 1096)
	testing.expect(
		t,
		pointer.available &&
		math.abs(pointer.position.x - 1024 / transform.scale.x) < 0.001 &&
		math.abs(pointer.position.y - 548 / transform.scale.y) < 0.001,
	)
}

@(test)
test_editor_browser_scrolls_selects_runtime_entities_and_clears_stale_selection :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}; defer delete(scene.entities)
	for i in 0 ..< 25 { append(&scene.entities, shared.Scene_Entity{name = "Browser Entity"}) }
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[24].origin = .Runtime
	world.entities[24].transform_index = len(
		world.transforms,
	); append_soa(&world.transforms, shared.Transform_Component{})
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[24].id, 300))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	left_sidebar := find_editor_name_node(state, &world, EDITOR_UI_LEFT_NAME)
	testing.expect(t, left_sidebar >= 0 && state.nodes[left_sidebar].scroll_max > 0)
	browser_index := find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, browser_index >= 0)
	if left_sidebar >= 0 && browser_index >= 0 {
		browser_offset :=
			state.nodes[browser_index].rect.y -
			state.nodes[left_sidebar].rect.y +
			state.nodes[left_sidebar].scroll_offset
		state.nodes[left_sidebar].scroll_target = clamp(
			browser_offset,
			0,
			state.nodes[left_sidebar].scroll_max,
		)
	}
	for _ in 0 ..< 60 {
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	}
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, browser_index >= 0)
	browser_rect := state.nodes[browser_index].rect
	browser_visible := rect_intersection(browser_rect, state.nodes[browser_index].clip)
	browser_point := shared.Vec2 {
		browser_visible.x + min(browser_visible.width * 0.5, 20),
		browser_visible.y + min(browser_visible.height * 0.5, 20),
	}

	// A wheel step settles at a pixel offset between rows instead of snapping to one.
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = browser_point, wheel_y = -1, available = true},
			1280,
			300,
		) ==
		"",
	)
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, state.nodes[browser_index].scroll_target == 48)
	testing.expect(
		t,
		int(state.nodes[browser_index].scroll_target) % int(EDITOR_ENTITY_ROW_HEIGHT) != 0,
	)
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "") }
	testing.expect(t, math.abs(state.nodes[browser_index].scroll_offset - 48) < 0.02)

	// A short window can continue smoothly to the runtime tail.
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = browser_point, wheel_y = -20, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[browser_index].scroll_target > 48)
	testing.expect(
		t,
		state.nodes[browser_index].scroll_offset > 0 &&
		state.nodes[browser_index].scroll_offset < state.nodes[browser_index].scroll_target,
	)
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	state.nodes[browser_index].scroll_target = state.nodes[browser_index].scroll_max
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "") }
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	testing.expect(
		t,
		math.abs(
			state.nodes[browser_index].scroll_offset - state.nodes[browser_index].scroll_target,
		) <
		0.02,
	)
	runtime_row_entity := -1
	for component in world.editor_uis { if component.role == .Browser_Row && component.target == world.entities[24].id { runtime_row_entity = component.entity_index; break } }
	runtime_row_node := find_node_by_entity_index(state, runtime_row_entity)
	testing.expect(t, runtime_row_node >= 0 && state.nodes[runtime_row_node].has_clip)
	row_rect := state.nodes[runtime_row_node].rect
	row_visible := rect_intersection(row_rect, state.nodes[runtime_row_node].clip)
	row_point := shared.Vec2 {
		row_visible.x + min(row_visible.width * 0.5, 20),
		row_visible.y + row_visible.height * 0.5,
	}
	testing.expectf(
		t,
		node_pointer_contains(state.nodes[runtime_row_node], row_point),
		"runtime row laid_out=%v rect=%v clip=%v visible=%v has_clip=%v point=%v browser=%v",
		state.nodes[runtime_row_node].laid_out,
		state.nodes[runtime_row_node].rect,
		state.nodes[runtime_row_node].clip,
		row_visible,
		state.nodes[runtime_row_node].has_clip,
		row_point,
		state.nodes[browser_index].rect,
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = row_point, primary_down = true, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.editor_has_selection)
	testing.expect(t, state.editor_selected_entity == world.entities[24].id)
	testing.expect(t, world.entities[24].origin == .Runtime)
	testing.expect(t, entity_component_count(&world, 24) == 1)
	browser_entity := world.entities[int(state.nodes[browser_index].entity.index)]
	testing.expect(
		t,
		world.ui_lists[browser_entity.ui_list_index].selected ==
		world.entities[runtime_row_entity].uuid,
	)

	world.entities[24].alive = false
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	testing.expect(t, !state.editor_has_selection)
}

@(test)
test_editor_browser_uses_name_color_instead_of_provenance_labels :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{name = "Authored"},
		shared.Scene_Entity{name = "Runtime"},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[1].origin = .Runtime
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[1].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	theme := reduced_dark_theme()
	scene_color := theme.palette.text
	runtime_color := theme.palette.text_muted
	scene_label, runtime_label := -1, -1
	for component in world.editor_uis {
		if component.role != .Browser_Row_Label { continue }
		if component.target == world.entities[0].id { scene_label = component.entity_index }
		if component.target == world.entities[1].id { runtime_label = component.entity_index }
	}
	testing.expect(t, scene_label >= 0 && runtime_label >= 0)
	if scene_label >=
	   0 { label := world.ui_texts[world.entities[scene_label].ui_text_index]; testing.expect(t, label.color == scene_color); testing.expect(t, label.size == EDITOR_TEXT_SIZE); testing.expect(t, world.ui_layouts[world.entities[scene_label].ui_layout_index].size.y == EDITOR_ENTITY_ROW_HEIGHT) }
	if runtime_label >=
	   0 { testing.expect(t, world.ui_texts[world.entities[runtime_label].ui_text_index].color == runtime_color) }
}

@(test)
test_editor_selection_promotes_derived_model_entity_to_authored_root :: proc(t: ^testing.T) {
	root_id := ui_test_id("Model Selection Root")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{id = root_id, name = "Authored Model"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	derived_index, created := ecs.create_world_entity(
		&world,
		"Authored Model / Node / primitive:0",
		{},
		.Runtime,
	)
	testing.expect(t, created)
	if !created {
		return
	}
	world.entities[derived_index].model_owner = root_id
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true

	testing.expect(t, editor_select_entity(state, &world, world.entities[derived_index].id, 720))
	testing.expect_value(t, state.editor_selected_entity, world.entities[0].id)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect_value(t, editor_browser_row_count(&world), 1)
	root_row, row_found := editor_ui_entity(&world, .Browser_Row, 0)
	browser, browser_found := editor_ui_entity(&world, .Browser_Scroll, 0)
	testing.expect(t, row_found && browser_found)
	if row_found && browser_found {
		list := world.ui_lists[world.entities[browser].ui_list_index]
		testing.expect_value(t, list.selected, world.entities[root_row].uuid)
	}
}

@(test)
test_editor_browser_builds_collapsible_transform_tree_and_reparents_with_history :: proc(
	t: ^testing.T,
) {
	parent_id := ui_test_id("Hierarchy Parent")
	child_id := ui_test_id("Hierarchy Child")
	sibling_id := ui_test_id("Hierarchy Sibling")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_transform = true,
			transform = {position = {2, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_transform = true,
			transform = {parent = parent_id, position = {1, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = sibling_id,
			name = "Sibling",
			has_transform = true,
			transform = {position = {8, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_simulation_playing = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect_value(t, editor_browser_row_count(&world), 3)
	first_row, _ := editor_ui_entity(&world, .Browser_Row, 0)
	second_row, _ := editor_ui_entity(&world, .Browser_Row, 1)
	third_row, _ := editor_ui_entity(&world, .Browser_Row, 2)
	first := world.editor_uis[world.entities[first_row].editor_ui_index]
	second := world.editor_uis[world.entities[second_row].editor_ui_index]
	third := world.editor_uis[world.entities[third_row].editor_ui_index]
	testing.expect(t, first.target == world.entities[0].id)
	testing.expect(t, second.target == world.entities[1].id)
	testing.expect(t, third.target == world.entities[2].id)
	browser, browser_found := editor_ui_entity(&world, .Browser_Scroll, 0)
	testing.expect(t, browser_found)
	if browser_found {
		event_cursor := ecs.ui_event_latest_sequence(&world)
		state.events[0] = {
			kind = .Dropped,
			entity = world.entities[browser].id,
			source = world.entities[first_row].id,
			target = world.entities[third_row].id,
			drop_placement = .After,
		}
		state.event_count = 1
		publish_ui_events(state, &world)
		testing.expect(t, editor_ui_consume_events(state, &world, event_cursor))
		testing.expect_value(t, editor_entity_parent_uuid(&world, 0), shared.Entity_UUID{})
		testing.expect_value(t, editor_entity_parent_uuid(&world, 1), parent_id)
		indices, depths: [MAX_NODES]int
		has_children: [MAX_NODES]bool
		visible_count := editor_hierarchy_visible_entities(
			state,
			&world,
			&indices,
			&depths,
			&has_children,
		)
		testing.expect_value(t, visible_count, 3)
		testing.expect_value(t, indices[0], 2)
		testing.expect_value(t, indices[1], 0)
		testing.expect_value(t, indices[2], 1)
		testing.expect(t, editor_undo(state, &world))
		ecs.begin_world_transform_resolution(&world)
		child_world_before, _ := ecs.resolve_world_transform(&world, 1)
		state.events[0] = {
			kind = .Dropped,
			entity = world.entities[browser].id,
			source = world.entities[second_row].id,
			target = world.entities[third_row].id,
			drop_placement = .Before,
		}
		state.event_count = 1
		event_cursor = ecs.ui_event_latest_sequence(&world)
		publish_ui_events(state, &world)
		testing.expect(t, editor_ui_consume_events(state, &world, event_cursor))
		testing.expect_value(t, state.editor_history_count, 1)
		testing.expect_value(t, state.editor_history_cursor, 1)
		testing.expect_value(t, editor_entity_parent_uuid(&world, 1), shared.Entity_UUID{})
		ecs.begin_world_transform_resolution(&world)
		child_world_after, _ := ecs.resolve_world_transform(&world, 1)
		testing.expect_value(t, child_world_after.position, child_world_before.position)
		visible_count = editor_hierarchy_visible_entities(
			state,
			&world,
			&indices,
			&depths,
			&has_children,
		)
		testing.expect_value(t, visible_count, 3)
		testing.expect_value(t, indices[0], 0)
		testing.expect_value(t, indices[1], 1)
		testing.expect_value(t, indices[2], 2)
		testing.expect_value(t, depths[1], 0)
		testing.expect(t, editor_undo(state, &world))
		testing.expect_value(t, editor_entity_parent_uuid(&world, 1), parent_id)
		testing.expect(t, editor_redo(state, &world))
		testing.expect_value(t, editor_entity_parent_uuid(&world, 1), shared.Entity_UUID{})
		testing.expect(t, editor_undo(state, &world))
	}

	disclosure, found := editor_ui_entity(&world, .Browser_Row_Disclosure, 0)
	testing.expect(t, found)
	if found {
		editor_ui_handle_activation(state, &world, world.entities[disclosure].id, {})
		testing.expect(t, state.editor_collapsed_entities[parent_id])
		indices, depths: [MAX_NODES]int
		has_children: [MAX_NODES]bool
		testing.expect_value(
			t,
			editor_hierarchy_visible_entities(state, &world, &indices, &depths, &has_children),
			3,
		)
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
		testing.expect_value(t, editor_browser_row_count(&world), 3)
		collapsed_child_row, child_row_found := editor_ui_entity(&world, .Browser_Row, 1)
		testing.expect(t, child_row_found)
		if child_row_found {
			collapsed_child_node := find_node_by_entity_index(state, collapsed_child_row)
			testing.expect(t, collapsed_child_node >= 0)
			if collapsed_child_node >= 0 {
				testing.expect(t, !state.nodes[collapsed_child_node].laid_out)
			}
		}
		editor_ui_handle_activation(state, &world, world.entities[disclosure].id, {})
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	}

	ecs.begin_world_transform_resolution(&world)
	before, _ := ecs.resolve_world_transform(&world, 2)
	testing.expect(t, editor_reparent_entity(state, &world, 2, parent_id))
	testing.expect_value(t, state.editor_history_count, 1)
	ecs.begin_world_transform_resolution(&world)
	after, _ := ecs.resolve_world_transform(&world, 2)
	testing.expect_value(t, after.position, before.position)
	testing.expect_value(t, world.transforms[world.entities[2].transform_index].parent, parent_id)
	testing.expect(t, editor_undo(state, &world))
	testing.expect_value(
		t,
		world.transforms[world.entities[2].transform_index].parent,
		shared.Entity_UUID{},
	)
	testing.expect(t, editor_redo(state, &world))
	testing.expect_value(t, world.transforms[world.entities[2].transform_index].parent, parent_id)
	testing.expect(t, editor_reorder_entity(state, &world, 2, 1, false))
	testing.expect_value(t, state.editor_history_count, 2)
	testing.expect_value(t, world.transforms[world.entities[2].transform_index].parent, parent_id)
	indices, depths: [MAX_NODES]int
	has_children: [MAX_NODES]bool
	visible_count := editor_hierarchy_visible_entities(
		state,
		&world,
		&indices,
		&depths,
		&has_children,
	)
	testing.expect_value(t, visible_count, 3)
	testing.expect_value(t, indices[0], 0)
	testing.expect_value(t, indices[1], 2)
	testing.expect_value(t, indices[2], 1)
	testing.expect(t, !editor_reorder_entity(state, &world, 0, 1, false))
	testing.expect(t, editor_undo(state, &world))
	visible_count = editor_hierarchy_visible_entities(
		state,
		&world,
		&indices,
		&depths,
		&has_children,
	)
	testing.expect_value(t, visible_count, 3)
	testing.expect_value(t, indices[0], 0)
	testing.expect_value(t, indices[1], 1)
	testing.expect_value(t, indices[2], 2)
	testing.expect(t, editor_redo(state, &world))
	visible_count = editor_hierarchy_visible_entities(
		state,
		&world,
		&indices,
		&depths,
		&has_children,
	)
	testing.expect_value(t, indices[1], 2)
	testing.expect_value(t, indices[2], 1)
}

@(test)
test_editor_reparents_transformless_entities_and_uses_transformless_parents :: proc(
	t: ^testing.T,
) {
	parent_id := ui_test_id("Transformless Parent")
	child_id := ui_test_id("Transformless Child")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{id = parent_id, name = "Ambient Light"},
		shared.Scene_Entity{id = child_id, name = "Marker"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_stopped = true
	state.editor_simulation_playing = false
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	parent_row := -1
	child_row := -1
	for binding in world.editor_uis {
		if binding.role != .Browser_Row {
			continue
		}
		if binding.target == world.entities[0].id {
			parent_row = binding.entity_index
		}
		if binding.target == world.entities[1].id {
			child_row = binding.entity_index
		}
	}
	parent_node := find_node_by_entity_index(state, parent_row)
	child_node := find_node_by_entity_index(state, child_row)
	testing.expect(t, parent_node >= 0 && child_node >= 0)
	for _ in 0 ..< 4 {
		if !diagnostic_reveal_target(state, &world, child_node) {
			break
		}
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
		parent_node = find_node_by_entity_index(state, parent_row)
		child_node = find_node_by_entity_index(state, child_row)
	}
	start := shared.Vec2 {
		state.nodes[child_node].rect.x + 40,
		state.nodes[child_node].rect.y + state.nodes[child_node].rect.height * 0.5,
	}
	target := shared.Vec2 {
		state.nodes[parent_node].rect.x + 40,
		state.nodes[parent_node].rect.y + state.nodes[parent_node].rect.height * 0.5,
	}
	testing.expectf(
		t,
		node_pointer_contains(state.nodes[child_node], start),
		"child row is not interactable: rect=%v clip=%v point=%v",
		state.nodes[child_node].rect,
		state.nodes[child_node].clip,
		start,
	)
	testing.expectf(
		t,
		node_pointer_contains(state.nodes[parent_node], target),
		"parent row is not interactable: rect=%v clip=%v point=%v",
		state.nodes[parent_node].rect,
		state.nodes[parent_node].clip,
		target,
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = start, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expectf(t, state.list_drags[1].armed, "scene tree drag did not arm from child row")
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = target, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = target, available = true}) == "",
	)
	testing.expect(t, world.entities[0].transform_index < 0)
	testing.expect(t, world.entities[1].transform_index >= 0)
	transform := world.transforms[world.entities[1].transform_index]
	testing.expect_value(t, transform.parent, parent_id)
	testing.expect_value(t, transform.scale, shared.Vec3{1, 1, 1})
	ecs.begin_world_transform_resolution(&world)
	resolved, valid := ecs.resolve_world_transform(&world, 1)
	testing.expect(t, valid)
	testing.expect_value(t, resolved.scale, shared.Vec3{1, 1, 1})
	testing.expect(t, editor_undo(state, &world))
	testing.expect(t, world.entities[1].transform_index < 0)
	testing.expect(t, editor_redo(state, &world))
	testing.expect(t, world.entities[1].transform_index >= 0)
}

@(test)
test_editor_browser_hides_runtime_churn_until_a_runtime_entity_is_selected :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{name = "One"},
		shared.Scene_Entity{name = "Two"},
		shared.Scene_Entity{name = "Three"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 3)

	ecs.despawn_entity(&world, 1, world.entities[1].id.generation)
	ecs.despawn_entity(&world, 2, world.entities[2].id.generation)
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 1)
	for component in world.editor_uis {
		if component.role != .Browser_Row || component.slot == 0 { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive)
		testing.expect(t, world.ui_layouts[entity.ui_layout_index].hidden)
	}

	names := [3]string{"Runtime A", "Runtime B", "Runtime C"}
	for name in names {
		spawn: ecs.Spawn_Command
		testing.expect(t, ecs.init_spawn_command(&spawn, name) == "")
		_ = ecs.spawn_entity(&world, &spawn)
	}
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 1)
	runtime_entity := world.entities[1].id
	testing.expect(t, editor_select_entity(state, &world, runtime_entity, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 2)
	for component, component_index in world.editor_uis {
		if component.role != .Browser_Row && component.role != .Browser_Row_Label { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive && entity.origin == .Editor)
		testing.expect(t, entity.editor_ui_index == component_index)
	}
}

@(test)
test_editor_browser_ui_storage_does_not_scale_with_hidden_runtime_entities :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Authored"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	for _ in 0 ..< 1024 {
		_, created := ecs.create_world_entity(&world, "Runtime", {}, .Runtime)
		testing.expect(t, created)
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect_value(t, editor_browser_row_count(&world), 1)
	browser_bindings := 0
	for component in world.editor_uis {
		if component.role == .Browser_Row ||
		   component.role == .Browser_Row_Disclosure ||
		   component.role == .Browser_Row_Label {
			browser_bindings += 1
		}
	}
	testing.expect_value(t, browser_bindings, 3)
}

@(test)
test_editor_scene_camera_and_editor_ui_are_hidden_from_the_entity_browser :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	entity_index, _, ok := ecs.reconcile_editor_scene_camera(&world, true)
	testing.expect(t, ok)
	testing.expect(t, world.entities[entity_index].origin == .Editor)
	testing.expect(t, entity_component_count(&world, entity_index) == 3)

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, !editor_select_entity(state, &world, world.entities[entity_index].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	for component in world.editor_uis { if component.role == .Browser_Row || component.role == .Browser_Row_Label { testing.expect(t, component.target != world.entities[entity_index].id) } }
	testing.expect(t, editor_browser_row_count(&world) == 0)
}

@(test)
test_advanced_inspector_components_start_collapsed_and_remember_expansion :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Advanced Camera",
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 500, exposure = 1.25},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	camera_index, camera_found := component.find_definition_index(&registry, "scrapbot.camera")
	testing.expect(t, camera_found)
	if !camera_found {
		return
	}
	registry.definitions[camera_index].advanced = true

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 300))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")

	panel_entity := -1
	for binding in world.editor_uis {
		if binding.role != .Inspector_Panel ||
		   binding.reflected_component_id != registry.definitions[camera_index].id {
			continue
		}
		entity := world.entities[binding.entity_index]
		if entity.alive &&
		   !world.ui_layouts[entity.ui_layout_index].hidden &&
		   world.ui_panels[entity.ui_panel_index].title == "CAMERA" {
			panel_entity = binding.entity_index
			break
		}
	}
	testing.expect(t, panel_entity >= 0)
	if panel_entity < 0 {
		return
	}
	panel_index := world.entities[panel_entity].ui_panel_index
	testing.expect(t, world.ui_panels[panel_index].collapsed)
	world.ui_panels[panel_index].collapsed = false
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	testing.expect(t, !world.ui_panels[panel_index].collapsed)
}

@(test)
test_component_inspector_formats_live_fields_and_scrolls_independently :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	theme := reduced_dark_theme()
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Inspectable",
			has_transform = true,
			transform = {position = {1, 2.5, -3}, rotation = {0.1, 0.2, 0.3}, scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 500},
			has_shadow_caster = true,
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				position = {20, 30},
				size = {300, 120},
				padding = {4, 5, 6, 7},
				corner_radius = 8,
			},
			has_ui_button = true,
			ui_button = {
				text = "Launch",
				size = 14,
				color = {1, 1, 1, 1},
				hover_background = {0.2, 0.3, 0.4, 1},
			},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	transform_definition, _ := component.find_definition(&registry, "scrapbot.transform")
	camera_definition, _ := component.find_definition(&registry, "scrapbot.camera")
	shadow_definition, _ := component.find_definition(&registry, "scrapbot.shadow_caster")
	button_definition, _ := component.find_definition(&registry, "scrapbot.ui_button")
	layout_definition, _ := component.find_definition(&registry, "scrapbot.ui_layout")
	camera_exposure_field := -1
	for field, index in camera_definition.fields[:camera_definition.field_count] {
		if field.name == "exposure" {
			camera_exposure_field = index
			break
		}
	}
	layout_hidden_field := -1
	for field, index in layout_definition.fields[:layout_definition.field_count] {
		if field.name == "hidden" {
			layout_hidden_field = index
			break
		}
	}
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	state.component_registry = &registry
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 300))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	testing.expect(t, state.editor_has_selection)
	content_entity, content_found := editor_ui_entity(&world, .Inspector_Content)
	inspector_node := find_editor_role_node(state, .Inspector_Scroll)
	testing.expect(t, content_found && inspector_node >= 0)
	if inspector_node >= 0 {
		state.nodes[inspector_node].scroll_target = min(
			EDITOR_DOCK_TAB_HEIGHT,
			state.nodes[inspector_node].scroll_max,
		)
		state.nodes[inspector_node].scroll_offset = state.nodes[inspector_node].scroll_target
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	}
	if content_found {
		testing.expect(t, world.entities[content_entity].ui_text_index < 0)
		testing.expect(t, world.entities[content_entity].name == EDITOR_UI_RIGHT_CONTENT_NAME)
		testing.expect(t, world.entities[content_entity].ui_vstack_index >= 0)
	}
	header_node := find_editor_name_node(state, &world, EDITOR_UI_INSPECTOR_HEADER_NAME)
	first_panel_node := find_editor_role_node(state, .Inspector_Panel)
	testing.expect(t, header_node >= 0 && first_panel_node >= 0)
	if content_found && header_node >= 0 && first_panel_node >= 0 {
		header := state.nodes[header_node]
		panel := state.nodes[first_panel_node]
		testing.expect(t, header.parent_entity_index == content_entity)
		testing.expect(t, panel.parent_entity_index == content_entity)
		testing.expect(t, math.abs(header.rect.x - panel.rect.x) < 0.01)
		testing.expect(t, math.abs(header.rect.width - panel.rect.width) < 0.01)
	}
	first_table_node := find_editor_role_node(state, .Inspector_Table)
	first_cell_node := find_editor_role_node(state, .Inspector_Cell)
	testing.expect(t, first_panel_node >= 0 && first_table_node >= 0 && first_cell_node >= 0)
	if first_panel_node >= 0 && first_table_node >= 0 && first_cell_node >= 0 {
		panel := state.nodes[first_panel_node]
		table := state.nodes[first_table_node]
		cell := state.nodes[first_cell_node]
		testing.expect(t, math.abs(table.rect.x - panel.rect.x) < 0.01)
		testing.expect(t, math.abs(table.rect.width - panel.rect.width) < 0.01)
		testing.expect(
			t,
			math.abs(table.rect.y - panel.rect.y - INSPECTOR_PANEL_TITLE_HEIGHT) < 0.01,
		)
		testing.expect(
			t,
			math.abs(table.rect.y + table.rect.height - panel.rect.y - panel.rect.height) < 0.01,
		)
		testing.expect(t, math.abs(cell.rect.x - table.rect.x) < 0.01)
	}
	panel_count, table_count, cell_count, input_count, checkbox_count := 0, 0, 0, 0, 0
	found_transform, found_button, found_shadow := false, false, false
	found_position := false
	position_label_cell := -1
	found_bound_checkbox := false
	position_inputs := [3]int{-1, -1, -1}
	fov_input := -1
	exposure_input := -1
	button_input := -1
	camera_input_count := 0
	shadow_field_control_count := 0
	for component in world.editor_uis {
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive { continue }
		#partial switch component.role {
			case .Inspector_Panel:
				panel_count += 1
				panel := world.ui_panels[entity.ui_panel_index]
				layout := world.ui_layouts[entity.ui_layout_index]
				testing.expect(t, panel.title_height == INSPECTOR_PANEL_TITLE_HEIGHT)
				testing.expect(t, panel.title_size == theme.metrics.small_text_size)
				testing.expect(t, layout.padding == INSPECTOR_PANEL_PADDING)
				found_transform = found_transform || panel.title == "TRANSFORM"
				found_button = found_button || panel.title == "UI BUTTON"
				found_shadow = found_shadow || panel.title == "SHADOW CASTER"
			case .Inspector_Table:
				table_count += 1
				table := world.ui_tables[entity.ui_table_index]
				if table.columns == 1 {
					testing.expect(t, !table.resizable_columns)
				} else {
					testing.expect(t, table.columns == 2)
					testing.expect(t, table.column_gap == 0)
					testing.expect(t, table.proportional_columns)
					testing.expect(t, table.resizable_columns)
					testing.expect(t, table.min_column_width == 72)
				}
			case .Inspector_Cell:
				cell_count += 1
				layout := world.ui_layouts[entity.ui_layout_index]
				component_menu_cell := layout.size.y == 46
				testing.expect(t, component_menu_cell || layout.size.y == INSPECTOR_CELL_HEIGHT)
				if entity.ui_hstack_index >= 0 && !component_menu_cell {
					testing.expect(t, world.ui_hstacks[entity.ui_hstack_index].gap == 6)
					testing.expect(t, layout.padding == INSPECTOR_VALUE_CELL_PADDING)
				}
				if entity.ui_text_index >= 0 {
					testing.expect(t, layout.padding == INSPECTOR_LABEL_CELL_PADDING)
					testing.expect(
						t,
						world.ui_texts[entity.ui_text_index].size == EDITOR_TEXT_SIZE,
					)
					found_position =
						found_position || world.ui_texts[entity.ui_text_index].text == "position"
					if position_label_cell < 0 &&
					   world.ui_texts[entity.ui_text_index].text == "position" {
						position_label_cell = component.entity_index
					}
				}
			case .Inspector_Input:
				input_count += 1
				testing.expect(
					t,
					world.ui_layouts[entity.ui_layout_index].size.y == INSPECTOR_CONTROL_HEIGHT,
				)
				testing.expect(
					t,
					world.ui_layouts[entity.ui_layout_index].corner_radius ==
					theme.metrics.radius_small,
				)
				testing.expect(t, world.ui_inputs[entity.ui_input_index].size == EDITOR_TEXT_SIZE)
				if entity.ui_input_index >= 0 &&
				   entity.ui_input_index < len(world.ui_inputs) &&
				   component.reflected_component_id == button_definition.id &&
				   component.reflected_field_index == 0 &&
				   world.ui_inputs[entity.ui_input_index].text == "Launch" {
					button_input = component.entity_index
				}
				if component.reflected_component_id == camera_definition.id &&
				   component.reflected_field_index == 0 {
					fov_input = component.entity_index
				}
				if component.reflected_component_id == camera_definition.id {
					camera_input_count += 1
				}
				if component.reflected_component_id == shadow_definition.id {
					shadow_field_control_count += 1
				}
				if component.reflected_component_id == camera_definition.id &&
				   component.reflected_field_index == camera_exposure_field {
					exposure_input = component.entity_index
				}
				if component.reflected_component_id == transform_definition.id &&
				   component.reflected_field_index == 0 {
					axis_index := int(component.inspector_axis) - 1
					if axis_index >= 0 && axis_index < len(position_inputs) {
						position_inputs[axis_index] = component.entity_index
					}
				}
			case .Inspector_Checkbox:
				checkbox_count += 1
				testing.expect(t, entity.ui_checkbox_index >= 0)
				testing.expect(
					t,
					world.ui_layouts[entity.ui_layout_index].size.y == INSPECTOR_CONTROL_HEIGHT,
				)
				checkbox := world.ui_checkboxes[entity.ui_checkbox_index]
				if component.reflected_component_id == layout_definition.id &&
				   component.reflected_field_index == layout_hidden_field {
					found_bound_checkbox =
						found_bound_checkbox || !checkbox.read_only && !checkbox.checked
				}
				if component.reflected_component_id == shadow_definition.id {
					shadow_field_control_count += 1
				}
		}
	}
	testing.expect(t, panel_count >= 6)
	testing.expect(t, table_count == panel_count)
	testing.expect(t, cell_count > 20)
	testing.expect(t, input_count > cell_count / 2)
	testing.expect(t, checkbox_count >= 2)
	testing.expect(t, found_bound_checkbox)
	testing.expect(t, camera_definition.field_count == 24)
	testing.expect(t, camera_exposure_field >= 0)
	testing.expect(t, camera_input_count == 15)
	testing.expect(t, found_transform && found_button && found_shadow)
	testing.expect(t, shadow_field_control_count == 0)
	testing.expect(t, found_position)
	for input in position_inputs { testing.expect(t, input >= 0) }
	testing.expect(t, fov_input >= 0)
	testing.expect(t, exposure_input >= 0)
	testing.expect(t, button_input >= 0)
	if position_inputs[0] >= 0 && position_inputs[1] >= 0 && position_inputs[2] >= 0 {
		x_node := find_node_by_entity_index(state, position_inputs[0])
		y_node := find_node_by_entity_index(state, position_inputs[1])
		z_node := find_node_by_entity_index(state, position_inputs[2])
		testing.expect(t, x_node >= 0 && y_node >= 0 && z_node >= 0)
		if x_node >= 0 && y_node >= 0 && z_node >= 0 {
			x_cell_node := find_node_by_entity_index(
				state,
				state.nodes[x_node].parent_entity_index,
			)
			testing.expect(t, x_cell_node >= 0)
			testing.expect(t, state.nodes[x_node].rect.height == INSPECTOR_CONTROL_HEIGHT)
			if x_cell_node >= 0 {
				cell := state.nodes[x_cell_node]
				input := state.nodes[x_node]
				testing.expect(t, input.rect.y - cell.rect.y == INSPECTOR_VALUE_CELL_PADDING.x)
				testing.expect(
					t,
					cell.rect.y + cell.rect.height - input.rect.y - input.rect.height ==
					INSPECTOR_VALUE_CELL_PADDING.z,
				)
			}
			label_node := find_node_by_entity_index(state, position_label_cell)
			testing.expect(t, label_node >= 0)
			if label_node >= 0 {
				input_layout :=
					world.ui_layouts[world.entities[position_inputs[0]].ui_layout_index]
				input_content_height :=
					state.nodes[x_node].rect.height -
					input_layout.padding.x -
					input_layout.padding.z
				label_baseline :=
					state.nodes[label_node].rect.y +
					INSPECTOR_LABEL_CELL_PADDING.x +
					state.font.ascender * EDITOR_TEXT_SIZE
				input_baseline :=
					state.nodes[x_node].rect.y +
					input_layout.padding.x +
					max((input_content_height - EDITOR_TEXT_SIZE) * 0.5, 0) +
					state.font.ascender * EDITOR_TEXT_SIZE
				testing.expectf(
					t,
					math.abs(label_baseline - input_baseline) < 0.01,
					"label baseline %.2f differs from input baseline %.2f",
					label_baseline,
					input_baseline,
				)
			}
			testing.expect(t, state.nodes[x_node].rect.y == state.nodes[y_node].rect.y)
			testing.expect(t, state.nodes[y_node].rect.y == state.nodes[z_node].rect.y)
			testing.expect(t, state.nodes[x_node].rect.x < state.nodes[y_node].rect.x)
			testing.expect(t, state.nodes[y_node].rect.x < state.nodes[z_node].rect.x)
			x_input := world.ui_inputs[world.entities[position_inputs[0]].ui_input_index]
			testing.expect(t, x_input.prefix == "X")
			testing.expect(t, x_input.prefix_color == theme.palette.axis_x)
		}
	}
	testing.expect(t, format_vec3({1, 2.5, -3}) == "(1.00, 2.50, -3.00)")
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	position_input := position_inputs[0]
	testing.expect(t, position_input >= 0)
	if position_input >= 0 {
		focus_input(state, &world, position_input)
		refresh_count := state.editor_snapshot_refresh_count
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, state.editor_snapshot_refresh_count == refresh_count)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "9"}) == "",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{1, 2.5, -3})
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {escape = true}) == "",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{1, 2.5, -3})
		testing.expect(t, !state.editor_scene_dirty)
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "4", tab = true},
			) ==
			"",
		)
		testing.expect(t, state.focused_input == world.entities[position_inputs[1]].id)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "5", tab = true},
			) ==
			"",
		)
		testing.expect(t, state.focused_input == world.entities[position_inputs[2]].id)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "6", enter = true},
			) ==
			"",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{1, 2.5, 6})
		testing.expect(t, !state.has_focused_input)
		testing.expect(t, state.editor_history_count == 1)

		// Axis prefixes reserve text width while horizontal reveal keeps the caret inside.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "123456789"}) ==
			"",
		)
		testing.expect(t, state.input_scroll_x > 0)
		x_node := find_node_by_entity_index(state, position_inputs[0])
		caret_inside := false
		if x_node >= 0 {
			for command in state.paint[:state.paint_count] {
				if command.kind == .Panel && command.rect.width == 1 {
					caret_inside =
						command.rect.x >= state.nodes[x_node].rect.x &&
						command.rect.x <
							state.nodes[x_node].rect.x + state.nodes[x_node].rect.width
				}
			}
		}
		testing.expect(t, caret_inside)
		text_clipped_behind_axis := true
		if x_node >= 0 {
			layout := world.ui_layouts[world.entities[position_inputs[0]].ui_layout_index]
			text_viewport_left :=
				state.nodes[x_node].rect.x +
				layout.padding.w +
				UI_INPUT_PREFIX_WIDTH +
				UI_INPUT_PREFIX_GAP
			input_color := world.ui_inputs[world.entities[position_inputs[0]].ui_input_index].color
			for command in state.paint[:state.paint_count] {
				if command.kind == .Glyph &&
				   command.color == input_color &&
				   rect_contains(state.nodes[x_node].rect, {command.rect.x, command.rect.y}) &&
				   (!command.has_clip || command.clip.x < text_viewport_left) {
					text_clipped_behind_axis = false
					break
				}
			}
		}
		testing.expect(t, text_clipped_behind_axis)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {escape = true}) == "",
		)

		// Invalid text remains local, receives invalid styling, and cannot commit.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "nope"}) == "",
		)
		testing.expect(t, !state.input_valid)
		testing.expect(t, world.transforms[0].position == shared.Vec3{1, 2.5, 6})
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {enter = true}) == "",
		)
		testing.expect(t, state.has_focused_input)
		invalid_border_found := false
		x_node = find_node_by_entity_index(state, position_inputs[0])
		if x_node >= 0 {
			for command in state.paint[:state.paint_count] {
				if command.kind == .Panel &&
				   command.rect == state.nodes[x_node].rect &&
				   command.border_color.x > 0.9 &&
				   command.border_color.y < 0.3 {
					invalid_border_found = true
					break
				}
			}
		}
		testing.expect(t, invalid_border_found)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {escape = true}) == "",
		)

		// Stepping respects coarse/fine modifiers and records one completed command.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{up = true, shift = true},
			) ==
			"",
		)
		testing.expect(t, world.transforms[0].position.x == 1)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{down = true, fine = true, enter = true},
			) ==
			"",
		)
		stepped := world.transforms[0].position.x
		testing.expect(t, math.abs(stepped - 1.099) < 0.001)

		// Dragging the X axis label scrubs, commits on release, and participates in undo/redo.
		inspector_node = find_editor_role_node(state, .Inspector_Scroll)
		x_node = find_node_by_entity_index(state, position_inputs[0])
		for _ in 0 ..< 8 {
			if x_node < 0 || inspector_node < 0 {
				break
			}
			input := state.nodes[x_node]
			if rect_intersection(input.rect, input.clip).height > 0 {
				break
			}
			wheel_y := f32(-1)
			if input.rect.y < input.clip.y {
				wheel_y = 1
			}
			inspector := state.nodes[inspector_node]
			point := shared.Vec2 {
				inspector.rect.x + inspector.rect.width * 0.5,
				inspector.rect.y + inspector.rect.height * 0.5,
			}
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = point, wheel_y = wheel_y, available = true},
					1280,
					300,
					1.0 / 60.0,
				) ==
				"",
			)
			for _ in 0 ..< 12 {
				testing.expect(
					t,
					reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0) == "",
				)
			}
			x_node = find_node_by_entity_index(state, position_inputs[0])
		}
		if x_node >= 0 {
			state.editor_snapshot_elapsed = 0
			state.editor_snapshot_valid = true
			scrub_refresh_count := state.editor_snapshot_refresh_count
			visible := rect_intersection(state.nodes[x_node].rect, state.nodes[x_node].clip)
			start := shared.Vec2{state.nodes[x_node].rect.x + 7, visible.y + visible.height * 0.5}
			testing.expectf(
				t,
				visible.height > 0,
				"scrub input rect=%v clip=%v visible=%v inspector=%v scroll=%.2f/%.2f",
				state.nodes[x_node].rect,
				state.nodes[x_node].clip,
				visible,
				state.nodes[inspector_node].rect,
				state.nodes[inspector_node].scroll_offset,
				state.nodes[inspector_node].scroll_max,
			)
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = start, primary_down = true, available = true},
					1280,
					300,
				) ==
				"",
			)
			drag := start
			for step in 1 ..= 18 {
				drag.x = start.x + f32(4 + step * 2)
				testing.expect(
					t,
					reconcile(
						state,
						&world,
						1280,
						720,
						{position = drag, primary_down = true, available = true},
						1280,
						300,
					) ==
					"",
				)
			}
			testing.expect(t, state.input_scrubbing)
			testing.expect(t, state.editor_snapshot_refresh_count == scrub_refresh_count)
			scrubbed := world.transforms[0].position.x
			testing.expect(t, scrubbed > stepped)
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = drag, available = true},
					1280,
					300,
				) ==
				"",
			)
			testing.expect(t, state.editor_history_count > 0)
			if state.editor_history_count > 0 {
				command := state.editor_history[state.editor_history_count - 1]
				testing.expect(t, command.component_structural != nil)
				if command.component_structural != nil {
					before := command.component_structural.before.value.transform.position.x
					after := command.component_structural.after.value.transform.position.x
					testing.expect(t, math.abs(before - stepped) < 0.001)
					testing.expect(t, math.abs(after - scrubbed) < 0.001)
				}
			}
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {undo = true}) == "",
			)
			testing.expect(t, math.abs(world.transforms[0].position.x - stepped) < 0.001)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {redo = true}) == "",
			)
			testing.expect(t, math.abs(world.transforms[0].position.x - scrubbed) < 0.001)
		}

		// Field constraints reject out-of-range but syntactically valid values.
		if fov_input >= 0 {
			focus_input(state, &world, fov_input)
			fov_binding := world.editor_uis[world.entities[fov_input].editor_ui_index]
			testing.expect(t, fov_binding.reflected_component_id == camera_definition.id)
			testing.expect(t, fov_binding.reflected_field_index == 0)
			testing.expect(t, !editor_reflected_input_valid(state, &world, fov_binding, "200"))
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {text = "200"}) == "",
			)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {enter = true}) == "",
			)
			testing.expect(t, !state.input_valid)
			testing.expect(t, world.cameras[0].fov == 60)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {escape = true}) == "",
			)
		}

		// Editor history shortcuts do not leak into the project while chrome is closed.
		before_hidden_undo := world.transforms[0].position.x
		state.editor_visible = false
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {undo = true}) == "",
		)
		testing.expect(t, world.transforms[0].position.x == before_hidden_undo)
		state.editor_visible = true

		// History refuses to cross a component remove/re-add boundary on the same entity.
		ecs.remove_transform(&world, 0)
		ecs.add_transform(&world, 0, {position = {77, 8, 9}, scale = {1, 1, 1}})
		testing.expect(t, !editor_history_apply(state, &world, false))
		testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 77)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	inspector_node = find_editor_role_node(state, .Inspector_Scroll)
	testing.expect(t, inspector_node >= 0)
	inspector_rect := state.nodes[inspector_node].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{
				position = {inspector_rect.x + 20, inspector_rect.y + 20},
				wheel_y = -4,
				available = true,
			},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[inspector_node].scroll_offset > 0)
	testing.expect(
		t,
		state.nodes[inspector_node].scroll_offset < state.nodes[inspector_node].scroll_target,
	)
	browser_node := find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, browser_node >= 0 && state.nodes[browser_node].scroll_offset == 0)

	// Inspector focus cannot outlive the target component or entity represented by a pooled input.
	if position_input >= 0 {
		button_input = -1
		for component in world.editor_uis {
			if component.role == .Inspector_Input &&
			   component.reflected_component_id == button_definition.id &&
			   component.reflected_field_index == 0 {
				button_input = component.entity_index
				break
			}
		}
		if button_input >= 0 {
			focus_input(state, &world, button_input)
			testing.expect(
				t,
				ecs.set_registered_component_membership(&world, 0, &button_definition, false),
			)
			testing.expect(
				t,
				!editor_entity_has_registered_component(&world, 0, &button_definition),
			)
			testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0.21) == "")
			testing.expect(t, !state.has_focused_input)
			testing.expect(
				t,
				ecs.set_registered_component_membership(&world, 0, &button_definition, true),
			)
		}

		focus_input(state, &world, position_input)
		transform_index := world.entities[0].transform_index
		world.entities[0].transform_index = -1
		ecs.bump_component_revision(&world, 0)
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, !state.has_focused_input)
		world.entities[0].transform_index = transform_index
		ecs.bump_component_revision(&world, 0)

		focus_input(state, &world, position_input)
		world.entities[0].alive = false
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, !state.has_focused_input)
		testing.expect(t, !state.editor_has_selection)
	}
}

@(test)
test_editor_history_bounds_branches_and_skips_stale_commands :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_transform = true,
			transform = {position = {0, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			name = "Second",
			has_transform = true,
			transform = {position = {10, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	first := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .Transform_Position,
		inspector_axis = .X,
	}
	second := first
	second.target = world.entities[1].id

	for index in 0 ..< EDITOR_HISTORY_CAPACITY + 2 {
		editor_history_push(state, &world, first, f32(index), f32(index + 1))
	}
	testing.expect(t, state.editor_history_count == EDITOR_HISTORY_CAPACITY)
	testing.expect(t, state.editor_history_cursor == EDITOR_HISTORY_CAPACITY)
	testing.expect(t, state.editor_history[0].changes[0].before_number == 2)
	testing.expect(
		t,
		state.editor_history[EDITOR_HISTORY_CAPACITY - 1].changes[0].after_number == 130,
	)

	state.editor_history_count = 0
	state.editor_history_cursor = 0
	world.transforms[world.entities[0].transform_index].position.x = 1
	editor_history_push(state, &world, first, 0, 1)
	world.transforms[world.entities[0].transform_index].position.x = 2
	editor_history_push(state, &world, first, 1, 2)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 1)
	world.transforms[world.entities[0].transform_index].position.x = 3
	editor_history_push(state, &world, first, 1, 3)
	testing.expect(t, state.editor_history_count == 2)
	testing.expect(t, state.editor_history_cursor == 2)
	testing.expect(t, state.editor_history[1].changes[0].after_number == 3)
	testing.expect(t, !editor_history_apply(state, &world, true))
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 3)

	state.editor_history_count = 0
	state.editor_history_cursor = 0
	world.transforms[world.entities[1].transform_index].position.x = 11
	editor_history_push(state, &world, second, 10, 11)
	world.transforms[world.entities[0].transform_index].position.x = 4
	editor_history_push(state, &world, first, 3, 4)
	ecs.remove_transform(&world, 0)
	ecs.add_transform(&world, 0, {position = {77, 0, 0}, scale = {1, 1, 1}})
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_history_cursor == 0)
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 77)
	testing.expect(t, world.transforms[world.entities[1].transform_index].position.x == 10)
}

@(test)
test_editor_history_transactions_undo_and_redo_boolean_changes :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Undo Checkbox"),
			name = "Undo Checkbox",
			has_ui_layout = true,
			ui_layout = {size = {80, 32}},
			has_ui_checkbox = true,
			ui_checkbox = shared.ui_checkbox_default(),
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .UI_Checkbox_Checked,
	}
	testing.expect(t, write_inspector_bool(state, &world, binding, true))
	editor_history_push_bool(state, &world, binding, false, true)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_history[0].changes[0].kind == .Boolean)
	complete_scene_save(state, true)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, !state.editor_scene_dirty && len(state.editor_dirty_entities) == 0)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, !world.ui_checkboxes[world.entities[0].ui_checkbox_index].checked)
	testing.expect(t, state.editor_scene_dirty && len(state.editor_dirty_entities) == 1)
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.ui_checkboxes[world.entities[0].ui_checkbox_index].checked)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 0)
	editor_stop(state)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, !state.editor_scene_dirty && len(state.editor_dirty_entities) == 0)
	testing.expect(t, !consume_playback_stop_request(state))
}

@(test)
test_editor_history_is_stopped_only_and_tracks_the_saved_cursor :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Saved Cursor"),
			name = "Saved Cursor",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .Transform_Position,
		inspector_axis = .X,
	}
	testing.expect(t, write_inspector_numeric(state, &world, binding, 2))
	editor_history_push(state, &world, binding, 0, 2)
	testing.expect(t, state.editor_scene_dirty)
	complete_scene_save(state, true)
	testing.expect(t, !state.editor_scene_dirty)

	state.editor_simulation_stopped = false
	state.editor_simulation_playing = true
	testing.expect(t, !editor_undo(state, &world))
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 2)

	state.editor_simulation_stopped = true
	state.editor_simulation_playing = false
	testing.expect(t, editor_undo(state, &world))
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, editor_redo(state, &world))
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 0)
}

@(test)
test_editor_boolean_transaction_restores_dependent_stack_fields :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Dependent Booleans"),
			name = "Dependent Booleans",
			has_ui_layout = true,
			ui_layout = {size = {80, 32}},
			has_ui_hstack = true,
			ui_hstack = {fill = true, draggable = true},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .UI_HStack_Fill,
	}
	transaction, ok := editor_history_begin_bool_transaction(&world, binding)
	testing.expect(t, ok)
	testing.expect(t, write_inspector_bool(state, &world, binding, false))
	editor_history_finish_bool_transaction(state, &world, transaction)
	stack_index := world.entities[0].ui_hstack_index
	testing.expect(t, !world.ui_hstacks[stack_index].fill)
	testing.expect(t, !world.ui_hstacks[stack_index].draggable)
	testing.expect(t, state.editor_history[0].change_count == 2)
	testing.expect(t, editor_undo(state, &world))
	testing.expect(t, world.ui_hstacks[stack_index].fill)
	testing.expect(t, world.ui_hstacks[stack_index].draggable)
	testing.expect(t, editor_redo(state, &world))
	testing.expect(t, !world.ui_hstacks[stack_index].fill)
	testing.expect(t, !world.ui_hstacks[stack_index].draggable)
}

@(test)
test_reflected_inspector_edits_every_registry_field_shape_with_structural_undo :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	text := shared.ui_text_default()
	text.text = "Hello"
	table := shared.ui_table_default()
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Reflected Inspector"),
			name = "Reflected Inspector",
			has_ui_layout = true,
			ui_layout = {size = {320, 180}, background = {0.1, 0.2, 0.3, 1}},
			has_ui_table = true,
			ui_table = table,
			has_ui_text = true,
			ui_text = text,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_selected_entity = world.entities[0].id
	state.editor_has_selection = true

	definition_pointer := proc(
		registry: ^component.Registry,
		name: string,
	) -> ^component.Definition {
		for index in 0 ..< registry.definition_count {
			if registry.definitions[index].name == name {
				return &registry.definitions[index]
			}
		}
		return nil
	}
	field_index := proc(definition: ^component.Definition, name: string) -> int {
		if definition == nil {
			return -1
		}
		for index in 0 ..< definition.field_count {
			if definition.fields[index].name == name {
				return index
			}
		}
		return -1
	}
	binding := proc(
		world: ^shared.World,
		definition: ^component.Definition,
		field: int,
		axis: shared.Editor_Inspector_Axis = .None,
	) -> shared.Editor_UI_Component {
		return {
			target = world.entities[0].id,
			inspector_axis = axis,
			reflected_component_id = definition.id,
			reflected_field_index = field,
		}
	}

	layout := definition_pointer(&registry, "scrapbot.ui_layout")
	table_definition := definition_pointer(&registry, "scrapbot.ui_table")
	text_definition := definition_pointer(&registry, "scrapbot.ui_text")
	testing.expect(t, layout != nil && table_definition != nil && text_definition != nil)
	if layout == nil || table_definition == nil || text_definition == nil {
		return
	}
	testing.expect(
		t,
		editor_reflected_apply_text(
			state,
			&world,
			binding(&world, text_definition, field_index(text_definition, "text")),
			"Goodbye",
		),
	)
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].text == "Goodbye")
	testing.expect(
		t,
		editor_reflected_apply_text(
			state,
			&world,
			binding(&world, text_definition, field_index(text_definition, "alignment")),
			"right",
		),
	)
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].alignment == .Right)
	testing.expect(
		t,
		editor_reflected_apply_text(
			state,
			&world,
			binding(&world, layout, field_index(layout, "position"), .X),
			"42.5",
		),
	)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].position.x == 42.5)
	testing.expect(
		t,
		editor_reflected_apply_text(
			state,
			&world,
			binding(&world, layout, field_index(layout, "background"), .W),
			"0.5",
		),
	)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].background.w == 0.5)
	testing.expect(
		t,
		editor_reflected_apply_text(
			state,
			&world,
			binding(&world, table_definition, field_index(table_definition, "columns")),
			"3",
		),
	)
	testing.expect(t, world.ui_tables[world.entities[0].ui_table_index].columns == 3)
	testing.expect(
		t,
		editor_reflected_apply_bool(
			state,
			&world,
			binding(&world, layout, field_index(layout, "hidden")),
			true,
		),
	)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].hidden)
	testing.expect(t, state.editor_history_count == 6)
	testing.expect(t, state.editor_scene_dirty)

	invalid_binding := binding(&world, table_definition, field_index(table_definition, "columns"))
	testing.expect(t, !editor_reflected_input_valid(state, &world, invalid_binding, "0"))
	testing.expect(t, !editor_reflected_apply_text(state, &world, invalid_binding, "0"))
	testing.expect(t, world.ui_tables[world.entities[0].ui_table_index].columns == 3)
	testing.expect(t, state.editor_history_count == 6)

	for _ in 0 ..< 6 {
		testing.expect(t, editor_undo(state, &world))
	}
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].text == "Hello")
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].alignment == .Left)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].position.x == 0)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].background.w == 1)
	testing.expect(t, world.ui_tables[world.entities[0].ui_table_index].columns == 1)
	testing.expect(t, !world.ui_layouts[world.entities[0].ui_layout_index].hidden)
	testing.expect(t, !state.editor_scene_dirty)

	color_w := binding(&world, layout, field_index(layout, "background"), .W)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	structure_revision := world.ui_structure_revision
	layout_index := world.entities[0].ui_layout_index
	testing.expect(t, editor_reflected_preview_number(state, &world, color_w, 0.75))
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].background.w == 0.75)
	testing.expect(t, world.entities[0].ui_layout_index == layout_index)
	testing.expect(t, world.ui_structure_revision == structure_revision)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, editor_reflected_finish_number_scrub(state, &world, color_w, 1, 0.75, false))
	testing.expect(t, state.editor_history_count == 1 && state.editor_history_cursor == 1)
	testing.expect(t, editor_undo(state, &world))
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].background.w == 1)
	testing.expect(t, !state.editor_scene_dirty)

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	found_text_input := false
	found_vec4_w := false
	for editor_binding in world.editor_uis {
		if editor_binding.role != .Inspector_Input ||
		   editor_binding.reflected_component_id == shared.INVALID_COMPONENT_ID {
			continue
		}
		if editor_binding.reflected_component_id == text_definition.id &&
		   editor_binding.reflected_field_index == field_index(text_definition, "text") {
			input_entity := world.entities[editor_binding.entity_index]
			found_text_input =
				input_entity.ui_input_index >= 0 &&
				!world.ui_inputs[input_entity.ui_input_index].read_only
		}
		if editor_binding.reflected_component_id == layout.id &&
		   editor_binding.reflected_field_index == field_index(layout, "background") &&
		   editor_binding.inspector_axis == .W {
			found_vec4_w = true
		}
	}
	testing.expect(t, found_text_input)
	testing.expect(t, found_vec4_w)
}

@(test)
test_public_popup_anchors_clamps_scrolls_and_closes_generically :: proc(t: ^testing.T) {
	anchor_id := ui_test_id("Popup Anchor")
	popup_id := ui_test_id("Popup Root")
	content_id := ui_test_id("Popup Content")
	outside_id := ui_test_id("Popup Outside")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = anchor_id,
			name = "Popup Anchor",
			has_ui_layout = true,
			ui_layout = {position = {40, 180}, size = {180, 30}},
			has_ui_button = true,
			ui_button = {text = "Choose", size = 13, popup = popup_id},
		},
		shared.Scene_Entity {
			id = popup_id,
			name = "Popup Root",
			has_ui_layout = true,
			ui_layout = {
				size = {400, 630},
				padding = {5, 5, 5, 5},
				popup = true,
				popup_close_on_selection = true,
				popup_gap = 4,
				popup_min_width = 360,
				popup_max_height = 100,
				popup_viewport_margin = 4,
			},
			has_ui_vstack = true,
			ui_vstack = {fill = true},
		},
		shared.Scene_Entity {
			id = content_id,
			name = "Popup Content",
			has_ui_layout = true,
			ui_layout = {parent = popup_id, size = {170, 1}, fill_width = true},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
			has_ui_list = true,
			ui_list = shared.ui_list_default(),
		},
		shared.Scene_Entity {
			id = outside_id,
			name = "Popup Outside",
			has_ui_layout = true,
			ui_layout = {position = {240, 10}, size = {40, 30}},
			has_ui_button = true,
			ui_button = {text = "Outside", size = 13},
		},
	)
	for index in 0 ..< 20 {
		append(
			&scene.entities,
			shared.Scene_Entity {
				id = ui_test_id(fmt.tprintf("Popup Item %d", index)),
				name = fmt.tprintf("Popup Item %d", index),
				has_ui_layout = true,
				ui_layout = {parent = content_id, size = {170, 30}},
				has_ui_button = true,
				ui_button = {text = fmt.tprintf("Item %d", index), size = 13},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	testing.expect(t, reconcile(state, &world, 300, 220) == "")
	popup_node := find_node(state, world.entities[1].id)
	testing.expect(t, popup_node >= 0)
	if popup_node < 0 {
		return
	}
	testing.expect(t, !state.nodes[popup_node].laid_out)
	testing.expect(t, handle_popup_press(state, &world, world.entities[0].id))
	testing.expect(t, reconcile(state, &world, 300, 220) == "")
	popup_node = find_node(state, world.entities[1].id)
	content_node := find_node(state, world.entities[2].id)
	testing.expect(t, popup_node >= 0 && content_node >= 0)
	if popup_node < 0 || content_node < 0 {
		return
	}
	testing.expect(t, state.nodes[popup_node].laid_out)
	testing.expect_value(t, state.nodes[popup_node].rect.height, f32(100))
	testing.expect_value(t, state.nodes[popup_node].rect.width, f32(292))
	testing.expect(t, state.nodes[popup_node].rect.y < state.nodes[0].rect.y)
	testing.expect(t, state.nodes[content_node].scroll_max > 0)

	selected_index := 4 + 15
	testing.expect(t, handle_list_press(state, &world, world.entities[selected_index].id))
	testing.expect(t, close_selection_popup(state, &world, world.entities[selected_index].id))
	testing.expect_value(
		t,
		world.ui_lists[world.entities[2].ui_list_index].selected,
		world.entities[selected_index].uuid,
	)
	testing.expect(t, !world.ui_layouts[world.entities[1].ui_layout_index].popup_open)

	anchor_button := world.ui_buttons[world.entities[0].ui_button_index]
	anchor_button.popup = {}
	testing.expect(t, ecs.set_ui_button(&world, 0, anchor_button))
	testing.expect(t, !handle_popup_press(state, &world, world.entities[0].id))
	testing.expect(t, !world.ui_layouts[world.entities[1].ui_layout_index].popup_open)
	anchor_button = world.ui_buttons[world.entities[0].ui_button_index]
	anchor_button.popup = popup_id
	testing.expect(t, ecs.set_ui_button(&world, 0, anchor_button))

	testing.expect(t, handle_popup_press(state, &world, world.entities[0].id))
	testing.expect(t, !close_popups_on_escape(state, &world, true, false))
	testing.expect(t, world.ui_layouts[world.entities[1].ui_layout_index].popup_open)
	testing.expect(t, close_popups_on_escape(state, &world, false, true))
	testing.expect(t, handle_popup_press(state, &world, world.entities[0].id))
	anchor_layout := world.ui_layouts[world.entities[0].ui_layout_index]
	anchor_layout.hidden = true
	testing.expect(t, ecs.set_ui_layout(&world, 0, anchor_layout))
	testing.expect(t, reconcile(state, &world, 300, 220) == "")
	testing.expect(t, !world.ui_layouts[world.entities[1].ui_layout_index].popup_open)
	anchor_layout.hidden = false
	testing.expect(t, ecs.set_ui_layout(&world, 0, anchor_layout))
	testing.expect(t, reconcile(state, &world, 300, 220) == "")
	testing.expect(t, handle_popup_press(state, &world, world.entities[0].id))
	testing.expect(t, close_popups_on_escape(state, &world))
	testing.expect(t, handle_popup_press(state, &world, world.entities[0].id))
	testing.expect(t, handle_popup_press(state, &world, world.entities[3].id))
	testing.expect(t, !world.ui_layouts[world.entities[1].ui_layout_index].popup_open)
}

@(test)
test_reflected_enum_inspector_uses_public_choice_popup_and_structural_history :: proc(
	t: ^testing.T,
) {
	icon := shared.UI_Icon_Position.Leading
	changed, parsed := editor_reflected_set_enum_value(
		any{rawptr(&icon), typeid_of(shared.UI_Icon_Position)},
		"Trailing",
	)
	testing.expect(t, changed && parsed && icon == .Trailing)
	_, parsed = editor_reflected_set_enum_value(
		any{rawptr(&icon), typeid_of(shared.UI_Icon_Position)},
		"missing",
	)
	testing.expect(t, !parsed && icon == .Trailing)
	small := UI_Test_U8_Enum.Low
	changed, parsed = editor_reflected_set_enum_value(
		any{rawptr(&small), typeid_of(UI_Test_U8_Enum)},
		"High",
	)
	testing.expect(t, changed && parsed && small == .High)
	signed := UI_Test_I16_Enum.Positive
	changed, parsed = editor_reflected_set_enum_value(
		any{rawptr(&signed), typeid_of(UI_Test_I16_Enum)},
		"Negative",
	)
	testing.expect(t, changed && parsed && signed == .Negative)
	unknown := transmute(UI_Test_U8_Enum)u8(42)
	unknown_name, unknown_named := editor_reflected_enum_display_name(
		any{rawptr(&unknown), typeid_of(UI_Test_U8_Enum)},
	)
	testing.expect(t, !unknown_named && unknown_name == "<unknown: 42>")

	scene := shared.Scene{}
	defer delete(scene.entities)
	text := shared.ui_text_default()
	text.text = "Enum"
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Enum Inspector"),
			name = "Enum Inspector",
			has_ui_layout = true,
			ui_layout = {size = {240, 48}},
			has_ui_text = true,
			ui_text = text,
		},
		shared.Scene_Entity {
			id = ui_test_id("Second Enum Inspector"),
			name = "Second Enum Inspector",
			has_ui_layout = true,
			ui_layout = {size = {240, 48}},
			has_ui_text = true,
			ui_text = text,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	text_definition, definition_found := component.find_definition(&registry, "scrapbot.ui_text")
	testing.expect(t, definition_found)
	if !definition_found {
		return
	}
	alignment_field := -1
	for field, index in text_definition.fields[:text_definition.field_count] {
		if field.name == "alignment" {
			alignment_field = index
			break
		}
	}
	testing.expect(t, alignment_field >= 0)
	if alignment_field < 0 {
		return
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_selected_entity = world.entities[0].id
	state.editor_has_selection = true

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	enum_button := -1
	for binding in world.editor_uis {
		if binding.role == .Inspector_Enum_Menu_Button &&
		   binding.reflected_component_id == text_definition.id &&
		   binding.reflected_field_index == alignment_field {
			enum_button = binding.entity_index
			break
		}
	}
	testing.expect(t, enum_button >= 0)
	if enum_button < 0 {
		return
	}
	button_entity := world.entities[enum_button]
	testing.expect(t, button_entity.ui_button_index >= 0)
	testing.expect(t, world.ui_buttons[button_entity.ui_button_index].text == "Left")
	testing.expect(t, handle_popup_press(state, &world, button_entity.id))
	editor_ui_handle_activation(state, &world, button_entity.id, {})
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	menu, menu_found := editor_ui_entity(&world, .Inspector_Enum_Menu)
	content, content_found := editor_ui_entity(&world, .Inspector_Enum_Menu_Content)
	testing.expect(t, menu_found && content_found)
	if menu_found && content_found {
		testing.expect(t, world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
		content_entity := world.entities[content]
		testing.expect(t, content_entity.ui_list_index >= 0)
		testing.expect(t, content_entity.ui_scroll_area_index >= 0)
		list := world.ui_lists[content_entity.ui_list_index]
		left_item, left_found := editor_ui_entity(&world, .Inspector_Enum_Menu_Item, 0)
		testing.expect(t, left_found)
		if left_found {
			testing.expect_value(t, list.selected, world.entities[left_item].uuid)
		}
	}
	right_item, right_found := editor_ui_entity(&world, .Inspector_Enum_Menu_Item, 2)
	testing.expect(t, right_found)
	if !right_found {
		return
	}
	testing.expect(t, handle_list_press(state, &world, world.entities[right_item].id))
	testing.expect(t, close_selection_popup(state, &world, world.entities[right_item].id))
	editor_ui_handle_activation(state, &world, world.entities[right_item].id, {})
	if menu_found {
		testing.expect(t, !world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
	}
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].alignment == .Right)
	testing.expect_value(t, state.editor_history_count, 1)
	testing.expect(t, editor_undo(state, &world))
	testing.expect(t, world.ui_texts[world.entities[0].ui_text_index].alignment == .Left)

	testing.expect(t, handle_popup_press(state, &world, button_entity.id))
	editor_ui_handle_activation(state, &world, button_entity.id, {})
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	state.editor_selected_entity = world.entities[1].id
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, !world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
}

@(test)
test_reflected_entity_reference_inspector_uses_searchable_public_popup_and_history :: proc(
	t: ^testing.T,
) {
	parent_id := ui_test_id("Entity Reference Parent")
	child_id := ui_test_id("Entity Reference Child")
	descendant_id := ui_test_id("Entity Reference Descendant")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Reference Parent",
			has_transform = true,
			transform = {position = {3, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Reference Child",
			has_transform = true,
			transform = {position = {1, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = descendant_id,
			name = "Reference Descendant",
			has_transform = true,
			transform = {parent = child_id, position = {2, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	transform_definition, definition_found := component.find_definition(
		&registry,
		"scrapbot.transform",
	)
	testing.expect(t, definition_found)
	if !definition_found {
		return
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_selected_entity = world.entities[1].id
	state.editor_has_selection = true

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	entity_button := -1
	for binding in world.editor_uis {
		if binding.role == .Inspector_Entity_Menu_Button &&
		   binding.reflected_component_id == transform_definition.id {
			entity_button = binding.entity_index
			break
		}
	}
	testing.expect(t, entity_button >= 0)
	if entity_button < 0 {
		return
	}
	for binding in world.editor_uis {
		testing.expect(t, binding.role != .Inspector_Entity_Menu_Item)
	}
	button_entity := world.entities[entity_button]
	testing.expect_value(t, world.ui_buttons[button_entity.ui_button_index].text, "None")
	testing.expect(t, handle_popup_press(state, &world, button_entity.id))
	editor_ui_handle_activation(state, &world, button_entity.id, {})
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	menu, menu_found := editor_ui_entity(&world, .Inspector_Entity_Menu)
	filter, filter_found := editor_ui_entity(&world, .Inspector_Entity_Menu_Filter)
	content, content_found := editor_ui_entity(&world, .Inspector_Entity_Menu_Content)
	testing.expect(t, menu_found && filter_found && content_found)
	if !menu_found || !filter_found || !content_found {
		return
	}
	testing.expect(t, world.ui_layouts[world.entities[menu].ui_layout_index].popup_open)
	testing.expect(t, world.entities[filter].ui_input_index >= 0)
	testing.expect(t, world.entities[content].ui_list_index >= 0)
	testing.expect(t, world.entities[content].ui_scroll_area_index >= 0)
	list := world.ui_lists[world.entities[content].ui_list_index]
	testing.expect_value(t, list.filter_input, world.entities[filter].uuid)
	testing.expect(t, list.virtualized)
	parent_item := -1
	child_listed := false
	descendant_listed := false
	for binding in world.editor_uis {
		if binding.role != .Inspector_Entity_Menu_Item {
			continue
		}
		if binding.entity_reference == parent_id {
			parent_item = binding.entity_index
		}
		if binding.entity_reference == child_id {
			child_listed = true
		}
		if binding.entity_reference == descendant_id {
			descendant_listed = true
		}
	}
	testing.expect(t, parent_item >= 0)
	testing.expect(t, !child_listed)
	testing.expect(t, !descendant_listed)
	if parent_item < 0 {
		return
	}
	testing.expect(t, handle_list_press(state, &world, world.entities[parent_item].id))
	testing.expect(t, close_selection_popup(state, &world, world.entities[parent_item].id))
	editor_ui_handle_activation(state, &world, world.entities[parent_item].id, {})
	testing.expect_value(t, world.transforms[world.entities[1].transform_index].parent, parent_id)
	testing.expect_value(t, state.editor_history_count, 1)
	testing.expect(t, editor_undo(state, &world))
	testing.expect_value(
		t,
		world.transforms[world.entities[1].transform_index].parent,
		shared.Entity_UUID{},
	)
	testing.expect(t, editor_redo(state, &world))
	testing.expect_value(t, world.transforms[world.entities[1].transform_index].parent, parent_id)
}

Reflected_Collection_Test_Value :: struct {
	weights: [3]f32,
}

@(test)
test_reflected_container_path_traverses_and_mutates_fixed_array_leaves :: proc(t: ^testing.T) {
	value := Reflected_Collection_Test_Value {
		weights = {1, 2, 3},
	}
	root := any{rawptr(&value), typeid_of(Reflected_Collection_Test_Value)}
	weights, weights_found := editor_reflected_container_child(root, 0)
	testing.expect(t, weights_found)
	count, count_found := editor_reflected_container_count(weights)
	testing.expect(t, count_found)
	testing.expect_value(t, count, 3)
	path: [8]int
	path[1] = 1
	leaf, leaf_found := editor_reflected_nested_value(root, path, 2)
	testing.expect(t, leaf_found)
	if !leaf_found {
		return
	}
	changed, parsed := editor_reflected_set_number(leaf, .None, 7.5)
	testing.expect(t, changed && parsed)
	testing.expect_value(t, value.weights[1], f32(7.5))
}

@(test)
test_reflected_resource_uuid_remains_a_leaf_value :: proc(t: ^testing.T) {
	value := shared.Resource_UUID{}
	field_type, found := editor_reflected_value_field_type(
		any{rawptr(&value), typeid_of(shared.Resource_UUID)},
	)
	testing.expect(t, found)
	testing.expect_value(t, field_type, component.Field_Type.String)
}

@(test)
test_reflected_nested_inspector_composes_public_disclosures_and_leaf_inputs :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Nested Inspector"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	append(
		&world.render_instances,
		shared.Render_Instance_Component {
			geometry = {index = 7, generation = 3},
			material = {index = 11, generation = 5},
		},
	)
	world.entities[0].render_instance_index = 0
	registry: component.Registry
	component.init_registry(&registry)
	definition, definition_found := component.find_definition(
		&registry,
		"scrapbot.internal.render_instance",
	)
	testing.expect(t, definition_found)
	if !definition_found {
		return
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_stopped = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	panel_entity := -1
	for binding in world.editor_uis {
		if binding.role == .Inspector_Panel && binding.reflected_component_id == definition.id {
			panel_entity = binding.entity_index
			break
		}
	}
	testing.expect(t, panel_entity >= 0)
	if panel_entity < 0 {
		return
	}
	panel_index := world.entities[panel_entity].ui_panel_index
	world.ui_panels[panel_index].collapsed = false
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	disclosure := -1
	for binding in world.editor_uis {
		testing.expect(
			t,
			binding.role != .Inspector_Input || binding.reflected_component_id != definition.id,
		)
		if binding.role == .Inspector_Container_Disclosure &&
		   binding.reflected_component_id == definition.id &&
		   binding.reflected_field_index == 0 &&
		   binding.reflected_path_count == 0 {
			disclosure = binding.entity_index
			break
		}
	}
	testing.expect(t, disclosure >= 0)
	if disclosure < 0 {
		return
	}
	editor_ui_handle_activation(state, &world, world.entities[disclosure].id, {})
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	found_index := false
	found_generation := false
	for binding in world.editor_uis {
		if binding.role != .Inspector_Input ||
		   binding.reflected_component_id != definition.id ||
		   binding.reflected_field_index != 0 ||
		   binding.reflected_path_count != 1 {
			continue
		}
		entity := world.entities[binding.entity_index]
		input := world.ui_inputs[entity.ui_input_index]
		testing.expect(t, input.read_only)
		if binding.reflected_path[0] == 0 && input.text == "7" {
			found_index = true
		}
		if binding.reflected_path[0] == 1 && input.text == "3" {
			found_generation = true
		}
	}
	testing.expect(t, found_index)
	testing.expect(t, found_generation)
}

@(test)
test_editor_entity_snapshots_and_running_values_refresh_at_five_hz :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_transform = true,
			transform = {position = {1, 2, 3}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity{name = "Second"},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[1].alive = false
	registry: component.Registry
	component.init_registry(&registry)
	transform_definition, _ := component.find_definition(&registry, "scrapbot.transform")
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.component_registry = &registry
	state.editor_visible = true
	state.editor_simulation_playing = true
	state.editor_simulation_stopped = false
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 1)
	testing.expect(t, state.editor_inspector_snapshot_refresh_count == 1)
	testing.expect(t, editor_browser_row_count(&world) == 1)

	world.entities[1].alive = true
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.1) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 1)
	testing.expect(t, editor_browser_row_count(&world) == 1)
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.11) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 2)
	testing.expect(t, state.editor_inspector_snapshot_refresh_count == 2)
	testing.expect(t, editor_browser_row_count(&world) == 1)
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, editor_browser_row_count(&world) == 2)

	position_x_input := -1
	for binding in world.editor_uis {
		if binding.role == .Inspector_Input &&
		   binding.reflected_component_id == transform_definition.id &&
		   binding.reflected_field_index == 0 &&
		   binding.inspector_axis == .X {
			position_x_input = binding.entity_index
			break
		}
	}
	testing.expect(t, position_x_input >= 0)
	world.transforms[world.entities[0].transform_index].position.x = 99
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.21) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 4)
	testing.expect(t, state.editor_inspector_snapshot_refresh_count == 4)
	if position_x_input >= 0 {
		input_index := world.entities[position_x_input].ui_input_index
		testing.expect(t, world.ui_inputs[input_index].text == "99.00")
		focus_input(state, &world, position_x_input)
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0, {text = "123"}) == "")
		testing.expect(t, world.ui_inputs[input_index].text == "123")
		testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 99)
		world.transforms[world.entities[0].transform_index].position.x = 42
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.21) == "")
		testing.expect(t, state.editor_inspector_snapshot_refresh_count == 5)
		testing.expect(t, world.ui_inputs[input_index].text == "123")
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0, {escape = true}) == "")
		testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 42)
	}

	// Selection changes bypass the interval so the inspector never opens stale.
	testing.expect(t, editor_select_entity(state, &world, world.entities[1].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 6)
	testing.expect(t, state.editor_inspector_snapshot_refresh_count == 6)
}

@(test)
test_editor_system_profile_uses_selectable_list_panel_and_scroll_components :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	profile: shared.System_Profile
	profile.entry_count = 3
	profile.sample_frames = 10
	profile.revision = 1
	profile.entries[0].kind = .Project_Odin
	profile.entries[0].average_nanoseconds = 1_500_000
	physics_name := "Physics"
	profile.entries[0].name_length = len(physics_name)
	for index in 0 ..< len(physics_name) {
		profile.entries[0].name[index] = physics_name[index]
	}
	profile.entries[1].kind = .Luau
	profile.entries[1].average_nanoseconds = 2_500
	luau_name := "Orbit Lights"
	profile.entries[1].name_length = len(luau_name)
	for index in 0 ..< len(luau_name) {
		profile.entries[1].name[index] = luau_name[index]
	}
	profile.entries[2].kind = .Luau
	profile.entries[2].average_nanoseconds = 4_000
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.system_profile = &profile

	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	systems, found := editor_ui_entity(&world, .Systems_Scroll)
	testing.expect(t, found)
	filter, filter_found := editor_ui_entity(&world, .Browser_Filter, 2)
	testing.expect(t, filter_found)
	panel, panel_found := ecs.entity_index_by_uuid(
		&world,
		shared.entity_uuid_from_engine_name(EDITOR_UI_SYSTEMS_NAME),
	)
	testing.expect(t, panel_found)
	if found && filter_found && panel_found {
		entity := world.entities[systems]
		panel_entity := world.entities[panel]
		filter_entity := world.entities[filter]
		testing.expect(t, entity.ui_panel_index < 0)
		testing.expect(t, entity.ui_list_index >= 0)
		testing.expect(t, entity.ui_scroll_area_index >= 0)
		testing.expect(t, panel_entity.ui_panel_index >= 0)
		testing.expect(t, panel_entity.ui_vstack_index >= 0)
		testing.expect(t, world.ui_panels[panel_entity.ui_panel_index].title == "SYSTEMS / 3")
		list := world.ui_lists[entity.ui_list_index]
		testing.expect_value(t, list.filter_input, world.entities[filter].uuid)
		testing.expect(t, list.virtualized)
		testing.expect_value(t, list.item_height, SYSTEM_PROFILE_CELL_HEIGHT)
		testing.expect_value(t, list.overscan, 2)
		testing.expect_value(t, world.ui_layouts[entity.ui_layout_index].parent, panel_entity.uuid)
		layout := world.ui_layouts[entity.ui_layout_index]
		testing.expect(t, layout.padding == (shared.Vec4{}))
		filter_layout := world.ui_layouts[filter_entity.ui_layout_index]
		filter_value := world.ui_inputs[filter_entity.ui_input_index]
		testing.expect(t, filter_layout.margin == shared.Vec4{2, 0, 2, 0})
		testing.expect(t, filter_layout.fill_width)
		testing.expect_value(
			t,
			filter_layout.padding.w,
			reduced_dark_theme().metrics.padding_control.w,
		)
		testing.expect_value(t, filter_value.prefix, "")
		testing.expect_value(t, filter_value.prefix_width, 0)
		testing.expect_value(t, filter_value.icon_set, shared.builtin_icon_set_uuid())
		testing.expect_value(t, filter_value.icon, "magnifying-glass")
		testing.expect_value(t, filter_value.icon_size, f32(14))
		filter_node := find_node_by_entity_index(state, filter)
		list_node := find_node_by_entity_index(state, systems)
		testing.expect(t, filter_node >= 0 && list_node >= 0)
		if filter_node >= 0 && list_node >= 0 {
			testing.expect(
				t,
				math.abs(state.nodes[filter_node].rect.x - state.nodes[list_node].rect.x) < 0.01,
			)
			testing.expect(
				t,
				math.abs(state.nodes[filter_node].rect.width - state.nodes[list_node].rect.width) <
				0.01,
			)
		}
	}
	first_row, first_row_found := editor_ui_entity(&world, .Systems_Row, 0)
	name_cell, name_found := editor_ui_entity(&world, .Systems_Name, 0)
	time_cell, time_found := editor_ui_entity(&world, .Systems_Time, 0)
	luau_cell, luau_found := editor_ui_entity(&world, .Systems_Name, 1)
	luau_time_cell, luau_time_found := editor_ui_entity(&world, .Systems_Time, 1)
	fallback_cell, fallback_found := editor_ui_entity(&world, .Systems_Name, 2)
	testing.expect(
		t,
		first_row_found &&
		name_found &&
		time_found &&
		luau_found &&
		luau_time_found &&
		fallback_found,
	)
	if name_found {
		text := world.ui_texts[world.entities[name_cell].ui_text_index]
		testing.expect(t, text.text == "Physics")
		testing.expect(t, text.size == EDITOR_TEXT_SIZE)
	}
	if time_found {
		text := world.ui_texts[world.entities[time_cell].ui_text_index]
		testing.expect(t, text.text == "1.500 ms")
		testing.expect(t, text.size == EDITOR_TEXT_SIZE)
		testing.expect(t, text.alignment == .Right)
	}
	if luau_found {
		text := world.ui_texts[world.entities[luau_cell].ui_text_index]
		testing.expect(t, text.text == luau_name)
	}
	if luau_time_found {
		text := world.ui_texts[world.entities[luau_time_cell].ui_text_index]
		testing.expect(t, text.text == "0.003 ms")
	}
	if fallback_found {
		text := world.ui_texts[world.entities[fallback_cell].ui_text_index]
		testing.expect(t, text.text == "Luau System 2")
	}
	if found && first_row_found && name_found {
		row_layout := world.ui_layouts[world.entities[first_row].ui_layout_index]
		testing.expect(t, row_layout.padding.y == 4 && row_layout.padding.w == 4)
		name_layout := world.ui_layouts[world.entities[name_cell].ui_layout_index]
		testing.expect(
			t,
			row_layout.padding.w + name_layout.padding.w == EDITOR_BROWSER_TEXT_INSET,
		)
		systems_node := find_node_by_entity_index(state, systems)
		row_node := find_node_by_entity_index(state, first_row)
		testing.expect(t, systems_node >= 0 && row_node >= 0)
		if systems_node >= 0 && row_node >= 0 {
			testing.expect(
				t,
				math.abs(state.nodes[row_node].rect.x - state.nodes[systems_node].rect.x) < 0.01,
			)
			testing.expect(
				t,
				math.abs(state.nodes[row_node].rect.width - state.nodes[systems_node].rect.width) <
				0.01,
			)
		}
		name_node := find_node_by_entity_index(state, name_cell)
		testing.expect(t, name_node >= 0)
		if name_node >= 0 {
			name_rect := state.nodes[name_node].rect
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{
						position = {name_rect.x + 10, name_rect.y + name_rect.height * 0.5},
						primary_down = true,
						available = true,
					},
				) ==
				"",
			)
			list := world.ui_lists[world.entities[systems].ui_list_index]
			testing.expect(t, list.selected == world.entities[first_row].uuid)
		}
	}
	if found && filter_found {
		testing.expect(t, ecs.set_ui_input_value(&world, filter, "orbit"))
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
		laid_out_system_rows := 0
		for binding in world.editor_uis {
			if binding.role != .Systems_Row || binding.entity_index < 0 {
				continue
			}
			node_index := find_node_by_entity_index(state, binding.entity_index)
			if node_index >= 0 && state.nodes[node_index].laid_out {
				laid_out_system_rows += 1
			}
		}
		testing.expect_value(t, laid_out_system_rows, 1)
		systems_node := find_node_by_entity_index(state, systems)
		testing.expect(t, systems_node >= 0)
		if systems_node >= 0 {
			testing.expect_value(t, state.nodes[systems_node].list_flow_count, 1)
		}
		testing.expect(t, ecs.set_ui_input_value(&world, filter, ""))
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	}
	project_origin, project_origin_found := editor_ui_entity(&world, .Systems_Origin, 0)
	luau_origin, luau_origin_found := editor_ui_entity(&world, .Systems_Origin, 1)
	testing.expect(t, project_origin_found && luau_origin_found)
	if project_origin_found {
		layout := world.ui_layouts[world.entities[project_origin].ui_layout_index]
		testing.expect(t, layout.background == system_profile_origin_color(.Project_Odin))
	}
	if luau_origin_found {
		layout := world.ui_layouts[world.entities[luau_origin].ui_layout_index]
		testing.expect(t, layout.background == system_profile_origin_color(.Luau))
	}
	first_row_entity := world.entities[first_row]
	testing.expect(t, first_row_entity.ui_progress_index >= 0)
	if first_row_entity.ui_progress_index >= 0 {
		progress := world.ui_progresses[first_row_entity.ui_progress_index]
		testing.expect(t, progress.fill_color == system_profile_origin_color(.Project_Odin))
		testing.expect(t, progress.value == f32(profile.entries[0].average_nanoseconds))
		testing.expect(t, progress.maximum == f32(SYSTEM_PROFILE_BAR_MAX_NANOSECONDS))
		testing.expect(t, progress.right_to_left)
	}
	testing.expect(
		t,
		system_profile_origin_color(.Engine) != system_profile_origin_color(.Project_Odin) &&
		system_profile_origin_color(.Engine) != system_profile_origin_color(.Luau),
	)

	refresh_count := state.editor_snapshot_refresh_count
	profile.entries[0].average_nanoseconds = 750_000
	profile.revision += 1
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == refresh_count)
	testing.expect(t, state.editor_system_profile_revision == profile.revision)
	if time_found {
		text := world.ui_texts[world.entities[time_cell].ui_text_index]
		testing.expect(t, text.text == "0.750 ms")
	}
}

@(test)
test_editor_performance_panel_uses_public_panel_table_and_text_components :: proc(t: ^testing.T) {
	world := ecs.build_world(&shared.Scene{})
	defer ecs.destroy_world(&world)
	diagnostics := shared.Performance_Diagnostics {
		fps = 59.9,
		frame_ms = 16.69,
		gpu_frame_ms = 2.25,
		gpu_scene_ms = 1.75,
		render_scale = 0.75,
		shadow_resolution = 1024,
		adaptive_post_quality = 0.75,
		gpu_timestamps_valid = true,
		entity_count = 42,
		retained_batches = 7,
		visible_batches = 4,
		visible_meshlet_draws = 11,
		frustum_culled_instances = 9,
		occlusion_culled_instances = 13,
		occlusion_culled_meshlets = 17,
		hiz_occlusion_status = .Active,
		hiz_instance_threshold = 256,
		sample_frames = 50,
		revision = 1,
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.performance_diagnostics = &diagnostics
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	panel, panel_found := editor_ui_entity(&world, .Diagnostics_Panel)
	testing.expect(t, panel_found)
	if panel_found {
		entity := world.entities[panel]
		testing.expect(t, entity.ui_panel_index >= 0)
		testing.expect(t, entity.ui_vstack_index >= 0)
		testing.expect(t, world.ui_panels[entity.ui_panel_index].title == "PERFORMANCE")
	}
	table := find_editor_name_node(state, &world, EDITOR_UI_DIAGNOSTICS_TABLE_NAME)
	testing.expect(t, table >= 0)
	if table >= 0 {
		entity := world.entities[int(state.nodes[table].entity.index)]
		testing.expect(t, entity.ui_table_index >= 0)
		testing.expect(t, entity.ui_scroll_area_index >= 0)
	}
	expected_labels := [15]string {
		"FPS",
		"CPU FRAME",
		"GPU FRAME",
		"GPU SCENE",
		"RENDER SCALE",
		"SHADOW MAP",
		"POST QUALITY",
		"ENTITIES",
		"RETAINED BATCHES",
		"VISIBLE BATCHES",
		"VISIBLE MESHLET DRAWS",
		"HI-Z CULLING",
		"FRUSTUM CULLED",
		"OBJECT OCCLUSION",
		"MESHLET OCCLUSION",
	}
	for expected, slot in expected_labels {
		cell, found := editor_ui_entity(&world, .Diagnostics_Label, slot)
		testing.expect(t, found)
		if !found {
			continue
		}
		entity := world.entities[cell]
		testing.expect(t, entity.ui_text_index >= 0)
		testing.expect(t, world.ui_texts[entity.ui_text_index].text == expected)
	}
	expected_values := [15]string {
		"59.9",
		"16.69 ms",
		"2.25 ms",
		"1.75 ms",
		"75%",
		"1024²",
		"75%",
		"42",
		"7",
		"4",
		"11",
		"ACTIVE",
		"9",
		"13",
		"17",
	}
	for expected, slot in expected_values {
		cell, found := editor_ui_entity(&world, .Diagnostics_Value, slot)
		testing.expect(t, found)
		if !found {
			continue
		}
		entity := world.entities[cell]
		testing.expect(t, entity.ui_text_index >= 0)
		testing.expect(t, world.ui_texts[entity.ui_text_index].text == expected)
		testing.expect(t, world.ui_texts[entity.ui_text_index].alignment == .Right)
	}
	previous_paint_revision := world.ui_editor_paint_revision
	diagnostics.visible_instances = 99
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, world.ui_editor_paint_revision == previous_paint_revision)
	diagnostics.entity_count = 43
	diagnostics.revision += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	entity_value, found := editor_ui_entity(&world, .Diagnostics_Value, 7)
	testing.expect(t, found)
	if found {
		text := world.ui_texts[world.entities[entity_value].ui_text_index]
		testing.expect(t, text.text == "43")
	}
	if panel_found && table >= 0 {
		panel_layout := world.ui_layouts[world.entities[panel].ui_layout_index]
		panel_layout.size.y = 120
		_ = ecs.set_ui_layout(&world, panel, panel_layout)
		testing.expect(t, reconcile(state, &world, 1280, 720) == "")
		table = find_editor_name_node(state, &world, EDITOR_UI_DIAGNOSTICS_TABLE_NAME)
		testing.expect(t, table >= 0)
		if table >= 0 {
			testing.expect(t, state.nodes[table].scroll_max > 0)
		}
	}
}

@(test)
test_editor_gizmo_appends_three_axis_lines_and_handles :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_gizmo_visible =
		true; state.editor_gizmo_origin = {100, 100}; state.editor_gizmo_endpoints = {{180, 100}, {100, 20}, {145, 145}}; state.editor_gizmo_hovered_handle = .Y
	testing.expect(t, append_editor_gizmo(state) == "")
	line_count, triangle_count := 0, 0; active_color_line_found := false
	for command in state.paint[:state.paint_count] {
		if command.kind ==
		   .Line { line_count += 1; if command.color.y > 0.8 && command.line_thickness == 5 { active_color_line_found = true } }
		if command.kind == .Triangle { triangle_count += 1 }
		testing.expect(t, command.color.x > 0.1 || command.color.y > 0.1 || command.color.z > 0.1)
	}
	testing.expect(t, line_count == 3)
	testing.expect(t, triangle_count == 9)
	testing.expect(t, active_color_line_found)
	center_handle_found := false
	for command in state.paint[:state.paint_count] { if command.kind == .Panel && command.rect.width == 11 { center_handle_found = true } }
	testing.expect(t, center_handle_found)
}

@(test)
test_editor_model_placement_preview_paints_contact_and_origin_feedback :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	state.editor_pixel_density = 1
	state.editor_model_placement_preview_visible = true
	state.editor_model_placement_preview_contact = {100, 120}
	state.editor_model_placement_preview_origin = {100, 80}
	state.editor_model_placement_preview_clip = {20, 30, 400, 300}
	state.paint_editor_overlay = true
	testing.expect(t, append_editor_model_placement_preview(state) == "")
	testing.expect_value(t, state.editor_overlay_paint_count, 5)
	testing.expect_value(t, state.editor_overlay_paint[0].kind, Paint_Kind.Ring)
	testing.expect_value(t, state.editor_overlay_paint[0].ring_center, shared.Vec2{100, 120})
	testing.expect_value(t, state.editor_overlay_paint[4].line_end, shared.Vec2{100, 80})
}

@(test)
test_editor_camera_mesh_appends_editor_viewport_lines :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_camera_mesh_segment_count = 2
	state.editor_camera_mesh_segments[0] = {
		start = {10, 20},
		end = {30, 40},
		color = {0.4, 0.7, 1, 1},
		thickness = 1.5,
	}
	state.editor_camera_mesh_segments[1] = {
		start = {30, 40},
		end = {50, 20},
		color = {1, 0.7, 0.2, 1},
		thickness = 2.25,
	}

	state.paint_count = 1
	state.paint[0] = {
		kind = .Panel,
		rect = {0, 0, 10, 10},
	}
	testing.expect(t, rebuild_editor_world_overlay(state) == "")
	overlay_revision := state.editor_overlay_paint_output_revision
	testing.expect(t, overlay_revision > 0)
	testing.expect(t, state.paint_count == 1)
	testing.expect(t, state.paint[0].kind == .Panel)
	testing.expect(t, state.editor_overlay_paint_count == 2)
	testing.expect(t, state.editor_overlay_paint[0].kind == .Line)
	testing.expect(t, state.editor_overlay_paint[0].line_start == shared.Vec2{10, 20})
	testing.expect(t, state.editor_overlay_paint[1].line_thickness == 2.25)
	testing.expect(t, rebuild_editor_world_overlay(state) == "")
	testing.expect_value(t, state.editor_overlay_paint_output_revision, overlay_revision)
	state.editor_camera_mesh_segments[1].thickness = 3
	testing.expect(t, rebuild_editor_world_overlay(state) == "")
	testing.expect(t, state.editor_overlay_paint_output_revision > overlay_revision)
}

@(test)
test_editor_gizmo_modes_render_rings_and_square_scale_handles :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_gizmo_visible =
		true; state.editor_gizmo_origin = {100, 100}; state.editor_gizmo_endpoints = {{180, 100}, {100, 20}, {145, 145}}
	for axis in 0 ..< 3 { for point_index in 0 ..< EDITOR_GIZMO_RING_POINT_COUNT { angle := f32(point_index) / EDITOR_GIZMO_RING_POINT_COUNT * 2 * math.PI; state.editor_gizmo_ring_points[axis][point_index] = {100 + math.cos(angle) * 60, 100 + math.sin(angle) * 60} } }
	state.editor_gizmo_mode = .Rotate
	testing.expect(t, append_editor_gizmo(state) == "")
	ring_count := 0
	for command in state.paint[:state.paint_count] { if command.kind == .Ring { ring_count += 1; testing.expect(t, command.ring_thickness == 1.35); testing.expect(t, command.ring_axis_x != shared.Vec2{} && command.ring_axis_y != shared.Vec2{}) } }
	testing.expect(t, ring_count == 3)

	state.paint_count = 0; state.editor_gizmo_mode = .Scale
	testing.expect(t, append_editor_gizmo(state) == "")
	square_handle_found := false
	for command in state.paint[:state.paint_count] { if command.kind == .Panel && command.rect.width == 12 && command.corner_radius == 1.5 { square_handle_found = true; break } }
	testing.expect(t, square_handle_found)

	state.editor_snapshot_valid =
		true; state.editor_gizmo_active_handle = .X; state.editor_gizmo_captures_pointer = true
	editor_set_gizmo_mode(state, .Translate)
	testing.expect(t, state.editor_gizmo_mode == .Translate && !state.editor_snapshot_valid)
	testing.expect(
		t,
		state.editor_gizmo_active_handle == .None && !state.editor_gizmo_captures_pointer,
	)
}

@(test)
test_editor_ui_role_lookup_is_indexed_and_repairs_a_missing_entry :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	root, found := editor_ui_entity(&world, .Root)
	testing.expect(t, found)
	key := shared.Editor_UI_Lookup_Key {
		role = .Root,
	}
	testing.expect(t, world.editor_ui_by_role_slot[key] == root)
	delete_key(&world.editor_ui_by_role_slot, key)

	repaired_root, repaired := editor_ui_entity(&world, .Root)
	testing.expect(t, repaired && repaired_root == root)
	testing.expect(t, world.editor_ui_by_role_slot[key] == root)
}

@(test)
test_editor_preview_reset_restores_camera_without_losing_target :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	resource, parsed := shared.resource_uuid_parse("a7000000-0000-4000-8000-000000000001")
	testing.expect(t, parsed)
	viewport := editor_ui_create_box(
		&world,
		"Preview Surface",
		"",
		.Inspector_Preview_Surface,
		{size = {320, 180}},
		3,
	)
	value := shared.ui_viewport_default()
	value.resource = resource
	value.orbit = {0.7, -2.1}
	value.distance = 9
	testing.expect(t, ecs.set_ui_viewport(&world, viewport, value))
	reset := editor_ui_create_box(
		&world,
		"Preview Reset",
		"",
		.Inspector_Preview_Reset,
		{size = {64, 28}},
		3,
	)
	editor_ui_handle_activation(state, &world, world.entities[reset].id, {})
	updated := world.ui_viewports[world.entities[viewport].ui_viewport_index]
	defaults := shared.ui_viewport_default()
	testing.expect(t, updated.resource == resource)
	testing.expect(t, updated.orbit == defaults.orbit)
	testing.expect(t, updated.distance == defaults.distance)
}

@(test)
test_editor_model_preview_requests_an_undoable_precise_scene_placement :: proc(t: ^testing.T) {
	parent_id := ui_test_id("Model Placement Parent")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Placement Parent",
			has_transform = true,
			transform = {position = {2, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	resource_id, parsed := shared.resource_uuid_parse("a7000000-0000-4000-8000-000000000031")
	testing.expect(t, parsed)
	declaration := shared.Project_Resource {
		id = resource_id,
		kind = .Model,
		name = "Handcrafted Cliff",
		source = "resources/cliff.resource.toml",
		model = {source = "assets/cliff.glb"},
	}
	product: asset_import.Model_Product
	_, register_err := resources.register_project_model(&registry, declaration, &product)
	testing.expect(t, register_err == "")

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.resource_registry = &registry
	state.editor_visible = true
	state.editor_simulation_stopped = true
	state.editor_selected_resource = resource_id
	state.editor_has_resource_selection = true
	_, _, camera_ready := ecs.reconcile_editor_scene_camera(&world, true)
	testing.expect(t, camera_ready)
	testing.expect(t, ecs.set_editor_scene_camera_pose(&world, {10, 4, 8}, {}))

	testing.expect(t, reconcile(state, &world, 1280, 720, resource_registry = &registry) == "")
	place, place_found := editor_ui_entity(&world, .Inspector_Preview_Place, 0)
	testing.expect(t, place_found)
	if !place_found {
		return
	}
	place_layout := world.ui_layouts[world.entities[place].ui_layout_index]
	testing.expect(t, !place_layout.hidden)
	editor_ui_handle_activation(state, &world, world.entities[place].id, {})
	request, requested := consume_model_placement_request(state)
	testing.expect(t, requested)
	testing.expect_value(t, request.resource, resource_id)
	_, placement_ok := editor_authoring_place_model(
		state,
		&world,
		&registry,
		request.resource,
		request.parent,
		shared.Vec3{1.5, 2, -3.5},
	)
	testing.expect(t, placement_ok)

	placed_index, placed := editor_selected_world_index(state, &world)
	testing.expect(t, placed)
	if !placed {
		return
	}
	entity := world.entities[placed_index]
	testing.expect_value(t, entity.name, "Handcrafted Cliff")
	testing.expect(t, entity.origin == .Scene)
	testing.expect(t, entity.transform_index >= 0)
	testing.expect_value(
		t,
		world.transforms[entity.transform_index].position,
		shared.Vec3{1.5, 2, -3.5},
	)
	id_buffer: [36]u8
	testing.expect_value(
		t,
		entity.model_resource,
		shared.resource_uuid_to_string(resource_id, id_buffer[:]),
	)
	testing.expect(t, entity.geometry_mode == .Inherit)
	placed_id := entity.uuid
	testing.expect(t, state.editor_scene_dirty)
	testing.expect_value(t, state.editor_history_count, 1)

	testing.expect(t, editor_undo(state, &world))
	_, found_after_undo := ecs.entity_index_by_uuid(&world, placed_id)
	testing.expect(t, !found_after_undo)
	testing.expect(t, editor_redo(state, &world))
	restored_index, restored := ecs.entity_index_by_uuid(&world, placed_id)
	testing.expect(t, restored)
	if restored {
		testing.expect_value(t, world.entities[restored_index].name, "Handcrafted Cliff")
		testing.expect_value(
			t,
			world.transforms[world.entities[restored_index].transform_index].position,
			shared.Vec3{1.5, 2, -3.5},
		)
	}

	resource_row, resource_row_found := editor_ui_entity(&world, .Project_Resource_Row, 0)
	parent_row, parent_row_found := editor_ui_entity(&world, .Browser_Row, 0)
	testing.expect(t, resource_row_found && parent_row_found)
	if resource_row_found && parent_row_found {
		resource_action_index := world.entities[resource_row].ui_action_index
		testing.expect(t, resource_action_index >= 0)
		if resource_action_index >= 0 {
			testing.expect(t, world.ui_actions[resource_action_index].drag_source)
		}
		event_cursor := ecs.ui_event_latest_sequence(&world)
		state.events[0] = {
			kind = .Dropped,
			entity = world.entities[parent_row].id,
			source = world.entities[resource_row].id,
			target = world.entities[parent_row].id,
			drop_placement = .Into,
		}
		state.event_count = 1
		publish_ui_events(state, &world)
		testing.expect(t, editor_ui_consume_events(state, &world, event_cursor))
		request, requested = consume_model_placement_request(state)
		testing.expect(t, requested)
		_, placement_ok = editor_authoring_place_model(
			state,
			&world,
			&registry,
			request.resource,
			request.parent,
			shared.Vec3{1.5, 2, -3.5},
		)
		testing.expect(t, placement_ok)
		child_index, child_placed := editor_selected_world_index(state, &world)
		testing.expect(t, child_placed)
		if child_placed {
			testing.expect_value(t, editor_entity_parent_uuid(&world, child_index), parent_id)
			ecs.begin_world_transform_resolution(&world)
			child_world, valid := ecs.resolve_world_transform(&world, child_index)
			testing.expect(t, valid)
			testing.expect_value(t, child_world.position, shared.Vec3{1.5, 2, -3.5})
		}
		testing.expect_value(t, state.editor_history_count, 2)
		testing.expect(t, editor_undo(state, &world))
	}

	state.editor_simulation_stopped = false
	refresh_editor_ecs_snapshot(state, &world)
	if resource_row_found {
		resource_action_index := world.entities[resource_row].ui_action_index
		testing.expect(t, resource_action_index >= 0)
		if resource_action_index >= 0 {
			testing.expect(t, !world.ui_actions[resource_action_index].drag_source)
		}
	}
	_, placed_while_running := editor_authoring_place_model(state, &world, &registry, resource_id)
	testing.expect(t, !placed_while_running)
}
@(test)
test_editor_viewport_is_clamped_to_a_small_physical_target :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	state.editor_visible = true
	state.editor_pixel_density = 2
	state.node_count = 1
	state.nodes[0] = {
		origin = .Editor,
		editor_role = .Viewport,
		rect = {124, 26, 314.5, 319},
	}

	viewport := editor_viewport(state, 480, 270)
	testing.expect_value(t, viewport, Rect{248, 52, 232, 218})
	testing.expect(t, viewport.x + viewport.width <= 480)
	testing.expect(t, viewport.y + viewport.height <= 270)
}
