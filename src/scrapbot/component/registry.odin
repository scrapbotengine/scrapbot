package component

import shared "../shared"
import "core:fmt"

MAX_COMPONENTS :: 128
MAX_COMPONENT_FIELDS :: 32
MAX_COMPONENT_NAME_TOKENS :: 16

Custom_Component :: shared.Custom_Component
Component_ID :: shared.Component_ID

Owner :: enum {
	Engine,
	Library,
	Project,
}

Field_Type :: enum {
	Bool,
	String,
	Vec2,
	Vec3,
	Vec4,
	Number,
}

Storage_Kind :: enum {
	Custom,
	Transform,
	Camera,
	Ambient_Light,
	Directional_Light,
	Point_Light,
	Mesh,
	Geometry,
	Material,
	Shadow_Caster,
	Shadow_Receiver,
	UI_Layout,
	UI_HStack,
	UI_VStack,
	UI_Scroll_Area,
	UI_Panel,
	UI_Table,
	UI_List,
	UI_Progress,
	UI_Text,
	UI_Button,
	UI_Input,
	UI_Checkbox,
	UI_State,
	Derived,
}

Lifecycle :: enum {
	Authored,
	Derived,
}

Field_Definition :: struct {
	name: string,
	field_type: Field_Type,
}

Definition :: struct {
	id: Component_ID,
	name: string,
	owner: Owner,
	storage_kind: Storage_Kind,
	lifecycle: Lifecycle,
	fields: [MAX_COMPONENT_FIELDS]Field_Definition,
	field_count: int,
	name_tokens: [MAX_COMPONENT_NAME_TOKENS]string,
	name_token_count: int,
}

Registry :: struct {
	definitions: [MAX_COMPONENTS]Definition,
	definition_count: int,
	revision: u64,
}

init_registry :: proc(registry: ^Registry) {
	registry^ = {}

	register_engine_component(
		registry,
		"scrapbot.transform",
		{
			Field_Definition{name = "parent", field_type = .String},
			Field_Definition{name = "position", field_type = .Vec3},
			Field_Definition{name = "rotation", field_type = .Vec3},
			Field_Definition{name = "scale", field_type = .Vec3},
		},
	)
	register_engine_component(registry, "scrapbot.camera", {})
	register_engine_component(
		registry,
		"scrapbot.ambient_light",
		{
			Field_Definition{name = "color", field_type = .Vec3},
			Field_Definition{name = "intensity", field_type = .Number},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.directional_light",
		{
			Field_Definition{name = "direction", field_type = .Vec3},
			Field_Definition{name = "color", field_type = .Vec3},
			Field_Definition{name = "intensity", field_type = .Number},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.point_light",
		{
			Field_Definition{name = "color", field_type = .Vec3},
			Field_Definition{name = "intensity", field_type = .Number},
			Field_Definition{name = "range", field_type = .Number},
		},
	)
	register_engine_component(registry, "scrapbot.mesh", {})
	register_engine_component(registry, "scrapbot.geometry", {})
	register_engine_component(registry, "scrapbot.material", {})
	register_engine_component(registry, "scrapbot.shadow_caster", {})
	register_engine_component(registry, "scrapbot.shadow_receiver", {})
	register_engine_component(
		registry,
		"scrapbot.ui_layout",
		{
			Field_Definition{name = "parent", field_type = .String},
			Field_Definition{name = "position", field_type = .Vec2},
			Field_Definition{name = "size", field_type = .Vec2},
			Field_Definition{name = "min_size", field_type = .Vec2},
			Field_Definition{name = "margin", field_type = .Vec4},
			Field_Definition{name = "padding", field_type = .Vec4},
			Field_Definition{name = "background", field_type = .Vec4},
			Field_Definition{name = "border_color", field_type = .Vec4},
			Field_Definition{name = "border_width", field_type = .Number},
			Field_Definition{name = "corner_radius", field_type = .Number},
			Field_Definition{name = "hidden", field_type = .Bool},
			Field_Definition{name = "fill_width", field_type = .Bool},
			Field_Definition{name = "fill_height", field_type = .Bool},
			Field_Definition{name = "fit_content_width", field_type = .Bool},
			Field_Definition{name = "fit_content_height", field_type = .Bool},
			Field_Definition{name = "fixed_in_fill", field_type = .Bool},
			Field_Definition{name = "tree_item", field_type = .Bool},
			Field_Definition{name = "tree_parent", field_type = .String},
			Field_Definition{name = "tree_order", field_type = .Number},
			Field_Definition{name = "tree_collapsed", field_type = .Bool},
		},
	)
	stack_fields := [?]Field_Definition {
		{name = "gap", field_type = .Number},
		{name = "fill", field_type = .Bool},
		{name = "draggable", field_type = .Bool},
		{name = "min_size", field_type = .Number},
	}
	register_engine_component(registry, "scrapbot.ui_hstack", stack_fields[:])
	register_engine_component(registry, "scrapbot.ui_vstack", stack_fields[:])
	register_engine_component(
		registry,
		"scrapbot.ui_scroll_area",
		{
			Field_Definition{name = "scroll_speed", field_type = .Number},
			Field_Definition{name = "smoothness", field_type = .Number},
			Field_Definition{name = "scrollbar_width", field_type = .Number},
			Field_Definition{name = "scrollbar_right", field_type = .Number},
			Field_Definition{name = "scrollbar_vertical_inset", field_type = .Number},
			Field_Definition{name = "minimum_thumb_size", field_type = .Number},
			Field_Definition{name = "scrollbar_corner_radius", field_type = .Number},
			Field_Definition{name = "scrollbar_track_color", field_type = .Vec4},
			Field_Definition{name = "scrollbar_thumb_color", field_type = .Vec4},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_panel",
		{
			Field_Definition{name = "title", field_type = .String},
			Field_Definition{name = "font", field_type = .String},
			Field_Definition{name = "title_color", field_type = .Vec4},
			Field_Definition{name = "title_background", field_type = .Vec4},
			Field_Definition{name = "title_size", field_type = .Number},
			Field_Definition{name = "title_height", field_type = .Number},
			Field_Definition{name = "disclosure_size", field_type = .Number},
			Field_Definition{name = "disclosure_margin", field_type = .Number},
			Field_Definition{name = "disclosure_gap", field_type = .Number},
			Field_Definition{name = "disclosure_corner_radius", field_type = .Number},
			Field_Definition{name = "collapsible", field_type = .Bool},
			Field_Definition{name = "collapsed", field_type = .Bool},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_table",
		{
			Field_Definition{name = "columns", field_type = .Number},
			Field_Definition{name = "column_gap", field_type = .Number},
			Field_Definition{name = "row_gap", field_type = .Number},
			Field_Definition{name = "proportional_columns", field_type = .Bool},
			Field_Definition{name = "resizable_columns", field_type = .Bool},
			Field_Definition{name = "min_column_width", field_type = .Number},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_list",
		{
			Field_Definition{name = "selected", field_type = .String},
			Field_Definition{name = "gap", field_type = .Number},
			Field_Definition{name = "selection_background", field_type = .Vec4},
			Field_Definition{name = "hover_background", field_type = .Vec4},
			Field_Definition{name = "active_background", field_type = .Vec4},
			Field_Definition{name = "draggable", field_type = .Bool},
			Field_Definition{name = "drag_threshold", field_type = .Number},
			Field_Definition{name = "drop_edge_fraction", field_type = .Number},
			Field_Definition{name = "drop_target_background", field_type = .Vec4},
			Field_Definition{name = "drop_indicator_color", field_type = .Vec4},
			Field_Definition{name = "drop_indicator_thickness", field_type = .Number},
			Field_Definition{name = "drop_indicator_inset", field_type = .Number},
			Field_Definition{name = "tree_enabled", field_type = .Bool},
			Field_Definition{name = "tree_indent", field_type = .Number},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_text",
		{
			Field_Definition{name = "text", field_type = .String},
			Field_Definition{name = "font", field_type = .String},
			Field_Definition{name = "color", field_type = .Vec4},
			Field_Definition{name = "size", field_type = .Number},
			Field_Definition{name = "alignment", field_type = .String},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_progress",
		{
			Field_Definition{name = "value", field_type = .Number},
			Field_Definition{name = "maximum", field_type = .Number},
			Field_Definition{name = "fill_color", field_type = .Vec4},
			Field_Definition{name = "background_color", field_type = .Vec4},
			Field_Definition{name = "inset", field_type = .Vec4},
			Field_Definition{name = "corner_radius", field_type = .Number},
			Field_Definition{name = "right_to_left", field_type = .Bool},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_state",
		{
			Field_Definition{name = "hovered", field_type = .Bool},
			Field_Definition{name = "active", field_type = .Bool},
			Field_Definition{name = "focused", field_type = .Bool},
			Field_Definition{name = "activated", field_type = .Bool},
			Field_Definition{name = "changed", field_type = .Bool},
			Field_Definition{name = "valid", field_type = .Bool},
			Field_Definition{name = "submitted", field_type = .Bool},
			Field_Definition{name = "cancelled", field_type = .Bool},
			Field_Definition{name = "dragging", field_type = .Bool},
			Field_Definition{name = "drag_source", field_type = .String},
			Field_Definition{name = "drop_target", field_type = .String},
			Field_Definition{name = "drop_placement", field_type = .String},
			Field_Definition{name = "activation_revision", field_type = .Number},
			Field_Definition{name = "change_revision", field_type = .Number},
			Field_Definition{name = "submit_revision", field_type = .Number},
			Field_Definition{name = "cancel_revision", field_type = .Number},
			Field_Definition{name = "drop_revision", field_type = .Number},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_button",
		{
			Field_Definition{name = "text", field_type = .String},
			Field_Definition{name = "font", field_type = .String},
			Field_Definition{name = "color", field_type = .Vec4},
			Field_Definition{name = "size", field_type = .Number},
			Field_Definition{name = "alignment", field_type = .String},
			Field_Definition{name = "hover_background", field_type = .Vec4},
			Field_Definition{name = "active_background", field_type = .Vec4},
			Field_Definition{name = "hover_color", field_type = .Vec4},
			Field_Definition{name = "active_color", field_type = .Vec4},
			Field_Definition{name = "icon", field_type = .String},
			Field_Definition{name = "icon_inset", field_type = .Number},
			Field_Definition{name = "icon_stroke", field_type = .Number},
			Field_Definition{name = "panel_action", field_type = .Bool},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_input",
		{
			Field_Definition{name = "text", field_type = .String},
			Field_Definition{name = "font", field_type = .String},
			Field_Definition{name = "prefix", field_type = .String},
			Field_Definition{name = "color", field_type = .Vec4},
			Field_Definition{name = "prefix_color", field_type = .Vec4},
			Field_Definition{name = "prefix_background", field_type = .Vec4},
			Field_Definition{name = "size", field_type = .Number},
			Field_Definition{name = "prefix_width", field_type = .Number},
			Field_Definition{name = "selection_background", field_type = .Vec4},
			Field_Definition{name = "focus_border_color", field_type = .Vec4},
			Field_Definition{name = "invalid_border_color", field_type = .Vec4},
			Field_Definition{name = "caret_color", field_type = .Vec4},
			Field_Definition{name = "number", field_type = .Number},
			Field_Definition{name = "step", field_type = .Number},
			Field_Definition{name = "minimum", field_type = .Number},
			Field_Definition{name = "maximum", field_type = .Number},
			Field_Definition{name = "prefix_gap", field_type = .Number},
			Field_Definition{name = "prefix_corner_radius", field_type = .Number},
			Field_Definition{name = "prefix_text_padding", field_type = .Number},
			Field_Definition{name = "selection_corner_radius", field_type = .Number},
			Field_Definition{name = "focus_border_width", field_type = .Number},
			Field_Definition{name = "invalid_border_width", field_type = .Number},
			Field_Definition{name = "caret_width", field_type = .Number},
			Field_Definition{name = "caret_inset", field_type = .Number},
			Field_Definition{name = "read_only", field_type = .Bool},
			Field_Definition{name = "numeric", field_type = .Bool},
			Field_Definition{name = "has_minimum", field_type = .Bool},
			Field_Definition{name = "has_maximum", field_type = .Bool},
		},
	)
	register_engine_component(
		registry,
		"scrapbot.ui_checkbox",
		{
			Field_Definition{name = "checked", field_type = .Bool},
			Field_Definition{name = "box_size", field_type = .Number},
			Field_Definition{name = "background", field_type = .Vec4},
			Field_Definition{name = "checked_background", field_type = .Vec4},
			Field_Definition{name = "border_color", field_type = .Vec4},
			Field_Definition{name = "check_color", field_type = .Vec4},
			Field_Definition{name = "hover_background", field_type = .Vec4},
			Field_Definition{name = "active_background", field_type = .Vec4},
			Field_Definition{name = "corner_radius", field_type = .Number},
			Field_Definition{name = "border_width", field_type = .Number},
			Field_Definition{name = "check_inset", field_type = .Number},
			Field_Definition{name = "check_corner_radius", field_type = .Number},
			Field_Definition{name = "read_only", field_type = .Bool},
		},
	)
	register_engine_component(registry, "scrapbot.internal.render_instance", {})
}

register_engine_component :: proc(
	registry: ^Registry,
	name: string,
	fields: []Field_Definition,
) -> string {
	storage_kind, lifecycle := engine_component_storage(name)
	definition := Definition {
		name = name,
		owner = .Engine,
		storage_kind = storage_kind,
		lifecycle = lifecycle,
	}
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
	project_definition.storage_kind = .Custom
	project_definition.lifecycle = .Authored
	return register_definition(registry, project_definition)
}

register_library_component :: proc "c" (registry: ^Registry, definition: Definition) -> string {
	if !shared.component_name_is_valid(definition.name) {
		return "component name must be dot-separated identifier tokens"
	}
	if !shared.component_name_is_namespaced(definition.name) {
		return "library components must use dotted component names"
	}
	if component_name_uses_scrapbot_namespace(definition.name) {
		return "library components cannot use the scrapbot namespace"
	}

	library_definition := definition
	library_definition.owner = .Library
	library_definition.storage_kind = .Custom
	library_definition.lifecycle = .Authored
	return register_definition(registry, library_definition)
}

definition_is_authorable :: proc "contextless" (definition: Definition) -> bool {
	return definition.lifecycle == .Authored
}

engine_component_storage :: proc "contextless" (name: string) -> (Storage_Kind, Lifecycle) {
	switch name {
		case "scrapbot.transform":
			return .Transform, .Authored
		case "scrapbot.camera":
			return .Camera, .Authored
		case "scrapbot.ambient_light":
			return .Ambient_Light, .Authored
		case "scrapbot.directional_light":
			return .Directional_Light, .Authored
		case "scrapbot.point_light":
			return .Point_Light, .Authored
		case "scrapbot.mesh":
			return .Mesh, .Authored
		case "scrapbot.geometry":
			return .Geometry, .Authored
		case "scrapbot.material":
			return .Material, .Authored
		case "scrapbot.shadow_caster":
			return .Shadow_Caster, .Authored
		case "scrapbot.shadow_receiver":
			return .Shadow_Receiver, .Authored
		case "scrapbot.ui_layout":
			return .UI_Layout, .Authored
		case "scrapbot.ui_hstack":
			return .UI_HStack, .Authored
		case "scrapbot.ui_vstack":
			return .UI_VStack, .Authored
		case "scrapbot.ui_scroll_area":
			return .UI_Scroll_Area, .Authored
		case "scrapbot.ui_panel":
			return .UI_Panel, .Authored
		case "scrapbot.ui_table":
			return .UI_Table, .Authored
		case "scrapbot.ui_list":
			return .UI_List, .Authored
		case "scrapbot.ui_progress":
			return .UI_Progress, .Authored
		case "scrapbot.ui_text":
			return .UI_Text, .Authored
		case "scrapbot.ui_button":
			return .UI_Button, .Authored
		case "scrapbot.ui_input":
			return .UI_Input, .Authored
		case "scrapbot.ui_checkbox":
			return .UI_Checkbox, .Authored
		case "scrapbot.ui_state":
			return .UI_State, .Derived
	}
	return .Derived, .Derived
}

register_definition :: proc "c" (registry: ^Registry, definition: Definition) -> string {
	if registry == nil {
		return "component registry is not available"
	}
	if !shared.component_name_is_valid(definition.name) {
		return "component name must be dot-separated identifier tokens"
	}

	prepared := definition
	cache_definition_name_tokens(&prepared)
	if index, found := find_definition_index(registry, definition.name); found {
		existing := registry.definitions[index]
		if existing.owner != definition.owner {
			return "component is already registered"
		}
		registered := prepared
		registered.id = existing.id
		registry.definitions[index] = registered
		registry.revision += 1
		return ""
	}

	if registry.definition_count >= MAX_COMPONENTS {
		return "too many component definitions"
	}

	registered := prepared
	registered.id = Component_ID(registry.definition_count + 1)
	registry.definitions[registry.definition_count] = registered
	registry.definition_count += 1
	registry.revision += 1
	return ""
}

cache_definition_name_tokens :: proc "contextless" (definition: ^Definition) {
	if definition == nil {
		return
	}
	definition.name_token_count = 0
	start := 0
	for index in 0 ..= len(definition.name) {
		if index < len(definition.name) && definition.name[index] != '.' {
			continue
		}
		if definition.name_token_count >= MAX_COMPONENT_NAME_TOKENS {
			return
		}
		definition.name_tokens[definition.name_token_count] = definition.name[start:index]
		definition.name_token_count += 1
		start = index + 1
	}
}

find_definition :: proc "c" (
	registry: ^Registry,
	name: string,
) -> (
	definition: Definition,
	ok: bool,
) {
	index, found := find_definition_index(registry, name)
	if !found {
		return {}, false
	}
	return registry.definitions[index], true
}

find_definition_by_id :: proc "c" (
	registry: ^Registry,
	id: Component_ID,
) -> (
	definition: Definition,
	ok: bool,
) {
	if registry == nil || id == shared.INVALID_COMPONENT_ID {
		return {}, false
	}
	for definition in registry.definitions[:registry.definition_count] {
		if definition.id == id {
			return definition, true
		}
	}
	return {}, false
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

validate_custom_component :: proc(
	registry: ^Registry,
	scene_component: Custom_Component,
) -> string {
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

lookup_field_definition :: proc(
	definition: Definition,
	name: string,
) -> (
	field: Field_Definition,
	ok: bool,
) {
	for i in 0 ..< definition.field_count {
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

component_name_uses_scrapbot_namespace :: proc "c" (name: string) -> bool {
	prefix: string : "scrapbot."
	return len(name) > len(prefix) && name[:len(prefix)] == prefix
}
