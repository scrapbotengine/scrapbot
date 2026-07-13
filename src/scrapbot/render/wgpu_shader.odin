package render

WGPU_RENDER_SHADER :: `
struct Render_Uniform {
	mvp: array<mat4x4<f32>, 64>,
	model: array<mat4x4<f32>, 64>,
	normal_model: array<mat4x4<f32>, 64>,
	shadow_mvp: array<mat4x4<f32>, 64>,
	color: array<vec4<f32>, 64>,
	shadow_flags: array<vec4<f32>, 64>,
	ambient: vec4<f32>,
	directional_direction_intensity: array<vec4<f32>, 4>,
	directional_color: array<vec4<f32>, 4>,
	point_position_range: array<vec4<f32>, 16>,
	point_color_intensity: array<vec4<f32>, 16>,
	light_counts: vec4<u32>,
};

@group(0) @binding(0)
var<uniform> render: Render_Uniform;
@group(0) @binding(1) var shadow_map: texture_depth_2d;
@group(0) @binding(2) var shadow_sampler: sampler_comparison;
@group(1) @binding(0) var base_color_texture: texture_2d<f32>;
@group(1) @binding(1) var base_color_sampler: sampler;

struct Vertex_Input {
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
};

struct Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) color: vec3<f32>,
	@location(1) world_position: vec3<f32>,
	@location(2) world_normal: vec3<f32>,
	@location(3) shadow_position: vec4<f32>,
	@location(4) shadow_receiver: f32,
	@location(5) uv: vec2<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
	var output: Vertex_Output;
	output.position = render.mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.world_position = (render.model[instance_index] * vec4<f32>(input.position, 1.0)).xyz;
	output.world_normal = normalize((render.normal_model[instance_index] * vec4<f32>(input.normal, 0.0)).xyz);
	output.color = render.color[instance_index].rgb;
	output.shadow_position = render.shadow_mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.shadow_receiver = render.shadow_flags[instance_index].y;
	output.uv = input.uv;
	return output;
}

@vertex
fn shadow_vs(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> @builtin(position) vec4<f32> {
	if (render.shadow_flags[instance_index].x < 0.5) {
		return vec4<f32>(2.0, 2.0, 2.0, 1.0);
	}
	return render.shadow_mvp[instance_index] * vec4<f32>(input.position, 1.0);
}

@fragment
fn fs_main(input: Vertex_Output) -> @location(0) vec4<f32> {
	let normal = normalize(input.world_normal);
	var lighting = render.ambient.rgb;
	var shadow = 1.0;
	if (input.shadow_receiver > 0.5 && render.light_counts.x > 0u && input.shadow_position.w > 0.0) {
		let projected = input.shadow_position.xyz / input.shadow_position.w;
		let uv = vec2<f32>(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
		if (all(uv >= vec2<f32>(0.0)) && all(uv <= vec2<f32>(1.0)) && projected.z >= 0.0 && projected.z <= 1.0) {
			shadow = textureSampleCompare(shadow_map, shadow_sampler, uv, projected.z - 0.002);
		}
	}
	for (var i: u32 = 0u; i < render.light_counts.x; i = i + 1u) {
		let packed = render.directional_direction_intensity[i];
		let diffuse = max(dot(normal, -normalize(packed.xyz)), 0.0);
		lighting += render.directional_color[i].rgb * packed.w * diffuse * shadow;
	}
	for (var i: u32 = 0u; i < render.light_counts.y; i = i + 1u) {
		let packed = render.point_position_range[i];
		let offset = packed.xyz - input.world_position;
		let distance = length(offset);
		if (distance < packed.w && distance > 0.0001) {
			let diffuse = max(dot(normal, offset / distance), 0.0);
			let range_fade = max(1.0 - distance / packed.w, 0.0);
			let attenuation = range_fade * range_fade / (1.0 + distance * distance);
			lighting += render.point_color_intensity[i].rgb * render.point_color_intensity[i].w * diffuse * attenuation;
		}
	}
	let texture_color = textureSample(base_color_texture, base_color_sampler, input.uv).rgb;
	let base_color = texture_color * pow(max(input.color, vec3<f32>(0.0)), vec3<f32>(2.2));
	let hdr = base_color * lighting;
	let mapped = clamp(
		(hdr * (2.51 * hdr + vec3<f32>(0.03))) /
		(hdr * (2.43 * hdr + vec3<f32>(0.59)) + vec3<f32>(0.14)),
		vec3<f32>(0.0),
		vec3<f32>(1.0),
	);
	return vec4<f32>(mapped, 1.0);
}
`

WGPU_UI_SHADER :: `
@group(0) @binding(0) var font_texture: texture_2d<f32>;
@group(0) @binding(1) var font_sampler: sampler;
struct Input {@location(0) position:vec2<f32>,@location(1) uv:vec2<f32>,@location(2) color:vec4<f32>,@location(3) kind:f32,@location(4) size_radius:vec3<f32>};
struct Output {@builtin(position) position:vec4<f32>,@location(0) uv:vec2<f32>,@location(1) color:vec4<f32>,@location(2) kind:f32,@location(3) size_radius:vec3<f32>};
@vertex fn ui_vs(input:Input)->Output {var output:Output;output.position=vec4<f32>(input.position,0.0,1.0);output.uv=input.uv;output.color=input.color;output.kind=input.kind;output.size_radius=input.size_radius;return output;}
fn median(value:vec3<f32>)->f32{return max(min(value.r,value.g),min(max(value.r,value.g),value.b));}
fn font_screen_pixel_range(uv:vec2<f32>)->f32{let unit_range=vec2<f32>(8.0)/vec2<f32>(textureDimensions(font_texture));let screen_texture_size=vec2<f32>(1.0)/fwidth(uv);return max(0.5*dot(unit_range,screen_texture_size),1.0);}
@fragment fn ui_fs(input:Output)->@location(0) vec4<f32>{if input.kind>0.5 {let distance=median(textureSample(font_texture,font_sampler,input.uv).rgb);let screen_distance=font_screen_pixel_range(input.uv)*(distance-0.5);let coverage=clamp(screen_distance+0.5,0.0,1.0);return vec4<f32>(input.color.rgb,input.color.a*coverage);}let radius=min(input.size_radius.z,min(input.size_radius.x,input.size_radius.y)*0.5);let point=input.uv*input.size_radius.xy-input.size_radius.xy*0.5;let q=abs(point)-(input.size_radius.xy*0.5-vec2<f32>(radius));let distance=length(max(q,vec2<f32>(0.0)))+min(max(q.x,q.y),0.0)-radius;let smoothing=max(fwidth(distance),0.75);let coverage=1.0-smoothstep(-smoothing,smoothing,distance);return vec4<f32>(input.color.rgb,input.color.a*coverage);}
`
