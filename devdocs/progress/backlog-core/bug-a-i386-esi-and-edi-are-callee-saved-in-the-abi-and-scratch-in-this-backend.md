---
slug: bug-a-i386-esi-and-edi-are-callee-saved-in-the-abi-and-scratch-in-this-backend
title: "i386: esi and edi are callee-saved in the System V ABI and scratch in ir_codegen386"
track: A
prio: 40
type: bug
status: open
created: 2026-09-04
found-by: frankC
summary: "The i386 System V ABI makes **eax, ecx and edx** the scratch registers and **ebx, esi, edi and ebp** callee-saved. `ir_codegen386.inc` treats esi and edi as scratch throughout — `mov esi, eax` (line 64), `test esi, esi`, `mov [edi], al`, `inc esi` / `inc edi` in the string paths — and saves neither, while it DOES push and pop ebx explicitly wherever it needs it (lines 472, 486). So a pxx-compiled i386 function preserves ebx and does not preserve esi/edi. **Nothing in the busybox corpus is hurt by this**, because every translation unit there is pxx-compiled and pxx is self-consistent; it bites only where a pxx-compiled i386 function is called from code built by another compiler, which is the direction `--emit-obj` exists to make possible. Found while adding the i386 inline-asm register pool (`bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386`), which matches the backend rather than the document and says so; the pool is not the defect and changing it alone would not fix this."
---

# What is measured

`ir_codegen386.inc`, esi and edi as scratch with no save:

```
64:   EmitB($89); EmitB($C6);   { mov esi, eax (src) }
295:  EmitStoreStrLen386(1, 7, ...);   { [edi] := ecx }
302:  EmitB($46);               { inc esi }
303:  EmitB($47);               { inc edi }
```

and ebx handled the other way, deliberately:

```
472:  EmitB($53);               { push ebx }
486:  EmitB($53);               { push ebx }
```

So the backend has a convention and it is internally consistent. It is simply
not the i386 System V one, in exactly two registers.

# Why it has not shown up

Every consumer so far is pxx-compiled end to end. busybox at the 394-applet
scope links 521 pxx objects with `gcc -m32` doing nothing but the link, and
crtl is pxx too — so there is no frame anywhere in that program that expects
esi or edi to survive a pxx call.

The reachable case is a pxx `--emit-obj` object linked into a program whose
other objects are gcc's, where a gcc caller holds a live value in esi or edi
across a call into pxx code. That is the whole point of separate compilation,
so this is a real defect rather than a theoretical one — it just has no
reproducer in the corpus today.

# What a fix costs, and why it is not free

Two options, and the choice is the ticket:

- **Save and restore in the prologue** for any function whose body touches
  esi/edi. Correct, and it puts a push/pop pair on a large number of functions
  — the string paths use edi constantly.
- **Stop using them**, leaving eax/ecx/edx plus spill slots. Correct, and it
  costs a register file the backend is already short of on a 32-bit target.

Measure before choosing: count the functions that would gain a pair, and the
extra spills the second option would add, on a real program rather than on a
test.

# The inline-asm pool is downstream of this and is not the bug

`CAsmPool386` (`cparser.inc`) is `ecx esi edi eax edx`, and `CAsmRegIsCalleeSaved`
answers `ebx/ebp/esp` on i386. Both are written to match what this backend
actually preserves, with a comment saying so and pointing here. If this ticket
resolves toward the ABI, those two are part of the same change — and until it
does, making the pool three registers on its own would refuse busybox's
`tls_pstm_mul_comba.c` while fixing nothing, since the enclosing function would
still clobber esi and edi on its own account.
