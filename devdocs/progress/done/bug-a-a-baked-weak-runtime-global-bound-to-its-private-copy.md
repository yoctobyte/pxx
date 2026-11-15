---
slug: bug-a-a-baked-weak-runtime-global-bound-to-its-private-copy
track: A
prio: 60
type: bug
status: done
created: 2026-11-15
found-by: claude-opus (toybox suite, getopt)
tags: [emit-obj, link, static-data]
blocked-by: []
summary: "ObjDataExportSymForOff refused .data-resident globals. Its comment said the export loop writes .bss for every data symbol, which stopped being true when ObjDataShndx learned .data. So once --c-static-data baked a weak crtl global into .data (`int optind = 1;`), every reference inside the object went section-relative to its private copy instead of through the symbol the linker resolves. toybox getopt set its own optind and getopt_long (another object's winning copy) read a different one: 14 getopt tests failed. It now matches both encodings, and the C-initialiser path (ObjCDataRelaSym) asks it for .data globals too. Only weak (runtime) definitions can tell the difference."
---

# A baked weak runtime global bound to its private copy

Test: rows c_srt_dgr and c_srt_dr link the default objects part-first, so
main's references must reach the other object's optind.
