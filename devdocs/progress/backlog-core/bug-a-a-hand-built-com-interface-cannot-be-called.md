---
track: A
prio: 55
type: bug
blocked-by: []
status: backlog
found: 2026-09-09
found-by: frankS
owner: unassigned
summary: "An interface value built BY HAND -- a pointer whose first word is a table of code pointers, which is FPC's and Delphi's interface representation -- segfaults when called under pxx. 60-line repro (test-shaped, in the body): pxx dies in PXXIntfIMTOf, fpc 3.2.2 prints 42. The two representations are INVERTED and each compiler is self-consistent: pxx's interface value is the INSTANCE pointer and the IMT is recovered per call from the instance's RTTI blob (`[[inst]-8]` -> iface table -> IMT, ir.inc's AN_INTF_CALL and builtinheap.pas's PXXIntfIMTOf); FPC's value IS the IMT pointer. The positive control is the mirror and it is exact -- `IFoo(Pointer(anObject))` WORKS under pxx and dies with RTE 216 under fpc. The IMT CONTENTS already agree (slot 0 QueryInterface, 1 _AddRef, 2 _Release, then methods, spelled out in builtinheap.pas); only the ROUTE to the IMT differs. No runtime discrimination is available -- the RTTI blob carries no magic word, so a fallback in PXXIntfIMTOf would be a guess, not a check. The discrimination DOES exist at the cast site (the operand's static type is a raw pointer, not a class) and cannot survive the value, because the value is one word with nowhere to put a tag. That is why this is a representation decision and not a patch. Blocks feature-pascal-corpus-generics: `TComparer<T>.Default` is nil because rtl-generics reaches every comparer through exactly this construct."
---

# A hand-built COM interface cannot be called

**Blocks [[feature-pascal-corpus-generics]]** — this is what leaves
`TComparer<LongInt>.Default` answering nil. Not the static-Self ABI, which is
fixed ([[bug-p-a-static-class-functions-address-carries-a-hidden-self]], done)
and was a different wall.

## The repro — 60 lines, no rtl-generics

```pascal
type
  IFoo = interface function Val: Integer; end;
  TFooVMT = packed record
    QueryInterface, _AddRef, _Release, Val: CodePointer;
  end;
  TSpoof = record VMT: Pointer; RefCount: LongInt; end;
  TRaw = class          { virtual methods only so their addresses are stable }
    function QueryInterface(constref IID: TGUID; out Obj): HResult; virtual;
    function _AddRef: LongInt; virtual;
    function _Release: LongInt; virtual;
    function Val: Integer; virtual;    { returns 42 }
  end;
const
  FooVMT: TFooVMT = (QueryInterface: @TRaw.QueryInterface; _AddRef: @TRaw._AddRef;
                     _Release: @TRaw._Release; Val: @TRaw.Val);
var s: TSpoof; f: IFoo;
begin
  s.VMT := @FooVMT; s.RefCount := 1;
  f := IFoo(@s);        { assigns cleanly under both }
  WriteLn(f.Val);       { pxx: SIGSEGV in PXXIntfIMTOf.  fpc 3.2.2: 42 }
end.
```

## The positive control, and it is the mirror

```pascal
o := TImpl.Create;  p := Pointer(o);  g := IFoo(p);  WriteLn(g.Val);
```

**pxx prints 7. fpc dies with `Runtime error 216`.** So this is not "pxx is
broken at interface casts" — the two compilers hold opposite representations and
each is correct about its own. What makes it a defect on our side is only that
real source someone MEANT to write builds FPC's one, and `generics.defaults.pas`
is that source.

**NOT `known-incompat/`, and the paragraph above is exactly what would get it
refiled there.** "Both behaviours are correct about their own implementation"
is the known-incompat criterion word for word, and it is satisfied here. What
fails the rest of that test is the second half: known-incompat also requires
that ours be **chosen**, and nothing chose this — it is the incidental
consequence of recovering the IMT from RTTI, which was chosen to keep the value
one word. A construct FPC's own packages use to reach every default comparer is
not an edge case a programmer reached by mistake, so `ON PAR WITH THE LANGUAGE`
does not excuse it either. It is a bug with a mirror, which is a different
animal from a divergence with a rationale.

## Why the route differs and the contents do not

pxx: the value is the INSTANCE. `AN_INTF_CALL` (ir.inc) emits
`imt := PXXIntfIMTOf(self, ifaceId)` and then `code := [imt + slot*8]`.
`PXXIntfIMTOf` (builtinheap.pas) reads `vmt := [inst]`, then
`rtti := [vmt - 8]`, then walks the parent chain looking for the interface id in
a `{GUID:16, IMT:8, id:8}` table. Behind a hand-built object, `[vmt - 8]` is
whatever the linker put before a typed const, so the walk faults.

FPC: the value IS the IMT pointer. `[value + slot*8]` and nothing else.

**The IMT layout is already the same on both sides** — builtinheap.pas states it:
slot 0 = QueryInterface, 1 = _AddRef, 2 = _Release, methods after. So the tables
rtl-generics builds are correctly shaped for us; nothing can find them.

## What a fix has to decide, and why it is not a patch

- **No runtime discrimination exists.** The class RTTI blob has no magic word
  (`RTTI_CLS_*` in defs.inc is name/parent/instSize/vmt/... with no signature),
  so "if the blob looks invalid, treat `[inst]` as the IMT" is a guess that
  cannot be checked and would mis-fire silently on a corrupted instance.
- **The compile-time discrimination is real and does not survive.** At
  `IFoo(@s)` the operand's static type is a record pointer, not a class, so the
  cast site knows. The interface VALUE is one word with nowhere to carry the
  answer, which is exactly the property that lets it stay one word.
- So the options are: give the cast a synthesised shim carrying real RTTI whose
  IMT is `[raw]`; or move to FPC's representation. Both are Track A ABI work.
  Not attempted here.

Measured 2026-09-09 at binary `68421d8ff193`, commit `f68021557`, against
fpc 3.2.2 `-Mdelphi`.
