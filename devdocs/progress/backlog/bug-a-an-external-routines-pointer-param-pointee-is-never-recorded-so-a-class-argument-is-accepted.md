---
track: A
prio: 55
type: bug
blocked-by: []
summary: "A routine declared `external` never reaches the durable param-pointee store, so `ProcParamPtrElemTk` stays at the `tyUnknown` sentinel for every one of its pointer params — and the narrowing guard that sentinel feeds fails OPEN. Identical signature, body vs `external`, is the whole difference: `procedure g(p: PInteger)` with a body correctly rejects a class argument; the same line declared `external 'c' name 'abs'` compiles clean and passes an object pointer to libc `abs`. FPC rejects it. This is the SAME fail-open as bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching, on the one registration path that fix did not cover."
status: new
owner: ""
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
