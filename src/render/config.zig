const std = @import("std");
const runtime = @import("../runtime.zig");
const wgpu = @import("wgpu");

pub const AntialiasingMode = enum {
    none,
    fxaa,
};

pub const VignetteConfig = struct {
    enabled: bool = false,
    strength: f32 = 0.28,
    radius: f32 = 0.78,
};

pub const ChromaticAberrationConfig = struct {
    enabled: bool = false,
    strength: f32 = 0.003,
};

pub const BloomConfig = struct {
    enabled: bool = false,
    threshold: f32 = 1.0,
    intensity: f32 = 0.18,
    radius: f32 = 1.0,
};

pub const PostProcessConfig = struct {
    enabled: bool = false,
    antialiasing: AntialiasingMode = .none,
    vignette: VignetteConfig = .{},
    chromatic_aberration: ChromaticAberrationConfig = .{},
    bloom: BloomConfig = .{},

    pub fn isActive(self: PostProcessConfig) bool {
        return self.enabled and
            (self.antialiasing == .fxaa or
                self.vignette.enabled or
                self.chromatic_aberration.enabled or
                self.bloom.enabled);
    }
};

pub const ToneMappingMode = enum {
    none,
    reinhard,
    aces,
};

pub const ColorConfig = struct {
    hdr: bool = false,
    exposure: f32 = 0.0,
    tone_mapping: ToneMappingMode = .none,
};

pub const RenderConfig = struct {
    color: ColorConfig = .{},
    postprocess: PostProcessConfig = .{},

    pub fn requiresPostProcess(self: RenderConfig) bool {
        return self.postprocess.isActive() or self.color.hdr or self.color.tone_mapping != .none or self.color.exposure != 0.0;
    }

    pub fn bloomActive(self: RenderConfig) bool {
        return self.postprocess.enabled and self.postprocess.bloom.enabled and self.postprocess.bloom.intensity > 0.0;
    }

    pub fn sceneTextureFormat(self: RenderConfig, target_format: wgpu.TextureFormat) wgpu.TextureFormat {
        if (self.requiresPostProcess() and self.color.hdr) {
            return .rgba16_float;
        }
        return target_format;
    }
};

pub fn fromWorld(world: *const runtime.World) RenderConfig {
    const settings = world.rendererSettings() orelse return .{};
    return .{
        .color = .{
            .hdr = settings.hdr,
            .exposure = settings.exposure,
            .tone_mapping = parseToneMappingMode(settings.tone_mapping) orelse .none,
        },
        .postprocess = .{
            .enabled = settings.postprocess_enabled,
            .antialiasing = parseAntialiasingMode(settings.antialiasing) orelse .none,
            .vignette = .{
                .enabled = settings.vignette_enabled,
                .strength = settings.vignette_strength,
                .radius = settings.vignette_radius,
            },
            .chromatic_aberration = .{
                .enabled = settings.chromatic_aberration_enabled,
                .strength = settings.chromatic_aberration_strength,
            },
            .bloom = .{
                .enabled = settings.bloom_enabled,
                .threshold = settings.bloom_threshold,
                .intensity = settings.bloom_intensity,
                .radius = settings.bloom_radius,
            },
        },
    };
}

fn parseAntialiasingMode(value: []const u8) ?AntialiasingMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "fxaa")) return .fxaa;
    return null;
}

fn parseToneMappingMode(value: []const u8) ?ToneMappingMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "reinhard")) return .reinhard;
    if (std.mem.eql(u8, value, "aces")) return .aces;
    return null;
}
