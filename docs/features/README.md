# Arc and Oa feature inventory

Arc feature snapshot: **November 7, 2026**. Oa checklist initialized:
**November 8, 2026**. This folder is the starting point for documenting Arc's
features and tracking Oa's equivalents. For now it contains only an inventory;
detailed behavior, acceptance criteria and prioritization come later.

## How to read this

- **Arc ✅**: a documented or UI-observed Arc **macOS desktop** capability, not a
  runtime or service-availability guarantee. Explicitly retired features are separated below.
- **Oa ✅**: implemented in Oa and verified on the live engine.
- **Oa ☐**: unchecked and not yet assessed. Every Oa entry intentionally starts
  unchecked, regardless of any existing implementation; this is not a claim that
  the feature is missing.
- **†**: known from dated release notes; continued availability has not been
  independently established. Explicit removals belong in the retired table.

This is a feature-and-settings checklist, not a specification. The baseline is
macOS, not a claim that Windows has the same features. Arc Search's mobile-only
features, such as Browse for Me and Call Arc, are outside this desktop comparison.
No Oa implementation audit or app test run is represented by these unchecked entries.

**Date caveat:** Arc's official [sunset timeline][arc-sunset] schedules desktop
Arc's shutdown for December 22, 2026. That is still in the future at this snapshot.
The table records its documented feature set, including older official release
notes where dedicated help pages are no longer available; it does not certify
that every online integration still works.

## Browse the checklist

- [Sidebar, tabs and folders](#sidebar-tabs-and-folders)
- [Spaces, profiles and windows](#spaces-profiles-and-windows)
- [Split View](#split-view)
- [Command bar, search and shortcuts](#command-bar-search-and-shortcuts)
- [Air Traffic Control](#air-traffic-control-link-routing)
- [Little Arc](#little-arc-quick-windows)
- [Peek](#peek-interactive-link-previews)
- [Page controls and developer tools](#page-controls-and-developer-tools)
- [Privacy, security and extensions](#privacy-security-extensions-and-browser-data)
- [Accounts, sync and migration](#accounts-sync-and-migration)
- [Downloads and Library](#downloads-and-library)
- [Captures, Easels, Boosts and sharing](#library-captures-customization-and-sharing)
- [Sidebar previews and integrations](#sidebar-previews-and-integrations)
- [Media](#media)
- [Arc Max and AI link previews](#arc-max-and-ai)
- [General and Advanced settings](#general-and-advanced-settings)
- [Retired features](#retired-arc-features--historical-inventory-only)
- [Coverage and remaining investigation](#coverage-and-remaining-investigation)

## Sidebar, tabs and folders

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Vertical sidebar | ✅ | ☐ |
| Hide/reveal and resize the sidebar | ✅ | ☐ |
| Optional top toolbar | ✅ | ☐ |
| Favorites | ✅ | ☐ |
| Pinned tabs | ✅ | ☐ |
| Ordinary / Today tabs | ✅ | ☐ |
| Rename and duplicate tabs | ✅ | ☐ |
| Move and reorder tabs with drag and drop | ✅ | ☐ |
| Custom tab icons | ✅ | ☐ |
| Reset a pinned tab to its pinned URL | ✅ | ☐ |
| Select and act on multiple tabs | ✅ | ☐ |
| Recent-tab switcher | ✅ | ☐ |
| Close tabs and reopen the last closed tab | ✅ | ☐ |
| Clear all ordinary tabs | ✅ | ☐ |
| Automatic tab archiving | ✅ | ☐ |
| Configure auto-archive interval per profile | ✅ | ☐ |
| Archive browser and archived-tab restoration | ✅ | ☐ |
| Search archived tabs † | ✅ | ☐ |
| Clear the entire Archive † | ✅ | ☐ |
| Folders and nested folders | ✅ | ☐ |
| Rename, duplicate and move folders | ✅ | ☐ |
| Convert a folder into a Space | ✅ | ☐ |
| Copy all links in a folder | ✅ | ☐ |
| Custom folder icons | ✅ | ☐ |
| Folder search | ✅ | ☐ |
| Collapse Pinned Tabs | ✅ | ☐ |
| Reveal the current tab in the sidebar | ✅ | ☐ |
| Reset all tabs in the current Space | ✅ | ☐ |
| Copy multiple selected tab URLs † | ✅ | ☐ |
| Copy folder links as Markdown | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23], [2024–2026][arc24].

## Spaces, profiles and windows

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Create, rename, reorder and delete Spaces | ✅ | ☐ |
| Space names and icons | ✅ | ☐ |
| Switch Spaces by gesture or keyboard | ✅ | ☐ |
| Spaces overview / management | ✅ | ☐ |
| Space colors, gradients, texture and appearance | ✅ | ☐ |
| Separate browsing profiles | ✅ | ☐ |
| Assign profiles to Spaces | ✅ | ☐ |
| Create, rename and delete profiles | ✅ | ☐ |
| Multiple browser windows | ✅ | ☐ |
| Separate blank-window command | ✅ | ☐ |
| Move an active page between windows | ✅ | ☐ |
| Restore the sidebar and window selections after relaunch | ✅ | ☐ |
| Full browser-session restoration | ✅ | ☐ |
| Incognito windows | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23], [profile migration guide][arc-migration].

## Split View

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Multiple pages in a Split View | ✅ | ☐ |
| Horizontal and vertical splits | ✅ | ☐ |
| Resize, reorder and focus split panes | ✅ | ☐ |
| Create splits by dragging tabs or links | ✅ | ☐ |
| Pin and save Split Views | ✅ | ☐ |
| Separate a page from a split | ✅ | ☐ |
| Custom Split View titles | ✅ | ☐ |
| Expand Current Split | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23].

## Command bar, search and shortcuts

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Command bar for addresses and web searches | ✅ | ☐ |
| Search and switch to open tabs | ✅ | ☐ |
| Run browser actions from the command bar | ✅ | ☐ |
| Search suggestions and history matches | ✅ | ☐ |
| Site Search shortcuts | ✅ | ☐ |
| Choose and manage search engines per profile | ✅ | ☐ |
| Enable/disable search suggestions per profile | ✅ | ☐ |
| Delete individual command-bar suggestions † | ✅ | ☐ |
| Keyboard shortcuts | ✅ | ☐ |
| Customize keyboard shortcuts | ✅ | ☐ |
| Search/filter shortcut settings | ✅ | ☐ |
| Reset individual/all keyboard shortcuts | ✅ | ☐ |
| Prefer Arc versus website keyboard shortcuts | ✅ | ☐ |
| Include/exclude Favorites in numbered navigation † | ✅ | ☐ |
| Choose ninth-item versus last-item shortcut behavior † | ✅ | ☐ |
| Copy the current URL with confirmation | ✅ | ☐ |
| Copy current URL as Markdown | ✅ | ☐ |
| Copy URL as Quote / share selected-text quote | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23].

## Air Traffic Control: link routing

Air Traffic Control decides **where a link opens**. It is not Peek or an AI
preview. These rows describe the observed routing controls, not unverified
matching edge cases or rule-priority semantics.

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Open links from other apps as the default browser | ✅ | ☐ |
| Air Traffic Control / URL-routing rules | ✅ | ☐ |
| Create, edit and remove routes | ✅ | ☐ |
| URL matching: Is equal to / Contains | ✅ | ☐ |
| Route matching links to a chosen Space | ✅ | ☐ |
| Route matching links to Little Arc | ✅ | ☐ |
| Most Recent Space as an individual rule destination | ✅ | ☐ |
| Default destination: chosen Space / Most Recent Space | ✅ | ☐ |
| Default destination: Little Arc | ✅ | ☐ |
| Apply routing when restoring archived tabs † | ✅ | ☐ |
| Apply routing when opening Peek destinations † | ✅ | ☐ |
| Reuse an already-open destination tab | ✅ | ☐ |

Sources: Arc [2023][arc23], [2024–2026][arc24], [feature FAQ][arc-faq], and native
Settings → Links → Air Traffic Control (including operator/destination menus).

## Little Arc: quick windows

Little Arc is a separate small browser window, not an overlay or summary card.

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Little Arc / quick browsing window | ✅ | ☐ |
| Enable/disable opening external links in Little Arc | ✅ | ☐ |
| Open the quick-window page in a Space | ✅ | ☐ |
| Launch Little Arc globally from another app | ✅ | ☐ |
| Option-Command-click a link to open Little Arc | ✅ | ☐ |
| Configure Little Arc auto-archive interval | ✅ | ☐ |
| Multiple simultaneous Little Arc windows † | ✅ | ☐ |
| Reuse an identical external-link Little Arc window † | ✅ | ☐ |
| Remember domain-specific profile selection † | ✅ | ☐ |
| Filter Archive to Little Arc † | ✅ | ☐ |
| Show/hide all Little Arc windows from the Dock † | ✅ | ☐ |
| Use extensions in Little Arc † | ✅ | ☐ |
| Optional menu-bar launcher † | ✅ | ☐ |

Sources: Arc native Settings → Links; [2021][arc21], [2022][arc22],
[2023][arc23].

## Peek: interactive link previews

Peek loads an **interactive webpage over the source tab**. For AI hover-link
summaries, see [5-Second Previews](#arc-max-and-ai); for sidebar hover cards,
see [sidebar previews](#sidebar-previews-and-integrations).

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Peek interactive webpage overlay | ✅ | ✅ |
| Cross-site links from Favorites/Pinned tabs open Peek | ✅ | ✅ |
| Shift-click links to open Peek | ✅ | ✅ |
| Expand a Peek into a tab | ✅ | ✅ |
| Add a Peek to Split View | ✅ | ☐ |
| Reopen a closed Peek † | ✅ | ☐ |
| Open Easels in Peek † | ✅ | ☐ |
| Copy Peek URL as Markdown † | ✅ | ☐ |

Sources: Arc native Settings → Links and [2023 release notes][arc23].

## Page controls and developer tools

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Webpage loading, back/forward, reload and stop | ✅ | ☐ |
| Force Refresh | ✅ | ☐ |
| Clear Cookies and Refresh | ✅ | ☐ |
| Clear Cache and Refresh | ✅ | ☐ |
| Live page titles, URLs, favicons and loading indicators | ✅ | ✅ |
| Find in page | ✅ | ☐ |
| Page zoom | ✅ | ☐ |
| Print and Save as PDF | ✅ | ☐ |
| Save Page As | ✅ | ☐ |
| Open local files and PDFs | ✅ | ☐ |
| Native page/link/image/text context menus | ✅ | ☐ |
| Full-screen browser window | ✅ | ☐ |
| Page translation | ✅ | ☐ |
| Browsing-history viewer | ✅ | ☐ |
| Chromium DevTools, inspector and console | ✅ | ☐ |
| View page source | ✅ | ☐ |
| Arc Developer Mode tabs | ✅ | ☐ |
| Developer Mode for localhost and its subdomains † | ✅ | ☐ |
| Toggle Developer Mode by shortcut † | ✅ | ☐ |
| Developer Mode JSON formatter installation † | ✅ | ☐ |
| Browser task manager | ✅ | ☐ |
| End a tab process from Task Manager | ✅ | ☐ |
| Record diagnostic performance traces | ✅ | ☐ |
| AppleScript browser automation | ✅ | ☐ |

Sources: Arc [2021][arc21], [2022][arc22], [2023][arc23],
[troubleshooting][arc-troubleshoot].

## Privacy, security, extensions and browser data

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Ad blocker | ✅ | ☐ |
| Install and manage Chrome extensions | ✅ | ☐ |
| Site Controls and per-site permission settings | ✅ | ☐ |
| Permission prompts for camera, microphone, location, etc. | ✅ | ☐ |
| Connection-security indicator | ✅ | ☐ |
| JavaScript alert, confirm and prompt dialogs | ✅ | ☐ |
| Clear browsing data / privacy settings UI | ✅ | ☐ |
| Password manager | ✅ | ☐ |
| Address and payment autofill UI | ✅ | ☐ |
| Per-profile notifications settings | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23], [2024–2026][arc24],
[ad-blocker troubleshooting][arc-troubleshoot], [data clearing][arc-clear],
[data export][arc-export], [updates][arc-updates].

## Accounts, sync and migration

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Sign in with an existing Arc account / sign out | ✅ | ☐ |
| Change account name or email | ✅ | ☐ |
| Reset account password | ✅ | ☐ |
| Delete account | ✅ | ☐ |
| Cross-device Arc Sync | ✅ | ☐ |
| Sync the sidebar between Mac and Windows † | ✅ | ☐ |
| Import from another browser | ✅ | ☐ |
| Import multiple browser profiles † | ✅ | ☐ |
| Export Spaces and tabs as a Markdown link list | ✅ | ☐ |

Sources: Arc [account management][arc-account], [account deletion][arc-delete],
[export][arc-export], [2023][arc23], [2024–2026][arc24].

## Downloads and Library

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Downloads manager | ✅ | ☐ |
| Configure download location per profile | ✅ | ☐ |
| Display download progress † | ✅ | ☐ |
| Cancel an active download † | ✅ | ☐ |
| Recent downloads on Library hover † | ✅ | ☐ |
| Library lists downloads outside the Downloads folder † | ✅ | ☐ |
| Include/exclude screenshots in Library † | ✅ | ☐ |
| Remember the selected Library section † | ✅ | ☐ |
| Move Library files to macOS Trash † | ✅ | ☐ |

Sources: Arc native Settings → Profiles; [2022][arc22], [2023][arc23],
[2024–2026][arc24].

## Library, captures, customization and sharing

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Library | ✅ | ☐ |
| Screenshot of the visible page | ✅ | ☐ |
| Region capture and capture editing | ✅ | ☐ |
| Capture Full Page | ✅ | ☐ |
| Capture in Portrait Mode | ✅ | ☐ |
| Copy a capture's source URL † | ✅ | ☐ |
| Easels | ✅ | ☐ |
| Compose Easels with text, images, drawings and links † | ✅ | ☐ |
| Zoom the Easel canvas † | ✅ | ☐ |
| Snap/align Easel objects † | ✅ | ☐ |
| Drag selected webpage text into an Easel † | ✅ | ☐ |
| Remember Easel font/color choices † | ✅ | ☐ |
| Choose an Easel link-preview thumbnail † | ✅ | ☐ |
| Embed playable video URLs in Easels † | ✅ | ☐ |
| Live webpage captures in Easels | ✅ | ☐ |
| Play/pause and refresh Easel Live Captures † | ✅ | ☐ |
| Boosts: website colors, fonts and element removal | ✅ | ☐ |
| Boosts: custom CSS and JavaScript | ✅ | ☐ |
| Enable/disable individual Boosts † | ✅ | ☐ |
| Shuffle Boost styling † | ✅ | ☐ |
| Use Space-theme colors in Boost CSS † | ✅ | ☐ |
| Enable JavaScript Boosts separately on each device † | ✅ | ☐ |
| Boost gallery and Boost sharing | ✅ | ☐ |
| Custom application icons | ✅ | ☐ |
| Share a page URL through the system share sheet | ✅ | ☐ |
| Hosted sharing of Spaces, folders and Split Views | ✅ | ☐ |
| Read-only Easel sharing / viewing in other browsers † | ✅ | ☐ |
| Export an Easel as PNG | ✅ | ☐ |
| Bulk-export owned Easels as HTML/ZIP | ✅ | ☐ |

Sources: Arc [2021][arc21], [2022][arc22], [2023][arc23], [2024–2026][arc24], [export][arc-export].

## Sidebar previews and integrations

These are **hover previews for sidebar items**, separate from Peek and Max.
The Settings → General → Previews switches below were observed individually.

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Folder hover previews (Arc Folders) | ✅ | ☐ |
| Google Calendar previews | ✅ | ☐ |
| Google Mail previews | ✅ | ☐ |
| Outlook Calendar previews | ✅ | ☐ |
| Outlook Mail previews | ✅ | ☐ |
| Recent-page previews for Linear, Notion and Figma | ✅ | ☐ |
| Notion Calendar previews | ✅ | ☐ |
| Enable/disable each supported preview integration | ✅ | ☐ |
| Toggle site previews from Site Controls † | ✅ | ☐ |
| Live Calendar: upcoming meeting and join action † | ✅ | ☐ |
| Configure Live Calendar updates † | ✅ | ☐ |
| Join an active meeting by shortcut † | ✅ | ☐ |
| Exclude declined Live Calendar events † | ✅ | ☐ |
| GitHub Live Folders | ✅ | ☐ |
| Create documents in external document apps | ✅ | ☐ |

Sources: Arc native General → Previews and Profiles settings;
[2023][arc23], [2024–2026][arc24].

## Media

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Picture-in-Picture / automatic video mini-player | ✅ | ☐ |
| Sidebar audio player and media controls | ✅ | ☐ |
| Mute a tab from the browser UI | ✅ | ☐ |
| Cast a browser tab | ✅ | ☐ |
| Automatically show Google Meet Picture-in-Picture † | ✅ | ☐ |
| Open a notification's existing sender tab † | ✅ | ☐ |

Sources: Arc [2022][arc22], [2023][arc23], [2024–2026][arc24],
and Arc's native View → Cast menu.

## Arc Max and AI

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Enable/turn off Max as a whole | ✅ | ☐ |
| Separate switches for the six Max features | ✅ | ☐ |
| Automatically enable future Max features | ✅ | ☐ |
| Tidy Tab Titles: AI-rename tabs when pinning | ✅ | ☐ |
| Tidy Downloads: AI-rename downloaded files | ✅ | ☐ |
| Tidy Tabs: AI-organize Today tabs with the broom action | ✅ | ☐ |
| 5-Second Previews: AI hover-link summaries | ✅ | ☐ |
| Hover summaries on supported sites / Shift-hover on any link | ✅ | ☐ |
| Copy an AI summary as text/link or image † | ✅ | ☐ |
| Instant Links: Shift-Enter opens top search results | ✅ | ☐ |
| Instant Links for multiple queries | ✅ | ☐ |
| ChatGPT command-bar suggestions / ChatGPT then Tab | ✅ | ☐ |
| Organization policy to disable Max † | ✅ | ☐ |

Sources: Arc [2023][arc23], [2024–2026][arc24], [feature FAQ][arc-faq].

## General and Advanced settings

| Feature | Arc | Oa |
| --- | :---: | :---: |
| Manually check for browser updates | ✅ | ☐ |
| Automatic browser updates | ✅ | ☐ |
| Update-available prompt and restart workflow | ✅ | ☐ |
| Warn before quitting | ✅ | ☐ |
| Browser sound-effects switch | ✅ | ☐ |
| Tab-reordering haptic-feedback switch | ✅ | ☐ |
| Configure whether previous windows reopen at startup | ✅ | ☐ |
| Allow/disallow dragging the window from webpage tops | ✅ | ☐ |
| Show full URL in the toolbar | ✅ | ☐ |
| Show/hide Shared Quotes on text selection | ✅ | ☐ |
| Enable/disable automatic Picture-in-Picture | ✅ | ☐ |
| Allow sites access to Space-theme data | ✅ | ☐ |
| Enable/disable Boosts globally | ✅ | ☐ |
| More Settings: open advanced Chromium settings | ✅ | ☐ |
| Reset translated-site prompts | ✅ | ☐ |
| Automatic low-battery saving behavior † | ✅ | ☐ |

Sources: native Arc General/Advanced settings, [updates][arc-updates],
[2022][arc22], [2023][arc23], [2024–2026][arc24].

## Retired Arc features — historical inventory only

These checkmarks mean **Arc had the feature**, not that it still offers it.
They are not automatically Oa requirements. Easels are not Arc Notes and
remain in the documented-feature inventory above.

| Historical feature | Arc | Oa | Arc status |
| --- | :---: | :---: | --- |
| Arc Notes | ✅ | ☐ | Deprecated April 18, 2024. |
| Beta Reader Mode | ✅ | ☐ | Removed June 6, 2024. |
| GitHub hover previews | ✅ | ☐ | Deprecated May 23, 2024; distinct from Live Folders. |
| Ask On Page on macOS | ✅ | ☐ | Removed August 28, 2025. |
| Recent Tab Indicator | ✅ | ☐ | Removed February 29, 2024. |
| Paste & Go command-bar suggestion | ✅ | ☐ | Unshipped March 28, 2024. |
| Legacy iCloud Sync | ✅ | ☐ | Superseded by Arc Sync. |
| Create a new Arc account | ✅ | ☐ | Ended October 22, 2026. |

Source: Arc's dated [2024–2026 release notes][arc24], which take precedence over
older feature pages and marketing, and [account management][arc-account].
The retired iOS Sidebar Sync companion is
outside the macOS comparison.

## Coverage and remaining investigation

The Arc reference audit observed **Arc 1.172.1 on macOS, November 7, 2026**,
and used public Help Center articles/release notes. The following native UI was
inspected without changing preferences or routes:

- General and its Previews sheet; Profiles; Max; Links and Air Traffic Control,
  including URL operators, destinations and the unmatched-link fallback.
- Shortcuts and Advanced settings; File, Edit, View and Tabs menu commands.
- Icon pane was opened, but its accessibility labels did not expose a useful
  choice inventory. Account-data pages and Chromium's More Settings were not audited.

Native observation proves a control/menu is present, not that its service works
or that an Oa counterpart has been assessed. Sources for historical-only additions
are marked **†**. Older broad feature-family rows remain documentation-based;
an unchecked removal search is not proof that they still run.

**The checklist is expanded, not proven exhaustive.** Keep these gaps visible
rather than inventing Arc checkmarks or treating uncertainty as Oa parity:

| Candidate / area | What remains to establish |
| --- | --- |
| TypeTravel | Named by the official [FAQ][arc-faq]; behavior and current availability not established. |
| More Settings / Chromium preferences | Complete settings inventory, including Memory Saver, Energy Saver and always-active-site controls. |
| Air Traffic Control edge cases | Rule priority/reordering, compound conditions, individual enable switches and routing-toast actions were not established. |
| Gesture and navigation preferences | Scope/direction controls beyond the observed Space switching and Peek entry points. |
| Downloads | Ask-for-location, pause/resume/retry and file-management operations beyond the documented rows. |
| Account and sync controls | Exact sync payload, exclusions, device management and error/status UI. |
| Easel collaboration / Boost management | Editing permissions, detailed tools and management operations beyond the documented rows. |
| Historical integrations | Continued availability of release-note-only capabilities and their external services. |

[arc21]: https://resources.arc.net/hc/en-us/articles/20498463803799-Arc-for-macOS-2021-Release-Notes
[arc22]: https://resources.arc.net/hc/en-us/articles/20498417809815-Arc-for-macOS-2022-Release-Notes
[arc23]: https://resources.arc.net/hc/en-us/articles/20498377604887-Arc-for-macOS-2023-Release-Notes
[arc24]: https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes
[arc-sunset]: https://resources.arc.net/hc/en-us/articles/44412972248471-Arc-Sunset-Key-Dates-and-What-to-Expect
[arc-faq]: https://resources.arc.net/hc/en-us/articles/44413577819159-Arc-Sunset-Frequently-Asked-Questions
[arc-migration]: https://resources.arc.net/hc/en-us/articles/44413129117591-Move-from-Arc-to-Dia
[arc-troubleshoot]: https://resources.arc.net/hc/en-us/articles/19335714372759-Troubleshoot-or-Report-a-Problem-in-Arc
[arc-clear]: https://resources.arc.net/hc/en-us/articles/25614376281751-How-Do-You-Clear-Your-Cache-Cookies-and-or-History-on-Arc-for-Desktop
[arc-export]: https://resources.arc.net/hc/en-us/articles/25583851606039-How-Do-I-Export-My-Data-from-Arc
[arc-updates]: https://resources.arc.net/hc/en-us/articles/21489650267031-Update-Arc-for-Desktop
[arc-account]: https://resources.arc.net/hc/en-us/articles/19401542261911-Manage-Your-Arc-Account
[arc-delete]: https://resources.arc.net/hc/en-us/articles/22351623346327-Delete-My-Arc-Account
