---
track: B
prio: 45
type: feature
blocked-by: []
resolved: PENDING-COMMIT
summary: "lib/pcl/gtk3_c.h hand-redeclares 135 GTK3/cairo functions with simplified types. All 135 exist in the stock headers (gcc-verified), so the migration is bounded: 3 variadic call sites and a PGtkWidget typedef used in 4 test files. Consumers are the PCL widget stack, 11 GUI tests and 5 examples."
---

# Migrate lib/pcl off the curated `gtk3_c.h`

Filed 2026-08-29 by frankC (Track C) out of
[[feature-c-gtk3-header-final-wiring]]. The compiler side is proven: stock GTK3
headers import cleanly, resolve to `libgtk-3.so.0` and run a real window — gated
by `test/test_c_gtk3_stock.pas`, whose forwarding header is literally
`#include <gtk/gtk.h>`. What remains is a **library** job in Track B's files,
which is why it is not in the Track C ticket.

## Why bother

`lib/pcl/gtk3_c.h` is 135 hand-written prototypes with deliberately simplified
types (`void*` for every object pointer, `char*` for every string) plus an
invented `typedef void* PGtkWidget`. Every one of them is an independent guess
that happens to be call-compatible. `test/test_c_gtk_window.pas` already carries
the scar in a comment: `PGtkWidget was never declared — it was silently a 4-byte
int, TRUNCATING the pointer`. Stock headers make the compiler check what is
currently trusted.

## The blast radius is smaller than it looks — measured, not estimated

**All 135 curated functions exist in the stock GTK3/cairo headers.** Verified by
compiling an address-taking probe over every name against
`pkg-config --cflags gtk+-3.0`: gcc exit 0, zero undeclared. So nothing has to be
kept behind.

The real blockers are two, and both are small:

1. **Three functions are variadic in the stock headers** where the curated file
   declared a fixed arity. Found with `gcc -aux-info` over all 14,453 emitted
   prototypes, not by reading:
   - `g_signal_emit_by_name`
   - `gtk_file_chooser_dialog_new`
   - `gtk_message_dialog_new`

   These are the actual failure a naive swap produces first
   (`no overload of gtk_message_dialog_new matches these arguments`). The curated
   header's fixed-arity forms are a deliberate simplification — see its own
   comment on `gtk_file_chooser_dialog_new` about passing a NULL terminator.

2. **`PGtkWidget` does not exist in stock GTK3** (it is `GtkWidget*`). Used in
   **4 files, all tests** — `test/test_c_gtk_window.pas`,
   `test/test_c_gtk_types.pas`, `test/gui/test_gtk_window.pas`,
   `test/gui/test_gtk_signals.pas`. **Zero uses in `lib/pcl` or `examples`.**

Constants were checked too and are all correct against the real enums
(`GTK_BUTTONS_*`, `GTK_DIALOG_*`, `GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER`,
`GTK_POLICY_*`, `CAIRO_FORMAT_*`) — nothing to fix there.

## Consumers to keep green

`lib/pcl/gtk3.pas`, `gtk3widgets.pas`, `gtk3gl.pas`, `graphics.pas`,
`glarea.pas`, `interfaces.pas`; 11 `test/gui/test_*.pas`; and
`examples/{mandelbrot,life,solitaire_gui,raytracer}` + `examples/gl/triangle.pas`.

Note `lib/pcl/gtk3.pas`'s `PC()` hands GTK a raw `Pointer` where the stock
headers want `const gchar*`; whether that still type-checks is the first thing to
try, and is not covered by the two blockers above.

## Suggested shape

Replace the body of `lib/pcl/gtk3_c.h` with `#include <gtk/gtk.h>` (keeping the
file, so the `gtk3_c` unit name and its `gtk-3` stem→soname mapping are
untouched), then fix the 3 variadic call sites and the 4 `PGtkWidget` test uses.
Build with `$(PXX_STABLE)` per Track B's gate; `make lib-test` / `demos`.

## Depends on

[[decide-which-gtk-a-bare-gtk-gtk-h-means]] — until that is settled, every
consumer needs an explicit `-I/usr/include/gtk-3.0/`, because gtk-2.0 is a
default system include root and gtk-3.0 is not. Doing this migration first would
mean threading that flag through the PCL build and every example.


## DONE (2026-08-29, frankR)

`lib/pcl/gtk3_c.h` is now `#include <gtk/gtk.h>` against the installed headers.
135 hand-written prototypes with `void*`-for-everything types are gone, and the
whole PCL widget stack, the GUI tests and the GUI examples build against the real
declarations and link `libgtk-3.so.0`.

### What the swap actually cost

Less than the ticket estimated, and in a different place.

**`gtk_file_chooser_dialog_new` was never a blocker.** It is variadic in the
stock headers, as frankC found, but pxx imports its **four** fixed parameters
(`title, parent, action, first_button_text`) and `SelectFolder` already passes
exactly four. It compiled unchanged.

**`gtk_message_dialog_new` was the only library blocker**, and its rewrite is the
one behaviour-affecting change in this migration:

```pascal
{ was }  gtk_message_dialog_new(nil, MODAL, INFO, OK, PC('%s'), PC(AText))
{ now }  dlg := gtk_message_dialog_new(nil, MODAL, INFO, OK, nil);
         esc := g_markup_escape_text(PC(AText), -1);
         gtk_message_dialog_set_markup(dlg, esc);
         g_free(esc);
```

**The escape is load-bearing and is the trap in this rewrite.** `"%s"` set the
dialog's *text*, which is literal; `set_markup` INTERPRETS Pango markup. Without
`g_markup_escape_text` a message containing `&` or `<` renders wrong or vanishes
— a silent behaviour change that no existing test would have caught, because
`test/gui/test_pcl_showmessage.pas` is **not in the suite and was already failing
at baseline** (`Runtime error 216`, identical before and after this change).
Verified instead by a direct probe of the exact sequence against real GTK3:
`a<b&c` → `a&lt;b&amp;c`, markup set, freed, dialog destroyed.

**`lib/pcl/gl_c.h` had to be cleaned up too**, which the ticket did not
anticipate. It re-declared eight GTK functions (`gtk_gl_area_*`,
`gtk_widget_get_allocated_width/height`) that the stock headers now provide, and
`examples/gl/triangle.pas` broke on the collision. They are GTK, not GL — the
comment above them already said "linked via libgtk-3.so.0" — so they were
removed and `gtk3gl.pas` now uses `gtk3_c` for them. Leaving them would have kept
one arm of exactly the hazard this ticket exists to remove: two headers declaring
the same eight functions with different types.

**`PGtkWidget` was two files, not four.** `test/test_c_gtk_window.pas` and
`test/test_c_gtk_types.pas` already used `Pointer` (they carry the scar comment).
The two that still declared it — `test/gui/test_gtk_window.pas` and
`test/gui/test_gtk_signals.pas` — are converted. Note both are **orphans**:
neither is referenced by `tools/gui_suite.sh` or the Makefile, so nothing runs
them. Worth a separate look.

`PC()`'s raw `Pointer` where the stock headers want `const gchar*` type-checks
fine — the ticket's "first thing to try" is a non-issue.

### The include root, and how this stays off the Track U fork

`GTK3_INC`, one definition in the `Makefile` and one in `tools/gui_suite.sh`,
`pkg-config --cflags-only-I gtk+-3.0` with the literal path as fallback. Nothing
depends on [[decide-which-gtk-a-bare-gtk-gtk-h-means]] being settled, and the
variable is what deletes itself if gtk-3.0 ever becomes a default include root.

**A consumer that forgets the flag gets a compile ERROR, not a silent GTK2
build** — measured: `undefined variable (gdk_event_get_button)`. State that
precisely, though: it is loud because PCL happens to call a GTK3-only function,
which is a property of today's PCL surface and not a designed guard. A PCL
consumer whose own surface is entirely GTK2-compatible would build silently
against the wrong library.

`tools/gui_suite.sh` now opens with `gtk_version_check`, which asserts
`libgtk-3.so.0` is in DT_NEEDED **and that `libgtk-x11-2.0.so.0` is not**. Per
frankC's rule: `gtk_main`, `gtk_main_quit` and most of the surface PCL uses exist
in both GTK2 and GTK3, so a suite that only compiles and runs would pass just as
happily against the wrong library.

GTK2 stays authoritative: `test_c_gtk*` use `uses gtk` (a different unit that
resolves through the default GTK2 root) and are untouched by this change.

### What is left, and why it is left

`test/gui/test_pcl_input.pas` no longer compiles, and is **deliberately not
fixed**. Its three `g_signal_emit_by_name(handle, signal, event, @handled)` calls
need the variadic tail that pxx's C import drops
([[bug-a-a-c-headers-variadic-tail-is-dropped-on-import]], filed with this work —
C mode itself calls varargs correctly, so only the import discards it). The
obvious reroute, `gtk_widget_event` / `gtk_widget_size_allocate`, is both the
compiler-appeasement workaround the platonic-code rule forbids AND worse on its
merits: the comment already in that file records that those impose a
realized-window assertion the test cannot satisfy headlessly. The platonic call
stays; the file carries a comment pointing at the ticket.

Suite delta vs baseline, measured on the same box, same pin: `gtk version` is a
new OK, `test_pcl_input` is a new FAIL, and the two pre-existing failures
(`solitaire_gui` real toplevel, `eliah_ide` compile) are unchanged. Nothing else
moved.
