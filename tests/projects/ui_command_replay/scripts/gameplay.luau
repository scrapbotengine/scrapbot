--!strict

local CommandEvent = ecs.component<<MachinaUiCommandEvent>>("machina.ui.command_event")
local Flag = ecs.component("flag", {
  fields = ecs.fields({
    active = "boolean",
  }),
})

local CommandEvents = ecs.query(CommandEvent)
local Flags = ecs.query(Flag)

ecs.system("handle_ui_commands", {
  phase = "update",
  query = CommandEvents,
  reads = ecs.refs(CommandEvent),
  writes = ecs.refs(Flag),
  run = function(world, _dt)
    for _event_entity, event in CommandEvents:iter(world) do
      if event.command == "activate_flag" then
        for _flag_entity, flag in Flags:iter(world) do
          flag.active = true
        end
      end
    end
  end,
})
