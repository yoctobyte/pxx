---
slug: bug-a-two-promotable-int-locals-and-exactly-one-other-local-segfault-at-o2
track: A
prio: 80
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
tags: [nilpy, promotable-int, o2, codegen, refcount, segfault]
blocked-by: []
summary: "A NINE-LINE NilPy program with no classes, no imports and no library calls SEGFAULTS at -O2, which is the shipped default level, and it reproduces identically on pin v418 (fda77c48b8ee) and at HEAD. TRIGGER, order-independent and measured across 18 variants: a function frame with EXACTLY THREE locals of which EXACTLY TWO are tyPromoInt64 (tk=28). Two promo-ints plus zero, two or three other locals all run clean; plus exactly ONE other local crashes, and the third local's type does not matter -- Int64 (tk=13), AnsiString (tk=23) and Double (tk=19) all segfault -- nor does its declaration position (first, middle, last all crash). Reducing to ONE promo-int makes it run. LEVEL MATRIX: -O0 clean, -O1 clean, -O2 SEGV, -O3 clean; the default with no -O flag is -O2 and therefore crashes. FAULTING INSTRUCTION is a refcount release sequence -- `cmpq $0x40000000,-0x10(%rax)` (the saturation check) then `decq -0x10(%rax)` -- with rax=0x2aa6428c, i.e. a promo-int's INLINE payload being dereferenced as a heap bignum pointer. So a release is emitted against a slot whose tag says the payload is not on the heap, or against the wrong slot entirely. NOT a missing tag check in general, because the same two promo-ints are clean at every other local count. NOT yet attributed to a pass: the compiler exposes no per-pass flags, so isolating it needs Track A instrumentation. Found while building a benchmark for perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program, where the coarse getattr arm MASKED it -- boxing every method to tyVariant removes the promo-int pair, so the arm that ticket wants narrowed is currently hiding this crash."
---

# Two promotable-int locals plus exactly one other local segfault at -O2

## The repro, complete

```python
def main():
    v0 = 0
    acc = 0
    i = 0
    while i < 3:
        acc = acc + 1
        i = i + 1
    print(acc)

main()
```

    ./compiler/pascal26 repro.py out     # default -O, i.e. -O2
    ./out                                # Segmentation fault (core dumped), rc=139

No class, no import, no method call, no library call. `v0` is never read
after its initialiser and never appears in the loop.

## What the compiler inferred

    PXXDBG n.locals main v0  tk=13    { Int64 }
    PXXDBG n.locals main acc tk=28    { tyPromoInt64 }
    PXXDBG n.locals main i   tk=28    { tyPromoInt64 }

`acc` and `i` are promotable ints because they are incremented and could grow;
`v0` cannot, so it stays a plain `Int64`. That inference looks correct. The
defect is downstream of it.

## The trigger, measured rather than reasoned

Holding the two promo-ints fixed and varying the OTHER locals:

| other locals | rc |
| ---: | --- |
| 0 | 0 |
| **1** | **139 (SIGSEGV)** |
| 2 | 0 |
| 3 | 0 |

**A prediction that was wrong and is recorded so nobody re-runs it:** the 2-pass
/ 4-fail / 3-crash shape looked like stack misalignment (3 x 8 = 24 bytes, not
16-aligned), so I predicted odd counts crash and even pass. Measured 1..8 total
locals: only 3 crashes. **It is not an alignment parity.**

Varying the third local's TYPE and POSITION — all still crash:

| variant | third local | rc |
| --- | --- | --- |
| plain first | `v0 = 0` (tk=13) | 139 |
| plain middle | `v0 = 0` | 139 |
| plain last | `v0 = 0` | 139 |
| plain is a string | `v0 = 'q'` (tk=23) | 139 |
| plain is a float | `v0 = 1.5` (tk=19) | 139 |
| **only one promo-int** | `acc` never incremented, so tk=13 | **0** |

So the condition is **two `tyPromoInt64` locals and exactly one other**, and
nothing else about the third local matters.

## Optimisation level

| level | rc |
| --- | --- |
| -O0 | 0 |
| -O1 | 0 |
| **-O2** | **139** |
| -O3 | 0 |
| default (no flag) | **139** |

`-O2` is the proven default, so every ordinary invocation hits it.

## Where it faults

Built `-g -O2`, under gdb:

```
Program received signal SIGSEGV
=> 0x40022a:  cmpq   $0x40000000,-0x10(%rax)
   0x400232:  jae    0x400260
   0x400234:  decq   -0x10(%rax)
   0x400238:  jne    0x400260
rax  0x2aa6428c   (715539084)
```

That is the refcount release sequence — saturation check at `0x40000000`, then
decrement, then skip the free when nonzero. `rax` holds `715539084`, which is a
small integer, not a heap address: **a promo-int's inline payload is being
dereferenced as a bignum pointer.**

## What is NOT established

- **Which pass.** The compiler has no per-pass flags (`--help` lists only
  `-O0..-O3` and `-OO`), so attributing this needs Track A instrumentation.
- **Whether the bug is the release's TAG CHECK or its SLOT INDEX.** Both fit the
  evidence. The same two promo-ints are clean at every other local count, which
  argues against a simply-missing tag check and for something layout-dependent.
- **Whether Pascal or C front ends can reach it.** `tyPromoInt64` is what the
  NilPy frontend infers for a growable integer; no attempt was made to produce
  the same frame from another language.

## Why it had not been found

The shape needs an *unused* extra local beside two loop counters, which is what
a hand-written test rarely has and what real code has constantly. It is also
**masked by boxing**: when
`perf-n-one-computed-getattr-in-any-imported-module-boxes-every-method-in-the-program`'s
coarse arm fires, every method takes variant params and results, the promo-int
pair disappears into `tyVariant`, and the crash goes with it. My first benchmark
for that ticket ran clean *because* it contained a computed `getattr`; deleting
the getattr is what produced the segfault. **Narrowing that arm will unmask this
in programs that currently work.**
