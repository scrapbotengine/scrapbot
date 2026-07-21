package extension

import raw "../extension_api"
import "core:testing"

@(test)
test_system_trampoline_invokes_contextless_callback_with_project_userdata :: proc(t: ^testing.T) {
	called := false
	binding := System_Binding {
		callback = test_contextless_system,
		userdata = &called,
	}
	ctx := raw.System_Context {
		userdata = &binding,
	}
	err := system_trampoline(&ctx)
	testing.expect(t, err == nil)
	testing.expect(t, called)
}

test_contextless_system :: proc "contextless" (ctx: ^System_Context) -> cstring {
	if ctx == nil || ctx.userdata == nil {
		return "missing test userdata"
	}
	called := cast(^bool)ctx.userdata
	called^ = true
	return nil
}

@(test)
test_typed_custom_field_helpers_preserve_schema_metadata_and_payload_shapes :: proc(
	t: ^testing.T,
) {
	component := Component {
		name = "test.settings",
	}
	number_field := Number_Field {
		component = component,
		name = "rate",
	}
	vec2_field := Vec2_Field {
		component = component,
		name = "offset",
	}
	vec3_field := Vec3_Field {
		component = component,
		name = "direction",
	}
	vec4_field := Vec4_Field {
		component = component,
		name = "weights",
	}
	color_field := Color_Field(Vec4_Field{component = component, name = "tint"})

	number_definition := number_draggable(number_field, 0.25, 0, 20)
	testing.expect(t, number_definition.field_type == .Number)
	testing.expect(t, number_definition.draggable == 1)
	testing.expect(t, number_definition.step == 0.25)
	testing.expect(t, number_definition.has_minimum == 1 && number_definition.minimum == 0)
	testing.expect(t, number_definition.has_maximum == 1 && number_definition.maximum == 20)
	testing.expect(t, vec2(vec2_field).field_type == .Vec2)
	testing.expect(t, vec3(vec3_field).field_type == .Vec3)
	testing.expect(t, vec4(vec4_field).field_type == .Vec4)
	testing.expect(t, color(color_field).field_type == .Color)

	numbers := [?]Component_Number_Field{number_value(number_field, 12.5)}
	vec2s := [?]Component_Vec2_Field{vec2_value(vec2_field, {1, 2})}
	vec3s := [?]Component_Vec3_Field{vec3_value(vec3_field, {3, 4, 5})}
	vec4s := [?]Component_Vec4_Field {
		vec4_value(vec4_field, {6, 7, 8, 9}),
		color_value(color_field, {0.1, 0.2, 0.3, 1}),
	}
	payload := payload(component, vec3s[:], numbers[:], vec2s[:], vec4s[:])
	testing.expect(t, payload.number_field_count == 1)
	testing.expect(t, payload.vec2_field_count == 1)
	testing.expect(t, payload.vec3_field_count == 1)
	testing.expect(t, payload.vec4_field_count == 2)
	testing.expect(t, payload.number_fields[0].value == 12.5)
	testing.expect(t, payload.vec2_fields[0].value == Vec2{1, 2})
	testing.expect(t, payload.vec3_fields[0].value == Vec3{3, 4, 5})
	testing.expect(t, payload.vec4_fields[1].value == Vec4{0.1, 0.2, 0.3, 1})
}

@(test)
test_query_chunk_helpers_preserve_lanes_and_bound_write_masks :: proc(t: ^testing.T) {
	component := Component {
		name = "test.motion",
	}
	velocity := Vec3_Field {
		component = component,
		name = "velocity",
	}
	descriptor := query([]Component{Transform_Component, component})
	chunk: Query_Chunk
	testing.expect(t, init_query_chunk(&chunk, descriptor))

	transforms: [5]Transform
	values := [5]Vec3{{1, 2, 3}, {4, 5, 6}, {7, 8, 9}, {10, 11, 12}, {13, 14, 15}}
	transform_binding, transform_ok := bind_transform(&chunk, transforms[:], .Write)
	_, velocity_ok := bind_vec3(&chunk, velocity, values[:])
	testing.expect(t, transform_ok && velocity_ok)
	testing.expect(t, chunk.desc.capacity == 5)

	packed := load_vec3x4(values[:])
	x := transmute([4]f32)packed.x
	y := transmute([4]f32)packed.y
	z := transmute([4]f32)packed.z
	testing.expect(t, x == [4]f32{1, 4, 7, 10})
	testing.expect(t, y == [4]f32{2, 5, 8, 11})
	testing.expect(t, z == [4]f32{3, 6, 9, 12})

	chunk.desc.count = 5
	testing.expect(t, chunk_write_mask(&chunk, transform_binding, 0xff))
	testing.expect(t, chunk.bindings[int(transform_binding)].write_mask == 0x1f)
	testing.expect(t, !chunk_write_mask(&chunk, Query_Chunk_Binding_Handle(99), 1))
}
