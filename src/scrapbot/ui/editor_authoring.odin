package ui

import component "../component"
import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:fmt"

Editor_Entity_Batch :: struct {
	indices: [dynamic]int,
	explicit_uuids: [dynamic]shared.Entity_UUID,
}

destroy_editor_entity_batch :: proc(batch: ^Editor_Entity_Batch) {
	if batch == nil {
		return
	}
	delete(batch.indices)
	delete(batch.explicit_uuids)
	batch^ = {}
}

editor_selected_entity_batch :: proc(
	state: ^State,
	world: ^shared.World,
	include_descendants: bool,
) -> Editor_Entity_Batch {
	result: Editor_Entity_Batch
	if state == nil || world == nil {
		return result
	}
	selected := make(map[shared.Entity_UUID]bool)
	defer delete(selected)
	for id in state.editor_selected_uuids {
		if entity_index, found := ecs.entity_index_by_uuid(world, id);
		   found && world.entities[entity_index].origin != .Editor {
			selected[id] = true
			append(&result.explicit_uuids, id)
		}
	}
	ordered := ecs.ordered_non_editor_entity_indices(world)
	defer delete(ordered)
	for entity_index in ordered {
		entity := world.entities[entity_index]
		if entity.model_owner != (shared.Entity_UUID{}) {
			continue
		}
		included := selected[entity.uuid]
		if !included && include_descendants {
			for root in result.explicit_uuids {
				root_index, root_found := ecs.entity_index_by_uuid(world, root)
				if root_found &&
				   entity.origin == world.entities[root_index].origin &&
				   ecs.entity_is_descendant_of_uuid(world, entity_index, root) {
					included = true
					break
				}
			}
		}
		if included {
			append(&result.indices, entity_index)
		}
	}
	return result
}

editor_duplicate_batch_order :: proc(
	world: ^shared.World,
	batch: ^Editor_Entity_Batch,
	duplicate_by_source: map[shared.Entity_UUID]shared.Entity_UUID,
	authored_only: bool = false,
) -> [dynamic]shared.Entity_UUID {
	result: [dynamic]shared.Entity_UUID
	if world == nil || batch == nil {
		return result
	}
	duplicate_ids := make(map[shared.Entity_UUID]bool)
	defer delete(duplicate_ids)
	for _, duplicate_id in duplicate_by_source {
		duplicate_ids[duplicate_id] = true
	}
	anchor: shared.Entity_UUID
	anchor_order := -1
	for source_index in batch.indices {
		if authored_only && world.entities[source_index].origin != .Scene {
			continue
		}
		if world.entities[source_index].scene_order >= anchor_order {
			anchor = world.entities[source_index].uuid
			anchor_order = world.entities[source_index].scene_order
		}
	}
	ordered := ecs.ordered_non_editor_entity_indices(world)
	defer delete(ordered)
	for entity_index in ordered {
		if authored_only && world.entities[entity_index].origin != .Scene {
			continue
		}
		id := world.entities[entity_index].uuid
		if duplicate_ids[id] {
			continue
		}
		append(&result, id)
		if id == anchor {
			for source_index in batch.indices {
				if authored_only && world.entities[source_index].origin != .Scene {
					continue
				}
				append(&result, duplicate_by_source[world.entities[source_index].uuid])
			}
		}
	}
	return result
}

editor_entity_hierarchy_depth :: proc(world: ^shared.World, entity_index: int) -> int {
	depth := 0
	cursor := entity_index
	for _ in 0 ..< len(world.entities) {
		entity := world.entities[cursor]
		if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
			break
		}
		parent := world.transforms[entity.transform_index].parent
		if parent == (shared.Entity_UUID{}) {
			break
		}
		parent_index, found := ecs.entity_index_by_uuid(world, parent)
		if !found {
			break
		}
		depth += 1
		cursor = parent_index
	}
	return depth
}

editor_sort_entity_batch_parent_first :: proc(world: ^shared.World, indices: []int) {
	for index in 1 ..< len(indices) {
		value := indices[index]
		value_depth := editor_entity_hierarchy_depth(world, value)
		cursor := index
		for cursor > 0 {
			previous := indices[cursor - 1]
			previous_depth := editor_entity_hierarchy_depth(world, previous)
			if previous_depth < value_depth ||
			   (previous_depth == value_depth &&
					   world.entities[previous].scene_order <= world.entities[value].scene_order) {
				break
			}
			indices[cursor] = previous
			cursor -= 1
		}
		indices[cursor] = value
	}
}

editor_authoring_definition_is_supported :: proc(definition: ^component.Definition) -> bool {
	return definition != nil && component.definition_is_authorable(definition^)
}

editor_authoring_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if definition == nil || !editor_authoring_definition_is_supported(definition) {
		return false
	}
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	if world.entities[entity_index].origin != .Scene {
		return false
	}
	before := capture_component_snapshot_pointer(world, entity_index, definition)
	if before == nil {
		return false
	}
	if !ecs.set_registered_component_membership(world, entity_index, definition, present) {
		destroy_component_snapshot_pointer(before)
		return false
	}
	after := capture_component_snapshot_pointer(world, entity_index, definition)
	if after == nil {
		_ = ecs.apply_registered_component_snapshot(world, entity_index, before)
		destroy_component_snapshot_pointer(before)
		return false
	}
	push_component_structural_change(state, world.entities[entity_index].uuid, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_set_registered_component :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
	present: bool,
) -> bool {
	if state == nil || world == nil || definition == nil {
		return false
	}
	if state.editor_simulation_stopped {
		return editor_authoring_set_registered_component(
			state,
			world,
			entity_index,
			definition,
			present,
		)
	}
	if !editor_authoring_definition_is_supported(definition) ||
	   !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return false
	}
	if !ecs.set_registered_component_membership(world, entity_index, definition, present) {
		return false
	}
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_component_membership_available :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if state == nil || world == nil || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	origin := world.entities[entity_index].origin
	if state.editor_simulation_stopped {
		return origin == .Scene
	}
	return origin != .Editor
}

editor_authoring_create_entity :: proc(
	state: ^State,
	world: ^shared.World,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) {
		return {}, false
	}
	snapshot := new(ecs.Entity_Snapshot)
	snapshot.origin = .Scene
	snapshot.entity.id = shared.entity_uuid_generate()
	snapshot.entity.name = ecs.clone_snapshot_string("New Entity")
	snapshot.entity.scene_order = ecs.next_scene_order_index(world)
	snapshot.entity.has_transform = true
	snapshot.entity.transform.scale = {1, 1, 1}
	entity_index, ok := ecs.apply_entity_snapshot(world, snapshot)
	if !ok {
		ecs.destroy_entity_snapshot(snapshot)
		free(snapshot)
		return {}, false
	}
	push_structural_change(state, snapshot.entity.id, nil, snapshot)
	editor_authoring_select(state, world, entity_index)
	return world.entities[entity_index].id, true
}

editor_authoring_place_model :: proc(
	state: ^State,
	world: ^shared.World,
	registry: ^resources.Registry,
	resource_id: shared.Resource_UUID,
	parent: shared.Entity_UUID = {},
	explicit_position: Maybe(shared.Vec3) = nil,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) || registry == nil {
		return {}, false
	}
	handle, found := resources.model_handle_by_uuid(registry, resource_id)
	if !found {
		return {}, false
	}
	model, alive := resources.get_model(registry, handle)
	if !alive || !model.authored {
		return {}, false
	}
	if parent != (shared.Entity_UUID{}) {
		parent_index, parent_found := ecs.entity_index_by_uuid(world, parent)
		if !parent_found || world.entities[parent_index].origin != .Scene {
			return {}, false
		}
	}

	position := shared.Vec3{0, 2, 1}
	if requested_position, has_requested_position := explicit_position.?; has_requested_position {
		position = requested_position
	} else if camera_index, _, camera_found := ecs.editor_scene_camera_entity(world);
	   camera_found {
		camera_entity := world.entities[camera_index]
		if camera_entity.transform_index >= 0 &&
		   camera_entity.transform_index < len(world.transforms) {
			camera_transform := world.transforms[camera_entity.transform_index]
			position = shared.camera_vec3_add(
				camera_transform.position,
				shared.camera_vec3_mul(shared.camera_forward(camera_transform.rotation), 5),
			)
		}
	}

	id_buffer: [36]u8
	resource := shared.resource_uuid_to_string(resource_id, id_buffer[:])
	snapshot := new(ecs.Entity_Snapshot)
	snapshot.origin = .Scene
	snapshot.entity.id = shared.entity_uuid_generate()
	snapshot.entity.name = ecs.clone_snapshot_string(model.name)
	snapshot.entity.scene_order = ecs.next_scene_order_index(world)
	snapshot.entity.has_transform = true
	snapshot.entity.transform.position = position
	snapshot.entity.transform.scale = {1, 1, 1}
	snapshot.entity.has_model = true
	snapshot.entity.model.resource = ecs.clone_snapshot_string(resource)
	snapshot.entity.model.geometry_mode = .Inherit
	entity_index, ok := ecs.apply_entity_snapshot(world, snapshot)
	if !ok {
		ecs.destroy_entity_snapshot(snapshot)
		free(snapshot)
		return {}, false
	}
	if parent != (shared.Entity_UUID{}) {
		if !ecs.set_transform_parent(world, entity_index, parent, true) {
			_ = ecs.delete_entity_by_uuid(world, snapshot.entity.id)
			ecs.destroy_entity_snapshot(snapshot)
			free(snapshot)
			return {}, false
		}
		snapshot.entity.transform = world.transforms[world.entities[entity_index].transform_index]
	}
	push_structural_change(state, snapshot.entity.id, nil, snapshot)
	editor_authoring_select(state, world, entity_index)
	return world.entities[entity_index].id, true
}

editor_request_model_placement :: proc(
	state: ^State,
	resource: shared.Resource_UUID,
	parent: shared.Entity_UUID = {},
	pointer: Maybe(shared.Vec2) = nil,
) {
	if state == nil || state.editor_model_placement_requested {
		return
	}
	request := Editor_Model_Placement_Request {
		resource = resource,
		parent = parent,
	}
	if value, ok := pointer.?; ok {
		request.pointer = value
		request.has_pointer = true
	}
	state.editor_model_placement_request = request
	state.editor_model_placement_requested = true
}

consume_model_placement_request :: proc(state: ^State) -> (Editor_Model_Placement_Request, bool) {
	if state == nil || !state.editor_model_placement_requested {
		return {}, false
	}
	request := state.editor_model_placement_request
	state.editor_model_placement_request = {}
	state.editor_model_placement_requested = false
	return request, true
}

editor_authoring_duplicate_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> (
	shared.Entity,
	bool,
) {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return {}, false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		return {}, false
	}
	after.entity.id = shared.entity_uuid_generate()
	if source_order, found := ecs.entity_scene_order_index(world, entity_index); found {
		after.entity.scene_order = source_order + 1
	}
	delete(after.entity.name)
	after.entity.name = ecs.clone_snapshot_string(
		fmt.tprintf("%s Copy", world.entities[entity_index].name),
	)
	after.origin = .Scene
	created_index, ok := ecs.apply_entity_snapshot(world, after)
	if !ok {
		destroy_snapshot_pointer(after)
		return {}, false
	}
	push_structural_change(state, after.entity.id, nil, after)
	editor_authoring_select(state, world, created_index)
	return world.entities[created_index].id, true
}

editor_duplicate_selected_entities :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || world == nil || len(state.editor_selected_uuids) == 0 {
		return false
	}
	batch := editor_selected_entity_batch(state, world, true)
	defer destroy_editor_entity_batch(&batch)
	if len(batch.indices) == 0 {
		return false
	}
	editor_sort_entity_batch_parent_first(world, batch.indices[:])

	duplicate_by_source := make(map[shared.Entity_UUID]shared.Entity_UUID)
	defer delete(duplicate_by_source)
	for entity_index in batch.indices {
		duplicate_by_source[world.entities[entity_index].uuid] = shared.entity_uuid_generate()
	}

	change := new(Editor_Structural_Batch_Change)
	transaction := Editor_Edit_Transaction {
		structural_batch = change,
	}
	succeeded := false
	defer if !succeeded {
		for item_index := len(change.items) - 1; item_index >= 0; item_index -= 1 {
			_ = ecs.delete_entity_by_uuid(world, change.items[item_index].target_uuid)
		}
		if len(change.before_order) > 0 {
			_ = apply_scene_order(world, change.before_order[:])
		}
		editor_history_destroy_transaction(&transaction)
	}
	if state.editor_simulation_stopped {
		change.before_order = capture_scene_order(world)
	}
	append(&change.before_selection, ..state.editor_selected_uuids[:])
	authored_before_order: [dynamic]shared.Entity_UUID
	defer delete(authored_before_order)
	if !state.editor_simulation_stopped {
		authored_before_order = capture_authored_scene_order(world)
	}

	for source_index in batch.indices {
		source := world.entities[source_index]
		after := capture_snapshot_pointer(world, source_index)
		if after == nil {
			return false
		}
		after.entity.id = duplicate_by_source[source.uuid]
		delete(after.entity.name)
		after.entity.name = ecs.clone_snapshot_string(fmt.tprintf("%s Copy", source.name))
		if state.editor_simulation_stopped || source.origin == .Scene {
			after.origin = .Scene
		} else {
			after.origin = .Runtime
		}
		if after.entity.has_transform {
			if duplicate_parent, found := duplicate_by_source[after.entity.transform.parent];
			   found {
				after.entity.transform.parent = duplicate_parent
			}
		}
		created_index, ok := ecs.apply_entity_snapshot(world, after)
		if !ok {
			destroy_snapshot_pointer(after)
			return false
		}
		append(
			&change.items,
			Editor_Structural_Change{target_uuid = after.entity.id, after = after},
		)
		_ = created_index
	}

	if state.editor_simulation_stopped {
		change.after_order = editor_duplicate_batch_order(world, &batch, duplicate_by_source)
		if !apply_scene_order(world, change.after_order[:]) {
			return false
		}
	}
	for source_id in batch.explicit_uuids {
		if duplicate_id, found := duplicate_by_source[source_id]; found {
			append(&change.after_selection, duplicate_id)
		}
	}
	editor_restore_selection_uuids(state, world, change.after_selection[:])
	if state.editor_simulation_stopped {
		for item in change.items {
			editor_mark_scene_uuid_dirty(state, item.target_uuid)
		}
		editor_history_push_transaction(state, transaction)
	} else {
		persisted := new(Editor_Structural_Batch_Change)
		persisted.before_order = authored_before_order
		authored_before_order = nil
		persisted.after_order = editor_duplicate_batch_order(
			world,
			&batch,
			duplicate_by_source,
			true,
		)
		for source_id in batch.explicit_uuids {
			if source_index, found := ecs.entity_index_by_uuid(world, source_id);
			   found && world.entities[source_index].origin == .Scene {
				append(&persisted.before_selection, source_id)
			}
		}
		for item_index in 0 ..< len(change.items) {
			item := &change.items[item_index]
			created_index, found := ecs.entity_index_by_uuid(world, item.target_uuid)
			if found && world.entities[created_index].origin == .Scene {
				append(&persisted.items, item^)
				item.after = nil
				append(&persisted.after_selection, item.target_uuid)
			}
		}
		if len(persisted.items) > 0 {
			if !apply_scene_order(world, persisted.after_order[:]) {
				failed := Editor_Edit_Transaction {
					structural_batch = persisted,
				}
				editor_history_destroy_transaction(&failed)
				return false
			}
			append(
				&state.editor_play_structural_changes,
				Editor_Edit_Transaction{structural_batch = persisted},
			)
			state.editor_transport_visual_valid = false
			state.editor_snapshot_valid = false
		} else {
			empty := Editor_Edit_Transaction {
				structural_batch = persisted,
			}
			editor_history_destroy_transaction(&empty)
		}
		editor_history_destroy_transaction(&transaction)
	}
	succeeded = true
	return true
}

editor_duplicate_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> (
	shared.Entity,
	bool,
) {
	if state == nil || world == nil {
		return {}, false
	}
	if state.editor_simulation_stopped {
		return editor_authoring_duplicate_entity(state, world, entity_index)
	}
	if !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return {}, false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		return {}, false
	}
	after.entity.id = shared.entity_uuid_generate()
	delete(after.entity.name)
	after.entity.name = ecs.clone_snapshot_string(
		fmt.tprintf("%s Copy", world.entities[entity_index].name),
	)
	after.origin = .Runtime
	created_index, ok := ecs.apply_entity_snapshot(world, after)
	destroy_snapshot_pointer(after)
	if !ok {
		return {}, false
	}
	editor_authoring_select(state, world, created_index)
	return world.entities[created_index].id, true
}

editor_authoring_delete_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	entity_uuid := world.entities[entity_index].uuid
	for candidate in world.entities {
		if !candidate.alive ||
		   candidate.transform_index < 0 ||
		   candidate.transform_index >= len(world.transforms) {
			continue
		}
		if world.transforms[candidate.transform_index].parent == entity_uuid {
			return false
		}
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id := before.entity.id
	if !ecs.delete_entity_by_uuid(world, id) {
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, id, before, nil)
	editor_remove_selection_uuid(state, world, id)
	return true
}

editor_delete_selected_entities :: proc(state: ^State, world: ^shared.World) -> bool {
	if state == nil || world == nil || len(state.editor_selected_uuids) == 0 {
		return false
	}
	batch := editor_selected_entity_batch(state, world, true)
	defer destroy_editor_entity_batch(&batch)
	if len(batch.indices) == 0 {
		return false
	}
	editor_sort_entity_batch_parent_first(world, batch.indices[:])
	if state.editor_simulation_stopped {
		for entity_index in batch.indices {
			if world.entities[entity_index].origin != .Scene {
				return false
			}
		}
	}

	if state.editor_simulation_stopped {
		change := new(Editor_Structural_Batch_Change)
		transaction := Editor_Edit_Transaction {
			structural_batch = change,
		}
		succeeded := false
		defer if !succeeded {
			editor_history_destroy_transaction(&transaction)
		}
		change.before_order = capture_scene_order(world)
		append(&change.before_selection, ..state.editor_selected_uuids[:])
		for entity_index in batch.indices {
			before := capture_snapshot_pointer(world, entity_index)
			if before == nil {
				return false
			}
			append(
				&change.items,
				Editor_Structural_Change{target_uuid = before.entity.id, before = before},
			)
		}
		for item_index := len(change.items) - 1; item_index >= 0; item_index -= 1 {
			if !ecs.delete_entity_by_uuid(world, change.items[item_index].target_uuid) {
				for &item in change.items {
					if item.before != nil {
						_, _ = ecs.apply_entity_snapshot(world, item.before)
					}
				}
				_ = apply_scene_order(world, change.before_order[:])
				return false
			}
		}
		editor_clear_selection(state)
		change.after_order = capture_scene_order(world)
		for item in change.items {
			editor_mark_scene_uuid_dirty(state, item.target_uuid)
		}
		editor_history_push_transaction(state, transaction)
		succeeded = true
	} else {
		ids: [dynamic]shared.Entity_UUID
		defer delete(ids)
		for entity_index in batch.indices {
			append(&ids, world.entities[entity_index].uuid)
		}
		for item_index := len(ids) - 1; item_index >= 0; item_index -= 1 {
			if !ecs.delete_entity_by_uuid(world, ids[item_index]) {
				return false
			}
		}
		editor_clear_selection(state)
	}
	return true
}

editor_delete_entity :: proc(state: ^State, world: ^shared.World, entity_index: int) -> bool {
	if state == nil || world == nil {
		return false
	}
	if state.editor_simulation_stopped {
		return editor_authoring_delete_entity(state, world, entity_index)
	}
	if !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].origin == .Editor {
		return false
	}
	id := world.entities[entity_index].uuid
	if !ecs.delete_entity_by_uuid(world, id) {
		return false
	}
	editor_remove_selection_uuid(state, world, id)
	return true
}

editor_authoring_rename_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	name: string,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   name == "" ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene || before.entity.name == name {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.set_entity_name(world, entity_index, name) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_reparent_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	parent: shared.Entity_UUID,
) -> bool {
	if state == nil || world == nil || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.origin == .Editor {
		return false
	}
	if !state.editor_simulation_stopped {
		added_transform :=
			entity.transform_index < 0 || entity.transform_index >= len(world.transforms)
		if added_transform {
			ecs.add_transform(world, entity_index, {scale = {1, 1, 1}})
		}
		if ecs.set_transform_parent(world, entity_index, parent, true) {
			return true
		}
		if added_transform {
			ecs.remove_transform(world, entity_index)
		}
		return false
	}
	if entity.origin != .Scene {
		return false
	}
	if parent != (shared.Entity_UUID{}) {
		parent_index, found := ecs.entity_index_by_uuid(world, parent)
		if !found || world.entities[parent_index].origin != .Scene {
			return false
		}
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil {
		return false
	}
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		ecs.add_transform(world, entity_index, {scale = {1, 1, 1}})
	}
	if !ecs.set_transform_parent(world, entity_index, parent, true) {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	push_structural_change(state, entity.uuid, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_entity_parent_uuid :: proc(world: ^shared.World, entity_index: int) -> shared.Entity_UUID {
	if world == nil || !ecs.entity_is_alive(world, entity_index) {
		return {}
	}
	entity := world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		return {}
	}
	return world.transforms[entity.transform_index].parent
}

capture_scene_order :: proc(world: ^shared.World) -> [dynamic]shared.Entity_UUID {
	result: [dynamic]shared.Entity_UUID
	if world == nil {
		return result
	}
	indices := ecs.ordered_non_editor_entity_indices(world)
	defer delete(indices)
	for entity_index in indices {
		append(&result, world.entities[entity_index].uuid)
	}
	return result
}

capture_authored_scene_order :: proc(world: ^shared.World) -> [dynamic]shared.Entity_UUID {
	result: [dynamic]shared.Entity_UUID
	if world == nil {
		return result
	}
	indices := ecs.ordered_non_editor_entity_indices(world)
	defer delete(indices)
	for entity_index in indices {
		if world.entities[entity_index].origin == .Scene {
			append(&result, world.entities[entity_index].uuid)
		}
	}
	return result
}

apply_scene_order :: proc(world: ^shared.World, order: []shared.Entity_UUID) -> bool {
	if world == nil {
		return false
	}
	for id, order_index in order {
		entity_index, found := ecs.entity_index_by_uuid(world, id)
		if !found || world.entities[entity_index].origin == .Editor {
			return false
		}
		world.entities[entity_index].scene_order = order_index
	}
	return true
}

editor_place_entity_adjacent :: proc(
	world: ^shared.World,
	entity_index, target_index: int,
	after: bool,
) -> bool {
	if world == nil ||
	   !ecs.entity_is_alive(world, entity_index) ||
	   !ecs.entity_is_alive(world, target_index) ||
	   entity_index == target_index {
		return false
	}
	target_parent := editor_entity_parent_uuid(world, target_index)
	current_parent := editor_entity_parent_uuid(world, entity_index)
	parent_changed := current_parent != target_parent
	if parent_changed {
		entity := world.entities[entity_index]
		added_transform :=
			entity.transform_index < 0 || entity.transform_index >= len(world.transforms)
		if added_transform {
			ecs.add_transform(world, entity_index, {scale = {1, 1, 1}})
		}
		if !ecs.set_transform_parent(world, entity_index, target_parent, true) {
			if added_transform {
				ecs.remove_transform(world, entity_index)
			}
			return false
		}
	}
	reordered := ecs.move_entity_scene_order_subtree(world, entity_index, target_index, after)
	return parent_changed || reordered
}

editor_reorder_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index, target_index: int,
	after: bool,
) -> bool {
	if state == nil ||
	   world == nil ||
	   !ecs.entity_is_alive(world, entity_index) ||
	   !ecs.entity_is_alive(world, target_index) ||
	   entity_index == target_index {
		return false
	}
	entity := world.entities[entity_index]
	target := world.entities[target_index]
	if entity.origin == .Editor || target.origin == .Editor {
		return false
	}
	if !state.editor_simulation_stopped {
		if !editor_place_entity_adjacent(world, entity_index, target_index, after) {
			return false
		}
		editor_authoring_select(state, world, entity_index)
		return true
	}
	if entity.origin != .Scene || target.origin != .Scene {
		return false
	}
	target_parent := editor_entity_parent_uuid(world, target_index)
	if target_parent != (shared.Entity_UUID{}) {
		parent_index, found := ecs.entity_index_by_uuid(world, target_parent)
		if !found || world.entities[parent_index].origin != .Scene {
			return false
		}
	}
	before_order := capture_scene_order(world)
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil {
		delete(before_order)
		return false
	}
	if !editor_place_entity_adjacent(world, entity_index, target_index, after) {
		delete(before_order)
		destroy_snapshot_pointer(before)
		return false
	}
	after_order := capture_scene_order(world)
	after_snapshot := capture_snapshot_pointer(world, entity_index)
	if after_snapshot == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		_ = apply_scene_order(world, before_order[:])
		delete(before_order)
		delete(after_order)
		destroy_snapshot_pointer(before)
		return false
	}
	change := new(Editor_Structural_Change)
	change.target_uuid = entity.uuid
	change.before = before
	change.after = after_snapshot
	change.before_order = before_order
	change.after_order = after_order
	editor_history_push_transaction(state, {structural = change})
	editor_mark_scene_uuid_dirty(state, entity.uuid)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_set_material_resource :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	resource_id: shared.Resource_UUID,
) -> bool {
	if !editor_authoring_available(state, world) ||
	   state.resource_registry == nil ||
	   !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	if _, found := resources.material_by_uuid(state.resource_registry, resource_id); !found {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Scene {
		destroy_snapshot_pointer(before)
		return false
	}
	id_buffer: [36]u8
	value := shared.resource_uuid_to_string(resource_id, id_buffer[:])
	if before.entity.material_resource == value {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		destroy_snapshot_pointer(before)
		return false
	}
	delete(after.entity.material_resource)
	after.entity.material_resource = ecs.clone_snapshot_string(value)
	after.entity.has_material = true
	if _, ok := ecs.apply_entity_snapshot(world, after); !ok {
		destroy_snapshot_pointer(before)
		destroy_snapshot_pointer(after)
		return false
	}
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

resolve_snapshot_resource_names :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
	snapshot: ^ecs.Entity_Snapshot,
) {
	if state == nil || state.resource_registry == nil || snapshot == nil {
		return
	}
	entity := world.entities[entity_index]
	if snapshot.entity.geometry.resource == "" &&
	   entity.geometry_index >= 0 &&
	   entity.geometry_index < len(world.geometries) {
		handle := world.geometries[entity.geometry_index].handle
		if int(handle.index) < len(state.resource_registry.geometries) {
			resource := state.resource_registry.geometries[handle.index]
			if resource.alive && resource.generation == handle.generation {
				snapshot.entity.has_geometry = true
				snapshot.entity.geometry.resource = ecs.clone_snapshot_string(resource.name)
			}
		}
	}
	if snapshot.entity.material_resource == "" &&
	   entity.material_index >= 0 &&
	   entity.material_index < len(world.materials) {
		handle := world.materials[entity.material_index].handle
		if int(handle.index) < len(state.resource_registry.materials) {
			resource := state.resource_registry.materials[handle.index]
			if resource.alive && resource.authored && resource.generation == handle.generation {
				id_buffer: [36]u8
				snapshot.entity.has_material = true
				snapshot.entity.material_resource = ecs.clone_snapshot_string(
					shared.resource_uuid_to_string(resource.id, id_buffer[:]),
				)
			}
		}
	}
}

editor_authoring_promote_entity :: proc(
	state: ^State,
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if !editor_authoring_available(state, world) || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	before := capture_snapshot_pointer(world, entity_index)
	if before == nil || before.origin != .Runtime {
		destroy_snapshot_pointer(before)
		return false
	}
	if !ecs.promote_entity_to_scene(world, entity_index) {
		destroy_snapshot_pointer(before)
		return false
	}
	after := capture_snapshot_pointer(world, entity_index)
	if after == nil {
		_, _ = ecs.apply_entity_snapshot(world, before)
		destroy_snapshot_pointer(before)
		return false
	}
	resolve_snapshot_resource_names(state, world, entity_index, after)
	_, _ = ecs.apply_entity_snapshot(world, after)
	push_structural_change(state, before.entity.id, before, after)
	editor_authoring_select(state, world, entity_index)
	return true
}

editor_authoring_available :: proc(state: ^State, world: ^shared.World) -> bool {
	return state != nil && world != nil && state.editor_simulation_stopped
}

capture_snapshot_pointer :: proc(world: ^shared.World, entity_index: int) -> ^ecs.Entity_Snapshot {
	snapshot, ok := ecs.capture_entity_snapshot(world, entity_index)
	if !ok {
		return nil
	}
	result := new(ecs.Entity_Snapshot)
	result^ = snapshot
	return result
}

destroy_snapshot_pointer :: proc(snapshot: ^ecs.Entity_Snapshot) {
	if snapshot == nil {
		return
	}
	ecs.destroy_entity_snapshot(snapshot)
	free(snapshot)
}

capture_component_snapshot_pointer :: proc(
	world: ^shared.World,
	entity_index: int,
	definition: ^component.Definition,
) -> ^ecs.Registered_Component_Snapshot {
	snapshot, ok := ecs.capture_registered_component_snapshot(world, entity_index, definition)
	if !ok {
		return nil
	}
	result := new(ecs.Registered_Component_Snapshot)
	result^ = snapshot
	return result
}

destroy_component_snapshot_pointer :: proc(snapshot: ^ecs.Registered_Component_Snapshot) {
	if snapshot == nil {
		return
	}
	ecs.destroy_registered_component_snapshot(snapshot)
	free(snapshot)
}

push_structural_change :: proc(
	state: ^State,
	id: shared.Entity_UUID,
	before, after: ^ecs.Entity_Snapshot,
) {
	change := new(Editor_Structural_Change)
	change.target_uuid = id
	change.before = before
	change.after = after
	editor_history_push_transaction(state, {structural = change})
	editor_mark_scene_uuid_dirty(state, id)
}

push_component_structural_change :: proc(
	state: ^State,
	id: shared.Entity_UUID,
	before, after: ^ecs.Registered_Component_Snapshot,
) {
	change := new(Editor_Component_Structural_Change)
	change.target_uuid = id
	change.before = before
	change.after = after
	editor_history_push_transaction(state, {component_structural = change})
	editor_mark_scene_uuid_dirty(state, id)
}

editor_authoring_select :: proc(state: ^State, world: ^shared.World, entity_index: int) {
	_ = editor_select_entity(state, world, world.entities[entity_index].id, 0)
}
