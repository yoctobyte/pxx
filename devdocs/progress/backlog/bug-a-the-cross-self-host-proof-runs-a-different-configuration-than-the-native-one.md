---
track: A
prio: 35
type: bug
status: backlog
owner: unassigned
blocked-by: []
found: 2026-08-30
found-by: frankD, auditing public copy for the two byte-identical claims
summary: "'x86-64, i386, aarch64 and arm32 self-host byte-identical' is true but is TWO gates, not one: the native proof builds with no flags at all (PXXFLAGS empty) while cross-bootstrap builds with -dPXX_MANAGED_STRING, whose own rule comment says the managed runtime is REQUIRED. Nothing outside Makefile:13809 says so. Track A owns the reason; docs can place the sentence once A supplies it."
---

# The cross self-host proof runs a different configuration than the native one

- **Type:** bug (undisclosed qualifier on a load-bearing claim) — **Track A** owns the
  reason; the docs half is already handled.
- **Found:** 2026-08-30 by frankD, which **verified the claim rather than accepting it**
  — reading `Makefile:13809`'s `cross-bootstrap` rules to confirm the cross proof is a
  real proof (cross-compile `compiler.pas` for the target, run *that* binary under QEMU
  to compile it again, `cmp`), and finding the configuration difference on the way.

## The two configurations

| proof | build flags |
| --- | --- |
| native self-host fixedpoint | **none** — `PXXFLAGS` empty |
| `cross-bootstrap` (i386 / aarch64 / arm32) | **`-dPXX_MANAGED_STRING`**, and the rule's own comment says *"Managed runtime is **required**"* |

So *"all four self-host byte-identical"* reads as one gate and is two. Both are real;
they are not the same claim.

## What Track A needs to supply

**Why the managed runtime is required for the cross bootstrap.** frankD deliberately
**stated the difference without explaining it** — *"asserting a reason would be inventing
one"* — which is the right call and the reason this ticket exists rather than a docs edit
that guesses. The candidate readings differ a lot in what they imply:

- a deliberate, permanent property of cross targets (then it is documentation, and the
  claim should say so on both surfaces); or
- a workaround for an unmanaged-string defect on non-x86-64 targets (then it is a **bug**
  with a `-dPXX_MANAGED_STRING` shaped scar on it, and the cross claim is weaker than it
  reads); or
- historical, no longer required, never re-tested. **Cheapest to check and the most
  likely to be true of a required flag nobody has questioned** — cf. face 181, a guard
  already hardened once is the one whose stated reason nobody re-reads.

A one-sentence answer closes this. frankD has offered to place it in `docs/**`.

## Why it matters beyond the wording

Same failure mode as the `-O`-scope omission found in the same audit, one axis over:
**a true claim whose qualifier lives in a Makefile comment no reader will ever see.**
The claims-discipline section of CLAUDE.md is about not conflating two *different*
byte-identical claims; this is a third distinction inside one of them.

And it bears on the self-host gate's own authority. CLAUDE.md already narrows that gate
once — *"evidence the compiler compiles itself **at one optimisation level**, not that it
compiles itself"* — after a `-O0`-only self-compile failure passed the entire gate on
2026-08-19. This is the second narrowing, on the axis of build flags rather than
optimisation level, and it was likewise found by someone looking at something else.
