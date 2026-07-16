import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const registryPath = path.join(root, 'src/scrapbot/component/registry.odin');
const docsPath = path.join(
	root,
	'docs-website/src/content/docs/reference/components.md',
);

for (const required of [registryPath, docsPath]) {
	if (!fs.existsSync(required)) {
		console.error(`missing required file: ${path.relative(root, required)}`);
		process.exit(2);
	}
}

const registry = fs.readFileSync(registryPath, 'utf8');
const docs = fs.readFileSync(docsPath, 'utf8');
const names = [
	...registry.matchAll(
		/register_engine_component\(\s*registry,\s*"([a-z0-9_.]+)"/g,
	),
].map((match) => match[1]);
const uniqueNames = [...new Set(names)].sort();
const fields = [
	...registry.matchAll(/Field_Definition\{name = "([a-z0-9_]+)"/g),
].map((match) => match[1]);
const uniqueFields = [...new Set(fields)].sort();
const missingNames = uniqueNames.filter((name) => !docs.includes(`\`${name}\``));
const missingFields = uniqueFields.filter((field) => !docs.includes(field));

if (missingNames.length > 0) {
	console.error('engine components missing from the canonical component reference:');
	for (const name of missingNames) {
		console.error(`- ${name}`);
	}
	process.exit(1);
}

if (missingFields.length > 0) {
	console.error('registered fields missing from the canonical component reference:');
	for (const field of missingFields) {
		console.error(`- ${field}`);
	}
	process.exit(1);
}

const internalCount = uniqueNames.filter((name) =>
	name.startsWith('scrapbot.internal.'),
).length;
console.log(
	`component documentation inventory is complete: ${uniqueNames.length - internalCount} public, ${internalCount} internal, ${uniqueFields.length} reflected fields`,
);
