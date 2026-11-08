// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    {
      type: "category",
      label: "Architecture",
      collapsed: false,
      link: { type: "doc", id: "architecture/README" },
      items: [
        { type: "doc", id: "architecture/app/README", label: "App/UI" },
        { type: "doc", id: "architecture/adk/README", label: "ADK" },
        { type: "doc", id: "architecture/core/README", label: "Core" },
        { type: "doc", id: "architecture/chromium/README", label: "Chromium" },
      ],
    },
    {
      type: "category",
      label: "Features",
      collapsed: false,
      items: [
        { type: "doc", id: "features/README", label: "Arc and Oa feature inventory" },
      ],
    },
  ],
};

module.exports = sidebars;
