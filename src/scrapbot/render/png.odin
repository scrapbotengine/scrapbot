package render

import "core:c"
import "core:strings"
import stb "vendor:stb/image"

PNG_SIGNATURE :: []u8{0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'}

write_png_rgba8 :: proc(path: string, pixels: []u8, width, height: u32) -> string {
	expected_len := int(width * height * 4)
	if len(pixels) != expected_len {
		return "png framegrab pixel buffer has the wrong size"
	}

	path_c:=strings.clone_to_cstring(path)
	defer delete(path_c)
	if stb.write_png(path_c,c.int(width),c.int(height),4,raw_data(pixels),c.int(width*4))==0 {
		return "failed to write PNG framegrab"
	}
	return ""
}
