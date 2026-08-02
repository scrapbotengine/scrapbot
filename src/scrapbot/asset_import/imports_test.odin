package asset_import

import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

Progress_Test_Event :: struct {
	kind: Progress_Event_Kind,
	index, total: int,
	imported: bool,
	has_product: bool,
	has_error: bool,
	imported_count, cached_count: int,
}

Progress_Test_Collector :: struct {
	events: [8]Progress_Test_Event,
	count: int,
}

record_progress_test_event :: proc "contextless" (data: rawptr, event: Progress_Event) {
	collector := cast(^Progress_Test_Collector)data
	if collector == nil || collector.count >= len(collector.events) {
		return
	}
	collector.events[collector.count] = {
		kind = event.kind,
		index = event.index,
		total = event.total,
		imported = event.imported,
		has_product = event.product != nil,
		has_error = event.err != "",
		imported_count = event.imported_count,
		cached_count = event.cached_count,
	}
	collector.count += 1
}

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
test_import_progress_reports_live_work_and_cache_hits :: proc(t: ^testing.T) {
	root := make_texture_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	declaration := texture_test_declaration()

	first_events: Progress_Test_Collector
	first := ensure_project_imports(
		root,
		[]shared.Project_Resource{declaration},
		progress = {callback = record_progress_test_event, data = &first_events},
	)
	defer destroy_report(&first)
	testing.expectf(t, first.err == "", "texture import failed: %s", first.err)
	testing.expect_value(t, first_events.count, 4)
	if first_events.count == 4 {
		testing.expect_value(t, first_events.events[0].kind, Progress_Event_Kind.Started)
		testing.expect_value(t, first_events.events[0].total, 1)
		testing.expect_value(t, first_events.events[1].kind, Progress_Event_Kind.Asset_Started)
		testing.expect_value(t, first_events.events[1].index, 1)
		testing.expect_value(t, first_events.events[2].kind, Progress_Event_Kind.Asset_Completed)
		testing.expect(t, first_events.events[2].imported)
		testing.expect(t, first_events.events[2].has_product)
		testing.expect_value(t, first_events.events[3].kind, Progress_Event_Kind.Completed)
		testing.expect_value(t, first_events.events[3].imported_count, 1)
		testing.expect_value(t, first_events.events[3].cached_count, 0)
	}

	second_events: Progress_Test_Collector
	second := ensure_project_imports(
		root,
		[]shared.Project_Resource{declaration},
		progress = {callback = record_progress_test_event, data = &second_events},
	)
	defer destroy_report(&second)
	testing.expectf(t, second.err == "", "cached texture import failed: %s", second.err)
	testing.expect_value(t, second_events.count, 4)
	if second_events.count == 4 {
		testing.expect_value(t, second_events.events[2].kind, Progress_Event_Kind.Asset_Completed)
		testing.expect(t, !second_events.events[2].imported)
		testing.expect(t, second_events.events[2].has_product)
		testing.expect_value(t, second_events.events[3].imported_count, 0)
		testing.expect_value(t, second_events.events[3].cached_count, 1)
	}
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
	failure_events: Progress_Test_Collector
	failed := ensure_project_imports(
		root,
		[]shared.Project_Resource{declaration},
		progress = {callback = record_progress_test_event, data = &failure_events},
	)
	defer destroy_report(&failed)
	testing.expect(t, failed.err != "")
	testing.expect_value(t, failure_events.count, 3)
	if failure_events.count == 3 {
		testing.expect_value(t, failure_events.events[2].kind, Progress_Event_Kind.Asset_Failed)
		testing.expect(t, failure_events.events[2].has_error)
	}
	after, after_err := os.read_entire_file(owned_artifact_path, context.allocator)
	defer delete(before)
	defer delete(after)
	testing.expect(t, after_err == nil)
	testing.expect(t, string(after) == string(before))
}

@(test)
test_forced_texture_reimport_can_target_one_resource :: proc(t: ^testing.T) {
	root := make_texture_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	first_declaration := texture_test_declaration()
	second_declaration := texture_test_declaration()
	second_declaration.id, _ = shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000100")
	second_declaration.name = "Checker Two"
	declarations := []shared.Project_Resource{first_declaration, second_declaration}
	warm := ensure_project_imports(root, declarations)
	defer destroy_report(&warm)
	testing.expectf(t, warm.err == "", "texture import failed: %s", warm.err)
	testing.expect_value(t, warm.imported_count, 2)
	targeted := ensure_project_imports(
		root,
		declarations,
		force = true,
		only = second_declaration.id,
	)
	defer destroy_report(&targeted)
	testing.expectf(t, targeted.err == "", "targeted reimport failed: %s", targeted.err)
	testing.expect_value(t, targeted.imported_count, 1)
	testing.expect_value(t, targeted.cached_count, 0)
	testing.expect_value(t, len(targeted.products), 1)
	if len(targeted.products) == 1 {
		testing.expect(t, targeted.products[0].id == second_declaration.id)
	}
}
