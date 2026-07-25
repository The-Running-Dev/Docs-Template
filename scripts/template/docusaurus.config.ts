import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

/**
 * Local Docusaurus config — overrides the base image's default when this
 * directory is copied over /template (see ./Dockerfile). Content lives in
 * ./docs (games/); the sidebar is ./sidebar.ts.
 *
 * Placeholder title/url/tagline — edit to taste. Broken-link checks are 'warn'
 * (not 'throw') to keep authoring frictionless; flip to 'throw' to gate builds.
 */
const config: Config = {
  title: '',
  tagline: '',
  url: 'https://example.com',
  baseUrl: '/',
  onBrokenLinks: 'warn',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn'
    }
  },
  i18n: { defaultLocale: 'en', locales: ['en'] },
  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebar.ts',
          routeBasePath: 'docs'
        },
        blog: false
      } satisfies Preset.Options
    ]
  ],

  themeConfig: {
    navbar: {
      title: '',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docs',
          position: 'left',
          label: 'Docs'
        }
      ]
    },
    footer: { style: 'dark', links: [] }
  } satisfies Preset.ThemeConfig
};

export default config;
