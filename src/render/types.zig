pub const RenderError = error{
    NoAdapter,
    NoDevice,
    NoSurface,
    NoSurfaceFormat,
    SurfaceFailed,
    WindowingUnsupported,
    SdlInitFailed,
    WindowCreateFailed,
    MetalViewCreateFailed,
    MetalLayerMissing,
    NativeWindowHandleMissing,
    BufferMapFailed,
    OutOfMemory,
    InvalidScene,
    UnsupportedImageFormat,
};

pub const UiVertex = extern struct {
    position: [2]f32,
    color: [4]f32,
    local_position: [2]f32,
    rect_size_radius: [4]f32,
    glyph_rows0: [4]f32,
    glyph_rows1: [4]f32,
    glyph_rows2: [4]f32,
    glyph_rows3: [4]f32,
    glyph_rows4: [4]f32,
    glyph_rows5: [4]f32,
    glyph_rows6: [4]f32,
    glyph_rows7: [4]f32,
};

pub const InstanceAttributes = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    object_color: [4]f32,
    shadow_mvp: [16]f32,
    shadow_flags: [4]f32,
};
