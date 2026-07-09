{ SPDX-License-Identifier: MPL-2.0 }
const

  MAX_CODE      = 8388608;  { 8 MB; arm32's literal-pool-heavy self-host code exceeds 4 MB }
  LOCAL_STR_CAP = 256;     { max string length for local/stack variables }
  DEFAULT_STR_CAP = 255;   { default capacity (max chars) for tyFixedString/tyShortString when no string[N] size given }
  LINE_BUF_SIZE = 4096;    { readln stdin line buffer }
  MAX_DATA    = 2097152;      { 2 MB }
  MAX_STRS    = 8192;
  MAX_FIXUPS  = 131072;
  MAX_SYMS    = 131072;
  MAX_PROCS   = 16384;
  PROC_HASH_SIZE = 16384;  { FindProc hash buckets; power of two (mask below) }
  SYM_HASH_SIZE  = 65536;  { FindSym hash buckets; power of two }
  MAX_PROC_PARAMS = 32;
  MAX_INLINE_LOCALS = 8;   { max callee locals in a slice-2b (-O3) inline body }
  MAX_CALL_ARGS = 128;
  MAX_PARAM_DEPTHS = MAX_PROCS * MAX_PROC_PARAMS;
  MAX_CALLFIX = 16384;
  MAX_GLOBFIX = 65536;
  MAX_ASM_GLOBFIX = 4096;
  MAX_INLINE_ASM_LINES = 4096;
  MAX_INLINE_ASM_HOLES = 1024;
  MAX_EXTERNAL = 16384;
  MAX_ASM_OBJ_CALLFIX = 4096;   { .asm frontend -c: extern calls needing an R_X86_64_PLT32 relocation }
  MAX_ASM_GLOBALS = 64;         { .asm frontend: distinct `global <label>` declarations }
  MAX_CPREP_MACROS = 32768;
  CPREP_MACRO_HASH_SIZE = 16384;   { power of two; ~half-full at MAX macros }
  MAX_DECL_NAMES = 256;  { comma-separated names in one var declaration line }
  MAX_ARR_DIMS = 6;      { max dimensions of a fixed multidimensional array }
  MAX_PENDING_INITS = 16384;  { constant global-var initializer assignments }
  MAX_LOCAL_INITS   = 4096;   { routine-local typed-const initializer assignments }
  MAX_CPREP_PARAMS = 131072;
  MAX_CPREP_CONDS = 256;
  MAX_CPREP_INCLUDES = 128;
  MAX_CPREP_CHARS = 8388608;  { 8 MB }
  MAX_C_INCLUDE_DIRS = 64;    { user `-I` C include search roots }
  MAX_PAS_UNIT_DIRS  = 64;    { user `-Fu`/`-I` Pascal unit search roots }
  MAX_CPREP_ARGS = 4096;
  STRING_CAP  = 8388608;      { 8 MB }
  MAX_TOKENS  = 2097152;
  MAX_AST     = 524288;
  { Top slice of the AST pool reserved for retained inline-routine bodies
    (feature-inline-routines). Per-proc AST allocation (AllocNode) uses
    [0..INLINE_AST_BASE); retained inline bodies live in
    [INLINE_AST_BASE..MAX_AST) and are NOT cleared by the per-proc reset. }
  INLINE_AST_BASE = 516096;   { MAX_AST - 8192 }
  MAX_IR      = 131072;
  MAX_STACK_FRAME_SIZE = 1048576; { default --max-stack-frame threshold: warn when a
                                    routine's stack frame exceeds 1 MB. Locals live on
                                    the stack (~8 MB total, shared by the whole call
                                    chain); a single fat frame risks overflow as a
                                    runtime SIGSEGV (e.g. the FPC-seed 8 MB-local bug,
                                    project_fpc_seed_segfault_done). 0 disables. }
  MAX_OPEN_ARRAY_STACK_TEMP = 65536; { bug-const-open-array-param-stack-copies-caller-frame:
                                    a fixed array passed to an `array of T` open-array
                                    parameter needs a `[len:8][data]`-shaped temp built
                                    in the CALLER's frame. Below this size (64 KB) it's
                                    a frame/BSS-local buffer (fast, auto-frees, proven
                                    correct/leak-free) same as always; above it, a
                                    managed heap dyn-array temp instead (bounded, never
                                    grows the caller's frame regardless of the source
                                    array's size, released automatically at scope exit).
                                    The compiler's own source never crosses this
                                    threshold, so self-host/cross-bootstrap never
                                    exercise the heap path — it's addressable only by
                                    user code hitting the large-array shape. }
  MAX_DWARF      = 1048576;   { DWARF -g: byte buffer for all .debug_* section content }
  MAX_DWARF_ROWS = 131072;    { DWARF -g: (code-offset, line) rows for the .debug_line program }
  MAX_DBG_VARS   = 16384;     { DWARF -g: snapshotted params/locals/globals (Tier 3) }
  MAX_DBG_TYPES  = 4096;      { DWARF -g: distinct type DIEs }
  MAX_LOOP_FIXUPS = 256;
  MAX_GOTO_LABELS = 2048; { was 64 — a stackless generator burns ~1 label per
                            yield + 2-3 per flattened if/while/for/case; chess's
                            GenMoves alone needs several hundred }
  MAX_DECL_ITEMS = 32768;       { top-level subroutine items recorded by the declaration pre-scan }
  MAX_PAS_DEFINES = 1024;       { jedi.inc-grade compatibility headers define hundreds }
  MAX_PAS_DEFINE_CHARS = 32768;
  MAX_PAS_CONDS = 64;
  SPECIAL_IN  = 999;

  MAX_UCLASS      = 2048;  { user-defined class/record slots (incl. imported C structs) }
  MAX_UFIELD      = 262144; { field slots across all user classes/records }
  MAX_UMETH       = 8192;  { method slots across all user classes }
  MAX_IMT         = 512;   { per-(class,interface) interface method tables }
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
  AN_VAR_DECL     = 47;
  AN_DEFAULT      = 48;
  AN_SYSCALL      = 49; { __pxxrawsyscall(nr, a0..a5): Int64; Left = AN_ARG chain (1..7 args) }
  AN_VARREC_ARRAY = 50; { `array of const` literal: Left = AN_ARG chain of element
                          exprs, IVal = TVarRec record id. Lowers to a heap
                          dyn-array of TVarRec; yields the data-pointer handle. }
  AN_COSWITCH     = 51; { __pxxcoswitch(pfrom, pto: Pointer): low-level coroutine
                          context switch. Left = AN_ARG chain of 2 pointer exprs
                          (address of the from/to TCoroCtx). Calls the bare
                          CoSwitch runtime stub. }
  AN_YIELD        = 52; { yield E inside a `; generator;` routine. Left = value
                          expr. Lowers to: store E into the generator instance's
                          `current` slot, then CoSwitch back to the consumer. }
  AN_CALL_IND     = 53; { Indirect call through a procedural-type value:
                          v(args) where v is a proc-typed var. ASTLeft = AN_ARG
                          chain; ASTRight = callee expr (yields the code address);
                          ASTIVal = signature proc index (param/ret marshalling). }
  AN_AWAIT        = 54; { await E inside an `; async;` routine. Left = awaited
                          expr. STACKFUL (default): documentary — lowers straight
                          to its operand (the underlying call suspends on its own
                          via the reactor/CoYield). STACKLESS (later): the marker
                          that bounds the state-machine split locally. }
  AN_STR_FROM_CHAR = 55; { String(c) rvalue: materialise a 1-char string. Left =
                           char expr; ASTIVal = hidden string temp sym. Lowered in
                           shared IR by reusing the `s := c` store + a var read. }
  AN_IS_TEST       = 56; { `X is T`: Left = instance expr; ASTIVal = target class ci.
                           Boolean = X's VMT is T's or a descendant's (closed-world). }
  AN_AS_CAST       = 57; { `X as T`: Left = instance expr; ASTIVal = target class ci.
                           Checked downcast — yields X typed as T, traps on mismatch. }
  AN_INTF_CALL     = 58; { CORBA interface method call `iface.M(args)`. Left = arg
                           chain; Right = interface value (fat ptr {IMT,instance});
                           ASTIVal = signature proc idx; ASTSOffset = IMT slot. }
  AN_INTF_FROM_CLASS = 59; { class -> interface fat-pointer build. Left = class
                             instance expr; ASTIVal = IMT-table entry index. }
  AN_SET_INCL      = 60; { Include(s, v): Left = set lvalue, Right = value expr. }
  AN_SET_EXCL      = 61; { Exclude(s, v): Left = set lvalue, Right = value expr. }
  AN_DYN_COPY      = 62; { Copy(arr, index [, count]) over a dynamic array → fresh
                           array of T. Left = source array ident; Right = AN_ARG
                           chain [index, count]. }
  AN_DYN_DELETE    = 74; { Delete(arr, index, count) over a dynamic array → fresh
                           array of T with the range removed (assigned back onto
                           arr by the parser's AN_ASSIGN wrapper). Left = source
                           array ident; Right = AN_ARG chain [index, count]. }
  AN_SET_SIGNAL    = 76; { SetSignalHandler(sig, @proc) statement: Left = signal
                           number expr, Right = handler address expr (nil/0
                           reverts to default disposition on next delivery).
                           Lowers to IR_SET_SIGNAL. }
  AN_DYN_INSERT    = 75; { Insert(value, arr, index) over a dynamic array → fresh
                           array of T with value inserted (assigned back via
                           AN_ASSIGN like AN_DYN_DELETE). Left = source array
                           ident; Right = AN_ARG chain [value, index]. }
  AN_CLASS_CAST    = 63; { TClass(expr): hard reinterpret class typecast (no
                           runtime check, unlike AN_AS_CAST). Left = instance
                           expr; ASTIVal = target class ci. Classes are pointers
                           so the value passes through unchanged; the tag exists
                           so trailing .field/[i] resolve offsets against TClass
                           (ResolveNodeRec maps it to REC_UCLASS_BASE+ci). }
  AN_ARRAY_CTOR    = 64; { `[e0, e1, ...]` passed to an `array of T` (scalar/string
                           element) parameter: Left = AN_ARG element chain, ASTIVal
                           = element TTypeKind ord. Lowers to a heap dyn-array temp
                           (alloc + SetLength + per-element store) whose handle is
                           the open-array argument — mirror of AN_VARREC_ARRAY for
                           plain (non-TVarRec) elements. }
  AN_SET_CONST_REF = 66; { named set constant used as a value: ASTIVal = Data[]
                           offset of the baked 32-byte mask. Lowers to IR_SET_LIT
                           (same blob-address value a set literal yields). }
  AN_INCDEC        = 69; { C pre/post increment/decrement. Left = lvalue;
                           ASTIVal = +1 / -1 (scaled by element size for a
                           pointer); ASTSOffset = 1 for postfix (yield OLD value),
                           0 for prefix (yield NEW value). Lowers via the
                           evaluate-lvalue-address-once primitive. }
  AN_COMPOUND_ASSIGN = 70; { C assignment expression yielding a value. Left =
                           lvalue, Right = rhs, ASTIVal = the binop token
                           (tkPlus/tkMinus/tkStar/tkSlash...) for `+=` etc, or
                           Ord(tkAssign) for a plain value-bearing `=`/`:=`
                           (right-assoc, so `a = b = c` nests on the Right). The
                           lvalue address is computed ONCE; yields the stored
                           value. }
  AN_COMMA         = 68; { C comma operator `(a, b)`: evaluate Left for its side
                           effects (value discarded), yield Right's value.
                           Right-nested for `(a,b,c)`. ASTTk = Right's type. Only
                           produced by the C frontend and Pascal's parenthesised
                           comma form (a syntax error otherwise) — never in
                           compiler source, so self-host stays byte-identical. }
  AN_TERNARY       = 67; { value-bearing conditional expression `c ? a : b`
                           (C frontend) / `if c then a else b` expression form.
                           Left = condition; Right = AN_PAIR(then-arm, else-arm).
                           ASTTk = result type. Short-circuit: only the selected
                           arm is evaluated. Lowers to JUMP_IF_FALSE/labels with
                           each arm stored into one hidden temp, yielding a load
                           (see ir.inc). Pascal's own parser only emits it for the
                           explicit if-expression; never in compiler source, so
                           self-host stays byte-identical. }
  AN_METACLASS_NEW = 65; { metaclass-dispatched construction `classRefVar.Create(..)`:
                           Left = AN_ARG chain of explicit ctor args (NO Self);
                           Right = classref value node (yields the RTTI blob ptr);
                           ASTIVal = ctor proc idx (param signature); ASTSOffset =
                           ctor VMT slot (-1 if non-virtual). Allocates the DYNAMIC
                           class (size=[cref+16], vmt=[cref+24]) then runs the
                           virtual ctor through the stamped VMT. }
  AN_SWITCH        = 71; { C `switch (sel) { body }`: Left = selector expr; Right =
                           AN_BLOCK body whose statement SEQ contains AN_CASE (17) /
                           AN_DEFAULT (48) marker nodes — shared with the Pascal
                           case/default node kinds. Lowered to a dispatch (compare
                           selector vs each case, jump to its label) + the body in
                           order (fallthrough), with a break-only scope. }
  AN_ATOMIC        = 73; { __pxxatomic_xchg/cas/add(addr, ...): Int64. 32-bit atomic
                           read-modify-write on addr^. ASTIVal = op (ATOMIC_XCHG/CAS/ADD);
                           Left = AN_ARG chain (addr, then 1 or 2 operands). Lowers to
                           IR_ATOMIC; x86-64 emits a lock-prefixed rmw and returns the
                           OLD value. The atomic substrate for futex sync primitives. }
  ATOMIC_XCHG = 0;  { xchg [addr], val          -> old (xchg to mem is implicitly locked) }
  ATOMIC_CAS  = 1;  { lock cmpxchg [addr]; args (addr, expected, newval) -> old }
  ATOMIC_ADD  = 2;  { lock xadd [addr], delta   -> old }
  ATOMIC_XCHG64 = 3;  { 64-bit variants of the above (full-width [addr] rmw) }
  ATOMIC_CAS64  = 4;
  ATOMIC_ADD64  = 5;

  AN_SLOTADDR      = 77;
  AN_INLINE_PARAM  = 78;  { placeholder inside a RETAINED inline body: IVal = param index. Only exists in the reserved inline AST region; substituted to an AN_IDENT of the caller's arg temp when the body is cloned into a call site. Never reaches IRLowerAST directly. }
  AN_INLINE_LOCAL  = 79;  { placeholder for a callee LOCAL: IVal = local index (slice 2b, -O3). Substituted to an AN_IDENT of a fresh caller local. }
  AN_INLINE_RESULT = 80;  { placeholder for the callee Result (slice 2b, -O3). Substituted to an AN_IDENT of the caller Result temp. } { address of a variable's own stack/BSS slot (lea),
                           bypassing the by-ref auto-deref an AN_ADDR on a var/
                           const param gets in IRLowerAddress. ASTIVal = Syms[]
                           idx; yields tyPointer. Lowers to IR_SLOTADDR. Used by
                           the stackless-generator transform to save/restore a
                           by-ref param's POINTER WORD itself (a plain AN_ASSIGN
                           to an IsRef sym stores THROUGH the caller's address). }

  AN_CLONE         = 72; { __pxxclone(flags, childStack, entry, arg, ctidptr): Int64.
                           Left = AN_ARG chain (exactly 5). Lowers to IR_CLONE: moves
                           the args into the SysV arg regs and calls the bare clone+
                           trampoline stub (thread_emit.inc). Returns the child tid in
                           the parent; never returns in the child (runs entry(arg) then
                           SYS_exit). The one machine-code piece of libc-free threading. }

  { Inline-asm operand kinds }
  AOP_NONE   = 0;
  AOP_REG    = 1;
  AOP_MEM    = 2;   { [rbp+disp32] — a named local/param }
  AOP_IMM    = 3;
  AOP_GLOBAL = 4;   { absolute [disp32] — a named global var, BSS-relative }
  AOP_MEMR   = 5;   { explicit [reg], [reg+disp], [reg+reg*scale+disp] }

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
  IR_ZERO_SYM     = 51;
  IR_DEFAULT_MEM  = 52;  { IRA = dest addr node; IRC = managed record id or REC_NONE; IRIVal = bytes to zero }
  IR_READ_DISCARD = 53;
  IR_SYSCALL      = 54;  { IRA = first IR_ARG (nr, then up to 6 args); raw target syscall; result in accumulator }
  IR_COSWITCH     = 55;  { IRA = first IR_ARG (pfrom, pto); emits a call to the bare CoSwitch runtime stub }
  IR_YIELD        = 56;  { IRA = value node; IRIVal = generator self-pointer local sym idx. Stores value to [self+16] then CoSwitch(self+0 -> self+8) }
  IR_CALL_IND     = 57;  { Indirect call. IRA = callee value node (code addr); IRB = first IR_ARG; IRIVal = signature proc index (Params/RetType); IRStmtRoot marks a statement-level call (result discarded) }
  IR_VMTADDR      = 58;  { IRA = class index (ci); load the runtime address of that class's VMT (= the per-class identity stored at [instance+0]). Used by is/as type-tests. }
  IR_IMTADDR      = 59;  { IRA = IMT-table entry index; load the runtime address of that (class,interface) Interface Method Table. Captured as the fat pointer's first word. }
  IR_STORE_DYN    = 60;  { ARC-correct whole dyn-array store into a slot ADDRESS (record/class field or nested sub-array). IRA = slot-address node; IRB = new handle value node; IRC = dyn depth; IRIVal = -1 (non-symbol → node-derived descriptor); IRTk = base TTypeKind; IRSetLenBaseRec = base record id. Retains the new handle, publishes it, element-aware releases the old. x86-64 only; other targets keep the IR_STORE_MEM share path. }
  IR_SETLEN_STR   = 61;  { SetLength on a managed AnsiString reached through ANY lvalue (symbol, record/class field, var-param field, index, deref). IRA = target slot-ADDRESS node (IRLowerAddress of the lvalue → &handle slot); IRB = new length count node. Calls PXXStrSetLen(addr, n). Address-based so a field/var-param target needs no symbol reconstruction — the managed-string analogue of IR_SETLEN_DYN. Frozen inline strings (tyString, the self-host model) keep the -101 store-length path; only tyAnsiString reaches here. }
  IR_CLONE        = 62;  { IRA = first IR_ARG (flags, childStack, entry, arg, ctidptr — exactly 5); moves them into the SysV arg regs and calls the bare clone+trampoline stub (CloneStubAddr). Result (child tid) in the accumulator. Libc-free thread creation; x86-64 first, i386 next. }
  IR_ATOMIC       = 63;  { IRIVal = op (ATOMIC_XCHG/CAS/ADD); IRA = IR_ARG chain (addr, then operands). x86-64 emits a 32-bit lock-prefixed read-modify-write on addr^ and returns the OLD value in the accumulator. Substrate for futex mutexes/atomic counters. }
  IR_EXC_MATCH_HIT = 64; { Positive-polarity sibling of IR_EXC_MATCH: IRA = label, IRIVal = class id; jumps to the label when the raised class EQUALS the id (vs. IR_EXC_MATCH's jump-away-on-mismatch). Used to chain "raised class is any descendant of the handler's target class" checks -- see IsClassDescOrSelf's usage in AN_TRY_EXCEPT lowering. }
  IR_SET_SIGNAL    = 65; { SetSignalHandler(sig, @proc): IRA = signal-number value node, IRB = handler-address value node (0/nil = revert to default on next delivery). Lowers to a call of the emitted SigSetHook stub (store hook slot + rt_sigaction install). x86-64 Linux only; other targets Error at codegen. }
  IR_IO_LOCK       = 66; { --threadsafe statement-atomic console I/O: acquire the reentrant owner-tid I/O spinlock (BSS_IO_OWNER/BSS_IO_DEPTH). Emitted by AN_WRITE/AN_WRITELN/AN_READ* lowering around the whole statement, x86-64 + ThreadSafeMode only. Reentrant so a write-arg calling a writing function cannot self-deadlock. }
  IR_IO_UNLOCK     = 67; { release the I/O statement lock (depth-counted; owner cleared at depth 0). }
  IR_CONST_DATA    = 68; { generic data-reference constant: IRIVal = Data[] offset OR a negative dataref sentinel (RECORD_RTTI/CLASSREF/SYM_RTTI bases, resolved by the pre-link fixup pass). Value = absolute data address in the accumulator. Lets IR-level CALLS pass descriptor addresses (e.g. a record layout descriptor to PXXDynArrayRetainImmediate) instead of needing a bespoke per-backend op. }

  { Generator-instance heap layout (see lib/rtl/coroutine.pas + the generator
    body lowering). A TCoroCtx is a single saved sp, so genCtx/callerCtx are one
    qword each. CO_OFF_SELF doubles as the rbx-slot handoff in the initial frame
    (CoAlloc stores the instance ptr there; CoSwitch pops it into rbx; the body
    prologue copies rbx -> its hidden self local). }
  CO_OFF_GENCTX    = 0;    { gen context saved sp }
  CO_OFF_CALLERCTX = 8;    { consumer context saved sp }
  CO_OFF_CURRENT   = 16;   { last yielded value (<= 8 bytes in v1) }
  CO_OFF_DONE      = 24;   { 0 = suspended/live, 1 = exhausted }
  CO_OFF_STACKBASE = 32;   { heap stack base, for FreeMem at exhaustion }
  CO_OFF_SELF      = 40;   { instance ptr (= rbx-slot handoff) }
  CO_OFF_PARAMS    = 48;   { first generator parameter; params are 8 bytes each }
  CO_HDR_BYTES     = 48;   { header size before params }
  CO_STACK_BYTES   = 65536;{ per-generator heap stack }
  CO_MAX_PARAMS    = 4;    { v1: generators take up to 4 (Int64-width) params }

  { Stackless-generator instance layout (see lib/rtl/slgen.pas + the stackless
    state-machine transform in parser.inc). Shares CURRENT/DONE offsets with the
    stackful layout so for-in reads the value/done flag identically for either
    strategy; only the advance step differs (CoSwitch vs a direct step call).
    SL_OFF_STATE reuses the unused GENCTX slot. Persistent slots (declared params
    then body locals, one machine word each) start at SL_OFF_SLOTS. }
  SL_OFF_STATE     = 0;    { resume state; 0 = not yet started }
  SL_OFF_CURRENT   = 16;   { = CO_OFF_CURRENT }
  SL_OFF_DONE      = 24;   { = CO_OFF_DONE }
  SL_OFF_SLOTS     = 48;   { = CO_OFF_PARAMS; params+locals, 8 bytes each }
  MAX_GEN_STATES   = 1024; { max yields in one stackless generator body }

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
  EXC_FRAME_SIZE_386 = 32;
  EXC_JMP_OFFSET_386 = 8;
  EXC_FRAME_SIZE_ARM32 = 48;
  EXC_JMP_OFFSET_ARM32 = 8;
  EXC_FRAME_SIZE_A64 = 128;
  EXC_JMP_OFFSET_A64 = 16;
  EXC_FRAME_SIZE_RV32 = 32;   { [0]=prev EXC_TOP, jmpbuf (s0,sp,ra) at +8 }
  EXC_JMP_OFFSET_RV32 = 8;
  EXC_FRAME_SIZE_XT = 32;     { [0]=prev EXC_TOP, jmpbuf (a15,sp,a0) at +8 (Call0) }
  EXC_JMP_OFFSET_XT = 8;

  { Data-ref sentinel base for class-reference (metaclass) values. A fixup with
    DataOff = -(CLASSREF_DATAREF_BASE + ci) is patched to UClsRTTIOff[ci] after
    EmitRTTI, then resolved to a real address by writeELF. Must clear the -100
    (RTTI registry) / -101 (resource table) sentinels with room for every ci. }
  CLASSREF_DATAREF_BASE = 100000;
  RECORD_RTTI_DATAREF_BASE = 200000;
  SYM_RTTI_DATAREF_BASE = 300000;

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

  { Compile targets. x86-64 is the native/self-host target; others are
    cross-only and grow op-by-op (unsupported constructs error, never
    mis-compile). See devdocs/progress/*/feature-target-i386.md. }
  TARGET_X86_64 = 0;
  TARGET_I386   = 1;
  TARGET_AARCH64 = 2;
  TARGET_ARM32   = 3;
  TARGET_XTENSA  = 4;
  TARGET_RISCV32 = 5;
  XTENSA_ABI_CALL0    = 0;
  XTENSA_ABI_WINDOWED = 1;
  { Platform / OS axis — independent of the CPU axis above. posix = hosted
    (syscalls, fd IO, sockets, dlopen); esp = bare-metal esp32 (MMIO, no
    filesystem/sockets yet). Do NOT derive platform from CPU: aarch64 can be
    posix or bare. See devdocs/progress/*/feature-platform-abstraction-layer.md. }
  PLATFORM_POSIX = 0;
  PLATFORM_ESP   = 1;
  { Bytes reserved below the windowed locals frame for the constant-sp
    expression/argument spill stack. Stage-1 nesting is shallow; 256 = 64
    slots is ample and keeps every offset inside the s32i/l32i imm range. }
  XT_EXPR_REGION = 256;
  LOAD_ADDR32        = $08048000;  { classic i386 ET_EXEC base }
  { ESP32 bare-metal SRAM map (--esp-profile=bare). On ESP32-C3 the internal
    SRAM is mapped twice: instruction bus (IRAM) at 0x4037C000 and data bus
    (DRAM) at 0x3FC7C000. qemu's esp32c3 machine models it as one RWX region,
    so the whole image (code+data+bss) loads at the IRAM org just past the
    16 KiB ICache, and the stack grows down from the top. ESP32-S3 reuses the
    same IRAM org; see the writer for the per-SoC base. UART0 FIFO is MMIO at
    0x60000000 on both. }
  ESP_BARE_IRAM_BASE = $40380000;  { C3: SRAM_IRAM_START(0x4037C000)+ICACHE(0x4000) }
  ESP_BARE_IRAM_BASE_XT = $40378000; { S3: SRAM_DIRAM_I_START (shared I/D SRAM) }
  ESP_BARE_STACK_TOP = $403C0000;  { top of stack (grows down toward image);
                                     valid IRAM on both C3 and S3 }
  ELF32_HEADER_SIZE  = 52;
  PROG32_HEADER_SIZE = 32;
  CODE_OFFSET32      = ELF32_HEADER_SIZE + PROG32_HEADER_SIZE;
  { Dynamic i386: ehdr + PT_LOAD + PT_INTERP + PT_DYNAMIC program headers. }
  DYNAMIC_CODE_OFFSET32 = ELF32_HEADER_SIZE + PROG32_HEADER_SIZE +
                          PROG32_HEADER_SIZE + PROG32_HEADER_SIZE;
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
    tkDefault,
    tkAsm,
    tkShl,
    tkPacked,
    { C declaration-specifier keywords (distinct so width/signedness/void are
      not collapsed into tkInteger_T). `int`->tkInteger_T, `char`->tkChar_T
      stay as before. }
    tkCVoid, tkCShort, tkCLong, tkCSigned, tkCUnsigned, tkCFloat, tkCDouble, tkCBool,
    tkIndent, tkDedent, tkNewline,
    tkHigh,
    tkXor,
    tkLow,
    { C multi-char operators (Slice A). Distinct so the C body parser and const
      evaluator can tell `&`/`&&`, `|`/`||`, `<<`/`>>`, and the compound-assigns
      apart. tkShl/tkXor/tkColon already exist above and are reused. }
    tkShr,
    tkAmp, tkPipe,
    tkPlusPlus, tkMinusMinus,
    tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq, tkModEq,
    tkAmpEq, tkPipeEq, tkXorEq, tkShlEq, tkShrEq,
    tkQuestion,
    tkLogNot,  { C `!` (logical not); distinct from `~` which stays tkNot }
    { Rust-only keywords/punctuation (feature-rust-frontend-skeleton). `struct`
      reuses tkRecord, `return` reuses tkExit, `break`/`continue` are shared —
      only genuinely new shapes get their own token. }
    tkFn, tkLet, tkMut, tkLoop, tkPathSep, tkDotDotEq, tkLifetime
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

  { A global-var operand referenced from inline asm: the encoder writes the
    ModRM/SIB bytes immediately (parse time, into AsmBytes) but can't call
    EmitGlobRef yet — AsmBytes offsets aren't the final code position, only
    the IR_ASM codegen-replay loop knows that (see ir_codegen.inc). AsmOff
    is the AsmBytes-relative offset of the 4-byte placeholder; the replay
    loop matches it against the block it's currently emitting and calls the
    real EmitGlobRef(BSSoff) at that point instead of copying the literal
    placeholder bytes. }
  TAsmGlobFix = record
    AsmOff : Integer;
    BSSoff : Integer;
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
    tyAuto,       { 24: Statically typed variable with inferred type }
    { Ordinals 25+: frozen fixed-length string kinds (disambiguate the old
      overloaded tyString). Appended at the tail so bootstrap-stable low ordinals
      do not shift. tyString stays a legacy frozen alias during migration. }
    tyShortString, { 25: classic Pascal shortstring — byte length prefix, cap 255, 256B total }
    tyFixedString  { 26: string[N] — NativeInt length word prefix, capacity N (SymStrCap) }
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
    Params     : array[0..31] of TParam;   { literal 31: record-field bounds cannot use MAX_PROC_PARAMS-1 (const-expr gap); keep = MAX_PROC_PARAMS }
    BodyAddr   : Integer;   { -1 = forward declared }
    FramePatch : Integer;   { code position of sub rsp imm32 }
    RetSymIdx  : Integer;   { Syms[] index for return value; -1 if proc }
    ScopeBase  : Integer;   { Syms[] index at start of this proc's locals }
  end;

const
  MAX_TEMPLATES = 16;
  MAX_TEMPLATE_PARAMS = 4;   { type parameters per generic template (<TKey, TData>) }
  MAX_TEMPLATE_TOKENS = 65536;  { FPC fgl alone buffers ~14k tokens of generic method bodies }
  MAX_NESTED_TOKENS = 8192;
  MAX_LIFTS = 512;
  MAX_LIFT_CAPS = 2048;
  MAX_GENERIC_METHODS = 512;    { FPC fgl has ~211 generic method bodies }
  MAX_PENDING_SPECS = 32;
  MAX_SPECIALIZATIONS = 32;
  MAX_GENERIC_FUNCS = 16;
  MAX_PENDING_GFSPECS = 32;
  MAX_OP_OVERLOADS = 64;

type
  TTemplate = record
    Name     : AnsiString;
    TokStart : Integer;
    TokCount : Integer;
    { type parameters live in the parallel TemplateParamNames/TemplateNParams
      globals (managed-string arrays inside record-array elements misbehave) }
  end;

  TSpecialization = record
    Name         : AnsiString;  { e.g. TIntStack }
    TemplateName : AnsiString;  { e.g. TStack }
    { concrete args live in SpecConcreteNames/Kinds/SpecNParams globals }
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
  TARGET_PTR_SIZE    : Integer;
  Templates          : array[0..MAX_TEMPLATES-1] of TTemplate;
  TemplateCount      : Integer;
  Specializations    : array[0..MAX_SPECIALIZATIONS-1] of TSpecialization;
  SpecializationCount: Integer;
  TemplateTokens     : array[0..MAX_TEMPLATE_TOKENS-1] of TRawToken;
  SpecializeTemplateName: AnsiString;
  { Active substitution set for SpecializeStream (param name -> concrete token),
    filled by each caller right before streaming. Multi-param generics
    substitute all entries in one pass. }
  SpecSubNames  : array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  SpecSubValues : array[0..MAX_TEMPLATE_PARAMS-1] of AnsiString;
  SpecSubKinds  : array[0..MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  SpecSubCount  : Integer;
  TypeSectionDepth : Integer; { >0 while inside a nested class-local type section — defers the pending-specialization flush to the OUTERMOST section end }
  { Per-template type parameters + per-specialization concrete args, parallel
    to Templates[]/Specializations[] (flat ti*MAX_TEMPLATE_PARAMS+k layout). }
  TemplateParamNames : array[0..MAX_TEMPLATES*MAX_TEMPLATE_PARAMS-1] of AnsiString;
  TemplateNParams    : array[0..MAX_TEMPLATES-1] of Integer;
  SpecConcreteNames  : array[0..MAX_SPECIALIZATIONS*MAX_TEMPLATE_PARAMS-1] of AnsiString;
  SpecConcreteKinds  : array[0..MAX_SPECIALIZATIONS*MAX_TEMPLATE_PARAMS-1] of TTokenKind;
  SpecNParams        : array[0..MAX_SPECIALIZATIONS-1] of Integer;
  SpecializeTokens   : array[0..MAX_TEMPLATE_TOKENS-1] of TRawToken;
  TemplateTokenCount : Integer;
  { Nested routines (Approach B / lambda-lifting): a nested procedure/function is
    forward-declared in place and its full body stashed here to be re-parsed as a
    fresh top-level routine once the enclosing routine finishes. See
    ParseNestedRoutine / FlushPendingNestedProcs in parser.inc. }
  PendNestTok        : array[0..MAX_NESTED_TOKENS-1] of TRawToken;
  PendNestCount      : Integer;
  { Per-routine boundaries within PendNestTok: a single enclosing body may stash
    several nested routines back to back, so the flush records each as its own
    DeclItem span (one ParseSubroutine per routine). }
  PendNestRtnStart   : array[0..MAX_LIFTS-1] of Integer;
  PendNestRtnCount   : Integer;
  { Lambda-lift descriptors: a nested routine that captures enclosing state is
    given a mangled unique name; ParseSubroutine looks the name up here (both at
    the forward decl and the real definition) and appends the captured state as
    extra params, copying the type metadata snapshotted at the capture site (the
    enclosing Syms slots are recycled by the time the lifted body is parsed, so
    indices can't be stored — only snapshots). See ParseNestedRoutine. }
  LiftName           : array[0..MAX_LIFTS-1] of AnsiString;
  LiftNeedSelf       : array[0..MAX_LIFTS-1] of Boolean;
  LiftSelfCi         : array[0..MAX_LIFTS-1] of Integer;
  LiftCapStart       : array[0..MAX_LIFTS-1] of Integer;
  LiftCapCount       : array[0..MAX_LIFTS-1] of Integer;
  LiftCount          : Integer;
  LiftCapName        : array[0..MAX_LIFT_CAPS-1] of AnsiString;
  LiftCapTk          : array[0..MAX_LIFT_CAPS-1] of TTypeKind;
  LiftCapRec         : array[0..MAX_LIFT_CAPS-1] of Integer;
  LiftCapArr         : array[0..MAX_LIFT_CAPS-1] of Boolean;
  LiftCapDyn         : array[0..MAX_LIFT_CAPS-1] of Integer;
  LiftCapPtrTk       : array[0..MAX_LIFT_CAPS-1] of TTypeKind;
  LiftCapPtrRec      : array[0..MAX_LIFT_CAPS-1] of Integer;
  LiftCapProcSig     : array[0..MAX_LIFT_CAPS-1] of Integer;
  LiftCapTot         : Integer;
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
  AnonDynArrayOff    : array[0..8191] of Integer;
  AnonDynArrayDepth  : array[0..8191] of Integer;
  AnonDynArrayBaseTk : array[0..8191] of Integer;
  AnonDynArrayBaseRec: array[0..8191] of Integer;
  AnonDynArrayElSize : array[0..8191] of Integer;
  AnonDynArrayCount  : Integer;
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
  DumpProcMap : Boolean;  { --proc-map: print 'PROC hexvaddr name' per routine to stderr (profiler symbolication) }
  OptLevel : Integer;     { -O0..-O3: optimization level. 0 (default) = the historic 1:1 emission — the self-host byte-identity gate runs at -O0 and is NEVER affected by opt passes; each pass gates on OptLevel >= its tier. }
  WarnedMissedFold : Boolean;  { one-shot latch for IROptWarnMissedFold: a foldable const-const / identity IR_BINOP reached codegen (const-fold was measured 0-fire and not shipped; this tripwire flags a future pass that starts producing them). }
  { --measure-regcall: phase-0 opportunity probe for feature-callconv-register-args.
    Per compiled body, tally params and how many are register-residency-eligible
    (scalar int/ptr, not by-ref/array/float/aggregate, address never taken in the
    body's IR). Summary printed at end of compile; no codegen change. }
  MeasureRegcall : Boolean;
  RegcallProcsWithParams : Integer;  { bodies that have >=1 param }
  RegcallTotalParams     : Integer;  { total declared params across all bodies }
  RegcallEligibleParams  : Integer;  { params that pass the residency eligibility test }
  RegcallAddrTaken       : Integer;  { scalar-typed params rejected only because their address is taken in-body }
  RegcallCapped2         : Integer;  { sum over bodies of min(eligible-in-body, 2) — phase-1 (r14/r15) capture }
  RegcallCapped5         : Integer;  { sum over bodies of min(eligible-in-body, 5) — phase-2 (rbx/r12/r13 too) capture }
  RegcallEligibleUses    : Integer;  { IR_LOAD_SYM+IR_STORE_SYM refs to eligible params — reload/spill traffic removable }
  { Phase-1 register calling convention (feature-callconv-register-args), -O2,
    x86-64 only. Up to 2 eligible scalar-by-value params of the current proc are
    kept resident in callee-saved r14/r15 for the whole body: reads become
    `mov rax/rcx, r14/r15` instead of a frame reload. The frame slot is still the
    authoritative copy (the early prologue spill writes it, and every store
    dual-writes it), so any non-EmitLoadVar reader — and the excluded addr-taken
    cases — stay correct; residency is a read cache. r14/r15 are callee-saved, so
    the caller's values are saved to a reserved frame slot at body entry and
    restored in the epilogue. These globals hold the CURRENT proc's residency
    (procs compile sequentially; nested procs flush after the enclosing one). }
  RcResidentCount   : Integer;               { 0..2 params resident in the current body }
  RcResidentSym     : array[0..1] of Integer; { Syms[] index of each resident param }
  RcResidentReg     : array[0..1] of Integer; { 14 or 15 }
  RcResidentSaveOff : array[0..1] of Integer; { rbp offset of the caller-reg save slot }
  { --measure-inline: phase-0 opportunity probe for feature-inline-routines /
    auto-inline. Per compiled body records size + leaf/early-exit/addr-taken-param
    facts; per direct call target counts the call sites. Summary printed at end of
    compile; no codegen change. }
  MeasureInline          : Boolean;
  ProcBodyIRNodes        : array[0..MAX_PROCS-1] of Integer; { IR node count of the body }
  ProcBodyMakesCall      : array[0..MAX_PROCS-1] of Boolean; { body contains any call → non-leaf }
  ProcBodyEarlyExit      : array[0..MAX_PROCS-1] of Boolean; { body has an explicit Exit (IR_TERMINATE) → multi-exit }
  ProcBodyAddrTakenParam : array[0..MAX_PROCS-1] of Boolean; { a param's address is taken in the body }
  ProcBodyCompiled       : array[0..MAX_PROCS-1] of Boolean; { CompileAST ran for this proc (has a real body) }
  InlineCallSites        : array[0..MAX_PROCS-1] of Integer; { direct internal-call sites targeting this proc }
  { Inline routine expansion (feature-inline-routines), -O2. A proc marked
    `inline;` (or auto-selected) whose body is a single `Result := E` pure
    expression over scalar-by-value params has E retained in the reserved AST
    region; at a direct call site the body is cloned in with params substituted by
    fresh arg temps and lowered in place of the call. }
  ProcInline       : array[0..MAX_PROCS-1] of Boolean; { `inline;` directive seen }
  InlineBodyRoot   : array[0..MAX_PROCS-1] of Integer; { retained E root in [INLINE_AST_BASE..), or -1 if not inlinable }
  InlineParamCnt   : array[0..MAX_PROCS-1] of Integer; { param count of the retained body }
  InlineASTNext    : Integer;   { next free slot in the reserved inline AST region }
  InliningActive   : Integer;   { >0 while splicing an inline body (recursion/nesting guard) }
  InlineArgAST     : array[0..MAX_PROC_PARAMS-1] of Integer; { arg AST per param index during a splice }
  { Slice 2b (-O3): straight-line multi-statement bodies with scalar ordinal
    locals + a single Result. The retained body is the whole AN_SEQ chain, with
    param/local/Result idents rewritten to placeholders. }
  InlineBodyIsStmt : array[0..MAX_PROCS-1] of Boolean; { retained body is a statement seq (needs locals + result temp), not a value expr }
  InlineLocalCnt   : array[0..MAX_PROCS-1] of Integer; { number of callee locals in the retained body }
  InlineLocalTk    : array[0..MAX_PROCS*MAX_INLINE_LOCALS-1] of Integer; { TypeKind ord per (proc, local index) }
  { Retention context (set while cloning a body into the region): map from a callee
    local/Result sym to its placeholder index. }
  RetLocalCnt      : Integer;
  RetLocalSym      : array[0..MAX_INLINE_LOCALS-1] of Integer;
  RetResSym        : Integer;
  { Splice context (set while cloning a stmt body back into the live pool): the
    fresh caller syms each placeholder maps to. }
  InlineLocalSym   : array[0..MAX_INLINE_LOCALS-1] of Integer;
  InlineResultSym  : Integer;
  InlineWrittenLocal : array[0..MAX_INLINE_LOCALS-1] of Boolean; { read-before-write guard during shape-3 validation }
  DumpCpp : Boolean;  { --dump-cpp: print the C-preprocessed source to stdout and exit }
  NoStdInc : Boolean;  { -nostdinc: do not auto-search pxx's crtl headers nor the /usr/include host fallback }
  StrictOverload : Boolean;
  DelphiMode : Boolean;  { {$mode delphi}: relaxes a bare function name bound to a procedural-value target to take its address (@F-optional). PXX's dialect is otherwise one objfpc-ish superset; this is the one behavioural delta. Default off. }
  ThreadSafeMode : Boolean;
  MatchQuiet : Boolean;  { suppress MatchProcCall's mismatch diagnostics for a speculative overload probe (delphi @-relax call-first attempt). }
  MimicFpc : Boolean;  { --mimic-fpc / {$MIMIC FPC}: install a curated FPC 3.2.2 define set so identity-probing library headers pick their FPC path. Opt-in only, NEVER default (the compiler's own {$ifdef FPC} means real FPC; mimic during self-build = broken bootstrap). }
  InterfacesComMode : Boolean; { {$interfaces com}: interfaces declared while on are COM/ARC (reference-counted). Default off = CORBA (no refcount). }
  ComInterfaceUsed : Boolean; { set when any COM/ARC interface is declared; forces the builtinheap unit (PXXIntfAddRef/Release live there) and the ARC cleanup path. }
  EnableAutoVar : Boolean;
  EnableLazyVar : Boolean;
  ImplicitVars  : Boolean;    { opt-in (--auto-locals / {$IMPLICITVARS ON}): assignment to a previously-undeclared name declares a routine-local tyAuto var (type inferred from RHS) instead of erroring "undefined variable". Off by default (masks typos); NEVER on in the self-build. See feature-implicit-locals-sloppy-switch. }
  CStyleComments : Boolean;   { CSTYLECOMMENTS directive: enable C slash-star comments }
  NestedComments : Boolean;   { NESTEDCOMMENTS directive: nest brace and paren-star comments }
  CaseSensitiveMode : Boolean; { CASESENSITIVE directive: when on, identifiers declared here match case-sensitively. Default off (standard case-insensitive Pascal). }
  LazyCasing : Boolean; { LAZYCASING directive: when on, a C-import (external, case-sensitive) symbol may resolve through a case-insensitive fallback if exactly one matches (a warning is emitted). Default off; never weakens Pascal case rules. }
  NoUnhandledHandler : Boolean;
  Source  : AnsiString;
  SrcPos  : Integer;
  SrcLine : Integer;
  CurLowerLine : Integer; { current AST source line being lowered → stamped onto IR (DWARF -g) }
  DebugInfo : Boolean;    { -g: emit DWARF .debug_* sections + section header table }
  CurTok  : TToken;
  PasDefineChars   : array[0..MAX_PAS_DEFINE_CHARS-1] of Char;
  PasDefineNameOff : array[0..MAX_PAS_DEFINES-1] of Integer;
  PasDefineNameLen : array[0..MAX_PAS_DEFINES-1] of Integer;
  PasDefineActive  : array[0..MAX_PAS_DEFINES-1] of Boolean;
  PasDefineValue   : array[0..MAX_PAS_DEFINES-1] of Int64;
  PasDefineHasValue: array[0..MAX_PAS_DEFINES-1] of Boolean;
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
  { Cross-section internal calls (a flash<->iram pair). The call is emitted as an
    indirect load of a 32-bit literal slot (like an external call); the literal
    at CodePos is relocated R_*_32 against the target proc's own local symbol so
    the linker fills the final absolute address. }
  IramCallFix : array[0..MAX_CALLFIX-1] of TCallFix;
  IramCallFixCount : Integer;

  Syms      : array[0..MAX_SYMS-1]  of TSymbol;
  SymCaseSensitive : array[0..MAX_SYMS-1] of Boolean; { match this symbol name case-sensitively }
  SymUnitIdx : array[0..MAX_SYMS-1] of Integer; { Strs[] unit name, or -1 for main/local compiler-generated symbols }
  SymDynDepth : array[0..MAX_SYMS-1] of Integer; { dynamic-array nesting: 0=not dynamic, 1=array of T, 2=array of array of T, ... }
  SymElemDynDepth : array[0..MAX_SYMS-1] of Integer; { for a FIXED array whose ELEMENT is itself a dynamic array (`array[..] of TDynAlias`): the element's dyn depth (0 = element not dynamic). Element base type/rec live in ElemType/ElemRecName; each slot is pointer-sized. }
  SymGenSlot  : array[0..MAX_SYMS-1] of Integer; { stackless generator: persistent-slot index for a local that must survive yields; -1 = not persisted }
  SymProcSig  : array[0..MAX_SYMS-1] of Integer; { procedural-type var/param: signature proc index (Procs[] entry, BodyAddr=-1) for indirect-call marshalling; -1 = not a proc-typed value }
  SymElemProcSig : array[0..MAX_SYMS-1] of Integer; { array-of-proctype var: signature proc index of the ELEMENT proc type, for an indexed indirect call `arr[i](args)`; -1 = element not proc-typed }
  SymSetEnumId : array[0..MAX_SYMS-1] of Integer; { set var: element enum type index for `set of TEnum`, else -1. Drives `for e in set` range }
  SymSetElemTk : array[0..MAX_SYMS-1] of Integer; { set var: element TTypeKind ordinal (tyChar/tyInteger/enum-as-integer), else 0 }
  SymStrCap : array[0..MAX_SYMS-1] of Integer; { frozen fixed-string capacity (max chars) for tyFixedString/tyShortString slots; 0 = use the kind default (DEFAULT_STR_CAP) }
  SymPtrDepth : array[0..MAX_SYMS-1] of Integer; { typed pointer depth: P^^ / char** = 2. 0 = unknown/not a pointer. }
  SymPtrBaseTk : array[0..MAX_SYMS-1] of Integer; { typed pointer ultimate base TTypeKind ordinal, tyUnknown if unset. }
  SymPtrBaseRec : array[0..MAX_SYMS-1] of Integer; { typed pointer ultimate base record id, REC_NONE if unset. }
  SymPtrElemArrLen : array[0..MAX_SYMS-1] of Integer; { C pointer-to-array `elem (*p)[N]`: the pointee is a fixed array of N; row length N (elem stride = PtrElemTk size). 0 = pointee is not an array. Drives `p[i][j]` flatten (i*N+j). }
  { 2-D fixed array flattened to 1-D storage: m[i,j] / m[i][j] index as
    (i-lo1)*span2 + (j-lo2). Default False/0 (single-dimension array). }
  { N-D fixed array flattened to 1-D storage; element [i0..iN-1] linearises to
    Horner( (i_d - lo_d) over span_d ). NDims=0 means single-dimension. Per-dim
    lo/span live in flat side tables indexed [sym*MAX_ARR_DIMS + d]. }
  SymArrNDims  : array[0..MAX_SYMS-1] of Integer;
  SymArrDimLo  : array[0..MAX_SYMS*MAX_ARR_DIMS-1] of Integer;
  SymArrDimSpan: array[0..MAX_SYMS*MAX_ARR_DIMS-1] of Integer;
  SymRTTIOff  : array[0..MAX_SYMS-1] of Integer; { Data[] offset of layout RTTI descriptor, -1 if none }
  SymIsHiddenArgTemp : array[0..MAX_SYMS-1] of Boolean; { compiler-synthesised owning managed local created during IR lowering (materialised managed-string call argument, or an `array of const` TVarRec dyn-array temp); allocated after the parser's prologue zero-init pass, so codegen nil-inits it before the body }
  SymBlockId : array[0..MAX_SYMS-1] of Integer;
  SymDeclTok : array[0..MAX_SYMS-1] of Integer; { token index where a global var was declared (decl-order gating); 0 = unstamped/always-visible }
  SymCount  : Integer;
  FrameSize : Integer;

  Procs     : array[0..MAX_PROCS-1] of TProc;
  { FindProc hash index (perf-compiler-hotspots-algorithmic): buckets keyed on
    the case-FOLDED name so exact and case-insensitive candidates share one
    chain. Chains are FIFO (= registration order), so every walker keeps the
    linear scan's first-match / overload-order semantics exactly. Procs are
    append-only (ProcCount never rolls back), so there is no unlink path. }
  ProcHashHead : array[0..PROC_HASH_SIZE-1] of Integer;
  ProcHashTail : array[0..PROC_HASH_SIZE-1] of Integer;
  ProcHashNext : array[0..MAX_PROCS-1] of Integer;
  { FindSym hash index: same folded-name bucketing, but chains are NEWEST-
    FIRST (head = most recent) because FindSym scans innermost-scope-out —
    walking head->older is exactly the linear `downto` order. Scope exits
    truncate SymCount; SymRollbackTo pops the removed range off the chain
    heads (descending idx = each is its bucket's current head), so chains
    never hold dead indices. }
  SymHashHead : array[0..SYM_HASH_SIZE-1] of Integer;
  SymHashPrev : array[0..MAX_SYMS-1] of Integer;   { next-older same-bucket idx }
  ProcOverloadDirective : array[0..MAX_PROCS-1] of Boolean;
  ProcFlexColumn : array[0..MAX_PROCS-1] of Boolean; { `flexcolumn` directive: call args accept write-style `:width[:decimals]` modifiers; each value arg expands to three actuals (value, width, decimals; defaults 0 / -1), so the routine declares (v; w, d) triples. }
  ProcCount : Integer;
  CurProc   : Integer;   { -1 = main }
  BlockParent: array[0..32767] of Integer;
  BlockCount: Integer;
  CurBlockId: Integer;
  ProcExternal : array[0..MAX_PROCS-1] of Boolean;
  ProcCaseSensitive : array[0..MAX_PROCS-1] of Boolean; { match this proc name case-sensitively (C imports, or Pascal in case-sensitive mode) }
  ProcLibrary  : array[0..MAX_PROCS-1] of Integer; { Strs[] entry for DT_NEEDED name }
  ProcExtName  : array[0..MAX_PROCS-1] of Integer; { Strs[] link symbol from `external 'lib' name 'sym'`; -1 = use the Pascal routine name }
  ProcCdecl    : array[0..MAX_PROCS-1] of Boolean; { signature uses the C (System V AMD64) convention. Set for a `... cdecl` PROC TYPE so an INDIRECT call through it marshals SysV (int->rdi.., float->xmm0..) instead of PXX's internal all-integer convention — needed for dlsym'd C functions with float args. }
  ProcVariadic : array[0..MAX_PROCS-1] of Boolean; { C function with a trailing `...` — needs the System V register-save prologue so va_arg can read the variadic args. }
  ProcNamedGP  : array[0..MAX_PROCS-1] of Integer; { count of named (non-variadic) GP params, for va_start's initial gp_offset }
  ProcNamedFP  : array[0..MAX_PROCS-1] of Integer; { count of named (non-variadic) FP/XMM params, for va_start's initial fp_offset }
  ProcUnitIdx : array[0..MAX_PROCS-1] of Integer; { Strs[] unit name, or -1 for main }
  ProcRetRecId : array[0..MAX_PROCS-1] of Integer; { record id for tyRecord results }
  ProcAggregateDestSym : array[0..MAX_PROCS-1] of Integer; { hidden caller-result pointer local, or -1 }
  ProcRetIsDynArray : array[0..MAX_PROCS-1] of Boolean; { result is `array of T` (pointer-sized heap handle) }
  ProcIsAsync     : array[0..MAX_PROCS-1] of Boolean;   { `; async;` routine — non-viral hint; legalises `await` in the body (stackful: documentary; stackless transform later) }
  ProcIsGenerator : array[0..MAX_PROCS-1] of Boolean;   { `; generator;` routine — compiled as a stackful-coroutine body (see coroutine.pas) }
  ProcIsStackless : array[0..MAX_PROCS-1] of Boolean;   { `; generator; stackless;` — compiled as a state-machine step fn (see slgen.pas) }
  ProcIram        : array[0..MAX_PROCS-1] of Boolean;   { `; iram;` — body placed in the ELF .iram1.text section (ESP IRAM) }
  ProcIsInterrupt : array[0..MAX_PROCS-1] of Boolean;   { `; interrupt;` — raw hardware interrupt handler (reserved; full reg-save/iret not yet emitted) }
  ProcBodyEnd     : array[0..MAX_PROCS-1] of Integer;   { Code[] offset just past this proc's body (set at proc end); the iram byte-range is [BodyAddr, ProcBodyEnd) }
  ProcDbgMain     : array[0..MAX_PROCS-1] of Boolean;   { DWARF -g: proc defined in the main source file (gets a DW_TAG_subprogram DIE) }
  ProcGenElemTk   : array[0..MAX_PROCS-1] of TTypeKind; { stackless: declared (yielded) element type; the proc's own RetType is Boolean (has-next) }
  ProcGenElemRec  : array[0..MAX_PROCS-1] of Integer;   { stackless: record id when the element type is a record (REC_NONE otherwise); CURRENT then holds a POINTER to a record region at the instance tail }
  ProcGenParamCnt : array[0..MAX_PROCS-1] of Integer;   { stackless: declared param count (the ABI param is the single hidden instance ptr) }
  ProcGenInstSize : array[0..MAX_PROCS-1] of Integer;   { stackless: instance byte size (header + persistent slots) }
  ProcRetElemTk : array[0..MAX_PROCS-1] of TTypeKind;    { element type of a dyn-array result }
  ProcRetElemRec : array[0..MAX_PROCS-1] of Integer;     { element record id of a dyn-array result }
  ProcRetPtrElemTk : array[0..MAX_PROCS-1] of Integer;   { pointed-at TTypeKind ord when the result is a typed pointer (tyUnknown otherwise) }
  ProcRetProcSig   : array[0..MAX_PROCS-1] of Integer;   { call signature when the result is itself a function pointer (`fty go(void)`), so `go()(args)` is an indirect call; -1 otherwise }
  CProcHasLocalDef : array[0..MAX_PROCS-1] of Boolean;   { a local (in-TU) function body for this proc was seen in pass 1; a later redundant prototype (guardless header re-included by several .c) must NOT re-mark it external — keeps the pass-2 forward call internal, not a dynamic import }
  ProcRetPtrElemRec : array[0..MAX_PROCS-1] of Integer;  { pointed-at record id when the result is a typed pointer-to-struct }
  ProcParamPtrDepth : array[0..MAX_PARAM_DEPTHS-1] of Integer; { C interop: pointer depth for parameters }
  ProcParamRecId : array[0..MAX_PARAM_DEPTHS-1] of Integer; { record/class/interface rec id per param (param syms are reused across procs, so this must persist); REC_NONE if not a record/class }
  ProcParamDynDepth : array[0..MAX_PARAM_DEPTHS-1] of Integer; { named dynamic-array param: dyn nesting depth (>0); 0 = not a named dynarray param. Persists because param syms are reused across procs. Distinguishes a resizable `TDynArr=array of T` param from an open `array of T` param at the call site. }
  ProcParamIsConst : array[0..MAX_PARAM_DEPTHS-1] of Boolean; { param declared `const` (read-only by-ref). Persists because param syms are reused across procs. At a call site, a `const` record param may bind a non-lvalue temporary (FPC behaviour) — the temp is materialized into a hidden local and its address passed; a `var`/`out` param still requires a true lvalue for write-back. }
  ProcParamExplicitByRef : array[0..MAX_PARAM_DEPTHS-1] of Boolean; { param was EXPLICITLY declared by-ref (`var`/`out`/`const`) at the source level, before the >8-byte record ABI forces IsRef. Lets a call site tell a genuine `var`/`out` record param (needs a real lvalue for write-back) from a plain by-value record passed by-ref only for ABI (a temporary is fine — the callee copies). const records carry their own ProcParamIsConst flag. }
  ProcParamUntyped : array[0..MAX_PARAM_DEPTHS-1] of Boolean; { param declared untyped (`var x`/`const x`/`out x`, no type) — an untyped by-ref param. Overload matching accepts ANY argument type for this slot; the caller passes the argument's address. Underpins Move/FillChar-style routines. }
  ProcParamHasDefault : array[0..MAX_PARAM_DEPTHS-1] of Boolean; { param has a default value (`b: Integer = 10`). Trailing params only. A call omitting trailing args supplies these; overload matching accepts nArgs in [required..ParamCount]. }
  ProcParamDefaultVal : array[0..MAX_PARAM_DEPTHS-1] of Int64;   { the constant-folded default ordinal value (when ProcParamHasDefault). }
  CurrentCLibrary : AnsiString;
  CTypeIsVoid : Boolean; { last ParseCDeclType saw bare void (no pointer) }
  CTypePtrDepth : Integer;   { pointer-star count of the last ParseCDeclType (0 = not a pointer) }
  CTypeElemTk : Integer;     { pointed-at TTypeKind ordinal when CTypePtrDepth>0 (tyPointer for depth>=2) }
  CTypeElemRec : Integer;    { pointed-at record id when the element is a struct, else REC_NONE }
  CTypePtrBaseTk : Integer;  { ultimate pointed-at base TTypeKind ordinal when CTypePtrDepth>0 }
  CTypePtrBaseRec : Integer; { ultimate pointed-at base record id when CTypePtrDepth>0 }
  CTypeBaseRec : Integer;    { record id of the base type before any pointer suffix, else REC_NONE }
  CTypeProcSig : Integer;    { fn-pointer typedef signature Procs[] index of the last ParseCDeclType (CTypePtrDepth=0), else -1 }
  CTypeTypedefArrLen : Integer; { array-typedef (`typedef float v4[4]`) inherent length of the last ParseCDeclType, else -1 }
  CTypeFnPtrName : AnsiString; { fn-pointer declarator name `ret (*Name)(..)` captured by the last ParseCDeclType, else '' }
  CTypeFnPtrNameOff, CTypeFnPtrNameLen : Integer; { token-char off/len of CTypeFnPtrName (for struct-member field registration) }
  CTypeFnPtrArrLen : Integer; { array length of an inline fn-ptr-ARRAY declarator `ret (*Name[N])(..)`: -2 = not an array, -1 = `[]` unbounded, >=0 = sized }
  CTypePtrElemArrLen : Integer; { pointer-to-array declarator `elem (*Name)[N]`: the pointee is a fixed array of N (row length). 0 = not a pointer-to-array. }
  CTypeFnRetIsFunc : Boolean; { last ParseCDeclType saw `ret (*Name(params))(...)`: a real function returning a fn pointer, not a fn-pointer variable }
  CTypeFnRetParamCount : Integer;
  CTypeFnRetPTypes : array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  CTypeFnRetPNames : array[0..MAX_PROC_PARAMS-1] of AnsiString;
  CTypeFnRetPDepths : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPBaseTk : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPBaseRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPElemTk : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPElemRec : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPRecId : array[0..MAX_PROC_PARAMS-1] of Integer;
  CTypeFnRetPProcSig : array[0..MAX_PROC_PARAMS-1] of Integer;
  CLocalStaticDecl : Boolean; { current block-scope C declaration had `static`;
    allocate its storage globally while still parsing it in statement position }
  CHeaderMode : Boolean; { parsing C in header/FFI mode }
  CProgramMode : Boolean; { compiling a C .c program (vs importing a header):
    a `{...}` function body is a LOCAL definition (internal), so the pass-1
    signature scan must mark it ProcExternal=False even while skipping the body,
    or a caller compiled before the callee's definition emits an external call. }
  CTypedefCount : Integer;
  CTypedefNameOff : array[0..MAX_CTYPEDEF-1] of Integer;
  CTypedefNameLen : array[0..MAX_CTYPEDEF-1] of Integer;
  CTypedefTk    : array[0..MAX_CTYPEDEF-1] of Integer; { resolved TTypeKind ordinal }
  CTypedefElemTk : array[0..MAX_CTYPEDEF-1] of Integer; { pointer typedef: pointed-at TTypeKind ordinal }
  CTypedefRec   : array[0..MAX_CTYPEDEF-1] of Integer;  { struct typedef: record id; pointer typedef: elem record id }
  CTypedefProcSig : array[0..MAX_CTYPEDEF-1] of Integer; { fn-pointer typedef: signature Procs[] index (BodyAddr=-1) for indirect-call marshalling; -1 = not a fn pointer }
  CTypedefIsFnType : array[0..MAX_CTYPEDEF-1] of Boolean; { True for a function-TYPE typedef `typedef R N(args);` (vs a fn-POINTER typedef): a following `*` in a declarator DECAYS (pointer-to-function) rather than adding a level, so `N *p` is the callable, matching C function/pointer-to-function equivalence }
  CTypedefArrLen : array[0..MAX_CTYPEDEF-1] of Integer; { array typedef `typedef ELEM name[N]`: inherent length N (single dim); -1 = not an array typedef }
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
  LastTypeElemDynDepth : Integer; { set when a fixed-array element type resolves to a dynamic-array alias; consumed by AllocArray to lay the element out pointer-sized and record SymElemDynDepth, then reset }
  LastTypeStrCap : Integer; { frozen fixed-string capacity from the most recent string[N] type parse (0 = default); consumed by AllocVar/AllocArray, then reset }
  TVarRecId : Integer;   { record id of builtinheap.TVarRec (`array of const`
                           element), or REC_NONE if the unit isn't loaded }
  MethodPtrRecId : Integer; { record id of the 16-byte method-pointer layout
                           {Code@0, Data@8} minted on first `of object` proc
                           type; REC_NONE until then }
  LastTypePointerElemTk : TTypeKind;
  LastTypePointerElemRec : Integer;
  LastTypePointerDepth : Integer;
  LastTypePointerBaseTk : Integer;
  LastTypePointerBaseRec : Integer;
  LastTypeProcSig : Integer;  { set by ParseTypeKind when a name resolves to a procedural type: signature proc index, else -1 }
  ErrorIdent : AnsiString;
  WarnCount : Integer;     { number of non-fatal warnings emitted via Warn }
  WarnAsError : Boolean;   { -Werror: promote the next Warn to a fatal Error }
  { Label fixup scratch for the machine-code emit pass. One shared set: only the
    active target's IREmitMachineCode* runs per compile, and it runs once (not
    reentrant), so a single global set is safe. Moved off the stack — as locals
    these were array[0..MAX_IR-1] (512 KB each, ~1.5 MB/frame) in EVERY backend,
    bloating the compiler's own frames (feature-warn-oversized-stack-frame). }
  LabelPositions : array[0..MAX_IR-1] of Integer;
  LabelFixupPos : array[0..MAX_IR-1] of Integer;
  LabelFixupTarget : array[0..MAX_IR-1] of Integer;
  MaxStackFrameSize : Integer; { effective oversized-stack-frame warn threshold in
                                 bytes (0 = disabled). Init to MAX_STACK_FRAME_SIZE;
                                 overridable via --max-stack-frame=N / {$MAXSTACKFRAME n}. }
  WarnSelfResult : Boolean; { --warn-self-result: warn when a paramless function's
                             bare own name is read as a value (FPC = its Result,
                             but often a mistaken `Name()` self-recursion). Off by
                             default — the compiler's own source uses the idiom. }
  LastExprTk : TTypeKind;
  InInterface : Boolean;
  { Declaration pre-scan (whole-section forward visibility): pass 1 registers
    every top-level routine header (and all types/consts/vars) with bodies
    skipped, so a routine may call another declared later (and mutual recursion
    needs no `forward`). Pass 2 replays the recorded subroutine spans to emit the
    bodies. See devdocs/progress/*/feature-declaration-prescan. }
  PreScanPass : Boolean;        { True while registering headers (pass 1) }
  GenericMethodBuffered : Boolean; { set by ParseSubroutine when it consumed a generic
    class-method impl (`procedure TBox.Meth` for a template TBox) via
    BufferGenericMethod and Exited. The pass-1 driver then must NOT record it as a
    replayable DeclItem — the method is buffered once and streamed by specialize;
    replaying it in pass 2 would double-buffer and corrupt the token stream. }
  DeclItemStart : array[0..MAX_DECL_ITEMS-1] of Integer; { token index of each recorded subroutine }
  DeclItemEnd   : array[0..MAX_DECL_ITEMS-1] of Integer; { token index just past it }
  DeclItemCount : Integer;
  { Body-pass (pass 2) token-stream tracking. A nested routine lifted during the
    body pass edits the token stream (forward-rewrite removes the inner body, and
    FlushPendingNestedProcs appends the lifted definition as a fresh DeclItem). Those
    edits shift the indices the pass-2 driver still relies on: the remaining recorded
    DeclItem spans and the program/unit body-begin marker. Pass2Active gates the
    span adjustment so the (nested-routine-free) compiler self-build is untouched;
    Pass2BodyTok is the single live body-begin index, kept in sync by AdjustPass2Spans. }
  Pass2Active   : Boolean;
  Pass2BodyTok  : Integer;
  CompiledUnits : array[0..255] of Integer;
  CompiledUnitCount : Integer;
  CurrentUnitIdx : Integer; { Strs[] name while parsing an imported unit, else -1 }
  { `uses 'name' as alias` table: a qualifier `alias.Sym` resolves to the real
    unit's symbols. UnitAliasName[k] = Strs[] idx of the (lowercased) alias,
    UnitAliasReal[k] = Strs[] idx of the real unit (= its SymUnitIdx tag). }
  UnitAliasName : array[0..63] of Integer;
  UnitAliasReal : array[0..63] of Integer;
  UnitAliasCount : Integer;
  { Multidim `SetLength(a, d1, d2, ...)` scratch: the parsed size-expr AST nodes
    for one SetLength call (not nested, so a single shared buffer is safe). }
  SetLenDimNode : array[0..31] of Integer;
  SetLenDimN : Integer;
  { Synthesized unit initialization procs, in dependency (post-uses) order.
    Called at program entry before the main body so unit globals get set up. }
  InitProcs : array[0..255] of Integer;
  InitProcCount : Integer;
  SourceFileDir : AnsiString;
  { Base name (no dir, no ext) of the source file currently being lexed; used to
    resolve the `*` in $R *.lfm / $R *.res to the current unit. }
  CurSrcBaseName : AnsiString;
  { Directory of the source file whose `uses` clause is being parsed; path-form
    unit references (uses './sub/unit') resolve relative to it. Saved/restored
    around each nested unit parse, like CurSrcBaseName. }
  CurUnitDir : AnsiString;
  { Selected compile target (TARGET_*). Default TARGET_X86_64. }
  TargetArch : Integer;
  { Selected platform/OS (PLATFORM_*). Default PLATFORM_POSIX; derived from the
    target (esp targets / --esp-profile=bare -> PLATFORM_ESP) unless --platform=
    overrides. Set explicitly = PlatformExplicit True (suppresses derivation). }
  TargetPlatform : Integer;
  PlatformExplicit : Boolean;
  { Xtensa ABI selector. Call0 remains the bare-target default; ESP-IDF uses
    the windowed ABI. }
  XtensaABI : Integer;
  { Xtensa integer divide policy. Default False = native quos/rems (LX7 / ESP32
    -S2/-S3 baseline). True (via --xtensa-cpu=lx6) routes div/mod through the
    software shift-subtract helpers __pxx_divsi3/__pxx_modsi3 for ESP32 classic
    (LX6), which has the multiply option but not the divide option. }
  XtensaSoftDivide : Boolean;
  { Xtensa single-precision hardware FPU. Default False = single-width float ops
    go through the soft kernels (correct on EVERY xtensa part, incl ESP32-S2
    which has NO FPU). True (via --xtensa-fpu) lowers single +,-,* to the
    hardware add.s/sub.s/mul.s (ESP32 / ESP32-S3 only); single /, comparisons and
    conversions stay soft (no HW single divide/compare-to-AR path wired). Opt-in
    because FPU presence can't be inferred from the cpu flag (S2 has none). }
  XtensaHasFpu : Boolean;
  { {$FASTDOUBLES ON} — compute Double +,-,* through the hardware single FPU
    (round-trip d2s/op.s/s2d) instead of the soft-double kernels. Lossy (single
    precision); default OFF. Only meaningful on xtensa with --xtensa-fpu (single
    HW, double soft); no-op on riscv (both soft) and double-native targets. }
  XtensaFastDoubles : Boolean;
  { Windowed-ABI expression stack: a constant-sp function keeps its stack
    pointer fixed (the window overflow/underflow handlers spill the caller's
    a0-a3 to [sp-16], so sp must not move). Temporaries live at sp-relative
    positive offsets inside a reserved frame region; XtSpillDepth is the
    current byte offset, reset per proc. Call0 keeps the moving-sp stack. }
  XtSpillDepth : Integer;
  { Emit a relocatable ET_REL .o instead of a linked ET_EXEC image
    (--emit-obj, or inferred from a .o output name). esp32 targets only. }
  EmitObjMode : Boolean;
  EmitSharedMode : Boolean;   { .asm frontend --shared: x86-64 ET_DYN .so output }
  EmitAsmTextMode : Boolean;  { -S: also write <outFile>.s, a best-effort x86-64
                                 disassembly of whatever codegen just produced
                                 (feature-asm-textual-emit-mode, head 2) }
  { ESP32 bare-metal profile (--esp-profile=bare): emit a self-contained
    ET_EXEC image targeting the SoC SRAM map (code/data/bss/stack in IRAM),
    bootable directly via `qemu-system-* -M esp32c3 -kernel`, with no ESP-IDF
    runtime. The entry stub sets sp; output (PutC) goes to UART0 MMIO from the
    program itself. Defines PXX_ESP_BARE for the source. xtensa/riscv32 only. }
  EspBareBoot : Boolean;
  { --no-default-rtl: suppress the default standard-unit surface (textfile +
    its builtin numeric-format backing). Set for compiler self-build, where
    textfile would drag the PAL platform_backend onto a search path the
    bootstrap does not provide, and the compiler relies on builtins only. }
  NoDefaultRtl : Boolean;
  { writeELF32Rel scratch: per-proc / per-external .strtab name offsets
    (globals, not locals — 64KB each would strain the self-hosted stack). }
  ObjProcStrOff : array[0..MAX_PROCS-1] of Integer;
  ObjExtStrOff  : array[0..MAX_EXTERNAL-1] of Integer;
  ObjProcSymIdx : array[0..MAX_PROCS-1] of Integer; { .symtab index of each proc (extended iram writer) }
  ObjProcIramOff: array[0..MAX_PROCS-1] of Integer; { offset of an iram proc's body within .iram1.text }
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
  AsmGlobFix: array[0..MAX_ASM_GLOBFIX-1] of TAsmGlobFix;
  AsmGlobFixCount: Integer;
  { Inline asm on cross targets (riscv32 first): the parser cannot encode at
    parse time like x86-64's AsmBytes path (the per-target EmitAsmXxx engines
    emit at CodeLen, where EmitGlobRef/EmitDataRef fixups are natively
    correct), so it captures the block as resolved TEXT lines here — Pascal
    local/param names already substituted to frame references, globals to
    @glob + a hole value — and the target's IR_ASM codegen case replays them
    through its EmitAsmXxx engine. InlineAsmLineHole0[i] is the index into
    InlineAsmHoleVal of line i's first hole value ('%' count in the line says
    how many). }
  InlineAsmLine: array[0..MAX_INLINE_ASM_LINES-1] of AnsiString;
  InlineAsmLineHole0: array[0..MAX_INLINE_ASM_LINES-1] of Integer;
  InlineAsmLineHoleN: array[0..MAX_INLINE_ASM_LINES-1] of Integer;
  InlineAsmLineCount: Integer;
  InlineAsmHoleVal: array[0..MAX_INLINE_ASM_HOLES-1] of Int64;
  InlineAsmHoleCount: Integer;
  { .asm frontend: code offset of a `global <label>` entry-point override
    (feature-asm-source-frontend); 0 = default (start of Code[], unchanged
    for every non-.asm compile). }
  AsmEntryOff: Integer;
  { .asm frontend -c (EmitObjMode): `call <extern>` emits a plain `call
    rel32` placeholder instead of the GOT-indirect ET_EXEC form, and records
    (code position of the rel32 field, ExternalProc[]/RegisterExternal index)
    here so writeELFRelX64 can turn it into an R_X86_64_PLT32 relocation for
    a real external linker to resolve. }
  AsmObjCallPos: array[0..MAX_ASM_OBJ_CALLFIX-1] of Integer;
  AsmObjCallExtIdx: array[0..MAX_ASM_OBJ_CALLFIX-1] of Integer;
  AsmObjCallCount: Integer;
  { .asm frontend: resolved `global <label>` symbols (name + offset into the
    single combined Code[] blob + whether the label was in `section .data`),
    for writeELFRelX64 to export as GLOBAL ELF symbols. Populated at the end
    of ParseAsmProgram; unused outside EmitObjMode. }
  AsmGlobalSymName: array[0..MAX_ASM_GLOBALS-1] of AnsiString;
  AsmGlobalSymOff: array[0..MAX_ASM_GLOBALS-1] of Integer;
  AsmGlobalSymIsData: array[0..MAX_ASM_GLOBALS-1] of Boolean;
  AsmGlobalSymCount: Integer;
  { writeELFRelX64 scratch: .strtab offset of each AsmGlobalSymName[i]/each
    extern's Procs[].Name (mirrors ObjProcStrOff/ObjExtStrOff's role in the
    xtensa/riscv32 ET_REL writer). }
  AsmGlobalSymStrOff: array[0..MAX_ASM_GLOBALS-1] of Integer;
  { .asm frontend --shared (EmitSharedMode): `call <extern>` needs
    position-independent GOT access (a fixed load address can't be assumed),
    so it emits `call qword ptr [rip+disp32]` (FF 15) instead of either the
    ET_EXEC absolute-GOT form or the -c PLT32-relocation form, and records
    (code position of the disp32 field, RegisterExternal index) here.
    writeELFSharedX64 resolves each disp32 the same way every other
    rip-relative site in this compiler is resolved: target-(patch_pos+4),
    once the GOT slot's (chosen-base-relative) virtual address is known --
    the GOT slot itself is the *same* ExternalGotOff[]/Data[] slot
    RegisterExternal already allocates for the ET_EXEC path, just filled by
    the dynamic linker's R_X86_64_GLOB_DAT relocation instead of by us. }
  AsmSoCallPos: array[0..MAX_ASM_OBJ_CALLFIX-1] of Integer;
  AsmSoCallExtIdx: array[0..MAX_ASM_OBJ_CALLFIX-1] of Integer;
  AsmSoCallCount: Integer;
  { -S (WriteDisassemblyX64): O(1) "does a proc start/does a branch land
    here" lookup table, one entry per possible Code[] position. A LOCAL
    `array of Integer` (SetLength-based) here previously triggered pxx's
    oversized-stack-frame warning at ~8MB (MAX_CODE) -- a global sidesteps
    it entirely (BSS, not stack), matching the warning's own suggestion. }
  AsmDisProcAtPos: array[0..MAX_CODE] of Integer;
  { Inline-asm operand scratch (slot 0 = dest, slot 1 = src) }
  AsmOpKind : array[0..1] of Integer;   { AOP_* }
  AsmOpReg  : array[0..1] of Integer;   { register number 0..15; AOP_MEMR base reg }
  AsmOpSize : array[0..1] of Integer;   { 1, 2, 4, 8 (bytes) }
  AsmOpVal  : array[0..1] of Int64;     { immediate value, or mem disp for AOP_MEM/AOP_MEMR }
  AsmOpIndex: array[0..1] of Integer;   { AOP_MEMR index reg, -1 = none }
  AsmOpScale: array[0..1] of Integer;   { AOP_MEMR scale: 1/2/4/8 }
  AssignPath : AnsiString;
  IncExpanded : AnsiString;
  IncIncluded : AnsiString;
  UnitContent : AnsiString;
  LoadPath : AnsiString;
  SavedLexSource : AnsiString;
  sysbuf : array[0..7] of Byte;

  { Ordered C `#include` search roots from `-I` (project / library dirs).
    Searched after the including file's own directory and before any system
    fallback, so a project header (e.g. our own zlib.h) wins over a host one. }
  CIncludeDirs    : array[0..MAX_C_INCLUDE_DIRS-1] of AnsiString;
  CIncludeDirCount: Integer;

  { Auto-pull of pxx's own libc-free C runtime (lib/crtl). When a crtl `<header>`
    resolves, the compiler also pulls its sibling `lib/crtl/src/<name>.c` impl —
    pxx has no separate link step, so this IS the "link": a C program that
    `#include <math.h>` gets fabs/sqrt's libc-free bodies (bridged to the Pascal
    RTL) with no DT_NEEDED, instead of an unresolved libm extern. Each impl is
    pulled at most once (CrtlSrcPulled dedup, also breaks the cycle where the impl
    re-includes its own header). Bare `--system-libs` opts the whole program back
    to real shared-library externs; `--system-libs=m,pthread` does that only for
    selected soname stems and leaves the rest on the bundled crtl path. }
  CUseSystemLibs   : Boolean;
  CSystemLibs       : array[0..MAX_C_INCLUDE_DIRS-1] of AnsiString;
  CSystemLibCount   : Integer;
  CrtlSrcPulled    : array[0..MAX_C_INCLUDE_DIRS-1] of AnsiString;
  CrtlSrcPulledCount : Integer;

  { Ordered Pascal-unit (`uses`) search roots from `-Fu<dir>` (FPC-style) and
    `-I<dir>`. Searched in LoadUnit after the including file's own directory and
    before the compiler-anchored builtin/RTL/LCL dirs — so a project or
    per-platform unit dir (e.g. lib/rtl/platform/posix/) can supply or override a
    unit by name (the PAL backend-selection mechanism). }
  PasUnitDirs     : array[0..MAX_PAS_UNIT_DIRS-1] of AnsiString;
  PasUnitDirCount : Integer;

  { C preprocessor state. Macro text is pooled to avoid string-array BSS cost. }
  CPrepOut      : AnsiString;
  { Amortized-growth bookkeeping for CPrepOut: CPrepOut carries geometric spare
    capacity (its physical Length), CPrepOutLen is the logical byte count. Without
    this, appending each output char via SetLength(len+1) reallocated+copied the
    whole (multi-MB) output per char — O(n^2), 33s to preprocess the GTK2 headers
    (perf-gtk-system-header-parse). CPrepLineExp is the per-line expansion scratch. }
  CPrepOutLen   : NativeInt;
  CPrepLineExp  : AnsiString;
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
  CPMVariadic   : array[0..MAX_CPREP_MACROS-1] of Boolean;   { `...` / __VA_ARGS__ }
  CPMCount      : Integer;
  { Macro-name hash index: without it CPFindMacro linear-scanned all CPMCount
    entries per lookup, so preprocessing a header that defines thousands of macros
    (GTK/glib) and expands ~1M identifiers was O(identifiers * macros). Chain is
    newest-first (redefine stacks, newest wins); #undef only tombstones NameLen so
    chains never need unlinking (a dead entry fails the name-equality check). }
  CPMHashHead   : array[0..CPREP_MACRO_HASH_SIZE-1] of Integer;
  CPMHashNext   : array[0..MAX_CPREP_MACROS-1] of Integer;
  { #pragma push_macro/pop_macro stack: each push snapshots the active macro
    index for a name; pop appends a fresh macro entry cloning that snapshot. }
  CPPushNameOff : array[0..255] of Integer;
  CPPushNameLen : array[0..255] of Integer;
  CPPushMi      : array[0..255] of Integer;   { snapshot macro idx, -1 = was undefined }
  CPPushCount   : Integer;
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
  CPExprDepth   : Integer;   { #if macro-atom recursion guard (chained #defines) }

  { Reserved BSS slot 0: initial rsp (for argv access) }
  BSS_INITIAL_RSP : Integer;  { always 0; set in ParseProgram init }
  BSS_INTBUF      : Integer;
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
  BSS_PEEK_VALID  : Integer;  { Eof one-byte stdin pushback: 1 if a byte is held }
  BSS_PEEK_BYTE   : Integer;  { the held pushback byte (consumed by next read) }
  BSS_IO_OWNER    : Integer;  { --threadsafe I/O statement lock: owning thread id (gettid), 0 = free }
  BSS_IO_DEPTH    : Integer;  { --threadsafe I/O statement lock: reentrancy depth of the owner }
  BSS_SIG_HOOKS   : Integer;  { 64 qword slots: user handler proc address per signal 1..64 (slot = (sig-1)*8), 0 = none. Written by SetSignalHandler, read by the emitted signal dispatch stub. }
  BSS_SIG_SCRATCH : Integer;  { 32-byte kernel struct sigaction build area for the install/redefault stubs (handler, flags, restorer, mask) }
  ExceptionUsed   : Boolean;
  ProcExceptionCleanupFrameActive: Boolean;
  InLValueWrite   : Boolean;
  CurWriteFd      : Integer; { fd a write/writeln syscall targets; STDOUT by default, 2 for writeln(StdErr,..) }
  CAttrPacked     : Boolean;
  CAttrAligned    : Boolean;
  CAttrAlignValue : Integer;
  CLexUnsignedSuffix : Boolean; { last C integer literal had a u/U suffix }
  CLexHexOctal : Boolean; { last C integer literal was hex or octal (radix<>10) — C types these through the unsigned rungs of the constant ladder, decimals do not }
  { Declaration-order gating for program/unit GLOBAL VARIABLES (declare-before-use,
    FPC-parity). The whole-program pre-scan registers every global before any body
    compiles, which otherwise lets a routine bind a global declared textually below
    it (a stray-name / reentrancy hazard, e.g. a shared loop counter). Each global
    var records the token index where it was declared; while compiling a routine
    body, FindSym hides a global whose declaration token is past the body's header
    token (i.e. declared after the routine). Token positions are absolute into the
    single expanded Tokens[] stream, so methods, forward decls and unit/builtin
    routines are all handled by real source position — no registration-order
    bookkeeping. Types/consts/procs stay forward-visible (legit mutual recursion). }
  CurBodyHdrTok    : Integer;    { token index of the routine body being compiled; high = see all (outside a body) }
  DeclOrderStrict  : Boolean;    { hide a global var declared after the current body's header }
  LaxDeclOrder     : Boolean;    { user opt-out (--lax-decl-order / {$DECLORDER OFF}): when True, ParseProgram sets DeclOrderStrict := False — restores the old lenient forward-visible-global behavior }
  NoDivCheck       : Boolean;    { user opt-out (--no-div-check): skip the pre-divide zero check on integer div/mod (FPC-style runtime error 200 is the default; without the check x86 raw-SIGFPEs and ARM silently yields 0). x86-64 only for now. }
  NoSignals        : Boolean;    { user opt-out (--no-signals): skip the default signal runtime (SIGINT/SIGTERM dispatch + SetSignalHandler support). Default ON, no auto-detection — user decision, see feature-signal-handlers. x86-64 Linux only for now. }
  StrictIR         : Boolean;    { user opt-in (--strict-ir): IRVerify hard-errors on any IR_UNSUPPORTED node (a frontend could not lower an AST node). Default OFF so an in-development frontend (e.g. Track R Rust) that still emits IR_UNSUPPORTED is not broken. Turns "frontend gap -> silent nondeterministic self-host miscompile" into an immediate compile error naming the AST kind. See feature-selfhost-guard-ir-unsupported / bug-selfhost-multifn-ifelse-miscompile. }
  ExcSetJmpAddr   : Integer;
  ExcLongJmpAddr  : Integer;
  ExcRaiseAddr    : Integer;
  CoroutineUsed   : Boolean;
  CoSwitchAddr    : Integer;  { code address of the bare CoSwitch context-switch stub }
  CloneStubAddr   : Integer;  { code address of the bare clone+trampoline thread-spawn stub; 0 = not yet emitted (lazy) }
  CurProcIsAsync  : Boolean;  { parsing the body of an `; async;` routine (legalises `await`) }
  CurProcIsGenerator : Boolean; { parsing the body of a `; generator;` routine }
  CurGenSelfSym   : Integer;  { sym idx of the generator body's hidden self-pointer local }
  CurGenSeenYield : Boolean;  { a yield was seen in the current generator body (validation) }
  GenTryDepth     : Integer;  { try-nesting while parsing a generator body (yield-in-try is illegal in v1) }
  CurProcIsStackless : Boolean; { parsing the body of a `; generator; stackless;` routine }
  CurGenStateCtr  : Integer;  { next state number to assign to a yield in the current stackless body }
  CurGenSlotNext  : Integer;  { next persistent-slot index (offset = SL_OFF_SLOTS + 8*idx) }
  CurGenScopeBase : Integer;  { first sym idx of the current stackless generator's scope (save/restore only its own slots, never leaked globals) }
  CurGenElemOff   : Integer;  { record element: byte offset of the CURRENT record region in the instance (-1 = scalar element) }
  CurGenElemRecId : Integer;  { record element: record id of the yielded record type }
  GenStateLabelIdx : array[0..MAX_GEN_STATES-1] of Integer; { resume label (GotoLabel slot) per state }
  SigRestorerAddr : Integer;  { code offset of the SA_RESTORER stub (rt_sigreturn) — x86-64 requires a userspace restorer }
  SigDispatchAddr : Integer;  { code offset of the shared signal dispatch handler (hook table -> call, else redefault + re-raise) }
  SigInstallAddr  : Integer;  { code offset of the callable install routine: edi = signal number -> rt_sigaction(sig, dispatch) }
  SigSetHookAddr  : Integer;  { code offset of the SetSignalHandler stub: edi = signal, rsi = handler address -> store hook slot, fall through into SigInstallAddr }
  IOLockAddr  : Integer;  { code offset of the --threadsafe I/O statement-lock acquire stub (reentrant owner-tid spinlock over BSS_IO_OWNER/DEPTH) }
  IOUnlockAddr: Integer;  { code offset of the matching release stub }
  Div0StubAddr : Integer;  { code offset of the shared div-by-zero abort stub
                             (write "Runtime error 200 ..." + exit_group(200)),
                             emitted unconditionally on x86-64; the fallback
                             call target when builtinheap (PXXDivZero) is not
                             pulled in. See bug-integer-div-zero-sigfpe-uncatchable. }
  AnsiStrReleaseAddr : Integer;
  AnsiStrRetainAddr  : Integer;
  AnsiStrFromLiteralAddr : Integer;
  AnsiStrUniqueAddr : Integer;
  AnsiStrConcatAddr : Integer;
  AnsiStrLoadFileAddr : Integer;

  TokChars   : array[0..STRING_CAP-1] of Char;
  TokCharLen : Integer;
  { File-read staging buffer for LoadFile. Global (BSS) rather than an 8 MB stack
    local: an 8 MB frame overflows a default 8 MB process stack (the FPC-seeded
    cold-bootstrap binary segfaulted in LoadFile's prologue). Single-use and never
    re-entered (include loads are sequential), so a shared global is safe here. }
  LoadFileBuf : array[0..STRING_CAP-1] of Byte;
  Tokens     : array[0..MAX_TOKENS-1] of TRawToken;
  TokPackRecords : array[0..MAX_TOKENS-1] of Integer;
  CAttrFlags : array[0..MAX_TOKENS-1] of Byte;
  CAttrAlignValues : array[0..MAX_TOKENS-1] of Integer;
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

  { Constant global-var initializers (`var x: T = v;` / `= (e0,e1,...)`). Each
    entry is one assignment `sym` or `sym[elem] := value`, compiled into the
    program entry just before `main begin`. }
  PendingInitSym  : array[0..MAX_PENDING_INITS-1] of Integer;  { target symbol }
  PendingInitElem : array[0..MAX_PENDING_INITS-1] of Integer;  { array index, or -1 for a scalar }
  PendingInitVal  : array[0..MAX_PENDING_INITS-1] of Int64;    { constant value }
  PendingInitValAux: array[0..MAX_PENDING_INITS-1] of Integer; { string length / spare }
  PendingInitKind : array[0..MAX_PENDING_INITS-1] of Integer;  { 0=int, 1=string literal, 2=proc addr }
  PendingInitTk   : array[0..MAX_PENDING_INITS-1] of Integer;  { value type kind }
  { Record typed-const field: source span of the field name, so the emitter builds
    `sym.field := value` instead of `sym[elem]`. SOff = -1 when not a field. }
  PendingInitFOff : array[0..MAX_PENDING_INITS-1] of Integer;
  PendingInitFLen : array[0..MAX_PENDING_INITS-1] of Integer;
  PendingInitCount: Integer;

  { Routine-LOCAL typed-const initializers (`const T: array[..] of X = (..)`
    inside a routine). Same shape as PendingInit but compiled into the routine's
    own prologue (after managed-local zero-init, before the body) so each call
    re-initializes its stack-resident table. Reset at routine entry. }
  LocalInitSym  : array[0..MAX_LOCAL_INITS-1] of Integer;
  LocalInitElem : array[0..MAX_LOCAL_INITS-1] of Integer;
  LocalInitVal  : array[0..MAX_LOCAL_INITS-1] of Int64;
  LocalInitKind : array[0..MAX_LOCAL_INITS-1] of Integer;  { 0=int, 1=string literal; mirrors PendingInitKind }
  LocalInitTk   : array[0..MAX_LOCAL_INITS-1] of Integer;
  LocalInitFOff : array[0..MAX_LOCAL_INITS-1] of Integer;  { record-field span (SOff=-1 if not a field) }
  LocalInitFLen : array[0..MAX_LOCAL_INITS-1] of Integer;  { field-name length, or (Kind=1) string literal length }
  LocalInitCount: Integer;

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
  ASTLine    : array[0..MAX_AST-1] of Integer; { source line of this node (CurTok.Line at alloc), 0 if unknown — DWARF -g }
  ASTNodeCount : Integer;

  IRKind  : array[0..MAX_IR-1] of Integer;
  IRA     : array[0..MAX_IR-1] of Integer;
  IRB     : array[0..MAX_IR-1] of Integer;
  IRC     : array[0..MAX_IR-1] of Integer;
  IRIVal  : array[0..MAX_IR-1] of Int64;
  IRTk    : array[0..MAX_IR-1] of Integer;
  { Hidden caller-destination for a call that returns an aggregate / frozen string
    by a caller-owned buffer. For IR_CALL the dest IR_LEA is in IRC; IR_VIRTUAL_CALL
    and IR_CALL_IND have no free operand, so their dest node lives here (-1 = none).
    bug-frozen-string-result-global-not-reentrant. }
  IRCallDest : array[0..MAX_IR-1] of Integer;
  IRSetLenBaseRec : array[0..MAX_IR-1] of Integer; { IR_SETLEN_DYN on a non-symbol (field) target: base element record id when IRIVal<0; -1/REC_NONE otherwise }
  { Pending open-array copy-out (writeback) for a static array passed to a
    `var`/`out` open-array parameter. The call site copies the static array into
    a header'd dyn temp (so Length/High and indexing work over the param), then
    after the call copies the temp's data back to the static array. A small fixed
    stack, kept nested-call-safe by saving/restoring the count around each call's
    arg lowering. See IRLowerCallArg + the AN_CALL flush. }
  PendOAWBCount : Integer;
  PendOAWBTemp  : array[0..63] of Integer;  { hidden dyn-array temp sym }
  PendOAWBDest  : array[0..63] of Integer;  { static-array argument AST node, re-lowered via IRLowerAddress for the copy-out destination (simple var or record/class field) }
  PendOAWBSize  : array[0..63] of Integer;  { byte count to copy back }
  { Marks an IR node as a statement root (its result is discarded). The top-
    level emitter only emits roots; calls whose value is consumed are emitted
    via their parent. Needed for IR_VIRTUAL_CALL, whose IRIVal holds the VMT
    slot and so cannot double as the IR_CALL=1 statement flag. }
  IRStmtRoot : array[0..MAX_IR-1] of Boolean;
  IRLine  : array[0..MAX_IR-1] of Integer; { source line of this IR instr (from CurLowerLine), 0 if unknown — DWARF -g }
  IRCount : Integer;

  { DWARF -g (Tier 1): address→line rows collected at emit, and a single byte
    buffer that all .debug_* section bytes are built into. e_shoff stays 0 unless
    DebugInfo. See feature-dwarf-debug-info.md. }
  DwarfRowAddr : array[0..MAX_DWARF_ROWS-1] of Integer; { raw Code[] offset of the statement }
  DwarfRowLine : array[0..MAX_DWARF_ROWS-1] of Integer; { source line at that offset }
  DwarfRowPrologueEnd : array[0..MAX_DWARF_ROWS-1] of Boolean; { first row of a proc body → DW_LNS_set_prologue_end (gdb skips the prologue to here) }
  DwarfRowCount : Integer;
  DwarfLastLine : Integer;   { dedup tracker, reset per proc }
  DwarfProcFirstRow : Boolean;  { next recorded row is this body's first → mark prologue_end }
  DbgBuf : array[0..MAX_DWARF-1] of Byte;
  DbgLen : Integer;
  { Section metadata filled by BuildDwarfSections — offsets/sizes are WITHIN
    DbgBuf; name fields are byte offsets into the .shstrtab span. }
  DbgLineSecOff, DbgLineSecSize : Integer;
  DbgInfoSecOff, DbgInfoSecSize : Integer;
  DbgAbbrevSecOff, DbgAbbrevSecSize : Integer;
  DbgFrameSecOff, DbgFrameSecSize : Integer;
  DbgShStrSecOff, DbgShStrSecSize : Integer;
  DbgNmLine, DbgNmInfo, DbgNmAbbrev, DbgNmFrame, DbgNmShStr : Integer;
  DbgNmText, DbgNmData, DbgNmBss : Integer;
  DbgShFlags, DbgShAddr, DbgShAlign : Int64;  { per-section header fields for writeShdr64 (avoids the >6-param call landmine) }
  DbgSrcName : AnsiString;   { source filename recorded in the line table + CU DIE }
  DbgMainTokEnd : Integer;   { token index just past the main source file; nodes from appended units (TokPos beyond this) get ASTLine 0 so the single-file line table stays unambiguous }
  DbgProgName : AnsiString;  { program name → main-body DW_TAG_subprogram }
  DbgMainBodyStart, DbgMainBodyEnd : Integer;  { Code[] range of the program body }
  DbgGlobalScopeBase : Integer;  { Syms[] index after runtime units, before main decls — globals above this are the program's own }
  DbgBssBase : Int64;            { runtime base address of BSS, for global-var DW_OP_addr locations }
  { Per-target DWARF parameters (set by DbgSetArchParams). x86-64 + aarch64 use
    8-byte addresses; i386 + arm32 use 4. esp targets get no -g. }
  DbgPtrSize : Integer;          { address byte width: 8 (x86-64/aarch64) or 4 (i386/arm32) }
  DbgRegFrame : Integer;         { DWARF reg of the frame base (rbp=6, ebp=5, x29=29, r11=11) }
  DbgRegRA : Integer;            { DWARF return-address column (rip=16, i386=8, x30=30, lr=14) }
  DbgRegSP : Integer;            { DWARF reg of the stack pointer (rsp=7, esp=4, sp=31, sp=13) }
  DbgRegLR : Integer;            { DWARF reg of the link register saved in the prologue (aarch64/arm32) }
  DbgFrameSavesLR : Boolean;     { prologue stores the return reg in the frame (aarch64/arm32) vs `call` pushed it (x86) }
  DbgPrologAdv1, DbgPrologAdv2 : Integer;  { byte lengths of the two prologue steps for FDE advance_loc }

  { DWARF Tier 3 side tables. Symbol slots recycle across procs (SymCount is
    restored at each proc's end), so per-proc params/locals must be snapshotted
    during compilation — they are gone by writeELF time. DbgVarProc = owning
    Procs[] index, or -1 for a program-body global. }
  DbgVarProc    : array[0..MAX_DBG_VARS-1] of Integer;
  DbgVarName    : array[0..MAX_DBG_VARS-1] of AnsiString;
  DbgVarTk      : array[0..MAX_DBG_VARS-1] of Integer;
  DbgVarRec     : array[0..MAX_DBG_VARS-1] of Integer;
  DbgVarOff     : array[0..MAX_DBG_VARS-1] of Integer;   { rbp-relative (local/param) or BSS offset (global) }
  DbgVarIsParam : array[0..MAX_DBG_VARS-1] of Boolean;
  DbgVarIsGlobal: array[0..MAX_DBG_VARS-1] of Boolean;
  DbgVarIsRef   : array[0..MAX_DBG_VARS-1] of Boolean;   { by-ref param: location needs a trailing deref }
  DbgVarIsArray : array[0..MAX_DBG_VARS-1] of Boolean;
  DbgVarArrLen  : array[0..MAX_DBG_VARS-1] of Integer;   { >=0 fixed array; <0 dynamic }
  DbgVarElemTk  : array[0..MAX_DBG_VARS-1] of Integer;
  DbgVarElemRec : array[0..MAX_DBG_VARS-1] of Integer;
  DbgVarCount   : Integer;
  { Type-DIE dedup map (cat, recId, aux) -> .debug_info offset. }
  DbgTypeCat    : array[0..MAX_DBG_TYPES-1] of Integer;
  DbgTypeRecId  : array[0..MAX_DBG_TYPES-1] of Integer;
  DbgTypeAux    : array[0..MAX_DBG_TYPES-1] of Integer;
  DbgTypeOff    : array[0..MAX_DBG_TYPES-1] of Integer;
  DbgTypeCount  : Integer;
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
  UClsForward : array[0..MAX_UCLASS-1] of Boolean; { forward stub `TFoo = class;` — the full decl reuses this entry (else its base/fields land on a shadowed duplicate; FindUClass returns the first match) }
  UClsIsInterface : array[0..MAX_UCLASS-1] of Boolean; { CORBA interface type: methods are slot signatures (no bodies/fields); a var of it is a 16-byte fat pointer {IMT, instance} }
  UClsIsComInterface : array[0..MAX_UCLASS-1] of Boolean; { COM/ARC interface ({$interfaces com}): reference-counted via the IMT _Release slot (slot 2). Compiler inserts _AddRef/_Release at assign/param/result/scope-exit/unwind. Default off (CORBA, no refcount). }
  UClsCount  : Integer;

  { Per-(class, interface) Interface Method Table: a Data[] array of code
    addresses, one per interface method slot, filled (like the VMT) via
    MethodFixups to the class's implementing methods. A class->interface
    assignment captures IMTOff as the fat pointer's first word. }
  IMTClass : array[0..MAX_IMT-1] of Integer;  { implementing class ci }
  IMTIntf  : array[0..MAX_IMT-1] of Integer;  { interface ci }
  IMTOff   : array[0..MAX_IMT-1] of Integer;  { Data[] offset of the IMT }
  IMTCount : Integer;

  UFldNOff   : array[0..MAX_UFIELD-1] of Integer;
  UFldNLen   : array[0..MAX_UFIELD-1] of Integer;
  UFldOff_   : array[0..MAX_UFIELD-1] of Integer;
  UFldTk     : array[0..MAX_UFIELD-1] of Integer;
  UFldRec_   : array[0..MAX_UFIELD-1] of Integer;
  UFldPtrElemTk : array[0..MAX_UFIELD-1] of Integer;
  UFldPtrElemRec : array[0..MAX_UFIELD-1] of Integer;
  UFldProcSig : array[0..MAX_UFIELD-1] of Integer; { procedural-type field: signature proc index (Procs[] entry) for an indirect call `rec.field(args)`; -1 = not proc-typed }
  UFldIsArray : array[0..MAX_UFIELD-1] of Boolean;
  UFldArrLen  : array[0..MAX_UFIELD-1] of Integer;
  UFldDynDepth : array[0..MAX_UFIELD-1] of Integer; { dynamic-array field nesting: 0 = not a dynamic array, 1 = array of T, 2 = array of array of T, ... (UFldArrLen = -1 also marks dynamic, mirroring the symbol convention) }
  UFldPub    : array[0..MAX_UFIELD-1] of Integer;  { 1 = published, 0 = other }
  UFldSetEnumId : array[0..MAX_UFIELD-1] of Integer; { set field: element enum type index for `set of TEnum`, else -1. Drives `for e in obj.field` range }
  UFldSetElemTk : array[0..MAX_UFIELD-1] of Integer; { set field: element TTypeKind ordinal (tyChar/enum-as-integer), else 0 }
  UFldBitWidth : array[0..MAX_UFIELD-1] of Integer; { C named bit-field width in bits; 0 = ordinary field }
  UFldBitShift : array[0..MAX_UFIELD-1] of Integer; { C named bit-field least-significant bit offset within storage unit }
  UFldBitBytes : array[0..MAX_UFIELD-1] of Integer; { C named bit-field storage bytes used for masked RMW }
  { 2-D fixed-array fields: `m: array[a..b, c..d] of T`, flattened to 1-D
    storage; r.m[i,j] / r.m[i][j] index via (i-lo1)*span2 + (j-lo2). }
  UFldArrNDims  : array[0..MAX_UFIELD-1] of Integer;
  UFldArrDimLo  : array[0..MAX_UFIELD*MAX_ARR_DIMS-1] of Integer;
  UFldArrDimSpan: array[0..MAX_UFIELD*MAX_ARR_DIMS-1] of Integer;
  UFldCount  : Integer;

  UMthNOff   : array[0..MAX_UMETH-1] of Integer;
  UMthNLen   : array[0..MAX_UMETH-1] of Integer;
  UMthProc_  : array[0..MAX_UMETH-1] of Integer;
  UMthVirSlot : array[0..MAX_UMETH-1] of Integer;
  UMthIsStatic : array[0..MAX_UMETH-1] of Boolean;
  UMthIsCtor   : array[0..MAX_UMETH-1] of Boolean; { declared `constructor` — TClass.AnyCtor(args) builds a metaclass-new, not a method call }
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
  UPropIsIndexed : array[0..MAX_UPROP-1] of Boolean;  { array property: `property Items[i: TIdx]: T` — getter/setter take the index as an extra arg }
  UPropIsDefault : array[0..MAX_UPROP-1] of Boolean;  { `default;` indexed property: `obj[i]` lowers through it }
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

  { Class variables (`class var x: T`): one shared global storage slot per class,
    addressed as TClass.x or instance.x. Registry maps (owning class ci, name) ->
    the global var sym; inherited (a subclass sees a parent's class var). }
  ClassVarCi      : array[0..MAX_TYPEALIAS-1] of Integer;   { owning class ci }
  ClassVarNOff    : array[0..MAX_TYPEALIAS-1] of Integer;   { name in TokChars }
  ClassVarNLen    : array[0..MAX_TYPEALIAS-1] of Integer;
  ClassVarSym     : array[0..MAX_TYPEALIAS-1] of Integer;   { global var sym idx }
  ClassVarCount   : Integer;
  LastTypeEnumId  : Integer;  { set by ParseTypeKind: enum type index or -1 }
  LastTypeSetEnumId : Integer;  { set by ParseTypeKind for set types: element enum index or -1 }
  LastTypeSetElemTk : Integer;  { set by ParseTypeKind for set types: element TTypeKind ordinal }

  { Named type aliases. Phase 2: pointer aliases (PFoo = ^TFoo) carry an element
    type so the deref/index machinery knows what they point at. }
  AliasNOff    : array[0..MAX_TYPEALIAS-1] of Integer;  { alias name in TokChars }
  AliasNLen    : array[0..MAX_TYPEALIAS-1] of Integer;
  AliasTk      : array[0..MAX_TYPEALIAS-1] of Integer;  { resolved TTypeKind ordinal }
  AliasElemTk  : array[0..MAX_TYPEALIAS-1] of Integer;  { pointer element TTypeKind ordinal }
  AliasElemRec : array[0..MAX_TYPEALIAS-1] of Integer;  { pointer element record/class id }
  AliasPtrDepth : array[0..MAX_TYPEALIAS-1] of Integer; { pointer alias depth, 0 for non-pointer/unknown }
  AliasPtrBaseTk : array[0..MAX_TYPEALIAS-1] of Integer; { pointer alias ultimate base TTypeKind ordinal }
  AliasPtrBaseRec : array[0..MAX_TYPEALIAS-1] of Integer; { pointer alias ultimate base record/class id }
  AliasProcSig : array[0..MAX_TYPEALIAS-1] of Integer;  { procedural-type alias: signature proc index (Procs[] entry, BodyAddr=-1); -1 = not a proc type }
  AliasTargetNOff : array[0..MAX_TYPEALIAS-1] of Integer;
  AliasTargetNLen : array[0..MAX_TYPEALIAS-1] of Integer;
  AliasCount   : Integer;

  { Named fixed-array types: `type TA = array[lo..hi (, lo2..hi2)] of T`.
    Resolved when a var/field/param uses the name. Flattened bounds in Lo/Hi
    (0..span1*span2-1 for 2-D); 2-D dims in the Arr2* fields. }
  ArrTypeName   : array[0..MAX_TYPEALIAS-1] of AnsiString;
  ArrTypeLo     : array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeHi     : array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeElemTk : array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeElemRec: array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeNDims  : array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeDimLo  : array[0..MAX_TYPEALIAS*MAX_ARR_DIMS-1] of Integer;
  ArrTypeDimSpan: array[0..MAX_TYPEALIAS*MAX_ARR_DIMS-1] of Integer;
  ArrTypeIsDyn  : array[0..MAX_TYPEALIAS-1] of Boolean;   { `array of T` alias }
  ArrTypeDynDepth: array[0..MAX_TYPEALIAS-1] of Integer;
  ArrTypeCount  : Integer;

  { Untyped string constants `const Name = 'literal'`. Stored as the literal's
    source span; a use of the name builds an AN_STR_LIT over that span. }
  StrConstName : array[0..MAX_TYPEALIAS-1] of AnsiString;
  StrConstSOff : array[0..MAX_TYPEALIAS-1] of Integer;
  StrConstSLen : array[0..MAX_TYPEALIAS-1] of Integer;
  StrConstCount: Integer;

  { Named set constants (`const S = [1,2,3]` / `const S: TS = [..]`). The 32-byte
    bitmask is baked into Data[] at decl time; a use resolves to AN_SET_CONST_REF
    carrying the data offset (lowered via IR_SET_LIT, like a literal). }
  SetConstName : array[0..MAX_TYPEALIAS-1] of AnsiString;
  SetConstOff  : array[0..MAX_TYPEALIAS-1] of Integer;   { Data[] offset of the mask }
  SetConstEnumId : array[0..MAX_TYPEALIAS-1] of Integer; { element enum type id, or -1 }
  SetConstCount: Integer;

  { Scratch filled by NodeArrNDInfo for the multidim array a node references. }
  NDInfoNDims : Integer;
  NDInfoLo    : array[0..MAX_ARR_DIMS-1] of Integer;
  NDInfoSpan  : array[0..MAX_ARR_DIMS-1] of Integer;
  NDIdxNode   : array[0..MAX_ARR_DIMS-1] of Integer; { parsed index exprs for a multidim ref }

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

const
  MAX_WS_STACK = 64;   { Whitespace frontend compile-time expression stack }

var
  isC, isBasic, isNilPy, isAsm, isRust, isAda, isZig, isLol, isWs, isF90, isAlgol, isErl: Boolean;

  { Whitespace frontend state (wparser.inc) — here rather than in the
    include because a var section that late in the chain trips the
    impl-prescan's declared-later check. }
  WsPos: Integer;                                 { read cursor into Source }
  WsStk: array[0..MAX_WS_STACK-1] of Integer;     { AST node ids }
  WsSp: Integer;
  WsStmtList: Integer;
  WsDone: Boolean;
