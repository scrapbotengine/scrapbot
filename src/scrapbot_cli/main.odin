package main

import scrapbot "../scrapbot"
import diagnostic "../scrapbot/diagnostic"
import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"

PARSING_STYLE :: flags.Parsing_Style.Unix

Init_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to initialize."`,
	name: string `args:"pos=1" usage:"Project display name."`,
	json: bool `usage:"Emit one machine-readable JSON result."`,
}

Check_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to validate."`,
	json: bool `usage:"Emit one machine-readable JSON result."`,
}

Build_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to package."`,
	target: string `usage:"Build target. Defaults to the host target."`,
	json: bool `usage:"Emit one machine-readable JSON result."`,
}

Run_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to run."`,
	backend: string `usage:"Renderer backend: null or wgpu. Defaults to wgpu."`,
	window: bool `usage:"Open a platform window. Enabled by default for source-project runs."`,
	headless: bool `usage:"Run without a visible window; use the null backend or request a framegrab."`,
	hot_reload: bool `name:"hot-reload" usage:"Enable project hot reload. Enabled by default for source-project runs."`,
	no_hot_reload: bool `name:"no-hot-reload" usage:"Disable project hot reload for this run."`,
	editor: bool `usage:"Start with the in-game editor shell visible. Cmd/Ctrl+E toggles it."`,
	scheduler_trace: bool `name:"scheduler-trace" usage:"Print native scheduler worker and parallel-stage statistics."`,
	runtime_stats: bool `name:"runtime-stats" usage:"Collect ECS storage, engine allocator, and early/late engine-frame timing statistics."`,
	frames: u32 `usage:"Limit renderer frames. Windowed 0 runs until close; headless 0 captures one frame."`,
	framegrab: string `usage:"Write the final headless WGPU frame to this PNG path."`,
	framegrab_region: string `name:"framegrab-region" usage:"Export a 1:1 top-left pixel crop as x,y,width,height."`,
	ui_script: string `name:"ui-script" usage:"Replay semantic UI actions from a JSON script."`,
	ui_dump: string `name:"ui-dump" usage:"Write the final reconciled UI tree as JSON."`,
	json: bool `usage:"Emit one machine-readable JSON result."`,
}

Packaged_Run_Options :: struct {
	backend: string `usage:"Renderer backend: null or wgpu."`,
	window: bool `usage:"Open a platform window for renderer runs."`,
	headless: bool `usage:"Force headless mode."`,
	frames: u32 `usage:"Limit renderer frames."`,
	framegrab: string `usage:"Write the final headless WGPU frame to this PNG path."`,
	framegrab_region: string `name:"framegrab-region" usage:"Export a 1:1 top-left pixel crop as x,y,width,height."`,
	ui_script: string `name:"ui-script" usage:"Replay semantic UI actions from a JSON script."`,
	ui_dump: string `name:"ui-dump" usage:"Write the final reconciled UI tree as JSON."`,
	runtime_stats: bool `name:"runtime-stats" usage:"Collect ECS storage, engine allocator, and early/late engine-frame timing statistics."`,
	json: bool `usage:"Emit one machine-readable JSON result."`,
}

Json_Envelope :: struct($T: typeid) {
	schema_version: int,
	command: string,
	ok: bool,
	diagnostics: []diagnostic.Diagnostic,
	result: T,
}

Path_Result :: struct {
	path: string,
}
Build_Result :: struct {
	target, output_directory, executable: string,
}
Check_Result :: struct {
	project_file, path: string,
}
Run_Result :: struct {
	backend: string,
	entities, cameras, geometries, renderables, draw_batches: int,
	scheduler_workers, parallel_stages, max_parallel_width: int,
}
Run_Stats_Result :: struct {
	backend: string,
	entities, cameras, geometries, renderables, draw_batches: int,
	scheduler_workers, parallel_stages, max_parallel_width: int,
	runtime_stats: scrapbot.Runtime_Stats,
}
Error_Result :: struct {}

main :: proc() {
	code := run()
	os.exit(code)
}

run :: proc() -> int {
	args := os.args[1:]
	if is_packaged_game() {
		return run_packaged(args)
	}
	if len(args) == 0 {
		print_help()
		return 0
	}

	switch args[0] {
		case "--version", "version":
			fmt.println(scrapbot.VERSION)
			return 0
		case "help", "--help", "-h":
			if len(args) >= 2 {
				return print_command_help(args[1])
			}
			print_help()
			return 0
		case "init":
			return run_init(args[1:])
		case "check":
			return run_check(args[1:])
		case "build":
			return run_build(args[1:])
		case "run":
			return run_project(args[1:])
		case:
			fmt.eprintf("unknown command: %s\n", args[0])
			print_help()
			return 1
	}
}

run_init :: proc(args: []string) -> int {
	opt := Init_Options {
		path = ".",
	}
	code, should_run := parse_command_args(&opt, args, "scrapbot init")
	if !should_run {
		return code
	}

	if err := scrapbot.init_project(opt.path, opt.name); err != "" {
		if opt.json { emit_json_error("init", "SCRAPBOT_INIT_FAILED", err, opt.path); return 1 }
		fmt.eprintln(err)
		return 1
	}
	if opt.json { emit_json_success("init", Path_Result{path = opt.path}); return 0 }
	fmt.printf("initialized Scrapbot project in %s\n", opt.path)
	return 0
}

run_check :: proc(args: []string) -> int {
	opt := Check_Options {
		path = ".",
	}
	code, should_run := parse_command_args(&opt, args, "scrapbot check")
	if !should_run {
		return code
	}

	if err := scrapbot.check_project(opt.path); err != "" {
		if opt.json { emit_json_error("check", "SCRAPBOT_CHECK_FAILED", err, opt.path); return 1 }
		fmt.eprintln(err)
		return 1
	}
	if opt.json { emit_json_success("check", Check_Result{project_file = scrapbot.PROJECT_FILE, path = opt.path}); return 0 }
	fmt.printf("%s is valid\n", scrapbot.PROJECT_FILE)
	return 0
}

run_build :: proc(args: []string) -> int {
	opt := Build_Options {
		path = ".",
	}
	code, should_run := parse_command_args(&opt, args, "scrapbot build")
	if !should_run {
		return code
	}

	result := scrapbot.package_project(opt.path, scrapbot.Package_Config{target = opt.target})
	defer scrapbot.destroy_package_result(&result)
	if result.err != "" {
		code := "SCRAPBOT_BUILD_FAILED"
		if opt.target != "" &&
		   opt.target != "host" &&
		   opt.target != scrapbot.host_target() { code = "SCRAPBOT_UNSUPPORTED_TARGET" }
		if opt.json { emit_json_error("build", code, result.err, opt.path); return 1 }
		fmt.eprintln(result.err)
		return 1
	}
	if opt.json { emit_json_success("build", Build_Result{target = result.target, output_directory = result.output_directory, executable = result.executable}); return 0 }
	fmt.printf("built %s package in %s\n", result.target, result.output_directory)
	return 0
}

is_packaged_game :: proc() -> bool {
	dir, err := os.get_executable_directory(context.temp_allocator)
	if err != nil { return false }
	marker, join_err := filepath.join({dir, scrapbot.PACKAGE_MARKER}, context.temp_allocator)
	if join_err != nil { return false }
	return os.exists(marker)
}

run_packaged :: proc(args: []string) -> int {
	opt := Packaged_Run_Options {
		backend = "wgpu",
		window = len(args) == 0,
	}
	code, should_run := parse_command_args(&opt, args, "scrapbot run")
	if !should_run { return code }
	root, root_err := os.get_executable_directory(context.temp_allocator)
	if root_err != nil {
		if opt.json { emit_json_error("run", "SCRAPBOT_RUN_FAILED", fmt.tprintf("failed to locate packaged game: %v", root_err), ""); return 1 }
		fmt.eprintf("failed to locate packaged game: %v\n", root_err)
		return 1
	}
	backend, backend_ok := scrapbot.parse_renderer_backend(opt.backend)
	if !backend_ok {
		if opt.json { emit_json_error("run", "SCRAPBOT_UNKNOWN_RENDERER", fmt.tprintf("unknown renderer backend: %s", opt.backend), root); return 1 }
		fmt.eprintf("unknown renderer backend: %s\n", opt.backend)
		return 1
	}
	framegrab_region, region_ok := scrapbot.parse_framegrab_region(opt.framegrab_region)
	if !region_ok ||
	   opt.framegrab_region != "" &&
		   opt.framegrab ==
			   "" { message := "--framegrab-region requires x,y,width,height and --framegrab"; if opt.json { emit_json_error("run", "SCRAPBOT_ARGUMENT_ERROR", message, root) } else { fmt.eprintln(message) }; return 1 }
	if opt.runtime_stats &&
	   opt.window &&
	   !opt.headless &&
	   opt.frames ==
		   0 { message := "--runtime-stats requires --frames for windowed runs"; if opt.json { emit_json_error("run", "SCRAPBOT_ARGUMENT_ERROR", message, root) } else { fmt.eprintln(message) }; return 1 }
	config := scrapbot.Run_Config {
		backend = backend,
		window = opt.window && !opt.headless,
		hot_reload = false,
		max_frames = opt.frames,
		framegrab_path = opt.framegrab,
		framegrab_region = framegrab_region,
		ui_script_path = opt.ui_script,
		ui_dump_path = opt.ui_dump,
		collect_runtime_stats = opt.runtime_stats,
		log_enabled = !opt.json,
	}
	result := scrapbot.run_packaged_project(root, config)
	if result.err != "" {
		if opt.json { emit_json_error("run", "SCRAPBOT_RUN_FAILED", result.err, root); return 1 }
		fmt.eprintln(result.err)
		return 1
	}
	if opt.json {
		if result.runtime_stats.enabled { emit_json_success("run", Run_Stats_Result{backend = scrapbot.renderer_backend_name(backend), entities = result.frame.entity_count, cameras = result.frame.camera_count, geometries = result.frame.mesh_count, renderables = result.frame.renderable_count, draw_batches = result.draw_batches, scheduler_workers = result.scheduler_workers, parallel_stages = result.parallel_stages, max_parallel_width = result.max_parallel_width, runtime_stats = result.runtime_stats}) } else { emit_json_success("run", Run_Result{backend = scrapbot.renderer_backend_name(backend), entities = result.frame.entity_count, cameras = result.frame.camera_count, geometries = result.frame.mesh_count, renderables = result.frame.renderable_count, draw_batches = result.draw_batches, scheduler_workers = result.scheduler_workers, parallel_stages = result.parallel_stages, max_parallel_width = result.max_parallel_width}) }
		return 0
	}
	if opt.runtime_stats { print_runtime_stats(result.runtime_stats) }
	fmt.printf(
		"%s frame: %d entities, %d cameras, %d geometries, %d renderables, %d draw batches\n",
		scrapbot.renderer_backend_name(backend),
		result.frame.entity_count,
		result.frame.camera_count,
		result.frame.mesh_count,
		result.frame.renderable_count,
		result.draw_batches,
	)
	return 0
}

run_project :: proc(args: []string) -> int {
	opt := Run_Options {
		path = ".",
		backend = "wgpu",
		window = true,
		hot_reload = true,
	}
	code, should_run := parse_command_args(&opt, args, "scrapbot run")
	if !should_run {
		return code
	}

	backend, backend_ok := scrapbot.parse_renderer_backend(opt.backend)
	if !backend_ok {
		if opt.json { emit_json_error("run", "SCRAPBOT_UNKNOWN_RENDERER", fmt.tprintf("unknown renderer backend: %s", opt.backend), opt.path); return 1 }
		fmt.eprintf("unknown renderer backend: %s\n", opt.backend)
		return 1
	}
	windowed := backend == .WGPU && opt.window && !opt.headless
	hot_reload := opt.hot_reload && !opt.no_hot_reload
	framegrab_region, region_ok := scrapbot.parse_framegrab_region(opt.framegrab_region)
	if !region_ok ||
	   opt.framegrab_region != "" &&
		   opt.framegrab ==
			   "" { message := "--framegrab-region requires x,y,width,height and --framegrab"; if opt.json { emit_json_error("run", "SCRAPBOT_ARGUMENT_ERROR", message, opt.path) } else { fmt.eprintln(message) }; return 1 }
	if opt.runtime_stats &&
	   windowed &&
	   opt.frames ==
		   0 { message := "--runtime-stats requires --frames for windowed runs"; if opt.json { emit_json_error("run", "SCRAPBOT_ARGUMENT_ERROR", message, opt.path) } else { fmt.eprintln(message) }; return 1 }

	config := scrapbot.Run_Config {
		backend = backend,
		window = windowed,
		hot_reload = hot_reload,
		editor = opt.editor,
		max_frames = opt.frames,
		framegrab_path = opt.framegrab,
		framegrab_region = framegrab_region,
		ui_script_path = opt.ui_script,
		ui_dump_path = opt.ui_dump,
		collect_runtime_stats = opt.runtime_stats,
		log_enabled = !opt.json,
	}
	result := scrapbot.run_project(opt.path, config)
	if result.err != "" {
		if opt.json { emit_json_error("run", "SCRAPBOT_RUN_FAILED", result.err, opt.path); return 1 }
		fmt.eprintln(result.err)
		return 1
	}
	if opt.json {
		if result.runtime_stats.enabled {
			emit_json_success(
				"run",
				Run_Stats_Result {
					backend = scrapbot.renderer_backend_name(backend),
					entities = result.frame.entity_count,
					cameras = result.frame.camera_count,
					geometries = result.frame.mesh_count,
					renderables = result.frame.renderable_count,
					draw_batches = result.draw_batches,
					scheduler_workers = result.scheduler_workers,
					parallel_stages = result.parallel_stages,
					max_parallel_width = result.max_parallel_width,
					runtime_stats = result.runtime_stats,
				},
			)
		} else {
			emit_json_success(
				"run",
				Run_Result {
					backend = scrapbot.renderer_backend_name(backend),
					entities = result.frame.entity_count,
					cameras = result.frame.camera_count,
					geometries = result.frame.mesh_count,
					renderables = result.frame.renderable_count,
					draw_batches = result.draw_batches,
					scheduler_workers = result.scheduler_workers,
					parallel_stages = result.parallel_stages,
					max_parallel_width = result.max_parallel_width,
				},
			)
		}
		return 0
	}
	if opt.scheduler_trace {
		fmt.printf(
			"scheduler: %d workers, %d parallel stages, max width %d\n",
			result.scheduler_workers,
			result.parallel_stages,
			result.max_parallel_width,
		)
	}
	if opt.runtime_stats { print_runtime_stats(result.runtime_stats) }
	fmt.printf(
		"%s frame: %d entities, %d cameras, %d geometries, %d renderables, %d draw batches\n",
		scrapbot.renderer_backend_name(backend),
		result.frame.entity_count,
		result.frame.camera_count,
		result.frame.mesh_count,
		result.frame.renderable_count,
		result.draw_batches,
	)
	return 0
}

print_runtime_stats :: proc(stats: scrapbot.Runtime_Stats) {
	fmt.printf(
		"runtime stats: %d frames, engine frame %.3f -> %.3f ms (%.2fx), allocator %d -> %d bytes, %d after teardown\n",
		stats.frames,
		f64(stats.early_update_ns_per_frame) / 1_000_000.0,
		f64(stats.late_update_ns_per_frame) / 1_000_000.0,
		stats.cpu_growth_ratio,
		stats.allocator_early_bytes,
		stats.allocator_late_bytes,
		stats.allocator_final_bytes,
	)
}

parse_command_args :: proc(
	opt: ^$T,
	args: []string,
	program: string,
) -> (
	code: int,
	should_run: bool,
) {
	err := flags.parse(opt, args, PARSING_STYLE)
	if err == nil {
		return 0, true
	}

	if json_requested(args) {
		emit_json_error(
			program[len("scrapbot "):],
			"SCRAPBOT_ARGUMENT_ERROR",
			fmt.tprintf("%v", err),
			"",
		)
	} else {
		flags.print_errors(T, err, program, PARSING_STYLE)
	}
	if _, is_help := err.(flags.Help_Request); is_help {
		return 0, false
	}
	return 1, false
}

json_requested :: proc(args: []string) -> bool {
	for arg in args { if arg == "--json" { return true } }
	return false
}

emit_json_success :: proc(command: string, result: $T) {
	diagnostics := make([]diagnostic.Diagnostic, 0)
	defer delete(diagnostics)
	emit_json(
		Json_Envelope(T) {
			schema_version = 1,
			command = command,
			ok = true,
			diagnostics = diagnostics,
			result = result,
		},
	)
}

emit_json_error :: proc(command, code, message, path: string) {
	diagnostics := []diagnostic.Diagnostic{diagnostic.error(code, message, path)}
	emit_json(
		Json_Envelope(Error_Result) {
			schema_version = 1,
			command = command,
			ok = false,
			diagnostics = diagnostics,
			result = {},
		},
	)
}

emit_json :: proc(envelope: $T) {
	data, err := json.marshal(envelope)
	if err != nil { fmt.eprintf("failed to encode diagnostic JSON: %v\n", err); return }
	defer delete(data)
	fmt.println(string(data))
}

print_command_help :: proc(command: string) -> int {
	stdout := os.to_stream(os.stdout)
	switch command {
		case "init":
			flags.write_usage(stdout, Init_Options, "scrapbot init", PARSING_STYLE)
		case "check":
			flags.write_usage(stdout, Check_Options, "scrapbot check", PARSING_STYLE)
		case "build":
			flags.write_usage(stdout, Build_Options, "scrapbot build", PARSING_STYLE)
		case "run":
			flags.write_usage(stdout, Run_Options, "scrapbot run", PARSING_STYLE)
		case:
			fmt.eprintf("unknown command: %s\n", command)
			print_help()
			return 1
	}
	return 0
}

print_help :: proc() {
	fmt.println(
		`scrapbot commands:
  scrapbot init [path] [name]    Create project.toml and scenes/main.scene.toml
  scrapbot check [path]          Validate project.toml and the default scene
  scrapbot build [path]          Build a host-native runnable game package
  scrapbot run [path] [--backend null|wgpu] [--window] [--editor] [--hot-reload] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--ui-script actions.json] [--ui-dump tree.json]
                                  Load the project and render
  scrapbot help <command>         Print command-specific options
  scrapbot --version             Print the engine version`,
	)
}
