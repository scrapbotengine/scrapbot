# Scraproids

A compact spaceship-versus-asteroids game that dogfoods runtime input singleton components, Luau ECS systems, deferred spawning and despawning, collisions, generated geometry/materials, authored resources, lighting, HDR bloom, editable tuning, and public ECS UI.

```sh
bin/scrapbot run examples/asteroids
```

Use A/D or the left/right arrow keys to rotate freely, W/up to thrust, S/down for reverse thrust, and Space to fire. Momentum carries the ship and its shots, while the screen edges act as physical walls instead of wrapping objects around. Large, flat-shaded low-tessellation icosahedrons split into two or three crunchy, eased fragments; destroying them drives an ECS camera-shake impulse system. Open the editor with Cmd/Ctrl-E to inspect and tune the game while it runs.
