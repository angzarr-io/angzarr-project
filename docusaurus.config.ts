import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import codeSnippets from 'remark-code-snippets';

const config: Config = {
  title: '⍼ Angzarr',
  tagline: 'Polyglot Event Sourcing & CQRS Framework',
  favicon: 'img/favicon.ico',

  future: {
    v4: true,
  },

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  themes: [
    '@docusaurus/theme-mermaid',
    'docusaurus-theme-openapi-docs',
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        indexDocs: true,
        indexBlog: true,
        indexPages: false,
        docsRouteBasePath: '/',
        language: ['en'],
        highlightSearchTermsOnTargetPage: true,
      },
    ],
  ],

  // GitHub Pages deployment with custom domain
  url: 'https://angzarr.io',
  baseUrl: '/',
  organizationName: 'angzarr-io',
  projectName: 'angzarr-project',
  trailingSlash: false,

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/angzarr-io/angzarr-project/tree/main/',
          routeBasePath: '/', // Docs at root, no /docs prefix
          remarkPlugins: [
            [codeSnippets, {
              baseDir: './angzarr',  // Main repo checked out by CI for code snippets
            }],
          ],
        },
        blog: {
          showReadingTime: true,
          editUrl: 'https://github.com/angzarr-io/angzarr-project/tree/main/',
          blogTitle: 'Angzarr Blog',
          blogDescription: 'Release notes, design decisions, and architecture deep-dives',
          postsPerPage: 10,
          blogSidebarTitle: 'Recent posts',
          blogSidebarCount: 5,
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    // Terminology plugin for glossary with tooltips
    [
      '@lunaticmuch/docusaurus-terminology',
      {
        termsDir: 'docs/glossary',
        glossaryFilepath: 'docs/glossary.mdx',
      },
    ],
    // Client redirects for URL stability
    [
      '@docusaurus/plugin-client-redirects',
      {
        redirects: [
          // Add redirects here as docs evolve
          // { from: '/old-path', to: '/new-path' },
        ],
      },
    ],
    // OpenAPI documentation
    [
      'docusaurus-plugin-openapi-docs',
      {
        id: 'openapi',
        docsPluginId: 'classic',
        config: {
          restapi: {
            specPath: 'openapi/angzarr.swagger.json',
            outputDir: 'docs/api/rest',
            sidebarOptions: {
              groupPathsBy: 'tag',
            },
          },
        },
      },
    ],
  ],

  themeConfig: {
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: '⍼ Angzarr',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          to: '/blog',
          label: 'Blog',
          position: 'left',
        },
        {
          type: 'doc',
          docId: 'glossary',
          label: 'Glossary',
          position: 'left',
        },
        {
          href: 'https://github.com/angzarr-io/angzarr',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Documentation',
          items: [
            {
              label: 'Getting Started',
              to: '/getting-started',
            },
            {
              label: 'Architecture',
              to: '/architecture',
            },
            {
              label: 'Components',
              to: '/components/aggregate',
            },
          ],
        },
        {
          title: 'Examples',
          items: [
            {
              label: 'Why Poker',
              to: '/examples/why-poker',
            },
            {
              label: 'Aggregates',
              to: '/examples/aggregates',
            },
            {
              label: 'Sagas',
              to: '/examples/sagas',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/angzarr-io/angzarr',
            },
            {
              label: 'PITCH.md',
              href: 'https://github.com/angzarr-io/angzarr/blob/main/PITCH.md',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Angzarr. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: [
        'bash',
        'rust',
        'go',
        'java',
        'csharp',
        'cpp',
        'protobuf',
        'yaml',
        'toml',
        'gherkin',
      ],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
