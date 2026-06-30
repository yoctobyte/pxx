program AsmBranchLoop;
{ Inline asm labels + jcc branches (feature-asm-structured-ir-library TODO #1,
  "highest value — unlocks loops and conditionals in asm"). Sums 1..9 = 45
  purely inside one asm block, then exits with that value — the inline-asm
  analogue of test/test_asm_loop.asm. }
begin
  asm
    mov rdi, 0
    mov rcx, 9
  sumloop:
    add rdi, rcx
    dec rcx
    cmp rcx, 0
    jg sumloop
    mov eax, 60
    syscall
  end;
end.
