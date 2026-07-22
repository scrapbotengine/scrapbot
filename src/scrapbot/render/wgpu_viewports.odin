package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import wgpu "vendor:wgpu"

WGPU_Viewport_Draw :: struct {
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	model: Mat4,
}

wgpu_encode_embedded_viewports :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	state: ^ui.State,
	registry: ^resources.Registry,
	world: ^shared.World,
	render_list: ^shared.Render_List,
) -> string {
	if renderer != nil {
		renderer.ui_viewport_active_targets = 0
		renderer.ui_viewport_target_pixels = 0
	}
	if renderer == nil || encoder == nil || state == nil || registry == nil {
		return ""
	}
	count := min(state.viewport_surface_count, ui.MAX_EMBEDDED_VIEWPORTS)
	renderer.ui_viewport_active_targets = count
	for layer in 0 ..< count {
		surface := state.viewport_surfaces[layer]
		target_width, target_height := wgpu_viewport_target_size(surface.rect)
		if err := wgpu_resize_viewport_target(renderer, layer, target_width, target_height);
		   err != "" {
			return err
		}
		renderer.ui_viewport_target_pixels += u64(target_width) * u64(target_height)
		aspect := f32(target_width) / f32(target_height)
		if surface.component.resource != (shared.Resource_UUID{}) {
			handle, found := resources.model_handle_by_uuid(registry, surface.component.resource)
			if found {
				model, alive := resources.get_model(registry, handle)
				if !alive {
					wgpu_invalidate_viewport_cache(renderer, layer)
					continue
				}
				if wgpu_viewport_cache_matches(
					   renderer,
					   layer,
					   surface.component,
					   aspect,
					   model.version,
					   registry.geometry_topology_revision,
					   registry.texture_revision,
					   registry.material_revision,
				   ) &&
				   renderer.ui_viewport_cache_warmup_frames[layer] == 0 {
					if err := wgpu_encode_cached_viewport_layer(renderer, encoder, layer);
					   err != "" {
						return err
					}
					continue
				}
				if err := wgpu_encode_model_viewport(
					renderer,
					encoder,
					registry,
					model,
					surface.component,
					aspect,
					layer,
				); err != "" {
					return err
				}
				wgpu_store_viewport_cache(
					renderer,
					layer,
					surface.component,
					aspect,
					model.version,
					registry.geometry_topology_revision,
					registry.texture_revision,
					registry.material_revision,
				)
				continue
			}
			if material_handle, material_found := resources.material_by_uuid(
				registry,
				surface.component.resource,
			); material_found {
				material, alive := resources.get_material(registry, material_handle)
				if !alive {
					wgpu_invalidate_viewport_cache(renderer, layer)
					continue
				}
				if wgpu_viewport_cache_matches(
					   renderer,
					   layer,
					   surface.component,
					   aspect,
					   material.version,
					   0,
					   registry.texture_revision,
					   registry.material_revision,
				   ) &&
				   renderer.ui_viewport_cache_warmup_frames[layer] == 0 {
					if err := wgpu_encode_cached_viewport_layer(renderer, encoder, layer);
					   err != "" {
						return err
					}
					continue
				}
				if err := wgpu_encode_material_viewport(
					renderer,
					encoder,
					registry,
					material_handle,
					surface.component,
					aspect,
					layer,
				); err != "" {
					return err
				}
				wgpu_store_viewport_cache(
					renderer,
					layer,
					surface.component,
					aspect,
					material.version,
					0,
					registry.texture_revision,
					registry.material_revision,
				)
				continue
			}
			if texture_handle, texture_found := resources.texture_handle_by_uuid(
				registry,
				surface.component.resource,
			); texture_found {
				texture, alive := resources.get_texture(registry, texture_handle)
				if !alive {
					wgpu_invalidate_viewport_cache(renderer, layer)
					continue
				}
				if wgpu_viewport_cache_matches(
					   renderer,
					   layer,
					   surface.component,
					   aspect,
					   texture.version,
					   0,
					   registry.texture_revision,
					   0,
				   ) &&
				   renderer.ui_viewport_cache_warmup_frames[layer] == 0 {
					if err := wgpu_encode_cached_viewport_layer(renderer, encoder, layer);
					   err != "" {
						return err
					}
					continue
				}
				if err := wgpu_encode_texture_viewport(
					renderer,
					encoder,
					registry,
					texture_handle,
					surface.component,
					layer,
				); err != "" {
					return err
				}
				wgpu_store_viewport_cache(
					renderer,
					layer,
					surface.component,
					aspect,
					texture.version,
					0,
					registry.texture_revision,
					0,
				)
				continue
			}
			wgpu_invalidate_viewport_cache(renderer, layer)
		} else if err := wgpu_encode_world_viewport(
			renderer,
			encoder,
			registry,
			world,
			render_list,
			surface.component,
			layer,
		); err != "" {
			return err
		} else {
			wgpu_invalidate_viewport_cache(renderer, layer)
		}
	}
	for layer in count ..< ui.MAX_EMBEDDED_VIEWPORTS {
		wgpu_invalidate_viewport_cache(renderer, layer)
	}
	return ""
}

wgpu_viewport_target_dimension :: proc(value: f32) -> u32 {
	rounded := u32(max(math.ceil(value), f32(WGPU_VIEWPORT_TARGET_MIN_SIZE)))
	rounded =
		((rounded + WGPU_VIEWPORT_TARGET_GRANULARITY - 1) / WGPU_VIEWPORT_TARGET_GRANULARITY) *
		WGPU_VIEWPORT_TARGET_GRANULARITY
	return min(rounded, WGPU_VIEWPORT_TARGET_MAX_SIZE)
}

wgpu_viewport_target_size :: proc(rect: ui.Rect) -> (u32, u32) {
	return wgpu_viewport_target_dimension(rect.width), wgpu_viewport_target_dimension(rect.height)
}

wgpu_invalidate_viewport_cache :: proc(renderer: ^WGPU_Renderer, layer: int) {
	if renderer == nil || layer < 0 || layer >= ui.MAX_EMBEDDED_VIEWPORTS {
		return
	}
	renderer.ui_viewport_cache_valid[layer] = false
	renderer.ui_viewport_cache_warmup_frames[layer] = 0
}

wgpu_viewport_cache_matches :: proc(
	renderer: ^WGPU_Renderer,
	layer: int,
	component: shared.UI_Viewport_Component,
	aspect: f32,
	resource_version: u32,
	geometry_revision, texture_revision, material_revision: u64,
) -> bool {
	return(
		renderer != nil &&
		layer >= 0 &&
		layer < ui.MAX_EMBEDDED_VIEWPORTS &&
		renderer.ui_viewport_cache_valid[layer] &&
		renderer.ui_viewport_cached_components[layer] == component &&
		renderer.ui_viewport_cached_aspects[layer] == aspect &&
		renderer.ui_viewport_cached_resource_versions[layer] == resource_version &&
		renderer.ui_viewport_cached_geometry_revisions[layer] == geometry_revision &&
		renderer.ui_viewport_cached_texture_revisions[layer] == texture_revision &&
		renderer.ui_viewport_cached_material_revisions[layer] == material_revision \
	)
}

wgpu_store_viewport_cache :: proc(
	renderer: ^WGPU_Renderer,
	layer: int,
	component: shared.UI_Viewport_Component,
	aspect: f32,
	resource_version: u32,
	geometry_revision, texture_revision, material_revision: u64,
) {
	if renderer == nil || layer < 0 || layer >= ui.MAX_EMBEDDED_VIEWPORTS {
		return
	}
	cache_key_matches := wgpu_viewport_cache_matches(
		renderer,
		layer,
		component,
		aspect,
		resource_version,
		geometry_revision,
		texture_revision,
		material_revision,
	)
	if !cache_key_matches {
		renderer.ui_viewport_cache_warmup_frames[layer] = 2
	}
	renderer.ui_viewport_cached_components[layer] = component
	renderer.ui_viewport_cached_resource_versions[layer] = resource_version
	renderer.ui_viewport_cached_aspects[layer] = aspect
	renderer.ui_viewport_cached_geometry_revisions[layer] = geometry_revision
	renderer.ui_viewport_cached_texture_revisions[layer] = texture_revision
	renderer.ui_viewport_cached_material_revisions[layer] = material_revision
	renderer.ui_viewport_cache_valid[layer] = true
	if renderer.ui_viewport_cache_warmup_frames[layer] > 0 {
		renderer.ui_viewport_cache_warmup_frames[layer] -= 1
	}
}

wgpu_encode_cached_viewport_layer :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	layer: int,
) -> string {
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.ui_viewport_layer_views[layer],
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Cached Embedded Viewport Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
		},
	)
	if pass == nil {
		return "failed to preserve cached embedded viewport layer"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderEnd(pass)
	renderer.ui_viewport_cache_hit_count += 1
	return ""
}

wgpu_encode_model_viewport :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	model: ^resources.Model,
	component: shared.UI_Viewport_Component,
	aspect: f32,
	layer: int,
) -> string {
	if layer < 0 || layer >= ui.MAX_EMBEDDED_VIEWPORTS {
		return "embedded viewport layer is out of range"
	}
	node_models := make([]Mat4, len(model.nodes), context.temp_allocator)
	resolved := make([]bool, len(model.nodes), context.temp_allocator)
	resolving := make([]bool, len(model.nodes), context.temp_allocator)
	draws: [WGPU_MAX_INSTANCES]WGPU_Viewport_Draw
	draw_count := 0
	minimum := shared.Vec3{3.402823e38, 3.402823e38, 3.402823e38}
	maximum := shared.Vec3{-3.402823e38, -3.402823e38, -3.402823e38}
	has_bounds := false
	for node, node_index in model.nodes {
		if node.mesh_index < 0 || int(node.mesh_index) >= len(model.meshes) {
			continue
		}
		node_model, ok := wgpu_viewport_node_model(
			model,
			node_index,
			node_models,
			resolved,
			resolving,
		)
		if !ok {
			continue
		}
		mesh := model.meshes[node.mesh_index]
		for primitive in mesh.primitives {
			if draw_count >= len(draws) {
				break
			}
			geometry, geometry_alive := resources.get_geometry(registry, primitive.geometry)
			if !geometry_alive {
				continue
			}
			material := primitive.material
			if _, material_alive := resources.get_material(registry, material); !material_alive {
				material, _ = resources.material_by_name(registry, "default")
			}
			draws[draw_count] = {
				geometry = primitive.geometry,
				material = material,
				model = node_model,
			}
			draw_count += 1
			for x in 0 ..< 2 {
				for y in 0 ..< 2 {
					for z in 0 ..< 2 {
						point := pick_transform_point(
							node_model,
							{
								geometry.bounds.min.x if x == 0 else geometry.bounds.max.x,
								geometry.bounds.min.y if y == 0 else geometry.bounds.max.y,
								geometry.bounds.min.z if z == 0 else geometry.bounds.max.z,
							},
						)
						minimum = {
							min(minimum.x, point.x),
							min(minimum.y, point.y),
							min(minimum.z, point.z),
						}
						maximum = {
							max(maximum.x, point.x),
							max(maximum.y, point.y),
							max(maximum.z, point.z),
						}
						has_bounds = true
					}
				}
			}
		}
	}
	if draw_count == 0 || !has_bounds {
		return ""
	}
	center := shared.Vec3 {
		(minimum.x + maximum.x) * 0.5,
		(minimum.y + maximum.y) * 0.5,
		(minimum.z + maximum.z) * 0.5,
	}
	extent := shared.Vec3{maximum.x - minimum.x, maximum.y - minimum.y, maximum.z - minimum.z}
	radius := max(
		math.sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z) * 0.5,
		f32(0.05),
	)
	pitch := clamp(component.orbit.x, f32(-1.45), f32(1.45))
	yaw := component.orbit.y
	direction := shared.Vec3 {
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		math.cos(pitch) * math.cos(yaw),
	}
	distance := radius * max(component.distance, f32(1.1))
	eye := shared.Vec3 {
		center.x + direction.x * distance,
		center.y + direction.y * distance,
		center.z + direction.z * distance,
	}
	view := mat4_look_at(eye, center, {0, 1, 0})
	projection := mat4_perspective(
		math.to_radians(f32(38)),
		aspect,
		max(radius * 0.01, f32(0.001)),
		distance + radius * 4,
	)
	view_projection := mat4_mul(projection, view)
	uniform: WGPU_Render_Uniform
	uniform.camera_position = {eye.x, eye.y, eye.z, 1}
	uniform.ambient = {0.28, 0.30, 0.34, 1}
	uniform.directional_direction_intensity[0] = {-0.45, -0.80, -0.35, 1.4}
	uniform.directional_color[0] = {1.0, 0.96, 0.90, 1}
	uniform.light_counts[0] = 1
	for draw, index in draws[:draw_count] {
		material, _ := resources.get_material(registry, draw.material)
		uniform.model[index] = draw.model
		uniform.normal_model[index] = draw.model
		uniform.mvp[index] = mat4_mul(view_projection, draw.model)
		uniform.color[index] = {
			material.desc.base_color.x,
			material.desc.base_color.y,
			material.desc.base_color.z,
			material.desc.base_color.w,
		}
		uniform.emissive[index] = {
			material.desc.emissive.x,
			material.desc.emissive.y,
			material.desc.emissive.z,
			0,
		}
	}
	return wgpu_encode_viewport_draws(
		renderer,
		encoder,
		registry,
		draws[:draw_count],
		&uniform,
		component.clear_color,
		layer,
	)
}

wgpu_preview_camera :: proc(
	component: shared.UI_Viewport_Component,
	aspect, radius: f32,
) -> (
	Mat4,
	shared.Vec3,
) {
	pitch := clamp(component.orbit.x, f32(-1.45), f32(1.45))
	yaw := component.orbit.y
	direction := shared.Vec3 {
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		math.cos(pitch) * math.cos(yaw),
	}
	distance := radius * max(component.distance, f32(1.1))
	eye := shared.Vec3{direction.x * distance, direction.y * distance, direction.z * distance}
	view := mat4_look_at(eye, {}, {0, 1, 0})
	projection := mat4_perspective(
		math.to_radians(f32(38)),
		aspect,
		max(radius * 0.01, f32(0.001)),
		distance + radius * 4,
	)
	return mat4_mul(projection, view), eye
}

wgpu_apply_preview_lighting :: proc(uniform: ^WGPU_Render_Uniform) {
	uniform.ambient = {0.28, 0.30, 0.34, 1}
	uniform.directional_direction_intensity[0] = {-0.45, -0.80, -0.35, 1.4}
	uniform.directional_color[0] = {1.0, 0.96, 0.90, 1}
	uniform.light_counts[0] = 1
}

wgpu_encode_material_viewport :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	handle: shared.Material_Handle,
	component: shared.UI_Viewport_Component,
	aspect: f32,
	layer: int,
) -> string {
	material, alive := resources.get_material(registry, handle)
	if !alive {
		return "material preview handle is stale"
	}
	material_cache, material_err := wgpu_material_cache(renderer, registry, handle)
	if material_err != "" {
		return material_err
	}
	model := mat4_identity()
	uniform: WGPU_Render_Uniform
	wgpu_apply_preview_lighting(&uniform)
	view_projection, eye := wgpu_preview_camera(component, aspect, 0.75)
	uniform.camera_position = {eye.x, eye.y, eye.z, 1}
	uniform.model[0] = model
	uniform.normal_model[0] = model
	uniform.mvp[0] = mat4_mul(view_projection, model)
	uniform.color[0] = {
		material.desc.base_color.x,
		material.desc.base_color.y,
		material.desc.base_color.z,
		material.desc.base_color.w,
	}
	uniform.emissive[0] = {
		material.desc.emissive.x,
		material.desc.emissive.y,
		material.desc.emissive.z,
		0,
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.ui_viewport_uniform_buffers[layer],
		0,
		&uniform,
		uint(size_of(WGPU_Render_Uniform)),
	)
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.ui_viewport_layer_views[layer],
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {
			f64(component.clear_color.x),
			f64(component.clear_color.y),
			f64(component.clear_color.z),
			f64(component.clear_color.w),
		},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = renderer.ui_viewport_depth_views[layer],
		depthLoadOp = .Clear,
		depthStoreOp = .Store,
		depthClearValue = 1,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Material Preview Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if pass == nil {
		return "failed to begin material preview pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		0,
		0,
		f32(renderer.ui_viewport_widths[layer]),
		f32(renderer.ui_viewport_heights[layer]),
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		0,
		0,
		renderer.ui_viewport_widths[layer],
		renderer.ui_viewport_heights[layer],
	)
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.ui_viewport_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.ui_viewport_bind_groups[layer])
	wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cache.bind_group)
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, renderer.environment_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		pass,
		0,
		renderer.ui_viewport_preview_vertex_buffer,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		pass,
		renderer.ui_viewport_preview_index_buffer,
		.Uint32,
		0,
		wgpu.WHOLE_SIZE,
	)
	wgpu.RenderPassEncoderDrawIndexed(pass, renderer.ui_viewport_preview_index_count, 1, 0, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	renderer.ui_viewport_redraw_count += 1
	return ""
}

wgpu_encode_texture_viewport :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	handle: shared.Texture_Handle,
	component: shared.UI_Viewport_Component,
	layer: int,
) -> string {
	texture, alive := resources.get_texture(registry, handle)
	if !alive {
		return "texture preview handle is stale"
	}
	texture_cache, texture_err := wgpu_texture_cache(renderer, registry, handle)
	if texture_err != "" {
		return texture_err
	}
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = texture_cache.view},
		{binding = 1, sampler = renderer.material_sampler},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Texture Preview Bind Group",
			layout = renderer.ui_viewport_texture_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if bind_group == nil {
		return "failed to create texture preview bind group"
	}
	defer wgpu.BindGroupRelease(bind_group)
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.ui_viewport_layer_views[layer],
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {
			f64(component.clear_color.x),
			f64(component.clear_color.y),
			f64(component.clear_color.z),
			f64(component.clear_color.w),
		},
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Texture Preview Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
		},
	)
	if pass == nil {
		return "failed to begin texture preview pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	target_width := f32(renderer.ui_viewport_widths[layer])
	target_height := f32(renderer.ui_viewport_heights[layer])
	target_aspect := target_width / max(target_height, f32(1))
	texture_aspect := f32(texture.desc.width) / f32(max(texture.desc.height, u32(1)))
	draw_width, draw_height := target_width, target_height
	draw_x, draw_y := f32(0), f32(0)
	if texture_aspect > target_aspect {
		draw_height = target_width / texture_aspect
		draw_y = (target_height - draw_height) * 0.5
	} else {
		draw_width = target_height * texture_aspect
		draw_x = (target_width - draw_width) * 0.5
	}
	wgpu.RenderPassEncoderSetViewport(pass, draw_x, draw_y, draw_width, draw_height, 0, 1)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		0,
		0,
		renderer.ui_viewport_widths[layer],
		renderer.ui_viewport_heights[layer],
	)
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.ui_viewport_texture_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, bind_group)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	renderer.ui_viewport_redraw_count += 1
	return ""
}

wgpu_encode_world_viewport :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	world: ^shared.World,
	render_list: ^shared.Render_List,
	component: shared.UI_Viewport_Component,
	layer: int,
) -> string {
	if world == nil || render_list == nil {
		return ""
	}
	draws: [WGPU_MAX_INSTANCES]WGPU_Viewport_Draw
	draw_count := 0
	for instance in render_list.instances {
		if component.root != (shared.Entity_UUID{}) &&
		   instance.entity.uuid != component.root &&
		   !ecs.render_instance_descends_from(world, instance, component.root) {
			continue
		}
		if draw_count >= len(draws) {
			break
		}
		draws[draw_count] = {
			geometry = instance.geometry.handle,
			material = instance.material.handle,
			model = wgpu_build_model(instance.transform),
		}
		draw_count += 1
	}
	if draw_count == 0 {
		return ""
	}
	camera := render_list.camera
	has_camera := render_list.has_camera
	if component.camera != (shared.Entity_UUID{}) {
		if entity_index, found := ecs.entity_index_by_uuid(world, component.camera); found {
			entity := world.entities[entity_index]
			if entity.camera_index >= 0 &&
			   entity.camera_index < len(world.cameras) &&
			   entity.transform_index >= 0 &&
			   entity.transform_index < len(world.transforms) {
				transform, resolved := ecs.resolve_world_transform(world, entity_index)
				if resolved {
					camera = {
						entity = entity,
						transform = transform,
						camera = world.cameras[entity.camera_index],
					}
					has_camera = true
				}
			}
		}
	}
	virtual_width := renderer.ui_viewport_widths[layer]
	virtual_height := renderer.ui_viewport_heights[layer]
	view_projection := wgpu_build_view_projection(
		camera,
		has_camera,
		virtual_width,
		virtual_height,
	)
	uniform: WGPU_Render_Uniform
	camera_position := shared.Vec3{0, 2, 6}
	if has_camera {
		camera_position = camera.transform.position
	}
	uniform.camera_position = {camera_position.x, camera_position.y, camera_position.z, 1}
	uniform.ambient = {render_list.ambient.x, render_list.ambient.y, render_list.ambient.z, 1}
	for light, index in render_list.directional_lights[:render_list.directional_light_count] {
		uniform.directional_direction_intensity[index] = {
			light.light.direction.x,
			light.light.direction.y,
			light.light.direction.z,
			light.light.intensity,
		}
		uniform.directional_color[index] = {
			light.light.color.x,
			light.light.color.y,
			light.light.color.z,
			1,
		}
	}
	for light, index in render_list.point_lights[:render_list.point_light_count] {
		uniform.point_position_range[index] = {
			light.position.x,
			light.position.y,
			light.position.z,
			light.light.range,
		}
		uniform.point_color_intensity[index] = {
			light.light.color.x,
			light.light.color.y,
			light.light.color.z,
			light.light.intensity,
		}
	}
	uniform.light_counts = {
		u32(render_list.directional_light_count),
		u32(render_list.point_light_count),
		0,
		0,
	}
	for draw, index in draws[:draw_count] {
		material, alive := resources.get_material(registry, draw.material)
		if !alive {
			continue
		}
		uniform.model[index] = draw.model
		uniform.normal_model[index] = draw.model
		uniform.mvp[index] = mat4_mul(view_projection, draw.model)
		uniform.color[index] = {
			material.desc.base_color.x,
			material.desc.base_color.y,
			material.desc.base_color.z,
			material.desc.base_color.w,
		}
		uniform.emissive[index] = {
			material.desc.emissive.x,
			material.desc.emissive.y,
			material.desc.emissive.z,
			0,
		}
	}
	return wgpu_encode_viewport_draws(
		renderer,
		encoder,
		registry,
		draws[:draw_count],
		&uniform,
		component.clear_color,
		layer,
	)
}

wgpu_encode_viewport_draws :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	draws: []WGPU_Viewport_Draw,
	uniform: ^WGPU_Render_Uniform,
	clear_color: shared.Vec4,
	layer: int,
) -> string {
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.ui_viewport_uniform_buffers[layer],
		0,
		uniform,
		uint(size_of(WGPU_Render_Uniform)),
	)
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.ui_viewport_layer_views[layer],
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {
			f64(clear_color.x),
			f64(clear_color.y),
			f64(clear_color.z),
			f64(clear_color.w),
		},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = renderer.ui_viewport_depth_views[layer],
		depthLoadOp = .Clear,
		depthStoreOp = .Store,
		depthClearValue = 1,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Embedded Viewport Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if pass == nil {
		return "failed to begin embedded viewport pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		0,
		0,
		f32(renderer.ui_viewport_widths[layer]),
		f32(renderer.ui_viewport_heights[layer]),
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		0,
		0,
		renderer.ui_viewport_widths[layer],
		renderer.ui_viewport_heights[layer],
	)
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.ui_viewport_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.ui_viewport_bind_groups[layer])
	wgpu.RenderPassEncoderSetBindGroup(pass, 2, renderer.environment_bind_group)
	for draw, index in draws {
		geometry, geometry_err := wgpu_geometry_cache(renderer, registry, draw.geometry)
		if geometry_err != "" {
			return geometry_err
		}
		material, material_err := wgpu_material_cache(renderer, registry, draw.material)
		if material_err != "" {
			return material_err
		}
		resource, alive := resources.get_geometry(registry, draw.geometry)
		if !alive {
			continue
		}
		wgpu.RenderPassEncoderSetBindGroup(pass, 1, material.bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, geometry.vertex_buffer, 0, wgpu.WHOLE_SIZE)
		wgpu.RenderPassEncoderSetIndexBuffer(
			pass,
			geometry.index_buffer,
			.Uint32,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(pass, u32(len(resource.indices)), 1, 0, 0, u32(index))
	}
	wgpu.RenderPassEncoderEnd(pass)
	renderer.ui_viewport_redraw_count += 1
	return ""
}

wgpu_viewport_node_model :: proc(
	model: ^resources.Model,
	node_index: int,
	models: []Mat4,
	resolved, resolving: []bool,
) -> (
	Mat4,
	bool,
) {
	if model == nil || node_index < 0 || node_index >= len(model.nodes) {
		return {}, false
	}
	if resolved[node_index] {
		return models[node_index], true
	}
	if resolving[node_index] {
		return {}, false
	}
	resolving[node_index] = true
	node := model.nodes[node_index]
	value := wgpu_build_model(node.transform)
	if node.parent_index >= 0 {
		parent, ok := wgpu_viewport_node_model(
			model,
			int(node.parent_index),
			models,
			resolved,
			resolving,
		)
		if !ok {
			resolving[node_index] = false
			return {}, false
		}
		value = mat4_mul(parent, value)
	}
	models[node_index] = value
	resolved[node_index] = true
	resolving[node_index] = false
	return value, true
}
