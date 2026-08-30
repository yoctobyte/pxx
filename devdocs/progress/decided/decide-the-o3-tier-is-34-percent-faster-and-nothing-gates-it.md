---
track: U
prio: 65
type: decision
blocked-by: []
status: new
owner: ""
found: 2026-08-30
found-by: frank-optimize, probing the per-call cost driver behind feature-opt-nilpy-container-subscript
summary: "-O3 was 28-34% faster than -O2 on the compiler's own workload. ~78-82% of that was ONE pass -- EmitStaticLitHandle / EmitStaticLitHandleA64, the static string-literal handle -- PROMOTED to -O2 in 440c822e6a80 (both backends; quick gate green, full+cross sweep requested from frankT, not pin-eligible until it returns). MEASURED AFTER: the remaining -O3 gap is ~5-7%, real (7 of 9 paired runs) but at the edge of what a contended box resolves. The campaign is effectively over -- the rest does not justify per-pass promotion at this measurement precision. -O1 limbo untouched."
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

### What `-O3` changes in the emitted code — CORRELATION ONLY, see the correction below

**CORRECTED 2026-08-30, same session, before this ticket was acted on.** The
counts in this section are real and were measured correctly. The sentence that
followed them — that this code-shape improvement *is* the win — was an
assertion I could not then demonstrate, and attempting to demonstrate it
falsified it. Read this section as "what differs", never as "why it is faster".
The attribution attempt is in "Why no pass can be named" below.

Statically, on one NilPy binary:

| | `-O2` | `-O3` |
| --- | ---: | ---: |
| `movabs $0x0` (10 bytes, to materialise zero) | 141 | **3** |
| `push %rax` | 15,249 | **11,342** |
| `rep stosb` / `rep movsb` | 1457 / 1492 | 1457 / 1492 (unchanged) |

The hot RTL routines at `-O2` spend twelve instructions and three stack
round-trips on `if p = nil` — load the param, `push`, a 10-byte `movabs $0`,
`mov`, `pop`, `cmp`, `sete`, `movzbq`, store the bool to a stack slot, reload it,
`test`, `je`. Sampling a NilPy call benchmark (700 samples) put ~55% of total runtime in
routines shaped like that. That the profile is flat — the uforth ticket's "134
routines, no peak" — is consistent with a uniform baseline cost, but consistency
is not attribution and I stopped calling it one.

## THE PASS IS NAMED — this supersedes the section below

**2026-08-30, same session, third and final revision of this ticket.** I said
first that the win was a code-shape improvement (wrong), then that no single
pass reproduced it (also wrong, and I had already sent that upward). It is one
pass, and I found it by **diffing emitted code instead of timing anything** —
which is what I should have done before writing either earlier claim.

**`EmitStaticLitHandle` — `compiler/ir_codegen.inc:3480`, gated `if OptLevel < 3
then Exit;`.** This is the `PXX_FLAG_STATIC` work. A string literal becomes its
static `.data` block plus a four-byte `inc qword [rax-16]`, replacing a heap
allocation, a copy, and an eventual free **on every evaluation**.

### Measured — promoting that ONE gate to `-O2`

Compiling `compiler.pas`, min of 5 interleaved, load 9.7 -> 10.1:

| compiler | min | vs `-O2` |
| --- | ---: | ---: |
| `-O2` (baseline) | 20.23 s | — |
| **only `EmitStaticLitHandle` promoted** | **16.23 s** | **20%** |
| every `-O3` gate promoted | 18.06 s | 11% |
| `-O3` | 14.54 s | 28% |

**One pass is ~71% of the whole tier.** All five reps agreed in direction
(22.20/18.34, 20.23/16.23, 21.41/18.18, 23.01/18.15, 21.74/16.69) — this is not
a noise-limited result the way the per-group zeros below were.

**And promoting everything at once is WORSE than promoting this one alone**
(18.06 vs 16.23). The passes interfere: enabling the scratch-register arms
changes eligibility for others. That is a real caution for any promotion
campaign — promote and measure one at a time, because the batch is not the sum.

### How it hid, and the clue I had and misread

`pint.pas` — a pure-integer loop — measured **exactly 1.000** at `-O2` vs `-O3`.
I recorded that as "the win is not Pascal, it is many-local pointer routines".
The true reading is simpler: **pure integer code has no string literals.** Every
workload that moved (the compiler, NilPy programs, the RTL) is dense in them;
the one that did not move has none. I had the discriminating experiment in hand
and drew the wrong line through it.

It also retro-explains the uforth ticket's oldest finding — `PXXAlloc +
PXXStrFromLit + PXXFree` at 28.5% with *"a flat profile rather than a pole"* —
and my own earlier measurement that `x = "k"` costs 80.3 ns at `-O2` and 0.0 ns
at `-O3`. Three independent observations of one pass.

### Correctness of the promoted build

Self-host fixedpoint converged (2 rounds); it compiles and correctly runs six
programs (2 Pascal, 4 NilPy); and the compiler *it* produces agrees with the
reference `-O2` compiler's output on a third program. Same caveat as everywhere
else in this ticket: that is evidence, not a gate.

### What this does to the options

**It reverses what I said an hour ago.** Option 1 (per-pass promotion) is not
incapable — it is the right answer and it is *cheap*: one pass, one gate run,
~71% of the win. Option 2 (gate the whole tier) is now the follow-up for the
remaining ~29%, not the primary. **Recommendation: promote
`EmitStaticLitHandle` to `-O2` behind a full gate, then re-open the tier
question for what is left.**

---

## Superseded: "why no pass can be named" — the failed attribution attempt

**Kept for the record; its conclusion is wrong and the section above replaces
it.** Its per-group zeros were measured at min-of-3 under load 6-13, which
cannot resolve what was being asked. The one row still worth trusting is the
DCE row, because it was decided by a flag rather than by a margin: `-O2 --dce`
is flat and `-O3 --no-dce` keeps the win, so DCE is genuinely not the cause.

`CLAUDE.md`'s promotion policy is per-pass, so the obvious next step was to find
which pass earns the 34%. I promoted each `-O3` gate group to `-O2`, rebuilt the
compiler (each reached a self-host fixedpoint), and measured. **Every group,
individually, gives nothing:**

| promoted to `-O2` | vs `-O2` |
| --- | ---: |
| `ir_codegen.inc`, all 16 gates (W1/W2 scratch-register passes) | -6% (noise) |
| `ir.inc`, the inlining gates | 0% |
| `inline_expand.inc`, the 2c inline slices | 0% |
| `symtab.inc`, resident-slot dual-write elimination | -3% (noise) |
| dead-code elimination alone (`-O2 --dce`; a flag exists, no patch needed) | **0%** |
| every gate at once | 12% |
| `-O3 --no-dce` | **26%** |

Two things follow, and the second is the important one.

**DCE is not the cause.** `-O3` turns DCE on (`compiler.pas:1689`) and the `-O3`
binary is 3.3% smaller, which made it the natural second hypothesis after the
scratch-register passes died. `-O2 --dce` is flat and `-O3 --no-dce` keeps the
entire win. Both halves of that check matter; either alone would have been
suggestive rather than decisive.

**Promoting every gate at once recovers only half the win, and produces a
DIFFERENT binary from the `-O3` one.** (Their file sizes match, but that is page
rounding — the bytes differ.) So a discriminator between `-O2` and `-O3` exists
that is not any `OptLevel` comparison I can find in `compiler/**`. Until it is
found, **nobody should claim to know why `-O3` is faster.**

### What this does to the options

It weakens option 1 and strengthens option 2. **If no individual pass reproduces
the win, per-pass promotion may never deliver it** — each promotion would gate a
change that measures as zero, and the 34% would stay unclaimed through the whole
campaign. Gating the tier as a whole does not depend on knowing which pass is
responsible. The recommendation below is unchanged; one of its competitors got
worse.

Finding the discriminator is worth a session on its own and is the natural
follow-up whichever option is chosen.

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

---

# RULED, 2026-08-30, by the owner

> *"About O3 — once things proven stable and are reasonable O2, they are allowed
> to move. We discussed that in the past already. So yes, this makes O3 sortof
> experimental and O2 the de-facto stable, leaving O0 for debugging and O1 in
> limbo."*

## What the ruling settles

**The principle is prove-then-promote, and proof is the only ceremony.** A pass
that is stable and sensible as a default is *allowed* to move to `-O2`. Nothing
else stands between it and promotion — no campaign, no per-pass approval, no
queue.

**The tier semantics are now named, and they were previously only implied:**

| tier | what it means |
| --- | --- |
| `-O0` | debugging |
| `-O1` | **in limbo** — the owner's own word; nothing targets it and nothing defends it |
| `-O2` | the de-facto stable default |
| `-O3` | **experimental** — deliberately, not accidentally |

`-O3` being *experimental by design* is the part worth carrying forward. It is
not a staging area that ought to be empty; it is where a pass lives while it
earns `-O2`.

## What the ruling does NOT settle, and the honest reading

> **CORRECTION, added by frank-optimize after this section was written.** The
> indented measurement below — *"no individual pass reproduces the 23-34% win …
> an interaction effect across the ~25 sites"* — **is false, and it was mine.**
> I reported it from min-of-3 timings under box load 6-13 against a 20% effect,
> which is a null from an instrument that could not resolve it. Measured
> properly since: **`EmitStaticLitHandle` (`ir_codegen.inc:3480`) alone gives
> 20% of `-O3`'s 28%** — ~71% of the tier — 5 of 5 reps agreeing. See "THE PASS
> IS NAMED" above.
>
> This section's *conclusion* may still be right; its stated reason is not.
> Option 1 is not incapable, and "each pass measured alone looks not worth
> promoting" is exactly what the corrected measurement contradicts. The
> granularity question is genuinely open again and should be re-argued on the
> corrected numbers rather than inherited from this paragraph.
>
> Left in place rather than rewritten: it is the coordinator's honest inference
> from the evidence available at the time, and deleting it would hide that a
> ruling was nearly operationalised on a bad null. **A null needs its power
> reported the way a measurement needs its units.**


**The ruling is about the PRINCIPLE, not the granularity.** It says stable things
may move. It does not say they must move one at a time — and that matters here,
because of a fact measured after this ticket was filed and which the owner did
not have in view when ruling:

> **No individual pass reproduces the 23-34% win.** Measured 2026-08-30. The gain
> is an interaction effect across the ~25 `OptLevel >= 3` sites, not a sum of
> separable wins.

So **option 1 taken literally satisfies the ruling and never delivers the 34%**:
each pass, measured alone, looks not worth promoting, and the tier stays where it
is forever. That is not the owner overruling the measurement — it is the
measurement arriving after the rule.

**Therefore: option 2 is the reading that satisfies the ruling.** Gate the tier as
a unit — ask Track T for its full and cross matrices against an `-O3` build — and
promote what comes back green. That IS prove-then-promote; the unit of proof is
the tier rather than the pass, because the tier is the unit the win exists in.
It costs one Track T request instead of a multi-session campaign.

**Option 3 stays rejected, and the ticket's own argument is why:** building the
dev loop's compiler at `-O3` makes the artifact under test a product of an
untested tier, so an `-O3`-only miscompile surfaces as a mystery in someone
else's lane. A known cost traded for an unbounded one. The owner's ruling does
not license this and should not be read as licensing it.

**Flagged rather than assumed:** the inference from *"stable things may move"* to
*"gate the tier as a unit"* is mine, not the owner's words. If Track T's matrix
comes back green and someone still wants per-pass promotion before the default
changes, that is a legitimate reading of the same sentence and the owner should
be asked directly. What is NOT open is doing nothing: the ruling makes promotion
the expected outcome of proof.

## Next action

**One Track T request** — full and cross matrices against an `-O3`-built
compiler. Green means the tier promotes; red names the pass that must not.

`-O1`'s limbo is a real finding and not this ticket's: nothing targets it,
nothing defends it, and no one has priced deleting it or filling it. If it ever
matters it needs its own ticket.

---

# CORRECTION, 2026-08-30, same evening — the premise under the ruling's inference was false

**Do not ask Track T for tier matrices. That ask came from me and it is withdrawn.**

The ruling above stands unchanged — *prove-then-promote, proof is the only
ceremony* — but the inference I hung on it (**"the unit of proof is the tier"**)
rested on one sentence that has since been measured false:

> ~~No individual pass reproduces the 23-34% win.~~

**It does.** frank-optimize found it; I verified the site independently before
correcting this file — `EmitStaticLitHandle`, `compiler/ir_codegen.inc:3480`,
`if OptLevel < 3 then Exit;`. The comment directly above that line already
anticipates this promotion: *"only its USE is gated, so `-O2` keeps calling the
runtime and stays the proven default until this has been through a full gate."*

| compiler | min of 5 | vs `-O2` |
| --- | ---: | ---: |
| `-O2` baseline | 20.23 s | — |
| **only `EmitStaticLitHandle` promoted** | **16.23 s** | **20%** |
| every `-O3` gate promoted | 18.06 s | 11% |
| `-O3` | 14.54 s | 28% |

**One pass is ~71% of the tier.** Per-pass promotion is not merely capable of
delivering the win — it is cheap, well-scoped, and *precisely what the owner's
ruling already prescribes*. The literal reading was right and my correction to it
was wrong.

## The revised action, and it is SMALLER than what it replaces

**Promote `EmitStaticLitHandle` to `-O2` behind a normal full gate.** Then
re-open the tier question for the remaining ~29%, with the same discipline.
Option 3 (building the dev loop's compiler at `-O3`) stays rejected for
frank-optimize's original reason, which nothing here touches.

## Two things that survive regardless of which way this went

**1. The batch is not the sum.** Promoting every `-O3` gate at once measured
*worse* (18.06 s) than promoting the one pass alone (16.23 s). The passes
interfere. A promotion campaign must promote and measure **one at a time**; "all
of them" is a different experiment, not a shortcut through "each of them".

**2. The original sweep's zeros were not results.** min-of-3 under load 6-13
cannot resolve a 20% effect. It returned nulls for every pass and they were
written up in the grammar of findings. **The one row that survived is DCE — and
it survived because it was settled by a FLAG, not by a margin**, decided by
construction rather than by a difference of means. That is the transferable part:
when you can arrange for the answer to be a flag, box load stops mattering. Both
are now in `debugging-playbook.md`.

## How it got into a ruling, since that is the part worth not repeating

The false sentence was **checked, and checked against the wrong thing** — it was
verified as *stated in the ticket*, not as *supported by its instrument*. Nobody
asked what load the sweep ran under or what effect size min-of-3 could resolve.
It was then amplified: called the sharpest claim in the ticket, passed to me as
settled, and used by me as the reason a literal reading of the owner's words
needed correcting. Three hands, no new evidence at any of them.

That is [[the-name-is-not-the-thing]] with a number in place of an identifier,
and it is the same shape as the evening's ghost shas: **the claim was real, the
support was never looked at.** The guard is the one CLAUDE.md already states —
ask what this would be if it were false, and go look at *that*.

**It got better twice by being wrong in public.** The question is no longer
"adopt an untested tier for 34%" but "promote one well-scoped pass for 20%, gated
normally."

---

# WHAT COUNTS AS PROOF — ruled by the owner, 2026-08-30

> *"About optimization: self-host + all tests passed = proof. We have no more
> proof until we have a counterproof."*

**This closes the ceremony question completely.** A pass that self-hosts and
passes the full suite is proven, and there is nothing stronger available — so
stacking an extra benchmark, an extra tier, or an approval step on top of a green
full gate is not rigour, it is delay. **Promote it.**

The back edge arrives in the same sentence and is what makes the bar affordable:
**a later regression IS the counterproof**, and it demotes the pass. Promotion is
reversible. Nobody needs to be certain in advance, which is the assumption that
made the promotion backlog feel expensive in the first place.

## Who runs "all tests", since the promoting agent cannot

The hook denies `gate.sh full` and `testmgr --tier full|limited` to every lane
but T, deliberately, and `PXX_ALLOW_FULL_SUITE=1` is the owner's to grant — not
a coordinator's and not a peer's. frank-optimize's own bound is the honest one:
a fixedpoint in 2 rounds plus six programs is **evidence, not a gate.**

**So: land the promotion, then ask frankT to sweep that exact sha, full + cross.**
One pass, not a tier — much smaller than the ask this ticket withdrew, and
precisely what Track T is for. No new machinery.

**The line that matters is the PIN, not the push** (added here because the ruling
does not say it and the distinction is load-bearing). Landing an unproven `-O2`
default is the ordinary land-non-green case this repo already accepts, and the
counterproof demotes it. **Pinning is what moves every lane's ground.** So a
promoted pass becomes eligible to pin only once T's sweep of its sha is green.
That is the entire additional discipline.

If the owner would rather have the sweep *before* the land, the knob is his:
`PXX_ALLOW_FULL_SUITE=1` for that one run. Nothing here requires it.

## The one boundary — and it is about the instrument, not an extra hurdle

The ruling says a passing suite is all the proof there is. It does not make a
suite see what it cannot. Where a change leaves the corpus **self-consistent
before and after**, a green is **no measurement**, not a null — and the C-ABI
fork is the live case, where the cross suites pass either way by construction.
There you need a differential oracle, not more suite.

That is not a caveat on the ruling. It is
[[the-name-is-not-the-thing]] applied to a test result: *"all tests passed"* is
an identifier, and what it stands for is *"every way this could be wrong was
exercised"* — which is a different claim, and occasionally a false one.

---

## Closing measurement — the campaign is effectively over

**After `440c822e6a80` (the promotion), same workload, same method.** Compiling
`compiler.pas`, 9 paired interleaved runs, load 6.3 -> 11.1:

| | before the promotion | after |
| --- | ---: | ---: |
| `-O3` vs `-O2` on `compiler.pas` | **28%** | **~5-7%** |
| binary size gap | 3.3% | 2.2% |

Min-of-9 gives 6.6% and **7 of 9 paired runs favour `-O3`** — reported as a sign
test rather than a mean because at this size the mean is mostly a measure of the
other agents on the box. **One pass took the tier from 28% to ~6%.**

**Recommendation: stop here.** The remaining passes are worth ~5-7% *collectively*
and each would need its own full gate under prove-then-promote. That is a poor
trade at a measurement precision that cannot cleanly separate 6% from noise —
and the one-at-a-time rule, which is correct, makes the collective figure the
wrong thing to promote against anyway. Whoever wants the rest should first
re-measure on a quiet box; if the gap is really 6%, no individual remaining pass
is likely to clear the bar.

**What the remaining gap is made of**, for whoever does pick it up — from a
mnemonic-frequency diff of the two builds of `compiler.pas` (1.95M instructions
each), which needs no timing at all:

| mnemonic | `-O3` minus `-O2` |
| --- | ---: |
| `push` / `pop` | **-26,965 each** (exactly matched pairs) |
| `movslq` | -17,241 |
| `mov` | +55,717 |
| `movaps` | +219 (zero at `-O2`) |

So the rest is the **W1/W2 scratch-register work** — ~27k push/pop pairs
replaced by register moves — plus sign-extension elimination. Note that this is
a large *instruction* change for a small *time* change, which is the same trap
this ticket already fell into once: **an instruction count is not a cost.**
