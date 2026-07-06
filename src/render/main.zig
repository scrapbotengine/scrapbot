const engine = @import("engine.zig");

pub const RenderError = engine.RenderError;
pub const Stats = engine.Stats;
pub const WindowOptions = engine.WindowOptions;
pub const ImageRenderOptions = engine.ImageRenderOptions;
pub const AntialiasingMode = engine.AntialiasingMode;
pub const VignetteConfig = engine.VignetteConfig;
pub const ChromaticAberrationConfig = engine.ChromaticAberrationConfig;
pub const BloomConfig = engine.BloomConfig;
pub const PostProcessConfig = engine.PostProcessConfig;
pub const ToneMappingMode = engine.ToneMappingMode;
pub const ColorConfig = engine.ColorConfig;
pub const RenderConfig = engine.RenderConfig;
pub const Scene = engine.Scene;
pub const SceneReloadHook = engine.SceneReloadHook;
pub const FrameUpdateHook = engine.FrameUpdateHook;
pub const PointerInput = engine.PointerInput;
pub const KeyboardInput = engine.KeyboardInput;
pub const EditorAxis = engine.EditorAxis;
pub const EditorState = engine.EditorState;
pub const EditorSplitter = engine.EditorSplitter;
pub const EditorFrameState = engine.EditorFrameState;
pub const EditorUpdate = engine.EditorUpdate;
pub const EditorViewportBounds = engine.EditorViewportBounds;
pub const EditorError = engine.EditorError;
pub const FrameInput = engine.FrameInput;
pub const default_output_width = engine.default_output_width;
pub const default_output_height = engine.default_output_height;
pub const editorFrameState = engine.editorFrameState;
pub const updateEditorState = engine.updateEditorState;
pub const stats = engine.stats;
pub const writeFrameInput = engine.writeFrameInput;
pub const renderDemoImage = engine.renderDemoImage;
pub const renderDemoImageWithInput = engine.renderDemoImageWithInput;
pub const renderDemoImageFrames = engine.renderDemoImageFrames;
pub const runDemoWindow = engine.runDemoWindow;
pub const editorGameViewportBounds = engine.editorGameViewportBounds;
pub const editorSystemListHitTestPoint = engine.editorSystemListHitTestPoint;

test {
    _ = engine;
    _ = @import("engine_tests/editor_interaction.zig");
    _ = @import("engine_tests/render_ecs_ui.zig");
    _ = @import("engine_tests/editor_rendering.zig");
}
