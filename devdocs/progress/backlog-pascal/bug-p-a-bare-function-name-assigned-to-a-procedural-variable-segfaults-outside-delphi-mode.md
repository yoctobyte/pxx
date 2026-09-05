---
track: P
prio: 60
type: bug
blocked-by: []
summary: "ATTEMPTED AND REVERTED 2026-09-05 (4760474da -> 2d6bfadd6); the DIAGNOSIS below is sound and the ENFORCEMENT was not -- read `The attempt that failed` before retrying. TWO POSITIONS, not one: `f := G;` AND `Use(G)` where the parameter is procedural both compile OUTSIDE `{$mode delphi}` and segfault at runtime (measured 2026-09-05, rc=139 each). FPC rejects it there (`Incompatible types: got LongInt`) and accepts it only in Delphi mode, which pxx also gets right — so the Delphi arm is correct and the DEFAULT arm is the defect. Silent accept plus a crash is the worst of the three possible answers; erroring like FPC is the fix."
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

## 2026-09-05 (frankB) — it is FOUR paths, the root cause is real, and my fix was reverted

### What is established and should not be re-derived

Reproduced, then the SHAPE varied before fixing. The same value reaches a
procedural slot four ways. **pxx accepted all four silently and all four
SIGSEGV; FPC rejects all four:** `v := G`, `r.f := G` (record field),
`a[0] := G` (array element), `TakesIt(G)` (argument). The first three funnel
through one check; argument position is `TypesCompatible` and is a separate
path.

**The root cause is not a missing rule.** There IS a single assignment
type-check (`AssignKindsIncompatible`, one call site in `ir.inc`). It never ran
here, for two independent reasons in `AssignSideKind`, either of which alone was
enough:

1. **The destination was invisible on purpose** — `if SymProcSig[si] >= 0 then
   Exit; { procvar: the kind is the RESULT's }`. Probed rather than trusted, and
   the comment was right: `Syms[].TypeKind` for `f: TF` where
   `TF = function: Integer` is **Integer**, so `f := G` reads as
   `Integer := Integer`, the two sides **agree**, and the check passes.
2. **The source had no arm at all** — no `AN_CALL` case, so a call result
   short-circuited the whole check, *"looking, as before, exactly like a check
   that fired and passed"*, which is that function's own words about the
   previous three times.

A ticket saying "no rule for bare procvar names" would send someone to add a
fifth special case. That is why this section exists.

### The attempt that failed, and exactly why

`4760474da` typed a procedural slot as `tyPointer`, added the call-result arm,
and then added the rule the pair needs in both `AssignKindsIncompatible` and
`TypesCompatible`:

```pascal
if (pType = tyPointer) and (aType <> tyPointer) then  { WRONG }
```

**`TypeIsOrdinal` includes `tyChar`.** So this refused every legal
Char-into-PChar binding along with the procedural case — `Show('-')` and
`p := 'e'`, both of which this dialect allows and both of which have dedicated
tests. Thirteen rows went red on seven's NATIVE tier (eight NEW-RED plus five
gtk jobs that changed cause under an unchanged STILL-RED colour). Reverted in
`2d6bfadd6` rather than narrowed again, because a second speculative narrowing
stacked on a broken one, ungated, with a pin in flight, is three risks
compounding.

**Why the gate did not catch it, which is the reusable part:** `gate.sh quick`
does not run those rows, and the self-host fixedpoint **cannot see the shape at
all** — `compiler.pas` never binds a Char to a PChar. A GREEN was read as
coverage it never had.

### What the real fix needs

**The rule must be PROCEDURAL-TARGET-specific, not pointer-general.** The defect
is an ordinal reaching a slot that will be **called**; a PChar is a pointer that
will be **read**, and `TTypeKind` cannot tell them apart. That is one more
consumer of
[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] — and note the
shape it adds to that fork: the identity is needed at a REFUSAL site, where
getting it wrong rejects working code rather than mis-executing it.

**Any retry must run these by name before it is believed:**
`test_char_literal_to_pchar_param`, `test_char_to_pchar_conversion`,
`test_pchar_from_a_string_literal`, `test_cast_to_array_type`,
`test_dynarray_to_pointer_seam_leaks`, `test_stackless_gen`,
`test_generator_instance_freed_on_escaping_raise`, `strict_fpc_case_fail`.

### Do NOT "fix" it by adopting Delphi's binding

Binding the address in the default mode also removes the crash and accepts
strictly more programs. It was rejected deliberately: `defs.inc` documents
`DelphiMode` as *"the one behavioural delta"* of this dialect, and adopting
Delphi's answer everywhere deletes that delta. It is a dialect decision, not
something to arrive at while fixing a segfault. `docs/reference/modes.md`
already tells users to write `@F` here (frankD, confirmed).

### Related: three spellings of one rule, counted and deliberately not unified

`TypesCompatible` now has (or nearly has) three narrowings of "a pointer formal
cannot see its pointee": the existing `tyClass` one, this procedural one, and
frankH's `tyPointer <- tyString` work. Three is the count
`root-cause-over-microfix.md` calls a design flaw — but frankH's judgement,
which I accept, is that they do not share an ANSWER: each permits a different
pointee set, so a shared helper would take that set as a parameter and share the
`if` while sharing none of the thinking. Unify when the pointee question has one
answer; this revert is evidence we do not have it yet for the procedural case.


# The argument position segfaults too, and it is the p30 refactor's shape

Measured 2026-09-05 (frankB), following a cross-link frankS recorded and
frank-coordinator handed on. The ticket reported the ASSIGNMENT. The same bare
name in an ARGUMENT is the same defect:

| spelling | default mode | `{$MODE DELPHI}` |
| --- | --- | --- |
| `f := G` | compiles, **SIGSEGV rc=139** | prints 7 |
| `Use(G)`, `Use(h: TF)` | compiles, **SIGSEGV rc=139** | prints 7 |
| `Use(G)` where G is a PROCEDURE | `undefined variable (G)` | prints G |
| `f := @G` / `Use(@G)` | prints 7 | prints 7 |

fpc rejects both bare forms in objfpc (`Got "LongInt"`, and `Got "untyped"` for
the procedure), and accepts both in Delphi mode. So the third row is the same
mechanism wearing a different face: a bare FUNCTION name read as a call is a
value (an Integer, stored into a pointer slot and jumped through), and a bare
PROCEDURE name read as a call is not a value at all, so name resolution reports
it as undefined.

**This is the shape
[[refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes]] names
as its second unanswerable argument** -- *"a bare routine name used as a
procedural value types as neither a pointer nor the signature"*. It is one
missing answer with two consumers: the overload gate cannot run the full check
without it, and the default-mode arm cannot REFUSE without it, because refusing
requires knowing the name is a routine reference rather than a call.

The refactor is therefore **necessary and not sufficient** for this bug. It
supplies the fact; the enforcement is still the part that failed in
`4760474da`, and `The attempt that failed` above is still the thing to read
first.
