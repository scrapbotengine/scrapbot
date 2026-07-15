package project

import components "../component"
import shared "../shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"

PROJECT_FILE :: shared.PROJECT_FILE
DEFAULT_SCENE :: shared.DEFAULT_SCENE
DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_LUAU_TYPES :: shared.DEFAULT_LUAU_TYPES
DEFAULT_VSCODE_SETTINGS :: shared.DEFAULT_VSCODE_SETTINGS

Project_Config :: shared.Project_Config
Scene :: shared.Scene
Scene_Entity :: shared.Scene_Entity
Vec3 :: shared.Vec3
Vec2 :: shared.Vec2
Vec4 :: shared.Vec4
Custom_Component :: shared.Custom_Component
Named_Vec3 :: shared.Named_Vec3

Project_Load_Result :: struct {
	config: Project_Config,
	scene: Scene,
	err: string,
}

Project_Config_Load_Result :: struct {
	config: Project_Config,
	err: string,
}

Scene_Load_Result :: struct {
	scene: Scene,
	err: string,
}

project_toml_template :: proc(name: string) -> string {
	return fmt.tprintf(`name = "%s"
default_scene = "%s"
`, name, DEFAULT_SCENE)
}

default_scene_template :: proc() -> string {
	camera_buffer, cube_buffer: [36]u8
	camera_id := shared.entity_uuid_to_string(shared.entity_uuid_generate(), camera_buffer[:])
	cube_id := shared.entity_uuid_to_string(shared.entity_uuid_generate(), cube_buffer[:])
	return fmt.tprintf(
		`[[entities]]
id = "%s"
name = "Main Camera"

[entities.transform]
position = [0, 2, 6]
rotation = [-0.321751, 0, 0]
scale = [1, 1, 1]

[entities.camera]
fov = 60
near = 0.1
far = 100

[[entities]]
id = "%s"
name = "Cube"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 1.5707963, 0]

`,
		camera_id,
		cube_id,
	)
}

default_script_template :: proc() -> string {
	return(
		`scrapbot.log("hello from Scrapbot")

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { "scrapbot.transform" },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, autorotate: Autorotate)
	transform.rotation.x += autorotate.velocity.x * time.delta_time
	transform.rotation.y += autorotate.velocity.y * time.delta_time
	transform.rotation.z += autorotate.velocity.z * time.delta_time
end)
` \
	)
}

default_luau_types_template :: proc() -> string {
	registry: components.Registry
	components.init_registry(&registry)
	register_default_project_components(&registry)

	text, err := components.generate_luau_types(&registry)
	if err != "" {
		return components.LUAU_TYPES_PREAMBLE + "declare scrapbot: Scrapbot\n"
	}
	return text
}

default_vscode_settings_template :: proc() -> string {
	return(
		`{
  "luau-lsp.platform.type": "standard",
  "luau-lsp.fflags.enableNewSolver": true,
  "luau-lsp.sourcemap.enabled": false,
  "luau-lsp.types.definitionFiles": {
    "scrapbot": "types/scrapbot.d.luau"
  }
}
` \
	)
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

	assets_dir, join_assets_err := filepath.join({root, "assets"})
	if join_assets_err != nil { return "failed to allocate assets path" }
	defer delete(assets_dir)
	if err := os.make_directory_all(assets_dir);
	   err != nil { return fmt.tprintf("failed to create assets directory: %v", err) }

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
	types_text := default_luau_types_template()
	defer delete(types_text)
	if err := os.write_entire_file(types_path, types_text); err != nil {
		return fmt.tprintf("failed to write %s: %v", types_path, err)
	}

	vscode_settings_path, join_settings_err := filepath.join({root, DEFAULT_VSCODE_SETTINGS})
	if join_settings_err != nil {
		return "failed to allocate editor settings file path"
	}
	defer delete(vscode_settings_path)
	if err := os.write_entire_file(vscode_settings_path, default_vscode_settings_template());
	   err != nil {
		return fmt.tprintf("failed to write %s: %v", vscode_settings_path, err)
	}

	return ""
}

load_project :: proc(root: string) -> Project_Load_Result {
	result: Project_Load_Result

	config_result := load_project_config(root)
	if config_result.err != "" {
		result.err = config_result.err
		return result
	}
	result.config = config_result.config

	scene_path, join_scene_err := filepath.join({root, result.config.default_scene})
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
		result.err = fmt.tprintf("%s: %s", result.config.default_scene, scene_parse_result.message)
		return result
	}

	result.scene = scene
	if font_err := validate_scene_font_references(&result.scene, &result.config); font_err != "" {
		result.err = font_err
	}
	return result
}

load_scene_file :: proc(path: string) -> Scene_Load_Result {
	result: Scene_Load_Result
	scene_bytes, scene_err := os.read_entire_file(path, context.temp_allocator)
	if scene_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", path, scene_err)
		return result
	}
	scene, parse_result := parse_scene(string(scene_bytes))
	if parse_result.err != .None {
		result.err = fmt.tprintf("%s: %s", path, parse_result.message)
		return result
	}
	result.scene = scene
	return result
}

destroy_scene_load_result :: proc(result: ^Scene_Load_Result) {
	destroy_scene(&result.scene)
	result^ = {}
}

validate_scene_font_references :: proc(scene: ^Scene, config: ^Project_Config) -> string {
	if scene == nil || config == nil { return "" }
	for entity in scene.entities {
		font_names := [4]string {
			entity.ui_panel.font,
			entity.ui_text.font,
			entity.ui_button.font,
			entity.ui_input.font,
		}
		for font_name in font_names {
			if font_name == "" { continue }
			found := false
			for font in config.fonts {
				if font.name == font_name { found = true; break }
			}
			if !found {
				return fmt.tprintf(
					"scene entity '%s' references undeclared font '%s'",
					entity.name,
					font_name,
				)
			}
		}
	}
	return ""
}

load_project_config :: proc(root: string) -> Project_Config_Load_Result {
	result: Project_Config_Load_Result

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
		destroy_project_config(&config)
		result.err = fmt.tprintf("%s: %s", PROJECT_FILE, parse_result.message)
		return result
	}

	result.config = config
	return result
}

destroy_project_config_load_result :: proc(result: ^Project_Config_Load_Result) {
	destroy_project_config(&result.config)
	result^ = {}
}

destroy_project_load_result :: proc(result: ^Project_Load_Result) {
	destroy_scene(&result.scene)
	destroy_project_config(&result.config)
	result^ = {}
}

destroy_project_config :: proc(config: ^Project_Config) {
	delete(config.native_extensions)
	delete(config.fonts)
	config^ = {}
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
	if loaded.err != "" {
		return loaded.err
	}
	return validate_namespaced_scene_components(&loaded.scene)
}

write_luau_types :: proc(root: string, registry: ^components.Registry) -> string {
	types_dir, join_types_dir_err := filepath.join({root, "types"})
	if join_types_dir_err != nil {
		return "failed to allocate Luau types directory path"
	}
	defer delete(types_dir)
	if !os.exists(types_dir) {
		if err := os.make_directory_all(types_dir); err != nil {
			return fmt.tprintf("failed to create Luau types directory: %v", err)
		}
	}

	types_path, join_types_path_err := filepath.join({root, DEFAULT_LUAU_TYPES})
	if join_types_path_err != nil {
		return "failed to allocate Luau types path"
	}
	defer delete(types_path)

	types_text, generate_err := components.generate_luau_types(registry)
	if generate_err != "" {
		return generate_err
	}
	defer delete(types_text)

	if err := os.write_entire_file(types_path, types_text); err != nil {
		return fmt.tprintf("failed to write %s: %v", types_path, err)
	}
	return ""
}

register_default_project_components :: proc(registry: ^components.Registry) {
	definition := components.Definition {
		name = "autorotate",
		field_count = 1,
	}
	definition.fields[0] = components.Field_Definition {
		name = "velocity",
		field_type = .Vec3,
	}
	components.register_project_component(registry, definition)
}

validate_namespaced_scene_components :: proc(scene: ^Scene) -> string {
	registry: components.Registry
	components.init_registry(&registry)
	for entity in scene.entities {
		for scene_component in entity.custom_components {
			if !shared.component_name_is_namespaced(scene_component.name) {
				continue
			}
			if err := components.validate_custom_component(&registry, scene_component); err != "" {
				return err
			}
		}
	}
	return ""
}

validate_scene_components :: proc(scene: ^Scene, registry: ^components.Registry) -> string {
	for entity in scene.entities {
		for scene_component in entity.custom_components {
			if err := components.validate_custom_component(registry, scene_component); err != "" {
				return err
			}
		}
	}
	return ""
}
