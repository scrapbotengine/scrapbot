struct FrameUniforms {
    light_dir: vec4<f32>,
    light_color: vec4<f32>,
    lighting: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> frame: FrameUniforms;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) mvp0: vec4<f32>,
    @location(3) mvp1: vec4<f32>,
    @location(4) mvp2: vec4<f32>,
    @location(5) mvp3: vec4<f32>,
    @location(6) model0: vec4<f32>,
    @location(7) model1: vec4<f32>,
    @location(8) model2: vec4<f32>,
    @location(9) model3: vec4<f32>,
    @location(10) object_color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) object_color: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    let mvp = mat4x4<f32>(input.mvp0, input.mvp1, input.mvp2, input.mvp3);
    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    var output: VertexOutput;
    output.clip_position = mvp * vec4<f32>(input.position, 1.0);
    output.normal = normalize((model * vec4<f32>(input.normal, 0.0)).xyz);
    output.object_color = input.object_color;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let normal = normalize(input.normal);
    let light = normalize(frame.light_dir.xyz);
    let diffuse = max(dot(normal, light), 0.0);
    let ambient = frame.lighting.x;
    let intensity = frame.lighting.y;
    let rim = pow(1.0 - max(abs(normal.z), 0.0), 2.0) * 0.12;
    let lit = input.object_color.xyz * frame.light_color.xyz * diffuse * intensity;
    let shaded = input.object_color.xyz * ambient + lit + vec3<f32>(rim);
    return vec4<f32>(shaded, 1.0);
}
