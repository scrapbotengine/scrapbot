package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:encoding/json"
import "core:mem"
import "core:os"
import "core:strings"

register_project_icon_sets :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
	products: []asset_import.Product,
	retire_missing: bool = true,
) -> string {
	if registry == nil {
		return "icon-set registry is not available"
	}
	ensure_allocator(registry)
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Icon_Set {
			continue
		}
		product, found := icon_set_product_by_id(products, declaration.id)
		if !found {
			return "imported icon-set product is missing"
		}
		pixels, pixels_err := os.read_entire_file(product.artifact_path, context.temp_allocator)
		metadata_bytes, metadata_err := os.read_entire_file(
			product.metadata_path,
			context.temp_allocator,
		)
		metadata: asset_import.Icon_Set_Metadata
		unmarshal_err := json.unmarshal(
			metadata_bytes,
			&metadata,
			allocator = context.temp_allocator,
		)
		if pixels_err != nil ||
		   metadata_err != nil ||
		   unmarshal_err != nil ||
		   len(pixels) != product.byte_count ||
		   product.width != asset_import.ICON_SET_ATLAS_SIZE ||
		   product.height != asset_import.ICON_SET_ATLAS_SIZE ||
		   product.symbol_count <= 0 ||
		   product.symbol_count != len(metadata.symbols) {
			return "imported icon-set product is invalid"
		}
		symbols := make([dynamic]Icon_Symbol, 0, product.symbol_count, context.temp_allocator)
		for symbol in metadata.symbols {
			append(&symbols, Icon_Symbol{name = symbol.name, uv = symbol.uv, plane = symbol.plane})
		}
		if _, register_err := register_project_icon_set(
			registry,
			declaration,
			{pixels = pixels, width = product.width, height = product.height, symbols = symbols},
			product.byte_count,
		); register_err != "" {
			return register_err
		}
		seen[declaration.id] = true
	}
	if retire_missing {
		for &icon_set in registry.icon_sets {
			if icon_set.authored && icon_set.alive && !seen[icon_set.id] {
				icon_set.alive = false
				icon_set.generation += 1
				icon_set.version += 1
				bump_icon_set_revision(registry)
			}
		}
	}
	return ""
}

register_project_icon_set :: proc(
	registry: ^Registry,
	declaration: shared.Project_Resource,
	desc: Icon_Set_Desc,
	import_byte_count: int,
) -> (
	Icon_Set_Handle,
	string,
) {
	if declaration.id == (shared.Resource_UUID{}) ||
	   declaration.name == "" ||
	   declaration.source == "" ||
	   declaration.icon_set.source == "" {
		return {}, "project icon-set metadata must not be empty"
	}
	if desc.width != asset_import.ICON_SET_ATLAS_SIZE ||
	   desc.height != asset_import.ICON_SET_ATLAS_SIZE ||
	   len(desc.pixels) != int(desc.width * desc.height * 4) ||
	   len(desc.symbols) == 0 ||
	   len(desc.symbols) > asset_import.MAX_ICON_SET_SYMBOLS {
		return {}, "icon set must contain a complete RGBA8 atlas and symbols"
	}
	for symbol, index in desc.symbols {
		if symbol.name == "" {
			return {}, "icon symbol name must not be empty"
		}
		for previous in desc.symbols[:index] {
			if previous.name == symbol.name {
				return {}, "icon symbol names must be unique"
			}
		}
	}
	ensure_allocator(registry)
	if index, found := icon_set_index_by_uuid_any(registry, declaration.id); found {
		icon_set := &registry.icon_sets[index]
		if !icon_set.authored {
			return {}, "project icon-set UUID is reserved by a built-in resource"
		}
		replacement, clone_err := make_project_icon_set(
			declaration,
			desc,
			import_byte_count,
			registry.allocator,
		)
		if clone_err != "" {
			return {}, clone_err
		}
		generation := icon_set.generation
		version := icon_set.version + 1
		destroy_icon_set(icon_set, registry.allocator)
		icon_set^ = replacement
		icon_set.generation = generation
		icon_set.version = version
		bump_icon_set_revision(registry)
		return {u32(index), generation}, ""
	}
	icon_set, clone_err := make_project_icon_set(
		declaration,
		desc,
		import_byte_count,
		registry.allocator,
	)
	if clone_err != "" {
		return {}, clone_err
	}
	icon_set.generation = 1
	icon_set.version = 1
	append(&registry.icon_sets, icon_set)
	bump_icon_set_revision(registry)
	return {u32(len(registry.icon_sets) - 1), 1}, ""
}

make_project_icon_set :: proc(
	declaration: shared.Project_Resource,
	desc: Icon_Set_Desc,
	import_byte_count: int,
	allocator: mem.Allocator,
) -> (
	icon_set: Icon_Set,
	err: string,
) {
	icon_set = {
		id = declaration.id,
		import_byte_count = import_byte_count,
		authored = true,
		alive = true,
		desc = clone_icon_set_desc(desc, allocator),
	}
	icon_set.name, _ = strings.clone(declaration.name, allocator)
	icon_set.source, _ = strings.clone(declaration.source, allocator)
	icon_set.asset_source, _ = strings.clone(declaration.icon_set.source, allocator)
	if icon_set.name == "" ||
	   icon_set.source == "" ||
	   icon_set.asset_source == "" ||
	   len(icon_set.desc.pixels) == 0 ||
	   len(icon_set.desc.symbols) != len(desc.symbols) {
		destroy_icon_set(&icon_set, allocator)
		return {}, "failed to allocate icon-set resource"
	}
	return icon_set, ""
}

clone_icon_set_desc :: proc(desc: Icon_Set_Desc, allocator: mem.Allocator) -> Icon_Set_Desc {
	result := Icon_Set_Desc {
		pixels = clone_slice(desc.pixels, allocator),
		width = desc.width,
		height = desc.height,
		symbols = make([dynamic]Icon_Symbol, 0, len(desc.symbols), allocator),
	}
	for symbol in desc.symbols {
		name, clone_err := strings.clone(symbol.name, allocator)
		if clone_err != nil {
			for &owned in result.symbols {
				delete(owned.name, allocator)
			}
			delete(result.symbols)
			delete(result.pixels, allocator)
			return {}
		}
		append(&result.symbols, Icon_Symbol{name = name, uv = symbol.uv, plane = symbol.plane})
	}
	return result
}

clone_icon_set :: proc(icon_set: Icon_Set, allocator: mem.Allocator) -> (Icon_Set, string) {
	result := icon_set
	result.name, _ = strings.clone(icon_set.name, allocator)
	result.source, _ = strings.clone(icon_set.source, allocator)
	result.asset_source, _ = strings.clone(icon_set.asset_source, allocator)
	result.desc = clone_icon_set_desc(icon_set.desc, allocator)
	if result.name == "" ||
	   result.source == "" ||
	   result.asset_source == "" ||
	   len(result.desc.pixels) != len(icon_set.desc.pixels) ||
	   len(result.desc.symbols) != len(icon_set.desc.symbols) {
		destroy_icon_set(&result, allocator)
		return {}, "failed to clone icon-set resource"
	}
	return result, ""
}

destroy_icon_set :: proc(icon_set: ^Icon_Set, allocator: mem.Allocator) {
	if icon_set == nil {
		return
	}
	delete(icon_set.name, allocator)
	delete(icon_set.source, allocator)
	delete(icon_set.asset_source, allocator)
	delete(icon_set.desc.pixels, allocator)
	for &symbol in icon_set.desc.symbols {
		delete(symbol.name, allocator)
	}
	delete(icon_set.desc.symbols)
	icon_set^ = {}
}

get_icon_set :: proc(registry: ^Registry, handle: Icon_Set_Handle) -> (^Icon_Set, bool) {
	if registry == nil || int(handle.index) >= len(registry.icon_sets) {
		return nil, false
	}
	icon_set := &registry.icon_sets[handle.index]
	return icon_set, icon_set.alive && icon_set.generation == handle.generation
}

icon_set_handle_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Icon_Set_Handle,
	bool,
) {
	if index, found := icon_set_index_by_uuid_any(registry, id); found {
		icon_set := registry.icon_sets[index]
		if icon_set.alive {
			return {u32(index), icon_set.generation}, true
		}
	}
	return {}, false
}

icon_symbol :: proc(icon_set: ^Icon_Set, name: string) -> (Icon_Symbol, bool) {
	if icon_set == nil || !icon_set.alive {
		return {}, false
	}
	for symbol in icon_set.desc.symbols {
		if symbol.name == name {
			return symbol, true
		}
	}
	return {}, false
}

icon_set_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for icon_set, index in registry.icon_sets {
		if icon_set.id == id {
			return index, true
		}
	}
	return -1, false
}

icon_set_product_by_id :: proc(
	products: []asset_import.Product,
	id: shared.Resource_UUID,
) -> (
	asset_import.Product,
	bool,
) {
	for product in products {
		if product.kind == .Icon_Set && product.id == id {
			return product, true
		}
	}
	return {}, false
}

bump_icon_set_revision :: proc(registry: ^Registry) {
	registry.icon_set_revision += 1
	if registry.icon_set_revision == 0 {
		registry.icon_set_revision = 1
	}
}
