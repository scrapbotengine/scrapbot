package ui

import c "core:c"
import shared "../shared"
import stb "vendor:stb/truetype"

MAX_NODES :: 256
MAX_PAINT_COMMANDS :: 4096
FONT_FIRST_CHAR :: 32
FONT_CHAR_COUNT :: 95
FONT_ATLAS_SIZE :: 256
FONT_BAKE_SIZE :: f32(16)
FONT_DATA :: #load("assets/monogram.ttf")

Rect :: struct {x,y,width,height:f32}
Paint_Kind :: enum {Panel,Glyph}
Paint_Command :: struct {kind:Paint_Kind,rect:Rect,color:shared.Vec4,uv:shared.Vec4}
Font_Atlas :: struct {pixels:[FONT_ATLAS_SIZE*FONT_ATLAS_SIZE]u8,glyphs:[FONT_CHAR_COUNT]stb.bakedchar,ready:bool}
Node :: struct {entity:shared.Entity,layout_index,text_index,parent_entity_index:int,rect:Rect,seen:bool}
State :: struct {
	nodes:[MAX_NODES]Node,
	node_count:int,
	paint:[MAX_PAINT_COMMANDS]Paint_Command,
	paint_count:int,
	font:Font_Atlas,
	err:string,
}

init :: proc(state:^State)->string {
	state^={}
	result:=stb.BakeFontBitmap(raw_data(FONT_DATA),0,FONT_BAKE_SIZE,raw_data(state.font.pixels[:]),FONT_ATLAS_SIZE,FONT_ATLAS_SIZE,FONT_FIRST_CHAR,FONT_CHAR_COUNT,raw_data(state.font.glyphs[:]))
	if result<=0 {state.err="failed to bake built-in UI font atlas";return state.err}
	state.font.ready=true
	return ""
}

destroy :: proc(state:^State){if state==nil{return};state^={}}

reconcile :: proc(state:^State,world:^shared.World,width,height:f32)->string {
	if state==nil||world==nil{return "UI state or world is unavailable"}
	if !state.font.ready {if err:=init(state);err!=""{return err}}
	for &node in state.nodes[:state.node_count]{node.seen=false}
	for &entity in world.entities {
		if !entity.alive||entity.ui_layout_index<0||entity.ui_layout_index>=len(world.ui_layouts){continue}
		index:=find_node(state,entity.id)
		if index<0 {if state.node_count>=MAX_NODES{return "too many UI entities"};index=state.node_count;state.node_count+=1}
		node:=&state.nodes[index];node.entity=entity.id;node.layout_index=entity.ui_layout_index;node.text_index=entity.ui_text_index;node.parent_entity_index=find_parent_entity(world,world.ui_layouts[entity.ui_layout_index].parent);node.seen=true
	}
	for i:=0;i<state.node_count;{if state.nodes[i].seen{i+=1}else{state.node_count-=1;state.nodes[i]=state.nodes[state.node_count]}}
	state.paint_count=0
	viewport:=Rect{0,0,width,height}
	for i in 0..<state.node_count {if state.nodes[i].parent_entity_index<0 {if err:=layout_node(state,world,i,viewport,0);err!=""{return err}}}
	return ""
}

find_node :: proc(state:^State,entity:shared.Entity)->int{for node,i in state.nodes[:state.node_count]{if node.entity==entity{return i}};return -1}
find_node_by_entity_index :: proc(state:^State,index:int)->int{for node,i in state.nodes[:state.node_count]{if int(node.entity.index)==index{return i}};return -1}
find_parent_entity :: proc(world:^shared.World,name:string)->int{if name==""{return -1};for entity in world.entities{if entity.alive&&entity.name==name{return int(entity.id.index)}};return -1}

layout_node :: proc(state:^State,world:^shared.World,node_index:int,parent:Rect,depth:int)->string {
	if depth>MAX_NODES{return "UI hierarchy contains a cycle"}
	node:=&state.nodes[node_index];layout:=world.ui_layouts[node.layout_index]
	if node.parent_entity_index<0 {node.rect={layout.position.x,layout.position.y,layout.size.x,layout.size.y}}
	else {node.rect={parent.x+layout.position.x,parent.y+layout.position.y,layout.size.x,layout.size.y}}
	if layout.background.w>0 {if err:=append_paint(state,{kind=.Panel,rect=node.rect,color=layout.background,uv={0,0,0,0}});err!=""{return err}}
	if node.text_index>=0&&node.text_index<len(world.ui_texts){if err:=append_text(state,world.ui_texts[node.text_index],node.rect,layout.padding);err!=""{return err}}
	cursor:=layout.padding
	for child_index in 0..<state.node_count {
		child:=&state.nodes[child_index];if child.parent_entity_index!=int(node.entity.index){continue}
		child_layout:=world.ui_layouts[child.layout_index]
		child_parent:=node.rect
		switch layout.direction {case .Column:child_layout.position={layout.padding,cursor};cursor+=child_layout.size.y+layout.gap;case .Row:child_layout.position={cursor,layout.padding};cursor+=child_layout.size.x+layout.gap;case .Overlay:child_layout.position.x+=layout.padding;child_layout.position.y+=layout.padding}
		original:=world.ui_layouts[child.layout_index].position;world.ui_layouts[child.layout_index].position=child_layout.position
		err:=layout_node(state,world,child_index,child_parent,depth+1)
		world.ui_layouts[child.layout_index].position=original
		if err!=""{return err}
	}
	return ""
}

append_text :: proc(state:^State,text:shared.UI_Text_Component,rect:Rect,padding:f32)->string {
	scale:=text.size/FONT_BAKE_SIZE;x:=rect.x+padding;y:=rect.y+padding+text.size
	for character in text.text {
		if character=='\n'{x=rect.x+padding;y+=text.size;continue}
		code:=int(character);if code<FONT_FIRST_CHAR||code>=FONT_FIRST_CHAR+FONT_CHAR_COUNT{code=int('?')}
		bx,by:=x/scale,y/scale;q:stb.aligned_quad
		stb.GetBakedQuad(&state.font.glyphs[0],FONT_ATLAS_SIZE,FONT_ATLAS_SIZE,c.int(code-FONT_FIRST_CHAR),&bx,&by,&q,true)
		x=bx*scale;y=by*scale
		if q.x1>q.x0&&q.y1>q.y0 {if err:=append_paint(state,{kind=.Glyph,rect={q.x0*scale,q.y0*scale,(q.x1-q.x0)*scale,(q.y1-q.y0)*scale},color=text.color,uv={q.s0,q.t0,q.s1,q.t1}});err!=""{return err}}
	}
	return ""
}

append_paint :: proc(state:^State,command:Paint_Command)->(string){if state.paint_count>=MAX_PAINT_COMMANDS{return "too many UI paint commands"};state.paint[state.paint_count]=command;state.paint_count+=1;return ""}
