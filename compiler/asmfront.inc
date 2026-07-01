{ ===== .asm -> executable frontend (feature-asm-source-frontend) =====

  Parses a hand-written x86-64 assembly file (Intel syntax, dst-first) and
  drives lib/asmcore's AsmEncodeX64 + the existing ET_EXEC writer. This grew
  out of the straight-line MVP (feature-asm-mvp-frontend); it now adds the
  layer-2 symbolic resolution the MVP deferred:

    - labels (`name:`, alone or prefixing an instruction)
    - branches: jmp / call / jcc <label>  (rel32, forward + backward resolved)
    - syscall and the rest of asmcore's grown instruction set
    - `[base+disp]` memory operands, `section .text`/`section .data` +
      db/dw/dd/dq, `[rel label]` rip-relative addressing
    - `extern <name>[, "libname"]` (default libc.so.6): synthesizes a
      Procs[] entry exactly like a Pascal `external 'lib'` declaration, so
      `call <name>` routes through the existing GOT-indirect dynamic-call
      machinery (RegisterExternal/EmitExternalIndirectCall,
      PrepareDynamicData/PatchDynCallSites in elfwriter.inc) — no new ELF-
      writer code. jmp/jcc to an extern name is rejected (only `call` goes
      through an indirect GOT slot; a direct rel32 jump can't).
    - `global <label>`: overrides the ELF entry point (default: start of
      Code[]) with a chosen code label's offset (AsmEntryOff, defs.inc;
      always 0 — a no-op — for every non-.asm compile).

  Still deferred to later increments (clear errors point at them):
    - `-c` ET_REL object output, `--shared` ET_DYN .so writer (see
      feature-asm-source-frontend tasks #5/#6).

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

{ Build one TAsmOperand from a textual operand (register / [mem] / [rel label]
  / immediate). out-param avoids an asmcore-typed function result, which the
  compiler's two-pass prescan does not resolve here. ripLabel is set (lower-
  cased) iff the operand was a `[rel name]` rip-relative form — the caller
  threads that into the same label-fixup table branches already use, since
  the relocation arithmetic (target - (patch_offset+4)) is identical. }
procedure AsmParseOperand(const tok: AnsiString; lineNo: Integer; var op: TAsmOperand; var ripLabel: AnsiString);
var reg, size: Integer; iv: Int64; ok: Boolean; inner, innerLower, nm: AnsiString;
begin
  ripLabel := '';
  if (Length(tok) > 0) and (tok[1] = '[') then
  begin
    inner := AsmTrim(Copy(tok, 2, Length(tok) - 2));
    innerLower := AsmLower(inner);
    if (Length(innerLower) > 4) and (Copy(innerLower, 1, 4) = 'rel ') then
    begin
      nm := AsmLower(AsmTrim(Copy(inner, 5, Length(inner) - 4)));
      if nm = '' then Error('asm:' + AsmIntToStr(lineNo) + ': empty rip-relative label');
      op := MemOp(REG_RIP, 0);
      ripLabel := nm;
      Exit;
    end;
    AsmParseMem(tok, lineNo, op);
  end
  else if AsmRegLookup(AsmLower(tok), reg, size) then
    op := RegOp(reg, size)
  else
  begin
    iv := AsmParseInt(tok, ok);
    if not ok then Error('asm:' + AsmIntToStr(lineNo) + ': bad operand "' + tok + '"');
    op := ImmOp(iv);
  end;
end;

{ Parse a `db`/`dw`/`dd`/`dq` data line's operand list into dataBuf, quote-
  aware (string literals only valid with `db`, expand one byte per char). }
procedure AsmParseDataLine(const mnem: AnsiString; const restp: AnsiString; lineNo: Integer; var dataBuf: TAsmByteBuf);
var width, i, n: Integer; tok: AnsiString; ok: Boolean; v: Int64;
begin
  if mnem = 'db' then width := 1
  else if mnem = 'dw' then width := 2
  else if mnem = 'dd' then width := 4
  else if mnem = 'dq' then width := 8
  else begin Error('asm:' + AsmIntToStr(lineNo) + ': unknown data directive "' + mnem + '" (.data section allows db/dw/dd/dq only)'); width := 0; end;

  if restp = '' then Error('asm:' + AsmIntToStr(lineNo) + ': "' + mnem + '" needs operands');

  n := Length(restp);
  i := 1;
  while i <= n do
  begin
    while (i <= n) and AsmIsSpace(restp[i]) do Inc(i);
    if i > n then Break;
    if restp[i] = '"' then
    begin
      if width <> 1 then Error('asm:' + AsmIntToStr(lineNo) + ': string literal only valid with db');
      Inc(i);
      while (i <= n) and (restp[i] <> '"') do
      begin
        BufAppend(dataBuf, Byte(Ord(restp[i])));
        Inc(i);
      end;
      if i > n then Error('asm:' + AsmIntToStr(lineNo) + ': unterminated string literal');
      Inc(i);   { closing quote }
    end
    else
    begin
      tok := '';
      while (i <= n) and (restp[i] <> ',') do begin tok := tok + restp[i]; Inc(i); end;
      tok := AsmTrim(tok);
      if tok = '' then Error('asm:' + AsmIntToStr(lineNo) + ': empty data value');
      v := AsmParseInt(tok, ok);
      if not ok then Error('asm:' + AsmIntToStr(lineNo) + ': bad data value "' + tok + '"');
      case width of
        1: BufAppend(dataBuf, Byte(v and $FF));
        2: begin BufAppend(dataBuf, Byte(v and $FF)); BufAppend(dataBuf, Byte((v shr 8) and $FF)); end;
        4: BufAppendI32(dataBuf, v);
        8: BufAppendI64(dataBuf, v);
      end;
    end;
    while (i <= n) and AsmIsSpace(restp[i]) do Inc(i);
    if (i <= n) and (restp[i] = ',') then Inc(i)
    else if i <= n then Error('asm:' + AsmIntToStr(lineNo) + ': expected "," in data list "' + restp + '"');
  end;
end;

const
  ASM_FRONT_MAX_EXTERNS = 256;

type
  { Named array types, not `array of T` open params: pxx self-host currently
    loses writes/reads through a `var`/`const array of AnsiString` open-array
    parameter (see bug-open-array-managed-param-loses-writes) — a fixed
    matching type on both sides sidesteps it. }
  TAsmExternNames = array[0..ASM_FRONT_MAX_EXTERNS-1] of AnsiString;
  TAsmExternProcs = array[0..ASM_FRONT_MAX_EXTERNS-1] of Integer;

{ Look up a case-sensitive extern symbol name (real C link-time names are
  case-sensitive, unlike this frontend's own lower-cased label table). }
function AsmExternLookup(const nm: AnsiString; const externName: TAsmExternNames;
  const externProcIdx: TAsmExternProcs; externCount: Integer; var procIdx: Integer): Boolean;
var i: Integer;
begin
  Result := False; procIdx := -1;
  for i := 0 to externCount - 1 do
    if externName[i] = nm then begin procIdx := externProcIdx[i]; Result := True; end;
end;

{ Parse an `extern <name>[, "libname"]` line: synthesizes a Procs[] entry
  exactly like a Pascal `external 'lib'` declaration (RegisterProc + the
  ProcExternal/ProcLibrary flags PrepareDynamicData/PatchDynCallSites already
  know how to turn into a DT_NEEDED + GOT-indirect `call`), so no new ELF-
  writer code is needed — the .asm frontend just needs to reach the existing
  dynamic-link machinery. Default library is libc.so.6 (the overwhelmingly
  common case for hand-written asm calling out; the raw `syscall` instruction
  covers the kernel-only case without needing `extern` at all).

  Returns the registered name + Procs[] index via scalar `var` params instead
  of writing an extern-table array element itself — a `var array[..] of
  AnsiString` param silently loses its write in the pxx self-hosted binary
  (see bug-var-array-of-ansistring-param-loses-writes); the caller does the
  array[externCount]:=... assignment directly on its own local instead. }
procedure AsmParseExternLine(const restp0: AnsiString; lineNo: Integer;
  var outName: AnsiString; var outProcIdx: Integer);
var restp, nameTok, libTok: AnsiString; ci, procIdx: Integer;
    dummyNames: array[0..0] of AnsiString; dummyTypes: array[0..0] of TTypeKind;
begin
  restp := AsmTrim(restp0);
  if restp = '' then Error('asm:' + AsmIntToStr(lineNo) + ': "extern" needs a symbol name');
  ci := Pos(',', restp);
  if ci > 0 then
  begin
    nameTok := AsmTrim(Copy(restp, 1, ci - 1));
    libTok := AsmTrim(Copy(restp, ci + 1, Length(restp) - ci));
    if (Length(libTok) < 2) or (libTok[1] <> '"') or (libTok[Length(libTok)] <> '"') then
      Error('asm:' + AsmIntToStr(lineNo) + ': extern library name must be quoted, e.g. extern foo, "libfoo.so"');
    libTok := Copy(libTok, 2, Length(libTok) - 2);
  end
  else
  begin
    nameTok := restp;
    libTok := 'libc.so.6';
  end;
  if nameTok = '' then Error('asm:' + AsmIntToStr(lineNo) + ': "extern" needs a symbol name');
  procIdx := RegisterProc(nameTok, False, tyUnknown, 0, dummyNames, dummyTypes);
  Procs[procIdx].BodyAddr := -1;
  ProcExternal[procIdx] := True;
  ProcLibrary[procIdx] := InternStr(libTok);
  outName := nameTok;
  outProcIdx := procIdx;
end;

const
  ASM_FRONT_MAX_LABELS = 4096;
  ASM_FRONT_MAX_FIXUPS = 8192;
  SEC_TEXT = 0;
  SEC_DATA = 1;

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
  branchLabel, opRipLabel: AnsiString;
  curSection, dataBase: Integer;
  dataBuf: TAsmByteBuf;
  { label table + branch fixups (layer-2 symbolic resolution) }
  lblName: array[0..ASM_FRONT_MAX_LABELS-1] of AnsiString;
  lblOff:  array[0..ASM_FRONT_MAX_LABELS-1] of Integer;
  lblIsData: array[0..ASM_FRONT_MAX_LABELS-1] of Boolean;
  lblCount: Integer;
  fixPos:  array[0..ASM_FRONT_MAX_FIXUPS-1] of Integer;
  fixName: array[0..ASM_FRONT_MAX_FIXUPS-1] of AnsiString;
  fixLine: array[0..ASM_FRONT_MAX_FIXUPS-1] of Integer;
  fixCount: Integer;
  found: Boolean; rel: Int64; tgt: Integer;
  labelPart: AnsiString;
  { extern table + global entry-point override (layer-2 symbolic resolution
    reusing the compiler's existing dynamic-link machinery) }
  externName: TAsmExternNames;
  externProcIdx: TAsmExternProcs;
  externCount, externResolvedIdx, extIdx, j2: Integer;
  externParsedName: AnsiString;
  externParsedProcIdx: Integer;
  globalEntryName: AnsiString;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('asm frontend: x86-64 only (matches lib/asmcore coverage)');
  n := Length(Source);
  i := 1;
  lineNo := 0;
  emittedAny := False;
  lblCount := 0;
  fixCount := 0;
  curSection := SEC_TEXT;
  externCount := 0;
  globalEntryName := '';
  BufInit(dataBuf);

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
      if lblCount >= ASM_FRONT_MAX_LABELS then
        Error('asm:' + AsmIntToStr(lineNo) + ': too many labels');
      lblName[lblCount] := AsmLower(labelPart);
      lblIsData[lblCount] := (curSection = SEC_DATA);
      if curSection = SEC_DATA then lblOff[lblCount] := dataBuf.Len
      else lblOff[lblCount] := CodeLen;
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

    if mnem = 'section' then
    begin
      if AsmLower(restp) = '.text' then curSection := SEC_TEXT
      else if AsmLower(restp) = '.data' then curSection := SEC_DATA
      else Error('asm:' + AsmIntToStr(lineNo) + ': unsupported section "' + restp + '" (only .text/.data)');
      Continue;
    end;

    if mnem = 'extern' then
    begin
      if externCount >= ASM_FRONT_MAX_EXTERNS then
        Error('asm:' + AsmIntToStr(lineNo) + ': too many extern declarations');
      AsmParseExternLine(restp, lineNo, externParsedName, externParsedProcIdx);
      externName[externCount] := externParsedName;
      externProcIdx[externCount] := externParsedProcIdx;
      Inc(externCount);
      Continue;
    end;

    if mnem = 'global' then
    begin
      if restp = '' then Error('asm:' + AsmIntToStr(lineNo) + ': "global" needs a label name');
      if globalEntryName = '' then globalEntryName := AsmLower(AsmTrim(restp));
      Continue;
    end;

    if curSection = SEC_DATA then
    begin
      AsmParseDataLine(mnem, restp, lineNo, dataBuf);
      Continue;
    end;

    if (mnem = 'db') or (mnem = 'dw') or (mnem = 'dd') or (mnem = 'dq') then
      Error('asm:' + AsmIntToStr(lineNo) + ': "' + mnem + '" needs "section .data"');

    branchLabel := '';
    instr.Mnemonic := mnem;

    if AsmIsBranch(mnem) then
    begin
      { the single operand is a label target -> rel32 patch site, unless
        `call` names a declared `extern` symbol: that routes through the
        existing GOT-indirect dynamic-call machinery instead (no rel32 patch
        site at all, so it's handled and Continue'd before reaching the
        shared encode block below). }
      if restp = '' then
        Error('asm:' + AsmIntToStr(lineNo) + ': "' + mnem + '" needs a label target');
      if (mnem = 'call') and AsmExternLookup(AsmTrim(restp), externName, externProcIdx, externCount, externResolvedIdx) then
      begin
        extIdx := RegisterExternal(externResolvedIdx);
        EmitExternalIndirectCall(extIdx);
        emittedAny := True;
        Continue;
      end;
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
      begin
        AsmParseOperand(ops[k], lineNo, instr.Operands[k], opRipLabel);
        if opRipLabel <> '' then branchLabel := opRipLabel;
      end;
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
      if fixCount >= ASM_FRONT_MAX_FIXUPS then
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

  { exit epilogue: SYS_exit(rdi). mov eax,60 ; syscall. A program that runs off
    the end exits with whatever it left in rdi (programs may also exit via an
    explicit `syscall`). }
  EmitB($B8); EmitB($3C); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 60 }
  EmitB($0F); EmitB($05);                                       { syscall }

  { append the data section after code+epilogue (one contiguous loaded image,
    so rip-relative disp arithmetic below is valid) and turn each data
    label's dataBuf-local offset into its final absolute one. }
  dataBase := CodeLen;
  for i := 0 to lblCount - 1 do
    if lblIsData[i] then lblOff[i] := dataBase + lblOff[i];
  for k := 0 to dataBuf.Len - 1 do
    EmitB(dataBuf.Bytes[k]);

  { resolve fixups (branch rel32 + rip-relative disp32): same formula,
    target - (patchPos + 4), since both measure from the end of the patched
    field to the resolved address. }
  for k := 0 to fixCount - 1 do
  begin
    found := False; tgt := 0;
    for i := 0 to lblCount - 1 do
      if lblName[i] = fixName[k] then begin tgt := lblOff[i]; found := True; end;
    if not found then
    begin
      for j2 := 0 to externCount - 1 do
        if AsmLower(externName[j2]) = fixName[k] then
          Error('asm:' + AsmIntToStr(fixLine[k]) + ': "' + fixName[k] +
            '" is declared extern -- only "call" can reach it (jmp/jcc unsupported for external targets)');
      Error('asm:' + AsmIntToStr(fixLine[k]) + ': undefined label "' + fixName[k] + '"');
    end;
    rel := tgt - (fixPos[k] + 4);
    Patch32(fixPos[k], rel);
  end;

  { `global <label>`: override the ELF entry point (default = start of
    Code[]) with a chosen code label's offset. First `global` naming an
    actual code label wins; a program with none keeps the old default. }
  if globalEntryName <> '' then
  begin
    found := False; tgt := 0;
    for i := 0 to lblCount - 1 do
      if (not lblIsData[i]) and (lblName[i] = globalEntryName) then begin tgt := lblOff[i]; found := True; end;
    if not found then
      Error('asm: "global ' + globalEntryName + '" -- no code label with that name');
    AsmEntryOff := tgt;
  end;
end;
