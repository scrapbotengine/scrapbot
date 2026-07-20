package render

import shared "../shared"
import "core:math"

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
	return mat4_mul(projection, view)
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
		length := math.sqrt(plane[0] * plane[0] + plane[1] * plane[1] + plane[2] * plane[2])
		if length > 0.000001 {
			for index in 0 ..< 4 {
				plane[index] /= length
			}
		}
	}
	return planes
}

wgpu_sphere_visible :: proc(bounds: [4]f32, planes: [6][4]f32) -> bool {
	for plane in planes {
		distance := plane[0] * bounds[0] + plane[1] * bounds[1] + plane[2] * bounds[2] + plane[3]
		if distance < -bounds[3] {
			return false
		}
	}
	return true
}

vec4_add :: proc(a, b: [4]f32) -> [4]f32 {
	return {a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]}
}

vec4_sub :: proc(a, b: [4]f32) -> [4]f32 {
	return {a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]}
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

mat4_identity :: proc() -> Mat4 {
	return Mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
}

mat4_mul :: proc(a, b: Mat4) -> Mat4 {
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
