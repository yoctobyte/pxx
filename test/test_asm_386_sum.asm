; i386 .asm frontend: sum 1..10 = 55, exit code = ebx (fall-through epilogue).
; Pre-start block exits 7 — only a working `global start` override reaches the loop.
    mov ebx, 7
    mov eax, 1
    int 128
start:
    mov ebx, 0
    mov ecx, 10
loop_top:
    cmp ecx, 0
    je done
    add ebx, ecx
    sub ecx, 1
    jmp loop_top
done:
global start
