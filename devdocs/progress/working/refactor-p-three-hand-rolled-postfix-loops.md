---
track: P
prio: 55
type: refactor
blocked-by: []
summary: "TWO now, down from three (27e656541), four (7927fe685) and five (8627d25ce). THE SLUG SAYS THREE AND IS LEFT SAYING THREE: a count in a slug is frozen at filing, nothing anywhere dates it, and repairing it in place would destroy the only evidence it was ever a different number -- the series belongs here. The two expression-side loops are MERGED: ParseCastPostfixSuffix in pasparser_lval.inc parses the `^ / .field / [i]` chain for both cast spellings, and it is a PARAMETERISATION rather than a lift, because a record-name cast has no alias row (its ASTIVal is 0 for `plain reinterpret`, which ResolveDerefShapeAt would read as alias row ZERO) so that caller passes aliasIdx = -1 and a seed that IS the answer. The record-name copy turned out to be a strict SUBSET of the alias copy arm for arm, every gap already filed as a silent wrong value on that spelling alone, so the merge was a deletion of the weaker twin and not a reconciliation. WHAT IS LEFT is ONE loop: ApplyCallResultPtrSuffix in pasparser_lval.inc, which frankB is holding (bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type adds a `(` arm to it). Its `[` arm survived a deadness probe -- live on a deliberate pxx extension with a committed test and no fpc oracle -- and pyparser.inc's two remain DELIBERATE per the-substrate-is-ast-and-ir-not-the-parser. The guard is tools/cast_suffix_walk_probe.py, 132 rows, with a twin check for the 38 rows fpc refuses by construction."
status: working
owner: frankA
---

# P three hand-rolled copies of the postfix `^ / .field / [i]` loop

- **Track P** (`compiler/pasparser_lval.inc`, `compiler/pasparser_expr.inc`).
- Banked diagnosis from
  [[bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped]], per
  `devdocs/dev/root-cause-over-microfix.md`: that bug was fixed properly (in the
  shared `NodePtrElem` predicate, not at the call site) and this is the overhaul
  it exposed but deliberately did not attempt. **Not urgent** — nothing is
  broken today that is known; this is about the next one.

## The count

`while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do`:

| file | what opens the chain |
| --- | --- |
| `pasparser_lval.inc` (~900) | an IDENT — the shared, most complete loop |
| `pasparser_expr.inc` (~5027) | a RECORD-NAME cast, `TRec(q)` |
| `pasparser_expr.inc` (~5223) | a POINTER-ALIAS cast, `PRec(q)` |
| `pyparser.inc` (~44092) | byte-identical copy of the third — Track N, see [[bug-n-inline-cast-deref-loses-a-pointer-fields-pointee]] |

`root-cause-over-microfix.md`'s own rule: *two mechanisms for one concept is a
smell, three is a design flaw.* This is four.

## The evidence that they diverge

Each of these was one copy knowing something the others did not, and each
produced a plausible wrong VALUE rather than an error:

- `bug-pascal-record-cast-field-offset` — the record-cast copy put an
  `AN_FIELD` straight on the `PTR_CAST`, so every field resolved at offset 0.
- `bug-pascal-record-cast-chain-drops-method-call` — the hand-rolled builder can
  only make `AN_FIELD`, so a METHOD at the end of a chain evaluated to the
  receiver instead of being called.
- `PPVmt(Self)^.__ClassRef.GetHashList(...)` — a metaclass-typed field is a
  RECEIVER, and the copy walked into it; the chain evaluated to the class
  reference.
- `bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped` — the
  pointer-alias copy answered every `^` from the cast's alias.

Note the shape of the last three fixes: each ADDED an escape from the private
loop back into a shared routine (`ParseClassRecordSelectors`,
`ParseMetaclassMemberTail`, `NodePtrElem`). The copies are already being
dismantled one arm at a time by whoever hits the next hole.

## The work

Finish that. Factor ONE suffix parser that takes the opening node plus its
`(tk, recName, pointee)` state, and have all three Pascal sites call it. Measure
by tickets-closed-per-change, not lines: the copies exist only because each cast
path needed "the same thing but starting from a different node", which is a
parameter, not a fork.

Watch for the genuine differences before merging them away — the `-1`/`-2`
adapter casts (`PChar(s)^`, the widening ordinal pun) carry no alias row and
need the fallback the alias-cast loop has; the record-name cast builds an
`AN_ADDR`-then-deref for the in-place `TRec(q).field` reinterpret. Both are real
behaviour, not accidents, and both must survive.

`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` is not a
counter-argument here: it says duplicate ACROSS languages, normalise WITHIN one.
These four copies are three within Pascal plus one in NilPy — the Pascal three
are exactly what it says to normalise, and the NilPy one is N's own call.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. This one is worth more than
the usual care: it is pure refactor of a path that has produced four silent
wrong-value bugs, so land it incrementally (one call site at a time, each
green) rather than as one swap.

---

## 2026-09-04 (frankA) — the count is FIVE in Pascal, not three, and the title is wrong

Recounted at `f8b9e4394673`, listed rather than remembered:

```
grep -n 'while CurTok.Kind in \[tkCaret, tkDot, tkLBrack\]' compiler/*.inc
```

| file:line | opened by |
| --- | --- |
| `pasparser_lval.inc:5030` | a call RESULT — inside `ApplyCallResultPtrSuffix` |
| `pasparser_expr.inc:6624` | a RECORD-NAME cast, `TRec(q)` |
| `pasparser_expr.inc:7022` | a POINTER-ALIAS cast, `PRec(q)` |
| `pasparser_stmt.inc:7077` | a cast as an assignment TARGET |
| `pasparser_stmt.inc:7292` | the statement path's own walk |
| `pyparser.inc:48234`, `:48380` | Track N, two copies |

**Five in Pascal plus two in NilPy = seven**, against the body's "three ... plus
a fourth in pyparser.inc". The table above is generated by the grep, so it
carries a line number that will drift; the grep is the durable half.

The body's own rule — *"two is a smell, three is a design flaw"* — is being
applied to a number nobody re-derived. Worth stating because this ticket is the
one a reader consults to decide whether the refactor is worth it, and it is
underselling itself by 40%.

## Two more arms dismantled the way this ticket predicts

The body notes that the last three fixes each *"ADDED an escape from the private
loop back into a shared routine"* and that the copies *"are already being
dismantled one arm at a time"*. Two more, both 2026-09-04:

- **`ff2495a55`** — the `tkArgStr` (ParamStr) arm was a SIXTH site that needed a
  suffix and did not have one. It returned with `[` still in the token stream,
  which in argument position was a loud parse error and in assignment position
  was a **silently discarded subscript** (the statement catch-all ate it), so
  `cc := ParamStr(0)[1]` stored the low byte of the string pointer. Fixed by
  calling `GenMakeStringValueIndex` — the escape, not a sixth loop.
- **`d9604ea59`** — `ParseClassRecordSelectors`' DEFAULT-property arm never
  asked whether its `[` was an assignment target, while the NAMED-property arm
  200 lines above it in the same function always had. Fixed by giving the
  default arm the sibling's question, not a new walker.

**Both fixes were "the shared routine was missing an arm its sibling had", not
"the private loop was wrong".** That is a slightly different disease from the
one this ticket describes and it argues the same cure: the escapes are working,
and what is left over is that the shared routine has to actually be complete.

## A note for whoever takes it: the per-SPELLING antipattern has a precedent now

frankH's `44c08dc66` fixed a neighbouring ticket by finding that "is this a
procedural value?" was answered **spelling by spelling**, and replaced them with
`PasNodeProcSig` — one node-keyed answer asked once after the lvalue walk —
**deleting** the identifier-only arm rather than leaving it beside the new one.
If the five loops here are also answering per-spelling rather than per-node,
that is the shape to copy, and the precedent is in the tree.

Expect the AST slot-write census to go RED if the work adds slot writes;
regenerate with `python3 tools/ast_slot_overloads.py --update` after reading
every row, and grep the gate log rather than trusting the wrapper's exit code.

---

## 2026-09-05 (frankA) — the ESCAPE CENSUS, which is the map this refactor needs, and it found a live bug

The body says the last three fixes each *"ADDED an escape from the private loop
back into a shared routine"* and that the copies are *"already being dismantled
one arm at a time"*. That is measurable, so I measured it. For each of the five
Pascal loops, which shared routines does its body reach?

| loop | escapes reached |
| --- | --- |
| `pasparser_expr.inc:7094` (pointer-alias cast) | **6** — `ParseClassRecordSelectors`, `NodePtrElem`, `FoldDerefArrayLowBound`, `ParseMetaclassMemberTail`, `ParseNDSubscriptTail`, `BuildFlatNDIndex` |
| `pasparser_expr.inc:6627` (record-name cast) | 2 — `ParseClassRecordSelectors`, `ParseMetaclassMemberTail` |
| `pasparser_stmt.inc:7439` | 1 — `ParseClassRecordSelectors` |
| `pasparser_stmt.inc:7224` | 1 — `ParseClassRecordSelectors` |
| `pasparser_lval.inc:5101` (`ApplyCallResultPtrSuffix`) | 1 — `ParseNDSubscriptTail` |

Line numbers as of `db40103f2`; the census is the durable half, and it is
`grep`-able per loop body rather than remembered.

**This table is a defect predictor, and it paid immediately.** One loop reaches
six and the rest reach one or two, so any arm present only in the rich one is a
candidate. `FoldDerefArrayLowBound` was in exactly one of five —
`ApplyCallResultPtrSuffix` mints an `AN_INDEX` over a deref and never subtracted
the pointee's low bound. Probe against fpc 3.2.2, `array[1..5] of Integer`:
`GetP^[3]` read `lo[4]`, and `GetP^[2] := 77` wrote `lo[3]`. Silent, both faces,
in pin v403. Fixed `9e6233f18`, regression rows in
`test/test_inline_ptr_cast_low_bound.pas`.

**No repro was involved.** The table said "this loop is missing an arm its
sibling has", and a five-line program confirmed it. That is the argument for the
unification stated as a measurement rather than as a principle.

### What this says about how to do the work

The body proposes factoring ONE suffix parser taking `(node, tk, recName,
pointee)`. The census suggests the cheaper ordering: **the rich loop at
`expr:7094` is already most of that parser.** Rather than writing a new one and
migrating five callers, walk the table row by row and ask, for each escape the
rich loop has and a poorer one does not, whether the poorer one can reach the
shape that escape exists for. Each answer is either a bug to fix now (as above)
or a documented reason the arm is unreachable there — and either way the loops
converge, which is what makes the eventual merge safe rather than hopeful.

The five are also very unequal — 208, 96, 40, 22 and 118 lines — so "five copies
of one loop" oversells the symmetry. Two of them are barely more than a
`ParseClassRecordSelectors` call already.

### Still true, and re-derived

Five in Pascal plus two in NilPy (`pyparser.inc:48234`, `:48380`), unchanged
since the 2026-09-04 recount. The body's "three plus a fourth" remains wrong;
the title still says three.

---

## 2026-09-05 (frankA, later) — the escape census above COUNTED COMMENTS, and the corrected table found a second live bug

**Retraction first.** The table in the section above is wrong. It was built by
grepping each loop body for the names of shared routines, and a Pascal loop body
contains prose: `{ ... }` comments naming the very routines the code no longer
calls. Two of the six escapes credited to `expr:7094` were comment matches, and
one of them — **`NodePtrElem` — has not existed since 2026-09-01**, when it was
deleted (the note sits at `pasparser_lval.inc:5638`, explaining at length that it
was measured as the poorer walk and removed). The census reported a call to a
routine that is not in the tree.

This is `a-grep-count-is-not-a-set-count` exactly: *prose mentioning a marker
matches too.* The instrument did not error. It answered about the file's TEXT
while being read as an answer about its CALLS.

Re-derived with `{...}`, `(*...*)` and `//` stripped before matching, at
`e3e654416`:

| loop | escapes reached |
| --- | --- |
| `pasparser_expr.inc:7094` (pointer-alias cast, 212 lines) | **6** — `ParseClassRecordSelectors`, `ResolveDerefShape`, `FoldDerefArrayLowBound`, `ParseMetaclassMemberTail`, `ParseNDSubscriptTail`, `BuildPartialNDRowIndex` |
| `pasparser_lval.inc:5110` (`ApplyCallResultPtrSuffix`, 125 lines) | 3 — `FoldDerefArrayLowBound`, `ParseNDSubscriptTail`, `BuildPartialNDRowIndex` |
| `pasparser_expr.inc:6627` (record-name cast, 100 lines) | 2 — `ParseClassRecordSelectors`, `ParseMetaclassMemberTail` |
| `pasparser_stmt.inc:7439` (40 lines) | 2 — `ParseClassRecordSelectors`, `ResolveDerefShape` |
| `pasparser_stmt.inc:7224` (22 lines) | 1 — `ParseClassRecordSelectors` |

**The correction did not weaken the table's argument; it sharpened it.** The
previous version's `NodePtrElem` row obscured that the real shared pointee
resolver is `ResolveDerefShape`, and that `ApplyCallResultPtrSuffix` is the one
loop of five reaching **neither** `ResolveDerefShape` nor
`ParseClassRecordSelectors`. That is a much more specific prediction than "one
loop is richer".

### It paid a second time, and the bug has two faces

`ApplyCallResultPtrSuffix`'s `^` arm answered **every** deref in its suffix loop
from `elemTk`/`elemRec` — the returned pointer's own pointee, captured once
before the loop. Correct for the first `^`; wrong for every later one, because
by then the node is a FIELD with a pointee of its own. Against fpc 3.2.2:

| | pxx, pin v403 | fpc 3.2.2 |
| --- | --- | --- |
| `GetP^.pc^` where `pc: PChar` | `90` | `Z` |
| `GetP^.pi^ := 9` where `pi: ^Integer` | `error: incompatible types: cannot assign Integer to record` | stores 9 |
| `vp^.pc^` / `vp^.pi^ := 7` (plain variable) | correct | correct |

The variable rows are the control that says the **opener** is the variable, not
the shape. Both faces reproduce on the pinned compiler.

**And the loud face MASKS the silent one** (`a-loud-defect-masks-the-quiet-one-behind-it`):
the pinned compiler stops at the store and never reaches the Char row, so a
single program cannot show both on the old binary. The silent face had to be
measured on its own, in a program with no store in it.

This is the SAME defect `ResolveDerefShape` already fixed in the pointer-alias
copy, where the private loop answered every `^` from the CAST's alias. Fifth
copy, same hole. The `[` arm of this loop is NOT affected — it already refreshes
its own alias from `DerefPtrArrayElem`, which is why the fix is scoped to the
walked-past-a-field case.

Fixed by asking the shared resolver once the walk has left the call node.
Regression rows: `test/test_callres_field_deref.pas`, `.expected` byte-identical
to fpc 3.2.2 `-Mdelphi -O1`, and it is REFUSED by the pinned compiler, which is
what makes it a test.

### For whoever continues down the table

Two escapes are still absent from `ApplyCallResultPtrSuffix` and one from every
poorer loop:

- **`ParseClassRecordSelectors` in `ApplyCallResultPtrSuffix`** — a method,
  property or default property at the end of a call-result chain
  (`GetObj^.Method(x)`, `GetObj^.Prop`). The body's own history says a
  hand-rolled builder that can only make `AN_FIELD` evaluates a METHOD to the
  receiver. Not probed yet; that is the next row.
- **`ResolveDerefShape` in `expr:6627` and `stmt:7224`.** Both are short loops
  that hand off early, so the arm may be genuinely unreachable there — but
  "unreachable" must be CONSTRUCTED, not assumed.

The census script lives in the session scratchpad and is ten lines; rebuild it
rather than trusting this table, and **strip comments before matching**, which
is the whole lesson of this section.

---

## 2026-09-05 (frankA) — the NEXT row is measured and NOT fixed, because the function is frankH's

The section above names `ParseClassRecordSelectors` in `ApplyCallResultPtrSuffix`
as the next row to probe. I probed it. **I am not fixing it**, for a reason that
has nothing to do with the code: on 2026-09-04 I told frankH *"Take
`ApplyCallResultPtrSuffix` and the five AN_CALL_IND sites; I'll stay out of that
function. I'll tell you before I touch it if my boundary table forces me to."*
I then landed inside it twice without telling anyone (`9e6233f18`, `7095ca817`).
The measurement below is handed over rather than acted on.

### The finding, so it is not lost

A record METHOD reached through a call result is refused. `TRec` with
`function Doubled: Integer`, `PRec = ^TRec`, `function GetP: PRec`:

| opener | fpc 3.2.2 | pxx (HEAD and pin v403) |
| --- | --- | --- |
| `a.Doubled` (plain var) | 42 | 42 |
| `vp^.Doubled` (var deref) | 42 | 42 |
| `PRec(q)^.Doubled` (pointer-alias cast) | 42 | 42 |
| `TRec(a).Doubled` (record-name cast) | 42 | 42 |
| **`GetP^.Doubled` (call result)** | **42** | **`error: "Doubled": no such member on this record/class`** |

Four of five openers are the negative control: the divergence is the OPENER, not
the member and not the record. Same for a procedure member in statement
position — `GetP^.Bump(1)` is refused while `vp^.Bump(1)` stores.

**A loud refusal, not a silent wrong value**, which is why it ranks below the
`^`-after-a-field pair fixed in `7095ca817`.

### The part that is NOT a simple copy of the rich loop

`ApplyCallResultPtrSuffix`'s `tkDot` arm calls `RequireRecMember` and then builds
an `AN_FIELD`, so a non-field member cannot survive it. But the obvious remedy —
copy the rich loop's hand-off — **does not transfer as written**: that guard is
`(recName >= REC_UCLASS_BASE) and (FindUField(...) < 0)`, i.e. CLASSES only, and
this case is a plain record. Whatever answers `vp^.Doubled` today is a different
route, and that route is what should be reached here. Worth finding before
writing the arm; the four working openers make a ready-made oracle.

Probes are reconstructible from the table above in about five lines each; the
matrix is one heredoc per opener against `fpc -Mdelphi -O1`.

---

## 2026-09-05 (frankA) — the table's remaining `ResolveDerefShape` gaps, worked: THREE more faces, one per loop

The corrected census left `ResolveDerefShape` absent from two loops and asked
whether each could reach the shape the arm exists for. Both could. Working the
table row by row produced three more divergences against fpc 3.2.2, all
pre-existing in pin v403 and **all confirmed failing ALONE on the pin** — which
mattered, because in one program the parse error masks the two stores behind it.

Field `pi: ^Integer` in a record; `b` the variable, `q: Pointer`, `PA = ^TA`:

| # | shape | pinned pxx | fpc 3.2.2 | loop |
| --- | --- | --- | --- | --- |
| 1 | `TA(b).pi^` (read) | `error: expected ')' before '^'` | 42 | `expr` record-name cast |
| 2 | `TA(b).pi^ := 7` | `cannot assign Integer to record` | stores | `stmt` record-cast target |
| 3 | `PA(q)^.pi^ := 7` | `cannot assign Integer to record` | stores | `stmt` alias-cast target |

Controls green on the pin AND at HEAD: `b.pi^`, `vpa^.pi^`, `PA(q)^.pi^` (read),
`b.pi^ := 7`, `vpa^.pi^ := 7`. **Four openers spell chain 1 and only one was
wrong**, which is what says these are about the opener rather than the shape.

### Three different mechanisms, and the third is the interesting one

- **(1) the token was never consumed.** The record-cast arm delegates every
  `.name` to `ParseClassRecordSelectors` and then `Break`s. That walker's own
  loop is `[tkDot, tkLBrack]` — no `tkCaret` — so a trailing `^` is simply left
  in the stream. Not a wrong value; a parse error two tokens later, which is why
  it reads as a syntax problem and not a walker problem.
- **(2) a private notion of what `^` yields.** The stmt record-cast loop stamped
  `tyRecord` and the CAST's record on the deref node. Identical to the
  call-result bug in `7095ca817` and to the alias-cast bug `ResolveDerefShape`
  was originally written for.
- **(3) the resolver was CALLED, was RIGHT, and its answer was thrown away.**
  The stmt alias-cast loop already called `ResolveDerefShape`. Downstream sat an
  adapter fallback: *if* `tyInteger` and `REC_NONE` and no depth and no base rec,
  restore the alias, because the PChar adapter cast carries no alias row for the
  resolver to read. **That test is both the resolver's decline signature and a
  true answer for `^Integer`.** After delegation the true reading is the common
  one, so the fallback put the cast's record back over a correct answer.

**(3) is the one to remember**, because the census cannot see it. The escape was
present; the call was there; the arm was reached. A census of *which routines a
loop calls* scores that loop as having the arm — and it did, and it was still
wrong. Gated on the same delegation bit the other two fixes needed: a default
that is also a real answer cannot signal "not applicable", so membership needs
its own bit rather than being inferred from the value.

### What the table looks like now

All five Pascal loops reach `ResolveDerefShape` or provably need not. What
remains open on this ticket is the unification itself, plus one row banked
separately: `ParseClassRecordSelectors` is still absent from
`ApplyCallResultPtrSuffix`, so a record METHOD through a call result is refused
(see the previous section — frankH has since released that function, so it is
takeable).

Regression rows: `test/test_cast_field_deref.pas`, byte-identical to fpc 3.2.2
`-Mdelphi -O1`, refused by the pinned compiler. It carries the PChar adapter
rows as the control that narrowing the fallback in (3) did not disable it where
it is the right answer.

**One coverage limit, stated rather than glossed:** the adapter fallback's
narrowing is gated on delegation, and an adapter cast cannot BE delegated —
`PChar`'s pointee has no fields — so "adapter cast plus delegation" is not a
constructible shape and the new guard has no positive control drawn from it.
The adapter rows prove only that the undelegated path still works.

---

## 2026-09-05 (frankA) — the last `ParseClassRecordSelectors` gap, and frankH's lead was refutable from evidence already in hand

frankH released `ApplyCallResultPtrSuffix` (its words, recorded by frankuser),
so the row banked two sections above is now done.

**A non-field member through a call result was refused.** The suffix loop's
`.name` arm goes straight to `RequireRecMember`, which knows only fields:

| shape | pinned pxx | fpc 3.2.2 |
| --- | --- | --- |
| `GetP^.Doubled` (function) | `"Doubled": no such member on this record/class` | 42 |
| `GetP^.Bump(1)` (procedure) | same | stores |
| `GetP^.P` (property read) | same | 40 |
| `GetP^.P := 7` (property write) | same | stores |

**All four confirmed failing ALONE on the pin.** Four other openers spell the
same member on the same record and all four were right throughout, on the pin
too: `a.Doubled`, `vp^.Doubled`, `PRec(q)^.Doubled`, `TRec(a).Doubled`.

### The lead, and why it did not need running

frankH offered a hypothesis, explicitly labelled unverified: that
`ProcRetPtrElemRec` might be `REC_NONE` for a pointer-to-record return, so the
shared walker would be asked to find a method on a record whose identity it had
not been told — *"which would refuse the method loudly while a field might still
resolve by another route, and that matches the shape of what you measured."*

**It is refuted by evidence that was already on the table.** A plain field
through the identical chain — `GetP^.value`, measured hours earlier while
probing the deref bug — has always resolved correctly, and it resolves through
`recId` in the very same arm. An empty record id cannot produce a correct field
offset. So the id was populated and the ONLY thing missing was the escape.

Worth recording because the hypothesis was a good one and cost nothing: it named
a specific column, a specific consequence, and a cheap falsification. What made
it unnecessary was that the discriminating observation had already been taken
for a different question. **Before running a proposed probe, check whether an
earlier measurement already separates the arms** — the field row was collected
to test the deref bug and happens to answer this one too.

Fixed by peeking the member name before consuming the dot
(`FindUField(recId - REC_UCLASS_BASE, GetTokenStr(TokPos)) < 0`, the same idiom
the pointer-alias loop uses, because the shared walker's own loop starts ON the
dot) and delegating. Regression rows:
`test/test_callres_record_member.pas`, byte-identical to fpc 3.2.2.

### Where the ticket stands

All five Pascal postfix loops now reach both `ResolveDerefShape` and
`ParseClassRecordSelectors` where they can be reached. **The escape census is
spent as a defect predictor** — it found four separate bugs across three
sessions of use and there are no unequal rows left in it.

What remains is the ticket's original ask: ONE suffix parser rather than five.
That is now a pure refactor with no defect backlog attached, and the case for it
should be argued on its own merits — the same place
[[refactor-p-one-lvalue-path-for-statements-and-expressions]] ended up.

**One caveat for whoever ranks it.** The last fix found a defect class the
census structurally CANNOT see: the stmt alias-cast loop CALLED
`ResolveDerefShape`, correctly, and discarded the answer downstream. A census of
which routines a loop calls scores that loop as having the arm. So "all five now
reach every escape" is a weaker statement than it sounds, and it is not evidence
that the loops agree.

---

## 2026-09-05 (frankA) — the census's own caveat, spent: an OPENER x CHAIN differential, 46 rows, one red

The 2026-09-05 summary says the escape census *"cannot see a loop that CALLS an
escape and discards its answer"*, and that is exactly what was left. A census of
which shared routines each loop REACHES is a census of call sites; it cannot
see what happens to the answer. So this pass varied the other axis: run the same
CHAIN through every OPENER and compare against fpc 3.2.2.

**Five openers x five chains, read and write.** Openers: a plain record
variable, a pointer variable, `PRec(raw)^` (the alias cast), `TRec(raw)^` (the
record-name cast), `GetP(raw)^` (the call result). Chains: `.a`, `.pi^`,
`.arr[1]`, `.n^.a`, `.o.Twice`. The two variable openers are the control: a
chain that is simply wrong for everyone shows up as a whole COLUMN, not as a
cell.

```
agree=36  DIFFER=1(the injected control)  PXX-REFUSES=1  pxx-only=9  total=46
```

**The harness carries a must-differ row of its own** — one tag is handed
DIFFERENT source to each compiler, so a harness that cannot report DIFFER is
caught by its own output instead of by trusting a clean sweep. It fires. The 36
is therefore a measured zero and not a vacuous one.

### The one red

```
GetP(raw)^.arr[1] := 44     ->  incompatible types: cannot assign Integer to record
```

The READ of the identical chain was correct, and the same store through all
four other openers was accepted; fpc accepts it too.

**It is the `^` arm's own fix, one arm over.** `ApplyCallResultPtrSuffix`
captures the CALL's pointee once before the loop. The `^` arm learnt that this
is only right while the walk is still on the call — that is the `movedOffCall`
guard added when the escape census found `GetP^.pi^ := 9` refused with the
IDENTICAL message — and the `[` arm, three screens down the same loop, kept
re-stamping `tk`/`recId` from the call's constants. One arm of a double case
fixed and the sibling not grepped for, **inside the routine whose own ticket is
about that habit** (`devdocs/dev/normalise-dont-special-case.md`: *"Fixed one
arm of a double case? Grep for the sibling before closing."*).

Fixed with the same guard. `test/test_call_result_suffix_after_a_field.pas`
pins it, every row run through the call AND through a pointer variable.
Negative control: the pre-fix compiler (`5ec14c826891`) refuses two rows.

### The nine rows with no oracle, and why they are a RESULT

`TRec(raw)^...` — a record-name cast of a raw pointer — is refused by fpc in all
nine spellings, so pxx accepting it is not a defect and there is nothing to
differ from. **What the column DOES say is that all nine values equal the
control's**: `11 / 77 / 33 / 5 / 18` reading and `42 / 43 / 44 / 45` writing,
identical to the plain-variable opener. The record-name cast loop is internally
consistent with the other four, which is the strongest thing that column can
say and is worth more than a missing oracle row.

### What is left

The count is unchanged: five in Pascal, two in NilPy. With this red closed the
five agree on every shape the differential can express, so **the unification now
has no defect backlog under it and a 46-row before/after instrument above it.**
The generator is small enough to rebuild from the opener and chain lists here;
it lives in ticket history rather than `test/` because it is a before/after
instrument, and the one row that became permanent is in `test/`.

---

## 2026-09-06 (frankA) — five becomes four, and the merge told us why they were two

`8627d25ce`. The two `pasparser_stmt.inc` loops are `ParseCastTargetSuffix`,
one body, 103 insertions against 124 deletions. Full write-up in
[[refactor-p-one-lvalue-path-for-statements-and-expressions]], which is where
the before/after census lives; the part that belongs here is what the merge
revealed about why there were two.

**They differed in one arm and the difference was a FACT, not a preference.**
The `^` arm has to know what a cast's pointee is, and that is different for the
two casts: a record-name cast knows it (its own record) and carries `ival 0`, so
there is no alias row and `ResolveDerefShape` would index alias 0; a
pointer-alias cast carries the whole triple and must ask. One boolean. Everything
else — including the delegation branch that hands `.` and `[` to
`ParseClassRecordSelectors` — was byte-identical.

**And both had learned the same lesson separately, months apart:** after
delegation the seed is never the answer, because the value in hand is a field
whose pointee has nothing to do with the cast. `TA(b).pi^ := 7` and
`PA(q)^.pi^ := 7` were each refused for that and each fixed on its own copy.
**That is this ticket's whole argument in one artefact** — not that five loops
are untidy, but that each one has to be taught every lesson again, and the
teaching is only ever noticed when someone hits the arm.

The escape census this ticket built stays the right instrument for the
remaining three, but it cannot answer the next question, which is not "does this
loop reach the shared routine" — all four do — but **"is the arm it built by
hand instead of delegating the right arm at all"**. The expr record-cast twin's
`AN_INDEX` is that arm.

## 2026-09-06 (frankA, later) — the third instrument: census the FIELD, not the call site

Two censuses have been run against these loops now, and they answer different
questions:

1. **the escape census** — which shared routines does this loop REACH?
   All four Pascal loops reach `ResolveDerefShape` and
   `ParseClassRecordSelectors`. Answer: they all escape. Instrument exhausted.
2. **the encoding census** — what does this loop STAMP, and does every consumer
   read the same encoding? Run today over the remaining three: they stamp one
   identical triple on `AN_DEREF` and there is no second convention among them
   (detail in [[refactor-p-one-lvalue-path-for-statements-and-expressions]]).

The second instrument is the one that found a real bug, and it did so **not on
a loop but on the OPENER** — the `AN_PTR_CAST` record-name arm stamping
`ASTIVal := 0` as a fourth "none" in a field whose `>= 0` space is alias row
indices. `b7b9e309e` / `8de0ee547`.

**The transferable part is that it is closed-world in a way a call-site census
is not.** "Which routines does this loop call" is answered by grepping the loop,
and a grep can only confirm the sites you thought to look for — that is how the
count of readers stood at two for a day when it was three. "Who reads this
field on this node kind" is answered by grepping the FIELD, and the field has a
finite number of mentions in the tree. Name the encoding first, then enumerate
its readers; do not enumerate the readers you remember and infer the encoding.

So the remaining question for these three loops is neither reach nor encoding.
It is **control flow**: `ParseClassRecordSelectors`'s own loop is
`[tkDot, tkLBrack]` with no `tkCaret`, so a hand-rolled loop that delegates and
then `Break`s strands a following `^` in the token stream — measured once
already as `TA(b).pi^`. Whether each remaining hand-built arm re-enters its own
loop after delegating, or breaks, is the next thing to measure, and unlike the
first two censuses it needs a differential rather than a grep, because the
failure is a token nobody consumed.

## 2026-09-06 (frankA, later still) — the re-entry question found a refusal, and four becomes three

The control-flow measurement this ticket named as next is run, and it found a
real defect on the one loop that had never been taught the lesson.

**`PTC(raw)^.GetP^` and `PTC(raw)^.Pp^` were refused outright** — *expected `)`
before `^`* — while `pc^.GetP^` and `pc^.Pp^`, the same chains off a plain
variable, compiled and printed 42. fpc 3.2.2 accepts all four. The pinned
compiler refuses exactly the two cast rows and passes the two variable rows, so
it pre-dates v403 and the test can fail.

The pointer-alias cast walk delegates a METHOD or PROPERTY name to
`ParseClassRecordSelectors` — whose own loop is `[tkDot, tkLBrack]` with **no
`tkCaret`** — and then `Break`ed unconditionally. Nobody consumed the `^`. The
record-name twin has carried `if CurTok.Kind <> tkCaret then Break; Continue;`
since `TA(b).pi^`, and `ApplyCallResultPtrSuffix` has it too. **One opener of
three had never been told.**

### The instrument, and why the two earlier censuses could not find it

- *escape census* — which shared routines does this loop REACH? All four reach
  them. Cannot see this.
- *encoding census* — what does it HAND them? Clean, one triple, no second
  convention. Cannot see this either.
- *re-entry* — does it come back into its own loop after delegating? **This one
  needs a differential, not a grep**, because the failure is a token nobody
  consumed. An absent case leaves no site to grep, so no census over the source
  can contain it; only running the shape can.

Three instruments, three different questions, and each found exactly what the
previous one was structurally unable to see.

### The fix removes copies rather than adding one

The minimal fix is pasting the guard a third time, which is this ticket's own
complaint. Instead: all three post-delegation `^` handlers were writing out the
same block — ask `ResolveDerefShape`, stamp remaining depth in `ASTSOffset`,
ultimate base in `ASTSLen`/`ASTIVal`, `StrValTk` in `ASTTk`. That is now
**`StampDerefFromShape`** (`pasparser_lval.inc`), called from all three. Three
copies to one, orphaned locals dropped with them. `414099b7f`.

**Count: three hand-rolled postfix walks remain in Pascal** (was four this
morning, five yesterday), and they now share the deref-stamp body even where
they still have their own loops. What is left duplicated is the LOOP and its
token set, not what the arms write.

Test `test_a_deref_after_a_delegated_member_on_a_pointer_cast` pairs every cast
row with the same chain off a variable — a cast row alone cannot tell a fixed
walk from a language that never allowed this — and rows 5-8 assert the TAG
rather than the parse, since consuming the token is not enough. 8 rows,
byte-identical to fpc.

## 2026-09-06 — four becomes three, by deleting a CALLER

`f56d42898` and `7927fe685` merged the cast-headed assignment target onto the
expression parser and deleted both statement-side arms and `ParseCastTargetSuffix`
with them. So the count did not fall by unifying two bodies; it fell because the
thing that CALLED one of them stopped existing. That is worth saying because it
is the cheaper move and this ticket had not considered it: ask who calls a
duplicated walk before asking how to merge it into its twin.

`grep -n 'while CurTok.Kind in \[tkCaret, tkDot, tkLBrack\]' compiler/*.inc` now
answers five, three of them Pascal:

| where | opener |
| --- | --- |
| `pasparser_lval.inc:5528` | `ApplyCallResultPtrSuffix` — a call RESULT |
| `pasparser_expr.inc:6779` | the record-name cast |
| `pasparser_expr.inc:7331` | the pointer-alias cast |
| `pyparser.inc:48199`, `:48345` | Track N, deliberate — duplicate the parser per LANGUAGE |

### A third census the escape census cannot do

The escape census asks which shared routines a loop reaches, and the re-entry
question asks whether it comes back after delegating. Neither can see a loop that
reaches the right resolver, gets the right answer, and then **overwrites it** —
which is what `7927fe685` found in the pointer-alias caret arm. Its restore fires
on `tyInteger / REC_NONE / 0 / 0`, and that quadruple is BOTH `ResolveDerefShape`'s
decline signature AND its true answer for a `^Integer` field, so the arm could not
tell "no shape recorded" from "the shape is `^Integer`". `PA(q)^.pi^` was refused
in both faces on pin v404 and every other opener of the same chain was right.

The generalisation is worth carrying into the remaining unification: **a fallback
whose trigger is a default value cannot signal "not applicable"**, and the fix is
a separate bit for membership (`pcMovedOff`) rather than a smarter test on the
value. The statement-side copy already had that bit; the expression copy had it
only on the one arm where `.name` is not a field, i.e. the arm a plain field never
takes. Two copies of one rule, and only one of them complete — which is the
argument this ticket exists to make.

### What remains

Unifying the two `pasparser_expr.inc` loops is still not a lift-and-share: the
record-name twin hand-builds its own `AN_INDEX` arm, the pointer-alias twin has
real element-type logic (frozen strings, N-D folding, dyn-array element kinds),
and `ApplyCallResultPtrSuffix` carries the call's own constants. Each arm has to
be shown RIGHT before it can be shown redundant, and the instrument for that is
an opener × chain differential, not a reading.

## 2026-09-06 (frankA) — the record-cast `[` arm is LIVE, and the probe that said otherwise was the wrong program

The ticket's own summary names the divergence that makes this merge harder than
the statement-side one: **the record-cast twin hand-builds its own `AN_INDEX`
arm where the pointer-alias twin has real element-type logic.** So the first
question is whether that hand-built arm is reachable at all — a dead arm makes
the merge a deletion instead of a parameterisation.

**It is reachable, and it has a committed test.** Measured at `85c81be85`,
canary binary `c5b9f15c6811` (a `WriteLn` literal planted at the top of the
`tkLBrack` arm, `pasparser_expr.inc:6839`, removed after; the restored tree
rebuilt back to `faa41e4b920f`, which is the byte-identity check that the
restore was clean):

| program | canary fires |
| --- | --- |
| `TRec(q)[0]` / `TRec(q)^[0]` | **1** |
| `TArr(q)[1]`, `TArr(q)^[1]`, `PArr(q)^[1]` | 0 |
| `test/test_record_name_cast_strides_by_its_record.pas` | **4** |
| `test_a_default_property_subscript_through_a_pointer_cast`, `test_cast_to_array_type`, `test_alias_cast_assign_target`, `test_cast_default_property_target`, `test_indexing_a_string_cast_of_a_pointer_slot` | 0 |
| `compiler.pas` (the whole self-host) | 0 |

`TRec(raw)[i]` is a **deliberate pxx extension** — `PRec(ptr)` without a
declared `PRec` — with **no fpc oracle by construction** (fpc refuses it:
`Illegal type conversion: "Pointer" to "TRec"`). Its test asserts the alias
spelling and the record-name spelling of the *same* access agree, and it exists
because they once did not: `TRec(raw)[0..2].a` gave `10 0 0`, element 0 right by
coincidence, because the cast node's `ASTIVal` was stamped `0` for "plain
reinterpret" and `ir.inc` reads that field as an ALIAS INDEX.

**So the arm's hard-coded `tk := tyRecord; recName := baseRec` is CORRECT for
this opener** — the record-name cast's element *is* the record — and the merge
must parameterise the element type rather than pick either twin's version. That
is the shape of the work: the shared loop takes `elemTk`/`elemRec` as inputs,
the record-name caller passes the record, the pointer-alias caller passes what
its alias row says.

**And my first probe could not have answered this.** I asked `TRec(q)[0]` with
no trailing `.a`, which prints a whole record as an integer — `94489280523`,
garbage from a program that means nothing, next to fpc's refusal. It fires the
canary, so the reach answer was right, but the *value* row was uninterpretable
and would have read as "the arm is broken" rather than "the arm is live". The
corrected shape `TRec(raw)[1].a` answers `11` and agrees with the alias spelling.

### What the merge's guard has to be, and why fpc cannot be all of it

`castwalk/gen.py` is 64 rows over cast openers: `agree=54  PXX-ONLY(no
oracle)=9  DIFFER=1(control)`. **Nine rows have no oracle** — they are this
extension and its relatives, which fpc refuses on purpose. An fpc differential
is therefore blind on exactly the rows the record-cast twin exists to serve.
Those nine need a **pxx-before vs pxx-after byte-identity** check instead: a
refactor that is meant to change nothing makes byte-identity a bug detector,
where an oracle differential can only say "still refused by fpc".

## 2026-09-06 (frankA) — the merge landed in two steps, and what each one could prove

`e40274490` moved the pointer-alias loop out of `ParseFactorCore` into
`ParseCastPostfixSuffix` with NOTHING semantic changed; `27e656541` deleted the
record-name loop and pointed its site at the same body. Split deliberately:
landing both together would have made one diff in which a 300-line move and a
behaviour change were indistinguishable. Step 1 had an exact expected result
(byte-identical output on every row); step 2's diff is only the lines that can
change an answer.

**The instrument grew three things before either step, and each changed what the
numbers meant:**

1. **`{$POINTERMATH ON}`, which gives fpc an ORACLE for `PRec(raw)[i]`.** Nine
   rows moved from PXX-ONLY to `agree` when I added it. I had recorded them as
   oracle-less one commit earlier and they were not — fpc refuses pointer
   indexing only because the harness had not asked for it. **An absent oracle
   can be an absent flag.**
2. **An ADVANCED RECORD** — the only shape where the two dot-arm guards
   disagreed (the record-name loop delegated *every* name once
   `recName >= REC_UCLASS_BASE`; the alias loop delegates only names that are
   not fields). A plain record cannot tell them apart, so without it the merge's
   riskiest line was unasserted. Its `av` field is at **offset 0 and is a
   LongInt**, which a walker that had lost the field type entirely would still
   answer correctly for, so it carries a nonzero-offset twin and a `Double`.
3. **A twin check that branches.** Verified it can fail: pointing `recname` at a
   different record produces 9 `TWIN MISMATCH` lines and exit 1.

**And the rows were proven to REACH the new arm rather than assumed to**, because
identical output is also what a change that never executes produces:

| probe | result |
| --- | --- |
| canary in the `aliasIdx < 0` arm, on `TRec(raw)^.a` | fires |
| the same canary over the whole self-host | silent — `compiler.pas` does not walk it |
| poison `recName` in that arm | 15 lines move, twin check exits 1 |
| poison `ASTIVal[indexNode]` in that arm | **nothing moves** |

The last row is a blank and is recorded as one. The rows that consult that write
reach it through the `[` arm, not the caret arm, so this harness does not assert
it — and it is not being deleted on a null result. **Only `field-dbl`, `method`
and `prop` moved under the `recName` poison**: the discriminating rows are the
ones whose answer depends on a TYPE or a dispatch, never on an offset.


## 2026-09-06 (frankA) — the last merge is a RECONCILIATION, not a deletion, and the gap list is already two silent wrong values

frankB is out of `ApplyCallResultPtrSuffix` (`1aee0f035`, `f919f0cb1`), so the
two remaining Pascal loops are free. Both re-derived at HEAD rather than read
off this ticket's table, which is stale:

| loop | lines | arms | terminator set |
| --- | --- | --- | --- |
| `ApplyCallResultPtrSuffix` `pasparser_lval.inc:5688` | 231 | `tkCaret` `tkLBrack` | `[tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen]` |
| `ParseCastPostfixSuffix` `pasparser_lval.inc:8577` | 320 | `tkCaret` `tkLBrack` | the same five |

**Identical shells. Not an identical body, and this is where it differs from the
last merge.** `27e656541` deleted a weaker twin because the record-name loop was
a strict SUBSET of the alias one, arm for arm. This pair is not: a helper census
over the two bodies gives **11 helpers only the cast loop calls** and **2 only
the call-result loop calls** (`DerefPtrArrayElemPtr`, `RequireRecMember`). So
this one is a reconciliation and has to be planned as one.

**THE GAP LIST IS A BUG LIST, and it predicted two live ones before any code was
read.** Each helper the call-result loop never calls is a capability the call
route may not have, so each got a row in
`tools/call_result_suffix_probe.py` — one chain written twice, once off a CALL
RESULT and once off a pointer VARIABLE holding the same address, against fpc:

```
defprop      pxx call=111481838526725  var=131   fpc 131 | 131   <- FindDefaultProp
frozen-str   pxx call=<220 bytes of heap>  var=b  fpc b | b      <- TypeIsFrozenString
```

`FB^[1]` through a class's DEFAULT PROPERTY answers a heap address where the
variable spelling answers 131, and `FS^[2]` on a `^ShortString` prints a screen
of garbage where the variable spelling prints `b`. Five other rows agree on both
routes and with fpc, and the must-differ control fires in both compilers.

**The variable route is the control and it cannot be wrong for a reason the call
route is also wrong for** — same address, same chain, different loop. That is
the whole design: an fpc differential alone would flag the row without saying
which of the two loops owns it.

**Shape for the merge.** The last one worked because the caller computes a SEED
and passes it: `ParseCastPostfixSuffix(node, tk, recName, aliasIdx, seedTk,
seedRec)`. The call-result site can do the same from its `ProcRet*` columns, and
then the 231-line loop is deleted rather than reconciled line by line. What has
to be answered first is the two helpers that exist only on the call side —
`DerefPtrArrayElemPtr` and `RequireRecMember` — since a seed cannot carry those.

**Not attempted in this pass.** Banked with the instrument rather than
half-merged: the probe is committed and red on exactly two rows, so the merge
has an acceptance criterion that is not "the tests still pass".
