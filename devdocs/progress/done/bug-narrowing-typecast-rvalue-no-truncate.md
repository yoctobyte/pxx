# Narrowing ordinal typecast doesn't truncate in rvalue position

- **Type:** bug (codegen / typecast — correctness) — Track A
- **Status:** done — fixed 2026-07-01, pin v129
- **Severity:** high — silent wrong values; breaks byte/word masking,
  comparisons, and hashing that rely on `byte(x)` / `word(x)` wrapping.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Resolution

Two distinct bugs, both real, layered on top of each other:

1. **The width-conversion itself was missing** (`ir.inc`'s `AN_PTR_CAST`
   fallback, the `else IRTk[Result] := ASTTk[node];` branch) — a narrowing
   cast just re-tagged the IR node's type without emitting any value
   conversion. Fixed by emitting an explicit mask (unsigned targets) or
   mask-then-sign-extend via the standard two's-complement identity
   `(v xor signbit) - signbit` (signed targets) whenever the cast target is
   an ordinal narrower than 64 bits (excluding `Boolean`/`Char`/`Pointer`,
   which keep their existing behavior). This alone fixed `word`/`cardinal`/
   `shortint` completely.

2. **`byte(x)` specifically never reached that fix at all.** `byte` lexes as
   `tkInteger_T` — the *same* token as `integer` (a pre-existing, previously
   undocumented-outside-`asmenc.inc` lexer quirk) — so `byte(i)` was parsed
   by the `tkInteger_T`/`tkLongWord_T` branch (`parser.inc:3695`), which
   unconditionally built an `AN_CALL` "value-pun" node hardcoded to
   `tyInteger`, discarding that the source text said "byte". That branch's
   codegen (`ir_codegen.inc`) is a pure bit-for-bit passthrough — exactly why
   `byte(i)` behaved identically to a no-op `Integer(i)` reinterpret,
   completely bypassing fix #1. `longword` has the identical problem (shares
   `tkLongWord_T` with `longint`) and was fixed the same way, though it
   wasn't in the original ticket's repro. Fix: disambiguate on the token's
   source text (`CaseEqual(CurTok.SVal, 'byte'/'longword')`, the same
   technique `SizeOf`'s type-name parsing already uses) and route those two
   specifically to a proper `AN_PTR_CAST` node instead — `integer`/`longint`
   keep their exact existing passthrough behavior, zero regression risk
   there.

   Found via a dedicated investigation subagent after direct testing showed
   `word`/`cardinal`/`shortint` fixed correctly as rvalues but `byte`
   stubbornly wasn't, and `-S` disassembly of `writeln(byte(i))` showed a
   plain `movsxd rax, [i]` with no masking instructions at all — the tell
   that the cast node itself was never reaching the new logic.

Regression test `test/test_narrowing_typecast_rvalue.pas` covers `byte`,
`word`, `cardinal`, `longword`, `shortint`, the `=` comparison case, the
already-working `and`/`mod` manual-workaround cases (unchanged), `integer`
staying a pure passthrough, and no-op cases (values already in range).
Verified identical output on i386/arm32/aarch64 via cross-compile + QEMU, not
just x86-64 native. Self-host byte-identical (one generation of lag on
landing — expected, the compiler's own source uses these casts internally;
gen2==gen3 confirmed), full `make test` green, `make stabilize` green.

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
