package render

import "core:fmt"
import "core:math"
import "core:time"
import ecs "../ecs"
import platform "../platform"
import shared "../shared"
import resources "../resources"
import ui "../ui"
import "vendor:wgpu"

Vec3 :: shared.Vec3
Render_Instance :: shared.Render_Instance
Camera_Instance :: shared.Camera_Instance
Render_List :: shared.Render_List

Mat4 :: [16]f32

WGPU_MAX_INSTANCES :: 64

WGPU_Render_Uniform :: struct {
	mvp: [WGPU_MAX_INSTANCES]Mat4,
	model: [WGPU_MAX_INSTANCES]Mat4,
	normal_model: [WGPU_MAX_INSTANCES]Mat4,
	shadow_mvp: [WGPU_MAX_INSTANCES]Mat4,
	color: [WGPU_MAX_INSTANCES][4]f32,
	shadow_flags: [WGPU_MAX_INSTANCES][4]f32,
	ambient: [4]f32,
	directional_direction_intensity: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	directional_color: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	point_position_range: [shared.MAX_POINT_LIGHTS][4]f32,
	point_color_intensity: [shared.MAX_POINT_LIGHTS][4]f32,
	light_counts: [4]u32,
}

WGPU_Draw_Batch :: struct {
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	first_instance: u32,
	instance_count: u32,
}

WGPU_Geometry_Cache :: struct {
	handle: shared.Geometry_Handle,
	version: u32,
	vertex_buffer: wgpu.Buffer,
	index_buffer: wgpu.Buffer,
	index_count: u32,
	valid: bool,
}

WGPU_Material_Cache :: struct {
	handle: shared.Material_Handle,
	version: u32,
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	bind_group: wgpu.BindGroup,
	valid: bool,
}
WGPU_UI_Vertex :: struct {position:[2]f32,uv:[2]f32,color:[4]f32,kind:f32,size_radius:[3]f32}
#assert(size_of(WGPU_UI_Vertex)==48)

WGPU_Request_Adapter_State :: struct {
	completed: bool,
	status:  wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: string,
}

WGPU_Request_Device_State :: struct {
	completed: bool,
	status:  wgpu.RequestDeviceStatus,
	device:  wgpu.Device,
	message: string,
}

WGPU_Buffer_Map_State :: struct {
	completed: bool,
	status:  wgpu.MapAsyncStatus,
	message: string,
}

WGPU_Renderer :: struct {
	instance:          wgpu.Instance,
	surface:           wgpu.Surface,
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	queue:             wgpu.Queue,
	pipeline_layout:   wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	material_bind_group_layout: wgpu.BindGroupLayout,
	material_sampler: wgpu.Sampler,
	ui_bind_group_layout: wgpu.BindGroupLayout,
	ui_bind_group: wgpu.BindGroup,
	ui_pipeline_layout: wgpu.PipelineLayout,
	ui_shader: wgpu.ShaderModule,
	ui_pipeline: wgpu.RenderPipeline,
	ui_font_texture: wgpu.Texture,
	ui_font_view: wgpu.TextureView,
	ui_font_sampler: wgpu.Sampler,
	shadow_bind_group_layout: wgpu.BindGroupLayout,
	shadow_bind_group: wgpu.BindGroup,
	shadow_pipeline_layout: wgpu.PipelineLayout,
	shader:            wgpu.ShaderModule,
	pipeline:          wgpu.RenderPipeline,
	shadow_pipeline:   wgpu.RenderPipeline,
	geometry_cache:    [64]WGPU_Geometry_Cache,
	geometry_cache_count: int,
	material_cache: [64]WGPU_Material_Cache,
	material_cache_count: int,
	uniform_buffer:    wgpu.Buffer,
	depth_texture:     wgpu.Texture,
	depth_view:        wgpu.TextureView,
	shadow_texture:    wgpu.Texture,
	shadow_view:       wgpu.TextureView,
	shadow_sampler:    wgpu.Sampler,
	format:            wgpu.TextureFormat,
	present_mode:      wgpu.PresentMode,
	alpha_mode:        wgpu.CompositeAlphaMode,
	width:             u32,
	height:            u32,
	configured:        bool,
}

wgpu_material_cache :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry, handle: shared.Material_Handle) -> (^WGPU_Material_Cache, string) {
	material, ok := resources.get_material(registry,handle)
	if !ok {return nil,"render material handle is stale"}
	cache_index := -1
	for i in 0..<renderer.material_cache_count {if renderer.material_cache[i].handle == handle {cache_index=i; break}}
	if cache_index < 0 {
		if renderer.material_cache_count >= len(renderer.material_cache) {return nil,"too many cached materials"}
		cache_index=renderer.material_cache_count; renderer.material_cache_count+=1
	}
	cached := &renderer.material_cache[cache_index]
	if cached.valid && cached.version == material.version {return cached,""}
	if cached.bind_group != nil {wgpu.BindGroupRelease(cached.bind_group)}
	if cached.view != nil {wgpu.TextureViewRelease(cached.view)}
	if cached.texture != nil {wgpu.TextureRelease(cached.texture)}
	cached^ = {handle=handle,version=material.version}
	width,height := material.desc.texture_width,material.desc.texture_height
	pixels := material.desc.texture_pixels
	white := [4]u8{255,255,255,255}
	if len(pixels)==0 {width=1; height=1; pixels=white[:]}
	cached.texture = wgpu.DeviceCreateTexture(renderer.device,&wgpu.TextureDescriptor{
		label="Scrapbot Material Texture",usage={.TextureBinding,.CopyDst},dimension=._2D,
		size={width=width,height=height,depthOrArrayLayers=1},format=.RGBA8UnormSrgb,mipLevelCount=1,sampleCount=1,
	})
	if cached.texture==nil {return nil,"failed to create material texture"}
	wgpu.QueueWriteTexture(renderer.queue,&wgpu.TexelCopyTextureInfo{texture=cached.texture,aspect=.All},raw_data(pixels),uint(len(pixels)),&wgpu.TexelCopyBufferLayout{bytesPerRow=width*4,rowsPerImage=height},&wgpu.Extent3D{width=width,height=height,depthOrArrayLayers=1})
	cached.view=wgpu.TextureCreateView(cached.texture)
	if cached.view==nil {return nil,"failed to create material texture view"}
	entries := [?]wgpu.BindGroupEntry{{binding=0,textureView=cached.view},{binding=1,sampler=renderer.material_sampler}}
	cached.bind_group=wgpu.DeviceCreateBindGroup(renderer.device,&wgpu.BindGroupDescriptor{label="Scrapbot Material Bind Group",layout=renderer.material_bind_group_layout,entryCount=uint(len(entries)),entries=raw_data(entries[:])})
	if cached.bind_group==nil {return nil,"failed to create material bind group"}
	cached.valid=true
	return cached,""
}

WGPU_OFFSCREEN_WIDTH :: u32(1280)
WGPU_OFFSCREEN_HEIGHT :: u32(720)
WGPU_SHADOW_MAP_SIZE :: u32(2048)

wgpu_prepare_draw_batches :: proc(renderer: ^WGPU_Renderer, render_list: ^Render_List, registry: ^resources.Registry, width, height: u32) -> ([64]WGPU_Draw_Batch, int) {
	uniform: WGPU_Render_Uniform
	uniform.ambient = {render_list.ambient.x, render_list.ambient.y, render_list.ambient.z, 1}
	uniform.light_counts = {u32(render_list.directional_light_count), u32(render_list.point_light_count), 0, 0}
	for light, i in render_list.directional_lights[:render_list.directional_light_count] {
		uniform.directional_direction_intensity[i] = {light.light.direction.x, light.light.direction.y, light.light.direction.z, light.light.intensity}
		uniform.directional_color[i] = {light.light.color.x, light.light.color.y, light.light.color.z, 1}
	}
	for light, i in render_list.point_lights[:render_list.point_light_count] {
		uniform.point_position_range[i] = {light.position.x, light.position.y, light.position.z, light.light.range}
		uniform.point_color_intensity[i] = {light.light.color.x, light.light.color.y, light.light.color.z, light.light.intensity}
	}
	light_view_projection := mat4_identity()
	if render_list.directional_light_count > 0 {
		light_view_projection = wgpu_build_directional_light_view_projection(render_list.directional_lights[0].light.direction)
	}
	batches: [64]WGPU_Draw_Batch
	batch_count, instance_count := 0, 0
	for candidate in render_list.instances {
		already_batched := false
		for i in 0..<batch_count {if batches[i].geometry == candidate.geometry.handle && batches[i].material == candidate.material.handle {already_batched = true; break}}
		if already_batched {continue}
		batch := &batches[batch_count]
		batch.geometry = candidate.geometry.handle; batch.material = candidate.material.handle; batch.first_instance = u32(instance_count)
		material, material_ok := resources.get_material(registry, candidate.material.handle)
		if !material_ok {continue}
		for instance in render_list.instances {
			if instance.geometry.handle != batch.geometry || instance.material.handle != batch.material {continue}
			if instance_count >= WGPU_MAX_INSTANCES {break}
			uniform.mvp[instance_count] = wgpu_build_mvp(instance, render_list.camera, render_list.has_camera, width, height)
			uniform.model[instance_count] = wgpu_build_model(instance.transform)
			uniform.normal_model[instance_count] = wgpu_build_normal_model(instance.transform)
			uniform.shadow_mvp[instance_count] = mat4_mul(light_view_projection, wgpu_build_model(instance.transform))
			uniform.shadow_flags[instance_count] = {1 if instance.shadow_caster else 0, 1 if instance.shadow_receiver else 0, 0, 0}
			color := material.desc.base_color
			uniform.color[instance_count] = {color.x,color.y,color.z,color.w}
			instance_count += 1; batch.instance_count += 1
		}
		if batch.instance_count > 0 {batch_count += 1}
	}
	if instance_count == 0 {
		return batches, 0
	}

	wgpu.QueueWriteBuffer(renderer.queue, renderer.uniform_buffer, 0, &uniform, uint(size_of(WGPU_Render_Uniform)))
	return batches, batch_count
}

wgpu_geometry_cache :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry, handle: shared.Geometry_Handle) -> (^WGPU_Geometry_Cache, string) {
	geometry, ok := resources.get_geometry(registry, handle)
	if !ok {return nil, "render geometry handle is stale"}
	cache_index := -1
	for i in 0..<renderer.geometry_cache_count {if renderer.geometry_cache[i].handle == handle {cache_index = i; break}}
	if cache_index < 0 {
		if renderer.geometry_cache_count >= len(renderer.geometry_cache) {return nil, "too many cached geometries"}
		cache_index = renderer.geometry_cache_count; renderer.geometry_cache_count += 1
	}
	cached := &renderer.geometry_cache[cache_index]
	if cached.valid && cached.version == geometry.version {return cached, ""}
	if cached.vertex_buffer != nil {wgpu.BufferRelease(cached.vertex_buffer)}
	if cached.index_buffer != nil {wgpu.BufferRelease(cached.index_buffer)}
	cached^ = {handle = handle, version = geometry.version, index_count = u32(len(geometry.indices))}
	cached.vertex_buffer = wgpu.DeviceCreateBufferWithData(renderer.device, &wgpu.BufferWithDataDescriptor{label="Scrapbot Geometry Vertices", usage={.Vertex}}, geometry.vertices)
	cached.index_buffer = wgpu.DeviceCreateBufferWithData(renderer.device, &wgpu.BufferWithDataDescriptor{label="Scrapbot Geometry Indices", usage={.Index}}, geometry.indices)
	if cached.vertex_buffer == nil || cached.index_buffer == nil {return nil, "failed to upload geometry buffers"}
	cached.valid = true
	return cached, ""
}

wgpu_encode_render_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	color_view: wgpu.TextureView,
	depth_view: wgpu.TextureView,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	ui_state: ^ui.State,
	label: string,
	target_width,target_height:u32,
) -> string {
	color_attachment := wgpu.RenderPassColorAttachment {
		view       = color_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = wgpu.Color{0.08, 0.10, 0.12, 1.0},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view            = depth_view,
		depthLoadOp     = .Clear,
		depthStoreOp    = .Store,
		depthClearValue = 1.0,
		stencilLoadOp   = .Undefined,
		stencilStoreOp  = .Undefined,
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label                  = label,
			colorAttachmentCount   = 1,
			colorAttachments       = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if render_pass == nil {
		return "failed to begin wgpu render pass"
	}
	defer wgpu.RenderPassEncoderRelease(render_pass)

	if len(batches) > 0 {
		drawable_width:=f32(target_width);drawable_height:=f32(target_height)
		viewport:=ui.editor_viewport(ui_state,drawable_width,drawable_height)
		wgpu.RenderPassEncoderSetViewport(render_pass,viewport.x,viewport.y,viewport.width,viewport.height,0,1)
		wgpu.RenderPassEncoderSetScissorRect(render_pass,u32(viewport.x),u32(viewport.y),u32(viewport.width),u32(viewport.height))
		wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.pipeline)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, renderer.bind_group)
		for batch in batches {
			cached, cache_err := wgpu_geometry_cache(renderer, registry, batch.geometry)
			if cache_err != "" {return cache_err}
			material_cached, material_err := wgpu_material_cache(renderer,registry,batch.material)
			if material_err != "" {return material_err}
			wgpu.RenderPassEncoderSetBindGroup(render_pass,1,material_cached.bind_group)
			wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, cached.vertex_buffer, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderSetIndexBuffer(render_pass, cached.index_buffer, .Uint32, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderDrawIndexed(render_pass, cached.index_count, batch.instance_count, 0, 0, batch.first_instance)
		}
	}
	wgpu.RenderPassEncoderEnd(render_pass)
	if ui_state!=nil&&ui_state.paint_count>0 {
		ui_color_attachment:=wgpu.RenderPassColorAttachment{view=color_view,depthSlice=wgpu.DEPTH_SLICE_UNDEFINED,loadOp=.Load,storeOp=.Store}
		ui_depth_attachment:=wgpu.RenderPassDepthStencilAttachment{view=depth_view,depthLoadOp=.Load,depthStoreOp=.Store,stencilLoadOp=.Undefined,stencilStoreOp=.Undefined}
		ui_pass:=wgpu.CommandEncoderBeginRenderPass(encoder,&wgpu.RenderPassDescriptor{label="Scrapbot UI Overlay Pass",colorAttachmentCount=1,colorAttachments=&ui_color_attachment,depthStencilAttachment=&ui_depth_attachment})
		if ui_pass==nil{return "failed to begin UI overlay render pass"}
		defer wgpu.RenderPassEncoderRelease(ui_pass)
		vertices:=make([dynamic]WGPU_UI_Vertex,0,ui_state.paint_count*6);defer delete(vertices)
		drawable_width:=f32(target_width);drawable_height:=f32(target_height)
		viewport:=ui.editor_viewport(ui_state,drawable_width,drawable_height)
		for command,command_index in ui_state.paint[:ui_state.paint_count] {
			rect:=command.rect;radius:=command.corner_radius
			if command_index<ui_state.editor_paint_start {
				scale_x,scale_y:=viewport.width/1280,viewport.height/720
				rect={viewport.x+rect.x*scale_x,viewport.y+rect.y*scale_y,rect.width*scale_x,rect.height*scale_y};radius*=min(scale_x,scale_y)
			}
			positions:[4][2]f32;shape_width,shape_height:=rect.width,rect.height
			if command.kind==.Line {
				dx:=command.line_end.x-command.line_start.x;dy:=command.line_end.y-command.line_start.y;line_length:=math.sqrt(dx*dx+dy*dy)
				if line_length<=0.0001{line_length=0.0001};half:=command.line_thickness*0.5;px:=-dy/line_length*half;py:=dx/line_length*half
				points:=[4]shared.Vec2{{command.line_start.x-px,command.line_start.y-py},{command.line_end.x-px,command.line_end.y-py},{command.line_end.x+px,command.line_end.y+py},{command.line_start.x+px,command.line_start.y+py}}
				for point,i in points {positions[i]={point.x/drawable_width*2-1,1-point.y/drawable_height*2}}
				shape_width=line_length;shape_height=command.line_thickness
			} else {
				x0:=rect.x/drawable_width*2-1;x1:=(rect.x+rect.width)/drawable_width*2-1;y0:=1-rect.y/drawable_height*2;y1:=1-(rect.y+rect.height)/drawable_height*2
				positions={{x0,y0},{x1,y0},{x1,y1},{x0,y1}}
			}
			u0,v0,u1,v1:=command.uv.x,command.uv.y,command.uv.z,command.uv.w
			kind:=f32(0);if command.kind==.Glyph{kind=1}
			if command.kind==.Panel||command.kind==.Line {u0=0;v0=0;u1=1;v1=1}
			color:=[4]f32{command.color.x,command.color.y,command.color.z,command.color.w}
			params:=[3]f32{shape_width,shape_height,radius}
			append(&vertices,WGPU_UI_Vertex{position=positions[0],uv={u0,v0},color=color,kind=kind,size_radius=params},WGPU_UI_Vertex{position=positions[1],uv={u1,v0},color=color,kind=kind,size_radius=params},WGPU_UI_Vertex{position=positions[2],uv={u1,v1},color=color,kind=kind,size_radius=params},WGPU_UI_Vertex{position=positions[0],uv={u0,v0},color=color,kind=kind,size_radius=params},WGPU_UI_Vertex{position=positions[2],uv={u1,v1},color=color,kind=kind,size_radius=params},WGPU_UI_Vertex{position=positions[3],uv={u0,v1},color=color,kind=kind,size_radius=params})
		}
		buffer:=wgpu.DeviceCreateBufferWithData(renderer.device,&wgpu.BufferWithDataDescriptor{label="Scrapbot UI Vertices",usage={.Vertex}},vertices[:]);if buffer==nil{return "failed to upload UI vertices"};defer wgpu.BufferRelease(buffer)
		wgpu.RenderPassEncoderSetViewport(ui_pass,0,0,drawable_width,drawable_height,0,1);wgpu.RenderPassEncoderSetScissorRect(ui_pass,0,0,target_width,target_height)
		wgpu.RenderPassEncoderSetPipeline(ui_pass,renderer.ui_pipeline);wgpu.RenderPassEncoderSetBindGroup(ui_pass,0,renderer.ui_bind_group);wgpu.RenderPassEncoderSetVertexBuffer(ui_pass,0,buffer,0,wgpu.WHOLE_SIZE)
		if ui_state.editor_visible {
			project_vertex_count:=u32(ui_state.editor_paint_start*6)
			if project_vertex_count>0 {wgpu.RenderPassEncoderSetScissorRect(ui_pass,u32(viewport.x),u32(viewport.y),u32(viewport.width),u32(viewport.height));wgpu.RenderPassEncoderDraw(ui_pass,project_vertex_count,1,0,0)}
			gizmo_start:=u32(ui_state.editor_gizmo_paint_start*6);gizmo_end:=u32(ui_state.editor_gizmo_paint_end*6);total:=u32(len(vertices))
			wgpu.RenderPassEncoderSetScissorRect(ui_pass,0,0,target_width,target_height)
			if gizmo_start>project_vertex_count{wgpu.RenderPassEncoderDraw(ui_pass,gizmo_start-project_vertex_count,1,project_vertex_count,0)}
			if gizmo_end>gizmo_start {wgpu.RenderPassEncoderSetScissorRect(ui_pass,u32(viewport.x),u32(viewport.y),u32(viewport.width),u32(viewport.height));wgpu.RenderPassEncoderDraw(ui_pass,gizmo_end-gizmo_start,1,gizmo_start,0)}
			if total>gizmo_end {wgpu.RenderPassEncoderSetScissorRect(ui_pass,0,0,target_width,target_height);wgpu.RenderPassEncoderDraw(ui_pass,total-gizmo_end,1,gizmo_end,0)}
		} else {
			wgpu.RenderPassEncoderSetScissorRect(ui_pass,u32(viewport.x),u32(viewport.y),u32(viewport.width),u32(viewport.height))
			wgpu.RenderPassEncoderDraw(ui_pass,u32(len(vertices)),1,0,0)
		}
		wgpu.RenderPassEncoderEnd(ui_pass)
	}
	return ""
}

wgpu_encode_shadow_pass :: proc(renderer: ^WGPU_Renderer, encoder: wgpu.CommandEncoder, batches: []WGPU_Draw_Batch, registry: ^resources.Registry) -> string {
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view=renderer.shadow_view, depthLoadOp=.Clear, depthStoreOp=.Store, depthClearValue=1,
		stencilLoadOp=.Undefined, stencilStoreOp=.Undefined,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wgpu.RenderPassDescriptor {
		label="Scrapbot Shadow Pass", depthStencilAttachment=&depth_attachment,
	})
	if pass == nil {return "failed to begin wgpu shadow pass"}
	defer wgpu.RenderPassEncoderRelease(pass)
	if len(batches) > 0 {
		wgpu.RenderPassEncoderSetPipeline(pass, renderer.shadow_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.shadow_bind_group)
		for batch in batches {
			cached, err := wgpu_geometry_cache(renderer, registry, batch.geometry)
			if err != "" {return err}
			wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, cached.vertex_buffer, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderSetIndexBuffer(pass, cached.index_buffer, .Uint32, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderDrawIndexed(pass, cached.index_count, batch.instance_count, 0, 0, batch.first_instance)
		}
	}
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_draw_frame :: proc(renderer: ^WGPU_Renderer, world: ^World, config: ^Run_Config, delta_time: f32) -> (presented, should_quit: bool, err: string) {
	drawable, configure_err := wgpu_configure_surface(renderer)
	if configure_err != "" || !drawable {
		return false, false, configure_err
	}

	surface_texture, acquired_texture, acquire_should_quit := wgpu_acquire_surface_texture(renderer)
	if acquire_should_quit {
		return false, true, ""
	}
	if !acquired_texture {
		switch surface_texture.status {
		case .Occluded, .Timeout:
			return false, false, ""
		case .Outdated, .Lost:
			renderer.configured = false
			return false, false, ""
		case .Error:
			return false, false, "failed to acquire wgpu surface texture: Error"
		case .SuccessOptimal, .SuccessSuboptimal:
		}
		return false, false, fmt.tprintf("failed to acquire wgpu surface texture: %v", surface_texture.status)
	}
	texture := surface_texture.texture
	if texture == nil {
		return false, false, "wgpu surface returned no texture"
	}

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return false, false, "failed to create wgpu texture view"
	}
	defer wgpu.TextureViewRelease(view)
	defer wgpu.TextureRelease(texture)

	if err = run_frame_system(config, world, delta_time, f32(renderer.width), f32(renderer.height)); err != "" {
		return false, false, err
	}
	render_list := ecs.build_resource_render_list(world, config.resource_registry, config.ui_state != nil && config.ui_state.editor_visible)
	defer ecs.destroy_render_list(&render_list)
	viewport:=ui.editor_viewport(config.ui_state,f32(renderer.width),f32(renderer.height))
	batches, batch_count := wgpu_prepare_draw_batches(renderer, &render_list, config.resource_registry, u32(viewport.width), u32(viewport.height))
	if config.stats != nil {config.stats.draw_batches = batch_count}

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Render Encoder"})
	if encoder == nil {
		return false, false, "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	if err = wgpu_encode_shadow_pass(renderer, encoder, batches[:batch_count], config.resource_registry); err != "" {return false, false, err}
	if err = wgpu_encode_render_pass(renderer, encoder, view, renderer.depth_view, batches[:batch_count], config.resource_registry, config.ui_state, "Scrapbot Geometry Pass",renderer.width,renderer.height); err != "" {
		return false, false, err
	}

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Render Commands"})
	if command_buffer == nil {
		return false, false, "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	if wgpu.SurfacePresent(renderer.surface) != .Success {
		return false, false, "failed to present wgpu surface"
	}

	return true, false, ""
}

wgpu_render_offscreen_frame :: proc(
	renderer: ^WGPU_Renderer,
	world: ^World,
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	depth_view: wgpu.TextureView,
	readback: wgpu.Buffer = nil,
	row_stride: u32 = 0,
	width: u32 = 0,
	height: u32 = 0,
	config: ^Run_Config = nil,
) -> string {
	if config != nil {
		if err := run_frame_system(config, world, 1.0 / 60.0); err != "" {
			return err
		}
	}
	render_list := ecs.build_resource_render_list(world, config.resource_registry, config.ui_state != nil && config.ui_state.editor_visible)
	defer ecs.destroy_render_list(&render_list)
	viewport:=ui.editor_viewport(config.ui_state,f32(width),f32(height))
	batches, batch_count := wgpu_prepare_draw_batches(renderer, &render_list, config.resource_registry, u32(viewport.width), u32(viewport.height))
	if config != nil && config.stats != nil {config.stats.draw_batches = batch_count}

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Headless Render Encoder"})
	if encoder == nil {
		return "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	if err := wgpu_encode_shadow_pass(renderer, encoder, batches[:batch_count], config.resource_registry); err != "" {return err}
	if err := wgpu_encode_render_pass(renderer, encoder, view, depth_view, batches[:batch_count], config.resource_registry, config.ui_state, "Scrapbot Headless Geometry Pass",width,height); err != "" {
		return err
	}

	if readback != nil {
		wgpu.CommandEncoderCopyTextureToBuffer(
			encoder,
			&wgpu.TexelCopyTextureInfo {
				texture = texture,
				aspect = .All,
			},
			&wgpu.TexelCopyBufferInfo {
				buffer = readback,
				layout = wgpu.TexelCopyBufferLayout {
					bytesPerRow  = row_stride,
					rowsPerImage = height,
				},
			},
			&wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			},
		)
	}

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Headless Render Commands"})
	if command_buffer == nil {
		return "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	return ""
}

wgpu_run_headless :: proc(world: ^World, config: ^Run_Config) -> string {
	renderer, init_err := wgpu_init_renderer(true,config.ui_state)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}

	width := WGPU_OFFSCREEN_WIDTH
	height := WGPU_OFFSCREEN_HEIGHT
	row_bytes := width * 4
	row_stride := align_to(row_bytes, 256)
	readback_size := u64(row_stride * height)

	texture := wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label  = "Scrapbot Headless Frame Texture",
			usage  = {.RenderAttachment, .CopySrc},
			dimension = ._2D,
			size = wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			},
			format     = renderer.format,
			mipLevelCount = 1,
			sampleCount   = 1,
		},
	)
	if texture == nil {
		return "failed to create wgpu headless texture"
	}
	defer wgpu.TextureRelease(texture)

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		return "failed to create wgpu headless texture view"
	}
	defer wgpu.TextureViewRelease(view)

	depth_texture, depth_view, depth_err := wgpu_create_depth_texture(&renderer, width, height)
	if depth_err != "" {
		return depth_err
	}
	defer wgpu.TextureViewRelease(depth_view)
	defer wgpu.TextureRelease(depth_texture)

	readback := wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Headless Readback Buffer",
			usage = {.CopyDst, .MapRead},
			size  = readback_size,
		},
	)
	if readback == nil {
		return "failed to create wgpu headless readback buffer"
	}
	defer wgpu.BufferRelease(readback)

	frame_count := config.max_frames
	if frame_count == 0 {
		frame_count = 1
	}
	for index in 0 ..< frame_count {
		capture := index == frame_count - 1
		err := wgpu_render_offscreen_frame(
			&renderer,
			world,
			texture,
			view,
			depth_view,
			readback if capture else nil,
			row_stride if capture else 0,
			width,
			height,
			config,
		)
		if err != "" {
			return err
		}
	}

	map_state: WGPU_Buffer_Map_State
	wgpu.BufferMapAsync(
		readback,
		{.Read},
		0,
		uint(readback_size),
		wgpu.BufferMapCallbackInfo {
			mode      = .AllowSpontaneos,
			callback  = wgpu_buffer_map_callback,
			userdata1 = &map_state,
		},
	)
	if !wgpu_wait_for_buffer_map(renderer.instance, &map_state) {
		message := map_state.message
		if message == "" {
			message = "request timed out"
		}
		return fmt.tprintf("failed to map wgpu readback buffer: %s", message)
	}
	defer wgpu.BufferUnmap(readback)

	mapped := wgpu.BufferGetMappedRange(readback, 0, uint(readback_size))
	pixels := make([]u8, int(row_bytes * height))
	defer delete(pixels)
	for y in 0 ..< int(height) {
		dst := y * int(row_bytes)
		src := y * int(row_stride)
		copy_framegrab_row(pixels[dst:dst + int(row_bytes)], mapped[src:src + int(row_bytes)], renderer.format)
	}

	return write_png_rgba8(config.framegrab_path, pixels, width, height)
}

copy_framegrab_row :: proc(dst, src: []u8, format: wgpu.TextureFormat) {
	#partial switch format {
	case .BGRA8Unorm, .BGRA8UnormSrgb:
		for i := 0; i < len(dst); i += 4 {
			dst[i + 0] = src[i + 2]
			dst[i + 1] = src[i + 1]
			dst[i + 2] = src[i + 0]
			dst[i + 3] = src[i + 3]
		}
	case:
		copy(dst, src)
	}
}

align_to :: proc(value, alignment: u32) -> u32 {
	return ((value + alignment - 1) / alignment) * alignment
}

wgpu_run_window :: proc(world: ^World, config: ^Run_Config) -> string {
	renderer, init_err := wgpu_init_renderer(true,config.ui_state)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}

	frame_count: u32
	previous_tick := time.tick_now()
	for config.max_frames == 0 || frame_count < config.max_frames {
		if platform.pump_runtime_window_events() {
			break
		}
		wgpu.InstanceProcessEvents(renderer.instance)

		now := time.tick_now()
		delta_time := f32(1.0 / 60.0)
		if frame_count > 0 {
			duration := time.tick_diff(previous_tick, now)
			delta_time = f32(f64(duration) / 1_000_000_000.0)
			if delta_time <= 0 {delta_time = 1.0 / 60.0}
		}
		previous_tick = now
		delta_time = min(delta_time, ecs.MAX_DELTA_TIME)
		_, should_quit, draw_err := wgpu_draw_frame(&renderer, world, config, delta_time)
		if draw_err != "" {
			return draw_err
		}
		if should_quit {
			break
		}

		frame_count += 1
		time.sleep(16 * time.Millisecond)
	}

	return ""
}
