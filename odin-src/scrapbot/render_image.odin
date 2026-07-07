package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import core_image "core:image"
import bmp "core:image/bmp"
import png "core:image/png"

Render_Image_Error :: enum {
	None,
	Invalid_Output,
	Unsupported_Format,
	Out_Of_Memory,
	Io_Error,
	Backend_Unavailable,
	Backend_Render_Failed,
	Invalid_Image,
	Image_Size_Mismatch,
	Missing_Foreground,
	Missing_Visible_Components,
	Missing_Color_Groups,
}

Render_Image_Format :: enum {
	PNG,
	BMP,
}

Render_Image :: struct {
	width:  int,
	height: int,
	rgb:    []u8,
}

Render_Image_Verification :: struct {
	foreground_pixels: int,
	visible_components: int,
	color_groups:       int,
}

Render_Image_Comparison_Options :: struct {
	max_channel_delta:        u8,
	max_mean_channel_delta:   f32,
	max_changed_pixel_ratio:  f32,
	changed_pixel_delta:      u8,
}

Render_Image_Comparison :: struct {
	width:                int,
	height:               int,
	pixels:               int,
	max_channel_delta:    u8,
	mean_channel_delta:   f32,
	changed_pixels:       int,
	changed_pixel_ratio:  f32,
}

DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS :: Render_Image_Comparison_Options{
	max_channel_delta = 8,
	max_mean_channel_delta = 1.5,
	max_changed_pixel_ratio = 0.02,
	changed_pixel_delta = 2,
}

EDITOR_CHROME_TOP_COLOR :: [3]u8{34, 40, 50}
EDITOR_CHROME_PANEL_COLOR :: [3]u8{44, 50, 60}
EDITOR_CHROME_BOTTOM_COLOR :: [3]u8{30, 34, 42}
EDITOR_CHROME_RULE_COLOR :: [3]u8{82, 92, 108}
EDITOR_CHROME_VIEWPORT_COLOR :: [3]u8{87, 169, 216}
EDITOR_CHROME_SELECTION_COLOR :: [3]u8{240, 160, 76}
EDITOR_CHROME_BUTTON_COLOR :: [3]u8{82, 96, 116}
EDITOR_CHROME_BUTTON_ACCENT_COLOR :: [3]u8{149, 204, 116}
EDITOR_CHROME_BUTTON_DESTRUCTIVE_COLOR :: [3]u8{220, 112, 104}
EDITOR_CHROME_INSPECTOR_CARD_COLOR :: [3]u8{54, 61, 73}
EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR :: [3]u8{68, 77, 92}
EDITOR_CHROME_INSPECTOR_FIELD_COLOR :: [3]u8{36, 42, 52}

render_write_scene_image :: proc(world: Runtime_World, options: Render_Options, verify_output: bool) -> (Render_Image_Verification, Render_Image_Error) {
	format, format_ok := render_image_format_from_path(options.output_path)
	if !format_ok {
		return Render_Image_Verification{}, .Unsupported_Format
	}
	image := Render_Image{}
	image_ok := false
	image_error := Render_Image_Error.None
	switch options.backend {
	case .Software:
		image, image_ok = render_image_from_scene(world, options)
	case .WebGPU:
		wgpu_error: string
		image, wgpu_error, image_ok = wgpu_render_scene_image(world, options)
		if !image_ok {
			if wgpu_error == WGPU_OFFSCREEN_LIBRARY_NOT_FOUND || wgpu_error == WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR {
				image_error = .Backend_Unavailable
			} else {
				image_error = .Backend_Render_Failed
			}
		}
	}
	if !image_ok {
		if image_error != .None {
			return Render_Image_Verification{}, image_error
		}
		return Render_Image_Verification{}, .Out_Of_Memory
	}
	defer render_image_free(&image)

	verify := Render_Image_Verification{}
	if verify_output {
		verify_err: Render_Image_Error
		verify, verify_err = render_verify_image(image)
		if verify_err != .None {
			return verify, verify_err
		}
	}
	write_err := render_write_image_file(image, options.output_path, format)
	if write_err != .None {
		return verify, write_err
	}
	return verify, .None
}

render_write_artifact_metadata :: proc(path: string, options: Render_Options) -> Render_Image_Error {
	metadata_path := render_artifact_metadata_path(path)
	defer delete(metadata_path)
	if !render_ensure_output_parent(metadata_path) {
		return .Io_Error
	}
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, "{\n")
	strings.write_string(&builder, `  "artifact": "`)
	write_json_string_contents(&builder, path)
	strings.write_string(&builder, `",` + "\n")
	strings.write_string(&builder, `  "physical_width": `)
	strings.write_string(&builder, fmt.tprintf("%d", options.width))
	strings.write_string(&builder, "," + "\n")
	strings.write_string(&builder, `  "physical_height": `)
	strings.write_string(&builder, fmt.tprintf("%d", options.height))
	strings.write_string(&builder, "," + "\n")
	strings.write_string(&builder, `  "logical_width": `)
	strings.write_string(&builder, render_f32_metadata_string(f32(options.width) / options.pixel_scale))
	strings.write_string(&builder, "," + "\n")
	strings.write_string(&builder, `  "logical_height": `)
	strings.write_string(&builder, render_f32_metadata_string(f32(options.height) / options.pixel_scale))
	strings.write_string(&builder, "," + "\n")
	strings.write_string(&builder, `  "pixel_scale": `)
	strings.write_string(&builder, render_f32_metadata_string(options.pixel_scale))
	strings.write_string(&builder, "," + "\n")
	strings.write_string(&builder, `  "backend": "`)
	strings.write_string(&builder, render_backend_metadata_value(options.backend))
	strings.write_string(&builder, `"` + "\n}\n")
	if os.write_entire_file(metadata_path, strings.to_string(builder)) != nil {
		return .Io_Error
	}
	return .None
}

render_backend_metadata_value :: proc(backend: Render_Backend) -> string {
	switch backend {
	case .Software:
		return "software"
	case .WebGPU:
		return "wgpu"
	}
	return "software"
}

render_artifact_metadata_path :: proc(path: string) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	strings.write_string(&builder, path)
	strings.write_string(&builder, ".metadata.json")
	return strings.clone(strings.to_string(builder))
}

render_f32_metadata_string :: proc(value: f32) -> string {
	return fmt.tprintf("%.3f", value)
}

render_compare_image_files :: proc(expected_path, actual_path: string, options := DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS) -> (Render_Image_Comparison, Render_Image_Error) {
	expected, expected_err := render_load_rgb_image(expected_path)
	if expected_err != .None {
		return Render_Image_Comparison{}, expected_err
	}
	defer render_image_free(&expected)

	actual, actual_err := render_load_rgb_image(actual_path)
	if actual_err != .None {
		return Render_Image_Comparison{}, actual_err
	}
	defer render_image_free(&actual)

	return render_compare_images(expected, actual, options)
}

render_compare_images :: proc(expected, actual: Render_Image, options: Render_Image_Comparison_Options) -> (Render_Image_Comparison, Render_Image_Error) {
	if expected.width <= 0 || expected.height <= 0 || expected.rgb == nil || actual.width <= 0 || actual.height <= 0 || actual.rgb == nil {
		return Render_Image_Comparison{}, .Invalid_Image
	}
	if expected.width != actual.width || expected.height != actual.height {
		return Render_Image_Comparison{}, .Image_Size_Mismatch
	}

	pixel_count := expected.width * expected.height
	total_channel_delta: u64 = 0
	comparison := Render_Image_Comparison{
		width = expected.width,
		height = expected.height,
		pixels = pixel_count,
	}
	for index in 0 ..< pixel_count {
		offset := index * 3
		pixel_changed := false
		deltas := [?]u8{
			render_abs_diff_u8(expected.rgb[offset], actual.rgb[offset]),
			render_abs_diff_u8(expected.rgb[offset + 1], actual.rgb[offset + 1]),
			render_abs_diff_u8(expected.rgb[offset + 2], actual.rgb[offset + 2]),
		}
		for delta in deltas {
			comparison.max_channel_delta = max(comparison.max_channel_delta, delta)
			total_channel_delta += u64(delta)
			if delta > options.changed_pixel_delta {
				pixel_changed = true
			}
		}
		if pixel_changed {
			comparison.changed_pixels += 1
		}
	}
	comparison.mean_channel_delta = f32(total_channel_delta) / f32(pixel_count * 3)
	comparison.changed_pixel_ratio = f32(comparison.changed_pixels) / f32(pixel_count)
	return comparison, .None
}

render_comparison_passed :: proc(comparison: Render_Image_Comparison, options := DEFAULT_RENDER_IMAGE_COMPARISON_OPTIONS) -> bool {
	return comparison.max_channel_delta <= options.max_channel_delta &&
	       comparison.mean_channel_delta <= options.max_mean_channel_delta &&
	       comparison.changed_pixel_ratio <= options.max_changed_pixel_ratio
}

render_load_rgb_image :: proc(path: string) -> (Render_Image, Render_Image_Error) {
	format, format_ok := render_image_format_from_path(path)
	if !format_ok {
		return Render_Image{}, .Unsupported_Format
	}

	img: ^core_image.Image
	err: core_image.Error
	switch format {
	case .PNG:
		img, err = png.load(path)
	case .BMP:
		img, err = bmp.load(path)
	}
	if err != nil || img == nil {
		return Render_Image{}, .Invalid_Image
	}
	defer core_image.destroy(img)

	if img.width <= 0 || img.height <= 0 || img.depth != 8 || img.channels < 3 || img.channels > 4 {
		return Render_Image{}, .Invalid_Image
	}
	if len(img.pixels.buf) < img.width * img.height * img.channels {
		return Render_Image{}, .Invalid_Image
	}
	pixels := make([]u8, img.width * img.height * 3)
	if pixels == nil {
		return Render_Image{}, .Out_Of_Memory
	}
	for index in 0 ..< img.width * img.height {
		source := index * img.channels
		target := index * 3
		pixels[target] = img.pixels.buf[source]
		pixels[target + 1] = img.pixels.buf[source + 1]
		pixels[target + 2] = img.pixels.buf[source + 2]
	}
	return Render_Image{width = img.width, height = img.height, rgb = pixels}, .None
}

render_abs_diff_u8 :: proc(left, right: u8) -> u8 {
	if left >= right {
		return left - right
	}
	return right - left
}

render_image_format_from_path :: proc(path: string) -> (Render_Image_Format, bool) {
	lower := strings.to_lower(filepath.ext(path))
	defer delete(lower)
	switch lower {
	case ".png":
		return .PNG, true
	case ".bmp":
		return .BMP, true
	}
	return .PNG, false
}

render_image_from_scene :: proc(world: Runtime_World, options: Render_Options) -> (Render_Image, bool) {
	width := options.width
	height := options.height
	if width <= 0 || height <= 0 {
		return Render_Image{}, false
	}
	pixels := make([]u8, width * height * 3)
	if pixels == nil {
		return Render_Image{}, false
	}
	image := Render_Image{width = width, height = height, rgb = pixels}
	render_fill(&image, {18, 22, 29})
	render_draw_scene_renderables(&image, world)
	render_draw_scene_ui(&image, world)
	if options.editor {
		render_draw_editor_chrome(&image, world, options)
	}
	return image, true
}

render_image_free :: proc(image: ^Render_Image) {
	if image.rgb != nil {
		delete(image.rgb)
	}
	image^ = Render_Image{}
}

render_fill :: proc(image: ^Render_Image, color: [3]u8) {
	for y in 0 ..< image.height {
		for x in 0 ..< image.width {
			render_set_pixel(image, x, y, color)
		}
	}
}

render_draw_scene_renderables :: proc(image: ^Render_Image, world: Runtime_World) {
	cursor := 0
	index := 0
	for {
		entity, found := runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID}, &cursor)
		if !found {
			break
		}
		has_geometry := render_entity_has_component(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID) &&
		                render_entity_has_component(world, entity, SURFACE_MATERIAL_COMPONENT_ID)
		has_legacy_cube := render_entity_has_component(world, entity, CUBE_RENDERER_COMPONENT_ID)
		if !has_geometry && !has_legacy_cube {
			continue
		}
		color := render_entity_color(world, entity, index)
		rect := render_renderable_rect(image.width, image.height, index)
		render_fill_rect(image, rect.x, rect.y, rect.width, rect.height, color)
		render_stroke_rect(image, rect.x, rect.y, rect.width, rect.height, render_lighten_color(color))
		index += 1
	}
}

render_draw_scene_ui :: proc(image: ^Render_Image, world: Runtime_World) {
	cursor := 0
	for {
		entity, found := runtime_world_query_next(world, []string{UI_RECT_COMPONENT_ID}, &cursor)
		if !found {
			break
		}
		position, position_err := runtime_world_get_vec3(world, entity, UI_RECT_COMPONENT_ID, "position")
		size, size_err := runtime_world_get_vec3(world, entity, UI_RECT_COMPONENT_ID, "size")
		color_value, color_err := runtime_world_get_component_field_value(world, entity, UI_RECT_COMPONENT_ID, "color")
		if position_err != .None || size_err != .None || color_err != .None || color_value.value_type != .Vec3 {
			continue
		}
		x := int(math.round_f32(position[0]))
		y := int(math.round_f32(position[1]))
		width := max(1, int(math.round_f32(size[0])))
		height := max(1, int(math.round_f32(size[1])))
		color := render_vec3_to_rgb(color_value.vec3, {80, 170, 245})
		render_fill_rect(image, x, y, width, height, color)
	}
}

render_draw_editor_chrome :: proc(image: ^Render_Image, world: Runtime_World, options: Render_Options) {
	if image.width <= 0 || image.height <= 0 {
		return
	}
	top_height := min(max(24, image.height / 12), max(1, image.height / 3))
	bottom_height := min(max(18, image.height / 16), max(1, image.height / 5))
	body_y := top_height
	body_height := max(0, image.height - top_height - bottom_height)
	left_width := min(max(72, image.width / 5), max(1, image.width / 3))
	right_width := min(max(96, image.width * 3 / 10), max(1, image.width / 3))
	if left_width + right_width + 48 > image.width {
		left_width = max(8, image.width / 5)
		right_width = max(8, image.width / 4)
	}
	viewport_x := left_width
	viewport_width := max(0, image.width - left_width - right_width)

	render_fill_rect(image, 0, 0, image.width, top_height, EDITOR_CHROME_TOP_COLOR)
	render_fill_rect(image, 0, image.height - bottom_height, image.width, bottom_height, EDITOR_CHROME_BOTTOM_COLOR)
	render_fill_rect(image, 0, body_y, left_width, body_height, EDITOR_CHROME_PANEL_COLOR)
	render_fill_rect(image, image.width - right_width, body_y, right_width, body_height, EDITOR_CHROME_PANEL_COLOR)
	render_draw_editor_entity_buttons(image, left_width, body_y)
	render_fill_rect(image, 0, top_height - 2, image.width, 2, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, 0, image.height - bottom_height, image.width, 2, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, left_width - 2, body_y, 2, body_height, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, image.width - right_width, body_y, 2, body_height, EDITOR_CHROME_RULE_COLOR)
	if viewport_width > 0 && body_height > 0 {
		render_stroke_rect(image, viewport_x, body_y, viewport_width, body_height, EDITOR_CHROME_VIEWPORT_COLOR)
	}
	if options.selected_entity_id != "" && right_width > 24 && body_height > 28 {
		accent_x := image.width - right_width + 12
		accent_y := body_y + 14
		accent_width := max(4, right_width - 24)
		accent_height := min(max(8, body_height / 18), body_height - 28)
		render_fill_rect(image, accent_x, accent_y, accent_width, accent_height, EDITOR_CHROME_SELECTION_COLOR)
		render_draw_editor_inspector_cards(image, world, options.selected_entity_id, image.width - right_width, body_y, right_width, body_height, options.inspector_scroll_y)
	}
	render_draw_editor_component_buttons(image, image.width - right_width, right_width, body_y)
}

render_draw_editor_entity_buttons :: proc(image: ^Render_Image, left_width, body_y: int) {
	if left_width < 32 {
		return
	}
	button_size := min(max(10, left_width / 4), 18)
	gap := max(4, button_size / 4)
	spawn_x := max(4, left_width - button_size * 2 - gap - 8)
	button_y := body_y + 8
	render_fill_rect(image, spawn_x, button_y, button_size, button_size, EDITOR_CHROME_BUTTON_COLOR)
	render_stroke_rect(image, spawn_x, button_y, button_size, button_size, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, spawn_x + button_size / 2 - 1, button_y + 4, 2, max(2, button_size - 8), EDITOR_CHROME_BUTTON_ACCENT_COLOR)
	render_fill_rect(image, spawn_x + 4, button_y + button_size / 2 - 1, max(2, button_size - 8), 2, EDITOR_CHROME_BUTTON_ACCENT_COLOR)

	despawn_x := spawn_x + button_size + gap
	render_fill_rect(image, despawn_x, button_y, button_size, button_size, EDITOR_CHROME_BUTTON_COLOR)
	render_stroke_rect(image, despawn_x, button_y, button_size, button_size, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, despawn_x + 4, button_y + button_size / 2 - 1, max(2, button_size - 8), 2, EDITOR_CHROME_BUTTON_DESTRUCTIVE_COLOR)
}

render_draw_editor_component_buttons :: proc(image: ^Render_Image, right_x, right_width, body_y: int) {
	if right_width < 32 {
		return
	}
	button_size := min(max(10, right_width / 6), 18)
	gap := max(4, button_size / 4)
	spawn_x := right_x + max(4, right_width - button_size * 2 - gap - 8)
	button_y := body_y + 8
	render_fill_rect(image, spawn_x, button_y, button_size, button_size, EDITOR_CHROME_BUTTON_COLOR)
	render_stroke_rect(image, spawn_x, button_y, button_size, button_size, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, spawn_x + button_size / 2 - 1, button_y + 4, 2, max(2, button_size - 8), EDITOR_CHROME_BUTTON_ACCENT_COLOR)
	render_fill_rect(image, spawn_x + 4, button_y + button_size / 2 - 1, max(2, button_size - 8), 2, EDITOR_CHROME_BUTTON_ACCENT_COLOR)

	remove_x := spawn_x + button_size + gap
	render_fill_rect(image, remove_x, button_y, button_size, button_size, EDITOR_CHROME_BUTTON_COLOR)
	render_stroke_rect(image, remove_x, button_y, button_size, button_size, EDITOR_CHROME_RULE_COLOR)
	render_fill_rect(image, remove_x + 4, button_y + button_size / 2 - 1, max(2, button_size - 8), 2, EDITOR_CHROME_BUTTON_DESTRUCTIVE_COLOR)
}

render_draw_editor_inspector_cards :: proc(image: ^Render_Image, world: Runtime_World, selected_entity_id: string, right_x, body_y, right_width, body_height: int, scroll_y: f32) {
	selected, selected_ok := runtime_world_find_entity_by_id(world, selected_entity_id)
	if !selected_ok {
		return
	}
	selected_index, selected_err := runtime_world_entity_index(world, selected)
	if selected_err != .None {
		return
	}
	card_x := right_x + 12
	card_y := body_y + 36 - int(math.round_f32(max_f32(scroll_y, 0.0)))
	card_width := max(4, right_width - 24)
	clip_top := body_y + 36
	clip_bottom := body_y + body_height - 8
	for table in world.component_tables {
		if selected_index >= len(table.rows_by_entity) || table.rows_by_entity[selected_index] < 0 {
			continue
		}
		field_count := len(table.columns)
		card_height := 24 + max(1, field_count) * 8
		if card_y >= clip_bottom {
			break
		}
		draw_y := card_y
		draw_height := card_height
		header_offset := 0
		if draw_y < clip_top {
			header_offset = clip_top - draw_y
			draw_height -= header_offset
			draw_y = clip_top
		}
		if draw_y + draw_height > clip_bottom {
			draw_height = max(0, clip_bottom - draw_y)
		}
		if draw_height > 0 {
			render_fill_rect(image, card_x, draw_y, card_width, draw_height, EDITOR_CHROME_INSPECTOR_CARD_COLOR)
			render_stroke_rect(image, card_x, draw_y, card_width, draw_height, EDITOR_CHROME_RULE_COLOR)
			if header_offset < 12 {
				header_y := max(card_y + 2, clip_top)
				header_available := draw_y + draw_height - header_y
				if header_available > 0 {
					header_height := min(10 - header_offset, header_available)
					render_fill_rect(image, card_x + 2, header_y, max(1, card_width - 4), header_height, EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR)
				}
			}
			field_y := card_y + 16
			for _ in table.columns {
				if field_y + 5 >= card_y + card_height - 2 {
					break
				}
				if field_y + 5 >= clip_top && field_y < clip_bottom {
					clipped_y := max(field_y, clip_top)
					clipped_height := min(5, clip_bottom - clipped_y)
					if clipped_height > 0 {
						render_fill_rect(image, card_x + 6, clipped_y, max(1, card_width - 12), clipped_height, EDITOR_CHROME_INSPECTOR_FIELD_COLOR)
					}
				}
				field_y += 8
			}
		}
		card_y += card_height + 4
	}
}

Renderable_Rect :: struct {
	x:      int,
	y:      int,
	width:  int,
	height: int,
}

render_renderable_rect :: proc(width, height, index: int) -> Renderable_Rect {
	cell_width := max(64, width / 4)
	cell_height := max(64, height / 3)
	size := min(min(cell_width, cell_height) * 3 / 5, 120)
	x := (index % 4) * cell_width + (cell_width - size) / 2
	y := (index / 4) * cell_height + (cell_height - size) / 2
	if y + size >= height {
		y = max(0, height - size - 8)
	}
	return Renderable_Rect{x = x, y = y, width = size, height = size}
}

render_entity_color :: proc(world: Runtime_World, entity: Entity_Handle, index: int) -> [3]u8 {
	if value, err := runtime_world_get_component_field_value(world, entity, SURFACE_MATERIAL_COMPONENT_ID, "base_color"); err == .None && value.value_type == .Vec3 {
		return render_vec3_to_rgb(value.vec3, render_fallback_color(index))
	}
	if value, err := runtime_world_get_component_field_value(world, entity, CUBE_RENDERER_COMPONENT_ID, "color"); err == .None && value.value_type == .Vec3 {
		return render_vec3_to_rgb(value.vec3, render_fallback_color(index))
	}
	return render_fallback_color(index)
}

render_fallback_color :: proc(index: int) -> [3]u8 {
	colors := [?][3]u8{
		{235, 112, 67},
		{62, 155, 230},
		{226, 190, 72},
		{116, 207, 138},
	}
	return colors[index % len(colors)]
}

render_vec3_to_rgb :: proc(value: [3]f32, fallback: [3]u8) -> [3]u8 {
	if !render_f32_is_finite(value[0]) || !render_f32_is_finite(value[1]) || !render_f32_is_finite(value[2]) {
		return fallback
	}
	return {
		u8(math.clamp(value[0], 0.0, 1.0) * 255.0),
		u8(math.clamp(value[1], 0.0, 1.0) * 255.0),
		u8(math.clamp(value[2], 0.0, 1.0) * 255.0),
	}
}

render_f32_is_finite :: proc(value: f32) -> bool {
	return !math.is_nan_f32(value) && !math.is_inf_f32(value)
}

render_lighten_color :: proc(color: [3]u8) -> [3]u8 {
	return {
		u8(min(255, int(color[0]) + 38)),
		u8(min(255, int(color[1]) + 38)),
		u8(min(255, int(color[2]) + 38)),
	}
}

render_fill_rect :: proc(image: ^Render_Image, x, y, width, height: int, color: [3]u8) {
	min_x := max(0, x)
	min_y := max(0, y)
	max_x := min(image.width, x + width)
	max_y := min(image.height, y + height)
	for py in min_y ..< max_y {
		for px in min_x ..< max_x {
			render_set_pixel(image, px, py, color)
		}
	}
}

render_stroke_rect :: proc(image: ^Render_Image, x, y, width, height: int, color: [3]u8) {
	render_fill_rect(image, x, y, width, 2, color)
	render_fill_rect(image, x, y + height - 2, width, 2, color)
	render_fill_rect(image, x, y, 2, height, color)
	render_fill_rect(image, x + width - 2, y, 2, height, color)
}

render_set_pixel :: proc(image: ^Render_Image, x, y: int, color: [3]u8) {
	if x < 0 || y < 0 || x >= image.width || y >= image.height {
		return
	}
	offset := (y * image.width + x) * 3
	image.rgb[offset] = color[0]
	image.rgb[offset + 1] = color[1]
	image.rgb[offset + 2] = color[2]
}

render_verify_image :: proc(image: Render_Image) -> (Render_Image_Verification, Render_Image_Error) {
	if image.width <= 0 || image.height <= 0 || image.rgb == nil {
		return Render_Image_Verification{}, .Invalid_Image
	}
	pixel_count := image.width * image.height
	visited := make([]bool, pixel_count)
	if visited == nil {
		return Render_Image_Verification{}, .Out_Of_Memory
	}
	defer delete(visited)
	stack := make([]int, pixel_count)
	if stack == nil {
		return Render_Image_Verification{}, .Out_Of_Memory
	}
	defer delete(stack)

	verify := Render_Image_Verification{}
	warm_pixels := 0
	cool_pixels := 0
	for start in 0 ..< pixel_count {
		if visited[start] {
			continue
		}
		visited[start] = true
		if !render_is_foreground(image.rgb[start * 3:][:3]) {
			continue
		}

		component_area := 0
		stack_len := 1
		stack[0] = start
		for stack_len > 0 {
			stack_len -= 1
			index := stack[stack_len]
			component_area += 1
			pixel := image.rgb[index * 3:][:3]
			if render_is_warm(pixel) {
				warm_pixels += 1
			}
			if render_is_cool(pixel) {
				cool_pixels += 1
			}

			x := index % image.width
			y := index / image.width
			neighbors := [?]int{
				x > 0 ? index - 1 : -1,
				x + 1 < image.width ? index + 1 : -1,
				y > 0 ? index - image.width : -1,
				y + 1 < image.height ? index + image.width : -1,
			}
			for neighbor in neighbors {
				if neighbor < 0 || visited[neighbor] {
					continue
				}
				visited[neighbor] = true
				if !render_is_foreground(image.rgb[neighbor * 3:][:3]) {
					continue
				}
				stack[stack_len] = neighbor
				stack_len += 1
			}
		}

		verify.foreground_pixels += component_area
		if component_area >= 100 {
			verify.visible_components += 1
		}
	}
	if warm_pixels >= 500 {
		verify.color_groups += 1
	}
	if cool_pixels >= 500 {
		verify.color_groups += 1
	}
	if verify.foreground_pixels < 1000 {
		return verify, .Missing_Foreground
	}
	if verify.visible_components < 1 {
		return verify, .Missing_Visible_Components
	}
	if verify.color_groups < 1 {
		return verify, .Missing_Color_Groups
	}
	return verify, .None
}

render_is_foreground :: proc(pixel: []u8) -> bool {
	return int(pixel[0]) + int(pixel[1]) + int(pixel[2]) > 96
}

render_is_warm :: proc(pixel: []u8) -> bool {
	return pixel[0] > pixel[2] && pixel[0] > 96
}

render_is_cool :: proc(pixel: []u8) -> bool {
	return pixel[2] > pixel[0] && pixel[2] > 96
}

render_write_image_file :: proc(image: Render_Image, path: string, format: Render_Image_Format) -> Render_Image_Error {
	if !render_ensure_output_parent(path) {
		return .Io_Error
	}
	switch format {
	case .PNG:
		return render_write_png(image, path)
	case .BMP:
		return render_write_bmp(image, path)
	}
	return .Unsupported_Format
}

render_ensure_output_parent :: proc(path: string) -> bool {
	dir, _ := filepath.split(path)
	if dir == "" || os.exists(dir) {
		return true
	}
	return os.mkdir_all(dir) == nil
}

render_write_png :: proc(image: Render_Image, path: string) -> Render_Image_Error {
	filtered_len := (image.width * 3 + 1) * image.height
	filtered := make([]u8, filtered_len)
	if filtered == nil {
		return .Out_Of_Memory
	}
	defer delete(filtered)
	cursor := 0
	for y in 0 ..< image.height {
		filtered[cursor] = 0
		cursor += 1
		row_start := y * image.width * 3
		copy(filtered[cursor:][:image.width * 3], image.rgb[row_start:][:image.width * 3])
		cursor += image.width * 3
	}

	zlib := render_zlib_store(filtered)
	if zlib == nil {
		return .Out_Of_Memory
	}
	defer delete(zlib)

	output: [dynamic]u8
	defer delete(output)
	render_append_bytes(&output, []u8{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a})
	ihdr: [13]u8
	render_put_be_u32(ihdr[:], 0, u32(image.width))
	render_put_be_u32(ihdr[:], 4, u32(image.height))
	ihdr[8] = 8
	ihdr[9] = 2
	ihdr[10] = 0
	ihdr[11] = 0
	ihdr[12] = 0
	render_append_png_chunk(&output, "IHDR", ihdr[:])
	render_append_png_chunk(&output, "IDAT", zlib)
	render_append_png_chunk(&output, "IEND", nil)
	if os.write_entire_file(path, output[:]) != nil {
		return .Io_Error
	}
	return .None
}

render_zlib_store :: proc(data: []u8) -> []u8 {
	output: [dynamic]u8
	append(&output, u8(0x78))
	append(&output, u8(0x01))
	cursor := 0
	for cursor < len(data) {
		remaining := len(data) - cursor
		block_len := min(remaining, 65535)
		final := cursor + block_len == len(data)
		append(&output, final ? u8(0x01) : u8(0x00))
		len16 := u16(block_len)
		nlen16 := ~len16
		render_append_le_u16(&output, len16)
		render_append_le_u16(&output, nlen16)
		render_append_bytes(&output, data[cursor:][:block_len])
		cursor += block_len
	}
	adler := render_adler32(data)
	render_append_be_u32(&output, adler)
	return output[:]
}

render_append_png_chunk :: proc(output: ^[dynamic]u8, chunk_type: string, data: []u8) {
	render_append_be_u32(output, u32(len(data)))
	start := len(output^)
	render_append_bytes(output, transmute([]u8)chunk_type)
	if data != nil {
		render_append_bytes(output, data)
	}
	crc := render_crc32(output^[start:])
	render_append_be_u32(output, crc)
}

render_write_bmp :: proc(image: Render_Image, path: string) -> Render_Image_Error {
	row_bytes := render_bmp_row_bytes(image.width)
	file_size := 54 + row_bytes * image.height
	output := make([]u8, file_size)
	if output == nil {
		return .Out_Of_Memory
	}
	defer delete(output)
	cursor := 0
	render_write_bytes(output, &cursor, []u8{'B', 'M'})
	render_write_le_u32(output, &cursor, u32(file_size))
	render_write_le_u32(output, &cursor, 0)
	render_write_le_u32(output, &cursor, 54)
	render_write_le_u32(output, &cursor, 40)
	render_write_le_u32(output, &cursor, u32(image.width))
	render_write_le_u32(output, &cursor, u32(image.height))
	render_write_le_u16(output, &cursor, 1)
	render_write_le_u16(output, &cursor, 24)
	for _ in 0 ..< 24 {
		output[cursor] = 0
		cursor += 1
	}
	for row in 0 ..< image.height {
		source_y := image.height - row - 1
		for x in 0 ..< image.width {
			source := (source_y * image.width + x) * 3
			output[cursor] = image.rgb[source + 2]
			output[cursor + 1] = image.rgb[source + 1]
			output[cursor + 2] = image.rgb[source]
			cursor += 3
		}
		padding := row_bytes - image.width * 3
		for _ in 0 ..< padding {
			output[cursor] = 0
			cursor += 1
		}
	}
	if os.write_entire_file(path, output) != nil {
		return .Io_Error
	}
	return .None
}

render_bmp_row_bytes :: proc(width: int) -> int {
	return ((width * 3 + 3) / 4) * 4
}

render_append_bytes :: proc(output: ^[dynamic]u8, bytes: []u8) {
	for byte in bytes {
		append(output, byte)
	}
}

render_append_le_u16 :: proc(output: ^[dynamic]u8, value: u16) {
	append(output, u8(value & 0xff))
	append(output, u8((value >> 8) & 0xff))
}

render_append_be_u32 :: proc(output: ^[dynamic]u8, value: u32) {
	append(output, u8((value >> 24) & 0xff))
	append(output, u8((value >> 16) & 0xff))
	append(output, u8((value >> 8) & 0xff))
	append(output, u8(value & 0xff))
}

render_write_bytes :: proc(output: []u8, cursor: ^int, bytes: []u8) {
	copy(output[cursor^:], bytes)
	cursor^ += len(bytes)
}

render_write_le_u16 :: proc(output: []u8, cursor: ^int, value: u16) {
	output[cursor^] = u8(value & 0xff)
	output[cursor^ + 1] = u8((value >> 8) & 0xff)
	cursor^ += 2
}

render_write_le_u32 :: proc(output: []u8, cursor: ^int, value: u32) {
	output[cursor^] = u8(value & 0xff)
	output[cursor^ + 1] = u8((value >> 8) & 0xff)
	output[cursor^ + 2] = u8((value >> 16) & 0xff)
	output[cursor^ + 3] = u8((value >> 24) & 0xff)
	cursor^ += 4
}

render_put_be_u32 :: proc(output: []u8, offset: int, value: u32) {
	output[offset] = u8((value >> 24) & 0xff)
	output[offset + 1] = u8((value >> 16) & 0xff)
	output[offset + 2] = u8((value >> 8) & 0xff)
	output[offset + 3] = u8(value & 0xff)
}

render_crc32 :: proc(data: []u8) -> u32 {
	crc := u32(0xffffffff)
	for byte in data {
		crc = crc ~ u32(byte)
		for _ in 0 ..< 8 {
			if crc & 1 != 0 {
				crc = (crc >> 1) ~ u32(0xedb88320)
			} else {
				crc = crc >> 1
			}
		}
	}
	return ~crc
}

render_adler32 :: proc(data: []u8) -> u32 {
	a := u32(1)
	b := u32(0)
	for byte in data {
		a = (a + u32(byte)) % 65521
		b = (b + a) % 65521
	}
	return (b << 16) | a
}
