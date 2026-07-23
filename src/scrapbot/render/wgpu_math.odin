package render

import shared "../shared"
import "base:intrinsics"
import "core:math"

F32x4 :: #simd[4]f32

WGPU_Shadow_Cascades :: struct {
	matrices: [WGPU_SHADOW_CASCADE_COUNT]Mat4,
	splits: [WGPU_SHADOW_CASCADE_COUNT]f32,
}

f32x4_from_array :: proc "contextless" (value: [4]f32) -> F32x4 {
	return transmute(F32x4)value
}

f32x4_to_array :: proc "contextless" (value: F32x4) -> [4]f32 {
	return transmute([4]f32)value
}

f32x4_dot :: proc "contextless" (a, b: F32x4) -> f32 {
	return intrinsics.simd_reduce_add_pairs(intrinsics.simd_mul(a, b))
}

wgpu_build_mvp :: proc(
	instance: Render_Instance,
	camera: Camera_Instance,
	has_camera: bool,
	width, height: u32,
) -> Mat4 {
	return mat4_mul(
		wgpu_build_view_projection(camera, has_camera, width, height),
		wgpu_build_model(instance.transform),
	)
}

wgpu_build_view_projection :: proc(
	camera: Camera_Instance,
	has_camera: bool,
	width, height: u32,
) -> Mat4 {
	view, projection := wgpu_build_camera_matrices(camera, has_camera, width, height)
	return mat4_mul(projection, view)
}

wgpu_build_camera_matrices :: proc(
	camera: Camera_Instance,
	has_camera: bool,
	width, height: u32,
) -> (
	Mat4,
	Mat4,
) {
	aspect := f32(16.0 / 9.0)
	if width > 0 && height > 0 {
		aspect = f32(width) / f32(height)
	}

	eye := Vec3{0, 2, 6}
	fov := f32(60)
	near := f32(0.1)
	far := f32(100)
	if has_camera {
		eye = camera.transform.position
		if camera.camera.fov > 0 {
			fov = camera.camera.fov
		}
		if camera.camera.near > 0 {
			near = camera.camera.near
		}
		if camera.camera.far > near {
			far = camera.camera.far
		}
	}

	target := Vec3{0, 0, 0}
	up := Vec3{0, 1, 0}
	if has_camera {
		target = shared.camera_vec3_add(eye, shared.camera_forward(camera.transform.rotation))
		up = shared.camera_up(camera.transform.rotation)
	}
	view := mat4_look_at(eye, target, up)
	projection := mat4_perspective(math.to_radians(fov), aspect, near, far)
	return view, projection
}

wgpu_temporal_jitter :: proc(sample_index: u64, width, height: u32) -> Vec2 {
	if width == 0 || height == 0 {
		return {}
	}
	sequence := [8]Vec2 {
		{0.5, 1.0 / 3.0},
		{0.25, 2.0 / 3.0},
		{0.75, 1.0 / 9.0},
		{0.125, 4.0 / 9.0},
		{0.625, 7.0 / 9.0},
		{0.375, 2.0 / 9.0},
		{0.875, 5.0 / 9.0},
		{0.0625, 8.0 / 9.0},
	}
	sample := sequence[int(sample_index % u64(len(sequence)))]
	return {(sample.x - 0.5) * 2 / f32(width), (sample.y - 0.5) * 2 / f32(height)}
}

wgpu_jitter_projection :: proc(projection: Mat4, jitter: Vec2) -> Mat4 {
	result := projection
	result[8] += jitter.x
	result[9] += jitter.y
	return result
}

wgpu_device_depth_to_view_distance :: proc(depth: f32, projection: Mat4) -> f32 {
	return projection[14] / (depth + projection[10])
}

wgpu_inverse_rigid_view :: proc(view: Mat4) -> Mat4 {
	result := mat4_identity()
	result[0], result[1], result[2] = view[0], view[4], view[8]
	result[4], result[5], result[6] = view[1], view[5], view[9]
	result[8], result[9], result[10] = view[2], view[6], view[10]
	result[12] = -(result[0] * view[12] + result[4] * view[13] + result[8] * view[14])
	result[13] = -(result[1] * view[12] + result[5] * view[13] + result[9] * view[14])
	result[14] = -(result[2] * view[12] + result[6] * view[13] + result[10] * view[14])
	return result
}

wgpu_temporal_camera_state :: proc(
	camera: Camera_Instance,
	has_camera: bool,
) -> WGPU_Temporal_Camera {
	if !has_camera {
		return {position = {0, 2, 6}, forward = vec3_normalize(Vec3{0, -2, -6}), fov = 60}
	}
	fov := camera.camera.fov
	if fov <= 0 {
		fov = 60
	}
	return {
		position = camera.transform.position,
		forward = shared.camera_forward(camera.transform.rotation),
		fov = fov,
		has_camera = true,
	}
}

wgpu_temporal_camera_continuous :: proc(previous, current: WGPU_Temporal_Camera) -> bool {
	if previous.has_camera != current.has_camera {
		return false
	}
	offset := vec3_sub(current.position, previous.position)
	if vec3_dot(offset, offset) > 4 {
		return false
	}
	if vec3_dot(previous.forward, current.forward) < 0.8660254 {
		return false
	}
	return math.abs(previous.fov - current.fov) <= 10
}

wgpu_extract_frustum_planes :: proc(value: Mat4) -> [6][4]f32 {
	rows := [4][4]f32 {
		{value[0], value[4], value[8], value[12]},
		{value[1], value[5], value[9], value[13]},
		{value[2], value[6], value[10], value[14]},
		{value[3], value[7], value[11], value[15]},
	}
	planes := [6][4]f32 {
		vec4_add(rows[3], rows[0]),
		vec4_sub(rows[3], rows[0]),
		vec4_add(rows[3], rows[1]),
		vec4_sub(rows[3], rows[1]),
		rows[2],
		vec4_sub(rows[3], rows[2]),
	}
	for &plane in planes {
		packed := f32x4_from_array(plane)
		normal := intrinsics.simd_mul(packed, F32x4{1, 1, 1, 0})
		length := math.sqrt(f32x4_dot(normal, normal))
		if length > 0.000001 {
			plane = f32x4_to_array(intrinsics.simd_mul(packed, F32x4(1 / length)))
		}
	}
	return planes
}

wgpu_sphere_visible :: proc(bounds: [4]f32, planes: [6][4]f32) -> bool {
	center := F32x4{bounds[0], bounds[1], bounds[2], 1}
	for plane in planes {
		distance := f32x4_dot(f32x4_from_array(plane), center)
		if distance < -bounds[3] {
			return false
		}
	}
	return true
}

vec4_add :: proc(a, b: [4]f32) -> [4]f32 {
	return f32x4_to_array(intrinsics.simd_add(f32x4_from_array(a), f32x4_from_array(b)))
}

vec4_sub :: proc(a, b: [4]f32) -> [4]f32 {
	return f32x4_to_array(intrinsics.simd_sub(f32x4_from_array(a), f32x4_from_array(b)))
}

wgpu_build_model :: proc(transform: shared.Transform_Component) -> Mat4 {
	return mat4_mul(
		mat4_translate(transform.position),
		mat4_mul(
			mat4_rotate_z(transform.rotation.z),
			mat4_mul(
				mat4_rotate_y(transform.rotation.y),
				mat4_mul(mat4_rotate_x(transform.rotation.x), mat4_scale(transform.scale)),
			),
		),
	)
}

wgpu_build_normal_model :: proc(transform: shared.Transform_Component) -> Mat4 {
	return wgpu_build_normal_model_from_model(wgpu_build_model(transform), transform.scale)
}

wgpu_build_normal_model_from_model :: proc(model: Mat4, scale: Vec3) -> Mat4 {
	inverse_scale := Vec3{}
	if math.abs(scale.x) > 0.000001 { inverse_scale.x = 1 / (scale.x * scale.x) }
	if math.abs(scale.y) > 0.000001 { inverse_scale.y = 1 / (scale.y * scale.y) }
	if math.abs(scale.z) > 0.000001 { inverse_scale.z = 1 / (scale.z * scale.z) }
	return Mat4 {
		model[0] * inverse_scale.x,
		model[1] * inverse_scale.x,
		model[2] * inverse_scale.x,
		0,
		model[4] * inverse_scale.y,
		model[5] * inverse_scale.y,
		model[6] * inverse_scale.y,
		0,
		model[8] * inverse_scale.z,
		model[9] * inverse_scale.z,
		model[10] * inverse_scale.z,
		0,
		0,
		0,
		0,
		1,
	}
}

wgpu_build_directional_light_view_projection :: proc(direction: Vec3) -> Mat4 {
	normalized := vec3_normalize(direction)
	if vec3_dot(normalized, normalized) <= 0 { normalized = Vec3{0, -1, 0} }
	eye := Vec3{-normalized.x * 20, -normalized.y * 20, -normalized.z * 20}
	up := Vec3{0, 1, 0}
	if math.abs(vec3_dot(normalized, up)) > 0.99 { up = Vec3{0, 0, 1} }
	return mat4_mul(mat4_orthographic(-16, 16, -16, 16, 0.1, 50), mat4_look_at(eye, Vec3{}, up))
}

wgpu_build_directional_shadow_cascades :: proc(
	camera: Camera_Instance,
	has_camera: bool,
	width, height: u32,
	direction: Vec3,
) -> WGPU_Shadow_Cascades {
	eye := Vec3{0, 2, 6}
	rotation := Vec3{}
	fov := f32(60)
	near := f32(0.1)
	far := f32(100)
	if has_camera {
		eye = camera.transform.position
		rotation = camera.transform.rotation
		if camera.camera.fov > 0 {
			fov = camera.camera.fov
		}
		if camera.camera.near > 0 {
			near = camera.camera.near
		}
		if camera.camera.far > near {
			far = camera.camera.far
		}
	}
	far = min(far, WGPU_SHADOW_MAX_DISTANCE)
	far = max(far, near + 0.001)
	aspect := f32(16.0 / 9.0)
	if width > 0 && height > 0 {
		aspect = f32(width) / f32(height)
	}
	forward := shared.camera_forward(rotation)
	right := shared.camera_right(rotation)
	up := shared.camera_up(rotation)
	tan_half_fov := math.tan(math.to_radians(fov) * 0.5)
	light_direction := vec3_normalize(direction)
	if vec3_dot(light_direction, light_direction) <= 0 {
		light_direction = {0, -1, 0}
	}
	light_up := Vec3{0, 1, 0}
	if math.abs(vec3_dot(light_direction, light_up)) > 0.99 {
		light_up = {0, 0, 1}
	}
	light_right := vec3_normalize(vec3_cross(light_direction, light_up))
	light_up = vec3_normalize(vec3_cross(light_right, light_direction))

	result: WGPU_Shadow_Cascades
	previous_split := near
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		fraction := f32(cascade_index + 1) / f32(WGPU_SHADOW_CASCADE_COUNT)
		logarithmic := near * math.pow(far / near, fraction)
		uniform := near + (far - near) * fraction
		split := uniform * (1 - WGPU_SHADOW_SPLIT_LAMBDA) + logarithmic * WGPU_SHADOW_SPLIT_LAMBDA
		if cascade_index == WGPU_SHADOW_CASCADE_COUNT - 1 {
			split = far
		}
		result.splits[cascade_index] = split

		corners: [8]Vec3
		corner_count := 0
		distances := [2]f32{previous_split, split}
		coordinates := [2]f32{-1, 1}
		for distance in distances {
			half_height := distance * tan_half_fov
			half_width := half_height * aspect
			center := wgpu_vec3_add(eye, wgpu_vec3_mul(forward, distance))
			for y in coordinates {
				for x in coordinates {
					corners[corner_count] = wgpu_vec3_add(
						center,
						wgpu_vec3_add(
							wgpu_vec3_mul(right, x * half_width),
							wgpu_vec3_mul(up, y * half_height),
						),
					)
					corner_count += 1
				}
			}
		}
		center: Vec3
		for corner in corners {
			center = wgpu_vec3_add(center, corner)
		}
		center = wgpu_vec3_mul(center, 1.0 / f32(len(corners)))
		radius := f32(0)
		for corner in corners {
			radius = max(radius, wgpu_vec3_length(vec3_sub(corner, center)))
		}
		radius = max(math.ceil(radius * 16) / 16, 0.25)
		texel_size := 2 * radius / f32(WGPU_SHADOW_MAP_SIZE)
		right_coordinate := vec3_dot(center, light_right)
		up_coordinate := vec3_dot(center, light_up)
		snapped_right := math.floor(right_coordinate / texel_size + 0.5) * texel_size
		snapped_up := math.floor(up_coordinate / texel_size + 0.5) * texel_size
		center = wgpu_vec3_add(
			center,
			wgpu_vec3_add(
				wgpu_vec3_mul(light_right, snapped_right - right_coordinate),
				wgpu_vec3_mul(light_up, snapped_up - up_coordinate),
			),
		)
		eye_distance := radius * 3
		light_eye := vec3_sub(center, wgpu_vec3_mul(light_direction, eye_distance))
		view := mat4_look_at(light_eye, center, light_up)
		projection := mat4_orthographic(
			-radius,
			radius,
			-radius,
			radius,
			0.1,
			eye_distance + radius * 3,
		)
		result.matrices[cascade_index] = mat4_mul(projection, view)
		previous_split = split
	}
	return result
}

mat4_identity :: proc() -> Mat4 {
	return Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
}

mat4_mul :: proc(a, b: Mat4) -> Mat4 {
	a0 := F32x4{a[0], a[1], a[2], a[3]}
	a1 := F32x4{a[4], a[5], a[6], a[7]}
	a2 := F32x4{a[8], a[9], a[10], a[11]}
	a3 := F32x4{a[12], a[13], a[14], a[15]}
	result: Mat4
	for column in 0 ..< 4 {
		base := column * 4
		value := intrinsics.simd_mul(a0, F32x4(b[base]))
		value = intrinsics.fused_mul_add(a1, F32x4(b[base + 1]), value)
		value = intrinsics.fused_mul_add(a2, F32x4(b[base + 2]), value)
		value = intrinsics.fused_mul_add(a3, F32x4(b[base + 3]), value)
		packed := f32x4_to_array(value)
		copy(result[base:base + 4], packed[:])
	}
	return result
}

mat4_mul_scalar :: proc "contextless" (a, b: Mat4) -> Mat4 {
	result: Mat4
	for column in 0 ..< 4 {
		for row in 0 ..< 4 {
			sum: f32
			for index in 0 ..< 4 {
				sum += a[index * 4 + row] * b[column * 4 + index]
			}
			result[column * 4 + row] = sum
		}
	}
	return result
}

mat4_translate :: proc(value: Vec3) -> Mat4 {
	result := mat4_identity()
	result[12], result[13], result[14] = value.x, value.y, value.z
	return result
}

mat4_scale :: proc(value: Vec3) -> Mat4 {
	result := mat4_identity()
	result[0], result[5], result[10] = value.x, value.y, value.z
	return result
}

mat4_rotate_x :: proc(angle: f32) -> Mat4 {
	c, s := math.cos(angle), math.sin(angle)
	result := mat4_identity()
	result[5], result[6], result[9], result[10] = c, s, -s, c
	return result
}

mat4_rotate_y :: proc(angle: f32) -> Mat4 {
	c, s := math.cos(angle), math.sin(angle)
	result := mat4_identity()
	result[0], result[2], result[8], result[10] = c, -s, s, c
	return result
}

mat4_rotate_z :: proc(angle: f32) -> Mat4 {
	c, s := math.cos(angle), math.sin(angle)
	result := mat4_identity()
	result[0], result[1], result[4], result[5] = c, s, -s, c
	return result
}

mat4_perspective :: proc(fovy_radians, aspect, near, far: f32) -> Mat4 {
	f := 1 / math.tan(fovy_radians / 2)
	result: Mat4
	result[0], result[5] = f / aspect, f
	result[10], result[11] = far / (near - far), -1
	result[14] = (far * near) / (near - far)
	return result
}

mat4_orthographic :: proc(left, right, bottom, top, near, far: f32) -> Mat4 {
	result := mat4_identity()
	result[0] = 2 / (right - left)
	result[5] = 2 / (top - bottom)
	result[10] = 1 / (near - far)
	result[12] = -(right + left) / (right - left)
	result[13] = -(top + bottom) / (top - bottom)
	result[14] = near / (near - far)
	return result
}

mat4_look_at :: proc(eye, target, up: Vec3) -> Mat4 {
	forward := vec3_normalize(vec3_sub(target, eye))
	side := vec3_normalize(vec3_cross(forward, up))
	true_up := vec3_cross(side, forward)

	result := mat4_identity()
	result[0], result[1], result[2] = side.x, true_up.x, -forward.x
	result[4], result[5], result[6] = side.y, true_up.y, -forward.y
	result[8], result[9], result[10] = side.z, true_up.z, -forward.z
	result[12], result[13], result[14] =
		-vec3_dot(side, eye), -vec3_dot(true_up, eye), vec3_dot(forward, eye)
	return result
}

vec3_sub :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a.x - b.x, a.y - b.y, a.z - b.z}
}

wgpu_vec3_add :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a.x + b.x, a.y + b.y, a.z + b.z}
}

wgpu_vec3_mul :: proc(value: Vec3, scalar: f32) -> Vec3 {
	return Vec3{value.x * scalar, value.y * scalar, value.z * scalar}
}

wgpu_vec3_length :: proc(value: Vec3) -> f32 {
	return math.sqrt(vec3_dot(value, value))
}

vec3_cross :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

vec3_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

vec3_normalize :: proc(value: Vec3) -> Vec3 {
	length := math.sqrt(vec3_dot(value, value))
	if length <= 0 {
		return Vec3{}
	}
	return Vec3{value.x / length, value.y / length, value.z / length}
}
