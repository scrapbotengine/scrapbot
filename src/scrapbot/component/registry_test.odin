package component

import "core:testing"
import "core:strings"
import shared "../shared"

@(test)
test_registry_contains_engine_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	transform, transform_ok := find_definition(&registry, "scrapbot.transform")
	testing.expect(t, transform_ok)
	testing.expect(t, transform.id != shared.INVALID_COMPONENT_ID)
	testing.expect(t, transform.owner == .Engine)
	testing.expect(t, transform.field_count == 3)

	camera, camera_ok := find_definition(&registry, "scrapbot.camera")
	testing.expect(t, camera_ok)
	testing.expect(t, camera.id != transform.id)
	mesh, mesh_ok := find_definition(&registry, "scrapbot.mesh")
	testing.expect(t, mesh_ok)
	testing.expect(t, mesh.id != camera.id)
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
	testing.expect(t, autorotate.id != shared.INVALID_COMPONENT_ID)
	by_id, by_id_ok := find_definition_by_id(&registry, autorotate.id)
	testing.expect(t, by_id_ok)
	testing.expect(t, by_id.name == "autorotate")

	err = register_project_component(&registry, Definition{name = "autorotate", field_count = 1})
	testing.expect(t, err == "")
	updated, updated_ok := find_definition(&registry, "autorotate")
	testing.expect(t, updated_ok)
	testing.expect(t, updated.id == autorotate.id)
	testing.expect(t, updated.field_count == 1)
}

@(test)
test_registry_registers_library_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	err := register_library_component(&registry, Definition{name = "rigidbody"})
	testing.expect(t, err == "library components must use dotted component names")

	err = register_library_component(&registry, Definition{name = "scrapbot.physics"})
	testing.expect(t, err == "library components cannot use the scrapbot namespace")

	err = register_library_component(&registry, Definition{name = "scrapbot.transform"})
	testing.expect(t, err == "library components cannot use the scrapbot namespace")

	definition := Definition{name = "scrappyphysics.rigidbody", field_count = 1}
	definition.fields[0] = Field_Definition{name = "velocity", field_type = .Vec3}
	err = register_library_component(&registry, definition)
	testing.expect(t, err == "")

	rigidbody, rigidbody_ok := find_definition(&registry, "scrappyphysics.rigidbody")
	testing.expect(t, rigidbody_ok)
	testing.expect(t, rigidbody.owner == .Library)
	testing.expect(t, rigidbody.id != shared.INVALID_COMPONENT_ID)
	testing.expect(t, rigidbody.field_count == 1)

	err = register_project_component(&registry, Definition{name = "scrappyphysics.rigidbody"})
	testing.expect(t, err == "project scripts can only define single-token project component names")
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
test_registry_validates_library_scene_component_fields :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	definition := Definition{name = "scrappyphysics.rigidbody", field_count = 1}
	definition.fields[0] = Field_Definition{name = "velocity", field_type = .Vec3}
	err := register_library_component(&registry, definition)
	testing.expect(t, err == "")

	scene_component := shared.Custom_Component{name = "scrappyphysics.rigidbody"}
	append(&scene_component.vec3_fields, shared.Named_Vec3{name = "velocity"})
	defer delete(scene_component.vec3_fields)

	testing.expect(t, validate_custom_component(&registry, scene_component) == "")

	scene_component.vec3_fields[0].name = "mass"
	testing.expect(
		t,
		validate_custom_component(&registry, scene_component) ==
			`scene component "scrappyphysics.rigidbody" has field "mass" that is not defined by its registered schema`,
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

@(test)
test_luau_types_include_registered_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	definition := Definition{name = "autorotate", field_count = 1}
	definition.fields[0] = Field_Definition{name = "velocity", field_type = .Vec3}
	err := register_project_component(&registry, definition)
	testing.expect(t, err == "")
	library_definition := Definition{name = "scrappyphysics.rigidbody", field_count = 1}
	library_definition.fields[0] = Field_Definition{name = "velocity", field_type = .Vec3}
	library_err := register_library_component(&registry, library_definition)
	testing.expect(t, library_err == "")

	text, generate_err := generate_luau_types(&registry)
	testing.expect(t, generate_err == "")
	defer delete(text)

	testing.expect(t, strings.contains(text, "export type ScrapbotTransform = {"))
	testing.expect(t, strings.contains(text, "vec3: ScrapbotComponentField<Vec3, ReadonlyVec3>,"))
	testing.expect(t, strings.contains(text, "\tposition: Vec3,"))
	testing.expect(t, strings.contains(text, "export type ReadonlyScrapbotTransform = {"))
	testing.expect(t, strings.contains(text, "\tread position: ReadonlyVec3,"))
	testing.expect(t, strings.contains(text, "export type Autorotate = {"))
	testing.expect(t, strings.contains(text, "\tvelocity: Vec3,"))
	testing.expect(t, strings.contains(text, "export type ReadonlyAutorotate = {"))
	testing.expect(t, strings.contains(text, "\tread velocity: ReadonlyVec3,"))
	testing.expect(t, strings.contains(text, "export type AutorotateComponent = ScrapbotComponent<Autorotate, ReadonlyAutorotate>"))
	testing.expect(t, strings.contains(text, "library_component: <T>(name: string, schema: ScrapbotComponentSchema) -> ScrapbotComponent<T, T>,"))
	testing.expect(t, strings.contains(text, "export type ScrappyphysicsRigidbody = {"))
	testing.expect(t, strings.contains(text, "export type ScrappyphysicsRigidbodyComponent = ScrapbotComponent<ScrappyphysicsRigidbody, ReadonlyScrappyphysicsRigidbody>"))
	testing.expect(t, strings.contains(text, "export type ScrapbotQuery2<A, RA, B, RB> = {"))
	testing.expect(t, strings.contains(text, "\t_arity: \"2\","))
	testing.expect(t, strings.contains(text, "\t_read_type_a: RA?,"))
	testing.expect(t, strings.contains(text, "\t_read_type_b: RB?,"))
	testing.expect(t, strings.contains(text, "((query: ScrapbotQuery1<any, any>, system: (delta_seconds: number, entity: ScrapbotEntity, component: any) -> ()) -> ())"))
	testing.expect(t, strings.contains(text, "callback: (ScrapbotEntity, RA, RB) -> ()) -> (),"))
	testing.expect(t, strings.contains(text, "<A, RA, B, RB>(first: ScrapbotComponent<A, RA>, second: ScrapbotComponent<B, RB>) -> ScrapbotQuery2<A, RA, B, RB>"))
	testing.expect(t, !strings.contains(text, "query3:"))
}

@(test)
test_luau_component_type_names_use_pascal_case_tokens :: proc(t: ^testing.T) {
	name := luau_component_type_name("scrappyphysics.rigid_body")
	defer delete(name)
	testing.expect(t, name == "ScrappyphysicsRigidBody")
}
