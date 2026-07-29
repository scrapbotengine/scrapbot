package resources

import shared "../shared"
import "core:mem"
import "core:strings"

BUILTIN_ICON_ATLAS :: #load("assets/builtin_icons_mtsdf.bin")

Builtin_Icon_Symbol_Data :: struct {
	name: string,
	uv: [4]f32,
	plane: [4]f32,
}

register_builtin_icon_set :: proc(registry: ^Registry) -> string {
	if registry == nil {
		return "icon-set registry is not available"
	}
	ensure_allocator(registry)
	allocator := registry.allocator
	pixels := make([]u8, len(BUILTIN_ICON_ATLAS), allocator)
	if len(pixels) != len(BUILTIN_ICON_ATLAS) {
		return "failed to allocate built-in icon atlas"
	}
	atlas := BUILTIN_ICON_ATLAS
	for index in 0 ..< len(BUILTIN_ICON_ATLAS) {
		pixels[index] = atlas[index]
	}
	symbols := make([dynamic]Icon_Symbol, 0, len(BUILTIN_ICON_SYMBOLS), allocator)
	for source in BUILTIN_ICON_SYMBOLS {
		name, clone_err := strings.clone(source.name, allocator)
		if clone_err != nil {
			destroy_builtin_icon_data(pixels, symbols, allocator)
			return "failed to allocate built-in icon symbols"
		}
		append(&symbols, Icon_Symbol{name = name, uv = source.uv, plane = source.plane})
	}
	name, name_err := strings.clone("Scrapbot Built-ins", allocator)
	source, source_err := strings.clone("builtin://scrapbot/icons", allocator)
	asset_source, asset_source_err := strings.clone(
		"src/scrapbot/resources/assets/builtin-icons",
		allocator,
	)
	if name_err != nil || source_err != nil || asset_source_err != nil {
		delete(name, allocator)
		delete(source, allocator)
		delete(asset_source, allocator)
		destroy_builtin_icon_data(pixels, symbols, allocator)
		return "failed to allocate built-in icon metadata"
	}
	append(
		&registry.icon_sets,
		Icon_Set {
			id = shared.builtin_icon_set_uuid(),
			name = name,
			source = source,
			asset_source = asset_source,
			authored = false,
			desc = {pixels = pixels, width = 512, height = 512, symbols = symbols},
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	bump_icon_set_revision(registry)
	return ""
}

destroy_builtin_icon_data :: proc(
	pixels: []u8,
	symbols: [dynamic]Icon_Symbol,
	allocator: mem.Allocator,
) {
	delete(pixels, allocator)
	for symbol in symbols {
		delete(symbol.name, allocator)
	}
	delete(symbols)
}
