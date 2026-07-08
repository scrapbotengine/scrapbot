--!strict

type Scrapbot = {
	log: (message: any) -> (),
	entity_count: () -> number,
	renderable_count: () -> number,
	component: <T>(name: string, schema: ScrapbotComponentSchema) -> ScrapbotComponent<T>,
	system: (system: (delta_seconds: number) -> ()) -> (),
	query: <T>(component: ScrapbotComponent<T>, callback: (entity: ScrapbotEntity, component: T) -> ()) -> (),
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

type ScrapbotComponent<T> = {
	name: string,
}

type ScrapbotComponentSchema = {
	[string]: ScrapbotComponentFieldType,
}

type ScrapbotComponentFieldType = "vec3"

declare scrapbot: Scrapbot
