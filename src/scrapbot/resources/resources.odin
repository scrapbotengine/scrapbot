package resources

import project "../project"
import shared "../shared"
import c "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import stb "vendor:stb/image"

Vec3 :: shared.Vec3

Vec2 :: struct {
	x, y: f32,
}
Vec4 :: struct {
	x, y, z, w: f32,
}

Geometry_Handle :: shared.Geometry_Handle
Material_Handle :: shared.Material_Handle
Font_Handle :: shared.Font_Handle

Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

Bounds :: struct {
	min, max: Vec3,
}

Geometry_Desc :: struct {
	vertices: []Vertex,
	indices: []u32,
}

Material_Desc :: struct {
	base_color: Vec4,
	emissive: Vec3,
	texture_pixels: []u8,
	texture_width: u32,
	texture_height: u32,
}

Font_Desc :: struct {
	pixels: []u8,
	width, height: u32,
	ascender: f32,
	glyphs: [shared.FONT_CHAR_COUNT]shared.Font_Glyph,
}

Geometry :: struct {
	id: shared.Resource_UUID,
	name: string,
	source: string,
	authored: bool,
	vertices: []Vertex,
	indices: []u32,
	bounds: Bounds,
	lod_handles: [shared.MAX_GEOMETRY_LODS - 1]Geometry_Handle,
	lod_screen_radii: [shared.MAX_GEOMETRY_LODS - 1]f32,
	lod_count: int,
	generation: u32,
	version: u32,
	alive: bool,
}

Material :: struct {
	id: shared.Resource_UUID,
	name: string,
	source: string,
	texture_asset: string,
	authored: bool,
	desc: Material_Desc,
	generation: u32,
	version: u32,
	alive: bool,
}

Project_Material_Snapshot :: struct {
	id: shared.Resource_UUID,
	name: string,
	source: string,
	texture_asset: string,
	desc: Material_Desc,
}

Prepared_Project_Material :: struct {
	declaration_index: int,
	desc: Material_Desc,
}

Font :: struct {
	name: string,
	desc: Font_Desc,
	generation: u32,
	version: u32,
	alive: bool,
}

Registry :: struct {
	geometries: [dynamic]Geometry,
	materials: [dynamic]Material,
	fonts: [dynamic]Font,
	geometry_topology_revision: u64,
	allocator: mem.Allocator,
}

ensure_allocator :: proc(registry: ^Registry) {
	if registry.allocator.procedure == nil { registry.allocator = context.allocator }
	if registry.geometries ==
	   nil { registry.geometries = make([dynamic]Geometry, registry.allocator) }
	if registry.materials ==
	   nil { registry.materials = make([dynamic]Material, registry.allocator) }
	if registry.fonts == nil { registry.fonts = make([dynamic]Font, registry.allocator) }
}
init_registry :: proc(registry: ^Registry, allocator := context.allocator) {registry^ = {}
	registry.allocator = allocator
	ensure_allocator(registry)}

destroy_registry :: proc(registry: ^Registry) {
	if registry == nil { return }
	allocator :=
		registry.allocator; if allocator.procedure == nil { allocator = context.allocator }
	for &geometry in registry.geometries {
		delete(geometry.name, allocator)
		delete(geometry.source, allocator)
		delete(geometry.vertices, allocator)
		delete(geometry.indices, allocator)
	}
	for &material in registry.materials {
		delete(material.name, allocator)
		delete(material.source, allocator)
		delete(material.texture_asset, allocator)
		delete(material.desc.texture_pixels, allocator)
	}
	for &font in registry.fonts { delete(font.name, allocator); delete(font.desc.pixels, allocator) }
	delete(registry.geometries)
	delete(registry.materials)
	delete(registry.fonts)
	registry^ = {}
}

register_font :: proc(
	registry: ^Registry,
	name: string,
	desc: Font_Desc,
) -> (
	Font_Handle,
	string,
) {
	if registry == nil { return {}, "font registry is not available" }
	ensure_allocator(registry)
	if name == "" { return {}, "font name must not be empty" }
	if desc.width != shared.FONT_ATLAS_SIZE || desc.height != shared.FONT_ATLAS_SIZE {
		return {}, fmt.tprintf("font atlas must be %dx%d", shared.FONT_ATLAS_SIZE, shared.FONT_ATLAS_SIZE)
	}
	if len(desc.pixels) != int(desc.width * desc.height * 4) {
		return {}, "font atlas must contain linear RGBA8 pixels"
	}
	if !finite(desc.ascender) ||
	   desc.ascender <= 0 { return {}, "font ascender must be positive and finite" }
	if index, found := font_index_by_name(registry, name); found {
		font := &registry.fonts[index]
		delete(font.desc.pixels, registry.allocator)
		font.desc = clone_font_desc(desc, registry.allocator)
		font.version += 1
		return {u32(index), font.generation}, ""
	}
	if len(registry.fonts) >= shared.MAX_PROJECT_FONTS { return {}, "too many project fonts" }
	cloned_name, clone_err := strings.clone(name, registry.allocator)
	if clone_err != nil { return {}, "failed to allocate font name" }
	append(
		&registry.fonts,
		Font {
			name = cloned_name,
			desc = clone_font_desc(desc, registry.allocator),
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	return {u32(len(registry.fonts) - 1), 1}, ""
}

Font_JSON_Bounds :: struct {
	left, top, right, bottom: f64,
}

Font_JSON_Glyph :: struct {
	unicode: int,
	advance: f64,
	plane_bounds: Font_JSON_Bounds `json:"planeBounds"`,
	atlas_bounds: Font_JSON_Bounds `json:"atlasBounds"`,
}

Font_JSON_Metrics :: struct {
	ascender: f64,
}

Font_JSON_Atlas :: struct {
	width, height: int,
}

Font_JSON :: struct {
	atlas: Font_JSON_Atlas,
	metrics: Font_JSON_Metrics,
	glyphs: [dynamic]Font_JSON_Glyph,
}

register_project_fonts :: proc(
	registry: ^Registry,
	root: string,
	fonts: []shared.Project_Font,
) -> string {
	if len(fonts) == 0 { return "" }
	build_dir, build_join_err := filepath.join({root, shared.PROJECT_FONT_BUILD_DIR})
	if build_join_err != nil { return "failed to allocate project font build path" }
	defer delete(build_dir)
	for font in fonts {
		atlas_name := fmt.tprintf("%s.mtsdf.bin", font.name)
		json_name := fmt.tprintf("%s.mtsdf.json", font.name)
		atlas_path, atlas_join_err := filepath.join({build_dir, atlas_name})
		if atlas_join_err !=
		   nil { return fmt.tprintf("failed to allocate atlas path for font '%s'", font.name) }
		defer delete(atlas_path)
		json_path, json_join_err := filepath.join({build_dir, json_name})
		if json_join_err !=
		   nil { return fmt.tprintf("failed to allocate metrics path for font '%s'", font.name) }
		defer delete(json_path)
		if err := register_project_font_files(registry, font.name, atlas_path, json_path);
		   err != "" {
			return err
		}
	}
	return ""
}

register_project_font_files :: proc(
	registry: ^Registry,
	name, atlas_path, json_path: string,
) -> string {
	pixels, pixels_err := os.read_entire_file(atlas_path, context.temp_allocator)
	if pixels_err !=
	   nil { return fmt.tprintf("failed to read generated atlas for font '%s': %v", name, pixels_err) }
	metadata_bytes, metadata_err := os.read_entire_file(json_path, context.temp_allocator)
	if metadata_err !=
	   nil { return fmt.tprintf("failed to read generated metrics for font '%s': %v", name, metadata_err) }
	metadata: Font_JSON
	defer delete(metadata.glyphs)
	if unmarshal_err := json.unmarshal(metadata_bytes, &metadata); unmarshal_err != nil {
		return fmt.tprintf("failed to parse generated metrics for font '%s'", name)
	}
	if metadata.atlas.width != shared.FONT_ATLAS_SIZE ||
	   metadata.atlas.height != shared.FONT_ATLAS_SIZE {
		return fmt.tprintf("generated atlas for font '%s' has unsupported dimensions", name)
	}
	desc := Font_Desc {
		pixels = pixels,
		width = u32(metadata.atlas.width),
		height = u32(metadata.atlas.height),
		ascender = f32(abs(metadata.metrics.ascender)),
	}
	seen: [shared.FONT_CHAR_COUNT]bool
	for glyph in metadata.glyphs {
		if glyph.unicode < shared.FONT_FIRST_CHAR ||
		   glyph.unicode >= shared.FONT_FIRST_CHAR + shared.FONT_CHAR_COUNT { continue }
		index := glyph.unicode - shared.FONT_FIRST_CHAR
		desc.glyphs[index] = {
			advance = f32(glyph.advance),
			plane = {
				f32(glyph.plane_bounds.left),
				f32(glyph.plane_bounds.top),
				f32(glyph.plane_bounds.right),
				f32(glyph.plane_bounds.bottom),
			},
			uv = {
				f32(glyph.atlas_bounds.left / f64(metadata.atlas.width)),
				f32(glyph.atlas_bounds.top / f64(metadata.atlas.height)),
				f32(glyph.atlas_bounds.right / f64(metadata.atlas.width)),
				f32(glyph.atlas_bounds.bottom / f64(metadata.atlas.height)),
			},
		}
		seen[index] = true
	}
	for present, index in seen {
		if !present {
			return fmt.tprintf(
				"generated font '%s' is missing ASCII codepoint %d",
				name,
				index + shared.FONT_FIRST_CHAR,
			)
		}
	}
	_, register_err := register_font(registry, name, desc)
	return register_err
}

clone_font_desc :: proc(desc: Font_Desc, allocator: mem.Allocator) -> Font_Desc {
	result := desc
	result.pixels = clone_slice(desc.pixels, allocator)
	return result
}

register_geometry :: proc(
	registry: ^Registry,
	name: string,
	desc: Geometry_Desc,
) -> (
	Geometry_Handle,
	string,
) {
	if registry == nil { return {}, "geometry registry is not available" }
	ensure_allocator(registry)
	if err := validate_geometry(desc); err != "" { return {}, err }
	if index, found := geometry_index_by_name(registry, name); found {
		geometry := &registry.geometries[index]
		if geometry.authored {
			return {}, fmt.tprintf("geometry name '%s' belongs to a project resource and cannot be replaced at runtime", name)
		}
		had_lods := geometry.lod_count > 0
		delete(geometry.vertices, registry.allocator)
		delete(geometry.indices, registry.allocator)
		geometry.vertices = clone_slice(desc.vertices, registry.allocator)
		geometry.indices = clone_slice(desc.indices, registry.allocator)
		geometry.bounds = calculate_bounds(desc.vertices)
		geometry.lod_handles = {}
		geometry.lod_screen_radii = {}
		geometry.lod_count = 0
		geometry.version += 1
		if had_lods {
			registry.geometry_topology_revision += 1
		}
		return {u32(index), geometry.generation}, ""
	}
	cloned_name, clone_err := strings.clone(name, registry.allocator)
	if clone_err != nil { return {}, "failed to allocate geometry name" }
	append(
		&registry.geometries,
		Geometry {
			name = cloned_name,
			vertices = clone_slice(desc.vertices, registry.allocator),
			indices = clone_slice(desc.indices, registry.allocator),
			bounds = calculate_bounds(desc.vertices),
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	registry.geometry_topology_revision += 1
	return {u32(len(registry.geometries) - 1), 1}, ""
}

set_geometry_lods :: proc(
	registry: ^Registry,
	base: Geometry_Handle,
	lod_handles: []Geometry_Handle,
	screen_radii: []f32,
) -> string {
	geometry, alive := get_geometry(registry, base)
	if !alive {
		return "base geometry handle is stale"
	}
	if len(lod_handles) != len(screen_radii) || len(lod_handles) >= shared.MAX_GEOMETRY_LODS {
		return fmt.tprintf(
			"geometry LODs require matching handles and screen radii with at most %d alternatives",
			shared.MAX_GEOMETRY_LODS - 1,
		)
	}
	previous_radius := f32(3.402823e38)
	for handle, index in lod_handles {
		if _, lod_alive := get_geometry(registry, handle); !lod_alive {
			return fmt.tprintf("geometry LOD %d handle is stale", index + 1)
		}
		radius := screen_radii[index]
		if !finite(radius) || radius <= 0 || radius >= previous_radius {
			return "geometry LOD screen radii must be positive, finite, and strictly descending"
		}
		previous_radius = radius
	}
	geometry.lod_handles = {}
	geometry.lod_screen_radii = {}
	geometry.lod_count = len(lod_handles)
	copy(geometry.lod_handles[:], lod_handles)
	copy(geometry.lod_screen_radii[:], screen_radii)
	geometry.version += 1
	registry.geometry_topology_revision += 1
	return ""
}

register_project_lod_geometry :: proc(
	registry: ^Registry,
	declaration: shared.Project_Resource,
) -> (
	Geometry_Handle,
	string,
) {
	if registry == nil {
		return {}, "geometry registry is not available"
	}
	if declaration.kind != .Geometry_LOD || declaration.id == (shared.Resource_UUID{}) {
		return {}, "project LOD geometry declaration is invalid"
	}
	if declaration.name == "" || declaration.source == "" {
		return {}, "project LOD geometry requires a name and source"
	}
	definition := declaration.geometry_lod
	if definition.lod_count < 1 || definition.lod_count > shared.MAX_GEOMETRY_LODS {
		return {}, fmt.tprintf("project LOD geometry requires between 1 and %d levels", shared.MAX_GEOMETRY_LODS)
	}
	descriptions: [shared.MAX_GEOMETRY_LODS]Geometry_Desc
	defer {
		for index in 0 ..< definition.lod_count {
			delete(descriptions[index].vertices)
			delete(descriptions[index].indices)
		}
	}
	for index in 0 ..< definition.lod_count {
		desc, desc_err := icosphere(definition.radius, definition.subdivisions[index])
		if desc_err != "" {
			return {}, fmt.tprintf("LOD %d: %s", index, desc_err)
		}
		descriptions[index] = desc
	}
	ensure_allocator(registry)
	base_index, existing := geometry_index_by_uuid_any(registry, declaration.id)
	if !existing {
		if collision, found := geometry_index_by_name(registry, declaration.name);
		   found && registry.geometries[collision].id != declaration.id {
			return {}, fmt.tprintf("geometry name '%s' is already registered", declaration.name)
		}
		cloned_name, name_err := strings.clone(declaration.name, registry.allocator)
		if name_err != nil {
			return {}, "failed to allocate project geometry name"
		}
		cloned_source, source_err := strings.clone(declaration.source, registry.allocator)
		if source_err != nil {
			delete(cloned_name, registry.allocator)
			return {}, "failed to allocate project geometry source"
		}
		append(
			&registry.geometries,
			Geometry {
				id = declaration.id,
				name = cloned_name,
				source = cloned_source,
				authored = true,
				vertices = clone_slice(descriptions[0].vertices, registry.allocator),
				indices = clone_slice(descriptions[0].indices, registry.allocator),
				bounds = calculate_bounds(descriptions[0].vertices),
				generation = 1,
				version = 1,
				alive = true,
			},
		)
		registry.geometry_topology_revision += 1
		base_index = len(registry.geometries) - 1
	} else {
		geometry := &registry.geometries[base_index]
		if collision, found := geometry_index_by_name(registry, declaration.name);
		   found && collision != base_index {
			return {}, fmt.tprintf("geometry name '%s' is already registered", declaration.name)
		}
		cloned_name, name_err := strings.clone(declaration.name, registry.allocator)
		if name_err != nil {
			return {}, "failed to allocate project geometry name"
		}
		cloned_source, source_err := strings.clone(declaration.source, registry.allocator)
		if source_err != nil {
			delete(cloned_name, registry.allocator)
			return {}, "failed to allocate project geometry source"
		}
		delete(geometry.name, registry.allocator)
		delete(geometry.source, registry.allocator)
		delete(geometry.vertices, registry.allocator)
		delete(geometry.indices, registry.allocator)
		geometry.name = cloned_name
		geometry.source = cloned_source
		geometry.vertices = clone_slice(descriptions[0].vertices, registry.allocator)
		geometry.indices = clone_slice(descriptions[0].indices, registry.allocator)
		geometry.bounds = calculate_bounds(descriptions[0].vertices)
		geometry.authored = true
		geometry.alive = true
		geometry.version += 1
	}
	base := Geometry_Handle{u32(base_index), registry.geometries[base_index].generation}
	lod_handles: [shared.MAX_GEOMETRY_LODS - 1]Geometry_Handle
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(declaration.id, id_buffer[:])
	for index in 1 ..< definition.lod_count {
		internal_name := fmt.tprintf("__project_lod_%s_%d", id_text, index)
		handle, register_err := register_geometry(registry, internal_name, descriptions[index])
		if register_err != "" {
			return {}, register_err
		}
		lod_handles[index - 1] = handle
	}
	if lod_err := set_geometry_lods(
		registry,
		base,
		lod_handles[:definition.lod_count - 1],
		definition.screen_radii[:definition.lod_count - 1],
	); lod_err != "" {
		return {}, lod_err
	}
	return base, ""
}

register_project_lod_geometries :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
) -> string {
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Geometry_LOD {
			continue
		}
		if _, err := register_project_lod_geometry(registry, declaration); err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, err)
		}
		seen[declaration.id] = true
	}
	for &geometry in registry.geometries {
		if geometry.authored && !seen[geometry.id] {
			geometry.alive = false
			geometry.generation += 1
			geometry.version += 1
			registry.geometry_topology_revision += 1
		}
	}
	return ""
}

register_material :: proc(
	registry: ^Registry,
	name: string,
	desc: Material_Desc,
) -> (
	Material_Handle,
	string,
) {
	if registry == nil { return {}, "material registry is not available" }
	ensure_allocator(registry)
	if name == "" { return {}, "material name must not be empty" }
	if err := validate_material_desc(desc); err != "" {
		return {}, err
	}
	if index, found := material_index_by_name(registry, name); found {
		material := &registry.materials[index]
		if material.authored {
			return {}, fmt.tprintf("material name '%s' belongs to a project resource and cannot be replaced at runtime", name)
		}
		delete(material.desc.texture_pixels, registry.allocator)
		material.desc = clone_material_desc(desc, registry.allocator)
		material.version += 1
		return {u32(index), material.generation}, ""
	}
	cloned_name, clone_err := strings.clone(name, registry.allocator)
	if clone_err != nil { return {}, "failed to allocate material name" }
	append(
		&registry.materials,
		Material {
			name = cloned_name,
			desc = clone_material_desc(desc, registry.allocator),
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	return {u32(len(registry.materials) - 1), 1}, ""
}

register_project_material :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
	name, source: string,
	desc: Material_Desc,
	texture_asset: string = "",
) -> (
	Material_Handle,
	string,
) {
	if registry == nil {
		return {}, "material registry is not available"
	}
	if id == (shared.Resource_UUID{}) {
		return {}, "project material UUID must not be empty"
	}
	if source == "" {
		return {}, "project material source must not be empty"
	}
	if err := validate_material_desc(desc); err != "" {
		return {}, err
	}
	ensure_allocator(registry)
	if index, found := material_index_by_uuid_any(registry, id); found {
		material := &registry.materials[index]
		cloned_name, name_err := strings.clone(name, registry.allocator)
		if name_err != nil {
			return {}, "failed to allocate material name"
		}
		cloned_source, source_err := strings.clone(source, registry.allocator)
		if source_err != nil {
			delete(cloned_name, registry.allocator)
			return {}, "failed to allocate material source"
		}
		cloned_texture, texture_err := strings.clone(texture_asset, registry.allocator)
		if texture_err != nil {
			delete(cloned_name, registry.allocator)
			delete(cloned_source, registry.allocator)
			return {}, "failed to allocate material texture path"
		}
		delete(material.name, registry.allocator)
		delete(material.source, registry.allocator)
		delete(material.texture_asset, registry.allocator)
		delete(material.desc.texture_pixels, registry.allocator)
		material.name = cloned_name
		material.source = cloned_source
		material.texture_asset = cloned_texture
		material.authored = true
		material.desc = clone_material_desc(desc, registry.allocator)
		material.alive = true
		material.version += 1
		return {u32(index), material.generation}, ""
	}
	if _, found := material_index_by_name(registry, name); found {
		return {}, fmt.tprintf("material name '%s' is already registered", name)
	}
	cloned_name, name_err := strings.clone(name, registry.allocator)
	if name_err != nil {
		return {}, "failed to allocate material name"
	}
	cloned_source, source_err := strings.clone(source, registry.allocator)
	if source_err != nil {
		delete(cloned_name, registry.allocator)
		return {}, "failed to allocate material source"
	}
	cloned_texture, texture_err := strings.clone(texture_asset, registry.allocator)
	if texture_err != nil {
		delete(cloned_name, registry.allocator)
		delete(cloned_source, registry.allocator)
		return {}, "failed to allocate material texture path"
	}
	append(
		&registry.materials,
		Material {
			id = id,
			name = cloned_name,
			source = cloned_source,
			texture_asset = cloned_texture,
			authored = true,
			desc = clone_material_desc(desc, registry.allocator),
			generation = 1,
			version = 1,
			alive = true,
		},
	)
	return {u32(len(registry.materials) - 1), 1}, ""
}

capture_project_material :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	^Project_Material_Snapshot,
	bool,
) {
	if registry == nil {
		return nil, false
	}
	index, found := material_index_by_uuid_any(registry, id)
	if !found || !registry.materials[index].alive {
		return nil, false
	}
	material := registry.materials[index]
	snapshot := new(Project_Material_Snapshot)
	snapshot.id = material.id
	snapshot.name, _ = strings.clone(material.name)
	snapshot.source, _ = strings.clone(material.source)
	snapshot.texture_asset, _ = strings.clone(material.texture_asset)
	snapshot.desc = clone_material_desc(material.desc, context.allocator)
	return snapshot, true
}

clone_project_material_snapshot :: proc(
	source: ^Project_Material_Snapshot,
) -> ^Project_Material_Snapshot {
	if source == nil {
		return nil
	}
	result := new(Project_Material_Snapshot)
	result.id = source.id
	result.name, _ = strings.clone(source.name)
	result.source, _ = strings.clone(source.source)
	result.texture_asset, _ = strings.clone(source.texture_asset)
	result.desc = clone_material_desc(source.desc, context.allocator)
	return result
}

destroy_project_material_snapshot :: proc(snapshot: ^Project_Material_Snapshot) {
	if snapshot == nil {
		return
	}
	delete(snapshot.name)
	delete(snapshot.source)
	delete(snapshot.texture_asset)
	delete(snapshot.desc.texture_pixels)
	snapshot^ = {}
}

valid_project_resource_source :: proc(source: string) -> bool {
	if source == "" || filepath.is_abs(source) || !strings.has_suffix(source, ".resource.toml") {
		return false
	}
	segment_start := 0
	for value, index in source {
		if value == '\\' {
			return false
		}
		if value != '/' {
			continue
		}
		segment := source[segment_start:index]
		if segment == "" || segment == "." || segment == ".." {
			return false
		}
		segment_start = index + 1
	}
	segment := source[segment_start:]
	return segment != "" && segment != "." && segment != ".."
}

validate_project_material_identity :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
	name, source: string,
) -> string {
	if registry == nil {
		return "material registry is not available"
	}
	if strings.trim_space(name) == "" ||
	   strings.contains(name, "\n") ||
	   strings.contains(name, "\"") {
		return "material name must be non-empty and contain no quotes or newlines"
	}
	if !valid_project_resource_source(source) {
		return "material source must be a relative .resource.toml path under resources/"
	}
	for material in registry.materials {
		if !material.alive || !material.authored || material.id == id {
			continue
		}
		if material.name == name {
			return fmt.tprintf("material name '%s' is already used", name)
		}
		if material.source == source {
			return fmt.tprintf("material source '%s' is already used", source)
		}
	}
	return ""
}

apply_project_material_snapshot :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
	snapshot: ^Project_Material_Snapshot,
) -> string {
	if registry == nil {
		return "material registry is not available"
	}
	if snapshot == nil {
		index, found := material_index_by_uuid_any(registry, id)
		if !found || !registry.materials[index].alive {
			return "project material does not exist"
		}
		material := &registry.materials[index]
		material.alive = false
		material.generation += 1
		material.version += 1
		return ""
	}
	if snapshot.id != id {
		return "project material snapshot UUID does not match"
	}
	if err := validate_project_material_identity(registry, id, snapshot.name, snapshot.source);
	   err != "" {
		return err
	}
	_, err := register_project_material(
		registry,
		snapshot.id,
		snapshot.name,
		snapshot.source,
		snapshot.desc,
		snapshot.texture_asset,
	)
	return err
}

unique_project_material_identity :: proc(
	registry: ^Registry,
	base_name, base_source: string,
) -> (
	name, source: string,
) {
	for ordinal := 1; ordinal < 10000; ordinal += 1 {
		candidate_name := base_name
		candidate_source := base_source
		if ordinal > 1 {
			candidate_name = fmt.tprintf("%s %d", base_name, ordinal)
			stem := base_source[:len(base_source) - len(".resource.toml")]
			candidate_source = fmt.tprintf("%s-%d.resource.toml", stem, ordinal)
		}
		if validate_project_material_identity(registry, {}, candidate_name, candidate_source) ==
		   "" {
			name, _ = strings.clone(candidate_name)
			source, _ = strings.clone(candidate_source)
			return
		}
	}
	return
}

register_project_materials :: proc(
	registry: ^Registry,
	root: string,
	declarations: []shared.Project_Resource,
) -> string {
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	names := make(map[string]shared.Resource_UUID)
	defer delete(names)
	prepared := make([dynamic]Prepared_Project_Material)
	defer {
		for item in prepared {
			delete(item.desc.texture_pixels)
		}
		delete(prepared)
	}
	for declaration, declaration_index in declarations {
		if declaration.kind != .Material {
			continue
		}
		seen[declaration.id] = true
		if existing_id, duplicate_name := names[declaration.name];
		   duplicate_name && existing_id != declaration.id {
			return fmt.tprintf(
				"resources/%s: material name '%s' is already used by another project resource",
				declaration.source,
				declaration.name,
			)
		}
		names[declaration.name] = declaration.id
		if existing_index, found := material_index_by_name(registry, declaration.name);
		   found && registry.materials[existing_index].id != declaration.id {
			return fmt.tprintf(
				"resources/%s: material name '%s' is already registered",
				declaration.source,
				declaration.name,
			)
		}
		desc := Material_Desc {
			base_color = {
				declaration.material.base_color.x,
				declaration.material.base_color.y,
				declaration.material.base_color.z,
				declaration.material.base_color.w,
			},
			emissive = declaration.material.emissive,
		}
		if declaration.material.texture != "" {
			texture_desc, texture_err := load_material_texture(
				root,
				declaration.material.texture,
				desc.base_color,
				desc.emissive,
			)
			if texture_err != "" {
				return fmt.tprintf("resources/%s: %s", declaration.source, texture_err)
			}
			desc = texture_desc
		}
		append(
			&prepared,
			Prepared_Project_Material{declaration_index = declaration_index, desc = desc},
		)
	}
	for item in prepared {
		declaration := declarations[item.declaration_index]
		_, register_err := register_project_material(
			registry,
			declaration.id,
			declaration.name,
			declaration.source,
			item.desc,
			declaration.material.texture,
		)
		if register_err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, register_err)
		}
	}
	for &material in registry.materials {
		if !material.alive || !material.authored {
			continue
		}
		if !seen[material.id] {
			material.alive = false
			material.generation += 1
			material.version += 1
		}
	}
	return ""
}

save_project_materials :: proc(
	registry: ^Registry,
	root: string,
	ids: []shared.Resource_UUID,
) -> string {
	files: [dynamic]project.Save_File
	defer project.destroy_owned_save_files(&files)
	if err := prepare_project_material_save_files(registry, root, ids, &files); err != "" {
		return err
	}
	return project.commit_project_save(root, files[:])
}

prepare_project_material_save_files :: proc(
	registry: ^Registry,
	root: string,
	ids: []shared.Resource_UUID,
	files: ^[dynamic]project.Save_File,
) -> string {
	if registry == nil {
		return "resource registry is not available"
	}
	if files == nil {
		return "project save file collection is not available"
	}
	baseline, load_err := project.load_project_resources(root)
	_ = load_err
	defer project.destroy_project_resources(&baseline)
	seen := make(map[shared.Resource_UUID]bool, len(ids))
	defer delete(seen)
	for id in ids {
		if seen[id] {
			continue
		}
		seen[id] = true
		baseline_source := ""
		for declaration in baseline {
			if declaration.kind == .Material && declaration.id == id {
				baseline_source = declaration.source
				break
			}
		}
		material: ^Material
		current_alive := false
		if index, found := material_index_by_uuid_any(registry, id); found {
			material = &registry.materials[index]
			current_alive = material.alive && material.authored
		}
		if baseline_source == "" && current_alive {
			current_path, join_err := filepath.join(
				{root, shared.PROJECT_RESOURCES_DIR, material.source},
			)
			if join_err != nil {
				return "failed to allocate current project material path"
			}
			if os.exists(current_path) {
				baseline_source = material.source
			}
			delete(current_path)
		}
		if baseline_source == "" && !current_alive {
			continue
		}
		if baseline_source != "" && (!current_alive || material.source != baseline_source) {
			old_path, join_err := filepath.join(
				{root, shared.PROJECT_RESOURCES_DIR, baseline_source},
			)
			if join_err != nil {
				return "failed to allocate old project material path"
			}
			append(files, project.Save_File{path = old_path, action = .Delete})
		}
		if !current_alive {
			continue
		}
		if err := validate_project_material_identity(
			registry,
			material.id,
			material.name,
			material.source,
		); err != "" {
			return err
		}
		resource_path, join_err := filepath.join(
			{root, shared.PROJECT_RESOURCES_DIR, material.source},
		)
		if join_err != nil {
			return "failed to allocate project material path"
		}
		builder := strings.builder_make()
		id_buffer: [36]u8
		fmt.sbprintf(
			&builder,
			`id = "%s"
type = "scrapbot.material"
name = "%s"

[material]
base_color = [%.9g, %.9g, %.9g, %.9g]
emissive = [%.9g, %.9g, %.9g]
`,
			shared.resource_uuid_to_string(material.id, id_buffer[:]),
			material.name,
			material.desc.base_color.x,
			material.desc.base_color.y,
			material.desc.base_color.z,
			material.desc.base_color.w,
			material.desc.emissive.x,
			material.desc.emissive.y,
			material.desc.emissive.z,
		)
		if material.texture_asset != "" {
			fmt.sbprintf(&builder, "texture = \"%s\"\n", material.texture_asset)
		}
		source, clone_err := strings.clone(strings.to_string(builder))
		strings.builder_destroy(&builder)
		if clone_err != nil {
			delete(resource_path)
			return "failed to allocate project material source"
		}
		parsed, parse_result := project.parse_project_resource(source)
		if parse_result.err != .None {
			delete(source)
			delete(resource_path)
			return fmt.tprintf(
				"refusing to replace resource with invalid generated TOML: %s",
				parse_result.message,
			)
		}
		if parsed.id != material.id ||
		   parsed.kind != .Material ||
		   parsed.name != material.name ||
		   parsed.material.base_color != shared.Vec4(material.desc.base_color) ||
		   parsed.material.emissive != material.desc.emissive ||
		   parsed.material.texture != material.texture_asset {
			delete(source)
			delete(resource_path)
			return "generated project material changed meaning during serialization"
		}
		append(
			files,
			project.Save_File {
				path = resource_path,
				source = source,
				expect_missing = baseline_source == "" || baseline_source != material.source,
			},
		)
	}
	return ""
}

register_textured_material :: proc(
	registry: ^Registry,
	root, name, asset_path: string,
	base_color: Vec4,
) -> (
	Material_Handle,
	string,
) {
	desc, load_err := load_material_texture(root, asset_path, base_color, {})
	if load_err != "" {
		return {}, load_err
	}
	defer delete(desc.texture_pixels)
	return register_material(registry, name, desc)
}

load_material_texture :: proc(
	root, asset_path: string,
	base_color: Vec4,
	emissive: Vec3,
) -> (
	Material_Desc,
	string,
) {
	if !valid_asset_path(asset_path) {
		return {}, "texture path must be a relative .png file under assets/"
	}
	path, join_err := filepath.join({root, asset_path})
	if join_err != nil {
		return {}, "failed to allocate texture asset path"
	}
	defer delete(path)
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return {}, fmt.tprintf("failed to read texture asset %s: %v", asset_path, read_err)
	}
	if len(data) == 0 {
		return {}, fmt.tprintf("texture asset is empty: %s", asset_path)
	}
	x, y, channels: c.int
	pixels := stb.load_from_memory(raw_data(data), c.int(len(data)), &x, &y, &channels, 4)
	if pixels == nil {
		return {}, fmt.tprintf("failed to decode texture asset %s: %s", asset_path, string(stb.failure_reason()))
	}
	defer stb.image_free(pixels)
	if x <= 0 || y <= 0 || x > 8192 || y > 8192 {
		return {}, fmt.tprintf("texture asset dimensions are unsupported: %s", asset_path)
	}
	owned_pixels := clone_slice(pixels[:int(x * y * 4)])
	return Material_Desc {
			base_color = base_color,
			emissive = emissive,
			texture_pixels = owned_pixels,
			texture_width = u32(x),
			texture_height = u32(y),
		},
		""
}

valid_asset_path :: proc(path: string) -> bool {
	if !strings.has_prefix(path, "assets/") ||
	   !strings.has_suffix(path, ".png") ||
	   filepath.is_abs(path) { return false }
	remaining := path
	for part in strings.split_iterator(&remaining, "/") { if part == ".." { return false } }
	return true
}

clone_material_desc :: proc(desc: Material_Desc, allocator: mem.Allocator) -> Material_Desc {
	result := desc
	result.texture_pixels = clone_slice(desc.texture_pixels, allocator)
	return result
}

get_geometry :: proc(registry: ^Registry, handle: Geometry_Handle) -> (^Geometry, bool) {
	if registry == nil || int(handle.index) >= len(registry.geometries) { return nil, false }
	geometry := &registry.geometries[handle.index]
	return geometry, geometry.alive && geometry.generation == handle.generation
}

get_material :: proc(registry: ^Registry, handle: Material_Handle) -> (^Material, bool) {
	if registry == nil || int(handle.index) >= len(registry.materials) { return nil, false }
	material := &registry.materials[handle.index]
	return material, material.alive && material.generation == handle.generation
}

get_font :: proc(registry: ^Registry, handle: Font_Handle) -> (^Font, bool) {
	if registry == nil || int(handle.index) >= len(registry.fonts) { return nil, false }
	font := &registry.fonts[handle.index]
	return font, font.alive && font.generation == handle.generation
}

geometry_by_name :: proc(registry: ^Registry, name: string) -> (Geometry_Handle, bool) {
	index, found := geometry_index_by_name(registry, name)
	if !found { return {}, false }
	return {u32(index), registry.geometries[index].generation}, true
}

geometry_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Geometry_Handle,
	bool,
) {
	index, found := geometry_index_by_uuid(registry, id)
	if !found {
		return {}, false
	}
	return {u32(index), registry.geometries[index].generation}, true
}

material_by_name :: proc(registry: ^Registry, name: string) -> (Material_Handle, bool) {
	index, found := material_index_by_name(registry, name)
	if !found { return {}, false }
	return {u32(index), registry.materials[index].generation}, true
}

material_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Material_Handle,
	bool,
) {
	index, found := material_index_by_uuid(registry, id)
	if !found {
		return {}, false
	}
	return {u32(index), registry.materials[index].generation}, true
}

font_by_name :: proc(registry: ^Registry, name: string) -> (Font_Handle, bool) {
	index, found := font_index_by_name(registry, name)
	if !found { return {}, false }
	return {u32(index), registry.fonts[index].generation}, true
}

geometry_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	for geometry, index in registry.geometries { if geometry.alive && geometry.name == name { return index, true } }
	return -1, false
}

geometry_index_by_uuid :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for geometry, index in registry.geometries {
		if geometry.alive && geometry.authored && geometry.id == id {
			return index, true
		}
	}
	return -1, false
}

geometry_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for geometry, index in registry.geometries {
		if geometry.authored && geometry.id == id {
			return index, true
		}
	}
	return -1, false
}

material_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	for material, index in registry.materials { if material.alive && material.name == name { return index, true } }
	return -1, false
}

material_index_by_uuid :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for material, index in registry.materials {
		if material.alive && material.authored && material.id == id {
			return index, true
		}
	}
	return -1, false
}

material_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for material, index in registry.materials {
		if material.authored && material.id == id {
			return index, true
		}
	}
	return -1, false
}

validate_material_desc :: proc(desc: Material_Desc) -> string {
	if !finite4(desc.base_color) {
		return "material base color must be finite"
	}
	if !finite3(desc.emissive) ||
	   desc.emissive.x < 0 ||
	   desc.emissive.y < 0 ||
	   desc.emissive.z < 0 {
		return "material emissive color must be finite and non-negative"
	}
	if len(desc.texture_pixels) > 0 {
		if desc.texture_width == 0 || desc.texture_height == 0 {
			return "material texture dimensions must be positive"
		}
		if len(desc.texture_pixels) != int(desc.texture_width * desc.texture_height * 4) {
			return "material texture must contain RGBA8 pixels"
		}
	}
	return ""
}

font_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	if registry == nil { return -1, false }
	for font, index in registry.fonts {
		if font.alive && font.name == name { return index, true }
	}
	return -1, false
}

validate_geometry :: proc(desc: Geometry_Desc) -> string {
	if len(desc.vertices) == 0 { return "geometry must contain vertices" }
	if len(desc.indices) == 0 ||
	   len(desc.indices) % 3 != 0 { return "geometry indices must contain triangle lists" }
	for vertex in desc.vertices {
		if !finite3(vertex.position) ||
		   !finite3(vertex.normal) ||
		   !finite2(vertex.uv) { return "geometry vertex values must be finite" }
	}
	for index in desc.indices { if int(index) >= len(desc.vertices) { return "geometry index is outside the vertex array" } }
	return ""
}

calculate_bounds :: proc(vertices: []Vertex) -> Bounds {
	bounds := Bounds {
		min = vertices[0].position,
		max = vertices[0].position,
	}
	for vertex in vertices[1:] {
		bounds.min.x = min(
			bounds.min.x,
			vertex.position.x,
		); bounds.min.y = min(bounds.min.y, vertex.position.y); bounds.min.z = min(bounds.min.z, vertex.position.z)
		bounds.max.x = max(
			bounds.max.x,
			vertex.position.x,
		); bounds.max.y = max(bounds.max.y, vertex.position.y); bounds.max.z = max(bounds.max.z, vertex.position.z)
	}
	return bounds
}

finite :: proc(v: f32) -> bool { return !math.is_nan(v) && !math.is_inf(v) }
finite2 :: proc(v: Vec2) -> bool { return finite(v.x) && finite(v.y) }
finite3 :: proc(v: Vec3) -> bool { return finite(v.x) && finite(v.y) && finite(v.z) }
finite4 :: proc(v: Vec4) -> bool {
	return finite(v.x) && finite(v.y) && finite(v.z) && finite(v.w)
}

clone_slice :: proc(values: []$T, allocator := context.allocator) -> []T {
	result := make([]T, len(values), allocator); copy(result, values); return result
}

cube :: proc(size: f32 = 1) -> (Geometry_Desc, string) {
	if !finite(size) || size <= 0 { return {}, "cube size must be positive and finite" }
	h := size / 2
	vertices := make([]Vertex, 24)
	positions := [8]Vec3 {
		{-h, -h, -h},
		{h, -h, -h},
		{h, h, -h},
		{-h, h, -h},
		{-h, -h, h},
		{h, -h, h},
		{h, h, h},
		{-h, h, h},
	}
	faces := [6][4]u32 {
		{4, 5, 6, 7},
		{1, 0, 3, 2},
		{0, 4, 7, 3},
		{5, 1, 2, 6},
		{3, 7, 6, 2},
		{0, 1, 5, 4},
	}
	normals := [6]Vec3{{0, 0, 1}, {0, 0, -1}, {-1, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}}
	uvs := [4]Vec2{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	for face in 0 ..< 6 { for corner in 0 ..< 4 { vertices[face * 4 + corner] = {positions[faces[face][corner]], normals[face], uvs[corner]} } }
	indices := make([]u32, 36)
	for face in 0 ..< 6 {
		base := u32(face * 4); offset := face * 6
		face_indices := [6]u32{base, base + 1, base + 2, base, base + 2, base + 3}
		for value, index in face_indices { indices[offset + index] = value }
	}
	return {vertices, indices}, ""
}

plane :: proc(width: f32 = 1, depth: f32 = 1) -> (Geometry_Desc, string) {
	if !finite(width) ||
	   !finite(depth) ||
	   width <= 0 ||
	   depth <= 0 { return {}, "plane dimensions must be positive and finite" }
	w, d := width / 2, depth / 2
	vertices := make([]Vertex, 4)
	vertices[0] = {{-w, 0, -d}, {0, 1, 0}, {0, 0}}; vertices[1] = {{w, 0, -d}, {0, 1, 0}, {1, 0}}
	vertices[2] = {{w, 0, d}, {0, 1, 0}, {1, 1}}; vertices[3] = {{-w, 0, d}, {0, 1, 0}, {0, 1}}
	indices := make([]u32, 6)
	copy(indices, []u32{0, 1, 2, 0, 2, 3})
	return {vertices, indices}, ""
}

pyramid :: proc(width: f32 = 1, height: f32 = 1, depth: f32 = 1) -> (Geometry_Desc, string) {
	if !finite(width) ||
	   !finite(height) ||
	   !finite(depth) ||
	   width <= 0 ||
	   height <= 0 ||
	   depth <= 0 {
		return {}, "pyramid dimensions must be positive and finite"
	}
	w, h, d := width / 2, height / 2, depth / 2
	vertices := make([]Vertex, 16)
	indices := make([]u32, 18)
	base := [4]Vec3{{-w, -h, -d}, {w, -h, -d}, {w, -h, d}, {-w, -h, d}}
	uvs := [3]Vec2{{0, 0}, {1, 0}, {0.5, 1}}
	for i in 0 ..< 4 {
		next := (i + 1) % 4
		a, b, apex := base[i], base[next], Vec3{0, h, 0}
		normal := normalize(cross(sub(b, a), sub(apex, a)))
		vertices[i * 3 + 0] = {a, normal, uvs[0]}
		vertices[i * 3 + 1] = {b, normal, uvs[1]}
		vertices[i * 3 + 2] = {apex, normal, uvs[2]}
		indices[i * 3 + 0] = u32(
			i * 3,
		); indices[i * 3 + 1] = u32(i * 3 + 1); indices[i * 3 + 2] = u32(i * 3 + 2)
	}
	base_offset := 12
	base_uvs := [4]Vec2{{0, 0}, {0, 1}, {1, 1}, {1, 0}}
	for i in 0 ..< 4 { vertices[base_offset + i] = {base[i], {0, -1, 0}, base_uvs[i]} }
	copy(indices[12:], []u32{12, 14, 13, 12, 15, 14})
	return {vertices, indices}, ""
}

cylinder :: proc(
	radius: f32 = 0.5,
	height: f32 = 1,
	segments: int = 24,
) -> (
	Geometry_Desc,
	string,
) {
	if !finite(radius) ||
	   !finite(height) ||
	   radius <= 0 ||
	   height <= 0 { return {}, "cylinder dimensions must be positive and finite" }
	if segments < 3 || segments > 256 { return {}, "cylinder segments must be between 3 and 256" }
	vertex_count := (segments + 1) * 2 + (segments + 1) * 2
	vertices := make([]Vertex, vertex_count)
	indices := make([]u32, segments * 12)
	h := height / 2
	for i in 0 ..= segments {
		u := f32(i) / f32(segments); angle := u * 2 * math.PI
		x, z := math.cos(angle) * radius, math.sin(angle) * radius
		normal := Vec3{x, 0, z}; normal = normalize(normal)
		vertices[i * 2] = {{x, -h, z}, normal, {u, 0}}
		vertices[i * 2 + 1] = {{x, h, z}, normal, {u, 1}}
	}
	for i in 0 ..< segments {
		v := u32(i * 2); o := i * 6
		copy(indices[o:o + 6], []u32{v, v + 1, v + 3, v, v + 3, v + 2})
	}
	cap_start := (segments + 1) * 2
	for cap in 0 ..< 2 {
		y := -h if cap == 0 else h
		normal := Vec3{0, -1, 0} if cap == 0 else Vec3{0, 1, 0}
		offset := cap_start + cap * (segments + 1)
		vertices[offset] = {{0, y, 0}, normal, {0.5, 0.5}}
		for i in 0 ..< segments {
			angle := f32(i) * 2 * math.PI / f32(segments)
			x, z := math.cos(angle) * radius, math.sin(angle) * radius
			vertices[offset + 1 + i] = {
				{x, y, z},
				normal,
				{x / (2 * radius) + 0.5, z / (2 * radius) + 0.5},
			}
			next := (i + 1) % segments; o := segments * 6 + (cap * segments + i) * 3
			if cap ==
			   0 {copy(indices[o:o + 3], []u32{u32(offset), u32(offset + 1 + next), u32(offset + 1 + i)})
			} else {copy(
					indices[o:o + 3],
					[]u32{u32(offset), u32(offset + 1 + i), u32(offset + 1 + next)},
				)}
		}
	}
	return {vertices, indices}, ""
}

sphere :: proc(radius: f32 = 0.5, segments: int = 24, rings: int = 16) -> (Geometry_Desc, string) {
	if !finite(radius) || radius <= 0 { return {}, "sphere radius must be positive and finite" }
	if segments < 3 || segments > 256 { return {}, "sphere segments must be between 3 and 256" }
	if rings < 2 || rings > 256 { return {}, "sphere rings must be between 2 and 256" }
	vertices := make([]Vertex, (rings + 1) * (segments + 1))
	indices := make([]u32, segments * (rings - 1) * 6)
	for ring in 0 ..= rings {
		v := f32(ring) / f32(rings); phi := v * math.PI
		for segment in 0 ..= segments {
			u := f32(segment) / f32(segments); theta := u * 2 * math.PI
			normal := Vec3 {
				math.sin(phi) * math.cos(theta),
				math.cos(phi),
				math.sin(phi) * math.sin(theta),
			}
			vertices[ring * (segments + 1) + segment] = {mul(normal, radius), normal, {u, v}}
		}
	}
	offset := 0
	for ring in 0 ..< rings {for segment in 0 ..< segments {
			a := u32(ring * (segments + 1) + segment); b := a + u32(segments + 1)
			if ring != 0 { copy(indices[offset:offset + 3], []u32{a, b, a + 1}); offset += 3 }
			if ring !=
			   rings - 1 { copy(indices[offset:offset + 3], []u32{a + 1, b, b + 1}); offset += 3 }
		}}
	return {vertices, indices}, ""
}

icosphere :: proc(radius: f32 = 0.5, subdivisions: int = 2) -> (Geometry_Desc, string) {
	if !finite(radius) || radius <= 0 { return {}, "icosphere radius must be positive and finite" }
	if subdivisions < 0 ||
	   subdivisions > 4 { return {}, "icosphere subdivisions must be between 0 and 4" }
	t := (f32(1) + math.sqrt(f32(5))) / 2
	positions := [dynamic]Vec3{}
	defer delete(positions)
	base := [12]Vec3 {
		{-1, t, 0},
		{1, t, 0},
		{-1, -t, 0},
		{1, -t, 0},
		{0, -1, t},
		{0, 1, t},
		{0, -1, -t},
		{0, 1, -t},
		{t, 0, -1},
		{t, 0, 1},
		{-t, 0, -1},
		{-t, 0, 1},
	}
	for value in base { append(&positions, normalize(value)) }
	indices := make([dynamic]u32, 0, 60)
	defer delete(indices)
	copy_faces := [60]u32 {
		0,
		11,
		5,
		0,
		5,
		1,
		0,
		1,
		7,
		0,
		7,
		10,
		0,
		10,
		11,
		1,
		5,
		9,
		5,
		11,
		4,
		11,
		10,
		2,
		10,
		7,
		6,
		7,
		1,
		8,
		3,
		9,
		4,
		3,
		4,
		2,
		3,
		2,
		6,
		3,
		6,
		8,
		3,
		8,
		9,
		4,
		9,
		5,
		2,
		4,
		11,
		6,
		2,
		10,
		8,
		6,
		7,
		9,
		8,
		1,
	}
	append(&indices, ..copy_faces[:])
	for _ in 0 ..< subdivisions {
		next := make([dynamic]u32, 0, len(indices) * 4)
		for i := 0; i < len(indices); i += 3 {
			a, b, c := indices[i], indices[i + 1], indices[i + 2]
			ab := u32(
				len(positions),
			); append(&positions, normalize(add(positions[a], positions[b])))
			bc := u32(
				len(positions),
			); append(&positions, normalize(add(positions[b], positions[c])))
			ca := u32(
				len(positions),
			); append(&positions, normalize(add(positions[c], positions[a])))
			append(&next, a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca)
		}
		delete(indices); indices = next
	}
	vertices := make([]Vertex, len(positions))
	for position, i in positions {
		u :=
			0.5 +
			math.atan2(position.z, position.x) /
				(2 * math.PI); v := 0.5 - math.asin(position.y) / math.PI
		vertices[i] = {mul(position, radius), position, {u, v}}
	}
	result_indices := clone_slice(indices[:])
	return {vertices, result_indices}, ""
}

add :: proc(a, b: Vec3) -> Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
sub :: proc(a, b: Vec3) -> Vec3 { return {a.x - b.x, a.y - b.y, a.z - b.z} }
mul :: proc(a: Vec3, scalar: f32) -> Vec3 { return {a.x * scalar, a.y * scalar, a.z * scalar} }
cross :: proc(a, b: Vec3) -> Vec3 {return{
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}}
normalize :: proc(v: Vec3) -> Vec3 {length := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	return {v.x / length, v.y / length, v.z / length}}
