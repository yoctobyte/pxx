---
prio: 60  # auto
---

# feature: PXX Basic — own free-form BASIC dialect (real demo target, not an esoteric probe)

- **Type:** feature (Track A — `compiler/blexer.inc`/`bparser.inc`, `lib/` RTL bits as needed)
- **Status:** backlog — already exists in skeleton form, blocked on a real bug
- **Owner:** —
- **Opened:** 2026-07-05 (user idea: "we're totally free to do as we see fit,
  there are no standards, just intentions — wild demo")

## What this is, and how it's different from the esoteric-probe category

**Not** part of [[feature-esoteric-frontend-probes]] — that category is
explicitly capped at "skeleton only, stop at trivial, success = bug found or
clean pass, never chase usability." PXX Basic is the opposite intent: an
actual, finished, fun, demo-worthy dialect that's ours to shape however we
want, no spec to match, no BASIC standard body to satisfy. Same spirit as
Nil-Python (PXX's own take on a Python-like surface, not CPython-compatible) —
BASIC gets the same treatment.

## What already exists (confirmed by reading the tree, not assumed)

`compiler/blexer.inc` (249 lines) + `compiler/bparser.inc` (378 lines) already
implement a real, already-blended dialect:
- Classic line-numbered style (`10 PRINT "hi"`, `GOTO`/`GOSUB`/`RETURN`) *and*
  modern numberless style (`FOR i = 1 TO 10 STEP 2` / `NEXT i`,
  `WHILE`/`WEND`) accepted in the **same program**, freely mixed. Already a
  deliberately non-standard choice — no real BASIC dialect does this.
- `USES my_pas_lib` / `USES my_c_lib` — BASIC code calling real Pascal and C
  functions directly, per `test/test_basic_comprehensive.bas` (already
  written, already exercises this).
- `test/test_basic_lexer.bas`, `test/test_basic_comprehensive.bas`,
  `test/my_pas_lib.pas`, `test/my_c_lib.c` — test fixtures already in the tree.

Docs already mention it exists: `docs/targets/cross-languages.md` lists `.bas`
as "BASIC, experimental" in the frontend-by-suffix table — but nothing beyond
that one line, and no progress ticket existed for it until this one.

## What's blocking it right now

[[bug-basic-goto-gosub-halts-program]] — `GOTO`/`GOSUB` are lexed straight to
`tkHalt` (stub/placeholder token reuse, looks unfinished rather than
intentional), so any program using classic line-numbered control flow silently
halts instead of running. This has to land first — it's not a "make it nicer"
gap, it's "half the dialect doesn't execute."

## Scope ideas (not committed, brainstorm-tier — refine when picked up)

- Fix the GOTO/GOSUB/RETURN bug first (see above).
- Decide how far to lean into "free-form, no standard" as a feature rather
  than an accident: e.g. keep the deliberate classic+modern blend, maybe add
  PXX-specific flourishes (a REPL mode reusing the `examples/lisp` REPL
  pattern? direct access to any PXX RTL/PCL unit via `USES`, not just
  hand-written demo shims?).
- A demo program written to show off the mixed-style + cross-language-import
  angle specifically — that combination (line numbers *and* modern loops *and*
  calling real Pascal/C) is the actual novelty worth showing, not "yet another
  BASIC."
- Consider whether this belongs under `examples/` (a demo, Track B) once the
  frontend itself (Track A) is solid, mirroring how the C/Nil-Python frontends
  split from their demo programs.

## Acceptance (loose — this is a demo/fun target, not a strict spec)

`test/test_basic_comprehensive.bas` runs end-to-end and prints everything it
claims to (currently silently truncates after ~1 line, see the blocking bug).
Beyond that: "is it a fun demo" is the real bar, not a formal conformance
suite — no BASIC standard to satisfy, by design.

## Log
- 2026-07-05 — filed from a user brainstorm; found the frontend already exists
  (untracked) and already has personality (mixed dialect + cross-language
  import), but is blocked by a real GOTO/GOSUB bug filed separately as
  [[bug-basic-goto-gosub-halts-program]].
