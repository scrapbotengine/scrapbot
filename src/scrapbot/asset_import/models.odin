package asset_import

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

MODEL_IMPORTER_SCHEMA :: "scrapbot.model.v6.semantic-scene"
MODEL_PRODUCT_MAGIC :: [8]u8{'S', 'B', 'M', 'O', 'D', 'E', 'L', '6'}

Model_Vertex :: struct {
	position, normal: shared.Vec3,
	uv: shared.Vec2,
}

Model_Image :: struct {
	pixels: []u8,
	width, height, mip_count: u32,
	sampler: shared.Texture_Sampler,
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
			delete(primitive.key)
			delete(primitive.vertices)
			delete(primitive.indices)
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
	source_hash, hash_err := model_import_hash(source, data, source_path)
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
		model, model_err := build_model_product(data, source_path)
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

model_import_hash :: proc(source: []u8, data: ^cgltf.data, source_path: string) -> (u64, string) {
	value := hash.fnv64a(source)
	value = hash.fnv64a(transmute([]byte)(string(MODEL_IMPORTER_SCHEMA)), value)
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

encode_model_product :: proc(model: ^Model_Product) -> []u8 {
	bytes: [dynamic]u8
	magic := MODEL_PRODUCT_MAGIC
	model_write_bytes(&bytes, magic[:])
	model_write_u32(&bytes, u32(len(model.materials)))
	model_write_u32(&bytes, u32(len(model.meshes)))
	model_write_u32(&bytes, u32(len(model.nodes)))
	for material in model.materials {
		model_write_string(&bytes, material.key)
		model_write_string(&bytes, material.name)
		model_write_vec4(&bytes, material.base_color)
		model_write_vec3(&bytes, material.emissive)
		model_write_f32(&bytes, material.metallic_factor)
		model_write_f32(&bytes, material.roughness_factor)
		model_write_f32(&bytes, material.normal_scale)
		model_write_f32(&bytes, material.occlusion_strength)
		model_write_u32(&bytes, u32(material.alpha_mode))
		model_write_f32(&bytes, material.alpha_cutoff)
		model_write_u32(&bytes, 1 if material.double_sided else 0)
		model_write_image(&bytes, material.base_color_image)
		model_write_image(&bytes, material.metallic_roughness_image)
		model_write_image(&bytes, material.normal_image)
		model_write_image(&bytes, material.occlusion_image)
		model_write_image(&bytes, material.emissive_image)
		model_write_u32(&bytes, material.ignored_texture_count)
	}
	for mesh in model.meshes {
		model_write_string(&bytes, mesh.key)
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
		model_write_string(&bytes, node.key)
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
			ok = model_read_image(&reader, image)
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
	if reader.offset != len(reader.bytes) {
		destroy_model_product(&model)
		return {}, "imported model product has trailing data"
	}
	return model, ""
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

model_write_image :: proc(bytes: ^[dynamic]u8, image: Model_Image) {
	model_write_u32(bytes, image.width)
	model_write_u32(bytes, image.height)
	model_write_u32(bytes, image.mip_count)
	model_write_u32(bytes, u32(image.sampler.mag_filter))
	model_write_u32(bytes, u32(image.sampler.min_filter))
	model_write_u32(bytes, u32(image.sampler.mipmap_filter))
	model_write_u32(bytes, u32(image.sampler.address_u))
	model_write_u32(bytes, u32(image.sampler.address_v))
	model_write_u32(bytes, u32(len(image.pixels)))
	model_write_bytes(bytes, image.pixels)
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

model_read_image :: proc(reader: ^Model_Reader, image: ^Model_Image) -> bool {
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
	pixel_count, pixel_count_ok := model_read_u32(reader)
	if !pixel_count_ok || pixel_count > 16384 * 16384 * 4 {
		return false
	}
	texture_bytes, bytes_ok := model_read_bytes(reader, int(pixel_count))
	if !bytes_ok {
		return false
	}
	if pixel_count == 0 {
		return width == 0 && height == 0 && mip_count == 0
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
	if expected != u64(pixel_count) {
		return false
	}
	image.pixels = make([]u8, int(pixel_count))
	copy(image.pixels, texture_bytes)
	image.width = width
	image.height = height
	image.mip_count = mip_count
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
