--!strict

type Scrapbot = {
	log: (message: any) -> (),
	entity_count: () -> number,
	renderable_count: () -> number,
}

declare scrapbot: Scrapbot
