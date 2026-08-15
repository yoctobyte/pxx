---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`Base.st(1, b=7)` — a STATIC method reached through the class name — fails with `undefined variable (b)`. The sibling instance shape `Base.meth(self, 1, opt=2)` was fixed; this one goes through GenMakeStaticMethodCall, a positional, index-driven builder shared with Pascal, and was deliberately left rather than forced."
---

# A static method called on the class takes no keyword arguments

- **Type:** bug (NilPy frontend / call lowering) — **Track N**, but the fix lands
  in the shared `parser.inc`, so it is A's ground for collision purposes.
- **Found 2026-08-15** while fixing
  [[bug-nilpy-an-unbound-method-call-takes-no-keyword-arguments]] — the same
  sweep, the one row that did not come with it.

## Repro

```python
class Base:
    @staticmethod
    def st(a, b=2):
        return str(a) + "-" + str(b)

print(Base.st(1, b=7))     # CPython: 1-7
```

```
error: undefined variable (b)
  near:  st    b >>>
```

`Base.st(1, 7)` (positional) works. `Base.st(1)` works. Only the keyword form
fails. CPython accepts all three.

## Why it was not fixed with its sibling

The INSTANCE shape `Base.meth(self, 1, opt=2)` had its own hand-rolled argument
loop in `parser.inc`, chain-driven, so it took `PyKwArgIndex` + `PyBindKwArgs`
— the same pair `PyMakeSuperCall` uses — as a direct addition.

The static shape goes through **`GenMakeStaticMethodCall`**, which is a
different animal:

- it is **index-driven** (`while ai <= ParamCount - 1`), assigning each parsed
  expression to parameter `ai` positionally, and
- it **interleaves `FillDefaultArgs`** into the same chain as it goes.

`PyBindKwArgs` reorders a finished chain and fills the holes itself, so bolting
it onto a loop that has already inserted default nodes mid-flight is not a
two-line change — the two mechanisms would both claim the holes. It is also
shared with the Pascal call paths (inert there: `PyKwArgIndex` returns 0 unless
`isNilPy`), so a mistake reaches further than NilPy.

## Suggested direction

Make the loop chain-driven when a keyword is seen: parse every argument into an
AN_ARG chain with its `PyKwArgIndex` binding, skip the interleaved
`FillDefaultArgs` for that call, and let `PyBindKwArgs` do the reordering and
hole-filling it already does for four other call sites. Keeping the existing
index-driven path for the no-keyword case makes the change additive and leaves
every Pascal call byte-identical.

Per `normalise-dont-special-case.md` the better end state is that ONE builder
serves every call spelling; five hand-rolled argument loops that each have to
learn about keywords separately is the actual defect, and this ticket is its
fifth instance.

## Gate

`Base.st(1, b=7)` answers `1-7`; positional and defaulted forms unchanged;
`gate.sh quick` + self-host byte-identical. Add the row to
`test/test_nilpy_unbound_method_keyword_args.npy`, which already covers the
instance shapes and is where a reader will look.
