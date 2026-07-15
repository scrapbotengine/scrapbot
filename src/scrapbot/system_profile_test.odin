package scrapbot

import native "./native"
import render "./render"
import script "./script"
import "core:testing"

@(test)
test_system_profile_publishes_five_frame_updates_over_a_fifty_frame_window :: proc(t: ^testing.T) {
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
	testing.expect(t, profile.snapshot.entry_count == ENGINE_SYSTEM_PROFILE_COUNT + 2)
	testing.expect(t, profile.snapshot.revision == 1)
	for phase in render.Engine_System_Profile_Phase {
		if phase == .Count {
			continue
		}
		entry := &profile.snapshot.entries[int(phase)]
		testing.expect(t, entry.kind == .Engine)
		name := engine_system_profile_name(phase)
		testing.expect(t, string(entry.name[:entry.name_length]) == name)
	}
	odin_index := ENGINE_SYSTEM_PROFILE_COUNT
	luau_index := odin_index + 1
	testing.expect(t, profile.snapshot.entries[odin_index].kind == .Project_Odin)
	testing.expect(t, profile.snapshot.entries[odin_index].name_length == len("Physics"))
	testing.expect(t, profile.snapshot.entries[luau_index].kind == .Luau)
	testing.expect(t, profile.snapshot.entries[luau_index].name_length == len(script_name))
	testing.expect(
		t,
		string(
			profile.snapshot.entries[luau_index].name[:profile.snapshot.entries[luau_index].name_length],
		) ==
		script_name,
	)
	testing.expect(t, profile.snapshot.sample_frames == 0)

	durations: [ENGINE_SYSTEM_PROFILE_COUNT + 2]i64
	durations[int(render.Engine_System_Profile_Phase.UI)] = 500
	durations[odin_index] = 1_000
	durations[luau_index] = 3_000
	for _ in 0 ..< SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES - 1 {
		system_profile_commit_frame(&profile, durations[:])
	}
	testing.expect(t, profile.snapshot.revision == 1)
	testing.expect(t, profile.snapshot.sample_frames == 0)

	system_profile_commit_frame(&profile, durations[:])
	testing.expect(t, profile.snapshot.revision == 2)
	testing.expect(t, profile.snapshot.sample_frames == SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES)
	testing.expect(
		t,
		profile.snapshot.entries[int(render.Engine_System_Profile_Phase.UI)].average_nanoseconds ==
		500,
	)
	testing.expect(t, profile.snapshot.entries[odin_index].average_nanoseconds == 1_000)
	testing.expect(t, profile.snapshot.entries[luau_index].average_nanoseconds == 3_000)
	testing.expect(t, profile.frames_since_publish == 0)

	for _ in SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES ..< SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES {
		system_profile_commit_frame(&profile, durations[:])
	}
	testing.expect(t, profile.snapshot.sample_frames == SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES)
	high_durations := durations
	high_durations[odin_index] = 6_000
	high_durations[luau_index] = 8_000
	for _ in 0 ..< SYSTEM_PROFILE_PUBLISH_INTERVAL_FRAMES {
		system_profile_commit_frame(&profile, high_durations[:])
	}
	testing.expect(t, profile.snapshot.sample_frames == SYSTEM_PROFILE_ROLLING_WINDOW_FRAMES)
	testing.expect(t, profile.snapshot.entries[odin_index].average_nanoseconds == 1_500)
	testing.expect(t, profile.snapshot.entries[luau_index].average_nanoseconds == 3_500)

	native_extensions.systems[0].name = "Movement"
	system_profile_prepare(&profile, &native_extensions, &script_runtime)
	testing.expect(t, profile.snapshot.revision == 13)
	testing.expect(t, profile.snapshot.sample_frames == 0)
	testing.expect(t, profile.sample_count == 0)
	testing.expect(t, profile.frames_since_publish == 0)
}
