package scrapbot

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import ecs "./ecs"
import component "./component"
import native "./native"
import project "./project"
import render "./render"
import resources "./resources"
import schedule "./schedule"
import script "./script"
import shared "./shared"
import ui "./ui"

VERSION :: "0.1.0-dev"

PROJECT_FILE :: shared.PROJECT_FILE
DEFAULT_SCENE :: shared.DEFAULT_SCENE
DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_LUAU_TYPES :: shared.DEFAULT_LUAU_TYPES

Renderer_Backend :: shared.Renderer_Backend
Run_Config :: render.Run_Config
Project_Load_Result :: project.Project_Load_Result
Runtime_Result :: struct {
	frame: shared.Render_Frame,
	err:   string,
	scheduler_workers: int,
	parallel_stages:   int,
	max_parallel_width: int,
	draw_batches: int,
}

Frame_Runtime :: struct {
	script_runtime: script.Runtime,
	native_extensions: native.Extension_Set,
	executor: schedule.Executor,
	resources: resources.Registry,
}

Native_Work_Context :: struct {
	system:         ^native.Native_System,
	world:          ^shared.World,
	commands:       ecs.Command_Buffer,
	registry:       ^component.Registry,
	time:           shared.Time_Resource,
	err:            string,
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

	return build_native_extensions(root, &loaded.config)
}

check_project :: proc(root: string) -> string {
	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	if err := build_native_extensions(root, &loaded.config); err != "" {
		return err
	}

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)

	registry: component.Registry
	component.init_registry(&registry)
	render_resources: resources.Registry
	defer resources.destroy_registry(&render_resources)
	if err := init_render_resources(&render_resources, &world); err != "" {return err}
	extensions: native.Extension_Set
	defer native.destroy_extension_set(&extensions)
	if extension_load := native.load_project_extensions(&extensions, root, &registry, &render_resources); extension_load.err != "" {
		return extension_load.err
	}

	runtime: script.Runtime
	defer script.destroy_runtime(&runtime)
	script_result := script.run_project_script_with_registry(&runtime, root, &world, &registry, script.Source_Options{resource_registry = &render_resources})
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

	temp_dir, temp_err := os.make_directory_temp("", "scrapbot-luau-analyze-*", context.temp_allocator)
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

run_project_internal :: proc(root: string, config: Run_Config, extensions_prebuilt: bool) -> Runtime_Result {
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
	if !extensions_prebuilt {
		if err := build_native_extensions(root, &loaded.config); err != "" {
			result.err = err
			return result
		}
	}

	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)
	ui_state:=new(ui.State)
	defer free(ui_state)
	if ui_err:=ui.init(ui_state);ui_err!=""{result.err=ui_err;return result}
	ui_state.editor_visible=run_config.editor
	defer ui.destroy(ui_state)
	run_config.ui_state=ui_state

	if run_config.hot_reload {
		hot_reload: Hot_Reload_State
		defer destroy_hot_reload_state(&hot_reload)
		if err := init_hot_reload_state(&hot_reload, root, &loaded, &world); err != "" {
			result.err = err
			return result
		}

		run_config.frame_system = hot_reload_frame_system
		run_config.frame_system_data = &hot_reload
		run_config.resource_registry = &hot_reload.resources
		result.frame, result.err = render.run_renderer(run_config, &world)
		result.scheduler_workers = hot_reload.executor.worker_count
		result.parallel_stages = hot_reload.executor.parallel_stages
		result.max_parallel_width = hot_reload.executor.max_parallel_width
		result.draw_batches = render_stats.draw_batches
		return result
	}

	registry: component.Registry
	component.init_registry(&registry)
	frame_runtime: Frame_Runtime
	defer script.destroy_runtime(&frame_runtime.script_runtime)
	defer native.destroy_extension_set(&frame_runtime.native_extensions)
	defer schedule.destroy_executor(&frame_runtime.executor)
	defer resources.destroy_registry(&frame_runtime.resources)
	if err := init_render_resources(&frame_runtime.resources, &world); err != "" {result.err = err; return result}
	extensions: native.Extension_Set
	defer native.destroy_extension_set(&extensions)
	if extension_load := native.load_project_extensions(&extensions, root, &registry, &frame_runtime.resources); extension_load.err != "" {
		result.err = extension_load.err
		return result
	}

	script_result := script.run_project_script_with_registry(
		&frame_runtime.script_runtime,
		root,
		&world,
		&registry,
		script.Source_Options{log_enabled = config.log_enabled, resource_registry = &frame_runtime.resources},
	)
	if script_result.err != "" {
		result.err = script_result.err
		return result
	}
	frame_runtime.native_extensions = extensions
	extensions = {}
	if script_result.ran || frame_runtime.native_extensions.system_count > 0 {
		run_config.frame_system = step_frame_runtime_system
		run_config.frame_system_data = &frame_runtime
	}
	run_config.resource_registry = &frame_runtime.resources

	result.frame, result.err = render.run_renderer(run_config, &world)
	result.scheduler_workers = frame_runtime.executor.worker_count
	result.parallel_stages = frame_runtime.executor.parallel_stages
	result.max_parallel_width = frame_runtime.executor.max_parallel_width
	result.draw_batches = render_stats.draw_batches
	return result
}

init_render_resources :: proc(registry: ^resources.Registry, world: ^shared.World) -> string {
	cube_desc, cube_err := resources.cube(2)
	if cube_err != "" {return cube_err}
	defer delete(cube_desc.vertices); defer delete(cube_desc.indices)
	cube_handle, register_err := resources.register_geometry(registry, "cube", cube_desc)
	if register_err != "" {return register_err}
	material_handle, material_err := resources.register_material(registry, "default", {base_color = {0.3, 0.7, 0.95, 1}})
	if material_err != "" {return material_err}
	for entity, index in world.entities {
		if entity.mesh_index >= 0 {
			ecs.add_geometry(world, index, cube_handle)
			ecs.add_material(world, index, material_handle)
		}
	}
	return ""
}

step_frame_runtime_system :: proc(data: rawptr, world: ^shared.World, delta_seconds: f32) -> string {
	runtime := cast(^Frame_Runtime)data
	if runtime == nil {
		return ""
	}
	return step_frame_runtime(runtime, world, delta_seconds)
}

step_frame_runtime :: proc(runtime: ^Frame_Runtime, world: ^shared.World, delta_seconds: f32) -> string {
	if runtime == nil {
		return ""
	}
	ecs.advance_time(&world.time, delta_seconds)
	return step_frame_runtime_parts(&runtime.script_runtime, &runtime.native_extensions, &runtime.executor, world, world.time)
}

step_frame_runtime_parts :: proc(
	script_runtime: ^script.Runtime,
	native_extensions: ^native.Extension_Set,
	executor: ^schedule.Executor,
	world: ^shared.World,
	time: shared.Time_Resource,
) -> string {
	if script_runtime == nil || native_extensions == nil || executor == nil {
		return ""
	}
	if script_runtime.L != nil {
		script_runtime.world = world
	}

	system_count := native_extensions.system_count + script_runtime.system_count
	if system_count == 0 {
		return ""
	}
	if system_count > schedule.MAX_SYSTEMS {
		return "too many frame systems"
	}

	scheduled_systems: [schedule.MAX_SYSTEMS]schedule.System
	index := 0
	for system in native_extensions.systems[:native_extensions.system_count] {
		scheduled_systems[index] = system.declaration
		index += 1
	}
	for system in script_runtime.systems[:script_runtime.system_count] {
		scheduled_systems[index] = system.declaration
		index += 1
	}

	plan := schedule.build_plan(scheduled_systems[:system_count])
	if !executor.initialized {
		max_native_width := 0
		for batch in plan.batches[:plan.batch_count] {
			native_width := 0
			for i in 0..<batch.system_count {
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
		for i in 0..<batch.system_count {
			system_index := batch.system_indices[i]
			if system_index < native_extensions.system_count {
				work_context := &native_contexts[native_count]
				ecs.init_command_buffer(&work_context.commands)
				work_context.system = &native_extensions.systems[system_index]
				work_context.world = world
				work_context.registry = &script_runtime.registry
				work_context.time = time
				native_work[native_count] = schedule.Work {
					procedure = run_native_work,
					data = work_context,
				}
				native_count += 1
				continue
			}
		}

		schedule.run_parallel(executor, native_work[:native_count])
		for i in 0..<native_count {
			work_context := &native_contexts[i]
			if work_context.err != "" {
				for j in 0..<native_count {
					ecs.destroy_command_buffer(&native_contexts[j].commands)
				}
				ecs.clear_commands(&script_runtime.commands)
				return work_context.err
			}
			if err := ecs.append_commands(&script_runtime.commands, &work_context.commands); err != "" {
				for j in 0..<native_count {
					ecs.destroy_command_buffer(&native_contexts[j].commands)
				}
				ecs.clear_commands(&script_runtime.commands)
				return err
			}
		}
		for i in 0..<native_count {
			ecs.destroy_command_buffer(&native_contexts[i].commands)
		}

		for i in 0..<batch.system_count {
			system_index := batch.system_indices[i]
			if system_index < native_extensions.system_count {
				continue
			}
			script_index := system_index - native_extensions.system_count
			system := script_runtime.systems[script_index]
			if err := script.run_script_system(script_runtime, script_runtime.L, system, time); err != "" {
				ecs.clear_commands(&script_runtime.commands)
				return err
			}
		}
	}

	return ecs.apply_commands(world, &script_runtime.commands)
}

run_native_work :: proc(data: rawptr) {
	work := cast(^Native_Work_Context)data
	work.err = native.step_system(
		work.system,
		work.world,
		&work.commands,
		work.registry,
		work.time,
	)
}

build_native_extensions :: proc(root: string, config: ^shared.Project_Config) -> string {
	if config == nil {
		return ""
	}
	build_result := native.build_project_extensions(root, config.native_extensions[:])
	return build_result.err
}
