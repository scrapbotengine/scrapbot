package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:math"
import "core:os"
import "core:strings"

register_project_environments :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
	products: []asset_import.Product,
	retire_missing: bool = true,
) -> string {
	if registry == nil {
		return "environment registry is not available"
	}
	ensure_allocator(registry)
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Environment {
			continue
		}
		product, found := environment_product_by_id(products, declaration.id)
		if !found {
			return "imported environment product is missing"
		}
		bytes, read_err := os.read_entire_file(product.artifact_path, context.temp_allocator)
		sky_texels := int(product.width * product.height)
		irradiance_texels :=
			asset_import.ENVIRONMENT_IRRADIANCE_SIZE * asset_import.ENVIRONMENT_IRRADIANCE_SIZE * 6
		if read_err != nil ||
		   len(bytes) != product.byte_count ||
		   product.width == 0 ||
		   product.height == 0 ||
		   product.width != product.height * 2 ||
		   product.mip_count != asset_import.ENVIRONMENT_SPECULAR_MIP_COUNT ||
		   len(bytes) !=
			   asset_import.environment_product_texel_count(product.width, product.height) * 8 {
			return "imported environment product is invalid"
		}
		pixels := (cast([^]u16)raw_data(bytes))[:len(bytes) / size_of(u16)]
		sky_values := sky_texels * 4
		irradiance_values := irradiance_texels * 4
		if _, register_err := register_project_environment(
			registry,
			declaration,
			{
				sky_pixels = pixels[:sky_values],
				irradiance_pixels = pixels[sky_values:sky_values + irradiance_values],
				specular_pixels = pixels[sky_values + irradiance_values:],
				sky_width = product.width,
				sky_height = product.height,
				irradiance_size = asset_import.ENVIRONMENT_IRRADIANCE_SIZE,
				specular_size = asset_import.ENVIRONMENT_SPECULAR_SIZE,
				specular_mip_count = asset_import.ENVIRONMENT_SPECULAR_MIP_COUNT,
			},
			product.byte_count,
		); register_err != "" {
			return register_err
		}
		seen[declaration.id] = true
	}
	if retire_missing {
		for &environment in registry.environments {
			if environment.authored && environment.alive && !seen[environment.id] {
				environment.alive = false
				environment.generation += 1
				environment.version += 1
				bump_environment_revision(registry)
			}
		}
	}
	return ""
}

register_project_environment :: proc(
	registry: ^Registry,
	declaration: shared.Project_Resource,
	desc: Environment_Desc,
	import_byte_count: int,
) -> (
	Environment_Handle,
	string,
) {
	if declaration.id == (shared.Resource_UUID{}) ||
	   declaration.name == "" ||
	   declaration.source == "" ||
	   declaration.environment.source == "" {
		return {}, "project environment metadata must not be empty"
	}
	if desc.sky_width == 0 ||
	   desc.sky_height == 0 ||
	   desc.sky_width != desc.sky_height * 2 ||
	   len(desc.sky_pixels) != int(desc.sky_width * desc.sky_height * 4) ||
	   desc.irradiance_size == 0 ||
	   desc.specular_size == 0 ||
	   desc.specular_mip_count == 0 ||
	   len(desc.irradiance_pixels) != int(desc.irradiance_size * desc.irradiance_size * 6 * 4) ||
	   len(desc.specular_pixels) == 0 {
		return {}, "environment must contain a complete RGBA16F sky panorama and IBL cube maps"
	}
	ensure_allocator(registry)
	if index, found := environment_index_by_uuid_any(registry, declaration.id); found {
		environment := &registry.environments[index]
		name, name_err := strings.clone(declaration.name, registry.allocator)
		if name_err != nil {
			return {}, "failed to allocate environment name"
		}
		source, source_err := strings.clone(declaration.source, registry.allocator)
		if source_err != nil {
			delete(name, registry.allocator)
			return {}, "failed to allocate environment source"
		}
		asset_source, asset_err := strings.clone(
			declaration.environment.source,
			registry.allocator,
		)
		if asset_err != nil {
			delete(name, registry.allocator)
			delete(source, registry.allocator)
			return {}, "failed to allocate environment asset source"
		}
		delete(environment.name, registry.allocator)
		delete(environment.source, registry.allocator)
		delete(environment.asset_source, registry.allocator)
		delete(environment.desc.sky_pixels, registry.allocator)
		delete(environment.desc.irradiance_pixels, registry.allocator)
		delete(environment.desc.specular_pixels, registry.allocator)
		environment.name = name
		environment.source = source
		environment.asset_source = asset_source
		environment.import_byte_count = import_byte_count
		environment.desc = desc
		environment.desc.sky_pixels = clone_slice(desc.sky_pixels, registry.allocator)
		environment.desc.irradiance_pixels = clone_slice(
			desc.irradiance_pixels,
			registry.allocator,
		)
		environment.desc.specular_pixels = clone_slice(desc.specular_pixels, registry.allocator)
		environment.authored = true
		environment.alive = true
		environment.version += 1
		bump_environment_revision(registry)
		return {u32(index), environment.generation}, ""
	}
	environment := Environment {
		id = declaration.id,
		import_byte_count = import_byte_count,
		authored = true,
		generation = 1,
		version = 1,
		alive = true,
		desc = desc,
	}
	environment.name, _ = strings.clone(declaration.name, registry.allocator)
	environment.source, _ = strings.clone(declaration.source, registry.allocator)
	environment.asset_source, _ = strings.clone(declaration.environment.source, registry.allocator)
	environment.desc.sky_pixels = clone_slice(desc.sky_pixels, registry.allocator)
	environment.desc.irradiance_pixels = clone_slice(desc.irradiance_pixels, registry.allocator)
	environment.desc.specular_pixels = clone_slice(desc.specular_pixels, registry.allocator)
	if environment.name == "" || environment.source == "" || environment.asset_source == "" {
		delete(environment.name, registry.allocator)
		delete(environment.source, registry.allocator)
		delete(environment.asset_source, registry.allocator)
		delete(environment.desc.sky_pixels, registry.allocator)
		delete(environment.desc.irradiance_pixels, registry.allocator)
		delete(environment.desc.specular_pixels, registry.allocator)
		return {}, "failed to allocate environment metadata"
	}
	append(&registry.environments, environment)
	bump_environment_revision(registry)
	return {u32(len(registry.environments) - 1), 1}, ""
}

configure_project_environment :: proc(
	registry: ^Registry,
	config: shared.Project_Render_Config,
) -> string {
	if registry == nil {
		return "environment registry is not available"
	}
	handle: Environment_Handle
	if config.environment != (shared.Resource_UUID{}) {
		resolved, found := environment_handle_by_uuid(registry, config.environment)
		if !found {
			return "configured environment resource is unavailable"
		}
		handle = resolved
	}
	background_handle: Environment_Handle
	if config.background_visible {
		background_id := config.background_environment
		if background_id == (shared.Resource_UUID{}) {
			background_id = config.environment
		}
		if background_id != (shared.Resource_UUID{}) {
			resolved, found := environment_handle_by_uuid(registry, background_id)
			if !found {
				return "configured background environment resource is unavailable"
			}
			background_handle = resolved
		}
	}
	if math.is_nan(config.environment_intensity) ||
	   math.is_inf(config.environment_intensity) ||
	   config.environment_intensity < 0 ||
	   math.is_nan(config.environment_rotation) ||
	   math.is_inf(config.environment_rotation) ||
	   math.is_nan(config.exposure) ||
	   math.is_inf(config.exposure) ||
	   config.exposure <= 0 ||
	   (config.background_visible &&
			   (math.is_nan(config.background_intensity) ||
					   math.is_inf(config.background_intensity) ||
					   config.background_intensity < 0 ||
					   math.is_nan(config.background_rotation) ||
					   math.is_inf(config.background_rotation) ||
					   math.is_nan(config.background_exposure) ||
					   math.is_inf(config.background_exposure) ||
					   config.background_exposure <= 0 ||
					   math.is_nan(config.background_blur) ||
					   math.is_inf(config.background_blur) ||
					   config.background_blur < 0 ||
					   config.background_blur > 1)) {
		return "environment render configuration is invalid"
	}
	if registry.active_environment != handle ||
	   registry.environment_intensity != config.environment_intensity ||
	   registry.environment_rotation != config.environment_rotation ||
	   registry.exposure != config.exposure ||
	   registry.background_visible != config.background_visible ||
	   registry.background_environment != background_handle ||
	   registry.background_intensity != config.background_intensity ||
	   registry.background_rotation != config.background_rotation ||
	   registry.background_exposure != config.background_exposure ||
	   registry.background_blur != config.background_blur {
		registry.active_environment = handle
		registry.environment_intensity = config.environment_intensity
		registry.environment_rotation = config.environment_rotation
		registry.exposure = config.exposure
		registry.background_visible = config.background_visible
		registry.background_environment = background_handle
		registry.background_intensity = config.background_intensity
		registry.background_rotation = config.background_rotation
		registry.background_exposure = config.background_exposure
		registry.background_blur = config.background_blur
		bump_environment_revision(registry)
	}
	return ""
}

reconcile_world_environment :: proc(registry: ^Registry, world: ^shared.World) -> string {
	if registry == nil || world == nil {
		return "environment state is not available"
	}
	structural_change :=
		!world.world_environment_initialized ||
		world.world_environment_revision != world.world_environment_reconciled_revision
	if structural_change {
		world.world_environment_entity_index = -1
		for entity, entity_index in world.entities {
			if !entity.alive ||
			   entity.world_environment_index < 0 ||
			   entity.world_environment_index >= len(world.world_environments) {
				continue
			}
			if world.world_environment_entity_index >= 0 {
				return "a scene may contain only one scrapbot.world_environment component"
			}
			world.world_environment_entity_index = entity_index
		}
		world.world_environment_reconciled_revision = world.world_environment_revision
		world.world_environment_component_revision = 0
		world.world_environment_initialized = true
	}
	entity_index := world.world_environment_entity_index
	if entity_index < 0 ||
	   entity_index >= len(world.entities) ||
	   !world.entities[entity_index].alive {
		if !structural_change {
			return ""
		}
		return configure_world_environment(registry, shared.world_environment_default())
	}
	entity := world.entities[entity_index]
	if !structural_change &&
	   entity.component_revision == world.world_environment_component_revision {
		return ""
	}
	value := world.world_environments[entity.world_environment_index]
	if err := configure_world_environment(registry, value); err != "" {
		return err
	}
	world.world_environment_component_revision = entity.component_revision
	return ""
}

configure_world_environment :: proc(
	registry: ^Registry,
	value: shared.World_Environment_Component,
) -> string {
	if !shared.world_environment_is_valid(value) {
		return "world environment configuration is invalid"
	}
	config := shared.Project_Render_Config {
		environment_intensity = value.lighting_intensity,
		environment_rotation = value.lighting_rotation,
		exposure = value.exposure,
		background_visible = value.background_visible,
		background_intensity = value.background_intensity,
		background_rotation = value.background_rotation,
		background_exposure = value.background_exposure,
		background_blur = value.background_blur,
	}
	if value.lighting != "" {
		id, ok := shared.resource_uuid_parse(value.lighting)
		if !ok {
			return "world environment lighting must be an Environment resource UUID"
		}
		config.environment = id
	}
	if value.background != "" {
		id, ok := shared.resource_uuid_parse(value.background)
		if !ok {
			return "world environment background must be an Environment resource UUID"
		}
		config.background_environment = id
	}
	if err := configure_project_environment(registry, config); err != "" {
		return err
	}
	if registry.atmosphere_sky_tint != value.sky_tint ||
	   registry.atmosphere_ground_color != value.ground_color ||
	   registry.atmosphere_turbidity != value.turbidity ||
	   registry.atmosphere_thickness != value.atmosphere_thickness ||
	   registry.atmosphere_horizon_softness != value.horizon_softness ||
	   registry.atmosphere_sun_size != value.sun_size ||
	   registry.atmosphere_sun_glow != value.sun_glow {
		registry.atmosphere_sky_tint = value.sky_tint
		registry.atmosphere_ground_color = value.ground_color
		registry.atmosphere_turbidity = value.turbidity
		registry.atmosphere_thickness = value.atmosphere_thickness
		registry.atmosphere_horizon_softness = value.horizon_softness
		registry.atmosphere_sun_size = value.sun_size
		registry.atmosphere_sun_glow = value.sun_glow
		bump_environment_revision(registry)
	}
	return ""
}

get_environment :: proc(registry: ^Registry, handle: Environment_Handle) -> (^Environment, bool) {
	if registry == nil || int(handle.index) >= len(registry.environments) {
		return nil, false
	}
	environment := &registry.environments[handle.index]
	return environment, environment.alive && environment.generation == handle.generation
}

environment_handle_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Environment_Handle,
	bool,
) {
	if index, found := environment_index_by_uuid_any(registry, id); found {
		environment := registry.environments[index]
		if environment.alive {
			return {u32(index), environment.generation}, true
		}
	}
	return {}, false
}

environment_index_by_uuid_any :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	int,
	bool,
) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for environment, index in registry.environments {
		if environment.authored && environment.id == id {
			return index, true
		}
	}
	return -1, false
}

environment_product_by_id :: proc(
	products: []asset_import.Product,
	id: shared.Resource_UUID,
) -> (
	asset_import.Product,
	bool,
) {
	for product in products {
		if product.kind == .Environment && product.id == id {
			return product, true
		}
	}
	return {}, false
}

bump_environment_revision :: proc(registry: ^Registry) {
	registry.environment_revision += 1
	if registry.environment_revision == 0 {
		registry.environment_revision = 1
	}
}
