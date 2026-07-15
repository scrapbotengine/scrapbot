package scrapbot

import native "./native"
import script "./script"
import "core:testing"

@(test)
test_system_profile_publishes_ten_frame_averages :: proc(t: ^testing.T) {
	native_extensions: native.Extension_Set
	native_extensions.system_count = 1
	native_extensions.systems[0].name = "Physics"
	script_runtime: script.Runtime
	script_runtime.system_count = 1
	script_name := "Orbit Lights"
	script_runtime.systems[0].name_length = len(script_name)
	for index in 0 ..< len(script_name) {
		script_runtime.systems[0].name[index] = script_name[index]
	}
	profile: System_Profile_Accumulator

	system_profile_prepare(&profile, &native_extensions, &script_runtime)
	testing.expect(t, profile.snapshot.entry_count == 2)
	testing.expect(t, profile.snapshot.revision == 1)
	testing.expect(t, profile.snapshot.entries[0].kind == .Native)
	testing.expect(t, profile.snapshot.entries[0].name_length == len("Physics"))
	testing.expect(t, profile.snapshot.entries[1].kind == .Luau)
	testing.expect(t, profile.snapshot.entries[1].name_length == len(script_name))
	testing.expect(
		t,
		string(profile.snapshot.entries[1].name[:profile.snapshot.entries[1].name_length]) ==
		script_name,
	)
	testing.expect(t, profile.snapshot.sample_frames == 0)

	durations := [2]i64{1_000, 3_000}
	for _ in 0 ..< SYSTEM_PROFILE_WINDOW_FRAMES - 1 {
		system_profile_commit_frame(&profile, durations[:])
	}
	testing.expect(t, profile.snapshot.revision == 1)
	testing.expect(t, profile.snapshot.sample_frames == 0)

	system_profile_commit_frame(&profile, durations[:])
	testing.expect(t, profile.snapshot.revision == 2)
	testing.expect(t, profile.snapshot.sample_frames == SYSTEM_PROFILE_WINDOW_FRAMES)
	testing.expect(t, profile.snapshot.entries[0].average_nanoseconds == 1_000)
	testing.expect(t, profile.snapshot.entries[1].average_nanoseconds == 3_000)
	testing.expect(t, profile.window_frames == 0)

	native_extensions.systems[0].name = "Movement"
	system_profile_prepare(&profile, &native_extensions, &script_runtime)
	testing.expect(t, profile.snapshot.revision == 3)
	testing.expect(t, profile.snapshot.sample_frames == 0)
	testing.expect(t, profile.window_frames == 0)
}
