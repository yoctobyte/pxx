---
track: P
prio: 35
status: done
owner: claude-dupwt
type: perf
blocked-by: []
summary: "CHARACTERISED, NOT MEASURED, AND DELIBERATELY NOT OPENED -- banked so it is cheap to pick up later. The shape: `CaseEqual(GetTokenStr(idx), nm)` allocates an AnsiString through GetTokenStrFromRaw (SetLength + copy) purely to compare it and free it, and CaseEqual's length reject fires only AFTER the string exists, so a wrong-length token pays a full PXXAlloc/PXXFree round trip to learn it was never a candidate. 159 occurrences remain across the Pascal and Rust frontends -- pasparser_prog.inc 93, pasparser_generic.inc 38, pasparser_decl.inc 10, pasparser_proc.inc 8, pasparser_stmt.inc 4, pasparser_expr.inc 1, rparser.inc 1 -- counted by OCCURRENCE, not by grep -c, which counts lines and undercounted this twice on 2026-09-21. The remedy already exists and is proven: TokenCaseEqual in ast_syminfer.inc compares TokChars in place after an integer length reject, semantics identical including the empty/out-of-range edges, and converting the 62 occurrences in pyparser.inc was part of a change that took lekkerzeilen's compile from 105.6s to 92.5s (-12.4%) with BYTE-IDENTICAL emitted output. WHY IT IS NOT BEING DONE NOW: the owner scoped compiler-speed work to NilPy on 2026-09-21 -- 'the 12 second self-build is totally acceptable, we are just worried about nilpy' -- so Pascal parse time is not a worry he holds, and this is banked rather than opened. NOTHING HERE IS A MEASUREMENT OF PASCAL PARSE TIME: no profile has ever been taken of it and the NilPy result does not transfer, because NilPy's cost came from scans that cross the whole import closure and the Pascal frontend may have no equivalent. WHAT WOULD MAKE THIS WORTH OPENING: a profile of a large Pascal build showing GetTokenStrFromRaw or PXXAlloc/PXXFree in the top few symbols. That profile does not exist. Mechanism and the NilPy result: devdocs/perf/lekkerzeilen-build-time.md."
---

# The Pascal parser allocates a string per identifier token to throw it away

**This ticket is a characterised job, not a request to do it.** It exists so
that on some later day the work is an afternoon rather than a rediscovery.

## The shape

`GetTokenStr(idx)` calls `GetTokenStrFromRaw`, which does `SetLength(s, len)`
and a copy — a heap allocation. `CaseEqual(a, b)` then rejects on length in its
first two lines. **So the cheap reject happens after the expensive part.** Every
identifier token a scan passes costs an allocation, a copy, a comparison and a
free, in order to answer a question an integer comparison settles.

## The remedy, already written and already proven

`TokenCaseEqual(idx, nm)` in `ast_syminfer.inc` compares `TokChars` in place
after `Tokens[idx].SLen <> Length(nm)` rejects. **Semantics are identical,
edges included** — an out-of-range index and an empty token both yield `''` from
`GetTokenStr`, and `CaseEqual('', nm)` is true exactly when `nm` is empty, which
the replacement reproduces explicitly rather than by accident.

It carries `-dPXX_TCE_CROSSCHECK` (computes both ways, reports disagreements)
and `-dPXX_TCE_BREAK` (deliberately wrong, to prove the crosscheck fires). On
lekkerzeilen those read 0 and 67. **So a converter does not have to trust the
substitution; they can measure it in two builds.**

The rewrite is mechanical: `CaseEqual(GetTokenStr(X), Y)` -> `TokenCaseEqual(X, Y)`,
and every occurrence in `pyparser.inc` had a simple index expression with no
nested parentheses.

## What is NOT claimed

**Pascal parse time has never been profiled.** The NilPy win came from routines
that scan the whole token array *per definition*, where that array holds every
imported module — a shape the Pascal frontend may simply not have. **A reader
who assumes 12.4% transfers is reasoning from an unmeasured analogy.**

Before opening this, profile a large Pascal build. If `GetTokenStrFromRaw` or
the allocator is not in the top few symbols, close this as not worth it and say
so here.

## 2026-11-19 (claude-dupwt): profiled, then done, with a bigger neighbour

**The profile.** I sampled the compiler compiling itself with
`tools/pxx_pc_sample.py`: 200 samples, flat self-time, using the binary's own
fresh map. This is the large Pascal build the ticket asked for.

| symbol | before | after both changes |
| --- | --- | --- |
| ShiftTokParallel + InsertTokens | **31.5%** | (`__pxxMove` 9.5%, after the first change) |
| GetTokenStrFromRaw | 4.0% | 8.5% (share grew once the shift cost was gone) |
| PXXAlloc + PXXFree + GetTokenStr + CaseEqual | 9.0% | 10.0% |

The top item was not the one this ticket names. It was token SPLICING:
ShiftTokParallel moved thirteen parallel arrays one element at a time, in
lockstep, and InsertTokens / RemoveTokens moved `Tokens[]` the same way. Once
that was fixed, the token-string family was 18.5% of samples and
GetTokenStrFromRaw was the second-largest named symbol. That meets the
ticket's own condition for doing the conversion, so I did it.

**Change 1 (lexer.inc).** New `MoveTokParallelRun`: one overlap-safe `Move`
per parallel array. ShiftTokParallel uses it in both directions, and
InsertTokens / RemoveTokens block-move `Tokens[]`. The gap-fill policy (inherit
directive state, zero the spelling and attribute channels) is unchanged. A new
parallel array now has to be added in three places: EnsureTokCapacity,
MoveTokParallelRun and the gap fill.

**Change 2.** I rewrote all 159 occurrences of
`CaseEqual(GetTokenStr(X), Y)` as `TokenCaseEqual(X, Y)`. They are in
pasparser_prog 96, pasparser_generic 38, pasparser_decl 11, pasparser_proc 8,
pasparser_stmt 4, pasparser_expr 1 and rparser 1. That is exactly the
ticket's count. The rewrite was mechanical: a balanced-parenthesis scan, with
no index expression that contained a quote or a newline.
pyparser.inc:1821 still has one (NilPy, rd's lane, left alone).

**Verification.**
- `-dPXX_TCE_CROSSCHECK` compiler compiling the compiler: **0** TCE-DISAGREE.
  The control (`-dPXX_TCE_BREAK`) reports **477**, so the check is not
  vacuous.
- Fixedpoint converged in 1 round after each change, so the compiler's output
  for its own source is byte-identical to the previous compiler's. The three
  self-compile outputs (original, Move only, both) `cmp` identical.
- Gate quick: see the commit.

**Time.** Self-compile, user CPU, three alternating rounds. The box was loaded
(load average 12 to 35 on 12 threads), so compare within a round:

| round | original | Move only | both |
| --- | --- | --- | --- |
| 1 | 42.33 s | 36.48 s | 32.86 s |
| 2 | 45.30 s | 39.55 s | 35.93 s |
| 3 | 49.01 s | 40.13 s | 36.19 s |

That is about -22% to -26% on the compiler's own build. The owner said
self-build time is acceptable (2026-09-21), so this is a cheap win, not a
requested one.

**Still in the profile:** `__pxxMove` at 9.5%. The splices are now cheap per
call but still O(TokCount) each. Batching them would be the next step if
anyone needs one. GetTokenStrFromRaw stays at 8.5% through its other callers
(plain `GetTokenStr` uses that are not comparisons).
