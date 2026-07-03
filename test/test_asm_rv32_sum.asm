; riscv32 .asm frontend (feature-asm-source-frontend rv32 leg):
; sum 1..10 = 55 via labels + branches; exit code = a0 (fall-through epilogue).
; The pre-start block exits 7 — only a working `global start` entry override
; reaches the loop, so exit 55 proves both codegen and the override.
    addi a0, zero, 7
    addi a7, zero, 93
    ecall
start:
    addi a0, zero, 0
    addi t0, zero, 10
loop:
    beq t0, zero, done
    add a0, a0, t0
    addi t0, t0, -1
    j loop
done:
global start
