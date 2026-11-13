---
track: E
tags: [xtensa]
prio: 60
type: bug
blocked-by: []
summary: "IREmitBodyXtensa's retry loop restored CodeRef, Fixups, GlobFix, CallFix, DynCall and IramCallFix, but not ProcAddrFix. When a second pass emitted different bytes, the pass-1 entry patched a closure's code address into the middle of an instruction (SIGILL / SIGSEGV)."
status: done
owner: claude
---

# A relaxation retry leaves stale proc-address fixups

The Xtensa body emitter re-emits a body when a pass has to change it:
- forward-jump relaxation, for a body over 128 KiB;
- a wider outgoing area;
- since 2026-11-13, the per-body a7 bias.

Each table the body appends to has to be rewound to its count at the start
of the retry. The list held six tables. IR_PROC_ADDR's ProcAddrFix was not
on it.

This stayed latent because the old triggers re-emitted the same bytes for
the code that takes a procedure address. The stale pass-1 entry then pointed
at a valid position, the same one the pass-2 entry patched. The per-body
bias moves code by 3 bytes on its second pass. test/test_nilpy_escaping_closure_many_captures.npy
(`mk8`, which takes `inner`'s address) then died in qemu: the bytes at the
old position had been overwritten (`movi.n a0, 13; bltz a7, ...` where the
object has two stores). Whether the stale patch hit live code depended on
literal-pool alignment, so builds that differed only in which bodies were
re-biased failed or passed.

Fix: save ProcAddrFixCount with the others and restore it each pass.
The table list in the loop's comment now names it.

Found by `make test-xtensa` (xtensa-windowed/closurecaps). A forced retry
with identical bytes did NOT reproduce it, which is how the stale-table
theory was confirmed: only a pass that moves code exposes the bug.
