---
track: A
prio: 65
type: feature
blocked-by: []
summary: "Reserve N=4 leading VMT slots (Destroy, Equals, GetHashCode, ToString) in every class so a static-TObject receiver can dispatch to a descendant's override, with --compact-classes opting out to today's behaviour and the ESP target defaulting to compact. Implements decide-tobject-root-methods-dispatch-model; unblocks feature-pascal-builtin-tobject-class and the generics corpus rung."
status: backlog
owner: unassigned
---

# Reserved leading VMT slots for TObject's root methods

- **Track A** — shared class machinery. **Three sites**, see below.
- Implements [[decide-tobject-root-methods-dispatch-model]] (answered by the
  user 2026-08-21). That ticket holds the measurement and the reasoning; this
  one is the work.

## What to build

Every class reserves **N = 4** leading VMT slots — `Destroy`, `Equals`,
`GetHashCode`, `ToString` (FPC's set) — with its own virtuals starting at index
N. The root-method names get fixed slot numbers in the override resolver, so
`o.Equals(x)` on a variable statically typed `TObject` dispatches through a known
slot and a descendant's `override Equals` lands in it.

TObject stays an **implicit** parent; `class(TObject)` keeps resolving to `-1`.
This is what makes C not-B: the base shifts uniformly at declaration time rather
than relocating classes that already exist.

## The three sites

Slot allocation and VMT emission are duplicated, so this lands in all three or
Pascal and NilPy classes disagree on the base — and they share one symbol table:

| file | what it does |
| --- | --- |
| `compiler/symtab.inc` | `UClsVirtCount[UClsCount] := 0` at class mint |
| `compiler/pasparser_decl.inc` | Pascal: slot alloc + VMT emission (`ResolveVMTSlotProc` walk) |
| `compiler/pyparser.inc` | NilPy: slot alloc + its own VMT emission (hand-rolled ancestor walk) |

`cparser.inc` and `zparser.inc` do not touch `UClsVirtCount` — nothing to do there.

Everything else follows for free: ~20 consumers in `pasparser_expr` / `_stmt` /
`_lval` read `UMthVirSlot[mmi]` back from the method record, VMT emission walks
`0 .. UClsVirtCount[ci]-1` generically, and **no VMT slot literal exists anywhere
in the compiler**. The IMT is a separate table and is untouched.

## `--compact-classes`

Opts out: N = 0, i.e. **exactly today's behaviour**, which is why the opt-out
path is not new untested code. Under compact there is no root slot, so a
static-`TObject` root-method call **cannot be emitted and must be a compile error
naming the flag** — never a silent fallback. That property is the whole reason
option A was rejected; do not soften it.

**The ESP target defaults to compact** (user, 2026-08-21: *"memory is precious on
that target"*) and this must be **documented** in the ESP profile docs — an
implied flag that changes what compiles is otherwise a surprise. An ESP program
that wants a class-keyed default comparer turns it off in that build.

Interaction to record: `--emit-obj` makes this an ABI-splitting switch (two
objects with different N disagree on slot numbers). Same class of hazard
`--threadsafe` already carries; give it the same treatment — a recorded mode,
diagnosed rather than left to produce garbage.

## Implementation choice to MEASURE, not assume

C was partly chosen because it lets `pasparser_decl.inc:4110`'s
`Destroy`/`Create` materialisation hack be **deleted** — that hack exists only
because the implicit root carries no method table. But compact mode reverting to
N=0 keeps the hack alive as the compact path, and the deletion evaporates.

Option: **compact reserves `Destroy` only (N=1)** instead of N=0. Then the hack
is deleted in both modes. Cost relative to today is zero for a class with no
virtuals or one that overrides `Destroy` (both already pay one slot — Pascal's
`vmtSlots < 1` floor), and **+8 bytes for a class with virtuals but no
destructor**, which is a common shape. Measure that against a real ESP build
before choosing; it is bytes vs. one deleted special case, and the ESP budget is
the reason the flag exists.

Whatever is chosen: **do not let this ticket's write-up claim a deletion that did
not happen.**

## Pre-existing drift worth fixing while in here (not a blocker)

Pascal floors the VMT at one slot (`if vmtSlots < 1 then vmtSlots := 1`); NilPy
does not, so a NilPy class with zero virtuals emits a zero-length VMT. Benign
today — no virtuals means no dispatch — but the two emitters are one concept with
two implementations and a hand-maintained *"keep the two in step"* comment.
Collapsing them into one shared emitter is the `normalise-dont-special-case`
answer and would make this change land once instead of twice.

## Unmeasured, and it decides how narrow the compact escape is

Whether merely **constructing** a default-comparer container over a class type
pulls the class comparer in, or only the first compare/hash does — i.e. whether
pxx specializes lazily per-method or eagerly per-class. It determines whether
`TDictionary<TFoo, X>` under `--compact-classes` fails at construction or never.
Answer it before documenting the flag's limits.

## What unblocks

[[feature-pascal-builtin-tobject-class]] (slice 2: the RTTI-free root methods) →
[[feature-pascal-corpus-generics]] walls 1569 and 1780 → walls 28-33, so far only
measured against a throwaway tree with the two methods stubbed.

## Gate

`make compiler/pascal26` + self-host fixedpoint (byte-identical), `tools/gate.sh
quick`. Tests: a descendant's `override Equals` dispatched through a static
`TObject` receiver; the same for `GetHashCode`; `Destroy` still virtual through
`Free`; a NilPy class and a Pascal class agreeing on the base; and a
`--compact-classes` row asserting the **compile error**, not a wrong answer.
Cross where a backend is touched — though nothing here should reach one.
