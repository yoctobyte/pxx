---
track: A
prio: 45
type: bug
blocked-by: []
status: done
found-by: frankS (boundary-testing the Variant-parameter fix)
summary: "A `generator; stackless;` routine with a `var` parameter SEGFAULTS. The for-in caller stores the argument's VALUE into the instance slot, but the slot is the by-ref arm's and the step function reads it back as the caller's ADDRESS and dereferences it. Measured: `SlSet(off=48, val=0x28)` for `mm = 40`, then a deref of 40. PRE-EXISTING -- identical on the pinned compiler, so it is not from the Variant-parameter fix (0f6b627d7); it is the SIBLING of that defect in a different arm, and the same shape: the two ends disagree about whether the slot holds a value or an address."
owner: ""
---

# A `var` parameter of a stackless generator stores the value where the slot expects an address

## Repro

```pascal
program var_only; uses slgen;
function Gen(var m: Int64): Integer; generator; stackless;
begin yield m; yield m + 1; end;
var x: Integer; mm: Int64;
begin mm := 40; for x in Gen(mm) do writeln('got=', x); end.
```

```
pinned  rc=139  []
HEAD    rc=139  []
```

Both columns crash, so this predates `0f6b627d7` and is not caused by it.

## Mechanism, measured

`AssignStacklessSlots` sends a by-ref parameter to its first arm, which is
correct and documented: *"the slot persists the caller ADDRESS (one pointer
word); save/restore go through AN_SLOTADDR so the word itself is copied, never
the pointee."* `SLSaveLocals` and `SLRestoreLocals` honour that.

The CALLER does not. `ParseForInGeneratorAST` stores every argument the same
way — `GenSlSetStmt2(gIdx, off, aK)` — which evaluates the argument as a VALUE:

```
SlSet(off=48, val=0x28)      { 0x28 = 40 = the value of mm }
```

An address would be a `0x7fff...` stack pointer. The step function then reads
that word back as the caller's address and dereferences 40.

## Why it is the sibling of the Variant defect and not the same bug

`bug-a-a-stackless-generator-with-a-variant-parameter-...` was the same
disagreement in the opposite direction: there the SLOT was right (a pointer
word) and the generator treated it as a 16-byte value. Here the GENERATOR is
right (it wants a pointer word) and the CALLER supplies a value. One concept —
"does this slot hold the value or its address?" — and the two ends are answered
independently at each site, so they can disagree either way round.

That is why the two must not be closed as one: the Variant fix
(`GenMakeVariantArgTemp` + `SLVariantByRefParam`) makes the caller store an
address for VARIANT parameters specifically. It does not touch `var`.

## Likely fix, NOT verified

The caller should store the ADDRESS of the argument lvalue for any parameter
the callee treats as by-ref — `GenMakeAddrOf(aK)`, whose comment already says
it "keeps by-ref auto-deref semantics — an IsRef sym yields the caller's
address, which is what a copy source wants".

**The thing to check before doing that**, and the reason this is filed rather
than fixed: `Params[k].IsRef` is ALSO true for a `const record` parameter,
whose argument may be an expression rather than an lvalue, and there is no
address to take of a temporary that dies at the end of the statement. The
Variant fix handled its own case by MATERIALISING a local in the enclosing
function first; the same trick likely applies here, but which shapes need it
has not been established.

## Also worth checking when this is taken

Whether any NilPy generator lowers a parameter to a by-ref non-Variant. NilPy's
Variant params carry a cell and are fine, but a by-ref Int64 would hit exactly
this, and it CRASHES rather than yielding a wrong value —
`bug-a-a-nilpy-generator-fails-on-wasm32-while-three-other-targets-agree` is in
the neighbourhood.

## Not verified

- That `GenMakeAddrOf` at the six store sites is sufficient. Not attempted.
- Which by-ref parameter shapes reach the for-in generator path at all. Only
  `var m: Int64` was measured.

## 2026-09-06 (frankS) — FIXED, `ddc7e0fa5`

`PasGenArgNeedsAddr` makes the caller take the ADDRESS for every by-ref
parameter, so the word it stores is the word the slot arm already documented
itself as persisting.

**Uniform, not a scalar special case, and the reason is the thing that hid this
bug.** A RECORD argument's bare ident already evaluates to its address, which is
why `const r: TR` and `r: TR` were right by construction and only a scalar `var`
was wrong. Records now go through `AN_ADDR` and come out at the same address
they already had — measured, both record rows unchanged, no double-addressing.
Special-casing scalars would have left the caller and the callee reasoning about
representation by different rules, which is the coupling that produced this.

| shape | pinned | HEAD |
| --- | --- | --- |
| `var m: Int64`, read | `rc=139` | `40 41` |
| `var m: Int64`, mutated | `rc=139` | `41 41` |
| `const r: TR` | `11 22` | `11 22` (unchanged) |
| `r: TR` by value | `11 22` | `11 22` (unchanged) |

**The mutating row is the one a copy cannot satisfy.** A `var` parameter must
ALIAS the caller's variable, so an "address of a materialised temp" fix — which
is exactly what the Variant sibling correctly does, because a VALUE parameter
wants a copy — would still yield 41 from inside the generator and leave `mm` at
40 outside. A read-only assertion cannot tell the two fixes apart, so the test
mutates and checks the caller's variable afterwards.

frankwasm measured the same defect on wasm32 independently before the fix:
native SEGV against wasm32 `got=0`, `const` clean on both. That is the same
two-target signature the Variant bug had and it has the same explanation — the
bad address lands on something that faults on one target and not the other.

`test/test_stackless_gen_byref_param.pas` is wired into `test-core`; it fails on
the pinned compiler and passes at HEAD. `test_stackless_gen` byte-identical, the
Variant test unchanged, three NilPy generator tests still pass.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
