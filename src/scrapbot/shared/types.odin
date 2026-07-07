package shared

PROJECT_FILE :: "project.toml"
DEFAULT_SCENE :: "scenes/main.scene.toml"

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
	id:   Entity,
	name: string,
}

World :: struct {
	entities:   [dynamic]World_Entity,
	transforms: #soa[dynamic]Transform_Component,
	cameras:    [dynamic]Camera_Component,
	meshes:     [dynamic]Mesh_Component,
}

Render_Frame :: struct {
	entity_count: int,
	camera_count: int,
	mesh_count:   int,
}
