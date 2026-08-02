local ArchiveCamera = scrapbot.component("archive_camera", {
	origin = scrapbot.vec3,
	travel = scrapbot.number,
	duration = scrapbot.number,
}, { advanced = true }) :: ArchiveCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, ArchiveCamera)
scrapbot.system(Cameras, {
	name = "archive_camera",
	writes = { scrapbot.transform },
	reads = { ArchiveCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	camera: ArchiveCamera
)
	local duration = math.max(camera.duration, 0.001)
	local progress = (time.elapsed_time % duration) / duration
	local eased = progress * progress * (3 - 2 * progress)
	local breath = math.sin(time.elapsed_time * 0.37)
	transform.position.x = camera.origin.x + math.sin(progress * math.pi * 4) * 1.25
	transform.position.y = camera.origin.y + breath * 0.55
	transform.position.z = camera.origin.z - camera.travel * eased
	transform.rotation.x = -0.035 + math.sin(time.elapsed_time * 0.21) * 0.025
	transform.rotation.y = math.sin(progress * math.pi * 4 + 0.6) * 0.085
end)
