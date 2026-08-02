package asset_import

import "core:encoding/endian"
import "core:fmt"
import "core:os"

ASSET_PRODUCT_MAGIC :: [8]u8{'S', 'B', 'P', 'R', 'O', 'D', '0', '1'}
ASSET_PRODUCT_FORMAT_VERSION: u32 : 1
ASSET_PRODUCT_HEADER_SIZE :: 24
ASSET_PRODUCT_CHUNK_ENTRY_SIZE :: 40
ASSET_PRODUCT_MAX_CHUNKS :: 1024

Asset_Product_Chunk_Kind :: enum u32 {
	Model_Runtime = 1,
}

Asset_Product_Chunk :: struct {
	kind: Asset_Product_Chunk_Kind,
	index: u32,
	flags: u32,
	offset: u64,
	stored_size: u64,
	decoded_size: u64,
}

Asset_Product_Directory :: struct {
	kind: Product_Kind,
	chunks: []Asset_Product_Chunk,
}

destroy_asset_product_directory :: proc(directory: ^Asset_Product_Directory) {
	if directory == nil {
		return
	}
	delete(directory.chunks)
	directory^ = {}
}

asset_product_begin :: proc(bytes: ^[dynamic]u8, kind: Product_Kind, chunk_count: int) -> bool {
	if bytes == nil ||
	   len(bytes^) != 0 ||
	   chunk_count <= 0 ||
	   chunk_count > ASSET_PRODUCT_MAX_CHUNKS {
		return false
	}
	resize(bytes, ASSET_PRODUCT_HEADER_SIZE + chunk_count * ASSET_PRODUCT_CHUNK_ENTRY_SIZE)
	magic := ASSET_PRODUCT_MAGIC
	copy(bytes^[:len(magic)], magic[:])
	asset_product_put_u32(bytes^[:], 8, ASSET_PRODUCT_FORMAT_VERSION)
	asset_product_put_u32(bytes^[:], 12, u32(kind) + 1)
	asset_product_put_u32(bytes^[:], 16, u32(chunk_count))
	asset_product_put_u32(bytes^[:], 20, 0)
	return true
}

asset_product_begin_chunk :: proc(
	bytes: ^[dynamic]u8,
	entry_index: int,
	kind: Asset_Product_Chunk_Kind,
	index: u32 = 0,
) -> (
	offset: int,
	ok: bool,
) {
	if bytes == nil || entry_index < 0 {
		return 0, false
	}
	chunk_count := asset_product_get_u32(bytes^[:], 16)
	if entry_index >= int(chunk_count) {
		return 0, false
	}
	entry_offset := ASSET_PRODUCT_HEADER_SIZE + entry_index * ASSET_PRODUCT_CHUNK_ENTRY_SIZE
	offset = len(bytes^)
	asset_product_put_u32(bytes^[:], entry_offset, u32(kind))
	asset_product_put_u32(bytes^[:], entry_offset + 4, index)
	asset_product_put_u32(bytes^[:], entry_offset + 8, 0)
	asset_product_put_u32(bytes^[:], entry_offset + 12, 0)
	asset_product_put_u64(bytes^[:], entry_offset + 16, u64(offset))
	return offset, true
}

asset_product_finish_chunk :: proc(bytes: ^[dynamic]u8, entry_index, chunk_offset: int) -> bool {
	if bytes == nil || chunk_offset < 0 || chunk_offset > len(bytes^) || entry_index < 0 {
		return false
	}
	chunk_count := asset_product_get_u32(bytes^[:], 16)
	if entry_index >= int(chunk_count) {
		return false
	}
	entry_offset := ASSET_PRODUCT_HEADER_SIZE + entry_index * ASSET_PRODUCT_CHUNK_ENTRY_SIZE
	if asset_product_get_u64(bytes^[:], entry_offset + 16) != u64(chunk_offset) {
		return false
	}
	size := u64(len(bytes^) - chunk_offset)
	asset_product_put_u64(bytes^[:], entry_offset + 24, size)
	asset_product_put_u64(bytes^[:], entry_offset + 32, size)
	return size > 0
}

read_asset_product_directory :: proc(
	file: ^os.File,
	file_size: int,
	expected_kind: Product_Kind,
) -> (
	directory: Asset_Product_Directory,
	err: string,
) {
	if file == nil || file_size < ASSET_PRODUCT_HEADER_SIZE {
		return {}, "asset product is truncated"
	}
	header: [ASSET_PRODUCT_HEADER_SIZE]u8
	if !asset_product_read_exact(file, header[:], 0) {
		return {}, "failed to read asset product header"
	}
	magic := ASSET_PRODUCT_MAGIC
	if string(header[:len(magic)]) != string(magic[:]) {
		return {}, "asset product has an invalid header"
	}
	version := asset_product_get_u32(header[:], 8)
	kind_value := asset_product_get_u32(header[:], 12)
	chunk_count := asset_product_get_u32(header[:], 16)
	reserved := asset_product_get_u32(header[:], 20)
	if version != ASSET_PRODUCT_FORMAT_VERSION {
		return {}, fmt.tprintf("asset product format version %d is not supported", version)
	}
	if kind_value != u32(expected_kind) + 1 {
		return {}, "asset product kind does not match its resource"
	}
	if chunk_count == 0 || chunk_count > ASSET_PRODUCT_MAX_CHUNKS || reserved != 0 {
		return {}, "asset product directory is invalid"
	}
	directory_size := ASSET_PRODUCT_HEADER_SIZE + int(chunk_count) * ASSET_PRODUCT_CHUNK_ENTRY_SIZE
	if directory_size > file_size {
		return {}, "asset product directory is truncated"
	}
	entry_bytes := make(
		[]u8,
		int(chunk_count) * ASSET_PRODUCT_CHUNK_ENTRY_SIZE,
		context.temp_allocator,
	)
	if !asset_product_read_exact(file, entry_bytes, ASSET_PRODUCT_HEADER_SIZE) {
		return {}, "failed to read asset product directory"
	}
	directory.kind = expected_kind
	directory.chunks = make([]Asset_Product_Chunk, int(chunk_count))
	previous_end := u64(directory_size)
	for &chunk, entry_index in directory.chunks {
		offset := entry_index * ASSET_PRODUCT_CHUNK_ENTRY_SIZE
		kind := asset_product_get_u32(entry_bytes, offset)
		chunk.kind = Asset_Product_Chunk_Kind(kind)
		chunk.index = asset_product_get_u32(entry_bytes, offset + 4)
		chunk.flags = asset_product_get_u32(entry_bytes, offset + 8)
		reserved_entry := asset_product_get_u32(entry_bytes, offset + 12)
		chunk.offset = asset_product_get_u64(entry_bytes, offset + 16)
		chunk.stored_size = asset_product_get_u64(entry_bytes, offset + 24)
		chunk.decoded_size = asset_product_get_u64(entry_bytes, offset + 32)
		chunk_end := chunk.offset + chunk.stored_size
		if kind == 0 ||
		   chunk.flags != 0 ||
		   reserved_entry != 0 ||
		   chunk.offset < previous_end ||
		   chunk.stored_size == 0 ||
		   chunk.decoded_size != chunk.stored_size ||
		   chunk_end < chunk.offset ||
		   chunk_end > u64(file_size) {
			destroy_asset_product_directory(&directory)
			return {}, "asset product chunk directory is invalid"
		}
		for previous in directory.chunks[:entry_index] {
			if previous.kind == chunk.kind && previous.index == chunk.index {
				destroy_asset_product_directory(&directory)
				return {}, "asset product chunk identity is duplicated"
			}
		}
		previous_end = chunk_end
	}
	if previous_end != u64(file_size) {
		destroy_asset_product_directory(&directory)
		return {}, "asset product has trailing data"
	}
	return directory, ""
}

asset_product_find_chunk :: proc(
	directory: ^Asset_Product_Directory,
	kind: Asset_Product_Chunk_Kind,
	index: u32 = 0,
) -> (
	Asset_Product_Chunk,
	bool,
) {
	if directory == nil {
		return {}, false
	}
	for chunk in directory.chunks {
		if chunk.kind == kind && chunk.index == index {
			return chunk, true
		}
	}
	return {}, false
}

asset_product_read_exact :: proc(file: ^os.File, destination: []u8, offset: int) -> bool {
	if file == nil || offset < 0 {
		return false
	}
	read_count, read_err := os.read_at(file, destination, i64(offset))
	return read_err == nil && read_count == len(destination)
}

asset_product_put_u32 :: proc(bytes: []u8, offset: int, value: u32) {
	endian.unchecked_put_u32le(bytes[offset:], value)
}

asset_product_put_u64 :: proc(bytes: []u8, offset: int, value: u64) {
	endian.unchecked_put_u64le(bytes[offset:], value)
}

asset_product_get_u32 :: proc(bytes: []u8, offset: int) -> u32 {
	return endian.unchecked_get_u32le(bytes[offset:])
}

asset_product_get_u64 :: proc(bytes: []u8, offset: int) -> u64 {
	return endian.unchecked_get_u64le(bytes[offset:])
}
