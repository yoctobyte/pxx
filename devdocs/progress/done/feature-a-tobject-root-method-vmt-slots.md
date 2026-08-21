---
track: A
prio: 65
type: feature
blocked-by: []
summary: "Reserve N=4 leading VMT slots (Destroy, Equals, GetHashCode, ToString) in every class so a static-TObject receiver can dispatch to a descendant's override, with --compact-classes opting out to today's behaviour and the ESP target defaulting to compact. Implements decide-tobject-root-methods-dispatch-model; unblocks feature-pascal-builtin-tobject-class and the generics corpus rung."
status: done
owner: agent-A
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

## What landed (2026-08-21)

**N = 4, `--compact-classes` = N 0.** `RootVMTSlotCount` / `RootVMTSlotOf`
(`compiler/symtab.inc`) are the ONE place the count and the name→slot map live;
no VMT slot literal was added anywhere else. Sites:

| file | change |
| --- | --- |
| `defs.inc` | `ROOT_VMT_*` constants, `CompactClasses` / `CompactClassesExplicit` |
| `symtab.inc` | `RootVMTSlotCount` / `RootVMTSlotOf`; the implicit-root tail in `FindUMeth`; the empty-window re-base in `AddUMeth` |
| `pasparser_decl.inc` | root class reserves `RootVMTSlotCount`; `override` of a root name takes its fixed slot; the `--compact-classes` refusal |
| `pyparser.inc` | the same reservation for a root NilPy class |
| `pasparser_prog.inc` | TObject's own VMT grown to N; `EnsureTObjectRootMethods`; `FillRootVMTSlotDefaults`; the `.Equals/.GetHashCode/.ToString` pre-scan trigger |
| `builtin/builtin.pas` | `__pxxTObjectEquals` / `GetHashCode` / `ToString` — the defaults, in Pascal, so no per-backend work |
| `compiler.pas` | `--compact-classes` / `--no-compact-classes`; `--platform=esp` implies compact unless stated |

Two things the plan did not predict, both measured rather than reasoned:

- **The defaults must be LAZY.** Forcing `builtin` into every class program costs
  **+42 KB** at default `-O` (58,812 → 100,558 B), so the rows are minted at the
  END of pass 1 (after every `uses`), not beside the ambient units, and the token
  pre-scan pulls the unit only for a DOT-preceded `.Equals` / `.GetHashCode` /
  `.ToString`. Without the builtin unit there are no rows and the call is the
  ordinary "no such member" error — a refusal, never a nil dispatch.
- **`AddUMeth` was mis-basing an empty method window.** `UClsMBase` is fixed at
  class-mint time, so a class that gets its FIRST method later — exactly TObject,
  minted at startup — claimed another class's row as its own. `Equals` landed at
  the tail while the window still pointed at index 0, so `o.Equals(p)` reported
  "no such member" while `o.ToString` worked. Latent for any late-first-method
  class; fixed generically (re-base an empty window).

`class(TObject)` still resolves to parentCi = -1, so the chain walk cannot see
TObject's rows — `FindUMeth` gained the implicit-root tail for exactly the names
that have a reserved slot. Dispatch is through the slot, so a descendant's
override wins on a base-typed receiver.

Verified: `test/test_tobject_root_methods.pas` output is IDENTICAL to FPC 3.2.2's
on the same source, natively and under qemu on **aarch64 / arm32 / riscv32 /
i386**. `--compact-classes` refuses the override by name
(`test_tobject_root_methods_compact_fail.pas`). NilPy classes still dispatch
(`Animal`/`Dog` overriding through a list). `gate.sh quick` GREEN.

## Not done, deliberately — follow-ups filed

- **The `Destroy`/`Create` materialisation hack is NOT deleted**, and this
  write-up does not claim it: compact mode still reverts to N = 0, so the hack is
  still the compact path. The N = 1 compact variant is unmeasured and left open.
- **`Destroy` has no TObject row and slot 0 is left nil** when nothing overrides
  it. That exposed a REAL pre-existing bug, filed separately: `b.Free` through a
  base reference never runs the descendant's `Destroy` when the base declares
  none — FPC runs it. See [[bug-p-free-through-base-reference-skips-destroy]].
  The reserved slot 0 is what makes that fix cheap now.
- **`--emit-obj` ABI split** not diagnosed: two objects with different N disagree
  on slot numbers. Filed as [[feature-a-emit-obj-record-class-abi-mode]].
- **Docs**: nothing in `docs/**` documents `--platform=esp` today, so there is no
  page to extend without opening a Track D lane. The implication is recorded here
  and in `compiler.pas` beside the flag.
- The NilPy-vs-Pascal VMT emitter collapse (the `vmtSlots < 1` floor drift) is
  still two implementations of one concept; untouched, still worth doing.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
