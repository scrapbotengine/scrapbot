// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://scrapbot.dev',
	vite: {
		server: {
			allowedHosts: ['localhost', '127.0.0.1'],
		},
	},
	integrations: [
		starlight({
			title: 'Scrapbot',
			description: 'Documentation for the Scrapbot experimental game engine.',
			customCss: ['./src/styles/scrapbot.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/scrapbotengine/scrapbot' }],
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Overview', slug: '' },
						{ label: 'Quickstart', slug: 'guides/quickstart' },
						{ label: 'Project Layout', slug: 'guides/project-layout' },
					],
				},
				{
					label: 'Engine Guides',
					items: [
						{ label: 'ECS UI', slug: 'guides/ecs-ui' },
						{ label: 'Luau Scripting', slug: 'guides/luau-scripting' },
						{ label: 'Native Extensions', slug: 'guides/native-extensions' },
						{ label: 'Live Editor', slug: 'guides/live-editor' },
						{ label: 'Rendering And Testing', slug: 'guides/rendering-testing' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Source Layout', slug: 'reference/source-layout' },
						{ label: 'CLI', slug: 'reference/cli' },
						{ label: 'Project Files', slug: 'reference/project-files' },
						{ label: 'Engine Components', slug: 'reference/components' },
						{ label: 'Luau API', slug: 'reference/luau-api' },
						{ label: 'Native Extension ABI', slug: 'reference/native-extension-abi' },
						{ label: 'Architecture Records', slug: 'reference/architecture-records' },
						{ label: 'Glossary', slug: 'reference/glossary' },
					],
				},
			],
		}),
	],
});
