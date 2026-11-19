---
slug: meta-c-netbsd-rump-kernel-through-pxx
track: C
prio: 50
type: meta
status: backlog
created: 2026-11-15
found-by: pxx (Nilix seat) trial build at 4225bfacc1
tags: [cfront, nilix, freestanding, inline-asm, link]
blocked-by: []
summary: "STATUS 2026-11-19 (rd): the summary below this line was stale. A librump built entirely by pxx LINKS AND BOOTS since ac091638d7 (2026-11-18, frank-user: 229/229 objects renamed and archived as NetBSD does, gcc's librumpuser, \"rump kernel init complete, rv 0\"); 487/488 compile at 7deee32b0f. Every repro in Rainyday docs/rump-pxx compiles and its silent-gap check matches gcc (re-measured 2026-11-19, below; s09 fixed in 7dade5d0b0). Open: the driver libraries Rainyday wants (usb/xhci/umass/if_wm) linked and attached from pxx objects, and .rodata for C const objects in x86-64 objects (s01). Original: 126/485 compiled, nothing linked."
---

# NetBSD rump kernel through pxx

The source of truth is ~/nilix/docs/rump-pxx/README.md (gap numbers below are its own).
This is the order pxx takes them in, and why.

1. **Silent wrong objects that any C program can hit:**
   - S10: `extern T *const a, *const b;` defines b.
   - S11: a function declared through a function typedef becomes an object.
   - S6: `mode(__DI__)` gives size 4.
   - S7: a union cast faults.
   - S5: `weak` is ignored.

   They pass compilation and break at link or run time, so they come before
   anything that only refuses.
2. **The two items that block almost every file:** gcc's predefined type
   macros (1) and `_Pragma` (2).
3. **Declarators** (8, 9, 12, 18), plus `__typeof__` / `__typeof_unqual__` /
   `__builtin_offsetof` (7, 10, 14).
4. **Pointer casts in static initialisers under `--freestanding`** (6).
5. **Inline asm** (3-5): skip unused static inline bodies first, then constraint
   alternatives and memory outputs. feature-c-inline-asm-plus-m-read-write-memory-operand
   is part of 5.
6. **Freestanding builtins and header synthesis under `-nostdinc`** (11, 13, 15-17).
7. **The rest of the silent object gaps:**
   - S1: section attribute, `__start_`/`__stop_`.
   - S2: constructors in `--emit-obj`.
   - S3/S4: file-scope asm, asm labels.
   - S8: `__thread` in objects.
   - S9: visibility.

   S1 and S2 need the linker side too.
8. **Tools:**
   - a `.S` assembler;
   - `--link` taking archives and foreign objects;
   - nm/objcopy equivalents (host binutils already work on pxx objects).

Each fixed gap gets its own done ticket with the repro as a test.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).

## Re-measured 2026-11-19 (rd)

Rainyday docs/rump-pxx/repros/run.sh against pxx at 8d21004d32 plus the
visibility fix: all 53 repros (g01..g40, s01..s12) compile. Checked the
s* repros' CHECK lines against gcc's objects:
- s02 (constructors), s03 (file-scope asm: feature-c-file-scope-asm-that-defines-code),
  s04, s05, s10, s11, s12: symbols match gcc's.
- s06 `8 1` and s07 `5`: gcc's output.
- s08: .tdata with R_X86_64_GOTTPOFF (initial-exec; gcc writes local-exec
  TPOFF32 for an executable-bound object; both link).
- s09: fixed here (bug-c-visibility-attribute-was-ignored).
- s01: the section and __start_/__stop_ work; the pointed-to
  `static const struct ls lsv` is .bss filled at start-up in a hosted object
  and .data with --freestanding, where gcc uses .rodata. Writable rather than
  read-only, same values.
What is left is the real link of the rump libraries, which needs the
Rainyday side to try it again.

