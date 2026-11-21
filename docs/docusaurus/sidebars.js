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
        { type: "doc", id: "architecture/ui/README", label: "UI" },
        { type: "doc", id: "architecture/devkit/README", label: "DevKit" },
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
        { type: "doc", id: "features/sidebar/README", label: "Sidebar state" },
        { type: "doc", id: "features/sidebar-motion/README", label: "Sidebar motion" },
        { type: "doc", id: "features/peek/README", label: "Peek" },
        { type: "doc", id: "features/favorites/README", label: "Favorites" },
        { type: "doc", id: "features/profiles/README", label: "Profiles" },
        { type: "doc", id: "features/saved-state/README", label: "Saved state and recovery" },
        { type: "doc", id: "features/downloads/README", label: "Downloads" },
        { type: "doc", id: "features/context-menu/README", label: "Page context menu" },
        { type: "doc", id: "features/command-bar/README", label: "Command bar and history" },
        { type: "doc", id: "features/key-bindings/README", label: "Shortcuts over a page" },
        { type: "doc", id: "features/undo/README", label: "Undo and redo" },
        { type: "doc", id: "features/copy-url/README", label: "Copy URL" },
        { type: "doc", id: "features/extensions/README", label: "Extensions" },
        { type: "doc", id: "features/picture-in-picture/README", label: "Picture-in-picture" },
        { type: "doc", id: "features/tab-switcher/README", label: "Recent-tab switcher" },
      ],
    },
  ],
};

module.exports = sidebars;
