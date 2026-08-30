---
track: P
prio: 45
type: bug
blocked-by: []
summary: "The parser types `w[i]` on a WideString as `tyChar`, because a string's element width is not a parse fact. 7c corrected the READ by taking the width from the ADDRESS node (which IRLowerAddress already tags `tyWideChar`), so `Ord(w[i])` is right — but every OTHER consumer of the index node still sees `tyChar`: `Write(w[i])` of a non-BMP unit prints its low byte, and `s + w[i]` appends one byte. The fix is to type the node, not to add an arm per consumer: `NodeIsWideCharVal` already keys on `tyWideChar`, so the existing `WrapWideCharToUTF8` path would make both correct for free."
status: done
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

## 2026-08-30 (frankwasm) — fixed at the one deciding site, and both workarounds removed

`pasparser_lval.inc` has a single arm that answers *"what kind is a string
index"*. It said `tyChar` unconditionally; it now asks the width. That is the
whole fix, and it made **nine positions** correct at once — because everything
downstream already handles a `tyWideChar`: `NodeIsWideCharVal` keys on exactly
that kind, and `WrapWideCharToUTF8` is already wired into `Write`, concat,
string arguments and string assignment. Nine positions, one line, through a
path that already existed and was already tested.

**The removals are what make this a fix rather than an addition.** 7c's
`strIsWide` in `IRLowerAddress` and its load-width arm in the `AN_INDEX` read
both existed *only because the AST node lied*. With the node telling the truth,
`IR_INDEX` and `IR_LOAD_MEM` take `ASTTk[node]` like every other node kind. Net
−30 lines in `ir.inc`; two mechanisms for one concept collapse to one, and the
survivor is the one that cannot disagree with itself.

### Found while removing them: the third widening of the same predicate

`test_widestring_lowering` **aborted**:

```
error: WideChar->string conversion: __pxxWideCharToUTF8 helper not loaded
```

That helper is pulled by a token pre-scan whose list has now grown three times:

1. `widechar(` — a **cast**, the only way to make such a value at the time.
2. the type **names**, when `var w: WideChar` turned out to be a second producer
   (that widening has its own paragraph in `pasparser_prog.inc`, including the
   note that it survived because every test that exercised the conversion
   happened to write the cast).
3. `widestring` / `unicodestring` — because **indexing** a UTF-16 string is a
   third producer, in a program that need never write the word `widechar`.

> **A needs-predicate enumerates the SYNTAX that produces a value, and every new
> producer silently invalidates it.**

This one fails *loud* — a build abort, not a wrong answer — which is the only
reason it was cheap to find. The same predicate shape elsewhere in the compiler
decides what gets linked, and there the failure mode is a link error rather than
a wrong value, so the class is self-announcing. That is worth knowing before
someone builds a needs-predicate whose failure is silent.

### Why `ASTStrElemTkOf` is forwarded rather than duplicated

`NodeIsWideCharVal` is in `pasparser_lval.inc`, included **before** `ir.inc`, so
the width function needed a forward in `frontend_forwards.inc`. Reimplementing
it in the parser was the alternative and was rejected: it resolves six entities
(symbol, record field, pointee, call result, concat, array element) and **every
one of those answers has been wrong at least once during this campaign**, so a
second copy would be a seventh place to get them wrong. The width is a
shared-substrate fact — the side of
`the-substrate-is-ast-and-ir-not-the-parser.md` that says *share the AST*.

### The test enumerates POSITIONS, not entities

`test_widestring_element_positions` is the 7c argument-gap lesson paid forward.
`test_widestring_lowering` enumerates the six **entities** that carry a width
and was structurally blind to arguments, because an argument is not an entity —
it is a **position**. So this file is derived from the positions an element
value can occupy: `Ord`, `Write`, concat, string argument, string assignment,
WideChar destination, comparison, element store, loop. Before the fix, only the
first was right.

Not an FPC oracle, and the header says exactly where FPC lands: it agrees on
`units=2`, on `Ord` (233) and on the comparison, and answers **one** byte
wherever a wide element reaches a byte string, because its conversion goes
through `DefaultSystemCodePage` and yields Latin-1 where pxx's `AnsiString` is
UTF-8. Measured, and quoted in the file.

**Gate:** `gate.sh quick` GREEN, self-host fixedpoint converged, all five
widestring/sysutils tests green.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
