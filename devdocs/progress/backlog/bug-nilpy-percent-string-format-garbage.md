---
summary: "nilpy: printf-style % on a string yields garbage instead of formatting (silent wrong output)"
type: bug
track: N
prio: 60
---

# nilpy: `"%.2f" % value` produces garbage

- **Type:** bug (Nil-Python frontend, lowering) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Severity: silent wrong output

Compiles clean and runs, printing a wrong value with no diagnostic. That is the
worst failure class we have — a program that looks like it works.

## Repro

```python
print("A", "%.2f" % 3.14159)      # CPython: A 3.14   -> pxx: A 0.0
print("B", "%d" % 42)             # CPython: B 42     -> pxx: B 39
print("C", "%s" % "str")          # CPython: C str    -> pxx: C 8568
print("D", "%.1f/%.1f" % (1.5, 2.5))  # CPython: D 1.5/2.5 -> pxx: D 5010409
```

The results look like the numeric `mod` operator being applied to a string /
pointer value rather than string interpolation, i.e. `%` is not being recognized
as string formatting when the left operand is a str.

## Lane note (2026-07-26)

The multiplicative-expression loop that would need the `str % args` case lives in
the SHARED `compiler/parser.inc` (~line 11736 for `tkMod`; the neighbouring
`PyExprMode` string/list/bytes-repeat cases for `tkStar` are the precedent at
~11706-11721), not in Track N's own `pyparser.inc`. So the hook itself is a Track A
edit even though the semantics are nilpy's — needs the sole-A check, or file the
parser.inc hook as a Track A ticket and keep the formatting helper in pyparser.inc.

## Fix shape

Recognize `str % value` and `str % tuple` in the nilpy lowering and route to a
formatting helper (the `{}`-style path presumably already has one; f-string specs
are the neighbouring gap, [[feature-nilpy-fstring-format-spec]]). Failing to
support a conversion must be a compile error, never a wrong value.

## Gate

`make test-nilpy` green with a `.npy` case covering `%s %d %f %.Nf` and the tuple
form, diffed against CPython, + `--tier quick` + self-host byte-identical.

## Still live 2026-07-28 (287b1b34d)

```
print("%s" % "s")        CPython: s       pxx: 5207332
print("%d" % 42)         CPython: 42      pxx: 36
print("%.2f" % 3.14159)  CPython: 3.14    pxx: 0.0
```

The integer case is the tell: 42 comes back as **36**, which is `42 mod 6` —
`"%d"` is being read as a numeric operand (its digit content) and `%` as the
arithmetic modulo, exactly as the original report guessed. So the fix is at the
`%` lowering, not in a formatting helper: when the LEFT operand is a string, the
operator is interpolation, and only then does the right side become the argument
tuple.

Sibling surface worth doing in the same pass: `"{} {}".format(a, b)` errors with
"takes exactly one argument here; several placeholders are not implemented yet".
That one is at least LOUD, unlike this.
