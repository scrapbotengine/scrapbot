package scrapbot

import asset_import "./asset_import"
import project "./project"
import resources "./resources"
import shared "./shared"

RESOURCE_EVICTION_GRACE_FRAMES :: u64(3)

Resource_Eviction :: struct {
	id: shared.Resource_UUID,
	due_frame: u64,
}

Resource_Residency :: struct {
	declarations: [dynamic]shared.Project_Resource,
	always_resident: [dynamic]shared.Resource_UUID,
	active: [dynamic]shared.Resource_UUID,
	staging: [dynamic]shared.Resource_UUID,
	evictions: [dynamic]Resource_Eviction,
	frame: u64,
}

init_resource_residency :: proc(
	residency: ^Resource_Residency,
	loaded: ^project.Project_Load_Result,
	active_scene: ^shared.Project_Scene,
) {
	residency^ = {}
	residency.declarations = loaded.resources
	loaded.resources = nil
	residency.always_resident = make([dynamic]shared.Resource_UUID)
	append_unique_resource_id(&residency.always_resident, loaded.config.render.environment)
	if loaded.config.render.background_visible {
		background := loaded.config.render.background_environment
		if background == (shared.Resource_UUID{}) {
			background = loaded.config.render.environment
		}
		append_unique_resource_id(&residency.always_resident, background)
	}
	residency.active = resource_residency_scene_closure(residency, active_scene)
}

init_resident_render_resources :: proc(
	residency: ^Resource_Residency,
	registry: ^resources.Registry,
	world: ^shared.World,
	root: string,
	config: ^shared.Project_Config,
) -> string {
	if residency == nil {
		return "resource residency is unavailable"
	}
	subset := make([dynamic]shared.Project_Resource)
	defer delete(subset)
	for declaration in residency.declarations {
		if resource_id_in(residency.active[:], declaration.id) {
			append(&subset, declaration)
		}
	}
	return init_render_resources(registry, world, root, config, subset[:])
}

destroy_resource_residency :: proc(residency: ^Resource_Residency) {
	if residency == nil {
		return
	}
	project.destroy_project_resources(&residency.declarations)
	delete(residency.always_resident)
	delete(residency.active)
	delete(residency.staging)
	delete(residency.evictions)
	residency^ = {}
}

resource_residency_scene_closure :: proc(
	residency: ^Resource_Residency,
	scene: ^shared.Project_Scene,
) -> [dynamic]shared.Resource_UUID {
	result := make([dynamic]shared.Resource_UUID)
	if residency == nil {
		return result
	}
	for id in residency.always_resident {
		append_unique_resource_id(&result, id)
	}
	if scene != nil {
		for id in scene.resource_closure {
			append_unique_resource_id(&result, id)
		}
	}
	return result
}

resource_residency_stage :: proc(
	residency: ^Resource_Residency,
	registry: ^resources.Registry,
	root: string,
	scene: ^shared.Project_Scene,
) -> string {
	if residency == nil {
		return "resource residency is unavailable"
	}
	delete(residency.staging)
	residency.staging = resource_residency_scene_closure(residency, scene)
	missing := make([dynamic]shared.Resource_UUID)
	defer delete(missing)
	for id in residency.staging {
		cancel_resource_eviction(residency, id)
		if !resources.project_resource_is_resident(registry, id) {
			append(&missing, id)
		}
	}
	if len(missing) == 0 {
		return ""
	}
	if err := register_project_resource_subset(
		registry,
		root,
		residency.declarations[:],
		missing[:],
	); err != "" {
		resource_residency_cancel_staging(residency, registry)
		return err
	}
	for id in residency.staging {
		if !resources.project_resource_is_resident(registry, id) {
			resource_residency_cancel_staging(residency, registry)
			return "scene resource closure could not be made resident"
		}
	}
	return ""
}

resource_residency_activate_staging :: proc(residency: ^Resource_Residency) {
	if residency == nil || residency.staging == nil {
		return
	}
	previous := residency.active
	residency.active = residency.staging
	residency.staging = nil
	for id in residency.active {
		cancel_resource_eviction(residency, id)
	}
	for id in previous {
		if !resource_id_in(residency.active[:], id) {
			schedule_resource_eviction(residency, id)
		}
	}
	delete(previous)
}

resource_residency_cancel_staging :: proc(
	residency: ^Resource_Residency,
	registry: ^resources.Registry,
) {
	if residency == nil {
		return
	}
	for id in residency.staging {
		if !resource_id_in(residency.active[:], id) {
			schedule_resource_eviction(residency, id)
		}
	}
	delete(residency.staging)
	residency.staging = nil
}

resource_residency_advance :: proc(residency: ^Resource_Residency, registry: ^resources.Registry) {
	if residency == nil || registry == nil {
		return
	}
	residency.frame += 1
	write_index := 0
	for eviction in residency.evictions {
		if eviction.due_frame > residency.frame ||
		   resource_id_in(residency.active[:], eviction.id) ||
		   resource_id_in(residency.staging[:], eviction.id) {
			residency.evictions[write_index] = eviction
			write_index += 1
			continue
		}
		_ = resources.retire_project_resource(registry, eviction.id)
	}
	resize(&residency.evictions, write_index)
}

resource_residency_schedule_unreferenced :: proc(
	residency: ^Resource_Residency,
	registry: ^resources.Registry,
) {
	if residency == nil || registry == nil {
		return
	}
	for declaration in residency.declarations {
		id := declaration.id
		if resources.project_resource_is_resident(registry, id) &&
		   !resource_id_in(residency.active[:], id) &&
		   !resource_id_in(residency.staging[:], id) &&
		   !resource_id_in(residency.always_resident[:], id) {
			schedule_resource_eviction(residency, id)
		}
	}
}

register_project_resource_subset :: proc(
	registry: ^resources.Registry,
	root: string,
	declarations: []shared.Project_Resource,
	ids: []shared.Resource_UUID,
) -> string {
	subset := make([dynamic]shared.Project_Resource)
	defer delete(subset)
	for declaration in declarations {
		if resource_id_in(ids, declaration.id) {
			append(&subset, declaration)
		}
	}
	imports := asset_import.ensure_project_imports(root, subset[:])
	defer asset_import.destroy_report(&imports)
	if imports.err != "" {
		return imports.err
	}
	if err := resources.register_project_lod_geometries(registry, subset[:], false); err != "" {
		return err
	}
	if err := resources.register_project_textures(registry, subset[:], imports.products[:], false);
	   err != "" {
		return err
	}
	if err := resources.register_project_environments(
		registry,
		subset[:],
		imports.products[:],
		false,
	); err != "" {
		return err
	}
	if err := resources.register_project_icon_sets(
		registry,
		subset[:],
		imports.products[:],
		false,
	); err != "" {
		return err
	}
	if err := resources.register_project_models(registry, subset[:], imports.products[:], false);
	   err != "" {
		return err
	}
	if err := resources.register_project_shaders(registry, root, subset[:], false); err != "" {
		return err
	}
	if err := resources.register_project_materials(registry, root, subset[:], false); err != "" {
		return err
	}
	return resources.register_project_ui_themes(registry, subset[:], false)
}

schedule_resource_eviction :: proc(residency: ^Resource_Residency, id: shared.Resource_UUID) {
	if id == (shared.Resource_UUID{}) || resource_id_in(residency.always_resident[:], id) {
		return
	}
	for &eviction in residency.evictions {
		if eviction.id == id {
			eviction.due_frame = residency.frame + RESOURCE_EVICTION_GRACE_FRAMES
			return
		}
	}
	append(
		&residency.evictions,
		Resource_Eviction{id = id, due_frame = residency.frame + RESOURCE_EVICTION_GRACE_FRAMES},
	)
}

cancel_resource_eviction :: proc(residency: ^Resource_Residency, id: shared.Resource_UUID) {
	write_index := 0
	for eviction in residency.evictions {
		if eviction.id == id {
			continue
		}
		residency.evictions[write_index] = eviction
		write_index += 1
	}
	resize(&residency.evictions, write_index)
}

append_unique_resource_id :: proc(ids: ^[dynamic]shared.Resource_UUID, id: shared.Resource_UUID) {
	if id != (shared.Resource_UUID{}) && !resource_id_in(ids^[:], id) {
		append(ids, id)
	}
}

resource_id_in :: proc(ids: []shared.Resource_UUID, id: shared.Resource_UUID) -> bool {
	for candidate in ids {
		if candidate == id {
			return true
		}
	}
	return false
}
