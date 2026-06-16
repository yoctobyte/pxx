# Import C headers for complex libraries (glib/GTK-grade)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §2c — "the real goal")

## Motivation

Hand-written `external 'soname'` bindings (e.g. `test/gui/gtk3.pas`) hardcode the
soname and every prototype → manual versioning and drift. End state: `uses gtk;`
resolves `/usr/include/gtk-3.0/...` and derives the soname from the headers, like
`ctype` already does. Manual `external` stays as the escape hatch.

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
already true; the remaining work below is what makes it real-world-robust.

## Scope (remaining stages)

Plan: `../../developer/plan-c-header-import.md`. Stage A/B + float ABI + arg
spill done. Remaining:

- Stage C — macro soup: nested includes, function-like macros, `##` token paste,
  `#` stringification, variadic macros, attribute spellings, conditional platform
  blocks, typedef/struct/enum/pointer churn.
- Stage D — recovery; Stage E — final wiring (`uses gtk;`).
- Related C-interop gaps: struct-by-value ABI proof, out-param depth ≥ 2 beyond
  the strict trailing lift, non-integer `#define` constants, deeper callback
  signature metadata.

## Acceptance

A stock GTK3 header set imports and a GTK program builds without a hand-written
binding unit; existing simple-header imports stay green. Keep hot-path lookups
O(1) (see AGENTS.md FindCTag landmine).

## Log
- 2026-06-06 — ticket opened from todo.md §2c.
