---
title: Compiler modes and strictness
order: 93
---

# Compiler modes and strictness

PXX has one dialect, not several semantic modes. What changes is **how strict**
that dialect is about a handful of FPC-parity rules. This page explains the
model as a whole; the individual switches are listed on the
[command line](./cli.md) page and, for the in-source forms, on the
[directives](./directives.md) page.

## The model: lax → strict → mimic

- **Lax by default.** PXX's own dialect is deliberately permissive. Declaration
  order, member visibility, operator and overload resolution, and `case`-label
  checking are all relaxed unless you ask for the stricter behavior. This keeps
  quick programs and in-progress code compiling without ceremony.
- **`--strict` — the umbrella.** Turns on the FPC-parity strictness family
  together. Today that family is the routine-visibility check
  (`--require-forward`); the umbrella name is the stable entry point as more
  checks join it.
- **Granular switches — one rule at a time.** Each check is independently
  toggleable, so you can tighten (or loosen) exactly one rule without the whole
  umbrella:

  | Switch | What it enforces | Lax default |
  | --- | --- | --- |
  | `--require-forward` | Routine defined/declared before its call site. | Whole-source pre-scan finds it anywhere. |
  | `--strict-overload` | Explicit `overload;` on overloaded routines. | Marker not required. |
  | `--strict-operator` | Reject `=` / `<>` on class operands. | Value-equality operators allowed. |
  | `--strict-case` | Inverted-range and duplicate/overlapping `case` labels are errors. | First-match, no diagnostics. |
  | `--strict-visibility` | `private` / `protected` / `strict` access is enforced. | Markers parsed, access granted anywhere. |
  | `--lax-decl-order` | (opt-*out*) declare-before-use for forward-visible globals. | Enforced by default. |

  Each also has an in-source directive form (`{$STRICT_OVERLOAD ON}`,
  `{$STRICT_CASE ON}`, `{$DECLORDER OFF}`, …) so a source file can carry its own
  strictness need — see [directives](./directives.md).

- **`--mimic-fpc` — the compatibility preset.** For compiling FPC-oriented
  code. It installs the curated FPC define set **and** turns on the subset of
  strictness that FPC enforces in practice: `--require-forward`, IO checking
  (`{$I+}`), and `--strict-visibility`. It is a preset built *on top of* the
  strict family, not a separate mode. The in-source equivalent is `{$MIMIC FPC}`.
  For the FPC-specific details of what ports and what does not, see
  [FPC compatibility](../language/fpc-compatibility.md).

## Why lax is the default

PXX is its own dialect first and an FPC-compatibility tool second. The lax
default serves the dialect; the strict flags and `--mimic-fpc` serve
compatibility when you want it. That split is deliberate: you opt *into*
FPC-parity strictness per rule, rather than opting out of it.

Note that `{$mode objfpc}` / `-Mobjfpc` and the other FPC mode markers are
accepted as compatibility markers only — they do **not** switch PXX into a
different semantic mode. Strictness is controlled by the switches above, not by
the mode marker.

## Next

- [Command line](./cli.md)
- [Compiler directives](./directives.md)
- [FPC compatibility](../language/fpc-compatibility.md)
