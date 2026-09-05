---
track: P
prio: 40
type: bug
status: done
blocked-by: []
owner: frankO
summary: "The implicit Self injected at parameter slot 0 shifts every per-param array with it -- except `puntyped`, at all three injection sites. A METHOD's untyped-param flag therefore sat one slot LEFT of its parameter, so for `M(a: Integer; out b)` the typed `a` answered untyped and the untyped `b` answered typed. Two defects in opposite directions from the one omission, both measured on pin fe1e9c37d322 as well as at HEAD: the method spelling of `Integer(b) := 99` was REFUSED where the byte-identical free routine is accepted, and the method spelling of `Int64(a) := 99` was ACCEPTED -- an 8-byte store into a 4-byte parameter slot, silent, no diagnostic. Fixed; test asserts the method/free RELATION so it carries no per-target width."
---

# The Self shift forgets `puntyped`, so a method parameter is mislabelled

`pnames`, `ptypes`, `pconst`, `pout`, `pdefault*`, `pDynDepth`, `pDim*` all
shift when Self is injected at slot 0. `puntyped` did not, at any of the three
sites: two in `pasparser_proc.inc` (the method-impl shift and its `__genself`
twin) and one in `pasparser_decl.inc`.

`IsUntypedVarParamSym` (`pasparser_stmt.inc`) matches the parameter NAME at slot
`i` against the FLAG at slot `i`. Moving one and not the other therefore
mislabels **both** ends at once — which is why one omission produced two
opposite defects.

## Measured, and both halves pre-date the fix

Byte-identical parameter lists, free routine vs method. Pin `fe1e9c37d322` and
HEAD agreed, so this is not a recent regression:

| construct | free routine | method | correct |
| --- | --- | --- | --- |
| `Integer(b) := 99`, `b` untyped | accepted | **REFUSED** | accepted |
| `Int64(a) := 99`, `a` a 4-byte Integer | refused | **ACCEPTED** | refused |

The cast-as-lvalue arm is legal on an untyped parameter precisely because such a
parameter has no declared width for the cast to disagree with. The second row is
the dangerous direction: an 8-byte store into a 4-byte slot, accepted with no
diagnostic.

## How it stayed invisible

Nothing asked a *method* parameter whether it was untyped. The construct that
does — the cast-as-lvalue arm — is rare, and the overload-matching readers of
`ProcParamUntyped` are reached for methods only on a path that, at HEAD, does
not type-check single-candidate method arguments at all.

**A probe I built for this first could not fail**, and the controls caught it:
an interface method binding a string to an `Integer` parameter was accepted —
but so was the same call with *no untyped parameter anywhere*, so the probe was
measuring the missing check, not the shift. The discriminating pair had to be
the two cast-as-lvalue directions, where free and method spellings differ.

## Fix

`puntyped[i] := puntyped[i-1]` in both `pasparser_proc.inc` shift loops and
`mPUntyped` in the `pasparser_decl.inc` one, plus `[0] := False` beside the
existing `pconst[0] := False` (Self always has a type).

`test/test_method_untyped_param_self_shift.pas`, wired into `test-core`, asserts
that the method matches the byte-identical free routine **and** that both give
the right value — an equality-only check would pass on two identical zeros. It
carries no per-target constant. Positive control: the pinned compiler refuses to
compile it, at the method, `cast-as-lvalue: the cast type must be the same size
as the variable`.

Found while diagnosing the single-candidate gate widening in
`refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes`: two of
that experiment's regressions were this bug becoming visible once the gate
started reading `ProcParamUntyped` for methods.
