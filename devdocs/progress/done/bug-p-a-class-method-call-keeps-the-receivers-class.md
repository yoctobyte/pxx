---
track: P
prio: 70
type: bug
blocked-by: []
summary: "A CLASS method's call result kept the RECEIVER's class in the selector chain instead of its return type: `f.MakeC.Tag` looked Tag up on f's class, not on MakeC's. Where only the returned class had that member it was a spurious `no such member`; where BOTH had one it silently CALLED THE WRONG METHOD on the wrong object (measured: printed 70 from the receiver's method where fpc rejects the program outright). One missing line in pasparser_lval.inc's instance-reached class-method arm, which set node and tk but not recName."
status: done
owner: frankA
---

# A class-method call keeps the receiver's class instead of its return type

Found while reducing rung 3's wall at `generics.defaults.pas:3341`
([[feature-pascal-corpus-generics]]). Not the wall itself — a second, more
serious defect the reduction walked through on the way.

## The silent arm is the one that matters

The spurious rejection is the visible half. The dangerous half:

```pascal
x := f.GetObjC.OnlyOnFactory(14);   { OnlyOnFactory is a member of f's class,
                                      NOT of the class GetObjC returns }
```

pxx **compiled this and printed 70** — it resolved `OnlyOnFactory` against the
receiver's class and called it on the returned object. FPC rejects the same
program: `identifier idents no member "OnlyOnFactory"`. A member lookup that
silently lands on the wrong class, called against an object of an unrelated
type, is a wrong-value/wrong-dispatch bug, not a diagnostics difference — so it
is a `bug-` ticket rather than compat, per CLAUDE.md's escape row.

## Root cause — one missing line

`compiler/pasparser_lval.inc`, the "a CLASS method reached through an INSTANCE"
arm:

```pascal
  node := mcallNode;
  tk := Procs[mpi].RetType;
  Continue;                      { <-- recName never updated }
```

The instance-*method* arm ~300 lines below does the same three lines **plus**
`recName := ProcRetRecId[mpi]`, and carries a comment explaining that the loop
must continue so `obj.M.M2` chains resolve. This sibling arm was written without
it, so the receiver's `recName` survived into the next selector iteration.

That is this rung's recurring shape, named in the ticket's own recon notes: **a
facility that works on one path and is missing on its sibling.** Worth checking
first the next time a wall here looks novel.

## Measured, one variable at a time

FPC 3.2.2 answers 42 for every row.

| receiver | the called method | pxx before | after |
| --- | --- | --- | --- |
| instance | instance function | 42 | 42 |
| instance | **class** function | `"Inst": no such member` | 42 |
| instance | class fn, member exists on BOTH classes | **70 — wrong method, silently** | rejected, as fpc does |
| instance | split via a temp var | 42 | 42 |

The third row is the one that justifies the priority; the fourth is the control
that a fix must not trade away.

## Not fixed here, and deliberately separated

Two neighbours measured in the same sweep are **different defects** and are
filed apart rather than folded in:

- [[bug-p-a-call-chained-onto-a-class-method-result-is-dropped]] — the class-NAME
  receiver (`TFactory.MakeC.Tag`) is still silently wrong after this fix.
- [[bug-a-nodemetaclassci-does-not-know-a-virtual-class-method-call]] — the
  actual corpus wall, and Track A's file.

## Gate

`make compiler/pascal26` (fixedpoint, `8c0f0e471e61`), `tools/forwardlint.py`
clean, `gate.sh quick` GREEN. Test `test/test_class_method_result_type.pas`,
expected generated from FPC, **confirmed refused on the baseline first** (line
38, `no such member`). It carries the working sibling and the split spelling as
controls.

## Log
- 2026-08-29 — resolved, commit 2674dfe45.
