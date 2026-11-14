{ SPDX-License-Identifier: MPL-2.0 }
{ casm_a64.inc -- GNU C inline asm templates for AArch64.

  The x86 path reads AT&T text with asmatt.inc and wraps the encoded bytes in
  frame-slot moves at parse time. That does not carry over: the aarch64
  backend's locals can live in registers and its frame addressing belongs to
  codegen. So the work is split at the same seam the operands cross:

    parse time (CAsmBuildBlockA64, cparser.inc): each operand is pinned to a
      register from the scratch pool x10..x15 (codegen's load/store helpers
      touch only x0, x1, x9 and d0), every %N in the template is replaced by
      that register's name, and the text is ENCODED HERE into AArch64 words in
      AsmBytes. The block also records which temporary feeds or drains which
      register (CAsmA64Bind*, defs.inc);
    codegen (the IR_ASM arm of ir_codegen_aarch64.inc): load each input with
      EmitLoadVarA64Dest, copy the words, store each output with
      EmitStoreVarA64. Those helpers know about residency and frame layout,
      so nothing here has to.

  The instruction set is the register/immediate subset real templates use
  (dropbear's sntrup761.c constant-time helpers first): shifts, logical ops
  with bitmask immediates, add/sub/cmp with extended registers, bitfield
  extracts, rbit/clz, the conditional selects and sets, mov/neg/mvn/mul.
  There is no memory operand, label or branch. Anything else is refused by
  name. Every encoding is checked against llvm-mc by
  tools/check_casm_a64_encodings.sh.
  feature-c-dropbear-builds-with-pxx (acceptance 5: aarch64) }

var
  CA64OpReg: array[0..MAX_CASM_OPERANDS-1] of Integer;    { -1: an immediate }
  CA64OpSz: array[0..MAX_CASM_OPERANDS-1] of Integer;
  CA64OpImm: array[0..MAX_CASM_OPERANDS-1] of Int64;
  CA64OpName: array[0..MAX_CASM_OPERANDS-1] of AnsiString;
  CA64OpCount: Integer;
  { the instruction being encoded }
  CA64Line, CA64Mn: AnsiString;
  CA64Ops: array[0..5] of AnsiString;
  CA64N: Integer;
  CA64Sf: Integer;          { 1 when the first register operand is an x register }
  CA64Is64: Boolean;

procedure CA64Fail(const why: AnsiString);
begin
  Error('C: aarch64 inline asm: ' + why + ' in "' + CA64Line + '"');
end;

procedure CA64Word(w: Int64);
var i: Integer;
begin
  if AsmBytesCount + 4 > Length(AsmBytes) then Error('C: aarch64 inline asm: the asm buffer is full');
  for i := 0 to 3 do
  begin
    AsmBytes[AsmBytesCount] := Byte((w shr (8 * i)) and $FF);
    Inc(AsmBytesCount);
  end;
end;

{ x0..x30 / w0..w30 / xzr / wzr. sp is refused: none of these encodings
  takes it, and register 31 means the zero register in all of them. }
function CA64RegOf(const sIn: AnsiString; var r: Integer; var is64: Boolean): Boolean;
var s: AnsiString;
begin
  s := AsmTextLowerStr(AsmTextTrim(sIn));
  Result := False;
  if (s = 'sp') or (s = 'wsp') then Exit;
  Result := AsmA64RegNum(s, r, is64);
end;

function CA64ImmOf(const sIn: AnsiString; var v: Int64): Boolean;
var s: AnsiString; neg: Boolean; i, d: Integer;
begin
  Result := False;
  s := AsmTextLowerStr(AsmTextTrim(sIn));
  if (s <> '') and (s[1] = '#') then s := AsmTextTrim(Copy(s, 2, Length(s) - 1));
  neg := False;
  if (s <> '') and (s[1] = '-') then begin neg := True; s := Copy(s, 2, Length(s) - 1); end
  else if (s <> '') and (s[1] = '+') then s := Copy(s, 2, Length(s) - 1);
  if s = '' then Exit;
  v := 0;
  if (Length(s) > 2) and (s[1] = '0') and (s[2] = 'x') then
  begin
    for i := 3 to Length(s) do
    begin
      if (s[i] >= '0') and (s[i] <= '9') then d := Ord(s[i]) - Ord('0')
      else if (s[i] >= 'a') and (s[i] <= 'f') then d := Ord(s[i]) - Ord('a') + 10
      else Exit;
      v := (v shl 4) or d;
    end;
  end
  else
    for i := 1 to Length(s) do
    begin
      if (s[i] < '0') or (s[i] > '9') then Exit;
      v := v * 10 + (Ord(s[i]) - Ord('0'));
    end;
  if neg then v := -v;
  Result := True;
end;

function CA64Cond(const sIn: AnsiString): Integer;
var s: AnsiString;
begin
  s := AsmTextLowerStr(AsmTextTrim(sIn));
  if s = 'eq' then Result := 0 else if s = 'ne' then Result := 1
  else if (s = 'cs') or (s = 'hs') then Result := 2 else if (s = 'cc') or (s = 'lo') then Result := 3
  else if s = 'mi' then Result := 4 else if s = 'pl' then Result := 5
  else if s = 'vs' then Result := 6 else if s = 'vc' then Result := 7
  else if s = 'hi' then Result := 8 else if s = 'ls' then Result := 9
  else if s = 'ge' then Result := 10 else if s = 'lt' then Result := 11
  else if s = 'gt' then Result := 12 else if s = 'le' then Result := 13
  else if s = 'al' then Result := 14
  else Result := -1;
end;

{ A logical (bitmask) immediate: a run of ones, rotated, repeated in an
  element of 2..64 bits. v is taken modulo the operand width. }
function CA64Bitmask(v: Int64; is64: Boolean; var nbit, immr, imms: Integer): Boolean;
var x, elt, pat, mask, rot: QWord; e, ones, r, i: Integer;
begin
  Result := False;
  x := QWord(v);
  if not is64 then
  begin
    x := x and QWord($FFFFFFFF);
    x := x or (x shl 32);
  end;
  if (x = 0) or (x = not QWord(0)) then Exit;
  e := 2;
  while e < 64 do
  begin
    mask := (QWord(1) shl e) - 1;
    elt := x and mask;
    i := e;
    while (i < 64) and (((x shr i) and mask) = elt) do i := i + e;
    if i >= 64 then Break;
    e := e * 2;
  end;
  if e = 64 then mask := not QWord(0) else mask := (QWord(1) shl e) - 1;
  elt := x and mask;
  ones := 0;
  for i := 0 to e - 1 do if ((elt shr i) and 1) = 1 then Inc(ones);
  if (ones = 0) or (ones = e) then Exit;
  pat := (QWord(1) shl ones) - 1;
  for r := 0 to e - 1 do
  begin
    if r = 0 then rot := pat
    else rot := ((pat shr r) or (pat shl (e - r))) and mask;
    if rot = elt then
    begin
      if e = 64 then nbit := 1 else nbit := 0;
      immr := r;
      imms := (((not (e - 1)) shl 1) and $3F) or (ones - 1);
      Result := True;
      Exit;
    end;
  end;
end;

function CA64Extend(const sIn: AnsiString; var opt, amt: Integer): Boolean;
var s, a: AnsiString; p: Integer; v: Int64;
begin
  s := AsmTextLowerStr(AsmTextTrim(sIn));
  amt := 0;
  p := Pos(' ', s);
  if p > 0 then
  begin
    a := AsmTextTrim(Copy(s, p + 1, Length(s) - p));
    s := Copy(s, 1, p - 1);
    if (not CA64ImmOf(a, v)) or (v < 0) or (v > 4) then begin Result := False; Exit; end;
    amt := Integer(v);
  end;
  Result := True;
  if s = 'uxtb' then opt := 0 else if s = 'uxth' then opt := 1
  else if s = 'uxtw' then opt := 2 else if s = 'uxtx' then opt := 3
  else if s = 'sxtb' then opt := 4 else if s = 'sxth' then opt := 5
  else if s = 'sxtw' then opt := 6 else if s = 'sxtx' then opt := 7
  else Result := False;
end;

procedure CA64Need(k: Integer);
begin
  if CA64N <> k then CA64Fail(CA64Mn + ' takes ' + AIntToStr(k) + ' operands');
end;

{ Operand k as a register. Operand 0 sets the width; the others must match. }
function CA64R(k: Integer): Integer;
var rr: Integer; bb: Boolean;
begin
  if (k >= CA64N) or not CA64RegOf(CA64Ops[k], rr, bb) then
    CA64Fail('operand ' + AIntToStr(k + 1) + ' of ' + CA64Mn + ' is not a register');
  if k = 0 then
  begin
    CA64Is64 := bb;
    if bb then CA64Sf := 1 else CA64Sf := 0;
  end
  else if bb <> CA64Is64 then
    CA64Fail('operand ' + AIntToStr(k + 1) + ' of ' + CA64Mn + ' is not the width of the first');
  Result := rr;
end;

function CA64IsReg(k: Integer): Boolean;
var rr: Integer; bb: Boolean;
begin
  Result := (k < CA64N) and CA64RegOf(CA64Ops[k], rr, bb);
end;

function CA64I(k: Integer): Int64;
var vv: Int64;
begin
  if (k >= CA64N) or not CA64ImmOf(CA64Ops[k], vv) then
    CA64Fail('operand ' + AIntToStr(k + 1) + ' of ' + CA64Mn + ' is not an immediate');
  Result := vv;
end;

function CA64SfBits: Int64;
begin
  Result := Int64(CA64Sf) shl 31;
end;

{ SBFM/UBFM rd, rn, #immr, #imms (N = sf) }
procedure CA64Bitfield(op: Int64; rd, rn, immr, imms: Integer);
var w: Integer;
begin
  w := 32 + 32 * CA64Sf;
  if (immr < 0) or (imms < 0) or (immr >= w) or (imms >= w) then
    CA64Fail(CA64Mn + ': bit position out of range');
  CA64Word(op or CA64SfBits or (Int64(CA64Sf) shl 22) or (Int64(immr) shl 16)
           or (Int64(imms) shl 10) or (Int64(rn) shl 5) or rd);
end;

{ add/sub/adds/subs (and cmp/cmn with rd = zr): operand k is a register,
  optionally followed by an extend, or an immediate of 12 bits (a negative
  one flips add and sub, as gas does). }
procedure CA64AddSub(isSub, setFlags: Boolean; rd, rn, k: Integer);
var op, v: Int64; rm, opt, amt: Integer; b64: Boolean;
begin
  op := 0;
  if isSub then op := op or $40000000;
  if setFlags then op := op or $20000000;
  if CA64IsReg(k) then
  begin
    if CA64N = k + 2 then
    begin
      { extended register: the source is a w register (an x one for
        uxtx/sxtx) whatever the destination's width }
      if not CA64Extend(CA64Ops[k + 1], opt, amt) then
        CA64Fail(CA64Mn + ': only an extend (uxtb .. sxtx) may follow the register');
      if not CA64RegOf(CA64Ops[k], rm, b64) then CA64Fail(CA64Mn + ': the extended operand is not a register');
      if b64 <> ((opt and 3) = 3) then
        CA64Fail(CA64Mn + ': the extended register must be x for uxtx/sxtx and w otherwise');
      CA64Word($0B200000 or op or CA64SfBits or (Int64(rm) shl 16) or (Int64(opt) shl 13)
               or (Int64(amt) shl 10) or (Int64(rn) shl 5) or rd);
      Exit;
    end;
    rm := CA64R(k);
    if CA64N <> k + 1 then CA64Fail(CA64Mn + ' has too many operands');
    CA64Word($0B000000 or op or CA64SfBits or (Int64(rm) shl 16) or (Int64(rn) shl 5) or rd);
    Exit;
  end;
  if CA64N <> k + 1 then CA64Fail(CA64Mn + ' has too many operands');
  v := CA64I(k);
  if v < 0 then begin v := -v; op := op xor $40000000; end;
  if v > 4095 then CA64Fail(CA64Mn + ': the immediate does not fit 12 bits');
  CA64Word($11000000 or op or CA64SfBits or (v shl 10) or (Int64(rn) shl 5) or rd);
end;

{ and/orr/eor/ands (tst with rd = zr): operand k is a register or a bitmask
  immediate. }
procedure CA64Logical(regOp, immOp: Int64; rd, rn, k: Integer);
var v: Int64; rm, nbit, immr, imms: Integer;
begin
  if CA64N <> k + 1 then CA64Fail(CA64Mn + ': a shifted register operand is not supported');
  if CA64IsReg(k) then
  begin
    rm := CA64R(k);
    CA64Word(regOp or CA64SfBits or (Int64(rm) shl 16) or (Int64(rn) shl 5) or rd);
    Exit;
  end;
  v := CA64I(k);
  if not CA64Bitmask(v, CA64Is64, nbit, immr, imms) then
    CA64Fail(CA64Mn + ': ' + AIntToStr(v) + ' is not a logical (bitmask) immediate');
  CA64Word(immOp or CA64SfBits or (Int64(nbit) shl 22) or (Int64(immr) shl 16)
           or (Int64(imms) shl 10) or (Int64(rn) shl 5) or rd);
end;

{ One instruction, its operands already register names and numbers. }
procedure CA64EncodeLine(const line: AnsiString);
var rest, mn: AnsiString; p, rd, rn, rm, ra, cc, w, imms: Integer;
    b64: Boolean; v, v2, op: Int64;
begin
  CA64Line := line;
  rest := AsmTextTrim(line);
  p := 1;
  while (p <= Length(rest)) and (rest[p] <> ' ') do Inc(p);
  mn := AsmTextLowerStr(Copy(rest, 1, p - 1));
  CA64Mn := mn;
  rest := AsmTextTrim(Copy(rest, p, Length(rest) - p + 1));
  if Pos('[', rest) > 0 then CA64Fail('memory operands are not supported');
  CA64N := 0;
  while rest <> '' do
  begin
    if CA64N > 5 then CA64Fail('too many operands');
    p := Pos(',', rest);
    if p = 0 then begin CA64Ops[CA64N] := AsmTextTrim(rest); rest := ''; end
    else
    begin
      CA64Ops[CA64N] := AsmTextTrim(Copy(rest, 1, p - 1));
      rest := AsmTextTrim(Copy(rest, p + 1, Length(rest) - p));
    end;
    Inc(CA64N);
  end;
  CA64Sf := 0; CA64Is64 := False;

  if (mn = 'lsl') or (mn = 'lsr') or (mn = 'asr') or (mn = 'ror') then
  begin
    CA64Need(3); rd := CA64R(0); rn := CA64R(1);
    if CA64IsReg(2) then
    begin
      rm := CA64R(2);
      if mn = 'lsl' then op := $1AC02000 else if mn = 'lsr' then op := $1AC02400
      else if mn = 'asr' then op := $1AC02800 else op := $1AC02C00;
      CA64Word(op or CA64SfBits or (Int64(rm) shl 16) or (Int64(rn) shl 5) or rd);
      Exit;
    end;
    w := 32 + 32 * CA64Sf;
    v := CA64I(2);
    if (v < 0) or (v >= w) then CA64Fail(mn + ': shift out of range');
    if mn = 'lsl' then CA64Bitfield($53000000, rd, rn, Integer((w - v) mod w), Integer(w - 1 - v))
    else if mn = 'lsr' then CA64Bitfield($53000000, rd, rn, Integer(v), w - 1)
    else if mn = 'asr' then CA64Bitfield($13000000, rd, rn, Integer(v), w - 1)
    else CA64Word($13800000 or CA64SfBits or (Int64(CA64Sf) shl 22) or (Int64(rn) shl 16)
                  or (v shl 10) or (Int64(rn) shl 5) or rd);    { extr rd, rn, rn, #v }
    Exit;
  end;
  if (mn = 'ubfx') or (mn = 'sbfx') or (mn = 'ubfiz') or (mn = 'sbfiz') then
  begin
    CA64Need(4); rd := CA64R(0); rn := CA64R(1); v := CA64I(2); v2 := CA64I(3);
    w := 32 + 32 * CA64Sf;
    if (v < 0) or (v2 < 1) or (v + v2 > w) then CA64Fail(mn + ': field out of range');
    if mn[1] = 'u' then op := $53000000 else op := $13000000;
    if (mn = 'ubfx') or (mn = 'sbfx') then CA64Bitfield(op, rd, rn, Integer(v), Integer(v + v2 - 1))
    else CA64Bitfield(op, rd, rn, Integer((w - v) mod w), Integer(v2 - 1));
    Exit;
  end;
  if (mn = 'sxtb') or (mn = 'sxth') or (mn = 'sxtw') or (mn = 'uxtb') or (mn = 'uxth') then
  begin
    CA64Need(2); rd := CA64R(0);
    if not CA64RegOf(CA64Ops[1], rn, b64) then CA64Fail(mn + ': the source is not a register');
    if b64 then CA64Fail(mn + ' takes a w source register');
    if (mn[1] = 'u') and CA64Is64 then CA64Fail(mn + ' writes a w register');
    if (mn = 'sxtw') and not CA64Is64 then CA64Fail('sxtw writes an x register');
    if mn[1] = 's' then op := $13000000 else op := $53000000;
    if mn[4] = 'b' then imms := 7 else if mn[4] = 'h' then imms := 15 else imms := 31;
    CA64Bitfield(op, rd, rn, 0, imms);
    Exit;
  end;
  if (mn = 'rbit') or (mn = 'clz') or (mn = 'cls') then
  begin
    CA64Need(2); rd := CA64R(0); rn := CA64R(1);
    if mn = 'rbit' then op := $5AC00000 else if mn = 'clz' then op := $5AC01000 else op := $5AC01400;
    CA64Word(op or CA64SfBits or (Int64(rn) shl 5) or rd);
    Exit;
  end;
  if (mn = 'and') or (mn = 'orr') or (mn = 'eor') or (mn = 'ands') then
  begin
    if CA64N < 3 then CA64Fail(mn + ' takes 3 operands');
    rd := CA64R(0); rn := CA64R(1);
    if mn = 'and' then CA64Logical($0A000000, $12000000, rd, rn, 2)
    else if mn = 'orr' then CA64Logical($2A000000, $32000000, rd, rn, 2)
    else if mn = 'eor' then CA64Logical($4A000000, $52000000, rd, rn, 2)
    else CA64Logical($6A000000, $72000000, rd, rn, 2);
    Exit;
  end;
  if mn = 'tst' then
  begin
    if CA64N < 2 then CA64Fail('tst takes 2 operands');
    rn := CA64R(0);
    CA64Logical($6A000000, $72000000, 31, rn, 1);
    Exit;
  end;
  if (mn = 'add') or (mn = 'sub') or (mn = 'adds') or (mn = 'subs') then
  begin
    if CA64N < 3 then CA64Fail(mn + ' takes 3 operands');
    rd := CA64R(0); rn := CA64R(1);
    CA64AddSub(mn[1] = 's', Length(mn) = 4, rd, rn, 2);
    Exit;
  end;
  if (mn = 'cmp') or (mn = 'cmn') then
  begin
    if CA64N < 2 then CA64Fail(mn + ' takes 2 operands');
    rn := CA64R(0);
    CA64AddSub(mn = 'cmp', True, 31, rn, 1);
    Exit;
  end;
  if (mn = 'cset') or (mn = 'csetm') then
  begin
    CA64Need(2); rd := CA64R(0); cc := CA64Cond(CA64Ops[1]);
    if (cc < 0) or (cc >= 14) then CA64Fail(mn + ': ' + CA64Ops[1] + ' is not a condition');
    if mn = 'cset' then op := $1A800400 else op := $5A800000;
    CA64Word(op or CA64SfBits or (Int64(31) shl 16) or (Int64(cc xor 1) shl 12) or (Int64(31) shl 5) or rd);
    Exit;
  end;
  if (mn = 'csel') or (mn = 'csinc') or (mn = 'csinv') or (mn = 'csneg') then
  begin
    CA64Need(4); rd := CA64R(0); rn := CA64R(1); rm := CA64R(2); cc := CA64Cond(CA64Ops[3]);
    if cc < 0 then CA64Fail(mn + ': ' + CA64Ops[3] + ' is not a condition');
    if mn = 'csel' then op := $1A800000 else if mn = 'csinc' then op := $1A800400
    else if mn = 'csinv' then op := $5A800000 else op := $5A800400;
    CA64Word(op or CA64SfBits or (Int64(rm) shl 16) or (Int64(cc) shl 12) or (Int64(rn) shl 5) or rd);
    Exit;
  end;
  if mn = 'mov' then
  begin
    CA64Need(2); rd := CA64R(0);
    if CA64IsReg(1) then
    begin
      rm := CA64R(1);
      CA64Word($2A0003E0 or CA64SfBits or (Int64(rm) shl 16) or rd);   { orr rd, zr, rm }
      Exit;
    end;
    v := CA64I(1);
    if (v < 0) or (v > $FFFF) then CA64Fail('mov: only an immediate 0..65535 is supported');
    CA64Word($52800000 or CA64SfBits or (v shl 5) or rd);                { movz }
    Exit;
  end;
  if (mn = 'neg') or (mn = 'mvn') then
  begin
    CA64Need(2); rd := CA64R(0); rm := CA64R(1);
    if mn = 'neg' then op := $4B0003E0 else op := $2A2003E0;
    CA64Word(op or CA64SfBits or (Int64(rm) shl 16) or rd);
    Exit;
  end;
  if (mn = 'mul') or (mn = 'madd') or (mn = 'msub') then
  begin
    if mn = 'mul' then CA64Need(3) else CA64Need(4);
    rd := CA64R(0); rn := CA64R(1); rm := CA64R(2);
    if mn = 'mul' then ra := 31 else ra := CA64R(3);
    if mn = 'msub' then op := $1B008000 else op := $1B000000;
    CA64Word(op or CA64SfBits or (Int64(rm) shl 16) or (Int64(ra) shl 10) or (Int64(rn) shl 5) or rd);
    Exit;
  end;
  if mn = 'nop' then begin CA64Need(0); CA64Word($D503201F); Exit; end;
  CA64Fail('instruction "' + mn + '" is not supported (register and immediate data'
           + ' processing only: shifts, logical, add/sub/cmp, bitfield, rbit/clz,'
           + ' cset/csel, mov/neg/mvn/mul)');
end;

{ The template with every operand reference replaced by its register name
  (or immediate), then encoded line by line. %N and %[name] take the operand's
  width (an 8-byte operand prints x, anything narrower w, as gcc prints by
  mode); %wN and %xN force it. %% is a literal %. Lines split at newline and
  ';'; a // comment runs to the end of its line. }
procedure CA64EncodeTemplate(const tpl: AnsiString);
var s, line, nm: AnsiString; i, j, k, num, sz: Integer; md: Char;
begin
  s := '';
  i := 1;
  while i <= Length(tpl) do
  begin
    if tpl[i] <> '%' then begin s := s + tpl[i]; Inc(i); Continue; end;
    Inc(i);
    if (i <= Length(tpl)) and (tpl[i] = '%') then begin s := s + '%'; Inc(i); Continue; end;
    md := ' ';
    if (i <= Length(tpl)) and ((tpl[i] = 'w') or (tpl[i] = 'x')) then begin md := tpl[i]; Inc(i); end;
    num := -1;
    if (i <= Length(tpl)) and (tpl[i] = '[') then
    begin
      j := i + 1;
      while (j <= Length(tpl)) and (tpl[j] <> ']') do Inc(j);
      nm := Copy(tpl, i + 1, j - i - 1);
      for k := 0 to CA64OpCount - 1 do if CA64OpName[k] = nm then num := k;
      if num < 0 then Error('C: aarch64 inline asm names operand [' + nm + '], which does not exist');
      i := j + 1;
    end
    else if (i <= Length(tpl)) and (tpl[i] >= '0') and (tpl[i] <= '9') then
    begin
      num := 0;
      while (i <= Length(tpl)) and (tpl[i] >= '0') and (tpl[i] <= '9') do
      begin
        num := num * 10 + Ord(tpl[i]) - Ord('0');
        Inc(i);
      end;
      if num >= CA64OpCount then
        Error('C: aarch64 inline asm uses %' + AIntToStr(num) + ', which is not an operand');
    end
    else Error('C: aarch64 inline asm: an operand modifier other than w or x is not supported');
    if CA64OpReg[num] < 0 then
    begin
      if md <> ' ' then Error('C: aarch64 inline asm: %' + md + ' on an immediate operand');
      s := s + AIntToStr(CA64OpImm[num]);
    end
    else
    begin
      sz := CA64OpSz[num];
      if md = ' ' then begin if sz = 8 then md := 'x' else md := 'w'; end;
      s := s + md + AIntToStr(CA64OpReg[num]);
    end;
  end;
  line := '';
  i := 1;
  while i <= Length(s) + 1 do
  begin
    if (i > Length(s)) or (s[i] = #10) or (s[i] = ';') then
    begin
      j := Pos('//', line);
      if j > 0 then line := Copy(line, 1, j - 1);
      line := AsmTextTrim(line);
      if line <> '' then CA64EncodeLine(line);
      line := '';
    end
    else if s[i] = #9 then line := line + ' '
    else line := line + s[i];
    Inc(i);
  end;
end;
