
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
