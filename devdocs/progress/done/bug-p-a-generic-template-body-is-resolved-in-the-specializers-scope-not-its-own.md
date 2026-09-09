---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankH
found-by: frankS
created: 2026-09-09
summary: "RESOLVED 2026-09-09 as a SCOPE rule in two halves, both of them rules this tree already had somewhere else, and nothing was narrowed -- all eight rows of test_a_class_helper_on_a_class_level_method now match fpc 3.2.2 and gen-TTest2 answers 3. MEASURED FIRST with PXXDBG=p.specunit, which named the half nobody had looked at: DoTest_TTest parsed at body-unit=-1, the PROGRAM, while the same unit's own methods carried body-unit=60 -- a specialization's METHOD bodies have parsed as their DECLARING unit since bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site and a generic ROUTINE's body never got that rule. Half one: GenericFuncUnitIdx (the channel TemplateUnitIdx already carries for a generic CLASS) plus NoteGFSpecBodyUnit at both splice sites, and ParseSubroutine switches CurrentUnitIdx exactly as the method arm beside it does; keyed by NAME because parsing one body can register another specialization, and `found` is returned separately from the unit because a generic routine declared by the main program records -1 legitimately. Half one alone changed NOTHING, which is the finding that produced half two: FindHelperForType had no visibility test of ANY kind, a flat scan in which any helper anywhere won. It now asks HelperRowVisibleHere -- ClassRowVisibleHere minus the carve-out that exempts rows minted by the SPECIALIZING scope, because those are synthesized CLASS rows and a class helper is never one, so the exemption had no subject here and was what let the program's helper reach inside an imported template body. gen-TTest=2 and gen-TTest2=3 are ONE RULE ON TWO INPUTS, as the ticket required; plain-TTest2 still answers 4 because in the program's own scope the program's helper is visible and must apply. Corpus row tgenfunc19.pp burned, verified printing Ok at rc=0 under both compilers. frankZ's token-splicing mechanism is recorded as a HYPOTHESIS, NOT MEASURED."
---

# The shape

`test/uclshelperdispatch.pas` declares `TTest`, a `class helper for TTest`, and
`generic function DoTest<T: TTest>: LongInt` whose body is `Result := T.CS`.
`test/test_a_class_helper_on_a_class_level_method.pas` declares `TTest2 =
class(TTest)` with **its own** `CS` (3) and a `class helper for TTest2` (4).

```
row               pxx   fpc 3.2.2
specialize DoTest<TTest2>    4     3      <- this ticket
TTest2.CS                    4     4      <- agrees, and is the control
```

Same class, same helper, same program, and the two rows differ **in fpc**. That
is the finding: the only thing separating them is that one call goes through a
template body imported from another unit. fpc binds the body's names where the
template was DECLARED; pxx binds them where it is SPECIALIZED.

## Why this could not be seen before 2026-09-09

pxx answered 3 and that matched. It matched because pxx applied no class-level
helper **anywhere** — there was no exclusion rule doing the work, just nothing
happening. `TTest2.CS` in the same program answered 3 as well, against fpc's 4,
which is what settles it.

`bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper` fixed
class-level helper dispatch (four member-lookup loops, two of which never asked
`ClassHelperRecFor`). The moment helpers were applied at all, this row flipped to
4 with nothing to stop it — which was **predicted before the fix landed** and
pinned at 3 in its own commit (`17a0e4bd6`) so the flip would read as a defect
revealed rather than caused. frankS called it; the pin is theirs.

## The constraint on any fix

**Do not narrow helper dispatch.** Seven rows in the same file depend on
class-level helpers being applied: `gen-TTest` (2), `inunit` (2), `plain-TTest`
(2), `plain-TTest2` (4), `classfn-nonstatic` (20), `instance` (400),
`stmt-touch` (2). A fix that makes `gen-TTest2` answer 3 by applying fewer
helpers takes `gen-TTest` down with it — `gen-TTest` is the *same template* and
must answer the TEMPLATE unit's helper.

So the fix is a SCOPE rule, not a dispatch rule: while resolving a specialized
body, helper lookup must see the helpers visible at the template's declaration
site, not those visible at the specialization site. `gen-TTest` = 2 and
`gen-TTest2` = 3 are the same rule read on two inputs.

## Corpus

`library_candidates/fpc-testsuite/tests/test/tgenfunc19.pp` asserts exactly these
two rows (`Halt(1)` on the first, `Halt(2)` on the second) and is currently
blocked on this one row alone.

## Resolved 2026-09-09 — a scope rule, in two halves, both already in this tree

`gen-TTest2` answers **3**. All eight rows in
`test/test_a_class_helper_on_a_class_level_method.pas` now match fpc 3.2.2, and
the constraint held: nothing was narrowed.

### Measured first, and it named the half nobody had looked at

`PXXDBG=p.specunit` on the fixture:

```
DoTest_TTest   body-unit=-1  spec-host=-2   <- the PROGRAM
DoTest_TTest2  body-unit=-1  spec-host=-2
TTest.CS       body-unit=60  spec-host=-2   <- the unit, correctly
```

A specialization's METHOD bodies have parsed as their DECLARING unit since
[[bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site]].
**A generic ROUTINE's body never got that rule** — it parsed as whoever
specialized it. Same concept, one arm missing, which is the double case
`normalise-dont-special-case` is about.

### Half one — the body parses as its declaring unit

`GenericFuncUnitIdx` records where a generic routine was declared (the channel
`TemplateUnitIdx` already carries for a generic CLASS), `NoteGFSpecBodyUnit`
records it against the spliced routine's name at both splice sites, and
`ParseSubroutine` switches `CurrentUnitIdx` for the body exactly as the method
arm beside it does.

Keyed by NAME rather than held in a global because parsing one concrete body can
register another specialization — a generic routine that calls a second one — so
splice and parse do not nest predictably. `FlushPendingFuncSpecializations`
loops on a count its own body can grow for the same reason.

The lookup returns `found` separately from the unit, because a generic routine
declared by the MAIN PROGRAM records -1 legitimately and that is the common
case: a bare `>= 0` test reads "no row" and "the program declared it" as one
answer.

### Half two — helper lookup is visibility-aware at all

This half is the answer to "why did half one change nothing on its own", which
it did: with the body parsing as unit 60, all eight rows were still unchanged.

**`FindHelperForType` had no visibility test of any kind** — a flat downward
scan of every helper ever registered, so any helper anywhere won. Invisible
until two scopes declare helpers for related classes, which is exactly this
fixture.

It now asks `HelperRowVisibleHere`. That is `ClassRowVisibleHere`'s rule minus
one carve-out, and the carve-out is the whole reason it is a separate function:
`ClassRowVisibleHere` exempts rows whose unit is the SPECIALIZING scope, so that
rows the specialization itself minted still resolve inside a body parsed as
another unit (`TFPGListEnumeratorSpec` in `fgl.pp`). Those are SYNTHESIZED CLASS
rows. **A `class helper` is never one** — nothing a specializer mints is a
helper — so the exemption has no subject in helper lookup, and applying it
anyway is precisely what let the program's `TTest2Helper` reach inside a
template body imported from another unit.

### The constraint held

`gen-TTest` = 2 and `gen-TTest2` = 3 are ONE RULE ON TWO INPUTS, which is what
the ticket asked for: the template unit's own helper still reaches the body, the
specializing program's does not. Narrowing dispatch would have fixed the second
and broken the first. The seven rows that stand on helpers being applied —
`inunit`, `plain-TTest`, `plain-TTest2`, `classfn-nonstatic`, `instance`,
`stmt-touch`, `gen-TTest` — are unchanged, and `plain-TTest2` still answers 4,
because in the PROGRAM's own scope the program's helper is visible and must
apply.

### The mechanism frankZ asked be recorded as a hypothesis

**NOT MEASURED, carried as their words:** specialization is token splicing under
the alias's name, with the substituted body re-parsed at the specialization
site. It is consistent with everything above and with `p.specsplice`'s output on
the sibling ticket, and nothing here establishes it — the two halves that fixed
this row were verified by their own before/after, not by that model.

### Corpus row burned

`tgenfunc19.pp` is out of `test/pascal-conformance/pxx.skip`. Verified rather
than trusted: it prints `Ok` and exits 0 under pxx, and identically under fpc
3.2.2. Its two assertions are this ticket's two rows —
`specialize DoTest<TTest> <> 2 -> Halt(1)` and `<TTest2> <> 3 -> Halt(2)`.

Gate GREEN, FPC seed canary PASS.

Log: fixed in `compiler/symtab.inc` + `compiler/pasparser_proc.inc` +
`compiler/pasparser_generic.inc` + `compiler/defs.inc`, commit f0aca9c59. That commit
also burns `tgenfunc19.pp` from `test/pascal-conformance/pxx.skip` and re-aims
the fixture; the close is this file's move to `done/` in the same commit.

### The half worth carrying out of this ticket

`FindHelperForType` having **no visibility test of any kind** is the finding to
flag, and not for this row's sake. frankZ's framing, which is better than the
one above: it is the same shape as the four-member-lookup-loops-documented-as-two
note one layer down — *a question with no scope filter at all, sampling correct
because nothing had yet asked it from two places*. It sat directly under the
class-helper dispatch work of the same morning.

`ClassHelperRecFor`'s comment now says so, because a reader who finds the
four-loop note will otherwise take the scope question for settled: that
paragraph is about WHICH LOOPS ASK, never about WHOSE HELPERS ANSWER.
