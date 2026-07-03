; arm32 .asm frontend: sum 1..10 = 55, exit code = r0 (fall-through epilogue).
; Pre-start block exits 7 — only a working `global start` override reaches the loop.
    mov r0, 7
    mov r7, 1
    svc 0
start:
    mov r0, 0
    mov r1, 10
loop:
    cmp r1, 0
    beq done
    add r0, r0, r1
    sub r1, r1, 1
    b loop
done:
global start
