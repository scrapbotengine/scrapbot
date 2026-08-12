local VIOLET_SCENE = "b5000000-0000-4000-8000-000000000001"
local AMBER_SCENE = "b5000000-0000-4000-8000-000000000002"
local VIOLET_TITLE = "b5200000-0000-4000-8000-000000000022"
local AMBER_TITLE = "b5300000-0000-4000-8000-000000000022"

local event_cursor = 0
local active_scene = ""

local function request_scene(scene_id: string)
	scrapbot.log("changing scene to " .. scene_id)
	scrapbot.change_scene(scene_id)
end

scrapbot.system({
	name = "scene_transition_controls",
	reads = { scrapbot.keyboard_input, scrapbot.ui_text },
}, function(_time: ScrapbotTime)
	if scrapbot.input.key_pressed("1") then
		request_scene(VIOLET_SCENE)
	elseif scrapbot.input.key_pressed("2") then
		request_scene(AMBER_SCENE)
	end

	local current_scene = ""
	for _, item in scrapbot.view(scrapbot.ui_text) do
		if item.entity.id == VIOLET_TITLE then
			current_scene = VIOLET_SCENE
		elseif item.entity.id == AMBER_TITLE then
			current_scene = AMBER_SCENE
		end
	end
	if current_scene ~= active_scene then
		active_scene = current_scene
		event_cursor = 0
	end

	local snapshot = scrapbot.ui.events(event_cursor)
	event_cursor = snapshot.latest_sequence

	for _, event in snapshot.events do
		if event.kind == "activated" then
			if event.action == "scene.show_violet" then
				request_scene(VIOLET_SCENE)
			elseif event.action == "scene.show_amber" then
				request_scene(AMBER_SCENE)
			end
		end
	end
end)
