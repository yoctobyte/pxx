---
track: U
prio: 55
type: decision
blocked-by: []
summary: "RULED 2026-08-31: GTK 3 is the default -- \"i think gtk3 is a sane default in 2026\". A bare <gtk/gtk.h> resolves to GTK 3; the default C include roots move from /usr/include/gtk-2.0/ to gtk-3.0/. Four hardcoded literals, not a system: cpreproc.inc:2219-2220, pasparser_proc.inc:3105, and the alias map at pasparser_proc.inc:2834-2836. Blast radius is three test files that use `uses gtk`. NilPy tk is NOT affected -- lib/pcl/tk.pas is a Tcl/Tk 8.6 soname embed that never touches GTK, checked not assumed. GTK 4 is unreachable regardless: its lib is installed here, its headers are not. Version selection filed separately as feature-a-gtk-version-selection-at-the-header-and-soname-layer -- the resolver half is cheap, the WIDGETSET half is a port and must not be promised with it."
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

---

# RULED 2026-08-31 — GTK 3 is the default

Owner: *"i think gtk3 is a sane default in 2026."* Everything in the tree already
targets it — `lib/pcl/gtk3.pas`, `gtk3widgets.pas`, `gtk3gl.pas` all bind
`libgtk-3.so.0`. GTK 2 is the anomaly, not the baseline.

## The change is four literals, not a system

- `compiler/cpreproc.inc:2219` and `:2220` — the two default C include roots,
  hardcoded to `/usr/include/gtk-2.0/` and the arch-specific
  `gtk-2.0/include/`.
- `compiler/pasparser_proc.inc:3105` — header paths built from
  `/usr/include/gtk-2.0/gtk/`.
- `compiler/pasparser_proc.inc:2834-2836` — the alias map: `gtk3_c` -> stem
  `gtk-3` -> `libgtk-3.so.0`; `gtk` -> stem `gtk-x11-2.0` ->
  `libgtk-x11-2.0.so.0`.

## THE NAMING IS THE REAL DEFECT — owner, and it is sharper than "rename it"

*"you said 'uses gtk'.. but, logically, that ought to be 'uses gtk3'."*

**`gtk` and `gtk3` are not parallel names — they live in different namespaces**,
which is why this reads wrong and keeps reading wrong:

- `uses gtk3_c` is a **C header import**, resolved through the alias map.
- `uses gtk` is *also* a C header import, resolved through the same map — to
  **GTK 2**.
- `lib/pcl/gtk3.pas` is a **Pascal unit** — a real file holding `SignalConnect`.
  `uses gtk3` finds that file, not an alias.

So the two spellings a reader would take as "version 2 vs version 3 of the same
thing" are actually "a C library alias" and "a Pascal source file". Renaming
without fixing that just moves the confusion.

**Blast radius, and it is small and visible:** three files use `uses gtk` and
flip from GTK 2 to GTK 3 — `test/test_c_gtk.pas`, `test_c_gtk_call.pas`,
`test_c_gtk_types.pas`. Nothing else in the tree does.

## NilPy's tk is NOT affected — checked, not assumed

`lib/pcl/tk.pas` is a thin **Tcl/Tk 8.6** embed: it links the system Tcl/Tk
sonames directly via `external`, *"needs no -dev headers and no change to the
compiler's C-import registry"*, and the whole GUI is command strings through
`TkEval`. It never touches GTK at any version. The tkinter mimicry question is
orthogonal to this ticket.

## What is installed here, for whoever implements it

plexus has headers for `gtk-2.0` and `gtk-3.0`, and runtime libs for **2, 3 and
4**. There is **no `/usr/include/gtk-4.0`** — GTK 4's library is present, its
headers are not, so GTK 4 is unreachable until `libgtk-4-dev` is installed.

## Version selection is a SEPARATE, SCOPED feature

The owner asked for 2/3/4 selectable, defaulting to 3. The resolver half is
cheap — one variable driving the four literals above. **The widgetset half is
not**, and must not be promised with it: `gtk3widgets.pas` and friends bind GTK 3
specifically, and GTK 4 reshaped the container, event and drawing models. So
selecting a version buys the right headers and the right soname; it does **not**
make the PCL widget layer work on 2 or 4. Filed as
[[feature-a-gtk-version-selection-at-the-header-and-soname-layer]].

*Ruled 2026-08-31 by the owner; mechanism and tk backend verified by frank-user.*
