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
