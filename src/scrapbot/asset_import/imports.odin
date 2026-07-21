package asset_import

import shared "../shared"
import c "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:strings"
import stb "vendor:stb/image"

TEXTURE_IMPORTER_SCHEMA :: "scrapbot.texture.v1.rgba8-mips"

Product_Kind :: enum {
	Texture,
}

Product :: struct {
	id: shared.Resource_UUID,
	kind: Product_Kind,
	source: string,
	artifact_path: string,
	width, height: u32,
	mip_count: u32,
	color_space: shared.Texture_Color_Space,
}

Report :: struct {
	products: [dynamic]Product,
	imported_count: int,
	cached_count: int,
	err: string,
}

Texture_Metadata :: struct {
	schema: string,
	source: string,
	source_hash: u64,
	width, height: u32,
	mip_count: u32,
	byte_count: int,
	color_space: shared.Texture_Color_Space,
	generate_mipmaps: bool,
}

destroy_report :: proc(report: ^Report) {
	if report == nil {
		return
	}
	for &product in report.products {
		delete(product.source)
		delete(product.artifact_path)
	}
	delete(report.products)
	delete(report.err)
	report^ = {}
}

clone_error :: proc(message: string) -> string {
	cloned, clone_err := strings.clone(message)
	if clone_err != nil {
		return ""
	}
	return cloned
}

ensure_project_imports :: proc(root: string, declarations: []shared.Project_Resource) -> Report {
	report: Report
	has_imports := false
	for declaration in declarations {
		if declaration.kind == .Texture {
			has_imports = true
			break
		}
	}
	if !has_imports {
		return report
	}
	build_dir, join_err := filepath.join({root, shared.PROJECT_IMPORTED_ASSETS_DIR})
	if join_err != nil {
		report.err = clone_error("failed to allocate imported asset directory path")
		return report
	}
	defer delete(build_dir)
	if !os.exists(build_dir) {
		if make_err := os.make_directory_all(build_dir); make_err != nil {
			report.err = fmt.aprintf("failed to create imported asset directory: %v", make_err)
			return report
		}
	}
	for declaration in declarations {
		if declaration.kind != .Texture {
			continue
		}
		product, imported, import_err := ensure_texture_import(root, build_dir, declaration)
		if import_err != "" {
			report.err = clone_error(import_err)
			return report
		}
		append(&report.products, product)
		if imported {
			report.imported_count += 1
		} else {
			report.cached_count += 1
		}
	}
	return report
}

ensure_texture_import :: proc(
	root, build_dir: string,
	declaration: shared.Project_Resource,
) -> (
	product: Product,
	imported: bool,
	err: string,
) {
	source_path, source_join_err := filepath.join({root, declaration.texture.source})
	if source_join_err != nil {
		return {}, false, "failed to allocate texture source path"
	}
	defer delete(source_path)
	source, read_err := os.read_entire_file(source_path, context.temp_allocator)
	if read_err != nil {
		return {}, false, fmt.tprintf("failed to read texture source %s: %v", declaration.texture.source, read_err)
	}
	if len(source) == 0 {
		return {}, false, fmt.tprintf("texture source is empty: %s", declaration.texture.source)
	}
	source_hash := texture_import_hash(source, declaration.texture)
	artifact_path, metadata_path, paths_err := texture_product_paths(build_dir, declaration.id)
	if paths_err != "" {
		return {}, false, paths_err
	}
	defer delete(artifact_path)
	defer delete(metadata_path)
	metadata, cache_hit := read_texture_cache(
		artifact_path,
		metadata_path,
		declaration,
		source_hash,
	)
	if !cache_hit {
		pixels, width, height, mip_count, decode_err := decode_texture_product(
			source,
			declaration.texture.generate_mipmaps,
		)
		if decode_err != "" {
			return {}, false, fmt.tprintf("failed to import texture %s: %s", declaration.texture.source, decode_err)
		}
		defer delete(pixels)
		metadata = {
			schema = TEXTURE_IMPORTER_SCHEMA,
			source = declaration.texture.source,
			source_hash = source_hash,
			width = width,
			height = height,
			mip_count = mip_count,
			byte_count = len(pixels),
			color_space = declaration.texture.color_space,
			generate_mipmaps = declaration.texture.generate_mipmaps,
		}
		metadata_bytes, marshal_err := json.marshal(metadata)
		if marshal_err != nil {
			return {}, false, "failed to encode texture import metadata"
		}
		defer delete(metadata_bytes)
		if write_err := write_import_product_atomically(
			artifact_path,
			pixels,
			metadata_path,
			metadata_bytes,
		); write_err != "" {
			return {}, false, write_err
		}
		imported = true
	}
	product_source, source_clone_err := strings.clone(declaration.texture.source)
	if source_clone_err != nil {
		return {}, false, "failed to allocate imported texture source"
	}
	product_path, path_clone_err := strings.clone(artifact_path)
	if path_clone_err != nil {
		delete(product_source)
		return {}, false, "failed to allocate imported texture product path"
	}
	return Product {
			id = declaration.id,
			kind = .Texture,
			source = product_source,
			artifact_path = product_path,
			width = metadata.width,
			height = metadata.height,
			mip_count = metadata.mip_count,
			color_space = metadata.color_space,
		},
		imported,
		""
}

texture_import_hash :: proc(source: []u8, texture: shared.Project_Texture_Resource) -> u64 {
	value := hash.fnv64a(source)
	value = hash.fnv64a(transmute([]byte)(string(TEXTURE_IMPORTER_SCHEMA)), value)
	color_space := texture.color_space
	value = hash.fnv64a((cast([^]byte)&color_space)[:size_of(color_space)], value)
	generate_mipmaps := texture.generate_mipmaps
	value = hash.fnv64a((cast([^]byte)&generate_mipmaps)[:size_of(generate_mipmaps)], value)
	return value
}

texture_product_paths :: proc(
	build_dir: string,
	id: shared.Resource_UUID,
) -> (
	artifact_path, metadata_path, err: string,
) {
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(id, id_buffer[:])
	artifact_name := fmt.tprintf("%s.texture.rgba", id_text)
	metadata_name := fmt.tprintf("%s.texture.json", id_text)
	artifact, artifact_err := filepath.join({build_dir, artifact_name})
	if artifact_err != nil {
		return "", "", "failed to allocate texture artifact path"
	}
	metadata, metadata_err := filepath.join({build_dir, metadata_name})
	if metadata_err != nil {
		delete(artifact)
		return "", "", "failed to allocate texture metadata path"
	}
	return artifact, metadata, ""
}

read_texture_cache :: proc(
	artifact_path, metadata_path: string,
	declaration: shared.Project_Resource,
	source_hash: u64,
) -> (
	Texture_Metadata,
	bool,
) {
	if !os.exists(artifact_path) || !os.exists(metadata_path) {
		return {}, false
	}
	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	metadata: Texture_Metadata
	if unmarshal_err := json.unmarshal(
		metadata_bytes,
		&metadata,
		allocator = context.temp_allocator,
	); unmarshal_err != nil {
		return {}, false
	}
	if metadata.schema != TEXTURE_IMPORTER_SCHEMA ||
	   metadata.source != declaration.texture.source ||
	   metadata.source_hash != source_hash ||
	   metadata.color_space != declaration.texture.color_space ||
	   metadata.generate_mipmaps != declaration.texture.generate_mipmaps ||
	   metadata.width == 0 ||
	   metadata.height == 0 ||
	   metadata.mip_count == 0 ||
	   metadata.byte_count <= 0 {
		return {}, false
	}
	artifact_info, stat_err := os.stat(artifact_path, context.temp_allocator)
	if stat_err != nil || artifact_info.size != i64(metadata.byte_count) {
		return {}, false
	}
	return metadata, true
}

decode_texture_product :: proc(
	source: []u8,
	generate_mipmaps: bool,
) -> (
	pixels: []u8,
	width, height, mip_count: u32,
	err: string,
) {
	x, y, channels: c.int
	decoded := stb.load_from_memory(raw_data(source), c.int(len(source)), &x, &y, &channels, 4)
	if decoded == nil {
		return nil, 0, 0, 0, string(stb.failure_reason())
	}
	defer stb.image_free(decoded)
	if x <= 0 || y <= 0 || x > 16384 || y > 16384 {
		return nil, 0, 0, 0, "dimensions are unsupported"
	}
	width = u32(x)
	height = u32(y)
	mip_count = 1
	if generate_mipmaps {
		mip_width, mip_height := width, height
		for mip_width > 1 || mip_height > 1 {
			mip_width = max(mip_width / 2, 1)
			mip_height = max(mip_height / 2, 1)
			mip_count += 1
		}
	}
	total_bytes := texture_mip_byte_count(width, height, mip_count)
	pixels = make([]u8, total_bytes)
	base_size := int(width * height * 4)
	copy(pixels[:base_size], decoded[:base_size])
	previous_offset := 0
	output_offset := base_size
	previous_width, previous_height := width, height
	for level in 1 ..< mip_count {
		level_width := max(previous_width / 2, 1)
		level_height := max(previous_height / 2, 1)
		generate_rgba8_mip(
			pixels[previous_offset:output_offset],
			previous_width,
			previous_height,
			pixels[output_offset:],
			level_width,
			level_height,
		)
		previous_offset = output_offset
		output_offset += int(level_width * level_height * 4)
		previous_width = level_width
		previous_height = level_height
	}
	return pixels, width, height, mip_count, ""
}

texture_mip_byte_count :: proc(width, height, mip_count: u32) -> int {
	result := 0
	w, h := width, height
	for _ in 0 ..< mip_count {
		result += int(w * h * 4)
		w = max(w / 2, 1)
		h = max(h / 2, 1)
	}
	return result
}

generate_rgba8_mip :: proc(
	source: []u8,
	source_width, source_height: u32,
	destination: []u8,
	destination_width, destination_height: u32,
) {
	for y in 0 ..< destination_height {
		for x in 0 ..< destination_width {
			for channel in 0 ..< 4 {
				total: u32
				samples: u32
				for offset_y in 0 ..< 2 {
					source_y := y * 2 + u32(offset_y)
					if source_y >= source_height {
						continue
					}
					for offset_x in 0 ..< 2 {
						source_x := x * 2 + u32(offset_x)
						if source_x >= source_width {
							continue
						}
						index := int((source_y * source_width + source_x) * 4 + u32(channel))
						total += u32(source[index])
						samples += 1
					}
				}
				destination_index := int((y * destination_width + x) * 4 + u32(channel))
				destination[destination_index] = u8((total + samples / 2) / samples)
			}
		}
	}
}

write_import_product_atomically :: proc(
	artifact_path: string,
	artifact: []u8,
	metadata_path: string,
	metadata: []u8,
) -> string {
	artifact_temp := fmt.tprintf("%s.tmp", artifact_path)
	metadata_temp := fmt.tprintf("%s.tmp", metadata_path)
	defer os.remove(artifact_temp)
	defer os.remove(metadata_temp)
	if write_err := os.write_entire_file(artifact_temp, artifact); write_err != nil {
		return fmt.tprintf("failed to write imported texture product: %v", write_err)
	}
	if write_err := os.write_entire_file(metadata_temp, metadata); write_err != nil {
		return fmt.tprintf("failed to write imported texture metadata: %v", write_err)
	}
	if rename_err := os.rename(artifact_temp, artifact_path); rename_err != nil {
		return fmt.tprintf("failed to install imported texture product: %v", rename_err)
	}
	if rename_err := os.rename(metadata_temp, metadata_path); rename_err != nil {
		return fmt.tprintf("failed to install imported texture metadata: %v", rename_err)
	}
	return ""
}
