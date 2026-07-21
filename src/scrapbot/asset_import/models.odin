package asset_import

import shared "../shared"
import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import cgltf "vendor:cgltf"

MODEL_IMPORTER_SCHEMA :: "scrapbot.model.v2.static-gltf2"
MODEL_PRODUCT_MAGIC :: [8]u8{'S', 'B', 'M', 'O', 'D', 'E', 'L', '2'}

Model_Vertex :: struct {
	position, normal: shared.Vec3,
	uv: shared.Vec2,
}

Model_Material :: struct {
	name: string,
	base_color: shared.Vec4,
	emissive: shared.Vec3,
}

Model_Primitive :: struct {
	key: string,
	material_index: i32,
	vertices: [dynamic]Model_Vertex,
	indices: [dynamic]u32,
}

Model_Mesh :: struct {
	name: string,
	primitives: [dynamic]Model_Primitive,
}

Model_Node :: struct {
	name: string,
	parent_index, mesh_index: i32,
	transform: shared.Transform_Component,
}

Model_Product :: struct {
	materials: [dynamic]Model_Material,
	meshes: [dynamic]Model_Mesh,
	nodes: [dynamic]Model_Node,
}

Model_Metadata :: struct {
	schema: string,
	source: string,
	source_hash: u64,
	byte_count: int,
	node_count, mesh_count, primitive_count: int,
	vertex_count, index_count, material_count: int,
}

destroy_model_product :: proc(model: ^Model_Product) {
	if model == nil {
		return
	}
	for &material in model.materials {
		delete(material.name)
	}
	for &mesh in model.meshes {
		delete(mesh.name)
		for &primitive in mesh.primitives {
			delete(primitive.key)
			delete(primitive.vertices)
			delete(primitive.indices)
		}
		delete(mesh.primitives)
	}
	for &node in model.nodes {
		delete(node.name)
	}
	delete(model.materials)
	delete(model.meshes)
	delete(model.nodes)
	model^ = {}
}

ensure_model_import :: proc(
	root, build_dir: string,
	declaration: shared.Project_Resource,
) -> (
	product: Product,
	imported: bool,
	err: string,
) {
	source_path, source_join_err := filepath.join({root, declaration.model.source})
	if source_join_err != nil {
		return {}, false, "failed to allocate model source path"
	}
	defer delete(source_path)
	source, read_err := os.read_entire_file(source_path, context.temp_allocator)
	if read_err != nil {
		return {}, false, fmt.tprintf("failed to read model source %s: %v", declaration.model.source, read_err)
	}
	path_cstring, path_err := strings.clone_to_cstring(source_path, context.temp_allocator)
	if path_err != nil {
		return {}, false, "failed to allocate model importer path"
	}
	data, parse_result := cgltf.parse_file({}, path_cstring)
	if parse_result != .success || data == nil {
		return {}, false, fmt.tprintf("failed to parse glTF model %s: %s", declaration.model.source, cgltf_result_message(parse_result))
	}
	defer cgltf.free(data)
	if uri_err := validate_model_buffer_uris(data); uri_err != "" {
		return {}, false, fmt.tprintf("unsupported glTF model %s: %s", declaration.model.source, uri_err)
	}
	if load_result := cgltf.load_buffers({}, data, path_cstring); load_result != .success {
		return {}, false, fmt.tprintf("failed to load glTF dependencies for %s: %s", declaration.model.source, cgltf_result_message(load_result))
	}
	if validate_result := cgltf.validate(data); validate_result != .success {
		return {}, false, fmt.tprintf("invalid glTF model %s: %s", declaration.model.source, cgltf_result_message(validate_result))
	}
	if unsupported_err := validate_supported_static_gltf(data); unsupported_err != "" {
		return {}, false, fmt.tprintf("unsupported glTF model %s: %s", declaration.model.source, unsupported_err)
	}
	source_hash := model_import_hash(source, data)
	artifact_path, metadata_path, paths_err := model_product_paths(build_dir, declaration.id)
	if paths_err != "" {
		return {}, false, paths_err
	}
	defer delete(artifact_path)
	defer delete(metadata_path)
	metadata, cache_hit := read_model_cache(artifact_path, metadata_path, declaration, source_hash)
	if !cache_hit {
		model, model_err := build_model_product(data)
		if model_err != "" {
			return {}, false, fmt.tprintf("failed to import glTF model %s: %s", declaration.model.source, model_err)
		}
		defer destroy_model_product(&model)
		artifact := encode_model_product(&model)
		defer delete(artifact)
		metadata = model_metadata(declaration.model.source, source_hash, artifact, &model)
		metadata_bytes, marshal_err := json.marshal(metadata)
		if marshal_err != nil {
			return {}, false, "failed to encode model import metadata"
		}
		defer delete(metadata_bytes)
		if write_err := write_import_product_atomically(
			artifact_path,
			artifact,
			metadata_path,
			metadata_bytes,
		); write_err != "" {
			return {}, false, write_err
		}
		imported = true
	}
	product_source, source_clone_err := strings.clone(declaration.model.source)
	if source_clone_err != nil {
		return {}, false, "failed to allocate imported model source"
	}
	product_path, product_clone_err := strings.clone(artifact_path)
	if product_clone_err != nil {
		delete(product_source)
		return {}, false, "failed to allocate imported model product path"
	}
	return Product {
			id = declaration.id,
			kind = .Model,
			source = product_source,
			artifact_path = product_path,
			byte_count = metadata.byte_count,
			node_count = metadata.node_count,
			mesh_count = metadata.mesh_count,
			primitive_count = metadata.primitive_count,
			vertex_count = metadata.vertex_count,
			index_count = metadata.index_count,
			material_count = metadata.material_count,
		},
		imported,
		""
}

validate_model_buffer_uris :: proc(data: ^cgltf.data) -> string {
	for buffer in data.buffers {
		if buffer.uri == nil {
			continue
		}
		uri := string(buffer.uri)
		if strings.has_prefix(uri, "data:") {
			continue
		}
		decoded_uri, clone_err := strings.clone_to_cstring(uri, context.temp_allocator)
		if clone_err != nil {
			return "failed to allocate external buffer URI"
		}
		_ = cgltf.decode_uri(cast([^]u8)decoded_uri)
		decoded: string = string(decoded_uri)
		if decoded == "" ||
		   strings.has_prefix(decoded, "/") ||
		   strings.contains(decoded, "\\") ||
		   strings.contains(decoded, ":") ||
		   strings.contains(decoded, "?") ||
		   strings.contains(decoded, "#") {
			return fmt.tprintf("external buffer URI '%s' must be a safe relative path", uri)
		}
		remaining: string = decoded
		for part in strings.split_iterator(&remaining, "/") {
			if part == "" || part == "." || part == ".." {
				return fmt.tprintf(
					"external buffer URI '%s' must stay inside the model asset directory",
					uri,
				)
			}
		}
	}
	return ""
}

validate_supported_static_gltf :: proc(data: ^cgltf.data) -> string {
	if len(data.extensions_required) > 0 {
		return fmt.tprintf(
			"required extension '%s' is not supported",
			string(data.extensions_required[0]),
		)
	}
	if len(data.animations) > 0 {
		return "animations are not supported yet"
	}
	if len(data.skins) > 0 {
		return "skins are not supported yet"
	}
	for mesh in data.meshes {
		for primitive in mesh.primitives {
			if primitive.type != .triangles {
				return "only triangle primitives are supported"
			}
			if len(primitive.targets) > 0 {
				return "morph targets are not supported yet"
			}
			if primitive.has_draco_mesh_compression {
				return "Draco-compressed geometry is not supported yet"
			}
		}
	}
	for node in data.nodes {
		if node.has_matrix {
			return(
				"matrix-authored node transforms are not supported yet; export node transforms as TRS" \
			)
		}
	}
	for material in data.materials {
		if material.has_pbr_metallic_roughness &&
		   material.pbr_metallic_roughness.base_color_texture.texture != nil {
			return(
				"base-color textures inside glTF are not supported yet; use a Scrapbot Texture resource" \
			)
		}
		if material.normal_texture.texture != nil ||
		   material.emissive_texture.texture != nil ||
		   material.occlusion_texture.texture != nil {
			return "glTF material textures other than base color are not supported yet"
		}
	}
	return ""
}

model_import_hash :: proc(source: []u8, data: ^cgltf.data) -> u64 {
	value := hash.fnv64a(source)
	value = hash.fnv64a(transmute([]byte)(string(MODEL_IMPORTER_SCHEMA)), value)
	for buffer in data.buffers {
		if buffer.data != nil && buffer.size > 0 {
			value = hash.fnv64a((cast([^]u8)buffer.data)[:buffer.size], value)
		}
	}
	return value
}

build_model_product :: proc(data: ^cgltf.data) -> (model: Model_Product, err: string) {
	for material, material_index in data.materials {
		name := model_item_name(material.name, "material", material_index)
		base_color := shared.Vec4{1, 1, 1, 1}
		if material.has_pbr_metallic_roughness {
			factor := material.pbr_metallic_roughness.base_color_factor
			base_color = {factor[0], factor[1], factor[2], factor[3]}
		}
		emissive := shared.Vec3 {
			material.emissive_factor[0],
			material.emissive_factor[1],
			material.emissive_factor[2],
		}
		if material.has_emissive_strength {
			strength := material.emissive_strength.emissive_strength
			emissive.x *= strength
			emissive.y *= strength
			emissive.z *= strength
		}
		append(
			&model.materials,
			Model_Material{name = name, base_color = base_color, emissive = emissive},
		)
	}
	for &mesh, mesh_index in data.meshes {
		imported_mesh := Model_Mesh {
			name = model_item_name(mesh.name, "mesh", mesh_index),
		}
		for &primitive, primitive_index in mesh.primitives {
			imported_primitive, primitive_err := build_model_primitive(
				data,
				&primitive,
				mesh_index,
				primitive_index,
			)
			if primitive_err != "" {
				destroy_model_product(&model)
				destroy_model_mesh(&imported_mesh)
				return {}, primitive_err
			}
			append(&imported_mesh.primitives, imported_primitive)
		}
		append(&model.meshes, imported_mesh)
	}
	for &node, node_index in data.nodes {
		imported_node := Model_Node {
			name = model_item_name(node.name, "node", node_index),
			parent_index = -1,
			mesh_index = -1,
			transform = {scale = {1, 1, 1}},
		}
		if node.parent != nil {
			imported_node.parent_index = i32(cgltf.node_index(data, node.parent))
		}
		if node.mesh != nil {
			imported_node.mesh_index = i32(cgltf.mesh_index(data, node.mesh))
		}
		if node.has_translation {
			imported_node.transform.position = {
				node.translation[0],
				node.translation[1],
				node.translation[2],
			}
		}
		if node.has_rotation {
			imported_node.transform.rotation = shared.transform_quaternion_to_euler(
				{
					x = node.rotation[0],
					y = node.rotation[1],
					z = node.rotation[2],
					w = node.rotation[3],
				},
			)
		}
		if node.has_scale {
			imported_node.transform.scale = {node.scale[0], node.scale[1], node.scale[2]}
		}
		append(&model.nodes, imported_node)
	}
	return model, ""
}

build_model_primitive :: proc(
	data: ^cgltf.data,
	primitive: ^cgltf.primitive,
	mesh_index, primitive_index: int,
) -> (
	result: Model_Primitive,
	err: string,
) {
	position: ^cgltf.accessor
	normal: ^cgltf.accessor
	uv: ^cgltf.accessor
	for attribute in primitive.attributes {
		#partial switch attribute.type {
			case .position:
				if attribute.index == 0 { position = attribute.data }
			case .normal:
				if attribute.index == 0 { normal = attribute.data }
			case .texcoord:
				if attribute.index == 0 { uv = attribute.data }
			case:
		}
	}
	if position == nil || position.type != .vec3 {
		return {}, "triangle primitive is missing a VEC3 POSITION attribute"
	}
	if normal != nil && (normal.type != .vec3 || normal.count != position.count) {
		return {}, "NORMAL must be a VEC3 accessor matching POSITION count"
	}
	if uv != nil && (uv.type != .vec2 || uv.count != position.count) {
		return {}, "TEXCOORD_0 must be a VEC2 accessor matching POSITION count"
	}
	key := fmt.aprintf("mesh:%d/primitive:%d", mesh_index, primitive_index)
	result.key = key
	result.material_index = -1
	if primitive.material != nil {
		result.material_index = i32(cgltf.material_index(data, primitive.material))
	}
	resize(&result.vertices, int(position.count))
	for vertex_index in 0 ..< int(position.count) {
		position_value: [3]f32
		if !cgltf.accessor_read_float(
			position,
			uint(vertex_index),
			raw_data(position_value[:]),
			3,
		) {
			destroy_model_primitive(&result)
			return {}, "failed to decode POSITION accessor"
		}
		result.vertices[vertex_index].position = {
			position_value[0],
			position_value[1],
			position_value[2],
		}
		if normal != nil {
			normal_value: [3]f32
			if !cgltf.accessor_read_float(
				normal,
				uint(vertex_index),
				raw_data(normal_value[:]),
				3,
			) {
				destroy_model_primitive(&result)
				return {}, "failed to decode NORMAL accessor"
			}
			result.vertices[vertex_index].normal = {
				normal_value[0],
				normal_value[1],
				normal_value[2],
			}
		}
		if uv != nil {
			uv_value: [2]f32
			if !cgltf.accessor_read_float(uv, uint(vertex_index), raw_data(uv_value[:]), 2) {
				destroy_model_primitive(&result)
				return {}, "failed to decode TEXCOORD_0 accessor"
			}
			result.vertices[vertex_index].uv = {uv_value[0], uv_value[1]}
		}
	}
	if primitive.indices != nil {
		resize(&result.indices, int(primitive.indices.count))
		for index in 0 ..< len(result.indices) {
			result.indices[index] = u32(cgltf.accessor_read_index(primitive.indices, uint(index)))
			if int(result.indices[index]) >= len(result.vertices) {
				destroy_model_primitive(&result)
				return {}, "primitive index is outside POSITION accessor"
			}
		}
	} else {
		resize(&result.indices, len(result.vertices))
		for &index, index_value in result.indices {
			index = u32(index_value)
		}
	}
	if len(result.indices) == 0 || len(result.indices) % 3 != 0 {
		destroy_model_primitive(&result)
		return {}, "triangle primitive index count must be a non-empty multiple of three"
	}
	if normal == nil {
		generate_model_normals(result.vertices[:], result.indices[:])
	}
	return result, ""
}

destroy_model_primitive :: proc(primitive: ^Model_Primitive) {
	delete(primitive.key)
	delete(primitive.vertices)
	delete(primitive.indices)
	primitive^ = {}
}

destroy_model_mesh :: proc(mesh: ^Model_Mesh) {
	if mesh == nil {
		return
	}
	delete(mesh.name)
	for &primitive in mesh.primitives {
		destroy_model_primitive(&primitive)
	}
	delete(mesh.primitives)
	mesh^ = {}
}

generate_model_normals :: proc(vertices: []Model_Vertex, indices: []u32) {
	for triangle := 0; triangle < len(indices); triangle += 3 {
		a := vertices[indices[triangle]].position
		b := vertices[indices[triangle + 1]].position
		c_value := vertices[indices[triangle + 2]].position
		ab := shared.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
		ac := shared.Vec3{c_value.x - a.x, c_value.y - a.y, c_value.z - a.z}
		normal := shared.Vec3 {
			ab.y * ac.z - ab.z * ac.y,
			ab.z * ac.x - ab.x * ac.z,
			ab.x * ac.y - ab.y * ac.x,
		}
		for corner in 0 ..< 3 {
			vertex := &vertices[indices[triangle + corner]]
			vertex.normal.x += normal.x
			vertex.normal.y += normal.y
			vertex.normal.z += normal.z
		}
	}
	for &vertex in vertices {
		length := math.sqrt(
			vertex.normal.x * vertex.normal.x +
			vertex.normal.y * vertex.normal.y +
			vertex.normal.z * vertex.normal.z,
		)
		if length > 0 {
			vertex.normal.x /= length
			vertex.normal.y /= length
			vertex.normal.z /= length
		} else {
			vertex.normal = {0, 1, 0}
		}
	}
}

model_item_name :: proc(value: cstring, kind: string, index: int) -> string {
	if value != nil && string(value) != "" {
		result, _ := strings.clone(string(value))
		return result
	}
	return fmt.aprintf("%s %d", kind, index)
}

model_metadata :: proc(
	source: string,
	source_hash: u64,
	artifact: []u8,
	model: ^Model_Product,
) -> Model_Metadata {
	metadata := Model_Metadata {
		schema = MODEL_IMPORTER_SCHEMA,
		source = source,
		source_hash = source_hash,
		byte_count = len(artifact),
		node_count = len(model.nodes),
		mesh_count = len(model.meshes),
		material_count = len(model.materials),
	}
	for mesh in model.meshes {
		metadata.primitive_count += len(mesh.primitives)
		for primitive in mesh.primitives {
			metadata.vertex_count += len(primitive.vertices)
			metadata.index_count += len(primitive.indices)
		}
	}
	return metadata
}

model_product_paths :: proc(
	build_dir: string,
	id: shared.Resource_UUID,
) -> (
	artifact_path, metadata_path, err: string,
) {
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(id, id_buffer[:])
	artifact_name := fmt.tprintf("%s.model.bin", id_text)
	metadata_name := fmt.tprintf("%s.model.json", id_text)
	artifact, artifact_err := filepath.join({build_dir, artifact_name})
	if artifact_err != nil {
		return "", "", "failed to allocate model artifact path"
	}
	metadata, metadata_err := filepath.join({build_dir, metadata_name})
	if metadata_err != nil {
		delete(artifact)
		return "", "", "failed to allocate model metadata path"
	}
	return artifact, metadata, ""
}

read_model_cache :: proc(
	artifact_path, metadata_path: string,
	declaration: shared.Project_Resource,
	source_hash: u64,
) -> (
	Model_Metadata,
	bool,
) {
	if !os.exists(artifact_path) || !os.exists(metadata_path) {
		return {}, false
	}
	metadata_bytes, read_err := os.read_entire_file(metadata_path, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	metadata: Model_Metadata
	if unmarshal_err := json.unmarshal(
		metadata_bytes,
		&metadata,
		allocator = context.temp_allocator,
	); unmarshal_err != nil {
		return {}, false
	}
	if metadata.schema != MODEL_IMPORTER_SCHEMA ||
	   metadata.source != declaration.model.source ||
	   metadata.source_hash != source_hash ||
	   metadata.byte_count <= 0 {
		return {}, false
	}
	artifact_info, stat_err := os.stat(artifact_path, context.temp_allocator)
	if stat_err != nil || artifact_info.size != i64(metadata.byte_count) {
		return {}, false
	}
	return metadata, true
}

encode_model_product :: proc(model: ^Model_Product) -> []u8 {
	bytes: [dynamic]u8
	magic := MODEL_PRODUCT_MAGIC
	model_write_bytes(&bytes, magic[:])
	model_write_u32(&bytes, u32(len(model.materials)))
	model_write_u32(&bytes, u32(len(model.meshes)))
	model_write_u32(&bytes, u32(len(model.nodes)))
	for material in model.materials {
		model_write_string(&bytes, material.name)
		model_write_vec4(&bytes, material.base_color)
		model_write_vec3(&bytes, material.emissive)
	}
	for mesh in model.meshes {
		model_write_string(&bytes, mesh.name)
		model_write_u32(&bytes, u32(len(mesh.primitives)))
		for primitive in mesh.primitives {
			model_write_string(&bytes, primitive.key)
			model_write_i32(&bytes, primitive.material_index)
			model_write_u32(&bytes, u32(len(primitive.vertices)))
			model_write_u32(&bytes, u32(len(primitive.indices)))
			for vertex in primitive.vertices {
				model_write_vec3(&bytes, vertex.position)
				model_write_vec3(&bytes, vertex.normal)
				model_write_vec2(&bytes, vertex.uv)
			}
			for index in primitive.indices {
				model_write_u32(&bytes, index)
			}
		}
	}
	for node in model.nodes {
		model_write_string(&bytes, node.name)
		model_write_i32(&bytes, node.parent_index)
		model_write_i32(&bytes, node.mesh_index)
		model_write_vec3(&bytes, node.transform.position)
		model_write_vec3(&bytes, node.transform.rotation)
		model_write_vec3(&bytes, node.transform.scale)
	}
	return bytes[:]
}

read_model_product :: proc(path: string) -> (model: Model_Product, err: string) {
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return {}, fmt.tprintf("failed to read imported model product: %v", read_err)
	}
	reader := Model_Reader {
		bytes = bytes,
	}
	magic, magic_ok := model_read_bytes(&reader, len(MODEL_PRODUCT_MAGIC))
	expected_magic := MODEL_PRODUCT_MAGIC
	if !magic_ok || string(magic) != string(expected_magic[:]) {
		return {}, "imported model product has an invalid header"
	}
	ok: bool
	material_count: u32
	material_count, ok = model_read_u32(&reader)
	if !ok {
		return {}, "imported model product is truncated"
	}
	mesh_count: u32
	mesh_count, ok = model_read_u32(&reader)
	if !ok {
		return {}, "imported model product is truncated"
	}
	node_count: u32
	node_count, ok = model_read_u32(&reader)
	if !ok {
		return {}, "imported model product is truncated"
	}
	if material_count > 65536 || mesh_count > 65536 || node_count > 1000000 {
		return {}, "imported model product counts exceed limits"
	}
	for _ in 0 ..< material_count {
		material: Model_Material
		material.name, ok = model_read_string(&reader)
		if !ok {
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		material.base_color, ok = model_read_vec4(&reader)
		if !ok {
			delete(material.name)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		material.emissive, ok = model_read_vec3(&reader)
		if !ok {
			delete(material.name)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		append(&model.materials, material)
	}
	for _ in 0 ..< mesh_count {
		mesh: Model_Mesh
		mesh.name, ok = model_read_string(&reader)
		if !ok {
			destroy_model_product(&model)
			return {}, "imported model mesh is truncated"
		}
		primitive_count: u32
		primitive_count, ok = model_read_u32(&reader)
		if !ok || primitive_count > 65536 {
			delete(mesh.name)
			destroy_model_product(&model)
			return {}, "imported model primitive count is invalid"
		}
		for _ in 0 ..< primitive_count {
			primitive: Model_Primitive
			primitive.key, ok = model_read_string(&reader)
			if !ok {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model primitive is truncated"
			}
			primitive.material_index, ok = model_read_i32(&reader)
			if !ok {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model primitive is truncated"
			}
			vertex_count: u32
			vertex_count, ok = model_read_u32(&reader)
			if !ok {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model primitive is truncated"
			}
			index_count: u32
			index_count, ok = model_read_u32(&reader)
			remaining_bytes := u64(len(reader.bytes) - reader.offset)
			required_bytes := u64(vertex_count) * 32 + u64(index_count) * 4
			if !ok ||
			   vertex_count > 10000000 ||
			   index_count > 30000000 ||
			   required_bytes > remaining_bytes {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model geometry counts are invalid"
			}
			resize(&primitive.vertices, int(vertex_count))
			for &vertex in primitive.vertices {
				vertex.position, ok = model_read_vec3(&reader)
				if ok {
					vertex.normal, ok = model_read_vec3(&reader)
				}
				if ok {
					vertex.uv, ok = model_read_vec2(&reader)
				}
				if !ok {
					destroy_model_primitive(&primitive)
					destroy_model_mesh(&mesh)
					destroy_model_product(&model)
					return {}, "imported model vertices are truncated"
				}
			}
			resize(&primitive.indices, int(index_count))
			for &index in primitive.indices {
				index, ok = model_read_u32(&reader)
				if !ok || int(index) >= len(primitive.vertices) {
					destroy_model_primitive(&primitive)
					destroy_model_mesh(&mesh)
					destroy_model_product(&model)
					return {}, "imported model indices are invalid"
				}
			}
			if primitive.material_index < -1 ||
			   primitive.material_index >= i32(len(model.materials)) {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model material index is invalid"
			}
			append(&mesh.primitives, primitive)
		}
		append(&model.meshes, mesh)
	}
	for _ in 0 ..< node_count {
		node: Model_Node
		node.name, ok = model_read_string(&reader)
		if ok {
			node.parent_index, ok = model_read_i32(&reader)
		}
		if ok {
			node.mesh_index, ok = model_read_i32(&reader)
		}
		if ok {
			node.transform.position, ok = model_read_vec3(&reader)
		}
		if ok {
			node.transform.rotation, ok = model_read_vec3(&reader)
		}
		if ok {
			node.transform.scale, ok = model_read_vec3(&reader)
		}
		if !ok {
			delete(node.name)
			destroy_model_product(&model)
			return {}, "imported model nodes are truncated"
		}
		append(&model.nodes, node)
	}
	if validation_err := validate_decoded_model(&model); validation_err != "" {
		destroy_model_product(&model)
		return {}, validation_err
	}
	if reader.offset != len(reader.bytes) {
		destroy_model_product(&model)
		return {}, "imported model product has trailing data"
	}
	return model, ""
}

validate_decoded_model :: proc(model: ^Model_Product) -> string {
	for node, node_index in model.nodes {
		if node.parent_index < -1 ||
		   node.parent_index >= i32(len(model.nodes)) ||
		   node.parent_index == i32(node_index) {
			return "imported model node parent is invalid"
		}
		if node.mesh_index < -1 || node.mesh_index >= i32(len(model.meshes)) {
			return "imported model node mesh is invalid"
		}
		values := [9]f32 {
			node.transform.position.x,
			node.transform.position.y,
			node.transform.position.z,
			node.transform.rotation.x,
			node.transform.rotation.y,
			node.transform.rotation.z,
			node.transform.scale.x,
			node.transform.scale.y,
			node.transform.scale.z,
		}
		for value in values {
			if math.is_nan(value) || math.is_inf(value, 0) {
				return "imported model node transform is not finite"
			}
		}
		parent := node.parent_index
		for depth in 0 ..< len(model.nodes) {
			if parent < 0 {
				break
			}
			parent = model.nodes[parent].parent_index
			if depth == len(model.nodes) - 1 {
				return "imported model node hierarchy contains a cycle"
			}
		}
	}
	return ""
}

Model_Reader :: struct {
	bytes: []u8,
	offset: int,
}

model_write_u32 :: proc(bytes: ^[dynamic]u8, value: u32) {
	offset := len(bytes^)
	resize(bytes, offset + 4)
	endian.unchecked_put_u32le(bytes^[offset:], value)
}

model_write_i32 :: proc(bytes: ^[dynamic]u8, value: i32) {
	model_write_u32(bytes, transmute(u32)value)
}

model_write_f32 :: proc(bytes: ^[dynamic]u8, value: f32) {
	model_write_u32(bytes, transmute(u32)value)
}

model_write_string :: proc(bytes: ^[dynamic]u8, value: string) {
	model_write_u32(bytes, u32(len(value)))
	model_write_bytes(bytes, transmute([]u8)(value))
}

model_write_bytes :: proc(bytes: ^[dynamic]u8, value: []u8) {
	offset := len(bytes^)
	resize(bytes, offset + len(value))
	copy(bytes^[offset:], value)
}

model_write_vec2 :: proc(bytes: ^[dynamic]u8, value: shared.Vec2) {
	model_write_f32(bytes, value.x)
	model_write_f32(bytes, value.y)
}

model_write_vec3 :: proc(bytes: ^[dynamic]u8, value: shared.Vec3) {
	model_write_f32(bytes, value.x)
	model_write_f32(bytes, value.y)
	model_write_f32(bytes, value.z)
}

model_write_vec4 :: proc(bytes: ^[dynamic]u8, value: shared.Vec4) {
	model_write_f32(bytes, value.x)
	model_write_f32(bytes, value.y)
	model_write_f32(bytes, value.z)
	model_write_f32(bytes, value.w)
}

model_read_bytes :: proc(reader: ^Model_Reader, count: int) -> ([]u8, bool) {
	if count < 0 || reader.offset + count > len(reader.bytes) {
		return nil, false
	}
	result := reader.bytes[reader.offset:reader.offset + count]
	reader.offset += count
	return result, true
}

model_read_u32 :: proc(reader: ^Model_Reader) -> (u32, bool) {
	bytes, ok := model_read_bytes(reader, 4)
	if !ok {
		return 0, false
	}
	return endian.unchecked_get_u32le(bytes), true
}

model_read_i32 :: proc(reader: ^Model_Reader) -> (i32, bool) {
	value, ok := model_read_u32(reader)
	return transmute(i32)value, ok
}

model_read_f32 :: proc(reader: ^Model_Reader) -> (f32, bool) {
	value, ok := model_read_u32(reader)
	return transmute(f32)value, ok
}

model_read_string :: proc(reader: ^Model_Reader) -> (string, bool) {
	length, ok := model_read_u32(reader)
	if !ok || length > 1048576 {
		return "", false
	}
	bytes, bytes_ok := model_read_bytes(reader, int(length))
	if !bytes_ok {
		return "", false
	}
	value, clone_err := strings.clone(string(bytes))
	return value, clone_err == nil
}

model_read_vec2 :: proc(reader: ^Model_Reader) -> (shared.Vec2, bool) {
	x, ok_x := model_read_f32(reader)
	if !ok_x {
		return {}, false
	}
	y, ok_y := model_read_f32(reader)
	return {x, y}, ok_y
}

model_read_vec3 :: proc(reader: ^Model_Reader) -> (shared.Vec3, bool) {
	x, ok_x := model_read_f32(reader)
	if !ok_x {
		return {}, false
	}
	y, ok_y := model_read_f32(reader)
	if !ok_y {
		return {}, false
	}
	z, ok_z := model_read_f32(reader)
	return {x, y, z}, ok_z
}

model_read_vec4 :: proc(reader: ^Model_Reader) -> (shared.Vec4, bool) {
	x, ok_x := model_read_f32(reader)
	if !ok_x {
		return {}, false
	}
	y, ok_y := model_read_f32(reader)
	if !ok_y {
		return {}, false
	}
	z, ok_z := model_read_f32(reader)
	if !ok_z {
		return {}, false
	}
	w, ok_w := model_read_f32(reader)
	return {x, y, z, w}, ok_w
}

cgltf_result_message :: proc(value: cgltf.result) -> string {
	switch value {
		case .success:
			return "success"
		case .data_too_short:
			return "data is too short"
		case .unknown_format:
			return "unknown file format"
		case .invalid_json:
			return "invalid JSON"
		case .invalid_gltf:
			return "invalid glTF structure"
		case .invalid_options:
			return "invalid importer options"
		case .file_not_found:
			return "dependency file not found"
		case .io_error:
			return "I/O error"
		case .out_of_memory:
			return "out of memory"
		case .legacy_gltf:
			return "legacy glTF is not supported"
	}
	return "unknown importer error"
}
