package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"

DEFAULT_RENDER_WIDTH :: 640
DEFAULT_RENDER_HEIGHT :: 480
DEFAULT_RENDER_PIXEL_SCALE :: f32(1.0)
DEFAULT_RENDER_FRAMES :: 1
DEFAULT_RENDER_OUTPUT :: "odin-out/scrapbot-render.png"
DEFAULT_RENDER_TEST_OUTPUT :: "odin-out/scrapbot-render-test.png"
DEFAULT_VISUAL_TEST_OUTPUT :: "odin-out/scrapbot-visual-test.png"
ODIN_SOFTWARE_RENDER_BACKEND :: "odin software offscreen placeholder; WebGPU binding pending"

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

Visual_Test_Options :: struct {
	render:        Render_Options,
	expected_path: string,
	update:        bool,
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

parse_visual_test_options :: proc(args: []string, emit_output: bool) -> (Visual_Test_Options, bool) {
	render_args: [dynamic]string
	defer delete(render_args)
	positionals: [dynamic]string
	defer delete(positionals)
	update := false

	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--update" {
			update = true
			i += 1
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			append(&render_args, arg)
			if render_option_requires_value(arg) {
				if i + 1 >= len(args) {
					if emit_output {
						fmt.eprintf("missing value for %s\n", arg)
					}
					return Visual_Test_Options{}, false
				}
				append(&render_args, args[i + 1])
				i += 2
				continue
			}
			i += 1
			continue
		}
		append(&positionals, arg)
		i += 1
	}

	if len(positionals) < 2 {
		if emit_output {
			fmt.eprintln("visual-test expects a project path and expected image path")
		}
		return Visual_Test_Options{}, false
	}
	if len(positionals) > 3 {
		if emit_output {
			fmt.eprintf("unexpected argument: %s\n", positionals[3])
		}
		return Visual_Test_Options{}, false
	}

	append(&render_args, positionals[0])
	if len(positionals) == 3 {
		append(&render_args, positionals[2])
	}
	render, render_ok := parse_render_options(render_args[:], DEFAULT_VISUAL_TEST_OUTPUT, emit_output)
	if !render_ok {
		return Visual_Test_Options{}, false
	}

	options := Visual_Test_Options{
		render = render,
		expected_path = positionals[1],
		update = update,
	}
	return options, true
}

render_option_requires_value :: proc(arg: string) -> bool {
	return arg == "--frames" || arg == "--width" || arg == "--height" || arg == "--pixel-scale" || arg == "--select"
}

same_resolved_path :: proc(left, right: string) -> bool {
	left_abs, left_err := filepath.abs(left)
	if left_err != nil {
		return left == right
	}
	defer delete(left_abs)
	right_abs, right_err := filepath.abs(right)
	if right_err != nil {
		return left == right
	}
	defer delete(right_abs)
	return paths_equal(left_abs, right_abs)
}

print_render_result :: proc(result: Project_Check_Result, options: Render_Options, completed_frames: int, command_name: string) {
	fmt.printf("%s OK: %s\n", command_name, result.project.name)
	fmt.printf("Selected scene: %s\n", result.project.default_scene)
	fmt.printf("Output: %s\n", options.output_path)
	fmt.printf("Frames: %d/%d\n", completed_frames, options.frames)
	fmt.printf("Viewport: %dx%d @%gx\n", options.width, options.height, options.pixel_scale)
	if options.editor {
		fmt.println("Editor: software chrome overlay")
	}
	if options.selected_entity_id != "" {
		fmt.printf("Selected entity: %s\n", options.selected_entity_id)
	}
	print_render_extract_text(result)
	fmt.printf("Renderer backend: %s\n", ODIN_SOFTWARE_RENDER_BACKEND)
}

print_render_test_result :: proc(result: Project_Check_Result, options: Render_Options, completed_frames: int, verification: Render_Image_Verification) {
	fmt.printf(
		"Render test OK: %s, %dx%d, foreground pixels: %d, visible components: %d, color groups: %d\n",
		result.project.name,
		options.width,
		options.height,
		verification.foreground_pixels,
		verification.visible_components,
		verification.color_groups,
	)
	fmt.printf("Output: %s\n", options.output_path)
	fmt.printf("Frames: %d/%d\n", completed_frames, options.frames)
	if options.editor {
		fmt.println("Editor: software chrome overlay")
	}
	if options.selected_entity_id != "" {
		fmt.printf("Selected entity: %s\n", options.selected_entity_id)
	}
	print_render_extract_text(result)
	fmt.printf("Renderer backend: %s\n", ODIN_SOFTWARE_RENDER_BACKEND)
}

print_visual_test_result :: proc(result: Project_Check_Result, options: Visual_Test_Options, completed_frames: int, comparison: Render_Image_Comparison, comparison_ok: bool) {
	if options.update {
		fmt.printf("Updated golden fixture: %s\n", options.expected_path)
	} else {
		status := comparison_ok ? "OK" : "FAILED"
		fmt.printf(
			"Visual test %s: %dx%d, max delta: %d, mean delta: %.3f, changed pixels: %d/%d (%.3f%%)\n",
			status,
			comparison.width,
			comparison.height,
			comparison.max_channel_delta,
			comparison.mean_channel_delta,
			comparison.changed_pixels,
			comparison.pixels,
			comparison.changed_pixel_ratio * 100.0,
		)
		fmt.printf("Expected: %s\n", options.expected_path)
		fmt.printf("Actual: %s\n", options.render.output_path)
	}
	fmt.printf("Selected scene: %s\n", result.project.default_scene)
	fmt.printf("Frames: %d/%d\n", completed_frames, options.render.frames)
	fmt.printf("Viewport: %dx%d @%gx\n", options.render.width, options.render.height, options.render.pixel_scale)
	if options.render.editor {
		fmt.println("Editor: software chrome overlay")
	}
	if options.render.selected_entity_id != "" {
		fmt.printf("Selected entity: %s\n", options.render.selected_entity_id)
	}
	print_render_extract_text(result)
	fmt.printf("Renderer backend: %s\n", ODIN_SOFTWARE_RENDER_BACKEND)
}
