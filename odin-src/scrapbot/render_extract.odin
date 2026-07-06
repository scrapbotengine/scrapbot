package main

Render_Extract_Error :: enum {
	None,
	Invalid_Scene,
}

Render_Extract_Result :: struct {
	renderables:          int,
	legacy_cubes:         int,
	geometry_primitives:  int,
	render_batches:       int,
	cameras:              int,
	directional_lights:   int,
	ui_rects:             int,
	ui_texts:             int,
	shadow_casters:       int,
	shadow_receivers:     int,
}

Render_Batch_Key :: struct {
	primitive:       string,
	segments:        int,
	rings:           int,
	casts_shadow:    bool,
	receives_shadow: bool,
}

render_extract_scene :: proc(world: Runtime_World) -> (Render_Extract_Result, Render_Extract_Error) {
	result := Render_Extract_Result{}
	batches := make([dynamic]Render_Batch_Key)
	defer delete(batches)

	cursor := 0
	for {
		entity, found := runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID}, &cursor)
		if !found {
			break
		}

			casts_shadow := render_entity_has_component(world, entity, SHADOW_CASTER_COMPONENT_ID)
			receives_shadow := render_entity_has_component(world, entity, SHADOW_RECEIVER_COMPONENT_ID)

			has_geometry := render_entity_has_component(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID)
			has_material := render_entity_has_component(world, entity, SURFACE_MATERIAL_COMPONENT_ID)
			has_legacy_cube := render_entity_has_component(world, entity, CUBE_RENDERER_COMPONENT_ID)
		if has_geometry && has_material {
			primitive_value, primitive_err := runtime_world_get_component_field_value(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID, "primitive")
			segments_value, segments_err := runtime_world_get_component_field_value(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID, "segments")
			rings_value, rings_err := runtime_world_get_component_field_value(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID, "rings")
			if primitive_err != .None || segments_err != .None || rings_err != .None ||
			   primitive_value.value_type != .String ||
			   segments_value.value_type != .Int ||
			   rings_value.value_type != .Int {
				return result, .Invalid_Scene
			}
			primitive, primitive_ok := render_normalize_primitive(primitive_value.string_value)
			if !primitive_ok {
				return result, .Invalid_Scene
			}
			result.renderables += 1
			result.geometry_primitives += 1
			render_count_shadow_flags(&result, casts_shadow, receives_shadow)
			render_record_batch(&batches, Render_Batch_Key{
				primitive = primitive,
				segments = segments_value.int_value,
				rings = rings_value.int_value,
				casts_shadow = casts_shadow,
				receives_shadow = receives_shadow,
			})
			continue
		}

		if has_legacy_cube {
			result.renderables += 1
			result.legacy_cubes += 1
			render_count_shadow_flags(&result, casts_shadow, receives_shadow)
			render_record_batch(&batches, Render_Batch_Key{
				primitive = "box",
				casts_shadow = casts_shadow,
				receives_shadow = receives_shadow,
			})
		}
	}

	result.cameras = render_count_query(world, []string{TRANSFORM_COMPONENT_ID, CAMERA_COMPONENT_ID})
	result.directional_lights = render_count_query(world, []string{DIRECTIONAL_LIGHT_COMPONENT_ID})
	result.ui_rects = render_count_query(world, []string{UI_RECT_COMPONENT_ID})
	result.ui_texts = render_count_query(world, []string{UI_TEXT_COMPONENT_ID})
	result.render_batches = len(batches)
	return result, .None
}

render_count_shadow_flags :: proc(result: ^Render_Extract_Result, casts_shadow, receives_shadow: bool) {
	if casts_shadow {
		result.shadow_casters += 1
	}
	if receives_shadow {
		result.shadow_receivers += 1
	}
}

render_record_batch :: proc(batches: ^[dynamic]Render_Batch_Key, key: Render_Batch_Key) {
	for existing in batches^ {
		if render_batch_keys_equal(existing, key) {
			return
		}
	}
	append(batches, key)
}

render_batch_keys_equal :: proc(left, right: Render_Batch_Key) -> bool {
	return left.primitive == right.primitive &&
		left.segments == right.segments &&
		left.rings == right.rings &&
		left.casts_shadow == right.casts_shadow &&
		left.receives_shadow == right.receives_shadow
}

render_entity_has_component :: proc(world: Runtime_World, entity: Entity_Handle, component_id: string) -> bool {
	has_component, err := runtime_world_has_component(world, entity, component_id)
	return err == .None && has_component
}

render_count_query :: proc(world: Runtime_World, component_ids: []string) -> int {
	count := 0
	cursor := 0
	for {
		_, found := runtime_world_query_next(world, component_ids, &cursor)
		if !found {
			break
		}
		count += 1
	}
	return count
}

render_normalize_primitive :: proc(value: string) -> (string, bool) {
	switch value {
	case "box":
		return "box", true
	case "plane":
		return "plane", true
	case "sphere":
		return "sphere", true
	case "uv_sphere", "uvsphere":
		return "uv_sphere", true
	case "ico_sphere", "icosphere":
		return "ico_sphere", true
	}
	return "", false
}
