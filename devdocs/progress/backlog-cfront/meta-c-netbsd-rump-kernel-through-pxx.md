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
summary: "NetBSD's rump kernel (USB/xHCI/umass/if_wm, Nilix's route to real-hardware drivers) through pxx: 126/485 compiles, nothing links. The full gap list, with minimal gcc-accepted repros, is ~/nilix/docs/rump-pxx/README.md and repros/ (run.sh; PXX= picks the compiler). Lockstep: Nilix waits, and no workarounds go in Nilix. g25 (extern incomplete array, then defined, under --freestanding) is fixed by 1f87a71427; nothing else changed there."
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
