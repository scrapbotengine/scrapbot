const std = @import("std");
const runtime = @import("../runtime.zig");
const ui_layout = @import("../ui_layout.zig");
const ui_font = @import("../ui_font.zig");
const editor_layout = @import("../editor/layout.zig");
const render_input = @import("input.zig");
const render_math = @import("math.zig");
const types = @import("types.zig");

pub const render_ui_button_state_component_id = "scrapbot.render.internal.ui.button_state";
pub const render_ui_clip_component_id = "scrapbot.render.internal.ui.clip";

const FrameInput = render_input.FrameInput;
const normalizedPixelScale = render_input.normalizedPixelScale;
const framePixelScale = render_input.framePixelScale;
const frameInputWithDefaultOutputMetrics = render_input.frameInputWithDefaultOutputMetrics;
const RenderError = types.RenderError;
const UiVertex = types.UiVertex;
pub const UiClipRect = ui_layout.ClipRect;
pub const UiCanvasTransform = ui_layout.CanvasTransform;
const editorGameViewport = editor_layout.gameViewport;
const isFiniteVec3 = render_math.isFiniteVec3;

const GlyphVertexRows = struct {
    rows: [8][4]f32,
    visible: bool,
};

pub const UiButtonState = struct {
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,

    fn eql(self: UiButtonState, other: UiButtonState) bool {
        return self.hovered == other.hovered and
            self.held == other.held and
            self.pressed == other.pressed;
    }
};

pub const UiBorder = struct {
    color: [3]f32,
    thickness: f32,
};

pub const UiProgressBar = struct {
    value: f32,
    max: f32,
    fill_color: [3]f32,
};

pub fn writeFrameInput(world: *runtime.World, input: FrameInput) runtime.WorldError!void {
    const entity = world.findEntityById(runtime.input_entity_id) orelse try world.createEngineTransientEntity(runtime.input_entity_id, "Input Frame");
    try world.setInputPointer(entity, .{
        .position = .{ input.pointer.position[0], input.pointer.position[1], 0.0 },
        .delta = .{ input.pointer.delta[0], input.pointer.delta[1], 0.0 },
        .has_position = input.pointer.has_position,
        .primary_down = input.pointer.primary_down,
        .primary_pressed = input.pointer.primary_pressed,
        .primary_released = input.pointer.primary_released,
        .secondary_down = input.pointer.secondary_down,
        .secondary_pressed = input.pointer.secondary_pressed,
        .secondary_released = input.pointer.secondary_released,
        .wheel_delta = .{ input.pointer.wheel_delta[0], input.pointer.wheel_delta[1], 0.0 },
    });
    try world.setInputKeyboard(entity, .{
        .ctrl_down = input.keyboard.ctrl_down,
        .shift_down = input.keyboard.shift_down,
        .alt_down = input.keyboard.alt_down,
        .super_down = input.keyboard.super_down,
        .move_forward = input.keyboard.move_forward,
        .move_back = input.keyboard.move_back,
        .move_left = input.keyboard.move_left,
        .move_right = input.keyboard.move_right,
        .move_up = input.keyboard.move_up,
        .move_down = input.keyboard.move_down,
        .editor_toggle_pressed = input.keyboard.editor_toggle_pressed,
    });
    try world.setInputFrame(entity, .{
        .ui_visible = input.ui_visible,
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport = .{ input.viewport_width, input.viewport_height, 0.0 },
        .pixel_scale = framePixelScale(input),
    });
}

pub fn setRenderFrameInput(world: *runtime.World, input: FrameInput) RenderError!void {
    writeFrameInput(world, input) catch |err| return mapWorldError(err);
}

pub fn renderFrameInput(world: *const runtime.World) RenderError!FrameInput {
    const entity = world.findEntityById(runtime.input_entity_id) orelse return RenderError.InvalidScene;
    const position = world.getVec3(entity, runtime.input_pointer_component_id, "position") catch |err| return mapWorldError(err);
    const delta = world.getVec3(entity, runtime.input_pointer_component_id, "delta") catch |err| return mapWorldError(err);
    const wheel_delta = world.getVec3(entity, runtime.input_pointer_component_id, "wheel_delta") catch |err| return mapWorldError(err);
    const viewport = world.getVec3(entity, runtime.input_frame_component_id, "viewport") catch |err| return mapWorldError(err);
    return .{
        .pointer = .{
            .position = .{ position[0], position[1] },
            .delta = .{ delta[0], delta[1] },
            .has_position = world.getBoolean(entity, runtime.input_pointer_component_id, "has_position") catch |err| return mapWorldError(err),
            .primary_down = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_down") catch |err| return mapWorldError(err),
            .primary_pressed = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_pressed") catch |err| return mapWorldError(err),
            .primary_released = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_released") catch |err| return mapWorldError(err),
            .secondary_down = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_down") catch |err| return mapWorldError(err),
            .secondary_pressed = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_pressed") catch |err| return mapWorldError(err),
            .secondary_released = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_released") catch |err| return mapWorldError(err),
            .wheel_delta = .{ wheel_delta[0], wheel_delta[1] },
        },
        .keyboard = .{
            .ctrl_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "ctrl_down") catch |err| return mapWorldError(err),
            .shift_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "shift_down") catch |err| return mapWorldError(err),
            .alt_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "alt_down") catch |err| return mapWorldError(err),
            .super_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "super_down") catch |err| return mapWorldError(err),
            .move_forward = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_forward") catch |err| return mapWorldError(err),
            .move_back = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_back") catch |err| return mapWorldError(err),
            .move_left = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_left") catch |err| return mapWorldError(err),
            .move_right = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_right") catch |err| return mapWorldError(err),
            .move_up = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_up") catch |err| return mapWorldError(err),
            .move_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_down") catch |err| return mapWorldError(err),
            .editor_toggle_pressed = world.getBoolean(entity, runtime.input_keyboard_component_id, "editor_toggle_pressed") catch |err| return mapWorldError(err),
        },
        .ui_visible = world.getBoolean(entity, runtime.input_frame_component_id, "ui_visible") catch |err| return mapWorldError(err),
        .debug_overlay_visible = world.getBoolean(entity, runtime.input_frame_component_id, "debug_overlay_visible") catch |err| return mapWorldError(err),
        .viewport_width = viewport[0],
        .viewport_height = viewport[1],
        .pixel_scale = normalizedPixelScale(world.getFloat(entity, runtime.input_frame_component_id, "pixel_scale") catch |err| return mapWorldError(err)),
    };
}

pub fn setRenderUiButtonState(world: *runtime.World, entity: runtime.EntityHandle, state: UiButtonState) RenderError!void {
    if (try renderUiButtonState(world, entity)) |existing| {
        if (existing.eql(state)) {
            return;
        }
    }
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "hovered", .value = .{ .boolean = state.hovered } },
        .{ .name = "held", .value = .{ .boolean = state.held } },
        .{ .name = "pressed", .value = .{ .boolean = state.pressed } },
    };
    world.setComponentSilently(entity, render_ui_button_state_component_id, &fields) catch |err| return mapWorldError(err);
}

pub fn setRenderUiClip(world: *runtime.World, entity: runtime.EntityHandle, clip: UiClipRect) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "position", .value = .{ .vec3 = clip.position } },
        .{ .name = "size", .value = .{ .vec3 = clip.size } },
    };
    world.setComponentSilently(entity, render_ui_clip_component_id, &fields) catch |err| return mapWorldError(err);
}

pub fn renderUiButtonState(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiButtonState {
    if (!(world.hasComponent(entity, render_ui_button_state_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .hovered = world.getBoolean(entity, render_ui_button_state_component_id, "hovered") catch |err| return mapWorldError(err),
        .held = world.getBoolean(entity, render_ui_button_state_component_id, "held") catch |err| return mapWorldError(err),
        .pressed = world.getBoolean(entity, render_ui_button_state_component_id, "pressed") catch |err| return mapWorldError(err),
    };
}

pub fn renderUiClip(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiClipRect {
    if (!(world.hasComponent(entity, render_ui_clip_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .position = world.getVec3(entity, render_ui_clip_component_id, "position") catch |err| return mapWorldError(err),
        .size = world.getVec3(entity, render_ui_clip_component_id, "size") catch |err| return mapWorldError(err),
    };
}

pub fn uiBorder(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiBorder {
    if (!(world.hasComponent(entity, runtime.ui_border_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .color = world.getVec3(entity, runtime.ui_border_component_id, "color") catch |err| return mapWorldError(err),
        .thickness = world.getFloat(entity, runtime.ui_border_component_id, "thickness") catch |err| return mapWorldError(err),
    };
}

pub fn uiProgressBar(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiProgressBar {
    if (!(world.hasComponent(entity, runtime.ui_progress_bar_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .value = world.getFloat(entity, runtime.ui_progress_bar_component_id, "value") catch |err| return mapWorldError(err),
        .max = world.getFloat(entity, runtime.ui_progress_bar_component_id, "max") catch |err| return mapWorldError(err),
        .fill_color = world.getVec3(entity, runtime.ui_progress_bar_component_id, "fill_color") catch |err| return mapWorldError(err),
    };
}

pub fn uiToggleChecked(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?bool {
    if (!(world.hasComponent(entity, runtime.ui_toggle_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return world.getBoolean(entity, runtime.ui_toggle_component_id, "checked") catch |err| return mapWorldError(err);
}

pub fn resolveUiLayout(world: *const runtime.World, entity: runtime.EntityHandle, local_position: [3]f32) RenderError!ui_layout.ResolvedLayout {
    return ui_layout.resolve(world, entity, local_position) catch |err| return mapLayoutError(err);
}

pub fn resolveUiLayoutWithCache(cache: *ui_layout.LayoutCache, world: *const runtime.World, entity: runtime.EntityHandle, local_position: [3]f32) RenderError!ui_layout.ResolvedLayout {
    return ui_layout.resolveWithCache(cache, world, entity, local_position) catch |err| return mapLayoutError(err);
}

pub fn combineUiClip(a: ?UiClipRect, b: ?UiClipRect) RenderError!?UiClipRect {
    return ui_layout.combineClip(a, b) catch |err| return mapLayoutError(err);
}

pub fn resolveUiScreenLayout(input: FrameInput, entity_id: []const u8, layout: ui_layout.ResolvedLayout, item_size: [3]f32) RenderError!ui_layout.ResolvedLayout {
    if (!input.debug_overlay_visible or isEditorUiEntityId(entity_id)) {
        return layout;
    }
    return ui_layout.clipToTarget(layout, sceneUiTarget(input, 0.0, 0.0), item_size) catch |err| return mapLayoutError(err);
}

pub fn sceneUiCanvasTransform(world: *const runtime.World, input: FrameInput, width: f32, height: f32) RenderError!UiCanvasTransform {
    return ui_layout.canvasTransform(world, sceneUiTarget(input, width, height)) catch |err| return mapLayoutError(err);
}

fn sceneUiTarget(input: FrameInput, width: f32, height: f32) ui_layout.Target {
    if (input.debug_overlay_visible) {
        const viewport = editorGameViewport(input);
        return .{ .x = viewport.x, .y = viewport.y, .width = viewport.width, .height = viewport.height };
    }
    return .{ .width = width, .height = height };
}

pub fn isEditorUiEntityId(entity_id: []const u8) bool {
    return std.mem.startsWith(u8, entity_id, "scrapbot.editor.");
}

pub fn applyUiCanvasLayout(transform: UiCanvasTransform, entity_id: []const u8, layout: ui_layout.ResolvedLayout) ui_layout.ResolvedLayout {
    if (isEditorUiEntityId(entity_id)) {
        return layout;
    }
    return ui_layout.applyCanvasTransform(transform, layout);
}

pub fn scaleUiVec3(transform: UiCanvasTransform, value: [3]f32) [3]f32 {
    return ui_layout.scaleVec3(transform, value);
}

pub fn scaleUiSize(transform: UiCanvasTransform, value: [3]f32) [3]f32 {
    return ui_layout.scaleSize(transform, value);
}

pub fn scaleUiVec3By(value: [3]f32, scale: f32) [3]f32 {
    return .{ value[0] * scale, value[1] * scale, value[2] * scale };
}

pub fn scaleUiClipBy(clip: ?UiClipRect, scale: f32) ?UiClipRect {
    const value = clip orelse return null;
    return .{
        .position = scaleUiVec3By(value.position, scale),
        .size = scaleUiVec3By(value.size, scale),
    };
}

pub fn scaleUiResolvedLayoutBy(layout: ui_layout.ResolvedLayout, scale: f32) ui_layout.ResolvedLayout {
    return .{
        .position = scaleUiVec3By(layout.position, scale),
        .clip = scaleUiClipBy(layout.clip, scale),
    };
}

pub fn uiLayoutItemSize(world: *const runtime.World, entity: runtime.EntityHandle) RenderError![3]f32 {
    return ui_layout.resolvedItemSize(world, entity) catch |err| return mapLayoutError(err);
}

pub fn uiLayoutItemSizeWithCache(cache: *ui_layout.LayoutCache, world: *const runtime.World, entity: runtime.EntityHandle) RenderError![3]f32 {
    return ui_layout.resolvedItemSizeWithCache(cache, world, entity) catch |err| return mapLayoutError(err);
}

pub fn hitTestUiRect(point: [2]f32, position: [3]f32, size: [3]f32, clip: ?UiClipRect) bool {
    return ui_layout.pointInsideRect(point, position, size, clip);
}

pub fn textPixelSize(value: []const u8, size: f32) [3]f32 {
    return ui_layout.textPixelSize(value, size);
}

pub fn resolveUiTextPosition(world: *const runtime.World, entity: runtime.EntityHandle, text: runtime.UiText, position: [3]f32) RenderError![3]f32 {
    return ui_layout.resolveTextPosition(world, entity, text, position) catch |err| return mapLayoutError(err);
}

pub fn evaluateUiButtonState(input: FrameInput, position: [3]f32, size: [3]f32, clip: ?UiClipRect) UiButtonState {
    const hovered = input.pointer.has_position and hitTestUiRect(input.pointer.position, position, size, clip);
    return .{
        .hovered = hovered,
        .held = hovered and input.pointer.primary_down,
        .pressed = hovered and input.pointer.primary_released,
    };
}

fn mapWorldError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

fn mapLayoutError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

pub fn buildUiVertices(allocator: std.mem.Allocator, world: *const runtime.World, width: u32, height: u32) RenderError!std.ArrayList(UiVertex) {
    var layout_cache = ui_layout.LayoutCache.init(allocator);
    defer layout_cache.deinit();

    var vertices: std.ArrayList(UiVertex) = .empty;
    errdefer vertices.deinit(allocator);
    try buildUiVerticesInto(allocator, &vertices, &layout_cache, world, width, height);
    return vertices;
}

const UiVertexCacheKey = struct {
    width: u32 = 0,
    height: u32 = 0,
    viewport_width: f32 = 0.0,
    viewport_height: f32 = 0.0,
    pixel_scale: f32 = 1.0,
    ui_visible: bool = false,
    debug_overlay_visible: bool = false,
    component_generation_fingerprint: u64 = 0,

    fn fromWorld(world: *const runtime.World, width: u32, height: u32) UiVertexCacheKey {
        const stored_input = renderFrameInput(world) catch FrameInput{};
        const input = frameInputWithDefaultOutputMetrics(stored_input, width, height);
        return .{
            .width = width,
            .height = height,
            .viewport_width = input.viewport_width,
            .viewport_height = input.viewport_height,
            .pixel_scale = framePixelScale(input),
            .ui_visible = input.ui_visible,
            .debug_overlay_visible = input.debug_overlay_visible,
            .component_generation_fingerprint = uiComponentGenerationFingerprint(world),
        };
    }

    fn eql(self: UiVertexCacheKey, other: UiVertexCacheKey) bool {
        return self.width == other.width and
            self.height == other.height and
            self.viewport_width == other.viewport_width and
            self.viewport_height == other.viewport_height and
            self.pixel_scale == other.pixel_scale and
            self.ui_visible == other.ui_visible and
            self.debug_overlay_visible == other.debug_overlay_visible and
            self.component_generation_fingerprint == other.component_generation_fingerprint;
    }
};

const ui_vertex_cache_component_ids = [_][]const u8{
    runtime.ui_canvas_component_id,
    runtime.ui_rect_component_id,
    runtime.ui_border_component_id,
    runtime.ui_text_component_id,
    runtime.ui_button_component_id,
    runtime.ui_scroll_view_component_id,
    runtime.ui_vgroup_component_id,
    runtime.ui_hgroup_component_id,
    runtime.ui_table_component_id,
    runtime.ui_stack_component_id,
    runtime.ui_layout_item_component_id,
    runtime.ui_spacer_component_id,
    runtime.ui_text_block_component_id,
    runtime.ui_toggle_component_id,
    runtime.ui_progress_bar_component_id,
    runtime.ui_separator_component_id,
    render_ui_button_state_component_id,
    render_ui_clip_component_id,
};

fn uiComponentGenerationFingerprint(world: *const runtime.World) u64 {
    var fingerprint: u64 = 14695981039346656037;
    for (ui_vertex_cache_component_ids) |component_id| {
        fingerprint ^= world.componentMutationGeneration(component_id);
        fingerprint *%= 1099511628211;
    }
    return fingerprint;
}

pub const UiVertexCache = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(UiVertex) = .empty,
    layout_cache: ui_layout.LayoutCache,
    rect_observer: runtime.QueryObserver,
    text_observer: runtime.QueryObserver,
    separator_observer: runtime.QueryObserver,
    last_key: UiVertexCacheKey = .{},
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) RenderError!UiVertexCache {
        var rect_observer = runtime.QueryObserver.init(allocator, &.{runtime.ui_rect_component_id}) catch return RenderError.OutOfMemory;
        errdefer rect_observer.deinit();
        var text_observer = runtime.QueryObserver.init(allocator, &.{runtime.ui_text_component_id}) catch return RenderError.OutOfMemory;
        errdefer text_observer.deinit();
        var separator_observer = runtime.QueryObserver.init(allocator, &.{runtime.ui_separator_component_id}) catch return RenderError.OutOfMemory;
        errdefer separator_observer.deinit();

        return .{
            .allocator = allocator,
            .layout_cache = ui_layout.LayoutCache.init(allocator),
            .rect_observer = rect_observer,
            .text_observer = text_observer,
            .separator_observer = separator_observer,
        };
    }

    pub fn deinit(self: *UiVertexCache) void {
        self.separator_observer.deinit();
        self.text_observer.deinit();
        self.rect_observer.deinit();
        self.layout_cache.deinit();
        self.vertices.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn refresh(self: *UiVertexCache, world: *const runtime.World, width: u32, height: u32) RenderError!bool {
        self.rect_observer.refresh(world.*) catch |err| return mapWorldError(err);
        self.text_observer.refresh(world.*) catch |err| return mapWorldError(err);
        self.separator_observer.refresh(world.*) catch |err| return mapWorldError(err);

        const key = UiVertexCacheKey.fromWorld(world, width, height);
        const membership_changed = observerMembershipChanged(self.rect_observer) or
            observerMembershipChanged(self.text_observer) or
            observerMembershipChanged(self.separator_observer);
        const should_rebuild = !self.initialized or membership_changed or !self.last_key.eql(key);
        if (!should_rebuild) {
            return false;
        }

        try buildUiVerticesInto(self.allocator, &self.vertices, &self.layout_cache, world, width, height);
        self.last_key = key;
        self.initialized = true;
        return true;
    }

    pub fn vertexItems(self: *const UiVertexCache) []const UiVertex {
        return self.vertices.items;
    }
};

fn observerMembershipChanged(observer: runtime.QueryObserver) bool {
    return observer.appeared().len > 0 or observer.disappeared().len > 0;
}

pub fn buildUiVerticesInto(
    allocator: std.mem.Allocator,
    vertices: *std.ArrayList(UiVertex),
    layout_cache: *ui_layout.LayoutCache,
    world: *const runtime.World,
    width: u32,
    height: u32,
) RenderError!void {
    if (width == 0 or height == 0) {
        return RenderError.InvalidScene;
    }

    const stored_input = renderFrameInput(world) catch FrameInput{};
    const input = frameInputWithDefaultOutputMetrics(stored_input, width, height);
    const pixel_scale = framePixelScale(input);
    const canvas_transform = try sceneUiCanvasTransform(world, input, input.viewport_width, input.viewport_height);
    const viewport_clip = UiClipRect{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ @floatFromInt(width), @floatFromInt(height), 0.0 },
    };
    layout_cache.reset(world) catch |err| return mapLayoutError(err);
    vertices.clearRetainingCapacity();
    const estimated_vertices = estimatedUiVertexCapacity(world);
    vertices.ensureTotalCapacity(allocator, estimated_vertices) catch return RenderError.OutOfMemory;

    var rects = world.uiRects();
    while (rects.next()) |rect| {
        if (!shouldDrawUiEntity(input, rect.id)) {
            continue;
        }
        const maybe_button_state = if (rect.is_button) try renderUiButtonState(world, rect.entity) else null;
        const item_size = try uiLayoutItemSizeWithCache(layout_cache, world, rect.entity);
        const layout = try resolveUiLayoutWithCache(layout_cache, world, rect.entity, rect.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, rect.id, layout);
        const screen_size = if (isEditorUiEntityId(rect.id)) item_size else scaleUiSize(canvas_transform, item_size);
        const screen_layout = try resolveUiScreenLayout(input, rect.id, canvas_layout, screen_size);
        const physical_layout = scaleUiResolvedLayoutBy(screen_layout, pixel_scale);
        const physical_size = scaleUiVec3By(screen_size, pixel_scale);
        const style_scale: f32 = (if (isEditorUiEntityId(rect.id)) 1.0 else canvas_transform.scale) * pixel_scale;
        const screen_radius = rect.corner_radius * style_scale;
        const maybe_clip = try viewportUiClip(scaleUiClipBy(try combineUiClip(screen_layout.clip, try renderUiClip(world, rect.entity)), pixel_scale), viewport_clip);
        var rect_color = rect.color;
        if (maybe_button_state) |state| {
            if (state.held) {
                rect_color = scaleColor(rect.color, 0.86);
            } else if (state.pressed) {
                rect_color = scaleColor(rect.color, 1.1);
            } else if (state.hovered) {
                rect_color = scaleColor(rect.color, 1.06);
            }
        }
        if ((try uiToggleChecked(world, rect.entity)) orelse false) {
            rect_color = scaleColor(rect_color, 1.18);
        }

        try appendStyledUiRect(vertices, allocator, world, width, height, rect.entity, physical_layout.position, physical_size, rect_color, screen_radius, style_scale, maybe_clip);
        if (try uiProgressBar(world, rect.entity)) |progress| {
            const ratio = try uiProgressRatio(progress);
            if (ratio > 0.0) {
                const fill_size = [3]f32{ physical_size[0] * ratio, physical_size[1], physical_size[2] };
                try appendUiRectClipped(vertices, allocator, width, height, physical_layout.position, fill_size, progress.fill_color, screen_radius, maybe_clip);
            }
        }
    }

    var separators = world.uiSeparators();
    while (separators.next()) |separator| {
        if (!shouldDrawUiEntity(input, separator.id)) {
            continue;
        }
        const item_size = try uiLayoutItemSizeWithCache(layout_cache, world, separator.entity);
        const layout = try resolveUiLayoutWithCache(layout_cache, world, separator.entity, separator.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, separator.id, layout);
        const screen_size = if (isEditorUiEntityId(separator.id)) item_size else scaleUiSize(canvas_transform, item_size);
        const screen_layout = try resolveUiScreenLayout(input, separator.id, canvas_layout, screen_size);
        const physical_layout = scaleUiResolvedLayoutBy(screen_layout, pixel_scale);
        const physical_size = scaleUiVec3By(screen_size, pixel_scale);
        const maybe_clip = try viewportUiClip(scaleUiClipBy(try combineUiClip(screen_layout.clip, try renderUiClip(world, separator.entity)), pixel_scale), viewport_clip);
        try appendUiRectClipped(vertices, allocator, width, height, physical_layout.position, physical_size, separator.color, 0.0, maybe_clip);
    }

    var texts = world.uiTexts();
    while (texts.next()) |text| {
        if (!shouldDrawUiEntity(input, text.id)) {
            continue;
        }
        const item_size = try uiLayoutItemSizeWithCache(layout_cache, world, text.entity);
        const layout = try resolveUiLayoutWithCache(layout_cache, world, text.entity, text.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, text.id, layout);
        const screen_item_size = if (isEditorUiEntityId(text.id)) item_size else scaleUiSize(canvas_transform, item_size);
        const screen_layout = try resolveUiScreenLayout(input, text.id, canvas_layout, screen_item_size);
        const maybe_clip = try viewportUiClip(scaleUiClipBy(try combineUiClip(screen_layout.clip, try renderUiClip(world, text.entity)), pixel_scale), viewport_clip);
        var resolved_text = text;
        if (isEditorUiEntityId(text.id)) {
            resolved_text.position = try resolveUiTextPosition(world, text.entity, text, screen_layout.position);
        } else {
            const design_position = try resolveUiTextPosition(world, text.entity, text, layout.position);
            resolved_text.position = scaleUiVec3(canvas_transform, design_position);
            resolved_text.size *= canvas_transform.scale;
        }
        resolved_text.position = scaleUiVec3By(resolved_text.position, pixel_scale);
        resolved_text.size *= pixel_scale;
        try appendUiText(vertices, allocator, width, height, resolved_text, maybe_clip);
    }
}

fn shouldDrawUiEntity(input: FrameInput, entity_id: []const u8) bool {
    if (isEditorUiEntityId(entity_id)) {
        return input.debug_overlay_visible;
    }
    return input.ui_visible;
}

fn viewportUiClip(clip: ?UiClipRect, viewport_clip: UiClipRect) RenderError!?UiClipRect {
    return combineUiClip(clip, viewport_clip);
}

fn estimatedUiVertexCapacity(world: *const runtime.World) usize {
    const rect_vertices = std.math.mul(usize, world.uiRectCount(), 18) catch std.math.maxInt(usize);
    const separator_vertices = std.math.mul(usize, world.uiSeparatorCount(), 6) catch std.math.maxInt(usize);
    const text_count = @min(world.uiTextCount(), 256);
    const text_vertices = std.math.mul(usize, text_count, 64) catch std.math.maxInt(usize);
    const total = std.math.add(usize, rect_vertices, separator_vertices) catch std.math.maxInt(usize);
    return @min(std.math.add(usize, total, text_vertices) catch std.math.maxInt(usize), 65_536);
}

fn uiProgressRatio(progress: UiProgressBar) RenderError!f32 {
    if (!std.math.isFinite(progress.value) or !std.math.isFinite(progress.max) or !isFiniteVec3(progress.fill_color) or progress.max <= 0.0) {
        return RenderError.InvalidScene;
    }
    return clamp01(progress.value / progress.max);
}

fn appendStyledUiRect(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    world: *const runtime.World,
    width: u32,
    height: u32,
    entity: runtime.EntityHandle,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    style_scale: f32,
    clip: ?UiClipRect,
) RenderError!void {
    const border = (try uiBorder(world, entity)) orelse {
        try appendUiRectClipped(vertices, allocator, width, height, position, size, color, corner_radius, clip);
        return;
    };
    if (!isFiniteVec3(border.color) or !std.math.isFinite(border.thickness) or border.thickness < 0.0) {
        return RenderError.InvalidScene;
    }
    if (border.thickness == 0.0) {
        try appendUiRectClipped(vertices, allocator, width, height, position, size, color, corner_radius, clip);
        return;
    }

    const thickness = @min(border.thickness * style_scale, @min(size[0], size[1]) * 0.5);
    try appendUiRectClipped(vertices, allocator, width, height, position, size, border.color, corner_radius, clip);
    const inner_size = [3]f32{
        @max(size[0] - thickness * 2.0, 0.0),
        @max(size[1] - thickness * 2.0, 0.0),
        size[2],
    };
    if (inner_size[0] <= 0.0 or inner_size[1] <= 0.0) {
        return;
    }
    try appendUiRectClipped(
        vertices,
        allocator,
        width,
        height,
        .{ position[0] + thickness, position[1] + thickness, position[2] },
        inner_size,
        color,
        @max(corner_radius - thickness, 0.0),
        clip,
    );
}

fn appendUiText(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    text: runtime.UiText,
    clip: ?UiClipRect,
) RenderError!void {
    if (!isFiniteVec3(text.position) or
        !std.math.isFinite(text.size) or
        text.size <= 0.0 or
        !isFiniteVec3(text.color))
    {
        return RenderError.InvalidScene;
    }

    const origin_x = text.position[0];
    if (!(try rectIntersectsClip(text.position, textPixelSize(text.value, text.size), clip))) {
        return;
    }
    var cursor_x = origin_x;
    var cursor_y = text.position[1];
    for (text.value) |byte| {
        if (byte == '\n') {
            cursor_x = origin_x;
            cursor_y += text.size * @as(f32, @floatFromInt(ui_font.height));
            continue;
        }
        try appendGlyph(vertices, allocator, width, height, cursor_x, cursor_y, text.size, text.color, byte, clip);
        cursor_x += text.size * @as(f32, @floatFromInt(ui_font.advance));
    }
}

fn appendGlyph(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    x: f32,
    y: f32,
    size: f32,
    color: [3]f32,
    byte: u8,
    clip: ?UiClipRect,
) RenderError!void {
    const glyph = glyphVertexRows(byte);
    if (!glyph.visible) {
        return;
    }
    try appendUiGlyphClipped(vertices, allocator, width, height, .{ x, y, 0.0 }, size, color, glyph.rows, clip);
}

fn rectIntersectsClip(position: [3]f32, size: [3]f32, clip: ?UiClipRect) RenderError!bool {
    if (size[0] <= 0.0 or size[1] <= 0.0) {
        return false;
    }
    const clip_rect = clip orelse return true;
    if (!isFiniteVec3(clip_rect.position) or !isFiniteVec3(clip_rect.size)) {
        return RenderError.InvalidScene;
    }
    if (clip_rect.size[0] <= 0.0 or clip_rect.size[1] <= 0.0) {
        return false;
    }
    const left = @max(position[0], clip_rect.position[0]);
    const top = @max(position[1], clip_rect.position[1]);
    const right = @min(position[0] + size[0], clip_rect.position[0] + clip_rect.size[0]);
    const bottom = @min(position[1] + size[1], clip_rect.position[1] + clip_rect.size[1]);
    return right > left and bottom > top;
}

fn appendUiRectClipped(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    clip: ?UiClipRect,
) RenderError!void {
    if (!isFiniteVec3(position) or
        !isFiniteVec3(size) or
        !isFiniteVec3(color) or
        !std.math.isFinite(corner_radius) or
        size[0] <= 0.0 or
        size[1] <= 0.0 or
        corner_radius < 0.0)
    {
        std.log.err(
            "invalid UI rect: position={d:.3},{d:.3},{d:.3} size={d:.3},{d:.3},{d:.3} color={d:.3},{d:.3},{d:.3} radius={d:.3}",
            .{
                position[0],
                position[1],
                position[2],
                size[0],
                size[1],
                size[2],
                color[0],
                color[1],
                color[2],
                corner_radius,
            },
        );
        return RenderError.InvalidScene;
    }

    var clipped_position = position;
    var clipped_size = size;
    if (clip) |clip_rect| {
        if (!isFiniteVec3(clip_rect.position) or !isFiniteVec3(clip_rect.size)) {
            return RenderError.InvalidScene;
        }
        if (clip_rect.size[0] <= 0.0 or clip_rect.size[1] <= 0.0) {
            return;
        }
        const left_px = @max(position[0], clip_rect.position[0]);
        const top_px = @max(position[1], clip_rect.position[1]);
        const right_px = @min(position[0] + size[0], clip_rect.position[0] + clip_rect.size[0]);
        const bottom_px = @min(position[1] + size[1], clip_rect.position[1] + clip_rect.size[1]);
        if (right_px <= left_px or bottom_px <= top_px) {
            return;
        }
        clipped_position = .{ left_px, top_px, position[2] };
        clipped_size = .{ right_px - left_px, bottom_px - top_px, size[2] };
    }

    const left = screenToClipX(clipped_position[0], width);
    const right = screenToClipX(clipped_position[0] + clipped_size[0], width);
    const top = screenToClipY(clipped_position[1], height);
    const bottom = screenToClipY(clipped_position[1] + clipped_size[1], height);
    const vertex_color = [4]f32{ clamp01(color[0]), clamp01(color[1]), clamp01(color[2]), 1.0 };
    const rect_size_radius = [4]f32{
        size[0],
        size[1],
        @min(corner_radius, @min(size[0], size[1]) * 0.5),
        if (corner_radius > 0.0) 1.0 else 0.0,
    };
    const local_left = clipped_position[0] - position[0];
    const local_top = clipped_position[1] - position[1];
    const local_right = local_left + clipped_size[0];
    const local_bottom = local_top + clipped_size[1];

    const glyph_rows = zeroGlyphRows();
    const quad = [_]UiVertex{
        uiVertex(.{ left, top }, vertex_color, .{ local_left, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, top }, vertex_color, .{ local_right, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, bottom }, vertex_color, .{ local_right, local_bottom }, rect_size_radius, glyph_rows),
        uiVertex(.{ left, top }, vertex_color, .{ local_left, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, bottom }, vertex_color, .{ local_right, local_bottom }, rect_size_radius, glyph_rows),
        uiVertex(.{ left, bottom }, vertex_color, .{ local_left, local_bottom }, rect_size_radius, glyph_rows),
    };
    try vertices.appendSlice(allocator, &quad);
}

fn appendUiGlyphClipped(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    position: [3]f32,
    pixel_size: f32,
    color: [3]f32,
    glyph_rows: [8][4]f32,
    clip: ?UiClipRect,
) RenderError!void {
    const size = [3]f32{
        @as(f32, @floatFromInt(ui_font.width)) * pixel_size,
        @as(f32, @floatFromInt(ui_font.height)) * pixel_size,
        0.0,
    };
    if (!isFiniteVec3(position) or
        !std.math.isFinite(pixel_size) or
        pixel_size <= 0.0 or
        !isFiniteVec3(color))
    {
        return RenderError.InvalidScene;
    }

    var clipped_position = position;
    var clipped_size = size;
    if (clip) |clip_rect| {
        if (!isFiniteVec3(clip_rect.position) or !isFiniteVec3(clip_rect.size)) {
            return RenderError.InvalidScene;
        }
        if (clip_rect.size[0] <= 0.0 or clip_rect.size[1] <= 0.0) {
            return;
        }
        const left_px = @max(position[0], clip_rect.position[0]);
        const top_px = @max(position[1], clip_rect.position[1]);
        const right_px = @min(position[0] + size[0], clip_rect.position[0] + clip_rect.size[0]);
        const bottom_px = @min(position[1] + size[1], clip_rect.position[1] + clip_rect.size[1]);
        if (right_px <= left_px or bottom_px <= top_px) {
            return;
        }
        clipped_position = .{ left_px, top_px, position[2] };
        clipped_size = .{ right_px - left_px, bottom_px - top_px, size[2] };
    }

    const left = screenToClipX(clipped_position[0], width);
    const right = screenToClipX(clipped_position[0] + clipped_size[0], width);
    const top = screenToClipY(clipped_position[1], height);
    const bottom = screenToClipY(clipped_position[1] + clipped_size[1], height);
    const vertex_color = [4]f32{ clamp01(color[0]), clamp01(color[1]), clamp01(color[2]), 1.0 };
    const rect_size_radius = [4]f32{ size[0], size[1], pixel_size, -1.0 };
    const local_left = clipped_position[0] - position[0];
    const local_top = clipped_position[1] - position[1];
    const local_right = local_left + clipped_size[0];
    const local_bottom = local_top + clipped_size[1];

    const quad = [_]UiVertex{
        uiVertex(.{ left, top }, vertex_color, .{ local_left, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, top }, vertex_color, .{ local_right, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, bottom }, vertex_color, .{ local_right, local_bottom }, rect_size_radius, glyph_rows),
        uiVertex(.{ left, top }, vertex_color, .{ local_left, local_top }, rect_size_radius, glyph_rows),
        uiVertex(.{ right, bottom }, vertex_color, .{ local_right, local_bottom }, rect_size_radius, glyph_rows),
        uiVertex(.{ left, bottom }, vertex_color, .{ local_left, local_bottom }, rect_size_radius, glyph_rows),
    };
    try vertices.appendSlice(allocator, &quad);
}

fn glyphVertexRows(byte: u8) GlyphVertexRows {
    return glyph_vertex_rows[if (byte < glyph_vertex_rows.len) byte else ui_font.fallback_codepoint];
}

const glyph_vertex_rows = buildGlyphVertexRows();

fn buildGlyphVertexRows() [128]GlyphVertexRows {
    @setEvalBranchQuota(8_192);
    var table: [128]GlyphVertexRows = undefined;
    for (&table, 0..) |*entry, byte| {
        entry.* = buildGlyphVertexRowsForByte(@intCast(byte));
    }
    return table;
}

fn buildGlyphVertexRowsForByte(byte: u8) GlyphVertexRows {
    const rows = ui_font.glyphRows(byte);
    var glyph_rows = zeroGlyphRows();
    var visible = false;
    for (rows, 0..) |row_bits, row| {
        visible = visible or row_bits != 0;
        glyph_rows[row / 4][row % 4] = @floatFromInt(row_bits);
    }
    return .{ .rows = glyph_rows, .visible = visible };
}

fn zeroGlyphRows() [8][4]f32 {
    return .{
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
    };
}

fn uiVertex(position: [2]f32, color: [4]f32, local_position: [2]f32, rect_size_radius: [4]f32, glyph_rows: [8][4]f32) UiVertex {
    return .{
        .position = position,
        .color = color,
        .local_position = local_position,
        .rect_size_radius = rect_size_radius,
        .glyph_rows0 = glyph_rows[0],
        .glyph_rows1 = glyph_rows[1],
        .glyph_rows2 = glyph_rows[2],
        .glyph_rows3 = glyph_rows[3],
        .glyph_rows4 = glyph_rows[4],
        .glyph_rows5 = glyph_rows[5],
        .glyph_rows6 = glyph_rows[6],
        .glyph_rows7 = glyph_rows[7],
    };
}

pub fn screenToClipX(value: f32, width: u32) f32 {
    return (value / @as(f32, @floatFromInt(width))) * 2.0 - 1.0;
}

pub fn screenToClipY(value: f32, height: u32) f32 {
    return 1.0 - (value / @as(f32, @floatFromInt(height))) * 2.0;
}

fn scaleColor(color: [3]f32, scale: f32) [3]f32 {
    return .{
        clamp01(color[0] * scale),
        clamp01(color[1] * scale),
        clamp01(color[2] * scale),
    };
}

pub fn clamp01(value: f32) f32 {
    return @min(@max(value, 0.0), 1.0);
}
