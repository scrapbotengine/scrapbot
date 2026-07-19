package scrapbot

import component "./component"
import ecs "./ecs"
import native "./native"
import project "./project"
import render "./render"
import resources "./resources"
import schedule "./schedule"
import script "./script"
import shared "./shared"
import ui "./ui"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

VERSION :: shared.VERSION

PROJECT_FILE :: shared.PROJECT_FILE
DEFAULT_SCENE :: shared.DEFAULT_SCENE
DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_LUAU_TYPES :: shared.DEFAULT_LUAU_TYPES

Renderer_Backend :: shared.Renderer_Backend
Run_Config :: render.Run_Config
Framegrab_Region :: render.Framegrab_Region
Runtime_Stats :: render.Runtime_Stats
Render_Stats :: render.Render_Stats
World_Storage_Stats :: ecs.World_Storage_Stats
parse_framegrab_region :: render.parse_framegrab_region
Project_Load_Result :: project.Project_Load_Result
Runtime_Result :: struct {
	frame: shared.Render_Frame,
	err: string,
	scheduler_workers: int,
	parallel_stages: int,
	max_parallel_width: int,
	draw_batches: int,
	render_stats: Render_Stats,
	runtime_stats: Runtime_Stats,
}

Frame_Runtime :: struct {
	root: string,
	scene_path: string,
	playback_baseline: Playback_Baseline,
	script_runtime: script.Runtime,
	native_extensions: native.Extension_Set,
	executor: schedule.Executor,
	frame_systems: Frame_System_Cache,
	resources: resources.Registry,
	system_profile: System_Profile_Accumulator,
}

destroy_frame_runtime :: proc(runtime: ^Frame_Runtime) {
	if runtime == nil {
		return
	}
	resources.destroy_registry(&runtime.resources)
	destroy_frame_system_cache(&runtime.frame_systems)
	schedule.destroy_executor(&runtime.executor)
	native.destroy_extension_set(&runtime.native_extensions)
	script.destroy_runtime(&runtime.script_runtime)
	destroy_playback_baseline(&runtime.playback_baseline)
	delete(runtime.scene_path)
	runtime^ = {}
}

SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES :: 5
SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES :: 50

System_Profile_Accumulator :: struct {
	snapshot: shared.System_Profile,
	totals: [shared.MAX_SYSTEM_PROFILE_ENTRIES]i64,
	samples: [shared.MAX_SYSTEM_PROFILE_ENTRIES][SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES]i64,
	pending_durations: [shared.MAX_SYSTEM_PROFILE_ENTRIES]i64,
	sample_cursor: int,
	sample_count: int,
	frames_since_publish: int,
}

ENGINE_SYSTEM_PROFILE_COUNT :: int(render.Engine_System_Profile_Phase.Count)

engine_system_profile_name :: proc(phase: render.Engine_System_Profile_Phase) -> string {
	switch phase {
		case .Editor_Camera:
			return "scrapbot.camera"
		case .Editor_Gizmo:
			return "scrapbot.gizmo"
		case .UI:
			return "scrapbot.ui"
		case .Picking:
			return "scrapbot.pick"
		case .Render_Prepare:
			return "scrapbot.prepare"
		case .Render_Cull:
			return "scrapbot.render.cull"
		case .Render_Shadow:
			return "scrapbot.render.shadow"
		case .Render_World:
			return "scrapbot.render.world"
		case .Render_Post:
			return "scrapbot.render.post"
		case .Render_UI:
			return "scrapbot.render.ui"
		case .Render_Finish:
			return "scrapbot.render.finish"
		case .Render_Submit:
			return "scrapbot.render.submit"
		case .Render_Present:
			return "scrapbot.render.present"
		case .Count:
	}
	return ""
}

Native_Work_Context :: struct {
	system: ^native.Native_System,
	world: ^shared.World,
	commands: ^ecs.Command_Buffer,
	registry: ^component.Registry,
	time: shared.Time_Resource,
	err: string,
	duration_ns: i64,
	system_index: int,
}

Frame_System_Cache :: struct {
	systems: [schedule.MAX_SYSTEMS]schedule.System,
	system_count: int,
	plan: schedule.Plan,
	plan_valid: bool,
	plan_build_count: u64,
	native_commands: [schedule.MAX_SYSTEMS]ecs.Command_Buffer,
	native_command_count: int,
}

destroy_frame_system_cache :: proc(cache: ^Frame_System_Cache) {
	if cache == nil {
		return
	}
	for index in 0 ..< cache.native_command_count {
		ecs.destroy_command_buffer(&cache.native_commands[index])
	}
	cache^ = {}
}

invalidate_frame_system_plan :: proc(cache: ^Frame_System_Cache) {
	if cache == nil {
		return
	}
	cache.system_count = 0
	cache.plan = {}
	cache.plan_valid = false
}

schedule_system_matches :: proc(a, b: schedule.System) -> bool {
	if a.access_count != b.access_count {
		return false
	}
	for index in 0 ..< a.access_count {
		if a.accesses[index] != b.accesses[index] {
			return false
		}
	}
	return true
}

prepare_frame_system_cache :: proc(
	cache: ^Frame_System_Cache,
	systems: []schedule.System,
	native_system_count: int,
) -> ^schedule.Plan {
	if cache == nil {
		return nil
	}
	for index in cache.native_command_count ..< native_system_count {
		ecs.init_command_buffer_capacity(&cache.native_commands[index], 4)
	}
	for index in native_system_count ..< cache.native_command_count {
		ecs.destroy_command_buffer(&cache.native_commands[index])
	}
	cache.native_command_count = native_system_count

	topology_changed := !cache.plan_valid || cache.system_count != len(systems)
	if !topology_changed {
		for system, index in systems {
			if !schedule_system_matches(cache.systems[index], system) {
				topology_changed = true
				break
			}
		}
	}
	if topology_changed {
		cache.system_count = len(systems)
		for system, index in systems {
			cache.systems[index] = system
		}
		cache.plan = schedule.build_plan(cache.systems[:cache.system_count])
		cache.plan_valid = true
		cache.plan_build_count += 1
	}
	return &cache.plan
}

init_project :: project.init_project
load_project :: project.load_project
destroy_project_load_result :: project.destroy_project_load_result

parse_renderer_backend :: render.parse_renderer_backend
renderer_backend_name :: render.renderer_backend_name

build_project :: proc(root: string) -> string {
	loaded := project.load_project_config(root)
	defer project.destroy_project_config_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	if err := project.prepare_project_fonts(root, &loaded.config); err != "" { return err }

	return build_native_extensions(root, &loaded.config)
}

check_project :: proc(root: string) -> string {
	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	if err := project.prepare_project_fonts(root, &loaded.config); err != "" { return err }
	if err := build_native_extensions(root, &loaded.config); err != "" {
		return err
	}

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	registry: component.Registry
	component.init_registry(&registry)
	render_resources: resources.Registry
	defer resources.destroy_registry(&render_resources)
	if err := init_render_resources(
		&render_resources,
		&world,
		root,
		&loaded.config,
		loaded.resources[:],
	); err != "" { return err }
	extensions: native.Extension_Set
	defer native.destroy_extension_set(&extensions)
	if extension_load := native.load_project_extensions(
		&extensions,
		root,
		&registry,
		&render_resources,
	); extension_load.err != "" {
		return extension_load.err
	}

	runtime: script.Runtime
	defer script.destroy_runtime(&runtime)
	script_result := script.run_project_script_with_registry(
		&runtime,
		root,
		&world,
		&registry,
		script.Source_Options{resource_registry = &render_resources},
	)
	if script_result.err != "" {
		return script_result.err
	}

	if script_result.ran {
		if err := project.validate_scene_components(&loaded.scene, &runtime.registry); err != "" {
			return err
		}
		if err := project.write_luau_types(root, &runtime.registry); err != "" {
			return err
		}
		return analyze_project_luau(root)
	}

	if err := project.validate_scene_components(&loaded.scene, &registry); err != "" {
		return err
	}
	if err := project.write_luau_types(root, &registry); err != "" {
		return err
	}
	return analyze_project_luau(root)
}

analyze_project_luau :: proc(root: string) -> string {
	script_path, join_script_err := filepath.join({root, DEFAULT_SCRIPT})
	if join_script_err != nil {
		return "failed to allocate script path"
	}
	defer delete(script_path)
	if !os.exists(script_path) {
		return ""
	}

	types_path, join_types_err := filepath.join({root, DEFAULT_LUAU_TYPES})
	if join_types_err != nil {
		return "failed to allocate Luau types path"
	}
	defer delete(types_path)

	types_bytes, types_read_err := os.read_entire_file(types_path, context.temp_allocator)
	if types_read_err != nil {
		return fmt.tprintf("failed to read %s: %v", types_path, types_read_err)
	}
	script_bytes, script_read_err := os.read_entire_file(script_path, context.temp_allocator)
	if script_read_err != nil {
		return fmt.tprintf("failed to read %s: %v", script_path, script_read_err)
	}

	fixture, fixture_err := luau_analyzer_fixture(string(types_bytes), string(script_bytes))
	if fixture_err != "" {
		return fixture_err
	}
	defer delete(fixture)

	temp_dir, temp_err := os.make_directory_temp(
		"",
		"scrapbot-luau-analyze-*",
		context.temp_allocator,
	)
	if temp_err != nil {
		return fmt.tprintf("failed to create Luau analyzer temp directory: %v", temp_err)
	}
	defer os.remove_all(temp_dir)

	fixture_path, join_fixture_err := filepath.join({temp_dir, "main.analyze.luau"})
	if join_fixture_err != nil {
		return "failed to allocate Luau analyzer fixture path"
	}
	defer delete(fixture_path)

	if err := os.write_entire_file(fixture_path, fixture); err != nil {
		return fmt.tprintf("failed to write Luau analyzer fixture: %v", err)
	}

	command := []string{"luau-analyze", "--formatter=plain", "--mode=strict", fixture_path}
	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	if len(stdout) > 0 {
		defer delete(stdout)
	}
	if len(stderr) > 0 {
		defer delete(stderr)
	}
	if exec_err != nil {
		return ""
	}
	output := strings.trim_space(string(stderr))
	if output == "" {
		output = strings.trim_space(string(stdout))
	}
	if state.success && output == "" {
		return ""
	}
	if output == "" {
		return fmt.tprintf("Luau analyzer failed with exit code %d", state.exit_code)
	}
	if !luau_analyzer_output_has_errors(output) {
		return ""
	}
	return fmt.tprintf("Luau analyzer failed:\n%s", output)
}

luau_analyzer_output_has_errors :: proc(output: string) -> bool {
	return strings.contains(output, "TypeError:") || strings.contains(output, "SyntaxError:")
}

luau_analyzer_fixture :: proc(types_text, script_text: string) -> (text: string, err: string) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	if strings.has_suffix(types_text, "declare scrapbot: Scrapbot\n") {
		strings.write_string(
			&builder,
			strings.trim_suffix(types_text, "declare scrapbot: Scrapbot\n"),
		)
		strings.write_string(&builder, "local scrapbot: Scrapbot = nil :: any\n")
	} else if strings.has_suffix(types_text, "declare scrapbot: Scrapbot") {
		strings.write_string(
			&builder,
			strings.trim_suffix(types_text, "declare scrapbot: Scrapbot"),
		)
		strings.write_string(&builder, "local scrapbot: Scrapbot = nil :: any\n")
	} else {
		strings.write_string(&builder, types_text)
	}
	fixture_types := strings.to_string(builder)
	if !strings.has_suffix(fixture_types, "\n") {
		strings.write_string(&builder, "\n")
	}
	strings.write_string(&builder, "\n")

	script_body := strip_luau_mode_directive(script_text)
	strings.write_string(&builder, script_body)
	if !strings.has_suffix(script_body, "\n") {
		strings.write_string(&builder, "\n")
	}

	cloned, clone_err := strings.clone(strings.to_string(builder))
	if clone_err != nil {
		return "", "failed to allocate Luau analyzer fixture"
	}
	return cloned, ""
}

strip_luau_mode_directive :: proc(script_text: string) -> string {
	if strings.has_prefix(script_text, "--!strict\n") {
		return strings.trim_prefix(script_text, "--!strict\n")
	}
	if strings.has_prefix(script_text, "--!nonstrict\n") {
		return strings.trim_prefix(script_text, "--!nonstrict\n")
	}
	if strings.has_prefix(script_text, "--!nocheck\n") {
		return strings.trim_prefix(script_text, "--!nocheck\n")
	}
	return script_text
}

luau_analyzer_available :: proc() -> bool {
	command := []string{"luau-analyze", "--help"}
	_, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	if len(stdout) > 0 {
		defer delete(stdout)
	}
	if len(stderr) > 0 {
		defer delete(stderr)
	}
	return exec_err == nil
}

run_headless :: proc(root: string) -> Runtime_Result {
	return run_project(root, Run_Config{backend = .Null})
}

run_project :: proc(root: string, config: Run_Config) -> Runtime_Result {
	return run_project_internal(root, config, false)
}

run_packaged_project :: proc(root: string, config: Run_Config) -> Runtime_Result {
	return run_project_internal(root, config, true)
}

run_project_internal :: proc(
	root: string,
	config: Run_Config,
	extensions_prebuilt: bool,
) -> Runtime_Result {
	if config.collect_runtime_stats {
		backing_allocator := context.allocator
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, backing_allocator, backing_allocator)
		tracked_config := config
		stats: Runtime_Stats
		tracked_config.runtime_stats = &stats
		tracked_config.allocator_current_bytes = &tracker.current_memory_allocated
		tracked_config.allocator_peak_bytes = &tracker.peak_memory_allocated
		old_context := context
		context.allocator = mem.tracking_allocator(&tracker)
		result := run_project_internal_untracked(root, tracked_config, extensions_prebuilt)
		context = old_context
		stats.allocator_peak_bytes = tracker.peak_memory_allocated
		stats.allocator_final_bytes = tracker.current_memory_allocated
		result.runtime_stats = stats
		mem.tracking_allocator_destroy(&tracker)
		return result
	}
	return run_project_internal_untracked(root, config, extensions_prebuilt)
}

run_project_internal_untracked :: proc(
	root: string,
	config: Run_Config,
	extensions_prebuilt: bool,
) -> Runtime_Result {
	result: Runtime_Result
	run_config := config
	render_stats: render.Render_Stats
	run_config.stats = &render_stats

	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		result.err = loaded.err
		return result
	}
	run_config.window_width = loaded.config.window.width
	run_config.window_height = loaded.config.window.height
	if err := project.prepare_project_fonts(root, &loaded.config); err != "" {
		result.err = err
		return result
	}
	if !extensions_prebuilt {
		if err := build_native_extensions(root, &loaded.config); err != "" {
			result.err = err
			return result
		}
	}

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)
	ui_state := new(ui.State)
	defer free(ui_state)
	if ui_err := ui.init(ui_state); ui_err != "" { result.err = ui_err; return result }
	ui_state.editor_visible = run_config.editor
	defer ui.destroy(ui_state)
	run_config.ui_state = ui_state

	if run_config.hot_reload {
		hot_reload := new(Hot_Reload_State)
		defer free(hot_reload)
		defer destroy_hot_reload_state(hot_reload)
		if err := init_hot_reload_state(hot_reload, root, &loaded, &world, run_config.log_enabled);
		   err != "" {
			result.err = err
			return result
		}
		ui_state.system_profile = &hot_reload.system_profile.snapshot
		ui_state.component_registry = &hot_reload.runtime.registry

		run_config.frame_system = hot_reload_frame_system
		run_config.frame_system_data = hot_reload
		run_config.system_profile_begin = hot_reload_system_profile_begin
		run_config.system_profile_record = hot_reload_system_profile_record
		run_config.system_profile_commit = hot_reload_system_profile_commit
		run_config.system_profile_data = hot_reload
		run_config.runtime_playback_begin = hot_reload_playback_begin
		run_config.runtime_playback_begin_data = hot_reload
		run_config.runtime_playback_stop = hot_reload_playback_stop
		run_config.runtime_playback_stop_data = hot_reload
		run_config.runtime_save = hot_reload_scene_save
		run_config.runtime_save_data = hot_reload
		run_config.runtime_revert = hot_reload_scene_revert
		run_config.runtime_revert_data = hot_reload
		run_config.resource_registry = &hot_reload.resources
		result.frame, result.err = render.run_renderer(run_config, &world)
		result.scheduler_workers = hot_reload.executor.worker_count
		result.parallel_stages = hot_reload.executor.parallel_stages
		result.max_parallel_width = hot_reload.executor.max_parallel_width
		result.draw_batches = render_stats.draw_batches
		result.render_stats = render_stats
		return result
	}

	registry: component.Registry
	component.init_registry(&registry)
	frame_runtime := new(Frame_Runtime)
	defer free(frame_runtime)
	defer destroy_frame_runtime(frame_runtime)
	scene_path, scene_path_err := filepath.join({root, loaded.config.default_scene})
	if scene_path_err != nil {
		result.err = "failed to allocate scene path"
		return result
	}
	frame_runtime.scene_path = scene_path
	frame_runtime.root = root
	if err := init_render_resources(
		&frame_runtime.resources,
		&world,
		root,
		&loaded.config,
		loaded.resources[:],
	); err != "" { result.err = err; return result }
	if err := capture_playback_baseline(
		&frame_runtime.playback_baseline,
		&world,
		&frame_runtime.resources,
	); err != "" { result.err = err; return result }
	extensions: native.Extension_Set
	defer native.destroy_extension_set(&extensions)
	if extension_load := native.load_project_extensions(
		&extensions,
		root,
		&registry,
		&frame_runtime.resources,
	); extension_load.err != "" {
		result.err = extension_load.err
		return result
	}

	script_result := script.run_project_script_with_registry(
		&frame_runtime.script_runtime,
		root,
		&world,
		&registry,
		script.Source_Options {
			log_enabled = config.log_enabled,
			resource_registry = &frame_runtime.resources,
		},
	)
	if script_result.err != "" {
		result.err = script_result.err
		return result
	}
	if !script_result.ran {
		frame_runtime.script_runtime.registry = registry
		frame_runtime.script_runtime.world = &world
		frame_runtime.script_runtime.resource_registry = &frame_runtime.resources
	}
	frame_runtime.native_extensions = extensions
	extensions = {}
	ui_state.system_profile = &frame_runtime.system_profile.snapshot
	ui_state.component_registry = &frame_runtime.script_runtime.registry
	if script_result.ran || frame_runtime.native_extensions.system_count > 0 {
		run_config.frame_system = step_frame_runtime_system
		run_config.frame_system_data = frame_runtime
	}
	run_config.resource_registry = &frame_runtime.resources
	run_config.system_profile_begin = frame_runtime_system_profile_begin
	run_config.system_profile_record = frame_runtime_system_profile_record
	run_config.system_profile_commit = frame_runtime_system_profile_commit
	run_config.system_profile_data = frame_runtime
	run_config.runtime_playback_begin = frame_runtime_playback_begin
	run_config.runtime_playback_begin_data = frame_runtime
	run_config.runtime_playback_stop = frame_runtime_playback_stop
	run_config.runtime_playback_stop_data = frame_runtime
	run_config.runtime_save = frame_runtime_save
	run_config.runtime_save_data = frame_runtime
	run_config.runtime_revert = frame_runtime_revert
	run_config.runtime_revert_data = frame_runtime

	result.frame, result.err = render.run_renderer(run_config, &world)
	result.scheduler_workers = frame_runtime.executor.worker_count
	result.parallel_stages = frame_runtime.executor.parallel_stages
	result.max_parallel_width = frame_runtime.executor.max_parallel_width
	result.draw_batches = render_stats.draw_batches
	result.render_stats = render_stats
	return result
}

init_render_resources :: proc(
	registry: ^resources.Registry,
	world: ^shared.World,
	root: string = "",
	config: ^shared.Project_Config = nil,
	project_resources: []shared.Project_Resource = nil,
) -> string {
	cube_desc, cube_err := resources.cube(2)
	if cube_err != "" { return cube_err }
	defer delete(cube_desc.vertices); defer delete(cube_desc.indices)
	cube_handle, register_err := resources.register_geometry(registry, "cube", cube_desc)
	if register_err != "" { return register_err }
	material_handle, material_err := resources.register_material(
		registry,
		"default",
		{base_color = {0.3, 0.7, 0.95, 1}},
	)
	if material_err != "" { return material_err }
	if config != nil && len(config.fonts) > 0 {
		if font_err := resources.register_project_fonts(registry, root, config.fonts[:]);
		   font_err != "" {
			return font_err
		}
	}
	if err := resources.register_project_materials(registry, root, project_resources); err != "" {
		return err
	}
	for entity, index in world.entities {
		if entity.mesh_index >= 0 && entity.geometry_resource == "" {
			ecs.add_geometry(world, index, cube_handle)
		}
		if entity.mesh_index >= 0 && entity.material_resource == "" {
			ecs.add_material(world, index, material_handle)
		}
	}
	return ""
}

step_frame_runtime_system :: proc(
	data: rawptr,
	world: ^shared.World,
	delta_seconds: f32,
) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil {
		return ""
	}
	return step_frame_runtime(runtime, world, delta_seconds)
}

frame_runtime_system_profile_begin :: proc(data: rawptr) {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil {
		return
	}
	system_profile_begin_frame(
		&runtime.system_profile,
		&runtime.native_extensions,
		&runtime.script_runtime,
	)
}

frame_runtime_system_profile_record :: proc(
	data: rawptr,
	phase: render.Engine_System_Profile_Phase,
	duration_nanoseconds: i64,
) {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil {
		return
	}
	system_profile_record_engine(&runtime.system_profile, phase, duration_nanoseconds)
}

frame_runtime_system_profile_commit :: proc(data: rawptr) {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil {
		return
	}
	system_profile_commit_pending_frame(&runtime.system_profile)
}

frame_runtime_playback_begin :: proc(data: rawptr, world: ^shared.World) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil || world == nil {
		return "cannot snapshot an unavailable project runtime"
	}
	return capture_playback_baseline(&runtime.playback_baseline, world, &runtime.resources)
}

frame_runtime_playback_stop :: proc(data: rawptr, world: ^shared.World) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil || world == nil {
		return "cannot restore an unavailable project runtime"
	}
	return restore_playback_baseline(
		&runtime.playback_baseline,
		&runtime.script_runtime,
		world,
		&runtime.resources,
	)
}

frame_runtime_save :: proc(
	data: rawptr,
	world: ^shared.World,
	dirty_entities: []shared.Entity_UUID,
	dirty_resources: []shared.Resource_UUID,
) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil || world == nil {
		return "cannot save an unavailable project runtime"
	}
	return save_project_world(
		runtime.root,
		runtime.scene_path,
		&runtime.resources,
		world,
		dirty_entities,
		dirty_resources,
	)
}

frame_runtime_revert :: proc(data: rawptr, world: ^shared.World) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil || world == nil {
		return "cannot revert an unavailable project runtime"
	}
	loaded := project.load_project(runtime.root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	if err := resources.register_project_materials(
		&runtime.resources,
		runtime.root,
		loaded.resources[:],
	); err != "" {
		return err
	}
	return reset_scene_world(runtime.scene_path, &runtime.script_runtime, world)
}

reset_scene_world :: proc(
	scene_path: string,
	script_runtime: ^script.Runtime,
	world: ^shared.World,
) -> string {
	loaded := project.load_scene_file(scene_path)
	defer project.destroy_scene_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	next_world := ecs.build_world(&loaded.scene)
	if err := script.validate_runtime_world(script_runtime, &next_world); err != "" {
		ecs.destroy_world(&next_world)
		return err
	}
	ecs.destroy_world(world)
	world^ = next_world
	script.bind_runtime_world(script_runtime, world)
	return ""
}

step_frame_runtime :: proc(
	runtime: ^Frame_Runtime,
	world: ^shared.World,
	delta_seconds: f32,
) -> string {
	if runtime == nil {
		return ""
	}
	ecs.advance_time(&world.time, delta_seconds)
	return step_frame_runtime_parts(
		&runtime.script_runtime,
		&runtime.native_extensions,
		&runtime.executor,
		&runtime.frame_systems,
		&runtime.system_profile,
		world,
		world.time,
	)
}

system_profile_entry_matches :: proc(
	entry: ^shared.System_Profile_Entry,
	kind: shared.System_Profile_Kind,
	name: string,
) -> bool {
	if entry == nil || entry.kind != kind {
		return false
	}
	length := min(len(name), shared.SYSTEM_PROFILE_NAME_CAPACITY)
	if entry.name_length != length {
		return false
	}
	for index in 0 ..< length {
		if entry.name[index] != name[index] {
			return false
		}
	}
	return true
}

system_profile_set_entry :: proc(
	entry: ^shared.System_Profile_Entry,
	kind: shared.System_Profile_Kind,
	name: string,
) {
	entry^ = {}
	entry.kind = kind
	entry.name_length = min(len(name), shared.SYSTEM_PROFILE_NAME_CAPACITY)
	for index in 0 ..< entry.name_length {
		entry.name[index] = name[index]
	}
}

system_profile_prepare :: proc(
	profile: ^System_Profile_Accumulator,
	native_extensions: ^native.Extension_Set,
	script_runtime: ^script.Runtime,
) {
	if profile == nil || native_extensions == nil || script_runtime == nil {
		return
	}
	entry_count :=
		ENGINE_SYSTEM_PROFILE_COUNT + native_extensions.system_count + script_runtime.system_count
	topology_changed := profile.snapshot.entry_count != entry_count
	if !topology_changed {
		for phase in render.Engine_System_Profile_Phase {
			if phase == .Count {
				continue
			}
			if !system_profile_entry_matches(
				&profile.snapshot.entries[int(phase)],
				.Engine,
				engine_system_profile_name(phase),
			) {
				topology_changed = true
				break
			}
		}
	}
	if !topology_changed {
		for index in 0 ..< native_extensions.system_count {
			if !system_profile_entry_matches(
				&profile.snapshot.entries[ENGINE_SYSTEM_PROFILE_COUNT + index],
				.Project_Odin,
				native_extensions.systems[index].name,
			) {
				topology_changed = true
				break
			}
		}
	}
	if !topology_changed {
		for index in 0 ..< script_runtime.system_count {
			profile_index := ENGINE_SYSTEM_PROFILE_COUNT + native_extensions.system_count + index
			system := &script_runtime.systems[index]
			name := string(system.name[:system.name_length])
			if !system_profile_entry_matches(
				&profile.snapshot.entries[profile_index],
				.Luau,
				name,
			) {
				topology_changed = true
				break
			}
		}
	}
	if !topology_changed {
		return
	}
	revision := profile.snapshot.revision + 1
	profile^ = {}
	profile.snapshot.entry_count = entry_count
	profile.snapshot.revision = revision
	for phase in render.Engine_System_Profile_Phase {
		if phase == .Count {
			continue
		}
		system_profile_set_entry(
			&profile.snapshot.entries[int(phase)],
			.Engine,
			engine_system_profile_name(phase),
		)
	}
	for index in 0 ..< native_extensions.system_count {
		system_profile_set_entry(
			&profile.snapshot.entries[ENGINE_SYSTEM_PROFILE_COUNT + index],
			.Project_Odin,
			native_extensions.systems[index].name,
		)
	}
	for index in 0 ..< script_runtime.system_count {
		profile_index := ENGINE_SYSTEM_PROFILE_COUNT + native_extensions.system_count + index
		system := &script_runtime.systems[index]
		name := string(system.name[:system.name_length])
		system_profile_set_entry(&profile.snapshot.entries[profile_index], .Luau, name)
	}
}

system_profile_commit_frame :: proc(profile: ^System_Profile_Accumulator, durations: []i64) {
	if profile == nil {
		return
	}
	for index in 0 ..< min(profile.snapshot.entry_count, len(durations)) {
		previous := i64(0)
		if profile.sample_count == SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES {
			previous = profile.samples[index][profile.sample_cursor]
		}
		profile.samples[index][profile.sample_cursor] = durations[index]
		profile.totals[index] += durations[index] - previous
	}
	profile.sample_cursor = (profile.sample_cursor + 1) % SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES
	profile.sample_count = min(profile.sample_count + 1, SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES)
	profile.frames_since_publish += 1
	if profile.frames_since_publish < SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES {
		return
	}
	for index in 0 ..< profile.snapshot.entry_count {
		profile.snapshot.entries[index].average_nanoseconds =
			f64(profile.totals[index]) / f64(profile.sample_count)
	}
	profile.snapshot.sample_frames = profile.sample_count
	profile.frames_since_publish = 0
	profile.snapshot.revision += 1
}

system_profile_begin_frame :: proc(
	profile: ^System_Profile_Accumulator,
	native_extensions: ^native.Extension_Set,
	script_runtime: ^script.Runtime,
) {
	if profile == nil {
		return
	}
	system_profile_prepare(profile, native_extensions, script_runtime)
	profile.pending_durations = {}
}

system_profile_record_engine :: proc(
	profile: ^System_Profile_Accumulator,
	phase: render.Engine_System_Profile_Phase,
	duration_nanoseconds: i64,
) {
	if profile == nil || phase == .Count {
		return
	}
	profile.pending_durations[int(phase)] = duration_nanoseconds
}

system_profile_commit_pending_frame :: proc(profile: ^System_Profile_Accumulator) {
	if profile == nil || profile.snapshot.entry_count == 0 {
		return
	}
	system_profile_commit_frame(profile, profile.pending_durations[:profile.snapshot.entry_count])
}

step_frame_runtime_parts :: proc(
	script_runtime: ^script.Runtime,
	native_extensions: ^native.Extension_Set,
	executor: ^schedule.Executor,
	frame_systems: ^Frame_System_Cache,
	system_profile: ^System_Profile_Accumulator,
	world: ^shared.World,
	frame_time: shared.Time_Resource,
) -> string {
	if script_runtime == nil || native_extensions == nil || executor == nil {
		return ""
	}
	if script_runtime.L != nil {
		script_runtime.world = world
	}

	system_count := native_extensions.system_count + script_runtime.system_count
	if system_count > schedule.MAX_SYSTEMS {
		return "too many frame systems"
	}
	system_profile_prepare(system_profile, native_extensions, script_runtime)
	if system_count == 0 {
		return ""
	}

	scheduled_systems: [schedule.MAX_SYSTEMS]schedule.System
	frame_durations: [schedule.MAX_SYSTEMS]i64
	index := 0
	for system in native_extensions.systems[:native_extensions.system_count] {
		scheduled_systems[index] = system.declaration
		index += 1
	}
	for system in script_runtime.systems[:script_runtime.system_count] {
		scheduled_systems[index] = system.declaration
		index += 1
	}

	plan := prepare_frame_system_cache(
		frame_systems,
		scheduled_systems[:system_count],
		native_extensions.system_count,
	)
	if plan == nil {
		return "frame-system cache is unavailable"
	}
	if !executor.initialized {
		max_native_width := 0
		for batch in plan.batches[:plan.batch_count] {
			native_width := 0
			for i in 0 ..< batch.system_count {
				if batch.system_indices[i] < native_extensions.system_count {
					native_width += 1
				}
			}
			max_native_width = max(max_native_width, native_width)
		}
		if max_native_width > 1 {
			schedule.init_executor(executor, max_native_width)
		}
	}
	for batch in plan.batches[:plan.batch_count] {
		native_work: [schedule.MAX_SYSTEMS]schedule.Work
		native_contexts: [schedule.MAX_SYSTEMS]Native_Work_Context
		native_count := 0
		for i in 0 ..< batch.system_count {
			system_index := batch.system_indices[i]
			if system_index < native_extensions.system_count {
				work_context := &native_contexts[native_count]
				commands := &frame_systems.native_commands[native_count]
				ecs.clear_commands(commands)
				work_context.system = &native_extensions.systems[system_index]
				work_context.world = world
				work_context.commands = commands
				work_context.registry = &script_runtime.registry
				work_context.time = frame_time
				work_context.system_index = system_index
				native_work[native_count] = schedule.Work {
					procedure = run_native_work,
					data = work_context,
				}
				native_count += 1
				continue
			}
		}

		schedule.run_parallel(executor, native_work[:native_count])
		for i in 0 ..< native_count {
			work_context := &native_contexts[i]
			if work_context.err != "" {
				for j in 0 ..< native_count {
					ecs.clear_commands(native_contexts[j].commands)
				}
				ecs.clear_commands(&script_runtime.commands)
				return work_context.err
			}
			frame_durations[work_context.system_index] = work_context.duration_ns
			if err := ecs.append_commands(&script_runtime.commands, work_context.commands);
			   err != "" {
				for j in 0 ..< native_count {
					ecs.clear_commands(native_contexts[j].commands)
				}
				ecs.clear_commands(&script_runtime.commands)
				return err
			}
		}
		for i in 0 ..< batch.system_count {
			system_index := batch.system_indices[i]
			if system_index < native_extensions.system_count {
				continue
			}
			script_index := system_index - native_extensions.system_count
			system := script_runtime.systems[script_index]
			start := time.tick_now()
			err := script.run_script_system(script_runtime, script_runtime.L, system, frame_time)
			finish := time.tick_now()
			frame_durations[system_index] = time.duration_nanoseconds(
				time.tick_diff(start, finish),
			)
			if err != "" {
				ecs.clear_commands(&script_runtime.commands)
				return err
			}
		}
	}

	if err := ecs.apply_commands(world, &script_runtime.commands); err != "" {
		return err
	}
	for index in 0 ..< system_count {
		system_profile.pending_durations[ENGINE_SYSTEM_PROFILE_COUNT + index] =
			frame_durations[index]
	}
	return ""
}

run_native_work :: proc(data: rawptr) {
	work := cast(^Native_Work_Context)data
	start := time.tick_now()
	work.err = native.step_system(work.system, work.world, work.commands, work.registry, work.time)
	finish := time.tick_now()
	work.duration_ns = time.duration_nanoseconds(time.tick_diff(start, finish))
}

build_native_extensions :: proc(root: string, config: ^shared.Project_Config) -> string {
	if config == nil {
		return ""
	}
	build_result := native.build_project_extensions(root, config.native_extensions[:])
	return build_result.err
}
