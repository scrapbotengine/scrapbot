struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) local_position: vec2<f32>,
    @location(3) rect_size_radius: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) local_position: vec2<f32>,
    @location(2) rect_size_radius: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.clip_position = vec4<f32>(input.position, 0.0, 1.0);
    output.color = input.color;
    output.local_position = input.local_position;
    output.rect_size_radius = input.rect_size_radius;
    return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    if (input.rect_size_radius.w < 0.5) {
        return input.color;
    }

    let size = input.rect_size_radius.xy;
    let radius = clamp(input.rect_size_radius.z, 0.0, min(size.x, size.y) * 0.5);
    let half_size = size * 0.5;
    let p = input.local_position - half_size;
    let q = abs(p) - (half_size - vec2<f32>(radius));
    let distance = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    let edge_width = max(fwidth(distance), 1.0);
    let coverage = 1.0 - smoothstep(0.0, edge_width, distance);
    let alpha = input.color.a * coverage;
    if (alpha <= 0.001) {
        discard;
    }
    return vec4<f32>(input.color.rgb, alpha);
}
