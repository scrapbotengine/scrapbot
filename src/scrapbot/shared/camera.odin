package shared

import "core:math"

camera_exposure :: proc "contextless" (camera: Camera_Component) -> f32 {
	if camera.exposure == 0 {
		return 1
	}
	return camera.exposure
}

camera_forward :: proc(rotation: Vec3) -> Vec3 {
	cos_pitch := math.cos(rotation.x)
	return {
		math.sin(rotation.y) * cos_pitch,
		math.sin(rotation.x),
		-math.cos(rotation.y) * cos_pitch,
	}
}

camera_right :: proc(rotation: Vec3) -> Vec3 {
	forward := camera_forward(rotation)
	base_right := camera_vec3_normalize(camera_vec3_cross(forward, {0, 1, 0}))
	base_up := camera_vec3_cross(base_right, forward)
	cos_roll, sin_roll := math.cos(rotation.z), math.sin(rotation.z)
	return camera_vec3_normalize(
		camera_vec3_add(camera_vec3_mul(base_right, cos_roll), camera_vec3_mul(base_up, sin_roll)),
	)
}

camera_up :: proc(rotation: Vec3) -> Vec3 {
	return camera_vec3_cross(camera_right(rotation), camera_forward(rotation))
}

camera_vec3_add :: proc(a, b: Vec3) -> Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

camera_vec3_mul :: proc(value: Vec3, scalar: f32) -> Vec3 {
	return {value.x * scalar, value.y * scalar, value.z * scalar}
}

camera_vec3_cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

camera_vec3_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

camera_vec3_normalize :: proc(value: Vec3) -> Vec3 {
	length := math.sqrt(camera_vec3_dot(value, value))
	if length <= 0.000001 {
		return {}
	}
	return {value.x / length, value.y / length, value.z / length}
}
