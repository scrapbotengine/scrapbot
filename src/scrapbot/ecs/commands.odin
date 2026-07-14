package ecs

import shared "../shared"

MAX_COMMANDS :: 128
MAX_COMMAND_NAME_BYTES :: 64
MAX_COMMAND_COMPONENTS :: 8
MAX_COMMAND_FIELDS :: 16

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

Command_Mesh :: struct {
	primitive: [MAX_COMMAND_NAME_BYTES]u8,
	primitive_len: int,
}

Spawn_Command :: struct {
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
}

init_command_buffer :: proc(buffer: ^Command_Buffer) {
	buffer^ = {}
	buffer.commands = make([]Command, MAX_COMMANDS)
}

destroy_command_buffer :: proc(buffer: ^Command_Buffer) {
	delete(buffer.commands)
	buffer^ = {}
}

queue_spawn :: proc "c" (buffer: ^Command_Buffer, name: string) -> string {
	spawn: Spawn_Command
	if err := init_spawn_command(&spawn, name); err != "" {
		return err
	}
	return queue_spawn_command(buffer, spawn)
}

init_spawn_command :: proc "c" (spawn: ^Spawn_Command, name: string) -> string {
	if spawn == nil {
		return "spawn command is not available"
	}
	spawn^ = {}
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
	if buffer.command_count >= len(buffer.commands) {
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
	if buffer.command_count >= len(buffer.commands) {
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
	if buffer.command_count >= len(buffer.commands) {
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
	if buffer == nil ||
	   buffer.commands ==
		   nil { return "command buffer is not initialized" }; if buffer.command_count >= len(buffer.commands) { return "too many deferred world commands" }
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = {
			entity_index = entity_index,
			generation = generation,
			has_geometry = true,
			geometry = handle,
		},
	}; buffer.command_count += 1; return ""
}

queue_add_material :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	handle: Material_Handle,
) -> string {
	if buffer == nil ||
	   buffer.commands ==
		   nil { return "command buffer is not initialized" }; if buffer.command_count >= len(buffer.commands) { return "too many deferred world commands" }
	buffer.commands[buffer.command_count] = {
		kind = .Add_Component,
		add_component = {
			entity_index = entity_index,
			generation = generation,
			has_material = true,
			material = handle,
		},
	}; buffer.command_count += 1; return ""
}

queue_add_marker :: proc "c" (
	buffer: ^Command_Buffer,
	entity_index: int,
	generation: u32,
	name: string,
) -> string {
	if buffer == nil || buffer.commands == nil { return "command buffer is not initialized" }
	if buffer.command_count >= len(buffer.commands) { return "too many deferred world commands" }
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
	if buffer.command_count >= len(buffer.commands) {
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
	if buffer.command_count >= len(buffer.commands) {
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
	if buffer.command_count >= len(buffer.commands) {
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
	if destination.command_count + source.command_count > len(destination.commands) {
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
	entity_index := len(world.entities)
	generation := u32(1)
	reusing_slot := false
	for entity, index in world.entities {
		if entity.alive {
			continue
		}
		entity_index = index
		generation = entity.id.generation
		reusing_slot = true
		break
	}
	id := Entity {
		index = u32(entity_index),
		generation = generation,
	}
	transform_index := INVALID_COMPONENT_INDEX
	if spawn.has_transform {
		transform_index = allocate_transform_slot(world, spawn.transform)
	}
	mesh_index := INVALID_COMPONENT_INDEX
	if spawn.has_mesh {
		mesh_index = allocate_mesh_slot(world, command_mesh_primitive(&spawn.mesh))
	}

	world_entity := World_Entity {
		id = id,
		alive = true,
		origin = .Runtime,
		name = clone_world_string(spawn_command_name(spawn)),
		transform_index = transform_index,
		camera_index = INVALID_COMPONENT_INDEX,
		ambient_light_index = INVALID_COMPONENT_INDEX,
		directional_light_index = INVALID_COMPONENT_INDEX,
		point_light_index = INVALID_COMPONENT_INDEX,
		mesh_index = mesh_index,
		geometry_index = INVALID_COMPONENT_INDEX,
		material_index = INVALID_COMPONENT_INDEX,
		render_instance_index = INVALID_COMPONENT_INDEX,
		ui_layout_index = INVALID_COMPONENT_INDEX,
		ui_hstack_index = INVALID_COMPONENT_INDEX,
		ui_vstack_index = INVALID_COMPONENT_INDEX,
		ui_scroll_area_index = INVALID_COMPONENT_INDEX,
		ui_panel_index = INVALID_COMPONENT_INDEX,
		ui_table_index = INVALID_COMPONENT_INDEX,
		ui_text_index = INVALID_COMPONENT_INDEX,
		ui_button_index = INVALID_COMPONENT_INDEX,
		ui_input_index = INVALID_COMPONENT_INDEX,
		editor_transform_gizmo_index = INVALID_COMPONENT_INDEX,
		editor_ui_index = INVALID_COMPONENT_INDEX,
		has_shadow_caster = spawn.has_shadow_caster,
		has_shadow_receiver = spawn.has_shadow_receiver,
	}
	if reusing_slot {
		world.entities[entity_index] = world_entity
	} else {
		append(&world.entities, world_entity)
	}
	ensure_entity_renderable(world, entity_index)
	if spawn.has_geometry { add_geometry(world, entity_index, spawn.geometry) }
	if spawn.has_material { add_material(world, entity_index, spawn.material) }

	for i in 0 ..< spawn.custom_component_count {
		add_custom_component(world, entity_index, &spawn.custom_components[i])
	}
	return entity_index
}

despawn_entity :: proc(world: ^World, entity_index: int, generation: u32) {
	if !entity_is_current(world, entity_index, generation) {
		return
	}

	entity := &world.entities[entity_index]
	delete(entity.name)
	delete(entity.geometry_resource)
	delete(entity.material_resource)
	entity.name = ""
	entity.geometry_resource = ""
	entity.material_resource = ""
	entity.alive = false
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
	entity.mesh_index = INVALID_COMPONENT_INDEX
	entity.geometry_index = INVALID_COMPONENT_INDEX
	entity.material_index = INVALID_COMPONENT_INDEX
	for &storage in world.custom_components {
		for &component in storage.components {
			if component.entity_index != entity_index {
				continue
			}
			delete(component.name)
			component.name = ""
			component.entity_index = INVALID_COMPONENT_INDEX
			component.component_id = shared.INVALID_COMPONENT_ID
			for field in component.vec3_fields {
				delete(field.name)
			}
			delete(component.vec3_fields)
			component.vec3_fields = nil
		}
	}
	if entity.editor_transform_gizmo_index >= 0 &&
	   entity.editor_transform_gizmo_index <
		   len(
			   world.editor_transform_gizmos,
		   ) { world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index = INVALID_COMPONENT_INDEX }
	entity.editor_transform_gizmo_index = INVALID_COMPONENT_INDEX
	for &camera in world.editor_scene_cameras { if camera.entity_index == entity_index { camera.entity_index = INVALID_COMPONENT_INDEX } }
	entity.has_shadow_caster = false
	entity.has_shadow_receiver = false
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
	if command.has_shadow_caster { world.entities[command.entity_index].has_shadow_caster = true; return }
	if command.has_shadow_receiver { world.entities[command.entity_index].has_shadow_receiver = true; return }
	add_custom_component(world, command.entity_index, &command.component)
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
	   "scrapbot.shadow_caster" { world.entities[command.entity_index].has_shadow_caster = false; return }
	if name ==
	   "scrapbot.shadow_receiver" { world.entities[command.entity_index].has_shadow_receiver = false; return }
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
