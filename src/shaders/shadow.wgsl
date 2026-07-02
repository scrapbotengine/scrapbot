struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(2) shadow_mvp0: vec4<f32>,
    @location(3) shadow_mvp1: vec4<f32>,
    @location(4) shadow_mvp2: vec4<f32>,
    @location(5) shadow_mvp3: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> @builtin(position) vec4<f32> {
    let shadow_mvp = mat4x4<f32>(input.shadow_mvp0, input.shadow_mvp1, input.shadow_mvp2, input.shadow_mvp3);
    return shadow_mvp * vec4<f32>(input.position, 1.0);
}
