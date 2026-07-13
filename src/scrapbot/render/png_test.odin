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

@(test)
test_png_writer_losslessly_compresses_flat_framegrabs :: proc(t:^testing.T) {
	width,height:=u32(128),u32(128)
	pixels:=make([]u8,int(width*height*4));defer delete(pixels)
	for i:=0;i<len(pixels);i+=4 {pixels[i]=18;pixels[i+1]=20;pixels[i+2]=24;pixels[i+3]=255}
	path:="/tmp/scrapbot-test-compressed-framegrab.png"
	testing.expect(t,write_png_rgba8(path,pixels,width,height)=="")
	data,err:=os.read_entire_file(path,context.temp_allocator)
	testing.expect(t,err==nil)
	testing.expect(t,len(data)<len(pixels)/4)
}
