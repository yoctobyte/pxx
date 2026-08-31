---
prio: 80
track: A
type: meta
status: backlog
found: 2026-08-31
found-by: frank-user, at the owner's direction
owner: ""
blocked-by: []
summary: "Standing umbrella, priced ABOVE bug fixing by the owner 2026-08-31. pxx can CALL OUT (elfwriter emits DT_NEEDED/dynsym/GOT-indirect) and BE CALLED BACK (gtk3.pas:47 hands a handler to g_signal_connect_data and GTK calls into us, in production). It cannot BE LINKED INTO anything: no general relocatable object on x86-64/i386/arm32/aarch64 (--emit-obj is xtensa|riscv32 for general code, .asm-only on x86-64), and --shared is .asm-frontend only (compiler.pas:1238). So the ABI machinery exists and the ET_REL writer does not -- a narrower gap than 'we cannot link'. Beyond the capability itself this is the ONLY thing that makes the C-ABI convention externally checkable: link a pxx object against a gcc-built caller on i386 and decide-does-a-c-function-always-use-the-c-abi stops being an argument and becomes a measurement."
---

# Meta: pxx produces linkable code, not just programs

- **Type:** meta (governance / index / epic) — **Track A**, with **C** on the
  ABI half.
- **Status:** backlog (standing index — new object/link/export work links here)
- **Origin:** the owner, 2026-08-31, reviewing
  [[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]:
  *"we can craft object files for any target, right? if not, that is a big
  missing feature I overlooked"* — and, on being shown the state:
  *"to me this feels like one of the top prio things to do — above further bug
  fixing."*

## What already works — do not rebuild it

Measured 2026-08-31, not assumed:

- **Dynamic linking out.** `elfwriter.inc` emits `DT_NEEDED` (one per distinct
  soname), `dynsym`/`dynstr`, and GOT-indirect calls.
- **Callbacks in.** `lib/pcl/gtk3.pas:47` passes a handler pointer to
  `g_signal_connect_data`; GTK then calls *our* code. Foreign code calling us,
  in production, today.
- **Per-function call type.** `ProcCdecl[procIdx]`, read through the single
  named predicate `CProcUsesCAbi` (`symtab.inc:11599`).

So the prerequisites the owner expected to exist **do** exist. The gap is one
direction only.

## What is missing

**Being linked into something else.**

- `--emit-obj` writes a general relocatable object for **xtensa and riscv32
  only**. On x86-64 it accepts `.asm` sources alone (text + global labels +
  extern calls); a Pascal/C/NilPy program is refused. i386, aarch64 and arm32
  refuse outright.
- `--shared` is `.asm`-frontend only — `compiler.pas:1238` says so in the option
  handler itself. A Pascal `library` unit does not even parse
  (`expected 'begin' before 'library'`).

The diagnosis is already banked in the child ticket and is sharper than "not
implemented": there are **two object writers, dispatched by architecture, when
the discriminator should be what the object has to carry.**

## Why it is priced above bug fixing

1. **It is a capability gap, not a defect** — it does not compete with bugs on
   the same axis. Nothing is wrong; a whole class of use is absent.
2. **It converts an unanswerable design question into a measurement.** Today the
   C-ABI convention on i386/arm32/aarch64 is unobservable from outside: the
   corpus is self-consistent before *and* after any change, which is exactly how
   that bug survived on three targets. An ET_REL writer lets a gcc-built caller
   be the oracle.
3. **The live boundary and the divergent targets do not overlap.** GTK callbacks
   work on **x86-64**, which is the one target that *never* diverged — it has
   always used `EmitParamSpillsForTarget`. So today's working callbacks prove the
   machinery and say nothing about the three targets in question. Correct about
   something else.

## Children

- [[feature-a-a-general-x86-64-relocatable-object-writer]] — the writer. p80.
- [[bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64]] — the
  refusal message names a set excluding a working target. p25, cheap.
- **Not yet filed, and deliberately so** — cross-target ET_REL
  (i386/arm32/aarch64), `--shared` beyond the `.asm` frontend, and a Pascal
  `library` unit. File them when the x86-64 writer's shape is known; filing
  them now would guess at an interface that does not exist.

## Unblocks

[[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]
— deferred *on this*, with the trigger named there.

## The gate this must not break

`--emit-obj` on xtensa/riscv32 works today and is what the ESP path uses. A
rewrite that unifies the two writers must keep those green; they are the only
evidence any of this works at all.
