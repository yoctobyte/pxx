---
slug: bug-p-generic-constraints-are-checked-before-the-type-section-closes
track: P
prio: 70
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "DONE, 35/40 -> 39/40 on fpc-testsuite tgenconstraint*.pp. Constraint checking ran inside ParseSpecialization, where 'not a class' and 'not declared yet' are the same observation. First half: a builtin scalar and the metaclass TClass are now refused by a class/constructor/named-type constraint (4 and 5), DEFERRED to type-section close so a user type shadowing a builtin name is not falsely rejected. Second half: a FORWARD stub (38, 39) is NOT 'an error in its own right' -- that was this ticket's proposed rule and six fpc oracle rows refute it. A stub is a class whose ancestry is TObject and which implements nothing yet, judged AT the specialization point: (none), `class` and `TObject` are ACCEPTED, `record`, a deeper named class and any interface are REFUSED. The fix is a DELETION -- the `if UClsForward[argCi] then Exit;` guard -- because the checks behind it were already correct and simply never ran. Only 37 remains, rejected-valid and pre-existing."
owner: frankwasm
---

# P: generic constraints are checked before the type section closes

Follow-up to [[bug-p-generic-type-constraints-are-parsed-and-discarded]], which
implemented constraint checking and took 33 of the 40 FAIL-marked
`tgenconstraint` tests from wrongly-accepted to correctly-rejected. This is the
residual, and it is a **placement** problem, not a rule problem.

## The defect

`CheckTemplateConstraint` is called from `ParseSpecialization`
(`pasparser_generic.inc`), which is mid-parse. At that moment "this name is not
a class" and "this name is not declared yet" are the same observation:

```pascal
type TInner<T: class> = class end;
     TC = class end;          { declared BEFORE the use... }
     TA = TInner<TC>;         { ...and still unknown when the check runs }
```

`DelphiRewriteGenericUses` desugars `TInner<TC>` by inserting the alias
declaration at `insertAt` — immediately after the TEMPLATE — so the
specialization is parsed *ahead of* `TC`. The objfpc spelling hits the same wall
through a forward `TC = class;`, whose stub carries no parent link, so a
`T: TObject` constraint finds no ancestor chain to walk.

Both were **measured** as false rejections on an intermediate build, which is
why the shipped check bails out on any argument that is not an already-declared
non-forward class.

## What that costs

| | |
| --- | --- |
| `tgenconstraint4` — `TTest1<LongInt>` vs `T: class` | still accepted |
| `tgenconstraint5` — `TTest1<TClass>` vs `T: class` | still accepted |
| any constraint against a forward-declared class | not enforced |
| any constraint against a class declared later in the section | not enforced |

All **missed rejections, never wrong ones** — the failure mode is laxness, which
is the right way round for a check that did not exist at all until today.

## The fix

> **CORRECTED 2026-08-31 (frankwasm) — read the note at the bottom before
> implementing this section. Measured against fpc 3.2.2, deferring the check to
> the end of the type section produces the WRONG answer for `tgenconstraint39`.
> The section below is kept as filed; it is no longer the plan.**

Record `(ti, k, argName, argKind, line)` at `ParseSpecialization` instead of
checking there, and drain the list when the type section closes — by which point
every type in the section is declared and `UClsForward` has been cleared.

**The hook already exists and already lives in Track P's own file:**
`FlushPendingClassSpecializations` (`pasparser_generic.inc`), called from
`pasparser_decl.inc` at `TypeSectionDepth = 0`.

**The one obstacle is that the call is guarded:**

```pascal
if (PendingSpecCount > 0) and (TypeSectionDepth = 0) then
begin
  Dec(TokPos);
  FlushPendingClassSpecializations;
  Next;
end;
```

A pending-constraint list cannot reach it when `PendingSpecCount = 0`, which is
the common case. Making that call unconditional — or adding a separate
unconditional drain beside `ResolvePendingPointerAliases` on the line below — is
**one line in `pasparser_decl.inc`**, which was held by another session on
2026-08-30 (a multi-hour proc-shape refactor). Hence this ticket rather than the
edit.

Note the `Dec(TokPos)`/`Next` bracketing around the existing call: a drain that
only reads types and reports errors does not need it, so the cheaper change is a
new unconditional call, not a widened guard.

## Also worth folding in when this is done

- `T: constructor` is currently enforced only as "must be a class". The corpus
  pins exactly that much; the parameterless-constructor half is unverified and
  was deliberately left out.
- `GCSupportsIntf` reconstructs the DECLARED interface set from the IMT closure
  by prefix order (see the parent ticket). Exact for every shape in the corpus;
  its one blind spot is a class redundantly listing both a derived interface and
  its ancestor in that order. Recording `implOrig` in `defs.inc` would make it
  exact — also a frankwasm-file change, so also deferred here.

## Raised 40 -> 70: this is now a live regression, not a latent one-liner (coordinator, 2026-08-30)

`f4fb9d31b` (*"generic type constraints are recorded and checked"*) made
constraints load-bearing for the first time — correctly; 40 FAIL-marked
`tgenconstraint` tests were being wrongly accepted. The moment it landed, this
ticket stopped being a timing curiosity nothing could observe and became the
mechanism behind a **NEW-RED on `test-fgl`**, on real FPC-corpus code:
`TFPGObjectList<TThing>` is rejected because `TThing` — a bare `class`, i.e. an
implicit `TObject` descendant — is declared in the **same type section** as the
specialization.

Tracked as [[regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section]],
which carries the repro and a 30-second discriminating test. **Do not fix by
loosening the check** — the 40 tests are the arm that would silently undo.

This is the second time today that a carrier nothing read turned out to be wrong
the instant a reader existed (the other: `UFldStrElemTk` hardwired to
`Ord(tyChar)` under a comment justifying it as safe *today*). Same shape: correct
when written, false the moment something consumed it.

## 2026-08-30 (frankwasm) — claimed, NOT written: it is not one line in `pasparser_decl.inc`

Routed to me as "one line in the same file" while I held `pasparser_decl.inc`.
Read before writing, and the framing does not survive it.

**The one line is the call. The call has nothing to drain.** There is a pending
**specialization** list (`PendingSpecTi`/`PendingSpecIdx`/`PendingSpecCount`,
`pasparser_generic.inc:2778-2781`, drained by
`FlushPendingClassSpecializations` at `:2808`) — but there is **no pending
*constraint* list**. `CheckTemplateConstraint` is still called inline at
`pasparser_generic.inc:2551`, which is the whole defect.

So the fix has three parts, not one:

| part | file | holder |
| --- | --- | --- |
| a pending-constraint list (`ti`, `k`, `argName`, `argKind`, `line`) | `defs.inc` | frankwasm |
| **record instead of check** at `pasparser_generic.inc:2551` | `pasparser_generic.inc` | **frank-rust** |
| unconditional drain at `TypeSectionDepth = 0` | `pasparser_decl.inc` | frankwasm |

**I did not write my two parts.** A drain with nothing to record into it is a
**guard that cannot fire** — the same shape this campaign has catalogued four
times today, and adding a fifth deliberately, in a file whose owner would then
inherit a half-built mechanism with no failing test to explain it, is worse than
leaving the ticket whole. The middle row is where the behaviour changes, and it
is the row I do not own.

**Sequencing when someone takes it:** the middle part is the ticket. Whoever
holds `pasparser_generic.inc` should write all three, or take the two
`frankwasm` rows by grant — they are mechanical once the list's shape is
decided, and the shape is decided by the recording site. Splitting them across
two agents costs more coordination than the change is worth.

Nothing in the original diagnosis is disputed; only the sizing. Parked rather
than half-done, and unclaimed so the ranker offers it again.


---

## 2026-08-31 (frankwasm) — half fixed, and the OTHER half's prescribed fix is wrong

Binary `df796c0b6edc` (self-host fixedpoint, `converged after 1 round(s)`).
Corpus: `fpc-testsuite/tests/test/tgenconstraint*.pp`, 40 files, each scored
against its own `{ %FAIL }` marker. This checkout does not carry that corpus;
it was read from a sibling checkout, unmodified.

### Measured, before and after, on two binaries

| | baseline `eda10567f26a` | with the fix `df796c0b6edc` |
| --- | --- | --- |
| agree with the `%FAIL` marker | **35 / 40** | **37 / 40** |
| accepted-invalid | 4, 5, 38, 39 | 38, 39 |
| rejected-valid | 37 | 37 |

`tgenconstraint37` is rejected-valid on BOTH binaries — pre-existing, and it is
[[bug-p-a-forward-interface-declaration-is-not-parsed]], not this ticket. **No
program went from accepted to rejected**, which is the only direction that could
break working code.

### What was fixed, and why it needed no deferral at all

The bail is right for a name the parse has not REACHED. It is wrong for a name
that is **settled**:

- a **builtin scalar** — `BuiltinTypeNameTk` answers from a fixed table, not the
  symbol table, so its answer cannot change later in the parse. If a user type
  shadows the name, `FindUClass` found it and we never reach here.
- **`TClass`** — `ParseTypeKind` (`pasparser_decl.inc:729`) lowers a bare
  `TClass` to a class REFERENCE (tyPointer with a tyClass element). A class
  reference is not a class instance type, which is what `T: class` asks for.

Both are knowable at `ParseSpecialization` time. The ticket's framing —
*"the fix is to check at end of type section"* — was true of the ROWS IT NAMED
only by coincidence: 4 and 5 are not blocked on the type section closing, they
were blocked on the check having no way to say *"this name is not a class and
never will be"*. Only the constraints that REQUIRE a class or interface are
enforced on that path; `record` is left alone, so the failure mode stays laxness.

### The correction, and it is the reason to read this note

**fpc 3.2.2 checks the constraint AT THE SPECIALIZATION POINT, not at the end of
the type section.** `tgenconstraint39` is the discriminating case, and it is
already in the corpus:

```pascal
  TSomeClass = class end;
  generic TGeneric<T: TSomeClass> = class end;
  TTest = class;                              { forward }
  TGenericTTest = specialize TGeneric<TTest>; { <-- FPC errors HERE }
  TTest = class(TSomeClass) end;              { ...and TTest DOES descend }
```

```
tgenconstraint39.pp(16,39) Error: Incompatible types: got "TTest" expected "TSomeClass"
```

By the time the section closes, `TTest` satisfies the constraint. FPC rejects it
anyway, because at the point of use the forward stub carries no parent. **A
drain at end of section would accept `tgenconstraint39` and diverge from the
oracle** — it would turn one accepted-invalid into another accepted-invalid
while looking like progress, and `tgenconstraint38` passing would make it look
like the whole thing worked.

So the remaining half is not "defer the check". It is closer to: **a
specialization argument that is a forward stub is an ERROR in its own right**,
which is a different rule with a different diagnostic. That is a design
question, not a placement one, and whoever takes it should confirm the rule
against more of the corpus before writing it — `T: class` against a forward
stub may well be legal where `T: TSomeClass` is not, since the former needs no
ancestor chain.

### Note on the hook this ticket was named after

`FlushPendingClassSpecializations`'s guarded call site in `pasparser_decl.inc`
is untouched. Nothing here needed it, and given the above it should not be
widened on this ticket's authority.

---

## 2026-08-31, LATER (frankwasm) — the deferral WAS needed, and I found that out by regressing

Binary `65be5936fe9a`. This corrects the note above it in the same file.

**The earlier note said the settled-name fix "needed no deferral at all". That
was wrong, and the way it was wrong is the point.** A builtin name is settled
against *the builtin table*. It is not settled against *the program*, because a
user may declare a type with that name — and `DelphiRewriteGenericUses` inserts
the specialization alias immediately after the TEMPLATE, so anything declared
below the template is invisible when the check runs. Measured:

```pascal
type
  TNeedsClass<T: class> = class end;
  LongInt = class end;              { the user takes a builtin's name }
  TOk = TNeedsClass<LongInt>;       { fpc 3.2.2: ACCEPTS }
```

Shipped behaviour at `19bb32f31`: **rejected**, "LongInt is a value type". A
false rejection — the one direction that ticket's own note claimed it had
avoided, and the claim was checked against a 40-file corpus in which the case
does not occur.

### How it was found, because the method transfers and the diff did not

Not by review and not by the corpus. A sibling change of mine the same night
(`ce4d9004c`, `BuiltinTypeNameTk`) regressed in the *same family* — a builtin
stealing a user's name — and frank-rust measured it. Applying that shape to this
change as a deliberate probe produced the failing case on the first try.

The rule it came from, which frank-coordinator banked from that incident:
**a control sampled from inside the OLD boundary cannot detect that you moved
the boundary.** The accept-side control here had four arms and every one of them
used ordinary user classes — drawn from the population the change was *about*,
when the change was to which NAMES the checker will answer for. The missing arm
was the only one that mattered.

### The fix

Defer: `RecordPendingConstraint` parks (template, parameter, argument, line)
whenever the argument does not resolve; `DrainPendingConstraints` re-asks at
`TypeSectionDepth = 0` with `final = True`, where FindUClass sees the whole
section. Name stored as a TokChars offset, not an AnsiString, matching
`PendingSpec*`'s BSS reasoning. Deferred errors report through
`ConstraintError`, which uses `ErrorAt` with the RECORDED line — the parser is
at the section's closing token by then, which can be hundreds of lines away, and
a diagnostic naming the wrong line is worse than one naming none.

The drain call is **unconditional**. Its neighbour `FlushPendingClassSpecializations`
is guarded by `PendingSpecCount > 0`, which is what this ticket originally
complained about; an empty list costs one comparison.

### It does NOT resurrect the design this ticket originally prescribed

The correction above still stands: fpc checks a FORWARD STUB at the
specialization point, so `tgenconstraint39` must be rejected there and a
general "defer everything" would accept it. That case never reaches the pending
list — a forward stub has `argCi >= 0` and takes the `UClsForward` exit before
it. **Measured: 37/40 both before and after this change, with the same three
disagreements (37 pre-existing, 38 and 39 the forward-stub pair).** The deferral
buys the shadowing fix and changes nothing else.

### Still open, unchanged

`tgenconstraint38`/`39`: a forward stub as a specialization argument. Still a
design question — is that an error in its own right? — not a placement one.

## DONE — the forward-stub half, and the proposed rule was wrong (frankwasm, 2026-08-31)

**37/40 -> 39/40.** `tgenconstraint38` and `39` now agree with their `%FAIL`
markers; `37` stays rejected-valid, pre-existing and untouched. Binary
`8cb1778e7539`, baseline `a36c42bc4487` re-measured in the same session with the
same script.

The section above proposed *"a specialization argument that is a forward stub is
an ERROR in its own right"* and flagged it as unconfirmed. **It is wrong, and
one afternoon of oracle rows says why.** Six constraints against one shape
(`TTest = class;` forward, the specialization, then `TTest = class(TSomeClass)`),
fpc 3.2.2:

| constraint | fpc | why |
| --- | --- | --- |
| (none) | ACCEPT | nothing to check |
| `class` | ACCEPT | a stub IS a class |
| `TObject` | ACCEPT | every class descends from TObject |
| `record` | REJECT | `Record type expected` |
| `TSomeClass` | REJECT | the stub carries no parent yet |
| `IInterface` | REJECT | the stub implements nothing yet |

So a stub is neither an error nor unknowable: it is **a class whose ancestry is
TObject and which implements nothing YET**, judged at the specialization point.
`T: class` against a forward stub is legal and common — the accept control in
`test_generic_constraint_accept_control.pas` has been guarding exactly that shape
since this ticket's first half, which is what would have made the proposed rule
fail loudly rather than quietly.

### The fix is a DELETION

`if UClsForward[argCi] then Exit;` — one line, gone. `isClass` is already True
for a stub, its parent chain is already empty and its interface list is already
empty, so every row of that table falls out of checks that were already written
and were simply never reached. Nothing was added.

That is also why the *"design question, not a placement one"* framing above was
right about the diagnosis and wrong about the cost: it reads as though the
remaining half needed a new rule with a new diagnostic. The measurement replaced
a design question with six oracle rows, and the code was already correct behind
a guard. **Cheaper to ask FPC six times than to reason once** — which is the
`root-cause-over-microfix` "vary the shape to find the boundary" step, and it is
what the first half of this ticket skipped on its way to shipping a false
rejection.

### Evidence

* `test/test_generic_constraint_forward_stub_fail.pas` (new, `test-core`) —
  tgenconstraint39, must be refused, message must name the constraint.
* `test/test_generic_constraint_accept_control.pas` — extended with
  `TNeedsTObject<TFwd>`, the arm the change actually moved, `accepted 4` ->
  `accepted 5`. The deeper-named and interface arms are what must fail; this is
  the one that must not.
* All six variants above measured pxx-vs-fpc side by side: identical, six for six.

### What 37 actually is, and the trap it sets for the next change

`tgenconstraint37` is the last disagreement and **it is not a constraint bug at
all.** It is `%NORUN` (must compile) and we reject it at line 18:

```
pascal26:18: error: expected 'end' before ';'
  near: = class ; ITestInterface = interface >>> ; TGenericTObjectTTestObject =
```

`ITestInterface = interface;` — a **forward INTERFACE declaration**, which we do
not parse. That is [[bug-p-a-forward-interface-declaration-is-not-parsed]] (p45),
already filed and in the ready queue. Nothing in this ticket can move 37, and
counting it against the constraint checker misreads it.

**The trap, for whoever takes that p45 ticket:** 37's third specialization is
`TGenericIInterface<ITestInterface>` — an interface FORWARD STUB against an
interface constraint — and fpc accepts it. This ticket's change makes the checker
judge stubs instead of skipping them, so the moment the parse gap closes, that
line reaches `GCIntfDescends(argCi, conCi)` with a stub that has no parent yet
and will very likely be **refused**. The class case has an explicit answer for
this (`T: TObject` means `isClass`, because every class descends from TObject);
the interface case needs the mirror — an interface stub descends from
`IInterface` — and nothing asserts it today because nothing can reach it.

So closing p45 should take this corpus to 40/40 **or** surface exactly that one
line. Either is fine; being surprised by it is not.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
