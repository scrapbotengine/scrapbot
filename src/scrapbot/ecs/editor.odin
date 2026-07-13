package ecs

import shared "../shared"

reconcile_editor_transform_gizmo :: proc(world:^World,selected:shared.Entity,enabled:bool) {
	if world==nil{return};target:=INVALID_COMPONENT_INDEX
	if enabled {index:=int(selected.index);if index>=0&&index<len(world.entities)&&world.entities[index].alive&&world.entities[index].id.generation==selected.generation&&world.entities[index].transform_index>=0{target=index}}
	for &entity,index in world.entities {
		if entity.editor_transform_gizmo_index<0{continue}
		if entity.editor_transform_gizmo_index>=len(world.editor_transform_gizmos)||world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index!=index {entity.editor_transform_gizmo_index=INVALID_COMPONENT_INDEX;continue}
		if index!=target {world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index=INVALID_COMPONENT_INDEX;entity.editor_transform_gizmo_index=INVALID_COMPONENT_INDEX}
	}
	if target<0{return}
	target_component_index:=world.entities[target].editor_transform_gizmo_index
	if target_component_index>=0&&target_component_index<len(world.editor_transform_gizmos)&&world.editor_transform_gizmos[target_component_index].entity_index==target{return}
	component_index:=INVALID_COMPONENT_INDEX
	for component,index in world.editor_transform_gizmos{if component.entity_index<0{component_index=index;break}}
	component:=shared.Editor_Transform_Gizmo_Component{entity_index=target,mode=.World_Translate}
	if component_index<0{component_index=len(world.editor_transform_gizmos);append(&world.editor_transform_gizmos,component)}else{world.editor_transform_gizmos[component_index]=component}
	world.entities[target].editor_transform_gizmo_index=component_index
}

editor_transform_gizmo_entity :: proc(world:^World)->(int,^shared.Editor_Transform_Gizmo_Component,bool) {
	if world==nil{return -1,nil,false}
	for &component,index in world.editor_transform_gizmos {if component.entity_index>=0&&component.entity_index<len(world.entities)&&world.entities[component.entity_index].alive&&world.entities[component.entity_index].editor_transform_gizmo_index==index{return component.entity_index,&component,true}}
	return -1,nil,false
}
