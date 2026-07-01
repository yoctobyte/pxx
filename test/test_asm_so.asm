; feature-asm-source-frontend task #6: --shared ET_DYN shared-library output.
; Exports a pure function (so_add) and a function that calls libc through a
; real R_X86_64_PLT32-free, position-independent rip-relative GOT access
; (so_greet) -- proven by actually dlopen()/dlsym()-ing the resulting .so
; (make test's link+run checks, gcc-guarded) rather than just inspecting
; bytes. No PIC codegen retrofit was needed: this frontend's own addressing
; (rip-relative labels/branches, register-relative [base+disp]) is already
; position-independent by construction; only the extern-call encoding needed
; a rip-relative GOT variant for this mode.

section .text

extern puts
extern fflush

global so_add
global so_greet

so_add:
    mov eax, edi
    add eax, esi
    ret

so_greet:
    lea rdi, [rel msg]
    call puts
    xor edi, edi
    call fflush        ; fflush(NULL) -- see test_asm_extern.asm for why
    ret

section .data
msg: db "hello from shared lib", 0
