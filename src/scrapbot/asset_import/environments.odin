package asset_import

import shared "../shared"
import c "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import stb "vendor:stb/image"

ENVIRONMENT_IMPORTER_SCHEMA :: "scrapbot.environment.v2.rgba16f-ibl"
ENVIRONMENT_IRRADIANCE_SIZE :: 32
ENVIRONMENT_SPECULAR_SIZE :: 128
ENVIRONMENT_SPECULAR_MIP_COUNT :: 8

Environment_Metadata :: struct {
	schema: string,
	source: string,
	source_hash: u64,
	width, height: u32,
	irradiance_size: u32,
	specular_size: u32,
	specular_mip_count: u32,
	byte_count: int,
}

ensure_environment_import :: proc(
	root, build_dir: string,
	declaration: shared.Project_Resource,
	force: bool = false,
) -> (
	product: Product,
	imported: bool,
	err: string,
) {
	source_path, join_err := filepath.join({root, declaration.environment.source})
	if join_err != nil {
		return {}, false, "failed to allocate environment source path"
	}
	defer delete(source_path)
	source, read_err := os.read_entire_file(source_path, context.temp_allocator)
	if read_err != nil {
		return {}, false, fmt.tprintf("failed to read environment source %s: %v", declaration.environment.source, read_err)
	}
	if len(source) == 0 {
		return {}, false, fmt.tprintf("environment source is empty: %s", declaration.environment.source)
	}
	source_hash := hash.fnv64a(source)
	source_hash = hash.fnv64a(transmute([]byte)(string(ENVIRONMENT_IMPORTER_SCHEMA)), source_hash)
	artifact_path, metadata_path, paths_err := environment_product_paths(build_dir, declaration.id)
	if paths_err != "" {
		return {}, false, paths_err
	}
	defer delete(artifact_path)
	defer delete(metadata_path)
	metadata, cache_hit := read_environment_cache(
		artifact_path,
		metadata_path,
		declaration,
		source_hash,
	)
	if force {
		cache_hit = false
	}
	if !cache_hit {
		pixels, width, height, decode_err := decode_environment_product(source)
		if decode_err != "" {
			return {}, false, fmt.tprintf("failed to import environment %s: %s", declaration.environment.source, decode_err)
		}
		defer delete(pixels)
		metadata = {
			schema = ENVIRONMENT_IMPORTER_SCHEMA,
			source = declaration.environment.source,
			source_hash = source_hash,
			width = width,
			height = height,
			irradiance_size = ENVIRONMENT_IRRADIANCE_SIZE,
			specular_size = ENVIRONMENT_SPECULAR_SIZE,
			specular_mip_count = ENVIRONMENT_SPECULAR_MIP_COUNT,
			byte_count = len(pixels) * size_of(u16),
		}
		metadata_bytes, marshal_err := json.marshal(metadata)
		if marshal_err != nil {
			return {}, false, "failed to encode environment import metadata"
		}
		defer delete(metadata_bytes)
		pixel_bytes := (cast([^]u8)raw_data(pixels))[:metadata.byte_count]
		if write_err := write_import_product_atomically(
			artifact_path,
			pixel_bytes,
			metadata_path,
			metadata_bytes,
		); write_err != "" {
			return {}, false, write_err
		}
		imported = true
	}
	product_source, source_clone_err := strings.clone(declaration.environment.source)
	if source_clone_err != nil {
		return {}, false, "failed to allocate imported environment source"
	}
	product_path, path_clone_err := strings.clone(artifact_path)
	if path_clone_err != nil {
		delete(product_source)
		return {}, false, "failed to allocate imported environment product path"
	}
	return Product {
			id = declaration.id,
			kind = .Environment,
			source = product_source,
			artifact_path = product_path,
			width = metadata.specular_size,
			height = metadata.irradiance_size,
			mip_count = metadata.specular_mip_count,
			byte_count = metadata.byte_count,
			color_space = .Linear,
		},
		imported,
		""
}

decode_environment_product :: proc(source: []u8) -> ([]u16, u32, u32, string) {
	if stb.is_hdr_from_memory(raw_data(source), c.int(len(source))) == 0 {
		return nil, 0, 0, "source is not a Radiance HDR image"
	}
	x, y, channels: c.int
	decoded := stb.loadf_from_memory(raw_data(source), c.int(len(source)), &x, &y, &channels, 4)
	if decoded == nil {
		return nil, 0, 0, fmt.tprintf(
			"failed to decode HDR image: %s",
			string(stb.failure_reason()),
		)
	}
	defer stb.image_free(decoded)
	if x <= 0 || y <= 0 || x > 8192 || y > 4096 || x != y * 2 {
		return nil,
			0,
			0,
			"environment must be a 2:1 equirectangular image no larger than 8192x4096"
	}
	source_pixels := decoded[:int(x * y * 4)]
	pixel_count := environment_product_texel_count() * 4
	pixels := make([]u16, pixel_count)
	cursor := 0
	cursor = append_environment_cube(
		pixels,
		cursor,
		source_pixels,
		int(x),
		int(y),
		ENVIRONMENT_IRRADIANCE_SIZE,
		0,
		true,
	)
	for mip in 0 ..< ENVIRONMENT_SPECULAR_MIP_COUNT {
		size := max(ENVIRONMENT_SPECULAR_SIZE >> uint(mip), 1)
		roughness := f32(mip) / f32(ENVIRONMENT_SPECULAR_MIP_COUNT - 1)
		cursor = append_environment_cube(
			pixels,
			cursor,
			source_pixels,
			int(x),
			int(y),
			size,
			roughness,
			false,
		)
	}
	return pixels, u32(x), u32(y), ""
}

environment_product_texel_count :: proc() -> int {
	count := ENVIRONMENT_IRRADIANCE_SIZE * ENVIRONMENT_IRRADIANCE_SIZE * 6
	for mip in 0 ..< ENVIRONMENT_SPECULAR_MIP_COUNT {
		size := max(ENVIRONMENT_SPECULAR_SIZE >> uint(mip), 1)
		count += size * size * 6
	}
	return count
}

append_environment_cube :: proc(
	destination: []u16,
	cursor: int,
	source: []f32,
	source_width, source_height, size: int,
	roughness: f32,
	diffuse: bool,
) -> int {
	write_cursor := cursor
	for face in 0 ..< 6 {
		for y in 0 ..< size {
			for x in 0 ..< size {
				u := (f32(x) + 0.5) / f32(size) * 2 - 1
				v := (f32(y) + 0.5) / f32(size) * 2 - 1
				direction := environment_cube_direction(face, u, v)
				color: [3]f32
				if diffuse {
					color = environment_diffuse_sample(
						source,
						source_width,
						source_height,
						direction,
					)
				} else {
					color = environment_specular_sample(
						source,
						source_width,
						source_height,
						direction,
						roughness,
					)
				}
				for channel in 0 ..< 3 {
					destination[write_cursor + channel] = environment_f16(color[channel])
				}
				destination[write_cursor + 3] = environment_f16(1)
				write_cursor += 4
			}
		}
	}
	return write_cursor
}

environment_cube_direction :: proc(face: int, u, v: f32) -> [3]f32 {
	direction: [3]f32
	switch face {
		case 0:
			direction = {1, -v, -u}
		case 1:
			direction = {-1, -v, u}
		case 2:
			direction = {u, 1, v}
		case 3:
			direction = {u, -1, -v}
		case 4:
			direction = {u, -v, 1}
		case:
			direction = {-u, -v, -1}
	}
	return environment_normalize(direction)
}

environment_diffuse_sample :: proc(source: []f32, width, height: int, normal: [3]f32) -> [3]f32 {
	tangent, bitangent := environment_basis(normal)
	color: [3]f32
	SAMPLE_COUNT :: 32
	for index in 0 ..< SAMPLE_COUNT {
		xi := environment_hammersley(index, SAMPLE_COUNT)
		phi := 2 * f32(math.PI) * xi[0]
		cos_theta := math.sqrt(1 - xi[1])
		sin_theta := math.sqrt(xi[1])
		local := [3]f32{math.cos(phi) * sin_theta, math.sin(phi) * sin_theta, cos_theta}
		direction := environment_normalize(
			environment_from_basis(local, tangent, bitangent, normal),
		)
		sample := environment_sample_equirect(source, width, height, direction)
		color += sample
	}
	return color / f32(SAMPLE_COUNT)
}

environment_specular_sample :: proc(
	source: []f32,
	width, height: int,
	normal: [3]f32,
	roughness: f32,
) -> [3]f32 {
	if roughness <= 0.001 {
		return environment_sample_equirect(source, width, height, normal)
	}
	tangent, bitangent := environment_basis(normal)
	color: [3]f32
	weight := f32(0)
	SAMPLE_COUNT :: 48
	for index in 0 ..< SAMPLE_COUNT {
		xi := environment_hammersley(index, SAMPLE_COUNT)
		a := roughness * roughness
		phi := 2 * f32(math.PI) * xi[0]
		cos_theta := math.sqrt((1 - xi[1]) / max(1 + (a * a - 1) * xi[1], f32(0.000001)))
		sin_theta := math.sqrt(max(1 - cos_theta * cos_theta, f32(0)))
		half_local := [3]f32{math.cos(phi) * sin_theta, math.sin(phi) * sin_theta, cos_theta}
		halfway := environment_normalize(
			environment_from_basis(half_local, tangent, bitangent, normal),
		)
		view_dot_half := max(environment_dot(normal, halfway), f32(0))
		light := environment_normalize(halfway * (2 * view_dot_half) - normal)
		n_dot_l := max(environment_dot(normal, light), f32(0))
		if n_dot_l > 0 {
			color += environment_sample_equirect(source, width, height, light) * n_dot_l
			weight += n_dot_l
		}
	}
	return color / max(weight, f32(0.000001))
}

environment_sample_equirect :: proc(
	source: []f32,
	width, height: int,
	direction: [3]f32,
) -> [3]f32 {
	u := math.atan2(direction[2], direction[0]) / (2 * f32(math.PI)) + 0.5
	v := math.asin(clamp(direction[1], f32(-1), f32(1))) / f32(math.PI) + 0.5
	x := clamp(int(u * f32(width)), 0, width - 1)
	y := clamp(int((1 - v) * f32(height)), 0, height - 1)
	index := (y * width + x) * 4
	result: [3]f32
	for channel in 0 ..< 3 {
		value := source[index + channel]
		if !math.is_nan(value) && !math.is_inf(value) {
			result[channel] = clamp(value, f32(0), f32(65504))
		}
	}
	return result
}

environment_basis :: proc(normal: [3]f32) -> (tangent, bitangent: [3]f32) {
	up := [3]f32{0, 1, 0}
	if math.abs(normal[1]) > 0.999 {
		up = {1, 0, 0}
	}
	tangent = environment_normalize(environment_cross(up, normal))
	bitangent = environment_cross(normal, tangent)
	return
}

environment_from_basis :: proc(local, tangent, bitangent, normal: [3]f32) -> [3]f32 {
	return tangent * local[0] + bitangent * local[1] + normal * local[2]
}

environment_hammersley :: proc(index, count: int) -> [2]f32 {
	bits := u32(index)
	bits = (bits << 16) | (bits >> 16)
	bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)
	bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)
	bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)
	bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)
	return {f32(index) / f32(count), f32(bits) * 2.3283064365386963e-10}
}

environment_normalize :: proc(value: [3]f32) -> [3]f32 {
	return value / max(math.sqrt(environment_dot(value, value)), f32(0.000001))
}

environment_dot :: proc(a, b: [3]f32) -> f32 {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

environment_cross :: proc(a, b: [3]f32) -> [3]f32 {
	return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}

environment_f16 :: proc(value: f32) -> u16 {
	return transmute(u16)f16(clamp(value, f32(0), f32(65504)))
}

environment_product_paths :: proc(
	build_dir: string,
	id: shared.Resource_UUID,
) -> (
	artifact_path, metadata_path, err: string,
) {
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(id, id_buffer[:])
	artifact_name := fmt.tprintf("%s.environment.rgba16f", id_text)
	metadata_name := fmt.tprintf("%s.environment.json", id_text)
	artifact, artifact_err := filepath.join({build_dir, artifact_name})
	if artifact_err != nil {
		return "", "", "failed to allocate environment artifact path"
	}
	metadata, metadata_err := filepath.join({build_dir, metadata_name})
	if metadata_err != nil {
		delete(artifact)
		return "", "", "failed to allocate environment metadata path"
	}
	return artifact, metadata, ""
}

read_environment_cache :: proc(
	artifact_path, metadata_path: string,
	declaration: shared.Project_Resource,
	source_hash: u64,
) -> (
	Environment_Metadata,
	bool,
) {
	if !os.exists(artifact_path) || !os.exists(metadata_path) {
		return {}, false
	}
	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	metadata: Environment_Metadata
	if unmarshal_err := json.unmarshal(
		metadata_bytes,
		&metadata,
		allocator = context.temp_allocator,
	); unmarshal_err != nil {
		return {}, false
	}
	if metadata.schema != ENVIRONMENT_IMPORTER_SCHEMA ||
	   metadata.source != declaration.environment.source ||
	   metadata.source_hash != source_hash ||
	   metadata.width == 0 ||
	   metadata.height == 0 ||
	   metadata.width != metadata.height * 2 ||
	   metadata.irradiance_size != ENVIRONMENT_IRRADIANCE_SIZE ||
	   metadata.specular_size != ENVIRONMENT_SPECULAR_SIZE ||
	   metadata.specular_mip_count != ENVIRONMENT_SPECULAR_MIP_COUNT ||
	   metadata.byte_count != environment_product_texel_count() * 8 {
		return {}, false
	}
	artifact_info, stat_err := os.stat(artifact_path, context.temp_allocator)
	if stat_err != nil || artifact_info.size != i64(metadata.byte_count) {
		return {}, false
	}
	return metadata, true
}
