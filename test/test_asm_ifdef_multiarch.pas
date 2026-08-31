program AsmIfdefMultiarch;
{ Cross-target inline asm selection: one source, per-target asm blocks behind
  the compiler-provided CPU defines (CPUX86_64/CPURISCV32/CPUAARCH64/CPUXTENSA — see
  PasApplyTargetDefines, lexer.inc). Inline asm always follows --target; the
  inactive branches are conditionally skipped and never parsed. }
function AddViaAsm(a, b: Integer): Integer;
var r: Integer;
begin
  r := 0;
{$ifdef CPUX86_64}
  asm
    mov eax, a
    add eax, b
    mov r, eax
  end;
{$endif}
{$ifdef CPURISCV32}
  asm
    lw t0, a
    lw t1, b
    add t2, t0, t1
    sw t2, r
  end;
{$endif}
{$ifdef CPUAARCH64}
  asm
    ldr w9, a
    ldr w10, b
    add w9, w9, w10
    str w9, r
  end;
{$endif}
{$ifdef CPUXTENSA}
  { a8 is NOT usable here: EmitAsmXtensa holds the address of a variable operand
    in it, and says so rather than miscompiling. a10/a11 are free under both
    ABIs -- verified Call0 AND windowed, since this is the one construct where
    the two could plausibly differ. }
  asm
    l32i a10, a
    l32i a11, b
    add a10, a10, a11
    s32i a10, r
  end;
{$endif}
  Result := r;
end;
begin
  writeln(AddViaAsm(19, 23));
end.
