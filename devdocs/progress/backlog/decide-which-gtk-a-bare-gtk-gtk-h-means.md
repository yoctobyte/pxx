---
track: U
prio: 55
type: decision
blocked-by: []
summary: "GTK2 and GTK3 both answer to `#include <gtk/gtk.h>` and are told apart only by include root. /usr/include/gtk-2.0 is a default system include root and gtk-3.0 is not, so GTK3 needs an explicit -I today. Adding gtk-3.0 to the defaults decides the GTK version for every C consumer at once — including the GTK2 macro-soup regression guard."
---

# Which GTK does a bare `#include <gtk/gtk.h>` mean?

Filed 2026-08-29 by frankC (Track C) out of
[[feature-c-gtk3-header-final-wiring]], which is parked in `unfinished/` on this
answer. The capability that ticket was about is **proven and gated** — stock
GTK3 headers import, link to `libgtk-3.so.0` and run a real window
(`test/test_c_gtk3_stock.pas`). What is not settled is the default.

## The fork

Both header sets exist on a normal box and both are reached by the *same*
spelling:

```
/usr/include/gtk-2.0/gtk/gtk.h
/usr/include/gtk-3.0/gtk/gtk.h
```

`BuildCSysIncludeDirs` (`compiler/cpreproc.inc`) makes `/usr/include/gtk-2.0/`
a default system include root. `/usr/include/gtk-3.0/` is **not** one — which is
the entire reason GTK3 needs an explicit `-I/usr/include/gtk-3.0/` today, and
the reason the ticket's recorded 2026-06-29 probe failure looked like a deep
import bug when it was a wrong include root (it passed
`-I/usr/include/gtk-3.0/gtk`, so `#include <gtk/gtkactionable.h>` could not
resolve).

Everything else GTK3 needs — glib, pango, cairo, gdk-pixbuf, atk, harfbuzz,
freetype2, pixman, fontconfig — is **already** in the default roots and is shared
with GTK2. The gtk root is the only divergence.

The list is flat and global, so whichever gtk root comes first wins for **every**
C consumer in the process. There is no per-unit include path today. That is what
makes this a decision rather than a patch.

## Options

1. **Leave the defaults alone; GTK3 requires an explicit `-I`.** Status quo, and
   what the new test does. Costs nothing, breaks nothing, and keeps the GTK2
   macro-soup regression guard authoritative. But `uses gtk3_c` alone does not
   work, so the PCL binding can never be a plain `#include <gtk/gtk.h>` without
   every consumer passing a flag.
2. **Put `/usr/include/gtk-3.0/` in the defaults, before gtk-2.0.** GTK3 becomes
   what a bare `<gtk/gtk.h>` means. This *silently* re-points the existing GTK2
   tests at GTK3 headers while they still link `libgtk-x11-2.0.so.0` — a header
   set and a shared library from different major versions. Would need the GTK2
   tests migrated or pinned with their own explicit `-I` in the same change.
3. **Put it in the defaults, after gtk-2.0.** Achieves nothing: gtk-2.0 still
   wins for `<gtk/gtk.h>`, so GTK3 consumers still need the `-I`. Listed only to
   record that it was considered and is a no-op.
4. **Give the include root a scope — the stem already knows.** `CHeaderStem`
   already maps the unit `gtk3_c` to the stem `gtk-3` and `gtk` to
   `gtk-x11-2.0`, and that stem is what picks the soname. Let it pick the
   include root too, so a GTK3 binding searches gtk-3.0 first and a GTK2 binding
   searches gtk-2.0 first, with no global default disturbed. Principled, and it
   is the "normalise, don't special-case" answer — one fact (which GTK am I
   binding) driving both the library and the headers instead of one driving the
   library and a flag driving the headers.

## Recommendation

**Option 4**, with option 1 as the standing behaviour until it is built. It is
the only one where both GTK versions keep working without a flag and without
either silently shadowing the other, and it needs no new concept — the stem→root
association is the same fact as the existing stem→soname one, which is already
computed at exactly the right moment.

Its cost is honest and worth stating: the stem is computed in `CHeaderStem`
(`compiler/pasparser_proc.inc`, **Track P**'s file) and the include roots are
built in `BuildCSysIncludeDirs` (`compiler/cpreproc.inc`, **Track C**'s), so the
plumbing crosses a lane boundary and wants an owner assigned rather than a lane
guessed. That is the second thing this ticket is asking.

## Related

- [[feature-c-gtk3-header-final-wiring]] — parked on this; its capability half is done.
- [[feature-b-migrate-pcl-off-the-curated-gtk3-header]] — wants option 1 or 4 settled first.
