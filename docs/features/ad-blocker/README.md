# Ad blocker

Oa's built-in blocker is opt-in in **Settings → General**. Block Ads selects
EasyList; Block Trackers selects EasyPrivacy. The switches and site exclusions
apply to every profile, following Arc's native blocker. Site Controls can turn
blocking off for the current host and offers **Reload Page** to retry resources
that were already blocked.

## Lists and updates

The app bundles unmodified EasyList and EasyPrivacy, and downloads updates
straight from their authors:

- https://easylist.to/easylist/easylist.txt
- https://easylist.to/easylist/easyprivacy.txt

There is no dependency on Arc or Dia servers. Attribution and license links
ship alongside the lists in DevKit's resource bundle.

DevKit owns the catalogue, saved selections and update loop. Each logical
list has ordered URL components. `BlockList.json` stores their original text,
URL, ETag and last-update date; components are joined with LF. The current
catalogue has one component per list. `AdBlockSettings.json` stores the global
master switch, selected list IDs and excluded hosts beside the list cache in
Oa's data directory.

Cached rules, or bundled rules on first use, are applied before restored pages
open. While enabled, updates run at startup and hourly, with a three-hour
minimum age per URL. Conditional requests send the saved ETag. A 304 retains
the old text and timestamp. A failed component retains the previous logical
list. Successful downloads are written atomically; update errors are shown in
General without clearing the working rules. These collection rules follow the
Arc research.

## Page loading

Core compiles the selected text on a background thread using Chromium's
filter-list parser and ruleset indexer. An immutable shared-memory snapshot
contains the network and cosmetic rules. Browser and renderer throttles match
requests locally; there is no Swift call for each request. Rule updates are
sent to existing renderer processes and replayed to new ones.

The browser throttle exempts main documents and first-party requests. The
renderer throttle also checks first-party subresources, as Arc's does.
Request destinations select the filter resource type; fetch/XHR use OTHER.
Requests blocked by Oa return Chromium's `ERR_BLOCKED_BY_CLIENT`. Redirects
are not rechecked by these throttles.

At document start, each frame receives a stylesheet built from matching domain
and generic selectors, with cosmetic exceptions applied. CSS also hides
matching elements added later. Changing rules, exclusions or the master
switch replaces or removes the stylesheet in open documents.

Site exclusions are decided from the request alone, as Arc's are: its
initiator, its top frame's origin, and for the browser's own requests the top
frame in their isolation info. Blink already knows the top frame for frames
and dedicated workers; a Chromium patch copies it onto the network request,
where Arc added the same field. It is not sent over Mojo.

Two small Chromium patches support this. One installs Oa's renderer client in
macOS helpers; those helpers enter `ChromeMainDelegate` rather than Oa's
browser delegate. The client preserves Chrome's renderer hooks and throttle
provider. The other adds the top frame's origin to renderer requests.

## Oa choices and limits

Arc research confirms General as the settings location and global native
rules/exclusions. Opt-in startup, the two-list catalogue, exact-host matching,
the explicit Reload button, and Chromium's standard blocked-request error are
Oa's choices. Excluding `example.com` does not automatically exclude
`www.example.com`. A frame is exempt when its own host or its top-level host
is excluded.

This slice does not implement Arc's profile-specific extension chooser,
additional regional/annoyance lists, custom subscriptions or scriptlets.
Chromium's parser determines supported filter syntax; `+js` rules are omitted.
A service worker has no top frame, so only its own origin is checked against
the exclusions. This is not a claim of complete Arc or uBlock Origin parity.

## Verification

Swift and Chromium builds passed. Live checks used a renamed app bundle with
separate data and Chrome DevTools MCP. They covered network blocking, ordinary
and dynamically inserted cosmetic targets, cosmetic exceptions, a second
browser context, live master/exclusion changes, cache restart, ETag/304,
failed updates retaining working rules, successful rule replacement, and a
dedicated worker inside a cross-site iframe on an excluded page. The DevKit
settings path was also exercised in the stub engine. Native settings
click-through and layout were not automated through DevTools.
