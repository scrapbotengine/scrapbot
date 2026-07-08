package shared

PROJECT_FILE :: "project.toml"
DEFAULT_SCENE :: "scenes/main.scene.toml"
DEFAULT_SCRIPT :: "scripts/main.luau"

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

	has_mesh: bool,
	mesh:     Mesh_Component,
}

Entity :: struct {
	index:      u32,
	generation: u32,
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

Mesh_Component :: struct {
	primitive: string,
}

World_Entity :: struct {
	id:              Entity,
	name:            string,
	transform_index: int,
	camera_index:    int,
	mesh_index:      int,
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
}

Camera_Instance :: struct {
	entity:    World_Entity,
	transform: Transform_Component,
	camera:    Camera_Component,
}

Render_List :: struct {
	instances:  [dynamic]Render_Instance,
	camera:     Camera_Instance,
	has_camera: bool,
}

World :: struct {
	entities:   [dynamic]World_Entity,
	transforms: #soa[dynamic]Transform_Component,
	cameras:    [dynamic]Camera_Component,
	meshes:     [dynamic]Mesh_Component,
	renderables: [dynamic]Renderable,
}

Render_Frame :: struct {
	entity_count:     int,
	camera_count:     int,
	mesh_count:       int,
	renderable_count: int,
}
