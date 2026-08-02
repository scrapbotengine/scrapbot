package asset_import

import geometry "../geometry"
import shared "../shared"
import "core:encoding/base64"
import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import cgltf "vendor:cgltf"

MODEL_IMPORTER_SCHEMA :: "scrapbot.model.v15.split-product"
MODEL_CATALOG_MAGIC :: [8]u8{'S', 'B', 'M', 'C', 'A', 'T', '1', '5'}
MODEL_IMAGE_CHUNK_MAGIC :: [8]u8{'S', 'B', 'M', 'I', 'M', 'G', '1', '5'}
MODEL_COARSE_CHUNK_MAGIC :: [8]u8{'S', 'B', 'M', 'C', 'R', 'S', '1', '5'}
MODEL_DETAIL_CHUNK_MAGIC :: [8]u8{'S', 'B', 'M', 'D', 'T', 'L', '1', '5'}
MODEL_PRODUCT_CHUNK_COUNT :: 4
MODEL_READER_BUFFER_SIZE :: 64 * 1024

Model_Vertex :: struct {
	position, normal: shared.Vec3,
	uv: shared.Vec2,
	tangent: shared.Vec4,
}

Model_Image :: struct {
	pixels: []u8,
	width, height, mip_count: u32,
	sampler: shared.Texture_Sampler,
	product_offset, product_size: u64,
}

Model_Material :: struct {
	key: string,
	name: string,
	base_color: shared.Vec4,
	emissive: shared.Vec3,
	metallic_factor, roughness_factor: f32,
	normal_scale, occlusion_strength: f32,
	alpha_mode: shared.Material_Alpha_Mode,
	alpha_cutoff: f32,
	double_sided: bool,
	base_color_image: Model_Image,
	metallic_roughness_image: Model_Image,
	normal_image: Model_Image,
	occlusion_image: Model_Image,
	emissive_image: Model_Image,
	ignored_texture_count: u32,
}

Model_Primitive :: struct {
	key: string,
	material_index: i32,
	vertices: [dynamic]Model_Vertex,
	indices: [dynamic]u32,
	query_positions: []shared.Vec3,
	vertex_count, index_count: u32,
	hierarchy: geometry.Hierarchy,
	page_payloads: []geometry.Page_Payload_Record,
	lods: [dynamic]Model_Primitive_LOD,
}

Model_Primitive_LOD :: struct {
	vertices: [dynamic]Model_Vertex,
	indices: [dynamic]u32,
	query_positions: []shared.Vec3,
	vertex_count, index_count: u32,
	hierarchy: geometry.Hierarchy,
	page_payloads: []geometry.Page_Payload_Record,
	level: u32,
	screen_radius: f32,
	simplification_error: f32,
}

Model_Mesh :: struct {
	key: string,
	name: string,
	primitives: [dynamic]Model_Primitive,
}

Model_Node :: struct {
	key: string,
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
	vertex_count, index_count, material_count, texture_count: int,
	lod_count, lod_vertex_count, lod_index_count: int,
	cluster_count, cluster_group_count, cluster_page_count: int,
	ignored_texture_count: int,
}

destroy_model_product :: proc(model: ^Model_Product) {
	if model == nil {
		return
	}
	for &material in model.materials {
		delete(material.key)
		delete(material.name)
		destroy_model_image(&material.base_color_image)
		destroy_model_image(&material.metallic_roughness_image)
		destroy_model_image(&material.normal_image)
		destroy_model_image(&material.occlusion_image)
		destroy_model_image(&material.emissive_image)
	}
	for &mesh in model.meshes {
		delete(mesh.key)
		delete(mesh.name)
		for &primitive in mesh.primitives {
			destroy_model_primitive(&primitive)
		}
		delete(mesh.primitives)
	}
	for &node in model.nodes {
		delete(node.key)
		delete(node.name)
	}
	delete(model.materials)
	delete(model.meshes)
	delete(model.nodes)
	model^ = {}
}

destroy_model_image :: proc(image: ^Model_Image) {
	if image == nil {
		return
	}
	delete(image.pixels)
	image^ = {}
}

ensure_model_import :: proc(
	root, build_dir: string,
	declaration: shared.Project_Resource,
	force: bool = false,
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
	if uri_err := validate_model_uris(data); uri_err != "" {
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
	source_hash, hash_err := model_import_hash(source, data, source_path, declaration.model)
	if hash_err != "" {
		return {}, false, fmt.tprintf("failed to fingerprint glTF model %s: %s", declaration.model.source, hash_err)
	}
	artifact_path, metadata_path, paths_err := model_product_paths(build_dir, declaration.id)
	if paths_err != "" {
		return {}, false, paths_err
	}
	defer delete(artifact_path)
	defer delete(metadata_path)
	metadata, cache_hit := read_model_cache(artifact_path, metadata_path, declaration, source_hash)
	if force {
		cache_hit = false
	}
	if !cache_hit {
		model, model_err := build_model_product(data, source_path, declaration.model)
		if model_err != "" {
			return {}, false, fmt.tprintf("failed to import glTF model %s: %s", declaration.model.source, model_err)
		}
		defer destroy_model_product(&model)
		written_metadata, write_err := write_model_product_atomically(
			artifact_path,
			metadata_path,
			declaration.model.source,
			source_hash,
			&model,
		)
		if write_err != "" {
			return {}, false, write_err
		}
		metadata = written_metadata
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
			lod_count = metadata.lod_count,
			lod_vertex_count = metadata.lod_vertex_count,
			lod_index_count = metadata.lod_index_count,
			cluster_count = metadata.cluster_count,
			cluster_group_count = metadata.cluster_group_count,
			cluster_page_count = metadata.cluster_page_count,
			material_count = metadata.material_count,
			texture_count = metadata.texture_count,
			ignored_texture_count = metadata.ignored_texture_count,
		},
		imported,
		""
}

validate_model_uris :: proc(data: ^cgltf.data) -> string {
	for buffer in data.buffers {
		if buffer.uri == nil {
			continue
		}
		if err := validate_model_uri(string(buffer.uri), "buffer"); err != "" {
			return err
		}
	}
	for image in data.images {
		if image.uri == nil {
			continue
		}
		if err := validate_model_uri(string(image.uri), "image"); err != "" {
			return err
		}
	}
	return ""
}

validate_model_uri :: proc(uri, kind: string) -> string {
	if strings.has_prefix(uri, "data:") {
		return ""
	}
	decoded_uri, clone_err := strings.clone_to_cstring(uri, context.temp_allocator)
	if clone_err != nil {
		return fmt.tprintf("failed to allocate external %s URI", kind)
	}
	_ = cgltf.decode_uri(cast([^]u8)decoded_uri)
	decoded: string = string(decoded_uri)
	if decoded == "" ||
	   strings.has_prefix(decoded, "/") ||
	   strings.contains(decoded, "\\") ||
	   strings.contains(decoded, ":") ||
	   strings.contains(decoded, "?") ||
	   strings.contains(decoded, "#") {
		return fmt.tprintf("external %s URI '%s' must be a safe relative path", kind, uri)
	}
	remaining: string = decoded
	for part in strings.split_iterator(&remaining, "/") {
		if part == "" || part == "." || part == ".." {
			return fmt.tprintf(
				"external %s URI '%s' must stay inside the model asset directory",
				kind,
				uri,
			)
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
	selection := model_scene_selection(data)
	defer destroy_model_scene_selection(&selection)
	for mesh, mesh_index in data.meshes {
		if !selection.meshes[mesh_index] {
			continue
		}
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
	for node, node_index in data.nodes {
		if !selection.nodes[node_index] {
			continue
		}
		if node.has_matrix {
			return(
				"matrix-authored node transforms are not supported yet; export node transforms as TRS" \
			)
		}
	}
	for &material, material_index in data.materials {
		if !selection.materials[material_index] {
			continue
		}
		if material.alpha_mode == .blend {
			return(
				"BLEND alpha materials require sorted transparent rendering and are not supported yet" \
			)
		}
		if material.has_pbr_metallic_roughness {
			if err := validate_model_texture_view(
				material.pbr_metallic_roughness.base_color_texture,
				"base-color",
			); err != "" {
				return err
			}
			if err := validate_model_texture_view(
				material.pbr_metallic_roughness.metallic_roughness_texture,
				"metallic-roughness",
			); err != "" {
				return err
			}
		}
		if err := validate_model_texture_view(material.normal_texture, "normal"); err != "" {
			return err
		}
		if err := validate_model_texture_view(material.occlusion_texture, "occlusion"); err != "" {
			return err
		}
		if err := validate_model_texture_view(material.emissive_texture, "emissive"); err != "" {
			return err
		}
	}
	return ""
}

Model_Scene_Selection :: struct {
	nodes, meshes, materials: []bool,
}

destroy_model_scene_selection :: proc(selection: ^Model_Scene_Selection) {
	if selection == nil {
		return
	}
	delete(selection.nodes)
	delete(selection.meshes)
	delete(selection.materials)
	selection^ = {}
}

model_scene_selection :: proc(data: ^cgltf.data) -> Model_Scene_Selection {
	selection := Model_Scene_Selection {
		nodes = make([]bool, len(data.nodes)),
		meshes = make([]bool, len(data.meshes)),
		materials = make([]bool, len(data.materials)),
	}
	pending: [dynamic]int
	defer delete(pending)
	scene := data.scene
	if scene == nil && len(data.scenes) > 0 {
		scene = &data.scenes[0]
	}
	if scene != nil {
		for node in scene.nodes {
			append(&pending, int(cgltf.node_index(data, node)))
		}
	} else {
		for &node, node_index in data.nodes {
			if node.parent == nil {
				append(&pending, node_index)
			}
		}
	}
	for len(pending) > 0 {
		pending_index := len(pending) - 1
		node_index := pending[pending_index]
		resize(&pending, pending_index)
		if node_index < 0 || node_index >= len(data.nodes) || selection.nodes[node_index] {
			continue
		}
		selection.nodes[node_index] = true
		node := &data.nodes[node_index]
		if node.mesh != nil {
			mesh_index := int(cgltf.mesh_index(data, node.mesh))
			if mesh_index >= 0 && mesh_index < len(selection.meshes) {
				selection.meshes[mesh_index] = true
			}
		}
		for child in node.children {
			append(&pending, int(cgltf.node_index(data, child)))
		}
	}
	for mesh, mesh_index in data.meshes {
		if !selection.meshes[mesh_index] {
			continue
		}
		for primitive in mesh.primitives {
			if primitive.material == nil {
				continue
			}
			material_index := int(cgltf.material_index(data, primitive.material))
			if material_index >= 0 && material_index < len(selection.materials) {
				selection.materials[material_index] = true
			}
		}
	}
	return selection
}

validate_model_texture_view :: proc(view: cgltf.texture_view, kind: string) -> string {
	if view.texture != nil && (view.texcoord != 0 || view.has_transform) {
		return fmt.tprintf(
			"%s texture coordinates and transforms other than TEXCOORD_0 are not supported yet",
			kind,
		)
	}
	return ""
}

model_import_hash :: proc(
	source: []u8,
	data: ^cgltf.data,
	source_path: string,
	settings: shared.Project_Model_Resource,
) -> (
	u64,
	string,
) {
	value := hash.fnv64a(source)
	value = hash.fnv64a(transmute([]byte)(string(MODEL_IMPORTER_SCHEMA)), value)
	generate_lods := settings.generate_lods
	lod_count := settings.lod_count
	lod_ratios := settings.lod_ratios
	lod_screen_radii := settings.lod_screen_radii
	value = hash.fnv64a((cast([^]u8)&generate_lods)[:size_of(generate_lods)], value)
	value = hash.fnv64a((cast([^]u8)&lod_count)[:size_of(lod_count)], value)
	value = hash.fnv64a((cast([^]u8)&lod_ratios)[:size_of(lod_ratios)], value)
	value = hash.fnv64a((cast([^]u8)&lod_screen_radii)[:size_of(lod_screen_radii)], value)
	for buffer in data.buffers {
		if buffer.data != nil && buffer.size > 0 {
			value = hash.fnv64a((cast([^]u8)buffer.data)[:buffer.size], value)
		}
	}
	for &image in data.images {
		bytes, image_err := load_model_image_bytes(&image, source_path)
		if image_err != "" {
			return 0, image_err
		}
		value = hash.fnv64a(bytes, value)
		delete(bytes)
	}
	return value, ""
}

build_model_product :: proc(
	data: ^cgltf.data,
	source_path: string,
	settings: shared.Project_Model_Resource,
) -> (
	model: Model_Product,
	err: string,
) {
	selection := model_scene_selection(data)
	defer destroy_model_scene_selection(&selection)
	material_remap := make([]i32, len(data.materials), context.temp_allocator)
	mesh_remap := make([]i32, len(data.meshes), context.temp_allocator)
	node_remap := make([]i32, len(data.nodes), context.temp_allocator)
	for &index in material_remap {
		index = -1
	}
	for &index in mesh_remap {
		index = -1
	}
	for &index in node_remap {
		index = -1
	}
	for &material, material_index in data.materials {
		if !selection.materials[material_index] {
			continue
		}
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
		imported_material := Model_Material {
			key = model_semantic_key("material", material.name, material_index),
			name = name,
			base_color = base_color,
			emissive = emissive,
			metallic_factor = 1,
			roughness_factor = 1,
			normal_scale = 1,
			occlusion_strength = 1,
			alpha_cutoff = material.alpha_cutoff,
			double_sided = bool(material.double_sided),
		}
		if material.alpha_mode == .mask {
			imported_material.alpha_mode = .Mask
		}
		if material.has_pbr_metallic_roughness {
			pbr := material.pbr_metallic_roughness
			imported_material.metallic_factor = pbr.metallic_factor
			imported_material.roughness_factor = pbr.roughness_factor
			if image_err := decode_model_material_image(
				pbr.base_color_texture,
				source_path,
				&imported_material.base_color_image,
			); image_err != "" {
				destroy_model_material(&imported_material)
				destroy_model_product(&model)
				return {}, fmt.tprintf("material %d base-color texture: %s", material_index, image_err)
			}
			if image_err := decode_model_material_image(
				pbr.metallic_roughness_texture,
				source_path,
				&imported_material.metallic_roughness_image,
			); image_err != "" {
				destroy_model_material(&imported_material)
				destroy_model_product(&model)
				return {}, fmt.tprintf("material %d metallic-roughness texture: %s", material_index, image_err)
			}
		}
		if material.normal_texture.texture != nil {
			imported_material.normal_scale = material.normal_texture.scale
		}
		if material.occlusion_texture.texture != nil {
			imported_material.occlusion_strength = material.occlusion_texture.scale
		}
		views := [?]cgltf.texture_view {
			material.normal_texture,
			material.occlusion_texture,
			material.emissive_texture,
		}
		images := [?]^Model_Image {
			&imported_material.normal_image,
			&imported_material.occlusion_image,
			&imported_material.emissive_image,
		}
		labels := [?]string{"normal", "occlusion", "emissive"}
		for view, index in views {
			if image_err := decode_model_material_image(view, source_path, images[index]);
			   image_err != "" {
				destroy_model_material(&imported_material)
				destroy_model_product(&model)
				return {}, fmt.tprintf("material %d %s texture: %s", material_index, labels[index], image_err)
			}
		}
		delete(imported_material.key)
		imported_material.key = model_material_semantic_key(
			data,
			&material,
			material_index,
			&imported_material,
		)
		material_remap[material_index] = i32(len(model.materials))
		append(&model.materials, imported_material)
	}
	for &mesh, mesh_index in data.meshes {
		if !selection.meshes[mesh_index] {
			continue
		}
		imported_mesh := Model_Mesh {
			key = model_semantic_key("mesh", mesh.name, mesh_index),
			name = model_item_name(mesh.name, "mesh", mesh_index),
		}
		for &primitive in mesh.primitives {
			imported_primitive, primitive_err := build_model_primitive(data, &primitive)
			if primitive_err != "" {
				destroy_model_product(&model)
				destroy_model_mesh(&imported_mesh)
				return {}, primitive_err
			}
			if imported_primitive.material_index >= 0 {
				imported_primitive.material_index =
					material_remap[imported_primitive.material_index]
			}
			if settings.generate_lods {
				build_model_primitive_lods(&imported_primitive, settings)
			}
			if hierarchy_err := build_model_primitive_hierarchies(&imported_primitive);
			   hierarchy_err != "" {
				destroy_model_primitive(&imported_primitive)
				destroy_model_product(&model)
				destroy_model_mesh(&imported_mesh)
				return {}, hierarchy_err
			}
			append(&imported_mesh.primitives, imported_primitive)
		}
		delete(imported_mesh.key)
		imported_mesh.key = model_mesh_semantic_key(data, &mesh, mesh_index, &imported_mesh)
		for &primitive in imported_mesh.primitives {
			material_key := "default"
			if primitive.material_index >= 0 {
				material_key = model.materials[primitive.material_index].key
			}
			primitive.key = fmt.aprintf("%s/primitive:%s", imported_mesh.key, material_key)
		}
		for &primitive in imported_mesh.primitives {
			duplicate_count := 0
			for candidate in imported_mesh.primitives {
				if candidate.material_index == primitive.material_index {
					duplicate_count += 1
				}
			}
			if duplicate_count > 1 {
				base_key := primitive.key
				primitive.key = fmt.aprintf(
					"%s:geometry:%016x",
					base_key,
					model_primitive_fingerprint(&primitive),
				)
				delete(base_key)
			}
		}
		mesh_remap[mesh_index] = i32(len(model.meshes))
		append(&model.meshes, imported_mesh)
	}
	for &node, node_index in data.nodes {
		if !selection.nodes[node_index] {
			continue
		}
		node_remap[node_index] = i32(len(model.nodes))
		node_key := model_semantic_key("node", node.name, node_index)
		if node.name == nil || string(node.name) == "" {
			delete(node_key)
			mesh_key := "empty"
			if node.mesh != nil {
				imported_mesh_index := mesh_remap[cgltf.mesh_index(data, node.mesh)]
				if imported_mesh_index >= 0 {
					mesh_key = model.meshes[imported_mesh_index].key
				}
			}
			node_key = fmt.aprintf("node:unnamed:%s", mesh_key)
		}
		imported_node := Model_Node {
			key = node_key,
			name = model_item_name(node.name, "node", node_index),
			parent_index = -1,
			mesh_index = -1,
			transform = {scale = {1, 1, 1}},
		}
		if node.mesh != nil {
			imported_node.mesh_index = mesh_remap[cgltf.mesh_index(data, node.mesh)]
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
	for &node, node_index in data.nodes {
		if !selection.nodes[node_index] || node.parent == nil {
			continue
		}
		imported_index := node_remap[node_index]
		parent_source_index := cgltf.node_index(data, node.parent)
		if imported_index >= 0 && node_remap[parent_source_index] >= 0 {
			model.nodes[imported_index].parent_index = node_remap[parent_source_index]
		}
	}
	if key_err := model_qualify_node_keys(&model); key_err != "" {
		destroy_model_product(&model)
		return {}, key_err
	}
	return model, ""
}

model_qualify_node_keys :: proc(model: ^Model_Product) -> string {
	for &node in model.nodes {
		duplicate_count := 0
		for sibling in model.nodes {
			if sibling.parent_index != node.parent_index || sibling.name != node.name {
				continue
			}
			duplicate_count += 1
		}
		if duplicate_count < 2 {
			continue
		}
		mesh_key := "empty"
		if node.mesh_index >= 0 && int(node.mesh_index) < len(model.meshes) {
			mesh_key = model.meshes[node.mesh_index].key
		}
		discriminator := fmt.tprintf(
			"%s:%s:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f",
			node.key,
			mesh_key,
			node.transform.position.x,
			node.transform.position.y,
			node.transform.position.z,
			node.transform.rotation.x,
			node.transform.rotation.y,
			node.transform.rotation.z,
			node.transform.scale.x,
			node.transform.scale.y,
			node.transform.scale.z,
		)
		previous := node.key
		node.key = fmt.aprintf("%s:%016x", previous, hash.fnv64a(transmute([]byte)discriminator))
		delete(previous)
	}
	for &node, node_index in model.nodes {
		occurrence := 0
		for previous_index in 0 ..< node_index {
			previous := model.nodes[previous_index]
			if previous.parent_index == node.parent_index &&
			   previous.name == node.name &&
			   previous.mesh_index == node.mesh_index &&
			   previous.transform == node.transform {
				occurrence += 1
			}
		}
		if occurrence > 0 {
			previous := node.key
			node.key = fmt.aprintf("%s:occurrence:%d", previous, occurrence)
			delete(previous)
		}
	}
	states := make([]u8, len(model.nodes), context.temp_allocator)
	for node_index in 0 ..< len(model.nodes) {
		if err := model_qualify_node_key(model, node_index, states); err != "" {
			return err
		}
	}
	return ""
}

model_qualify_node_key :: proc(model: ^Model_Product, node_index: int, states: []u8) -> string {
	if states[node_index] == 2 {
		return ""
	}
	if states[node_index] == 1 {
		return "model node hierarchy contains a cycle"
	}
	states[node_index] = 1
	node := &model.nodes[node_index]
	leaf := node.key
	if node.parent_index >= 0 {
		parent_index := int(node.parent_index)
		if err := model_qualify_node_key(model, parent_index, states); err != "" {
			return err
		}
		node.key = fmt.aprintf("%s/%s", model.nodes[parent_index].key, leaf)
		delete(leaf)
	}
	states[node_index] = 2
	return ""
}

destroy_model_material :: proc(material: ^Model_Material) {
	if material == nil {
		return
	}
	delete(material.key)
	delete(material.name)
	destroy_model_image(&material.base_color_image)
	destroy_model_image(&material.metallic_roughness_image)
	destroy_model_image(&material.normal_image)
	destroy_model_image(&material.occlusion_image)
	destroy_model_image(&material.emissive_image)
	material^ = {}
}

decode_model_material_image :: proc(
	view: cgltf.texture_view,
	source_path: string,
	image: ^Model_Image,
) -> string {
	if view.texture == nil {
		return ""
	}
	pixels, width, height, mip_count, err := decode_model_texture(view.texture, source_path)
	if err != "" {
		return err
	}
	image^ = {
		pixels = pixels,
		width = width,
		height = height,
		mip_count = mip_count,
		sampler = model_texture_sampler(view.texture.sampler),
	}
	return ""
}

model_texture_sampler :: proc(sampler: ^cgltf.sampler) -> shared.Texture_Sampler {
	result := shared.Texture_Sampler {
		mag_filter = .Linear,
		min_filter = .Linear,
		mipmap_filter = .Linear,
		address_u = .Repeat,
		address_v = .Repeat,
	}
	if sampler == nil {
		return result
	}
	if sampler.mag_filter == .nearest {
		result.mag_filter = .Nearest
	}
	#partial switch sampler.min_filter {
		case .nearest:
			result.min_filter = .Nearest
			result.mipmap_filter = .Base_Only
		case .linear:
			result.min_filter = .Linear
			result.mipmap_filter = .Base_Only
		case .nearest_mipmap_nearest:
			result.min_filter = .Nearest
			result.mipmap_filter = .Nearest
		case .linear_mipmap_nearest:
			result.min_filter = .Linear
			result.mipmap_filter = .Nearest
		case .nearest_mipmap_linear:
			result.min_filter = .Nearest
			result.mipmap_filter = .Linear
		case .linear_mipmap_linear, .undefined:
			result.min_filter = .Linear
			result.mipmap_filter = .Linear
	}
	#partial switch sampler.wrap_s {
		case .clamp_to_edge:
			result.address_u = .Clamp_To_Edge
		case .mirrored_repeat:
			result.address_u = .Mirrored_Repeat
		case .repeat:
			result.address_u = .Repeat
	}
	#partial switch sampler.wrap_t {
		case .clamp_to_edge:
			result.address_v = .Clamp_To_Edge
		case .mirrored_repeat:
			result.address_v = .Mirrored_Repeat
		case .repeat:
			result.address_v = .Repeat
	}
	return result
}

decode_model_texture :: proc(
	texture: ^cgltf.texture,
	source_path: string,
) -> (
	pixels: []u8,
	width, height, mip_count: u32,
	err: string,
) {
	if texture == nil {
		return nil, 0, 0, 0, "texture is missing"
	}
	if texture.has_basisu {
		return nil, 0, 0, 0, "KTX2/Basis Universal images are not supported yet"
	}
	if texture.image_ == nil {
		return nil, 0, 0, 0, "texture image is missing"
	}
	encoded, image_err := load_model_image_bytes(texture.image_, source_path)
	if image_err != "" {
		return nil, 0, 0, 0, image_err
	}
	defer delete(encoded)
	decode_err: string
	pixels, width, height, mip_count, decode_err = decode_texture_product(encoded, true)
	if decode_err != "" {
		return nil, 0, 0, 0, fmt.tprintf("failed to decode image: %s", decode_err)
	}
	return pixels, width, height, mip_count, ""
}

load_model_image_bytes :: proc(image: ^cgltf.image, source_path: string) -> ([]u8, string) {
	if image == nil {
		return nil, "image is missing"
	}
	if image.buffer_view != nil {
		if image.buffer_view.size == 0 {
			return nil, "embedded image buffer is empty"
		}
		data := cgltf.buffer_view_data(image.buffer_view)
		if data == nil {
			return nil, "embedded image buffer is unavailable"
		}
		bytes := make([]u8, int(image.buffer_view.size))
		copy(bytes, data[:image.buffer_view.size])
		return bytes, ""
	}
	if image.uri == nil {
		return nil, "image has neither a buffer view nor a URI"
	}
	uri := string(image.uri)
	if strings.has_prefix(uri, "data:") {
		comma := strings.index_byte(uri, ',')
		if comma < 0 || !strings.contains(uri[:comma], ";base64") {
			return nil, "image data URI must use base64 encoding"
		}
		decoded, decode_err := base64.decode(uri[comma + 1:])
		if decode_err != nil {
			return nil, "image data URI contains invalid base64"
		}
		return decoded, ""
	}
	decoded_uri, clone_err := strings.clone_to_cstring(uri, context.temp_allocator)
	if clone_err != nil {
		return nil, "failed to allocate external image URI"
	}
	_ = cgltf.decode_uri(cast([^]u8)decoded_uri)
	directory := filepath.dir(source_path)
	path, join_err := filepath.join({directory, string(decoded_uri)})
	if join_err != nil {
		return nil, "failed to allocate external image path"
	}
	defer delete(path)
	bytes, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return nil, fmt.tprintf("failed to read external image '%s': %v", uri, read_err)
	}
	return bytes, ""
}

build_model_primitive :: proc(
	data: ^cgltf.data,
	primitive: ^cgltf.primitive,
) -> (
	result: Model_Primitive,
	err: string,
) {
	position: ^cgltf.accessor
	normal: ^cgltf.accessor
	uv: ^cgltf.accessor
	tangent: ^cgltf.accessor
	for attribute in primitive.attributes {
		#partial switch attribute.type {
			case .position:
				if attribute.index == 0 { position = attribute.data }
			case .normal:
				if attribute.index == 0 { normal = attribute.data }
			case .texcoord:
				if attribute.index == 0 { uv = attribute.data }
			case .tangent:
				if attribute.index == 0 { tangent = attribute.data }
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
	if tangent != nil && (tangent.type != .vec4 || tangent.count != position.count) {
		return {}, "TANGENT must be a VEC4 accessor matching POSITION count"
	}
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
		if tangent != nil {
			tangent_value: [4]f32
			if !cgltf.accessor_read_float(
				tangent,
				uint(vertex_index),
				raw_data(tangent_value[:]),
				4,
			) {
				destroy_model_primitive(&result)
				return {}, "failed to decode TANGENT accessor"
			}
			result.vertices[vertex_index].tangent = {
				tangent_value[0],
				tangent_value[1],
				tangent_value[2],
				tangent_value[3],
			}
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
	delete(primitive.query_positions)
	delete(primitive.page_payloads)
	geometry.destroy_hierarchy(&primitive.hierarchy)
	for &lod in primitive.lods {
		delete(lod.vertices)
		delete(lod.indices)
		delete(lod.query_positions)
		delete(lod.page_payloads)
		geometry.destroy_hierarchy(&lod.hierarchy)
	}
	delete(primitive.lods)
	primitive^ = {}
}

build_model_primitive_hierarchies :: proc(primitive: ^Model_Primitive) -> string {
	if primitive == nil {
		return "imported model primitive is unavailable"
	}
	hierarchy, hierarchy_err := geometry.build_hierarchy(
		primitive.indices[:],
		raw_data(primitive.vertices[:]),
		len(primitive.vertices),
		size_of(Model_Vertex),
	)
	if hierarchy_err != "" {
		return hierarchy_err
	}
	geometry.destroy_hierarchy(&primitive.hierarchy)
	primitive.hierarchy = hierarchy
	for &lod in primitive.lods {
		lod_hierarchy, lod_hierarchy_err := geometry.build_hierarchy(
			lod.indices[:],
			raw_data(lod.vertices[:]),
			len(lod.vertices),
			size_of(Model_Vertex),
		)
		if lod_hierarchy_err != "" {
			return lod_hierarchy_err
		}
		geometry.destroy_hierarchy(&lod.hierarchy)
		lod.hierarchy = lod_hierarchy
	}
	return ""
}

destroy_model_mesh :: proc(mesh: ^Model_Mesh) {
	if mesh == nil {
		return
	}
	delete(mesh.key)
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

model_semantic_key :: proc(kind: string, value: cstring, fallback_index: int) -> string {
	if value != nil && string(value) != "" {
		return fmt.aprintf("%s:%s", kind, string(value))
	}
	return fmt.aprintf("%s:unnamed:%d", kind, fallback_index)
}

model_material_semantic_key :: proc(
	data: ^cgltf.data,
	source: ^cgltf.material,
	source_index: int,
	material: ^Model_Material,
) -> string {
	name := ""
	if source.name != nil {
		name = string(source.name)
	}
	duplicate_count := 0
	if name != "" {
		for candidate in data.materials {
			if candidate.name != nil && string(candidate.name) == name {
				duplicate_count += 1
			}
		}
	}
	if name != "" && duplicate_count == 1 {
		return model_semantic_key("material", source.name, source_index)
	}
	description := fmt.tprintf(
		"%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%.9f:%d:%d",
		material.base_color.x,
		material.base_color.y,
		material.base_color.z,
		material.base_color.w,
		material.emissive.x,
		material.emissive.y,
		material.emissive.z,
		material.metallic_factor,
		material.roughness_factor,
		material.alpha_mode,
		material.double_sided,
	)
	value := hash.fnv64a(transmute([]byte)description)
	images := [?]Model_Image {
		material.base_color_image,
		material.metallic_roughness_image,
		material.normal_image,
		material.occlusion_image,
		material.emissive_image,
	}
	for image in images {
		value = hash.fnv64a(image.pixels, value)
	}
	if name == "" {
		return fmt.aprintf("material:unnamed:%016x", value)
	}
	return fmt.aprintf("material:%s:%016x", name, value)
}

model_mesh_semantic_key :: proc(
	data: ^cgltf.data,
	source: ^cgltf.mesh,
	source_index: int,
	mesh: ^Model_Mesh,
) -> string {
	name := ""
	if source.name != nil {
		name = string(source.name)
	}
	duplicate_count := 0
	if name != "" {
		for candidate in data.meshes {
			if candidate.name != nil && string(candidate.name) == name {
				duplicate_count += 1
			}
		}
	}
	if name != "" && duplicate_count == 1 {
		return model_semantic_key("mesh", source.name, source_index)
	}
	value := hash.fnv64a(transmute([]byte)(string("scrapbot:mesh")))
	for &primitive in mesh.primitives {
		fingerprint := model_primitive_fingerprint(&primitive)
		value = hash.fnv64a((cast([^]u8)&fingerprint)[:size_of(fingerprint)], value)
	}
	if name == "" {
		return fmt.aprintf("mesh:unnamed:%016x", value)
	}
	return fmt.aprintf("mesh:%s:%016x", name, value)
}

model_primitive_fingerprint :: proc(primitive: ^Model_Primitive) -> u64 {
	value := hash.fnv64a(
		(cast([^]u8)raw_data(primitive.vertices[:]))[:size_of(Model_Vertex) *
		len(primitive.vertices)],
	)
	return hash.fnv64a(
		(cast([^]u8)raw_data(primitive.indices[:]))[:size_of(u32) * len(primitive.indices)],
		value,
	)
}

model_metadata :: proc(
	source: string,
	source_hash: u64,
	byte_count: int,
	model: ^Model_Product,
) -> Model_Metadata {
	metadata := Model_Metadata {
		schema = MODEL_IMPORTER_SCHEMA,
		source = source,
		source_hash = source_hash,
		byte_count = byte_count,
		node_count = len(model.nodes),
		mesh_count = len(model.meshes),
		material_count = len(model.materials),
	}
	for mesh in model.meshes {
		metadata.primitive_count += len(mesh.primitives)
		for primitive in mesh.primitives {
			metadata.vertex_count += len(primitive.vertices)
			metadata.index_count += len(primitive.indices)
			metadata.cluster_count += len(primitive.hierarchy.clusters)
			metadata.cluster_group_count += len(primitive.hierarchy.groups)
			metadata.cluster_page_count += len(primitive.hierarchy.pages)
			metadata.lod_count += len(primitive.lods)
			for lod in primitive.lods {
				metadata.lod_vertex_count += len(lod.vertices)
				metadata.lod_index_count += len(lod.indices)
				metadata.cluster_count += len(lod.hierarchy.clusters)
				metadata.cluster_group_count += len(lod.hierarchy.groups)
				metadata.cluster_page_count += len(lod.hierarchy.pages)
			}
		}
	}
	for material in model.materials {
		images := [?]Model_Image {
			material.base_color_image,
			material.metallic_roughness_image,
			material.normal_image,
			material.occlusion_image,
			material.emissive_image,
		}
		for image in images {
			if len(image.pixels) > 0 {
				metadata.texture_count += 1
			}
		}
		metadata.ignored_texture_count += int(material.ignored_texture_count)
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

encode_model_product_for_test :: proc(model: ^Model_Product) -> []u8 {
	root, root_err := os.make_directory_temp("", "scrapbot-model-product-*", context.allocator)
	assert(root_err == nil)
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "model.bin"})
	assert(path_err == nil)
	defer delete(path)
	detail_path, detail_path_err := filepath.join({root, "detail.pages"})
	assert(detail_path_err == nil)
	defer delete(detail_path)
	_, write_err := write_model_product_file(path, detail_path, model)
	assert(write_err == "")
	bytes, read_err := os.read_entire_file(path, context.allocator)
	assert(read_err == nil)
	return bytes
}

write_model_product_atomically :: proc(
	artifact_path, metadata_path, source: string,
	source_hash: u64,
	model: ^Model_Product,
) -> (
	metadata: Model_Metadata,
	err: string,
) {
	artifact_temp := fmt.tprintf("%s.tmp", artifact_path)
	detail_temp := fmt.tprintf("%s.pages.tmp", artifact_path)
	metadata_temp := fmt.tprintf("%s.tmp", metadata_path)
	defer os.remove(artifact_temp)
	defer os.remove(detail_temp)
	defer os.remove(metadata_temp)
	byte_count, product_err := write_model_product_file(artifact_temp, detail_temp, model)
	if product_err != "" {
		return {}, product_err
	}
	metadata = model_metadata(source, source_hash, byte_count, model)
	metadata_bytes, marshal_err := json.marshal(metadata)
	if marshal_err != nil {
		return {}, "failed to encode model import metadata"
	}
	defer delete(metadata_bytes)
	if write_err := os.write_entire_file(metadata_temp, metadata_bytes); write_err != nil {
		return {}, fmt.tprintf("failed to write imported model metadata: %v", write_err)
	}
	if rename_err := os.rename(artifact_temp, artifact_path); rename_err != nil {
		return {}, fmt.tprintf("failed to install imported model product: %v", rename_err)
	}
	if rename_err := os.rename(metadata_temp, metadata_path); rename_err != nil {
		return {}, fmt.tprintf("failed to install imported model metadata: %v", rename_err)
	}
	return metadata, ""
}

write_model_product_file :: proc(
	path, detail_path: string,
	model: ^Model_Product,
) -> (
	int,
	string,
) {
	if model == nil {
		return 0, "imported model product is unavailable"
	}
	file, create_err := os.create(path)
	if create_err != nil {
		return 0, fmt.tprintf("failed to create imported model product: %v", create_err)
	}
	file_open := true
	defer if file_open {
		os.close(file)
	}
	detail_file, detail_err := os.create(detail_path)
	if detail_err != nil {
		return 0, fmt.tprintf("failed to create imported model page spool: %v", detail_err)
	}
	defer os.close(detail_file)
	writer, begin_err := asset_product_stream_begin(file, .Model, MODEL_PRODUCT_CHUNK_COUNT)
	if begin_err != "" {
		return 0, begin_err
	}
	defer destroy_asset_product_stream_writer(&writer)
	if !asset_product_stream_begin_chunk(&writer, .Model_Material_Images) {
		return 0, "failed to begin imported model image chunk"
	}
	image_magic := MODEL_IMAGE_CHUNK_MAGIC
	if !asset_product_stream_write(&writer, image_magic[:]) ||
	   !model_stream_images(&writer, model) ||
	   !asset_product_stream_finish_chunk(&writer) {
		return 0, "failed to write imported model image chunk"
	}
	if !asset_product_stream_begin_chunk(&writer, .Model_Coarse_Geometry) {
		return 0, "failed to begin imported model coarse-geometry chunk"
	}
	coarse_magic := MODEL_COARSE_CHUNK_MAGIC
	if !asset_product_stream_write(&writer, coarse_magic[:]) {
		return 0, "failed to write imported model coarse-geometry chunk"
	}
	detail_size, pages_err := model_stream_geometry_pages(&writer, detail_file, model)
	if pages_err != "" || !asset_product_stream_finish_chunk(&writer) {
		return 0,
			pages_err if pages_err != "" else "failed to finish imported model coarse-geometry chunk"
	}
	if !asset_product_stream_begin_chunk(&writer, .Model_Detail_Geometry) {
		return 0, "failed to begin imported model detail-geometry chunk"
	}
	detail_magic := MODEL_DETAIL_CHUNK_MAGIC
	if !asset_product_stream_write(&writer, detail_magic[:]) {
		return 0, "failed to write imported model detail-geometry chunk"
	}
	detail_base := writer.offset
	model_rebase_detail_page_records(model, detail_base)
	if !model_copy_page_spool(&writer, detail_file, detail_size) ||
	   !asset_product_stream_finish_chunk(&writer) {
		return 0, "failed to write imported model detail-geometry chunk"
	}
	if !asset_product_stream_begin_chunk(&writer, .Model_Catalog) ||
	   !model_stream_catalog(&writer, model) ||
	   !asset_product_stream_finish_chunk(&writer) {
		return 0, "failed to write imported model catalog chunk"
	}
	byte_count, finish_err := asset_product_stream_finish(&writer)
	if finish_err != "" {
		return 0, finish_err
	}
	if close_err := os.close(file); close_err != nil {
		return 0, "failed to close imported model product"
	}
	file_open = false
	return byte_count, ""
}

model_stream_images :: proc(writer: ^Asset_Product_Stream_Writer, model: ^Model_Product) -> bool {
	for &material in model.materials {
		images := [?]^Model_Image {
			&material.base_color_image,
			&material.metallic_roughness_image,
			&material.normal_image,
			&material.occlusion_image,
			&material.emissive_image,
		}
		for image in images {
			image.product_offset = 0
			image.product_size = 0
			if len(image.pixels) == 0 {
				continue
			}
			image.product_offset = writer.offset
			image.product_size = u64(len(image.pixels))
			if !asset_product_stream_write(writer, image.pixels) {
				return false
			}
		}
	}
	return true
}

model_stream_geometry_pages :: proc(
	writer: ^Asset_Product_Stream_Writer,
	detail_file: ^os.File,
	model: ^Model_Product,
) -> (
	detail_size: u64,
	err: string,
) {
	for &mesh in model.meshes {
		for &primitive in mesh.primitives {
			detail_size, err = model_stream_page_payloads(
				writer,
				detail_file,
				primitive.hierarchy,
				raw_data(primitive.vertices[:]),
				len(primitive.vertices),
				&primitive.page_payloads,
				detail_size,
			)
			if err != "" {
				return detail_size, err
			}
			for &lod in primitive.lods {
				detail_size, err = model_stream_page_payloads(
					writer,
					detail_file,
					lod.hierarchy,
					raw_data(lod.vertices[:]),
					len(lod.vertices),
					&lod.page_payloads,
					detail_size,
				)
				if err != "" {
					return detail_size, err
				}
			}
		}
	}
	return detail_size, ""
}

model_stream_page_payloads :: proc(
	writer: ^Asset_Product_Stream_Writer,
	detail_file: ^os.File,
	hierarchy: geometry.Hierarchy,
	vertices: rawptr,
	vertex_count: int,
	records: ^[]geometry.Page_Payload_Record,
	detail_offset: u64,
) -> (
	u64,
	string,
) {
	detail_cursor := detail_offset
	hierarchy_copy := hierarchy
	payloads, payload_err := geometry.build_page_payloads(
		&hierarchy_copy,
		vertices,
		vertex_count,
		size_of(Model_Vertex),
	)
	if payload_err != "" {
		return detail_offset, payload_err
	}
	defer geometry.destroy_page_payloads(&payloads)
	delete(records^)
	records^ = make([]geometry.Page_Payload_Record, len(payloads.records))
	for source_record, page_index in payloads.records {
		start := int(source_record.offset)
		payload := payloads.bytes[start:start + int(source_record.size)]
		record := source_record
		if hierarchy.pages[page_index].pinned {
			record.offset = writer.offset
			if !asset_product_stream_write(writer, payload) {
				return detail_cursor, "failed to stream imported model coarse page"
			}
		} else {
			record.offset = detail_cursor
			written, write_err := os.write(detail_file, payload)
			if write_err != nil || written != len(payload) {
				return detail_cursor, "failed to spool imported model detail page"
			}
			detail_cursor += u64(written)
		}
		records^[page_index] = record
	}
	return detail_cursor, ""
}

model_rebase_detail_page_records :: proc(model: ^Model_Product, detail_base: u64) {
	for &mesh in model.meshes {
		for &primitive in mesh.primitives {
			model_rebase_page_records(primitive.hierarchy, primitive.page_payloads, detail_base)
			for &lod in primitive.lods {
				model_rebase_page_records(lod.hierarchy, lod.page_payloads, detail_base)
			}
		}
	}
}

model_rebase_page_records :: proc(
	hierarchy: geometry.Hierarchy,
	records: []geometry.Page_Payload_Record,
	detail_base: u64,
) {
	for &record, page_index in records {
		if !hierarchy.pages[page_index].pinned {
			record.offset += detail_base
		}
	}
}

model_copy_page_spool :: proc(
	writer: ^Asset_Product_Stream_Writer,
	detail_file: ^os.File,
	detail_size: u64,
) -> bool {
	buffer := make([]u8, 1024 * 1024, context.temp_allocator)
	offset: u64
	for offset < detail_size {
		count := int(min(u64(len(buffer)), detail_size - offset))
		read_count, read_err := os.read_at(detail_file, buffer[:count], i64(offset))
		if read_err != nil ||
		   read_count != count ||
		   !asset_product_stream_write(writer, buffer[:count]) {
			return false
		}
		offset += u64(count)
	}
	return true
}

model_stream_catalog :: proc(writer: ^Asset_Product_Stream_Writer, model: ^Model_Product) -> bool {
	bytes: [dynamic]u8
	defer delete(bytes)
	magic := MODEL_CATALOG_MAGIC
	model_write_bytes(&bytes, magic[:])
	model_write_u32(&bytes, u32(len(model.materials)))
	model_write_u32(&bytes, u32(len(model.meshes)))
	model_write_u32(&bytes, u32(len(model.nodes)))
	if !model_stream_catalog_record(writer, &bytes) {
		return false
	}
	for material in model.materials {
		model_write_material_record(&bytes, material)
		if !model_stream_catalog_record(writer, &bytes) {
			return false
		}
	}
	for mesh in model.meshes {
		model_write_string(&bytes, mesh.key)
		model_write_string(&bytes, mesh.name)
		model_write_u32(&bytes, u32(len(mesh.primitives)))
		if !model_stream_catalog_record(writer, &bytes) {
			return false
		}
		for primitive in mesh.primitives {
			model_write_primitive_record(&bytes, primitive)
			if !model_stream_catalog_record(writer, &bytes) {
				return false
			}
		}
	}
	for node in model.nodes {
		model_write_node_record(&bytes, node)
		if !model_stream_catalog_record(writer, &bytes) {
			return false
		}
	}
	return true
}

model_stream_catalog_record :: proc(
	writer: ^Asset_Product_Stream_Writer,
	bytes: ^[dynamic]u8,
) -> bool {
	if len(bytes^) == 0 || !asset_product_stream_write(writer, bytes^[:]) {
		return false
	}
	clear(bytes)
	return true
}

model_write_material_record :: proc(bytes: ^[dynamic]u8, material: Model_Material) {
	model_write_string(bytes, material.key)
	model_write_string(bytes, material.name)
	model_write_vec4(bytes, material.base_color)
	model_write_vec3(bytes, material.emissive)
	model_write_f32(bytes, material.metallic_factor)
	model_write_f32(bytes, material.roughness_factor)
	model_write_f32(bytes, material.normal_scale)
	model_write_f32(bytes, material.occlusion_strength)
	model_write_u32(bytes, u32(material.alpha_mode))
	model_write_f32(bytes, material.alpha_cutoff)
	model_write_u32(bytes, 1 if material.double_sided else 0)
	model_write_image_descriptor(bytes, material.base_color_image)
	model_write_image_descriptor(bytes, material.metallic_roughness_image)
	model_write_image_descriptor(bytes, material.normal_image)
	model_write_image_descriptor(bytes, material.occlusion_image)
	model_write_image_descriptor(bytes, material.emissive_image)
	model_write_u32(bytes, material.ignored_texture_count)
}

model_write_primitive_record :: proc(bytes: ^[dynamic]u8, primitive: Model_Primitive) {
	model_write_string(bytes, primitive.key)
	model_write_i32(bytes, primitive.material_index)
	model_write_u32(bytes, u32(len(primitive.vertices)))
	model_write_u32(bytes, u32(len(primitive.indices)))
	for vertex in primitive.vertices {
		model_write_vec3(bytes, vertex.position)
	}
	model_write_hierarchy(bytes, primitive.hierarchy)
	model_write_page_records(bytes, primitive.page_payloads)
	model_write_u32(bytes, u32(len(primitive.lods)))
	for lod in primitive.lods {
		model_write_u32(bytes, lod.level)
		model_write_f32(bytes, lod.screen_radius)
		model_write_f32(bytes, lod.simplification_error)
		model_write_u32(bytes, u32(len(lod.vertices)))
		model_write_u32(bytes, u32(len(lod.indices)))
		for vertex in lod.vertices {
			model_write_vec3(bytes, vertex.position)
		}
		model_write_hierarchy(bytes, lod.hierarchy)
		model_write_page_records(bytes, lod.page_payloads)
	}
}

model_write_node_record :: proc(bytes: ^[dynamic]u8, node: Model_Node) {
	model_write_string(bytes, node.key)
	model_write_string(bytes, node.name)
	model_write_i32(bytes, node.parent_index)
	model_write_i32(bytes, node.mesh_index)
	model_write_vec3(bytes, node.transform.position)
	model_write_vec3(bytes, node.transform.rotation)
	model_write_vec3(bytes, node.transform.scale)
}

model_write_page_records :: proc(bytes: ^[dynamic]u8, records: []geometry.Page_Payload_Record) {
	model_write_u32(bytes, u32(len(records)))
	for record in records {
		model_write_u32(bytes, record.vertex_count)
		model_write_u32(bytes, record.index_count)
		model_write_u64(bytes, record.offset)
		model_write_u64(bytes, record.size)
	}
}

model_write_hierarchy :: proc(bytes: ^[dynamic]u8, hierarchy: geometry.Hierarchy) {
	model_write_u32(bytes, hierarchy.max_depth)
	model_write_u32(bytes, u32(len(hierarchy.groups)))
	model_write_u32(bytes, u32(len(hierarchy.clusters)))
	model_write_u32(bytes, u32(len(hierarchy.pages)))
	model_write_u32(bytes, u32(len(hierarchy.vertices)))
	model_write_u32(bytes, u32(len(hierarchy.triangles)))
	for group in hierarchy.groups {
		for value in group.bounds {
			model_write_f32(bytes, value)
		}
		model_write_f32(bytes, group.error)
		model_write_u32(bytes, group.depth)
		model_write_u32(bytes, group.cluster_offset)
		model_write_u32(bytes, group.cluster_count)
		model_write_u32(bytes, group.page_offset)
		model_write_u32(bytes, group.page_count)
	}
	for cluster in hierarchy.clusters {
		model_write_u32(bytes, cluster.vertex_offset)
		model_write_u32(bytes, cluster.triangle_offset)
		model_write_u32(bytes, cluster.vertex_count)
		model_write_u32(bytes, cluster.triangle_count)
		for value in cluster.bounds {
			model_write_f32(bytes, value)
		}
		for value in cluster.cone_axis_cutoff {
			model_write_f32(bytes, value)
		}
		model_write_i32(bytes, cluster.group)
		model_write_i32(bytes, cluster.refined_group)
		model_write_u32(bytes, cluster.page)
		model_write_u32(bytes, cluster.page_index_offset)
	}
	for page in hierarchy.pages {
		model_write_u32(bytes, page.cluster_offset)
		model_write_u32(bytes, page.cluster_count)
		model_write_u32(bytes, page.index_count)
		model_write_u32(bytes, 1 if page.pinned else 0)
	}
	for vertex in hierarchy.vertices {
		model_write_u32(bytes, vertex)
	}
	model_write_bytes(bytes, hierarchy.triangles)
}

model_validate_chunk_magic :: proc(
	file: ^os.File,
	chunk: Asset_Product_Chunk,
	magic: [8]u8,
) -> bool {
	if chunk.stored_size < u64(len(magic)) || chunk.offset > u64(max(i64)) {
		return false
	}
	actual: [8]u8
	expected := magic
	return(
		asset_product_read_exact(file, actual[:], int(chunk.offset)) &&
		string(actual[:]) == string(expected[:]) \
	)
}

model_chunk_contains :: proc(chunk: Asset_Product_Chunk, offset, size: u64) -> bool {
	chunk_end := chunk.offset + chunk.stored_size
	end := offset + size
	return(
		size > 0 &&
		chunk_end >= chunk.offset &&
		end >= offset &&
		offset >= chunk.offset + 8 &&
		end <= chunk_end \
	)
}

read_model_product :: proc(path: string) -> (model: Model_Product, err: string) {
	file, open_err := os.open(path)
	if open_err != nil {
		return {}, fmt.tprintf("failed to open imported model product: %v", open_err)
	}
	defer os.close(file)
	info, stat_err := os.stat(path, context.temp_allocator)
	if stat_err != nil || info.size < 0 || info.size > i64(max(int)) {
		return {}, "failed to inspect imported model product"
	}
	reader := Model_Reader {
		file = file,
	}
	directory, directory_err := read_asset_product_directory(file, int(info.size), .Model)
	if directory_err != "" {
		return {}, directory_err
	}
	defer destroy_asset_product_directory(&directory)
	if len(directory.chunks) != MODEL_PRODUCT_CHUNK_COUNT {
		return {}, "imported model product chunk count is invalid"
	}
	image_chunk, image_found := asset_product_find_chunk(&directory, .Model_Material_Images)
	coarse_chunk, coarse_found := asset_product_find_chunk(&directory, .Model_Coarse_Geometry)
	detail_chunk, detail_found := asset_product_find_chunk(&directory, .Model_Detail_Geometry)
	catalog_chunk, catalog_found := asset_product_find_chunk(&directory, .Model_Catalog)
	if !image_found || !coarse_found || !detail_found || !catalog_found {
		return {}, "imported model product chunks are missing"
	}
	if !model_validate_chunk_magic(file, image_chunk, MODEL_IMAGE_CHUNK_MAGIC) ||
	   !model_validate_chunk_magic(file, coarse_chunk, MODEL_COARSE_CHUNK_MAGIC) ||
	   !model_validate_chunk_magic(file, detail_chunk, MODEL_DETAIL_CHUNK_MAGIC) {
		return {}, "imported model product has an invalid chunk header"
	}
	if catalog_chunk.offset > u64(max(int)) ||
	   catalog_chunk.stored_size > u64(max(int)) ||
	   catalog_chunk.offset + catalog_chunk.stored_size > u64(max(int)) {
		return {}, "imported model catalog chunk is invalid"
	}
	reader.offset = int(catalog_chunk.offset)
	reader.size = int(catalog_chunk.offset + catalog_chunk.stored_size)
	magic: [len(MODEL_CATALOG_MAGIC)]u8
	magic_ok := model_read_exact(&reader, magic[:])
	expected_magic := MODEL_CATALOG_MAGIC
	if !magic_ok || string(magic[:]) != string(expected_magic[:]) {
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
		material.key, ok = model_read_string(&reader)
		if ok {
			material.name, ok = model_read_string(&reader)
		}
		if !ok {
			delete(material.key)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		material.base_color, ok = model_read_vec4(&reader)
		if !ok {
			destroy_model_material(&material)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		material.emissive, ok = model_read_vec3(&reader)
		if !ok {
			destroy_model_material(&material)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		material.metallic_factor, ok = model_read_f32(&reader)
		if ok {
			material.roughness_factor, ok = model_read_f32(&reader)
		}
		if ok {
			material.normal_scale, ok = model_read_f32(&reader)
		}
		if ok {
			material.occlusion_strength, ok = model_read_f32(&reader)
		}
		alpha_mode: u32
		if ok {
			alpha_mode, ok = model_read_u32(&reader)
		}
		if ok && alpha_mode <= u32(shared.Material_Alpha_Mode.Mask) {
			material.alpha_mode = shared.Material_Alpha_Mode(alpha_mode)
		} else {
			ok = false
		}
		if ok {
			material.alpha_cutoff, ok = model_read_f32(&reader)
		}
		double_sided: u32
		if ok {
			double_sided, ok = model_read_u32(&reader)
			ok = ok && double_sided <= 1
			material.double_sided = double_sided == 1
		}
		images := [?]^Model_Image {
			&material.base_color_image,
			&material.metallic_roughness_image,
			&material.normal_image,
			&material.occlusion_image,
			&material.emissive_image,
		}
		for image in images {
			if !ok {
				break
			}
			ok = model_read_image(&reader, image, image_chunk)
		}
		if !ok {
			destroy_model_material(&material)
			destroy_model_product(&model)
			return {}, "imported model material texture is invalid"
		}
		material.ignored_texture_count, ok = model_read_u32(&reader)
		if !ok {
			destroy_model_material(&material)
			destroy_model_product(&model)
			return {}, "imported model material is truncated"
		}
		append(&model.materials, material)
	}
	for _ in 0 ..< mesh_count {
		mesh: Model_Mesh
		mesh.key, ok = model_read_string(&reader)
		if ok {
			mesh.name, ok = model_read_string(&reader)
		}
		if !ok {
			delete(mesh.key)
			destroy_model_product(&model)
			return {}, "imported model mesh is truncated"
		}
		primitive_count: u32
		primitive_count, ok = model_read_u32(&reader)
		if !ok || primitive_count > 65536 {
			delete(mesh.key)
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
			remaining_bytes := u64(reader.size - reader.offset)
			required_bytes := u64(vertex_count) * 12
			if !ok ||
			   vertex_count > 10000000 ||
			   index_count > 30000000 ||
			   required_bytes > remaining_bytes {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model geometry counts are invalid"
			}
			primitive.vertex_count = vertex_count
			primitive.index_count = index_count
			primitive.query_positions = make([]shared.Vec3, int(vertex_count))
			for &position in primitive.query_positions {
				position, ok = model_read_vec3(&reader)
				if !ok {
					destroy_model_primitive(&primitive)
					destroy_model_mesh(&mesh)
					destroy_model_product(&model)
					return {}, "imported model query positions are truncated"
				}
			}
			if ok {
				ok = model_read_hierarchy(&reader, &primitive.hierarchy, int(vertex_count))
			}
			if ok {
				ok = model_read_page_payloads(
					&reader,
					&primitive.hierarchy,
					&primitive.page_payloads,
					coarse_chunk,
					detail_chunk,
				)
			}
			if !ok {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model cluster hierarchy is invalid"
			}
			lod_count: u32
			lod_count, ok = model_read_u32(&reader)
			if !ok || lod_count >= shared.MAX_GEOMETRY_LODS {
				destroy_model_primitive(&primitive)
				destroy_model_mesh(&mesh)
				destroy_model_product(&model)
				return {}, "imported model LOD count is invalid"
			}
			for _ in 0 ..< lod_count {
				lod: Model_Primitive_LOD
				lod.level, ok = model_read_u32(&reader)
				if ok {
					lod.screen_radius, ok = model_read_f32(&reader)
				}
				if ok {
					lod.simplification_error, ok = model_read_f32(&reader)
				}
				lod_vertex_count: u32
				if ok {
					lod_vertex_count, ok = model_read_u32(&reader)
				}
				lod_index_count: u32
				if ok {
					lod_index_count, ok = model_read_u32(&reader)
				}
				remaining_lod_bytes := u64(reader.size - reader.offset)
				required_lod_bytes := u64(lod_vertex_count) * 12
				if !ok ||
				   lod_vertex_count > vertex_count ||
				   lod_index_count >= index_count ||
				   lod_index_count < 3 ||
				   lod_index_count % 3 != 0 ||
				   required_lod_bytes > remaining_lod_bytes {
					destroy_model_lod(&lod)
					destroy_model_primitive(&primitive)
					destroy_model_mesh(&mesh)
					destroy_model_product(&model)
					return {}, "imported model LOD geometry counts are invalid"
				}
				lod.vertex_count = lod_vertex_count
				lod.index_count = lod_index_count
				lod.query_positions = make([]shared.Vec3, int(lod_vertex_count))
				for &position in lod.query_positions {
					position, ok = model_read_vec3(&reader)
					if !ok {
						destroy_model_lod(&lod)
						destroy_model_primitive(&primitive)
						destroy_model_mesh(&mesh)
						destroy_model_product(&model)
						return {}, "imported model LOD query positions are truncated"
					}
				}
				if ok {
					ok = model_read_hierarchy(&reader, &lod.hierarchy, int(lod_vertex_count))
				}
				if ok {
					ok = model_read_page_payloads(
						&reader,
						&lod.hierarchy,
						&lod.page_payloads,
						coarse_chunk,
						detail_chunk,
					)
				}
				if !ok {
					destroy_model_lod(&lod)
					destroy_model_primitive(&primitive)
					destroy_model_mesh(&mesh)
					destroy_model_product(&model)
					return {}, "imported model LOD cluster hierarchy is invalid"
				}
				append(&primitive.lods, lod)
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
		node.key, ok = model_read_string(&reader)
		if ok {
			node.name, ok = model_read_string(&reader)
		}
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
			delete(node.key)
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
	if reader.offset != reader.size {
		destroy_model_product(&model)
		return {}, "imported model product has trailing data"
	}
	return model, ""
}

model_read_page_payloads :: proc(
	reader: ^Model_Reader,
	hierarchy: ^geometry.Hierarchy,
	records: ^[]geometry.Page_Payload_Record,
	coarse_chunk, detail_chunk: Asset_Product_Chunk,
) -> bool {
	if reader == nil || hierarchy == nil || records == nil {
		return false
	}
	page_count, ok := model_read_u32(reader)
	if !ok || int(page_count) != len(hierarchy.pages) {
		return false
	}
	result := make([]geometry.Page_Payload_Record, int(page_count))
	for &record, page_index in result {
		header: [24]u8
		ok = model_read_exact(reader, header[:])
		record.vertex_count = endian.unchecked_get_u32le(header[0:])
		record.index_count = endian.unchecked_get_u32le(header[4:])
		record.offset = endian.unchecked_get_u64le(header[8:])
		record.size = endian.unchecked_get_u64le(header[16:])
		expected_size :=
			u64(record.vertex_count) * u64(size_of(Model_Vertex)) +
			u64(record.index_count) * u64(size_of(u32))
		expected_chunk := detail_chunk
		if hierarchy.pages[page_index].pinned {
			expected_chunk = coarse_chunk
		}
		if !ok ||
		   record.vertex_count == 0 ||
		   record.index_count != hierarchy.pages[page_index].index_count ||
		   record.size != expected_size ||
		   !model_chunk_contains(expected_chunk, record.offset, record.size) {
			delete(result)
			return false
		}
	}
	records^ = result
	return true
}

model_read_hierarchy :: proc(
	reader: ^Model_Reader,
	hierarchy: ^geometry.Hierarchy,
	canonical_vertex_count: int,
) -> bool {
	if reader == nil || hierarchy == nil {
		return false
	}
	ok: bool
	max_depth: u32
	max_depth, ok = model_read_u32(reader)
	if !ok {
		return false
	}
	group_count, group_ok := model_read_u32(reader)
	cluster_count, cluster_ok := model_read_u32(reader)
	page_count, page_ok := model_read_u32(reader)
	vertex_count, vertex_ok := model_read_u32(reader)
	triangle_byte_count, triangle_ok := model_read_u32(reader)
	if !group_ok ||
	   !cluster_ok ||
	   !page_ok ||
	   !vertex_ok ||
	   !triangle_ok ||
	   group_count == 0 ||
	   group_count > 4_000_000 ||
	   cluster_count == 0 ||
	   cluster_count > 16_000_000 ||
	   page_count == 0 ||
	   page_count > cluster_count ||
	   vertex_count == 0 ||
	   vertex_count > 64_000_000 ||
	   triangle_byte_count == 0 ||
	   triangle_byte_count > 256_000_000 {
		return false
	}
	required_bytes :=
		u64(group_count) * 40 +
		u64(cluster_count) * 64 +
		u64(page_count) * 16 +
		u64(vertex_count) * 4 +
		u64(triangle_byte_count)
	if required_bytes > u64(reader.size - reader.offset) {
		return false
	}
	hierarchy.max_depth = max_depth
	hierarchy.groups = make([]geometry.Cluster_Group, int(group_count))
	hierarchy.clusters = make([]geometry.Cluster, int(cluster_count))
	hierarchy.pages = make([]geometry.Cluster_Page, int(page_count))
	hierarchy.vertices = make([]u32, int(vertex_count))
	for &group in hierarchy.groups {
		for &value in group.bounds {
			value, ok = model_read_f32(reader)
			if !ok {
				geometry.destroy_hierarchy(hierarchy)
				return false
			}
		}
		group.error, ok = model_read_f32(reader)
		if ok {
			group.depth, ok = model_read_u32(reader)
		}
		if ok {
			group.cluster_offset, ok = model_read_u32(reader)
		}
		if ok {
			group.cluster_count, ok = model_read_u32(reader)
		}
		if ok {
			group.page_offset, ok = model_read_u32(reader)
		}
		if ok {
			group.page_count, ok = model_read_u32(reader)
		}
		if !ok {
			geometry.destroy_hierarchy(hierarchy)
			return false
		}
	}
	for &cluster in hierarchy.clusters {
		cluster.vertex_offset, ok = model_read_u32(reader)
		if ok {
			cluster.triangle_offset, ok = model_read_u32(reader)
		}
		if ok {
			cluster.vertex_count, ok = model_read_u32(reader)
		}
		if ok {
			cluster.triangle_count, ok = model_read_u32(reader)
		}
		for &value in cluster.bounds {
			if !ok {
				break
			}
			value, ok = model_read_f32(reader)
		}
		for &value in cluster.cone_axis_cutoff {
			if !ok {
				break
			}
			value, ok = model_read_f32(reader)
		}
		if ok {
			cluster.group, ok = model_read_i32(reader)
		}
		if ok {
			cluster.refined_group, ok = model_read_i32(reader)
		}
		if ok {
			cluster.page, ok = model_read_u32(reader)
		}
		if ok {
			cluster.page_index_offset, ok = model_read_u32(reader)
		}
		if !ok {
			geometry.destroy_hierarchy(hierarchy)
			return false
		}
	}
	for &page in hierarchy.pages {
		page.cluster_offset, ok = model_read_u32(reader)
		if ok {
			page.cluster_count, ok = model_read_u32(reader)
		}
		if ok {
			page.index_count, ok = model_read_u32(reader)
		}
		pinned: u32
		if ok {
			pinned, ok = model_read_u32(reader)
		}
		if !ok || pinned > 1 {
			geometry.destroy_hierarchy(hierarchy)
			return false
		}
		page.pinned = pinned == 1
	}
	for &vertex in hierarchy.vertices {
		vertex, ok = model_read_u32(reader)
		if !ok {
			geometry.destroy_hierarchy(hierarchy)
			return false
		}
	}
	hierarchy.triangles = make([]u8, int(triangle_byte_count))
	if !model_read_exact(reader, hierarchy.triangles) {
		geometry.destroy_hierarchy(hierarchy)
		return false
	}
	return geometry.validate_hierarchy(hierarchy, canonical_vertex_count) == ""
}

validate_decoded_model :: proc(model: ^Model_Product) -> string {
	for material in model.materials {
		if material.key == "" {
			return "imported model material semantic key is empty"
		}
		if math.is_nan(material.alpha_cutoff) ||
		   math.is_inf(material.alpha_cutoff) ||
		   material.alpha_cutoff < 0 ||
		   material.alpha_cutoff > 1 {
			return "imported model material alpha cutoff is invalid"
		}
	}
	for mesh in model.meshes {
		if mesh.key == "" {
			return "imported model mesh semantic key is empty"
		}
		for primitive in mesh.primitives {
			if primitive.key == "" {
				return "imported model primitive semantic key is empty"
			}
			previous_radius := f32(3.402823e38)
			previous_index_count := int(primitive.index_count)
			previous_level := -1
			for lod in primitive.lods {
				if lod.level >= shared.MAX_GEOMETRY_LODS - 1 ||
				   int(lod.level) <= previous_level ||
				   math.is_nan(lod.screen_radius) ||
				   math.is_inf(lod.screen_radius) ||
				   lod.screen_radius <= 0 ||
				   lod.screen_radius >= previous_radius ||
				   math.is_nan(lod.simplification_error) ||
				   math.is_inf(lod.simplification_error) ||
				   lod.simplification_error < 0 ||
				   int(lod.index_count) >= previous_index_count {
					return "imported model LOD metadata is invalid"
				}
				previous_radius = lod.screen_radius
				previous_index_count = int(lod.index_count)
				previous_level = int(lod.level)
			}
		}
	}
	node_keys := make(map[string]bool)
	defer delete(node_keys)
	for node, node_index in model.nodes {
		if node.key == "" || node_keys[node.key] {
			return "imported model node semantic key is empty or duplicated"
		}
		node_keys[node.key] = true
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
	file: ^os.File,
	size: int,
	offset: int,
	buffer: [MODEL_READER_BUFFER_SIZE]u8,
	buffer_offset: int,
	buffer_count: int,
	read_operations: int,
}

model_write_u32 :: proc(bytes: ^[dynamic]u8, value: u32) {
	offset := len(bytes^)
	resize(bytes, offset + 4)
	endian.unchecked_put_u32le(bytes^[offset:], value)
}

model_write_u64 :: proc(bytes: ^[dynamic]u8, value: u64) {
	offset := len(bytes^)
	resize(bytes, offset + 8)
	endian.unchecked_put_u64le(bytes^[offset:], value)
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

model_write_image_descriptor :: proc(bytes: ^[dynamic]u8, image: Model_Image) {
	model_write_u32(bytes, image.width)
	model_write_u32(bytes, image.height)
	model_write_u32(bytes, image.mip_count)
	model_write_u32(bytes, u32(image.sampler.mag_filter))
	model_write_u32(bytes, u32(image.sampler.min_filter))
	model_write_u32(bytes, u32(image.sampler.mipmap_filter))
	model_write_u32(bytes, u32(image.sampler.address_u))
	model_write_u32(bytes, u32(image.sampler.address_v))
	model_write_u64(bytes, image.product_offset)
	model_write_u64(bytes, image.product_size)
}

model_read_bytes :: proc(reader: ^Model_Reader, count: int) -> ([]u8, bool) {
	if reader == nil || reader.file == nil || count < 0 || reader.offset + count > reader.size {
		return nil, false
	}
	result := make([]u8, count, context.temp_allocator)
	read_count, read_err := os.read_at(reader.file, result, i64(reader.offset))
	if read_err != nil || read_count != count {
		return nil, false
	}
	reader.offset += count
	return result, true
}

model_read_exact :: proc(reader: ^Model_Reader, destination: []u8) -> bool {
	if reader == nil || reader.file == nil || reader.offset + len(destination) > reader.size {
		return false
	}
	if len(destination) > len(reader.buffer) {
		return model_read_exact_direct(reader, destination)
	}
	written := 0
	for written < len(destination) {
		if reader.offset < reader.buffer_offset ||
		   reader.offset >= reader.buffer_offset + reader.buffer_count {
			reader.buffer_offset = reader.offset
			reader.buffer_count = min(len(reader.buffer), reader.size - reader.offset)
			read_count, read_err := os.read_at(
				reader.file,
				reader.buffer[:reader.buffer_count],
				i64(reader.buffer_offset),
			)
			reader.read_operations += 1
			if read_err != nil || read_count != reader.buffer_count {
				reader.buffer_count = 0
				return false
			}
		}
		buffer_index := reader.offset - reader.buffer_offset
		available := reader.buffer_count - buffer_index
		copy_count := min(available, len(destination) - written)
		copy(
			destination[written:written + copy_count],
			reader.buffer[buffer_index:buffer_index + copy_count],
		)
		reader.offset += copy_count
		written += copy_count
	}
	return true
}

model_read_exact_direct :: proc(reader: ^Model_Reader, destination: []u8) -> bool {
	if reader == nil || reader.file == nil || reader.offset + len(destination) > reader.size {
		return false
	}
	read_count, read_err := os.read_at(reader.file, destination, i64(reader.offset))
	reader.read_operations += 1
	if read_err != nil || read_count != len(destination) {
		return false
	}
	reader.offset += len(destination)
	return true
}

model_skip_bytes :: proc(reader: ^Model_Reader, count: int) -> bool {
	if reader == nil || count < 0 || reader.offset + count > reader.size {
		return false
	}
	reader.offset += count
	return true
}

model_read_u32 :: proc(reader: ^Model_Reader) -> (u32, bool) {
	if reader == nil || reader.file == nil || reader.offset + 4 > reader.size {
		return 0, false
	}
	bytes: [4]u8
	if !model_read_exact(reader, bytes[:]) {
		return 0, false
	}
	return endian.unchecked_get_u32le(bytes[:]), true
}

model_read_u64 :: proc(reader: ^Model_Reader) -> (u64, bool) {
	if reader == nil || reader.file == nil || reader.offset + 8 > reader.size {
		return 0, false
	}
	bytes: [8]u8
	if !model_read_exact(reader, bytes[:]) {
		return 0, false
	}
	return endian.unchecked_get_u64le(bytes[:]), true
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

model_read_image :: proc(
	reader: ^Model_Reader,
	image: ^Model_Image,
	image_chunk: Asset_Product_Chunk,
) -> bool {
	if image == nil {
		return false
	}
	width, width_ok := model_read_u32(reader)
	if !width_ok {
		return false
	}
	height, height_ok := model_read_u32(reader)
	if !height_ok {
		return false
	}
	mip_count, mip_count_ok := model_read_u32(reader)
	if !mip_count_ok {
		return false
	}
	mag_filter, mag_ok := model_read_u32(reader)
	min_filter, min_ok := model_read_u32(reader)
	mipmap_filter, mipmap_ok := model_read_u32(reader)
	address_u, address_u_ok := model_read_u32(reader)
	address_v, address_v_ok := model_read_u32(reader)
	if !mag_ok ||
	   !min_ok ||
	   !mipmap_ok ||
	   !address_u_ok ||
	   !address_v_ok ||
	   mag_filter > u32(shared.Texture_Filter.Linear) ||
	   min_filter > u32(shared.Texture_Filter.Linear) ||
	   mipmap_filter > u32(shared.Texture_Mipmap_Filter.Linear) ||
	   address_u > u32(shared.Texture_Address_Mode.Repeat) ||
	   address_v > u32(shared.Texture_Address_Mode.Repeat) {
		return false
	}
	product_offset, offset_ok := model_read_u64(reader)
	product_size, size_ok := model_read_u64(reader)
	if !offset_ok || !size_ok || product_size > 16384 * 16384 * 4 {
		return false
	}
	if product_size == 0 {
		return product_offset == 0 && width == 0 && height == 0 && mip_count == 0
	}
	if width == 0 ||
	   height == 0 ||
	   width > 16384 ||
	   height > 16384 ||
	   mip_count == 0 ||
	   mip_count > 15 {
		return false
	}
	expected: u64
	mip_width, mip_height := width, height
	for _ in 0 ..< mip_count {
		expected += u64(mip_width) * u64(mip_height) * 4
		mip_width = max(mip_width / 2, 1)
		mip_height = max(mip_height / 2, 1)
	}
	if expected != product_size ||
	   !model_chunk_contains(image_chunk, product_offset, product_size) {
		return false
	}
	image.pixels = make([]u8, int(product_size))
	read_count, read_err := os.read_at(reader.file, image.pixels, i64(product_offset))
	if read_err != nil || read_count != len(image.pixels) {
		delete(image.pixels)
		image.pixels = nil
		return false
	}
	image.width = width
	image.height = height
	image.mip_count = mip_count
	image.product_offset = product_offset
	image.product_size = product_size
	image.sampler = {
		mag_filter = shared.Texture_Filter(mag_filter),
		min_filter = shared.Texture_Filter(min_filter),
		mipmap_filter = shared.Texture_Mipmap_Filter(mipmap_filter),
		address_u = shared.Texture_Address_Mode(address_u),
		address_v = shared.Texture_Address_Mode(address_v),
	}
	return true
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
