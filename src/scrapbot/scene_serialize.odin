package scrapbot

import ecs "./ecs"
import shared "./shared"
import "core:fmt"
import "core:strings"

write_scene_world_entity :: proc(
	builder: ^strings.Builder,
	world: ^shared.World,
	entity_index: int,
	authoring: ^shared.Scene_Entity = nil,
) -> bool {
	snapshot, ok := ecs.capture_entity_snapshot(world, entity_index)
	if !ok {
		return false
	}
	defer ecs.destroy_entity_snapshot(&snapshot)
	if authoring != nil && authoring.has_ui_theme {
		snapshot.entity.has_ui_theme = true
		snapshot.entity.ui_theme = authoring.ui_theme
		snapshot.entity.ui_theme_resource = authoring.ui_theme_resource
		snapshot.entity.ui_theme_recipes = authoring.ui_theme_recipes
		snapshot.entity.ui_theme_recipe_count = authoring.ui_theme_recipe_count
	}
	write_scene_entity(builder, &snapshot.entity)
	return true
}

write_scene_entity :: proc(builder: ^strings.Builder, entity: ^shared.Scene_Entity) {
	strings.write_string(builder, "[[entities]]\n")
	write_scene_string(builder, "id", scene_uuid(entity.id))
	write_scene_string(builder, "name", entity.name)
	if entity.has_ui_theme && entity.ui_theme_recipe_count > 0 {
		if entity.ui_theme_resource != (shared.Resource_UUID{}) {
			write_scene_string(builder, "ui_theme", scene_resource_uuid(entity.ui_theme_resource))
		} else {
			write_scene_string(builder, "ui_theme", shared.ui_theme_name(entity.ui_theme))
		}
		strings.write_string(builder, "ui_recipes = [")
		for recipe, index in entity.ui_theme_recipes[:entity.ui_theme_recipe_count] {
			if index > 0 {
				strings.write_string(builder, ", ")
			}
			fmt.sbprintf(builder, "%q", shared.ui_theme_recipe_name(recipe))
		}
		strings.write_string(builder, "]\n")
	}
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
		write_scene_value(
			builder,
			"resolution_scale",
			scene_f32(shared.camera_resolution_scale(entity.camera)),
		)
		write_scene_value(
			builder,
			"dynamic_resolution",
			scene_bool(entity.camera.dynamic_resolution),
		)
		write_scene_value(
			builder,
			"dynamic_resolution_min_scale",
			scene_f32(shared.camera_dynamic_resolution_min_scale(entity.camera)),
		)
		write_scene_value(
			builder,
			"dynamic_resolution_target_ms",
			scene_f32(shared.camera_dynamic_resolution_target_ms(entity.camera)),
		)
		write_scene_value(builder, "exposure", scene_f32(shared.camera_exposure(entity.camera)))
		write_scene_value(
			builder,
			"automatic_exposure",
			scene_bool(entity.camera.automatic_exposure),
		)
		write_scene_value(
			builder,
			"automatic_exposure_min",
			scene_f32(shared.camera_automatic_exposure_min(entity.camera)),
		)
		write_scene_value(
			builder,
			"automatic_exposure_max",
			scene_f32(shared.camera_automatic_exposure_max(entity.camera)),
		)
		write_scene_value(
			builder,
			"automatic_exposure_speed",
			scene_f32(shared.camera_automatic_exposure_speed(entity.camera)),
		)
		write_scene_value(
			builder,
			"temporal_antialiasing",
			scene_bool(entity.camera.temporal_antialiasing),
		)
		write_scene_value(
			builder,
			"fast_antialiasing",
			scene_bool(entity.camera.fast_antialiasing),
		)
		write_scene_value(
			builder,
			"ambient_occlusion",
			scene_bool(entity.camera.ambient_occlusion),
		)
		write_scene_value(
			builder,
			"ambient_occlusion_quality",
			scene_f32(shared.camera_ambient_occlusion_quality(entity.camera)),
		)
		write_scene_value(
			builder,
			"screen_space_reflections",
			scene_bool(entity.camera.screen_space_reflections),
		)
		write_scene_value(
			builder,
			"screen_space_reflections_quality",
			scene_f32(shared.camera_screen_space_reflections_quality(entity.camera)),
		)
		write_scene_value(builder, "bloom", scene_bool(entity.camera.bloom))
	}
	if entity.has_world_environment {
		value := entity.world_environment
		write_scene_section(builder, "world_environment")
		write_scene_string(builder, "lighting", value.lighting)
		write_scene_value(builder, "lighting_intensity", scene_f32(value.lighting_intensity))
		write_scene_value(builder, "reflection_intensity", scene_f32(value.reflection_intensity))
		write_scene_value(builder, "lighting_rotation", scene_f32(value.lighting_rotation))
		write_scene_value(builder, "exposure", scene_f32(value.exposure))
		write_scene_value(builder, "background_visible", scene_bool(value.background_visible))
		write_scene_string(builder, "background", value.background)
		write_scene_value(builder, "background_intensity", scene_f32(value.background_intensity))
		write_scene_value(builder, "background_rotation", scene_f32(value.background_rotation))
		write_scene_value(builder, "background_exposure", scene_f32(value.background_exposure))
		write_scene_value(builder, "background_blur", scene_f32(value.background_blur))
		write_scene_value(builder, "sky_tint", scene_vec3(value.sky_tint))
		write_scene_value(builder, "ground_color", scene_vec3(value.ground_color))
		write_scene_value(builder, "turbidity", scene_f32(value.turbidity))
		write_scene_value(builder, "atmosphere_thickness", scene_f32(value.atmosphere_thickness))
		write_scene_value(builder, "horizon_softness", scene_f32(value.horizon_softness))
		write_scene_value(builder, "sun_direction", scene_vec3(value.sun_direction))
		write_scene_value(builder, "sun_color", scene_vec3(value.sun_color))
		write_scene_value(builder, "sun_intensity", scene_f32(value.sun_intensity))
		write_scene_value(builder, "sun_size", scene_f32(value.sun_size))
		write_scene_value(builder, "sun_glow", scene_f32(value.sun_glow))
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
		write_scene_value(builder, "basis", scene_f32(value.basis))
		write_scene_value(builder, "grow", scene_f32(value.grow))
		write_scene_value(builder, "shrink", scene_f32(value.shrink))
		write_scene_string(
			builder,
			"horizontal_alignment",
			scene_ui_alignment(value.horizontal_alignment),
		)
		write_scene_string(
			builder,
			"vertical_alignment",
			scene_ui_alignment(value.vertical_alignment),
		)
		write_scene_value(builder, "tree_item", scene_bool(value.tree_item))
		if value.tree_parent != (shared.Entity_UUID{}) {
			write_scene_string(builder, "tree_parent", scene_uuid(value.tree_parent))
		}
		write_scene_value(builder, "tree_order", fmt.tprintf("%d", value.tree_order))
		write_scene_value(builder, "tree_collapsed", scene_bool(value.tree_collapsed))
		write_scene_value(builder, "stack_order", fmt.tprintf("%d", value.stack_order))
		if value.popup {
			write_scene_value(builder, "popup", scene_bool(true))
		}
		if value.popup_anchor != (shared.Entity_UUID{}) {
			write_scene_string(builder, "popup_anchor", scene_uuid(value.popup_anchor))
		}
		if value.popup_open {
			write_scene_value(builder, "popup_open", scene_bool(true))
		}
		if value.popup_close_on_selection {
			write_scene_value(builder, "popup_close_on_selection", scene_bool(true))
		}
		if value.popup_gap > 0 {
			write_scene_value(builder, "popup_gap", scene_f32(value.popup_gap))
		}
		if value.popup_min_width > 0 {
			write_scene_value(builder, "popup_min_width", scene_f32(value.popup_min_width))
		}
		if value.popup_max_width > 0 {
			write_scene_value(builder, "popup_max_width", scene_f32(value.popup_max_width))
		}
		if value.popup_max_height > 0 {
			write_scene_value(builder, "popup_max_height", scene_f32(value.popup_max_height))
		}
		if value.popup_viewport_margin > 0 {
			write_scene_value(
				builder,
				"popup_viewport_margin",
				scene_f32(value.popup_viewport_margin),
			)
		}
		if entity.has_ui_canvas {
			value := entity.ui_canvas
			write_scene_section(builder, "ui_canvas")
			write_scene_value(builder, "reference_size", scene_vec2(value.reference_size))
			write_scene_string(builder, "scale_mode", scene_ui_canvas_scale_mode(value.scale_mode))
			write_scene_string(
				builder,
				"horizontal_alignment",
				scene_ui_canvas_alignment(value.horizontal_alignment),
			)
			write_scene_string(
				builder,
				"vertical_alignment",
				scene_ui_canvas_alignment(value.vertical_alignment),
			)
			write_scene_value(builder, "safe_area", scene_vec4(value.safe_area))
			write_scene_value(builder, "min_scale", scene_f32(value.min_scale))
			write_scene_value(builder, "max_scale", scene_f32(value.max_scale))
		}
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
		write_scene_value(builder, "disclosure_inset", scene_f32(value.disclosure_inset))
		write_scene_value(builder, "collapsible", scene_bool(value.collapsible))
		write_scene_value(builder, "collapsed", scene_bool(value.collapsed))
		write_scene_value(builder, "movable", scene_bool(value.movable))
	}
	if entity.has_ui_dock_space {
		value := entity.ui_dock_space
		write_scene_section(builder, "ui_dock_space")
		if value.active != (shared.Entity_UUID{}) {
			write_scene_string(builder, "active", scene_uuid(value.active))
		}
		write_scene_string(builder, "font", value.font)
		write_scene_value(builder, "tab_height", scene_f32(value.tab_height))
		write_scene_value(builder, "tab_min_width", scene_f32(value.tab_min_width))
		write_scene_value(builder, "tab_max_width", scene_f32(value.tab_max_width))
		write_scene_value(builder, "tab_gap", scene_f32(value.tab_gap))
		write_scene_value(builder, "tab_padding", scene_f32(value.tab_padding))
		write_scene_value(builder, "tab_size", scene_f32(value.tab_size))
		write_scene_value(builder, "tab_corner_radius", scene_f32(value.tab_corner_radius))
		write_scene_value(builder, "tab_connection_height", scene_f32(value.tab_connection_height))
		write_scene_value(builder, "tab_content_overlap", scene_f32(value.tab_content_overlap))
		write_scene_value(builder, "tab_strip_background", scene_vec4(value.tab_strip_background))
		write_scene_value(builder, "content_background", scene_vec4(value.content_background))
		write_scene_value(builder, "content_corner_radius", scene_f32(value.content_corner_radius))
		write_scene_value(builder, "content_padding", scene_vec4(value.content_padding))
		write_scene_value(builder, "tab_color", scene_vec4(value.tab_color))
		write_scene_value(builder, "tab_active_color", scene_vec4(value.tab_active_color))
		write_scene_value(builder, "tab_background", scene_vec4(value.tab_background))
		write_scene_value(builder, "tab_hover_background", scene_vec4(value.tab_hover_background))
		write_scene_value(
			builder,
			"tab_active_background",
			scene_vec4(value.tab_active_background),
		)
		write_scene_value(builder, "drop_background", scene_vec4(value.drop_background))
		write_scene_value(builder, "draggable", scene_bool(value.draggable))
		write_scene_value(builder, "split_horizontal", scene_bool(value.split_horizontal))
		write_scene_value(builder, "split_vertical", scene_bool(value.split_vertical))
		write_scene_value(builder, "split_ratio", scene_f32(value.split_ratio))
		write_scene_value(builder, "split_edge_fraction", scene_f32(value.split_edge_fraction))
		write_scene_value(builder, "split_gap", scene_f32(value.split_gap))
		write_scene_value(builder, "split_min_size", scene_f32(value.split_min_size))
	}
	if entity.has_ui_dock_item {
		value := entity.ui_dock_item
		write_scene_section(builder, "ui_dock_item")
		write_scene_string(builder, "title", value.title)
		write_scene_value(builder, "movable", scene_bool(value.movable))
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
		if value.filter_input != (shared.Entity_UUID{}) {
			write_scene_string(builder, "filter_input", scene_uuid(value.filter_input))
		}
		write_scene_value(builder, "gap", scene_f32(value.gap))
		write_scene_value(builder, "selection_background", scene_vec4(value.selection_background))
		write_scene_value(builder, "hover_background", scene_vec4(value.hover_background))
		write_scene_value(builder, "active_background", scene_vec4(value.active_background))
		write_scene_value(
			builder,
			"highlight_corner_radius",
			scene_f32(value.highlight_corner_radius),
		)
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
		write_scene_value(builder, "virtualized", scene_bool(value.virtualized))
		write_scene_value(builder, "item_height", scene_f32(value.item_height))
		write_scene_value(builder, "overscan", fmt.tprintf("%d", value.overscan))
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
	if entity.has_ui_icon { write_scene_icon(builder, entity.ui_icon) }
	if entity.has_ui_text { write_scene_text(builder, "ui_text", entity.ui_text) }
	if entity.has_ui_button { write_scene_button(builder, entity.ui_button) }
	if entity.has_ui_input { write_scene_input(builder, entity.ui_input) }
	if entity.has_ui_checkbox { write_scene_checkbox(builder, entity.ui_checkbox) }
	if entity.has_ui_color_picker { write_scene_color_picker(builder, entity.ui_color_picker) }
	if entity.has_ui_action { write_scene_action(builder, entity.ui_action) }
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
	write_scene_value(builder, "reorderable", scene_bool(value.reorderable))
	write_scene_value(builder, "drag_threshold", scene_f32(value.drag_threshold))
	write_scene_value(builder, "drop_indicator_color", scene_vec4(value.drop_indicator_color))
	write_scene_value(
		builder,
		"drop_indicator_thickness",
		scene_f32(value.drop_indicator_thickness),
	)
	write_scene_value(builder, "drop_indicator_inset", scene_f32(value.drop_indicator_inset))
	write_scene_value(builder, "wrap", scene_bool(value.wrap))
	write_scene_value(builder, "line_gap", scene_f32(value.line_gap))
}

write_scene_icon :: proc(builder: ^strings.Builder, value: shared.UI_Icon_Component) {
	write_scene_section(builder, "ui_icon")
	write_scene_string(builder, "icon_set", scene_resource_uuid(value.icon_set))
	write_scene_string(builder, "icon", value.icon)
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "inset", scene_f32(value.inset))
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
	write_scene_value(builder, "wrap", scene_bool(value.wrap))
	write_scene_value(builder, "line_height", scene_f32(value.line_height))
}

write_scene_button :: proc(builder: ^strings.Builder, value: shared.UI_Button_Component) {
	write_scene_section(builder, "ui_button")
	write_scene_string(builder, "text", value.text)
	write_scene_string(builder, "font", value.font)
	if value.popup != (shared.Entity_UUID{}) {
		write_scene_string(builder, "popup", scene_uuid(value.popup))
	}
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "size", scene_f32(value.size))
	write_scene_string(builder, "alignment", scene_alignment(value.alignment))
	write_scene_value(builder, "hover_background", scene_vec4(value.hover_background))
	write_scene_value(builder, "active_background", scene_vec4(value.active_background))
	write_scene_value(builder, "hover_color", scene_vec4(value.hover_color))
	write_scene_value(builder, "active_color", scene_vec4(value.active_color))
	if value.icon_set != (shared.Resource_UUID{}) {
		write_scene_string(builder, "icon_set", scene_resource_uuid(value.icon_set))
	}
	write_scene_string(builder, "icon", value.icon)
	write_scene_string(builder, "icon_position", scene_icon_position(value.icon_position))
	write_scene_value(builder, "icon_size", scene_f32(value.icon_size))
	write_scene_value(builder, "icon_gap", scene_f32(value.icon_gap))
	write_scene_value(builder, "icon_inset", scene_f32(value.icon_inset))
	write_scene_value(builder, "panel_action", scene_bool(value.panel_action))
}

write_scene_input :: proc(builder: ^strings.Builder, value: shared.UI_Input_Component) {
	write_scene_section(builder, "ui_input")
	write_scene_string(builder, "text", value.text)
	write_scene_string(builder, "font", value.font)
	write_scene_string(builder, "prefix", value.prefix)
	if value.icon_set != (shared.Resource_UUID{}) {
		write_scene_string(builder, "icon_set", scene_resource_uuid(value.icon_set))
	}
	write_scene_string(builder, "icon", value.icon)
	write_scene_string(builder, "icon_position", scene_icon_position(value.icon_position))
	write_scene_value(builder, "color", scene_vec4(value.color))
	write_scene_value(builder, "icon_color", scene_vec4(value.icon_color))
	write_scene_value(builder, "prefix_color", scene_vec4(value.prefix_color))
	write_scene_value(builder, "prefix_background", scene_vec4(value.prefix_background))
	write_scene_value(builder, "size", scene_f32(value.size))
	write_scene_value(builder, "icon_size", scene_f32(value.icon_size))
	write_scene_value(builder, "icon_gap", scene_f32(value.icon_gap))
	write_scene_value(builder, "icon_inset", scene_f32(value.icon_inset))
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

write_scene_color_picker :: proc(
	builder: ^strings.Builder,
	value: shared.UI_Color_Picker_Component,
) {
	write_scene_section(builder, "ui_color_picker")
	write_scene_value(builder, "value", scene_vec4(value.value))
	write_scene_value(builder, "hdr", scene_bool(value.hdr))
	write_scene_value(builder, "show_alpha", scene_bool(value.show_alpha))
	write_scene_value(builder, "read_only", scene_bool(value.read_only))
	write_scene_value(builder, "exposure", scene_f32(value.exposure))
	write_scene_value(builder, "maximum_exposure", scene_f32(value.maximum_exposure))
	write_scene_value(builder, "track_height", scene_f32(value.track_height))
	write_scene_value(builder, "gap", scene_f32(value.gap))
	write_scene_value(builder, "thumb_radius", scene_f32(value.thumb_radius))
	write_scene_value(builder, "thumb_color", scene_vec4(value.thumb_color))
	write_scene_value(builder, "thumb_border_color", scene_vec4(value.thumb_border_color))
	write_scene_value(builder, "thumb_border_width", scene_f32(value.thumb_border_width))
	write_scene_value(builder, "checker_light", scene_vec4(value.checker_light))
	write_scene_value(builder, "checker_dark", scene_vec4(value.checker_dark))
}

write_scene_action :: proc(builder: ^strings.Builder, value: shared.UI_Action_Component) {
	write_scene_section(builder, "ui_action")
	write_scene_string(builder, "action", value.action)
	if value.payload != "" {
		write_scene_string(builder, "payload", value.payload)
	}
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

scene_ui_alignment :: proc(value: shared.UI_Alignment) -> string {
	switch value {
		case .Start:
			return "start"
		case .Center:
			return "center"
		case .End:
			return "end"
		case .Stretch:
			return "stretch"
	}
	return "start"
}

scene_ui_canvas_scale_mode :: proc(value: shared.UI_Canvas_Scale_Mode) -> string {
	switch value {
		case .Fit:
			return "fit"
		case .Fill:
			return "fill"
		case .Expand:
			return "expand"
		case .Stretch:
			return "stretch"
		case .Pixel_Perfect:
			return "pixel_perfect"
		case .None:
			return "none"
	}
	return "fit"
}

scene_ui_canvas_alignment :: proc(value: shared.UI_Canvas_Alignment) -> string {
	switch value {
		case .Start:
			return "start"
		case .Center:
			return "center"
		case .End:
			return "end"
	}
	return "start"
}

scene_icon_position :: proc(value: shared.UI_Icon_Position) -> string {
	switch value {
		case .Leading:
			return "leading"
		case .Trailing:
			return "trailing"
	}
	return "leading"
}
