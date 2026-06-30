; .asm frontend: section .data + db + rip-relative lea (feature-asm-source-frontend).
; write(1, msg, 18) then exit(0). Proves layer-2 symbolic resolution covers
; data labels the same way it covers branch targets.
section .text
  mov rax, 1
  mov rdi, 1
  lea rsi, [rel msg]
  mov rdx, 18
  syscall
  mov rax, 60
  mov rdi, 0
  syscall

section .data
msg: db "Hello, asm world!", 10
