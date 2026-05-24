{$mode objfpc}{$H+}
{ Pascal26 Compiler - Stage 2
  Adds: integer variables, arithmetic, if/while/for/repeat, writeln(int), inc/dec.
  Bootstrap: fpc }

program Pascal26;

uses SysUtils, BaseUnix;

const
  MAX_CODE   = 1048576;
  MAX_DATA   = 1048576;
  MAX_STRS   = 4096;
  MAX_FIXUPS = 16384;
  MAX_SYMS   = 4096;

  SYS_WRITE = 1;
  SYS_EXIT  = 60;
  STDOUT    = 1;

  LOAD_ADDR        = $400000;
  ELF_HEADER_SIZE  = 64;
  PROG_HEADER_SIZE = 56;
  CODE_OFFSET      = ELF_HEADER_SIZE + PROG_HEADER_SIZE;

  { Data section layout }
  INTBUF_OFFSET   = 0;   { 24 bytes: int-to-string workspace }
  INTBUF_SIZE     = 24;
  MINUS_OFFSET    = 24;  { 1 byte: '-' }
  NEWLINE_OFFSET  = 25;  { 1 byte: #10 }
  STR_INIT_OFFSET = 26;  { string literals start here }

type
  TTokenKind = (
    tkEOF, tkIdent, tkInteger, tkString,
    tkProgram, tkBegin, tkEnd, tkVar, tkConst, tkType,
    tkProcedure, tkFunction, tkUses, tkUnit,
    tkIf, tkThen, tkElse,
    tkWhile, tkDo, tkFor, tkTo, tkDownto, tkRepeat, tkUntil,
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
    Offset : Integer;
    Len    : Integer;
  end;

  TFixup = record
    CodePos : Integer;
    DataOff : Integer;
  end;

  TTypeKind = (tyUnknown, tyInteger, tyBoolean, tyChar);

  TSymbol = record
    Name     : AnsiString;
    TypeKind : TTypeKind;
    Offset   : Integer;  { rbp-relative, negative: -8, -16, ... }
  end;

var
  Source  : AnsiString;
  SrcPos  : Integer;
  SrcLine : Integer;
  CurTok  : TToken;

  Code    : array[0..MAX_CODE-1] of Byte;
  CodeLen : Integer;

  Data    : array[0..MAX_DATA-1] of Byte;
  DataLen : Integer;

  Strs     : array[0..MAX_STRS-1]  of TStrEntry;
  StrCount : Integer;

  Fixups   : array[0..MAX_FIXUPS-1] of TFixup;
  FixCount : Integer;

  Syms      : array[0..MAX_SYMS-1] of TSymbol;
  SymCount  : Integer;
  FrameSize : Integer;
  ProloguePatchPos : Integer;

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
        if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '*') then
        begin
          Inc(SrcPos, 2);
          while SrcPos+1 <= Length(Source) do
          begin
            if (Source[SrcPos] = '*') and (Source[SrcPos+1] = ')') then
              begin Inc(SrcPos, 2); Break; end;
            if Source[SrcPos] = #10 then Inc(SrcLine);
            Inc(SrcPos);
          end;
        end
        else Break;
      '/':
        if (SrcPos+1 <= Length(Source)) and (Source[SrcPos+1] = '/') then
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
var c: Char; s: AnsiString; n: Int64;
begin
  SkipSpace;
  CurTok.Line := SrcLine;
  CurTok.SVal := '';
  if SrcPos > Length(Source) then begin CurTok.Kind := tkEOF; Exit; end;
  c := Source[SrcPos];

  if c in ['a'..'z','A'..'Z','_'] then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and
          (Source[SrcPos] in ['a'..'z','A'..'Z','0'..'9','_']) do
      begin s := s + Source[SrcPos]; Inc(SrcPos); end;
    CurTok.Kind := Keyword(s); CurTok.SVal := s; Exit;
  end;

  if c in ['0'..'9'] then
  begin
    n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
      begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '$' then
  begin
    Inc(SrcPos); n := 0;
    while SrcPos <= Length(Source) do
    begin
      c := Source[SrcPos];
      if c in ['0'..'9'] then n := n*16 + (Ord(c)-48)
      else if c in ['a'..'f'] then n := n*16 + (Ord(c)-87)
      else if c in ['A'..'F'] then n := n*16 + (Ord(c)-55)
      else Break;
      Inc(SrcPos);
    end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '&' then
  begin
    Inc(SrcPos); n := 0;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'7']) do
      begin n := n*8 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
    CurTok.Kind := tkInteger; CurTok.IVal := n; Exit;
  end;

  if c = '''' then
  begin
    Inc(SrcPos); s := '';
    while SrcPos <= Length(Source) do
    begin
      if Source[SrcPos] = '''' then
      begin
        Inc(SrcPos);
        if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then
          begin s := s + ''''; Inc(SrcPos); end
        else Break;
      end
      else begin s := s + Source[SrcPos]; Inc(SrcPos); end;
    end;
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
  end;

  if c = '#' then
  begin
    s := '';
    while (SrcPos <= Length(Source)) and (Source[SrcPos] = '#') do
    begin
      Inc(SrcPos); n := 0;
      while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
        begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
      s := s + Chr(n);
    end;
    while (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') do
    begin
      Inc(SrcPos);
      while SrcPos <= Length(Source) do
      begin
        if Source[SrcPos] = '''' then
        begin
          Inc(SrcPos);
          if (SrcPos <= Length(Source)) and (Source[SrcPos] = '''') then
            begin s := s + ''''; Inc(SrcPos); end
          else Break;
        end
        else begin s := s + Source[SrcPos]; Inc(SrcPos); end;
      end;
    end;
    CurTok.Kind := tkString; CurTok.SVal := s; Exit;
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
    '.': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '.') then
           begin Inc(SrcPos); CurTok.Kind := tkDotDot; end
         else CurTok.Kind := tkDot;
    ':': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
           begin Inc(SrcPos); CurTok.Kind := tkAssign; end
         else CurTok.Kind := tkColon;
    '=': CurTok.Kind := tkEq;
    '<': if SrcPos <= Length(Source) then
           case Source[SrcPos] of
             '>': begin Inc(SrcPos); CurTok.Kind := tkNeq; end;
             '=': begin Inc(SrcPos); CurTok.Kind := tkLe;  end;
             else CurTok.Kind := tkLt;
           end
         else CurTok.Kind := tkLt;
    '>': if (SrcPos <= Length(Source)) and (Source[SrcPos] = '=') then
           begin Inc(SrcPos); CurTok.Kind := tkGe; end
         else CurTok.Kind := tkGt;
    else Error('unexpected character: ''' + c + '''');
  end;
end;

function Eat(k: TTokenKind): Boolean;
begin Result := CurTok.Kind = k; if Result then Next; end;

procedure Expect(k: TTokenKind; const name: AnsiString);
begin
  if CurTok.Kind <> k then
    Error('expected ' + name + ', got ''' + CurTok.SVal + '''');
  Next;
end;

{ ===== Emitter ===== }

procedure EmitB(b: Byte); inline;
begin
  if CodeLen >= MAX_CODE then Error('code overflow');
  Code[CodeLen] := b; Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(Byte(v         and $FF));
  EmitB(Byte((v shr 8)  and $FF));
  EmitB(Byte((v shr 16) and $FF));
  EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin EmitI32(v and $FFFFFFFF); EmitI32((v shr 32) and $FFFFFFFF); end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos]   := Byte(v         and $FF);
  Code[pos+1] := Byte((v shr 8)  and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF);
  Code[pos+3] := Byte((v shr 24) and $FF);
end;

{ REX.W + B8+r: mov reg, imm64 }
procedure MovRaxImm(v: Int64); begin EmitB($48); EmitB($B8); EmitI64(v); end;
procedure MovRbxImm(v: Int64); begin EmitB($48); EmitB($BB); EmitI64(v); end;
procedure MovRcxImm(v: Int64); begin EmitB($48); EmitB($B9); EmitI64(v); end;
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;

procedure EmitSyscall; begin EmitB($0F); EmitB($05); end;

procedure EmitDataRef(dataOff: Integer);
{ Emit 8-byte placeholder; record fixup to patch with data_base+dataOff }
begin
  if FixCount >= MAX_FIXUPS then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen;
  Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EmitI64(0);
end;

procedure EmitWriteSyscall(dataOff, len: Integer);
begin
  MovRaxImm(SYS_WRITE);
  MovRdiImm(STDOUT);
  EmitB($48); EmitB($BE); EmitDataRef(dataOff); { mov rsi, data_base+off }
  MovRdxImm(len);
  EmitSyscall;
end;

procedure EmitExit(code: Int64);
begin MovRaxImm(SYS_EXIT); MovRdiImm(code); EmitSyscall; end;

{ ===== String table ===== }

function InternStr(const s: AnsiString): Integer;
var i, j: Integer;
begin
  for i := 0 to StrCount-1 do
    if Strs[i].Text = s then begin Result := i; Exit; end;
  if StrCount >= MAX_STRS then Error('string table overflow');
  Strs[StrCount].Text   := s;
  Strs[StrCount].Offset := DataLen;
  Strs[StrCount].Len    := Length(s);
  for j := 1 to Length(s) do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := Ord(s[j]); Inc(DataLen);
  end;
  Result := StrCount; Inc(StrCount);
end;

{ ===== Symbol table ===== }

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := LowerCase(name);
  for i := 0 to SymCount-1 do
    if Syms[i].Name = lo then begin Result := i; Exit; end;
  Result := -1;
end;

function AllocVar(const name: AnsiString; tk: TTypeKind): Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Inc(FrameSize, 8);
  Syms[SymCount].Name     := LowerCase(name);
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].Offset   := -FrameSize;
  Result := SymCount; Inc(SymCount);
end;

function AllocTemp: Integer;
{ Anonymous compiler-generated temporary (e.g., for-loop limit) }
begin
  Result := AllocVar('', tyInteger);
end;

procedure EmitLoadVar(idx: Integer);
{ mov rax, [rbp + offset] (offset is negative) }
begin
  EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
end;

procedure EmitStoreVar(idx: Integer);
{ mov [rbp + offset], rax }
begin
  EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);
end;

{ ===== Stack frame ===== }

procedure EmitPrologue;
{ push rbp; mov rbp,rsp; sub rsp,<patched later> }
begin
  EmitB($55);                          { push rbp }
  EmitB($48); EmitB($89); EmitB($E5); { mov rbp, rsp }
  EmitB($48); EmitB($81); EmitB($EC); { sub rsp, imm32 }
  ProloguePatchPos := CodeLen;
  EmitI32(0);
end;

procedure PatchPrologue;
var aligned: Integer;
begin
  aligned := (FrameSize + 15) and (not 15);
  Patch32(ProloguePatchPos, aligned);
end;

{ ===== int-to-string + write ===== }

procedure EmitWriteInt;
{ Input: rax = integer value. Writes decimal representation to stdout. }
{ Clobbers: rax, rbx, rcx, rdx, rdi, rsi }
var jnsOff: Integer; loopStart: Integer;
begin
  { Handle sign: if rax < 0, negate and write '-' first }
  EmitB($48); EmitB($85); EmitB($C0);   { test rax, rax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);  { jns rel8 (patch below) }

  { Negative branch }
  EmitB($48); EmitB($F7); EmitB($D8);   { neg rax }
  EmitB($50);                            { push rax (save absolute value) }
  EmitWriteSyscall(MINUS_OFFSET, 1);     { write '-' }
  EmitB($58);                            { pop rax }

  { Patch jns to here }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));

  { Digit conversion loop:
    rcx = digit count; rbx = 10; rdi = end of temp buffer }
  EmitB($48); EmitB($31); EmitB($C9);   { xor rcx, rcx }
  MovRbxImm(10);
  EmitB($48); EmitB($BF);               { mov rdi, imm64 }
  EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE); { = one past end of temp buffer }

  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);   { xor rdx, rdx }
  EmitB($48); EmitB($F7); EmitB($F3);   { div rbx }
  EmitB($80); EmitB($C2); EmitB($30);   { add dl, '0' }
  EmitB($48); EmitB($FF); EmitB($CF);   { dec rdi }
  EmitB($88); EmitB($17);               { mov [rdi], dl }
  EmitB($48); EmitB($FF); EmitB($C1);   { inc rcx }
  EmitB($48); EmitB($85); EmitB($C0);   { test rax, rax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1))); { jnz loopStart }

  { rsi = rdi (start of digits); rdx = rcx (length) }
  EmitB($48); EmitB($89); EmitB($FE);   { mov rsi, rdi }
  EmitB($48); EmitB($89); EmitB($CA);   { mov rdx, rcx }
  MovRaxImm(SYS_WRITE);
  MovRdiImm(STDOUT);
  EmitSyscall;
end;

{ ===== Expression parser ===== }
{ Result always in rax. Binary ops: push left, eval right -> rcx, pop left -> rax, apply. }

procedure ParseExpr; forward;

procedure ParseFactor;
var si, idx: Integer;
begin
  case CurTok.Kind of
    tkInteger:
    begin
      MovRaxImm(CurTok.IVal); Next;
    end;
    tkTrue:  begin MovRaxImm(1); Next; end;
    tkFalse: begin MovRaxImm(0); Next; end;
    tkIdent:
    begin
      idx := FindSym(CurTok.SVal);
      if idx < 0 then Error('undefined identifier: ' + CurTok.SVal);
      EmitLoadVar(idx); Next;
    end;
    tkLParen:
    begin
      Next; ParseExpr; Expect(tkRParen, ')');
    end;
    tkMinus:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($F7); EmitB($D8); { neg rax }
    end;
    tkNot:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($83); EmitB($F0); EmitB($01); { xor rax, 1 }
    end;
    tkOrd:
    begin
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      { ord() = identity for integer/char }
    end;
    else Error('expected expression, got ''' + CurTok.SVal + '''');
  end;
end;

procedure ParseTerm;
var op: TTokenKind;
begin
  ParseFactor;
  while CurTok.Kind in [tkStar, tkDiv, tkMod, tkAnd] do
  begin
    op := CurTok.Kind; Next;
    EmitB($50);                           { push rax (left) }
    ParseFactor;
    EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax (right) }
    EmitB($58);                           { pop rax (left) }
    case op of
      tkStar: begin
        EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); { imul rax, rcx }
      end;
      tkDiv: begin
        EmitB($48); EmitB($99);           { cqo }
        EmitB($48); EmitB($F7); EmitB($F9); { idiv rcx }
      end;
      tkMod: begin
        EmitB($48); EmitB($99);           { cqo }
        EmitB($48); EmitB($F7); EmitB($F9); { idiv rcx }
        EmitB($48); EmitB($89); EmitB($D0); { mov rax, rdx (remainder) }
      end;
      tkAnd: begin
        EmitB($48); EmitB($21); EmitB($C8); { and rax, rcx }
      end;
    end;
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean;
begin
  neg := (CurTok.Kind = tkMinus);
  Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then begin EmitB($48); EmitB($F7); EmitB($D8); end; { neg rax }
  while CurTok.Kind in [tkPlus, tkMinus, tkOr] do
  begin
    op := CurTok.Kind; Next;
    EmitB($50);                           { push rax }
    ParseTerm;
    EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax }
    EmitB($58);                           { pop rax }
    case op of
      tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end; { add rax, rcx }
      tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end; { sub rax, rcx }
      tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end; { or rax, rcx }
    end;
  end;
end;

procedure ParseExpr;
var op: TTokenKind;
begin
  ParseSimpleExpr;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    op := CurTok.Kind; Next;
    EmitB($50);                           { push rax (left) }
    ParseSimpleExpr;
    EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax (right) }
    EmitB($58);                           { pop rax (left) }
    EmitB($48); EmitB($3B); EmitB($C1);  { cmp rax, rcx }
    case op of
      tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end; { sete  al }
      tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end; { setne al }
      tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end; { setl  al }
      tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end; { setle al }
      tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end; { setg  al }
      tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end; { setge al }
    end;
    EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
  end;
end;

{ ===== Statement parser ===== }

procedure ParseStatement; forward;

procedure ParseWriteArgs(newline: Boolean);
var si: Integer = 0;
begin
  if CurTok.Kind = tkLParen then
  begin
    Next;
    while CurTok.Kind <> tkRParen do
    begin
      if CurTok.Kind = tkString then
      begin
        si := InternStr(CurTok.SVal); Next;
        if Strs[si].Len > 0 then EmitWriteSyscall(Strs[si].Offset, Strs[si].Len);
      end
      else
      begin
        ParseExpr;
        EmitWriteInt;
      end;
      if not Eat(tkComma) then Break;
    end;
    Expect(tkRParen, ')');
  end;
  if newline then EmitWriteSyscall(NEWLINE_OFFSET, 1);
end;

procedure ParseIfStatement;
var elseJmp, thenJmp: Integer;
begin
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);    { test rax, rax }
  EmitB($0F); EmitB($84);                { jz rel32 (false -> else/end) }
  thenJmp := CodeLen; EmitI32(0);
  Expect(tkThen, 'then');
  ParseStatement;
  if CurTok.Kind = tkElse then
  begin
    EmitB($E9); elseJmp := CodeLen; EmitI32(0); { jmp past else }
    Patch32(thenJmp, CodeLen - (thenJmp + 4));
    Next; { consume 'else' }
    ParseStatement;
    Patch32(elseJmp, CodeLen - (elseJmp + 4));
  end
  else
    Patch32(thenJmp, CodeLen - (thenJmp + 4));
end;

procedure ParseWhileStatement;
var loopTop, condJmp: Integer;
begin
  loopTop := CodeLen;
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);    { test rax, rax }
  EmitB($0F); EmitB($84);                { jz exit }
  condJmp := CodeLen; EmitI32(0);
  Expect(tkDo, 'do');
  ParseStatement;
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4)); { jmp loopTop }
  Patch32(condJmp, CodeLen - (condJmp + 4));
end;

procedure ParseForStatement;
var varIdx, limitIdx: Integer;
    loopTop, exitJmp: Integer;
    down: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  varIdx := FindSym(CurTok.SVal);
  if varIdx < 0 then Error('for: undefined variable: ' + CurTok.SVal);
  Next;
  Expect(tkAssign, ':=');
  ParseExpr;
  EmitStoreVar(varIdx);              { i := start }

  down := CurTok.Kind = tkDownto;
  if down then Next else Expect(tkTo, 'to');

  ParseExpr;
  limitIdx := AllocTemp;            { allocate stack slot for limit }
  EmitStoreVar(limitIdx);           { limit := expr }

  loopTop := CodeLen;
  EmitLoadVar(varIdx);              { rax = i }
  { cmp rax, [rbp + limitOff] }
  EmitB($48); EmitB($3B); EmitB($85); EmitI32(Syms[limitIdx].Offset);
  { exit if i > limit (to) or i < limit (downto) }
  EmitB($0F);
  if down then EmitB($8C) else EmitB($8F); { jl / jg }
  exitJmp := CodeLen; EmitI32(0);

  Expect(tkDo, 'do');
  ParseStatement;

  { increment / decrement loop variable }
  EmitLoadVar(varIdx);
  if down then begin EmitB($48); EmitB($FF); EmitB($C8); end  { dec rax }
           else begin EmitB($48); EmitB($FF); EmitB($C0); end; { inc rax }
  EmitStoreVar(varIdx);
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4)); { jmp loopTop }
  Patch32(exitJmp, CodeLen - (exitJmp + 4));
end;

procedure ParseRepeatStatement;
var loopTop: Integer;
begin
  loopTop := CodeLen;
  while not (CurTok.Kind in [tkUntil, tkEOF]) do
    begin ParseStatement; Eat(tkSemicolon); end;
  Expect(tkUntil, 'until');
  ParseExpr;
  EmitB($48); EmitB($85); EmitB($C0);    { test rax, rax }
  EmitB($0F); EmitB($84);                { jz loopTop (loop again if false) }
  EmitI32(loopTop - (CodeLen + 4));
end;

procedure ParseBlock;
begin
  while not (CurTok.Kind in [tkEnd, tkEOF, tkUntil]) do
    begin ParseStatement; Eat(tkSemicolon); end;
end;

procedure ParseStatement;
var idx: Integer; name: AnsiString;
begin
  case CurTok.Kind of
    tkWriteln: begin Next; ParseWriteArgs(True);  end;
    tkWrite:   begin Next; ParseWriteArgs(False); end;

    tkHalt, tkExit:
    begin
      Next;
      if CurTok.Kind = tkLParen then
      begin
        Next;
        if CurTok.Kind = tkInteger then
          begin EmitExit(CurTok.IVal); Next; end
        else EmitExit(0);
        Expect(tkRParen, ')');
      end
      else EmitExit(0);
    end;

    tkInc, tkDec:
    begin
      name := LowerCase(CurTok.SVal); Next;
      Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('expected variable');
      idx := FindSym(CurTok.SVal);
      if idx < 0 then Error('undefined: ' + CurTok.SVal);
      Next;
      EmitLoadVar(idx);
      if Eat(tkComma) then
      begin
        EmitB($50); ParseExpr;           { push old val, get amount in rax }
        EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax (amount) }
        EmitB($58);                      { pop rax (var) }
        if name = 'inc' then
          begin EmitB($48); EmitB($01); EmitB($C8); end  { add rax, rcx }
        else
          begin EmitB($48); EmitB($29); EmitB($C8); end; { sub rax, rcx }
      end
      else
      begin
        if name = 'inc' then
          begin EmitB($48); EmitB($FF); EmitB($C0); end  { inc rax }
        else
          begin EmitB($48); EmitB($FF); EmitB($C8); end; { dec rax }
      end;
      EmitStoreVar(idx);
      Expect(tkRParen, ')');
    end;

    tkIf:     begin Next; ParseIfStatement;    end;
    tkWhile:  begin Next; ParseWhileStatement; end;
    tkFor:    begin Next; ParseForStatement;   end;
    tkRepeat: begin Next; ParseRepeatStatement; end;

    tkBegin:
    begin
      Next; ParseBlock; Expect(tkEnd, 'end');
    end;

    tkIdent:
    begin
      { Assignment: ident := expr }
      name := CurTok.SVal; Next;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        idx := FindSym(name);
        if idx < 0 then Error('undefined variable: ' + name);
        ParseExpr;
        EmitStoreVar(idx);
      end
      else
      begin
        { Unknown call/statement: skip to semicolon }
        while not (CurTok.Kind in
          [tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF]) do Next;
      end;
    end;

    tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF: { empty }  ;

    else
    begin
      while not (CurTok.Kind in
        [tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF]) do Next;
    end;
  end;
end;

{ ===== Declaration parsing ===== }

function ParseType: TTypeKind;
begin
  case CurTok.Kind of
    tkInteger_T, tkLongWord_T: Result := tyInteger;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    else Result := tyUnknown;
  end;
  Next;
end;

procedure ParseVarSection;
var
  names: array[0..63] of AnsiString;
  n: Integer; tk: TTypeKind; i: Integer;
begin
  Next; { consume 'var' }
  while CurTok.Kind = tkIdent do
  begin
    n := 0;
    repeat
      if CurTok.Kind <> tkIdent then Error('expected identifier');
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    { skip array/record qualifiers for stage 2 }
    while not (CurTok.Kind in [tkSemicolon, tkBegin, tkVar,
               tkConst, tkType, tkProcedure, tkFunction, tkEOF]) do
    begin
      tk := ParseType;
      if CurTok.Kind in [tkSemicolon, tkBegin, tkVar,
                         tkConst, tkType, tkProcedure, tkFunction, tkEOF] then Break;
    end;
    for i := 0 to n-1 do AllocVar(names[i], tk);
    Eat(tkSemicolon);
  end;
end;

procedure SkipSection;
begin
  Next;
  while not (CurTok.Kind in
    [tkBegin, tkVar, tkConst, tkType, tkProcedure, tkFunction, tkEOF]) do Next;
end;

procedure SkipSubroutine;
var depth: Integer;
begin
  while not (CurTok.Kind in [tkBegin, tkEOF]) do Next;
  if CurTok.Kind = tkEOF then Exit;
  Next; depth := 1;
  while (depth > 0) and (CurTok.Kind <> tkEOF) do
  begin
    case CurTok.Kind of
      tkBegin: Inc(depth);
      tkEnd:   begin Dec(depth); if depth = 0 then begin Next; Break; end; end;
    end;
    Next;
  end;
  Eat(tkSemicolon);
end;

procedure ParseProgram;
begin
  Expect(tkProgram, 'program');
  if CurTok.Kind <> tkIdent then Error('expected program name');
  Next;
  if CurTok.Kind = tkLParen then
    begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
  Eat(tkSemicolon);

  while CurTok.Kind in [tkUses, tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        while CurTok.Kind = tkIdent do begin Next; if not Eat(tkComma) then Break; end;
        Eat(tkSemicolon);
      end;
      tkVar: ParseVarSection;
      tkConst, tkType: SkipSection;
      tkProcedure, tkFunction: SkipSubroutine;
    end;

  EmitPrologue;      { push rbp; mov rbp,rsp; sub rsp, <patch> }

  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkDot);

  EmitExit(0);
  PatchPrologue;     { fill in actual frame size }
end;

{ ===== ELF writer ===== }

procedure PatchAddr(pos: Integer; addr: Int64);
begin
  Code[pos+0] := Byte(addr          and $FF);
  Code[pos+1] := Byte((addr shr  8) and $FF);
  Code[pos+2] := Byte((addr shr 16) and $FF);
  Code[pos+3] := Byte((addr shr 24) and $FF);
  Code[pos+4] := Byte((addr shr 32) and $FF);
  Code[pos+5] := Byte((addr shr 40) and $FF);
  Code[pos+6] := Byte((addr shr 48) and $FF);
  Code[pos+7] := Byte((addr shr 56) and $FF);
end;

procedure WriteU8(var f: File; v: Byte);  begin BlockWrite(f, v, 1); end;
procedure WriteU16(var f: File; v: Word);
var b: array[0..1] of Byte;
begin b[0]:=v and $FF; b[1]:=(v shr 8) and $FF; BlockWrite(f,b,2); end;
procedure WriteU32(var f: File; v: LongWord);
var b: array[0..3] of Byte;
begin b[0]:=v and $FF; b[1]:=(v shr 8) and $FF;
      b[2]:=(v shr 16) and $FF; b[3]:=(v shr 24) and $FF; BlockWrite(f,b,4); end;
procedure WriteU64(var f: File; v: Int64);
begin WriteU32(f,LongWord(v and $FFFFFFFF)); WriteU32(f,LongWord((v shr 32) and $FFFFFFFF)); end;

procedure WriteELF(const outPath: AnsiString);
var f: File; i: Integer; dataBase, entry, fsize, addr: Int64;
begin
  dataBase := LOAD_ADDR + CODE_OFFSET + CodeLen;
  entry    := LOAD_ADDR + CODE_OFFSET;
  fsize    := CODE_OFFSET + CodeLen + DataLen;

  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    PatchAddr(Fixups[i].CodePos, addr);
  end;

  Assign(f, outPath); Rewrite(f, 1);

  { ELF64 header }
  WriteU8(f,$7F); WriteU8(f,$45); WriteU8(f,$4C); WriteU8(f,$46); { magic }
  WriteU8(f,2); WriteU8(f,1); WriteU8(f,1); WriteU8(f,0);
  WriteU8(f,0); WriteU8(f,0); WriteU8(f,0); WriteU8(f,0);
  WriteU8(f,0); WriteU8(f,0); WriteU8(f,0); WriteU8(f,0);
  WriteU16(f,2); WriteU16(f,62); WriteU32(f,1);
  WriteU64(f,entry); WriteU64(f,64); WriteU64(f,0);
  WriteU32(f,0); WriteU16(f,64); WriteU16(f,56);
  WriteU16(f,1); WriteU16(f,64); WriteU16(f,0); WriteU16(f,0);

  { PT_LOAD program header — RWX: int-to-str writes into data section }
  { TODO: split into separate R+X text and R+W data segments }
  WriteU32(f,1); WriteU32(f,7);
  WriteU64(f,0); WriteU64(f,LOAD_ADDR); WriteU64(f,LOAD_ADDR);
  WriteU64(f,fsize); WriteU64(f,fsize); WriteU64(f,$200000);

  if CodeLen > 0 then BlockWrite(f, Code[0], CodeLen);
  if DataLen > 0 then BlockWrite(f, Data[0], DataLen);
  Close(f);
  FpChmod(outPath, &755);
end;

{ ===== Main ===== }

var inFile, outFile: AnsiString; tf: TextFile; line: AnsiString;
begin
  if ParamCount < 1 then
    begin WriteLn(StdErr,'usage: pascal26 <src.pas> [out]'); Halt(1); end;

  inFile  := ParamStr(1);
  outFile := ChangeFileExt(inFile, '');
  if ParamCount >= 2 then outFile := ParamStr(2);

  Source := '';
  Assign(tf, inFile); Reset(tf);
  while not EOF(tf) do begin ReadLn(tf, line); Source := Source + line + #10; end;
  Close(tf);

  SrcPos   := 1;
  SrcLine  := 1;
  CodeLen  := 0;
  DataLen  := STR_INIT_OFFSET;
  Data[MINUS_OFFSET]   := Ord('-');
  Data[NEWLINE_OFFSET] := 10;
  StrCount := 0;
  FixCount := 0;
  SymCount := 0;
  FrameSize := 0;

  Next;
  ParseProgram;
  WriteELF(outFile);

  WriteLn('ok: ', outFile, '  [code=', CodeLen, 'B  data=', DataLen,
          'B  vars=', SymCount, '  frame=', FrameSize, 'B]');
end.
