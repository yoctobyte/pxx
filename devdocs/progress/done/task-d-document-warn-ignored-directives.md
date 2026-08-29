---
summary: "New --warn-ignored-directives flag needs a row in docs/reference/cli.md, and the routine-directive table in docs/language/dialect.md should point at it as the way to find out which markers are inert"
type: task
track: D
prio: 20
status: done
owner: frankD
---

# Document `--warn-ignored-directives`

- **Type:** task — docs. **Track D** (Track A shipped the flag but does not
  edit `docs/**`).
- **Opened:** 2026-08-05
- **From:** [[feature-pascal-warn-on-unfulfillable-directive]] (Track P, done).

## What landed

A routine directive that is accepted and then silently dropped now reports
itself, with the reason, under an opt-in flag. Default behaviour is unchanged
and silent.

```
$ pascal26 -O2 --warn-ignored-directives x.pas x
x.pas:2: warning: directive 'cdecl' ignored here: the calling convention is the
  target's and is not selectable per routine, so P already uses it; the marker
  is documentation only
x.pas:4: warning: directive 'iram' ignored here: IRAM placement exists on the
  ESP targets (xtensa, riscv32) only; this target has no separate instruction
  RAM to place R in
x.pas:6: warning: directive 'inline' ignored here: the inliner takes at most six
  by-value scalar parameters and Big has 7
```

Covers `cdecl`, `register`, `iram` off the ESP targets, `stackful`,
`reintroduce`, and `inline` when the routine cannot be inlined. Hint directives
(`deprecated`/`platform`/…) are deliberately excluded — they are meant to be
inert until usage warnings exist, and warning on them would fire on ordinary
FPC source.

## Two edits

1. **`docs/reference/cli.md`** — a row next to `--warn-uses-leak` (same
   opt-in-diagnostic family):

   | `--warn-ignored-directives` | Report a routine directive that is accepted but cannot be honored, with the reason. Diagnostic only — codegen is unchanged. |

2. **`docs/language/dialect.md#routine-directives`** — that table already
   splits directives into load-bearing / accepted-and-ignored / rejected. The
   "accepted and ignored" group should say that this flag names them at the
   point of use, which is the difference between a reader having to consult the
   table and the compiler telling them.

## Note on the `inline` reasons

The flag reports only causes knowable at the declaration: optimisation level,
procedure-vs-function, assembler/generator/async/stackless, and more than six
parameters. It does **not** claim "your body is too complex" — the body has not
been parsed at that point, and the ticket's whole premise was that the compiler
should not assert things it has not established. Worth a sentence if the docs
describe the flag's coverage, so nobody reads silence as "this will inline".

## Gate

Both pages build and the flag name matches the implementation exactly
(`--warn-ignored-directives`).

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Both edits, plus one the ticket did not ask for and should have.

### The bigger edit: `dialect.md` was still advertising this as a known gap

`docs/language/dialect.md` carried a section titled **"On unfulfillable
directives"** whose whole content was:

> PXX does not currently warn when a directive is accepted but cannot be honored
> — `iram` on x86-64 compiles silently. Only `interrupt` errors. A uniform
> "this directive is ignored here" diagnostic is a known gap.

That gap is exactly what this flag closed. The page was telling readers the
feature does not exist. Replaced with **"Finding out which ones are inert here:
`--warn-ignored-directives`"** — the worked example, the coverage list, the
hint-directive exclusion and why, the `inline` caveat, and `interrupt` kept as
the one directive that errors rather than warns. The accepted-and-ignored table
now opens with a pointer to it: *ask the compiler rather than consulting this
table*.

Finding this was luck of the draw — the ticket named the section by anchor
(`#routine-directives`) and asked only for a pointer sentence, so reading the
whole section was what turned up the stale paragraph three headings below.

### `cli.md`

The row went beside `--warn-uses-leak` as the ticket specified — but that
section's preamble said *"These serve compiler development and self-inspection,
not normal builds. Use them only when directed"*, which is wrong for a flag
aimed at ordinary source. Split it: the `--warn-*` family is opt-in diagnostics
you can run against your own code and none of them changes what is compiled; the
dump/measure flags below are the compiler-development ones. That is accurate for
every existing row too.

### One quote corrected — the ticket's own example misstates the prefix

The ticket renders the warnings as `x.pas:2: warning: …`. The compiler prints
**`pascal26:3:`** — its own name, not the source file's. I had copied the
ticket's form before checking; caught by the usual string-compare. The page now
shows the **source and its real output together**, which makes the whole example
verifiable rather than illustrative: the published Pascal block was extracted
from the rendered Markdown, compiled, and its three warnings diffed line-for-line
against the published output block — **exact match on all three**.

### Verified — pinned v393, no rebuild

- the flag reports all three cases (`cdecl`, `iram`, `inline` with 7 params) with
  the reasons the page quotes;
- **default is silent**: the same program with no flag emits zero warnings, so
  "default behaviour is unchanged" is measured rather than repeated;
- the flag name matches the implementation exactly, as the Gate required.

The `inline` caveat the ticket asked for is in, in its own paragraph: the flag
reports only causes knowable at the declaration, never "your body is too
complex", so silence about a routine is **not** a promise that it will be
inlined.
