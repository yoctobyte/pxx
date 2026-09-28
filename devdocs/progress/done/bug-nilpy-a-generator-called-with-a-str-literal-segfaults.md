---
track: N
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "A Nil Python generator called with a str LITERAL (`for x in gen('hi')`, `next(gen('hi'))`) segfaulted on every target. A parameter every call site passes a literal is inferred AnsiString, and PasGenArgNeedsStrTemp excluded Nil Python, so the literal went into the instance slot raw."
owner: ""
---

# A Nil Python generator called with a str literal segfaults

```python
def gen(s):
    yield s
for x in gen("hi"):      # segfault, every target
    print(x)
```

These all worked: `gen(t)` with a str variable, `gen("hi" + "")`, `gen(5)`,
`gen(None)` and a tuple. The boundary is the parameter's stored kind: 23
(AnsiString) for the literal call, and 22 (Variant, carried in a heap cell)
otherwise. This is the Nil Python twin of
bug-a-a-string-literal-passed-to-a-stackless-generator-is-stored-without-being-materialised.

## Fix

`PasGenArgNeedsStrTemp` no longer excludes Nil Python. `PyBuildGeneratorValue`
materialises the argument through an AnsiString temp in the same way, and now
takes its slot offsets from `GenArgSlotOff`, like the `for` desugar.

## Test

`test/test_nilpy_cross32_values.py` (the str-literal block): a row in `test-core`
and rows in the three cross targets. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.
