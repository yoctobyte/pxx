---
track: N
prio: 45
type: bug
summary: "`@overload` from typing is refused with `unsupported decorator (only @dataclass)`. The last of the typing names that has a RUN-TIME form; TypeVar/NewType/cast/Generic/Protocol all landed under bug-n-typevar-call-is-an-undefined-variable. Its answer is a different shape from theirs — the decorated def is a STUB CPython throws away, so this is about skipping a definition, not about producing a value."
---

# `@overload` is refused

- **Type:** bug (upward-compatibility violation) — **Track N**.
- **Split out of** [[bug-n-typevar-call-is-an-undefined-variable]], which closed
  the rest of the typing names. Filed rather than folded in because the answer is
  a different mechanism and touches sites that one did not.

## Reproduce

```python
from typing import overload
@overload
def f(x: int) -> int: ...
def f(x): return x
print(f(1))
```

```
error: Nil Python: unsupported decorator (only @dataclass)
```

## Why it is not the same fix as its siblings

`TypeVar`, `NewType` and `cast` are EXPRESSIONS — each has a value, and the fix
was to say what the value is. `Generic`/`Protocol` are bases, and the fix was to
erase them. `@overload` is neither: CPython registers the decorated function in
an overload registry and the **implementation def that follows replaces it**, so
the stub's body (`...` by convention) never runs. The honest lowering is
therefore to SKIP the decorated def entirely, which is a statement-level
operation the other four never needed.

## Sites — there are two, and they are separate parsers

Same shape as the class-attribute and augmented-assign matrices: one concept,
independent sites, and fixing one leaves the other wrong.

1. **module level** — the `tkAt` branch of the module loop, whose message is
   `unsupported decorator (only @dataclass)`.
2. **inside a class** — the `tkAt` branch in `PyParseClass`, whose message is
   `unsupported decorator inside class (only @property, @<name>.setter and
   @staticmethod)`. `@overload` on METHODS is at least as common as on
   functions.

And a third thing to check rather than assume: the class-member **pre-pass**
registers methods before the body is parsed, so skipping a stub in the body may
not be enough — the pre-pass may already have registered it, and two same-named
methods interact with overload-by-arg-type
(`PyPickOverloadByArgTypes`, [[project_nilpy_method_overloads_now_picked_by_arg_type]]:
declaration order is load-bearing there). Measure before choosing.

## The open question, if skipping turns out to be wrong

A module of ONLY `@overload` stubs and no implementation (the `.pyi`-shaped
pattern) would leave the name unbound. That is not valid at run time in CPython
either — calling such a stub raises `NotImplementedError` — so refusing it is
defensible, but it should be a decision, not an accident. If the measurement
says the two answers differ in observable behaviour, file a Track U
`decide-*` rather than picking.

## Gate

Both sites, module-level and method, compile and run; `@overload` stubs are
dropped and the implementation is what is called, diffed against CPython. Plus
`gate.sh quick` + self-host fixedpoint.
