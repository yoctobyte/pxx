---
track: A
prio: 60
type: bug
status: done
found: 2026-08-31
found-by: frankA
owner: frankA
blocked-by: []
summary: "`p^[i]` is correct only when p is a plain local/global IDENTIFIER. Name the same pointer any other way and it breaks, four ways, all measured against FPC 3.2.2 on the same source: a pointer-to-array held in a RECORD FIELD gives silent wrong values for a fixed pointee (0.00 where FPC says 1.50, rc=0) and SEGFAULTS for a dynamic one; a FUNCTION RESULT (`GetP^[i]`) HANGS; and an ARRAY ELEMENT holding the pointer (`ap[0]^[i]`) segfaults. Cause is structural and already written down: DerefPtrArraySym is documented as narrow -- 'AN_DEREF over a plain identifier whose SymPtrElemArrLen > 0' -- and it is the predicate the whole family routes through, so every non-identifier spelling falls out of the array path and lands on whichever arm the element kind collides with. NOT the fixed/dynamic axis that bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride fixed: the record-field case is wrong for a FIXED pointee too, and all four faces reproduce identically on the compiler before that fix (5c3a2ab5324d)."
---

# `p^[i]` is only correct when the pointer is a plain identifier

Found while sweeping for siblings after
[[bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride]], on the
repo's own rule: fix one arm of a double case, grep for the other.

## Measured

Every row `for i := 0 to 3 do <spelling> := (i+1)*1.5` over a 4-element array,
then reading back element 0 and 3. FPC 3.2.2 answers `1.50 6.00` for all of
them (checked with `(p^)[i]`, since FPC rejects the bare spelling).

| how the pointer is named | pointee | pxx |
| --- | --- | --- |
| plain variable `p` | fixed | `1.50 6.00` — correct |
| plain variable `p` | dynamic | `1.50 6.00` — correct (fixed by the ticket above) |
| **record field** `r.q^[i]` | **fixed** | **`0.00 0.00`, rc=0 — silent** |
| **record field** `r.q^[i]` | dynamic | **SIGSEGV** (rc=139) |
| **function result** `GetP^[i]` | dynamic | **HANG** (rc=124 at 10s) |
| **array element** `ap[0]^[i]` | dynamic | **SIGSEGV** (rc=139) |

Sources in the ticket's repro block below; all four are ~8 lines.

**Not a regression, and not the fixed/dynamic axis.** All four reproduce
byte-identically on `5c3a2ab5324d3b97`, the compiler built from the commit
*before* the dynamic-stride fix — checked by reverting the two files, rebuilding
and re-running, then restoring. And the record-field case is wrong for a
**fixed** pointee, which that fix never touched.

## Diagnosis (banked, not acted on)

**ESTABLISHED vs HYPOTHESIS, explicitly, because the rest of this section is a
design argument and only part of it was run.** ESTABLISHED by measurement: the
six-row table above (each compiled and run, FPC diffed on the same source); that
all four faces reproduce on `5c3a2ab5324d3b97`, i.e. they predate the
dynamic-stride fix; and the carrier census below, which is a direct read of the
declarations in `compiler/defs.inc`. HYPOTHESIS, NOT run: that widening the
predicate's return is the right fix, and the per-face effort estimates that
follow from the census. No code was written for any of it.


`IsNodeArray`, `NodePtrElem` and the selector chain all decide "is this an
array?" for a deref by asking `DerefPtrArraySym` / `DerefPtrArrayInfo`. That
predicate's own docstring says what it covers:

> It is narrow (AN_DEREF over a plain identifier whose `SymPtrElemArrLen > 0`)
> and pure.

So a deref whose base is an `AN_FIELD`, an `AN_CALL` or an `AN_INDEX` answers
FALSE, the node keeps the ELEMENT's type tag, and — exactly as that ticket's
root-cause sentence puts it — *"whichever arm that element kind collides with
claims the node, and the symptom is a property of the ARM, not of the type."*
That is why one shape is silent, two crash and one hangs: four arms, one cause.

What is missing is that `DerefPtrArraySym` cannot express them, because it
returns a **symbol index** and a field or a call result has none.

**CORRECTION to an earlier draft of this paragraph, which said "the metadata to
answer properly already exists per source kind". That is only one-third true,
and the census matters more than the sentence did:**

| carrier | symbol | record field | call result |
| --- | --- | --- | --- |
| element kind / rec / str-kind | `SymPtrElem*`, `Syms[].PtrElem*` | `UFldPtrElemTk/Rec/StrTk` | `ProcRetPtrElemTk/Rec/StrTk` |
| pointee ARRAY shape (`ArrLen`, `NDims`, `DynDepth`, `StrCap`) | `SymPtrElem*` — **present** | **absent** | **absent** |
| alias handle back to the pointee type | absent | `UFldPtrAlias` — **present, populated** | **absent** |

So the three faces need three different amounts of work, and that is the useful
thing to know before starting:

- **Record field** — reachable **with no new storage**. `UFldPtrAlias[fIdx]` is
  set at field declaration (`symtab.inc:1746`) and `AliasPtrElemArrAi[alias]`
  gives the pointee's ArrType index, which carries the whole shape
  (`ArrTypeLo/Hi/NDims/ElemTk/ElemRec/IsDyn/DynDepth/ElemStrCap`). This is the
  face with the SILENT wrong values, so it is also the one worth most.
- **Call result** — needs a new `ProcRetPtrAlias` carrier, recorded where the
  result type is registered. This is the HANG.
- **Array element holding the pointer** — needs the equivalent for an array
  symbol's element. This is the second SIGSEGV.

That changes the earlier "do it once rather than teaching three call sites"
advice only in emphasis: the predicate widening is still the right shape, but
two of the three sources must be given something to answer WITH first. The
alias route is the pattern to copy, because it stores one integer instead of
four and cannot drift from the type it points at — which is precisely the
"a fifth field means four more chances for the copies to drift" hazard
`SetPtrElemArrayInfo`'s header already records.

**So the shape of the fix is a widening of the predicate's return, not another
arm** — something that answers "element kind, element rec, extent" for any
pointer-valued node, with the four existing carriers behind it. Do that once
rather than teaching three call sites about three more node kinds; the sibling
ticket's own conclusion was that one predicate beats a per-site copy, and this
is the same lesson one node-kind further out.

**Deliberately parked rather than microfixed.** Adding an `AN_FIELD` arm to
`DerefPtrArraySym` alone would fix the loudest face and leave the call-result
hang, which is the worst outcome: the crash that was pointing at the design
would be gone.

## Independently re-measured 2026-09-01 (frankB) — all four faces confirmed

Reproduced from scratch at compiler `c4a89282faa6` (commit `9b9e762d8`), each
program compiled `-O2` and run under `timeout 10`. **The table above is exactly
right**, including the two that are easy to get wrong: the record-field/fixed
case really does exit 0 with wrong values, and the function-result case really
hangs rather than crashing.

| face | pxx | rc |
| --- | --- | --- |
| plain `p^[i]`, fixed | `1.50 6.00` | 0 |
| record field, fixed | `0.00 0.00` | 0 — **silent** |
| record field, dynamic | — | 139 |
| function result `GetP^[i]` | — | 124 (**hang**, killed at 10s) |
| array element `ap[0]^[i]` | — | 139 |

**The plain-identifier row is the positive control and it is worth keeping as
one.** Same semantics, same arithmetic, different spelling, correct answer — so
"what should this print" needs no external oracle and no FPC run. A fix that
breaks that row has broken the working path, and a harness without it can pass
on a build where nothing compiled at all.

Not claiming this ticket — frankA registered the surrounding topic (aggregate
indexing and the record-vs-array type distinction) before I picked it up, and
they hold three neighbouring tickets that may share the cause. Recording the
confirmation because it is worth more than the hour it would cost the next
person to redo, and because a re-measurement on today's compiler is the thing
that decides whether a ticket found on 08-31 is still live. It is.

## Repro

```pascal
{ silent: prints 0.00 0.00, exits 0. FPC prints 1.50 6.00 }
type TF = array[0..3] of Double; TPF = ^TF; TR = record q: TPF; end;
var f: TF; r: TR; i: Integer;
begin
  r.q := @f;
  for i := 0 to 3 do r.q^[i] := (i+1)*1.5;
  WriteLn(f[0]:0:2, ' ', f[3]:0:2);
end.
```

Swap `TF` for `array of Double` (plus `SetLength`) for the SIGSEGV; replace the
field with `function GetP: TPD; begin GetP := @d; end` and index `GetP^[i]` for
the hang; put the pointer in an `array[0..1] of TPD` and index `ap[0]^[i]` for
the other SIGSEGV.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.
