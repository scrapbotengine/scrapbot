package main

import "core:strings"

Script_Diagnostic_Stage :: enum {
	None,
	Load,
	Native_Build,
	Native_Load,
	Native_Registration,
	Registration,
	Schedule,
	Runtime,
}

Script_Diagnostic_Position :: struct {
	line:       int,
	column:     int,
	has_column: bool,
}

Script_Diagnostic :: struct {
	stage:     Script_Diagnostic_Stage,
	path:      string,
	path_owned: bool,
	system_id: string,
	system_id_owned: bool,
	start:     Script_Diagnostic_Position,
	has_start: bool,
	message:   string,
}

script_diagnostic_present :: proc(diagnostic: Script_Diagnostic) -> bool {
	return diagnostic.stage != .None && diagnostic.message != ""
}

script_diagnostic_free :: proc(diagnostic: ^Script_Diagnostic) {
	if diagnostic.path_owned && diagnostic.path != "" {
		delete(diagnostic.path)
	}
	if diagnostic.system_id_owned && diagnostic.system_id != "" {
		delete(diagnostic.system_id)
	}
	diagnostic^ = Script_Diagnostic{}
}

script_diagnostic_stage_name :: proc(stage: Script_Diagnostic_Stage) -> string {
	switch stage {
	case .Load:
		return "load"
	case .Native_Build:
		return "native_build"
	case .Native_Load:
		return "native_load"
	case .Native_Registration:
		return "native_registration"
	case .Registration:
		return "registration"
	case .Schedule:
		return "schedule"
	case .Runtime:
		return "runtime"
	case .None:
		return "none"
	}
	return "none"
}

script_diagnostic_stage_label :: proc(stage: Script_Diagnostic_Stage) -> string {
	switch stage {
	case .Load:
		return "script load"
	case .Native_Build:
		return "native build"
	case .Native_Load:
		return "native load"
	case .Native_Registration:
		return "native registration"
	case .Registration:
		return "script registration"
	case .Schedule:
		return "script schedule"
	case .Runtime:
		return "script runtime"
	case .None:
		return "script"
	}
	return "script"
}

script_diagnostic_line_from_offset :: proc(contents: string, absolute_offset: int) -> int {
	line := 1
	limit := absolute_offset
	if limit < 0 {
		limit = 0
	}
	if limit > len(contents) {
		limit = len(contents)
	}
	for index := 0; index < limit; index += 1 {
		if contents[index] == '\n' {
			line += 1
		}
	}
	return line
}

script_registration_diagnostic :: proc(path, contents: string, absolute_offset: int, message: string) -> Script_Diagnostic {
	owned_path, path_owned := script_diagnostic_clone(path)
	return Script_Diagnostic{
		stage = .Registration,
		path = owned_path,
		path_owned = path_owned,
		start = Script_Diagnostic_Position{line = script_diagnostic_line_from_offset(contents, absolute_offset)},
		has_start = true,
		message = message,
	}
}

script_system_registration_diagnostic :: proc(path, contents: string, absolute_offset: int, system_id: string, message: string) -> Script_Diagnostic {
	diagnostic := script_registration_diagnostic(path, contents, absolute_offset, message)
	diagnostic.system_id, diagnostic.system_id_owned = script_diagnostic_clone(system_id)
	return diagnostic
}

script_schedule_diagnostic :: proc(phase: Runtime_System_Phase, message: string) -> Script_Diagnostic {
	return Script_Diagnostic{
		stage = .Schedule,
		message = script_schedule_message(phase, message),
	}
}

script_schedule_message :: proc(phase: Runtime_System_Phase, message: string) -> string {
	if message != "failed to build script schedule" {
		return message
	}
	switch phase {
	case .Startup:
		return "failed to build script schedule: startup"
	case .Update:
		return "failed to build script schedule: update"
	case .Fixed_Update:
		return "failed to build script schedule: fixed_update"
	case .Render:
		return "failed to build script schedule: render"
	}
	return message
}

script_diagnostic_clone :: proc(value: string) -> (string, bool) {
	if value == "" {
		return "", false
	}
	owned, err := strings.clone(value)
	if err != nil {
		return "", false
	}
	return owned, true
}
