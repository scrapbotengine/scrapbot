const std = @import("std");

const runtime = @import("../runtime.zig");
const editor_layout = @import("../editor/layout.zig");
const render_input = @import("input.zig");
const render_math = @import("math.zig");
const render_types = @import("types.zig");

const FrameInput = render_input.FrameInput;
const RenderError = render_types.RenderError;
const addVec3 = render_math.addVec3;
const subtractVec3 = render_math.subtractVec3;
const scaleVec3 = render_math.scaleVec3;
const normalizeVec3 = render_math.normalizeVec3;
const vec3Length = render_math.vec3Length;
const rotateDirection = render_math.rotateDirection;
const isFiniteVec3 = render_math.isFiniteVec3;
const editorGameViewport = editor_layout.gameViewport;

pub const live_run_default_delta_seconds: f32 = 1.0 / 60.0;
pub const live_run_max_delta_seconds: f32 = 0.1;
const fly_camera_move_speed: f32 = 6.0;
const fly_camera_look_sensitivity: f32 = 0.0035;
const fly_camera_max_pitch: f32 = std.math.degreesToRadians(89.0);

pub const CameraState = struct {
    transform: runtime.Transform = .{ .position = .{ 0.0, 0.0, 4.8 } },
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const FlyCameraState = struct {
    initialized: bool = false,
    captured_look: bool = false,
    transform: runtime.Transform = .{},

    pub fn reset(self: *FlyCameraState) void {
        self.* = .{};
    }
};

pub const DirectionalLightState = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
};

pub fn cameraState(world: *const runtime.World) RenderError!CameraState {
    if (world.renderCamera()) |camera| {
        return validateCamera(.{
            .transform = camera.transform,
            .fov_y_degrees = camera.fov_y_degrees,
            .near = camera.near,
            .far = camera.far,
        });
    }
    if (world.componentInstanceCountFor(runtime.camera_component_id) != 0) {
        return RenderError.InvalidScene;
    }
    return .{};
}

pub fn cameraStateForInput(world: *const runtime.World, input: FrameInput) RenderError!CameraState {
    var camera = try cameraState(world);
    if (input.camera_override) |camera_transform| {
        camera.transform = camera_transform;
    }
    return validateCamera(camera);
}

pub fn liveRunDeltaSecondsFromElapsedNs(elapsed_ns: u64) f32 {
    if (elapsed_ns == 0) {
        return live_run_default_delta_seconds;
    }

    const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    if (!std.math.isFinite(elapsed_seconds) or elapsed_seconds <= 0.0) {
        return live_run_default_delta_seconds;
    }

    return @floatCast(@min(elapsed_seconds, @as(f64, live_run_max_delta_seconds)));
}

pub fn updateFlyCamera(state: *FlyCameraState, world: *const runtime.World, input: FrameInput, delta_seconds: f32) RenderError!?runtime.Transform {
    const active = updateFlyCameraCapture(state, input);
    if (!state.initialized and !active) {
        return null;
    }
    if (!state.initialized) {
        state.transform = (try cameraState(world)).transform;
        state.initialized = true;
    }
    if (!active) {
        return state.transform;
    }

    const dt = if (std.math.isFinite(delta_seconds) and delta_seconds > 0.0)
        @min(delta_seconds, 0.1)
    else
        0.0;

    if (std.math.isFinite(input.pointer.delta[0]) and std.math.isFinite(input.pointer.delta[1])) {
        state.transform.rotation[1] -= input.pointer.delta[0] * fly_camera_look_sensitivity;
        state.transform.rotation[0] = std.math.clamp(
            state.transform.rotation[0] - input.pointer.delta[1] * fly_camera_look_sensitivity,
            -fly_camera_max_pitch,
            fly_camera_max_pitch,
        );
        state.transform.rotation[2] = 0.0;
    }

    var movement = [3]f32{ 0.0, 0.0, 0.0 };
    const forward = rotateDirection(state.transform.rotation, .{ 0.0, 0.0, -1.0 });
    const right = rotateDirection(state.transform.rotation, .{ 1.0, 0.0, 0.0 });
    if (input.keyboard.move_forward) {
        movement = addVec3(movement, forward);
    }
    if (input.keyboard.move_back) {
        movement = subtractVec3(movement, forward);
    }
    if (input.keyboard.move_right) {
        movement = addVec3(movement, right);
    }
    if (input.keyboard.move_left) {
        movement = subtractVec3(movement, right);
    }
    if (input.keyboard.move_up) {
        movement[1] += 1.0;
    }
    if (input.keyboard.move_down) {
        movement[1] -= 1.0;
    }

    if (vec3Length(movement) > 0.0001 and dt > 0.0) {
        state.transform.position = addVec3(
            state.transform.position,
            scaleVec3(normalizeVec3(movement), fly_camera_move_speed * dt),
        );
    }

    return state.transform;
}

pub fn updateFlyCameraCapture(state: *FlyCameraState, input: FrameInput) bool {
    if (!input.pointer.secondary_down or input.pointer.secondary_released) {
        state.captured_look = false;
        return false;
    }

    if (input.pointer.secondary_pressed and flyCameraCaptureStartAllowed(input)) {
        state.captured_look = true;
    }

    return flyCameraInputActive(state.*, input);
}

fn flyCameraInputActive(state: FlyCameraState, input: FrameInput) bool {
    return state.captured_look and input.pointer.secondary_down;
}

fn flyCameraCaptureStartAllowed(input: FrameInput) bool {
    if (!input.debug_overlay_visible) {
        return true;
    }
    return input.pointer.has_position and editorGameViewport(input).contains(input.pointer.position);
}

pub fn directionalLightState(world: *const runtime.World) RenderError!DirectionalLightState {
    if (world.renderDirectionalLight()) |light| {
        return validateDirectionalLight(.{
            .direction = light.direction,
            .color = light.color,
            .intensity = light.intensity,
            .ambient = light.ambient,
        });
    }
    return .{};
}

pub fn validateCamera(camera: CameraState) RenderError!CameraState {
    if (!isFiniteVec3(camera.transform.position) or
        !isFiniteVec3(camera.transform.rotation) or
        !isFiniteVec3(camera.transform.scale) or
        !std.math.isFinite(camera.fov_y_degrees) or
        !std.math.isFinite(camera.near) or
        !std.math.isFinite(camera.far) or
        camera.fov_y_degrees <= 0.0 or
        camera.fov_y_degrees >= 179.0 or
        camera.near <= 0.0 or
        camera.far <= camera.near)
    {
        return RenderError.InvalidScene;
    }
    return camera;
}

pub fn validateDirectionalLight(light: DirectionalLightState) RenderError!DirectionalLightState {
    if (!isFiniteVec3(light.direction) or
        !isFiniteVec3(light.color) or
        !std.math.isFinite(light.intensity) or
        !std.math.isFinite(light.ambient) or
        vec3Length(light.direction) == 0.0 or
        light.intensity < 0.0 or
        light.ambient < 0.0)
    {
        return RenderError.InvalidScene;
    }
    return light;
}
