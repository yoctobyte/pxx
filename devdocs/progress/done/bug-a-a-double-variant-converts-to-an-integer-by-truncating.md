---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`i := v` and `Integer(v)` on a Variant holding 2.75 answer 2; FPC answers 3. The VT_DOUBLE arm of VariantToInt64 truncates where FPC's variant conversion table ROUNDS (banker's, half-to-even). Silent wrong integer, off by one, through every integer target (Integer/Int64/Byte/Word/SmallInt all narrow from this one helper). pxx's own Round() is already correct -- only the VARIANT conversion diverges."
---

# A Double Variant converts to an Integer by truncating, not rounding

Found 2026-08-23 by the Variant differential family (`fpc 3.2.2 -Mobjfpc -O1`
vs pxx `9074403c0`).

```pascal
var v: Variant; i: Integer;
begin
  v := 2.75;  i := v;  WriteLn(i);   { fpc: 3   pxx: 2 }
  v := -2.75; i := v;  WriteLn(i);   { fpc: -3  pxx: -2 }
end.
```

**Silent wrong integer**, off by one, and it reaches every integer target:
`Integer`, `Int64`, `Byte`, `Word` and `SmallInt` all narrow from the same
helper, and all five were measured wrong together.

## The rounding mode, measured

| value | fpc | pxx |
| --- | --- | --- |
| 2.75 | 3 | 2 |
| 2.5 | 2 | 2 |
| 3.5 | 4 | 3 |
| 1.5 | 2 | 1 |
| 0.5 | 0 | 0 |
| -2.5 | -2 | -2 |
| -2.75 | -3 | -2 |

FPC is round-half-to-EVEN (banker's): 2.5 → 2 but 3.5 → 4, 0.5 → 0 but 1.5 → 2.
That is exactly what pxx's own `Round()` already does — measured side by side,
`Round(2.5)=2`, `Round(3.5)=4`, `Round(1.5)=2`, identical to FPC on every row.

## Why it is one word

`compiler/builtin/builtin.pas:1032`, the VT_DOUBLE arm of `VariantToInt64`:

```pascal
else if p^.VType = 3 then
  Result := Trunc(PDouble(@p^.Payload)^)
```

`Round` is the correct call and is the only occurrence of this pattern in the
builtin units. Scope is the VARIANT conversion table, the same scope the
neighbouring VT_BOOL rule already carries ("True is -1, not 1... scoped to the
VARIANT conversion: `Ord(True)` and `Integer(someBooleanVar)` stay 1"). A plain
`Trunc(2.75)` on a Double variable stays 2, as in FPC.

## NilPy is not affected and must not be

Python's `int(2.75)` truncates to 2, and CPython agrees with NilPy today. NilPy
does not reach this helper — pylib routes to `pyvar_to_int` (`pylib.pas:7499`,
with the comment saying so), the same lowering seam the VT_BOOL rule uses.
Verified: `int(2.75)`, `int(2.5)`, `int(-2.75)`, `int(3.5)` under NilPy match
CPython before and after.

## Not Track F

The datatype is a float; the MECHANISM is a conversion table entry that picks
the wrong operation, and the wrong value is an INTEGER off by a whole unit, not
a matter of ulps or digits. `Round()` itself is already correct, so nothing here
is about float accuracy. Rank the mechanism, not the datatype.

## Gate

Track A's, plus the seven rows above matching fpc 3.2.2 through each of
`Integer`/`Int64`/`Byte`/`Word`/`SmallInt`, a row proving `Trunc` on a plain
Double is unchanged, and a `.npy` row proving `int(2.75)` still truncates.

## Log
- 2026-08-23 — resolved, commit PENDING-COMMIT.
