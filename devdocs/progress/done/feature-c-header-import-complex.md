# Import C headers for complex libraries (glib/GTK-grade)

- **Type:** feature
- **Status:** done
- **Track:** C (C frontend)
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §2c — "the real goal")
- **Closed:** 2026-06-29

## Motivation

Hand-written `external 'soname'` bindings hardcode the soname and every
prototype → manual versioning and drift. This ticket covers the importer
hardening needed to ingest real macro-heavy system headers directly. Manual
`external` stays as the escape hatch.

## Architectural framing (2026-06-16)

This is NOT "shell out to a C toolchain / pkg-config and parse its output." PXX is
already a **self-contained, all-in-memory C+Pascal compiler + assembler + linker**:
it has a full C frontend (`clexer/cparser/cpreproc.inc`, compiles `.c` directly),
its own ELF writer (`elfwriter.inc`) and per-target encoders, and shells out to
**nothing** — no `as`/`ld`/`gcc`, no temp `.o` files. The self-hosted runtime has
**no `execve`** (project_c_header_import_arc), so an external toolchain isn't even
an option — in-process is mandatory.

So the goal is to **harden PXX's own in-process C compiler to real-header grade**
(eat GTK/glib macro soup directly), and to expose a **unified driver**: feed it C
and Pascal, it crafts objects and links in one in-memory pass, no intermediate
files. Standalone single binary, no toolchain to install, no disk churn — the
file-based C toolchain was an artifact of 1970s memory limits we no longer have.
This is finishing/extending the existing architecture, not rebuilding it.

The "ideally PXX is also a full C compiler + assembler + linker" vision is largely
already true; this ticket hardened the header importer enough for real-world
macro-soup system headers.

## Scope Completed

Plan: `../../developer/plan-c-header-import.md`. Stage A/B + float ABI + arg
spill were already done; later C work completed enough of Stage C/D for real
GTK/glib-grade headers:

- Nested includes and host include fallbacks for GTK/glib dependency forests.
- Function-like macro expansion and recursive rescan for the GObject macro
  patterns that occur in real headers.
- GCC/GObject attributes and qualifier spellings are stripped or applied where
  ABI-relevant (`packed`, `aligned(N)`).
- Typedef/struct/union/enum/pointer churn is tolerant enough to keep usable
  declarations and constants while skipping unmodelled noise.
- Dynamic library mapping resolves imported GTK2 symbols to
  `libgtk-x11-2.0.so.0`.

## Acceptance

Real GTK/glib-grade headers import and a GTK program builds without a
hand-written binding unit for that header surface; existing simple-header
imports stay green. Keep hot-path lookups bounded enough for huge headers.

Concrete gate:

- `test/test_c_gtk.pas` imports `uses gtk`, which resolves to the installed
  `/usr/include/gtk-2.0/gtk/gtk.h` on the current system and registers 13,588
  procedures.
- `test/test_c_gtk_call.pas` imports the same header set, links dynamically, and
  calls `gtk_init`.
- `test/test_c_gtk_types.pas` imports the same header set and creates a GTK
  window pointer under Xvfb.

The old GTK3/PCL end-state (`lib/pcl/gtk3.pas` using stock GTK3 headers instead
of curated `gtk3_c.h`) remains a narrower follow-up:
`feature-c-gtk3-header-final-wiring`.

## Log
- 2026-06-06 — ticket opened from todo.md §2c.
- 2026-06-29 — DONE. Verified the broad system-header GTK import path:
  `./compiler/pascal26 test/test_c_gtk.pas /tmp/test_c_gtk26` registered 13,588
  procs and ran; `test_c_gtk_call.pas` called `gtk_init`; `test_c_gtk_types.pas`
  ran under `xvfb-run -a`. Remaining GTK3/PCL curated-header replacement split to
  `feature-c-gtk3-header-final-wiring`.
