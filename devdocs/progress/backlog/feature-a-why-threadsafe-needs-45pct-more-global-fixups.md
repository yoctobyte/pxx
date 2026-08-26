---
track: A
prio: 20
type: investigation
summary: "--threadsafe self-compile emits 45% more global fixups than the normal one (65657 vs 45326). Raising the cap unblocked it; nobody has explained the +45%, and it may be one fixup per TLS access that dedupes away"
---

# Why does `--threadsafe` need 45% more global fixups?

- **Type:** investigation — **Track A** (`compiler/emit.inc`, the backends)
- **Split out 2026-08-02** from
  [[bug-a-threadsafe-self-host-exceeds-max-globfix-by-121]], whose "fix
  directions" recommended raising the cap now and asking this separately. The
  cap was raised (commit 5d7fa14f3's parent, `91f063250`) so nothing is blocked
  on this; it is the question the capacity bug left behind.

## The measurement, from that ticket

| build | global fixups |
|---|---|
| normal self-compile | 45326 |
| `--threadsafe` self-compile | 65657 |

**+20331 (+45%)** for the same source. 65657 entries against 2379 procs is a lot
of fixups per routine, which is what makes the number suspicious rather than
merely large: the shape suggests the same (symbol, addend) recurring, and
`EmitGlobRef` appends unconditionally — there is no dedupe.

## Worth answering because

- If it is one fixup per TLS access, collapsing repeats attacks the GROWTH
  rather than the ceiling, and the ceiling is a wall we have now walked into
  once and will walk into again.
- It is a plausible *bug* rather than a cost. Nobody has checked whether
  threadsafe codegen is emitting references it does not need.
- Every fixup is emitter work and image size, so a dedupe is a small,
  measurable win on the one build that already costs the most.

## Where to look

`EmitGlobRef` (`compiler/emit.inc` ~96) is the single append point, so counting
by `BSSoff` there answers "how many distinct globals vs how many references" in
one run. Compare a `--threadsafe` and a normal self-compile of
`compiler/compiler.pas` — the two numbers in the table above came from exactly
that pair, so the harness is trivial.

## Not urgent

The cap is 262144 now, with the threadsafe build at 65657 — roughly 4x headroom.
This is an efficiency and hygiene question, not a blocker.
