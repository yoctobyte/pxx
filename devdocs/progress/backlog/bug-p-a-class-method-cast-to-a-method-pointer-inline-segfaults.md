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

---

## Root cause for defect A, measured (frankA, `ea689da902bb`)

`PXXDBG=a.ast` on the two forms side by side is decisive.

**Instance (works)** — `m := s.IPick`:

```
kind=12 (AN_ASSIGN)
  kind=3  (AN_IDENT)      m
  kind=45 (AN_METHODREF)  <- a method REFERENCE
    kind=3 (AN_IDENT)     s
```

**Class (segfaults)** — `m := TSvc.CPick`:

```
kind=12 (AN_ASSIGN)
  kind=3  (AN_IDENT)      m
  kind=8  (AN_CALL)       <- a CALL, not a reference
    kind=9  (AN_ARG)
      kind=46 (AN_CLASSREF)
```

So `TSvc.CPick` is **called**, with the class reference passed as its hidden
self, and the returned `Int64` is stored into the 16-byte method-pointer
variable. `m(5)` then jumps to that integer. That is the SIGSEGV — the pointer
was never a pointer.

### Where the choice is made

`pasparser_stmt.inc:6797`, the Delphi `@`-optional method-pointer path
(`p := obj.M` == `@obj.M`). Its guard opens with:

```pascal
argIdx := FindSym(CurTok.SVal);
... and (argIdx >= 0) and (Syms[argIdx].RecName >= REC_UCLASS_BASE) ...
```

`FindSym` resolves a **variable**. For `TSvc.CPick` the receiver is a *type*, so
`argIdx < 0`, the arm is skipped, the next arm wants `FindProc` (also no), and
the expression falls through to the ordinary path — which parses `Type.Method`
as a call. The arm was written for instance receivers and a class receiver was
never added.

### What a fix has to get right

`AN_ASSIGN` writes `{Code, Data}`. For an instance, `Data` is the object. For a
class method, `Data` must be the **class reference**, which is what a
`class function` expects as its hidden self — so an `AN_CLASSREF` in `ASTLeft`
is the right shape, not a special case.

**The virtual half needs care and is where silent wrongness would enter.**
`IRMethodRefCode` (`ir.inc:5126`) resolves a virtual method as
`vmt := LOAD_MEM(selfVal); code := [vmt + slot*8]` — it *dereferences the object*
to reach the vmt. For a class reference the value **is** the vmt already, so that
deref is one indirection too many. Any fix must branch on receiver kind there, or
it will produce a plausible-looking wrong code pointer rather than a crash.

**And the corpus needs exactly the virtual path**: `generics.defaults.pas`
declares `SelectIntegerEqualityComparer ... override`, so all 28 sites are
virtual class methods. A non-virtual-only fix does not unblock rung 6.

### Defect B is not diagnosed

Everything above concerns defect A. The inline-cast failure (row 3, an *instance*
method) has not been traced and may or may not share this mechanism. Do not
assume it falls out of the same fix.

---

## Defect A FIXED (`9ab19fb21`). Defect B remains and is what blocks rung 6.

Fixed on binary `4157f75831bb`, `gate.sh quick` GREEN. Regression test
`test/test_class_method_to_method_pointer` asserts seven shapes against FPC,
byte for byte: `15 TRUE 35 TRUE 10 500 TRUE`. Five of them segfaulted before.

The two virtual rows are the load-bearing ones — `TSvc.CPick` (override) → 10
and `TBase.CPick` (base) → 500 must differ, which is what proves the blob's VMT
at +24 is being read rather than the blob's name pointer at +0. A wrong offset
there yields a plausible code pointer, not a crash, so the test pins both.

### Updated table

| # | shape | before | now |
| --- | --- | --- | --- |
| 1, 2 | instance → var → call / record cast | ok | ok |
| **3** | **instance, INLINE cast** | SEGFAULT | **SEGFAULT — defect B, open** |
| 4, 5 | class → var → call / record cast | SEGFAULT | **ok** |
| **6** | **class, INLINE cast** (the corpus shape) | SEGFAULT | **`IR_UNSUPPORTED` kind 88 — defect B, open** |
| 7, 8 | plain `@` | ok | ok |

Row 6 changed its failure mode but not its outcome: it no longer segfaults, it
now refuses. That is strictly better — it moved from the silent exit to the
honest one — but it is not a fix.

### Defect B, now with a shape

Same root cause as A wearing a different hat: a method reference is parsed as a
**call** in expression position. A fixed it at the *assignment* site
(`pasparser_stmt.inc`'s `@`-optional arm). B is the same mistake at the *cast*
site — `TSel(s.IPick)` and `TSel(TSvc.CPick)` — where a cast to a
method-pointer type should likewise yield a reference rather than invoking the
method.

That it hits an **instance** receiver too (row 3) is what makes it a separate
fix rather than a missed case of A: A's arm is only reached for an assignment
whose LHS is a method-pointer lvalue, and a cast has no such LHS to key on. The
type being cast TO is the signal instead.

**Rung 6 needs B, not A.** The corpus writes
`TMethod(TSelectMethod(THashService<T>.SelectBinaryEqualityComparer)).Code` —
row 6 — at all 28 sites, and `generics.defaults.pas` still stops at 2411.
