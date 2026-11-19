# Command bar and history

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

One bar types every address and search, as in Arc. ⌘T, ⌘L, a click on the
toolbar's URL, the sidebar's New Tab row and a new window all open the same
card. It is drawn in the browser window, 766 pt wide and centred on the whole
window, with five 50 pt rows showing before the list scrolls. Esc or a click
outside closes it and leaves nothing behind.

- **⌘T** opens it empty and makes no tab: Return makes one, at the top of the
  Space's unpinned tabs, and selects it. The sidebar's New Tab row is
  highlighted while the bar is up.
- **⌘L** and the toolbar's URL open it with the front page's full URL selected,
  a Peek's included, and Return loads the current tab. Over a JavaScript dialog
  ⌘L does nothing. With no tab selected it acts as ⌘T.

A JavaScript dialog that arrives while the bar is open is drawn over it and
takes the keys, as Arc's bar opens behind a dialog; the bar has them back when
the dialog is answered. ⌘T itself waits while a dialog is up, as the window's
other commands do in Oa. Oa's own: the bar closes when the window's selected
tab or Space changes under it, as with ⌘W or ⌘Y, so it never acts on a tab it
wasn't opened for.

## Rows

Chromium's omnibox answers what is typed. Core runs upstream's
`AutocompleteController` with the default omnibox providers for the window's
profile, as ArcCore's browser does, and each start gets its own result
callback, so a quick Return never acts on an earlier input's results. A start
made before the profile has loaded waits for it.

Chromium's combined result holds at most 8 matches, 10 when they are all
searches. As ArcCore's result does, Core's also carries every provider's own
matches, and DevKit passes them on as additional matches, as ADK does, without
the ones Chromium only kept from its previous answer. As in ArcCore's Chromium,
the history quick provider offers 10 matches where upstream offers 3; Core sets
that with a Chromium feature parameter rather than a patch. So a query lists up
to ten history rows and 13 rows were reached, as measured in Arc.

DevKit keeps the kinds ADK keeps: typed URL and search, history, past searches,
search and navigation suggestions and other engines. Chromium's open-tab,
bookmark and calculator matches are dropped; Arc never shows them.

Open tabs come from Oa's sidebar instead, as Arc's sidebar gives them, only
when the bar makes a new tab, and never the selected tab. A tab needs an
address, its live page's or else its saved one; its title doesn't matter.

- **With text typed**, as Arc's sidebar provider: the Space's tabs and the
  profile's Favorites whose title or whole URL holds the text. A tab and the
  history entry of its page are one row, the tab, at the better of their two
  places. A tab of another Space isn't offered, so its page shows as history.
- **With nothing typed**, as Arc's null state: the profile's Favorites and the
  tabs of all its Spaces, at most four rows and one for an address. They are
  the only rows; Arc fills up to five with most visited sites and its
  onboarding links, which Oa doesn't have.

Each row is one line: the icon, the title, then "— host/path" for a page or
"Switch to Tab ➜" for a tab. A tab of another Space names its Space there
instead, and Return switches to it in its Space.

## Ranking

With nothing typed nothing is scored, as in Arc. Each window keeps when it
last showed a tab and when a tab was made through it, as Arc's windows do. The
tabs with such a date come first, latest first, by the last showing or else
the making; then the rest, by when they were last selected in any window. A
window stamps a tab it shows by a selection, a Space switch included, and each
minute the one it is showing unless the window is fully hidden; the tab itself
is stamped with it. A pinned tab that is closed loses when it was made.

Oa's own here, because Arc's isn't known or its sources are missing:

- the tab that takes a closed tab's place isn't stamped until the minute
  passes: Arc's code reads as if it were, and Arc's bar showed it wasn't;
- a tab moved or dropped into a window isn't dated as made there, and a tab
  never selected comes last: Oa's tabs have no creation date;
- the dates are restored with the window and dropped when their tab is gone;
- the arrow beside a Space's name.

With text, the rows are ranked with Arc's own scorer, ASE2, and its
compiled-in weights. Every row gets all of ASE2's features, each is normalised
over the query's rows, and the categories are weighted: kind 35, Chromium's
rank and relevance 25, recency 15, saved-ness 15, visit and typed counts 10,
text match 2. An additional match has no Chromium rank and takes ASE2's
default, 11. Boosts join the weighted mean:

- a tab shown in the last hour;
- a tab or page whose URL starts with what was typed, and a search suggestion
  or past search that does;
- a tab or page whose URL is what was typed;
- a tab or page on a bare host that starts with it, more when it is exactly
  it;
- Chromium's first search row for a search operator such as `site:example`.

After the sort, as Arc does:

- a stale tab at the top yields to the Chromium row below it,
- a history row gives its place to the open tab of its page,
- the row picked for the same query in the last 24 hours goes first,
- the typed search is no lower than second, and first for a search operator;
  a typed URL of four characters or more is first,
- a query with a space and no URL puts the typed search first.

The list ends at 15 rows, the limit Arc's bar gives ASE2.

Oa's own, because Arc's isn't known:

- the text matcher (prefix, word start, inside a word);
- two boosts are narrower than ASE2's code reads, to match the orders Arc
  showed: the typed search gets no search boost, and a navigation suggestion
  none for its bare host;
- the place a picked row is promoted to, the top;
- the features Oa has no source for, such as Type Travel, most-visited rank
  and site engagement, keep ASE2's defaults, which is how Arc ranks a query
  without them. A tab's custom title has no boost, as Oa's tabs have none.

ASE2 can also keep the current page off the top; in Arc it stayed first, so Oa
leaves that out. A tab's recency is when it was last selected, as Arc's.
Chromium records a page's last visit only to the hour.

The picks are kept per profile in `command-bar.json` in the data directory, as
Arc keeps them. Oa's own: picks older than 24 hours no longer count and are
dropped, and so are the picks of a profile that is gone.

## Typing and Return

- **Inline completion** selects the top row's untyped rest. There is none
  after a deletion, with the caret before the end, or while an input method
  composes. Moving the caret or selecting text keeps the query; the next edit
  uses the visible text. A later completion can refresh the field only if the
  selection reaches its end.
- **Arrows** move the selection and fill the field: a search with its untyped
  rest selected, a page with its URL, a tab with what was typed. Oa's own: the
  highlight stays on its row when a later answer re-ranks the list.
- **Return** opens the selected row once Chromium has answered what is typed.
  A tab is switched to, with no new tab and no reload. ⌘Return opens a new tab
  in the background, ⇧Return is plain Return. From ⌘L, ⌘Return doing the same
  is Oa's own; Arc's wasn't tested. ⌥Return is Arc's Split View, so it is plain
  Return until Oa has splits.
- **⇧⌦** deletes a past search; a page from history stays, as in Arc.

## Search and history

Each profile has its search engine, Chromium's list for the region, and
whether the engine suggests as you type, in Settings ▸ Profiles. Search
Settings… closes Settings and opens Chromium's search engines page as Arc does:
a new tab at the top of a Space of that profile, in a window showing one, else
in the frontmost window, which moves to one. A profile with no Space gets no
page.

**View History ⌘Y** in the Archive menu opens Chromium's History page in a new
tab at the top of the Space, for the Space's profile. Deleting a page there
removes it from the bar too.

## Site Search

As Arc, Oa adds Arc's 19 popular site searches (YouTube, Wikipedia, GitHub,
Google Drive and the rest) to Chromium's search engines with their colours:
once for every profile the first time Oa runs, and to each profile made after.
A removed one stays gone. They are edited on Chromium's search engines page.

When what is typed starts an engine's keyword ("you", "YouTube",
"youtube.com"), the field offers "Search YouTube" with a Tab key cap; the
shortest keyword wins, and the highlighted row doesn't change it. Tab or a
click on it enters Site Search: the engine's name in a pill of its colour, an
empty field, and Chromium in keyword mode for that engine, so the rows are the
search for the text and past searches on that engine. Return, ⌘Return and ⌘L
open the engine's results as any row does.

- **Backspace** at the field's start leaves, putting back what was typed before
  Tab, with the caret after it.
- **Esc** leaves and clears the field; a second Esc closes the bar.
- **Tab** with an empty query leaves; with a query it does nothing.

The pill and the highlighted row take the engine's colour by Arc's rule, looked
up each time a Site Search is entered and never cached:

1. **Arc's table.** An engine Chromium didn't ship gets the colour of the
   popular site search with the same URL, else of the first one whose host its
   own host is or is under. So a YouTube engine on `www.youtube.com` is red
   whatever its template, and one on `youtube.com` isn't. The colour is drawn
   as it is, read as Display P3 as Arc reads it.
2. **The site's favicon.** Otherwise the profile's history is searched for the
   engine's host, and the newest page's stored favicon gives its dominant
   colour: ColorThief's quantizer over every tenth pixel, the first of five
   colours that isn't nearly black, darkened by 0.15 of HSL lightness. It
   arrives a frame after the pill. The pill is drawn in the `focus` colour of
   the theme that colour generates, light or dark by the app's appearance. The
   history search matches words, so a host can find another site's page, as in
   Arc.
3. **Neither.** The window theme's `focus`.

The pill has continuous 12 pt corners and a shadow in its colour. The pill,
text and icon change in one frame; the bar bounces whenever a Site Search is
entered or left, a dip to about 0.988 of its size and back in 0.2 s. On entry
a block of the colour behind the card blurs out over 1.2 s, starting when the
colour is known. Oa's card lets more of it through than Arc's, so the card
tints more strongly in the first frames.

| Layer | What it holds |
| --- | --- |
| UI | The pill, the scoped row, the bounce and the glow, with the theme generator that window themes use |
| DevKit | The table lookup on `SearchEngine`, the quantizer (`DominantColor`), and a profile's history search and stored favicon on `BrowserContext` |
| Core | Chromium's history text search and favicon service for a profile |
| Chromium | Patch 0015, which lets `chrome://settings` activate an engine or make one the default without a `BrowserView` |

Not done yet, as later slices: the pill's menu (remove, change, manage),
Space as a trigger, and an empty scope's recent searches.

Not done yet, as later slices: Arc's commands in the bar, the sidebar's URL
pill, Little Arc's bar and the onboarding rows.

Related: [Sidebar state](../sidebar/README.md) · [Peek](../peek/README.md).

Return to the [feature inventory](../README.md).
