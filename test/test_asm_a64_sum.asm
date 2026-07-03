; aarch64 .asm frontend: sum 1..10 = 55, exit code = x0 (fall-through epilogue).
; Pre-start block exits 7 — only a working `global start` override reaches the loop.
    mov x0, 7
    mov x8, 93
    svc 0
start:
    mov x0, 0
    mov x9, 10
loop:
    cbz x9, done
    add x0, x0, x9
    sub x9, x9, 1
    b loop
done:
global start
