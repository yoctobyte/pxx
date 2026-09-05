---
track: A
prio: 40
type: feature
status: done
found: 2026-08-31
found-by: frank-user, at the owner's request
owner: ""
blocked-by: []
summary: "DONE 2026-09-05 (frankC) — `--gtk=2|3|4`, default 3. The owner asked for GTK 2/3/4 user-selectable, defaulting to 3. SPLIT DELIBERATELY, because the two halves have wildly different costs. The RESOLVER half is cheap: one version variable driving the hardcoded literals -- the default include root, the header path fallback and the alias-map stem. NOTE (2026-09-05, frankC): the GTK 3 default LANDED, so those literals now read gtk-3.0 and there are THREE of them, not four -- the arch-specific root was deleted rather than moved, GTK 3 keeping gdkconfig.h inside /usr/include/gtk-3.0/gdk/. That also retired a hardcoded x86_64-linux-gnu path, so a version selector must not reintroduce one. Line numbers deliberately dropped from this summary: the ones it used to carry (2219-2220 / 3105 / 2834-2836) had already drifted twice before the change landed -- grep the root literal instead, and cite the address rather than the value. The WIDGETSET half is a PORT and is NOT in scope: gtk3widgets.pas, gtk3.pas and gtk3gl.pas bind GTK 3 specifically, and GTK 4 reshaped the container, event and drawing models. So this feature buys the right headers and the right soname -- it does NOT make the PCL widget layer work on 2 or 4, and saying it does would promise work nobody has done. GTK 4 additionally needs libgtk-4-dev: plexus has the GTK 4 runtime but no /usr/include/gtk-4.0."
---

# GTK version selection at the header and soname layer

Follows `decided/decide-which-gtk-a-bare-gtk-gtk-h-means` (GTK 3 is now the
default). This is the *selectable* half the owner asked for: *"if we (easily)
_can_, gtk 2/3/4 should actually be user selectable, defaulting to 3.. but maybe
this creates a library hell."*

**It does not create library hell at this layer**, which is why it is worth
doing. It would at the widgetset layer, which is why that is excluded.

## In scope

A single version selector — flag or directive — driving the four sites the
parent ticket enumerates. Default 3.

## Explicitly OUT of scope, and say so in the docs

The PCL widget layer stays GTK 3 only. Selecting 2 or 4 gives a C program the
right headers and the right `DT_NEEDED`; it does not port `gtk3widgets.pas`.

## Naming, from the parent ruling

`gtk` and `gtk3` are not parallel names today — the first two are alias-map
entries, `gtk3` is a Pascal unit file (`lib/pcl/gtk3.pas`). Whoever builds the
selector should settle that, or the version flag inherits the same confusion.

## Blocked in practice for GTK 4

No `/usr/include/gtk-4.0` on plexus. `libgtk-4-dev` is needed before the 4 arm
is testable at all — until then, build and test the 2 and 3 arms and refuse 4
with a diagnostic that says why.

## 2026-09-05 (frankC) — DONE: `--gtk=2|3|4`, default 3

The resolver half, which is all this ticket ever scoped. `CGtkVersion` in
`defs.inc` drives **two** functions and nothing else reads a GTK literal:

- `CGtkIncludeRoot` -> the C include root (`cpreproc.inc`)
- `CGtkStem` -> the alias-map stem, hence the soname (`pasparser_proc.inc`)

**They come from one variable ON PURPOSE.** Headers and soname disagreeing —
GTK 3 headers against a GTK 2 library — is the hazard the parent ruling names,
and it is exactly what doing *half* the change produces. Deriving both from
`CGtkVersion` makes the mismatch **unrepresentable** rather than merely
avoided.

### Measured

| | soname | runs |
| --- | --- | --- |
| default (no flag) | `libgtk-3.so.0` | yes |
| `--gtk=3` | `libgtk-3.so.0` | yes |
| `--gtk=2` | `libgtk-x11-2.0.so.0` | **yes** — real window, `gtk_main` loop |
| `--gtk=4` | refuses, naming `libgtk-4-dev` | — |

The GTK 2 run is the load-bearing row. **A soname assertion alone cannot tell a
coherent pick from a mismatched one** — headers and library disagreeing links
fine and dies at run time — so the test asserts the pair.

### GTK 4 is PROBED, not hardcoded unavailable

This ticket said to "refuse 4 with a diagnostic that says why" until
`libgtk-4-dev` lands. Implemented as a **filesystem probe** of
`/usr/include/gtk-4.0` rather than a literal refusal, because a hardcoded
"4 is unsupported" **stays wrong after somebody installs the package** — the
same defect as the hardcoded gcc include version this file's neighbours were
fixed for, a fallback that expires silently. The row flips to a build on its
own when the headers appear.

The diagnostic names the package **and** the missing directory, and
`--gtk=9` still answers `unknown option` — asserted, because "the flag failed"
and "the flag is not recognised" must not read alike.

### `gtk3_c` follows the selector, despite the `3` in its name

The C include list is **flat and global** — there is no per-unit search path —
so one compilation has exactly one GTK's headers. Pinning `gtk3_c` to GTK 3
while `--gtk=2` moved the root would hand it GTK 2 headers against
`libgtk-3.so.0`, which is the mismatch this feature exists to prevent. The flag
wins and the halves stay coherent. The naming remains the wart the parent
ruling records (`gtk`/`gtk3_c` are C aliases, `gtk3` is a Pascal unit).

`test/gtk3stock/gtk3_c.h`'s own `#error` guard catches the combination and
refuses loudly — verified. Its advice was stale after the default flip ("pass
-I for the gtk-3.0 root") and now says to drop `--gtk=2` instead.

### Still explicitly OUT of scope, and unchanged

The **widgetset half**. `gtk3.pas`, `gtk3widgets.pas` and `gtk3gl.pas` bind
GTK 3 specifically and GTK 4 reshaped the container, event and drawing models.
Selecting 2 or 4 buys the right headers and the right `DT_NEEDED`; it does
**not** port the PCL widget layer. Verified unchanged: the PCL stack still
builds and links `libgtk-3.so.0` at the default.

### One wart recorded rather than silently reintroduced

GTK 2 **alone** needs a second, arch-specific root
(`/usr/lib/<triplet>/gtk-2.0/include/`) because its `gdkconfig.h` lives there;
GTK 3 and 4 keep theirs inside `/usr/include/gtk-N.0/gdk/`. The triplet is
spelled literally, which is the **pre-existing** wart it shares with its
neighbours (glib's arch root, `/usr/include/<triplet>/`, the gcc dirs) — wrong
on every non-x86-64 host for all of them at once, so it is one job across the
block, not a special case here. **The GTK 3 default reaches no literal triplet
at all.**

### Gate

`gate.sh quick` **GREEN 17/17 including the FPC seed canary**, run with
`compiler/**` uncommitted. Fixedpoint `546ec0cf30a3`.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
