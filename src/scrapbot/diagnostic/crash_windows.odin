#+build windows

package diagnostic

import "base:runtime"
import trace "core:debug/trace"

native_trace_context: trace.Context
native_trace_initialized: bool

@(no_instrumentation)
init_native_stack_trace :: proc() {
	native_trace_initialized = trace.init(&native_trace_context)
}

@(no_instrumentation)
destroy_native_stack_trace :: proc() {
	if native_trace_initialized {
		_ = trace.destroy(&native_trace_context)
		native_trace_initialized = false
	}
}

@(no_instrumentation)
print_native_stack_trace :: proc() {
	if !native_trace_initialized || trace.in_resolve(&native_trace_context) {
		return
	}
	frames_buffer: [64]trace.Frame
	frames := trace.frames(&native_trace_context, 1, frames_buffer[:])
	if len(frames) > 0 {
		runtime.print_string("Native stack trace:\n")
	}
	for frame in frames {
		frame_location := trace.resolve(&native_trace_context, frame, context.temp_allocator)
		if frame_location.loc.file_path == "" && frame_location.loc.procedure == "" {
			continue
		}
		runtime.print_string("  ")
		runtime.print_caller_location(frame_location.loc)
		if frame_location.loc.procedure != "" {
			runtime.print_string(" ")
			runtime.print_string(frame_location.loc.procedure)
		}
		runtime.print_byte('\n')
	}
}
