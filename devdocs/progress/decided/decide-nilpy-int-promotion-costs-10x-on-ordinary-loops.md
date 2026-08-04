---
track: U
prio: 60
type: decide
---

# Option 1 was decided without a number; the number is 10x

- **Type:** decision (Track U) — blocks the remaining half of
  [[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]]
- **Filed:** 2026-08-04, after implementing option 1 and measuring it.

[[decide-nilpy-int-promotion-default]] chose **option 1** — "default every
NilPy `int` binding to promotable, native int64 only where the frontend can
PROVE the range". That was the right call on semantics and it is not being
re-opened here. What was never measured is what it costs, and the bug ticket's
own gate asks for exactly that: *"a benchmark check that ordinary integer loops
have not regressed"*.

## Measured (self-hosted binary at HEAD + the option-1 patch, x86-64)

```python
def loop(n):
    t = 0
    i = 0
    while i < n:
        t = t + i
        i = i + 1
    return t
print(loop(20000000))
```

| build | time |
| --- | --- |
| pinned (before) | **0.868 s** |
| option 1 (every int `+ - *` typed promo) | **8.739 s** |
| CPython 3 | 1.177 s |

So **10.1x slower**, and it flips NilPy from 1.35x *faster* than CPython on
integer loops to **7.4x slower**. Every promo operation is a runtime call today
— `feature-a-promoint-check-elision` is the open ticket for that — so the cost
is one call per arithmetic operator, not a marginal widening.

The implementation is not the problem. Both accumulator and counter are
genuinely unprovable: `i = i + 1` bounded by `i < n` says nothing about `n`, and
`t = t + i` says nothing at all. A range-proof pass strong enough to recover
this is a real analysis, not a special case, and it is not written.

## The fork

1. **Accept the 10x.** Correctness first (that is the recorded preference), ship
   option 1 as measured, and let `feature-a-promoint-check-elision` claw it back
   later. Every NilPy integer program gets ~10x slower the day it lands.
2. **Fund check-elision FIRST**, then land option 1 behind it. A promo `+` whose
   operands are both inline-tagged is an add and a branch; making that path
   inline rather than a call is where most of the 10x lives. Ordering this first
   means the user-visible day is "correct AND fast", at the cost of the wrap
   staying live until then.
3. **Land option 1 behind a flag** (`--nilpy-bigint`, default off) so the
   semantics exist and can be tested while the default stays fast. Honest, but
   it means the default NilPy `int` still is not Python's `int`, which is the
   whole complaint.
4. **Restrict promotion to values that have already been observed to grow** —
   i.e. option 2 from the original ticket (runtime promote-on-overflow), which
   needs a way to re-type a live binding and was set aside as bigger than a
   Track N change.

**Recommendation: 2.** The 10x is concentrated in one place, that place already
has a ticket, and landing the slowdown first means every benchmark row in
`tstate/` moves for a reason unrelated to what those rows exist to watch.

## What is already done and waiting

The option-1 patch is written, self-hosts, and gates GREEN
(`tools/gate.sh quick`), preserved as
`devdocs/progress/patches/int-promotion-option1-arith-typing.patch` and
`...-module-scope.patch`. With it, every row of the bug ticket's table matches
CPython except the two that were already known-separate. Full findings, including
the three regressions it exposes and their fixes, are on the bug ticket.

## DECIDED 2026-08-04 (Rene) — accept the 10x, land option 1

> "integer promotion, i think that's an optimization-like ticket. not a big
> deal. python wasnt meant for performant tight loops in the first place."

So the cost question is settled: correctness first, the 10x is acceptable, and
`feature-a-promoint-check-elision` claws it back later on its own schedule
rather than gating this.

**Landing is a separate matter and is NOT done.** Attempting it immediately
after this decision turned up four more wrong-value sites that the bug ticket's
earlier survey had missed, because that survey checked whether programs COMPILED
rather than what they PRINTED — including `[0] * n`, which is how Python
allocates a fixed-size list. Details, and the two fixes that did land, are on
[[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]].

Moved to `decided/`: the question this ticket asked has an answer. What is left
is implementation, tracked there.
