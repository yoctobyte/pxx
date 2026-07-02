# Stackless generator: allow `yield` inside a `case` statement

- **Type:** feature (compiler restriction lift)
- **Track:** A — `compiler/**` (generator lowering, stackless backend)
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing `feature-demo-chess` for cross-target
  (i386/aarch64/arm32/riscv32/xtensa) build viability.

## Problem

`; generator; stackless;` currently hard-rejects a `yield` that is lexically
inside a `case` statement — only `for`/`while`/`if` nesting is allowed (see
`done/feature-generators-yield.md`, the "Phase 4 (v2 stackless backend)" log
entry: "yield-in-try/case/repeat/with is a clear compile error", documented as
intentional for the initial cut, not lifted since).

Minimal repro:

```pascal
program ReproCaseYield;

function Gen(n: Integer): Integer; generator; stackless;
begin
  case n of
    1: yield 10;
    2: yield 20;
  else
    yield 99;
  end;
end;

var x: Integer;
begin
  for x in Gen(1) do
    writeln(x);
end.
```

```
$ ./pxx --target=i386 repro_case_yield.pas out
pascal26:13: error: stackless generator: yield only allowed at top level or inside for/while/if (not in this construct) ()
```

(Error is reported at the *compiler's own* source line, not the user's file
line/col — a secondary diagnostics-quality gap worth fixing alongside this.)

## Why it matters

The default (stackful) generator backend only targets x86-64
(`generator: only the x86-64 target is supported for the stackful backend (use
`stackless` for other targets)`), so **any cross-target generator use must go
through stackless**. `examples/chess/chess.pas`'s `GenMoves` — the flagship
demo's move generator — dispatches on piece kind via `case k of ... end` with
`yield` in every branch. This is an idiomatic, ordinary pattern (not managed
types, not exception-adjacent), so the `case` restriction is the first and
only wall standing between the chess demo and cross-target validation
(perft byte-identical across i386/aarch64/arm32/riscv32/xtensa is the ticket's
whole point). Likely blocks other cross-target generator code the same way.

## Scope

- Lift the `case`-nesting restriction for stackless generators: a state
  captured before entering a `case` and yielded from inside one of its
  branches should resume back into the same branch, mirroring how `if` is
  already handled.
- `try`/`repeat`/`with` nesting can stay out of scope for this ticket
  (separate, lower-priority asks) — this ticket is scoped to `case` only,
  since that's the concrete blocker found.
- Bonus (not required for the core fix, but same investigation surfaced it):
  report the *user's* file:line for stackless-generator legality errors
  instead of the compiler's own internal source line — the current message
  is actively misleading for debugging (looks like a compiler bug at first
  glance).

## Acceptance

- The repro above compiles under `--target=i386` (and the other 4 cross
  targets) and prints `10`/`20` when driven with `n=1`/`n=2`, and `99` for any
  other `n`.
- `examples/chess/chess.pas` builds under `--target=i386` /
  `aarch64` / `arm32` / `riscv32` / `xtensa` without modification (this is the
  actual validation — no chess.pas rewrite should be needed to unblock it).
- Existing stackless generator tests (`test/test_stackless_gen.pas`) stay
  green; self-host byte-identical.

## Log
- 2026-07-02 — Filed by Track B while validating `feature-demo-chess` cross-
  target buildability. Confirmed via minimal repro; not a regression, the
  restriction has been there since the v2 stackless backend landed (see
  `done/feature-generators-yield.md`). Root-caused to the single wall blocking
  chess cross-target: everything else about the demo (movegen structure, perft
  oracle, x86-64 build) already validated.
