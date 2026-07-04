// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'Machina Engine',
			sidebar: [
				{
					label: 'Getting Started',
					items: [
						{ label: 'Overview', slug: 'getting-started/overview' },
						{ label: 'Quickstart', slug: 'getting-started/quickstart' },
					],
				},
				{
					label: 'Core Concepts',
					items: [
						{ label: 'Project Model', slug: 'concepts/project-model' },
						{ label: 'Scene Authoring', slug: 'concepts/scenes' },
						{ label: 'ECS Runtime', slug: 'concepts/ecs' },
					],
				},
				{
					label: 'Scripting & Native Code',
					items: [
						{ label: 'Luau Systems', slug: 'scripting/luau' },
						{ label: 'Queries and Views', slug: 'scripting/queries-and-views' },
						{ label: 'Project-Local Zig', slug: 'scripting/native-zig' },
					],
				},
				{
					label: 'Rendering & UI',
					items: [
						{ label: 'Rendering Overview', slug: 'rendering/overview' },
						{ label: 'Geometry and Materials', slug: 'rendering/geometry-materials' },
						{ label: 'Batching and Shadows', slug: 'rendering/batching-and-shadows' },
						{ label: 'Editor UI Overlay', slug: 'editor-ui/debug-overlay' },
					],
				},
				{
					label: 'Workflow',
					items: [
						{ label: 'Live Reload', slug: 'workflow/live-reload' },
						{ label: 'Building Games', slug: 'workflow/building-games' },
						{ label: 'Testing and Verification', slug: 'workflow/testing' },
						{ label: 'Diagnostics', slug: 'workflow/diagnostics' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'CLI', slug: 'reference/cli' },
						{ label: 'Project Files', slug: 'reference/project-files' },
						{ label: 'Engine Components', slug: 'reference/components' },
						{ label: 'Example Projects', slug: 'reference/examples' },
					],
				},
			],
		}),
	],
});
