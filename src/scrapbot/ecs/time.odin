package ecs

import "core:math"
import shared "../shared"

MAX_DELTA_TIME :: f32(0.25)
SMOOTH_DELTA_HALF_LIFE :: f32(0.1)

advance_time :: proc(time: ^shared.Time_Resource, unscaled_delta_time: f32) {
	if time == nil {return}
	delta := max(unscaled_delta_time, 0)
	if time.frame_index == 0 {
		time.smooth_delta_time = delta
	} else {
		alpha := 1 - math.exp(-delta * f32(math.LN2) / SMOOTH_DELTA_HALF_LIFE)
		time.smooth_delta_time += (delta - time.smooth_delta_time) * alpha
	}
	time.delta_time = delta
	time.elapsed_time += f64(delta)
	time.frame_index += 1
}
