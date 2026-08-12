package script


import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import base_runtime "base:runtime"
import c "core:c"
import "core:math"
import "core:strings"

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
			if err := ecs.init_spawn_command(&spawn, luau_string(name_data, name_length));
			   err != "" {
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
	id_buffer: [36]u8
	id := shared.entity_uuid_to_string(spawn.uuid, id_buffer[:])
	lua_pushlstring(L, cstring(raw_data(id)), c.size_t(len(id)))
	return 1
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

scrapbot_change_scene :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	raw_id, ok := luau_required_string(L, 1)
	if !ok {
		return luau_push_error(L, "scrapbot.change_scene expects a scene UUID string")
	}
	id, parsed := shared.resource_uuid_parse(raw_id)
	if !parsed {
		return luau_push_error(L, "scrapbot.change_scene expects a non-zero scene UUID")
	}
	runtime.requested_scene = id
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
		if err = ecs.queue_add_transform(
			&runtime.commands,
			entity.index,
			entity.generation,
			transform,
		); err != "" {
			return luau_push_error(L, err)
		}
		return 0
	}
	if component_ref.name == "scrapbot.mesh" {
		if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
			return luau_push_error(L, err)
		}
		primitive, geometry_mode, ok := read_mesh_payload(L, 3)
		if !ok {
			return luau_push_error(
				L,
				"scrapbot.mesh expects primitive and optional geometry_mode fields",
			)
		}
		if err := ecs.queue_add_mesh(
			&runtime.commands,
			entity.index,
			entity.generation,
			primitive,
			geometry_mode,
		); err != "" {
			return luau_push_error(L, err)
		}
		return 0
	}
	if component_ref.name == "scrapbot.geometry" || component_ref.name == "scrapbot.material" {
		if err := require_system_access(runtime, component_ref.name, .Write);
		   err != "" { return luau_push_error(L, err) }
		expected := "geometry"; if component_ref.name == "scrapbot.material" { expected = "material" }
		index, generation, geometry_mode, ok := render_resource_payload_fields(L, 3, expected)
		if !ok {
			return luau_push_error(L, "render component expects a matching resource payload")
		}
		if component_ref.name == "scrapbot.geometry" {
			if _, valid := resources.get_geometry(runtime.resource_registry, {index, generation});
			   !valid { return luau_push_error(L, "geometry resource handle is stale") }
			if err := ecs.queue_add_geometry(
				&runtime.commands,
				entity.index,
				entity.generation,
				{index, generation},
				geometry_mode,
			); err != "" { return luau_push_error(L, err) }
		} else {
			if _, valid := resources.get_material(runtime.resource_registry, {index, generation});
			   !valid { return luau_push_error(L, "material resource handle is stale") }
			if err := ecs.queue_add_material(
				&runtime.commands,
				entity.index,
				entity.generation,
				{index, generation},
			); err != "" { return luau_push_error(L, err) }
		}
		return 0
	}
	if component_ref.name == "scrapbot.shadow_caster" ||
	   component_ref.name == "scrapbot.shadow_receiver" {
		if err := require_system_access(runtime, component_ref.name, .Write);
		   err != "" { return luau_push_error(L, err) }
		if err := ecs.queue_add_marker(
			&runtime.commands,
			entity.index,
			entity.generation,
			component_ref.name,
		); err != "" { return luau_push_error(L, err) }
		return 0
	}
	if ui_component_name_is_mutable(component_ref.name) {
		if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
			return luau_push_error(L, err)
		}
		kind := ecs.ui_component_command_kind(component_ref.name)
		base := ecs.queued_ui_component(
			&runtime.commands,
			int(entity.index),
			entity.generation,
			kind,
		)
		ui_component: ecs.UI_Component_Command
		if err := read_ui_component_command_from_luau(
			L,
			runtime.world,
			int(entity.index),
			component_ref.name,
			3,
			&ui_component,
			base,
		); err != "" {
			return luau_push_error(L, err)
		}
		if err := ecs.queue_add_ui_component(
			&runtime.commands,
			entity.index,
			entity.generation,
			ui_component,
		); err != "" {
			return luau_push_error(L, err)
		}
		return 0
	}

	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	command_component: ecs.Command_Component
	if err := read_custom_component_payload(L, runtime, component_ref, 3, &command_component);
	   err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_add_custom_component(
		&runtime.commands,
		entity.index,
		entity.generation,
		command_component,
	); err != "" {
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
	if component_ref.name != "scrapbot.transform" &&
	   component_ref.name != "scrapbot.geometry" &&
	   component_ref.name != "scrapbot.material" &&
	   component_ref.name != "scrapbot.shadow_caster" &&
	   component_ref.name != "scrapbot.shadow_receiver" &&
	   !ui_component_name_is_mutable(component_ref.name) &&
	   !component_ref_is_custom_schema_component(&runtime.registry, component_ref) {
		return luau_push_error(
			L,
			"runtime component removal does not support this engine component",
		)
	}
	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_remove_component(
		&runtime.commands,
		entity.index,
		entity.generation,
		component_ref.id,
		component_ref.name,
	); err != "" {
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
		} else if component_name == "scrapbot.mesh" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {
				return err
			}
			primitive, geometry_mode, ok := read_mesh_payload(L, -1)
			if !ok {
				return "scrapbot.mesh expects primitive and optional geometry_mode fields"
			}
			if err := ecs.spawn_set_mesh(spawn, primitive, geometry_mode); err != "" {
				return err
			}
		} else if component_name == "scrapbot.geometry" {
			if err := require_system_access(runtime, component_name, .Write);
			   err != "" { return err }
			index, generation, geometry_mode, ok := render_resource_payload_fields(
				L,
				-1,
				"geometry",
			)
			if !ok { return "scrapbot.geometry expects a geometry resource handle" }
			if _, valid := resources.get_geometry(runtime.resource_registry, {index, generation});
			   !valid { return "scrapbot.geometry references a stale resource" }
			ecs.spawn_set_geometry(spawn, {index, generation})
			spawn.geometry_mode = geometry_mode
		} else if component_name == "scrapbot.material" {
			if err := require_system_access(runtime, component_name, .Write);
			   err != "" { return err }
			index, generation, ok := resource_handle_fields(L, -1, "material")
			if !ok { return "scrapbot.material expects a material resource handle" }
			if _, valid := resources.get_material(runtime.resource_registry, {index, generation});
			   !valid { return "scrapbot.material references a stale resource" }
			ecs.spawn_set_material(spawn, {index, generation})
		} else if component_name == "scrapbot.point_light" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {
				return err
			}
			point_light, err := read_point_light_payload(L, -1)
			if err != "" {
				return err
			}
			if err = ecs.spawn_set_point_light(spawn, point_light); err != "" {
				return err
			}
		} else if component_name == "scrapbot.shadow_caster" ||
		   component_name == "scrapbot.shadow_receiver" {
			if err := require_system_access(runtime, component_name, .Write);
			   err != "" { return err }
			if err := ecs.spawn_set_marker(spawn, component_name); err != "" { return err }
		} else if ui_component_name_is_mutable(component_name) {
			if err := require_system_access(runtime, component_name, .Write); err != "" {
				return err
			}
			ui_component: ecs.UI_Component_Command
			if err := read_ui_component_command_from_luau(
				L,
				runtime.world,
				-1,
				component_name,
				-1,
				&ui_component,
			); err != "" {
				return err
			}
			if err := ecs.spawn_add_ui_component(spawn, ui_component); err != "" {
				return err
			}
		} else {
			command_component: ecs.Command_Component
			definition, registered := component.find_definition(&runtime.registry, component_name)
			if !registered {
				return "runtime component payload references an unregistered component"
			}
			if err := require_system_access(runtime, definition.name, .Write); err != "" {
				return err
			}
			component_ref := Component_Reference {
				name = definition.name,
				id = definition.id,
			}
			if err := read_custom_component_payload(
				L,
				runtime,
				component_ref,
				-1,
				&command_component,
			); err != "" {
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

read_point_light_payload :: proc "c" (
	L: Lua_State,
	payload_index: c.int,
) -> (
	value: shared.Point_Light_Component,
	err: string,
) {
	color, color_ok := required_vec3_field(L, payload_index, "color")
	if !color_ok {
		return value, "scrapbot.point_light.color must be a vec3"
	}
	intensity, intensity_found, intensity_ok := optional_number_field(
		L,
		payload_index,
		"intensity",
	)
	if !intensity_found || !intensity_ok {
		return value, "scrapbot.point_light.intensity must be a number"
	}
	light_range, range_found, range_ok := optional_number_field(L, payload_index, "range")
	if !range_found || !range_ok {
		return value, "scrapbot.point_light.range must be a number"
	}
	if color.x < 0 ||
	   color.x > 1 ||
	   color.y < 0 ||
	   color.y > 1 ||
	   color.z < 0 ||
	   color.z > 1 ||
	   intensity < 0 ||
	   light_range < 0 ||
	   math.is_nan(color.x) ||
	   math.is_nan(color.y) ||
	   math.is_nan(color.z) ||
	   math.is_nan(intensity) ||
	   math.is_nan(light_range) ||
	   math.is_inf(color.x) ||
	   math.is_inf(color.y) ||
	   math.is_inf(color.z) ||
	   math.is_inf(intensity) ||
	   math.is_inf(light_range) {
		return value, "scrapbot.point_light payload is invalid"
	}
	return shared.Point_Light_Component{color = color, intensity = intensity, range = light_range},
		""
}

resource_handle_fields :: proc "c" (
	L: Lua_State,
	index: c.int,
	expected_kind: string,
) -> (
	u32,
	u32,
	bool,
) {
	lua_getfield(L, index, "kind"); kind, kind_ok := luau_required_string(L, -1); lua_settop(L, -2)
	if !kind_ok || kind != expected_kind { return 0, 0, false }
	is_number: c.int; lua_getfield(L, index, "index"); handle_index := lua_tointegerx(L, -1, &is_number); lua_settop(L, -2); if is_number == 0 || handle_index < 0 { return 0, 0, false }
	lua_getfield(
		L,
		index,
		"generation",
	); generation := lua_tointegerx(L, -1, &is_number); lua_settop(L, -2); if is_number == 0 || generation <= 0 { return 0, 0, false }
	return u32(handle_index), u32(generation), true
}

read_mesh_payload :: proc "c" (
	L: Lua_State,
	index: c.int,
) -> (
	string,
	shared.Geometry_Mode,
	bool,
) {
	lua_getfield(L, index, "primitive")
	primitive, primitive_ok := luau_required_string(L, -1)
	lua_settop(L, -2)
	if !primitive_ok || primitive == "" {
		return "", .Inherit, false
	}

	geometry_mode := shared.Geometry_Mode.Inherit
	lua_getfield(L, index, "geometry_mode")
	if lua_type(L, -1) != LUA_TNIL {
		name, name_ok := luau_required_string(L, -1)
		if !name_ok {
			lua_settop(L, -2)
			return "", .Inherit, false
		}
		parsed, parsed_ok := shared.geometry_mode_from_name(name)
		if !parsed_ok {
			lua_settop(L, -2)
			return "", .Inherit, false
		}
		geometry_mode = parsed
	}
	lua_settop(L, -2)
	return primitive, geometry_mode, true
}

render_resource_payload_fields :: proc "c" (
	L: Lua_State,
	index: c.int,
	expected_kind: string,
) -> (
	u32,
	u32,
	shared.Geometry_Mode,
	bool,
) {
	if handle_index, generation, ok := resource_handle_fields(L, index, expected_kind); ok {
		return handle_index, generation, .Inherit, true
	}

	lua_getfield(L, index, "resource")
	handle_index, generation, handle_ok := resource_handle_fields(L, -1, expected_kind)
	lua_settop(L, -2)
	if !handle_ok {
		return 0, 0, .Inherit, false
	}

	geometry_mode := shared.Geometry_Mode.Inherit
	lua_getfield(L, index, "geometry_mode")
	if lua_type(L, -1) != LUA_TNIL {
		name, name_ok := luau_required_string(L, -1)
		if !name_ok {
			lua_settop(L, -2)
			return 0, 0, .Inherit, false
		}
		parsed, parsed_ok := shared.geometry_mode_from_name(name)
		if !parsed_ok {
			lua_settop(L, -2)
			return 0, 0, .Inherit, false
		}
		geometry_mode = parsed
	}
	lua_settop(L, -2)
	return handle_index, generation, geometry_mode, true
}

read_transform_payload :: proc "c" (
	L: Lua_State,
	payload_index: c.int,
) -> (
	transform: Transform_Component,
	err: string,
) {
	transform.scale = Vec3{1, 1, 1}
	if err = read_ui_uuid_field(L, payload_index, "parent", &transform.parent); err != "" {
		return transform, "scrapbot.transform.parent must be an entity UUID string"
	}

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

read_full_transform_table :: proc "c" (
	L: Lua_State,
	payload_index: c.int,
) -> (
	transform: Transform_Component,
	err: string,
) {
	if err = read_ui_uuid_field(L, payload_index, "parent", &transform.parent); err != "" {
		return transform, "scrapbot.transform.parent must be an entity UUID string"
	}
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

read_full_camera_table :: proc "c" (
	L: Lua_State,
	payload_index: c.int,
	original: shared.Camera_Component,
) -> (
	value: shared.Camera_Component,
	err: string,
) {
	value = original
	if err = read_ui_number_field(L, payload_index, "fov", &value.fov); err != "" {
		return
	}
	if err = read_ui_number_field(L, payload_index, "near", &value.near); err != "" {
		return
	}
	if err = read_ui_number_field(L, payload_index, "far", &value.far); err != "" {
		return
	}
	debug_view_name := shared.render_debug_view_name(value.debug_view)
	if err = read_ui_string_field(L, payload_index, "debug_view", &debug_view_name); err != "" {
		return
	}
	debug_view, debug_view_ok := shared.render_debug_view_from_name(debug_view_name)
	if !debug_view_ok {
		err = "scrapbot.camera.debug_view must name a supported render debug view"
		return
	}
	value.debug_view = debug_view
	if err = read_ui_number_field(L, payload_index, "debug_hiz_mip", &value.debug_hiz_mip);
	   err != "" {
		return
	}
	if err = read_ui_bool_field(
		L,
		payload_index,
		"debug_occlusion_freeze",
		&value.debug_occlusion_freeze,
	); err != "" {
		return
	}
	if err = read_ui_number_field(L, payload_index, "resolution_scale", &value.resolution_scale);
	   err != "" {
		return
	}
	if err = read_ui_bool_field(L, payload_index, "dynamic_resolution", &value.dynamic_resolution);
	   err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"dynamic_resolution_min_scale",
		&value.dynamic_resolution_min_scale,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"dynamic_resolution_target_ms",
		&value.dynamic_resolution_target_ms,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"adaptive_quality_minimum",
		&value.adaptive_quality_minimum,
	); err != "" {
		return
	}
	if err = read_ui_number_field(L, payload_index, "exposure", &value.exposure); err != "" {
		return
	}
	if err = read_ui_bool_field(L, payload_index, "automatic_exposure", &value.automatic_exposure);
	   err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"automatic_exposure_min",
		&value.automatic_exposure_min,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"automatic_exposure_max",
		&value.automatic_exposure_max,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"automatic_exposure_speed",
		&value.automatic_exposure_speed,
	); err != "" {
		return
	}
	if err = read_ui_bool_field(
		L,
		payload_index,
		"temporal_antialiasing",
		&value.temporal_antialiasing,
	); err != "" {
		return
	}
	if err = read_ui_bool_field(L, payload_index, "fast_antialiasing", &value.fast_antialiasing);
	   err != "" {
		return
	}
	if err = read_ui_bool_field(L, payload_index, "ambient_occlusion", &value.ambient_occlusion);
	   err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"ambient_occlusion_quality",
		&value.ambient_occlusion_quality,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"ambient_occlusion_resolution_scale",
		&value.ambient_occlusion_resolution_scale,
	); err != "" {
		return
	}
	if err = read_ui_bool_field(
		L,
		payload_index,
		"screen_space_reflections",
		&value.screen_space_reflections,
	); err != "" {
		return
	}
	if err = read_ui_number_field(
		L,
		payload_index,
		"screen_space_reflections_quality",
		&value.screen_space_reflections_quality,
	); err != "" {
		return
	}
	if err = read_ui_bool_field(L, payload_index, "bloom", &value.bloom); err != "" {
		return
	}
	if math.is_nan(value.fov) ||
	   math.is_inf(value.fov) ||
	   value.fov < 1 ||
	   value.fov > 179 ||
	   math.is_nan(value.near) ||
	   math.is_inf(value.near) ||
	   value.near <= 0 ||
	   math.is_nan(value.far) ||
	   math.is_inf(value.far) ||
	   value.far <= value.near ||
	   math.is_nan(value.debug_hiz_mip) ||
	   math.is_inf(value.debug_hiz_mip) ||
	   value.debug_hiz_mip < 0 ||
	   value.debug_hiz_mip > 15 ||
	   math.is_nan(value.resolution_scale) ||
	   math.is_inf(value.resolution_scale) ||
	   value.resolution_scale < 0.5 ||
	   value.resolution_scale > 1 ||
	   math.is_nan(value.dynamic_resolution_min_scale) ||
	   math.is_inf(value.dynamic_resolution_min_scale) ||
	   value.dynamic_resolution_min_scale < 0.5 ||
	   value.dynamic_resolution_min_scale > value.resolution_scale ||
	   math.is_nan(value.dynamic_resolution_target_ms) ||
	   math.is_inf(value.dynamic_resolution_target_ms) ||
	   value.dynamic_resolution_target_ms < 1 ||
	   value.dynamic_resolution_target_ms > 100 ||
	   math.is_nan(value.adaptive_quality_minimum) ||
	   math.is_inf(value.adaptive_quality_minimum) ||
	   value.adaptive_quality_minimum < 0.25 ||
	   value.adaptive_quality_minimum > 1 ||
	   math.is_nan(value.exposure) ||
	   math.is_inf(value.exposure) ||
	   value.exposure <= 0 ||
	   math.is_nan(value.automatic_exposure_min) ||
	   math.is_inf(value.automatic_exposure_min) ||
	   value.automatic_exposure_min <= 0 ||
	   math.is_nan(value.automatic_exposure_max) ||
	   math.is_inf(value.automatic_exposure_max) ||
	   value.automatic_exposure_max < value.automatic_exposure_min ||
	   math.is_nan(value.automatic_exposure_speed) ||
	   math.is_inf(value.automatic_exposure_speed) ||
	   value.automatic_exposure_speed <= 0 ||
	   math.is_nan(value.ambient_occlusion_quality) ||
	   math.is_inf(value.ambient_occlusion_quality) ||
	   value.ambient_occlusion_quality < 0.25 ||
	   value.ambient_occlusion_quality > 1 ||
	   math.is_nan(value.ambient_occlusion_resolution_scale) ||
	   math.is_inf(value.ambient_occlusion_resolution_scale) ||
	   value.ambient_occlusion_resolution_scale < 0.25 ||
	   value.ambient_occlusion_resolution_scale > 1 ||
	   math.is_nan(value.screen_space_reflections_quality) ||
	   math.is_inf(value.screen_space_reflections_quality) ||
	   value.screen_space_reflections_quality < 0.25 ||
	   value.screen_space_reflections_quality > 1 {
		return value, "invalid scrapbot.camera payload"
	}
	return value, ""
}

read_full_world_environment_table :: proc "c" (
	L: Lua_State,
	payload_index: c.int,
	original: shared.World_Environment_Component,
) -> (
	value: shared.World_Environment_Component,
	err: string,
) {
	context = base_runtime.default_context()
	value = original
	lighting := ""
	if err = read_ui_string_field(L, payload_index, "lighting", &lighting); err != "" {
		return value, err
	}
	value.lighting = strings.clone(lighting)
	background := ""
	if err = read_ui_string_field(L, payload_index, "background", &background); err != "" {
		delete(value.lighting)
		return value, err
	}
	value.background = strings.clone(background)
	defer if err != "" {
		delete(value.lighting)
		delete(value.background)
	}

	if err = read_ui_number_field(
		L,
		payload_index,
		"lighting_intensity",
		&value.lighting_intensity,
	); err != "" { return }
	if err = read_ui_number_field(
		L,
		payload_index,
		"reflection_intensity",
		&value.reflection_intensity,
	); err != "" { return }
	if err = read_ui_number_field(L, payload_index, "lighting_rotation", &value.lighting_rotation);
	   err != "" { return }
	if err = read_ui_number_field(L, payload_index, "exposure", &value.exposure);
	   err != "" { return }
	if err = read_ui_bool_field(L, payload_index, "background_visible", &value.background_visible);
	   err != "" { return }
	if err = read_ui_number_field(
		L,
		payload_index,
		"background_intensity",
		&value.background_intensity,
	); err != "" { return }
	if err = read_ui_number_field(
		L,
		payload_index,
		"background_rotation",
		&value.background_rotation,
	); err != "" { return }
	if err = read_ui_number_field(
		L,
		payload_index,
		"background_exposure",
		&value.background_exposure,
	); err != "" { return }
	if err = read_ui_number_field(L, payload_index, "background_blur", &value.background_blur);
	   err != "" { return }
	vec3_ok := false
	if value.sky_tint, vec3_ok = required_vec3_field(L, payload_index, "sky_tint"); !vec3_ok {
		return value, "scrapbot.world_environment.sky_tint must be a vec3"
	}
	if value.ground_color, vec3_ok = required_vec3_field(L, payload_index, "ground_color");
	   !vec3_ok {
		return value, "scrapbot.world_environment.ground_color must be a vec3"
	}
	if err = read_ui_number_field(L, payload_index, "turbidity", &value.turbidity);
	   err != "" { return }
	if err = read_ui_number_field(
		L,
		payload_index,
		"atmosphere_thickness",
		&value.atmosphere_thickness,
	); err != "" { return }
	if err = read_ui_number_field(L, payload_index, "horizon_softness", &value.horizon_softness);
	   err != "" { return }
	if value.sun_direction, vec3_ok = required_vec3_field(L, payload_index, "sun_direction");
	   !vec3_ok {
		return value, "scrapbot.world_environment.sun_direction must be a non-zero vec3"
	}
	if value.sun_color, vec3_ok = required_vec3_field(L, payload_index, "sun_color"); !vec3_ok {
		return value, "scrapbot.world_environment.sun_color must be a vec3"
	}
	if err = read_ui_number_field(L, payload_index, "sun_intensity", &value.sun_intensity);
	   err != "" { return }
	if err = read_ui_number_field(L, payload_index, "sun_size", &value.sun_size);
	   err != "" { return }
	if err = read_ui_number_field(L, payload_index, "sun_glow", &value.sun_glow);
	   err != "" { return }
	if !shared.world_environment_is_valid(value) {
		return value, "scrapbot.world_environment payload is invalid"
	}
	return value, ""
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
		return(
			"runtime component mutation only supports scrapbot.transform and schema-backed custom components" \
		)
	}
	if err := ecs.init_command_component(command_component, component_ref.id, component_ref.name);
	   err != "" {
		return err
	}

	for i in 0 ..< definition.field_count {
		field := definition.fields[i]
		switch field.field_type {
			case .Number:
				value, found, ok := optional_number_field(
					L,
					payload_index,
					cstring(raw_data(field.name)),
				)
				if !found || !ok {
					return "component payload field must be a number"
				}
				if err := ecs.command_component_add_number(command_component, field.name, value);
				   err != "" {
					return err
				}
			case .Vec2:
				value, found, ok := optional_vec2_field(
					L,
					payload_index,
					cstring(raw_data(field.name)),
				)
				if !found || !ok {
					return "component payload field must be a vec2"
				}
				if err := ecs.command_component_add_vec2(command_component, field.name, value);
				   err != "" {
					return err
				}
			case .Vec3:
				value, found, ok := optional_vec3_field(
					L,
					payload_index,
					cstring(raw_data(field.name)),
				)
				if !found || !ok {
					return "component payload field must be a vec3"
				}
				if err := ecs.command_component_add_vec3(command_component, field.name, value);
				   err != "" {
					return err
				}
			case .Vec4, .Color:
				value, found, ok := optional_vec4_field(
					L,
					payload_index,
					cstring(raw_data(field.name)),
				)
				if !found || !ok {
					return "component payload field must be a vec4"
				}
				if err := ecs.command_component_add_vec4(command_component, field.name, value);
				   err != "" {
					return err
				}
			case .Bool, .String:
				return "unsupported component field type"
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
	   len(world_component.number_fields) != command_component.number_field_count ||
	   len(world_component.vec2_fields) != command_component.vec2_field_count ||
	   len(world_component.vec3_fields) != command_component.vec3_field_count {
		return false
	}
	if len(world_component.vec4_fields) != command_component.vec4_field_count {
		return false
	}

	for i in 0 ..< command_component.number_field_count {
		command_field := &command_component.number_fields[i]
		value, ok := custom_component_number_field(
			world_component,
			ecs.command_number_field_name(command_field),
		)
		if !ok || value != command_field.value {
			return false
		}
	}
	for i in 0 ..< command_component.vec2_field_count {
		command_field := &command_component.vec2_fields[i]
		value, ok := custom_component_vec2_field(
			world_component,
			ecs.command_vec2_field_name(command_field),
		)
		if !ok || value != command_field.value {
			return false
		}
	}

	for i in 0 ..< command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		value, ok := custom_component_vec3_field(
			world_component,
			ecs.command_field_name(command_field),
		)
		if !ok || value != command_field.value {
			return false
		}
	}
	for i in 0 ..< command_component.vec4_field_count {
		command_field := &command_component.vec4_fields[i]
		value, ok := custom_component_vec4_field(
			world_component,
			ecs.command_vec4_field_name(command_field),
		)
		if !ok || value != command_field.value {
			return false
		}
	}

	return true
}

custom_component_number_field :: proc(
	world_component: Custom_Component,
	name: string,
) -> (
	f32,
	bool,
) {
	for field in world_component.number_fields {
		if field.name == name {
			return field.value, true
		}
	}
	return 0, false
}

custom_component_vec2_field :: proc(
	world_component: Custom_Component,
	name: string,
) -> (
	Vec2,
	bool,
) {
	for field in world_component.vec2_fields {
		if field.name == name {
			return field.value, true
		}
	}
	return {}, false
}

custom_component_vec3_field :: proc(
	world_component: Custom_Component,
	name: string,
) -> (
	value: Vec3,
	ok: bool,
) {
	for field in world_component.vec3_fields {
		if field.name == name {
			return field.value, true
		}
	}
	return {}, false
}

custom_component_vec4_field :: proc(
	world_component: Custom_Component,
	name: string,
) -> (
	Vec4,
	bool,
) {
	for field in world_component.vec4_fields {
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
	for i in 0 ..< command_component.number_field_count {
		command_field := &command_component.number_fields[i]
		field_name := ecs.command_number_field_name(command_field)
		for &world_field in world_component.number_fields {
			if world_field.name == field_name {
				world_field.value = command_field.value
				break
			}
		}
	}
	for i in 0 ..< command_component.vec2_field_count {
		command_field := &command_component.vec2_fields[i]
		field_name := ecs.command_vec2_field_name(command_field)
		for &world_field in world_component.vec2_fields {
			if world_field.name == field_name {
				world_field.value = command_field.value
				break
			}
		}
	}
	for i in 0 ..< command_component.vec3_field_count {
		command_field := &command_component.vec3_fields[i]
		field_name := ecs.command_field_name(command_field)
		for &world_field in world_component.vec3_fields {
			if world_field.name == field_name {
				world_field.value = command_field.value
				break
			}
		}
	}
	for i in 0 ..< command_component.vec4_field_count {
		command_field := &command_component.vec4_fields[i]
		field_name := ecs.command_vec4_field_name(command_field)
		for &world_field in world_component.vec4_fields {
			if world_field.name == field_name {
				world_field.value = command_field.value
				break
			}
		}
	}
}

optional_number_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
) -> (
	value: f32,
	found, ok: bool,
) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return 0, false, true
	}
	is_number: c.int
	value = f32(lua_tonumberx(L, -1, &is_number))
	lua_settop(L, -2)
	return value, true, is_number != 0
}

optional_vec2_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
) -> (
	value: Vec2,
	found, ok: bool,
) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return {}, false, true
	}
	value, ok = vec2_argument(L, -1)
	lua_settop(L, -2)
	return value, true, ok
}

optional_vec3_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
) -> (
	value: Vec3,
	found, ok: bool,
) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return {}, false, true
	}
	value, ok = vec3_argument(L, -1)
	lua_settop(L, -2)
	return value, true, ok
}

optional_vec4_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
) -> (
	value: Vec4,
	found, ok: bool,
) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return {}, false, true
	}
	value, ok = vec4_argument(L, -1)
	lua_settop(L, -2)
	return value, true, ok
}

required_vec3_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
) -> (
	value: Vec3,
	ok: bool,
) {
	lua_getfield(L, index, name)
	value, ok = vec3_argument(L, -1)
	lua_settop(L, -2)
	return value, ok
}
