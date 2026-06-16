# Short-circuit boolean evaluation (`and` / `or`)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-14 (found while landing the asm text emitter)
- **Closed:** 2026-06-16

## Current behaviour

PXX evaluates `and` / `or` **completely** — both operands always run, no
short-circuit. Standard Pascal / FPC default (`{$B-}` in `objfpc` mode) is the
opposite: **short-circuit / lazy**, evaluating the right operand only when the
left does not already decide the result. (`{$B+}` selects complete evaluation;
there is no per-operand exception for function calls — under `$B-` the right side
simply isn't evaluated, side effects and all.)

So PXX silently diverges from FPC's default. This is a real hazard because
`compiler.pas` is compiled by **both**: a guard that relies on short-circuit —
e.g. `(Length(s) > 0) and (s[i] = c)` or `(p <> nil) and (p^.x = 1)` — works
under FPC but, under PXX, still evaluates the right operand. Most such guards
survive only by luck (indexing a non-empty string one past the end reads a valid
byte; the `and` then discards it). The failure surfaces when the right operand
**faults**: indexing an EMPTY AnsiString derefs a nil data pointer and segfaults.
See [[project_pxx_and_not_shortcircuit]].

Confirmed empirically (PXX): `if False and Bang then` runs `Bang`; `if True or
Bang then` runs `Bang`; `(p <> nil) and (p^ = 1)` with `p = nil` segfaults.

This bit the asm-text-emitter work: the FPC-built compiler compiled
`writeln(PChar(s))` fine while the PXX-built compiler segfaulted on the same
source (the emitter's `(Length(dispStr) > 0) and AsmTextIsSpace(dispStr[1])`
touched `dispStr[1]` on an empty string). Worked around locally with a
range-checked `AsmTextCharAt`.

## No viable interim guard

Forcing FPC to complete evaluation with `{$B+}` (so both builds match) was tried
and **crashes the FPC build**: `compiler.pas` itself relies on short-circuit
guards throughout (FPC default `{$B-}`), and complete-evaluating them faults the
FPC-built compiler. So `{$B+}` is off the table; the only real fix is making PXX
short-circuit. Until then, new compiler/RTL code must not lean on short-circuit
to protect a faulting right operand (nil deref, empty-string index, /0) — guard
explicitly (e.g. the `AsmTextCharAt` accessor).

Curiosity worth a glance during the fix: PXX self-hosts `compiler.pas` despite
its short-circuit-reliant guards, so those guards' right operands happen never to
fault for the values the self-compile sees — fragile, and exactly what short-
circuit would make robust.

## Scope (the fix)

1. Lower `a and b` / `a or b` with a short-circuit branch when `b` is not a
   trivially-pure leaf: evaluate `a`; for `and`, if false skip `b` (result
   false); for `or`, if true skip `b` (result true). Boolean-typed operands only
   — bitwise `and`/`or` on integers must stay full-width, unconditional.
2. Honour the `{$B+}` / `{$B-}` directives (parse + a mode flag) so source can
   opt into complete evaluation; default to `{$B-}` to match FPC.
3. Tests: a guard whose right operand has an observable side effect / would fault
   (nil deref, empty-string index, divide-by-zero) proves the right side is
   skipped; a `{$B+}` variant proves it is not. Run on every target.
4. Keep the self-host fixedpoint byte-identical (the change shifts emitted bytes
   for boolean expressions, but native↔self must still agree).

## Notes / landmines

- Distinguish boolean `and`/`or` (short-circuit candidates) from bitwise integer
  `and`/`or` (never short-circuit) at lowering time — the dialect overloads both
  on the same tokens.
- Once short-circuit lands, audit `asmtext.inc` (and anywhere else that added
  defensive `CharAt`-style guards for this) and simplify back where wanted.

## Log

- 2026-06-14 — opened. Found via the FPC-fine / PXX-segfault divergence on
  `writeln(PChar(s))` during the asm-text-emitter slice. Confirmed PXX
  complete-evaluates `and`/`or`. Tried `{$B+}` on the FPC path to force parity —
  it crashes the FPC build (compiler.pas relies on short-circuit), so reverted;
  no interim. Emitter guarded with `AsmTextCharAt`.

- 2026-06-16 — **DONE** (commit c01af32, ticket close 87946f1). Lowered logical and/or to short-circuit control flow in
  the shared IR (`ir.inc` AN_BINOP): the parser already tags a both-boolean
  and/or with `ASTTk = tyBoolean` (bitwise integer and/or keep an ordinal type),
  so lowering stores the left into a temp, branches (`and` skips right when left
  false; `or` skips when left true via a JUMP_IF_FALSE→eval-right / JUMP→end
  pair), then lowers the right operand AFTER the branch so its IR sits past the
  jump in the linear statement stream. Temp is a proc-local (recursion-safe).
  One IR change → all four targets; byte-identical on x86-64/i386/aarch64/arm32,
  cross-bootstrap self-fixedpoint still byte-identical on all 3. Self-host
  reseeded via `make bootstrap` (codegen change; +~82 KB code from the branches).
  `test_cross_shortcircuit` wired into all four suites. Scope item 2 ({$B+}
  complete-eval opt-in) deferred as a rarely-used follow-up. Landmine confirmed:
  a literal `{$B-}` inside a `{ }` comment is lexed as a directive — keep
  `{$...}` out of comments (see project_rtl_dialect_landmines).
