# Space theme editor

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

A Space's theme is made in Arc's theme editor. It opens from Spaces ▸ Edit
Theme…, from Edit Theme Color… in the Space menu (the Space name's and the dock
item's), from a Library card's brush, and from Choose a Theme in Create a Space.

## Where it opens

- **From the menus** it hangs off the sidebar's right edge, level with the
  pointer, with no arrow. With the sidebar hidden, the floating sidebar comes
  out for it and stays out until it closes.
- **From the Library**, a card being the Space's sidebar, it hangs off the
  card's right edge the same way.
- **From Create a Space** it points at the Choose a Theme row.

It is a transient popover, as Arc's. A click outside closes it, and so does
Escape, unless a page has the keyboard.

## What it holds

The editor keeps what Arc's does: a key colour, how many colours (one to
three), the wheel the others are turned on, the intensity, the texture and its
amount. The theme is built from those as Arc builds it:

- **One colour** is a single colour. **Two** are a gradient from the key colour
  to one turned 180°. **Three** turn the others 150° and 210°, and the third
  fades in over the gradient from the top.
- **The page-two presets** are three close colours: turned 40° and −40°.
- **Both palettes** the chrome draws in come from the key colour, and so does
  whether the sidebar's content is light or dark, by its contrast with the two
  title colours.

Themes Arc's editor saved, rebuilt this way, come back colour for colour.
Opening the editor on a Space builds its state from the Space's
theme; the second and third colours are always worked out again from the key.

## The controls

- **The pad.** A tap or drag sets the key colour: the angle is the hue, the
  distance from the centre the lightness. − and + remove and add colours;
  removing the last removes the theme, with its texture.
- **The presets.** Five pages of nine, in Arc's order: Arc's brand colours,
  the same as three close colours, then pastel, drab and greys. A preset keeps
  the intensity and texture. The window keeps the page for all its editors.
- **The intensity wave**, 0 to 1, 0.8 for a new theme.
- **The dial.** Dragging round it, or clicking the ring, sets the texture's
  amount in steps of 0.05, a full turn being 1. A click in the centre turns the
  texture on at 0.8, then moves through grain, sand, denim and tweed, then off.
- **Automatic, Light and Dark** set the app's appearance, as View ▸ Appearance
  does. They leave the theme alone, as in Arc.

The trackpad taps as the intensity passes each fifth and the dial each tenth.

## Live, then saved on close

The window draws the Space in the editor's theme while it is open, on every
change. The Space keeps its saved theme until the editor closes, however it
closes, and there is no Cancel. Each change is its own "Update Theme" step on
Edit ▸ Undo, and ⌘Z works with the editor open.

In Create a Space, the whole window shows the chosen theme before Create, and
the Space is made with it. The Create Space button is drawn in the theme's
darkest colour, as Arc's is.

## Oa's own

- Opening the editor from a Space's menu shows that Space first.
- Changes made in Create a Space's editor file no undo steps; where Arc's go
  isn't traced.
- The icons, knobs, dot grid and dial are drawn by Oa, after Arc's measures;
  Arc's images and animations aren't used.
- Arc's editor also moves the colour into a light or dark range when told to
  force an appearance. Nothing in Arc was found to send that, so Oa leaves it out.
- The command bar's Edit Theme… row waits for the command bar's actions.
