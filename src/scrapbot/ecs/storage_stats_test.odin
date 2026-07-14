package ecs

import "core:testing"

@(test)
test_world_storage_peak_includes_ui_input_slots :: proc(t: ^testing.T) {
	peak := world_storage_stats_max(
		World_Storage_Stats{ui_input_slots = 2},
		World_Storage_Stats{ui_input_slots = 7},
	)
	testing.expect(t, peak.ui_input_slots == 7)
}
