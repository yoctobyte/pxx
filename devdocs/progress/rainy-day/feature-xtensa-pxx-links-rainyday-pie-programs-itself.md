---
track: ESP
tags: [esp, xtensa, rainyday, pie, link]
prio: 70
type: feature
blocked-by: []
summary: "pxx's own --link could write the Rainyday/S3 user-program format (32-bit ET_DYN, no PT_INTERP, only R_XTENSA_RELATIVE, code alone in the R+X PT_LOAD, as tests/xtensa/prog.ld lays it out) so no GNU ld is needed. Optional: the ld route works and is tested."
status: open
owner: unassigned
created: 2026-11-19
---

# pxx links Rainyday PIE programs itself

The rest of feature-xtensa-gibux-user-programs-as-et-dyn-pie (done
2026-11-19). Today the programs are linked by Espressif's ld:

    pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh --xtensa-abi=windowed --no-ro-data --emit-obj prog.c prog.o
    xtensa-esp32s3-elf-ld -pie --no-dynamic-linker -e app_main -T prog.ld prog.o -o prog

That is the GNU-free goal's last outside tool for these programs. The shape
is in ~/rainyday/tests/xtensa/prog.ld; tools/check_xtensa_pie_link.py checks
the result.
