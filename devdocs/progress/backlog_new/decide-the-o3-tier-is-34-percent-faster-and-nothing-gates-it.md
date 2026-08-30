---
track: U
prio: 65
type: decision
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, probing the per-call cost driver behind feature-opt-nilpy-container-subscript
summary: "The compiler built at -O3 compiles compiler.pas 34% faster than the same compiler built at -O2, produces byte-identical output, is 3.3% smaller, and reaches a self-host fixedpoint in zero rounds. NilPy programs run 17-26% faster. -O2 is the default and -O3 is the untested tier, so the whole gap is currently unclaimed. The fork is what to do about it: promote per-pass as policy says, promote the tier wholesale, or change what the dev loop builds. Not a fork an agent should settle."
---

# The `-O3` tier is 34% faster than `-O2`, and nothing gates it

## The fork

`CLAUDE.md` (Track O): *"New passes land behind `-O3` (a free tier — nothing
gates `OptLevel>=3` yet) and promote to `-O2` per-pass only after the full gate;
`-O2` stays the proven default."*

That policy is sound and it has a cost nobody has priced until now: **the
promotion backlog is worth 34% of the compiler's own runtime.** Every lane's
`make compiler/pascal26` — the one mandatory step in the per-fix loop, run
dozens of times a session by every agent — is paying it.

I am not settling this. It is a risk/benefit call about the *default* build of
the toolchain, which is the owner's, and the options differ in kind rather than
degree.

## Measured — HEAD `4990bfc3efee`, binary `869fe2330c45`, x86-64

Every number is min-of-N interleaved A/B (both halves back to back, alternating,
minimum taken) rather than a mean, because the box is shared and contended; the
minimum is the least-disturbed run and a mean is mostly a measure of the other
agents. Box load is recorded per row. There is **no profile behind any of these**
— see "On instruments" below.

### The compiler compiling `compiler.pas` (real Pascal, 37k+ lines)

| compiler built at | min of 3 | binary size |
| --- | ---: | ---: |
| `-O2` | 21.69 s | 10,293,928 |
| `-O3` | **14.40 s** | **9,958,056** |

**34% faster and 3.3% smaller.** Load 9.51 → 7.89; all three pairs agreed in
direction (21.69/16.56, 21.81/14.40, 22.57/16.92). Re-measured earlier at a
different sha under load 5.1: 18.14 → 13.53, ratio 0.746. Two shas, two load
regimes, same answer.

### NilPy programs (min of 5 interleaved, load ~8)

| program | `-O3` / `-O2` |
| --- | ---: |
| call-heavy (`t = work(i)` in a loop) | 0.743 |
| list subscript (`t = b[2]`) | 0.834 |

At an earlier sha, min-of-7 at load ~4: 0.833 / 0.843 / 0.850 across
call-heavy, bare-loop and subscript. **The win is uniform across construct**,
which is what says it is baseline code quality rather than one pass catching one
shape.

### Where it does *not* help

A trivial Pascal integer loop (`Step(x) = (x*3+7) mod 1000003`, 40M calls) is
**1.000** — no change at all. So the win is not "Pascal code gets faster"; it is
*routines with many locals, pointers and comparisons* getting faster, which is
what the RTL and the compiler are made of and what a 3-op arithmetic function is
not. I had this backwards for one measurement and it is an easy mistake to
repeat: a microbenchmark that shows nothing here is not evidence of nothing.

### What `-O3` actually changes in the emitted code

Statically, on one NilPy binary:

| | `-O2` | `-O3` |
| --- | ---: | ---: |
| `movabs $0x0` (10 bytes, to materialise zero) | 141 | **3** |
| `push %rax` | 15,249 | **11,342** |
| `rep stosb` / `rep movsb` | 1457 / 1492 | 1457 / 1492 (unchanged) |

The hot RTL routines at `-O2` spend **twelve instructions and three stack
round-trips on `if p = nil`** — load the param, `push`, a 10-byte `movabs $0`,
`mov`, `pop`, `cmp`, `sete`, `movzbq`, store the bool to a stack slot, reload it,
`test`, `je`. Sampling a NilPy call benchmark (700 samples) put **~55% of total
runtime in routines shaped exactly like that**, which also explains the uforth
profile's "134 routines, no peak": the cost is flat because *every* routine is
built this way, so no single one stands out.

## Correctness evidence — real, and NOT a substitute for a gate

- **`-O3` reaches a self-host fixedpoint in ZERO rounds.** `E1 = pxx -O3 src`,
  `E2 = E1 -O3 src`, `E3 = E2 -O3 src` — all three are `96d63cb4dd4a`. The
  default build needs one round to converge; `-O3` is already at its fixedpoint.
- **The `-O3`-built compiler produces byte-identical output to the `-O2`-built
  compiler** on `compiler.pas`, the largest Pascal input in the tree.
- Six programs (4 NilPy, 2 Pascal) produce identical output at `-O2` and `-O3`.

**And that is nowhere near enough.** `CLAUDE.md` is explicit that the self-host
fixedpoint proves byte-identity *at one optimisation level only*, and cites a
`-O0`-only self-compile failure that passed the entire gate on 2026-08-19 and
was found by a benchmark. Six programs and one fixedpoint is the same class of
evidence. **Nothing here says `-O3` is correct**; it says `-O3` is not obviously
broken, which is what you would expect of an untested tier either way.

## The options, and what each costs

1. **Per-pass promotion, as policy says.** Safest, and the policy exists for
   good reasons. Cost: there are ~25 `OptLevel >= 3` sites across
   `ir_codegen.inc`, `ir_codegen_aarch64.inc`, `ir.inc`, `symtab.inc`,
   `emit.inc` and `inline_expand.inc`; promoting them one at a time, each behind
   a full gate, is many sessions. The 34% stays unclaimed throughout.
2. **Gate the tier, then promote wholesale.** Ask Track T to run its full and
   cross matrices against an `-O3` build. If that is green, the per-pass ceremony
   is buying much less than it costs. This is the option I would take, because it
   converts an unbounded backlog into one measurement that a machine already
   does nightly.
3. **Leave `-O2` the default but build the DEV LOOP's compiler at `-O3`.**
   Tempting — 34% off the one mandatory step, today. **I recommend against it**
   and want to be explicit about why: the dev loop's binary IS the artifact under
   test, so a lane would be gating its work on a compiler built by an untested
   tier, and a `-O3`-only miscompile would surface as a mysterious failure in
   someone else's lane. It trades a known cost for an unbounded one.
4. **Do nothing, deliberately.** Legitimate. If so, this ticket should be closed
   with the reasoning recorded, because the measurement will otherwise be
   rediscovered — that is exactly how the `PXX_FLAG_STATIC` follow-up got
   re-derived from a disassembly today after already having landed.

Recommendation: **option 2**, and it costs one Track T request rather than a
campaign.

## On instruments

The coordinator's standing note is that `perf_event_paranoid` is 4 here, so
`perf` is unusable and lanes should plan on A/B rather than profiles. The first
half is right; **the second is not, and it is worth correcting fleet-wide**:
`gdb` SIGINT-sampling works on this box and produced the 700-sample profile
above. Three settings are required and **missing any one yields zero samples
with no error** — `set startup-with-shell off` (otherwise the inferior is gdb's
grandchild and your signals hit the shell; find it with `pgrep -x <basename>`,
not `pgrep -P`), `handle SIGINT stop nopass` (without `nopass`, `continue`
re-delivers the signal and the program dies after one sample), and alternating
`printf "SAMPLE %#lx\n", $pc` with `continue`, one pair per sample, signalling
the inferior on a timer. Attribute by collecting every `call 0x...` target from
`objdump -d` and bucketing each `$pc` to the greatest entry below it.

Two failure modes that cost me time today, both of which report a *plausible
wrong answer* rather than an error: `objdump -d` on a binary built **without
`-g`** emits three lines and no instructions, so any pattern count over it is
silently **0**; and a binary that failed to build gives the same 0. Print
`NOSECT` / `NOBIN` and never let a count default to zero — on this box the
zero always looks like the result you were hoping for.

## Gate

None proposed — this is a decision, not work. The work that follows it depends
on which option is chosen, and options 1 and 2 have very different gates.
