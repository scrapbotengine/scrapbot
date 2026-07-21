import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const project = process.argv[2] ?? "examples/ecs-showcase";
const frames = Number.parseInt(process.argv[3] ?? "2000", 10);
const trials = Number.parseInt(process.argv[4] ?? "3", 10);

function fail(message) {
	console.error(`profile benchmark failed: ${message}`);
	process.exit(1);
}

if (!Number.isInteger(frames) || frames < 120) {
	fail("frame count must be an integer of at least 120");
}
if (!Number.isInteger(trials) || trials < 1) {
	fail("trial count must be a positive integer");
}

function run(binary) {
	const result = spawnSync(
		path.join(root, "bin", binary),
		[
			"run",
			project,
			"--backend",
			"null",
			"--headless",
			"--no-hot-reload",
			"--frames",
			String(frames),
			"--runtime-stats",
			"--json",
		],
		{ cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
	);
	if (result.error) {
		fail(result.error.message);
	}
	if (result.status !== 0) {
		fail(result.stderr.trim() || result.stdout.trim() || `${binary} exited with ${result.status}`);
	}
	let document;
	try {
		document = JSON.parse(result.stdout);
	} catch (error) {
		fail(`${binary} did not emit one JSON document: ${error.message}`);
	}
	const stats = document.result?.runtime_stats;
	if (document.schema_version !== 1 || document.command !== "run" || document.ok !== true ||
		!stats?.enabled || stats.frames !== frames) {
		fail(`${binary} returned incomplete runtime statistics`);
	}
	return stats.late_update_ns_per_frame;
}

function median(values) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.floor(sorted.length / 2)];
}

const profiles = [
	{ name: "development (-o:minimal)", binary: "scrapbot-dev" },
	{ name: "performance (-o:speed)", binary: "scrapbot" },
];
const measurements = profiles.map((profile) => {
	const samples = [];
	for (let trial = 0; trial < trials; trial += 1) {
		samples.push(run(profile.binary));
	}
	return { ...profile, samples, median: median(samples) };
});

const baseline = measurements[0].median;
for (const measurement of measurements) {
	const milliseconds = measurement.median / 1_000_000;
	const relative = baseline / measurement.median;
	console.log(`${measurement.name.padEnd(27)} ${milliseconds.toFixed(3)} ms/frame  ${relative.toFixed(2)}x`);
}

