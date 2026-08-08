package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "vendor:wgpu"

WGPU_Distance_Field_Debug_Uniform :: struct {
	dimensions: [4]u32,
	viewport: [4]f32,
	parameters: [4]f32,
}
#assert(size_of(WGPU_Distance_Field_Debug_Uniform) == 48)

wgpu_pack_distance_field_samples :: proc(samples: []i16, allocator := context.allocator) -> []u32 {
	packed := make([]u32, (len(samples) + 1) / 2, allocator)
	for sample, index in samples {
		word_index := index / 2
		bits := u32(transmute(u16)sample)
		if index % 2 == 0 {
			packed[word_index] |= bits
		} else {
			packed[word_index] |= bits << 16
		}
	}
	return packed
}

wgpu_unpack_distance_field_sample :: proc "contextless" (packed: []u32, index: int) -> i16 {
	word := packed[index / 2]
	bits := u16(word & 0xffff) if index % 2 == 0 else u16(word >> 16)
	return transmute(i16)bits
}

wgpu_create_distance_field_debug_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_DISTANCE_FIELD_DEBUG_SHADER,
	}
	renderer.gpu_distance_field_debug_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &chain,
			label = "Scrapbot Distance Field Debug Shader",
		},
	)
	if renderer.gpu_distance_field_debug_shader == nil {
		return "failed to create distance-field debug shader"
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Distance_Field_Debug_Uniform)),
			},
		},
	}
	renderer.gpu_distance_field_debug_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Distance Field Debug Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_distance_field_debug_bind_group_layout == nil {
		return "failed to create distance-field debug bind group layout"
	}
	renderer.gpu_distance_field_debug_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Distance Field Debug Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_distance_field_debug_bind_group_layout,
		},
	)
	if renderer.gpu_distance_field_debug_pipeline_layout == nil {
		return "failed to create distance-field debug pipeline layout"
	}
	renderer.gpu_distance_field_debug_pipeline = wgpu_create_fullscreen_pipeline(
		renderer,
		renderer.gpu_distance_field_debug_shader,
		renderer.gpu_distance_field_debug_pipeline_layout,
		"distance_field_debug_fs",
		.RGBA16Float,
		"Scrapbot Distance Field Debug Pipeline",
	)
	if renderer.gpu_distance_field_debug_pipeline == nil {
		return "failed to create distance-field debug pipeline"
	}
	return ""
}

wgpu_release_geometry_distance_field :: proc(cached: ^WGPU_Geometry_Cache) {
	if cached == nil {
		return
	}
	if cached.distance_field_bind_group != nil {
		wgpu.BindGroupRelease(cached.distance_field_bind_group)
	}
	if cached.distance_field_uniform_buffer != nil {
		wgpu.BufferRelease(cached.distance_field_uniform_buffer)
	}
	if cached.distance_field_buffer != nil {
		wgpu.BufferRelease(cached.distance_field_buffer)
	}
	cached.distance_field_bind_group = nil
	cached.distance_field_uniform_buffer = nil
	cached.distance_field_buffer = nil
	cached.distance_field_bytes = 0
}

wgpu_release_distance_field_debug :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.gpu_distance_field_debug_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.gpu_distance_field_debug_pipeline)
	}
	if renderer.gpu_distance_field_debug_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_distance_field_debug_pipeline_layout)
	}
	if renderer.gpu_distance_field_debug_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_distance_field_debug_bind_group_layout)
	}
	if renderer.gpu_distance_field_debug_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_distance_field_debug_shader)
	}
}

wgpu_ensure_geometry_distance_field :: proc(
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	cached: ^WGPU_Geometry_Cache,
) -> string {
	if renderer == nil || geometry == nil || cached == nil {
		return "distance-field GPU cache is unavailable"
	}
	if cached.distance_field_buffer != nil && cached.distance_field_bind_group != nil {
		return ""
	}
	if geometry.distance_field.product_size == 0 {
		return "geometry has no distance field"
	}
	samples, sample_err := resources.load_geometry_distance_field_samples(
		geometry,
		context.temp_allocator,
	)
	if sample_err != "" {
		return sample_err
	}
	defer delete(samples, context.temp_allocator)
	packed := wgpu_pack_distance_field_samples(samples, context.temp_allocator)
	defer delete(packed, context.temp_allocator)
	packed_bytes := u64(len(packed) * size_of(u32))
	buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Geometry Distance Field",
		{.Storage, .CopyDst},
		max(packed_bytes, u64(4)),
	)
	uniform_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Distance Field Debug Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_Distance_Field_Debug_Uniform)),
	)
	if buffer == nil || uniform_buffer == nil {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
		if uniform_buffer != nil {
			wgpu.BufferRelease(uniform_buffer)
		}
		return "failed to create distance-field GPU buffers"
	}
	wgpu.QueueWriteBuffer(renderer.queue, buffer, 0, raw_data(packed), uint(packed_bytes))
	bind_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = buffer, offset = 0, size = max(packed_bytes, u64(4))},
		{
			binding = 1,
			buffer = uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Distance_Field_Debug_Uniform)),
		},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Distance Field Debug Bind Group",
			layout = renderer.gpu_distance_field_debug_bind_group_layout,
			entryCount = uint(len(bind_entries)),
			entries = raw_data(bind_entries[:]),
		},
	)
	if bind_group == nil {
		wgpu.BufferRelease(buffer)
		wgpu.BufferRelease(uniform_buffer)
		return "failed to create distance-field debug bind group"
	}
	cached.distance_field_buffer = buffer
	cached.distance_field_uniform_buffer = uniform_buffer
	cached.distance_field_bind_group = bind_group
	cached.distance_field_bytes = geometry.distance_field.product_size
	return ""
}

wgpu_encode_distance_field_debug_view :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	viewport: ui.Rect,
) -> string {
	if renderer == nil ||
	   registry == nil ||
	   renderer.gpu_render_uniform.debug.x != u32(shared.Render_Debug_View.Distance_Field) {
		return ""
	}
	geometry: ^resources.Geometry
	cached: ^WGPU_Geometry_Cache
	for batch in renderer.draw_batch_cache.batches {
		candidate, alive := resources.get_geometry(registry, batch.geometry)
		if !alive || candidate.distance_field.product_size == 0 {
			continue
		}
		cache_err: string
		cached, cache_err = wgpu_geometry_cache(
			renderer,
			registry,
			batch.geometry,
			batch.geometry_mode,
		)
		if cache_err != "" {
			return cache_err
		}
		geometry = candidate
		break
	}
	if geometry == nil || cached == nil {
		return ""
	}
	if cache_err := wgpu_ensure_geometry_distance_field(renderer, geometry, cached);
	   cache_err != "" {
		return cache_err
	}
	uniform := WGPU_Distance_Field_Debug_Uniform {
		dimensions = {
			geometry.distance_field.dimensions[0],
			geometry.distance_field.dimensions[1],
			geometry.distance_field.dimensions[2],
			0,
		},
		viewport = {viewport.x, viewport.y, viewport.width, viewport.height},
		parameters = {
			geometry.distance_field.value_scale,
			geometry.distance_field.voxel_size,
			1 if geometry.distance_field.signed else 0,
			0.5,
		},
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		cached.distance_field_uniform_buffer,
		0,
		&uniform,
		size_of(uniform),
	)
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Distance Field Debug View Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
		},
	)
	if pass == nil {
		return "failed to begin distance-field debug view pass"
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
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.gpu_distance_field_debug_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, cached.distance_field_bind_group)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

WGPU_DISTANCE_FIELD_DEBUG_SHADER :: `
struct Distance_Field_Debug_Uniform {
	dimensions: vec4<u32>,
	viewport: vec4<f32>,
	parameters: vec4<f32>,
};

@group(0) @binding(0) var<storage, read> samples: array<u32>;
@group(0) @binding(1) var<uniform> field: Distance_Field_Debug_Uniform;

struct Fullscreen_Output {
	@builtin(position) position: vec4<f32>,
};

@vertex
fn fullscreen_vs(@builtin(vertex_index) index: u32) -> Fullscreen_Output {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(3.0, -1.0),
		vec2<f32>(-1.0, 3.0),
	);
	var output: Fullscreen_Output;
	output.position = vec4<f32>(positions[index], 0.0, 1.0);
	return output;
}

fn read_sample(index: u32) -> f32 {
	let word = samples[index / 2u];
	let packed = select(word & 0xffffu, word >> 16u, (index & 1u) != 0u);
	let signed_value = bitcast<i32>(packed << 16u) >> 16;
	return f32(signed_value) * field.parameters.x;
}

@fragment
fn distance_field_debug_fs(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	let uv = clamp(
		(input.position.xy - field.viewport.xy) / max(field.viewport.zw, vec2<f32>(1.0)),
		vec2<f32>(0.0),
		vec2<f32>(0.999999),
	);
	let x = min(u32(uv.x * f32(field.dimensions.x)), field.dimensions.x - 1u);
	let y = min(u32((1.0 - uv.y) * f32(field.dimensions.y)), field.dimensions.y - 1u);
	let z = min(u32(field.parameters.w * f32(field.dimensions.z)), field.dimensions.z - 1u);
	let index = x + field.dimensions.x * (y + field.dimensions.y * z);
	let distance = read_sample(index);
	let magnitude = clamp(abs(distance) / max(field.parameters.y * 5.0, 0.000001), 0.0, 1.0);
	let positive = mix(vec3<f32>(0.98, 0.95, 0.82), vec3<f32>(0.95, 0.23, 0.08), magnitude);
	let negative = mix(vec3<f32>(0.90, 0.97, 1.0), vec3<f32>(0.04, 0.26, 0.95), magnitude);
	let unsigned_color = mix(vec3<f32>(0.02, 0.04, 0.05), vec3<f32>(0.10, 0.92, 0.82), 1.0 - magnitude);
	let signed_color = select(positive, negative, distance < 0.0);
	let color = select(unsigned_color, signed_color, field.parameters.z > 0.5);
	return vec4<f32>(color, 1.0);
}
`
