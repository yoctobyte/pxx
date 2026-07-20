---
summary: "Track U: reject the GPC corpus wish, or keep it? Two sweeps have called it a rejection candidate."
type: decide
prio: 45
track: U
---

# decide: reject `wish-compile-gnu-pascal`, or keep it open?

- **Type:** decision — **Track U**. Scope call, no files, no gate.
- **Status:** open — filed 2026-07-20.
- **Blocks:** [[wish-compile-gnu-pascal]].
- **Raised by:** Track B queue sweep. The wish has carried a "rejection candidate
  (user call)" note since 2026-07-19 and was still ranked at prio 45 as available
  Track B work. Nobody had filed the actual question, so it sat in the queue
  looking like a task while waiting on a decision.

## The question

Should GNU Pascal be a corpus target at all?

## The case for rejecting

- **GPC is not standalone-buildable.** It is a GCC *frontend*, so "compile GPC"
  means building it inside a GCC tree, not compiling a self-contained project.
  That is a very different and much larger job than the wish implies.
- **The sibling analysis already says so.** `idea-c-realworld-test-targets`
  reaches the same conclusion independently and recommends p2c or tcc instead.
- **tcc self-compile is already DONE**, so the thing this wish would have proven
  — that the C frontend handles a real compiler codebase — is proven.
- GPC's Pascal runtime targets ISO 7185/10206. Our Pascal frontend targets the
  FPC/Delphi surface. Overlap is partial, so even the Track B half feeds the
  compat campaign less than Synapse, fgl or FPC itself already do.

## The case for keeping it

Its ISO-dialect runtime is the one thing in the list we do *not* otherwise
exercise — every current Pascal corpus target is FPC/Delphi-shaped. If ISO
conformance ever becomes a goal, this is the ready-made corpus. That is a real
argument, just not one that supports a prio-45 ranking today.

## Recommendation

**Reject**, and note the ISO angle in `idea-c-realworld-test-targets` so it is
not lost. Two independent sweeps have now reached the same conclusion; leaving it
open a third time costs more attention than the option is worth.

## Once decided

Reject -> move [[wish-compile-gnu-pascal]] to `rejected/` with a pointer here.
Keep -> drop its `blocked-by` edge and re-rank it honestly (well below 45, since
nothing depends on it).

## Log
- 2026-07-20 — Filed from the Track B sweep. Moving it to `rejected/` IS the
  decision, which is why a Track B agent should not simply do it.
