---
summary: "MEASURED: copying one SHARED AnsiString handle in a `parallel for` body, with ZERO allocation in the loop, runs 0.08-0.09x of serial on 12 workers -- three times worse than the heap-spinlock cliff it is usually confused with. Every worker retains/releases the same refcount word, so one cache line is bounced across all cores. A per-thread heap free-list cache CANNOT fix this: there is no allocation. The unshared control (each worker owning its strings) shows the same mechanism costing essentially nothing, so this is about SHARING, not about refcounting."
type: bug
prio: 45
track: A
---

# A shared AnsiString handle in a `parallel for` is 11x slower than serial

- **Type:** bug / perf — **Track O** (optimization; file-ownership + gate
  **Track A**).
- **Status:** backlog — filed 2026-08-31.
- **Found by:** frankA, while separating the two contended mechanisms named in
  [[feature-opt-heap-per-thread-cache]]. Filed separately **because a per-thread
  heap cache cannot touch it** — folding it into a ticket titled about the heap
  would make it invisible.

## Measured

Binary `3b0833e71eaf`, 12 cores, box load ~6, N = 4,000,000, three repeats. Each
row is the identical loop run serially and then under `parallel(pdChunked) for`.

| | what it contends on | serial | parallel | speedup |
| --- | --- | --- | --- | --- |
| A `GetMem(64)/FreeMem`, no managed type | heap spinlock only | 250-260 ms | 954-2169 ms | 0.11-0.26x |
| **B copy a SHARED AnsiString handle, no allocation** | **refcount atomics only** | **148-155 ms** | **1595-1787 ms** | **0.08-0.09x** |
| C `SetLength` churn | both | 364-380 ms | 1366-1536 ms | 0.23-0.27x |

Row B is the subject. It is the **fastest serial** row and the **slowest
parallel** one.

```pascal
shared := 'a shared immutable handle every worker copies';
...
parallel(pdChunked) for i := 0 to N - 1 reduction(+: acc) do
begin s := shared; acc := acc + Length(s); end;
```

`s := shared` retains, and `s` going out of scope releases — both `lock`-prefixed
RMWs on **the same refcount word**, for every worker, every iteration. One cache
line, twelve cores.

## Why this is not the heap ticket

- **There is no allocation in row B's loop.** A per-thread free-list cache has
  nothing to cache.
- **Row C is the unshared control and it exonerates refcounting in general.**
  C allocates *and* refcounts, each worker owning its own strings, and lands on
  row A's number — so private-string refcounting costs essentially nothing.
  The mechanism is not "atomics are expensive"; it is "one line, twelve writers".

So state the claim as **"a shared string handle in a parallel loop"**, never as
"refcounting is 11x". Row B is the maximally-contended shape by construction and
would be a misleading headline on its own — which is exactly the kind of number
that gets quoted for a year.

## Why it matters

The shape is ordinary, not adversarial: a shared prefix, a lookup table, a
config string, an error-message template read inside a hot parallel loop. Nothing
about the source says "this line is a global lock". The program is correct and
the slowdown is silent.

## Directions (unmeasured, in rough order of cost)

1. **Hoist the retain out of the loop.** If the compiler can see that `s` is
   assigned from a loop-invariant handle and never escapes the iteration, the
   retain/release pair is redundant — the handle outlives the loop. This is an
   ARC-elision question, not a runtime one, and it is the only direction that
   costs nothing at run time.
2. **Non-atomic refcounts for handles proven thread-local**, with the atomic path
   kept for anything that crosses a thread boundary. Needs an escape analysis
   this compiler does not have today.
3. **Biased/deferred reference counting** — the standard literature fix. Large.
4. Nothing at all: document it and let `parallel for` users copy the string into
   a local before the loop. Cheapest, and honest, if 1 is out of reach.

## Acceptance

- Row B's speedup > 1x on 12 workers, with rows A and C not regressing.
- The unshared control (row C) must stay where it is — a fix that makes shared
  handles fast by making private ones slower is not a fix.
- Track A gate: `make test` + self-host byte-identical.

## Links
[[feature-opt-heap-per-thread-cache]] (where the separation was measured; that
ticket keeps rows A and C) · `lib/rtl/palparallel.pas` ·
`compiler/builtin/builtinheap.pas` (the retain/release helpers).


---

## 2026-08-31 (frankB) — part of row B was the LITERAL, and it is fixed; the rest is the lock order

Row B's `shared` is a **string literal**, so at `-O2` it is a static pool block
with a saturated refcount — and until today x86-64's hand-emitted retain/release
blobs wrote that refcount unconditionally, `lock`-prefixed under `--threadsafe`.
Twelve workers were doing a locked RMW on one immutable word, per iteration.

`bug-a-string-release-has-two-implementations-that-already-disagree` gave both
blobs the `MSTR_STATIC_RC` guard that `PXXStrDecRef`/`PXXStrIncRef` always had,
so a saturated block is now never written. Measured on this ticket's own shape
(4M iterations, 12 workers, binary `4ae31c9e10cf` vs `f92c42a69850`, min of 3):

| | before | after | |
| --- | ---: | ---: | --- |
| parallel only | 1.18 s | **0.95 s** | ~19% |
| serial only, `--threadsafe` | 0.14 s | **0.12 s** | ~14% |

**So this ticket is not closed, and the remaining gap has a named cause.**
Parallel is still ~8x serial, and it is no longer the refcount word: both blobs
call `EmitAcquireHeapLock` **before** the nil test and before the guard, so a
release that is about to do nothing at all still takes the global heap spinlock
first. Twelve workers now serialise on the *lock* line instead of the
*refcount* line.

That also sharpens the summary's claim. "A per-thread heap free-list cache
cannot fix this" is still right — there is no allocation — but the reason has
two halves, and only one of them was refcount atomics. The other is a lock
acquired for a path with nothing to protect.

**The fix, and why it was not done in the same change:** hoist the nil test and
the `MSTR_STATIC_RC` compare above `EmitAcquireHeapLock`, leaving the lock
around only the `dec`-and-maybe-free. It is sound — the lock protects the free
list, not the refcount word, and a saturated block's count is immutable, which
is the argument `PXXStrIncRef` already makes for its own lock-free read of the
same word. It needs rel32 patch sites (the jumps now span the whole TTAS lock
body, which can exceed a rel8 displacement) and it lands in threadsafe-only
code that `--tier quick` barely exercises, so it wants its own change and its
own measurement rather than riding along.
