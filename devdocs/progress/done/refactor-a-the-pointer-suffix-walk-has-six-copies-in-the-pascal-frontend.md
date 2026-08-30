---
slug: refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend
title: "The `^`/`.`/`[]` suffix walk has six copies in the Pascal frontend, and none can be deleted alone"
track: A
prio: 55
type: refactor
blocked-by: []
status: done
owner: frankA
created: 2026-08-30
found-by: frankA (splitting item 4 out of feature-a-typeref-migrate-consumers)
summary: "The pointer/field/index suffix walk is duplicated SIX times in the Pascal frontend (not four, as the parent ticket says -- listed, not counted). Each copy stamps a different subset of the node tags the rest of the compiler reads, which is why four separate tickets have now ended 'the metadata was there, the reader was missing'. None can be deleted without the others agreeing on the tags, so this is one refactor, not six fixes."
---

# The suffix walk has six copies, and the reader is always the broken half

Split out of [[feature-a-typeref-migrate-consumers]], whose "still open" list
asks for exactly this and says to *"file it before starting, with the four sites
named"*. **There are six, not four** — the parent's count was never listed out.

## The sites, measured 2026-08-30 (listed, not counted)

| # | site | shape |
| --- | --- | --- |
| 1 | `pasparser_lval.inc:4770` | inside `ApplyCallResultPtrSuffix` (from :4722) — the call-RESULT suffix |
| 2 | `pasparser_expr.inc:930` | the `^`-or-`.` walk in the factor path |
| 3 | `pasparser_expr.inc:6391` | `[tkCaret, tkDot, tkLBrack]` |
| 4 | `pasparser_expr.inc:6740` | `[tkCaret, tkDot, tkLBrack]` |
| 5 | `pasparser_stmt.inc:6444` | `[tkCaret, tkDot, tkLBrack]` |
| 6 | `pasparser_stmt.inc:6559` | `[tkCaret, tkDot]` — note the SHORTER set, no index arm. **Fixed 2026-08-30, see below**: this was the one copy that actually diverged from FPC, and it diverged twice |

**Not in scope, deliberately:** `pyparser.inc:42567 / 47378 / 47524` are NilPy's
own three copies. Duplication *across* languages is the rule
(`the-substrate-is-ast-and-ir-not-the-parser.md`: share the AST and IR, duplicate
the parser), so those are correct as duplicates and must not be folded into the
Pascal ones. They are worth reading while doing this, because they are a second
opinion on what the walk must stamp — but they stay separate.

Site 6 having a shorter token set than the other five is the smell in miniature:
six copies of one concept, one of which quietly does not handle indexing.

## Why this is the valuable half

Four tickets in a row have ended with the same sentence — *the metadata was
there, the reader was missing*:

- `bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape`:
  populating proc-return depth fixed **nothing** on its own. `c := GetQ^;
  WriteLn(c)` printed the string while `WriteLn(GetQ^)` printed the address —
  same binary, same declaration — because `ApplyCallResultPtrSuffix` stamped
  none of the node tags the rest of the compiler reads.
- The parent ticket's own conclusion: *"when a pointer shape is wrong, look at
  the reader before the table."*

So the table-folding work (`TTypeRef`) makes the *data* consistent, and this
makes the *consumers* consistent. The parent ticket judges this "a bigger,
better-value refactor than the table fold".

## The constraint that makes it one job

**None of the six can be deleted without the other five agreeing on the node
tags they stamp.** That is the whole difficulty and it is why this is filed as
one refactor rather than six small fixes: a partial merge leaves a caller whose
tags differ from its neighbours', which is the current state and the thing being
fixed.

## Suggested approach (not a prescription)

1. **Inventory what each copy stamps** — the node tags, not the parse. A table
   of six rows against the tag set is the deliverable that makes the rest
   mechanical, and it is most of the work.
2. Land the union as one helper, converting copies **one at a time**, each under
   the parent ticket's A/B binary-comparison standard (compiler built before and
   after, same sources, diffed) rather than "the tests pass". That standard is
   what caught the 2026-08-01 revert's absence, and it is the right one here
   because a tag that no current test reads is exactly what is being unified.
3. Expect the union to be strictly larger than any one copy. A copy that stamps
   fewer tags is not "simpler"; it is the one with the latent bug.

## Gate

Per converted copy: `make compiler/pascal26` + A/B binary identity across the
Pascal, C, BASIC and NilPy sources the parent ticket lists, plus the 72-pair
`GetQ^` cross product (10 shapes x 8 contexts) staying at 72/72 against
fpc 3.2.2. `tools/gate.sh quick` before any pin.

**Do not** take this concurrently with `feature-a-typeref-migrate-consumers`'s
step 2 — that one needs `ir.inc` and re-points `PtrBaseTk`, and these six
readers are downstream of exactly that field's meaning.

---

# Step 1 done: the inventory, measured 2026-08-30

## What each copy stamps (the deliverable step 1 asked for)

The tag set that matters is the four fields a downstream reader consults on an
`AN_DEREF`: `ASTTk` (the value's kind), `ASTSOffset` (**levels remaining**),
`ASTSLen` (**ultimate base kind**), `ASTIVal` (**a record id** — see the trap
below). The readers are `ResolveDerefShape`'s own `AN_DEREF` arm,
`ResolveNodeRec`'s `AN_DEREF` arm, `IsNodePChar` arm 7, and `IRPointerStride`.

| # | site | reached by | `^` arm | `[` arm | `.` arm | stamps on its `AN_DEREF` |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `pasparser_lval.inc:4770` | a call RESULT, `f()^` | own walk, reads `ProcRetPtr*` | yes (`AN_INDEX`, `ASTTk` only) | hand-rolled `AN_FIELD` | Tk + SOffset + SLen + IVal (**ultimate base**) |
| 2 | `pasparser_expr.inc:930` | a GROUPED value, `(x)^` | calls `ResolveDerefShape` | yes, + string-value temp; class → `ParseClassRecordSelectors` | class → selectors; else hand-rolled + interface dispatch | Tk + SOffset + SLen + IVal (**ultimate base**) |
| 3 | `pasparser_expr.inc:6391` | `TRec(x)` record-name cast, RVALUE | own walk, hard `tyRecord` | yes (`AN_INDEX`, hard `tyRecord`) | `ParseClassRecordSelectors` (every name, since 2026-08-27) | Tk + IVal (**immediate pointee**) — no SOffset/SLen |
| 4 | `pasparser_expr.inc:6740` | `PRec(x)` alias cast, RVALUE | calls `ResolveDerefShape` | yes (`AN_INDEX`, alias elem) | not-a-field → selectors; metaclass tail; else hand-rolled | Tk + SOffset + SLen + IVal (**ultimate base**) |
| 5 | `pasparser_stmt.inc:6444` | `TRec(x) := ` record-name cast, LVALUE | own walk, hard `tyRecord` | via `ParseClassRecordSelectors` | `ParseClassRecordSelectors` | Tk + IVal (**immediate pointee**) — no SOffset/SLen |
| 6 | `pasparser_stmt.inc:6559` | `PRec(x) := ` alias cast, LVALUE | own walk, alias's immediate pointee | **ABSENT** | hand-rolled `AN_FIELD` only | **Tk only** |

Site 6 is the laggard on every column: the shortest token set, the poorest
stamps, and the only one with no handoff to the shared selector walker.

## The measured differential — and it is NOT six-way drift

Ten cells, each the same shape driven through a different entry point, every one
diffed against `fpc 3.2.2 -Mobjfpc -O2`. Two axes: a subscript after the field,
and a depth-2 deref.

```
CELL      SHAPE                        FPC          PXX (pre-fix)  VERDICT
c1_idx    WriteLn(GetP^.a[0])          7            7              ok
c2_idx    WriteLn((p)^.a[0])           7            7              ok
c3_idx    WriteLn(TRec(r).a[0])        7            7              ok
c4_idx    WriteLn(PRec(raw)^.a[0])     7            7              ok
c5_idx    TRec(r).a[0] := 42           42           42             ok
c6_idx    PRec(raw)^.a[0] := 42        42           COMPILE-ERR    DIVERGES
c1_dep    WriteLn(GetPP^^.b)           12345        12345          ok
c2_dep    WriteLn((pp)^^.b)            12345        12345          ok
c4_dep    WriteLn(PPRec(raw2)^^.b)     12345        12345          ok
c6_dep    PPRec(raw2)^^.b := 99        99           12345          DIVERGES
```

**Both divergences are site 6, one on each axis.** That is a sharper — and
smaller — statement than this ticket's own premise. The premise was "six copies,
therefore six chances to drift"; the measurement says five of the six agree with
FPC *on the two axes probed*, and the sixth is behind on both. (Stated
precisely: two shapes × six entries is a thin basis for calling sites 1–5
correct in general. It is a solid basis for locating where the value was.)

A note on method: the depth cells first used the target's initial value `22` as
the expected answer, so pxx and FPC "agreed" at `22` in a program where `22` was
simply what was already there — a vacuous agreement. Re-run with a distinctive
`12345`, the agreements held and c6_dep's disagreement became legible.

## The two defects, and why nobody had reported them

- **`PRec(raw)^.a[0] := 42`** → `Expected: :=, but got: [`. This is the **exact
  twin** of `bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed`,
  already fixed at site 5 — on the *record-name* cast. The *alias-name* sibling
  was never grepped for when that ticket closed. Reachable, loud, and the
  identical chain as an rvalue parsed fine.
- **`PPRec(raw2)^^.b := 99`** → compiles clean, stores at the **wrong address**,
  target keeps its old value, no diagnostic. The alias row has carried the whole
  triple (`AliasPtrDepth`/`BaseTk`/`BaseRec`) all along and `ResolveDerefShape`
  has had an `AN_PTR_CAST` arm that reads it — this walk simply never asked.
  *The metadata was there, the reader was missing.* Fifth ticket in a row.

Why they survived, measured rather than guessed: the shape site 6 handles is
**load-bearing** — 80+ alias-cast-lvalue sites in `lib/rtl` (`coroutine.pas` 14,
`scheduler.pas` 23, `typinfo.pas` 11, `rtti.pas`, `strings.pas`,
`configparser.pas`, both platform backends). Every one of them is **depth-1 with
a plain field**, which was correct all along. In-repo uses of the two broken
shapes: **zero**. One of those zeros is self-fulfilling — a parse error cannot
appear in code that compiles, so its absence says nothing about demand. The
other is luck: `^^` through an alias cast as a target would have silently
corrupted memory in the RTL.

## The trap the union helper must not walk into

`ASTIVal` on an `AN_DEREF` **means two different things** depending on which
copy wrote it:

- sites 1/2/4 write the **ultimate base** record (bottom of the pointer chain);
- sites 3/5/6 write the **immediate pointee** record.

`ResolveNodeRec`'s `AN_DEREF` arm reads `ASTIVal > 0` **ungated** and treats it
as "the record this deref yields" — i.e. the *immediate pointee* meaning.
`ResolveDerefShape` reads it as the *ultimate base*, but only under
`ASTSOffset > 0`, and sites 3/5/6 leave `ASTSOffset` at 0 — so the gate happens
to shield the collision today. The two meanings coincide whenever remaining
depth is 0 or 1, which is every shape currently in the repo.

**This is a live constraint on step 2**, not a curiosity: a union helper that
unconditionally stamps the ultimate base into `ASTIVal` would change what
`ResolveNodeRec` answers on the cast paths. Whichever meaning the union picks,
`ResolveNodeRec`'s arm must be moved to match it in the same commit.

## Revised plan

Step 1 is done (above). The remainder splits by value, which the inventory made
visible and the original plan could not:

1. ~~Inventory~~ — done.
2. **Site 6 brought up to its twins** — done, this commit. Not a new helper:
   site 6 now uses the token set + selector handoff its *lvalue* twin (site 5)
   already had, and the `ResolveDerefShape` call + three stamps its *rvalue*
   twin (site 4) already had. Both remedies already existed in the file; site 6
   was simply never updated when its two siblings were fixed. Net **−433 bytes**
   of compiler code (a hand-rolled field builder deleted, not added to).
3. **Unifying sites 1–5 into one helper is still worth doing, but it is now
   explicitly hygiene**: zero measured behavioural payoff, five conversions of
   real regression risk, and the `ASTIVal` trap above to resolve first. Its
   value is preventing *the next* site 6 — which is a real value, since site 6's
   two defects are precisely what six-way duplication produces. It should be
   judged and scheduled on that basis, not on bug count. Keep the A/B
   binary-identity standard when it is taken.
   **Re-filed as [[refactor-a-unify-the-five-remaining-pascal-postfix-suffix-walks]]
   at prio 35** — deliberately not inheriting this ticket's 55, because the
   inventory this ticket performed is what demoted it from bug-fixing to
   hygiene. That successor carries the `ASTIVal` design question above as a
   blocking item, since it must be settled before a union helper is written.

**On closing this ticket rather than parking it:** the headline goal in the
title — deleting five of the six copies — is NOT done, and this resolution does
not claim it. What is done is this ticket's own step 1, which it called *"most
of the work"*, plus the two defects that step exposed. Re-scoping on the
measurement is the reason to do an inventory first; the alternative was to spend
five risky conversions before learning that only one site was wrong. A Track A
ticket must not sit in `unfinished/` (it fails `progress.sh check`), so the
remainder is a successor ticket rather than a parked one.

## Evidence for this commit

- `make compiler/pascal26` → `converged after 1 round(s)`, self-host fixedpoint
  verified, binary `7ee9ac95843d` (baseline `3b00f387f0df`).
- **A/B binary identity**: the compiler built before and after the change, both
  used to compile every program under `examples/` — **33 identical, 0 different**,
  12 failing to build identically under both. Not a vacuous zero: those 33 each
  link `lib/rtl`, which contains 80+ instances of exactly the construct this
  walk parses.
- 14-probe before/after/FPC differential: **2 FIXED, 12 unchanged**, including
  four regression probes aimed at what the change disturbed (the PChar adapter
  fallback, a plain field store, a bare deref store, a nested field store).
- Regression test `test/test_cast_lvalue_suffix_siblings.pas`, wired into the
  Makefile beside its rvalue ancestor `test_cast_deref_chain_siblings`. Six rows,
  all diffed against FPC. Confirmed to **fail on the baseline** — it does not
  compile there.
- One pre-existing, unrelated divergence found and left alone: `PChar(s)^ := 'J'`
  on a literal-assigned string prints `Jello` under pxx and dies with FPC
  runtime error 216 (a write to a read-only literal). **Identical before and
  after**, so not this change; and per CLAUDE.md's compat table, accepting a form
  FPC rejects is not a defect. The regression test uses `UniqueString` to keep
  the row on the shared behaviour.

## Log
- 2026-08-30 — resolved, commit 1d01554e3.
