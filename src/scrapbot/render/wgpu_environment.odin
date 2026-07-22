package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import "vendor:wgpu"

WGPU_SKY_SHADER :: `
struct Sky_Uniform {
	right: vec4<f32>,
	up: vec4<f32>,
	forward: vec4<f32>,
	projection: vec4<f32>,
};

struct Environment_Uniform {
	intensity: f32,
	rotation: f32,
	exposure: f32,
	enabled: f32,
	max_specular_lod: f32,
	background_intensity: f32,
	background_rotation: f32,
	background_exposure: f32,
	background_blur: f32,
	background_enabled: f32,
	background_max_specular_lod: f32,
	_padding: f32,
};

@group(0) @binding(0) var<uniform> sky: Sky_Uniform;
@group(1) @binding(0) var irradiance_cube: texture_cube<f32>;
@group(1) @binding(1) var specular_cube: texture_cube<f32>;
@group(1) @binding(2) var environment_sampler: sampler;
@group(1) @binding(3) var<uniform> environment: Environment_Uniform;
@group(1) @binding(4) var sky_panorama: texture_2d<f32>;
@group(1) @binding(5) var background_specular_cube: texture_cube<f32>;

struct Output {
	@builtin(position) position: vec4<f32>,
	@location(0) screen: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> Output {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(3.0, -1.0),
		vec2<f32>(-1.0, 3.0),
	);
	var output: Output;
	output.position = vec4<f32>(positions[index], 0.0, 1.0);
	output.screen = positions[index];
	return output;
}

@fragment
fn fs_main(input: Output) -> @location(0) vec4<f32> {
	if (environment.background_enabled < 0.5) {
		discard;
	}
	let direction = normalize(
		sky.forward.xyz +
		sky.right.xyz * input.screen.x * sky.projection.x * sky.projection.y +
		sky.up.xyz * input.screen.y * sky.projection.y
	);
	let c = cos(environment.background_rotation);
	let s = sin(environment.background_rotation);
	let rotated = vec3<f32>(
		c * direction.x - s * direction.z,
		direction.y,
		s * direction.x + c * direction.z,
	);
	let longitude = atan2(rotated.z, rotated.x) / (2.0 * 3.141592653589793) + 0.5;
	let latitude = asin(clamp(rotated.y, -1.0, 1.0)) / 3.141592653589793 + 0.5;
	let panorama_color = textureSampleLevel(
		sky_panorama,
		environment_sampler,
		vec2<f32>(longitude, 1.0 - latitude),
		0.0,
	).rgb;
	let blur = clamp(environment.background_blur, 0.0, 1.0);
	let blurred_color = textureSampleLevel(
		background_specular_cube,
		environment_sampler,
		rotated,
		blur * environment.background_max_specular_lod,
	).rgb;
	let color = mix(panorama_color, blurred_color, smoothstep(0.0, 0.1, blur));
	return vec4<f32>(
		color * environment.background_intensity * environment.background_exposure * environment.exposure,
		1.0,
	);
}
`

wgpu_create_environment_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = .Cube},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = .Cube},
		},
		{binding = 2, visibility = {.Fragment}, sampler = {type = .Filtering}},
		{
			binding = 3,
			visibility = {.Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Environment_Uniform))},
		},
		{
			binding = 4,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = .Cube},
		},
	}
	renderer.environment_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Environment Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.environment_bind_group_layout == nil {
		return "failed to create environment bind group layout"
	}
	renderer.environment_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Environment Sampler",
			addressModeU = .Repeat,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			maxAnisotropy = 1,
		},
	)
	renderer.environment_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Environment Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Environment_Uniform)),
		},
	)
	if renderer.environment_sampler == nil || renderer.environment_uniform_buffer == nil {
		return "failed to create environment sampler or uniform buffer"
	}
	if err := wgpu_create_sky_resources(renderer); err != "" {
		return err
	}
	return wgpu_rebuild_environment_textures(renderer, nil, nil)
}

wgpu_create_sky_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	entry := wgpu.BindGroupLayoutEntry {
		binding = 0,
		visibility = {.Fragment},
		buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Sky_Uniform))},
	}
	renderer.sky_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Sky Bind Group Layout",
			entryCount = 1,
			entries = &entry,
		},
	)
	renderer.sky_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Sky Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Sky_Uniform)),
		},
	)
	if renderer.sky_bind_group_layout == nil || renderer.sky_uniform_buffer == nil {
		return "failed to create sky uniform resources"
	}
	bind_entry := wgpu.BindGroupEntry {
		binding = 0,
		buffer = renderer.sky_uniform_buffer,
		size = u64(size_of(WGPU_Sky_Uniform)),
	}
	renderer.sky_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Sky Bind Group",
			layout = renderer.sky_bind_group_layout,
			entryCount = 1,
			entries = &bind_entry,
		},
	)
	layouts := [?]wgpu.BindGroupLayout {
		renderer.sky_bind_group_layout,
		renderer.environment_bind_group_layout,
	}
	renderer.sky_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Sky Pipeline Layout",
			bindGroupLayoutCount = uint(len(layouts)),
			bindGroupLayouts = raw_data(layouts[:]),
		},
	)
	shader_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_SKY_SHADER,
	}
	renderer.sky_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &shader_source, label = "Scrapbot Sky Shader"},
	)
	target := wgpu.ColorTargetState {
		format = .RGBA16Float,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.sky_shader,
		entryPoint = "fs_main",
		targetCount = 1,
		targets = &target,
	}
	renderer.sky_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Sky Pipeline",
			layout = renderer.sky_pipeline_layout,
			vertex = {module = renderer.sky_shader, entryPoint = "vs_main"},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.sky_bind_group == nil ||
	   renderer.sky_pipeline_layout == nil ||
	   renderer.sky_shader == nil ||
	   renderer.sky_pipeline == nil {
		return "failed to create sky pipeline"
	}
	return ""
}

wgpu_encode_sky_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	ui_state: ^ui.State,
	target_width, target_height: u32,
) -> string {
	viewport := ui.editor_viewport(ui_state, f32(target_width), f32(target_height))
	wgpu_update_sky_uniform(renderer, &renderer.render_list, viewport.width, viewport.height)
	color_attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = wgpu.Color{0.08, 0.10, 0.12, 1.0},
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Sky Pass",
			colorAttachmentCount = 1,
			colorAttachments = &color_attachment,
		},
	)
	if pass == nil {
		return "failed to begin sky render pass"
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
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.sky_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.sky_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(pass, 1, renderer.environment_bind_group)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_update_sky_uniform :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^shared.Render_List,
	width, height: f32,
) {
	uniform := wgpu_build_sky_uniform(render_list, width, height)
	if !wgpu_retain_sky_uniform(renderer, uniform) {
		return
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.sky_uniform_buffer,
		0,
		&uniform,
		size_of(uniform),
	)
}

wgpu_retain_sky_uniform :: proc(renderer: ^WGPU_Renderer, uniform: WGPU_Sky_Uniform) -> bool {
	if renderer.sky_uniform_cache_valid && renderer.sky_cached_uniform == uniform {
		return false
	}
	renderer.sky_cached_uniform = uniform
	renderer.sky_uniform_cache_valid = true
	return true
}

wgpu_build_sky_uniform :: proc(
	render_list: ^shared.Render_List,
	width, height: f32,
) -> WGPU_Sky_Uniform {
	right := shared.Vec3{1, 0, 0}
	up := shared.Vec3{0, 1, 0}
	forward := shared.Vec3{0, 0, -1}
	fov := f32(60)
	if render_list != nil && render_list.has_camera {
		rotation := render_list.camera.transform.rotation
		right = shared.camera_right(rotation)
		up = shared.camera_up(rotation)
		forward = shared.camera_forward(rotation)
		if render_list.camera.camera.fov > 0 {
			fov = render_list.camera.camera.fov
		}
	}
	aspect := f32(16.0 / 9.0)
	if height > 0 {
		aspect = width / height
	}
	return WGPU_Sky_Uniform {
		right = {right.x, right.y, right.z, 0},
		up = {up.x, up.y, up.z, 0},
		forward = {forward.x, forward.y, forward.z, 0},
		projection = {aspect, math.tan(math.to_radians(fov) * 0.5), 0, 0},
	}
}

wgpu_sync_environment :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	render_list: ^shared.Render_List,
) -> string {
	handle := shared.Environment_Handle{}
	version := u32(0)
	environment: ^resources.Environment
	background_handle := shared.Environment_Handle{}
	background_version := u32(0)
	background_environment: ^resources.Environment
	if registry != nil {
		handle = registry.active_environment
		resolved, alive := resources.get_environment(registry, handle)
		if alive {
			environment = resolved
			version = resolved.version
		}
		if registry.background_visible {
			background_handle = registry.background_environment
			resolved_background, background_alive := resources.get_environment(
				registry,
				background_handle,
			)
			if background_alive {
				background_environment = resolved_background
				background_version = resolved_background.version
			}
		}
	}
	revision := u64(0)
	if registry != nil {
		revision = registry.environment_revision
	}
	camera_exposure := f32(1)
	if render_list != nil && render_list.has_camera {
		camera_exposure = shared.camera_exposure(render_list.camera.camera)
	}
	if math.is_nan(camera_exposure) || math.is_inf(camera_exposure) || camera_exposure <= 0 {
		camera_exposure = 1
	}
	if renderer.environment_cache_valid &&
	   renderer.environment_cached_handle == handle &&
	   renderer.environment_cached_version == version &&
	   renderer.environment_cached_background_handle == background_handle &&
	   renderer.environment_cached_background_version == background_version &&
	   renderer.environment_cached_revision == revision &&
	   renderer.environment_cached_camera_exposure == camera_exposure {
		return ""
	}
	textures_changed :=
		!renderer.environment_cache_valid ||
		renderer.environment_cached_handle != handle ||
		renderer.environment_cached_version != version ||
		renderer.environment_cached_background_handle != background_handle ||
		renderer.environment_cached_background_version != background_version
	if textures_changed {
		if err := wgpu_rebuild_environment_textures(renderer, environment, background_environment);
		   err != "" {
			return err
		}
	}
	uniform := WGPU_Environment_Uniform {
		exposure = 1,
	}
	if registry != nil {
		uniform.intensity = registry.environment_intensity
		uniform.rotation = registry.environment_rotation * f32(math.PI) / 180
		uniform.exposure = registry.exposure * camera_exposure
		uniform.background_intensity = registry.background_intensity
		uniform.background_rotation = registry.background_rotation * f32(math.PI) / 180
		uniform.background_exposure = registry.background_exposure
		uniform.background_blur = registry.background_blur
	}
	if environment != nil {
		uniform.enabled = 1
		uniform.max_specular_lod = f32(environment.desc.specular_mip_count - 1)
	}
	if background_environment != nil {
		uniform.background_enabled = 1
		uniform.background_max_specular_lod = f32(
			background_environment.desc.specular_mip_count - 1,
		)
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.environment_uniform_buffer,
		0,
		&uniform,
		size_of(uniform),
	)
	renderer.environment_cached_handle = handle
	renderer.environment_cached_version = version
	renderer.environment_cached_background_handle = background_handle
	renderer.environment_cached_background_version = background_version
	renderer.environment_cached_revision = revision
	renderer.environment_cached_camera_exposure = camera_exposure
	renderer.environment_cache_valid = true
	return ""
}

wgpu_rebuild_environment_textures :: proc(
	renderer: ^WGPU_Renderer,
	environment: ^resources.Environment,
	background_environment: ^resources.Environment,
) -> string {
	wgpu_release_environment_textures(renderer)
	irradiance_size := u32(1)
	specular_size := u32(1)
	specular_mips := u32(1)
	sky_width := u32(1)
	sky_height := u32(1)
	background_specular_size := u32(1)
	background_specular_mips := u32(1)
	if environment != nil {
		irradiance_size = environment.desc.irradiance_size
		specular_size = environment.desc.specular_size
		specular_mips = environment.desc.specular_mip_count
	}
	if background_environment != nil {
		sky_width = background_environment.desc.sky_width
		sky_height = background_environment.desc.sky_height
		background_specular_size = background_environment.desc.specular_size
		background_specular_mips = background_environment.desc.specular_mip_count
	}
	renderer.environment_sky_texture = wgpu_create_environment_2d_texture(
		renderer,
		"Scrapbot HDR Sky Panorama",
		sky_width,
		sky_height,
	)
	renderer.environment_irradiance_texture = wgpu_create_environment_cube_texture(
		renderer,
		"Scrapbot Irradiance Cube",
		irradiance_size,
		1,
	)
	renderer.environment_specular_texture = wgpu_create_environment_cube_texture(
		renderer,
		"Scrapbot Prefiltered Environment Cube",
		specular_size,
		specular_mips,
	)
	renderer.environment_background_specular_texture = wgpu_create_environment_cube_texture(
		renderer,
		"Scrapbot Background Prefiltered Environment Cube",
		background_specular_size,
		background_specular_mips,
	)
	if renderer.environment_sky_texture == nil ||
	   renderer.environment_irradiance_texture == nil ||
	   renderer.environment_specular_texture == nil ||
	   renderer.environment_background_specular_texture == nil {
		return "failed to create environment sky or lighting textures"
	}
	if environment == nil {
		black := [24]u16{}
		wgpu_upload_environment_cube_level(
			renderer,
			renderer.environment_irradiance_texture,
			black[:],
			1,
			0,
		)
		wgpu_upload_environment_cube_level(
			renderer,
			renderer.environment_specular_texture,
			black[:],
			1,
			0,
		)
	} else {
		wgpu_upload_environment_cube_level(
			renderer,
			renderer.environment_irradiance_texture,
			environment.desc.irradiance_pixels,
			environment.desc.irradiance_size,
			0,
		)
		cursor := 0
		for mip in 0 ..< int(environment.desc.specular_mip_count) {
			size := max(environment.desc.specular_size >> u32(mip), 1)
			value_count := int(size * size * 6 * 4)
			wgpu_upload_environment_cube_level(
				renderer,
				renderer.environment_specular_texture,
				environment.desc.specular_pixels[cursor:cursor + value_count],
				size,
				u32(mip),
			)
			cursor += value_count
		}
	}
	if background_environment == nil {
		black_2d := [4]u16{}
		black_cube := [24]u16{}
		wgpu_upload_environment_2d(renderer, renderer.environment_sky_texture, black_2d[:], 1, 1)
		wgpu_upload_environment_cube_level(
			renderer,
			renderer.environment_background_specular_texture,
			black_cube[:],
			1,
			0,
		)
	} else {
		wgpu_upload_environment_2d(
			renderer,
			renderer.environment_sky_texture,
			background_environment.desc.sky_pixels,
			background_environment.desc.sky_width,
			background_environment.desc.sky_height,
		)
		cursor := 0
		for mip in 0 ..< int(background_environment.desc.specular_mip_count) {
			size := max(background_environment.desc.specular_size >> u32(mip), 1)
			value_count := int(size * size * 6 * 4)
			wgpu_upload_environment_cube_level(
				renderer,
				renderer.environment_background_specular_texture,
				background_environment.desc.specular_pixels[cursor:cursor + value_count],
				size,
				u32(mip),
			)
			cursor += value_count
		}
	}
	renderer.environment_sky_view = wgpu.TextureCreateView(
		renderer.environment_sky_texture,
		&wgpu.TextureViewDescriptor {
			format = .RGBA16Float,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
			usage = {.TextureBinding},
		},
	)
	renderer.environment_irradiance_view = wgpu_create_environment_cube_view(
		renderer.environment_irradiance_texture,
		1,
	)
	renderer.environment_specular_view = wgpu_create_environment_cube_view(
		renderer.environment_specular_texture,
		specular_mips,
	)
	renderer.environment_background_specular_view = wgpu_create_environment_cube_view(
		renderer.environment_background_specular_texture,
		background_specular_mips,
	)
	if renderer.environment_sky_view == nil ||
	   renderer.environment_irradiance_view == nil ||
	   renderer.environment_specular_view == nil ||
	   renderer.environment_background_specular_view == nil {
		return "failed to create environment cube views"
	}
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = renderer.environment_irradiance_view},
		{binding = 1, textureView = renderer.environment_specular_view},
		{binding = 2, sampler = renderer.environment_sampler},
		{
			binding = 3,
			buffer = renderer.environment_uniform_buffer,
			size = u64(size_of(WGPU_Environment_Uniform)),
		},
		{binding = 4, textureView = renderer.environment_sky_view},
		{binding = 5, textureView = renderer.environment_background_specular_view},
	}
	renderer.environment_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Environment Bind Group",
			layout = renderer.environment_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.environment_bind_group == nil {
		return "failed to create environment bind group"
	}
	return ""
}

wgpu_create_environment_2d_texture :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	width, height: u32,
) -> wgpu.Texture {
	return wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA16Float,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
}

wgpu_upload_environment_2d :: proc(
	renderer: ^WGPU_Renderer,
	texture: wgpu.Texture,
	pixels: []u16,
	width, height: u32,
) {
	wgpu.QueueWriteTexture(
		renderer.queue,
		&wgpu.TexelCopyTextureInfo{texture = texture, aspect = .All},
		raw_data(pixels),
		uint(len(pixels) * size_of(u16)),
		&wgpu.TexelCopyBufferLayout{bytesPerRow = width * 8, rowsPerImage = height},
		&wgpu.Extent3D{width = width, height = height, depthOrArrayLayers = 1},
	)
}

wgpu_create_environment_cube_texture :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	size, mip_count: u32,
) -> wgpu.Texture {
	return wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = size, height = size, depthOrArrayLayers = 6},
			format = .RGBA16Float,
			mipLevelCount = mip_count,
			sampleCount = 1,
		},
	)
}

wgpu_create_environment_cube_view :: proc(
	texture: wgpu.Texture,
	mip_count: u32,
) -> wgpu.TextureView {
	return wgpu.TextureCreateView(
		texture,
		&wgpu.TextureViewDescriptor {
			format = .RGBA16Float,
			dimension = .Cube,
			baseMipLevel = 0,
			mipLevelCount = mip_count,
			baseArrayLayer = 0,
			arrayLayerCount = 6,
			aspect = .All,
			usage = {.TextureBinding},
		},
	)
}

wgpu_upload_environment_cube_level :: proc(
	renderer: ^WGPU_Renderer,
	texture: wgpu.Texture,
	pixels: []u16,
	size, mip: u32,
) {
	face_value_count := int(size * size * 4)
	for face in 0 ..< 6 {
		values := pixels[face * face_value_count:(face + 1) * face_value_count]
		wgpu.QueueWriteTexture(
			renderer.queue,
			&wgpu.TexelCopyTextureInfo {
				texture = texture,
				mipLevel = mip,
				origin = {z = u32(face)},
				aspect = .All,
			},
			raw_data(values),
			uint(len(values) * size_of(u16)),
			&wgpu.TexelCopyBufferLayout{bytesPerRow = size * 8, rowsPerImage = size},
			&wgpu.Extent3D{width = size, height = size, depthOrArrayLayers = 1},
		)
	}
}

wgpu_release_environment_textures :: proc(renderer: ^WGPU_Renderer) {
	if renderer.environment_bind_group != nil {
		wgpu.BindGroupRelease(renderer.environment_bind_group)
	}
	if renderer.environment_sky_view != nil {
		wgpu.TextureViewRelease(renderer.environment_sky_view)
	}
	if renderer.environment_irradiance_view != nil {
		wgpu.TextureViewRelease(renderer.environment_irradiance_view)
	}
	if renderer.environment_specular_view != nil {
		wgpu.TextureViewRelease(renderer.environment_specular_view)
	}
	if renderer.environment_background_specular_view != nil {
		wgpu.TextureViewRelease(renderer.environment_background_specular_view)
	}
	if renderer.environment_irradiance_texture != nil {
		wgpu.TextureRelease(renderer.environment_irradiance_texture)
	}
	if renderer.environment_specular_texture != nil {
		wgpu.TextureRelease(renderer.environment_specular_texture)
	}
	if renderer.environment_background_specular_texture != nil {
		wgpu.TextureRelease(renderer.environment_background_specular_texture)
	}
	if renderer.environment_sky_texture != nil {
		wgpu.TextureRelease(renderer.environment_sky_texture)
	}
	renderer.environment_bind_group = nil
	renderer.environment_sky_view = nil
	renderer.environment_sky_texture = nil
	renderer.environment_irradiance_view = nil
	renderer.environment_specular_view = nil
	renderer.environment_background_specular_view = nil
	renderer.environment_irradiance_texture = nil
	renderer.environment_specular_texture = nil
	renderer.environment_background_specular_texture = nil
}

wgpu_release_environment_resources :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_environment_textures(renderer)
	if renderer.sky_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.sky_pipeline)
	}
	if renderer.sky_shader != nil {
		wgpu.ShaderModuleRelease(renderer.sky_shader)
	}
	if renderer.sky_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.sky_pipeline_layout)
	}
	if renderer.sky_bind_group != nil {
		wgpu.BindGroupRelease(renderer.sky_bind_group)
	}
	if renderer.sky_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.sky_uniform_buffer)
	}
	if renderer.sky_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.sky_bind_group_layout)
	}
	if renderer.environment_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.environment_uniform_buffer)
	}
	if renderer.environment_sampler != nil {
		wgpu.SamplerRelease(renderer.environment_sampler)
	}
	if renderer.environment_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.environment_bind_group_layout)
	}
}
