import React from 'react';
import Admonition from '@theme/Admonition';
import Link from '@docusaurus/Link';

export default function BlogHeader(): React.JSX.Element {
  return (
    <Admonition type="info" title="About This Blog">
      <p>
        This blog documents learnings from building <Link to="/">Angzarr</Link>—a
        polyglot event sourcing framework. The framework core is written in Rust,
        so examples here are primarily Rust.
      </p>
      <p>
        <strong>Angzarr doesn't require Rust.</strong> Client <Link to="/sdks">SDKs</Link> exist for
        Go, Python, Java, C#, and C++. The author—a polyglot developer—doesn't
        believe Rust is the best language for everything. It <em>is</em> the right
        choice for this framework's core, and building it has produced these learnings.
      </p>
      <p>
        The Rust should be readable by most programmers. If you have questions:
        consult <a href="https://doc.rust-lang.org/book/">The Rust Book</a>, ask
        an LLM, or <a href="mailto:ben+angzarrblog@abbitt.me">email the author</a>.
      </p>
    </Admonition>
  );
}
