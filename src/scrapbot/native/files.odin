package native

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

project_extension_paths :: proc(root: string) -> (paths: []string, err: string) {
	extensions_dir, dir_err := project_extensions_dir(root)
	if dir_err != "" {
		return nil, dir_err
	}
	defer delete(extensions_dir)

	if !os.exists(extensions_dir) {
		return nil, ""
	}

	manifest_paths, manifest_found, manifest_err := project_extension_manifest_paths(extensions_dir)
	if manifest_err != "" {
		return nil, manifest_err
	}
	if manifest_found {
		return manifest_paths, ""
	}

	entries, read_err := os.read_all_directory_by_path(extensions_dir, context.temp_allocator)
	if read_err != nil {
		return nil, fmt.tprintf("failed to read native extension directory: %v", read_err)
	}

	builder: [dynamic]string
	for entry in entries {
		if entry.type != .Regular {
			continue
		}
		if !strings.has_suffix(entry.name, "." + dynlib.LIBRARY_FILE_EXTENSION) {
			continue
		}
		path, path_err := filepath.join({extensions_dir, entry.name})
		if path_err != nil {
			destroy_extension_paths(builder[:])
			return nil, "failed to allocate native extension path"
		}
		append(&builder, path)
	}

	paths = make([]string, len(builder))
	copy(paths, builder[:])
	delete(builder)
	sort_strings(paths)
	return paths, ""
}

write_extensions_manifest :: proc(extensions_dir: string, output_names: []string) -> string {
	manifest_path, path_err := filepath.join({extensions_dir, EXTENSIONS_MANIFEST})
	if path_err != nil {
		return "failed to allocate native extension manifest path"
	}
	defer delete(manifest_path)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for name in output_names {
		strings.write_string(&builder, name)
		strings.write_rune(&builder, '\n')
	}

	if err := os.write_entire_file(manifest_path, strings.to_string(builder)); err != nil {
		return fmt.tprintf("failed to write native extension manifest: %v", err)
	}
	return ""
}

project_extension_manifest_paths :: proc(extensions_dir: string) -> (paths: []string, found: bool, err: string) {
	manifest_path, path_err := filepath.join({extensions_dir, EXTENSIONS_MANIFEST})
	if path_err != nil {
		return nil, false, "failed to allocate native extension manifest path"
	}
	defer delete(manifest_path)

	if !os.exists(manifest_path) {
		return nil, false, ""
	}

	manifest, read_err := os.read_entire_file(manifest_path, context.temp_allocator)
	if read_err != nil {
		return nil, true, fmt.tprintf("failed to read native extension manifest: %v", read_err)
	}

	builder: [dynamic]string
	text := string(manifest)
	for raw_line in strings.split_lines_iterator(&text) {
		name := strings.trim_space(raw_line)
		if name == "" {
			continue
		}
		path, join_err := filepath.join({extensions_dir, name})
		if join_err != nil {
			destroy_extension_paths(builder[:])
			return nil, true, "failed to allocate native extension manifest entry path"
		}
		append(&builder, path)
	}

	paths = make([]string, len(builder))
	copy(paths, builder[:])
	delete(builder)
	return paths, true, ""
}

project_extensions_dir :: proc(root: string) -> (path: string, err: string) {
	out, join_err := filepath.join({root, EXTENSIONS_DIR})
	if join_err != nil {
		return "", "failed to allocate native extension directory path"
	}
	return out, ""
}

destroy_extension_paths :: proc(paths: []string) {
	for path in paths {
		delete(path)
	}
	delete(paths)
}

sort_strings :: proc(values: []string) {
	for i in 1..<len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j - 1] > value {
			values[j] = values[j - 1]
			j -= 1
		}
		values[j] = value
	}
}

extension_stamp :: proc(path: string) -> Extension_Stamp {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return {}
	}
	defer os.file_info_delete(fi, context.temp_allocator)

	return Extension_Stamp {
		exists = true,
		modified_ns = time.to_unix_nanoseconds(fi.modification_time),
		size = fi.size,
	}
}

extension_stamps_equal :: proc(a, b: Extension_Stamp) -> bool {
	return a.exists == b.exists && a.modified_ns == b.modified_ns && a.size == b.size
}

extension_source_stamp :: proc(root, source: string) -> Source_Stamp {
	source_dir, source_err := filepath.join({root, source})
	if source_err != nil {
		return {}
	}
	defer delete(source_dir)

	stamp: Source_Stamp
	accumulate_source_dir_stamp(source_dir, &stamp)
	return stamp
}

extension_host_source_stamp :: proc() -> Source_Stamp {
	stamp: Source_Stamp
	accumulate_source_dir_stamp("src/scrapbot/extension_api", &stamp)
	accumulate_source_dir_stamp("src/scrapbot/extension", &stamp)
	return stamp
}

accumulate_source_dir_stamp :: proc(path: string, stamp: ^Source_Stamp) {
	accumulate_source_path_stamp(path, stamp)

	entries, read_err := os.read_all_directory_by_path(path, context.temp_allocator)
	if read_err != nil {
		return
	}

	for entry in entries {
		child_path, child_err := filepath.join({path, entry.name})
		if child_err != nil {
			continue
		}

		#partial switch entry.type {
		case .Regular:
			accumulate_source_path_stamp(child_path, stamp)
		case .Directory:
			accumulate_source_dir_stamp(child_path, stamp)
		case:
		}
		delete(child_path)
	}
}

accumulate_source_path_stamp :: proc(path: string, stamp: ^Source_Stamp) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return
	}
	defer os.file_info_delete(fi, context.temp_allocator)

	stamp.exists = true
	stamp.entry_count += 1
	stamp.size += fi.size
	modified_ns := time.to_unix_nanoseconds(fi.modification_time)
	if modified_ns > stamp.modified_ns {
		stamp.modified_ns = modified_ns
	}
}

source_stamps_equal :: proc(a, b: Source_Stamp) -> bool {
	return a.exists == b.exists &&
		a.modified_ns == b.modified_ns &&
		a.size == b.size &&
		a.entry_count == b.entry_count
}
