---
prio: 70
track: P
owner: unassigned
---

# Method pointers: a class method never works, and an inline cast never works

- **Type:** bug — **silent wrong behaviour**. Compiles clean, crashes at
  runtime. CLAUDE.md's "compiles but *runs* wrong" escape row, so a bug at its
  own prio rather than compat.
- **Track P** (Pascal frontend lowering).
- **Pre-existing:** every failing row reproduces identically on **pinned**.
- **Binary:** `ea689da902bb`. Oracle: FPC 3.2.2.
- **Virtual sibling:**
  [[bug-p-the-address-of-a-virtual-class-method-cannot-be-lowered]] — the same
  expression shape with a `virtual` class method refuses honestly
  (`IR_UNSUPPORTED`, kind 88) instead of crashing. One mechanism, two exits;
  fix together or the silent exit survives.

## The boundary — TWO independent defects, not one

Eight shapes, all measured on `ea689da902bb`:

| # | shape | pxx | FPC |
| --- | --- | --- | --- |
| 1 | instance → var → call | 15 | 15 |
| 2 | instance → var → record cast `.Code` | TRUE | TRUE |
| 3 | **instance, INLINE cast** `TMethodRec(TSel(s.IPick)).Code` | **SEGFAULT** | TRUE |
| 4 | **class → var → call** `m := TSvc.CPick; m(5)` | **SEGFAULT** | 10 |
| 5 | **class → var → record cast** | **SEGFAULT** | TRUE |
| 6 | **class, INLINE cast** (the corpus shape) | **SEGFAULT** | TRUE |
| 7 | `@TSvc.CPick` — plain address of a class method | TRUE | TRUE |
| 8 | `@s.IPick` — plain address of an instance method | TRUE | *rejects* |

Read down the table and two separable defects fall out:

**Defect A — a CLASS method cannot become a method pointer at all.** Rows 4/5/6
fail where their instance twins 1/2 pass. **No cast is required to trigger it**,
which is the important correction: row 4 is twelve lines with no cast and no
record in sight.

**Defect B — an INLINE cast of a method reference fails even for an instance
method.** Row 3 against rows 1/2: going through a variable works, casting in
expression position does not.

Whether these share one mechanism (method-pointer construction) or are two is
**the first thing to determine** — they might well be one, but the table does not
prove it and assuming it would pick the fix before the diagnosis.

Row 8 is not a defect: we accept a form FPC rejects, which is CLAUDE.md's
"not a defect" row. Belongs in `pascal-dialect-divergences.md`, noted here only
so nobody re-measures it as a finding.

## Simplest repro — defect A, 13 lines, no cast

```pascal
program n4;
{$MODE DELPHI}{$H+}
type
  TSel = function (A: LongInt): LongInt of object;
  TSvc = class
    class function CPick(A: LongInt): LongInt;
  end;
class function TSvc.CPick(A: LongInt): LongInt; begin Result := A*2; end;
var m: TSel;
begin
  m := TSvc.CPick;
  WriteLn(m(5));      { FPC: 10.   pxx: SIGSEGV, on HEAD and on pinned }
end.
```

## Why it matters — this is rung 6's current blocker

`generics.defaults.pas` uses row 6 (both defects at once) **28 times** to build
its comparer dispatch table:

```pascal
FEqualityComparerInstances[tkInteger] :=
  TInstance.CreateSelector(TMethod(TSelectMethod(
    THashService<T>.SelectIntegerEqualityComparer)).Code);
```

Measured on the **pristine** corpus — no stubs, typinfo facade `cfa72767f` in
place, wall 2 fixed — `generics.defaults.pas` now reaches line 2411 and stops
here. Walls 1 and 2 of the five-wall partition are genuinely gone; this is what
is left.

The error is reported at the enclosing procedure's `end;`, not at the offending
statement — IR lowering runs at procedure end. Do not read the reported line as
the site.

## Suggested direction

Rows 1/2 passing means the `{Code, Data}` construction path exists and is
correct for an instance receiver reached through a variable. So look at what
that path does when (a) the receiver is a class rather than an instance —
`Data` should carry the class reference, which is what a `class function`
expects as its hidden self — and (b) the reference is consumed in expression
position rather than assigned.

## A note on how this ticket was first filed

The first version of this table had four rows and concluded "everything adjacent
works, only the inline cast is broken." That was wrong: it had not tried
`class → var` (row 4) or `instance, inline cast` (row 3), which are the two rows
that separate the defects. Four shapes looked like a boundary and were not one.
Recorded because the fix that first table implied — "handle the inline cast" —
would have left defect A untouched and row 4 still crashing.
