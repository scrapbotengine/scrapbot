package project

import shared "../shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

load_project_scenes :: proc(
	root: string,
	project_resources: []shared.Project_Resource,
) -> (
	scenes: [dynamic]shared.Project_Scene,
	err: string,
) {
	scenes_root, join_err := filepath.join({root, "scenes"})
	if join_err != nil {
		return nil, "failed to allocate scenes directory path"
	}
	defer delete(scenes_root)
	if !os.exists(scenes_root) {
		return nil, "project is missing its scenes directory"
	}
	if err = load_project_scene_directory(scenes_root, "", project_resources, &scenes); err != "" {
		destroy_project_scenes(&scenes)
		return nil, err
	}
	seen := make(map[shared.Resource_UUID]string)
	defer delete(seen)
	for scene in scenes {
		if previous_source, duplicate := seen[scene.id]; duplicate {
			id_buffer: [36]u8
			return scenes, fmt.tprintf(
				"scene UUID %s is declared by both %s and %s",
				shared.resource_uuid_to_string(scene.id, id_buffer[:]),
				previous_source,
				scene.source,
			)
		}
		seen[scene.id] = scene.source
	}
	return scenes, ""
}

load_project_scene_directory :: proc(
	full_dir, relative_dir: string,
	project_resources: []shared.Project_Resource,
	scenes: ^[dynamic]shared.Project_Scene,
) -> string {
	entries, read_err := os.read_all_directory_by_path(full_dir, context.allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read scene directory %s: %v", full_dir, read_err)
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		relative_path := entry.name
		owned_relative_path := ""
		defer delete(owned_relative_path)
		if relative_dir != "" {
			joined, join_err := filepath.join({relative_dir, entry.name})
			if join_err != nil {
				return "failed to allocate relative scene path"
			}
			owned_relative_path = joined
			relative_path = joined
		}
		#partial switch entry.type {
			case .Directory:
				if err := load_project_scene_directory(
					entry.fullpath,
					relative_path,
					project_resources,
					scenes,
				); err != "" {
					return err
				}
			case .Regular:
				if !strings.has_suffix(entry.name, ".scene.toml") {
					continue
				}
				bytes, file_err := os.read_entire_file(entry.fullpath, context.temp_allocator)
				if file_err != nil {
					return fmt.tprintf("failed to read scene %s: %v", relative_path, file_err)
				}
				parsed, parse_result := parse_scene(string(bytes), project_resources, true)
				if parse_result.err != .None {
					destroy_scene(&parsed)
					return fmt.tprintf("scenes/%s: %s", relative_path, parse_result.message)
				}
				name, name_err := strings.clone(parsed.name)
				source, source_err := strings.clone(relative_path)
				id := parsed.id
				destroy_scene(&parsed)
				if name_err != nil || source_err != nil {
					delete(name)
					delete(source)
					return "failed to allocate project scene metadata"
				}
				append(scenes, shared.Project_Scene{id = id, name = name, source = source})
			case:
		}
	}
	return ""
}

project_scene_by_id :: proc(
	scenes: []shared.Project_Scene,
	id: shared.Resource_UUID,
) -> (
	^shared.Project_Scene,
	bool,
) {
	for &scene in scenes {
		if scene.id == id {
			return &scene, true
		}
	}
	return nil, false
}

project_scene_path :: proc(root: string, scene: ^shared.Project_Scene) -> (string, string) {
	if scene == nil || scene.source == "" {
		return "", "scene is unavailable"
	}
	path, join_err := filepath.join({root, "scenes", scene.source})
	if join_err != nil {
		return "", "failed to allocate scene path"
	}
	return path, ""
}

destroy_project_scenes :: proc(scenes: ^[dynamic]shared.Project_Scene) {
	if scenes == nil {
		return
	}
	for &scene in scenes^ {
		delete(scene.name)
		delete(scene.source)
	}
	delete(scenes^)
	scenes^ = nil
}
