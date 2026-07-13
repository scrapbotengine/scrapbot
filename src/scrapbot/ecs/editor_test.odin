package ecs

import "core:testing"
import shared "../shared"

@(test)
test_editor_transform_gizmo_component_follows_selection :: proc(t:^testing.T) {
	world:World;defer delete(world.entities);defer delete(world.transforms);defer delete(world.editor_transform_gizmos)
	append_soa(&world.transforms,shared.Transform_Component{},shared.Transform_Component{})
	append(&world.entities,
		shared.World_Entity{id={index=0,generation=1},alive=true,transform_index=0,editor_transform_gizmo_index=-1},
		shared.World_Entity{id={index=1,generation=1},alive=true,transform_index=1,editor_transform_gizmo_index=-1},
	)

	reconcile_editor_transform_gizmo(&world,{index=0,generation=1},true)
	entity_index,gizmo,ok:=editor_transform_gizmo_entity(&world)
	testing.expect(t,ok&&entity_index==0&&gizmo.mode==.World_Translate)
	testing.expect(t,world.entities[0].editor_transform_gizmo_index>=0)

	reconcile_editor_transform_gizmo(&world,{index=1,generation=1},true)
	entity_index,_,ok=editor_transform_gizmo_entity(&world)
	testing.expect(t,ok&&entity_index==1)
	testing.expect(t,world.entities[0].editor_transform_gizmo_index==-1)
	testing.expect(t,world.entities[1].editor_transform_gizmo_index>=0)

	reconcile_editor_transform_gizmo(&world,{},false)
	_,_,ok=editor_transform_gizmo_entity(&world)
	testing.expect(t,!ok)
	testing.expect(t,world.entities[1].editor_transform_gizmo_index==-1)
}
