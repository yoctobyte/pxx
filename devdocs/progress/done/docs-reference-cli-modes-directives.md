---
summary: "Reference docs incomplete: cli.md lists ~26 of the compiler's 37 --flags, there is no compiler-modes/strictness page (lax -> --strict -> granular -> --mimic-fpc), and no {$...} directive reference — three linked reference gaps"
type: feature
track: D
prio: 40
---

# Reference: complete the CLI flags, add a modes/strictness page, add a directive reference

- **Track:** D (docs — `docs/reference/**`, `docs/language/**`). Prose only; no
  `compiler/**` or `lib/**` edits. Verify every documented flag/directive by
  compiling against `$(PXX_STABLE)` — do not invent behaviour.
- **Found:** 2026-07-15, auditing the reference section. Three distinct but
  tightly-linked gaps; one ticket because they cross-reference each other
  (cli.md should deep-link the modes page; the modes page and the directive
  reference overlap on `{$mode}` / `{$MIMIC}`). Split into three if an agent
  prefers — they are independently shippable in the order below.

## Ground truth (verified against the source at time of filing)

The compiler recognises **37 `--` long flags** (grepped from `compiler/**`):

```
--auto-locals --debug --dump-cpp --dump-ir --dump-rtti --emit-obj
--experimental-ir-codegen --lax-decl-order --measure-inline --measure-regcall
--mimic-fpc --no-auto-var --no-default-rtl --no-div-check --no-lazy-var
--no-signals --nostdinc --no-strict-ir --no-unhandled-handler
--permissive-overload --proc-map --require-forward --selftest --shared --strict
--strict-case --strict-ir --strict-operator --strict-overload
--strict-visibility --system-libs --threadsafe --warn-missed-fold
--warn-self-result --werror --xtensa-fpu --xtensa-soft-divide
```

plus the short/`-`-prefixed forms (`-g`, `-d`, target/output selectors, etc.).
`docs/reference/cli.md` documents roughly two-thirds of these.

## 1. Complete the CLI flag reference (`docs/reference/cli.md`)

Bring cli.md up to the full recognised set. **Do not blindly dump all 37** —
triage first, because several are internal/dev-only and documenting them as
user-facing would mislead:

- **User-facing, currently missing** (the valuable half): `--strict`,
  `--strict-case`, `--strict-operator`, `--strict-visibility`,
  `--strict-ir` / `--no-strict-ir`, `--require-forward`, `--lax-decl-order`,
  `--no-default-rtl`, `--no-div-check`, `--no-signals`, `--auto-locals`,
  `--no-unhandled-handler`, `--xtensa-soft-divide`, `--experimental-ir-codegen`.
- **Already in cli.md** (the user's first-pass list flagged a few of these as
  missing — reconcile, do not duplicate): `--nostdinc`, `--shared`,
  `--system-libs`, `--xtensa-fpu`, `--mimic-fpc`, `--permissive-overload`,
  `--strict-overload`, `--threadsafe`, `--no-auto-var`, `--no-lazy-var`,
  `--dump-ir`, `--dump-rtti`, `--emit-obj`, `--debug`.
- **Internal / dev / measurement — decide explicitly**, then either omit or put
  under a clearly-marked "diagnostics / internal" subsection, never mixed with
  the user flags: `--dump-cpp`, `--proc-map`, `--selftest`, `--measure-inline`,
  `--measure-regcall`, `--warn-missed-fold`, `--warn-self-result`, `--werror`.

For each user-facing flag: one line of what it does + default + (where relevant)
the directive equivalent, cross-linked to the modes page (#2). Confirm the exact
spelling and behaviour by running `pxx --help` / compiling a probe — the grep
above is the recognised set, not a promise about semantics.

## 2. New page: compiler modes & strictness (`docs/reference/modes.md` or `docs/language/`)

Nothing today explains the model as a whole — only `fpc-compatibility.md`, and it
only touches `--mimic-fpc`. Write the conceptual page that the strict flags in #1
deep-link to instead of each explaining the model from scratch. The model:

- **lax by default** — PXX's own dialect is deliberately permissive (declaration
  order, visibility, operator/overload resolution, IR checks all relaxed).
- **`--strict` umbrella** — turns the family on together.
- **granular switches** — `--strict-case`, `--strict-operator`,
  `--strict-visibility`, `--strict-ir`, `--strict-overload`, `--require-forward`,
  `--lax-decl-order` (the opt-*out*), each independently toggleable, for turning
  one rule on/off without the whole umbrella.
- **`--mimic-fpc`** — the reference-compatibility preset (how it relates to the
  strict family: overlap, what it adds beyond strictness). Link out to
  `fpc-compatibility.md` for the FPC-specific details rather than repeating them.

This is the natural deep-link target the whole strictness story has been
missing. Keep the CLAUDE.md claims-discipline in mind if any parity wording is
used (the two different "byte-identical" senses).

## 3. New page: compiler directives reference (`docs/reference/directives.md`)

`{$mode objfpc}`, `{$MIMIC FPC}`, `{$I+}`/`{$I-}`, `{$ifdef}`/`{$if}`/`{$define}`,
range/overflow toggles, include, etc. are scattered across pages with no single
`{$...}` reference. Collect the recognised directive set into one table:
directive, argument(s), what it does, default, and the CLI-flag equivalent where
one exists (cross-link to #1 and #2 — e.g. `{$MIMIC FPC}` <-> `--mimic-fpc`,
`{$I-}` <-> IO-checking). Enumerate the recognised directives from the source
(`lexer.inc` / wherever `{$` is handled) so the list is complete, not anecdotal;
verify each by compiling a probe.

## Why it matters

The strict/mimic machinery is a real, shipped feature with **no discoverable
entry point** — a user cannot find `--strict` or learn the lax→strict→mimic
model from the docs at all, only from the source. #2 is the highest-value piece
(it turns an invisible feature into a documented one); #1 makes the flags
findable; #3 does the same for the `{$...}` surface. Low urgency, high
completeness value.

## Acceptance

- `docs/reference/cli.md` covers every user-facing recognised flag, internal
  flags either omitted or clearly segregated, each cross-linked to the modes
  page where relevant.
- A modes/strictness page exists explaining lax -> `--strict` -> granular ->
  `--mimic-fpc` as one model, deep-linked from cli.md and from the strict flags.
- A `{$...}` directive reference page exists, complete against the source, with
  CLI-equivalent cross-links.
- Every flag/directive/snippet documented was verified by compiling against
  `$(PXX_STABLE)` — no invented behaviour.

## Log
- 2026-07-15 — resolved, commit 05b0cdcd.
