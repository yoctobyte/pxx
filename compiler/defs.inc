const
  TARGET_PTR_SIZE = 8;  { pointer size in bytes on the current target (x86-64) }

  MAX_CODE      = 1048576;
  LOCAL_STR_CAP = 256;     { max string length for local/stack variables }
  MAX_DATA    = 1048576;
  MAX_STRS    = 4096;
  MAX_FIXUPS  = 65536;
  MAX_SYMS    = 8192;
  MAX_PROCS   = 512;
  MAX_CALLFIX = 4096;
  MAX_GLOBFIX = 8192;
  MAX_EXTERNAL = 256;
  MAX_CPREP_MACROS = 1024;
  MAX_CPREP_PARAMS = 4096;
  MAX_CPREP_CONDS = 64;
  MAX_CPREP_INCLUDES = 16;
  MAX_CPREP_CHARS = 1048576;
  MAX_CPREP_ARGS = 544; { 34 macro-expansion levels, 16 arguments each }
  STRING_CAP  = 1048576;
  MAX_TOKENS  = 262144;
  MAX_AST     = 131072;
  MAX_IR      = 8192;
  MAX_LOOP_FIXUPS = 256;
  MAX_GOTO_LABELS = 64;
  MAX_PAS_DEFINES = 128;
  MAX_PAS_DEFINE_CHARS = 4096;
  MAX_PAS_CONDS = 64;
  SPECIAL_IN  = 999;

  MAX_UCLASS      = 32;    { user-defined class slots }
  MAX_UFIELD      = 256;   { field slots across all user classes }
  MAX_UMETH       = 256;   { method slots across all user classes }
  MAX_UPROP       = 64;
  REC_NONE         = 0;
  REC_TMETHODFIXUP = 15;
  REC_UCLASS_BASE = 16;    { user class recIds start here; must exceed REC_TMETHODFIXUP=15 }

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
  AN_BREAK     = 25;
  AN_CONTINUE  = 26;
  AN_TRY_EXCEPT = 27; { Left = protected block; Right = AN_EXC_HANDLER chain }
  AN_RAISE     = 28;  { Left = raised expression }
  AN_TRY_FINALLY = 29; { Left = protected block; Right = finalizer block }
  AN_EXC_HANDLER = 30; { IVal = class recId or -1; Left = body; Right = next }
  AN_FLOAT_LIT   = 31; { IVal = IEEE 754 double bits; ASTTk = Ord(tySingle or tyDouble) }
  AN_VIRTUAL_CALL = 32;
  AN_LABEL        = 33; { ASTSOffset/SLen = label name in TokChars }
  AN_GOTO         = 34; { ASTSOffset/SLen = label name in TokChars }
  AN_ADDR         = 35;
  AN_DEREF        = 36;

  { IR opcodes. Append only while bootstrapping, as with token/node kinds. }
  IR_NOP       = 0;
  IR_CONST_INT = 1;
  IR_CONST_STR = 2;
  IR_LOAD_SYM  = 3;
  IR_STORE_SYM = 4;
  IR_BINOP     = 5;
  IR_CALL      = 6;
  IR_WRITE     = 7;
  IR_WRITELN   = 8;
  IR_BLOCK     = 9;
  IR_UNSUPPORTED = 10;
  IR_IF        = 11;
  IR_LABEL     = 12;
  IR_JUMP      = 13;
  IR_JUMP_IF_FALSE = 14;
  IR_NEG       = 15;
  IR_NOT       = 16;
  IR_LEA       = 17;
  IR_INDEX     = 18;
  IR_FIELD     = 19;
  IR_LOAD_MEM  = 20;
  IR_STORE_MEM = 21;
  IR_ARG       = 22;
  IR_EXC_ENTER = 23;
  IR_EXC_LEAVE = 24;
  IR_RAISE     = 25;
  IR_EXC_MATCH = 26;
  IR_EXC_STORE = 27;
  IR_EXC_CLEAR = 28;
  IR_TERMINATE = 29;
  IR_VIRTUAL_CALL = 30;  { VMT dispatch: IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot }

  EXC_FRAME_SIZE = 80;
  EXC_JMP_OFFSET = 8;

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
  DYNAMIC_CODE_OFFSET = ELF_HEADER_SIZE + PROG_HEADER_SIZE +
                        PROG_HEADER_SIZE + PROG_HEADER_SIZE;

  INTBUF_OFFSET   = 0;
  INTBUF_SIZE     = 24;
  MINUS_OFFSET    = 24;
  NEWLINE_OFFSET  = 25;
  SPACES_SIZE     = 40;
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
    tkSemicolon, tkColon, tkComma, tkDot, tkDotDot, tkAt, tkCaret,
    tkBreak, tkContinue, tkOverload,
    tkTry, tkExcept, tkFinally, tkRaise, tkOn,
    tkFloat, tkSingle_T, tkDouble_T, tkExtended_T,
    tkProperty,
    tkNil
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

  TTypeKind = (
    { Ordinals 0–6: fixed since first bootstrap — DO NOT reorder }
    tyUnknown,   { 0: unresolved/error }
    tyInteger,   { 1: Integer, kept at its bootstrap ordinal; 4-byte signed }
    tyBoolean,   { 2: Boolean, kept at its bootstrap ordinal; 1-byte unsigned }
    tyChar,      { 3: 1-byte unsigned character/Byte alias }
    tyString,    { 4: Pascal string with inline length prefix }
    tyRecord,    { 5: record/struct }
    tyClass,     { 6: class reference (pointer-sized) }
    { Ordinals 7–17: appended for correct Pascal semantics — safe to extend }
    tyInt8,      { 7: ShortInt  — 1 byte signed }
    tyUInt8,     { 8: Byte      — 1 byte unsigned }
    tyInt16,     { 9: SmallInt — 2 bytes signed }
    tyUInt16,    { 10: Word    — 2 bytes unsigned }
    tyInt32,     { 11: Integer/LongInt — 4 bytes signed }
    tyUInt32,    { 12: Cardinal/LongWord — 4 bytes unsigned }
    tyInt64,     { 13: Int64  — 8 bytes signed }
    tyUInt64,    { 14: QWord  — 8 bytes unsigned }
    tyNativeInt,  { 15: NativeInt/PtrInt — pointer-sized signed }
    tyNativeUInt, { 16: NativeUInt/PtrUInt — pointer-sized unsigned }
    tyPointer,   { 17: untyped Pointer — pointer-sized, no sign }
    tySingle,    { 18: Single — 4-byte IEEE 754, SSE2 xmm }
    tyDouble,    { 19: Double/Real — 8-byte IEEE 754, SSE2 xmm }
    tyExtended   { 20: Extended — 10-byte x87, load/store via x87; ops in SSE2 double }
  );

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
    PtrElemTk : TTypeKind;
    PtrElemRec: Integer;
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
    Params     : array[0..15] of TParam;
    BodyAddr   : Integer;   { -1 = forward declared }
    FramePatch : Integer;   { code position of sub rsp imm32 }
    RetSymIdx  : Integer;   { Syms[] index for return value; -1 if proc }
    ScopeBase  : Integer;   { Syms[] index at start of this proc's locals }
  end;

const
  MAX_TEMPLATES = 16;
  MAX_TEMPLATE_TOKENS = 8192;
  MAX_SPECIALIZATIONS = 32;
  MAX_GENERIC_FUNCS = 16;
  MAX_PENDING_GFSPECS = 32;
  MAX_OP_OVERLOADS = 64;

type
  TTemplate = record
    Name     : AnsiString;
    Param    : AnsiString;
    TokStart : Integer;
    TokCount : Integer;
  end;

  TSpecialization = record
    Name         : AnsiString;  { e.g. TIntStack }
    TemplateName : AnsiString;  { e.g. TStack }
    ConcreteType : TTokenKind;  { e.g. tkInteger_T }
    ConcreteName : AnsiString;  { e.g. 'Integer' or 'TMyClass' }
  end;

  TGenericFunc = record
    Name     : AnsiString;
    Param    : AnsiString;
    IsFunc   : Boolean;
    TokStart : Integer;
    TokCount : Integer;
  end;

  TPendingGFSpec = record
    GenFuncIdx   : Integer;
    ConcreteKind : TTokenKind;
    ConcreteName : AnsiString;
    SpecName     : AnsiString;
  end;

  TMethodFixup = record
    DataPos : Integer;
    ProcIdx : Integer;
  end;

var
  Templates          : array[0..MAX_TEMPLATES-1] of TTemplate;
  TemplateCount      : Integer;
  Specializations    : array[0..MAX_SPECIALIZATIONS-1] of TSpecialization;
  SpecializationCount: Integer;
  TemplateTokens     : array[0..MAX_TEMPLATE_TOKENS-1] of TRawToken;
  SpecializeTemplateName: AnsiString;
  SpecializeTokens   : array[0..MAX_TEMPLATE_TOKENS-1] of TRawToken;
  TemplateTokenCount : Integer;
  GenericFuncs       : array[0..MAX_GENERIC_FUNCS-1] of TGenericFunc;
  GenericFuncCount   : Integer;
  PendingGFSpecs     : array[0..MAX_PENDING_GFSPECS-1] of TPendingGFSpec;
  PendingGFSpecCount : Integer;
  MethodFixups       : array[0..255] of TMethodFixup;
  MethodFixCount     : Integer;
  { Operator overload table — parallel arrays, one entry per registered overload }
  OvrlOpKind   : array[0..MAX_OP_OVERLOADS-1] of Integer;  { TTokenKind ordinal }
  OvrlTypeKind : array[0..MAX_OP_OVERLOADS-1] of Integer;  { TTypeKind ordinal }
  OvrlRecId    : array[0..MAX_OP_OVERLOADS-1] of Integer;
  OvrlProcIdx  : array[0..MAX_OP_OVERLOADS-1] of Integer;
  OvrlCount    : Integer;
  { Scratch output of ScanGenericFuncSig }
  GFSig_NParams : Integer;
  GFSig_RetType : TTypeKind;
  GFSig_PNames  : array[0..7] of AnsiString;
  GFSig_PTypes  : array[0..7] of TTypeKind;

  DebugTrace : Boolean;
  DumpIR : Boolean;
  ExperimentalIRCodegen : Boolean;
  StrictOverload : Boolean;
  NoUnhandledHandler : Boolean;
  Source  : AnsiString;
  SrcPos  : Integer;
  SrcLine : Integer;
  CurTok  : TToken;
  PasDefineChars   : array[0..MAX_PAS_DEFINE_CHARS-1] of Char;
  PasDefineNameOff : array[0..MAX_PAS_DEFINES-1] of Integer;
  PasDefineNameLen : array[0..MAX_PAS_DEFINES-1] of Integer;
  PasDefineActive  : array[0..MAX_PAS_DEFINES-1] of Boolean;
  PasDefineCharLen : Integer;
  PasDefineCount   : Integer;
  PasCondParent    : array[0..MAX_PAS_CONDS-1] of Boolean;
  PasCondActive    : array[0..MAX_PAS_CONDS-1] of Boolean;
  PasCondTaken     : array[0..MAX_PAS_CONDS-1] of Boolean;
  PasCondCount     : Integer;
  PasCommandOption : AnsiString;

  Code    : array[0..MAX_CODE-1] of Byte;
  CodeLen : Integer;

  Data    : array[0..MAX_DATA-1] of Byte;
  DataLen      : Integer;
  SpacesOffset : Integer;  { -1 = not yet allocated; set lazily on first :width use }

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
  ProcOverloadDirective : array[0..MAX_PROCS-1] of Boolean;
  ProcCount : Integer;
  CurProc   : Integer;   { -1 = main }
  ProcExternal : array[0..MAX_PROCS-1] of Boolean;
  ProcLibrary  : array[0..MAX_PROCS-1] of Integer; { Strs[] entry for DT_NEEDED name }
  CurrentCLibrary : AnsiString;
  ExternalProc   : array[0..MAX_EXTERNAL-1] of Integer;
  ExternalGotOff : array[0..MAX_EXTERNAL-1] of Integer;
  ExternalCount  : Integer;
  DynCallCodePos : array[0..MAX_CALLFIX-1] of Integer;
  DynCallExtIdx  : array[0..MAX_CALLFIX-1] of Integer;
  DynCallCount   : Integer;
  DynamicInterpOff : Integer;
  DynamicInterpSize: Integer;
  DynamicStrOff    : Integer;
  DynamicStrSize   : Integer;
  DynamicSymOff    : Integer;
  DynamicHashOff   : Integer;
  DynamicRelaOff   : Integer;
  DynamicOff       : Integer;
  DynamicSize      : Integer;
  LastTypeRecId : Integer;
  LastTypePointerElemTk : TTypeKind;
  LastTypePointerElemRec : Integer;
  ErrorIdent : AnsiString;
  LastExprTk : TTypeKind;
  InInterface : Boolean;
  CompiledUnits : array[0..255] of Integer;
  CompiledUnitCount : Integer;
  SourceFileDir : AnsiString;
  CurASTNode : Integer;
  LoopNestDepth       : Integer;
  LoopBreakFixPos     : array[0..MAX_LOOP_FIXUPS-1] of Integer;
  LoopBreakFixCount   : Integer;
  LoopContinueFixPos  : array[0..MAX_LOOP_FIXUPS-1] of Integer;
  LoopContinueFixCount: Integer;
  LoopExceptionDepth  : array[0..MAX_LOOP_FIXUPS-1] of Integer;
  ExceptionCodegenDepth: Integer;
  ExceptionFinallyBody : array[0..MAX_LOOP_FIXUPS-1] of Integer;
  ExceptionHandlerParseDepth: Integer;
  AssignPath : AnsiString;
  IncExpanded : AnsiString;
  IncIncluded : AnsiString;
  UnitContent : AnsiString;
  LoadPath : AnsiString;
  SavedLexSource : AnsiString;
  sysbuf : array[0..7] of Byte;

  { C preprocessor state. Macro text is pooled to avoid string-array BSS cost. }
  CPrepOut      : AnsiString;
  CPrepLine     : AnsiString;
  CPrepPath     : AnsiString;
  CPrepInclude0 : AnsiString;
  CPrepInclude1 : AnsiString;
  CPrepInclude2 : AnsiString;
  CPrepInclude3 : AnsiString;
  CPrepInclude4 : AnsiString;
  CPrepInclude5 : AnsiString;
  CPrepInclude6 : AnsiString;
  CPrepInclude7 : AnsiString;
  CPrepInclude8 : AnsiString;
  CPrepInclude9 : AnsiString;
  CPrepInclude10: AnsiString;
  CPrepInclude11: AnsiString;
  CPrepInclude12: AnsiString;
  CPrepInclude13: AnsiString;
  CPrepInclude14: AnsiString;
  CPrepInclude15: AnsiString;
  CPrepChars    : array[0..MAX_CPREP_CHARS-1] of Char;
  CPrepCharLen  : Integer;
  CPMNameOff    : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMNameLen    : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMValueOff   : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMValueLen   : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMParamBase  : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMParamCount : array[0..MAX_CPREP_MACROS-1] of Integer;
  CPMFunction   : array[0..MAX_CPREP_MACROS-1] of Boolean;
  CPMCount      : Integer;
  CPPNameOff    : array[0..MAX_CPREP_PARAMS-1] of Integer;
  CPPNameLen    : array[0..MAX_CPREP_PARAMS-1] of Integer;
  CPPCount      : Integer;
  CPArgStart    : array[0..MAX_CPREP_ARGS-1] of Integer;
  CPArgEnd      : array[0..MAX_CPREP_ARGS-1] of Integer;
  CPCondParent  : array[0..MAX_CPREP_CONDS-1] of Boolean;
  CPCondActive  : array[0..MAX_CPREP_CONDS-1] of Boolean;
  CPCondTaken   : array[0..MAX_CPREP_CONDS-1] of Boolean;
  CPCondCount   : Integer;
  CPExprText    : AnsiString;
  CPExprPos     : Integer;
  CPExprEnd     : Integer;

  { Reserved BSS slot 0: initial rsp (for argv access) }
  BSS_INITIAL_RSP : Integer;  { always 0; set in ParseProgram init }
  BSS_HEAP_PTR    : Integer;
  BSS_HEAP_END    : Integer;
  BSS_EXC_TOP     : Integer;
  BSS_EXC_OBJ     : Integer;
  BSS_EXC_CLS     : Integer;
  ExceptionUsed   : Boolean;
  ExcSetJmpAddr   : Integer;
  ExcLongJmpAddr  : Integer;
  ExcRaiseAddr    : Integer;

  TokChars   : array[0..STRING_CAP-1] of Char;
  TokCharLen : Integer;
  Tokens     : array[0..MAX_TOKENS-1] of TRawToken;
  TokCount   : Integer;
  TokPos     : Integer;
  MainProgramTokCount : Integer;

  BLabelLineNums : array[0..255] of Int64;
  BLabelCodePoss : array[0..255] of Integer;
  BLabelCount    : Integer;

  { goto/label fixup tables for Pascal label declarations }
  GotoLabelNOff   : array[0..MAX_GOTO_LABELS-1] of Integer; { name offset in TokChars }
  GotoLabelNLen   : array[0..MAX_GOTO_LABELS-1] of Integer; { name length }
  GotoLabelCodePos: array[0..MAX_GOTO_LABELS-1] of Integer; { code position; -1 = not yet placed }
  GotoLabelIRId   : array[0..MAX_GOTO_LABELS-1] of Integer; { IR label ID for IR path; -1 = unallocated }
  GotoLabelCount  : Integer;
  GotoFixupCodePos: array[0..255] of Integer; { code position of the jmp rel32 operand }
  GotoFixupNOff   : array[0..255] of Integer; { name offset }
  GotoFixupNLen   : array[0..255] of Integer; { name length }
  GotoFixupCount  : Integer;

  BFixupTargetLines : array[0..255] of Int64;
  BFixupCodePoss    : array[0..255] of Integer;
  BFixupIsGOSUBs    : array[0..255] of Boolean;
  BFixupCount       : Integer;

  { AST node pool — struct-of-arrays, 8 bytes per field }
  ASTKind    : array[0..MAX_AST-1] of Integer;
  ASTIVal    : array[0..MAX_AST-1] of Int64;
  ASTSOffset : array[0..MAX_AST-1] of Integer;
  ASTSLen    : array[0..MAX_AST-1] of Integer;
  ASTLeft    : array[0..MAX_AST-1] of Integer;
  ASTRight   : array[0..MAX_AST-1] of Integer;
  ASTTk      : array[0..MAX_AST-1] of Integer;  { TTypeKind of expression }
  ASTNodeCount : Integer;

  IRKind  : array[0..MAX_IR-1] of Integer;
  IRA     : array[0..MAX_IR-1] of Integer;
  IRB     : array[0..MAX_IR-1] of Integer;
  IRC     : array[0..MAX_IR-1] of Integer;
  IRIVal  : array[0..MAX_IR-1] of Int64;
  IRTk    : array[0..MAX_IR-1] of Integer;
  IRCount : Integer;
  IRLabelCount : Integer;
  IRLoopStackBreak    : array[0..63] of Integer;
  IRLoopStackContinue : array[0..63] of Integer;
  IRLoopStackExceptionDepth : array[0..63] of Integer;
  IRLoopStackDepth    : Integer;

  { User-defined class/field/method tables - integer-only for fixedpoint safety }
  UClsNOff   : array[0..MAX_UCLASS-1] of Integer;
  UClsNLen   : array[0..MAX_UCLASS-1] of Integer;
  UClsSize_  : array[0..MAX_UCLASS-1] of Integer;
  UClsFBase  : array[0..MAX_UCLASS-1] of Integer;
  UClsFCount : array[0..MAX_UCLASS-1] of Integer;
  UClsMBase  : array[0..MAX_UCLASS-1] of Integer;
  UClsMCount : array[0..MAX_UCLASS-1] of Integer;
  UClsParent : array[0..MAX_UCLASS-1] of Integer;
  UClsVirtCount : array[0..MAX_UCLASS-1] of Integer;
  UClsVMTOffset : array[0..MAX_UCLASS-1] of Integer;
  UClsPBase  : array[0..MAX_UCLASS-1] of Integer;
  UClsPCount : array[0..MAX_UCLASS-1] of Integer;
  UClsIsRecord : array[0..MAX_UCLASS-1] of Boolean;
  UClsCount  : Integer;

  UFldNOff   : array[0..MAX_UFIELD-1] of Integer;
  UFldNLen   : array[0..MAX_UFIELD-1] of Integer;
  UFldOff_   : array[0..MAX_UFIELD-1] of Integer;
  UFldTk     : array[0..MAX_UFIELD-1] of Integer;
  UFldRec_   : array[0..MAX_UFIELD-1] of Integer;
  UFldPtrElemTk : array[0..MAX_UFIELD-1] of Integer;
  UFldPtrElemRec : array[0..MAX_UFIELD-1] of Integer;
  UFldCount  : Integer;

  UMthNOff   : array[0..MAX_UMETH-1] of Integer;
  UMthNLen   : array[0..MAX_UMETH-1] of Integer;
  UMthProc_  : array[0..MAX_UMETH-1] of Integer;
  UMthVirSlot : array[0..MAX_UMETH-1] of Integer;
  UMthIsStatic : array[0..MAX_UMETH-1] of Boolean;
  UMthCount  : Integer;

  UPropNOff   : array[0..MAX_UPROP-1] of Integer;
  UPropNLen   : array[0..MAX_UPROP-1] of Integer;
  UPropTk     : array[0..MAX_UPROP-1] of Integer;
  UPropRec    : array[0..MAX_UPROP-1] of Integer;
  UPropReadFOff : array[0..MAX_UPROP-1] of Integer;
  UPropReadFLen : array[0..MAX_UPROP-1] of Integer;
  UPropReadMOff : array[0..MAX_UPROP-1] of Integer;
  UPropReadMLen : array[0..MAX_UPROP-1] of Integer;
  UPropWriteFOff: array[0..MAX_UPROP-1] of Integer;
  UPropWriteFLen: array[0..MAX_UPROP-1] of Integer;
  UPropWriteMOff: array[0..MAX_UPROP-1] of Integer;
  UPropWriteMLen: array[0..MAX_UPROP-1] of Integer;
  UPropCount  : Integer;

  CurSelfClass : Integer;

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

function IntToTypeKind(val: Integer): TTypeKind;
begin
  {$ifdef FPC}
  Result := TTypeKind(val);
  {$else}
  Result := val;
  {$endif}
end;

function CaseEqual(const s1, s2: AnsiString): Boolean;
var i, len: Integer; c1, c2: Char; match: Boolean;
begin
  Result := False;
  len := Length(s1);
  if len = Length(s2) then
  begin
    match := True;
    for i := 1 to len do
    begin
      c1 := s1[i];
      c2 := s2[i];
      if (c1 >= 'A') and (c1 <= 'Z') then c1 := Chr(Ord(c1) + 32);
      if (c2 >= 'A') and (c2 <= 'Z') then c2 := Chr(Ord(c2) + 32);
      if c1 <> c2 then match := False;
    end;
    Result := match;
  end;
end;
