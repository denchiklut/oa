# Profiles

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

A profile is a Chromium profile: its own cookies, history, logins, extensions
and settings. Each Space uses one profile, and a profile's Favorites show in
every Space that uses it. Profiles are made, renamed and deleted in Settings ▸
Profiles, as in Arc.

## Who owns what

The engine owns the list of profiles and their names, as Arc's does. DevKit's
`allProfiles()` reads Chromium's profile storage, loaded or not, in Chromium's
own order, and `userVisibleName(of:)` reads a name from it each time. The app
stores no name. The pane lists the profiles in that order, not by name; Arc's
list is not sorted either. `sidebar.json` keeps only what the sidebar needs for
a profile: its ID and its Favorites root.

An older `sidebar.json` carries profile names. At the first launch the engine
takes them over once, and they leave the file; a new install's one profile is
named "Personal" the same way. An older build can't read the file after that.

A profile's ID is an app UUID and its Chromium directory is `Oa-<UUID>`. Arc
names its directories `Profile N`; nothing in creating, renaming or deleting a
profile depends on that. The profile every install starts with has a fixed ID
and can't be deleted.

## The strip under the list

`+`, `−` and edit, at Arc's sizes and with Arc's symbols. `+` and edit are
always on. `−` is off for the default profile and for a profile that a Space
uses. Its two explanations ("The Default Profile cannot be deleted." and "Only
Profiles not assigned to any Spaces can be deleted.") are set as help on the
disabled button, where macOS never draws them; they reach accessibility only,
as in Arc. Arc's fourth button, "Delete unused Profiles", sits behind a remote
flag that is off, and Oa doesn't have it.

## Creating a profile

Three sheets on a browser window, as in Arc:

1. **Create a new Profile.** The name is cut at 500 characters as it is typed
   and newlines become spaces. Next stays off for an empty name, for another
   profile's name ("A Profile with that name already exists."; the check trims
   and is case-sensitive) and for one of Chromium's reserved names ("Invalid
   Profile name."). No character is refused.
2. **Which Spaces should use this Profile?** A card per Space; Create Profile
   stays off until one is ticked. Back keeps the name.
3. **Switch to your ‹name› Profile?** The profile exists by now, with an empty
   Favorites root, and is selected in Settings. "Switch it up" moves the ticked
   Spaces to it; Cancel leaves it unused.

The sheet opens from Settings ▸ Profiles ▸ `+` on the last key browser window,
with nothing ticked; from File ▸ New Profile with the window's Space ticked;
and from a Space's menu ▸ Set Profile ▸ New Profile… with that Space ticked.
With no browser window open, `+` does nothing. Arc also opens it from the
command bar and from Spaces ▸ Change Profile, and has a one-step form in its
Create a Space panel; Oa has none of the three yet.

The sheets use Arc's wording, sizes and colours as measured in light
appearance. The dark colours are Oa's own, and so are the symbols in place of
Arc's mascot art. Each Space card shows the window's theme until Spaces have
themes of their own.

## Moving a Space to another profile

A Space's menu ▸ Set Profile lists the profiles with a tick on the current one.
Choosing another asks with the same "Switch to your ‹name› Profile?" sheet.

A page can't change profile, so a move keeps nothing of the Space's pages, as
in Arc: every live page of the Space is dropped without asking, and its Peeks
with it. The window showing the Space then selects its bottom-most unpinned tab
and loads it in the new profile. Every other tab loads when it is next
selected, a pinned tab at its pinned address and an unpinned one at its last
address, with no history. The Favorites row shows the new profile's Favorites;
the old profile keeps its own. A command bar open over the Space closes, since
it searches the old profile, and opens again for a new tab when the Space has no
tab to select; that part is Oa's own.

Arc leaves the pages a second window holds alive in the old profile, where they
show blank. In Oa a tab has one page, and it is dropped whichever window holds
it.

## Renaming

Edit opens "Rename your Profile" on the Settings window with the name selected.
This is Arc's other name dialog, with other rules: the name isn't cut, and over
256 characters Save goes off with "Almost there, name must be 256 characters or
less." Another profile's name, or a reserved one, gets "A Profile with that
name already exists."; the profile's own name in any case is fine. With a
single profile Arc skips both checks, and so does Oa. Save writes Chromium's
profile name; the Spaces keep theirs.

## Deleting

`−` opens "Delete this Profile" on the Settings window. Delete stays off until
the profile's name is typed; the match ignores case and doesn't trim. Every
window then lets go of the profile (its Favorites' pages, its browser and its
omnibox) and DevKit drops its context, before Core releases its own hold and
hands the profile to Chromium's `DeleteProfileHelper`. With nothing left
holding it, Chromium unloads the profile and removes its directory at once.

The profile's Favorites go with it and are not archived. Its entry for the
archive interval stays, as in Arc. Archive entries record a Space, not a
profile, so they stay too; one whose Space is gone returns to the window's
Space. The pane then selects the profile of the frontmost browser window's
Space.

## Archive tabs after

Changing the interval always writes the profile's own entry first. When there
are several profiles and their stored entries now differ, a sheet on Settings
asks "Oa will now archive your tabs after ‹value›": "Only this Profile"
(Escape) writes nothing more, and "All Profiles" (Return) writes an entry for
every profile and the value for all. With no question, the value for all is
written as well, so every profile without an entry of its own follows the
change. That is Arc's rule, taken as it is.
