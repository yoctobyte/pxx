---
track: A
prio: 45
type: bug
blocked-by: []
status: backlog
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
