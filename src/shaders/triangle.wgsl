@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
    var p = vec2f(0.0, 0.0);

    if (vertex_index == 0u) {
        p = vec2f(-0.55, -0.45);
    } else if (vertex_index == 1u) {
        p = vec2f(0.55, -0.45);
    } else {
        p = vec2f(0.0, 0.55);
    }

    return vec4f(p, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4f {
    return vec4f(0.0, 0.55, 1.0, 1.0);
}
