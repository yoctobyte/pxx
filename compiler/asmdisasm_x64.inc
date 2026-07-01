{ ===== x86-64 disassembler for `-S` / textual emit mode =====
  (feature-assembler-first-class-citizen head 2, feature-asm-textual-emit-mode)

  Head 2's stated design ("a pretty-printer over the same IR the binary
  encoder already walks") assumes a structured instruction-list IR feeding
  both a byte encoder and a text encoder. x64's codegen (ir_codegen.inc)
  never grew that: it hand-encodes bytes directly (EmitB/EmitI32 call sites
  outnumber the text-capable EmitAsmX64 path ~360:1) -- exactly why the
  umbrella ticket calls x64/i386 "the long pole" for this head. Retrofitting
  ir_codegen.inc onto a textual intermediate would touch the single most
  central, most self-host-critical file in the compiler for every source
  language, not just `.asm` -- high risk for a readability feature.

  This takes the other, additive route: DISASSEMBLE the bytes codegen
  already produced. Same observable result (a human-readable `.s`-style
  text file reflecting exactly what the compiler generated, for diffing
  across compiler changes) with zero risk to existing codegen -- this file
  only runs when `-S` is passed, and touches nothing else.

  Coverage is a bounded, real x86-64 subset -- not a general-purpose
  disassembler, just what this compiler's own x64 backend actually emits
  (verified against `objdump -d` on real compiled test programs): REX-
  prefixed ALU/mov/test/cmp forms (ModRM+SIB+disp8/32), push/pop, call/jmp/
  jcc (short + near), the FF/F6/F7/shift opcode groups, lea, ret/leave/nop/
  syscall, movzx/movsx/setcc/cmovcc/imul, and the SSE2 double-precision
  forms Pascal's Double type uses (movsd/addsd/mulsd/subsd/divsd/ucomisd/
  cvtsi2sd/cvttsd2si + the movq bridge to/from xmm). Anything unrecognized
  falls back to a `db 0xNN` line for that one byte and resumes decoding at
  the next byte -- always terminates, never errors, always shows something
  for every byte in Code[]. }

const
  DIS_MAX_LINE = 256;

function DisHexByte(b: Byte): AnsiString;
const hexd: AnsiString = '0123456789abcdef';
begin
  Result := '';
  AppendChar(Result, hexd[(b shr 4) + 1]);
  AppendChar(Result, hexd[(b and 15) + 1]);
end;

function DisHex32(v: LongWord): AnsiString;
var i: Integer; b: Byte;
begin
  Result := '0x';
  for i := 7 downto 0 do
  begin
    b := (v shr (i * 4)) and 15;
    if b < 10 then AppendChar(Result, Chr(Ord('0') + b))
    else AppendChar(Result, Chr(Ord('a') + b - 10));
  end;
end;

function DisHex64(lo, hi: LongWord): AnsiString;
var i: Integer; b: Byte; v: LongWord;
begin
  Result := '0x';
  for i := 7 downto 0 do
  begin
    if i >= 4 then begin v := hi; b := (v shr ((i - 4) * 4)) and 15; end
    else begin v := lo; b := (v shr (i * 4)) and 15; end;
    if b < 10 then AppendChar(Result, Chr(Ord('0') + b))
    else AppendChar(Result, Chr(Ord('a') + b - 10));
  end;
end;

function DisIntToStr(v: Int64): AnsiString;
var neg: Boolean; u: Int64; r: AnsiString;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0; u := v; if neg then u := -u;
  r := '';
  while u > 0 do begin r := Chr(Ord('0') + (u mod 10)) + r; u := u div 10; end;
  if neg then r := '-' + r;
  Result := r;
end;

{ 64-bit GP register name, 0..15 (already REX-extended), width 1/2/4/8 bytes.
  hasRex distinguishes the 8-bit spl/bpl/sil/dil encoding (REX present) from
  legacy ah/ch/dh/bh (no REX, regnum 4..7). }
function DisReg(regnum, width: Integer; hasRex: Boolean): AnsiString;
const
  RegNames8: array[0..15] of AnsiString = (
    'rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi',
    'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15');
  RegNames4: array[0..15] of AnsiString = (
    'eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi',
    'r8d', 'r9d', 'r10d', 'r11d', 'r12d', 'r13d', 'r14d', 'r15d');
  RegNames2: array[0..15] of AnsiString = (
    'ax', 'cx', 'dx', 'bx', 'sp', 'bp', 'si', 'di',
    'r8w', 'r9w', 'r10w', 'r11w', 'r12w', 'r13w', 'r14w', 'r15w');
  RegNames1NoRex: array[0..7] of AnsiString = (
    'al', 'cl', 'dl', 'bl', 'ah', 'ch', 'dh', 'bh');
  RegNames1Rex: array[0..15] of AnsiString = (
    'al', 'cl', 'dl', 'bl', 'spl', 'bpl', 'sil', 'dil',
    'r8b', 'r9b', 'r10b', 'r11b', 'r12b', 'r13b', 'r14b', 'r15b');
begin
  case width of
    8: if (regnum >= 0) and (regnum <= 15) then Result := RegNames8[regnum]
       else Result := '?reg' + DisIntToStr(regnum);
    4: if (regnum >= 0) and (regnum <= 15) then Result := RegNames4[regnum]
       else Result := '?reg' + DisIntToStr(regnum);
    2: if (regnum >= 0) and (regnum <= 15) then Result := RegNames2[regnum]
       else Result := '?reg' + DisIntToStr(regnum);
    1: if (not hasRex) and (regnum < 8) then
       begin
         if (regnum >= 0) and (regnum <= 7) then Result := RegNames1NoRex[regnum]
         else Result := '?reg' + DisIntToStr(regnum);
       end
       else
       begin
         if (regnum >= 0) and (regnum <= 15) then Result := RegNames1Rex[regnum]
         else Result := '?reg' + DisIntToStr(regnum);
       end;
  else
    Result := '?reg' + DisIntToStr(regnum);
  end;
end;

function DisXmm(regnum: Integer): AnsiString;
begin
  Result := 'xmm' + DisIntToStr(regnum);
end;

{ Decoded ModRM/SIB memory or register operand. }
type
  TDisModRM = record
    IsReg: Boolean;
    RegField: Integer;     { the /reg field, REX.R-extended }
    RmReg: Integer;        { valid when IsReg: the r/m-as-register, REX.B-extended }
    MemText: AnsiString;   { valid when not IsReg: formatted "[...]" operand }
    Consumed: Integer;     { bytes consumed by ModRM+SIB+disp, from the ModRM byte }
  end;

{ Parse ModRM (+ SIB + disp8/32) starting at Code[pos]. regW/rmW are operand
  widths for formatting (regW unused for the memory-text path itself).
  Reads the global Code[] directly rather than taking a `code: array of
  Byte` parameter -- passing the (multi-MB) Code[] array as a const open-
  array argument stack-copied it into the CALLER's frame instead of passing
  by reference, a real pxx codegen bug (SIGSEGV on a large self-compile, not
  just slow) found while building this; see
  bug-const-open-array-param-stack-copies-caller-frame.md. }
function DisParseModRM(pos, len: Integer;
  rexR, rexX, rexB: Boolean; var mrm: TDisModRM): Boolean;
var modf, regf, rmf, sibByte, scale, idx, base: Integer;
    disp: Int64; i: Integer; hasDisp: Boolean; s: AnsiString;
begin
  Result := False;
  if pos >= len then Exit;
  modf := (Code[pos] shr 6) and 3;
  regf := (Code[pos] shr 3) and 7;
  rmf := Code[pos] and 7;
  if rexR then regf := regf + 8;
  mrm.RegField := regf;
  i := pos + 1;

  if modf = 3 then
  begin
    mrm.IsReg := True;
    mrm.RmReg := rmf;
    if rexB then mrm.RmReg := mrm.RmReg + 8;
    mrm.Consumed := i - pos;
    Result := True;
    Exit;
  end;

  mrm.IsReg := False;
  s := '[';
  disp := 0; hasDisp := False;

  if rmf = 4 then
  begin
    { SIB byte follows }
    if i >= len then Exit;
    sibByte := Code[i]; Inc(i);
    scale := 1 shl ((sibByte shr 6) and 3);
    idx := (sibByte shr 3) and 7;
    base := sibByte and 7;
    if rexX then idx := idx + 8;
    if rexB then base := base + 8;
    if (idx = 4) then
    begin
      { no index (rsp can't be a SIB index) }
      if (base and 7) = 5 then
      begin
        if modf = 0 then
        begin
          if i + 4 > len then Exit;
          disp := Int64(LongInt(Code[i] or (Code[i+1] shl 8) or (Code[i+2] shl 16) or (Code[i+3] shl 24)));
          i := i + 4;
          s := s + DisHex32(LongWord(disp));
        end
        else
        begin
          s := s + DisReg(base, 8, True);
        end;
      end
      else
        s := s + DisReg(base, 8, True);
    end
    else
    begin
      s := s + DisReg(base, 8, True) + '+' + DisReg(idx, 8, True);
      if scale <> 1 then s := s + '*' + DisIntToStr(scale);
    end;
  end
  else if (modf = 0) and (rmf = 5) then
  begin
    { RIP-relative }
    if i + 4 > len then Exit;
    disp := Int64(LongInt(Code[i] or (Code[i+1] shl 8) or (Code[i+2] shl 16) or (Code[i+3] shl 24)));
    i := i + 4;
    s := s + 'rip+' + DisHex32(LongWord(disp));
    mrm.MemText := s + ']';
    mrm.Consumed := i - pos;
    Result := True;
    Exit;
  end
  else
  begin
    base := rmf;
    if rexB then base := base + 8;
    s := s + DisReg(base, 8, True);
  end;

  if modf = 1 then
  begin
    if i >= len then Exit;
    disp := Int64(ShortInt(Code[i])); Inc(i);
    hasDisp := True;
  end
  else if modf = 2 then
  begin
    if i + 4 > len then Exit;
    disp := Int64(LongInt(Code[i] or (Code[i+1] shl 8) or (Code[i+2] shl 16) or (Code[i+3] shl 24)));
    i := i + 4;
    hasDisp := True;
  end;

  if hasDisp and (disp <> 0) then
  begin
    if disp < 0 then s := s + '-' + DisIntToStr(-disp)
    else s := s + '+' + DisIntToStr(disp);
  end;

  mrm.MemText := s + ']';
  mrm.Consumed := i - pos;
  Result := True;
end;

function DisRmText(const mrm: TDisModRM; width: Integer; hasRex: Boolean): AnsiString;
begin
  if mrm.IsReg then Result := DisReg(mrm.RmReg, width, hasRex)
  else Result := mrm.MemText;
end;

function DisRead32(pos: Integer): LongWord;
begin
  Result := Code[pos] or (Code[pos+1] shl 8) or (Code[pos+2] shl 16) or (LongWord(Code[pos+3]) shl 24);
end;

function DisReadI32(pos: Integer): LongInt;
begin
  Result := LongInt(DisRead32(pos));
end;

function DisAluName(idx: Integer): AnsiString;
const
  AluNames: array[0..7] of AnsiString = (
    'add', 'or', 'adc', 'sbb', 'and', 'sub', 'xor', 'cmp');
begin
  if (idx >= 0) and (idx <= 7) then Result := AluNames[idx]
  else Result := '?alu';
end;

function DisShiftName(idx: Integer): AnsiString;
const
  ShiftNames: array[0..7] of AnsiString = (
    'rol', 'ror', 'rcl', 'rcr', 'shl', 'shr', 'sal', 'sar');
begin
  if (idx >= 0) and (idx <= 7) then Result := ShiftNames[idx]
  else Result := '?shift';
end;

function DisCcName(idx: Integer): AnsiString;
const
  CcNames: array[0..15] of AnsiString = (
    'o', 'no', 'b', 'ae', 'e', 'ne', 'be', 'a',
    's', 'ns', 'p', 'np', 'l', 'ge', 'le', 'g');
begin
  if (idx >= 0) and (idx <= 15) then Result := CcNames[idx]
  else Result := '?cc';
end;

{ Decode one instruction at Code[pos]. Returns bytes consumed (>=1) and the
  formatted text (mnemonic + operands, no trailing newline). procNameAt is
  used to resolve call/jmp/jcc targets to a proc name when the target is a
  known BodyAddr, else a `loc_<hex>` label. Falls back to a 1-byte `db`
  line (Result:=1, text describes the raw byte) for anything unrecognized. }
{ brTarget: -1 unless this instruction is a direct call/jmp/jcc, in which
  case it's the absolute Code[]-relative target position -- the caller
  resolves that to a proc name (if it matches a known BodyAddr) or a
  `loc_<hex>` fallback label; DisOne itself never embeds the target text. }
function DisOneReal(pos, len: Integer; var text: AnsiString; var brTarget: Integer): Integer;
var
  rexW, rexR, rexX, rexB, hasRex: Boolean;
  p, opc, opc2, regf, sz: Integer;
  mrm: TDisModRM;
  disp32: LongInt;
  imm8: ShortInt;
  imm32: LongInt;
  mnem, rmTxt, regTxt: AnsiString;
  legacyPfx: Integer;
begin
  p := pos;
  brTarget := -1;
  rexW := False; rexR := False; rexX := False; rexB := False; hasRex := False;
  legacyPfx := 0;

  { x86 prefix order is [legacy: 66/F2/F3] [REX] [opcode] -- REX is always
    the LAST prefix before the real opcode, so it must be checked *after*
    an optional legacy SSE prefix, not before (checking REX first silently
    misparsed every REX.W SSE2 form, e.g. `66 48 0F 6E` movq or `F2 48 0F 2A`
    cvtsi2sd -- the REX byte sat between the legacy prefix and 0F, which the
    original REX-first check never accounted for). }
  if (p < len) and ((Code[p] = $66) or (Code[p] = $F2) or (Code[p] = $F3)) then
  begin
    legacyPfx := Code[p];
    Inc(p);
  end;
  if (p < len) and (Code[p] >= $40) and (Code[p] <= $4F) then
  begin
    hasRex := True;
    rexW := (Code[p] and 8) <> 0;
    rexR := (Code[p] and 4) <> 0;
    rexX := (Code[p] and 2) <> 0;
    rexB := (Code[p] and 1) <> 0;
    Inc(p);
  end;

  if p >= len then begin text := '(truncated)'; Result := len - pos; if Result < 1 then Result := 1; Exit; end;

  if rexW then sz := 8 else sz := 4;
  opc := Code[p];

  { ---- 0F two-byte opcodes (SSE2 double-precision + integer) ---- }
  if opc = $0F then
  begin
    if p + 1 >= len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    opc2 := Code[p+1];

    if ((legacyPfx = $F2) or (legacyPfx = $F3)) and ((opc2 = $10) or (opc2 = $11)) then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if legacyPfx = $F2 then mnem := 'movsd' else mnem := 'movss';
      if mrm.IsReg then rmTxt := DisXmm(mrm.RmReg) else rmTxt := mrm.MemText;
      if opc2 = $10 then text := mnem + ' ' + DisXmm(mrm.RegField) + ', ' + rmTxt
      else text := mnem + ' ' + rmTxt + ', ' + DisXmm(mrm.RegField);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if ((legacyPfx = $F2) or (legacyPfx = $F3)) and ((opc2 = $58) or (opc2 = $59) or (opc2 = $5C) or (opc2 = $5E) or (opc2 = $51)) then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if legacyPfx = $F2 then
      begin
        case opc2 of
          $58: mnem := 'addsd'; $59: mnem := 'mulsd'; $5C: mnem := 'subsd';
          $5E: mnem := 'divsd'; $51: mnem := 'sqrtsd';
        end;
      end
      else
      begin
        case opc2 of
          $58: mnem := 'addss'; $59: mnem := 'mulss'; $5C: mnem := 'subss';
          $5E: mnem := 'divss'; $51: mnem := 'sqrtss';
        end;
      end;
      if mrm.IsReg then rmTxt := DisXmm(mrm.RmReg) else rmTxt := mrm.MemText;
      text := mnem + ' ' + DisXmm(mrm.RegField) + ', ' + rmTxt;
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if ((legacyPfx = $F2) or (legacyPfx = $F3)) and (opc2 = $2A) then   { [F2|F3] [REX.W] 0F 2A: cvtsi2sd/cvtsi2ss }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if legacyPfx = $F2 then mnem := 'cvtsi2sd' else mnem := 'cvtsi2ss';
      text := mnem + ' ' + DisXmm(mrm.RegField) + ', ' + DisRmText(mrm, sz, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if ((legacyPfx = $F2) or (legacyPfx = $F3)) and ((opc2 = $2C) or (opc2 = $2D)) then   { cvtt[sd|ss]2si / cvt[sd|ss]2si }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if legacyPfx = $F2 then begin if opc2 = $2C then mnem := 'cvttsd2si' else mnem := 'cvtsd2si'; end
      else begin if opc2 = $2C then mnem := 'cvttss2si' else mnem := 'cvtss2si'; end;
      if mrm.IsReg then rmTxt := DisXmm(mrm.RmReg) else rmTxt := mrm.MemText;
      text := mnem + ' ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + rmTxt;
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if ((legacyPfx = $F2) or (legacyPfx = $F3)) and (opc2 = $5A) then   { cvtsd2ss / cvtss2sd }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if legacyPfx = $F2 then mnem := 'cvtsd2ss' else mnem := 'cvtss2sd';
      if mrm.IsReg then rmTxt := DisXmm(mrm.RmReg) else rmTxt := mrm.MemText;
      text := mnem + ' ' + DisXmm(mrm.RegField) + ', ' + rmTxt;
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (legacyPfx = $66) and (opc2 = $2E) then   { ucomisd }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if mrm.IsReg then rmTxt := DisXmm(mrm.RmReg) else rmTxt := mrm.MemText;
      text := 'ucomisd ' + DisXmm(mrm.RegField) + ', ' + rmTxt;
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (legacyPfx = $66) and ((opc2 = $6E) or (opc2 = $7E)) then   { movq gpr<->xmm }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if opc2 = $6E then
        text := 'movq ' + DisXmm(mrm.RegField) + ', ' + DisRmText(mrm, sz, hasRex)
      else
        text := 'movq ' + DisRmText(mrm, sz, hasRex) + ', ' + DisXmm(mrm.RegField);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;

    if opc2 = $05 then begin text := 'syscall'; Result := (p + 2) - pos; Exit; end;
    if (opc2 >= $80) and (opc2 <= $8F) then
    begin
      if p + 6 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      disp32 := DisReadI32(p + 2);
      brTarget := p + 6 + disp32;
      text := 'j' + DisCcName(opc2 and 15);
      Result := (p + 6) - pos; Exit;
    end;
    if (opc2 >= $90) and (opc2 <= $9F) then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'set' + DisCcName(opc2 and 15) + ' ' + DisRmText(mrm, 1, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (opc2 >= $40) and (opc2 <= $4F) then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'cmov' + DisCcName(opc2 and 15) + ' ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if opc2 = $AF then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'imul ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (opc2 = $B0) or (opc2 = $B1) then   { cmpxchg Ev,Gv -- atomic CAS primitive }
    begin
      if opc2 = $B0 then sz := 1;
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'cmpxchg ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (opc2 = $C0) or (opc2 = $C1) then   { xadd Ev,Gv -- atomic fetch-and-add primitive }
    begin
      if opc2 = $C0 then sz := 1;
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'xadd ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if (opc2 = $B6) or (opc2 = $B7) or (opc2 = $BE) or (opc2 = $BF) then
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if opc2 = $B6 then begin mnem := 'movzx'; rmTxt := DisRmText(mrm, 1, hasRex); end
      else if opc2 = $B7 then begin mnem := 'movzx'; rmTxt := DisRmText(mrm, 2, hasRex); end
      else if opc2 = $BE then begin mnem := 'movsx'; rmTxt := DisRmText(mrm, 1, hasRex); end
      else begin mnem := 'movsx'; rmTxt := DisRmText(mrm, 2, hasRex); end;
      text := mnem + ' ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + rmTxt;
      Result := (p + 2 + mrm.Consumed) - pos; Exit;
    end;
    if opc2 = $BA then   { Group 8: BT/BTS/BTR/BTC r/m, imm8 -- e.g. `btc reg,63`
      flips a double's sign bit, this compiler's float-negate encoding }
    begin
      if not DisParseModRM(p + 2, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      p := p + 2 + mrm.Consumed;
      if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      case mrm.RegField and 7 of
        4: mnem := 'bt'; 5: mnem := 'bts'; 6: mnem := 'btr'; 7: mnem := 'btc';
      else
        begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      end;
      text := mnem + ' ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHexByte(Code[p]);
      Result := (p + 1) - pos; Exit;
    end;
    text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit;
  end;

  { ---- single-byte opcodes ---- }
  if (opc >= $50) and (opc <= $57) then
  begin
    regf := opc - $50; if rexB then regf := regf + 8;
    text := 'push ' + DisReg(regf, 8, True);
    Result := (p + 1) - pos; Exit;
  end;
  if (opc >= $58) and (opc <= $5F) then
  begin
    regf := opc - $58; if rexB then regf := regf + 8;
    text := 'pop ' + DisReg(regf, 8, True);
    Result := (p + 1) - pos; Exit;
  end;
  if opc = $C3 then begin text := 'ret'; Result := (p + 1) - pos; Exit; end;
  if opc = $C9 then begin text := 'leave'; Result := (p + 1) - pos; Exit; end;
  if opc = $90 then begin text := 'nop'; Result := (p + 1) - pos; Exit; end;
  if opc = $CC then begin text := 'int3'; Result := (p + 1) - pos; Exit; end;
  if opc = $CD then begin
    if p + 2 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'int ' + DisHexByte(Code[p+1]); Result := (p + 2) - pos; Exit;
  end;
  if opc = $99 then begin if rexW then text := 'cqo' else text := 'cdq'; Result := (p + 1) - pos; Exit; end;
  if opc = $98 then begin if rexW then text := 'cdqe' else text := 'cwde'; Result := (p + 1) - pos; Exit; end;

  { string ops (movs/stos/cmps/scas/lods), optionally rep/repe/repne-
    prefixed (0xF3/0xF2 legacy prefix) -- implicit rsi/rdi/rax/rcx operands,
    no ModRM. *SB forms are always byte-sized; the rest follow REX.W. }
  if (opc = $A4) or (opc = $A5) or (opc = $A6) or (opc = $A7) or
     (opc = $AA) or (opc = $AB) or (opc = $AC) or (opc = $AD) or
     (opc = $AE) or (opc = $AF) then
  begin
    case opc of
      $A4, $A5: mnem := 'movs'; $A6, $A7: mnem := 'cmps';
      $AA, $AB: mnem := 'stos'; $AC, $AD: mnem := 'lods';
      $AE, $AF: mnem := 'scas';
    end;
    if (opc and 1) = 0 then mnem := mnem + 'b'
    else if rexW then mnem := mnem + 'q'
    else mnem := mnem + 'd';
    if legacyPfx = $F3 then
    begin
      if (opc = $A6) or (opc = $A7) or (opc = $AE) or (opc = $AF) then text := 'repe ' + mnem
      else text := 'rep ' + mnem;
    end
    else if legacyPfx = $F2 then text := 'repne ' + mnem
    else text := mnem;
    Result := (p + 1) - pos; Exit;
  end;

  if opc = $E8 then
  begin
    if p + 5 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    disp32 := DisReadI32(p + 1);
    brTarget := p + 5 + disp32;
    text := 'call';
    Result := (p + 5) - pos; Exit;
  end;
  if opc = $E9 then
  begin
    if p + 5 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    disp32 := DisReadI32(p + 1);
    brTarget := p + 5 + disp32;
    text := 'jmp';
    Result := (p + 5) - pos; Exit;
  end;
  if opc = $EB then
  begin
    if p + 2 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    imm8 := ShortInt(Code[p+1]);
    brTarget := p + 2 + imm8;
    text := 'jmp';
    Result := (p + 2) - pos; Exit;
  end;
  if (opc >= $70) and (opc <= $7F) then
  begin
    if p + 2 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    imm8 := ShortInt(Code[p+1]);
    brTarget := p + 2 + imm8;
    text := 'j' + DisCcName(opc and 15);
    Result := (p + 2) - pos; Exit;
  end;

  if opc = $8D then   { lea Gv, M }
  begin
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    if mrm.IsReg then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;   { lea needs a mem operand }
    text := 'lea ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + mrm.MemText;
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  if opc = $63 then   { movsxd Gv, Ed (sign-extend 32->64, needs REX.W dest) }
  begin
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'movsxd ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, 4, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  if (opc = $69) or (opc = $6B) then   { imul Gv, Ev, imm32/imm8 (3-operand form) }
  begin
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    p := p + 1 + mrm.Consumed;
    if opc = $69 then
    begin
      if p + 4 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'imul ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHex32(DisRead32(p));
      Result := (p + 4) - pos; Exit;
    end
    else
    begin
      if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'imul ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex) + ', ' + DisIntToStr(ShortInt(Code[p]));
      Result := (p + 1) - pos; Exit;
    end;
  end;

  if opc = $87 then   { xchg Ev,Gv }
  begin
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'xchg ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  { ALU Ev,Gv (opcodes 00,08,10,18,20,28,30,38 + 1) and Gv,Ev (+2) forms }
  if ((opc and $C0) = 0) and ((opc and 7) <= 3) then
  begin
    regf := (opc shr 3) and 7;   { which ALU op: add/or/adc/sbb/and/sub/xor/cmp }
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    if (opc and 3) < 2 then
    begin
      { Eb/Ev, Gb/Gv: dest = r/m, src = reg }
      if (opc and 1) = 0 then sz := 1;
      text := DisAluName(regf) + ' ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
    end
    else
    begin
      { Gb/Gv, Eb/Ev: dest = reg, src = r/m }
      if (opc and 1) = 0 then sz := 1;
      text := DisAluName(regf) + ' ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex);
    end;
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  { ALU AL/eAX/rAX, imm short forms (04/0C/../3C = AL,imm8; 05/0D/../3D =
    eAX/rAX,imm32) -- no ModRM byte at all, a special-cased encoding for the
    accumulator register only. }
  if ((opc and $C0) = 0) and (((opc and 7) = 4) or ((opc and 7) = 5)) then
  begin
    regf := (opc shr 3) and 7;
    if (opc and 7) = 4 then
    begin
      if p + 2 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := DisAluName(regf) + ' al, ' + DisHexByte(Code[p+1]);
      Result := (p + 2) - pos; Exit;
    end
    else
    begin
      if p + 5 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := DisAluName(regf) + ' ' + DisReg(0, sz, hasRex) + ', ' + DisHex32(DisRead32(p + 1));
      Result := (p + 5) - pos; Exit;
    end;
  end;

  if (opc = $84) or (opc = $85) then   { test Ev,Gv }
  begin
    if opc = $84 then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'test ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  if (opc = $88) or (opc = $89) then   { mov Ev,Gv }
  begin
    if opc = $88 then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'mov ' + DisRmText(mrm, sz, hasRex) + ', ' + DisReg(mrm.RegField, sz, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;
  if (opc = $8A) or (opc = $8B) then   { mov Gv,Ev }
  begin
    if opc = $8A then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := 'mov ' + DisReg(mrm.RegField, sz, hasRex) + ', ' + DisRmText(mrm, sz, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  if (opc >= $B8) and (opc <= $BF) then   { mov r, imm32/imm64 }
  begin
    regf := opc - $B8; if rexB then regf := regf + 8;
    if rexW then
    begin
      if p + 9 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'mov ' + DisReg(regf, 8, True) + ', ' + DisHex64(DisRead32(p + 1), DisRead32(p + 5));
      Result := (p + 9) - pos; Exit;
    end
    else
    begin
      if p + 5 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'mov ' + DisReg(regf, 4, True) + ', ' + DisHex32(DisRead32(p + 1));
      Result := (p + 5) - pos; Exit;
    end;
  end;

  if (opc = $C6) or (opc = $C7) then   { mov Ev, imm8/imm32 (group 11 /0) }
  begin
    if opc = $C6 then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    p := p + 1 + mrm.Consumed;
    if opc = $C6 then
    begin
      if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'mov byte ' + DisRmText(mrm, 1, hasRex) + ', ' + DisHexByte(Code[p]);
      Result := (p + 1) - pos; Exit;
    end
    else
    begin
      if p + 4 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'mov ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHex32(DisRead32(p));
      Result := (p + 4) - pos; Exit;
    end;
  end;

  if (opc = $80) or (opc = $81) or (opc = $83) then   { ALU group1 Ev, imm }
  begin
    if opc = $80 then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    p := p + 1 + mrm.Consumed;
    if opc = $81 then
    begin
      if p + 4 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      imm32 := DisReadI32(p);
      text := DisAluName(mrm.RegField and 7) + ' ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHex32(LongWord(imm32));
      Result := (p + 4) - pos; Exit;
    end
    else
    begin
      if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      if opc = $80 then imm8 := ShortInt(Code[p]) else imm8 := ShortInt(Code[p]);
      text := DisAluName(mrm.RegField and 7) + ' ' + DisRmText(mrm, sz, hasRex) + ', ' + DisIntToStr(imm8);
      Result := (p + 1) - pos; Exit;
    end;
  end;

  if (opc = $A8) or (opc = $A9) then   { test AL/eAX, imm }
  begin
    if opc = $A8 then
    begin
      if p + 2 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'test al, ' + DisHexByte(Code[p+1]);
      Result := (p + 2) - pos; Exit;
    end
    else
    begin
      if p + 5 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
      text := 'test ' + DisReg(0, sz, hasRex) + ', ' + DisHex32(DisRead32(p + 1));
      Result := (p + 5) - pos; Exit;
    end;
  end;

  if (opc = $FE) or (opc = $FF) then   { INC/DEC/CALL/JMP/PUSH group }
  begin
    if opc = $FE then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    case mrm.RegField and 7 of
      0: mnem := 'inc';
      1: mnem := 'dec';
      2: begin text := 'call ' + DisRmText(mrm, 8, hasRex); Result := (p + 1 + mrm.Consumed) - pos; Exit; end;
      4: begin text := 'jmp ' + DisRmText(mrm, 8, hasRex); Result := (p + 1 + mrm.Consumed) - pos; Exit; end;
      6: begin text := 'push ' + DisRmText(mrm, 8, hasRex); Result := (p + 1 + mrm.Consumed) - pos; Exit; end;
    else
      text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit;
    end;
    if not mrm.IsReg then
    begin
      if sz = 8 then text := mnem + ' qword ' + mrm.MemText
      else text := mnem + ' dword ' + mrm.MemText;
    end
    else
      text := mnem + ' ' + DisRmText(mrm, sz, hasRex);
    Result := (p + 1 + mrm.Consumed) - pos; Exit;
  end;

  if (opc = $F6) or (opc = $F7) then   { TEST/NOT/NEG/MUL/IMUL/DIV/IDIV group }
  begin
    if opc = $F6 then sz := 1;
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    p := p + 1 + mrm.Consumed;
    if (mrm.RegField and 7 <= 1) then
    begin
      if sz = 1 then begin
        if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
        text := 'test ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHexByte(Code[p]);
        Result := (p + 1) - pos; Exit;
      end else begin
        if p + 4 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
        text := 'test ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHex32(DisRead32(p));
        Result := (p + 4) - pos; Exit;
      end;
    end;
    case mrm.RegField and 7 of
      2: mnem := 'not';
      3: mnem := 'neg';
      4: mnem := 'mul';
      5: mnem := 'imul';
      6: mnem := 'div';
      7: mnem := 'idiv';
    end;
    text := mnem + ' ' + DisRmText(mrm, sz, hasRex);
    Result := p - pos; Exit;
  end;

  if (opc = $D1) or (opc = $D3) or (opc = $C1) then   { shift group }
  begin
    if not DisParseModRM(p + 1, len, rexR, rexX, rexB, mrm) then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    p := p + 1 + mrm.Consumed;
    mnem := DisShiftName(mrm.RegField and 7);
    if opc = $D1 then begin text := mnem + ' ' + DisRmText(mrm, sz, hasRex) + ', 1'; Result := p - pos; Exit; end;
    if opc = $D3 then begin text := mnem + ' ' + DisRmText(mrm, sz, hasRex) + ', cl'; Result := p - pos; Exit; end;
    if p + 1 > len then begin text := 'db ' + DisHexByte(Code[pos]); Result := 1; Exit; end;
    text := mnem + ' ' + DisRmText(mrm, sz, hasRex) + ', ' + DisHexByte(Code[p]);
    Result := (p + 1) - pos; Exit;
  end;

  text := 'db ' + DisHexByte(Code[pos]);
  Result := 1;
end;

{ LOCK (0xF0) can prefix almost any read-modify-write instruction (atomic
  ops -- xchg/add/inc/etc, see test_multithreading.pas); it isn't part of
  any single opcode form, so it's peeled off here rather than threaded
  through DisOneReal's ~40 exit points. }
function DisOne(pos, len: Integer; var text: AnsiString; var brTarget: Integer): Integer;
var inner: Integer;
begin
  if (pos < len) and (Code[pos] = $F0) then
  begin
    inner := DisOneReal(pos + 1, len, text, brTarget);
    text := 'lock ' + text;
    Result := inner + 1;
  end
  else
    Result := DisOneReal(pos, len, text, brTarget);
end;

{ Writes s to fd via the shared TokChars scratch buffer (same pattern
  WriteMapFile uses, elfwriter.inc) -- sysopen/syswrite/sysclose/sysfchmod
  are ifdef-free (defs.inc), so this needs no FPC/self-host branching. }
procedure DisWriteStr(fd: Integer; const s: AnsiString);
var i, len: Integer;
begin
  len := Length(s);
  if len > STRING_CAP then len := STRING_CAP;
  for i := 0 to len - 1 do TokChars[i] := s[i + 1];
  if len > 0 then syswrite(fd, TokChars, len);
end;

{ `-S`: disassemble Code[0..CodeLen-1] (whatever codegen just produced, for
  any source language -- this doesn't touch codegen, it runs after) to a
  readable text file instead of writing an ELF binary. Written incrementally
  (one syswrite per line) rather than building one giant AnsiString, since a
  large program's disassembly text can run to tens of MB, past STRING_CAP. }
procedure WriteDisassemblyX64(const outPath: AnsiString);
var
  fd, pos, consumed, i, brTarget: Integer;
  line, labelText: AnsiString;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('-S: textual emit mode is x86-64 only');

  { O(1) "does a proc start/does a branch land here" lookup, built once --
    a per-instruction or per-branch linear scan over ProcCount would be
    O(CodeLen * ProcCount), far too slow for a multi-MB self-compile. }
  
  for i := 0 to CodeLen do AsmDisProcAtPos[i] := -1;
  for i := 0 to ProcCount - 1 do
    if (Procs[i].BodyAddr >= 0) and (Procs[i].BodyAddr <= CodeLen) then
      AsmDisProcAtPos[Procs[i].BodyAddr] := i;

  fd := sysopen(outPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
  if fd < 0 then Error('-S: cannot open ' + outPath + ' for output');
  sysfchmod(fd, 420); { chmod 644 }

  DisWriteStr(fd, '; -S: best-effort x86-64 disassembly (compiler debug/readability mode)' + Chr(10));
  DisWriteStr(fd, '; unrecognized byte sequences fall back to a raw "db 0xNN" line' + Chr(10) + Chr(10));

  pos := 0;
  while pos < CodeLen do
  begin
    if AsmDisProcAtPos[pos] >= 0 then
      DisWriteStr(fd, Procs[AsmDisProcAtPos[pos]].Name + ':' + Chr(10));
    consumed := DisOne(pos, CodeLen, line, brTarget);
    if consumed < 1 then consumed := 1;   { never infinite-loop on a decode bug }
    if brTarget >= 0 then
    begin
      if (brTarget >= 0) and (brTarget <= CodeLen) and (AsmDisProcAtPos[brTarget] >= 0) then
        labelText := Procs[AsmDisProcAtPos[brTarget]].Name
      else
        labelText := 'loc_' + DisHex32(LongWord(brTarget));
      line := line + ' ' + labelText;
    end;
    DisWriteStr(fd, '    ' + line + Chr(10));
    pos := pos + consumed;
  end;

  sysclose(fd);
end;
