package native

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import shared "../shared"

build_project_extensions :: proc(root: string, targets: []shared.Native_Extension_Target) -> Build_Result {
	result: Build_Result
	extensions_dir, dir_err := project_extensions_dir(root)
	if dir_err != "" {
		result.err = dir_err
		return result
	}
	defer delete(extensions_dir)

	if len(targets) == 0 {
		if os.exists(extensions_dir) {
			if err := write_extensions_manifest(extensions_dir, nil); err != "" {
				result.err = err
			}
		}
		return result
	}

	if !os.exists(extensions_dir) {
		if err := os.make_directory_all(extensions_dir); err != nil {
			result.err = fmt.tprintf("failed to create native extension output directory: %v", err)
			return result
		}
	}

	output_names: [dynamic]string
	defer {
		for name in output_names {
			delete(name)
		}
		delete(output_names)
	}

	for target in targets {
		output_name, err := build_extension(root, extensions_dir, target)
		if err != "" {
			result.err = err
			return result
		}
		append(&output_names, output_name)
		result.built_count += 1
	}

	if err := write_extensions_manifest(extensions_dir, output_names[:]); err != "" {
		result.err = err
		return result
	}

	return result
}

sync_project_extension_sources :: proc(
	set: ^Source_Set,
	root: string,
	targets: []shared.Native_Extension_Target,
) -> string {
	destroy_source_set(set)
	if len(targets) > MAX_EXTENSIONS {
		return "too many native extension source targets"
	}

	for target in targets {
		cloned_name, name_err := strings.clone(target.name)
		if name_err != nil {
			destroy_source_set(set)
			return "failed to retain native extension source target name"
		}

		cloned_source, source_err := strings.clone(target.source)
		if source_err != nil {
			delete(cloned_name)
			destroy_source_set(set)
			return "failed to retain native extension source target path"
		}

		set.targets[set.target_count] = Source_Target {
			name = cloned_name,
			source = cloned_source,
			stamp = extension_source_stamp(root, target.source),
		}
		set.target_count += 1
	}

	return ""
}

destroy_source_set :: proc(set: ^Source_Set) {
	if set == nil {
		return
	}
	for &target in set.targets[:set.target_count] {
		delete(target.name)
		delete(target.source)
	}
	set^ = {}
}

project_extension_sources_changed :: proc(set: ^Source_Set, root: string) -> bool {
	if set == nil {
		return false
	}
	for target in set.targets[:set.target_count] {
		if !source_stamps_equal(target.stamp, extension_source_stamp(root, target.source)) {
			return true
		}
	}
	return false
}

build_extension :: proc(root, extensions_dir: string, target: shared.Native_Extension_Target) -> (output_name: string, err: string) {
	source_dir, source_err := filepath.join({root, target.source})
	if source_err != nil {
		return "", fmt.tprintf("failed to allocate native extension source path for %s", target.name)
	}
	defer delete(source_dir)

	if !os.exists(source_dir) {
		return "", fmt.tprintf("native extension %s source does not exist: %s", target.name, target.source)
	}

	source_stamp := extension_source_stamp(root, target.source)
	host_stamp := extension_host_source_stamp()
	temp_output_name := fmt.tprintf(
		"%s-%d-%d-%d-%d-%d-%d.%s",
		target.name,
		source_stamp.modified_ns,
		source_stamp.size,
		source_stamp.entry_count,
		host_stamp.modified_ns,
		host_stamp.size,
		host_stamp.entry_count,
		dynlib.LIBRARY_FILE_EXTENSION,
	)
	cloned_output_name, clone_err := strings.clone(temp_output_name)
	if clone_err != nil {
		return "", "failed to retain native extension output name"
	}
	output_name = cloned_output_name
	output_path, output_err := filepath.join({extensions_dir, output_name})
	if output_err != nil {
		delete(output_name)
		return "", fmt.tprintf("failed to allocate native extension output path for %s", target.name)
	}
	defer delete(output_path)

	out_arg := fmt.tprintf("-out:%s", output_path)
	command := []string {
		"odin",
		"build",
		source_dir,
		"-build-mode:shared",
		out_arg,
		"-collection:scrapbot=src/scrapbot",
	}
	state, stdout, stderr, exec_err := os.process_exec(os.Process_Desc{command = command}, context.allocator)
	if len(stdout) > 0 {
		defer delete(stdout)
	}
	if len(stderr) > 0 {
		defer delete(stderr)
	}
	if exec_err != nil {
		delete(output_name)
		return "", fmt.tprintf("failed to build native extension %s: %v", target.name, exec_err)
	}
	if !state.success {
		output := strings.trim_space(string(stderr))
		if output == "" {
			output = strings.trim_space(string(stdout))
		}
		if output == "" {
			delete(output_name)
			return "", fmt.tprintf("failed to build native extension %s: odin exited with code %d", target.name, state.exit_code)
		}
		delete(output_name)
		return "", fmt.tprintf("failed to build native extension %s:\n%s", target.name, output)
	}
	return output_name, ""
}
