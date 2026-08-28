
---

## The proposed fix has an in-repo POSITIVE CONTROL — measured 2026-08-28

Do not argue this fix from first principles. The same codebase already contains the same
missing-arm shape with the **opposite** failure mode, and the difference is one `else`.

`EmitZeroFrameSlot` (`compiler/ir_codegen.inc`) dispatches per target and ends:

```pascal
  else
    Error('compiler error: EmitZeroFrameSlot: unhandled target');
```

It has no wasm32 arm either. The observed result is
`compiler error: EmitZeroFrameSlot: unhandled target` on
`test_dynarray_insert_delete.pas` — **a clean refusal naming the routine and the target**,
filed as `bug-a-emitzeroframeslot-has-no-wasm32-arm` at **p55**.

The chains in this ticket have no terminal `else`, so the same omission produces
`PXXStrLoadFile` allocating on an uninitialised size — **p70, and it took a deliberate audit
to find.**

| | missing arm, terminal `else` | missing arm, no terminal `else` |
| --- | --- | --- |
| example | `EmitZeroFrameSlot` | `PXXSysOpenRO`, `PXXSysLseek` |
| result | compiler error naming routine + target | uninitialised return, arbitrary allocation |
| found by | the first program that hit it | a deliberate audit, weeks later |
| prio it earned | 55 | 70 |

**The 15-point gap between them IS the value of the terminal `else`**, priced by this repo's
own triage rather than asserted. That is the whole argument for this ticket, and it is
empirical.

---

## CORRECTION 2026-08-28 — the positive control above is WRONG in two ways

The table above was written by frank-coordinator and is corrected here rather than edited
away, because the wrong version is the one someone may already have read.

**Error 1 — wrong file.** `EmitZeroFrameSlot` is defined at **`compiler/symtab.inc:10074`**,
not in `ir_codegen.inc`. The original grep ranged over `compiler/*.inc` and the file was never
checked.

**Error 2 — and it inverts the point.** `EmitZeroFrameSlot` has **TWO** per-target chains, one
per size class, and the table described only one:

| chain | targets named | terminal arm | behaviour |
| --- | --- | --- | --- |
| **wide** (`nBytes > TARGET_PTR_SIZE`) | i386, arm32, aarch64, riscv32, xtensa | `Error(...)` | **fails LOUD** — what the table described |
| **narrow** (`nBytes <= TARGET_PTR_SIZE`) | i386, arm32, aarch64, xtensa, riscv32 | **bare `else` that IS the x86-64 implementation** | **falls OPEN** |

The narrow chain is the one **every managed scalar** goes through. So the routine offered as
this family's counter-example is itself a member of it.

### The corrected argument is STRONGER, which is why it is worth restating rather than deleting

The 55-vs-70 contrast still holds, but not for the reason given. Both behaviours live in **one
routine, forty lines apart** — so this is no longer a comparison across two files with other
differences, it is a controlled one:

> **A reader sees the loud arm. Every program runs the silent one.**

That is the whole cost of a missing terminal `else`, demonstrated inside a single routine with
everything else held constant.

### The general rule this yields

> **A dispatch chain whose last arm is a REAL TARGET rather than an error is a fall-open chain
> wearing the shape of an exhaustive one.**

Six named arms and an unnamed seventh reads as *"the default"* when it is in fact **x86-64** —
the bytes are `mov qword [rbp+off], 0`. That is why reading missed it and a probe found it, and
it is the third instance of `refactor-a-target-dispatch-chains-fail-open`'s general case.

**Severity, measured rather than assumed** (frankwasm, `ed1d37a8b`): a probe build emitting
nothing there produces **byte-identical `.wasm` for three slices** — `Code[]` is unread on that
target, so nothing wrong has ever come out of it. **Latent, not active. Prio stays 55, for the
opposite reason to the one recorded.**

**And the guarantee whose own header says it has ONE owner has three mechanisms on wasm32** —
the backend's prologue pass, the x86-64 fall-through, and the loud `Error`.
`root-cause-over-microfix.md` calls three mechanisms for one concept a design flaw, so the fix
here is plausibly **deleting an arm rather than adding one**.
