package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:fmt"
import "core:os"
import "core:strings"

register_project_textures :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
	products: []asset_import.Product,
	retire_missing: bool = true,
) -> string {
	if registry == nil {
		return "texture registry is not available"
	}
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Texture {
			continue
		}
		product, found := texture_product_by_id(products, declaration.id)
		if !found {
			return fmt.tprintf(
				"resources/%s: imported texture product is missing",
				declaration.source,
			)
		}
		pixels, read_err := os.read_entire_file(product.artifact_path, context.temp_allocator)
		if read_err != nil {
			return fmt.tprintf(
				"resources/%s: failed to read imported texture product: %v",
				declaration.source,
				read_err,
			)
		}
		desc := Texture_Desc {
			pixels = pixels,
			width = product.width,
			height = product.height,
			mip_count = product.mip_count,
			color_space = product.color_space,
		}
		if len(pixels) != product.byte_count {
			return fmt.tprintf(
				"resources/%s: imported texture product is truncated",
				declaration.source,
			)
		}
		if _, register_err := register_project_texture(
			registry,
			declaration.id,
			declaration.name,
			declaration.source,
			declaration.texture.source,
			desc,
			product.byte_count,
		); register_err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, register_err)
		}
		seen[declaration.id] = true
	}
	if !retire_missing {
		return ""
	}
	for &texture in registry.textures {
		if texture.authored && texture.alive && !seen[texture.id] {
			_ = retire_project_resource(registry, texture.id)
		}
	}
	return ""
}

register_project_texture :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
	name, source, asset_source: string,
	desc: Texture_Desc,
	import_byte_count: int = 0,
) -> (
	Texture_Handle,
	string,
) {
	if registry == nil {
		return {}, "texture registry is not available"
	}
	if id == (shared.Resource_UUID{}) {
		return {}, "project texture UUID must not be empty"
	}
	if name == "" || source == "" || asset_source == "" {
		return {}, "project texture metadata must not be empty"
	}
	if desc_err := validate_texture_desc(desc); desc_err != "" {
		return {}, desc_err
	}
	ensure_allocator(registry)
	if index, found := texture_index_by_uuid_any(registry, id); found {
		texture := &registry.textures[index]
		name_value, _ := strings.clone(name, registry.allocator)
		source_value, _ := strings.clone(source, registry.allocator)
		asset_value, _ := strings.clone(asset_source, registry.allocator)
		pixels := clone_slice(desc.pixels, registry.allocator)
		if name_value == "" || source_value == "" || asset_value == "" || pixels == nil {
			delete(name_value, registry.allocator)
			delete(source_value, registry.allocator)
			delete(asset_value, registry.allocator)
			delete(pixels, registry.allocator)
			return {}, "failed to allocate project texture"
		}
		delete(texture.name, registry.allocator)
		delete(texture.source, registry.allocator)
		delete(texture.asset_source, registry.allocator)
		delete(texture.desc.pixels, registry.allocator)
		texture.name = name_value
		texture.source = source_value
		texture.asset_source = asset_value
		texture.import_byte_count = import_byte_count
		texture.desc = desc
		texture.desc.pixels = pixels
		texture.alive = true
		texture.version += 1
		bump_texture_revision(registry)
		return {u32(index), texture.generation}, ""
	}
	if _, found := texture_index_by_name(registry, name); found {
		return {}, fmt.tprintf("texture name '%s' is already registered", name)
	}
	name_value, _ := strings.clone(name, registry.allocator)
	source_value, _ := strings.clone(source, registry.allocator)
	asset_value, _ := strings.clone(asset_source, registry.allocator)
	pixels := clone_slice(desc.pixels, registry.allocator)
	if name_value == "" || source_value == "" || asset_value == "" || pixels == nil {
		delete(name_value, registry.allocator)
		delete(source_value, registry.allocator)
		delete(asset_value, registry.allocator)
		delete(pixels, registry.allocator)
		return {}, "failed to allocate project texture"
	}
	append(
		&registry.textures,
		Texture {
			id = id,
			name = name_value,
			source = source_value,
			asset_source = asset_value,
			authored = true,
			import_byte_count = import_byte_count,
			desc = {
				pixels = pixels,
				width = desc.width,
				height = desc.height,
				mip_count = desc.mip_count,
				color_space = desc.color_space,
			},
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	bump_texture_revision(registry)
	return {u32(len(registry.textures) - 1), 1}, ""
}

get_texture :: proc(registry: ^Registry, handle: Texture_Handle) -> (^Texture, bool) {
	if registry == nil || int(handle.index) >= len(registry.textures) {
		return nil, false
	}
	texture := &registry.textures[handle.index]
	return texture, texture.alive && texture.generation == handle.generation
}

texture_handle_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Texture_Handle,
	bool,
) {
	if index, found := texture_index_by_uuid(registry, id); found {
		texture := registry.textures[index]
		return {u32(index), texture.generation}, true
	}
	return {}, false
}

texture_product_by_id :: proc(
	products: []asset_import.Product,
	id: shared.Resource_UUID,
) -> (
	asset_import.Product,
	bool,
) {
	for product in products {
		if product.kind == .Texture && product.id == id {
			return product, true
		}
	}
	return {}, false
}

texture_index_by_uuid :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for texture, index in registry.textures {
		if texture.alive && texture.authored && texture.id == id {
			return index, true
		}
	}
	return -1, false
}

texture_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for texture, index in registry.textures {
		if texture.authored && texture.id == id {
			return index, true
		}
	}
	return -1, false
}

texture_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	if registry == nil {
		return -1, false
	}
	for texture, index in registry.textures {
		if texture.alive && texture.name == name {
			return index, true
		}
	}
	return -1, false
}

validate_texture_desc :: proc(desc: Texture_Desc) -> string {
	if desc.width == 0 || desc.height == 0 || desc.mip_count == 0 {
		return "texture dimensions and mip count must be positive"
	}
	expected := 0
	width, height := desc.width, desc.height
	for _ in 0 ..< desc.mip_count {
		expected += int(width * height * 4)
		width = max(width / 2, 1)
		height = max(height / 2, 1)
	}
	if len(desc.pixels) != expected {
		return "texture product does not contain a complete RGBA8 mip chain"
	}
	return ""
}

bump_texture_revision :: proc(registry: ^Registry) {
	registry.texture_revision += 1
	if registry.texture_revision == 0 {
		registry.texture_revision = 1
	}
}
