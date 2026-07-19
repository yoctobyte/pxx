---
track: N
prio: 65
type: bug
---

# NilPy: a string local TRUNCATES at 255 characters, silently

```python
s = ""
i = 0
while i < 300:
    s = s + "x"
    i = i + 1
print(len(s))        # CPython 300   pxx 255
```

No error, no warning — the string just stops growing.

## Why

An inferred string local is `tyString`, the FROZEN (inline, length-prefixed)
string kind, whose maximum length is 255. Python strings are unbounded.

This is pre-existing — the token-scanning inference typed every string
expression `tyString` by construction — but it was made explicit rather than
accidental by the widening rule added in
[[feature-n-nilpy-ast-based-typing]]: a literal is born `tyString` and a
concat result `tyAnsiString`, and `PyWiden` deliberately resolves that pair to
`tyString`. That choice was made to preserve the storage model the RTL paths
are exercised against — picking `tyAnsiString` instead silently converted
every inferred string local to a managed one and corrupted the heap through
[[bug-a-str-boxed-into-variant-does-not-own-bytes]].

So the two are linked: **moving NilPy string locals to managed strings is
gated on that Track A boxing bug**, not merely on a one-line change to
PyWiden.

## Why it matters

uforth builds strings well past 255 characters — token buffers, assembled
output lines, error messages with embedded source. Truncation there is a
wrong ANSWER, not a diagnostic, and it will look like a Forth bug rather than
a compiler one.

## Shape

1. Fix [[bug-a-str-boxed-into-variant-does-not-own-bytes]] (Track A).
2. Flip `PyWiden`'s string pair to `tyAnsiString`, and make an inferred string
   local managed.
3. Re-run the whole `.npy` suite against CPython — `test_nilpy_str_param`
   segfaulted the first time this was tried, which is what the boxing fix has
   to make impossible.

Until then, the 255 limit should probably be an ERROR rather than silent
truncation, if that can be done cheaply — a wrong length is the worst of the
three outcomes.

## Gate

`test-nilpy` green with the 300-character case above diffed against CPython +
`--tier quick` + self-host byte-identical + `make fpc-check`.
