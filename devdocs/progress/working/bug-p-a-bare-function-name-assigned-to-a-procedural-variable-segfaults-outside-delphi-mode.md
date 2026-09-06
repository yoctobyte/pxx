---
track: P
prio: 60
type: bug
blocked-by: []   # cleared 2026-09-06: the fix asks the recorded per-entity ProcSig facts and never needs the overload probe
summary: "RESOLVED 2026-09-06 on the SECOND attempt (the first, 4760474da -> 2d6bfadd6, is kept below as `The attempt that failed`). FOUR spellings, not the two this ticket names: `f := G`, `r.f := G`, `a[0] := G` and `Use(G)` all compiled outside `{$mode delphi}` and segfaulted at runtime; all four now refuse, and fpc 3.2.2 refuses the same four lines (checked, not assumed). THE REVERTED ATTEMPT AND THIS ONE DIFFER IN WHAT THEY ASK, NOT IN WHERE THEY ASK IT: it typed the slot `tyPointer` and wrote a pointer-general rule, and this ticket's own diagnosis of why that fails -- `TTypeKind` cannot tell a pointer that will be CALLED from one that will be READ -- is correct and is the design. So the check never consults the kind: it asks `SymProcSig`/`UFldProcSig`/`SymElemProcSig`/`ProcParamProcSig` (is the destination a procedural SLOT) and `ProcRetProcSig` (is the source a call whose result is not itself procedural), so `f := MakeCb` still works and a Char into a PChar is unreachable from here. Three wired tests. A consequence was split out rather than folded in: bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target -- `r.f := G` and `a[0] := G` under Delphi mode SIGSEGV'd on pin v404 and are now REFUSED, which is louder and still not what fpc does."
status: working
owner: frankB
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

## RESOLVED 2026-09-06 — all four spellings refuse, and the rule never asks the kind

Three wired tests:
`test_a_bare_routine_name_into_a_procedural_slot_is_refused` (the four
refusals, counted, and fpc 3.2.2 refuses the same four lines — checked, not
assumed), `test_a_routine_address_into_a_procedural_slot_still_works` (the
positive half, fpc's own output byte for byte) and
`test_delphi_mode_binds_a_bare_routine_name` (the other side of the flag).

**WHAT MADE THE RETRY WORK IS THAT IT ASKS A DIFFERENT QUESTION.** The reverted
attempt typed the slot `tyPointer` and then wrote a pointer-general rule, and
this ticket's own diagnosis of that — *`TTypeKind` cannot tell "a pointer that
will be CALLED" from "a pointer that will be READ"* — is correct and is the
whole design. So the check does not consult the kind at all. It asks the two
facts already recorded per entity:

- **is the destination a PROCEDURAL slot** — `SymProcSig` (variable/parameter),
  `UFldProcSig` (record/class field), `SymElemProcSig` (element of an array of
  them), `ProcParamProcSig` (a formal parameter). One arm per lvalue shape, in
  `NodeProcSlotSig`; every shape with no arm answers -1 and falls into the old
  ACCEPT, because a refusal site must fail open.
- **is the source a CALL whose result is not itself procedural** —
  `ProcRetProcSig`. `f := MakeCb` (a function RETURNING a procedural value) is
  therefore accepted, and is row C of the positive test: it is the row that
  separates this rule from the next-wider one, *"a call cannot fill a
  procedural slot"*, which passes every other row in that file.

A PChar is neither of those things, so the Char-into-PChar shape that reverted
the first attempt cannot be reached from here by any spelling. The eight tests
this ticket names by name were run individually before the suite.

**FOUR SPELLINGS, TWO CHECKS, AND THE SPLIT IS STRUCTURAL.** Three funnel
through `AN_ASSIGN`; the fourth is an ARGUMENT and passes through no node the
other three do, so it is checked at `IRLowerCallArg` — the one place that
already knows the parameter is procedural. That is why the first attempt fixed
the assignment and left the argument crashing: there is no single node to hang
one check on, and the ticket had recorded the argument face as a separate path
before the retry started.

**A SENTINEL THAT IS ALSO A REAL ANSWER, CAUGHT BY THE BUILD.** The argument
check first reused `pvSinkIsProcVar`, the local the sink already computes —
whose DEFAULT is `True`, meaning *"unknown, do not auto-call"*. For a BUILTIN
call `cpi` is negative, the default survives, and the compiler's own
`WriteLn(..., Ord(SymIsComInterface(i)), ...)` was refused: the self-host
failed, which is the one instrument that could have caught it. Rewritten to ask
`ProcParamProcSig` directly. Third instance in one day of a value that is both
a decline signature and a legal answer, and the remedy is the same each time —
**ask the fact, not the variable that was set from it.**

**AND THE FULL SUITE EARNED ITS MINUTES A SECOND TIME.** The first narrowing —
*"a call whose result is not itself procedural"* — refused
`m.Code := a.MethodAddress(nm)` in `test_method_ptr_cast_b277`, which builds a
callable `TMethod` by hand. That destination genuinely IS a procedural slot
(`TMethod.Code` carries a `UFldProcSig`) and a code address genuinely belongs in
it. `gate.sh quick` does not run that row. So the rule asks what the result can
HOLD, not whether it is a call: an ordinal, float, string or set result cannot
be a code address under any reading and jumping through one is the crash, while
a pointer, record or class result can be and is left alone. **Two axes, and only
one of them was in the test file I wrote** — the other was already asserted by
b277, which is where it stays rather than being duplicated.

**A SEPARATE DEFECT IS FILED AND IT IS A CONSEQUENCE OF THIS FIX:**
[[bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target]].
`{$mode delphi}`'s @-optional arm is keyed on the destination SYMBOL, so
`r.f := G` and `a[0] := G` never reached it — those two SIGSEGV'd on the pin and
are now REFUSED, which is louder and still not what fpc does. The Delphi
variable and argument spellings are unchanged and asserted. It is not folded in
here because the two changes run in opposite directions: this one is a REFUSAL
whose risk is refusing working code, that one is a BINDING whose risk is binding
where FPC calls — and stacking a speculative widening on a refusal is precisely
what the first attempt was reverted for.

**Gate:** `tools/gate.sh quick` with the tree DIRTY (FPC seed canary ran, PASS;
16 rows PASS; the only RED is the known `pinned builds live lib/rtl`). AND the
full Pascal suite under `PXX_ALLOW_FULL_SUITE=1`, lifted deliberately: the first
attempt at this ticket went red on thirteen rows that `gate.sh quick` does not
run and that the self-host fixedpoint **cannot see** — `compiler.pas` never
binds a Char to a PChar — so a green quick tier was read as coverage it never
had. That is the one situation the speed guardrail should be lifted for.
