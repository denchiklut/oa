# Picture-in-picture

Oa implementation notes. The [Chromium chapter](../../architecture/chromium/README.md)
describes the broader intended responsibilities.

A video keeps playing in a small floating window when its tab stops being
shown, and goes back into the page when the tab is shown again, as in Arc.
Chromium does the playing: its picture-in-picture session, its media session
and its one-video-at-a-time manager are untouched. Core replaces only the
window Chrome would draw, a views widget with Chrome's own controls, through
a hook Chromium already has, so no patch is needed. ArcCore replaces the same
window the same way.

## When it opens and closes

The app decides, with Arc's rule in Arc's order, each time the page a window
shows changes: another tab is selected, a new tab opens over it, the Space is
switched. A page that moves between windows counts once the move has settled.

The app leaves a page's picture-in-picture alone when any of these holds:

1. the page's address is on the disallow list (Slack, Google Meet and
   Microsoft Teams, as Arc bundles it);
2. automatic picture-in-picture is switched off (`autoPipGloballyDisabled`,
   Arc's key; Oa has no switch for it in Settings yet);
3. the site's Automatic Picture-in-Picture setting is Block.

Otherwise the video should be in picture-in-picture when all of these hold:

1. the page's media session is active, which is what playing means here;
2. the media has sound and picture;
3. no window shows the page;
4. the page is audible, or its site is one that may start silent (YouTube).

A page that captures the camera or microphone is asked for whenever no window
shows it, as in Arc. When the answer differs from what the page has, the app
asks the engine to enter or to leave. The window is up within a tenth of a
second of leaving the tab and gone as fast on return.

The engine can still refuse, and nothing shows then. It refuses a page with no
media session, and a video that carries `disablepictureinpicture`: Oa
overrides no restriction a page sets. So a clip that has ended, a paused
video, a muted one and one that opts out all stay in their tabs.

A page's own request, as from a site's picture-in-picture button, lands in
the same window and follows the same rule afterwards. Chromium's automatic
picture-in-picture, which acts only for pages that register the media
session's enter action, is left as it is upstream.

## The window

One window for the app. It is Arc's as read from Arc 1.172.2:

- a non-activating panel with no title bar, floating above other windows, on
  every Space and beside full-screen windows, with a shadow and 6 pt corners;
- 320 pt wide at first, with the height from the video's own proportions,
  which resizing keeps; never smaller than 224×126;
- dragged by the video;
- at the frame it had when it last closed, saved as `LastPiPPosition` in the
  JSON Arc writes.

With nothing saved it opens at the main screen's top right, 10 pt in. Arc's
place for that case is unknown, so this one is Oa's own.

Two controls show over a dimmed video when the pointer moves 3 pt or more
over the window, and fade 3 s after its last move:

| Control | Place | What it does |
| --- | --- | --- |
| Back to Tab | top left | Selects the video's tab in its window; the video plays on there |
| Close | top right | Ends picture-in-picture and pauses the video; the selection stays |

Both are 28 pt tall and 16 pt in from the corner. Back to Tab is an icon
until the window is 400 pt wide and carries its label from there. Close loses
its label under 280 pt, where the inset drops to 12 pt. These are Arc's
measurements. How much Arc dims the video is read off its captures, and the
controls' accessibility labels are Oa's own: Arc's have none.

## Layers

| Layer | Holds |
| --- | --- |
| UI | The rule, the session states (Arc's names), the floating panel and its controls |
| DevKit | `MediaSession` on the page (state, request, exit with or without a pause), the page's `isAudible` and its picture-in-picture events with the engine's video view |
| Core | The `VideoOverlayWindow` Chromium is given for a page's video: a view that draws the video's surface through a compositor of its own, and show, hide, close and resolution as page events; request and exit through the page's media session and Chrome's picture-in-picture manager |
| Chromium | Nothing: `ContentBrowserClient::CreateWindowForVideoPictureInPicture` is overridden in the client Core returns |

The view gives its compositor its size in points as the size in pixels, as
ArcCore's does.

The stub engine's pages have a "Play a video" link; a playing page's
picture-in-picture shows a placeholder view.

Not done yet: Minimize, the playback controls and scrubber, the sidebar mini
player, the switch in Settings and the Site Controls row, the per-site
snooze, the site attributes that hide controls, a refreshed site
configuration, throwing the window to a corner and keeping it inside the
screen, pinch and two-finger gestures, picture-in-picture when the window is
covered, Document Picture-in-Picture and Google Meet. Arc also keeps a muted
tab out; Oa has no tab muting yet.
