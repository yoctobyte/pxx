---
slug: bug-p-member-access-on-a-procedural-variable-call-result-is-rejected
track: P
prio: 40
type: bug
status: done
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (writing test_cross_indirect_aggregate_return)
summary: "`fp(7).c` where fp is a procedural VARIABLE is rejected with `expected ')' before '.'`. The identical member access is accepted on a DIRECT call result (`Plain(8).c`) and on a VIRTUAL method call result (`b.M(8).c`), both measured working. feature-member-access-on-call-result is done and covered two of the three shapes; ApplyCallResultPtrSuffix is the one materialisation point and it takes a real procIdx, so the AN_CALL_IND sites never reach it. There are FIVE AllocNode(AN_CALL_IND) sites in pasparser_lval.inc, which is why this is not a one-line fix and is filed rather than patched at one of them."
---

# Member access on a procedural-variable call result is rejected

## Measured

One program, three shapes, one run (2026-09-04, x86-64):

```pascal
type TR = record a, b, c: Integer; end;
     TF = function(k: Integer): TR;
function Plain(k: Integer): TR;      { .a := k; .b := k*2; .c := k*3 }
type TB = class function M(k: Integer): TR; virtual; end;
var fp: TF; b: TB;
```

| expression | result |
| --- | --- |
| `Plain(8).c` | **24** — accepted |
| `b.M(8).c` | **308** — accepted |
| `fp(8).c` | **`pascal26:8: error: expected ')' before '.'`** |

So it is not member-access-on-a-temporary that is missing, and it is not
indirect dispatch either — a virtual call is indirect and works. It is
specifically the procedural-variable call.

## Why

`ApplyCallResultPtrSuffix` (`pasparser_lval.inc:4918`) is, by its own forward
declaration, *"the ONE materialisation point for a suffix on a call RESULT"*.
Its first statement is `tk := Procs[procIdx].RetType` — it takes a real proc
index, and every one of its callers has one. A procedural-variable call has a
signature proc (the IR carries it in `IRIVal` for `IR_CALL_IND`), but the
AN_CALL_IND construction sites do not call the helper at all.

## Why this is filed and not fixed

`AllocNode(AN_CALL_IND)` appears at FIVE sites in `pasparser_lval.inc` (72,
636, 809, 1811, 3024) plus one in `pasparser_stmt.inc`. Adding the suffix walk
at the site that happens to produce the reported failure is precisely the
second path that stays broken — the other four would each need finding again
later, by someone reducing a different symptom.

The shape of the fix is the same one `normalise-dont-special-case.md`
prescribes and that this helper's own comment already claims to be: make the
materialisation point reachable from the indirect sites too, once, rather than
five times. Whoever takes it should establish first whether all five sites have
a usable signature proc in hand at that moment, because that is what decides
between "call the existing helper" and "give the helper a signature-only
entry point".

## Guard when it closes

`test/test_cross_indirect_aggregate_return.pas` carries the row commented out
with this slug beside it (`fp(7).c`). Un-comment it; the file is already wired
on all six cross targets, so the row lands everywhere at once.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 49194d2ab.
