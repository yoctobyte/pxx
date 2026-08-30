---
track: T
prio: 40
type: feature
status: backlog
blocked-by: []
owner: ""
summary: "The csmith oracle is a checksum of the globals, so it is complete for VALUES and structurally blind to LAYOUT: a struct whose members sit at the wrong offsets stores and loads consistently and produces an identical checksum. Predicted 2026-07-13, unacted on, and a real offset bug then survived every batch since -- 443 on 2026-08-30 alone. Proposes a layout dimension: emit offsetof for every member of every generated struct and diff against gcc."
---

# A layout oracle dimension — the checksum is complete for values and blind to offsets

- **Track T** — fuzzing tooling and its oracles (`tools/csmith_fuzz.py`).
- **Found:** 2026-08-30 by frankC, after filing
  `bug-c-a-long-long-bitfield-after-a-smaller-one-puts-later-members-at-the-wrong-offset`.
- **Sibling:** `feature-t-a-second-oracle-dimension-section-alignment` — same
  shape, a second dimension added to a differential because the first cannot see
  a whole class.

## The gap, stated as a property of the instrument

csmith's oracle is **a checksum of every global**. That makes it complete for
values and **structurally blind to layout**: a struct whose members sit at the
wrong offsets stores and loads through those same wrong offsets, self-consistently,
and prints an identical checksum. `MISCOMPILE_VS_GCC` cannot fire. Neither can
`MISCOMPILE_OPT`, which compares our own `-O` levels to each other and is if
anything *more* blind — both arms share the layout.

This is not a shortcoming of a particular batch. **No batch of any size, at any
complexity, on any target, can find a layout defect**, because the quantity that
differs is not in the quantity being compared.

## It was predicted, and the prediction was the whole of the action taken

`feature-c-csmith-differential-fuzzing` has carried this since **2026-07-13**:

> **Bitfield LAYOUT** — `sizeof` of a packed bitfield struct is 12 where gcc gives
> 8. Values are right, so the checksum oracle **CANNOT see it**; it breaks
> ABI/interop instead.

Correct, and nothing followed from it. The consequence, measured:

- A real layout bug sat **unfiled for seven weeks** — not unfixed, *unfiled*.
- Batches kept running past it. On 2026-08-30 alone: 443 comparisons across two
  x86-64 batches, plus 100 aarch64 and 100 i386, **none of which could have seen
  it**, all reported as clean.
- When it was finally measured, the recorded shape (`sizeof` 12 vs 8) **did not
  reproduce** and a worse one did: `sizeof` **matching at 16 both** while
  `offsetof` of a following member differs (12 vs 8).

That last point is the argument for building the dimension rather than
hand-checking layout occasionally. **A size check is what a careful person
writes, and a size check is exactly what misses this.** The July note tested the
metric that cannot see the bug, and the note stood for seven weeks looking like
coverage.

## What to build

For each generated program, emit alongside the checksum a **layout manifest**:
for every struct and union type, `sizeof` and `offsetof` of **every member**.
Build with gcc and with pxx, diff the manifests.

Properties that make this cheap and strong:

- **Both compilers compute the numbers directly.** No execution, no qemu, no
  timing, no UB questions — `offsetof` is a compile-time constant. It can run as
  a compile-only pass over the same generated program the value oracle already
  built.
- **It is a pure differential**, so it needs no judgement, exactly like the
  checksum.
- **It is orthogonal, not redundant** — the checksum is complete for values and
  blind to layout; this is complete for layout and says nothing about values.
  Both are needed and neither subsumes the other.
- csmith generates bitfields, unions, packed structs and nested aggregates
  already; the generator side needs nothing.

**It must compare OFFSETS, not just sizes.** Comparing sizes reproduces the exact
blind spot that hid this bug for seven weeks — the case that matters had matching
sizes. Say so in the implementation, because "diff the sizeof" is the obvious
first cut and it is the wrong one.

A new bucket (`LAYOUT_DIFF`) alongside the existing `LAYOUT_SUSPECT` — which
today triggers only on a *value* divergence in a program that happens to contain
bitfields, and therefore cannot fire when values agree.

## Prio note

p40 rather than higher because nothing is presently silent: the one known layout
defect is now filed with a mapped boundary. The dimension earns its rank by what
it prevents — every future layout defect is otherwise found the way this one was,
by somebody deciding to look, seven weeks late.
