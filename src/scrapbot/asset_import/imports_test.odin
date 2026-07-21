package asset_import

import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

texture_test_declaration :: proc(source := "assets/checker.png") -> shared.Project_Resource {
	id, _ := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000099")
	return {
		id = id,
		kind = .Texture,
		name = "Checker",
		texture = {source = source, color_space = .SRGB, generate_mipmaps = true},
	}
}

make_texture_test_project :: proc(t: ^testing.T) -> string {
	root, temp_err := os.make_directory_temp("", "scrapbot-asset-import-*", context.allocator)
	testing.expect(t, temp_err == nil)
	assets, _ := filepath.join({root, "assets"})
	defer delete(assets)
	testing.expect(t, os.make_directory_all(assets) == nil)
	fixture, read_err := os.read_entire_file(
		"examples/minimal/assets/checker.png",
		context.temp_allocator,
	)
	testing.expect(t, read_err == nil)
	path, _ := filepath.join({assets, "checker.png"})
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, fixture) == nil)
	return root
}

@(test)
test_texture_import_is_incremental_and_generates_complete_mip_chain :: proc(t: ^testing.T) {
	root := make_texture_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	declaration := texture_test_declaration()
	first := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&first)
	testing.expectf(t, first.err == "", "texture import failed: %s", first.err)
	testing.expect_value(t, first.imported_count, 1)
	testing.expect_value(t, len(first.products), 1)
	if len(first.products) == 1 {
		product := first.products[0]
		testing.expect_value(t, product.width, u32(8))
		testing.expect_value(t, product.height, u32(8))
		testing.expect_value(t, product.mip_count, u32(4))
		info, stat_err := os.stat(product.artifact_path, context.temp_allocator)
		testing.expect(t, stat_err == nil)
		if stat_err == nil {
			testing.expect_value(t, info.size, i64((64 + 16 + 4 + 1) * 4))
		}
	}
	second := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&second)
	testing.expectf(t, second.err == "", "cached texture import failed: %s", second.err)
	testing.expect_value(t, second.imported_count, 0)
	testing.expect_value(t, second.cached_count, 1)
}

@(test)
test_failed_texture_reimport_preserves_last_good_product :: proc(t: ^testing.T) {
	root := make_texture_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	declaration := texture_test_declaration()
	first := ensure_project_imports(root, []shared.Project_Resource{declaration})
	testing.expectf(t, first.err == "", "texture import failed: %s", first.err)
	if len(first.products) != 1 {
		destroy_report(&first)
		return
	}
	before, read_err := os.read_entire_file(first.products[0].artifact_path, context.allocator)
	testing.expect(t, read_err == nil)
	artifact_path := first.products[0].artifact_path
	owned_artifact_path, clone_err := strings.clone(artifact_path)
	testing.expect(t, clone_err == nil)
	destroy_report(&first)
	defer delete(owned_artifact_path)
	source_path, _ := filepath.join({root, declaration.texture.source})
	defer delete(source_path)
	testing.expect(t, os.write_entire_file(source_path, "not a png") == nil)
	failed := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&failed)
	testing.expect(t, failed.err != "")
	after, after_err := os.read_entire_file(owned_artifact_path, context.allocator)
	defer delete(before)
	defer delete(after)
	testing.expect(t, after_err == nil)
	testing.expect(t, string(after) == string(before))
}
