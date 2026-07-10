package component

import "core:fmt"
import shared "../shared"

MAX_COMPONENTS :: 128
MAX_COMPONENT_FIELDS :: 16

Custom_Component :: shared.Custom_Component

Owner :: enum {
	Engine,
	Project,
}

Field_Type :: enum {
	Vec3,
}

Field_Definition :: struct {
	name: string,
	field_type: Field_Type,
}

Definition :: struct {
	name: string,
	owner: Owner,
	fields: [MAX_COMPONENT_FIELDS]Field_Definition,
	field_count: int,
}

Registry :: struct {
	definitions: [MAX_COMPONENTS]Definition,
	definition_count: int,
}

init_registry :: proc(registry: ^Registry) {
	registry^ = {}

	register_engine_component(
		registry,
		"scrapbot.transform",
		{
			Field_Definition{name = "position", field_type = .Vec3},
			Field_Definition{name = "rotation", field_type = .Vec3},
			Field_Definition{name = "scale", field_type = .Vec3},
		},
	)
	register_engine_component(registry, "scrapbot.camera", {})
	register_engine_component(registry, "scrapbot.mesh", {})
}

register_engine_component :: proc(registry: ^Registry, name: string, fields: []Field_Definition) -> string {
	definition := Definition{name = name, owner = .Engine}
	if err := copy_fields(&definition, fields); err != "" {
		return err
	}
	return register_definition(registry, definition)
}

register_project_component :: proc "c" (registry: ^Registry, definition: Definition) -> string {
	if !shared.component_name_is_valid(definition.name) {
		return "component name must be dot-separated identifier tokens"
	}
	if !shared.component_name_is_project_level(definition.name) {
		return "project scripts can only define single-token project component names"
	}

	project_definition := definition
	project_definition.owner = .Project
	return register_definition(registry, project_definition)
}

register_definition :: proc "c" (registry: ^Registry, definition: Definition) -> string {
	if registry == nil {
		return "component registry is not available"
	}
	if !shared.component_name_is_valid(definition.name) {
		return "component name must be dot-separated identifier tokens"
	}

	if index, found := find_definition_index(registry, definition.name); found {
		existing := registry.definitions[index]
		if existing.owner != definition.owner {
			return "component is already registered"
		}
		registry.definitions[index] = definition
		return ""
	}

	if registry.definition_count >= MAX_COMPONENTS {
		return "too many component definitions"
	}

	registry.definitions[registry.definition_count] = definition
	registry.definition_count += 1
	return ""
}

find_definition :: proc "c" (registry: ^Registry, name: string) -> (definition: Definition, ok: bool) {
	index, found := find_definition_index(registry, name)
	if !found {
		return {}, false
	}
	return registry.definitions[index], true
}

find_definition_index :: proc "c" (registry: ^Registry, name: string) -> (index: int, ok: bool) {
	if registry == nil {
		return -1, false
	}
	for definition, i in registry.definitions[:registry.definition_count] {
		if definition.name == name {
			return i, true
		}
	}
	return -1, false
}

validate_custom_component :: proc(registry: ^Registry, scene_component: Custom_Component) -> string {
	definition, found := find_definition(registry, scene_component.name)
	if !found {
		if shared.component_name_is_project_level(scene_component.name) {
			return fmt.tprintf(
				`scene component "%s" is not defined by scripts/main.luau; add scrapbot.component("%s", schema)`,
				scene_component.name,
				scene_component.name,
			)
		}
		return fmt.tprintf(`scene component "%s" is not registered`, scene_component.name)
	}

	for field in scene_component.vec3_fields {
		field_definition, field_ok := lookup_field_definition(definition, field.name)
		if !field_ok {
			if definition.owner == .Project {
				return fmt.tprintf(
					`scene component "%s" has field "%s" that is not defined by scripts/main.luau`,
					scene_component.name,
					field.name,
				)
			}
			return fmt.tprintf(
				`scene component "%s" has field "%s" that is not defined by its registered schema`,
				scene_component.name,
				field.name,
			)
		}
		if field_definition.field_type != .Vec3 {
			return fmt.tprintf(
				`scene component "%s" field "%s" does not accept vec3 values`,
				scene_component.name,
				field.name,
			)
		}
	}

	return ""
}

lookup_field_definition :: proc(definition: Definition, name: string) -> (field: Field_Definition, ok: bool) {
	for i in 0..<definition.field_count {
		definition_field := definition.fields[i]
		if definition_field.name == name {
			return definition_field, true
		}
	}
	return {}, false
}

copy_fields :: proc(definition: ^Definition, fields: []Field_Definition) -> string {
	if len(fields) > MAX_COMPONENT_FIELDS {
		return "too many fields in component definition"
	}
	definition.field_count = len(fields)
	for field, i in fields {
		definition.fields[i] = field
	}
	return ""
}
