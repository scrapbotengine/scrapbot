package native

import component "../component"
import ecs "../ecs"
import api "../extension_api"
import resources "../resources"
import schedule "../schedule"
import shared "../shared"
import "core:dynlib"
import "core:fmt"
import "core:strings"

EXTENSIONS_DIR :: shared.PROJECT_EXTENSION_BUILD_DIR
EXTENSIONS_MANIFEST :: ".scrapbot-extensions"
REGISTER_SYMBOL :: "scrapbot_extension_register"
MAX_EXTENSIONS :: 32
MAX_NATIVE_SYSTEMS :: schedule.MAX_SYSTEMS

Extension_Stamp :: struct {
	exists: bool,
	modified_ns: i64,
	size: i64,
}

Source_Stamp :: struct {
	exists: bool,
	modified_ns: i64,
	size: i64,
	entry_count: int,
}

Extension :: struct {
	path: string,
	stamp: Extension_Stamp,
	library: dynlib.Library,
}

Native_System :: struct {
	name: string,
	declaration: schedule.System,
	callback: api.System_Proc,
	userdata: rawptr,
}

Step_Context :: struct {
	world: ^shared.World,
	system: ^Native_System,
	commands: ^ecs.Command_Buffer,
	registry: ^component.Registry,
}

Source_Target :: struct {
	name: string,
	source: string,
	stamp: Source_Stamp,
}

Extension_Set :: struct {
	extensions: [MAX_EXTENSIONS]Extension,
	extension_count: int,
	systems: [MAX_NATIVE_SYSTEMS]Native_System,
	system_count: int,
	registry: ^component.Registry,
	resources: ^resources.Registry,
}

Source_Set :: struct {
	targets: [MAX_EXTENSIONS]Source_Target,
	target_count: int,
}

Load_Result :: struct {
	loaded_count: int,
	err: string,
}

Build_Result :: struct {
	built_count: int,
	err: string,
}


load_project_extensions :: proc(
	set: ^Extension_Set,
	root: string,
	registry: ^component.Registry,
	resource_registry: ^resources.Registry = nil,
) -> Load_Result {
	destroy_extension_set(set)
	set.registry = registry
	set.resources = resource_registry
	defer set.registry = nil

	extension_paths, paths_err := project_extension_paths(root)
	if paths_err != "" {
		return Load_Result{err = paths_err}
	}
	defer destroy_extension_paths(extension_paths)

	for path in extension_paths {
		if set.extension_count >= MAX_EXTENSIONS {
			return Load_Result {
				loaded_count = set.extension_count,
				err = "too many native extensions",
			}
		}
		if err := load_extension(set, path); err != "" {
			return Load_Result{loaded_count = set.extension_count, err = err}
		}
	}

	return Load_Result{loaded_count = set.extension_count}
}

destroy_extension_set :: proc(set: ^Extension_Set) {
	if set == nil {
		return
	}
	for &extension in set.extensions[:set.extension_count] {
		if extension.library != nil {
			dynlib.unload_library(extension.library)
		}
		delete(extension.path)
	}
	set^ = {}
}

project_extensions_changed :: proc(set: ^Extension_Set, root: string) -> bool {
	extension_paths, paths_err := project_extension_paths(root)
	if paths_err != "" {
		return set != nil && set.extension_count > 0
	}
	defer destroy_extension_paths(extension_paths)

	if set == nil {
		return len(extension_paths) > 0
	}
	if len(extension_paths) != set.extension_count {
		return true
	}

	for path, index in extension_paths {
		if set.extensions[index].path != path {
			return true
		}
		if !extension_stamps_equal(set.extensions[index].stamp, extension_stamp(path)) {
			return true
		}
	}
	return false
}

load_extension :: proc(set: ^Extension_Set, path: string) -> string {
	library, ok := dynlib.load_library(path)
	if !ok {
		return fmt.tprintf("failed to load native extension %s: %s", path, dynlib.last_error())
	}

	symbol, found := dynlib.symbol_address(library, REGISTER_SYMBOL)
	if !found {
		dynlib.unload_library(library)
		return fmt.tprintf("native extension %s does not export %s", path, REGISTER_SYMBOL)
	}

	register := cast(api.Register_Proc)symbol
	host_api := api.API {
		userdata = set,
		register_library_component = extension_register_library_component,
		register_system = extension_register_system,
		register_geometry = extension_register_geometry,
		register_material = extension_register_material,
	}
	if register_err := register(&host_api); register_err != nil {
		dynlib.unload_library(library)
		return fmt.tprintf(
			"native extension %s failed to register: %s",
			path,
			string(register_err),
		)
	}

	cloned_path, clone_err := strings.clone(path)
	if clone_err != nil {
		dynlib.unload_library(library)
		return "failed to retain native extension path"
	}

	set.extensions[set.extension_count] = Extension {
		path = cloned_path,
		stamp = extension_stamp(path),
		library = library,
	}
	set.extension_count += 1
	return ""
}

api_transform_from_shared :: proc "c" (transform: shared.Transform_Component) -> api.Transform {
	return api.Transform {
		position = api_vec3_from_shared(transform.position),
		rotation = api_vec3_from_shared(transform.rotation),
		scale = api_vec3_from_shared(transform.scale),
	}
}

shared_transform_from_api :: proc "c" (transform: api.Transform) -> shared.Transform_Component {
	return shared.Transform_Component {
		position = shared_vec3_from_api(transform.position),
		rotation = shared_vec3_from_api(transform.rotation),
		scale = shared_vec3_from_api(transform.scale),
	}
}

api_vec3_from_shared :: proc "c" (value: shared.Vec3) -> api.Vec3 {
	return api.Vec3{x = value.x, y = value.y, z = value.z}
}

shared_vec3_from_api :: proc "c" (value: api.Vec3) -> shared.Vec3 {
	return shared.Vec3{x = value.x, y = value.y, z = value.z}
}
