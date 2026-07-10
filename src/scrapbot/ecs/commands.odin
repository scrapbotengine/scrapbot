package ecs

MAX_COMMANDS :: 128
MAX_SPAWN_NAME_BYTES :: 64

Command_Kind :: enum {
	Spawn,
	Despawn,
}

Spawn_Command :: struct {
	name:     [MAX_SPAWN_NAME_BYTES]u8,
	name_len: int,
}

Command :: struct {
	kind: Command_Kind,
	spawn: Spawn_Command,
	entity_index: int,
}

Command_Buffer :: struct {
	commands: [MAX_COMMANDS]Command,
	command_count: int,
}

queue_spawn :: proc "c" (buffer: ^Command_Buffer, name: string) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.command_count >= MAX_COMMANDS {
		return "too many deferred world commands"
	}
	if len(name) >= MAX_SPAWN_NAME_BYTES {
		return "spawn name is too long"
	}

	command := &buffer.commands[buffer.command_count]
	command^ = Command{kind = .Spawn}
	command.spawn.name_len = len(name)
	name_bytes := (cast([^]u8)raw_data(name))[:len(name)]
	for byte_value, index in name_bytes {
		command.spawn.name[index] = byte_value
	}
	buffer.command_count += 1
	return ""
}

queue_despawn :: proc "c" (buffer: ^Command_Buffer, entity_index: int) -> string {
	if buffer == nil {
		return "command buffer is not available"
	}
	if buffer.command_count >= MAX_COMMANDS {
		return "too many deferred world commands"
	}

	buffer.commands[buffer.command_count] = Command {
		kind         = .Despawn,
		entity_index = entity_index,
	}
	buffer.command_count += 1
	return ""
}

apply_commands :: proc(world: ^World, buffer: ^Command_Buffer) -> string {
	if world == nil || buffer == nil {
		return ""
	}

	for command_index in 0..<buffer.command_count {
		command := &buffer.commands[command_index]
		switch command.kind {
		case .Spawn:
			spawn_entity(world, spawn_command_name(&command.spawn))
		case .Despawn:
			despawn_entity(world, command.entity_index)
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

spawn_entity :: proc(world: ^World, name: string) -> int {
	entity_index := len(world.entities)
	id := Entity{index = u32(entity_index), generation = 1}
	append(
		&world.entities,
		World_Entity {
			id              = id,
			alive           = true,
			name            = clone_world_string(name),
			transform_index = INVALID_COMPONENT_INDEX,
			camera_index    = INVALID_COMPONENT_INDEX,
			mesh_index      = INVALID_COMPONENT_INDEX,
		},
	)
	return entity_index
}

despawn_entity :: proc(world: ^World, entity_index: int) {
	if !entity_is_alive(world, entity_index) {
		return
	}

	entity := &world.entities[entity_index]
	delete(entity.name)
	entity.name = ""
	entity.alive = false
	entity.id.generation += 1
	entity.transform_index = INVALID_COMPONENT_INDEX
	entity.camera_index = INVALID_COMPONENT_INDEX
	entity.mesh_index = INVALID_COMPONENT_INDEX
}

spawn_command_name :: proc(spawn: ^Spawn_Command) -> string {
	return string(spawn.name[:spawn.name_len])
}
