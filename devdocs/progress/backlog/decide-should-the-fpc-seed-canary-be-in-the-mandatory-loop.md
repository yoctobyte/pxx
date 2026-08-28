---
slug: decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop
title: "The per-fix loop is blind by construction to breaking the FPC bootstrap seed"
track: U
prio: 55
type: decide
blocked-by: []
status: backlog
owner: unassigned
created: 2026-08-28
summary: "make compiler/pascal26 compiles with pxx, which accepts a call to a routine defined later in the same include; FPC rejects it, and FPC bootstraps this compiler. So an edit that adds a call above its definition breaks the seed while every commit stays green on the documented per-fix loop. Measured 2026-08-28: a branch was red for days across several commits, caught only by the FPC seed canary at tools/gate.sh:219, which is in the gate and not in the loop. CLAUDE.md's gating section is the owner's file, so whether the canary moves into the mandatory path is the owner's call."
---

# The one failure class the documented loop cannot see

CLAUDE.md states the per-fix loop is the whole gate, and that
`make compiler/pascal26` is load-bearing precisely because a compiler that cannot
reproduce itself would poison every lane. **That is true and this does not
contradict it** — but there is a second whole-fleet failure the same loop is blind
to, and unlike a broken fixedpoint it produces **no signal at all**.

**Mechanism.** `make compiler/pascal26` compiles `compiler.pas` **with pxx**. Our
dialect accepts a call to a routine defined later in the same include. **FPC does
not, and FPC is the seed** — a broken seed means the compiler cannot be
bootstrapped from source by anyone who does not already have a working binary.

**Measured, 2026-08-28 (frankwasm).** `WasmEmitCall` used at
`ir_codegen_wasm32.inc:912`, defined at 1030. The seed was broken **the day direct
calls landed** and stayed broken across several commits — **every one green on
`make compiler/pascal26`**, because the loop's compiler is the one that accepts it.
Caught only by the FPC seed canary at `tools/gate.sh:219`. Fixed in 18 lines of
forwards (`cd878f9ca`), verified by building `compiler.pas` with `fpc` directly.

**Why the loop cannot be blamed:** the canary is deliberately *in* the gate, and
`gate.sh`'s own comment (line 228) says it is affordable **precisely because it is
concurrent** — it starts first, in the background, and overlaps the rest. Serially,
in a per-fix loop, it would not be free.

## The fork

| option | cost | catches |
| --- | --- | --- |
| **1. Targeted trigger (recommended)** — leave the loop alone; document that *adding a call above its definition in `compiler/**`* is the one edit shape the loop cannot see, and run `gate.sh quick` after that specific kind of edit | ~0 normally, ~30s on the edits that matter | everything, **if lanes notice they made that edit** |
| 2. Canary in the mandatory loop | a serial FPC build per fix, on the box that is the binding constraint | everything, unconditionally |
| 3. Leave as-is | 0 | nothing — the next occurrence is also silent, and only surfaces at someone's next pin |

**Recommendation: option 1**, with the caveat that its weakness is real — it relies
on a lane recognising its own edit shape, and frankwasm's edit was exactly that
shape and went unnoticed for days. If the owner judges that unreliable, option 2 is
the honest alternative and the cost is stated above.

**Filed as Track U rather than acted on** because it concerns the gating section of
`CLAUDE.md`, which is the owner's file. No agent should widen or narrow the
documented loop on its own initiative, and no peer can authorise it.

**Already propagated without touching the loop:** a warning is appended to
`bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream` (the unclaimed
Track A ticket, which is a `compiler/**` edit), and the finding is in
`devdocs/dev/session-roster.md`. Track B is unaffected — FPC never compiles
`lib/rtl`.

---

## UPDATE 2026-08-28: a fourth option now exists, built and verified

The seed broke **a second time, in the same file, hours after the first** —
`WasmEmitIndArgs` called at 1309, defined at 1620. That settles option 1's stated
weakness empirically: **the targeted trigger does not work**, because the lane
recognised neither instance of its own edit shape.

Worse, and this is the finding: **the forward block already carried a written rule**
— *"every routine the dispatchers dispatch to belongs here"* — and the break walked
straight past it, because `WasmEmitIndArgs` is **not** a dispatch target; it is
called by a builtin lowering sitting above the machinery it shares.

> **A rule that is slightly wrong is worse than no rule: it reads as complete.**
> frankwasm read it *while writing the code that violated it.*

### Option 4 (now the recommendation): a static forward lint in the fast loop

frankwasm built `forwardlint.py` — **4.1 seconds** (see the correction below), reads the same files FPC reads and
asks FPC's question directly. **Verified against BOTH historical breaks**: deleting
today's forward reports line 1313; deleting the *original* one — the break that cost
several commits before the canary found it — reports line 1065; the fixed file is
clean.

**Deliberately narrow, with the failure mode chosen rather than accepted: it misses
rather than false-alarms**, because the gate's real FPC build remains the backstop
either way. That satisfies the criterion this repo settled on the same night — **a
check whose worst case is LATENESS can live in a fast loop; one whose worst case is
a WRONG ANSWER cannot** — and it also answers the cost objection that made option 2
unattractive, since a second is not a serial FPC build.

| option | cost | catches | status |
| --- | --- | --- | --- |
| 1. targeted trigger | ~0 | **empirically: nothing** — missed twice | **disproven** |
| 2. FPC build in the loop | serial FPC build per fix | everything | unattractive on cost |
| 3. leave as-is | 0 | nothing | — |
| **4. static forward lint** | **4.1s** | the whole observed failure class, by design a miss not a false alarm | **built + verified** |

**Still a Track U decision**, because putting anything in the mandatory loop touches
the gating section of `CLAUDE.md`, which is the owner's file. But the question is no
longer *"is it worth a serial FPC build?"* — it is *"should a verified one-second
lint join the loop?"*, which is a materially easier call.

### CORRECTION 2026-08-28: 4.1s, not ~1s — and the narrow version had to be thrown away

**The ~1s figure was wrong and it was load-bearing**, so it is corrected in place above
rather than quietly. It measured a three-file version that **does not work on this repo**:
pointed at the whole compiler it reported **seventeen failures on a tree FPC builds clean**,
because this codebase declares cross-file forwards in dedicated files (`forwards.inc`,
`pyforwards.inc`, `frontend_forwards.inc`) that a per-file view cannot see.

The shipped version (`tools/forwardlint.py`, `c7690064e`) expands `compiler.pas`'s
`{$include}` chain in order and asks FPC's question over the real stream: **206,768 lines
in 4.1s, 17 → 0**, re-verified in both directions against both historical breaks. Still
**~11x faster than the 46-second FPC build**, so the cost argument survives — but the
number in this ticket was wrong and the version it described is gone.

Two further false-alarm sources had to be removed to get there, and both are worth reading
before anyone writes a similar tool:

- a declaration regex anchored at `^` cannot see `{$ifndef PXX_NO_ARM32}procedure Foo; forward;{$endif}`;
- **braces nest in practice**: standard Pascal says the first `}` closes the comment, but
  **both pxx and FPC** accept `{ ... span_{nd-1} ... }` as one comment. Measured with a
  six-line program after the scanner ended a comment early and reported a name that appears
  only in prose. **A tokenizer that disagrees with both compilers about where a comment ends
  is not a check; it is a generator of plausible-looking failures.**

### Whoever adopts this must expect ONE note on a clean tree

`forwardlint` prints a NOTE (not a failure) on today's master, reproduced by the coordinator
independently: `pasparser_expr.inc:1924` calls `LowerCase` before this codebase declares it
at `pasparser_proc.inc:2384`, and it is forward-declared **nowhere**. It compiles either
way — FPC resolves that call to its **own** system-unit routine — which is exactly why it is
a note.

**That note should be fixed before this joins any loop, not allowlisted.** A check that
prints something permanent on a clean tree is on the path to being ignored, which is this
repo's own recorded rule about checks that cry wolf. Filed separately as
`bug-a-lowercase-resolves-to-two-different-routines-depending-on-the-seed`.

## Worked example, 2026-08-28 — the loop was green while the seed build was red

Added by the coordinator. This decision had been arguing in the abstract; frankA hit
the exact case while landing wall 6 (`35f485537`).

`make compiler/pascal26` — the mandatory loop, and the byte-identical self-host
fixedpoint — was **GREEN**. The **FPC seed build was not**: `GenericMethodBodyEnd`
is defined below its caller, which pxx resolves either way and FPC does not. The
optional `tools/gate.sh quick` caught it. Had it been skipped — and the loop says
it MAY be skipped — the tree would have been pushed in a state that cannot be
rebuilt from the seed.

**Why the mandatory step cannot ever catch this class:** the fixedpoint only
exercises **pxx compiling pxx**. A construct pxx accepts and FPC rejects is
invisible to it *by construction*, not by oversight. That is the `bug-a-fpc-seed-drift`
shape, and no amount of care inside the per-fix loop will surface it, because the
instrument does not read that axis at all.

This is the second time in one day the optional gate caught something the mandatory
one structurally could not.

**What it does NOT settle:** the cost side. Adding the seed build to the mandatory
loop lengthens the one step that is deliberately ~12s and on every fix's critical
path, and the loop's whole design is that breadth is offloaded to Track T. The
question is still whether this class is frequent enough to pay that on every commit,
or whether it belongs in `gate.sh quick` (where it already is) with the loop simply
saying so more loudly. **The decision remains the owner's** — it changes the
mandatory loop, which is CLAUDE.md's own text.
