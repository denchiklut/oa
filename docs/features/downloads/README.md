# Downloads

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

Chromium downloads the files, as it does in Arc: its own delegate picks the
name and folder, writes the `.crdownload` file and renames it, quarantines the
result, keeps the history per profile, asks before a site downloads several
files at once through the permission prompt, and badges the Dock icon. Oa adds
nothing to that path and replaces none of it. What it adds is the list.

Core has one downloads object per profile, as ArcCore has per browser context:
an observer of every item of the profile's download manager, which reports the
downloads Chromium's history brought back, then each one created, updated and
removed, each as a snapshot of what ArcCore's download item reads: the item's
GUID, state, bytes received and expected, speed, seconds left (−1 while there is
no estimate), target path, source URL, start time, whether it is paused, done
or resumable, and the page that started it. It pauses, resumes, cancels and
removes by GUID. Every event is posted, as ArcCore posts its delegate's. This
Chromium loads the history only when a download UI asks for it, so the object
asks when it starts, as Chrome's bubble and downloads page do. ArcCore's hook
for the file name is left out: Arc's app answers it at once with the default.

DevKit carries that on the profile's `BrowserContext` as `downloads`, an
observable list of `Download` values kept current by those events, never
polled, with Arc's statuses: not started until Chromium has chosen the file,
in progress, paused, finished, failed for an interrupted download, cancelled.
Opening, revealing, copying and trashing a file stay in the app, as in Arc. The
stub engine's pages have "Download a file" and "Download a file that fails",
which run for fifteen seconds and leave a small text file in a temporary folder.

## The Library

The sidebar's bottom row starts with the Library button, left of the Spaces.
While downloads run it carries a white disc with a blue arrow and one ring for
all of them, as Arc's does; its symbol is Oa's own. Hovering it shows Arc's
flyout: the four most recent downloads, the newest at the bottom, each with its
Quick Look thumbnail or file icon, name and age; a running one with its own
ring, "32.6/94.4 MB · 1m 1s" and an ✕ that cancels; a cancelled one as
"Cancelled · from ‹host›" and a failed one as "Failed to Download", both
without an icon. A finished one whose file is gone is left out, as in Arc. A
finished row drags out as a file. Arc's flyout also lists its Library's other
files, which Oa doesn't have.

A click on the button, or Window ▸ View Downloads…, puts the Library in the
sidebar's place with the page still showing; the menu item then reads Hide
Downloads. It has Arc's Downloads section only, 300 pt wide, Oa's own width.
The list merges every profile's downloads, newest first, under Today,
Yesterday, N days ago, 1 week ago and N weeks ago. A row has the thumbnail or
icon, the name and Arc's line under it: "‹Kind› from ‹host›" with Arc's type
words (Image, Disk Image, PDF, Video, Movie, Audio, Zip Archive, Archive) and
"Download" for the rest, "50.8/94.4 MB · 45s" with the ring while it runs,
"Opening… (24%)" once it is set to open, "Paused", "Failed to Download" and
"Cancelled" greyed. A source that is a bare address, such as 127.0.0.1, isn't
named, as in Arc. What was cancelled, failed or lost its file before the
Library opened isn't listed; one that ends so while it shows stays until the
next time, as in Arc. "Search Downloads…" narrows the list by name, and Filter
opens "Filter Downloads…" with a chip per profile. An empty list reads
"Nothing here yet!".

A click on a finished row previews the file over the window with Quick Look:
close, previous and next, the name and age, a menu with Send via iMessage,
AirDrop and Show in Finder, and "Open in ‹App›". A click on a running row makes
it open in its app when it finishes, as in Arc. A row's "…" button and its
context menu have Arc's items: Open ‹Kind›, Copy ‹Kind›, Show in Finder, Cancel
Download while it runs, Hide from Oa, and Move to Trash once it is finished;
‹Kind› falls back to the file's extension. A cancelled or failed row keeps the
first three disabled. Hide removes the row and Chromium's record and leaves the
file; Move to Trash removes all three. Copy puts the file on the pasteboard as
Finder does; what else Arc puts there is unknown. The flyout's rows have Arc's
shorter menus: Cancel Download for a running one; Copy, Send via iMessage,
AirDrop, Open in ‹App›, Show in Finder, Hide from Oa and Move to Trash for a
finished one; none for a cancelled or failed one. No pause, resume or retry
anywhere, as in Arc, though the engine can.

## Quitting

Quitting with downloads running asks first, with Arc's words: "Downloads in
progress", "There are downloads in progress. Closing the application will
cancel them.", Close Oa on Return and Keep browsing on Esc. It comes after the
"Quit Oa?" warning when that is on and alone when it is off, and before any
page's "Leave site?". Arc draws its own panel over the key window; Oa's is a
sheet there. Closing a window never asks, and its downloads keep running. On
Close Oa, Chromium cancels the downloads and deletes their partial files, Oa's
own: Arc leaves the `.crdownload` file behind.

## Where files go

Settings ▸ Profiles has Arc's "Download location" for each profile: the folder,
Other… to choose one, and Ask every time. They are Chromium's
`download.default_directory`, `savefile.default_directory` and
`download.prompt_for_download` for the profile, read and set through Core and
DevKit as ArcCore's preferences are. With Ask every time, Chromium shows its
Save panel as a sheet on the page's window; cancelling it leaves no row and no
file.

## Not there yet

The download's flight into the Library button, the Library's other sections,
Arc's renaming of finished files, the shortcuts (⇧⌘J, ⇧⌘L) and anything for a
download Chromium holds as dangerous or insecure: as in Arc, such a download
stays in progress and only `chrome://downloads` can keep or discard it.
