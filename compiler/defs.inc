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
  MAX_TOKENS  = 131072;
  MAX_AST     = 65536;
  SPECIAL_IN  = 999;
  MAX_RECORDS = 64;
  MAX_FIELDS  = 64;

  { AST node kinds }
  AN_NONE      = 0;
  AN_INT_LIT   = 1;
  AN_STR_LIT   = 2;
  AN_IDENT     = 3;
  AN_BOOL_LIT  = 4;
  AN_BINOP     = 5;   { IVal = token kind of operator }
  AN_NEG       = 6;   { unary minus; Left = operand }
  AN_NOT       = 7;   { unary not;   Left = operand }
  AN_CALL      = 8;   { IVal = proc index; Left = first arg (AN_ARG chain) }
  AN_ARG       = 9;   { Left = value; Right = next arg or -1 }
  AN_INDEX     = 10;  { Left = base sym idx; Right = index expr }
  AN_FIELD     = 11;  { Left = base sym idx; SOffset/SLen = field name }
  AN_ASSIGN    = 12;
  AN_IF        = 13;  { Left = cond; Right = AN_PAIR(then, else) }
  AN_WHILE     = 14;  { Left = cond; Right = body }
  AN_FOR       = 15;
  AN_REPEAT    = 16;
  AN_CASE      = 17;
  AN_BLOCK     = 18;  { Left = first stmt (AN_SEQ chain) }
  AN_SEQ       = 19;  { Left = stmt; Right = next or -1 }
  AN_PAIR      = 20;  { Left = first; Right = second }
  AN_WRITELN   = 21;
  AN_WRITE     = 22;
  AN_HALT      = 23;
  AN_EXIT      = 24;

  SYS_READ  = 0;
  SYS_WRITE = 1;
  SYS_OPEN  = 2;
  SYS_CLOSE = 3;
  SYS_EXIT  = 60;
  SYS_BRK   = 12;
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
    tkArray, tkRecord, tkClass,
    tkAnd, tkOr, tkNot, tkDiv, tkMod,
    tkTrue, tkFalse,
    tkwriteln, tkwrite, tkReadln, tkRead,
    tkHalt, tkInc, tkDec, tkLength, tkGetMem, tkOrd, tkChr, tkExit,
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

  TRawToken = record
    Kind    : TTokenKind;
    IVal    : Int64;
    Line    : Integer;
    SOffset : Integer;
    SLen    : Integer;
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

  TTypeKind = (tyUnknown, tyInteger, tyBoolean, tyChar, tyString, tyRecord, tyClass);

  TField = record
    Name     : AnsiString;
    Offset   : Integer;
    TypeKind : TTypeKind;
    RecId    : Integer;
    IsArray  : Boolean;
    ArrLen   : Integer;
  end;

  TRecord = record
    Name       : AnsiString;
    Size       : Integer;
    IsClass    : Boolean;
    FieldCount : Integer;
    Fields     : array[0..MAX_FIELDS-1] of TField;
  end;
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
  Records       : array[0..MAX_RECORDS-1] of TRecord;
  RecordCount   : Integer;
  ErrorIdent : AnsiString;
  LastExprTk : TTypeKind;
  InInterface : Boolean;
  CompiledUnits : array[0..255] of Integer;
  CompiledUnitCount : Integer;
  SourceFileDir : AnsiString;
  CurASTNode : Integer;
  AssignPath : AnsiString;
  IncExpanded : AnsiString;
  IncIncluded : AnsiString;
  LoadPath : AnsiString;
  sysbuf : array[0..7] of Byte;

  { Reserved BSS slot 0: initial rsp (for argv access) }
  BSS_INITIAL_RSP : Integer;  { always 0; set in ParseProgram init }
  BSS_HEAP_PTR    : Integer;
  BSS_HEAP_END    : Integer;

  TokChars   : array[0..STRING_CAP-1] of Char;
  TokCharLen : Integer;
  Tokens     : array[0..MAX_TOKENS-1] of TRawToken;
  TokCount   : Integer;
  TokPos     : Integer;

  { AST node pool — struct-of-arrays, 8 bytes per field }
  ASTKind    : array[0..MAX_AST-1] of Integer;
  ASTIVal    : array[0..MAX_AST-1] of Int64;
  ASTSOffset : array[0..MAX_AST-1] of Integer;
  ASTSLen    : array[0..MAX_AST-1] of Integer;
  ASTLeft    : array[0..MAX_AST-1] of Integer;
  ASTRight   : array[0..MAX_AST-1] of Integer;
  ASTTk      : array[0..MAX_AST-1] of Integer;  { TTypeKind of expression }
  ASTNodeCount : Integer;

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

function IntToTokenKind(val: Integer): TTokenKind;
begin
  {$ifdef FPC}
  Result := TTokenKind(val);
  {$else}
  Result := val;
  {$endif}
end;
