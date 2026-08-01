package resources

import "core:fmt"
import "core:mem"
import "core:os"

read_geometry_page_payload :: proc(
	geometry: ^Geometry,
	page_index: int,
	allocator: mem.Allocator = context.allocator,
) -> (
	[]u8,
	string,
) {
	if geometry == nil || page_index < 0 || page_index >= len(geometry.page_payload_records) {
		return nil, "geometry page is out of bounds"
	}
	record := geometry.page_payload_records[page_index]
	if record.size == 0 || record.size > u64(max(int)) {
		return nil, "geometry page size is invalid"
	}
	bytes := make([]u8, int(record.size), allocator)
	#partial switch geometry.page_source_kind {
		case .Memory:
			end := record.offset + record.size
			if end > u64(len(geometry.page_payload_bytes)) {
				delete(bytes, allocator)
				return nil, "geometry memory page is truncated"
			}
			copy(bytes, geometry.page_payload_bytes[int(record.offset):int(end)])
		case .File:
			file, open_err := os.open(geometry.page_source_path)
			if open_err != nil {
				delete(bytes, allocator)
				return nil, fmt.tprintf("failed to open geometry page source: %v", open_err)
			}
			defer os.close(file)
			read_count, read_err := os.read_at(file, bytes, i64(record.offset))
			if read_err != nil || read_count != len(bytes) {
				delete(bytes, allocator)
				return nil, "failed to read complete geometry page"
			}
	}
	return bytes, ""
}

geometry_page_vertex_bytes :: proc(geometry: ^Geometry, page_index: int) -> u64 {
	if geometry == nil || page_index < 0 || page_index >= len(geometry.page_payload_records) {
		return 0
	}
	return u64(geometry.page_payload_records[page_index].vertex_count) * u64(size_of(Vertex))
}
