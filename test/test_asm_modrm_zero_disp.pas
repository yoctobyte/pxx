program AsmModRMZeroDisp;
{ A ModRM byte whose REG field is r8..r15 and whose memory operand has NO
  displacement.

  This is the one combination where an unmasked reg field is visible. asmcore's
  EmitModRMMem composed the byte as `(modBits shl 6) or (regField shl 3) or rm`
  with regField a full 0..15 register number, so bit 3 -- which belongs to
  REX.R, already emitted -- landed in the MOD field:

    mov r8, [r9+8]   modBits=1, so the stray bit sets a bit that was going to be
                     set anyway. Correct by accident, and this is why every
                     existing test passed.
    mov r8, [r9]     modBits=0. The byte now says mod=01, "a disp8 follows",
                     and none does. The stream desynchronises and the next
                     instruction's REX prefix is eaten as the displacement.

  Measured against the pinned compiler on 2026-09-02: this predates the AT&T
  inline-asm reader that found it, and it is reachable from Pascal alone.

  A BEHAVIOURAL assertion, not a byte one. A desynchronised instruction stream
  does not merely differ from the intended bytes -- it executes something else
  entirely -- so what the value check below can observe is exactly the defect
  class. The values are chosen so no single wrong instruction produces them:
  each load must reach a different one of three distinct constants.

  feature-c-gnu-inline-asm-with-a-non-empty-template }

var
  a, b, c: Int64;
  ra, rb, rc: Int64;

begin
  a := 111; b := 222; c := 333;
  ra := 0; rb := 0; rc := 0;
  asm
    lea r9, a
    mov r8, [r9]        { high reg dest, high reg base, ZERO displacement }
    mov ra, r8

    lea r10, b
    mov r15, [r10]      { the top of the high half, as the reg field }
    mov rb, r15

    lea r11, c
    mov rax, [r11]      { low reg dest, high reg base -- the control: this
                          combination was always encoded correctly }
    mov rc, rax
  end ['rax', 'r8', 'r9', 'r10', 'r11', 'r15'];
  writeln(ra);   { 111 }
  writeln(rb);   { 222 }
  writeln(rc);   { 333 }
end.
