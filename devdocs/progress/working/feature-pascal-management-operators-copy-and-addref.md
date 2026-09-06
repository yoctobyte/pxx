---
slug: feature-pascal-management-operators-copy-and-addref
title: "`class operator Copy` / `AddRef` are recognised but never dispatched"
track: P
prio: 30
type: feature
status: working
owner: frankA
blocked-by: []
summary: "BOTH HALVES DONE 2026-09-06 (frankA), ABOVE 8 BYTES. `class operator Copy(constref src; var dst)` dispatches at the record-assignment lowering; `class operator AddRef` dispatches at the BY-VALUE PARAMETER copy. Both match fpc 3.2.2 byte for byte (test_mgmt_operators_copy at three assignment sites; test_mgmt_operators_addref across by-value/const/var; test_mgmt_operators_addref_nonlvalue_arg across the argument SHAPE) and all are refused outright on the pin. THE BY-VALUE PARAMETER HAD NO LIFECYCLE AT ALL, not merely a missing AddRef -- the copy is an skParam and the parser-side wrapper walks skLocal/skGlobal only, so the callee-side Finalize was missing too and AddRef could not land alone; both are now emitted at the caller's private temp, Finalize FIRST (pre-order) on the post-call queue. THE HOOK IS KEYED ON WHETHER `var`/`out`/`const` WAS WRITTEN, NEVER ON WHETHER A TEMP WAS BUILT: a temp is built for four different reasons and only three are by-value. Measured both directions -- a const parameter given a NON-LVALUE takes a temp and fpc runs no operator (the first cut fired there: callee read 107 against fpc's 7), while a by-value parameter given a non-lvalue takes the SAME arm and fpc DOES run AddRef. REFUSED AT OR UNDER 8 BYTES, by name and by size: the backend pushes the record as machine words so the copy has no address: forcing a temp there was MEASURED to break the ABI (callee read 4311096 for 107) and was reverted for an explicit refusal. RESIDUAL, NOT MINE: a genuine `var` record parameter on an INTERFACE or `virtual; abstract` method has no trustworthy discriminator here, because ProcParamExplicitByRef is never written by the parameter parsers in pasparser_decl.inc (frankB, 2026-09-06); the `const` half is excluded independently via ProcParamIsConst, which IS written at those sites, and the guard tightens for free when that column is fixed. CORPUS: tmoperator8 RE-MEASURED at fe2ef24ce, not assumed -- it moved from line 63 (the AddRef refusal) to line 143, where it now stops on the DYNAMIC/MULTI-DIMENSIONAL ARRAY refusal, so the row is advanced but still not cleared and its remaining blocker is feature-pascal-management-operators-nested-and-array. NOT ESTABLISHED: whether the two assignment arms hooked are the whole population (78 IR_COPY_REC mentions), and whether a record with a genuinely managed FIELD alongside the operators routes its copy through a different helper."
---

# `class operator Copy` / `AddRef` are recognised but never dispatched

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** working
- **Follows:** [[feature-pascal-class-management-operators]] — slice 3 landed
  Initialize/Finalize and refuses these two by name.

## Symptom

    error: operator Copy/AddRef is recognised but not dispatched yet — the copy
           lifetime event is a separate slice

The spelling parses, the arity is checked, the overload registers — and then
nothing invokes it, because pxx has no **copy** lifetime event. Accepting one
silently would give a record whose invariant never runs.

## What FPC does — MEASURED 2026-09-06, and it is not what this section said

The two paragraphs that used to sit here said `Copy` *"replaces the copy
entirely; when present, `AddRef` is not called for that assignment"* and that
both *"fire wherever a record value is duplicated"*. **Both claims are false
against fpc 3.2.2.** They describe a precedence between two operators that
compete for one event; what fpc actually has is two operators on **disjoint
sites**, and no site where the choice between them arises.

Measured with three programs differing only in which operators are declared —
AddRef alone, both, Copy alone — each operator printing its own name so a value
check cannot confuse them:

| duplication site | AddRef alone | both declared | Copy alone |
| --- | --- | --- | --- |
| `b := a` (local := local) | *nothing* | **Copy** | **Copy** |
| by-value parameter | **AddRef** | **AddRef** | *nothing* |
| `b := Mk` (return into a var) | *nothing* | **Copy** | **Copy** |
| `arr[0] := a` (into a container) | *nothing* | **Copy** | **Copy** |
| `const` parameter | *nothing* | *nothing* | *nothing* |
| `var` parameter | *nothing* | *nothing* | *nothing* |

Read the middle column against the two outer ones: with BOTH declared, the
assignment sites still run Copy and the by-value site still runs AddRef. Neither
operator ever displaces the other, because neither is ever offered the other's
site. So:

- **`Copy(constref src; var dst)` is the ASSIGNMENT event** — every store of a
  record value into an existing destination.
- **`AddRef(var a)` is the BY-VALUE PARAMETER event, and only that** — the copy
  the caller makes into the callee's parameter slot.

The Copy-only column is the one that settles it: the by-value parameter runs
**no operator at all**, while its slot is still Finalized at exit. So a declared
`Copy` is silently not honoured for a parameter copy — arguably fpc's own gap,
and recorded here as measurement rather than as a target.

**Axis swept:** `-O1`, `-O2`, `-O3`, identical at all three (`-O0` is not an fpc
spelling). Not swept: a record with a genuinely managed FIELD (ansistring,
interface) alongside the operators, which could route the copy through a
different helper — check that before relying on the table for such a record.

**What this changes for the slice.** The scope is much narrower than "wherever a
record value is duplicated": `Copy` hooks the RECORD-ASSIGNMENT lowering, which
already has a branch to hang it on — `ir.inc` tests `RecordHasManagedFields` and
picks `IR_COPY_REC_MANAGED` over `IR_COPY_REC` at the general `AN_ASSIGN` arm
and again at the inline-var-decl arm. A Copy operator is a third arm in the same
choice, emitting a call instead of a bulk copy. `AddRef` is a separate and much
smaller hook at the by-value record argument copy. **The two halves do not share
a site and could land independently**, which the old framing hid by treating
them as one event with a precedence rule.

Not yet established: whether those two `IR_COPY_REC_MANAGED` arms are the whole
assignment population. There are 78 `IR_COPY_REC` mentions across `compiler/`;
a census keyed on which of them can receive a USER record assignment is the
first task of the implementing slice, and a call-site census is open-world — see
the field-vs-call-site distinction before trusting a count of them.

## Why it is a separate slice

Initialize/Finalize are *scope* events and desugar into `Initialize(v); try
BODY finally Finalize(v); end` around the routine body — one AST rewrite, no
backend work (see the parent ticket). A copy event has no such single site: it
has to be hooked wherever a record assignment is lowered, which is the
`AN_ASSIGN` record path plus the by-value argument and return paths — i.e. the
IR side, not the parser side. That likely makes the dispatch half a **Track A**
ticket once the shape is settled.

## Repro

The Copy refusal fixture under `test/` (currently pinned as an ERROR — it
becomes an output test when this lands).

## Gate

`make compiler/pascal26` (self-host fixedpoint) + a trace program diffed
against FPC 3.2.2 + `tools/gate.sh quick`.

## 2026-09-06 (frankS) — the corpus row that asks for this

`tmoperator8.pp` in the fpc testsuite stops at line 63 on this ticket's own
refusal string, and it is the only one of the six live `tmoperator` rows that
does. Measured at `88a0b3d93835`; the other five split two-and-three onto
[[feature-pascal-management-operators-nested-and-array]] and
[[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]].

**Skip row, verbatim, so the evidence and the ticket cannot drift apart:**

    tmoperator8.pp	gap: management operators AddRef/Copy/Initialize/Finalize on records

That reason is only two-thirds true and is corrected in the same commit:
Initialize and Finalize work. The row is blocked on Copy/AddRef alone.

## 2026-09-06 (frankA) — Copy lands; AddRef is the remainder

`class operator Copy` dispatches. The hook is `IRRecCopyOpCall` in `ir.inc`,
consulted at both record-assignment arms — the general `AN_ASSIGN` one and the
inline-var-decl one — ahead of the existing `RecordHasManagedFields` choice
between `IR_COPY_REC_MANAGED` and `IR_COPY_REC`. It returns the call node or
-1, so the two call sites read one predicate rather than each re-deciding.

### Three measurements the implementation depended on, none of them guessed

**Copy REPLACES the copy.** Not a notification emitted alongside the bytes. The
probe operator assigns neither field; after `b := a`, `b.n` was still b's own
value under fpc, and is under pxx. So the hook returns the call INSTEAD of the
bulk copy. The fixture keeps that operator for exactly this reason: one that
dutifully copies the fields cannot distinguish "ran instead of the copy" from
"ran as well as the copy", because both print the same thing.

**The destination is NOT finalized first.** `dst` arrives holding its previous
value — the operator prints it. There is no release-then-copy here the way
`IR_COPY_REC_MANAGED` does for ARC fields; the operator owns whatever that
means for the record.

**Both parameters cross by reference, including for a small record.** `var` is
by-ref, and a `const` record parameter is forced by-ref too (by value it would
truncate to one qword). So passing two addresses is correct for a 4-byte record
as well as a large one — which mattered, because the size-based by-ref rule
alone would not have covered it.

The rule is in `pasparser_proc.inc`, found by grepping for
``const` record param is passed by reference`` — deep inside `ParseSubroutine`.
**This paragraph cited `ParseParamList` when it landed in `10d7a345a`, and no
such routine has ever existed in this tree.** I invented a plausible name for a
rule I had actually read, an hour after relaying a peer's correction of exactly
that failure (`ArgListHasBracketElem`, also cited in two comments and defined
nowhere). `tools/ghost_names.py` cannot catch this one: it reports names that
were once defined and are now gone, and a name that never existed leaves no
trace for it to find. The only instrument that works is grepping your own
citations for a definition — which is what turned it up here.

### Why AddRef did not land with it

They are disjoint sites (the corrected section above). AddRef fires on the
BY-VALUE PARAMETER copy and only that, which is a different hook in a different
pass — `IRLowerCallArg`'s private temp, not the assignment lowering. Nothing in
the Copy work brings it closer, and nothing in it blocks AddRef either.

### What is NOT established

- **Whether the two arms hooked are the whole assignment population.** There are
  78 `IR_COPY_REC` mentions in `compiler/`. A call-site census is open-world, so
  the honest statement is that three source-level sites were measured against
  fpc and matched, not that every path was found. A `with`-scoped destination, a
  `Copy` on a record reached through a pointer deref, and an assignment
  synthesised by another desugar are the shapes to try next.
- **A record with a genuinely managed FIELD (ansistring, interface) alongside a
  Copy operator.** fpc might route that copy through a different helper, and the
  measurement table above did not include one. Ours currently gives Copy
  priority over `IR_COPY_REC_MANAGED`, which means the operator becomes
  responsible for the ARC fields — plausible, and unmeasured.

### The corpus row still does not clear

`tmoperator8` stops at line 63 as before, now on the AddRef refusal instead of
the Copy one. It declares all four operators. Advancing the refusal by one
operator is not clearing the row and is not recorded as such.

## AddRef — landed 2026-09-06 (frankA)

### What the measurement changed

The by-value parameter had **no lifecycle at all**, which is not what this
ticket predicted. The copy is an `skParam`, and `WrapManagementOpsRange`
(`pasparser_proc.inc` ~631) tests `isTarget` = `skLocal`/`skGlobal`, so the
callee-side **Finalize was missing too**. AddRef could not be added to a working
mechanism because there was no mechanism; both operators are now emitted at the
caller's private temp in `IRLowerCallArg`, and `IRFlushPostCallIntf` runs the
operator's Finalize **before** the ARC release (pre-order), with the release
itself now conditional on the record actually having managed fields.

### The guard, and why it is not "a temp was built"

`needTemp` is reached for four reasons and only three are by-value. The one that
is not: a genuine `const`/`var` parameter handed a **non-lvalue** gets a temp
purely so the by-ref slot has something to point at.

Keying the emission on `needTemp` was wrong, and the fixture could not see it —
every row passed an lvalue, so the const and var rows never built a temp and
never reached the arm. **A control that cannot reach the arm is not a control.**
The fixture varied the parameter MODE and held the argument SHAPE fixed.

Measured, both directions, on the same day:

| parameter | argument | fpc 3.2.2 | first cut | now |
| --- | --- | --- | --- | --- |
| `const` | lvalue | no operator | no operator | no operator |
| `const` | `Make` (rvalue) | **no operator** | **AddRef, callee 107** | no operator |
| by-value | lvalue | AddRef, callee 107 | AddRef, callee 107 | AddRef, callee 107 |
| by-value | `Make` (rvalue) | **AddRef, callee 107** | *(none)* | AddRef, callee 107 |

Rows 2 and 4 take the **same arm** and need **opposite answers**, so the arm
cannot be the discriminator. The question is only ever *was `var`/`out`/`const`
written*, which is `ProcParamExplicitByRef`. A first attempt at the fix read the
arm and so repaired row 2 by breaking row 4 — caught only because row 4 was
measured against fpc rather than assumed.

`test_mgmt_operators_addref_nonlvalue_arg` exists to hold that axis.

### Blocked-adjacent: a column that is False for two different reasons

`ProcParamExplicitByRef` is never written by the parameter parsers in
`pasparser_decl.inc` (frankB, 2026-09-06), so on an **interface** or
`virtual; abstract` method it reads False for a genuine `var`/`const` exactly as
it does for a silently-promoted by-value param — and this guard would then run an
operator where fpc runs none.

The `const` half is excluded independently: `ProcParamIsConst` **is** written at
those two sites (`pasparser_decl.inc:6996`, `:7787`), from the same `mPConst[]`
array on the adjacent line. Asking both columns is not redundancy — they go
blank on different populations. The `var` half has no local signal and waits on
frankB's fix; the guard tightens for free when that column is written, with no
change here.

### The 8-byte floor is a refusal, not a gap

At or under 8 bytes the backend pushes the record's own bytes as machine words,
so the copy has no address for an operator to act on. Forcing `needTemp` there
was **measured**, not reasoned: the callee then receives the temp's address where
its ABI says bytes and read `id=4311096` against fpc's 107, while AddRef and
Finalize themselves ran correctly. A silently wrong field in the callee is worse
than a refusal, so that was reverted and the refusal names the size and the
ticket. `test_mgmt_operators_addref_small_refused` greps the **size wording**,
not the slug — the pin's old blanket refusal cites the same slug, so a slug-only
grep would score a revert as a pass.

### Left open

- **`tmoperator8`, re-measured at `fe2ef24ce`** rather than assumed: it moved
  from line 63 (the AddRef refusal) to **line 143**, where it stops on the
  dynamic/multi-dimensional array refusal. The row is advanced, not cleared, and
  its remaining blocker is
  [[feature-pascal-management-operators-nested-and-array]] — which is the next
  slice of this same group, so the corpus row is a live indicator for it.
- A managed record **function result** runs neither Initialize nor Finalize —
  filed as
  [[bug-a-a-managed-record-function-result-runs-neither-initialize-nor-finalize]],
  pre-existing (the pin shares it), and the reason
  `test_mgmt_operators_addref_nonlvalue_arg.expected` is deliberately not fpc's
  output byte for byte.
- Whether the two hooked assignment arms are the whole population (78
  `IR_COPY_REC` mentions).
