const std = @import("std");

pub const FieldType = enum {
    boolean,
    int,
    float,
    vec3,
    string,
};

pub const ComponentFieldDefinition = struct {
    name: []const u8,
    value_type: FieldType,
};

pub const ComponentDefinition = struct {
    id: []const u8,
    version: u32 = 1,
    fields: []const ComponentFieldDefinition = &.{},
};

pub const SystemPhase = enum {
    startup,
    update,
    fixed_update,
    render,
};

pub const SystemDefinition = struct {
    id: []const u8,
    phase: SystemPhase = .update,
    reads: []const []const u8 = &.{},
    writes: []const []const u8 = &.{},
    before: []const []const u8 = &.{},
    after: []const []const u8 = &.{},
    runner: SystemRunner = .none,
};

pub const SystemRunner = union(enum) {
    none,
    luau: u32,
    native: u32,
};

pub const SystemProfileSnapshot = struct {
    id: []const u8,
    phase: SystemPhase,
    sample_count: u32,
    window_size: u32,
    last_ns: u64,
    rolling_average_ns: u64,
};

pub const ScheduledSystem = struct {
    registry_index: usize,
    id: []const u8,
    runner: SystemRunner,
};

pub const SystemBatch = struct {
    phase: SystemPhase,
    systems: []const ScheduledSystem,
};

pub const SystemSchedule = struct {
    allocator: std.mem.Allocator,
    batches: []const SystemBatch,

    pub fn deinit(self: *SystemSchedule) void {
        const allocator = self.allocator;
        for (self.batches) |batch| {
            for (batch.systems) |system| {
                allocator.free(system.id);
            }
            allocator.free(batch.systems);
        }
        allocator.free(self.batches);
        self.* = .{
            .allocator = allocator,
            .batches = &.{},
        };
    }

    pub fn batchCount(self: SystemSchedule) usize {
        return self.batches.len;
    }

    pub fn systemCount(self: SystemSchedule) usize {
        var count: usize = 0;
        for (self.batches) |batch| {
            count += batch.systems.len;
        }
        return count;
    }
};

pub const EntityHandle = struct {
    index: u32,
    generation: u32 = 0,
};

pub const EntityProvenance = enum {
    authored,
    spawned,
    engine_transient,
};

pub const CreateEntityOptions = struct {
    provenance: EntityProvenance = .spawned,
    emit_structural_events: bool = true,
};

pub const ResolvedComponentRow = struct {
    table_index: u32,
    row_index: u32,
};

pub const Entity = struct {
    id: []const u8,
    name: []const u8,
    generation: u32 = 0,
    provenance: EntityProvenance = .spawned,
    engine_transient_mark: u64 = 0,
};

pub const StructuralEventKind = enum {
    entity_created,
    entity_removed,
    component_added,
    component_removed,
};

pub const StructuralEvent = struct {
    kind: StructuralEventKind,
    entity: EntityHandle,
    component_id: ?[]const u8 = null,
};

pub const Transform = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    rotation: [3]f32 = .{ 0.0, 0.0, 0.0 },
    scale: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

pub const CubeRenderer = struct {
    color: [3]f32 = .{ 0.0, 0.56, 1.0 },
};

pub const GeometryPrimitive = struct {
    primitive: []const u8 = "box",
    segments: i32 = 0,
    rings: i32 = 0,
};

pub const SurfaceMaterial = struct {
    base_color: [3]f32 = .{ 0.0, 0.56, 1.0 },
};

pub const Camera = struct {
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const DirectionalLight = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
};

pub const Spin = struct {
    angular_velocity: [3]f32 = .{ 0.62, 1.0, 0.0 },
};

pub const RenderableCube = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    color: [3]f32,
    spin: [3]f32,
};

pub const RenderableMesh = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    primitive: []const u8,
    segments: i32,
    rings: i32,
    base_color: [3]f32,
    spin: [3]f32,
    casts_shadow: bool,
    receives_shadow: bool,
};

pub const RenderCamera = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    transform: Transform,
    fov_y_degrees: f32,
    near: f32,
    far: f32,
};

pub const RenderDirectionalLight = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    direction: [3]f32,
    color: [3]f32,
    intensity: f32,
    ambient: f32,
};

pub const RendererSettings = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    hdr: bool,
    tone_mapping: []const u8,
    exposure: f32,
    postprocess_enabled: bool,
    antialiasing: []const u8,
    bloom_enabled: bool,
    bloom_threshold: f32,
    bloom_intensity: f32,
    bloom_radius: f32,
    vignette_enabled: bool,
    vignette_strength: f32,
    vignette_radius: f32,
    chromatic_aberration_enabled: bool,
    chromatic_aberration_strength: f32,
};

pub const UiRectComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    corner_radius: f32 = 0.0,
};

pub const UiCanvasComponent = struct {
    design_size: [3]f32 = .{ 0.0, 0.0, 0.0 },
    scale_mode: []const u8 = "none",
};

pub const UiBorderComponent = struct {
    color: [3]f32 = .{ 0.0, 0.0, 0.0 },
    thickness: f32 = 1.0,
};

pub const UiTextComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: f32 = 2.0,
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    value: []const u8 = "",
};

pub const UiHitAreaComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
};

pub const UiCommandComponent = struct {
    command: []const u8,
};

pub const UiScrollViewComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    content_offset: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiHGroupComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    spacing: f32 = 0.0,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiVGroupComponent = UiHGroupComponent;

pub const UiTableComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    columns: i32 = 2,
    row_height: f32 = 1.0,
    column_gap: f32 = 0.0,
    row_gap: f32 = 0.0,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
    first_column_ratio: f32 = 0.5,
};

pub const UiStackComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    spacing: f32 = 0.0,
    direction: []const u8 = "vertical",
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiLayoutItemComponent = struct {
    parent: []const u8,
    order: i32 = 0,
    min_size: [3]f32 = .{ 0.0, 0.0, 0.0 },
    preferred_size: [3]f32 = .{ 0.0, 0.0, 0.0 },
    max_size: [3]f32 = .{ 0.0, 0.0, 0.0 },
    grow: f32 = 0.0,
    shrink: f32 = 0.0,
    @"align": []const u8 = "start",
    margin: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const UiSpacerComponent = struct {
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
};

pub const UiTextBlockComponent = struct {
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    horizontal_align: []const u8 = "start",
    vertical_align: []const u8 = "start",
};

pub const UiToggleComponent = struct {
    checked: bool = false,
};

pub const UiProgressBarComponent = struct {
    value: f32 = 0.0,
    max: f32 = 1.0,
    fill_color: [3]f32 = .{ 0.22, 0.714, 0.82 },
};

pub const UiSeparatorComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    size: [3]f32 = .{ 1.0, 1.0, 0.0 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
};

pub const UiCommandEventComponent = struct {
    command: []const u8,
    source: []const u8,
};

pub const UiCommandEvent = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    command: []const u8,
    source: []const u8,
};

pub const UiRect = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    is_button: bool,
};

pub const UiText = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: f32,
    color: [3]f32,
    value: []const u8,
};

pub const UiSeparator = struct {
    entity: EntityHandle,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
};

pub const InputPointerComponent = struct {
    position: [3]f32 = .{ 0.0, 0.0, 0.0 },
    delta: [3]f32 = .{ 0.0, 0.0, 0.0 },
    has_position: bool = false,
    primary_down: bool = false,
    primary_pressed: bool = false,
    primary_released: bool = false,
    secondary_down: bool = false,
    secondary_pressed: bool = false,
    secondary_released: bool = false,
    wheel_delta: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const InputKeyboardComponent = struct {
    ctrl_down: bool = false,
    shift_down: bool = false,
    alt_down: bool = false,
    super_down: bool = false,
    move_forward: bool = false,
    move_back: bool = false,
    move_left: bool = false,
    move_right: bool = false,
    move_up: bool = false,
    move_down: bool = false,
    editor_toggle_pressed: bool = false,
};

pub const InputFrameComponent = struct {
    ui_visible: bool = true,
    debug_overlay_visible: bool = false,
    viewport: [3]f32 = .{ 0.0, 0.0, 0.0 },
    pixel_scale: f32 = 1.0,
};

pub const ComponentValue = union(FieldType) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: []const u8,
};

pub const ComponentFieldValue = struct {
    name: []const u8,
    value: ComponentValue,
};
