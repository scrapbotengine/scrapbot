package ecs

import shared "../shared"
import "core:math"

MAX_DELTA_TIME :: f32(0.25)
SMOOTH_DELTA_HALF_LIFE :: f32(0.1)

advance_time :: proc(time: ^shared.Time_Resource, unscaled_delta_time: f32) {
	if time == nil { return }
	delta := max(unscaled_delta_time, 0)
	if time.frame_index == 0 {
		time.smooth_delta_time = delta
	} else {
		alpha := 1 - math.exp(-delta * f32(math.LN2) / SMOOTH_DELTA_HALF_LIFE)
		time.smooth_delta_time += (delta - time.smooth_delta_time) * alpha
	}
	time.delta_time = delta
	time.elapsed_time += f64(delta)
	time.frame_index += 1
}

time_component_number :: proc(component: ^shared.Custom_Component, name: string) -> ^f32 {
	if component == nil {
		return nil
	}
	for &field in component.number_fields {
		if field.name == name {
			return &field.value
		}
	}
	return nil
}

ensure_time_component_number :: proc(
	world: ^shared.World,
	component: ^shared.Custom_Component,
	name: string,
	default_value: f32 = 0,
) -> ^f32 {
	if value := time_component_number(component, name); value != nil {
		return value
	}
	append(
		&component.number_fields,
		shared.Named_Number{name = clone_world_string(world, name), value = default_value},
	)
	return &component.number_fields[len(component.number_fields) - 1].value
}

time_resource_from_component :: proc(
	world: ^shared.World,
	component: ^shared.Custom_Component,
) -> shared.Time_Resource {
	return {
		delta_time = ensure_time_component_number(world, component, "delta_time")^,
		smooth_delta_time = ensure_time_component_number(world, component, "smooth_delta_time")^,
		elapsed_time = f64(ensure_time_component_number(world, component, "elapsed_time")^),
		frame_index = u64(max(ensure_time_component_number(world, component, "frame_index")^, 0)),
	}
}

write_time_resource_to_component :: proc(
	world: ^shared.World,
	component: ^shared.Custom_Component,
	time: shared.Time_Resource,
) {
	ensure_time_component_number(world, component, "delta_time")^ = time.delta_time
	ensure_time_component_number(world, component, "smooth_delta_time")^ = time.smooth_delta_time
	ensure_time_component_number(world, component, "elapsed_time")^ = f32(time.elapsed_time)
	ensure_time_component_number(world, component, "frame_index")^ = f32(time.frame_index)
}

advance_project_time :: proc(world: ^shared.World, unscaled_delta_time: f32) {
	if world == nil {
		return
	}
	storage := find_custom_component_storage(world, shared.INVALID_COMPONENT_ID, "scrapbot.clock")
	if storage == nil || len(storage.active_component_indices) == 0 {
		world.default_clock_uuid = {}
		advance_time(&world.time, unscaled_delta_time)
		return
	}

	default_component_index := -1
	default_scene_order := 0
	for component_index in storage.active_component_indices {
		component := &storage.components[component_index]
		if component.entity_index < 0 || component.entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[component.entity_index]
		if !entity.alive || entity.origin == .Editor {
			continue
		}
		if default_component_index < 0 || entity.scene_order < default_scene_order {
			default_scene_order = entity.scene_order
			default_component_index = component_index
		}
	}
	if default_component_index < 0 {
		world.default_clock_uuid = {}
		advance_time(&world.time, unscaled_delta_time)
		return
	}
	default_component := &storage.components[default_component_index]
	default_entity := world.entities[default_component.entity_index]
	if world.default_clock_uuid != default_entity.uuid {
		world.time = time_resource_from_component(world, default_component)
		world.default_clock_uuid = default_entity.uuid
	}

	for component_index in storage.active_component_indices {
		component := &storage.components[component_index]
		if component.entity_index < 0 || component.entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[component.entity_index]
		if !entity.alive || entity.origin == .Editor {
			continue
		}
		speed_value := ensure_time_component_number(world, component, "speed", 1)
		speed := max(speed_value^, 0)
		speed_value^ = speed
		if component_index == default_component_index {
			advance_time(&world.time, max(unscaled_delta_time, 0) * speed)
			write_time_resource_to_component(world, component, world.time)
			continue
		}

		local_time := time_resource_from_component(world, component)
		advance_time(&local_time, max(unscaled_delta_time, 0) * speed)
		write_time_resource_to_component(world, component, local_time)
	}
}
