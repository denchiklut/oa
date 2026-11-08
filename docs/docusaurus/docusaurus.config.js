// @ts-check
const { themes: prismThemes } = require("prism-react-renderer");

const repoUrl = "https://github.com/denchiklut/oa";

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: "Oa",
  tagline: "Architecture of a native macOS browser over Chromium",
  url: "https://denchiklut.github.io",
  baseUrl: "/oa/",
  organizationName: "denchiklut",
  projectName: "oa",
  trailingSlash: true,

  onBrokenLinks: "throw",
  markdown: {
    // Plain .md files are parsed as CommonMark, not MDX, so they stay GitHub-compatible.
    format: "detect",
    hooks: { onBrokenMarkdownLinks: "throw" },
  },

  i18n: { defaultLocale: "en", locales: ["en"] },

  presets: [
    [
      "classic",
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          // Docs are read in place, so they still render on GitHub as before.
          path: "..",
          include: ["architecture/**/README.md", "features/**/README.md"],
          exclude: ["**/.local/**"],
          routeBasePath: "/",
          sidebarPath: require.resolve("./sidebars.js"),
          editUrl: ({ docPath }) => `${repoUrl}/edit/main/docs/${docPath}`,
          showLastUpdateTime: true,
        },
        blog: false,
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: { respectPrefersColorScheme: true },
      navbar: {
        title: "Oa",
        items: [
          { to: "/architecture/", label: "Architecture", position: "left" },
          { to: "/features/", label: "Features", position: "left" },
          { href: repoUrl, label: "GitHub", position: "right" },
        ],
      },
      footer: {
        style: "dark",
        copyright: `Oa architecture documentation`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

module.exports = config;
