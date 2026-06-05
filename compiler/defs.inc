const
  TARGET_PTR_SIZE = 8;  { pointer size in bytes on the current target (x86-64) }

  MAX_CODE      = 4194304;
  LOCAL_STR_CAP = 256;     { max string length for local/stack variables }
  LINE_BUF_SIZE = 4096;    { readln stdin line buffer }
  MAX_DATA    = 2097152;      { 2 MB }
  MAX_STRS    = 8192;
  MAX_FIXUPS  = 131072;
  MAX_SYMS    = 131072;
  MAX_PROCS   = 16384;
  MAX_PARAM_DEPTHS = 262144;  { MAX_PROCS * 16 }
  MAX_CALLFIX = 16384;
  MAX_GLOBFIX = 32768;
  MAX_EXTERNAL = 16384;
  MAX_CPREP_MACROS = 32768;
  MAX_CPREP_PARAMS = 131072;
  MAX_CPREP_CONDS = 256;
  MAX_CPREP_INCLUDES = 128;
  MAX_CPREP_CHARS = 8388608;  { 8 MB }
  MAX_CPREP_ARGS = 4096;
  STRING_CAP  = 8388608;      { 8 MB }
  MAX_TOKENS  = 524288;
  MAX_AST     = 524288;
  MAX_IR      = 131072;
  MAX_LOOP_FIXUPS = 256;
  MAX_GOTO_LABELS = 64;
  MAX_PAS_DEFINES = 128;
  MAX_PAS_DEFINE_CHARS = 4096;
  MAX_PAS_CONDS = 64;
  SPECIAL_IN  = 999;

  MAX_UCLASS      = 512;   { user-defined class/record slots (incl. imported C structs) }
  MAX_UFIELD      = 16384; { field slots across all user classes/records }
  MAX_UMETH       = 256;   { method slots across all user classes }
  MAX_UPROP       = 64;
  MAX_ENUMTYPE = 512;
  MAX_ENUMVAL  = 4096;
  MAX_TYPEALIAS = 4096;
  MAX_CTYPEDEF  = 8192;
  MAX_RESOURCES   = 16;    { embedded R-directive resources }
  MAX_DATAPTRFIX  = 4096;  { data->data 8-byte pointer relocations (RTTI blobs) }
  MAX_METHFIX     = 1024;  { code-address relocations into Data[] (VMT + RTTI) }

  { RTTI property kinds (OUR codes; streaming-grade subset) }
  RTTI_KIND_INT    = 0;   { integer / ordinal / boolean / sized ints }
  RTTI_KIND_STRING = 1;
  RTTI_KIND_CLASS  = 2;
  RTTI_KIND_ENUM   = 3;   { reserved; enum name tables not emitted yet }
  RTTI_KIND_SET    = 4;   { reserved }
  RTTI_KIND_METHOD = 5;   { reserved; event/method-pointer props }

  { RTTI blob byte layouts (all fields 8 bytes) }
  RTTI_CLS_SIZE    = 80;  { name,parent,instSize,vmt,propCount,props,methCount,meths,fieldCount,fields }
  RTTI_PROP_SIZE   = 64;  { name,kind,typeRef,getKind,getRef,setKind,setRef,ordType }
  RTTI_METH_SIZE   = 16;  { name,code }
  RTTI_FIELD_SIZE  = 16;  { name,offset (published fields, for streamed child->field wiring) }

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
  AN_SET_LIT      = 37;
  AN_ASM          = 38;
  AN_PTR_CAST     = 39; { typed pointer cast PType(expr):
                            Left=inner expr, IVal=aliasIdx (AliasElemTk/Rec),
                            Tk=Ord(tyPointer) }
  AN_RTTI_REG     = 40; { __rttireg() intrinsic returning pointer to RTTI registry }
  AN_RESOURCES    = 41; { __resources() intrinsic returning pointer to resource table }
  AN_READLN       = 42; { Left = AN_ARG chain of lvalue targets (consumes a line) }
  AN_READ         = 43; { like AN_READLN; subset: also reads a fresh line }
  AN_PROCADDR     = 44; { ASTIVal = proc index; @proc → absolute code address as Pointer }
  AN_METHODREF    = 45; { @obj.method → TMethod; ASTIVal = method proc index, ASTLeft = object value }
  AN_CLASSREF     = 46; { class identifier used as a value (metaclass): ASTIVal = class index (ci);
                          yields the runtime address of the class's RTTI blob (PClassRTTI) }

  { Inline-asm operand kinds }
  AOP_NONE = 0;
  AOP_REG  = 1;
  AOP_MEM  = 2;   { [rbp+disp32] — a named local/param }
  AOP_IMM  = 3;

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
  IR_ASM          = 31;
  IR_RTTI_REG     = 32;
  IR_SET_LIT      = 33;
  IR_RESOURCES    = 34;
  IR_READLINE     = 35;  { read one line from stdin into the line buffer }
  IR_READ_VAR     = 36;  { IRA = target address; IRTk = target type; parse from buffer }
  IR_COPY_REC     = 37;  { IRA = dest addr; IRB = src addr; IRIVal = byte count (full record copy) }
  IR_PROCADDR     = 38;  { IRA = proc idx; load absolute code address of an internal proc into the result }
  IR_CLASSREF     = 39;  { IRA = class index (ci); load runtime address of the class RTTI blob (PClassRTTI) }
  IR_SET_COPY     = 40;  { IRA = dest addr; IRB = src addr; copy full 32-byte set }
  IR_SET_BINOP    = 41;  { IRA/IRB = set addresses; IRC = op; IRIVal = BSS scratch offset }
  IR_SET_CMP      = 42;  { IRA/IRB = set addresses; IRC = comparison op }
  IR_VAR_STORE    = 43;  { IRA = dest variant addr; IRB = value; IRC = source TTypeKind ord (tyVariant ord = 16-byte copy) }
  IR_VAR_BINOP    = 44;  { value: IRA/IRB = operand variant addrs; IRC = op token; IRIVal = result BSS off (arith); IRTk = tyVariant(arith)|tyBoolean(cmp) }
  IR_VAR_BOX      = 45;  { value: IRA = temp variant addr; IRB = scalar value; IRC = scalar TTypeKind ord; boxes and returns addr in rax }
  IR_COPY_REC_MANAGED = 46; { IRA = dest addr; IRB = src addr; IRC = recId; IRIVal = byte count; ARC-correct whole-record copy }
  IR_DYNDATA      = 47;  { IRA = dyn-array symbol idx; loads the data pointer from the slot (mov, never lea) }
  IR_SETLEN_DYN   = 48;  { IRA = target slot-address node; IRB = count; IRC = dyn depth; IRIVal = root dyn-array symbol idx }
  IR_DYNUNIQUE    = 49;  { IRA = slot-address node; IRB = dyn depth at this level; IRC = base record id; IRIVal = element size; IRTk = base TTypeKind. Read mode (not InLValueWrite): load data ptr. Write mode: clone-if-shared then load. Returns the (unique) data pointer in rax. }
  IR_SLOTADDR     = 50;  { IRA = symbol idx; always loads the ADDRESS of the variable's slot (lea), bypassing IR_LEA's dyn-array/AnsiString auto-load. Used as the IR_DYNUNIQUE base for a root dynamic array. }

  { Variant tag (VType) values, stored in the first 8 bytes of a tyVariant slot.
    Payload (next 8 bytes) interpreted per tag. Closed scalar set; vtObject is a
    reserved seam for the future class-boxing tier (see lib/rtl/anybox.pas). }
  VT_EMPTY   = 0;   { unassigned slot; payload ignored }
  VT_INT     = 1;   { payload = sign-extended Int64 }
  VT_INT64   = 2;   { payload = Int64 }
  VT_DOUBLE  = 3;   { payload = IEEE-754 double bits }
  VT_BOOL    = 4;   { payload = 0/1 }
  VT_CHAR    = 5;   { payload = byte in low 8 bits }
  VT_STRING  = 6;   { payload = managed AnsiString ref }
  VT_OBJECT  = 7;   { reserved: payload = pointer to boxed class/record (not yet implemented) }

  EXC_FRAME_SIZE = 80;
  EXC_JMP_OFFSET = 8;

  { Data-ref sentinel base for class-reference (metaclass) values. A fixup with
    DataOff = -(CLASSREF_DATAREF_BASE + ci) is patched to UClsRTTIOff[ci] after
    EmitRTTI, then resolved to a real address by writeELF. Must clear the -100
    (RTTI registry) / -101 (resource table) sentinels with room for every ci. }
  CLASSREF_DATAREF_BASE = 100000;

  SYS_READ  = 0;
  SYS_WRITE = 1;
  SYS_OPEN  = 2;
  SYS_CLOSE = 3;
  SYS_LSEEK = 8;
  SYS_EXIT  = 60;
  SYS_EXIT_GROUP = 231;
  SYS_BRK   = 12;
  SYS_MMAP  = 9;
  { Heap arena reserved per mmap call. We allocate via mmap, not brk, so our
    bump heap never collides with libc/GTK malloc (which owns the program
    break). 256 MB is lazily committed by the kernel — only touched pages use
    RAM. Fits in an imm32 for `add r/m64, imm32`. }
  HEAP_ARENA_SIZE = $10000000;
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
    tkHalt, tkInc, tkDec, tkLength, tkGetMem, tkFreeMem, tkOrd, tkChr, tkExit,
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
    tkNil,
    tkIn,
    tkWith,
    tkAsm,
    tkShl,
    tkPacked,
    { C declaration-specifier keywords (distinct so width/signedness/void are
      not collapsed into tkInteger_T). `int`->tkInteger_T, `char`->tkChar_T
      stay as before. }
    tkCVoid, tkCShort, tkCLong, tkCSigned, tkCUnsigned, tkCFloat, tkCDouble, tkCBool,
    tkIndent, tkDedent, tkNewline
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
    tyExtended,  { 20: Extended — 10-byte x87, load/store via x87; ops in SSE2 double }
    tySet,       { 21: Set — 32-byte bitset }
    tyVariant,    { 22: Variant — 16-byte tagged scalar value (8-byte tag + 8-byte payload) }
    tyAnsiString, { 23: Managed refcounted AnsiString }
    tyAuto        { 24: Statically typed variable with inferred type }
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
    ElemType : TTypeKind; { element type when IsArray; for dyn arrays this is the BASE element type }
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
  MAX_GENERIC_METHODS = 64;
  MAX_PENDING_SPECS = 32;
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

  { A buffered generic-class method body, kept so a specialization that is
    parsed AFTER the method (e.g. the template lives in a used unit and the
    `specialize` is in the program) can still materialise the method. }
  TGenericMethod = record
    TemplateIdx : Integer;
    TokStart    : Integer;
    TokCount    : Integer;
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

  TDataPtrFix = record
    DataPos   : Integer;   { byte offset in Data[] of the 8-byte pointer slot }
    TargetOff : Integer;   { byte offset in Data[] the slot should point at }
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
  GenericMethods     : array[0..MAX_GENERIC_METHODS-1] of TGenericMethod;
  GenericMethodCount : Integer;
  { Class specializations seen in the current type section whose template
    methods must be materialised AFTER the section closes (streaming a method —
    a `procedure ...` — inside the section would terminate it). Stored as
    indices into Specializations[] (which already holds the names/types) to
    avoid large frozen-AnsiString arrays in the compiler's own BSS. Flushed by
    ParseTypeSection. }
  PendingSpecTi    : array[0..MAX_PENDING_SPECS-1] of Integer;
  PendingSpecIdx   : array[0..MAX_PENDING_SPECS-1] of Integer;
  PendingSpecCount : Integer;
  GenericFuncCount   : Integer;
  PendingGFSpecs     : array[0..MAX_PENDING_GFSPECS-1] of TPendingGFSpec;
  PendingGFSpecCount : Integer;
  MethodFixups       : array[0..MAX_METHFIX-1] of TMethodFixup;
  MethodFixCount     : Integer;
  DataPtrFix         : array[0..MAX_DATAPTRFIX-1] of TDataPtrFix;
  DataPtrFixCount    : Integer;
  { RTTI emission state }
  UClsRTTIOff        : array[0..MAX_UCLASS-1] of Integer; { Data[] off of class RTTI hdr, -1 if none }
  RTTIRegistryOff    : Integer;  { Data[] off of registry (count slot then name/rtti ptr pairs), -1 if none }
  RTTIRegistryCount  : Integer;
  DumpRTTI           : Boolean;
  { Embedded resources (R directive: name + file); pending pairs filled by the
    lexer, blobs + table emitted post-parse by EmitResources. }
  ResPendName        : array[0..MAX_RESOURCES-1] of AnsiString;
  ResPendFile        : array[0..MAX_RESOURCES-1] of AnsiString;
  ResPendCount       : Integer;
  ResourceTableOff   : Integer;  { Data[] off of resource table (count slot then name/data/len triples), -1 if none }
  ResourceCount      : Integer;
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
  StrictOverload : Boolean;
  ThreadSafeMode : Boolean;
  EnableAutoVar : Boolean;
  CStyleComments : Boolean;   { CSTYLECOMMENTS directive: enable C slash-star comments }
  NestedComments : Boolean;   { NESTEDCOMMENTS directive: nest brace and paren-star comments }
  CaseSensitiveMode : Boolean; { CASESENSITIVE directive: when on, identifiers declared here match case-sensitively. Default off (standard case-insensitive Pascal). }
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

  { @proc: code-side `mov rax, imm64` placeholders patched at finalize with the
    absolute runtime address of an internal proc (entry + BodyAddr). }
  ProcAddrFix : array[0..MAX_CALLFIX-1] of TCallFix;
  ProcAddrFixCount : Integer;

  Syms      : array[0..MAX_SYMS-1]  of TSymbol;
  SymCaseSensitive : array[0..MAX_SYMS-1] of Boolean; { match this symbol name case-sensitively }
  SymUnitIdx : array[0..MAX_SYMS-1] of Integer; { Strs[] unit name, or -1 for main/local compiler-generated symbols }
  SymDynDepth : array[0..MAX_SYMS-1] of Integer; { dynamic-array nesting: 0=not dynamic, 1=array of T, 2=array of array of T, ... }
  SymIsHiddenArgTemp : array[0..MAX_SYMS-1] of Boolean; { compiler-synthesised owning local for a materialised managed-string call argument; needs nil-init before the body }
  SymCount  : Integer;
  FrameSize : Integer;

  Procs     : array[0..MAX_PROCS-1] of TProc;
  ProcOverloadDirective : array[0..MAX_PROCS-1] of Boolean;
  ProcCount : Integer;
  CurProc   : Integer;   { -1 = main }
  ProcExternal : array[0..MAX_PROCS-1] of Boolean;
  ProcCaseSensitive : array[0..MAX_PROCS-1] of Boolean; { match this proc name case-sensitively (C imports, or Pascal in case-sensitive mode) }
  ProcLibrary  : array[0..MAX_PROCS-1] of Integer; { Strs[] entry for DT_NEEDED name }
  ProcUnitIdx : array[0..MAX_PROCS-1] of Integer; { Strs[] unit name, or -1 for main }
  ProcRetRecId : array[0..MAX_PROCS-1] of Integer; { record id for tyRecord results }
  ProcAggregateDestSym : array[0..MAX_PROCS-1] of Integer; { hidden caller-result pointer local, or -1 }
  ProcRetIsDynArray : array[0..MAX_PROCS-1] of Boolean; { result is `array of T` (pointer-sized heap handle) }
  ProcRetElemTk : array[0..MAX_PROCS-1] of TTypeKind;    { element type of a dyn-array result }
  ProcRetElemRec : array[0..MAX_PROCS-1] of Integer;     { element record id of a dyn-array result }
  ProcRetPtrElemTk : array[0..MAX_PROCS-1] of Integer;   { pointed-at TTypeKind ord when the result is a typed pointer (tyUnknown otherwise) }
  ProcRetPtrElemRec : array[0..MAX_PROCS-1] of Integer;  { pointed-at record id when the result is a typed pointer-to-struct }
  ProcParamPtrDepth : array[0..MAX_PARAM_DEPTHS-1] of Integer; { C interop: pointer depth for parameters }
  CurrentCLibrary : AnsiString;
  CTypeIsVoid : Boolean; { last ParseCDeclType saw bare void (no pointer) }
  CTypePtrDepth : Integer;   { pointer-star count of the last ParseCDeclType (0 = not a pointer) }
  CTypeElemTk : Integer;     { pointed-at TTypeKind ordinal when CTypePtrDepth>0 (tyPointer for depth>=2) }
  CTypeElemRec : Integer;    { pointed-at record id when the element is a struct, else REC_NONE }
  CTypeBaseRec : Integer;    { record id of the base type before any pointer suffix, else REC_NONE }
  CHeaderMode : Boolean; { parsing C in header/FFI mode }
  CTypedefCount : Integer;
  CTypedefNameOff : array[0..MAX_CTYPEDEF-1] of Integer;
  CTypedefNameLen : array[0..MAX_CTYPEDEF-1] of Integer;
  CTypedefTk    : array[0..MAX_CTYPEDEF-1] of Integer; { resolved TTypeKind ordinal }
  CTypedefElemTk : array[0..MAX_CTYPEDEF-1] of Integer; { pointer typedef: pointed-at TTypeKind ordinal }
  CTypedefRec   : array[0..MAX_CTYPEDEF-1] of Integer;  { struct typedef: record id; pointer typedef: elem record id }
  { Open-addressed name->index hash for O(1) FindCTypedef. Stores idx+1 so the
    zero-initialised state means "empty" (no -1 fill needed). Size is a power of
    two > 2*MAX_CTYPEDEF for a <=0.5 load factor. }
  CTypedefHash  : array[0..16383] of Integer;
  { C struct/union tag namespace (separate from typedefs): tag name -> record id.
    Lets `struct Tag` resolve, bare tagged structs lay out, and a struct
    self-reference (`struct Node *next;` inside Node) work via forward tags. }
  CTagCount   : Integer;
  CTagNameOff : array[0..MAX_CTYPEDEF-1] of Integer;
  CTagNameLen : array[0..MAX_CTYPEDEF-1] of Integer;
  CTagRec     : array[0..MAX_CTYPEDEF-1] of Integer;  { REC_UCLASS_BASE + ci }
  CTagChars   : array[0..524287] of Char;
  CTagCharLen : Integer;
  CTagHash    : array[0..16383] of Integer;  { name->idx+1 (0=empty), O(1) tag lookup }
  CTypedefChars : array[0..524287] of Char;
  CTypedefCharLen : Integer;
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
  DynamicNeededCount : Integer; { distinct DT_NEEDED libraries }
  LastTypeRecId : Integer;
  LastTypePointerElemTk : TTypeKind;
  LastTypePointerElemRec : Integer;
  ErrorIdent : AnsiString;
  LastExprTk : TTypeKind;
  InInterface : Boolean;
  CompiledUnits : array[0..255] of Integer;
  CompiledUnitCount : Integer;
  CurrentUnitIdx : Integer; { Strs[] name while parsing an imported unit, else -1 }
  { Synthesized unit initialization procs, in dependency (post-uses) order.
    Called at program entry before the main body so unit globals get set up. }
  InitProcs : array[0..255] of Integer;
  InitProcCount : Integer;
  SourceFileDir : AnsiString;
  { Base name (no dir, no ext) of the source file currently being lexed; used to
    resolve the `*` in $R *.lfm / $R *.res to the current unit. }
  CurSrcBaseName : AnsiString;
  { Directory of the compiler binary itself (from ParamStr(0)); RTL/LCL units are
    located relative to it so the compiler works from any CWD, not just the repo
    root. Empty if the path has no directory part (then CWD-relative is used). }
  ExeDir : AnsiString;
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
  WithStack: array[0..31] of Integer;
  WithStackDepth: Integer;
  AsmBytes: array[0..65535] of Byte;
  AsmBytesCount: Integer;
  { Inline-asm operand scratch (slot 0 = dest, slot 1 = src) }
  AsmOpKind : array[0..1] of Integer;   { AOP_* }
  AsmOpReg  : array[0..1] of Integer;   { register number 0..15 }
  AsmOpSize : array[0..1] of Integer;   { 1, 2, 4, 8 (bytes) }
  AsmOpVal  : array[0..1] of Int64;     { immediate value, or mem disp for AOP_MEM }
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
  CPActiveMacros : array[0..63] of Integer;
  CPActiveMacroCount : Integer;
  CPTempStr0, CPTempStr1, CPTempStr2, CPTempStr3, CPTempStr4, CPTempStr5, CPTempStr6, CPTempStr7,
  CPTempStr8, CPTempStr9, CPTempStr10, CPTempStr11, CPTempStr12, CPTempStr13, CPTempStr14, CPTempStr15,
  CPTempStr16, CPTempStr17, CPTempStr18, CPTempStr19, CPTempStr20, CPTempStr21, CPTempStr22, CPTempStr23,
  CPTempStr24, CPTempStr25, CPTempStr26, CPTempStr27, CPTempStr28, CPTempStr29, CPTempStr30, CPTempStr31,
  CPTempStr32 : AnsiString;
  CPExpandedArg0, CPExpandedArg1, CPExpandedArg2, CPExpandedArg3, CPExpandedArg4, CPExpandedArg5, CPExpandedArg6, CPExpandedArg7,
  CPExpandedArg8, CPExpandedArg9, CPExpandedArg10, CPExpandedArg11, CPExpandedArg12, CPExpandedArg13, CPExpandedArg14, CPExpandedArg15,
  CPExpandedArg16, CPExpandedArg17, CPExpandedArg18, CPExpandedArg19, CPExpandedArg20, CPExpandedArg21, CPExpandedArg22, CPExpandedArg23,
  CPExpandedArg24, CPExpandedArg25, CPExpandedArg26, CPExpandedArg27, CPExpandedArg28, CPExpandedArg29, CPExpandedArg30, CPExpandedArg31,
  CPExpandedArg32 : AnsiString;
  PackRecordsVal : Integer;
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
  BSS_FREE_LIST   : Integer;  { head of GetMem/FreeMem free list; 0 = empty (BSS zero-init) }
  BSS_HEAP_LOCK   : Integer;  { spinlock for heap allocations }
  BSS_EXC_TOP     : Integer;
  BSS_EXC_OBJ     : Integer;
  BSS_EXC_CLS     : Integer;
  BSS_LINE_BUF    : Integer;  { readln line buffer }
  BSS_LINE_LEN    : Integer;  { bytes currently in line buffer }
  BSS_LINE_POS    : Integer;  { parse cursor into line buffer }
  ExceptionUsed   : Boolean;
  InLValueWrite   : Boolean;
  ExcSetJmpAddr   : Integer;
  ExcLongJmpAddr  : Integer;
  ExcRaiseAddr    : Integer;
  AnsiStrReleaseAddr : Integer;
  AnsiStrRetainAddr  : Integer;
  AnsiStrFromLiteralAddr : Integer;
  AnsiStrUniqueAddr : Integer;
  AnsiStrConcatAddr : Integer;
  AnsiStrLoadFileAddr : Integer;

  TokChars   : array[0..STRING_CAP-1] of Char;
  TokCharLen : Integer;
  Tokens     : array[0..MAX_TOKENS-1] of TRawToken;
  TokPackRecords : array[0..MAX_TOKENS-1] of Integer;
  TokCount   : Integer;
  TokPos     : Integer;
  MainProgramTokCount : Integer;
  PyExprMode : Boolean;  { True only while parsing Nil Python expressions: gives `and`/`or`/`not`
                           Python precedence (below comparison) via PyParseBoolExpr; suppressed
                           in Pascal RTL units pulled in by .npy programs }

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
  ASTLiftedVar : array[0..MAX_AST-1] of Integer; { symbol index of compiler-lifted variable, or -1 }
  ASTNodeCount : Integer;

  IRKind  : array[0..MAX_IR-1] of Integer;
  IRA     : array[0..MAX_IR-1] of Integer;
  IRB     : array[0..MAX_IR-1] of Integer;
  IRC     : array[0..MAX_IR-1] of Integer;
  IRIVal  : array[0..MAX_IR-1] of Int64;
  IRTk    : array[0..MAX_IR-1] of Integer;
  IRSetLenBaseRec : array[0..MAX_IR-1] of Integer; { IR_SETLEN_DYN on a non-symbol (field) target: base element record id when IRIVal<0; -1/REC_NONE otherwise }
  { Marks an IR node as a statement root (its result is discarded). The top-
    level emitter only emits roots; calls whose value is consumed are emitted
    via their parent. Needed for IR_VIRTUAL_CALL, whose IRIVal holds the VMT
    slot and so cannot double as the IR_CALL=1 statement flag. }
  IRStmtRoot : array[0..MAX_IR-1] of Boolean;
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
  UClsAlign  : array[0..MAX_UCLASS-1] of Integer;
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
  UFldIsArray : array[0..MAX_UFIELD-1] of Boolean;
  UFldArrLen  : array[0..MAX_UFIELD-1] of Integer;
  UFldDynDepth : array[0..MAX_UFIELD-1] of Integer; { dynamic-array field nesting: 0 = not a dynamic array, 1 = array of T, 2 = array of array of T, ... (UFldArrLen = -1 also marks dynamic, mirroring the symbol convention) }
  UFldPub    : array[0..MAX_UFIELD-1] of Integer;  { 1 = published, 0 = other }
  UFldCount  : Integer;

  UMthNOff   : array[0..MAX_UMETH-1] of Integer;
  UMthNLen   : array[0..MAX_UMETH-1] of Integer;
  UMthProc_  : array[0..MAX_UMETH-1] of Integer;
  UMthVirSlot : array[0..MAX_UMETH-1] of Integer;
  UMthIsStatic : array[0..MAX_UMETH-1] of Boolean;
  UMthPub    : array[0..MAX_UMETH-1] of Integer;  { 1 = published, 0 = other }
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
  UPropPub    : array[0..MAX_UPROP-1] of Integer;  { 1 = published, 0 = other }
  UPropEnumId : array[0..MAX_UPROP-1] of Integer;  { enum type index if prop is enum-typed, else -1 }
  UPropSetEnumId : array[0..MAX_UPROP-1] of Integer;  { element enum type index if prop is set-typed, else -1 }
  UPropCount  : Integer;

  { Named enum types (ordinal<->name). Enum vars stay integer-sized; this table
    only records identity + value names for RTTI/streaming. }
  EnumTypeNOff    : array[0..MAX_ENUMTYPE-1] of Integer;  { type name in TokChars }
  EnumTypeNLen    : array[0..MAX_ENUMTYPE-1] of Integer;
  EnumTypeValBase : array[0..MAX_ENUMTYPE-1] of Integer;  { into EnumVal* arrays }
  EnumTypeValCount: array[0..MAX_ENUMTYPE-1] of Integer;
  EnumTypeRTTIOff : array[0..MAX_ENUMTYPE-1] of Integer;  { Data[] off, -1 }
  EnumTypeCount   : Integer;
  EnumValNOff     : array[0..MAX_ENUMVAL-1] of Integer;   { value name in TokChars }
  EnumValNLen     : array[0..MAX_ENUMVAL-1] of Integer;
  EnumValCount    : Integer;
  LastTypeEnumId  : Integer;  { set by ParseTypeKind: enum type index or -1 }
  LastTypeSetEnumId : Integer;  { set by ParseTypeKind for set types: element enum index or -1 }

  { Named type aliases. Phase 2: pointer aliases (PFoo = ^TFoo) carry an element
    type so the deref/index machinery knows what they point at. }
  AliasNOff    : array[0..MAX_TYPEALIAS-1] of Integer;  { alias name in TokChars }
  AliasNLen    : array[0..MAX_TYPEALIAS-1] of Integer;
  AliasTk      : array[0..MAX_TYPEALIAS-1] of Integer;  { resolved TTypeKind ordinal }
  AliasElemTk  : array[0..MAX_TYPEALIAS-1] of Integer;  { pointer element TTypeKind ordinal }
  AliasElemRec : array[0..MAX_TYPEALIAS-1] of Integer;  { pointer element record/class id }
  AliasCount   : Integer;

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
  if Result < 0 then
    writeln('fpRead fd=', fd, ' count=', count, ' failed with errno=', fpGetErrno);
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

var
  isC, isBasic, isNilPy: Boolean;
