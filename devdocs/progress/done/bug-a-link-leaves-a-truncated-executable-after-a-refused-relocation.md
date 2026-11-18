---
track: A
tags: [linker, elf, link]
prio: 40
type: bug
blocked-by: []
summary: "`pascal26 --link` that refuses an input object's relocation (R_X86_64_32 in a gcc -fno-pie object: 'pxx emits R_X86_64_64, ... only') still leaves the -o file behind, truncated ('ELF ... missing section headers'). Running it segfaults, which reads like a miscompile. The undefined-reference path says 'nothing written' and writes nothing; this one should do the same."
status: done
owner: claude-dupwt
---

# --link leaves a truncated executable after a refused relocation

Seen 2026-11-18 linking 311 pxx LVGL objects plus one gcc object built with
`-fno-pie` (R_X86_64_32 relocations). The error is printed, the exit code is
non-zero, and `file lvp_sw` reports "statically linked, missing section headers
at 7877176". A script that runs the output after the link misreports the
failure as a crash.

Fix: write the output to a temporary name and rename it on success, or delete
it on any error path, as the undefined-reference path already avoids writing.

## Fixed (2026-11-18)

`ElfLnkAbort` (elfreader.inc) closes and unlinks the output and prints
"nothing written". It replaces the plain close on the four error paths after
the output is opened: a short re-read, a refused or out-of-range relocation in
.text or in RW data, and a failed .rodata/.multiboot fill. Proof: row
c_lnkref26 links a pxx main with a gcc `movl $gv` object (R_X86_64_32).
The link fails and no file exists. A good link of the same main still runs.
