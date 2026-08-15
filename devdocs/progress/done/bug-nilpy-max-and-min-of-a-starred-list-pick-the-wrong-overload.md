---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`max(*[xs])` and `min(*[xs])` return the LIST instead of its largest/smallest element — the star forwarder resolves the callee to one procIdx before it knows the argument is a container, so it binds the 2-argument `max(a, b)` overload where the direct `max(xs)` call correctly binds the list-taking one. Silent wrong value; the direct spelling is right, which is why no test saw it."
status: done
owner: claude-A-N
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

## RESOLVED — the ticket's cause was wrong; it is not overload resolution at all

Filed as "the star path resolves the callee to one procIdx before it knows the
argument is a container". Measured, and that is not what happens. `max`/`min`
never reach the forwarder: `parser.inc` has an arm just for them
(`PyStarIsIterableForm`) that rewrites `max(*xs)` to the single-argument
iterable form `max(xs)` — deliberately, from
[[bug-nilpy-star-unpack-into-a-fixed-arity-builtin]], because the run-time arity
dispatch used to look for a three-argument `max`.

**That rewrite is a real equivalence, but only above one element.** CPython's
`max(*xs)` is `max(xs[0], xs[1], …)`:

- **two or more** starred elements — the elements are compared, which is exactly
  what `max(xs)` does. The rewrite is correct and is left untouched.
- **exactly one** — it is `max(xs[0])`, over that element's CONTENTS. The
  rewrite compared a one-element list of lists instead and handed back the inner
  list.

So the boundary is the starred COUNT, not the argument's type, and it is a
run-time fact — which is why no compile-time overload choice could have fixed
it, and why `max(v)` on a variant holding a list was right all along (checked:
via a dict value, a list element, and a def parameter).

**Fix.** `pystar_iterable(l: TPyList): TPyList` in `compiler/builtin/pylib.pas`
returns `l` unchanged for a count other than 1, and `pystar_as_list(l.at(0))`
for a count of 1. For two or more this is byte-for-byte the previous lowering.
`pystar_as_list`, not a cast, because the single element may be any iterable —
`max(*["abc"])` is CPython's `max("abc")` = `'c'`. The frontend wraps the star
operand in it at the one `PyStarIsIterableForm` arm
(`PyStarIterableNode`); `zip(*rows)` shares `PyZipStarOperand` but not this arm
and is unchanged.

**Verified** byte-identical to CPython across 12 rows: the one-element list, a
float list, a one-element str, two-and-more scalars, a named `xs`, string
comparison, `zip(*rows)`, and the direct `max(xs)` control. Regression rows
added to `test/test_nilpy_zip_star_and_n_way.npy` — which already carried the
`max(*xs)`/`min(*xs)` coverage from the earlier ticket, so this is the same
file the equivalence was first recorded in — with its `.expected` updated.
`tools/gate.sh quick` GREEN.

No repin needed despite the `compiler/builtin` change: `pinned` compiles against
its own frozen `compiler/builtin/*.pas`, and only a HEAD-built frontend emits
the new call, so nothing that builds against `pinned` can reach it.

## Log
- 2026-08-15 — resolved, commit 61b95e238.
