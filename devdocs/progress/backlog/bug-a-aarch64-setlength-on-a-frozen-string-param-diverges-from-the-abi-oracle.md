---
slug: bug-a-aarch64-setlength-on-a-frozen-string-param-diverges-from-the-abi-oracle
title: aarch64 SetLength re-derives the param-slot rule and disagrees with the oracle on IsArray
track: A
type: bug
prio: 40
status: backlog
found: 2026-08-31
found-by: frank-rust (first finding of tools/abi_oracle_lint.py)
owner: unassigned
blocked-by: []
summary: "ir_codegen_aarch64.inc:2869 decides whether a SetLength target's param slot holds a pointer with a hand-written `(Kind = skParam) and TypeIsFrozenString(TypeKind) and not IsArray`, instead of calling ABIParamSlotHoldsValueAddr. The delta is the `not IsArray`: the oracle returns True when IsArray is set, this chain returns False, so for a param that is BOTH an array and a frozen string the two disagree about whether to deref — the oracle says deref, the chain does not. NOT yet confirmed to be reachable: no repro built, and the guarding IR_LEA/SetLength path may make the combination unconstructible. Either it is reachable and aarch64 writes the length prefix to the wrong address, or it is not and the `not IsArray` is dead defensive text that should be deleted so the site can just call the oracle. Found by the linter written for bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire; it is that linter's only unmarked hit."
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
