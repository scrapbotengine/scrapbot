package project

import "core:fmt"
import "core:os"
import "core:path/filepath"
import shared "../shared"

PROJECT_FILE :: shared.PROJECT_FILE
DEFAULT_SCENE :: shared.DEFAULT_SCENE
DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_LUAU_TYPES :: shared.DEFAULT_LUAU_TYPES
DEFAULT_VSCODE_SETTINGS :: shared.DEFAULT_VSCODE_SETTINGS

Project_Config :: shared.Project_Config
Scene :: shared.Scene
Scene_Entity :: shared.Scene_Entity
Vec3 :: shared.Vec3
Custom_Component :: shared.Custom_Component
Named_Vec3 :: shared.Named_Vec3

Project_Load_Result :: struct {
	config: Project_Config,
	scene:  Scene,
	err:    string,
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

[entities.components.autorotate]
velocity = [0, 1.5707963, 0]
`
}

default_script_template :: proc() -> string {
	return `scrapbot.log("hello from Scrapbot")

scrapbot.component("autorotate", {
	velocity = "vec3",
})

scrapbot.system(function(delta_seconds)
	scrapbot.query("autorotate", function(entity, autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += autorotate.velocity.x * delta_seconds
		rotation.y += autorotate.velocity.y * delta_seconds
		rotation.z += autorotate.velocity.z * delta_seconds
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`
}

default_luau_types_template :: proc() -> string {
	return `--!strict

type Scrapbot = {
	log: (message: any) -> (),
	entity_count: () -> number,
	renderable_count: () -> number,
	component: (name: string, schema: ScrapbotComponentSchema) -> (),
	system: (system: (delta_seconds: number) -> ()) -> (),
	query: (component_name: string, callback: (entity: ScrapbotEntity, component: any) -> ()) -> (),
	get_rotation: (entity: ScrapbotEntity) -> ScrapbotVec3,
	set_rotation: (entity: ScrapbotEntity, rotation: ScrapbotVec3) -> (),
}

type ScrapbotEntity = {
	index: number,
	name: string?,
}

type ScrapbotVec3 = {
	x: number,
	y: number,
	z: number,
}

type ScrapbotComponentSchema = {
	[string]: "vec3",
}

declare scrapbot: Scrapbot
`
}

default_vscode_settings_template :: proc() -> string {
	return `{
  "luau-lsp.platform.type": "standard",
  "luau-lsp.sourcemap.enabled": false,
  "luau-lsp.types.definitionFiles": {
    "scrapbot": "types/scrapbot.d.luau"
  }
}
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

	scripts_dir, join_scripts_err := filepath.join({root, "scripts"})
	if join_scripts_err != nil {
		return "failed to allocate scripts path"
	}
	defer delete(scripts_dir)
	if err := os.make_directory_all(scripts_dir); err != nil {
		return fmt.tprintf("failed to create scripts directory: %v", err)
	}

	types_dir, join_types_err := filepath.join({root, "types"})
	if join_types_err != nil {
		return "failed to allocate types path"
	}
	defer delete(types_dir)
	if err := os.make_directory_all(types_dir); err != nil {
		return fmt.tprintf("failed to create types directory: %v", err)
	}

	vscode_dir, join_vscode_err := filepath.join({root, ".vscode"})
	if join_vscode_err != nil {
		return "failed to allocate editor settings path"
	}
	defer delete(vscode_dir)
	if err := os.make_directory_all(vscode_dir); err != nil {
		return fmt.tprintf("failed to create editor settings directory: %v", err)
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

	script_path, join_script_err := filepath.join({root, DEFAULT_SCRIPT})
	if join_script_err != nil {
		return "failed to allocate script path"
	}
	defer delete(script_path)
	if err := os.write_entire_file(script_path, default_script_template()); err != nil {
		return fmt.tprintf("failed to write %s: %v", script_path, err)
	}

	types_path, join_types_file_err := filepath.join({root, DEFAULT_LUAU_TYPES})
	if join_types_file_err != nil {
		return "failed to allocate Luau types path"
	}
	defer delete(types_path)
	if err := os.write_entire_file(types_path, default_luau_types_template()); err != nil {
		return fmt.tprintf("failed to write %s: %v", types_path, err)
	}

	vscode_settings_path, join_settings_err := filepath.join({root, DEFAULT_VSCODE_SETTINGS})
	if join_settings_err != nil {
		return "failed to allocate editor settings file path"
	}
	defer delete(vscode_settings_path)
	if err := os.write_entire_file(vscode_settings_path, default_vscode_settings_template()); err != nil {
		return fmt.tprintf("failed to write %s: %v", vscode_settings_path, err)
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
	destroy_scene(&result.scene)
	result^ = {}
}

destroy_scene :: proc(scene: ^Scene) {
	for &entity in scene.entities {
		for &component in entity.custom_components {
			delete(component.vec3_fields)
		}
		delete(entity.custom_components)
	}
	delete(scene.entities)
	scene^ = {}
}

check_project :: proc(root: string) -> string {
	loaded := load_project(root)
	defer destroy_project_load_result(&loaded)
	return loaded.err
}
