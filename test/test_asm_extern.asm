; feature-asm-source-frontend: extern (dynamic-link call) + global (entry
; point override) directives. Calls libc printf via the same GOT-indirect
; dynamic-call machinery a Pascal `external 'libc.so.6'` declaration uses.

section .text

extern printf
extern fflush

global _start

_start:
    lea rdi, [rel msg]
    xor eax, eax
    call printf
    xor edi, edi
    call fflush        ; fflush(NULL) -- we exit via a raw syscall below, not
                        ; libc's exit(), so nothing else flushes printf's
                        ; buffered stdout for us.
    xor edi, edi
    mov eax, 60
    syscall

section .data
msg: db "Hello from extern printf!", 10, 0
