---
track: N
prio: 60
type: bug
owner: frank1-AN
blocked-by: []
summary: "`bytearray.append(self, x)` — how a bytearray subclass reaches the base method it overrode — is `unexpected token`, because pylib's `function bytearray: TPyBytes` makes the bare word `bytearray` a complete parameterless call, so it parses as `bytearray().append(self, x)`. The identical defect in list/tuple/bytes was introduced and reverted on 2026-08-27; this one is original and has never been written down."
status: done
---

# `bytearray`'s zero-argument overload makes the bare name a call

- **Type:** bug (Track N) — a compile refusal of working CPython code.
- **Found:** 2026-08-27, while reverting the same defect after introducing it in
  `list`/`tuple`/`bytes`
  ([[regression-test-core-test-nilpy-unbound-builtin-method]]).
- **Measured on:** pinned **v383** (`18392d1d3181`) and HEAD alike. Original,
  not a regression — it has existed for as long as the overload has.

## Repro

```python
class BA(bytearray):
    def add(self, x):
        bytearray.append(self, x)
b = BA()
b.add(65)
print(len(b))          # CPython 1
```

```
v383: pascal26:3: error: unexpected token
HEAD: pascal26:3: error: unexpected token
```

`list.append(self, x)` and `dict.__getitem__(self, k)` both work (they are
gated by `test_nilpy_unbound_builtin_method`); only the `bytearray` spelling
does not, and nobody had written it.

## Cause

This dialect lets a **parameterless function be called by its bare name** — a
Pascal inheritance. `pylib.pas` declares `function bytearray: TPyBytes;
overload;` for the zero-argument constructor, so the bare word `bytearray` is a
complete call, and `bytearray.append(self, x)` becomes
`bytearray().append(self, x)` — an instance `append` given two arguments, hence
`Expected: ), but got: x`. The unbound-receiver intercept
(`PyBuiltinBaseCi`, reached from `pyparser.inc`'s
"BUILTIN type name as a RECEIVER" arm) never gets a chance to run.

This was measured directly: the same three lines added to `list`, `tuple` and
`bytes` broke the two gated unbound tests within the hour, and reverting them
restored both.

## Why the sibling fix did not just take it over

`list()` / `tuple()` / `bytes()` now answer in the PARSER, keyed on the
`name` `(` `)` shape — which by construction cannot capture a bare name or a
name before a `.`. `bytearray()` was routed there too and then backed out: the
pylib overload also stamps `FIsByteArray`, and without it `repr(bytearray())`
became `b''` instead of `bytearray(b'')`. Reproducing that needs a second pylib
entry point (a named one, not an overload of `bytearray`), which is a small
pylib change with a pin attached rather than a parser change.

## Shape of the fix

Add `pybytes_new_bytearray` (or reuse whatever already stamps `FIsByteArray`) to
pylib, drop `function bytearray: TPyBytes; overload;`, and add `bytearray` to
`PyIsZeroArgCtorName` / `PyZeroArgCtorIsContainer` with an arm that calls the new
entry point. Then no builtin type name is a parameterless call.

Worth checking in the same pass: whether any OTHER pylib proc has a
zero-argument overload whose name a NilPy program could write bare. That is the
general form of this bug, and a grep for `overload;` on a parameterless
declaration answers it.

## Gate

The repro prints `1`; `repr(bytearray())` stays `bytearray(b'')` and
`type(bytearray()).__name__` stays `bytearray`; `test_nilpy_unbound_builtin_method`
and `test_nilpy_builtin_subclass_dunder_dispatch` stay green. Touches
`compiler/builtin/**`, so it carries the `stabilize-fast` + `make pin`
obligation.

## Resolution — 2026-08-27

Fixedpoint `22690b507548`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_bytearray_unbound_and_subclass.npy` + `.expected`,
registered in the Makefile. The Gate's requirements all hold: the repro prints
`1`, `repr(bytearray())` is `bytearray(b'')`, `type(bytearray()).__name__` is
`bytearray`, and `test_nilpy_unbound_builtin_method` and
`test_nilpy_builtin_subclass_dunder_dispatch` are both green.

Implemented as the ticket's "Shape of the fix" section specified:

- **`pybytes_mark_bytearray`** added to pylib — the twin of `pylist_mark_list`,
  stamping `FIsByteArray` on an already-built TPyBytes. This is the second pylib
  entry point the ticket said was needed, and it deliberately reuses
  `pybytes_from_list` rather than adding a construction path.
- **`function bytearray: TPyBytes; overload;` is gone**, so no builtin type name
  is a parameterless call any more.
- **`bytearray` added to `PyZeroArgCtorIsContainer`** with an arm that builds
  the empty literal exactly as `bytes` does and then marks it.
- **`pyeval.pas`'s reflective `bytearray`/`bytes` call-by-name** used the
  removed overload. Rewritten — and split, because the one line served both
  names and answered a **bytearray-stamped object for a zero-argument
  `bytes()`**, so `type(bytes()).__name__` said `bytearray` through that route.
  Found only because the removal forced the line open.

**A second, pre-existing defect was blocking the Gate and is fixed with it.**
With the parse error gone the repro compiled and then **segfaulted**. Measured
on pinned v385 as well, so it is not this change's doing — and the boundary is
sharp: `class BA(bytearray): pass` then `BA()` segfaults, while `class L(list)`
and `class D(dict)` are fine. Cause: a subclass with no `__init__` emits a call
to the base's **parameterless `Create`**, and `TPyBytes` declared only
`Create(n: Integer)` where TPyList and TPyDict each declare a no-argument one.
The asymmetry was the defect, not the subclassing. `TPyBytes` now declares both
as overloads; `Create` is not a name a NilPy program writes, so this reintroduces
no bare-name hazard. Both `class X(bytearray)` and `class X(bytes)` construct.

**The general form, as the ticket asked.** Grepping parameterless `overload;`
declarations across `pylib.pas` and `pyeval.pas` finds exactly one other:
`function complex: TPyComplex; overload;`. It is **latent, not reachable** —
`TPyComplex` declares no methods at all, so there is no `complex.<meth>(self,
…)` spelling for the bare name to swallow, and `complex(1, 2)` / `.real` /
`.imag` all measure correct. Left alone rather than churned: it becomes a real
defect the moment TPyComplex gains a method, and this note is the record of
why it was seen and passed over.

**Canaries green, named:** `unbound_builtin_method`,
`builtin_subclass_dunder_dispatch`, `bytearray_ctor`, `bytearray_vs_bytes`,
`bytes_repr`, `bytes_literal`, `bytes_methods`, `subscript_dunder_spellings`.

**Carries the pin obligation** (`compiler/builtin/**` touched) — pinned in the
same push.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
