const
  VERBOSE       = False;  { set True to enable debug trace output }

  MAX_CODE      = 1048576;
  LOCAL_STR_CAP = 256;     { max string length for local/stack variables }
  MAX_DATA    = 1048576;
  MAX_STRS    = 4096;
  MAX_FIXUPS  = 65536;
  MAX_SYMS    = 8192;
  MAX_PROCS   = 512;
  MAX_CALLFIX = 4096;
  MAX_GLOBFIX = 8192;
  STRING_CAP  = 1048576;

  SYS_READ  = 0;
  SYS_WRITE = 1;
  SYS_OPEN  = 2;
  SYS_CLOSE = 3;
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
    tkwriteln, tkwrite, tkReadln, tkRead,
    tkHalt, tkInc, tkDec, tkLength, tkOrd, tkChr, tkExit,
    tkSysOpen, tkSysRead, tkSyswrite, tkSysClose, tkSysFchmod,
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

  TTypeKind = (tyUnknown, tyInteger, tyBoolean, tyChar, tyString, tyRecord);
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
    RecName  : Integer;
    ElemRecName: Integer;
    IsRef    : Boolean;   { parameter passed by reference }
  end;

  TParam = record
    Name    : AnsiString;
    TypeKind: TTypeKind;
    SymIdx  : Integer;
    IsRef   : Boolean;
    IsArray : Boolean;
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
  LastTypeRecId : Integer;
  ErrorIdent : AnsiString;
  LastExprTk : TTypeKind;
  AssignPath : AnsiString;
  IncExpanded : AnsiString;
  IncIncluded : AnsiString;
  LoadPath : AnsiString;
  sysbuf : array[0..7] of Byte;

  { Reserved BSS slot 0: initial rsp (for argv access) }
  BSS_INITIAL_RSP : Integer;  { always 0; set in ParseProgram init }

{$ifdef FPC}
function sysopen(const path: AnsiString; flags: Integer): Integer;
begin
  Result := fpOpen(path, flags, &644);
end;

function syswrite(fd: Integer; const buf; count: Integer): Integer;
begin
  Result := fpWrite(fd, buf, count);
end;

function sysread(fd: Integer; var buf; count: Integer): Integer;
begin
  Result := fpRead(fd, buf, count);
end;

function sysclose(fd: Integer): Integer;
begin
  Result := fpClose(fd);
end;

procedure sysfchmod(fd: Integer; mode: Integer);
begin
  fpChmod(AssignPath, mode);
end;
{$endif}
