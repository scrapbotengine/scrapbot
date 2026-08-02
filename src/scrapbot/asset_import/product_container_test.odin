package asset_import

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_asset_product_stream_writer_commits_bounded_chunks :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-product-stream-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "stream.product"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(path)
	file, create_err := os.create(path)
	testing.expect(t, create_err == nil)
	if create_err != nil {
		return
	}
	writer, begin_err := asset_product_stream_begin(file, .Model, 2)
	defer destroy_asset_product_stream_writer(&writer)
	testing.expectf(t, begin_err == "", "stream begin failed: %s", begin_err)
	testing.expect(t, asset_product_stream_begin_chunk(&writer, .Model_Coarse_Geometry))
	testing.expect(t, asset_product_stream_write(&writer, transmute([]u8)(string("coarse"))))
	testing.expect(t, asset_product_stream_finish_chunk(&writer))
	testing.expect(t, asset_product_stream_begin_chunk(&writer, .Model_Detail_Geometry))
	testing.expect(t, asset_product_stream_write(&writer, transmute([]u8)(string("detail"))))
	testing.expect(t, asset_product_stream_finish_chunk(&writer))
	byte_count, finish_err := asset_product_stream_finish(&writer)
	testing.expectf(t, finish_err == "", "stream finish failed: %s", finish_err)
	testing.expect_value(
		t,
		byte_count,
		ASSET_PRODUCT_HEADER_SIZE + 2 * ASSET_PRODUCT_CHUNK_ENTRY_SIZE + 12,
	)
	testing.expect(t, os.close(file) == nil)
	opened_file, open_err := os.open(path)
	testing.expect(t, open_err == nil)
	if open_err != nil {
		return
	}
	defer os.close(opened_file)
	directory, directory_err := read_asset_product_directory(opened_file, byte_count, .Model)
	defer destroy_asset_product_directory(&directory)
	testing.expectf(t, directory_err == "", "stream directory read failed: %s", directory_err)
	coarse, coarse_found := asset_product_find_chunk(&directory, .Model_Coarse_Geometry)
	detail, detail_found := asset_product_find_chunk(&directory, .Model_Detail_Geometry)
	testing.expect(t, coarse_found)
	testing.expect(t, detail_found)
	testing.expect_value(t, coarse.stored_size, u64(6))
	testing.expect_value(t, detail.stored_size, u64(6))
}

@(test)
test_asset_product_directory_round_trips_typed_chunks :: proc(t: ^testing.T) {
	bytes: [dynamic]u8
	defer delete(bytes)
	testing.expect(t, asset_product_begin(&bytes, .Model, 2))
	first_offset, first_ok := asset_product_begin_chunk(&bytes, 0, .Model_Runtime, 0)
	testing.expect(t, first_ok)
	append(&bytes, 'm', 'o', 'd', 'e', 'l')
	testing.expect(t, asset_product_finish_chunk(&bytes, 0, first_offset))
	second_offset, second_ok := asset_product_begin_chunk(&bytes, 1, .Model_Runtime, 1)
	testing.expect(t, second_ok)
	append(&bytes, 'p', 'a', 'g', 'e')
	testing.expect(t, asset_product_finish_chunk(&bytes, 1, second_offset))

	root, temp_err := os.make_directory_temp("", "scrapbot-asset-product-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "model.product"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, bytes[:]) == nil)
	file, open_err := os.open(path)
	testing.expect(t, open_err == nil)
	if open_err != nil {
		return
	}
	defer os.close(file)
	directory, directory_err := read_asset_product_directory(file, len(bytes), .Model)
	defer destroy_asset_product_directory(&directory)
	testing.expectf(t, directory_err == "", "product directory read failed: %s", directory_err)
	testing.expect_value(t, len(directory.chunks), 2)
	first, first_found := asset_product_find_chunk(&directory, .Model_Runtime, 0)
	second, second_found := asset_product_find_chunk(&directory, .Model_Runtime, 1)
	testing.expect(t, first_found)
	testing.expect(t, second_found)
	testing.expect_value(t, first.offset, u64(first_offset))
	testing.expect_value(t, first.stored_size, u64(5))
	testing.expect_value(t, second.offset, u64(second_offset))
	testing.expect_value(t, second.stored_size, u64(4))
}

@(test)
test_asset_product_directory_rejects_overlapping_chunks :: proc(t: ^testing.T) {
	bytes: [dynamic]u8
	defer delete(bytes)
	testing.expect(t, asset_product_begin(&bytes, .Model, 2))
	first_offset, _ := asset_product_begin_chunk(&bytes, 0, .Model_Runtime, 0)
	append(&bytes, 'a')
	testing.expect(t, asset_product_finish_chunk(&bytes, 0, first_offset))
	second_offset, _ := asset_product_begin_chunk(&bytes, 1, .Model_Runtime, 1)
	append(&bytes, 'b')
	testing.expect(t, asset_product_finish_chunk(&bytes, 1, second_offset))
	second_entry := ASSET_PRODUCT_HEADER_SIZE + ASSET_PRODUCT_CHUNK_ENTRY_SIZE
	asset_product_put_u64(bytes[:], second_entry + 16, u64(first_offset))

	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-asset-product-invalid-*",
		context.allocator,
	)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "broken.product"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, bytes[:]) == nil)
	file, open_err := os.open(path)
	testing.expect(t, open_err == nil)
	if open_err != nil {
		return
	}
	defer os.close(file)
	directory, directory_err := read_asset_product_directory(file, len(bytes), .Model)
	defer destroy_asset_product_directory(&directory)
	testing.expect(t, directory_err != "")
}
