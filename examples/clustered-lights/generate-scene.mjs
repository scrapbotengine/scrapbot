import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const RING_COUNT = 20;
const DARK_MATERIAL = "c1a57000-1000-4000-8000-000000000001";
const MID_MATERIAL = "c1a57000-1000-4000-8000-000000000002";
const SCULPTURE_MATERIAL = "c1a57000-1000-4000-8000-000000000003";

const output = fileURLToPath(new URL("scenes/main.scene.toml", import.meta.url));
const lines = [
	'[[entities]]',
	'id = "c1a57000-0000-4000-8000-000000000001"',
	'name = "Main Camera"',
	"",
	"[entities.transform]",
	"position = [0, 3.9, 14]",
	"rotation = [-0.02, 0, 0]",
	"scale = [1, 1, 1]",
	"",
	"[entities.camera]",
	"fov = 62",
	"near = 0.1",
	"far = 120",
	"exposure = 1.15",
	"",
	"[entities.components.camera_drift]",
	"origin = [0, 3.9, 14]",
	"",
	"[[entities]]",
	'id = "c1a57000-0000-4000-8000-000000000002"',
	'name = "Night Environment"',
	"",
	"[entities.world_environment]",
	'lighting = ""',
	"lighting_intensity = 1",
	"lighting_rotation = 0",
	"exposure = 1.15",
	"background_visible = true",
	'background = ""',
	"background_intensity = 1",
	"background_rotation = 0",
	"background_exposure = 0.58",
	"background_blur = 0",
	"sky_tint = [0.12, 0.16, 0.28]",
	"ground_color = [0.025, 0.032, 0.06]",
	"turbidity = 1.8",
	"atmosphere_thickness = 0.45",
	"horizon_softness = 0.8",
	"sun_direction = [-0.4, 0.01, -0.91]",
	"sun_color = [0.3, 0.4, 0.75]",
	"sun_intensity = 0.05",
	"sun_size = 0.35",
	"sun_glow = 0.15",
	"",
	"[[entities]]",
	'id = "c1a57000-0000-4000-8000-000000000003"',
	'name = "Deep Ambient"',
	"",
	"[entities.ambient_light]",
	"color = [0.35, 0.42, 0.6]",
	"intensity = 0.55",
	"",
];

let nextEntityId = 0x100;

function number(value) {
	const rounded = Math.round(value * 1_000_000) / 1_000_000;
	return Object.is(rounded, -0) ? "0" : String(rounded);
}

function vector(values) {
	return `[${values.map(number).join(", ")}]`;
}

function entityId() {
	const suffix = nextEntityId.toString(16).padStart(12, "0");
	nextEntityId += 1;
	return `c1a57000-0000-4000-8000-${suffix}`;
}

function addRenderable({
	name,
	position,
	rotation = [0, 0, 0],
	scale,
	geometry,
	material,
	spin,
}) {
	lines.push(
		"[[entities]]",
		`id = "${entityId()}"`,
		`name = "${name}"`,
		"",
		"[entities.transform]",
		`position = ${vector(position)}`,
		`rotation = ${vector(rotation)}`,
		`scale = ${vector(scale)}`,
		"",
		"[entities.geometry]",
		`resource = "${geometry}"`,
		"",
		"[entities.material]",
		`resource = "${material}"`,
		"",
		"[entities.shadow_caster]",
		"",
		"[entities.shadow_receiver]",
	);
	if (spin) {
		lines.push(
			"",
			"[entities.components.sculpture_spin]",
			`speed = ${vector(spin)}`,
		);
	}
	lines.push("");
}

function addBlock(name, x, y, z, scaleX, scaleY, scaleZ, material) {
	addRenderable({
		name,
		position: [x, y, z],
		scale: [scaleX, scaleY, scaleZ],
		geometry: "cube",
		material,
	});
}

addBlock("Cathedral Floor", 0, -0.35, -19, 10, 0.25, 27, DARK_MATERIAL);
addBlock("Cathedral Ceiling", 0, 8.35, -19, 10, 0.2, 27, DARK_MATERIAL);
addBlock("Cathedral Left Wall", -10.15, 4, -19, 0.2, 4.2, 27, DARK_MATERIAL);
addBlock("Cathedral Right Wall", 10.15, 4, -19, 0.2, 4.2, 27, DARK_MATERIAL);
addBlock("Cathedral End Wall", 0, 4, -46, 10, 4.2, 0.25, DARK_MATERIAL);

for (let ring = 0; ring < RING_COUNT; ring += 1) {
	const z = 3 - ring * 3.25;
	const ribMaterial = ring % 2 === 0 ? MID_MATERIAL : DARK_MATERIAL;
	addBlock("Left Rib", -8.7, 3.45, z, 0.3, 3.45, 0.3, ribMaterial);
	addBlock("Right Rib", 8.7, 3.45, z, 0.3, 3.45, 0.3, ribMaterial);
	addBlock("Ceiling Rib", 0, 7.15, z, 8.7, 0.28, 0.3, ribMaterial);

	for (let pedestal = -1; pedestal <= 1; pedestal += 1) {
		const x = pedestal * 4.8;
		const height = 0.3 + ((ring + pedestal + 3) % 4) * 0.18;
		addBlock("Floor Prism", x, height * 0.5 - 0.08, z, 0.62, height, 0.62, MID_MATERIAL);
	}

	if (ring % 2 === 0) {
		addRenderable({
			name: "Suspended Sculpture",
			position: [
				Math.sin(ring * 1.7) * 2.4,
				3.1 + Math.cos(ring * 0.9) * 0.7,
				z - 1.45,
			],
			rotation: [ring * 0.17, ring * 0.29, 0],
			scale: [0.72, 0.72, 0.72],
			geometry: "cluster.sculpture",
			material: SCULPTURE_MATERIAL,
			spin: [
				0.09 + ring * 0.004,
				0.18 + ring * 0.007,
				0.055,
			],
		});
	}
}

while (lines.at(-1) === "") {
	lines.pop();
}
const generated = `${lines.join("\n")}\n`;
if (process.argv.includes("--check")) {
	if (readFileSync(output, "utf8") !== generated) {
		console.error("clustered-lights scene is stale; run node generate-scene.mjs");
		process.exit(1);
	}
} else {
	writeFileSync(output, generated);
}
