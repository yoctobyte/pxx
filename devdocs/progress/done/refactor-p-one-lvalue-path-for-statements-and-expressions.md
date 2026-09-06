---
slug: refactor-p-one-lvalue-path-for-statements-and-expressions
title: "Two lvalue parsers, and the statement one keeps missing what the expression one learned"
track: P
prio: 55
type: refactor
blocked-by: []
status: done
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

### The recorded blank, and it is now closed

`EnsureRecPtrAlias` mints a row with `AliasPtrDepth = 0` and no base kind, which
is what `RegisterPtrAlias` writes; a source-declared `PRec = ^TRec` gets those
filled by the `^T` parse. The shape that would read them is a double deref
through the cast ITSELF, which the censuses do not spell — `deref2-fld` is
`TRec(raw)^.n^.a`, whose second `^` is on a FIELD.

**Probed rather than argued.** `TRec(raw)^^.a` beside `PPRec(raw)^^.a` over the
same bytes: both answer 11, **and both answer 11 on pin v403 as well**. So the
minted row did not move that shape, which is the half that matters — the pin row
is what says the agreement is not something my change arranged. Depth is not
read for a record-name cast on any shape that can be written, so the blank is
closed rather than left open.

---

## 2026-09-06 (frankA) — there are THREE readers of that field, not the two recorded above

The paragraph "fixes **both** `ir.inc` sites" is a true statement about `ir.inc`
and an incomplete census of the ENCODING. Running the census this ticket asks
for — *what does the opener stamp, and does every consumer read the same
encoding* — found a third reader outside `ir.inc`:

```
compiler/pasparser_lval.inc  ResolveDerefShapeAt
      else if (DwDispatchKind(node) = AN_PTR_CAST) and (ASTIVal[node] >= 0) and
              (ASTIVal[node] < AliasCount) then
      begin
        tk := IntToTypeKind(AliasElemTk[ASTIVal[node]]);
        recName := AliasElemRec[ASTIVal[node]];
```

`0` satisfies `>= 0 and < AliasCount`, so this arm was also answering from
**alias row zero** for every record-name cast — the same defect as the two
`ir.inc` sites, in the file this ticket is about, reached by a different guard
spelling. `b7b9e309e` corrects it too, because the fix is at the WRITER.

**How it was found is the transferable part.** Grepping the two sites I already
knew about could only re-confirm them. Naming the ENCODING first —

```
-3 WideChar value cast   -2 PChar adapter   -1 plain value cast   >=0 alias row
```

— and then listing everyone who reads `ASTIVal` on an `AN_PTR_CAST` is what
turned up the third. A census of an encoding is a different instrument from a
census of call sites, and only the first one is closed-world.

So the question posed above for the remaining three walks stands unchanged, with
its scope corrected: *does every consumer of that field read the same encoding*
means **every** consumer, and the count of consumers is itself something to
measure rather than carry forward from the last commit message.

The NilPy sibling of the same stamp (`pyparser.inc`) is the third copy of the
WRITER; it is a separate commit and carries an explicitly unconstructed
reachability claim rather than an implied repro.

### …and the same census run over the THREE REMAINING LOOPS answers clean

The measurement recorded above — *for each of the three remaining loops, what
does its opener stamp on the node, and does every consumer of that field read
the same encoding?* — is now run rather than promised. The three are
`ApplyCallResultPtrSuffix` (`pasparser_lval.inc:5447`) and the two cast-suffix
walks in `pasparser_expr.inc` (`:6767` record-name, `:7274` pointer-alias).

All three stamp the SAME triple on the `AN_DEREF` they build:

```
ASTSOffset := remaining pointer levels     (0 = "this deref lands on the base")
ASTSLen    := ultimate base type kind      (0 = tyUnknown = "not recorded")
ASTIVal    := ultimate base record id      (REC_NONE = 0 = "no record")
ASTTk      := StrValTk(tk)
```

and all three now reach `ResolveDerefShape` for it. **There is no second
encoding among them.** The `AN_PTR_CAST` writer was the only disagreement, and
it is fixed.

Two apparent inconsistencies checked and dismissed, so nobody re-checks them:

- `if baseRec > 0 then ASTIVal[n] := baseRec` (lval, stmt) versus a bare
  `ASTIVal[n] := baseRec` (expr, pyparser) are **equivalent**, not two
  conventions: `REC_NONE = 0` (`defs.inc:468`) and `AllocNode` zeroes `ASTIVal`
  at birth (`ast_arena.inc:59`), and every producer initialises `baseRec` to
  `REC_NONE` before the resolver runs, so the guard can only ever skip a write
  of the value already there. Each node is freshly allocated per iteration, so
  there is no re-stamp path where the guard could preserve a stale id.
- the non-delegated `^` arm of `:6767` stamps `ASTIVal` and *not* depth/base.
  That is correct and not an omission: it is the FIRST `^` on a record-name
  cast, where the pointee is the cast's own record and the remaining depth
  really is zero. Depth only becomes a question after delegation, which is the
  arm that calls the resolver.

**So the encoding is not what blocks the merge.** That was the open risk this
ticket recorded, and the answer is that it is closed: the remaining three walks
already agree with the shared walker about what an `AN_DEREF` carries. What is
still unmeasured is the CONTROL-FLOW half — whether the shared walker consumes
the same token sets (`ParseClassRecordSelectors`'s own loop is `[tkDot,
tkLBrack]` with **no `tkCaret`**, which is precisely what stranded `TA(b).pi^`),
and whether an assignment-target hand-off can suppress the call the expression
path would make on a trailing `.name`. Those are the next measurement; the
field-encoding question is answered and should not be re-opened.

**Negative results are recorded here on purpose.** An agreement nobody wrote
down is re-derived by the next session at full price, and worse, "not checked"
and "checked, agrees" are the same silence in a ticket.

**Correction to the subject line of `1af1ad7ab`.** It reads *"the reader count
was 2, not 3"*, which says the opposite of the finding. **It was recorded as 2
and it is 3.** The body of that commit and both sections above are correct; only
the subject is inverted, and it is pushed, so it cannot be amended without
rewriting a shared master. Anyone grepping commit subjects for the reader count
gets the wrong number — this line is the copy that says so.

Recorded rather than quietly left because the failure is exactly the one the
commit is about: a count that travels in a summary while the measurement behind
it says something else, and the summary is the part everyone reads.

## 2026-09-06 (frankA) — the hand-off risk is MEASURED, and it is one mechanism

This ticket's "catch to measure first" — *the expression parser resolves a
trailing `.name` and may CALL it, which in target position must not happen* — is
now measured rather than feared, and the answer changes what the merge has to
build.

**The flag this ticket asks for already exists, and it is not a flag.**
`PropAccessIsWrite` (`pasparser_call.inc:751`) is a token LOOKAHEAD: after the
name, either `:=` directly, or a balanced `[...]` group followed by `:=`. Every
property arm in `pasparser_lval.inc` already calls it. So the hand-off does not
need a caller-supplied "this is an assignment target" bit — the walker can see
it for itself, and has been doing so.

**Measured with side-effecting accessors rather than by reading.** A class whose
getter and setter each `WriteLn` their own name turns "which accessor fired"
into a printed trace. Nine target shapes off a plain receiver — plain property,
indexed property, default property, each read and write, plus a property
returning a pointer stored through — are **byte-identical to fpc 3.2.2,
including which accessor fires and in which order.** The lookahead is correct on
every shape that can be spelled.

### The three that fail are ONE mechanism, and it is the merge

Through a CAST-headed target, all three property spellings are refused:

```
PTC(raw)^.P := 21        expected ':=' before ';'      (fpc: SetV, v=21)
PTC(raw)^.A[2] := 22     expected ':=' before ';'      (fpc: SetA)
PTC(raw)^[3] := 23       expected ':=' before ';'      (fpc: SetA)
```

and all three are correct through the variable spelling `pc^...`, and all three
pre-date pin v403. **The error text names the mechanism**: the statement path
delegates, `ParseClassRecordSelectors` sees the `:=` via `PropAccessIsWrite`,
performs the WHOLE store and returns a call node — and `ParseStatementAST` does
not know the assignment already happened, so it demands its own `:=`.

So the merge's real problem is **not** suppressing a call the expression path
would make. It is the opposite: the shared walker sometimes does the entire
statement, and the hand-off needs a way to say so. The class-cast arm already
lives with this — its comment records `TDerived(b)[3] := 206` coming back "as a
CALL, the caller took it for a method-call statement". **That convention is the
thing to design, and it is smaller than the merge this ticket describes.**

**A refusal is the safe failure here and worth noting as such**: these three are
diagnostics, not wrong values. The one SILENT member of the same family was in
expression position — `t := PTC(raw)^[3]` reading the object as a raw array,
fixed in `25cdaac51` — which is the usual asymmetry: the target-position bug
announces itself and the read-position bug does not.

### What this ticket now needs

Not a differential over every target shape — that is run, and the receiver-side
answer is clean. It needs **one decision**: how a delegated walk reports "I
consumed the assignment". Once that exists, the statement path's remaining
duplicated walk can be deleted rather than converged arm by arm.

## 2026-09-06 (frankA) — the blocker is GONE, and it was the opposite of the one recorded

`4238fe9c7`. The convention this ticket needed exists and the three refusals it
was measured on are fixed.

**What the hand-off actually needed** was not a way to suppress a call. It was a
way to say *the walk already performed the store* — because
`ParseClassRecordSelectors` asks `PropAccessIsWrite` for itself, emits the
setter, and consumes the `:=` and the value with it. Both cast arms then ran
`Expect(tkAssign)` on a token that was gone.

The convention is the one `pasparser_stmt.inc` already used for the non-cast
spellings — **a call node in target position IS the statement** — plus one
conjunct that makes it sound: **the `:=` must be gone.** Three cases, separated
by that conjunct alone:

| shape | node | `:=` | outcome |
|---|---|---|---|
| `PTC(raw)^.P := 21` | call | consumed | the statement |
| `PTC(raw)^.Bump;` | call | absent | the statement (was refused) |
| `PTC(raw)^.GetV := 5` | call | still there | error, as before |

Reading the token stream is not a weaker signal than an out-parameter here — it
is the same fact, taken from the one place that cannot disagree with itself.

**A comment I wrote before measuring was wrong and is corrected in the same
commit.** I claimed case three fell through to *"cannot assign to the result of
a function call"*. It did not: it answered `IR_UNSUPPORTED ... could not lower
AST node (kind 8)` — an internal message for an ordinary user mistake, on the
pin too — because the single-exit guard tests the RETURNED node for being a
call and the cast branches hand back an `AN_ASSIGN` whose LEFT is the call.
Extended at that guard rather than in the branch, which is what its own comment
argues for.

### What is left of this ticket

The blocker is discharged, so the remaining work is the merge itself: parse the
target with the expression lvalue parser, take whatever comes back, and delete
`ParseCastTargetSuffix` and the arms around it. Everything this ticket listed as
unknown is now measured:

- the assignment-target flag — **exists, and is a lookahead, not a flag**
- whether the shared walker over-calls a trailing `.name` — **it does not; nine
  receiver-side shapes are byte-identical to fpc including accessor identity
  and order**
- whether it mis-consumes `[` — **it does not; it dispatches the default
  property correctly in both faces**
- what happens when it completes the store — **the convention above**

**The one thing still unmeasured is the deletion itself**, and it should be done
as a differential over target shapes before and after, not as a reading. The
harness for it is the accessor-trace program used here: give every accessor a
side effect that names itself, so a store that reaches the setter and a store
that goes somewhere else are distinguishable even when the resulting VALUE is
the same. `arr[3]` is written both by the setter and by a raw subscript, so a
value diff cannot see the difference; the trace can.

## 2026-09-06 — the merge landed, and it is PARTIAL because a canary said so

`ParseStatementAST`'s cast-headed delegation lost its `not StatementIsAssignment`
conjunct, so an assignment TARGET headed by a record-name or type-alias cast is
now parsed by the expression parser and the statement builds the `AN_ASSIGN`
over whatever comes back. **The record-name cast-target arm — 110 lines that
rebuilt the in-place value cast, the pointee-tagged deref and the suffix walk a
second time — is deleted.**

### The deletion is by GUARD SUBSUMPTION, and the canary only corroborates

The deleted arm's test was `IsRecordType(name) >= REC_UCLASS_BASE`; the
delegation's is `IsRecordType(name) <> REC_NONE`, over the same `node = -1` and
the same `tkLParen`. The first implies the second, and the delegation runs
first, so no input can reach the arm. A canary planted inside it never fired —
through the self-host, the 44-row target differential, the four cast tests and
a 57-row before/after over every Pascal fixture in the test tree containing a
cast in target position — which is agreement with the subsumption, not a
substitute for it.

### The pointer-alias arm STAYS, and the canary is the reason

Planted in both arms, the ALIAS one fired **during the self-host itself**. The
delegation's guard asks `FindTypeAlias(name) >= 0`, and that arm is entered on
more: `EnsureBuiltinPtrAlias` mints a row for a BUILT-IN pointer name after the
guard has already said no, and the PChar adapter has no alias row at all. So the
merge is partial, and the measurement — not a reading of the two conditions — is
what says which half.

### The merge found a live bug in the path it delegates TO

`PA(q)^.pi^` with `pi: ^Integer` was refused in **both** faces —
`x := PA(q)^.pi^` "cannot assign record to Integer", `PA(q)^.pi^ := 11`
"cannot assign Integer to record" — on the pinned compiler too, while every
other opener (`b.pi^`, `vpa^.pi^`, `TA(b).pi^`) was right throughout.

`pasparser_expr.inc`'s pointer-alias postfix loop restores the alias's element
type whenever `ResolveDerefShape` answers tyInteger / REC_NONE / 0 / 0 — which
is BOTH that resolver's decline signature AND its true answer for a `^Integer`
field, so a correct answer was overwritten with the record `PA` points at.
`ParseCastTargetSuffix` already gates its copy of this restore on `not
delegated`; this loop had the bit only on the arm where `.name` is NOT a field,
which is the one arm a plain field never takes. The bit is now set by every
suffix that is not a `^` (`pcDelegated` → `pcMovedOff`), which is the fact it
was always about: the walk has LEFT the cast.

**A statement-side merge is how this was found.** The store face was going
through `ParseCastTargetSuffix`, which had the gate; delegating moved it onto
the expression copy, which did not. The 44-row differential could not see it —
its record openers are `r`, `pr^`, `ppr^^`, `TRec(raw)^`, `PRec(raw)^` and none
of them dereferences a POINTER FIELD reached through the cast. The 57-row
before/after over the test tree did, on `test_cast_field_deref`, which is the
test whose own header documents the three sibling instances of this same
mistake. Rows added to it for the ASSIGN face (`x := <chain>`), which is the
face that reads `ASTTk`; `WriteLn` re-derives and printed the right value off a
wrongly-tagged node throughout. The pin refuses the new rows, which is the
positive control.

### What is left

- `ParseCastTargetSuffix`'s `aliasSeeded` parameter now has one caller and it
  passes a literal `True`; the record-name mode of that routine is unreachable.
- The pointer-alias statement arm itself, which needs the delegation guard to
  ask the same question `EnsureBuiltinPtrAlias` answers rather than
  `FindTypeAlias` alone.

## 2026-09-06 (second half) — the arm the canary kept alive is dead now, and the guard is why

The partial merge was partial because the **guard was narrower than the arm**,
not because the arm could do anything the delegation could not. Widening it to
the arm's own three entry conditions —

```
(IsRecordType(name) <> REC_NONE) or (FindTypeAlias(name) >= 0) or
(BuiltinPtrNameElemTk(name) <> tyUnknown) or
CaseEqual(name, 'pchar') or CaseEqual(name, 'pansichar')
```

— makes it subsumption rather than resemblance: `BuiltinPtrNameElemTk` is the
pure predicate `EnsureBuiltinPtrAlias` is built on (its first line, and its only
reason to return -1), so the guard decides exactly what the arm decided and mints
nothing while deciding it.

**The same canary, two answers, and the difference is one line of guard.** With
the narrow guard it fired during the self-host and named the missing disjunct.
With the wide guard it is silent — self-host, the 44-row target differential,
the 57-row before/after. That is what a canary is good for and it is *all* it is
good for: it proves REACH. The before/after is what proves the replacement is
EQUIVALENT, and the first half of this merge is the case in point — the canary
was silent, the arm really was dead, and the merge still landed a regression on
a shape the differential caught (`PA(q)^.pi^`).

Deleted: the pointer-alias cast-target arm (224 lines) and
`ParseCastTargetSuffix` (95 more, last caller). `aliasIdx`, `fieldNode`,
`indexNode`, `castRec`, `castElemTk`, `castElemRec` and `pcharCast` leave
`ParseStatementAST`'s var block; nothing in that routine holds a cast's shape any
more.

Both string sub-arms went with it and **were already dead at `f56d42898`** —
`FindTypeAlias >= 0` was in the guard from the first half — so `TS(s) := 'z'` and
`t(p) := 'abc'` over a Pointer slot have been served by the expression path since
then, with `test_a_string_alias_cast_over_a_pointer_slot`,
`test_string_alias_cast_index` and `test_alias_cast_assign_target` green
throughout. Their rationale lives in those tests and in
[[bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer]];
the arm was the third place it had been written down.

**Done.** There is one lvalue path for a cast-headed assignment target and it is
the expression parser.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
