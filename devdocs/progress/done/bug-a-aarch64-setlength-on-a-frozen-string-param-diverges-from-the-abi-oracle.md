---
slug: bug-a-aarch64-setlength-on-a-frozen-string-param-diverges-from-the-abi-oracle
title: aarch64 SetLength re-derives the param-slot rule and disagrees with the oracle on IsArray
track: A
type: bug
prio: 40
status: done
found: 2026-08-31
found-by: frank-rust (first finding of tools/abi_oracle_lint.py)
owner: frankS
blocked-by: []
summary: "FIXED 2026-08-31 (frankS). The divergence was real, LIVE, and neither of the two outcomes this ticket enumerated. `not IsArray` was wrong but arrays had nothing to do with it: the arm fires for a plain `var s: string[20]` (IsArray False, condition True) and double-dereferences, because EmitLoadVarAddrA64 has ALREADY dereferenced a by-ref param — a two-line SIGSEGV with no array anywhere. Correct condition is `not IsRef`, and the site legitimately CANNOT call the oracle: the question is what the emitter one line up already did, which a symIdx cannot express. Marked abi-divergence, baseline line retired. It also turned out to be the aarch64 face of a THREE-site bug — four symtab.inc string helpers and the i386 prologue asked the same question as `TypeKind = tyString` and missed tyFixedString/tyShortString entirely. Was: ir_codegen_aarch64.inc:2869 decides whether a SetLength target's param slot holds a pointer with a hand-written `(Kind = skParam) and TypeIsFrozenString(TypeKind) and not IsArray`, instead of calling ABIParamSlotHoldsValueAddr. The delta is the `not IsArray`: the oracle returns True when IsArray is set, this chain returns False, so for a param that is BOTH an array and a frozen string the two disagree about whether to deref — the oracle says deref, the chain does not. NOT yet confirmed to be reachable: no repro built, and the guarding IR_LEA/SetLength path may make the combination unconstructible. Either it is reachable and aarch64 writes the length prefix to the wrong address, or it is not and the `not IsArray` is dead defensive text that should be deleted so the site can just call the oracle. Found by the linter written for bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire; it is that linter's only unmarked hit."
---

# The site

`compiler/ir_codegen_aarch64.inc:2869`, inside `SetLength` on a frozen inline
string:

```pascal
EmitLoadVarAddrA64(si);              { x0 = buffer addr (or &slot for a string param) }
if (Syms[si].Kind = skParam) and TypeIsFrozenString(Syms[si].TypeKind) and
   not Syms[si].IsArray then
  EmitI32($F9400000);                { ldr x0, [x0] = P (param slot holds the pointer) }
```

That condition is verbatim the question `ABIParamSlotHoldsValueAddr` exists to
answer — *"does a PARAMETER's stack slot hold the ADDRESS OF THE VALUE?"* — and
it is answered here by hand.

# The delta, exactly

`abi.inc:69`:

```pascal
if Syms[symIdx].Kind <> skParam then Exit;              { both agree }
if Syms[symIdx].IsRef or Syms[symIdx].IsArray or
   TypeIsFrozenString(Syms[symIdx].TypeKind) or ...     { oracle: IsArray => True }
```

| `Kind=skParam`, frozen string, `IsArray` | oracle | aarch64:2869 |
| --- | --- | --- |
| False | True | True |
| **True** | **True (deref)** | **False (no deref)** |

An open-array-of-frozen-string parameter's slot holds the caller's data
pointer, so the oracle's answer is the right one and the hand chain skips a
deref — writing the 8-byte length prefix to the address of the slot rather than
to the buffer.

# What is NOT established

**No repro.** I did not build one, and the combination may be unconstructible:
the site is guarded by `IRKind[left] = IR_LEA` and by `SetLength`'s own
argument checking, which may reject an array-typed target before this line. So
this is a *divergence*, confirmed by reading, and not yet a confirmed *defect*.

Both outcomes are worth the same small amount of work and neither leaves the
line as it is:

- **Reachable** → aarch64 miscompiles it, and the fix is to call the oracle.
- **Unreachable** → `not IsArray` is dead defensive text whose only effect is
  to make this site disagree with the oracle in the linter's eyes; delete it
  and call the oracle, which is one line and removes the copy.

Note the twins do NOT have this shape: riscv32, xtensa and x86-64 reach the
same decision through arms that depend on `InLValueWrite` (marked
`abi-divergence:`, since the oracle's signature cannot see write context).
aarch64 is alone in re-deriving a question the oracle answers with no such
excuse — which is what makes it the interesting hit rather than noise.

# How it was found

`tools/abi_oracle_lint.py`, on its first real run. Baseline 78 raw hits →
22 after narrowing to parameter questions → 6 after exempting
`EmitParamSpillsForTarget` (which asks slot WIDTH, a question the oracle does
not answer) → 1 after marking five sites whose divergence is real and stated.
This is that 1.


---

# Resolution (frankS, 2026-08-31) — a third outcome

The ticket enumerated two, and said neither leaves the line as it is. It was
right about that and wrong about both branches.

**Reachable, trivially, and with no array in sight.**

```pascal
type TS = string[20];
procedure P(var s: TS); begin SetLength(s, 3); WriteLn(Length(s)); end;
```

SIGSEGV on aarch64. `IsArray` is False here, so `not IsArray` is TRUE and the
arm fires — and `EmitLoadVarAddrA64` has *already* emitted `ldr x0, [x9]` for a
by-ref param, so the extra `ldr x0, [x0]` is a second dereference. The array
case the ticket reasoned about was a distraction; the bug was in the half the
condition was letting through.

**And it cannot call the oracle, so branch (b) was wrong too.**
`ABIParamSlotHoldsValueAddr` answers *does this param's slot hold the value's
address?* — True for every frozen-string param, by-ref or not. The question at
this site is *has the emitter one line above already consumed that fact?*, which
a `symIdx` cannot express. Correct condition: `not Syms[si].IsRef`. Site now
carries an `abi-divergence:` marker whose stated reason is true **of this arm**
(the failure mode of the four original markers, one of which was written for its
neighbour), and `tools/abi_oracle_lint.baseline`'s entry is deleted — the
linter's stale-entry error is what told me to delete it, working as designed.

## The bigger finding: it is one bug in THREE places

Chasing the aarch64 repro turned up the same narrow predicate twice more, and
the aarch64 one is the *least* severe of the three:

| site | wrote | effect |
| --- | --- | --- |
| `symtab.inc` × 4 (`EmitStoreStrLen`, `EmitLoadStrLen`, `EmitLeaStrDataRdi/Rsi`) | `TypeKind = tyString` | **x86-64: `SetLength` writes the length OVER the parameter slot**, destroying the pointer; next `Length()` derefs 3 → SIGSEGV |
| `ir_codegen.inc:1258` (i386 prologue) | `TypeKind in [tyString, …]` | i386 **REFUSED** a by-value `string[20]` param — "only ordinal/pointer parameters supported yet", which reads like a target limitation and is not one |
| `ir_codegen_aarch64.inc` | `not IsArray` | aarch64 double-deref on a `var` one |

`TypeIsFrozenString` exists precisely to be the one answer — its own comment
says *"widen existing `= tyString` codegen checks to this predicate"* — and
these three were missed. `string[20]` is `tyFixedString`, `ShortString` is
`tyShortString`; only the legacy overloaded `tyString` matched. **i386 and
arm32 were correct throughout**, which is what made it findable at all: four
backends, two right.

A **local** frozen string is correct everywhere. Only the PARAMETER arms were
narrow, in all three places, which is why nothing caught it.

## Evidence

`test/test_frozen_string_param_setlength.pas`, wired into `test-core`,
`test-i386`, `test-aarch64` and `test-arm32`. By-value *and* by-ref, because
they fail on different targets — a test with only one of them passes on one of
the two broken backends. Byte-identical to FPC. **Positive control:** `pinned`
compiles it and SIGSEGVs at the first by-value row.

riscv32 and xtensa cannot run it: `SetLength` (builtin 101) is unimplemented in
their bare-metal stage 1. An honest compile-time refusal, not a wrong value, and
unrelated.

## Log
- 2026-08-31 — fixed; three sites widened to `TypeIsFrozenString`, aarch64's
  condition corrected to `not IsRef` and marked, baseline entry retired.
