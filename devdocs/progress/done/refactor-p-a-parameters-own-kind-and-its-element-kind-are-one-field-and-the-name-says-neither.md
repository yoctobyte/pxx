---
slug: refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither
track: P
type: refactor
prio: 45
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
title: "`Params[j].TypeKind` means two different things depending on `IsArray`, and a caller that reads it alone gets a plausible wrong answer"
summary: "`Procs[pi].Params[j].TypeKind` is the parameter's OWN kind when `Params[j].IsArray` is False and its ELEMENT kind when True; the field name says neither, and five landed defects from three seats in one day came from a caller reading one half. DONE for the `pasparser_*` increment 2026-09-06 (frankB): raw readers there are now **0** (was 23 lines / 24 occurrences). THREE accessors in symtab.inc, not two — `ParamOwnKind` (tyUnknown when IsArray), `ParamElemKind` (tyUnknown when not), and `ParamStoredKind`, the raw field named to say it is the union. The third is what makes the refactor honest: most sites cannot be DECIDED without a behaviour change nobody has evidence for, so the choice was leaving raw reads a newcomer copies, or smuggling behaviour changes under a rename. `ParamStoredKind` is the absence of a decision, named and greppable. Seven decided conversions, each exact by construction; the rest annotated in place as deliberate-union (4) or suspect (12). ABLATION RUN: `ParamElemKind`'s refusal is load-bearing — removing it segfaults `ifclist.pas` in `run_fgl_corpus.sh`, which `--tier quick` does NOT see — while `ParamOwnKind`'s refusal is INERT at all four of its sites and is recorded as such rather than credited. One suspect was measured reachable: `const a: TLA = nil` on a named dynamic array compiles under both compilers, so the default-value block does get an array row and tags its 0 with tyInteger, right only because a dyn array is a pointer. REMAINING: symtab.inc 32, IR+lowering 142, other frontends 56; the accessors are visible to all of them."
---

# One field, two meanings, no refusal

```
Procs[pi].Params[j].IsArray = False  ->  TypeKind is the parameter's own kind
Procs[pi].Params[j].IsArray = True   ->  TypeKind is its ELEMENT kind
```

Nothing enforces the pairing and the field name carries no hint of it. Every
instance below is a caller that read one half and got an answer that looked
right.

| landed instance | what it read | what it did |
| --- | --- | --- |
| parameter default-value check | `TypeKind` alone | saw a string parameter for `array of string`, demanded a string literal, and accepted `= 'x'` — the callee then read a frozen literal's prefix as a length |
| bracket-argument arms (2 of them) | `IsArray` alone | sent every `[...]` to the TVarRec builder, so `array of Integer` got the wrong stride |
| overload signature identity | both, but not `ProcParamDynDepth` | `array of LongInt` and `TLongIntArray` are one signature; the later body wins and fpc binds two |
| `ParamIsConstVariant` | `TypeKind = tyVariant` alone | answers True for `const a: array of Variant` — the ELEMENT kind read as the parameter's own. **Accidentally right**, and left alone (below) |
| `FindUMethOverloadAhead`'s candidate probe | `IsArray` alone, one line above `argIsNil` | a named-array parameter recorded with `IsArray = False` was asked about BY TYPE against the ELEMENT kind — so the same row REFUSED `i.A(t)` and marshalled `i.A(nil)` as a scalar into a segfault |

The first two are closed. The third is
[[bug-p-an-open-array-and-a-named-dynamic-array-parameter-are-one-signature]]
(frankS, P p45) and is **not** fixed by this refactor — it needs
`FindProcOverloadRec` to consult `ProcParamDynDepth`, which already records the
difference. This ticket makes that class of misread impossible to write; it does
not decide any particular caller's semantics.

### The fifth is the first where one field produces TWO different wrong answers at one call site

`pasparser_call.inc`, `FindUMethOverloadAhead`'s single-candidate probe:

```pascal
if Procs[pi].Params[pj].IsArray then continue;    { array param: no type question }
if ProcParamUntyped[...] then continue;
if argIsNil[j] then continue;
if not MatchParamAccepted(pi, pj, argTk[j]) then ok := False;
```

Two skips, one line apart, on two different questions. A named array-type
parameter that the declaration parsers had recorded with `IsArray = False`
([[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]],
closed 2026-09-06) therefore fell past the first skip and was asked about **by
type** — against the element kind, because that is what the field holds when
`IsArray` is set — so `i.A(t)` was refused. `i.A(nil)` on the SAME declaration
took the second skip, was never type-checked at all, and reached the call
marshalling a dynamic array as a scalar: a segfault.

**One field, one row, one call site, and two different wrong outcomes depending
on how the argument was spelled** — a refusal for a variable and a crash for
`nil`. The other four instances each produce one wrong answer; this is the one
that shows the two meanings are a defect rather than a naming complaint, because
no single reading of the field is right for both lines (frankS's observation,
2026-09-06).

Note the declaration-side half of that bug is fixed and this probe is unchanged:
it is correct **given a correct row**. That is the point — the accessor is for
the caller who did not know there was a question, and this caller asks two.

### The fourth instance is the interesting one, because nothing broke

`ParamIsConstVariant` (`pasparser_call.inc`) asks
`Procs[pi].Params[slot].TypeKind = tyVariant` with no `IsArray` test, so it
answers True for `const a: array of Variant`. Found 2026-09-06 while adding
`ParamBindsAnExpression` beside it
([[bug-p-a-bracket-at-the-head-of-an-argument-cannot-be-an-operators-left-operand]]).

**It produces the right answer for the wrong reason.** The predicate's one caller
asks "may an expression bind to this parameter", and an `array of Variant`
parameter is not a var-binding target either — so True is what the caller wanted,
by accident. It has therefore never failed and would never have been found by a
bug report. Deliberately NOT corrected: the correction changes behaviour in
`pyparser.inc`, which calls the same predicate from five sites, for no measured
reason.

This is the case the accessor is actually for. The three defects above announced
themselves; this one is a coin that has been landing heads. A `ParamOwnKind` that
refuses would have made it a compile error the day it was written, and the author
would have discovered that the question they meant was about binding and not
about `Variant` at all.

## The remedy, and why it is an accessor rather than a predicate

frankD's argument, which frankS seconded from a third door: **a predicate can be
called correctly and still be handed the wrong field.** A shared
`ParamIsOpenArray(pi, j)` helps a caller who thought to ask; it does nothing for
the caller who did not know there was a question. An accessor that refuses does:

```pascal
function ParamOwnKind(pi, j: Integer): TTypeKind;   { tyUnknown when IsArray }
function ParamElemKind(pi, j: Integer): TTypeKind;  { tyUnknown when not IsArray }
```

Neither can return a plausible answer to the wrong question, which is the
property the raw field lacks. `ParamIsVarRecArray` / `ParamIsOpenArrayScalar`
(pasparser_lval.inc) already encode the array half correctly and stay; the
missing half is the one that declines.

## Why this is a ticket and not a sitting

**The number that decides whether anyone picks this up is 30, and here is the
grep that produced it — on the same line, because the previous three versions of
this number travelled without one:**

```
grep -nE '\.Params\[[^]]*\]\.TypeKind' compiler/pasparser_*.inc \
  | grep -vE '\.TypeKind[[:space:]]*:='          # 30 read lines, 0 assignment targets
```

Per file: `pasparser_call.inc` 13, `pasparser_lval.inc` 10, `pasparser_stmt.inc`
4, `pasparser_name.inc` 2, `pasparser_expr.inc` 1. Zero of the 30 sit inside a
comment. frank-coordinator's comment-aware scanner puts the same population at
**31**; the one-line difference is regex breadth around the subscript and it
changes nothing anyone would decide. **Thirty is the increment. Convert the
pasparser readers is thirty lines, not three hundred** — that is the fact this
ticket exists to carry, and it is the population all three known bugs came from.

### The whole-tree count, and why it is NOT the number to carry

Four counts in one day, from three seats: **~18** (this ticket, as filed),
**209** (frankS), **266** (both of us, agreeing), **263** (frank-coordinator).
The last is the best: a comment-aware scanner finds 272 mentions of which 6 are
inside comments and 3 are assignment targets. The 18 and the 209 were the same
defect — a filter excluding every line containing `:=`, which throws away
`x := Procs[..].Params[i].TypeKind`, a read. frank-coordinator's *first*
predicate had a third variant of it (testing for `:=` anywhere on the line rather
than immediately after the field, giving 12 targets instead of 3).

**Three seats, three versions of "is there a `:=` involved", and the two that
agreed at 266 agreed because they were the same method run twice** — neither of
us had written the filter down, so neither of us could compare filters, only
totals (frankS). **A second source that produces a NUMBER has to publish its
PREDICATE**; without it, agreement in a sub-figure and disagreement in the total
is exactly what one method run twice looks like.

None of this moved the ticket. The decision to file rather than sit rests on
"more than one sitting", which was true at 18 and is true at 263. **The number
was wrong by a factor of fifteen and the disposition never depended on it** — so
carry the 30 with its grep, and treat the whole-tree figure as scale, not as
evidence.

| where | read lines (of 263) | what they are |
| --- | --- | --- |
| `ir.inc` | 66 | marshalling |
| `pyparser.inc` | 42 | NilPy's own param table |
| `ir_codegen.inc` + five cross-target codegens | 77 | ABI, per target |
| `symtab.inc` | 31 | overload matching, RTTI |
| `cparser.inc` | 14 | the C frontend's own |
| `pasparser_*` | **30** | **the population all three known bugs came from** |
| `abi.inc`, `rtti_emit.inc`, `inline_expand.inc` | 6 | |

### The load-bearing claim in this ticket is still UNCHECKED

The sentence that decides the ORDER of the work — *"many of these legitimately
want the element kind, so this is not a substitution"* — has never been verified
against the sites. It is the reason step 3 says leave `ir_codegen*` alone, and
nobody has read those 143 lines to find out whether it is true.

**Zero of the 263 name `IsArray` on the same line.** That was offered as evidence
of unguardedness and it is not: frankS re-derived it over the full population AND
over the 57 lines their own filter had dropped, and it holds at 0 in both —
**accidentally safe rather than actually checked**, because a same-line guard is
not how anyone writes this. frank-coordinator's proximity proxy is the honest
version, `IsArray` anywhere within five lines:

| population | `IsArray` within five lines | denominator |
| --- | --- | --- |
| IR + lowering | 64 | 142 |
| `symtab.inc` | 9 | 32 |
| other frontends (`pyparser`, `cparser`) | 9 | 56 |
| **`pasparser_*`** | **4** | **30** (re-derived here; theirs, 4/31) |

**This table is the ranking argument, and it is a proxy, not the claim.**
Proximity is not intent — a nearby `IsArray` may guard a different parameter —
but the contrast is the point: nearly half the IR sites are visibly array-aware
and one in eight of the pasparser ones is. The population where the field is read
with no array question anywhere nearby is the parser, which is where all three
defects were. Somebody still has to read the 143 IR lines before anyone claims
they *want* the element kind.

## The USER-FACING instance, and it is fixed (2026-09-06)

Everything above is about a caller getting a wrong answer. One caller printed
that answer straight to the programmer:

```
pascal26:8: error: no overload of OnlyArr matches these arguments
  argument types: (Integer)
  candidates:
    OnlyArr(LongInt)
```

for `procedure OnlyArr(const a: array of LongInt)`. `symtab.inc`'s
`OverloadReport` spelled every candidate with `TypeKindSpelling(Params[j].TypeKind)`
— so it **refused `OnlyArr(3)` and then offered a candidate that is a spelling of
the call the programmer had just made.** Not merely unhelpful: it argues for the
mistake.

Fixed by `ParamSpellingForReport(pi, j)` (`symtab.inc`, before `MatchProcCall`),
which prefixes `array of ` per `ProcParamDynDepth`, floor 1. Fixture
`test/test_an_overload_candidate_spells_an_array_parameter_as_an_array_fail.pas`.
**It is one site, so it is a fix and not the refactor** — the refactor is still
the thing that stops the next one.

## Two instances from the WRITE side (2026-09-06)

Every instance above is a reader. Two are not, and they change what the accessor
has to do:

1. **A widening.** Teaching the four parameter parsers about named array types
   made `IsArray` true for `a: TDyn` — correct — and four callers passing the
   bare flag to the open-array-default refusal silently changed question. **No
   character changed at any call site.** A refusing accessor protects readers and
   protects nobody who passes the flag onward (frankS).
2. **An absence.** `ProcParamExplicitByRef` was simply not written by four
   declaration-site parsers, so every reader got a well-formed `False`
   (`bug-p-a-var-record-parameters-write-back-is-dropped-...`, closed). **A column
   whose default is also a legal value cannot be told apart from an unwritten
   one**, and no accessor over the read can see that. If the accessor increment
   is going to pay for itself twice, making the parameter row's *unwritten* state
   distinguishable is the half that catches this class.

## The pairing rule, verbatim, because the constraint has nowhere else to live

`ProcParamIsConst` and `ProcParamExplicitByRef` are only correct **written
together** — `ByRefArgNeedsLvalue` asks `ExplicitByRef and not IsConst`, so one
without the other turns a `const` record parameter into one that refuses a
non-lvalue argument. In `pasparser_proc.inc` they are adjacent at every site:

```
1698/1699    2153/2154    2568/2569
```

In `pasparser_decl.inc` before 2026-09-06, two of the four sites wrote
`IsConst` only and two wrote neither. **A parallel-array channel whose writes are
correct only in pairs has no way to say so at its declaration**, so the check is
mechanical and belongs here: grep each name and compare the counts.

## Done when

The two accessors exist, every `pasparser_*` reader of `Params[].TypeKind` has
been through a decision (converted or annotated with which question it asks), and
a new reader cannot get a plausible wrong answer without writing `.TypeKind`
explicitly.

Found by three seats on 2026-09-06: frankB (default values, bracket arguments),
frankD (the slot-mask work and the accessor design), frankS (signature identity,
and the `pasparser_proc.inc` verification of the two meanings).

## Done for the `pasparser_*` increment — 2026-09-06 (frankB), compiler `b50b1643e1a8`

`grep -nE '\.Params\[[^]]*\]\.TypeKind' compiler/pasparser_*.inc` is now **0**.
It was 23 lines / 24 occurrences (the extra is the two reads on one line in the
signature comparison). `gate.sh quick` GREEN, FPC seed canary included; the three
bodies sit in `symtab.inc` above every `pasparser_*` caller, so no forward
declaration is needed and the canary confirms it.

### THREE accessors, not two, and the third is the load-bearing one for a REFACTOR

`ParamOwnKind` and `ParamElemKind` are as specified above. The third is
`ParamStoredKind` — the raw field, named to say it is the union.

Without it this ticket cannot be finished honestly. Two accessors let a site be
converted only when its question has been DECIDED, and most of these sites cannot
be decided without a behaviour change nobody has evidence for. The choice was
then between leaving 23 raw reads (so a new reader copies one and the refactor
buys nothing) and converting them anyway (so the refactor smuggles in behaviour
changes under a rename). `ParamStoredKind` is the third option: **the absence of
a decision, named and greppable.** A new reader now has to pick one of three
names, each of which says which question it answers, and the remaining work is a
grep for one identifier rather than a re-derivation of the population.

### Seven DECIDED conversions, each behaviour-preserving by construction

| site | to | why it is exact |
| --- | --- | --- |
| `pasparser_lval.inc` bracket door | `ParamElemKind` | guarded by `ParamIsOpenArrayScalar` one line up |
| `ParamIsVarRecArrayAt` | `ParamElemKind` | replaced `IsArray and (TypeKind = tyRecord)` — the accessor's refusal IS that conjunct |
| `ParamIsOpenArrayScalarAt` | `ParamElemKind` | `<> tyRecord`, so the `IsArray` guard STAYS: tyUnknown `<>` tyRecord is True and dropping it would have been a widening |
| bracket-slot set veto (`pasparser_call.inc`) | `ParamOwnKind` | replaced `(not IsArray) and (TypeKind = tySet)` |
| `hasSet` scan (`pasparser_lval.inc`) | `ParamOwnKind` | same shape |
| two `Params[0]` Self tags (lval, expr) | `ParamOwnKind` | Self is never an array |

The third row is the one worth reading: **an accessor that refuses is only a
drop-in for an `=` test.** On a `<>` test the refusal answers tyUnknown, which
satisfies the inequality, so the guard has to stay. That is the same near-miss as
a narrowing wearing a widening's message, one type family over.

### ABLATION, RUN AND NOT ASSUMED — and only one of the two refusals is covered

Each refusal removed in turn, compiler rebuilt each time:

| ablation | `--tier quick` | `run_fgl_corpus.sh` |
| --- | --- | --- |
| `ParamElemKind` stops refusing | GREEN | **RED — `ifclist.pas` exit 139** |
| `ParamOwnKind` stops refusing | GREEN | GREEN |
| both | GREEN | RED (the same row) |

So `ParamElemKind`'s refusal is load-bearing today and the corpus is the only
instrument that sees it — `quick` does not. **`ParamOwnKind`'s refusal is
INERT**, at all four of its sites, and two of them (`Params[0]` is Self) are inert
by construction and always will be. Recorded rather than papered over: an
attempt to build a row that discriminates it (an `array of <set>` parameter at a
bracket slot, so the veto would fire without the refusal) did not move the
answer, because the narrowing already declines when two array candidates share
the slot. `ParamOwnKind` earns its place as the thing a FUTURE caller cannot get
a plausible wrong answer out of, which is the ticket's thesis — not as a fix.

### The undecided sites, annotated in place, and one is measured reachable

Each remaining `ParamStoredKind` read now carries a comment saying which question
it asks. Two categories:

**Deliberate union reads, annotated so nobody "fixes" them:** the signature
equality test (`ParamOwnKind` there would make every pair of array parameters
compare equal — a widening), the two `OverloadArgRank` sites (an array parameter
is ranked by its element against an argument carrying the same element tag, which
is how a named dyn array separates from an open array at all), `ParamIsConstVariant`
(right for the wrong reason, and correcting it changes `pyparser.inc`'s five
callers for no measured reason), and the `PXXDBG` print.

**Suspects — the site means the parameter's OWN kind and an array row answers on
its element:** `ParamTakesCharLitAsStr` and the Char-literal refusal beside it
(`array of string` carries tyString); `OverloadArgElemMismatch`, both arms
(`array of AnsiString` / `array of Pointer`); the PChar→string and
WideChar→UTF8 wrappers; the procedural-designator arm; the three generator-argument
predicates (`array of Variant`, `array of AnsiString`). None converted: each is a
behaviour change with no probe asking for it.

**The default-value block is the one with a measurement.** It was left as a
suspect and then made reachable rather than theoretical:

```pascal
procedure P1(const a: TLA = nil);     { TLA = array of LongInt }
```

compiles under pxx AND under fpc 3.2.2, both printing `len=0`. So an array row
whose kind is its ELEMENT's does reach every read in that block; today it lands
on the `AN_INT_LIT` arm and tags a 0 with tyInteger, which is right only because
a dynamic array is a pointer. **Right by luck, not by rule** — the same shape as
`ParamIsConstVariant`, and the reason this ticket wanted an accessor rather than
a predicate.

### What is left

`symtab.inc` 32 reads, IR + lowering 142, other frontends 56. The accessors are
declared where all of those can see them. The load-bearing claim in this ticket —
*"many of these legitimately want the element kind"* — is still unchecked and this
increment did not check it; what it did establish is that in `pasparser_*` the
split is **7 decided, 4 deliberately union, 12 suspect**, which is not the ratio
the proximity proxy predicted and is a reason to read the IR sites rather than
assume them.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
