package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import "vendor:wgpu"

wgpu_selection_release_targets :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.selection.depth_view != nil {
		wgpu.TextureViewRelease(renderer.selection.depth_view)
	}
	if renderer.selection.depth_texture != nil {
		wgpu.TextureRelease(renderer.selection.depth_texture)
	}
	if renderer.selection.view != nil {
		wgpu.TextureViewRelease(renderer.selection.view)
	}
	if renderer.selection.texture != nil {
		wgpu.TextureRelease(renderer.selection.texture)
	}
	renderer.selection.texture = nil
	renderer.selection.view = nil
	renderer.selection.depth_texture = nil
	renderer.selection.depth_view = nil
	renderer.selection.width = 0
	renderer.selection.height = 0
}

wgpu_selection_destroy :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	wgpu_selection_release_targets(renderer)
	for &readback in renderer.selection.readbacks {
		if readback.buffer != nil {
			if readback.pending &&
			   readback.map_state.completed &&
			   readback.map_state.status == .Success {
				wgpu.BufferUnmap(readback.buffer)
			}
			wgpu.BufferRelease(readback.buffer)
		}
		delete(readback.slot_uuids)
		delete(readback.contained_uuids)
		delete(readback.overlay_uuids)
		readback = {}
	}
	renderer.selection.active_slot = -1
}

wgpu_selection_ensure_targets :: proc(renderer: ^WGPU_Renderer, width, height: u32) -> string {
	if renderer.selection.view != nil &&
	   renderer.selection.depth_view != nil &&
	   renderer.selection.width == width &&
	   renderer.selection.height == height {
		return ""
	}
	wgpu_selection_release_targets(renderer)
	texture, view, texture_err := wgpu_create_post_texture(
		renderer,
		"Scrapbot Selection Identity",
		width,
		height,
		.R32Uint,
		{.RenderAttachment, .CopySrc},
	)
	if texture_err != "" {
		return texture_err
	}
	depth_texture, depth_view, depth_err := wgpu_create_depth_texture(renderer, width, height)
	if depth_err != "" {
		wgpu.TextureViewRelease(view)
		wgpu.TextureRelease(texture)
		return depth_err
	}
	renderer.selection.texture = texture
	renderer.selection.view = view
	renderer.selection.depth_texture = depth_texture
	renderer.selection.depth_view = depth_view
	renderer.selection.width = width
	renderer.selection.height = height
	return ""
}

wgpu_selection_uuid_for_instance :: proc(instance: Render_Instance) -> shared.Entity_UUID {
	if instance.entity.model_owner != (shared.Entity_UUID{}) {
		return instance.entity.model_owner
	}
	return instance.entity.uuid
}

wgpu_selection_append_unique_uuid :: proc(
	values: ^[dynamic]shared.Entity_UUID,
	value: shared.Entity_UUID,
) {
	if values == nil || value == (shared.Entity_UUID{}) {
		return
	}
	for existing in values^ {
		if existing == value {
			return
		}
	}
	append(values, value)
}

wgpu_selection_request_rect :: proc(
	state: ^ui.State,
	output_viewport: ui.Rect,
	render_width, render_height: u32,
) -> (
	request: ui.Rect,
	marquee, toggle, found: bool,
) {
	if state == nil || output_viewport.width <= 0 || output_viewport.height <= 0 {
		return
	}
	if state.editor_box_select_requested {
		request = state.editor_box_select_request_rect
		marquee = true
		toggle = state.editor_box_select_request_toggle_selection
		found = request.width > 0 && request.height > 0
	} else if state.editor_pick_requested {
		request = {state.editor_pick_position.x - 1, state.editor_pick_position.y - 1, 3, 3}
		toggle = state.editor_pick_toggle_selection
		found = true
	}
	if !found {
		return
	}
	x0 := clamp(
		(request.x - output_viewport.x) / output_viewport.width * f32(render_width),
		0,
		f32(render_width),
	)
	y0 := clamp(
		(request.y - output_viewport.y) / output_viewport.height * f32(render_height),
		0,
		f32(render_height),
	)
	x1 := clamp(
		(request.x + request.width - output_viewport.x) /
		output_viewport.width *
		f32(render_width),
		0,
		f32(render_width),
	)
	y1 := clamp(
		(request.y + request.height - output_viewport.y) /
		output_viewport.height *
		f32(render_height),
		0,
		f32(render_height),
	)
	ix0 := u32(math.floor(min(x0, x1)))
	iy0 := u32(math.floor(min(y0, y1)))
	ix1 := u32(math.ceil(max(x0, x1)))
	iy1 := u32(math.ceil(max(y0, y1)))
	if ix1 <= ix0 || iy1 <= iy0 {
		found = false
		return
	}
	request = {f32(ix0), f32(iy0), f32(ix1 - ix0), f32(iy1 - iy0)}
	return
}

wgpu_selection_prepare_readback :: proc(
	renderer: ^WGPU_Renderer,
	world: ^shared.World,
	registry: ^resources.Registry,
	state: ^ui.State,
	request: ui.Rect,
	marquee, toggle: bool,
	output_viewport: ui.Rect,
) -> (
	index: int,
	err: string,
) {
	for offset in 0 ..< len(renderer.selection.readbacks) {
		candidate := (renderer.selection.next_slot + offset) % len(renderer.selection.readbacks)
		if !renderer.selection.readbacks[candidate].pending {
			index = candidate
			break
		}
		if offset == len(renderer.selection.readbacks) - 1 {
			return -1, ""
		}
	}
	readback := &renderer.selection.readbacks[index]
	width := u32(request.width)
	height := u32(request.height)
	row_stride := align_to(width * u32(size_of(u32)), 256)
	required_size := u64(row_stride) * u64(height)
	if readback.buffer == nil || wgpu.BufferGetSize(readback.buffer) < required_size {
		if readback.buffer != nil {
			wgpu.BufferRelease(readback.buffer)
		}
		readback.buffer = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot Selection Readback",
			{.MapRead, .CopyDst},
			required_size,
		)
		if readback.buffer == nil {
			return -1, "failed to create selection readback buffer"
		}
	}
	clear(&readback.slot_uuids)
	resize(&readback.slot_uuids, renderer.render_list.instance_slot_count)
	for instance in renderer.render_list.instances {
		if instance.slot >= 0 && instance.slot < len(readback.slot_uuids) {
			readback.slot_uuids[instance.slot] = wgpu_selection_uuid_for_instance(instance)
		}
	}
	clear(&readback.contained_uuids)
	if marquee {
		contained := editor_box_select_entities(
			world,
			&renderer.render_list,
			registry,
			state.editor_box_select_request_rect,
			output_viewport,
			false,
		)
		defer delete(contained)
		for entity in contained {
			entity_index := int(entity.index)
			if ecs.entity_is_alive(world, entity_index) &&
			   world.entities[entity_index].id == entity {
				wgpu_selection_append_unique_uuid(
					&readback.contained_uuids,
					world.entities[entity_index].uuid,
				)
			}
		}
	}
	clear(&readback.overlay_uuids)
	if marquee {
		for icon in state.editor_scene_icons[:state.editor_scene_icon_count] {
			if ui.rect_contains(state.editor_box_select_request_rect, icon.center) {
				entity_index := int(icon.entity.index)
				if ecs.entity_is_alive(world, entity_index) &&
				   world.entities[entity_index].id == icon.entity {
					wgpu_selection_append_unique_uuid(
						&readback.overlay_uuids,
						world.entities[entity_index].uuid,
					)
				}
			}
		}
	}
	readback.width = width
	readback.height = height
	readback.row_stride = row_stride
	readback.toggle = toggle
	readback.marquee = marquee
	renderer.selection.next_serial += 1
	readback.serial = renderer.selection.next_serial
	readback.world_uuid = world.instance_uuid
	renderer.selection.active_slot = index
	renderer.selection.next_slot = (index + 1) % len(renderer.selection.readbacks)
	state.editor_box_select_requested = false
	state.editor_box_select_request_toggle_selection = false
	state.editor_pick_requested = false
	state.editor_pick_toggle_selection = false
	return index, ""
}

wgpu_selection_uuid_allowed :: proc(
	readback: ^WGPU_Selection_Readback,
	id: shared.Entity_UUID,
) -> bool {
	if readback == nil || id == (shared.Entity_UUID{}) {
		return false
	}
	if !readback.marquee {
		return true
	}
	for contained in readback.contained_uuids {
		if contained == id {
			return true
		}
	}
	return false
}

wgpu_selection_consume :: proc(renderer: ^WGPU_Renderer, world: ^shared.World, state: ^ui.State) {
	if renderer == nil || world == nil || state == nil {
		return
	}
	wgpu.DevicePoll(renderer.device, false)
	for &readback in renderer.selection.readbacks {
		if !readback.pending || !readback.map_state.completed {
			continue
		}
		readback.pending = false
		if readback.map_state.status != .Success {
			continue
		}
		if readback.serial < renderer.selection.latest_applied_serial ||
		   readback.world_uuid != world.instance_uuid {
			wgpu.BufferUnmap(readback.buffer)
			continue
		}
		selected: [dynamic]shared.Entity
		defer delete(selected)
		best_click_uuid: shared.Entity_UUID
		best_click_distance := f32(3.4028235e38)
		mapped := wgpu.BufferGetConstMappedRange(
			readback.buffer,
			0,
			uint(wgpu.BufferGetSize(readback.buffer)),
		)
		if mapped != nil {
			for y in 0 ..< int(readback.height) {
				row := mapped[y * int(readback.row_stride):]
				ids := transmute([^]u32)raw_data(row)
				for x in 0 ..< int(readback.width) {
					encoded := ids[x]
					if encoded == 0 || int(encoded - 1) >= len(readback.slot_uuids) {
						continue
					}
					id := readback.slot_uuids[encoded - 1]
					if !wgpu_selection_uuid_allowed(&readback, id) {
						continue
					}
					if !readback.marquee {
						dx := f32(x) + 0.5 - f32(readback.width) * 0.5
						dy := f32(y) + 0.5 - f32(readback.height) * 0.5
						distance := dx * dx + dy * dy
						if distance < best_click_distance {
							best_click_distance = distance
							best_click_uuid = id
						}
						continue
					}
					if entity_index, found := ecs.entity_index_by_uuid(world, id); found {
						already_selected := false
						for entity in selected {
							if entity == world.entities[entity_index].id {
								already_selected = true
								break
							}
						}
						if !already_selected {
							append(&selected, world.entities[entity_index].id)
						}
					}
				}
			}
		}
		wgpu.BufferUnmap(readback.buffer)
		if !readback.marquee && best_click_uuid != (shared.Entity_UUID{}) {
			if entity_index, found := ecs.entity_index_by_uuid(world, best_click_uuid); found {
				append(&selected, world.entities[entity_index].id)
			}
		}
		if readback.marquee {
			for id in readback.overlay_uuids {
				if entity_index, found := ecs.entity_index_by_uuid(world, id); found {
					append(&selected, world.entities[entity_index].id)
				}
			}
		}
		ui.editor_set_entity_selection(state, world, selected[:], readback.toggle)
		renderer.selection.latest_applied_serial = readback.serial
	}
}

wgpu_selection_encode_draws :: proc(
	renderer: ^WGPU_Renderer,
	pass: wgpu.RenderPassEncoder,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
) -> string {
	if len(batches) == 0 {
		return ""
	}
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, renderer.environment_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		pass,
		0,
		renderer.geometry_vertex_arena.buffer,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		pass,
		renderer.geometry_index_arena.buffer,
		.Uint32,
		0,
		wgpu.WHOLE_SIZE,
	)
	batch_index := 0
	for batch_index < len(batches) {
		batch := batches[batch_index]
		span := wgpu_draw_submission_span(renderer, batches, batch_index)
		material, material_alive := resources.get_material(registry, batch.material)
		if !material_alive {
			return "selection pass references a stale material"
		}
		if material.desc.alpha_mode == .Blend {
			batch_index = span.next_batch
			continue
		}
		material_cached, material_err := wgpu_material_cache(renderer, registry, batch.material)
		if material_err != "" {
			return material_err
		}
		pipeline := renderer.gpu_selection_pipeline
		if material_cached.double_sided {
			pipeline = renderer.gpu_selection_double_sided_pipeline
		}
		if span.mode == .Compact {
			pipeline = renderer.gpu_compact_selection_pipeline
			if material_cached.double_sided {
				pipeline = renderer.gpu_compact_selection_double_sided_pipeline
			}
		}
		wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
		world_bind_group := renderer.gpu_world_bind_group
		if !renderer.gpu_meshlet_supported {
			world_bind_group = batch.world_bind_group
		} else if span.mode != .Classic {
			world_bind_group = renderer.gpu_meshlet_world_bind_group
		}
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, world_bind_group)
		wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cached.bind_group)
		if span.mode == .Compact {
			wgpu.RenderPassEncoderSetVertexBuffer(
				pass,
				0,
				renderer.gpu_compact_visible_buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			for command_offset in 0 ..< span.indirect_count {
				wgpu.RenderPassEncoderDrawIndirect(
					pass,
					renderer.gpu_indirect_buffer,
					u64(span.first_indirect + command_offset) *
					u64(size_of(WGPU_Draw_Indexed_Indirect)),
				)
			}
		} else if span.mode == .Meshlet {
			wgpu.RenderPassEncoderSetVertexBuffer(
				pass,
				0,
				renderer.geometry_vertex_arena.buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			wgpu.RenderPassEncoderMultiDrawIndexedIndirect(
				pass,
				renderer.gpu_meshlet_indirect_buffer,
				u64(span.first_indirect) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
				span.indirect_count,
			)
		} else if span.indirect_count > 1 {
			wgpu.RenderPassEncoderMultiDrawIndexedIndirect(
				pass,
				renderer.gpu_indirect_buffer,
				u64(span.first_indirect) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
				span.indirect_count,
			)
		} else {
			wgpu.RenderPassEncoderDrawIndexedIndirect(
				pass,
				renderer.gpu_indirect_buffer,
				u64(span.first_indirect) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
			)
		}
		batch_index = span.next_batch
	}
	return ""
}

wgpu_selection_encode_transparent :: proc(
	renderer: ^WGPU_Renderer,
	pass: wgpu.RenderPassEncoder,
	registry: ^resources.Registry,
) -> string {
	if len(renderer.transparent_draws) == 0 {
		return ""
	}
	wgpu.RenderPassEncoderSetVertexBuffer(
		pass,
		0,
		renderer.geometry_vertex_arena.buffer,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		pass,
		renderer.geometry_index_arena.buffer,
		.Uint32,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.transparent_world_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, renderer.environment_bind_group)
	for draw, draw_index in renderer.transparent_draws {
		material, material_ok := resources.get_material(registry, draw.material)
		if !material_ok {
			return "selection pass references a stale transparent material"
		}
		geometry, geometry_err := wgpu_geometry_cache(
			renderer,
			registry,
			draw.geometry,
			.Conventional,
		)
		if geometry_err != "" {
			return geometry_err
		}
		geometry_resource, geometry_ok := resources.get_geometry(registry, draw.geometry)
		if !geometry_ok {
			return "selection pass references stale transparent geometry"
		}
		custom, custom_err := wgpu_custom_shader_cache(renderer, registry, material.desc.shader)
		if custom_err != "" {
			return custom_err
		}
		material_cached, material_err := wgpu_material_cache(renderer, registry, draw.material)
		if material_err != "" {
			return material_err
		}
		wgpu.RenderPassEncoderSetPipeline(pass, custom.selection_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cached.bind_group)
		wgpu.RenderPassEncoderSetBindGroup(pass, 3, custom.render_bind_group)
		wgpu.RenderPassEncoderDrawIndexed(
			pass,
			u32(resources.geometry_fallback_index_count(geometry_resource)),
			1,
			u32(geometry.index_range.offset / u64(size_of(u32))),
			i32(geometry.vertex_range.offset / u64(size_of(resources.Vertex))),
			u32(draw_index),
		)
	}
	return ""
}

wgpu_selection_encode :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	world: ^shared.World,
	state: ^ui.State,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	layout: WGPU_Render_Target_Layout,
) -> string {
	wgpu_selection_consume(renderer, world, state)
	request, marquee, toggle, requested := wgpu_selection_request_rect(
		state,
		layout.output_viewport,
		layout.render_width,
		layout.render_height,
	)
	if !requested {
		return ""
	}
	if target_err := wgpu_selection_ensure_targets(
		renderer,
		layout.render_width,
		layout.render_height,
	); target_err != "" {
		return target_err
	}
	readback_index, readback_err := wgpu_selection_prepare_readback(
		renderer,
		world,
		registry,
		state,
		request,
		marquee,
		toggle,
		layout.output_viewport,
	)
	if readback_err != "" || readback_index < 0 {
		return readback_err
	}
	readback := &renderer.selection.readbacks[readback_index]
	for draw in renderer.transparent_draws {
		material, material_ok := resources.get_material(registry, draw.material)
		if !material_ok {
			return "selection pass references a stale transparent material"
		}
		custom, custom_err := wgpu_custom_shader_cache(renderer, registry, material.desc.shader)
		if custom_err != "" {
			return custom_err
		}
		if bind_err := wgpu_ensure_custom_shader_bind_group(renderer, custom); bind_err != "" {
			return bind_err
		}
		if spectral_err := wgpu_encode_spectral_surface(renderer, encoder, custom);
		   spectral_err != "" {
			return spectral_err
		}
	}
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.selection.view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = renderer.selection.depth_view,
		depthLoadOp = .Clear,
		depthStoreOp = .Store,
		depthClearValue = 1,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Editor Selection Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if pass == nil {
		return "failed to begin editor selection pass"
	}
	wgpu.RenderPassEncoderSetViewport(
		pass,
		0,
		0,
		f32(layout.render_width),
		f32(layout.render_height),
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		u32(request.x),
		u32(request.y),
		u32(request.width),
		u32(request.height),
	)
	draw_err := wgpu_selection_encode_draws(renderer, pass, batches, registry)
	if draw_err == "" {
		draw_err = wgpu_selection_encode_transparent(renderer, pass, registry)
	}
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)
	if draw_err != "" {
		return draw_err
	}
	wgpu.CommandEncoderCopyTextureToBuffer(
		encoder,
		&wgpu.TexelCopyTextureInfo {
			texture = renderer.selection.texture,
			origin = {x = u32(request.x), y = u32(request.y)},
			aspect = .All,
		},
		&wgpu.TexelCopyBufferInfo {
			buffer = readback.buffer,
			layout = {bytesPerRow = readback.row_stride, rowsPerImage = readback.height},
		},
		&wgpu.Extent3D{width = readback.width, height = readback.height, depthOrArrayLayers = 1},
	)
	return ""
}

wgpu_selection_after_submit :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || renderer.selection.active_slot < 0 {
		return
	}
	readback := &renderer.selection.readbacks[renderer.selection.active_slot]
	readback.map_state = {}
	readback.pending = true
	wgpu.BufferMapAsync(
		readback.buffer,
		{.Read},
		0,
		uint(wgpu.BufferGetSize(readback.buffer)),
		wgpu.BufferMapCallbackInfo {
			mode = .AllowProcessEvents,
			callback = wgpu_buffer_map_callback,
			userdata1 = &readback.map_state,
		},
	)
	renderer.selection.active_slot = -1
}
