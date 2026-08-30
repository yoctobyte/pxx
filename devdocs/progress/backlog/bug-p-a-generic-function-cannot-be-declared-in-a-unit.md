---
slug: bug-p-a-generic-function-cannot-be-declared-in-a-unit
track: P
prio: 40
type: bug
status: backlog
owner:
blocked-by: []
summary: "A `generic function F<T>(...)` is accepted at PROGRAM level and refused in a UNIT, in both sections: in the interface it is `expected generic class name`, in the implementation it is `unexpected token in a unit implementation section` at EOF. FPC accepts both and prints 9 for the repro. Small compat gap on its own, but it has a second cost: it makes pasparser_generic.inc:3370 -- the generic-FUNCTION copy of the body-extent counter -- UNREACHABLE, so the try/asm correction applied there alongside the measured method-side fix has no positive control and cannot get one until this is fixed. See bug-p-a-generic-method-body-with-try-loses-its-closing-end."
---

# A `generic function` cannot be declared in a unit

## Repro

```pascal
unit ugf; {$mode objfpc}
interface
function Caller: Integer;
implementation

generic function WrapTry<T>(a: T): T;
begin
  Result := a;
  try Result := a + a; finally Result := Result + 1; end;
end;

function Caller: Integer;
begin Result := specialize WrapTry<Integer>(4); end;

end.
```

| | result |
| --- | --- |
| FPC 3.2.2 | **9** |
| pxx, in the **implementation** section (above) | `unexpected token in a unit implementation section` |
| pxx, in the **interface** section | `expected generic class name` |
| pxx, same function at **program** level | **9** — works |

Both pxx failures are present on the pinned binary and on HEAD; this is not a
regression, and the `try` inside the body is incidental — a bodyless-simple
`generic function` in a unit fails the same way.

## The second cost, which is why this is filed rather than left

`compiler/pasparser_generic.inc` has two copies of the same body-extent counter.
The method-side one (`GenericMethodBodyEnd`) was measurably wrong — it counted
only `begin`/`case`, so `try` and `asm` ended a body one `end` early — and is
fixed with a positive control against the pinned binary.

The function-side copy at `:3370` had the identical defect and was corrected in
the same change. **It has no positive control and cannot be given one**, because
the only places a short generic-function body could be mis-terminated are a
unit's two sections, and this ticket is why neither is reachable. At program
level the pre-fix binary is already correct.

So the fix there is **unverified by construction**, which is recorded at the
line and in `test/test_generic_body_end_counting.pas`. Closing this ticket makes
that arm testable; the regression test should gain the arm at the same time.
