{ ===== .asm -> executable frontend (feature-asm-source-frontend) =====

  Parses a hand-written x86-64 assembly file (Intel syntax, dst-first) and
  drives lib/asmcore's AsmEncodeX64 + the existing ET_EXEC writer. This grew
  out of the straight-line MVP (feature-asm-mvp-frontend); it now adds the
  layer-2 symbolic resolution the MVP deferred:

    - labels (`name:`, alone or prefixing an instruction)
    - branches: jmp / call / jcc <label>  (rel32, forward + backward resolved)
    - syscall and the rest of asmcore's grown instruction set
    - `[base+disp]` memory operands

  Still deferred to later increments (clear errors point at them):
    - section/global/extern directives, db/dw/dd/dq data + a data section
      (needs rip-relative relocation), .so/object output.

  Termination: as in the MVP, a fixed exit epilogue (`mov eax,60; syscall`) is
  appended after the program, so a program that falls through exits with the
  value left in rdi. A program may also exit itself with an explicit `syscall`.
  x86-64 only. }

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

{ True if mnem is a control-transfer that takes a single label target. }
function AsmIsBranch(const mnem: AnsiString): Boolean;
begin
  Result := (mnem = 'jmp') or (mnem = 'call')
    or (mnem = 'je') or (mnem = 'jz') or (mnem = 'jne') or (mnem = 'jnz')
    or (mnem = 'jl') or (mnem = 'jnge') or (mnem = 'jge') or (mnem = 'jnl')
    or (mnem = 'jle') or (mnem = 'jng') or (mnem = 'jg') or (mnem = 'jnle')
    or (mnem = 'jb') or (mnem = 'jc') or (mnem = 'jnae')
    or (mnem = 'jae') or (mnem = 'jnb') or (mnem = 'jnc')
    or (mnem = 'jbe') or (mnem = 'jna') or (mnem = 'ja') or (mnem = 'jnbe')
    or (mnem = 'js') or (mnem = 'jns') or (mnem = 'jp') or (mnem = 'jpe')
    or (mnem = 'jnp') or (mnem = 'jpo') or (mnem = 'jo') or (mnem = 'jno');
end;

{ Parse a memory operand `[base+disp]` / `[base-disp]` / `[base]`. The token
  still has its surrounding brackets. Errors on a malformed form. }
procedure AsmParseMem(const tok: AnsiString; lineNo: Integer; var op: TAsmOperand);
var inner, basetok, disptok: AnsiString; sgn, i, n: Integer; reg, size: Integer;
    disp: Int64; ok: Boolean;
begin
  n := Length(tok);
  if (n < 3) or (tok[1] <> '[') or (tok[n] <> ']') then
    Error('asm:' + AsmIntToStr(lineNo) + ': malformed memory operand "' + tok + '"');
  inner := AsmTrim(Copy(tok, 2, n - 2));
  { find a +/- separating base from displacement (not at position 1) }
  sgn := 0; i := 2;
  while i <= Length(inner) do
  begin
    if (inner[i] = '+') or (inner[i] = '-') then begin sgn := i; i := Length(inner) + 1; end
    else Inc(i);
  end;
  if sgn = 0 then
  begin
    basetok := AsmTrim(inner);
    disp := 0;
  end
  else
  begin
    basetok := AsmTrim(Copy(inner, 1, sgn - 1));
    disptok := AsmTrim(Copy(inner, sgn + 1, Length(inner) - sgn));
    disp := AsmParseInt(disptok, ok);
    if not ok then Error('asm:' + AsmIntToStr(lineNo) + ': bad memory displacement "' + disptok + '"');
    if inner[sgn] = '-' then disp := -disp;
  end;
  if not AsmRegLookup(AsmLower(basetok), reg, size) then
    Error('asm:' + AsmIntToStr(lineNo) + ': bad base register in "' + tok + '"');
  op := MemOp(reg, disp);
end;

{ Build one TAsmOperand from a textual operand (register / [mem] / immediate).
  out-param avoids an asmcore-typed function result, which the compiler's
  two-pass prescan does not resolve here. }
procedure AsmParseOperand(const tok: AnsiString; lineNo: Integer; var op: TAsmOperand);
var reg, size: Integer; iv: Int64; ok: Boolean;
begin
  if (Length(tok) > 0) and (tok[1] = '[') then
    AsmParseMem(tok, lineNo, op)
  else if AsmRegLookup(AsmLower(tok), reg, size) then
    op := RegOp(reg, size)
  else
  begin
    iv := AsmParseInt(tok, ok);
    if not ok then Error('asm:' + AsmIntToStr(lineNo) + ': bad operand "' + tok + '"');
    op := ImmOp(iv);
  end;
end;

{ Reject a directive that still needs the deferred (data/section/symbol)
  machinery, with a clear pointer at the next increment. }
procedure AsmRejectIfUnsupported(const mnem: AnsiString; lineNo: Integer);
begin
  if (mnem = 'extern') or (mnem = 'global') or (mnem = 'section')
     or (mnem = 'db') or (mnem = 'dw') or (mnem = 'dd') or (mnem = 'dq') then
    Error('asm:' + AsmIntToStr(lineNo) +
      ': "' + mnem + '" needs a data section / symbol table — not in this ' +
      'frontend increment yet (see feature-asm-source-frontend). Supported: ' +
      'labels, jmp/call/jcc, syscall, and asmcore''s register/imm/[mem] forms.');
end;

const
  ASM_MAX_LABELS = 4096;
  ASM_MAX_FIXUPS = 8192;

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
  baseOff: Integer;
  branchLabel: AnsiString;
  { label table + branch fixups (layer-2 symbolic resolution) }
  lblName: array[0..ASM_MAX_LABELS-1] of AnsiString;
  lblOff:  array[0..ASM_MAX_LABELS-1] of Integer;
  lblCount: Integer;
  fixPos:  array[0..ASM_MAX_FIXUPS-1] of Integer;
  fixName: array[0..ASM_MAX_FIXUPS-1] of AnsiString;
  fixLine: array[0..ASM_MAX_FIXUPS-1] of Integer;
  fixCount: Integer;
  found: Boolean; rel: Int64; tgt: Integer;
  labelPart: AnsiString;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('asm frontend: x86-64 only (matches lib/asmcore coverage)');
  n := Length(Source);
  i := 1;
  lineNo := 0;
  emittedAny := False;
  lblCount := 0;
  fixCount := 0;

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

    { a leading `name:` is a label definition (alone, or prefixing an instr) }
    ci := Pos(':', line);
    if ci > 0 then
    begin
      labelPart := AsmTrim(Copy(line, 1, ci - 1));
      if labelPart = '' then
        Error('asm:' + AsmIntToStr(lineNo) + ': empty label');
      if lblCount >= ASM_MAX_LABELS then
        Error('asm:' + AsmIntToStr(lineNo) + ': too many labels');
      lblName[lblCount] := AsmLower(labelPart);
      lblOff[lblCount] := CodeLen;
      Inc(lblCount);
      line := AsmTrim(Copy(line, ci + 1, Length(line) - ci));
      if line = '' then Continue;   { label-only line }
    end;

    if line[1] = '.' then
      Error('asm:' + AsmIntToStr(lineNo) + ': directives (.section etc) not supported yet');

    { split mnemonic vs operand list }
    ci := 1;
    while (ci <= Length(line)) and (not AsmIsSpace(line[ci])) do Inc(ci);
    mnem := AsmLower(Copy(line, 1, ci - 1));
    restp := AsmTrim(Copy(line, ci, Length(line) - ci + 1));

    AsmRejectIfUnsupported(mnem, lineNo);

    branchLabel := '';
    instr.Mnemonic := mnem;

    if AsmIsBranch(mnem) then
    begin
      { the single operand is a label target -> rel32 patch site }
      if restp = '' then
        Error('asm:' + AsmIntToStr(lineNo) + ': "' + mnem + '" needs a label target');
      branchLabel := AsmLower(AsmTrim(restp));
      instr.OperandCount := 1;
      instr.Operands[0] := PatchOp(4);
    end
    else
    begin
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
      instr.OperandCount := opCount;
      for k := 0 to opCount - 1 do
        AsmParseOperand(ops[k], lineNo, instr.Operands[k]);
    end;

    { encode via lib/asmcore -> Code[] ; remember branch fixups }
    baseOff := CodeLen;
    BufInit(buf);
    PatchListInit(patches);
    if not AsmEncodeX64(instr, buf, patches) then
      Error('asm:' + AsmIntToStr(lineNo) + ': ' + AsmCoreLastError);
    for k := 0 to buf.Len - 1 do
      EmitB(buf.Bytes[k]);
    for k := 0 to patches.Count - 1 do
    begin
      if branchLabel = '' then
        Error('asm:' + AsmIntToStr(lineNo) + ': unresolved operand patch with no label');
      if fixCount >= ASM_MAX_FIXUPS then
        Error('asm:' + AsmIntToStr(lineNo) + ': too many branch fixups');
      fixPos[fixCount] := baseOff + patches.Items[k].Offset;
      fixName[fixCount] := branchLabel;
      fixLine[fixCount] := lineNo;
      Inc(fixCount);
    end;
    emittedAny := True;
  end;

  if not emittedAny then
    Error('asm: no instructions in source');

  { resolve branch fixups: rel32 = target - (patchPos + 4) }
  for k := 0 to fixCount - 1 do
  begin
    found := False; tgt := 0;
    for i := 0 to lblCount - 1 do
      if lblName[i] = fixName[k] then begin tgt := lblOff[i]; found := True; end;
    if not found then
      Error('asm:' + AsmIntToStr(fixLine[k]) + ': undefined label "' + fixName[k] + '"');
    rel := tgt - (fixPos[k] + 4);
    Patch32(fixPos[k], rel);
  end;

  { exit epilogue: SYS_exit(rdi). mov eax,60 ; syscall. A program that runs off
    the end exits with whatever it left in rdi (programs may also exit via an
    explicit `syscall`). }
  EmitB($B8); EmitB($3C); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 60 }
  EmitB($0F); EmitB($05);                                       { syscall }
end;
