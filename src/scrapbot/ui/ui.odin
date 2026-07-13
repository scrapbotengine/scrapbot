package ui

import shared "../shared"
import "core:fmt"
import "core:math"

MAX_NODES :: 256
MAX_PAINT_COMMANDS :: 4096
FONT_FIRST_CHAR :: 32
FONT_CHAR_COUNT :: 95
FONT_ATLAS_SIZE :: 512
FONT_ASCENDER :: f32(0.96875)
FONT_ATLAS_DATA :: #load("assets/inter_mtsdf.bin")

EDITOR_TOP_BAR_HEIGHT :: f32(48)
EDITOR_STATUS_BAR_HEIGHT :: f32(28)
EDITOR_LEFT_SIDEBAR_WIDTH :: f32(240)
EDITOR_RIGHT_SIDEBAR_WIDTH :: f32(300)
EDITOR_VIEWPORT_INSET :: f32(4)
EDITOR_ENTITY_ROW_HEIGHT :: f32(28)
EDITOR_SCROLL_SPEED :: f32(48)
EDITOR_SCROLL_SMOOTHNESS :: f32(18)

Rect :: struct {x,y,width,height:f32}
Pointer_Input :: struct {position:shared.Vec2,wheel_y:f32,primary_down,available:bool}
Paint_Kind :: enum {Panel,Glyph,Line}
Paint_Command :: struct {kind:Paint_Kind,rect:Rect,color:shared.Vec4,uv:shared.Vec4,corner_radius:f32,line_start,line_end:shared.Vec2,line_thickness:f32,clip:Rect,has_clip:bool}
Editor_Gizmo_Axis :: enum {None,X,Y,Z}
Font_Glyph :: struct {advance:f32,plane,uv:shared.Vec4}
Font_Atlas :: struct {glyphs:[FONT_CHAR_COUNT]Font_Glyph,ready:bool}
Node :: struct {
	entity:shared.Entity,
	layout_index,hstack_index,vstack_index,scroll_area_index,text_index,button_index,parent_entity_index:int,
	rect,clip:Rect,
	paint_order:int,
	scroll_offset,scroll_target,scroll_max,scroll_content_height:f32,
	seen,hovered,active,has_clip:bool,
}
State :: struct {
	nodes:[MAX_NODES]Node,
	node_count:int,
	paint:[MAX_PAINT_COMMANDS]Paint_Command,
	paint_count:int,
	font:Font_Atlas,
	active_entity:shared.Entity,
	has_active_entity:bool,
	previous_primary_down:bool,
	next_paint_order:int,
	editor_visible:bool,
	editor_pixel_density:f32,
	editor_paint_start:int,
	editor_selected_entity:shared.Entity,
	editor_has_selection:bool,
	editor_hovered_entity:shared.Entity,
	editor_has_hover:bool,
	editor_browser_scroll:f32,
	editor_browser_scroll_target:f32,
	editor_inspector_scroll:f32,
	editor_inspector_scroll_target:f32,
	editor_inspector_content_height:f32,
	editor_previous_primary_down:bool,
	editor_pick_requested:bool,
	editor_pick_position:shared.Vec2,
	editor_scene_camera_captures_input:bool,
	editor_gizmo_visible:bool,
	editor_gizmo_origin:shared.Vec2,
	editor_gizmo_endpoints:[3]shared.Vec2,
	editor_gizmo_hovered_axis:Editor_Gizmo_Axis,
	editor_gizmo_active_axis:Editor_Gizmo_Axis,
	editor_gizmo_captures_pointer:bool,
	editor_gizmo_drag_pointer:shared.Vec2,
	editor_gizmo_drag_position:shared.Vec3,
	editor_gizmo_drag_direction:shared.Vec2,
	editor_gizmo_drag_pixels:f32,
	editor_gizmo_drag_world_scale:f32,
	editor_gizmo_paint_start:int,
	editor_gizmo_paint_end:int,
	err:string,
}

init :: proc(state:^State)->string {
	state^={}
	state.editor_pixel_density=1
	state.font.glyphs=FONT_GLYPHS
	state.font.ready=true
	return ""
}

destroy :: proc(state:^State){if state==nil{return};state^={}}

reconcile :: proc(state:^State,world:^shared.World,width,height:f32,pointer:Pointer_Input={},drawable_width:f32=0,drawable_height:f32=0,delta_seconds:f32=1.0/60.0)->string {
	if state==nil||world==nil{return "UI state or world is unavailable"}
	surface_width:=drawable_width;if surface_width<=0 {surface_width=width}
	surface_height:=drawable_height;if surface_height<=0 {surface_height=height}
	if !state.font.ready {if err:=init(state);err!=""{return err}}
	for &node in state.nodes[:state.node_count]{node.seen=false}
	for &entity in world.entities {
		if !entity.alive||entity.ui_layout_index<0||entity.ui_layout_index>=len(world.ui_layouts){continue}
		index:=find_node(state,entity.id)
		if index<0 {if state.node_count>=MAX_NODES{return "too many UI entities"};index=state.node_count;state.node_count+=1;state.nodes[index]={}}
		node:=&state.nodes[index];node.entity=entity.id;node.layout_index=entity.ui_layout_index;node.hstack_index=entity.ui_hstack_index;node.vstack_index=entity.ui_vstack_index;node.scroll_area_index=entity.ui_scroll_area_index;node.text_index=entity.ui_text_index;node.button_index=entity.ui_button_index;node.parent_entity_index=find_parent_entity(world,world.ui_layouts[entity.ui_layout_index].parent);node.seen=true
	}
	for i:=0;i<state.node_count;{if state.nodes[i].seen{i+=1}else{state.node_count-=1;state.nodes[i]=state.nodes[state.node_count]}}
	viewport:=Rect{0,0,width,height}
	project_pointer:=project_pointer_input(state,pointer,width,height,surface_width,surface_height);if state.editor_gizmo_captures_pointer{project_pointer={}}
	if err:=layout_all(state,world,viewport);err!=""{return err}
	if update_scroll_areas(state,world,project_pointer,delta_seconds) {if err:=layout_all(state,world,viewport);err!=""{return err}}
	update_interaction(state,project_pointer)
	editor_scale:=max(state.editor_pixel_density,1)
	editor_pointer:=pointer
	if editor_pointer.available {editor_pointer.position.x/=editor_scale;editor_pointer.position.y/=editor_scale}
	update_editor_interaction(state,world,editor_pointer,surface_width/editor_scale,surface_height/editor_scale,delta_seconds)
	if state.editor_pick_requested {state.editor_pick_position.x*=editor_scale;state.editor_pick_position.y*=editor_scale}
	state.paint_count=0
	for i in 0..<state.node_count {if state.nodes[i].parent_entity_index<0 {if err:=paint_node(state,world,i,0);err!=""{return err}}}
	state.editor_paint_start=state.paint_count
	if state.editor_visible {
		if err:=append_editor_chrome(state,world,surface_width/editor_scale,surface_height/editor_scale,width,height);err!=""{return err}
		if editor_scale!=1 {scale_editor_chrome(state,editor_scale)}
	}
	return ""
}

editor_viewport :: proc(state:^State,drawable_width,drawable_height:f32,project_width:f32=1280,project_height:f32=720)->Rect {
	scale:=f32(1);if state!=nil&&state.editor_pixel_density>0{scale=state.editor_pixel_density}
	return editor_viewport_for_scale(state,drawable_width,drawable_height,scale)
}

editor_viewport_for_scale :: proc(state:^State,drawable_width,drawable_height,scale:f32)->Rect {
	available:=Rect{0,0,drawable_width,drawable_height}
	if state!=nil&&state.editor_visible {
		available={(EDITOR_LEFT_SIDEBAR_WIDTH+EDITOR_VIEWPORT_INSET)*scale,(EDITOR_TOP_BAR_HEIGHT+EDITOR_VIEWPORT_INSET)*scale,drawable_width-(EDITOR_LEFT_SIDEBAR_WIDTH+EDITOR_RIGHT_SIDEBAR_WIDTH+EDITOR_VIEWPORT_INSET*2)*scale,drawable_height-(EDITOR_TOP_BAR_HEIGHT+EDITOR_STATUS_BAR_HEIGHT+EDITOR_VIEWPORT_INSET*2)*scale}
	}
	if available.width<=0||available.height<=0{return {available.x,available.y,max(available.width,0),max(available.height,0)}}
	return available
}

project_pointer_input :: proc(state:^State,pointer:Pointer_Input,width,height:f32,drawable_width:f32=0,drawable_height:f32=0)->Pointer_Input {
	if state==nil||!pointer.available{return pointer}
	surface_width:=drawable_width;if surface_width<=0 {surface_width=width}
	surface_height:=drawable_height;if surface_height<=0 {surface_height=height}
	viewport:=editor_viewport(state,surface_width,surface_height,width,height)
	if !rect_contains(viewport,pointer.position){return {}}
	return {position={(pointer.position.x-viewport.x)/viewport.width*width,(pointer.position.y-viewport.y)/viewport.height*height},wheel_y=pointer.wheel_y,primary_down=pointer.primary_down,available=true}
}

editor_browser_rect :: proc(width,height:f32)->Rect{return {8,100,EDITOR_LEFT_SIDEBAR_WIDTH-16,max(height-EDITOR_STATUS_BAR_HEIGHT-108,0)}}

editor_clear_selection :: proc(state:^State){if state==nil{return};state.editor_has_selection=false;state.editor_inspector_scroll=0;state.editor_inspector_scroll_target=0;state.editor_gizmo_active_axis=.None;state.editor_gizmo_captures_pointer=false;state.editor_gizmo_visible=false}

editor_select_entity :: proc(state:^State,world:^shared.World,entity:shared.Entity,height:f32)->bool {
	if state==nil||world==nil{return false};index:=int(entity.index)
	if index<0||index>=len(world.entities)||!world.entities[index].alive||world.entities[index].id.generation!=entity.generation{return false}
	if !state.editor_has_selection||state.editor_selected_entity!=entity {state.editor_inspector_scroll=0;state.editor_inspector_scroll_target=0}
	if !state.editor_has_selection||state.editor_selected_entity!=entity {state.editor_gizmo_active_axis=.None;state.editor_gizmo_captures_pointer=false}
	state.editor_selected_entity=entity;state.editor_has_selection=true
	browser:=editor_browser_rect(EDITOR_LEFT_SIDEBAR_WIDTH,height)
	row:=0
	for candidate in world.entities {if !candidate.alive{continue};if candidate.id==entity{break};row+=1}
	row_top:=f32(row)*EDITOR_ENTITY_ROW_HEIGHT;row_bottom:=row_top+EDITOR_ENTITY_ROW_HEIGHT
	if row_top<state.editor_browser_scroll_target{state.editor_browser_scroll_target=row_top}
	else if row_bottom>state.editor_browser_scroll_target+browser.height{state.editor_browser_scroll_target=row_bottom-browser.height}
	return true
}

update_editor_interaction :: proc(state:^State,world:^shared.World,pointer:Pointer_Input,width,height,delta_seconds:f32) {
	state.editor_has_hover=false
	state.editor_pick_requested=false
	if state.editor_has_selection {
		index:=int(state.editor_selected_entity.index)
		if index<0||index>=len(world.entities)||!world.entities[index].alive||world.entities[index].id.generation!=state.editor_selected_entity.generation {editor_clear_selection(state)}
	}
	if !state.editor_visible {
		state.editor_previous_primary_down=false
		return
	}
	browser:=editor_browser_rect(width,height)
	alive_count:=0;for entity in world.entities{if entity.alive{alive_count+=1}}
	browser_scroll_max:=max(f32(alive_count)*EDITOR_ENTITY_ROW_HEIGHT-browser.height,0)
	if pointer.available&&rect_contains(browser,pointer.position)&&pointer.wheel_y!=0 {
		state.editor_browser_scroll_target=scroll_target_after_wheel(state.editor_browser_scroll_target,pointer.wheel_y,EDITOR_SCROLL_SPEED,browser_scroll_max)
	}
	state.editor_browser_scroll_target=clamp(state.editor_browser_scroll_target,0,browser_scroll_max)
	state.editor_browser_scroll=smooth_scroll_step(state.editor_browser_scroll,state.editor_browser_scroll_target,EDITOR_SCROLL_SMOOTHNESS,delta_seconds)
	state.editor_browser_scroll=clamp(state.editor_browser_scroll,0,browser_scroll_max)
	just_pressed:=pointer.primary_down&&!state.editor_previous_primary_down
	if pointer.available&&rect_contains(browser,pointer.position) {
		hit_row:=int((pointer.position.y-browser.y+state.editor_browser_scroll)/EDITOR_ENTITY_ROW_HEIGHT);alive_row:=0
		for entity in world.entities {
			if !entity.alive{continue}
			if alive_row==hit_row {
				state.editor_hovered_entity=entity.id;state.editor_has_hover=true
				if just_pressed {editor_select_entity(state,world,entity.id,height)}
				break
			}
			alive_row+=1
		}
	}
	viewport:=editor_viewport_for_scale(state,width,height,1)
	if just_pressed&&!state.editor_gizmo_captures_pointer&&pointer.available&&rect_contains(viewport,pointer.position) {state.editor_pick_requested=true;state.editor_pick_position=pointer.position}
	inspector:=Rect{width-EDITOR_RIGHT_SIDEBAR_WIDTH,180,EDITOR_RIGHT_SIDEBAR_WIDTH,max(height-EDITOR_STATUS_BAR_HEIGHT-188,0)}
	max_inspector_scroll:=max(state.editor_inspector_content_height-inspector.height,0)
	if pointer.available&&rect_contains(inspector,pointer.position)&&pointer.wheel_y!=0 {
		state.editor_inspector_scroll_target=scroll_target_after_wheel(state.editor_inspector_scroll_target,pointer.wheel_y,EDITOR_SCROLL_SPEED,max_inspector_scroll)
	}
	state.editor_inspector_scroll_target=clamp(state.editor_inspector_scroll_target,0,max_inspector_scroll)
	state.editor_inspector_scroll=smooth_scroll_step(state.editor_inspector_scroll,state.editor_inspector_scroll_target,EDITOR_SCROLL_SMOOTHNESS,delta_seconds)
	state.editor_inspector_scroll=clamp(state.editor_inspector_scroll,0,max_inspector_scroll)
	state.editor_previous_primary_down=pointer.primary_down
}

find_node :: proc(state:^State,entity:shared.Entity)->int{for node,i in state.nodes[:state.node_count]{if node.entity==entity{return i}};return -1}
find_node_by_entity_index :: proc(state:^State,index:int)->int{for node,i in state.nodes[:state.node_count]{if int(node.entity.index)==index{return i}};return -1}
find_parent_entity :: proc(world:^shared.World,name:string)->int{if name==""{return -1};for entity in world.entities{if entity.alive&&entity.name==name{return int(entity.id.index)}};return -1}

layout_all :: proc(state:^State,world:^shared.World,viewport:Rect)->string {
	state.next_paint_order=0
	for i in 0..<state.node_count {if state.nodes[i].parent_entity_index<0 {if err:=layout_node(state,world,i,viewport,{},false,{},false,0);err!=""{return err}}}
	return ""
}

layout_node :: proc(state:^State,world:^shared.World,node_index:int,parent:Rect,flow_position:shared.Vec2,flowed:bool,inherited_clip:Rect,has_inherited_clip:bool,depth:int)->string {
	if depth>MAX_NODES{return "UI hierarchy contains a cycle"}
	node:=&state.nodes[node_index];layout:=world.ui_layouts[node.layout_index]
	if node.parent_entity_index<0 {node.rect={layout.position.x+layout.margin.w,layout.position.y+layout.margin.x,layout.size.x,layout.size.y}}
	else if flowed {node.rect={flow_position.x,flow_position.y,layout.size.x,layout.size.y}}
	else {node.rect={parent.x+layout.padding.w+layout.position.x+layout.margin.w,parent.y+layout.padding.x+layout.position.y+layout.margin.x,layout.size.x,layout.size.y}}
	node.paint_order=state.next_paint_order;state.next_paint_order+=1
	node.clip=inherited_clip;node.has_clip=has_inherited_clip
	cursor:=f32(0)
	gap:=f32(0);is_hstack:=node.hstack_index>=0&&node.hstack_index<len(world.ui_hstacks);is_vstack:=node.vstack_index>=0&&node.vstack_index<len(world.ui_vstacks)
	is_scroll_area:=node.scroll_area_index>=0&&node.scroll_area_index<len(world.ui_scroll_areas)
	if is_hstack {gap=world.ui_hstacks[node.hstack_index].gap}
	if is_vstack {gap=world.ui_vstacks[node.vstack_index].gap}
	content:=Rect{node.rect.x+layout.padding.w,node.rect.y+layout.padding.x,max(node.rect.width-layout.padding.w-layout.padding.y,0),max(node.rect.height-layout.padding.x-layout.padding.z,0)}
	child_clip:=inherited_clip;child_has_clip:=has_inherited_clip
	if is_scroll_area {if child_has_clip{child_clip=rect_intersection(child_clip,content)}else{child_clip=content};child_has_clip=true}
	content_bottom:=f32(0)
	for child_index in 0..<state.node_count {
		child:=&state.nodes[child_index];if child.parent_entity_index!=int(node.entity.index){continue}
		child_layout:=world.ui_layouts[child.layout_index]
		position:shared.Vec2;child_flowed:=false
		if is_hstack {position={content.x+cursor+child_layout.margin.w,content.y+child_layout.margin.x};cursor+=child_layout.margin.w+child_layout.size.x+child_layout.margin.y+gap;child_flowed=true}
		else if is_vstack {position={content.x+child_layout.margin.w,content.y+cursor+child_layout.margin.x};cursor+=child_layout.margin.x+child_layout.size.y+child_layout.margin.z+gap;child_flowed=true}
		if is_scroll_area {position.y-=node.scroll_offset;if !child_flowed{position={node.rect.x+layout.padding.w+child_layout.position.x+child_layout.margin.w,content.y+child_layout.position.y+child_layout.margin.x-node.scroll_offset};child_flowed=true}}
		err:=layout_node(state,world,child_index,node.rect,position,child_flowed,child_clip,child_has_clip,depth+1)
		if err!=""{return err}
		unscrolled_bottom:=state.nodes[child_index].rect.y+state.nodes[child_index].rect.height+child_layout.margin.z
		if is_scroll_area {unscrolled_bottom+=node.scroll_offset}
		content_bottom=max(content_bottom,unscrolled_bottom-content.y)
	}
	if is_scroll_area {node.scroll_content_height=max(content.height,content_bottom);node.scroll_max=max(node.scroll_content_height-content.height,0);node.scroll_target=clamp(node.scroll_target,0,node.scroll_max);node.scroll_offset=clamp(node.scroll_offset,0,node.scroll_max)}
	return ""
}

scroll_target_after_wheel :: proc(target,wheel_y,speed,max_scroll:f32)->f32 {
	return clamp(target-wheel_y*speed,0,max_scroll)
}

smooth_scroll_step :: proc(offset,target,smoothness,delta_seconds:f32)->f32 {
	alpha:=f32(1)-math.exp(-smoothness*clamp(delta_seconds,0,f32(0.25)))
	next:=offset+(target-offset)*alpha
	if math.abs(target-next)<0.02{return target}
	return next
}

update_scroll_areas :: proc(state:^State,world:^shared.World,pointer:Pointer_Input,delta_seconds:f32)->bool {
	changed:=false
	if pointer.available&&pointer.wheel_y!=0 {
		hit:=-1;highest_order:=-1
		for node,index in state.nodes[:state.node_count] {
			if node.scroll_area_index<0||node.scroll_area_index>=len(world.ui_scroll_areas)||node.scroll_max<=0{continue}
			if node_pointer_contains(node,pointer.position)&&node.paint_order>=highest_order {hit=index;highest_order=node.paint_order}
		}
		if hit>=0 {node:=&state.nodes[hit];component:=world.ui_scroll_areas[node.scroll_area_index];node.scroll_target=scroll_target_after_wheel(node.scroll_target,pointer.wheel_y,component.scroll_speed,node.scroll_max)}
	}
	for &node in state.nodes[:state.node_count] {
		if node.scroll_area_index<0||node.scroll_area_index>=len(world.ui_scroll_areas){continue}
		component:=world.ui_scroll_areas[node.scroll_area_index]
		next:=smooth_scroll_step(node.scroll_offset,node.scroll_target,component.smoothness,delta_seconds)
		if math.abs(next-node.scroll_offset)>0.0001{node.scroll_offset=next;changed=true}
	}
	return changed
}

update_interaction :: proc(state:^State,pointer:Pointer_Input) {
	for &node in state.nodes[:state.node_count] {node.hovered=false;node.active=false}
	if !pointer.available {
		state.has_active_entity=false;state.previous_primary_down=false
		return
	}
	hit:=-1;highest_order:=-1
	for node,index in state.nodes[:state.node_count] {
		if node_pointer_contains(node,pointer.position) && node.paint_order>=highest_order {hit=index;highest_order=node.paint_order}
	}
	if hit>=0 {state.nodes[hit].hovered=true}
	if pointer.primary_down && !state.previous_primary_down {
		state.has_active_entity=hit>=0
		if hit>=0 {state.active_entity=state.nodes[hit].entity}
	}
	if pointer.primary_down && state.has_active_entity {
		if active:=find_node(state,state.active_entity);active>=0 {state.nodes[active].active=true} else {state.has_active_entity=false}
	} else if !pointer.primary_down {state.has_active_entity=false}
	state.previous_primary_down=pointer.primary_down
}

node_pointer_contains :: proc(node:Node,point:shared.Vec2)->bool{return rect_contains(node.rect,point)&&(!node.has_clip||rect_contains(node.clip,point))}
rect_intersection :: proc(a,b:Rect)->Rect{x0:=max(a.x,b.x);y0:=max(a.y,b.y);x1:=min(a.x+a.width,b.x+b.width);y1:=min(a.y+a.height,b.y+b.height);return {x0,y0,max(x1-x0,0),max(y1-y0,0)}}

paint_node :: proc(state:^State,world:^shared.World,node_index,depth:int)->string {
	if depth>MAX_NODES{return "UI hierarchy contains a cycle"}
	node:=&state.nodes[node_index];layout:=world.ui_layouts[node.layout_index]
	paint_start:=state.paint_count
	background:=layout.background
	if node.button_index>=0&&node.button_index<len(world.ui_buttons) {
		button:=world.ui_buttons[node.button_index]
		if node.active&&button.active_background.w>0 {background=button.active_background}
		else if node.hovered&&button.hover_background.w>0 {background=button.hover_background}
	}
	if background.w>0 {if err:=append_paint(state,{kind=.Panel,rect=node.rect,color=background,uv={0,0,0,0},corner_radius=layout.corner_radius});err!=""{return err}}
	if node.text_index>=0&&node.text_index<len(world.ui_texts){text:=world.ui_texts[node.text_index];if err:=append_text(state,text.text,text.color,text.size,node.rect,layout.padding);err!=""{return err}}
	if node.button_index>=0&&node.button_index<len(world.ui_buttons){button:=world.ui_buttons[node.button_index];color:=button.color;if node.active&&button.active_color.w>0{color=button.active_color}else if node.hovered&&button.hover_color.w>0{color=button.hover_color};if err:=append_centered_text(state,button.text,color,button.size,node.rect,layout.padding);err!=""{return err}}
	apply_paint_clip(state,paint_start,state.paint_count,node.clip,node.has_clip)
	for child_index in 0..<state.node_count {if state.nodes[child_index].parent_entity_index==int(node.entity.index){if err:=paint_node(state,world,child_index,depth+1);err!=""{return err}}}
	if node.scroll_area_index>=0&&node.scroll_area_index<len(world.ui_scroll_areas)&&node.scroll_max>0 {
		track:=Rect{node.rect.x+node.rect.width-7,node.rect.y+5,3,max(node.rect.height-10,0)}
		thumb_height:=max(track.height*track.height/max(node.scroll_content_height,track.height),18)
		thumb_y:=track.y+(track.height-thumb_height)*node.scroll_offset/max(node.scroll_max,1)
		start:=state.paint_count
		if err:=append_paint(state,{kind=.Panel,rect=track,color={0.08,0.09,0.11,0.78},corner_radius=1.5});err!=""{return err}
		if err:=append_paint(state,{kind=.Panel,rect={track.x,thumb_y,track.width,thumb_height},color={0.34,0.37,0.42,0.92},corner_radius=1.5});err!=""{return err}
		apply_paint_clip(state,start,state.paint_count,node.clip,node.has_clip)
	}
	return ""
}

apply_paint_clip :: proc(state:^State,start,end:int,clip:Rect,has_clip:bool){if !has_clip{return};for &command in state.paint[start:end]{command.clip=clip;command.has_clip=true}}

rect_contains :: proc(rect:Rect,point:shared.Vec2)->bool{return point.x>=rect.x&&point.y>=rect.y&&point.x<rect.x+rect.width&&point.y<rect.y+rect.height}

append_editor_chrome :: proc(state:^State,world:^shared.World,width,height,project_width,project_height:f32)->string {
	viewport:=editor_viewport_for_scale(state,width,height,1)
	// UI colors are linear and the sRGB target encodes them for display.
	top_color:=shared.Vec4{0.006,0.007,0.009,1};panel_color:=shared.Vec4{0.009,0.011,0.014,0.995};status_color:=shared.Vec4{0.005,0.006,0.008,1};seam:=shared.Vec4{0.030,0.037,0.051,1};muted:=shared.Vec4{0.287,0.319,0.366,1};text_color:=shared.Vec4{0.791,0.815,0.847,1}
	panels:=[6]Paint_Command{
		{kind=.Panel,rect={0,0,width,EDITOR_TOP_BAR_HEIGHT},color=top_color},
		{kind=.Panel,rect={0,EDITOR_TOP_BAR_HEIGHT,EDITOR_LEFT_SIDEBAR_WIDTH,height-EDITOR_TOP_BAR_HEIGHT-EDITOR_STATUS_BAR_HEIGHT},color=panel_color},
		{kind=.Panel,rect={width-EDITOR_RIGHT_SIDEBAR_WIDTH,EDITOR_TOP_BAR_HEIGHT,EDITOR_RIGHT_SIDEBAR_WIDTH,height-EDITOR_TOP_BAR_HEIGHT-EDITOR_STATUS_BAR_HEIGHT},color=panel_color},
		{kind=.Panel,rect={0,height-EDITOR_STATUS_BAR_HEIGHT,width,EDITOR_STATUS_BAR_HEIGHT},color=status_color},
		{kind=.Panel,rect={viewport.x-EDITOR_VIEWPORT_INSET,viewport.y-EDITOR_VIEWPORT_INSET,EDITOR_VIEWPORT_INSET,viewport.height+EDITOR_VIEWPORT_INSET*2},color=seam},
		{kind=.Panel,rect={viewport.x+viewport.width,viewport.y-EDITOR_VIEWPORT_INSET,EDITOR_VIEWPORT_INSET,viewport.height+EDITOR_VIEWPORT_INSET*2},color=seam},
	}
	for panel in panels {if err:=append_paint(state,panel);err!=""{return err}}
	if err:=append_paint(state,{kind=.Panel,rect={viewport.x-EDITOR_VIEWPORT_INSET,viewport.y-EDITOR_VIEWPORT_INSET,viewport.width+EDITOR_VIEWPORT_INSET*2,EDITOR_VIEWPORT_INSET},color=seam});err!=""{return err}
	if err:=append_paint(state,{kind=.Panel,rect={viewport.x-EDITOR_VIEWPORT_INSET,viewport.y+viewport.height,viewport.width+EDITOR_VIEWPORT_INSET*2,EDITOR_VIEWPORT_INSET},color=seam});err!=""{return err}
	if err:=append_paint(state,{kind=.Panel,rect={0,0,width,1},color={0.040,0.672,0.509,0.9}});err!=""{return err}
	if err:=append_paint(state,{kind=.Panel,rect={14,15,3,18},color={0.040,0.672,0.509,1},corner_radius=1});err!=""{return err}
	if err:=append_text(state,"SCRAPBOT",text_color,18,{23,10,120,30},{});err!=""{return err}
	if err:=append_text(state,"EDITOR / LIVE PROJECT",muted,13,{132,13,240,24},{});err!=""{return err}
	if err:=append_text(state,"SCENE",text_color,14,{18,68,180,24},{});err!=""{return err}
	if err:=append_text(state,"INSPECTOR",text_color,14,{width-EDITOR_RIGHT_SIDEBAR_WIDTH+18,68,220,24},{});err!=""{return err}
	if err:=append_entity_browser(state,world,width,height,muted,text_color);err!=""{return err}
	if err:=append_entity_inspector(state,world,width,height,muted,text_color);err!=""{return err}
	state.editor_gizmo_paint_start=state.paint_count
	if err:=append_editor_gizmo(state);err!=""{return err}
	state.editor_gizmo_paint_end=state.paint_count
	running_entity_count:=0
	for entity in world.entities {if entity.alive {running_entity_count+=1}}
	entity_status:=fmt.tprintf("RUNNING  /  %d ENTITIES",running_entity_count)
	if err:=append_text(state,entity_status,{0.125,0.651,0.423,1},12,{14,height-EDITOR_STATUS_BAR_HEIGHT+5,260,20},{});err!=""{return err}
	if err:=append_text(state,"RMB + WASD / SPACE / CTRL  FLY",muted,10,{max(width*0.5-140,280),height-EDITOR_STATUS_BAR_HEIGHT+7,280,18},{});err!=""{return err}
	if err:=append_text(state,"CTRL+ESC  CLOSE EDITOR",muted,12,{width-220,height-EDITOR_STATUS_BAR_HEIGHT+5,206,20},{});err!=""{return err}
	return ""
}

scale_paint_command :: proc(command:^Paint_Command,scale:f32) {
	command.rect={command.rect.x*scale,command.rect.y*scale,command.rect.width*scale,command.rect.height*scale}
	command.corner_radius*=scale
	command.line_start.x*=scale;command.line_start.y*=scale;command.line_end.x*=scale;command.line_end.y*=scale;command.line_thickness*=scale
	if command.has_clip {command.clip={command.clip.x*scale,command.clip.y*scale,command.clip.width*scale,command.clip.height*scale}}
}

scale_editor_chrome :: proc(state:^State,scale:f32) {
	for i in state.editor_paint_start..<state.editor_gizmo_paint_start {scale_paint_command(&state.paint[i],scale)}
	for i in state.editor_gizmo_paint_end..<state.paint_count {scale_paint_command(&state.paint[i],scale)}
}

append_editor_gizmo :: proc(state:^State)->string {
	if !state.editor_gizmo_visible{return ""}
	scale:=max(state.editor_pixel_density,1)
	colors:=[3]shared.Vec4{{0.95,0.20,0.24,1},{0.28,0.88,0.42,1},{0.24,0.48,1,1}}
	labels:=[3]string{"X","Y","Z"}
	for endpoint,index in state.editor_gizmo_endpoints {
		axis:=Editor_Gizmo_Axis(index+1);color:=colors[index];thickness:=f32(5)*scale
		if state.editor_gizmo_hovered_axis==axis||state.editor_gizmo_active_axis==axis {color.x=min(color.x+0.28,1);color.y=min(color.y+0.28,1);color.z=min(color.z+0.28,1);thickness=8*scale}
		if err:=append_paint(state,{kind=.Line,color=color,line_start=state.editor_gizmo_origin,line_end=endpoint,line_thickness=thickness,corner_radius=thickness*0.5});err!=""{return err}
		if err:=append_paint(state,{kind=.Panel,rect={endpoint.x-6*scale,endpoint.y-6*scale,12*scale,12*scale},color=color,corner_radius=6*scale});err!=""{return err}
		if err:=append_text(state,labels[index],color,11*scale,{endpoint.x+8*scale,endpoint.y-7*scale,16*scale,16*scale},{});err!=""{return err}
	}
	if err:=append_paint(state,{kind=.Panel,rect={state.editor_gizmo_origin.x-4*scale,state.editor_gizmo_origin.y-4*scale,8*scale,8*scale},color={0.88,0.92,0.98,1},corner_radius=4*scale});err!=""{return err}
	return ""
}

append_entity_browser :: proc(state:^State,world:^shared.World,width,height:f32,muted,text_color:shared.Vec4)->string {
	scene_count,runtime_count,editor_count:=0,0,0
	for entity in world.entities {if entity.alive {switch entity.origin {case .Scene:scene_count+=1;case .Runtime:runtime_count+=1;case .Editor:editor_count+=1}}}
	counts:=fmt.tprintf("%d SCENE / %d LIVE / %d EDITOR",scene_count,runtime_count,editor_count)
	if err:=append_text(state,counts,muted,10,{18,86,210,16},{});err!=""{return err}
	browser:=editor_browser_rect(width,height);alive_row:=0
	for entity in world.entities {
		if !entity.alive{continue}
		row:=Rect{browser.x,browser.y+f32(alive_row)*EDITOR_ENTITY_ROW_HEIGHT-state.editor_browser_scroll,browser.width,EDITOR_ENTITY_ROW_HEIGHT-2};alive_row+=1
		if row.y+row.height<=browser.y||row.y>=browser.y+browser.height{continue}
		paint_start:=state.paint_count
		selected:=state.editor_has_selection&&state.editor_selected_entity==entity.id
		hovered:=state.editor_has_hover&&state.editor_hovered_entity==entity.id
		if selected {if err:=append_paint(state,{kind=.Panel,rect=row,color={0.022,0.026,0.034,1},corner_radius=3});err!=""{return err}}
		else if hovered {if err:=append_paint(state,{kind=.Panel,rect=row,color={0.014,0.017,0.022,1},corner_radius=3});err!=""{return err}}
		origin_color:=shared.Vec4{0.125,0.651,0.423,1};origin_label:="SCENE"
		if entity.origin==.Runtime {origin_color={0.761,0.323,0.042,1};origin_label="LIVE"}
		if entity.origin==.Editor {origin_color={0.418,0.209,0.913,1};origin_label="EDIT"}
		if err:=append_paint(state,{kind=.Panel,rect={row.x,row.y,3,row.height},color=origin_color,corner_radius=1});err!=""{return err}
		if err:=append_text(state,origin_label,origin_color,9,{row.x+9,row.y+8,46,14},{});err!=""{return err}
		name:=entity.name;if name==""{name=fmt.tprintf("Entity %d",entity.id.index)}
		if err:=append_text_clipped(state,name,text_color,11,{row.x+59,row.y+7,row.width-65,16});err!=""{return err}
		apply_paint_clip(state,paint_start,state.paint_count,browser,true)
	}
	alive_count:=scene_count+runtime_count+editor_count
	content_height:=f32(alive_count)*EDITOR_ENTITY_ROW_HEIGHT
	if content_height>browser.height&&browser.height>0 {
		track:=Rect{browser.x+browser.width-6,browser.y+3,3,max(browser.height-6,0)}
		thumb_height:=max(track.height*browser.height/content_height,20)
		max_scroll:=content_height-browser.height;thumb_y:=track.y+(track.height-thumb_height)*state.editor_browser_scroll/max_scroll
		if err:=append_paint(state,{kind=.Panel,rect=track,color={0.005,0.006,0.008,1},corner_radius=1});err!=""{return err}
		if err:=append_paint(state,{kind=.Panel,rect={track.x,thumb_y,track.width,thumb_height},color={0.180,0.202,0.240,0.95},corner_radius=1.5});err!=""{return err}
	}
	return ""
}

entity_component_count :: proc(world:^shared.World,entity_index:int)->int {
	if entity_index<0||entity_index>=len(world.entities){return 0};entity:=world.entities[entity_index];count:=0
	indices:=[12]int{entity.transform_index,entity.camera_index,entity.ambient_light_index,entity.directional_light_index,entity.point_light_index,entity.mesh_index,entity.geometry_index,entity.material_index,entity.render_instance_index,entity.ui_layout_index,entity.ui_scroll_area_index,entity.ui_text_index}
	for index in indices{if index>=0{count+=1}}
	if entity.ui_hstack_index>=0{count+=1};if entity.ui_vstack_index>=0{count+=1};if entity.ui_button_index>=0{count+=1}
	if entity.editor_transform_gizmo_index>=0&&entity.editor_transform_gizmo_index<len(world.editor_transform_gizmos)&&world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index==entity_index{count+=1}
	for camera in world.editor_scene_cameras {if camera.entity_index==entity_index{count+=1;break}}
	if entity.has_shadow_caster{count+=1};if entity.has_shadow_receiver{count+=1}
	for storage in world.custom_components {for component in storage.components {if component.entity_index==entity_index{count+=1;break}}}
	return count
}

Inspector_Layout :: struct {state:^State,x,width,top,bottom,scroll,cursor:f32,text_color,muted,value_color:shared.Vec4}

inspector_section :: proc(layout:^Inspector_Layout,label:string)->string {
	y:=layout.top+layout.cursor-layout.scroll
	if y+23>layout.top&&y<layout.bottom {
		paint_start:=layout.state.paint_count
		if err:=append_paint(layout.state,{kind=.Panel,rect={layout.x,y,layout.width,23},color={0.018,0.021,0.030,1},corner_radius=3});err!=""{return err}
		if err:=append_text_clipped(layout.state,label,layout.text_color,11,{layout.x+9,y+6,layout.width-18,14});err!=""{return err}
		apply_paint_clip(layout.state,paint_start,layout.state.paint_count,{layout.x,layout.top,layout.width,layout.bottom-layout.top},true)
	}
	layout.cursor+=27;return ""
}

inspector_field :: proc(layout:^Inspector_Layout,label,value:string)->string {
	y:=layout.top+layout.cursor-layout.scroll
	if y+16>layout.top&&y<layout.bottom {
		paint_start:=layout.state.paint_count
		if err:=append_text_clipped(layout.state,label,layout.muted,9,{layout.x+8,y+4,78,12});err!=""{return err}
		if err:=append_text_clipped(layout.state,value,layout.value_color,9,{layout.x+88,y+4,layout.width-96,12});err!=""{return err}
		apply_paint_clip(layout.state,paint_start,layout.state.paint_count,{layout.x,layout.top,layout.width,layout.bottom-layout.top},true)
	}
	layout.cursor+=18;return ""
}

inspector_gap :: proc(layout:^Inspector_Layout){layout.cursor+=6}
format_vec2 :: proc(value:shared.Vec2)->string{return fmt.tprintf("(%.2f, %.2f)",value.x,value.y)}
format_vec3 :: proc(value:shared.Vec3)->string{return fmt.tprintf("(%.2f, %.2f, %.2f)",value.x,value.y,value.z)}
format_vec4 :: proc(value:shared.Vec4)->string{return fmt.tprintf("(%.2f, %.2f, %.2f, %.2f)",value.x,value.y,value.z,value.w)}
format_handle :: proc(index,generation:u32)->string{return fmt.tprintf("#%d:%d",index,generation)}

append_entity_inspector :: proc(state:^State,world:^shared.World,width,height:f32,muted,text_color:shared.Vec4)->string {
	x:=width-EDITOR_RIGHT_SIDEBAR_WIDTH+18;content_width:=EDITOR_RIGHT_SIDEBAR_WIDTH-36
	if !state.editor_has_selection {return append_text(state,"Select an entity to inspect",muted,12,{x,104,content_width,24},{})}
	index:=int(state.editor_selected_entity.index);if index<0||index>=len(world.entities){return ""};entity:=world.entities[index]
	name:=entity.name;if name==""{name=fmt.tprintf("Entity %d",entity.id.index)}
	if err:=append_text_clipped(state,name,text_color,15,{x,103,content_width,22});err!=""{return err}
	origin_label:="SCENE ENTITY";origin_color:=shared.Vec4{0.125,0.651,0.423,1};if entity.origin==.Runtime{origin_label="RUNTIME ENTITY";origin_color={0.761,0.323,0.042,1}}else if entity.origin==.Editor{origin_label="EDITOR ENTITY";origin_color={0.418,0.209,0.913,1}}
	identity:=fmt.tprintf("%s  /  #%d:%d",origin_label,entity.id.index,entity.id.generation)
	if err:=append_text_clipped(state,identity,origin_color,10,{x,130,content_width,16});err!=""{return err}
	component_count:=entity_component_count(world,index);heading:=fmt.tprintf("COMPONENTS  /  %d",component_count)
	if err:=append_text(state,heading,muted,10,{x,161,content_width,16},{});err!=""{return err}
	top:=f32(184);bottom:=height-EDITOR_STATUS_BAR_HEIGHT-8;visible_height:=max(bottom-top,0)
	max_scroll:=max(state.editor_inspector_content_height-visible_height,0);state.editor_inspector_scroll_target=clamp(state.editor_inspector_scroll_target,0,max_scroll);state.editor_inspector_scroll=clamp(state.editor_inspector_scroll,0,max_scroll)
	layout:=Inspector_Layout{state=state,x=x,width=content_width,top=top,bottom=bottom,scroll=state.editor_inspector_scroll,text_color=text_color,muted=muted,value_color={0.638,0.673,0.745,1}}
	if entity.transform_index>=0&&entity.transform_index<len(world.transforms) {value:=world.transforms[entity.transform_index];if err:=inspector_section(&layout,"Transform");err!=""{return err};if err:=inspector_field(&layout,"position",format_vec3(value.position));err!=""{return err};if err:=inspector_field(&layout,"rotation",format_vec3(value.rotation));err!=""{return err};if err:=inspector_field(&layout,"scale",format_vec3(value.scale));err!=""{return err};inspector_gap(&layout)}
	if entity.editor_transform_gizmo_index>=0&&entity.editor_transform_gizmo_index<len(world.editor_transform_gizmos)&&world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index==index {value:=world.editor_transform_gizmos[entity.editor_transform_gizmo_index];mode:="world translation";switch value.mode{case .World_Translate:};if err:=inspector_section(&layout,"Editor Transform Gizmo");err!=""{return err};if err:=inspector_field(&layout,"mode",mode);err!=""{return err};inspector_gap(&layout)}
	for value in world.editor_scene_cameras {if value.entity_index==index {if err:=inspector_section(&layout,"Editor Scene Camera");err!=""{return err};if err:=inspector_field(&layout,"move speed",fmt.tprintf("%.2f",value.move_speed));err!=""{return err};if err:=inspector_field(&layout,"look sensitivity",fmt.tprintf("%.4f",value.look_sensitivity));err!=""{return err};inspector_gap(&layout);break}}
	if entity.camera_index>=0&&entity.camera_index<len(world.cameras) {value:=world.cameras[entity.camera_index];if err:=inspector_section(&layout,"Camera");err!=""{return err};if err:=inspector_field(&layout,"fov",fmt.tprintf("%.2f",value.fov));err!=""{return err};if err:=inspector_field(&layout,"near",fmt.tprintf("%.3f",value.near));err!=""{return err};if err:=inspector_field(&layout,"far",fmt.tprintf("%.2f",value.far));err!=""{return err};inspector_gap(&layout)}
	if entity.ambient_light_index>=0&&entity.ambient_light_index<len(world.ambient_lights) {value:=world.ambient_lights[entity.ambient_light_index];if err:=inspector_section(&layout,"Ambient Light");err!=""{return err};if err:=inspector_field(&layout,"color",format_vec3(value.color));err!=""{return err};if err:=inspector_field(&layout,"intensity",fmt.tprintf("%.2f",value.intensity));err!=""{return err};inspector_gap(&layout)}
	if entity.directional_light_index>=0&&entity.directional_light_index<len(world.directional_lights) {value:=world.directional_lights[entity.directional_light_index];if err:=inspector_section(&layout,"Directional Light");err!=""{return err};if err:=inspector_field(&layout,"direction",format_vec3(value.direction));err!=""{return err};if err:=inspector_field(&layout,"color",format_vec3(value.color));err!=""{return err};if err:=inspector_field(&layout,"intensity",fmt.tprintf("%.2f",value.intensity));err!=""{return err};inspector_gap(&layout)}
	if entity.point_light_index>=0&&entity.point_light_index<len(world.point_lights) {value:=world.point_lights[entity.point_light_index];if err:=inspector_section(&layout,"Point Light");err!=""{return err};if err:=inspector_field(&layout,"color",format_vec3(value.color));err!=""{return err};if err:=inspector_field(&layout,"intensity",fmt.tprintf("%.2f",value.intensity));err!=""{return err};if err:=inspector_field(&layout,"range",fmt.tprintf("%.2f",value.range));err!=""{return err};inspector_gap(&layout)}
	if entity.mesh_index>=0&&entity.mesh_index<len(world.meshes) {value:=world.meshes[entity.mesh_index];if err:=inspector_section(&layout,"Mesh");err!=""{return err};if err:=inspector_field(&layout,"primitive",value.primitive);err!=""{return err};inspector_gap(&layout)}
	if entity.geometry_index>=0&&entity.geometry_index<len(world.geometries) {value:=world.geometries[entity.geometry_index];if err:=inspector_section(&layout,"Geometry");err!=""{return err};if err:=inspector_field(&layout,"handle",format_handle(value.handle.index,value.handle.generation));err!=""{return err};inspector_gap(&layout)}
	if entity.material_index>=0&&entity.material_index<len(world.materials) {value:=world.materials[entity.material_index];if err:=inspector_section(&layout,"Material");err!=""{return err};if err:=inspector_field(&layout,"handle",format_handle(value.handle.index,value.handle.generation));err!=""{return err};inspector_gap(&layout)}
	if entity.render_instance_index>=0&&entity.render_instance_index<len(world.render_instances) {value:=world.render_instances[entity.render_instance_index];if err:=inspector_section(&layout,"Render Instance");err!=""{return err};if err:=inspector_field(&layout,"geometry",format_handle(value.geometry.index,value.geometry.generation));err!=""{return err};if err:=inspector_field(&layout,"material",format_handle(value.material.index,value.material.generation));err!=""{return err};inspector_gap(&layout)}
	if entity.has_shadow_caster{if err:=inspector_section(&layout,"Shadow Caster");err!=""{return err};inspector_gap(&layout)}
	if entity.has_shadow_receiver{if err:=inspector_section(&layout,"Shadow Receiver");err!=""{return err};inspector_gap(&layout)}
	if entity.ui_layout_index>=0&&entity.ui_layout_index<len(world.ui_layouts) {value:=world.ui_layouts[entity.ui_layout_index];if err:=inspector_section(&layout,"UI Layout");err!=""{return err};if err:=inspector_field(&layout,"parent",value.parent);err!=""{return err};if err:=inspector_field(&layout,"position",format_vec2(value.position));err!=""{return err};if err:=inspector_field(&layout,"size",format_vec2(value.size));err!=""{return err};if err:=inspector_field(&layout,"margin",format_vec4(value.margin));err!=""{return err};if err:=inspector_field(&layout,"padding",format_vec4(value.padding));err!=""{return err};if err:=inspector_field(&layout,"background",format_vec4(value.background));err!=""{return err};if err:=inspector_field(&layout,"radius",fmt.tprintf("%.2f",value.corner_radius));err!=""{return err};inspector_gap(&layout)}
	if entity.ui_hstack_index>=0&&entity.ui_hstack_index<len(world.ui_hstacks) {value:=world.ui_hstacks[entity.ui_hstack_index];if err:=inspector_section(&layout,"UI HStack");err!=""{return err};if err:=inspector_field(&layout,"gap",fmt.tprintf("%.2f",value.gap));err!=""{return err};inspector_gap(&layout)}
	if entity.ui_vstack_index>=0&&entity.ui_vstack_index<len(world.ui_vstacks) {value:=world.ui_vstacks[entity.ui_vstack_index];if err:=inspector_section(&layout,"UI VStack");err!=""{return err};if err:=inspector_field(&layout,"gap",fmt.tprintf("%.2f",value.gap));err!=""{return err};inspector_gap(&layout)}
	if entity.ui_scroll_area_index>=0&&entity.ui_scroll_area_index<len(world.ui_scroll_areas) {value:=world.ui_scroll_areas[entity.ui_scroll_area_index];if err:=inspector_section(&layout,"UI Scroll Area");err!=""{return err};if err:=inspector_field(&layout,"scroll speed",fmt.tprintf("%.2f",value.scroll_speed));err!=""{return err};if err:=inspector_field(&layout,"smoothness",fmt.tprintf("%.2f",value.smoothness));err!=""{return err};inspector_gap(&layout)}
	if entity.ui_text_index>=0&&entity.ui_text_index<len(world.ui_texts) {value:=world.ui_texts[entity.ui_text_index];if err:=inspector_section(&layout,"UI Text");err!=""{return err};if err:=inspector_field(&layout,"text",value.text);err!=""{return err};if err:=inspector_field(&layout,"color",format_vec4(value.color));err!=""{return err};if err:=inspector_field(&layout,"size",fmt.tprintf("%.2f",value.size));err!=""{return err};inspector_gap(&layout)}
	if entity.ui_button_index>=0&&entity.ui_button_index<len(world.ui_buttons) {value:=world.ui_buttons[entity.ui_button_index];if err:=inspector_section(&layout,"UI Button");err!=""{return err};if err:=inspector_field(&layout,"text",value.text);err!=""{return err};if err:=inspector_field(&layout,"color",format_vec4(value.color));err!=""{return err};if err:=inspector_field(&layout,"size",fmt.tprintf("%.2f",value.size));err!=""{return err};if err:=inspector_field(&layout,"hover bg",format_vec4(value.hover_background));err!=""{return err};if err:=inspector_field(&layout,"active bg",format_vec4(value.active_background));err!=""{return err};inspector_gap(&layout)}
	for storage in world.custom_components {for component in storage.components {if component.entity_index==index {if err:=inspector_section(&layout,storage.name);err!=""{return err};for field in component.vec3_fields {if err:=inspector_field(&layout,field.name,format_vec3(field.value));err!=""{return err}};inspector_gap(&layout);break}}}
	state.editor_inspector_content_height=layout.cursor
	if layout.cursor>visible_height&&visible_height>0 {track:=Rect{x+content_width-3,top,3,visible_height};thumb_height:=max(track.height*visible_height/layout.cursor,20);thumb_y:=track.y+(track.height-thumb_height)*state.editor_inspector_scroll/max(layout.cursor-visible_height,1);if err:=append_paint(state,{kind=.Panel,rect=track,color={0.005,0.006,0.008,1},corner_radius=1});err!=""{return err};if err:=append_paint(state,{kind=.Panel,rect={track.x,thumb_y,3,thumb_height},color={0.180,0.202,0.240,0.95},corner_radius=1.5});err!=""{return err}}
	return ""
}

append_text :: proc(state:^State,text:string,color:shared.Vec4,size:f32,rect:Rect,padding:shared.Vec4)->string {
	x:=rect.x+padding.w;baseline:=rect.y+padding.x+FONT_ASCENDER*size
	return append_text_at(state,text,color,size,x,baseline,rect.x+padding.w)
}

append_text_clipped :: proc(state:^State,text:string,color:shared.Vec4,size:f32,rect:Rect)->string {
	x:=rect.x;baseline:=rect.y+FONT_ASCENDER*size
	for character in text {
		code:=int(character);if code<FONT_FIRST_CHAR||code>=FONT_FIRST_CHAR+FONT_CHAR_COUNT{code=int('?')};glyph:=state.font.glyphs[code-FONT_FIRST_CHAR]
		width:=(glyph.plane.z-glyph.plane.x)*size;height:=(glyph.plane.w-glyph.plane.y)*size;glyph_x:=x+glyph.plane.x*size
		if glyph_x+width>rect.x+rect.width{return ""}
		if width>0&&height>0 {if err:=append_paint(state,{kind=.Glyph,rect={glyph_x,baseline+glyph.plane.y*size,width,height},color=color,uv=glyph.uv});err!=""{return err}}
		x+=glyph.advance*size
	}
	return ""
}

append_centered_text :: proc(state:^State,text:string,color:shared.Vec4,size:f32,rect:Rect,padding:shared.Vec4)->string {
	bounds,has_ink:=measure_text_ink(state,text,size)
	if !has_ink{return ""}
	content:=Rect{rect.x+padding.w,rect.y+padding.x,rect.width-padding.w-padding.y,rect.height-padding.x-padding.z}
	x:=content.x+(content.width-bounds.width)*0.5-bounds.x
	baseline:=content.y+(content.height-bounds.height)*0.5-bounds.y
	return append_text_at(state,text,color,size,x,baseline,x)
}

append_text_at :: proc(state:^State,text:string,color:shared.Vec4,size,x_start,baseline_start,line_start:f32)->string {
	x:=x_start;baseline:=baseline_start
	for character in text {
		if character=='\n'{x=line_start;baseline+=size;continue}
		code:=int(character);if code<FONT_FIRST_CHAR||code>=FONT_FIRST_CHAR+FONT_CHAR_COUNT{code=int('?')}
		glyph:=state.font.glyphs[code-FONT_FIRST_CHAR]
		width:=(glyph.plane.z-glyph.plane.x)*size;height:=(glyph.plane.w-glyph.plane.y)*size
		if width>0&&height>0 {if err:=append_paint(state,{kind=.Glyph,rect={x+glyph.plane.x*size,baseline+glyph.plane.y*size,width,height},color=color,uv=glyph.uv});err!=""{return err}}
		x+=glyph.advance*size
	}
	return ""
}

measure_text_ink :: proc(state:^State,text:string,size:f32)->(Rect,bool) {
	x:=f32(0);min_x,min_y,max_x,max_y:=f32(0),f32(0),f32(0),f32(0);has_ink:=false
	for character in text {
		if character=='\n'{break}
		code:=int(character);if code<FONT_FIRST_CHAR||code>=FONT_FIRST_CHAR+FONT_CHAR_COUNT{code=int('?')}
		glyph:=state.font.glyphs[code-FONT_FIRST_CHAR]
		x0:=x+glyph.plane.x*size;y0:=glyph.plane.y*size;x1:=x+glyph.plane.z*size;y1:=glyph.plane.w*size
		if x1>x0&&y1>y0 {if !has_ink{min_x=x0;min_y=y0;max_x=x1;max_y=y1;has_ink=true}else{min_x=min(min_x,x0);min_y=min(min_y,y0);max_x=max(max_x,x1);max_y=max(max_y,y1)}}
		x+=glyph.advance*size
	}
	return {min_x,min_y,max_x-min_x,max_y-min_y},has_ink
}

append_paint :: proc(state:^State,command:Paint_Command)->(string){if state.paint_count>=MAX_PAINT_COMMANDS{return "too many UI paint commands"};state.paint[state.paint_count]=command;state.paint_count+=1;return ""}
