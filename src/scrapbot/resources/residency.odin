package resources

import shared "../shared"
import "core:mem"

// project_resource_is_resident reports logical CPU residency. Generated model
// products follow their owning Model and are not independently addressable.
project_resource_is_resident :: proc(registry: ^Registry, id: shared.Resource_UUID) -> bool {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return false
	}
	if index, found := texture_index_by_uuid_any(registry, id); found {
		return registry.textures[index].alive
	}
	if index, found := environment_index_by_uuid_any(registry, id); found {
		return registry.environments[index].alive
	}
	if index, found := icon_set_index_by_uuid_any(registry, id); found {
		return registry.icon_sets[index].alive
	}
	if index, found := model_index_by_uuid_any(registry, id); found {
		return registry.models[index].alive
	}
	if index, found := material_index_by_uuid_any(registry, id); found {
		return registry.materials[index].alive
	}
	if index, found := shader_index_by_uuid_any(registry, id); found {
		return registry.shaders[index].alive
	}
	if index, found := geometry_index_by_uuid_any(registry, id); found {
		return registry.geometries[index].alive
	}
	if index, found := ui_theme_index_by_id(registry, id); found {
		return registry.ui_themes[index].alive
	}
	return false
}

retire_project_resource :: proc(registry: ^Registry, id: shared.Resource_UUID) -> bool {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return false
	}
	if index, found := model_index_by_uuid_any(registry, id); found {
		model := &registry.models[index]
		if !model.alive {
			return false
		}
		retire_model_products(registry, model)
		generation := model.generation + 1
		version := model.version + 1
		destroy_model(model, registry.allocator)
		model.id = id
		model.authored = true
		model.generation = generation
		model.version = version
		bump_model_revision(registry)
		return true
	}
	if index, found := texture_index_by_uuid_any(registry, id); found {
		texture := &registry.textures[index]
		if !texture.alive {
			return false
		}
		delete(texture.desc.pixels, registry.allocator)
		texture.desc.pixels = nil
		texture.alive = false
		texture.generation += 1
		texture.version += 1
		bump_texture_revision(registry)
		return true
	}
	if index, found := environment_index_by_uuid_any(registry, id); found {
		environment := &registry.environments[index]
		if !environment.alive {
			return false
		}
		delete(environment.desc.sky_pixels, registry.allocator)
		delete(environment.desc.irradiance_pixels, registry.allocator)
		delete(environment.desc.specular_pixels, registry.allocator)
		environment.desc.sky_pixels = nil
		environment.desc.irradiance_pixels = nil
		environment.desc.specular_pixels = nil
		environment.alive = false
		environment.generation += 1
		environment.version += 1
		bump_environment_revision(registry)
		return true
	}
	if index, found := icon_set_index_by_uuid_any(registry, id); found {
		icon_set := &registry.icon_sets[index]
		if !icon_set.alive {
			return false
		}
		generation := icon_set.generation + 1
		version := icon_set.version + 1
		destroy_icon_set(icon_set, registry.allocator)
		icon_set.id = id
		icon_set.authored = true
		icon_set.generation = generation
		icon_set.version = version
		bump_icon_set_revision(registry)
		return true
	}
	if index, found := material_index_by_uuid_any(registry, id); found {
		material := &registry.materials[index]
		if !material.alive {
			return false
		}
		destroy_material_desc(&material.desc, registry.allocator)
		material.desc = {}
		material.alive = false
		material.generation += 1
		material.version += 1
		bump_material_revision(registry)
		return true
	}
	if index, found := shader_index_by_uuid_any(registry, id); found {
		shader := &registry.shaders[index]
		if !shader.alive {
			return false
		}
		delete(shader.wgsl, registry.allocator)
		shader.wgsl = ""
		shader.alive = false
		shader.generation += 1
		shader.version += 1
		registry.shader_revision += 1
		return true
	}
	if index, found := geometry_index_by_uuid_any(registry, id); found {
		geometry := &registry.geometries[index]
		if !geometry.alive {
			return false
		}
		for lod_index in 0 ..< geometry.lod_count {
			retire_generated_geometry(registry, geometry.lod_handles[lod_index])
		}
		release_geometry_payload(geometry, registry.allocator)
		geometry.alive = false
		geometry.generation += 1
		geometry.version += 1
		registry.geometry_topology_revision += 1
		return true
	}
	if index, found := ui_theme_index_by_id(registry, id); found {
		theme := &registry.ui_themes[index]
		if !theme.alive {
			return false
		}
		delete(theme.value.font, registry.allocator)
		theme.value.font = ""
		theme.alive = false
		theme.generation += 1
		theme.version += 1
		registry.ui_theme_revision += 1
		return true
	}
	return false
}

release_geometry_payload :: proc(geometry: ^Geometry, allocator: mem.Allocator) {
	if geometry == nil {
		return
	}
	delete(geometry.vertices, allocator)
	delete(geometry.indices, allocator)
	delete(geometry.query_proxy.positions, allocator)
	delete(geometry.meshlets, allocator)
	delete(geometry.meshlet_vertices, allocator)
	delete(geometry.meshlet_triangles, allocator)
	delete(geometry.cluster_groups, allocator)
	delete(geometry.clusters, allocator)
	delete(geometry.cluster_pages, allocator)
	delete(geometry.cluster_vertices, allocator)
	delete(geometry.cluster_triangles, allocator)
	destroy_geometry_page_source(geometry, allocator)
	geometry.vertices = nil
	geometry.indices = nil
	geometry.query_proxy.positions = nil
	geometry.meshlets = nil
	geometry.meshlet_vertices = nil
	geometry.meshlet_triangles = nil
	geometry.cluster_groups = nil
	geometry.clusters = nil
	geometry.cluster_pages = nil
	geometry.cluster_vertices = nil
	geometry.cluster_triangles = nil
	geometry.lod_handles = {}
	geometry.lod_count = 0
}
