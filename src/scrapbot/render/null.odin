package render

import ecs "../ecs"

Null_Renderer :: struct {}

renderer_submit :: proc(renderer: ^Null_Renderer, world: ^World) -> Render_Frame {
	return ecs.render_frame_from_world(world)
}
