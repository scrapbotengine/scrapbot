local WildsCamera = scrapbot.component("wilds_camera", {
	origin = scrapbot.vec3,
	travel = scrapbot.number,
	duration = scrapbot.number,
}, { advanced = true }) :: WildsCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, WildsCamera)

scrapbot.system(Cameras, {
	name = "virtual_wilds.camera",
	writes = { scrapbot.transform },
	reads = { WildsCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	camera: WildsCamera
)
	local duration = math.max(camera.duration, 0.001)
	local tour_frames = math.max(duration * 60, 1)
	local progress = ((time.frame_index - 1) % tour_frames) / tour_frames
	local eased = progress * progress * (3 - 2 * progress)
	local passage = math.sin(progress * math.pi)

	transform.position.x = camera.origin.x + math.sin(progress * math.pi * 3) * 3.2 * passage
	transform.position.y = camera.origin.y + math.sin(progress * math.pi * 2) * 0.8 + eased * 2.2
	transform.position.z = camera.origin.z - camera.travel * eased
	transform.rotation.x = -0.08 + math.sin(progress * math.pi * 2) * 0.025
	transform.rotation.y = math.sin(progress * math.pi * 3 + 0.35) * 0.11 * passage
end)
