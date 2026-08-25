---
summary: "Populate pointer-element-type metadata consistently (additive, fallback-preserving) — kill the recurring silent PChar/WideChar-conversion class at its source. SLICE 1 LANDED 2026-08-21 (decl-side population + the AN_VIRTUAL_CALL/AN_INTF_CALL reader gap); slices 2-3 (node-side storage, WideChar) remain"
type: refactor
prio: 45

owner: claude-A
---

# Populate pointer-element metadata consistently — the low-risk fix for the conversion class

- **Type:** refactor / data-completeness (Track A — `parser.inc` registration + node
  creation, `ir.inc` predicates). **Additive and fallback-preserving — NOT a big-bang
  rewrite.**
- **Status:** done
- **Opened:** 2026-07-17, from a user observation ("we keep special-casing AnsiString,
  keep finding issues"). **Re-scoped 2026-07-18** after the user correctly pointed out the
  sane, low-risk shape: *just store the pointer type; C already does it.*

## The observation, and the corrected diagnosis

The recurring PChar/WideChar→string bugs are **one root**, and it is NOT "shape
enumeration is inherently wrong" — it is **"the element-type metadata is not populated in
every creation path."**

- The reader predicates (`IsNodePChar`, `NodeIsWideCharVal`) key on stored data — e.g.
  `ProcRetPtrElemTk[procIdx]` (a proc's return pointer-element type). That field already
  exists.
- The bugs were **registration paths that forgot to set it**: the external-directive path
  and the `$proctype` signature path each re-implemented registration and dropped the
  return-element fields, so the predicate read `tyUnknown` and skipped the conversion →
  silent garbage / segfault.

C proves the pattern is fine: `cparser.inc` has the *same* shape-walk
(`CNodePtrElemRec`), but at node creation (`cparser.inc:374`) it **computes once and
STORES** the element type on the node (`ASTSOffset` side-channel), so downstream reads are
a clean lookup. Mirror that.

## Instances (all the SAME pattern; the point-fixes are slices of this)

- [[bug-pascal-ansistring-cast-of-cdecl-call-result]] — external decl dropped
  `ProcRetPtrElemTk` (FIXED, `33f0d555`).
- [[bug-pascal-ansistring-cast-of-fnptr-call-result]] — `$proctype` sig dropped it +
  `IsNodePChar` missed `AN_CALL_IND` (FIXED, `9118a760`).
- [[bug-pascal-widechar-var-to-string-segfault]] / [[bug-pascal-widechar-var-to-string-other-contexts]]
  — `NodeIsWideCharVal` cast-only, missed the tyUInt16 var shape (assign + concat FIXED,
  `19fbf64a`/`6ea2e6ff`; arg residual open).
- The copy-pasted conversion block → one `WrapPCharToString` builder (`7e4bebc0`).
- **Not-yet-fixed dropped-field sites:** `parser.inc` `18447`/`19128`/`19649` — method-decl
  registrations that set `BodyAddr` + params but never `ProcRetPtrElemTk`. Harmless when a
  method has a body (the impl re-registers via the normal path), but a decl-only PChar
  method (abstract/interface/virtual-via-base) would mis-lower `AnsiString(ref.Method())`.

## Status after the reachable-instance audit (2026-07-18)

**The reachable instances are all FIXED** (the 5 point-fixes above were the slices).
Verified: instance-method AND class-method PChar-result casts (`AnsiString(o.GetP())`,
`AnsiString(TObj.GetPC())`) work — a method **with a body** resolves to the impl's
procIdx, which the normal registration path populates. So the 3 method-decl sites
(`18447`/`19128`/`19649`) are **defensive-only and NOT reachable by a normal call** — no
failing test is constructible. Deliberately **not** patched: adding metadata there would
be self-host-identical with no test, and would set a shared field from a possibly-stale
`LastTypePointerElemTk` that cannot be verified — which violates the "added data must be
correct" rule. Leave them until a real reachable case appears.

Net: **do-with-a-test-when-needed.** This ticket is now forward insurance + documentation
of the pattern, not a list of open bugs. The bleeding is closed.

## The plan — additive, fallback-preserving, incremental (LOW RISK)

The whole reason this is safe: **add a stored fast-path, keep the old shape-walk as a
fallback.** A reader that consults stored metadata first and falls back to the existing
enumeration can only ever *add* recognitions (fix a missed shape) — never remove one. It
is impossible to regress by construction.

1. **Finish the proc side (first slice, do now).** Set `ProcRetPtrElemTk` (+ the other
   return-element fields) at the 3 method-decl registration sites so *every* proc
   registration records it — matching the external/`$proctype` fixes already landed.
   Purely additive; self-host byte-identical unless it fixes a real case.
2. **Node side (later).** Store the pointer-element type on pointer-typed nodes at
   creation (C's store-on-node pattern); have `IsNodePChar` read the stored value first,
   fall back to the shape-walk if unset. Populate creation sites incrementally.
3. **Fold WideChar in.** Same treatment (WideChar==tyUInt16 has no marker; the safe
   contexts are already handled — see [[project_string_conversion_shape_blindspot_pattern]]).

Each step: self-host byte-identical + a targeted regression + a fuzz pass. No step is a
sweep of all 688 `tyString` branches — that count is just the *evidence* of the sprawl,
not a to-do list.

## Why not just keep point-fixing?

You can, and it's safe — each new shape found by fuzzing gets a one-line populate. This
ticket is the *systematic* version: audit the creation sites once so future shapes are
covered as the data is populated, instead of waiting for a fuzzer to draw blood on each.
Do it at the pace that suits; the bleeding is already stopped.

## Acceptance

- Every proc-registration path sets `ProcRetPtrElemTk` (grep audit); a decl-only PChar
  method cast works.
- `IsNodePChar` prefers stored metadata with the shape-walk as fallback (additive).
- The known instances stay fixed; a fuzz pass finds no new PChar/WideChar-conversion
  divergence.
- Gate: `make test` + self-host byte-identical per slice.

## Explicitly NOT

- **Not** a big-bang rewrite of the conversion sites or the 688 `tyString` branches.
- **Not** removing the shape-enumeration walks — they stay as the fallback.
- **Not** reworking the managed-string runtime/ABI — this is about *where the compiler
  records/reads the pointer element type*, nothing about how strings are represented.

## Slice 1 landed 2026-08-21 — and the audit's "not reachable" was wrong

The 2026-07-18 audit closed this ticket's first slice as *"defensive-only and NOT
reachable by a normal call — no failing test is constructible"*, on the reasoning
that a method with a BODY re-registers through the normal path. That reasoning is
right and the conclusion did not follow: it covers every method **that has an
implementation**, and the two shapes whose call resolves to the DECL and never to
an implementation — an **abstract** method reached through the base class, and an
**interface** method reached through the interface — have none to fall back on.

Constructed in one try, and it is a silent wrong VALUE, not a crash:

```pascal
TBase = class function GetP: PChar; virtual; abstract; end;
IGet  = interface function GetP: PChar; end;
...
s := AnsiString(b.GetP);    { FPC: 'abcde'   pxx: '' }
s := AnsiString(g.GetP);    { FPC: 'abcde'   pxx: '' }
```

**Both halves were needed, which is the part worth recording.** Populating the
metadata at the three decl sites changed nothing on its own, because the READER
was shape-blind in the same way the ticket describes:

1. `pasparser_decl.inc` — the record-method, interface-method and class-method
   decl registrations now capture `LastTypePointerElem*` right after the return
   type is parsed (same place `mRetRecId` is captured) and store
   `ProcRetPtrElemTk/Rec`. This is the "finish the proc side" slice, verbatim.
2. `ir.inc` — `IsNodePChar` enumerated `AN_CALL` and `AN_CALL_IND` only. All FOUR
   call node kinds carry a `Procs[]` index in `IVal` (`AN_VIRTUAL_CALL` keeps the
   slot in `ASTRight`, `AN_INTF_CALL` the IMT slot in `ASTSOffset`), so the
   virtual and interface shapes now read the same way.

**A second bug fell out of the same enumeration**, and it is NOT interface- or
PChar-specific: `IRPointerStride`'s call arm read the element KIND and never the
element's RECORD id, so for `function P: PRec` the tail computed
`RecSize(REC_NONE)` = the pointer size. `P2 - P0` over a 24-byte record answered
**6 instead of 2**, and `P0 + 2` landed inside element 0 — on plain functions as
much as virtual ones, on `pinned` and on HEAD. Every other arm of that function
sets the (kind, rec) pair together; this one set half. Fixed here rather than
filed, because it is the same dropped-field pattern in the same predicate family
and the test was already written.

`test/test_pchar_result_decl_only_method.pas`: **9 / 9**, identical to FPC 3.2.2
on the same source, natively and under qemu on aarch64 / arm32 / i386 / riscv32.
`pinned` scores **1 / 9**. Gate: `make compiler/pascal26` (fixedpoint) +
`tools/gate.sh quick` GREEN.

**Still open, unchanged**: slice 2 (store the pointer-element type on pointer
NODES at creation, C's pattern, shape-walk as fallback) and slice 3 (fold
WideChar in). The ticket stays open for those; this closes slice 1 and the
reader-enumeration gap it depended on.

## Slice 2's first real instalment, 2026-08-21 — found by a 84-shape differential

The ticket's own acceptance line asks for "a fuzz pass finds no new
PChar/WideChar-conversion divergence". Ran the equivalent, deliberately as a
CROSS PRODUCT rather than a list: 12 PChar SOURCES (plain function, called
function, record field, array element, local var, pointer arithmetic, proc-typed
value, class method, instance method, virtual, abstract-through-base,
interface-through-interface) × 7 CONTEXTS (`AnsiString()` cast, assign, concat,
`WriteLn`, a `const s: AnsiString` argument, `Length`, `=`), each a program of
its own, each diffed against fpc 3.2.2. **18 of the 84 diverged.** All 18 are
now identical to FPC, from two fixes.

**1. `+` had no PChar conversion at all — and was wrong in two unrelated ways.**
Which one you got depended on the OTHER operand, which is why it never looked
like one bug:

| expression | pxx before | FPC |
| --- | --- | --- |
| `'xy' + p` | `xy?` — one garbage byte | `xyabcde` |
| `'x' + p` | `` (empty) | `xabcde` |
| `p + 'tail'` | `?tail` | `abcdetail` |
| `c + p`, `p + c` (char VAR) | `` (empty) | `Qabcde` / `abcdeQ` |
| `p + 1` | `bcde` | `bcde` ✓ |

With a multi-char literal the node typed as a string concat and the concat
codegen read the POINTER as string data. With a ONE-char literal — `tyChar`, an
ordinal — the `ordinal + pointer` arm claimed the expression first and it became
pointer arithmetic: the pointer moved 120 bytes and the result was ''. Same
expression shape, two different silent wrong answers, no diagnostic in either.

Fixed by normalising the OPERAND in `pasparser_expr.inc`, immediately next to
the WideChar wrap that was already doing exactly this — not by adding a third
arm to the typing chain below it. Downstream then sees two string operands and
needs to know nothing about PChar. The rule matches FPC and was measured, not
assumed: a char/string operand means concat, an integer operand stays pointer
arithmetic. Excluded in C mode, where `p + 'x'` genuinely IS arithmetic.

**2. An array-of-PChar ELEMENT was an unrecognised SHAPE.** `IsNodePChar`
enumerated cast / ident / field / call / binop and had no `AN_INDEX` arm, so
`arr[0]` was wrong in EVERY context at once — cast, assign, concat and `=`
produced '', `Length` answered 0, `WriteLn` printed the pointer as a decimal
number, and `Show(arr[0])` was refused outright with *"argument types:
(Pointer)"*. That spread is the tell: one broken context is a context bug, seven
broken contexts is an unrecognised shape.

Note what was NOT wrong: `AllocArray` and `AllocDynArray` both already record
the element pointee in `Syms[].PtrElemTk`. **The metadata was there and only the
reader was missing** — the mirror image of slice 1, where the reader was right
and the metadata was missing, and together they are the argument for this
ticket's whole framing.

`test/test_pchar_concat_and_array_element.pas`, 18 lines, byte-identical to fpc
3.2.2 on the same source. `pinned` does not compile it (the `const AnsiString`
argument is refused). Gate: `make compiler/pascal26` fixedpoint +
`tools/gate.sh quick` GREEN.

**Still open**: the node-side storage that is slice 2 proper (this instalment
extended the reader instead), slice 3 (WideChar), and `pp[i]` where `pp: PPChar`
— an element of a POINTER to pointers, which the new arm deliberately does not
cover because `IsArray` is false there and no differential row exercised it.

## The WideChar half of the same differential, same night

Same method, 6 WideChar sources (local var, record field, array element,
function result, `WideChar(n)` cast, and an ASCII local) × 5 contexts (assign,
concat either side, `const AnsiString` argument, `WriteLn`). **30 programs, 30
divergences** — and they collapse into exactly three facts:

1. **A hard COMPILE ERROR on code FPC accepts**, fixed here. A WideChar
   reaching a string context in a program containing no `WideChar(` CAST
   anywhere failed with *"WideChar->string conversion: __pxxWideCharToUTF8
   helper not loaded"*. The token pre-scan pulled the builtin unit for a
   `widechar(` cast only, on the reasoning written into the comment beside it:
   *"unlike WideChar it [UCS4Char] is a declarable TYPE"*. `var w: WideChar` is
   as declarable as `var c: UCS4Char`, so the premise was simply false. It
   survived because the failure needs the ABSENCE of a construct — every
   existing WideChar test happens to write the cast, and no test asserts an
   absence by accident. Now pulled on any mention, exactly as UCS4Char already
   was. `test/test_widechar_no_cast_in_program.pas`, identical to FPC; pinned
   does not compile it.

2. **`WriteLn(w)` prints the ordinal** — 65 for `'A'` where FPC prints `A`.
   Filed as [[bug-a-writeln-of-a-widechar-prints-its-ordinal]] rather than
   patched: WideChar has no type kind of its own (it collapses to `tyUInt16`),
   and the other contexts only work because "any tyUInt16 in a string context"
   is a safe guess THERE — `WriteLn` cannot guess, because `WriteLn(someWord)`
   must print the number. The fix is a `tyWideChar` kind, mirroring the
   `tyUCS4Char` that exists for this exact reason, and a new kind touches
   shared `defs.inc` numbering. Diagnosis banked, not half-applied.

3. **A non-ASCII code unit is 2 bytes under pxx, 1 under FPC** — pxx encodes
   UTF-8, FPC converts through the system codepage. Consistent at every
   conversion site, deliberate, not a defect. It belongs in user-facing docs,
   and is recorded in the ticket above so the next reader of this diff does not
   re-file it.

## Log
- 2026-08-21 — slice 1 landed. Note for whoever reads the 2026-07-18 audit next:
  "no failing test is constructible" was a claim about a search that stopped at
  methods with bodies. When a ticket says a case is unreachable, the cheap check
  is to try to reach it.

## Slice 3's premise expired on 2026-08-22 — WideChar now HAS a marker

Slice 3 reads *"Fold WideChar in. Same treatment (WideChar==tyUInt16 has no
marker; the safe contexts are already handled)."* That parenthesis is no longer
true. [[bug-a-writeln-of-a-widechar-prints-its-ordinal]] gave WideChar its own
type kind — **`tyWideChar`, kind 31** — for the reason this ticket is about: a
node-level marker is lost through a variable, and `WriteLn` is the one context
where the "any tyUInt16 in a string context must be a widechar" fallback cannot
be used, because `WriteLn(someWord)` must print the number.

So the WideChar half of this refactor got what it wanted, by the route
`tyUCS4Char` and `tyBool8` took rather than by node-side storage:

- `NodeIsWideCharVal` now answers on **either** the `-3` cast marker **or**
  `ASTTk = tyWideChar`, so it is already the "prefer stored metadata, keep the
  shape-walk as fallback" shape this ticket asks for — one level up, on the type
  kind rather than on a node side-channel.
- the `...or the operand is tyUInt16` clauses beside its call sites were
  deliberately LEFT IN, which is exactly this ticket's additive rule.
- `PWideChar`'s element type is `tyWideChar` too, so `p^` carries it.

Measured after that change: 63 WideChar programs, source shape × context, against
fpc 3.2.2 — every remaining divergence is the deliberate UTF-8-vs-codepage
encoding one, none is a missed recognition. The **"arg residual open"** noted
above against [[bug-pascal-widechar-var-to-string-other-contexts]] is closed: a
`w: WideChar` variable bound to a string parameter converts.

**What this leaves for slice 3:** re-scope it, or drop it. The remaining question
is whether PChar wants the same treatment — a `tyPChar` kind rather than
node-side element storage — which is a genuinely different call, because unlike
WideChar a PChar's element type is variable (`PWideChar`, `PByte`, `PInteger`…)
and a kind per pointee does not scale. That asymmetry is worth stating in the
ticket before anyone starts, since "do what WideChar did" is now the obvious and
probably wrong instinct.

## The acceptance line's differential, run again 2026-08-24 — and what it found

The acceptance line asks that "a fuzz pass finds no new PChar/WideChar-conversion
divergence". Ran the PChar half again as a cross product: **7 sources** (a PChar
var, a static array element by constant and by variable index, a dynamic array
element, a record field, a function result, pointer arithmetic) × **7 contexts**
(`AnsiString()` cast, assign, `WriteLn`, `'x' +`, `Length`, `=`, `<>`), each its
own program, each diffed against fpc 3.2.2.

**Four diverged, and none of them was where this ticket was looking.** They are
recorded and fixed under [[bug-p-a-string-literal-assigned-to-a-pchar-is-empty]]:
`p := 'literal'` stored the literal's HANDLE (so `WriteLn(p)` printed nothing), a
one-character literal stored the ORDINAL and segfaulted, and `p = 'alpha'`
compared POINTERS. The cross product is now 49/49 identical to FPC.

Two of those three fixes are this ticket's own pattern one construct over, which
is why they are noted here and not only there:

- the `+8` character-data skip existed at the call-ARGUMENT boundary and not at
  the ASSIGNMENT boundary — **one marshalling rule applied at one of its two
  boundaries**, the exact shape of slice 1's "the metadata was there and the
  reader was missing";
- the comparison wrap was added at the RELATIONAL level next to the one this
  ticket already added at the ADDITIVE level, by normalising the OPERAND rather
  than growing an arm in the comparison chain — the same move, same reason,
  stated in the same words.

### The `^PChar` residual, now diagnosed rather than just listed

The note above says *"`pp[i]` where `pp: PPChar` … the new arm deliberately does
not cover"*. Measured properly this time, and it is sharper than "not covered":

| context, on `q^` / `q[0]` / `(q+1)^` where `q: ^PChar` | result |
| --- | --- |
| `AnsiString(q^)`, `s := q^`, `Length(AnsiString(q^))` | correct |
| `WriteLn(q^)` | prints the POINTER as a decimal number |
| `'x' + q^` | empty string |

The three that "work" are **not** recognition. `AnsiString(<any pointer>)`
treats its operand as a PChar unconditionally — measured: `AnsiString(pi)` with
`pi: ^Integer` and `AnsiString(rawPointer)` both render the text. So the cast
and assign contexts are right by a blanket rule, and `WriteLn` and `+` are the
two contexts that correctly REFUSE to guess, because `WriteLn(somePointer)` must
print a number.

**Why `IsNodePChar` cannot answer it today, and why that is slice 2 exactly.**
For `q: ^PChar`, `Syms[q].PtrElemTk` is `tyPointer` — the pointee is a pointer,
and the char-ness one level further in is recorded nowhere. `NodePtrElem` has no
`AN_DEREF` arm either, and adding one would only return `tyPointer` again. The
metadata is genuinely absent, not merely unread: this is the first shape in this
ticket's history where that is true, and it is precisely the case node-side
storage at creation (slice 2 proper) exists to serve — at `q^`'s creation the
alias `^PChar` is in hand and PChar's own element type is one lookup away.

So the residual is not a missing arm to be added cheaply. Left open, with the
diagnosis banked rather than a half-fix applied.

### Slice 3's re-scope, still owed

Unchanged from the 2026-08-22 note: WideChar got a real type kind and no longer
wants node-side storage, and whether PChar wants a `tyPChar` kind is a genuinely
different call because a PChar's pointee varies. The `^PChar` finding above is
the first concrete argument for node-side storage over a kind, since a kind
cannot express "pointer to (pointer to char)" without one kind per depth.

## Slice 2's node-side read, 2026-08-24 — and the ^PChar residual was the metadata after all

The `^PChar` residual above was recorded as *"the metadata is genuinely absent,
not merely unread"* and left for node-side storage. Both halves of that sentence
turned out to be wrong, and the way they were wrong is the point:

**The node-side storage this ticket's slice 2 asks for ALREADY EXISTS.** The
deref chain in `pasparser_lval.inc` computes, for every `x^`, the pointer levels
REMAINING and the ULTIMATE base kind, and writes them onto the deref node
(`ASTSOffset` = remaining depth, `ASTSLen` = base kind, `ASTIVal` = base rec).
It has been doing that all along. `IsNodePChar` simply never read it — so the
new arm is four lines: one level remaining over a char base IS a PChar.

**And the metadata WAS absent, one construct earlier than the ticket looked.**
`ParseTypeKind`'s builtin-pointer-name arms — the `BuiltinPtrNameElemTk` family
and `pchar`/`pansichar` — set the immediate pointee and **left depth and base
unset**, while the `^T` caret arm right above them builds a nested pointer by
adding one to *whatever its element reported*. So `^PChar` came out as depth 1
over a base of `tyPointer` instead of depth 2 over `tyChar`, and every predicate
that asks "how many levels, over what" got a wrong answer. Measured, not
reasoned: a new `PXXDBG=a.symptr:<name>` topic prints what a declaration
actually recorded, which is how a plausible story about node-side storage got
replaced by the field that was empty.

That topic is worth keeping — it answers this ticket's recurring question ("was
the metadata never populated, or never read?") in one run, and it is the exact
lesson of `devdocs/dev/debugging-playbook.md`: the first arm added here was
written against an ASSUMED symbol layout, compiled, and changed nothing.

### What that fixed, measured as a cross product

**72 programs** — 8 PChar sources (a var, `q^`, `q[0]`, an array element, a
record field, a function result, pointer arithmetic, and an element of an array
of `^PChar`) × 9 contexts (`WriteLn`, assign, concat on either side,
`AnsiString()`, `Length`, `=`, `<>`, a `const AnsiString` argument), each its own
program, each diffed against fpc 3.2.2. Before: 15 diverged. After: 7, all of
them the one shape below.

Three fixes, and each is this ticket's own pattern:

1. **The dropped depth/base at the two builtin-pointer-alias arms** — the
   registration half.
2. **`IsNodePChar` reads the deref node's stored (remaining depth, base)** — the
   reader half, against storage that already existed. `q[i]` over a `^PChar`
   goes to the symbol instead, since the index path stores nothing.
3. **`Length(p)` over a PChar answered with the ADDRESS** — while
   `Length(arrayOfPChar[0])` on the line beside it answered 5. Fixed by
   normalising the OPERAND at the Length site (wrap to string), the same move
   already made at the concat, relational and argument boundaries, rather than
   growing a pointer arm inside the Length lowering. Note the shape of the bug:
   one concept, correct through one spelling and wrong through another.

**And `PPChar` was not a known type name at all** — `var p: PPChar` failed with
*"unknown type"*, on a compiler whose C interop is a headline feature and whose
users write `char**` as PPChar (argv, an environment block, a NULL-terminated
name table). Two levels over a char base, declared beside `pchar`, and the three
fixes above then make every context answer for `p^` and `p[i]`.

`test/test_pchar_pointer_to_pchar.pas`, 16 rows, byte-identical to fpc 3.2.2
natively and under qemu on i386 / aarch64 / arm32 / riscv32. `pinned` does not
compile it. Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.

### The one shape still open: an element of an `array of ^PChar`

`qa[0]^` where `qa: array[0..1] of ^PChar` is wrong in all 7 non-blanket
contexts, and unlike the residual it replaces, this one really is missing
metadata. An array symbol records its element's immediate pointee
(`Syms[].PtrElemTk`) and **nothing about the element's own depth or base** —
there is no `SymElemPtrDepth`. So the deref chain's AN_INDEX branch has nothing
to propagate onto the deref node, and the node-side reader above correctly
declines.

Adding a pair of parallel arrays would work and is the wrong shape: the fix is
an element TYPE REFERENCE rather than another two parallel fields, which is
exactly what [[feature-a-typeref-migrate-consumers]] is for (`SymTR` already
carries `PtrBaseTk` for the symbol itself). Left open and tied there rather than
bolted on — the ticket has enough parallel-field pairs already.

## The last open shape closed, 2026-08-24 — and the diagnosis above it was wrong

The section before this one closes with:

> `qa[0]^` where `qa: array[0..1] of ^PChar` ... **unlike the residual it
> replaces, this one really is missing metadata.** An array symbol records its
> element's immediate pointee (`Syms[].PtrElemTk`) and **nothing about the
> element's own depth or base** — there is no `SymElemPtrDepth`.

That is wrong, and it is wrong in the same direction the ticket has now been
wrong twice: **the metadata was there and the reader was missing.**

`AllocArray` (`compiler/symtab.inc`) already does, for `elemType = tyPointer`:

```pascal
  SymPtrDepth[SymCount]   := LastTypePointerDepth;
  SymPtrBaseTk[SymCount]  := LastTypePointerBaseTk;
  SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
```

An array symbol is not itself a pointer, so those three slots are free and
`AllocArray` parks the **element's** depth and ultimate base in them. Measured,
not read:

```
PXXDBG a.symptr qq kind=17 isArray=TRUE elemType=17 depth=2 ptrElemTk=17 baseTk=3 baseRec=0
```

`depth=2` over `baseTk=3` (tyChar) is precisely "pointer to pointer to char".
`SymElemPtrDepth` was never needed.

### The probe had a hole exactly where the question was

Getting that one line took extending `PXXDBG=a.symptr` first: it was called
from `AllocVar` only, so for an ARRAY of pointers — the one shape it was written
to diagnose — `a.symptr:*` printed every symbol in the program **except** the
one under investigation, and the silence read as an answer. It is now one
`DbgReportSymPtr` called from all five `Alloc*` tails, and it reports `isArray`
and `elemType` so the array case's field-reuse is visible rather than
confusing.

That is `devdocs/dev/debugging-playbook.md` twice over in one ticket: the
previous instalment recorded *"the first arm added here was written against an
ASSUMED symbol layout, compiled, and changed nothing"*, and this one would have
repeated it — a new `SymElemPtrDepth` array, populated, read, and identical
output, because the value was already sitting in the field beside it.

### The fix

Four lines in the deref chain's `AN_INDEX` arm (`pasparser_lval.inc`), mirroring
the `AN_IDENT` arm four lines above it, which already read exactly this triple.
The `AN_INDEX` arm read the immediate pointee and stopped.

### Measured, as a cross product

**88 programs** — 11 PChar sources (a var, `q^`, `q[0]`, `qa[0]^`, `qa[1]^`,
`qd[0]^` over a *dynamic* array of `^PChar`, `GetQ^`, a record field, a static
array element, a dynamic array element, pointer arithmetic) x 8 contexts
(`WriteLn`, assign, concat on either side, `AnsiString()`, `Length`, `=`, `<>`),
each its own program, each diffed against fpc 3.2.2.

```
pinned  : 36 diverged
HEAD    :  5 diverged
```

**All five remaining are one new shape**, not a residue of this one: a FUNCTION
returning `^PChar`. Filed as
[[bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape]] —
and that one genuinely IS missing metadata, verified by grep this time rather
than assumed: `ProcRetPtrElemTk`/`Rec` are the immediate pointee and there is no
`ProcRetPtrDepth`, so `PChar` and `^PChar` are indistinguishable as return
types. Deliberately **not** fixed here by adding two more parallel arrays — this
ticket's own text rules that out — and routed to
[[feature-a-typeref-migrate-consumers]] lane 4, which is 10 write sites and 7
read sites.

That routing surfaced a **blocker inside the TypeRef design** worth stating
here, because it blocks the lane and not the bug: `TTypeRef` has
`PtrBaseTk`/`PtrBaseRec` and `DynDepth` (dynamic-array nesting) but **no pointer
depth field**, so as declared it cannot express "pointer to (pointer to char)"
any better than the pair it replaces. Adding `PtrDepth` is additive and looks
clearly right, but it changes a shared type mid-migration.

### Test

`test/test_pchar_array_of_pointer_to_pchar.pas` + `.expected` (which IS fpc
3.2.2's output on that source), 12 rows over both a static and a dynamic array
of `^PChar` — two different allocators reaching the same arm. Byte-identical to
FPC natively and under qemu on **i386 / aarch64 / arm32 / riscv32**. `pinned`
gets four rows wrong. Wired into `test-core`.

**Gate:** `make compiler/pascal26` fixedpoint converged in one round; the 88-pair
differential; the four cross targets; `tools/gate.sh quick` GREEN.

## Resolved 2026-08-25 — the acceptance line re-run, the four walks made one

The acceptance line asks that "a fuzz pass finds no new PChar/WideChar-conversion
divergence". Ran it as two cross products, each program its own file, each diffed
against fpc 3.2.2:

| set | shape | before | after |
| --- | --- | --- | --- |
| the standing 88 | 11 sources x 8 contexts | pinned 45 diverged, HEAD 0 | **0** |
| 110 new | 10 NEW sources x 11 contexts (adding `Copy`, `Pos`, a `const AnsiString` argument) | 17 diverged | **0** |

The 88 were already clean at HEAD — the function-returning-`^PChar` shape that
closed the previous instalment as *"5 remaining, all one new shape"* is fixed, so
that residual is gone. The 110 found two new things, and both are this ticket's
pattern rather than new ones.

### 1. `(qa[0])^` — the fourth copy of the deref walk, and now there is one

The previous instalment named the problem without fixing it: *"four copies of
the pointer walk exist."* The parenthesised postfix tail in `pasparser_expr.inc`
was the small copy — it resolved the immediate pointee through `NodePtrElem` and
stamped **nothing**, no remaining depth, no ultimate base. So `(qa[0])^` over an
`array[0..1] of ^PChar` was wrong in every non-blanket context (WriteLn printed
the address, concat produced '', `Length` answered the pointer, `=` compared
pointers) while the identical **`qa[0]^`, one character to the left**, was
correct in all of them. One concept, correct through one spelling and wrong
through another — the fifth time that exact sentence has been written into this
ticket.

Extracted the 5-arm chain out of `ParseLValueAST` into **`ResolveDerefShape`**
and pointed both callers at it, rather than copying it a fifth time
(`devdocs/dev/normalise-dont-special-case.md`). Two things fell out for free:

- the parenthesised spelling gained the call-result, nested-deref and
  field arms it never had;
- the shared walk gained an **`AN_PTR_CAST`** arm — `PPC(raw)^` had no arm in
  EITHER copy and fell to the final else as `tyInteger`, while `NodePtrElem`
  read the alias's immediate pointee only. `AliasPtrDepth/BaseTk/BaseRec` were
  already populated; nothing read them. The metadata was there and the reader
  was missing, for the sixth time.

The `NodePtrElem` fallback is kept as the final else, so `(pc + 2)^` still reads
one char and not four bytes
([[bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced]]).

### 2. `Copy(p, 2, 3)` over a PChar was refused outright

*"Copy: dynamic-array Copy needs a dynamic-array first argument"* — on code fpc
accepts, and for **every PChar spelling at once**: a var, `q^`, `q[0]`,
`(qa[0])^`, `t^^`, an array element, a record field, a function result, a
`const PChar` parameter, an `out` parameter. That spread is the tell, and it is
the same one the array-element instalment recorded: one broken context is a
context bug, ten broken sources at one call site is an unrecognised **boundary**.

Fixed by normalising the OPERAND at the Copy site — literally beside the `Char`
-> string promotion already sitting there, and the same move already made at the
Length, concat, relational and argument boundaries. The string-Copy path below
needs to know nothing about pointers.

### A/B: no emitted byte moved

The extraction is a refactor on the path every Pascal dereference takes, so it
was checked as an A/B rather than by tests alone. Built the compiler from the
pre-change sources, then compiled the SAME sources with both binaries:

```
compiler/compiler.pas (37k lines, every construct)   BYTE-IDENTICAL
test_pchar_pointer_to_pchar, _concat_and_array_element,
_result_decl_only_method, test_ptr_untyped_deref,
test_pointer_{param,function_result,field}_keeps_its_depth,
test_builtin_pointer_cast_as_target                  BYTE-IDENTICAL (8/8)
```

### Test

`test/test_pchar_paren_deref_and_copy.pas`, 22 rows, `.expected` being fpc
3.2.2's own output — identical natively and under qemu on **i386, aarch64, arm32
and riscv32**. `pinned` does not compile it. Wired into `test-core`.

Gate: `make compiler/pascal26` fixedpoint converged in 1 round,
`tools/gate.sh quick` GREEN.

### Why this closes the ticket

Acceptance, line by line: every proc-registration path sets the return-pointer
fields (slice 1, 2026-08-21); `IsNodePChar` prefers stored metadata with the
shape-walk as fallback (slice 2, and the storage turned out to already exist);
the known instances stay fixed; and the fuzz-equivalent finds no new divergence —
**198/198**.

What is NOT done is slice 3, and it is not work: its premise expired twice (see
the 2026-08-22 note) and what remains is a design call — a `tyPChar` kind, node-
side storage, or neither now that the walk is one function. Filed as
[[decide-pchar-node-side-storage-or-a-pchar-type-kind]] (Track U) with a
recommendation, so the next reader of "slice 3, still owed" does not build a
`tyPChar` on the strength of "do what WideChar did".
- 2026-08-25 — resolved, commit f687061db.
