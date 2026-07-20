---
track: A
prio: 50
type: feature
---

# Promotable int: inline the fast path (check elision)

Stage 3 of [[feature-a-promotable-int]]'s staged plan, deferred while stages
1-2 (type, storage) and the heap tier landed. Purely performance — correctness
is done and CPython-verified.

## Why it is outstanding

Per [[decide-promoint-rvalue-representation]] Option A, **every promotable-int
operation is currently a runtime call**, including for values that never leave
the inline tier. That was the deliberate trade: it bought correctness on all
six backends with zero backend changes. The cost is real and this ticket is
where it is paid back.

The inline fast path already exists — it is just on the callee side, inside
`PXXPromoAdd` and friends in `compiler/builtin/promoint.pas`, rather than at
the call site.

## Shape

- Range/induction analysis to prove a value stays inside the inline tier, so
  loop counters, indices and `len()`-style results carry no check at all. The
  umbrella ticket calls this out as the thing that "restores full native speed
  in ordinary loops".
- Inline the tag test plus the native op at the call site, calling the runtime
  only on the overflow/heap edge.
- Land behind `-O3` first and promote per-pass to `-O2` only after the full
  gate, per Track O's rules.

## Measure first

Do not start from the assumption that the call is the dominant cost — build a
benchmark (a factorial or Fibonacci loop that stays inline, versus the same
loop on `Int64`) and get the actual ratio before choosing what to inline.

## Gate

Benchmarks showing the inline-tier loop approaching Int64 speed, every existing
promo test still exact against CPython, `--tier quick` + self-host
byte-identical.
