---
prio: 55
track: C
status: done
blocked-by: [decide-which-gtk-a-bare-gtk-gtk-h-means]
summary: "Stock GTK3 headers import, link to libgtk-3.so.0 and run a real window — done and gated by test_c_gtk3_stock. The 2026-06-29 probe failure was a wrong include root, not an importer limit. Parked: dropping the explicit -I needs decide-which-gtk-a-bare-gtk-gtk-h-means, and the PCL migration is a Track B ticket."
---

# GTK3 header import final wiring

- **Type:** feature
- **Status:** done
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

## 2026-08-30 — RE-MEASURE (triage only, nothing applied): still genuine, scope reduced

Checked in the parked-ticket pass.

**Still blocked, on a Track U decision that is genuinely open:**
[[decide-which-gtk-a-bare-gtk-gtk-h-means]] is in `backlog/` (track U, p55).
Human judgment, correctly escalated, and it does not age — it stays open until
someone answers it.

**One thing has changed, in this ticket's favour.**
[[feature-b-migrate-pcl-off-the-curated-gtk3-header]] — the Track B job this
park deliberately refused to smuggle in, on the grounds that swapping the
curated header changes signatures under the whole PCL widget stack, 11 GUI
tests and 5 examples — is now in `done/`. So the largest stated *consequence* of
resolving the decision has already been absorbed by the lane that owned it.
That does not unblock the decision, but it means whoever answers it faces a
smaller blast radius than this park describes.

The remaining plumbing note stands and is a staffing call, not a blocker: it
crosses Track P's `pasparser_proc.inc` and Track C's `cpreproc.inc`, so it
"wants an owner assigned rather than a lane guessed".

**Re-priced: unchanged**, but the ticket is one Track U answer away rather than
one answer plus a Track B migration.

## 2026-09-05 (frankC, Track C) — RESOLVED: the park's blocker was answered five days ago

**Both unmet acceptance bullets are now met**, and neither needed new capability.

**1. `uses gtk3` resolves the installed set with no flag.** The blocker
[[decide-which-gtk-a-bare-gtk-gtk-h-means]] was **ruled 2026-08-31** — *"i think
gtk3 is a sane default in 2026"* — and moved to `decided/`. Nobody implemented
it: `cpreproc.inc` still said `/usr/include/gtk-2.0/` today. Landed here.
Measured: `test_c_gtk3_stock.pas` now builds **without** `-I/usr/include/gtk-3.0/`,
byte-identical output to the flagged build, and still links `libgtk-3.so.0`.

**2. `lib/pcl/gtk3.pas` off hand-redeclared prototypes** —
[[feature-b-migrate-pcl-off-the-curated-gtk3-header]], in `done/` since the
08-30 re-measure. Track B's, closed by Track B.

### The park outlived its reason by five days, and that is a mechanism

The blocker was answered and **the ticket was never moved**, so `ready` listed
this as unblocked (its `blocked-by` resolves into `decided/`) while the body
told every reader it was parked. **The ranker and the reader disagreed for five
days.** Whoever answers a decision owns unparking what it blocks, or the answer
only reaches the person who already knew.

### What actually landed

Three literals, no structural change:

| site | was | now |
| --- | --- | --- |
| `cpreproc.inc` default C root | `/usr/include/gtk-2.0/` | `/usr/include/gtk-3.0/` |
| `cpreproc.inc` arch root | `/usr/lib/x86_64-linux-gnu/gtk-2.0/include/` | **deleted** |
| `pasparser_proc.inc` alias stem for `gtk` | `gtk-x11-2.0` | `gtk-3` |
| `pasparser_proc.inc` header fallback | `/usr/include/gtk-2.0/gtk/` | `/usr/include/gtk-3.0/gtk/` |

The arch root is **deleted rather than moved**: GTK 2 needed it for
`gdkconfig.h`, and GTK 3 keeps `gdkconfig.h` inside `/usr/include/gtk-3.0/gdk/`.
So the flip also retires a hardcoded `x86_64-linux-gnu` path that was wrong on
every other host arch — which the decision ticket had flagged as a **separate**
worry. A cross-target fix falling out of a default change.

The `gtk-x11-2.0` stem is deliberately **left** in the soname map and the
system-lib set. Nothing produces it from a `uses` clause any more, but it is
still a valid stem to name explicitly, and removing a mapping because its only
caller went away is deleting code believed dead rather than verified dead.

### The decision's blast radius was wrong, in the part everyone reads

It lists **three** files flipping. **Four** do — `test/test_c_gtk_window.pas` is
missing from the ruling's list, though the sibling ticket's own body has all
four. Both frontmatter summaries carry the three. The omitted one is the only
test that runs a full `gtk_main` loop.

It also says *"those four tests never touch GTK at runtime — they compile
against `test/my_gtk.h`, a local stub."* **False in both halves.** Three of the
four call into GTK, under `xvfb-run`; and **`my_gtk.h` is an orphan** — its only
two references in the entire tree are a `writeln` string and the Makefile
asserting that string. Nothing includes it.

So **the section a taker reads to size the job is the section to distrust.**
Neither error overturns the ruling: *"gtk3 is a sane default"* is intent and
needs no evidence. The blast radius does.

### `test_c_gtk_types.pas` was always wrong and GTK 2 was lenient

It called `gtk_window_new` **without `gtk_init`**. GTK 2 allowed a window with
no display connection; GTK 3 aborts in `_gtk_css_lookup_resolve` with *"Can't
create a GtkStyleContext without a display connection"*. `test_c_gtk_window`
passed throughout because it happens to call `gtk_init` first.

`gtk_init(nil, nil)` added. **This is not a GTK 3 workaround** — GTK has always
required it — and it does not weaken the row: the subject is still that
`gtk_window_new`'s `void*` reaches a Pascal `Pointer` untruncated, which
`gtk_init` cannot supply.

*(Noted, not fixed, as out of scope: that row asserts `window <> nil`, and a
truncated pointer is usually non-nil too, so the assertion is weaker than the
defect it cites. Pre-existing; flagged rather than silently widened.)*

### Gate

`make compiler/pascal26` converged, fixedpoint `5c40f3343701`. `gate.sh quick`
**GREEN 17/17 including the FPC seed canary** — run with `compiler/**`
uncommitted, which is the only state in which that canary runs at all. All four
`uses gtk` tests build, link **`libgtk-3.so.0`** and run green under xvfb;
`test_c_gtk3_stock` green with and without its now-redundant `-I`; the PCL stack
(`test_gtk_window`, `test_pcl_helloworld`) builds and links GTK 3.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
