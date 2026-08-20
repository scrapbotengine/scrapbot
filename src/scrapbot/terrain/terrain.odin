package terrain

import shared "../shared"
import "core:math"

Vec3 :: shared.Vec3

MAX_BRUSH_SAMPLE_RADIUS :: f32(31)
MAX_SAMPLE_COORDINATE :: f32(1_000_000_000)
MAX_EXTRACTION_AXIS_CELLS :: 64
MAX_EXTRACTION_TOTAL_CELLS :: 65_536

Sample_Coord :: struct {
	x, y, z: int,
}

Chunk_Coord :: struct {
	x, y, z: int,
}

Description :: struct {
	origin: Vec3,
	voxel_size: f32,
	height_columns: int,
	height_rows: int,
	height_cell_size: f32,
	heights: []f32,
}

Terrain :: struct {
	origin: Vec3,
	voxel_size: f32,
	height_columns: int,
	height_rows: int,
	height_cell_size: f32,
	heights: []f32,
	density_edits: map[Sample_Coord]f32,
}

Surface_Vertex :: struct {
	position: Vec3,
	normal: Vec3,
}

Surface_Mesh :: struct {
	vertices: [dynamic]Surface_Vertex,
	indices: [dynamic]u32,
	vertex_lookup: map[Surface_Edge]u32,
}

Surface_Edge :: struct {
	a, b: Sample_Coord,
}

Surface_Point :: struct {
	position: Vec3,
	edge: Surface_Edge,
}

Dirty_Chunk_Queue :: struct {
	cells_per_axis: int,
	chunks: [dynamic]Chunk_Coord,
	membership: map[Chunk_Coord]bool,
	read_index: int,
}

Pending_Density_Edit :: struct {
	sample: Sample_Coord,
	value: f32,
}

init :: proc(terrain: ^Terrain, description: Description) -> string {
	if terrain == nil {
		return "terrain destination is required"
	}
	if !finite_vec3(description.origin) {
		return "terrain origin must be finite"
	}
	if !finite(description.voxel_size) || description.voxel_size <= 0 {
		return "terrain voxel size must be positive and finite"
	}
	if !finite(description.height_cell_size) || description.height_cell_size <= 0 {
		return "terrain height cell size must be positive and finite"
	}
	if description.height_columns < 1 || description.height_rows < 1 {
		return "terrain height dimensions must be positive"
	}
	expected_height_count := (description.height_columns + 1) * (description.height_rows + 1)
	if len(description.heights) != expected_height_count {
		return "terrain height data must contain one value per height-grid sample"
	}
	for height in description.heights {
		if !finite(height) {
			return "terrain height data must be finite"
		}
	}

	terrain.origin = description.origin
	terrain.voxel_size = description.voxel_size
	terrain.height_columns = description.height_columns
	terrain.height_rows = description.height_rows
	terrain.height_cell_size = description.height_cell_size
	terrain.heights = make([]f32, len(description.heights))
	copy(terrain.heights, description.heights)
	terrain.density_edits = make(map[Sample_Coord]f32)
	return ""
}

destroy :: proc(terrain: ^Terrain) {
	if terrain == nil {
		return
	}
	delete(terrain.heights)
	delete(terrain.density_edits)
	terrain^ = {}
}

destroy_surface_mesh :: proc(mesh: ^Surface_Mesh) {
	if mesh == nil {
		return
	}
	delete(mesh.vertices)
	delete(mesh.indices)
	delete(mesh.vertex_lookup)
	mesh^ = {}
}

init_dirty_chunk_queue :: proc(queue: ^Dirty_Chunk_Queue, cells_per_axis: int) -> string {
	if queue == nil {
		return "terrain dirty-chunk queue destination is required"
	}
	if cells_per_axis < 1 || cells_per_axis > 64 {
		return "terrain dirty-chunk queues require between 1 and 64 cells per axis"
	}
	queue.cells_per_axis = cells_per_axis
	queue.chunks = make([dynamic]Chunk_Coord)
	queue.membership = make(map[Chunk_Coord]bool)
	return ""
}

destroy_dirty_chunk_queue :: proc(queue: ^Dirty_Chunk_Queue) {
	if queue == nil {
		return
	}
	delete(queue.chunks)
	delete(queue.membership)
	queue^ = {}
}

dirty_chunk_count :: proc(queue: ^Dirty_Chunk_Queue) -> int {
	if queue == nil {
		return 0
	}
	return len(queue.chunks) - queue.read_index
}

enqueue_dirty_chunk :: proc(queue: ^Dirty_Chunk_Queue, chunk: Chunk_Coord) {
	if queue == nil || queue.cells_per_axis < 1 || queue.membership[chunk] {
		return
	}
	queue.membership[chunk] = true
	append(&queue.chunks, chunk)
}

take_dirty_chunk :: proc(queue: ^Dirty_Chunk_Queue) -> (Chunk_Coord, bool) {
	if dirty_chunk_count(queue) == 0 {
		return {}, false
	}
	chunk := queue.chunks[queue.read_index]
	queue.read_index += 1
	delete_key(&queue.membership, chunk)
	if queue.read_index == len(queue.chunks) {
		clear(&queue.chunks)
		queue.read_index = 0
	} else if queue.read_index >= 1024 && queue.read_index * 2 >= len(queue.chunks) {
		remaining := len(queue.chunks) - queue.read_index
		copy(queue.chunks[:remaining], queue.chunks[queue.read_index:])
		resize(&queue.chunks, remaining)
		queue.read_index = 0
	}
	return chunk, true
}

enqueue_dirty_sample :: proc(queue: ^Dirty_Chunk_Queue, sample: Sample_Coord) {
	if queue == nil {
		return
	}
	chunks := affected_chunks_for_sample(sample, queue.cells_per_axis)
	defer delete(chunks)
	for chunk in chunks {
		enqueue_dirty_chunk(queue, chunk)
	}
}

apply_sphere_brush :: proc(
	terrain: ^Terrain,
	queue: ^Dirty_Chunk_Queue,
	center: Vec3,
	radius, strength: f32,
) -> (
	int,
	string,
) {
	if terrain == nil || terrain.heights == nil {
		return 0, "terrain is not initialized"
	}
	if queue == nil || queue.cells_per_axis < 1 {
		return 0, "terrain brush requires an initialized dirty-chunk queue"
	}
	if !finite_vec3(center) || !finite(radius) || radius <= 0 {
		return 0, "terrain brush center and positive radius must be finite"
	}
	if !finite(strength) {
		return 0, "terrain brush strength must be finite"
	}
	if strength == 0 {
		return 0, ""
	}
	local_center := sub(center, terrain.origin)
	sample_center := Vec3 {
		local_center.x / terrain.voxel_size,
		local_center.y / terrain.voxel_size,
		local_center.z / terrain.voxel_size,
	}
	if math.abs(sample_center.x) > MAX_SAMPLE_COORDINATE ||
	   math.abs(sample_center.y) > MAX_SAMPLE_COORDINATE ||
	   math.abs(sample_center.z) > MAX_SAMPLE_COORDINATE {
		return 0, "terrain brush center is outside the supported sample-coordinate range"
	}
	sample_radius := radius / terrain.voxel_size
	if sample_radius > MAX_BRUSH_SAMPLE_RADIUS {
		return 0, "terrain brush affects too many samples for one authoring step"
	}
	minimum := Sample_Coord {
		int(math.floor(sample_center.x - sample_radius)),
		int(math.floor(sample_center.y - sample_radius)),
		int(math.floor(sample_center.z - sample_radius)),
	}
	maximum := Sample_Coord {
		int(math.ceil(sample_center.x + sample_radius)),
		int(math.ceil(sample_center.y + sample_radius)),
		int(math.ceil(sample_center.z + sample_radius)),
	}
	pending := make([dynamic]Pending_Density_Edit)
	defer delete(pending)
	for z in minimum.z ..= maximum.z {
		for y in minimum.y ..= maximum.y {
			for x in minimum.x ..= maximum.x {
				sample := Sample_Coord{x, y, z}
				position := sample_world_position(terrain, sample)
				distance := length(sub(position, center))
				if distance > radius {
					continue
				}
				t := 1 - distance / radius
				falloff := t * t * (3 - 2 * t)
				value := terrain.density_edits[sample] + strength * falloff
				if !finite(value) {
					return 0, "terrain brush would produce a non-finite density edit"
				}
				if value == terrain.density_edits[sample] {
					continue
				}
				append(&pending, Pending_Density_Edit{sample, value})
			}
		}
	}
	for edit in pending {
		set_density_edit(terrain, edit.sample, edit.value)
		enqueue_dirty_sample(queue, edit.sample)
	}
	return len(pending), ""
}

set_density_edit :: proc(terrain: ^Terrain, sample: Sample_Coord, value: f32) -> string {
	if terrain == nil || terrain.heights == nil {
		return "terrain is not initialized"
	}
	if !finite(value) {
		return "terrain density edits must be finite"
	}
	if value == 0 {
		delete_key(&terrain.density_edits, sample)
	} else {
		terrain.density_edits[sample] = value
	}
	return ""
}

density_at_sample :: proc(terrain: ^Terrain, sample: Sample_Coord) -> f32 {
	position := sample_world_position(terrain, sample)
	baseline := height_at_world(terrain, position.x, position.z) - position.y
	edit := terrain.density_edits[sample]
	return baseline + edit
}

density_at_world :: proc(terrain: ^Terrain, position: Vec3) -> f32 {
	baseline := height_at_world(terrain, position.x, position.z) - position.y
	local := sub(position, terrain.origin)
	x := local.x / terrain.voxel_size
	y := local.y / terrain.voxel_size
	z := local.z / terrain.voxel_size
	x0 := int(math.floor(x))
	y0 := int(math.floor(y))
	z0 := int(math.floor(z))
	tx := x - f32(x0)
	ty := y - f32(y0)
	tz := z - f32(z0)
	edit := f32(0)
	for dz in 0 ..= 1 {
		wz := tz if dz == 1 else 1 - tz
		for dy in 0 ..= 1 {
			wy := ty if dy == 1 else 1 - ty
			for dx in 0 ..= 1 {
				wx := tx if dx == 1 else 1 - tx
				edit +=
					terrain.density_edits[Sample_Coord{x0 + dx, y0 + dy, z0 + dz}] * wx * wy * wz
			}
		}
	}
	return baseline + edit
}

height_at_world :: proc(terrain: ^Terrain, world_x, world_z: f32) -> f32 {
	x := clamp(
		(world_x - terrain.origin.x) / terrain.height_cell_size,
		f32(0),
		f32(terrain.height_columns),
	)
	z := clamp(
		(world_z - terrain.origin.z) / terrain.height_cell_size,
		f32(0),
		f32(terrain.height_rows),
	)
	x0 := min(int(math.floor(x)), terrain.height_columns - 1)
	z0 := min(int(math.floor(z)), terrain.height_rows - 1)
	x1 := x0 + 1
	z1 := z0 + 1
	tx := x - f32(x0)
	tz := z - f32(z0)
	stride := terrain.height_columns + 1
	h00 := terrain.heights[z0 * stride + x0]
	h10 := terrain.heights[z0 * stride + x1]
	h01 := terrain.heights[z1 * stride + x0]
	h11 := terrain.heights[z1 * stride + x1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)
}

sample_world_position :: proc(terrain: ^Terrain, sample: Sample_Coord) -> Vec3 {
	return add(
		terrain.origin,
		Vec3 {
			f32(sample.x) * terrain.voxel_size,
			f32(sample.y) * terrain.voxel_size,
			f32(sample.z) * terrain.voxel_size,
		},
	)
}

extract_chunk :: proc(
	terrain: ^Terrain,
	chunk: Chunk_Coord,
	cells_per_axis: int,
) -> (
	Surface_Mesh,
	string,
) {
	if terrain == nil || terrain.heights == nil {
		return {}, "terrain is not initialized"
	}
	if cells_per_axis < 1 || cells_per_axis > MAX_EXTRACTION_AXIS_CELLS {
		return {}, "terrain extraction chunks must contain between 1 and 64 cells per axis"
	}
	cell_origin := Sample_Coord {
		chunk.x * cells_per_axis,
		chunk.y * cells_per_axis,
		chunk.z * cells_per_axis,
	}
	return extract_region(
		terrain,
		cell_origin,
		Sample_Coord{cells_per_axis, cells_per_axis, cells_per_axis},
	)
}

extract_region :: proc(
	terrain: ^Terrain,
	cell_origin, cell_counts: Sample_Coord,
) -> (
	Surface_Mesh,
	string,
) {
	if terrain == nil || terrain.heights == nil {
		return {}, "terrain is not initialized"
	}
	if cell_counts.x < 1 ||
	   cell_counts.y < 1 ||
	   cell_counts.z < 1 ||
	   cell_counts.x > MAX_EXTRACTION_AXIS_CELLS ||
	   cell_counts.y > MAX_EXTRACTION_AXIS_CELLS ||
	   cell_counts.z > MAX_EXTRACTION_AXIS_CELLS {
		return {}, "terrain extraction regions must contain between 1 and 64 cells per axis"
	}
	if cell_counts.x * cell_counts.y * cell_counts.z > MAX_EXTRACTION_TOTAL_CELLS {
		return {}, "terrain extraction regions may contain at most 65536 cells"
	}
	mesh := Surface_Mesh {
		vertex_lookup = make(map[Surface_Edge]u32),
	}
	for z in 0 ..< cell_counts.z {
		for y in 0 ..< cell_counts.y {
			for x in 0 ..< cell_counts.x {
				extract_cell(
					terrain,
					Sample_Coord{cell_origin.x + x, cell_origin.y + y, cell_origin.z + z},
					&mesh,
				)
			}
		}
	}
	delete(mesh.vertex_lookup)
	mesh.vertex_lookup = nil
	return mesh, ""
}

affected_chunks_for_sample :: proc(
	sample: Sample_Coord,
	cells_per_axis: int,
) -> [dynamic]Chunk_Coord {
	result := make([dynamic]Chunk_Coord, 0, 8)
	if cells_per_axis < 1 {
		return result
	}
	for z in sample.z - 1 ..= sample.z {
		for y in sample.y - 1 ..= sample.y {
			for x in sample.x - 1 ..= sample.x {
				chunk := Chunk_Coord {
					floor_div(x, cells_per_axis),
					floor_div(y, cells_per_axis),
					floor_div(z, cells_per_axis),
				}
				found := false
				for existing in result {
					if existing == chunk {
						found = true
						break
					}
				}
				if !found {
					append(&result, chunk)
				}
			}
		}
	}
	return result
}

@(private)
extract_cell :: proc(terrain: ^Terrain, origin: Sample_Coord, mesh: ^Surface_Mesh) {
	offsets := [8]Sample_Coord {
		{0, 0, 0},
		{1, 0, 0},
		{0, 1, 0},
		{1, 1, 0},
		{0, 0, 1},
		{1, 0, 1},
		{0, 1, 1},
		{1, 1, 1},
	}
	positions: [8]Vec3
	densities: [8]f32
	samples: [8]Sample_Coord
	for offset, index in offsets {
		sample := Sample_Coord{origin.x + offset.x, origin.y + offset.y, origin.z + offset.z}
		samples[index] = sample
		positions[index] = sample_world_position(terrain, sample)
		densities[index] = density_at_sample(terrain, sample)
	}
	tetrahedra := [6][4]int {
		{0, 1, 3, 7},
		{0, 3, 2, 7},
		{0, 2, 6, 7},
		{0, 6, 4, 7},
		{0, 4, 5, 7},
		{0, 5, 1, 7},
	}
	for tetrahedron in tetrahedra {
		extract_tetrahedron(terrain, samples, positions, densities, tetrahedron, mesh)
	}
}

@(private)
extract_tetrahedron :: proc(
	terrain: ^Terrain,
	samples: [8]Sample_Coord,
	positions: [8]Vec3,
	densities: [8]f32,
	tetrahedron: [4]int,
	mesh: ^Surface_Mesh,
) {
	inside: [4]int
	outside: [4]int
	inside_count := 0
	outside_count := 0
	for corner in tetrahedron {
		if densities[corner] >= 0 {
			inside[inside_count] = corner
			inside_count += 1
		} else {
			outside[outside_count] = corner
			outside_count += 1
		}
	}
	if inside_count == 0 || inside_count == 4 {
		return
	}
	if inside_count == 1 {
		a := interpolate_surface_point(
			samples[inside[0]],
			samples[outside[0]],
			positions[inside[0]],
			positions[outside[0]],
			densities[inside[0]],
			densities[outside[0]],
		)
		b := interpolate_surface_point(
			samples[inside[0]],
			samples[outside[1]],
			positions[inside[0]],
			positions[outside[1]],
			densities[inside[0]],
			densities[outside[1]],
		)
		c := interpolate_surface_point(
			samples[inside[0]],
			samples[outside[2]],
			positions[inside[0]],
			positions[outside[2]],
			densities[inside[0]],
			densities[outside[2]],
		)
		emit_triangle(terrain, mesh, a, b, c)
		return
	}
	if inside_count == 3 {
		a := interpolate_surface_point(
			samples[outside[0]],
			samples[inside[0]],
			positions[outside[0]],
			positions[inside[0]],
			densities[outside[0]],
			densities[inside[0]],
		)
		b := interpolate_surface_point(
			samples[outside[0]],
			samples[inside[1]],
			positions[outside[0]],
			positions[inside[1]],
			densities[outside[0]],
			densities[inside[1]],
		)
		c := interpolate_surface_point(
			samples[outside[0]],
			samples[inside[2]],
			positions[outside[0]],
			positions[inside[2]],
			densities[outside[0]],
			densities[inside[2]],
		)
		emit_triangle(terrain, mesh, a, c, b)
		return
	}

	a := interpolate_surface_point(
		samples[inside[0]],
		samples[outside[0]],
		positions[inside[0]],
		positions[outside[0]],
		densities[inside[0]],
		densities[outside[0]],
	)
	b := interpolate_surface_point(
		samples[inside[0]],
		samples[outside[1]],
		positions[inside[0]],
		positions[outside[1]],
		densities[inside[0]],
		densities[outside[1]],
	)
	c := interpolate_surface_point(
		samples[inside[1]],
		samples[outside[1]],
		positions[inside[1]],
		positions[outside[1]],
		densities[inside[1]],
		densities[outside[1]],
	)
	d := interpolate_surface_point(
		samples[inside[1]],
		samples[outside[0]],
		positions[inside[1]],
		positions[outside[0]],
		densities[inside[1]],
		densities[outside[0]],
	)
	emit_triangle(terrain, mesh, a, b, c)
	emit_triangle(terrain, mesh, a, c, d)
}

@(private)
interpolate_surface_point :: proc(
	sample_a, sample_b: Sample_Coord,
	a, b: Vec3,
	density_a, density_b: f32,
) -> Surface_Point {
	if density_a == 0 {
		return Surface_Point{a, Surface_Edge{sample_a, sample_a}}
	}
	if density_b == 0 {
		return Surface_Point{b, Surface_Edge{sample_b, sample_b}}
	}
	magnitude_a := math.abs(density_a)
	magnitude_b := math.abs(density_b)
	scale := max(magnitude_a, magnitude_b)
	scaled_a := magnitude_a / scale
	scaled_b := magnitude_b / scale
	t := clamp(scaled_a / (scaled_a + scaled_b), f32(0), f32(1))
	return Surface_Point{lerp3(a, b, t), canonical_edge(sample_a, sample_b)}
}

@(private)
emit_triangle :: proc(terrain: ^Terrain, mesh: ^Surface_Mesh, a, b, c: Surface_Point) {
	vertex_b := b
	vertex_c := c
	face_normal := cross(sub(vertex_b.position, a.position), sub(vertex_c.position, a.position))
	if a.edge == vertex_b.edge || a.edge == vertex_c.edge || vertex_b.edge == vertex_c.edge {
		return
	}
	if face_normal.x == 0 && face_normal.y == 0 && face_normal.z == 0 {
		return
	}
	normal_a := surface_normal(terrain, a.position)
	normal_b := surface_normal(terrain, vertex_b.position)
	normal_c := surface_normal(terrain, vertex_c.position)
	average_normal := add(add(normal_a, normal_b), normal_c)
	if dot(face_normal, average_normal) < 0 {
		vertex_b, vertex_c = vertex_c, vertex_b
		normal_b, normal_c = normal_c, normal_b
	}
	index_a := surface_vertex(mesh, a, normal_a)
	index_b := surface_vertex(mesh, vertex_b, normal_b)
	index_c := surface_vertex(mesh, vertex_c, normal_c)
	append(&mesh.indices, index_a, index_b, index_c)
}

@(private)
surface_vertex :: proc(mesh: ^Surface_Mesh, point: Surface_Point, normal: Vec3) -> u32 {
	if index, found := mesh.vertex_lookup[point.edge]; found {
		return index
	}
	index := u32(len(mesh.vertices))
	append(&mesh.vertices, Surface_Vertex{point.position, normal})
	mesh.vertex_lookup[point.edge] = index
	return index
}

@(private)
canonical_edge :: proc(a, b: Sample_Coord) -> Surface_Edge {
	if sample_coord_less(b, a) {
		return {b, a}
	}
	return {a, b}
}

@(private)
sample_coord_less :: proc(a, b: Sample_Coord) -> bool {
	if a.x != b.x {
		return a.x < b.x
	}
	if a.y != b.y {
		return a.y < b.y
	}
	return a.z < b.z
}

@(private)
surface_normal :: proc(terrain: ^Terrain, position: Vec3) -> Vec3 {
	epsilon := terrain.voxel_size * 0.25
	dx :=
		f64(density_at_world(terrain, add(position, Vec3{epsilon, 0, 0}))) -
		f64(density_at_world(terrain, sub(position, Vec3{epsilon, 0, 0})))
	dy :=
		f64(density_at_world(terrain, add(position, Vec3{0, epsilon, 0}))) -
		f64(density_at_world(terrain, sub(position, Vec3{0, epsilon, 0})))
	dz :=
		f64(density_at_world(terrain, add(position, Vec3{0, 0, epsilon}))) -
		f64(density_at_world(terrain, sub(position, Vec3{0, 0, epsilon})))
	return normalize_f64(-dx, -dy, -dz)
}

@(private)
normalize_f64 :: proc(x, y, z: f64) -> Vec3 {
	scale := max(math.abs(x), math.abs(y), math.abs(z))
	if scale == 0 {
		return {0, 1, 0}
	}
	sx, sy, sz := x / scale, y / scale, z / scale
	inverse_length := 1 / math.sqrt(sx * sx + sy * sy + sz * sz)
	return {f32(sx * inverse_length), f32(sy * inverse_length), f32(sz * inverse_length)}
}

@(private)
floor_div :: proc(value, divisor: int) -> int {
	quotient := value / divisor
	remainder := value % divisor
	if remainder != 0 && value < 0 {
		quotient -= 1
	}
	return quotient
}

@(private)
finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

@(private)
finite_vec3 :: proc(value: Vec3) -> bool {
	return finite(value.x) && finite(value.y) && finite(value.z)
}

@(private)
length :: proc(value: Vec3) -> f32 {
	return math.sqrt(dot(value, value))
}

@(private)
clamp :: proc(value, minimum, maximum: f32) -> f32 {
	return min(max(value, minimum), maximum)
}

@(private)
lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

@(private)
lerp3 :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return Vec3{lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t)}
}

@(private)
add :: proc(a, b: Vec3) -> Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

@(private)
sub :: proc(a, b: Vec3) -> Vec3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}

@(private)
dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

@(private)
cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

@(private)
normalize :: proc(value: Vec3) -> Vec3 {
	scale := max(math.abs(value.x), math.abs(value.y), math.abs(value.z))
	if scale == 0 {
		return {0, 1, 0}
	}
	scaled := Vec3{value.x / scale, value.y / scale, value.z / scale}
	inverse_length := 1 / math.sqrt(dot(scaled, scaled))
	return {scaled.x * inverse_length, scaled.y * inverse_length, scaled.z * inverse_length}
}
