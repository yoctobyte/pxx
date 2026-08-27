---
slug: feature-a-wasm32-module-writer-wiring
title: "Wire the wasm32 module writer into compiler.pas, and correct the false reason in exception_emit.inc"
track: A
prio: 55
type: feature
blocked-by: []
status: done
owner: frankwasm
created: 2026-08-27
summary: "Two {$include} lines and the TARGET_WASM32 output arm in compiler.pas, plus the message text (not the mechanism) at exception_emit.inc:437. The wasm lane's first shared-file edit, taken under a coordinator grant with named edges after both files were confirmed uncontended. Lands on branch `wasm`, not master — it reaches master at the eventual merge-back."
---

# Why this exists as a ticket at all

The `wasm` branch's whole strategy is *move the conflict, don't manage it*
(`feature-a-wasm32-target-registration-skeleton`): registration went to `master`
first so the branch would add only new files. `PLAN.md` named the expected
escapes as Phase 4 (VMT fixups) and Phase 5 (exceptions), and set a standing
rule — a shared-file edit outside that list is *"a surprise worth stopping for"*.

Phase 1's milestone is "pxx emits a `.wasm`". Reaching it needs `compiler.pas`.
That is a shared file, at Phase 1. So the lane stopped, built the encoder to be
provable **without** the wiring — a standalone self-test that includes the two
new files directly (`test/wasm/check_phase1.sh`) — and put the routing to the
coordinator rather than arguing itself across the boundary on an "it's only
three lines" basis. That argument is exactly how the strategy erodes.

The registration commit had in fact anticipated this moment: *"that branch adds
only new files and never merges a shared one **until it emits**"*. It emits now.

# What was granted, and the edges

Granted by the coordinator after measuring rather than assuming — `git log` on
both files showed only the landed registration commit `290ee8ca4`, with frankA
in `pasparser_*`/`defs.inc` and frank-optimize in `ir_codegen.inc`. Both files
uncontended. Filed as Track A and self-resolved: the combined-track pattern
CLAUDE.md describes, whose only requirement is a coordinator confirming no
concurrent A holder.

1. `compiler/compiler.pas` — `{$include wasmenc.inc}` beside the encoders,
   `{$include asmtext_wasm.inc}` beside the text emitters, and the
   `TARGET_WASM32` output arm calling `writeWasm` instead of erroring.
2. `compiler/exception_emit.inc:437` — **the message text only**, never the
   mechanism.

Anything beyond those two is a new conversation.

# The guard, and why it is not a placeholder

`writeWasm` errors when `WasmFuncCount = 0`. With no codegen the module model is
empty, so writing an empty-but-valid `.wasm` for a program that plainly has code
would be a **silently wrong output** — the failure class this project treats as
the expensive one. Every real program takes the error branch until Phase 2, and
takes it for an accurate reason. The guard stays correct once codegen exists.

# The exception_emit.inc correction

The wasm arm said the module *"needs the exception-handling proposal or a
trampoline"*. It needs neither. Pending-flag threading uses no engine proposal,
no version dependency and no trampoline — which is precisely why `PLAN.md` chose
it over the EH proposal, whose legacy-vs-final opcode split is live
fragmentation. It was prototyped and diffed against a native build before the
replacement text was written (`devdocs/dev/wasm/phase5-exceptions.md`,
`test/wasm/proto/check.sh`).

Erroring there is still correct — exceptions genuinely are not implemented. Only
the stated reason was wrong. **A wrong reason attached to a correct behaviour is
the most durable kind of wrong**, because nothing ever fails to make anyone
check it.

# Gate — seen, not assumed

This is the first wasm change that could reach the self-host loop at all: the
branch converged at `325b4479070a` up to now only because nothing `compiler.pas`
includes had moved. Two includes ends that.

- `make compiler/pascal26` → **`converged after 1 round(s)`**, `cb55d648a657`,
  differing from pinned `325b4479070a`. The convergence line was watched for
  specifically; its absence is the only tell and there is no error to wait for.
- **No existing target moved:** 4 programs x 6 targets = 20 output hashes,
  identical before and after, with the "before" compiler rebuilt from the
  reverted files and reproducing `325b4479070a` exactly.
- `test/wasm/check_phase1.sh` and `test/wasm/proto/check.sh` green under the
  new binary.

# Consequence the next session needs

**The `wasm` branch now touches shared files.** It was true until today that a
`master` merge could not conflict in `compiler/**`; it is not any more.
`CHARTER.md`'s escapes table records this. Merge `master` in *more* often, and
treat a conflict in `compiler.pas` or `exception_emit.inc` as a coordination
event rather than a merge to resolve locally.
