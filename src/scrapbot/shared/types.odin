package shared

PROJECT_FILE :: "project.toml"
DEFAULT_SCENE :: "scenes/main.scene.toml"
DEFAULT_SCRIPT :: "scripts/main.luau"
DEFAULT_LUAU_TYPES :: "types/scrapbot.d.luau"
DEFAULT_VSCODE_SETTINGS :: ".vscode/settings.json"

VERSION :: "0.1.0-dev"

Vec3 :: struct {
	x, y, z: f32,
}

Renderer_Backend :: enum {
	Null,
	WGPU,
}

Project_Config :: struct {
	name:          string,
	default_scene: string,
	native_extensions: [dynamic]Native_Extension_Target,
}

Native_Extension_Target :: struct {
	name:   string,
	source: string,
}

Scene :: struct {
	entities: [dynamic]Scene_Entity,
}

Scene_Entity :: struct {
	name: string,

	has_transform: bool,
	transform:     Transform_Component,

	has_camera: bool,
	camera:     Camera_Component,
	has_ambient_light: bool,
	ambient_light: Ambient_Light_Component,
	has_directional_light: bool,
	directional_light: Directional_Light_Component,
	has_point_light: bool,
	point_light: Point_Light_Component,

	has_mesh: bool,
	mesh:     Mesh_Component,
	has_geometry: bool,
	geometry_resource: string,
	has_material: bool,
	material_resource: string,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,

	custom_components: [dynamic]Custom_Component,
}

Entity :: struct {
	index:      u32,
	generation: u32,
}

Component_ID :: int
INVALID_COMPONENT_ID :: Component_ID(0)

Geometry_Handle :: struct {index, generation: u32}
Material_Handle :: struct {index, generation: u32}

Time_Resource :: struct {
	delta_time:        f32,
	smooth_delta_time: f32,
	elapsed_time:      f64,
	frame_index:       u64,
}

Transform_Component :: struct {
	position: Vec3,
	rotation: Vec3,
	scale:    Vec3,
}

Camera_Component :: struct {
	fov:  f32,
	near: f32,
	far:  f32,
}

Ambient_Light_Component :: struct {color: Vec3, intensity: f32}
Directional_Light_Component :: struct {direction, color: Vec3, intensity: f32}
Point_Light_Component :: struct {color: Vec3, intensity, range: f32}

Mesh_Component :: struct {
	primitive: string,
}

Geometry_Component :: struct {handle: Geometry_Handle}
Material_Component :: struct {handle: Material_Handle}
Render_Instance_Component :: struct {
	geometry: Geometry_Handle,
	material: Material_Handle,
}

Named_Vec3 :: struct {
	name:  string,
	value: Vec3,
}

Custom_Component :: struct {
	entity_index: int,
	component_id: Component_ID,
	name:         string,
	vec3_fields: [dynamic]Named_Vec3,
}

Custom_Component_Storage :: struct {
	component_id: Component_ID,
	name:         string,
	components:   [dynamic]Custom_Component,
}

World_Entity :: struct {
	id:              Entity,
	alive:           bool,
	name:            string,
	transform_index: int,
	camera_index:    int,
	ambient_light_index: int,
	directional_light_index: int,
	point_light_index: int,
	mesh_index:      int,
	geometry_index:  int,
	material_index:  int,
	render_instance_index: int,
	has_shadow_caster: bool,
	has_shadow_receiver: bool,
	geometry_resource: string,
	material_resource: string,
}

Renderable :: struct {
	entity_index:    int,
	transform_index: int,
	mesh_index:      int,
}

Render_Instance :: struct {
	entity:    World_Entity,
	transform: Transform_Component,
	mesh:      Mesh_Component,
	geometry:  Geometry_Component,
	material:  Material_Component,
	shadow_caster: bool,
	shadow_receiver: bool,
}

Camera_Instance :: struct {
	entity:    World_Entity,
	transform: Transform_Component,
	camera:    Camera_Component,
}

Directional_Light_Instance :: struct {light: Directional_Light_Component}
Point_Light_Instance :: struct {position: Vec3, light: Point_Light_Component}

MAX_DIRECTIONAL_LIGHTS :: 4
MAX_POINT_LIGHTS :: 16

Render_List :: struct {
	instances:  [dynamic]Render_Instance,
	camera:     Camera_Instance,
	has_camera: bool,
	ambient: Vec3,
	directional_lights: [MAX_DIRECTIONAL_LIGHTS]Directional_Light_Instance,
	directional_light_count: int,
	point_lights: [MAX_POINT_LIGHTS]Point_Light_Instance,
	point_light_count: int,
}

World :: struct {
	time:       Time_Resource,
	entities:   [dynamic]World_Entity,
	transforms: #soa[dynamic]Transform_Component,
	cameras:    [dynamic]Camera_Component,
	ambient_lights: [dynamic]Ambient_Light_Component,
	directional_lights: [dynamic]Directional_Light_Component,
	point_lights: [dynamic]Point_Light_Component,
	meshes:     [dynamic]Mesh_Component,
	renderables: [dynamic]Renderable,
	geometries: [dynamic]Geometry_Component,
	materials: [dynamic]Material_Component,
	render_instances: [dynamic]Render_Instance_Component,
	custom_components: [dynamic]Custom_Component_Storage,
}

Render_Frame :: struct {
	entity_count:     int,
	camera_count:     int,
	mesh_count:       int,
	renderable_count: int,
}

component_name_is_valid :: proc "c" (name: string) -> bool {
	if name == "" {
		return false
	}

	token_start := 0
	for c, index in name {
		if c == '.' {
			if !component_token_is_valid(name[token_start:index]) {
				return false
			}
			token_start = index + 1
		}
	}

	return component_token_is_valid(name[token_start:])
}

component_name_is_project_level :: proc "c" (name: string) -> bool {
	return component_name_is_valid(name) && !component_name_is_namespaced(name)
}

component_name_is_namespaced :: proc "c" (name: string) -> bool {
	for c in name {
		if c == '.' {
			return true
		}
	}
	return false
}

component_token_is_valid :: proc "c" (token: string) -> bool {
	if token == "" {
		return false
	}
	for c in token {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' {
			continue
		}
		return false
	}
	return true
}
