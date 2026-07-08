--!strict

type Scrapbot = {
	log: (message: any) -> (),
	entity_count: () -> number,
	renderable_count: () -> number,
	component: (name: string, schema: ScrapbotComponentSchema) -> (),
	system: (system: (delta_seconds: number) -> ()) -> (),
	query: (component_name: string, callback: (entity: ScrapbotEntity, component: any) -> ()) -> (),
	get_rotation: (entity: ScrapbotEntity) -> ScrapbotVec3,
	set_rotation: (entity: ScrapbotEntity, rotation: ScrapbotVec3) -> (),
}

type ScrapbotEntity = {
	index: number,
	name: string?,
}

type ScrapbotVec3 = {
	x: number,
	y: number,
	z: number,
}

type ScrapbotComponentSchema = {
	[string]: "vec3",
}

declare scrapbot: Scrapbot
