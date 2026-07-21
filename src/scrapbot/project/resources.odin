package project

import shared "../shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

load_project_resources :: proc(
	root: string,
) -> (
	resources: [dynamic]shared.Project_Resource,
	err: string,
) {
	resources_root, join_err := filepath.join({root, shared.PROJECT_RESOURCES_DIR})
	if join_err != nil {
		return nil, "failed to allocate resources directory path"
	}
	defer delete(resources_root)
	if !os.exists(resources_root) {
		return resources, ""
	}
	if err = load_project_resource_directory(resources_root, "", &resources); err != "" {
		destroy_project_resources(&resources)
		return nil, err
	}
	seen := make(map[shared.Resource_UUID]string)
	defer delete(seen)
	for resource in resources {
		if previous_source, duplicate := seen[resource.id]; duplicate {
			id_buffer: [36]u8
			return resources, fmt.tprintf(
				"resource UUID %s is declared by both %s and %s",
				shared.resource_uuid_to_string(resource.id, id_buffer[:]),
				previous_source,
				resource.source,
			)
		}
		seen[resource.id] = resource.source
	}
	return resources, ""
}

load_project_resource_directory :: proc(
	full_dir, relative_dir: string,
	resources: ^[dynamic]shared.Project_Resource,
) -> string {
	entries, read_err := os.read_all_directory_by_path(full_dir, context.allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read resource directory %s: %v", full_dir, read_err)
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		relative_path := entry.name
		owned_relative_path := ""
		defer delete(owned_relative_path)
		if relative_dir != "" {
			joined, join_err := filepath.join({relative_dir, entry.name})
			if join_err != nil {
				return "failed to allocate relative resource path"
			}
			owned_relative_path = joined
			relative_path = joined
		}
		#partial switch entry.type {
			case .Directory:
				if err := load_project_resource_directory(
					entry.fullpath,
					relative_path,
					resources,
				); err != "" {
					return err
				}
			case .Regular:
				if !strings.has_suffix(entry.name, ".resource.toml") {
					continue
				}
				bytes, file_err := os.read_entire_file(entry.fullpath, context.temp_allocator)
				if file_err != nil {
					return fmt.tprintf("failed to read resource %s: %v", relative_path, file_err)
				}
				resource, parse_result := parse_project_resource(string(bytes))
				if parse_result.err != .None {
					return fmt.tprintf("resources/%s: %s", relative_path, parse_result.message)
				}
				if clone_err := clone_project_resource_strings(&resource, relative_path);
				   clone_err != "" {
					return clone_err
				}
				append(resources, resource)
			case:
		}
	}
	return ""
}

clone_project_resource_strings :: proc(
	resource: ^shared.Project_Resource,
	source: string,
) -> string {
	name, name_err := strings.clone(resource.name)
	if name_err != nil {
		return "failed to allocate project resource name"
	}
	texture := ""
	if resource.material.texture != "" {
		texture_value, texture_err := strings.clone(resource.material.texture)
		if texture_err != nil {
			delete(name)
			return "failed to allocate project resource texture path"
		}
		texture = texture_value
	}
	texture_source := ""
	if resource.texture.source != "" {
		texture_source_value, texture_source_err := strings.clone(resource.texture.source)
		if texture_source_err != nil {
			delete(name)
			delete(texture)
			return "failed to allocate project texture source path"
		}
		texture_source = texture_source_value
	}
	source_value, source_err := strings.clone(source)
	if source_err != nil {
		delete(name)
		delete(texture)
		delete(texture_source)
		return "failed to allocate project resource source path"
	}
	resource.name = name
	resource.material.texture = texture
	resource.texture.source = texture_source
	resource.source = source_value
	return ""
}

destroy_project_resources :: proc(resources: ^[dynamic]shared.Project_Resource) {
	if resources == nil {
		return
	}
	for &resource in resources^ {
		delete(resource.name)
		delete(resource.source)
		delete(resource.material.texture)
		delete(resource.texture.source)
	}
	delete(resources^)
	resources^ = nil
}

validate_scene_resource_references :: proc(
	scene: ^Scene,
	resources: []shared.Project_Resource,
) -> string {
	if scene == nil {
		return ""
	}
	known_materials := make(map[shared.Resource_UUID]bool)
	defer delete(known_materials)
	known_geometries := make(map[shared.Resource_UUID]bool)
	defer delete(known_geometries)
	for resource in resources {
		if resource.kind == .Material {
			known_materials[resource.id] = true
		} else if resource.kind == .Geometry_LOD {
			known_geometries[resource.id] = true
		}
	}
	for entity in scene.entities {
		if entity.has_geometry {
			if resource_id, valid := shared.resource_uuid_parse(entity.geometry_resource);
			   valid && !known_geometries[resource_id] {
				return fmt.tprintf(
					"scene entity '%s' references unknown geometry resource '%s'",
					entity.name,
					entity.geometry_resource,
				)
			}
		}
		if !entity.has_material {
			continue
		}
		resource_id, valid := shared.resource_uuid_parse(entity.material_resource)
		if !valid {
			return fmt.tprintf(
				"scene entity '%s' has invalid material resource UUID '%s'",
				entity.name,
				entity.material_resource,
			)
		}
		if !known_materials[resource_id] {
			return fmt.tprintf(
				"scene entity '%s' references unknown material resource '%s'",
				entity.name,
				entity.material_resource,
			)
		}
	}
	return ""
}
