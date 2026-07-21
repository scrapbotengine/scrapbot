package render

import "core:math"
import "core:testing"

simd_test_random :: proc(state: ^u32) -> f32 {
	state^ = state^ * 1664525 + 1013904223
	return f32(i32(state^ >> 8) % 20001 - 10000) / 997
}

@(test)
test_simd_matrix_multiply_matches_scalar_oracle :: proc(t: ^testing.T) {
	state := u32(0x7a914e2d)
	for _ in 0 ..< 256 {
		a, b: Mat4
		for &value in a {
			value = simd_test_random(&state)
		}
		for &value in b {
			value = simd_test_random(&state)
		}
		actual := mat4_mul(a, b)
		expected := mat4_mul_scalar(a, b)
		for value, index in actual {
			testing.expectf(
				t,
				math.abs(value - expected[index]) <= 0.0002,
				"matrix lane %d differed: SIMD=%v scalar=%v",
				index,
				value,
				expected[index],
			)
		}
	}
}

@(test)
test_simd_frustum_sphere_test_matches_scalar_oracle :: proc(t: ^testing.T) {
	state := u32(0x3c6ef372)
	for _ in 0 ..< 256 {
		projection: Mat4
		for &value in projection {
			value = simd_test_random(&state)
		}
		planes := wgpu_extract_frustum_planes(projection)
		bounds := [4]f32 {
			simd_test_random(&state),
			simd_test_random(&state),
			simd_test_random(&state),
			math.abs(simd_test_random(&state)),
		}
		expected := true
		for plane in planes {
			distance :=
				plane[0] * bounds[0] + plane[1] * bounds[1] + plane[2] * bounds[2] + plane[3]
			if distance < -bounds[3] {
				expected = false
				break
			}
		}
		testing.expect_value(t, wgpu_sphere_visible(bounds, planes), expected)
	}
}
