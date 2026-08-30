---
track: A
prio: 40
type: feature
status: done
blocked-by: []
owner: frank-optimize
summary: "-O3 is the free tier for new passes precisely because nothing gates OptLevel>=3. As of 2026-08-30 it has 443 programs of csmith self-differential coverage (pxx -O0 vs -O2 vs -O3, zero MISCOMPILE_OPT) -- an oracle-free check no gcc-disagreement argument can touch. Proposes making it standing per new -O3 pass rather than a one-off."
---

# `-O3` now has differential coverage, and it should be standing

- **Track O** (work-tag) — **file-owned by Track A**, gated by A's rules, per
  CLAUDE.md's rule that an O ticket carries A's file ownership.
- **Found:** 2026-08-30 by frankC, running the csmith campaign. Filed rather than
  written into `devdocs/dev/optimization-architecture.md` because that file is
  A/B ground and Track O agents may be in it; **a line there is still the right
  permanent home** — see "What I am asking for" below.

## What now exists

`tools/csmith_fuzz.py --opts 0,2,3` ran for the first time on 2026-08-30, across
two batches:

| batch | seeds | complexity | agreed | skipped | `MISCOMPILE_OPT` |
| --- | --- | --- | ---: | ---: | ---: |
| A | 1-200 | default | 175 | 25 | **0** |
| B | 40000-40299 | full | 268 | 32 | **0** |

**443 comparisons, zero optimisation-level divergences.** Compiler
`f2bfbb3c94a5`, a self-host fixedpoint at HEAD `f278ddaca`.

Reproduce:

```sh
tools/csmith_fuzz.py --iters 300 --seed-start <unused> --opts 0,2,3
```

## Why this is the strongest kind of check available here, and specific to `-O3`

CLAUDE.md makes `-O3` the landing tier for new passes on an explicit basis:
it is *"a free tier — **nothing gates `OptLevel>=3` yet**"*, with promotion to
`-O2` per-pass only after the full gate. That freedom is the point, and the cost
of it is that a `-O3`-only miscompile has, until now, had **no differential
coverage anywhere in the repo**.

What the harness adds is not another oracle but a **self**-differential: it
builds the same csmith program at `-O0`, `-O2` and `-O3` with the same compiler
and compares the checksums. So:

- **No oracle is involved**, and therefore no "gcc is wrong here" conversation is
  available. A disagreement between our own `-O0` and `-O3` is a miscompile we
  own outright.
- **The programs are UB-free by construction** (csmith's whole premise), so a
  divergence cannot be dismissed as the test's fault either.
- It is **orthogonal to the corpora**. lua/zlib/sqlite are written by humans who
  avoid dark corners; this campaign's own history records nine bugs found in one
  sitting that *none* of those corpora could reach.

It cannot be argued with, only extended. That is a rare property and it is worth
knowing it now applies to the tier where the newest, least-exercised passes live.

## What this does NOT prove

443 dry programs narrow the space; they do not clear it. Both batches were
**x86-64 native** — a `-O3` pass with a backend-specific arm (the aarch64
peephole and register-allocator work, say) is untouched by this. `--target` works
and a cross batch is running as this is filed; until it reports, `-O3`'s
differential coverage is x86-64 only and should be described that way.

Nor does it substitute for the full gate on promotion to `-O2`. It is evidence a
pass does not miscompile the kind of code csmith writes, which is a narrower
claim than correctness.

## What I am asking for

1. **Record that this coverage exists** where pass authors will see it — one line
   in `devdocs/dev/optimization-architecture.md`, which I did not edit because it
   is not Track C's file. Someone holding A/B should add it.
2. **Make it standing rather than a one-off.** A new `-O3` pass is exactly the
   change this check is sensitive to, and it costs one command. Suggested shape:
   a batch of a few hundred at `--opts 0,2,3` in unused seed space when a pass
   lands in the free tier, with the seed range recorded so the next author does
   not re-walk it.
3. **Extend to cross targets** as `--target` batches come in, so a per-backend
   `-O3` arm is covered by the same oracle-free check.

Track T owns the harness; this ticket asks nothing of that file. It asks Track O
to adopt a check that already exists.

## 2026-08-30 (frank-optimize) — the cross batch was never run at `-O3`, and the new one is NOT vacuous

### The gap this ticket's item 3 names is wider than it says

`--opts` defaults to `0,2` (`tools/csmith_fuzz.py:595`). The aarch64 batch cited
in the csmith ticket's section D1 — `--target aarch64 --iters 150 --seed-start
300100` — **passes no `--opts`**, so *"136 ran clean across pxx `-O` levels"*
means `-O0` against `-O2`. **aarch64 has never had `-O3` differential coverage
at all**, while carrying 10 `-O3` gate sites by
`tools/check_o3_backend_parity.py`'s count. Filed as
[[bug-t-csmith-batch-records-do-not-state-which-o-levels-they-compared]],
because the wording will mislead the next reader whatever this run returns.

Running now: `--target aarch64 --opts 0,2,3 --iters 150 --seed-start 330000`,
compiler **`ba3d1a18edf6`** (rebuilt first — the binary on disk was three
compiler commits stale).

### First: is a green here worth anything? Rule 2 of the campaign, applied

A batch that never fires the passes is a vacuous green. Measured before
reporting the batch, so the answer does not depend on how it ends.

**Tier level:** aarch64 `-O2` and `-O3` binaries differ on all three probe
seeds, so `-O3` code paths are reached.

**Pass level**, counting the exact word the operand-staging fold skips
(`ldr x0,[sp],#16` = `$F84107E0`) in `.text`, decoded directly — aarch64 is
fixed-width, and local `objdump` has no aarch64 support even though the ELF has
9 section headers and an `AX` `.text`:

| seed | `-O` | instrs | staging pops | density | `ret` |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 330500 | 2 | 196550 | 7850 | 3.99% | 1677 |
| 330500 | 3 | 196550 | 1663 | **0.85%** | 1677 |
| 330501 | 2 | 196550 | 7856 | 4.00% | 1677 |
| 330501 | 3 | 196550 | 1664 | **0.85%** | 1677 |
| 330502 | 2 | 442310 | 20970 | 4.74% | 1701 |
| 330502 | 3 | 393158 | 5512 | **1.40%** | 1701 |

**Identical instruction and `ret` counts at both levels on the small seeds** —
so nothing is inlined away, function count is unchanged, and the 79% drop in
staging is the operand folds alone with the confound held fixed by the data
rather than by an argument.

**But those two rows do not say what they appear to.** Both small programs give
*exactly* 196550 instructions, because `.text` is dominated by the statically
linked RTL — so they measure the fold firing on **the RTL**, not on csmith's
generated code. Subtracting that common baseline from seed 330502 (1096 lines,
the only probe with a large program-specific part):

| | instrs | staging pops | density |
| --- | ---: | ---: | ---: |
| csmith code, `-O2` | 245760 | 13120 | 5.34% |
| csmith code, `-O3` | 196608 | 3849 | **1.96%** |

**71% of the staging in csmith's own code is eliminated at `-O3`.** So the batch
is non-vacuous at pass level too, and a clean result will be worth reporting.

**Two labels I got wrong and am recording rather than quietly fixing.** I first
called `mov x1, x0` (`$AA0003E1`) a control because both arms of the compare
fold emit it — it fell 74%, as fast as the thing it was controlling for, because
other `-O3` arms avoid the staging entirely. And neither stack word is exclusive
to operand staging; prologues use the same encodings. The numbers are a density
argument, not a firing count.

**Residual, and I own it:** this shows the *operand-staging family* fires. It
does not attribute firings to individual slices, and does not show that all 10
aarch64 gate sites are reached. A clean batch clears the family, not each site.

### Firing counts, and three numbers that were not measurements

The section above closes the *family* question by density. The per-slice
question has a real instrument — `PXXDBG` probes, one of which
(`ir_codegen_aarch64.inc:1256`) exists for exactly this reason and says so:
*"There is no aarch64 disassembler on a typical dev box, and a pass that
silently stops firing is invisible to every correctness check we own."*

On csmith seed 330502, `--target=aarch64 -O3`:

| probe | count | what it is |
| --- | ---: | --- |
| `a.w2` | **105** | a real firing count — the aarch64 in-place-ALU slice |
| `a.resid` | **2280** | real — residency decisions, both backends probed |
| `a.forinit` | **2** | real — `ir.inc`, shared |
| `a.a64binop` | 18778 | **a POPULATION, not firings.** The comment says `REPORT ONLY` |
| `a.w1left` | 0 | **meaningless here** — its only live site is in `ir_codegen.inc`, x86-64 |
| `a.w1cmp32` | 0 | same |
| `a.reload` | 0 | **no live probe exists** — two text mentions, zero `PxxDbgEnabled` sites |

**Four of those seven rows are not what they look like, in four different
ways**, and every one of them answers rather than erroring: a population read as
a result, two probes belonging to the other backend, and one probe that no
longer exists. The check that separates them is one grep —
`grep -rc "PxxDbgEnabled('<tag>')" compiler/` — and which FILE the site is in.

**So the honest residual is narrower and sharper than I banked above.** csmith
code at `-O3` on aarch64 provably fires W2 (105) and exercises residency (2280).
**The aarch64 compare fold and the widen fusion — the two slices this session
landed — have no probe at all**, so whether csmith reaches them is not merely
unmeasured, it is unmeasurable with the instruments in the tree. Adding a probe
to each is the obvious next step and it is cheap; I am naming it rather than
doing it under this ticket, since it is campaign work, not coverage work.

### Provenance of the binary under test

`ba3d1a18edf6` is a **binary sha256**, not a commit. The commits in it that
matter, all verified ancestors of HEAD:

- `ba99a4e81` — generic method body / `try`+`asm` `end`-counting fix
- **`f370bb085` — the shared-IR control-flow rewrite the pin is held on**
  (`IRMarkReachableLabels`, `IROptDeadCode`'s own fixpoint deleted, strictly
  more deletion than before)
- `931b43ae0` — `MAX_GENERIC_METHODS` 512 → 2048

That makes this batch incidental evidence about `f370bb085`: a control-flow-heavy
generator against a brand-new dead-code eliminator. **It is not a substitute for
the queued full tier** — different question, different matrix — but it was not
commissioned for it, which is worth stating plainly rather than letting it be
read as coverage it is not.

### RESULT — aarch64 `-O3` differential coverage, the first there has ever been

```
tools/csmith_fuzz.py --target aarch64 --opts 0,2,3 --iters 150 --seed-start 330000
```

**129 agreed with the gcc oracle, 21 skipped, ZERO findings.** No
`MISCOMPILE_OPT`, no `MISCOMPILE_VS_GCC`, no `PXX_CRASH`, no
`PXX_COMPILE_FAIL`, no `PXX_TIMEOUT`. Compiler `ba3d1a18edf6` (provenance
above). Seeds **330000-330149**, previously unused.

**Stating the scope, since that is this ticket's whole subject:**

- **`-O3` WAS built** — the run header reads `pxx -O{0,2,3} --target=aarch64`,
  which is the line the T ticket asks the harness to always print.
- **21 skips = 14%**, every one *"the native validity filter could not build/run
  it"* — csmith programs gcc itself would not take, so they never reached pxx.
  Comparable to D1's 9%. **A skip is scored passlike**, so 129 is the
  denominator that means anything, not 150.
- **The slow ratio is NOT CHECKED**, and the harness says so itself: the oracle
  matched aarch64's *data model*, not its ISA, and ran natively. Timing across
  an emulation boundary is not a comparison anyone should make.
- The pass-level reach is the section above: W2 fires 105 times per program,
  residency 2280; the two slices this session landed have no probe and are
  therefore not covered by any claim here.

**What this closes and what it does not.** Item 3 is done for aarch64: the
backend that carries 10 `-O3` gate sites now has oracle-free differential
coverage at that tier, where it had none. It does not close arm32 / riscv32 /
i386 — those are ILP32 and belong to the D3 class, a different evidentiary
question — and it does not make the tier proven; 129 dry programs narrow the
space, they do not clear it.

### The residual is CLOSED: both unprobed slices fire on csmith code

Two probes written, measured with a **scratch** build (`./compiler/pascal26
compiler/compiler.pas $SCRATCH/p26-probe`) so the x86-64 batch running against
`compiler/pascal26` never saw its binary move. On csmith seed 330502,
`--target=aarch64`:

| `-O` | cmp site reached | **folded** | widen **fused** |
| ---: | ---: | ---: | ---: |
| 0 | 2867 | **0** | 0 |
| 2 | 2891 | **0** | 0 |
| 3 | 2903 | **485** | **6** |

**Both slices this session landed fire on csmith code**, so the clean
150-program batch above is coverage for them and not merely for the family.
Compare fold (slices 5+7, which collapse into one arm on aarch64): 485 firings,
16.7% of the sites it sees. Widen fusion (slice 10's aarch64 twin): 6.

**The probes are built so a zero cannot be ambiguous, which is the whole lesson
of the four false rows above.** Each prints on *every* call with
`folded=`/`fused=` TRUE or FALSE, so the ~2900 `FALSE` rows are a standing
positive control: the instrument is demonstrably able to print both values, and
a total of 0 would mean *the site was never reached* rather than *no probe
exists*. The `-O0`/`-O2` rows are then the gate control, and they are exactly 0.
`a.reload` could never have produced a table like this — it has no call site, so
its only possible output is the one that looks like a firing count of zero.

**Parked as a patch** (`git diff -- compiler/ir_codegen_aarch64.inc > …patch`,
then `git checkout --`), not a file copy, and lands once the batch releases the
compiler — the per-fix loop needs `make compiler/pascal26`, and running that
mid-batch would swap the binary underneath 300 programs and produce a result
measured against no particular compiler, with nothing on disk to show it.

**Noted, not filed** (coordinator's call): the separator that sorts a real probe
from the four kinds of non-probe is one command —
`grep -rc "PxxDbgEnabled('<tag>')" compiler/` plus which file the site is in.
Running it over every `PXXDBG` tag in the tree is cheap and nobody has.

### RESULT — x86-64 `-O3`, re-established against the CURRENT binary

```
tools/csmith_fuzz.py --opts 0,2,3 --iters 300 --seed-start 340000
```

**258 agreed with the gcc oracle, 42 skipped, ZERO findings.** Seeds
**340000-340299**, compiler `ba3d1a18edf6` — unchanged for the whole run, which
is the property the result depends on and the reason no rebuild happened while
it was in flight.

**This is not "443 + 258".** The 443 was measured against `f2bfbb3c94a5` and is
evidence about that binary; this is evidence about `ba3d1a18edf6`. They do not
add. **Two clean batches on one backend are the same evidence with a bigger
denominator**, not twice the evidence — and 42 skips (14%) means 258 is the
denominator, not 300.

### The probes LANDED — and the control that nearly produced a false alarm

`8d44c9754`. Both are inside `PxxDbgEnabled`, so the claim that they cannot
change codegen is sound — and it was checked anyway, which is the right
relationship between an argument and a cheap test.

**The check first said they DID change codegen.** Whole-file `cmp` of a
`-g` build, probe compiler vs no-probe compiler: 384 bytes apart. Section by
section, the truth: **`.text` byte-identical**, `.data` identical, `.bss`
identical — the entire difference was **`.debug_line`**.

Then the discriminator, and it exonerates the probes completely: a **stage-1
build WITH the probes** emits `e79b4908…`, byte-for-byte what the **no-probe**
build emits. Probe and no-probe are indistinguishable; what differed was
something else entirely.

**It is `argv[0]`.** The same byte-identical binary, same source, same flags,
same output path, invoked three ways:

| output | invocation |
| --- | --- |
| `d17ef8a29b32d82f` | `./compiler/pascal26` |
| `a7a9eba654ee6237` | `/home/neo/frank-optimize/compiler/pascal26` |
| `e79b49081c9e0b68` | `$SCRATCH/p26-probe-s1` (byte-identical to the first) |

**Known, deliberate, and not a bug**:
[[bug-a-the-compilers-output-depends-on-argv0]] (done, `3b0a886e9`) fixed the
emitted string pool via `KeyStrs` and scopes this out in as many words —
*"Debug info (`-g`) records real source paths by design and is not in scope
here."*

**The reusable caveat, and it lands on the technique this ticket has been
recommending all evening:** a **`-g` build cannot serve as a byte-comparison
control between two compilers at different paths**, and the scratch-build
technique *always* puts them at different paths. Compare `.text`
section-by-section, or invoke both through equal-length paths. I was one step
from reporting "my debug-only probe changed codegen", and the thing that caught
it was refusing to accept a whole-file `cmp` as an answer about code.

## Log
- 2026-08-30 — resolved, commit 9b745f37c.
