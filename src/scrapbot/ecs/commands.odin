package ecs

import shared "../shared"
import base_runtime "base:runtime"
import "core:mem"

MAX_COMMANDS :: 128
MAX_COMMAND_NAME_BYTES :: 64
MAX_COMMAND_COMPONENTS :: 8
MAX_COMMAND_FIELDS :: 16
MAX_UI_COMMAND_TEXT_BYTES :: 1024
MAX_UI_COMMAND_FONT_BYTES :: 256
MAX_UI_COMMAND_PREFIX_BYTES :: 64

Command_Kind :: enum {
	Spawn,
	Despawn,
	Add_Component,
	Remove_Component,
}

Command_Component :: struct {
	component_id: Component_ID,
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	vec3_fields: [MAX_COMMAND_FIELDS]Command_Vec3_Field,
	vec3_field_count: int,
}

Command_Vec3_Field :: struct {
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	value: Vec3,
}

UI_Component_Command_Kind :: enum {
	None,
	Layout,
	HStack,
	VStack,
	Scroll_Area,
	Panel,
	Table,
	List,
	Progress,
	Text,
	Button,
	Input,
	Checkbox,
}

UI_Component_Command :: struct {
	kind: UI_Component_Command_Kind,
	layout: UI_Layout_Component,
	stack: UI_Stack_Component,
	scroll_area: UI_Scroll_Area_Component,
	panel: UI_Panel_Component,
	table: UI_Table_Component,
	list: UI_List_Component,
	progress: UI_Progress_Component,
	text: UI_Text_Component,
	button: UI_Button_Component,
	input: UI_Input_Component,
	checkbox: UI_Checkbox_Component,
	text_bytes: [MAX_UI_COMMAND_TEXT_BYTES]u8,
	text_len: int,
	font_bytes: [MAX_UI_COMMAND_FONT_BYTES]u8,
	font_len: int,
	prefix_bytes: [MAX_UI_COMMAND_PREFIX_BYTES]u8,
	prefix_len: int,
}

Command_Mesh :: struct {
	primitive: [MAX_COMMAND_NAME_BYTES]u8,
	primitive_len: int,
}

Spawn_Command :: struct {
	uuid: shared.Entity_UUID,
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	has_transform: bool,
	transform: Transform_Component,
	has_mesh: bool,
	mesh: Command_Mesh,
	has_geometry: bool,
	geometry: Geometry_Handle,
	has_material: bool,
	material: Material_Handle,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,
	custom_components: [MAX_COMMAND_COMPONENTS]Command_Component,
	custom_component_count: int,
	ui_components: [MAX_COMMAND_COMPONENTS]UI_Component_Command,
	ui_component_count: int,
}

Add_Component_Command :: struct {
	entity_index: int,
	generation: u32,
	has_transform: bool,
	transform: Transform_Component,
	has_mesh: bool,
	mesh: Command_Mesh,
	has_geometry: bool,
	geometry: Geometry_Handle,
	has_material: bool,
	material: Material_Handle,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,
	component: Command_Component,
	ui_component: UI_Component_Command,
}

Remove_Component_Command :: struct {
	entity_index: int,
	generation: u32,
	component_id: Component_ID,
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
}

Command :: struct {
	kind: Command_Kind,
	spawn: Spawn_Command,
	entity_index: int,
	generation: u32,
	add_component: Add_Component_Command,
	remove_component: Remove_Component_Command,
}

Command_Buffer :: struct {
	commands: []Command,
	command_count: int,
	allocator: mem.Allocator,
}

init_command_buffer :: proc(buffer: ^Command_Buffer) {
	init_command_buffer_capacity(buffer, MAX_COMMANDS)
}

init_command_buffer_capacity :: proc(buffer: ^Command_Buffer, capacity: int) {
	buffer^ = {}
	buffer.allocator = context.allocator
	buffer.commands = make([]Command, clamp(capacity, 1, MAX_COMMANDS), buffer.allocator)
}

destroy_command_buffer :: proc(buffer: ^Command_Buffer) {
	delete(buffer.commands, buffer.allocator)
	buffer^ = {}
}

ensure_command_capacity :: proc "c" (buffer: ^Command_Buffer, additional := 1) -> bool {
	context = base_runtime.default_context()
	if buffer == nil || buffer.commands == nil || additional < 0 {
		return false
	}
	required := buffer.command_count + additional
	if required > MAX_COMMANDS {
		return false
	}
	if required <= len(buffer.commands) {
		return true
	}
	capacity := min(max(len(buffer.commands) * 2, required), MAX_COMMANDS)
	commands := make([]Command, capacity, buffer.allocator)
	copy(commands[:buffer.command_count], buffer.commands[:buffer.command_count])
	delete(buffer.commands, buffer.allocator)
	buffer.commands = commands
	return true
}

queue_spawn :: proc "c" (buffer: ^Command_Buffer, name: string) -> string {
	spawn: Spawn_Command
	if err := init_spawn_command(&spawn, name); err != "" {
		return err
	}
	return queue_spawn_command(buffer, spawn)
}

init_spawn_command :: proc "c" (spawn: ^Spawn_Command, name: string) -> string {
	context = base_runtime.default_context()
	if spawn == nil {
		return "spawn command is not available"
	}
	spawn^ = {}
	spawn.uuid = shared.entity_uuid_generate()
	if err := copy_command_string(spawn.name[:], &spawn.name_len, name, "spawn name"); err != "" {
		return err
	}
	return ""
}

spawn_set_transform :: proc "c" (spawn: ^Spawn_Command, transform: Transform_Component) -> string {
	if spawn == nil {
		return "spawn command is not available"
	}
	spawn.has_transform = true
	spawn.transform = transform
	return ""
}

spawn_set_mesh :: proc "c" (spawn: ^Spawn_Command, primitive: string) -> string {
	if spawn == nil {
		return "spawn command is not available"
	}
	spawn.has_mesh = true
	if err := copy_command_string(
		spawn.mesh.primitive[:],
		&spawn.mesh.primitive_len,
		primitive,
		"mesh primitive",
	); err != "" {
		return err
	}
	return ""
}

spawn_set_geometry :: proc "c" (spawn: ^Spawn_Command, handle: Geometry_Handle) -> string {
	if spawn ==
	   nil { return "spawn command is not available" }; spawn.has_geometry = true; spawn.geometry = handle; return ""
}

spawn_set_material :: proc "c" (spawn: ^Spawn_Command, handle: Material_Handle) -> string {
	if spawn ==
	   nil { return "spawn command is not available" }; spawn.has_material = true; spawn.material = handle; return ""
}

spawn_set_marker :: proc "c" (spawn: ^Spawn_Command, name: string) -> string {
	if spawn == nil { return "spawn command is not available" }
	switch name {
		case "scrapbot.shadow_caster":
			spawn.has_shadow_caster = true
		case "scrapbot.shadow_receiver":
			spawn.has_shadow_receiver = true
		case:
			return "unsupported marker component"
	}
	return ""
}

spawn_add_custom_component :: proc "c" (
	spawn: ^Spawn_Command,
	command_component: Command_Component,
) -> string {
	if spawn == nil {
		return "spawn command is not available"
	}
	if spawn.custom_component_count >= MAX_COMMAND_COMPONENTS {
		return "too many spawn components"
	}
	spawn.custom_components[spawn.custom_component_count] = command_component
	spawn.custom_component_count += 1
	return ""
}

init_ui_component_command :: proc "contextless" (
	command: ^UI_Component_Command,
	kind: UI_Component_Command_Kind,
	text: string = "",
	font: string = "",
	prefix: string = "",
) -> string {
	if command == nil {
		return "UI component command is not available"
	}
	command.kind = kind
	if err := copy_command_string(command.text_bytes[:], &command.text_len, text, "UI text");
	   err != "" {
		return err
	}
	if err := copy_command_string(command.font_bytes[:], &command.font_len, font, "UI font");
	   err != "" {
		return err
	}
	if err := copy_command_string(
		command.prefix_bytes[:],
		&command.prefix_len,
		prefix,
		"UI input prefix",
	); err != "" {
		return err
	}
	return ""
}

ui_component_command_kind :: proc "contextless" (name: string) -> UI_Component_Command_Kind {
	switch name {
		case "scrapbot.ui_layout":
			return .Layout
		case "scrapbot.ui_hstack":
			return .HStack
		case "scrapbot.ui_vstack":
			return .VStack
		case "scrapbot.ui_scroll_area":
			return .Scroll_Area
		case "scrapbot.ui_panel":
			return .Panel
		case "scrapbot.ui_table":
			return .Table
		case "scrapbot.ui_list":
			return .List
		case "scrapbot.ui_progress":
			return .Progress
		case "scrapbot.ui_text":
			return .Text
		case "scrapbot.ui_button":
			return .Button
		case "scrapbot.ui_input":
			return .Input
		case "scrapbot.ui_checkbox":
			return .Checkbox
	}
	return .None
}

queued_ui_component :: proc(
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	kind: UI_Component_Command_Kind,
) -> ^UI_Component_Command {
	if buffer == nil || buffer.commands == nil || kind == .None {
		return nil
	}
	for command_index := buffer.command_count - 1; command_index >= 0; command_index -= 1 {
		command := &buffer.commands[command_index]
		if command.kind == .Remove_Component &&
		   command.remove_component.entity_index == entity_index &&
		   command.remove_component.generation == generation &&
		   ui_component_command_kind(remove_component_name(&command.remove_component)) == kind {
			return nil
		}
		if command.kind != .Add_Component ||
		   command.add_component.entity_index != entity_index ||
		   command.add_component.generation != generation ||
		   command.add_component.ui_component.kind != kind {
			continue
		}
		return &command.add_component.ui_component
	}
	return nil
}

ui_component_command_text :: proc "contextless" (command: ^UI_Component_Command) -> string {
	if command == nil { return "" }
	return string(command.text_bytes[:command.text_len])
}

ui_component_command_font :: proc "contextless" (command: ^UI_Component_Command) -> string {
	if command == nil { return "" }
	return string(command.font_bytes[:command.font_len])
}

ui_component_command_prefix :: proc "contextless" (command: ^UI_Component_Command) -> string {
	if command == nil { return "" }
	return string(command.prefix_bytes[:command.prefix_len])
}

spawn_add_ui_component :: proc "contextless" (
	spawn: ^Spawn_Command,
	component: UI_Component_Command,
) -> string {
	if spawn == nil {
		return "spawn command is not available"
	}
	if spawn.ui_component_count >= len(spawn.ui_components) {
		return "too many spawn UI components"
	}
	spawn.ui_components[spawn.ui_component_count] = component
	spawn.ui_component_count += 1
	return ""
}

init_command_component :: proc "c" (
	command_component: ^Command_Component,
	component_id: Component_ID,
	name: string,
) -> string {
	if command_component == nil {
		return "component command is not available"
	}
	command_component^ = {}
	command_component.component_id = component_id
	if err := copy_command_string(
		command_component.name[:],
		&command_component.name_len,
		name,
		"component name",
	); err != "" {
		return err
	}
	return ""
}

command_component_add_vec3 :: proc "c" (
	command_component: ^Command_Component,
	name: string,
	value: Vec3,
) -> string {
	if command_component == nil {
		return "component command is not available"
	}
	if command_component.vec3_field_count >= MAX_COMMAND_FIELDS {
		return "too many component fields"
	}

	field := &command_component.vec3_fields[command_component.vec3_field_count]
	if err := copy_command_string(field.name[:], &field.name_len, name, "component field name");
	   err != "" {
		return err
	}
	field.value = value
	command_component.vec3_field_count += 1
	return ""
}

queue_spawn_command :: proc "c" (buffer: ^Command_Buffer, spawn: Spawn_Command) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	command := &buffer.commands[buffer.command_count]
	command^ = Command {
		kind = .Spawn,
		spawn = spawn,
	}
	buffer.command_count += 1
	return ""
}

queue_despawn :: proc "c" (buffer: ^Command_Buffer, entity_index: int, generation: u32) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	buffer.commands[buffer.command_count] = Command {
		kind = .Despawn,
		entity_index = entity_index,
		generation = generation,
	}
	buffer.command_count += 1
	return ""
}

queue_add_transform :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	transform: Transform_Component,
) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	buffer.commands[buffer.command_count] = Command {
		kind = .Add_Component,
		add_component = Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			has_transform = true,
			transform = transform,
		},
	}
	buffer.command_count += 1
	return ""
}

queue_add_geometry :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	handle: Geometry_Handle,
) -> string {
	if buffer == nil || buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = {
			entity_index = entity_index,
			generation = generation,
			has_geometry = true,
			geometry = handle,
		},
	}
	buffer.command_count += 1
	return ""
}

queue_add_material :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	handle: Material_Handle,
) -> string {
	if buffer == nil || buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = {
			entity_index = entity_index,
			generation = generation,
			has_material = true,
			material = handle,
		},
	}
	buffer.command_count += 1
	return ""
}

queue_add_marker :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	name: string,
) -> string {
	if buffer == nil || buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}
	add := Add_Component_Command {
		entity_index = entity_index,
		generation = generation,
	}
	switch name {
		case "scrapbot.shadow_caster":
			add.has_shadow_caster = true
		case "scrapbot.shadow_receiver":
			add.has_shadow_receiver = true
		case:
			return "unsupported marker component"
	}
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = add,
	}
	buffer.command_count += 1
	return ""
}

queue_add_mesh :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	primitive: string,
) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	add: Add_Component_Command
	add.entity_index = entity_index
	add.generation = generation
	add.has_mesh = true
	if err := copy_command_string(
		add.mesh.primitive[:],
		&add.mesh.primitive_len,
		primitive,
		"mesh primitive",
	); err != "" {
		return err
	}

	buffer.commands[buffer.command_count] = Command {
		kind = .Add_Component,
		add_component = add,
	}
	buffer.command_count += 1
	return ""
}

queue_add_custom_component :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	command_component: Command_Component,
) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	buffer.commands[buffer.command_count] = Command {
		kind = .Add_Component,
		add_component = Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			component = command_component,
		},
	}
	buffer.command_count += 1
	return ""
}

queue_add_ui_component :: proc "contextless" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	component: UI_Component_Command,
) -> string {
	if buffer == nil || buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = {
			entity_index = entity_index,
			generation = generation,
			ui_component = component,
		},
	}
	buffer.command_count += 1
	return ""
}

queue_remove_component :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	component_id: Component_ID,
	name: string,
) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(buffer) {
		return "too many deferred world commands"
	}

	remove: Remove_Component_Command
	remove.entity_index = entity_index
	remove.generation = generation
	remove.component_id = component_id
	if err := copy_command_string(remove.name[:], &remove.name_len, name, "component name");
	   err != "" {
		return err
	}

	buffer.commands[buffer.command_count] = Command {
		kind = .Remove_Component,
		remove_component = remove,
	}
	buffer.command_count += 1
	return ""
}

apply_commands :: proc(world: ^World, buffer: ^Command_Buffer) -> string {
	if world == nil || buffer == nil {
		return ""
	}
	if buffer.commands == nil {
		return ""
	}

	for command_index in 0 ..< buffer.command_count {
		command := &buffer.commands[command_index]
		switch command.kind {
			case .Spawn:
				spawn_entity(world, &command.spawn)
			case .Despawn:
				despawn_entity(world, command.entity_index, command.generation)
			case .Add_Component:
				apply_add_component(world, &command.add_component)
			case .Remove_Component:
				apply_remove_component(world, &command.remove_component)
		}
	}
	buffer.command_count = 0
	when ODIN_TEST || WORLD_INTEGRITY_CHECKS {
		if failure, ok := validate_world_integrity(world); !ok {
			return format_world_integrity_failure(failure)
		}
	}
	return ""
}

clear_commands :: proc "c" (buffer: ^Command_Buffer) {
	if buffer != nil {
		buffer.command_count = 0
	}
}

append_commands :: proc(destination, source: ^Command_Buffer) -> string {
	if destination == nil || source == nil || source.command_count == 0 {
		return ""
	}
	if destination.commands == nil || source.commands == nil {
		return "command buffer is not initialized"
	}
	if !ensure_command_capacity(destination, source.command_count) {
		return "too many deferred world commands"
	}
	for i in 0 ..< source.command_count {
		destination.commands[destination.command_count] = source.commands[i]
		destination.command_count += 1
	}
	source.command_count = 0
	return ""
}

spawn_entity :: proc(world: ^World, spawn: ^Spawn_Command) -> int {
	context = base_runtime.default_context()
	entity_index, created := create_world_entity(
		world,
		spawn_command_name(spawn),
		spawn.uuid,
		.Runtime,
		true,
	)
	if !created {
		return INVALID_COMPONENT_INDEX
	}
	spawn.uuid = shared.entity_uuid_generate()
	transform_index := INVALID_COMPONENT_INDEX
	if spawn.has_transform {
		transform_index = allocate_transform_slot(world, spawn.transform)
	}
	mesh_index := INVALID_COMPONENT_INDEX
	if spawn.has_mesh {
		mesh_index = allocate_mesh_slot(world, command_mesh_primitive(&spawn.mesh))
	}

	world_entity := &world.entities[entity_index]
	world_entity.transform_index = transform_index
	world_entity.mesh_index = mesh_index
	world_entity.has_shadow_caster = spawn.has_shadow_caster
	world_entity.has_shadow_receiver = spawn.has_shadow_receiver
	ensure_entity_renderable(world, entity_index)
	if spawn.has_geometry { add_geometry(world, entity_index, spawn.geometry) }
	if spawn.has_material { add_material(world, entity_index, spawn.material) }

	for i in 0 ..< spawn.custom_component_count {
		add_custom_component(world, entity_index, &spawn.custom_components[i])
	}
	for i in 0 ..< spawn.ui_component_count {
		apply_ui_component(world, entity_index, &spawn.ui_components[i])
	}
	mark_render_entity_dirty(world, entity_index)
	return entity_index
}

despawn_entity :: proc(world: ^World, entity_index: int, generation: u32) {
	if !entity_is_current(world, entity_index, generation) {
		return
	}
	detach_transform_children(world, entity_index)

	entity := &world.entities[entity_index]
	if world.entity_by_uuid != nil {
		delete_key(&world.entity_by_uuid, entity.uuid)
	}
	if entity.ui_layout_index >= 0 {
		mark_ui_subtree_dirty(world, entity_index)
	}
	delete_world_string(world, entity.name)
	delete_world_string(world, entity.geometry_resource)
	delete_world_string(world, entity.material_resource)
	entity.name = ""
	entity.geometry_resource = ""
	entity.material_resource = ""
	ui_component_names := [?]string {
		"scrapbot.ui_layout",
		"scrapbot.ui_hstack",
		"scrapbot.ui_vstack",
		"scrapbot.ui_scroll_area",
		"scrapbot.ui_panel",
		"scrapbot.ui_table",
		"scrapbot.ui_list",
		"scrapbot.ui_progress",
		"scrapbot.ui_text",
		"scrapbot.ui_button",
		"scrapbot.ui_input",
		"scrapbot.ui_checkbox",
	}
	for component_name in ui_component_names {
		remove_ui_component(world, entity_index, component_name)
	}
	release_ui_state(world, entity_index)
	entity.alive = false
	sync_render_watch_memberships(world, entity_index)
	entity.uuid = {}
	entity.id.generation += 1
	if entity.id.generation == 0 {
		entity.id.generation = 1
	}
	invalidate_entity_renderables(world, entity_index)
	release_transform_slot(world, entity.transform_index)
	release_mesh_slot(world, entity.mesh_index)
	release_geometry_slot(world, entity.geometry_index)
	release_material_slot(world, entity.material_index)
	release_entity_render_instance(world, entity)
	entity.transform_index = INVALID_COMPONENT_INDEX
	entity.camera_index = INVALID_COMPONENT_INDEX
	entity.ambient_light_index = INVALID_COMPONENT_INDEX
	entity.directional_light_index = INVALID_COMPONENT_INDEX
	entity.point_light_index = INVALID_COMPONENT_INDEX
	entity.mesh_index = INVALID_COMPONENT_INDEX
	entity.geometry_index = INVALID_COMPONENT_INDEX
	entity.material_index = INVALID_COMPONENT_INDEX
	for storage_index in entity.custom_component_storage_indices {
		when ODIN_TEST {
			world.custom_teardown_storage_visit_count += 1
		}
		if storage_index < 0 || storage_index >= len(world.custom_components) {
			continue
		}
		storage := &world.custom_components[storage_index]
		component_index, found := custom_component_index_for_entity(storage, entity_index)
		if found {
			release_custom_component_slot(world, storage, component_index)
		}
	}
	clear(&entity.custom_component_storage_indices)
	if entity.editor_transform_gizmo_index >= 0 &&
	   entity.editor_transform_gizmo_index <
		   len(
			   world.editor_transform_gizmos,
		   ) { world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index = INVALID_COMPONENT_INDEX }
	entity.editor_transform_gizmo_index = INVALID_COMPONENT_INDEX
	for &camera in world.editor_scene_cameras { if camera.entity_index == entity_index { camera.entity_index = INVALID_COMPONENT_INDEX } }
	if entity.editor_ui_index >= 0 && entity.editor_ui_index < len(world.editor_uis) {
		world.editor_uis[entity.editor_ui_index].entity_index = INVALID_COMPONENT_INDEX
	}
	entity.editor_ui_index = INVALID_COMPONENT_INDEX
	entity.has_shadow_caster = false
	entity.has_shadow_receiver = false
	entity.render_dirty = false
	append(&world.free_entity_indices, entity_index)
}

apply_add_component :: proc(world: ^World, command: ^Add_Component_Command) {
	if !entity_is_current(world, command.entity_index, command.generation) {
		return
	}
	if command.has_transform {
		add_transform(world, command.entity_index, command.transform)
		return
	}
	if command.has_mesh {
		add_mesh(world, command.entity_index, command_mesh_primitive(&command.mesh))
		return
	}
	if command.has_geometry { add_geometry(world, command.entity_index, command.geometry); return }
	if command.has_material { add_material(world, command.entity_index, command.material); return }
	if command.has_shadow_caster { if !world.entities[command.entity_index].has_shadow_caster { world.entities[command.entity_index].has_shadow_caster = true; bump_component_revision(world, command.entity_index) }; return }
	if command.has_shadow_receiver { if !world.entities[command.entity_index].has_shadow_receiver { world.entities[command.entity_index].has_shadow_receiver = true; bump_component_revision(world, command.entity_index) }; return }
	if command.ui_component.kind != .None {
		apply_ui_component(world, command.entity_index, &command.ui_component)
		return
	}
	add_custom_component(world, command.entity_index, &command.component)
}

apply_ui_component :: proc(world: ^World, entity_index: int, command: ^UI_Component_Command) {
	if world == nil || command == nil {
		return
	}
	text := string(command.text_bytes[:command.text_len])
	font := string(command.font_bytes[:command.font_len])
	prefix := string(command.prefix_bytes[:command.prefix_len])
	switch command.kind {
		case .Layout:
			set_ui_layout(world, entity_index, command.layout)
		case .HStack:
			set_ui_hstack(world, entity_index, command.stack)
		case .VStack:
			set_ui_vstack(world, entity_index, command.stack)
		case .Scroll_Area:
			set_ui_scroll_area(world, entity_index, command.scroll_area)
		case .Panel:
			value := command.panel
			value.title = text
			value.font = font
			set_ui_panel(world, entity_index, value)
		case .Table:
			set_ui_table(world, entity_index, command.table)
		case .List:
			set_ui_list(world, entity_index, command.list)
		case .Progress:
			set_ui_progress(world, entity_index, command.progress)
		case .Text:
			value := command.text
			value.text = text
			value.font = font
			set_ui_text(world, entity_index, value)
		case .Button:
			value := command.button
			value.text = text
			value.font = font
			set_ui_button(world, entity_index, value)
		case .Input:
			value := command.input
			value.text = text
			value.font = font
			value.prefix = prefix
			set_ui_input(world, entity_index, value)
		case .Checkbox:
			set_ui_checkbox(world, entity_index, command.checkbox)
		case .None:
			return
	}
}

apply_remove_component :: proc(world: ^World, command: ^Remove_Component_Command) {
	if !entity_is_current(world, command.entity_index, command.generation) {
		return
	}
	name := remove_component_name(command)
	if name == "scrapbot.transform" {
		remove_transform(world, command.entity_index)
		return
	}
	if name == "scrapbot.mesh" {
		remove_mesh(world, command.entity_index)
		return
	}
	if name == "scrapbot.geometry" { remove_geometry(world, command.entity_index); return }
	if name == "scrapbot.material" { remove_material(world, command.entity_index); return }
	if name ==
	   "scrapbot.shadow_caster" { if world.entities[command.entity_index].has_shadow_caster { world.entities[command.entity_index].has_shadow_caster = false; bump_component_revision(world, command.entity_index) }; return }
	if name ==
	   "scrapbot.shadow_receiver" { if world.entities[command.entity_index].has_shadow_receiver { world.entities[command.entity_index].has_shadow_receiver = false; bump_component_revision(world, command.entity_index) }; return }
	if remove_ui_component(world, command.entity_index, name) {
		return
	}
	remove_custom_component(world, command.entity_index, command.component_id, name)
}

spawn_command_name :: proc(spawn: ^Spawn_Command) -> string {
	return string(spawn.name[:spawn.name_len])
}

command_component_name :: proc(command_component: ^Command_Component) -> string {
	return string(command_component.name[:command_component.name_len])
}

command_field_name :: proc(field: ^Command_Vec3_Field) -> string {
	return string(field.name[:field.name_len])
}

command_mesh_primitive :: proc(mesh: ^Command_Mesh) -> string {
	return string(mesh.primitive[:mesh.primitive_len])
}

remove_component_name :: proc(command: ^Remove_Component_Command) -> string {
	return string(command.name[:command.name_len])
}

copy_command_string :: proc "c" (
	dest: []u8,
	out_len: ^int,
	value: string,
	label: string,
) -> string {
	if len(value) >= len(dest) {
		return "command string is too long"
	}
	out_len^ = len(value)
	if len(value) == 0 {
		return ""
	}
	value_bytes := (cast([^]u8)raw_data(value))[:len(value)]
	for byte_value, index in value_bytes {
		dest[index] = byte_value
	}
	return ""
}
