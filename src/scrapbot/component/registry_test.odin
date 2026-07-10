package component

import "core:testing"
import shared "../shared"

@(test)
test_registry_contains_engine_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	transform, transform_ok := find_definition(&registry, "scrapbot.transform")
	testing.expect(t, transform_ok)
	testing.expect(t, transform.owner == .Engine)
	testing.expect(t, transform.field_count == 3)

	_, camera_ok := find_definition(&registry, "scrapbot.camera")
	testing.expect(t, camera_ok)
	_, mesh_ok := find_definition(&registry, "scrapbot.mesh")
	testing.expect(t, mesh_ok)
}

@(test)
test_registry_rejects_project_component_name_collisions :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	err := register_project_component(&registry, Definition{name = "scrapbot.transform"})
	testing.expect(t, err == "project scripts can only define single-token project component names")

	err = register_project_component(&registry, Definition{name = "autorotate"})
	testing.expect(t, err == "")
	autorotate, autorotate_ok := find_definition(&registry, "autorotate")
	testing.expect(t, autorotate_ok)
	testing.expect(t, autorotate.owner == .Project)
}

@(test)
test_registry_validates_scene_component_fields :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	definition := Definition{name = "autorotate", field_count = 1}
	definition.fields[0] = Field_Definition{name = "velocity", field_type = .Vec3}
	err := register_project_component(&registry, definition)
	testing.expect(t, err == "")

	scene_component := shared.Custom_Component{name = "autorotate"}
	append(&scene_component.vec3_fields, shared.Named_Vec3{name = "velocity"})
	defer delete(scene_component.vec3_fields)

	testing.expect(t, validate_custom_component(&registry, scene_component) == "")

	scene_component.vec3_fields[0].name = "speed"
	testing.expect(
		t,
		validate_custom_component(&registry, scene_component) ==
			`scene component "autorotate" has field "speed" that is not defined by scripts/main.luau`,
	)
}

@(test)
test_registry_rejects_unknown_namespaced_scene_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	scene_component := shared.Custom_Component{name = "scrappyphysics.rigidbody"}
	err := validate_custom_component(&registry, scene_component)
	testing.expect(t, err == `scene component "scrappyphysics.rigidbody" is not registered`)
}
