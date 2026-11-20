import mermaid from 'mermaid';

function initMermaid() {
	const isDark = document.documentElement.dataset.theme === 'dark';
	mermaid.initialize({
		startOnLoad: false,
		theme: isDark ? 'dark' : 'default',
		securityLevel: 'loose',
	});
	mermaid.run({ querySelector: 'pre.mermaid' });
}

if (document.readyState !== 'loading') {
	initMermaid();
} else {
	document.addEventListener('DOMContentLoaded', initMermaid);
}

document.addEventListener('astro:after-swap', initMermaid);
