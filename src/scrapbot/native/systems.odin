package native

import component "../component"
import ecs "../ecs"
import api "../extension_api"
import resources "../resources"
import schedule "../schedule"
import shared "../shared"
import base_runtime "base:runtime"
import c "core:c"
import "core:fmt"
import "core:time"

extension_register_geometry :: proc "c" (
	host_api: ^api.API,
	name: cstring,
	desc: ^api.Geometry_Desc,
	out_handle: ^api.Resource_Handle,
) -> cstring {
	context = base_runtime.default_context()
	if host_api == nil ||
	   host_api.userdata == nil ||
	   name == nil ||
	   desc == nil ||
	   out_handle == nil { return "native geometry registration is not available" }
	set := cast(^Extension_Set)host_api.userdata; if set.resources == nil { return "native geometry registry is not available" }
	if desc.vertex_count < 0 ||
	   desc.index_count < 0 { return "native geometry counts are invalid" }
	vertices := cast([^]resources.Vertex)desc.vertices
	handle, err := resources.register_geometry(
		set.resources,
		string(name),
		{
			vertices = vertices[:int(desc.vertex_count)],
			indices = desc.indices[:int(desc.index_count)],
		},
	)
	if err != "" { return "native geometry registration failed" }
	out_handle^ = {handle.index, handle.generation}; return nil
}

extension_register_material :: proc "c" (
	host_api: ^api.API,
	name: cstring,
	desc: ^api.Material_Desc,
	out_handle: ^api.Resource_Handle,
) -> cstring {
	context = base_runtime.default_context()
	if host_api == nil ||
	   host_api.userdata == nil ||
	   name == nil ||
	   desc == nil ||
	   out_handle == nil { return "native material registration is not available" }
	set := cast(^Extension_Set)host_api.userdata; if set.resources == nil { return "native material registry is not available" }
	c := desc.base_color
	e := desc.emissive
	handle, err := resources.register_material(
		set.resources,
		string(name),
		{base_color = {c.x, c.y, c.z, c.w}, emissive = {e.x, e.y, e.z}},
	)
	if err != "" { return "native material registration failed" }
	out_handle^ = {handle.index, handle.generation}; return nil
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
	for i in 0 ..< component_definition.field_count {
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

	for i in 0 ..< int(definition.access_count) {
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
			mode = mode,
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
	time: shared.Time_Resource,
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
		userdata = system.userdata,
		host = &step_context,
		time = {
			delta_time = time.delta_time,
			smooth_delta_time = time.smooth_delta_time,
			elapsed_time = time.elapsed_time,
			frame_index = time.frame_index,
		},
		query_count = system_query_count,
		query_entity_at = system_query_entity_at,
		query_next = system_query_next,
		get_transform = system_get_transform,
		set_transform = system_set_transform,
		get_vec3_field = system_get_vec3_field,
		set_vec3_field = system_set_vec3_field,
		get_ui_component = system_get_ui_component,
		set_ui_component = system_set_ui_component,
		spawn = system_spawn,
		despawn = system_despawn,
		add_transform = system_add_transform,
		add_mesh = system_add_mesh,
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

system_query_next :: proc "c" (
	ctx: ^api.System_Context,
	terms: [^]api.Query_Term,
	term_count: c.int,
	next_entity_index: ^c.int,
) -> api.Entity {
	step, ok := system_step_context(ctx)
	if !ok || next_entity_index == nil {
		return api.Entity{index = -1}
	}
	query, query_ok := system_query_from_terms(step, terms, term_count)
	if !query_ok {
		return api.Entity{index = -1}
	}
	cursor := int(next_entity_index^)
	entity_index, entity_ok := ecs.query_next(step.world, query, &cursor)
	next_entity_index^ = c.int(cursor)
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
	if !ok ||
	   transform == nil ||
	   !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Read) {
		return 0
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return 0
	}
	world_entity := step.world.entities[entity_index]
	if world_entity.transform_index < 0 ||
	   world_entity.transform_index >= len(step.world.transforms) {
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
	context = base_runtime.default_context()
	step, ok := system_step_context(ctx)
	if !ok ||
	   transform == nil ||
	   !system_allows_component_access(step.system.declaration, "scrapbot.transform", .Write) {
		return 0
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return 0
	}
	world_entity := step.world.entities[entity_index]
	if world_entity.transform_index < 0 ||
	   world_entity.transform_index >= len(step.world.transforms) {
		return 0
	}
	next := shared_transform_from_api(transform^)
	current := step.world.transforms[world_entity.transform_index]
	if next.parent != current.parent &&
	   !ecs.transform_parent_is_valid(step.world, entity_index, next.parent) {
		return 0
	}
	step.world.transforms[world_entity.transform_index] = next
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
		if err := ecs.spawn_set_transform(&spawn, shared_transform_from_api(options.transform^));
		   err != "" {
			return cstring(raw_data(err))
		}
	}
	if options.mesh != nil {
		if !system_allows_component_access(step.system.declaration, "scrapbot.mesh", .Write) {
			return "native system does not have write access to scrapbot.mesh"
		}
		if options.mesh.primitive == nil {
			return "native mesh primitive is not available"
		}
		if err := ecs.spawn_set_mesh(&spawn, string(options.mesh.primitive)); err != "" {
			return cstring(raw_data(err))
		}
	}
	if options.geometry != nil {
		if !system_allows_component_access(
			step.system.declaration,
			"scrapbot.geometry",
			.Write,
		) { return "native system does not have write access to scrapbot.geometry" }
		ecs.spawn_set_geometry(&spawn, {options.geometry.index, options.geometry.generation})
	}
	if options.material != nil {
		if !system_allows_component_access(
			step.system.declaration,
			"scrapbot.material",
			.Write,
		) { return "native system does not have write access to scrapbot.material" }
		ecs.spawn_set_material(&spawn, {options.material.index, options.material.generation})
	}

	if options.component_count < 0 || options.component_count > ecs.MAX_COMMAND_COMPONENTS {
		return "invalid spawn component count"
	}
	if options.component_count > 0 && options.components == nil {
		return "spawn components are not available"
	}
	for i in 0 ..< int(options.component_count) {
		payload := options.components[i]
		if payload.component == nil {
			return "spawn component name is required"
		}
		name := string(payload.component)
		if !system_allows_component_access(step.system.declaration, name, .Write) {
			return "native system does not have write access to spawn component"
		}
		if name == "scrapbot.shadow_caster" || name == "scrapbot.shadow_receiver" {
			if err := ecs.spawn_set_marker(&spawn, name);
			   err != "" { return cstring(raw_data(err)) }
			continue
		}
		command_component: ecs.Command_Component
		if err := command_component_from_payload(step, &payload, &command_component); err != "" {
			return cstring(raw_data(err))
		}
		if err := ecs.spawn_add_custom_component(&spawn, command_component); err != "" {
			return cstring(raw_data(err))
		}
	}
	if options.ui_component_count < 0 || options.ui_component_count > ecs.MAX_COMMAND_COMPONENTS {
		return "invalid spawn UI component count"
	}
	if options.ui_component_count > 0 && options.ui_components == nil {
		return "spawn UI components are not available"
	}
	for i in 0 ..< int(options.ui_component_count) {
		payload := &options.ui_components[i]
		if payload.component == nil {
			return "spawn UI component name is required"
		}
		name := string(payload.component)
		if !system_allows_component_access(step.system.declaration, name, .Write) {
			return "native system does not have write access to spawn UI component"
		}
		command: ecs.UI_Component_Command
		if err := ui_command_from_api_payload(payload, &command); err != "" {
			return cstring(raw_data(err))
		}
		if err := ecs.spawn_add_ui_component(&spawn, command); err != "" {
			return cstring(raw_data(err))
		}
	}

	if err := ecs.queue_spawn_command(step.commands, spawn); err != "" {
		return cstring(raw_data(err))
	}
	if options.out_uuid != nil {
		options.out_uuid^ = api_uuid_from_shared(spawn.uuid)
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
	if err := ecs.queue_add_transform(
		step.commands,
		int(entity.index),
		entity.generation,
		shared_transform_from_api(transform^),
	); err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

system_add_mesh :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	mesh: ^api.Mesh_Payload,
) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if mesh == nil || mesh.primitive == nil {
		return "native mesh payload is not available"
	}
	if !system_allows_component_access(step.system.declaration, "scrapbot.mesh", .Write) {
		return "native system does not have write access to scrapbot.mesh"
	}
	if !ecs.entity_is_current(step.world, int(entity.index), entity.generation) {
		return "native add component entity is stale"
	}
	if err := ecs.queue_add_mesh(
		step.commands,
		int(entity.index),
		entity.generation,
		string(mesh.primitive),
	); err != "" {
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
	if name == "scrapbot.shadow_caster" || name == "scrapbot.shadow_receiver" {
		if err := ecs.queue_add_marker(step.commands, int(entity.index), entity.generation, name);
		   err != "" { return cstring(raw_data(err)) }
		return nil
	}
	command_component: ecs.Command_Component
	if err := command_component_from_payload(step, payload, &command_component); err != "" {
		return cstring(raw_data(err))
	}
	if err := ecs.queue_add_custom_component(
		step.commands,
		int(entity.index),
		entity.generation,
		command_component,
	); err != "" {
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
	if name != "scrapbot.transform" &&
	   name != "scrapbot.mesh" &&
	   name != "scrapbot.shadow_caster" &&
	   name != "scrapbot.shadow_receiver" &&
	   !ecs.ui_component_name_is_mutable(name) {
		definition, found := component.find_definition(step.registry, name)
		if !found || (definition.owner != .Project && definition.owner != .Library) {
			return(
				"native component removal only supports built-in and schema-backed custom components" \
			)
		}
		component_id = definition.id
	}
	if err := ecs.queue_remove_component(
		step.commands,
		int(entity.index),
		entity.generation,
		component_id,
		name,
	); err != "" {
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

	if err := ecs.init_command_component(command_component, definition.id, definition.name);
	   err != "" {
		return err
	}

	for i in 0 ..< definition.field_count {
		field := definition.fields[i]
		if field.field_type != component.Field_Type.Vec3 {
			return "unsupported component field type"
		}
		value, found := payload_vec3_field(payload, field.name)
		if !found {
			return "component payload is missing a required field"
		}
		if err := ecs.command_component_add_vec3(
			command_component,
			field.name,
			shared_vec3_from_api(value),
		); err != "" {
			return err
		}
	}

	return ""
}

payload_vec3_field :: proc "c" (
	payload: ^api.Component_Payload,
	field_name: string,
) -> (
	api.Vec3,
	bool,
) {
	if payload == nil || payload.vec3_fields == nil {
		return {}, false
	}
	for i in 0 ..< int(payload.vec3_field_count) {
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
) -> (
	ecs.Query,
	bool,
) {
	if step == nil || terms == nil || term_count <= 0 || term_count > api.MAX_QUERY_TERMS {
		return {}, false
	}

	query: ecs.Query
	for i in 0 ..< int(term_count) {
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
) -> (
	^shared.Custom_Component,
	bool,
) {
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
	for i in 0 ..< declaration.access_count {
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
