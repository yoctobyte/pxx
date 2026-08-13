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
