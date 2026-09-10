# The process entry for a freestanding pxx link: no crt1.o, no libc, no loader.
#
# pxx emits objects with no _start -- for an EXECUTABLE its own ELF writer
# supplies the entry, and --emit-obj deliberately does not. So a multi-object
# `ld` link has to supply one, and this is it.
#
# IT IS NOT A 6-INSTRUCTION STUB, AND THAT IS THE FINDING. Reading argc/argv off
# the stack and calling main is enough for a program that only writes to stdout
# -- busybox's echo, ls, wc, grep and pwd all ran that way -- and it is NOT
# enough in general. Under that stub busybox's ash segfaulted in hashvar on a
# NULL varinit pointer, `date` segfaulted, and `uname -a` printed "Linux" eight
# times, while the SAME 86 objects linked with gcc were byte-identical to the
# gcc oracle over 132 cases. Three symptoms, three subsystems, ONE cause, and
# the cause is not in any of them: an entry owes the program four things beyond
# argc/argv, and glibc's crt1.o was quietly providing all four.
#
#   1. THE CONTROL BLOCK IN %gs. crtl keeps per-thread state there. Without the
#      arch_prctl below it reads whatever %gs happened to hold.
#   2. .init_array. THIS is what the three symptoms above were: the link has 84
#      constructors in it and glibc's startup runs them. A constructor that does
#      not run leaves its subsystem's tables zeroed, which is why the failures
#      look like data corruption far from any cause.
#   3. environ. argv + argc + 1, which nothing else is in a position to compute.
#   4. .fini_array, via exit.
#
# The sequence for 1 is not invented: it is what pxx's own ELF writer emits at
# the entry of an executable, read off a pxx-built binary with gdb `starti` and
# transcribed -- getrlimit(RLIMIT_STACK), gettid, build {self, tid, stack_low,
# stack_top}, arch_prctl(ARCH_SET_GS).
#
# The right home for all of this is the compiler, not a checked-in .s: see
# feature-a-pxx-cannot-link-its-own-objects. An `--emit-obj --entry` that wrote
# these bytes into an object would retire this file and keep the sequence in ONE
# place -- a hand copy of a codegen detail goes stale silently, and the symptom
# is a segfault in somebody else's library.
        .text
        .globl  _start
_start:
        xorl    %ebp, %ebp              /* ABI: mark the outermost frame */
        movq    %rsp, %r8               /* the stack the kernel handed us */
        andq    $-16, %rsp              /* ABI: 16-byte aligned at every call */

        /* ---- 1. the control block in %gs ---------------------------------- */
        leaq    pxx_tcb(%rip), %r9
        leaq    0x1080(%r9), %rsi       /* scratch for the rlimit struct */
        movl    $3, %edi                /* RLIMIT_STACK */
        movl    $97, %eax               /* getrlimit */
        syscall
        movq    0x1080(%r9), %rcx       /* rlim_cur */
        movq    $0x4000000, %r10        /* clamp at 64 MB, as pxx does */
        cmpq    %r10, %rcx
        jbe     1f
        movq    %r10, %rcx
1:      movq    %r8, %r10
        subq    %rcx, %r10              /* lowest stack address */
        /* rcx is consumed BEFORE the next syscall on purpose: syscall clobbers
           rcx and r11, so computing the stack base after gettid would use a
           return address as a stack size. */
        movl    $186, %eax              /* gettid */
        syscall

        movq    %r9,  0(%r9)            /* self */
        movq    %rax, 8(%r9)            /* tid */
        movq    %r10, 16(%r9)           /* stack low */
        movq    %r8,  24(%r9)           /* stack top */

        movq    %r9, %rsi
        movl    $0x1001, %edi           /* ARCH_SET_GS */
        movl    $158, %eax              /* arch_prctl */
        syscall

        /* ---- argc, argv, envp, kept in callee-saved registers ------------- */
        movq    0(%r8), %r13            /* argc */
        leaq    8(%r8), %r14            /* argv */
        leaq    8(%r14,%r13,8), %r15    /* envp = argv + argc + 1 */

        /* ---- 3. environ --------------------------------------------------- */
        movq    %r15, environ(%rip)

        /* ---- 2. the constructors ------------------------------------------ */
        /* __init_array_start/_end come from ld's own default linker script, so
           this needs no -T and no custom script. A link whose .init_array is
           empty makes the two symbols equal and the loop runs zero times --
           which is why this is safe to carry unconditionally. Each entry gets
           (argc, argv, envp): glibc passes them, and a constructor compiled
           expecting them reads registers rather than garbage. */
        leaq    __init_array_start(%rip), %rbx
        leaq    __init_array_end(%rip), %r12
2:      cmpq    %r12, %rbx
        jae     3f
        movq    %r13, %rdi
        movq    %r14, %rsi
        movq    %r15, %rdx
        call    *(%rbx)
        addq    $8, %rbx
        jmp     2b

        /* ---- main -------------------------------------------------------- */
3:      movq    %r13, %rdi
        movq    %r14, %rsi
        movq    %r15, %rdx
        call    main
        movl    %eax, %edi
        call    exit                    /* 4. exit runs .fini_array */
        hlt                             /* exit does not return */

        .bss
        .align  16
pxx_tcb:
        .space  0x2000                  /* 0x1080 of control block + scratch */
