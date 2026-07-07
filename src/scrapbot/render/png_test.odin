package render

import "core:os"
import "core:testing"

@(test)
test_png_writer_produces_png_signature :: proc(t: ^testing.T) {
	pixels := []u8{255, 0, 0, 255}
	path := "/tmp/scrapbot-test-framegrab.png"

	err := write_png_rgba8(path, pixels, 1, 1)
	testing.expect(t, err == "")

	data, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	testing.expect(t, len(data) >= len(PNG_SIGNATURE))
	for byte, index in PNG_SIGNATURE {
		testing.expect(t, data[index] == byte)
	}
}
