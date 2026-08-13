---
track: N
prio: 60
type: bug
blocked-by: []
summary: "Python's adjacent-string-literal concatenation (`\"a\" \"b\"` is `\"ab\"`) works at an assignment and in a pylib call, but yields an EMPTY string as an argument to a user def, an unterminated/garbage string inside a list literal, and a PARSE ERROR inside a dict literal. Two of those are silent wrong values; the list one reads far past the string. Found compiling html5lib/constants.py, where the idiom is everywhere."
---

# Adjacent string literals concatenate in some positions and corrupt in others

- **Type:** bug (silent wrong value + an unbounded over-read) — **Track N**
- **Found:** 2026-08-13, compiling
  `html5lib/constants.py` for [[feature-nilpy-thirdparty-libraries-as-targets]].
  That file is a dict of error messages written in exactly this idiom, so it is
  the first thing html5lib hits after `six`.

## The idiom

CPython concatenates adjacent string literals at COMPILE time — it is how a long
message is wrapped across lines:

```python
"cant-convert-numeric-entity":
    "Numeric entity couldn't be converted to character "
    "(codepoint U+%(charAsInt)08x).",
```

## Measured, per position (CPython on the left, pxx on the right)

| shape | CPython | pxx |
| --- | --- | --- |
| `x = "p" "q"` | `pq` | `pq` ✔ |
| `print("p" "q")` | `pq` | `pq` ✔ |
| `print(("p" "q"))` | `pq` | `pq` ✔ |
| `print(len("p" "q"))` | `2` | `2` ✔ |
| `f("p" "q")` where `def f(x): return x` | `pq` | **empty string** (`len` 0) |
| `["p" "q"]` | `['pq']` | element has **len 0**, and printing the list dumps **kilobytes of the data segment** |
| `{"k": "aa " "bb"}` | `aa bb` | **compile error**: `Expected: close brace, but got: bb` |

So four positions are right, three are wrong, and two of the three are SILENT.
The list case is the worst: the element is an unterminated string whose length
comes from somewhere else entirely, so `print(xs)` walks the data segment (RTTI
tables, class names, pylib method names — all observed in the output).

## Where to look

The working positions and the broken ones differ by WHICH parse the second
literal reaches, which is the recurring NilPy shape: one construct, several
paths, and the ones nobody swept stay broken
(`devdocs/dev/normalise-dont-special-case.md`). The fix is presumably to fold
adjacent literals **in the string-literal factor itself** — one place, every
position — rather than at whichever site currently handles it.

Note the working `print("p" "q")` is a pylib callee and the broken `f("p" "q")`
is a user def: the two take different argument-parse routes, exactly as the
keyword-argument work in
[[bug-nilpy-dict-update-keyword-args-segfault-on-two-keywords]] found.

## Gate

A `.npy` diffed against CPython covering all seven rows above, plus
`html5lib/constants.py` getting past line 20.

## FIXED 2026-08-13 — and the root cause is Track A, not the adjacency idiom

All seven rows now match CPython. The adjacency idiom was the *messenger*: the
NilPy lexer already splices ` + ` between adjacent literals, so `"a" "b"` and
`"a" + "b"` are the same construct by the time the parser sees them — and the
explicit `+` form was broken in exactly the same positions, **in plain Pascal
too**:

```pascal
procedure Show(const v: Variant); ...
Show('pq');          { [pq] }
Show('p' + 'q');     { []   <- silent, and this is ordinary Pascal }
s := 'p' + 'q'; Show(s);  { [pq] }
```

### The cause: IRC described what the AST expected, not what was produced

IR folds a literal-concat into ONE interned literal and deliberately tags it
**tyString**, not tyAnsiString — the comment at that fold explains why: a static
literal pointer treated as a heap handle gets released at scope exit and
crashes. But the variant store took its source kind from the **AST** node, which
is tyAnsiString, so it boxed the folded literal as a managed string and read a
length word that is not there. Hence empty (`len` 0), and hence the list-literal
print walking the data segment: the payload is a raw `.data` address with no
header.

One line in `ir.inc`'s AN_ASSIGN variant-target arm: when the lowered value IS a
folded `IR_CONST_STR` and the AST said tyAnsiString, take the kind from the
value. That puts it on the byte-for-byte path a one-line literal already takes —
the known-good form — rather than inventing a third.

**The general rule worth carrying:** a store that is told a KIND separately from
its VALUE must take the kind from the value once anything in between can rewrite
it. Constant folding is exactly such a rewrite.

### The dict-literal parse error was a second, unrelated bug

`{"k": "aa "\n      "bb"}` failed to parse because the lexer's adjacency scan
counted `(` and `[` as "still on the same logical line" and **not `{`**. A dict
or set display continues a line exactly as the other two do. One character class
added in `pylexer.inc`.

### Tests

- `test/test_nilpy_adjacent_string_literals.npy` + `.expected` (CPython), all
  seven positions plus the runtime-concat control, in `test-nilpy`.
- `test/test_variant_literal_concat_arg.pas` in `make test` — the Track A half,
  because the bug is reachable without NilPy at all.

`html5lib/constants.py` now compiles past line 20 (where this stopped it) to
line 305, where it meets `frozenset` — an ordinary missing builtin, filed
separately if it blocks.

Gate: `make compiler/pascal26` fixedpoint + `gate.sh quick` GREEN + the full
`make test-nilpy` family sweep (this moves a variant-boxing path, which is what
the sweep exists for).
