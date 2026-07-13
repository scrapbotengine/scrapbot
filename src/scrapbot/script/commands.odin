package script


import base_runtime "base:runtime"
import c "core:c"
import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"

scrapbot_spawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}

	spawn: ecs.Spawn_Command
	if err := ecs.init_spawn_command(&spawn, ""); err != "" {
		return luau_push_error(L, err)
	}
	if lua_type(L, 1) == LUA_TTABLE {
		name_length: c.size_t
		lua_getfield(L, 1, "name")
		name_data := lua_tolstring(L, -1, &name_length)
		if name_data != nil {
			if err := ecs.init_spawn_command(&spawn, luau_string(name_data, name_length)); err != "" {
				lua_settop(L, -2)
				return luau_push_error(L, err)
			}
		}
		lua_settop(L, -2)

		if err := read_spawn_components(L, runtime, 1, &spawn); err != "" {
			return luau_push_error(L, err)
		}
	} else if lua_type(L, 1) != LUA_TNONE && lua_type(L, 1) != LUA_TNIL {
		return luau_push_error(L, "scrapbot.spawn expects an optional entity options table")
	}

	if err := ecs.queue_spawn_command(&runtime.commands, spawn); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_despawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, ok := entity_argument(L, 1, runtime.world)
	if !ok {
		return luau_push_error(L, "scrapbot.despawn expects an entity")
	}

	if err := ecs.queue_despawn(&runtime.commands, entity.index, entity.generation); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_add_component :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, entity_ok := entity_argument(L, 1, runtime.world)
	if !entity_ok {
		return luau_push_error(L, "scrapbot.add_component expects an entity")
	}
	component_ref, component_err := component_reference_argument(L, runtime, 2)
	if component_err != "" {
		return luau_push_error(L, component_err)
	}
	if lua_type(L, 3) != LUA_TTABLE {
		return luau_push_error(L, "scrapbot.add_component expects a component payload table")
	}

	if component_ref.name == "scrapbot.transform" {
		if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
			return luau_push_error(L, err)
		}
		transform, err := read_transform_payload(L, 3)
		if err != "" {
			return luau_push_error(L, err)
		}
		if err = ecs.queue_add_transform(&runtime.commands, entity.index, entity.generation, transform); err != "" {
			return luau_push_error(L, err)
		}
		return 0
	}
	if component_ref.name == "scrapbot.geometry" || component_ref.name == "scrapbot.material" {
		if err := require_system_access(runtime,component_ref.name,.Write); err != "" {return luau_push_error(L,err)}
		expected := "geometry"; if component_ref.name == "scrapbot.material" {expected = "material"}
		index,generation,ok := resource_handle_fields(L,3,expected); if !ok {return luau_push_error(L,"render component expects a matching resource handle")}
		if component_ref.name == "scrapbot.geometry" {
			if _,valid:=resources.get_geometry(runtime.resource_registry,{index,generation}); !valid {return luau_push_error(L,"geometry resource handle is stale")}
			if err:=ecs.queue_add_geometry(&runtime.commands,entity.index,entity.generation,{index,generation}); err!="" {return luau_push_error(L,err)}
		} else {
			if _,valid:=resources.get_material(runtime.resource_registry,{index,generation}); !valid {return luau_push_error(L,"material resource handle is stale")}
			if err:=ecs.queue_add_material(&runtime.commands,entity.index,entity.generation,{index,generation}); err!="" {return luau_push_error(L,err)}
		}
		return 0
	}
	if component_ref.name == "scrapbot.shadow_caster" || component_ref.name == "scrapbot.shadow_receiver" {
		if err := require_system_access(runtime, component_ref.name, .Write); err != "" {return luau_push_error(L, err)}
		if err := ecs.queue_add_marker(&runtime.commands, entity.index, entity.generation, component_ref.name); err != "" {return luau_push_error(L, err)}
		return 0
	}

	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	command_component: ecs.Command_Component
	if err := read_custom_component_payload(L, runtime, component_ref, 3, &command_component); err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_add_custom_component(&runtime.commands, entity.index, entity.generation, command_component); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_remove_component :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, entity_ok := entity_argument(L, 1, runtime.world)
	if !entity_ok {
		return luau_push_error(L, "scrapbot.remove_component expects an entity")
	}
	component_ref, component_err := component_reference_argument(L, runtime, 2)
	if component_err != "" {
		return luau_push_error(L, component_err)
	}
	if component_ref.name != "scrapbot.transform" && component_ref.name != "scrapbot.geometry" && component_ref.name != "scrapbot.material" && component_ref.name != "scrapbot.shadow_caster" && component_ref.name != "scrapbot.shadow_receiver" && !component_ref_is_custom_schema_component(&runtime.registry, component_ref) {
		return luau_push_error(L, "runtime component removal does not support this engine component")
	}
	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_remove_component(&runtime.commands, entity.index, entity.generation, component_ref.id, component_ref.name); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

read_spawn_components :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	options_index: c.int,
	spawn: ^ecs.Spawn_Command,
) -> string {
	context = base_runtime.default_context()
	lua_getfield(L, options_index, "components")
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL {
		return ""
	}
	if lua_type(L, -1) != LUA_TTABLE {
		return "spawn components must be a table"
	}

	lua_pushnil(L)
	for lua_next(L, -2) != 0 {
		if lua_type(L, -2) != LUA_TSTRING || lua_type(L, -1) != LUA_TTABLE {
			return "spawn components must map component names to payload tables"
		}
		name_length: c.size_t
		name_data := lua_tolstring(L, -2, &name_length)
		if name_data == nil {
			return "spawn component names must be strings"
		}
		component_name := luau_string(name_data, name_length)

		if component_name == "scrapbot.transform" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {
				return err
			}
			transform, err := read_transform_payload(L, -1)
			if err != "" {
				return err
			}
			if err = ecs.spawn_set_transform(spawn, transform); err != "" {
				return err
			}
		} else if component_name == "scrapbot.geometry" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {return err}
			index, generation, ok := resource_handle_fields(L, -1, "geometry")
			if !ok {return "scrapbot.geometry expects a geometry resource handle"}
			if _, valid := resources.get_geometry(runtime.resource_registry, {index,generation}); !valid {return "scrapbot.geometry references a stale resource"}
			ecs.spawn_set_geometry(spawn, {index,generation})
		} else if component_name == "scrapbot.material" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {return err}
			index, generation, ok := resource_handle_fields(L, -1, "material")
			if !ok {return "scrapbot.material expects a material resource handle"}
			if _, valid := resources.get_material(runtime.resource_registry, {index,generation}); !valid {return "scrapbot.material references a stale resource"}
			ecs.spawn_set_material(spawn, {index,generation})
		} else if component_name == "scrapbot.shadow_caster" || component_name == "scrapbot.shadow_receiver" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {return err}
			if err := ecs.spawn_set_marker(spawn, component_name); err != "" {return err}
		} else {
			command_component: ecs.Command_Component
			definition, registered := component.find_definition(&runtime.registry, component_name)
			if !registered {
				return "runtime component payload references an unregistered component"
			}
			if err := require_system_access(runtime, definition.name, .Write); err != "" {
				return err
			}
			component_ref := Component_Reference{name = definition.name, id = definition.id}
			if err := read_custom_component_payload(L, runtime, component_ref, -1, &command_component); err != "" {
				return err
			}
			if err := ecs.spawn_add_custom_component(spawn, command_component); err != "" {
				return err
			}
		}

		lua_settop(L, -2)
	}
	return ""
}

resource_handle_fields :: proc "c" (L: Lua_State, index: c.int, expected_kind: string) -> (u32, u32, bool) {
	lua_getfield(L, index, "kind"); kind, kind_ok := luau_required_string(L, -1); lua_settop(L, -2)
	if !kind_ok || kind != expected_kind {return 0,0,false}
	is_number: c.int; lua_getfield(L, index, "index"); handle_index := lua_tointegerx(L, -1, &is_number); lua_settop(L, -2); if is_number == 0 || handle_index < 0 {return 0,0,false}
	lua_getfield(L, index, "generation"); generation := lua_tointegerx(L, -1, &is_number); lua_settop(L, -2); if is_number == 0 || generation <= 0 {return 0,0,false}
	return u32(handle_index), u32(generation), true
}

read_transform_payload :: proc "c" (L: Lua_State, payload_index: c.int) -> (transform: Transform_Component, err: string) {
	transform.scale = Vec3{1, 1, 1}

	if value, found, ok := optional_vec3_field(L, payload_index, "position"); found {
		if !ok {
			return transform, "scrapbot.transform.position must be a vec3"
		}
		transform.position = value
	}
	if value, found, ok := optional_vec3_field(L, payload_index, "rotation"); found {
		if !ok {
			return transform, "scrapbot.transform.rotation must be a vec3"
		}
		transform.rotation = value
	}
	if value, found, ok := optional_vec3_field(L, payload_index, "scale"); found {
		if !ok {
			return transform, "scrapbot.transform.scale must be a vec3"
		}
		transform.scale = value
	}

	return transform, ""
}

read_full_transform_table :: proc "c" (L: Lua_State, payload_index: c.int) -> (transform: Transform_Component, err: string) {
	value, ok := required_vec3_field(L, payload_index, "position")
	if !ok {
		return transform, "scrapbot.transform.position must be a vec3"
	}
	transform.position = value

	value, ok = required_vec3_field(L, payload_index, "rotation")
	if !ok {
		return transform, "scrapbot.transform.rotation must be a vec3"
	}
	transform.rotation = value

	value, ok = required_vec3_field(L, payload_index, "scale")
	if !ok {
		return transform, "scrapbot.transform.scale must be a vec3"
	}
	transform.scale = value
	return transform, ""
}

read_custom_component_payload :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	component_ref: Component_Reference,
	payload_index: c.int,
	command_component: ^ecs.Command_Component,
) -> string {
	definition, registered := component.find_definition_by_id(&runtime.registry, component_ref.id)
	if !registered {
		if shared.component_name_is_project_level(component_ref.name) {
			return "runtime component payload references an unregistered project component"
		}
		return "runtime component payload references an unregistered component"
	}
	if definition.name != component_ref.name {
		return "runtime component payload references an unregistered component"
	}
	if definition.owner != .Project && definition.owner != .Library {
		return "runtime component mutation only supports scrapbot.transform and schema-backed custom components"
	}
	if err := ecs.init_command_component(command_component, component_ref.id, component_ref.name); err != "" {
		return err
	}

	for i in 0..<definition.field_count {
		field := definition.fields[i]
		if field.field_type != component.Field_Type.Vec3 {
			return "unsupported component field type"
		}
		value, found, ok := optional_vec3_field(L, payload_index, cstring(raw_data(field.name)))
		if !found {
			return "component payload is missing a required field"
		}
		if !ok {
			return "component payload field must be a vec3"
		}
		if err := ecs.command_component_add_vec3(command_component, field.name, value); err != "" {
			return err
		}
	}

	return ""
}

custom_component_matches_command :: proc(
	world_component: Custom_Component,
	command_component: ^ecs.Command_Component,
) -> bool {
	if world_component.component_id != command_component.component_id ||
	   world_component.name != ecs.command_component_name(command_component) ||
	   len(world_component.vec3_fields) != command_component.vec3_field_count {
		return false
	}

	for i in 0..<command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		value, ok := custom_component_vec3_field(world_component, ecs.command_field_name(command_field))
		if !ok || value != command_field.value {
			return false
		}
	}

	return true
}

custom_component_vec3_field :: proc(
	world_component: Custom_Component,
	name: string,
) -> (value: Vec3, ok: bool) {
	for field in world_component.vec3_fields {
		if field.name == name {
			return field.value, true
		}
	}
	return {}, false
}

apply_custom_component_command :: proc(
	world_component: ^Custom_Component,
	command_component: ^ecs.Command_Component,
) {
	if world_component == nil {
		return
	}
	for i in 0..<command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		field_name := ecs.command_field_name(command_field)
		for &world_field in world_component.vec3_fields {
			if world_field.name == field_name {
				world_field.value = command_field.value
				break
			}
		}
	}
}

optional_vec3_field :: proc "c" (L: Lua_State, index: c.int, name: cstring) -> (value: Vec3, found, ok: bool) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return {}, false, true
	}
	value, ok = vec3_argument(L, -1)
	lua_settop(L, -2)
	return value, true, ok
}

required_vec3_field :: proc "c" (L: Lua_State, index: c.int, name: cstring) -> (value: Vec3, ok: bool) {
	lua_getfield(L, index, name)
	value, ok = vec3_argument(L, -1)
	lua_settop(L, -2)
	return value, ok
}
