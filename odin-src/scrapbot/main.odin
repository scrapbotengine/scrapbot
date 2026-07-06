package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

VERSION :: "0.0.0-odin-migration"
DEFAULT_STEP_FRAMES :: 1
DEFAULT_BENCH_FRAMES :: 240
DEFAULT_STEP_DELTA_SECONDS :: f32(1.0 / 60.0)

Simulation_Options :: struct {
	target_path:   string,
	frames:        int,
	delta_seconds: f32,
	format:        Check_Output_Format,
}

main :: proc() {
	exit_code := run(os.args)
	if exit_code != 0 {
		os.exit(exit_code)
	}
}

run :: proc(args: []string) -> int {
	return run_with_output(args, true)
}

run_with_output :: proc(args: []string, emit_output: bool) -> int {
	if len(args) <= 1 {
		if emit_output {
			print_help()
		}
		return 0
	}

	command := args[1]
	if command == "--version" {
		fmt.println(VERSION)
		return 0
	}
	if command == "help" || command == "--help" {
		if emit_output {
			print_help()
		}
		return 0
	}
	if command == "check" {
		return run_check(args[2:], emit_output)
	}
	if command == "step" {
		return run_step(args[2:], emit_output)
	}
	if command == "bench" {
		return run_bench(args[2:], emit_output)
	}
	if command == "test" {
		return run_test(args[2:], emit_output)
	}
	if command == "run" {
		return run_project(args[2:], emit_output)
	}
	if command == "init" {
		return run_init(args[2:], emit_output)
	}
	if command == "build" {
		return run_build(args[2:], emit_output)
	}

	if emit_output {
		fmt.eprintf("unknown command: %s\n", command)
		print_help()
	}
	return 1
}

print_help :: proc() {
	fmt.println(`scrapbot - agent-native game engine

Usage:
  scrapbot --version
  scrapbot help
  scrapbot init [path]
  scrapbot check [path] [--format text|json]
  scrapbot step [path] [--frames N] [--dt seconds] [--format text|json]
  scrapbot bench [path] [--frames N] [--dt seconds] [--format text|json]
  scrapbot test [path] [--format text|json]
  scrapbot run [path] [--frames N] [--editor] [--hidden]
  scrapbot build [path] [--output DIR] [--name NAME] [--force] [--format text|json]

Odin migration status:
  init, check, build, deterministic step, benchmark, test discovery, and bounded run
  currently cover text project creation, validation, packaging, and schedule-aware frame accounting slices.
  Luau/native callback execution, assertion evaluation, rendering, and editor are still being ported.`)
}

run_init :: proc(args: []string, emit_output: bool) -> int {
	target_path := "."
	if len(args) > 1 {
		if emit_output {
			fmt.eprintln("unknown argument")
		}
		return 1
	}
	if len(args) == 1 {
		target_path = args[0]
	}

	name := project_name_from_path(target_path)
	err := init_project(target_path, name)
	if err != .None {
		if emit_output {
			fmt.eprintf("init failed: %s: %s\n", target_path, project_error_message(err))
		}
		return 1
	}

	if emit_output {
		fmt.printf("Initialized Scrapbot project at %s\n", target_path)
	}
	return 0
}

run_build :: proc(args: []string, emit_output: bool) -> int {
	options := Build_Options{target_path = "."}
	format: Check_Output_Format = .Text

	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--force" {
			options.force = true
			i += 1
			continue
		}
		if strings.has_prefix(arg, "--output=") {
			options.output_root = arg[len("--output="):]
			i += 1
			continue
		}
		if arg == "--output" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --output")
				}
				return 1
			}
			options.output_root = args[i + 1]
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--name=") {
			options.name = arg[len("--name="):]
			i += 1
			continue
		}
		if arg == "--name" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --name")
				}
				return 1
			}
			options.name = args[i + 1]
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--format=") {
			parsed, ok := parse_output_format(arg[len("--format="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", arg[len("--format="):])
				}
				return 1
			}
			format = parsed
			i += 1
			continue
		}
		if arg == "--format" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --format")
				}
				return 1
			}
			parsed, ok := parse_output_format(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", args[i + 1])
				}
				return 1
			}
			format = parsed
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return 1
		}
		if options.target_path != "." {
			if emit_output {
				fmt.eprintf("unexpected argument: %s\n", arg)
			}
			return 1
		}
		options.target_path = arg
		i += 1
	}

	result, err := build_project(options)
	if err != .None {
		if emit_output {
			print_build_error(err, options.target_path, format)
		}
		return 1
	}
	defer free_build_result(result)

	if emit_output {
		print_build_result(result, format)
	}
	return 0
}

run_step :: proc(args: []string, emit_output: bool) -> int {
	options, options_ok := parse_simulation_options(args, DEFAULT_STEP_FRAMES, emit_output)
	if !options_ok {
		return 1
	}

	result := check_project(options.target_path)
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_check_error(result.err, options.target_path, options.format)
		}
		return 1
	}

	if emit_output {
		print_step_result(result, options)
	}
	return 0
}

run_bench :: proc(args: []string, emit_output: bool) -> int {
	options, options_ok := parse_simulation_options(args, DEFAULT_BENCH_FRAMES, emit_output)
	if !options_ok {
		return 1
	}

	startup_start := time.tick_now()
	result := check_project(options.target_path)
	startup_ns := time.duration_nanoseconds(time.tick_since(startup_start))
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_check_error(result.err, options.target_path, options.format)
		}
		return 1
	}

	update_start := time.tick_now()
	completed_frames := 0
	for completed_frames < options.frames {
		completed_frames += 1
	}
	update_ns := time.duration_nanoseconds(time.tick_since(update_start))

	if emit_output {
		print_bench_result(result, options, startup_ns, update_ns, completed_frames)
	}
	return 0
}

run_test :: proc(args: []string, emit_output: bool) -> int {
	options, options_ok := parse_test_options(args, emit_output)
	if !options_ok {
		return 1
	}

	result, err := run_test_command(options)
	defer free_test_command_result(result)
	if err != .None {
		if emit_output {
			print_test_command_error(err, options.target_path, options.format)
		}
		return 1
	}

	if emit_output {
		print_test_command_result(result, options.format)
	}
	if result.summary.failed > 0 {
		return 1
	}
	return 0
}

run_project :: proc(args: []string, emit_output: bool) -> int {
	options, options_ok := parse_run_options(args, emit_output)
	if !options_ok {
		return 1
	}

	result := check_project(options.target_path)
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_check_error(result.err, options.target_path, .Text)
		}
		return 1
	}

	if emit_output {
		print_run_result(result, options)
	}
	return 0
}

run_check :: proc(args: []string, emit_output: bool) -> int {
	target_path := "."
	format: Check_Output_Format = .Text

	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--format" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --format")
				}
				return 1
			}
			switch args[i + 1] {
			case "text":
				format = .Text
			case "json":
				format = .JSON
			case:
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", args[i + 1])
				}
				return 1
			}
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return 1
		}
		if target_path != "." {
			if emit_output {
				fmt.eprintf("unexpected argument: %s\n", arg)
			}
			return 1
		}
		target_path = arg
		i += 1
	}

	result := check_project(target_path)
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_check_error(result.err, target_path, format)
		}
		return 1
	}
	if !emit_output {
		return 0
	}

	project := result.project
	scene := result.scene
	switch format {
	case .Text:
		fmt.printf("Project OK: %s\n", project.name)
		fmt.printf("Default scene: %s\n", project.default_scene)
		fmt.printf("Scene: %s\n", scene.name)
		fmt.printf("Entities: %d\n", scene.entity_count)
		fmt.printf("Components: %d\n", scene.component_instance_count)
		fmt.printf("Renderable cubes: %d\n", scene.renderable_cube_count)
		fmt.printf("Scripts: %d\n", len(project.scripts))
		fmt.printf(
			"Schedules: startup %d batches/%d systems, update %d batches/%d systems, fixed_update %d batches/%d systems, render %d batches/%d systems\n",
			runtime_system_schedule_batch_count(result.startup_schedule),
			runtime_system_schedule_system_count(result.startup_schedule),
			runtime_system_schedule_batch_count(result.update_schedule),
			runtime_system_schedule_system_count(result.update_schedule),
			runtime_system_schedule_batch_count(result.fixed_update_schedule),
			runtime_system_schedule_system_count(result.fixed_update_schedule),
			runtime_system_schedule_batch_count(result.render_schedule),
			runtime_system_schedule_system_count(result.render_schedule),
		)
		if project.native != "" {
			fmt.printf("Native source: %s\n", project.native)
		}
		if project.native_artifact != "" {
			fmt.printf("Native artifact: %s\n", project.native_artifact)
		}
		fmt.println("Runtime validation: schedules ok")
	case .JSON:
		fmt.print(`{"ok":true,"project":`)
		fmt.print(`{"name":"`)
		json_print(project.name, false)
		fmt.print(`","default_scene":"`)
		json_print(project.default_scene, false)
		fmt.printf(`","scripts":%d`, len(project.scripts))
		fmt.print(`},"scene":`)
		fmt.print(`{"name":"`)
		json_print(scene.name, false)
		fmt.printf(
			`","entities":%d,"components":%d,"renderable_cubes":%d`,
			scene.entity_count,
			scene.component_instance_count,
			scene.renderable_cube_count,
		)
		fmt.print(`},"schedule":`)
		print_schedule_summary_json(result)
		fmt.println(`,"runtime_validation":"schedules_ok"}`)
	}

	return 0
}

print_step_result :: proc(result: Project_Check_Result, options: Simulation_Options) {
	switch options.format {
	case .Text:
		fmt.printf("Step OK: %s\n", result.project.name)
		fmt.printf("Scene: %s\n", result.scene.name)
		fmt.printf("Frames: %d/%d, dt: %g\n", options.frames, options.frames, options.delta_seconds)
		fmt.printf("Entities: %d, components: %d, renderable cubes: %d\n", result.scene.entity_count, result.scene.component_instance_count, result.scene.renderable_cube_count)
		fmt.printf("Update batches: %d, systems: %d\n", runtime_system_schedule_batch_count(result.update_schedule), runtime_system_schedule_system_count(result.update_schedule))
		fmt.println("Execution: pending Luau/native Odin bridge")
	case .JSON:
		fmt.print(`{"ok":true,"project":`)
		fmt.print(`{"name":"`)
		json_print(result.project.name, false)
		fmt.print(`","default_scene":"`)
		json_print(result.project.default_scene, false)
		fmt.printf(`","scripts":%d`, len(result.project.scripts))
		fmt.print(`},"scene":{"name":"`)
		json_print(result.scene.name, false)
		fmt.printf(`","entities":%d,"components":%d,"renderable_cubes":%d`, result.scene.entity_count, result.scene.component_instance_count, result.scene.renderable_cube_count)
		fmt.print(`},"simulation":{`)
		fmt.printf(`"frames":%d,"completed_frames":%d,"dt":%g`, options.frames, options.frames, options.delta_seconds)
		fmt.print(`}`)
		fmt.print(`,"schedule":`)
		print_schedule_summary_json(result)
		fmt.println(`,"execution":"pending_odin_luau_native_bridge"}`)
	}
}

print_bench_result :: proc(result: Project_Check_Result, options: Simulation_Options, startup_ns, update_ns: i64, completed_frames: int) {
	ns_per_frame := f64(0)
	if completed_frames > 0 {
		ns_per_frame = f64(update_ns) / f64(completed_frames)
	}
	startup_ms := f64(startup_ns) / 1_000_000.0
	update_ms := f64(update_ns) / 1_000_000.0
	ms_per_frame := ns_per_frame / 1_000_000.0
	switch options.format {
	case .Text:
		fmt.printf("Benchmark OK: %s\n", result.project.name)
		fmt.printf("Scene: %s\n", result.scene.name)
		fmt.printf("Frames: %d, dt: %g\n", options.frames, options.delta_seconds)
		fmt.printf("Startup: %g ms\n", startup_ms)
		fmt.printf("Update: %g ms total, %g ms/frame\n", update_ms, ms_per_frame)
		fmt.printf("Entities: %d, components: %d, renderable cubes: %d\n", result.scene.entity_count, result.scene.component_instance_count, result.scene.renderable_cube_count)
		fmt.printf("Update batches: %d, systems: %d\n", runtime_system_schedule_batch_count(result.update_schedule), runtime_system_schedule_system_count(result.update_schedule))
		fmt.println("Execution: pending Luau/native Odin bridge")
		print_render_extract_text(result)
		fmt.println("Renderer backend: pending Odin wgpu-native binding")
	case .JSON:
		fmt.print(`{"ok":true,"project":`)
		fmt.print(`{"name":"`)
		json_print(result.project.name, false)
		fmt.print(`","default_scene":"`)
		json_print(result.project.default_scene, false)
		fmt.printf(`","scripts":%d`, len(result.project.scripts))
		fmt.print(`},"scene":{"name":"`)
		json_print(result.scene.name, false)
		fmt.printf(`","entities":%d,"components":%d,"renderable_cubes":%d`, result.scene.entity_count, result.scene.component_instance_count, result.scene.renderable_cube_count)
		fmt.print(`},"benchmark":{`)
		fmt.printf(`"frames":%d,"completed_frames":%d,"dt":%g,"startup_ns":%d,"update_ns":%d,"ns_per_frame":%g`, options.frames, completed_frames, options.delta_seconds, startup_ns, update_ns, ns_per_frame)
		fmt.print(`}`)
		fmt.print(`,"schedule":`)
		print_schedule_summary_json(result)
		fmt.print(`,"render_stats":`)
		print_render_extract_json(result)
		fmt.println(`,"execution":"pending_odin_luau_native_bridge","renderer_backend":"pending_odin_wgpu_native_binding"}`)
	}
}

print_render_extract_text :: proc(result: Project_Check_Result) {
	extract, extract_err := render_extract_scene(result.scene.world)
	if extract_err != .None {
		fmt.println("Render stats: invalid scene render data")
		return
	}
	fmt.printf(
		"Render stats: %d renderables, %d batches, %d cameras, %d directional lights, %d UI rects, %d UI texts\n",
		extract.renderables,
		extract.render_batches,
		extract.cameras,
		extract.directional_lights,
		extract.ui_rects,
		extract.ui_texts,
	)
}

print_render_extract_json :: proc(result: Project_Check_Result) {
	extract, extract_err := render_extract_scene(result.scene.world)
	if extract_err != .None {
		fmt.print(`{"status":"invalid_scene"}`)
		return
	}
	fmt.print(`{"status":"ok"`)
	fmt.printf(
		`,"renderables":%d,"legacy_cubes":%d,"geometry_primitives":%d,"batches":%d,"cameras":%d,"directional_lights":%d,"ui_rects":%d,"ui_texts":%d,"shadow_casters":%d,"shadow_receivers":%d`,
		extract.renderables,
		extract.legacy_cubes,
		extract.geometry_primitives,
		extract.render_batches,
		extract.cameras,
		extract.directional_lights,
		extract.ui_rects,
		extract.ui_texts,
		extract.shadow_casters,
		extract.shadow_receivers,
	)
	fmt.print(`}`)
}

print_schedule_summary_json :: proc(result: Project_Check_Result) {
	fmt.print(`{`)
	print_schedule_phase_json("startup", result.startup_schedule, false)
	print_schedule_phase_json("update", result.update_schedule, true)
	print_schedule_phase_json("fixed_update", result.fixed_update_schedule, true)
	print_schedule_phase_json("render", result.render_schedule, true)
	fmt.print(`}`)
}

print_schedule_phase_json :: proc(name: string, schedule: Runtime_System_Schedule, comma: bool) {
	if comma {
		fmt.print(`,`)
	}
	fmt.print(`"`)
	json_print(name, false)
	fmt.print(`":{`)
	fmt.printf(`"batches":%d,"systems":%d`, runtime_system_schedule_batch_count(schedule), runtime_system_schedule_system_count(schedule))
	fmt.print(`}`)
}

parse_output_format :: proc(value: string) -> (Check_Output_Format, bool) {
	switch value {
	case "text":
		return .Text, true
	case "json":
		return .JSON, true
	}
	return .Text, false
}

parse_simulation_options :: proc(args: []string, default_frames: int, emit_output: bool) -> (Simulation_Options, bool) {
	options := Simulation_Options{
		target_path = ".",
		frames = default_frames,
		delta_seconds = DEFAULT_STEP_DELTA_SECONDS,
		format = .Text,
	}
	i := 0
	for i < len(args) {
		arg := args[i]
		if strings.has_prefix(arg, "--frames=") {
			frames, ok := parse_positive_int(arg[len("--frames="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --frames: %s\n", arg[len("--frames="):])
				}
				return options, false
			}
			options.frames = frames
			i += 1
			continue
		}
		if arg == "--frames" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --frames")
				}
				return options, false
			}
			frames, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --frames: %s\n", args[i + 1])
				}
				return options, false
			}
			options.frames = frames
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--dt=") {
			delta_seconds, ok := parse_positive_f32(arg[len("--dt="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --dt: %s\n", arg[len("--dt="):])
				}
				return options, false
			}
			options.delta_seconds = delta_seconds
			i += 1
			continue
		}
		if arg == "--dt" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --dt")
				}
				return options, false
			}
			delta_seconds, ok := parse_positive_f32(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --dt: %s\n", args[i + 1])
				}
				return options, false
			}
			options.delta_seconds = delta_seconds
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--format=") {
			parsed, ok := parse_output_format(arg[len("--format="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", arg[len("--format="):])
				}
				return options, false
			}
			options.format = parsed
			i += 1
			continue
		}
		if arg == "--format" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --format")
				}
				return options, false
			}
			parsed, ok := parse_output_format(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --format: %s\n", args[i + 1])
				}
				return options, false
			}
			options.format = parsed
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return options, false
		}
		if options.target_path != "." {
			if emit_output {
				fmt.eprintf("unexpected argument: %s\n", arg)
			}
			return options, false
		}
		options.target_path = arg
		i += 1
	}
	return options, true
}

parse_positive_int :: proc(value: string) -> (int, bool) {
	parsed, ok := strconv.parse_int(value, 10)
	if !ok || parsed <= 0 {
		return 0, false
	}
	return parsed, true
}

parse_positive_f32 :: proc(value: string) -> (f32, bool) {
	parsed, ok := strconv.parse_f32(value)
	if !ok || parsed <= 0 || parsed != parsed || parsed > 3.4028234663852886e38 || parsed < -3.4028234663852886e38 {
		return 0, false
	}
	return parsed, true
}

print_build_error :: proc(err: Project_Error, target_path: string, format: Check_Output_Format) {
	message := project_error_message(err)
	switch format {
	case .Text:
		fmt.eprintf("%s: %s\n", target_path, message)
	case .JSON:
		fmt.print(`{"ok":false,"error":"`)
		json_print(message, false)
		fmt.print(`","path":"`)
		json_print(target_path, false)
		fmt.println(`"}`)
	}
}

print_build_result :: proc(result: Build_Result, format: Check_Output_Format) {
	switch format {
	case .Text:
		fmt.printf("Build OK: %s\n", result.project_name)
		fmt.printf("Bundle: %s\n", result.bundle_path)
		fmt.printf("Project: %s\n", result.project_path)
		fmt.printf("Runtime: %s\n", result.runtime_path)
		fmt.printf("Launcher: %s\n", result.launcher_path)
		if result.sdl3_warning != "" {
			fmt.printf("Warning: %s\n", result.sdl3_warning)
		}
	case .JSON:
		fmt.print(`{"ok":true,"project":"`)
		json_print(result.project_name, false)
		fmt.print(`","bundle":"`)
		json_print(result.bundle_path, false)
		fmt.print(`","project_path":"`)
		json_print(result.project_path, false)
		fmt.print(`","runtime":"`)
		json_print(result.runtime_path, false)
		fmt.print(`","launcher":"`)
		json_print(result.launcher_path, false)
		fmt.print(`","native_artifact":null,"sdl3_bundled":false,"sdl3_warning":"`)
		json_print(result.sdl3_warning, false)
		fmt.println(`"}`)
	}
}

print_check_error :: proc(err: Project_Error, target_path: string, format: Check_Output_Format) {
	message := project_error_message(err)
	switch format {
	case .Text:
		fmt.eprintf("Project invalid: %s: %s\n", target_path, message)
	case .JSON:
		fmt.eprint(`{"ok":false,"error":"`)
		json_print(message, true)
		fmt.eprint(`","path":"`)
		json_print(target_path, true)
		fmt.eprintln(`"}`)
	}
}

json_print :: proc(value: string, stderr: bool) {
	for c in value {
		switch c {
		case '"':
			print_json_fragment(`\"`, stderr)
		case '\\':
			print_json_fragment(`\\`, stderr)
		case '\n':
			print_json_fragment(`\n`, stderr)
		case '\r':
			print_json_fragment(`\r`, stderr)
		case '\t':
			print_json_fragment(`\t`, stderr)
		case:
			if stderr {
				fmt.eprintf("%c", c)
			} else {
				fmt.printf("%c", c)
			}
		}
	}
}

print_json_fragment :: proc(fragment: string, stderr: bool) {
	if stderr {
		fmt.eprint(fragment)
	} else {
		fmt.print(fragment)
	}
}
