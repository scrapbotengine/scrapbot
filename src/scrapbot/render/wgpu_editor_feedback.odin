package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import wgpu "vendor:wgpu"

WGPU_EDITOR_FEEDBACK_MAX_DRAWS :: 4096

WGPU_Editor_Feedback_Instance :: struct {
	mvp: Mat4,
	mode_alpha: [4]f32,
}

WGPU_Editor_Feedback_Draw :: struct {
	geometry: shared.Geometry_Handle,
	geometry_mode: shared.Geometry_Mode,
	material: shared.Material_Handle,
	instance: WGPU_Editor_Feedback_Instance,
}

WGPU_EDITOR_FEEDBACK_SHADER :: `
struct Feedback_Instance {
	mvp: mat4x4<f32>,
	mode_alpha: vec4<f32>,
};

struct Material_Uniform {
	pbr_factors: vec4<f32>,
	flags: vec4<f32>,
	alpha: vec4<f32>,
	shader_parameters: array<vec4<f32>, 4>,
};

@group(0) @binding(0) var<storage, read> feedback_instances: array<Feedback_Instance>;
@group(1) @binding(0) var base_color_texture: texture_2d<f32>;
@group(1) @binding(1) var base_color_sampler: sampler;
@group(1) @binding(6) var<uniform> material: Material_Uniform;

struct Vertex_Input {
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
	@location(3) tangent: vec4<f32>,
};

struct Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
	@location(1) @interpolate(flat) mode_alpha: vec4<f32>,
};

@vertex
fn feedback_vs(
	input: Vertex_Input,
	@builtin(instance_index) instance_index: u32,
) -> Vertex_Output {
	let instance = feedback_instances[instance_index];
	var output: Vertex_Output;
	output.position = instance.mvp * vec4<f32>(input.position, 1.0);
	output.uv = input.uv;
	output.mode_alpha = instance.mode_alpha;
	return output;
}

@fragment
fn feedback_fs(input: Vertex_Output) -> @location(0) vec4<f32> {
	if (material.flags.z > 0.5) {
		let sampled_alpha = textureSample(base_color_texture, base_color_sampler, input.uv).a;
		if (sampled_alpha * input.mode_alpha.z < material.alpha.x) {
			discard;
		}
	}
	return vec4<f32>(input.mode_alpha.xy, 0.0, 1.0);
}
`

wgpu_create_editor_feedback_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil {
		return "editor feedback renderer is unavailable"
	}
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_EDITOR_FEEDBACK_SHADER,
	}
	renderer.editor_feedback_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &shader_source,
			label = "Scrapbot Editor Feedback Shader",
		},
	)
	if renderer.editor_feedback_shader == nil {
		return "failed to create editor feedback shader"
	}
	renderer.editor_feedback_instance_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Editor Feedback Instances",
			usage = {.Storage, .CopyDst},
			size = u64(WGPU_EDITOR_FEEDBACK_MAX_DRAWS * size_of(WGPU_Editor_Feedback_Instance)),
		},
	)
	if renderer.editor_feedback_instance_buffer == nil {
		return "failed to create editor feedback instance buffer"
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_Editor_Feedback_Instance)),
			},
		},
	}
	renderer.editor_feedback_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Editor Feedback Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.editor_feedback_bind_group_layout == nil {
		return "failed to create editor feedback bind group layout"
	}
	renderer.editor_feedback_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Editor Feedback Bind Group",
			layout = renderer.editor_feedback_bind_group_layout,
			entryCount = 1,
			entries = &wgpu.BindGroupEntry {
				binding = 0,
				buffer = renderer.editor_feedback_instance_buffer,
				offset = 0,
				size = u64(
					WGPU_EDITOR_FEEDBACK_MAX_DRAWS * size_of(WGPU_Editor_Feedback_Instance),
				),
			},
		},
	)
	if renderer.editor_feedback_bind_group == nil {
		return "failed to create editor feedback bind group"
	}
	layouts := [?]wgpu.BindGroupLayout {
		renderer.editor_feedback_bind_group_layout,
		renderer.material_bind_group_layout,
	}
	renderer.editor_feedback_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Editor Feedback Pipeline Layout",
			bindGroupLayoutCount = uint(len(layouts)),
			bindGroupLayouts = raw_data(layouts[:]),
		},
	)
	if renderer.editor_feedback_pipeline_layout == nil {
		return "failed to create editor feedback pipeline layout"
	}
	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
		{format = .Float32x4, offset = 32, shaderLocation = 3},
	}
	vertex_layout := wgpu.VertexBufferLayout {
		arrayStride = u64(size_of(resources.Vertex)),
		stepMode = .Vertex,
		attributeCount = uint(len(attributes)),
		attributes = raw_data(attributes[:]),
	}
	target := wgpu.ColorTargetState {
		format = .RGBA8Unorm,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.editor_feedback_shader,
		entryPoint = "feedback_fs",
		targetCount = 1,
		targets = &target,
	}
	renderer.editor_feedback_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Editor Feedback Pipeline",
			layout = renderer.editor_feedback_pipeline_layout,
			vertex = {
				module = renderer.editor_feedback_shader,
				entryPoint = "feedback_vs",
				bufferCount = 1,
				buffers = &vertex_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.editor_feedback_pipeline == nil {
		return "failed to create editor feedback pipeline"
	}
	return ""
}

wgpu_release_editor_feedback_resources :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.editor_feedback_mask_view != nil {
		wgpu.TextureViewRelease(renderer.editor_feedback_mask_view)
		renderer.editor_feedback_mask_view = nil
	}
	if renderer.editor_feedback_mask_texture != nil {
		wgpu.TextureRelease(renderer.editor_feedback_mask_texture)
		renderer.editor_feedback_mask_texture = nil
	}
	if renderer.editor_feedback_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.editor_feedback_pipeline)
	}
	if renderer.editor_feedback_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.editor_feedback_pipeline_layout)
	}
	if renderer.editor_feedback_bind_group != nil {
		wgpu.BindGroupRelease(renderer.editor_feedback_bind_group)
	}
	if renderer.editor_feedback_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.editor_feedback_bind_group_layout)
	}
	if renderer.editor_feedback_instance_buffer != nil {
		wgpu.BufferRelease(renderer.editor_feedback_instance_buffer)
	}
	if renderer.editor_feedback_shader != nil {
		wgpu.ShaderModuleRelease(renderer.editor_feedback_shader)
	}
}

wgpu_append_editor_feedback_draw :: proc(
	draws: ^[dynamic]WGPU_Editor_Feedback_Draw,
	geometry: shared.Geometry_Handle,
	geometry_mode: shared.Geometry_Mode,
	material: shared.Material_Handle,
	model, view_projection: Mat4,
	selection, preview, alpha: f32,
) {
	if draws == nil || len(draws^) >= WGPU_EDITOR_FEEDBACK_MAX_DRAWS {
		return
	}
	append(
		draws,
		WGPU_Editor_Feedback_Draw {
			geometry = geometry,
			geometry_mode = geometry_mode,
			material = material,
			instance = {
				mvp = mat4_mul(view_projection, model),
				mode_alpha = {selection, preview, alpha, 0},
			},
		},
	)
}

wgpu_append_editor_model_feedback_draws :: proc(
	draws: ^[dynamic]WGPU_Editor_Feedback_Draw,
	registry: ^resources.Registry,
	resource: shared.Resource_UUID,
	root_model, view_projection: Mat4,
) {
	handle, found := resources.model_handle_by_uuid(registry, resource)
	if !found {
		return
	}
	model, alive := resources.get_model(registry, handle)
	if !alive {
		return
	}
	node_models := make([]Mat4, len(model.nodes), context.temp_allocator)
	resolved := make([]bool, len(model.nodes), context.temp_allocator)
	resolving := make([]bool, len(model.nodes), context.temp_allocator)
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
		for primitive in model.meshes[node.mesh_index].primitives {
			material := primitive.material
			if _, material_alive := resources.get_material(registry, material); !material_alive {
				material, _ = resources.material_by_name(registry, "default")
			}
			material_resource, material_alive := resources.get_material(registry, material)
			if !material_alive {
				continue
			}
			wgpu_append_editor_feedback_draw(
				draws,
				primitive.geometry,
				.Inherit,
				material,
				mat4_mul(root_model, node_model),
				view_projection,
				0,
				1,
				material_resource.desc.base_color.w,
			)
		}
	}
}

wgpu_collect_editor_feedback_draws :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	render_list: ^shared.Render_List,
	state: ^ui.State,
) -> [dynamic]WGPU_Editor_Feedback_Draw {
	if state == nil || !state.editor_visible {
		return nil
	}
	draws := make(
		[dynamic]WGPU_Editor_Feedback_Draw,
		0,
		min(WGPU_EDITOR_FEEDBACK_MAX_DRAWS, len(renderer.gpu_editor_selected_slots) + 64),
		context.temp_allocator,
	)
	view_projection := renderer.gpu_render_uniform.view_projection
	for slot in renderer.gpu_editor_selected_slots {
		instance, found := wgpu_render_instance_by_slot(render_list, slot)
		if !found {
			continue
		}
		material, alive := resources.get_material(registry, instance.material.handle)
		if !alive {
			continue
		}
		wgpu_append_editor_feedback_draw(
			&draws,
			instance.geometry.handle,
			instance.geometry.geometry_mode,
			instance.material.handle,
			wgpu_build_model(instance.transform),
			view_projection,
			1,
			0,
			material.desc.base_color.w,
		)
	}
	if state != nil &&
	   state.editor_model_placement_preview_visible &&
	   state.editor_model_placement_preview_resource != (shared.Resource_UUID{}) {
		root := wgpu_build_model(
			shared.Transform_Component {
				position = state.editor_model_placement_preview_position,
				scale = {1, 1, 1},
			},
		)
		wgpu_append_editor_model_feedback_draws(
			&draws,
			registry,
			state.editor_model_placement_preview_resource,
			root,
			view_projection,
		)
	}
	return draws
}

wgpu_encode_editor_feedback_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	render_list: ^shared.Render_List,
	state: ^ui.State,
	width, height: u32,
) -> string {
	if renderer == nil ||
	   encoder == nil ||
	   registry == nil ||
	   renderer.editor_feedback_mask_view == nil {
		return ""
	}
	draws := wgpu_collect_editor_feedback_draws(renderer, registry, render_list, state)
	requested := len(draws) > 0
	if !requested &&
	   !renderer.editor_feedback_mask_active &&
	   renderer.editor_feedback_mask_initialized {
		return ""
	}
	for draw in draws {
		if _, geometry_err := wgpu_geometry_cache(
			renderer,
			registry,
			draw.geometry,
			draw.geometry_mode,
		); geometry_err != "" {
			return geometry_err
		}
		if _, material_err := wgpu_material_cache(renderer, registry, draw.material);
		   material_err != "" {
			return material_err
		}
	}
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.editor_feedback_mask_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {},
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Editor Feedback Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
		},
	)
	if pass == nil {
		return "failed to begin editor feedback pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	if requested {
		instances := make([]WGPU_Editor_Feedback_Instance, len(draws), context.temp_allocator)
		for draw, index in draws {
			instances[index] = draw.instance
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.editor_feedback_instance_buffer,
			0,
			raw_data(instances),
			uint(len(instances) * size_of(WGPU_Editor_Feedback_Instance)),
		)
		wgpu.RenderPassEncoderSetViewport(pass, 0, 0, f32(width), f32(height), 0, 1)
		wgpu.RenderPassEncoderSetScissorRect(pass, 0, 0, width, height)
		wgpu.RenderPassEncoderSetPipeline(pass, renderer.editor_feedback_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.editor_feedback_bind_group)
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
		for draw, index in draws {
			geometry, _ := wgpu_geometry_cache(
				renderer,
				registry,
				draw.geometry,
				draw.geometry_mode,
			)
			material, _ := wgpu_material_cache(renderer, registry, draw.material)
			if geometry == nil {
				continue
			}
			command := wgpu_geometry_indirect_template(geometry, 0, false)
			if command.index_count == 0 {
				continue
			}
			wgpu.RenderPassEncoderSetBindGroup(pass, 1, material.bind_group)
			wgpu.RenderPassEncoderDrawIndexed(
				pass,
				command.index_count,
				1,
				command.first_index,
				command.base_vertex,
				u32(index),
			)
		}
	}
	wgpu.RenderPassEncoderEnd(pass)
	renderer.editor_feedback_mask_initialized = true
	renderer.editor_feedback_mask_active = requested
	return ""
}
