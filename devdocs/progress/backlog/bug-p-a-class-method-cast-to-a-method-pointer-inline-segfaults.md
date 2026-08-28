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

## STATE CHANGE 2026-08-28 — defect A is fixed; defect B now fails LOUDLY

Re-measured at HEAD (`c70622013`, self-host verified) against FPC 3.2.2. **Do not
work from the eight-row table above without reading this first** — five of its
rows have moved.

| # | shape | pinned (was) | HEAD (now) | FPC |
| --- | --- | --- | --- | --- |
| 1 | instance → var → call | 15 | **15** | 15 |
| 2 | instance → var → record cast | TRUE | **TRUE** | TRUE |
| 3 | instance, INLINE cast | SEGFAULT | **compile error** | TRUE |
| 4 | class → var → call | SEGFAULT | **10** | 10 |
| 5 | class → var → record cast | SEGFAULT | **TRUE** | TRUE |
| 6 | class, INLINE cast (the corpus shape) | SEGFAULT | **compile error** | TRUE |
| 7 | `@TSvc.CPick` | TRUE | **TRUE** | TRUE |

**Defect A is fixed** (`9ab19fb21`, the RTTI-blob VMT offset). Rows 4/5 now agree
with FPC.

**Defect B changed failure mode rather than being fixed**, as a side effect of
[[bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage]]
(`c70622013`). Rows 3 and 6 now report

```
pascal26:17: error: wrong number of parameters in call to TSvc.IPick
```

This is the mechanism that ticket predicted, arriving from the expected
direction: `TSel(s.IPick)` segfaulted **because** `s.IPick` was silently read as
a zero-argument call and the resulting integer was reinterpreted as a
`Code`/`Data` pair. The arity check removes the silence. It does not yet supply
the right reading.

**So the remaining work is unchanged in substance and better in shape:** make
`s.IPick` resolve as a method REFERENCE when the context is a cast to a
method-pointer type, instead of as a call. What has changed is that the wrong
reading is now a diagnostic rather than a crash — the failure announces itself
and names the call, which is the whole difference between this and the class of
bug that hides for months.

**Honest cost, which is why this stays open at its own prio:** by CLAUDE.md's
compat table we now *reject a form FPC accepts* on rows 3/6 — normally a compat
item ranked by how much real code uses it. Here real code does use it: row 6 is
the **rtl-generics corpus shape** (wall 5). A segfault and a compile error both
block that corpus, so nothing regressed and the diagnostic is strictly more
useful; but this is a blocking divergence, not a cosmetic one, and it is the
reason to finish defect B rather than call the shape refused-by-design.

The regression sweep that cleared the arity change (lib/rtl, lib/pcl, examples —
unchanged compile counts, zero new diagnostics) did **not** cover this shape,
because nothing swept uses an inline method-pointer cast. It was found by
re-measuring this ticket's own table, not by the sweep.

## Defect B — located, and the shape the fix should take

**Where.** A cast through a user-declared procedural type goes through the alias
cast arm in `pasparser_expr.inc` (~6436), which is `Next; Expect(tkLParen);
ParseExpr; Expect(tkRParen);`. That site's own docstring already establishes it
is the single cast path a procedural type can reach ("ONE site, and that is the
whole answer to the question this ticket was parked on"), and that a procedural
type is always user-DECLARED so the builtin/scalar/PChar/enum cast flavours can
never produce a callable value.

*Verified:* the error surfaces on the cast's own source line, so the operand is
being parsed as a call. *Inferred from that docstring rather than instrumented:*
that this specific arm is the one `TSel(...)` takes. Cheap to confirm with a
probe before editing, and worth confirming — a plausible-but-unverified location
is how a wrong root cause got recorded in this repo before.

**Why it reads as a call.** `ParseExpr` has no notion of the cast's target type,
so `s.IPick` is resolved by the ordinary expression path. The `@`-less
method-reference reading exists only in the ASSIGNMENT arm
(`pasparser_stmt.inc` ~6797), and it is driven by the LHS symbol being a
method-pointer variable (`SymProcSig[idx] >= 0` and `TypeKind = tyRecord`). A
cast has no LHS symbol — it has a target TYPE — so that arm cannot fire, and the
call reading wins by default.

**The shape the fix should take, and the trap to avoid.** The obvious move is to
special-case the cast arm and build an `AN_METHODREF` there. That would be the
**fifth** near-identical `AN_METHODREF` construction site (`pasparser_expr` ×2
for the `@` forms, `pasparser_stmt` ×2 for the `@`-less Delphi forms), which is
past the point where `root-cause-over-microfix.md` says to stop adding
mechanisms and start counting them.

What the two contexts actually share is one question — *"is this mention a call
or a reference?"* — asked from two different sources of context (an assignment's
LHS type; a cast's target type). So the fix is to extract the `@`-less
method-reference reading into **one** helper that both arms call, parameterised
by the receiver, rather than to copy it a fifth time. That reduces the site count
instead of raising it, and it is the same normalisation that
[[bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage]]
applied to the arity decision.

**Do not simply relax the arity check to make this pass.** The check is what
turned this from a segfault into a diagnostic; weakening it restores the silence
and re-opens the garbage-argument hole everywhere. The call reading is not "too
strict" here — it is the *wrong reading*, and the fix is to supply the right one.

## Defect B — the reading is fixed; one lowering gap remains

**Verified first, as this ticket's own note asked.** A probe at the C4 alias
cast arm printed `C4 alias cast taken for TSel` immediately before the error, so
the inferred location is now measured fact rather than a reading of a docstring.
Probe removed.

**The fix.** `TryParseParenlessMethodRef` in `pasparser_call.inc` — **one**
place answering "is this mention a call or a reference?", where two contexts
were answering it separately. The cast arm consults it, gated on the alias
being a method pointer (`AliasProcSig >= 0` **and** `AliasTk = tyRecord`, the
16-byte `{Code, Data}` form the call arm already distinguishes from the pointer
form), so no other cast flavour changes how its operand is read. Both receiver
flavours are handled together because they are one concept: a variable (Self is
the instance, `AN_IDENT`) and a class name (Self is the metaclass blob,
`AN_CLASSREF`). **No fifth `AN_METHODREF` construction site was written.**

Measured at HEAD against FPC 3.2.2 — the cast in ASSIGNMENT position now works
for both receivers, and virtual dispatch survives the cast:

| shape | pinned | HEAD | FPC |
| --- | --- | --- | --- |
| `m := TSel(s.IPick)` | SEGFAULT | **15** | 15 |
| `m := TSel(TSvc.CPick)` | SEGFAULT | **10** | 10 |
| `m := TSel(s.VPick)`, override via base ref | SEGFAULT | **1005** | 1005 |

Pinned in `test/test_method_pointer_cast.{pas,expected}` — expectations taken
from the FPC oracle, and confirmed to **segfault on `pinned`**, so it is not a
test that would have passed anyway.

### What is left: `AN_METHODREF` has no lowering as a VALUE

Rows 3/6 — `TMethodRec(TSel(s.IPick)).Code` — now report

```
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 45) — a frontend gap, would miscompile
```

The parse is now correct; the node reaches IR lowering as a genuine method
reference and there is no arm for it in **value** position. `AN_ASSIGN` knows
how to write a method reference (Code at +0, Data at +TARGET_PTR_SIZE), so the
capability exists — it is simply not reachable except as an assignment RHS.

**This is the third failure mode this shape has had, and each step was an
improvement in honesty:** silent segfault → a false "wrong number of parameters"
(the arity check, correct mechanism, wrong reading) → an accurate refusal naming
the real gap. It is now the same honest `IR_UNSUPPORTED` exit as its virtual
sibling [[bug-p-the-address-of-a-virtual-class-method-cannot-be-lowered]]
(kind 88), which is the ticket to fix it **with**: one mechanism, two node
kinds, and fixing either alone leaves the other's exit in place.

The remaining work is Track A (`ir.inc`), not the frontend: factor the
method-reference materialisation out of `AN_ASSIGN` into a temp-producing
helper, and lower `AN_METHODREF` in value position through it — the same
normalisation, one level down.
