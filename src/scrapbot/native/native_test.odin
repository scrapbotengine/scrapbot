package native

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_build_project_extensions_clears_manifest_when_targets_are_removed :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-native-*", context.allocator)
	if !testing.expect(t, temp_err == nil) {
		testing.fail_now(t)
	}
	defer delete(root)
	defer os.remove_all(root)

	extensions_dir, dir_err := project_extensions_dir(root)
	if !testing.expect(t, dir_err == "") {
		testing.fail_now(t)
	}
	defer delete(extensions_dir)

	make_dir_err := os.make_directory_all(extensions_dir)
	if !testing.expect(t, make_dir_err == nil) {
		testing.fail_now(t)
	}

	manifest_path, manifest_path_err := filepath.join({extensions_dir, EXTENSIONS_MANIFEST})
	if !testing.expect(t, manifest_path_err == nil) {
		testing.fail_now(t)
	}
	defer delete(manifest_path)

	write_err := os.write_entire_file(manifest_path, "stale-extension.dylib\n")
	testing.expect(t, write_err == nil)

	result := build_project_extensions(root, nil)
	testing.expectf(t, result.err == "", "build_project_extensions failed: %s", result.err)
	testing.expect(t, result.built_count == 0)

	manifest, read_err := os.read_entire_file(manifest_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	testing.expect(t, string(manifest) == "")

	paths, paths_err := project_extension_paths(root)
	testing.expectf(t, paths_err == "", "project_extension_paths failed: %s", paths_err)
	defer destroy_extension_paths(paths)
	testing.expect(t, len(paths) == 0)
}
