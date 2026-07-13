package ui

import ecs "../ecs"
import shared "../shared"
import "core:math"
import "core:testing"

@(test)
test_embedded_mtsdf_font_has_expected_atlas_and_proportional_metrics :: proc(t:^testing.T) {
	testing.expect(t,len(FONT_ATLAS_DATA)==FONT_ATLAS_SIZE*FONT_ATLAS_SIZE*4)
	i:=FONT_GLYPHS[int('I')-FONT_FIRST_CHAR]
	w:=FONT_GLYPHS[int('W')-FONT_FIRST_CHAR]
	testing.expect(t,i.advance>0)
	testing.expect(t,w.advance>i.advance)
	testing.expect(t,w.uv.z>w.uv.x&&w.uv.w>w.uv.y)
}

@(test)
test_reconcile_tracks_ui_entity_appearance_and_disappearance :: proc(t:^testing.T) {
	scene:=shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities,
		shared.Scene_Entity{name="Root",has_ui_layout=true,ui_layout={size={300,160},padding={10,10,10,10},background={0.1,0.2,0.3,1}},has_ui_vstack=true,ui_vstack={gap=0}},
		shared.Scene_Entity{name="Label",has_ui_layout=true,ui_layout={parent="Root",size={200,40}},has_ui_text=true,ui_text={text="HELLO",color={1,1,1,1},size=16}},
	)
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	testing.expect(t,state.node_count==2)
	testing.expect(t,state.paint_count>2)
	world.entities[1].alive=false
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	testing.expect(t,state.node_count==1)
	testing.expect(t,state.paint_count==1)
}

@(test)
test_column_layout_places_children_in_order :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,
		shared.Scene_Entity{name="Root",has_ui_layout=true,ui_layout={size={300,200},padding={10,10,10,10}},has_ui_vstack=true,ui_vstack={gap=5}},
		shared.Scene_Entity{name="A",has_ui_layout=true,ui_layout={parent="Root",size={100,20}}},
		shared.Scene_Entity{name="B",has_ui_layout=true,ui_layout={parent="Root",size={100,30}}},
	)
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	a:=find_node_by_entity_index(state,1);b:=find_node_by_entity_index(state,2)
	testing.expect(t,a>=0&&b>=0)
	if a>=0&&b>=0 {testing.expect(t,state.nodes[a].rect.y==10);testing.expect(t,state.nodes[b].rect.y==35)}
}

@(test)
test_box_model_applies_margins_padding_and_rounded_button_paint :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,
		shared.Scene_Entity{name="Root",has_ui_layout=true,ui_layout={position={20,30},size={300,120},padding={10,10,10,10}},has_ui_hstack=true,ui_hstack={gap=6}},
		shared.Scene_Entity{name="Button",has_ui_layout=true,ui_layout={parent="Root",size={100,40},margin={2,3,4,5},padding={8,8,8,8},background={0.2,0.4,0.8,1},corner_radius=12},has_ui_button=true,ui_button={text="GO",color={1,1,1,1},size=16}},
	)
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	button:=find_node_by_entity_index(state,1);testing.expect(t,button>=0)
	if button>=0 {testing.expect(t,state.nodes[button].rect.x==35);testing.expect(t,state.nodes[button].rect.y==42)}
	testing.expect(t,state.paint_count>=3)
	if state.paint_count>0 {testing.expect(t,state.paint[0].corner_radius==12)}
}

@(test)
test_pointer_states_belong_to_elements_and_buttons_consume_them :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,
		shared.Scene_Entity{name="Root",has_ui_layout=true,ui_layout={size={300,120}}},
		shared.Scene_Entity{name="Button",has_ui_layout=true,ui_layout={parent="Root",position={20,20},size={100,40},background={0.1,0.2,0.3,1}},has_ui_button=true,ui_button={text="GO",color={1,1,1,1},size=16,hover_background={0.2,0.4,0.6,1},active_background={0.05,0.1,0.15,1}}},
	)
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	button:=1

	testing.expect(t,reconcile(state,&world,1280,720,{position={30,30},available=true})=="")
	testing.expect(t,state.nodes[button].hovered&&!state.nodes[button].active)
	testing.expect(t,state.paint[0].color==shared.Vec4{0.2,0.4,0.6,1})
	ink_min_x,ink_min_y,ink_max_x,ink_max_y:=f32(10000),f32(10000),f32(-10000),f32(-10000)
	for command in state.paint[:state.paint_count] {if command.kind==.Glyph {ink_min_x=min(ink_min_x,command.rect.x);ink_min_y=min(ink_min_y,command.rect.y);ink_max_x=max(ink_max_x,command.rect.x+command.rect.width);ink_max_y=max(ink_max_y,command.rect.y+command.rect.height)}}
	delta_x:=(ink_min_x+ink_max_x)*0.5-70;if delta_x<0{delta_x=-delta_x}
	delta_y:=(ink_min_y+ink_max_y)*0.5-40;if delta_y<0{delta_y=-delta_y}
	testing.expect(t,delta_x<0.001&&delta_y<0.001)

	testing.expect(t,reconcile(state,&world,1280,720,{position={30,30},primary_down=true,available=true})=="")
	testing.expect(t,state.nodes[button].hovered&&state.nodes[button].active)
	testing.expect(t,state.paint[0].color==shared.Vec4{0.05,0.1,0.15,1})

	testing.expect(t,reconcile(state,&world,1280,720,{position={500,500},primary_down=true,available=true})=="")
	testing.expect(t,!state.nodes[button].hovered&&state.nodes[button].active)

	testing.expect(t,reconcile(state,&world,1280,720,{position={500,500},available=true})=="")
	testing.expect(t,!state.nodes[button].hovered&&!state.nodes[button].active)
}

@(test)
test_scroll_area_clips_descendants_and_smoothly_approaches_wheel_target :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,
		shared.Scene_Entity{name="Scroll",has_ui_layout=true,ui_layout={position={20,20},size={200,100},padding={10,10,10,10},background={0.08,0.09,0.11,1}},has_ui_scroll_area=true,ui_scroll_area={scroll_speed=60,smoothness=12}},
		shared.Scene_Entity{name="Pane",has_ui_layout=true,ui_layout={parent="Scroll",size={180,300},background={0.12,0.13,0.15,1}}},
		shared.Scene_Entity{name="Button",has_ui_layout=true,ui_layout={parent="Pane",position={10,75},size={150,40},background={0.2,0.3,0.4,1}},has_ui_button=true,ui_button={text="CLIPPED",color={1,1,1,1},size=12}},
	)
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)

	// The button occupies this point geometrically, but the scroll viewport clips it.
	testing.expect(t,reconcile(state,&world,1280,720,{position={40,115},available=true})=="")
	scroll:=find_node_by_entity_index(state,0);pane:=find_node_by_entity_index(state,1);button:=find_node_by_entity_index(state,2)
	testing.expect(t,scroll>=0&&pane>=0&&button>=0)
	if scroll>=0&&pane>=0&&button>=0 {
		testing.expect(t,state.nodes[scroll].scroll_max==220)
		testing.expect(t,state.nodes[pane].clip==Rect{30,30,180,80})
		testing.expect(t,!state.nodes[button].hovered)
	}
	clipped_paint:=false
	expected_clip:=Rect{30,30,180,80}
	for command in state.paint[:state.paint_count] {if command.has_clip&&command.clip==expected_clip{clipped_paint=true;break}}
	testing.expect(t,clipped_paint)

	initial_pane_y:=state.nodes[pane].rect.y
	testing.expect(t,reconcile(state,&world,1280,720,{position={40,40},wheel_y=-1,available=true},0,0,1.0/60.0)=="")
	testing.expect(t,state.nodes[scroll].scroll_target==60)
	testing.expect(t,state.nodes[scroll].scroll_offset>0&&state.nodes[scroll].scroll_offset<60)
	testing.expect(t,state.nodes[pane].rect.y<initial_pane_y)
	for _ in 0..<60 {testing.expect(t,reconcile(state,&world,1280,720,{},0,0,1.0/60.0)=="")}
	testing.expect(t,math.abs(state.nodes[scroll].scroll_offset-60)<0.02)

	// A later entity occupying a released retained-node slot starts at the top.
	for &entity in world.entities {entity.alive=false}
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	for &entity in world.entities {entity.alive=true}
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	scroll=find_node_by_entity_index(state,0)
	testing.expect(t,scroll>=0&&state.nodes[scroll].scroll_offset==0&&state.nodes[scroll].scroll_target==0)
}

@(test)
test_editor_shell_reserves_live_viewport_and_appends_engine_chrome :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,shared.Scene_Entity{name="Game UI",has_ui_layout=true,ui_layout={size={100,40},background={0.2,0.3,0.4,1}}})
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	state.editor_visible=true
	testing.expect(t,reconcile(state,&world,1280,720)=="")
	viewport:=editor_viewport(state,1280,720)
	testing.expect(t,viewport==Rect{244,52,732,636})
	testing.expect(t,state.editor_paint_start==1)
	testing.expect(t,state.paint_count>state.editor_paint_start)
	pointer:=project_pointer_input(state,{position={viewport.x+viewport.width*0.5,viewport.y+viewport.height*0.5},available=true},1280,720)
	testing.expect(t,pointer.available&&pointer.position==shared.Vec2{640,360})
	testing.expect(t,!project_pointer_input(state,{position={20,100},available=true},1280,720).available)

	// Editor chrome and the project viewport follow the full available drawable.
	testing.expect(t,reconcile(state,&world,1280,720,{},2048,1096)=="")
	viewport=editor_viewport(state,2048,1096)
	testing.expect(t,viewport==Rect{244,52,1500,1012})
	testing.expect(t,state.paint[state.editor_paint_start].rect.width==2048)
	pointer=project_pointer_input(state,{position={viewport.x+viewport.width*0.5,viewport.y+viewport.height*0.5},available=true},1280,720,2048,1096)
	testing.expect(t,pointer.available&&pointer.position==shared.Vec2{640,360})
	testing.expect(t,reconcile(state,&world,1280,720,{position={viewport.x+100,viewport.y+100},primary_down=true,available=true},2048,1096)=="")
	testing.expect(t,state.editor_pick_requested)
	testing.expect(t,state.editor_pick_position==shared.Vec2{viewport.x+100,viewport.y+100})

	// Native-density windows keep the same logical chrome size while painting at 2x resolution.
	state.editor_pixel_density=2
	testing.expect(t,reconcile(state,&world,1280,720,{},2560,1440)=="")
	viewport=editor_viewport(state,2560,1440)
	testing.expect(t,viewport==Rect{488,104,1464,1272})
	testing.expect(t,state.paint[state.editor_paint_start].rect==Rect{0,0,2560,96})
}

@(test)
test_resized_play_view_maps_pointer_back_to_project_canvas :: proc(t:^testing.T) {
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	viewport:=editor_viewport(state,2048,1096)
	testing.expect(t,viewport==Rect{0,0,2048,1096})
	pointer:=project_pointer_input(state,{position={1024,548},available=true},1280,720,2048,1096)
	testing.expect(t,pointer.available&&pointer.position==shared.Vec2{640,360})
}

@(test)
test_editor_browser_scrolls_selects_runtime_entities_and_clears_stale_selection :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	for i in 0..<25 {append(&scene.entities,shared.Scene_Entity{name="Browser Entity"})}
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	world.entities[24].origin=.Runtime
	world.entities[24].transform_index=len(world.transforms);append_soa(&world.transforms,shared.Transform_Component{})
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state);state.editor_visible=true

	// A wheel step settles at a pixel offset between rows instead of snapping to one.
	testing.expect(t,reconcile(state,&world,1280,720,{position={100,150},wheel_y=-1,available=true},1280,300)=="")
	testing.expect(t,state.editor_browser_scroll_target==48)
	testing.expect(t,int(state.editor_browser_scroll_target)%int(EDITOR_ENTITY_ROW_HEIGHT)!=0)
	for _ in 0..<60 {testing.expect(t,reconcile(state,&world,1280,720,{},1280,300)=="")}
	testing.expect(t,math.abs(state.editor_browser_scroll-48)<0.02)

	// A short window can continue smoothly to the runtime tail.
	testing.expect(t,reconcile(state,&world,1280,720,{position={100,150},wheel_y=-20,available=true},1280,300)=="")
	testing.expect(t,state.editor_browser_scroll_target==536)
	testing.expect(t,state.editor_browser_scroll>0&&state.editor_browser_scroll<state.editor_browser_scroll_target)
	for _ in 0..<60 {testing.expect(t,reconcile(state,&world,1280,720,{},1280,300)=="")}
	testing.expect(t,math.abs(state.editor_browser_scroll-state.editor_browser_scroll_target)<0.02)
	browser_clip_found:=false
	browser:=editor_browser_rect(1280,300)
	for command in state.paint[:state.paint_count] {if command.has_clip&&command.clip==browser{browser_clip_found=true;break}}
	testing.expect(t,browser_clip_found)
	testing.expect(t,reconcile(state,&world,1280,720,{position={100,245},primary_down=true,available=true},1280,300)=="")
	testing.expect(t,state.editor_has_selection)
	testing.expect(t,state.editor_selected_entity==world.entities[24].id)
	testing.expect(t,world.entities[24].origin==.Runtime)
	testing.expect(t,entity_component_count(&world,24)==1)

	world.entities[24].alive=false
	testing.expect(t,reconcile(state,&world,1280,720,{},1280,300)=="")
	testing.expect(t,!state.editor_has_selection)
}

@(test)
test_editor_scene_camera_is_inspectable_as_an_editor_entity :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	entity_index, _, ok := ecs.reconcile_editor_scene_camera(&world, true)
	testing.expect(t, ok)
	testing.expect(t, world.entities[entity_index].origin == .Editor)
	testing.expect(t, entity_component_count(&world, entity_index) == 3)

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[entity_index].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.editor_inspector_content_height > 180)
}

@(test)
test_component_inspector_formats_live_fields_and_scrolls_independently :: proc(t:^testing.T) {
	scene:=shared.Scene{};defer delete(scene.entities)
	append(&scene.entities,shared.Scene_Entity{
		name="Inspectable",has_transform=true,transform={position={1,2.5,-3},rotation={0.1,0.2,0.3},scale={1,1,1}},
		has_camera=true,camera={fov=60,near=0.1,far=500},
		has_ui_layout=true,ui_layout={parent="Root",position={20,30},size={300,120},padding={4,5,6,7},corner_radius=8},
		has_ui_button=true,ui_button={text="Launch",size=14,color={1,1,1,1},hover_background={0.2,0.3,0.4,1}},
	})
	world:=ecs.build_world(&scene);defer ecs.destroy_world(&world)
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state);state.editor_visible=true
	testing.expect(t,reconcile(state,&world,1280,720,{position={100,105},primary_down=true,available=true},1280,300)=="")
	testing.expect(t,state.editor_has_selection)
	testing.expect(t,state.editor_inspector_content_height>200)
	testing.expect(t,format_vec3({1,2.5,-3})=="(1.00, 2.50, -3.00)")
	testing.expect(t,reconcile(state,&world,1280,720,{position={1100,220},wheel_y=-4,available=true},1280,300)=="")
	testing.expect(t,state.editor_inspector_scroll>0)
	testing.expect(t,state.editor_inspector_scroll<state.editor_inspector_scroll_target)
	testing.expect(t,state.editor_browser_scroll==0)
}

@(test)
test_editor_gizmo_appends_three_axis_lines_and_handles :: proc(t:^testing.T) {
	state:=new(State);defer free(state);testing.expect(t,init(state)=="");defer destroy(state)
	state.editor_gizmo_visible=true;state.editor_gizmo_origin={100,100};state.editor_gizmo_endpoints={{180,100},{100,20},{145,145}};state.editor_gizmo_hovered_axis=.Y
	testing.expect(t,append_editor_gizmo(state)=="")
	line_count:=0;for command in state.paint[:state.paint_count]{if command.kind==.Line{line_count+=1}}
	testing.expect(t,line_count==3)
	testing.expect(t,state.paint[3].line_thickness==8)
}
