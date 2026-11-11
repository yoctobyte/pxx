{ asmregs.inc -- x86-64 register NAME -> (number, size) resolution, shared by
  the inline assembler (asmenc.inc), the text assembler (asmtext.inc) and the
  standalone asm harnesses. Split out of asmenc.inc 2026-11-11 so the harnesses
  test the REAL resolver: test_asm_emit_x64.pas carried a hand-written mock
  table that had no r8d..r15d, so `xor r8d, r8d` -- used by the compiler since
  batch 1 of the raw-asm conversion -- was never assembled by any harness. }

{ Lowercase one ASCII letter. Local to this file: asmtext.inc's AsmTextLower is
  the same function, but it is included five files LATER (see compiler.pas). }
function AsmRegLower(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Chr(Ord(c) + 32) else Result := c;
end;

{ 'ax'->0 'cx'->1 'dx'->2 'bx'->3 'sp'->4 'bp'->5 'si'->6 'di'->7; -1 for
  anything else. Both chars must already be lowercase. }
function AsmRegBase2(c1, c2: Char): Integer;
begin
  Result := -1;
  if c2 = 'x' then
  begin
    if c1 = 'a' then Result := 0
    else if c1 = 'c' then Result := 1
    else if c1 = 'd' then Result := 2
    else if c1 = 'b' then Result := 3;
  end
  else if c2 = 'p' then
  begin
    if c1 = 's' then Result := 4
    else if c1 = 'b' then Result := 5;
  end
  else if c2 = 'i' then
  begin
    if c1 = 's' then Result := 6
    else if c1 = 'd' then Result := 7;
  end;
end;

{ The r8..r15 sub-register suffix: 'd'->4 'w'->2 'b'->1; 0 = not a suffix. }
function AsmRegSuffixSize(c: Char): Integer;
begin
  if c = 'd' then Result := 4
  else if c = 'w' then Result := 2
  else if c = 'b' then Result := 1
  else Result := 0;
end;

{ Resolve a register name -> number (0..15) and size (1/2/4/8, plus 16 = xmm and
  32 = ymm -- the VEX emitter reads the size to choose L).

  Character-driven and ALLOCATION-FREE, which is the whole point. This used to
  CaseEqual against 32 string literals and then BUILD 64 more names --
  'r8'..'r15' in four sizes and 'xmm0'..'ymm15' -- with AppendChar, i.e. one
  SetLength (one heap realloc) per character, on EVERY call. And the common
  case is a MISS: AsmTextOperand calls this to ask "is this operand a
  register?" about immediates and displacements too, and a miss runs the entire
  table.

  Measured 2026-08-26 on an FPC `-pg` build compiling an EMPTY .npy (which
  still compiles all of pylib+pyeval, hence the volume): 284,481 calls issuing
  20,058,632 AppendChar and 10,679,880 CaseEqual calls -- 72% of that compile's
  whole string-append traffic came from this one function.
  See bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost. }
function AsmRegNum(const nm: AnsiString; var num, size: Integer): Boolean;
var
  n, b, sz, d: Integer;
  c1, c2, c3, c4, c5: Char;
begin
  Result := False;
  n := Length(nm);
  { every accepted spelling is 2..5 chars: al .. xmm15 }
  if (n < 2) or (n > 5) then Exit;

  c1 := AsmRegLower(nm[1]);
  c2 := AsmRegLower(nm[2]);
  c3 := Chr(0); c4 := Chr(0); c5 := Chr(0);
  if n >= 3 then c3 := AsmRegLower(nm[3]);
  if n >= 4 then c4 := AsmRegLower(nm[4]);
  if n >= 5 then c5 := AsmRegLower(nm[5]);

  if n = 2 then
  begin
    { al cl dl bl }
    if c2 = 'l' then
    begin
      if c1 = 'a' then begin num := 0; size := 1; Result := True; end
      else if c1 = 'c' then begin num := 1; size := 1; Result := True; end
      else if c1 = 'd' then begin num := 2; size := 1; Result := True; end
      else if c1 = 'b' then begin num := 3; size := 1; Result := True; end;
      Exit;
    end;
    { r8 r9 }
    if (c1 = 'r') and (c2 >= '8') and (c2 <= '9') then
    begin
      num := Ord(c2) - Ord('0'); size := 8; Result := True; Exit;
    end;
    { ax cx dx bx sp bp si di }
    b := AsmRegBase2(c1, c2);
    if b >= 0 then begin num := b; size := 2; Result := True; end;
    Exit;
  end;

  if n = 3 then
  begin
    { rax..rdi (size 8) and eax..edi (size 4) }
    if (c1 = 'r') or (c1 = 'e') then
    begin
      b := AsmRegBase2(c2, c3);
      if b >= 0 then
      begin
        num := b;
        if c1 = 'r' then size := 8 else size := 4;
        Result := True;
        Exit;
      end;
    end;
    { spl bpl sil dil -- REX-form low bytes; only the b>=4 half exists in this
      spelling ('axl' is not a register, so the base index must be 4..7). }
    if c3 = 'l' then
    begin
      b := AsmRegBase2(c1, c2);
      if b >= 4 then begin num := b; size := 1; Result := True; end;
      Exit;
    end;
    { r10..r15 }
    if (c1 = 'r') and (c2 = '1') and (c3 >= '0') and (c3 <= '5') then
    begin
      num := 10 + (Ord(c3) - Ord('0')); size := 8; Result := True; Exit;
    end;
    { r8d r8w r8b r9d r9w r9b }
    if (c1 = 'r') and (c2 >= '8') and (c2 <= '9') then
    begin
      sz := AsmRegSuffixSize(c3);
      if sz > 0 then begin num := Ord(c2) - Ord('0'); size := sz; Result := True; end;
    end;
    Exit;
  end;

  if n = 4 then
  begin
    { r10d .. r15b }
    if (c1 = 'r') and (c2 = '1') and (c3 >= '0') and (c3 <= '5') then
    begin
      sz := AsmRegSuffixSize(c4);
      if sz > 0 then
      begin
        num := 10 + (Ord(c3) - Ord('0')); size := sz; Result := True;
      end;
      Exit;
    end;
    { xmm0..xmm9 / ymm0..ymm9 }
    if (c2 = 'm') and (c3 = 'm') and (c4 >= '0') and (c4 <= '9') then
    begin
      if c1 = 'x' then begin num := Ord(c4) - Ord('0'); size := 16; Result := True; end
      else if c1 = 'y' then begin num := Ord(c4) - Ord('0'); size := 32; Result := True; end;
    end;
    Exit;
  end;

  { n = 5: xmm10..xmm15 / ymm10..ymm15 }
  if (c2 = 'm') and (c3 = 'm') and (c4 = '1') and (c5 >= '0') and (c5 <= '5') then
  begin
    d := 10 + (Ord(c5) - Ord('0'));
    if c1 = 'x' then begin num := d; size := 16; Result := True; end
    else if c1 = 'y' then begin num := d; size := 32; Result := True; end;
  end;
end;
