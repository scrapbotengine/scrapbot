package scrapbot

import project "./project"
import resources "./resources"
import shared "./shared"
import "core:strings"

@(private)
Project_Save_Committer :: #type proc(root: string, files: []project.Save_File) -> string

@(private)
save_project_world :: proc(
	root, scene_path: string,
	registry: ^resources.Registry,
	world: ^shared.World,
	dirty_entities: []shared.Entity_UUID,
	dirty_resources: []shared.Resource_UUID,
) -> string {
	return save_project_world_with_committer(
		root,
		scene_path,
		registry,
		world,
		dirty_entities,
		dirty_resources,
		project.commit_project_save,
	)
}

@(private)
save_project_world_with_committer :: proc(
	root, scene_path: string,
	registry: ^resources.Registry,
	world: ^shared.World,
	dirty_entities: []shared.Entity_UUID,
	dirty_resources: []shared.Resource_UUID,
	committer: Project_Save_Committer,
) -> string {
	if committer == nil {
		return "cannot save without a project transaction committer"
	}
	files: [dynamic]project.Save_File
	defer project.destroy_owned_save_files(&files)
	if err := resources.prepare_project_material_save_files(
		registry,
		root,
		dirty_resources,
		&files,
	); err != "" {
		return err
	}
	if len(dirty_entities) > 0 {
		scene_source, scene_err := prepare_scene_world_save(scene_path, world, dirty_entities)
		if scene_err != "" {
			return scene_err
		}
		owned_scene_path, clone_err := strings.clone(scene_path)
		if clone_err != nil {
			delete(scene_source)
			return "failed to allocate prepared scene path"
		}
		append(&files, project.Save_File{path = owned_scene_path, source = scene_source})
	}
	if validation_err := validate_project_save_references(root, scene_path, registry, files[:]);
	   validation_err != "" {
		return validation_err
	}
	return committer(root, files[:])
}

@(private)
validate_project_save_references :: proc(
	root, scene_path: string,
	registry: ^resources.Registry,
	files: []project.Save_File,
) -> string {
	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	candidate: shared.Scene
	defer project.destroy_scene(&candidate)
	scene := &loaded.scene
	for file in files {
		if file.path != scene_path {
			continue
		}
		parse_result: project.Parse_Result
		candidate, parse_result = project.parse_scene(file.source)
		if parse_result.err != .None {
			return "prepared scene became invalid before project save"
		}
		scene = &candidate
		break
	}
	candidate_resources: [dynamic]shared.Project_Resource
	defer delete(candidate_resources)
	if registry != nil {
		for material in registry.materials {
			if !material.alive || !material.authored {
				continue
			}
			append(
				&candidate_resources,
				shared.Project_Resource {
					id = material.id,
					kind = .Material,
					name = material.name,
					source = material.source,
				},
			)
		}
	}
	return project.validate_scene_resource_references(scene, candidate_resources[:])
}
