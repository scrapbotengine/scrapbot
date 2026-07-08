package scrapbot

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import ecs "./ecs"
import project "./project"
import script "./script"
import shared "./shared"

File_Stamp :: struct {
	exists:      bool,
	modified_ns: i64,
	size:        i64,
}

Hot_Reload_State :: struct {
	root:         string,
	scene_path:   string,
	script_path:  string,
	scene_stamp:  File_Stamp,
	script_stamp: File_Stamp,
	runtime:      script.Runtime,
	last_good_script_source: string,
	has_last_good_script:    bool,
}

Script_Load :: struct {
	runtime:    script.Runtime,
	source:     string,
	has_source: bool,
	err:        string,
}

init_hot_reload_state :: proc(
	state: ^Hot_Reload_State,
	root: string,
	loaded: ^project.Project_Load_Result,
	world: ^shared.World,
) -> string {
	state^ = {}
	state.root = root

	scene_path, scene_join_err := filepath.join({root, loaded.config.default_scene})
	if scene_join_err != nil {
		return "failed to allocate scene path"
	}
	state.scene_path = scene_path

	script_path, script_join_err := filepath.join({root, shared.DEFAULT_SCRIPT})
	if script_join_err != nil {
		delete(state.scene_path)
		state.scene_path = ""
		return "failed to allocate script path"
	}
	state.script_path = script_path

	state.scene_stamp = file_stamp(state.scene_path)
	state.script_stamp = file_stamp(state.script_path)

	return load_script_runtime(state, world)
}

destroy_hot_reload_state :: proc(state: ^Hot_Reload_State) {
	script.destroy_runtime(&state.runtime)
	delete(state.last_good_script_source)
	delete(state.scene_path)
	delete(state.script_path)
	state^ = {}
}

hot_reload_frame_system :: proc(data: rawptr, world: ^shared.World, delta_seconds: f32) -> string {
	state := cast(^Hot_Reload_State)data
	if state == nil {
		return ""
	}

	poll_hot_reload(state, world)
	return script.step_runtime(&state.runtime, world, delta_seconds)
}

poll_hot_reload :: proc(state: ^Hot_Reload_State, world: ^shared.World) {
	next_scene_stamp := file_stamp(state.scene_path)
	next_script_stamp := file_stamp(state.script_path)
	scene_changed := !file_stamps_equal(state.scene_stamp, next_scene_stamp)
	script_changed := !file_stamps_equal(state.script_stamp, next_script_stamp)
	if !scene_changed && !script_changed {
		return
	}

	if scene_changed {
		state.scene_stamp = next_scene_stamp
		state.script_stamp = next_script_stamp
		if err := reload_project_world_and_script(state, world); err != "" {
			fmt.eprintf("[hot-reload] failed to reload scene: %s\n", err)
			return
		}
		fmt.eprintf("[hot-reload] reloaded %s and %s\n", state.scene_path, state.script_path)
		return
	}

	state.script_stamp = next_script_stamp
	if err := load_script_runtime(state, world); err != "" {
		fmt.eprintf("[hot-reload] failed to reload script: %s\n", err)
		return
	}
	fmt.eprintf("[hot-reload] reloaded %s\n", state.script_path)
}

reload_project_world_and_script :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	loaded := project.load_project(state.root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}

	next_world := ecs.build_world(&loaded.scene)
	script_load := load_script_from_path(state.script_path, &next_world)
	if script_load.err != "" {
		ecs.destroy_world(&next_world)
		destroy_script_load(&script_load)
		if restore_err := restore_last_good_script_runtime(state, world); restore_err != "" {
			return fmt.tprintf("%s; failed to restore last good script: %s", script_load.err, restore_err)
		}
		return script_load.err
	}

	ecs.destroy_world(world)
	world^ = next_world

	script.destroy_runtime(&state.runtime)
	delete(state.last_good_script_source)
	state.runtime = script_load.runtime
	script.rebind_runtime(&state.runtime)
	state.last_good_script_source = script_load.source
	state.has_last_good_script = script_load.has_source

	state.scene_stamp = file_stamp(state.scene_path)
	state.script_stamp = file_stamp(state.script_path)
	return ""
}

load_script_runtime :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	script_load := load_script_from_path(state.script_path, world)
	if script_load.err != "" {
		destroy_script_load(&script_load)
		if restore_err := restore_last_good_script_runtime(state, world); restore_err != "" {
			return fmt.tprintf("%s; failed to restore last good script: %s", script_load.err, restore_err)
		}
		return script_load.err
	}

	script.destroy_runtime(&state.runtime)
	delete(state.last_good_script_source)
	state.runtime = script_load.runtime
	script.rebind_runtime(&state.runtime)
	state.last_good_script_source = script_load.source
	state.has_last_good_script = script_load.has_source
	return ""
}

load_script_from_path :: proc(path: string, world: ^shared.World) -> Script_Load {
	result: Script_Load
	if !os.exists(path) {
		return result
	}

	source, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", path, read_err)
		return result
	}

	run_result := script.run_source(&result.runtime, string(source), script.DEFAULT_SCRIPT_CHUNK, world)
	if run_result.err != "" {
		result.err = run_result.err
		return result
	}

	cloned_source, clone_err := strings.clone(string(source))
	if clone_err != nil {
		script.destroy_runtime(&result.runtime)
		result.err = "failed to retain last good Luau source"
		return result
	}
	result.source = cloned_source
	result.has_source = true
	return result
}

destroy_script_load :: proc(load: ^Script_Load) {
	script.destroy_runtime(&load.runtime)
	delete(load.source)
	load^ = {}
}

restore_last_good_script_runtime :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	if !state.has_last_good_script {
		return ""
	}

	restored: script.Runtime
	result := script.run_source(&restored, state.last_good_script_source, script.DEFAULT_SCRIPT_CHUNK, world)
	if result.err != "" {
		script.destroy_runtime(&restored)
		return result.err
	}

	script.destroy_runtime(&state.runtime)
	state.runtime = restored
	script.rebind_runtime(&state.runtime)
	return ""
}

file_stamp :: proc(path: string) -> File_Stamp {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return {}
	}
	defer os.file_info_delete(fi, context.temp_allocator)

	return File_Stamp {
		exists      = true,
		modified_ns = time.to_unix_nanoseconds(fi.modification_time),
		size        = fi.size,
	}
}

file_stamps_equal :: proc(a, b: File_Stamp) -> bool {
	return a.exists == b.exists && a.modified_ns == b.modified_ns && a.size == b.size
}
