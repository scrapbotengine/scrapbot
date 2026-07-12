package scrapbot

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import component "./component"
import ecs "./ecs"
import native "./native"
import project "./project"
import schedule "./schedule"
import resources "./resources"
import script "./script"
import shared "./shared"

HOT_RELOAD_CHECK_INTERVAL_SECONDS :: f32(0.25)

File_Stamp :: struct {
	exists:      bool,
	modified_ns: i64,
	size:        i64,
}
Asset_Stamp :: struct {exists: bool, modified_ns: i64, size: i64, entry_count: int}

Hot_Reload_State :: struct {
	root:         string,
	project_path: string,
	scene_path:   string,
	script_path:  string,
	assets_path: string,
	project_stamp: File_Stamp,
	scene_stamp:  File_Stamp,
	script_stamp: File_Stamp,
	assets_stamp: Asset_Stamp,
	runtime:      script.Runtime,
	native_extensions: native.Extension_Set,
	executor:          schedule.Executor,
	resources:         resources.Registry,
	native_sources: native.Source_Set,
	last_good_script_source: string,
	has_last_good_script:    bool,
	seconds_until_next_check: f32,
}

Script_Load :: struct {
	runtime:    script.Runtime,
	native_extensions: native.Extension_Set,
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

	project_path, project_join_err := filepath.join({root, shared.PROJECT_FILE})
	if project_join_err != nil {
		return "failed to allocate project path"
	}
	state.project_path = project_path

	scene_path, scene_join_err := filepath.join({root, loaded.config.default_scene})
	if scene_join_err != nil {
		delete(state.project_path)
		state.project_path = ""
		return "failed to allocate scene path"
	}
	state.scene_path = scene_path

	script_path, script_join_err := filepath.join({root, shared.DEFAULT_SCRIPT})
	if script_join_err != nil {
		delete(state.project_path)
		state.project_path = ""
		delete(state.scene_path)
		state.scene_path = ""
		return "failed to allocate script path"
	}
	state.script_path = script_path
	assets_path, assets_join_err := filepath.join({root,"assets"})
	if assets_join_err != nil {return "failed to allocate assets path"}
	state.assets_path = assets_path

	if source_err := native.sync_project_extension_sources(&state.native_sources, root, loaded.config.native_extensions[:]); source_err != "" {
		delete(state.project_path)
		delete(state.scene_path)
		delete(state.script_path)
		state.project_path = ""
		state.scene_path = ""
		state.script_path = ""
		return source_err
	}

	state.project_stamp = file_stamp(state.project_path)
	state.scene_stamp = file_stamp(state.scene_path)
	state.script_stamp = file_stamp(state.script_path)
	state.assets_stamp = asset_stamp(state.assets_path)
	state.seconds_until_next_check = HOT_RELOAD_CHECK_INTERVAL_SECONDS

	if err := init_render_resources(&state.resources, world); err != "" {return err}
	return load_script_runtime(state, world)
}

destroy_hot_reload_state :: proc(state: ^Hot_Reload_State) {
	script.destroy_runtime(&state.runtime)
	native.destroy_extension_set(&state.native_extensions)
	schedule.destroy_executor(&state.executor)
	resources.destroy_registry(&state.resources)
	native.destroy_source_set(&state.native_sources)
	delete(state.last_good_script_source)
	delete(state.project_path)
	delete(state.scene_path)
	delete(state.script_path)
	delete(state.assets_path)
	state^ = {}
}

hot_reload_frame_system :: proc(data: rawptr, world: ^shared.World, delta_seconds: f32) -> string {
	state := cast(^Hot_Reload_State)data
	if state == nil {
		return ""
	}
	ecs.advance_time(&world.time, delta_seconds)

	maybe_poll_hot_reload(state, world, delta_seconds)
	return step_frame_runtime_parts(&state.runtime, &state.native_extensions, &state.executor, world, world.time)
}

maybe_poll_hot_reload :: proc(state: ^Hot_Reload_State, world: ^shared.World, delta_seconds: f32) {
	state.seconds_until_next_check -= delta_seconds
	if state.seconds_until_next_check > 0 {
		return
	}
	state.seconds_until_next_check = HOT_RELOAD_CHECK_INTERVAL_SECONDS
	poll_hot_reload(state, world)
}

poll_hot_reload :: proc(state: ^Hot_Reload_State, world: ^shared.World) {
	next_project_stamp := file_stamp(state.project_path)
	next_scene_stamp := file_stamp(state.scene_path)
	next_script_stamp := file_stamp(state.script_path)
	next_assets_stamp := asset_stamp(state.assets_path)
	project_changed := !file_stamps_equal(state.project_stamp, next_project_stamp)
	scene_changed := !file_stamps_equal(state.scene_stamp, next_scene_stamp)
	script_changed := !file_stamps_equal(state.script_stamp, next_script_stamp)
	assets_changed := !asset_stamps_equal(state.assets_stamp,next_assets_stamp)
	extensions_changed := native.project_extensions_changed(&state.native_extensions, state.root)
	sources_changed := native.project_extension_sources_changed(&state.native_sources, state.root)
	if !project_changed && !scene_changed && !script_changed && !assets_changed && !extensions_changed && !sources_changed {
		return
	}

	if project_changed || scene_changed || assets_changed || extensions_changed || sources_changed {
		if err := reload_project_world_and_script(state, world); err != "" {
			fmt.eprintf("[hot-reload] failed to reload project: %s\n", err)
			return
		}
		fmt.eprintf("[hot-reload] reloaded %s, %s, %s, assets, and native extensions\n", state.project_path, state.scene_path, state.script_path)
		return
	}

	if err := load_script_runtime(state, world); err != "" {
		fmt.eprintf("[hot-reload] failed to reload script: %s\n", err)
		return
	}
	state.script_stamp = next_script_stamp
	fmt.eprintf("[hot-reload] reloaded %s\n", state.script_path)
}

reload_project_world_and_script :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	loaded := project.load_project(state.root)
	defer project.destroy_project_load_result(&loaded)
	if loaded.err != "" {
		return loaded.err
	}
	if err := build_native_extensions(state.root, &loaded.config); err != "" {
		return err
	}

	next_world := ecs.build_world(&loaded.scene)
	script_load := load_script_from_path(state.root, state.script_path, &next_world, &state.resources)
	if script_load.err != "" {
		reload_err := script_load.err
		ecs.destroy_world(&next_world)
		destroy_script_load(&script_load)
		if restore_err := restore_last_good_script_runtime(state, world); restore_err != "" {
			return fmt.tprintf("%s; failed to restore last good script: %s", reload_err, restore_err)
		}
		return reload_err
	}

	next_sources: native.Source_Set
	if source_err := native.sync_project_extension_sources(&next_sources, state.root, loaded.config.native_extensions[:]); source_err != "" {
		ecs.destroy_world(&next_world)
		destroy_script_load(&script_load)
		return source_err
	}

	ecs.destroy_world(world)
	world^ = next_world

	script.destroy_runtime(&state.runtime)
	native.destroy_extension_set(&state.native_extensions)
	native.destroy_source_set(&state.native_sources)
	delete(state.last_good_script_source)
	state.runtime = script_load.runtime
	state.native_extensions = script_load.native_extensions
	state.native_sources = next_sources
	script.rebind_runtime(&state.runtime)
	state.last_good_script_source = script_load.source
	state.has_last_good_script = script_load.has_source

	state.project_stamp = file_stamp(state.project_path)
	state.scene_stamp = file_stamp(state.scene_path)
	state.script_stamp = file_stamp(state.script_path)
	state.assets_stamp = asset_stamp(state.assets_path)
	return ""
}

load_script_runtime :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	script_load := load_script_from_path(state.root, state.script_path, world, &state.resources)
	if script_load.err != "" {
		reload_err := script_load.err
		destroy_script_load(&script_load)
		if restore_err := restore_last_good_script_runtime(state, world); restore_err != "" {
			return fmt.tprintf("%s; failed to restore last good script: %s", reload_err, restore_err)
		}
		return reload_err
	}

	script.destroy_runtime(&state.runtime)
	native.destroy_extension_set(&state.native_extensions)
	delete(state.last_good_script_source)
	state.runtime = script_load.runtime
	state.native_extensions = script_load.native_extensions
	script.rebind_runtime(&state.runtime)
	state.last_good_script_source = script_load.source
	state.has_last_good_script = script_load.has_source
	return ""
}

load_script_from_path :: proc(root, path: string, world: ^shared.World, resource_registry: ^resources.Registry) -> Script_Load {
	result: Script_Load
	registry: component.Registry
	component.init_registry(&registry)
	if extension_load := native.load_project_extensions(&result.native_extensions, root, &registry, resource_registry); extension_load.err != "" {
		result.err = extension_load.err
		return result
	}

	if !os.exists(path) {
		return result
	}

	source, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", path, read_err)
		return result
	}

	run_result := script.run_source_with_registry(
		&result.runtime,
		string(source),
		script.DEFAULT_SCRIPT_CHUNK,
		world,
		&registry,
		script.Source_Options{log_enabled = true, resource_registry = resource_registry, project_root = root},
	)
	if run_result.err != "" {
		result.err = run_result.err
		native.destroy_extension_set(&result.native_extensions)
		return result
	}

	cloned_source, clone_err := strings.clone(string(source))
	if clone_err != nil {
		script.destroy_runtime(&result.runtime)
		native.destroy_extension_set(&result.native_extensions)
		result.err = "failed to retain last good Luau source"
		return result
	}
	result.source = cloned_source
	result.has_source = true
	return result
}

destroy_script_load :: proc(load: ^Script_Load) {
	script.destroy_runtime(&load.runtime)
	native.destroy_extension_set(&load.native_extensions)
	delete(load.source)
	load^ = {}
}

restore_last_good_script_runtime :: proc(state: ^Hot_Reload_State, world: ^shared.World) -> string {
	if !state.has_last_good_script {
		return ""
	}

	script_load := load_script_from_source(state.root, state.last_good_script_source, world, &state.resources)
	if script_load.err != "" {
		destroy_script_load(&script_load)
		return script_load.err
	}

	script.destroy_runtime(&state.runtime)
	native.destroy_extension_set(&state.native_extensions)
	state.runtime = script_load.runtime
	state.native_extensions = script_load.native_extensions
	script.rebind_runtime(&state.runtime)
	return ""
}

load_script_from_source :: proc(root, source: string, world: ^shared.World, resource_registry: ^resources.Registry) -> Script_Load {
	result: Script_Load
	registry: component.Registry
	component.init_registry(&registry)
	if extension_load := native.load_project_extensions(&result.native_extensions, root, &registry, resource_registry); extension_load.err != "" {
		result.err = extension_load.err
		return result
	}

	run_result := script.run_source_with_registry(
		&result.runtime,
		source,
		script.DEFAULT_SCRIPT_CHUNK,
		world,
		&registry,
		script.Source_Options{log_enabled = true, resource_registry = resource_registry, project_root = root},
	)
	if run_result.err != "" {
		result.err = run_result.err
		native.destroy_extension_set(&result.native_extensions)
		return result
	}

	return result
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

asset_stamp :: proc(path: string) -> Asset_Stamp {stamp: Asset_Stamp; accumulate_asset_stamp(path,&stamp); return stamp}
accumulate_asset_stamp :: proc(path: string, stamp: ^Asset_Stamp) {
	fi, err := os.stat(path,context.temp_allocator); if err != nil {return}; defer os.file_info_delete(fi,context.temp_allocator)
	stamp.exists=true; stamp.entry_count+=1; stamp.size+=fi.size
	modified := time.to_unix_nanoseconds(fi.modification_time); if modified>stamp.modified_ns {stamp.modified_ns=modified}
	if fi.type != .Directory {return}
	entries, read_err := os.read_all_directory_by_path(path,context.temp_allocator); if read_err != nil {return}; defer os.file_info_slice_delete(entries,context.temp_allocator)
	for entry in entries {child, join_err := filepath.join({path,entry.name}); if join_err != nil {continue}; accumulate_asset_stamp(child,stamp); delete(child)}
}
asset_stamps_equal :: proc(a,b: Asset_Stamp) -> bool {return a==b}
