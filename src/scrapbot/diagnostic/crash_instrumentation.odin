package diagnostic

import "base:runtime"

SOFTWARE_STACK_TRACE_ENABLED :: #config(SCRAPBOT_SOFTWARE_STACK_TRACE, false)
SOFTWARE_STACK_TRACE_CAPACITY :: 512
software_stack_trace_ready: bool

when SOFTWARE_STACK_TRACE_ENABLED {
	@(thread_local)
	software_stack_locations: [SOFTWARE_STACK_TRACE_CAPACITY]runtime.Source_Code_Location
	@(thread_local)
	software_stack_depth: int

	@(instrumentation_enter, no_instrumentation)
	software_stack_enter :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) #no_bounds_check {
		if !software_stack_trace_ready {
			return
		}
		if software_stack_depth < SOFTWARE_STACK_TRACE_CAPACITY {
			software_stack_locations[software_stack_depth] = loc
		}
		software_stack_depth += 1
	}

	@(instrumentation_exit, no_instrumentation)
	software_stack_exit :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) #no_bounds_check {
		if !software_stack_trace_ready {
			return
		}
		software_stack_depth = max(software_stack_depth - 1, 0)
	}
}

@(no_instrumentation)
start_software_stack_trace :: proc() {
	when SOFTWARE_STACK_TRACE_ENABLED {
		software_stack_trace_ready = true
	}
}

@(no_instrumentation)
stop_software_stack_trace :: proc() {
	when SOFTWARE_STACK_TRACE_ENABLED {
		software_stack_trace_ready = false
	}
}

@(no_instrumentation)
print_software_stack_trace :: proc() {
	when SOFTWARE_STACK_TRACE_ENABLED {
		count := min(software_stack_depth, SOFTWARE_STACK_TRACE_CAPACITY)
		if count <= 0 {
			return
		}
		runtime.print_string("Instrumented Odin stack trace:\n")
		for reverse_index in 0 ..< count {
			index := count - reverse_index - 1
			loc := software_stack_locations[index]
			runtime.print_string("  ")
			runtime.print_int(reverse_index)
			runtime.print_string(": ")
			runtime.print_caller_location(loc)
			if loc.procedure != "" {
				runtime.print_string(" ")
				runtime.print_string(loc.procedure)
			}
			runtime.print_byte('\n')
		}
	}
}
