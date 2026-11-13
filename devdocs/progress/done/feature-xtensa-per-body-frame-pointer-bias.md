---
track: E
tags: [esp, xtensa, size]
prio: 60
type: feature
blocked-by: []
summary: "Each windowed Xtensa body now picks its own a7 bias from the frame slots it actually touches. A deep frame's slots below base-64 were an `addi a8, a7, -k` plus the access; moving a7 down to them makes most of those one l32i. Thermostat S3 .text went from 443,199 to 432,587 B (-2.4%), with RAM unchanged."
status: done
owner: claude
---

# Xtensa: a per-body frame-pointer bias

Before this change, a7 was always base - 64 (XT_FP_BIAS, 7dbf6fe4df). Slots
down to base - 64 were one narrow access, while anything deeper was
`addi a8, a7, -k` plus an access at 0. On the 2026-11-13 thermostat that
pattern made up 4,373 of the instructions.

The body emitter now records every frame-slot access on pass 1 (offset and
width; XtFpNote in XtFrameDirect / EmitFrameAddrXtensa). XtChooseFpBias then
prices each candidate bias with the emitter's own forms:
- l32i.n/s32i.n reach 0..60;
- the 3-byte loads and stores reach 1020, 255 or 510 by width;
- addi plus an access within -128, addmi below that.

The candidates are one addi (-64..+124) or one addmi (multiples of 256)
away. A bias is taken only if it saves more than the 3-byte
`addi a7, a7, 64 - B` it costs. When one is chosen, the body is emitted
again, starting with that instruction, and every slot helper reads
XtFpBias instead of the constant.

What holds the moved a7:
- the epilogue and any other code after the body run with it;
- a `try` inside the body restores the try frame's own saved a4..a7 from
  its jmpbuf. Its setjmp runs after the move, so that is the moved value;
- the procedure's CLEANUP frame (a body with managed locals) is different:
  its setjmp runs in the prologue, BEFORE the move. A raise that lands in
  its pad gets the prologue's a7 back while the pad addresses slots at the
  moved bias. EmitProcCleanupLandingPadForTarget therefore moves a7 again
  at the landing. Before that fix,
  test/test_nilpy_sort_is_stable_and_n_log_n.npy segfaulted on xtensa-windowed
  (`__lt__` raising inside TPyList.sort, bias 320). The regression test is
  test/test_a_raise_through_a_deep_frame_cleanup_pad.pas (xtensa-windowed/deeppad);
  it fails without the pad move and passes with it;
- every prologue resets XtFpBias (EmitProcPrologue and the four a7 set
  sites);
- the MAIN body is left alone.

`--xtensa-no-fp-rebias` turns it off. The thermostat object built with it
is byte-identical to the one from before the change.

Measured on the thermostat S3 object (build.sh esp_build flags, WITH_METER):
.text went from 443,199 to 432,587 B (-10,612, -2.4%). .data (1,104) and
.bss (15,964) are unchanged. 59 bodies moved their a7, and 934 of the
4,373 `addi aX, a7, k` instructions went away. The rest are mostly
addresses that are needed anyway, such as var arguments.

The second pass exposed a latent bug: ProcAddrFix was not saved and
restored by the retry loop. See
bug-xtensa-a-relaxation-retry-leaves-stale-proc-address-fixups.md.
