package resources

import shared "../shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

SHADER_SOURCE_MAX_BYTES :: 1 * 1024 * 1024

validate_shader_source :: proc(source: string) -> string {
	if source == "" {
		return "shader source must not be empty"
	}
	if len(source) > SHADER_SOURCE_MAX_BYTES {
		return "shader source exceeds the 1 MiB limit"
	}
	forbidden_tokens := [?]string{"@group", "@binding", "@vertex", "@fragment", "@compute"}
	for forbidden in forbidden_tokens {
		if strings.contains(source, forbidden) {
			return fmt.tprintf(
				"shader hooks must not declare '%s' resources or entry points",
				forbidden,
			)
		}
	}
	if !strings.contains(source, "fn scrapbot_vertex") {
		return "shader source must define fn scrapbot_vertex"
	}
	if !strings.contains(source, "fn scrapbot_fragment") {
		return "shader source must define fn scrapbot_fragment"
	}
	return ""
}

register_project_shaders :: proc(
	registry: ^Registry,
	root: string,
	declarations: []shared.Project_Resource,
) -> string {
	if registry == nil {
		return "shader registry is not available"
	}
	ensure_allocator(registry)
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Shader {
			continue
		}
		seen[declaration.id] = true
		path, path_err := filepath.join({root, declaration.shader.source})
		if path_err != nil {
			return fmt.tprintf("resources/%s: failed to resolve shader source", declaration.source)
		}
		bytes, read_err := os.read_entire_file(path, context.temp_allocator)
		delete(path)
		if read_err != nil {
			return fmt.tprintf(
				"resources/%s: failed to read %s: %v",
				declaration.source,
				declaration.shader.source,
				read_err,
			)
		}
		wgsl := string(bytes)
		if source_err := validate_shader_source(wgsl); source_err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, source_err)
		}
		if _, register_err := register_project_shader(registry, declaration, wgsl);
		   register_err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, register_err)
		}
	}
	for &shader in registry.shaders {
		if !shader.alive {
			continue
		}
		if !seen[shader.id] {
			shader.alive = false
			shader.generation += 1
			shader.version += 1
			registry.shader_revision += 1
		}
	}
	return ""
}

register_project_shader :: proc(
	registry: ^Registry,
	declaration: shared.Project_Resource,
	wgsl: string,
) -> (
	Shader_Handle,
	string,
) {
	if registry == nil || declaration.id == (shared.Resource_UUID{}) {
		return {}, "shader identity is invalid"
	}
	if declaration.name == "" || declaration.source == "" || declaration.shader.source == "" {
		return {}, "shader name and source paths must not be empty"
	}
	if err := validate_shader_source(wgsl); err != "" {
		return {}, err
	}
	ensure_allocator(registry)
	if index, found := shader_index_by_uuid_any(registry, declaration.id); found {
		shader := &registry.shaders[index]
		name, _ := strings.clone(declaration.name, registry.allocator)
		source, _ := strings.clone(declaration.source, registry.allocator)
		asset_source, _ := strings.clone(declaration.shader.source, registry.allocator)
		owned_wgsl, _ := strings.clone(wgsl, registry.allocator)
		if name == "" || source == "" || asset_source == "" || owned_wgsl == "" {
			delete(name, registry.allocator)
			delete(source, registry.allocator)
			delete(asset_source, registry.allocator)
			delete(owned_wgsl, registry.allocator)
			return {}, "failed to allocate shader source"
		}
		delete(shader.name, registry.allocator)
		delete(shader.source, registry.allocator)
		delete(shader.asset_source, registry.allocator)
		delete(shader.wgsl, registry.allocator)
		shader.name = name
		shader.source = source
		shader.asset_source = asset_source
		shader.wgsl = owned_wgsl
		shader.cull_mode = declaration.shader.cull_mode
		shader.spectral_surface = declaration.shader.spectral_surface
		shader.alive = true
		shader.version += 1
		registry.shader_revision += 1
		return {u32(index), shader.generation}, ""
	}
	if _, found := shader_index_by_name(registry, declaration.name); found {
		return {}, fmt.tprintf("shader name '%s' is already registered", declaration.name)
	}
	name, _ := strings.clone(declaration.name, registry.allocator)
	source, _ := strings.clone(declaration.source, registry.allocator)
	asset_source, _ := strings.clone(declaration.shader.source, registry.allocator)
	owned_wgsl, _ := strings.clone(wgsl, registry.allocator)
	if name == "" || source == "" || asset_source == "" || owned_wgsl == "" {
		delete(name, registry.allocator)
		delete(source, registry.allocator)
		delete(asset_source, registry.allocator)
		delete(owned_wgsl, registry.allocator)
		return {}, "failed to allocate shader source"
	}
	append(
		&registry.shaders,
		Shader {
			id = declaration.id,
			name = name,
			source = source,
			asset_source = asset_source,
			wgsl = owned_wgsl,
			cull_mode = declaration.shader.cull_mode,
			spectral_surface = declaration.shader.spectral_surface,
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	registry.shader_revision += 1
	return {u32(len(registry.shaders) - 1), 1}, ""
}

get_shader :: proc(registry: ^Registry, handle: Shader_Handle) -> (^Shader, bool) {
	if registry == nil || int(handle.index) >= len(registry.shaders) {
		return nil, false
	}
	shader := &registry.shaders[handle.index]
	return shader, shader.alive && shader.generation == handle.generation
}

shader_handle_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Shader_Handle,
	bool,
) {
	index, found := shader_index_by_uuid_any(registry, id)
	if !found || !registry.shaders[index].alive {
		return {}, false
	}
	return {u32(index), registry.shaders[index].generation}, true
}

shader_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for shader, index in registry.shaders {
		if shader.id == id {
			return index, true
		}
	}
	return -1, false
}

shader_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	if registry == nil || name == "" {
		return -1, false
	}
	for shader, index in registry.shaders {
		if shader.alive && shader.name == name {
			return index, true
		}
	}
	return -1, false
}
