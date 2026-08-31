---
prio: 80
track: A
type: meta
status: backlog
found: 2026-08-31
found-by: frank-user, at the owner's direction
owner: ""
blocked-by: []
summary: "Standing umbrella, priced ABOVE bug fixing by the owner 2026-08-31. FIRST CHILD DONE: the general x86-64 relocatable object writer landed 41045d7b4 (frankC) -- a gcc-built main now links a pxx object and calls into it, and clang and tcc link the same object; export surface is the C-convention routines, and a link needs -no-pie. What remains: i386/arm32/aarch64 object output (p70, and i386 is the one that MATTERS -- x86-64 never diverged, so it structurally cannot settle decide-does-a-c-function-always-use-the-c-abi; i386 can), position-independent x86-64 output, --shared for compiled sources (blocked on the same backend work, and -no-pie cannot rescue a .so), and a Pascal `library` unit (now worth LESS than it looked -- `cdecl` on a definition is already a working export spelling). pxx can now be linked into something; it still cannot be linked into everything."
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

**Being linked into something else — now partly closed.** Updated 2026-08-31,
after 41045d7b4; the original text is one paragraph down, because the diagnosis
in it is what the fix was built on.

- `--emit-obj` writes a general relocatable object for **x86-64, xtensa and
  riscv32**. On x86-64 the export surface is the C-convention routines and a
  link needs `-no-pie`. **i386, aarch64 and arm32 still refuse** —
  [[feature-a-object-output-for-i386-arm32-and-aarch64]], and i386 is the one
  the C-ABI decision waits on.
- `--shared` is still `.asm`-frontend only (`compiler.pas:1238`), and for a
  reason the `.o` did not have to face: a `.so` is relocated at load, so the
  absolute model `-no-pie` accepts cannot work there at all
  ([[feature-a-shared-library-output-for-compiled-sources]]). A Pascal `library`
  unit still does not parse (`expected 'begin' before 'library'`) —
  [[feature-p-a-pascal-library-unit-does-not-parse]], and worth less than it
  looked, since `cdecl` is now a working export spelling.

**The original diagnosis, which is what the fix was built on:** there were **two
object writers, dispatched by architecture, when the discriminator should be
what the object has to carry.** That is now what `compiler.pas` asks.

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

- [[feature-a-a-general-x86-64-relocatable-object-writer]] — the writer.
  **DONE, landed 41045d7b4** (frankC, 2026-08-31). A gcc-built `main` links a
  pxx object and calls into it; clang and tcc agree on the same object.
- [[bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64]] — the
  refusal message names a set excluding a working target. p25, cheap.
- [[feature-a-object-output-for-i386-arm32-and-aarch64]] — **i386 DONE**, same
  day. It was priced p70 because it is the target that can settle the C-ABI
  decision below, and **it did, within minutes of linking**: see that decision's
  TRIGGER FIRED section. It also turned up
  [[bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function]], invisible until
  something outside pxx could call in.
- [[feature-a-object-output-for-arm32-and-aarch64]] — p45, the remainder. Second
  and third oracles for a question now answered once; aarch64 is gated on its
  own ABI question first.
- [[feature-a-x86-64-object-output-is-position-dependent]] — p50. `-no-pie` is
  the current contract; lifting it is backend work.
- [[feature-a-shared-library-output-for-compiled-sources]] — p50, blocked on the
  same backend work, and **`-no-pie` cannot rescue a `.so`**.
- [[feature-p-a-pascal-library-unit-does-not-parse]] — p40, Track P, and worth
  **less** than it looked before the writer landed: `cdecl` on a definition is
  already a working export spelling, so `library`/`exports` is a second
  declarative one. Compat, not capability.

The last four were the "not yet filed, deliberately" set. They are filed now
because the writer's shape is known, so each is written against a real interface
rather than a guessed one — and two of them **changed shape** in the process:
the `.so` turned out to be blocked on the backend rather than on a writer, and
`library` lost most of its value to the export surface the writer already has.

## Unblocks

[[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]
— deferred *on this*, with the trigger named there.

**TRIGGER FIRED 2026-08-31 — the measurement is in and says OPTION A.** The
x86-64 writer settled nothing, exactly as the third bullet above predicts: that
target never diverged. The i386 writer, landed hours later, settled it in one
run. With `CProcUsesCAbi` FALSE — a standalone C unit, the landed option B —
two integer arguments arrive **reversed** (`i_ii(1,2)` returns 21) and every
`double` argument and return is **-nan**, under a `gcc -m32 -no-pie` caller.
With it TRUE (Pascal `cdecl`, same signatures, same object writer, same
caller): all correct. Table, controls and the three limits of the claim are in
the decision file. **Awaiting the owner's ruling** — it is evidence, not a
re-ruling, and the change is one clause.

This is what the umbrella was priced for, and it is worth stating plainly: the
object writer did not answer the question, it built the instrument that could.

## The gate this must not break

`--emit-obj` on xtensa/riscv32 works today and is what the ESP path uses. A
rewrite that unifies the two writers must keep those green; they are the only
evidence any of this works at all.
