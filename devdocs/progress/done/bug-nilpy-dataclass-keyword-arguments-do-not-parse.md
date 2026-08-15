---
prio: 30
track: N
type: bug
blocked-by: []
status: done
---

# `@dataclass(order=True)` does not parse — the decorator takes no arguments

- **Type:** bug (loud: a parse error, not a wrong answer) — **Track N**
- **Found:** 2026-08-08, while gating
  [[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]] (it was going to be the
  natural third case in that test)
- **Owner:** agent-AN

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

## Resolution (2026-08-15) — `order=True` generates the comparisons; ticket closed

The remaining work the 2026-08-12 pass named. `@dataclass(order=True)` now
generates `__lt__`, `__le__`, `__gt__` and `__ge__` over the FIELD TUPLE in
declaration order, which is what CPython's decorator documents.

**The bodies are tuple ordering written as one expression**, built from the last
field backwards:

```
acc := <False for lt/gt, True for le/ge>
for i := last downto first:  acc := (a_i OP b_i) or ((a_i = b_i) and acc)
```

That is the same accumulator shape `PyEmitDataclassEq` next door uses, and it
gives the property that matters: the first differing field decides, and later
fields only matter while the earlier ones are equal. Verified against CPython on
a two-field class where both orders of divergence are exercised.

**The flag is recorded by the PRE-PASS, not by `PyParseDataclassArgs`.** That
routine runs on the cursor before the class is reached and has no `ci` to record
against, while the pre-pass sees every class — and BOTH passes reach
`PyRegisterClassMembers`, which is where the four methods are registered. Same
two-passes-must-agree hazard the 2026-08-12 pass hit with the backwards scan,
avoided the same way: one place decides.

`PyDcCmpName` is one function asked by both the registration and the body
emitter, so the two cannot disagree about which of the four slots is which.

**The refusal test is retired WITH the feature.** `test_nilpy_dataclass_order_
fail.npy` asserted the compile error this ticket just removed; left in place it
would have compiled and turned the nilpy suite red in a way `gate.sh quick`
cannot see. Deleted, its Makefile recipe replaced with the real test, and the
file's own header says what replaced it. `frozen=True` and the unknown-option
refusals are untouched and still asserted.

**One divergence, in the permitted direction:** CPython REFUSES a hand-written
`__lt__` under `order=True` (`TypeError: Cannot overwrite attribute __lt__`);
NilPy accepts it and lets the hand-written one win, as it already does for
`__eq__`/`__repr__`. No program CPython runs can observe that, so it is recorded
in `devdocs/dev/nilpy-semantics-divergences.md` rather than refused.

**Gate:** `test/test_nilpy_dataclass_order.npy` (+`.expected`, in the Makefile)
— single- and two-field ordering, all four operators, `sorted`/`min`/`max`, a
mixed int/str class with a default, and `order=False` still being the bare
decorator. Byte-identical to CPython. The five sibling dataclass tests re-run
unchanged. `tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit 6582d9a20.
