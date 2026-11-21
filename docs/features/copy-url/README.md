# Copy URL

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

Edit ▸ Copy URL ⇧⌘C copies the address of the page in front, as Arc's does: a
Peek's while one is up, else the shown tab's page as it is now, so a pinned tab
that has moved on gives where it is, not where it is pinned. The link button
in the address field is the same command.

- **The binding** is Arc's `copyCurrentURL`, and it wins over a page that wants
  the key; both can be changed in [Settings ▸ Shortcuts](../key-bindings/README.md).
- **The clipboard** gets one item, a URL and the same as text, as Arc writes
  it. No title and no rich link.
- **Trackers are stripped**, by Arc's rule and lists: query items whose name
  starts with one of 42 prefixes (`utm_`, `mc_`, `pk_`, `ref` and so on) or is
  one of 23 names (`fbclid`, `gclid`, `si` and so on), and a few more on
  Twitter and X, YouTube, eBay and Amazon, where a last path component that
  starts with `ref=` goes too. A URL with a `;` in its query is left alone.
- **The toast** comes over the page for five seconds: "Copied Current URL", or
  "Copied a clean link without trackers" when something was stripped.

As in Arc, a URL with a query is put together again from its items even when
none was a tracker, so `%2B` in a value is copied as `+`. And an Amazon path
that loses its `ref=` end is escaped a second time, so `%20` in it is copied
as `%2520`.

Oa's own: with no tab the item is off; Arc's stays on and offers to share the
Space. Arc's toast also has a Share button, which Oa's doesn't yet. Copy URL as
Markdown and as Quote are not there.
