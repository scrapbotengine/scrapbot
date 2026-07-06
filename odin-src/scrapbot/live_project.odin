package main

import "core:os"
import "core:strings"
import "core:time"

Source_File_Stamp :: struct {
	size:                i64,
	modification_time_ns: i64,
}

Live_Source_File :: struct {
	path:  string,
	stamp: Source_File_Stamp,
}

Live_Reload_Info :: struct {
	project_reloaded: bool,
	scene_reloaded:   bool,
	scripts_reloaded: bool,
	native_reloaded:  bool,
	entity_count:     int,
	system_count:     int,
}

Live_Reload_Result :: struct {
	changed: bool,
	info:    Live_Reload_Info,
}

Live_Reload_Event :: struct {
	frame: int,
	info:  Live_Reload_Info,
}

Live_Project_Run_Report :: struct {
	reloads: [dynamic]Live_Reload_Event,
}

Live_Project_Frame_Hook :: proc(project: ^Live_Project, completed_frames: int, user_data: rawptr) -> bool

Live_Project :: struct {
	check:                 Project_Check_Result,
	script_sources:        []Live_Source_File,
	project_stamp:         Source_File_Stamp,
	scene_stamp:           Source_File_Stamp,
	native_stamp:          Source_File_Stamp,
	has_native_stamp:      bool,
	last_failed_project:   Source_File_Stamp,
	has_last_failed_project: bool,
	last_failed_scene:     Source_File_Stamp,
	has_last_failed_scene: bool,
	last_failed_script_index: int,
	last_failed_script_stamp: Source_File_Stamp,
	has_last_failed_script:   bool,
	last_failed_native:    Source_File_Stamp,
	has_last_failed_native: bool,
	last_diagnostic:       Script_Diagnostic,
	startup_ran:           bool,
}

live_project_init :: proc(root_path: string) -> (Live_Project, Project_Error) {
	check := check_project(root_path)
	if check.err != .None {
		return Live_Project{check = check}, check.err
	}
	project_stamp, project_stamp_ok := live_project_stat_project(check.project)
	if !project_stamp_ok {
		free_check_result(check)
		return Live_Project{}, .Missing_Project_File
	}
	scene_stamp, scene_stamp_ok := live_project_stat_scene(check.project)
	if !scene_stamp_ok {
		free_check_result(check)
		return Live_Project{}, .Missing_Default_Scene
	}
	script_sources, scripts_ok := live_project_stat_scripts(check.project)
	if !scripts_ok {
		free_check_result(check)
		return Live_Project{}, .Missing_Script
	}
	stamp, has_stamp, stamp_ok := live_project_stat_native(check.project)
	if !stamp_ok {
		live_source_files_free(script_sources)
		free_check_result(check)
		return Live_Project{}, .Missing_Native
	}
	return Live_Project{
		check = check,
		script_sources = script_sources,
		project_stamp = project_stamp,
		scene_stamp = scene_stamp,
		native_stamp = stamp,
		has_native_stamp = has_stamp,
	}, .None
}

live_project_free :: proc(project: ^Live_Project) {
	free_check_result(project.check)
	live_source_files_free(project.script_sources)
	script_diagnostic_free(&project.last_diagnostic)
	project^ = Live_Project{}
}

live_project_poll_project_source :: proc(project: ^Live_Project) -> (Live_Reload_Result, Project_Error) {
	next_stamp, stamp_ok := live_project_stat_project(project.check.project)
	if !stamp_ok {
		return Live_Reload_Result{}, .Missing_Project_File
	}
	if source_file_stamp_equal(next_stamp, project.project_stamp) {
		return Live_Reload_Result{}, .None
	}
	if project.has_last_failed_project && source_file_stamp_equal(next_stamp, project.last_failed_project) {
		return Live_Reload_Result{}, .None
	}

	next_check := check_project(project.check.project.root_path)
	if next_check.err != .None {
		live_project_store_failed_diagnostic(project, &next_check)
		project.last_failed_project = next_stamp
		project.has_last_failed_project = true
		free_check_result(next_check)
		return Live_Reload_Result{}, next_check.err
	}

	next_project_stamp, project_stamp_ok := live_project_stat_project(next_check.project)
	if !project_stamp_ok {
		free_check_result(next_check)
		return Live_Reload_Result{}, .Missing_Project_File
	}
	next_scene_stamp, scene_stamp_ok := live_project_stat_scene(next_check.project)
	if !scene_stamp_ok {
		free_check_result(next_check)
		return Live_Reload_Result{}, .Missing_Default_Scene
	}
	next_script_sources, scripts_ok := live_project_stat_scripts(next_check.project)
	if !scripts_ok {
		free_check_result(next_check)
		return Live_Reload_Result{}, .Missing_Script
	}
	next_native_stamp, has_native_stamp, native_stamp_ok := live_project_stat_native(next_check.project)
	if !native_stamp_ok {
		live_source_files_free(next_script_sources)
		free_check_result(next_check)
		return Live_Reload_Result{}, .Missing_Native
	}

	live_project_clear_diagnostic(project)
	live_source_files_free(project.script_sources)
	old_check := project.check
	project.check = next_check
	project.script_sources = next_script_sources
	project.project_stamp = next_project_stamp
	project.scene_stamp = next_scene_stamp
	project.native_stamp = next_native_stamp
	project.has_native_stamp = has_native_stamp
	project.has_last_failed_project = false
	project.has_last_failed_scene = false
	project.has_last_failed_script = false
	project.has_last_failed_native = false
	project.startup_ran = false
	free_check_result(old_check)
	return Live_Reload_Result{
		changed = true,
		info = Live_Reload_Info{
			project_reloaded = true,
			scene_reloaded = true,
			scripts_reloaded = true,
			native_reloaded = has_native_stamp,
			entity_count = runtime_world_entity_count(project.check.scene.world),
			system_count = runtime_system_schedule_system_count(project.check.update_schedule),
		},
	}, .None
}

live_project_poll_scene_source :: proc(project: ^Live_Project) -> (Live_Reload_Result, Project_Error) {
	next_stamp, stamp_ok := live_project_stat_scene(project.check.project)
	if !stamp_ok {
		return Live_Reload_Result{}, .Missing_Default_Scene
	}
	if source_file_stamp_equal(next_stamp, project.scene_stamp) {
		return Live_Reload_Result{}, .None
	}
	if project.has_last_failed_scene && source_file_stamp_equal(next_stamp, project.last_failed_scene) {
		return Live_Reload_Result{}, .None
	}

	live_project_clear_diagnostic(project)
	scene_path := project_relative_path(project.check.project.root_path, project.check.project.default_scene)
	defer delete(scene_path)
	next_scene, scene_err := load_scene_file(scene_path, project.check.registry)
	if scene_err != .None {
		free_scene(next_scene)
		project.last_failed_scene = next_stamp
		project.has_last_failed_scene = true
		return Live_Reload_Result{}, scene_err
	}

	old_scene := project.check.scene
	project.check.scene = next_scene
	free_scene(old_scene)
	project.scene_stamp = next_stamp
	project.has_last_failed_scene = false
	project.startup_ran = false
	return Live_Reload_Result{
		changed = true,
		info = Live_Reload_Info{
			scene_reloaded = true,
			scripts_reloaded = false,
			native_reloaded = false,
			entity_count = runtime_world_entity_count(project.check.scene.world),
			system_count = runtime_system_schedule_system_count(project.check.update_schedule),
		},
	}, .None
}

live_project_poll_script_sources :: proc(project: ^Live_Project) -> (Live_Reload_Result, Project_Error) {
	for source, index in project.script_sources {
		next_stamp, stamp_ok := live_project_stat_project_source(project.check.project, source.path)
		if !stamp_ok {
			return Live_Reload_Result{}, .Missing_Script
		}
		if source_file_stamp_equal(next_stamp, source.stamp) {
			continue
		}
		if project.has_last_failed_script &&
			project.last_failed_script_index == index &&
			source_file_stamp_equal(next_stamp, project.last_failed_script_stamp) {
			return Live_Reload_Result{}, .None
		}

		next_check := check_project(project.check.project.root_path)
		if next_check.err != .None {
			live_project_store_failed_diagnostic(project, &next_check)
			project.last_failed_script_index = index
			project.last_failed_script_stamp = next_stamp
			project.has_last_failed_script = true
			free_check_result(next_check)
			return Live_Reload_Result{}, next_check.err
		}

		next_script_sources, scripts_ok := live_project_stat_scripts(next_check.project)
		if !scripts_ok {
			free_check_result(next_check)
			return Live_Reload_Result{}, .Missing_Script
		}
		next_native_stamp, has_native_stamp, native_stamp_ok := live_project_stat_native(next_check.project)
		if !native_stamp_ok {
			live_source_files_free(next_script_sources)
			free_check_result(next_check)
			return Live_Reload_Result{}, .Missing_Native
		}

		live_project_clear_diagnostic(project)
		live_source_files_free(project.script_sources)
		live_project_swap_check_preserving_scene(project, next_check)
		project.script_sources = next_script_sources
		project.native_stamp = next_native_stamp
		project.has_native_stamp = has_native_stamp
		project.has_last_failed_scene = false
		project.has_last_failed_script = false
		project.has_last_failed_native = false
		return Live_Reload_Result{
			changed = true,
			info = Live_Reload_Info{
				scripts_reloaded = true,
				native_reloaded = false,
				entity_count = runtime_world_entity_count(project.check.scene.world),
				system_count = runtime_system_schedule_system_count(project.check.update_schedule),
			},
		}, .None
	}

	return Live_Reload_Result{}, .None
}

live_project_poll_native_source :: proc(project: ^Live_Project) -> (Live_Reload_Result, Project_Error) {
	if !project.has_native_stamp || project.check.project.native == "" {
		return Live_Reload_Result{}, .None
	}

	next_stamp, has_stamp, stamp_ok := live_project_stat_native(project.check.project)
	if !stamp_ok || !has_stamp {
		return Live_Reload_Result{}, .Missing_Native
	}
	if source_file_stamp_equal(next_stamp, project.native_stamp) {
		return Live_Reload_Result{}, .None
	}
	if project.has_last_failed_native && source_file_stamp_equal(next_stamp, project.last_failed_native) {
		return Live_Reload_Result{}, .None
	}

	next_check := check_project(project.check.project.root_path)
	if next_check.err != .None {
		live_project_store_failed_diagnostic(project, &next_check)
		project.last_failed_native = next_stamp
		project.has_last_failed_native = true
		free_check_result(next_check)
		return Live_Reload_Result{}, next_check.err
	}

	live_project_clear_diagnostic(project)
	live_project_swap_check_preserving_scene(project, next_check)
	project.native_stamp = next_stamp
	project.has_native_stamp = true
	project.has_last_failed_scene = false
	project.has_last_failed_native = false
	return Live_Reload_Result{
		changed = true,
		info = Live_Reload_Info{
			scripts_reloaded = true,
			native_reloaded = true,
			entity_count = runtime_world_entity_count(project.check.scene.world),
			system_count = runtime_system_schedule_system_count(project.check.update_schedule),
		},
	}, .None
}

live_project_update :: proc(project: ^Live_Project, frames: int, delta_seconds: f32) -> Simulation_Run_Result {
	return run_script_simulation(&project.check, frames, delta_seconds)
}

live_project_run_frames :: proc(project: ^Live_Project, frames: int, delta_seconds: f32) -> Simulation_Run_Result {
	return live_project_run_frames_with_hook(project, frames, delta_seconds, nil, nil)
}

live_project_run_report_free :: proc(report: ^Live_Project_Run_Report) {
	if report.reloads != nil {
		delete(report.reloads)
	}
	report^ = Live_Project_Run_Report{}
}

live_project_run_frames_with_hook :: proc(
	project: ^Live_Project,
	frames: int,
	delta_seconds: f32,
	frame_hook: Live_Project_Frame_Hook,
	hook_data: rawptr,
) -> Simulation_Run_Result {
	return live_project_run_frames_with_report(project, frames, delta_seconds, frame_hook, hook_data, nil)
}

live_project_run_frames_with_report :: proc(
	project: ^Live_Project,
	frames: int,
	delta_seconds: f32,
	frame_hook: Live_Project_Frame_Hook,
	hook_data: rawptr,
	report: ^Live_Project_Run_Report,
) -> Simulation_Run_Result {
	startup_result := live_project_run_startup_if_needed(project)
	if !startup_result.ok {
		return startup_result
	}

	completed_frames := 0
	for completed_frames < frames {
		if frame_hook != nil && !frame_hook(project, completed_frames, hook_data) {
			return Simulation_Run_Result{
				ok = false,
				completed_frames = completed_frames,
				diagnostic = script_runtime_diagnostic("", "", 0, "live project frame hook failed"),
			}
		}

		frame := live_project_run_frame_with_report(project, delta_seconds, completed_frames, report)
		if !frame.ok {
			return frame
		}
		completed_frames = frame.completed_frames
	}

	return Simulation_Run_Result{ok = true, completed_frames = completed_frames}
}

live_project_run_frame_with_report :: proc(project: ^Live_Project, delta_seconds: f32, completed_frames: int, report: ^Live_Project_Run_Report) -> Simulation_Run_Result {
	startup_result := live_project_run_startup_if_needed(project)
	if !startup_result.ok {
		startup_result.completed_frames = completed_frames
		return startup_result
	}

	reload, reload_err := live_project_poll_project_source(project)
	if reload_err != .None {
		return live_project_reload_error_result(project, reload_err, completed_frames)
	}
	live_project_record_reload(report, completed_frames, reload)

	reload, reload_err = live_project_poll_scene_source(project)
	if reload_err != .None {
		return live_project_reload_error_result(project, reload_err, completed_frames)
	}
	live_project_record_reload(report, completed_frames, reload)

	reload, reload_err = live_project_poll_script_sources(project)
	if reload_err != .None {
		return live_project_reload_error_result(project, reload_err, completed_frames)
	}
	live_project_record_reload(report, completed_frames, reload)

	reload, reload_err = live_project_poll_native_source(project)
	if reload_err != .None {
		return live_project_reload_error_result(project, reload_err, completed_frames)
	}
	live_project_record_reload(report, completed_frames, reload)

	startup_result = live_project_run_startup_if_needed(project)
	if !startup_result.ok {
		startup_result.completed_frames = completed_frames
		return startup_result
	}

	update := script_program_run_schedule(&project.check.script_program, &project.check.registry, &project.check.scene.world, project.check.update_schedule, delta_seconds)
	if !update.ok {
		return Simulation_Run_Result{ok = false, completed_frames = completed_frames, diagnostic = update.diagnostic}
	}
	return Simulation_Run_Result{ok = true, completed_frames = completed_frames + 1}
}

live_project_record_reload :: proc(report: ^Live_Project_Run_Report, completed_frames: int, reload: Live_Reload_Result) {
	if report == nil || !reload.changed {
		return
	}
	append(&report.reloads, Live_Reload_Event{frame = completed_frames, info = reload.info})
}

live_project_run_startup_if_needed :: proc(project: ^Live_Project) -> Simulation_Run_Result {
	if project.startup_ran {
		return Simulation_Run_Result{ok = true}
	}
	startup := script_program_run_schedule(&project.check.script_program, &project.check.registry, &project.check.scene.world, project.check.startup_schedule, 0)
	if !startup.ok {
		return Simulation_Run_Result{ok = false, diagnostic = startup.diagnostic}
	}
	project.startup_ran = true
	return Simulation_Run_Result{ok = true}
}

live_project_reload_error_result :: proc(project: ^Live_Project, reload_err: Project_Error, completed_frames: int) -> Simulation_Run_Result {
	diagnostic, diagnostic_found := live_project_last_diagnostic(project)
	if diagnostic_found {
		return Simulation_Run_Result{
			ok = false,
			completed_frames = completed_frames,
			diagnostic = script_diagnostic_clone_value(diagnostic),
		}
	}
	return Simulation_Run_Result{
		ok = false,
		completed_frames = completed_frames,
		diagnostic = script_runtime_diagnostic("", "", 0, project_error_message(reload_err)),
	}
}

live_project_last_diagnostic :: proc(project: ^Live_Project) -> (Script_Diagnostic, bool) {
	return project.last_diagnostic, script_diagnostic_present(project.last_diagnostic)
}

live_project_stat_scripts :: proc(project: Project) -> ([]Live_Source_File, bool) {
	if len(project.scripts) == 0 {
		return nil, true
	}
	sources := make([]Live_Source_File, len(project.scripts))
	if sources == nil {
		return nil, false
	}
	for script_path, index in project.scripts {
		stamp, stamp_ok := live_project_stat_project_source(project, script_path)
		if !stamp_ok {
			live_source_files_free(sources)
			return nil, false
		}
		owned_path, path_err := strings.clone(script_path)
		if path_err != nil {
			live_source_files_free(sources)
			return nil, false
		}
		sources[index] = Live_Source_File{path = owned_path, stamp = stamp}
	}
	return sources, true
}

live_project_stat_native :: proc(project: Project) -> (Source_File_Stamp, bool, bool) {
	if project.native == "" {
		return Source_File_Stamp{}, false, true
	}
	stamp, ok := live_project_stat_project_source(project, project.native)
	return stamp, true, ok
}

live_project_stat_scene :: proc(project: Project) -> (Source_File_Stamp, bool) {
	return live_project_stat_project_source(project, project.default_scene)
}

live_project_stat_project :: proc(project: Project) -> (Source_File_Stamp, bool) {
	return live_project_stat_project_source(project, project.metadata_path)
}

live_project_stat_project_source :: proc(project: Project, resource_path: string) -> (Source_File_Stamp, bool) {
	path := project_relative_path(project.root_path, resource_path)
	defer delete(path)
	stamp, found, ok := source_file_stamp(path)
	return stamp, found && ok
}

source_file_stamp :: proc(path: string) -> (Source_File_Stamp, bool, bool) {
	info, stat_err := os.stat(path, context.allocator)
	if stat_err != nil {
		return Source_File_Stamp{}, false, false
	}
	defer os.file_info_delete(info, context.allocator)
	return Source_File_Stamp{
		size = info.size,
		modification_time_ns = time.to_unix_nanoseconds(info.modification_time),
	}, true, true
}

source_file_stamp_equal :: proc(left, right: Source_File_Stamp) -> bool {
	return left.size == right.size && left.modification_time_ns == right.modification_time_ns
}

live_project_store_failed_diagnostic :: proc(project: ^Live_Project, failed: ^Project_Check_Result) {
	live_project_clear_diagnostic(project)
	project.last_diagnostic = failed.diagnostic
	failed.diagnostic = Script_Diagnostic{}
}

live_project_clear_diagnostic :: proc(project: ^Live_Project) {
	script_diagnostic_free(&project.last_diagnostic)
}

live_source_files_free :: proc(sources: []Live_Source_File) {
	for source in sources {
		if source.path != "" {
			delete(source.path)
		}
	}
	if sources != nil {
		delete(sources)
	}
}

live_project_swap_check_preserving_scene :: proc(project: ^Live_Project, next_check: Project_Check_Result) {
	preserved_scene := project.check.scene
	old_check := project.check
	old_check.scene = Scene{}

	validation_scene := next_check.scene
	next := next_check
	next.scene = preserved_scene

	project.check = next
	free_scene(validation_scene)
	free_check_result(old_check)
}
