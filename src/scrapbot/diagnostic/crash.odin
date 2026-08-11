package diagnostic

import "base:runtime"

crash_reporting_ready: bool

@(no_instrumentation)
init_crash_reporting :: proc() {
	init_native_stack_trace()
	context.assertion_failure_proc = crash_assertion_failure
	start_software_stack_trace()
	crash_reporting_ready = true
}

@(no_instrumentation)
destroy_crash_reporting :: proc() {
	crash_reporting_ready = false
	stop_software_stack_trace()
	destroy_native_stack_trace()
}

@(optimization_mode = "none", no_instrumentation)
crash_assertion_failure :: proc(prefix, message: string, loc := #caller_location) -> ! {
	print_fatal_report(prefix, message, loc)
	runtime.trap()
}

fatal_engine_error :: proc(message: string, loc := #caller_location) {
	print_fatal_report("fatal engine invariant", message, loc)
	runtime.trap()
}

engine_task_failure :: proc(message: string, loc := #caller_location) -> string {
	if crash_reporting_ready {
		print_failure_report("engine task failure", message, loc)
	}
	return message
}

@(optimization_mode = "none", no_instrumentation)
print_fatal_report :: proc(prefix, message: string, loc: runtime.Source_Code_Location) {
	print_failure_report(prefix, message, loc)
}

@(optimization_mode = "none", no_instrumentation)
print_failure_report :: proc(prefix, message: string, loc: runtime.Source_Code_Location) {
	runtime.print_caller_location(loc)
	runtime.print_string(" ")
	runtime.print_string(prefix)
	if len(message) > 0 {
		runtime.print_string(": ")
		runtime.print_string(message)
	}
	runtime.print_byte('\n')

	print_software_stack_trace()
	print_native_stack_trace()
}
