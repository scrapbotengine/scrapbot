package render

import live_debug "../live_debug"
import shared "../shared"
import ui "../ui"

publish_live_debug_snapshot :: proc(
	config: ^Run_Config,
	world: ^World,
	render_list: ^shared.Render_List,
	frame_index: u64,
	output_width, output_height: u32,
	render_width, render_height: u32,
	pixel_density: f32,
	viewport: ui.Rect,
) {
	if config == nil || config.live_debug == nil || world == nil {
		return
	}
	snapshot := live_debug.Snapshot {
		phase = "running",
		frame_index = frame_index,
		entity_count = world.live_entity_count,
		editor_visible = config.ui_state != nil && config.ui_state.editor_visible,
		renderer = {
			backend = renderer_backend_name(config.backend),
			frame_index = frame_index,
			output_width = output_width,
			output_height = output_height,
			render_width = render_width,
			render_height = render_height,
			pixel_density = pixel_density,
			viewport = {
				x = viewport.x,
				y = viewport.y,
				width = viewport.width,
				height = viewport.height,
			},
		},
	}
	if render_list != nil {
		world_uuid_buffer: [36]u8
		snapshot.world_uuid = shared.entity_uuid_to_string(
			render_list.world_uuid,
			world_uuid_buffer[:],
		)
		if render_list.has_camera {
			camera := render_list.camera
			camera_uuid_buffer: [36]u8
			forward := shared.camera_forward(camera.transform.rotation)
			snapshot.camera = {
				available = true,
				entity_uuid = shared.entity_uuid_to_string(
					camera.entity.uuid,
					camera_uuid_buffer[:],
				),
				position = vec3_to_live_debug(camera.transform.position),
				rotation = vec3_to_live_debug(camera.transform.rotation),
				forward = vec3_to_live_debug(forward),
				fov = camera.camera.fov,
				near = camera.camera.near,
				far = camera.camera.far,
				debug_view = shared.render_debug_view_name(camera.camera.debug_view),
			}
		}
	}
	publish_live_debug_render_stats(&snapshot.renderer, config.stats)
	live_debug.publish_snapshot(config.live_debug, snapshot)
	plan := live_debug.begin_capture_frame(config.live_debug)
	if plan.active && card(plan.artifacts) > 0 && config.backend != .WGPU {
		live_debug.capture_fail(
			config.live_debug,
			"the active renderer does not provide live render-artifact capture",
		)
		return
	}
	_ = live_debug.capture_published_snapshot(config.live_debug)
}

vec3_to_live_debug :: proc "contextless" (value: shared.Vec3) -> live_debug.Vec3 {
	return {x = value.x, y = value.y, z = value.z}
}

publish_live_debug_render_stats :: proc(
	destination: ^live_debug.Renderer_Snapshot,
	stats: ^Render_Stats,
) {
	if destination == nil || stats == nil {
		return
	}
	destination.draw_batches = stats.draw_batches
	destination.conventional_batches = stats.conventional_batches
	destination.virtual_batches = stats.virtual_batches
	destination.conventional_instances = stats.conventional_instances
	destination.virtual_instances = stats.virtual_instances
	destination.meshlet_compacted = stats.meshlet_compacted
	destination.meshlet_compact_batches = stats.meshlet_compact_batches
	destination.meshlet_compact_instances = stats.meshlet_compact_instances
	destination.visible_batches = stats.visible_batches
	destination.visible_meshlet_draws = stats.visible_meshlet_draws
	destination.visible_virtual_clusters = stats.visible_virtual_clusters
	destination.visible_virtual_blend_clusters = stats.visible_virtual_blend_clusters
	destination.visible_virtual_triangles = stats.visible_virtual_triangles
	destination.compact_triangles = stats.compact_triangles
	destination.compact_vertex_invocations = stats.compact_vertex_invocations
	destination.virtual_rejected_clusters = stats.virtual_rejected_clusters
	destination.virtual_geometry_page_budget_bytes = stats.virtual_geometry_page_budget_bytes
	destination.virtual_geometry_page_resident_bytes = stats.virtual_geometry_page_resident_bytes
	destination.virtual_geometry_pages = stats.virtual_geometry_pages
	destination.virtual_geometry_resident_pages = stats.virtual_geometry_resident_pages
	destination.virtual_geometry_pinned_pages = stats.virtual_geometry_pinned_pages
	destination.virtual_geometry_prefetched_pages = stats.virtual_geometry_prefetched_pages
	destination.virtual_geometry_page_requests = stats.virtual_geometry_page_requests
	destination.virtual_geometry_page_prefetches = stats.virtual_geometry_page_prefetches
	destination.virtual_geometry_page_request_overflow =
		stats.virtual_geometry_page_request_overflow
	destination.virtual_geometry_page_uploads = stats.virtual_geometry_page_uploads
	destination.virtual_geometry_page_evictions = stats.virtual_geometry_page_evictions
	destination.virtual_geometry_group_uploads = stats.virtual_geometry_group_uploads
	destination.virtual_geometry_group_activations = stats.virtual_geometry_group_activations
	destination.virtual_geometry_transitioning_groups = stats.virtual_geometry_transitioning_groups
	destination.virtual_geometry_group_evictions = stats.virtual_geometry_group_evictions
	destination.virtual_geometry_deferred_groups = stats.virtual_geometry_deferred_groups
	destination.gpu_timestamps_valid = stats.gpu_timestamps_valid
	destination.gpu_frame_ms = stats.gpu_frame_ms
	destination.gpu_scene_ms = stats.gpu_scene_ms
}
