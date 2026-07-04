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
var scene_texture: texture_2d<f32>;

@group(0) @binding(2)
var scene_sampler: sampler;

@group(0) @binding(3)
var bloom_level_0: texture_2d<f32>;

@group(0) @binding(4)
var bloom_level_1: texture_2d<f32>;

@group(0) @binding(5)
var bloom_level_2: texture_2d<f32>;

@group(0) @binding(6)
var bloom_level_3: texture_2d<f32>;

@group(0) @binding(7)
var bloom_level_4: texture_2d<f32>;

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

fn luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn sample_scene(uv: vec2<f32>) -> vec3<f32> {
    return textureSample(scene_texture, scene_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0))).rgb;
}

fn fxaa(uv: vec2<f32>, texel: vec2<f32>) -> vec3<f32> {
    let center = sample_scene(uv);
    let north = sample_scene(uv + vec2<f32>(0.0, -texel.y));
    let south = sample_scene(uv + vec2<f32>(0.0, texel.y));
    let west = sample_scene(uv + vec2<f32>(-texel.x, 0.0));
    let east = sample_scene(uv + vec2<f32>(texel.x, 0.0));

    let edge_horizontal = abs(luma(west) - luma(east));
    let edge_vertical = abs(luma(north) - luma(south));
    let edge = max(edge_horizontal, edge_vertical);
    let blend = smoothstep(0.035, 0.18, edge);
    let filtered = (north + south + west + east) * 0.25;
    return mix(center, filtered, blend * 0.72);
}

fn bloom(uv: vec2<f32>, color: vec3<f32>) -> vec3<f32> {
    if post.params2.x < 0.5 {
        return color;
    }

    let intensity = post.params2.z;
    let clamped_uv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    var glow = textureSample(bloom_level_0, scene_sampler, clamped_uv).rgb * 0.36;
    glow = glow + textureSample(bloom_level_1, scene_sampler, clamped_uv).rgb * 0.26;
    glow = glow + textureSample(bloom_level_2, scene_sampler, clamped_uv).rgb * 0.18;
    glow = glow + textureSample(bloom_level_3, scene_sampler, clamped_uv).rgb * 0.12;
    glow = glow + textureSample(bloom_level_4, scene_sampler, clamped_uv).rgb * 0.08;
    return color + glow * intensity;
}

fn chromatic_aberration(uv: vec2<f32>, texel: vec2<f32>, color: vec3<f32>) -> vec3<f32> {
    let strength = post.params0.w;
    if strength <= 0.0 {
        return color;
    }

    let from_center = uv - vec2<f32>(0.5);
    let direction = normalize(from_center + vec2<f32>(0.0001));
    let distance = length(from_center) * 2.0;
    let offset = direction * strength * distance * vec2<f32>(1.0, 0.75) + texel * strength * 40.0;
    return vec3<f32>(
        sample_scene(uv + offset).r,
        color.g,
        sample_scene(uv - offset).b,
    );
}

fn vignette(uv: vec2<f32>, color: vec3<f32>) -> vec3<f32> {
    if post.params1.x < 0.5 {
        return color;
    }

    let strength = post.params1.y;
    let radius = max(post.params1.z, 0.001);
    let centered = uv - vec2<f32>(0.5);
    let distance = length(centered) / radius;
    let shade = 1.0 - smoothstep(0.45, 1.18, distance) * strength;
    return color * clamp(shade, 0.0, 1.0);
}

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + vec3<f32>(b))) / (color * (c * color + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn tone_map(color: vec3<f32>) -> vec3<f32> {
    let exposure = exp2(post.params3.y);
    let exposed = max(color * exposure, vec3<f32>(0.0));
    if post.params3.z < 0.5 {
        return exposed;
    }
    if post.params3.z < 1.5 {
        return exposed / (exposed + vec3<f32>(1.0));
    }
    return aces_tonemap(exposed);
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let texel = post.params0.xy;
    var color = sample_scene(input.uv);
    if post.params0.z > 0.5 {
        color = fxaa(input.uv, texel);
    }
    color = bloom(input.uv, color);
    color = chromatic_aberration(input.uv, texel, color);
    color = tone_map(color);
    color = vignette(input.uv, color);
    return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}
