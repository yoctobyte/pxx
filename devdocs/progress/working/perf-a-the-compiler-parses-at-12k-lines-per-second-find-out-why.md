---
track: A
prio: 60
type: perf
blocked-by: []
created: 2026-08-31
summary: "ANSWERED and partly fixed. Profiled: the managed-string + heap runtime is ~47% of a self-compile (PXXStrFromLit 17%, PXXAlloc 10%, PXXFree 8.6%, refcount thunks 8.6%) — resolved through the compiler's own .map file, not DWARF. GetTokenStr built every token string a char at a time and was 17 of the 18 AppendChar samples; fixed in 4b3d34f74 for 13.8% off a self-compile. Top remaining item split out as perf-o-string-literals-still-allocate-at-11329-call-sites-despite-the-static-handle-pass. FPC oracle now measured: we are 1.28x fpc 3.2.2 on the same file, i.e. inside the 2x band the ticket set as its own de-escalation criterion. Still open: the July-3.4s vs today-21.7s discrepancy."
status: working
owner: frankB
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

---

## CORRECTION, same day — the profile above was read without its family

Filed by the same agent that wrote the profile, hours after filing
`feature-t-detect-ticket-clusters-that-share-a-construct`, and demonstrating its
need on itself. **Read this section before acting on the profile.**

### 1. The quadratic append was already fixed, and the fix is IN the tree I profiled

`bug-o-the-in-place-string-append-is-x86-64-only-so-every-other-backend-is-quadratic`
(track A, **prio 92**, found and closed by frankA 2026-08-31, resolved
`af07a59ff`, landed 15:15). Verified rather than assumed:
`git merge-base --is-ancestor af07a59ff 4546a42bf` → **yes**.

Its finding: `PXXStrSetLen` always reallocated and copied, so
`SetLength(s, Length(s)+1)` copied the whole string per call — making the
compiler's own string building O(n^2) **everywhere but x86-64**, which had an
inline fast path in its emitter. Now fixed in the runtime for all six targets:
*"20000 appends: 19780 allocations -> 16 on every target."*

**So step 2 of "Next steps" above is answered, and answered the other way.** The
profile was taken on x86-64, which already had the fast path, and `AppendChar`
is still 17.5% of self time. This is **not** a quadratic-realloc problem. It is
the per-character cost of the *already-optimised* path multiplied by an enormous
call count — a different problem needing a different fix. Do not go looking for
the reallocation; it is not there.

### 2. The obvious attack was already tried and rejected ON MEASUREMENT

`rejected/feature-opt-lazy-token-sval` (2026-07-10, prio 55) prototyped
"don't materialise token strings" in full — gated pool storage in
`LexAll`/`LexAppend`, keep-everything inside `asm..end`, monotone SOffset
preserved. Measured on the frozen-string self-host binary:

```
baseline pascal26 self-compile:  3.406 s ± 0.038  (hyperfine, 8 runs)
patched stage1 self-compile:     3.455 s ± 0.049  → no win, ~1% noise
```

Rejected 2026-07-11 per the campaign's measured-not-speculative rule. **Do not
re-derive this.** If you believe it should win now, say what changed since
2026-07-11 and measure that, rather than re-running the same prototype.

### 3. The cluster this ticket belongs to

Six prior tickets on "the compiler is slow at string building / startup", none
of which were consulted before this one was filed:

| ticket | state |
| --- | --- |
| `perf-compiler-hotspots-algorithmic` | done, 2026-07-03 |
| `feature-opt-lazy-token-sval` | rejected, 0 win measured |
| `bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost` | done, p80 |
| `bug-o-the-in-place-string-append-is-x86-64-only-...` | done today, p92 |
| `decide-nilpy-runtime-tax-serialise-the-image-or-defer-the-bodies` | rejected today |
| *this ticket* | open |

This is the exact blind spot `feature-t-detect-ticket-clusters-that-share-a-construct`
exists to close, reproduced by the agent who filed that ticket, on the same day.
**A profile is evidence about the binary; it is not evidence that the question
is new.**

### 4. One OPEN and UNVERIFIED discrepancy

The July baseline above is a **3.406s** self-compile. The measurement at the top
of this ticket is **19.7s** for the same operation. The compiler has grown since
July and this box's load was not recorded (CLAUDE.md notes the watcher costs
2-3x), so it may be entirely explained. **It is also 5.8x and nobody has
checked.** Do not report this as a regression; do not dismiss it either.
Re-measure both under known load before drawing anything from it.

---

## 2026-08-31, owner — the runtime is ALREADY optimal here; the cost is the call sites

Owner proposed over-allocating on realloc (16-256 spare bytes) to cut
reallocations. **Already implemented, in the stronger form**, and read out of
the code rather than a ticket summary — `builtinheap.pas:4295`:

```pascal
want := newLen + PXX_HDR_SIZE + 1;
if (oldData <> nil) and (newLen > oldLen) then want := want + want;   { geometric }
```

Why the implemented form is better, stated because the fixed-slack idea is
intuitive and will be re-proposed: **a fixed 16-256 byte slack is still
quadratic**, merely with a smaller constant — a 100 KB string built one
character at a time with 256 bytes of headroom still performs ~400
reallocations. Geometric doubling is amortised O(1), which is why the measured
figure is 20,000 appends -> **16** allocations (log2, exactly).

`feature-opt-bulk-copy-is-byte-at-a-time` (p65) is **done**, so the copy inside
the realloc path is not byte-at-a-time either.

### Therefore

Both runtime-level fixes are in. The remaining `AppendChar` 17.5% is **not
allocation and not copying**. It is the per-call cost of the in-place fast path
multiplied by the call count: a procedure call, a `Length` load, a refcount
test, an `APPENDABLE` flag test, a capacity test, a zero-fill, a length store, a
NUL store and a meta store — **to move one byte**.

**So the fix is at the ~400 call sites, not in the runtime.** `AppendRange(dst,
src, first, last)` already exists and appends a span in one call. The archetype
is a lexer scanning an identifier one character at a time while it already knows
where the token started: note the end, append the range once. That is one
`SetLength` and one copy per token instead of one full fast-path traversal per
character.

**Still gated on the same measurement.** This is the shape of the fix IF the 46%
unresolved frames turn out to be under `AppendChar`. Attribute them first — this
paragraph is a plan, not a finding.

### OWNER DIRECTIVE 2026-08-31 — reduce the USE of AppendChar; do not wait on the frame attribution

*"let's just try to minimize the use of appendchar() in the first place."*

This supersedes "attribute the `??` frames first" as the **starting** task. The
attribution is still worth having — it says whether the ceiling is a quarter of
compile time or most of it — but it no longer blocks the work, because both
runtime-level fixes are already in and the call sites are where the remaining
cost lives regardless.

Order of attack, by call density: `pyparser.inc` (53), `cpreproc.inc` (72),
`elfwriter.inc` (38), `lexer.inc` (28), `pasparser_lval.inc` (25),
`clexer.inc` (21), `pylexer.inc` (21), then the six asm-text emitters.

Five constraints, and the first is the one that will bite:

1. **Measure, do not count.** "~400 call sites" is a **census**, not a
   measurement — the O-charter is explicit that promise means *delivered value
   measured*, after a campaign advertised ~37% from an instruction census and
   delivered 5-7%. Baseline first, convert a batch, re-measure. Min-of-N
   interleaved A/B/A/B, never means, sha256 of the binary beside every number.
2. **Land incrementally.** Not 400 sites in one commit. Per-fix loop each time.
3. **`lexer.inc` has TWO definitions** of `AppendChar`/`AppendString`/
   `AppendRange`: `{$ifdef FPC}` (`dst := dst + c`, the seed path) and `{$else}`
   (`SetLength` per char, what a pxx-built compiler runs). Converting CALL SITES
   is arm-neutral. Touching the definitions means both arms must stay correct.
4. **The fixedpoint does not cover what is being edited.** `compiler.pas` is not
   written in C, NilPy, Rust or Zig, so editing those lexers is invisible to it.
   Carry a one-line repro per frontend touched.
5. **Behaviour must not change.** This is purely how a string is accumulated. A
   conversion that is not obviously equivalent gets skipped and noted, not
   guessed — a subtly different token string is a wrong VALUE surfacing far from
   its cause.


---

## 2026-08-31, frankB — the ranked list this ticket asked for, and a 13.8% win

Assigned as a cluster by the owner via frank-user-a2. Two profiles, both gdb,
both `-g -O2` self-compiles of `compiler.pas`, 70 samples each.

### First: the AppendChar census was pointing at the wrong function

Profile 1, binary `436c178ddcb9`, attributing **AppendChar's CALLERS** rather
than counting call sites:

```
18/70 samples have AppendChar on the stack
17 of those 18 come from ONE site — GetTokenStr, ast_syminfer.inc:181
```

Not `cpreproc.inc` (72 sites) or `pyparser.inc` (53). Those counts are a census
of the SOURCE, and **`cpreproc.inc` is the C preprocessor — it does not execute
at all in a Pascal self-compile.** Converting its 72 sites would have measured
as exactly zero. This is constraint 1 of the owner directive doing its job on
the ordering that accompanied it.

`GetTokenStr` built a token's text one `AppendChar` per character out of the
contiguous `TokChars` pool. `lexer.inc`'s `GetTokenStrFromRaw` is the **same
function already written correctly** — one `SetLength`, one fill — with a
comment saying it was changed because char-at-a-time was O(n²) per token. Its
twin was missed. The arm left slow was the one every parser goes through:
`GetTokenStr` is how token text is read at 570+ call sites across all
frontends, `pyparser.inc` alone calling it 314 times.

Fixed in `4b3d34f74`, two lines, delegating to the existing function.

| | runs (s) | min |
| --- | --- | ---: |
| base `101c9a7ea8b0` | 22.081 22.270 21.650 21.984 21.837 | **21.650** |
| mod `a5ca167411d8` | 18.999 18.996 18.673 19.245 20.193 | **18.673** |

**13.8% faster**, min-of-5 interleaved A/B/A/B, load 6.46 → 6.17. The worst
modified run beats the best baseline run, which is what makes it robust to the
box carrying ten other agents. Both binaries then compiled `compiler.pas` and
the two outputs are **byte-identical** (`cmp`) — behaviour unchanged.

### Second: where the time actually goes

Profile 2, binary `c6cf4c33684a`, taken after that fix. **The `??` frames are
resolved** — not by DWARF, but through **the compiler's own `.map` file**,
which `pinned` writes beside every binary. This ticket's method note says
`.symtab` is empty and `nm`-based tooling reports nothing; that is true and it
led everyone to gdb. The map was there the whole time and resolves every
runtime frame by nearest preceding symbol.

Frame #0 — what is actually executing:

| | samples | share |
| --- | ---: | ---: |
| `PXXStrFromLit` + its thunk | 12 | **17.1%** |
| `PXXAlloc` | 7 | 10.0% |
| `PXXFree` | 6 | 8.6% |
| inline string refcount inc/dec thunks | 6 | 8.6% |
| `PXXHdrSetMeta`, `PXXDynArrayRelease` | 2 | 2.9% |
| **— managed-string + heap runtime** | **33** | **47%** |
| `GetTokenStrFromRaw` | 5 | 7.1% |
| `AppendChar` / `AppendRange` / `AppendString` | 6 | 8.6% |
| compiler proper (parser, lexer, IR, emit, all sites ≤2) | 16 | 23% |

**So the ticket's open question is answered, and the answer is the second
option: not a quarter, roughly half.** The 46% unresolved in the first profile
was hypothesised to be "the managed-string runtime under `AppendChar`". Half
right, and the wrong half is the actionable one — it IS the managed-string
runtime, but the bulk of it is **not** under `AppendChar`. It is under string
**literal materialisation** and **refcounting**, which need a different fix.

Two guards on those numbers. 70 samples is small: treat each row as ±5%, and
the ordering as the finding rather than the digits. And nearest-preceding-symbol
resolution attributes a gap to the previous symbol — the 8 samples that
resolved to `_start` sat in a 1117-byte unnamed gap, so I disassembled it
rather than reporting it: `0x400109` is a register-save thunk calling
`PXXStrFromLit`, `0x400129` is string incref (`incq -0x10(%rax)`), `0x400137`
is decref falling into `PXXFree`. None of it is `_start`.

### What is now the top item, and it is filed

[[perf-o-string-literals-still-allocate-at-11329-call-sites-despite-the-static-handle-pass]]
— `objdump` counts **11,329** `movabs len / movabs ptr / call PXXStrFromLit`
sites in the `-O2` compiler binary, even though `EmitStaticLitHandle` exists to
make a literal an address and **is** active at `-O2`.

### Remaining AppendChar work is measured as NOT worth a campaign

After the `GetTokenStr` fix, `Append*` is 6/70 samples spread over **six
different call sites at one sample each** — `elfwriter.inc`'s
`ExpandPasMacros`/`ExpandIncludes`/`IncEmitLineMarker` and one in `LexOne`.
There is no second concentration. Converting the remaining ~390 census sites is
not supported by any measurement, and the O-charter's promise gate ("delivered
value, measured") is the reason to say so rather than grind through them. The
elfwriter expander loops are still a legitimate small batch — genuine
per-character loops that already know their span — but they are worth about
6-7% collectively, not individually.

### The FPC oracle — MEASURED, and it shrinks this ticket

The ticket says compiling comparable Pascal with fpc 3.2.2 and dividing is the
first thing to do, "because if we are within 2x of FPC this ticket is much
smaller than it looks". Done, on the same file both compilers actually build
(`compiler/compiler.pas`, 235,854 lines), interleaved FPC/PXX/FPC/PXX,
min-of-3, pxx binary `b11f52fb4316`:

| | runs (s) | min | lines/s |
| --- | --- | ---: | ---: |
| fpc 3.2.2 `-O2 -Tlinux -Px86_64` | 12.04 12.01 10.07 | **10.07** | 23,424 |
| pxx (default `-O2`) | 14.40 13.09 12.89 | **12.89** | 18,303 |

**1.28x.** So we are well inside the 2x band, and by the ticket's own criterion
it is much smaller than it looked. ~12k lines/s is not a defect; it is roughly
what a mature Pascal compiler does on this box.

Two honesty notes. FPC's later runs trend faster (12.04 → 10.07), so some of
its min is page-cache warmth and our real disadvantage is if anything smaller
than 1.28x. And **the headline "12,000 lines/s" is itself load-dependent**: the
same operation measured 18,303 lines/s here on a quieter box. That does not
overturn the ticket, but any future comparison against that number has to
record load or it is comparing machines rather than compilers.

### Still open, unchanged, and NOT claimed
- **The 3.406s (July) vs ~21.7s (today) discrepancy.** Not re-measured here,
  so not reported as a regression and not dismissed. Note only that today's
  baseline was taken at load ~6.5 with ten agents on the box.
- `asmenc.inc` has **42** `AppendChar` sites — more than `elfwriter.inc`'s 38 —
  and was missing from the density ordering. Never measured; may be cold.

---

## STATE AT 2026-08-31 REBOOT (frankB) — established vs hypothesis, and the next step

Nothing in flight; tree clean at `7ef9c2204`, everything below is on origin.

**ESTABLISHED (measured, numbers and binary shas in the sections above):**

- `GetTokenStr` was 17 of 18 `AppendChar` samples. Fixed, `4b3d34f74`, **13.8%**
  off a self-compile, output byte-identical.
- The managed-string + heap runtime is **~47%** of a self-compile;
  `PXXStrFromLit` + its thunk is **17.1%**. Resolved through the compiler's own
  `.map`, with the `_start` gap disassembled rather than reported.
- **1.28x fpc 3.2.2** on the same file — inside this ticket's own 2x
  de-escalation band.
- The remaining `AppendChar` campaign is **not worth running**: 6/70 samples
  over six sites at one each. This is a measured negative, not an untried idea.
- `cpreproc.inc` already has `CPAppendRange` and uses it in its hot paths, and
  it does not execute in a Pascal self-compile at all. Its 72-site census was
  misleading twice over.

**HYPOTHESIS, explicitly not established:**

- *Why* 11,329 literal sites miss `EmitStaticLitHandle`. The guard reads
  `IRKind[node] = IR_CONST_STR`, so a literal arriving in another IR shape
  would miss — **read off one guard, never measured.** Attribute the call sites
  first; each carries its length and pool pointer in two `movabs` immediates.
- The July **3.406s** vs today's figures. Untouched. The one new datum is that
  the same binary and source move ~40% with load on this box (12,889 vs 18,303
  lines/s measured hours apart), so load plausibly explains much of it. Not a
  regression claim either way.

**NEXT STEP:** `perf-o-string-literals-still-allocate-at-11329-call-sites-despite-the-static-handle-pass`
(backlog, p65, unowned). It is the top item and it is self-contained.

**DO NOT** re-run the census-ordered call-site conversion; see the measured
negative above.
