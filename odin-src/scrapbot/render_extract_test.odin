package main

import "core:os"
import "core:testing"

@(test)
test_render_extract_counts_minimal_project_scene :: proc(t: ^testing.T) {
	result := check_project("examples/minimal")
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)

	extract, extract_err := render_extract_scene(result.scene.world)
	testing.expect_value(t, extract_err, Render_Extract_Error.None)
	testing.expect_value(t, extract.renderables, 2)
	testing.expect_value(t, extract.legacy_cubes, 2)
	testing.expect_value(t, extract.geometry_primitives, 0)
	testing.expect_value(t, extract.render_batches, 1)
	testing.expect_value(t, extract.cameras, 1)
	testing.expect_value(t, extract.directional_lights, 1)
}

@(test)
test_render_extract_batches_geometry_by_primitive_and_shadow_state :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	add_test_renderable(t, &world, "blue-box-a", "box", 0, 0, true, false)
	add_test_renderable(t, &world, "blue-box-b", "box", 0, 0, true, false)
	add_test_renderable(t, &world, "blue-box-receiver", "box", 0, 0, false, true)
	add_test_renderable(t, &world, "gold-sphere", "uv_sphere", 16, 8, false, false)

	extract, extract_err := render_extract_scene(world)
	testing.expect_value(t, extract_err, Render_Extract_Error.None)
	testing.expect_value(t, extract.renderables, 4)
	testing.expect_value(t, extract.geometry_primitives, 4)
	testing.expect_value(t, extract.legacy_cubes, 0)
	testing.expect_value(t, extract.render_batches, 3)
	testing.expect_value(t, extract.shadow_casters, 2)
	testing.expect_value(t, extract.shadow_receivers, 1)
}

@(test)
test_render_extract_counts_shadow_flags_only_for_renderables :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity, entity_err := runtime_world_create_entity(&world, "shadow-only", "Shadow Only")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	transform_fields := []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "rotation", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "scale", value = runtime_component_value_vec3({1.0, 1.0, 1.0})},
	}
	testing.expect_value(t, runtime_world_set_component(&world, entity, TRANSFORM_COMPONENT_ID, transform_fields), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, entity, SHADOW_CASTER_COMPONENT_ID, []Runtime_Component_Field_Value{}), Runtime_Error.None)

	extract, extract_err := render_extract_scene(world)
	testing.expect_value(t, extract_err, Render_Extract_Error.None)
	testing.expect_value(t, extract.renderables, 0)
	testing.expect_value(t, extract.shadow_casters, 0)
}

@(test)
test_render_extract_counts_ui_primitives :: proc(t: ^testing.T) {
	root := make_test_project(t, "render-extract-ui")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"UI\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "panel"
name = "Panel"

[entities.components."scrapbot.ui.rect"]
position = [1.0, 2.0, 0.0]
size = [10.0, 20.0, 0.0]
color = [0.1, 0.2, 0.3]

[[entities]]
id = "label"
name = "Label"

[entities.components."scrapbot.ui.text"]
position = [2.0, 3.0, 0.0]
size = 1.0
color = [1.0, 1.0, 1.0]
value = "READY"
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)

	extract, extract_err := render_extract_scene(result.scene.world)
	testing.expect_value(t, extract_err, Render_Extract_Error.None)
	testing.expect_value(t, extract.ui_rects, 1)
	testing.expect_value(t, extract.ui_texts, 1)
}

@(test)
test_render_extract_rejects_unknown_geometry_primitive :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	add_test_renderable(t, &world, "unknown", "unknown_shape", 0, 0, false, false)

	_, extract_err := render_extract_scene(world)
	testing.expect_value(t, extract_err, Render_Extract_Error.Invalid_Scene)
}

add_test_renderable :: proc(
	t: ^testing.T,
	world: ^Runtime_World,
	id: string,
	primitive: string,
	segments, rings: int,
	casts_shadow, receives_shadow: bool,
) {
	entity, entity_err := runtime_world_create_entity(world, id, id)
	testing.expect_value(t, entity_err, Runtime_Error.None)

	transform_fields := []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "rotation", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "scale", value = runtime_component_value_vec3({1.0, 1.0, 1.0})},
	}
	testing.expect_value(t, runtime_world_set_component(world, entity, TRANSFORM_COMPONENT_ID, transform_fields), Runtime_Error.None)

	geometry_fields := []Runtime_Component_Field_Value{
		{name = "primitive", value = runtime_component_value_string(primitive)},
		{name = "segments", value = runtime_component_value_int(segments)},
		{name = "rings", value = runtime_component_value_int(rings)},
	}
	testing.expect_value(t, runtime_world_set_component(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID, geometry_fields), Runtime_Error.None)

	material_fields := []Runtime_Component_Field_Value{
		{name = "base_color", value = runtime_component_value_vec3({0.1, 0.2, 0.3})},
	}
	testing.expect_value(t, runtime_world_set_component(world, entity, SURFACE_MATERIAL_COMPONENT_ID, material_fields), Runtime_Error.None)

	if casts_shadow {
		testing.expect_value(t, runtime_world_set_component(world, entity, SHADOW_CASTER_COMPONENT_ID, []Runtime_Component_Field_Value{}), Runtime_Error.None)
	}
	if receives_shadow {
		testing.expect_value(t, runtime_world_set_component(world, entity, SHADOW_RECEIVER_COMPONENT_ID, []Runtime_Component_Field_Value{}), Runtime_Error.None)
	}
}
