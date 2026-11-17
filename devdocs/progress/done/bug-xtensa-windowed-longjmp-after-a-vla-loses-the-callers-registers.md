---
track: ESP
tags: [xtensa, windowed, setjmp, crtl, busybox, gibux]
prio: 5
type: bug
blocked-by: []
summary: "On windowed xtensa, a longjmp back into a frame that made a VLA (or alloca) after its setjmp returned with that frame's a4-a7 corrupted. In BusyBox, run_nofork_applet came back with a7 = 0, and every NOFORK applet that exits through xfunc (uname -a ...) killed the shell. The VLA lowers sp, and its contents cover the 16 bytes under the setjmp-time sp: the grand-caller's a0-a3, whose a1 word the caller's window underflow reads (sp-12) to find its own a4-a7. setjmp now also saves those four words (jmp_buf words 11..14) and longjmp writes them back under the restored sp, as glibc and newlib do."
status: done
owner: unassigned
---

# Windowed longjmp after a VLA lost the caller's registers

pxx2 found it on Gibux (StoreProhibited at 0x2c, a7 = 0, at run_nofork_applet+0xa8 right after __pxx_setjmp returned the second time) and diagnosed it. Repro: /data/tmp/pxxrepro/longjmp_vla.c. gcc prints `rc 13 (want 13)`; pxx windowed segfaulted under qemu-user. call0 was never affected.

## Fix
cparser.inc EmitCSetjmpStubs (windowed):
- setjmp copies [caller_sp-16 .. caller_sp) into jmp_buf offsets 44..56. The spill chain has just forced those words to memory.
- longjmp writes them back to [saved caller_sp - 16] before the forged RETW.
jmp_buf is 64 bytes and the windowed layout now uses 60.

## Test
test/c_xtensa_setjmp.c gains vla_run, pxx2's shape: setjmp, then a VLA filled with argv including its NULL, then a longjmp from 13 frames down. The expected output is gcc's (`vla 13`). The previous compiler's windowed build crashes before printing it; call0 passes either way.

Note: windowed C programs are built as --emit-obj and linked with ld (the hosted C entry stub is call0 only). A windowed "repro" compiled straight to an executable does not build at all, and with its output hidden it looked like a failing run.
