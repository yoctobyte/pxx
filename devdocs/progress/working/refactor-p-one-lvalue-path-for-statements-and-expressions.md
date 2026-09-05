---
slug: refactor-p-one-lvalue-path-for-statements-and-expressions
title: "Two lvalue parsers, and the statement one keeps missing what the expression one learned"
track: P
prio: 55
type: refactor
blocked-by: []
status: working
owner: frankA
created: 2026-08-24
summary: "An assignment TARGET is parsed by a second, smaller copy of the lvalue walk in pasparser_stmt.inc, which resolves every `.name` as a field and ends on Expect(':='). Every capability the expression path gains has to be re-added there by hand, and three bugs so far are exactly that omission: the builtin pointer-name fallback, the PChar adapter, and the deref-then-index shape. The statement path should delegate, as its own cast-headed-CALL arm already does."
---

# The shape

`ParseStatementAST` handles `<name>(...)^.f := v` itself: it builds the
AN_PTR_CAST, walks `^` and `.field` in a small loop, then `Expect(tkAssign)`.
`ParseLValueAST` / the expression parser handle the same syntax with far more in
them — default properties, class casts, metaclasses, the `-2` PChar adapter,
depth-carrying derefs, index-over-deref, builtin pointer names.

The statement copy has to be taught each of those separately, and the failure
mode is always the same: the expression spelling works, the assignment-target
spelling is a compile error or a wrong node.

Known instances, all measured:

- `PInteger(p)^ := 42` was "undefined variable" while `WriteLn(PInteger(p)^)`
  compiled — [[bug-p-a-builtin-pointer-cast-is-refused-as-an-assignment-target]]
  (fixed by copying two lines).
- `PChar(p)^ := 'x'` needed the `-2` adapter copied over as well (same ticket).
- The deref chain's own arms (AN_FIELD / AN_INDEX / AN_CALL depth reads) live
  only in `pasparser_lval.inc`, so any target-position use of those shapes is a
  separate question nobody has swept.

# What to do

The statement path already knows how to hand off: its cast-headed-CALL arm says
*"hand the whole thing to the expression parser, which already builds this chain
correctly"*. Do that for the ASSIGNMENT case too — parse the target with the
expression lvalue parser, then `Expect(':=')` and build AN_ASSIGN over whatever
came back — and delete the duplicated walk.

The catch to measure first: the expression parser resolves a trailing `.name` as
a field/method/property and may CALL it, which in target position must not
happen; and it consumes `[` as an index or a default property. Both are decided
before `:=` is seen, so the hand-off needs the same "this is an assignment
target" flag the class-cast arm passes today. Sweep with a differential over
every target shape (bare, field, index, deref, cast, property, default
property) before and after.

# Gate

Track P's, plus a target-shape differential against fpc 3.2.2, plus the
self-host fixedpoint (this path parses every assignment in `compiler.pas`).


---

## 2026-09-02 (frankH) — the differential this ticket asks for now EXISTS, and it is 23/25

This ticket's gate says: *"Sweep with a differential over every target shape
(bare, field, index, deref, cast, property, default property) before and
after."* That sweep has now been built and run against fpc 3.2.2, so the
before-picture is a measurement rather than an expectation.

**25 target shapes. 23 match FPC exactly.** Bare, field, index, deref,
deref-field, deref-index, pointer-cast-deref, pointer-cast-deref-index, class
field, class-field-index, class-field-record-field, class-field-deref, string
index, PChar deref, PChar index, property, named indexed property, default
property, class-cast-field, class-cast-property, with-block field, record-alias
cast field, and non-pointer alias whole assignment.

That number is the useful part, and it changes what this ticket is worth. The
body above lists three instances and says the statement copy "has to be taught
each capability separately" — all three named ones are already fixed, and the
sweep says the remaining divergence surface is **two shapes**, not a class:

1. [[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] —
   `TAlias(s)[2] := 'X'` stores nothing, silently.
2. [[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]]
   — `TDerived(b)[3] := v` is refused; FPC stores it. Filed 2026-09-02, and the
   sixth measured instance.

**A third was found by the sweep and FIXED rather than filed**, because it was
the dangerous kind: `type TS = AnsiString; TS(s) := 'z'` stored a managed string
through a POINTER-shaped target — this arm is entered on `FindTypeAlias`, which
finds every named alias, and then stamped `AN_PTR_CAST` / `tyPointer`
unconditionally. Length came back `1073741824` and reading the target walked off
into the heap, with **no diagnostic**. The builtin spelling of the same line,
`AnsiString(s) := 'z'`, was already correct on the pinned compiler — the same
one-concept-two-lookup-paths defect the arms above it each carry a comment
about, arriving by a fourth spelling. Regression test:
`test/test_alias_cast_assign_target.pas`.

### What this means for whoever takes the refactor

- **The harness is the deliverable to reuse.** Its worth is that 23/25 is
  now known, so a unification has a gate instead of a hope. It lives in the
  ticket history rather than in `test/` because it is a before/after
  instrument, not a permanent row; rebuild it from the shape list above.
- **The int and char alias rows are load-bearing.** `TI(i) := 5` and
  `TC(c) := 'q'` go through the very arm that corrupted the string case and
  were already correct, which is why the fix above is scoped to managed strings.
  A refactor that re-routes every non-pointer alias must keep those green — and
  when that was tried here it also turned the silent-index bug into a new parse
  error, i.e. traded a wrong value for a different wrong answer.
- **Two of the remaining shapes refuse loudly and one is silent.** If the
  refactor is ranked on risk removed rather than tickets closed, the silent one
  is the whole argument.

---

## 2026-09-02 (frankH, later) — the surface is now ONE shape, and the silent one is gone

[[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] is fixed
(`9339d6661`), so the divergence list from this morning's sweep reads:

| | |
| --- | --- |
| string-alias cast, indexed, read AND written | **fixed** — all four string flavours, matching fpc 3.2.2 |
| [[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]] | still open, and it **refuses loudly** |

**This ticket's argument has changed and whoever ranks it should know how.** The
2026-09-01 sweep noted that *"if the refactor is ranked on risk removed rather
than tickets closed, the silent one is the whole argument."* That silent one is
now fixed, so the remaining case announces itself with a diagnostic. The ticket
is not stale — two lvalue parsers is still the design flaw — but the risk half
of its case is spent, and what is left is tidiness plus one loud refusal.

**And the fix was not a microfix**, which is the part that bears on the refactor
itself: it DELETED a special case. The arm returned early with the subscript
still in the token stream; it now falls through to the suffix loop already
standing below it, and the statement side hands the string to
`ParseClassRecordSelectors` rather than walking it. That is this ticket's own
remedy applied to one arm, and it worked without the flag-passing hand-off the
body above worries about — because there was no resolution step to protect, only
an `Exit` to remove. Two arms down by the same move (the record-cast twin in
`done/` was the first), which is evidence the unification is tractable
incrementally rather than as one change.

---

## 2026-09-04 (frankA) — the 25-shape sweep's divergence list is now EMPTY

The 2026-09-02 note left the sweep at 24/25 and said *"the ticket is not stale —
two lvalue parsers is still the design flaw — but the risk half of its case is
spent, and what is left is tidiness plus one loud refusal."*

**That one loud refusal is fixed** (`d9604ea59`,
[[bug-p-a-class-cast-cannot-index-a-default-property-as-an-assignment-target]]),
so the list reads:

| shape | |
| --- | --- |
| string-alias cast, indexed | fixed 2026-09-02 |
| class-cast default-property store | **fixed 2026-09-04** |

**25 of 25 target shapes now match fpc 3.2.2.**

### What that does to this ticket's case, stated plainly

The remaining argument is **purely** "two lvalue parsers is a design flaw" —
there is no measured divergence left to point at, and no known program that
compiles wrong because of the duplication. Whoever ranks this should rank it as
a refactor on its own merits and not on a defect backlog, because there isn't
one attached any more.

Two things that push slightly the other way and are worth weighing:

1. **The fix continued the pattern this ticket's own history calls tractable.**
   Like the two before it, it DELETED a special case rather than adding an arm:
   the class-cast target arm already hands its suffix to
   `ParseClassRecordSelectors`, and the bug was that the shared walker's
   default-property arm was incomplete. Three arms down by the same move, none
   of which needed the flag-passing hand-off the body worries about.
2. **The body's central worry has not been tested and is now cheaper to test.**
   It says the hand-off needs an "this is an assignment target" flag because the
   expression parser *"resolves a trailing `.name` as a field/method/property
   and may CALL it"*. In practice the shared walker answers that question itself
   — the NAMED-property arm peeks past the bracket group for `:=` and the
   DEFAULT arm now does too. If the walker can always decide locally, **the flag
   is not needed and the hand-off is smaller than this ticket assumes.** That is
   the single measurement that would most change the estimate, and it is one
   afternoon.

### The harness

The body says *"rebuild it from the shape list above"*. Still true, and there
are now three permanent rows in `test/` covering what used to be its findings:
`test_alias_cast_assign_target.pas`, `test_cast_default_property_target.pas`,
and the string-alias index test. Those are regression rows, not the sweep — the
sweep is still a before/after instrument and still worth rebuilding for the
refactor itself.

---

## 2026-09-05 (frankA) — the flag question is ANSWERED, and the answer is a third finding

The 2026-09-04 note named *"the single measurement that would most change the
estimate"*: the body says the hand-off needs an "this is an assignment target"
flag because the expression parser *"resolves a trailing `.name` as a
field/method/property and may CALL it"*, and the note observed that in practice
the shared walker peeks past the bracket group for `:=` and may not need to be
told.

**Measured. The walker decides locally in every arm, and the arms do not decide
the same way.** Listed, not counted, in `pasparser_lval.inc` at `2792cec8f` --
every site that picks a property's READ or WRITE accessor:

| line | receiver spelling | how it peeks for `:=` |
| --- | --- | --- |
| 833 | bare name inside a method | balances the bracket group |
| 2474 | instance-qualified, `c.P` | balances |
| 4574 | the selector walker | balances |
| 4962 | default property, `obj[i]` | balances |
| 1169 | the class name, `TC.P` | `CurTok` and one token past it -- **fixed** |
| 516 / 539 | with-scope | `CurTok` only, and only the FIELD slots -- **fixed** |
| 735 | bare name, class-var-backed accessor | `CurTok` only; NOT investigated, and it re-enters on a backing global rather than building a call, so whether an indexed spelling can reach it is an open question |

For an INDEXED property the `:=` sits after the whole subscript, so an arm that
peeks at `CurTok` reads the `[`, concludes "read", and calls the GETTER for a
write. **The balanced scan is a copy-paste that reached four sites and not the
other three**, and nothing in the tree says which arm has it.

That is not an argument against the unification — it is an argument for it, and
of a different kind than the ticket has been carrying. The ticket's case has
been *"two lvalue parsers is a design flaw, with no defect backlog attached"*
since the 25/25 sweep. The defect backlog was not absent; it was **inside the
one walker**, in the arms nobody had lined up against each other. Two live bugs
came out of the census the same afternoon:

- [[bug-p-a-class-property-cannot-be-indexed]] — `TC.A[2] := 7` picked the read
  accessor, `WriteLn(TC.A[2])` left the `[` behind, and `index N` reached
  neither direction. The class-name arm hand-built its accessor call.
- [[bug-p-a-with-scoped-property-with-method-accessors-is-undefined]] — a
  with-scoped property resolved only through a backing FIELD; a getter/setter
  pair was `undefined variable`. The arm declined method accessors in a
  comment.

**Both are the same omission, and it is the one this ticket's remedy is about:
an arm that resolves a property WITHOUT going through `pasparser_call.inc`'s
four accessor helpers.** Those helpers exist and their own header says eleven
sites had built the dispatch by hand; the two arms above were among the ones
still doing it. Fixing each meant deleting hand-built call construction, not
adding a case — the same move the three earlier increments made.

### What this changes for whoever finishes the refactor

1. **The flag is not needed, and the reason is stronger than "the walker can
   decide".** It already does decide, at every site in the table above, from the
   token stream alone. What it lacks is ONE decision, not a caller's flag — the peek is
   copy-pasted with two different degrees of care. **Unifying the peek is a
   smaller and better-defined job than unifying the two parsers, and it removes
   the class both of today's bugs came from.** That is the next increment.
2. **The escape census generalises from the postfix loops to the ACCESSOR
   calls.** [[refactor-p-three-hand-rolled-postfix-loops]] built a census of
   which shared routines each suffix loop reaches, and it predicted four
   defects. The same instrument aimed at `MakeAccessorCall` /
   `AccessorArgChain` / `ParsePropIndexArgs` / `PropIndexConstArg` predicted
   these two. Run it before the unification, not after.
3. **A "no defect backlog attached" reading of a duplication ticket should be
   re-taken whenever the duplication is INSIDE one routine.** The 25-shape
   sweep varies the TARGET SHAPE against a fixed receiver spelling; both bugs
   here need a varied RECEIVER (class name, with-scope) at a fixed shape. The
   sweep was sound and its population was the wrong axis — which is why it read
   as 25/25 while two arms were broken.

---

## 2026-09-05 (frankA, later) — the peek IS unified, and the seventh row paid for itself

The note above named the next increment as *"unify the peek, not the parsers"*
and recorded line 735 as **NOT investigated** rather than as clean. Both of
those decided what happened next.

### `PropAccessIsWrite(afterNameTok)` — one decision, nine call sites

It lives in `pasparser_call.inc` beside the other accessor helpers. The
parameter is the index of the first token AFTER the property name, spelled out
rather than derived, because **the callers do not agree on whether the name is
consumed**: arms reached from `ParseLValueAST`'s entry have it consumed already
(pass `TokPos - 1`), the selector walker still has `CurTok` on the name (pass
`TokPos`). That disagreement is exactly why two of the copied scans started at
`TokPos` and two at `TokPos - 1`, and it is the thing a shared helper has to
carry rather than hide.

Its bracket test is on the TOKEN, not on `UPropIsIndexed`, which is what closed
the seventh row.

### Investigating line 735 took one probe and found the silent one

The row said "we did not look". Looking cost one file. A FIELD-backed property
**can** carry a subscript in pxx — fpc refuses that declaration, so there is no
oracle and accepting it is not a defect — and with `read FR write FW` over two
array fields, **one declaration gave three answers across four receiver
spellings**:

| spelling | before |
| --- | --- |
| `c.A[2] := 7` | FW — correct |
| `Self.A[1] := 8` | FW — correct |
| `A[1] := 8` (bare, in a method) | refused: `indexed property has no setter: A` |
| `with c do A[3] := 9` | **FR — stored through the READ field, silently** |

The with-scope row is the one worth the test: it stores through the read field
**and the read-back agrees**, because the read goes to the same wrong place. An
`expect_same` row comparing a write to its own read-back cannot fail on it.

Both are fixed — the peek unification fixes the with-scope store, and the bare
arm gained the field-backed branch it never had (decided BEFORE
`ParsePropIndexArgs`, because a field backing takes the subscript as an ARRAY
index and the `[` has to stay in the stream for the suffix loop). All four
spellings now store through FW and read from FR.

**No oracle is not the same as no verdict.** fpc refuses this declaration, so
there is nothing to differ from — but answering differently in four places is
an INTERNAL inconsistency, which is a defect under any policy, the same
standing the variant part's own alignment row had.

### What is left of this ticket

The peek is one function. What is still two parsers is the **walk** — the
statement side's cast-target loop against `ParseLValueAST` — and that is the
original ask, now with no accessor-direction defects left under it. Two
permanent rows exist as the positive control a unification needs:

- `test/test_indexed_property_every_receiver_spelling.pas` — one indexed
  property through bare / `Self.` / `c.` / with-scope, expected output fpc's
  own, getter +100 so a wrong direction prints 100 off rather than failing.
- `test/test_indexed_property_over_a_field_is_one_answer.pas` — the same matrix
  over FIELD accessors, asserted for internal consistency against **no oracle by
  construction**, with read and write on DIFFERENT fields because that is the
  only way a wrong choice is observable.

The class-name spelling and the `index N` modifier are in
`test/test_class_property_indexed.pas`.

---

## 2026-09-06 (frankA) — the statement side's two cast-target walks are ONE, and the census that gates it

The note above left this ticket with *"what is still two parsers is the WALK —
the statement side's cast-target loop against `ParseLValueAST`"*. The statement
side did not have **a** cast-target loop; it had **two**, and they were character
for character identical apart from the `^` arm — the delegation branch that
hands `.` and `[` to `ParseClassRecordSelectors` was byte-identical between them.

`ParseCastTargetSuffix` is now the one body (`8627d25ce`), and **the difference
between the two copies collapsed to one boolean because it is a fact about the
CAST rather than a preference:**

| | the `^` arm |
| --- | --- |
| record-name cast | the pointee is the cast's own record, known here; the node carries `ival 0`, so there is no alias row and asking `ResolveDerefShape` would index alias 0 |
| pointer-alias / PChar cast | the alias row carries depth, base kind and base rec, so the resolver is asked |

Both copies had separately learned, months apart, that **after delegation the
seed is never the answer** — the value in hand is a field and its pointee has
nothing to do with the cast. `TA(b).pi^ := 7` and `PA(q)^.pi^ := 7` were each
refused for exactly that and each fixed on its own copy. One routine is the only
thing that stops that being a coincidence.

103 insertions, 124 deletions. Two of the five hand-rolled Pascal postfix walks,
so this is an increment on [[refactor-p-three-hand-rolled-postfix-loops]] too.

### The census, and why it is a different axis from the 25-shape sweep

The 25-shape sweep varies the target SHAPE at a fixed receiver and has been
25/25 for two days. **A duplicated WALK is invisible to it**, the same way the
receiver-spelling census found two live bugs that a shape sweep could not. So
this one varies **the CAST SPELLING** at fixed shapes:

- 7 openers — no cast, plain deref, call result, record-name deref, record-name
  in place (no leading `^`), alias deref, alias double-deref — × 9 chains
  (field, deref-field, index, deref2-field, method; read and write).
- A second block for the two pointer-alias LOOKUP paths, which is this ticket's
  own recorded *"one concept, two lookup paths, and the second one never got the
  fallback"*: `PRec` via `FindTypeAlias` against `PInteger` via
  `EnsureBuiltinPtrAlias`, plus PChar.

Controls are OPENERS, not extra rows, so a chain wrong for everyone shows up as
a COLUMN. The harness carries its own must-differ row, because `63 agree` and
`63 rows that never compiled` print the same otherwise.

**Identical on both sides of the change: 54 agree, 9 PXX-ONLY(no oracle), 1
DIFFER which is the control.** The nine are the whole `TRec(raw)^` column — fpc
refuses a record-name cast of an untyped pointer followed by a deref, and
accepting what fpc rejects is not a defect. **No oracle is not no verdict:**
that column answers 11/77/33/5/18/42/43/44/45, which is what all four
oracle-backed openers answer, so it is internally consistent with them on every
chain.

### Recorded blanks, because a "not looked at" cell is a work queue

- The class-name cast arm (`AN_CLASS_CAST`, a few hundred lines above) is NOT in
  the opener set. Its chains are class fields, not record fields, so it needs
  its own header rather than a row.
- The `SetLength(TS(s), n)` and string-alias arms are not in it either; they
  have permanent rows in `test/`.
- No NilPy row was run. `pyparser.inc` keeps its own two copies **by design**
  (`the-substrate-is-ast-and-ir-not-the-parser.md`), so they are not part of this.

### What is left

Three hand-rolled walks, all on the expression side: two in
`pasparser_expr.inc` and one in `pasparser_lval.inc`. **They are not the same
merge** — the expr record-cast twin hand-builds its own `AN_INDEX` arm where
the statement side delegates `[`, so unifying those is a question about whether
that arm is right, not about lifting a body. That is the next measurement, and
it wants its own census of what indexing a record cast is supposed to yield.

---

## 2026-09-06 (frankA, later) — the question about the hand-built arm has an answer, and it is a silent wrong address

The note above named the next measurement: the expr record-cast twin hand-builds
its own `AN_INDEX` arm where the statement side delegates `[`, so **the question
is whether that arm is RIGHT, not whether a body can be lifted.**

**It is not, and neither is the delegation.** Both sides are wrong in the same
place and self-consistently so, which is why no sweep had caught it.

```
t: array[0..2] of TRec;   a = 10 11 12

PRec(raw)[0..2].a    10 11 12      the pointer-alias spelling
TRec(raw)[0..2].a    10  0  0      the record-name spelling
```

Element 0 is right **by coincidence** — it needs no stride. And as an assignment
target it is the quiet kind: `TRec(raw)[1].a := 71` left `t[1].a` at 11 and then
**read back 71 through the same cast**, because the read goes to the same wrong
address. A row comparing a store to its own read-back cannot fail on it.

### The cause was one number, and two AST dumps found it

The same access under both spellings differs in **exactly one field**:

```
alias    #8195 kind=39 tk=17 ival=14      <- an alias row
recname  #8195 kind=39 tk=17 ival=0       <- "plain reinterpret, no adapter"
```

`ir.inc` reads that field as an **alias index**, and `0` passes its `< 0` test
for "no alias", so the stride came from **alias row zero — whatever type the
program declared first.** A default that is also a real answer cannot signal
"not applicable"; that is the trap the PChar adapter fallback already carries a
paragraph about one file over, arriving here through a different field.

Fixed in `b7b9e309e` by minting the row the cast should always have carried
(`EnsureRecPtrAlias`), which fixes **both** `ir.inc` sites that read the field
rather than teaching either one what a record cast is.

### What this says about the remaining three walks

**Delegating is not the fix by itself.** The statement side already delegates
`[` here and was equally wrong, because both consumers read the same missing
field. So the remaining merge is not "lift the body and delete the hand-built
arm" — the hand-built arms and the shared walker have to agree about what the
NODE carries first. That is a smaller and better-defined question than the
merge, and it is the one to answer next:

**for each of the three remaining loops, what does its opener stamp on the node,
and does every consumer of that field read the same encoding?** The escape
census answers "which shared routines does this loop reach"; this one is "what
does it hand them", and the two are not the same instrument.

### Recorded blank

`EnsureRecPtrAlias` mints a row with `AliasPtrDepth = 0` and no base kind, which
is what `RegisterPtrAlias` writes; a source-declared `PRec = ^TRec` gets those
filled by the `^T` parse. Every row of the fixture and all three censuses agree
across the change, so nothing measured needs them — but **`^^` through a
record-name cast was NOT probed** and is where a missing depth would show.
