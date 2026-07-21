import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const frames = Number.parseInt(process.argv[2] ?? "2000", 10);
const spawnRate = Number.parseInt(process.argv[3] ?? "500", 10);

function fail(message) {
	console.error(`native query benchmark failed: ${message}`);
	process.exit(1);
}

if (!Number.isInteger(frames) || frames < 120 || !Number.isFinite(spawnRate) || spawnRate < 1) {
	fail("usage: benchmark_native_queries.mjs [frames >= 120] [spawn rate >= 1]");
}

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "scrapbot-native-query-"));
const project = path.join(temporaryRoot, "ecs-showcase-stress");
try {
	fs.cpSync(path.join(root, "examples", "ecs-showcase"), project, {
		recursive: true,
		filter(source) {
			const relative = path.relative(path.join(root, "examples", "ecs-showcase"), source);
			return relative !== "build" && !relative.startsWith(`build${path.sep}`) &&
				relative !== ".scrapbot" && !relative.startsWith(`.scrapbot${path.sep}`);
		},
	});
	const scenePath = path.join(project, "scenes", "main.scene.toml");
	const scene = fs.readFileSync(scenePath, "utf8");
	const stressed = scene.replace(/spawn_rate = [0-9.]+/, `spawn_rate = ${spawnRate}`);
	if (stressed === scene) {
		fail("could not locate showcase emitter spawn_rate");
	}
	fs.writeFileSync(scenePath, stressed);

	const result = spawnSync(
		path.join(root, "bin", "scrapbot"),
		[
			"run", project,
			"--backend", "null",
			"--headless",
			"--no-hot-reload",
			"--frames", String(frames),
			"--runtime-stats",
			"--json",
		],
		{ cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
	);
	if (result.error || result.status !== 0) {
		fail(result.error?.message ?? result.stderr.trim() ?? result.stdout.trim());
	}
	const document = JSON.parse(result.stdout);
	const stats = document.result?.runtime_stats;
	const query = stats?.native_queries;
	if (!document.ok || !stats?.enabled || !query || query.chunks < 1 || query.entities < 1) {
		fail("runtime did not return native query diagnostics");
	}
	const milliseconds = stats.late_update_ns_per_frame / 1_000_000;
	const fill = query.entities / query.chunks;
	console.log(`${spawnRate} spawns/s, ${frames} frames: ${milliseconds.toFixed(3)} ms/frame`);
	console.log(
		`${query.entities} packed entities / ${query.chunks} chunks ` +
		`(${fill.toFixed(1)} avg), ${query.scalar_tail_lanes} tail lanes`,
	);
	console.log(`${query.plan_builds} compiled plan builds / ${query.plan_hits} retained hits`);
} finally {
	fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
