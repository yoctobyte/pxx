---
prio: 60
track: A
status: done
owner: frank-optimize-b4
---

# `-dPXX_ALLOC_CENSUS` — this runtime could not answer "how much does it allocate"

Track A files (`compiler/builtin/builtinheap.pas` and its own define), filed
under Track O's campaign because
[[bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython]] is what
needed it. Dispatched by the coordinator rather than routed to U: the instrument
question only needs a decision if the instrument is expensive or contentious,
and it was neither.

## The gap

The runtime had three diagnostic defines and all three answer **correctness**
questions:

| question | tool |
| --- | --- |
| is memory read after free? | `-dPXX_HEAP_DEBUG` |
| who retained / released it? | `-dPXX_OBJTRACE` |
| what did the compiler infer? | `PXXDBG` |
| **how much does it allocate, and of what size?** | **nothing** |

The debugging playbook's tool table had an empty row exactly there, and it was
not a theoretical gap. Three sessions of the uforth ticket ranked their own
follow-ups on callgrind shares — 9.28% `PXXStrFromLit`, 13.18% `PXXAlloc`,
6.06% `PXXFree` — and **valgrind is not installed on plexus**, where
`perf_event_paranoid` is 4 and blocks even user-space sampling. Those numbers
came from somewhere else or a differently configured box, and nothing in the
ticket said so. A share quoted without the condition that makes it true, on a
ticket whose entire ranking depends on it.

The distinction that matters: wall-clock A/B is **enough to size a change
already made, and not enough to rank two changes not yet made.** The census is
what unblocks the second without needing anything installed.

## What it does

Counters in `PXXAlloc` / `PXXFree` — calls, frees, bytes, which path served the
request (size bin / large first-fit list / arena bump), arenas mapped, and a
histogram over the 64 size classes. One block to stderr:

```
pxx-census: allocs=14482408 frees=14040465 live=441943 bytes=595241560 reuse=13999247 list=41000 bump=442161 arenas=1
pxx-census: sizes 8:37176 16:558 24:509 32:11710484 40:899237 48:571422 ...
```

`live` flat with `allocs` climbing is churn; `live` climbing is retention.
`reuse` vs `bump` says whether the free lists are working. The histogram is
where the churn actually is.

## Three design decisions, each forced by something

**No exit hook, so the report fires on a schedule.** The program's exit is
emitted by CODEGEN (`EmitExit`), not by this runtime, so a report-at-exit needs
a change outside the two files this was scoped to. Reporting at intervals turns
out to be better than the thing it substitutes for: it gives a growth CURVE
rather than one number, and **a program that segfaults still leaves its
census**.

**The interval is +12.5%, and doubling was tried first and measured as too
loose.** With no exit hook the last line is the closest thing to a total, and
its error is the step size. At 2x, two runs of the same program differing by
half their allocations produced last-report ranges that **overlapped** — the
honest reading of a real 44% reduction was "no conclusion". At `+ (n div 8) + 1`
the tail is within 12.5%, ranges separate cleanly, and about 180 lines cover
1e9 allocations.

**No call-site attribution.** That needs a caller tag threaded through every
entry point or a stack walk, and both change what they measure. Sizes plus
rates answer the question this was built for; the histogram turned out to
identify call sites indirectly anyway (see below).

**It allocates nothing**, and that is a hard requirement rather than tidiness:
it runs from inside `PXXAlloc`, so an allocation here re-enters the allocator,
and a managed string temp would be finalized on the way out into the release
blob, which takes the heap lock. That is the hang
`bug-a-threadsafe-plus-heap-debug-hangs-at-runtime` documents; digits go out
one byte at a time from a local array and labels are indexed in place out of
constants, exactly as `PXXDbgFlush` does.

## It paid for itself in the first run

uforth's `core.fr`, `-O2` against `-O3` — the static-string-literal pass:

| | allocations | bytes | live | 32-byte class |
| --- | --- | --- | --- | --- |
| -O2 | 14,482,408 | 595,241,560 | 441,943 | 11,710,484 |
| -O3 | 8,036,705 | 384,315,424 | 195,746 | 5,567,269 |

**44.5% of every allocation in the run is gone**, 35% of the bytes — and the
histogram says *where*: the 32-byte class alone falls by 6.14M, which is **95%
of the entire reduction** and is exactly the size of a short literal's block
(24-byte header + up to 7 bytes + nul, rounded to 8). That is a mechanism-level
reading no timing number can produce, and it is deterministic: a counting
instrument is immune to the box being busy, unlike the wall-clock figures on
the same box, which drifted enough that one binary measured 2.514s and 2.817s
twenty minutes apart.

## Gate

`make compiler/pascal26` (self-host fixedpoint), `gate.sh quick` GREEN, and one
verification that is stronger than either: **the compiler's own binary is
byte-identical across this change** (sha256 `53800fbeb0b6` before and after),
which is the claim "zero cost when the define is off" in its provable form.

`test_alloc_census` pins both directions — with the define a well-formed census
must reach stderr, without it nothing may, and the program's stdout must be
identical either way (a diagnostic that perturbs what it measures is worse than
no diagnostic). Both assertions were proven failable by inverting them.

Documented in `devdocs/dev/debugging-playbook.md` as step 3b, the row that was
empty.

## Not done here

- **No call-site attribution**, as scoped above.
- **`perf` and `valgrind` are still absent from plexus.** The census removes
  the dependency for allocation questions; it does not answer instruction
  counts or wall-clock attribution, and those remain unanswerable on this box.
  Installing the packages is the owner's call — recorded here so the constraint
  is written down somewhere other than in a session that ended.

## Log
- 2026-08-30 — built and landed, commit 0f0a5619a.
