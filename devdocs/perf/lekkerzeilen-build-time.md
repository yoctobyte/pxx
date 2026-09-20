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
