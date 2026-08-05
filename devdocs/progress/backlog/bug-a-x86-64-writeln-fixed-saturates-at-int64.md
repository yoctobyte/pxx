---
track: A
prio: 50
type: bug
summary: "x86-64 writeln(d:0:2) of a value past 2^63 prints 9223372036854775809.00 — the Int64 scaling saturates. FPC and every other pxx target print the right number"
---

# x86-64: `writeln(d:w:n)` saturates at Int64 for large values

- **Type:** bug — Track A (x86-64 native float emitter)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, comparing float output across targets while fixing
  `bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked`. **Pre-existing**
  in `pinned`.

## Repro

```pascal
var d: Double;
begin
  d := 1e20;                 writeln(d:0:2);
  d := 123456789012345678.0; writeln(d:0:2);
end.
```

| | `1e20:0:2` | `1.23456789012345678e17:0:2` |
| --- | --- | --- |
| FPC | `100000000000000000000.00` | `123456789012345680.00` |
| pxx aarch64 / i386 / arm32 | `100000000000000000000.00` | `123456789012345680.00` |
| **pxx x86-64** | **`9223372036854775809.00`** | `123456789012345680.00` |

`9223372036854775809` is 2^63 + 1 — the value saturated when scaled into an
Int64. Silent: it is a plausible-looking number, and only the first row is
affected because the second still fits.

## Why x86-64 is the odd one out

The cross targets route `writeln(d:w:n)` through the runtime helper
`PXXWriteFloatFixed`, which handles the large-magnitude case. x86-64 keeps a
hand-written native emitter (`EmitWriteFloatFixed` in `symtab.inc`) that scales
through Int64. This is the same "N copies of one formatter, and the copies
disagree" shape as
`bug-a-writeln-float-exponent-form-not-correctly-rounded`, which collapsed the
Sci formatters from four copies to one.

## Second, independent repro (2026-08-05)

`bug-a-x86-64-qword-to-double-assign-halves-above-2-63` was filed believing the
QWord→Double *conversion* halved. It does not — measured, `d := q` for
QWord max produces exactly FPC's double and compares equal to the literal
`18446744073709551616.0`. What it was actually seeing was THIS bug:

```pascal
q := 18446744073709551615; d := q;
writeln(d);        { pxx  1.8446744073709552E+019   = FPC }
writeln(d:0:1);    { pxx  9223372036854775809.0     FPC 18446744073709552000.0 }
```

Same double, two spellings, only the fixed one wrong. That ticket is closed as a
duplicate of this one. Worth knowing because it means this bug has already
cost one wrong diagnosis: it presents as an arithmetic fault somewhere else.

## Fix

Shim `EmitWriteFloatFixed` onto `PXXWriteFloatFixed`, as the Sci emitter now
is. **Blocked on one thing:** the runtime helper does not take a field WIDTH and
x86-64's emitter does, so shimming it today would silently drop padding — the
exact defect `bug-a-aarch64-float-field-width-ignored` describes on the other
targets. Add the width to the helper first, then this becomes a two-line shim
and the last hand-written float formatter goes away.
