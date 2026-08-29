---
prio: 55
track: C
status: unfinished
blocked-by: [decide-which-gtk-a-bare-gtk-gtk-h-means]
summary: "Stock GTK3 headers import, link to libgtk-3.so.0 and run a real window — done and gated by test_c_gtk3_stock. The 2026-06-29 probe failure was a wrong include root, not an importer limit. Parked: dropping the explicit -I needs decide-which-gtk-a-bare-gtk-gtk-h-means, and the PCL migration is a Track B ticket."
---

# GTK3 header import final wiring

- **Type:** feature
- **Status:** unfinished (parked on decide-which-gtk-a-bare-gtk-gtk-h-means)
- **Track:** C (C frontend)
- **Owner:** frankC
- **Opened:** 2026-06-29
- **Split-from:** feature-c-header-import-complex

## Motivation

`feature-c-header-import-complex` proved that PXX can ingest real macro-heavy
GTK/glib-grade system headers through the GTK2 import path. The remaining
product-facing target is narrower: use stock GTK3 headers for the PCL GTK3
binding instead of the curated `lib/pcl/gtk3_c.h` surface.

## Scope

- Make `uses gtk` or `uses gtk3` resolve the installed GTK3 header set
  (`/usr/include/gtk-3.0/...`) with the needed transitive include roots.
- Map the imported header stem to `libgtk-3.so.0` and any required companion
  system libraries.
- Replace or bypass the curated `gtk3_c.h` binding for PCL where practical.
- Keep the existing GTK2 system-header import tests green; they are the broad
  macro-soup regression guard.

## Acceptance

- A GTK3 hello/window smoke program builds from stock GTK3 headers, not
  `lib/pcl/gtk3_c.h`.
- `lib/pcl/gtk3.pas` no longer depends on hand-redeclared GTK3 prototypes for
  the covered smoke surface.
- `test/test_c_gtk*.pas` and the GUI smoke tests remain green.

## Notes

As of 2026-06-29, a manual probe with `-I/usr/include/gtk-3.0/gtk` stops at a
missing transitive include path:

`C include file not found (/usr/lib/llvm-18/lib/clang/18/include/gtk/gtkactionable.h)`

That is an include-root/final-wiring issue, not evidence that the broad
macro-soup importer ticket should stay open.

## Worked 2026-08-29 by frankC (Track C) — capability DONE and gated; parked on a decision

### What is done

**Stock GTK3 headers work end to end.** Not "parse" — build, link to the right
library, and run:

```
./compiler/pascal26 -Futest/gtk3stock -I/usr/include/gtk-3.0/ \
    test/test_c_gtk3_stock.pas $TMP/test_c_gtk3_stock26
  ok  [code=142372B  data=4380B  bss=42492B  procs=14769]
readelf -d ... | grep libgtk-3.so.0            -> PASS
xvfb-run -a $TMP/test_c_gtk3_stock26
  Successfully created window
  Starting gtk_main loop...
  AutoQuit called from GTK main loop!
  Main loop exited cleanly
```

14,769 procs imported from the stock `/usr/include/gtk-3.0` surface. Gated by
`test/test_c_gtk3_stock.pas` + `test/gtk3stock/gtk3_c.h` (a forwarding header
that is just `#include <gtk/gtk.h>`, shadowing the curated binding via `-Fu`
without touching it), wired into the Makefile beside the existing GTK tests. The
test asserts the *version*, not merely that it links: `gtk_main`/`gtk_main_quit`
exist in both GTK2 and GTK3, so a run alone would pass against the wrong library.

**The GTK2 regression guard is untouched** — verified, not assumed:
`test_c_gtk` passes and `test_c_gtk_window` still links `libgtk-x11-2.0.so.0`
and runs clean. Both GTK versions now work side by side.

### The 2026-06-29 note in this ticket was a red herring

The recorded failure —
`C include file not found (.../clang/18/include/gtk/gtkactionable.h)` — was a
**wrong include root**, not an importer limitation. The probe passed
`-I/usr/include/gtk-3.0/gtk`, so `#include <gtk/gtkactionable.h>` had nowhere to
resolve. With `-I/usr/include/gtk-3.0/` the entire header set parses. Every other
root GTK3 needs (glib, pango, cairo, gdk-pixbuf, atk, harfbuzz, freetype2,
pixman, fontconfig) is already a default and shared with GTK2.

### Why this is parked and not resolved

Two acceptance bullets are unmet, and both are outside Track C:

- **"`uses gtk3` resolves the installed GTK3 header set"** without a flag is
  blocked on a genuine fork: `/usr/include/gtk-2.0/gtk/gtk.h` and
  `/usr/include/gtk-3.0/gtk/gtk.h` both answer to `#include <gtk/gtk.h>`, the
  system include list is flat and global, and gtk-2.0 is in it while gtk-3.0 is
  not. Whichever root goes first decides the GTK version for every C consumer at
  once. Filed as [[decide-which-gtk-a-bare-gtk-gtk-h-means]] (recommendation:
  scope the include root by the stem that already picks the soname; the plumbing
  crosses Track P's `pasparser_proc.inc` and Track C's `cpreproc.inc`, so it
  wants an owner assigned rather than a lane guessed).

- **"`lib/pcl/gtk3.pas` no longer depends on hand-redeclared prototypes"** is a
  Track B job in Track B's files: [[feature-b-migrate-pcl-off-the-curated-gtk3-header]].
  Enumerated rather than estimated — all 135 curated functions exist in the stock
  headers (gcc address-taking probe, exit 0, zero undeclared), only **3** are
  variadic where the curated file was fixed-arity (`g_signal_emit_by_name`,
  `gtk_file_chooser_dialog_new`, `gtk_message_dialog_new`, found via
  `gcc -aux-info` over 14,453 prototypes), and `PGtkWidget` — which stock GTK3
  does not have — appears in 4 files, all tests, none in `lib/pcl` or `examples`.

Deliberately NOT smuggled into this ticket: swapping the curated header changes
the signatures under the whole PCL widget stack, 11 GUI tests and 5 examples.
That is Track B's gate, not Track C's.

### Gate

`make compiler/pascal26` — converged after 2 round(s), fixedpoint verified. (No
compiler source was changed by this work: the change is a new test, its header,
and two Makefile lines.) New test and both existing GTK2 tests run green above.
