; MVP .asm frontend smoke test (feature-asm-mvp-frontend).
; Straight-line mov/add encoded through lib/asmcore; the frontend appends an
; exit epilogue (SYS_exit with rdi). Exit code = 21 + 21 = 42.
mov rdi, 21
add rdi, rdi
