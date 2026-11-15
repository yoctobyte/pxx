---
slug: feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc
track: C
prio: 55
type: feature
status: backlog
created: 2026-11-15
found-by: size root-cause measurement of toybox 0.8.15 (default build, 3ae36d29f5, --function-sections)
tags: [cfront, codegen, size]
blocked-by: []
summary: "pxx's toybox is 1,688,048 bytes, static with its own libc. gcc's is 475,648 (-Os, dynamic glibc), and 2,037,248 stripped if linked static. On toybox's own code pxx emits ~3.6x gcc: 838 shared functions are 838 KB vs 286 KB, a ratio of about 3.3 at every function size; pxx executes 5.0x the instructions. Gap breakdown: codegen density ~743 KB (61%); runtime in the file ~300 KB (25%, only because glibc is a .so for gcc; weak merging works, no duplicates); C string literals ~190 KB (16%), each carrying a 32-byte AnsiString header plus 16-byte alignment (154 KB of headers over 4,805 literals, 35 KB padding; only 5.5 KB is duplicate text). -O2 changes nothing for C (byte-identical sections). Fixes by cost: (1) emit C literals as plain bytes in .rodata, about -190 KB; (2) drop the per-call stack realignment where the frame depth is already known, 18 B x 8,669 calls, up to -156 KB; (3) register allocation for locals (rbp slot traffic 307 KB + movslq reloads 56 KB), the big one, with cheap peepholes meanwhile (branch on the compare instead of setcc/movzb/cmp, -40..55 KB; add/sub $0, -19 KB). Scripts and data: the session scratchpad tbsize/ (gone after the next wipe)."
---
