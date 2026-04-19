import { visit } from 'unist-util-visit';

export default function remarkMermaid() {
	return (tree) => {
		visit(tree, 'code', (node, index, parent) => {
			if (node.lang !== 'mermaid') return;
			const html = `<pre class="mermaid">${escapeHtml(node.value)}</pre>`;
			parent.children[index] = { type: 'html', value: html };
		});
	};
}

function escapeHtml(s) {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;');
}
