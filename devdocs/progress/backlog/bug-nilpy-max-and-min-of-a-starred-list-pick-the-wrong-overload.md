---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`max(*[xs])` and `min(*[xs])` return the LIST instead of its largest/smallest element — the star forwarder resolves the callee to one procIdx before it knows the argument is a container, so it binds the 2-argument `max(a, b)` overload where the direct `max(xs)` call correctly binds the list-taking one. Silent wrong value; the direct spelling is right, which is why no test saw it."
---

# `max(*[xs])` / `min(*[xs])` bind the wrong overload

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-15, sweeping the star forwarder for
  [[bug-nilpy-star-forwarder-refuses-a-container-typed-parameter]]. It is
  **pre-existing and independent** of that fix — reproduced identically on
  `pinned` — so it is filed rather than folded in.

## Repro

```python
print(max(*[[4, 9, 2]]))     # CPython 9      pxx [4, 9, 2]
print(min(*[[4, 9, 2]]))     # CPython 2      pxx [4, 9, 2]
```

The **direct** spelling is correct on both `pinned` and HEAD:

```python
xs = [4, 9, 2]
print(max(xs))               # 9    agrees
print(max([4, 9, 2]))        # 9    agrees
```

Two spellings of one operation answering differently is the tell.

## Where it comes from

`PyStarForwardCall(procIdx, listNode, dictNode)` takes the callee's `procIdx`
**already resolved** — chosen before the forwarded argument's runtime type is
known. `max`/`min` are overloaded (a 2-argument scalar form and a
container-taking form), and the resolution that happens on the star path picks
the scalar one, so a forwarded single list argument binds where the direct call
would have selected the container overload.

Note this is the by-name-resolution family
(`project_nilpy_byname_findproc_lowerings_are_the_unchecked_population`): a
lowering that names a callee and skips overload resolution. Worth grepping the
other star entry points for callees with more than one overload before closing —
`sum` and `sorted` have a single signature and are unaffected, which is exactly
why the sweep only caught `max`/`min`.

## Deliberately NOT covered by the star-forwarder test

`test/test_nilpy_star_forward.npy` was extended for the container-parameter fix
and stops short of `max`/`min` on purpose: a test that covers someone else's
open bug goes red for a change that did not cause it.

## Gate

`.npy` diffed against CPython: `max(*[xs])`, `min(*[xs])`, both against their
direct spellings, plus a two-scalar forward (`max(*[1, 2])`) which must keep
selecting the scalar overload. Per-fix loop.
