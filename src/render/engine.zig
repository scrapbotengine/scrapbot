const std = @import("std");
const Io = std.Io;
const geometry = @import("../geometry.zig");
const runtime = @import("../runtime.zig");
const ui_layout = @import("../ui_layout.zig");
const ui_font = @import("../ui_font.zig");
const editor_state_types = @import("../editor/state.zig");
const editor_layout = @import("../editor/layout.zig");
const editor_render_chrome = @import("../editor/render_chrome.zig");
const editor_gizmo = @import("../editor/gizmo.zig");
const editor_input_routing = @import("../editor/input_routing.zig");
const editor_theme = @import("../editor/theme.zig");
const render_math = @import("math.zig");
const render_batching = @import("batching.zig");
const render_camera_module = @import("camera.zig");
const render_config_module = @import("config.zig");
const render_input = @import("input.zig");
const render_platform = @import("platform.zig");
const render_resources = @import("resources.zig");
const render_window = @import("window.zig");
const render_offscreen = @import("offscreen.zig");
const render_extract = @import("extract.zig");
const render_ecs = @import("ecs.zig");
const render_editor_extract = @import("editor/extract.zig");
const render_editor_input = @import("../editor/input.zig");
const render_editor_routing = @import("../editor/routing.zig");
const render_pipelines = @import("pipelines.zig");
const render_types = @import("types.zig");
const render_ui = @import("ui.zig");
const render_ui_draw = @import("ui_draw.zig");
const wgpu = @import("wgpu");

const is_supported_window_platform = render_platform.is_supported_window_platform;
const sdl = render_platform.sdl;

const cameraViewMatrix = render_math.cameraViewMatrix;
const lookAt = render_math.lookAt;
const isFiniteVec3 = render_math.isFiniteVec3;
const addVec3 = render_math.addVec3;
const subtractVec3 = render_math.subtractVec3;
const scaleVec3 = render_math.scaleVec3;
const dotVec3 = render_math.dotVec3;
const normalizeVec3 = render_math.normalizeVec3;
const vec3Length = render_math.vec3Length;
const subtractVec2 = render_math.subtractVec2;
const scaleVec2 = render_math.scaleVec2;
const dotVec2 = render_math.dotVec2;
const vec2Length = render_math.vec2Length;
const distancePointToScreenSegment = render_math.distancePointToScreenSegment;
const rotateDirection = render_math.rotateDirection;
const transformPoint = render_math.transformPoint;
const perspective = render_math.perspective;
const orthographic = render_math.orthographic;
const translation = render_math.translation;
const scaling = render_math.scaling;
const rotationX = render_math.rotationX;
const rotationY = render_math.rotationY;
const rotationZ = render_math.rotationZ;
const matMul = render_math.matMul;
pub const CameraState = render_camera_module.CameraState;
pub const FlyCameraState = render_camera_module.FlyCameraState;
const DirectionalLightState = render_camera_module.DirectionalLightState;
pub const cameraState = render_camera_module.cameraState;
const cameraStateForInput = render_camera_module.cameraStateForInput;
const directionalLightState = render_camera_module.directionalLightState;
pub const liveRunDeltaSecondsFromElapsedNs = render_camera_module.liveRunDeltaSecondsFromElapsedNs;
pub const updateFlyCamera = render_camera_module.updateFlyCamera;
const updateFlyCameraCapture = render_camera_module.updateFlyCameraCapture;
const validateCamera = render_camera_module.validateCamera;
const validateDirectionalLight = render_camera_module.validateDirectionalLight;
pub const PointerInput = render_input.PointerInput;
pub const KeyboardInput = render_input.KeyboardInput;
pub const FrameInput = render_input.FrameInput;
const normalizedPixelScale = render_input.normalizedPixelScale;
const framePixelScale = render_input.framePixelScale;
const logicalPixelsFromPhysical = render_input.logicalPixelsFromPhysical;
const frameInputWithOutputMetrics = render_input.frameInputWithOutputMetrics;
const frameInputWithDefaultOutputMetrics = render_input.frameInputWithDefaultOutputMetrics;
const toggleDebugOverlay = render_input.toggleDebugOverlay;
const DepthTarget = render_resources.DepthTarget;
const PostProcessTarget = render_resources.PostProcessTarget;
const ShadowTarget = render_resources.ShadowTarget;
const openGpu = render_resources.openGpu;
const chooseSurfaceFormat = render_resources.chooseSurfaceFormat;
const createStaticBuffer = render_resources.createStaticBuffer;
const writeUniforms = render_resources.writeUniforms;
const writePostProcessUniforms = render_resources.writeUniforms;
const WindowSurface = render_window.Surface;
const updatePointerFromWindow = render_window.updatePointerFromWindow;
const configureSurfaceFromWindow = render_window.configureSurfaceFromWindow;
const RenderOutputFormat = render_offscreen.OutputFormat;
const imageFormatFromPath = render_offscreen.imageFormatFromPath;
const alignedOutputBytesPerRow = render_offscreen.alignedOutputBytesPerRow;
const handleBufferMap = render_offscreen.handleBufferMap;
const write24BitBmp = render_offscreen.write24BitBmp;
const write24BitPng = render_offscreen.write24BitPng;
const extractSceneUiInto = render_extract.extractSceneUiInto;
const createMeshPipeline = render_pipelines.createMesh;
const createShadowPipeline = render_pipelines.createShadow;
const createUiPipeline = render_pipelines.createUi;
const createPostProcessPipeline = render_pipelines.createPostProcess;
const createBloomExtractPipeline = render_pipelines.createBloomExtract;
const createBloomBlurPipeline = render_pipelines.createBloomBlur;
const BatchPlan = render_batching.BatchPlan;
const BatchResources = render_batching.BatchResources;
pub const writeFrameInput = render_ui.writeFrameInput;
const setRenderFrameInput = render_ui.setRenderFrameInput;
const renderFrameInput = render_ui.renderFrameInput;
const setRenderUiButtonState = render_ui.setRenderUiButtonState;
const setRenderUiClip = render_ui.setRenderUiClip;
const renderUiButtonState = render_ui.renderUiButtonState;
const renderUiClip = render_ui.renderUiClip;
const uiBorder = render_ui.uiBorder;
const uiProgressBar = render_ui.uiProgressBar;
const uiToggleChecked = render_ui.uiToggleChecked;
const resolveUiLayout = render_ui.resolveUiLayout;
const combineUiClip = render_ui.combineUiClip;
const resolveUiScreenLayout = render_ui.resolveUiScreenLayout;
const sceneUiCanvasTransform = render_ui.sceneUiCanvasTransform;
const isEditorUiEntityId = render_ui.isEditorUiEntityId;
const applyUiCanvasLayout = render_ui.applyUiCanvasLayout;
const scaleUiVec3 = render_ui.scaleUiVec3;
const scaleUiSize = render_ui.scaleUiSize;
const scaleUiVec3By = render_ui.scaleUiVec3By;
const scaleUiClipBy = render_ui.scaleUiClipBy;
const scaleUiResolvedLayoutBy = render_ui.scaleUiResolvedLayoutBy;
const uiLayoutItemSize = render_ui.uiLayoutItemSize;
const hitTestUiRect = render_ui.hitTestUiRect;
const textPixelSize = render_ui.textPixelSize;
const resolveUiTextPosition = render_ui.resolveUiTextPosition;
const evaluateUiButtonState = render_ui.evaluateUiButtonState;
const buildUiVerticesInto = render_ui.buildUiVerticesInto;
const screenToClipX = render_ui.screenToClipX;
const screenToClipY = render_ui.screenToClipY;
const clamp01 = render_ui.clamp01;
const extractEditorShellInto = render_editor_extract.extractEditorShellInto;
const extractDebugOverlayInto = render_editor_extract.extractDebugOverlayInto;
const extractEditorTopBarInto = render_editor_extract.extractEditorTopBarInto;
const extractEditorBottomBarInto = render_editor_extract.extractEditorBottomBarInto;
const editorSystemProfileScrollCount = render_editor_extract.editorSystemProfileScrollCount;
const editorSystemMaxScrollY = render_editor_extract.editorSystemMaxScrollY;
const editorEntityMaxScrollY = render_editor_extract.editorEntityMaxScrollY;
const editorInspectorMaxScrollY = render_editor_extract.editorInspectorMaxScrollY;
const editorEntityMaxScroll = render_editor_extract.editorEntityMaxScroll;
const editorInspectorNeedsScroll = render_editor_extract.editorInspectorNeedsScroll;
const editorInspectorComponentContentHeight = render_editor_extract.editorInspectorComponentContentHeight;
const editorInspectorComponentCardHeight = render_editor_extract.editorInspectorComponentCardHeight;
const editorEntityHandleAt = render_editor_extract.editorEntityHandleAt;
const editorEntityComponentCount = render_editor_extract.editorEntityComponentCount;
const monotonicTimestampNs = render_editor_extract.monotonicTimestampNs;
const elapsedNanosecondsSince = render_editor_extract.elapsedNanosecondsSince;
const editorSystemNeedsScrollForInput = render_editor_extract.editorSystemNeedsScrollForInput;
const editorEntityNeedsScroll = render_editor_extract.editorEntityNeedsScroll;
const editorEntityTableContentHeight = render_editor_extract.editorEntityTableContentHeight;
const editorEntityVisibleRange = render_editor_extract.editorEntityVisibleRange;
pub const editorFrameState = render_editor_input.editorFrameState;
const editorTextInputFrame = render_editor_input.editorTextInputFrame;
const clampEditorSystemScroll = render_editor_input.clampEditorSystemScroll;
const clampEditorInspectorScroll = render_editor_input.clampEditorInspectorScroll;
const clampEditorEntityScroll = render_editor_input.clampEditorEntityScroll;
const applyEditorScrollRoute = render_editor_input.applyEditorScrollRoute;
const animateEditorScroll = render_editor_input.animateEditorScroll;
const ensureEditorSidebarWidths = render_editor_input.ensureEditorSidebarWidths;
const dragEditorSplitter = render_editor_input.dragEditorSplitter;
const applyEditorKeyboardEdits = render_editor_input.applyEditorKeyboardEdits;
pub const focusEditorTextInput = render_editor_input.focusEditorTextInput;
const editorTextInputFocusOptionsForProperty = render_editor_input.editorTextInputFocusOptionsForProperty;
pub const applyEditorTypedControlClick = render_editor_input.applyEditorTypedControlClick;
const editorFieldLooksLikeColor = render_editor_input.editorFieldLooksLikeColor;
const validatedEditorSelection = render_editor_input.validatedEditorSelection;
const validatedEditorFieldSelection = render_editor_input.validatedEditorFieldSelection;
const validatedEditorTextInput = render_editor_input.validatedEditorTextInput;
const commitEditorTextInput = render_editor_input.commitEditorTextInput;
const blurEditorTextInput = render_editor_input.blurEditorTextInput;
pub const makeEditorFieldSelection = render_editor_input.makeEditorFieldSelection;
pub const EditorCommand = render_editor_routing.EditorCommand;
pub const EditorUiRoute = render_editor_routing.EditorUiRoute;
pub const routeEditorUi = render_editor_routing.routeEditorUi;
pub const routeEditorSplitterAt = render_editor_routing.routeEditorSplitterAt;
const pickEditorInspectorProperty = render_editor_routing.pickEditorInspectorProperty;
const hitEditorChrome = render_editor_routing.hitEditorChrome;
const routeEditorScrollWheel = render_editor_routing.routeEditorScrollWheel;
pub const editorCursorKind = render_editor_routing.editorCursorKind;
pub const editorSidebarPanelRect = render_editor_extract.editorSidebarPanelRect;
pub const editorSystemVisibleRange = render_editor_extract.editorSystemVisibleRange;
pub const editorSystemListClipRect = render_editor_extract.editorSystemListClipRect;
pub const editorSystemListHitTestPoint = render_editor_extract.editorSystemListHitTestPoint;
pub const editorEntityListClipRect = render_editor_extract.editorEntityListClipRect;
pub const editorSystemVisibleRows = render_editor_extract.editorSystemVisibleRows;
pub const editorSystemTableContentHeight = render_editor_extract.editorSystemTableContentHeight;
pub const editorEntityHandlesEqual = render_editor_extract.editorEntityHandlesEqual;
pub const editorInspectorScrollClipRect = render_editor_extract.editorInspectorScrollClipRect;
pub const AntialiasingMode = render_config_module.AntialiasingMode;
pub const VignetteConfig = render_config_module.VignetteConfig;
pub const ChromaticAberrationConfig = render_config_module.ChromaticAberrationConfig;
pub const BloomConfig = render_config_module.BloomConfig;
pub const PostProcessConfig = render_config_module.PostProcessConfig;
pub const ToneMappingMode = render_config_module.ToneMappingMode;
pub const ColorConfig = render_config_module.ColorConfig;
pub const RenderConfig = render_config_module.RenderConfig;
const renderConfigFromWorld = render_config_module.fromWorld;
const editor_component_id_buffer_len = editor_state_types.component_id_buffer_len;
const editor_field_name_buffer_len = editor_state_types.field_name_buffer_len;
const editor_input_text_buffer_len = editor_state_types.input_text_buffer_len;
const editor_undo_capacity = editor_state_types.undo_capacity;
pub const EditorAxis = editor_state_types.EditorAxis;
pub const EditorFieldSelection = editor_state_types.EditorFieldSelection;
const EditorStoredValue = editor_state_types.EditorStoredValue;
const EditorFieldEditCommand = editor_state_types.EditorFieldEditCommand;
const EditorTextInputState = editor_state_types.EditorTextInputState;
const EditorTextInputFrame = editor_state_types.EditorTextInputFrame;
const EditorTextInputFocusOptions = editor_state_types.EditorTextInputFocusOptions;
pub const EditorState = editor_state_types.EditorState;
pub const EditorSplitter = editor_state_types.EditorSplitter;
pub const EditorScrollBoundary = editor_state_types.EditorScrollBoundary;
pub const EditorFrameState = editor_state_types.EditorFrameState;
pub const EditorUpdate = editor_state_types.EditorUpdate;
pub const EditorViewportBounds = editor_state_types.EditorViewportBounds;
pub const EditorError = editor_state_types.EditorError;

pub const EditorCursorKind = editor_input_routing.CursorKind;
const ScreenRect = editor_layout.ScreenRect;
const scaleScreenRect = editor_layout.scaleScreenRect;
const pointInsideScreenRect = editor_layout.pointInsideScreenRect;
const editorViewportWidth = editor_layout.viewportWidth;
const editorViewportHeight = editor_layout.viewportHeight;
const EditorSideWidths = editor_layout.SideWidths;
const EditorBodyLayout = editor_layout.BodyLayout;
const editorDefaultSideWidths = editor_layout.defaultSideWidths;
const editorSideWidths = editor_layout.sideWidths;
const clampEditorSideWidths = editor_layout.clampSideWidths;
const editorTopBarRect = editor_layout.topBarRect;
const editorBottomBarRect = editor_layout.bottomBarRect;
const editorBodyRect = editor_layout.bodyRect;
const editorBodyLayout = editor_layout.bodyLayout;
const editorLeftSidebarRect = editor_layout.leftSidebarRect;
const editorRightSidebarRect = editor_layout.rightSidebarRect;
const editorSplitterRect = editor_layout.splitterRect;
const editorSplitterHitRect = editor_layout.splitterHitRect;
const editorGameViewport = editor_layout.gameViewport;
pub const editorGameViewportBounds = editor_layout.gameViewportBounds;
const editorPlayButtonRect = editor_layout.playButtonRect;
const editorStepButtonRect = editor_layout.stepButtonRect;

pub const default_output_width = 640;
pub const default_output_height = 480;
const depth_format = wgpu.TextureFormat.depth24_plus;
const shadow_depth_format = wgpu.TextureFormat.depth32_float;
const bloom_level_count = 5;
const render_ui_button_state_component_id = render_ui.render_ui_button_state_component_id;
const render_ui_clip_component_id = render_ui.render_ui_clip_component_id;
const default_window_width = 1280;
const default_window_height = 720;
const editor_top_bar_height = editor_layout.top_bar_height;
const editor_bottom_bar_height = editor_layout.bottom_bar_height;
pub const editor_left_sidebar_target_width = editor_layout.left_sidebar_target_width;
const editor_left_sidebar_min_width = editor_layout.left_sidebar_min_width;
const editor_right_sidebar_target_width = editor_layout.right_sidebar_target_width;
const editor_right_sidebar_min_width = editor_layout.right_sidebar_min_width;
const editor_min_game_viewport_width = editor_layout.min_game_viewport_width;
const editor_splitter_width = editor_layout.splitter_width;
const editor_splitter_hit_width = editor_layout.splitter_hit_width;
pub const editor_performance_display_interval_ns = render_ecs.editor_performance_display_interval_ns;
pub const live_run_default_delta_seconds: f32 = 1.0 / 60.0;
pub const live_run_max_delta_seconds: f32 = 0.1;
pub const editor_system_text_size = editor_theme.system_text_size;
const editor_panel_padding_x = editor_layout.panel_padding_x;
const editor_panel_padding_y = editor_theme.panel_padding_y;
const editor_panel_section_gap = editor_theme.panel_section_gap;
pub const editor_panel_label_gap = editor_theme.panel_label_gap;
const editor_panel_bottom_padding = editor_theme.panel_bottom_padding;
pub const editor_system_row_stride = editor_theme.system_row_stride;
const editor_system_row_label_padding_x = editor_theme.system_row_label_padding_x;
const editor_system_row_duration_padding_x = editor_theme.system_row_duration_padding_x;
const editor_system_field_column_gap = editor_theme.system_field_column_gap;
const editor_system_card_padding_y = editor_theme.system_card_padding_y;
pub const editor_system_scroll_pixels_per_wheel = editor_theme.system_scroll_pixels_per_wheel;
const editor_system_scroll_smoothing = editor_theme.system_scroll_smoothing;
const editor_entity_text_size = editor_theme.entity_text_size;
pub const editor_entity_row_stride = editor_theme.entity_row_stride;
pub const editor_entity_row_label_padding_x = editor_theme.entity_row_label_padding_x;
const editor_entity_row_component_padding_x = editor_theme.entity_row_component_padding_x;
const editor_entity_field_column_gap = editor_theme.entity_field_column_gap;
pub const editor_entity_card_padding_y = editor_theme.entity_card_padding_y;
pub const editor_left_panel_gap = editor_theme.left_panel_gap;
const editor_entity_panel_min_height = editor_theme.entity_panel_min_height;
const editor_system_panel_min_height = editor_theme.system_panel_min_height;
const editor_scrollbar_width = editor_theme.scrollbar_width;
const editor_scrollbar_gap = editor_theme.scrollbar_gap;
pub const render_system_profile_window_frames = render_ecs.render_system_profile_window_frames;
pub const editor_control_button_width = editor_layout.control_button_width;
pub const editor_control_button_height = editor_layout.control_button_height;
const editor_control_button_gap = editor_layout.control_button_gap;
pub const editor_bar_text_offset_y = editor_theme.bar_text_offset_y;
const editor_top_fps_x = editor_theme.top_fps_x;
pub const editor_panel_corner_radius = editor_theme.panel_corner_radius;
const editor_sidebar_panel_margin = editor_theme.sidebar_panel_margin;
pub const editor_button_corner_radius = editor_theme.button_corner_radius;
pub const editor_command_play_toggle = editor_theme.command_play_toggle;
const editor_command_step = editor_theme.command_step;
pub const editor_command_splitter_left = editor_theme.command_splitter_left;
const editor_command_splitter_right = editor_theme.command_splitter_right;
pub const editor_inspector_text_size = editor_render_chrome.inspector_text_size;
const editor_inspector_line_stride = editor_render_chrome.inspector_line_stride;
pub const editor_inspector_field_row_margin_y = editor_render_chrome.inspector_field_row_margin_y;
pub const editor_inspector_card_gap = editor_render_chrome.inspector_card_gap;
pub const editor_inspector_separator_height = editor_render_chrome.inspector_separator_height;
pub const editor_inspector_card_padding_x = editor_render_chrome.inspector_card_padding_x;
pub const editor_inspector_card_padding_y = editor_render_chrome.inspector_card_padding_y;
const editor_inspector_field_column_gap = editor_render_chrome.inspector_field_column_gap;
const editor_inspector_column_min_width = editor_render_chrome.inspector_column_min_width;
pub const editor_inspector_input_padding_x = editor_render_chrome.inspector_input_padding_x;
pub const editor_inspector_input_padding_y = editor_render_chrome.inspector_input_padding_y;
const editor_inspector_input_gap = editor_render_chrome.inspector_input_gap;
pub const editor_inspector_input_border_thickness = editor_render_chrome.inspector_input_border_thickness;
pub const editor_inspector_input_text_offset_x = editor_render_chrome.inspector_input_text_offset_x;
pub const editor_inspector_input_text_offset_y = editor_render_chrome.inspector_input_text_offset_y;
const editor_inspector_input_height = editor_render_chrome.inspector_input_height;
pub const editor_inspector_input_cell_padding = editor_render_chrome.inspector_input_cell_padding;
pub const editor_inspector_field_row_height = editor_render_chrome.inspector_field_row_height;
pub const editor_inspector_field_row_stride = editor_render_chrome.inspector_field_row_stride;
pub const editor_inspector_input_corner_radius = editor_render_chrome.inspector_input_corner_radius;
const editor_inspector_caret_width = editor_render_chrome.inspector_caret_width;
pub const editor_inspector_field_control_offset_y = editor_render_chrome.inspector_field_control_offset_y;
const editor_inspector_field_text_offset_y = editor_render_chrome.inspector_field_text_offset_y;
const editor_inspector_selection_padding_y = editor_render_chrome.inspector_selection_padding_y;
const editor_inspector_toggle_width = editor_render_chrome.inspector_toggle_width;
const editor_inspector_swatch_size = editor_render_chrome.inspector_swatch_size;
const editor_inspector_lane_label_width = editor_render_chrome.inspector_lane_label_width;
const editor_inspector_lane_label_gap = editor_render_chrome.inspector_lane_label_gap;
pub const editorTextHeight = editor_render_chrome.textHeight;
pub const editorTextWidth = editor_render_chrome.textWidth;
const EditorInspectorFieldLayout = editor_render_chrome.InspectorFieldLayout;
pub const editorInspectorFieldLayout = editor_render_chrome.inspectorFieldLayout;
const fitEditorTextToWidth = editor_render_chrome.fitTextToWidth;
const editorPanelTextPosition = editor_render_chrome.panelTextPosition;
const insetScreenRect = editor_render_chrome.insetScreenRect;
const editor_geometry_primitives = editor_theme.geometry_primitives;
const editor_color_channels = editor_theme.color_channels;
const editor_vec3_lane_labels = editor_theme.vec3_lane_labels;
const editor_gizmo_axis_length = editor_gizmo.axis_length;
const editor_gizmo_pick_radius_px = editor_gizmo.pick_radius_px;

pub const editor_palette = editor_theme.palette;

pub const RenderError = render_types.RenderError;

pub const Stats = struct {
    renderables: usize,
    render_batches: usize,
    ui_rects: usize,
    ui_texts: usize,
};

pub const WindowOptions = struct {
    max_frames: ?u32 = null,
    editor: bool = false,
    hidden: bool = false,
    scene_reload: ?SceneReloadHook = null,
    frame_update: ?FrameUpdateHook = null,
};

pub const ImageRenderOptions = struct {
    frames: u32 = 1,
    delta_seconds: f32 = live_run_default_delta_seconds,
    width: u32 = default_output_width,
    height: u32 = default_output_height,
    pixel_scale: f32 = 1.0,
    frame_input: FrameInput = .{},
    frame_update: ?FrameUpdateHook = null,
};

pub const Scene = struct {
    world: *runtime.World,
};

pub const SceneReloadHook = struct {
    context: *anyopaque,
    poll: *const fn (context: *anyopaque) ?Scene,
};

pub const FrameUpdateHook = struct {
    context: *anyopaque,
    step: *const fn (context: *anyopaque, delta_seconds: f32, input: *FrameInput) void,
};

pub fn isEditorToggleShortcut(key: sdl.ScrapbotSdlKey, ctrl_down: bool) bool {
    return key == sdl.SCRAPBOT_SDL_KEY_TAB and ctrl_down;
}

fn updateKeyboardModifiers(keyboard: *KeyboardInput, event: sdl.ScrapbotSdlEvent) void {
    keyboard.ctrl_down = event.ctrl_down != 0;
    keyboard.shift_down = event.shift_down != 0;
    keyboard.alt_down = event.alt_down != 0;
    keyboard.super_down = event.super_down != 0;
    keyboard.move_down = keyboard.ctrl_down;
}

fn updateKeyboardKeyState(keyboard: *KeyboardInput, key: sdl.ScrapbotSdlKey, down: bool) void {
    if (key == sdl.SCRAPBOT_SDL_KEY_W) {
        keyboard.move_forward = down;
    } else if (key == sdl.SCRAPBOT_SDL_KEY_S) {
        keyboard.move_back = down;
    } else if (key == sdl.SCRAPBOT_SDL_KEY_A) {
        keyboard.move_left = down;
    } else if (key == sdl.SCRAPBOT_SDL_KEY_D) {
        keyboard.move_right = down;
    } else if (key == sdl.SCRAPBOT_SDL_KEY_SPACE) {
        keyboard.move_up = down;
    } else if (key == sdl.SCRAPBOT_SDL_KEY_LCTRL or key == sdl.SCRAPBOT_SDL_KEY_RCTRL) {
        keyboard.move_down = down;
    }
}

fn updateEditorKeyboardActions(keyboard: *KeyboardInput, event: sdl.ScrapbotSdlEvent) void {
    if (event.kind != sdl.SCRAPBOT_SDL_EVENT_KEY_DOWN) {
        return;
    }
    if (event.key == sdl.SCRAPBOT_SDL_KEY_LEFT) {
        keyboard.editor_left_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_RIGHT) {
        keyboard.editor_right_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_HOME) {
        keyboard.editor_home_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_END) {
        keyboard.editor_end_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_BACKSPACE) {
        keyboard.editor_backspace_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_DELETE) {
        keyboard.editor_delete_pressed = true;
    } else if (event.key == sdl.SCRAPBOT_SDL_KEY_RETURN and event.repeat == 0) {
        keyboard.editor_enter_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.SCRAPBOT_SDL_KEY_A and event.ctrl_down != 0) {
        keyboard.editor_select_all_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.SCRAPBOT_SDL_KEY_Z and event.ctrl_down != 0 and event.shift_down == 0) {
        keyboard.editor_undo_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.SCRAPBOT_SDL_KEY_Z and event.ctrl_down != 0 and event.shift_down != 0) {
        keyboard.editor_redo_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.SCRAPBOT_SDL_KEY_Y and event.ctrl_down != 0) {
        keyboard.editor_redo_pressed = true;
    }
}

pub fn updateEditorState(allocator: std.mem.Allocator, world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!EditorUpdate {
    state.selected_entity = validatedEditorSelection(world, state.selected_entity);
    state.selected_property = validatedEditorFieldSelection(world, state.selected_entity, state.selected_property);
    state.text_input = validatedEditorTextInput(world, state.selected_entity, state.text_input);
    if (!input.debug_overlay_visible) {
        try blurEditorTextInput(world, state);
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
        return .{};
    }
    ensureEditorSidebarWidths(state, input);
    var effective_input = input;
    effective_input.editor.selected_entity = state.selected_entity;
    effective_input.editor.left_sidebar_width = state.left_sidebar_width;
    effective_input.editor.right_sidebar_width = state.right_sidebar_width;
    effective_input.editor.system_scroll_y = state.system_scroll_y;
    effective_input.editor.entity_scroll_y = state.entity_scroll_y;
    effective_input.editor.inspector_scroll_y = state.inspector_scroll_y;
    effective_input.editor.text_input = editorTextInputFrame(world, state.selected_entity, state.text_input);

    const profile_count = editorSystemProfileScrollCount(input);
    clampEditorSystemScroll(state, effective_input, profile_count);
    clampEditorEntityScroll(state, world, effective_input);
    clampEditorInspectorScroll(state, world, effective_input);

    const wheel_y = input.pointer.wheel_delta[1];
    const scroll_route = if (wheel_y != 0.0 and
        input.pointer.has_position and
        !std.math.isNan(input.pointer.position[0]) and
        !std.math.isNan(input.pointer.position[1]))
        try routeEditorScrollWheel(allocator, world, state, effective_input, profile_count, wheel_y)
    else
        null;

    if (wheel_y == 0.0 or scroll_route == null) {
        state.system_scroll_boundary = .none;
        state.entity_scroll_boundary = .none;
        state.inspector_scroll_boundary = .none;
    }

    if (scroll_route) |route| {
        switch (route) {
            .system_scroll => |scroll| {
                applyEditorScrollRoute(&state.system_scroll_y, &state.system_scroll_target_y, &state.system_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            .entity_scroll => |scroll| {
                applyEditorScrollRoute(&state.entity_scroll_y, &state.entity_scroll_target_y, &state.entity_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            .inspector_scroll => |scroll| {
                applyEditorScrollRoute(&state.inspector_scroll_y, &state.inspector_scroll_target_y, &state.inspector_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            else => {},
        }
    }

    animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
    animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
    animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);

    if (try applyEditorKeyboardEdits(world, state, input)) {
        return .{ .consumed_pointer = true };
    }

    if (!input.pointer.has_position) {
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.has_last_pointer = false;
        return .{};
    }

    const release_consumes = input.pointer.primary_released and
        (state.captured_pointer or state.dragging_axis != .none or state.dragging_splitter != .none or hitEditorChrome(input));
    if (input.pointer.primary_released) {
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
    }

    if (state.dragging_splitter != .none and input.pointer.primary_down) {
        dragEditorSplitter(state, input);
        return .{ .consumed_pointer = true };
    }

    if (input.pointer.primary_pressed) {
        const picked_property = try pickEditorInspectorProperty(world, effective_input);
        if (state.text_input.active and (picked_property == null or !state.text_input.selection.sameInput(picked_property.?))) {
            try commitEditorTextInput(world, state);
            effective_input.editor.text_input = editorTextInputFrame(world, state.selected_entity, state.text_input);
        }
        if (try routeEditorUi(allocator, world, state.system_scroll_target_y, state.entity_scroll_target_y, state.inspector_scroll_target_y, effective_input, profile_count)) |route| {
            switch (route) {
                .splitter => |splitter| {
                    state.dragging_splitter = splitter;
                    state.captured_pointer = true;
                    state.last_pointer = input.pointer.position;
                    state.has_last_pointer = true;
                    return .{ .consumed_pointer = true };
                },
                .command => |command| {
                    state.captured_pointer = true;
                    return switch (command) {
                        .play_toggle => blk: {
                            state.paused = !state.paused;
                            break :blk .{ .consumed_pointer = true };
                        },
                        .step => blk: {
                            state.paused = true;
                            break :blk .{ .consumed_pointer = true, .step_once = true };
                        },
                    };
                },
                .entity_select => |entity| {
                    _ = world.entity(entity) catch {
                        state.captured_pointer = true;
                        return .{ .consumed_pointer = true };
                    };
                    state.selected_entity = entity;
                    state.selected_property = .{};
                    state.text_input = .{};
                    state.captured_pointer = true;
                    return .{ .consumed_pointer = true };
                },
                .system_scroll => {},
                .entity_scroll => {},
                .inspector_scroll => {},
            }
        }
        if (picked_property) |property| {
            if (try applyEditorTypedControlClick(world, state, property)) {
                state.captured_pointer = true;
                return .{ .consumed_pointer = true };
            }
            try focusEditorTextInput(world, state, property, editorTextInputFocusOptionsForProperty(world, property));
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }
        if (hitEditorChrome(input)) {
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }

        if (state.selected_entity) |selected| {
            const axis = try pickEditorGizmoAxis(world, selected, input);
            if (axis != .none) {
                state.dragging_axis = axis;
                state.captured_pointer = true;
                state.last_pointer = input.pointer.position;
                state.has_last_pointer = true;
                return .{ .consumed_pointer = true };
            }
        }

        const previous_selection = state.selected_entity;
        state.selected_entity = try pickRenderableEntity(world, input);
        if (previous_selection == null or state.selected_entity == null or previous_selection.?.index != state.selected_entity.?.index or previous_selection.?.generation != state.selected_entity.?.generation) {
            state.selected_property = .{};
            state.text_input = .{};
        }
        state.captured_pointer = state.selected_entity != null;
        return .{ .consumed_pointer = state.selected_entity != null };
    }

    if (input.pointer.primary_down and state.dragging_axis != .none) {
        try dragSelectedEntity(world, state, input);
        return .{ .consumed_pointer = true };
    }

    if (release_consumes) {
        return .{ .consumed_pointer = true };
    }

    state.has_last_pointer = false;
    return .{};
}

pub fn stats(allocator: std.mem.Allocator, scene: Scene) RenderError!Stats {
    var plan = try BatchPlan.build(allocator, scene.world);
    defer plan.deinit();

    return .{
        .renderables = plan.renderables.len,
        .render_batches = plan.batches.len,
        .ui_rects = scene.world.uiRectCount(),
        .ui_texts = scene.world.uiTextCount(),
    };
}

const UiButtonState = render_ui.UiButtonState;
const UiClipRect = render_ui.UiClipRect;
const UiCanvasTransform = render_ui.UiCanvasTransform;
const UiBorder = render_ui.UiBorder;
const UiProgressBar = render_ui.UiProgressBar;

pub fn renderDemoImage(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene) !void {
    try renderDemoImageWithInput(io, allocator, output_path, scene, .{});
}

pub fn renderDemoImageWithInput(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene, frame_input: FrameInput) !void {
    try renderDemoImageFrames(io, allocator, output_path, scene, .{ .frame_input = frame_input });
}

pub fn renderDemoImageFrames(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene, options: ImageRenderOptions) !void {
    try renderDemoOutputFrames(io, allocator, output_path, scene, options, try imageFormatFromPath(output_path));
}

fn renderDemoOutputFrames(
    io: Io,
    allocator: std.mem.Allocator,
    output_path: []const u8,
    scene: Scene,
    options: ImageRenderOptions,
    output_format: RenderOutputFormat,
) !void {
    if (options.width == 0 or options.height == 0) {
        return RenderError.InvalidScene;
    }
    const output_extent = wgpu.Extent3D{
        .width = options.width,
        .height = options.height,
        .depth_or_array_layers = 1,
    };
    const output_bytes_per_row = alignedOutputBytesPerRow(options.width);
    if (output_bytes_per_row > std.math.maxInt(u32)) {
        return RenderError.InvalidScene;
    }
    const output_size = output_bytes_per_row * @as(usize, options.height);

    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var gpu = try openGpu(instance, null);
    defer gpu.deinit();

    const texture_format = wgpu.TextureFormat.bgra8_unorm_srgb;
    const target_texture = gpu.device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh target"),
        .size = output_extent,
        .format = texture_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }) orelse return RenderError.NoDevice;
    defer target_texture.release();

    const target_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh target view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer target_view.release();

    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, texture_format, scene);
    defer demo.deinit();

    var depth = try DepthTarget.create(gpu.device, options.width, options.height);
    defer depth.deinit();

    const staging_buffer = gpu.device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh staging buffer"),
        .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }) orelse return RenderError.NoDevice;
    defer staging_buffer.release();

    const frame_count = @max(options.frames, 1);
    var frame_index: u32 = 0;
    while (frame_index < frame_count) : (frame_index += 1) {
        var input = frameInputWithOutputMetrics(options.frame_input, options.width, options.height, options.pixel_scale);
        input.delta_seconds = options.delta_seconds;
        input.system_profile_count_hint = demo.renderSystemProfileCount();
        if (options.frame_update) |frame_update| {
            frame_update.step(frame_update.context, options.delta_seconds, &input);
        }

        try demo.draw(gpu.device, gpu.queue, target_view, depth.view orelse return RenderError.NoDevice, .{
            .width = options.width,
            .height = options.height,
            .scene = scene,
            .input = input,
        });
        instance.processEvents();
    }

    const encoder = gpu.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh copy encoder"),
    }) orelse return RenderError.NoDevice;
    defer encoder.release();

    encoder.copyTextureToBuffer(
        &wgpu.TexelCopyTextureInfo{
            .origin = .{},
            .texture = target_texture,
        },
        &wgpu.TexelCopyBufferInfo{
            .layout = .{
                .bytes_per_row = @intCast(output_bytes_per_row),
                .rows_per_image = options.height,
            },
            .buffer = staging_buffer,
        },
        &output_extent,
    );

    const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh copy command buffer"),
    }) orelse return RenderError.NoDevice;
    defer command_buffer.release();

    const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
    gpu.queue.submit(&command_buffers);

    var map_complete = false;
    var map_status: wgpu.MapAsyncStatus = .unknown;
    _ = staging_buffer.mapAsync(wgpu.MapModes.read, 0, output_size, .{
        .callback = handleBufferMap,
        .userdata1 = @ptrCast(&map_complete),
        .userdata2 = @ptrCast(&map_status),
    });

    instance.processEvents();
    while (!map_complete) {
        instance.processEvents();
    }

    if (map_status != .success) {
        return RenderError.BufferMapFailed;
    }

    const mapped: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, output_size) orelse return RenderError.BufferMapFailed));
    defer staging_buffer.unmap();

    switch (output_format) {
        .bmp => try write24BitBmp(io, allocator, output_path, mapped[0..output_size], options.width, options.height, output_bytes_per_row),
        .png => try write24BitPng(io, allocator, output_path, mapped[0..output_size], options.width, options.height, output_bytes_per_row),
    }
}

pub fn runDemoWindow(allocator: std.mem.Allocator, title: []const u8, options: WindowOptions, initial_scene: Scene) !void {
    if (!is_supported_window_platform) {
        return RenderError.WindowingUnsupported;
    }

    const title_z = try allocator.dupeZ(u8, title);
    defer allocator.free(title_z);

    if (sdl.scrapbot_sdl_init_video() == 0) {
        return RenderError.SdlInitFailed;
    }
    defer sdl.scrapbot_sdl_quit();

    const window = sdl.scrapbot_sdl_create_window(title_z.ptr, default_window_width, default_window_height, @intFromBool(options.hidden)) orelse return RenderError.WindowCreateFailed;
    defer sdl.scrapbot_sdl_destroy_window(window);
    _ = sdl.scrapbot_sdl_start_text_input(window);

    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var window_surface = try WindowSurface.create(instance, window);
    defer window_surface.deinit();
    const surface = window_surface.surface;

    var gpu = try openGpu(instance, surface);
    defer gpu.deinit();

    var capabilities: wgpu.SurfaceCapabilities = undefined;
    if (surface.getCapabilities(gpu.adapter, &capabilities) != .success) {
        return RenderError.SurfaceFailed;
    }
    defer capabilities.freeMembers();

    const surface_format = chooseSurfaceFormat(capabilities) orelse return RenderError.NoSurfaceFormat;
    var scene = initial_scene;
    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, scene);
    defer demo.deinit();
    var fly_camera = FlyCameraState{};

    var depth = DepthTarget{};
    defer depth.deinit();

    var width: u32 = 0;
    var height: u32 = 0;
    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
    try depth.ensure(gpu.device, width, height);

    var running = true;
    var frame_count: u32 = 0;
    var input: FrameInput = .{ .debug_overlay_visible = options.editor };
    var relative_mouse_enabled = false;
    const resize_ew_cursor: ?*anyopaque = sdl.scrapbot_sdl_create_resize_ew_cursor();
    defer if (resize_ew_cursor) |cursor| sdl.scrapbot_sdl_destroy_cursor(cursor);
    var active_cursor_kind: EditorCursorKind = .default;
    var last_frame_ticks = sdl.scrapbot_sdl_get_ticks_ns();
    var last_performance_display_ticks: u64 = 0;
    var smoothed_fps: f32 = 0.0;
    var displayed_fps: f32 = 0.0;
    while (running) {
        input.beginFrame();

        var event: sdl.ScrapbotSdlEvent = undefined;
        while (sdl.scrapbot_sdl_poll_event(&event) != 0) {
            switch (event.kind) {
                sdl.SCRAPBOT_SDL_EVENT_QUIT => running = false,
                sdl.SCRAPBOT_SDL_EVENT_KEY_DOWN => {
                    updateKeyboardKeyState(&input.keyboard, event.key, true);
                    updateKeyboardModifiers(&input.keyboard, event);
                    updateEditorKeyboardActions(&input.keyboard, event);
                    if (event.repeat == 0 and isEditorToggleShortcut(event.key, event.ctrl_down != 0)) {
                        toggleDebugOverlay(&input);
                    }
                },
                sdl.SCRAPBOT_SDL_EVENT_KEY_UP => {
                    updateKeyboardKeyState(&input.keyboard, event.key, false);
                    updateKeyboardModifiers(&input.keyboard, event);
                },
                sdl.SCRAPBOT_SDL_EVENT_MOUSE_MOTION => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    input.pointer.delta[0] += event.xrel;
                    input.pointer.delta[1] += event.yrel;
                },
                sdl.SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    if (event.button == sdl.scrapbot_sdl_button_left()) {
                        input.pointer.primary_down = true;
                        input.pointer.primary_pressed = true;
                    } else if (event.button == sdl.scrapbot_sdl_button_right()) {
                        input.pointer.secondary_down = true;
                        input.pointer.secondary_pressed = true;
                    }
                },
                sdl.SCRAPBOT_SDL_EVENT_MOUSE_BUTTON_UP => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    if (event.button == sdl.scrapbot_sdl_button_left()) {
                        input.pointer.primary_down = false;
                        input.pointer.primary_released = true;
                    } else if (event.button == sdl.scrapbot_sdl_button_right()) {
                        input.pointer.secondary_down = false;
                        input.pointer.secondary_released = true;
                    }
                },
                sdl.SCRAPBOT_SDL_EVENT_MOUSE_WHEEL => {
                    input.pointer.wheel_delta[0] += event.wheel_x;
                    input.pointer.wheel_delta[1] += event.wheel_y;
                },
                sdl.SCRAPBOT_SDL_EVENT_TEXT_INPUT => {
                    input.appendTextInput(std.mem.sliceTo(event.text[0..], 0));
                },
                sdl.SCRAPBOT_SDL_EVENT_WINDOW_RESIZED => {
                    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
                    try depth.ensure(gpu.device, width, height);
                },
                else => {},
            }
        }

        if (!running) {
            break;
        }

        const frame_ticks = sdl.scrapbot_sdl_get_ticks_ns();
        const elapsed_ns = if (frame_ticks > last_frame_ticks) frame_ticks - last_frame_ticks else 0;
        if (frame_ticks > last_frame_ticks) {
            last_frame_ticks = frame_ticks;
            const instant_fps = 1_000_000_000.0 / @as(f32, @floatFromInt(elapsed_ns));
            smoothed_fps = if (smoothed_fps == 0.0) instant_fps else smoothed_fps * 0.9 + instant_fps * 0.1;
            if (displayed_fps == 0.0 or frame_ticks - last_performance_display_ticks >= editor_performance_display_interval_ns) {
                displayed_fps = smoothed_fps;
                last_performance_display_ticks = frame_ticks;
            }
            input.fps = displayed_fps;
        }

        if (options.scene_reload) |reload| {
            if (reload.poll(reload.context)) |reloaded_scene| {
                const reloaded_demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, reloaded_scene);
                demo.deinit();
                demo = reloaded_demo;
                scene = reloaded_scene;
                fly_camera.reset();
            }
        }

        const delta_seconds = liveRunDeltaSecondsFromElapsedNs(elapsed_ns);
        input.delta_seconds = delta_seconds;
        input.viewport_width = @floatFromInt(width);
        input.viewport_height = @floatFromInt(height);
        input.pixel_scale = 1.0;
        input.system_profile_count_hint = demo.renderSystemProfileCount();
        const should_enable_relative_mouse = updateFlyCameraCapture(&fly_camera, input);
        if (should_enable_relative_mouse != relative_mouse_enabled) {
            _ = sdl.scrapbot_sdl_set_window_relative_mouse_mode(window, @intFromBool(should_enable_relative_mouse));
            relative_mouse_enabled = should_enable_relative_mouse;
        }
        input.camera_override = updateFlyCamera(&fly_camera, scene.world, input, delta_seconds) catch null;
        if (options.frame_update) |frame_update| {
            frame_update.step(frame_update.context, delta_seconds, &input);
        }
        const desired_cursor = if (relative_mouse_enabled) EditorCursorKind.default else editorCursorKind(allocator, input) catch .default;
        if (desired_cursor != active_cursor_kind) {
            setEditorCursor(desired_cursor, resize_ew_cursor);
            active_cursor_kind = desired_cursor;
        }

        try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
        try depth.ensure(gpu.device, width, height);
        try drawMeshToSurface(surface, gpu.device, gpu.queue, &demo, depth.view orelse return RenderError.NoDevice, .{
            .width = width,
            .height = height,
            .scene = scene,
            .input = input,
        });
        instance.processEvents();

        frame_count += 1;
        if (options.max_frames) |max_frames| {
            if (frame_count >= max_frames) {
                break;
            }
        }

        sdl.scrapbot_sdl_delay_ms(1);
    }
    if (relative_mouse_enabled) {
        _ = sdl.scrapbot_sdl_set_window_relative_mouse_mode(window, 0);
    }
}

fn setEditorCursor(kind: EditorCursorKind, resize_ew_cursor: ?*anyopaque) void {
    switch (kind) {
        .default => sdl.scrapbot_sdl_set_default_cursor(),
        .resize_ew => {
            if (resize_ew_cursor) |cursor| {
                sdl.scrapbot_sdl_set_cursor(cursor);
            } else {
                sdl.scrapbot_sdl_set_default_cursor();
            }
        },
    }
}

const FrameConfig = struct {
    width: u32,
    height: u32,
    scene: Scene,
    input: FrameInput = .{},

    fn gameViewport(self: FrameConfig) ScreenRect {
        const logical = editorGameViewport(frameInputWithDefaultOutputMetrics(self.input, self.width, self.height));
        return scaleScreenRect(logical, framePixelScale(self.input));
    }
};

const InstanceConfig = struct {
    width: f32,
    height: f32,
    mesh: *const runtime.RenderableMesh,
    camera: CameraState,
    light_view_projection: [16]f32,
};

const BloomViews = [bloom_level_count]*wgpu.TextureView;

const RenderSystemContext = struct {
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    target_view: *wgpu.TextureView,
    depth_view: *wgpu.TextureView,
    frame: FrameConfig,
};

pub const RenderEcsState = render_ecs.RenderEcsState;
pub const render_draw_batch_component_id = render_ecs.render_draw_batch_component_id;
pub const render_extract_system_id = render_ecs.render_extract_system_id;
pub const render_prepare_meshes_system_id = render_ecs.render_prepare_meshes_system_id;
pub const render_queue_meshes_system_id = render_ecs.render_queue_meshes_system_id;
pub const render_interact_ui_system_id = render_ecs.render_interact_ui_system_id;
pub const render_prepare_ui_system_id = render_ecs.render_prepare_ui_system_id;
pub const render_queue_ui_system_id = render_ecs.render_queue_ui_system_id;
pub const render_draw_meshes_system_id = render_ecs.render_draw_meshes_system_id;
pub const mapWorldError = render_ecs.mapWorldError;

const UiDrawResources = render_ui_draw.UiDrawResources;
const InstanceAttributes = render_types.InstanceAttributes;

const MeshDemo = struct {
    allocator: std.mem.Allocator,
    texture_format: wgpu.TextureFormat,
    scene_texture_format: wgpu.TextureFormat,
    pipeline: *wgpu.RenderPipeline,
    shadow_pipeline: *wgpu.RenderPipeline,
    ui_pipeline: *wgpu.RenderPipeline,
    postprocess_pipeline: *wgpu.RenderPipeline,
    bloom_extract_pipeline: *wgpu.RenderPipeline,
    bloom_blur_pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    postprocess_bind_group_layout: *wgpu.BindGroupLayout,
    bloom_bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    shadow_pipeline_layout: *wgpu.PipelineLayout,
    ui_pipeline_layout: *wgpu.PipelineLayout,
    postprocess_pipeline_layout: *wgpu.PipelineLayout,
    bloom_pipeline_layout: *wgpu.PipelineLayout,
    frame_uniform_buffer: *wgpu.Buffer,
    postprocess_uniform_buffer: *wgpu.Buffer,
    bloom_extract_uniform_buffer: *wgpu.Buffer,
    bloom_blur_x_uniform_buffer: *wgpu.Buffer,
    bloom_blur_y_uniform_buffer: *wgpu.Buffer,
    bind_group: *wgpu.BindGroup,
    shadow_target: ShadowTarget,
    shadow_sampler: *wgpu.Sampler,
    postprocess_sampler: *wgpu.Sampler,
    postprocess_target: PostProcessTarget = .{},
    bloom_extract_targets: [bloom_level_count]PostProcessTarget = [_]PostProcessTarget{.{}} ** bloom_level_count,
    bloom_ping_targets: [bloom_level_count]PostProcessTarget = [_]PostProcessTarget{.{}} ** bloom_level_count,
    bloom_pong_targets: [bloom_level_count]PostProcessTarget = [_]PostProcessTarget{.{}} ** bloom_level_count,
    render_state: RenderEcsState,
    batches: []BatchResources,
    ui_draw: UiDrawResources = .{},
    ui_vertices: std.ArrayList(UiVertex) = .empty,
    ui_layout_cache: ui_layout.LayoutCache,

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        texture_format: wgpu.TextureFormat,
        scene: Scene,
    ) RenderError!MeshDemo {
        const initial_render_config = renderConfigFromWorld(scene.world);
        const scene_texture_format = initial_render_config.sceneTextureFormat(texture_format);

        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex | wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(FrameUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .depth,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .comparison,
                },
            },
        };
        const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot mesh bind group layout"),
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group_layout.release();

        const postprocess_bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(PostProcessUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .filtering,
                },
            },
            .{
                .binding = 3,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 4,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 5,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 6,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 7,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
        };
        const postprocess_bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot postprocess bind group layout"),
            .entry_count = postprocess_bind_group_layout_entries.len,
            .entries = &postprocess_bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer postprocess_bind_group_layout.release();

        const bloom_bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(PostProcessUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .filtering,
                },
            },
        };
        const bloom_bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot bloom bind group layout"),
            .entry_count = bloom_bind_group_layout_entries.len,
            .entries = &bloom_bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bloom_bind_group_layout.release();

        const frame_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot frame uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(FrameUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer frame_uniform_buffer.release();

        const postprocess_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot postprocess uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(PostProcessUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer postprocess_uniform_buffer.release();

        const bloom_extract_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot bloom extract uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(PostProcessUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer bloom_extract_uniform_buffer.release();

        const bloom_blur_x_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot bloom horizontal blur uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(PostProcessUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer bloom_blur_x_uniform_buffer.release();

        const bloom_blur_y_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot bloom vertical blur uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(PostProcessUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer bloom_blur_y_uniform_buffer.release();

        var initial_uniforms = try frameUniforms(.{});
        writeUniforms(queue, frame_uniform_buffer, &initial_uniforms);
        var initial_postprocess_uniforms = postProcessUniforms(initial_render_config, 1, 1);
        writePostProcessUniforms(queue, postprocess_uniform_buffer, &initial_postprocess_uniforms);
        writePostProcessUniforms(queue, bloom_extract_uniform_buffer, &initial_postprocess_uniforms);
        writePostProcessUniforms(queue, bloom_blur_x_uniform_buffer, &initial_postprocess_uniforms);
        writePostProcessUniforms(queue, bloom_blur_y_uniform_buffer, &initial_postprocess_uniforms);

        var shadow_target = try ShadowTarget.create(device);
        errdefer shadow_target.deinit();

        const shadow_sampler = device.createSampler(&wgpu.SamplerDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot shadow comparison sampler"),
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .nearest,
            .compare = .less_equal,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_sampler.release();

        const postprocess_sampler = device.createSampler(&wgpu.SamplerDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot postprocess sampler"),
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .nearest,
        }) orelse return RenderError.NoDevice;
        errdefer postprocess_sampler.release();

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = frame_uniform_buffer,
                .size = @sizeOf(FrameUniforms),
            },
            .{
                .binding = 1,
                .texture_view = shadow_target.view orelse return RenderError.NoDevice,
            },
            .{
                .binding = 2,
                .sampler = shadow_sampler,
            },
        };
        const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot frame bind group"),
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group.release();

        var render_state = try RenderEcsState.init(allocator);
        errdefer render_state.deinit();

        const batches = allocator.alloc(BatchResources, 0) catch return RenderError.OutOfMemory;
        errdefer allocator.free(batches);

        const bind_group_layouts = [_]*wgpu.BindGroupLayout{bind_group_layout};
        const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot mesh pipeline layout"),
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer pipeline_layout.release();

        const pipeline = try createMeshPipeline(device, scene_texture_format, pipeline_layout);
        errdefer pipeline.release();

        const empty_bind_group_layouts = [_]*wgpu.BindGroupLayout{};
        const shadow_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot shadow pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_pipeline_layout.release();

        const shadow_pipeline = try createShadowPipeline(device, shadow_pipeline_layout);
        errdefer shadow_pipeline.release();

        const ui_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot UI pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer ui_pipeline_layout.release();

        const ui_pipeline = try createUiPipeline(device, texture_format, ui_pipeline_layout);
        errdefer ui_pipeline.release();

        const postprocess_bind_group_layouts = [_]*wgpu.BindGroupLayout{postprocess_bind_group_layout};
        const postprocess_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot postprocess pipeline layout"),
            .bind_group_layout_count = postprocess_bind_group_layouts.len,
            .bind_group_layouts = &postprocess_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer postprocess_pipeline_layout.release();

        const postprocess_pipeline = try createPostProcessPipeline(device, texture_format, postprocess_pipeline_layout);
        errdefer postprocess_pipeline.release();

        const bloom_bind_group_layouts = [_]*wgpu.BindGroupLayout{bloom_bind_group_layout};
        const bloom_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot bloom pipeline layout"),
            .bind_group_layout_count = bloom_bind_group_layouts.len,
            .bind_group_layouts = &bloom_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer bloom_pipeline_layout.release();

        const bloom_extract_pipeline = try createBloomExtractPipeline(device, scene_texture_format, bloom_pipeline_layout);
        errdefer bloom_extract_pipeline.release();

        const bloom_blur_pipeline = try createBloomBlurPipeline(device, scene_texture_format, bloom_pipeline_layout);
        errdefer bloom_blur_pipeline.release();

        return .{
            .allocator = allocator,
            .texture_format = texture_format,
            .scene_texture_format = scene_texture_format,
            .pipeline = pipeline,
            .shadow_pipeline = shadow_pipeline,
            .ui_pipeline = ui_pipeline,
            .postprocess_pipeline = postprocess_pipeline,
            .bloom_extract_pipeline = bloom_extract_pipeline,
            .bloom_blur_pipeline = bloom_blur_pipeline,
            .bind_group_layout = bind_group_layout,
            .postprocess_bind_group_layout = postprocess_bind_group_layout,
            .bloom_bind_group_layout = bloom_bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .shadow_pipeline_layout = shadow_pipeline_layout,
            .ui_pipeline_layout = ui_pipeline_layout,
            .postprocess_pipeline_layout = postprocess_pipeline_layout,
            .bloom_pipeline_layout = bloom_pipeline_layout,
            .frame_uniform_buffer = frame_uniform_buffer,
            .postprocess_uniform_buffer = postprocess_uniform_buffer,
            .bloom_extract_uniform_buffer = bloom_extract_uniform_buffer,
            .bloom_blur_x_uniform_buffer = bloom_blur_x_uniform_buffer,
            .bloom_blur_y_uniform_buffer = bloom_blur_y_uniform_buffer,
            .bind_group = bind_group,
            .shadow_target = shadow_target,
            .shadow_sampler = shadow_sampler,
            .postprocess_sampler = postprocess_sampler,
            .render_state = render_state,
            .batches = batches,
            .ui_layout_cache = ui_layout.LayoutCache.init(allocator),
        };
    }

    fn deinit(self: *MeshDemo) void {
        self.render_state.deinit();
        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.bind_group.release();
        self.frame_uniform_buffer.release();
        self.postprocess_uniform_buffer.release();
        self.bloom_extract_uniform_buffer.release();
        self.bloom_blur_x_uniform_buffer.release();
        self.bloom_blur_y_uniform_buffer.release();
        self.postprocess_target.deinit();
        for (&self.bloom_extract_targets) |*target| {
            target.deinit();
        }
        for (&self.bloom_ping_targets) |*target| {
            target.deinit();
        }
        for (&self.bloom_pong_targets) |*target| {
            target.deinit();
        }
        self.postprocess_sampler.release();
        self.shadow_sampler.release();
        self.shadow_target.deinit();
        self.pipeline.release();
        self.shadow_pipeline.release();
        self.ui_pipeline.release();
        self.postprocess_pipeline.release();
        self.bloom_extract_pipeline.release();
        self.bloom_blur_pipeline.release();
        self.pipeline_layout.release();
        self.shadow_pipeline_layout.release();
        self.ui_pipeline_layout.release();
        self.postprocess_pipeline_layout.release();
        self.bloom_pipeline_layout.release();
        self.bloom_bind_group_layout.release();
        self.postprocess_bind_group_layout.release();
        self.bind_group_layout.release();
        self.ui_draw.deinit();
        self.ui_vertices.deinit(self.allocator);
        self.ui_layout_cache.deinit();
    }

    fn draw(
        self: *MeshDemo,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        target_view: *wgpu.TextureView,
        depth_view: *wgpu.TextureView,
        config: FrameConfig,
    ) RenderError!void {
        try self.runRenderSchedule(.{
            .device = device,
            .queue = queue,
            .target_view = target_view,
            .depth_view = depth_view,
            .frame = config,
        });
    }

    fn renderSystemProfileCount(self: *const MeshDemo) usize {
        return self.render_state.system_profiles.items.len;
    }

    fn runRenderSchedule(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        var maybe_plan: ?BatchPlan = null;
        defer if (maybe_plan) |*plan| {
            plan.deinit();
        };
        defer self.render_state.clearFrameState(context.frame.scene.world) catch |err| {
            std.log.err("render frame cleanup failed: {s}", .{@errorName(err)});
        };

        var profiled_context = context;
        profiled_context.frame.input.system_profiles = try self.render_state.combineSystemProfileSnapshots(context.frame.input.system_profiles);

        for (self.render_state.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const started_ns = monotonicTimestampNs();
                const result = self.runRenderSystem(system, profiled_context, &maybe_plan);
                self.render_state.recordSystemDuration(system, batch.phase, elapsedNanosecondsSince(started_ns));
                try result;
            }
        }
    }

    fn runRenderSystem(
        self: *MeshDemo,
        system: runtime.ScheduledSystem,
        context: RenderSystemContext,
        maybe_plan: *?BatchPlan,
    ) RenderError!void {
        const result: RenderError!void = if (std.mem.eql(u8, system.id, render_extract_system_id)) blk: {
            break :blk self.render_state.extractSceneWithInput(.{ .world = context.frame.scene.world }, context.frame.input);
        } else if (std.mem.eql(u8, system.id, render_prepare_meshes_system_id)) blk: {
            var plan = try BatchPlan.buildFromRenderables(self.allocator, self.render_state.extractedRenderableMeshes());
            var plan_transferred = false;
            errdefer if (!plan_transferred) {
                plan.deinit();
            };
            try self.prepareBatchResources(context.device, plan);
            try self.updateBatchInstances(context.queue, plan, context.frame);
            maybe_plan.* = plan;
            plan_transferred = true;
            break :blk {};
        } else if (std.mem.eql(u8, system.id, render_queue_meshes_system_id)) blk: {
            _ = maybe_plan.* orelse return RenderError.InvalidScene;
            break :blk {};
        } else if (std.mem.eql(u8, system.id, render_interact_ui_system_id)) blk: {
            break :blk self.render_state.updateUiInteractions();
        } else if (std.mem.eql(u8, system.id, render_prepare_ui_system_id)) blk: {
            break :blk self.prepareUiDrawResources(context.device, context.queue, context.frame);
        } else if (std.mem.eql(u8, system.id, render_queue_ui_system_id)) blk: {
            break :blk self.render_state.queueUiDraw();
        } else if (std.mem.eql(u8, system.id, render_draw_meshes_system_id)) blk: {
            const plan = maybe_plan.* orelse return RenderError.InvalidScene;
            break :blk self.drawQueuedBatches(context, plan);
        } else {
            return RenderError.InvalidScene;
        };
        result catch |err| {
            std.log.err("render system '{s}' failed: {s}", .{ system.id, @errorName(err) });
            return err;
        };
    }

    fn prepareUiDrawResources(self: *MeshDemo, device: *wgpu.Device, queue: *wgpu.Queue, config: FrameConfig) RenderError!void {
        try buildUiVerticesInto(self.allocator, &self.ui_vertices, &self.ui_layout_cache, config.scene.world, config.width, config.height);
        try self.ui_draw.update(device, queue, self.ui_vertices.items);
    }

    fn prepareBatchResources(self: *MeshDemo, device: *wgpu.Device, plan: BatchPlan) RenderError!void {
        if (self.batchResourcesMatchPlan(plan)) {
            return;
        }

        const new_batches = self.allocator.alloc(BatchResources, plan.batches.len) catch return RenderError.OutOfMemory;
        var batch_count: usize = 0;
        errdefer {
            for (new_batches[0..batch_count]) |*batch| {
                batch.deinit();
            }
            self.allocator.free(new_batches);
        }

        for (plan.batches, 0..) |entry, index| {
            new_batches[index] = try BatchResources.create(self.allocator, device, entry);
            batch_count += 1;
        }

        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.batches = new_batches;
    }

    fn batchResourcesMatchPlan(self: MeshDemo, plan: BatchPlan) bool {
        if (self.batches.len != plan.batches.len) {
            return false;
        }
        for (plan.batches, self.batches) |entry, batch| {
            if (!batch.matches(entry)) {
                return false;
            }
        }
        return true;
    }

    fn updateBatchInstances(self: *MeshDemo, queue: *wgpu.Queue, plan: BatchPlan, config: FrameConfig) RenderError!void {
        const camera = try cameraStateForInput(config.scene.world, config.input);
        const light = try directionalLightState(config.scene.world);
        const light_view_projection = try shadowLightViewProjection(light);
        const game_viewport = config.gameViewport();
        for (plan.batches, 0..) |entry, batch_index| {
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }

            const instances = self.allocator.alloc(InstanceAttributes, entry.render_indices.len) catch return RenderError.OutOfMemory;
            defer self.allocator.free(instances);

            for (entry.render_indices, 0..) |render_index, instance_index| {
                if (render_index >= plan.renderables.len) {
                    return RenderError.InvalidScene;
                }
                const mesh = plan.renderables[render_index];
                instances[instance_index] = try instanceAttributes(.{
                    .width = game_viewport.width,
                    .height = game_viewport.height,
                    .mesh = &mesh,
                    .camera = camera,
                    .light_view_projection = light_view_projection,
                });
            }

            const bytes = std.mem.sliceAsBytes(instances);
            queue.writeBuffer(self.batches[batch_index].instance_buffer, 0, bytes.ptr, bytes.len);
        }
    }

    fn drawQueuedBatches(self: *MeshDemo, context: RenderSystemContext, plan: BatchPlan) RenderError!void {
        const light = try directionalLightState(context.frame.scene.world);
        var frame_uniforms = try frameUniforms(light);
        writeUniforms(context.queue, self.frame_uniform_buffer, &frame_uniforms);

        for (plan.batches, 0..) |_, batch_index| {
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }
        }

        const should_draw_ui = self.render_state.uiDrawCommandCount() > 0 and self.ui_draw.vertex_count > 0;

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot mesh command encoder"),
        }) orelse return RenderError.NoDevice;
        defer encoder.release();

        try self.drawShadowPass(encoder, plan.batches.len);

        const render_config = renderConfigFromWorld(context.frame.scene.world);
        const postprocess_active = render_config.requiresPostProcess();
        const bloom_active = render_config.bloomActive();
        const scene_target_view = if (postprocess_active) blk: {
            try self.postprocess_target.ensure(
                context.device,
                context.frame.width,
                context.frame.height,
                self.scene_texture_format,
            );
            break :blk self.postprocess_target.view orelse return RenderError.NoDevice;
        } else context.target_view;

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = scene_target_view,
                .clear_value = .{
                    .r = 0.0006,
                    .g = 0.0018,
                    .b = 0.0086,
                    .a = 1.0,
                },
            },
        };
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = context.depth_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };

        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();
        const game_viewport = context.frame.gameViewport();
        render_pass.setViewport(game_viewport.x, game_viewport.y, game_viewport.width, game_viewport.height, 0.0, 1.0);
        render_pass.setScissorRect(
            @intFromFloat(@max(@floor(game_viewport.x), 0.0)),
            @intFromFloat(@max(@floor(game_viewport.y), 0.0)),
            @intFromFloat(@max(@ceil(game_viewport.width), 1.0)),
            @intFromFloat(@max(@ceil(game_viewport.height), 1.0)),
        );
        render_pass.setPipeline(self.pipeline);
        render_pass.setBindGroup(0, self.bind_group, 0, null);
        for (0..plan.batches.len) |batch_index| {
            const batch = self.batches[batch_index];
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();

        if (postprocess_active) {
            const bloom_views = if (bloom_active)
                try self.drawBloomPasses(render_config, context.device, encoder, context.queue, scene_target_view, context.frame.width, context.frame.height)
            else
                emptyBloomViews(scene_target_view);
            try self.drawPostProcessPass(render_config, encoder, context.device, context.queue, context.target_view, scene_target_view, bloom_views, context.frame.width, context.frame.height);
        }

        if (should_draw_ui) {
            try self.drawUiPass(encoder, context.target_view);
        }

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot mesh command buffer"),
        }) orelse return RenderError.NoDevice;
        defer command_buffer.release();

        const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
        context.queue.submit(&command_buffers);
    }

    fn drawShadowPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, batch_count: usize) RenderError!void {
        const shadow_view = self.shadow_target.view orelse return RenderError.NoDevice;
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = shadow_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        const color_attachments = [_]wgpu.ColorAttachment{};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot shadow pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.shadow_pipeline);
        for (0..batch_count) |batch_index| {
            const batch = self.batches[batch_index];
            if (!batch.shadow_key.casts_shadow) {
                continue;
            }
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();
    }

    fn drawUiPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, target_view: *wgpu.TextureView) RenderError!void {
        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = target_view,
                .load_op = .load,
                .store_op = .store,
            },
        };
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot UI pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.ui_pipeline);
        const vertex_buffer = self.ui_draw.vertex_buffer orelse return RenderError.NoDevice;
        render_pass.setVertexBuffer(0, vertex_buffer, 0, self.ui_draw.vertex_buffer_size);
        render_pass.draw(self.ui_draw.vertex_count, 1, 0, 0);
        render_pass.end();
    }

    fn drawPostProcessPass(
        self: *MeshDemo,
        render_config: RenderConfig,
        encoder: *wgpu.CommandEncoder,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        target_view: *wgpu.TextureView,
        scene_view: *wgpu.TextureView,
        bloom_views: BloomViews,
        width: u32,
        height: u32,
    ) RenderError!void {
        var uniforms = postProcessUniforms(render_config, width, height);
        writePostProcessUniforms(queue, self.postprocess_uniform_buffer, &uniforms);
        const bind_group = try createCompositeBindGroup(
            device,
            self.postprocess_bind_group_layout,
            self.postprocess_uniform_buffer,
            scene_view,
            bloom_views,
            self.postprocess_sampler,
        );
        defer bind_group.release();

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = target_view,
                .clear_value = .{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                },
            },
        };
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot postprocess pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.postprocess_pipeline);
        render_pass.setBindGroup(0, bind_group, 0, null);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
    }

    fn drawBloomPasses(
        self: *MeshDemo,
        render_config: RenderConfig,
        device: *wgpu.Device,
        encoder: *wgpu.CommandEncoder,
        queue: *wgpu.Queue,
        scene_view: *wgpu.TextureView,
        width: u32,
        height: u32,
    ) RenderError!BloomViews {
        var views: BloomViews = undefined;
        var source_view = scene_view;
        for (0..bloom_level_count) |level| {
            const divisor = @as(u32, 1) << @intCast(level + 1);
            const bloom_width = @max(width / divisor, 1);
            const bloom_height = @max(height / divisor, 1);
            try self.bloom_extract_targets[level].ensure(device, bloom_width, bloom_height, self.scene_texture_format);
            try self.bloom_ping_targets[level].ensure(device, bloom_width, bloom_height, self.scene_texture_format);
            try self.bloom_pong_targets[level].ensure(device, bloom_width, bloom_height, self.scene_texture_format);

            var extract_uniforms = postProcessUniforms(render_config, width, height);
            extract_uniforms.params4 = .{ @floatFromInt(level), 0.0, 0.0, 0.0 };
            writePostProcessUniforms(queue, self.bloom_extract_uniform_buffer, &extract_uniforms);
            try self.drawBloomSamplePass(
                device,
                encoder,
                self.bloom_extract_pipeline,
                self.bloom_extract_uniform_buffer,
                source_view,
                self.bloom_extract_targets[level].view orelse return RenderError.NoDevice,
                "Scrapbot bloom extract/downsample pass",
            );

            var blur_x_uniforms = postProcessUniforms(render_config, width, height);
            blur_x_uniforms.params4 = .{ 1.0, 0.0, @floatFromInt(level), 0.0 };
            writePostProcessUniforms(queue, self.bloom_blur_x_uniform_buffer, &blur_x_uniforms);
            try self.drawBloomSamplePass(
                device,
                encoder,
                self.bloom_blur_pipeline,
                self.bloom_blur_x_uniform_buffer,
                self.bloom_extract_targets[level].view orelse return RenderError.NoDevice,
                self.bloom_ping_targets[level].view orelse return RenderError.NoDevice,
                "Scrapbot bloom horizontal blur pass",
            );

            var blur_y_uniforms = postProcessUniforms(render_config, width, height);
            blur_y_uniforms.params4 = .{ 0.0, 1.0, @floatFromInt(level), 0.0 };
            writePostProcessUniforms(queue, self.bloom_blur_y_uniform_buffer, &blur_y_uniforms);
            try self.drawBloomSamplePass(
                device,
                encoder,
                self.bloom_blur_pipeline,
                self.bloom_blur_y_uniform_buffer,
                self.bloom_ping_targets[level].view orelse return RenderError.NoDevice,
                self.bloom_pong_targets[level].view orelse return RenderError.NoDevice,
                "Scrapbot bloom vertical blur pass",
            );

            views[level] = self.bloom_pong_targets[level].view orelse return RenderError.NoDevice;
            source_view = views[level];
        }

        return views;
    }

    fn drawBloomSamplePass(
        self: *MeshDemo,
        device: *wgpu.Device,
        encoder: *wgpu.CommandEncoder,
        pipeline: *wgpu.RenderPipeline,
        uniform_buffer: *wgpu.Buffer,
        source_view: *wgpu.TextureView,
        target_view: *wgpu.TextureView,
        label: []const u8,
    ) RenderError!void {
        const bind_group = try createSingleTextureBindGroup(
            device,
            self.bloom_bind_group_layout,
            uniform_buffer,
            source_view,
            self.postprocess_sampler,
        );
        defer bind_group.release();

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = target_view,
                .clear_value = .{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                },
            },
        };
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice(label),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(pipeline);
        render_pass.setBindGroup(0, bind_group, 0, null);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
    }
};

fn drawMeshToSurface(
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    demo: *MeshDemo,
    depth_view: *wgpu.TextureView,
    config: FrameConfig,
) !void {
    var surface_texture = wgpu.SurfaceTexture{
        .next_in_chain = null,
        .texture = null,
        .status = .@"error",
    };
    surface.getCurrentTexture(&surface_texture);
    switch (surface_texture.status) {
        .success_optimal, .success_suboptimal => {},
        else => return RenderError.SurfaceFailed,
    }

    const texture = surface_texture.texture orelse return RenderError.SurfaceFailed;
    defer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot surface texture view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer view.release();

    try demo.draw(device, queue, view, depth_view, config);
    if (surface.present() != .success) {
        return RenderError.SurfaceFailed;
    }
}

fn createSingleTextureBindGroup(
    device: *wgpu.Device,
    layout: *wgpu.BindGroupLayout,
    uniform_buffer: *wgpu.Buffer,
    texture_view: *wgpu.TextureView,
    sampler: *wgpu.Sampler,
) RenderError!*wgpu.BindGroup {
    const bind_group_entries = [_]wgpu.BindGroupEntry{
        .{
            .binding = 0,
            .buffer = uniform_buffer,
            .size = @sizeOf(PostProcessUniforms),
        },
        .{
            .binding = 1,
            .texture_view = texture_view,
        },
        .{
            .binding = 2,
            .sampler = sampler,
        },
    };
    return device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot texture pass bind group"),
        .layout = layout,
        .entry_count = bind_group_entries.len,
        .entries = &bind_group_entries,
    }) orelse return RenderError.NoDevice;
}

fn createCompositeBindGroup(
    device: *wgpu.Device,
    layout: *wgpu.BindGroupLayout,
    uniform_buffer: *wgpu.Buffer,
    scene_view: *wgpu.TextureView,
    bloom_views: BloomViews,
    sampler: *wgpu.Sampler,
) RenderError!*wgpu.BindGroup {
    const bind_group_entries = [_]wgpu.BindGroupEntry{
        .{
            .binding = 0,
            .buffer = uniform_buffer,
            .size = @sizeOf(PostProcessUniforms),
        },
        .{
            .binding = 1,
            .texture_view = scene_view,
        },
        .{
            .binding = 2,
            .sampler = sampler,
        },
        .{
            .binding = 3,
            .texture_view = bloom_views[0],
        },
        .{
            .binding = 4,
            .texture_view = bloom_views[1],
        },
        .{
            .binding = 5,
            .texture_view = bloom_views[2],
        },
        .{
            .binding = 6,
            .texture_view = bloom_views[3],
        },
        .{
            .binding = 7,
            .texture_view = bloom_views[4],
        },
    };
    return device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot postprocess composite bind group"),
        .layout = layout,
        .entry_count = bind_group_entries.len,
        .entries = &bind_group_entries,
    }) orelse return RenderError.NoDevice;
}

fn emptyBloomViews(view: *wgpu.TextureView) BloomViews {
    return [_]*wgpu.TextureView{view} ** bloom_level_count;
}

fn frameUniforms(light_value: DirectionalLightState) RenderError!FrameUniforms {
    const light = try validateDirectionalLight(light_value);
    const normalized_light = normalizeVec3(light.direction);

    return .{
        .light_dir = .{ normalized_light[0], normalized_light[1], normalized_light[2], 0.0 },
        .light_color = .{ light.color[0], light.color[1], light.color[2], 1.0 },
        .lighting = .{ light.ambient, light.intensity, 0.0, 0.0 },
    };
}

fn postProcessUniforms(config: RenderConfig, width: u32, height: u32) PostProcessUniforms {
    const safe_width = @max(width, 1);
    const safe_height = @max(height, 1);
    return .{
        .params0 = .{
            1.0 / @as(f32, @floatFromInt(safe_width)),
            1.0 / @as(f32, @floatFromInt(safe_height)),
            if (config.postprocess.enabled and config.postprocess.antialiasing == .fxaa) 1.0 else 0.0,
            if (config.postprocess.enabled and config.postprocess.chromatic_aberration.enabled) config.postprocess.chromatic_aberration.strength else 0.0,
        },
        .params1 = .{
            if (config.postprocess.enabled and config.postprocess.vignette.enabled) 1.0 else 0.0,
            config.postprocess.vignette.strength,
            config.postprocess.vignette.radius,
            0.0,
        },
        .params2 = .{
            if (config.postprocess.enabled and config.postprocess.bloom.enabled) 1.0 else 0.0,
            config.postprocess.bloom.threshold,
            config.postprocess.bloom.intensity,
            config.postprocess.bloom.radius,
        },
        .params3 = .{
            if (config.color.hdr) 1.0 else 0.0,
            config.color.exposure,
            switch (config.color.tone_mapping) {
                .none => 0.0,
                .reinhard => 1.0,
                .aces => 2.0,
            },
            0.0,
        },
        .params4 = .{ 0.0, 0.0, 0.0, 0.0 },
    };
}

fn instanceAttributes(config: InstanceConfig) RenderError!InstanceAttributes {
    const aspect = config.width / config.height;
    const mesh = config.mesh;
    const rotation = matMul(
        rotationZ(mesh.rotation[2]),
        matMul(
            rotationY(mesh.rotation[1]),
            rotationX(mesh.rotation[0]),
        ),
    );
    const model = matMul(
        translation(mesh.position[0], mesh.position[1], mesh.position[2]),
        matMul(rotation, scaling(mesh.scale[0], mesh.scale[1], mesh.scale[2])),
    );
    const camera = try validateCamera(config.camera);
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), aspect, camera.near, camera.far);
    const mvp = matMul(projection, matMul(view, model));
    const shadow_mvp = matMul(config.light_view_projection, model);

    return .{
        .mvp = mvp,
        .model = model,
        .object_color = .{ mesh.base_color[0], mesh.base_color[1], mesh.base_color[2], 1.0 },
        .shadow_mvp = shadow_mvp,
        .shadow_flags = .{
            @floatFromInt(@as(u32, @intFromBool(mesh.receives_shadow))),
            @floatFromInt(@as(u32, @intFromBool(mesh.casts_shadow))),
            0.0,
            0.0,
        },
    };
}

fn shadowLightViewProjection(light_value: DirectionalLightState) RenderError![16]f32 {
    const light = try validateDirectionalLight(light_value);
    const light_direction = normalizeVec3(light.direction);
    const eye = scaleVec3(light_direction, 7.5);
    const target = [3]f32{ 0.0, 0.0, 0.0 };
    const preferred_up = [3]f32{ 0.0, 1.0, 0.0 };
    const up = if (@abs(dotVec3(light_direction, preferred_up)) > 0.95)
        [3]f32{ 0.0, 0.0, 1.0 }
    else
        preferred_up;
    const view = lookAt(eye, target, up);
    const projection = orthographic(-5.2, 5.2, -3.9, 3.9, 0.1, 18.0);
    return matMul(projection, view);
}

const EditorRay = struct {
    origin: [3]f32,
    direction: [3]f32,
};

fn pickRenderableEntity(world: *const runtime.World, input: FrameInput) EditorError!?runtime.EntityHandle {
    if (!editorGameViewport(input).contains(input.pointer.position)) {
        return null;
    }
    const ray = try editorRayFromInput(world, input);
    var best_entity: ?runtime.EntityHandle = null;
    var best_t = std.math.inf(f32);

    var meshes = world.renderableMeshes();
    while (meshes.next()) |mesh| {
        const radius = editorPickRadiusForMesh(mesh);
        const hit_t = intersectRaySphere(ray, mesh.position, radius) orelse continue;
        if (hit_t >= 0.0 and hit_t < best_t) {
            best_t = hit_t;
            best_entity = mesh.entity;
        }
    }

    return best_entity;
}

fn pickEditorGizmoAxis(world: *const runtime.World, selected: runtime.EntityHandle, input: FrameInput) EditorError!EditorAxis {
    const transform_value = (try world.getTransform(selected)) orelse return .none;
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return .none;
    const axes = [_]struct {
        axis: EditorAxis,
        vector: [3]f32,
    }{
        .{ .axis = .x, .vector = .{ 1.0, 0.0, 0.0 } },
        .{ .axis = .y, .vector = .{ 0.0, 1.0, 0.0 } },
        .{ .axis = .z, .vector = .{ 0.0, 0.0, 1.0 } },
    };

    var best_axis = EditorAxis.none;
    var best_distance = editor_gizmo_pick_radius_px;
    for (axes) |entry| {
        const end_screen = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(entry.vector, editor_gizmo_axis_length)), camera, input) orelse continue;
        const distance = distancePointToScreenSegment(input.pointer.position, origin_screen, end_screen);
        if (distance < best_distance) {
            best_distance = distance;
            best_axis = entry.axis;
        }
    }
    return best_axis;
}

fn dragSelectedEntity(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!void {
    const selected = state.selected_entity orelse return;
    const transform_value = (try world.getTransform(selected)) orelse return;
    if (!state.has_last_pointer) {
        state.last_pointer = input.pointer.position;
        state.has_last_pointer = true;
        return;
    }

    const axis = editorAxisVector(state.dragging_axis) orelse return;
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return;
    const axis_screen_end = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(axis, editor_gizmo_axis_length)), camera, input) orelse return;
    const axis_screen_delta = subtractVec2(axis_screen_end, origin_screen);
    const axis_screen_length = vec2Length(axis_screen_delta);
    if (axis_screen_length < 0.001) {
        state.last_pointer = input.pointer.position;
        return;
    }

    const axis_screen = scaleVec2(axis_screen_delta, 1.0 / axis_screen_length);
    const pointer_delta = subtractVec2(input.pointer.position, state.last_pointer);
    const projected_pixels = dotVec2(pointer_delta, axis_screen);
    const camera_distance = vec3Length(subtractVec3(transform_value.position, camera.transform.position));
    const units_per_pixel = @max(camera_distance, 1.0) * 0.0025;
    const world_delta = projected_pixels * units_per_pixel;
    const next_position = addVec3(transform_value.position, scaleVec3(axis, world_delta));

    try world.setVec3(selected, runtime.transform_component_id, "position", next_position);
    state.last_pointer = input.pointer.position;
}

fn editorRayFromInput(world: *const runtime.World, input: FrameInput) EditorError!EditorRay {
    const viewport = editorGameViewport(input);
    const width = viewport.width;
    const height = viewport.height;
    if (width <= 0.0 or height <= 0.0) {
        return error.InvalidScene;
    }
    if (!viewport.contains(input.pointer.position)) {
        return error.InvalidScene;
    }
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const aspect = width / height;
    const tan_half_fov = @tan(std.math.degreesToRadians(camera.fov_y_degrees) * 0.5);
    const local_pointer = subtractVec2(input.pointer.position, .{ viewport.x, viewport.y });
    const ndc_x = (local_pointer[0] / width) * 2.0 - 1.0;
    const ndc_y = 1.0 - (local_pointer[1] / height) * 2.0;
    const local_direction = normalizeVec3(.{
        ndc_x * tan_half_fov * aspect,
        ndc_y * tan_half_fov,
        -1.0,
    });
    return .{
        .origin = camera.transform.position,
        .direction = rotateDirection(camera.transform.rotation, local_direction),
    };
}

fn projectWorldToScreen(position: [3]f32, camera_value: CameraState, input: FrameInput) ?[2]f32 {
    const viewport = editorGameViewport(input);
    const width = viewport.width;
    const height = viewport.height;
    if (width <= 0.0 or height <= 0.0) {
        return null;
    }
    const camera = validateCamera(camera_value) catch return null;
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), width / height, camera.near, camera.far);
    const clip = transformPoint(matMul(projection, view), .{ position[0], position[1], position[2], 1.0 });
    if (@abs(clip[3]) < 0.00001) {
        return null;
    }
    const ndc_x = clip[0] / clip[3];
    const ndc_y = clip[1] / clip[3];
    if (!std.math.isFinite(ndc_x) or !std.math.isFinite(ndc_y)) {
        return null;
    }
    return .{
        viewport.x + (ndc_x + 1.0) * 0.5 * width,
        viewport.y + (1.0 - ndc_y) * 0.5 * height,
    };
}

fn intersectRaySphere(ray: EditorRay, center: [3]f32, radius: f32) ?f32 {
    const oc = subtractVec3(ray.origin, center);
    const a = dotVec3(ray.direction, ray.direction);
    const b = 2.0 * dotVec3(oc, ray.direction);
    const c = dotVec3(oc, oc) - radius * radius;
    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return null;
    }
    const root = @sqrt(discriminant);
    const near_t = (-b - root) / (2.0 * a);
    if (near_t >= 0.0) {
        return near_t;
    }
    const far_t = (-b + root) / (2.0 * a);
    return if (far_t >= 0.0) far_t else null;
}

fn editorPickRadiusForMesh(mesh: runtime.RenderableMesh) f32 {
    return @max(@max(@abs(mesh.scale[0]), @abs(mesh.scale[1])), @abs(mesh.scale[2])) * 1.25;
}

fn editorAxisVector(axis: EditorAxis) ?[3]f32 {
    return switch (axis) {
        .none => null,
        .x => .{ 1.0, 0.0, 0.0 },
        .y => .{ 0.0, 1.0, 0.0 },
        .z => .{ 0.0, 0.0, 1.0 },
    };
}

const FrameUniforms = extern struct {
    light_dir: [4]f32,
    light_color: [4]f32,
    lighting: [4]f32,
};

const PostProcessUniforms = extern struct {
    params0: [4]f32,
    params1: [4]f32,
    params2: [4]f32,
    params3: [4]f32,
    params4: [4]f32,
};

const UiVertex = render_types.UiVertex;
