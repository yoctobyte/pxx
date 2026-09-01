---
slug: decide-the-wasm-umbrella-at-70-reinstates-everything-the-owner-demoted-to-25
title: "umbrella-wasm-is-a-real-platform is priced at 70 and cancels the owner's wasm re-pricing"
track: U
prio: 60
type: decide
status: new
blocked-by: []
owner: user
summary: "On 2026-08-30 the owner ruled WASM IS LOW PRIO FROM NOW ON -- 'these tickets stay OPEN and correct; they simply must not outrank ordinary Track A work' -- and the wasm bugs were correctly set to prio: 25. On 2026-08-31, 8d9a5794b created umbrella-wasm-is-a-real-platform at prio 70. effective_prio takes the max over dependents, so those same tickets come back out of `ready` at 70 and DO outrank ordinary Track A work: exactly the outcome the ruling forbade. The leaves were re-priced; the goal above them was not. The ranker is working perfectly and delivering the opposite of the instruction. One number fixes it, but which number is the owner's call. NOT affected: bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa, whose 75 comes from umbrella-managed-memory-is-correct and is legitimate under either reading."
---

# The wasm umbrella reinstates what the wasm re-pricing demoted

Found 2026-09-01 by frankB while taking the wasm32 group off `ready --track A`,
and independently by frank-coordinator the same hour. Neither of us was looking
for it; it is what `ready` hands you.

## The two instructions, both real, one dated later

**2026-08-30, in the body of both wasm `bug-a-` tickets:**

> *"it works, it tests our IR, we should be able to compile applications.. for
> now, that's good enough."* The anchor is met — `pascal26` runs under wasmtime
> and emits an ELF byte-identical to the native compiler's. **These tickets stay
> OPEN and correct; they simply must not outrank ordinary Track A work.**

Someone acted on it correctly: both are `prio: 25`.

**2026-08-31, `8d9a5794b`**, landing the umbrella scheme, created
`umbrella-wasm-is-a-real-platform` at **prio 70** with four wasm tickets wired
to it. `effective_prio` takes the max over dependents, so:

| ticket | own `prio:` | comes out of `ready` at |
| --- | --- | --- |
| `bug-a-emitzeroframeslot-has-no-wasm32-arm` | 25 | **70** |
| `bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime` | — | **70** |
| `feature-t-run-the-wasi-slices-under-wasmtime-...` | — | **70** |

**Nothing is broken.** The ranker does exactly what CLAUDE.md specifies. The
re-pricing was applied to the leaves and the goal above them was never given a
number consistent with it, so the ruling was reversed by a mechanism that landed
the next day and could not know about it.

## Why this is probably an accident rather than a reversal

The five umbrellas in `8d9a5794b` are priced **90, 85, 80, 75, 70** — exact
five-point steps. That is a **ladder assigned by ordering**, not five
independent ratings; wasm's 70 is "last of five", not "worth 70". The commit
says the umbrellas were *"derived strictly from the stated goal"*, and the goal
document does name wasm in the platform list — so 70 is a defensible reading of
`the-goal-cross-cross.md` by someone who had not seen the 08-30 ruling, which
lives only in two ticket bodies.

That is the whole mechanism: **a ruling recorded where the ranker cannot see it,
overturned by a number chosen from a document that does not contain it.**

## The fork

- **(a) Lower the umbrella to ~25.** Honours the explicit, dated ruling; wasm
  tickets rank on their own prio and stay open and correct, which is exactly
  what the ruling asked for. **Recommended** — it is the only option that makes
  the board agree with a sentence the owner actually wrote.
- **(b) Keep 70.** Treats the 08-31 umbrella as a deliberate re-rating. Costs
  nothing to adopt, but no evidence supports it: the ladder tell above suggests
  the number was never a judgement about wasm.
- **(c) Split the umbrella.** "Emit correct wasm32" demoted, "host the compiler
  under a wasm runtime" kept high because the goal's second proof is pxx hosting
  itself off Linux/x86-64. **Weaker than it looks** — the 08-30 note says that
  anchor is already **met** under wasmtime, so the high half is largely done.

## Scope, so nobody over-corrects

Only the wasm umbrella is in question. **`bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa`
is NOT affected**: its 75 comes from `umbrella-managed-memory-is-correct`, an
unwind leak is a managed-memory correctness hole on its own terms, and CLAUDE.md
cites that very ticket as the worked example of legitimate multi-umbrella
membership. It ranks at 75 under either answer here.

## The general shape, which outlives this ticket

**A re-pricing applied to leaves is undone by any umbrella later placed above
them, silently, and the ranker will look correct while it happens.** Worth a
`progress.sh check` aperture: a ticket whose own `prio:` is far below its
`effective_prio` *and* whose body contains an explicit ruling is the detectable
form. Nobody misread anything here — frankA read 25, frankB read 70, both
numbers are real, and only one reflects intent.
