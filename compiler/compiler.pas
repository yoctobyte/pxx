{$mode objfpc}{$H+}
{ Pascal26 Compiler - Stage 3
  Adds: procedures/functions, global vars (BSS), constants, enum types, case. }

program Pascal26;

uses SysUtils, BaseUnix;

const
  MAX_CODE    = 1048576;
  MAX_DATA    = 1048576;
  MAX_STRS    = 4096;
  MAX_FIXUPS  = 65536;
  MAX_SYMS    = 8192;
  MAX_PROCS   = 512;
  MAX_CALLFIX = 4096;
  MAX_GLOBFIX = 8192;

  SYS_WRITE = 1;
  SYS_EXIT  = 60;
  STDOUT    = 1;

  LOAD_ADDR        = $400000;
  ELF_HEADER_SIZE  = 64;
  PROG_HEADER_SIZE = 56;
  CODE_OFFSET      = ELF_HEADER_SIZE + PROG_HEADER_SIZE;

  INTBUF_OFFSET   = 0;
  INTBUF_SIZE     = 24;
  MINUS_OFFSET    = 24;
  NEWLINE_OFFSET  = 25;
  STR_INIT_OFFSET = 26;

type
  TTokenKind = (
    tkEOF, tkIdent, tkInteger, tkString,
    tkProgram, tkBegin, tkEnd, tkVar, tkConst, tkType,
    tkProcedure, tkFunction, tkUses, tkUnit, tkForward,
    tkIf, tkThen, tkElse,
    tkWhile, tkDo, tkFor, tkTo, tkDownto, tkRepeat, tkUntil,
    tkCase, tkOf,
    tkArray, tkRecord,
    tkAnd, tkOr, tkNot, tkDiv, tkMod,
    tkTrue, tkFalse,
    tkWriteln, tkWrite, tkReadln, tkRead,
    tkHalt, tkInc, tkDec, tkLength, tkOrd, tkChr, tkExit,
    tkSysOpen, tkSysRead, tkSysWrite, tkSysClose, tkSysFchmod,
    tkArgCount, tkArgStr,
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

  TGlobFix = record
    CodePos : Integer;
    BSSoff  : Integer;
  end;

  TCallFix = record
    CodePos  : Integer;
    ProcIdx  : Integer;
  end;

  TTypeKind = (tyUnknown, tyInteger, tyBoolean, tyChar, tyString);
  TSymKind  = (skLocal, skGlobal, skParam, skConst);

  TSymbol = record
    Name     : AnsiString;
    TypeKind : TTypeKind;
    Kind     : TSymKind;
    Offset   : Integer;   { skLocal/skParam: rbp-relative; skGlobal: BSS offset }
    ConstVal : Int64;     { skConst }
    IsArray  : Boolean;
    ArrLen   : Integer;   { number of elements (IsArray=True) }
    ElemType : TTypeKind; { element type when IsArray }
  end;

  TParam = record
    Name    : AnsiString;
    TypeKind: TTypeKind;
    SymIdx  : Integer;
  end;

  TProc = record
    Name       : AnsiString;
    IsFunc     : Boolean;
    RetType    : TTypeKind;
    ParamCount : Integer;
    Params     : array[0..7] of TParam;
    BodyAddr   : Integer;   { -1 = forward declared }
    FramePatch : Integer;   { code position of sub rsp imm32 }
    RetSymIdx  : Integer;   { Syms[] index for return value; -1 if proc }
    ScopeBase  : Integer;   { Syms[] index at start of this proc's locals }
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

  BSSSize : Integer;

  Strs     : array[0..MAX_STRS-1]    of TStrEntry;
  StrCount : Integer;

  Fixups   : array[0..MAX_FIXUPS-1]  of TFixup;
  FixCount : Integer;

  GlobFix  : array[0..MAX_GLOBFIX-1] of TGlobFix;
  GlobFixCount : Integer;

  CallFix  : array[0..MAX_CALLFIX-1] of TCallFix;
  CallFixCount : Integer;

  Syms      : array[0..MAX_SYMS-1]  of TSymbol;
  SymCount  : Integer;
  FrameSize : Integer;

  Procs     : array[0..MAX_PROCS-1] of TProc;
  ProcCount : Integer;
  CurProc   : Integer;   { -1 = main }

  { Reserved BSS slot 0: initial rsp (for argv access) }
  BSS_INITIAL_RSP : Integer;  { always 0; set in ParseProgram init }

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
    'forward':   Result := tkForward;
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
    'case':      Result := tkCase;
    'of':        Result := tkOf;
    'array':     Result := tkArray;
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
    'sysopen':   Result := tkSysOpen;
    'sysread':   Result := tkSysRead;
    'syswrite':  Result := tkSysWrite;
    'sysclose':  Result := tkSysClose;
    'sysfchmod': Result := tkSysFchmod;
    'argcount':  Result := tkArgCount;
    'argstr':    Result := tkArgStr;
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
  CurTok.Line := SrcLine; CurTok.SVal := '';
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
  EmitB(Byte(v and $FF)); EmitB(Byte((v shr 8) and $FF));
  EmitB(Byte((v shr 16) and $FF)); EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin EmitI32(v and $FFFFFFFF); EmitI32((v shr 32) and $FFFFFFFF); end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos]   := Byte(v and $FF); Code[pos+1] := Byte((v shr 8) and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF); Code[pos+3] := Byte((v shr 24) and $FF);
end;

procedure MovRaxImm(v: Int64); begin EmitB($48); EmitB($B8); EmitI64(v); end;
procedure MovRbxImm(v: Int64); begin EmitB($48); EmitB($BB); EmitI64(v); end;
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;

procedure EmitSyscall; begin EmitB($0F); EmitB($05); end;

procedure EmitDataRef(dataOff: Integer);
begin
  if FixCount >= MAX_FIXUPS then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount); EmitI64(0);
end;

procedure EmitGlobRef(bssOff: Integer);
{ Emit 4-byte placeholder for absolute BSS address }
begin
  if GlobFixCount >= MAX_GLOBFIX then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount); EmitI32(0);
end;

procedure EmitWriteSyscall(dataOff, len: Integer);
begin
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT);
  EmitB($48); EmitB($BE); EmitDataRef(dataOff);
  MovRdxImm(len); EmitSyscall;
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
    begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := Ord(s[j]); Inc(DataLen); end;
  Result := StrCount; Inc(StrCount);
end;

{ ===== Symbol table ===== }

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := LowerCase(name);
  for i := SymCount-1 downto 0 do
    if Syms[i].Name = lo then begin Result := i; Exit; end;
  Result := -1;
end;

function AllocVar(const name: AnsiString; tk: TTypeKind): Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := LowerCase(name);
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  Syms[SymCount].ElemType := tyInteger;
  if CurProc < 0 then
  begin
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    if tk = tyString then Inc(BSSSize, 264)   { 8-byte length + 256-byte data }
    else Inc(BSSSize, 8);
  end
  else
  begin
    Inc(FrameSize, 8);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  Result := SymCount; Inc(SymCount);
end;

function AllocArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var elemSize, totalSize: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  elemSize := 1;
  if elemType in [tyInteger, tyBoolean] then elemSize := 8;
  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := LowerCase(name);
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  Syms[SymCount].ElemType := elemType;
  if CurProc < 0 then
  begin
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, totalSize);
  end
  else Error('local arrays not yet supported');
  Result := SymCount; Inc(SymCount);
end;

function AllocTemp: Integer;
begin Result := AllocVar('', tyInteger); end;

function AddConst(const name: AnsiString; tk: TTypeKind; v: Int64): Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := LowerCase(name);
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].Kind     := skConst;
  Syms[SymCount].ConstVal := v;
  Syms[SymCount].Offset   := 0;
  Result := SymCount; Inc(SymCount);
end;

{ ===== Variable load/store ===== }

procedure EmitLoadVar(idx: Integer);
begin
  case Syms[idx].Kind of
    skLocal, skParam:
      begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
    skGlobal:
      begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    skConst:
      MovRaxImm(Syms[idx].ConstVal);
  end;
end;

procedure EmitStoreVar(idx: Integer);
begin
  case Syms[idx].Kind of
    skLocal, skParam:
      begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
    skGlobal:
      begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    skConst: Error('cannot assign to constant');
  end;
end;

procedure EmitCmpRaxVar(idx: Integer);
{ cmp rax, var }
begin
  case Syms[idx].Kind of
    skLocal, skParam:
      begin EmitB($48); EmitB($3B); EmitB($85); EmitI32(Syms[idx].Offset); end;
    skGlobal:
      begin EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    skConst:
      begin
        { cmp rax, imm32 }
        EmitB($48); EmitB($3D); EmitI32(Syms[idx].ConstVal);
      end;
  end;
end;

{ ===== String helpers ===== }

procedure EmitWriteStrVar(idx: Integer);
{ sys_write the string variable at Syms[idx] (global only) }
begin
  { mov rdx, [bss+Offset] -- length }
  EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(Syms[idx].Offset);
  { lea rsi, [bss+Offset+8] -- data ptr }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8);
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitStrAssignLiteral(dstIdx, litOff, litLen: Integer);
{ s := 'literal': store length, rep movsb the literal bytes }
begin
  { Store length into [bss+Offset] }
  MovRaxImm(litLen);
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[dstIdx].Offset);
  if litLen > 0 then
  begin
    { mov rcx, litLen }
    EmitB($48); EmitB($B9); EmitI64(litLen);
    { lea rdi, [bss+Offset+8] }
    EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[dstIdx].Offset + 8);
    { mov rsi, data_addr (literal bytes in data section) }
    EmitB($48); EmitB($BE); EmitDataRef(litOff);
    { rep movsb }
    EmitB($F3); EmitB($A4);
  end;
end;

procedure EmitStrAssignVar(dstIdx, srcIdx: Integer);
{ s := t: copy length then rep movsb the data }
begin
  { rax = src length }
  EmitLoadVar(srcIdx);
  { store length to dst }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[dstIdx].Offset);
  { rcx = length (for rep) }
  EmitB($48); EmitB($89); EmitB($C1);   { mov rcx, rax }
  { lea rdi, [bss+dst.Offset+8] }
  EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[dstIdx].Offset + 8);
  { lea rsi, [bss+src.Offset+8] }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[srcIdx].Offset + 8);
  { rep movsb }
  EmitB($F3); EmitB($A4);
end;

procedure EmitStrCmp(aIdx, bIdx: Integer; eq: Boolean);
{ rax = 1 if (a=b), 0 otherwise.  eq=False → rax = 1 if (a<>b). }
var skipJmp, okJmp: Integer;
begin
  { Compare lengths first }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[bIdx].Offset);
  { jne → not equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);
  { Lengths equal — compare bytes; rcx = length }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($89); EmitB($C1);
  { lea rdi, [a_data] }
  EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[aIdx].Offset + 8);
  { lea rsi, [b_data] }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[bIdx].Offset + 8);
  { repe cmpsb }
  EmitB($F3); EmitB($A6);
  { je → bytes equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);
  { Not equal }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);
  Patch32(okJmp, CodeLen - (okJmp + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

{ ===== Array element access ===== }

procedure EmitArrElemAddr(arrIdx: Integer);
{ On entry: rax = array index. On exit: rax = element address. }
var elemSize: Integer;
begin
  elemSize := 1;
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean] then elemSize := 8;
  if elemSize > 1 then
  begin
    { shl rax, 3  (multiply by 8) }
    EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);
  end;
  { Subtract lower bound * elemSize (if non-zero) }
  if (Syms[arrIdx].ConstVal <> 0) and (elemSize > 1) then
  begin
    EmitB($48); EmitB($2D); EmitI32(Syms[arrIdx].ConstVal * elemSize);
  end;
  { add eax, bss_arr_base  (32-bit add, zero-extends to rax) }
  EmitB($05); EmitGlobRef(Syms[arrIdx].Offset);
end;

procedure EmitArrLoad(arrIdx: Integer);
{ rax = index → rax = element value }
begin
  EmitArrElemAddr(arrIdx);
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean] then
    begin EmitB($48); EmitB($8B); EmitB($00); end  { mov rax, [rax] }
  else
    begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end; { movzx rax, byte [rax] }
end;

procedure EmitArrStore(arrIdx: Integer);
{ Stack: [..., addr]. rax = value. Store value at addr. }
begin
  { addr was pushed before RHS eval }
  EmitB($59);                   { pop rcx -- element address }
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean] then
    begin EmitB($48); EmitB($89); EmitB($01); end  { mov [rcx], rax }
  else
    begin EmitB($88); EmitB($01); end;              { mov [rcx], al }
end;

{ ===== Procedure table ===== }

function FindProc(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := LowerCase(name);
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = lo then begin Result := i; Exit; end;
  Result := -1;
end;

function RegisterProc(const name: AnsiString; isFunc: Boolean;
  retType: TTypeKind; nParams: Integer;
  const pnames: array of AnsiString; const ptypes: array of TTypeKind;
  bodyAddr: Integer): Integer;
var i: Integer;
begin
  if ProcCount >= MAX_PROCS then Error('too many procedures');
  Procs[ProcCount].Name       := LowerCase(name);
  Procs[ProcCount].IsFunc     := isFunc;
  Procs[ProcCount].RetType    := retType;
  Procs[ProcCount].ParamCount := nParams;
  Procs[ProcCount].BodyAddr   := bodyAddr;
  Procs[ProcCount].FramePatch := -1;
  Procs[ProcCount].RetSymIdx  := -1;
  Procs[ProcCount].ScopeBase  := 0;
  for i := 0 to nParams-1 do
  begin
    Procs[ProcCount].Params[i].Name     := LowerCase(pnames[i]);
    Procs[ProcCount].Params[i].TypeKind := ptypes[i];
    Procs[ProcCount].Params[i].SymIdx   := -1;
  end;
  Result := ProcCount; Inc(ProcCount);
end;

{ ===== int-to-string write ===== }

procedure EmitWriteInt;
var jnsOff, loopStart: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($79); jnsOff := CodeLen; EmitB(0);
  EmitB($48); EmitB($F7); EmitB($D8);
  EmitB($50);
  EmitWriteSyscall(MINUS_OFFSET, 1);
  EmitB($58);
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($48); EmitB($31); EmitB($C9);
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);
  EmitB($48); EmitB($F7); EmitB($F3);
  EmitB($80); EmitB($C2); EmitB($30);
  EmitB($48); EmitB($FF); EmitB($CF);
  EmitB($88); EmitB($17);
  EmitB($48); EmitB($FF); EmitB($C1);
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));
  EmitB($48); EmitB($89); EmitB($FE);
  EmitB($48); EmitB($89); EmitB($CA);
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitWriteChar;
{ rax = char byte value → write 1 byte to stdout }
begin
  { Store byte to INTBUF[0] in data section }
  EmitB($48); EmitB($BE); EmitDataRef(INTBUF_OFFSET);  { mov rsi, &intbuf }
  EmitB($88); EmitB($06);                               { mov [rsi], al }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); MovRdxImm(1); EmitSyscall;
end;

{ ===== Prologue/Epilogue ===== }

function EmitProcPrologue: Integer;
{ Returns patch position for sub rsp imm32 }
begin
  EmitB($55);
  EmitB($48); EmitB($89); EmitB($E5);
  EmitB($48); EmitB($81); EmitB($EC);
  Result := CodeLen; EmitI32(0);
end;

procedure PatchProcPrologue(patchPos, size: Integer);
var aligned: Integer;
begin
  aligned := (size + 15) and (not 15);
  Patch32(patchPos, aligned);
end;

procedure EmitProcEpilog(retSymIdx: Integer);
begin
  if retSymIdx >= 0 then
  begin
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset);
  end;
  EmitB($C9); EmitB($C3);
end;

{ ===== Call emission ===== }

procedure EmitCallProc(pi: Integer);
begin
  EmitB($E8);
  if Procs[pi].BodyAddr >= 0 then
    EmitI32(Procs[pi].BodyAddr - (CodeLen + 4))
  else
  begin
    if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
    CallFix[CallFixCount].CodePos := CodeLen;
    CallFix[CallFixCount].ProcIdx := pi;
    Inc(CallFixCount);
    EmitI32(0);
  end;
end;

procedure ApplyCallFixups;
var i, pi: Integer;
begin
  for i := 0 to CallFixCount-1 do
  begin
    pi := CallFix[i].ProcIdx;
    if Procs[pi].BodyAddr < 0 then
      Error('unresolved forward: ' + Procs[pi].Name);
    Patch32(CallFix[i].CodePos, Procs[pi].BodyAddr - (CallFix[i].CodePos + 4));
  end;
end;

{ ===== Expression parser ===== }

procedure ParseExpr; forward;

procedure ParseFactor;
var name: AnsiString; idx, pi, i: Integer;
begin
  case CurTok.Kind of
    tkInteger: begin MovRaxImm(CurTok.IVal); Next; end;
    tkTrue:    begin MovRaxImm(1); Next; end;
    tkFalse:   begin MovRaxImm(0); Next; end;
    tkString:
    begin
      { Single-char literal → ordinal value }
      if Length(CurTok.SVal) = 1 then begin MovRaxImm(Ord(CurTok.SVal[1])); Next; end
      else Error('string literal not valid in expression (use writeln)');
    end;
    tkLParen:  begin Next; ParseExpr; Expect(tkRParen, ')'); end;
    tkMinus:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($F7); EmitB($D8);
    end;
    tkNot:
    begin
      Next; ParseFactor;
      EmitB($48); EmitB($83); EmitB($F0); EmitB($01);
    end;
    tkOrd:
    begin
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
    end;
    tkLength:
    begin
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('Length: expected string variable');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then
        Error('Length: not a string variable');
      EmitLoadVar(idx);   { loads int64 length from BSS[Offset] }
      Next; Expect(tkRParen, ')');
    end;
    tkSysOpen:
    begin
      { SysOpen(path_str_var, flags): Integer = fd }
      Next; Expect(tkLParen, '(');
      if CurTok.Kind <> tkIdent then Error('SysOpen: expected string var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('SysOpen: not a string var');
      { lea rdi, [bss+str.Offset+8] (path data, NUL-terminated) }
      EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8);
      Next; Expect(tkComma, ',');
      ParseExpr;   { flags → rax }
      EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax }
      MovRaxImm(0); EmitB($48); EmitB($89); EmitB($C2); { rdx=0 (mode ignored for open) }
      MovRaxImm(2); EmitSyscall;                         { SYS_OPEN=2 }
      Expect(tkRParen, ')');
    end;
    tkSysRead:
    begin
      { SysRead(fd, buf_array, maxn): Integer = bytes read }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);     { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('SysRead: expected array var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or not Syms[idx].IsArray then Error('SysRead: not an array var');
      { lea rsi, [bss+arr.Offset] }
      EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      Next; Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C2);     { mov rdx, rax (count) }
      MovRaxImm(0); EmitSyscall;                          { SYS_READ=0 }
      Expect(tkRParen, ')');
    end;
    tkSysWrite:
    begin
      { SysWrite(fd, buf_array, n): Integer = bytes written }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);     { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      if CurTok.Kind <> tkIdent then Error('SysWrite: expected array var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or not Syms[idx].IsArray then Error('SysWrite: not an array var');
      { lea rsi, [bss+arr.Offset] }
      EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      Next; Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C2);     { mov rdx, rax (count) }
      MovRaxImm(1); EmitSyscall;                          { SYS_WRITE=1 }
      Expect(tkRParen, ')');
    end;
    tkArgCount:
    begin
      { ArgCount(): Integer = argc }
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      { mov rax, [bss_initial_rsp]; load argc from [initial_rsp] }
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
      EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] }
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      idx  := FindSym(name);
      pi   := FindProc(name);
      if (idx >= 0) and (Syms[idx].Kind = skConst) then
      begin
        MovRaxImm(Syms[idx].ConstVal); Next;
      end
      else if (pi >= 0) and Procs[pi].IsFunc then
      begin
        { Function call in expression }
        Next;
        { Push args left to right }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          for i := 0 to Procs[pi].ParamCount-1 do
          begin
            ParseExpr; EmitB($50);
            if i < Procs[pi].ParamCount-1 then Expect(tkComma, ',');
          end;
          Expect(tkRParen, ')');
        end;
        { Pop into registers right to left }
        for i := Procs[pi].ParamCount-1 downto 0 do
          case i of
            0: EmitB($5F);
            1: EmitB($5E);
            2: EmitB($5A);
            3: EmitB($59);
            4: begin EmitB($41); EmitB($58); end;
            5: begin EmitB($41); EmitB($59); end;
          end;
        EmitCallProc(pi);
        { rax = return value }
      end
      else if (idx >= 0) and Syms[idx].IsArray then
      begin
        Next;
        { arr[index] load }
        Expect(tkLBrack, '[');
        ParseExpr;        { index in rax }
        Expect(tkRBrack, ']');
        EmitArrLoad(idx);
      end
      else if idx >= 0 then
      begin
        EmitLoadVar(idx); Next;
      end
      else
        Error('undefined: ' + name);
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
    EmitB($50);
    ParseFactor;
    EmitB($48); EmitB($89); EmitB($C1);
    EmitB($58);
    case op of
      tkStar: begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end;
      tkDiv:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
      tkMod:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9);
                    EmitB($48); EmitB($89); EmitB($D0); end;
      tkAnd:  begin EmitB($48); EmitB($21); EmitB($C8); end;
    end;
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean;
begin
  neg := CurTok.Kind = tkMinus; Eat(tkMinus); Eat(tkPlus);
  ParseTerm;
  if neg then begin EmitB($48); EmitB($F7); EmitB($D8); end;
  while CurTok.Kind in [tkPlus, tkMinus, tkOr] do
  begin
    op := CurTok.Kind; Next; EmitB($50); ParseTerm;
    EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
    case op of
      tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end;
      tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end;
      tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end;
    end;
  end;
end;

procedure ParseExpr;
var op: TTokenKind;
begin
  ParseSimpleExpr;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    op := CurTok.Kind; Next; EmitB($50); ParseSimpleExpr;
    EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
    EmitB($48); EmitB($3B); EmitB($C1);
    case op of
      tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
      tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
      tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end;
      tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end;
      tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end;
      tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end;
    end;
    EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);
  end;
end;

function ConstEval: Int64;
{ Evaluate a compile-time constant expression (no code emitted) }
var r, v: Int64; idx: Integer; op: TTokenKind;
begin
  r := 0;
  if CurTok.Kind = tkInteger then begin r := CurTok.IVal; Next; end
  else if CurTok.Kind = tkMinus then begin Next; r := -ConstEval; end
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
      r := Syms[idx].ConstVal
    else Error('not a constant: ' + CurTok.SVal);
    Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEval; Expect(tkRParen, ')');
  end;
  while CurTok.Kind in [tkPlus, tkMinus, tkStar, tkDiv] do
  begin
    op := CurTok.Kind; Next; v := ConstEval;
    case op of
      tkPlus:  r := r + v;
      tkMinus: r := r - v;
      tkStar:  r := r * v;
      tkDiv:   r := r div v;
    end;
  end;
  Result := r;
end;

{ ===== Statement parser ===== }

procedure ParseStatement; forward;

procedure ParseWriteArgs(newline: Boolean);
var si, vidx: Integer;
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
      else if CurTok.Kind = tkIdent then
      begin
        vidx := FindSym(CurTok.SVal);
        if (vidx >= 0) and (Syms[vidx].TypeKind = tyString) and (Syms[vidx].Kind = skGlobal) then
        begin
          EmitWriteStrVar(vidx); Next;
        end
        else if (vidx >= 0) and Syms[vidx].IsArray and (Syms[vidx].ElemType = tyChar) then
        begin
          { char array element: writeln(arr[i]) writes as character }
          ParseExpr;
          EmitWriteChar;
        end
        else begin ParseExpr; EmitWriteInt; end;
      end
      else begin ParseExpr; EmitWriteInt; end;
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
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); thenJmp := CodeLen; EmitI32(0);
  Expect(tkThen, 'then');
  ParseStatement;
  if CurTok.Kind = tkElse then
  begin
    EmitB($E9); elseJmp := CodeLen; EmitI32(0);
    Patch32(thenJmp, CodeLen - (thenJmp + 4));
    Next; ParseStatement;
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
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); condJmp := CodeLen; EmitI32(0);
  Expect(tkDo, 'do');
  ParseStatement;
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
  Patch32(condJmp, CodeLen - (condJmp + 4));
end;

procedure ParseForStatement;
var varIdx, limitIdx, loopTop, exitJmp: Integer; down: Boolean;
begin
  if CurTok.Kind <> tkIdent then Error('for: expected variable');
  varIdx := FindSym(CurTok.SVal);
  if varIdx < 0 then Error('for: undefined: ' + CurTok.SVal);
  Next;
  Expect(tkAssign, ':=');
  ParseExpr; EmitStoreVar(varIdx);
  down := CurTok.Kind = tkDownto;
  if down then Next else Expect(tkTo, 'to');
  ParseExpr;
  limitIdx := AllocTemp; EmitStoreVar(limitIdx);
  loopTop := CodeLen;
  EmitLoadVar(varIdx);
  EmitCmpRaxVar(limitIdx);
  EmitB($0F); if down then EmitB($8C) else EmitB($8F);
  exitJmp := CodeLen; EmitI32(0);
  Expect(tkDo, 'do');
  ParseStatement;
  EmitLoadVar(varIdx);
  if down then begin EmitB($48); EmitB($FF); EmitB($C8); end
           else begin EmitB($48); EmitB($FF); EmitB($C0); end;
  EmitStoreVar(varIdx);
  EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
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
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($0F); EmitB($84); EmitI32(loopTop - (CodeLen + 4));
end;

procedure ParseCaseStatement;
{ case expr of val1,val2: stmt; ... else stmt; end }
const MAX_BRANCHES = 64;
var
  jePositions : array[0..MAX_BRANCHES-1] of Integer;
  jeCount     : Integer;
  jmpPositions: array[0..MAX_BRANCHES-1] of Integer;
  jmpCount    : Integer;
  elseJmp, i, branchJeStart, si: Integer;
  hasElse     : Boolean;
  cv          : Int64;
begin
  { Save expression in rcx (rax gets clobbered by comparisons) }
  ParseExpr;
  EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax }

  Expect(tkOf, 'of');
  jeCount  := 0;
  jmpCount := 0;
  hasElse  := False;

  while not (CurTok.Kind in [tkEnd, tkEOF]) do
  begin
    if CurTok.Kind = tkElse then
    begin
      hasElse := True;
      Next;
      ParseStatement;
      Eat(tkSemicolon);
      Break;
    end;

    { Collect label values and emit comparisons }
    branchJeStart := jeCount;
    repeat
      { Parse label value }
      if CurTok.Kind = tkInteger then cv := CurTok.IVal
      else if CurTok.Kind = tkIdent then
      begin
        si := FindSym(CurTok.SVal);
        if (si >= 0) and (Syms[si].Kind = skConst) then cv := Syms[si].ConstVal
        else Error('case label must be constant: ' + CurTok.SVal);
      end
      else Error('expected case label');
      Next;
      { cmp rcx, imm32; je (forward) }
      EmitB($48); EmitB($81); EmitB($F9); EmitI32(cv); { cmp rcx, imm32 }
      EmitB($0F); EmitB($84);
      if jeCount >= MAX_BRANCHES then Error('too many case branches');
      jePositions[jeCount] := CodeLen; Inc(jeCount);
      EmitI32(0);
    until not Eat(tkComma);
    Expect(tkColon, ':');

    { This branch's code starts here: patch all its je targets }
    for i := branchJeStart to jeCount-1 do
      Patch32(jePositions[i], CodeLen - (jePositions[i] + 4));

    ParseStatement;
    Eat(tkSemicolon);

    { jmp end_case }
    EmitB($E9);
    if jmpCount >= MAX_BRANCHES then Error('too many case branches');
    jmpPositions[jmpCount] := CodeLen; Inc(jmpCount);
    EmitI32(0);
  end;

  if not hasElse then
  begin
    { Patch unmatched case: skip to end }
  end;

  Expect(tkEnd, 'end');

  { Patch all jmp end_case to here }
  for i := 0 to jmpCount-1 do
    Patch32(jmpPositions[i], CodeLen - (jmpPositions[i] + 4));
end;

procedure ParseBlock;
begin
  while not (CurTok.Kind in [tkEnd, tkEOF, tkUntil]) do
    begin ParseStatement; Eat(tkSemicolon); end;
end;

procedure ParseStatement;
var name: AnsiString; idx, pi, i, si, si2: Integer;
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
        if CurTok.Kind = tkInteger then begin EmitExit(CurTok.IVal); Next; end
        else EmitExit(0);
        Expect(tkRParen, ')');
      end
      else if CurTok.Kind = tkSemicolon then
      begin
        { exit from function: emit epilogue }
        if CurProc >= 0 then EmitProcEpilog(Procs[CurProc].RetSymIdx)
        else EmitExit(0);
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
        EmitB($50); ParseExpr;
        EmitB($48); EmitB($89); EmitB($C1); EmitB($58);
        if name = 'inc' then begin EmitB($48); EmitB($01); EmitB($C8); end
        else begin EmitB($48); EmitB($29); EmitB($C8); end;
      end
      else
      begin
        if name = 'inc' then begin EmitB($48); EmitB($FF); EmitB($C0); end
        else begin EmitB($48); EmitB($FF); EmitB($C8); end;
      end;
      EmitStoreVar(idx);
      Expect(tkRParen, ')');
    end;

    { ---- File I/O and argv builtins ---- }
    tkSysClose:
    begin
      { SysClose(fd) }
      Next; Expect(tkLParen, '(');
      ParseExpr;  { fd → rax }
      EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax }
      MovRaxImm(3); EmitSyscall;             { SYS_CLOSE=3 }
      Expect(tkRParen, ')');
    end;
    tkSysFchmod:
    begin
      { SysFchmod(fd, mode): SYS_FCHMOD=91 }
      Next; Expect(tkLParen, '(');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C7);   { mov rdi, rax (fd) }
      Expect(tkComma, ',');
      ParseExpr; EmitB($48); EmitB($89); EmitB($C6);   { mov rsi, rax (mode) }
      MovRaxImm(91); EmitSyscall;
      Expect(tkRParen, ')');
    end;
    tkArgStr:
    begin
      { ArgStr(n, s): copy argv[n] bytes into string var s (global) }
      Next; Expect(tkLParen, '(');
      ParseExpr;  { n → rax }
      Expect(tkComma, ',');
      { compute argv[n] address: [rsp_initial + 8 + n*8] }
      { rax = n; multiply by 8; add initial_rsp+8 }
      EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);   { shl rax, 3 }
      { add rax, [bss_initial_rsp] + 8 }
      { mov rcx, [bss_initial_rsp]; add rcx, 8; add rax, rcx }
      EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
      EmitB($48); EmitB($83); EmitB($C1); EmitB($08);   { add rcx, 8 }
      EmitB($48); EmitB($01); EmitB($C8);               { add rax, rcx }
      { rax = address of argv[n] pointer }
      EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] }
      { rax = pointer to argument C-string }
      EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax (src) }
      { target string var: }
      if CurTok.Kind <> tkIdent then Error('ArgStr: expected string var');
      idx := FindSym(CurTok.SVal);
      if (idx < 0) or (Syms[idx].TypeKind <> tyString) then Error('ArgStr: not a string var');
      { Count length: scan rsi for NUL, store length + copy }
      { Use rcx as length counter }
      EmitB($48); EmitB($31); EmitB($C9);               { xor rcx, rcx }
      { NUL scan: cmp byte [rsi+rcx], 0; je +5; inc rcx; jmp -11 }
      EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0  -- 4 bytes }
      EmitB($74); EmitB($05);                            { je +5 (over inc+jmp)   -- 2 bytes }
      EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx                -- 3 bytes }
      EmitB($EB); EmitB($F5);                            { jmp -11 (back to cmp) -- 2 bytes }
      { rcx = length; store length }
      EmitB($48); EmitB($89); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      { lea rdi, [bss+str.Offset+8] }
      EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8);
      { rep movsb }
      EmitB($F3); EmitB($A4);
      Next;
      Expect(tkRParen, ')');
    end;

    tkIf:     begin Next; ParseIfStatement;    end;
    tkWhile:  begin Next; ParseWhileStatement; end;
    tkFor:    begin Next; ParseForStatement;   end;
    tkRepeat: begin Next; ParseRepeatStatement; end;
    tkCase:   begin Next; ParseCaseStatement;  end;

    tkBegin:  begin Next; ParseBlock; Expect(tkEnd, 'end'); end;

    tkIdent:
    begin
      name := CurTok.SVal;

      { Function return value: FuncName := expr }
      if (CurProc >= 0) and Procs[CurProc].IsFunc and
         (LowerCase(name) = Procs[CurProc].Name) then
      begin
        Next; Expect(tkAssign, ':=');
        ParseExpr;
        EmitStoreVar(Procs[CurProc].RetSymIdx);
        Exit;
      end;

      { Procedure call }
      pi := FindProc(name);
      if pi >= 0 then
      begin
        Next;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          for i := 0 to Procs[pi].ParamCount-1 do
          begin
            ParseExpr; EmitB($50);
            if i < Procs[pi].ParamCount-1 then Expect(tkComma, ',');
          end;
          Expect(tkRParen, ')');
        end;
        for i := Procs[pi].ParamCount-1 downto 0 do
          case i of
            0: EmitB($5F);
            1: EmitB($5E);
            2: EmitB($5A);
            3: EmitB($59);
            4: begin EmitB($41); EmitB($58); end;
            5: begin EmitB($41); EmitB($59); end;
          end;
        EmitCallProc(pi);
        Exit;
      end;

      { Variable assignment }
      Next;
      if CurTok.Kind = tkLBrack then
      begin
        { arr[index] := expr }
        idx := FindSym(name);
        if (idx < 0) or not Syms[idx].IsArray then Error('not an array: ' + name);
        Next;   { consume [ }
        ParseExpr;  { index → rax }
        Expect(tkRBrack, ']');
        EmitArrElemAddr(idx);
        EmitB($50);  { push element address }
        Expect(tkAssign, ':=');
        ParseExpr;   { value → rax }
        EmitArrStore(idx);
        Exit;
      end;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        idx := FindSym(name);
        if idx < 0 then Error('undefined variable: ' + name);
        if (Syms[idx].TypeKind = tyString) and (Syms[idx].Kind = skGlobal) then
        begin
          if CurTok.Kind = tkString then
          begin
            si := InternStr(CurTok.SVal); Next;
            EmitStrAssignLiteral(idx, Strs[si].Offset, Strs[si].Len);
          end
          else
          begin
            { string := string_var }
            si2 := FindSym(CurTok.SVal);
            if (si2 >= 0) and (Syms[si2].TypeKind = tyString) and (Syms[si2].Kind = skGlobal) then
            begin
              EmitStrAssignVar(idx, si2); Next;
            end
            else Error('string assignment: literal or string var required');
          end;
        end
        else
        begin
          ParseExpr; EmitStoreVar(idx);
        end;
      end
      else
        while not (CurTok.Kind in [tkSemicolon,tkEnd,tkElse,tkUntil,tkEOF]) do Next;
    end;

    tkSemicolon, tkEnd, tkElse, tkUntil, tkEOF: ;
    else
      while not (CurTok.Kind in [tkSemicolon,tkEnd,tkElse,tkUntil,tkEOF]) do Next;
  end;
end;

{ ===== Declaration parsing ===== }

function ParseTypeKind: TTypeKind;
begin
  case CurTok.Kind of
    tkInteger_T, tkLongWord_T: Result := tyInteger;
    tkBoolean_T: Result := tyBoolean;
    tkChar_T:    Result := tyChar;
    tkString_T:  Result := tyString;
    else
    begin
      { Maybe an enum type name — look up as tyInteger }
      Result := tyInteger;
    end;
  end;
  Next;
end;

procedure ParseVarSection;
var names: array[0..63] of AnsiString; n, i: Integer; tk: TTypeKind;
    isArr: Boolean; arrLo, arrHi: Integer; elemTk: TTypeKind;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    n := 0;
    repeat
      names[n] := CurTok.SVal; Inc(n); Next;
    until not Eat(tkComma);
    Expect(tkColon, ':');
    isArr := False; arrLo := 0; arrHi := 0; elemTk := tyInteger;
    if CurTok.Kind = tkArray then
    begin
      isArr := True; Next;
      if CurTok.Kind = tkLBrack then
      begin
        Next;
        arrLo := ConstEval;
        Expect(tkDotDot, '..');
        arrHi := ConstEval;
        Expect(tkRBrack, ']');
      end;
      Expect(tkOf, 'of');
      elemTk := ParseTypeKind;
      tk := elemTk;
    end
    else
    begin
      { Skip qualifiers like pointer, ^, etc. }
      while not (CurTok.Kind in [tkSemicolon, tkBegin, tkVar, tkConst, tkType,
                 tkProcedure, tkFunction, tkEOF]) do
      begin
        tk := ParseTypeKind;
        if CurTok.Kind in [tkSemicolon, tkBegin, tkVar, tkConst, tkType,
                           tkProcedure, tkFunction, tkEOF] then Break;
      end;
    end;
    if isArr then
      for i := 0 to n-1 do AllocArray(names[i], elemTk, arrLo, arrHi)
    else
      for i := 0 to n-1 do AllocVar(names[i], tk);
    Eat(tkSemicolon);
  end;
end;

procedure ParseConstSection;
var name: AnsiString; v: Int64;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    name := CurTok.SVal; Next;
    Expect(tkEq, '=');
    v := ConstEval;
    AddConst(name, tyInteger, v);
    Eat(tkSemicolon);
  end;
end;

procedure ParseTypeSection;
{ Handles enum types: type TFoo = (a, b, c); }
var ord: Int64; tname: AnsiString;
begin
  Next;
  while CurTok.Kind = tkIdent do
  begin
    tname := CurTok.SVal; Next;
    Expect(tkEq, '=');
    if CurTok.Kind = tkLParen then
    begin
      Next; ord := 0;
      while CurTok.Kind = tkIdent do
      begin
        AddConst(CurTok.SVal, tyInteger, ord);
        Inc(ord); Next;
        if not Eat(tkComma) then Break;
      end;
      Expect(tkRParen, ')');
    end
    else
    begin
      { Skip non-enum type defs }
      while not (CurTok.Kind in [tkSemicolon,tkIdent,tkEOF]) do Next;
    end;
    Eat(tkSemicolon);
  end;
end;

{ ===== Procedure/function parser ===== }

procedure ParseSubroutine;
var
  isFunc   : Boolean;
  name     : AnsiString;
  retType  : TTypeKind;
  tk       : TTypeKind;
  pnames   : array[0..7] of AnsiString;
  ptypes   : array[0..7] of TTypeKind;
  nparams  : Integer;
  pi, i    : Integer;
  savedSC, savedFS : Integer;
  patchPos : Integer;
  { arg reg ModRM bytes for store-to-frame: rdi,rsi,rdx,rcx }
  ArgModRM : array[0..3] of Byte = ($BD, $B5, $95, $8D);
begin
  isFunc := CurTok.Kind = tkFunction;
  Next;
  if CurTok.Kind <> tkIdent then Error('expected name');
  name := CurTok.SVal; Next;

  nparams := 0; retType := tyInteger;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    while CurTok.Kind <> tkRParen do
    begin
      if CurTok.Kind in [tkVar, tkConst] then Next;
      while CurTok.Kind = tkIdent do
      begin
        pnames[nparams] := CurTok.SVal; Inc(nparams); Next;
        if not Eat(tkComma) then Break;
        if CurTok.Kind = tkColon then Break;
      end;
      Expect(tkColon, ':');
      tk := ParseTypeKind;
      for i := 0 to nparams-1 do ptypes[i] := tk;
      if not Eat(tkSemicolon) then Break;
    end;
    Expect(tkRParen, ')');
  end;

  if isFunc then
  begin
    Expect(tkColon, ':');
    retType := ParseTypeKind;
  end;

  { Forward declaration? }
  if CurTok.Kind = tkForward then
  begin
    Next; Eat(tkSemicolon);
    if FindProc(name) < 0 then
      RegisterProc(name, isFunc, retType, nparams, pnames, ptypes, -1);
    Exit;
  end;

  Eat(tkSemicolon);

  { Register or resolve }
  pi := FindProc(name);
  if pi < 0 then
    pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes, CodeLen)
  else
    Procs[pi].BodyAddr := CodeLen;

  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;

  { Allocate param slots }
  for i := 0 to nparams-1 do
  begin
    AllocVar(pnames[i], ptypes[i]);
    Procs[pi].Params[i].SymIdx := SymCount - 1;
    Syms[SymCount-1].Kind := skParam;
  end;

  { Return value slot }
  if isFunc then
  begin
    AllocVar('', tyInteger);
    Procs[pi].RetSymIdx := SymCount - 1;
    Syms[SymCount-1].Kind := skLocal;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;

  { Copy params from registers to stack }
  for i := 0 to nparams-1 do
  begin
    if i < 4 then
    begin
      EmitB($48); EmitB($89); EmitB(ArgModRM[i]);
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end
    else if i = 4 then
    begin
      EmitB($4C); EmitB($89); EmitB($85);
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end
    else if i = 5 then
    begin
      EmitB($4C); EmitB($89); EmitB($8D);
      EmitI32(Syms[Procs[pi].Params[i].SymIdx].Offset);
    end;
  end;

  { Optional var section }
  while CurTok.Kind in [tkVar, tkConst, tkType] do
    case CurTok.Kind of
      tkVar:   ParseVarSection;
      tkConst: ParseConstSection;
      tkType:  ParseTypeSection;
    end;

  { Body }
  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkSemicolon);

  { Epilogue }
  EmitProcEpilog(Procs[pi].RetSymIdx);

  { Patch frame size }
  PatchProcPrologue(patchPos, FrameSize);

  { Restore scope }
  SymCount  := savedSC;
  FrameSize := savedFS;
  CurProc   := -1;
end;

{ ===== Program ===== }

procedure ParseProgram;
var jmpPatch: Integer;
begin
  Expect(tkProgram, 'program');
  if CurTok.Kind = tkEOF then Error('expected program name');
  Next;  { program name can be any identifier (even keyword) }
  if CurTok.Kind = tkLParen then
    begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
  Eat(tkSemicolon);

  { Reserve BSS[0..7] for initial rsp (argv access) }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  { Emit entry stub: save rsp then jmp to main body }
  { mov [bss_initial_rsp], rsp: 48 89 24 25 <GlobRef(0)> }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  while CurTok.Kind in
    [tkUses, tkVar, tkConst, tkType, tkProcedure, tkFunction] do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        while CurTok.Kind = tkIdent do begin Next; if not Eat(tkComma) then Break; end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection;
      tkType:     ParseTypeSection;
      tkProcedure,
      tkFunction: ParseSubroutine;
    end;

  { Patch jmp to point here (start of main body) }
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  Expect(tkBegin, 'begin');
  ParseBlock;
  Expect(tkEnd, 'end');
  Eat(tkDot);

  EmitExit(0);
  ApplyCallFixups;
end;

{ ===== ELF writer ===== }

procedure PatchAddr8(pos: Integer; addr: Int64);
begin
  Code[pos+0] := Byte(addr and $FF);
  Code[pos+1] := Byte((addr shr 8) and $FF);
  Code[pos+2] := Byte((addr shr 16) and $FF);
  Code[pos+3] := Byte((addr shr 24) and $FF);
  Code[pos+4] := Byte((addr shr 32) and $FF);
  Code[pos+5] := Byte((addr shr 40) and $FF);
  Code[pos+6] := Byte((addr shr 48) and $FF);
  Code[pos+7] := Byte((addr shr 56) and $FF);
end;

procedure WriteU8(var f:File;v:Byte);   begin BlockWrite(f,v,1); end;
procedure WriteU16(var f:File;v:Word);
var b:array[0..1]of Byte;
begin b[0]:=v and $FF;b[1]:=(v shr 8)and $FF;BlockWrite(f,b,2);end;
procedure WriteU32(var f:File;v:LongWord);
var b:array[0..3]of Byte;
begin b[0]:=v and $FF;b[1]:=(v shr 8)and $FF;b[2]:=(v shr 16)and $FF;b[3]:=(v shr 24)and $FF;BlockWrite(f,b,4);end;
procedure WriteU64(var f:File;v:Int64);
begin WriteU32(f,LongWord(v and $FFFFFFFF));WriteU32(f,LongWord((v shr 32)and $FFFFFFFF));end;

procedure WriteELF(const outPath: AnsiString);
var f: File; i: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  dataBase := LOAD_ADDR + CODE_OFFSET + CodeLen;
  bssBase  := dataBase + DataLen;
  entry    := LOAD_ADDR + CODE_OFFSET;
  filesz   := CODE_OFFSET + CodeLen + DataLen;
  memsz    := filesz + BSSSize;

  { Apply data fixups (8-byte absolute) }
  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    PatchAddr8(Fixups[i].CodePos, addr);
  end;

  { Apply global fixups (4-byte absolute) }
  for i := 0 to GlobFixCount-1 do
  begin
    addr := bssBase + GlobFix[i].BSSoff;
    Patch32(GlobFix[i].CodePos, addr);
  end;

  Assign(f, outPath); Rewrite(f, 1);

  WriteU8(f,$7F);WriteU8(f,$45);WriteU8(f,$4C);WriteU8(f,$46);
  WriteU8(f,2);WriteU8(f,1);WriteU8(f,1);WriteU8(f,0);
  WriteU8(f,0);WriteU8(f,0);WriteU8(f,0);WriteU8(f,0);
  WriteU8(f,0);WriteU8(f,0);WriteU8(f,0);WriteU8(f,0);
  WriteU16(f,2);WriteU16(f,62);WriteU32(f,1);
  WriteU64(f,entry);WriteU64(f,64);WriteU64(f,0);
  WriteU32(f,0);WriteU16(f,64);WriteU16(f,56);
  WriteU16(f,1);WriteU16(f,64);WriteU16(f,0);WriteU16(f,0);

  WriteU32(f,1);WriteU32(f,7);  { PT_LOAD, RWX }
  WriteU64(f,0);WriteU64(f,LOAD_ADDR);WriteU64(f,LOAD_ADDR);
  WriteU64(f,filesz);WriteU64(f,memsz);WriteU64(f,$200000);

  if CodeLen > 0 then BlockWrite(f,Code[0],CodeLen);
  if DataLen > 0 then BlockWrite(f,Data[0],DataLen);
  Close(f);
  FpChmod(outPath,&755);
end;

{ ===== Main ===== }

var inFile, outFile: AnsiString; tf: TextFile; line: AnsiString;
begin
  if ParamCount < 1 then
    begin WriteLn(StdErr,'usage: pascal26 <src.pas> [out]'); Halt(1); end;

  inFile  := ParamStr(1);
  outFile := ChangeFileExt(inFile,'');
  if ParamCount >= 2 then outFile := ParamStr(2);

  Source := '';
  Assign(tf,inFile); Reset(tf);
  while not EOF(tf) do begin ReadLn(tf,line); Source := Source + line + #10; end;
  Close(tf);

  SrcPos   := 1; SrcLine  := 1;
  CodeLen  := 0;
  DataLen  := STR_INIT_OFFSET;
  Data[MINUS_OFFSET]   := Ord('-');
  Data[NEWLINE_OFFSET] := 10;
  BSSSize  := 0;
  StrCount := 0; FixCount := 0;
  GlobFixCount := 0; CallFixCount := 0;
  SymCount := 0; ProcCount := 0;
  FrameSize := 0; CurProc := -1;

  Next;
  ParseProgram;
  WriteELF(outFile);

  WriteLn('ok: ',outFile,'  [code=',CodeLen,'B  data=',DataLen,
          'B  bss=',BSSSize,'B  procs=',ProcCount,']');
end.
