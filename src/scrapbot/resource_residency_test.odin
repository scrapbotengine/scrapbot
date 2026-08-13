#+feature dynamic-literals
package scrapbot

import resources "./resources"
import shared "./shared"
import "core:testing"

residency_test_id :: proc(value: string) -> shared.Resource_UUID {
	id, _ := shared.resource_uuid_parse(value)
	return id
}

register_residency_test_texture :: proc(
	registry: ^resources.Registry,
	id: shared.Resource_UUID,
	name: string,
) -> shared.Texture_Handle {
	pixels := []u8{1, 2, 3, 4}
	handle, _ := resources.register_project_texture(
		registry,
		id,
		name,
		"resident.resource.toml",
		"resident.png",
		{pixels = pixels, width = 1, height = 1, mip_count = 1},
	)
	return handle
}

@(test)
test_retiring_project_texture_releases_payload_and_reuses_slot :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	id := residency_test_id("c3000000-0000-4000-8000-000000000001")
	first := register_residency_test_texture(&registry, id, "resident")
	testing.expect(t, resources.project_resource_is_resident(&registry, id))
	testing.expect(t, resources.retire_project_resource(&registry, id))
	testing.expect(t, !resources.project_resource_is_resident(&registry, id))
	testing.expect_value(t, len(registry.textures), 1)
	testing.expect_value(t, len(registry.textures[0].desc.pixels), 0)
	_, old_alive := resources.get_texture(&registry, first)
	testing.expect(t, !old_alive)

	second := register_residency_test_texture(&registry, id, "resident")
	testing.expect(t, resources.project_resource_is_resident(&registry, id))
	testing.expect_value(t, len(registry.textures), 1)
	testing.expect(t, second.generation != first.generation)
	_, new_alive := resources.get_texture(&registry, second)
	testing.expect(t, new_alive)
}

@(test)
test_residency_activation_keeps_shared_resources_and_delays_eviction :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	a := residency_test_id("c4000000-0000-4000-8000-000000000001")
	b := residency_test_id("c4000000-0000-4000-8000-000000000002")
	shared_id := residency_test_id("c4000000-0000-4000-8000-000000000003")
	_ = register_residency_test_texture(&registry, a, "a")
	_ = register_residency_test_texture(&registry, b, "b")
	_ = register_residency_test_texture(&registry, shared_id, "shared")
	residency := Resource_Residency {
		active = {a, shared_id},
		staging = {b, shared_id},
	}
	defer destroy_resource_residency(&residency)
	resource_residency_activate_staging(&residency)
	testing.expect_value(t, len(residency.evictions), 1)
	for _ in 0 ..< RESOURCE_EVICTION_GRACE_FRAMES - 1 {
		resource_residency_advance(&residency, &registry)
		testing.expect(t, resources.project_resource_is_resident(&registry, a))
	}
	resource_residency_advance(&residency, &registry)
	testing.expect(t, !resources.project_resource_is_resident(&registry, a))
	testing.expect(t, resources.project_resource_is_resident(&registry, b))
	testing.expect(t, resources.project_resource_is_resident(&registry, shared_id))
}

@(test)
test_residency_rapid_return_cancels_pending_eviction :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	a := residency_test_id("c5000000-0000-4000-8000-000000000001")
	b := residency_test_id("c5000000-0000-4000-8000-000000000002")
	_ = register_residency_test_texture(&registry, a, "a")
	_ = register_residency_test_texture(&registry, b, "b")
	residency := Resource_Residency {
		active = {a},
		staging = {b},
	}
	defer destroy_resource_residency(&residency)
	resource_residency_activate_staging(&residency)
	residency.staging = make([dynamic]shared.Resource_UUID)
	append(&residency.staging, a)
	resource_residency_activate_staging(&residency)
	for _ in 0 ..< RESOURCE_EVICTION_GRACE_FRAMES {
		resource_residency_advance(&residency, &registry)
	}
	testing.expect(t, resources.project_resource_is_resident(&registry, a))
	testing.expect(t, !resources.project_resource_is_resident(&registry, b))
}

@(test)
test_staging_reference_cancels_eviction_before_admission :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	a := residency_test_id("c6000000-0000-4000-8000-000000000001")
	b := residency_test_id("c6000000-0000-4000-8000-000000000002")
	_ = register_residency_test_texture(&registry, a, "a")
	_ = register_residency_test_texture(&registry, b, "b")
	residency := Resource_Residency {
		active = {a},
		staging = {b},
	}
	defer destroy_resource_residency(&residency)
	resource_residency_activate_staging(&residency)
	for _ in 0 ..< RESOURCE_EVICTION_GRACE_FRAMES - 1 {
		resource_residency_advance(&residency, &registry)
	}
	delete(residency.staging)
	residency.staging = make([dynamic]shared.Resource_UUID)
	append(&residency.staging, a)
	cancel_resource_eviction(&residency, a)
	resource_residency_advance(&residency, &registry)
	testing.expect(t, resources.project_resource_is_resident(&registry, a))
}
