---
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: frankB
summary: "FIXED, and it was FOUR paths rather than the one reported -- a variable, a record FIELD, an array ELEMENT and an ARGUMENT, all accepted silently, all SIGSEGV. Root cause is not the missing rule: AssignSideKind, the typing side of the only assignment check in the compiler, could type NEITHER side. It bailed on a procedural destination (`SymProcSig >= 0 then Exit`, because Syms[].TypeKind holds the RESULT's type, so `f := G` looked like Integer := Integer and the two sides AGREED) and had no arm at all for a CALL result -- the FOURTH time that function has been extended for that one reason. Fixed by typing a procedural slot as tyPointer, adding the call-result arm, and adding the pointer-sink rules the pair then needs in AssignKindsIncompatible and TypesCompatible; argument position is a separate path and needed its own. Deliberately ASYMMETRIC: only the pointer SINK is refused, so `i := PtrInt(p)` is untouched. {$mode delphi} is UNCHANGED and asserted so, because binding the address everywhere would also fix the crash and would silently erase the dialect's one documented behavioural delta -- that is a dialect decision, not a bug fix."
---

# A bare function name assigned to a procedural variable segfaults outside Delphi mode

```pascal
program p;
type TF = function: Integer;
function G: Integer; begin G := 7; end;
var f: TF;
begin
  f := G;          { no @ — objfpc requires one }
  writeln(f());
end.
```

| | result |
|---|---|
| fpc 3.2.2 `-Mobjfpc` | `Error: Incompatible types: got "LongInt" expected "<procedure variable type of function:LongInt;Register>"` |
| fpc 3.2.2 `-Mdelphi` | prints `7` |
| **pxx, default mode** | **compiles `ok:`, then SIGSEGV (rc=139)** |
| pxx, `{$MODE DELPHI}` | prints `7` |
| pxx, default, `f := @G` | prints `7` |

Measured 2026-09-05 at `9bcfd2b4da30`, and identical under
`stable_linux_amd64/default/pinned`, so it is not new.

## Why the Delphi arm being right is the useful part

`DelphiMode` is documented in `defs.inc:2857` as relaxing exactly this — *"a bare
function name bound to a procedural-value target to take its address
(@F-optional) … this is the one behavioural delta"* — and it works. So the
machinery to bind the name to its address exists and is correct; what is missing
is the **rejection** on the other side of the flag. Outside Delphi mode the bare
`G` is being read as a CALL (FPC's reading — hence its `got "LongInt"`), the
Integer result is stored into a procedural slot, and `f()` then calls through 7.

## Why this is a bug and not a dialect choice

The compat ceiling asks what the source MEANT and prefers the answer that leaves
a mistake visible. Both readings of a bare `G` are defensible and FPC picks one
per mode; **neither of them is "store an Integer in a function pointer and jump
to it."** There is no mode in which this program is correct, so accepting it
silently is not latitude — the three available answers are error (FPC's, in this
mode), take-the-address (FPC's, in Delphi mode, which we already implement), and
crash, and we ship the third.

## Not mine to fix

Found by frankD (Track D, docs) while establishing what `{$mode delphi}` actually
changes, in order to write it down truthfully on `docs/reference/modes.md` —
which had claimed the mode markers *"do not switch PXX into a different semantic
mode"*. They do; this is one of the two deltas, and it is the one that crashes.

Filed rather than fixed: Track P frontend work, and frankB holds that topic.

## 2026-09-05 (frankB) — FIXED, and it was four paths, not one

frankD reported the variable spelling with the oracle already measured, which
was the expensive half. Reproduced first, then varied the SHAPE before fixing —
and the same value reaches a procedural slot four ways. **pxx accepted all four
silently; FPC rejects all four:**

| path | pxx before | fpc -Mobjfpc |
| --- | --- | --- |
| `v := G` | compiles, SIGSEGV | `Incompatible types: got "LongInt"` |
| `r.f := G` (field) | compiles, SIGSEGV | same |
| `a[0] := G` (element) | compiles, SIGSEGV | same |
| `TakesIt(G)` (argument) | compiles, prints `calling: `, SIGSEGV | `Incompatible type for arg no. 1` |

## The root cause is not the missing rule

There IS a single assignment type-check (`AssignKindsIncompatible`, one call
site in `ir.inc`, and its own comment says every syntactic form of assignment
funnels through that node). It never ran here, for **two independent reasons in
its typing helper**, either of which alone was enough:

1. **The destination was invisible on purpose.** `AssignSideKind`'s AN_IDENT arm
   had `if SymProcSig[si] >= 0 then Exit; { procvar: the kind is the RESULT's }`.
   Measured rather than believed — reporting the raw kind for `f: TF` where
   `TF = function: Integer` leaves the assignment looking like `Integer :=
   Integer`, the two sides **agree**, and the check passes. The comment was
   true; bailing out was the same outcome, quieter.
2. **The source had no arm at all.** There was no `AN_CALL` case, so a call
   result returned False and the check short-circuited — *"looking, as before,
   exactly like a check that fired and passed"*, which is that function's own
   words about the previous three times. **This is the fourth.**

So the fix is three parts, and the first two are the actual bug:

- a procedural slot reports **tyPointer** (what the slot holds — a code
  address — rather than what calling it would produce). A METHOD pointer keeps
  the bail: it is a 16-byte `{Code,Data}` record, not a pointer;
- an **AN_CALL / AN_CALL_IND / AN_VIRTUAL_CALL / AN_CLASS_VIRTUAL_CALL /
  AN_INTF_CALL** arm, reading ASTTk exactly as the element/field/deref arm does
  and for the same stated reason;
- the rule the pair then needs, in **both** places, because argument position
  does not go through the assignment check: `AssignKindsIncompatible` and
  `TypesCompatible`. `TypeIsOrdinal` **includes tyPointer**, so the blanket
  ordinal/ordinal rule had been waving every one of these through — the pair had
  no rule at all. `TypesCompatible` already had the same shape for Boolean
  parameters, for the same reason.

**Deliberately asymmetric, and narrower than FPC.** Only the pointer SINK is
refused. `i := PtrInt(p)` is how NativeInt round-trips are spelled here, it is
not the direction that turns a value into an instruction pointer, and accepting
what FPC rejects is not a defect under this repo's ceiling. Asserted as a row.

## What was NOT done, and why it is a dialect decision

Binding the address in the default mode — Delphi's answer — **also fixes the
crash**, accepts strictly more programs, and is defensible under
*"us accepting what FPC rejects is not a defect"*. It was not taken: `defs.inc`
documents `DelphiMode` as *"the one behavioural delta"* of this dialect, and
adopting it everywhere deletes that delta. That is a dialect change, not a bug
fix, and it would need to be decided rather than arrived at while fixing a
segfault. `test_procvar_bare_name_delphi.pas` exists to make the difference
observable instead of assumed. `docs/reference/modes.md` already tells users to
write `@F` in the default dialect, so that page stays true as written and frankD
needs no doc change (they asked).

## Tests

- `test_procvar_bare_name_binding.pas` + `.expected` (fpc's own output): the
  POSITIVE half — every legal way to fill a procedural slot, plus the asymmetry
  row an over-broad fix would break.
- `test_procvar_bare_name_delphi.pas`: the control for the delta.
- `procvar_bare_name_{var,field,elem,arg}.pas`: the four refusals, **each
  asserting its SPECIFIC diagnostic rather than a non-zero exit** — a refusal
  test that only checks "the compiler failed" also passes when the fixture has a
  typo in it. Separate files because the argument arm is diagnosed at PARSE time
  and aborts before the assignment arms are lowered, so one file cannot show all
  four.

## Not a width change

Flagged because the coordinator warned that Track T is down and representation
changes are structurally invisible on x86-64: this one is not that class. It
moves no size, alignment or layout — it is a parse-time/AST type rule, and the
same rule fires identically on every target. The self-host fixedpoint
(~10k lines of Pascal through the changed check) is the blast-radius measurement
that matters here and it converged at each of the three steps.
