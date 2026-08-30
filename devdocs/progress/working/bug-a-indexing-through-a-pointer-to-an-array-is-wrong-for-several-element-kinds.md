---
slug: bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds
track: A
prio: 60
type: bug
status: working
owner: frankA
blocked-by: []
summary: "`p^[i]` where p points to an ARRAY is broken for several element kinds, and the WORST arm is SILENT: `array[0..3] of string[7]` (also string[31], ShortString) yields an EMPTY string where FPC yields `hi`, exit 0, no crash and no diagnostic -- a plausible wrong VALUE, which is the expensive class. Other element kinds (Pointer, PChar, PInteger, AnsiString) segfault; Integer, Int64, Double, Boolean, Char, TObject and a record element are correct. It compiles clean in every case, so a build-only check reports success. DIAGNOSED: the crash is a bad BASE, not a bad index -- `ppa^[1]` emits an extra load_mem with size=1, computing [[ppa]] + 1*1. THE MODEL IS NOT ABOUT POINTERS: the `[` arm chain dispatches on `tk`, and for a pointer-to-array `tk` holds the ARRAY ELEMENT KIND while every arm reads it as the type of the thing being indexed -- collide with an arm above the array fall-through and you break, collide with nothing and you are fine. The crash site is IRLowerAddress AN_INDEX (~40 lines: baseAddr choice and elemSize), NOT the parser -- proven by routing past all five element-kind arms and getting a byte-identical segfault. A second real parser defect makes the string[7] row silently wrong and is separable."
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

---

## Two more rows, and one of them is worse than a crash (frank-rust)

Binary `18ceb4588586`, self-host fixedpoint at HEAD. Testing the corrected model
— *"the working rows escape only because their tag cannot collide"* — predicts
which untried element types break, so here are four that had not been tried:

| element | result | why |
| --- | --- | --- |
| `Char`, `Boolean` | correct | no arm matches the tag |
| a record type | correct | the record arm wants a record BASE, not a record element |
| **`string[7]` (frozen)** | **`short ` — SILENTLY WRONG, no crash** | the frozen-string arm matches |

FPC prints `short hi`; we print an empty string. The same array indexed WITHOUT
the pointer prints `hi`, so it is the `p^[i]` path and not the declaration.

**That row matters more than the crashes.** A frozen string is neither
pointer-kind nor a managed handle, so it is a third independent arm — and it
fails by producing a plausible wrong VALUE rather than a signal. Everything
found so far was a segfault, which is the cheap case; this is the expensive one
and it was sitting in the same defect the whole time.

The predicate is therefore not about pointers at all: **the `[` arm chain
dispatches on `tk`, and for a pointer-to-array `tk` holds the ARRAY'S ELEMENT
kind while every arm reads it as the type of the thing being indexed.** Any
element kind that collides with an arm above the array fall-through breaks —
`tyPointer` (three pointer arms), `tyAnsiString` and frozen strings (two string
arms) — and any kind that collides with nothing is fine.

## The parser is NOT the crash site — measured, so the two candidates are now one

Earlier I said I would not start a fix because there were two plausible sites and
no measurement to choose between them. There is one now.

I taught `IsNodeArray` (`symtab.inc`) that an `AN_DEREF` over a pointer with
`SymPtrElemArrLen > 0` is an array, which routes `p^[i]` down the ARRAY arm of
the index chain and past all five broken element-kind arms. Instrumented at
every `AllocNode(AN_INDEX)` site to confirm it actually fires:

```
PXXDBG p.idxarm site=pasparser_lval.inc:1406
PXXDBG p.idxarm chain=A basekind=36 tk=17 isarr=TRUE      <- AN_DEREF, now an array
```

**Result: the index's element tag is fixed (`AN_INDEX` goes from `tk=0` to
`tk=17`) and the program still segfaults, byte-identically.** The IR keeps both
of its real defects:

```
4: load_mem a=3                          <- still takes element 0's CONTENTS as the base
5: index a=4 b=2 [lo=0 size=1] tk=17     <- still strides ONE byte
```

So: the parser arm chain is a genuine second bug (it is what makes `string[7]`
silently wrong, and `tk=0` is its fingerprint), but **it is not what crashes.**
The crash lives entirely in `IRLowerAddress`'s `AN_INDEX` arm — the `baseAddr`
choice and the `elemSize` computation for an `AN_DEREF` base. `TypeSize(tyPointer)`
is 8 and the emitted stride is 1, so that arm is not reaching its own
`else elemSize := TypeSize(tk)` tail; something above it is claiming the node
first. That is where to look, and it is ~40 lines.

**I reverted the `IsNodeArray` change rather than landing it.** On its own it
fixes no observable row — every row behaves identically before and after, only
an IR tag moves — and it changes a predicate shared across the compiler. Landing
a shared-predicate change that fixes nothing, next to a still-broken IR, would
read as a fix to the next person. It is recorded here instead, with the exact
edit, so whoever takes the IR half can re-apply it in one minute and get the
parser half for free.


## 2026-08-30, later (frank-rust; independently confirmed by frankB) — a SILENT arm, and the model finishes

**This row belongs at the top of the ticket.** Everything above is a segfault,
which is the cheap case — it has a location and it stops. This does not:

```pascal
type TSA = array[0..3] of string[7]; PSA = ^TSA;
a[1] := 'hi';  p := @a;
                          pxx            FPC
  direct   a[1]           [hi]           [hi]
  through  p^[1]          [ ]            [hi]        exit 0, no diagnostic
```

Confirmed in my own checkout against the FPC oracle, and it is not specific to a
width: `string[7]`, `string[31]` and `ShortString` all produce the empty string
through the pointer while `Char` is correct. **A frozen string is neither
pointer-kind nor a managed handle**, so this is a third independent arm — and it
had been sitting inside the same defect the whole time, invisible because every
probe either of us wrote asked "did it crash?".

### The model, finished — and it is not about pointers

frank-rust's statement, which supersedes every element-type reading including my
corrected one:

> **The `[` arm chain dispatches on `tk`, and for a pointer-to-array `tk` holds
> the ARRAY'S ELEMENT KIND while every arm reads it as the type of the thing
> being indexed.** Collide with an arm above the array fall-through and you
> break; collide with nothing and you are fine.

That is why the symptom set looks arbitrary: it is a list of which element kinds
happen to have an arm above the fall-through, and **the symptom differs by which
arm catches it** — a pointer arm gives a wrong base and a segfault, the frozen
string arm gives a wrong value and silence. `TObject`/`AnsiString` killed
"pointer-kind"; `string[7]` kills "representational" entirely.

### The crash site is the IR, not the parser — measured

frank-rust taught `IsNodeArray` that a deref of a pointer-to-fixed-array is an
array, routing `p^[i]` past all five broken element-kind arms, and instrumented
every `AllocNode(AN_INDEX)` site to confirm it **fired** rather than assuming
(`basekind=36 isarr=TRUE`; the index's element tag moved `tk=0` -> `tk=17`).
**The program segfaulted byte-identically.**

So: the crash lives entirely in `IRLowerAddress`'s `AN_INDEX` arm — the baseAddr
choice and elemSize, ~40 lines. `TypeSize(tyPointer)` is 8 and the emitted stride
is 1, so that arm never reaches its own `TypeSize` tail; something above claims
the node first. The parser defect is real, is what makes the `string[7]` row
silently wrong, and is **separable**.

### That parser change was deliberately NOT landed

It fixes no observable row — every row behaves identically, only an IR tag moves —
and it changes a predicate shared across the compiler. **A shared-predicate change
that fixes nothing, sitting next to a still-broken IR, reads as a fix to the next
person.** The exact edit is banked in the ticket so whoever takes the IR half gets
the parser half in a minute.

## 2026-08-30, frankA — three of the readers fixed; the frozen-string arm is not

Landed with a ten-row test against `fpc -Mobjfpc`. **Fixed:** a raw pointer
element, a record-pointer element (with a field behind the second caret), an
AnsiString element (read, write and `Length`), and a PChar element written
inline. **Still broken, and it is the silent one:** a FROZEN-string element.

### What the three fixes were

One ambiguous tag, three readers. The caret arm tags a deref node with the
ELEMENT's kind, so `tk = tyPointer` on `p^` means both "the pointee is a
pointer" and "the pointee is an ARRAY whose element is a pointer".

| reader | wrong answer | effect |
| --- | --- | --- |
| `IsNodeArray` | FALSE | the array path took the managed-STRING arm: `p^` loaded as a handle, indexed 1-based at stride 1 |
| `IRNodePointerBase` | TRUE | lowered as pointer arithmetic: extra `load_mem`, stride 1, element 0's contents as the base |
| `IsNodePChar` | FALSE | had `arr[i]` and `q^`/`q[i]`, not the two composed — silent wrong value |

`DerefPtrArrayInfo` already knew the real shape; two of the three now ask it.

### The two lowering fixes are disjoint — ablated, not argued

With only `IsNodeArray` fixed, a Pointer/PChar/PRec element still segfaults.
With only `IRNodePointerBase` fixed, an AnsiString element still segfaults.

### The ticket's suspected site measured as NO CHANGE

This ticket named the parser's `p^[i]` arm. I guarded it there first — it is the
obvious fix and it reads right. Ablated properly it moved **nothing**: every row
passes without it, *including* the two compile errors it was supposed to
explain. Those come from `IsNodeArray`, which the **parser** also calls. Dropped
rather than kept.

The first ablation was itself wrong and is worth recording: `(not False and X)`
parses as `(not False) and X` = `X`, which **inverts** a guard rather than
disabling it. The rows passed anyway, which is how it survived a look.

### What is left, and why my own table missed it

**I asserted exit code, not output.** `ShortString` scored as PASSING in my
element-type sweep on `rc=0` alone. Measured properly on the fixed binary:

```
string[7]     pxx [] [] len=0                 fpc [hi] [hi] len=2
string[31]    pxx [] [] len=0                 fpc [hi] [hi] len=2
ShortString   pxx [i <220 spaces>] [] len=7493989779944505344
```

A frozen-string element is a different arm from the three above —
`TypeIsFrozenString(tk) and not isArr` in `IRLowerAddress`, plus whatever gives
`Length` a garbage answer. `isArr` is now TRUE for this shape, so that arm is no
longer the one being taken and the remaining fault is downstream of it. Not
diagnosed further.

Test: `test/test_ptr_to_array_of_pointers_index.pas`, wired in `make test`.
Non-vacuous per row on `pinned` (139 / compile error / 139 / 139), measured
individually because the file stops at the first compile error.
