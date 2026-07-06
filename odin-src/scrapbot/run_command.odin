package main

import "core:fmt"
import "core:strings"

Run_Options :: struct {
	target_path: string,
	max_frames:  int,
	editor:      bool,
	hidden:      bool,
}

parse_run_options :: proc(args: []string, emit_output: bool) -> (Run_Options, bool) {
	options := Run_Options{
		target_path = ".",
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
	return options, true
}

print_run_result :: proc(result: Project_Check_Result, options: Run_Options, completed_frames: int, report: Live_Project_Run_Report) {
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
	fmt.println("Renderer backend: pending Odin wgpu-native binding")
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
