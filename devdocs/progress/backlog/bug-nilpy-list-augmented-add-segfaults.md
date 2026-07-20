---
track: N
prio: 55
type: bug
---

# NilPy: `xs += [2]` on a list SEGFAULTS

Found 2026-07-20 in the operator sweep.

```python
s = "ab"
s += "cd"
print(s)          # abcd   correct

xs = [1]
xs += [2]         # SEGFAULT — CPython extends, len 2
print(len(xs))
```

The string form is correct; only the list form crashes. `+=` lowers to
`xs = xs + [2]`, and `+` on two class pointers is not list concatenation — it
adds the pointers and the result is used as a TPyList.

## Shape

Python's `list + list` concatenates and `list += list` extends in place
(they differ: `+=` mutates, `+` does not, and that is observable through an
alias). Both want a pylib helper — `pylist_concat(a, b)` returning a new list,
and an `extend` method for the in-place form — dispatched from the binop on a
TPyList-typed operand, the way `in` now dispatches on the container's class.

Until then it should be a clean ERROR rather than a crash: getting the
dispatch wrong here is a segfault, which is the same trap the `in` dispatch
had (fixed in c49064af).

## uforth relevance

Zero `+= [` sites, but **`.extend(` appears 5 times**, which is the same
underlying operation and equally unimplemented. Sizing them together is
sensible.

## Gate

`test-nilpy` green with both the string and list forms diffed against
CPython + `--tier quick` + self-host byte-identical + `make fpc-check`.
