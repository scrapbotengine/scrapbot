package scrapbot

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_check_project_refreshes_luau_types_from_script_registry :: proc(t: ^testing.T) {
	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	types_path := join_check_project_path(t, root, DEFAULT_LUAU_TYPES)
	defer delete(types_path)
	write_err := os.write_entire_file(types_path, "-- stale\n")
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expectf(t, check_err == "", "check_project failed: %s", check_err)

	types_bytes, read_err := os.read_entire_file(types_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	types_text := string(types_bytes)
	testing.expect(t, strings.contains(types_text, "export type Autorotate = {"))
	testing.expect(t, strings.contains(types_text, "\tvelocity: Vec3,"))
	testing.expect(t, strings.contains(types_text, "export type ReadonlyAutorotate = {"))
	testing.expect(t, strings.contains(types_text, "\tread velocity: ReadonlyVec3,"))
	testing.expect(t, strings.contains(types_text, "export type AutorotateComponent = ScrapbotComponent<Autorotate, ReadonlyAutorotate>"))
}

@(test)
test_check_project_validates_project_level_components_with_script_registry :: proc(t: ^testing.T) {
	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_err := os.write_entire_file(script_path, `scrapbot.log("no component schema")`)
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expect(
		t,
		check_err == `scene component "autorotate" is not defined by scripts/main.luau; add scrapbot.component("autorotate", schema)`,
	)
}

@(test)
test_check_project_accepts_script_registered_library_components :: proc(t: ^testing.T) {
	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	scene_path := join_check_project_path(t, root, DEFAULT_SCENE)
	defer delete(scene_path)
	write_scene_err := os.write_entire_file(scene_path, `[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 4, 0]
`)
	testing.expect(t, write_scene_err == nil)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_script_err := os.write_entire_file(script_path, `
local RigidbodyComponent = scrapbot.library_component("scrappyphysics.rigidbody", {
	velocity = scrapbot.vec3,
}) :: ScrappyphysicsRigidbodyComponent

local Rigidbodies = scrapbot.query(RigidbodyComponent)

scrapbot.system(Rigidbodies, function(delta_seconds: number, entity: ScrapbotEntity, rigidbody: ReadonlyScrappyphysicsRigidbody)
	local speed: number = rigidbody.velocity.y
	assert(speed > 0)
end)
`)
	testing.expect(t, write_script_err == nil)

	check_err := check_project(root)
	testing.expectf(t, check_err == "", "check_project failed: %s", check_err)

	types_path := join_check_project_path(t, root, DEFAULT_LUAU_TYPES)
	defer delete(types_path)
	types_bytes, read_err := os.read_entire_file(types_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	types_text := string(types_bytes)
	testing.expect(t, strings.contains(types_text, "library_component: <T>(name: string, schema: ScrapbotComponentSchema) -> ScrapbotComponent<T, T>,"))
	testing.expect(t, strings.contains(types_text, "export type ScrappyphysicsRigidbody = {"))
	testing.expect(t, strings.contains(types_text, "export type ScrappyphysicsRigidbodyComponent = ScrapbotComponent<ScrappyphysicsRigidbody, ReadonlyScrappyphysicsRigidbody>"))
}

@(test)
test_check_project_accepts_native_extension_registered_components :: proc(t: ^testing.T) {
	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	write_check_project_native_extension_source(t, root)

	project_path := join_check_project_path(t, root, PROJECT_FILE)
	defer delete(project_path)
	write_project_err := os.write_entire_file(project_path, `name = "Check Test"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "scrapbotnative"
source = "native/scrapbotnative"
`)
	testing.expect(t, write_project_err == nil)

	scene_path := join_check_project_path(t, root, DEFAULT_SCENE)
	defer delete(scene_path)
	write_scene_err := os.write_entire_file(scene_path, `[[entities]]
name = "Native Body"

[entities.components.scrapbotnative.body]
velocity = [0, 4, 0]
`)
	testing.expect(t, write_scene_err == nil)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_script_err := os.write_entire_file(script_path, `
local BodyComponent = scrapbot.component_handle("scrapbotnative.body") :: ScrapbotnativeBodyComponent
local Bodies = scrapbot.query(BodyComponent)

scrapbot.system(Bodies, function(delta_seconds: number, entity: ScrapbotEntity, body: ReadonlyScrapbotnativeBody)
	local speed: number = body.velocity.y
	assert(speed > 0)
end)
`)
	testing.expect(t, write_script_err == nil)

	check_err := check_project(root)
	testing.expectf(t, check_err == "", "check_project failed: %s", check_err)

	types_path := join_check_project_path(t, root, DEFAULT_LUAU_TYPES)
	defer delete(types_path)
	types_bytes, read_err := os.read_entire_file(types_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	types_text := string(types_bytes)
	testing.expect(t, strings.contains(types_text, "component_handle: <T, R>(name: string) -> ScrapbotComponent<T, R>,"))
	testing.expect(t, strings.contains(types_text, "export type ScrapbotnativeBody = {"))
	testing.expect(t, strings.contains(types_text, "export type ScrapbotnativeBodyComponent = ScrapbotComponent<ScrapbotnativeBody, ReadonlyScrapbotnativeBody>"))

	manifest_path := join_check_project_path(t, root, "build/extensions/.scrapbot-extensions")
	defer delete(manifest_path)
	manifest_bytes, manifest_read_err := os.read_entire_file(manifest_path, context.temp_allocator)
	testing.expect(t, manifest_read_err == nil)
	manifest := string(manifest_bytes)
	testing.expect(t, strings.contains(manifest, "scrapbotnative-"))
	testing.expect(t, strings.contains(manifest, fmt.tprintf(".%s", dynlib.LIBRARY_FILE_EXTENSION)))
}

@(test)
test_check_project_runs_luau_analyzer_when_available :: proc(t: ^testing.T) {
	if !luau_analyzer_available() {
		return
	}

	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_err := os.write_entire_file(script_path, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

local should_be_number: number = "not a number"
`)
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expect(t, strings.contains(check_err, "Luau analyzer failed:"))
	testing.expect(t, strings.contains(check_err, "Expected this to be 'number', but got 'string'"))
}

@(test)
test_check_project_analyzer_accepts_typed_three_component_query :: proc(t: ^testing.T) {
	if !luau_analyzer_available() {
		return
	}

	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_err := os.write_entire_file(script_path, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

scrapbot.system(function()
	local RenderedAutorotating = scrapbot.query(scrapbot.transform, scrapbot.mesh, AutorotateComponent)
	RenderedAutorotating:each(function(entity, transform: ReadonlyScrapbotTransform, mesh: ReadonlyScrapbotMesh, autorotate: ReadonlyAutorotate)
		local y: number = transform.rotation.y + autorotate.velocity.y
		assert(mesh ~= nil)
		assert(y > -100)
	end)
end)
`)
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expectf(t, check_err == "", "check_project failed: %s", check_err)
}

@(test)
test_check_project_analyzer_rejects_query_each_payload_mutation :: proc(t: ^testing.T) {
	if !luau_analyzer_available() {
		return
	}

	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_err := os.write_entire_file(script_path, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

scrapbot.system(function()
	local Autorotating = scrapbot.query(AutorotateComponent)
	Autorotating:each(function(entity, autorotate)
		autorotate.velocity.y += 1
	end)
end)
`)
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expect(t, strings.contains(check_err, "Luau analyzer failed:"))
	testing.expect(t, strings.contains(check_err, "Property y of table"))
	testing.expect(t, strings.contains(check_err, "is read-only"))
}

@(test)
test_check_project_analyzer_accepts_typed_writable_query_system :: proc(t: ^testing.T) {
	if !luau_analyzer_available() {
		return
	}

	root, parent := make_check_project_test_project(t)
	defer delete(root)
	defer os.remove_all(parent)

	script_path := join_check_project_path(t, root, DEFAULT_SCRIPT)
	defer delete(script_path)
	write_err := os.write_entire_file(script_path, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { scrapbot.transform, AutorotateComponent },
}, function(delta_seconds: number, entity: ScrapbotEntity, transform: ScrapbotTransform, autorotate: Autorotate)
	transform.rotation.y += autorotate.velocity.y * delta_seconds
	autorotate.velocity.y += 1
end)
`)
	testing.expect(t, write_err == nil)

	check_err := check_project(root)
	testing.expectf(t, check_err == "", "check_project failed: %s", check_err)
}

@(test)
test_luau_analyzer_fixture_declares_scrapbot_as_local :: proc(t: ^testing.T) {
	fixture, err := luau_analyzer_fixture(
		`--!strict
export type Scrapbot = {}
declare scrapbot: Scrapbot
`,
		`--!strict
scrapbot.log("hello")
`,
	)
	testing.expect(t, err == "")
	defer delete(fixture)

	testing.expect(t, strings.contains(fixture, "local scrapbot: Scrapbot = nil :: any"))
	testing.expect(t, !strings.contains(fixture, "declare scrapbot"))
	testing.expect(t, !strings.contains(fixture, "--!strict\nscrapbot.log"))
}

@(test)
test_luau_analyzer_output_filter_ignores_lints :: proc(t: ^testing.T) {
	testing.expect(t, luau_analyzer_output_has_errors(`main.luau:1:1-2: (W0) TypeError: bad type`))
	testing.expect(t, luau_analyzer_output_has_errors(`main.luau:1:1-2: (W0) SyntaxError: bad syntax`))
	testing.expect(t, !luau_analyzer_output_has_errors(`main.luau:1:1-2: (W0) LocalUnused: Variable is never used`))
}

make_check_project_test_project :: proc(t: ^testing.T) -> (string, string) {
	parent, temp_err := os.make_directory_temp("", "scrapbot-check-*", context.temp_allocator)
	if !testing.expect(t, temp_err == nil) {
		testing.fail_now(t)
	}

	root, join_err := filepath.join({parent, "project"})
	if !testing.expect(t, join_err == nil) {
		testing.fail_now(t)
	}

	init_err := init_project(root, "Check Test")
	if !testing.expectf(t, init_err == "", "init_project failed: %s", init_err) {
		testing.fail_now(t)
	}
	return root, parent
}

join_check_project_path :: proc(t: ^testing.T, root, path: string) -> string {
	out, join_err := filepath.join({root, path})
	testing.expect(t, join_err == nil)
	return out
}

write_check_project_native_extension_source :: proc(t: ^testing.T, root: string) {
	source_dir, source_dir_err := filepath.join({root, "native", "scrapbotnative"})
	if !testing.expect(t, source_dir_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_dir)
	make_source_dir_err := os.make_directory_all(source_dir)
	if !testing.expect(t, make_source_dir_err == nil) {
		testing.fail_now(t)
	}

	source_path, source_path_err := filepath.join({source_dir, "scrapbotnative.odin"})
	if !testing.expect(t, source_path_err == nil) {
		testing.fail_now(t)
	}
	defer delete(source_path)
	write_source_err := os.write_entire_file(source_path, `package scrapbotnative

import c "core:c"
import api "scrapbot:extension_api"

@(export)
scrapbot_extension_register :: proc "c" (scrapbot: ^api.API) -> cstring {
	if scrapbot == nil {
		return "Scrapbot API is not available"
	}
	if scrapbot.abi_version != api.ABI_VERSION {
		return "unsupported Scrapbot extension ABI"
	}

	fields := [?]api.Field_Definition {
		{name = "velocity", field_type = .Vec3},
	}
	definition := api.Component_Definition {
		name = "scrapbotnative.body",
		fields = raw_data(fields[:]),
		field_count = c.int(len(fields)),
	}
	return scrapbot.register_library_component(scrapbot, &definition)
}
`)
	if !testing.expect(t, write_source_err == nil) {
		testing.fail_now(t)
	}
}
