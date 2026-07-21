package render

WGPU_RENDER_SHADER :: `
struct Render_Uniform {
	mvp: array<mat4x4<f32>, 64>,
	model: array<mat4x4<f32>, 64>,
	normal_model: array<mat4x4<f32>, 64>,
	shadow_mvp: array<mat4x4<f32>, 64>,
	color: array<vec4<f32>, 64>,
	emissive: array<vec4<f32>, 64>,
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
	@location(6) emissive: vec3<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
	var output: Vertex_Output;
	output.position = render.mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.world_position = (render.model[instance_index] * vec4<f32>(input.position, 1.0)).xyz;
	output.world_normal = normalize((render.normal_model[instance_index] * vec4<f32>(input.normal, 0.0)).xyz);
	output.color = render.color[instance_index].rgb;
	output.emissive = render.emissive[instance_index].rgb;
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
	return vec4<f32>(base_color * lighting + input.emissive, 1.0);
}
`

WGPU_POST_PROCESS_SHADER :: `
@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var destination_texture: texture_storage_2d<rgba16float, write>;

fn tent_sample(uv: vec2<f32>) -> vec3<f32> {
	let texel = 1.0 / vec2<f32>(textureDimensions(source_texture));
	var color = textureSampleLevel(source_texture, linear_sampler, uv, 0.0).rgb * 4.0;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>( 1.0, -1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>(-1.0,  1.0), 0.0).rgb;
	color += textureSampleLevel(source_texture, linear_sampler, uv + texel * vec2<f32>( 1.0,  1.0), 0.0).rgb;
	return color * 0.125;
}

fn destination_uv(pixel: vec2<u32>) -> vec2<f32> {
	return (vec2<f32>(pixel) + vec2<f32>(0.5)) / vec2<f32>(textureDimensions(destination_texture));
}

@compute @workgroup_size(8, 8)
fn bright_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(destination_texture);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let color = tent_sample(destination_uv(invocation.xy));
	let brightness = max(color.r, max(color.g, color.b));
	let knee = 0.5;
	let soft = clamp(brightness - 1.0 + knee, 0.0, 2.0 * knee);
	let contribution = max(brightness - 1.0, soft * soft / (4.0 * knee + 0.0001));
	let result = color * contribution / max(brightness, 0.0001);
	textureStore(destination_texture, vec2<i32>(invocation.xy), vec4<f32>(result, 1.0));
}

@compute @workgroup_size(8, 8)
fn downsample_cs(@builtin(global_invocation_id) invocation: vec3<u32>) {
	let dimensions = textureDimensions(destination_texture);
	if (invocation.x >= dimensions.x || invocation.y >= dimensions.y) {
		return;
	}
	let uv = destination_uv(invocation.xy);
	let texel = 1.5 / vec2<f32>(textureDimensions(source_texture));
	var color = textureSampleLevel(source_texture, linear_sampler, uv, 0.0).rgb * 0.20;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb * 0.12;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb * 0.08;
	color += textureSampleLevel(source_texture, linear_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.08;
	textureStore(destination_texture, vec2<i32>(invocation.xy), vec4<f32>(color, 1.0));
}
`

WGPU_COMPOSITE_SHADER :: `
@group(0) @binding(0) var hdr_texture: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var bloom_0: texture_2d<f32>;
@group(0) @binding(3) var bloom_1: texture_2d<f32>;
@group(0) @binding(4) var bloom_2: texture_2d<f32>;
@group(0) @binding(5) var bloom_3: texture_2d<f32>;
@group(0) @binding(6) var bloom_4: texture_2d<f32>;

struct Fullscreen_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
};

@vertex
fn fullscreen_vs(@builtin(vertex_index) index: u32) -> Fullscreen_Output {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(3.0, -1.0),
		vec2<f32>(-1.0, 3.0),
	);
	var output: Fullscreen_Output;
	output.position = vec4<f32>(positions[index], 0.0, 1.0);
	output.uv = output.position.xy * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
	return output;
}

fn aces(color: vec3<f32>) -> vec3<f32> {
	return clamp(
		(color * (2.51 * color + vec3<f32>(0.03))) /
		(color * (2.43 * color + vec3<f32>(0.59)) + vec3<f32>(0.14)),
		vec3<f32>(0.0),
		vec3<f32>(1.0),
	);
}

@fragment
fn composite_fs(input: Fullscreen_Output) -> @location(0) vec4<f32> {
	var bloom = textureSample(bloom_0, linear_sampler, input.uv).rgb * 0.34;
	bloom += textureSample(bloom_1, linear_sampler, input.uv).rgb * 0.26;
	bloom += textureSample(bloom_2, linear_sampler, input.uv).rgb * 0.20;
	bloom += textureSample(bloom_3, linear_sampler, input.uv).rgb * 0.13;
	bloom += textureSample(bloom_4, linear_sampler, input.uv).rgb * 0.07;
	let hdr = textureSample(hdr_texture, linear_sampler, input.uv).rgb + bloom * 0.8;
	return vec4<f32>(aces(hdr), 1.0);
}
`

WGPU_UI_SHADER :: `
@group(0) @binding(0) var font_texture: texture_2d_array<f32>;
@group(0) @binding(1) var font_sampler: sampler;
@group(0) @binding(2) var viewport_texture_0: texture_2d<f32>;
@group(0) @binding(3) var viewport_texture_1: texture_2d<f32>;
@group(0) @binding(4) var viewport_texture_2: texture_2d<f32>;
@group(0) @binding(5) var viewport_texture_3: texture_2d<f32>;
@group(0) @binding(6) var viewport_texture_4: texture_2d<f32>;
@group(0) @binding(7) var viewport_texture_5: texture_2d<f32>;
@group(0) @binding(8) var viewport_texture_6: texture_2d<f32>;
@group(0) @binding(9) var viewport_texture_7: texture_2d<f32>;
struct Input {@location(0) position:vec2<f32>,@location(1) uv:vec2<f32>,@location(2) color:vec4<f32>,@location(3) kind:f32,@location(4) size_radius:vec3<f32>,@location(5) clip:vec4<f32>,@location(6) border_color:vec4<f32>,@location(7) border_width:f32,@location(8) font_layer:f32};
struct Output {@builtin(position) position:vec4<f32>,@location(0) uv:vec2<f32>,@location(1) color:vec4<f32>,@location(2) kind:f32,@location(3) size_radius:vec3<f32>,@location(4) @interpolate(flat) clip:vec4<f32>,@location(5) border_color:vec4<f32>,@location(6) border_width:f32,@location(7) @interpolate(flat) font_layer:f32};
@vertex fn ui_vs(input:Input)->Output {var output:Output;output.position=vec4<f32>(input.position,0.0,1.0);output.uv=input.uv;output.color=input.color;output.kind=input.kind;output.size_radius=input.size_radius;output.clip=input.clip;output.border_color=input.border_color;output.border_width=input.border_width;output.font_layer=input.font_layer;return output;}
fn median(value:vec3<f32>)->f32{return max(min(value.r,value.g),min(max(value.r,value.g),value.b));}
fn font_screen_pixel_range(uv:vec2<f32>)->f32{let unit_range=vec2<f32>(8.0)/vec2<f32>(textureDimensions(font_texture));let screen_texture_size=vec2<f32>(1.0)/fwidth(uv);return max(0.5*dot(unit_range,screen_texture_size),1.0);}
fn segment_distance(point:vec2<f32>,a:vec2<f32>,b:vec2<f32>)->f32{let segment=b-a;let projection=clamp(dot(point-a,segment)/max(dot(segment,segment),0.0001),0.0,1.0);return length(point-(a+segment*projection));}
fn sample_viewport(layer:i32,uv:vec2<f32>)->vec4<f32>{switch layer{case 0:{return textureSample(viewport_texture_0,font_sampler,uv);}case 1:{return textureSample(viewport_texture_1,font_sampler,uv);}case 2:{return textureSample(viewport_texture_2,font_sampler,uv);}case 3:{return textureSample(viewport_texture_3,font_sampler,uv);}case 4:{return textureSample(viewport_texture_4,font_sampler,uv);}case 5:{return textureSample(viewport_texture_5,font_sampler,uv);}case 6:{return textureSample(viewport_texture_6,font_sampler,uv);}default:{return textureSample(viewport_texture_7,font_sampler,uv);}}}
@fragment fn ui_fs(input:Output)->@location(0) vec4<f32>{if input.position.x<input.clip.x||input.position.y<input.clip.y||input.position.x>=input.clip.z||input.position.y>=input.clip.w{discard;}if input.kind>5.5{return sample_viewport(i32(input.font_layer),input.uv)*input.color;}if input.kind>4.5 {let size=max(input.size_radius.xy,vec2<f32>(0.001));let point=input.uv*size;let a=vec2<f32>(size.x*0.08,size.y*0.48);let b=vec2<f32>(size.x*0.38,size.y*0.78);let c=vec2<f32>(size.x*0.92,size.y*0.18);let distance=min(segment_distance(point,a,b),segment_distance(point,b,c));let edge=distance-input.size_radius.z*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>3.5 {let size=max(input.size_radius.xy,vec2<f32>(0.001));let point=input.uv*size;var a=vec2<f32>(size.x*0.30,size.y*0.18);var b=vec2<f32>(size.x*0.70,size.y*0.50);var c=vec2<f32>(size.x*0.30,size.y*0.82);if input.size_radius.z<0.0 {a=vec2<f32>(size.x*0.18,size.y*0.30);b=vec2<f32>(size.x*0.50,size.y*0.70);c=vec2<f32>(size.x*0.82,size.y*0.30);}let distance=min(segment_distance(point,a,b),segment_distance(point,b,c));let edge=distance-abs(input.size_radius.z)*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>2.5 {let half_size=max(input.size_radius.xy*0.5,vec2<f32>(0.001));let point=(input.uv*2.0-1.0)*half_size;let k0=length(point/half_size);let k1=max(length(point/(half_size*half_size)),0.0001);let distance=k0*(k0-0.92)/k1;let edge=abs(distance)-input.size_radius.z*0.5;let smoothing=max(fwidth(edge),0.65);let coverage=1.0-smoothstep(-smoothing,smoothing,edge);return vec4<f32>(input.color.rgb,input.color.a*coverage);}if input.kind>1.5{return input.color;}if input.kind>0.5 {let distance=median(textureSample(font_texture,font_sampler,input.uv,i32(input.font_layer)).rgb);let screen_distance=font_screen_pixel_range(input.uv)*(distance-0.5);let coverage=clamp(screen_distance+0.5,0.0,1.0);return vec4<f32>(input.color.rgb,input.color.a*coverage);}let radius=min(input.size_radius.z,min(input.size_radius.x,input.size_radius.y)*0.5);let point=input.uv*input.size_radius.xy-input.size_radius.xy*0.5;let q=abs(point)-(input.size_radius.xy*0.5-vec2<f32>(radius));let distance=length(max(q,vec2<f32>(0.0)))+min(max(q.x,q.y),0.0)-radius;let smoothing=max(fwidth(distance),0.75);let coverage=1.0-smoothstep(-smoothing,smoothing,distance);let border_mix=smoothstep(-input.border_width-smoothing,-input.border_width+smoothing,distance)*step(0.001,input.border_width)*input.border_color.a;let surface=mix(input.color,input.border_color,border_mix);return vec4<f32>(surface.rgb,surface.a*coverage);}
`

WGPU_VIEWPORT_TEXTURE_SHADER :: `
@group(0) @binding(0) var source_texture: texture_2d<f32>;
@group(0) @binding(1) var source_sampler: sampler;
struct Output {@builtin(position) position:vec4<f32>,@location(0) uv:vec2<f32>};
@vertex fn vs_main(@builtin(vertex_index) index:u32)->Output{var positions=array<vec2<f32>,3>(vec2<f32>(-1.0,-1.0),vec2<f32>(3.0,-1.0),vec2<f32>(-1.0,3.0));var output:Output;output.position=vec4<f32>(positions[index],0.0,1.0);output.uv=positions[index]*vec2<f32>(0.5,-0.5)+vec2<f32>(0.5,0.5);return output;}
@fragment fn fs_main(input:Output)->@location(0) vec4<f32>{return textureSample(source_texture,source_sampler,input.uv);}
`
