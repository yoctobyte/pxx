---
track: N
prio: 45
type: bug
summary: "`@overload` from typing is refused with `unsupported decorator (only @dataclass)`. The last of the typing names that has a RUN-TIME form; TypeVar/NewType/cast/Generic/Protocol all landed under bug-n-typevar-call-is-an-undefined-variable. Its answer is a different shape from theirs — the decorated def is a STUB CPython throws away, so this is about skipping a definition, not about producing a value."
status: done
owner: agent-AN
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

## Resolution

Dropped, header and body — the answer the ticket predicted, at more sites than
it predicted.

### It really was three sites, and the third is why the first two were not enough

The ticket named two decorator branches and flagged the pre-passes as
"measure before choosing". Measured, and they were the load-bearing part:

1. **module-level decorator branch** — ×2, actually, the unit loop AND the
   program loop, which the ticket counted as one.
2. **class-body decorator branch**.
3. **the PRE-PASSES.** `PyRegisterDefShells` registers a bodyless proc from the
   HEADER before any body is parsed, and `PyRegisterClassMembers` does the same
   for methods. So with only 1 and 2 done, the stub was skipped in the body and
   still registered from its header — the implementation's own registration lost
   to it, and `g(1)` failed with **"by-reference argument must be a variable"**,
   pointing at the CALL rather than at the stub that mis-registered it. Exactly
   the frontend's recurring shape: one concept, independent sites, and fixing
   the visible ones leaves a stranger symptom than before.

`PyDefAtIsOverloadStub(i)` is the shared token-level test the pre-passes use;
`PyEatOverloadDecorator` is the cursor-level one the three parse branches use.

### The open question resolved itself

The ticket asked what a module of ONLY stubs should do, and whether that needed
a Track U ticket. It does not: **CPython does not accept-and-run such a program
either** — calling an overload-only function raises `NotImplementedError`, and
its message says outright that an implementation should always follow. pxx
refuses it at compile time (`undefined variable`), which is earlier and louder.
Nothing that works on CPython breaks here, so it is inside the
upward-compatibility rule. Recorded in `nilpy-semantics-divergences.md` with the
one honest criticism: our message names the call, not the missing
implementation.

### One adjacent fix it forced

`@typing.overload` is an ordinary spelling, and it needs `import typing` to
parse — but only the FROM-import form was consumed-and-dropped; the plain form
died with *"no unit named typing"*. `typing` added to both plain-import skip
lists (there are two, same as the decorator branches). Deliberately narrow: the
other consumed-only roots are NOT widened, because `import collections` then
`collections.Counter(...)` is an ordinary pylib symbol that must keep resolving.

### Verified against the CPython oracle

`test/test_nilpy_overload_decorator.npy` — **byte-identical to CPython** —
covers: a one-line stub body and an INDENTED one; `@overload` and
`@typing.overload`; two stubs stacked before one implementation; a stub with
defaults and keyword-only params (the header scan balances brackets so a colon
inside an annotation cannot end it early); stub METHODS; and `@staticmethod` /
`@property` in the same class body, which must be unaffected.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary). Parser only, no frozen builtin, so no re-pin.

With this, every typing name that has a run-time form works:
`TypeVar`, `NewType`, `cast`, `Generic`/`Protocol` as bases
([[bug-n-typevar-call-is-an-undefined-variable]]) and now `@overload`.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
