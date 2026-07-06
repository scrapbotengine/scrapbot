const std = @import("std");
const Io = std.Io;

pub fn printHelp(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\scrapbot - agent-native game engine
        \\
        \\Usage:
        \\  scrapbot --version
        \\  scrapbot help
        \\  scrapbot init [path]
        \\  scrapbot check [path] [--format text|json]
        \\  scrapbot step [path] [--frames N] [--dt seconds] [--format text|json]
        \\  scrapbot bench [path] [--frames N] [--dt seconds] [--format text|json]
        \\  scrapbot test [tests-path|project-path] [--format text|json]
        \\  scrapbot build [path] [--output DIR] [--name NAME] [--force] [--format text|json]
        \\  scrapbot run [path] [--frames N] [--editor] [--hidden]
        \\  scrapbot render [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
        \\  scrapbot render-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
        \\  scrapbot visual-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [--update] <path> <expected.png> [actual.png]
        \\
    );
}
