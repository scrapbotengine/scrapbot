package ecs

import "core:math"
import "core:testing"
import shared "../shared"

@(test)
test_time_resource_tracks_delta_elapsed_and_frame_index :: proc(t: ^testing.T) {
	time: shared.Time_Resource
	advance_time(&time, 0.1)
	testing.expect(t, math.abs(time.delta_time - 0.1) < 0.00001)
	testing.expect(t, math.abs(time.smooth_delta_time - 0.1) < 0.00001)
	testing.expect(t, math.abs(time.elapsed_time - 0.1) < 0.00001)
	testing.expect(t, time.frame_index == 1)

	advance_time(&time, 0.2)
	testing.expect(t, time.smooth_delta_time > 0.1 && time.smooth_delta_time < 0.2)
	testing.expect(t, math.abs(time.elapsed_time - 0.3) < 0.00001)
	testing.expect(t, time.frame_index == 2)
}

@(test)
test_time_resource_rejects_negative_delta :: proc(t: ^testing.T) {
	time: shared.Time_Resource
	advance_time(&time, -1)
	testing.expect(t, time.delta_time == 0)
	testing.expect(t, time.elapsed_time == 0)
}
