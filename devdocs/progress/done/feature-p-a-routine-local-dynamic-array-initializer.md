---
track: P
prio: 30
type: feature
blocked-by: []
status: done
owner: frankH
created: 2026-09-06
summary: "`var v: array of Integer = (1, 2, 3);` inside a routine is refused with `a routine-local dynamic-array initializer is not supported yet; assign in statements`. The FIXED-array case landed 2026-09-06 (feature-p-a-local-var-section-array-initializer); this is the deliberate residual and the reason it is separate is STRUCTURAL, not effort: a dynamic-array element list is carried as pending-init kind 10, whose payload is an AST NODE, and `FlushLocalInits` reads kinds 0/1/2/4/5/9 — every one of them a scalar, a string or a symbol index, none of them holding a node. So there is no local table row to write, and `RegisterVarInitElem` calls `Error` for kind 10 rather than writing a row the flusher would silently ignore. The fix is either a local kind that carries a node, or lowering the element list to statements at the flush site (which is what the diagnostic already tells the programmer to do by hand). fpc 3.2.2 -Mobjfpc accepts it. NOT hit by fcl-passrc rung 7 — ranked on the language, not on a corpus wall."
---

# A routine-local dynamic-array initializer

- **Type:** feature (compat — FPC-legal, refused) — **Track P**
  (`compiler/pasparser_decl.inc`).

```pascal
procedure P;
var v: array of Integer = (1, 2, 3);   { fpc: ok.  pxx: refused }
begin
  WriteLn(Length(v), ' ', v[0]);
end;
```

Global `var v: array of Integer = (1,2,3)` at file scope works today; so does the
routine-local FIXED array since `feature-p-a-local-var-section-array-initializer`.
This is the one spelling left.

## Why the refusal is narrow on purpose

The message names the missing half. Before the fixed-array fix, every local array
initializer answered *"local var-section ARRAY initializer not supported"* —
which was true of the message and false of the compiler, since the machinery
existed and only the fork was missing. Leaving the dynamic case behind the same
wide message would repeat exactly that, so it says `dynamic-array` and the
fixed case no longer reaches it.

**Pending-init kind 10 is the whole obstacle.** It carries an AST node —
the element list, unevaluated. `FlushLocalInits` walks kinds 0/1/2/4/5/9 and
every one of those is a value or an index; nothing in the local path can hold a
node. `RegisterVarInitElem` therefore raises rather than writing a row that
would be dropped without a diagnostic — a silently-ignored table row is the
failure mode this whole area already produced once.

## Gate

The global spelling is the control and must not move (it is the same element
loop). Assert `Length(v)` **and** an element value: a dynamic array that ends up
empty still compiles and still indexes-in-range for zero iterations, so a length
row alone can pass on a do-nothing lowering.

## 2026-09-09 — closed, and the premise had expired

`var v: array of Integer = (1, 2, 3);` inside a routine compiles and runs,
fpc-identical.

**The obstacle this ticket names no longer existed when I read it.** Its
summary says *"`FlushLocalInits` reads kinds 0/1/2/4/5/9 — every one of them a
scalar, a string or a symbol index, none of them holding a node"*, and offers
two designs for fixing that. Neither was needed: `FlushLocalInits` grew a
kind-10 arm of its own (`pasparser_proc.inc:114`) for a routine-local
`var g: TGUID = ICom`, whose GUID node cannot be rebuilt from a constant
either. The local table has held a node since then. **The refusal outlived its
reason by three days and the ticket was still accurate about the compiler it
was written against.**

**What was actually missing was one FORK, and it is the eighth instance of the
one this area keeps producing.** The 1-D dynamic arm wrote `PendingInit*` by
hand — nine field assignments — instead of going through
`RegisterVarInitElem`, the helper created precisely because *"the choice was
made SEVEN times inline in ParseVarSection's array loop, and every one of them
wrote PendingInit* unconditionally"*. So the fix is that arm calling the helper,
plus deleting two refusals.

### The bug the first attempt shipped, and the row that catches it

Routing the arm through the helper was not enough, because `vIsLocal` — the
flag that says WHICH TABLE — was assigned **further down the procedure than the
dynamic arm that needed it**. The arm therefore read the PREVIOUS declaration
group's value: a routine-local declaration registered a FILE-SCOPE initializer,
program entry assigned into a symbol index belonging to a rolled-back routine
scope, `Length(v)` answered 0 and the first index SEGFAULTED. `CurProc` cannot
change inside `ParseVarSection`, so the read now sits at the top, where its own
comment always claimed it was: **"read once" that is read once per SHAPE is not
read once.**

That failure needs TWO calls to the routine to be visible as anything but a
crash, which is why every row of the fixture prints twice — an initializer that
runs once at program entry and one that runs on each entry to the routine are
indistinguishable from a single call.

### The gate this ticket asked for

Row 1 is the global spelling, unmoved, because it is the same element loop and
a regression shows up there rather than locally. No row asserts a length alone:
an empty dynamic array compiles and indexes in range for zero iterations, so
every row reads back an element too, and one writes to the array afterwards
because a var initializer is a writable starting value.

`test/test_a_routine_local_dynamic_array_initializer` — seven rows, printed
twice, fpc-identical under `-Mobjfpc`, and identical on i386/aarch64/arm32/
riscv32 under qemu. The DELPHI bracket spelling `= [4, 5]` is a separate
surface and is not in the file: fpc refuses it under `-Mobjfpc` and accepts it
under `-Mdelphi`, where pxx agrees with it (`2 4 5` from both). The two
spellings cannot share a mode.

The other kind-10 site — a FIXED array of DYNAMIC arrays, one pending init per
element — was refused by the same assertion and is fixed by the same deletion.
It is row 5.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ad3f58463.
