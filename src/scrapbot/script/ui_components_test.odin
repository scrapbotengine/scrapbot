package script

import ecs "../ecs"
import project "../project"
import "core:testing"

@(test)
test_luau_exposes_and_queries_all_public_ui_container_and_input_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
name = "Inspector Field"
[entities.ui_layout]
size = [240, 32]
[entities.ui_panel]
title = "FIELD"
[entities.ui_table]
columns = 1
[entities.ui_input]
text = "42"
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
assert(scrapbot.ui_panel.id > 0)
assert(scrapbot.ui_table.id > 0)
assert(scrapbot.ui_input.id > 0)

scrapbot.system(function()
	local count = 0
	scrapbot.query(scrapbot.ui_panel, scrapbot.ui_table, scrapbot.ui_input):each(function(_, panel, table, input)
		assert(type(panel) == "table")
		assert(type(table) == "table")
		assert(type(input) == "table")
		count += 1
	end)
	assert(count == 1)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, step_runtime(&runtime, &world, 0) == "")
}
