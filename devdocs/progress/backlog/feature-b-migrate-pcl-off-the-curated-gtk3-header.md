---
track: B
prio: 45
type: feature
blocked-by: []
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
