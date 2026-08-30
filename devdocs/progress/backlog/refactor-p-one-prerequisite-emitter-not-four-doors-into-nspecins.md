---
slug: refactor-p-one-prerequisite-emitter-not-four-doors-into-nspecins
track: P
prio: 55
type: refactor
status: backlog
blocked-by: []
summary: "`NSpecIns` — the buffer that carries 'declarations that must exist before this specialization' — is now filled by FOUR independent sites through three different emitters (EmitSpecDecl, EmitQualAliasDecl, EmitHoistedDecls) with four hand-written `NSpecInsCnt := 0` / `InsertTokens` pairs, each carrying its own capacity check, its own leading-`type` decision and its own ordering rule. One concept, four doors. Per root-cause-over-microfix.md two mechanisms is a smell and three is a design flaw — this is at four, and it got there one honest increment at a time in a single session."
owner: unassigned
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
