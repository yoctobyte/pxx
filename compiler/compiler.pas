{$mode objfpc}{$H+}
{ Pascal26 Compiler - Stage 1
  Self-hosting Pascal compiler targeting x86-64 Linux ELF64.
  Bootstrap: compile this file with fpc.
  No external libraries. No assembler. No linker.
  Generates ELF64 executables by emitting x64 machine code directly. }

program Pascal26;

uses
  SysUtils, BaseUnix;

const
  MAX_CODE   = 1048576;  { 1 MB code buffer }
  MAX_DATA   = 1048576;  { 1 MB data buffer }
  MAX_STRS   = 4096;
  MAX_FIXUPS = 16384;

  { Linux x86-64 syscall numbers }
  SYS_WRITE = 1;
  SYS_EXIT  = 60;
  STDOUT    = 1;

  { ELF64 layout constants }
  LOAD_ADDR        = $400000;
  ELF_HEADER_SIZE  = 64;
  PROG_HEADER_SIZE = 56;
  CODE_OFFSET      = ELF_HEADER_SIZE + PROG_HEADER_SIZE;  { 120 }

type
  TTokenKind = (
    tkEOF, tkIdent, tkInteger, tkString,
    tkProgram, tkBegin, tkEnd, tkVar, tkConst, tkType,
    tkProcedure, tkFunction, tkUses, tkUnit,
    tkIf, tkThen, tkElse,
    tkWhile, tkDo,
    tkFor, tkTo, tkDownto,
    tkRepeat, tkUntil,
    tkArray, tkOf, tkRecord,
    tkAnd, tkOr, tkNot, tkDiv, tkMod,
    tkTrue, tkFalse,
    tkWriteln, tkWrite, tkReadln, tkRead,
    tkHalt, tkInc, tkDec, tkLength, tkOrd, tkChr, tkExit,
    tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T, tkLongWord_T,
    tkAssign, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe,
    tkPlus, tkMinus, tkStar, tkSlash,
    tkLParen, tkRParen, tkLBrack, tkRBrack,
    tkSemicolon, tkColon, tkComma, tkDot, tkDotDot, tkAt, tkCaret
  );

  TToken = record
    Kind : TTokenKind;
    SVal : AnsiString;
    IVal : Int64;
    Line : Integer;
  end;

  TStrEntry = record
    Text   : AnsiString;
    Offset : Integer;  { byte offset in Data[] }
    Len    : Integer;
  end;

  TFixup = record
    CodePos : Integer;  { position in Code[] to patch (8 bytes LE) }
    DataOff : Integer;  { data section byte offset }
  end;

var
  Source   : AnsiString;
  SrcPos   : Integer;
  SrcLine  : Integer;

  CurTok   : TToken;

  Code     : array[0..MAX_CODE-1] of Byte;
  CodeLen  : Integer;

  { Data[0] = newline byte; strings follow }
  Data     : array[0..MAX_DATA-1] of Byte;
  DataLen  : Integer;

  Strs     : array[0..MAX_STRS-1] of TStrEntry;
  StrCount : Integer;

  Fixups   : array[0..MAX_FIXUPS-1] of TFixup;
  FixCount : Integer;

{ ===== Error ===== }

procedure Error(const msg: AnsiString);
begin
  WriteLn(StdErr, ParamStr(1), ':', SrcLine, ': error: ', msg);
  Halt(1);
end;

{ ===== Lexer ===== }

procedure SkipSpace;
begin
  while SrcPos <= Length(Source) do
    case Source[SrcPos] of
      ' ', #9, #13: Inc(SrcPos);
      #10: begin Inc(SrcLine); Inc(SrcPos); end;
      '{':
      begin
        Inc(SrcPos);
        while (SrcPos <= Length(Source)) and (Source[SrcPos] <> '}') do
        begin
          if Source[SrcPos] = #10 then Inc(SrcLine);
          Inc(SrcPos);
        end;
        if SrcPos <= Length(Source) then Inc(SrcPos);
      end;
      '(':
        if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] = '*') then
        begin
          Inc(SrcPos, 2);
          while SrcPos + 1 <= Length(Source) do
          begin
            if (Source[SrcPos] = '*') and (Source[SrcPos+1] = ')') then
              begin Inc(SrcPos, 2); Break; end;
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
        end
        else Break;
      '/':
        if (SrcPos + 1 <= Length(Source)) and (Source[SrcPos+1] = '/') then
          while (SrcPos <= Length(Source)) and (Source[SrcPos] <> #10) do
            Inc(SrcPos)
        else Break;
      else Break;
    end;
end;

function Keyword(const s: AnsiString): TTokenKind;
var lo: AnsiString;
begin
  lo := LowerCase(s);
  case lo of
    'program':   Result := tkProgram;
    'begin':     Result := tkBegin;
    'end':       Result := tkEnd;
    'var':       Result := tkVar;
    'const':     Result := tkConst;
    'type':      Result := tkType;
    'procedure': Result := tkProcedure;
    'function':  Result := tkFunction;
    'uses':      Result := tkUses;
    'unit':      Result := tkUnit;
    'if':        Result := tkIf;
    'then':      Result := tkThen;
    'else':      Result := tkElse;
    'while':     Result := tkWhile;
    'do':        Result := tkDo;
    'for':       Result := tkFor;
    'to':        Result := tkTo;
    'downto':    Result := tkDownto;
    'repeat':    Result := tkRepeat;
    'until':     Result := tkUntil;
    'array':     Result := tkArray;
    'of':        Result := tkOf;
    'record':    Result := tkRecord;
    'and':       Result := tkAnd;
    'or':        Result := tkOr;
    'not':       Result := tkNot;
    'div':       Result := tkDiv;
    'mod':       Result := tkMod;
    'true':      Result := tkTrue;
    'false':     Result := tkFalse;
    'writeln':   Result := tkWriteln;
    'write':     Result := tkWrite;
    'readln':    Result := tkReadln;
    'read':      Result := tkRead;
    'halt':      Result := tkHalt;
    'inc':       Result := tkInc;
    'dec':       Result := tkDec;
    'length':    Result := tkLength;
    'ord':       Result := tkOrd;
    'chr':       Result := tkChr;
    'exit':      Result := tkExit;
    'integer':   Result := tkInteger_T;
    'boolean':   Result := tkBoolean_T;
    'char':      Result := tkChar_T;
    'string':    Result := tkString_T;
    'real':      Result := tkReal_T;
    'longword':  Result := tkLongWord_T;
    else         Result := tkIdent;
  end;
end;

procedure Next;
var
  c: Char;
  s: AnsiString;
  n: Int64;
begin
  SkipSpace;
  CurTok.Line := SrcLine;
  CurTok.SVal := '';

  if SrcPos > Length(Source) then
    begin CurTok.Kind := tkEOF; Exit; end;

  c := Source[SrcPos];

  if c in ['a'..'z', 'A'..'Z', '_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
      begin s := s + Source[SrcPos]; Inc(SrcPos); end;
    CurTok.Kind := Keyword(s);
    CurTok.SVal := s;
    Exit;
  end;

  if c in ['0'..'9'] then
  begin
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  if c = '$' then  { hex literal }
  begin
    Inc(SrcPos);
    n := 0;
    while SrcPos <= Length(Source) do
    begin
      c := Source[SrcPos];
      if c in ['0'..'9'] then n := n * 16 + (Ord(c) - 48)
      else if c in ['a'..'f'] then n := n * 16 + (Ord(c) - 87)
      else if c in ['A'..'F'] then n := n * 16 + (Ord(c) - 55)
      else Break;
      Inc(SrcPos);
    end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  if c = '&' then  { octal literal }
  begin
    Inc(SrcPos);
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'7']) do
      begin n := n * 8 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger;
    CurTok.IVal := n;
    Exit;
  end;

  if c = '''' then  { string literal }
  begin
    Inc(SrcPos);
    s := '';
    while SrcPos <= Length(Source) do
    begin
      if Source[SrcPos] = '''' then
      begin
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then
          begin s := s + ''''; Inc(SrcPos); end
        else
          Break;
      end
      else if Source[SrcPos] = #10 then
        begin Error('unterminated string'); Break; end
      else
        begin s := s + Source[SrcPos]; Inc(SrcPos); end;
    end;
    CurTok.Kind := tkString;
    CurTok.SVal := s;
    Exit;
  end;

  Inc(SrcPos);
  case c of
    '+': CurTok.Kind := tkPlus;
    '-': CurTok.Kind := tkMinus;
    '*': CurTok.Kind := tkStar;
    '/': CurTok.Kind := tkSlash;
    '(': CurTok.Kind := tkLParen;
    ')': CurTok.Kind := tkRParen;
    '[': CurTok.Kind := tkLBrack;
    ']': CurTok.Kind := tkRBrack;
    ';': CurTok.Kind := tkSemicolon;
    ',': CurTok.Kind := tkComma;
    '@': CurTok.Kind := tkAt;
    '^': CurTok.Kind := tkCaret;
    '.':
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
        begin Inc(SrcPos); CurTok.Kind := tkDotDot; end
      else
        CurTok.Kind := tkDot;
    ':':
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
        begin Inc(SrcPos); CurTok.Kind := tkAssign; end
      else
        CurTok.Kind := tkColon;
    '=': CurTok.Kind := tkEq;
    '<':
      if SrcPos <= Length(Source) then
        case Source[SrcPos] of
          '>': begin Inc(SrcPos); CurTok.Kind := tkNeq; end;
          '=': begin Inc(SrcPos); CurTok.Kind := tkLe; end;
          else CurTok.Kind := tkLt;
        end
      else CurTok.Kind := tkLt;
    '>':
      if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
        begin Inc(SrcPos); CurTok.Kind := tkGe; end
      else
        CurTok.Kind := tkGt;
    '#':  { char literal e.g. #10 #65 }
    begin
      n := 0;
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
        begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
      CurTok.Kind := tkString;
      CurTok.SVal := Chr(n);
      { If followed by more #nn, concatenate }
      while (SrcPos <= Length(Source)) and (Source[SrcPos] = '#') do
      begin
        Inc(SrcPos);
        n := 0;
        while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
          begin n := n * 10 + (Ord(Source[SrcPos]) - 48); Inc(SrcPos); end;
        CurTok.SVal := CurTok.SVal + Chr(n);
      end;
      { If followed by string literal, concatenate }
      while (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') do
      begin
        Inc(SrcPos);
        while SrcPos <= Length(Source) do
        begin
          if Source[SrcPos] = '''' then
          begin
            Inc(SrcPos);
            if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then
              begin CurTok.SVal := CurTok.SVal + ''''; Inc(SrcPos); end
            else Break;
          end
          else
            begin CurTok.SVal := CurTok.SVal + Source[SrcPos]; Inc(SrcPos); end;
        end;
      end;
    end;
    else Error('unexpected character: ''' + c + '''');
  end;
end;

function Eat(k: TTokenKind): Boolean;
begin
  Result := CurTok.Kind = k;
  if Result then Next;
end;

procedure Expect(k: TTokenKind; const name: AnsiString);
begin
  if CurTok.Kind <> k then
    Error('expected ' + name + ', got ''' + CurTok.SVal + '''');
  Next;
end;

{ ===== Code emitter ===== }

procedure EmitB(b: Byte); inline;
begin
  if CodeLen >= MAX_CODE then Error('code buffer overflow');
  Code[CodeLen] := b;
  Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(Byte(v and $FF));
  EmitB(Byte((v shr  8) and $FF));
  EmitB(Byte((v shr 16) and $FF));
  EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin
  EmitI32(v and $FFFFFFFF);
  EmitI32((v shr 32) and $FFFFFFFF);
end;

{ REX.W + B8+rd: mov rax, imm64 }
procedure MovRaxImm(v: Int64); begin EmitB($48); EmitB($B8); EmitI64(v); end;
{ REX.W + BF: mov rdi, imm64 }
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;
{ REX.W + BE: mov rsi, imm64 }
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
{ REX.W + BA: mov rdx, imm64 }
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;

procedure EmitSyscall; begin EmitB($0F); EmitB($05); end;

{ Emit 8-byte data reference (to be patched); record fixup }
procedure EmitDataRef(dataOff: Integer);
begin
  if FixCount >= MAX_FIXUPS then Error('fixup table overflow');
  Fixups[FixCount].CodePos := CodeLen;
  Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EmitI64(0);
end;

{ Emit: write(stdout, &data[dataOff], len) }
procedure EmitWriteSyscall(dataOff, len: Integer);
begin
  MovRaxImm(SYS_WRITE);
  MovRdiImm(STDOUT);
  EmitB($48); EmitB($BE);   { mov rsi, imm64 — address patched later }
  EmitDataRef(dataOff);
  MovRdxImm(len);
  EmitSyscall;
end;

{ Emit: exit(code) }
procedure EmitExit(code: Int64);
begin
  MovRaxImm(SYS_EXIT);
  MovRdiImm(code);
  EmitSyscall;
end;

{ ===== String table ===== }

function InternStr(const s: AnsiString): Integer;
var i, j: Integer;
begin
  for i := 0 to StrCount - 1 do
    if Strs[i].Text = s then begin Result := i; Exit; end;

  if StrCount >= MAX_STRS then Error('string table overflow');
  Strs[StrCount].Text   := s;
  Strs[StrCount].Offset := DataLen;
  Strs[StrCount].Len    := Length(s);

  for j := 1 to Length(s) do
  begin
    if DataLen >= MAX_DATA then Error('data buffer overflow');
    Data[DataLen] := Ord(s[j]);
    Inc(DataLen);
  end;

  Result := StrCount;
  Inc(StrCount);
end;

{ ===== Parser ===== }
{ Stage 1: handles writeln/write with string literals, halt, exit.
  Unknown statements are skipped (tokens consumed until ';' or 'end'). }

procedure ParseStatement; forward;

procedure ParseWriteArgs(newline: Boolean);
var si: Integer;
begin
  if CurTok.Kind = tkLParen then
  begin
    Next;
    while CurTok.Kind <> tkRParen do
    begin
      if CurTok.Kind = tkString then
      begin
        si := InternStr(CurTok.SVal);
        Next;
        if Strs[si].Len > 0 then
          EmitWriteSyscall(Strs[si].Offset, Strs[si].Len);
      end
      else
        Error('stage 1: writeln/write supports string literals only; got ''' + CurTok.SVal + '''');
      if not Eat(tkComma) then Break;
    end;
    Expect(tkRParen, ')');
  end;
  if newline then
    EmitWriteSyscall(0, 1);  { data[0] = newline }
end;

procedure SkipToSemiOrEnd;
begin
  while not (CurTok.Kind in
    [tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF]) do
    Next;
end;

procedure ParseStatement;
begin
  case CurTok.Kind of
    tkWriteln: begin Next; ParseWriteArgs(True); end;
    tkWrite:   begin Next; ParseWriteArgs(False); end;

    tkHalt:
    begin
      Next;
      if CurTok.Kind = tkLParen then
      begin
        Next;
        if CurTok.Kind = tkInteger then
          begin EmitExit(CurTok.IVal); Next; end
        else
          EmitExit(0);
        Expect(tkRParen, ')');
      end
      else
        EmitExit(0);
    end;

    tkExit:
    begin
      Next;
      if CurTok.Kind = tkLParen then
      begin
        Next;
        if CurTok.Kind = tkInteger then
          begin EmitExit(CurTok.IVal); Next; end
        else
          EmitExit(0);
        Expect(tkRParen, ')');
      end
      { For exit inside program main block, emit exit(0).
        Inside procedures this would return — not supported in stage 1. }
      else
        EmitExit(0);
    end;

    tkBegin:
    begin
      Next;
      while not (CurTok.Kind in [tkEnd, tkEOF]) do
        begin ParseStatement; Eat(tkSemicolon); end;
      Expect(tkEnd, 'end');
    end;

    { Empty / end-of-block markers — don't consume }
    tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF: ;

    else SkipToSemiOrEnd;
  end;
end;

procedure SkipSection;
{ Skip a var/const/type section by consuming until we hit a known section
  start or 'begin'. Leaves the next keyword in CurTok. }
begin
  Next;  { consume the section keyword }
  while not (CurTok.Kind in
    [tkBegin, tkVar, tkConst, tkType, tkProcedure, tkFunction, tkEOF]) do
    Next;
end;

procedure SkipSubroutine;
{ Skip a procedure or function definition (including its body). }
var depth: Integer;
begin
  { consume 'procedure'/'function' + header tokens until 'begin' or ';' body }
  while not (CurTok.Kind in [tkBegin, tkEOF]) do Next;
  if CurTok.Kind = tkEOF then Exit;
  Next;  { consume 'begin' }
  depth := 1;
  while (depth > 0) and (CurTok.Kind <> tkEOF) do
  begin
    case CurTok.Kind of
      tkBegin:  Inc(depth);
      tkEnd:  begin Dec(depth); if depth = 0 then begin Next; Break; end; end;
    end;
    Next;
  end;
  Eat(tkSemicolon);
end;

procedure ParseProgram;
begin
  Expect(tkProgram, 'program');
  if CurTok.Kind <> tkIdent then Error('expected program name');
  Next;  { program name }
  if CurTok.Kind = tkLParen then  { program Foo(input, output) }
    begin
      Next;
      while CurTok.Kind <> tkRParen do Next;
      Next;
    end;
  Eat(tkSemicolon);

  { Optional header sections }
  while CurTok.Kind in [tkUses, tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        while CurTok.Kind = tkIdent do begin Next; if not Eat(tkComma) then Break; end;
        Eat(tkSemicolon);
      end;
      tkVar, tkConst, tkType: SkipSection;
      tkProcedure, tkFunction: SkipSubroutine;
    end;

  Expect(tkBegin, 'begin');

  while not (CurTok.Kind in [tkEnd, tkEOF]) do
    begin ParseStatement; Eat(tkSemicolon); end;

  Expect(tkEnd, 'end');
  Eat(tkDot);

  EmitExit(0);
end;

{ ===== ELF64 writer ===== }

procedure PatchAddr(pos: Integer; addr: Int64);
begin
  Code[pos+0] := Byte(addr         and $FF);
  Code[pos+1] := Byte((addr shr  8) and $FF);
  Code[pos+2] := Byte((addr shr 16) and $FF);
  Code[pos+3] := Byte((addr shr 24) and $FF);
  Code[pos+4] := Byte((addr shr 32) and $FF);
  Code[pos+5] := Byte((addr shr 40) and $FF);
  Code[pos+6] := Byte((addr shr 48) and $FF);
  Code[pos+7] := Byte((addr shr 56) and $FF);
end;

procedure WriteU8(var f: File; v: Byte);
begin BlockWrite(f, v, 1); end;

procedure WriteU16(var f: File; v: Word);
var b: array[0..1] of Byte;
begin
  b[0] := v and $FF; b[1] := (v shr 8) and $FF;
  BlockWrite(f, b, 2);
end;

procedure WriteU32(var f: File; v: LongWord);
var b: array[0..3] of Byte;
begin
  b[0] := v and $FF; b[1] := (v shr 8) and $FF;
  b[2] := (v shr 16) and $FF; b[3] := (v shr 24) and $FF;
  BlockWrite(f, b, 4);
end;

procedure WriteU64(var f: File; v: Int64);
begin
  WriteU32(f, LongWord(v and $FFFFFFFF));
  WriteU32(f, LongWord((v shr 32) and $FFFFFFFF));
end;

procedure WriteELF(const outPath: AnsiString);
var
  f: File;
  i: Integer;
  dataBase, entryPoint, fileSize, addr: Int64;
begin
  dataBase   := LOAD_ADDR + CODE_OFFSET + CodeLen;
  entryPoint := LOAD_ADDR + CODE_OFFSET;
  fileSize   := CODE_OFFSET + CodeLen + DataLen;

  { Apply fixups: patch mov-rsi immediate with actual data address }
  for i := 0 to FixCount - 1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    PatchAddr(Fixups[i].CodePos, addr);
  end;

  Assign(f, outPath);
  Rewrite(f, 1);

  { ELF64 header (64 bytes) }
  WriteU8(f, $7F); WriteU8(f, $45); WriteU8(f, $4C); WriteU8(f, $46);  { magic }
  WriteU8(f, 2);   { ELFCLASS64 }
  WriteU8(f, 1);   { ELFDATA2LSB little-endian }
  WriteU8(f, 1);   { EV_CURRENT }
  WriteU8(f, 0);   { ELFOSABI_NONE }
  WriteU8(f,0); WriteU8(f,0); WriteU8(f,0); WriteU8(f,0);
  WriteU8(f,0); WriteU8(f,0); WriteU8(f,0); WriteU8(f,0);  { 8 bytes padding }
  WriteU16(f, 2);   { e_type = ET_EXEC }
  WriteU16(f, 62);  { e_machine = EM_X86_64 }
  WriteU32(f, 1);   { e_version }
  WriteU64(f, entryPoint);  { e_entry }
  WriteU64(f, 64);  { e_phoff: program headers at byte 64 }
  WriteU64(f, 0);   { e_shoff: no section headers }
  WriteU32(f, 0);   { e_flags }
  WriteU16(f, 64);  { e_ehsize }
  WriteU16(f, 56);  { e_phentsize }
  WriteU16(f, 1);   { e_phnum }
  WriteU16(f, 64);  { e_shentsize }
  WriteU16(f, 0);   { e_shnum }
  WriteU16(f, 0);   { e_shstrndx }

  { PT_LOAD program header (56 bytes) }
  WriteU32(f, 1);   { p_type = PT_LOAD }
  WriteU32(f, 5);   { p_flags = PF_R|PF_X }
  WriteU64(f, 0);   { p_offset: load from start of file }
  WriteU64(f, LOAD_ADDR);  { p_vaddr }
  WriteU64(f, LOAD_ADDR);  { p_paddr }
  WriteU64(f, fileSize);   { p_filesz }
  WriteU64(f, fileSize);   { p_memsz }
  WriteU64(f, $200000);    { p_align }

  { Code }
  if CodeLen > 0 then BlockWrite(f, Code[0], CodeLen);

  { Data }
  if DataLen > 0 then BlockWrite(f, Data[0], DataLen);

  Close(f);

  FpChmod(outPath, &755);
end;

{ ===== Main ===== }

var
  inFile, outFile: AnsiString;
  tf: TextFile;
  line: AnsiString;
begin
  if ParamCount < 1 then
  begin
    WriteLn(StdErr, 'usage: pascal26 <source.pas> [output]');
    Halt(1);
  end;

  inFile := ParamStr(1);
  if ParamCount >= 2 then
    outFile := ParamStr(2)
  else
  begin
    outFile := inFile;
    if (Length(outFile) > 4) and
       (LowerCase(Copy(outFile, Length(outFile)-3, 4)) = '.pas') then
      SetLength(outFile, Length(outFile) - 4);
  end;

  { Read source }
  Source := '';
  Assign(tf, inFile);
  Reset(tf);
  while not EOF(tf) do
  begin
    ReadLn(tf, line);
    Source := Source + line + #10;
  end;
  Close(tf);

  { Initialize }
  SrcPos   := 1;
  SrcLine  := 1;
  CodeLen  := 0;
  DataLen  := 1;   { Data[0] = '\n' }
  Data[0]  := 10;
  StrCount := 0;
  FixCount := 0;

  Next;  { prime lexer }
  ParseProgram;
  WriteELF(outFile);

  WriteLn('ok: ', outFile, '  [code=', CodeLen, 'B  data=', DataLen, 'B]');
end.
