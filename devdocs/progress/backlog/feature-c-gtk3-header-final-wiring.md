# GTK3 header import final wiring

- **Type:** feature
- **Status:** backlog
- **Track:** C (C frontend)
- **Owner:** —
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
