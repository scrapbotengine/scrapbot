package render

import resources "../resources"
import shared "../shared"
import "core:math"
import "vendor:wgpu"

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
			addressModeU = .ClampToEdge,
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
	return wgpu_rebuild_environment_textures(renderer, nil)
}

wgpu_sync_environment :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry) -> string {
	handle := shared.Environment_Handle{}
	version := u32(0)
	environment: ^resources.Environment
	if registry != nil {
		handle = registry.active_environment
		resolved, alive := resources.get_environment(registry, handle)
		if alive {
			environment = resolved
			version = resolved.version
		}
	}
	revision := u64(0)
	if registry != nil {
		revision = registry.environment_revision
	}
	if renderer.environment_cache_valid &&
	   renderer.environment_cached_handle == handle &&
	   renderer.environment_cached_version == version &&
	   renderer.environment_cached_revision == revision {
		return ""
	}
	textures_changed :=
		!renderer.environment_cache_valid ||
		renderer.environment_cached_handle != handle ||
		renderer.environment_cached_version != version
	if textures_changed {
		if err := wgpu_rebuild_environment_textures(renderer, environment); err != "" {
			return err
		}
	}
	uniform := WGPU_Environment_Uniform {
		exposure = 1,
	}
	if registry != nil {
		uniform.intensity = registry.environment_intensity
		uniform.rotation = registry.environment_rotation * f32(math.PI) / 180
		uniform.exposure = registry.exposure
	}
	if environment != nil {
		uniform.enabled = 1
		uniform.max_specular_lod = f32(environment.desc.specular_mip_count - 1)
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
	renderer.environment_cached_revision = revision
	renderer.environment_cache_valid = true
	return ""
}

wgpu_rebuild_environment_textures :: proc(
	renderer: ^WGPU_Renderer,
	environment: ^resources.Environment,
) -> string {
	wgpu_release_environment_textures(renderer)
	irradiance_size := u32(1)
	specular_size := u32(1)
	specular_mips := u32(1)
	if environment != nil {
		irradiance_size = environment.desc.irradiance_size
		specular_size = environment.desc.specular_size
		specular_mips = environment.desc.specular_mip_count
	}
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
	if renderer.environment_irradiance_texture == nil ||
	   renderer.environment_specular_texture == nil {
		return "failed to create environment cube textures"
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
	renderer.environment_irradiance_view = wgpu_create_environment_cube_view(
		renderer.environment_irradiance_texture,
		1,
	)
	renderer.environment_specular_view = wgpu_create_environment_cube_view(
		renderer.environment_specular_texture,
		specular_mips,
	)
	if renderer.environment_irradiance_view == nil || renderer.environment_specular_view == nil {
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
	if renderer.environment_irradiance_view != nil {
		wgpu.TextureViewRelease(renderer.environment_irradiance_view)
	}
	if renderer.environment_specular_view != nil {
		wgpu.TextureViewRelease(renderer.environment_specular_view)
	}
	if renderer.environment_irradiance_texture != nil {
		wgpu.TextureRelease(renderer.environment_irradiance_texture)
	}
	if renderer.environment_specular_texture != nil {
		wgpu.TextureRelease(renderer.environment_specular_texture)
	}
	renderer.environment_bind_group = nil
	renderer.environment_irradiance_view = nil
	renderer.environment_specular_view = nil
	renderer.environment_irradiance_texture = nil
	renderer.environment_specular_texture = nil
}

wgpu_release_environment_resources :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_environment_textures(renderer)
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
