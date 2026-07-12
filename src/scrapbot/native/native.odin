package native

import c "core:c"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import component "../component"
import ecs "../ecs"
import api "../extension_api"
import schedule "../schedule"
import shared "../shared"

EXTENSIONS_DIR :: "build/extensions"
EXTENSIONS_MANIFEST :: ".scrapbot-extensions"
REGISTER_SYMBOL :: "scrapbot_extension_register"
MAX_EXTENSIONS :: 32
MAX_NATIVE_SYSTEMS :: schedule.MAX_SYSTEMS

Extension_Stamp :: struct {
	exists: bool,
	modified_ns: i64,
	size: i64,
}

Source_Stamp :: struct {
	exists: bool,
	modified_ns: i64,
	size: i64,
	entry_count: int,
}

Extension :: struct {
	path: string,
	stamp: Extension_Stamp,
	library: dynlib.Library,
}

Native_System :: struct {
	name: string,
	declaration: schedule.System,
	callback: api.System_Proc,
	userdata: rawptr,
}

Step_Context :: struct {
	world: ^shared.World,
	system: ^Native_System,
	commands: ^ecs.Command_Buffer,
	registry: ^component.Registry,
}

Source_Target :: struct {
	name: string,
	source: string,
	stamp: Source_Stamp,
}

Extension_Set :: struct {
	extensions: [MAX_EXTENSIONS]Extension,
	extension_count: int,
	systems: [MAX_NATIVE_SYSTEMS]Native_System,
	system_count: int,
	registry: ^component.Registry,
}

Source_Set :: struct {
	targets: [MAX_EXTENSIONS]Source_Target,
	target_count: int,
}

Load_Result :: struct {
	loaded_count: int,
	err: string,
}

Build_Result :: struct {
	built_count: int,
	err: string,
}

build_project_extensions :: proc(root: string, targets: []shared.Native_Extension_Target) -> Build_Result {
	result: Build_Result
	extensions_dir, dir_err := project_extensions_dir(root)
	if dir_err != "" {
		result.err = dir_err
		return result
	}
	defer delete(extensions_dir)

	if len(targets) == 0 {
		if os.exists(extensions_dir) {
			if err := write_extensions_manifest(extensions_dir, nil); err != "" {
				result.err = err
			}
		}
		return result
	}

	if !os.exists(extensions_dir) {
		if err := os.make_directory_all(extensions_dir); err != nil {
			result.err = fmt.tprintf("failed to create native extension output directory: %v", err)
			return result
		}
	}

	output_names: [dynamic]string
	defer {
		for name in output_names {
			delete(name)
		}
		delete(output_names)
	}

	for target in targets {
		output_name, err := build_extension(root, extensions_dir, target)
		if err != "" {
			result.err = err
			return result
		}
		append(&output_names, output_name)
		result.built_count += 1
	}

	if err := write_extensions_manifest(extensions_dir, output_names[:]); err != "" {
		result.err = err
		return result
	}

	return result
}

sync_project_extension_sources :: proc(
	set: ^Source_Set,
	root: string,
	targets: []shared.Native_Extension_Target,
) -> string {
	destroy_source_set(set)
	if len(targets) > MAX_EXTENSIONS {
		return "too many native extension source targets"
	}

	for target in targets {
		cloned_name, name_err := strings.clone(target.name)
		if name_err != nil {
			destroy_source_set(set)
			return "failed to retain native extension source target name"
		}

		cloned_source, source_err := strings.clone(target.source)
		if source_err != nil {
			delete(cloned_name)
			destroy_source_set(set)
			return "failed to retain native extension source target path"
		}

		set.targets[set.target_count] = Source_Target {
			name = cloned_name,
			source = cloned_source,
			stamp = extension_source_stamp(root, target.source),
		}
		set.target_count += 1
	}

	return ""
}

destroy_source_set :: proc(set: ^Source_Set) {
	if set == nil {
		return
	}
	for &target in set.targets[:set.target_count] {
		delete(target.name)
		delete(target.source)
	}
	set^ = {}
}

project_extension_sources_changed :: proc(set: ^Source_Set, root: string) -> bool {
	if set == nil {
		return false
	}
	for target in set.targets[:set.target_count] {
		if !source_stamps_equal(target.stamp, extension_source_stamp(root, target.source)) {
			return true
		}
	}
	return false
}

build_extension :: proc(root, extensions_dir: string, target: shared.Native_Extension_Target) -> (output_name: string, err: string) {
	source_dir, source_err := filepath.join({root, target.source})
	if source_err != nil {
		return "", fmt.tprintf("failed to allocate native extension source path for %s", target.name)
	}
	defer delete(source_dir)

	if !os.exists(source_dir) {
		return "", fmt.tprintf("native extension %s source does not exist: %s", target.name, target.source)
	}

	source_stamp := extension_source_stamp(root, target.source)
	temp_output_name := fmt.tprintf(
		"%s-%d-%d-%d.%s",
		target.name,
		source_stamp.modified_ns,
		source_stamp.size,
		source_stamp.entry_count,
		dynlib.LIBRARY_FILE_EXTENSION,
	)
	cloned_output_name, clone_err := strings.clone(temp_output_name)
	if clone_err != nil {
		return "", "failed to retain native extension output name"
	}
	output_name = cloned_output_name
	output_path, output_err := filepath.join({extensions_dir, output_name})
	if output_err != nil {
		delete(output_name)
		return "", fmt.tprintf("failed to allocate native extension output path for %s", target.name)
	}
	defer delete(output_path)

	out_arg := fmt.tprintf("-out:%s", output_path)
	command := []string {
		"odin",
		"build",
		source_dir,
		"-build-mode:shared",
		out_arg,
		"-collection:scrapbot=src/scrapbot",
	}
	state, stdout, stderr, exec_err := os.process_exec(os.Process_Desc{command = command}, context.allocator)
	if len(stdout) > 0 {
		defer delete(stdout)
	}
	if len(stderr) > 0 {
		defer delete(stderr)
	}
	if exec_err != nil {
		delete(output_name)
		return "", fmt.tprintf("failed to build native extension %s: %v", target.name, exec_err)
	}
	if !state.success {
		output := strings.trim_space(string(stderr))
		if output == "" {
			output = strings.trim_space(string(stdout))
		}
		if output == "" {
			delete(output_name)
			return "", fmt.tprintf("failed to build native extension %s: odin exited with code %d", target.name, state.exit_code)
		}
		delete(output_name)
		return "", fmt.tprintf("failed to build native extension %s:\n%s", target.name, output)
	}
	return output_name, ""
}

load_project_extensions :: proc(set: ^Extension_Set, root: string, registry: ^component.Registry) -> Load_Result {
	destroy_extension_set(set)
	set.registry = registry
	defer set.registry = nil

	extension_paths, paths_err := project_extension_paths(root)
	if paths_err != "" {
		return Load_Result{err = paths_err}
	}
	defer destroy_extension_paths(extension_paths)

	for path in extension_paths {
		if set.extension_count >= MAX_EXTENSIONS {
			return Load_Result{loaded_count = set.extension_count, err = "too many native extensions"}
		}
		if err := load_extension(set, path); err != "" {
			return Load_Result{loaded_count = set.extension_count, err = err}
		}
	}

	return Load_Result{loaded_count = set.extension_count}
}

destroy_extension_set :: proc(set: ^Extension_Set) {
	if set == nil {
		return
	}
	for &extension in set.extensions[:set.extension_count] {
		if extension.library != nil {
			dynlib.unload_library(extension.library)
		}
		delete(extension.path)
	}
	set^ = {}
}

project_extensions_changed :: proc(set: ^Extension_Set, root: string) -> bool {
	extension_paths, paths_err := project_extension_paths(root)
	if paths_err != "" {
		return set != nil && set.extension_count > 0
	}
	defer destroy_extension_paths(extension_paths)

	if set == nil {
		return len(extension_paths) > 0
	}
	if len(extension_paths) != set.extension_count {
		return true
	}

	for path, index in extension_paths {
		if set.extensions[index].path != path {
			return true
		}
		if !extension_stamps_equal(set.extensions[index].stamp, extension_stamp(path)) {
			return true
		}
	}
	return false
}

load_extension :: proc(set: ^Extension_Set, path: string) -> string {
	library, ok := dynlib.load_library(path)
	if !ok {
		return fmt.tprintf("failed to load native extension %s: %s", path, dynlib.last_error())
	}

	symbol, found := dynlib.symbol_address(library, REGISTER_SYMBOL)
	if !found {
		dynlib.unload_library(library)
		return fmt.tprintf("native extension %s does not export %s", path, REGISTER_SYMBOL)
	}

	register := cast(api.Register_Proc)symbol
	host_api := api.API {
		abi_version = api.ABI_VERSION,
		userdata = set,
		register_library_component = extension_register_library_component,
		register_system = extension_register_system,
	}
	if register_err := register(&host_api); register_err != nil {
		dynlib.unload_library(library)
		return fmt.tprintf("native extension %s failed to register: %s", path, string(register_err))
	}

	cloned_path, clone_err := strings.clone(path)
	if clone_err != nil {
		dynlib.unload_library(library)
		return "failed to retain native extension path"
	}

	set.extensions[set.extension_count] = Extension {
		path = cloned_path,
		stamp = extension_stamp(path),
		library = library,
	}
	set.extension_count += 1
	return ""
}

extension_register_library_component :: proc "c" (
	host_api: ^api.API,
	definition: ^api.Component_Definition,
) -> cstring {
	if host_api == nil || host_api.userdata == nil || definition == nil {
		return "native extension registration API is not available"
	}
	set := cast(^Extension_Set)host_api.userdata
	if set.registry == nil {
		return "native extension component registry is not available"
	}
	if definition.name == nil {
		return "native extension component name is required"
	}
	if definition.field_count < 0 || definition.field_count > api.MAX_COMPONENT_FIELDS {
		return "native extension component has too many fields"
	}

	component_definition: component.Definition
	component_definition.name = string(definition.name)
	component_definition.field_count = int(definition.field_count)
	for i in 0..<component_definition.field_count {
		field := definition.fields[i]
		if field.name == nil {
			return "native extension component field name is required"
		}
		field_type, field_type_ok := extension_field_type(field.field_type)
		if !field_type_ok {
			return "native extension component field type is not supported"
		}
		component_definition.fields[i] = component.Field_Definition {
			name = string(field.name),
			field_type = field_type,
		}
	}

	if err := component.register_library_component(set.registry, component_definition); err != "" {
		return "native extension component registration failed"
	}
	return nil
}

extension_register_system :: proc "c" (
	host_api: ^api.API,
	definition: ^api.System_Definition,
) -> cstring {
	if host_api == nil || host_api.userdata == nil || definition == nil {
		return "native extension registration API is not available"
	}
	set := cast(^Extension_Set)host_api.userdata
	if set.registry == nil {
		return "native extension component registry is not available"
	}
	if set.system_count >= MAX_NATIVE_SYSTEMS {
		return "too many native systems"
	}
	if definition.name == nil {
		return "native system name is required"
	}
	if definition.callback == nil {
		return "native system callback is required"
	}
	if definition.access_count < 0 || definition.access_count > api.MAX_SYSTEM_ACCESSES {
		return "native system has too many access declarations"
	}

	system: Native_System
	system.name = string(definition.name)
	system.callback = definition.callback
	system.userdata = definition.userdata

	for i in 0..<int(definition.access_count) {
		access := definition.accesses[i]
		if access.component == nil {
			return "native system access component is required"
		}
		component_name := string(access.component)
		if _, found := component.find_definition(set.registry, component_name); !found {
			return "native system access references unregistered component"
		}
		mode, mode_ok := extension_access_mode(access.mode)
		if !mode_ok {
			return "native system access mode is not supported"
		}
		system.declaration.accesses[system.declaration.access_count] = schedule.Access {
			component = component_name,
			mode      = mode,
		}
		system.declaration.access_count += 1
	}

	set.systems[set.system_count] = system
	set.system_count += 1
	return nil
}

extension_field_type :: proc "c" (field_type: api.Field_Type) -> (component.Field_Type, bool) {
	#partial switch field_type {
	case .Vec3:
		return .Vec3, true
	}
	return {}, false
}

extension_access_mode :: proc "c" (mode: api.Access_Mode) -> (schedule.Access_Mode, bool) {
	#partial switch mode {
	case .Read:
		return .Read, true
	case .Write:
		return .Write, true
	}
	return {}, false
}

step_system :: proc(
	system: ^Native_System,
	world: ^shared.World,
	commands: ^ecs.Command_Buffer,
	registry: ^component.Registry,
	delta_seconds: f32,
) -> string {
	if system == nil || system.callback == nil {
		return ""
	}

	step_context := Step_Context {
		world = world,
		system = system,
		commands = commands,
		registry = registry,
	}
	ctx := api.System_Context {
		abi_version = api.ABI_VERSION,
		userdata = system.userdata,
		host = &step_context,
		delta_seconds = delta_seconds,
		query_count = system_query_count,
		query_entity_at = system_query_entity_at,
		get_transform = system_get_transform,
		set_transform = system_set_transform,
		get_vec3_field = system_get_vec3_field,
		set_vec3_field = system_set_vec3_field,
		spawn = system_spawn,
		despawn = system_despawn,
		add_transform = system_add_transform,
		add_component = system_add_component,
		remove_component = system_remove_component,
	}

	if err := system.callback(&ctx); err != nil {
		return fmt.tprintf("native system %s: %s", system.name, string(err))
	}
	return ""
}

system_query_count :: proc "c" (
	ctx: ^api.System_Context,
	terms: [^]api.Query_Term,
	term_count: c.int,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok {
		return -1
	}
	query, query_ok := system_query_from_terms(step, terms, term_count)
	if !query_ok {
		return -1
	}
	return c.int(ecs.query_count(step.world, query))
}

system_query_entity_at :: proc "c" (
	ctx: ^api.System_Context,
	terms: [^]api.Query_Term,
	term_count: c.int,
	visible_index: c.int,
) -> api.Entity {
	step, ok := system_step_context(ctx)
	if !ok {
		return api.Entity{index = -1}
	}
	query, query_ok := system_query_from_terms(step, terms, term_count)
	if !query_ok {
		return api.Entity{index = -1}
	}
	entity_index, entity_ok := ecs.query_entity_at(step.world, query, int(visible_index))
	if !entity_ok {
		return api.Entity{index = -1}
	}
	return api.Entity {
		index = c.int(entity_index),
		generation = step.world.entities[entity_index].id.generation,
	}
}

system_get_transform :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	transform: ^api.Transform,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok || transform == nil || !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Read) {
		return 0
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return 0
	}
	world_entity := step.world.entities[entity_index]
	if world_entity.transform_index < 0 || world_entity.transform_index >= len(step.world.transforms) {
		return 0
	}
	transform^ = api_transform_from_shared(step.world.transforms[world_entity.transform_index])
	return 1
}

system_set_transform :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	transform: ^api.Transform,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok || transform == nil || !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Write) {
		return 0
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return 0
	}
	world_entity := step.world.entities[entity_index]
	if world_entity.transform_index < 0 || world_entity.transform_index >= len(step.world.transforms) {
		return 0
	}
	step.world.transforms[world_entity.transform_index] = shared_transform_from_api(transform^)
	return 1
}

system_get_vec3_field :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	component_name: cstring,
	field_name: cstring,
	value: ^api.Vec3,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok || component_name == nil || field_name == nil || value == nil {
		return 0
	}
	name := string(component_name)
	if !system_allows_component_access(step.system.declaration, name, .Read) {
		return 0
	}
	world_component, component_ok := system_custom_component(step.world, entity, name)
	if !component_ok {
		return 0
	}
	for field in world_component.vec3_fields {
		if field.name == string(field_name) {
			value^ = api_vec3_from_shared(field.value)
			return 1
		}
	}
	return 0
}

system_set_vec3_field :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	component_name: cstring,
	field_name: cstring,
	value: ^api.Vec3,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok || component_name == nil || field_name == nil || value == nil {
		return 0
	}
	name := string(component_name)
	if !system_allows_component_access(step.system.declaration, name, .Write) {
		return 0
	}
	world_component, component_ok := system_custom_component(step.world, entity, name)
	if !component_ok {
		return 0
	}
	for &field in world_component.vec3_fields {
		if field.name == string(field_name) {
			field.value = shared_vec3_from_api(value^)
			return 1
		}
	}
	return 0
}

system_spawn :: proc "c" (ctx: ^api.System_Context, options: ^api.Spawn_Options) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if options == nil {
		return "spawn options are not available"
	}

	name := ""
	if options.name != nil {
		name = string(options.name)
	}
	spawn: ecs.Spawn_Command
	if err := ecs.init_spawn_command(&spawn, name); err != "" {
		return cstring(raw_data(err))
	}

	if options.transform != nil {
		if !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Write) {
			return "native system does not have write access to scrapbot.transform"
		}
		if err := ecs.spawn_set_transform(&spawn, shared_transform_from_api(options.transform^)); err != "" {
			return cstring(raw_data(err))
		}
	}

	if options.component_count < 0 || options.component_count > ecs.MAX_COMMAND_COMPONENTS {
		return "invalid spawn component count"
	}
	if options.component_count > 0 && options.components == nil {
		return "spawn components are not available"
	}
	for i in 0..<int(options.component_count) {
		payload := options.components[i]
		if payload.component == nil {
			return "spawn component name is required"
		}
		name := string(payload.component)
		if !system_allows_component_access(step.system.declaration, name, .Write) {
			return "native system does not have write access to spawn component"
		}
		command_component: ecs.Command_Component
		if err := command_component_from_payload(step, &payload, &command_component); err != "" {
			return cstring(raw_data(err))
		}
		if err := ecs.spawn_add_custom_component(&spawn, command_component); err != "" {
			return cstring(raw_data(err))
		}
	}

	if err := ecs.queue_spawn_command(step.commands, spawn); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_despawn :: proc "c" (ctx: ^api.System_Context, entity: api.Entity) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if !ecs.entity_is_current(step.world, int(entity.index), entity.generation) {
		return "native despawn entity is stale"
	}
	if err := ecs.queue_despawn(step.commands, int(entity.index), entity.generation); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_add_transform :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	transform: ^api.Transform,
) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if transform == nil {
		return "native transform payload is not available"
	}
	if !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Write) {
		return "native system does not have write access to scrapbot.transform"
	}
	if !ecs.entity_is_current(step.world, int(entity.index), entity.generation) {
		return "native add component entity is stale"
	}
	if err := ecs.queue_add_transform(step.commands, int(entity.index), entity.generation, shared_transform_from_api(transform^)); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_add_component :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	payload: ^api.Component_Payload,
) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if payload == nil || payload.component == nil {
		return "native component payload is not available"
	}
	name := string(payload.component)
	if !system_allows_component_access(step.system.declaration, name, .Write) {
		return "native system does not have write access to component"
	}
	if !ecs.entity_is_current(step.world, int(entity.index), entity.generation) {
		return "native add component entity is stale"
	}
	command_component: ecs.Command_Component
	if err := command_component_from_payload(step, payload, &command_component); err != "" {
		return cstring(raw_data(err))
	}
	if err := ecs.queue_add_custom_component(step.commands, int(entity.index), entity.generation, command_component); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_remove_component :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	component_name: cstring,
) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if component_name == nil {
		return "native remove component name is required"
	}
	name := string(component_name)
	if !system_allows_component_access(step.system.declaration, name, .Write) {
		return "native system does not have write access to component"
	}
	if !ecs.entity_is_current(step.world, int(entity.index), entity.generation) {
		return "native remove component entity is stale"
	}

	component_id := shared.INVALID_COMPONENT_ID
	if name != "scrapbot.transform" {
		definition, found := component.find_definition(step.registry, name)
		if !found || (definition.owner != .Project && definition.owner != .Library) {
			return "native component removal only supports scrapbot.transform and schema-backed custom components"
		}
		component_id = definition.id
	}
	if err := ecs.queue_remove_component(step.commands, int(entity.index), entity.generation, component_id, name); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_step_context :: proc "c" (ctx: ^api.System_Context) -> (^Step_Context, bool) {
	if ctx == nil || ctx.host == nil {
		return nil, false
	}
	step := cast(^Step_Context)ctx.host
	return step, step.world != nil && step.system != nil
}

command_component_from_payload :: proc "c" (
	step: ^Step_Context,
	payload: ^api.Component_Payload,
	command_component: ^ecs.Command_Component,
) -> string {
	if step == nil || step.registry == nil {
		return "native component registry is not available"
	}
	if payload == nil || payload.component == nil {
		return "native component payload is not available"
	}
	definition, found := component.find_definition(step.registry, string(payload.component))
	if !found || (definition.owner != .Project && definition.owner != .Library) {
		return "native component payload references an unregistered component"
	}
	if definition.field_count < 0 || definition.field_count > ecs.MAX_COMMAND_FIELDS {
		return "native component payload has too many fields"
	}
	if payload.vec3_field_count < 0 || payload.vec3_field_count > ecs.MAX_COMMAND_FIELDS {
		return "native component payload has invalid field count"
	}
	if payload.vec3_field_count > 0 && payload.vec3_fields == nil {
		return "native component payload fields are not available"
	}

	if err := ecs.init_command_component(command_component, definition.id, definition.name); err != "" {
		return err
	}

	for i in 0..<definition.field_count {
		field := definition.fields[i]
		if field.field_type != component.Field_Type.Vec3 {
			return "unsupported component field type"
		}
		value, found := payload_vec3_field(payload, field.name)
		if !found {
			return "component payload is missing a required field"
		}
		if err := ecs.command_component_add_vec3(command_component, field.name, shared_vec3_from_api(value)); err != "" {
			return err
		}
	}

	return ""
}

payload_vec3_field :: proc "c" (payload: ^api.Component_Payload, field_name: string) -> (api.Vec3, bool) {
	if payload == nil || payload.vec3_fields == nil {
		return {}, false
	}
	for i in 0..<int(payload.vec3_field_count) {
		field := payload.vec3_fields[i]
		if field.name != nil && string(field.name) == field_name {
			return field.value, true
		}
	}
	return {}, false
}

system_query_from_terms :: proc "c" (
	step: ^Step_Context,
	terms: [^]api.Query_Term,
	term_count: c.int,
) -> (ecs.Query, bool) {
	if step == nil || terms == nil || term_count <= 0 || term_count > api.MAX_QUERY_TERMS {
		return {}, false
	}

	query: ecs.Query
	for i in 0..<int(term_count) {
		term := terms[i]
		if term.component == nil {
			return {}, false
		}
		name := string(term.component)
		if !system_allows_component_access(step.system.declaration, name, .Read) {
			return {}, false
		}
		query.terms[query.term_count] = ecs.Query_Term {
			component_id = shared.INVALID_COMPONENT_ID,
			name = name,
		}
		query.term_count += 1
	}
	return query, true
}

system_custom_component :: proc "c" (
	world: ^shared.World,
	entity: api.Entity,
	component_name: string,
) -> (^shared.Custom_Component, bool) {
	entity_index := int(entity.index)
	if !ecs.entity_is_current(world, entity_index, entity.generation) {
		return nil, false
	}
	return ecs.custom_component_for_entity_ref(
		world,
		entity_index,
		shared.INVALID_COMPONENT_ID,
		component_name,
	)
}

system_allows_component_access :: proc "c" (
	declaration: schedule.System,
	component_name: string,
	mode: schedule.Access_Mode,
) -> bool {
	if declaration.access_count == 0 {
		return true
	}
	for i in 0..<declaration.access_count {
		access := declaration.accesses[i]
		if access.component != component_name {
			continue
		}
		if mode == .Read && (access.mode == .Read || access.mode == .Write) {
			return true
		}
		if mode == .Write && access.mode == .Write {
			return true
		}
	}
	return false
}

api_transform_from_shared :: proc "c" (transform: shared.Transform_Component) -> api.Transform {
	return api.Transform {
		position = api_vec3_from_shared(transform.position),
		rotation = api_vec3_from_shared(transform.rotation),
		scale    = api_vec3_from_shared(transform.scale),
	}
}

shared_transform_from_api :: proc "c" (transform: api.Transform) -> shared.Transform_Component {
	return shared.Transform_Component {
		position = shared_vec3_from_api(transform.position),
		rotation = shared_vec3_from_api(transform.rotation),
		scale    = shared_vec3_from_api(transform.scale),
	}
}

api_vec3_from_shared :: proc "c" (value: shared.Vec3) -> api.Vec3 {
	return api.Vec3{x = value.x, y = value.y, z = value.z}
}

shared_vec3_from_api :: proc "c" (value: api.Vec3) -> shared.Vec3 {
	return shared.Vec3{x = value.x, y = value.y, z = value.z}
}

project_extension_paths :: proc(root: string) -> (paths: []string, err: string) {
	extensions_dir, dir_err := project_extensions_dir(root)
	if dir_err != "" {
		return nil, dir_err
	}
	defer delete(extensions_dir)

	if !os.exists(extensions_dir) {
		return nil, ""
	}

	manifest_paths, manifest_found, manifest_err := project_extension_manifest_paths(extensions_dir)
	if manifest_err != "" {
		return nil, manifest_err
	}
	if manifest_found {
		return manifest_paths, ""
	}

	entries, read_err := os.read_all_directory_by_path(extensions_dir, context.temp_allocator)
	if read_err != nil {
		return nil, fmt.tprintf("failed to read native extension directory: %v", read_err)
	}

	builder: [dynamic]string
	for entry in entries {
		if entry.type != .Regular {
			continue
		}
		if !strings.has_suffix(entry.name, "." + dynlib.LIBRARY_FILE_EXTENSION) {
			continue
		}
		path, path_err := filepath.join({extensions_dir, entry.name})
		if path_err != nil {
			destroy_extension_paths(builder[:])
			return nil, "failed to allocate native extension path"
		}
		append(&builder, path)
	}

	paths = make([]string, len(builder))
	copy(paths, builder[:])
	delete(builder)
	sort_strings(paths)
	return paths, ""
}

write_extensions_manifest :: proc(extensions_dir: string, output_names: []string) -> string {
	manifest_path, path_err := filepath.join({extensions_dir, EXTENSIONS_MANIFEST})
	if path_err != nil {
		return "failed to allocate native extension manifest path"
	}
	defer delete(manifest_path)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for name in output_names {
		strings.write_string(&builder, name)
		strings.write_rune(&builder, '\n')
	}

	if err := os.write_entire_file(manifest_path, strings.to_string(builder)); err != nil {
		return fmt.tprintf("failed to write native extension manifest: %v", err)
	}
	return ""
}

project_extension_manifest_paths :: proc(extensions_dir: string) -> (paths: []string, found: bool, err: string) {
	manifest_path, path_err := filepath.join({extensions_dir, EXTENSIONS_MANIFEST})
	if path_err != nil {
		return nil, false, "failed to allocate native extension manifest path"
	}
	defer delete(manifest_path)

	if !os.exists(manifest_path) {
		return nil, false, ""
	}

	manifest, read_err := os.read_entire_file(manifest_path, context.temp_allocator)
	if read_err != nil {
		return nil, true, fmt.tprintf("failed to read native extension manifest: %v", read_err)
	}

	builder: [dynamic]string
	text := string(manifest)
	for raw_line in strings.split_lines_iterator(&text) {
		name := strings.trim_space(raw_line)
		if name == "" {
			continue
		}
		path, join_err := filepath.join({extensions_dir, name})
		if join_err != nil {
			destroy_extension_paths(builder[:])
			return nil, true, "failed to allocate native extension manifest entry path"
		}
		append(&builder, path)
	}

	paths = make([]string, len(builder))
	copy(paths, builder[:])
	delete(builder)
	return paths, true, ""
}

project_extensions_dir :: proc(root: string) -> (path: string, err: string) {
	out, join_err := filepath.join({root, EXTENSIONS_DIR})
	if join_err != nil {
		return "", "failed to allocate native extension directory path"
	}
	return out, ""
}

destroy_extension_paths :: proc(paths: []string) {
	for path in paths {
		delete(path)
	}
	delete(paths)
}

sort_strings :: proc(values: []string) {
	for i in 1..<len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j - 1] > value {
			values[j] = values[j - 1]
			j -= 1
		}
		values[j] = value
	}
}

extension_stamp :: proc(path: string) -> Extension_Stamp {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return {}
	}
	defer os.file_info_delete(fi, context.temp_allocator)

	return Extension_Stamp {
		exists = true,
		modified_ns = time.to_unix_nanoseconds(fi.modification_time),
		size = fi.size,
	}
}

extension_stamps_equal :: proc(a, b: Extension_Stamp) -> bool {
	return a.exists == b.exists && a.modified_ns == b.modified_ns && a.size == b.size
}

extension_source_stamp :: proc(root, source: string) -> Source_Stamp {
	source_dir, source_err := filepath.join({root, source})
	if source_err != nil {
		return {}
	}
	defer delete(source_dir)

	stamp: Source_Stamp
	accumulate_source_dir_stamp(source_dir, &stamp)
	return stamp
}

accumulate_source_dir_stamp :: proc(path: string, stamp: ^Source_Stamp) {
	accumulate_source_path_stamp(path, stamp)

	entries, read_err := os.read_all_directory_by_path(path, context.temp_allocator)
	if read_err != nil {
		return
	}

	for entry in entries {
		child_path, child_err := filepath.join({path, entry.name})
		if child_err != nil {
			continue
		}

		#partial switch entry.type {
		case .Regular:
			accumulate_source_path_stamp(child_path, stamp)
		case .Directory:
			accumulate_source_dir_stamp(child_path, stamp)
		case:
		}
		delete(child_path)
	}
}

accumulate_source_path_stamp :: proc(path: string, stamp: ^Source_Stamp) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os.file_info_delete(fi, context.temp_allocator)

	stamp.exists = true
	stamp.entry_count += 1
	stamp.size += fi.size
	modified_ns := time.to_unix_nanoseconds(fi.modification_time)
	if modified_ns > stamp.modified_ns {
		stamp.modified_ns = modified_ns
	}
}

source_stamps_equal :: proc(a, b: Source_Stamp) -> bool {
	return a.exists == b.exists &&
		a.modified_ns == b.modified_ns &&
		a.size == b.size &&
		a.entry_count == b.entry_count
}
