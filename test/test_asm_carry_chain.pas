program AsmCarryChain;
{ adc / sbb / cmc in the x86-64 inline-asm encoder (asmenc.inc).

  These three were absent from AsmDispatch until this test landed: the ALU
  table there runs add=0 or=1 adc=2 sbb=3 and=4 sub=5 xor=6 cmp=7 and only
  rows 2 and 3 were missing, while asmtext.inc — the other x86-64 encoder —
  had carried adc and sbb all along. Needed because a carry chain is what
  bignum code is made of; busybox's networking/tls_sp_c32.c is four of them.

  EVERY row here is a positive control: each answer is one a WRONG encoding
  could not produce.

    adc  — if adc assembled as add, the carry out of the low limb is lost and
           hi stays 0. Only a real adc makes hi 1.
    sbb  — if sbb assembled as sub, the borrow is lost and hi stays 1.
           Only a real sbb makes hi 0.
    cmc  — CF is deliberately set (0 - 1 borrows) before cmc clears it, so a
           cmc that did nothing at all leaves 1 in the accumulator. Only a
           cmc that actually flips CF makes it 0.

  A value check is the right assertion class here: these are flag-carrying
  data ops, so a wrong encoding lands in the result rather than leaking or
  hanging. What it cannot see is a mis-encoded ModRM that happens to compute
  the same value, which is why each row uses a different register pair. }

procedure Chain;
var
  lo, hi: Int64;
begin
  { --- adc: $FFFFFFFFFFFFFFFF + 1 as a 128-bit add --- }
  lo := -1;            { all ones }
  hi := 0;
  asm
    mov rax, lo
    mov rdx, hi
    mov rcx, 1
    mov rbx, 0
    add rax, rcx
    adc rdx, rbx
    mov lo, rax
    mov hi, rdx
  end ['rax', 'rbx', 'rcx', 'rdx'];
  writeln(lo);         { 0 }
  writeln(hi);         { 1  — 0 if adc were add }

  { --- sbb: (1:0) - 1 as a 128-bit subtract --- }
  lo := 0;
  hi := 1;
  asm
    mov r8, lo
    mov r9, hi
    mov r10, 1
    mov r11, 0
    sub r8, r10
    sbb r9, r11
    mov lo, r8
    mov hi, r9
  end ['r8', 'r9', 'r10', 'r11'];
  writeln(lo);         { -1 — all ones }
  writeln(hi);         { 0  — 1 if sbb were sub }

  { --- cmc: set CF, flip it, then read it back through adc --- }
  hi := 0;
  asm
    mov rsi, 0
    sub rsi, 1         { CF := 1 }
    cmc                { CF := 0 }
    mov rdi, 0
    adc rdi, 0         { rdi := 0 + 0 + CF }
    mov hi, rdi
  end ['rsi', 'rdi'];
  writeln(hi);         { 0 — 1 if cmc did nothing }
end;

begin
  Chain;
end.
