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

---

## 2026-09-04 (frankH) — banked: why no signature-only entry point is needed, MEASURED rather than read

Banked at frankuser's request before going idle. It was a reading when it went
into a peer message; it is a measurement now, and the two greps that settle it
cost less than writing the caveat would have.

**1. Every `AN_CALL_IND` construction site already carries its signature.**
All **18** `AllocNode(AN_CALL_IND)` sites in the tree set
`ASTIVal := <signature proc index>` within three lines of the allocation —
there is no site that builds the node and leaves the signature to be recovered
later:

| file | sites | field assigned |
| --- | --- | --- |
| `pasparser_lval.inc` | 5 (74, 667, 840, 1842, 3055) | `sigPi` / `fldSigPi` |
| `pasparser_stmt.inc` | 1 (7681) | `pvSig` |
| `cparser.inc` | 4 | `SymProcSig[idx]` / `sig` |
| `pyparser.inc` | 7 | `sigPi` / `fldSigPi` |
| `ir.inc` | 1 (3837) | `sig` |

The five in `pasparser_lval.inc` are the ones named in the boundary with
frankA. **The sixth Pascal site is in `pasparser_stmt.inc`** and is easy to miss
when the boundary is quoted as "the five".

**2. `ApplyCallResultPtrSuffix` needs nothing from a signature but its columns.**
Every use of `procIdx` in the whole procedure (in `pasparser_lval.inc`; cited by
NAME, not by line — see the re-check note below) is one of exactly two shapes — `Procs[procIdx].RetType`, once, and a
`ProcRet*[procIdx]` column, everywhere else: `ProcRetPtrElemTk`,
`ProcRetPtrElemRec`, `ProcRetPtrDepth`, `ProcRetPtrBaseTk`, `ProcRetPtrBaseRec`,
`ProcRetIsDynArray`, `ProcRetFixedArrBytes`, `ProcRetRecId`, `ProcRetElemTk`,
`ProcRetElemRec`, `ProcRetDynDepth`, `ProcRetArrAi`. Nothing reads a body, a
parameter list, a scope or a name.

**So the existing `(node, procIdx)` entry point IS the signature-only one.** A
new one would take the same two things and read the same columns.

### The residual risk is NOT the entry point, and this is the part to carry forward

The plumbing being uniform says the signature always ARRIVES. It says nothing
about whether the columns are FILLED, and they are not filled on every path —
measured in this slice's own `ProcRet*` census: `ParseSubroutine` fills all 17
columns, while the three `pasparser_decl.inc` paths fill the same 11 and drop
the same 6. `ProcRetEnumId` and `ProcRetRecId` were fixed there; the array
columns (`ProcRetIsDynArray`, `ProcRetFixedArrBytes`, `ProcRetElemTk`,
`ProcRetElemRec`) and `ProcRetProcSig` remain open as
[[bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type]].

**A signature declared by `ParseProcTypeSignature` therefore reaches this
function correctly and finds its array columns blank** — which reads exactly
like "this construct is not supported" rather than like a missing write.
Whoever picks that ticket up should expect the symptom to appear HERE while the
defect is in the writer, and should not go looking for a missing entry point.

Untested claim retired: nothing above is inferred from behaviour, and no repro
was run for this note. It is a static census of construction sites and of one
procedure's uses of one parameter, which is the whole of what it claims.

### 2026-09-05 — re-checked after `7095ca817`, and the citation de-lined

`7095ca817` (frankA, *"a `^` after a FIELD of a call result derefs the FIELD,
not the call"*) landed four hunks inside this procedure, +38 lines. **The
conclusion above is unchanged and was re-run, not assumed:** every `procIdx`
use is still `Procs[procIdx].RetType` once plus the same twelve `ProcRet*`
columns. The new code works on the node/field side and adds no signature
coupling at all, which is a good sign about the change rather than a lucky
escape.

What DID break is the citation. This note originally said
`pasparser_lval.inc:5011-5434`; the procedure is now at 5060-5529, so those
numbers were wrong within a day of being written and **a stale line number does
not error -- it points somewhere.** This repo already learned that once and
acted on it: the `Makefile:<n>` citations in CLAUDE.md were replaced with recipe
names after one drifted 142 lines in an evening, to `fi; \`, a real line that
explains nothing. Same failure, same fix -- the procedure is cited by name here
now, and anyone re-running this should bound it with a grep for its `procedure`
line rather than trusting a number in a document.

The re-check itself is the reusable part, and it is one command:

```
sed -n "<start>,<end>p" compiler/pasparser_lval.inc \
  | grep -o "[A-Za-z_]*\[procIdx\]\|Procs\[procIdx\]\.[A-Za-z_]*" | sort -u
```

If that ever prints something outside `Procs[].RetType` and the `ProcRet*`
family, the conclusion has expired and a signature-only entry point may be back
on the table.

