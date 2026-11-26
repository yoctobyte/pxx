---
slug: bug-c-a-numbered-asm-clobber-is-refused
track: C
prio: 50
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx curl + mbedTLS recipe)
tags: [cfront, inline-asm]
summary: "gcc accepts a clobber given as its hard-register NUMBER (mbedTLS aesni.c: `: \"memory\", \"cc\", \"xmm0\", \"xmm1\", \"0\", \"1\"`); pxx refused '\"0\", which is not a register this backend knows'. On x86 0..7 now map to gcc's i386.h order: ax, dx, cx, bx, si, di, bp, sp (e- on i386, r- on x86-64). Test c_asmbar26 against gcc."
---
# A numbered clobber was refused

mbedTLS 3.6.8 `library/aesni.c` clobbers `"0", "1"`: gcc's register numbers
for ax and dx, which the asm uses as `%eax`/`%edx`. `CAsmBuildBlock` looked
each clobber up by name and stopped on "0".

## Fix

0..7 are translated to the name first, in gcc's order (not the instruction
encoding's: gcc numbers dx before cx). Higher numbers (x87, flags, SSE, r8 and
up) are still refused, by name. aesni.c itself still does not build: its
templates are SSE/AES-NI (feature-c-inline-asm-sse-and-aes-ni).
