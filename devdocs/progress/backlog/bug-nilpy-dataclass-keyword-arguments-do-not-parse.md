---
prio: 30
track: N
type: bug
blocked-by: []
---

# `@dataclass(order=True)` does not parse — the decorator takes no arguments

- **Type:** bug (loud: a parse error, not a wrong answer) — **Track N**
- **Found:** 2026-08-08, while gating
  [[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]] (it was going to be the
  natural third case in that test)
- **Owner:** —

```python
from dataclasses import dataclass

@dataclass(order=True)
class D:
    v: int

print(sorted([D(3), D(1)]))      # CPython: [D(v=1), D(v=3)]
```

```
pascal26:20: error: unexpected token
  near:     dataclass  >>> order
```

The bare `@dataclass` form works. Only the CALLED form is rejected, so the
decorator parser evidently accepts a bare name and no argument list.

## Scope

CPython's `dataclass()` takes `init`, `repr`, `eq`, `order`, `unsafe_hash`,
`frozen`, `match_args`, `kw_only`, `slots`, `weakref_slot`. They are not all
equally urgent — `order=True` and `frozen=True` are the ones real code reaches
for, and `eq=False` is the one that would interact with the newly-added
`__eq__` dispatch.

A useful first step is **parsing the argument list and honouring only what is
implementable, rejecting the rest explicitly by name.** Accepting and silently
ignoring `frozen=True` would be worse than the current parse error: the class
would look immutable and not be, which is a silent wrong answer where today's
failure is loud. `order=True` is the one with an obvious lowering now that
`sorted()` dispatches `__lt__` at run time — generate the comparison dunders
over the field tuple, exactly as CPython documents.

## Why prio 30

The error is loud and the workaround is one hand-written `__lt__`, which is
what the new `test_nilpy_sort_lt_dunder` uses. It blocks no corpus today.

## Gate

A `.npy` diffed against CPython covering `@dataclass(order=True)` sorting, and
an explicit named rejection for each option NOT implemented — with a test that
the rejection is a compile error rather than silence.

## 2026-08-12 — the argument list PARSES; non-default values refused by name

Took the ticket's own "useful first step": parse the list, honour what is
implementable, refuse the rest explicitly. `PyParseDataclassArgs` (pyparser.inc)
replaces the two copies of `if tkLParen then begin Next; Expect(tkRParen) end`.

What that buys, given every option has a documented CPython default and passing
an option its own default changes nothing:

- `@dataclass(eq=True, repr=True, init=True, order=False, frozen=False, ...)`
  now compiles and is exactly `@dataclass`, trailing comma included.
- `order=True` / `frozen=True` / any other non-default value is a compile error
  NAMING the option, instead of `unexpected token` pointing at it.
- An unknown option name is refused by name (CPython raises TypeError).

Deliberately still refused rather than ignored — the ticket's own reasoning:
accepting `frozen=True` would hand back a class that looks immutable and is
not. Generating the comparison dunders for `order=True` is the remaining work
and this ticket stays open for it.

### The second site — a pre-pass that disagreed

`PyRegisterClassFieldsPrepass` finds `@dataclass` by scanning BACK from the
class header and requiring the name to sit immediately before it. With an
argument list the previous token is `)`, so the pre-pass would have said "not a
dataclass" while `PyParseClass` said it was — the recorded two-passes-disagree
hazard, and it would have shown up as unregistered fields, not as an error. The
scan now steps over a balanced paren group. Found by looking for the sibling
site before closing, per `normalise-dont-special-case`; the `Later` class in the
new test is the row that covers it.

### Gate
`make compiler/pascal26` (fixedpoint, 1 round) + `tools/gate.sh quick` GREEN.
Family sweep rather than a wider gate: the four existing dataclass tests
re-run and unchanged (`test_nilpy_dataclass` has no `from dataclasses import`
line so CPython cannot run it — its output is byte-identical to the pinned
binary's).

New tests, expectations from CPython:
`test_nilpy_dataclass_decorator_args.npy` + `.expected`, and three compile-error
tests (`_order_fail`, `_frozen_fail`, `_unknown_option_fail`), all in the
`test-nilpy` target.

Note for whoever adds `order=True`: an `Optional[int] = None` field prints as
`o=0` rather than `o=None`, on the pinned binary and the bare decorator alike —
that is [[bug-nilpy-a-def-returned-none-loses-its-none-ness-in-a-variant-slot]]'s
int arm, not this ticket. It was in a draft of the new test and was removed for
that reason.
