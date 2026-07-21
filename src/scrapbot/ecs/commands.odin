package ecs

import shared "../shared"
import base_runtime "base:runtime"

DEFAULT_COMMAND_CAPACITY :: 128
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
	number_fields: [MAX_COMMAND_FIELDS]Command_Number_Field,
	number_field_count: int,
	vec2_fields: [MAX_COMMAND_FIELDS]Command_Vec2_Field,
	vec2_field_count: int,
	vec3_fields: [MAX_COMMAND_FIELDS]Command_Vec3_Field,
	vec3_field_count: int,
	vec4_fields: [MAX_COMMAND_FIELDS]Command_Vec4_Field,
	vec4_field_count: int,
}

Command_Number_Field :: struct {
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	value: f32,
}

Command_Vec2_Field :: struct {
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	value: Vec2,
}

Command_Vec3_Field :: struct {
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	value: Vec3,
}

Command_Vec4_Field :: struct {
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	value: Vec4,
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

Add_Component_Command_Kind :: enum {
	Transform,
	Mesh,
	Geometry,
	Material,
	Shadow_Caster,
	Shadow_Receiver,
	Custom,
	UI,
}

Queued_Add_Component_Command :: struct {
	entity_index: int,
	generation: u32,
	kind: Add_Component_Command_Kind,
	transform: Transform_Component,
	mesh: Command_Mesh,
	geometry: Geometry_Handle,
	material: Material_Handle,
	payload_index: int,
}

Remove_Component_Command :: struct {
	entity_index: int,
	generation: u32,
	component_id: Component_ID,
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
}

Command_Header :: struct {
	kind: Command_Kind,
	payload_index: int,
}

Despawn_Command :: struct {
	entity_index: int,
	generation: u32,
}

Queued_Command_Component :: struct {
	component_id: Component_ID,
	name: [MAX_COMMAND_NAME_BYTES]u8,
	name_len: int,
	number_field_start: int,
	number_field_count: int,
	vec2_field_start: int,
	vec2_field_count: int,
	vec3_field_start: int,
	vec3_field_count: int,
	vec4_field_start: int,
	vec4_field_count: int,
}

Queued_Spawn_Command :: struct {
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
	custom_component_start: int,
	custom_component_count: int,
	ui_component_start: int,
	ui_component_count: int,
}

Command_Buffer :: struct {
	commands: [dynamic]Command_Header,
	spawns: [dynamic]Queued_Spawn_Command,
	components: [dynamic]Queued_Command_Component,
	number_fields: [dynamic]Command_Number_Field,
	vec2_fields: [dynamic]Command_Vec2_Field,
	vec3_fields: [dynamic]Command_Vec3_Field,
	vec4_fields: [dynamic]Command_Vec4_Field,
	ui_components: [dynamic]UI_Component_Command,
	despawns: [dynamic]Despawn_Command,
	add_components: [dynamic]Queued_Add_Component_Command,
	remove_components: [dynamic]Remove_Component_Command,
	command_count: int,
}

init_command_buffer :: proc(buffer: ^Command_Buffer) {
	init_command_buffer_capacity(buffer, DEFAULT_COMMAND_CAPACITY)
}

init_command_buffer_capacity :: proc(buffer: ^Command_Buffer, capacity: int) {
	buffer^ = {}
	allocator := context.allocator
	buffer.commands = make([dynamic]Command_Header, 0, max(capacity, 1), allocator)
	buffer.spawns = make([dynamic]Queued_Spawn_Command, allocator)
	buffer.components = make([dynamic]Queued_Command_Component, allocator)
	buffer.number_fields = make([dynamic]Command_Number_Field, allocator)
	buffer.vec2_fields = make([dynamic]Command_Vec2_Field, allocator)
	buffer.vec3_fields = make([dynamic]Command_Vec3_Field, allocator)
	buffer.vec4_fields = make([dynamic]Command_Vec4_Field, allocator)
	buffer.ui_components = make([dynamic]UI_Component_Command, allocator)
	buffer.despawns = make([dynamic]Despawn_Command, allocator)
	buffer.add_components = make([dynamic]Queued_Add_Component_Command, allocator)
	buffer.remove_components = make([dynamic]Remove_Component_Command, allocator)
}

destroy_command_buffer :: proc(buffer: ^Command_Buffer) {
	delete(buffer.commands)
	delete(buffer.spawns)
	delete(buffer.components)
	delete(buffer.number_fields)
	delete(buffer.vec2_fields)
	delete(buffer.vec3_fields)
	delete(buffer.vec4_fields)
	delete(buffer.ui_components)
	delete(buffer.despawns)
	delete(buffer.add_components)
	delete(buffer.remove_components)
	buffer^ = {}
}

append_command_header :: proc "contextless" (
	buffer: ^Command_Buffer,
	kind: Command_Kind,
	payload_index: int,
) {
	context = base_runtime.default_context()
	append(&buffer.commands, Command_Header{kind = kind, payload_index = payload_index})
	buffer.command_count = len(buffer.commands)
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
		header := &buffer.commands[command_index]
		if header.kind == .Remove_Component {
			command := &buffer.remove_components[header.payload_index]
			if command.entity_index == entity_index &&
			   command.generation == generation &&
			   ui_component_command_kind(remove_component_name(command)) == kind {
				return nil
			}
		}
		if header.kind != .Add_Component {
			continue
		}
		command := &buffer.add_components[header.payload_index]
		if command.entity_index != entity_index ||
		   command.generation != generation ||
		   command.kind != .UI ||
		   buffer.ui_components[command.payload_index].kind != kind {
			continue
		}
		return &buffer.ui_components[command.payload_index]
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

command_component_add_number :: proc "c" (
	command_component: ^Command_Component,
	name: string,
	value: f32,
) -> string {
	if command_component == nil || command_component.number_field_count >= MAX_COMMAND_FIELDS {
		return "too many component fields"
	}
	field := &command_component.number_fields[command_component.number_field_count]
	if err := copy_command_string(field.name[:], &field.name_len, name, "component field name");
	   err != "" { return err }
	field.value = value
	command_component.number_field_count += 1
	return ""
}

command_component_add_vec2 :: proc "c" (
	command_component: ^Command_Component,
	name: string,
	value: Vec2,
) -> string {
	if command_component == nil || command_component.vec2_field_count >= MAX_COMMAND_FIELDS {
		return "too many component fields"
	}
	field := &command_component.vec2_fields[command_component.vec2_field_count]
	if err := copy_command_string(field.name[:], &field.name_len, name, "component field name");
	   err != "" { return err }
	field.value = value
	command_component.vec2_field_count += 1
	return ""
}

command_component_add_vec4 :: proc "c" (
	command_component: ^Command_Component,
	name: string,
	value: Vec4,
) -> string {
	if command_component == nil || command_component.vec4_field_count >= MAX_COMMAND_FIELDS {
		return "too many component fields"
	}
	field := &command_component.vec4_fields[command_component.vec4_field_count]
	if err := copy_command_string(field.name[:], &field.name_len, name, "component field name");
	   err != "" { return err }
	field.value = value
	command_component.vec4_field_count += 1
	return ""
}

queue_component_payload :: proc "contextless" (
	buffer: ^Command_Buffer,
	component: Command_Component,
) -> int {
	context = base_runtime.default_context()
	queued := Queued_Command_Component {
		component_id = component.component_id,
		name = component.name,
		name_len = component.name_len,
		number_field_start = len(buffer.number_fields),
		number_field_count = component.number_field_count,
		vec2_field_start = len(buffer.vec2_fields),
		vec2_field_count = component.vec2_field_count,
		vec3_field_start = len(buffer.vec3_fields),
		vec3_field_count = component.vec3_field_count,
		vec4_field_start = len(buffer.vec4_fields),
		vec4_field_count = component.vec4_field_count,
	}
	for index in 0 ..< component.number_field_count {
		append(&buffer.number_fields, component.number_fields[index])
	}
	for index in 0 ..< component.vec2_field_count {
		append(&buffer.vec2_fields, component.vec2_fields[index])
	}
	for index in 0 ..< component.vec3_field_count {
		append(&buffer.vec3_fields, component.vec3_fields[index])
	}
	for index in 0 ..< component.vec4_field_count {
		append(&buffer.vec4_fields, component.vec4_fields[index])
	}
	payload_index := len(buffer.components)
	append(&buffer.components, queued)
	return payload_index
}

queue_spawn_command :: proc "c" (buffer: ^Command_Buffer, spawn: Spawn_Command) -> string {
	context = base_runtime.default_context()
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	queued := Queued_Spawn_Command {
		uuid = spawn.uuid,
		name = spawn.name,
		name_len = spawn.name_len,
		has_transform = spawn.has_transform,
		transform = spawn.transform,
		has_mesh = spawn.has_mesh,
		mesh = spawn.mesh,
		has_geometry = spawn.has_geometry,
		geometry = spawn.geometry,
		has_material = spawn.has_material,
		material = spawn.material,
		has_shadow_caster = spawn.has_shadow_caster,
		has_shadow_receiver = spawn.has_shadow_receiver,
		custom_component_start = len(buffer.components),
		custom_component_count = spawn.custom_component_count,
		ui_component_start = len(buffer.ui_components),
		ui_component_count = spawn.ui_component_count,
	}
	for index in 0 ..< spawn.custom_component_count {
		queue_component_payload(buffer, spawn.custom_components[index])
	}
	for index in 0 ..< spawn.ui_component_count {
		append(&buffer.ui_components, spawn.ui_components[index])
	}
	payload_index := len(buffer.spawns)
	append(&buffer.spawns, queued)
	append_command_header(buffer, .Spawn, payload_index)
	return ""
}

queue_despawn :: proc "c" (buffer: ^Command_Buffer, entity_index: int, generation: u32) -> string {
	context = base_runtime.default_context()
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	payload_index := len(buffer.despawns)
	append(&buffer.despawns, Despawn_Command{entity_index = entity_index, generation = generation})
	append_command_header(buffer, .Despawn, payload_index)
	return ""
}

queue_add_component_command :: proc "contextless" (
	buffer: ^Command_Buffer,
	command: Queued_Add_Component_Command,
) -> string {
	context = base_runtime.default_context()
	if buffer == nil || buffer.commands == nil {
		return "command buffer is not initialized"
	}
	payload_index := len(buffer.add_components)
	append(&buffer.add_components, command)
	append_command_header(buffer, .Add_Component, payload_index)
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
	return queue_add_component_command(
		buffer,
		Queued_Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			kind = .Transform,
			transform = transform,
		},
	)
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
	return queue_add_component_command(
		buffer,
		Queued_Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			kind = .Geometry,
			geometry = handle,
		},
	)
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
	return queue_add_component_command(
		buffer,
		Queued_Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			kind = .Material,
			material = handle,
		},
	)
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
	add := Queued_Add_Component_Command {
		entity_index = entity_index,
		generation = generation,
	}
	switch name {
		case "scrapbot.shadow_caster":
			add.kind = .Shadow_Caster
		case "scrapbot.shadow_receiver":
			add.kind = .Shadow_Receiver
		case:
			return "unsupported marker component"
	}
	return queue_add_component_command(buffer, add)
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
	add := Queued_Add_Component_Command {
		entity_index = entity_index,
		generation = generation,
		kind = .Mesh,
	}
	if err := copy_command_string(
		add.mesh.primitive[:],
		&add.mesh.primitive_len,
		primitive,
		"mesh primitive",
	); err != "" {
		return err
	}

	return queue_add_component_command(buffer, add)
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
	payload_index := queue_component_payload(buffer, command_component)
	return queue_add_component_command(
		buffer,
		Queued_Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			kind = .Custom,
			payload_index = payload_index,
		},
	)
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
	context = base_runtime.default_context()
	payload_index := len(buffer.ui_components)
	append(&buffer.ui_components, component)
	return queue_add_component_command(
		buffer,
		Queued_Add_Component_Command {
			entity_index = entity_index,
			generation = generation,
			kind = .UI,
			payload_index = payload_index,
		},
	)
}

queue_remove_component :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	component_id: Component_ID,
	name: string,
) -> string {
	context = base_runtime.default_context()
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.commands == nil {
		return "command buffer is not initialized"
	}
	remove: Remove_Component_Command
	remove.entity_index = entity_index
	remove.generation = generation
	remove.component_id = component_id
	if err := copy_command_string(remove.name[:], &remove.name_len, name, "component name");
	   err != "" {
		return err
	}

	payload_index := len(buffer.remove_components)
	append(&buffer.remove_components, remove)
	append_command_header(buffer, .Remove_Component, payload_index)
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
		header := &buffer.commands[command_index]
		switch header.kind {
			case .Spawn:
				spawn_queued_entity(world, buffer, &buffer.spawns[header.payload_index])
			case .Despawn:
				command := &buffer.despawns[header.payload_index]
				despawn_entity(world, command.entity_index, command.generation)
			case .Add_Component:
				apply_add_component(world, buffer, &buffer.add_components[header.payload_index])
			case .Remove_Component:
				apply_remove_component(world, &buffer.remove_components[header.payload_index])
		}
	}
	clear_commands(buffer)
	when ODIN_TEST || WORLD_INTEGRITY_CHECKS {
		if failure, ok := validate_world_integrity(world); !ok {
			return format_world_integrity_failure(failure)
		}
	}
	return ""
}

clear_commands :: proc "c" (buffer: ^Command_Buffer) {
	if buffer != nil {
		clear(&buffer.commands)
		clear(&buffer.spawns)
		clear(&buffer.components)
		clear(&buffer.number_fields)
		clear(&buffer.vec2_fields)
		clear(&buffer.vec3_fields)
		clear(&buffer.vec4_fields)
		clear(&buffer.ui_components)
		clear(&buffer.despawns)
		clear(&buffer.add_components)
		clear(&buffer.remove_components)
		buffer.command_count = 0
	}
}

append_queued_component :: proc "contextless" (
	destination, source: ^Command_Buffer,
	source_index: int,
) -> int {
	context = base_runtime.default_context()
	component := source.components[source_index]
	number_end := component.number_field_start + component.number_field_count
	vec2_end := component.vec2_field_start + component.vec2_field_count
	vec3_end := component.vec3_field_start + component.vec3_field_count
	vec4_end := component.vec4_field_start + component.vec4_field_count
	number_start := len(destination.number_fields)
	vec2_start := len(destination.vec2_fields)
	vec3_start := len(destination.vec3_fields)
	vec4_start := len(destination.vec4_fields)
	for index in component.number_field_start ..< number_end {
		append(&destination.number_fields, source.number_fields[index])
	}
	for index in component.vec2_field_start ..< vec2_end {
		append(&destination.vec2_fields, source.vec2_fields[index])
	}
	for index in component.vec3_field_start ..< vec3_end {
		append(&destination.vec3_fields, source.vec3_fields[index])
	}
	for index in component.vec4_field_start ..< vec4_end {
		append(&destination.vec4_fields, source.vec4_fields[index])
	}
	component.number_field_start = number_start
	component.vec2_field_start = vec2_start
	component.vec3_field_start = vec3_start
	component.vec4_field_start = vec4_start
	payload_index := len(destination.components)
	append(&destination.components, component)
	return payload_index
}

append_commands :: proc(destination, source: ^Command_Buffer) -> string {
	context = base_runtime.default_context()
	if destination == nil || source == nil || source.command_count == 0 {
		return ""
	}
	if destination.commands == nil || source.commands == nil {
		return "command buffer is not initialized"
	}
	if destination == source {
		return "cannot append a command buffer to itself"
	}
	for header in source.commands {
		switch header.kind {
			case .Spawn:
				spawn := source.spawns[header.payload_index]
				component_start := len(destination.components)
				ui_component_start := len(destination.ui_components)
				component_end := spawn.custom_component_start + spawn.custom_component_count
				ui_component_end := spawn.ui_component_start + spawn.ui_component_count
				for index in spawn.custom_component_start ..< component_end {
					append_queued_component(destination, source, index)
				}
				for index in spawn.ui_component_start ..< ui_component_end {
					append(&destination.ui_components, source.ui_components[index])
				}
				spawn.custom_component_start = component_start
				spawn.ui_component_start = ui_component_start
				payload_index := len(destination.spawns)
				append(&destination.spawns, spawn)
				append_command_header(destination, .Spawn, payload_index)
			case .Despawn:
				payload_index := len(destination.despawns)
				append(&destination.despawns, source.despawns[header.payload_index])
				append_command_header(destination, .Despawn, payload_index)
			case .Add_Component:
				command := source.add_components[header.payload_index]
				source_payload_index := command.payload_index
				#partial switch command.kind {
					case .Custom:
						command.payload_index = append_queued_component(
							destination,
							source,
							source_payload_index,
						)
					case .UI:
						command.payload_index = len(destination.ui_components)
						append(
							&destination.ui_components,
							source.ui_components[source_payload_index],
						)
				}
				payload_index := len(destination.add_components)
				append(&destination.add_components, command)
				append_command_header(destination, .Add_Component, payload_index)
			case .Remove_Component:
				payload_index := len(destination.remove_components)
				append(
					&destination.remove_components,
					source.remove_components[header.payload_index],
				)
				append_command_header(destination, .Remove_Component, payload_index)
		}
	}
	clear_commands(source)
	return ""
}

spawn_entity :: proc(world: ^World, spawn: ^Spawn_Command) -> int {
	if world == nil || spawn == nil {
		return INVALID_COMPONENT_INDEX
	}
	buffer: Command_Buffer
	init_command_buffer_capacity(&buffer, 1)
	defer destroy_command_buffer(&buffer)
	if queue_spawn_command(&buffer, spawn^) != "" {
		return INVALID_COMPONENT_INDEX
	}
	entity_index := spawn_queued_entity(world, &buffer, &buffer.spawns[0])
	spawn.uuid = buffer.spawns[0].uuid
	return entity_index
}

spawn_queued_entity :: proc(
	world: ^World,
	buffer: ^Command_Buffer,
	spawn: ^Queued_Spawn_Command,
) -> int {
	context = base_runtime.default_context()
	entity_index, created := create_world_entity(
		world,
		queued_spawn_command_name(spawn),
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
		component_index := spawn.custom_component_start + i
		add_queued_custom_component(world, entity_index, buffer, component_index)
	}
	for i in 0 ..< spawn.ui_component_count {
		component := &buffer.ui_components[spawn.ui_component_start + i]
		apply_ui_component(world, entity_index, component)
	}
	mark_render_entity_dirty(world, entity_index)
	return entity_index
}

despawn_model_instance_entities :: proc(world: ^World, owner: shared.Entity_UUID) {
	if world == nil || owner == (shared.Entity_UUID{}) {
		return
	}
	for candidate, candidate_index in world.entities {
		if !candidate.alive || candidate.model_owner != owner {
			continue
		}
		despawn_entity(world, candidate_index, candidate.id.generation)
	}
}

despawn_entity :: proc(world: ^World, entity_index: int, generation: u32) {
	if !entity_is_current(world, entity_index, generation) {
		return
	}
	if world.entities[entity_index].model_resource != "" {
		despawn_model_instance_entities(world, world.entities[entity_index].uuid)
	}
	mark_render_entity_dirty(world, entity_index)
	detach_transform_children(world, entity_index)

	entity := &world.entities[entity_index]
	world.live_entity_count = max(world.live_entity_count - 1, 0)
	switch entity.origin {
		case .Scene:
			world.scene_entity_count = max(world.scene_entity_count - 1, 0)
		case .Runtime:
			world.runtime_entity_count = max(world.runtime_entity_count - 1, 0)
		case .Editor:
			world.editor_entity_count = max(world.editor_entity_count - 1, 0)
	}
	if world.entity_by_uuid != nil {
		delete_key(&world.entity_by_uuid, entity.uuid)
	}
	if entity.ui_layout_index >= 0 {
		mark_ui_subtree_dirty(world, entity_index)
	}
	delete_world_string(world, entity.name)
	delete_world_string(world, entity.geometry_resource)
	delete_world_string(world, entity.material_resource)
	delete_world_string(world, entity.model_resource)
	entity.name = ""
	entity.geometry_resource = ""
	entity.material_resource = ""
	entity.model_resource = ""
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
		binding := &world.editor_uis[entity.editor_ui_index]
		if world.editor_ui_by_role_slot != nil {
			delete_key(
				&world.editor_ui_by_role_slot,
				shared.Editor_UI_Lookup_Key{role = binding.role, slot = binding.slot},
			)
		}
		binding.entity_index = INVALID_COMPONENT_INDEX
	}
	entity.editor_ui_index = INVALID_COMPONENT_INDEX
	entity.has_shadow_caster = false
	entity.has_shadow_receiver = false
	append(&world.free_entity_indices, entity_index)
}

apply_add_component :: proc(
	world: ^World,
	buffer: ^Command_Buffer,
	command: ^Queued_Add_Component_Command,
) {
	if !entity_is_current(world, command.entity_index, command.generation) {
		return
	}
	switch command.kind {
		case .Transform:
			add_transform(world, command.entity_index, command.transform)
		case .Mesh:
			add_mesh(world, command.entity_index, command_mesh_primitive(&command.mesh))
		case .Geometry:
			add_geometry(world, command.entity_index, command.geometry)
		case .Material:
			add_material(world, command.entity_index, command.material)
		case .Shadow_Caster:
			if !world.entities[command.entity_index].has_shadow_caster {
				world.entities[command.entity_index].has_shadow_caster = true
				bump_component_revision(world, command.entity_index)
				mark_render_entity_dirty(world, command.entity_index)
			}
		case .Shadow_Receiver:
			if !world.entities[command.entity_index].has_shadow_receiver {
				world.entities[command.entity_index].has_shadow_receiver = true
				bump_component_revision(world, command.entity_index)
				mark_render_entity_dirty(world, command.entity_index)
			}
		case .Custom:
			add_queued_custom_component(world, command.entity_index, buffer, command.payload_index)
		case .UI:
			apply_ui_component(
				world,
				command.entity_index,
				&buffer.ui_components[command.payload_index],
			)
	}
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
	if name == "scrapbot.shadow_caster" {
		if world.entities[command.entity_index].has_shadow_caster {
			world.entities[command.entity_index].has_shadow_caster = false
			bump_component_revision(world, command.entity_index)
			mark_render_entity_dirty(world, command.entity_index)
		}
		return
	}
	if name == "scrapbot.shadow_receiver" {
		if world.entities[command.entity_index].has_shadow_receiver {
			world.entities[command.entity_index].has_shadow_receiver = false
			bump_component_revision(world, command.entity_index)
			mark_render_entity_dirty(world, command.entity_index)
		}
		return
	}
	if remove_ui_component(world, command.entity_index, name) {
		return
	}
	remove_custom_component(world, command.entity_index, command.component_id, name)
}

spawn_command_name :: proc(spawn: ^Spawn_Command) -> string {
	return string(spawn.name[:spawn.name_len])
}

queued_spawn_command_name :: proc(spawn: ^Queued_Spawn_Command) -> string {
	return string(spawn.name[:spawn.name_len])
}

command_component_name :: proc(command_component: ^Command_Component) -> string {
	return string(command_component.name[:command_component.name_len])
}

queued_command_component_name :: proc(component: ^Queued_Command_Component) -> string {
	return string(component.name[:component.name_len])
}

command_field_name :: proc(field: ^Command_Vec3_Field) -> string {
	return string(field.name[:field.name_len])
}

command_number_field_name :: proc(field: ^Command_Number_Field) -> string {
	if field == nil { return "" }
	return string(field.name[:field.name_len])
}

command_vec2_field_name :: proc(field: ^Command_Vec2_Field) -> string {
	if field == nil { return "" }
	return string(field.name[:field.name_len])
}

command_vec4_field_name :: proc(field: ^Command_Vec4_Field) -> string {
	if field == nil { return "" }
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
