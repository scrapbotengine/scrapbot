package render

import ui "../ui"
import wgpu "vendor:wgpu"

WGPU_Editor_Grid_Uniform :: struct {
	view_projection: Mat4,
	camera_center_extent: [4]f32,
	spacing_lod_fade: [4]f32,
}

#assert(size_of(WGPU_Editor_Grid_Uniform) == 96)

WGPU_EDITOR_GRID_SHADER :: `
struct Grid_Uniform {
	view_projection: mat4x4<f32>,
	camera_center_extent: vec4<f32>,
	spacing_lod_fade: vec4<f32>,
};

@group(0) @binding(0) var<uniform> grid: Grid_Uniform;

struct Grid_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) world_position: vec3<f32>,
};

@vertex
fn grid_vs(@builtin(vertex_index) index: u32) -> Grid_Output {
	var corners = array<vec2<f32>, 6>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(1.0, -1.0),
		vec2<f32>(-1.0, 1.0),
		vec2<f32>(-1.0, 1.0),
		vec2<f32>(1.0, -1.0),
		vec2<f32>(1.0, 1.0),
	);
	let center = grid.camera_center_extent.xz;
	let world = center + corners[index] * grid.camera_center_extent.w;
	var output: Grid_Output;
	output.world_position = vec3<f32>(world.x, 0.0, world.y);
	output.position = grid.view_projection * vec4<f32>(output.world_position, 1.0);
	return output;
}

fn grid_line_coverage(position: vec2<f32>, spacing: f32) -> f32 {
	let coordinate = position / spacing;
	let derivative = max(fwidth(coordinate), vec2<f32>(0.0001));
	let distance_to_line = abs(fract(coordinate - 0.5) - 0.5) / derivative;
	return 1.0 - min(min(distance_to_line.x, distance_to_line.y), 1.0);
}

fn axis_coverage(distance: f32) -> f32 {
	let width = max(fwidth(distance), 0.0001);
	return 1.0 - smoothstep(width * 0.35, width * 1.35, abs(distance));
}

fn adaptive_grid_alpha(position: vec2<f32>, camera_height: f32) -> f32 {
	let base_spacing = grid.spacing_lod_fade.x;
	let primary_steps = 10.0;
	let division_level = clamp(
		log(max(camera_height / base_spacing, 1.0)) / log(10.0),
		grid.spacing_lod_fade.z,
		grid.spacing_lod_fade.w,
	);
	let level = floor(division_level);
	let transition = fract(division_level);
	let minor_spacing = base_spacing * pow(primary_steps, level);
	let major_spacing = minor_spacing * primary_steps;

	let minor = grid_line_coverage(position, minor_spacing) * 0.5 * (1.0 - transition);
	let major = grid_line_coverage(position, major_spacing) * 0.5;
	return max(minor, major);
}

@fragment
fn grid_fs(input: Grid_Output) -> @location(0) vec4<f32> {
	let camera = grid.camera_center_extent.xyz;
	let camera_height = abs(camera.y);
	let base_spacing = grid.spacing_lod_fade.x;
	let primary_steps = 10.0;
	let division_level = clamp(
		log(max(camera_height / base_spacing, 1.0)) / log(10.0),
		grid.spacing_lod_fade.z,
		grid.spacing_lod_fade.w,
	);
	let fade_spacing = base_spacing * pow(
		primary_steps,
		clamp(division_level - 1.0, grid.spacing_lod_fade.z, grid.spacing_lod_fade.w),
	);
	let fade_radius = (200.0 - primary_steps) * fade_spacing;
	let planar_distance = length(input.world_position.xz - camera.xz);
	let distance_fade = smoothstep(0.02, 0.3, 1.0 - planar_distance / fade_radius);
	let fade = distance_fade;
	if (fade <= 0.001) {
		discard;
	}

	var color = vec3<f32>(0.31, 0.33, 0.36);
	var alpha = adaptive_grid_alpha(input.world_position.xz, camera_height);

	let x_axis = axis_coverage(input.world_position.z);
	let z_axis = axis_coverage(input.world_position.x);
	color = mix(color, vec3<f32>(0.78, 0.16, 0.18), x_axis);
	color = mix(color, vec3<f32>(0.16, 0.36, 0.78), z_axis);
	alpha = max(alpha, max(x_axis, z_axis) * 0.72);
	if (alpha <= 0.001) {
		discard;
	}
	return vec4<f32>(color, alpha * fade);
}
`

wgpu_create_editor_grid_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil {
		return "editor grid renderer is unavailable"
	}
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_EDITOR_GRID_SHADER,
	}
	renderer.editor_grid_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &shader_source,
			label = "Scrapbot Editor Grid Shader",
		},
	)
	if renderer.editor_grid_shader == nil {
		return "failed to create editor grid shader"
	}
	renderer.editor_grid_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Editor Grid Uniform",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Editor_Grid_Uniform)),
		},
	)
	if renderer.editor_grid_uniform_buffer == nil {
		return "failed to create editor grid uniform buffer"
	}
	entry := wgpu.BindGroupLayoutEntry {
		binding = 0,
		visibility = {.Vertex, .Fragment},
		buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Editor_Grid_Uniform))},
	}
	renderer.editor_grid_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Editor Grid Bind Group Layout",
			entryCount = 1,
			entries = &entry,
		},
	)
	if renderer.editor_grid_bind_group_layout == nil {
		return "failed to create editor grid bind group layout"
	}
	renderer.editor_grid_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Editor Grid Bind Group",
			layout = renderer.editor_grid_bind_group_layout,
			entryCount = 1,
			entries = &wgpu.BindGroupEntry {
				binding = 0,
				buffer = renderer.editor_grid_uniform_buffer,
				size = u64(size_of(WGPU_Editor_Grid_Uniform)),
			},
		},
	)
	if renderer.editor_grid_bind_group == nil {
		return "failed to create editor grid bind group"
	}
	renderer.editor_grid_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Editor Grid Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.editor_grid_bind_group_layout,
		},
	)
	if renderer.editor_grid_pipeline_layout == nil {
		return "failed to create editor grid pipeline layout"
	}
	blend := wgpu.BlendState {
		color = {operation = .Add, srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha},
		alpha = {operation = .Add, srcFactor = .Zero, dstFactor = .One},
	}
	target := wgpu.ColorTargetState {
		format = .RGBA16Float,
		blend = &blend,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.editor_grid_shader,
		entryPoint = "grid_fs",
		targetCount = 1,
		targets = &target,
	}
	renderer.editor_grid_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Editor Infinite Grid Pipeline",
			layout = renderer.editor_grid_pipeline_layout,
			vertex = {module = renderer.editor_grid_shader, entryPoint = "grid_vs"},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .Less,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.editor_grid_pipeline == nil {
		return "failed to create editor grid pipeline"
	}
	return ""
}

wgpu_release_editor_grid_resources :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.editor_grid_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.editor_grid_pipeline)
	}
	if renderer.editor_grid_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.editor_grid_pipeline_layout)
	}
	if renderer.editor_grid_bind_group != nil {
		wgpu.BindGroupRelease(renderer.editor_grid_bind_group)
	}
	if renderer.editor_grid_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.editor_grid_bind_group_layout)
	}
	if renderer.editor_grid_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.editor_grid_uniform_buffer)
	}
	if renderer.editor_grid_shader != nil {
		wgpu.ShaderModuleRelease(renderer.editor_grid_shader)
	}
}

wgpu_editor_grid_uniform :: proc(
	renderer: ^WGPU_Renderer,
	state: ^ui.State,
) -> WGPU_Editor_Grid_Uniform {
	camera := renderer.gpu_render_uniform.camera_position
	far := max(renderer.gpu_render_uniform.camera_clip.y, 100)
	extent := min(max(far, 100), f32(10000))
	return {
		view_projection = renderer.gpu_render_uniform.view_projection,
		camera_center_extent = {camera[0], camera[1], camera[2], extent},
		spacing_lod_fade = {1, 10, 0, 4},
	}
}

wgpu_encode_editor_grid_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	depth_view: wgpu.TextureView,
	state: ^ui.State,
	viewport: ui.Rect,
) -> string {
	if renderer == nil ||
	   state == nil ||
	   !state.editor_visible ||
	   renderer.editor_grid_pipeline == nil ||
	   renderer.hdr_view == nil ||
	   depth_view == nil {
		return ""
	}
	uniform := wgpu_editor_grid_uniform(renderer, state)
	if !renderer.editor_grid_uniform_valid || renderer.editor_grid_uniform != uniform {
		renderer.editor_grid_uniform = uniform
		renderer.editor_grid_uniform_valid = true
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.editor_grid_uniform_buffer,
			0,
			&uniform,
			uint(size_of(uniform)),
		)
	}
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = depth_view,
		depthLoadOp = .Load,
		depthStoreOp = .Store,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Editor Infinite Grid Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if pass == nil {
		return "failed to begin editor infinite grid pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		viewport.x,
		viewport.y,
		viewport.width,
		viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		u32(viewport.x),
		u32(viewport.y),
		u32(viewport.width),
		u32(viewport.height),
	)
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.editor_grid_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.editor_grid_bind_group)
	wgpu.RenderPassEncoderDraw(pass, 6, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}
