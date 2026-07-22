package scrapbot

import ecs "./ecs"
import shared "./shared"
import "core:fmt"
import "core:strings"

write_scene_world_entity :: proc(
	builder: ^strings.Builder,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	snapshot, ok := ecs.capture_entity_snapshot(world, entity_index)
	if !ok {
		return false
	}
	defer ecs.destroy_entity_snapshot(&snapshot)
	write_scene_entity(builder, &snapshot.entity)
	return true
}

write_scene_entity :: proc(builder: ^strings.Builder, entity: ^shared.Scene_Entity) {
	strings.write_string(builder, "[[entities]]\n")
	write_scene_string(builder, "id", scene_uuid(entity.id))
	write_scene_string(builder, "name", entity.name)
	if entity.has_transform {
		write_scene_section(builder, "transform")
		if entity.transform.parent != (shared.Entity_UUID{}) {
			write_scene_string(builder, "parent", scene_uuid(entity.transform.parent))
		}
		write_scene_value(builder, "position", scene_vec3(entity.transform.position))
		write_scene_value(builder, "rotation", scene_vec3(entity.transform.rotation))
		write_scene_value(builder, "scale", scene_vec3(entity.transform.scale))
	}
	if entity.has_camera {
		write_scene_section(builder, "camera")
		write_scene_value(builder, "fov", scene_f32(entity.camera.fov))
		write_scene_value(builder, "near", scene_f32(entity.camera.near))
		write_scene_value(builder, "far", scene_f32(entity.camera.far))
		write_scene_value(builder, "exposure", scene_f32(shared.camera_exposure(entity.camera)))
	}
	if entity.has_ambient_light {
		write_scene_section(builder, "ambient_light")
		write_scene_value(builder, "color", scene_vec3(entity.ambient_light.color))
		write_scene_value(builder, "intensity", scene_f32(entity.ambient_light.intensity))
	}
	if entity.has_directional_light {
		write_scene_section(builder, "directional_light")
		write_scene_value(builder, "direction", scene_vec3(entity.directional_light.direction))
		write_scene_value(builder, "color", scene_vec3(entity.directional_light.color))
		write_scene_value(builder, "intensity", scene_f32(entity.directional_light.intensity))
	}
	if entity.has_point_light {
		write_scene_section(builder, "point_light")
		write_scene_value(builder, "color", scene_vec3(entity.point_light.color))
		write_scene_value(builder, "intensity", scene_f32(entity.point_light.intensity))
		write_scene_value(builder, "range", scene_f32(entity.point_light.range))
	}
	if entity.has_mesh {
		write_scene_section(builder, "mesh")
		write_scene_string(builder, "primitive", entity.mesh.primitive)
	}
	if entity.has_geometry {
		write_scene_section(builder, "geometry")
		write_scene_string(builder, "resource", entity.geometry_resource)
	}
	if entity.has_material {
		write_scene_section(builder, "material")
		write_scene_string(builder, "resource", entity.material_resource)
	}
	if entity.has_model {
		write_scene_section(builder, "model")
		write_scene_string(builder, "resource", entity.model_resource)
	}
	if entity.has_shadow_caster { write_scene_section(builder, "shadow_caster") }
	if entity.has_shadow_receiver { write_scene_section(builder, "shadow_receiver") }
	write_scene_ui_components(builder, entity)
	for component in entity.custom_components {
		strings.write_string(builder, "\n[entities.components.")
		strings.write_string(builder, component.name)
		strings.write_string(builder, "]\n")
		for field in component.number_fields {
			write_scene_value(builder, field.name, scene_f32(field.value))
		}
		for field in component.vec2_fields {
			write_scene_value(builder, field.name, scene_vec2(field.value))
		}
		for field in component.vec3_fields {
			write_scene_value(builder, field.name, scene_vec3(field.value))
		}
		for field in component.vec4_fields {
			write_scene_value(builder, field.name, scene_vec4(field.value))
		}
	}
}

write_scene_ui_components :: proc(builder: ^strings.Builder, entity: ^shared.Scene_Entity) {
	if entity.has_ui_layout {
		value := entity.ui_layout
		write_scene_section(builder, "ui_layout")
		if value.parent !=
		   (shared.Entity_UUID{}) { write_scene_string(builder, "parent", scene_uuid(value.parent)) }
		write_scene_value(builder, "position", scene_vec2(value.position))
		write_scene_value(builder, "size", scene_vec2(value.size))
		write_scene_value(builder, "min_size", scene_vec2(value.min_size))
		write_scene_value(builder, "margin", scene_vec4(value.margin))
		write_scene_value(builder, "padding", scene_vec4(value.padding))
		write_scene_value(builder, "background", scene_vec4(value.background))
		write_scene_value(builder, "border_color", scene_vec4(value.border_color))
		write_scene_value(builder, "border_width", scene_f32(value.border_width))
		write_scene_value(builder, "corner_radius", scene_f32(value.corner_radius))
		write_scene_value(builder, "hidden", scene_bool(value.hidden))
		write_scene_value(builder, "fill_width", scene_bool(value.fill_width))
		write_scene_value(builder, "fill_height", scene_bool(value.fill_height))
		write_scene_value(builder, "fit_content_width", scene_bool(value.fit_content_width))
		write_scene_value(builder, "fit_content_height", scene_bool(value.fit_content_height))
		write_scene_value(builder, "fixed_in_fill", scene_bool(value.fixed_in_fill))
		write_scene_value(builder, "tree_item", scene_bool(value.tree_item))
		if value.tree_parent != (shared.Entity_UUID{}) {
			write_scene_string(builder, "tree_parent", scene_uuid(value.tree_parent))
		}
		write_scene_value(builder, "tree_order", fmt.tprintf("%d", value.tree_order))
		write_scene_value(builder, "tree_collapsed", scene_bool(value.tree_collapsed))
	}
	if entity.has_ui_hstack { write_scene_stack(builder, "ui_hstack", entity.ui_hstack) }
	if entity.has_ui_vstack { write_scene_stack(builder, "ui_vstack", entity.ui_vstack) }
	if entity.has_ui_scroll_area {
		value := entity.ui_scroll_area
		write_scene_section(builder, "ui_scroll_area")
		write_scene_value(builder, "scroll_speed", scene_f32(value.scroll_speed))
		write_scene_value(builder, "smoothness", scene_f32(value.smoothness))
		write_scene_value(builder, "scrollbar_width", scene_f32(value.scrollbar_width))
		write_scene_value(builder, "scrollbar_right", scene_f32(value.scrollbar_right))
		write_scene_value(
			builder,
			"scrollbar_vertical_inset",
			scene_f32(value.scrollbar_vertical_inset),
		)
		write_scene_value(builder, "minimum_thumb_size", scene_f32(value.minimum_thumb_size))
		write_scene_value(
			builder,
			"scrollbar_corner_radius",
			scene_f32(value.scrollbar_corner_radius),
		)
		write_scene_value(
			builder,
			"scrollbar_track_color",
			scene_vec4(value.scrollbar_track_color),
		)
		write_scene_value(
			builder,
			"scrollbar_thumb_color",
			scene_vec4(value.scrollbar_thumb_color),
		)
	}
	if entity.has_ui_panel {
		value := entity.ui_panel
		write_scene_section(builder, "ui_panel")
		write_scene_string(builder, "title", value.title)
		write_scene_string(builder, "font", value.font)
		write_scene_value(builder, "title_color", scene_vec4(value.title_color))
		write_scene_value(builder, "title_background", scene_vec4(value.title_background))
		write_scene_value(builder, "title_size", scene_f32(value.title_size))
		write_scene_value(builder, "title_height", scene_f32(value.title_height))
		write_scene_value(builder, "disclosure_size", scene_f32(value.disclosure_size))
		write_scene_value(builder, "disclosure_margin", scene_f32(value.disclosure_margin))
		write_scene_value(builder, "disclosure_gap", scene_f32(value.disclosure_gap))
		write_scene_value(
			builder,
			"disclosure_corner_radius",
			scene_f32(value.disclosure_corner_radius),
		)
		write_scene_value(builder, "collapsible", scene_bool(value.collapsible))
		write_scene_value(builder, "collapsed", scene_bool(value.collapsed))
	}
	if entity.has_ui_table {
		value := entity.ui_table
		write_scene_section(builder, "ui_table")
		write_scene_value(builder, "columns", fmt.tprintf("%d", value.columns))
		write_scene_value(builder, "column_gap", scene_f32(value.column_gap))
		write_scene_value(builder, "row_gap", scene_f32(value.row_gap))
		write_scene_value(builder, "proportional_columns", scene_bool(value.proportional_columns))
		write_scene_value(builder, "resizable_columns", scene_bool(value.resizable_columns))
		write_scene_value(builder, "min_column_width", scene_f32(value.min_column_width))
	}
	if entity.has_ui_list {
		value := entity.ui_list
		write_scene_section(builder, "ui_list")
		if value.selected !=
		   (shared.Entity_UUID{}) { write_scene_string(builder, "selected", scene_uuid(value.selected)) }
		write_scene_value(builder, "gap", scene_f32(value.gap))
		write_scene_value(builder, "selection_background", scene_vec4(value.selection_background))
		write_scene_value(builder, "hover_background", scene_vec4(value.hover_background))
		write_scene_value(builder, "active_background", scene_vec4(value.active_background))
		write_scene_value(builder, "draggable", scene_bool(value.draggable))
		write_scene_value(builder, "drag_threshold", scene_f32(value.drag_threshold))
		write_scene_value(builder, "drop_edge_fraction", scene_f32(value.drop_edge_fraction))
		write_scene_value(
			builder,
			"drop_target_background",
			scene_vec4(value.drop_target_background),
		)
		write_scene_value(builder, "drop_indicator_color", scene_vec4(value.drop_indicator_color))
		write_scene_value(
			builder,
			"drop_indicator_thickness",
			scene_f32(value.drop_indicator_thickness),
		)
		write_scene_value(builder, "drop_indicator_inset", scene_f32(value.drop_indicator_inset))
		write_scene_value(builder, "tree_enabled", scene_bool(value.tree_enabled))
		write_scene_value(builder, "tree_indent", scene_f32(value.tree_indent))
	}
	if entity.has_ui_progress {
		value := entity.ui_progress
		write_scene_section(builder, "ui_progress")
		write_scene_value(builder, "value", scene_f32(value.value))
		write_scene_value(builder, "maximum", scene_f32(value.maximum))
		write_scene_value(builder, "fill_color", scene_vec4(value.fill_color))
		write_scene_value(builder, "background_color", scene_vec4(value.background_color))
		write_scene_value(builder, "inset", scene_vec4(value.inset))
		write_scene_value(builder, "corner_radius", scene_f32(value.corner_radius))
		write_scene_value(builder, "right_to_left", scene_bool(value.right_to_left))
	}
	if entity.has_ui_viewport {
		value := entity.ui_viewport
		write_scene_section(builder, "ui_viewport")
		if value.camera != (shared.Entity_UUID{}) {
			write_scene_string(builder, "camera", scene_uuid(value.camera))
		}
		if value.root != (shared.Entity_UUID{}) {
			write_scene_string(builder, "root", scene_uuid(value.root))
		}
		if value.resource != (shared.Resource_UUID{}) {
			write_scene_string(builder, "resource", scene_resource_uuid(value.resource))
		}
		write_scene_value(builder, "orbit", scene_vec2(value.orbit))
		write_scene_value(builder, "distance", scene_f32(value.distance))
		write_scene_value(builder, "clear_color", scene_vec4(value.clear_color))
		write_scene_value(builder, "interactive", scene_bool(value.interactive))
	}
	if entity.has_ui_text { write_scene_text(builder, "ui_text", entity.ui_text) }
	if entity.has_ui_button { write_scene_button(builder, entity.ui_button) }
	if entity.has_ui_input { write_scene_input(builder, entity.ui_input) }
	if entity.has_ui_checkbox { write_scene_checkbox(builder, entity.ui_checkbox) }
}

write_scene_stack :: proc(
	builder: ^strings.Builder,
	name: string,
	value: shared.UI_Stack_Component,
) {
	write_scene_section(builder, name)
	write_scene_value(builder, "gap", scene_f32(value.gap))
	write_scene_value(builder, "fill", scene_bool(value.fill))
	write_scene_value(builder, "draggable", scene_bool(value.draggable))
	write_scene_value(builder, "min_size", scene_f32(value.min_size))
}

write_scene_text :: proc(
	builder: ^strings.Builder,
	section: string,
	value: shared.UI_Text_Component,
) {
	write_scene_section(builder, section)
	write_scene_string(builder, "text", value.text)
	write_scene_string(builder, "font", value.font)
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "size", scene_f32(value.size))
	write_scene_string(builder, "alignment", scene_alignment(value.alignment))
}

write_scene_button :: proc(builder: ^strings.Builder, value: shared.UI_Button_Component) {
	write_scene_section(builder, "ui_button")
	write_scene_string(builder, "text", value.text)
	write_scene_string(builder, "font", value.font)
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "size", scene_f32(value.size))
	write_scene_string(builder, "alignment", scene_alignment(value.alignment))
	write_scene_value(builder, "hover_background", scene_vec4(value.hover_background))
	write_scene_value(builder, "active_background", scene_vec4(value.active_background))
	write_scene_value(builder, "hover_color", scene_vec4(value.hover_color))
	write_scene_value(builder, "active_color", scene_vec4(value.active_color))
	write_scene_string(builder, "icon", scene_icon(value.icon))
	write_scene_value(builder, "icon_inset", scene_f32(value.icon_inset))
	write_scene_value(builder, "icon_stroke", scene_f32(value.icon_stroke))
	write_scene_value(builder, "panel_action", scene_bool(value.panel_action))
}

write_scene_input :: proc(builder: ^strings.Builder, value: shared.UI_Input_Component) {
	write_scene_section(builder, "ui_input")
	write_scene_string(builder, "text", value.text)
	write_scene_string(builder, "font", value.font)
	write_scene_string(builder, "prefix", value.prefix)
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "prefix_color", scene_vec4(value.prefix_color))
	write_scene_value(builder, "prefix_background", scene_vec4(value.prefix_background))
	write_scene_value(builder, "size", scene_f32(value.size))
	write_scene_value(builder, "prefix_width", scene_f32(value.prefix_width))
	write_scene_value(builder, "selection_background", scene_vec4(value.selection_background))
	write_scene_value(builder, "focus_border_color", scene_vec4(value.focus_border_color))
	write_scene_value(builder, "invalid_border_color", scene_vec4(value.invalid_border_color))
	write_scene_value(builder, "caret_color", scene_vec4(value.caret_color))
	write_scene_value(builder, "number", scene_f32(value.number))
	write_scene_value(builder, "step", scene_f32(value.step))
	write_scene_value(builder, "minimum", scene_f32(value.minimum))
	write_scene_value(builder, "maximum", scene_f32(value.maximum))
	write_scene_value(builder, "prefix_gap", scene_f32(value.prefix_gap))
	write_scene_value(builder, "prefix_corner_radius", scene_f32(value.prefix_corner_radius))
	write_scene_value(builder, "prefix_text_padding", scene_f32(value.prefix_text_padding))
	write_scene_value(builder, "selection_corner_radius", scene_f32(value.selection_corner_radius))
	write_scene_value(builder, "focus_border_width", scene_f32(value.focus_border_width))
	write_scene_value(builder, "invalid_border_width", scene_f32(value.invalid_border_width))
	write_scene_value(builder, "caret_width", scene_f32(value.caret_width))
	write_scene_value(builder, "caret_inset", scene_f32(value.caret_inset))
	write_scene_value(builder, "read_only", scene_bool(value.read_only))
	write_scene_value(builder, "numeric", scene_bool(value.numeric))
	write_scene_value(builder, "draggable", scene_bool(value.draggable))
	write_scene_value(builder, "has_minimum", scene_bool(value.has_minimum))
	write_scene_value(builder, "has_maximum", scene_bool(value.has_maximum))
}

write_scene_checkbox :: proc(builder: ^strings.Builder, value: shared.UI_Checkbox_Component) {
	write_scene_section(builder, "ui_checkbox")
	write_scene_value(builder, "checked", scene_bool(value.checked))
	write_scene_value(builder, "box_size", scene_f32(value.box_size))
	write_scene_value(builder, "background", scene_vec4(value.background))
	write_scene_value(builder, "checked_background", scene_vec4(value.checked_background))
	write_scene_value(builder, "border_color", scene_vec4(value.border_color))
	write_scene_value(builder, "check_color", scene_vec4(value.check_color))
	write_scene_value(builder, "hover_background", scene_vec4(value.hover_background))
	write_scene_value(builder, "active_background", scene_vec4(value.active_background))
	write_scene_value(builder, "corner_radius", scene_f32(value.corner_radius))
	write_scene_value(builder, "border_width", scene_f32(value.border_width))
	write_scene_value(builder, "check_inset", scene_f32(value.check_inset))
	write_scene_value(builder, "check_corner_radius", scene_f32(value.check_corner_radius))
	write_scene_value(builder, "read_only", scene_bool(value.read_only))
}

write_scene_section :: proc(builder: ^strings.Builder, name: string) {
	strings.write_string(builder, "\n[entities.")
	strings.write_string(builder, name)
	strings.write_string(builder, "]\n")
}

write_scene_value :: proc(builder: ^strings.Builder, key, value: string) {
	strings.write_string(builder, key)
	strings.write_string(builder, " = ")
	strings.write_string(builder, value)
	strings.write_rune(builder, '\n')
}

write_scene_string :: proc(builder: ^strings.Builder, key, value: string) {
	write_scene_value(builder, key, fmt.tprintf("%q", value))
}

scene_uuid :: proc(id: shared.Entity_UUID) -> string {
	buffer: [36]u8
	return fmt.tprintf("%s", shared.entity_uuid_to_string(id, buffer[:]))
}

scene_resource_uuid :: proc(id: shared.Resource_UUID) -> string {
	buffer: [36]u8
	return fmt.tprintf("%s", shared.resource_uuid_to_string(id, buffer[:]))
}

scene_vec2 :: proc(value: shared.Vec2) -> string {
	return fmt.tprintf("[%s, %s]", scene_f32(value.x), scene_f32(value.y))
}

scene_vec4 :: proc(value: shared.Vec4) -> string {
	return fmt.tprintf(
		"[%s, %s, %s, %s]",
		scene_f32(value.x),
		scene_f32(value.y),
		scene_f32(value.z),
		scene_f32(value.w),
	)
}

scene_alignment :: proc(value: shared.UI_Text_Alignment) -> string {
	switch value {
		case .Left:
			return "left"
		case .Center:
			return "center"
		case .Right:
			return "right"
	}
	return "left"
}

scene_icon :: proc(value: shared.UI_Icon) -> string {
	switch value {
		case .Close:
			return "close"
		case .Plus:
			return "plus"
		case .Chevron_Right:
			return "chevron_right"
		case .Chevron_Down:
			return "chevron_down"
		case .None:
			return "none"
	}
	return "none"
}
