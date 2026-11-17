---
track: ESP
tags: [xtensa, object-writer, cfront, crtl, busybox, gibux]
prio: 10
type: feature
blocked-by: []
summary: "Hosted windowed xtensa objects (--emit-obj --platform=posix) now carry an .init_array slot pointing at an init thunk that fills their initialised globals (pxx keeps most of them in .bss and fills them at run time). crtl's __pxx_run_initializers, which the process entry now always calls on this route, walks __init_array_start..__init_array_end before main. Before, only the object holding main ran its initialisers, at the top of main, so every other object's globals read zero. In BusyBox that was all of libbb/messages.c and every table, and hush segfaulted in fputs after its banner. A custom linker script must KEEP .init_array between those two symbols; test/xtensa_pie_prog.ld shows how, and without them the link fails loudly."
status: done
owner: unassigned
---

# xtensa objects run their initialisers

pxx2 reported it from BusyBox on Gibux. Repro: /data/tmp/pxxrepro/def.c + use.c printed `[] [(null)] 0` on xtensa and `[hello world] [two] 5` on x86-64.

## Changes
- **cparser.inc**
  - The C init thunk (CompilePendingGlobalInits + deferred aggregate inits) is emitted for hosted windowed xtensa objects too (xtInitThunk), 4-aligned, without the environ call, which is the entry's job.
  - The finalizer thunk is not emitted on this route.
  - CNeedsEnvironInit is true on this route, so the entry stub calls __pxx_run_initializers. Under --shared-runtime that call is an external call into the runtime object.
- **symtab.inc**: EmitSharedThunkPrologue/Epilogue gain an xtensa arm: entry, a15 = sp, 128 bytes of scratch, a7 bias; retw.
- **elfwriter.inc**
  - Both ESP-family object writers emit .init_array (SHT_INIT_ARRAY, 4 bytes) plus .rela.init_array (R_XTENSA_32 against .text + the thunk's offset) when the object has a thunk (ObjInitArrHas).
  - ObjDataIsImport treats __init_array_start/__init_array_end as imports even inside the runtime object. Otherwise its copy of crtl kept private slots, and the walk called through a nil pointer.
- **lib/crtl/src/unistd.c**: __pxx_run_initializers walks the array on xtensa object builds (__PXXRT_MARKER).

## Test
tools/check_xtensa_shared_runtime.py: test/c_xtensa_srt_part.c now defines a char array, a pointer table, an int and a struct table. Main's object prints them under qemu-xtensa, and the result matches gcc. The PIE link uses the updated test/xtensa_pie_prog.ld. The previous compiler gives `[] [(null)] 0 (null)0`.
