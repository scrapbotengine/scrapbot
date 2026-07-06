local Flag = ecs.component("flag", {
  fields = ecs.fields({
    active = "boolean",
  }),
})
local Pointer = ecs.component("scrapbot.input.pointer")
local Frame = ecs.component("scrapbot.input.frame")

local Flags = ecs.query(Flag)
local Inputs = ecs.query(Pointer, Frame)

ecs.system("read_game_input", {
  phase = "update",
  query = Inputs,
  reads = ecs.refs(Pointer, Frame),
  writes = ecs.refs(Flag),
  run = function(world, _dt)
    for _input_entity, pointer, frame in Inputs:iter(world) do
      if frame.debug_overlay_visible and pointer.has_position and pointer.primary_released then
        for _flag_entity, flag in Flags:iter(world) do
          flag.active = true
        end
      end
    end
  end,
})
