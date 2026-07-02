# Machina Batching Demo

This project demonstrates automatic renderer batching. The scene authors many
independent ECS entities with repeated geometry/material component pairs; the
renderer groups those entities into shared GPU draw batches automatically.

```sh
mise machina check examples/batching
mise machina run examples/batching --frames 240
mise machina render examples/batching zig-out/batching.bmp
mise machina render-test examples/batching zig-out/batching-render-test.bmp
```
