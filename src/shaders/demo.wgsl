struct FrameUniforms {
    light_dir: vec4<f32>,
    light_color: vec4<f32>,
    lighting: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> frame: FrameUniforms;

@group(0) @binding(1)
var shadow_map: texture_depth_2d;

@group(0) @binding(2)
var shadow_sampler: sampler_comparison;

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
    @location(11) shadow_mvp0: vec4<f32>,
    @location(12) shadow_mvp1: vec4<f32>,
    @location(13) shadow_mvp2: vec4<f32>,
    @location(14) shadow_mvp3: vec4<f32>,
    @location(15) shadow_flags: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) object_color: vec4<f32>,
    @location(2) shadow_position: vec4<f32>,
    @location(3) shadow_flags: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    let mvp = mat4x4<f32>(input.mvp0, input.mvp1, input.mvp2, input.mvp3);
    let model = mat4x4<f32>(input.model0, input.model1, input.model2, input.model3);
    let shadow_mvp = mat4x4<f32>(input.shadow_mvp0, input.shadow_mvp1, input.shadow_mvp2, input.shadow_mvp3);
    var output: VertexOutput;
    let local_position = vec4<f32>(input.position, 1.0);
    output.clip_position = mvp * local_position;
    output.normal = normalize((model * vec4<f32>(input.normal, 0.0)).xyz);
    output.object_color = input.object_color;
    output.shadow_position = shadow_mvp * local_position;
    output.shadow_flags = input.shadow_flags;
    return output;
}

fn shadow_visibility(input: VertexOutput) -> f32 {
    if input.shadow_flags.x < 0.5 {
        return 1.0;
    }

    let projected = input.shadow_position.xyz / input.shadow_position.w;
    let uv = projected.xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5, 0.5);
    if uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || projected.z < 0.0 || projected.z > 1.0 {
        return 1.0;
    }

    let visibility = textureSampleCompare(shadow_map, shadow_sampler, uv, projected.z - 0.004);
    return mix(0.42, 1.0, visibility);
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let normal = normalize(input.normal);
    let light = normalize(frame.light_dir.xyz);
    let diffuse = max(dot(normal, light), 0.0);
    let ambient = frame.lighting.x;
    let intensity = frame.lighting.y;
    let shadow = shadow_visibility(input);
    let rim = pow(1.0 - max(abs(normal.z), 0.0), 2.0) * 0.12;
    let lit = input.object_color.xyz * frame.light_color.xyz * diffuse * intensity * shadow;
    let shaded = input.object_color.xyz * ambient + lit + vec3<f32>(rim * 0.5 + rim * 0.5 * shadow);
    return vec4<f32>(shaded, 1.0);
}
