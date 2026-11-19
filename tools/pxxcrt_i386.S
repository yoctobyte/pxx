/* pxxcrt_i386.S -- the process entry for linking pxx's i386 objects with the
 * host linker:  tools/pxx_link_i386.sh -o out a.o b.o ...
 *
 * `pascal26 --link` is x86-64/aarch64 only: it reads ELF64 objects, and the
 * i386 object writer emits ELF32 REL. pxx's objects need no libc (crtl is
 * inside them), so an i386 link is `ld -m elf_i386 -nostdlib -static` plus
 * this _start. feature-c-i386-link-for-c-objects.
 *
 * What it owes the program, as crt1.o + __libc_start_main would provide it:
 *   1. argc, argv, envp off the initial stack (cdecl: pushed right to left).
 *   2. .init_array, walked with (argc, argv, envp). pxx's C frontend sets
 *      environ in such a constructor, and a skipped walk is silent: a null
 *      environ and zeroed tables far from the cause.
 *   3. exit(main's result) through crtl's `exit`, NOT the raw syscall, so
 *      atexit handlers run and buffered stdout is flushed (measured: a raw
 *      exit lost both).
 * NOT done, and not needed for parity with an x86-64 object linked by gcc:
 * the pxx thread block in fs. A pxx OBJECT keeps errno as a plain global on
 * both targets (c_errno_is_per_thread reports SHARED for an x86-64 object
 * under gcc too). The block's size depends on the compile, so a copy here
 * would go stale; if objects ever need it, the compiler should emit it.
 */
    .text
    .globl _start
    .type _start, @function
_start:
    xor  %ebp, %ebp              /* outermost frame */
    mov  (%esp), %esi            /* argc */
    lea  4(%esp), %edi           /* argv */
    lea  4(%edi,%esi,4), %ebx    /* envp = argv + argc + 1 */
    and  $-16, %esp
    sub  $12, %esp               /* the cursor below sits at esp+0; 16-aligned frames */
    push $__init_array_start     /* cursor; esp is 16-aligned here */
1:  mov  (%esp), %ecx
    cmp  $__init_array_end, %ecx
    jae  2f
    sub  $4, %esp                /* 3 args + pad: 16-aligned at the call */
    push %ebx
    push %edi
    push %esi
    call *(%ecx)
    add  $16, %esp
    addl $4, (%esp)
    jmp  1b
2:  add  $16, %esp               /* drop the cursor and its pad */
    sub  $4, %esp
    push %ebx
    push %edi
    push %esi
    call main
    add  $16, %esp
    sub  $12, %esp
    push %eax
    call exit                    /* crtl's: atexit handlers, stdio flush */
    mov  %eax, %ebx              /* not reached: exit(2) if it ever returns */
    mov  $1, %eax
    int  $0x80
    hlt
    .size _start, .-_start
    .section .note.GNU-stack,"",@progbits
