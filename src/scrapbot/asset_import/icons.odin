package asset_import

import shared "../shared"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

ICON_SET_IMPORTER_SCHEMA :: "scrapbot.icon-set.v2.mtsdf-512-96-8"
ICON_SET_ATLAS_SIZE :: 512
ICON_SET_EM_SIZE :: 96
ICON_SET_DISTANCE_RANGE :: 8
MAX_ICON_SET_SYMBOLS :: 256

Icon_Source :: struct {
	relative_path: string,
	full_path: string,
}

Icon_Symbol_Metadata :: struct {
	name: string,
	codepoint: int,
	uv: [4]f32,
	plane: [4]f32,
}

Icon_Set_Metadata :: struct {
	schema: string,
	source: string,
	source_hash: u64,
	width, height: u32,
	byte_count: int,
	symbol_count: int,
	symbols: [dynamic]Icon_Symbol_Metadata,
}

Icon_Compiler_Symbol :: struct {
	name: string,
	codepoint: int,
}

Icon_Compiler_Map :: struct {
	symbol_count: int,
	symbols: [dynamic]Icon_Compiler_Symbol,
}

Icon_Atlas_Bounds :: struct {
	left, top, right, bottom: f32,
}

Icon_Atlas_Glyph :: struct {
	unicode: int,
	atlas_bounds: Icon_Atlas_Bounds `json:"atlasBounds"`,
	plane_bounds: Icon_Atlas_Bounds `json:"planeBounds"`,
}

Icon_Atlas_Description :: struct {
	glyphs: [dynamic]Icon_Atlas_Glyph,
}

ensure_icon_set_import :: proc(
	root, build_dir: string,
	declaration: shared.Project_Resource,
	force: bool = false,
) -> (
	product: Product,
	imported: bool,
	err: string,
) {
	source_path, join_err := filepath.join({root, declaration.icon_set.source})
	if join_err != nil {
		return {}, false, "failed to allocate icon-set source path"
	}
	defer delete(source_path)
	sources, source_hash, source_err := discover_icon_sources(source_path)
	if source_err != "" {
		return {}, false, fmt.tprintf("failed to import icon set %s: %s", declaration.icon_set.source, source_err)
	}
	defer destroy_icon_sources(&sources)
	source_hash = hash.fnv64a(transmute([]byte)(string(ICON_SET_IMPORTER_SCHEMA)), source_hash)
	artifact_path, metadata_path, paths_err := icon_set_product_paths(build_dir, declaration.id)
	if paths_err != "" {
		return {}, false, paths_err
	}
	defer delete(artifact_path)
	defer delete(metadata_path)
	metadata, cache_hit := read_icon_set_cache(
		artifact_path,
		metadata_path,
		declaration,
		source_hash,
	)
	if force {
		cache_hit = false
	}
	if !cache_hit {
		generated, generate_err := compile_icon_set_product(
			source_path,
			build_dir,
			declaration,
			source_hash,
		)
		if generate_err != "" {
			return {}, false, generate_err
		}
		defer delete(generated.symbols)
		metadata = generated
		metadata_bytes, marshal_err := json.marshal(metadata)
		if marshal_err != nil {
			return {}, false, "failed to encode icon-set import metadata"
		}
		defer delete(metadata_bytes)
		work_atlas_path := icon_set_work_path(build_dir, declaration.id, "atlas.bin")
		if work_atlas_path == "" {
			return {}, false, "failed to allocate generated icon-set atlas path"
		}
		defer delete(work_atlas_path)
		defer os.remove(work_atlas_path)
		atlas, atlas_err := os.read_entire_file(work_atlas_path, context.temp_allocator)
		if atlas_err != nil {
			return {}, false, "failed to read generated icon-set atlas"
		}
		if write_err := write_import_product_atomically(
			artifact_path,
			atlas,
			metadata_path,
			metadata_bytes,
		); write_err != "" {
			return {}, false, write_err
		}
		imported = true
	}
	product_source, source_clone_err := strings.clone(declaration.icon_set.source)
	if source_clone_err != nil {
		return {}, false, "failed to allocate imported icon-set source"
	}
	product_path, path_clone_err := strings.clone(artifact_path)
	if path_clone_err != nil {
		delete(product_source)
		return {}, false, "failed to allocate imported icon-set product path"
	}
	product_metadata_path, metadata_path_clone_err := strings.clone(metadata_path)
	if metadata_path_clone_err != nil {
		delete(product_source)
		delete(product_path)
		return {}, false, "failed to allocate imported icon-set metadata path"
	}
	return Product {
			id = declaration.id,
			kind = .Icon_Set,
			source = product_source,
			artifact_path = product_path,
			metadata_path = product_metadata_path,
			width = metadata.width,
			height = metadata.height,
			byte_count = metadata.byte_count,
			symbol_count = metadata.symbol_count,
			color_space = .Linear,
		},
		imported,
		""
}

discover_icon_sources :: proc(
	source_root: string,
) -> (
	sources: [dynamic]Icon_Source,
	source_hash: u64,
	err: string,
) {
	if !os.exists(source_root) {
		return nil, 0, "source directory does not exist"
	}
	if err = collect_icon_sources(source_root, "", &sources); err != "" {
		destroy_icon_sources(&sources)
		return nil, 0, err
	}
	slice.sort_by(sources[:], proc(a, b: Icon_Source) -> bool {
		return a.relative_path < b.relative_path
	})
	if len(sources) == 0 {
		destroy_icon_sources(&sources)
		return nil, 0, "source directory contains no .svg files"
	}
	if len(sources) > MAX_ICON_SET_SYMBOLS {
		count := len(sources)
		destroy_icon_sources(&sources)
		return nil, 0, fmt.tprintf(
			"source directory contains %d icons; maximum is %d",
			count,
			MAX_ICON_SET_SYMBOLS,
		)
	}
	for source in sources {
		bytes, read_err := os.read_entire_file(source.full_path, context.temp_allocator)
		if read_err != nil {
			destroy_icon_sources(&sources)
			return nil, 0, fmt.tprintf("failed to read %s: %v", source.relative_path, read_err)
		}
		source_hash = hash.fnv64a(transmute([]byte)(source.relative_path), source_hash)
		source_hash = hash.fnv64a(bytes, source_hash)
	}
	return sources, source_hash, ""
}

collect_icon_sources :: proc(
	full_dir, relative_dir: string,
	sources: ^[dynamic]Icon_Source,
) -> string {
	entries, read_err := os.read_all_directory_by_path(full_dir, context.allocator)
	if read_err != nil {
		return fmt.tprintf("failed to read source directory: %v", read_err)
	}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		relative_path := entry.name
		if relative_dir != "" {
			joined, join_err := filepath.join({relative_dir, entry.name})
			if join_err != nil {
				return "failed to allocate icon relative path"
			}
			relative_path = joined
		}
		#partial switch entry.type {
			case .Directory:
				if recurse_err := collect_icon_sources(entry.fullpath, relative_path, sources);
				   recurse_err != "" {
					if relative_path != entry.name {
						delete(relative_path)
					}
					return recurse_err
				}
			case .Regular:
				if !strings.has_suffix(entry.name, ".svg") {
					if relative_path != entry.name {
						delete(relative_path)
					}
					continue
				}
				owned_relative, relative_err := strings.clone(relative_path)
				owned_full, full_err := strings.clone(entry.fullpath)
				if relative_path != entry.name {
					delete(relative_path)
				}
				if relative_err != nil || full_err != nil {
					delete(owned_relative)
					delete(owned_full)
					return "failed to allocate icon source path"
				}
				append(sources, Icon_Source{owned_relative, owned_full})
				continue
			case:
		}
		if relative_path != entry.name {
			delete(relative_path)
		}
	}
	return ""
}

destroy_icon_sources :: proc(sources: ^[dynamic]Icon_Source) {
	if sources == nil {
		return
	}
	for &source in sources^ {
		delete(source.relative_path)
		delete(source.full_path)
	}
	delete(sources^)
	sources^ = nil
}

compile_icon_set_product :: proc(
	source_path, build_dir: string,
	declaration: shared.Project_Resource,
	source_hash: u64,
) -> (
	metadata: Icon_Set_Metadata,
	err: string,
) {
	font_path := icon_set_work_path(build_dir, declaration.id, "font.ttf")
	map_path := icon_set_work_path(build_dir, declaration.id, "map.json")
	charset_path := icon_set_work_path(build_dir, declaration.id, "charset.txt")
	atlas_path := icon_set_work_path(build_dir, declaration.id, "atlas.bin")
	atlas_json_path := icon_set_work_path(build_dir, declaration.id, "atlas.json")
	defer delete(font_path)
	defer delete(map_path)
	defer delete(charset_path)
	defer delete(atlas_path)
	defer delete(atlas_json_path)
	defer os.remove(font_path)
	defer os.remove(map_path)
	defer os.remove(charset_path)
	defer os.remove(atlas_json_path)

	icon_compiler := os.get_env("SCRAPBOT_ICON_COMPILER", context.temp_allocator)
	owned_compiler := ""
	defer delete(owned_compiler)
	if icon_compiler == "" {
		executable_dir, executable_err := os.get_executable_directory(context.allocator)
		if executable_err == nil {
			defer delete(executable_dir)
			candidate, candidate_err := filepath.join({executable_dir, "scrapbot-iconc"})
			if candidate_err == nil && os.exists(candidate) {
				owned_compiler = candidate
				icon_compiler = candidate
			} else {
				delete(candidate)
			}
		}
	}
	if icon_compiler == "" {
		icon_compiler = "scrapbot-iconc"
	}
	if process_err := run_icon_process(
		[]string {
			icon_compiler,
			source_path,
			"--font-out",
			font_path,
			"--map-out",
			map_path,
			"--charset-out",
			charset_path,
		},
		"SVG normalization",
	); process_err != "" {
		return {}, process_err
	}
	msdf_compiler := os.get_env("SCRAPBOT_MSDF_ATLAS_GEN", context.temp_allocator)
	if msdf_compiler == "" {
		msdf_compiler = "msdf-atlas-gen"
	}
	if process_err := run_icon_process(
		[]string {
			msdf_compiler,
			"-font",
			font_path,
			"-charset",
			charset_path,
			"-type",
			"mtsdf",
			"-format",
			"bin",
			"-dimensions",
			fmt.tprintf("%d", ICON_SET_ATLAS_SIZE),
			fmt.tprintf("%d", ICON_SET_ATLAS_SIZE),
			"-size",
			fmt.tprintf("%d", ICON_SET_EM_SIZE),
			"-pxrange",
			fmt.tprintf("%d", ICON_SET_DISTANCE_RANGE),
			"-yorigin",
			"top",
			"-imageout",
			atlas_path,
			"-json",
			atlas_json_path,
		},
		"MTSDF generation",
	); process_err != "" {
		return {}, process_err
	}
	map_bytes, map_err := os.read_entire_file(map_path, context.temp_allocator)
	atlas_json_bytes, atlas_json_err := os.read_entire_file(
		atlas_json_path,
		context.temp_allocator,
	)
	atlas_info, atlas_stat_err := os.stat(atlas_path, context.temp_allocator)
	if map_err != nil || atlas_json_err != nil || atlas_stat_err != nil {
		return {}, "icon compiler did not produce complete artifacts"
	}
	compiler_map: Icon_Compiler_Map
	atlas_description: Icon_Atlas_Description
	if json.unmarshal(map_bytes, &compiler_map, allocator = context.temp_allocator) != nil ||
	   json.unmarshal(atlas_json_bytes, &atlas_description, allocator = context.temp_allocator) !=
		   nil {
		return {}, "failed to parse generated icon metadata"
	}
	if compiler_map.symbol_count <= 0 ||
	   compiler_map.symbol_count != len(compiler_map.symbols) ||
	   len(compiler_map.symbols) != len(atlas_description.glyphs) ||
	   atlas_info.size != ICON_SET_ATLAS_SIZE * ICON_SET_ATLAS_SIZE * 4 {
		return {}, "generated icon artifacts have an invalid shape"
	}
	metadata = {
		schema = ICON_SET_IMPORTER_SCHEMA,
		source = declaration.icon_set.source,
		source_hash = source_hash,
		width = ICON_SET_ATLAS_SIZE,
		height = ICON_SET_ATLAS_SIZE,
		byte_count = ICON_SET_ATLAS_SIZE * ICON_SET_ATLAS_SIZE * 4,
		symbol_count = compiler_map.symbol_count,
	}
	metadata.symbols = make([dynamic]Icon_Symbol_Metadata, 0, compiler_map.symbol_count)
	for symbol in compiler_map.symbols {
		glyph, found := icon_atlas_glyph(atlas_description.glyphs[:], symbol.codepoint)
		if !found {
			delete(metadata.symbols)
			return {}, fmt.tprintf("generated atlas is missing icon symbol '%s'", symbol.name)
		}
		append(
			&metadata.symbols,
			Icon_Symbol_Metadata {
				name = symbol.name,
				codepoint = symbol.codepoint,
				uv = {
					glyph.atlas_bounds.left / ICON_SET_ATLAS_SIZE,
					glyph.atlas_bounds.top / ICON_SET_ATLAS_SIZE,
					glyph.atlas_bounds.right / ICON_SET_ATLAS_SIZE,
					glyph.atlas_bounds.bottom / ICON_SET_ATLAS_SIZE,
				},
				plane = {
					glyph.plane_bounds.left,
					glyph.plane_bounds.top,
					glyph.plane_bounds.right,
					glyph.plane_bounds.bottom,
				},
			},
		)
	}
	return metadata, ""
}

run_icon_process :: proc(command: []string, stage: string) -> string {
	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if exec_err != nil {
		return fmt.tprintf(
			"icon-set %s tool is unavailable; run 'mise setup' or configure its environment override",
			stage,
		)
	}
	if state.success {
		return ""
	}
	output := strings.trim_space(string(stderr))
	if output == "" {
		output = strings.trim_space(string(stdout))
	}
	if output == "" {
		output = fmt.tprintf("exit code %d", state.exit_code)
	}
	return fmt.tprintf("icon-set %s failed: %s", stage, output)
}

icon_atlas_glyph :: proc(glyphs: []Icon_Atlas_Glyph, codepoint: int) -> (Icon_Atlas_Glyph, bool) {
	for glyph in glyphs {
		if glyph.unicode == codepoint {
			return glyph, true
		}
	}
	return {}, false
}

icon_set_work_path :: proc(build_dir: string, id: shared.Resource_UUID, suffix: string) -> string {
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(id, id_buffer[:])
	name := fmt.tprintf("%s.icon-set.%s", id_text, suffix)
	path, path_err := filepath.join({build_dir, name})
	if path_err != nil {
		return ""
	}
	return path
}

icon_set_product_paths :: proc(
	build_dir: string,
	id: shared.Resource_UUID,
) -> (
	artifact: string,
	metadata: string,
	err: string,
) {
	artifact = icon_set_work_path(build_dir, id, "mtsdf.bin")
	metadata = icon_set_work_path(build_dir, id, "json")
	if artifact == "" || metadata == "" {
		delete(artifact)
		delete(metadata)
		return "", "", "failed to allocate icon-set product paths"
	}
	return artifact, metadata, ""
}

read_icon_set_cache :: proc(
	artifact_path, metadata_path: string,
	declaration: shared.Project_Resource,
	source_hash: u64,
) -> (
	Icon_Set_Metadata,
	bool,
) {
	if !os.exists(artifact_path) || !os.exists(metadata_path) {
		return {}, false
	}
	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	metadata: Icon_Set_Metadata
	if json.unmarshal(metadata_bytes, &metadata, allocator = context.temp_allocator) != nil {
		return {}, false
	}
	if metadata.schema != ICON_SET_IMPORTER_SCHEMA ||
	   metadata.source != declaration.icon_set.source ||
	   metadata.source_hash != source_hash ||
	   metadata.width != ICON_SET_ATLAS_SIZE ||
	   metadata.height != ICON_SET_ATLAS_SIZE ||
	   metadata.byte_count != ICON_SET_ATLAS_SIZE * ICON_SET_ATLAS_SIZE * 4 ||
	   metadata.symbol_count <= 0 ||
	   metadata.symbol_count != len(metadata.symbols) {
		return {}, false
	}
	artifact_info, stat_err := os.stat(artifact_path, context.temp_allocator)
	if stat_err != nil || artifact_info.size != i64(metadata.byte_count) {
		return {}, false
	}
	return metadata, true
}
