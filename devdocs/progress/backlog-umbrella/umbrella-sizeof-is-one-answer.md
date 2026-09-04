---
slug: umbrella-sizeof-is-one-answer
track: A
prio: 75
type: umbrella
status: backlog
owner: ""
blocked-by:
  - compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees
  - bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts
  - bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable
  - bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size
  - feature-p-implement-the-real-tyshortstring-byte-prefix-layout
  - bug-c-sizeof-of-a-pointer-to-array-struct-field-answers-the-pointer-size
  - bug-c-sizeof-reaches-a-pointee-through-one-spelling-only
  - refactor-a-the-const-cast-width-table-is-the-third-copy
  - bug-n-nilpy-carries-its-own-copies-of-the-float-type-table
  - bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386
  - bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets
  - bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes
  - bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more
summary: "GOAL: a program can trust SizeOf. `FillChar(x, SizeOf(x), 0)` and `Move(a, b, SizeOf(a))` are correct for EVERY type in every frontend, and `file of T` can write a layout that reads back. Today they are not: SizeOf answers 8 for every `string[N]` while pxx's OWN layout engine gives that type 18, so `FillChar` on an `array[0..2] of string[10]` clears 24 of 54 bytes and leaves a[2] intact -- silent, and correct under FPC so no differential probe sees it. Root cause is measured and structural: FOUR functions answer `how big is this type`, each adding one more parameter because the kind alone was not enough -- TypeSlotSize(tk) at 363 sites, TypeStorageSize(tk, recId), SizeOfSlot(tk, cap), FrozenStrSlotSize(tk, cap). SizeOfSlot's own comment says it: `A FROZEN STRING'S SIZE IS NOT A FUNCTION OF ITS KIND`. Two is a smell, three is a design flaw; this is four, plus duplicated builtin type tables in A, N and P that disagree with each other."
---

# Umbrella: `SizeOf` is one answer

**The goal is a property a program can rely on**, not a refactor: `FillChar(x,
SizeOf(x), 0)` zeroes all of `x`, `Move(a, b, SizeOf(a))` copies all of `a`, and
a record written by `file of T` reads back. Those are the commonest idioms in
Pascal and they are wrong today for ordinary declared types.

## Why this is one umbrella and not nine tickets

Measured 2026-09-02. Four functions answer *how big is this type*, and each was
added when the previous one's parameters turned out to be insufficient:

| function | parameters | sites |
| --- | --- | --- |
| `TypeSlotSize` | kind | **363** |
| `TypeStorageSize` | kind + record id | — |
| `SizeOfSlot` | kind + capacity | — |
| `FrozenStrSlotSize` | kind + capacity | 15 |

`SizeOfSlot`'s own comment states the defect: *"TypeSlotSize, except that **A
FROZEN STRING'S SIZE IS NOT A FUNCTION OF ITS KIND**."* The model is wrong —
size is a property of a TYPE, and every one of these takes a KIND plus whatever
extra the author needed that day. `root-cause-over-microfix.md`: two mechanisms
for one concept is a smell, three is a design flaw. **This is four**, and beside
it sit duplicated builtin type-name tables in A, N and P that disagree.

Every member below is the same sentence in a different place: **something other
than the layout engine was asked how big a type is, and it answered.**

## THE PRINCIPLE, traced back to where it started (owner, 2026-09-02)

*"it all started with the 'set' ticket .. that was the point i realized some
typing need to be strict."* The set work and the string work are **one defect
stated twice**:

> **A type whose SIZE is a function of a DECLARED NUMBER must carry that
> number. Otherwise the number is metadata, and metadata gets lost.**

- **Sets.** `set of 0..7` and `set of Char` are both `tySet`. The bound is not
  in the type, so the width cannot follow the declaration and everything gets
  32 bytes.
- **Fixed strings.** `string[10]` and `string[1000]` are both `tyFixedString`.
  The capacity is not in the type, so it lives in **nine** side-tables keyed
  three ways — and any path that fails to carry it yields a plausible 264-byte
  default rather than an error.

**The proof that it is one defect and not an analogy:** in `r.inner[0] := <20
chars>` the capacity reaches the truncating CLAMP (correctly 10) and not the
STRIDE (falls back to 264). One declared number, two consumers, two tables, one
populated. That cannot happen to a number the type carries.

**And the fix converges on one shape**, arrived at independently for both: a
hidden second kind selected by the bound, source spelling unchanged —
`smallset` for `set of 0..31`
([[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]],
parked), `tyShortString` for `string[N<=255]`
([[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]], p100). Both
move the representational choice back to where the bound is known — the
declaration — instead of leaving it to whichever side-channel happens to be
populated at the point of use.

**Read this before unparking the set work**: it is the same job, and whatever
the string half learns about carrying a bound on the type applies to it
directly.

## THE ROOT OF THE STRING HALF HAS A NAME: `tyString` IS OVERLOADED

Found 2026-09-02 when the owner asked whether `tyString` was misnamed. It is
not misnamed — **it is overloaded, and the codebase says so itself**:

```
tyString,      { 4: Pascal string with inline length prefix }
{ Ordinals 25+: frozen fixed-length string kinds (disambiguate the old
  overloaded tyString) ... tyString stays a legacy frozen alias during migration. }
tyShortString, { 25 }   tyFixedString, { 26 }
```

**`tyString` serves three roles**: string literals; plain `string` variables (a
`LOCAL_STR_CAP` = 256 slot); and `string[N]` record fields (`UFldSubHi`:
*"stored as tyString with an N+8 slot"*). Length is an inline 8-byte NativeInt
prefix — **but CAPACITY is carried out of band**, in `SymSubHi`, `UFldSubHi`,
`SymStrCap`, `ArrTypeElemStrCap` and `SymPtrElemStrCap`.

**That is this umbrella's string half, stated at the root.** `SizeOfSlot`'s
comment — *"a frozen string's size is not a function of its kind"* — is a
description of `tyString` being overloaded. The capacity side-tables exist
because the kind cannot carry the capacity; the size oracles exist because of
the side-tables. Every string member of this umbrella is a leaf of that.

**A migration to fix it already exists and is barely started:** 627 `tyString`
sites against 80 `tyFixedString` and 63 `tyShortString`. So the end condition
here is not only "one oracle" — for strings it is **finishing a migration
someone already designed**, which is a much better position than inventing one.
Whoever takes a string member should check whether their fix is a leaf or a
step in that migration, and prefer the step.

## Two shapes

**1. The oracle takes too few parameters** — so a type whose size depends on
more than its kind is silently wrong. `SizeOf(string[N])` = 8 against a real
stride of 18. A subrange wider than 32 bits was this shape too and is
**fixed** (`ffe20a8bc`) — `-3000000000` read back as `1294967296`, and nine days
of probes missed it because every one used a range that happened to fit.

**2. Duplicated type tables that disagree** — `ConstIntCastWidth` is the THIRD
copy of the builtin table; `pyparser.inc` holds three private copies of the
float mapping; Pascal settles a builtin name against the TABLE rather than
against the PROGRAM, so a user type shadowing a builtin answers `12 8 8` for the
same `SizeOf` in one program.

## What ENDS this umbrella

One oracle, asked by everything, answering from a type rather than a kind — and
a test that a value assertion cannot pass by accident. **The assertion class
matters here**: a wrong size does not corrupt a value in the common case, it
mis-sizes a copy, so `expect_same` rows pass while `FillChar` leaves a tail
intact. The subrange bug was found only because its positive control was a SIZE
row rather than a value row. Any test this umbrella accepts must assert sizes
and strides directly, and must include a row where the type's size is NOT a
function of its kind.

## Wiring a member — the edge runs ONE WAY

## THE UMBRELLA'S OWN TESTS SHARE ONE BLIND SPOT — a stride cannot audit itself

Raised by frankB from `bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes`
(2026-09-02), and it generalises past that ticket, so it belongs here rather
than there.

That bug is **not a fat layout — it is a write outside the record.**
`record inner: array[0..1] of string[10]; tail: LongInt` is 40 bytes, and
`@inner[1]` was **224 bytes past its end**; `r.inner[1] := s` clobbered five
words of an unrelated local. Ordinary declared Pascal. **Every value row passed
while it did that**, because the write and the read share the wrong stride:
they agree with each other outside the record, and the field reads back exactly
what was stored. frankB's control on the pinned binary:
`stride 0  fits 0  guard 0  tail 1  values 11`.

**Checked against this umbrella's two closed layout members, and the news is
mostly good.** Neither is value-only:
`bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets` asserts
relationally, CALLS through the pointer with two receivers so a wrong-offset
`Data` read cannot pass by landing on the only object present, and carries a
pinned-i386 positive control. `bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more`
asserts against a measured stride with `FillChar`/`Move` rows and a control
that drives the size rows to 0. Both are better instrumented than the trap
requires.

**But the blind spot survives in the instrument they share.**
`test/test_sizeof_stringn_matches_storage.pas:46` measures
`stride := LongInt(p1) - LongInt(p0)` — the layout engine's own answer — and
every row then asserts `SizeOf(x) = stride`. That is an **internal-consistency**
invariant: it proves `SizeOf` agrees with the layout engine, and is structurally
incapable of noticing that **the layout engine is wrong in the same direction**.
Under frankB's bug both sides move together and all seven rows stay green. The
one row carrying an absolute bound, `record  SizeOf(TRc) >= stride + 1`
(line 61), is a `>=` and therefore cannot fail upward — a record bloated to 264
by an over-strided field satisfies it.

**What the missing dimension is, in one sentence:** every assertion here is
relative, and nothing asserts that the aggregate's last element ends INSIDE the
aggregate. frankB's `guard` and `tail` rows are that instrument — a declared
neighbour, written before and read after, which fails when the stride walks past
the end regardless of what the values say.

### VARY THE CAPACITY BETWEEN NEIGHBOURING DECLARATIONS — a same-cap neighbour hides the bug

Third instrument failure for this umbrella, from frankB closing
`bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes`
(2026-09-02), and the sharpest of the three because the test looks thorough.

`P(var a: array of string[10])` was CORRECT. `P(var a: array of string[10];
t: LongInt)` strode 263. **The FOLLOWING parameter's type decided the
PRECEDING one's layout** — `AllocParam` reads `LastTypeStrCap`, a parse-window
return channel, from the ALLOCATION loop, which runs only after every
parameter's type has been parsed.

**The hazard: with `t: string[10]` following, the wrong answer and the right
answer COINCIDE.** A test that puts a same-capacity frozen-string neighbour
after the array is green against the bug. So a test does not merely need a
frozen string present — it must **VARY the capacity between neighbouring
declarations**, or the parse-window carry-over is invisible.

That generalises past this bug to anything in this umbrella tested with
neighbouring declarations: two fields, two parameters, two locals of the same
capacity cannot distinguish "each read its own" from "the second's value was
used for both."

**Checked for siblings, and the parameter path is clean.** The `LastType*`
parse-window family has **27 members**; `pasparser_proc.inc` stages **11** into
per-param `ptypes*` columns (Rec, SetEnum, Enum, StrElemTk, PtrElemTk,
PtrElemRec, PtrDepth, PtrBaseTk, PtrBaseRec, ProcSig, and now StrCap). Of the
remaining 16, **none is read in the parameter allocation loop** — the only
other appearance in that file is `LastTypePointerStrElemTk` at line 1205, which
is the RETURN type, parsed once rather than per-parameter. So capacity was the
last unstaged member on the PARAMETER path, and there is no fifth instance
waiting there.

**Residual, and it has an owner: this checked ONE path.** The bug shape is
"read a parse-window global outside its window", and parameters are one site
among several — frankB found three distinct causes across four sites for this
one ticket. Record fields, array elements and the pointer-element carriers were
not swept. Whoever next touches a `LastType*` reader outside `pasparser_proc.inc`
owns that question.

### A PINNED CONTROL IS ONLY A CONTROL UNTIL THE NEXT PIN

Three members of this umbrella rest on a pinned-compiler positive control, and
frankB hit the failure mode directly (2026-09-02): it re-ran its own pinned
control and the bug showed as GONE. Nothing had regressed. `make pin` had run,
**v401 landed carrying frankB's own `SizeOf` fix**, and the "old" compiler it
was controlling against was now a new one. **Nothing in the invocation names
which version answered.**

So the precondition has two halves, and the second one expires:

1. `git diff --stat` touches only what the pin freezes. A pin freezes the
   BINARY, not `lib/rtl/**` or `lib/crtl/**`, which it reads live from the
   working tree.
2. **Re-assert `git merge-base --is-ancestor <your fix> <the pin commit>` at
   the moment you QUOTE the control**, not when you first ran it.

Half 1 is a property of your change and is stable. Half 2 is a property of the
world and goes stale without erroring — the control keeps running and keeps
printing a verdict, about a different compiler.

**CHECK THE PINNED TREE, NOT THE PIN COMMIT — they are different commits and
the gap is not empty.** A pin commit is always a DESCENDANT of the tree it
pins, so `chore(stable): pin v401` (`766b99f98`) is not the tree the pinned
binary was built from; that is `07d196aa4`, and **four commits separate them**.
Ancestry against the pin record therefore answers about a tree slightly ahead
of the binary. This is the same defect Track T filed as
`bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names` (prio 70)
— `verify_pin()` has it too, which is why every pin grade in tstate history
grades the OUTGOING binary under the INCOMING one's name. The coordinator made
the identical mistake writing the first version of this table.

**Checked 2026-09-02 against the pinned TREE `07d196aa4` (v401, binary
`1eec4dc5e0a7`), and all three hold — as of that moment and no longer:**

| control | fix commit | in the pinned tree? |
| --- | --- | --- |
| method-pointer, pinned i386 2 rows FAIL | `9eaca27ca` | no — control valid |
| char-into-shortstring, pinned refuses on 3 targets | `e4cba526a` | no — control valid |
| frankB's record-field stride/guard rows go 0 | `ir.inc` fix, unlanded | no — control valid |

(The conclusions were unchanged by the correction — none of the three sits in
the four-commit gap — but the reference point was wrong and would have given a
false VALID for anything that did.)

**That table is a timestamp, not a property.** The next `make pin` can
invalidate any row in it without touching this file, and the ticket quoting the
control will still read as verified. Re-run the ancestry check rather than
citing this table.

**So, for any member of this umbrella still open or being verified:** a green
built only from `SizeOf == stride` rows is evidence about agreement between two
numbers, not about either being right. Add one absolute row. This is CLAUDE.md's
"a guard that cannot fail is not a guard, and it prints PASS", in the specific
form this umbrella keeps producing — which is unsurprising, since a subject
whose whole defect is "four functions disagree about a size" will naturally be
tested by comparing sizes to each other.

Not a defect claim against either closed ticket, and neither is reopened here.

**The UMBRELLA carries `blocked-by: <member>`. A member must NOT carry
`blocked-by: <umbrella>`.** Written the second way it means what it says — the
ticket is blocked BY the umbrella — and `ready` drops it entirely, which is the
exact opposite of joining the queue. Measured 2026-09-02: three tickets were
wired backwards (this coordinator told frankb-a9 to do it, and did it itself on
the set split); all three vanished from `ready` at p75 and nothing errored.
Add your slug to the list above instead.

## What the three C members actually were (measured 2026-09-02, all three closed)

`bug-c-a-file-scope-pointer-to-array-crashes-on-indexing` (`7d6559cd3`),
`...-struct-field-answers-the-pointer-size` (`1769ac004`) and
`...-reaches-a-pointee-through-one-spelling-only` (`536a3e2d0`).

**They were not three bugs.** Two of them are ONE arm in two scopes: the
parenthesised-declarator path, written for function pointers — whose pointee
genuinely has no type — and reached by `int (*p)[4]` as well, because
`ParseCDeclType` parks the name in `CTypeFnPtrName` for both shapes. It
recorded no pointee at file scope and none on a struct field; the local path
records one and has always worked. Three copies, one of them right.

**This umbrella's framing survives but its C example did not.** The recorded
`sizeof(*s.fp)` = 8 "the arm never firing at all" was already stale: it
answered **4**, and 4 is not the element size either — it is
`TypeStorageSize(tyUnknown)`, i.e. nothing recorded. The `int` spelling cannot
tell those apart, because the unknown default equals `sizeof(int)`. It took
`double (*dp)[4]` answering 4 rather than 8 to separate them. **Every C row in
this family that is spelled with `int` is a guard that cannot fail**, and the
same trap sits in the Pascal members: a size row whose expected value
coincides with a default proves nothing. Rows here must use a type whose size
is not 4 and not `sizeof(void*)`.

The third was a different mechanism and worth separating from the other two:
the token walk `CSizeofDescriptorWalk` answered `TypeSlotSize(tyUnknown)` and
reported success, while the general expression path — which typed the operand
correctly all along — was locked out because the walk had consumed the operand.
That is not "too few parameters"; it is a PARALLEL path answering where it
should decline, and the residue is banked as
[[bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown]]. It belongs to this
umbrella's thesis all the same: it is one more thing that was asked how big a
type is and answered.

One new column was needed: `UFldPtrElemArrLen`, the field twin of
`SymPtrElemArrLen`. That is shape 1 exactly — `TypeStorageSize(kind, recId)`
cannot express "array pointee of extent N", so the extent had to be threaded to
the caller instead. **A fifth oracle was NOT added**; the existing readers were
given the parameter they were missing.

## One member was removed, deliberately

`bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so` was
wired here and is **unwired as of 2026-09-02**, parked to `rainy-day/` by the
owner. It was always the odd member — the one case where the size oracle is
NOT the defect, since `TypeSlotSize(tySet)` is honest about what we build.
With the width chosen, it cannot be delivered by fixing the oracles, so
leaving it as a blocker would make this umbrella permanently unreachable.
**A parked member blocks the goal forever; that is why the edge is gone rather
than merely annotated.**

## Notes

- **`prio: 75` was set by the coordinator, not the owner** — he said the SizeOf
  bugs are worth doing and to work them as a group. It is above
  `feature-pascal-typed-and-untyped-files` [p70], which cannot be correct until
  layout is, and below the two live p85 umbrellas. Change it freely; per
  CLAUDE.md the umbrella number is the one a human sets.
- Members keep their own tracks and gates. This spans A, C, N and P by
  construction — that is the finding, not an accident of filing.
- frankb-a9 has a `string[N]` ticket drafted from the measurement above; wire it
  here when it lands.

## A C instance the attempt found, 2026-09-04 (`67708bbe8`, fixed)

Not a new blocker — recorded because it is evidence about the class rather than
about one ticket. `sizeof` of an ARRAY FIELD reached through a parenthesis, a
cast or a deref answered the **element** size: `sizeof((sp)->m)` on `char m[65]`
was 1 while `sizeof(sp->m)` was 65. **A parenthesis decided the answer**, and
the mechanism is this umbrella's own: two paths answer "how big is this", and
only one of them knew that `sizeof` is not a USE so an array does not decay.
The general-expression fallback sized by the node's RESULT type, which for an
array expression is its element type.

**It was found by attempting busybox, not by probing `sizeof`.** uname.c
declares `char processor[sizeof(((struct utsname*)NULL)->machine)]` twice, so
its info struct came out 402 bytes instead of 530 with three fields at
consecutive offsets, and `uname -p` printed `uu`. No diagnostic; the `offsetof`
table was correct about the layout it had been given. 516 `--help` differential
cases never reached it — the real-argument cases caught it in one run.

Fixed by extracting the rule from the arm that already had it
(`CSizeofRecFieldBytes`) rather than adding a third copy — the same
delete-a-case shape this umbrella argues for.
