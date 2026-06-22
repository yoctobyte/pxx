# `WriteLn(Boolean)` prints `0`/`1` instead of `FALSE`/`TRUE`

- **Type:** bug (output formatting / FPC-compat) — Track A
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC (`writeln(1>0)` → pxx `1`, fpc `TRUE`).

## Problem

`write`/`writeln` of a Boolean value prints the integer `0`/`1`. FPC prints
`FALSE`/`TRUE`. Affects any `writeln(b)` / `writeln(x>y)` etc. Severity is
formatting, not a silent miscompile (loud divergence), but it breaks FPC-output
parity broadly.

## Why it is not a quick fix (attempted 2026-06-23, reverted)

The write path resists both obvious fixes:

1. **Per-backend codegen** — `IR_WRITE` is lowered per target. A Boolean arrives
   as an ordinal and falls through to the integer-write path in EACH backend
   (x86-64 `ir_codegen.inc`, plus `ir_codegen_{386,aarch64,arm32}.inc`; ESP
   riscv32/xtensa `write` is a bare no-op). Adding a `tyBoolean` case
   (`test; jz .false; write 'TRUE'; jmp; .false: write 'FALSE'`) is mechanical
   but must be repeated in 4 hosted backends with per-arch branch encoding, and
   the cross-output comparison tests (`make test-i386/aarch64/arm32`, which diff
   cross output against the x86-64 oracle) break unless ALL hosted backends are
   fixed together. An x86-64-only fix was implemented + verified (TRUE/FALSE,
   FPC-matched) but reverted to avoid the half-done cross inconsistency.
2. **Target-independent IR lowering** (the clean design) — lower a Boolean write
   arg in `ir.inc` `AN_WRITE` to `if b goto L1; write('FALSE'); goto L2; L1:
   write('TRUE'); L2:` using `IR_IF_GOTO`/`IR_LABEL`/`IR_JMP` + `IR_WRITE` of a
   string constant (the linear IR emitter runs them in order, so injecting them
   into the write chain works on every backend at once). BLOCKER: an `IR_WRITE`
   string literal currently keys off a RAW SOURCE token span
   (`GetTokenStrFromRaw(IRA, IRB)`), so a synthetic `'TRUE'`/`'FALSE'` (not in the
   user's source) can't be referenced directly. Needs a way to emit an
   `IR_WRITE` of an interned/synthetic string (e.g. append the two literals to
   the raw buffer at init and remember their spans, or an `IR_WRITE` variant that
   takes an interned-string index). Once that exists, this is the right fix —
   one place, all targets.

## Recommended fix

Approach 2 (target-independent IR), after adding synthetic-string-literal support
to the write path. ~8 existing test expectations encode the current `0`/`1`
output and must flip to `TRUE`/`FALSE` (FPC-correct): `test_set_runtime`,
`test_uint64_ops`, `test_conformance_1`, `test_conformance_2`,
`test_cross_global_init`, `test_variant_ops`, `test_variant_string_ops` (the
exact new strings were computed during the reverted attempt).

## Gate

`make test` + `make cross-bootstrap` + the cross-output tests
(`make test-i386/aarch64/arm32`) must stay green; FPC oracle-match the boolean
output.
