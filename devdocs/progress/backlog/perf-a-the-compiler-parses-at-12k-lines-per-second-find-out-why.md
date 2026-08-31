---
track: A
prio: 60
type: perf
blocked-by: []
created: 2026-08-31
summary: "The compiler processes its own 235,854 lines in 19.7s and pylib+pyeval's 25,551 lines in 2.2s — ~12,000 lines/sec in both cases, so this is a uniform throughput figure and not a per-frontend problem. Find out where that time goes. Broad payoff (every frontend, every compile, every agent's mandatory 12s loop, and the 719 NilPy jobs per full tier) with no new mechanism and no new failure class — which is why this REPLACES the rejected unit-image cache."
---

# The compiler runs at ~12,000 lines/sec — find out why

Supersedes `rejected/decide-nilpy-runtime-tax-serialise-the-image-or-defer-the-bodies`
and closes `unfinished/perf-a-cache-the-compiled-nilpy-runtime-unit-image`. Read
the rejection for why caching was the wrong attack; this ticket is the right one.

## The number

| | lines | time | rate |
| --- | ---: | ---: | ---: |
| `compiler/*.inc` + `compiler.pas` (self-compile, pinned) | 235,854 | 19.7s | ~12,000 lines/s |
| `pylib.pas` + `pyeval.pas` | 25,551 | 2.2s | ~11,600 lines/s |

Same rate on two very different bodies of code, so the figure is a property of
the compiler and not of any one input. **Whether ~12k lines/s is bad is itself
unmeasured** — state it as the open question rather than as a defect. FPC is the
obvious oracle and `tools/fpc_diff_probe.sh` already exists; compiling a
comparable body of Pascal with fpc 3.2.2 and dividing is the first thing to do,
because if we are within 2x of FPC this ticket is much smaller than it looks.

## Known decomposition, inherited from the rejected ticket

Measured there on a 2.78s zero-byte `.npy` compile, and worth keeping because it
was carefully done (interleaved, min-of-N, load recorded):

| component | cost |
| --- | ---: |
| routine bodies (parse + lower + emit) | 1.63s (59%) |
| declaration / interface parsing | 0.78s (28%) |
| fixed compiler floor | 0.37s (13%) |

Also established there: **body text byte-scanning is ~0.02s**, so the 1.63s is
parse+lower+emit work and not I/O. What that experiment could not separate is
**tokenisation**, since its stripped and commented variants both avoided it.

## Method — the constraint that shaped this ticket

`perf` is dead on this box, and `.symtab` is empty even for a `-g` build (the
binary carries `.debug_info`/`.debug_line`/`.debug_frame` and nothing else), so
naive `nm`-based tooling reports nothing. `make pxx-debug` is `-O0` and says so
— **not** a profiling build. Build `-g -O2` explicitly.

`kernel.yama.ptrace_scope` is **1** on this box, so gdb cannot attach to a
sibling process; sample under `sudo gdb -p`, or launch the inferior as gdb's own
child. Neither needs a persistent system change and neither should be made one.

Per `debugging-playbook.md`: min-of-N interleaved, never means.

## What would make this ticket succeed

A named list of where the time goes, ranked, with a measurement per entry — not
a theory. The likely suspects (lexer, symbol lookup, the parallel-array growth
paths, IR construction) are **suspects and must be treated as such**; every
wrong root cause in this repo's history was a plausible story nobody diffed
against an oracle.

**And a benchmark before any change.** CLAUDE.md's O-charter is explicit that
`optdiff` proves a pass is not *wrong* and never that it *fires* — only a bench
answers the second, and only delivered value counts as promise.

---

## FIRST PROFILE, 2026-08-31 — 80 samples, `-g -O2` self-compile

Binary: `pxx_prof`, built by `stable_linux_amd64/default/pinned` at HEAD
`4546a42bf`, `-g -O2`. Workload: that compiler compiling `compiler/compiler.pas`
(235,854 lines). Sampled with `sudo gdb -p` (ptrace_scope is 1), `bt 30`, 80
samples.

| routine | self | on stack |
| --- | ---: | ---: |
| `??` (no DWARF) | **37 (46%)** | 37 |
| `AppendChar` | **14 (17.5%)** | 16 |
| `GetTokenStr` | 5 | 17 |
| `ParseFactorCore` | 4 | 11 |
| `IRLowerAST` | 4 | 7 |
| `InsertTokens` | 2 | — |
| `IRMarkReachableLabels` | 2 | — |

The first backtrace taken names the shape on its own:

```
ExpandPasMacros () at compiler/elfwriter.inc:4211
4211	        AppendChar(w, src[i]);
```

### The candidate

`compiler/lexer.inc:608`, the `{$else}` arm — **this is the one a pxx-built
compiler runs**; the `{$ifdef FPC}` arm above it (`dst := dst + c`) is only for
the FPC seed:

```pascal
procedure AppendChar(var dst: AnsiString; c: Char);
var len: Integer;
begin
  len := Length(dst);
  SetLength(dst, len + 1);
  dst[len + 1] := c;
end;
```

A managed-string `SetLength` **per character**, from roughly 400 call sites
across every lexer, `cpreproc.inc` (72), `pyparser.inc` (53), `elfwriter.inc`
(38), `pasparser_lval.inc` (25), `lexer.inc` (28) and all six asm-text emitters.
`SetLength`'s fast path is inlined, which is why its cost appears as
`AppendChar`'s own self time rather than in a callee.

### What is MEASURED and what is a STORY — do not conflate these

- **Measured:** `AppendChar` is 17.5% of self time in this workload.
- **NOT measured:** that the 46% `??` is the managed-string runtime beneath
  those appends. It *fits* — `builtinheap.pas` is compiled into the image
  without DWARF, so its frames cannot resolve — but it is a hypothesis. Every
  wrong root cause in this repo was a plausible story nobody diffed against an
  oracle, so **resolve those frames before acting on this.** It is the
  difference between "a quarter of compile time" and "most of it".

### Next steps, in order

1. **Attribute the `??` frames.** They have addresses; map them against the
   image. If they are the allocator/`PXXStrUnique`/copy path under
   `AppendChar`, this ticket has its root cause and the rest is design.
2. **Confirm the growth behaviour.** Does `SetLength(dst, len+1)` hit the
   in-place `PXX_FLAG_APPENDABLE` capacity path (amortised O(1)) or reallocate
   (O(n^2) per string built)? That single answer changes the size of the fix by
   an order of magnitude. Measure it; do not read it out of the source.
3. **Only then choose the shape.** A capacity-carrying builder, a `Reserve`, or
   nothing at all if step 2 says the fast path already fires. Per
   `root-cause-over-microfix.md`: count how many mechanisms serve "append to a
   string" before adding a fourth — `AppendChar`, `AppendString` and
   `AppendRange` are already three, each duplicated across an `{$ifdef FPC}`.
4. **Get the FPC comparison** the ticket body asks for, so "is 12k lines/s bad"
   stops being an assumption.

### Method notes for whoever picks this up

- `make pxx-debug` is `-O0` and says so — not a profiling build. Use
  `pinned -g -O2 compiler/compiler.pas <out>`.
- `.symtab` is empty even with `-g`; the binary carries only
  `.debug_info`/`.debug_line`/`.debug_frame`, so `nm`-based tooling reports
  nothing and gdb is the instrument.
- `kernel.yama.ptrace_scope` is 1: `sudo gdb -p`, or launch the inferior as
  gdb's own child. Do not make either a persistent system change.
