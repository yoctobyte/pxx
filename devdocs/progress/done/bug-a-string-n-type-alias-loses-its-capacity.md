---
track: A
prio: 60
type: bug
blocked-by: []
status: done
---

# A `string[N]` TYPE ALIAS loses its capacity, so nothing truncates

- **Type:** bug (silent wrong value; the FPC-semantics rule) — **Track A**
  (the fix is in the shared alias table / `ParseTypeKind`)
- **Found:** 2026-08-09, an FPC differential over the string surface.
- **Pre-existing:** identical on `pinned`.

```pascal
type TS8 = string[8];
var inl: string[8];   { INLINE spelling }
    ali: TS8;         { ALIAS spelling — the same type }

inl := 'way too long for eight';   { FPC 'way too ' 8;  pxx 'way too ' 8   ok }
ali := 'way too long for eight';   { FPC 'way too ' 8;  pxx the WHOLE 22 chars }
```

Same for a record field declared through the alias. Both compilers accept the
code, and their behaviour differs — so by the policy's first rule
([[feedback_fpc_faithful_default_dialect_switch]]: "semantics of code PXX
accepts track FPC's interpretation by default") this is a bug, not a dialect
choice, and needs no `--strict` flag.

## Cause

`RegisterGeneralAlias` records an alias's KIND and drops `LastTypeStrCap`. There
was no `AliasStrCap` field at all. Resolving `TS8` therefore produced
`tyFixedString` with no capacity, `Alloc*` stamped `SymStrCap = 0`, and
`EmitClampRcxToStrCap` fell back to `DEFAULT_STR_CAP` — a 256-char clamp on a
type the programmer declared as 8.

## Why the existing test did not catch it

`test/test_shortstring_trunc.pas` — written for
[[bug-pascal-shortstring-no-truncation-buffer-overrun]], which fixed the
truncation itself — spells **every** case inline (`a: string[4]`, and the record
field the same way). The clamp machinery it pinned was real and works; the alias
route into it was never exercised. Two spellings of one type, one of them
tested. The alias rows are now in that same file rather than a rival test.

## Not a buffer overrun, unlike its parent ticket

Measured: the neighbours survive (locals, and both fields of a record), because
the slot is over-allocated for the un-capped case. So this is a wrong VALUE and
a wrong `Length`, not memory corruption — which is also why it survived a fuzzer
campaign aimed at the overrun.

## Fix

`AliasStrCap` joins the alias table; `RegisterGeneralAlias` records
`LastTypeStrCap` when the aliased kind is a frozen string; `ParseTypeKind` hands
it back when it resolves the alias. Three lines in three files, one concept.

`TypeIsFrozenString` needed a `forward` — it is defined far below
`RegisterGeneralAlias` in `symtab.inc`, and the **FPC seed canary** in
`gate.sh quick` is what caught that (pxx itself resolves it either way).

## Verified

`test/test_shortstring_trunc.pas` extended with the alias spellings: a variable,
a record field with a guard, and concatenation. Byte-identical to FPC, and the
same output under qemu on aarch64, riscv32, i386 and arm32 — the four targets
that already run this test cross.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
