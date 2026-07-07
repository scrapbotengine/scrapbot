package scrapbot

import "core:fmt"
import "core:os"
import "core:path/filepath"

Project_Load_Result :: struct {
	config: Project_Config,
	scene:  Scene,
	err:    string,
}

Runtime_Result :: struct {
	frame: Render_Frame,
	err:   string,
}

project_toml_template :: proc(name: string) -> string {
	return fmt.tprintf(`name = "%s"
default_scene = "%s"
`, name, DEFAULT_SCENE)
}

default_scene_template :: proc() -> string {
	return `[[entities]]
name = "Main Camera"

[entities.transform]
position = [0, 2, 6]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.camera]
fov = 60
near = 0.1
far = 100

[[entities]]
name = "Cube"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"
`
}

init_project :: proc(root, name: string) -> string {
	project_name := name
	if project_name == "" {
		project_name = "Scrapbot Game"
	}
	if !is_basic_string_body(project_name) {
		return "project name cannot contain quotes, backslashes, or newlines"
	}

	if err := os.make_directory_all(root); err != nil {
		return fmt.tprintf("failed to create project directory: %v", err)
	}

	scenes_dir, join_err := filepath.join({root, "scenes"})
	if join_err != nil {
		return "failed to allocate scenes path"
	}
	defer delete(scenes_dir)
	if err := os.make_directory_all(scenes_dir); err != nil {
		return fmt.tprintf("failed to create scenes directory: %v", err)
	}

	project_path, join_project_err := filepath.join({root, PROJECT_FILE})
	if join_project_err != nil {
		return "failed to allocate project path"
	}
	defer delete(project_path)
	if os.exists(project_path) {
		return fmt.tprintf("%s already exists", project_path)
	}
	if err := os.write_entire_file(project_path, project_toml_template(project_name)); err != nil {
		return fmt.tprintf("failed to write %s: %v", project_path, err)
	}

	scene_path, join_scene_err := filepath.join({root, DEFAULT_SCENE})
	if join_scene_err != nil {
		return "failed to allocate scene path"
	}
	defer delete(scene_path)
	if err := os.write_entire_file(scene_path, default_scene_template()); err != nil {
		return fmt.tprintf("failed to write %s: %v", scene_path, err)
	}

	return ""
}

load_project :: proc(root: string) -> Project_Load_Result {
	result: Project_Load_Result

	project_path, join_project_err := filepath.join({root, PROJECT_FILE})
	if join_project_err != nil {
		result.err = "failed to allocate project path"
		return result
	}
	defer delete(project_path)

	project_bytes, project_err := os.read_entire_file(project_path, context.temp_allocator)
	if project_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", project_path, project_err)
		return result
	}

	config, parse_result := parse_project_config(string(project_bytes))
	if parse_result.err != .None {
		result.err = fmt.tprintf("%s: %s", PROJECT_FILE, parse_result.message)
		return result
	}

	scene_path, join_scene_err := filepath.join({root, config.default_scene})
	if join_scene_err != nil {
		result.err = "failed to allocate scene path"
		return result
	}
	defer delete(scene_path)
	scene_bytes, scene_err := os.read_entire_file(scene_path, context.temp_allocator)
	if scene_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", scene_path, scene_err)
		return result
	}

	scene, scene_parse_result := parse_scene(string(scene_bytes))
	if scene_parse_result.err != .None {
		result.err = fmt.tprintf("%s: %s", config.default_scene, scene_parse_result.message)
		return result
	}

	result.config = config
	result.scene = scene
	return result
}

destroy_project_load_result :: proc(result: ^Project_Load_Result) {
	delete(result.scene.entities)
	result^ = {}
}

check_project :: proc(root: string) -> string {
	loaded := load_project(root)
	defer destroy_project_load_result(&loaded)
	return loaded.err
}

run_headless :: proc(root: string) -> Runtime_Result {
	return run_project(root, Run_Config{backend = .Null})
}

run_project :: proc(root: string, config: Run_Config) -> Runtime_Result {
	result: Runtime_Result

	loaded := load_project(root)
	defer destroy_project_load_result(&loaded)
	if loaded.err != "" {
		result.err = loaded.err
		return result
	}

	world := build_world(&loaded.scene)
	defer destroy_world(&world)

	result.frame, result.err = run_renderer(config, &world)
	return result
}
