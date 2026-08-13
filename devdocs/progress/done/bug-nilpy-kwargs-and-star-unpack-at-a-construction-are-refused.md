---
summary: "Three construction-site argument shapes are refused with a diagnostic: `C(**kw)` on a `**kwargs` ctor, `C(*xs)` unpacking into one, and a keyword whose name matches a FIELD when the ctor takes `**kw`. All work at a plain `def` or an ordinary method; only the construction path is short."
type: bug
track: N
prio: 45
found-by: claude-AN
status: done
owner: claude-A-N
---

# `**kwargs` and `*`-unpack at a CONSTRUCTION are refused

- **Type:** bug (valid Python refused) — Track N
- **Opened:** 2026-08-11, sweeping the argument-shape matrix while fixing
  [[bug-nilpy-a-fixed-parameter-before-star-args-segfaults]]. That one was a
  segfault and is fixed; these three are diagnostics, so they are filed rather
  than folded in. All confirmed at `stable_linux_amd64/default/pinned`.

## The three shapes

```python
class E:
    def __init__(self, **kw):
        self.n = len(kw)

E(a=1)      # error: Nil Python: E has no field or constructor parameter named 'a'
```

```python
class A:
    def __init__(self, *args):
        self.n = len(args)

xs = [1, 2]
A(*xs)      # error: expected expression
```

```python
class F:
    def __init__(self, a, *rest, **kw):
        self.a = a
        self.k = len(kw)

F(1, 2, k=9)   # error: Nil Python: F() got multiple values for field 'k'
```

The third is the sharpest: the keyword `k` is not a declared parameter, so it
belongs in `**kw` — but the construction site matches a keyword name against the
class's FIELDS, and `self.k = ...` declared one. So a class is punished for
naming a field after one of its own keyword options, which is the normal thing
to do.

## Why they are one ticket

Same cause as the segfault that was just fixed, one step further along:
`PyClassCreate` assembles the construction call itself and does not go through
the shared argument path. `*args` packing was simply absent there and has now
been added (with a `selfSlots` offset, since the construction chain has no Self
node). These three are the remaining cases that path still does not reach:

- the `**kwargs` container is never built for a ctor, so an unmatched keyword
  has nowhere to go and the field/parameter lookup reports it as unknown;
- `PyStarUnpackMethodArgs` (the call-site `*xs` expansion) is wired into the
  METHOD paths in `parser.inc` and not into `PyClassCreate`;
- the keyword-vs-field precedence in `PyClassCreate` has no "…unless the ctor
  takes `**kwargs`, in which case a non-parameter keyword goes there" arm.

All three are a diagnostic rather than a crash, which is why they rate 45 rather
than the segfault's 55.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`C(**kw)`, `C(*xs)`, `C(*xs, **kw)`, a keyword colliding with a same-named
field, and the already-working `*args`/positional forms as controls; diffed
against CPython. The plain-`def` and ordinary-METHOD twins already work and
should stay in the test as the controls that say which path is short.

## Related

[[feature-nilpy-star-args-kwargs]] is the broad callee-side feature (unfinished);
this is specifically the CONSTRUCTION call site.

## 2026-08-11 (claude-A) — re-confirmed live at HEAD, not started

All three shapes still fail at HEAD, unchanged from the filing:

| shape | HEAD |
| --- | --- |
| `d_kw(a=1)` — a plain def with `**kw` (the CONTROL) | works, `1` |
| `E(a=1)` with `def __init__(self, **kw)` | `E has no field or constructor parameter named 'a'` |
| `A(*xs)` with `def __init__(self, *args)` | `expected expression` |
| `F(1, 2, k=9)` with `(self, a, *rest, **kw)` and a field `self.k` | `got multiple values for field 'k'` |

The control matters: the def twin working is what says this is the CONSTRUCTION
path being short rather than the feature being absent.

**Not started, deliberately.** `PyClassCreate` assembles the construction call
itself, so each of the three is a path the shared argument code already has and
this one does not — which means the honest fix is the one
`normalise-dont-special-case` prescribes: route construction through the shared
argument path rather than grow a third copy of `**kwargs` packing, `*`-unpack
and keyword-vs-field precedence inside it. That is a bigger change than the
ticket's three bullet points suggest, and worth scoping as such rather than
half-applying.

Released back to the backlog with the measurement above so the next session
starts from a confirmed boundary rather than re-deriving it.

## DONE 2026-08-13 — all three shapes, with one sub-case refused by name

`E(a=1)` on a `**kw` ctor, `C(*xs)`, and `F(1, 2, k=9)` where `k` is also a
field all work and match CPython.

### Shape 3 was the sharp one and the fix is an ORDERING

The keyword lookup checked the ctor's parameters, then FIELDS, and only had
nowhere left to go after that. A `**kwargs` ctor that stores `self.k = len(kw)`
declares a field named `k`, so the keyword matched the field, found its slot
taken by the positional `2`, and was rejected. The `**kwargs` arm now sits
BETWEEN the two: a name that is not a declared parameter goes to the dict if
the ctor has one, and only otherwise falls through to fields. So a class is no
longer punished for naming a field after one of its own keyword options.

The key travels on the argument's `ASTIVal` as `-(node + 1)` — the same
convention `PyKwArgIndex` already uses for a method call — and
`PyPackStarArgs`, which this path already ran for `*args`, decodes it into the
dict. These arguments are collected on their own chain and spliced in before
that packing runs, since they have no slot in the field-ordered re-emission.

### `C(*xs)` is handled BEFORE the slot loop

The whole argument list is one unpack, so there is nothing for the keyword/slot
bookkeeping to do; the shared `PyStarExpandCallArgs` fills every remaining
declared slot at once, exactly as the method paths use it.

**Refused by name, deliberately:** `A(*xs)` where the ctor ITSELF takes `*args`
or `**kwargs`. That wants the list passed through as the packed parameter — a
different lowering from expanding into declared slots — and the shared expander
counts every signature slot, packed ones included, so it demanded one element
per container and failed at RUN time with an arity message about a call the
program never wrote. A compile-time refusal naming the shape is strictly better
than that.

**Caught by the FPC SEED canary, not by the self-hosted build:**
`PyStarExpandCallArgs` is defined far below `PyClassCreate` in the same
include, which pxx resolves either way and FPC does not
([[bug-a-fpc-seed-drift-emitasmx64-forward]]). It now has a forward
declaration. Worth noting because `gate.sh quick` runs that canary concurrently
and it is the only thing that sees this class of error.

Test `test/test_nilpy_ctor_star_and_kwargs.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy`, with the plain-`def` and ordinary-METHOD
twins as the controls that say which path was short. The three existing
ctor/star/kwargs tests re-run against their inline expectations.

Gate: self-host fixedpoint + `tools/gate.sh quick` GREEN (including the seed
canary).

### Noted, not fixed

`self.kw = kw` — storing the `**kwargs` dict itself in a field — fails with
"cannot infer the type of field self.kw". That is the field-inference gap, not
this ticket's argument path, and no row here depends on it.

## Log
- 2026-08-13 — resolved, commit 3525a2d57.
