import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const project = process.argv[2] ?? "examples/ecs-showcase";
const frames = Number.parseInt(process.argv[3] ?? process.env.SCRAPBOT_SOAK_FRAMES ?? "10000", 10);
const maxCpuGrowth = Number.parseFloat(process.env.SCRAPBOT_SOAK_MAX_CPU_GROWTH ?? "1.5");
const maxAllocatorGrowth = Number.parseInt(process.env.SCRAPBOT_SOAK_MAX_ALLOCATOR_GROWTH ?? "65536", 10);
const maxFinalAllocatorBytes = Number.parseInt(process.env.SCRAPBOT_SOAK_MAX_FINAL_ALLOCATOR_BYTES ?? "65536", 10);

function fail(message) {
	console.error(`runtime soak failed: ${message}`);
	process.exit(1);
}

if (!Number.isInteger(frames) || frames < 1000) {
	fail("frame count must be an integer of at least 1000");
}
if (!Number.isFinite(maxCpuGrowth) || maxCpuGrowth < 1) {
	fail("SCRAPBOT_SOAK_MAX_CPU_GROWTH must be at least 1");
}
if (!Number.isInteger(maxAllocatorGrowth) || maxAllocatorGrowth < 0) {
	fail("SCRAPBOT_SOAK_MAX_ALLOCATOR_GROWTH must be a non-negative integer");
}
if (!Number.isInteger(maxFinalAllocatorBytes) || maxFinalAllocatorBytes < 0) {
	fail("SCRAPBOT_SOAK_MAX_FINAL_ALLOCATOR_BYTES must be a non-negative integer");
}

const run = spawnSync(
	path.join(root, "bin", "scrapbot"),
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

if (run.error) {
	fail(run.error.message);
}
if (run.status !== 0) {
	fail(run.stderr.trim() || run.stdout.trim() || `scrapbot exited with ${run.status}`);
}

let document;
try {
	document = JSON.parse(run.stdout);
} catch (error) {
	fail(`Scrapbot did not emit one JSON document: ${error.message}`);
}

if (document.schema_version !== 1 || document.command !== "run" || document.ok !== true) {
	fail("unexpected structured run envelope");
}
const stats = document.result?.runtime_stats;
if (!stats?.enabled || stats.frames !== frames) {
	fail("runtime statistics are missing or incomplete");
}
if (stats.early_update_ns_per_frame <= 0 || stats.late_update_ns_per_frame <= 0) {
	fail("update timing windows did not collect samples");
}
if (project.includes("ecs-showcase")) {
	const query = stats.native_queries;
	if (!query || query.plan_builds < 1 || query.plan_hits <= query.plan_builds ||
		query.chunks < 1 || query.entities < query.chunks) {
		fail("native query plans did not retain and pack chunk work");
	}
}

const storageGrowth = [];
const earlyStorage = stats.early_storage ?? {};
const lateStorage = stats.late_storage ?? {};
const finalStorage = stats.final_storage ?? {};
for (const [name, early] of Object.entries(earlyStorage)) {
	if (name === "live_entities") {
		continue;
	}
	const late = lateStorage[name];
	const final = finalStorage[name];
	if (late !== early || final !== late) {
		storageGrowth.push(`${name}: ${early} -> ${late} -> ${final}`);
	}
}
if (storageGrowth.length > 0) {
	fail(`ECS storage grew after warm-up (${storageGrowth.join(", ")})`);
}

const allocatorGrowth = stats.allocator_late_bytes - stats.allocator_early_bytes;
if (allocatorGrowth > maxAllocatorGrowth) {
	fail(
		`engine allocator grew by ${allocatorGrowth} bytes; allowed ${maxAllocatorGrowth}`,
	);
}
if (stats.allocator_final_bytes > maxFinalAllocatorBytes) {
	fail(
		`engine allocator retained ${stats.allocator_final_bytes} bytes after teardown; allowed ${maxFinalAllocatorBytes}`,
	);
}
if (stats.cpu_growth_ratio > maxCpuGrowth) {
	fail(
		`late update cost is ${stats.cpu_growth_ratio.toFixed(2)}x early cost; allowed ${maxCpuGrowth.toFixed(2)}x`,
	);
}

console.log(
	`runtime soak passed: ${frames} frames, ${stats.cpu_growth_ratio.toFixed(2)}x CPU trend, ` +
		`${allocatorGrowth} allocator bytes grown, ${stats.allocator_final_bytes} bytes after teardown, ` +
		`${stats.late_storage.entity_slots} entity slots`,
);
