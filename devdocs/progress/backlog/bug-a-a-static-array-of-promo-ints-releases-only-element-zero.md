---
track: A
prio: 45
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frankA (the cleanup half of bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice)
summary: "EmitManagedLocalCleanup's promo-int arm calls PXXPromoClear on the slot ADDRESS with no IsArray test, so a `array[0..N] of promoint64` local releases element 0 and leaks the heap-tier payload of elements 1..N. Exactly bug-a-local-static-array-of-string-never-released-at-scope-exit, one type over: that ticket's own comment says the scalar arm 'released element 0 ONLY -- the other N leaked, silently and linearly'. The INIT half of this same missing IsArray is fixed; this is the release half."
---

# A static array of promo ints releases only element 0

Split out of
[[bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice]],
which fixed the **init** half of one missing `IsArray` and measured this as the
other half of the same omission.

## The asymmetry

`compiler/symtab.inc:10792`:

```pascal
else if TypeIsPromoInt(Syms[i].TypeKind) then
begin
  procIdx := FindProc('PXXPromoClear');
  ...
  x64_lea_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);  { rdi = slot addr }
  EmitCallProc(procIdx);
end
```

No `IsArray` test, and the address passed is the array's base — so for
`a: array[0..3] of promoint64` exactly **one** element is cleared. Elements
1..N keep a heap-tier payload that nothing ever releases.

## Why it is a leak now and was a use-after-free an hour ago

The **init** side had the same missing `IsArray`, so the array was zeroed not at
all and element 0 was cleared from *stack garbage* — `PXXPromoClear` releases
the payload as a managed string whenever the tag reads `PROMO_TAG_HEAP`, and
its own header says it "cannot be used on uninitialised memory".
`test/test_promoint_local_array_zero_init.pas` **segfaults** on the pre-fix
compiler for that reason.

With init fixed, every element starts `{0, 0}`, so clearing element 0 is
harmless and the remaining defect is bounded: **elements 1..N leak whatever
heap-tier payload they were given.** Safety-critical half closed, correctness
half open — which is why this is filed at 45 rather than inheriting 55.

## The precedent names the remedy

This is the same defect as
`bug-a-local-static-array-of-string-never-released-at-scope-exit`, one type
over. That fix added the "STATIC array with MANAGED ELEMENTS: release EVERY
element" arm at `symtab.inc:10745`, which calls `PXXArrayReleaseImmediate` with
an explicit `(addr, count, baseKind, ref)` — a header-free element walk, since a
static array has no `[refcount][length]` prefix. Its comment describes this
ticket's symptom verbatim: *"fell into the scalar tyAnsiString arm below and
released element 0 ONLY — the other N leaked, silently and linearly."*

So the shape of the fix is known: give `ManagedElemKind` a promo-int kind and
let that existing arm claim promo arrays (it is **earlier** in the chain than
the promo arm, so it will), and teach `PXXArrayReleaseImmediate` to dispatch
that kind to `PXXPromoClear` per element. That is a runtime change in
`compiler/builtin/promocore.pas` plus a new base-kind number, which is why it
is not folded into the init fix.

## Reachability, measured

`promoint64` / `promoint32` / `promoint` are spellable Pascal type names
(`pasparser_decl.inc:543`), so this is reachable from ordinary Pascal. It is
*not* reachable from NilPy user code, which has no static-array syntax — a
NilPy list is a dyn array (`ArrLen = -1`) and is claimed by the dyn-array-handle
arm long before either promo arm. No in-repo source declares a promo-int array
today, which is why neither half was noticed.

## Gate

`make compiler/pascal26` + a leak probe in the shape of
`test_open_array_no_leak` (a hot loop writing a heap-tier value into
`a[1..N]`, RSS asserted flat) + `tools/gate.sh quick`.
