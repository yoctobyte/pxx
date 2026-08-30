---
slug: bug-a-indexing-through-a-pointer-to-an-array-of-pointers-segfaults
track: A
prio: 60
type: bug
status: backlog
owner:
blocked-by: []
summary: "`p^[i]` where p points to an ARRAY segfaults for some element types, on read AND write, in a plain default build; it compiles clean and dies at run time, so a build-only check reports success. DIAGNOSED at the IR by frank-rust (2eb6f76b4): it is a BAD BASE, not a bad index -- the arm emits an extra load_mem and size=1, so `ppa^[1]` computes [[ppa]] + 1*1, taking element 0s CONTENTS as the base address. Root cause is an AMBIGUOUS TAG: tk=tyPointer on a deref node means both \"the pointee is a pointer\" and \"the pointee is an array of pointers\", and the p^[i] arm in pasparser_lval.inc resolves the element from pointer DEPTH. CORRECTION: my original element-type table was misleading -- this is NOT about pointer-kind elements. AnsiString SEGFAULTS and TObject WORKS, which inverts that reading; Integer/Double/Boolean escape only because their tag cannot collide with the test. A second, SEPARABLE Track P defect (a pointer alias to a named fixed array loses AliasPtrBaseTk) is measured NOT to cause the crash on its own."
---

# `p^[i]` segfaults when the array's element type is a pointer

## Measured

Binary `992065f21f33` (the pin). Plain default build, no define, no flag.
Same program, only the element type varying:

```pascal
type TA = array[0..3] of <ET>; PA = ^TA;
var a: TA; p: PA;
begin
  p := @a;
  p^[1] := Default(<ET>);      { WRITE -- read fails identically }
  WriteLn('ok');
end.
```

| element type | result |
| --- | --- |
| `Integer` | **works** |
| `Int64` | **works** |
| `Pointer` | **SEGFAULT** (rc=139) |
| `PChar` | **SEGFAULT** |
| `PInteger` | **SEGFAULT** |

So it is **pointer-KIND elements**, not `Pointer` the type name.

## Oracle

FPC gets the whole thing right. On the read side, four rows, FPC vs pxx:

```
                     FPC     pxx
1 direct   s[0]      100     100
2 (pl^)[0]           100     <segfault>
3 pl^[1]             101     -
4 pl^[2] := 999 ;    999     -
  then s[2]
```

pxx prints row 1 and dies on row 2. `fpc -Mobjfpc` on the identical source
prints all four.

## Not a pointer-to-array problem in general

Worth stating, because that is the obvious first guess and it is wrong:
`pointer-to-record` deref (`pr^.x`) is **correct**, and `pointer-to-array-of-Integer`
indexing (`pia^[1]`) is **correct**, in the same program that then dies on
`pointer-to-array-of-Pointer`. The dereference machinery works; something on the
pointer-element path does not.

## Why it matters more than it looks

`p^[i]` over an array of pointers is an ordinary Pascal idiom, not a corner:
it is how FPC's own `TList.List` is consumed, and fcl-xml writes
`TObject(FBindings.List^[I]).Free` at `xmlutils.pp:760`.

**It compiles clean and dies at run time**, so any check that builds without
running reports success. Found only because the program was run.

## Consequence for [[bug-b-tlist-has-no-list-property]]

That ticket asks for `property List: PPointerList read FList` on `TList`, and the
storage supports it — measured: `Pointer(a) = @a[0]` for a dynamic array and the
stride is 8, so the layout is exactly what `PPointerList` expects.

**Adding the property anyway would be wrong today.** It would compile, and then
segfault at the one idiom it exists to enable. That converts an honest
`"List": no such member` into a crash at a call site, which is strictly worse:
the current error names the problem at compile time. The property should land
**with or after** this fix, and that ticket is now `blocked-by` this one.

## Gate

`make compiler/pascal26` + the element-type table above, **run, not just built** —
every row compiles.

---

## Diagnosis at the IR, and it is TWO defects (frank-rust, 2026-08-30)

Reproduced independently, binary `2df3a1efab85`, self-host fixedpoint at HEAD.
The `Integer` and `Pointer` rows in one program, dumped with
`PXXDBG=a.ir:<proc>`, and the divergence is one node:

```
  array of Int64 (WORKS)                array of Pointer (SEGFAULT)
  2: load_sym  pia                      3: load_sym  ppa
                                        4: load_mem  a=3          <-- EXTRA DEREF
  4: index a=2 b=3 [lo=0 size=8]        5: index a=4 b=2 [lo=0 size=1]   <-- size 1
  5: load_mem                           6: load_mem
```

So `ppa^[1]` computes `[[ppa]] + 1*1` — it takes **element 0's contents as the
base address** and then steps ONE byte. That is why putting a valid address into
`pa_[1]` does not survive either: the extra load reads `pa_[0]`, not `pa_[1]`.
The crash is not a bad index, it is a bad base.

The ASTs are structurally identical; only the tags differ (`AN_DEREF` tk 13 vs
17, and the `AN_INDEX` comes out **tk 0, tyUnknown**, which is where `size=1`
comes from).

### Defect 1 — `tk = tyPointer` on a deref means two different things

`pasparser_lval.inc`, the `p^[i]` arm (`(tk = tyPointer) and (ASTKind[node] =
AN_DEREF)`) resolves the element from the pointer DEPTH parked on the deref
node: *"one level left means the element IS the base type, two or more means the
element is still a pointer."*

That is correct for `^PChar`. It is wrong for `^TPtrArr`, because there `tk` is
not the pointee's kind — it is the pointee ARRAY's ELEMENT kind, and it happens
to be `tyPointer`. The arm cannot tell the two apart, so a pointer to an array
of pointers is processed as a pointer to a pointer. **`array of Integer` escapes
only because `tyInteger` cannot collide with the test at all** — which is
exactly why the bug looks element-type-specific and is not: the discriminator is
an ambiguous tag, not the element type.

The information to disambiguate is already on the symbol and is correct:

```
PXXDBG a.symptr ppa   kind=17 depth=1 ptrElemTk=17 ptrElemArrLen=4
PXXDBG a.symptr pia   kind=17 depth=1 ptrElemTk=13 ptrElemArrLen=4
```

`ptrElemArrLen=4` on both — the pointee IS known to be a 4-element array in both
cases. Nothing needs to be computed; the arm needs to ask.

### Defect 2 — the ALIAS loses the pointee's base kind, the inline type does not

Same program, same pointee, two spellings:

```
var ppa: PPtrArr;    (PPtrArr = ^TPtrArr)   ->  baseTk=0
var ppa: ^TPtrArr;                          ->  baseTk=17
```

`AliasPtrBaseTk` is not carried for a pointer alias whose pointee is a named
fixed array. That is separable and it is a **Track P** file
(`pasparser_decl.inc` / the alias registration in `symtab.inc`), not Track A.

**Fixing defect 2 alone does NOT fix the crash** — measured, not assumed: with
the inline spelling `baseTk` is right, the index element resolves to `tyPointer`
correctly, and it still segfaults, because defect 1's extra `load_mem` is
independent of it.

### A hypothesis this ruled OUT, recorded so nobody re-runs it

`ParseTypeKind`'s `tkCaret` arm reads `childDepth := LastTypePointerDepth`
*after* an if/else whose array branch never calls `ParseTypeKind` — so it reads a
STALE depth, and `(elemTk = tyPointer) and (childDepth > 0)` looked like it would
register the alias as a pointer-to-pointer. It is a real smell and it is **not
this bug**: setting `childDepth := 0` there produced **byte-identical IR** and
the identical segfault. The symbol already had `depth=1`. Do not spend the
build on it again.

### What a fix has to do

Make the `p^[i]` arm (and whatever in `IRLowerAddress` decides to materialise
the deref) recognise that the pointee is an ARRAY, so `p^` yields the array's
ADDRESS rather than a loaded pointer, and the index takes the array's element
stride. The `array of Int64` path already does exactly this — it simply gets
there by never entering the pointer arm. The two paths should reach it for the
same stated reason, not by one of them missing a test.

**Not started.** I have no measurement of which of the two sites is the right
one to change, and guessing between them is how a plausible-looking fix that
moves the crash somewhere else gets written.


---

## 2026-08-30 (frank-rust, extended by frankB) — diagnosed, and my table was misleading

**The crash is a bad BASE, not a bad index.** frank-rust dumped both rows:

```
array of Int64 (works)        array of Pointer (segfault)
2: load_sym  pia              3: load_sym  ppa
                              4: load_mem  a=3          <-- extra deref
4: index [lo=0 size=8]        5: index [lo=0 size=1]    <-- and size 1
5: load_mem                   6: load_mem
```

`ppa^[1]` computes `[[ppa]] + 1*1` — element 0's *contents* used as the base
address. Root cause: `tk = tyPointer` on a deref node means **two** things
("the pointee is a pointer" / "the pointee is an array whose elements are
pointers") and the `p^[i]` arm reads it as the first, resolving the element from
pointer **depth**. `PXXDBG=a.symptr` shows `ptrElemArrLen=4` on both symbols, so
the information to disambiguate exists and is correct — the arm does not ask.

### My element-type table was the wrong frame, and two more rows prove it

I reported this as "pointer-KIND elements break". **That reading is wrong**, and
the two element types neither of us had tried are the ones that break it:

| element type | result | |
| --- | --- | --- |
| `Integer` `Int64` `Double` `Boolean` | **work** | tag cannot collide |
| `TObject` | **works** | and it *is* a pointer at runtime |
| `AnsiString` | **SEGFAULT** | and it is not what anyone calls pointer-kind |
| `Pointer` `PChar` `PInteger` | **SEGFAULT** | |

`AnsiString` breaking while `TObject` works kills "pointer-kind" as the
predicate in both directions at once. What survives is frank-rust's model: it is
about **pointer depth as the tag reports it**, not about the element being a
pointer in any representational sense. The working rows are not "the working
element types" — they escape only because their tag cannot collide with the test.

**The general form is this ticket's real content:** an enumeration of symptoms
looked like a cause. A type list is a plausible-looking classification, and it
had 5 of 5 rows right while being the wrong axis entirely — which is exactly the
80%-accurate-name failure, since the part I sampled confirmed it.

### Two defects, and the second does NOT cause this

frank-rust measured a **separable Track P** defect — a pointer alias whose
pointee is a named fixed array loses `AliasPtrBaseTk` (`var ppa: PPtrArr` gives
`baseTk=0`; `var ppa: ^TPtrArr` gives `baseTk=17` for the same pointee) — and
confirmed **fixing it alone does not fix the crash**: with the inline spelling
the element resolves correctly and it still segfaults, because the extra
`load_mem` is independent.

### A hypothesis already RULED OUT — do not spend a build on it

`ParseTypeKind`'s `tkCaret` arm reads a stale `childDepth` after a branch that
never calls `ParseTypeKind`. Real smell, plausible story: setting it to 0 produced
**byte-identical IR and the identical segfault**.

### No fix started, deliberately

There is no measurement saying whether the parser arm or `IRLowerAddress` is the
right site, and guessing between two plausible sites is how a fix moves a crash
instead of removing it.
