package main

import "core:strings"

ENGINE_NAMESPACE :: "scrapbot"

TRANSFORM_COMPONENT_ID :: "scrapbot.transform"
CUBE_RENDERER_COMPONENT_ID :: "scrapbot.render.cube"
GEOMETRY_PRIMITIVE_COMPONENT_ID :: "scrapbot.geometry.primitive"
SURFACE_MATERIAL_COMPONENT_ID :: "scrapbot.material.surface"
RENDERER_COMPONENT_ID :: "scrapbot.renderer"
CAMERA_COMPONENT_ID :: "scrapbot.camera"
DIRECTIONAL_LIGHT_COMPONENT_ID :: "scrapbot.light.directional"
SHADOW_CASTER_COMPONENT_ID :: "scrapbot.shadow.caster"
SHADOW_RECEIVER_COMPONENT_ID :: "scrapbot.shadow.receiver"
UI_CANVAS_COMPONENT_ID :: "scrapbot.ui.canvas"
UI_RECT_COMPONENT_ID :: "scrapbot.ui.rect"
UI_BORDER_COMPONENT_ID :: "scrapbot.ui.border"
UI_TEXT_COMPONENT_ID :: "scrapbot.ui.text"
UI_BUTTON_COMPONENT_ID :: "scrapbot.ui.button"
UI_HIT_AREA_COMPONENT_ID :: "scrapbot.ui.hit_area"
UI_COMMAND_COMPONENT_ID :: "scrapbot.ui.command"
UI_COMMAND_EVENT_COMPONENT_ID :: "scrapbot.ui.command_event"
UI_SCROLL_VIEW_COMPONENT_ID :: "scrapbot.ui.scroll_view"
UI_VGROUP_COMPONENT_ID :: "scrapbot.ui.vgroup"
UI_HGROUP_COMPONENT_ID :: "scrapbot.ui.hgroup"
UI_TABLE_COMPONENT_ID :: "scrapbot.ui.table"
UI_STACK_COMPONENT_ID :: "scrapbot.ui.stack"
UI_LAYOUT_ITEM_COMPONENT_ID :: "scrapbot.ui.layout.item"
UI_SPACER_COMPONENT_ID :: "scrapbot.ui.spacer"
UI_TEXT_BLOCK_COMPONENT_ID :: "scrapbot.ui.text_block"
UI_TOGGLE_COMPONENT_ID :: "scrapbot.ui.toggle"
UI_PROGRESS_BAR_COMPONENT_ID :: "scrapbot.ui.progress_bar"
UI_SEPARATOR_COMPONENT_ID :: "scrapbot.ui.separator"
INPUT_POINTER_COMPONENT_ID :: "scrapbot.input.pointer"
INPUT_KEYBOARD_COMPONENT_ID :: "scrapbot.input.keyboard"
INPUT_FRAME_COMPONENT_ID :: "scrapbot.input.frame"

Runtime_Error :: enum {
	None,
	Out_Of_Memory,
	Invalid_Type_ID,
	Reserved_Type_ID,
	Invalid_Field_Name,
	Duplicate_Component_Field,
	Duplicate_Component_Type,
	Duplicate_Entity_ID,
	Invalid_Entity,
}

Runtime_Field_Type :: enum {
	Boolean,
	Int,
	Float,
	Vec3,
	String,
}

Runtime_Component_Field_Definition :: struct {
	name:       string,
	value_type: Runtime_Field_Type,
}

Runtime_Component_Definition :: struct {
	id:      string,
	version: int,
	fields:  []Runtime_Component_Field_Definition,
}

Runtime_Component_Registry :: struct {
	components: [dynamic]Runtime_Component_Definition,
}

Runtime_Registration_Context :: enum {
	Engine,
	Project,
	Package,
}

Entity_Provenance :: enum {
	Spawned,
	Authored,
}

Entity_Handle :: struct {
	index:      u32,
	generation: u32,
}

Runtime_Entity :: struct {
	id:         string,
	name:       string,
	generation: u32,
	provenance: Entity_Provenance,
}

Runtime_World :: struct {
	entities:               [dynamic]Runtime_Entity,
	next_entity_generation: u32,
}

runtime_registry_free :: proc(registry: ^Runtime_Component_Registry) {
	for component in registry.components {
		runtime_component_definition_free(component)
	}
	if registry.components != nil {
		delete(registry.components)
	}
	registry.components = nil
}

runtime_registry_component_count :: proc(registry: Runtime_Component_Registry) -> int {
	return len(registry.components)
}

runtime_register_project_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Project, definition)
}

runtime_register_package_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Package, definition)
}

runtime_register_engine_component :: proc(registry: ^Runtime_Component_Registry, definition: Runtime_Component_Definition) -> Runtime_Error {
	return runtime_register_component_as(registry, .Engine, definition)
}

runtime_find_component :: proc(registry: Runtime_Component_Registry, id: string) -> (^Runtime_Component_Definition, bool) {
	for &component in registry.components {
		if component.id == id {
			return &component, true
		}
	}
	return nil, false
}

runtime_register_component_as :: proc(
	registry: ^Runtime_Component_Registry,
	registration_context: Runtime_Registration_Context,
	definition: Runtime_Component_Definition,
) -> Runtime_Error {
	id_err := runtime_validate_type_id_for_context(definition.id, registration_context)
	if id_err != .None {
		return id_err
	}

	for field, index in definition.fields {
		field_err := runtime_validate_field_name(field.name)
		if field_err != .None {
			return field_err
		}
		for prior_field in definition.fields[:index] {
			if prior_field.name == field.name {
				return .Duplicate_Component_Field
			}
		}
	}

	if existing, ok := runtime_find_component(registry^, definition.id); ok {
		if runtime_component_definitions_equal(existing^, definition) {
			return .None
		}
		return .Duplicate_Component_Type
	}

	owned, copy_err := runtime_component_definition_clone(definition)
	if copy_err != .None {
		return copy_err
	}
	append(&registry.components, owned)
	return .None
}

runtime_component_definition_clone :: proc(definition: Runtime_Component_Definition) -> (Runtime_Component_Definition, Runtime_Error) {
	owned_id, id_err := strings.clone(definition.id)
	if id_err != nil {
		return Runtime_Component_Definition{}, .Out_Of_Memory
	}

	owned_fields := make([]Runtime_Component_Field_Definition, len(definition.fields))
	if owned_fields == nil && len(definition.fields) > 0 {
		delete(owned_id)
		return Runtime_Component_Definition{}, .Out_Of_Memory
	}

	copied_count := 0
	for field, index in definition.fields {
		owned_name, name_err := strings.clone(field.name)
		if name_err != nil {
			for copied in owned_fields[:copied_count] {
				delete(copied.name)
			}
			delete(owned_fields)
			delete(owned_id)
			return Runtime_Component_Definition{}, .Out_Of_Memory
		}
		owned_fields[index] = Runtime_Component_Field_Definition{
			name = owned_name,
			value_type = field.value_type,
		}
		copied_count += 1
	}

	return Runtime_Component_Definition{
		id = owned_id,
		version = definition.version,
		fields = owned_fields,
	}, .None
}

runtime_component_definition_free :: proc(definition: Runtime_Component_Definition) {
	if definition.id != "" {
		delete(definition.id)
	}
	for field in definition.fields {
		delete(field.name)
	}
	if definition.fields != nil {
		delete(definition.fields)
	}
}

runtime_component_definitions_equal :: proc(left, right: Runtime_Component_Definition) -> bool {
	if left.id != right.id || left.version != right.version || len(left.fields) != len(right.fields) {
		return false
	}
	for field, index in left.fields {
		other := right.fields[index]
		if field.name != other.name || field.value_type != other.value_type {
			return false
		}
	}
	return true
}

runtime_register_engine_components :: proc(registry: ^Runtime_Component_Registry) -> Runtime_Error {
	err := runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = TRANSFORM_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "rotation", value_type = .Vec3},
			{name = "scale", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = CUBE_RENDERER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "color", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = GEOMETRY_PRIMITIVE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "primitive", value_type = .String},
			{name = "segments", value_type = .Int},
			{name = "rings", value_type = .Int},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = SURFACE_MATERIAL_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "base_color", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = RENDERER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "hdr", value_type = .Boolean},
			{name = "tone_mapping", value_type = .String},
			{name = "exposure", value_type = .Float},
			{name = "postprocess_enabled", value_type = .Boolean},
			{name = "antialiasing", value_type = .String},
			{name = "bloom_enabled", value_type = .Boolean},
			{name = "bloom_threshold", value_type = .Float},
			{name = "bloom_intensity", value_type = .Float},
			{name = "bloom_radius", value_type = .Float},
			{name = "vignette_enabled", value_type = .Boolean},
			{name = "vignette_strength", value_type = .Float},
			{name = "vignette_radius", value_type = .Float},
			{name = "chromatic_aberration_enabled", value_type = .Boolean},
			{name = "chromatic_aberration_strength", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = CAMERA_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "fov_y_degrees", value_type = .Float},
			{name = "near", value_type = .Float},
			{name = "far", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = DIRECTIONAL_LIGHT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "direction", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
			{name = "intensity", value_type = .Float},
			{name = "ambient", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = SHADOW_CASTER_COMPONENT_ID, version = 1})
	if err != .None do return err
	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = SHADOW_RECEIVER_COMPONENT_ID, version = 1})
	if err != .None do return err
	err = runtime_register_engine_component(registry, Runtime_Component_Definition{id = UI_BUTTON_COMPONENT_ID, version = 1})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_CANVAS_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "design_size", value_type = .Vec3},
			{name = "scale_mode", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_RECT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
			{name = "corner_radius", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_BORDER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "color", value_type = .Vec3},
			{name = "thickness", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TEXT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Float},
			{name = "color", value_type = .Vec3},
			{name = "value", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_HIT_AREA_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_COMMAND_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "command", value_type = .String}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_COMMAND_EVENT_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "command", value_type = .String},
			{name = "source", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SCROLL_VIEW_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "content_offset", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_VGROUP_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_HGROUP_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TABLE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "columns", value_type = .Int},
			{name = "row_height", value_type = .Float},
			{name = "column_gap", value_type = .Float},
			{name = "row_gap", value_type = .Float},
			{name = "padding", value_type = .Vec3},
			{name = "first_column_ratio", value_type = .Float},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_STACK_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "spacing", value_type = .Float},
			{name = "direction", value_type = .String},
			{name = "padding", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_LAYOUT_ITEM_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "parent", value_type = .String},
			{name = "order", value_type = .Int},
			{name = "min_size", value_type = .Vec3},
			{name = "preferred_size", value_type = .Vec3},
			{name = "max_size", value_type = .Vec3},
			{name = "grow", value_type = .Float},
			{name = "shrink", value_type = .Float},
			{name = "align", value_type = .String},
			{name = "margin", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SPACER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "size", value_type = .Vec3}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TEXT_BLOCK_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "size", value_type = .Vec3},
			{name = "horizontal_align", value_type = .String},
			{name = "vertical_align", value_type = .String},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_TOGGLE_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{{name = "checked", value_type = .Boolean}},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_PROGRESS_BAR_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "value", value_type = .Float},
			{name = "max", value_type = .Float},
			{name = "fill_color", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = UI_SEPARATOR_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "size", value_type = .Vec3},
			{name = "color", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_POINTER_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "position", value_type = .Vec3},
			{name = "delta", value_type = .Vec3},
			{name = "has_position", value_type = .Boolean},
			{name = "primary_down", value_type = .Boolean},
			{name = "primary_pressed", value_type = .Boolean},
			{name = "primary_released", value_type = .Boolean},
			{name = "secondary_down", value_type = .Boolean},
			{name = "secondary_pressed", value_type = .Boolean},
			{name = "secondary_released", value_type = .Boolean},
			{name = "wheel_delta", value_type = .Vec3},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_KEYBOARD_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "ctrl_down", value_type = .Boolean},
			{name = "shift_down", value_type = .Boolean},
			{name = "alt_down", value_type = .Boolean},
			{name = "super_down", value_type = .Boolean},
			{name = "move_forward", value_type = .Boolean},
			{name = "move_back", value_type = .Boolean},
			{name = "move_left", value_type = .Boolean},
			{name = "move_right", value_type = .Boolean},
			{name = "move_up", value_type = .Boolean},
			{name = "move_down", value_type = .Boolean},
			{name = "editor_toggle_pressed", value_type = .Boolean},
		},
	})
	if err != .None do return err

	err = runtime_register_engine_component(registry, Runtime_Component_Definition{
		id = INPUT_FRAME_COMPONENT_ID,
		version = 1,
		fields = []Runtime_Component_Field_Definition{
			{name = "ui_visible", value_type = .Boolean},
			{name = "debug_overlay_visible", value_type = .Boolean},
			{name = "viewport", value_type = .Vec3},
			{name = "pixel_scale", value_type = .Float},
		},
	})
	if err != .None do return err

	return .None
}

runtime_validate_type_id :: proc(id: string) -> Runtime_Error {
	_, err := runtime_validate_type_id_shape(id)
	return err
}

runtime_validate_project_type_id :: proc(id: string) -> Runtime_Error {
	err := runtime_validate_type_id(id)
	if err != .None {
		return err
	}
	if runtime_is_engine_type_id(id) {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_package_type_id :: proc(id: string) -> Runtime_Error {
	segment_count, err := runtime_validate_type_id_shape(id)
	if err != .None {
		return err
	}
	if segment_count < 2 {
		return .Invalid_Type_ID
	}
	if runtime_is_engine_type_id(id) {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_engine_type_id :: proc(id: string) -> Runtime_Error {
	err := runtime_validate_type_id(id)
	if err != .None {
		return err
	}
	if !strings.has_prefix(id, ENGINE_NAMESPACE + ".") {
		return .Reserved_Type_ID
	}
	return .None
}

runtime_validate_type_id_for_context :: proc(id: string, registration_context: Runtime_Registration_Context) -> Runtime_Error {
	switch registration_context {
	case .Engine:
		return runtime_validate_engine_type_id(id)
	case .Project:
		return runtime_validate_project_type_id(id)
	case .Package:
		return runtime_validate_package_type_id(id)
	}
	return .Invalid_Type_ID
}

runtime_validate_field_name :: proc(name: string) -> Runtime_Error {
	err := runtime_validate_identifier_segment(name)
	if err != .None {
		return .Invalid_Field_Name
	}
	return .None
}

runtime_validate_type_id_shape :: proc(id: string) -> (int, Runtime_Error) {
	segment_count := 0
	remaining := id
	for segment in strings.split_iterator(&remaining, ".") {
		err := runtime_validate_identifier_segment(segment)
		if err != .None {
			return 0, err
		}
		segment_count += 1
	}
	if segment_count == 0 {
		return 0, .Invalid_Type_ID
	}
	return segment_count, .None
}

runtime_validate_identifier_segment :: proc(segment: string) -> Runtime_Error {
	if segment == "" || !runtime_is_lower_alpha(segment[0]) {
		return .Invalid_Type_ID
	}
	for index := 1; index < len(segment); index += 1 {
		byte := segment[index]
		if !runtime_is_lower_alpha(byte) && !(byte >= '0' && byte <= '9') && byte != '_' {
			return .Invalid_Type_ID
		}
	}
	return .None
}

runtime_is_engine_type_id :: proc(id: string) -> bool {
	return id == ENGINE_NAMESPACE || strings.has_prefix(id, ENGINE_NAMESPACE + ".")
}

runtime_is_lower_alpha :: proc(byte: u8) -> bool {
	return byte >= 'a' && byte <= 'z'
}

runtime_world_init :: proc() -> Runtime_World {
	return Runtime_World{next_entity_generation = 1}
}

runtime_world_free :: proc(world: ^Runtime_World) {
	for entity in world.entities {
		delete(entity.id)
		delete(entity.name)
	}
	if world.entities != nil {
		delete(world.entities)
	}
	world.entities = nil
	world.next_entity_generation = 1
}

runtime_world_entity_count :: proc(world: Runtime_World) -> int {
	return len(world.entities)
}

runtime_world_create_entity :: proc(world: ^Runtime_World, id, name: string) -> (Entity_Handle, Runtime_Error) {
	return runtime_world_create_entity_with_provenance(world, id, name, .Spawned)
}

runtime_world_create_authored_entity :: proc(world: ^Runtime_World, id, name: string) -> (Entity_Handle, Runtime_Error) {
	return runtime_world_create_entity_with_provenance(world, id, name, .Authored)
}

runtime_world_create_entity_with_provenance :: proc(
	world: ^Runtime_World,
	id, name: string,
	provenance: Entity_Provenance,
) -> (Entity_Handle, Runtime_Error) {
	if _, ok := runtime_world_find_entity_by_id(world^, id); ok {
		return Entity_Handle{}, .Duplicate_Entity_ID
	}

	owned_id, id_err := strings.clone(id)
	if id_err != nil {
		return Entity_Handle{}, .Out_Of_Memory
	}
	owned_name, name_err := strings.clone(name)
	if name_err != nil {
		delete(owned_id)
		return Entity_Handle{}, .Out_Of_Memory
	}

	generation := runtime_world_next_entity_generation(world)
	handle := Entity_Handle{index = u32(len(world.entities)), generation = generation}
	append(&world.entities, Runtime_Entity{
		id = owned_id,
		name = owned_name,
		generation = generation,
		provenance = provenance,
	})
	return handle, .None
}

runtime_world_entity :: proc(world: Runtime_World, handle: Entity_Handle) -> (Runtime_Entity, Runtime_Error) {
	index := int(handle.index)
	if index < 0 || index >= len(world.entities) {
		return Runtime_Entity{}, .Invalid_Entity
	}
	entity := world.entities[index]
	if handle.generation != 0 && entity.generation != handle.generation {
		return Runtime_Entity{}, .Invalid_Entity
	}
	return entity, .None
}

runtime_world_find_entity_by_id :: proc(world: Runtime_World, id: string) -> (Entity_Handle, bool) {
	for entity, index in world.entities {
		if entity.id == id {
			return Entity_Handle{index = u32(index), generation = entity.generation}, true
		}
	}
	return Entity_Handle{}, false
}

runtime_world_remove_entity :: proc(world: ^Runtime_World, handle: Entity_Handle) -> Runtime_Error {
	index := int(handle.index)
	if _, err := runtime_world_entity(world^, handle); err != .None {
		return err
	}

	last_index := len(world.entities) - 1
	delete(world.entities[index].id)
	delete(world.entities[index].name)
	if index != last_index {
		world.entities[index] = world.entities[last_index]
	}
	pop(&world.entities)
	return .None
}

runtime_world_next_entity_generation :: proc(world: ^Runtime_World) -> u32 {
	generation := world.next_entity_generation
	world.next_entity_generation += 1
	if world.next_entity_generation == 0 {
		world.next_entity_generation = 1
	}
	return generation
}
