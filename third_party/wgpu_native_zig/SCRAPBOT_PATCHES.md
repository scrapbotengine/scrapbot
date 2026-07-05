# Scrapbot Patches

This directory vendors `bronter/wgpu_native_zig` v6.5.0.

Local changes:

- Updated the build script for Zig 0.16 build API changes.
- Updated `callconv(.C)` to `callconv(.c)`.
- Removed sleeps from the wrapper's polling-based sync request helpers because Zig 0.16 moved sleep behind the new `std.Io` model.

The binding source should remain isolated behind Scrapbot renderer code.
