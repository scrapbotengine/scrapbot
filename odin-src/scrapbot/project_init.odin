package main

import "core:os"
import "core:path/filepath"
import "core:strings"

DEFAULT_SCENE_PATH :: "scenes/main.scene.toml"

STARTER_SCENE_CONTENTS :: `name = "Main"
version = 1

[[entities]]
id = "scrapbot.renderer"
name = "Renderer"

[entities.components."scrapbot.renderer"]
hdr = true
tone_mapping = "aces"
exposure = 0.0
postprocess_enabled = true
antialiasing = "fxaa"
bloom_enabled = true
bloom_threshold = 0.85
bloom_intensity = 0.12
bloom_radius = 1.0
vignette_enabled = true
vignette_strength = 0.24
vignette_radius = 0.82
chromatic_aberration_enabled = true
chromatic_aberration_strength = 0.0025

[[entities]]
id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001"
name = "Demo Cube"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]

[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 0
rings = 0

[entities.components."scrapbot.material.surface"]
base_color = [0.0, 0.56, 1.0]

[[entities]]
id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0002"
name = "Main Camera"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 4.8]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]

[entities.components."scrapbot.camera"]
fov_y_degrees = 48.0
near = 0.1
far = 100.0

[[entities]]
id = "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0003"
name = "Key Light"

[entities.components."scrapbot.light.directional"]
direction = [0.35, 0.68, 0.64]
color = [1.0, 1.0, 1.0]
intensity = 0.78
ambient = 0.18
`

init_project :: proc(root_path, name: string) -> Project_Error {
	if !ensure_directory(root_path) {
		return .Io_Error
	}

	canonical_metadata_path := project_relative_path(root_path, PROJECT_FILE_NAME)
	defer delete(canonical_metadata_path)
	if os.exists(canonical_metadata_path) {
		return .Already_Exists
	}
	legacy_metadata_path := project_relative_path(root_path, LEGACY_PROJECT_FILE_NAME)
	defer delete(legacy_metadata_path)
	if os.exists(legacy_metadata_path) {
		return .Already_Exists
	}

	scenes_path := project_relative_path(root_path, "scenes")
	defer delete(scenes_path)
	assets_path := project_relative_path(root_path, "assets")
	defer delete(assets_path)
	if !ensure_directory(scenes_path) || !ensure_directory(assets_path) {
		return .Io_Error
	}

	project_contents, contents_ok := starter_project_contents(name)
	if !contents_ok {
		return .Io_Error
	}
	defer delete(project_contents)

	if write_new_file(canonical_metadata_path, project_contents) != .None {
		return .Io_Error
	}

	scene_path := project_relative_path(root_path, DEFAULT_SCENE_PATH)
	defer delete(scene_path)
	if write_new_file(scene_path, STARTER_SCENE_CONTENTS) != .None {
		return .Io_Error
	}

	gitkeep_path := project_relative_path(root_path, "assets/.gitkeep")
	defer delete(gitkeep_path)
	if write_new_file(gitkeep_path, "") != .None {
		return .Io_Error
	}

	return .None
}

ensure_directory :: proc(path: string) -> bool {
	err := os.mkdir_all(path)
	if err == nil {
		return true
	}
	return os.is_dir(path)
}

starter_project_contents :: proc(name: string) -> (string, bool) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "name = \"")
	if !write_toml_basic_string_contents(&builder, name) {
		return "", false
	}
	strings.write_string(&builder, "\"\nversion = 1\ndefault_scene = \"")
	strings.write_string(&builder, DEFAULT_SCENE_PATH)
	strings.write_string(&builder, "\"\n\n# native = \"native/game.odin\"\n")
	return strings.clone(strings.to_string(builder)), true
}

write_toml_basic_string_contents :: proc(builder: ^strings.Builder, value: string) -> bool {
	for c in value {
		switch c {
		case '"':
			strings.write_string(builder, `\"`)
		case '\\':
			strings.write_string(builder, `\\`)
		case '\n':
			strings.write_string(builder, `\n`)
		case '\r':
			strings.write_string(builder, `\r`)
		case '\t':
			strings.write_string(builder, `\t`)
		case:
			if c < 0x20 {
				return false
			}
			strings.write_rune(builder, c)
		}
	}
	return true
}

write_new_file :: proc(path, contents: string) -> Project_Error {
	file, open_err := os.open(path, os.O_CREATE | os.O_EXCL | os.O_WRONLY, os.Permissions_Default_File)
	if open_err != nil {
		return .Io_Error
	}
	defer os.close(file)
	_, write_err := os.write_string(file, contents)
	if write_err != nil {
		return .Io_Error
	}
	return .None
}

project_name_from_path :: proc(path: string) -> string {
	trimmed := trim_trailing_path_separators(path)
	if trimmed == "" || trimmed == "." {
		return "Scrapbot Project"
	}
	return filepath.base(trimmed)
}

trim_trailing_path_separators :: proc(path: string) -> string {
	end := len(path)
	for end > 0 && (path[end - 1] == '/' || path[end - 1] == '\\') {
		end -= 1
	}
	return path[:end]
}
