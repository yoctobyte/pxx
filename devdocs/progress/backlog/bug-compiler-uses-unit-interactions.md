# Compiler self-build: two rough edges when `uses`-ing a real unit

- **Type:** bug (compiler robustness)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-30, wiring lib/asmcore into the compiler for the .asm frontend

Embedding the first real `uses`d library into the compiler (asmcore, for
feature-asm-mvp-frontend) surfaced two name-resolution rough edges. Both have clean
workarounds (used in compiler/asmfront.inc), so this is robustness, not a blocker.

## 1. Two-pass prescan can't resolve a `uses`-unit type as a function RESULT

A top-level `function F(...): TAsmOperand;` (TAsmOperand from a `uses`d unit) in
the included frontend was reported `undefined variable (F)` at its call site — the
prescan registers the signature before it can resolve the unit-provided return
type, so F never lands in the proc table. A plain `procedure` (no return) or a
function returning a builtin type registers fine; the same function shape works in
a small standalone program (no heavy prescan).

Workaround: return via a `var` out-param instead of a unit-typed function result.

Likely fix: order unit (`uses`) symbol loading before the main-program proc-signature
prescan, or defer return-type resolution for prescanned signatures.

## 2. Cross-unit access to a unit's global trips declare-before-use gating

Referencing `LastError` (a global in the asmcore unit) from compiler code raised
`undefined variable — it is a global declared later, declare it before use
(LastError)`. The decl-order gating (SymDeclTok vs CurBodyHdrTok) compares token
positions, but `uses`-unit tokens are appended after the main program, so any
unit global read from the main program looks "declared later".

Workaround: asmcore exposes an accessor `AsmCoreLastError` (a function call dodges
the gating); use that.

Likely fix: exempt symbols owned by a different unit (SymUnitIdx <> current) from
the token-position decl-order check — cross-unit visibility is governed by the
interface section, not source order.

## Why filed, not fixed now

The .asm frontend shipped with the workarounds and is green on self-host. These
fixes touch core name resolution + the decl-order feature; worth doing properly
under their own gate rather than inline. Both reproduce trivially (see asmfront.inc).

## Investigation (2026-07-01, item 2 attempted, reverted — could not reproduce)

Tried item 2's suggested fix exactly as described: added
`(SymUnitIdx[i] = CurrentUnitIdx)` to `FindSym`'s and `HiddenByDeclOrder`'s
decl-order-gating conditions (`compiler/symtab.inc`) so a symbol is only
gated by token position when it belongs to the SAME compilation context
(unit or main program) as the body currently being compiled. Self-host
byte-identical, full `make test` green — the change is safe on its own
terms.

**Could not reproduce the original failure to confirm the fix actually
addresses it**, despite two different attempts:

1. A plain standalone unit loaded via `-Fu` (a fresh `unit mylib` with an
   interface `var LastError: Integer` + a program referencing it from both
   the main `begin..end` block and from a nested procedure) — compiled fine
   on the **pre-fix** binary in both shapes. No decl-order error at all.
2. A `lib/rtl` unit loaded via the same auto-resolve path asmcore uses (no
   `-Fu` needed) — `uses unix; writeln(Tzseconds);` (`unix.pas`'s one
   interface-level global) — also compiled fine on the pre-fix binary, both
   directly in the program body and from inside a procedure.

Also checked whether the ORIGINAL trigger still exists in current source:
`asmcore_x64.pas`'s `LastError` is now **implementation-section only** (not
exported), so the exact repro the ticket describes (`compiler` code reading
an asmcore **interface** global directly) can no longer be constructed
without reintroducing a since-removed interface declaration — this bug's
specific trigger may have been refactored away when `LastError` was hidden
behind the `AsmCoreLastError` accessor, or the real trigger needs something
more specific than "any unit global reference from the main program" (e.g.
particular to self-hosting `compiler.pas` itself, or to how `asmcore`'s
own internal `uses` chain — `asmcore_base` -> `asmcore_x64` — interacts
with `CurrentUnitIdx`/token-append ordering, which a fresh standalone unit
doesn't replicate).

Reverted the speculative fix rather than land a change to `FindSym` (a hot,
ubiquitous, security-relevant-to-correctness function used everywhere) with
no failing test to prove it does anything, and no regression test to pin
its behavior going forward. The fix shape is still probably right if/when
someone reproduces the actual trigger — worth trying again starting from
self-hosting the compiler with a temporarily-re-exported asmcore
`LastError`, rather than a fresh standalone repro.
