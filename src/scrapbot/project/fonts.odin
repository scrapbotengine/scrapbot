package project

import shared "../shared"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "core:strings"

PROJECT_FONT_COMPILER_SCHEMA :: "scrapbot-font-v1-msdf-atlas-gen-1.4-mtsdf-512-48-8-ascii"

prepare_project_fonts :: proc(root: string, config: ^Project_Config) -> string {
	if config == nil || len(config.fonts) == 0 { return "" }
	build_dir, join_err := filepath.join({root, shared.PROJECT_FONT_BUILD_DIR})
	if join_err != nil { return "failed to allocate project font build path" }
	defer delete(build_dir)
	if !os.exists(build_dir) {
		if err := os.make_directory_all(build_dir); err != nil {
			return fmt.tprintf("failed to create project font build directory: %v", err)
		}
	}
	for font in config.fonts {
		if err := prepare_project_font(root, build_dir, font); err != "" { return err }
	}
	return ""
}

prepare_project_font :: proc(root, build_dir: string, font: shared.Project_Font) -> string {
	source_path, source_join_err := filepath.join({root, font.source})
	if source_join_err !=
	   nil { return fmt.tprintf("failed to allocate source path for font '%s'", font.name) }
	defer delete(source_path)
	source, read_err := os.read_entire_file(source_path, context.temp_allocator)
	if read_err != nil {
		return fmt.tprintf(
			"failed to read font '%s' from %s: %v",
			font.name,
			font.source,
			read_err,
		)
	}
	if len(source) == 0 { return fmt.tprintf("font '%s' source is empty", font.name) }

	atlas_path, json_path, meta_path, paths_err := project_font_artifact_paths(
		build_dir,
		font.name,
	)
	if paths_err != "" { return paths_err }
	defer delete(atlas_path)
	defer delete(json_path)
	defer delete(meta_path)

	hash_value := hash.fnv64a(source)
	hash_value = hash.fnv64a(transmute([]byte)(string(PROJECT_FONT_COMPILER_SCHEMA)), hash_value)
	expected_meta := fmt.tprintf(
		"schema=%s\nhash=%016x\n",
		PROJECT_FONT_COMPILER_SCHEMA,
		hash_value,
	)
	if project_font_cache_matches(atlas_path, json_path, meta_path, expected_meta) { return "" }

	compiler := os.get_env("SCRAPBOT_MSDF_ATLAS_GEN", context.temp_allocator)
	if compiler == "" { compiler = "msdf-atlas-gen" }
	command := []string {
		compiler,
		"-font",
		source_path,
		"-type",
		"mtsdf",
		"-format",
		"bin",
		"-dimensions",
		"512",
		"512",
		"-size",
		"48",
		"-pxrange",
		"8",
		"-yorigin",
		"top",
		"-imageout",
		atlas_path,
		"-json",
		json_path,
	}
	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	if len(stdout) > 0 { defer delete(stdout) }
	if len(stderr) > 0 { defer delete(stderr) }
	if exec_err != nil {
		return fmt.tprintf(
			"font '%s' needs atlas generation, but msdf-atlas-gen 1.4 is unavailable; install it or set SCRAPBOT_MSDF_ATLAS_GEN",
			font.name,
		)
	}
	if !state.success {
		output := strings.trim_space(string(stderr))
		if output == "" { output = strings.trim_space(string(stdout)) }
		if output == "" { output = fmt.tprintf("exit code %d", state.exit_code) }
		return fmt.tprintf("failed to generate atlas for font '%s': %s", font.name, output)
	}
	if !os.exists(atlas_path) || !os.exists(json_path) {
		return fmt.tprintf("font compiler did not produce complete artifacts for '%s'", font.name)
	}
	if err := os.write_entire_file(meta_path, expected_meta); err != nil {
		return fmt.tprintf("failed to write font cache metadata for '%s': %v", font.name, err)
	}
	return ""
}

project_font_cache_matches :: proc(
	atlas_path, json_path, meta_path, expected_meta: string,
) -> bool {
	if !os.exists(atlas_path) || !os.exists(json_path) || !os.exists(meta_path) { return false }
	atlas_info, atlas_err := os.stat(atlas_path, context.temp_allocator)
	json_info, json_err := os.stat(json_path, context.temp_allocator)
	if atlas_err != nil ||
	   json_err != nil ||
	   atlas_info.size != shared.FONT_ATLAS_SIZE * shared.FONT_ATLAS_SIZE * 4 ||
	   json_info.size <= 0 {
		return false
	}
	metadata, read_err := os.read_entire_file(meta_path, context.temp_allocator)
	return read_err == nil && string(metadata) == expected_meta
}

project_font_artifact_paths :: proc(
	build_dir, name: string,
) -> (
	atlas_path, json_path, meta_path, err: string,
) {
	atlas_name := fmt.tprintf("%s.mtsdf.bin", name)
	json_name := fmt.tprintf("%s.mtsdf.json", name)
	meta_name := fmt.tprintf("%s.mtsdf.meta", name)
	resolved_atlas_path, atlas_err := filepath.join({build_dir, atlas_name})
	if atlas_err != nil { return "", "", "", "failed to allocate font atlas path" }
	resolved_json_path, json_err := filepath.join({build_dir, json_name})
	if json_err != nil {
		delete(resolved_atlas_path)
		return "", "", "", "failed to allocate font metrics path"
	}
	resolved_meta_path, meta_err := filepath.join({build_dir, meta_name})
	if meta_err != nil {
		delete(resolved_atlas_path)
		delete(resolved_json_path)
		return "", "", "", "failed to allocate font metadata path"
	}
	return resolved_atlas_path, resolved_json_path, resolved_meta_path, ""
}
