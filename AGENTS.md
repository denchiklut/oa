# Notes for agents

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. These are the working rules the
author has asked for, in addition to it.

## Comments

Write a comment only when it says something the code can't: a decision and
its reason (often "as Arc does"), ownership or lifetime that isn't visible at
the call site, or a workaround for something in Chromium. Never restate what a
method does or what a type is for; the name does that. Doc comments on DevKit's
public protocols are the exception, kept to one or two lines. When in doubt,
leave the comment out.

## Code

Thin vertical slices across UI, DevKit, Core and Chromium, with seams in their
final shape even when the slice is small. Concise code, no unit tests for now.
Only the shortcuts the slice names; matching Arc's hotkeys is its own PR.
Product behavior follows what research in `docs/.local/research/` confirmed
about Arc; label a decision as Oa's own where Arc's behavior is unknown.

## Commits

Conventional lowercase subjects, no body: `feat(ui):`, `feat(devkit):`,
`feat(core):`, `fix:`, `docs:`, `chore:`. No attribution trailers or footers
in commits or pull requests.

## Workflow

Present the plan and wait for an explicit yes before writing code. Format with
`swift format --in-place --recursive ui devkit` and clang-format from
`.local/chromium/depot_tools` before committing. Verify on the stub and on the
live engine with a renamed copy of the bundle, never by driving the author's
own running Oa.
