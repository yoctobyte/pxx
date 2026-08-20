---
track: P
prio: 70
type: bug
blocked-by: []
summary: "`a := 'abcdefgh'` on an `array[0..7] of Char` stores ONE byte — the low byte of the literal's string handle — into a[0] and leaves the rest untouched. Silent. The other direction is silent too: `s := a` yields the empty string, `a = 'abcdefgh'` is False, `a + '!'` and `Write(a)` print one garbage character. Only array-to-array copy works. FPC treats a static Char array as string-compatible both ways."
status: done
owner: frank1-ACP
---

# A static `array of Char` is not string-compatible in either direction

- **Track P** (Pascal frontend: the AN_ASSIGN arm chain in `ir.inc`, string-context
  typing in `parser.inc`).
- Found 2026-08-20 by an FPC differential probe over strings.
- Pascal-side sibling of
  [[bug-c-a-string-literal-row-of-a-2d-char-array-stores-its-address]], which was
  the same mistake — a string literal reaching a `char` slot as its ADDRESS — on
  the C side, fixed 2026-08-16.

## Measured

```pascal
type TA8 = array[0..7] of Char;
var a: TA8; s: string;
```

| expression | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `a := 'abcdefgh'` then bytes | `97 98 99 100 101 102 103 104` | **`157 0 0 0 0 0 0 0`** |
| `a := 'abc'` then bytes | `97 98 99 0 0 0 0 0` | **`197 0 0 0 0 0 0 0`** |
| `s := a` | `abcdefgh` (8) | **`` (0)** |
| `a = 'abcdefgh'` | TRUE | **FALSE** |
| `a + '!'` | `abcdefgh!` | **one garbage char + `!`** |
| `Write(a)` | `abcdefgh` | **one garbage char** |
| `b := a` (array to array) | copies | copies — the one that works |
| `const CA: TA8 = 'abcdefgh'` | compiles | **`error: unexpected token`** — loud |

The leading byte varies run to run: it is the low byte of the literal's string
handle, so the store is the scalar path writing a pointer into a `Char` slot.
That is exactly the C-side bug's shape.

## Why it survived

An `array[0..N] of Char` symbol carries its arrayness on the SYMBOL
(`Syms[i].IsArray`, `ArrLen`), while the AST node for `a` is typed `tyChar`.
Every string context therefore sees a plain Char and does something defensible
with it. Nothing in the corpus exercises it, because the RTL had already routed
around the gap — `lib/rtl/palparallel.pas` declares

```pascal
PROC_STAT_PATH: array[0..10] of Char =
  ('/', 'p', 'r', 'o', 'c', '/', 's', 't', 'a', 't', #0);
```

one character at a time, which is a workaround for the last row of the table
above, written without a ticket.

## Shape of the fix

One concept — a static Char array IS a string of its own length — reachable
through five shapes. Per `normalise-dont-special-case.md` this wants a single
conversion at the boundary, not five special cases:

- **string -> char array** (`a := s`): a padded copy — `Min(Length(s), cap)`
  characters, zero fill to `cap`. This is the arm that is actively wrong rather
  than merely missing, so it goes first.
- **char array -> string** (`s := a`, comparison, concat, `Write`): a
  conversion that stops at the first #0 within `cap` and otherwise takes all
  `cap` characters. Measured against FPC rather than assumed: an
  `array[0..7] of Char` holding `'ABC'#0'EFGH'` converts to the THREE-character
  `'ABC'`, while the same array holding eight non-NUL characters converts to all
  eight. So it is PCharToString with a hard length bound, not a memcpy.
- **typed const** (`CA: TA8 = 'literal'`): the initializer path, which is loud
  today and so is the least urgent.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, and a test pinning
every row of the table above against FPC 3.2.2.

## Resolution — 2026-08-20

Two builtins carry the conversion (`compiler/builtin/builtin.pas`):
`__pxxCharArrayToStr(p, cap)` and `__pxxStrToCharArray(p, cap, s)`. Two
AST-level wrappers in `parser.inc` — `WrapCharArrayToStringExpr` and
`WrapStringToCharArrayStmt`, alongside the `WrapPCharToString` /
`WrapCharToStringExpr` pair they are modelled on — build the calls, and
`ASTCharArrayCap` is the single predicate ("is this node a STATIC Char array,
and how long?").

Three call sites, which are the three places a string is wanted:

| site | what it fixes |
| --- | --- |
| `AN_ASSIGN` (both directions) | `a := s` and `s := a` |
| `AN_BINOP` (`+`, and the six comparisons) | `a = 'abc'`, `a + '!'` |
| `AN_WRITE` / `AN_WRITELN` | `Write(a)` |

Two details worth keeping:

- **A one-character literal is spelled `tyChar`, not a string.** `b := 'q'` on
  an `array[1..3] of Char` still pads — FPC leaves `113 0 0` — so the assign arm
  promotes a Char RHS through `WrapCharToStringExpr` and takes the same path.
- **`builtin.pas` is pulled in by a TOKEN PAIR.** The unit-selection pre-pass is
  token-level, so the trigger is `of` immediately followed by `char`. Keying on
  `char` alone would drag `builtin.pas` into nearly every program; the pair
  fires for `array[0..7] of Char` and `array of Char` and nothing else.

Not done here, and deliberately: the typed-const form (`CA: TA8 = 'literal'`),
which is a compile error rather than a wrong value, and passing a Char array to
a `string` PARAMETER. Both are the initializer/argument paths rather than these
three, and both are loud.

`test/test_char_array_is_a_string.pas` — 77 assertions plus the `Write` line,
all FPC 3.2.2's, including the two forms that must NOT be dragged into the
conversion (array-to-array copy and element access).

## Log
- 2026-08-20 — resolved, commit a22177c73.

## Follow-up, same day — the argument and Length sites

The first landing named two things left out. One of them, the `string`
PARAMETER, turned out to be the same three-line change and is now done, along
with `Length`:

| site | before | now |
| --- | --- | --- |
| `Take(a)` where `Take(const q: string)` | one garbage character | `hi` |
| `Length(a)` on an `array[0..7] of Char` | **1** | 8 |
| `Pos('i', a)` | 0 | 2 |
| `Alias(a)` where `Alias(var q: TA8)` | aliases | aliases — unchanged |

`Length` was the sharper of the two: the fold `Length(c) = 1 for a Char` fires on
`ASTTk[valNode] = tyChar`, and a Char ARRAY's node is typed tyChar too, so
`Length(a)` had answered 1 for as long as the fold has existed. `Length` on an
`array[0..3] of Integer` was right all along — only the Char element type walked
into the Char arm. Guarded with `ASTCharArrayCap(valNode) < 0`.

**The argument case is worth recording for the trap it hid.** Putting the
conversion inside `IRLowerCallArg` — the parameter-aware lowering that every
call funnels through, and by every argument the obvious normalisation point —
looked correct and did nothing. The IR dump showed why:

```
4: call a=141 b=1 ival=0 tk=23      <- __pxxCharArrayToStr, AnsiString result
5: arg  a=4   b=-1     ival=0 tk=3  <- ...tagged tyChar
```

The argument LOOP builds its `IR_ARG` from `ASTTk[ASTLeft[item]]`, the original
node's type, so converting the value inside the callee-side helper produced the
right string and then labelled it a Char: the same wrong answer by a different
route. The node itself has to change, which is precisely what the NilPy
char-to-pystr wrap sitting in that loop already says in its own comment. The
conversion is now `IRCoerceCharArrayArg`, called from the six argument loops
next to it.

Still out, and still loud rather than silent: the typed-const form
(`CA: TA8 = 'literal'`).

The test grows to 86 assertions and adds the `var` parameter, which must NOT
convert.
