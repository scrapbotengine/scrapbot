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
DEFAULT_WGPU_RENDER_TEST_OUTPUT :: "odin-out/wgpu-render-test.png"
DEFAULT_WGPU_RENDER_TEST_WIDTH :: 1
DEFAULT_WGPU_RENDER_TEST_HEIGHT :: 1

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
	if command == "--version" || command == "version" {
		if emit_output {
			fmt.println(VERSION)
		}
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
	if command == "render" {
		return run_render(args[2:], emit_output, false)
	}
	if command == "render-test" {
		return run_render(args[2:], emit_output, true)
	}
	if command == "visual-test" {
		return run_visual_test(args[2:], emit_output)
	}
	if command == "sdl-window-check" {
		return run_sdl_window_check(args[2:], emit_output)
	}
	if command == "wgpu-surface-check" {
		return run_wgpu_surface_check(args[2:], emit_output)
	}
	if command == "wgpu-check" {
		return run_wgpu_check(args[2:], emit_output)
	}
	if command == "wgpu-render-test" {
		return run_wgpu_render_test(args[2:], emit_output)
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
  scrapbot test [tests-path|project-path] [--format text|json]
  scrapbot run [path] [--frames N] [--editor] [--hidden] [--backend software|wgpu] [--render-output output.png] [--render-width PX] [--render-height PX] [--render-pixel-scale S]
  scrapbot render [--backend software|wgpu] [--editor] [--select entity-id] [--inspector-scroll-y PX] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
  scrapbot render-test [--backend software|wgpu] [--editor] [--select entity-id] [--inspector-scroll-y PX] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
  scrapbot visual-test [--backend software|wgpu] [--editor] [--select entity-id] [--inspector-scroll-y PX] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [--update] <path> <expected.png> [actual.png]
  scrapbot sdl-window-check [--hidden|--visible]
  scrapbot wgpu-surface-check [root] [--hidden|--visible]
  scrapbot wgpu-check [root]
  scrapbot wgpu-render-test [root] [output.png]
  scrapbot build [path] [--output DIR] [--name NAME] [--force] [--format text|json]

Odin migration status:
  init, check, build, deterministic step, benchmark, test discovery, and bounded run
  currently cover text project creation, validation, packaging, and schedule-aware frame accounting slices.
  Luau execution, native module execution, retained scene UI/editor input replay, software render/visual output,
  WebGPU offscreen run/render output, image comparison, first-pass offscreen editor chrome, and first-pass
  WebGPU editor chrome overlays are partially ported; hidden and bounded/unbounded visible WebGPU
  presentation are partially ported; the full editor shell is still being ported.`)
}

run_sdl_window_check :: proc(args: []string, emit_output: bool) -> int {
	hidden := true
	for arg in args {
		switch arg {
		case "--hidden":
			hidden = true
		case "--visible":
			hidden = false
		case:
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return 1
		}
	}

	init_err := sdl_video_init()
	if init_err != .None {
		if emit_output {
			fmt.eprintf("SDL window check failed: %s\n", sdl_window_error_message(init_err))
		}
		return 1
	}
	defer sdl_video_quit()

	window, window_err := sdl_window_create(sdl_window_default_options(hidden))
	defer sdl_window_destroy(&window)
	if window_err != .None {
		if emit_output {
			fmt.eprintf("SDL window check failed: %s\n", sdl_window_error_message(window_err))
		}
		return 1
	}

	size, size_err := sdl_window_get_size(window.window)
	if size_err != .None {
		if emit_output {
			fmt.eprintf("SDL window size check failed: %s\n", sdl_window_error_message(size_err))
		}
		return 1
	}

	surface_descriptor := Sdl_WGPU_Surface_Descriptor{}
	surface_err := sdl_window_init_surface_descriptor(&surface_descriptor, window.window)
	defer sdl_wgpu_surface_descriptor_deinit(&surface_descriptor)
	if surface_err != .None {
		if emit_output {
			fmt.eprintf("SDL surface check failed: %s\n", sdl_window_error_message(surface_err))
		}
		return 1
	}

	if emit_output {
		fmt.printf("SDL window OK: %s\n", hidden ? "hidden" : "visible")
		fmt.printf("Window size: %dx%d\n", size.width, size.height)
		fmt.printf("Pixel size: %dx%d\n", size.pixel_width, size.pixel_height)
		fmt.printf("Surface source: %s\n", sdl_surface_source_kind_label(surface_descriptor.kind))
	}
	return 0
}

run_wgpu_surface_check :: proc(args: []string, emit_output: bool) -> int {
	root := "."
	hidden := true
	root_seen := false
	for arg in args {
		switch arg {
		case "--hidden":
			hidden = true
		case "--visible":
			hidden = false
		case:
			if len(arg) > 0 && arg[0] == '-' {
				if emit_output {
					fmt.eprintf("unknown argument: %s\n", arg)
				}
				return 1
			}
			if root_seen {
				if emit_output {
					fmt.eprintf("unexpected argument: %s\n", arg)
				}
				return 1
			}
			root = arg
			root_seen = true
		}
	}

	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		if emit_output {
			fmt.eprintf("wgpu-native library not found under %s\n", root)
			fmt.eprintf("Set %s to an explicit library path or run mise stage-odin-wgpu-native.\n", WGPU_OFFSCREEN_LIBRARY_ENV)
		}
		return 1
	}
	defer delete(path)

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !loaded_ok {
		if emit_output {
			fmt.eprintf("wgpu-native library failed to load: %s\n", missing)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	init_err := sdl_video_init()
	if init_err != .None {
		if emit_output {
			fmt.eprintf("wgpu surface check failed: %s\n", sdl_window_error_message(init_err))
		}
		return 1
	}
	defer sdl_video_quit()

	window, window_err := sdl_window_create(sdl_window_default_options(hidden))
	if window_err != .None {
		if emit_output {
			fmt.eprintf("wgpu surface check failed: %s\n", sdl_window_error_message(window_err))
		}
		return 1
	}
	defer sdl_window_destroy(&window)

	size, size_err := sdl_window_get_size(window.window)
	if size_err != .None {
		if emit_output {
			fmt.eprintf("wgpu surface size check failed: %s\n", sdl_window_error_message(size_err))
		}
		return 1
	}

	surface_descriptor := Sdl_WGPU_Surface_Descriptor{}
	surface_err := sdl_window_init_surface_descriptor(&surface_descriptor, window.window)
	defer sdl_wgpu_surface_descriptor_deinit(&surface_descriptor)
	if surface_err != .None {
		if emit_output {
			fmt.eprintf("wgpu surface descriptor check failed: %s\n", sdl_window_error_message(surface_err))
		}
		return 1
	}

	report, wgpu_error, present_ok := wgpu_present_surface_clear(
		loaded.procs,
		&surface_descriptor.descriptor,
		u32(size.pixel_width),
		u32(size.pixel_height),
	)
	if !present_ok {
		if emit_output {
			fmt.eprintf("wgpu surface presentation failed: %s\n", wgpu_error)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	if emit_output {
		fmt.printf("wgpu-native surface presentation OK: %s\n", path)
		fmt.printf("SDL window: %s\n", hidden ? "hidden" : "visible")
		fmt.printf("Window size: %dx%d\n", size.width, size.height)
		fmt.printf("Pixel size: %dx%d\n", size.pixel_width, size.pixel_height)
		fmt.printf("Surface source: %s\n", sdl_surface_source_kind_label(surface_descriptor.kind))
		fmt.printf("Surface frame: %dx%d format=0x%x present_mode=0x%x alpha_mode=0x%x\n", report.width, report.height, u32(report.format), u32(report.present_mode), u32(report.alpha_mode))
	}
	return 0
}

run_wgpu_check :: proc(args: []string, emit_output: bool) -> int {
	root := "."
	if len(args) > 1 {
		if emit_output {
			fmt.eprintln("wgpu-check expects at most one root path")
		}
		return 1
	}
	if len(args) == 1 {
		root = args[0]
	}

	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		if emit_output {
			fmt.eprintf("wgpu-native library not found under %s\n", root)
			fmt.eprintf("Set %s to an explicit library path or run mise stage-odin-wgpu-native.\n", WGPU_OFFSCREEN_LIBRARY_ENV)
		}
		return 1
	}
	defer delete(path)

	loaded, missing, ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !ok {
		if emit_output {
			fmt.eprintf("wgpu-native library failed to load: %s\n", missing)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	smoke_error, smoke_ok := wgpu_smoke_offscreen_triangle_readback(loaded.procs)
	if !smoke_ok {
		if emit_output {
			fmt.eprintf("wgpu-native offscreen smoke failed: %s\n", smoke_error)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	if emit_output {
		fmt.printf("wgpu-native offscreen pipeline OK: %s\n", path)
	}
	return 0
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
			print_project_check_error(result, options.target_path, options.format)
		}
		return 1
	}

	simulation := run_script_simulation(&result, options.frames, options.delta_seconds)
	if !simulation.ok {
		result.diagnostic = simulation.diagnostic
		result.err = .Invalid_Script
		if emit_output {
			print_project_check_error(result, options.target_path, options.format)
		}
		return 1
	}

	if emit_output {
		print_step_result(result, options, simulation.completed_frames)
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
			print_project_check_error(result, options.target_path, options.format)
		}
		return 1
	}

	update_start := time.tick_now()
	simulation := run_script_simulation(&result, options.frames, options.delta_seconds)
	update_ns := time.duration_nanoseconds(time.tick_since(update_start))
	if !simulation.ok {
		result.diagnostic = simulation.diagnostic
		result.err = .Invalid_Script
		if emit_output {
			print_project_check_error(result, options.target_path, options.format)
		}
		return 1
	}

	if emit_output {
		print_bench_result(result, options, startup_ns, update_ns, simulation.completed_frames)
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

	live, live_err := live_project_init(options.target_path)
	defer live_project_free(&live)
	if live_err != .None {
		if emit_output {
			print_project_check_error(live.check, options.target_path, .Text)
		}
		return 1
	}

	completed_frames := 0
	run_report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&run_report)
	window_result := Sdl_Run_Loop_Result{}
	if run_options_use_wgpu_sdl_window_loop(options) {
		simulation := Simulation_Run_Result{}
		window_error: string
		window_ok: bool
		window_result, simulation, window_error, window_ok = sdl_run_live_project_wgpu_loop(&live, options.target_path, options.max_frames, false, options.editor, emit_output, &run_report)
		if !window_ok {
			if emit_output {
				fmt.eprintf("run window loop failed: %s\n", window_error)
			}
			return 1
		}
		if !simulation.ok {
			live.check.diagnostic = simulation.diagnostic
			live.check.err = .Invalid_Script
			if emit_output {
				print_project_check_error(live.check, options.target_path, .Text)
			}
			return 1
		}
		completed_frames = simulation.completed_frames
	} else if run_options_use_sdl_window_loop(options) {
		simulation := Simulation_Run_Result{}
		window_error: string
		window_ok: bool
		window_result, simulation, window_error, window_ok = sdl_run_live_project_loop(&live, options.max_frames, false, options.editor, emit_output, &run_report)
		if !window_ok {
			if emit_output {
				fmt.eprintf("run window loop failed: %s\n", window_error)
			}
			return 1
		}
		if !simulation.ok {
			live.check.diagnostic = simulation.diagnostic
			live.check.err = .Invalid_Script
			if emit_output {
				print_project_check_error(live.check, options.target_path, .Text)
			}
			return 1
		}
		completed_frames = simulation.completed_frames
	} else if options.max_frames > 0 {
		simulation := live_project_run_frames_with_report(&live, options.max_frames, SDL_RUN_LOOP_FIXED_DELTA_SECONDS, nil, nil, &run_report)
		if !simulation.ok {
			live.check.diagnostic = simulation.diagnostic
			live.check.err = .Invalid_Script
			if emit_output {
				print_project_check_error(live.check, options.target_path, .Text)
			}
			return 1
		}
		completed_frames = simulation.completed_frames
	}

	render_result := Run_Render_Result{}
	if options.backend == .Software && window_result.presented {
		render_result.presented = true
		render_result.surface_width = window_result.surface_width
		render_result.surface_height = window_result.surface_height
		render_result.renderable_count = window_result.renderable_count
	}
	if options.backend == .WebGPU {
		_, extract_err := render_extract_scene(live.check.scene.world)
		if extract_err != .None {
			if emit_output {
				fmt.eprintln("run render failed: invalid scene render data")
			}
			return 1
		}
		if options.hidden {
			surface_report, surface_error, surface_ok := run_present_hidden_wgpu_surface(live.check.scene.world, options.target_path, options.editor)
			if !surface_ok {
				if emit_output {
					fmt.eprintf("run surface presentation failed: %s\n", surface_error)
				}
				return 1
			}
			render_result.presented = true
			render_result.surface_width = int(surface_report.width)
			render_result.surface_height = int(surface_report.height)
			render_result.renderable_count = surface_report.renderable_count + surface_report.overlay_count
		} else if window_result.presented {
			render_result.presented = true
			render_result.surface_width = window_result.surface_width
			render_result.surface_height = window_result.surface_height
			render_result.renderable_count = window_result.renderable_count
		}

		render_options := Render_Options{
			target_path = options.target_path,
			output_path = options.render_output_path,
			frames = options.max_frames,
			width = options.render_width,
			height = options.render_height,
			pixel_scale = options.render_pixel_scale,
			backend = options.backend,
			editor = options.editor,
		}
		_, image_err := render_write_scene_image(live.check.scene.world, render_options, false)
		if image_err != .None {
			if emit_output {
				fmt.eprintf("run render failed: %s\n", render_image_error_message(image_err))
			}
			return 1
		}
		metadata_err := render_write_artifact_metadata(render_options.output_path, render_options)
		if metadata_err != .None {
			if emit_output {
				fmt.eprintf("run render metadata failed: %s\n", render_image_error_message(metadata_err))
			}
			return 1
		}
		render_result.rendered = true
		render_result.output_path = render_options.output_path
		render_result.width = render_options.width
		render_result.height = render_options.height
		render_result.pixel_scale = render_options.pixel_scale
	}

	if emit_output {
		print_run_result(live.check, options, completed_frames, run_report, render_result, window_result)
	}
	return 0
}

run_render :: proc(args: []string, emit_output: bool, render_test: bool) -> int {
	default_output := DEFAULT_RENDER_OUTPUT
	command_name := "Render"
	error_name := "render"
	if render_test {
		default_output = DEFAULT_RENDER_TEST_OUTPUT
		command_name = "Render test"
		error_name = "render-test"
	}
	options, options_ok := parse_render_options(args, default_output, emit_output)
	if !options_ok {
		return 1
	}
	result := check_project(options.target_path)
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_project_check_error(result, options.target_path, .Text)
		}
		return 1
	}

	if options.selected_entity_id != "" {
		if _, found := runtime_world_find_entity_by_id(result.scene.world, options.selected_entity_id); !found {
			if emit_output {
				fmt.eprintf("%s selected entity not found: %s\n", error_name, options.selected_entity_id)
			}
			return 1
		}
	}

	update_frames := 0
	if options.frames > 1 {
		update_frames = options.frames - 1
	}
	simulation := run_script_simulation(&result, update_frames, 1.0 / 60.0)
	if !simulation.ok {
		result.diagnostic = simulation.diagnostic
		result.err = .Invalid_Script
		if emit_output {
			print_project_check_error(result, options.target_path, .Text)
		}
		return 1
	}

	_, extract_err := render_extract_scene(result.scene.world)
	if extract_err != .None {
		if emit_output {
			fmt.eprintln("render failed: invalid scene render data")
		}
		return 1
	}
	verification, image_err := render_write_scene_image(result.scene.world, options, render_test)
	if image_err != .None {
		if emit_output {
			fmt.eprintf("%s failed: %s\n", error_name, render_image_error_message(image_err))
		}
		return 1
	}
	metadata_err := render_write_artifact_metadata(options.output_path, options)
	if metadata_err != .None {
		if emit_output {
			fmt.eprintf("%s metadata failed: %s\n", error_name, render_image_error_message(metadata_err))
		}
		return 1
	}

	if emit_output {
		if render_test {
			print_render_test_result(result, options, options.frames, verification)
		} else {
			print_render_result(result, options, options.frames, command_name)
		}
	}
	return 0
}

run_visual_test :: proc(args: []string, emit_output: bool) -> int {
	options, options_ok := parse_visual_test_options(args, emit_output)
	if !options_ok {
		return 1
	}

	result := check_project(options.render.target_path)
	defer free_check_result(result)
	if result.err != .None {
		if emit_output {
			print_project_check_error(result, options.render.target_path, .Text)
		}
		return 1
	}

	if options.render.selected_entity_id != "" {
		if _, found := runtime_world_find_entity_by_id(result.scene.world, options.render.selected_entity_id); !found {
			if emit_output {
				fmt.eprintf("visual-test selected entity not found: %s\n", options.render.selected_entity_id)
			}
			return 1
		}
	}
	if !options.update {
		if same_resolved_path(options.expected_path, options.render.output_path) {
			if emit_output {
				fmt.eprintf("visual-test actual output must differ from expected path; use --update to refresh %s\n", options.expected_path)
			}
			return 1
		}
		if !os.exists(options.expected_path) {
			if emit_output {
				fmt.eprintf("visual-test expected image not found: %s\n", options.expected_path)
			}
			return 1
		}
	}

	update_frames := 0
	if options.render.frames > 1 {
		update_frames = options.render.frames - 1
	}
	simulation := run_script_simulation(&result, update_frames, 1.0 / 60.0)
	if !simulation.ok {
		result.diagnostic = simulation.diagnostic
		result.err = .Invalid_Script
		if emit_output {
			print_project_check_error(result, options.render.target_path, .Text)
		}
		return 1
	}

	_, extract_err := render_extract_scene(result.scene.world)
	if extract_err != .None {
		if emit_output {
			fmt.eprintln("visual-test failed: invalid scene render data")
		}
		return 1
	}

	render_options := options.render
	if options.update {
		render_options.output_path = options.expected_path
	}
	_, image_err := render_write_scene_image(result.scene.world, render_options, false)
	if image_err != .None {
		if emit_output {
			fmt.eprintf("visual-test render failed: %s\n", render_image_error_message(image_err))
		}
		return 1
	}
	metadata_err := render_write_artifact_metadata(render_options.output_path, render_options)
	if metadata_err != .None {
		if emit_output {
			fmt.eprintf("visual-test metadata failed: %s\n", render_image_error_message(metadata_err))
		}
		return 1
	}

	comparison := Render_Image_Comparison{}
	comparison_ok := true
	if !options.update {
		compare_err: Render_Image_Error
		comparison, compare_err = render_compare_image_files(options.expected_path, options.render.output_path)
		if compare_err != .None {
			if emit_output {
				fmt.eprintf("visual-test comparison failed: %s\n", render_image_error_message(compare_err))
			}
			return 1
		}
		comparison_ok = render_comparison_passed(comparison)
	}

	if emit_output {
		print_visual_test_result(result, options, options.render.frames, comparison, comparison_ok)
		if !options.update && !comparison_ok {
			fmt.eprintf(
				"visual-test exceeded tolerances: max delta <= %d, mean delta <= %.3f, changed pixels <= %.3f%%\n",
				DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS.max_channel_delta,
				DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS.max_mean_channel_delta,
				DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS.max_changed_pixel_ratio * 100.0,
			)
		}
	}
	if !comparison_ok {
		return 1
	}
	return 0
}

run_wgpu_render_test :: proc(args: []string, emit_output: bool) -> int {
	root := "."
	output_path := DEFAULT_WGPU_RENDER_TEST_OUTPUT
	if len(args) > 2 {
		if emit_output {
			fmt.eprintln("wgpu-render-test expects at most a root path and output image path")
		}
		return 1
	}
	if len(args) >= 1 {
		root = args[0]
	}
	if len(args) == 2 {
		output_path = args[1]
	}

	format, format_ok := render_image_format_from_path(output_path)
	if !format_ok {
		if emit_output {
			fmt.eprintf("unsupported image output: %s\n", output_path)
		}
		return 1
	}

	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		if emit_output {
			fmt.eprintf("wgpu-native library not found under %s\n", root)
			fmt.eprintf("Set %s to an explicit library path or run mise stage-odin-wgpu-native.\n", WGPU_OFFSCREEN_LIBRARY_ENV)
		}
		return 1
	}
	defer delete(path)

	loaded, missing, ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !ok {
		if emit_output {
			fmt.eprintf("wgpu-native library failed to load: %s\n", missing)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	image, render_error, render_ok := wgpu_render_offscreen_triangle_image(
		loaded.procs,
		DEFAULT_WGPU_RENDER_TEST_WIDTH,
		DEFAULT_WGPU_RENDER_TEST_HEIGHT,
	)
	defer render_image_free(&image)
	if !render_ok {
		if emit_output {
			fmt.eprintf("wgpu-native offscreen render failed: %s\n", render_error)
			fmt.eprintf("Path: %s\n", path)
		}
		return 1
	}

	write_error := render_write_image_file(image, output_path, format)
	if write_error != .None {
		if emit_output {
			fmt.eprintf("failed to write WebGPU render artifact %s: %s\n", output_path, render_image_error_message(write_error))
		}
		return 1
	}

	if emit_output {
		fmt.printf("wgpu-native offscreen render OK: %s\n", output_path)
		fmt.printf("Path: %s\n", path)
	}
	return 0
}

run_check :: proc(args: []string, emit_output: bool) -> int {
	target_path := "."
	format: Check_Output_Format = .Text

	i := 0
	for i < len(args) {
		arg := args[i]
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
			print_project_check_error(result, target_path, format)
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

Simulation_Run_Result :: struct {
	ok:               bool,
	completed_frames: int,
	diagnostic:       Script_Diagnostic,
	editor_state:     Editor_Test_Input_State,
}

run_script_simulation :: proc(result: ^Project_Check_Result, frames: int, delta_seconds: f32) -> Simulation_Run_Result {
	return run_script_simulation_with_input(result, frames, delta_seconds, nil)
}

run_script_simulation_with_input :: proc(result: ^Project_Check_Result, frames: int, delta_seconds: f32, input_frames: []Step_Input_Frame) -> Simulation_Run_Result {
	startup := script_program_run_schedule(&result.script_program, &result.registry, &result.scene.world, result.startup_schedule, 0)
	if !startup.ok {
		return Simulation_Run_Result{ok = false, diagnostic = startup.diagnostic}
	}
	completed_frames := 0
	editor_input_state := Editor_Test_Input_State{}
	defer editor_test_input_state_free(&editor_input_state)
	for completed_frames < frames {
		if len(input_frames) > 0 {
			frame_input := step_input_for_frame(input_frames, completed_frames + 1)
			route_editor_test_input(&editor_input_state, result.registry, &result.scene.world, &frame_input)
			input_err := write_frame_input(&result.scene.world, frame_input)
			if input_err != .None {
				return Simulation_Run_Result{
					ok = false,
					completed_frames = completed_frames,
					diagnostic = script_runtime_diagnostic("", "", 0, runtime_error_label(input_err)),
					editor_state = editor_input_state,
				}
			}
			route_err := route_test_frame_input(&result.scene.world)
			if route_err != .None {
				return Simulation_Run_Result{
					ok = false,
					completed_frames = completed_frames,
					diagnostic = script_runtime_diagnostic("", "", 0, runtime_error_label(route_err)),
					editor_state = editor_input_state,
				}
			}
			if !editor_test_should_run_update(editor_input_state) {
				completed_frames += 1
				continue
			}
		}
		update := script_program_run_schedule(&result.script_program, &result.registry, &result.scene.world, result.update_schedule, delta_seconds)
		if !update.ok {
			return Simulation_Run_Result{ok = false, completed_frames = completed_frames, diagnostic = update.diagnostic, editor_state = editor_input_state}
		}
		completed_frames += 1
	}
	return Simulation_Run_Result{ok = true, completed_frames = completed_frames, editor_state = editor_input_state}
}

print_step_result :: proc(result: Project_Check_Result, options: Simulation_Options, completed_frames: int) {
	switch options.format {
	case .Text:
		fmt.printf("Step OK: %s\n", result.project.name)
		fmt.printf("Scene: %s\n", result.scene.name)
		fmt.printf("Frames: %d/%d, dt: %g\n", completed_frames, options.frames, options.delta_seconds)
		fmt.printf("Entities: %d, components: %d, renderable cubes: %d\n", result.scene.entity_count, result.scene.component_instance_count, result.scene.renderable_cube_count)
		fmt.printf("Update batches: %d, systems: %d\n", runtime_system_schedule_batch_count(result.update_schedule), runtime_system_schedule_system_count(result.update_schedule))
		fmt.println("Execution: Odin Luau systems")
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
		fmt.printf(`"frames":%d,"completed_frames":%d,"dt":%g`, options.frames, completed_frames, options.delta_seconds)
		fmt.print(`}`)
		fmt.print(`,"schedule":`)
		print_schedule_summary_json(result)
		fmt.println(`,"execution":"odin_luau_systems"}`)
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
		fmt.println("Execution: Odin Luau systems")
		print_render_extract_text(result)
		fmt.printf("Renderer backend: %s\n", bench_renderer_backend_label())
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
		fmt.print(`,"execution":"odin_luau_systems","renderer_backend":"`)
		json_print(bench_renderer_backend_json_label(), false)
		fmt.println(`"}`)
	}
}

bench_renderer_backend_label :: proc() -> string {
	return "odin render extraction"
}

bench_renderer_backend_json_label :: proc() -> string {
	return "odin_render_extraction"
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

parse_non_negative_f32 :: proc(value: string) -> (f32, bool) {
	parsed, ok := strconv.parse_f32(value)
	if !ok || parsed < 0 || parsed != parsed || parsed > 3.4028234663852886e38 || parsed < -3.4028234663852886e38 {
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
		if result.native_artifact != "" {
			fmt.printf("Native artifact: %s\n", result.native_artifact)
		}
		fmt.printf("SDL3 bundled: %v\n", result.sdl3_bundled)
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
		fmt.print(`","native_artifact":`)
		if result.native_artifact == "" {
			fmt.print(`null`)
		} else {
			fmt.print(`"`)
			json_print(result.native_artifact, false)
			fmt.print(`"`)
		}
		if result.sdl3_bundled {
			fmt.print(`,"sdl3_bundled":true`)
		} else {
			fmt.print(`,"sdl3_bundled":false`)
		}
		fmt.print(`,"sdl3_warning":`)
		if result.sdl3_warning == "" {
			fmt.println(`null}`)
		} else {
			fmt.print(`"`)
			json_print(result.sdl3_warning, false)
			fmt.println(`"}`)
		}
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

print_project_check_error :: proc(result: Project_Check_Result, target_path: string, format: Check_Output_Format) {
	if !script_diagnostic_present(result.diagnostic) {
		print_check_error(result.err, target_path, format)
		return
	}

	diagnostic := result.diagnostic
	switch format {
	case .Text:
		fmt.eprintf("Project invalid: %s: %s", target_path, script_diagnostic_stage_label(diagnostic.stage))
		if diagnostic.path != "" {
			fmt.eprintf(" in %s", diagnostic.path)
		}
		if diagnostic.system_id != "" {
			fmt.eprintf(" system %s", diagnostic.system_id)
		}
		if diagnostic.has_start {
			fmt.eprintf(":%d", diagnostic.start.line)
			if diagnostic.start.has_column {
				fmt.eprintf(":%d", diagnostic.start.column)
			}
		}
		fmt.eprintf(": %s\n", diagnostic.message)
	case .JSON:
		fmt.eprint(`{"ok":false,"diagnostic":`)
		print_script_diagnostic_json(diagnostic, target_path, true)
		fmt.eprintln(`}`)
	}
}

render_image_error_message :: proc(err: Render_Image_Error) -> string {
	switch err {
	case .None:
		return "none"
	case .Invalid_Output:
		return "invalid output"
	case .Unsupported_Format:
		return "unsupported image format"
	case .Out_Of_Memory:
		return "out of memory"
	case .Io_Error:
		return "io error"
	case .Backend_Unavailable:
		return "render backend unavailable"
	case .Backend_Render_Failed:
		return "render backend failed"
	case .Invalid_Image:
		return "invalid image"
	case .Image_Size_Mismatch:
		return "image size mismatch"
	case .Missing_Foreground:
		return "missing foreground pixels"
	case .Missing_Visible_Components:
		return "missing visible components"
	case .Missing_Color_Groups:
		return "missing color groups"
	}
	return "unknown render image error"
}

print_script_diagnostic_json :: proc(diagnostic: Script_Diagnostic, root_path: string, stderr: bool) {
	print_json_fragment(`{"stage":"`, stderr)
	json_print(script_diagnostic_stage_name(diagnostic.stage), stderr)
	print_json_fragment(`","root":"`, stderr)
	json_print(root_path, stderr)
	print_json_fragment(`"`, stderr)
	if diagnostic.path != "" {
		print_json_fragment(`,"path":"`, stderr)
		json_print(diagnostic.path, stderr)
		print_json_fragment(`"`, stderr)
	}
	if diagnostic.system_id != "" {
		print_json_fragment(`,"system_id":"`, stderr)
		json_print(diagnostic.system_id, stderr)
		print_json_fragment(`"`, stderr)
	}
	if diagnostic.has_start {
		fmt_print_json_position(diagnostic.start, "start", stderr)
	}
	print_json_fragment(`,"message":"`, stderr)
	json_print(diagnostic.message, stderr)
	print_json_fragment(`"}`, stderr)
}

fmt_print_json_position :: proc(position: Script_Diagnostic_Position, key: string, stderr: bool) {
	print_json_fragment(`,"`, stderr)
	json_print(key, stderr)
	print_json_fragment(`":{"line":`, stderr)
	if stderr {
		fmt.eprintf(`%d`, position.line)
	} else {
		fmt.printf(`%d`, position.line)
	}
	if position.has_column {
		print_json_fragment(`,"column":`, stderr)
		if stderr {
			fmt.eprintf(`%d`, position.column)
		} else {
			fmt.printf(`%d`, position.column)
		}
	}
	print_json_fragment(`}`, stderr)
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
