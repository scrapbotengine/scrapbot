package resources

import shared "../shared"
import "core:strings"

register_project_ui_themes :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
) -> string {
	if registry == nil {
		return "UI theme registry is not available"
	}
	ensure_allocator(registry)
	seen := make(map[shared.Resource_UUID]bool, registry.allocator)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .UI_Theme {
			continue
		}
		seen[declaration.id] = true
		index, found := ui_theme_index_by_id(registry, declaration.id)
		if !found {
			name, name_err := strings.clone(declaration.name, registry.allocator)
			if name_err != nil {
				return "failed to allocate project UI theme name"
			}
			source, source_err := strings.clone(declaration.source, registry.allocator)
			if source_err != nil {
				delete(name, registry.allocator)
				return "failed to allocate project UI theme source"
			}
			font, font_err := strings.clone(declaration.ui_theme.theme.font, registry.allocator)
			if font_err != nil {
				delete(name, registry.allocator)
				delete(source, registry.allocator)
				return "failed to allocate project UI theme font"
			}
			value := declaration.ui_theme.theme
			value.font = font
			append(
				&registry.ui_themes,
				UI_Theme {
					id = declaration.id,
					name = name,
					source = source,
					value = value,
					generation = 1,
					version = 1,
					alive = true,
				},
			)
			registry.ui_theme_revision += 1
			continue
		}
		entry := &registry.ui_themes[index]
		name, name_err := strings.clone(declaration.name, registry.allocator)
		if name_err != nil {
			return "failed to allocate project UI theme name"
		}
		source, source_err := strings.clone(declaration.source, registry.allocator)
		if source_err != nil {
			delete(name, registry.allocator)
			return "failed to allocate project UI theme source"
		}
		font, font_err := strings.clone(declaration.ui_theme.theme.font, registry.allocator)
		if font_err != nil {
			delete(name, registry.allocator)
			delete(source, registry.allocator)
			return "failed to allocate project UI theme font"
		}
		delete(entry.name, registry.allocator)
		delete(entry.source, registry.allocator)
		delete(entry.value.font, registry.allocator)
		entry.name = name
		entry.source = source
		entry.value = declaration.ui_theme.theme
		entry.value.font = font
		if !entry.alive {
			entry.generation += 1
		}
		entry.alive = true
		entry.version += 1
		registry.ui_theme_revision += 1
	}
	for &entry in registry.ui_themes {
		if entry.alive && !seen[entry.id] {
			entry.alive = false
			entry.generation += 1
			entry.version += 1
			registry.ui_theme_revision += 1
		}
	}
	return ""
}

ui_theme_index_by_id :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return 0, false
	}
	for entry, index in registry.ui_themes {
		if entry.id == id {
			return index, true
		}
	}
	return 0, false
}

ui_theme_by_id :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (shared.UI_Theme, bool) {
	index, found := ui_theme_index_by_id(registry, id)
	if !found || !registry.ui_themes[index].alive {
		return {}, false
	}
	return registry.ui_themes[index].value, true
}

get_ui_theme_by_id :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (^UI_Theme, bool) {
	index, found := ui_theme_index_by_id(registry, id)
	if !found || !registry.ui_themes[index].alive {
		return nil, false
	}
	return &registry.ui_themes[index], true
}
