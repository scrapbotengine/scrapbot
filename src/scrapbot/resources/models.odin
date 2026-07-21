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
	authored: bool,
	meshes: [dynamic]Model_Mesh,
	nodes: [dynamic]Model_Node,
	material_handles: [dynamic]Material_Handle,
	generation: u32,
	version: u32,
	alive: bool,
}

register_project_models :: proc(
	registry: ^Registry,
	declarations: []shared.Project_Resource,
	products: []asset_import.Product,
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
		if _, register_err := register_project_model(registry, declaration, &imported);
		   register_err != "" {
			asset_import.destroy_model_product(&imported)
			return fmt.tprintf("resources/%s: %s", declaration.source, register_err)
		}
		asset_import.destroy_model_product(&imported)
		seen[declaration.id] = true
	}
	for &model in registry.models {
		if model.authored && !seen[model.id] {
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
			{base_color = Vec4(material.base_color), emissive = material.emissive},
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
