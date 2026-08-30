---
track: A
prio: 55
type: bug
blocked-by: []
summary: "FIXED, and the hole was 17 columns on two paths, not 2 on one. ParseSubroutine registers params THREE ways -- `external` (then Exits), forward/interface, body -- each hand-copying its own subset of the ~20 durable ProcParam* columns: body wrote all, forward 14, external THREE. Three divergences from fpc 3.2.2 came out of that, in BOTH directions: an external pointer param accepted a class (open), a forward pointer param accepted one at a call parsed before the body (open -- the ticket had predicted this path benign, measured false), and an external DEFAULT argument was refused (closed). All three paths now write the full row. Duplication itself is filed as refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths, blocked on bug-a-a-nested-routine-cannot-capture-a-fixed-size-array."
status: done
owner: frankS
---

# An `external` routine's pointer-param pointee is never recorded, so a class argument is accepted

- **Type:** bug — **Track A** (`compiler/pasparser_proc.inc`, the param
  registration paths in `ParseSubroutine`).
- **Found:** 2026-08-30 by frankwasm, while enumerating the param/return
  carriers for `feature-unicodestring-model` step 6c by *reading* the pointer
  family rather than grepping it. Not part of that campaign — the campaign only
  supplied the reason to read these three paths side by side.

## Measured

Two programs differing in exactly one word (`{$mode objfpc}`-equivalent shape,
`TFoo = class`, `PInteger = ^Integer`, call `g(f)` with `f: TFoo`):

| declaration | pxx @ `894e93867` (fixedpoint `dc8546a1d159`) | FPC 3.2.2 |
| --- | --- | --- |
| `procedure g(p: PInteger);` + body | **rejected** — `argument types: (class)` / `candidates: g(Pointer)` | rejected |
| `procedure g(p: PInteger); external 'c' name 'abs';` | **compiles clean**, calls `abs` with an object pointer | `Error: Incompatible type for arg no. 1: Got "TFoo", expected "PInteger"` |

`PXXDBG=p.ptrparam` on each — this is the cause measured, not inferred:

```
external:  MATCH proc=g j=0 durable=0 sym=-1  symPtrElem=1 ...     <- no REG line at all
body:      REG   proc=g i=0 sym=94 elemtk=1 stored=1 durable=1
           MATCH proc=g j=0 durable=1 sym=94 symPtrElem=1 ...
```

`durable=0` is `Ord(tyUnknown)`. The guard at `symtab.inc:8146-8168` reads that
column and rejects a class argument only when the pointee is neither `tyUnknown`
nor `tyClass` — so the sentinel **permits** it. `sym=-1` closes the last exit:
`Params[j].SymIdx` is -1 for an external, so there is no symbol to fall back to
even unreliably.

## Cause

`ParseSubroutine` has **three** param-registration paths, and the durable store
is on only one of them:

| path | line | writes `ProcParamRecId` / `SetEnumId` | writes `ProcParamPtrElemTk` |
| --- | --- | --- | --- |
| `external` (then `Exit`s ~1334) | 1325-1328 | yes | **no** |
| forward / interface decl | 1641-1644 | yes | **no** |
| body, where param syms are allocated | 1978, 2081 | yes | yes |

The `external` path exits at ~1334, ~750 lines before the store at
`pasparser_proc.inc:2081`, and for an external routine the body path never runs
at all — so the column is *permanently* the sentinel, not merely late. The
forward path is filled in later when the body is parsed, so it is likely benign;
it is listed because it is the same hole and a caller parsed between the two
would see the sentinel.

## Why it was not caught

`bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching`
fixed the *scope-recycling* fail-open by introducing this durable column, and
`defs.inc:2685` records that reasoning at length. The column was populated where
the recycling bug was measured — the body path — and `external`, which has no
body and no symbol, was never the shape under test. The sentinel doing double
duty as "untyped pointer" is what makes both variants silent rather than loud.

## Fix sketch

Mirror the two lines that already sit beside `ProcParamRecId` on the external
path (1325) and the forward path (1641):

```pascal
if (i < MAX_PROC_PARAMS) and (ptypes[i] = tyPointer) then
begin
  ProcParamPtrElemTk[procIdx * MAX_PROC_PARAMS + i] := Ord(ptypesPtrElemTk[i]);
  ProcParamPtrElemRec[procIdx * MAX_PROC_PARAMS + i] := ptypesPtrElemRec[i];
end;
```

The staging arrays are live and correct at both points (the harvest at :964 has
already run for every param), so this is a copy, not a re-derivation.

**Consider the root-cause form instead.** Three registration paths each
hand-copying an overlapping-but-different subset of ~20 `ptypes*` staging arrays
into their `ProcParam*` twins is the shape `normalise-dont-special-case.md`
describes: the second and third paths are the ones that stay broken. One
`PersistParamRow(procIdx, i)` called from all three would delete the divergence
rather than patch this instance of it — and would retire the same class of bug
for `ProcParamProcSig`, `ProcParamDynDepth` and the rest, which should each be
audited for the identical hole before choosing the microfix.

## Repro

Self-contained — no fixture needed:

```pascal
program extl;
type
  PInteger = ^Integer;
  TFoo = class
  end;
procedure g(p: PInteger); external 'c' name 'abs';
var f: TFoo;
begin
  f := TFoo.Create;
  g(f);
end.
```

Expect a compile error naming the incompatible argument; today it links and runs.

## Gate

Track A: `make compiler/pascal26` (self-host fixedpoint) + this repro rejected +
the body-path control still rejected (guard not over-tightened) + an `external`
routine with a *correctly typed* pointer argument still accepted.

## 2026-08-30 (frankS) — FIXED. The audit changed the fix: 17 missing columns, three defects, both directions

Binary: self-host fixedpoint `20bfc94a2c80`; `tools/gate.sh quick` GREEN.

### The hole was wider than filed, and counting it is what changed the answer

The ticket names `ProcParamPtrElemTk` on the `external` path. Sweeping every
`ProcParam*` write in `pasparser_proc.inc` against the three paths:

| path | columns written (of ~20) |
| --- | --- |
| `external` (then Exits) | **3** — RecId, SetEnumId, StrElemTk |
| forward / interface | **14** |
| body | all |

So `external` was missing **17**, not 2. That is not a bigger version of the
same bug — it is a different bug, because the omissions fail in **opposite
directions** and only one of them is a fail-open:

| repro | before | fpc 3.2.2 |
| --- | --- | --- |
| `g(p: PInteger); external …; g(anObject)` | accepted | rejected |
| `g(p: PInteger); forward;` + a call parsed before the body | accepted | rejected |
| `g(a: Integer; b: Integer = 7); external …; g(1)` | **rejected** | **accepted** |

The third is the one the filed diagnosis could not have predicted: the same
missing-column mechanism makes the overload matcher fail **closed**, so an
external routine with a default argument was uncallable. A fix measured only by
what it starts refusing would have missed half its own effect.

### The forward path is NOT benign — the ticket's one wrong prediction

The ticket reasoned it was "likely benign, since the forward path is filled in
later when the body is parsed." Measured false:

```pascal
procedure g(p: PInteger); forward;
procedure caller; begin g(someObject); end;   { parsed FIRST — accepted }
procedure g(p: PInteger); begin end;
```

"Later" is after any caller parsed in between — and a forward declaration exists
*precisely* so that something may be parsed there. That is the one assumption
this path may not make.

### What landed, and what deliberately did not

All three copies now write the full row, with the canonical explanation at the
body path's copy (search `THE DURABLE PARAM ROW`) and pointers from the other
two. The forward path also adopted the body path's **write-only-true** rule for
defaults, which it lacked — a body repeats the parameter list without them.

**The collapse into one `PersistParamRow` was written and does not compile:**
`nested routine: capture of fixed-size array 'pconst' not yet supported`. The 21
staging arrays are fixed-size locals, and they cannot become globals either
because `ParseSubroutine` is **re-entrant** (`pasparser_call.inc:272` calls it
from an anonymous-method body). Filed as
[[refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths]],
blocked on [[bug-a-a-nested-routine-cannot-capture-a-fixed-size-array]], with the
23-`var`-param alternative recorded as rejected — 15 same-typed array params
means a transposition type-checks, trading a silent missing column for a silent
wrong one. Not reshaped around, per the platonic-code rule.

### Evidence

`test_param_row_external_forward_fail.pas` — 3 rows, same three lines fpc
rejects, with the body path's row kept as the arm that already worked.
`test_param_row_external_forward_ok.pas` compiles **and runs**, matching fpc's
stdout exactly across defaults, pointee, rec id, set enum id, string element
width, proc signature and a `var` dynamic array.

**Both non-vacuous against `pinned`:** it rejects 1 of the 3 fail rows, and
cannot compile the ok half at all.

### One divergence found and not filed as this ticket's business

`external 'c'` links under FPC and fails at load time under pxx (`cannot open
shared object file: c`); `external 'libc.so.6'` works in both, and is what the
repo already uses everywhere. Tests use the working spelling. Noted here rather
than filed — it is a soname-resolution question, not a param-row one.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
