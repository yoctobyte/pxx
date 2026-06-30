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
