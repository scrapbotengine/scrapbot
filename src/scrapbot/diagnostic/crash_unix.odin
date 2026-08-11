#+build linux, darwin

package diagnostic

import "base:runtime"
import "core:c"

foreign import libc "system:c"

foreign libc {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size, fd: c.int) ---
}

@(no_instrumentation)
init_native_stack_trace :: proc() {  }

@(no_instrumentation)
destroy_native_stack_trace :: proc() {  }

@(optimization_mode = "none", no_instrumentation)
print_native_stack_trace :: proc() {
	frames: [64]rawptr
	count := backtrace(raw_data(frames[:]), c.int(len(frames)))
	if count <= 0 {
		return
	}
	runtime.print_string("Native stack trace:\n")
	backtrace_symbols_fd(raw_data(frames[:]), count, 2)
}
