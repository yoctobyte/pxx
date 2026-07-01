; feature-asm-source-frontend task #5: -c/--emit-obj ET_REL object output.
; Exports a callable function (asm_obj_add) and an entry point
; (asm_obj_start) that calls libc through real R_X86_64_PLT32 relocations --
; proven by actually linking the resulting .o with the system ld/gcc (make
; test's link+run checks, gcc-guarded) rather than just inspecting bytes.

section .text

extern puts
extern fflush

global asm_obj_add
global asm_obj_start

asm_obj_add:
    mov eax, edi
    add eax, esi
    ret

asm_obj_start:
    lea rdi, [rel msg]
    call puts
    xor edi, edi
    call fflush        ; fflush(NULL) -- see test_asm_extern.asm for why
    xor edi, edi
    mov eax, 60
    syscall

section .data
msg: db "asm object file test", 0
