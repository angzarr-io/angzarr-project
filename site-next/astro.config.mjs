// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightBlog from 'starlight-blog';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import remarkCodeRegion from './src/plugins/remark-code-region.mjs';
import remarkMermaid from './src/plugins/remark-mermaid.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export default defineConfig({
	site: 'https://angzarr.io',
	trailingSlash: 'ignore',
	redirects: {
		// Docusaurus blog pagination → Starlight pagination
		'/blog/page/2': '/blog/2',
		'/blog/page/3': '/blog/3',
		'/blog/page/4': '/blog/4',
		// Docusaurus archive → blog index
		'/blog/archive': '/blog',
	},
	markdown: {
		remarkPlugins: [
			[remarkCodeRegion, { rootDir: repoRoot, lenient: process.env.DOCS_LENIENT === '1' }],
			remarkMermaid,
		],
	},
	integrations: [
		starlight({
			title: '⍼ Angzarr',
			description: 'Polyglot Event Sourcing & CQRS Framework',
			head: [
				{
					tag: 'script',
					attrs: { type: 'module' },
					content: `
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
function run() {
	const dark = document.documentElement.dataset.theme === 'dark';
	mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'loose' });
	mermaid.run({ querySelector: 'pre.mermaid' });
}
if (document.readyState !== 'loading') run(); else document.addEventListener('DOMContentLoaded', run);
document.addEventListener('astro:after-swap', run);
					`.trim(),
				},
			],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/angzarr-io/angzarr' }],
			editLink: {
				baseUrl: 'https://github.com/angzarr-io/angzarr-project/edit/main/',
			},
			plugins: [
				starlightBlog({
					title: 'Angzarr Blog',
					postCount: 10,
					recentPostCount: 5,
					authors: {
						angzarr: {
							name: 'Ben Abbitt',
							title: 'Consultant, Software Architect, AI Wrangler',
							url: 'https://github.com/benjaminabbitt',
							picture: 'https://github.com/benjaminabbitt.png',
						},
					},
				}),
			],
			sidebar: [
				{ label: 'Why Event Sourcing', slug: '' },
				{
					label: 'Features',
					items: [
						{ label: 'Overview', slug: 'features' },
						{ label: 'Small Footprint', slug: 'features/small-footprint' },
						{ label: 'Facts', slug: 'features/facts' },
						{ label: 'Compensation', slug: 'features/compensation' },
						{ label: 'Cascade', slug: 'features/cascade' },
						{ label: 'Editions', slug: 'features/editions' },
						{ label: 'ML Training', slug: 'features/ml-training' },
						{ label: 'Upcasting', slug: 'features/upcasting' },
						{ label: 'Projections', slug: 'features/projections' },
						{ label: 'Polyglot', slug: 'features/polyglot' },
						{ label: 'Performance', slug: 'features/performance' },
						{ label: 'Observability', slug: 'features/observability' },
					],
				},
				{ label: 'Patterns Explained', slug: 'patterns-explained' },
				{ label: 'Intro', slug: 'intro' },
				{ label: 'Getting Started', slug: 'getting-started' },
				{ label: 'Architecture', slug: 'architecture' },
				{
					label: 'Components',
					autogenerate: { directory: 'components' },
				},
				{
					label: 'SDKs',
					items: [
						{ label: 'Overview', slug: 'sdks' },
						{ label: 'Clients', slug: 'sdks/clients' },
						{ label: 'Builders', slug: 'sdks/builders' },
						{ label: 'Error Handling', slug: 'sdks/error-handling' },
						{ label: 'Speculative', slug: 'sdks/speculative' },
						{
							label: 'By Language',
							items: [
								{ label: 'Rust', link: 'https://github.com/angzarr-io/angzarr-client-rust', attrs: { target: '_blank' } },
								{ label: 'Go', link: 'https://github.com/angzarr-io/angzarr-client-go', attrs: { target: '_blank' } },
								{ label: 'Python', link: 'https://github.com/angzarr-io/angzarr-client-python', attrs: { target: '_blank' } },
								{ label: 'Java', link: 'https://github.com/angzarr-io/angzarr-client-java', attrs: { target: '_blank' } },
								{ label: 'C#', link: 'https://github.com/angzarr-io/angzarr-client-csharp', attrs: { target: '_blank' } },
								{ label: 'C++', link: 'https://github.com/angzarr-io/angzarr-client-cpp', attrs: { target: '_blank' } },
							],
						},
					],
				},
				{
					label: 'Tooling',
					items: [
						{ label: 'Just', slug: 'tooling/just' },
						{ label: 'Cucumber', slug: 'tooling/cucumber' },
						{ label: 'Testcontainers', slug: 'tooling/testcontainers' },
						{ label: 'Just Overlays', slug: 'tooling/just-overlays' },
						{ label: 'SCM', slug: 'tooling/scm' },
						{ label: 'Claude', slug: 'tooling/claude' },
						{
							label: 'Databases',
							autogenerate: { directory: 'tooling/databases' },
						},
						{
							label: 'Message Buses',
							autogenerate: { directory: 'tooling/buses' },
						},
					],
				},
				{
					label: 'Operations',
					autogenerate: { directory: 'operations' },
				},
				{
					label: 'Reference',
					autogenerate: { directory: 'reference' },
				},
				{
					label: 'Examples',
					items: [
						{ label: 'Why Poker', slug: 'examples/why-poker' },
						{ label: 'Aggregates', slug: 'examples/aggregates' },
						{ label: 'Sagas', slug: 'examples/sagas' },
						{ label: 'Language Notes', slug: 'examples/language-notes' },
					],
				},
			],
		}),
	],
});
