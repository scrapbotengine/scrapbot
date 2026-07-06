struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) local_position: vec2<f32>,
    @location(3) rect_size_radius: vec4<f32>,
    @location(4) glyph_rows0: vec4<f32>,
    @location(5) glyph_rows1: vec4<f32>,
    @location(6) glyph_rows2: vec4<f32>,
    @location(7) glyph_rows3: vec4<f32>,
    @location(8) glyph_rows4: vec4<f32>,
    @location(9) glyph_rows5: vec4<f32>,
    @location(10) glyph_rows6: vec4<f32>,
    @location(11) glyph_rows7: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) local_position: vec2<f32>,
    @location(2) rect_size_radius: vec4<f32>,
    @location(3) glyph_rows0: vec4<f32>,
    @location(4) glyph_rows1: vec4<f32>,
    @location(5) glyph_rows2: vec4<f32>,
    @location(6) glyph_rows3: vec4<f32>,
    @location(7) glyph_rows4: vec4<f32>,
    @location(8) glyph_rows5: vec4<f32>,
    @location(9) glyph_rows6: vec4<f32>,
    @location(10) glyph_rows7: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.clip_position = vec4<f32>(input.position, 0.0, 1.0);
    output.color = input.color;
    output.local_position = input.local_position;
    output.rect_size_radius = input.rect_size_radius;
    output.glyph_rows0 = input.glyph_rows0;
    output.glyph_rows1 = input.glyph_rows1;
    output.glyph_rows2 = input.glyph_rows2;
    output.glyph_rows3 = input.glyph_rows3;
    output.glyph_rows4 = input.glyph_rows4;
    output.glyph_rows5 = input.glyph_rows5;
    output.glyph_rows6 = input.glyph_rows6;
    output.glyph_rows7 = input.glyph_rows7;
    return output;
}

fn glyph_row(input: VertexOutput, row: u32) -> u32 {
    let group = row / 4u;
    let slot = row - group * 4u;
    var row_value = 0.0;
    if (group == 0u) {
        row_value = input.glyph_rows0[slot];
    } else if (group == 1u) {
        row_value = input.glyph_rows1[slot];
    } else if (group == 2u) {
        row_value = input.glyph_rows2[slot];
    } else if (group == 3u) {
        row_value = input.glyph_rows3[slot];
    } else if (group == 4u) {
        row_value = input.glyph_rows4[slot];
    } else if (group == 5u) {
        row_value = input.glyph_rows5[slot];
    } else if (group == 6u) {
        row_value = input.glyph_rows6[slot];
    } else {
        row_value = input.glyph_rows7[slot];
    }
    return u32(row_value + 0.5);
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    if (input.rect_size_radius.w < -0.5) {
        let glyph_width = 16u;
        let glyph_height = 32u;
        let pixel_size = max(input.rect_size_radius.z, 0.0001);
        let glyph_x = u32(floor(input.local_position.x / pixel_size));
        let glyph_y = u32(floor(input.local_position.y / pixel_size));
        if (glyph_x >= glyph_width || glyph_y >= glyph_height) {
            discard;
        }
        let row = glyph_row(input, glyph_y);
        let bit = 1u << (glyph_width - 1u - glyph_x);
        if ((row & bit) == 0u) {
            discard;
        }
        return input.color;
    }

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
