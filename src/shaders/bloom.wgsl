struct PostProcessUniforms {
    params0: vec4<f32>,
    params1: vec4<f32>,
    params2: vec4<f32>,
    params3: vec4<f32>,
    params4: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> post: PostProcessUniforms;

@group(0) @binding(1)
var input_texture: texture_2d<f32>;

@group(0) @binding(2)
var input_sampler: sampler;

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    let positions = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -3.0),
        vec2<f32>(3.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );
    let position = positions[vertex_index];

    var output: VertexOutput;
    output.clip_position = vec4<f32>(position, 0.0, 1.0);
    output.uv = position * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5, 0.5);
    return output;
}

fn sample_input(uv: vec2<f32>) -> vec3<f32> {
    return textureSample(input_texture, input_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0))).rgb;
}

@fragment
fn fs_extract(input: VertexOutput) -> @location(0) vec4<f32> {
    let color = sample_input(input.uv);
    if post.params4.x > 0.5 {
        return vec4<f32>(color, 1.0);
    }

    let brightness = max(color.r, max(color.g, color.b));
    let threshold = post.params2.y;
    let knee = max(threshold * 0.45, 0.0001);
    let soft = clamp((brightness - threshold + knee) / (2.0 * knee), 0.0, 1.0);
    let contribution = max(brightness - threshold, 0.0) + soft * soft * knee;
    let scale = contribution / max(brightness, 0.0001);
    return vec4<f32>(color * scale, 1.0);
}

@fragment
fn fs_blur(input: VertexOutput) -> @location(0) vec4<f32> {
    let dimensions = vec2<f32>(textureDimensions(input_texture, 0));
    let texel = 1.0 / max(dimensions, vec2<f32>(1.0));
    let direction = post.params4.xy;
    let level = post.params4.z;
    let radius = max(post.params2.w + level * 0.45, 0.25);
    let sample_step = direction * texel * radius;

    var color = sample_input(input.uv) * 0.227027;
    color = color + sample_input(input.uv + sample_step * 1.384615) * 0.316216;
    color = color + sample_input(input.uv - sample_step * 1.384615) * 0.316216;
    color = color + sample_input(input.uv + sample_step * 3.230769) * 0.070270;
    color = color + sample_input(input.uv - sample_step * 3.230769) * 0.070270;
    return vec4<f32>(color, 1.0);
}
