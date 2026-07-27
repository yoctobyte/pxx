---
summary: "nilpy: int(\"abc\") halts the program instead of raising a catchable ValueError"
type: bug
track: N
prio: 55
---

# nilpy: `int("abc")` halts instead of raising ValueError

- **Type:** bug (Nil-Python frontend / pylib) — **Track N**
- **Opened:** 2026-07-27, while landing the Exception-surface fix
  ([[bug-nilpy-rtl-exception-surface-shadowed]]). Pre-existing and unrelated to
  it — reproduces with no import at all.

## Repro

```python
try:
    x = int("notanumber")
except ValueError as e:
    print("caught:", e)
print("end")
```
pxx: `Runtime error: int() got a string that is not a number: notanumber`,
exit 219 — the `except` never runs and `end` is never printed.
CPython: `caught: invalid literal for int() with base 10: 'notanumber'` then `end`.

## Why it matters

This is the standard input-validation idiom, and songformatter uses it directly:

```python
try:
    if int(get("Misc", "Debug", "0")):
        print(*args)
except (ValueError, TypeError):
    pass
```

A halt where CPython recovers is a behaviour difference that turns a handled bad
setting into a dead program — worse than a compile error, because it only shows
up at run time on bad input.

## Notes

pylib's one-argument `int(str)` path halts, while the two-argument
`pyint_parse(s, base)` path documents that it raises ValueError. Making the
one-argument path raise the same way is likely the whole fix; check `float("x")`
at the same time, and match CPython's message text.

The tuple form `except (ValueError, TypeError):` in that snippet already parses —
checked 2026-07-27 — so the halt is the only thing standing between that idiom and
working code.
