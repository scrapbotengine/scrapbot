package render

import "core:fmt"
import wgpu "vendor:wgpu"

WGPU_GEOMETRY_VERTEX_ARENA_INITIAL_BYTES :: u64(4 * 1024 * 1024)
WGPU_GEOMETRY_INDEX_ARENA_INITIAL_BYTES :: u64(4 * 1024 * 1024)

WGPU_Arena_Range :: struct {
	offset: u64,
	size: u64,
}

WGPU_Arena_Allocator :: struct {
	free_ranges: [dynamic]WGPU_Arena_Range,
	high_water: u64,
	resident_bytes: u64,
}

WGPU_Arena_Retirement :: struct {
	range: WGPU_Arena_Range,
	after_frame: u64,
}

WGPU_Geometry_Arena :: struct {
	buffer: wgpu.Buffer,
	allocator: WGPU_Arena_Allocator,
	retirements: [dynamic]WGPU_Arena_Retirement,
	capacity: u64,
	initial_size: u64,
	usage: wgpu.BufferUsageFlags,
	label: string,
	growth_count: u64,
	upload_count: u64,
	upload_bytes: u64,
}

wgpu_geometry_arena_retire :: proc(
	arena: ^WGPU_Geometry_Arena,
	allocation: WGPU_Arena_Range,
	after_frame: u64,
) {
	if arena == nil || allocation.size == 0 {
		return
	}
	append(
		&arena.retirements,
		WGPU_Arena_Retirement{range = allocation, after_frame = after_frame},
	)
}

wgpu_geometry_arena_reclaim :: proc(
	arena: ^WGPU_Geometry_Arena,
	completed_frame: u64,
) -> (
	reclaimed_count: int,
	reclaimed_bytes: u64,
) {
	if arena == nil {
		return
	}
	write_index := 0
	for retirement in arena.retirements {
		if retirement.after_frame > completed_frame {
			arena.retirements[write_index] = retirement
			write_index += 1
			continue
		}
		wgpu_arena_release(&arena.allocator, retirement.range)
		reclaimed_count += 1
		reclaimed_bytes += retirement.range.size
	}
	resize(&arena.retirements, write_index)
	return
}

wgpu_align_arena_offset :: proc "contextless" (value, alignment: u64) -> u64 {
	if alignment <= 1 {
		return value
	}
	return (value + alignment - 1) / alignment * alignment
}

wgpu_arena_allocate :: proc(
	allocator: ^WGPU_Arena_Allocator,
	size, alignment: u64,
) -> WGPU_Arena_Range {
	if allocator == nil || size == 0 {
		return {}
	}
	for free_range, index in allocator.free_ranges {
		offset := wgpu_align_arena_offset(free_range.offset, alignment)
		end := offset + size
		free_end := free_range.offset + free_range.size
		if end > free_end {
			continue
		}
		prefix := offset - free_range.offset
		suffix := free_end - end
		if prefix > 0 {
			allocator.free_ranges[index].size = prefix
			if suffix > 0 {
				append(&allocator.free_ranges, WGPU_Arena_Range{offset = end, size = suffix})
				wgpu_sort_arena_free_ranges(allocator)
			}
		} else if suffix > 0 {
			allocator.free_ranges[index] = {
				offset = end,
				size = suffix,
			}
		} else {
			ordered_remove(&allocator.free_ranges, index)
		}
		allocator.resident_bytes += size
		return {offset = offset, size = size}
	}
	offset := wgpu_align_arena_offset(allocator.high_water, alignment)
	if offset > allocator.high_water {
		append(
			&allocator.free_ranges,
			WGPU_Arena_Range{offset = allocator.high_water, size = offset - allocator.high_water},
		)
		wgpu_coalesce_arena_free_ranges(allocator)
	}
	allocator.high_water = offset + size
	allocator.resident_bytes += size
	return {offset = offset, size = size}
}

wgpu_arena_release :: proc(allocator: ^WGPU_Arena_Allocator, allocation: WGPU_Arena_Range) {
	if allocator == nil || allocation.size == 0 {
		return
	}
	append(&allocator.free_ranges, allocation)
	allocator.resident_bytes -= min(allocator.resident_bytes, allocation.size)
	wgpu_sort_arena_free_ranges(allocator)
	wgpu_coalesce_arena_free_ranges(allocator)
}

wgpu_sort_arena_free_ranges :: proc(allocator: ^WGPU_Arena_Allocator) {
	if allocator == nil {
		return
	}
	for index in 1 ..< len(allocator.free_ranges) {
		cursor := index
		for cursor > 0 &&
		    allocator.free_ranges[cursor].offset < allocator.free_ranges[cursor - 1].offset {
			allocator.free_ranges[cursor], allocator.free_ranges[cursor - 1] =
				allocator.free_ranges[cursor - 1], allocator.free_ranges[cursor]
			cursor -= 1
		}
	}
}

wgpu_coalesce_arena_free_ranges :: proc(allocator: ^WGPU_Arena_Allocator) {
	if allocator == nil {
		return
	}
	index := 0
	for index + 1 < len(allocator.free_ranges) {
		current := &allocator.free_ranges[index]
		next := allocator.free_ranges[index + 1]
		current_end := current.offset + current.size
		if current_end < next.offset {
			index += 1
			continue
		}
		current.size = max(current_end, next.offset + next.size) - current.offset
		ordered_remove(&allocator.free_ranges, index + 1)
	}
}

wgpu_destroy_geometry_arena :: proc(arena: ^WGPU_Geometry_Arena) {
	if arena == nil {
		return
	}
	if arena.buffer != nil {
		wgpu.BufferRelease(arena.buffer)
	}
	delete(arena.retirements)
	delete(arena.allocator.free_ranges)
	arena^ = {}
}

wgpu_geometry_arena_ensure_capacity :: proc(
	renderer: ^WGPU_Renderer,
	arena: ^WGPU_Geometry_Arena,
	required: u64,
) -> string {
	if renderer == nil || arena == nil {
		return "geometry arena is not available"
	}
	if arena.buffer != nil && required <= arena.capacity {
		return ""
	}
	capacity := max(arena.capacity, arena.initial_size)
	capacity = max(capacity, u64(4))
	for capacity < required {
		capacity *= 2
	}
	buffer := wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = arena.label,
			usage = arena.usage | {.CopySrc, .CopyDst},
			size = capacity,
		},
	)
	if buffer == nil {
		return fmt.tprintf("failed to grow %s to %d bytes", arena.label, capacity)
	}
	if arena.buffer != nil && arena.capacity > 0 {
		encoder := wgpu.DeviceCreateCommandEncoder(
			renderer.device,
			&wgpu.CommandEncoderDescriptor{label = "Scrapbot Geometry Arena Growth Encoder"},
		)
		if encoder == nil {
			wgpu.BufferRelease(buffer)
			return "failed to create geometry arena growth encoder"
		}
		copy_bytes := min(arena.capacity, capacity)
		wgpu.CommandEncoderCopyBufferToBuffer(encoder, arena.buffer, 0, buffer, 0, copy_bytes)
		command_buffer := wgpu.CommandEncoderFinish(
			encoder,
			&wgpu.CommandBufferDescriptor{label = "Scrapbot Geometry Arena Growth Commands"},
		)
		wgpu.CommandEncoderRelease(encoder)
		if command_buffer == nil {
			wgpu.BufferRelease(buffer)
			return "failed to finish geometry arena growth commands"
		}
		wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
		wgpu.CommandBufferRelease(command_buffer)
		wgpu.BufferRelease(arena.buffer)
		arena.growth_count += 1
	}
	arena.buffer = buffer
	arena.capacity = capacity
	return ""
}

wgpu_geometry_arena_upload :: proc(
	renderer: ^WGPU_Renderer,
	arena: ^WGPU_Geometry_Arena,
	allocation: WGPU_Arena_Range,
	data: rawptr,
	byte_count: u64,
) -> string {
	if byte_count == 0 || allocation.size < byte_count || data == nil {
		return "geometry arena upload range is invalid"
	}
	if err := wgpu_geometry_arena_ensure_capacity(
		renderer,
		arena,
		allocation.offset + allocation.size,
	); err != "" {
		return err
	}
	wgpu.QueueWriteBuffer(renderer.queue, arena.buffer, allocation.offset, data, uint(byte_count))
	arena.upload_count += 1
	arena.upload_bytes += byte_count
	return ""
}

wgpu_publish_geometry_arena_stats :: proc(
	renderer: ^WGPU_Renderer,
	stats: ^Render_Stats,
	batches: []WGPU_Draw_Batch,
) {
	if renderer == nil || stats == nil {
		return
	}
	stats.draw_submissions = wgpu_draw_submission_count(renderer, batches)
	stats.geometry_vertex_arena_capacity_bytes = renderer.geometry_vertex_arena.capacity
	stats.geometry_vertex_arena_resident_bytes =
		renderer.geometry_vertex_arena.allocator.resident_bytes
	stats.geometry_index_arena_capacity_bytes = renderer.geometry_index_arena.capacity
	stats.geometry_index_arena_resident_bytes =
		renderer.geometry_index_arena.allocator.resident_bytes
	stats.geometry_arena_uploads =
		renderer.geometry_vertex_arena.upload_count + renderer.geometry_index_arena.upload_count
	stats.geometry_arena_upload_bytes =
		renderer.geometry_vertex_arena.upload_bytes + renderer.geometry_index_arena.upload_bytes
	stats.geometry_arena_growths =
		renderer.geometry_vertex_arena.growth_count + renderer.geometry_index_arena.growth_count
}
