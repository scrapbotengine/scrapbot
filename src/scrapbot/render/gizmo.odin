package render

import "core:math"
import ecs "../ecs"
import shared "../shared"
import ui "../ui"

EDITOR_GIZMO_SCREEN_SIZE :: f32(92)
EDITOR_GIZMO_HIT_RADIUS :: f32(10)

editor_transform_gizmo_system :: proc(state:^ui.State,world:^shared.World,pointer:ui.Pointer_Input,viewport:ui.Rect,camera:shared.Camera_Instance,has_camera:bool) {
	if state==nil||world==nil {editor_hide_gizmo(state);return}
	ecs.reconcile_editor_transform_gizmo(world,state.editor_selected_entity,state.editor_visible&&state.editor_has_selection)
	entity_index,gizmo,has_gizmo:=ecs.editor_transform_gizmo_entity(world)
	if !has_gizmo||gizmo.mode!=.World_Translate {editor_hide_gizmo(state);return}
	entity:=&world.entities[entity_index]
	if entity.transform_index<0||entity.transform_index>=len(world.transforms){editor_hide_gizmo(state);return}
	transform:=&world.transforms[entity.transform_index]
	eye,fov:=editor_camera_eye_fov(camera,has_camera);distance:=math.sqrt(vec3_dot(vec3_sub(transform.position,eye),vec3_sub(transform.position,eye)))
	world_size:=max(2*max(distance,0.1)*math.tan(math.to_radians(fov)*0.5)/max(viewport.height,1)*EDITOR_GIZMO_SCREEN_SIZE,0.05)
	if !editor_project_gizmo(state,transform.position,world_size,viewport,camera,has_camera){editor_hide_gizmo(state);return}
	just_pressed:=pointer.available&&pointer.primary_down&&!state.editor_previous_primary_down
	if state.editor_gizmo_active_axis==.None {
		state.editor_gizmo_hovered_axis=editor_gizmo_hit_axis(pointer.position,state.editor_gizmo_origin,state.editor_gizmo_endpoints,pointer.available)
		if just_pressed&&state.editor_gizmo_hovered_axis!=.None {
			axis_index:=int(state.editor_gizmo_hovered_axis)-1;delta:=screen_sub(state.editor_gizmo_endpoints[axis_index],state.editor_gizmo_origin);pixels:=screen_length(delta)
			if pixels>0.001 {
				state.editor_gizmo_active_axis=state.editor_gizmo_hovered_axis;state.editor_gizmo_captures_pointer=true;state.editor_gizmo_drag_pointer=pointer.position;state.editor_gizmo_drag_position=transform.position;state.editor_gizmo_drag_direction={delta.x/pixels,delta.y/pixels};state.editor_gizmo_drag_pixels=pixels;state.editor_gizmo_drag_world_scale=world_size
			}
		}
	} else if !pointer.primary_down {
		state.editor_gizmo_active_axis=.None;state.editor_gizmo_captures_pointer=false
	} else {
		state.editor_gizmo_captures_pointer=true;state.editor_gizmo_hovered_axis=state.editor_gizmo_active_axis
		delta:=screen_sub(pointer.position,state.editor_gizmo_drag_pointer);pixels:=delta.x*state.editor_gizmo_drag_direction.x+delta.y*state.editor_gizmo_drag_direction.y;amount:=pixels/state.editor_gizmo_drag_pixels*state.editor_gizmo_drag_world_scale
		transform.position=state.editor_gizmo_drag_position
		switch state.editor_gizmo_active_axis {case .X:transform.position.x+=amount;case .Y:transform.position.y+=amount;case .Z:transform.position.z+=amount;case .None:}
		_ = editor_project_gizmo(state,transform.position,world_size,viewport,camera,has_camera)
	}
}

editor_hide_gizmo :: proc(state:^ui.State){if state==nil{return};state.editor_gizmo_visible=false;state.editor_gizmo_hovered_axis=.None;state.editor_gizmo_active_axis=.None;state.editor_gizmo_captures_pointer=false}

editor_project_gizmo :: proc(state:^ui.State,origin:shared.Vec3,world_size:f32,viewport:ui.Rect,camera:shared.Camera_Instance,has_camera:bool)->bool {
	origin_screen,ok:=editor_project_world(origin,viewport,camera,has_camera);if !ok{return false}
	world_endpoints:=[3]shared.Vec3{{origin.x+world_size,origin.y,origin.z},{origin.x,origin.y+world_size,origin.z},{origin.x,origin.y,origin.z+world_size}}
	endpoints:[3]shared.Vec2
	for endpoint,index in world_endpoints {projected,projected_ok:=editor_project_world(endpoint,viewport,camera,has_camera);if !projected_ok{return false};endpoints[index]=projected}
	state.editor_gizmo_origin=origin_screen;state.editor_gizmo_endpoints=endpoints;state.editor_gizmo_visible=true;return true
}

editor_project_world :: proc(point:shared.Vec3,viewport:ui.Rect,camera:shared.Camera_Instance,has_camera:bool)->(shared.Vec2,bool) {
	if viewport.width<=0||viewport.height<=0{return {},false};eye,fov:=editor_camera_eye_fov(camera,has_camera);near,far:=f32(0.1),f32(100)
	if has_camera {if camera.camera.near>0{near=camera.camera.near};if camera.camera.far>near{far=camera.camera.far}}
	target:=shared.Vec3{};up:=shared.Vec3{0,1,0};if has_camera{target=shared.camera_vec3_add(eye,shared.camera_forward(camera.transform.rotation));up=shared.camera_up(camera.transform.rotation)}
	view:=mat4_look_at(eye,target,up);projection:=mat4_perspective(math.to_radians(fov),viewport.width/viewport.height,near,far);vp:=mat4_mul(projection,view)
	clip_x:=vp[0]*point.x+vp[4]*point.y+vp[8]*point.z+vp[12];clip_y:=vp[1]*point.x+vp[5]*point.y+vp[9]*point.z+vp[13];clip_w:=vp[3]*point.x+vp[7]*point.y+vp[11]*point.z+vp[15]
	if clip_w<=0.0001{return {},false};ndc_x,ndc_y:=clip_x/clip_w,clip_y/clip_w
	return {viewport.x+(ndc_x+1)*0.5*viewport.width,viewport.y+(1-ndc_y)*0.5*viewport.height},true
}

editor_camera_eye_fov :: proc(camera:shared.Camera_Instance,has_camera:bool)->(shared.Vec3,f32) {eye:=shared.Vec3{0,2,6};fov:=f32(60);if has_camera{eye=camera.transform.position;if camera.camera.fov>0{fov=camera.camera.fov}};return eye,fov}

editor_gizmo_hit_axis :: proc(point,origin:shared.Vec2,endpoints:[3]shared.Vec2,available:bool)->ui.Editor_Gizmo_Axis {
	if !available{return .None};nearest:=EDITOR_GIZMO_HIT_RADIUS;axis:=ui.Editor_Gizmo_Axis.None
	for endpoint,index in endpoints {distance:=screen_point_segment_distance(point,origin,endpoint);if distance<=nearest{nearest=distance;axis=ui.Editor_Gizmo_Axis(index+1)}}
	return axis
}

screen_point_segment_distance :: proc(point,a,b:shared.Vec2)->f32 {ab:=screen_sub(b,a);length_squared:=ab.x*ab.x+ab.y*ab.y;if length_squared<=0{return screen_length(screen_sub(point,a))};ap:=screen_sub(point,a);t:=clamp((ap.x*ab.x+ap.y*ab.y)/length_squared,0,1);closest:=shared.Vec2{a.x+ab.x*t,a.y+ab.y*t};return screen_length(screen_sub(point,closest))}
screen_sub :: proc(a,b:shared.Vec2)->shared.Vec2{return {a.x-b.x,a.y-b.y}}
screen_length :: proc(value:shared.Vec2)->f32{return math.sqrt(value.x*value.x+value.y*value.y)}
