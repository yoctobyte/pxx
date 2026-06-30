# Narrowing ordinal typecast doesn't truncate in rvalue position

- **Type:** bug (codegen / typecast — correctness) — Track A
- **Status:** backlog
- **Severity:** high — silent wrong values; breaks byte/word masking,
  comparisons, and hashing that rely on `byte(x)` / `word(x)` wrapping.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Symptom

An explicit cast to a smaller ordinal type (`byte`, `word`, `cardinal`,
`shortint`, …) used as an **rvalue expression** does NOT mask/sign-extend to the
target width — it passes the full-width source value straight through. The
narrowing only happens when the result is *assigned to a variable* of that type.

```pascal
var i: integer;
begin
  i := 300;
  writeln(byte(i));          { prints 300 — want 44 (300 mod 256) }
  if byte(i) = 44 then ...   { false! byte(i) is 300 }

  i := -1;
  writeln(cardinal(i));      { prints 18446744073709551615 — want 4294967295 }

  i := 200;
  writeln(shortint(i));      { prints 200 — want -56 }
end.
```

## Isolation (stable v97)

| Expression / statement | expected | got |
| --- | --- | --- |
| `byte(i)` rvalue (i=300) | 44 | 300 |
| `by := byte(i)` then read `by` | 44 | 44 ✓ |
| `by := i` (plain assign to byte) | 44 | 44 ✓ |
| `word(i)` rvalue (i=70000) | 4464 | 70000 |
| `cardinal(i)` rvalue (i=-1) | 4294967295 | 18446744073709551615 |
| `shortint(i)` rvalue (i=200) | -56 | 200 |
| `byte(i) and $FF` (i=300) | 44 | 44 (the `and` masks, not the cast) |
| `byte(i) mod 256` | 44 | 44 (the `mod` truncates) |

So assignment narrowing works; the **cast operator itself** is a no-op on value
width. Only operations that inherently truncate (`and`, `mod`) accidentally
yield the right answer.

## Likely cause

The rvalue lowering for a narrowing ordinal typecast changes the static type but
emits no mask (for unsigned narrow) / no sign-extend-from-width (for signed
narrow) of the value — unlike the assignment path, which narrows on store. The
cast should emit the same width-conversion the store does: zero-extend after
masking to `8*size` bits for unsigned targets, sign-extend from the target width
for signed targets.

## Acceptance

- `byte(300) = 44`, `word(70000) = 4464`, `cardinal(-1) = 4294967295`,
  `shortint(200) = -56` as rvalues (writeln, comparison, arithmetic).
- Widening casts and same-width casts unchanged; cross targets consistent.
- Regression test (`test/test_narrowing_typecast_rvalue.pas`) wired into
  `make test`; self-host stays byte-identical.
