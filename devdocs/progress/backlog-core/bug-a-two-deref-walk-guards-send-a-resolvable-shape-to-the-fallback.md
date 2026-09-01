---
slug: bug-a-two-deref-walk-guards-send-a-resolvable-shape-to-the-fallback
title: "1159 derefs per full tier fall past an arm that could have answered them"
track: A
prio: 40
type: bug
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
status: new
summary: "ResolveDerefShapeAt has ten typed arms and two fallbacks that now just keep a default. Measured over a full tier with PXXDBG=a.derefwalk, the fallbacks take 1159 hits and only TWO node kinds ever reach them: AN_PTR_CAST 939 times, because the cast arm guards on `ASTIVal >= 0` and the adapter casts (ival -1/-2) fall past it; and AN_IDENT 220 times, because the ident arm answers tyUnknown for a pointer whose pointee it cannot name. Both then get tyInteger/tyUnknown, which is a GUESS in a walk whose whole job is to stop guessing -- the same family that produced five wrong-value tickets this week. Not urgent and not known to miscompile anything today: no test fails on it, which is exactly why it needs measuring rather than assuming. The counts come free from the probe, so the first job is to find out whether either default is ever WRONG."
---

# Two guards send a resolvable shape to the fallback

Fell out of [[refactor-a-collapse-nodeptrelem-into-the-deref-walk]], which
deleted the second walk those fallbacks used to consult. With it gone the
fallbacks keep a default, and the question "is the default right" is now the only
question left.

## Measured

Full tier, `PXXDBG=a.derefwalk:hits`, 1050 job logs of 7158 carrying a hit:

| kind | hits | why it falls past its own arm |
| --- | --- | --- |
| `AN_PTR_CAST` (39) | 939 | the cast arm is guarded `and (ASTIVal[node] >= 0)`; the ADAPTER casts carry ival -1/-2 and have no alias row |
| `AN_IDENT` (3) | 220 | the ident arm answers, but with `tyUnknown` — an untyped `Pointer`, say |
| `AN_FIELD` (11) | 1 | one job only; not yet characterised |
| `AN_CALL` (8) | 1 | one job only; not yet characterised |

The last two are single hits across a whole tier and are the interesting ones
precisely because they are rare — a shape that reaches a fallback once is a shape
nobody designed for.

## Why this is a bug and not a tidy-up

`tyInteger` and `tyUnknown` are GUESSES, in the walk whose stated purpose is to
stop each caller guessing. Every ticket in this family has the same shape: a
pointee that could not be named came out as a plausible ordinal, and the program
compiled, exited 0, and printed the wrong thing. The two fallbacks are the last
places in the walk where that can still happen by construction.

**No test fails on it today.** That is the reason to measure rather than assume:
the failure mode of this family is a wrong value in a spelling nobody tried, and
the population that found the last five was generated (`test/derefshape`), not
chosen.

## First job, before any fix

Do not widen the guards blind. For each of the four kinds, find whether the
default is ever OBSERVABLY wrong — the probe already prints the kind, so add the
source location and run one tier. If a default is always right for a kind, the
right change is to make that arm SAY so instead of falling through; if it is ever
wrong, the arm needs the missing carrier and that is the real ticket.

# Gate

Track A: `make compiler/pascal26` + `tools/gate.sh quick`, plus
`tools/derefshape_matrix.sh` (30 rows, write and read faces) and a full tier with
`TESTMGR_INHERIT_ENV=1 PXXDBG=a.derefwalk:hits` — note the inherit flag, without
which PXXDBG never reaches a testmgr job at all.
