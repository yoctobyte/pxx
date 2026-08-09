---
track: A
prio: 55
type: bug
blocked-by: []
status: done
---

# A by-value `set` or `string[N]` parameter aliases the caller's variable

- **Type:** bug (Pascal parameter passing; silent wrong value) — **Track A**
- **Found:** 2026-08-09, first measurement taken while starting
  [[feature-a-abi-oracle]] — before designing the oracle, diff what the five
  backends actually DO today against FPC.

```pascal
procedure MutSet(s: TSet);   begin s := s + [7]; end;      { s is BY VALUE }
procedure MutStr(s: TStr20); begin s := 'changed'; end;

s := [3];    MutSet(s);   { FPC: caller's s unchanged.  pxx: s now contains 7 }
t := 'orig'; MutStr(t);   { FPC: 'orig'.                pxx: 'changed'        }
```

Silent — no error, no crash, the caller's variable simply changes.

| target | `set` value param | `string[N]` value param |
| --- | --- | --- |
| x86-64 | **LEAK** | **changed** |
| aarch64 | **LEAK** | **changed** |
| arm32 | **LEAK** | **changed** |
| riscv32 | ok | ok |
| i386 | n/a — refuses these param kinds ("only ordinal/pointer parameters supported yet") |

Correct already, and verified as controls: record, variant, fixed array,
AnsiString, and a record CONTAINING a shortstring.

## This corrects [[bug-a-param-pointer-rule-divergence]]

That ticket tabulated the same three-versus-two split — the backends whose
"param slot holds a pointer" rule lists `tySet` versus the ones that omit it —
predicted a set param would misbehave, tested it, and concluded **LATENT, not a
live miscompile**. The probe was `if 3 in s`, which only READS the set. Writing
to the parameter reaches the path, and the prediction was right after all. The
same split governs `string[N]`.

So: the divergence is live, and the target that OMITS the clause is the one that
matches FPC.

## Fix

Caller-side, in `IRLowerCallArg` — the one funnel every call goes through, and
the same place and reasoning as
[[bug-a-open-array-value-parameter-aliases-instead-of-copying]], the previous
parameter kind to be missing its copy. A by-value, non-`const` set or
frozen-string argument is copied into a hidden temp and the temp is passed. It
is spelled as an ordinary `tmp := arg` assignment lowered through the normal
path, which already knows how to copy both kinds, so there is no second copy
mechanism to drift.

Target-neutral by construction: the callee gets a temp to scribble on whichever
convention its backend uses for the slot, which is why riscv32 — already
correct — is unaffected.

`const` is the escape hatch, exactly as for open arrays.

## Two things the measurement caught that reasoning would not have

1. **`ProcParamExplicitByRef`, not `IsRef`.** A frozen-string VALUE param
   carries `IsRef` anyway (the ABI passes its slot by reference), so keying on
   `IsRef` fixed the set half and left the string half aliasing.
2. **Match the frozen kinds by SHAPE, not exact kind.** A `string[20]`
   VARIABLE's node carries the legacy alias `tyString` (4) while the PARAMETER
   carries `tyFixedString` (26) — two spellings of one thing, mid-migration. An
   exact-kind equality test compiled clean and silently never fired.

## Verified

`test/test_set_shortstring_value_param_copies.pas` — 13 rows, byte-identical to
FPC's output: both leaking kinds, `ShortString`, the five control kinds, `var`
write-back still working, the `const` escape hatch, and forwarding (`Outer(s)`
calling `Inner(s)` must give Inner its own copy too).
Run cross as well: x86-64 / aarch64 / arm32 all now match FPC, riscv32 unchanged.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit 7d7bdad29.
