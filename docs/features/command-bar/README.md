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

Open tabs come from Oa's sidebar instead, as Arc's sidebar provider gives
them: the Space's tabs other than the selected one, with "Switch to Tab", only
when the bar makes a new tab. With nothing typed, they are the only rows. A
tab and the history entry of its page are one row, the tab, at the better of
their two places. Pinned tabs are offered and Favorites aren't, as Oa's own:
neither was tested in Arc.

Each row is one line: the icon, the title, then "— host/path" for a page or
"Switch to Tab ➜" for a tab.

## Ranking

The rows are ranked with Arc's own scorer, ASE2, and its compiled-in weights.
Every row gets all of ASE2's features, each is normalised over the query's
rows, and the categories are weighted: kind 35, Chromium's rank and relevance
25, recency 15, saved-ness 15, visit and typed counts 10, text match 2. An
additional match has no Chromium rank and takes ASE2's default, 11. Boosts join
the weighted mean:

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

- the text matcher (prefix, word start, inside a word), and which open tabs a
  query offers: those whose title or URL holds it;
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

- **Inline completion**: the top row's rest is typed in and selected, from
  Chromium's default match or from an open tab's URL. As in Chromium, there is
  none after a deletion, with the caret before the end of the text, or while
  an input method composes. Moving the caret or selecting keeps what the
  field shows and leaves the rows as they are; the next edit takes the field's
  text as typed, as in Arc.
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
Settings… opens Chromium's search engines page in a tab of the first window
showing a Space of that profile, or of a new window on one when none does, Oa's
own; Arc opened it in any window.

**View History ⌘Y** in the Archive menu opens Chromium's History page in a new
tab at the top of the Space, for the Space's profile. Deleting a page there
removes it from the bar too.

Not done yet, as later slices: Arc's commands in the bar, Site Search with Tab,
the sidebar's URL pill, Little Arc's bar and the onboarding rows.

Related: [Sidebar state](../sidebar/README.md) · [Peek](../peek/README.md).

Return to the [feature inventory](../README.md).
