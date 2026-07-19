package shared

import "core:math"

Transform_Quaternion :: struct {
	x, y, z, w: f32,
}

transform_combine :: proc "contextless" (
	parent, local: Transform_Component,
) -> Transform_Component {
	parent_rotation := transform_quaternion_from_euler(parent.rotation)
	local_rotation := transform_quaternion_from_euler(local.rotation)
	scaled_position := transform_vec3_mul_components(local.position, parent.scale)
	rotated_position := transform_quaternion_rotate(parent_rotation, scaled_position)
	return {
		position = transform_vec3_add(parent.position, rotated_position),
		rotation = transform_quaternion_to_euler(
			transform_quaternion_mul(parent_rotation, local_rotation),
		),
		scale = transform_vec3_mul_components(parent.scale, local.scale),
	}
}

transform_relative_to :: proc "contextless" (
	parent, world: Transform_Component,
) -> Transform_Component {
	parent_rotation := transform_quaternion_from_euler(parent.rotation)
	world_rotation := transform_quaternion_from_euler(world.rotation)
	offset := transform_vec3_sub(world.position, parent.position)
	unrotated := transform_quaternion_rotate(
		transform_quaternion_conjugate(parent_rotation),
		offset,
	)
	return {
		position = transform_vec3_div_components(unrotated, parent.scale),
		rotation = transform_quaternion_to_euler(
			transform_quaternion_mul(
				transform_quaternion_conjugate(parent_rotation),
				world_rotation,
			),
		),
		scale = transform_vec3_div_components(world.scale, parent.scale),
	}
}

transform_quaternion_from_euler :: proc "contextless" (rotation: Vec3) -> Transform_Quaternion {
	hx, hy, hz := rotation.x * 0.5, rotation.y * 0.5, rotation.z * 0.5
	sx, cx := math.sin(hx), math.cos(hx)
	sy, cy := math.sin(hy), math.cos(hy)
	sz, cz := math.sin(hz), math.cos(hz)
	return transform_quaternion_normalize(
		{
			x = sx * cy * cz - cx * sy * sz,
			y = cx * sy * cz + sx * cy * sz,
			z = cx * cy * sz - sx * sy * cz,
			w = cx * cy * cz + sx * sy * sz,
		},
	)
}

transform_quaternion_to_euler :: proc "contextless" (value: Transform_Quaternion) -> Vec3 {
	q := transform_quaternion_normalize(value)
	sin_x := 2 * (q.w * q.x + q.y * q.z)
	cos_x := 1 - 2 * (q.x * q.x + q.y * q.y)
	x := math.atan2(sin_x, cos_x)
	sin_y := 2 * (q.w * q.y - q.z * q.x)
	y: f32
	if math.abs(sin_y) >= 1 {
		y = math.copy_sign(f32(math.PI / 2), sin_y)
	} else {
		y = math.asin(sin_y)
	}
	sin_z := 2 * (q.w * q.z + q.x * q.y)
	cos_z := 1 - 2 * (q.y * q.y + q.z * q.z)
	z := math.atan2(sin_z, cos_z)
	return {x, y, z}
}

transform_quaternion_mul :: proc "contextless" (
	a, b: Transform_Quaternion,
) -> Transform_Quaternion {
	return transform_quaternion_normalize(
		{
			x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
			y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
			z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
			w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
		},
	)
}

transform_quaternion_conjugate :: proc "contextless" (
	value: Transform_Quaternion,
) -> Transform_Quaternion {
	return {-value.x, -value.y, -value.z, value.w}
}

transform_quaternion_rotate :: proc "contextless" (
	rotation: Transform_Quaternion,
	value: Vec3,
) -> Vec3 {
	q := transform_quaternion_normalize(rotation)
	u := Vec3{q.x, q.y, q.z}
	dot_uv := transform_vec3_dot(u, value)
	dot_uu := transform_vec3_dot(u, u)
	cross := transform_vec3_cross(u, value)
	return transform_vec3_add(
		transform_vec3_add(
			transform_vec3_mul(u, 2 * dot_uv),
			transform_vec3_mul(value, q.w * q.w - dot_uu),
		),
		transform_vec3_mul(cross, 2 * q.w),
	)
}

transform_quaternion_normalize :: proc "contextless" (
	value: Transform_Quaternion,
) -> Transform_Quaternion {
	length := math.sqrt(
		value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w,
	)
	if length <= 0.000001 {
		return {w = 1}
	}
	return {value.x / length, value.y / length, value.z / length, value.w / length}
}

transform_vec3_add :: proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

transform_vec3_sub :: proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.x - b.x, a.y - b.y, a.z - b.z}
}

transform_vec3_mul :: proc "contextless" (value: Vec3, scalar: f32) -> Vec3 {
	return {value.x * scalar, value.y * scalar, value.z * scalar}
}

transform_vec3_mul_components :: proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.x * b.x, a.y * b.y, a.z * b.z}
}

transform_vec3_div_components :: proc "contextless" (value, divisor: Vec3) -> Vec3 {
	result: Vec3
	if math.abs(divisor.x) > 0.000001 {
		result.x = value.x / divisor.x
	}
	if math.abs(divisor.y) > 0.000001 {
		result.y = value.y / divisor.y
	}
	if math.abs(divisor.z) > 0.000001 {
		result.z = value.z / divisor.z
	}
	return result
}

transform_vec3_dot :: proc "contextless" (a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

transform_vec3_cross :: proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}
