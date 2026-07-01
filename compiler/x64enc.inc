{ x64enc.inc — typed instruction encoders for x86-64 codegen }

const
  rRAX = 0; rRCX = 1; rRDX = 2; rRBX = 3;
  rRSP = 4; rRBP = 5; rRSI = 6; rRDI = 7;
  rR8  = 8; rR9  = 9; rR10 = 10; rR11 = 11;
  rR12 = 12; rR13 = 13; rR14 = 14; rR15 = 15;

var
  EncToAsmBuffer: Boolean = False;

{ Defined in asmenc.inc (included later); forward-declared here so
  EncModRMAbs can defer a global-var operand fixup to IR_ASM codegen-replay
  time instead of erroring. }
procedure AsmRecordGlobalFixup(bssOff: Integer); forward;

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

{ Prefix/REX for a MEMORY-operand instruction. Differs from EncPrefixAndREX in
  the byte-size case: the "force REX for spl/bpl/sil/dil" rule applies only to an
  8-bit *register operand* (regField when regIsByteOperand), never to the memory
  base register — a base in 4..7 (rsp/rbp/rsi/rdi) must NOT pull in a REX. }
procedure EncPrefixAndREXMem(size, regField, baseReg: Integer; regIsByteOperand: Boolean);
var w, r, b, rex: Integer;
begin
  if size = 2 then EncB($66);
  w := 0; if size = 8 then w := 1;
  r := 0; if regField >= 8 then r := 1;
  b := 0; if baseReg >= 8 then b := 1;
  if (w <> 0) or (r <> 0) or (b <> 0) or
     (regIsByteOperand and (regField >= 4) and (regField <= 7)) then
  begin
    rex := $40 or (w shl 3) or (r shl 2) or b;
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
    AsmRecordGlobalFixup(bssOff)
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
    { mov r/m64, imm32 (0xC7, sign-extended) when the value round-trips through
      a 32-bit sign extension -- same resulting register value, 3 bytes
      shorter than the movabs (0xB8+r, full imm64) form below. }
    if Int64(Integer(immVal)) = immVal then
    begin
      EncPrefixAndREX(8, 0, destReg, False);
      EncB($C7);
      EncModRMReg(0, destReg);
      EncI32(immVal);
    end
    else
    begin
      EncPrefixAndREX(8, 0, destReg, False);
      EncB($B8 + (destReg and 7));
      EncI64(immVal);
    end;
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
  EncPrefixAndREXMem(size, 0, baseReg, False);
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

{ --- Call / jump indirect (FF /2 = call, /4 = jmp; default 64-bit oper) --- }
procedure x64_call_reg(reg: Integer);
begin
  if reg >= 8 then EncB($41);   { REX.B; no REX.W (call r/m64 is 64-bit by default) }
  EncB($FF);
  EncModRMReg(2, reg);
end;

procedure x64_jmp_reg(reg: Integer);
begin
  if reg >= 8 then EncB($41);
  EncB($FF);
  EncModRMReg(4, reg);
end;

{ --- Unary F6/F7 group on a register.
  ext: 2=not 3=neg 4=mul 5=imul 6=div 7=idiv. --- }
procedure x64_unary_reg(size, ext, reg: Integer);
begin
  EncPrefixAndREX(size, ext, reg, False);
  if size = 1 then EncB($F6) else EncB($F7);
  EncModRMReg(ext, reg);
end;

{ --- imul reg, reg (two-operand signed multiply, 0F AF /r) --- }
procedure x64_imul_reg_reg(size, destReg, srcReg: Integer);
begin
  EncPrefixAndREX(size, destReg, srcReg, False);
  EncB($0F); EncB($AF);
  EncModRMReg(destReg, srcReg);
end;

{ --- Shifts: ext 4=shl/sal 5=shr 7=sar. reg by imm (or by 1) --- }
procedure x64_shift_reg_imm(size, ext, reg, imm: Integer);
begin
  EncPrefixAndREX(size, ext, reg, False);
  if imm = 1 then
  begin
    if size = 1 then EncB($D0) else EncB($D1);
    EncModRMReg(ext, reg);
  end
  else
  begin
    if size = 1 then EncB($C0) else EncB($C1);
    EncModRMReg(ext, reg);
    EncB(imm and $FF);
  end;
end;

{ --- Shifts by CL (D2/D3) --- }
procedure x64_shift_reg_cl(size, ext, reg: Integer);
begin
  EncPrefixAndREX(size, ext, reg, False);
  if size = 1 then EncB($D2) else EncB($D3);
  EncModRMReg(ext, reg);
end;

{ --- movzx / movsx reg, reg. srcSize 1 or 2; destSize sets 66/REX.W.
  signed=False → movzx (0F B6/B7); True → movsx (0F BE/BF). --- }
procedure x64_movx_reg_reg(destSize, srcSize, destReg, srcReg: Integer; signed: Boolean);
var force: Boolean;
begin
  { 32-bit signed source is MOVSXD (one-byte 0x63), not the 0F-prefixed form;
    32-bit unsigned source is just a plain `mov r32,r32` (zero-extends) — caller
    should use mov for that, so reject it here. }
  if srcSize = 4 then
  begin
    if not signed then Error('x64_movx: use mov for 32-bit zero-extend');
    EncPrefixAndREX(destSize, destReg, srcReg, False);
    EncB($63);
    EncModRMReg(destReg, srcReg);
    Exit;
  end;
  { an 8-bit src in 4..7 (spl/bpl/sil/dil) needs a REX to escape ah/ch/dh/bh }
  force := (srcSize = 1) and (srcReg >= 4) and (srcReg <= 7);
  EncPrefixAndREX(destSize, destReg, srcReg, force);
  EncB($0F);
  if signed then begin if srcSize = 1 then EncB($BE) else EncB($BF); end
  else begin if srcSize = 1 then EncB($B6) else EncB($B7); end;
  EncModRMReg(destReg, srcReg);
end;

{ --- movzx / movsx reg, [mem]. srcSize from explicit byte/word keyword. --- }
procedure x64_movx_reg_mem(destSize, srcSize, destReg, baseReg, disp: Integer;
  signed: Boolean; force32: Boolean);
begin
  EncPrefixAndREX(destSize, destReg, baseReg, False);
  EncB($0F);
  if signed then begin if srcSize = 1 then EncB($BE) else EncB($BF); end
  else begin if srcSize = 1 then EncB($B6) else EncB($B7); end;
  EncModRMMem(destReg, baseReg, disp, force32);
end;

{ --- setcc reg8 (0F 90+cc, /0) --- }
procedure x64_setcc_reg(cc, reg: Integer);
begin
  EncPrefixAndREX(1, 0, reg, False);   { size=1 forces REX for spl/bpl/sil/dil }
  EncB($0F); EncB($90 + (cc and 15));
  EncModRMReg(0, reg);
end;

{ --- String ops (operate on [rdi]/[rsi]); F3 = rep prefix --- }
procedure x64_movsb; begin EncB($A4); end;
procedure x64_stosb; begin EncB($AA); end;
procedure x64_rep_movsb; begin EncB($F3); EncB($A4); end;
procedure x64_rep_stosb; begin EncB($F3); EncB($AA); end;

{ --- ALU reg, [mem] and [mem], reg.
  opRM = the r,m opcode (03/0B/23/2B/33/3B; cmp=3B). opMR = the m,r opcode
  (01/09/21/29/31/39; cmp=39). --- }
procedure x64_alu_reg_mem(opRM, size, destReg, baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREXMem(size, destReg, baseReg, size = 1);
  EncB(opRM and $FF);
  EncModRMMem(destReg, baseReg, disp, force32);
end;

procedure x64_alu_mem_reg(opMR, size, baseReg, disp, srcReg: Integer; force32: Boolean);
begin
  EncPrefixAndREXMem(size, srcReg, baseReg, size = 1);
  EncB(opMR and $FF);
  EncModRMMem(srcReg, baseReg, disp, force32);
end;

{ --- test reg, [mem] (85 /r) --- }
procedure x64_test_reg_mem(size, reg, baseReg, disp: Integer; force32: Boolean);
begin
  EncPrefixAndREXMem(size, reg, baseReg, size = 1);
  if size = 1 then EncB($84) else EncB($85);
  EncModRMMem(reg, baseReg, disp, force32);
end;

{ --- SSE scalar (xmm) ops: [prefix] [REX] 0F opcode ModRM.
  prefix: 0 = none, else the mandatory byte (F2 for *sd, 66 for comisd...).
  rexW forces REX.W (cvtsi2sd from r64 / cvttsd2si to r64). regField/rmReg are
  the encoded register numbers (xmm or GP); R/B come from >=8. --- }
procedure x64_sse_rr(prefix, opcode, regField, rmReg: Integer; rexW: Boolean);
begin
  if prefix <> 0 then EncB(prefix);
  if rexW then EncPrefixAndREX(8, regField, rmReg, False)
  else EncPrefixAndREX(4, regField, rmReg, False);
  EncB($0F); EncB(opcode and $FF);
  EncModRMReg(regField, rmReg);
end;

procedure x64_sse_rm(prefix, opcode, regField, baseReg, disp: Integer;
  rexW: Boolean; force32: Boolean);
begin
  if prefix <> 0 then EncB(prefix);
  if rexW then EncPrefixAndREXMem(8, regField, baseReg, False)
  else EncPrefixAndREXMem(4, regField, baseReg, False);
  EncB($0F); EncB(opcode and $FF);
  EncModRMMem(regField, baseReg, disp, force32);
end;

{ --- test [mem], imm (F6/F7 /0) --- }
procedure x64_test_mem_imm(size, baseReg, disp: Integer; imm: Int64; force32: Boolean);
begin
  EncPrefixAndREXMem(size, 0, baseReg, False);
  if size = 1 then
  begin
    EncB($F6); EncModRMMem(0, baseReg, disp, force32); EncB(Integer(imm) and $FF);
  end
  else
  begin
    EncB($F7); EncModRMMem(0, baseReg, disp, force32);
    if size = 2 then EncI16(imm) else EncI32(imm);
  end;
end;
