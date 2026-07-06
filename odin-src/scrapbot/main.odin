package main

import "core:fmt"
import "core:os"

VERSION :: "0.0.0-odin-migration"

main :: proc() {
	exit_code := run(os.args)
	if exit_code != 0 {
		os.exit(exit_code)
	}
}

run :: proc(args: []string) -> int {
	if len(args) <= 1 {
		print_help()
		return 0
	}

	command := args[1]
	if command == "--version" {
		fmt.println(VERSION)
		return 0
	}
	if command == "help" || command == "--help" {
		print_help()
		return 0
	}
	if command == "check" {
		return run_check(args[2:])
	}

	fmt.eprintf("unknown command: %s\n", command)
	print_help()
	return 1
}

print_help :: proc() {
	fmt.println(`scrapbot - agent-native game engine

Usage:
  scrapbot --version
  scrapbot help
  scrapbot check [path] [--format text|json]

Odin migration status:
  check currently validates project metadata, referenced files, and first-pass scene structure.
  Runtime, scripting, rendering, editor, and test execution are still being ported.`)
}

run_check :: proc(args: []string) -> int {
	target_path := "."
	format: Check_Output_Format = .Text

	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--format" {
			if i + 1 >= len(args) {
				fmt.eprintln("missing value for --format")
				return 1
			}
			switch args[i + 1] {
			case "text":
				format = .Text
			case "json":
				format = .JSON
			case:
				fmt.eprintf("invalid --format: %s\n", args[i + 1])
				return 1
			}
			i += 2
			continue
		}
		if len(arg) > 0 && arg[0] == '-' {
			fmt.eprintf("unknown argument: %s\n", arg)
			return 1
		}
		if target_path != "." {
			fmt.eprintf("unexpected argument: %s\n", arg)
			return 1
		}
		target_path = arg
		i += 1
	}

	result := check_project(target_path)
	defer free_project(result.project)
	if result.err != .None {
		print_check_error(result.err, target_path, format)
		return 1
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
		if project.native != "" {
			fmt.printf("Native source: %s\n", project.native)
		}
		if project.native_artifact != "" {
			fmt.printf("Native artifact: %s\n", project.native_artifact)
		}
		fmt.println("Runtime validation: pending Odin port")
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
		fmt.println(`},"runtime_validation":"pending_odin_port"}`)
	}

	return 0
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
