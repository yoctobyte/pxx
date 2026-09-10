---
slug: bug-n-traffic-py-has-an-uninferable-heading-field
title: lekkerzeilen/traffic.py — self.heading has no inferable type
track: N
type: bug
prio: 60
status: done
summary: >
  RESOLVED 2026-09-10 (frankB) — TWO causes, and the second is the one nobody
  could see. (1) a qualified module CONSTANT had no arm in PyInferExprType:
  `math.pi` is a parameterless Pascal function and therefore its own call, so it
  carries no `(` for the call arm to key on. (2) PyJoinInferTk's unknown
  handling was ASYMMETRIC against its own comment, so `self.h = math.pi if d
  else r` compiled while `self.h = r if d else math.pi` refused — same value
  set, arms swapped. Line 402 is the second spelling and needed BOTH fixes. The
  "what it is NOT" table below is correct and structurally blind to (2): every
  reduced ternary in it has both arms unknown, the one combination where an arm
  asymmetry cannot show.
---

## The wall

    pascal26:402: error: Nil Python: cannot infer the type of field
                  self.heading - annotate it

`traffic.py:402` is:

    x, z, run, _ = route.at(along)
    self.heading = run if downstream else run + math.pi

## What it is NOT — measured, so the next reader does not re-run these

Every constituent of that line compiles on its own. Seven probes, all `ok`
against binary 84993c095465:

| shape | result |
| --- | --- |
| ternary of two float literals | ok |
| ternary of a float parameter | ok |
| bare name from a tuple unpack | ok |
| ternary over a tuple-unpacked name | ok |
| 4-way unpack from a method call | ok |
| the whole line, route as an untyped param | ok |
| 4-way unpack with a `_` throwaway | ok |

So **the boundary was not read off the failing line**, and reading it off the
failing line is what produced this list — recorded because the list is the
useful part, not the hypothesis it killed.

## THE CAUSE — frankB's measurement, re-derived here before being written in

`self.heading = run if downstream else run + math.pi` carries **two decoys in
one line**: it reads as a conditional expression over a tuple-unpack element,
and neither matters. Varying the shape (frankB's rows, plus my three confirming
them against binary 458767f38926):

| shape | result |
| --- | --- |
| `self.h = math.pi` | **WALL** |
| `self.h = <unpack elem> + math.pi` | **WALL** |
| `self.h = <unpack elem> + 3.0` | ok |
| `self.h = <elem> if d else <elem> + 3.0` | ok |
| `self.h = math.sqrt(2.0)` | ok |
| `t = math.pi; self.h = t` | ok |

It is `math.pi` alone **for the isolated field** — and line 402 needed a
SECOND fix as well; see the resolution at the foot of this ticket. That
sentence was frankB's and it was theirs to correct.
`lib/rtl/math.pas:44` and `:280` declare
**`function Pi: Double`** — in Pascal a parameterless function IS its own call,
so the expression has no `(` for the call arm of `PyInferExprType` to key on,
and every arm declines. The last two rows are the control: the VALUE is fine
and it is the scanner's view of that shape that is not.

The diagnostic also suggests the wrong annotation — it offers
`(self.heading: int = ...)` for a Double.

**Owner: frankB**, who has the fix written and deliberately unapplied until
their tier clears, in `PyInferExprType` after the class-receiver arms so a
local named `math` still wins, gated on `ParamCount = 0` so `x = math.sqrt`
does not become a typeable Double by accident. Not duplicating it here.

## Where to look instead — SUPERSEDED, kept because the exclusions still hold

`self.heading` is stored in **four** places, not one:

- `402` — `run if downstream else run + math.pi`
- `546` — `self.heading = heading` (a parameter)
- `648` — `self.heading = state.heading` (a field OFF ANOTHER OBJECT)

The pre-pass decides one type per field from all of its stores, so a single
store it cannot type refuses the field, and it reports at the FIRST store
rather than the offending one. `648` is the suspect on shape — it reads a
field off `state`, whose class the pre-pass may not have — but that is a
suspect and not a finding, which is the distinction this ticket exists to
keep. **Reduce traffic.py in place** (`devdocs/progress/census/lz_census.py`
compiles one module; ast-guided statement removal did 1392 -> 9 lines on
vessel.py in 122 compiles).

## Related, and worth reading first

`refactor-n-the-field-type-pre-pass-asks-one-question-in-six-places` — six
mechanisms serving one concept is past the point CLAUDE.md calls a design flaw,
and several closed `bug-n-a-field-assigned-from-*` tickets are the same shape
fixed one arm at a time. If the sixth mechanism is why this refuses, the fix is
that refactor and not a seventh arm.

## Resolved 2026-09-10 (frankB) — TWO causes, and the ticket's own table could not see the second

1. **`PyInferExprType` had no arm for a qualified module CONSTANT.**
   `lib/rtl/math.pas` declares `function Pi: Double`, and in Pascal a
   parameterless function IS its own call, so `math.pi` carries no `(` for the
   call arm to key on and every arm declined. New arm resolves
   `<unit>.<name>` through `FindUnitOrAlias` + `FindProcInUnit` and splits on
   `ParamCount`: 0 gives the RETURN type, anything else gives `tyVariant`,
   because `self.f = math.sqrt` is a function VALUE and typing it as its
   return type is the widening that passes every test anyone would write.

2. **`PyJoinInferTk`'s unknown handling was ASYMMETRIC** — against its own
   comment, which promised that an unknown "leaves the other standing".
   `Result := ta` then `if (ta = tyUnknown) or (tb = tyUnknown) then Exit`
   only did that when the unknown was on the RIGHT:

   | shape | before | after |
   | --- | --- | --- |
   | `self.h = math.pi if d else r` | ok | ok |
   | `self.h = r if d else math.pi` | **refused** | ok |

   Same value set, arms swapped, opposite verdicts. Line 402 is the second
   spelling. `and` / `or` go through the same join and carried it too.

**The "What it is NOT" table above is correct and structurally blind to (2).**
Its row `ternary over a tuple-unpacked name: ok` has BOTH arms unknown, which
is the one combination where an asymmetry between the arms cannot show. It
takes one KNOWN arm and one UNKNOWN one, **in that order**. That is worth more
than the fix: the table was built by reducing the failing line, and reducing
towards simplicity removes exactly the mixedness the bug needs.

Neither the ternary nor the tuple unpack was ever the defect. Both are asserted
WITHOUT the module constant in `test/test_nilpy_a_field_from_a_module_constant.npy`
as negative controls, so a later change aimed at either has something to fail.

`648` (`self.heading = state.heading`) was the suspect named above and was not
involved.

traffic.py now walls at **:277**, `nearest() takes exactly 2 argument(s), got 3`
— unrelated, and a separate ticket if it is still there after a census.

Resolved in `PENDING-COMMIT`.
