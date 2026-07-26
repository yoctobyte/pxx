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

## Fix shape

Recognize `str % value` and `str % tuple` in the nilpy lowering and route to a
formatting helper (the `{}`-style path presumably already has one; f-string specs
are the neighbouring gap, [[feature-nilpy-fstring-format-spec]]). Failing to
support a conversion must be a compile error, never a wrong value.

## Gate

`make test-nilpy` green with a `.npy` case covering `%s %d %f %.Nf` and the tuple
form, diffed against CPython, + `--tier quick` + self-host byte-identical.
