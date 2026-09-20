# Why does pxx take two minutes on lekkerzeilen?

**Lane:** build-time profiling (franks-5b, opened 2026-09-20 at the owner's ask,
relayed by frankuser: *"why our compiler takes 3 minutes on that source"*).
**Deliverable is measurement.** The owner's framing, verbatim: *"the frank doing
this can take all night and just study results."* A commit is optional; a number
without its population is not a result.

## The headline, and it corrects the number that opened the lane

**The compile alone is 125 s, not 3m17s and not 2m50s.**

    R1  131.75 s   (no load sample)
    R2  132.60 s   load1 3.73/4.65/4.87   runq 2/5/12
    R3  132.75 s   load1 3.45/4.02/4.56   runq 2/5/12
    R4  124.97 s   load1 2.40/3.08/3.54   runq 2/4/7     <- min-of-N

**Population, tree and oracle**, without which the number is unquotable:

| | |
|---|---|
| compiler | `/home/neo/frank-user/compiler/pascal26`, sha256 `55f1ef09492bf17e…` |
| compiler built at | pxx `7caadced1`, `converged after 1 round(s)` — a real rebuild, not the stamp path |
| optimisation | **default `-O`** — no `-O` flag in the invocation, not `pxx-debug`, so this is not a `-O0` number |
| CWD | `/home/neo/frank-user` — the compiler's own repo root, NOT the demo tree |
| source | `/home/neo/lekkerzeilen/lekkerzeilen/__main__.py`, ~35 modules, demo tree `8ca634f` |
| invocation | lifted verbatim from `runbin.sh`: `--threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES` |
| estimator | min of four runs, box load sampled for exactly each run's duration |
| output | `ok: […code=12047464B data=633524B bss=226823164B procs=11594 codeseg=12050032B]` |

The demo tree had moved from the `98b9f65` frankuser measured to `8ca634f`.
**Checked rather than assumed:** all five intervening commits are docs, `git diff
--stat 98b9f65..8ca634f -- '*.py'` is empty, and the `code=`/`procs=` figures
reproduce frankuser's `build.log` last line exactly. Same program.

**The CWD is load-bearing and is not incidental.** A pxx binary run from a
sibling checkout silently compiles THAT tree's `compiler/builtin/**` into its
output — twenty such checkouts exist on this box. The invocation is therefore
recorded with its CWD, and any re-run from elsewhere is measuring a different
program.

## Where 3m17s came from, and why the correction was still wrong

`time BUILD=1 ./runbin.sh --shot <png> --for 20 --throttle 0.8` — which
**compiles, then runs 20 s of simulation, then writes a chart** (3.4 s, it prints
its own line). One stopwatch reading, one run, no repetition, on a box with other
seats working. `bin/build.log` carries no timestamps, so nothing is recoverable
from it.

frankuser caught the contamination itself and corrected the figure to ~2m50s by
subtracting the run and the chart. **That correction overshoots the real number
by 29%,** and the reason is the finding:

> **A SUBTRACTION IS NOT A MEASUREMENT.** Removing known components from a
> composite gives a number that *looks* measured and carries none of a
> measurement's properties: it inherits every error in the total, adds the error
> in each estimated part, and — the part that bit here — **it silently inherits
> the conditions of the original run**, including a loaded box, while presenting
> as a clean figure. It also cannot be checked, because there is no second
> observation to disagree with it.

Three seats quoted the derived figure, through two hops and one correction, and
**the compile had never once been timed on its own.** The fix was one command.
When a composite is all you have, say so and time the part you care about.

## What the number means — the actual question is superlinearity

| | procs | `code=` | compile |
|---|---|---|---|
| pxx compiling **itself** | 4,950 | 7,887,757 B | ~12 s |
| pxx compiling **lekkerzeilen** | 11,594 | 12,047,464 B | **125 s** |
| ratio | 2.34x | 1.53x | **10.4x** |

**2.3x the procs for 10.4x the time.** That is the question this lane exists to
answer, and it is now resting on a measured number rather than a subtracted one.
Compare `backlog-cfront/perf-c-parse-codegen-large-file-superlinear.md`, which
found ~1.5x worse than linear on sqlite3.c and recorded that no phase timing
exists to split it further.

**Verified, not inherited: there is still no phase timing.** No clock primitive
anywhere under `compiler/` (all depths), no timing flag in `--help`. The
superlinear ticket said so on 2026-07-08 and it is still true at `47d65eae1` —
checked before adopting the gap, because a worked example decays faster than the
rule it illustrates.

## Open, in order

1. Split the 125 s across parse / IR-build / codegen / ELF. No instrument exists.
2. Sampling profile of the shipping configuration — **not** `make pxx-debug`,
   which forces `-O0`; and `-g` alone silently means `-O0` too.
3. Whether the superlinear term is the same one `perf-c-…-superlinear` saw.

## Hazards already paid for by someone else

- **`--shot FILE --for S` is not a frame-rate benchmark** (8e): its loop ticks
  simulation only and renders exactly once, after the loop, `present=False`. A
  profile of it is a profile of the simulation. `SDL_VIDEODRIVER=offscreen
  ./bin/lekkerzeilen --silent` runs the real loop and needs no display.
- **`ptrace_scope` is 1**, so gdb cannot attach to a running process. gdb-as-parent
  works and needs no permission. **Do not change the sysctl** — that is a guardrail
  and loosening one is the owner's call.
- **`handle SIGUSR1 stop nopass noprint` silently takes zero samples** (8e):
  gdb's `noprint` implies `nostop`, so the trailing keyword cancels the stop.
  Controls both ways: `TAKEN=3` without it, hangs at 0 with it.
- **A name is not provenance** (7a): `bin/lzfix` is a different build from the
  archived `lzfix` of the same name, and the compilers that built that week's
  binaries **no longer exist** — `pascal26` is overwritten in place. Resolve every
  arm by `.prov` or by `sha256sum`, never by path.
- **`.symtab` is empty even under `-g`**, so `nm` reports nothing; `pinned prog
  out` also writes `out.map`. Nearest-preceding-symbol always answers, so print
  the offset and disassemble anything not plausibly inside a body.

---

# FOUND: an imported module costs ~13x per function what the same code costs inline

**And the cost does not depend on anything referencing it.**

## The measurement

Identical function bodies, written two ways: all in the main `.npy`, or moved
verbatim into one module that main imports. Same compiler, same CWD, same flags,
back to back.

| functions | inline | through 1 import | ratio |
|---|---|---|---|
| 100 | 2.79 s | 6.81 s | 2.4x |
| 200 | 2.95 s | 11.41 s | 3.9x |
| 400 | 3.75 s | 20.35 s | **5.4x** |

Net of the 2.40 s fixed cost, per function: **inline ~3.4 ms, imported ~45 ms.**
Both linear in the function count over this range; the ratio grows only because
the fixed term is a shrinking share of the inline arm.

**The output is the same program.** 400 functions, inline against imported:

    inline    code=1809848B  data=129204B  procs=2624
    imported  code=1809866B  data=129292B  procs=2625

18 bytes of code and one proc apart — and **5.4x the time to produce it.**

## The discriminator: an UNREFERENCED import costs the same

`main.npy` = `import mod0` + `print(1)`, touching nothing in the module:

    unused-import  WALL 20.08 s      (referenced: 20.35 s)

**So this is not name resolution, not lookup, not per-reference work.** The cost
is incurred by compiling the imported module at all. That is what makes it a
clean target: nothing about the importing program's use of the module changes it.

## Module count is LINEAR — it is the per-module rate that is wrong

K=400 functions per module, varying the number of modules:

| modules | wall | s/module |
|---|---|---|
| 1 | 20.13 s | 20.13 |
| 2 | 38.64 s | 19.32 |
| 4 | 78.19 s | 19.55 |
| 8 | 170.37 s | 21.30 |

Flat. **There is no cross-module quadratic**, which is the reassuring half: the
architecture scales, the per-module constant is 13x too big.

**This inverted my prediction and that is why it was worth running.** I expected
splitting to HELP, on the theory that the single-file quadratic below was the
mechanism. The same 3200 functions take 53.25 s in one file and 170–173 s spread
over eight modules — **3.2x worse, not better.** I had a reason and the reason
was wrong; one experiment cost four minutes.

## NARROWED: it is the DECLARATIONS, not the bodies

Same 400-function imported module, bodies emptied to `pass`:

| module contents | wall |
|---|---|
| 400 `def`s, real bodies (4 lines each) | 20.11 s |
| 400 `def`s, `pass` bodies | **17.81 s** |

**Emptying every body saves 2.3 s of 20.1 s.** 88% of the cost survives the
removal of all body content, so the ~44.5 ms is charged **per declaration** and
is spent at registration rather than in parsing or lowering a body.

That is what a profile should be pointed at, and this is a better subject than
anything in the demo: deterministic, headless, no display, 18 seconds.

**Note what this does NOT say.** It does not say the work is redundant, and it
does not name a routine. `UCls`-scanning appears in two open correctness tickets
(`feature-n-register-the-class-shells-…`, `feature-n-register-every-module-s-classes-…`)
and the temptation is to connect them — but this reproducer declares no classes
and makes no method calls, so any such link is a guess and is recorded here as
one, not as a finding.

## A SEPARATE, SECOND effect: single-file compilation is near-quadratic

Everything above is linear. Within ONE file, it is not — N functions in one
`.npy`, net of the 2.40 s fixed cost:

| N | variable | ratio | implied exponent |
|---|---|---|---|
| 100 | 0.20 s | — | — |
| 200 | 0.42 s | 2.10 | 1.07 |
| 400 | 1.16 s | 2.76 | 1.47 |
| 800 | 3.76 s | 3.24 | 1.70 |
| 1600 | 13.63 s | 3.62 | 1.86 |
| 3200 | 50.85 s | 3.73 | **1.90** |

Converging on 2. Below ~400 functions the per-function cost is flat at ~3.4 ms,
so **this term is invisible at the sizes real modules have** and does not explain
lekkerzeilen. It is filed as its own finding because a 3200-function file is a
generated-code shape someone will eventually produce. It is plausibly the same
term `perf-c-parse-codegen-large-file-superlinear` saw on sqlite3.c.

## What this says about the 125 s

lekkerzeilen is ~35 modules, every one of them imported. **The dominant term in
the owner's flagship demo is the one measured above**, and it is a per-module
constant rather than anything about the program's size or shape. Nothing here
identifies WHERE inside the import path the time goes — that needs the sampling
profile, and the profile is the next step, not a conclusion I am drawing now.

**Not yet measured, and each would sharpen the ticket:** whether the cost tracks
declarations, lines, or bytes rather than function count; whether a module with
one function and 400 statements behaves like one with 400 functions; whether
class-heavy modules differ from function-heavy ones; and whether `.pas` imports
show the same rate or only `.npy` ones.

## Fixed cost: 2.40 s, and it is NOT the story

A zero-byte `.npy` — the whole NilPy runtime, `pylib.pas` + `pyeval.pas`:

    2.48 / 2.45 / 2.40 s      code=1384312B  procs=2224

**1.9% of the 125 s.** I went looking for a large fixed term because of a rule I
had written the same evening about fixed additive terms setting ceilings, and it
is not there — `bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost` is in
`done/` and stayed fixed. Recorded because a refuted hypothesis is worth exactly
one line to the next person who has it.

---

# PROFILED — and my pre-registered hypothesis was refuted

**Pre-registered before looking** (`scratchpad/PREREG.txt`, 20:18): the
declaration-registration story would be CONFIRMED by >=25% of samples in
symbol/declaration registration, and REFUTED by (a) >=25% in lexing or parsing,
(b) >=25% in codegen/ELF, (c) no bucket above 10%, (d) >=25% UNATTRIBUTED.

**Criterion (a) fired.** Registration accounts for essentially nothing; the mass
is in reading and re-reading the module's tokens. Stated plainly because the
whole point of writing it down first is not to reinterpret it afterwards.

## The differential — same 400 defs, inline versus through one import

Both arms: `tools/pxx_pc_sample.py` (frankb-8e), 100 samples, thread 1, flat
self-time, compiler `2d692164aea6` with its own freshly emitted map.

| symbol | imported (21.2 s) | inline (3.8 s) | absolute ratio |
|---|---|---|---|
| `GetTokenStrFromRaw` | **16%** = 3.39 s | 3% = 0.11 s | **~30x** |
| `PyFindSuiteIndent` | **13%** = 2.76 s | **absent** | — |
| `PXXAlloc` | 11% = 2.33 s | 6% = 0.23 s | ~10x |
| `PXXFree` | 10% = 2.12 s | 5% = 0.19 s | ~11x |
| `PyDefUsedAsValue` | 9% | 3% | ~17x |
| `GetTokenStr` | 6% | 2% | ~17x |
| distinct symbols | **20** | **46** | — |

**The two arms have different SHAPES, not different sizes.** The inline profile
is diffuse — 46 symbols, nothing above 11%, work spread across parse, IR and
emit, which is what compiling 400 functions is supposed to look like. The
imported profile collapses onto token-string extraction, suite scanning and the
allocator: **`GetTokenStrFromRaw` + `GetTokenStr` + `PXXAlloc` + `PXXFree` = 43%
of a run that is 5.6x longer.**

**`PyFindSuiteIndent` at 13% against zero is the sharpest single signal**, and
it is not a slow routine. `pyparser.inc:39422` is a bounded scan that stops at
the end of the construct's header — deliberately so, per
`bug-nilpy-def-body-scans-run-on-when-no-indent-is-found`. A cheap bounded scan
taking 2.76 s means **it is being CALLED an enormous number of times. The count
is the defect, not the walk.**

## What is measured and what is inferred — the line matters here

**MEASURED:** every number above; that the effect reproduces on a second
compiler (`2d692164aea6`, 5.6x, against frankuser's 5.4x); that an unreferenced
import costs the same as a used one; that emptying bodies saves 12%.

**INFERRED, and NOT established:** that a whole-module inference or site-analysis
pass runs over imported modules and drives those calls. It fits — `PyDefSiteMode`,
`PyDefUsedAsValue`, `PyParamTypeFromSites` all surface in the imported arm, and
`PyFindSuiteIndent`'s callers at `:42514` and `:42766` sit in `PyInferHdrHi` —
but **flat self-time has no caller information at all**, so this is a hypothesis
shaped like a conclusion. Anyone acting on it should confirm the call counts
first.

**The question that follows is sharp and cheap:** the inline arm compiles the
identical 400 definitions. Whatever re-reads those tokens 30x is work the inline
path does not need — so what does an import require that inlining does not?

## Method notes worth keeping

- **A map is only valid for the exact binary that emitted it and nothing in the
  file records which.** The only map beside `compiler/pascal26` was
  `pascal26-debug.map` dated **22 days earlier**; it would have resolved every
  address and been wrong about all of them, with plausible pxx-internal names.
  8e's tool refuses on it (exit 2) rather than running. I generated a fresh map
  by building my OWN compiler — **not frankuser's, because `make` would have
  replaced the binary another seat is using.**
- **Profiling a different compiler answers a different question**, so the 13x was
  re-measured on the compiler actually being profiled before any sample was taken.

---

# CONTROLLED A/B for frankb-8e's decider work — and it is a 20% BUILD-TIME WIN

Run at 8e's request because it would have been marking its own homework. **One
tree, one CWD, both binaries in-tree under distinct names, only the compiler
differs.** Each arm's `--where` checked for `MISSING` roots first and both report
the same count, which is the discharge from the relocated-binary section below
applied to its own author.

| | `24c2f18de` (pre-widening) | HEAD (`0c508e507` + `1fbe6e104`) |
|---|---|---|
| `code=` | 12,047,464 B | 12,159,489 B (**+0.93%**) |
| `data=` | 633,524 B | 633,716 B |
| `procs=` | 11,594 | **11,594 — identical** |
| compile, interleaved | 130.70 / 130.95 s | **104.15 / 104.19 s** |

**Two independent results, and the second was unmeasured by anyone.**

**Size: 8e's uncontrolled figures reproduce EXACTLY under control.** +0.93% with
`procs` unchanged — so no wrappers were added and the growth is boxing inside
bodies that already existed, which is what its ticket claims. It marked that
comparison uncontrolled because its before-row came from another seat's build 44
commits back; controlled, it lands on the same numbers.

**Time: HEAD compiles lekkerzeilen 20.3% FASTER — 130.70 s to 104.15 s, min-of-N,
interleaved, 26.5 s saved.** 8e predicted its memoisation would move my synthetic
benchmark by **zero** and it did (0.2%, 400 plain defs, no classes). It never
measured the class-heavy target, which is the only place the fix can act. **The
memoisation more than repays the widening that prompted it.**

**So the headline number for this lane moves: the demo now compiles in ~104 s at
HEAD**, against the 125 s measured on `55f1ef09492b`. Both rows stand with their
own populations; neither refutes the other.

**Attribution stated because I nearly got it wrong in the other direction
earlier tonight:** this delta is 8e's, not mine, and I have measured a RANGE of
two commits rather than one. Which of the pair carries the 20% is not separated
here — the widening alone would be expected to cost time, so the memoisation is
plausibly worth more than 26.5 s on its own. That decomposition is unrun.
