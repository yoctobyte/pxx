; .asm frontend: labels + forward/backward branches + ALU.
; Sums 1..9 = 45 in a loop, exits with the sum (via the fall-through epilogue).
  jmp start
  mov rdi, 99      ; forward jump skips this
start:
  mov rdi, 0       ; accumulator
  mov rcx, 9       ; counter
loop:
  add rdi, rcx
  dec rcx
  cmp rcx, 0
  jg loop          ; backward branch while rcx > 0
