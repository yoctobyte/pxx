---
slug: perf-b-something-in-the-roofs-frame-allocates-and-it-is-not-the-primitives
track: B
type: perf
prio: 40
status: backlog
found: 2026-09-22
found-by: franks-5b
owner: ""
blocked-by: []
summary: "lekkerzeilen-7a measured 20.2% of the roofs frame in allocator/refcount (14.6 points of it in the allocator proper) on a binary with NO debug symbols at the default -O2, so it is not the -g/-O0 path. But a per-operation allocation sweep at -O2 puts variant compare, variant arithmetic, list indexing, iteration, attribute read, len() and all six string comparisons at ZERO allocations per evaluation. Both measurements stand, so the allocating thing in that frame is NOT the primitives, and nobody has named what it is. LEADING CANDIDATE, and it has a date on it: string indexing `s[i]` allocated 1.0054/op at -O2 until 2026-09-22 -- 7a's profile predates that fix, so re-profiling roofs is the first move and may answer the whole thing. WHY 40 AND NOT HIGHER: what remains here is a MEASUREMENT queued behind the wrap-up, not a perf front -- the fix that prompted it has landed, and the owner's own sequence on 2026-09-22 is finish-then-ESP32. A re-profile of roofs at a tree carrying the fix is what raises this; if that re-profile leaves the 14.6 allocator points unexplained, it becomes a real front and should be re-ranked then. DELIBERATELY NOT wired blocked-by to the perf umbrella (p95): membership is an edge and effective_prio takes the max, so that edge would promote this to the top of `ready` and dispatch the next seat into a front just sequenced behind something else."
---

# Something in the roofs frame allocates and it is not the primitives

**Two measurements that are both correct and do not fit together.** That is the
finding; the resolution is open.

## What each one says, with its population

**7a's roofs profile** — gdb SIGINT sampling, `lekkerzeilen` roofs scene,
2026-09-22. 20.2% of frame time in allocator/refcount, 14.6 of those points in
the allocator proper. **The binary had no debug symbols** — evidenced by gdb
printing *"(No debugging symbols found in .../bin/demo)"* in the run that
produced the samples, and corroborated by 7a having had to resolve symbols by
hand from the `.map`, which is only necessary when `-g` is absent. So this is a
**default `-O2`** binary and NOT the `-g`-implies-`-O0` trap
(debugging-playbook.md, "Profile the SHIPPING binary").

**The allocation sweep** — compiler `59b5bf39acd1` at HEAD (not the pin),
x86-64 linux, `-dPXX_ALLOC_CENSUS`, allocations per operation from
`(allocs@11000 - allocs@1000) / 10000` so every fixed cost cancels. At the
default `-O2`: variant `==`/`<`/`+`/`*`, `lst[i]`, `for e in lst`, attribute
read, `len()` and **all six string comparisons** are **0.00 per evaluation**.
Two controls held in the same run — integer arithmetic at 0.00 (so fixed cost
is not being attributed to the loop) and an object allocated per iteration at
1.01 (so the instrument can see an allocation at all). Without both, the zeros
would be silence rather than measurements.

## EXCLUDED — this list is the value of the ticket

A negative result that names its exclusions is a finding; one that does not is a
shrug. Measured at 0.00 allocations per evaluation at the default `-O2`, on the
tree and with the controls above, and therefore **NOT** the source of the 14.6
allocator points:

- variant `==`, `!=`, `<`, `<=`, `>`, `>=`
- variant `+` and `*`
- **all six** string comparisons (inline `repz cmpsb`, no call, no heap -- and
  0.00 at `-O0` TOO, so this row is not an optimiser effect)
- list indexing `lst[i]`
- `for e in lst` iteration
- attribute read `obj.f`
- `len()`
- user function call, 2-arg call, method call, closure call, call returning a str
- `d[k]` read, `d[k] =` store, `k in d`

The call, dict and iteration rows matter most, because those are the operations
a frame loop is MADE of and the ones a reader would reach for first.

## The question

**Something in that frame allocates at `-O2`, and it is not the operations
anyone would have guessed.** Neither measurement is in doubt; what is missing is
the call site.

## What DOES allocate at -O2, same sweep — the candidate set

| operation | alloc/op at `-O2` |
| --- | ---: |
| `s[a:b]` slice | 1.01 |
| `s + t` concat | 1.01 |
| `s.upper()` (5 chars) | 4.59 |
| `[a, b, c]` list literal | 1.79 |
| object construction, `list.append` | > 0 |

`s.upper()` is the interesting row: `PyStrMapCase` starts at `''` and appends
per character, one reallocation each, so its cost scales with string LENGTH and
5 characters already cost 4.59. Anything formatting text per frame hits that.

## FIRST MOVE, and it may answer the whole thing

**`s[i]` allocated 1.0054/op at `-O2` until 2026-09-22** — a fresh one-character
string per subscript, and the same for a for-in variable and `list(s)`, which
all lower to `pystr_charat`. That is fixed now (a static 256-entry const table
shared by `pystr_charat` and `pychr_s`). **7a's profile predates the fix.** A
THIRD spelling of the same one-byte-string allocation, `pystr_ofchar` -- the
compiler's char->str promotion, wired at four sites in `pasparser_lval.inc`,
`ir.inc` and `pyparser.inc` -- is NOT yet on the table and still allocates.

So: **re-profile roofs at a tree carrying the fix before investigating
anything else.** If the allocator share drops, the question is answered and this
ticket closes. If it does not, the 14.6 points are still unexplained and the
next instrument is a reverse call graph on `PXXAlloc` over the roofs binary —
build `-g -O2` (BOTH: pxx emits no section headers without `-g`, and `-g` alone
silently means `-O0`), then attribute each call site to its enclosing proc via
an ADDRESS-SORTED map. pxx writes the map in neither address nor name order, so
taking "the next line" yields a plausible wrong range.

## What would make this ticket wrong

A re-profile showing the allocator share was always small and 20.2% was a
sampling artefact. 7a's own instrument had a defect that made an empty capture
present as twenty samples (its `=== SAMPLE` header), found and fixed the same
day — so the sample COUNT of the run quoted here is worth re-confirming before
a lot of work is spent on the strength of it.
