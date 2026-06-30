program AsmGlobal;
{ Inline asm global-var operands (feature-inline-asm-depth TODO #2):
  `mov reg,global` / `mov global,reg` / `add global,reg` / `cmp` / `lea
  reg,global` all resolve to an absolute [disp32] via a deferred
  EmitGlobRef fixup (AsmParseOperand can't call it at parse time -- AsmBytes
  offsets aren't final code positions; the IR_ASM codegen-replay loop in
  ir_codegen.inc does it once CodeLen is correct). Exercises multiple asm
  blocks across different procedures referencing different globals, to
  prove the per-block fixup matching is correctly scoped, not a one-shot
  fluke. }
var
  a, b, c: longint;
  addr: int64;
  pa: ^longint;

procedure SetA;
begin
  asm
    mov eax, 11
    mov a, eax
  end;
end;

procedure SetB;
begin
  asm
    mov eax, a
    add eax, 1
    mov b, eax
  end;
end;

begin
  a := 0; b := 0; c := 0;
  SetA;
  SetB;
  asm
    mov eax, a
    add eax, b
    mov c, eax
  end;
  writeln(a, ' ', b, ' ', c);   { expect 11 12 23 }

  asm
    lea rbx, a
    mov addr, rbx
  end;
  pa := @a;
  writeln(addr = int64(pa));    { expect TRUE: lea computed a's real address }
end.
