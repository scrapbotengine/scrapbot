package resources

import "core:math"
import "core:mem"
import "core:strings"
import shared "../shared"

Vec3 :: shared.Vec3

Vec2 :: struct {x, y: f32}
Vec4 :: struct {x, y, z, w: f32}

Geometry_Handle :: shared.Geometry_Handle
Material_Handle :: shared.Material_Handle

Vertex :: struct {
	position: Vec3,
	normal:   Vec3,
	uv:       Vec2,
}

Bounds :: struct {min, max: Vec3}

Geometry_Desc :: struct {
	vertices: []Vertex,
	indices:  []u32,
}

Material_Desc :: struct {
	base_color: Vec4,
}

Geometry :: struct {
	name:       string,
	vertices:   []Vertex,
	indices:    []u32,
	bounds:     Bounds,
	generation: u32,
	version:    u32,
	alive:      bool,
}

Material :: struct {
	name:       string,
	desc:       Material_Desc,
	generation: u32,
	version:    u32,
	alive:      bool,
}

Registry :: struct {
	geometries: [dynamic]Geometry,
	materials:  [dynamic]Material,
	allocator: mem.Allocator,
}

ensure_allocator :: proc(registry: ^Registry) {
	if registry.allocator.procedure == nil {registry.allocator = context.allocator}
	if registry.geometries == nil {registry.geometries = make([dynamic]Geometry, registry.allocator)}
	if registry.materials == nil {registry.materials = make([dynamic]Material, registry.allocator)}
}
init_registry :: proc(registry: ^Registry, allocator := context.allocator) {registry^ = {}; registry.allocator = allocator; ensure_allocator(registry)}

destroy_registry :: proc(registry: ^Registry) {
	if registry == nil {return}
	allocator := registry.allocator; if allocator.procedure == nil {allocator = context.allocator}
	for &geometry in registry.geometries {
		delete(geometry.name, allocator)
		delete(geometry.vertices, allocator)
		delete(geometry.indices, allocator)
	}
	for &material in registry.materials {delete(material.name, allocator)}
	delete(registry.geometries)
	delete(registry.materials)
	registry^ = {}
}

register_geometry :: proc(registry: ^Registry, name: string, desc: Geometry_Desc) -> (Geometry_Handle, string) {
	if registry == nil {return {}, "geometry registry is not available"}
	ensure_allocator(registry)
	if err := validate_geometry(desc); err != "" {return {}, err}
	if index, found := geometry_index_by_name(registry, name); found {
		geometry := &registry.geometries[index]
		delete(geometry.vertices, registry.allocator)
		delete(geometry.indices, registry.allocator)
		geometry.vertices = clone_slice(desc.vertices, registry.allocator)
		geometry.indices = clone_slice(desc.indices, registry.allocator)
		geometry.bounds = calculate_bounds(desc.vertices)
		geometry.version += 1
		return {u32(index), geometry.generation}, ""
	}
	cloned_name, clone_err := strings.clone(name, registry.allocator)
	if clone_err != nil {return {}, "failed to allocate geometry name"}
	append(&registry.geometries, Geometry {
		name = cloned_name,
		vertices = clone_slice(desc.vertices, registry.allocator),
		indices = clone_slice(desc.indices, registry.allocator),
		bounds = calculate_bounds(desc.vertices),
		generation = 1,
		version = 1,
		alive = true,
	})
	return {u32(len(registry.geometries) - 1), 1}, ""
}

register_material :: proc(registry: ^Registry, name: string, desc: Material_Desc) -> (Material_Handle, string) {
	if registry == nil {return {}, "material registry is not available"}
	ensure_allocator(registry)
	if name == "" {return {}, "material name must not be empty"}
	if !finite4(desc.base_color) {return {}, "material base color must be finite"}
	if index, found := material_index_by_name(registry, name); found {
		material := &registry.materials[index]
		material.desc = desc
		material.version += 1
		return {u32(index), material.generation}, ""
	}
	cloned_name, clone_err := strings.clone(name, registry.allocator)
	if clone_err != nil {return {}, "failed to allocate material name"}
	append(&registry.materials, Material{name = cloned_name, desc = desc, generation = 1, version = 1, alive = true})
	return {u32(len(registry.materials) - 1), 1}, ""
}

get_geometry :: proc(registry: ^Registry, handle: Geometry_Handle) -> (^Geometry, bool) {
	if registry == nil || int(handle.index) >= len(registry.geometries) {return nil, false}
	geometry := &registry.geometries[handle.index]
	return geometry, geometry.alive && geometry.generation == handle.generation
}

get_material :: proc(registry: ^Registry, handle: Material_Handle) -> (^Material, bool) {
	if registry == nil || int(handle.index) >= len(registry.materials) {return nil, false}
	material := &registry.materials[handle.index]
	return material, material.alive && material.generation == handle.generation
}

geometry_by_name :: proc(registry: ^Registry, name: string) -> (Geometry_Handle, bool) {
	index, found := geometry_index_by_name(registry, name)
	if !found {return {}, false}
	return {u32(index), registry.geometries[index].generation}, true
}

material_by_name :: proc(registry: ^Registry, name: string) -> (Material_Handle, bool) {
	index, found := material_index_by_name(registry, name)
	if !found {return {}, false}
	return {u32(index), registry.materials[index].generation}, true
}

geometry_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	for geometry, index in registry.geometries {if geometry.alive && geometry.name == name {return index, true}}
	return -1, false
}

material_index_by_name :: proc(registry: ^Registry, name: string) -> (int, bool) {
	for material, index in registry.materials {if material.alive && material.name == name {return index, true}}
	return -1, false
}

validate_geometry :: proc(desc: Geometry_Desc) -> string {
	if len(desc.vertices) == 0 {return "geometry must contain vertices"}
	if len(desc.indices) == 0 || len(desc.indices) % 3 != 0 {return "geometry indices must contain triangle lists"}
	for vertex in desc.vertices {
		if !finite3(vertex.position) || !finite3(vertex.normal) || !finite2(vertex.uv) {return "geometry vertex values must be finite"}
	}
	for index in desc.indices {if int(index) >= len(desc.vertices) {return "geometry index is outside the vertex array"}}
	return ""
}

calculate_bounds :: proc(vertices: []Vertex) -> Bounds {
	bounds := Bounds{min = vertices[0].position, max = vertices[0].position}
	for vertex in vertices[1:] {
		bounds.min.x = min(bounds.min.x, vertex.position.x); bounds.min.y = min(bounds.min.y, vertex.position.y); bounds.min.z = min(bounds.min.z, vertex.position.z)
		bounds.max.x = max(bounds.max.x, vertex.position.x); bounds.max.y = max(bounds.max.y, vertex.position.y); bounds.max.z = max(bounds.max.z, vertex.position.z)
	}
	return bounds
}

finite :: proc(v: f32) -> bool {return !math.is_nan(v) && !math.is_inf(v)}
finite2 :: proc(v: Vec2) -> bool {return finite(v.x) && finite(v.y)}
finite3 :: proc(v: Vec3) -> bool {return finite(v.x) && finite(v.y) && finite(v.z)}
finite4 :: proc(v: Vec4) -> bool {return finite(v.x) && finite(v.y) && finite(v.z) && finite(v.w)}

clone_slice :: proc(values: []$T, allocator := context.allocator) -> []T {
	result := make([]T, len(values), allocator); copy(result, values); return result
}

cube :: proc(size: f32 = 1) -> (Geometry_Desc, string) {
	if !finite(size) || size <= 0 {return {}, "cube size must be positive and finite"}
	h := size / 2
	vertices := make([]Vertex, 24)
	positions := [8]Vec3{{-h,-h,-h},{h,-h,-h},{h,h,-h},{-h,h,-h},{-h,-h,h},{h,-h,h},{h,h,h},{-h,h,h}}
	faces := [6][4]u32{{4,5,6,7},{1,0,3,2},{0,4,7,3},{5,1,2,6},{3,7,6,2},{0,1,5,4}}
	normals := [6]Vec3{{0,0,1},{0,0,-1},{-1,0,0},{1,0,0},{0,1,0},{0,-1,0}}
	uvs := [4]Vec2{{0,0},{1,0},{1,1},{0,1}}
	for face in 0..<6 {for corner in 0..<4 {vertices[face*4+corner] = {positions[faces[face][corner]], normals[face], uvs[corner]}}}
	indices := make([]u32, 36)
	for face in 0..<6 {
		base := u32(face*4); offset := face*6
		face_indices := [6]u32{base,base+1,base+2,base,base+2,base+3}
		for value, index in face_indices {indices[offset+index] = value}
	}
	return {vertices, indices}, ""
}

plane :: proc(width: f32 = 1, depth: f32 = 1) -> (Geometry_Desc, string) {
	if !finite(width) || !finite(depth) || width <= 0 || depth <= 0 {return {}, "plane dimensions must be positive and finite"}
	w, d := width/2, depth/2
	vertices := make([]Vertex, 4)
	vertices[0] = {{-w,0,-d},{0,1,0},{0,0}}; vertices[1] = {{w,0,-d},{0,1,0},{1,0}}
	vertices[2] = {{w,0,d},{0,1,0},{1,1}}; vertices[3] = {{-w,0,d},{0,1,0},{0,1}}
	indices := make([]u32, 6)
	copy(indices, []u32{0,1,2,0,2,3})
	return {vertices, indices}, ""
}
