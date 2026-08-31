---
track: A
prio: 65
type: bug
blocked-by: []
summary: "RESOLVED AS NOT-A-COMPILER-DEFECT, and the docs already said so. `parallel for` captures enclosing locals BY REFERENCE -- docs/library/concurrency.md: 'captured by reference through the frame', 'accumulating into one shared variable is a data race unless you guard it' -- so the test, which ran `s := ''` against another worker's `SetLength(s, 8)` on ONE captured AnsiString, was a documented data race. The three-way fork this ticket raised for Track U needs no ruling: option 1 (auto-privatise) would CONTRADICT the documented contract, so option 3 stands and the test is fixed. test_setlen_in_parallel_for_body.pas now pins the captured-scalar loop to one worker (`parallel(pdChunked, n 1)`), keeping the LOWERING under test -- the point of the file -- with no race, and adds a second loop writing DISJOINT slots of a captured dyn array for real concurrency. Was 16/20 correct, 3/15 on 4 cores; now 42/42 across 1/2/4-core pinnings. Filing this was still right: building the race-free replacement is what surfaced bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride, a silent miscompile of EVERY captured dynamic array in every parallel loop."
status: done
owner: frankA
---

# A `parallel for` body shares ONE captured string across every worker

Found 2026-08-31 on `seven` by the Track T heap-debug sweep, as one of two
failures in an otherwise clean 1836/1838 native tier.

## The measurement

`test/test_setlen_in_parallel_for_body.pas` (added with `aada606bc`) asserts
`total=8000`: 1000 iterations each contributing `Length(s)` = 8, via
`reduction(+: acc)`.

| build | correct runs |
| --- | --- |
| **plain, uninstrumented** (`cb0cc3bdbecfa602`) | **16 / 20** |
| `-dPXX_HEAP_DEBUG` (`1cf683edc2af`) | 6 / 10 |

Wrong totals seen: `7992` (-8, one iteration lost), `7968` (-32), `7912` (-88).

**It fails in the DEFAULT build.** The instrumented run is where the sweep
noticed it, but heap poisoning is not required to reproduce it and this is not
an artefact of the instrument — that was checked precisely because it would have
been the convenient conclusion.

Not a simple width threshold either — `taskset`, plain build, 15 runs each:

| cores | 4 | 12 | 16 | 24 |
| --- | --- | --- | --- | --- |
| correct | 3/15 | 6/15 | 5/15 | 11/15 |

Non-monotonic, so it is timing-dependent contention rather than a capacity
ceiling. (Contrast `bug-a-the-17th-thread-silently-aliases-reactor-slot-0`,
whose cliff is exactly at `MAX_REACTORS` and which is a different mechanism —
this test uses `palparallel` OS threads, not the `scheduler`/`CurR` reactors.)

## The mechanism, and why the test cannot be fixed in the test

```pascal
procedure Run;
var i: LongInt; s: AnsiString; acc: Int64;      { <-- s is Run's, not the body's }
begin
  parallel(pdChunked) for i := 0 to 999 reduction(+: acc) do
  begin
    s := '';  SetLength(s, 8);  acc := acc + Length(s);
  end;
```

`s` is declared in `Run`'s frame. The file's own header says the body "is lifted
with the string passed BY POINTER" — so every worker dereferences **the same**
`AnsiString`. `s := ''` in one worker races `SetLength(s, 8)` and `Length(s)` in
another, and a lost update shows up as a short total.

`acc` is correct by construction: `reduction(+: acc)` gives each worker a private
accumulator and folds them under a lock. **`s` has no such treatment and no way
to ask for one** — `reduction(op: v)` is the only clause in the grammar; there is
no `private(...)`. So the test cannot express what it means, which is why this is
a lowering/language item and not a test fix.

## What `aada606bc` did and did not do

It correctly fixed the SizeOf-style classifier bug: `SetLength` through a pointer
deref was classed as a frozen string, so this body would not compile at all
(`pinned` still refuses it). That fix is right and is not in question.

But a refusal was the only thing preventing the race from being observed, so
removing it made a latent defect reachable — the same shape frankA described for
`0d91dc88f`, where fixing a leak stopped padding a use-after-free. **The fix made
the shape compile; it did not make it correct.**

## The fork this needs decided (Track U if it is not obvious to the lane)

1. **Auto-privatise** a captured variable the body assigns, the way OpenMP treats
   loop-local scalars. Most likely what a reader expects, and it makes the test
   correct as written.
2. **Add a `private(...)` clause** and require it; the test then declares
   `private(s)` and the current lowering stays.
3. **Document the shape as unsupported** and change the test to a per-iteration
   local, which makes it a compile-only regression test for `aada606bc`.

Not chosen here: it is a language-semantics call, not a defect report. What is
NOT an option is leaving it — a test that passes ~80% of the time will flake in
every sweep from now on and be re-triaged by whoever next sees it, which is a
standing tax on Track T and on everyone reading tstate.

*Found by the Track T agent on `seven` under the provenance rule: my box's sweep
produced it, so the reduction is mine and the fix is the lane's.*

## Resolution (frankA, 2026-08-31)

**The fork did not need Track U — `docs/library/concurrency.md` already answers
it**, and it should have been read before this ticket proposed three options:

> The body may reference the loop variable, globals, and enclosing locals —
> scalars, strings, records, classes, and arrays alike — **captured by reference
> through the frame**. […] Iterations must be independent […] Writing disjoint
> slots is safe; **accumulating into one shared variable is a data race unless
> you guard it.**

That is the contract, it matches OpenMP's default for variables declared outside
the region, and the compiler implements it exactly. So option 1 (auto-privatise)
is not "most likely what a reader expects" — it would silently diverge from the
documented model, and in the other direction: a variable a body deliberately
shares would quietly become private. **Option 3 stands: the program was wrong.**

### What the test does now

`RunCaptured` keeps the exact motivating shape — a captured `AnsiString`,
`SetLength` through the lifted pointer — and pins it with `parallel(pdChunked,
n 1)`. The lowering under test is identical at any worker count; only the race
goes away. `RunDisjoint` restores real concurrency the documented-safe way,
writing disjoint slots of a captured `array of AnsiString`.

The header says **why** `n 1` is there and that widening it brings the flake
back, because the next reader's instinct will be to delete it.

**Measured:** 12/12 unpinned, 15/15 on 4 cores, 15/15 on 2 cores. The 4-core
figure is the one to compare — this ticket measured 3/15 there.

### What this cost, and what it bought

`RunDisjoint` would not compile: `SetLength(arr[i], 8)` on a captured dyn array
was refused. That was not a `parallel for` bug but
[[bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride]] — a 4-byte
stride for every captured dynamic array, which had a captured `array of Double`
in a parallel body writing **all zeros**, silently, in the default build. This
ticket's real value was leading there.

### Not chosen, filed separately

A `private(...)` clause ([[feature-a-a-private-clause-for-parallel-for]]) would
make the original shape expressible. Additive, consistent with the documented
model, and NOT required to close this — filed low.

## Log
- 2026-08-31 — resolved, commit f3ef2ef1d.
