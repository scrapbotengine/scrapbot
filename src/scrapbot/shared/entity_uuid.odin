package shared

import "core:crypto"
import "core:encoding/uuid"

Entity_UUID :: uuid.Identifier

entity_uuid_parse :: proc(value: string) -> (Entity_UUID, bool) {
	id, err := uuid.read(value)
	return id, err == .None && id != Entity_UUID{}
}

entity_uuid_generate :: proc() -> Entity_UUID {
	previous := context.random_generator
	context.random_generator = crypto.random_generator()
	defer context.random_generator = previous
	return uuid.generate_v4()
}

entity_uuid_from_engine_name :: proc(value: string) -> Entity_UUID {
	return uuid.generate_v8_hash(uuid.Namespace_URL, value, .SHA256)
}

entity_uuid_to_string :: proc "contextless" (id: Entity_UUID, buffer: []u8) -> string {
	if len(buffer) < 36 { return "" }
	hex := "0123456789abcdef"
	out_index := 0
	for byte, byte_index in id {
		if byte_index == 4 || byte_index == 6 || byte_index == 8 || byte_index == 10 {
			buffer[out_index] = '-'
			out_index += 1
		}
		buffer[out_index] = hex[byte >> 4]
		buffer[out_index + 1] = hex[byte & 0x0f]
		out_index += 2
	}
	return string(buffer[:36])
}
