--!strict

local CommandEvent = ecs.component<<ScrapbotUiCommandEvent>>("scrapbot.ui.command_event")
local UiText = ecs.component<<ScrapbotUiText>>("scrapbot.ui.text")
local UiProgressBar = ecs.component<<ScrapbotUiProgressBar>>("scrapbot.ui.progress_bar")

local StatusLabel = ecs.component("status_label", {
  fields = ecs.fields({}),
})

local MeterFill = ecs.component("meter_fill", {
  fields = ecs.fields({}),
})

local CommandEvents = ecs.query(CommandEvent)
local StatusLabels = ecs.query(UiText, StatusLabel)
local MeterFills = ecs.query(UiProgressBar, MeterFill)

local function set_status(world, text_value: string, meter_width: number)
  for _entity, text in StatusLabels:iter(world) do
    text.value = text_value
  end

  for _entity, progress in MeterFills:iter(world) do
    progress.value = meter_width
  end
end

ecs.system("handle_gallery_commands", {
  query = CommandEvents,
  reads = ecs.refs(CommandEvent, StatusLabel, MeterFill),
  writes = ecs.refs(UiText, UiProgressBar),
  run = function(world, _dt)
    for _event_entity, event in CommandEvents:iter(world) do
      if event.command == "gallery_primary" then
        set_status(world, "PRIMARY ACTION", 188)
      elseif event.command == "gallery_confirm" then
        set_status(world, "CONFIRMED", 248)
      elseif event.command == "gallery_warn" then
        set_status(world, "WARNING STATE", 116)
      end
    end
  end,
})
