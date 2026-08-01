---
track: U
prio: 60
type: decide
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — Option 1

**User's call: 1.** Default every NilPy `int` binding to promotable; native
int64 only where the frontend can prove the range (loop induction vars,
`len()`, indices). Matches CPython — `int` is always arbitrary-precision,
so silent wraparound is a correctness bug, not an edge case. Native's whole
point is tight/fast loops, and promotable-int's fixnum/heap-bignum hybrid
should already keep ordinary small-int overhead minimal by design — so the
benchmark gate isn't expected to be a real blocker, just confirmation.
Gate from the ticket still applies (benchmark check + regression suite)
before landing. Re-file the implementation into
[[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]]
(Track N, or A if it needs new symtab/IR machinery promotable-int doesn't
already have).

# Decide: should NilPy `int` bindings default to promotable, not native int64?

Split out of [[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]],
whose own text already says "probably wants a Track U call" — filing that call
rather than picking a direction, since it's a real performance-relevant default,
not a narrow bug fix.

## The fork

```python
n = 1
for i in range(1, 26):
    n = n * i
print(n)      # CPython: 15511210043330985984000000     pxx: 2076180480 (wraps)
```

[[feature-a-promotable-int]] already built real arbitrary-precision int
(fixnum → heap bignum) — it works when a binding's STATIC type comes out
promotable, which today is decided purely by how wide the INITIALISING
LITERAL was. `n = 1` starts native int64 and stays native int64 no matter how
large the arithmetic grows it, wrapping silently at 2^63 with no diagnostic.
A binding that starts with a big literal is correct all the way through.

Confirmed (this session) this is the whole story, not two bugs: the
ticket's own "factorial prints nothing" row does not reproduce as a crash or
empty output — `range(1, 26)` accumulation prints `2076180480`, an ordinary
silent wrap, same as every other row in the ticket's table.

## Why not a narrow fix

`feature-a-promotable-int` deliberately keeps loop induction variables,
indices, and `len()` results as native int64 "with no checks at all" — a
sound performance decision that should not change. The gap is that an
ordinary accumulator binding gets that SAME native treatment purely because
its first literal happened to fit in a word, and nothing today distinguishes
"this is provably a bounded induction variable" from "this is a general
integer that might grow arbitrarily".

## Options (from the ticket)

1. **Default every NilPy `int` binding to promotable**, keeping native int64
   only where the frontend can PROVE the range (a `range()`-loop induction
   variable, a `len()` result, an index). Correct by default; the ticket's
   own recommendation. Cost lands on ordinary integer code, which is most
   code — needs a benchmark check that ordinary integer loops have not
   regressed before this is acceptable.
2. **Promote on overflow at run time** — keep the native representation,
   add an overflow check to every arithmetic op that could carry out, and
   re-type the live binding when it does. Avoids the blanket cost of (1) but
   needs a way to change a binding's representation mid-lifetime, which
   nothing in this compiler's model does today.
3. **Widen only when a binding is assigned FROM an already-promotable
   expression** (propagate promotability through the assignment graph,
   rather than only from the literal). Cheaper than 1; still misses `n = 1`
   growing purely through native arithmetic (exactly the ticket's headline
   case), so it does not actually close the gap that matters most.

## Gate (once scope is decided)

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the ticket's
own measured table against CPython, AND a benchmark check that ordinary
(non-overflowing) integer loops have not regressed — that regression risk is
the entire cost of option 1 and needs to be measured, not assumed.
