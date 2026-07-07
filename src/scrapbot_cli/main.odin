package main

import "core:flags"
import "core:fmt"
import "core:os"
import scrapbot "../scrapbot"

PARSING_STYLE :: flags.Parsing_Style.Unix

Init_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to create."`,
	name: string `args:"pos=1" usage:"Project display name."`,
}

Check_Options :: struct {
	path: string `args:"pos=0" usage:"Project directory to validate."`,
}

Run_Options :: struct {
	path:     string `args:"pos=0" usage:"Project directory to run."`,
	backend: string `usage:"Renderer backend: null or wgpu."`,
	window:  bool   `usage:"Open a short-lived platform window for renderer smoke checks."`,
	headless: bool   `usage:"Force headless mode. This is the default unless --window is passed."`,
}

main :: proc() {
	code := run()
	os.exit(code)
}

run :: proc() -> int {
	args := os.args[1:]
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
	case "run":
		return run_project(args[1:])
	case:
		fmt.eprintf("unknown command: %s\n", args[0])
		print_help()
		return 1
	}
}

run_init :: proc(args: []string) -> int {
	opt := Init_Options{path = ".", name = "Scrapbot Game"}
	code, should_run := parse_command_args(&opt, args, "scrapbot init")
	if !should_run {
		return code
	}

	if err := scrapbot.init_project(opt.path, opt.name); err != "" {
		fmt.eprintln(err)
		return 1
	}
	fmt.printf("initialized Scrapbot project in %s\n", opt.path)
	return 0
}

run_check :: proc(args: []string) -> int {
	opt := Check_Options{path = "."}
	code, should_run := parse_command_args(&opt, args, "scrapbot check")
	if !should_run {
		return code
	}

	if err := scrapbot.check_project(opt.path); err != "" {
		fmt.eprintln(err)
		return 1
	}
	fmt.printf("%s is valid\n", scrapbot.PROJECT_FILE)
	return 0
}

run_project :: proc(args: []string) -> int {
	opt := Run_Options{path = ".", backend = "null"}
	code, should_run := parse_command_args(&opt, args, "scrapbot run")
	if !should_run {
		return code
	}

	backend, backend_ok := scrapbot.parse_renderer_backend(opt.backend)
	if !backend_ok {
		fmt.eprintf("unknown renderer backend: %s\n", opt.backend)
		return 1
	}

	config := scrapbot.Run_Config {
		backend = backend,
		window = opt.window && !opt.headless,
	}
	result := scrapbot.run_project(opt.path, config)
	if result.err != "" {
		fmt.eprintln(result.err)
		return 1
	}
	fmt.printf(
		"%s frame: %d entities, %d cameras, %d meshes\n",
		scrapbot.renderer_backend_name(backend),
		result.frame.entity_count,
		result.frame.camera_count,
		result.frame.mesh_count,
	)
	return 0
}

parse_command_args :: proc(opt: ^$T, args: []string, program: string) -> (code: int, should_run: bool) {
	err := flags.parse(opt, args, PARSING_STYLE)
	if err == nil {
		return 0, true
	}

	flags.print_errors(T, err, program, PARSING_STYLE)
	if _, is_help := err.(flags.Help_Request); is_help {
		return 0, false
	}
	return 1, false
}

print_command_help :: proc(command: string) -> int {
	stdout := os.to_stream(os.stdout)
	switch command {
	case "init":
		flags.write_usage(stdout, Init_Options, "scrapbot init", PARSING_STYLE)
	case "check":
		flags.write_usage(stdout, Check_Options, "scrapbot check", PARSING_STYLE)
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
	fmt.println(`scrapbot commands:
  scrapbot init [path] [name]    Create project.toml and scenes/main.scene.toml
  scrapbot check [path]          Validate project.toml and the default scene
  scrapbot run [path] [--backend null|wgpu] [--window]
                                  Load the project and render one frame
  scrapbot help <command>         Print command-specific options
  scrapbot --version             Print the engine version`)
}
