package script

import component "../component"
import ecs "../ecs"
import resources "../resources"
import schedule "../schedule"
import shared "../shared"
import c "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_SCRIPT_CHUNK :: "=" + DEFAULT_SCRIPT
MAX_SCRIPT_SYSTEMS :: schedule.MAX_SYSTEMS
MAX_QUERY_OBJECTS :: 128
World :: shared.World
Vec3 :: shared.Vec3
Transform_Component :: shared.Transform_Component
Custom_Component :: shared.Custom_Component
Named_Vec3 :: shared.Named_Vec3
Component_ID :: shared.Component_ID
Query :: ecs.Query
Query_Term :: ecs.Query_Term
QUERY_OBJECT_KIND: string : "scrapbot.query"
SCHEMA_FIELD_KIND: string : "scrapbot.schema_field"

Run_Result :: struct {
	ran: bool,
	err: string,
}

Source_Options :: struct {
	log_enabled: bool,
	registry: ^component.Registry,
	resource_registry: ^resources.Registry,
	project_root: string,
}

Runtime :: struct {
	L: Lua_State,
	world: ^World,
	registry: component.Registry,
	resource_registry: ^resources.Registry,
	project_root: string,
	log_enabled: bool,
	commands: ecs.Command_Buffer,
	systems: [MAX_SCRIPT_SYSTEMS]Script_System,
	system_count: int,
	query_objects: [MAX_QUERY_OBJECTS]Query_Object,
	query_object_count: int,
	active_system: schedule.System,
	has_active_system: bool,
}

Script_System :: struct {
	callback_ref: c.int,
	declaration: schedule.System,
	query: Query,
	has_query: bool,
	name: [shared.SYSTEM_PROFILE_NAME_CAPACITY]u8,
	name_length: int,
}

Query_Object :: struct {
	query: Query,
	ref: c.int,
}

Transform_Writeback :: struct {
	ref: c.int,
	transform_index: int,
	original: Transform_Component,
	can_write: bool,
}

Custom_Component_Writeback :: struct {
	ref: c.int,
	entity_index: int,
	component_id: Component_ID,
	name: string,
	can_write: bool,
}

Prepared_Transform_Writebacks :: struct {
	transforms: [ecs.MAX_QUERY_TERMS]Transform_Component,
	changed: [ecs.MAX_QUERY_TERMS]bool,
}

Prepared_Custom_Component_Writebacks :: struct {
	components: [ecs.MAX_QUERY_TERMS]ecs.Command_Component,
	changed: [ecs.MAX_QUERY_TERMS]bool,
}

Component_Reference :: struct {
	name: string,
	id: Component_ID,
}

Query_API :: enum {
	Query,
	View,
}

run_project_script :: proc(runtime: ^Runtime, root: string, world: ^World) -> Run_Result {
	return run_project_script_with_options(
		runtime,
		root,
		world,
		Source_Options{log_enabled = true},
	)
}

run_project_script_for_check :: proc(
	runtime: ^Runtime,
	root: string,
	world: ^World,
) -> Run_Result {
	return run_project_script_with_options(runtime, root, world, Source_Options{})
}

run_project_script_with_registry :: proc(
	runtime: ^Runtime,
	root: string,
	world: ^World,
	registry: ^component.Registry,
	options: Source_Options,
) -> Run_Result {
	registry_options := options
	registry_options.registry = registry
	return run_project_script_with_options(runtime, root, world, registry_options)
}

run_project_script_for_check_with_registry :: proc(
	runtime: ^Runtime,
	root: string,
	world: ^World,
	registry: ^component.Registry,
) -> Run_Result {
	return run_project_script_with_registry(runtime, root, world, registry, Source_Options{})
}

run_project_script_with_options :: proc(
	runtime: ^Runtime,
	root: string,
	world: ^World,
	options: Source_Options,
) -> Run_Result {
	result: Run_Result

	script_path, join_err := filepath.join({root, DEFAULT_SCRIPT})
	if join_err != nil {
		result.err = "failed to allocate script path"
		return result
	}
	defer delete(script_path)

	if !os.exists(script_path) {
		return result
	}

	source, read_err := os.read_entire_file(script_path, context.temp_allocator)
	if read_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", script_path, read_err)
		return result
	}

	project_options := options
	project_options.project_root = root
	result = run_source_with_options(
		runtime,
		string(source),
		DEFAULT_SCRIPT_CHUNK,
		world,
		project_options,
	)
	result.ran = result.err == ""
	return result
}

run_source :: proc(runtime: ^Runtime, source, chunk_name: string, world: ^World) -> Run_Result {
	return run_source_with_options(
		runtime,
		source,
		chunk_name,
		world,
		Source_Options{log_enabled = true},
	)
}

run_source_with_registry :: proc(
	runtime: ^Runtime,
	source, chunk_name: string,
	world: ^World,
	registry: ^component.Registry,
	options: Source_Options,
) -> Run_Result {
	registry_options := options
	registry_options.registry = registry
	return run_source_with_options(runtime, source, chunk_name, world, registry_options)
}

run_source_with_options :: proc(
	runtime: ^Runtime,
	source, chunk_name: string,
	world: ^World,
	options: Source_Options,
) -> Run_Result {
	result: Run_Result
	destroy_runtime(runtime)
	runtime^ = {}
	ecs.init_command_buffer(&runtime.commands)
	runtime.world = world
	runtime.log_enabled = options.log_enabled
	runtime.resource_registry = options.resource_registry
	runtime.project_root = options.project_root
	if options.registry != nil {
		runtime.registry = options.registry^
	} else {
		component.init_registry(&runtime.registry)
	}

	L := luaL_newstate()
	if L == nil {
		result.err = "failed to create Luau state"
		return result
	}
	runtime.L = L

	lua_setthreaddata(L, runtime)

	luaL_openlibs(L)
	register_scrapbot_api(L)
	luaL_sandbox(L)
	luaL_sandboxthread(L)

	options := Compile_Options {
		optimization_level = 1,
		debug_level = 1,
	}
	bytecode_size: c.size_t
	bytecode := luau_compile(
		cstring(raw_data(source)),
		c.size_t(len(source)),
		&options,
		&bytecode_size,
	)
	if bytecode == nil {
		result.err = fmt.tprintf("%s: failed to compile Luau source", chunk_name)
		return result
	}
	defer free_luau_bytecode(bytecode)

	chunk_cstring, chunk_err := strings.clone_to_cstring(chunk_name, context.temp_allocator)
	if chunk_err != nil {
		result.err = "failed to allocate Luau chunk name"
		return result
	}
	status := luau_load(L, chunk_cstring, bytecode, bytecode_size, 0)
	if status != LUA_OK {
		result.err = luau_stack_error(L, chunk_name)
		return result
	}

	status = lua_pcall(L, 0, 0, 0)
	if status != LUA_OK {
		result.err = luau_stack_error(L, chunk_name)
		return result
	}

	result.err = validate_world_components(runtime)
	if result.err != "" {
		return result
	}

	result.ran = true
	return result
}

destroy_runtime :: proc(runtime: ^Runtime) {
	if runtime.L != nil {
		for system in runtime.systems[:runtime.system_count] {
			lua_unref(runtime.L, system.callback_ref)
		}
		for query_object in runtime.query_objects[:runtime.query_object_count] {
			lua_unref(runtime.L, query_object.ref)
		}
		lua_close(runtime.L)
	}
	ecs.destroy_command_buffer(&runtime.commands)
	runtime^ = {}
}

rebind_runtime :: proc(runtime: ^Runtime) {
	if runtime != nil && runtime.L != nil {
		lua_setthreaddata(runtime.L, runtime)
	}
}

bind_runtime_world :: proc(runtime: ^Runtime, world: ^World) {
	if runtime == nil {
		return
	}
	ecs.clear_commands(&runtime.commands)
	runtime.world = world
}

step_runtime :: proc(runtime: ^Runtime, world: ^World, delta_seconds: f32) -> string {
	if runtime == nil || runtime.L == nil {
		return ""
	}
	runtime.world = world
	ecs.advance_time(&world.time, delta_seconds)
	L := runtime.L
	scheduled_systems: [MAX_SCRIPT_SYSTEMS]schedule.System
	for system, index in runtime.systems[:runtime.system_count] {
		scheduled_systems[index] = system.declaration
	}
	plan := schedule.build_plan(scheduled_systems[:runtime.system_count])

	for batch in plan.batches[:plan.batch_count] {
		for i in 0 ..< batch.system_count {
			system_index := batch.system_indices[i]
			system := runtime.systems[system_index]
			if err := run_script_system(runtime, L, system, world.time); err != "" {
				ecs.clear_commands(&runtime.commands)
				return err
			}
		}
	}
	return ecs.apply_commands(world, &runtime.commands)
}

run_script_system :: proc(
	runtime: ^Runtime,
	L: Lua_State,
	system: Script_System,
	time: shared.Time_Resource,
) -> string {
	runtime.active_system = system.declaration
	runtime.has_active_system = true
	defer {
		runtime.has_active_system = false
		runtime.active_system = {}
	}

	if system.has_query {
		for i in 0 ..< ecs.query_count(runtime.world, system.query) {
			entity_index, entity_ok := ecs.query_entity_at(runtime.world, system.query, i)
			if !entity_ok {
				continue
			}
			lua_rawgeti(L, LUA_REGISTRYINDEX, system.callback_ref)
			push_time_table(L, time)
			push_entity_table(L, runtime.world, entity_index)
			writebacks: [ecs.MAX_QUERY_TERMS]Transform_Writeback
			writeback_count := 0
			component_writebacks: [ecs.MAX_QUERY_TERMS]Custom_Component_Writeback
			component_writeback_count := 0
			for term_index in 0 ..< system.query.term_count {
				term := system.query.terms[term_index]
				push_query_component_table(L, runtime.world, entity_index, term)
				if term.name == "scrapbot.transform" {
					transform_index := runtime.world.entities[entity_index].transform_index
					if transform_index >= 0 && transform_index < len(runtime.world.transforms) {
						writebacks[writeback_count] = Transform_Writeback {
							ref = lua_ref(L, -1),
							transform_index = transform_index,
							original = runtime.world.transforms[transform_index],
							can_write = system_allows_component_access(
								system.declaration,
								"scrapbot.transform",
								.Write,
							),
						}
						writeback_count += 1
					}
				} else if query_term_is_custom_schema_component(&runtime.registry, term) {
					if _, ok := ecs.custom_component_for_entity_ref(
						runtime.world,
						entity_index,
						term.component_id,
						term.name,
					); ok {
						component_writebacks[component_writeback_count] =
							Custom_Component_Writeback {
								ref = lua_ref(L, -1),
								entity_index = entity_index,
								component_id = term.component_id,
								name = term.name,
								can_write = system_allows_component_access(
									system.declaration,
									term.name,
									.Write,
								),
							}
						component_writeback_count += 1
					}
				}
			}
			status := lua_pcall(L, c.int(system.query.term_count + 2), 0, 0)
			if status != LUA_OK {
				for writeback in writebacks[:writeback_count] {
					lua_unref(L, writeback.ref)
				}
				for writeback in component_writebacks[:component_writeback_count] {
					lua_unref(L, writeback.ref)
				}
				return luau_stack_error(L, "Luau system")
			}
			prepared_transforms: Prepared_Transform_Writebacks
			transform_err := prepare_transform_writebacks(
				L,
				writebacks[:writeback_count],
				&prepared_transforms,
			)
			prepared_components: Prepared_Custom_Component_Writebacks
			component_err := prepare_custom_component_writebacks(
				L,
				runtime,
				component_writebacks[:component_writeback_count],
				&prepared_components,
			)
			if transform_err != "" {
				return transform_err
			}
			if component_err != "" {
				return component_err
			}
			apply_transform_writebacks(
				runtime.world,
				writebacks[:writeback_count],
				&prepared_transforms,
			)
			apply_custom_component_writebacks(
				runtime.world,
				component_writebacks[:component_writeback_count],
				&prepared_components,
			)
		}
		return ""
	}

	lua_rawgeti(L, LUA_REGISTRYINDEX, system.callback_ref)
	push_time_table(L, time)
	status := lua_pcall(L, 1, 0, 0)
	if status != LUA_OK {
		return luau_stack_error(L, "Luau system")
	}
	return ""
}

push_time_table :: proc "c" (L: Lua_State, time: shared.Time_Resource) {
	lua_createtable(L, 0, 4)
	lua_pushnumber(L, f64(time.delta_time)); lua_setfield(L, -2, "delta_time")
	lua_pushnumber(L, f64(time.smooth_delta_time)); lua_setfield(L, -2, "smooth_delta_time")
	lua_pushnumber(L, time.elapsed_time); lua_setfield(L, -2, "elapsed_time")
	lua_pushinteger(L, c.ptrdiff_t(time.frame_index)); lua_setfield(L, -2, "frame_index")
}

prepare_transform_writebacks :: proc "c" (
	L: Lua_State,
	writebacks: []Transform_Writeback,
	prepared: ^Prepared_Transform_Writebacks,
) -> string {
	first_err := ""

	for writeback, index in writebacks {
		lua_rawgeti(L, LUA_REGISTRYINDEX, writeback.ref)
		transform, err := read_full_transform_table(L, -1)
		lua_settop(L, -2)
		lua_unref(L, writeback.ref)
		if err != "" {
			if first_err == "" {
				if !writeback.can_write {
					first_err = "Luau system: system access declaration does not permit component write"
				} else {
					first_err = "Luau system: invalid scrapbot.transform payload"
				}
			}
			continue
		}
		if transform == writeback.original {
			continue
		}
		if !writeback.can_write {
			if first_err == "" {
				first_err = "Luau system: system access declaration does not permit component write"
			}
			continue
		}
		prepared.transforms[index] = transform
		prepared.changed[index] = true
	}

	return first_err
}

apply_transform_writebacks :: proc "c" (
	world: ^World,
	writebacks: []Transform_Writeback,
	prepared: ^Prepared_Transform_Writebacks,
) {
	for writeback, index in writebacks {
		if world != nil &&
		   writeback.transform_index >= 0 &&
		   writeback.transform_index < len(world.transforms) {
			if prepared.changed[index] {
				world.transforms[writeback.transform_index] = prepared.transforms[index]
			}
		}
	}
}

prepare_custom_component_writebacks :: proc(
	L: Lua_State,
	runtime: ^Runtime,
	writebacks: []Custom_Component_Writeback,
	prepared: ^Prepared_Custom_Component_Writebacks,
) -> string {
	first_err := ""

	for writeback, index in writebacks {
		lua_rawgeti(L, LUA_REGISTRYINDEX, writeback.ref)
		component_ref := Component_Reference {
			name = writeback.name,
			id = writeback.component_id,
		}
		component_data: ecs.Command_Component
		err := read_custom_component_payload(L, runtime, component_ref, -1, &component_data)
		lua_settop(L, -2)
		lua_unref(L, writeback.ref)

		if err != "" {
			if first_err == "" {
				if !writeback.can_write {
					first_err = "Luau system: system access declaration does not permit component write"
				} else {
					first_err = "Luau system: invalid custom component payload"
				}
			}
			continue
		}

		world_component, ok := ecs.custom_component_for_entity_ref(
			runtime.world,
			writeback.entity_index,
			writeback.component_id,
			writeback.name,
		)
		if !ok {
			continue
		}
		if custom_component_matches_command(world_component^, &component_data) {
			continue
		}
		if !writeback.can_write {
			if first_err == "" {
				first_err = "Luau system: system access declaration does not permit component write"
			}
			continue
		}
		prepared.components[index] = component_data
		prepared.changed[index] = true
	}

	return first_err
}

apply_custom_component_writebacks :: proc(
	world: ^World,
	writebacks: []Custom_Component_Writeback,
	prepared: ^Prepared_Custom_Component_Writebacks,
) {
	for writeback, index in writebacks {
		if !prepared.changed[index] {
			continue
		}
		world_component, ok := ecs.custom_component_for_entity_ref(
			world,
			writeback.entity_index,
			writeback.component_id,
			writeback.name,
		)
		if !ok {
			continue
		}
		apply_custom_component_command(world_component, &prepared.components[index])
	}
}

system_allows_component_access :: proc "c" (
	declaration: schedule.System,
	component_name: string,
	mode: schedule.Access_Mode,
) -> bool {
	if declaration.access_count == 0 {
		return true
	}
	for i in 0 ..< declaration.access_count {
		access := declaration.accesses[i]
		if access.component != component_name {
			continue
		}
		if mode == .Read {
			if access.mode == .Read || access.mode == .Write {
				return true
			}
			continue
		}
		if access.mode == .Write {
			return true
		}
	}
	return false
}

query_term_is_custom_schema_component :: proc "c" (
	registry: ^component.Registry,
	term: Query_Term,
) -> bool {
	definition, ok := component.find_definition_by_id(registry, term.component_id)
	return(
		ok &&
		definition.name == term.name &&
		(definition.owner == .Project || definition.owner == .Library) \
	)
}

component_ref_is_custom_schema_component :: proc "c" (
	registry: ^component.Registry,
	component_ref: Component_Reference,
) -> bool {
	definition, ok := component.find_definition_by_id(registry, component_ref.id)
	return(
		ok &&
		definition.name == component_ref.name &&
		(definition.owner == .Project || definition.owner == .Library) \
	)
}

step_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	runtime := cast(^Runtime)data
	return step_runtime(runtime, world, delta_seconds)
}
