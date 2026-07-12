package render

import "core:testing"
import ecs "../ecs"

@(test)
test_renderer_backend_names_parse :: proc(t: ^testing.T) {
	backend, ok := parse_renderer_backend("null")
	testing.expect(t, ok)
	testing.expect(t, backend == .Null)

	backend, ok = parse_renderer_backend("wgpu-native")
	testing.expect(t, ok)
	testing.expect(t, backend == .WGPU)

	_, ok = parse_renderer_backend("potato")
	testing.expect(t, !ok)
}

@(test)
test_null_renderer_steps_frame_system_for_max_frames :: proc(t: ^testing.T) {
	world: World
	frame_count := 0

	_, err := run_renderer(
		Run_Config {
			backend = .Null,
			max_frames = 5,
			frame_system = test_count_frame_system,
			frame_system_data = &frame_count,
		},
		&world,
	)

	testing.expectf(t, err == "", "run_renderer failed: %s", err)
	testing.expect(t, frame_count == 5)
	testing.expect(t, world.time.frame_index == 5)
	testing.expect(t, world.time.delta_time == f32(1.0 / 60.0))
}

@(test)
test_directional_shadow_matrix_is_finite_and_non_identity :: proc(t: ^testing.T) {
	light_matrix := wgpu_build_directional_light_view_projection({-0.5, -1, -0.25})
	testing.expect(t, light_matrix != mat4_identity())
	for value in light_matrix {
		testing.expect(t, value == value)
	}
}

test_count_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	ecs.advance_time(&world.time, delta_seconds)
	count := cast(^int)data
	count^ += 1
	return ""
}
