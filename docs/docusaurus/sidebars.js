// @ts-check

// Public navigation follows the four-layer overview and its README pages.

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    { type: "doc", id: "README", label: "System architecture" },
    { type: "doc", id: "app/README", label: "App/UI" },
    { type: "doc", id: "adk/README", label: "ADK" },
    { type: "doc", id: "core/README", label: "Core" },
    { type: "doc", id: "chromium/README", label: "Chromium" },
  ],
};

module.exports = sidebars;
