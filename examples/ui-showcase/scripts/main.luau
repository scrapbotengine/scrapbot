local EVENT_MONITOR = "30000000-0000-4000-8000-00000000002b"
local ARCADE_STATUS = "30000000-0000-4000-8000-000000000024"

local cursor = 0
local event_count = 0

local function set_text(entity: ScrapbotEntity, text: string)
	local payload: ScrapbotUiText = { text = text }
	scrapbot.add_component(entity, scrapbot.ui_text, payload)
end

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
			set_text(item.entity, string.format("EVENT %03d  /  %s", event_count, describe(latest)))
		elseif item.entity.id == ARCADE_STATUS then
			if latest.action == "arcade.boost" and latest.kind == "activated" then
				set_text(item.entity, "BOOST ARMED")
			elseif latest.action == "arcade.drift" and latest.kind == "activated" then
				set_text(item.entity, "DRIFT MODE")
			elseif latest.action == "arcade.overdrive" and latest.kind == "changed" then
				set_text(item.entity, "OVERDRIVE TOGGLED")
			end
		end
	end
end)
