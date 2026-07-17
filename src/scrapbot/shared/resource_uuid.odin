package shared

import "core:crypto"
import "core:encoding/uuid"

Resource_UUID :: distinct uuid.Identifier

resource_uuid_parse :: proc(value: string) -> (Resource_UUID, bool) {
	id, err := uuid.read(value)
	resource_id := Resource_UUID(id)
	return resource_id, err == .None && resource_id != Resource_UUID{}
}

resource_uuid_generate :: proc() -> Resource_UUID {
	previous := context.random_generator
	context.random_generator = crypto.random_generator()
	defer context.random_generator = previous
	return Resource_UUID(uuid.generate_v4())
}

resource_uuid_to_string :: proc "contextless" (id: Resource_UUID, buffer: []u8) -> string {
	if len(buffer) < 36 {
		return ""
	}
	hex := "0123456789abcdef"
	out_index := 0
	bytes := uuid.Identifier(id)
	for byte, byte_index in bytes {
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
