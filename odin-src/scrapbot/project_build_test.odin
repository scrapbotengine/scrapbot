package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_build_project_creates_host_bundle :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-project-source")
	defer os.remove_all(root)
	defer delete(root)
	output_root := make_test_project_root(t, "build-project-output")
	defer os.remove_all(output_root)
	defer delete(output_root)

	testing.expect_value(t, init_project(root, "Bundle Game"), Project_Error.None)
	extra_path := project_relative_path(root, "assets/data.txt")
	defer delete(extra_path)
	testing.expect_value(t, os.write_entire_file(extra_path, "asset data"), nil)

	result, err := build_project(Build_Options{
		target_path = root,
		output_root = output_root,
		name = "bundle-game",
	})
	defer free_build_result(result)
	testing.expect_value(t, err, Project_Error.None)

	marker_path := join_test_path(t, result.bundle_path, BUILD_BUNDLE_MARKER)
	defer delete(marker_path)
	runtime_path := result.runtime_path
	launcher_path := result.launcher_path
	manifest_path := join_test_path(t, result.bundle_path, BUILD_MANIFEST_PATH)
	defer delete(manifest_path)
	copied_asset_path := join_test_path(t, result.project_path, "assets/data.txt")
	defer delete(copied_asset_path)

	testing.expect_value(t, os.exists(marker_path), true)
	testing.expect_value(t, os.exists(runtime_path), true)
	testing.expect_value(t, os.exists(launcher_path), true)
	testing.expect_value(t, os.exists(manifest_path), true)
	testing.expect_value(t, os.exists(copied_asset_path), true)

	launcher, launcher_read_err := os.read_entire_file(launcher_path, context.allocator)
	testing.expect_value(t, launcher_read_err, nil)
	defer delete(launcher)
	when ODIN_OS == .Windows {
		testing.expect(t, strings.contains(string(launcher), `PATH=%SCRIPT_DIR%lib;%SCRIPT_DIR%bin;%PATH%`))
	} else when ODIN_OS == .Darwin {
		testing.expect(t, strings.contains(string(launcher), "DYLD_LIBRARY_PATH"))
	} else when ODIN_OS == .Linux {
		testing.expect(t, strings.contains(string(launcher), "LD_LIBRARY_PATH"))
	}

	packaged := check_project(result.project_path)
	defer free_check_result(packaged)
	testing.expect_value(t, packaged.err, Project_Error.None)
	testing.expect_value(t, packaged.project.name, "Bundle Game")

	manifest, read_err := os.read_entire_file(manifest_path, context.allocator)
	testing.expect_value(t, read_err, nil)
	defer delete(manifest)
	testing.expect(t, strings.contains(string(manifest), `"schema": "scrapbot.build.v1"`))
	testing.expect(t, strings.contains(string(manifest), `"native_artifact": null`))
	testing.expect(t, strings.contains(string(manifest), `"sdl3_bundled":`))
	if result.sdl3_bundled {
		testing.expect_value(t, result.sdl3_warning, "")
		testing.expect(t, strings.contains(string(manifest), `"sdl3_warning": null`))
	} else {
		testing.expect(t, result.sdl3_warning != "")
		testing.expect(t, strings.contains(string(manifest), `"sdl3_warning": "SDL3 was not copied;`))
	}
}

@(test)
test_build_project_copies_packaged_native_artifact_from_scrapbot_cache :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-native-artifact-source")
	defer os.remove_all(root)
	defer delete(root)
	output_root := make_test_project_root(t, "build-native-artifact-output")
	defer os.remove_all(output_root)
	defer delete(output_root)

	testing.expect_value(t, init_project(root, "Artifact Game"), Project_Error.None)
	artifact_project_path := ".scrapbot/build/native/libscrapbot_project.test"
	artifact_full_path := project_relative_path(root, artifact_project_path)
	defer delete(artifact_full_path)
	artifact_parent := os.dir(artifact_full_path)
	testing.expect_value(t, ensure_directory(artifact_parent), true)
	testing.expect_value(t, os.write_entire_file(artifact_full_path, "native artifact bytes"), nil)
	write_file(t, root, PROJECT_FILE_NAME, "name = \"Artifact Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative_artifact = \".scrapbot/build/native/libscrapbot_project.test\"\n")

	result, err := build_project(Build_Options{
		target_path = root,
		output_root = output_root,
		name = "artifact-game",
	})
	defer free_build_result(result)
	testing.expect_value(t, err, Project_Error.None)
	testing.expect_value(t, result.native_artifact, artifact_project_path)

	packaged_artifact_path := join_test_path(t, result.project_path, artifact_project_path)
	defer delete(packaged_artifact_path)
	manifest_path := join_test_path(t, result.bundle_path, BUILD_MANIFEST_PATH)
	defer delete(manifest_path)

	testing.expect_value(t, os.exists(packaged_artifact_path), true)
	copied_artifact, copied_read_err := os.read_entire_file(packaged_artifact_path, context.allocator)
	testing.expect_value(t, copied_read_err, nil)
	defer delete(copied_artifact)
	testing.expect_value(t, string(copied_artifact), "native artifact bytes")

	packaged := check_project(result.project_path)
	defer free_check_result(packaged)
	testing.expect_value(t, packaged.err, Project_Error.None)
	testing.expect_value(t, packaged.project.native_artifact, artifact_project_path)

	manifest, read_err := os.read_entire_file(manifest_path, context.allocator)
	testing.expect_value(t, read_err, nil)
	defer delete(manifest)
	testing.expect(t, strings.contains(string(manifest), `"native_artifact": ".scrapbot/build/native/libscrapbot_project.test"`))
}

@(test)
test_build_project_copies_discoverable_sdl3_candidate :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-sdl3-candidate")
	defer os.remove_all(root)
	defer delete(root)

	lib_path := join_test_path(t, root, "lib")
	defer delete(lib_path)
	testing.expect_value(t, ensure_directory(lib_path), true)
	candidate_path := join_test_path(t, root, "libSDL3.test")
	defer delete(candidate_path)
	testing.expect_value(t, os.write_entire_file(candidate_path, "sdl3 bytes"), nil)
	copied_path := join_test_path(t, lib_path, "libSDL3.test")
	defer delete(copied_path)
	testing.expect_value(t, os.write_entire_file(copied_path, "old bytes"), nil)

	candidates := [?]string{candidate_path}
	testing.expect_value(t, copy_discoverable_sdl3_from_candidates(lib_path, candidates[:]), true)

	testing.expect_value(t, os.exists(copied_path), true)
	copied, copied_read_err := os.read_entire_file(copied_path, context.allocator)
	testing.expect_value(t, copied_read_err, nil)
	defer delete(copied)
	testing.expect_value(t, string(copied), "sdl3 bytes")

	missing_candidate := join_test_path(t, root, "missing-SDL3.test")
	defer delete(missing_candidate)
	missing_candidates := [?]string{missing_candidate}
	testing.expect_value(t, copy_discoverable_sdl3_from_candidates(lib_path, missing_candidates[:]), false)
}

@(test)
test_build_project_default_output_skips_project_build_tree :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-default-output")
	defer os.remove_all(root)
	defer delete(root)

	testing.expect_value(t, init_project(root, "Default Build"), Project_Error.None)
	generated_root := project_relative_path(root, BUILD_DEFAULT_OUTPUT_DIR)
	defer delete(generated_root)
	testing.expect_value(t, ensure_directory(generated_root), true)
	should_skip := project_relative_path(root, "build/old.txt")
	defer delete(should_skip)
	testing.expect_value(t, os.write_entire_file(should_skip, "old"), nil)

	result, err := build_project(Build_Options{target_path = root, name = "default-build"})
	defer free_build_result(result)
	testing.expect_value(t, err, Project_Error.None)

	copied_build_tree := join_test_path(t, result.project_path, BUILD_DEFAULT_OUTPUT_DIR)
	defer delete(copied_build_tree)
	testing.expect_value(t, os.exists(copied_build_tree), false)
}

@(test)
test_build_project_requires_force_for_existing_bundle :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-existing-source")
	defer os.remove_all(root)
	defer delete(root)
	output_root := make_test_project_root(t, "build-existing-output")
	defer os.remove_all(output_root)
	defer delete(output_root)

	testing.expect_value(t, init_project(root, "Existing Build"), Project_Error.None)

	first, first_err := build_project(Build_Options{target_path = root, output_root = output_root, name = "existing"})
	free_build_result(first)
	testing.expect_value(t, first_err, Project_Error.None)
	second, second_err := build_project(Build_Options{target_path = root, output_root = output_root, name = "existing"})
	free_build_result(second)
	testing.expect_value(t, second_err, Project_Error.Already_Exists)
	third, third_err := build_project(Build_Options{target_path = root, output_root = output_root, name = "existing", force = true})
	defer free_build_result(third)
	testing.expect_value(t, third_err, Project_Error.None)
}

@(test)
test_build_project_rejects_nested_in_project_output_root :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "build-nested-output")
	defer os.remove_all(root)
	defer delete(root)

	testing.expect_value(t, init_project(root, "Nested Output"), Project_Error.None)
	nested_output := project_relative_path(root, "assets/build")
	defer delete(nested_output)

	result, err := build_project(Build_Options{target_path = root, output_root = nested_output, name = "nested"})
	free_build_result(result)
	testing.expect_value(t, err, Project_Error.Invalid_Build_Output)
}

join_test_path :: proc(t: ^testing.T, left, right: string) -> string {
	joined, err := filepath.join([]string{left, right})
	if err != nil {
		testing.fail_now(t, "failed to join path")
	}
	return joined
}
