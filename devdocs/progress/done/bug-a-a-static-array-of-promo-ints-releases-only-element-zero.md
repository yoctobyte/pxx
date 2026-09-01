---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-30
found-by: frankA (the cleanup half of bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice)
summary: "ManagedElemKind answered 0 for a promo element AND for a Variant element, so every container element walk declined the array and the SCALAR arm claimed it: an array's TypeKind IS its element kind, so the address passed is element ZERO. Three faults from one missing fact -- scope exit released element 0 and leaked 1..N; the proc got no unwind landing pad at all (SymNeedsManagedCleanup asks ManagedElemKind too); and `b := a` on two promo arrays emitted ONE PXXPromoCopy on the base address, copying element 0 and leaving 1..N holding the destination's old values. The VARIANT half was not in this ticket and leaks more (109 MB vs 87.5 MB over 200k calls, against 392 KB for the scalar control). Fixed as kinds 5 and 6 in ManagedElemKind with the stride in ManagedElemRef, plus retain and release in all three runtime walks. RESOLVED."
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

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.


## Resolved

Fixed in the commit below. Four things worth carrying forward, because the
ticket had three of them wrong or absent:

**The remedy the ticket predicted was right, and incomplete.** It said: give
`ManagedElemKind` a promo kind and let the existing static-array arm claim it.
That is what landed. But it also said the runtime change belongs in
`promocore.pas`; it does not, and cannot -- a builtin unit cannot `uses`
another one, so the element walks live in `builtinheap.pas` and release the
heap-tier payload as what it is, a managed AnsiString. That is the same
representation `PXXVarClear` already uses for a variant carrying a promo tag,
so builtinheap was already the file that knew this.

**A base-kind number is not enough for these two.** Every kind above them
implies its element size; `promoint64` is a 16-byte slot and `promoint32` an
8-byte one, so kinds 5 and 6 carry the STRIDE in `ManagedElemRef`, which is the
designated second half of the (kind, ref) pair. Sending the compiler's own
`TypeSlotSize` is what stops the runtime and the compiler disagreeing about the
layout on any target.

**Two faults the ticket did not contain.** The unwind path: `SymNeedsManagedCleanup`
asks `ManagedElemKind` as well, so a proc whose only managed local was such an
array got no cleanup landing pad, and an exception past it leaked every element
including 0. And `b := a` on two static promo arrays reached the promo STORE
arm and emitted one `PXXPromoCopy` on the base address -- element 0 copied,
1..N left holding the destination's old values, silently. Both are fixed by the
same change, which is the argument for fixing it at `ManagedElemKind` rather
than in the scope-exit arm as the ticket framed it.

**"No in-repo source declares a promo-int array today"** was true when filed and
is no longer: `test_promoint_array_cleanup.pas` and `test_promoint_lvalue_shapes.pas`
both do, and the first runs on all five targets qemu can host.

The ticket's Gate line asked for a hot-loop RSS probe. That is the Makefile
row's second half, with the threshold placed between two executed numbers
(3.6 MB fixed, 54 MB unfixed) rather than beside one.
