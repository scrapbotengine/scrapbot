const font = @import("ui/font.zig");

pub const Row = font.Row;
pub const BitShift = font.BitShift;
pub const width = font.width;
pub const height = font.height;
pub const advance = font.advance;
pub const first_codepoint = font.first_codepoint;
pub const fallback_codepoint = font.fallback_codepoint;
pub const glyphRows = font.glyphRows;

test {
    _ = font;
}
