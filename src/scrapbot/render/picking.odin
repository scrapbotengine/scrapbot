package render

import "core:math"
import resources "../resources"
import shared "../shared"
import ui "../ui"

Pick_Ray :: struct {origin,direction:shared.Vec3}

editor_pick_ray :: proc(render_list:^shared.Render_List,position:shared.Vec2,viewport:ui.Rect)->(Pick_Ray,bool) {
	if viewport.width<=0||viewport.height<=0{return {},false}
	eye:=shared.Vec3{0,2,6};fov:=f32(60)
	if render_list!=nil&&render_list.has_camera {
		eye=render_list.camera.transform.position
		if render_list.camera.camera.fov>0{fov=render_list.camera.camera.fov}
	}
	forward:=vec3_normalize(vec3_sub({},eye));up:=shared.Vec3{0,1,0}
	if math.abs(vec3_dot(forward,up))>0.99{up={0,0,1}}
	side:=vec3_normalize(vec3_cross(forward,up));true_up:=vec3_cross(side,forward)
	ndc_x:=(position.x-viewport.x)/viewport.width*2-1
	ndc_y:=1-(position.y-viewport.y)/viewport.height*2
	tan_half:=math.tan(math.to_radians(fov)*0.5);aspect:=viewport.width/viewport.height
	direction:=pick_add(forward,pick_add(pick_mul(side,ndc_x*aspect*tan_half),pick_mul(true_up,ndc_y*tan_half)))
	return {eye,vec3_normalize(direction)},true
}

editor_pick_entity :: proc(render_list:^shared.Render_List,registry:^resources.Registry,position:shared.Vec2,viewport:ui.Rect)->(shared.Entity,bool) {
	if render_list==nil||registry==nil{return {},false}
	ray,ray_ok:=editor_pick_ray(render_list,position,viewport);if !ray_ok{return {},false}
	nearest:=f32(3.4028235e38);picked:shared.Entity;found:=false
	for instance in render_list.instances {
		geometry,ok:=resources.get_geometry(registry,instance.geometry.handle);if !ok{continue}
		model:=wgpu_build_model(instance.transform)
		for triangle:=0;triangle+2<len(geometry.indices);triangle+=3 {
			a:=pick_transform_point(model,geometry.vertices[geometry.indices[triangle]].position)
			b:=pick_transform_point(model,geometry.vertices[geometry.indices[triangle+1]].position)
			c:=pick_transform_point(model,geometry.vertices[geometry.indices[triangle+2]].position)
			if distance,hit:=pick_ray_triangle(ray,a,b,c);hit&&distance<nearest {nearest=distance;picked=instance.entity.id;found=true}
		}
	}
	return picked,found
}

pick_ray_triangle :: proc(ray:Pick_Ray,a,b,c:shared.Vec3)->(f32,bool) {
	edge1:=vec3_sub(b,a);edge2:=vec3_sub(c,a);p:=vec3_cross(ray.direction,edge2);det:=vec3_dot(edge1,p)
	if math.abs(det)<0.000001{return 0,false};inverse_det:=1/det;tvec:=vec3_sub(ray.origin,a);u:=vec3_dot(tvec,p)*inverse_det
	if u<0||u>1{return 0,false};q:=vec3_cross(tvec,edge1);v:=vec3_dot(ray.direction,q)*inverse_det
	if v<0||u+v>1{return 0,false};distance:=vec3_dot(edge2,q)*inverse_det
	return distance,distance>0.0001
}

pick_transform_point :: proc(m:Mat4,point:shared.Vec3)->shared.Vec3 {
	return {m[0]*point.x+m[4]*point.y+m[8]*point.z+m[12],m[1]*point.x+m[5]*point.y+m[9]*point.z+m[13],m[2]*point.x+m[6]*point.y+m[10]*point.z+m[14]}
}

pick_add :: proc(a,b:shared.Vec3)->shared.Vec3{return {a.x+b.x,a.y+b.y,a.z+b.z}}
pick_mul :: proc(value:shared.Vec3,scalar:f32)->shared.Vec3{return {value.x*scalar,value.y*scalar,value.z*scalar}}
