---
track: P
prio: 45
type: bug
blocked-by: []
summary: "The parser types `w[i]` on a WideString as `tyChar`, because a string's element width is not a parse fact. 7c corrected the READ by taking the width from the ADDRESS node (which IRLowerAddress already tags `tyWideChar`), so `Ord(w[i])` is right — but every OTHER consumer of the index node still sees `tyChar`: `Write(w[i])` of a non-BMP unit prints its low byte, and `s + w[i]` appends one byte. The fix is to type the node, not to add an arm per consumer: `NodeIsWideCharVal` already keys on `tyWideChar`, so the existing `WrapWideCharToUTF8` path would make both correct for free."
status: working
owner: frankwasm
---

# A wide string's element is typed `tyChar`, so only the `Ord` read of it is correct

- **Type:** bug — **Track P** (`pasparser_lval.inc` / wherever an index node's
  `ASTTk` is set), with an A-side consequence in `ir.inc`.
- **Found by:** the 7c lowering (`feature-unicodestring-model`), from the first
  program that put a non-BMP value in a WideString.

## The shape

`IRLowerAddress` computes both halves of a wide string index correctly:

```pascal
elemSize := 2;
tk := tyWideChar;
```

...and then the `IRAppend(IR_INDEX, ...)` one screen below takes `ASTTk[node]`,
not that local `tk`. So the **stride was right and the element type was
dropped**. 7c added `strIsWide` to carry it to the address node, and a matching
arm in the `AN_INDEX` read to load two bytes — that fixed `Ord(w[i])`, which
answered 61 (the low byte of `$D83D`) where FPC says 55357.

**It reads as correct on every ASCII string**, because a BMP code unit's low
byte IS the character on little-endian. That is why it survived 6a–6d.

## What is still wrong

Everything downstream of the index node that reads `ASTTk` rather than the
address node:

| shape | today | should be |
| --- | --- | --- |
| `Ord(w[i])` | correct (7c) | — |
| `Write(w[i])` | the unit's low byte | the unit's UTF-8 encoding |
| `s := s + w[i]` | one byte appended | the unit's UTF-8 encoding |
| `w[i] := c` | not investigated | a two-byte store |

## Why the fix is one line in the parser, not three arms in `ir.inc`

`NodeIsWideCharVal` (pasparser_lval.inc) already answers True for
`IntToTypeKind(ASTTk[n]) = tyWideChar`, and `WrapWideCharToUTF8` already wraps
such a node into `__pxxWideCharToUTF8(...)` — that is how `Write(WideChar(66))`
and `s + WideChar(233)` are already correct. **Typing the index node
`tyWideChar` routes `w[i]` into machinery that exists and is tested.** Adding a
per-consumer arm in `ir.inc` instead would be the second path that stays broken
(`normalise-dont-special-case.md`).

The catch, and why this is its own ticket rather than part of 7c: the retype
ripples through every consumer of an index node — store, compare, `Ord`,
`Write`, call argument — and each wants a test. It is a contained change with a
wide blast radius, which is exactly the kind that should not ride along inside
a larger commit.

## Repro

```pascal
program r;
{$define PXX_WIDE_PAYLOAD}
var w: WideString;
begin
  w := WideChar($D83D) + WideChar($DE00);
  writeln(Ord(w[1]));   { 55357 — correct since 7c }
  writeln(w[1]);        { prints one byte; should print the unit's UTF-8 }
end.
```

## Gate

Pascal frontend green + self-host byte-identical, plus
`test_widestring_lowering` and `test_widestring_surrogate_pair` still passing,
and a new case asserting `Write(w[i])` and `s + w[i]`.
