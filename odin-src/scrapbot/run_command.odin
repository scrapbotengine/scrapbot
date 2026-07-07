package main

import "core:fmt"
import "core:strings"

Run_Options :: struct {
	target_path:            string,
	max_frames:             int,
	editor:                 bool,
	hidden:                 bool,
	backend:                Render_Backend,
	render_output_path:     string,
	render_output_explicit: bool,
	render_width:           int,
	render_height:          int,
	render_pixel_scale:     f32,
}

Run_Render_Result :: struct {
	rendered:         bool,
	output_path:      string,
	width:            int,
	height:           int,
	pixel_scale:      f32,
	presented:        bool,
	surface_width:    int,
	surface_height:   int,
	renderable_count: int,
}

parse_run_options :: proc(args: []string, emit_output: bool) -> (Run_Options, bool) {
	options := Run_Options{
		target_path = ".",
		render_output_path = DEFAULT_RUN_RENDER_OUTPUT,
		render_width = DEFAULT_RENDER_WIDTH,
		render_height = DEFAULT_RENDER_HEIGHT,
		render_pixel_scale = DEFAULT_RENDER_PIXEL_SCALE,
	}

	i := 0
	target_seen := false
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
			options.max_frames = frames
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
			options.max_frames = frames
			i += 2
			continue
		}
		if arg == "--editor" {
			options.editor = true
			i += 1
			continue
		}
		if arg == "--hidden" {
			options.hidden = true
			i += 1
			continue
		}
		if strings.has_prefix(arg, "--backend=") {
			backend, ok := parse_render_backend(arg[len("--backend="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --backend: %s\n", arg[len("--backend="):])
				}
				return options, false
			}
			options.backend = backend
			i += 1
			continue
		}
		if arg == "--backend" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --backend")
				}
				return options, false
			}
			backend, ok := parse_render_backend(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --backend: %s\n", args[i + 1])
				}
				return options, false
			}
			options.backend = backend
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--render-output=") {
			options.render_output_path = arg[len("--render-output="):]
			options.render_output_explicit = true
			i += 1
			continue
		}
		if arg == "--render-output" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --render-output")
				}
				return options, false
			}
			options.render_output_path = args[i + 1]
			options.render_output_explicit = true
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--render-width=") {
			width, ok := parse_positive_int(arg[len("--render-width="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-width: %s\n", arg[len("--render-width="):])
				}
				return options, false
			}
			options.render_width = width
			i += 1
			continue
		}
		if arg == "--render-width" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --render-width")
				}
				return options, false
			}
			width, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-width: %s\n", args[i + 1])
				}
				return options, false
			}
			options.render_width = width
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--render-height=") {
			height, ok := parse_positive_int(arg[len("--render-height="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-height: %s\n", arg[len("--render-height="):])
				}
				return options, false
			}
			options.render_height = height
			i += 1
			continue
		}
		if arg == "--render-height" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --render-height")
				}
				return options, false
			}
			height, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-height: %s\n", args[i + 1])
				}
				return options, false
			}
			options.render_height = height
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--render-pixel-scale=") {
			pixel_scale, ok := parse_positive_f32(arg[len("--render-pixel-scale="):])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-pixel-scale: %s\n", arg[len("--render-pixel-scale="):])
				}
				return options, false
			}
			options.render_pixel_scale = pixel_scale
			i += 1
			continue
		}
		if arg == "--render-pixel-scale" {
			if i + 1 >= len(args) {
				if emit_output {
					fmt.eprintln("missing value for --render-pixel-scale")
				}
				return options, false
			}
			pixel_scale, ok := parse_positive_f32(args[i + 1])
			if !ok {
				if emit_output {
					fmt.eprintf("invalid --render-pixel-scale: %s\n", args[i + 1])
				}
				return options, false
			}
			options.render_pixel_scale = pixel_scale
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output {
				fmt.eprintf("unknown argument: %s\n", arg)
			}
			return options, false
		}
		if target_seen {
			if emit_output {
				fmt.eprintf("unexpected argument: %s\n", arg)
			}
			return options, false
		}
		options.target_path = arg
		target_seen = true
		i += 1
	}

	if options.hidden && options.max_frames == 0 {
		if emit_output {
			fmt.eprintln("--hidden requires --frames")
		}
		return options, false
	}
	if options.backend == .WebGPU && options.editor {
		if emit_output {
			fmt.eprintln("run failed: WebGPU editor chrome is not ported yet")
		}
		return options, false
	}
	if options.backend == .WebGPU && !options.hidden {
		if emit_output {
			fmt.eprintln("run failed: visible WebGPU presentation is not ported yet; use --hidden --frames")
		}
		return options, false
	}
	if options.backend == .WebGPU && options.max_frames == 0 {
		if emit_output {
			fmt.eprintln("run failed: WebGPU run rendering requires --frames")
		}
		return options, false
	}
	if options.render_output_explicit && options.backend != .WebGPU {
		if emit_output {
			fmt.eprintln("--render-output requires --backend wgpu")
		}
		return options, false
	}
	return options, true
}

print_run_result :: proc(result: Project_Check_Result, options: Run_Options, completed_frames: int, report: Live_Project_Run_Report, render_result: Run_Render_Result) {
	fmt.printf("Loaded project %s\n", result.project.name)
	fmt.printf("Selected scene: %s\n", result.project.default_scene)
	fmt.printf("Scene entities: %d\n", result.scene.entity_count)
	fmt.printf(
		"Scripts: %d, update batches: %d, update systems: %d\n",
		len(result.project.scripts),
		runtime_system_schedule_batch_count(result.update_schedule),
		runtime_system_schedule_system_count(result.update_schedule),
	)
	for event in report.reloads {
		print_run_reload_event(event)
	}
	if options.max_frames > 0 {
		fmt.printf("Frames: %d/%d\n", completed_frames, options.max_frames)
	} else {
		fmt.println("Frames: unbounded window loop pending Odin renderer")
	}
	if options.hidden {
		fmt.println("Window: hidden")
	} else {
		fmt.println("Window: visible presentation pending Odin renderer")
	}
	if options.editor {
		fmt.println("Editor: requested, pending Odin editor shell")
	}
	print_render_extract_text(result)
	if options.max_frames > 0 {
		fmt.println("Execution: Odin Luau systems")
	} else {
		fmt.println("Execution: pending unbounded Odin window loop")
	}
	if render_result.rendered {
		fmt.printf("Rendered frame: %s\n", render_result.output_path)
		fmt.printf("Render viewport: %dx%d @%gx\n", render_result.width, render_result.height, render_result.pixel_scale)
	}
	if render_result.presented {
		fmt.printf("Presented surface frame: %dx%d, renderables: %d\n", render_result.surface_width, render_result.surface_height, render_result.renderable_count)
	}
	fmt.printf("Renderer backend: %s\n", render_backend_label(options.backend))
}

print_run_reload_event :: proc(event: Live_Reload_Event) {
	info := event.info
	fmt.printf(
		"Reloaded %s%s%s%s at frame %d: %d entities, %d systems\n",
		info.project_reloaded ? "project" : "",
		info.scene_reloaded ? (info.project_reloaded ? " and scene" : "scene") : "",
		info.scripts_reloaded ? ((info.project_reloaded || info.scene_reloaded) ? " and scripts" : "scripts") : "",
		info.native_reloaded ? ((info.project_reloaded || info.scene_reloaded || info.scripts_reloaded) ? " and native" : "native") : "",
		event.frame,
		info.entity_count,
		info.system_count,
	)
}

run_present_hidden_wgpu_surface :: proc(world: Runtime_World, target_path: string) -> (WGPU_Surface_Presentation_Report, string, bool) {
	path, found := wgpu_find_default_offscreen_library(target_path)
	if !found && target_path != "." {
		path, found = wgpu_find_default_offscreen_library(".")
	}
	if !found {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}
	defer delete(path)

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !loaded_ok {
		if missing == "" {
			missing = WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR
		}
		return WGPU_Surface_Presentation_Report{}, missing, false
	}

	init_err := sdl_video_init()
	if init_err != .None {
		return WGPU_Surface_Presentation_Report{}, sdl_window_error_message(init_err), false
	}
	defer sdl_video_quit()

	window, window_err := sdl_window_create(sdl_window_default_options(true))
	defer sdl_window_destroy(&window)
	if window_err != .None {
		return WGPU_Surface_Presentation_Report{}, sdl_window_error_message(window_err), false
	}

	size, size_err := sdl_window_get_size(window.window)
	if size_err != .None {
		return WGPU_Surface_Presentation_Report{}, sdl_window_error_message(size_err), false
	}
	if size.pixel_width <= 0 || size.pixel_height <= 0 {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	surface_descriptor := Sdl_WGPU_Surface_Descriptor{}
	surface_err := sdl_window_init_surface_descriptor(&surface_descriptor, window.window)
	defer sdl_wgpu_surface_descriptor_deinit(&surface_descriptor)
	if surface_err != .None {
		return WGPU_Surface_Presentation_Report{}, sdl_window_error_message(surface_err), false
	}

	return wgpu_present_surface_scene(
		loaded.procs,
		&surface_descriptor.descriptor,
		world,
		u32(size.pixel_width),
		u32(size.pixel_height),
	)
}
