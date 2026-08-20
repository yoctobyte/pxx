---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`Integer(x)` in rvalue position handed the operand's bit pattern through untruncated — `Integer(LongWord(4000000000))` answered 4000000000 where FPC says -294967296 — while `LongInt(x)`, the same cast spelled the other way, was correct. Silent wrong values in any 64-bit-to-32-bit or unsigned-to-signed reinterpret."
status: done
owner: frank1-ACP
---

# `Integer(x)` as an rvalue is a bit-pattern pun, not a cast

- **Track P** (Pascal frontend: the `tkInteger_T` cast arm in `parser.inc`).
- Found 2026-08-20 by an FPC differential probe over integer casts.
- Direct sequel to [[bug-narrowing-typecast-rvalue-no-truncate]] (2026-07-01),
  which fixed `byte`/`word`/`cardinal`/`longword`/`shortint` and said of this
  arm: *"integer/longint keep their exact existing passthrough behavior, zero
  regression risk there."*

## Repro

```pascal
var c: LongWord;
begin
  c := 4000000000;
  Writeln(Integer(c));    { FPC: -294967296   pxx: 4000000000 }
  Writeln(LongInt(c));    { FPC: -294967296   pxx: -294967296  }
end.
```

| context | before |
| --- | --- |
| `i := Integer(c)` (assigned) | correct — the 4-byte store truncates for free |
| `LongInt(c)` (rvalue) | correct |
| `Integer(c)` (rvalue) | **wrong** |
| `Integer(int64Value)` (rvalue) | **wrong** — full 64 bits pass through |

## Root cause — one concept, two spellings

Only `byte`, `integer` and `longword` are type TOKENS in `lexer.inc`
(`tkInteger_T` / `tkLongWord_T`); `longint`, `cardinal`, `int64` and the rest
are ordinary identifiers. So `LongInt(x)` took the generic identifier-typecast
path, which builds a real `AN_PTR_CAST` and gets the mask-and-sign-extend that
`ir.inc` has emitted since July. `Integer(x)` was caught by the token arm, which
builds the `AN_CALL` "value-pun" node — bit pattern in, bit pattern out.

The July fix routed `byte` and `longword` out of that arm by disambiguating on
the token's source text, and left `integer` behind on purpose. This is the exact
failure mode `devdocs/dev/normalise-dont-special-case.md` names: the second path
is the one that stays broken.

## Fix

The same disambiguation, one arm further: an `Integer(x)` whose operand is an
ordinal that can actually change value under the cast — wider than 4 bytes, or
4 bytes unsigned — builds an `AN_PTR_CAST` and reuses the existing narrowing
logic. An operand that cannot change value (a signed 32-bit-or-narrower ordinal,
`Char`, `Boolean`) keeps the pun, so the very common `Integer(someInteger)`
still emits no masking at all and `test_narrowing_typecast_rvalue`'s
`integer(i)` line is unchanged.

Note the self-host angle: `compiler.pas` casts `Int64` fields with
`Integer(...)` in several places, and FPC — which builds the bootstrap seed —
has always truncated them. So the pxx-built compiler and the FPC-built compiler
disagreed on those expressions until now; the fix removes a latent divergence
rather than introducing one. The fixedpoint takes one extra generation to
converge, as the July fix did, for the same reason.

## Test

`test/test_integer_cast_truncates_rvalue.pas` — 28 assertions: the unsigned-32
reinterpret in rvalue, assigned, folded, in-expression and compared positions;
`LongInt` as the control; 64-bit operands; the operands that must keep the pun;
and the five neighbours the July fix owns, re-asserted. All FPC 3.2.2's.

## Gate

`make compiler/pascal26` fixedpoint (converges in 2 rounds) + `tools/gate.sh quick`.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
