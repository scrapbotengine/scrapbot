package render

import "core:testing"
import resources "../resources"
import shared "../shared"
import ui "../ui"

@(test)
test_editor_picking_returns_nearest_transformed_triangle_hit :: proc(t:^testing.T) {
	registry:resources.Registry;defer resources.destroy_registry(&registry)
	desc,desc_err:=resources.cube();testing.expect(t,desc_err=="");defer delete(desc.vertices);defer delete(desc.indices)
	handle,register_err:=resources.register_geometry(&registry,"pick-cube",desc);testing.expect(t,register_err=="")
	list:=shared.Render_List{has_camera=true,camera={transform={position={0,0,6}},camera={fov=60,near=0.1,far=100}}};defer delete(list.instances)
	append(&list.instances,
		shared.Render_Instance{entity={id={index=1,generation=1},alive=true},transform={position={0,0,0},scale={1,1,1}},geometry={handle=handle}},
		shared.Render_Instance{entity={id={index=2,generation=3},alive=true},transform={position={0,0,2},scale={1,1,1}},geometry={handle=handle}},
	)
	viewport:=ui.Rect{100,50,800,600}
	entity,found:=editor_pick_entity(&list,&registry,{500,350},viewport)
	testing.expect(t,found)
	testing.expect(t,entity==shared.Entity{index=2,generation=3})
	_,found=editor_pick_entity(&list,&registry,{105,55},viewport)
	testing.expect(t,!found)
}

@(test)
test_editor_pick_ray_tracks_live_viewport_aspect :: proc(t:^testing.T) {
	list:=shared.Render_List{has_camera=true,camera={transform={position={0,0,6}},camera={fov=60}}}
	ray,ok:=editor_pick_ray(&list,{900,300},ui.Rect{0,0,1000,600})
	testing.expect(t,ok)
	testing.expect(t,ray.direction.x>0)
	testing.expect(t,ray.direction.z<0)
	center,_:=editor_pick_ray(&list,{500,300},ui.Rect{0,0,1000,600})
	testing.expect(t,center.direction.x==0)
}
