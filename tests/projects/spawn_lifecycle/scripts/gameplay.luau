--!strict

local Stats = ecs.component("lifecycle_stats", {
  fields = ecs.fields({
    spawned_count = "int",
    removed_count = "int",
    despawned_count = "int",
  }),
})

local Payload = ecs.component("payload", {
  fields = ecs.fields({
    value = "int",
  }),
})

local Temporary = ecs.component("temporary", {
  fields = ecs.fields({
    value = "int",
  }),
})

local StatsQuery = ecs.query(Stats)

ecs.system("spawn_lifecycle_entities", {
  phase = "startup",
  query = StatsQuery,
  writes = ecs.refs(Stats, Payload, Temporary),
  run = function(world, _dt)
    for _entity, stats in StatsQuery:iter(world) do
      local survivor = world.spawn("spawned-survivor", "Spawned Survivor")
      survivor:add(Payload, { value = 42 })
      survivor:add(Temporary, { value = 100 })
      survivor:remove(Temporary)

      local doomed = world.spawn("spawned-doomed", "Spawned Doomed")
      doomed:add(Payload, { value = 1 })
      doomed:add(Temporary, { value = 2 })
      doomed:despawn()

      stats.spawned_count = 2
      stats.removed_count = 1
      stats.despawned_count = 1
    end
  end,
})
