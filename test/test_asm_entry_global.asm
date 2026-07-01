; feature-asm-source-frontend: `global <label>` overrides the ELF entry point
; (default: start of Code[]). Two SYS_exit sites with different codes, not
; connected by any jump/fallthrough -- only a working entry-point override
; reaches the second one.

section .text

    mov eax, 60
    mov edi, 1
    syscall

global real_start

real_start:
    mov eax, 60
    mov edi, 42
    syscall
