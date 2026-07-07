package render

import "core:hash"
import "core:os"

PNG_SIGNATURE :: []u8{0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'}
PNG_ZLIB_MOD :: u32(65521)

write_png_rgba8 :: proc(path: string, pixels: []u8, width, height: u32) -> string {
	expected_len := int(width * height * 4)
	if len(pixels) != expected_len {
		return "png framegrab pixel buffer has the wrong size"
	}

	out: [dynamic]u8
	defer delete(out)
	append(&out, ..PNG_SIGNATURE)

	ihdr: [13]u8
	write_u32_be(ihdr[0:4], width)
	write_u32_be(ihdr[4:8], height)
	ihdr[8] = 8
	ihdr[9] = 6
	append_png_chunk(&out, "IHDR", ihdr[:])

	raw: [dynamic]u8
	defer delete(raw)
	row_bytes := int(width * 4)
	for y in 0 ..< int(height) {
		append(&raw, 0)
		start := y * row_bytes
		append(&raw, ..pixels[start:start + row_bytes])
	}

	idat := build_zlib_stored_stream(raw[:])
	defer delete(idat)
	append_png_chunk(&out, "IDAT", idat[:])
	append_png_chunk(&out, "IEND", nil)

	if err := os.write_entire_file(path, out[:]); err != nil {
		return "failed to write PNG framegrab"
	}
	return ""
}

append_png_chunk :: proc(out: ^[dynamic]u8, kind: string, data: []u8) {
	append_u32_be(out, u32(len(data)))

	kind_start := len(out)
	append(out, kind[0], kind[1], kind[2], kind[3])
	append(out, ..data)

	crc := hash.crc32(out[kind_start:])
	append_u32_be(out, crc)
}

build_zlib_stored_stream :: proc(raw: []u8) -> [dynamic]u8 {
	out: [dynamic]u8
	append(&out, 0x78, 0x01)

	remaining := raw
	for len(remaining) > 0 {
		block_len := min(len(remaining), 65535)
		final := block_len == len(remaining)
		if final {
			append(&out, 0x01)
		} else {
			append(&out, 0x00)
		}
		append_u16_le(&out, u16(block_len))
		append_u16_le(&out, ~u16(block_len))
		append(&out, ..remaining[:block_len])
		remaining = remaining[block_len:]
	}

	append_u32_be(&out, adler32(raw))
	return out
}

adler32 :: proc(data: []u8) -> u32 {
	s1 := u32(1)
	s2 := u32(0)
	for byte in data {
		s1 = (s1 + u32(byte)) % PNG_ZLIB_MOD
		s2 = (s2 + s1) % PNG_ZLIB_MOD
	}
	return (s2 << 16) | s1
}

append_u16_le :: proc(out: ^[dynamic]u8, value: u16) {
	append(out, u8(value), u8(value >> 8))
}

append_u32_be :: proc(out: ^[dynamic]u8, value: u32) {
	append(out, u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value))
}

write_u32_be :: proc(out: []u8, value: u32) {
	out[0] = u8(value >> 24)
	out[1] = u8(value >> 16)
	out[2] = u8(value >> 8)
	out[3] = u8(value)
}
