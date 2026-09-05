---
slug: feature-n-nilpy-has-no-reachable-path-to-the-sys-and-arg-intrinsics
track: N
type: feature
prio: 20
status: backlog
owner: ""
created: 2026-09-05
blocked-by: []
summary: "NilPy cannot reach sysopen/sysread/syswrite/argcount/argstr as INTRINSICS, and has not been able to for as long as anyone has measured. PyParseFactorCore held five case arms matching those as TOKENS, and every -Ord(tkXxx) construction site in pyparser.inc was inside them — so the arms were the only path, and the arms could not fire. Surfaced by deleting them (they went dead for good when 5f177b181 made the spellings soft keywords), which is the only reason this is visible at all: dead code was standing in for a missing capability. NOT a regression — nothing that used to work stopped. The open question is whether NilPy should have these at all, given a NilPy program can already declare and bind its own paramstr/paramcount (frankD measured exactly that), and Python's own idiom is sys.argv rather than a paramstr intrinsic."
---

# NilPy has no reachable path to the sys* and arg* intrinsics

- **Type:** feature (a capability gap) — Track N
- **Found:** 2026-09-05 (frankS), while deleting the dead arms that hid it
- **Compiler:** `3d613aac6251`

## What was measured

`PyParseFactorCore` carried five arms — `tkSysOpen`, `tkSysRead`, `tkSyswrite`,
`tkArgCount`, `tkArgStr` — matching those spellings as **tokens**. Two things
were true at once:

1. The arms could not fire. `5f177b181` made those spellings **soft keywords**,
   so they lex as plain `tkIdent` and the `tk` enum members survive only as
   `-Ord(tkXxx)` intrinsic call ids. Confirmed four ways that fail differently:
   frankD's dynamic probe, the 2026-09-04 reachability sweep over all 830 `.npy`
   programs, the lexer emitting no such token for either frontend, and the
   Pascal parsers already having zero such arms.
2. **Every `-Ord(tkSysOpen)` … `-Ord(tkArgStr)` construction site in
   `pyparser.inc` was inside those arms.** Five arms, five construction sites,
   all in the dead region.

So the arms were the only path to those intrinsics from NilPy, and the path was
unreachable. **NilPy has never been able to call them.**

## Why this is a ticket rather than a line in a commit

Deleting dead code is normally silent. Here it removes the **only trace** that
NilPy was ever intended to have these, and a missing fact collides with nothing:
without this ticket, the next person to ask "can NilPy call sysopen" finds no
arms, no ids, no tests and no history, and concludes it was never wanted. That
may even be right — but it should be a decision, not an absence.

## The actual question, and it may well be "no"

**Do not implement this reflexively.** Two arguments against:

- A NilPy program can already **declare and bind its own** `paramstr` /
  `paramcount` — frankD measured precisely that, and it works today
  (verified again at `3d613aac6251`: a `.npy` defining both prints `3` and `8`).
- Python's idiom is `sys.argv`, not a `ParamStr` intrinsic. NilPy is **upward
  compatible with CPython**, so adding a Pascal-shaped intrinsic is the kind of
  thing `nilpy-semantics-divergences.md` exists to keep deliberate.

The argument for is raw file I/O without the pylib layer, which is a real want on
constrained targets — but that is a *use case someone should name*, not an
inference from five arms that never ran.
