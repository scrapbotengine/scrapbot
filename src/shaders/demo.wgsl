struct FrameUniforms {
    mvp: mat4x4<f32>,
    model: mat4x4<f32>,
    light_dir: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> frame: FrameUniforms;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) color: vec3<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) color: vec3<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.clip_position = frame.mvp * vec4<f32>(input.position, 1.0);
    output.normal = normalize((frame.model * vec4<f32>(input.normal, 0.0)).xyz);
    output.color = input.color;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let normal = normalize(input.normal);
    let light = normalize(frame.light_dir.xyz);
    let diffuse = max(dot(normal, light), 0.0);
    let ambient = 0.18;
    let rim = pow(1.0 - max(abs(normal.z), 0.0), 2.0) * 0.12;
    let shaded = input.color * (ambient + diffuse * 0.78) + vec3<f32>(rim);
    return vec4<f32>(shaded, 1.0);
}
