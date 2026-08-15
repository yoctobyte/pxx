---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`Base.st(1, b=7)` — a STATIC method reached through the class name — fails with `undefined variable (b)`. The sibling instance shape `Base.meth(self, 1, opt=2)` was fixed; this one goes through GenMakeStaticMethodCall, a positional, index-driven builder shared with Pascal, and was deliberately left rather than forced."
status: done
owner: agent-acpn
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

## FIXED 2026-08-16 — the suggested direction, taken as written

`GenMakeStaticMethodCall` now reads `PyKwArgIndex(mpi, 1)` before each argument
and tags the `AN_ARG` with it. When the index is non-zero the loop switches to
chain discipline for the rest of the call — stop at `)`, no interleaved
`FillDefaultArgs` — and `PyBindKwArgs` does the reordering and hole-filling at
the end, over the chain that starts at the SELF argument. No offset is needed:
`PyKwArgIndex` returns the ABSOLUTE parameter index and self is parameter 0,
which is exactly how the instance path already hands its chain over.

The switch is **additive**: with no keyword the index is 0, the old
index-driven path runs unchanged, and `PyBindKwArgs` exits on its own first
test. `PyKwArgIndex` returns 0 unless `isNilPy`, so every Pascal call through
this shared builder is byte-identical — which the self-host fixedpoint confirms.

All seven spellings now match CPython, including the three the ticket did not
name:

```
Base.st(1)  Base.st(1, 7)  Base.st(1, 7, 8)      # already worked, kept
Base.st(1, b=7)        # a hole BEFORE the keyword's parameter
Base.st(1, c=9)        # a hole between them, filled from the default
Base.st(1, c=9, b=4)   # out of declaration order
Base.st(a=1, b=7)      # every argument by keyword
```

`@classmethod` is refused by this frontend for its own reason (the `cls`
receiver is not modelled), so `Base.cm(1, b=6)` is out of scope here and stays
with that ticket.

### The fifth instance is still the defect

This is the fifth hand-rolled argument loop to learn about keywords separately,
and the ticket says so. Nothing here changes that: one builder serving every
call spelling is still the right end state, and this fix makes the fifth loop
behave rather than removing it. Left as a note rather than filed as a sixth
ticket, because a refactor ticket nobody is ranked to take is worth less than
the sentence in the file that keeps saying it.

### Gate

`make compiler/pascal26` (self-host fixedpoint, byte-identical) + `tools/gate.sh
quick` GREEN. `test/test_nilpy_static_method_kwargs.npy` pins all seven
spellings plus the instance shape that shares the reorder helper.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
