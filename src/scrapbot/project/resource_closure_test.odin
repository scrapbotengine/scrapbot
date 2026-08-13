#+feature dynamic-literals
package project

import shared "../shared"
import "core:testing"

resource_closure_test_id :: proc(value: string) -> shared.Resource_UUID {
	id, _ := shared.resource_uuid_parse(value)
	return id
}

@(test)
test_scene_resource_closure_is_deduplicated_and_dependency_first :: proc(t: ^testing.T) {
	texture := resource_closure_test_id("c1000000-0000-4000-8000-000000000001")
	shader := resource_closure_test_id("c1000000-0000-4000-8000-000000000002")
	material := resource_closure_test_id("c1000000-0000-4000-8000-000000000003")
	model := resource_closure_test_id("c1000000-0000-4000-8000-000000000004")
	environment := resource_closure_test_id("c1000000-0000-4000-8000-000000000005")
	resources := []shared.Project_Resource {
		{id = texture, kind = .Texture},
		{id = shader, kind = .Shader},
		{id = material, kind = .Material, material = {texture = texture, shader = shader}},
		{id = model, kind = .Model},
		{id = environment, kind = .Environment},
	}
	material_text := "c1000000-0000-4000-8000-000000000003"
	model_text := "c1000000-0000-4000-8000-000000000004"
	environment_text := "c1000000-0000-4000-8000-000000000005"
	scene := Scene {
		entities = {
			{
				has_material = true,
				material_resource = material_text,
				has_model = true,
				model = {resource = model_text},
			},
			{
				has_material = true,
				material_resource = material_text,
				has_world_environment = true,
				world_environment = {lighting = environment_text, background = environment_text},
			},
		},
	}
	defer destroy_scene(&scene)
	closure := scene_resource_closure(&scene, resources)
	defer delete(closure)
	testing.expect_value(t, len(closure), 5)
	if len(closure) == 5 {
		texture_index, shader_index, material_index := -1, -1, -1
		for id, index in closure {
			if id == texture {
				texture_index = index
			} else if id == shader {
				shader_index = index
			} else if id == material {
				material_index = index
			}
		}
		testing.expect(t, texture_index >= 0 && texture_index < material_index)
		testing.expect(t, shader_index >= 0 && shader_index < material_index)
	}
}

@(test)
test_scene_resource_closure_excludes_unreferenced_declarations :: proc(t: ^testing.T) {
	referenced := resource_closure_test_id("c2000000-0000-4000-8000-000000000001")
	unreferenced := resource_closure_test_id("c2000000-0000-4000-8000-000000000002")
	referenced_text := "c2000000-0000-4000-8000-000000000001"
	resources := []shared.Project_Resource {
		{id = referenced, kind = .Model},
		{id = unreferenced, kind = .Model},
	}
	scene := Scene {
		entities = {{has_model = true, model = {resource = referenced_text}}},
	}
	defer destroy_scene(&scene)
	closure := scene_resource_closure(&scene, resources)
	defer delete(closure)
	testing.expect_value(t, len(closure), 1)
	if len(closure) == 1 {
		testing.expect_value(t, closure[0], referenced)
	}
}
