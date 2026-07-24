package component

import shared "../shared"
import "core:reflect"
import "core:strings"
import "core:testing"

@(test)
test_registry_contains_engine_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	transform, transform_ok := find_definition(&registry, "scrapbot.transform")
	testing.expect(t, transform_ok)
	testing.expect(t, transform.id != shared.INVALID_COMPONENT_ID)
	testing.expect(t, transform.owner == .Engine)
	testing.expect(t, transform.storage_kind == .Transform)
	testing.expect(t, definition_is_authorable(transform))
	testing.expect(t, transform.field_count == 4)
	testing.expect(t, transform.fields[0].name == "parent")
	testing.expect(t, transform.name_token_count == 2)
	testing.expect(t, transform.name_tokens[0] == "scrapbot")
	testing.expect(t, transform.name_tokens[1] == "transform")

	camera, camera_ok := find_definition(&registry, "scrapbot.camera")
	testing.expect(t, camera_ok)
	testing.expect(t, camera.id != transform.id)
	testing.expect(t, camera.field_count == 9)
	testing.expect(t, camera.fields[4].name == "temporal_antialiasing")
	testing.expect(t, camera.fields[7].name == "screen_space_reflections")
	testing.expect(t, camera.fields[8].name == "bloom")
	fog, fog_ok := find_definition(&registry, "scrapbot.volumetric_fog")
	testing.expect(t, fog_ok)
	testing.expect(t, fog.storage_kind == .Custom)
	testing.expect(t, definition_is_authorable(fog))
	testing.expect(t, fog.field_count == 8)
	testing.expect(t, fog.fields[0].name == "color")
	testing.expect(t, fog.fields[1].name == "density")
	testing.expect(t, fog.fields[5].name == "anisotropy")
	mesh, mesh_ok := find_definition(&registry, "scrapbot.mesh")
	testing.expect(t, mesh_ok)
	testing.expect(t, mesh.id != camera.id)
	ui_state, ui_state_ok := find_definition(&registry, "scrapbot.ui_state")
	render_instance, render_instance_ok := find_definition(
		&registry,
		"scrapbot.internal.render_instance",
	)
	testing.expect(t, ui_state_ok && render_instance_ok)
	testing.expect(t, ui_state.storage_kind == .UI_State)
	testing.expect(t, !definition_is_authorable(ui_state))
	testing.expect(t, render_instance.storage_kind == .Render_Instance)
	testing.expect(t, !definition_is_authorable(render_instance))
	gizmo, gizmo_ok := find_definition(&registry, "scrapbot.internal.editor_transform_gizmo")
	testing.expect(t, gizmo_ok)
	testing.expect(t, gizmo.storage_kind == .Editor_Transform_Gizmo)
	testing.expect(t, !definition_is_authorable(gizmo))
	keyboard, keyboard_ok := find_definition(&registry, "scrapbot.keyboard_input")
	pointer, pointer_ok := find_definition(&registry, "scrapbot.pointer_input")
	testing.expect(t, keyboard_ok && pointer_ok)
	testing.expect(t, keyboard.storage_kind == .Keyboard_Input)
	testing.expect(t, pointer.storage_kind == .Pointer_Input)
	testing.expect(t, !definition_is_authorable(keyboard) && !definition_is_authorable(pointer))
}

@(test)
test_registry_revision_changes_with_definition_updates :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	initial_revision := registry.revision
	testing.expect(t, initial_revision == u64(registry.definition_count))
	testing.expect(t, register_project_component(&registry, {name = "health"}) == "")
	testing.expect(t, registry.revision == initial_revision + 1)
	testing.expect(t, register_project_component(&registry, {name = "health"}) == "")
	testing.expect(t, registry.revision == initial_revision + 2)
}

@(test)
test_registry_preserves_advanced_component_presentation_metadata :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	testing.expect(
		t,
		register_project_component(&registry, {name = "simulation_state", advanced = true}) == "",
	)
	definition, found := find_definition(&registry, "simulation_state")
	testing.expect(t, found)
	testing.expect(t, definition.advanced)

	testing.expect(
		t,
		register_project_component(&registry, {name = "simulation_state", advanced = false}) == "",
	)
	definition, found = find_definition(&registry, "simulation_state")
	testing.expect(t, found)
	testing.expect(t, !definition.advanced)
}

@(test)
test_public_ui_registry_fields_exactly_match_component_structs :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	cases := [?]struct {
		name: string,
		component_type: typeid,
	} {
		{"scrapbot.ui_layout", shared.UI_Layout_Component},
		{"scrapbot.ui_hstack", shared.UI_Stack_Component},
		{"scrapbot.ui_vstack", shared.UI_Stack_Component},
		{"scrapbot.ui_scroll_area", shared.UI_Scroll_Area_Component},
		{"scrapbot.ui_panel", shared.UI_Panel_Component},
		{"scrapbot.ui_table", shared.UI_Table_Component},
		{"scrapbot.ui_list", shared.UI_List_Component},
		{"scrapbot.ui_progress", shared.UI_Progress_Component},
		{"scrapbot.ui_state", shared.UI_State_Component},
		{"scrapbot.ui_text", shared.UI_Text_Component},
		{"scrapbot.ui_button", shared.UI_Button_Component},
		{"scrapbot.ui_input", shared.UI_Input_Component},
		{"scrapbot.ui_checkbox", shared.UI_Checkbox_Component},
	}
	for schema in cases {
		definition, found := find_definition(&registry, schema.name)
		testing.expectf(t, found, "%s is missing from the registry", schema.name)
		if !found {
			continue
		}
		names := reflect.struct_field_names(schema.component_type)
		testing.expectf(
			t,
			definition.field_count == len(names),
			"%s exposes %d of %d struct fields",
			schema.name,
			definition.field_count,
			len(names),
		)
		if definition.field_count != len(names) {
			continue
		}
		for name, index in names {
			testing.expectf(
				t,
				definition.fields[index].name == name,
				"%s field %d is %s, expected %s",
				schema.name,
				index,
				definition.fields[index].name,
				name,
			)
		}
	}
}

@(test)
test_registry_rejects_project_component_name_collisions :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	err := register_project_component(&registry, Definition{name = "scrapbot.transform"})
	testing.expect(
		t,
		err == "project scripts can only define single-token project component names",
	)

	err = register_project_component(&registry, Definition{name = "autorotate"})
	testing.expect(t, err == "")
	autorotate, autorotate_ok := find_definition(&registry, "autorotate")
	testing.expect(t, autorotate_ok)
	testing.expect(t, autorotate.owner == .Project)
	testing.expect(t, autorotate.storage_kind == .Custom)
	testing.expect(t, definition_is_authorable(autorotate))
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

	definition := Definition {
		name = "scrappyphysics.rigidbody",
		field_count = 1,
	}
	definition.fields[0] = Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
	err = register_library_component(&registry, definition)
	testing.expect(t, err == "")

	rigidbody, rigidbody_ok := find_definition(&registry, "scrappyphysics.rigidbody")
	testing.expect(t, rigidbody_ok)
	testing.expect(t, rigidbody.owner == .Library)
	testing.expect(t, rigidbody.storage_kind == .Custom)
	testing.expect(t, definition_is_authorable(rigidbody))
	testing.expect(t, rigidbody.id != shared.INVALID_COMPONENT_ID)
	testing.expect(t, rigidbody.field_count == 1)

	err = register_project_component(&registry, Definition{name = "scrappyphysics.rigidbody"})
	testing.expect(
		t,
		err == "project scripts can only define single-token project component names",
	)
}

@(test)
test_registry_validates_scene_component_fields :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)

	definition := Definition {
		name = "autorotate",
		field_count = 1,
	}
	definition.fields[0] = Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
	err := register_project_component(&registry, definition)
	testing.expect(t, err == "")

	scene_component := shared.Custom_Component {
		name = "autorotate",
	}
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

	definition := Definition {
		name = "scrappyphysics.rigidbody",
		field_count = 1,
	}
	definition.fields[0] = Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
	err := register_library_component(&registry, definition)
	testing.expect(t, err == "")

	scene_component := shared.Custom_Component {
		name = "scrappyphysics.rigidbody",
	}
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

	scene_component := shared.Custom_Component {
		name = "scrappyphysics.rigidbody",
	}
	err := validate_custom_component(&registry, scene_component)
	testing.expect(t, err == `scene component "scrappyphysics.rigidbody" is not registered`)
}

@(test)
test_luau_types_include_registered_components :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	definition := Definition {
		name = "autorotate",
		field_count = 1,
	}
	definition.fields[0] = Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
	err := register_project_component(&registry, definition)
	testing.expect(t, err == "")
	library_definition := Definition {
		name = "scrappyphysics.rigidbody",
		field_count = 1,
	}
	library_definition.fields[0] = Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
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
	testing.expect(
		t,
		strings.contains(
			text,
			"export type AutorotateComponent = ScrapbotComponent<Autorotate, ReadonlyAutorotate>",
		),
	)
	testing.expect(
		t,
		strings.contains(
			text,
			"library_component: <T>(name: string, schema: ScrapbotComponentSchema, options: ScrapbotComponentOptions?) -> ScrapbotComponent<T, T>,",
		),
	)
	testing.expect(t, strings.contains(text, "export type ScrappyphysicsRigidbody = {"))
	testing.expect(
		t,
		strings.contains(
			text,
			"export type ScrappyphysicsRigidbodyComponent = ScrapbotComponent<ScrappyphysicsRigidbody, ReadonlyScrappyphysicsRigidbody>",
		),
	)
	testing.expect(t, strings.contains(text, "export type ScrapbotQuery2<A, RA, B, RB> = {"))
	testing.expect(t, strings.contains(text, "\t_arity: \"2\","))
	testing.expect(t, strings.contains(text, "\t_read_type_a: RA?,"))
	testing.expect(t, strings.contains(text, "\t_read_type_b: RB?,"))
	testing.expect(t, strings.contains(text, "\tsystem: (...any) -> (),"))
	testing.expect(t, strings.contains(text, "callback: (ScrapbotEntity, RA, RB) -> ()) -> (),"))
	testing.expect(
		t,
		strings.contains(
			text,
			"<A, RA, B, RB>(first: ScrapbotComponent<A, RA>, second: ScrapbotComponent<B, RB>) -> ScrapbotQuery2<A, RA, B, RB>",
		),
	)
	testing.expect(
		t,
		strings.contains(text, "<A, RA>(query: ScrapbotQuery1<A, RA>) -> {ScrapbotQueryItem<RA>}"),
	)
	testing.expect(t, !strings.contains(text, "query3:"))
}

@(test)
test_luau_component_type_names_use_pascal_case_tokens :: proc(t: ^testing.T) {
	name := luau_component_type_name("scrappyphysics.rigid_body")
	defer delete(name)
	testing.expect(t, name == "ScrappyphysicsRigidBody")
}
