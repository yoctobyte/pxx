/* pxxcrt_x86_64.S -- the process-entry contract for a freestanding link of
 * pxx-emitted objects. Used by tools/busybox_diff.sh --freestanding.
 *
 * WHY THIS FILE EXISTS AT ALL. pxx's --emit-obj objects define `main' and no
 * `_start', because --emit-obj targets a C toolchain that supplies crt1.o.
 * Everything else a link needs is already in the objects: measured 2026-09-16
 * over 28 busybox objects, the only relocation types are R_X86_64_PC32 and
 * R_X86_64_64, and of 70 undefined references NONE is unsatisfied by another
 * object in the set -- no libc symbol is wanted. So the gap between the
 * current `gcc -o out obj/*.o' and a libc-free binary is this file, not a
 * linker's symbol engine.
 *
 * THIS IS THE MEASUREMENT'S SCAFFOLDING, NOT AN ARCHITECTURE. The end state is
 * feature-a-pxx-cannot-link-its-own-objects' route 2 -- a pxx --link mode, with
 * the compiler emitting its own entry code as elfwriter.inc already does for
 * executables (elfwriter.inc:472). Do not read this .S as a sanctioned shape;
 * it exists so the claim "busybox runs with no libc" is re-derivable in one
 * command instead of living in somebody's /tmp.
 *
 * THE .init_array WALK IS LOAD-BEARING AND ITS OMISSION IS SILENT. pxx's C
 * frontend emits an .init_array thunk that takes (argc, argv, envp) and calls
 * __pxx_set_environ (cparser.inc:13150) -- deliberately the same convention
 * glibc uses for DT_INIT and .init_array alike. Skip the walk and the program
 * still links, still starts, and has a null `environ': a wrong VALUE far from
 * its cause, not a crash.
 */
    .text
    .globl _start
    .type _start, @function
_start:
    /* Linux hands us: rsp -> argc, rsp+8 -> argv[0..argc-1], then a NULL,
     * then envp. rbp is zeroed so a backtrace terminates here rather than
     * walking into whatever the kernel left on the stack. */
    xor  %rbp, %rbp
    mov  (%rsp), %r12            /* argc */
    lea  8(%rsp), %r13           /* argv */
    lea  8(%r13,%r12,8), %r14    /* envp = argv + argc + 1, skipping the NULL */

    /* SysV wants rsp 16-aligned AT the call instruction. At process entry it
     * is 16-aligned pointing AT argc, which is not the same thing, so this is
     * not redundant. argc/argv/envp are already in callee-saved registers, so
     * moving rsp cannot lose them. */
    and  $-16, %rsp

    /* __init_array_start/__init_array_end are PROVIDEd by GNU ld's internal
     * linker script, which is still in force under -nostdlib. If a future
     * linker does not provide them the link FAILS LOUDLY on an undefined
     * symbol, which is the failure mode we want -- an empty range would be
     * indistinguishable from "there were no initialisers". */
    lea  __init_array_start(%rip), %rbx
    lea  __init_array_end(%rip), %r15
1:  cmp  %r15, %rbx
    jae  2f
    mov  %r12, %rdi
    mov  %r13, %rsi
    mov  %r14, %rdx
    call *(%rbx)
    add  $8, %rbx
    jmp  1b

2:  mov  %r12, %rdi
    mov  %r13, %rsi
    mov  %r14, %rdx
    call main

    /* exit(2), not exit_group(231): busybox's applets are single-threaded here
     * and 60 is what a freestanding program without a libc atexit chain wants.
     * .fini_array is deliberately NOT walked -- nothing in these objects
     * registers one that matters, and running it here would be a claim this
     * measurement has not checked. */
    mov  %eax, %edi
    mov  $60, %eax
    syscall
    hlt                          /* unreachable; traps rather than falling into data */
    .size _start, .-_start
    .section .note.GNU-stack,"",@progbits
