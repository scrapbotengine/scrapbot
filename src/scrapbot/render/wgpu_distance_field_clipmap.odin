package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import "vendor:wgpu"

WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT :: 3
WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION :: u32(32)
WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_VOXELS ::
	WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION *
	WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION *
	WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION
WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS ::
	WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_VOXELS * WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT
WGPU_DISTANCE_FIELD_CLIPMAP_JUMP_PASSES :: 5
WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT :: 256
WGPU_DISTANCE_FIELD_CLIPMAP_MAX_UNIFORMS :: 1024

WGPU_Distance_Field_Clipmap_Uniform :: struct {
	field_dimensions: [4]u32,
	field_bounds_min: [4]f32,
	field_bounds_max: [4]f32,
	field_parameters: [4]f32,
	cascade_centers: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT][4]f32,
	cascade_parameters: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT][4]f32,
	cascade_shifts: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT][4]i32,
	control: [4]u32,
	_padding: [8]u32,
}
#assert(
	size_of(WGPU_Distance_Field_Clipmap_Uniform) == WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
)

WGPU_Distance_Field_Clipmap_State :: struct {
	valid: bool,
	world_uuid: shared.Entity_UUID,
	topology_revision: u64,
	geometry_topology_revision: u64,
	centers: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT]Vec3,
	viewport: ui.Rect,
	rebuild_count: u64,
	scroll_count: u64,
	scroll_voxel_count: u64,
	dispatch_count: u64,
	upload_bytes: u64,
	instance_count: int,
	geometry_count: int,
}

WGPU_Distance_Field_Clipmap_Update :: struct {
	needed: bool,
	full_rebuild: bool,
	cascade_mask: u32,
	shifts: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT][3]i32,
	exposed_voxels: u32,
}

WGPU_DISTANCE_FIELD_CLIPMAP_ALL_CASCADES ::
	(u32(1) << WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT) - 1

wgpu_distance_field_clipmap_selected_cascade_count :: proc "contextless" (mask: u32) -> u32 {
	count: u32
	for cascade in 0 ..< WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT {
		if (mask & (u32(1) << u32(cascade))) != 0 {
			count += 1
		}
	}
	return count
}

WGPU_Distance_Field_Clipmap_Group :: struct {
	handle: shared.Geometry_Handle,
	virtual_geometry: bool,
	instance_offset: int,
	instance_count: int,
	sample_count: int,
}

wgpu_distance_field_clipmap_voxel_size :: proc "contextless" (cascade: int) -> f32 {
	return f32(u32(1) << u32(cascade * 2))
}

wgpu_distance_field_clipmap_centers :: proc "contextless" (
	camera_position: Vec3,
) -> [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT]Vec3 {
	centers: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT]Vec3
	for cascade in 0 ..< WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT {
		voxel_size := wgpu_distance_field_clipmap_voxel_size(cascade)
		centers[cascade] = {
			f32(math.floor(camera_position.x / voxel_size)) * voxel_size,
			f32(math.floor(camera_position.y / voxel_size)) * voxel_size,
			f32(math.floor(camera_position.z / voxel_size)) * voxel_size,
		}
	}
	return centers
}

wgpu_distance_field_clipmap_exposed_voxels :: proc "contextless" (shift: [3]i32) -> u32 {
	resolution := i32(WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION)
	overlap_x := max(resolution - math.abs(shift[0]), 0)
	overlap_y := max(resolution - math.abs(shift[1]), 0)
	overlap_z := max(resolution - math.abs(shift[2]), 0)
	return WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_VOXELS - u32(overlap_x * overlap_y * overlap_z)
}

wgpu_distance_field_clipmap_update :: proc "contextless" (
	state: WGPU_Distance_Field_Clipmap_State,
	render_list: ^Render_List,
	geometry_topology_revision: u64,
	centers: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT]Vec3,
	viewport: ui.Rect,
) -> WGPU_Distance_Field_Clipmap_Update {
	if render_list == nil {
		return {}
	}
	full_rebuild :=
		!state.valid ||
		state.world_uuid != render_list.world_uuid ||
		state.topology_revision != render_list.topology_revision ||
		state.geometry_topology_revision != geometry_topology_revision ||
		state.viewport != viewport ||
		len(render_list.dirty_instance_slots) > 0 ||
		len(render_list.dirty_transform_slots) > 0
	if full_rebuild {
		return {
			needed = true,
			full_rebuild = true,
			cascade_mask = WGPU_DISTANCE_FIELD_CLIPMAP_ALL_CASCADES,
			exposed_voxels = WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS,
		}
	}
	update: WGPU_Distance_Field_Clipmap_Update
	for cascade in 0 ..< WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT {
		if state.centers[cascade] == centers[cascade] {
			continue
		}
		voxel_size := wgpu_distance_field_clipmap_voxel_size(cascade)
		shift := [3]i32 {
			i32(math.round((centers[cascade].x - state.centers[cascade].x) / voxel_size)),
			i32(math.round((centers[cascade].y - state.centers[cascade].y) / voxel_size)),
			i32(math.round((centers[cascade].z - state.centers[cascade].z) / voxel_size)),
		}
		if math.abs(shift[0]) >= i32(WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION) ||
		   math.abs(shift[1]) >= i32(WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION) ||
		   math.abs(shift[2]) >= i32(WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION) {
			return {
				needed = true,
				full_rebuild = true,
				cascade_mask = WGPU_DISTANCE_FIELD_CLIPMAP_ALL_CASCADES,
				exposed_voxels = WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS,
			}
		}
		update.needed = true
		update.cascade_mask |= u32(1) << u32(cascade)
		update.shifts[cascade] = shift
		update.exposed_voxels += wgpu_distance_field_clipmap_exposed_voxels(shift)
	}
	return update
}

wgpu_distance_field_clipmap_metadata :: proc(
	centers: [WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT]Vec3,
	viewport: ui.Rect,
	update: WGPU_Distance_Field_Clipmap_Update = {},
) -> WGPU_Distance_Field_Clipmap_Uniform {
	uniform: WGPU_Distance_Field_Clipmap_Uniform
	uniform.field_dimensions = {
		WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION,
		WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION,
		WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION,
		WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_COUNT,
	}
	uniform.field_bounds_min = {viewport.x, viewport.y, viewport.width, viewport.height}
	for center, cascade in centers {
		voxel_size := wgpu_distance_field_clipmap_voxel_size(cascade)
		uniform.cascade_centers[cascade] = {center.x, center.y, center.z, 0}
		uniform.cascade_parameters[cascade] = {
			voxel_size,
			f32(WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_VOXELS * u32(cascade)),
			voxel_size * f32(WGPU_DISTANCE_FIELD_CLIPMAP_RESOLUTION),
			0,
		}
		uniform.cascade_shifts[cascade] = {
			update.shifts[cascade][0],
			update.shifts[cascade][1],
			update.shifts[cascade][2],
			0,
		}
	}
	uniform.control.y = update.cascade_mask
	uniform.control.z = u32(!update.full_rebuild)
	uniform.control.w = wgpu_distance_field_clipmap_selected_cascade_count(update.cascade_mask)
	return uniform
}

wgpu_distance_field_clipmap_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	layout: wgpu.PipelineLayout,
	entry_point, label: string,
) -> wgpu.ComputePipeline {
	return wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = label,
			layout = layout,
			compute = {
				module = renderer.gpu_distance_field_clipmap_shader,
				entryPoint = entry_point,
			},
		},
	)
}

wgpu_create_distance_field_clipmap_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_DISTANCE_FIELD_CLIPMAP_SHADER,
	}
	renderer.gpu_distance_field_clipmap_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &chain,
			label = "Scrapbot World Distance Field Shader",
		},
	)
	if renderer.gpu_distance_field_clipmap_shader == nil {
		return "failed to create world distance-field shader"
	}
	dynamic_uniform := wgpu.BufferBindingLayout {
		type = .Uniform,
		hasDynamicOffset = true,
		minBindingSize = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
	}
	raster_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{
			binding = 1,
			visibility = {.Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = size_of(WGPU_GPU_Instance)},
		},
		{
			binding = 2,
			visibility = {.Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 3, visibility = {.Compute}, buffer = {type = .Storage, minBindingSize = 4}},
		{binding = 4, visibility = {.Compute}, buffer = dynamic_uniform},
	}
	propagate_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 1, visibility = {.Compute}, buffer = {type = .Storage, minBindingSize = 4}},
		{binding = 2, visibility = {.Compute}, buffer = dynamic_uniform},
	}
	finalize_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 1, visibility = {.Compute}, buffer = {type = .Storage, minBindingSize = 4}},
		{
			binding = 2,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
			},
		},
	}
	debug_entries := [?]wgpu.BindGroupLayoutEntry {
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
				minBindingSize = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
			},
		},
	}
	renderer.gpu_distance_field_clipmap_raster_bind_group_layout =
		wgpu.DeviceCreateBindGroupLayout(
			renderer.device,
			&wgpu.BindGroupLayoutDescriptor {
				label = "Scrapbot World Distance Field Raster Layout",
				entryCount = len(raster_entries),
				entries = raw_data(raster_entries[:]),
			},
		)
	renderer.gpu_distance_field_clipmap_propagate_bind_group_layout =
		wgpu.DeviceCreateBindGroupLayout(
			renderer.device,
			&wgpu.BindGroupLayoutDescriptor {
				label = "Scrapbot World Distance Field Propagate Layout",
				entryCount = len(propagate_entries),
				entries = raw_data(propagate_entries[:]),
			},
		)
	renderer.gpu_distance_field_clipmap_finalize_bind_group_layout =
		wgpu.DeviceCreateBindGroupLayout(
			renderer.device,
			&wgpu.BindGroupLayoutDescriptor {
				label = "Scrapbot World Distance Field Finalize Layout",
				entryCount = len(finalize_entries),
				entries = raw_data(finalize_entries[:]),
			},
		)
	renderer.gpu_distance_field_clipmap_debug_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot World Distance Field Debug Layout",
			entryCount = len(debug_entries),
			entries = raw_data(debug_entries[:]),
		},
	)
	layouts := [?]^wgpu.BindGroupLayout {
		&renderer.gpu_distance_field_clipmap_raster_bind_group_layout,
		&renderer.gpu_distance_field_clipmap_propagate_bind_group_layout,
		&renderer.gpu_distance_field_clipmap_finalize_bind_group_layout,
		&renderer.gpu_distance_field_clipmap_debug_bind_group_layout,
	}
	pipeline_layouts := [?]^wgpu.PipelineLayout {
		&renderer.gpu_distance_field_clipmap_raster_pipeline_layout,
		&renderer.gpu_distance_field_clipmap_propagate_pipeline_layout,
		&renderer.gpu_distance_field_clipmap_finalize_pipeline_layout,
		&renderer.gpu_distance_field_clipmap_debug_pipeline_layout,
	}
	for layout, index in layouts {
		pipeline_layouts[index]^ = wgpu.DeviceCreatePipelineLayout(
			renderer.device,
			&wgpu.PipelineLayoutDescriptor {
				label = "Scrapbot World Distance Field Pipeline Layout",
				bindGroupLayoutCount = 1,
				bindGroupLayouts = layout,
			},
		)
	}
	if renderer.gpu_distance_field_clipmap_raster_pipeline_layout == nil ||
	   renderer.gpu_distance_field_clipmap_propagate_pipeline_layout == nil ||
	   renderer.gpu_distance_field_clipmap_finalize_pipeline_layout == nil ||
	   renderer.gpu_distance_field_clipmap_debug_pipeline_layout == nil {
		return "failed to create world distance-field pipeline layouts"
	}
	renderer.gpu_distance_field_clipmap_raster_pipeline = wgpu_distance_field_clipmap_pipeline(
		renderer,
		renderer.gpu_distance_field_clipmap_raster_pipeline_layout,
		"rasterize_fields",
		"Scrapbot World Distance Field Raster Pipeline",
	)
	renderer.gpu_distance_field_clipmap_shift_pipeline = wgpu_distance_field_clipmap_pipeline(
		renderer,
		renderer.gpu_distance_field_clipmap_propagate_pipeline_layout,
		"shift_seeds",
		"Scrapbot World Distance Field Shift Pipeline",
	)
	renderer.gpu_distance_field_clipmap_propagate_pipeline = wgpu_distance_field_clipmap_pipeline(
		renderer,
		renderer.gpu_distance_field_clipmap_propagate_pipeline_layout,
		"propagate_seeds",
		"Scrapbot World Distance Field Propagate Pipeline",
	)
	renderer.gpu_distance_field_clipmap_finalize_pipeline = wgpu_distance_field_clipmap_pipeline(
		renderer,
		renderer.gpu_distance_field_clipmap_finalize_pipeline_layout,
		"finalize_distances",
		"Scrapbot World Distance Field Finalize Pipeline",
	)
	renderer.gpu_distance_field_clipmap_debug_pipeline = wgpu_create_fullscreen_pipeline(
		renderer,
		renderer.gpu_distance_field_clipmap_shader,
		renderer.gpu_distance_field_clipmap_debug_pipeline_layout,
		"debug_world_distance_field",
		.RGBA16Float,
		"Scrapbot World Distance Field Debug Pipeline",
	)
	if renderer.gpu_distance_field_clipmap_shift_pipeline == nil ||
	   renderer.gpu_distance_field_clipmap_raster_pipeline == nil ||
	   renderer.gpu_distance_field_clipmap_propagate_pipeline == nil ||
	   renderer.gpu_distance_field_clipmap_finalize_pipeline == nil ||
	   renderer.gpu_distance_field_clipmap_debug_pipeline == nil {
		return "failed to create world distance-field pipelines"
	}
	voxel_bytes := u64(WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS * size_of(u32))
	for &buffer in renderer.gpu_distance_field_clipmap_seed_buffers {
		buffer = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot World Distance Field Seeds",
			{.Storage, .CopyDst},
			voxel_bytes,
		)
	}
	renderer.gpu_distance_field_clipmap_distance_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot World Distance Field Distances",
		{.Storage, .CopyDst},
		voxel_bytes,
	)
	renderer.gpu_distance_field_clipmap_instance_slot_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot World Distance Field Instance Slots",
		{.Storage, .CopyDst},
		u64(WGPU_MAX_GPU_INSTANCES * size_of(u32)),
	)
	renderer.gpu_distance_field_clipmap_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot World Distance Field Uniforms",
		{.Uniform, .CopyDst},
		WGPU_DISTANCE_FIELD_CLIPMAP_MAX_UNIFORMS * WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
	)
	if renderer.gpu_distance_field_clipmap_seed_buffers[0] == nil ||
	   renderer.gpu_distance_field_clipmap_seed_buffers[1] == nil ||
	   renderer.gpu_distance_field_clipmap_distance_buffer == nil ||
	   renderer.gpu_distance_field_clipmap_instance_slot_buffer == nil ||
	   renderer.gpu_distance_field_clipmap_uniform_buffer == nil {
		return "failed to create world distance-field buffers"
	}
	for index in 0 ..< 2 {
		entries := [?]wgpu.BindGroupEntry {
			{
				binding = 0,
				buffer = renderer.gpu_distance_field_clipmap_seed_buffers[index],
				size = voxel_bytes,
			},
			{
				binding = 1,
				buffer = renderer.gpu_distance_field_clipmap_seed_buffers[1 - index],
				size = voxel_bytes,
			},
			{
				binding = 2,
				buffer = renderer.gpu_distance_field_clipmap_uniform_buffer,
				size = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
			},
		}
		renderer.gpu_distance_field_clipmap_propagate_bind_groups[index] =
			wgpu.DeviceCreateBindGroup(
				renderer.device,
				&wgpu.BindGroupDescriptor {
					label = "Scrapbot World Distance Field Propagate Bind Group",
					layout = renderer.gpu_distance_field_clipmap_propagate_bind_group_layout,
					entryCount = len(entries),
					entries = raw_data(entries[:]),
				},
			)
	}
	finalize_entries_bind := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_distance_field_clipmap_seed_buffers[1],
			size = voxel_bytes,
		},
		{
			binding = 1,
			buffer = renderer.gpu_distance_field_clipmap_distance_buffer,
			size = voxel_bytes,
		},
		{
			binding = 2,
			buffer = renderer.gpu_distance_field_clipmap_uniform_buffer,
			size = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
		},
	}
	renderer.gpu_distance_field_clipmap_finalize_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot World Distance Field Finalize Bind Group",
			layout = renderer.gpu_distance_field_clipmap_finalize_bind_group_layout,
			entryCount = len(finalize_entries_bind),
			entries = raw_data(finalize_entries_bind[:]),
		},
	)
	debug_entries_bind := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_distance_field_clipmap_distance_buffer,
			size = voxel_bytes,
		},
		{
			binding = 1,
			buffer = renderer.gpu_distance_field_clipmap_uniform_buffer,
			size = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
		},
	}
	renderer.gpu_distance_field_clipmap_debug_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot World Distance Field Debug Bind Group",
			layout = renderer.gpu_distance_field_clipmap_debug_bind_group_layout,
			entryCount = len(debug_entries_bind),
			entries = raw_data(debug_entries_bind[:]),
		},
	)
	if renderer.gpu_distance_field_clipmap_propagate_bind_groups[0] == nil ||
	   renderer.gpu_distance_field_clipmap_propagate_bind_groups[1] == nil ||
	   renderer.gpu_distance_field_clipmap_finalize_bind_group == nil ||
	   renderer.gpu_distance_field_clipmap_debug_bind_group == nil {
		return "failed to create world distance-field bind groups"
	}
	return ""
}

wgpu_release_distance_field_clipmap :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	for bind_group in renderer.gpu_distance_field_clipmap_propagate_bind_groups {
		if bind_group != nil {
			wgpu.BindGroupRelease(bind_group)
		}
	}
	if renderer.gpu_distance_field_clipmap_finalize_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_distance_field_clipmap_finalize_bind_group)
	}
	if renderer.gpu_distance_field_clipmap_debug_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_distance_field_clipmap_debug_bind_group)
	}
	for buffer in renderer.gpu_distance_field_clipmap_seed_buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	if renderer.gpu_distance_field_clipmap_distance_buffer != nil {
		wgpu.BufferRelease(renderer.gpu_distance_field_clipmap_distance_buffer)
	}
	if renderer.gpu_distance_field_clipmap_instance_slot_buffer != nil {
		wgpu.BufferRelease(renderer.gpu_distance_field_clipmap_instance_slot_buffer)
	}
	if renderer.gpu_distance_field_clipmap_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.gpu_distance_field_clipmap_uniform_buffer)
	}
	pipelines := [?]wgpu.ComputePipeline {
		renderer.gpu_distance_field_clipmap_shift_pipeline,
		renderer.gpu_distance_field_clipmap_raster_pipeline,
		renderer.gpu_distance_field_clipmap_propagate_pipeline,
		renderer.gpu_distance_field_clipmap_finalize_pipeline,
	}
	for pipeline in pipelines {
		if pipeline != nil {
			wgpu.ComputePipelineRelease(pipeline)
		}
	}
	if renderer.gpu_distance_field_clipmap_debug_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.gpu_distance_field_clipmap_debug_pipeline)
	}
	pipeline_layouts := [?]wgpu.PipelineLayout {
		renderer.gpu_distance_field_clipmap_raster_pipeline_layout,
		renderer.gpu_distance_field_clipmap_propagate_pipeline_layout,
		renderer.gpu_distance_field_clipmap_finalize_pipeline_layout,
		renderer.gpu_distance_field_clipmap_debug_pipeline_layout,
	}
	for layout in pipeline_layouts {
		if layout != nil {
			wgpu.PipelineLayoutRelease(layout)
		}
	}
	bind_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_distance_field_clipmap_raster_bind_group_layout,
		renderer.gpu_distance_field_clipmap_propagate_bind_group_layout,
		renderer.gpu_distance_field_clipmap_finalize_bind_group_layout,
		renderer.gpu_distance_field_clipmap_debug_bind_group_layout,
	}
	for layout in bind_layouts {
		if layout != nil {
			wgpu.BindGroupLayoutRelease(layout)
		}
	}
	if renderer.gpu_distance_field_clipmap_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_distance_field_clipmap_shader)
	}
}

wgpu_encode_distance_field_clipmap :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	registry: ^resources.Registry,
	render_list: ^Render_List,
	viewport: ui.Rect,
) -> string {
	if renderer == nil ||
	   registry == nil ||
	   render_list == nil ||
	   renderer.gpu_render_uniform.debug.x != u32(shared.Render_Debug_View.World_Distance_Field) {
		return ""
	}
	camera_position := Vec3{0, 2, 6}
	if render_list.has_camera {
		camera_position = render_list.camera.transform.position
	}
	centers := wgpu_distance_field_clipmap_centers(camera_position)
	update := wgpu_distance_field_clipmap_update(
		renderer.gpu_distance_field_clipmap,
		render_list,
		registry.geometry_topology_revision,
		centers,
		viewport,
	)
	if !update.needed {
		return ""
	}
	groups := make([dynamic]WGPU_Distance_Field_Clipmap_Group, context.temp_allocator)
	defer delete(groups)
	instance_count := 0
	for instance in render_list.instances {
		geometry, alive := resources.get_geometry(registry, instance.geometry.handle)
		if !alive || geometry.distance_field.product_size == 0 {
			continue
		}
		virtual_geometry :=
			wgpu_resolve_geometry_mode(renderer, geometry, instance.geometry.geometry_mode) ==
			.Virtual
		group_index := -1
		for group, index in groups {
			if group.handle == instance.geometry.handle &&
			   group.virtual_geometry == virtual_geometry {
				group_index = index
				break
			}
		}
		if group_index < 0 {
			append(
				&groups,
				WGPU_Distance_Field_Clipmap_Group {
					handle = instance.geometry.handle,
					virtual_geometry = virtual_geometry,
					sample_count = int(geometry.distance_field.product_size / size_of(i16)),
				},
			)
			group_index = len(groups) - 1
		}
		groups[group_index].instance_count += 1
		instance_count += 1
	}
	if len(groups) + WGPU_DISTANCE_FIELD_CLIPMAP_JUMP_PASSES + 2 >
	   WGPU_DISTANCE_FIELD_CLIPMAP_MAX_UNIFORMS {
		return "world distance-field clipmap exceeded its uniform capacity"
	}
	slots := make([]u32, instance_count, context.temp_allocator)
	defer delete(slots, context.temp_allocator)
	offset := 0
	for &group in groups {
		group.instance_offset = offset
		offset += group.instance_count
		group.instance_count = 0
	}
	for instance in render_list.instances {
		geometry, alive := resources.get_geometry(registry, instance.geometry.handle)
		if !alive || geometry.distance_field.product_size == 0 {
			continue
		}
		virtual_geometry :=
			wgpu_resolve_geometry_mode(renderer, geometry, instance.geometry.geometry_mode) ==
			.Virtual
		for &group in groups {
			if group.handle != instance.geometry.handle ||
			   group.virtual_geometry != virtual_geometry {
				continue
			}
			slots[group.instance_offset + group.instance_count] = u32(instance.slot)
			group.instance_count += 1
			break
		}
	}
	uniforms := make(
		[]WGPU_Distance_Field_Clipmap_Uniform,
		2 + len(groups) + WGPU_DISTANCE_FIELD_CLIPMAP_JUMP_PASSES,
		context.temp_allocator,
	)
	defer delete(uniforms, context.temp_allocator)
	uniforms[0] = wgpu_distance_field_clipmap_metadata(centers, viewport, update)
	uniforms[1] = uniforms[0]
	for group, index in groups {
		geometry, _ := resources.get_geometry(registry, group.handle)
		uniforms[2 + index] = uniforms[0]
		uniforms[2 + index].field_dimensions = {
			geometry.distance_field.dimensions[0],
			geometry.distance_field.dimensions[1],
			geometry.distance_field.dimensions[2],
			u32(group.sample_count),
		}
		uniforms[2 + index].field_bounds_min = {
			geometry.distance_field.bounds.min.x,
			geometry.distance_field.bounds.min.y,
			geometry.distance_field.bounds.min.z,
			0,
		}
		uniforms[2 + index].field_bounds_max = {
			geometry.distance_field.bounds.max.x,
			geometry.distance_field.bounds.max.y,
			geometry.distance_field.bounds.max.z,
			0,
		}
		uniforms[2 + index].field_parameters = {
			geometry.distance_field.value_scale,
			f32(group.instance_offset),
			f32(group.instance_count),
			0,
		}
	}
	steps := [?]u32{16, 8, 4, 2, 1}
	for step, index in steps {
		uniforms[2 + len(groups) + index] = uniforms[0]
		uniforms[2 + len(groups) + index].control.x = step
	}
	if len(slots) > 0 {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_distance_field_clipmap_instance_slot_buffer,
			0,
			raw_data(slots),
			uint(len(slots) * size_of(u32)),
		)
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_distance_field_clipmap_uniform_buffer,
		0,
		raw_data(uniforms),
		uint(len(uniforms) * size_of(WGPU_Distance_Field_Clipmap_Uniform)),
	)
	voxel_bytes := u64(WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS * size_of(u32))
	update_voxels :=
		WGPU_DISTANCE_FIELD_CLIPMAP_CASCADE_VOXELS *
		wgpu_distance_field_clipmap_selected_cascade_count(update.cascade_mask)
	dispatches: u64
	if update.full_rebuild {
		wgpu.CommandEncoderClearBuffer(
			encoder,
			renderer.gpu_distance_field_clipmap_seed_buffers[0],
			0,
			voxel_bytes,
		)
	} else {
		shift_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor{label = "Scrapbot World Distance Field Shift Pass"},
		)
		if shift_pass == nil {
			return "failed to begin world distance-field shift pass"
		}
		wgpu.ComputePassEncoderSetPipeline(
			shift_pass,
			renderer.gpu_distance_field_clipmap_shift_pipeline,
		)
		shift_offset := [?]u32{WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT}
		wgpu.ComputePassEncoderSetBindGroup(
			shift_pass,
			0,
			renderer.gpu_distance_field_clipmap_propagate_bind_groups[1],
			shift_offset[:],
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(shift_pass, (update_voxels + 63) / 64, 1, 1)
		wgpu.ComputePassEncoderEnd(shift_pass)
		wgpu.ComputePassEncoderRelease(shift_pass)
		dispatches += 1
	}
	raster_pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor{label = "Scrapbot World Distance Field Raster Pass"},
	)
	if raster_pass == nil {
		return "failed to begin world distance-field raster pass"
	}
	wgpu.ComputePassEncoderSetPipeline(
		raster_pass,
		renderer.gpu_distance_field_clipmap_raster_pipeline,
	)
	for group, index in groups {
		geometry, _ := resources.get_geometry(registry, group.handle)
		cache_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			group.handle,
			group.virtual_geometry,
		)
		if cache_index < 0 {
			wgpu.ComputePassEncoderRelease(raster_pass)
			return "world distance-field geometry was not prepared for rendering"
		}
		cached := &renderer.geometry_cache[cache_index]
		if field_err := wgpu_ensure_geometry_distance_field(renderer, geometry, cached);
		   field_err != "" {
			wgpu.ComputePassEncoderRelease(raster_pass)
			return field_err
		}
		entries := [?]wgpu.BindGroupEntry {
			{
				binding = 0,
				buffer = cached.distance_field_buffer,
				size = max(cached.distance_field_bytes, u64(4)),
			},
			{
				binding = 1,
				buffer = renderer.gpu_instance_buffer,
				size = u64(WGPU_MAX_GPU_INSTANCES) * size_of(WGPU_GPU_Instance),
			},
			{
				binding = 2,
				buffer = renderer.gpu_distance_field_clipmap_instance_slot_buffer,
				size = u64(max(len(slots), 1) * size_of(u32)),
			},
			{
				binding = 3,
				buffer = renderer.gpu_distance_field_clipmap_seed_buffers[0],
				size = voxel_bytes,
			},
			{
				binding = 4,
				buffer = renderer.gpu_distance_field_clipmap_uniform_buffer,
				size = WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT,
			},
		}
		bind_group := wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot World Distance Field Raster Bind Group",
				layout = renderer.gpu_distance_field_clipmap_raster_bind_group_layout,
				entryCount = len(entries),
				entries = raw_data(entries[:]),
			},
		)
		if bind_group == nil {
			wgpu.ComputePassEncoderRelease(raster_pass)
			return "failed to create world distance-field raster bind group"
		}
		dynamic_offset := [?]u32{u32((2 + index) * WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT)}
		wgpu.ComputePassEncoderSetBindGroup(raster_pass, 0, bind_group, dynamic_offset[:])
		wgpu.ComputePassEncoderDispatchWorkgroups(
			raster_pass,
			u32((group.sample_count * group.instance_count + 63) / 64),
			1,
			1,
		)
		wgpu.BindGroupRelease(bind_group)
		dispatches += 1
	}
	wgpu.ComputePassEncoderEnd(raster_pass)
	wgpu.ComputePassEncoderRelease(raster_pass)
	for step_index in 0 ..< WGPU_DISTANCE_FIELD_CLIPMAP_JUMP_PASSES {
		pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor{label = "Scrapbot World Distance Field Propagate Pass"},
		)
		if pass == nil {
			return "failed to begin world distance-field propagation"
		}
		wgpu.ComputePassEncoderSetPipeline(
			pass,
			renderer.gpu_distance_field_clipmap_propagate_pipeline,
		)
		dynamic_offset := [?]u32 {
			u32((2 + len(groups) + step_index) * WGPU_DISTANCE_FIELD_CLIPMAP_UNIFORM_ALIGNMENT),
		}
		wgpu.ComputePassEncoderSetBindGroup(
			pass,
			0,
			renderer.gpu_distance_field_clipmap_propagate_bind_groups[step_index % 2],
			dynamic_offset[:],
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, (update_voxels + 63) / 64, 1, 1)
		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
		dispatches += 1
	}
	finalize_pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor{label = "Scrapbot World Distance Field Finalize Pass"},
	)
	if finalize_pass == nil {
		return "failed to begin world distance-field finalize pass"
	}
	wgpu.ComputePassEncoderSetPipeline(
		finalize_pass,
		renderer.gpu_distance_field_clipmap_finalize_pipeline,
	)
	wgpu.ComputePassEncoderSetBindGroup(
		finalize_pass,
		0,
		renderer.gpu_distance_field_clipmap_finalize_bind_group,
	)
	wgpu.ComputePassEncoderDispatchWorkgroups(finalize_pass, (update_voxels + 63) / 64, 1, 1)
	wgpu.ComputePassEncoderEnd(finalize_pass)
	wgpu.ComputePassEncoderRelease(finalize_pass)
	dispatches += 1
	renderer.gpu_distance_field_clipmap = {
		valid = true,
		world_uuid = render_list.world_uuid,
		topology_revision = render_list.topology_revision,
		geometry_topology_revision = registry.geometry_topology_revision,
		centers = centers,
		viewport = viewport,
		rebuild_count = renderer.gpu_distance_field_clipmap.rebuild_count + u64(update.full_rebuild),
		scroll_count = renderer.gpu_distance_field_clipmap.scroll_count + u64(!update.full_rebuild),
		scroll_voxel_count = renderer.gpu_distance_field_clipmap.scroll_voxel_count + u64(update.exposed_voxels) * u64(!update.full_rebuild),
		dispatch_count = renderer.gpu_distance_field_clipmap.dispatch_count + dispatches,
		upload_bytes = renderer.gpu_distance_field_clipmap.upload_bytes + u64(len(slots) * size_of(u32) + len(uniforms) * size_of(WGPU_Distance_Field_Clipmap_Uniform)),
		instance_count = instance_count,
		geometry_count = len(groups),
	}
	return ""
}

wgpu_encode_distance_field_clipmap_debug_view :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	viewport: ui.Rect,
) -> string {
	if renderer == nil ||
	   renderer.gpu_render_uniform.debug.x != u32(shared.Render_Debug_View.World_Distance_Field) ||
	   !renderer.gpu_distance_field_clipmap.valid {
		return ""
	}
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot World Distance Field Debug Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
		},
	)
	if pass == nil {
		return "failed to begin world distance-field debug pass"
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
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.gpu_distance_field_clipmap_debug_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(
		pass,
		0,
		renderer.gpu_distance_field_clipmap_debug_bind_group,
	)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_publish_distance_field_clipmap_stats :: proc(renderer: ^WGPU_Renderer, stats: ^Render_Stats) {
	if renderer == nil || stats == nil {
		return
	}
	state := renderer.gpu_distance_field_clipmap
	stats.world_distance_field = state.valid
	stats.world_distance_field_rebuilds = state.rebuild_count
	stats.world_distance_field_scrolls = state.scroll_count
	stats.world_distance_field_scroll_voxels = state.scroll_voxel_count
	stats.world_distance_field_instances = state.instance_count
	stats.world_distance_field_geometries = state.geometry_count
	stats.world_distance_field_voxels = int(WGPU_DISTANCE_FIELD_CLIPMAP_VOXELS)
	stats.world_distance_field_dispatches = state.dispatch_count
	stats.world_distance_field_upload_bytes = state.upload_bytes
}

WGPU_DISTANCE_FIELD_CLIPMAP_SHADER :: `
const RESOLUTION: u32 = 32u;
const CASCADE_VOXELS: u32 = 32768u;
const CASCADE_COUNT: u32 = 3u;
const INVALID_SEED: u32 = 0u;

struct Clipmap_Uniform {
	field_dimensions: vec4<u32>,
	field_bounds_min: vec4<f32>,
	field_bounds_max: vec4<f32>,
	field_parameters: vec4<f32>,
	cascade_centers: array<vec4<f32>, 3>,
	cascade_parameters: array<vec4<f32>, 3>,
	cascade_shifts: array<vec4<i32>, 3>,
	control: vec4<u32>,
	padding: array<vec4<u32>, 2>,
};

struct GPU_Instance {
	model: mat4x4<f32>,
	normal_model: mat4x4<f32>,
	color: vec4<f32>,
	emissive: vec4<f32>,
	render_flags: vec4<f32>,
	bounds: vec4<f32>,
	batch_indices: vec4<u32>,
	lod_screen_radii: vec4<f32>,
	lod_count: u32,
	is_active: u32,
	padding: vec2<u32>,
};

@group(0) @binding(0) var<storage, read> source_samples: array<u32>;
@group(0) @binding(1) var<storage, read> instances: array<GPU_Instance>;
@group(0) @binding(2) var<storage, read> instance_slots: array<u32>;
@group(0) @binding(3) var<storage, read_write> raster_seeds: array<atomic<u32>>;
@group(0) @binding(4) var<uniform> raster_uniform: Clipmap_Uniform;

fn source_sample(index: u32) -> f32 {
	let word = source_samples[index / 2u];
	let packed = select(word & 0xffffu, word >> 16u, (index & 1u) != 0u);
	let signed_value = bitcast<i32>(packed << 16u) >> 16;
	return f32(signed_value) * raster_uniform.field_parameters.x;
}

fn pack_seed(cell: vec3<u32>) -> u32 {
	return 0x80000000u | cell.x | (cell.y << 6u) | (cell.z << 12u);
}

fn unpack_seed(value: u32) -> vec3<u32> {
	return vec3<u32>(value & 63u, (value >> 6u) & 63u, (value >> 12u) & 63u);
}

fn cascade_selected(cascade: u32, control: vec4<u32>) -> bool {
	return (control.y & (1u << cascade)) != 0u;
}

fn selected_cascade(ordinal: u32, control: vec4<u32>) -> u32 {
	var remaining = ordinal;
	for (var cascade = 0u; cascade < CASCADE_COUNT; cascade += 1u) {
		if (!cascade_selected(cascade, control)) { continue; }
		if (remaining == 0u) { return cascade; }
		remaining -= 1u;
	}
	return 0u;
}

fn cell_is_exposed(cell: vec3<u32>, shift: vec3<i32>) -> bool {
	let source_cell = vec3<i32>(cell) + shift;
	return any(source_cell < vec3<i32>(0)) || any(source_cell >= vec3<i32>(32));
}

@compute @workgroup_size(64)
fn rasterize_fields(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let sample_count = raster_uniform.field_dimensions.w;
	let instance_count = u32(raster_uniform.field_parameters.z);
	let total = sample_count * instance_count;
	if (global_id.x >= total || sample_count == 0u) { return; }
	let sample_index = global_id.x % sample_count;
	let local_instance = global_id.x / sample_count;
	let slot = instance_slots[u32(raster_uniform.field_parameters.y) + local_instance];
	if (instances[slot].is_active == 0u) { return; }
	let dimensions = raster_uniform.field_dimensions.xyz;
	let x = sample_index % dimensions.x;
	let y = (sample_index / dimensions.x) % dimensions.y;
	let z = sample_index / (dimensions.x * dimensions.y);
	let denominator = max(vec3<f32>(dimensions - vec3<u32>(1u)), vec3<f32>(1.0));
	let local_uv = vec3<f32>(f32(x), f32(y), f32(z)) / denominator;
	let local_position = mix(raster_uniform.field_bounds_min.xyz, raster_uniform.field_bounds_max.xyz, local_uv);
	let world_position = (instances[slot].model * vec4<f32>(local_position, 1.0)).xyz;
	let world_distance = abs(source_sample(sample_index));
	for (var cascade = 0u; cascade < CASCADE_COUNT; cascade += 1u) {
		if (!cascade_selected(cascade, raster_uniform.control)) { continue; }
		let voxel_size = raster_uniform.cascade_parameters[cascade].x;
		if (world_distance > voxel_size * 1.75) { continue; }
		let local_cell = floor((world_position - raster_uniform.cascade_centers[cascade].xyz) / voxel_size + vec3<f32>(16.0));
		if (any(local_cell < vec3<f32>(0.0)) || any(local_cell >= vec3<f32>(32.0))) { continue; }
		let cell = vec3<u32>(local_cell);
		if (
			raster_uniform.control.z != 0u &&
			!cell_is_exposed(cell, raster_uniform.cascade_shifts[cascade].xyz)
		) { continue; }
		let linear = cell.x + RESOLUTION * (cell.y + RESOLUTION * cell.z);
		atomicStore(&raster_seeds[cascade * CASCADE_VOXELS + linear], pack_seed(cell));
	}
}

@group(0) @binding(0) var<storage, read> input_seeds: array<u32>;
@group(0) @binding(1) var<storage, read_write> output_seeds: array<u32>;
@group(0) @binding(2) var<uniform> propagate_uniform: Clipmap_Uniform;

fn squared_cell_distance(a: vec3<i32>, b: vec3<u32>) -> u32 {
	let delta = a - vec3<i32>(b);
	return u32(dot(delta, delta));
}

@compute @workgroup_size(64)
fn shift_seeds(@builtin(global_invocation_id) global_id: vec3<u32>) {
	if (global_id.x >= CASCADE_VOXELS * propagate_uniform.control.w) { return; }
	let cascade = selected_cascade(global_id.x / CASCADE_VOXELS, propagate_uniform.control);
	let linear = global_id.x % CASCADE_VOXELS;
	let cell = vec3<i32>(i32(linear % RESOLUTION), i32((linear / RESOLUTION) % RESOLUTION), i32(linear / (RESOLUTION * RESOLUTION)));
	let shift = propagate_uniform.cascade_shifts[cascade].xyz;
	let source_cell = cell + shift;
	if (any(source_cell < vec3<i32>(0)) || any(source_cell >= vec3<i32>(32))) {
		output_seeds[cascade * CASCADE_VOXELS + linear] = INVALID_SEED;
		return;
	}
	let source_linear = u32(source_cell.x) + RESOLUTION * (u32(source_cell.y) + RESOLUTION * u32(source_cell.z));
	let source_seed = input_seeds[cascade * CASCADE_VOXELS + source_linear];
	if ((source_seed & 0x80000000u) == 0u) {
		output_seeds[cascade * CASCADE_VOXELS + linear] = INVALID_SEED;
		return;
	}
	let shifted_seed = vec3<i32>(unpack_seed(source_seed)) - shift;
	if (any(shifted_seed < vec3<i32>(0)) || any(shifted_seed >= vec3<i32>(32))) {
		output_seeds[cascade * CASCADE_VOXELS + linear] = INVALID_SEED;
		return;
	}
	output_seeds[cascade * CASCADE_VOXELS + linear] = pack_seed(vec3<u32>(shifted_seed));
}

@compute @workgroup_size(64)
fn propagate_seeds(@builtin(global_invocation_id) global_id: vec3<u32>) {
	if (global_id.x >= CASCADE_VOXELS * propagate_uniform.control.w) { return; }
	let cascade = selected_cascade(global_id.x / CASCADE_VOXELS, propagate_uniform.control);
	let linear = global_id.x % CASCADE_VOXELS;
	let output_index = cascade * CASCADE_VOXELS + linear;
	let cell = vec3<i32>(i32(linear % RESOLUTION), i32((linear / RESOLUTION) % RESOLUTION), i32(linear / (RESOLUTION * RESOLUTION)));
	var best = input_seeds[output_index];
	var best_distance = 0xffffffffu;
	if ((best & 0x80000000u) != 0u) { best_distance = squared_cell_distance(cell, unpack_seed(best)); }
	let step = i32(propagate_uniform.control.x);
	for (var dz = -1; dz <= 1; dz += 1) {
		for (var dy = -1; dy <= 1; dy += 1) {
			for (var dx = -1; dx <= 1; dx += 1) {
				let candidate_cell = cell + vec3<i32>(dx, dy, dz) * step;
				if (any(candidate_cell < vec3<i32>(0)) || any(candidate_cell >= vec3<i32>(32))) { continue; }
				let candidate_linear = u32(candidate_cell.x) + RESOLUTION * (u32(candidate_cell.y) + RESOLUTION * u32(candidate_cell.z));
				let candidate = input_seeds[cascade * CASCADE_VOXELS + candidate_linear];
				if ((candidate & 0x80000000u) == 0u) { continue; }
				let distance = squared_cell_distance(cell, unpack_seed(candidate));
				if (distance < best_distance || (distance == best_distance && candidate < best)) { best = candidate; best_distance = distance; }
			}
		}
	}
	output_seeds[output_index] = best;
}

@group(0) @binding(0) var<storage, read> final_seeds: array<u32>;
@group(0) @binding(1) var<storage, read_write> final_distances: array<u32>;
@group(0) @binding(2) var<uniform> final_uniform: Clipmap_Uniform;

@compute @workgroup_size(64)
fn finalize_distances(@builtin(global_invocation_id) global_id: vec3<u32>) {
	if (global_id.x >= CASCADE_VOXELS * final_uniform.control.w) { return; }
	let cascade = selected_cascade(global_id.x / CASCADE_VOXELS, final_uniform.control);
	let linear = global_id.x % CASCADE_VOXELS;
	let output_index = cascade * CASCADE_VOXELS + linear;
	let seed = final_seeds[output_index];
	if ((seed & 0x80000000u) == 0u) { final_distances[output_index] = bitcast<u32>(1e20); return; }
	let cell = vec3<f32>(f32(linear % RESOLUTION), f32((linear / RESOLUTION) % RESOLUTION), f32(linear / (RESOLUTION * RESOLUTION)));
	let distance = length(cell - vec3<f32>(unpack_seed(seed))) * final_uniform.cascade_parameters[cascade].x;
	final_distances[output_index] = bitcast<u32>(distance);
}

struct Fullscreen_Output { @builtin(position) position: vec4<f32> };
@vertex fn fullscreen_vs(@builtin(vertex_index) index: u32) -> Fullscreen_Output {
	var positions = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
	var output: Fullscreen_Output;
	output.position = vec4<f32>(positions[index], 0.0, 1.0);
	return output;
}

@group(0) @binding(0) var<storage, read> debug_distances: array<u32>;
@group(0) @binding(1) var<uniform> debug_uniform: Clipmap_Uniform;
@fragment fn debug_world_distance_field(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	let viewport = debug_uniform.field_bounds_min;
	let dimensions = max(viewport.zw, vec2<f32>(1.0));
	let uv = clamp((input.position.xy - viewport.xy) / dimensions, vec2<f32>(0.0), vec2<f32>(0.9999));
	let x = min(u32(uv.x * 32.0), 31u);
	let z = min(u32((1.0 - uv.y) * 32.0), 31u);
	var distance = 1e20;
	for (var y = 0u; y < 32u; y += 1u) {
		let linear = x + RESOLUTION * (y + RESOLUTION * z);
		distance = min(distance, bitcast<f32>(debug_distances[linear]));
	}
	let normalized = clamp(distance / 12.0, 0.0, 1.0);
	let color = mix(vec3<f32>(0.12, 0.95, 0.82), vec3<f32>(0.015, 0.025, 0.04), normalized);
	return vec4<f32>(color, 1.0);
}
`
