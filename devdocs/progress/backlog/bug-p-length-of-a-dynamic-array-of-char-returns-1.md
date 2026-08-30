---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`Length(w)` on a dynamic `array of Char` returns 1 where FPC returns 6, silently. `High(w)` on the SAME variable returns 5 (correct), the elements store and read correctly, and `array of WideChar` / `array of Byte` are both right — so it is Length alone, and only for the Char element type. A loop written `for i := 0 to Length(w)-1` runs zero times on data that is there."
status: new
owner: ""
---

# `Length` of a dynamic `array of Char` returns 1

- **Type:** bug — **Track P** (Pascal lowering of `Length` in `compiler/ir.inc`).
- **Found:** 2026-08-30 by frankwasm, while A/B-ing `Length` across shapes to
  prove the `feature-unicodestring-model` item-5 change was neutral. The
  neutrality held (pinned == new on every row); this row was wrong on **both**
  sides, so it predates that work entirely.

## Measured

```pascal
{$mode objfpc}{$H+}
var w: array of Char; d: array of WideChar; b: array of Byte; i: Integer;
begin
  SetLength(w, 6); SetLength(d, 3); SetLength(b, 6);
  for i := 0 to 5 do w[i] := Chr(65 + i);
  WriteLn('char  len=', Length(w), ' high=', High(w));
  WriteLn('wide  len=', Length(d));
  WriteLn('byte  len=', Length(b));
  WriteLn('elems=', w[0], w[5]);
end.
```

| line | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `char  len= high=` | `6` / `5` | **`1`** / `5` |
| `wide  len=` | `3` | `3` |
| `byte  len=` | `6` | `6` |
| `elems=` | `AF` | `AF` |

The shape of the failure is what makes it worth a ticket rather than a note:

- **The array is fine.** `High(w)` is 5 and `w[0]`/`w[5]` read back the bytes
  that were written, so the allocation, the element size and the indexing are
  all correct. Only the `Length` answer is wrong.
- **It is the ELEMENT TYPE, not dynamic-arrayness.** `array of WideChar` and
  `array of Byte`, allocated and measured identically in the same program, are
  both right. Swapping `Char` for either fixes it.
- **It is silent and it under-reports.** `for i := 0 to Length(w)-1` runs once
  instead of six times; `for i := 0 to High(w)` runs six times. Two spellings
  of the same loop over the same variable disagree, and neither errors.

## What has already been eliminated

- **`IRCoerceCharArrayArg` is NOT the cause.** It is the obvious suspect — it
  sits in the argument loop directly above the `tkLength` arm and exists to turn
  a Char array into a string — but it exits on `cpi < 0`, and `Length` is a
  special with `cpi = -Ord(tkLength)`, so it never runs for this call.
- **It is not the item-5 `shr 1`.** That is guarded on the argument being
  `tyAnsiString`, which a dynamic array is not, and pinned (which predates it)
  answers `1` too.

The remaining suspect, unverified: something on the `Length` path treats an
array whose element is `Char` as a managed string and reads its block header,
or converts it through the char-array-to-string wrapper, either of which would
yield a one-character answer. Confirm with `PXXDBG=a.ir:<proc>` before writing a
cause into this ticket — `devdocs/dev/root-cause-over-microfix.md`, and the
standing rule that every wrong root cause in this repo was a plausible story
nobody diffed against an oracle.

## Related, but not this

- [[bug-p-a-char-array-is-not-a-string-in-any-direction]] (done) is the STATIC
  `array[0..N] of Char` case, and it is about assignment/comparison/`Write`,
  not `Length`. This is the dynamic array, and only `Length`.
- [[refactor-p-the-char-array-is-not-a-string-rule-is-spelled-five-times]] is
  the standing five-copies refactor over the same rule. If that consolidation
  is done first, check whether this falls out of it — a sixth site spelling the
  rule slightly differently is exactly the failure mode that ticket names, and
  **that would make this a tickets-closed-per-change win rather than a
  microfix**. Prefer that order if both are open.

## Gate

`make compiler/pascal26` + the program above matching FPC on all four lines.
