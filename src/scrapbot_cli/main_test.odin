package main

import "core:testing"

@(test)
test_profile_disabled_features_are_explicit_and_composable :: proc(t: ^testing.T) {
	overrides, ok := parse_profile_disabled_features(
		"ambient-occlusion,screen-space-reflections,bloom",
	)
	testing.expect(t, ok)
	testing.expect(t, overrides.disable_ambient_occlusion)
	testing.expect(t, overrides.disable_screen_space_reflections)
	testing.expect(t, overrides.disable_bloom)
	testing.expect(t, !overrides.disable_temporal_antialiasing)

	_, ok = parse_profile_disabled_features("ambient-occlusion,unicorn-rays")
	testing.expect(t, !ok)
}
