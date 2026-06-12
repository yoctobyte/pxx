{ x64enc.inc — typed instruction encoders for x86-64 codegen }

const
  rRAX = 0; rRCX = 1; rRDX = 2; rRBX = 3;
  rRSP = 4; rRBP = 5; rRSI = 6; rRDI = 7;
  rR8  = 8; rR9  = 9; rR10 = 10; rR11 = 11;
  rR12 = 12; rR13 = 13; rR14 = 14; rR15 = 15;

var
  EncToAsmBuffer: Boolean = False;

procedure EncB(b: Byte);
begin
  if EncToAsmBuffer then AsmB(b) else EmitB(b);
end;

procedure EncI16(v: Int64);
begin
  if EncToAsmBuffer then
    AsmI16(v)
  else
  begin
    EmitB(Byte(v and $FF));
    EmitB(Byte((v shr 8) and $FF));
  end;
end;

procedure EncI32(v: Int64);
begin
  if EncToAsmBuffer then AsmI32(v) else EmitI32(v);
end;

procedure EncI64(v: Int64);
begin
  if EncToAsmBuffer then AsmI64(v) else EmitI64(v);
end;

procedure EncPrefixAndREX(size: Integer; regField, rmReg: Integer; force: Boolean);
var
  w, r, x, b, rex: Integer;
begin
  if size = 2 then EncB($66);
  w := 0; if size = 8 then w := 1;
  r := 0; if regField >= 8 then r := 1;
  x := 0;
  b := 0; if (rmReg >= 8) then b := 1;
  
  if (w <> 0) or (r <> 0) or (b <> 0) or force or 
     ((size = 1) and (((regField >= 4) and (regField <= 7)) or ((rmReg >= 4) and (rmReg <= 7)))) then
  begin
    rex := $40 or (w shl 3) or (r shl 2) or (x shl 1) or b;
    EncB(rex);
  end;
end;

procedure EncModRMReg(regField, rmReg: Integer);
begin
  EncB($C0 or ((regField and 7) shl 3) or (rmReg and 7));
end;

procedure EncModRMMem(regField: Integer; baseReg: Integer; disp: Integer; force32: Boolean);
var
  modVal, rmVal, sibVal: Integer;
  needsSIB: Boolean;
begin
  needsSIB := (baseReg and 7) = 4; { RSP or R12 }
  
  if needsSIB then
  begin
    rmVal := 4;
    sibVal := $24; { scale=0, index=4 (none), base=4 }
  end
  else
  begin
    rmVal := baseReg and 7;
    sibVal := -1;
  end;

  if force32 then
  begin
    modVal := 2;
    EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
    if needsSIB then EncB(sibVal);
    EncI32(disp);
  end
  else
  begin
    { RBP (5) or R13 (13) cannot use mod=00 without displacement }
    if (disp = 0) and ((baseReg and 7) <> 5) then
    begin
      modVal := 0;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
    end
    else if (disp >= -128) and (disp <= 127) then
    begin
      modVal := 1;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
      EncB(disp and $FF);
    end
    else
    begin
      modVal := 2;
      EncB((modVal shl 6) or ((regField and 7) shl 3) or rmVal);
      if needsSIB then EncB(sibVal);
      EncI32(disp);
    end;
  end;
end;

procedure EncModRMAbs(regField: Integer; bssOff: Integer);
begin
  EncB(((regField and 7) shl 3) or 4); { mod=00, rm=4 }
  EncB($25); { SIB: scale=0, index=4 (none), base=5 }
  if EncToAsmBuffer then
    Error('asm: absolute BSS reference not supported in inline assembly')
  else
    EmitGlobRef(bssOff);
end;

{ --- 0-operand instructions --- }

procedure x64_nop;
begin
  EncB($90);
end;

procedure x64_ret;
begin
  EncB($C3);
end;

procedure x64_leave;
begin
  EncB($C9);
end;

procedure x64_syscall;
begin
  EncB($0F);
  EncB($05);
end;

{ --- Register/Register & Register/Immediate Mov --- }

procedure x64_mov_reg_reg(size, destReg, srcReg: Integer);
begin
  EncPrefixAndREX(size, srcReg, destReg, False);
  if size = 1 then EncB($88) else EncB($89);
  EncModRMReg(srcReg, destReg);
end;

procedure x64_mov_reg_imm(size, destReg: Integer; immVal: Int64);
begin
  if size = 8 then
  begin
    EncPrefixAndREX(8, 0, destReg, False);
    EncB($B8 + (destReg and 7));
    EncI64(immVal);
  end
  else
  begin
    EncPrefixAndREX(size, 0, destReg, False);
    if size = 1 then
    begin
      EncB($B0 + (destReg and 7));
      EncB(immVal and $FF);
    end
    else if size = 2 then
    begin
      EncB($B8 + (destReg and 7));
      EncI16(immVal);
    end
    else
    begin
      EncB($B8 + (destReg and 7));
      EncI32(immVal);
    end;
  end;
end;

{ --- Register/Memory Mov --- }

procedure x64_mov_reg_mem(size, destReg, baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(size, destReg, baseReg, False);
  if size = 1 then EncB($8A) else EncB($8B);
  EncModRMMem(destReg, baseReg, disp, force32);
end;

procedure x64_mov_mem_reg(size, baseReg, disp, srcReg: Integer; force32: Boolean);
begin
  EncPrefixAndREX(size, srcReg, baseReg, False);
  if size = 1 then EncB($88) else EncB($89);
  EncModRMMem(srcReg, baseReg, disp, force32);
end;

procedure x64_mov_mem_imm(size, baseReg, disp: Integer; immVal: Int64; force32: Boolean);
begin
  EncPrefixAndREX(size, 0, baseReg, False);
  if size = 1 then EncB($C6) else EncB($C7);
  EncModRMMem(0, baseReg, disp, force32);
  if size = 1 then EncB(immVal and $FF)
  else if size = 2 then EncI16(immVal)
  else EncI32(immVal);
end;

{ --- Absolute Global/BSS Mov --- }

procedure x64_mov_glob_reg(size, bssOff, srcReg: Integer);
begin
  EncPrefixAndREX(size, srcReg, 0, False);
  if size = 1 then EncB($88) else EncB($89);
  EncModRMAbs(srcReg, bssOff);
end;

procedure x64_mov_reg_glob(size, destReg, bssOff: Integer);
begin
  EncPrefixAndREX(size, destReg, 0, False);
  if size = 1 then EncB($8A) else EncB($8B);
  EncModRMAbs(destReg, bssOff);
end;

procedure x64_mov_glob_imm(size, bssOff: Integer; immVal: Int64);
begin
  EncPrefixAndREX(size, 0, 0, False);
  if size = 1 then EncB($C6) else EncB($C7);
  EncModRMAbs(0, bssOff);
  if size = 1 then EncB(immVal and $FF)
  else if size = 2 then EncI16(immVal)
  else EncI32(immVal);
end;

{ --- LEA --- }

procedure x64_lea_reg_mem(size, destReg, baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(size, destReg, baseReg, False);
  EncB($8D);
  EncModRMMem(destReg, baseReg, disp, force32);
end;

procedure x64_lea_reg_glob(size, destReg, bssOff: Integer);
begin
  EncPrefixAndREX(size, destReg, 0, False);
  EncB($8D);
  EncModRMAbs(destReg, bssOff);
end;

{ --- Push/Pop --- }

procedure x64_push_reg(reg: Integer);
begin
  EncPrefixAndREX(0, 0, reg, False);
  EncB($50 + (reg and 7));
end;

procedure x64_pop_reg(reg: Integer);
begin
  EncPrefixAndREX(0, 0, reg, False);
  EncB($58 + (reg and 7));
end;

procedure x64_push_imm(immVal: Integer);
begin
  EncB($68);
  EncI32(immVal);
end;

procedure x64_push_mem(baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(0, 6, baseReg, False);
  EncB($FF);
  EncModRMMem(6, baseReg, disp, force32);
end;

procedure x64_pop_mem(baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(0, 0, baseReg, False);
  EncB($8F);
  EncModRMMem(0, baseReg, disp, force32);
end;

{ --- ALU Helpers --- }

procedure EncALUImm(size, destReg: Integer; immVal: Int64; ext: Integer);
begin
  EncPrefixAndREX(size, ext, destReg, False);
  if size = 1 then
  begin
    EncB($80);
    EncModRMReg(ext, destReg);
    EncB(immVal and $FF);
  end
  else if (immVal >= -128) and (immVal <= 127) then
  begin
    EncB($83);
    EncModRMReg(ext, destReg);
    EncB(immVal and $FF);
  end
  else
  begin
    EncB($81);
    EncModRMReg(ext, destReg);
    if size = 2 then EncI16(immVal) else EncI32(immVal);
  end;
end;

procedure EncALURegReg(rmReg, regRm: Integer; size, destReg, srcReg: Integer);
begin
  EncPrefixAndREX(size, srcReg, destReg, False);
  if size = 1 then EncB(rmReg - 1) else EncB(rmReg);
  EncModRMReg(srcReg, destReg);
end;

procedure x64_add_reg_imm(size, destReg: Integer; immVal: Int64); begin EncALUImm(size, destReg, immVal, 0); end;
procedure x64_or_reg_imm(size, destReg: Integer; immVal: Int64);  begin EncALUImm(size, destReg, immVal, 1); end;
procedure x64_and_reg_imm(size, destReg: Integer; immVal: Int64); begin EncALUImm(size, destReg, immVal, 4); end;
procedure x64_sub_reg_imm(size, destReg: Integer; immVal: Int64); begin EncALUImm(size, destReg, immVal, 5); end;
procedure x64_xor_reg_imm(size, destReg: Integer; immVal: Int64); begin EncALUImm(size, destReg, immVal, 6); end;
procedure x64_cmp_reg_imm(size, destReg: Integer; immVal: Int64); begin EncALUImm(size, destReg, immVal, 7); end;

procedure x64_add_reg_reg(size, destReg, srcReg: Integer); begin EncALURegReg($01, $03, size, destReg, srcReg); end;
procedure x64_or_reg_reg(size, destReg, srcReg: Integer);  begin EncALURegReg($09, $0B, size, destReg, srcReg); end;
procedure x64_and_reg_reg(size, destReg, srcReg: Integer); begin EncALURegReg($21, $23, size, destReg, srcReg); end;
procedure x64_sub_reg_reg(size, destReg, srcReg: Integer); begin EncALURegReg($29, $2B, size, destReg, srcReg); end;
procedure x64_xor_reg_reg(size, destReg, srcReg: Integer); begin EncALURegReg($31, $33, size, destReg, srcReg); end;
procedure x64_cmp_reg_reg(size, destReg, srcReg: Integer); begin EncALURegReg($39, $3B, size, destReg, srcReg); end;

procedure x64_test_reg_reg(size, reg1, reg2: Integer);
begin
  EncPrefixAndREX(size, reg2, reg1, False);
  if size = 1 then EncB($84) else EncB($85);
  EncModRMReg(reg2, reg1);
end;

procedure x64_test_reg_imm(size, destReg: Integer; immVal: Int64);
begin
  EncPrefixAndREX(size, 0, destReg, False);
  if size = 1 then
  begin
    EncB($F6);
    EncModRMReg(0, destReg);
    EncB(immVal and $FF);
  end
  else
  begin
    EncB($F7);
    EncModRMReg(0, destReg);
    if size = 2 then EncI16(immVal) else EncI32(immVal);
  end;
end;

{ --- Inc/Dec --- }

procedure x64_inc_mem(size: Integer; baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(size, 0, baseReg, False);
  if size = 1 then EncB($FE) else EncB($FF);
  EncModRMMem(0, baseReg, disp, force32);
end;

procedure x64_dec_mem(size: Integer; baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREX(size, 1, baseReg, False);
  if size = 1 then EncB($FE) else EncB($FF);
  EncModRMMem(1, baseReg, disp, force32);
end;

procedure x64_inc_reg(size: Integer; reg: Integer);
begin
  EncPrefixAndREX(size, 0, reg, False);
  if size = 1 then EncB($FE) else EncB($FF);
  EncModRMReg(0, reg);
end;

procedure x64_dec_reg(size: Integer; reg: Integer);
begin
  EncPrefixAndREX(size, 1, reg, False);
  if size = 1 then EncB($FE) else EncB($FF);
  EncModRMReg(1, reg);
end;

{ --- Jump / Call --- }

procedure x64_jmp_rel32(disp: Integer);
begin
  EncB($E9);
  EncI32(disp);
end;

procedure x64_jmp_rel8(disp: Integer);
begin
  EncB($EB);
  EncB(disp and $FF);
end;

procedure x64_jcc_rel32(cc: Integer; disp: Integer);
begin
  EncB($0F);
  EncB($80 + (cc and 15));
  EncI32(disp);
end;

procedure x64_jcc_rel8(cc: Integer; disp: Integer);
begin
  EncB($70 + (cc and 15));
  EncB(disp and $FF);
end;

procedure x64_call_rel32(disp: Integer);
begin
  EncB($E8);
  EncI32(disp);
end;
