{ ===== MVP .asm -> executable frontend (feature-asm-mvp-frontend) =====

  The minimal slice: a flat sequence of straight-line instructions (mov/add/ret,
  matching lib/asmcore's current coverage) -> machine code via asmcore's
  AsmEncodeX64 -> the existing ET_EXEC writer. NO labels, jumps, extern/global,
  or sections (those land with the full feature-asm-source-frontend once asmcore
  grows branches). Each instruction is encoded by lib/asmcore so a `.asm` fixture
  is a real end-to-end test of that library.

  Termination: asmcore has no syscall mnemonic yet, so a flat program cannot exit
  on its own. The frontend appends a fixed exit epilogue (`mov eax,60; syscall`)
  that exits with the value left in rdi — so a `.asm` computes its result into rdi
  and the process exit code reflects it. x86-64 only. }

{ ---- tiny line helpers (self-contained; the compiler proper has its own) ---- }

function AsmIsSpace(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = #9) or (c = #13);
end;

function AsmTrim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1; b := Length(s);
  while (a <= b) and AsmIsSpace(s[a]) do Inc(a);
  while (b >= a) and AsmIsSpace(s[b]) do Dec(b);
  Result := Copy(s, a, b - a + 1);
end;

function AsmLower(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    r := r + c;
  end;
  Result := r;
end;

function AsmIntToStr(v: Integer): AnsiString;
var neg: Boolean; u: Integer; r: AnsiString;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0; u := v; if neg then u := -u;
  r := '';
  while u > 0 do begin r := Chr(Ord('0') + (u mod 10)) + r; u := u div 10; end;
  if neg then r := '-' + r;
  Result := r;
end;

{ Resolve a register name to its asmcore number + width (8 = 64-bit, 4 = 32-bit).
  Returns False if not a recognised GP register. }
function AsmRegLookup(const nm: AnsiString; var reg: Integer; var size: Integer): Boolean;
var r, sz: Integer; found: Boolean;
begin
  r := -1; sz := 8; found := True;
  { 64-bit }
  if nm = 'rax' then r := reg_rax else if nm = 'rcx' then r := reg_rcx
  else if nm = 'rdx' then r := reg_rdx else if nm = 'rbx' then r := reg_rbx
  else if nm = 'rsp' then r := reg_rsp else if nm = 'rbp' then r := reg_rbp
  else if nm = 'rsi' then r := reg_rsi else if nm = 'rdi' then r := reg_rdi
  else if nm = 'r8'  then r := reg_r8  else if nm = 'r9'  then r := reg_r9
  else if nm = 'r10' then r := reg_r10 else if nm = 'r11' then r := reg_r11
  else if nm = 'r12' then r := reg_r12 else if nm = 'r13' then r := reg_r13
  else if nm = 'r14' then r := reg_r14 else if nm = 'r15' then r := reg_r15
  else found := False;
  if not found then
  begin
    found := True; sz := 4;
    if nm = 'eax' then r := reg_rax else if nm = 'ecx' then r := reg_rcx
    else if nm = 'edx' then r := reg_rdx else if nm = 'ebx' then r := reg_rbx
    else if nm = 'esp' then r := reg_rsp else if nm = 'ebp' then r := reg_rbp
    else if nm = 'esi' then r := reg_rsi else if nm = 'edi' then r := reg_rdi
    else if nm = 'r8d'  then r := reg_r8  else if nm = 'r9d'  then r := reg_r9
    else if nm = 'r10d' then r := reg_r10 else if nm = 'r11d' then r := reg_r11
    else if nm = 'r12d' then r := reg_r12 else if nm = 'r13d' then r := reg_r13
    else if nm = 'r14d' then r := reg_r14 else if nm = 'r15d' then r := reg_r15
    else found := False;
  end;
  if found then begin reg := r; size := sz; end;
  Result := found;
end;

{ Parse a signed decimal or 0x-hex literal. Sets ok=False on a malformed token. }
function AsmParseInt(const s: AnsiString; var ok: Boolean): Int64;
var i, n: Integer; neg, hex: Boolean; v: Int64; c: Char; d: Integer;
begin
  ok := True; v := 0; neg := False; hex := False;
  n := Length(s); i := 1;
  if n = 0 then begin ok := False; Result := 0; Exit; end;
  if s[i] = '-' then begin neg := True; Inc(i); end
  else if s[i] = '+' then Inc(i);
  if (i + 1 <= n) and (s[i] = '0') and ((s[i+1] = 'x') or (s[i+1] = 'X')) then
  begin hex := True; i := i + 2; end;
  if i > n then begin ok := False; Result := 0; Exit; end;
  while i <= n do
  begin
    c := s[i]; d := -1;
    if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
    else if hex and (c >= 'a') and (c <= 'f') then d := 10 + Ord(c) - Ord('a')
    else if hex and (c >= 'A') and (c <= 'F') then d := 10 + Ord(c) - Ord('A');
    if d < 0 then begin ok := False; Result := 0; Exit; end;
    if hex then v := v * 16 + d else v := v * 10 + d;
    Inc(i);
  end;
  if neg then v := -v;
  Result := v;
end;

{ Build one TAsmOperand from a textual operand (out-param avoids an asmcore-typed
  function result, which the compiler's two-pass prescan does not resolve here). }
procedure AsmParseOperand(const tok: AnsiString; lineNo: Integer; var op: TAsmOperand);
var reg, size: Integer; iv: Int64; ok: Boolean;
begin
  if AsmRegLookup(AsmLower(tok), reg, size) then
    op := RegOp(reg, size)
  else
  begin
    iv := AsmParseInt(tok, ok);
    if not ok then Error('asm:' + AsmIntToStr(lineNo) + ': bad operand "' + tok + '"');
    op := ImmOp(iv);
  end;
end;

{ Reject a mnemonic that needs the deferred (label/branch/symbol) machinery, with
  a clear pointer at the full feature. }
procedure AsmRejectIfUnsupported(const mnem: AnsiString; lineNo: Integer);
begin
  if (mnem = 'jmp') or (mnem = 'je') or (mnem = 'jne') or (mnem = 'jz') or (mnem = 'jnz')
     or (mnem = 'jg') or (mnem = 'jl') or (mnem = 'jge') or (mnem = 'jle') or (mnem = 'call')
     or (mnem = 'extern') or (mnem = 'global') or (mnem = 'section') or (mnem = 'syscall') then
    Error('asm:' + AsmIntToStr(lineNo) +
      ': "' + mnem + '" needs labels/branches/symbols — not in the MVP frontend ' +
      '(see feature-asm-source-frontend). MVP accepts only straight-line mov/add/ret.');
end;

procedure ParseAsmProgram;
var
  i, n, lineNo, opCount, k: Integer;
  line, raw, mnem, restp, tok: AnsiString;
  ops: array[0..3] of AnsiString;
  ci: Integer;
  emittedAny: Boolean;
  instr: TAsmInstr;
  buf: TAsmByteBuf;
  patches: TAsmPatchList;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('asm frontend: x86-64 only in the MVP (matches lib/asmcore coverage)');
  n := Length(Source);
  i := 1;
  lineNo := 0;
  emittedAny := False;
  while i <= n do
  begin
    { slice one physical line }
    raw := '';
    while (i <= n) and (Source[i] <> #10) do
    begin
      if Source[i] <> #13 then raw := raw + Source[i];
      Inc(i);
    end;
    if (i <= n) and (Source[i] = #10) then Inc(i);
    Inc(lineNo);

    { strip a ';' comment }
    ci := Pos(';', raw);
    if ci > 0 then raw := Copy(raw, 1, ci - 1);
    line := AsmTrim(raw);
    if line = '' then Continue;

    if Pos(':', line) > 0 then
      Error('asm:' + AsmIntToStr(lineNo) + ': labels are not supported in the MVP frontend');
    if line[1] = '.' then
      Error('asm:' + AsmIntToStr(lineNo) + ': directives/sections are not supported in the MVP frontend');

    { split mnemonic vs operand list }
    ci := 1;
    while (ci <= Length(line)) and (not AsmIsSpace(line[ci])) do Inc(ci);
    mnem := AsmLower(Copy(line, 1, ci - 1));
    restp := AsmTrim(Copy(line, ci, Length(line) - ci + 1));

    AsmRejectIfUnsupported(mnem, lineNo);

    { comma-split operands }
    opCount := 0;
    while restp <> '' do
    begin
      ci := Pos(',', restp);
      if ci > 0 then
      begin
        tok := AsmTrim(Copy(restp, 1, ci - 1));
        restp := AsmTrim(Copy(restp, ci + 1, Length(restp) - ci));
      end
      else
      begin
        tok := AsmTrim(restp);
        restp := '';
      end;
      if opCount > 3 then Error('asm:' + AsmIntToStr(lineNo) + ': too many operands');
      ops[opCount] := tok;
      Inc(opCount);
    end;

    { encode this instruction via lib/asmcore -> Code[] }
    instr.Mnemonic := mnem;
    instr.OperandCount := opCount;
    for k := 0 to opCount - 1 do
      AsmParseOperand(ops[k], lineNo, instr.Operands[k]);
    BufInit(buf);
    PatchListInit(patches);
    if not AsmEncodeX64(instr, buf, patches) then
      Error('asm:' + AsmIntToStr(lineNo) + ': ' + AsmCoreLastError);
    if patches.Count > 0 then
      Error('asm:' + AsmIntToStr(lineNo) + ': operand needs relocation — not supported in the MVP frontend');
    for k := 0 to buf.Len - 1 do
      EmitB(buf.Bytes[k]);
    emittedAny := True;
  end;

  if not emittedAny then
    Error('asm: no instructions in source');

  { exit epilogue: SYS_exit(rdi). mov eax,60 ; syscall. The program's result is
    whatever it left in rdi. }
  EmitB($B8); EmitB($3C); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 60 }
  EmitB($0F); EmitB($05);                                       { syscall }
end;
