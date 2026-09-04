---
slug: refactor-p-one-prerequisite-emitter-not-four-doors-into-nspecins
track: P
prio: 55
type: refactor
status: done
blocked-by: []
summary: "DONE (101bf561f, f905ff471). NSpecInsCnt is touched only by BeginPrereqs/FlushPrereqs; every filler appends through one push under one bound (PrereqReserve) against one named capacity (PREREQ_CAP, which the array itself derives from), the leading-`type` decision is an argument applied at flush, queue order IS the ordering rule, and PrereqsPending() asks the three counters once. EmitSpecDecl went 42 lines to 21 and now reserves a whole declaration before pushing any of it. Was: `NSpecIns` — the buffer that carries 'declarations that must exist before this specialization' — was filled by FOUR independent sites through three different emitters (EmitSpecDecl, EmitQualAliasDecl, EmitHoistedDecls) with four hand-written `NSpecInsCnt := 0` / `InsertTokens` pairs, each carrying its own capacity check, its own leading-`type` decision and its own ordering rule. One concept, four doors. Verified by emitted-code identity over all 47 test_generic_* sources (32 identical binaries, 15 identical diagnostics, 0 differing) against a control reporting 32 of 32 differing versus the pin — NOT by the compiler's own sha, which adding procedures moves by design. Per root-cause-over-microfix.md two mechanisms is a smell and three is a design flaw — this is at four, and it got there one honest increment at a time in a single session."
owner: frankA
---

# One prerequisite emitter, not four doors into `NSpecIns`

Filed by the agent that added two of the four doors, on the day it added them.
Not a criticism of the increments — each was the right local change and each
landed with its regression set green. The point is that the shape is now visible
and will not be visible later.

## The population, named rather than gestured at

`compiler/pasparser_generic.inc`, HEAD of 2026-08-30:

| site | fills `NSpecIns` with | splices at |
| --- | --- | --- |
| `DelphiRewriteGenericUses` (~1172) | qualified-argument aliases | `insertAt` |
| `EmitLateNestedSpecDecls` (~1864) | nested specializations, after the section | `TokPos`, **with a leading `type`** |
| `ParseSpecialization` fast path (~2319) | nested specializations, materialisation-time | `TokPos` |
| `ParseSpecialization` deferral (~2364) | hoists, then qualified aliases, then nested specs, then the re-emitted self | `TokPos` |

Three emitters feed them — `EmitSpecDecl`, `EmitQualAliasDecl`,
`EmitHoistedDecls` — plus `QualPush`, which two of the three use for individual
tokens and the third does not.

## Why this is a design flaw and not tidying

Everything below is a rule that exists in one door and not the others, which is
the definition of the second path that stays broken:

- **The leading `type` keyword.** Exactly one site emits it, with a correct and
  well-documented reason (the section loop has already exited, so a bare
  `X = specialize Y<Z>;` is not a declaration there). Nothing states the rule
  where the other three could see it, so the fifth door will get it wrong in
  whichever direction its author happens to test.
- **The capacity check.** `EmitSpecDecl` guards `8 + 2*nArgs`; `QualPush` guards
  one token at a time; `EmitHoistedDecls` guards `n + 4` before a bulk copy.
  Three encodings of one buffer's limit, and the buffer is sized
  `MAX_NESTED_SPECS * (8 + 2*MAX_TEMPLATE_PARAMS)` — a formula that mentions
  nested specs and now carries hoisted record bodies, which have nothing to do
  with `MAX_TEMPLATE_PARAMS`.
- **The ordering rule.** "Hoists, then qualified aliases, then nested specs,
  then self" is real and load-bearing — each names the one before it — and it
  exists only as the statement order inside one `begin`/`end`. It is not
  checked, not named, and not visible from the other three doors.
- **The deferral trigger.** `(NSpecCount > 0) or (QNeedCount > 0) or
  hoistPending` — three counters that mean the same thing ("something must be
  declared ahead of this"), each added by a different change, each with its own
  reset points. A fourth kind of prerequisite means a fourth counter and a
  fourth clause, and forgetting one is silent.

## The reduction argument, which is what makes it worth doing

The proposal is a single `QueuePrereq(kind, ...)` / `FlushPrereqs(at,
needsTypeKeyword)` pair: one buffer, one capacity rule, one ordering (queue
order), one "is anything pending" predicate. Then:

- the leading-`type` decision becomes an argument at one call site instead of a
  fact three sites do not know;
- `hoistPending` / `QNeedCount` / `NSpecCount` collapse into `PrereqCount`, and
  the deferral condition stops growing a clause per feature;
- the next prerequisite kind is a new `kind` value rather than a fourth door;
- `bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template`
  gets materially easier, because its fix is *per-use anchoring* — several
  splices at several points instead of one ordered run — and that is a change to
  the flush, not to four sites.

That last point is the honest reason this is ranked at all: it is a refactor with
a named ticket it unblocks, not a cleanup for its own sake.

## Timing — deliberately NOT taken when filed

Filed during a fleet-wide pause before a re-pin. A broad rewrite of a shared
frontend file in the hour before a binary is blessed is the one window where this
shape of change is wrong, and a *partial* normalisation is worse than either end
state. Same call frankC made the same day on an `until (depth = 0) or
(CurTok.Kind = tkEOF)` repeated at four sites: not landing the one-liner, because
fixing one arm is how you get the arm that stays broken.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) +
`python3 tools/forwardlint.py` (read the output) + the full named generic set:
the 25 in `test-core` plus `test_generic_qualified_arg{,_delphi}` and
`test_generic_nested_type_as_argument`, each diffed against its `.expected` or
against `pinned`. **`test_generic_cycle_fail` must still fail with its cycle
diagnostic** — it is the control for every change to the deferral path and the
one this refactor is most likely to break. Track T sweeps the matrix.

---

## 2026-09-05 (frankA) — count RE-DERIVED and it holds at four; the line numbers do not

The body's table is dated 2026-08-30 and its four line numbers have all drifted.
Re-derived at `3e25c7ae5` from the door predicate rather than the names:

```
grep -n 'NSpecInsCnt *:= *0'          compiler/*.inc
grep -n 'InsertTokens(.*NSpecIns'     compiler/*.inc
```

Four resets, four splices, one file, pairing exactly:

| reset | splice | body's stale figure |
| --- | --- | --- |
| `pasparser_generic.inc:1757` | `:1762` | ~1172 |
| `:3134` | `:3162` | ~1864 |
| `:3636` | `:3642` | ~2319 |
| `:3684` | `:3700` | ~2364 |

**FOUR is correct — this ticket is not overselling itself.** Worth stating
explicitly because the sibling refactor
[[refactor-p-three-hand-rolled-postfix-loops]] WAS underselling itself by 40%
when I recounted it, and tonight frankB found a "twice" that was three times
with the uncounted copy carrying two silent bugs. **The instrument has now failed
in both directions in one week, so a holding count is a result, not a
formality.** The greps above are the durable half; the line numbers will drift
again.

---

## 2026-09-05 (frankA) — DONE, in two gated halves (`101bf561f`, `f905ff471`)

Four doors are one. `NSpecInsCnt` is touched only by `BeginPrereqs` and
`FlushPrereqs` now; every filler appends through `QualPush` / `PrereqPushRaw`
under one bound, `PrereqReserve`, against one named capacity, `PREREQ_CAP` —
which the buffer's own declaration derives from, so the array and its guard
cannot disagree.

Each of the four private facts the body listed, and where it went:

| was | is |
| --- | --- |
| leading `type` known at one door | an argument to `FlushPrereqs`, applied at flush so an empty queue cannot splice a lone `type` |
| three capacity encodings | `PrereqReserve`, one bound; `EmitHoistedDecls` keeps only its *message*, being the overflow a user can reach |
| ordering as statement order in one `begin`/`end` | queue order, with the rule written on `BeginPrereqs` |
| `NSpecCount` / `QNeedCount` / `hoistPending` at each asking site | `PrereqsPending(hoistPending)` |

`EmitSpecDecl` went 42 lines to 21: it open-coded the same six-line slot fill
ten times and reserved *after* the first, so a buffer filling mid-declaration
could splice half an `alias = specialize Name<args>;`. It reserves the whole
declaration up front now.

### The gate, and why the fixedpoint is not it

This adds procedures, which changes declaration order, which is exactly what
[[refactor-p-carve-out-paslexer-so-p-owns-its-lexer-too]] measured as the thing
that moves the compiler's own bytes. So the sha is expected to move and says
nothing. What must not move is the code it EMITS.

All 47 `test_generic_*` sources, compiled by the compiler from **before step 1**
and by the final one: **32 byte-identical binaries, 15 refusing with
byte-identical diagnostics, 0 differing, 0 exit-code differences.** Comparing
diagnostics rather than just exit status is what makes the 15 negative tests
carry signal instead of passing by failing.

Positive control on the same harness against the pinned compiler: **0 identical,
32 differing.** `test_generic_cycle_fail` still fails with its cycle diagnostic
naming both sides. `forwardlint` ok. `gate.sh quick` GREEN with the FPC seed
canary concurrent — the canary matters here because two routines were
forward-declared across their first call.

### What it unblocks, which was the ranking argument

[[bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template]]
wants *per-use anchoring* — several splices at several points instead of one
ordered run. That is now a change to `FlushPrereqs` and its call sites rather
than to four independent doors. Not attempted here.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit edf8afadf.
