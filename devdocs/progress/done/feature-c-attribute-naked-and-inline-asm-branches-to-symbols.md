---
slug: feature-c-attribute-naked-and-inline-asm-branches-to-symbols
track: C
prio: 45
type: feature
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [cfront, asm]
blocked-by: []
summary: "`__attribute__((naked))` is accepted and ignored, so the function still gets a prologue and epilogue. AT&T inline asm (asmatt.inc) can branch only to numeric local labels, not `jmp`/`call` a symbol. micropython's py/nlrx64.c needs both: its nlr_push is a naked function that tail-jumps to nlr_push_tail. The build used -DMICROPY_NLR_SETJMP=1 instead."
---

# `__attribute__((naked))`, and inline asm that branches to a symbol

## Found by

micropython v1.24.1, unix port, py/nlrx64.c:

```c
__attribute__((naked)) unsigned int nlr_push(nlr_buf_t *nlr) {
    __asm volatile (
        "movq   (%rsp), %rax  \n"
        ...
        "jmp    nlr_push_tail \n"
    );
}
```

Both features are needed together:

1. **naked**: no prologue or epilogue. pxx parses the attribute and drops it,
   so the asm runs with a pushed rbp and reads the wrong return address.
   gcc rejects anything in a naked function except basic asm. Supporting it
   means: no frame, no locals, no implicit return.
2. **A branch to a symbol**: `jmp sym` / `call sym` in asmatt.inc. Only `1f`/`1b`
   numeric labels are resolved today. It needs a relocation, or a fixup against
   the proc table, like an ordinary call.

Workaround in the scratch build: `-DMICROPY_NLR_SETJMP=1` (nlrsetjmp.c). The
interpreter runs under it, but the x86-64 native emitter does not support it.
In setjmp mode its `nlr_push` table entry is nlr_push_tail, and only xtensawin
JIT code calls setjmp after it (N_NLR_SETJMP in py/emitnative.c). x86-64 JIT
code therefore leaves its nlr_buf unsaved, and the first exception longjmps
into garbage. That accounts for seven of micropython's tests: native_gen,
native_try, native_try_deep, native_with, viper_globals, viper_try and
viper_with. Confirmed 2026-11-22: with py/nlrx64.c built by gcc (sections
pxx --link refuses stripped: .note.gnu.property, .eh_frame, debug) and the
other 215 files by pxx, without MICROPY_NLR_SETJMP, all seven pass.

Done means: pxx builds py/nlrx64.c itself, and those seven pass. One more
gap showed up on the way: `pxx --link` refuses a gcc object carrying
.note.gnu.property or .eh_frame, which every default gcc object has. Linking
third-party objects is a separate question, not part of this ticket.

Other ports have the same file per arch (nlrx86.c, nlraarch64.c, nlrthumb.c,
nlrxtensa.c, nlrrv32.c), so this is per-target work. x86-64 first.

## Done (2026-11-22), x86-64

- **naked** (clexer.inc carries it as token flag $4000; ParseCSubroutine
  reads it). The body must be basic asm statements only, as gcc requires.
  Their text is lowered as file-scope asm that defines the label
  (CFsaEmitCode). That path already assembles AT&T text, resolves `1f`/`1b`
  and calls functions by name. No prologue, no epilogue, no implicit return.
  Other targets refuse it loudly, and so does `main`.
- **`jmp`/`call` a name** in that code. A name not defined yet gets a
  six-byte slot. If the name is defined later in the unit, the slot becomes
  `nop; E8/E9 rel32` with an ordinary call fixup. Otherwise it becomes
  `FF 15`/`FF 25 [rip+GOT]`, the slot every external call uses, so the
  object writer and the linker see an ordinary import (R_X86_64_PC32 against
  the GOT entry).
- Tests (matched against gcc): c_naked_function (callee-saved stores, a
  return address read at (%rsp), `jmp` to a tail defined later, a numeric
  label, a call); c_naked_branch_to_other_object (two `--emit-obj` objects
  linked with pxx, and with gcc, where the output matches too); an aarch64
  refusal row.
- micropython: py/nlrx64.c built by pxx gives the same bytes as gcc's
  nlr_push. With every unit built by pxx and no MICROPY_NLR_SETJMP, the
  seven native/viper tests pass, and the full suite is 897/908. Its 11
  failures are the same as with gcc's nlrx64.o; 10 of them also fail with gcc.

What is still not covered:
- nlrx64.c takes the naked path only when `__GNUC__ >= 8` (or `__clang__`).
  pxx claims 2.7 (cpreproc.inc explains why), so it takes the
  `optimize("omit-frame-pointer")` path instead. That path is an ordinary
  function with `jmp nlr_push_tail` in its inline asm, which pxx still
  refuses, and could not run correctly under pxx's frame anyway. The scratch
  build passes `-U__GNUC__ -D__GNUC__=8` for that one unit. That exposed
  bug-c-command-line-undef-is-applied-after-every-define, fixed in the same
  commit. Whether pxx should claim a newer gcc is an owner decision:
  decide-what-gcc-version-pxx-claims.
- Inline (non-naked) asm still branches only to numeric labels.
- Targets other than x86-64.
