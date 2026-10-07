package resources


Geometry_Query_Triangle :: struct {
	a, b, c: Vec3,
}

Geometry_Query_Iterator :: struct {
	geometry: ^Geometry,
	triangle_index: int,
}


geometry_index_count :: proc "contextless" (geometry: ^Geometry) -> int {
	if geometry == nil {
		return 0
	}
	return len(geometry.indices)
}


geometry_query_iterator :: proc "contextless" (geometry: ^Geometry) -> Geometry_Query_Iterator {
	return {geometry = geometry}
}

geometry_query_next :: proc "contextless" (
	iterator: ^Geometry_Query_Iterator,
) -> (
	Geometry_Query_Triangle,
	bool,
) {
	if iterator == nil || iterator.geometry == nil {
		return {}, false
	}
	geometry := iterator.geometry
	index := iterator.triangle_index * 3
	if index + 2 >= len(geometry.indices) {
		return {}, false
	}
	iterator.triangle_index += 1
	a := geometry.indices[index]
	b := geometry.indices[index + 1]
	c := geometry.indices[index + 2]
	if int(a) >= len(geometry.vertices) ||
	   int(b) >= len(geometry.vertices) ||
	   int(c) >= len(geometry.vertices) {
		return {}, false
	}
	return {
			a = geometry.vertices[a].position,
			b = geometry.vertices[b].position,
			c = geometry.vertices[c].position,
		},
		true
}
