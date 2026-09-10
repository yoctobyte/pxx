---
slug: bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type
track: A
prio: 70
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [core, symtab, record-layout, silent-wrong-answer, self-host]
blocked-by: []
summary: "`IsRecordType` (compiler/symtab.inc:2890) maps FOURTEEN type names to builtin rec ids by string compare, before it ever consults user-declared records. So `type TProc = record A: array[0..99] of Int64 end` in an ordinary user program silently gets the COMPILER'S OWN TProc layout -- SizeOf 1344 where the declaration says 800 -- with no error and no warning. All fourteen reproduce; two controls (TMyClass, which has a REC_ constant but is not in the chain, and TZZZControl) are correct. TProc and TSymbol are ordinary names in real Pascal (Delphi ships a TProc), so this is a silent wrong-layout bug reachable by correct code that never mentions the compiler."
---

# Repro — 5 lines, no compiler rebuild

```pascal
program lk;
type TProc = record A: array[0..99] of Int64; end;
begin WriteLn(SizeOf(TProc)); end.
```

Prints **1344**. Rename the type to `TProcZZZ` and it prints **800**, which is
correct. Nothing is reported either way.

# The population is exact, not sampled

`IsRecordType` is a flat `if/else if` chain of string compares that returns a
builtin rec id and only falls through to `FindUClass` (the user's own records)
when none matched. Every name in the chain, measured with the same 800-byte
declaration:

| name | SizeOf | | name | SizeOf |
| --- | --- | --- | --- | --- |
| TToken | 32 | | TTemplate | 32 |
| TStrEntry | 24 | | TSpecialization | 32 |
| TFixup | 16 | | TGenericFunc | 40 |
| TGlobFix | 16 | | TPendingGFSpec | 32 |
| TCallFix | 16 | | TMethodFixup | 8 |
| TSymbol | 104 | | TParam | 40 |
| TProc | 1344 | | TRawToken | 40 |

Controls, both correct at 800: **TMyClass** — `REC_TMYCLASS = 10` exists as a
constant but the name is NOT in the chain, so having a rec id is not what does
it, the string compare is — and **TZZZControl**, an unrelated name.

# Why it was worth chasing

It is the actual reason `MAX_PROC_PARAMS` cannot be raised, which had been
filed twice with two wrong mechanisms (a "const-expr gap", then "a record
field's array bound is ignored"). Neither is real. `defs.inc`'s
`TProc = record ... Params : array[0..31] of TParam ... end` **is not what lays
TProc out** — the declaration resolves to `REC_TPROC` and the builtin layout
wins, so editing that bound changes nothing. That is why `array[0..31]`,
`array[0..63]` and `array[0..255]` all emit identical code/data/bss/procs while
producing three different binaries: the bound reaches bounds-check code and
never reaches the field offsets.

Raising `MAX_PROC_PARAMS` therefore widens every staging array and leaves the
destination at 32 slots, and `RegisterProc` writes `Params[32]` past the
builtin record — SIGSEGV at exactly 33 parameters, from a bare `external`
declaration, both frontends. See
`bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment`.

`symtab.inc:3604` already asserts the builtin's size as
`288 + MAX_PROC_PARAMS * 296 + 32` via `CheckBuiltinRecSize`, so the builtin
layout is *supposed* to track the constant. Measured, `SizeOf(TProc)` is 1344
at `MAX_PROC_PARAMS` = 16, 32 and 64 alike, so whatever defines the offsets
does not. **Start there** — that mismatch between the assertion's formula and
the observed size is the shortest thread.

# The fork

Shadowing is presumably deliberate for self-hosting: the compiler needs known
layouts for its own records. What is not deliberate is that the chain is
consulted for **every** program, so a user type is silently replaced. Two
shapes, and this is an engineering call, not an owner one:

1. **Scope the chain** to the self-host compile (only when the unit being
   compiled is the compiler's own), letting `FindUClass` win otherwise.
2. **Consult `FindUClass` FIRST** and fall back to the builtin chain, so an
   explicit user declaration always beats the builtin.

(2) is smaller and fixes the user-visible half immediately. Neither on its own
fixes `MAX_PROC_PARAMS`, because `compiler.pas` genuinely wants the builtin —
that needs the offsets to track the constant.

# What a guard would have to observe

`CheckBuiltinRecSize` is a positive-control-shaped guard that passes today
while `SizeOf` disagrees with its own formula, so it is not reading the
quantity it appears to. Any fix should assert the DECLARED shape against the
builtin's, not the builtin against a second copy of the same number.
