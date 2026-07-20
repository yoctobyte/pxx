---
prio: 45  # auto — Ord()/Chr() in a const or case label is everyday Pascal; every keyboard-handling program hits it
track: P
---

# `Ord()` / `Chr()` / `Length()` / `Succ()` are not folded in constant expressions

- **Type:** compat — **Track P** (Pascal frontend; constant-expression
  evaluation in the shared `parser.inc`, so it lands under Track A's gate).
- **Status:** backlog — filed 2026-07-20.
- **Found by:** Track E, building `examples/mandelbrot/mandelbrot_gui.pas`
  ([[feature-demo-mandelbrot-gui-threaded]]) — `case KeyCode of Ord('q'): ...`
  is the natural way to write a key handler and it does not compile.

## Symptom

```pascal
program Ck;
const K = Ord('q');
begin writeln(K); end.
```
```
pascal26:2: error: not a constant ()
  near: program Ck  const K  >>> Ord  q
```

Same in a `case` label (`case KeyCode of Ord('q'): ...` → `case label must be
constant`), which is where it actually bites.

## Survey (what folds today)

| expression | folded? |
| --- | --- |
| `1 shl 4` | yes |
| `High(Integer)` | yes |
| `Ord('q')` | **no** |
| `Chr(65)` | **no** |
| `Length('abc')` | **no** |
| `Succ(5)` | **no** |

So arithmetic/bit operators and `High` already go through the const evaluator;
the ordinal/character builtins were never wired into it. FPC and Delphi fold all
of the above — `Ord` and `Chr` in particular are ubiquitous in key handlers,
lookup tables and `set of Char` construction.

`Pred` was not tested but is presumably in the same bucket; `Low` presumably
works like `High`. Worth sweeping the whole builtin list while in there rather
than adding them one at a time.

## Secondary: the diagnostic dumps internal lexer state

The failing compile prints, before the error:
```
  Token 12: Line = 3 Kind = 1 SOffset = 22 SLen = 1
```
Internal token debugging leaking to stderr on this path. Should not ship;
worth removing while fixing, or filing separately if it is a broader debug-output
leak.

## Workaround in the meantime

Numeric literals with a comment (`113,  { 'q' }`), which is what the demo does.

## Acceptance

- All six rows of the table above compile and produce the right value.
- The same expressions work as `case` labels, array bounds, and subrange bounds.
- A conformance test (`test/test_const_expr_builtins.pas`) covering
  `Ord`/`Chr`/`Length`/`Succ`/`Pred`/`Low`/`High` in a `const`, a `case` label
  and an array-bound position.
- No stray token dump on the failing path.
- Gate: `make test` + self-host byte-identical (shared `parser.inc`).

## Links
[[feature-demo-mandelbrot-gui-threaded]] (where it turned up) ·
`compiler/parser.inc` (constant-expression evaluation).

## Log
- 2026-07-20 — Filed from Track E with the folding survey above.
