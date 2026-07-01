ecs.component("spin", {
  fields = {
    angular_velocity = "f32",
  },
})

ecs.system("rotate_cubes", {
  phase = "update",
  reads = { "spin" },
  writes = { "machina.transform" },
  run = function(world, dt)
    world.rotate("machina.transform", "spin", dt)
  end,
})

ecs.system("observe_cubes", {
  phase = "update",
  reads = { "machina.transform", "machina.render.cube" },
  after = { "rotate_cubes" },
})
