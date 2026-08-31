---
track: N
prio: 55
type: feature
blocked-by: []
---

# `"{name} is {age}".format(name=..., age=...)` — named fields not supported

Found by proactive CPython-diff sweeping. Positional `.format()` already
works (`"{} {}".format(a, b)`, `"{0} {1} {0}".format(a, b)` — see
`pystr_format`/`pystr_format2` and `PyFormatApply` in
`compiler/builtin/pylib.pas`), but a NAMED field matched against a keyword
argument does not:

```python
print("{name} is {age}".format(name="Bob", age=30))
```
CPython: `Bob is 30`. pxx: `error: undefined variable (name)` — the `.format`
call-argument parser (`wantArgs = -6` in `compiler/pyparser.inc`'s
`PyParseStrMethod`) only accepts POSITIONAL expression arguments via
`ParseArgExpr`, so `name="Bob"` is read as a bare expression starting with the
identifier `name`, which resolves to nothing.

## Fix direction

Two independent pieces, both needed:
1. **Parser**: the `.format(...)` argument-parsing branch needs to accept
   `key=value` pairs (not just positional expressions) — likely threading
   them into a `TPyDict` of name→value built at the call site, the same shape
   `**kwargs` collection elsewhere in this frontend already uses.
2. **Runtime**: `PyFormatApply` (`compiler/builtin/pylib.pas`) currently
   substitutes purely by POSITIONAL index (`{}`/`{0}`/`{1}`). It needs a third
   mode: given a field's NAME (not a digit), look it up in the keyword dict
   instead of the positional args.

Not attempted this pass — a real engine change to the format-substitution
core plus new call-argument parsing, more scope than a quick patch; filed
precisely at the end of an extended CPython-diff sweep rather than rushed.

## Gate

A `.npy` case mixing positional and named `.format()` fields (CPython allows
both in the same call), diffed against CPython, gated in `test-nilpy` +
`--tier quick` + self-host byte-identical.
