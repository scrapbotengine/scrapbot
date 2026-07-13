package render

import "core:testing"
import ecs "../ecs"
import shared "../shared"
import ui "../ui"

@(test)
test_transform_gizmo_projects_hits_and_drags_world_x :: proc(t:^testing.T) {
	world:shared.World;defer delete(world.entities);defer delete(world.transforms);defer delete(world.editor_transform_gizmos)
	append(&world.entities,shared.World_Entity{id={index=0,generation=1},alive=true,transform_index=0,editor_transform_gizmo_index=-1})
	append_soa(&world.transforms,shared.Transform_Component{scale={1,1,1}})
	state:=new(ui.State);defer free(state);state.editor_visible=true;state.editor_has_selection=true;state.editor_selected_entity={index=0,generation=1}
	camera:=shared.Camera_Instance{transform={position={4,4,8}},camera={fov=60,near=0.1,far=100}}
	viewport:=ui.Rect{240,48,740,644}
	editor_transform_gizmo_system(state,&world,{position={500,350},available=true},viewport,camera,true)
	testing.expect(t,state.editor_gizmo_visible)
	testing.expect(t,world.entities[0].editor_transform_gizmo_index>=0)
	_,gizmo,has_gizmo:=ecs.editor_transform_gizmo_entity(&world);testing.expect(t,has_gizmo&&gizmo.mode==.World_Translate)
	x_end:=state.editor_gizmo_endpoints[0];x_delta:=screen_sub(x_end,state.editor_gizmo_origin);x_length:=screen_length(x_delta)
	testing.expect(t,x_length>20)
	midpoint:=shared.Vec2{state.editor_gizmo_origin.x+x_delta.x*0.6,state.editor_gizmo_origin.y+x_delta.y*0.6}
	editor_transform_gizmo_system(state,&world,{position=midpoint,available=true},viewport,camera,true)
	testing.expect(t,state.editor_gizmo_hovered_axis==.X)
	editor_transform_gizmo_system(state,&world,{position=midpoint,primary_down=true,available=true},viewport,camera,true)
	testing.expect(t,state.editor_gizmo_active_axis==.X&&state.editor_gizmo_captures_pointer)
	state.editor_previous_primary_down=true
	drag:=shared.Vec2{midpoint.x+state.editor_gizmo_drag_direction.x*x_length*0.5,midpoint.y+state.editor_gizmo_drag_direction.y*x_length*0.5}
	editor_transform_gizmo_system(state,&world,{position=drag,primary_down=true,available=true},viewport,camera,true)
	testing.expect(t,world.transforms[0].position.x>0.1)
	testing.expect(t,world.transforms[0].position.y==0&&world.transforms[0].position.z==0)
	editor_transform_gizmo_system(state,&world,{position=drag,available=true},viewport,camera,true)
	testing.expect(t,state.editor_gizmo_active_axis==.None&&!state.editor_gizmo_captures_pointer)
}

@(test)
test_transform_gizmo_hides_for_entities_without_transform :: proc(t:^testing.T) {
	world:shared.World;defer delete(world.entities);defer delete(world.editor_transform_gizmos);append(&world.entities,shared.World_Entity{id={index=0,generation=1},alive=true,transform_index=-1,editor_transform_gizmo_index=-1})
	state:=new(ui.State);defer free(state);state.editor_visible=true;state.editor_has_selection=true;state.editor_selected_entity={index=0,generation=1};state.editor_gizmo_visible=true
	editor_transform_gizmo_system(state,&world,{},ui.Rect{0,0,800,600},{},false)
	testing.expect(t,!state.editor_gizmo_visible)
	testing.expect(t,len(world.editor_transform_gizmos)==0)
}
