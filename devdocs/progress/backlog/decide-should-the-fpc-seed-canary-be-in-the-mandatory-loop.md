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

frankwasm built `forwardlint.py` — **~1 second**, reads the same files FPC reads and
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
| **4. static forward lint** | **~1s** | the whole observed failure class, by design a miss not a false alarm | **built + verified** |

**Still a Track U decision**, because putting anything in the mandatory loop touches
the gating section of `CLAUDE.md`, which is the owner's file. But the question is no
longer *"is it worth a serial FPC build?"* — it is *"should a verified one-second
lint join the loop?"*, which is a materially easier call.
