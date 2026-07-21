package scrapbot

import project "./project"
import shared "./shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

PACKAGE_MARKER :: ".scrapbot-package"

Package_Config :: struct {
	target: string,
}

Package_Result :: struct {
	target: string,
	output_directory: string,
	executable: string,
	err: string,
}

destroy_package_result :: proc(result: ^Package_Result) {
	if result == nil { return }
	delete(result.target)
	delete(result.output_directory)
	delete(result.executable)
	delete(result.err)
	result^ = {}
}

host_target :: proc() -> string {
	when ODIN_OS == .Darwin {
		when ODIN_ARCH == .arm64 { return "darwin_arm64" } else when ODIN_ARCH == .amd64 { return "darwin_amd64" }
	} else when ODIN_OS == .Linux {
		when ODIN_ARCH == .arm64 { return "linux_arm64" } else when ODIN_ARCH == .amd64 { return "linux_amd64" }
	} else when ODIN_OS == .Windows {
		when ODIN_ARCH == .arm64 { return "windows_arm64" } else when ODIN_ARCH == .amd64 { return "windows_amd64" }
	}
	return "unknown"
}

package_project :: proc(root: string, config: Package_Config) -> Package_Result {
	result: Package_Result
	target := config.target
	if target == "" || target == "host" { target = host_target() }
	result.target = clone_package_string(target)
	if target != host_target() {
		result.err = clone_package_string(
			fmt.tprintf(
				"target %s is not available from this host; Scrapbot currently packages host-native builds only (%s)",
				target,
				host_target(),
			),
		)
		return result
	}

	loaded := project.load_project_config(root)
	defer project.destroy_project_config_load_result(&loaded)
	if loaded.err != "" {
		result.err = clone_package_string(loaded.err)
		return result
	}
	if err := project.prepare_project_fonts(root, &loaded.config); err != "" {
		result.err = clone_package_string(err)
		return result
	}
	if err := build_native_extensions(root, &loaded.config, .Release); err != "" {
		result.err = clone_package_string(err)
		return result
	}

	output_dir, join_err := filepath.join({root, "build", target})
	if join_err != nil {
		result.err = clone_package_string("failed to allocate package output path")
		return result
	}
	result.output_directory = output_dir
	if os.exists(output_dir) {
		if err := os.remove_all(output_dir); err != nil {
			result.err = clone_package_string(
				fmt.tprintf("failed to clean package output: %v", err),
			)
			return result
		}
	}
	if err := os.make_directory_all(output_dir); err != nil {
		result.err = clone_package_string(fmt.tprintf("failed to create package output: %v", err))
		return result
	}

	if err := copy_project_payload(root, output_dir); err != "" {
		result.err = clone_package_string(err)
		return result
	}

	executable_source, exe_err := os.get_executable_path(context.allocator)
	if exe_err != nil {
		result.err = clone_package_string(
			fmt.tprintf("failed to locate Scrapbot executable: %v", exe_err),
		)
		return result
	}
	defer delete(executable_source)
	executable_name := package_executable_name(loaded.config.name)
	defer delete(executable_name)
	executable_path, executable_join_err := filepath.join({output_dir, executable_name})
	if executable_join_err != nil {
		result.err = clone_package_string("failed to allocate packaged executable path")
		return result
	}
	result.executable = executable_path
	if err := os.copy_file(executable_path, executable_source); err != nil {
		result.err = clone_package_string(
			fmt.tprintf("failed to copy packaged executable: %v", err),
		)
		return result
	}

	marker_path, marker_err := filepath.join({output_dir, PACKAGE_MARKER})
	if marker_err != nil {
		result.err = clone_package_string("failed to allocate package marker path")
		return result
	}
	defer delete(marker_path)
	if err := os.write_entire_file(
		marker_path,
		fmt.tprintf("schema_version=1\ntarget=%s\n", target),
	); err != nil {
		result.err = clone_package_string(fmt.tprintf("failed to write package marker: %v", err))
	}
	return result
}

copy_project_payload :: proc(root, output_dir: string) -> string {
	entries, read_err := os.read_all_directory_by_path(root, context.allocator)
	if read_err != nil { return fmt.tprintf("failed to read project directory: %v", read_err) }
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		if entry.name == "build" ||
		   entry.name == "native" ||
		   entry.name == shared.PROJECT_STATE_DIR ||
		   entry.name == ".git" ||
		   entry.name == ".gitignore" ||
		   entry.name == ".vscode" { continue }
		dst, join_err := filepath.join({output_dir, entry.name})
		if join_err != nil { return "failed to allocate package payload path" }
		err := copy_package_entry(entry.fullpath, dst, entry.type)
		delete(dst)
		if err != "" { return err }
	}

	extensions_src, src_err := filepath.join({root, shared.PROJECT_EXTENSION_BUILD_DIR})
	if src_err != nil { return "failed to allocate extension source path" }
	defer delete(extensions_src)
	if os.exists(extensions_src) {
		extensions_dst, dst_err := filepath.join({output_dir, shared.PROJECT_EXTENSION_BUILD_DIR})
		if dst_err != nil { return "failed to allocate packaged extension path" }
		defer delete(extensions_dst)
		if err := copy_active_extensions(extensions_src, extensions_dst); err != "" { return err }
	}
	fonts_src, fonts_src_err := filepath.join({root, shared.PROJECT_FONT_BUILD_DIR})
	if fonts_src_err != nil { return "failed to allocate font artifact source path" }
	defer delete(fonts_src)
	if os.exists(fonts_src) {
		fonts_dst, fonts_dst_err := filepath.join({output_dir, shared.PROJECT_FONT_BUILD_DIR})
		if fonts_dst_err != nil { return "failed to allocate packaged font artifact path" }
		defer delete(fonts_dst)
		if err := copy_package_entry(fonts_src, fonts_dst, .Directory); err != "" { return err }
	}
	return ""
}

copy_active_extensions :: proc(src, dst: string) -> string {
	if err := os.make_directory_all(dst);
	   err != nil { return fmt.tprintf("failed to create packaged extension directory: %v", err) }
	manifest_src, src_err := filepath.join({src, ".scrapbot-extensions"})
	if src_err != nil { return "failed to allocate extension manifest source path" }
	defer delete(manifest_src)
	if !os.exists(
		manifest_src,
	) { return "native extension build did not produce an active extension manifest" }
	manifest, read_err := os.read_entire_file(manifest_src, context.temp_allocator)
	if read_err !=
	   nil { return fmt.tprintf("failed to read active extension manifest: %v", read_err) }
	manifest_dst, dst_err := filepath.join({dst, ".scrapbot-extensions"})
	if dst_err != nil { return "failed to allocate packaged extension manifest path" }
	defer delete(manifest_dst)
	if err := os.copy_file(manifest_dst, manifest_src);
	   err != nil { return fmt.tprintf("failed to copy active extension manifest: %v", err) }
	manifest_text := string(manifest)
	for line in strings.split_lines_iterator(&manifest_text) {
		name := strings.trim_space(line)
		if name == "" { continue }
		file_src, file_src_err := filepath.join({src, name})
		if file_src_err != nil { return "failed to allocate active extension source path" }
		file_dst, file_dst_err := filepath.join({dst, name})
		if file_dst_err !=
		   nil { delete(file_src); return "failed to allocate active extension destination path" }
		copy_err := os.copy_file(file_dst, file_src)
		delete(file_src)
		delete(file_dst)
		if copy_err !=
		   nil { return fmt.tprintf("failed to copy active native extension: %v", copy_err) }
	}
	return ""
}

copy_package_entry :: proc(src, dst: string, entry_type: os.File_Type) -> string {
	#partial switch entry_type {
		case .Directory:
			if err := os.make_directory_all(dst);
			   err != nil { return fmt.tprintf("failed to create package directory: %v", err) }
			entries, read_err := os.read_all_directory_by_path(src, context.allocator)
			if read_err !=
			   nil { return fmt.tprintf("failed to read package source directory: %v", read_err) }
			defer os.file_info_slice_delete(entries, context.allocator)
			for entry in entries {
				child_dst, join_err := filepath.join({dst, entry.name})
				if join_err != nil { return "failed to allocate package entry path" }
				err := copy_package_entry(entry.fullpath, child_dst, entry.type)
				delete(child_dst)
				if err != "" { return err }
			}
		case .Regular:
			if err := os.copy_file(dst, src);
			   err != nil { return fmt.tprintf("failed to copy package file: %v", err) }
		case:
			return fmt.tprintf("unsupported package entry type: %s", src)
	}
	return ""
}

package_executable_name :: proc(name: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	last_was_dash := false
	for rune in name {
		if rune >= 'a' && rune <= 'z' ||
		   rune >= '0' &&
			   rune <=
				   '9' { strings.write_rune(&builder, rune); last_was_dash = false } else if rune >= 'A' && rune <= 'Z' { strings.write_rune(&builder, rune + ('a' - 'A')); last_was_dash = false } else if strings.builder_len(builder) > 0 && !last_was_dash { strings.write_rune(&builder, '-'); last_was_dash = true }
	}
	value := strings.trim_right(strings.to_string(builder), "-")
	if value == "" { value = "scrapbot-game" }
	when ODIN_OS == .Windows {
		executable, err := strings.concatenate({value, ".exe"})
		if err != nil { return "" }
		return executable
	}
	return clone_package_string(value)
}

clone_package_string :: proc(value: string) -> string {
	cloned, err := strings.clone(value)
	if err != nil { return "" }
	return cloned
}
