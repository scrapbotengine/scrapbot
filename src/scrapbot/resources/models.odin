package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:fmt"
import "core:mem"
import "core:strings"

Model_Primitive :: struct {
	key: string,
	geometry: Geometry_Handle,
	material: Material_Handle,
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

Model :: struct {
	id: shared.Resource_UUID,
	name: string,
	source: string,
	asset_source: string,
	import_byte_count: int,
	authored: bool,
	meshes: [dynamic]Model_Mesh,
	nodes: [dynamic]Model_Node,
	material_handles: [dynamic]Material_Handle,
	ignored_texture_count: int,
	generation: u32,
	version: u32,
	alive: bool,
}

register_project_models :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
	products: []asset_import.Product,
	retire_missing: bool = true,
) -> string {
	if registry == nil {
		return "model registry is not available"
	}
	seen := make(map[shared.Resource_UUID]bool)
	defer delete(seen)
	for declaration in declarations {
		if declaration.kind != .Model {
			continue
		}
		product, found := model_product_by_id(products, declaration.id)
		if !found {
			return fmt.tprintf(
				"resources/%s: imported model product is missing",
				declaration.source,
			)
		}
		imported, read_err := asset_import.read_model_product(product.artifact_path)
		if read_err != "" {
			return fmt.tprintf("resources/%s: %s", declaration.source, read_err)
		}
		if _, register_err := register_project_model(
			registry,
			declaration,
			&imported,
			product.byte_count,
		); register_err != "" {
			asset_import.destroy_model_product(&imported)
			return fmt.tprintf("resources/%s: %s", declaration.source, register_err)
		}
		asset_import.destroy_model_product(&imported)
		seen[declaration.id] = true
	}
	if !retire_missing {
		return ""
	}
	for &model in registry.models {
		if model.authored && model.alive && !seen[model.id] {
			retire_model_products(registry, &model)
			model.alive = false
			model.generation += 1
			model.version += 1
			bump_model_revision(registry)
		}
	}
	return ""
}

register_project_model :: proc(
	registry: ^Registry,
	declaration: shared.Project_Resource,
	imported: ^asset_import.Model_Product,
	import_byte_count: int = 0,
) -> (
	Model_Handle,
	string,
) {
	if declaration.id == (shared.Resource_UUID{}) ||
	   declaration.name == "" ||
	   declaration.source == "" ||
	   declaration.model.source == "" {
		return {}, "project model metadata must not be empty"
	}
	ensure_allocator(registry)
	model := Model {
		id = declaration.id,
		authored = true,
		generation = 1,
		version = 1,
		alive = true,
	}
	model.meshes = make([dynamic]Model_Mesh, registry.allocator)
	model.nodes = make([dynamic]Model_Node, registry.allocator)
	model.material_handles = make([dynamic]Material_Handle, registry.allocator)
	model.name, _ = strings.clone(declaration.name, registry.allocator)
	model.source, _ = strings.clone(declaration.source, registry.allocator)
	model.asset_source, _ = strings.clone(declaration.model.source, registry.allocator)
	model.import_byte_count = import_byte_count
	for material in imported.materials {
		model.ignored_texture_count += int(material.ignored_texture_count)
	}
	if model.name == "" || model.source == "" || model.asset_source == "" {
		destroy_model(&model, registry.allocator)
		return {}, "failed to allocate project model metadata"
	}
	id_buffer: [36]u8
	id_text := shared.resource_uuid_to_string(declaration.id, id_buffer[:])
	for material, material_index in imported.materials {
		resource_name := fmt.tprintf("__model_%s_material_%d", id_text, material_index)
		handle, material_err := register_material(
			registry,
			resource_name,
			{
				base_color = Vec4(material.base_color),
				emissive = material.emissive,
				metallic_factor = material.metallic_factor,
				roughness_factor = material.roughness_factor,
				normal_scale = material.normal_scale,
				occlusion_strength = material.occlusion_strength,
				alpha_mode = material.alpha_mode,
				alpha_cutoff = material.alpha_cutoff,
				double_sided = material.double_sided,
				pbr = true,
				texture_pixels = material.base_color_image.pixels,
				texture_width = material.base_color_image.width,
				texture_height = material.base_color_image.height,
				texture_mip_count = material.base_color_image.mip_count,
				metallic_roughness_image = model_material_image(
					material.metallic_roughness_image,
					.Linear,
				),
				normal_image = model_material_image(material.normal_image, .Linear),
				occlusion_image = model_material_image(material.occlusion_image, .Linear),
				emissive_image = model_material_image(material.emissive_image, .SRGB),
			},
		)
		if material_err != "" {
			destroy_model(&model, registry.allocator)
			return {}, material_err
		}
		append(&model.material_handles, handle)
	}
	for mesh, mesh_index in imported.meshes {
		model_mesh := Model_Mesh{}
		model_mesh.primitives = make([dynamic]Model_Primitive, registry.allocator)
		model_mesh.name, _ = strings.clone(mesh.name, registry.allocator)
		if model_mesh.name == "" {
			destroy_model(&model, registry.allocator)
			return {}, "failed to allocate imported model mesh name"
		}
		for primitive, primitive_index in mesh.primitives {
			vertices := make([]Vertex, len(primitive.vertices))
			for vertex, vertex_index in primitive.vertices {
				vertices[vertex_index] = {
					position = vertex.position,
					normal = vertex.normal,
					uv = {vertex.uv.x, vertex.uv.y},
				}
			}
			geometry_name := fmt.tprintf(
				"__model_%s_mesh_%d_primitive_%d",
				id_text,
				mesh_index,
				primitive_index,
			)
			geometry, geometry_err := register_geometry(
				registry,
				geometry_name,
				{vertices = vertices, indices = primitive.indices[:]},
			)
			delete(vertices)
			if geometry_err != "" {
				destroy_model(&model, registry.allocator)
				return {}, geometry_err
			}
			model_primitive := Model_Primitive {
				geometry = geometry,
			}
			model_primitive.key, _ = strings.clone(primitive.key, registry.allocator)
			if primitive.material_index >= 0 &&
			   int(primitive.material_index) < len(model.material_handles) {
				model_primitive.material = model.material_handles[primitive.material_index]
			}
			append(&model_mesh.primitives, model_primitive)
		}
		append(&model.meshes, model_mesh)
	}
	for node in imported.nodes {
		model_node := Model_Node {
			parent_index = node.parent_index,
			mesh_index = node.mesh_index,
			transform = node.transform,
		}
		model_node.name, _ = strings.clone(node.name, registry.allocator)
		if model_node.name == "" {
			destroy_model(&model, registry.allocator)
			return {}, "failed to allocate imported model node name"
		}
		append(&model.nodes, model_node)
	}
	if index, found := model_index_by_uuid_any(registry, declaration.id); found {
		current := &registry.models[index]
		retire_replaced_model_products(registry, current, &model)
		model.generation = current.generation
		model.version = current.version + 1
		destroy_model(current, registry.allocator)
		current^ = model
		bump_model_revision(registry)
		return {u32(index), current.generation}, ""
	}
	for current in registry.models {
		if current.alive && current.name == declaration.name {
			destroy_model(&model, registry.allocator)
			return {}, fmt.tprintf("model name '%s' is already registered", declaration.name)
		}
	}
	append(&registry.models, model)
	bump_model_revision(registry)
	return {u32(len(registry.models) - 1), 1}, ""
}

model_material_image :: proc(
	image: asset_import.Model_Image,
	color_space: shared.Texture_Color_Space,
) -> Material_Image {
	return {
		pixels = image.pixels,
		width = image.width,
		height = image.height,
		mip_count = image.mip_count,
		color_space = color_space,
	}
}

retire_model_products :: proc(registry: ^Registry, model: ^Model) {
	if registry == nil || model == nil {
		return
	}
	for mesh in model.meshes {
		for primitive in mesh.primitives {
			retire_generated_geometry(registry, primitive.geometry)
		}
	}
	for handle in model.material_handles {
		retire_generated_material(registry, handle)
	}
}

retire_replaced_model_products :: proc(registry: ^Registry, old, replacement: ^Model) {
	if registry == nil || old == nil || replacement == nil {
		return
	}
	for mesh in old.meshes {
		for primitive in mesh.primitives {
			if !model_contains_geometry(replacement, primitive.geometry) {
				retire_generated_geometry(registry, primitive.geometry)
			}
		}
	}
	for handle in old.material_handles {
		if !model_contains_material(replacement, handle) {
			retire_generated_material(registry, handle)
		}
	}
}

model_contains_geometry :: proc(model: ^Model, handle: Geometry_Handle) -> bool {
	if model == nil {
		return false
	}
	for mesh in model.meshes {
		for primitive in mesh.primitives {
			if primitive.geometry == handle {
				return true
			}
		}
	}
	return false
}

model_contains_material :: proc(model: ^Model, handle: Material_Handle) -> bool {
	if model == nil {
		return false
	}
	for current in model.material_handles {
		if current == handle {
			return true
		}
	}
	return false
}

retire_generated_geometry :: proc(registry: ^Registry, handle: Geometry_Handle) {
	geometry, alive := get_geometry(registry, handle)
	if !alive || geometry.authored {
		return
	}
	geometry.alive = false
	geometry.generation += 1
	geometry.version += 1
	registry.geometry_topology_revision += 1
}

retire_generated_material :: proc(registry: ^Registry, handle: Material_Handle) {
	material, alive := get_material(registry, handle)
	if !alive || material.authored {
		return
	}
	material.alive = false
	material.generation += 1
	material.version += 1
	bump_material_revision(registry)
}

get_model :: proc(registry: ^Registry, handle: Model_Handle) -> (^Model, bool) {
	if registry == nil || int(handle.index) >= len(registry.models) {
		return nil, false
	}
	model := &registry.models[handle.index]
	return model, model.alive && model.generation == handle.generation
}

model_handle_by_uuid :: proc(
	registry: ^Registry,
	id: shared.Resource_UUID,
) -> (
	Model_Handle,
	bool,
) {
	if index, found := model_index_by_uuid(registry, id); found {
		model := registry.models[index]
		return {u32(index), model.generation}, true
	}
	return {}, false
}

model_product_by_id :: proc(
	products: []asset_import.Product,
	id: shared.Resource_UUID,
) -> (
	asset_import.Product,
	bool,
) {
	for product in products {
		if product.kind == .Model && product.id == id {
			return product, true
		}
	}
	return {}, false
}

model_index_by_uuid :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for model, index in registry.models {
		if model.alive && model.authored && model.id == id {
			return index, true
		}
	}
	return -1, false
}

model_index_by_uuid_any :: proc(registry: ^Registry, id: shared.Resource_UUID) -> (int, bool) {
	if registry == nil || id == (shared.Resource_UUID{}) {
		return -1, false
	}
	for model, index in registry.models {
		if model.authored && model.id == id {
			return index, true
		}
	}
	return -1, false
}

destroy_model :: proc(model: ^Model, allocator: mem.Allocator) {
	delete(model.name, allocator)
	delete(model.source, allocator)
	delete(model.asset_source, allocator)
	for &mesh in model.meshes {
		delete(mesh.name, allocator)
		for &primitive in mesh.primitives {
			delete(primitive.key, allocator)
		}
		delete(mesh.primitives)
	}
	for &node in model.nodes {
		delete(node.name, allocator)
	}
	delete(model.meshes)
	delete(model.nodes)
	delete(model.material_handles)
	model^ = {}
}

clone_model :: proc(source: Model, allocator: mem.Allocator) -> (model: Model, err: string) {
	model = source
	model.name, _ = strings.clone(source.name, allocator)
	model.source, _ = strings.clone(source.source, allocator)
	model.asset_source, _ = strings.clone(source.asset_source, allocator)
	model.meshes = nil
	model.nodes = nil
	model.meshes = make([dynamic]Model_Mesh, allocator)
	model.nodes = make([dynamic]Model_Node, allocator)
	model.material_handles = make([dynamic]Material_Handle, allocator)
	resize(&model.material_handles, len(source.material_handles))
	copy(model.material_handles[:], source.material_handles[:])
	for mesh in source.meshes {
		cloned_mesh := Model_Mesh{}
		cloned_mesh.primitives = make([dynamic]Model_Primitive, allocator)
		cloned_mesh.name, _ = strings.clone(mesh.name, allocator)
		for primitive in mesh.primitives {
			cloned_primitive := primitive
			cloned_primitive.key, _ = strings.clone(primitive.key, allocator)
			append(&cloned_mesh.primitives, cloned_primitive)
		}
		append(&model.meshes, cloned_mesh)
	}
	for node in source.nodes {
		cloned_node := node
		cloned_node.name, _ = strings.clone(node.name, allocator)
		append(&model.nodes, cloned_node)
	}
	if model.name == "" || model.source == "" || model.asset_source == "" {
		destroy_model(&model, allocator)
		return {}, "failed to clone model registry entry"
	}
	return model, ""
}

bump_model_revision :: proc(registry: ^Registry) {
	registry.model_revision += 1
	if registry.model_revision == 0 {
		registry.model_revision = 1
	}
}
