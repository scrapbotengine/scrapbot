--!strict

local CommandEvent = ecs.component<<MachinaUiCommandEvent>>("machina.ui.command_event")
local UiText = ecs.component<<MachinaUiText>>("machina.ui.text")
local UiRect = ecs.component<<MachinaUiRect>>("machina.ui.rect")

local StatusLabel = ecs.component("status_label", {
  fields = ecs.fields({}),
})

local MeterFill = ecs.component("meter_fill", {
  fields = ecs.fields({}),
})

local CommandEvents = ecs.query(CommandEvent)
local StatusLabels = ecs.query(UiText, StatusLabel)
local MeterFills = ecs.query(UiRect, MeterFill)

local function set_status(world, text_value: string, meter_width: number)
  for _entity, text in StatusLabels:iter(world) do
    text.value = text_value
  end

  for _entity, rect in MeterFills:iter(world) do
    rect.size = { meter_width, 18, 0 }
  end
end

ecs.system("handle_gallery_commands", {
  query = CommandEvents,
  reads = ecs.refs(CommandEvent, StatusLabel, MeterFill),
  writes = ecs.refs(UiText, UiRect),
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
