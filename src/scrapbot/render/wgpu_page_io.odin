package render

import shared "../shared"
import "core:mem"
import "core:os"
import "core:strings"
import "core:thread"

WGPU_Virtual_Page_IO :: struct {
	pool: thread.Pool,
	initialized: bool,
}

WGPU_Virtual_Page_IO_Job :: struct {
	handle: shared.Geometry_Handle,
	geometry_version: u32,
	page_index: u32,
	path: string,
	offset: u64,
	bytes: []u8,
	err: bool,
}

wgpu_virtual_page_io_init :: proc(io: ^WGPU_Virtual_Page_IO) {
	if io == nil || io.initialized {
		return
	}
	thread.pool_init(&io.pool, os.heap_allocator(), 1)
	thread.pool_start(&io.pool)
	io.initialized = true
}

wgpu_virtual_page_io_schedule :: proc(
	io: ^WGPU_Virtual_Page_IO,
	handle: shared.Geometry_Handle,
	geometry_version, page_index: u32,
	path: string,
	offset, size: u64,
) -> bool {
	if io == nil || path == "" || size == 0 || size > u64(max(int)) {
		return false
	}
	wgpu_virtual_page_io_init(io)
	job := new(WGPU_Virtual_Page_IO_Job, os.heap_allocator())
	job.handle = handle
	job.geometry_version = geometry_version
	job.page_index = page_index
	job.offset = offset
	job.path, _ = strings.clone(path, os.heap_allocator())
	job.bytes = make([]u8, int(size), os.heap_allocator())
	if job.path == "" {
		wgpu_virtual_page_io_destroy_job(job)
		return false
	}
	thread.pool_add_task(&io.pool, os.heap_allocator(), wgpu_virtual_page_io_read, job)
	return true
}

wgpu_virtual_page_io_read :: proc(task: thread.Task) {
	job := cast(^WGPU_Virtual_Page_IO_Job)task.data
	file, open_err := os.open(job.path)
	if open_err != nil {
		job.err = true
		return
	}
	defer os.close(file)
	read_count, read_err := os.read_at(file, job.bytes, i64(job.offset))
	job.err = read_err != nil || read_count != len(job.bytes)
}

wgpu_virtual_page_io_pop :: proc(io: ^WGPU_Virtual_Page_IO) -> (^WGPU_Virtual_Page_IO_Job, bool) {
	if io == nil || !io.initialized {
		return nil, false
	}
	task, ok := thread.pool_pop_done(&io.pool)
	if !ok {
		return nil, false
	}
	return cast(^WGPU_Virtual_Page_IO_Job)task.data, true
}

wgpu_virtual_page_io_destroy_job :: proc(job: ^WGPU_Virtual_Page_IO_Job) {
	if job == nil {
		return
	}
	delete(job.path, os.heap_allocator())
	delete(job.bytes, os.heap_allocator())
	free(job, os.heap_allocator())
}

wgpu_virtual_page_io_destroy :: proc(io: ^WGPU_Virtual_Page_IO) {
	if io == nil || !io.initialized {
		return
	}
	thread.pool_join(&io.pool)
	for {
		task, ok := thread.pool_pop_waiting(&io.pool)
		if !ok {
			break
		}
		wgpu_virtual_page_io_destroy_job(cast(^WGPU_Virtual_Page_IO_Job)task.data)
	}
	for {
		job, ok := wgpu_virtual_page_io_pop(io)
		if !ok {
			break
		}
		wgpu_virtual_page_io_destroy_job(job)
	}
	thread.pool_destroy(&io.pool)
	io^ = {}
}
