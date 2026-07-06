package main

import "core:fmt"
import "core:strings"

DEFAULT_RENDER_WIDTH :: 640
DEFAULT_RENDER_HEIGHT :: 480
DEFAULT_RENDER_PIXEL_SCALE :: f32(1.0)
DEFAULT_RENDER_FRAMES :: 1
DEFAULT_RENDER_OUTPUT :: "odin-out/scrapbot-render.png"
DEFAULT_RENDER_TEST_OUTPUT :: "odin-out/scrapbot-render-test.png"
RENDER_BACKEND_PENDING :: "pending_odin_wgpu_native_binding"

Render_Options :: struct {
	target_path:        string,
	output_path:        string,
	frames:             int,
	width:              int,
	height:             int,
	pixel_scale:        f32,
	editor:             bool,
	selected_entity_id: string,
}

parse_render_options :: proc(args: []string, default_output: string, emit_output: bool) -> (Render_Options, bool) {
	options := Render_Options{
		target_path = ".",
		output_path = default_output,
		frames = DEFAULT_RENDER_FRAMES,
		width = DEFAULT_RENDER_WIDTH,
		height = DEFAULT_RENDER_HEIGHT,
		pixel_scale = DEFAULT_RENDER_PIXEL_SCALE,
	}
	positionals := 0
	select_seen := false
	i := 0
	for i < len(args) {
		arg := args[i]
		if strings.has_prefix(arg, "--frames=") {
			frames, ok := parse_positive_int(arg[len("--frames="):])
			if !ok {
				if emit_output do fmt.eprintf("invalid --frames: %s\n", arg[len("--frames="):])
				return options, false
			}
			options.frames = frames
			i += 1
			continue
		}
		if arg == "--frames" {
			if i + 1 >= len(args) {
				if emit_output do fmt.eprintln("missing value for --frames")
				return options, false
			}
			frames, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output do fmt.eprintf("invalid --frames: %s\n", args[i + 1])
				return options, false
			}
			options.frames = frames
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--width=") {
			width, ok := parse_positive_int(arg[len("--width="):])
			if !ok {
				if emit_output do fmt.eprintf("invalid --width: %s\n", arg[len("--width="):])
				return options, false
			}
			options.width = width
			i += 1
			continue
		}
		if arg == "--width" {
			if i + 1 >= len(args) {
				if emit_output do fmt.eprintln("missing value for --width")
				return options, false
			}
			width, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output do fmt.eprintf("invalid --width: %s\n", args[i + 1])
				return options, false
			}
			options.width = width
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--height=") {
			height, ok := parse_positive_int(arg[len("--height="):])
			if !ok {
				if emit_output do fmt.eprintf("invalid --height: %s\n", arg[len("--height="):])
				return options, false
			}
			options.height = height
			i += 1
			continue
		}
		if arg == "--height" {
			if i + 1 >= len(args) {
				if emit_output do fmt.eprintln("missing value for --height")
				return options, false
			}
			height, ok := parse_positive_int(args[i + 1])
			if !ok {
				if emit_output do fmt.eprintf("invalid --height: %s\n", args[i + 1])
				return options, false
			}
			options.height = height
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--pixel-scale=") {
			pixel_scale, ok := parse_positive_f32(arg[len("--pixel-scale="):])
			if !ok {
				if emit_output do fmt.eprintf("invalid --pixel-scale: %s\n", arg[len("--pixel-scale="):])
				return options, false
			}
			options.pixel_scale = pixel_scale
			i += 1
			continue
		}
		if arg == "--pixel-scale" {
			if i + 1 >= len(args) {
				if emit_output do fmt.eprintln("missing value for --pixel-scale")
				return options, false
			}
			pixel_scale, ok := parse_positive_f32(args[i + 1])
			if !ok {
				if emit_output do fmt.eprintf("invalid --pixel-scale: %s\n", args[i + 1])
				return options, false
			}
			options.pixel_scale = pixel_scale
			i += 2
			continue
		}
		if strings.has_prefix(arg, "--select=") {
			options.selected_entity_id = arg[len("--select="):]
			options.editor = true
			select_seen = true
			i += 1
			continue
		}
		if arg == "--select" {
			if i + 1 >= len(args) {
				if emit_output do fmt.eprintln("missing value for --select")
				return options, false
			}
			options.selected_entity_id = args[i + 1]
			options.editor = true
			select_seen = true
			i += 2
			continue
		}
		if arg == "--editor" {
			options.editor = true
			i += 1
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			if emit_output do fmt.eprintf("unknown argument: %s\n", arg)
			return options, false
		}
		if positionals == 0 {
			options.target_path = arg
		} else if positionals == 1 {
			options.output_path = arg
		} else {
			if emit_output do fmt.eprintf("unexpected argument: %s\n", arg)
			return options, false
		}
		positionals += 1
		i += 1
	}
	if select_seen && options.selected_entity_id == "" {
		if emit_output do fmt.eprintln("missing value for --select")
		return options, false
	}
	return options, true
}

print_render_result :: proc(result: Project_Check_Result, options: Render_Options, completed_frames: int, command_name: string) {
	fmt.printf("%s OK: %s\n", command_name, result.project.name)
	fmt.printf("Selected scene: %s\n", result.project.default_scene)
	fmt.printf("Output: %s\n", options.output_path)
	fmt.printf("Frames: %d/%d\n", completed_frames, options.frames)
	fmt.printf("Viewport: %dx%d @%gx\n", options.width, options.height, options.pixel_scale)
	if options.editor {
		fmt.println("Editor: requested, pending Odin editor shell")
	}
	if options.selected_entity_id != "" {
		fmt.printf("Selected entity: %s\n", options.selected_entity_id)
	}
	print_render_extract_text(result)
	fmt.printf("Renderer backend: %s\n", RENDER_BACKEND_PENDING)
}
