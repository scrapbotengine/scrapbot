package scrapbot

import ecs "./ecs"
import project "./project"
import shared "./shared"
import ui "./ui"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

scene_persistence_failing_writer :: proc(path, source: string) -> string {
	return "injected scene write failure"
}

scene_persistence_fixture :: proc(count: int) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "# persistence torture fixture\n\n")
	for ordinal in 0 ..< count {
		id := shared.entity_uuid_from_engine_name(fmt.tprintf("persistence-%04d", ordinal))
		strings.write_string(&builder, "[[entities]]\n")
		write_scene_string(&builder, "id", scene_uuid(id))
		write_scene_string(&builder, "name", fmt.tprintf("Entity %04d", ordinal))
		strings.write_string(&builder, "\n[entities.transform]\n")
		fmt.sbprintf(&builder, "position = [%d, 1, 2] # entity-%04d position\n", ordinal, ordinal)
		strings.write_string(&builder, "rotation = [ 0, 0, 0 ] # preserve spacing\n")
		strings.write_string(&builder, "scale = [1, 1, 1]\n\n")
	}
	result, _ := strings.clone(strings.to_string(builder))
	return result
}

scene_persistence_read :: proc(t: ^testing.T, path: string) -> string {
	bytes, err := os.read_entire_file(path, context.allocator)
	testing.expectf(t, err == nil, "failed to read persistence fixture: %v", err)
	if err != nil {
		return ""
	}
	return string(bytes)
}

scene_persistence_expect_world_matches_disk :: proc(
	t: ^testing.T,
	path: string,
	world: ^shared.World,
) {
	loaded := project.load_scene_file(path)
	defer project.destroy_scene_load_result(&loaded)
	testing.expectf(t, loaded.err == "", "saved persistence scene did not reload: %s", loaded.err)
	if loaded.err != "" {
		return
	}
	reloaded := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&reloaded)
	scene_count := 0
	for entity in world.entities {
		if entity.alive && entity.origin == .Scene {
			scene_count += 1
		}
	}
	testing.expect_value(t, len(loaded.scene.entities), scene_count)
	for entity in loaded.scene.entities {
		current_index, current_found := ecs.entity_index_by_uuid(world, entity.id)
		reloaded_index, reloaded_found := ecs.entity_index_by_uuid(&reloaded, entity.id)
		testing.expectf(
			t,
			current_found && reloaded_found,
			"saved UUID %s is missing from one world",
			scene_uuid(entity.id),
		)
		if !current_found || !reloaded_found {
			continue
		}
		current_source := strings.builder_make()
		reloaded_source := strings.builder_make()
		_ = write_scene_world_entity(&current_source, world, current_index)
		_ = write_scene_world_entity(&reloaded_source, &reloaded, reloaded_index)
		testing.expect_value(
			t,
			strings.to_string(reloaded_source),
			strings.to_string(current_source),
		)
		strings.builder_destroy(&current_source)
		strings.builder_destroy(&reloaded_source)
	}
}

@(test)
test_scene_persistence_saves_explicit_entity_order_without_reparenting :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-order-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	a_id := shared.entity_uuid_from_engine_name("order-a")
	b_id := shared.entity_uuid_from_engine_name("order-b")
	c_id := shared.entity_uuid_from_engine_name("order-c")
	source := fmt.tprintf(
		`[[entities]]
id = "%s"
name = "A"

[[entities]]
id = "%s"
name = "B"

[[entities]]
id = "%s"
name = "C"
`,
		scene_uuid(a_id),
		scene_uuid(b_id),
		scene_uuid(c_id),
	)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)
	loaded := project.load_scene_file(scene_path)
	testing.expect_value(t, loaded.err, "")
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	a_index, a_found := ecs.entity_index_by_uuid(&world, a_id)
	c_index, c_found := ecs.entity_index_by_uuid(&world, c_id)
	testing.expect(t, a_found && c_found)
	if !a_found || !c_found {
		return
	}
	testing.expect(t, ecs.move_entity_scene_order(&world, c_index, a_index, false))
	dirty := []shared.Entity_UUID{c_id}
	testing.expect_value(t, save_scene_world(scene_path, &world, dirty), "")
	saved := scene_persistence_read(t, scene_path)
	defer delete(saved)
	reloaded := project.load_scene_file(scene_path)
	defer project.destroy_scene_load_result(&reloaded)
	testing.expect_value(t, reloaded.err, "")
	if reloaded.err == "" {
		testing.expect_value(t, len(reloaded.scene.entities), 3)
		testing.expect_value(t, reloaded.scene.entities[0].id, c_id)
		testing.expect_value(t, reloaded.scene.entities[1].id, a_id)
		testing.expect_value(t, reloaded.scene.entities[2].id, b_id)
	}
	testing.expect_value(t, save_scene_world(scene_path, &world, dirty), "")
	second := scene_persistence_read(t, scene_path)
	defer delete(second)
	testing.expect_value(t, second, saved)
}

@(test)
test_scene_persistence_scales_candidate_work_and_preserves_value_blocks :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-scale-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	source := scene_persistence_fixture(512)
	defer delete(source)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)

	loaded := project.load_scene_file(scene_path)
	testing.expectf(t, loaded.err == "", "large fixture failed to load: %s", loaded.err)
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	value_id := shared.entity_uuid_from_engine_name("persistence-0400")
	structural_id := shared.entity_uuid_from_engine_name("persistence-0003")
	value_index, value_found := ecs.entity_index_by_uuid(&world, value_id)
	structural_index, structural_found := ecs.entity_index_by_uuid(&world, structural_id)
	testing.expect(t, value_found && structural_found)
	if !value_found || !structural_found {
		return
	}
	world.transforms[world.entities[value_index].transform_index].position.x = 400.5
	testing.expect(t, ecs.set_entity_name(&world, structural_index, "Structurally Renamed"))
	runtime_index, runtime_created := ecs.create_world_entity(&world, "Runtime Only", {}, .Runtime)
	testing.expect(t, runtime_created)
	runtime_id := world.entities[runtime_index].uuid
	promoted_index, promoted_created := ecs.create_world_entity(
		&world,
		"Promoted Runtime",
		{},
		.Runtime,
	)
	testing.expect(t, promoted_created)
	ecs.add_transform(&world, promoted_index, {position = {8, 9, 10}, scale = {1, 1, 1}})
	testing.expect(t, ecs.promote_entity_to_scene(&world, promoted_index))
	promoted_id := world.entities[promoted_index].uuid
	dirty: [dynamic]shared.Entity_UUID
	defer delete(dirty)
	value_candidates := make(map[shared.Entity_UUID]bool)
	defer delete(value_candidates)
	value_candidates[value_id] = true
	append(&dirty, value_id, value_id, structural_id, runtime_id, promoted_id)
	seed := u64(0x7a91_4e2d_c6b8_035f)
	for _ in 0 ..< 64 {
		ordinal := int(lifecycle_next_random(&seed) % 512)
		if ordinal == 3 {
			ordinal = 4
		}
		id := shared.entity_uuid_from_engine_name(fmt.tprintf("persistence-%04d", ordinal))
		index, found := ecs.entity_index_by_uuid(&world, id)
		testing.expect(t, found)
		if !found {
			continue
		}
		world.transforms[world.entities[index].transform_index].position.y += 0.25
		value_candidates[id] = true
		append(&dirty, id)
	}
	stats: Scene_Save_Stats
	save_err := save_scene_world_with_writer(
		scene_path,
		&world,
		dirty[:],
		write_scene_atomically,
		&stats,
	)
	testing.expectf(t, save_err == "", "large mixed save failed: %s", save_err)
	testing.expect_value(t, stats.dirty_candidates, len(dirty))
	testing.expect_value(t, stats.unique_dirty_candidates, len(value_candidates) + 3)
	testing.expect_value(t, stats.structural_candidates, 2)
	testing.expect_value(t, stats.value_candidates, len(value_candidates))
	testing.expect_value(t, stats.ignored_candidates, 1)
	saved := scene_persistence_read(t, scene_path)
	defer delete(saved)
	testing.expect(t, strings.contains(saved, "position = [400.5, 1, 2] # entity-0400 position"))
	testing.expect(t, strings.contains(saved, "rotation = [ 0, 0, 0 ] # preserve spacing"))
	testing.expect(t, strings.contains(saved, "name = \"Structurally Renamed\""))
	testing.expect(t, !strings.contains(saved, "Runtime Only"))
	testing.expect(t, strings.contains(saved, "name = \"Promoted Runtime\""))
	untouched := fmt.tprintf(
		`[[entities]]
id = "%s"
name = "Entity 0255"

[entities.transform]
position = [255, 1, 2] # entity-0255 position
rotation = [ 0, 0, 0 ] # preserve spacing
scale = [1, 1, 1]
`,
		scene_uuid(shared.entity_uuid_from_engine_name("persistence-0255")),
	)
	testing.expect(t, strings.contains(saved, untouched))

	testing.expect(t, save_scene_world(scene_path, &world, dirty[:]) == "")
	second := scene_persistence_read(t, scene_path)
	defer delete(second)
	testing.expect_value(t, second, saved)
	scene_persistence_expect_world_matches_disk(t, scene_path, &world)
}

@(test)
test_scene_persistence_write_failure_never_changes_original :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-failure-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	source := scene_persistence_fixture(2)
	defer delete(source)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)
	loaded := project.load_scene_file(scene_path)
	testing.expect(t, loaded.err == "")
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	id := shared.entity_uuid_from_engine_name("persistence-0001")
	index, found := ecs.entity_index_by_uuid(&world, id)
	testing.expect(t, found)
	if !found {
		return
	}
	world.transforms[world.entities[index].transform_index].position.y = 99
	dirty := [1]shared.Entity_UUID{id}
	err := save_scene_world_with_writer(
		scene_path,
		&world,
		dirty[:],
		scene_persistence_failing_writer,
	)
	testing.expect_value(t, err, "injected scene write failure")
	unchanged := scene_persistence_read(t, scene_path)
	defer delete(unchanged)
	testing.expect_value(t, unchanged, source)
}

@(test)
test_scene_persistence_rejects_invalid_generated_toml_before_write :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-validation-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	source := scene_persistence_fixture(1)
	defer delete(source)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)
	loaded := project.load_scene_file(scene_path)
	testing.expect(t, loaded.err == "")
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	id := shared.entity_uuid_from_engine_name("persistence-0000")
	index, found := ecs.entity_index_by_uuid(&world, id)
	testing.expect(t, found)
	if !found {
		return
	}
	ecs.add_scene_custom_component(
		&world,
		index,
		shared.Custom_Component{name = "invalid component name"},
	)
	dirty := [1]shared.Entity_UUID{id}
	err := save_scene_world_with_writer(
		scene_path,
		&world,
		dirty[:],
		scene_persistence_failing_writer,
	)
	testing.expect(
		t,
		strings.has_prefix(err, "refusing to replace scene with invalid generated TOML"),
	)
	unchanged := scene_persistence_read(t, scene_path)
	defer delete(unchanged)
	testing.expect_value(t, unchanged, source)
}

@(test)
test_scene_persistence_structural_roundtrip_covers_every_scene_component :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-schema-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	source := scene_persistence_fixture(1)
	defer delete(source)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)
	loaded := project.load_scene_file(scene_path)
	testing.expect(t, loaded.err == "")
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}

	custom: shared.Custom_Component = {
		name = "velocity",
	}
	append(&custom.vec3_fields, shared.Named_Vec3{name = "amount", value = {1, 2, 3}})
	root_id := shared.entity_uuid_from_engine_name("persistence-schema-root")
	root := shared.Scene_Entity {
		id = root_id,
		name = "Schema Root",
		has_transform = true,
		transform = {position = {1, 2, 3}, rotation = {0.1, 0.2, 0.3}, scale = {2, 3, 4}},
		has_camera = true,
		camera = {fov = 72, near = 0.05, far = 500},
		has_ambient_light = true,
		ambient_light = {color = {0.1, 0.2, 0.3}, intensity = 0.4},
		has_directional_light = true,
		directional_light = {direction = {-0.5, -1, 0.25}, color = {1, 0.8, 0.6}, intensity = 2},
		has_point_light = true,
		point_light = {color = {0.2, 0.4, 1}, intensity = 12, range = 25},
		has_mesh = true,
		mesh = {primitive = "cube"},
		has_geometry = true,
		geometry_resource = "schema-geometry",
		has_material = true,
		material_resource = "a6000000-0000-4000-8000-000000000001",
		has_shadow_caster = true,
		has_shadow_receiver = true,
		has_ui_layout = true,
		ui_layout = {size = {800, 600}},
	}
	append(&root.custom_components, custom)
	append(&loaded.scene.entities, root)
	transform_child_id := shared.entity_uuid_from_engine_name("persistence-schema-transform-child")
	append(
		&loaded.scene.entities,
		shared.Scene_Entity {
			id = transform_child_id,
			name = "Schema Transform Child",
			has_transform = true,
			transform = {
				parent = root_id,
				position = {4, 5, 6},
				rotation = {0.4, 0.5, 0.6},
				scale = {0.5, 0.5, 0.5},
			},
		},
	)
	controls_id := shared.entity_uuid_from_engine_name("persistence-schema-controls")
	layout := shared.ui_layout_default()
	layout.parent = root_id
	layout.position = {10, 20}
	layout.size = {640, 480}
	layout.min_size = {120, 80}
	layout.margin = {1, 2, 3, 4}
	layout.padding = {5, 6, 7, 8}
	layout.background = {0.1, 0.2, 0.3, 0.9}
	layout.border_color = {0.4, 0.5, 0.6, 1}
	layout.border_width = 2
	layout.corner_radius = 8
	layout.fill_width = true
	layout.fit_content_height = true
	panel := shared.ui_panel_default()
	panel.title = "Schema Panel"
	panel.font = "Inter"
	panel.collapsible = true
	panel.collapsed = false
	progress := shared.ui_progress_default()
	progress.value = 3
	progress.maximum = 10
	text := shared.ui_text_default()
	text.text = "Schema Text"
	text.font = "Inter"
	text.alignment = .Right
	button := shared.ui_button_default()
	button.text = "Schema Button"
	button.font = "Inter"
	button.alignment = .Center
	input := shared.ui_input_default()
	input.text = "12.5"
	input.font = "Inter"
	input.prefix = "X"
	input.number = 12.5
	input.numeric = true
	input.has_minimum = true
	input.minimum = -100
	checkbox := shared.ui_checkbox_default()
	checkbox.checked = true
	append(
		&loaded.scene.entities,
		shared.Scene_Entity {
			id = controls_id,
			name = "Schema Controls",
			has_ui_layout = true,
			ui_layout = layout,
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
			has_ui_panel = true,
			ui_panel = panel,
			has_ui_progress = true,
			ui_progress = progress,
			has_ui_text = true,
			ui_text = text,
		},
	)
	button_id := shared.entity_uuid_from_engine_name("persistence-schema-button")
	input_id := shared.entity_uuid_from_engine_name("persistence-schema-input")
	checkbox_id := shared.entity_uuid_from_engine_name("persistence-schema-checkbox")
	append(
		&loaded.scene.entities,
		shared.Scene_Entity {
			id = button_id,
			name = "Schema Button",
			has_ui_layout = true,
			ui_layout = {parent = controls_id, size = {180, 40}},
			has_ui_button = true,
			ui_button = button,
		},
		shared.Scene_Entity {
			id = input_id,
			name = "Schema Input",
			has_ui_layout = true,
			ui_layout = {parent = controls_id, size = {180, 40}},
			has_ui_input = true,
			ui_input = input,
		},
		shared.Scene_Entity {
			id = checkbox_id,
			name = "Schema Checkbox",
			has_ui_layout = true,
			ui_layout = {parent = controls_id, size = {40, 40}},
			has_ui_checkbox = true,
			ui_checkbox = checkbox,
		},
	)
	container_ids: [4]shared.Entity_UUID
	for kind in 0 ..< 4 {
		container_ids[kind] = shared.entity_uuid_from_engine_name(
			fmt.tprintf("persistence-schema-container-%d", kind),
		)
		entity: shared.Scene_Entity = {
			id = container_ids[kind],
			name = fmt.tprintf("Schema Container %d", kind),
			has_ui_layout = true,
			ui_layout = {parent = controls_id, size = {320, 180}},
		}
		switch kind {
			case 0:
				entity.has_ui_hstack = true
				entity.ui_hstack = {
					gap = 9,
					fill = true,
					draggable = true,
					min_size = 40,
				}
			case 1:
				entity.has_ui_vstack = true
				entity.ui_vstack = {
					gap = 7,
					fill = false,
					min_size = 32,
				}
			case 2:
				entity.has_ui_table = true
				entity.ui_table = {
					columns = 3,
					column_gap = 6,
					row_gap = 4,
					proportional_columns = true,
					resizable_columns = true,
					min_column_width = 48,
				}
			case 3:
				entity.has_ui_list = true
				entity.ui_list = shared.ui_list_default()
				entity.ui_list.selected = controls_id
				entity.ui_list.gap = 3
		}
		append(&loaded.scene.entities, entity)
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	dirty := [10]shared.Entity_UUID {
		root_id,
		transform_child_id,
		controls_id,
		button_id,
		input_id,
		checkbox_id,
		container_ids[0],
		container_ids[1],
		container_ids[2],
		container_ids[3],
	}
	save_err := save_scene_world(scene_path, &world, dirty[:])
	testing.expectf(t, save_err == "", "complete component schema save failed: %s", save_err)
	if save_err == "" {
		scene_persistence_expect_world_matches_disk(t, scene_path, &world)
	}
}

@(test)
test_scene_persistence_savepoints_roundtrip_through_undo_redo_and_revert :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-persistence-history-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	source := scene_persistence_fixture(1)
	defer delete(source)
	testing.expect(t, os.write_entire_file(scene_path, source) == nil)
	loaded := project.load_scene_file(scene_path)
	testing.expect(t, loaded.err == "")
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .Transform_Position,
		inspector_axis = .X,
	}
	testing.expect(t, ui.write_inspector_numeric(state, &world, binding, 42))
	ui.editor_history_push(state, &world, binding, 0, 42)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, save_scene_world(scene_path, &world, state.editor_dirty_entities[:]) == "")
	ui.complete_scene_save(state, true)
	saved := scene_persistence_read(t, scene_path)
	defer delete(saved)
	testing.expect(t, strings.contains(saved, "position = [42, 1, 2]"))

	testing.expect(t, ui.editor_undo(state, &world))
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, save_scene_world(scene_path, &world, state.editor_dirty_entities[:]) == "")
	ui.complete_scene_save(state, true)
	undone := scene_persistence_read(t, scene_path)
	defer delete(undone)
	testing.expect(t, strings.contains(undone, "position = [0, 1, 2]"))

	testing.expect(t, ui.editor_redo(state, &world))
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, save_scene_world(scene_path, &world, state.editor_dirty_entities[:]) == "")
	ui.complete_scene_save(state, true)
	redone := scene_persistence_read(t, scene_path)
	defer delete(redone)
	testing.expect_value(t, redone, saved)

	testing.expect(t, ui.write_inspector_numeric(state, &world, binding, -8))
	ui.editor_history_push(state, &world, binding, 42, -8)
	testing.expect(t, state.editor_scene_dirty)
	reverted := project.load_scene_file(scene_path)
	testing.expect(t, reverted.err == "")
	if reverted.err == "" {
		next_world := ecs.build_world(&reverted.scene)
		ecs.destroy_world(&world)
		world = next_world
		ui.complete_scene_revert(state, true)
	}
	project.destroy_scene_load_result(&reverted)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect_value(t, state.editor_history_count, 0)
	position := world.transforms[world.entities[0].transform_index].position
	testing.expect_value(t, position, shared.Vec3{42, 1, 2})
}
