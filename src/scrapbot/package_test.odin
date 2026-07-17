package scrapbot

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_package_project_rejects_non_host_target :: proc(t: ^testing.T) {
	target := "linux_amd64"
	if host_target() == target {
		target = "darwin_arm64"
	}
	result := package_project(".", Package_Config{target = target})
	defer destroy_package_result(&result)
	testing.expect(t, result.err != "")
}

@(test)
test_package_project_writes_runnable_layout :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "scrapbot-package-*", context.temp_allocator)
	testing.expectf(t, temp_err == nil, "failed to create temp directory: %v", temp_err)
	if temp_err != nil {
		return
	}
	defer os.remove_all(temp_dir)
	root, join_err := filepath.join({temp_dir, "game"}, context.temp_allocator)
	testing.expectf(t, join_err == nil, "failed to allocate project path: %v", join_err)
	if join_err != nil {
		return
	}
	if err := init_project(root, "Package Fixture"); err != "" {
		testing.expectf(t, false, "failed to initialize project: %s", err)
		return
	}
	asset_dir, asset_dir_err := filepath.join({root, "assets"}, context.temp_allocator)
	testing.expect(t, asset_dir_err == nil)
	if asset_dir_err != nil {
		return
	}
	asset_path, asset_path_err := filepath.join({asset_dir, "texture.png"}, context.temp_allocator)
	testing.expect(t, asset_path_err == nil)
	if asset_path_err != nil {
		return
	}
	testing.expect(t, os.write_entire_file(asset_path, "fixture") == nil)

	result := package_project(root, {})
	defer destroy_package_result(&result)
	testing.expectf(t, result.err == "", "package_project failed: %s", result.err)
	if result.err != "" {
		return
	}
	testing.expect(t, result.target == host_target())
	testing.expect(t, os.exists(result.executable))
	marker, marker_err := filepath.join(
		{result.output_directory, PACKAGE_MARKER},
		context.temp_allocator,
	)
	testing.expectf(t, marker_err == nil, "failed to allocate marker path: %v", marker_err)
	if marker_err == nil {
		testing.expect(t, os.exists(marker))
	}
	manifest, manifest_err := filepath.join(
		{result.output_directory, PROJECT_FILE},
		context.temp_allocator,
	)
	testing.expectf(t, manifest_err == nil, "failed to allocate manifest path: %v", manifest_err)
	if manifest_err == nil {
		testing.expect(t, os.exists(manifest))
	}
	packaged_asset, packaged_asset_err := filepath.join(
		{result.output_directory, "assets", "texture.png"},
		context.temp_allocator,
	)
	testing.expect(t, packaged_asset_err == nil)
	if packaged_asset_err == nil {
		testing.expect(t, os.exists(packaged_asset))
	}
	packaged_types, packaged_types_err := filepath.join(
		{result.output_directory, DEFAULT_LUAU_TYPES},
		context.temp_allocator,
	)
	testing.expect(t, packaged_types_err == nil)
	if packaged_types_err == nil {
		testing.expect(t, !os.exists(packaged_types))
	}
	packaged_gitignore, packaged_gitignore_err := filepath.join(
		{result.output_directory, ".gitignore"},
		context.temp_allocator,
	)
	testing.expect(t, packaged_gitignore_err == nil)
	if packaged_gitignore_err == nil {
		testing.expect(t, !os.exists(packaged_gitignore))
	}
}
