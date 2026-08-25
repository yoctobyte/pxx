---
summary: "New --warn-ignored-directives flag needs a row in docs/reference/cli.md, and the routine-directive table in docs/language/dialect.md should point at it as the way to find out which markers are inert"
type: task
track: D
prio: 20
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
