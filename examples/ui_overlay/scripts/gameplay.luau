--!strict

local CommandEvent = ecs.component<<MachinaUiCommandEvent>>("machina.ui.command_event")
local UiText = ecs.component<<MachinaUiText>>("machina.ui.text")
local StatusLabel = ecs.component("status_label", {
  fields = ecs.fields({}),
})

local CommandEvents = ecs.query(CommandEvent)
local StatusLabels = ecs.query(UiText, StatusLabel)

ecs.system("handle_ui_commands", {
  query = CommandEvents,
  reads = ecs.refs(CommandEvent, StatusLabel),
  writes = ecs.refs(UiText),
  run = function(world, _dt)
    for _event_entity, event in CommandEvents:iter(world) do
      if event.command == "mark_ready_clicked" then
        for _label_entity, text in StatusLabels:iter(world) do
          text.value = "CLICKED"
        end
      end
    end
  end,
})
