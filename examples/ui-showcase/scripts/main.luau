local EVENT_MONITOR = "30000000-0000-4000-8000-000000000029"
local ARCADE_STATUS = "30000000-0000-4000-8000-000000000024"

local cursor = 0
local event_count = 0

local function describe(event: ScrapbotUiEvent): string
	local payload = if event.payload == "" then "" else "  /  " .. string.upper(event.payload)
	return string.format("%s  /  %s%s", string.upper(event.kind), string.upper(event.action), payload)
end

scrapbot.system({
	name = "ui_event_console",
	writes = { scrapbot.ui_text },
}, function(_time: ScrapbotTime)
	local snapshot = scrapbot.ui.events(cursor)
	cursor = snapshot.latest_sequence
	if snapshot.overflowed then
		event_count = 0
	end

	local latest: ScrapbotUiEvent? = nil
	for _, event in snapshot.events do
		if event.action ~= "" then
			latest = event
			event_count += 1
		end
	end
	if latest == nil then
		return
	end

	for _, item in scrapbot.view(scrapbot.ui_text) do
		if item.entity.id == EVENT_MONITOR then
			scrapbot.add_component(item.entity, scrapbot.ui_text, {
				text = string.format("EVENT %03d  /  %s", event_count, describe(latest)),
			})
		elseif item.entity.id == ARCADE_STATUS then
			if latest.action == "arcade.boost" and latest.kind == "activated" then
				scrapbot.add_component(item.entity, scrapbot.ui_text, { text = "BOOST ARMED" })
			elseif latest.action == "arcade.drift" and latest.kind == "activated" then
				scrapbot.add_component(item.entity, scrapbot.ui_text, { text = "DRIFT MODE" })
			elseif latest.action == "arcade.overdrive" and latest.kind == "changed" then
				scrapbot.add_component(item.entity, scrapbot.ui_text, { text = "OVERDRIVE TOGGLED" })
			end
		end
	end
end)
