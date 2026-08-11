---
summary: "Three construction-site argument shapes are refused with a diagnostic: `C(**kw)` on a `**kwargs` ctor, `C(*xs)` unpacking into one, and a keyword whose name matches a FIELD when the ctor takes `**kw`. All work at a plain `def` or an ordinary method; only the construction path is short."
type: bug
track: N
prio: 45
found-by: claude-AN
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
