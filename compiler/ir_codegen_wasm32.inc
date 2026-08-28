{ SPDX-License-Identifier: MPL-2.0 }
{ ir_codegen_wasm32.inc — the wasm32 backend. Phase 2: straight-line codegen.

  IREmitMachineCode dispatches here when TargetArch = TARGET_WASM32. It is
  called ONCE PER BODY with CurProc in scope (ir_codegen.inc:10053), which is
  the fact the whole design rests on: **one call = one wasm function.** The
  register backends append to a flat Code[] and fix up label positions; there is
  no such thing here, so this file builds into the module model in wasmenc.inc
  instead and every body becomes its own (func ...).

  Design notes live in devdocs/dev/wasm/phase2-shadow-stack.md. The two that
  shape this file:

  * TWO STACKS. Expression temporaries live on wasm's own operand stack — free,
    typed, validated — and the register backends' push/pop dance around a binop
    is DELETED, not translated. The shadow stack in linear memory holds named
    slots only: locals, params, Result. A value moves to a slot the moment it
    must survive a branch, a call's exception check, or an `&`.
  * NATIVE i64/f64. wasm32 has 4-byte pointers AND single-opcode 64-bit
    arithmetic, a combination none of the six register targets has. Do not port
    riscv32's lo:hi pair model or its soft-float call-outs.

  Frame layout. Pascal allocates locals downward and records Syms[i].Offset as
  NEGATIVE (symtab.inc:4115, `Offset := -FrameSize`), the [rbp-N] shape. $fp
  here points at the BOTTOM of the frame, so a slot at Pascal offset -N sits at
  $fp + (FrameSize - N). That conversion happens in WasmSlotAddr and nowhere
  else. Globals are not on the frame at all; the memory map is documented at
  WASM_BSS_BASE below. }

{ ===== incremental bringup =====

  Phase 2 cannot compile "a small program" in isolation: even a trivial one
  pulls compiler/builtin/builtinheap.pas, whose bodies use IR_STORE_MEM, calls
  and control flow long before anything the user wrote does. Measured on the
  backend's first ever run — it stopped at IR op 21 in builtinheap, not in the
  test program. So "handle the ops my test needs" is not a reachable milestone;
  the reachable one is "handle the ops the builtins need", which is most of
  Phases 2-4 at once.

  Rather than block all verification behind that, a body the backend cannot yet
  lower is emitted as a single `unreachable` and RECORDED. The module still
  builds, the bodies that ARE lowered can be called and diffed against the
  native build, and an unlowered body fails loudly at run time instead of
  quietly computing something.

  This is scaffolding, and it is safe only because it reports itself: the
  summary below prints unconditionally, so a module with holes can never be
  mistaken for a complete one. It comes out when the op coverage is complete —
  at which point the counter reads zero and the mechanism is inert. }

var
  WasmModuleStarted : Boolean = False;
  WasmBodyBroken    : Boolean = False;  { current body hit an unlowered op }
  WasmBrokenReason  : AnsiString = '';
  WasmBrokenCount   : Integer = 0;
  WasmLoweredCount  : Integer = 0;
  WasmBrokenNames   : AnsiString = '';
  WasmBrokenUnlisted: Integer = 0;   { broken bodies past the listing cap }
  WasmStubCount     : Integer = 0;   { declaration-only stubs — NOT a coverage gap }
  WasmStubNames     : AnsiString = '';
  WasmGSp           : Integer = -1;   { the $sp global's index }
  WasmCurSlot       : Integer = -1;   { function slot being emitted }
  WasmCurFrame      : Integer = 0;    { this body's frame size, bytes }
  WasmLocalFp       : Integer = 0;    { local index of $fp }
  WasmLocalPc       : Integer = -1;   { local index of $pc, -1 if no dispatch }
  WasmBlockCount    : Integer = 0;    { basic blocks in the current body }
  WasmBodySerial    : Integer = 0;    { stamps WasmLabelStamp, see below }
  WasmHasTerminate  : Boolean = False;{ body contains an early Exit }
  WasmNeedDispatch  : Boolean = False;{ ... so the dispatch must exist }
  WasmCurBlk        : Integer = 0;    { basic block being emitted, for the
                                        post-call exception check, which is
                                        needed in VALUE position where the
                                        emitters take no block argument }
  WasmGExcPend      : Integer = -1;   { the $exc_pending global, allocated on
                                        first use so a program without a raise
                                        emits a module without it }
  WasmExcSites      : Integer = 0;    { IR_EXC_ENTER sites in this body }
  WasmExcHasHandler : Boolean = False;{ ... any at all }
  WasmExcTopLocal   : Integer = -1;   { scratch i32 holding the chain head }
{ ONE reusable spill local per value type per body, not one per call site. A
  call result's life here is three instructions — set, check, get — and the
  check cannot itself contain a call, so nested calls cannot overlap. Per-site
  locals would add one to the locals vector for every call in the program. }
  WasmCRLocal       : array[0..3] of Integer;
  WasmStrDepth      : Integer = 0;    { string-expression nesting depth }
  WasmStrLocN       : Integer = -1;   { scratch: the handle being published }
  WasmStrLocS       : Integer = -1;   { scratch: the slot's address }
  WasmStrLocO       : Integer = -1;   { scratch: the handle being replaced }
  WasmStrLocZ       : Integer = -1;   { scratch: a materialised source value }
  { The `in` operand, held while every member is tested against it. Two, because
    the comparison happens at the value's own width and a body may contain both
    an i32 and an i64 `in`. Reused across every `in` in a body for the same
    reason the string scratch slots are: the value is fully materialised before
    the first test, and no `in` can be nested inside another one's operand. }
  WasmSetInLoc      : Integer = -1;
  WasmSetInLoc64    : Integer = -1;
  WasmCurNRes       : Integer = 0;    { this body's result count (0 or 1) }
  WasmCurResVt      : Byte = 0;       { ... and its wasm type when 1 }

{ Pascal proc index -> the wasm function slot it was given, or -1. A call may
  name a proc whose body has not been emitted yet, so the slot is reserved on
  first mention and filled in when the body arrives. Any slot still unfilled
  when the module is written gets an `unreachable` body and is REPORTED — a
  declared wasm function with no body is not a module. }
  WasmProcSlot      : array[0..MAX_PROCS-1] of Integer;

{ Label id -> the basic block it starts, stamped with the body that defined it.
  The stamp is not defensive clutter: these arrays outlive a body, Pascal has no
  cross-procedure goto, so a jump whose target was not defined by THIS body can
  only be a compiler bug — and without the stamp it would silently read another
  function's block number and branch to whatever is there. A jump to the wrong
  code is the exact failure this backend's structure otherwise makes
  impossible, so it is worth two arrays to keep it that way. }
  WasmLabelBlock    : array[0..MAX_IR-1] of Integer;
  WasmLabelStamp    : array[0..MAX_IR-1] of Integer;

{ IR_EXC_ENTER node -> which handler frame in this body's shadow frame it owns.
  One frame per SITE rather than per dynamic entry, which is correct for the
  same reason a Pascal local is: a site cannot be active twice in one
  invocation without being lexically nested inside itself, and recursion gets a
  new $fp. }
  WasmExcSlot       : array[0..MAX_IR-1] of Integer;

{ Locals for string EXPRESSIONS, pooled by nesting DEPTH rather than per site.
  A fresh local per site is what makes nesting safe, and it is also what ran a
  body out of them: the encoder allows 288 params+locals per body and a
  program with two dozen string operators in `main` wants eight apiece, which
  is `wasm: too many params+locals` — a loud failure, but a needless one.

  Depth is the real bound. An operand's three parts are live only from the
  moment it is split until the RTL call a few instructions later, and anything
  nested inside that operand has already finished by then, so SIBLINGS can
  share slots and only LEVELS need distinct ones. Lazily allocated, so a body
  that never nests pays for one level. }
  WasmStrPool       : array[0..15, 0..7] of Integer;

{ Mark the body being emitted as not-yet-lowerable. Deliberately NOT Error:
  Error aborts the compile, and one unimplemented op in a builtin would then
  block every test of every op that IS implemented. }
procedure WasmUnsupported(const why: AnsiString);
begin
  if WasmBodyBroken then Exit;     { keep the FIRST reason, not the last }
  WasmBodyBroken := True;
  WasmBrokenReason := why;
end;

{ ===== the type model =====

  A Pascal type has TWO wasm-facing widths and they are not the same number:

    * its VALUE type — what a signature, a local and the operand stack see.
      wasm has exactly four (i32, i64, f32, f64), so a Byte, a Char and a
      Pointer all arrive as i32.
    * its MEMORY width — how many bytes its frame slot actually occupies.
      symtab packs a frame by TypeSize with no padding to a machine word
      (symtab.inc:4113, `FrameSize := AlignTo(FrameSize + sz, align)`), so a
      Boolean local is ONE byte and another local starts immediately after it.

  Conflating them is not a missing feature, it is a live wrong-value bug in
  both directions: an i32.store into a 1-byte slot writes four bytes and
  destroys the neighbour, and an i32.load out of it reads three bytes of the
  neighbour into the high bits. So the width is carried all the way to the
  opcode — i32.store8 for a Boolean, i32.load16_s for a SmallInt — and the sign
  of a narrow load comes from TypeSigned, because zero- and sign-extension are
  different instructions in wasm rather than a property of the register.

  The DEFAULT IS REFUSE, not i32. A type this function does not recognise
  becoming i32 by falling off the end of an if-chain is exactly the
  silent-wrong-value class this target exists to convert into a hard failure
  (CHARTER.md), so an unclassified type returns False and the body is recorded
  as unlowered instead of being guessed at. }

{ A type kind by NAME. `type 4` is a number the reader has to go look up, and
  a refusal message is read precisely when nobody has the enum in front of
  them. Unknown ordinals still print as a number, which is the honest answer
  for one this list has not been taught. }
function WasmTypeKindName(tk: TTypeKind): AnsiString;
begin
  case tk of
    tyUnknown: WasmTypeKindName := 'tyUnknown';
    tyInteger: WasmTypeKindName := 'Integer';
    tyBoolean: WasmTypeKindName := 'Boolean';
    tyChar:    WasmTypeKindName := 'Char';
    tyString:  WasmTypeKindName := 'String (frozen, inline length prefix)';
    tyRecord:  WasmTypeKindName := 'record';
    tyClass:   WasmTypeKindName := 'class';
    tyPointer: WasmTypeKindName := 'Pointer';
    tySingle:  WasmTypeKindName := 'Single';
    tyDouble:  WasmTypeKindName := 'Double';
    tyVariant: WasmTypeKindName := 'Variant';
    tyAnsiString: WasmTypeKindName := 'AnsiString';
    tyInt8:    WasmTypeKindName := 'ShortInt';
    tyUInt8:   WasmTypeKindName := 'Byte';
    tyInt16:   WasmTypeKindName := 'SmallInt';
    tyUInt16:  WasmTypeKindName := 'Word';
    tyInt32:   WasmTypeKindName := 'LongInt';
    tyUInt32:  WasmTypeKindName := 'LongWord';
    tyInt64:   WasmTypeKindName := 'Int64';
    tyUInt64:  WasmTypeKindName := 'QWord';
    tyNativeInt:  WasmTypeKindName := 'NativeInt';
    tyNativeUInt: WasmTypeKindName := 'NativeUInt';
    tyExtended: WasmTypeKindName := 'Extended';
    tySet:     WasmTypeKindName := 'set';
    tyAuto:    WasmTypeKindName := 'an inferred type';
    { The two kinds tyString was split into. A message that says `type kind 26`
      sends the reader to the enum; one that says ShortString sends them to the
      code. Both are frozen — the distinction is the width of the length
      prefix, which is why the store path treats them alike. }
    tyShortString: WasmTypeKindName := 'ShortString (frozen)';
    tyFixedString: WasmTypeKindName := 'string[N] (frozen)';
  else
    WasmTypeKindName := 'type kind ' + WasmIntStr(Ord(tk));
  end;
end;

{ An operator's SPELLING, for a message. The refusal used to read
  `binary operator 70`, which is a token ordinal — the same thing
  WasmTypeKindName was written to stop doing for types, and for the same
  reason: an ordinal is read precisely when nobody has the enum in front of
  them. Only the operators this backend can emit are listed; anything else is
  already a compiler bug and its number is the useful thing to see. }
function WasmBinopName(op: TTokenKind): AnsiString;
begin
  case op of
    tkPlus:  WasmBinopName := '+';
    tkMinus: WasmBinopName := '-';
    tkStar:  WasmBinopName := '*';
    tkDiv:   WasmBinopName := 'div';
    tkMod:   WasmBinopName := 'mod';
    tkAnd:   WasmBinopName := 'and';
    tkOr:    WasmBinopName := 'or';
    tkXor:   WasmBinopName := 'xor';
    tkShl:   WasmBinopName := 'shl';
    tkShr:   WasmBinopName := 'shr';
    tkEq:    WasmBinopName := '=';
    tkNeq:   WasmBinopName := '<>';
    tkLt:    WasmBinopName := '<';
    tkGt:    WasmBinopName := '>';
    tkLe:    WasmBinopName := '<=';
    tkGe:    WasmBinopName := '>=';
  else
    WasmBinopName := 'operator ' + WasmIntStr(Ord(op));
  end;
end;

{ A symbol for a message. Compiler temporaries have no name, and 'assignment
  to ' followed by nothing is a message that has lost the only thing it was
  carrying — met exactly once, in the refusal that named the variant engine. }
function WasmSymLabel(si: Integer): AnsiString;
begin
  if (si >= 0) and (Syms[si].Name <> '') then WasmSymLabel := Syms[si].Name
  else WasmSymLabel := 'an unnamed temporary (symbol ' + WasmIntStr(si) + ')';
end;

function WasmScalarType(tk: TTypeKind; var vt: Byte): Boolean;
begin
  WasmScalarType := True;
  if TypeIsFloat(tk) then
  begin
    { tyExtended is 10 bytes and wasm has no 80-bit float, so it is refused
      rather than quietly narrowed to f64 — narrowing would compile and give
      slightly wrong answers, which is the outcome this file is built to avoid.
      Phase 7 decides whether Extended maps to Double on this target. }
    if tk = tySingle then vt := WT_F32
    else if tk = tyDouble then vt := WT_F64
    else WasmScalarType := False;
  end
  else if TypeIsOrdinal(tk) or TypeIsPointerSized(tk) then
  begin
    { Both predicates are the symbol table's own, so tyNativeInt follows
      TARGET_PTR_SIZE (4 here) without this file restating the rule, and the
      promotable-int family stays out by construction: symtab deliberately
      keeps it out of TypeIsOrdinal so that integer codegen cannot operate on
      its tag (symtab.inc TypeIsPromoInt). }
    if TypeSize(tk) = 8 then vt := WT_I64 else vt := WT_I32;
  end
  else
    WasmScalarType := False;   { records, sets, variants, frozen strings }
end;

{ A constant's 32-bit interpretation. IRIVal is an Int64 and carries a mask
  like $FFFFFFFF as 4294967295, but the Pascal value is 32 bits wide and its
  32-bit reading is -1. Every register backend gets this for free by moving the
  low half of a register; here the immediate is ENCODED, so the reading has to
  be taken explicitly — and an i32.const of 4294967295 is not merely wrong, it
  is unencodable, so the whole module stops decoding at that byte.

  Another member of the class named in
  bug-a-function-result-assignment-does-not-narrow: a declared width that only
  has to be enforced where something cannot hold the wider value. This one is
  ours rather than the native build's, and it is the friendly end of the class
  — it cannot be encoded, so it cannot ship. }
function WasmWrap32(v: Int64): Int64;
var w: Int64;
begin
  w := v and $FFFFFFFF;
  if w > 2147483647 then w := w - 4294967296;
  WasmWrap32 := w;
end;

{ The value type of an IR node, from the type the lowering recorded on it. }
function WasmNodeType(node: Integer; var vt: Byte): Boolean;
begin
  WasmNodeType := WasmScalarType(IntToTypeKind(IRTk[node]), vt);
end;

{ Emit the load for a value of type tk; the address is already on the operand
  stack. Narrow ordinals extend on the way in, per the note above. }
procedure WasmTypeLoad(tk: TTypeKind; vt: Byte);
begin
  if vt = WT_F32 then WasmMemOp($2A, 'f32.load', 2, 0)
  else if vt = WT_F64 then WasmMemOp($2B, 'f64.load', 3, 0)
  else if vt = WT_I64 then WasmMemOp($29, 'i64.load', 3, 0)
  else if TypeSize(tk) = 1 then
  begin
    if TypeSigned(tk) then WasmMemOp($2C, 'i32.load8_s', 0, 0)
    else WasmMemOp($2D, 'i32.load8_u', 0, 0);
  end
  else if TypeSize(tk) = 2 then
  begin
    if TypeSigned(tk) then WasmMemOp($2E, 'i32.load16_s', 1, 0)
    else WasmMemOp($2F, 'i32.load16_u', 1, 0);
  end
  else WasmMemOp($28, 'i32.load', 2, 0);
end;

{ Emit the store for a value of type tk; address then value are on the stack.
  The narrow forms write exactly the slot's width and nothing beyond it. }
procedure WasmTypeStore(tk: TTypeKind; vt: Byte);
begin
  if vt = WT_F32 then WasmMemOp($38, 'f32.store', 2, 0)
  else if vt = WT_F64 then WasmMemOp($39, 'f64.store', 3, 0)
  else if vt = WT_I64 then WasmMemOp($37, 'i64.store', 3, 0)
  else if TypeSize(tk) = 1 then WasmMemOp($3A, 'i32.store8', 0, 0)
  else if TypeSize(tk) = 2 then WasmMemOp($3B, 'i32.store16', 1, 0)
  else WasmMemOp($36, 'i32.store', 2, 0);
end;

{ ===== the linear-memory map =====

    0 .. WASM_BSS_BASE-1   null guard.
    WASM_BSS_BASE ..       globals: BSSSize bytes at Syms[].Offset, which for
                           an skGlobal is a positive offset from the start of
                           BSS. Zero-initialised for free — wasm linear memory
                           starts zeroed, so a .bss needs no data segment.
    WasmDataBase ..        the initialised blob: DataLen bytes of Data[],
                           loaded by one active data segment.
    ... WasmStackTop       the shadow stack, growing DOWN from the top.

  WHY BSS COMES FIRST, AND WHY THAT DECIDES WHICH BASE IS A CONSTANT. Both
  region sizes are unknown while bodies are being emitted — BSSSize and DataLen
  are still growing — so whichever region sits second has a base that cannot be
  written as an `i32.const` at the point the reference is emitted. One of the
  two therefore costs an indirection, and it should be the rarer one: every
  global variable is a BSS reference, while a Data[]-resident global is only a
  typed const. So BSS keeps the fixed base and its addressing is unchanged, and
  a data-resident reference goes through the `$data` global — whose initialiser
  is written in the global section at module-write time, when the layout is
  finally known. That is the same late-binding `sp` already uses.

  The alternative was to emit a padded 5-byte LEB placeholder and patch it, the
  way the ELF writers patch code. It is faster and it is worse here: the WAT
  oracle is generated alongside the bytes, and a patched constant is invisible
  in a text stream that was already written. Two instructions on the rare path
  buys an oracle that cannot drift from the binary.

  The null guard is a CONVENTION and nothing more, which is a genuine
  difference from every other target here. Address 0 is a perfectly legal wasm
  address: a load from it returns zero rather than faulting, and linear memory
  has no page protection to give it. So a nil dereference on this target reads
  zeros and keeps going where on x86-64 it segfaults. Reserving the low
  kilobyte does not fix that; it only means a nil-plus-small-field-offset
  deref stays inside the region nothing else uses, so it cannot silently
  corrupt a real global. Making nil actually fault would need an explicit
  compare before every dereference — a real cost, and a Phase 7 decision, not
  something to slip in here. }
const
  WASM_BSS_BASE    = 1024;

{ A HANDLER FRAME — one per `try` in the body, living in the shadow frame below
  the Pascal slots. Three words, and the third is the one the register backends
  do not need:

    +0  prev   the BSS_EXC_TOP this frame displaced
    +4  pad    the BASIC BLOCK the landing pad starts, not a code address —
               there are no code addresses in a wasm module
    +8  fp     the $fp of the invocation that pushed it

  `fp` is what answers "is the innermost handler MINE?" at a raise. A register
  target answers that with a longjmp, which simply lands wherever the setjmp
  buffer says; wasm cannot jump into another frame at all, so the question has
  to be asked explicitly and answered two ways — branch to the pad if the
  handler is ours, set the pending flag and return if it is not. See
  devdocs/dev/wasm/phase5-exceptions.md, "the landing pad is DYNAMIC". }
  WASM_EXCF_PREV   = 0;
  WASM_EXCF_PAD    = 4;
  WASM_EXCF_FP     = 8;
  WASM_EXCF_SIZE   = 12;
  { Eight slots is one string binop's worth: the Char scratch, three parts for
    each operand, and the spilled result. Sixteen levels is far past what a
    parser produces for `a + b + c + ...`, which nests LEFT and reuses one
    level; depth here is what explicit parentheses buy. Exceeding it is
    refused by name, never silently reused. }
  WASM_STR_DEPTH   = 16;
  WASM_STR_SLOTS   = 8;
  WASM_STACK_BYTES = 65536;
  WASM_PAGE        = 65536;

const
  { Program-body chunks. See WasmMainChunk below — 10 for a program with three
    typed const records, so the headroom is not theoretical. }
  MAX_WASM_MAIN_CHUNKS = 4096;

var
  WasmGData   : Integer;   { global index of $data, the blob's base address }
  WasmDataBase: Integer;   { its value — resolved in WasmFinishMemory }

  { THE PROGRAM BODY ARRIVES IN PIECES, and this is the one place a wasm module
    cannot mirror a register target for free.

    A frontend emits top-level code by calling the per-body entry point with
    CurProc = -1, and it does so more than once: every typed const that is
    built by startup code rather than stored in the blob — a record, an array
    of records — emits its stores as another such call. On a register target
    those pieces land in Code[] one after another and ARE one function; there
    is no seam, because a function is a range of bytes. A wasm function is a
    closed structure with its own locals vector and its own `end`, so the same
    sequence produces N functions, all named `main`, none of them called.

    That failed as `duplicate export "main"`, which is a validator complaint
    about the SYMPTOM. The bodies being unreachable is the defect, and it is
    silent: the module validates the moment the names are made unique, and
    every global those chunks were supposed to initialise reads zero.

    So each chunk keeps its own slot and `main` is synthesised at write time as
    a call to each in order. Concatenation and sequential calls are equivalent
    here because a chunk balances its own $sp — it allocates a frame, does its
    work and frees it — so there is nothing to carry across the seam. }
  WasmMainChunk     : array[0..MAX_WASM_MAIN_CHUNKS-1] of Integer;
  WasmMainChunkCount: Integer;

  { A proc's index in the function table, or -1 if its address has never been
    taken. Memoised because BOTH consumers must agree: the IR_PROCADDR arm,
    which emits it as a value, and the MethodFixups loop, which writes it into a
    VMT slot. Two sites deriving the same index separately is the shape that
    produced the IRTk planner/emitter split — one function, asked twice. }
  WasmProcTabIdx    : array[0..MAX_PROCS-1] of Integer;

  { A proc's wasm IMPORT index, or -1 if it is not an external routine this
    module has called. Memoised for the same reason WasmProcTabIdx is: an
    import must be declared exactly once, and two sites deciding independently
    would declare it twice. }
  WasmProcImpIdx    : array[0..MAX_PROCS-1] of Integer;

  { Host imports the BACKEND declares, as opposed to the ones a Pascal
    `external` declaration names. There is exactly one today — WASI's
    proc_exit, because `Halt` is a process-level operation with no wasm
    instruction behind it — and the table exists so the second one cannot be
    declared twice by two call sites. Keyed on the field name, which is unique
    within the one module namespace this backend uses. }
  WasmHostImpName   : array[0..15] of AnsiString;
  WasmHostImpIdx    : array[0..15] of Integer;
  WasmHostImpCount  : Integer;

  { Scratch i32 local for virtual dispatch, allocated on first use per body:
    Self is needed twice (as argument 0 and to load the VMT) and the operand
    stack only yields it once. -1 = not allocated in this body. }
  WasmLocalSelf     : Integer;

procedure WasmBeginModuleOnce;
var i: Integer;
begin
  if WasmModuleStarted then Exit;
  WasmModuleStarted := True;
  WasmReset;
  { One page to start; the module grows it via memory.grow when the heap
    arrived in Phase 6. Exported so a test harness can inspect linear memory. }
  WasmSetMemory(1, -1);
  WasmAddExport('memory', WEK_MEM, 0);
  { The shadow-stack pointer. Exported so a harness can assert it balances —
    the property the Phase 5 prototype leans on. }
  for i := 0 to MAX_PROCS - 1 do
  begin
    WasmProcSlot[i] := -1;
    WasmProcTabIdx[i] := -1;
    WasmProcImpIdx[i] := -1;
  end;
  WasmHostImpCount := 0;
  WasmGSp := WasmAddGlobal('sp', WT_I32, True, 65536);
  WasmAddExport('sp', WEK_GLOBAL, WasmGSp);
  { Immutable, and its initialiser is back-filled by WasmFinishMemory once
    BSSSize has stopped growing. Declared here rather than on first use so its
    global index is stable no matter which body happens to touch Data[] first. }
  WasmDataBase := 0;
  WasmMainChunkCount := 0;
  WasmGData := WasmAddGlobal('data', WT_I32, False, 0);
end;

{ Load the address of a slot onto the operand stack. A global's address is a
  constant; a local's is $fp plus a displacement, and this is the ONE place the
  sign convention is converted — Pascal records a local's Offset as NEGATIVE
  from the frame top (symtab.inc, `Offset := -FrameSize`) and $fp points at the
  frame BOTTOM, so the slot sits at $fp + (FrameSize - N). }
procedure WasmSlotAddr(si: Integer);
begin
  if Syms[si].Kind = skGlobal then
  begin
    { A global whose STORAGE is in the initialised blob rather than in BSS
      carries DATA_SYM_BIAS + dataOffset, so that offset ARITHMETIC downstream
      (`+ 8` for a field, an array element) survives the tag — defs.inc:1682.
      Every backend has to decode it; the ELF writers do it in their fixup
      loops, and this is where wasm does it. Missing it does not produce a
      wrong address so much as an address near 0x20000400, which is past the
      end of linear memory and traps — the good failure mode, but still a
      failure, and it arrives the first time a program declares a typed const
      array. }
    if SymOffIsData(Syms[si].Offset) then
    begin
      WasmGlobalGet(WasmGData);
      WasmI32Const(SymOffDataPart(Syms[si].Offset));
      WasmOp($6A, 'i32.add');
    end
    else
      WasmI32Const(WASM_BSS_BASE + Syms[si].Offset);
  end
  else
  begin
    WasmLocalGet(WasmLocalFp);
    WasmI32Const(WasmCurFrame + Syms[si].Offset);
    WasmOp($6A, 'i32.add');
  end;
end;

function WasmEmitNode(node: Integer): TTypeKind; forward;

{ FORWARDS FOR THE FPC SEED, and they are not optional decoration.

  pxx accepts a call to a routine defined later in the same include; FPC does
  not, and FPC is what BOOTSTRAPS this compiler. So a file that self-hosts
  perfectly can still break the seed build, and nothing in the per-fix loop
  looks: `make compiler/pascal26` compiles with pxx. This file broke the seed
  the day direct calls landed and stayed broken for several commits, until
  `gate.sh quick`'s FPC canary was run — which is the argument for running that
  gate once at the end of a phase rather than never.

  Every routine WasmEmitNode and WasmEmitStmt dispatch to belongs here, because
  the dispatchers sit above the emitters and always will.
  See bug-a-fpc-seed-drift-emitasmx64-forward. }
procedure WasmEmitCall(node: Integer; isStmt: Boolean); forward;
procedure WasmEmitProcAddr(node: Integer); forward;
procedure WasmEmitCallInd(node: Integer; isStmt: Boolean); forward;
procedure WasmEmitVirtualCall(node: Integer; isStmt: Boolean); forward;
{ Not a dispatch target — WasmEmitGetMem calls it to marshal a constructor's
  arguments, and GetMem is lowered as a BUILTIN, which puts its call site above
  the indirect-call machinery it shares. Caught by the FPC canary, twice now
  the same way: the file self-hosts perfectly with the call unresolved. }
function WasmEmitIndArgs(sigProc, firstArg, startIdx: Integer;
                         const what: AnsiString): Boolean; forward;
{ Caught by tools/forwardlint.py the second it was written, which is the third
  time this file has needed one and the first time it cost nothing. }
procedure WasmEmitConstStr(node: Integer); forward;
procedure WasmEmitFrozenStore(dstIsSym: Boolean;
                              dstRef, valNode, cap: Integer); forward;
{ The post-call exception check and the spill that must precede it. Forward
  because every call emitter needs them and the call emitters sit above the
  block machinery they branch through. }
procedure WasmEmitExcCheck; forward;
procedure WasmEmitPostCall(spillVt: Byte; hasResult: Boolean); forward;
procedure WasmEmitManagedStore(dstIsSym: Boolean;
                               dstRef, valNode: Integer); forward;
function WasmEmitStrBinop(node: Integer; op: TTokenKind): Boolean; forward;
function WasmStrParts(node, scrLoc, scratchOfs: Integer;
                      valLoc, lenLoc, srcLoc: Integer): Boolean; forward;
procedure WasmEmitAtomic(node: Integer); forward;
function WasmStrSlot(k: Integer): Integer; forward;
function WasmCallRtl(const nm: AnsiString): Boolean; forward;
procedure WasmEmitDynStore(dstSym, valNode: Integer); forward;

{ The address at which the PASCAL VARIABLE `si` lives, which is not always the
  address of its slot. A var/out parameter's slot holds the CALLER's address,
  so the variable is at [slot] and the extra load is the whole difference
  between writing through the reference and overwriting the reference.

  Every read, write and address-of goes through here, and that is the point:
  the first cut put this deref in the address-of path alone, so `o := o + n` on
  a var parameter read the address as if it were the value, added to it, and
  stored the sum over the reference. Both are i32, so the module validated and
  ran; the differential caught it, and nothing else could have. One concept
  reachable through three shapes is exactly the case
  devdocs/dev/normalise-dont-special-case.md says to normalise, and the arm
  left out is reliably the one that stays broken.

  Parameter HOMING is the deliberate exception and uses WasmSlotAddr directly:
  it writes the incoming reference INTO the slot, which is the one operation
  that means the slot itself. }
procedure WasmLValueAddr(si: Integer);
begin
  WasmSlotAddr(si);
  { THE ORACLE, not a flag test. abi.inc calls this exact question SLOT-HOLDS
    and names `(Syms[...].Kind = skParam) and Syms[...].IsRef` — which is what
    stood here — as the copy it exists to remove. It is not a stylistic
    difference: the set also contains open arrays, variants, and frozen-string
    VALUE parameters, so the hand-written version read a `const s: ShortString`
    parameter's buffer contents as if they were the buffer's address. }
  if ABIParamSlotHoldsValueAddr(si) then
    WasmMemOp($28, 'i32.load', 2, 0);
end;

{ Classify a frame slot, recording the body as unlowered if its type has no
  wasm value type at all (a record, a set, a variant). }
function WasmSlotType(si: Integer; var vt: Byte): Boolean;
begin
  WasmSlotType := WasmScalarType(Syms[si].TypeKind, vt);
  if not WasmSlotType then
    WasmUnsupported('slot ' + Syms[si].Name + ' has no wasm value type');
end;

procedure WasmEmitLoadSym(si: Integer);
var vt: Byte;
begin
  { Reading a frozen string yields its ADDRESS — see WasmEmitValueAs. There is
    no load: the variable IS the buffer. }
  if TypeIsFrozenString(Syms[si].TypeKind) then
  begin
    WasmLValueAddr(si);
    Exit;
  end;
  if not WasmSlotType(si, vt) then
  begin
    { Reported, not skipped. This used to Exit silently, which pushed NOTHING
      where the consumer expects a value: the module then fails validation with
      a stack-underflow at some later instruction, and the diagnostic names a
      line that is fine. }
    WasmUnsupported('read of ' + WasmSymLabel(si) + ', of type '
                    + WasmTypeKindName(Syms[si].TypeKind));
    Exit;
  end;
  WasmLValueAddr(si);
  WasmTypeLoad(Syms[si].TypeKind, vt);
end;

{ ===== width conversion =====

  The IR does NOT insert width conversions. On a register target it does not
  need to: an Integer added to an Int64 is already sitting in the low half of a
  64-bit register, and the backend picks a sub-register or a full one and the
  question never comes up. wasm has no sub-registers and its validator rejects
  `i64.add` with an i32 on the stack, byte offset and all — which is how this
  was found at all, rather than by a wrong answer in a test that happened to
  mix widths.

  So materialising a value at the width its consumer needs is THIS backend's
  job, and the line between a conversion it may insert on its own and one the
  IR must ask for is drawn at whether the conversion is mechanical or
  semantic:

    int -> int, either direction   INSERTED. Exactly what a register backend
                                   does when it picks eax over rax; Pascal
                                   defines the truncation, and it is the same
                                   truncation.
    int -> float                   INSERTED. Value-preserving and unambiguous.
    f32 <-> f64                    INSERTED. Mechanical, the same widening and
                                   rounding cvtss2sd/cvtsd2ss perform.
    float -> int                   REFUSED. Round, truncate, or raise is a
                                   LANGUAGE choice — Trunc and Round are
                                   different functions — and wasm's own
                                   i32.trunc_f64_s traps out of range. A
                                   backend that picked one would be answering a
                                   question the IR is supposed to ask. }

procedure WasmCoerce(fromTk: TTypeKind; from, want: Byte; const ctx: AnsiString);
var sgn: Boolean;
begin
  if from = want then Exit;
  sgn := TypeSigned(fromTk);
  if ((from = WT_F32) or (from = WT_F64))
     and ((want = WT_I32) or (want = WT_I64)) then
  begin
    WasmUnsupported('float-to-integer conversion in ' + ctx
                    + ' (the IR must say Trunc or Round)');
    Exit;
  end;
  if want = WT_I64 then
  begin
    if sgn then WasmOp($AC, 'i64.extend_i32_s')
    else WasmOp($AD, 'i64.extend_i32_u');
  end
  else if want = WT_I32 then
    WasmOp($A7, 'i32.wrap_i64')
  else if want = WT_F64 then
  begin
    if from = WT_F32 then WasmOp($BB, 'f64.promote_f32')
    else if from = WT_I32 then
    begin
      if sgn then WasmOp($B7, 'f64.convert_i32_s')
      else WasmOp($B8, 'f64.convert_i32_u');
    end
    else
    begin
      if sgn then WasmOp($B9, 'f64.convert_i64_s')
      else WasmOp($BA, 'f64.convert_i64_u');
    end;
  end
  else
  begin
    if from = WT_F64 then WasmOp($B6, 'f32.demote_f64')
    else if from = WT_I32 then
    begin
      if sgn then WasmOp($B2, 'f32.convert_i32_s')
      else WasmOp($B3, 'f32.convert_i32_u');
    end
    else
    begin
      if sgn then WasmOp($B4, 'f32.convert_i64_s')
      else WasmOp($B5, 'f32.convert_i64_u');
    end;
  end;
end;

{ Emit a value and leave it on the stack at exactly `want`. Every consumer of a
  value goes through here, so there is one place a width can be wrong. }
procedure WasmEmitValueAs(node: Integer; want: Byte; const ctx: AnsiString);
var got: TTypeKind; gvt: Byte;
begin
  got := WasmEmitNode(node);
  if WasmBodyBroken then Exit;
  { A frozen string is NOT a scalar and yet it is already an i32: every node
    whose type is one evaluates to the ADDRESS of its [len][chars] buffer, and
    that is the IR's own convention rather than this backend's invention — the
    x86-64 arm for a string-valued expression is a bare IREmitNode and a
    comment saying the address is in rax (ir_codegen.inc:6765).

    Stating it HERE rather than at each consumer is deliberate. The two callers
    that need it today are the write path and the frozen store, and the ones
    that need it tomorrow (a string argument, a string comparison) would each
    have grown their own arm — which is the second path that stays broken.
    Only WT_I32 is accepted: a frozen string asked for as an i64 or an f64 is a
    real type error and still refused. }
  if TypeIsFrozenString(got) and (want = WT_I32) then Exit;
  if not WasmScalarType(got, gvt) then
  begin
    WasmUnsupported('value of type ' + WasmTypeKindName(got) + ' in ' + ctx);
    Exit;
  end;
  WasmCoerce(got, gvt, want, ctx);
end;

{ The type two operands meet in. A Single meeting an integer widens to f64
  rather than f32: an Int64 does not fit a Single, and Pascal's own promotion
  goes to the wider real. Two Singles stay f32. }
function WasmUnify(a, b: Byte): Byte;
begin
  if (a = WT_F64) or (b = WT_F64) then WasmUnify := WT_F64
  else if (a = WT_F32) and (b = WT_F32) then WasmUnify := WT_F32
  else if (a = WT_F32) or (b = WT_F32) then WasmUnify := WT_F64
  else if (a = WT_I64) or (b = WT_I64) then WasmUnify := WT_I64
  else WasmUnify := WT_I32;
end;

{ ===== binary operators =====

  Every opcode below is written out rather than derived. The wasm opcode table
  is in fact regular — the i64 form of an integer instruction sits a fixed
  distance from its i32 form — and using that regularity would halve this code,
  but a wrong byte in a backend is not caught by review, by the type system, or
  by any test that does not happen to exercise that one operator on that one
  width. Written out, each byte can be checked against the spec table by eye.

  The OPERAND type picks the instruction, not the node's own type: a comparison
  node is Boolean while what it compares may be two Int64s. Signedness comes
  from the operand type too, because wasm splits div, rem and every ordering
  comparison into signed and unsigned instructions where a register target
  picks an addressing mode or a flag.

  `shr` is the exception, and it is a LANGUAGE fact rather than a wasm one:
  Pascal's `shr` is a LOGICAL shift whatever the operand's signedness — FPC
  gives 2147483644 for `(-8) shr 1` on an Integer, not -4 — so it lowers to
  shr_u unconditionally and shr_s is never emitted. Pascal has no arithmetic
  right-shift operator to emit it for. }

procedure WasmIntBinop(op: TTokenKind; wide, sgn: Boolean; const what: AnsiString);
begin
  if wide then
  begin
    if op = tkPlus then WasmOp($7C, 'i64.add')
    else if op = tkMinus then WasmOp($7D, 'i64.sub')
    else if op = tkStar then WasmOp($7E, 'i64.mul')
    else if (op = tkDiv) and sgn then WasmOp($7F, 'i64.div_s')
    else if op = tkDiv then WasmOp($80, 'i64.div_u')
    else if (op = tkMod) and sgn then WasmOp($81, 'i64.rem_s')
    else if op = tkMod then WasmOp($82, 'i64.rem_u')
    else if op = tkAnd then WasmOp($83, 'i64.and')
    else if op = tkOr then WasmOp($84, 'i64.or')
    else if op = tkXor then WasmOp($85, 'i64.xor')
    else if op = tkShl then WasmOp($86, 'i64.shl')
    else if op = tkShr then WasmOp($88, 'i64.shr_u')
    else if op = tkEq then WasmOp($51, 'i64.eq')
    else if op = tkNeq then WasmOp($52, 'i64.ne')
    else if (op = tkLt) and sgn then WasmOp($53, 'i64.lt_s')
    else if op = tkLt then WasmOp($54, 'i64.lt_u')
    else if (op = tkGt) and sgn then WasmOp($55, 'i64.gt_s')
    else if op = tkGt then WasmOp($56, 'i64.gt_u')
    else if (op = tkLe) and sgn then WasmOp($57, 'i64.le_s')
    else if op = tkLe then WasmOp($58, 'i64.le_u')
    else if (op = tkGe) and sgn then WasmOp($59, 'i64.ge_s')
    else if op = tkGe then WasmOp($5A, 'i64.ge_u')
    else WasmUnsupported(what);
  end
  else
  begin
    if op = tkPlus then WasmOp($6A, 'i32.add')
    else if op = tkMinus then WasmOp($6B, 'i32.sub')
    else if op = tkStar then WasmOp($6C, 'i32.mul')
    else if (op = tkDiv) and sgn then WasmOp($6D, 'i32.div_s')
    else if op = tkDiv then WasmOp($6E, 'i32.div_u')
    else if (op = tkMod) and sgn then WasmOp($6F, 'i32.rem_s')
    else if op = tkMod then WasmOp($70, 'i32.rem_u')
    else if op = tkAnd then WasmOp($71, 'i32.and')
    else if op = tkOr then WasmOp($72, 'i32.or')
    else if op = tkXor then WasmOp($73, 'i32.xor')
    else if op = tkShl then WasmOp($74, 'i32.shl')
    else if op = tkShr then WasmOp($76, 'i32.shr_u')
    else if op = tkEq then WasmOp($46, 'i32.eq')
    else if op = tkNeq then WasmOp($47, 'i32.ne')
    else if (op = tkLt) and sgn then WasmOp($48, 'i32.lt_s')
    else if op = tkLt then WasmOp($49, 'i32.lt_u')
    else if (op = tkGt) and sgn then WasmOp($4A, 'i32.gt_s')
    else if op = tkGt then WasmOp($4B, 'i32.gt_u')
    else if (op = tkLe) and sgn then WasmOp($4C, 'i32.le_s')
    else if op = tkLe then WasmOp($4D, 'i32.le_u')
    else if (op = tkGe) and sgn then WasmOp($4E, 'i32.ge_s')
    else if op = tkGe then WasmOp($4F, 'i32.ge_u')
    else WasmUnsupported(what);
  end;
end;

procedure WasmFloatBinop(op: TTokenKind; wide: Boolean; const what: AnsiString);
begin
  if wide then
  begin
    if op = tkPlus then WasmOp($A0, 'f64.add')
    else if op = tkMinus then WasmOp($A1, 'f64.sub')
    else if op = tkStar then WasmOp($A2, 'f64.mul')
    else if op = tkSlash then WasmOp($A3, 'f64.div')
    else if op = tkEq then WasmOp($61, 'f64.eq')
    else if op = tkNeq then WasmOp($62, 'f64.ne')
    else if op = tkLt then WasmOp($63, 'f64.lt')
    else if op = tkGt then WasmOp($64, 'f64.gt')
    else if op = tkLe then WasmOp($65, 'f64.le')
    else if op = tkGe then WasmOp($66, 'f64.ge')
    else WasmUnsupported(what);
  end
  else
  begin
    if op = tkPlus then WasmOp($92, 'f32.add')
    else if op = tkMinus then WasmOp($93, 'f32.sub')
    else if op = tkStar then WasmOp($94, 'f32.mul')
    else if op = tkSlash then WasmOp($95, 'f32.div')
    else if op = tkEq then WasmOp($5B, 'f32.eq')
    else if op = tkNeq then WasmOp($5C, 'f32.ne')
    else if op = tkLt then WasmOp($5D, 'f32.lt')
    else if op = tkGt then WasmOp($5E, 'f32.gt')
    else if op = tkLe then WasmOp($5F, 'f32.le')
    else if op = tkGe then WasmOp($60, 'f32.ge')
    else WasmUnsupported(what);
  end;
end;

{ ===== memory operands =====

  IR_LEA takes a SYMBOL and yields its address; IR_LOAD_MEM and IR_STORE_MEM
  take an address VALUE and carry the accessed type in IRTk[node]. That is the
  same contract the register backends read (ir_codegen_riscv32.inc:1534, :1669,
  :1710), and the load/store side maps onto WasmTypeLoad/WasmTypeStore exactly,
  narrow ordinals included.

  What is deliberately NOT handled: the slot shapes where an address is not
  `&slot`. A dynamic array's or an open-array parameter's slot holds a heap
  handle; a managed string's slot holds a handle in read position but its own
  address in write position; a frozen string store through an address is a
  length-clamped copy, not a store. Each is a real case with real rules, and
  each is refused by name here rather than approximated — an approximated
  address is a wrong pointer, which is the one failure this backend is built
  not to produce quietly. They arrive with the managed types, not with Phase 2
  scalars. }

procedure WasmEmitLea(node: Integer);
var si: Integer;
begin
  si := IRA[node];
  { A STATIC array's address is just its slot address — the elements are in the
    frame or in BSS. The shapes refused here are the ones whose slot holds a
    HEAP HANDLE rather than the data: a dynamic array (ArrLen = -1) and an
    open-array value parameter, where the caller passed the handle. Loading the
    handle is one more instruction and is not the hard part. Refusing every
    array — which is what this did first — also refused `a[i]` on a plain
    `array[0..9] of Integer`, where nothing is on the heap at all.

    THE REASON HERE WAS STALE UNTIL 2026-08-28. It said "needs the heap, Phase
    6" and Phase 6 shipped the heap; the refusal stayed correct and its stated
    cause stopped being true, which is the most durable kind of wrong, because
    nothing ever fails to make anyone check it. What is actually missing is the
    dynamic-array LAYOUT — the descriptor, its refcount and length, the
    element-address arithmetic, SetLength and the copy-on-write unique — none
    of which the heap provides. Measured the day the reason was corrected:
    compiling `compiler.pas` for wasm32 refuses 1591 of 3647 bodies, and 83% of
    the refusal lines are this one feature and its immediate family (dynamic
    arrays, SetLength on one, open-array parameters, Length of a non-string).
    It is not a list of gaps; it is one gap. }
  { A DYNAMIC ARRAY's slot holds a handle; IR_LEA on one yields the DATA
    pointer, in read and write position alike. That is not the string rule one
    line down, and the difference is the language's, not this backend's: a
    dynamic array is a reference type at every depth, so `b := a` aliases and
    there is no copy-on-write to decide between positions. The four register
    backends all deref unconditionally here and say so
    (ir_codegen_riscv32.inc's IR_DYNUNIQUE: "one deref, in read AND write mode
    alike").

    The consequence is that SetLength cannot go through IR_LEA — it needs the
    SLOT, and this hands it the contents. Its arm bypasses this by asking
    WasmLValueAddr directly, exactly as riscv32 does, and for the same reason
    riscv32 wrote a ticket about: handing PXXDynSetLen the current handle
    reads as `arrSlot = nil` on a fresh array, so SetLength silently does
    nothing and the first index segfaults. }
  if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
  begin
    WasmLValueAddr(si);
    WasmMemOp($28, 'i32.load', 2, 0);   { slot -> data pointer }
    Exit;
  end;
  if (Syms[si].Kind = skParam) and Syms[si].IsArray and not Syms[si].IsRef then
  begin
    WasmUnsupported('open-array parameter ' + Syms[si].Name
                    + ' — the slot holds a dynamic-array handle, whose layout'
                    + ' is not implemented on this target');
    Exit;
  end;
  if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray then
  begin
    { A scalar managed string. IR_LEA on one is POSITION-DEPENDENT: read
      position yields the HANDLE, write position yields the SLOT's address so
      a store can publish a new handle into it (ir_codegen_aarch64.inc:1351).

      Until slice 3 this arm answered HANDLE unconditionally, and the argument
      for that was not that reads are the only position — it was that every
      write-position consumer refused somewhere ELSE, so no write could reach
      here. That argument was written down rather than trusted precisely
      because it is an argument from what currently refuses, and slice 3 is
      what invalidated it: `s[i] := c` and `SetLength(s, n)` are exactly the
      two shapes it named, and both now lower.

      So the argument is REPLACED, not extended. The position is modelled, and
      it is modelled with the SAME mechanism the other four backends use —
      the global InLValueWrite, set by whoever walks a destination and
      restored after. Not a private wasm flag: defs.inc states the IR contract
      for IR_LEA, IR_INDEX and IR_DYNUNIQUE in terms of that global
      (defs.inc:747), so a second flag would be a second, undocumented
      contract. It is safe as a global because no backend ever leaves it set —
      every site saves and restores, and it is False between statements.

      The set sites on this target are the three destination walks:
      WasmEmitStoreMem's address, WasmEmitManagedStore's address, and
      WasmEmitFrozenStore's address; plus IR_SETLEN_STR's slot node. The reset
      site is WasmEmitIndex's INDEX sub-expression, which is a READ even when
      the whole IR_INDEX is a write target (`b[Length(b)] := c`). }
    WasmLValueAddr(si);
    if not InLValueWrite then
      WasmMemOp($28, 'i32.load', 2, 0);
    Exit;
  end;
  WasmLValueAddr(si);
end;

{ `a[i]` — base + (i - low) * elemSize, with the low bound in IRC and the
  element stride in IRIVal, both already resolved by the frontend. Same
  contract riscv32 reads (ir_codegen_riscv32.inc:1580); the arithmetic is
  identical and only the spilling is gone, because the base can simply sit on
  the operand stack while the index is computed.

  Indexing a managed string is the one shape where the base is not already an
  address. It is POSITION-DEPENDENT and the two positions call for different
  code, which is why it waited for a position model rather than an extra case:

    read   the base is the HANDLE, which IS the char pointer. `s[i]` is
           handle + (i - lo), no call.
    write  the base is the SLOT's address, and the string may be SHARED —
           `t := s; s[1] := 'z'` must not edit t. PXXStrUnique(slotAddr)
           clones when the refcount says so and publishes the clone back into
           the slot, returning a handle the caller may write through.

  Getting the write case wrong does not fail loudly: it stores the character
  INTO the handle slot, so the string reads back with length 0 and a malformed
  handle that segfaults at scope exit. riscv32 and arm32 both shipped that and
  fixed it twice — once for the scalar shape, once for a managed string that is
  itself a field or an array element, where the base is a slot address in BOTH
  positions and the read case needs its own load
  (bug-a-riscv32-setlength-on-string-array-element-loses-length). Both shapes
  are handled here from the start, and strop/managed cover both. }
procedure WasmEmitIndex(node: Integer);
var left, lo, elemSize: Integer; isStr, savedLVW: Boolean;
begin
  left := IRA[node];
  lo := IRC[node];
  elemSize := Integer(IRIVal[node]);
  isStr := ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString)
            and not Syms[IRA[left]].IsArray)
           or (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX))
               and (IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1));
  savedLVW := InLValueWrite;
  WasmEmitValueAs(left, WT_I32, 'array base');
  if WasmBodyBroken then Exit;
  if isStr then
  begin
    if savedLVW then
    begin
      { The base is the slot address in write position for BOTH shapes: IR_LEA
        answers slot-address under the flag, and a FIELD/INDEX base is a slot
        address to begin with. }
      if not WasmCallRtl('PXXStrUnique') then Exit;
    end
    else if (IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX) then
      WasmMemOp($28, 'i32.load', 2, 0);   { slot -> handle }
  end;
  { The INDEX is a READ even when the whole IR_INDEX is a write target:
    `b[Length(b)] := c` otherwise emits Length against the SLOT address rather
    than the handle and stores at a wild offset. Same reset every register
    backend does (ir_codegen_riscv32.inc:1633). }
  InLValueWrite := False;
  WasmEmitValueAs(IRB[node], WT_I32, 'array index');
  InLValueWrite := savedLVW;
  if WasmBodyBroken then Exit;
  if lo <> 0 then
  begin
    WasmI32Const(lo);
    WasmOp($6B, 'i32.sub');
  end;
  if elemSize <> 1 then
  begin
    WasmI32Const(elemSize);
    WasmOp($6C, 'i32.mul');
  end;
  WasmOp($6A, 'i32.add');
end;

{ A field's address: the base address plus a constant byte offset. IRIVal
  carries the offset, which the record layout has already resolved, so there is
  no record-shape knowledge in this backend at all — it is address arithmetic
  that happens to be spelled with a dot. }
procedure WasmEmitField(node: Integer);
begin
  WasmEmitValueAs(IRA[node], WT_I32, 'record base address');
  if WasmBodyBroken then Exit;
  if Integer(IRIVal[node]) <> 0 then
  begin
    WasmI32Const(Integer(IRIVal[node]));
    WasmOp($6A, 'i32.add');
  end;
end;

procedure WasmEmitLoadMem(node: Integer);
var tk: TTypeKind; vt: Byte;
begin
  tk := IntToTypeKind(IRTk[node]);
  if TypeIsFrozenString(tk) then
  begin
    { A frozen string through an address — a string[N] record field. Its value
      is the address, so the address computation IS the whole load. }
    WasmEmitValueAs(IRA[node], WT_I32, 'address of a frozen string');
    Exit;
  end;
  if not WasmScalarType(tk, vt) then
  begin
    WasmUnsupported('load through a pointer of type '
                    + WasmTypeKindName(tk));
    Exit;
  end;
  WasmEmitValueAs(IRA[node], WT_I32, 'address of a load');
  if WasmBodyBroken then Exit;
  WasmTypeLoad(tk, vt);
end;

procedure WasmEmitStoreMem(node: Integer);
var tk: TTypeKind; vt: Byte; savedLVW: Boolean;
begin
  tk := IntToTypeKind(IRTk[node]);
  if TypeIsFrozenString(tk) then
  begin
    { A frozen string through an ADDRESS — a string[N] record field, or `p^`.
      Capacity comes from the IR node here rather than from a symbol, because
      there is no symbol: the destination is an expression. }
    WasmEmitFrozenStore(False, IRA[node], IRB[node], Integer(IRIVal[node]));
    Exit;
  end;
  if tk = tyAnsiString then
  begin
    { A managed string through an ADDRESS — a record field, an array element.
      Same three steps as through a symbol; only how the slot is reached
      differs. }
    WasmEmitManagedStore(False, IRA[node], IRB[node]);
    Exit;
  end;
  if not WasmScalarType(tk, vt) then
  begin
    WasmUnsupported('store through a pointer of type '
                    + WasmTypeKindName(tk));
    Exit;
  end;
  { ADDRESS FIRST, then the value — wasm's i32.store pops them in that order.
    The register backends evaluate the VALUE first and spill it
    (ir_codegen_riscv32.inc:1710), so the two orders differ. Unobservable
    today, because nothing in Phase 2 can have a side effect: there are no
    calls yet. It becomes observable the moment Phase 4 lands and `p^ := f()`
    can be written, and at that point this needs a scratch local to evaluate
    the value first and keep the register backends' order — not a reshuffle of
    these two lines, which wasm's stack discipline will not allow. }
  savedLVW := InLValueWrite;
  InLValueWrite := True;
  WasmEmitValueAs(IRA[node], WT_I32, 'address of a store');
  InLValueWrite := savedLVW;
  WasmEmitValueAs(IRB[node], vt, 'value of a store');
  if WasmBodyBroken then Exit;
  WasmTypeStore(tk, vt);
end;

{ ===== what a node produces =====

  ONE pure function answers "what type does this node leave on the stack", and
  it is what the emitters return. That is not tidiness — it is the second half
  of the rule stated at WasmEmitNode, and it was learned the same way twice.

  `IRTk[node]` is the IR's own record of a node's type and it is NOT reliably
  populated: a for-loop's bound comparison arrives with an IR_LOAD_SYM whose
  IRTk is tyUnknown while the symbol it loads is plainly an Integer. Register
  backends never notice, because they read a register width rather than a type.
  Reading IRTk here refused every `for` loop in the compiler with "operand type
  in binary operator 67", which is a true statement about IRTk and a false one
  about the program.

  So the answer is taken from the thing that actually determines the value —
  the SYMBOL for a load, the unified operand width for a binop — and IRTk is
  the fallback for nodes whose type is nothing but what the IR recorded. }

function WasmNodeResultType(node: Integer): TTypeKind; forward;

function WasmIsCompare(op: TTokenKind): Boolean;
begin
  WasmIsCompare := (op = tkEq) or (op = tkNeq) or (op = tkLt)
                   or (op = tkLe) or (op = tkGt) or (op = tkGe);
end;

{ Pascal spells `shr` as an IDENTIFIER — the lexer never produces tkShr for it,
  so an IR_BINOP carrying `shr` carries Ord(tkIdent) as its operator
  (compiler/ir.inc:8867 says so in as many words, and ir.inc:8878 performs
  exactly this substitution for the one consumer that predates this backend).
  Doing it again here is the second arm of a double case, which is the shape
  devdocs/dev/normalise-dont-special-case.md says to fix at the source rather
  than duplicate — filed as bug-a-shr-reaches-the-ir-spelled-as-tkident. Until
  that lands, a backend that did NOT translate would not merely miss `shr`, it
  would mistake every `shr` for whatever it does with tkIdent. }
function WasmBinopOp(node: Integer): TTokenKind;
var op: TTokenKind;
begin
  op := TTokenKind(IRC[node]);
  if op = tkIdent then op := tkShr;
  WasmBinopOp := op;
end;

{ WHERE this predicate is asked, and why it is not inside a failure arm. What
  it should ANSWER is the note below — this one is about placement.

  One predicate, because two consumers need the same answer and disagreeing is
  how the wrong instruction gets emitted: WasmEmitBinop refuses on it, and
  WasmBinopWidth declines to unify a width on it so WasmNodeResultType falls
  through to the IR's own record
  (tyAnsiString for a concat) rather than reporting the ARITHMETIC width of two
  handles.

  It is asked BEFORE the width oracle, never inside its failure arm. Both
  string kinds are pointer-shaped, so every operator on them has an integer
  instruction that would compile and run — `a = b` is an i32.eq of two
  ADDRESSES, answering "the same buffer" where Pascal asked "the same
  characters" — and the oracle only refuses when it cannot agree on a width.
  `s + 'x'` is a handle and a Char, pointer-sized and ordinal, so it agreed on
  i32 and the guard that lived in the failure arm was never reached:
  `writeln(t + 'x')` lowered to `handle + 120` and passed it to PXXWriteStrMW.
  A refusal that depends on a different check happening to fail is not a
  refusal. }
{ Is this binop a STRING operation — one that has to go through the RTL rather
  than through an instruction?

  The two cases key on different things and that is the whole content of this
  predicate:

    COMPARISON  keys on the OPERANDS. `a = b` yields a Boolean whatever a and
                b are, so the result type says nothing; what makes it a string
                compare is that the things being compared are strings.
    `+`         keys on the RESULT. An operand being a string is NOT enough,
                because a frozen string's VALUE is its address — so
                `frozenString + 8` is ordinary pointer arithmetic, which is
                exactly how `PChar('literal')` lowers (measured: operands
                `String (frozen)` and `Integer`, result `Pointer`). The first
                version of this predicate asked only about operands and
                therefore refused that as "concatenation producing Pointer",
                which is a true statement about one operand and a false one
                about the operation. It made every program passing a string
                literal to a PChar parameter fail — which is most of the PAL.

  Every other operator is not a string operation. There is no string `-`, `*`
  or `and`, and claiming one would route an arithmetic node into
  WasmEmitStrBinop, which refuses by name rather than mis-lowering — a loud
  failure, but a failure on correct code.

  This is the same defect as the guard slice 2 fixed, in the opposite
  direction. There, a string operation was not recognised because an unrelated
  check happened to succeed first; here, a non-string operation IS recognised
  because a related check happens to be true of one operand. Both come from
  asking a question about the pieces instead of about the operation. }
function WasmBinopIsString(node: Integer): Boolean;
var op: TTokenKind; rtk: TTypeKind;
begin
  op := WasmBinopOp(node);
  rtk := IntToTypeKind(IRTk[node]);
  if WasmIsCompare(op) then
    WasmBinopIsString :=
      TypeIsFrozenString(WasmNodeResultType(IRA[node]))
      or TypeIsFrozenString(WasmNodeResultType(IRB[node]))
      or (WasmNodeResultType(IRA[node]) = tyAnsiString)
      or (WasmNodeResultType(IRB[node]) = tyAnsiString)
  else if op = tkPlus then
    WasmBinopIsString := (rtk = tyAnsiString) or TypeIsFrozenString(rtk)
  else
    WasmBinopIsString := False;
end;

{ Pure: the single width both operands are brought to, and its signedness.
  Shared by the planner and the type oracle so the two cannot disagree about
  what a binop yields. }
function WasmBinopWidth(node: Integer; var want: Byte; var sgn: Boolean): Boolean;
var tkA, tkB: TTypeKind; vtA, vtB, vtN: Byte;
begin
  WasmBinopWidth := False;
  if WasmBinopIsString(node) then Exit;
  tkA := WasmNodeResultType(IRA[node]);
  tkB := WasmNodeResultType(IRB[node]);
  { A FROZEN string is not a scalar type, but its VALUE in an expression is its
    ADDRESS — that is what WasmEmitValueAs already produces for one, and what
    makes `PChar('lit')` lower as `bufferAddress + 8`. So it unifies as an i32
    here rather than declining the whole binop. Only the arithmetic reaches
    this point: a string CONCAT or COMPARE was taken by WasmBinopIsString
    above, so the remaining uses of a frozen operand are pointer arithmetic. }
  if TypeIsFrozenString(tkA) then vtA := WT_I32
  else if not WasmScalarType(tkA, vtA) then Exit;
  if TypeIsFrozenString(tkB) then vtB := WT_I32
  else if not WasmScalarType(tkB, vtB) then Exit;
  { The node's own recorded type joins the unification when it HAS one. It can
    only widen the result (WasmUnify never narrows), and it is there to stop a
    plan that would truncate a value the IR expects whole. When it is unset —
    which happens — dropping it is right: the operands alone already say what
    the arithmetic is. }
  if not WasmScalarType(IntToTypeKind(IRTk[node]), vtN) then vtN := vtA;
  want := WasmUnify(WasmUnify(vtA, vtB), vtN);
  sgn := TypeSigned(tkA) or TypeSigned(tkB);
  WasmBinopWidth := True;
end;

{ A representative Pascal type for a wasm value type. Only its WIDTH and SIGN
  are ever read back — this is how a computed value carries enough of itself to
  be coerced again by whatever consumes it. }
function WasmRepType(vt: Byte; sgn: Boolean): TTypeKind;
begin
  if vt = WT_F32 then WasmRepType := tySingle
  else if vt = WT_F64 then WasmRepType := tyDouble
  else if vt = WT_I64 then
  begin
    if sgn then WasmRepType := tyInt64 else WasmRepType := tyUInt64;
  end
  else
  begin
    if sgn then WasmRepType := tyInt32 else WasmRepType := tyUInt32;
  end;
end;

{ A builtin IR_CALL's result type, for the oracle. Same rule as everywhere
  else: it is what the emitter PRODUCES, so a cast answers its cast type and
  Trunc/Round answers Int64 — never IRTk, which for these nodes records the
  frontend's intent rather than the emitted width. }
function WasmBuiltinResultType(node: Integer): TTypeKind; forward;

{ The oracle's body, now that WasmRepType exists. Every emitter's declared
  result is this function, so an emitter cannot report a type it did not
  produce. }
function WasmNodeResultType(node: Integer): TTypeKind;
var want: Byte; sgn: Boolean;
begin
  WasmNodeResultType := tyInt32;
  if node < 0 then Exit;
  case IRKind[node] of
    { A load's type is the SYMBOL's — the one place it is certainly right. }
    IR_LOAD_SYM      : WasmNodeResultType := Syms[IRA[node]].TypeKind;
    IR_LEA, IR_FIELD,
    IR_INDEX         : WasmNodeResultType := tyPointer;
    { A call's type is the CALLEE's declared result, which is the same place
      the signature came from. IRTk would usually agree and has no reason to be
      the authority. }
    IR_CALL          : if (IRA[node] >= 0) and (IRA[node] < MAX_PROCS) then
                         WasmNodeResultType := Procs[IRA[node]].RetType
                       else
                         WasmNodeResultType := WasmBuiltinResultType(node);
    { Same rule for the indirect forms — the type comes from the SIGNATURE, and
      the signature is where the call's shape came from. They differ only in
      which field holds the proc: IRIVal for an indirect call, IRC for a
      virtual one. A table index is a pointer-sized value, nothing more. }
    IR_CALL_IND      : if (Integer(IRIVal[node]) >= 0)
                          and (Integer(IRIVal[node]) < MAX_PROCS) then
                         WasmNodeResultType := Procs[Integer(IRIVal[node])].RetType
                       else
                         WasmNodeResultType := IntToTypeKind(IRTk[node]);
    IR_VIRTUAL_CALL  : if (IRC[node] >= 0) and (IRC[node] < MAX_PROCS) then
                         WasmNodeResultType := Procs[IRC[node]].RetType
                       else
                         WasmNodeResultType := IntToTypeKind(IRTk[node]);
    IR_PROCADDR      : WasmNodeResultType := tyPointer;
    IR_BINOP :
      if WasmIsCompare(WasmBinopOp(node)) then
        WasmNodeResultType := tyBoolean
      else if WasmBinopWidth(node, want, sgn) then
        WasmNodeResultType := WasmRepType(want, sgn)
      else
        WasmNodeResultType := IntToTypeKind(IRTk[node]);
  else
    { Constants, loads through a pointer, unaries: the IR's record is all there
      is, and for these it is populated. }
    WasmNodeResultType := IntToTypeKind(IRTk[node]);
  end;
end;

procedure WasmEmitBinop(node: Integer);
var
  op: TTokenKind;
  want: Byte;
  sgn: Boolean;
  what: AnsiString;
begin
  op := WasmBinopOp(node);
  what := 'binary operator ' + WasmBinopName(op);

  { STRINGS FIRST — see WasmBinopIsString for why this cannot live inside the
    width oracle's failure arm. }
  if WasmBinopIsString(node) then
  begin
    if WasmEmitStrBinop(node, op) then Exit;
    WasmUnsupported('`' + WasmBinopName(op) + '` on strings');
    Exit;
  end;

  if not WasmBinopWidth(node, want, sgn) then
  begin
    { Name the operand TYPES and the IR KINDS. "operand type in binary
      operator 67" says a comparison was refused and nothing about which side
      or why; with both named the report is a diagnosis rather than a pointer
      to one. }
    WasmUnsupported(what + ': operand types '
                    + WasmTypeKindName(WasmNodeResultType(IRA[node])) + '/'
                    + WasmTypeKindName(WasmNodeResultType(IRB[node]))
                    + ', IR kinds ' + WasmIntStr(IRKind[IRA[node]]) + '/'
                    + WasmIntStr(IRKind[IRB[node]]));
    Exit;
  end;

  { Both operands are brought to ONE width before the instruction, because wasm
    has no mixed-width arithmetic at all. }
  WasmEmitValueAs(IRA[node], want, what);
  WasmEmitValueAs(IRB[node], want, what);
  if WasmBodyBroken then Exit;

  { Pascal `div` and `mod` lower to wasm div_s/rem_s, which TRAP on a zero
    divisor and on the INT_MIN div -1 overflow rather than raising. A trap is
    not a catchable Pascal exception, so the checked forms must arrive with the
    IR's own pre-check in front of them — removing that pre-check is a SEMANTIC
    change, not an optimisation (phase2-shadow-stack.md). }
  if (want = WT_F32) or (want = WT_F64) then
    WasmFloatBinop(op, want = WT_F64, what)
  else
    WasmIntBinop(op, want = WT_I64, sgn, what);
end;

{ ===== unary operators =====

  wasm has no integer negate and no integer complement: both are spelled as an
  arithmetic identity, which is why the operand order below matters. `0 - x`
  needs the zero pushed FIRST, so the constant is emitted before the operand —
  the opposite of every other emitter here, and the kind of thing that produces
  a sign-flipped answer rather than a validation failure if it is got wrong.
  Floats do have f32.neg/f64.neg, and they are not `0.0 - x`: they flip the
  sign bit, so they negate zero and NaN correctly where the subtraction would
  not. }

procedure WasmEmitUnary(node: Integer; isNeg: Boolean);
var got: TTypeKind; vt: Byte;
begin
  got := IntToTypeKind(IRTk[node]);
  if not WasmScalarType(got, vt) then
  begin
    WasmUnsupported('unary operand type ' + WasmIntStr(IRTk[node]));
    Exit;
  end;
  if isNeg and ((vt = WT_F32) or (vt = WT_F64)) then
  begin
    WasmEmitValueAs(IRA[node], vt, 'negation');
    if vt = WT_F32 then WasmOp($8C, 'f32.neg') else WasmOp($9A, 'f64.neg');
  end
  else if isNeg then
  begin
    if vt = WT_I64 then WasmI64Const(0) else WasmI32Const(0);
    WasmEmitValueAs(IRA[node], vt, 'negation');
    if vt = WT_I64 then WasmOp($7D, 'i64.sub') else WasmOp($6B, 'i32.sub');
  end
  else if got = tyBoolean then
  begin
    { `not` on a Boolean is a logical inversion, and eqz is exactly that for
      the 0/1 the comparisons produce — but ONLY for 0/1. It answers 0 for any
      other non-zero byte, where Pascal's `not` would answer a complement, so
      this arm is correct precisely because a Boolean slot in this dialect is
      never anything else. }
    WasmEmitValueAs(IRA[node], vt, 'not');
    if vt = WT_I64 then WasmOp($50, 'i64.eqz') else WasmOp($45, 'i32.eqz');
  end
  else if (vt = WT_F32) or (vt = WT_F64) then
  begin
    WasmUnsupported('bitwise not on a float');
    Exit;
  end
  else
  begin
    WasmEmitValueAs(IRA[node], vt, 'not');
    if vt = WT_I64 then
    begin
      WasmI64Const(-1); WasmOp($85, 'i64.xor');
    end
    else
    begin
      WasmI32Const(-1); WasmOp($73, 'i32.xor');
    end;
  end;
end;

procedure WasmEmitConstInt(node: Integer);
var vt: Byte;
begin
  if not WasmNodeType(node, vt) then
  begin
    WasmUnsupported('integer constant of type ' + WasmIntStr(IRTk[node]));
    Exit;
  end;
  if vt = WT_I64 then WasmI64Const(IRIVal[node])
  else if vt = WT_I32 then WasmI32Const(WasmWrap32(IRIVal[node]))
  else if vt = WT_F64 then
  begin
    { IRIVal holds the RAW IEEE bit pattern — that is why every register
      backend loads a float constant with its integer immediate loader — so the
      value crosses into the float domain by reinterpretation, not conversion.

      Reinterpret rather than `f64.const`, whose immediate is eight raw IEEE
      bytes. Not because the binary is harder (it is easier) but because the
      TEXT is: a .wat `f64.const` needs the double printed back as a literal
      that reparses to the identical bits, and this file's oracle compares the
      two modules. An integer and a reinterpret print exactly, in both. }
    WasmI64Const(IRIVal[node]);
    WasmOp($BF, 'f64.reinterpret_i64');
  end
  else if vt = WT_F32 then
  begin
    WasmI32Const(WasmWrap32(IRIVal[node]));
    WasmOp($BE, 'f32.reinterpret_i32');
  end
  else
    WasmUnsupported('constant of value type ' + WasmIntStr(vt)
                    + ' (Pascal type ' + WasmIntStr(IRTk[node]) + ')');
end;

{ Emit a value node. The return is the Pascal type of what was ACTUALLY left on
  the operand stack, which is not always the type the IR recorded on the node —
  and where they differ, what was emitted is the one that has to be believed.
  Reading IRTk instead would make the coercion layer consult a second source of
  truth about a value it did not produce. }
function WasmEmitNode(node: Integer): TTypeKind;
begin
  WasmEmitNode := tyInt32;
  if WasmBodyBroken then Exit;
  if node < 0 then begin WasmUnsupported('null node reference'); Exit; end;
  WasmEmitNode := WasmNodeResultType(node);
  case IRKind[node] of
    IR_CONST_INT : WasmEmitConstInt(node);
    IR_LOAD_SYM  : WasmEmitLoadSym(IRA[node]);
    IR_BINOP     : WasmEmitBinop(node);
    IR_CALL      : WasmEmitCall(node, False);
    IR_LEA       : WasmEmitLea(node);
    { The RAW slot address, unconditionally — never WasmEmitLea, whose by-ref
      auto-deref would hand back the CALLER's address for a var parameter.
      That is the whole distinction between the two ops (defs.inc:748), and
      the stackless save/restore path depends on it: it writes a by-ref
      param's own slot. WasmSlotAddr is already exactly this. }
    IR_SLOTADDR  : WasmSlotAddr(IRA[node]);
    IR_CONST_STR : WasmEmitConstStr(node);
    IR_INDEX     : WasmEmitIndex(node);
    IR_FIELD     : WasmEmitField(node);
    IR_LOAD_MEM  : WasmEmitLoadMem(node);
    IR_NEG       : WasmEmitUnary(node, True);
    IR_NOT       : WasmEmitUnary(node, False);
    IR_PROCADDR  : WasmEmitProcAddr(node);
    IR_CALL_IND  : WasmEmitCallInd(node, False);
    IR_VIRTUAL_CALL : WasmEmitVirtualCall(node, False);
    IR_ATOMIC    : WasmEmitAtomic(node);
  else
    WasmUnsupported('value IR op ' + WasmIntStr(IRKind[node]));
  end;
end;

{ ===== proc signatures and direct calls =====

  One function computes a proc's wasm signature and one map holds its function
  slot, and BOTH are shared by the body emitter and every call site. That is
  not economy: a caller and a callee that derive the shape separately can
  disagree, and wasm's answer to a disagreement is a validation failure at the
  call, which points at the caller rather than at whichever of the two got it
  wrong. }

{ A parameter's wasm type. A `var`/`out` parameter and an array parameter are
  ADDRESSES, whatever they are declared as — so `var x: Int64` is an i32
  parameter, not an i64 one. Taking the declared type here would give an i64
  parameter whose caller passes a pointer, and the slot store would be an
  i64.store of an i32: loud, but loud at the wrong place and for the wrong
  reason. }
function WasmParamValType(p, i: Integer; var vt: Byte): Boolean;
begin
  { THE ORACLE ANSWERS THIS, not a flag test written out here. abi.inc's opening
    note names the exact shape it exists to stop — a `Syms[...].IsRef or` chain
    inside an ir_codegen file — and the chain this replaced was one, reading
    Procs[p].Params[i].IsRef. It was also WRONG in a way the oracle is not: a
    frozen-string value parameter is passed as the address of a buffer on every
    target, and the flag that says so lives on the parameter's SYMBOL, not on
    the proc's declaration record. So `const x: ShortString` came back with no
    wasm value type at all and both the callee and every call site went
    unreachable — a missing convention reported as a missing type. }
  if ABIParamSlotIsPointer(Procs[p].Params[i].TypeKind,
                           Procs[p].Params[i].IsRef,
                           Procs[p].Params[i].IsArray)
     or TypeIsFrozenString(Procs[p].Params[i].TypeKind) then
  begin
    vt := WT_I32;
    WasmParamValType := True;
  end
  else
    WasmParamValType := WasmScalarType(Procs[p].Params[i].TypeKind, vt);
end;

function WasmProcResult(p: Integer; var vt: Byte): Boolean;
begin
  WasmProcResult := WasmScalarType(Procs[p].RetType, vt);
end;

{ The type index for proc p. Records a refusal — against whatever body is
  currently being emitted — for any part of the signature wasm cannot express,
  and substitutes a placeholder so the module stays well-formed: the body will
  be `unreachable`, which is polymorphic and validates against any signature. }
function WasmSigForProc(p: Integer): Integer;
var
  i, nParams, nRes: Integer;
  ptypes: array[0..31] of Byte;
  rtypes: array[0..0] of Byte;
begin
  nParams := Procs[p].ParamCount;
  if nParams > 32 then
  begin
    WasmUnsupported(Procs[p].Name + ' has more than 32 parameters');
    nParams := 32;
  end;
  for i := 0 to nParams - 1 do
    if not WasmParamValType(p, i, ptypes[i]) then
    begin
      ptypes[i] := WT_I32;
      WasmUnsupported('parameter ' + Procs[p].Params[i].Name + ' of '
                      + Procs[p].Name + ' has no wasm value type');
    end;
  nRes := 0;
  if Procs[p].IsFunc then
  begin
    nRes := 1;
    if not WasmProcResult(p, rtypes[0]) then
    begin
      rtypes[0] := WT_I32;
      if RetViaHiddenDest(Procs[p].RetType) then
        { Not a missing type — a missing CONVENTION, and naming which one is
          the difference between a reader who knows what to build and one who
          goes looking for a type mapping that does not exist. abi.inc's
          RetViaHiddenDest is the shared rule: the CALLER allocates the
          destination, the callee copies its Result local into it and returns
          the pointer. Records, sets, variants, promotable ints and the frozen
          strings are all one mechanism, so all five arrive together when the
          extra i32 parameter is threaded through WasmSigForProc, the call
          sites and the epilogue. }
        WasmUnsupported('result of ' + Procs[p].Name + ', of type '
                        + WasmTypeKindName(Procs[p].RetType)
                        + ', is returned through a caller-owned hidden'
                        + ' destination (abi.inc RetViaHiddenDest) and this'
                        + ' target does not thread one yet')
      else
        WasmUnsupported('result of ' + Procs[p].Name + ' has no wasm value'
                        + ' type');
    end;
  end;
  if nParams = 0 then
  begin
    { The array-slice spellings keep WasmAddType's open-array parameters honest
      for the 0-param and 0-result cases. }
    if nRes = 0 then WasmSigForProc := WasmAddType([], [])
    else WasmSigForProc := WasmAddType([], [rtypes[0]]);
  end
  else
    WasmSigForProc := WasmAddTypeN(ptypes, nParams, rtypes, nRes);
end;

{ The wasm function slot for proc p, reserved on first mention. }
function WasmSlotForProc(p: Integer): Integer;
begin
  if (p < 0) or (p >= MAX_PROCS) then
  begin
    WasmUnsupported('proc index ' + WasmIntStr(p) + ' out of range');
    WasmSlotForProc := 0;
    Exit;
  end;
  if WasmProcSlot[p] < 0 then
    WasmProcSlot[p] := WasmAddFunc(Procs[p].Name, WasmSigForProc(p));
  WasmSlotForProc := WasmProcSlot[p];
end;

{ A direct call. On a register target this is where the argument-passing ABI
  lives — riscv32 spends 508 lines here spilling arguments to its stack and
  reloading them into a0..a7. wasm has neither registers nor a calling
  convention to implement: arguments are pushed onto the operand stack in
  order and `call` consumes them. The ABI is the instruction.

  What is NOT handled, by name rather than by omission:

  * The BUILTIN encodings. IR_CALL doubles as the node for GetMem, FreeMem,
    class instantiation, SetLength and the rest, spelled as a NEGATIVE proc
    index (`-Ord(tkGetMem)`). Each is a small program, not a call. The clause
    that used to end this sentence — "and each needs the heap, Phase 6" — was
    the same unmeasured cause the note below `WasmBuiltinName` was written to
    retire, and it outlived both Phase 6 and several of the builtins it
    described: `SetLength` on a string lowers here today. What each one needs
    is its own answer, and the report now names the builtin instead of
    asserting a cause.
  * EXTERNAL procs, which need a wasm import and a host to provide it.
  * The hidden-destination return ABI for aggregates. wasm can express it (a
    pointer parameter, exactly as the register targets do), but choosing the
    convention is an ABI decision and belongs with the rest of Phase 4, not
    inferred here from one call site. }
{ WHAT a negative proc index IS, for the coverage report.

  The message this replaces said `needs the heap, Phase 6` for every one of
  them. That was not measured, it was assumed from the two members of the set
  that are true — GetMem and FreeMem — and it was WRONG for the ones that
  mattered most: `PXXAlloc` itself is blocked on an `Integer()` CAST, and the
  write path on `Trunc`. Neither has anything to do with the heap, and the
  message said they did, in a report that is then read as evidence. A
  diagnostic that names a CAUSE is asserting a root cause; this one names the
  BUILTIN and lets the reader decide.

  Only the ones this backend has met are spelled out. An unnamed code is
  reported as its number, which is honest and greppable. }
function WasmBuiltinName(p: Integer): AnsiString;
begin
  if p = -Ord(tkGetMem) then WasmBuiltinName := 'GetMem / class instantiation'
  else if p = -Ord(tkFreeMem) then WasmBuiltinName := 'FreeMem'
  else if p = -Ord(tkLength) then WasmBuiltinName := 'Length'
  else if p = -Ord(tkOrd) then WasmBuiltinName := 'Ord (type pun)'
  else if p = -Ord(tkChr) then WasmBuiltinName := 'Chr (type pun)'
  else if p = -Ord(tkInteger_T) then WasmBuiltinName := 'Integer() cast'
  else if p = -Ord(tkLongWord_T) then WasmBuiltinName := 'LongWord() cast'
  else if p = -Ord(tkChar_T) then WasmBuiltinName := 'Char() cast'
  else if p = -Ord(tkBoolean_T) then WasmBuiltinName := 'Boolean() cast'
  else if p = -Ord(tkString_T) then WasmBuiltinName := 'String() cast'
  else if p = -100 then WasmBuiltinName := 'LoadFile'
  else if p = -101 then WasmBuiltinName := 'SetLength on a frozen string'
  else if p = -102 then WasmBuiltinName := 'SetLength'
  else if p = -103 then WasmBuiltinName := 'ReallocMem'
  else if p = -203 then WasmBuiltinName := 'Trunc'
  else if p = -204 then WasmBuiltinName := 'Round'
  { -SPECIAL_IN. Confirmed by repro rather than inferred from the constant:
    `if i in [1,2,3]` refuses with exactly this code. It was 68 of the 881
    refusal lines when compiling `compiler.pas` — the largest single item after
    the dynamic-array family — and it was reading as `unrecognised`, which is
    the one label that tells a reader nothing about how big the gap is. Every
    register backend handles it (`j = SPECIAL_IN`). }
  else if p = -SPECIAL_IN then WasmBuiltinName := 'set membership (`in`)'
  else WasmBuiltinName := 'unrecognised';
end;

{ The TYPE a cast builtin produces. A cast is a passthrough on a register
  target — `Integer(x)` is already in the low half of the register the value
  sits in, so five backends emit nothing at all for it. Here the four value
  types are distinct and `Integer(someInt64)` is an `i32.wrap_i64`: a real
  instruction, and omitting it is a validation failure rather than a silent
  truncation, which is the good direction. Returns False for a code that is not
  a cast. }
function WasmCastKind(p: Integer; var tk: TTypeKind): Boolean;
begin
  WasmCastKind := True;
  if p = -Ord(tkInteger_T) then tk := tyInt32
  else if p = -Ord(tkLongWord_T) then tk := tyUInt32
  else if p = -Ord(tkChar_T) then tk := tyChar
  else if p = -Ord(tkBoolean_T) then tk := tyBoolean
  else if p = -Ord(tkChr) then tk := tyChar
  else WasmCastKind := False;
end;

function WasmBuiltinResultType(node: Integer): TTypeKind;
var p: Integer; ctk: TTypeKind;
begin
  p := IRA[node];
  if WasmCastKind(p, ctk) then WasmBuiltinResultType := ctk
  else if (p = -203) or (p = -204) then WasmBuiltinResultType := tyInt64
  else if p = -Ord(tkGetMem) then WasmBuiltinResultType := tyPointer
  else if p = -SPECIAL_IN then WasmBuiltinResultType := tyBoolean
  else if p = -Ord(tkLength) then WasmBuiltinResultType := tyInt32
  else if (p = -Ord(tkOrd)) and (IRB[node] <> -1) then
    WasmBuiltinResultType := WasmNodeResultType(IRA[IRB[node]])
  else
    WasmBuiltinResultType := IntToTypeKind(IRTk[node]);
end;

{ Call a named routine in the builtin unit with the arguments already on the
  operand stack. Fails loudly rather than silently emitting nothing: a missing
  allocator is a compiler bug, not a coverage gap. }
function WasmCallRtl(const nm: AnsiString): Boolean;
var p: Integer;
begin
  p := FindProc(nm);
  if p < 0 then
  begin
    WasmUnsupported('the builtin unit has no ' + nm);
    WasmCallRtl := False;
    Exit;
  end;
  WasmCall(WasmSlotForProc(p), nm);
  WasmCallRtl := True;
end;

{ Push the address of a Data[] offset — the blob's base plus a displacement.
  The same two instructions WasmSlotAddr uses for a data-resident global, and
  for the same reason: the base is not known until the module is written. }
procedure WasmDataAddr(off: Integer);
begin
  WasmGlobalGet(WasmGData);
  WasmI32Const(off);
  WasmOp($6A, 'i32.add');
end;

function WasmEmitGetMem(node: Integer): Boolean;
var classIdx, alloc, ctor, argNode, obj: Integer; pvt: Byte;
begin
  WasmEmitGetMem := False;
  argNode := IRB[node];                     { the size argument }
  if argNode = -1 then Exit;
  alloc := FindProc('PXXAlloc');
  if alloc < 0 then
  begin
    WasmUnsupported('the builtin unit has no PXXAlloc');
    Exit;
  end;
  if not WasmParamValType(alloc, 0, pvt) then pvt := WT_I32;
  WasmEmitValueAs(IRA[argNode], pvt, 'size argument of PXXAlloc');
  if WasmBodyBroken then Exit;
  if not WasmParamValType(alloc, 1, pvt) then pvt := WT_I32;
  if pvt = WT_I64 then WasmI64Const(8) else WasmI32Const(8);   { alignment }
  if not WasmCallRtl('PXXAlloc') then Exit;

  classIdx := IRC[node];
  if classIdx < REC_UCLASS_BASE then
  begin
    { Plain GetMem/New: the payload pointer IS the result. }
    WasmEmitGetMem := True;
    Exit;
  end;

  obj := WasmAddLocal(WT_I32, 'newobj');
  WasmLocalTee(obj);
  WasmDataAddr(UClsVMTOffset[classIdx - REC_UCLASS_BASE]);
  WasmMemOp($36, 'i32.store', 2, 0);        { [Self + 0] := VMT }

  ctor := IRResolveCtorProc(node, classIdx);
  if ctor >= 0 then
  begin
    WasmLocalGet(obj);                      { Self is parameter 0 }
    if not WasmEmitIndArgs(ctor, IRB[argNode], 1, 'constructor '
                           + Procs[ctor].Name) then Exit;
    WasmCall(WasmSlotForProc(ctor), Procs[ctor].Name);
    { A constructor's own return value is not the instance — the INSTANCE is,
      on every target. x86-64 saves Self across the call and returns it; here
      the saved copy is already in a local, so the ctor's result is dropped and
      the local is read back. }
    if Procs[ctor].IsFunc then WasmOp($1A, 'drop');
  end;
  WasmLocalGet(obj);
  WasmEmitGetMem := True;
end;

function WasmEmitFreeMem(node: Integer): Boolean;
var argNode: Integer; pvt: Byte; f: Integer;
begin
  WasmEmitFreeMem := False;
  argNode := IRB[node];
  if argNode = -1 then Exit;
  f := FindProc('PXXFree');
  if f < 0 then
  begin
    WasmUnsupported('the builtin unit has no PXXFree');
    Exit;
  end;
  if not WasmParamValType(f, 0, pvt) then pvt := WT_I32;
  WasmEmitValueAs(IRA[argNode], pvt, 'pointer argument of PXXFree');
  if WasmBodyBroken then Exit;
  if not WasmCallRtl('PXXFree') then Exit;
  WasmEmitFreeMem := True;
end;

{ Builtins this backend can lower. Returns False for one it cannot, so the
  caller reports it by NAME rather than this function inventing a reason. }
{ The STRING type a node denotes.

  Three IR shapes evaluate to an ADDRESS and report their own type as Pointer —
  IR_LEA of a symbol, IR_FIELD, IR_INDEX — so for them the node type says how
  the value is REACHED and not what is there. What is there is in the symbol
  (IR_LEA) or in IRTk (IR_FIELD, IR_INDEX), which is where the x86-64 arms read
  it too (ir_codegen.inc:7386, :7396). Everything else answers for itself.

  IsArray is excluded from the IR_LEA case on purpose: an open-array
  parameter's symbol carries its ELEMENT type, so a bare type test on one reads
  the element's layout — the confusion behind
  bug-open-array-param-length-high-zero. }
function WasmStrTypeOf(node: Integer): TTypeKind;
begin
  WasmStrTypeOf := WasmNodeResultType(node);
  if node < 0 then Exit;
  if IRKind[node] = IR_LEA then
  begin
    if not Syms[IRA[node]].IsArray then
      WasmStrTypeOf := Syms[IRA[node]].TypeKind;
  end
  else if (IRKind[node] = IR_FIELD) or (IRKind[node] = IR_INDEX) then
    WasmStrTypeOf := IntToTypeKind(IRTk[node])
  ;
  { A concat needs no case here: WasmBinopIsString stops the width oracle
    unifying two handles into a LongWord, so WasmNodeResultType already falls
    through to the IR's own record and answers tyAnsiString. It answered
    LongWord before that predicate existed, which is a true statement about the
    arithmetic and a false one about the value. }
end;

{ Length. Both string representations keep their length in a machine word next
  to the characters, so this is one load in each case — but the word is at a
  DIFFERENT place and a different width for each, and the width is the target's,
  not x86-64's:

    AnsiString   handle points AT the chars; the length is the NativeInt at
                 handle-8 (builtinheap.pas: PXX_HDR_LEN = 16, PXX_HDR_SIZE = 24,
                 PWord = ^NativeInt). NativeInt is FOUR bytes here, so this is an
                 i32.load where the x86-64 arm reads a qword. The header LAYOUT
                 is target-independent; the field width is not.
    frozen       the value IS the buffer address and the length is the low word
                 of the 8-byte inline prefix, so an i32.load at offset 0 reads
                 it on a little-endian target.

  nil is length 0 and needs a real branch, not a select: the false arm loads
  from handle-8, which for a nil handle is 0xFFFFFFF8.

  Arrays are NOT here yet. Length of a dynamic array or an open-array parameter
  is a third layout (the element count below the data pointer) with its own set
  of shapes for how the pointer is reached, and guessing at it would produce a
  plausible number rather than a refusal. It is refused BY TYPE below and names
  the type in the message. }
{ Is this node a DYNAMIC ARRAY — the reference-typed one with a heap block and
  a length word, not a fixed `array[0..9] of Integer` whose storage is the
  frame? Both answer IsArray; ArrLen = -1 is what separates them, and asking
  only IsArray is what an earlier version of the IR_LEA arm did, which refused
  `a[i]` on a static array where nothing is on the heap at all.

  Only the LEA-of-a-symbol shape is recognised. A dynamic array reached through
  a record field or another array element is a slot address needing its own
  deref — the same distinction the string arms make — and it is not implemented
  yet, so it must not be silently treated as a root. Answering False here
  refuses it by name downstream, which is the direction that cannot produce a
  wrong number. }
function WasmNodeIsDynArray(n: Integer): Boolean;
begin
  WasmNodeIsDynArray := (IRKind[n] = IR_LEA) and (IRA[n] >= 0)
                        and Syms[IRA[n]].IsArray and (Syms[IRA[n]].ArrLen = -1);
end;

function WasmEmitLength(valNode: Integer): Boolean;
var tk: TTypeKind; lv, ll, ls: Integer; ok: Boolean;
begin
  WasmEmitLength := False;
  tk := WasmStrTypeOf(valNode);

  { Length IS the first half of WasmStrParts, so it asks WasmStrParts rather
    than restating the two layouts and the nil guard. They were two copies for
    one phase and the copies already differed in one detail — the FIELD/INDEX
    deref was in the managed arm here and nowhere else — which is how this
    would have drifted. Arrays are refused BY TYPE below, before the splitter
    sees them, because Length of a dynamic array is a THIRD layout and a
    plausible number is worse than a refusal. }
  { A DYNAMIC ARRAY is the third layout, and it is now implemented rather than
    refused. Its data pointer is what IR_LEA yields, and its element count sits
    where a string's character count does — one word below the data, written by
    PXXDynSetLen as `PWord(block + PXX_HDR_LEN)^` with data at
    `block + PXX_HDR_SIZE`. Sharing that offset with the string arm is the
    layout's doing, not a coincidence worth collapsing the two arms over: they
    reach the pointer differently and only agree from there on.

    nil is 0 elements, and the guard is required rather than defensive — a
    declared-but-never-SetLength array holds nil, `Length(a)` on it is legal
    Pascal and must answer 0, and without the guard it reads address -8. }
  if WasmNodeIsDynArray(valNode) then
  begin
    WasmEmitValueAs(valNode, WT_I32, 'Length of a dynamic array');
    if WasmBodyBroken then Exit;
    lv := WasmStrSlot(1);
    WasmLocalSet(lv);
    WasmLocalGet(lv);
    WasmOp($45, 'i32.eqz');
    WasmIf(WT_I32);
    WasmI32Const(0);
    WasmElse;
    WasmLocalGet(lv);
    WasmI32Const(8);
    WasmOp($6B, 'i32.sub');
    WasmMemOp($28, 'i32.load', 2, 0);
    WasmEnd;
    WasmEmitLength := True;
    Exit;
  end;
  if (tk <> tyAnsiString) and not TypeIsFrozenString(tk) then
  begin
    WasmUnsupported('Length of ' + WasmTypeKindName(tk)
                    + ' — only strings are implemented on this target so far');
    Exit;
  end;
  { A depth level of its own, because Length's operand may be a whole string
    expression (`Length(a + b)`) and would otherwise reuse these three slots
    while they are live. -1 for the scratch: the operand is a string by the
    check above, never a Char, so the spill path is unreachable here and says
    so rather than being handed an address it would not use. }
  if WasmStrDepth >= WASM_STR_DEPTH then
  begin
    WasmUnsupported('string expression nested more than '
                    + WasmIntStr(WASM_STR_DEPTH) + ' deep');
    Exit;
  end;
  lv := WasmStrSlot(1); ll := WasmStrSlot(2); ls := WasmStrSlot(3);
  Inc(WasmStrDepth);
  ok := WasmStrParts(valNode, -1, 0, lv, ll, ls);
  Dec(WasmStrDepth);
  if not ok then Exit;
  WasmLocalGet(ll);
  WasmEmitLength := True;
end;

{ `x in [a, b, lo..hi]` — SPECIAL_IN, spelled as a call with proc index -999.

  ARG SHAPE, read from the IR rather than guessed: arg1's IRA is the TEST
  VALUE; every later arg's IRA is a set item, and an item is either a constant
  node or an IR_BLOCK carrying a RANGE (lo in IRA, hi in IRB). That is the
  contract all four register backends implement.

  BRANCHLESS, where they all use jumps. wasm has no flags register to
  accumulate into, but it has an operand stack, so the whole set is one
  expression: start with 0 and `i32.or` each membership test onto it. A range is
  `(v >= lo) and (v <= hi)`, signed, matching i386's jl/jg. The empty set falls
  out correctly — nothing is or-ed onto the 0.

  SIGNEDNESS is signed for the same reason theirs is: set members are ordinals
  and an enum or Char is non-negative anyway, so the two agree everywhere a
  program can tell.

  WIDTH: the comparison happens at the TEST VALUE's own width. i386 moves the
  value into eax and compares 32-bit, so `i: Int64; i in [1]` with i = 2^32+1
  answers TRUE there. Doing it in i64 here is two extra opcodes and not a
  divergence worth inheriting — i64.eq/ge_s/le_s all yield i32, so only the
  pushes change type and the accumulator stays i32 either way.

  THE NON-CONSTANT REFUSAL IS A TRIPWIRE, NOT A GUARD, and the difference is
  worth stating because the first version of this comment got it wrong. It said
  the refusal protected against the fail-open in i386, which reads
  Integer(IRIVal[itemNode]) with no kind check. Measured: it protects against
  nothing, because SPECIAL_IN is only ever emitted for an ALL-CONSTANT set
  literal. `i in [j]` with a variable member does not reach here at all — it
  lowers to IR_DEFAULT_MEM over a real 32-byte set (confirmed in the IR dump:
  `default_mem ival=32 tk=21`, no -999 node anywhere). So i386's unchecked read
  is safe, and saying otherwise was a claim about another backend that one
  command would have checked, which is exactly what this branch keeps finding
  in other people's comments.

  The refusal stays, on the same reasoning as the -1 poison values in
  exception_emit.inc: it cannot fire today, and if the frontend ever routes a
  variable member through SPECIAL_IN it converts a silent comparison against a
  meaningless field into a named stop. What it must not do is read as coverage
  of a live hazard. }
function WasmEmitSetIn(node: Integer): Boolean;
var argNode, itemNode, v: Integer; vt: Byte; wide: Boolean;

  procedure PushOrd(x: Int64);
  begin
    if wide then WasmI64Const(x) else WasmI32Const(x);
  end;

  { IR_CONST_INT only — there is no IR_CONST_CHAR. `c in ['a'..'z']` lowers its
    members to const_int 97 and 122, which the IR dump shows directly and which
    is why this asks about the NODE KIND rather than about the element type. }
  function ItemIsConst(n: Integer): Boolean;
  begin
    ItemIsConst := IRKind[n] = IR_CONST_INT;
  end;

begin
  WasmEmitSetIn := False;
  argNode := IRB[node];
  if argNode = -1 then Exit;

  vt := WT_I32;
  if not WasmScalarType(WasmNodeResultType(IRA[argNode]), vt) then vt := WT_I32;
  wide := (vt = WT_I64);

  if wide then
  begin
    if WasmSetInLoc64 < 0 then WasmSetInLoc64 := WasmAddLocal(WT_I64, 'inval64');
    v := WasmSetInLoc64;
  end
  else
  begin
    if WasmSetInLoc < 0 then WasmSetInLoc := WasmAddLocal(WT_I32, 'inval');
    v := WasmSetInLoc;
  end;

  WasmEmitValueAs(IRA[argNode], vt, 'the value tested by `in`');
  if WasmBodyBroken then Exit;
  WasmLocalSet(v);

  WasmI32Const(0);                        { the accumulator }
  argNode := IRB[argNode];
  while argNode <> -1 do
  begin
    itemNode := IRA[argNode];
    if IRKind[itemNode] = IR_BLOCK then
    begin
      if not (ItemIsConst(IRA[itemNode]) and ItemIsConst(IRB[itemNode])) then
      begin
        WasmUnsupported('a non-constant range in a set literal');
        Exit;
      end;
      WasmLocalGet(v); PushOrd(IRIVal[IRA[itemNode]]);
      if wide then WasmOp($59, 'i64.ge_s') else WasmOp($4E, 'i32.ge_s');
      WasmLocalGet(v); PushOrd(IRIVal[IRB[itemNode]]);
      if wide then WasmOp($57, 'i64.le_s') else WasmOp($4C, 'i32.le_s');
      WasmOp($71, 'i32.and');
    end
    else
    begin
      if not ItemIsConst(itemNode) then
      begin
        WasmUnsupported('a non-constant member in a set literal');
        Exit;
      end;
      WasmLocalGet(v); PushOrd(IRIVal[itemNode]);
      if wide then WasmOp($51, 'i64.eq') else WasmOp($46, 'i32.eq');
    end;
    WasmOp($72, 'i32.or');
    argNode := IRB[argNode];
  end;
  WasmEmitSetIn := True;
end;

function WasmEmitBuiltin(node, p: Integer; isStmt: Boolean): Boolean;
var argNode: Integer; ctk: TTypeKind; atk: TTypeKind; want: Byte; wide: Boolean;
begin
  WasmEmitBuiltin := False;
  argNode := IRB[node];
  if argNode = -1 then Exit;

  { --- casts and Ord: a value conversion, not a no-op --- }
  if WasmCastKind(p, ctk) then
  begin
    if not WasmScalarType(ctk, want) then Exit;
    WasmEmitValueAs(IRA[argNode], want, WasmBuiltinName(p));
    WasmEmitBuiltin := True;
    Exit;
  end;

  { Ord: the ORDINAL of its argument, which is the value itself for every type
    that has one. Its width is the argument's, not a fixed i32 — `Ord` of an
    Int64-backed enum would otherwise be wrapped silently. }
  if p = -Ord(tkOrd) then
  begin
    atk := WasmNodeResultType(IRA[argNode]);
    if not WasmScalarType(atk, want) then Exit;
    WasmEmitValueAs(IRA[argNode], want, 'Ord');
    WasmEmitBuiltin := True;
    Exit;
  end;

  { --- GetMem, New, and class instantiation ---

    The allocator is NOT written here. `PXXAlloc(size, align)` is an ordinary
    Pascal routine in the builtin unit, and every backend calls it — the x86-64
    path spends its lines saving registers around the call, which is the whole
    of what this target does not have to do. So the interesting part is not the
    heap at all; it is the four steps AFTER it, which are the same on every
    target and which wasm expresses with a scratch local instead of a stack
    slot.

    A FRESH local per allocation SITE, not one per body. `z[0] := A.Create;
    z[1] := B.Create` is three sites in one body, and a constructor argument
    may itself allocate — a shared local would be clobbered by the inner
    allocation between the outer store and the outer read. One local per site
    is correct by construction and costs a locals-vector entry. }
  if p = -Ord(tkGetMem) then
  begin
    WasmEmitBuiltin := WasmEmitGetMem(node);
    Exit;
  end;

  if p = -Ord(tkFreeMem) then
  begin
    WasmEmitBuiltin := WasmEmitFreeMem(node);
    Exit;
  end;

  if p = -SPECIAL_IN then
  begin
    WasmEmitBuiltin := WasmEmitSetIn(node);
    Exit;
  end;

  if p = -Ord(tkLength) then
  begin
    WasmEmitBuiltin := WasmEmitLength(IRA[argNode]);
    Exit;
  end;

  { --- Trunc / Round: the float->int conversion the coercion layer REFUSES to
    insert on its own, and this is why. Which one you get is a language
    decision (toward zero vs nearest-even), so it has to be asked for, and
    these two nodes are the ask.

    Both yield Int64, matching what the other backends' soft-float kernels
    return. Round is `nearest` then `trunc`: wasm's f64.nearest is
    round-half-to-EVEN, which is Pascal's Round exactly, so no correction
    follows it.

    DIVERGENCE, stated because it is real and not a bug to be fixed here: wasm's
    trunc_*_s TRAPS on NaN and on a value outside Int64, where x86-64 returns
    $8000000000000000 and aarch64 saturates. Our own targets already disagree
    about this, so there is no behaviour to match; a trap is the loudest of the
    three and the easiest to reason about. The non-trapping `trunc_sat` forms
    exist and would need a post-MVP feature; revisit if a real program depends
    on the value rather than on not crashing. --- }
  { --- SetLength on a managed string ---

    SetLength is builtin -102 for BOTH a dynamic array and a managed string,
    and the two are different routines with different arguments; the lvalue's
    type is what tells them apart. Both halves are implemented; the array one
    is below, and it takes a third argument the string one does not.

    PXXStrSetLen(slotAddr, n) takes the SLOT's address, not the handle: it
    allocates a fresh block, copies min(old, new) bytes, and PUBLISHES the new
    handle into the slot before releasing the old one. Handing it the handle
    would compile — every argument here is an i32 — and would write a heap
    pointer over the first word of the string's own characters.

    So the argument is WasmLValueAddr, which already answers slot-address for
    a `var s: string` parameter too (the ABI oracle derefs the frame slot).
    That is the whole of the var-param case the register backends spell out by
    hand (ir_codegen_riscv32.inc:2350). --- }
  if p = -102 then
  begin
    if (IRKind[IRA[argNode]] = IR_LOAD_SYM)
       and (Syms[IRA[IRA[argNode]]].TypeKind = tyAnsiString)
       and not Syms[IRA[IRA[argNode]]].IsArray then
    begin
      if IRB[argNode] = -1 then
      begin
        WasmUnsupported('SetLength on a managed string with no length argument');
        Exit;
      end;
      WasmLValueAddr(IRA[IRA[argNode]]);
      WasmEmitValueAs(IRA[IRB[argNode]], WT_I32, 'SetLength count');
      if WasmBodyBroken then Exit;
      if not WasmCallRtl('PXXStrSetLen') then Exit;
      WasmEmitBuiltin := True;
    end;
    { --- SetLength on a DYNAMIC ARRAY ---

      PXXDynSetLen(slotAddr, n, desc) — the same slot-not-handle rule as the
      string call above, plus a DESCRIPTOR, because the routine has to know the
      element size to allocate and the element kind to release. The descriptor
      is `GetOrAllocSymRTTI(si)`, the SYMBOL's, which is what riscv32 uses on
      this flat path; the node-derived `GetOrAllocNodeDynDesc` is for a NESTED
      target (`SetLength(m[0], n)`), where the row has one fewer dimension than
      the symbol and the symbol's descriptor would say the wrong stride.

      WasmLValueAddr and NOT the IR_LEA node: LEA on a dynamic array yields the
      data pointer (see its arm), and PXXDynSetLen takes `arrSlot = nil` as
      "nothing to do", so handing it a fresh array's nil handle makes SetLength
      silently succeed and do nothing. riscv32 shipped exactly that bug
      (bug-a-riscv32-nested-dynamic-array-element-write-segfaults).

      The descriptor lands in Data[] and is filled by EmitRTTI, which is not
      target-gated, and relocated by WasmFillData, which already applies
      DataPtrFix. Both were checked before this arm was written rather than
      after it failed. --- }
    if (IRKind[IRA[argNode]] = IR_LEA)
       and (IRA[IRA[argNode]] >= 0)
       and Syms[IRA[IRA[argNode]]].IsArray
       and (Syms[IRA[IRA[argNode]]].ArrLen = -1) then
    begin
      if IRB[argNode] = -1 then
      begin
        WasmUnsupported('SetLength on a dynamic array with no length argument');
        Exit;
      end;
      WasmLValueAddr(IRA[IRA[argNode]]);
      WasmEmitValueAs(IRA[IRB[argNode]], WT_I32, 'SetLength count');
      if WasmBodyBroken then Exit;
      WasmDataAddr(GetOrAllocSymRTTI(IRA[IRA[argNode]]));
      if not WasmCallRtl('PXXDynSetLen') then Exit;
      WasmEmitBuiltin := True;
      Exit;
    end;
    { Anything else falls through and is refused by WasmEmitCall under the
      name it has always carried. What reaches here is a SetLength whose target
      is neither a scalar managed string nor a root dynamic array — a nested
      row, or a dyn array behind a field or an element — each of which is a
      slot address needing its own deref and its own descriptor. }
    Exit;
  end;

  if (p = -203) or (p = -204) then
  begin
    atk := WasmNodeResultType(IRA[argNode]);
    if TypeIsFloat(atk) then
    begin
      wide := (atk = tyDouble);
      if wide then WasmEmitValueAs(IRA[argNode], WT_F64, 'Trunc/Round')
      else WasmEmitValueAs(IRA[argNode], WT_F32, 'Trunc/Round');
      if WasmBodyBroken then Exit;
      if p = -204 then
      begin
        { $9E, not $9C. $9C is f64.floor, and the difference shows only on an
          exact half: Round(2.5) is 2 under both, Round(3.5) is 4 under nearest
          and 3 under floor. The slice picks halves either side of zero for
          exactly this reason, and it caught it on the first run. }
        if wide then WasmOp($9E, 'f64.nearest') else WasmOp($90, 'f32.nearest');
      end;
      if wide then WasmOp($B0, 'i64.trunc_f64_s')
      else WasmOp($AE, 'i64.trunc_f32_s');
    end
    else
    begin
      { Trunc/Round of an integer is identity, widened to the Int64 result. }
      WasmEmitValueAs(IRA[argNode], WT_I64, 'Trunc/Round of an integer');
    end;
    WasmEmitBuiltin := True;
    Exit;
  end;
end;

{ ===== host imports =====

  `external 'lib' name 'sym'` and a wasm import are the same declaration. The
  two-part name a wasm import needs — a MODULE and a FIELD — is exactly what
  the Pascal form already carries and what the parser already records:
  ProcLibrary is the module, ProcExtName the field (pasparser_proc.inc:1298).
  Nothing had to be added to a shared file for this; both fields were already
  there and populated, used until now only by the ELF writers.

  That is what makes Phase 8's PAL a set of DECLARATIONS rather than a set of
  backend special cases: the WASI surface is spelled in Pascal source.

  A routine declared external but never called declares no import — and that is
  load-bearing, not an optimisation. A wasm host must supply EVERY declared
  import or instantiation fails, so a module declaring imports it does not use
  is a module that will not load. `builtin.pas` alone declares more externals
  than any wasm host provides. }
{ Declare (once) a host import this backend needs in its own right, and return
  its wasm function index. See WasmHostImpName. }
function WasmHostImport(const modName, fldName: AnsiString;
                        const params: array of Byte;
                        const results: array of Byte): Integer;
var i: Integer;
begin
  for i := 0 to WasmHostImpCount - 1 do
    if WasmHostImpName[i] = fldName then
    begin
      WasmHostImport := WasmHostImpIdx[i];
      Exit;
    end;
  if WasmHostImpCount > High(WasmHostImpName) then
    WasmFail('wasm: too many backend host imports');
  WasmHostImpName[WasmHostImpCount] := fldName;
  WasmHostImpIdx[WasmHostImpCount] :=
    WasmAddImportFunc(modName, fldName, WasmAddType(params, results));
  WasmHostImport := WasmHostImpIdx[WasmHostImpCount];
  Inc(WasmHostImpCount);
end;

function WasmImportIndex(p: Integer): Integer;
var modName, fldName: AnsiString;
begin
  WasmImportIndex := -1;
  if (p < 0) or (p >= MAX_PROCS) then
  begin
    WasmUnsupported('external proc index ' + WasmIntStr(p) + ' out of range');
    Exit;
  end;
  if WasmProcImpIdx[p] < 0 then
  begin
    if ProcExtName[p] >= 0 then fldName := Strs[ProcExtName[p]].Text
    else fldName := Procs[p].Name;
    { No library clause: `env` is the module name wasm-ld defaults to and the
      convention non-WASI host toolchains write. A WASI routine names its module
      explicitly — external 'wasi_snapshot_preview1' name 'fd_write'. }
    if ProcLibrary[p] >= 0 then modName := Strs[ProcLibrary[p]].Text
    else modName := 'env';
    WasmProcImpIdx[p] := WasmAddImportFunc(modName, fldName, WasmSigForProc(p));
  end;
  WasmImportIndex := WasmProcImpIdx[p];
end;

{ A string literal used as a VALUE is the address of its interned blob — the
  same thing every register backend loads with an immediate dataref, and the
  same address the write path already hands to PXXWriteFrozenW. What sits there
  is a frozen string buffer: an 8-byte length prefix, then the chars, then a
  nul (measured: `0a 00 00 00 00 00 00 00 'QWERTYUIOP'`). So a consumer may
  read it as a length-prefixed string or, from +8, as a PChar, which is what
  the variant engine does with it.

  Note this is IR_CONST_STR the VALUE, not the operand form the write path
  special-cases: there the literal's offset is known at the call site and the
  address never reaches the operand stack. Two shapes, one address computation,
  and WasmDataAddr is where both end up. }
procedure WasmEmitConstStr(node: Integer);
var sVal: AnsiString; si: Integer;
begin
  sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
  si := InternStr(sVal);
  WasmDataAddr(Strs[si].Offset);
end;

procedure WasmEmitCall(node: Integer; isStmt: Boolean);
var p, argNode, i, nParams, impIdx: Integer; pvt: Byte;
begin
  p := IRA[node];
  if p < 0 then
  begin
    if WasmEmitBuiltin(node, p, isStmt) then Exit;
    WasmUnsupported('builtin ' + WasmBuiltinName(p) + ' (IR_CALL with proc '
                    + 'index ' + WasmIntStr(p) + ')');
    Exit;
  end;
  impIdx := -1;
  if (p < Length(ProcExternal)) and ProcExternal[p] then
  begin
    impIdx := WasmImportIndex(p);
    if impIdx < 0 then Exit;
  end;
  nParams := Procs[p].ParamCount;
  argNode := IRB[node];
  i := 0;
  while (argNode <> -1) and (not WasmBodyBroken) do
  begin
    if i >= nParams then
    begin
      WasmUnsupported('call to ' + Procs[p].Name + ' passes more than its '
                      + WasmIntStr(nParams) + ' parameters');
      Exit;
    end;
    if not WasmParamValType(p, i, pvt) then
    begin
      WasmUnsupported('argument ' + WasmIntStr(i) + ' of ' + Procs[p].Name
                      + ' has no wasm value type');
      Exit;
    end;
    WasmEmitValueAs(IRA[argNode], pvt, 'argument to ' + Procs[p].Name);
    Inc(i);
    argNode := IRB[argNode];
  end;
  if WasmBodyBroken then Exit;
  if i <> nParams then
  begin
    { wasm counts the operand stack, so a short call is a validation failure
      rather than a garbage register — but it is a validation failure in the
      CALLER, so say which call it was while that is still known. }
    WasmUnsupported('call to ' + Procs[p].Name + ' passes ' + WasmIntStr(i)
                    + ' of ' + WasmIntStr(nParams) + ' parameters');
    Exit;
  end;
  if impIdx >= 0 then WasmCallImport(impIdx, Procs[p].Name)
  else WasmCall(WasmSlotForProc(p), Procs[p].Name);
  { A function called for its side effect leaves its result on the operand
    stack, and wasm requires the stack to be empty at the end of a statement.
    `drop` is that requirement, not a tidy-up. }
  if isStmt and Procs[p].IsFunc then WasmOp($1A, 'drop');
  if impIdx < 0 then
  begin
    if not WasmProcResult(p, pvt) then pvt := WT_I32;
    WasmEmitPostCall(pvt, Procs[p].IsFunc and not isStmt);
  end;
end;

{ ===== indirect calls =====

  wasm has no code addresses. A function is reachable through a `call` (a
  static index) or through a `call_indirect` (a runtime index into a table),
  and nothing in the language turns a function into a number you can do
  arithmetic on. So `@Proc`, a procedural variable, a VMT slot and an RTTI
  method entry all become the same thing here: a TABLE INDEX.

  That is a smaller change than it sounds, and the reason is worth stating
  because the plan predicted otherwise. The frontends never write a code
  address into `Data[]` — they cannot, because no address exists while `Data[]`
  is being built. They record a RELOCATION (`AddMethodFix`, emit.inc:103, the
  one append point) and the writer resolves it. The ELF writers resolve it to
  `entry + BodyAddr`; this backend resolves it to a table index. Same list,
  same shape, different meaning, and no shared file has to know.

  Phase 0 checked the one thing that could have made indices unusable: whether
  any code ORDERS or does arithmetic on a procedure address. `lib/rtl/
  scheduler.pas` is the only place, and it is the coroutine stack-frame builder
  — already out of scope for this target.

  Index 0 is never handed out. An MVP table element that no segment writes is
  null and `call_indirect` through it traps, so a nil procedural variable — a
  zeroed VMT slot, an uninitialised procvar — traps on call for free, with no
  reserved dummy function and no explicit compare at the call site. }

{ A proc's table index, assigned on first demand. THE one place a proc becomes
  an index; both consumers ask here rather than deriving it. }
function WasmTableIndex(p: Integer): Integer;
begin
  if (p < 0) or (p >= MAX_PROCS) then
  begin
    WasmUnsupported('proc index ' + WasmIntStr(p) + ' out of range');
    WasmTableIndex := 0;
    Exit;
  end;
  if WasmProcTabIdx[p] < 0 then
    WasmProcTabIdx[p] := WasmTableAdd(WasmSlotForProc(p));
  WasmTableIndex := WasmProcTabIdx[p];
end;

{ `@Proc` — the address of a routine, as a table index. }
procedure WasmEmitProcAddr(node: Integer);
begin
  WasmI32Const(WasmTableIndex(IRA[node]));
end;

{ The arguments of an indirect or virtual call, pushed in order, starting at
  parameter `startIdx` — 0 for an ordinary indirect call, 1 for a virtual one
  whose Self has already been emitted and teed. Shared by both because the
  marshalling is identical (wasm has no calling convention to differ over), and
  because a caller and a callee that count parameters separately can disagree,
  which wasm reports at the CALLER. }
function WasmEmitIndArgs(sigProc, firstArg, startIdx: Integer;
                         const what: AnsiString): Boolean;
var argNode, i, nParams: Integer; pvt: Byte;
begin
  WasmEmitIndArgs := False;
  nParams := Procs[sigProc].ParamCount;
  argNode := firstArg;
  i := startIdx;
  while (argNode <> -1) and (not WasmBodyBroken) do
  begin
    if i >= nParams then
    begin
      WasmUnsupported(what + ' passes more than its ' + WasmIntStr(nParams)
                      + ' parameters');
      Exit;
    end;
    if not WasmParamValType(sigProc, i, pvt) then
    begin
      WasmUnsupported('argument ' + WasmIntStr(i) + ' of ' + what
                      + ' has no wasm value type');
      Exit;
    end;
    WasmEmitValueAs(IRA[argNode], pvt, 'argument to ' + what);
    Inc(i);
    argNode := IRB[argNode];
  end;
  if WasmBodyBroken then Exit;
  if i <> nParams then
  begin
    WasmUnsupported(what + ' passes ' + WasmIntStr(i) + ' of '
                    + WasmIntStr(nParams) + ' parameters');
    Exit;
  end;
  WasmEmitIndArgs := True;
end;

{ A call through a value: a procedural variable, or a VMT slot already loaded.
  IRA = the callee value, IRB = the argument chain, IRIVal = the proc whose
  declaration is the SIGNATURE (not a callee — nothing calls it). }
procedure WasmEmitCallInd(node: Integer; isStmt: Boolean);
var sigProc: Integer; pvt: Byte;
begin
  sigProc := Integer(IRIVal[node]);
  if (sigProc < 0) or (sigProc >= MAX_PROCS) then
  begin
    WasmUnsupported('indirect call with no signature');
    Exit;
  end;
  if IRCallDest[node] >= 0 then
  begin
    WasmUnsupported('indirect call returning an aggregate — the hidden-'
                    + 'destination ABI is not chosen for this target yet');
    Exit;
  end;
  if not WasmEmitIndArgs(sigProc, IRB[node], 0, 'indirect call') then Exit;
  { The table index goes on TOP, after the arguments — call_indirect pops it
    first. }
  WasmEmitValueAs(IRA[node], WT_I32, 'indirect call target');
  if WasmBodyBroken then Exit;
  WasmCallIndirect(WasmSigForProc(sigProc));
  if isStmt and Procs[sigProc].IsFunc then WasmOp($1A, 'drop');
  if not WasmProcResult(sigProc, pvt) then pvt := WT_I32;
  WasmEmitPostCall(pvt, Procs[sigProc].IsFunc and not isStmt);
end;

{ VMT dispatch. IRA = first arg (Self is argument 0), IRB chains them, IRC =
  the proc whose declaration is the signature, IRIVal = the VMT slot.

  Self is needed TWICE — once as argument 0 and once to load the VMT — and the
  operand stack yields it once, so it is teed into a scratch local. That is the
  whole difference from an ordinary indirect call; the register backends spill
  every argument to make room and then reload, which is machinery this target
  does not need.

  The slot stride is *8 on every target (ir.inc:7332): the data blob keeps
  8-byte slots and a 32-bit target puts its value in the low dword. PtrSize is
  4 here, so an i32 load at slot*8 reads exactly the four bytes WasmFillData
  wrote the table index into. }
procedure WasmEmitVirtualCall(node: Integer; isStmt: Boolean);
var sigProc, slot, argNode: Integer; pvt: Byte;
begin
  sigProc := IRC[node];
  slot := Integer(IRIVal[node]);
  if (sigProc < 0) or (sigProc >= MAX_PROCS) then
  begin
    WasmUnsupported('virtual call with no signature');
    Exit;
  end;
  if IRCallDest[node] >= 0 then
  begin
    WasmUnsupported('virtual call returning an aggregate — the hidden-'
                    + 'destination ABI is not chosen for this target yet');
    Exit;
  end;
  argNode := IRA[node];
  if argNode = -1 then
  begin
    WasmUnsupported('virtual call with no Self argument');
    Exit;
  end;
  if not WasmParamValType(sigProc, 0, pvt) then pvt := WT_I32;
  if pvt <> WT_I32 then
  begin
    WasmUnsupported('virtual call whose Self is not a pointer');
    Exit;
  end;
  if WasmLocalSelf < 0 then WasmLocalSelf := WasmAddLocal(WT_I32, 'vself');
  { argument 0, kept }
  WasmEmitValueAs(IRA[argNode], WT_I32, 'Self of a virtual call');
  if WasmBodyBroken then Exit;
  WasmLocalTee(WasmLocalSelf);
  if not WasmEmitIndArgs(sigProc, IRB[argNode], 1, 'virtual call') then Exit;
  { vmt := [Self];  index := [vmt + slot*8] }
  WasmLocalGet(WasmLocalSelf);
  WasmMemOp($28, 'i32.load', 2, 0);
  WasmMemOp($28, 'i32.load', 2, slot * 8);
  WasmCallIndirect(WasmSigForProc(sigProc));
  if isStmt and Procs[sigProc].IsFunc then WasmOp($1A, 'drop');
  if not WasmProcResult(sigProc, pvt) then pvt := WT_I32;
  WasmEmitPostCall(pvt, Procs[sigProc].IsFunc and not isStmt);
end;

{ ===== control flow =====

  wasm has no jumps, so an unstructured CFG cannot be emitted directly. The
  standard answer, and the one PLAN.md's Phase 3 names, is a DISPATCH LOOP: the
  body is cut into basic blocks, a `$pc` local holds the block to run next, and
  one `br_table` at the top of a loop jumps to it. The blocks are nested so
  that breaking out of exactly k of them lands at basic block k's code:

      block                    ;; $exit
        loop                   ;; $L
          block ... block      ;; B(n-1) ... B0, B0 innermost
            local.get $pc
            br_table 0 1 ... n-1  (default n+1 -> $exit)
          end                  ;; B0 ends, so:
          <code of block 0>
          end                  ;; B1 ends, so:
          <code of block 1>
          ...
          end                  ;; B(n-1) ends
          <code of block n-1>
        end                    ;; falling off a loop EXITS it — no back edge
      end

  Two things fall out of this shape that are worth stating, because both look
  like omissions:

  * **Fallthrough costs nothing.** Block k's code is the last thing inside
    B(k+1), so falling off the end of B(k+1) lands exactly on block k+1's code.
    A block that ends without a jump therefore emits no branch at all — not an
    optimisation, just what the nesting already means.
  * **A stale $pc is harmless.** $pc is read at the dispatch and nowhere else,
    and the dispatch is only reached by a `br` that is always immediately
    preceded by setting it. So a conditional jump may set $pc and then NOT
    branch, and the value is simply never read.

  A body with no control flow at all skips the whole construction and emits its
  statements flat, which keeps the .wat oracle readable for the simple cases
  where reading it is how you debug. }

{ The depth of the dispatch loop, counted outward from inside block blk's code:
  that code sits inside B(blk+1)..B(n-1) and the loop, so the loop is n-1-blk
  levels out. $exit is one further. These two lines are the entire reason this
  scheme is delicate — a depth is a property of WHERE THE BRANCH SITS, not of
  where it goes, so it cannot be checked by looking at the target. }
function WasmDepthToLoop(blk: Integer): Integer;
begin
  WasmDepthToLoop := WasmBlockCount - 1 - blk;
end;

{ One further out than the loop. Branching here leaves the dispatch entirely
  and lands on the instruction after the outer block's `end` — which is where
  the epilogue starts, so `br $exit` IS an early return. }
function WasmDepthToExit(blk: Integer): Integer;
begin
  WasmDepthToExit := WasmBlockCount - blk;
end;

{ Resolve a jump target to its basic block, refusing a label this body never
  defined rather than reading a stale entry. }
function WasmTargetBlock(lbl: Integer): Integer;
begin
  WasmTargetBlock := 0;
  if (lbl < 0) or (lbl >= MAX_IR) or (WasmLabelStamp[lbl] <> WasmBodySerial) then
  begin
    WasmUnsupported('jump to label ' + WasmIntStr(lbl)
                    + ', which this body does not define');
    Exit;
  end;
  WasmTargetBlock := WasmLabelBlock[lbl];
end;

procedure WasmEmitJump(node, blk: Integer);
begin
  WasmI32Const(WasmTargetBlock(IRA[node]));
  if WasmBodyBroken then Exit;
  WasmLocalSet(WasmLocalPc);
  WasmBr(WasmDepthToLoop(blk));
end;

procedure WasmEmitJumpIfFalse(node, blk: Integer);
var ctk: TTypeKind; cvt: Byte;
begin
  WasmI32Const(WasmTargetBlock(IRA[node]));
  if WasmBodyBroken then Exit;
  WasmLocalSet(WasmLocalPc);
  { The condition is tested AT ITS OWN WIDTH. Coercing it to i32 first would be
    an i32.wrap_i64, which discards the high half — riscv32 shipped exactly
    that bug (bug-32bit-truthiness-high-half, ir_codegen_riscv32.inc:3673): a
    nonzero Int64 whose low word happens to be zero tests as FALSE. wasm has
    i64.eqz, so the full-width test is one instruction and the narrowing never
    has to happen. }
  ctk := WasmEmitNode(IRB[node]);
  if WasmBodyBroken then Exit;
  if not WasmScalarType(ctk, cvt) then
  begin
    WasmUnsupported('condition of type ' + WasmIntStr(Ord(ctk)));
    Exit;
  end;
  if cvt = WT_I64 then WasmOp($50, 'i64.eqz')
  else if cvt = WT_I32 then WasmOp($45, 'i32.eqz')
  else
  begin
    WasmUnsupported('float condition');
    Exit;
  end;
  { eqz answered "the condition was false", which is precisely when this jump
    is taken. }
  WasmBrIf(WasmDepthToLoop(blk));
end;

{ ===== exceptions =====

  THE WHOLE MECHANISM, because it is small and the reason it is small is the
  interesting part.

  Every other backend reaches a landing pad through an ADDRESS: a setjmp buffer
  holds one, longjmp restores the stack and jumps to it, and a raise stub walks
  the handler chain doing that. A wasm module has no code addresses at all —
  calls are function indices, branches are structural — so none of that is
  expressible, and `exception_emit.inc`'s wasm arm emits no runtime bytes.

  What replaces it is two questions asked at two places:

    at a RAISE, and after every CALL that could have raised:
        is the innermost handler frame MINE?
          yes -> $pc := its pad, br $dispatch          (handled here)
          no  -> set $exc_pending, restore $sp, return (propagate outward)

  "Mine" is `[$exc_top + FP] = $fp`, which is why a handler frame carries the
  $fp that pushed it. The chain itself is the SAME runtime chain every register
  backend keeps, in the same shared BSS slot (BSS_EXC_TOP), so nothing new is
  stored and nothing in a shared file changed to store it.

  The pad is a BASIC BLOCK NUMBER, and branching to a computed one costs
  exactly what branching to a constant one costs, because $pc is already a
  variable feeding a br_table. That is a property of the dispatch LAYOUT rather
  than anything about exceptions — any control transfer whose target is data
  instead of syntax is free here — and it is what makes the dynamic pad
  affordable. The prototype assumed static pads; against the real IR they are
  not reconstructible, because a `try` emits TWO EXC_LEAVEs per EXC_ENTER and
  `EXC_LEAVE n` pops several frames at a point the lexically following code is
  still inside. A linear scan derives the wrong nesting SILENTLY.
  devdocs/dev/wasm/phase5-exceptions.md carries the worked case.

  NOT IMPLEMENTED and filed rather than hidden: a proc CLEANUP frame, which is
  what releases managed locals when an exception unwinds THROUGH a frame rather
  than being caught in it. wasm32 sits outside TargetHasProcCleanupFrame
  exactly as xtensa does, deliberately in xtensa's case and now in ours —
  bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa. An unwind leak
  prints nothing, which is why it is a ticket and not a comment. }

{ The pending flag. A wasm GLOBAL rather than a BSS word: it is read after every
  call in a program that uses exceptions, so it is the one piece of this that is
  hot, and a global is a register where a BSS word is a load. Allocated on FIRST
  USE so that a program containing no `raise` emits a module with no trace of
  any of this — which is also what keeps every pre-existing slice byte-for-byte
  what it was. }
function WasmExcPendGlobal: Integer;
begin
  if WasmGExcPend < 0 then
    WasmGExcPend := WasmAddGlobal('exc_pending', WT_I32, True, 0);
  WasmExcPendGlobal := WasmGExcPend;
end;

{ The address of one of the compiler-owned status words. They are 8 bytes wide
  because the shared allocator sizes them for a 64-bit target; here they are
  WRITTEN as i64 (so the high half is never stale garbage from a previous
  value) and READ as i32 (because that is the width of everything on this
  target). Writing i32 and reading i32 would work today and would leave a
  half-initialised word for the first 64-bit reader to find. }
procedure WasmBssAddr(off: Integer);
begin
  WasmI32Const(WASM_BSS_BASE + off);
end;

procedure WasmBssLoad(off: Integer);
begin
  WasmBssAddr(off);
  WasmMemOp($28, 'i32.load', 2, 0);
end;

{ value (i32) is already on the stack -> store it into the status word }
procedure WasmBssStoreFromStack(off: Integer; scratch: Integer);
begin
  WasmLocalSet(scratch);
  WasmBssAddr(off);
  WasmLocalGet(scratch);
  WasmOp($AD, 'i64.extend_i32_u');
  WasmMemOp($37, 'i64.store', 2, 0);
end;

procedure WasmBssStoreConst(off: Integer; v: Integer);
begin
  WasmBssAddr(off);
  WasmI64Const(v);
  WasmMemOp($37, 'i64.store', 2, 0);
end;

{ The address of this body's handler frame number k. }
procedure WasmExcFrameAddr(k: Integer);
begin
  WasmLocalGet(WasmLocalFp);
  if k > 0 then
  begin
    WasmI32Const(k * WASM_EXCF_SIZE);
    WasmOp($6A, 'i32.add');
  end;
end;

function WasmExcTop: Integer;
begin
  if WasmExcTopLocal < 0 then
    WasmExcTopLocal := WasmAddLocal(WT_I32, 'exctop');
  WasmExcTop := WasmExcTopLocal;
end;

{ A zero of the body's result type, for the propagate path's `return`. The
  value is DEAD — the caller spills it and then branches on the pending flag
  before ever reading it — but wasm has no notion of a dead value, so a
  function with a result must return one on every path. Floats go through
  reinterpret because this encoder has no f32/f64 const emitter, the same route
  IR_CONST_INT takes for a float literal. }
procedure WasmPushZeroOf(vt: Byte);
begin
  if vt = WT_I64 then WasmI64Const(0)
  else if vt = WT_F64 then
  begin
    WasmI64Const(0);
    WasmOp($BF, 'f64.reinterpret_i64');
  end
  else if vt = WT_F32 then
  begin
    WasmI32Const(0);
    WasmOp($BE, 'f32.reinterpret_i32');
  end
  else
    WasmI32Const(0);
end;

{ Leave this invocation with the exception still armed: restore $sp, produce a
  dead result if the signature needs one, and `return`.

  `return` rather than a branch to the epilogue, and that choice is load-bearing
  in a way worth stating: branching to the epilogue would need the dispatch
  blocks to exist, so EVERY body containing a call would have to grow a
  br_table it otherwise does not need. `return` restores nothing on its own —
  hence the explicit $sp write here, which is the same two instructions the
  epilogue does. }
procedure WasmEmitExcPropagate;
begin
  WasmLocalGet(WasmLocalFp);
  WasmI32Const(WasmCurFrame);
  WasmOp($6A, 'i32.add');
  WasmGlobalSet(WasmGSp);
  if WasmCurNRes = 1 then WasmPushZeroOf(WasmCurResVt);
  WasmReturn;
end;

{ Take the exception somewhere: into this body's innermost handler if the chain
  head belongs to this invocation, otherwise out of the function.

  `extra` is how many wasm blocks deep the caller has opened beyond the basic
  block's own nesting — the `if` of a post-call check, for instance — because a
  `br` depth counts wasm's structural nesting and not the IR's.

  The `[top + FP]` load happens even when top is 0, reading address 8. That is
  a legal read of a mapped page (linear memory starts at 0 and $sp starts at
  65536), the AND discards it, and it costs one load instead of a branch. Note
  the contrast with the frozen-string guard, where the equivalent trick would
  read `handle - 8` at 0xFFFFFFF8 and trap: whether an eager load is free
  depends on the ADDRESS it computes, not on the shape of the condition. }
procedure WasmEmitUnwind(blk, extra: Integer);
begin
  if WasmExcHasHandler then
  begin
    WasmBssLoad(BSS_EXC_TOP);
    WasmLocalTee(WasmExcTop);
    WasmI32Const(0);
    WasmOp($47, 'i32.ne');
    WasmLocalGet(WasmExcTop);
    WasmMemOp($28, 'i32.load', 2, WASM_EXCF_FP);
    WasmLocalGet(WasmLocalFp);
    WasmOp($46, 'i32.eq');
    WasmOp($71, 'i32.and');
    WasmIf(WT_VOID);
      { This frame owns it, so it is no longer pending — it is being handled.
        The OBJECT stays in BSS_EXC_OBJ, which is what a bare `raise;` re-arms
        from and what IR_EXC_STORE binds to `on E: T do`. }
      WasmI32Const(0);
      WasmGlobalSet(WasmExcPendGlobal);
      WasmLocalGet(WasmExcTop);
      WasmMemOp($28, 'i32.load', 2, WASM_EXCF_PAD);
      WasmLocalSet(WasmLocalPc);
      WasmBr(WasmDepthToLoop(blk) + extra + 1);
    WasmEnd;
  end;
  WasmEmitExcPropagate;
end;

{ After a call. Emitted only when the PROGRAM uses exceptions at all — if no
  `raise` exists anywhere, no call can raise, and every module that existed
  before this phase is unchanged byte for byte. ExceptionUsed is the frontend's
  own flag, set by EnableExceptionRuntime, so this is the same question the
  shared code already asked rather than a second answer to it. }
procedure WasmEmitExcCheck;
begin
  if not ExceptionUsed then Exit;
  if WasmBodyBroken then Exit;
  WasmGlobalGet(WasmExcPendGlobal);
  WasmIf(WT_VOID);
    WasmEmitUnwind(WasmCurBlk, 1);
  WasmEnd;
end;

{ Index into WasmCRLocal. The four wasm value types are $7F..$7C, descending,
  so this is a subtraction rather than a case. }
function WasmVtIndex(vt: Byte): Integer;
begin
  if (vt <= WT_I32) and (vt >= WT_F64) then WasmVtIndex := WT_I32 - vt
  else WasmVtIndex := 0;
end;

{ Everything a call site owes the exception mechanism.

  The RESULT IS SPILLED FIRST, and that is the rule the prototype found by
  getting it wrong: the check ends in a `br` on the unwind path, and a branch
  cannot carry a half-built expression with it. Landing the result in a local
  before the check makes the check's control flow independent of whatever
  expression the call sits inside.

  An IMPORT is exempt. A wasm import is a host function; it cannot set our
  pending flag, because the flag is a global of this module and the host has no
  Pascal `raise`. Checking after one would be a check that can never fire. }
procedure WasmEmitPostCall(spillVt: Byte; hasResult: Boolean);
var k: Integer;
begin
  if not ExceptionUsed then Exit;
  if WasmBodyBroken then Exit;
  if hasResult then
  begin
    k := WasmVtIndex(spillVt);
    if WasmCRLocal[k] < 0 then
      WasmCRLocal[k] := WasmAddLocal(spillVt, 'callres');
    WasmLocalSet(WasmCRLocal[k]);
    WasmEmitExcCheck;
    WasmLocalGet(WasmCRLocal[k]);
  end
  else
    WasmEmitExcCheck;
end;

{ `try` — push a handler frame. No setjmp, no branch: entering the pad is the
  raise site's job, not this one's. }
procedure WasmEmitExcEnter(node: Integer);
var k, pad: Integer;
begin
  k := WasmExcSlot[node];
  if (k < 0) or (k >= WasmExcSites) then
  begin
    WasmUnsupported('exception frame slot out of range — the pre-pass and the '
                    + 'emit pass disagree about this body');
    Exit;
  end;
  pad := WasmTargetBlock(IRA[node]);
  if WasmBodyBroken then Exit;

  WasmExcFrameAddr(k);
  WasmBssLoad(BSS_EXC_TOP);
  WasmMemOp($36, 'i32.store', 2, WASM_EXCF_PREV);

  WasmExcFrameAddr(k);
  WasmI32Const(pad);
  WasmMemOp($36, 'i32.store', 2, WASM_EXCF_PAD);

  WasmExcFrameAddr(k);
  WasmLocalGet(WasmLocalFp);
  WasmMemOp($36, 'i32.store', 2, WASM_EXCF_FP);

  WasmBssAddr(BSS_EXC_TOP);
  WasmExcFrameAddr(k);
  WasmOp($AD, 'i64.extend_i32_u');
  WasmMemOp($37, 'i64.store', 2, 0);
end;

{ Pop n frames. n is a compile-time constant and is small — it is the nesting
  depth a `break` or `Exit` jumps out of — so it is unrolled rather than
  looped. }
procedure WasmEmitExcLeave(node: Integer);
var i, n: Integer;
begin
  n := IRA[node];
  if n < 1 then n := 1;
  for i := 1 to n do
  begin
    WasmBssAddr(BSS_EXC_TOP);
    WasmBssLoad(BSS_EXC_TOP);
    WasmMemOp($28, 'i32.load', 2, WASM_EXCF_PREV);
    WasmOp($AD, 'i64.extend_i32_u');
    WasmMemOp($37, 'i64.store', 2, 0);
  end;
end;

{ `raise E` — arm the status words and unwind. A bare `raise;` inside a handler
  arrives with IRA = -1 and re-arms from whatever is still in the slots, which
  is the same contract every other backend reads. }
procedure WasmEmitRaise(node, blk: Integer);
begin
  if IRA[node] <> -1 then
  begin
    WasmEmitValueAs(IRA[node], WT_I32, 'the raised value');
    if WasmBodyBroken then Exit;
    WasmBssStoreFromStack(BSS_EXC_OBJ, WasmExcTop);
    WasmBssStoreConst(BSS_EXC_CLS, Integer(IRIVal[node]));
  end;
  WasmI32Const(1);
  WasmGlobalSet(WasmExcPendGlobal);
  WasmEmitUnwind(blk, 0);
end;

{ Bind a compiler-owned status word to a Pascal variable — `on E: T do` reads
  the object, and the signal family reads four more. One load, a different
  offset; IRExcStoreSlot picks which, and it is shared, so the signal three
  cost this backend nothing. }
procedure WasmEmitExcStore(node: Integer);
var si: Integer; vt: Byte;
begin
  si := IRA[node];
  if (si < 0) or not WasmSlotType(si, vt) then Exit;
  WasmLValueAddr(si);
  WasmBssLoad(IRExcStoreSlot(node));
  if vt = WT_I64 then WasmOp($AD, 'i64.extend_i32_u');
  WasmTypeStore(Syms[si].TypeKind, vt);
end;

procedure WasmEmitExcClear;
begin
  WasmBssStoreConst(BSS_EXC_OBJ, 0);
  WasmBssStoreConst(BSS_EXC_CLS, 0);
  WasmBssStoreConst(BSS_EXC_ADDR, 0);
end;

{ A handler arm's class test. MATCH jumps to the NEXT arm when the class does
  not match; MATCH_HIT jumps to the BODY when it does — two opcodes for one
  comparison with opposite senses, and the sense is the only difference. }
procedure WasmEmitExcMatch(node, blk: Integer; hit: Boolean);
begin
  WasmI32Const(WasmTargetBlock(IRA[node]));
  if WasmBodyBroken then Exit;
  WasmLocalSet(WasmLocalPc);
  WasmBssLoad(BSS_EXC_CLS);
  WasmI32Const(Integer(IRIVal[node]));
  if hit then WasmOp($46, 'i32.eq') else WasmOp($47, 'i32.ne');
  WasmBrIf(WasmDepthToLoop(blk));
end;

{ IR_TERMINATE is two statements wearing one opcode: `Halt(n)` when IRIVal is
  AN_HALT, and an early `Exit` otherwise (ir_codegen_riscv32.inc's arm makes the
  same split). Exit is a branch out of the dispatch to the epilogue, which is
  what every register backend spells as "jump to the procedure epilogue". Halt
  is a process-level operation with no wasm instruction at all — it needs WASI's
  proc_exit import, which arrived in Phase 6 — so it is refused by name rather than
  quietly returning, which would turn `Halt(1)` into success. }
procedure WasmEmitTerminate(node, blk: Integer);
begin
  if IRIVal[node] = AN_HALT then
  begin
    { Halt(n) must EXIT WITH n — the failure this arm exists to avoid is
      `Halt(7)` returning 0, which is a program's failure signal vanishing
      with no diagnostic (bug-a-halt-n-exits-zero-on-hosted-riscv32, the same
      mistake on a different target).

      Declared by the backend rather than named by an `external` declaration,
      because `Halt` is an IR op: there is no Pascal call site to hang the
      declaration on, and the RTL's PXXExitProcess reaches it through the same
      IR op rather than through a routine of its own.

      `unreachable` follows because proc_exit does not return. wasm does not
      know that — its type is (i32) -> () — so without it the validator goes on
      checking a path that cannot be taken, and a `Halt` in a function with a
      result fails validation for the missing value. `unreachable` is
      polymorphic and says exactly what is true here. }
    if IRA[node] <> -1 then
      WasmEmitValueAs(IRA[node], WT_I32, 'the Halt exit code')
    else
      WasmI32Const(0);
    WasmCallImport(WasmHostImport('wasi_snapshot_preview1', 'proc_exit',
                                  [WT_I32], []), 'proc_exit');
    WasmBodyUnreachable;
    Exit;
  end;
  WasmBr(WasmDepthToExit(blk));
end;

{ ===== write / writeln =====

  wasm has no syscall instruction, so there is no inline write to emit. That
  turns out to cost nothing, because the RTL already contains a target-neutral
  console-output family — PXXWriteNL / PXXWriteDecW / PXXWriteCharW /
  PXXWriteBoolW / PXXWriteStrMW / PXXWriteFrozenW / PXXWriteCStr / PXXWritePad
  in builtinheap.pas — written when hosted riscv32 hit the same wall, with the
  comment "any backend could adopt them". This one does, unchanged.

  They format into a local buffer and emit ONE PXXSysWrite, and they contain no
  `write` STATEMENT, which is what stops this arm recursing into itself.

  What they do NOT solve is the last inch: PXXSysWrite is an ifdef chain over
  __pxxrawsyscall with an arm per target and NO CPU_WASM32 arm, so on this
  target it returns 0 having written nothing. That is a shared file; see
  bug-a-pxxsyswrite-has-no-wasm32-arm. Until it lands, `writeln` here lowers
  correctly and prints nothing — which is why the slice asserts the silence
  rather than the output, and will fail the day it stops being silent.

  Argument types come from the CALLEE's declared parameters rather than being
  assumed, exactly as WasmEmitCall does it: a helper parameter declared
  NativeInt is i32 on wasm32 and i64 on a 64-bit target, and assuming either is
  how an i32/i64 mismatch gets in without a diagnostic. }

function WasmWriteHelper(const nm: AnsiString): Integer;
begin
  WasmWriteHelper := FindProc(nm);
  if WasmWriteHelper < 0 then
    WasmUnsupported('RTL helper ' + nm + ' not found');
end;

{ Push a compile-time integer as the callee's parameter i wants it. }
procedure WasmWriteConstArg(p, i: Integer; v: Int64);
var vt: Byte;
begin
  if not WasmParamValType(p, i, vt) then
  begin
    WasmUnsupported('write: parameter ' + WasmIntStr(i) + ' of '
                    + Procs[p].Name + ' has no wasm value type');
    Exit;
  end;
  if vt = WT_I64 then WasmI64Const(v) else WasmI32Const(v);
end;

{ Push an IR value as the callee's parameter i wants it. }
procedure WasmWriteValueArg(p, i, valNode: Integer);
var vt: Byte;
begin
  if not WasmParamValType(p, i, vt) then
  begin
    WasmUnsupported('write: parameter ' + WasmIntStr(i) + ' of '
                    + Procs[p].Name + ' has no wasm value type');
    Exit;
  end;
  WasmEmitValueAs(valNode, vt, 'write argument to ' + Procs[p].Name);
end;

procedure WasmEmitWrite(node: Integer);
var
  valNode, wid, decs, si, hp, scFrac, scExp: Integer;
  sVal: AnsiString;
  tk: TTypeKind;
begin
  if IRKind[node] = IR_WRITELN then
  begin
    hp := WasmWriteHelper('PXXWriteNL');
    if hp < 0 then Exit;
    WasmCall(WasmSlotForProc(hp), 'PXXWriteNL');
    Exit;
  end;

  valNode := IRA[node];
  wid  := IRB[node];      { field width, 0 = none }
  decs := IRC[node];      { decimals; -1 none, -2 native float, -3 PChar }

  { A literal is already a frozen string in Data[] — an 8-byte length prefix
    followed by the chars — which is precisely PXXWriteFrozenW's argument, so
    the padding and the write are one call rather than the two the register
    backends need. }
  if IRKind[valNode] = IR_CONST_STR then
  begin
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    si := InternStr(sVal);
    hp := WasmWriteHelper('PXXWriteFrozenW');
    if hp < 0 then Exit;
    WasmDataAddr(Strs[si].Offset);
    WasmWriteConstArg(hp, 1, wid);
    WasmCall(WasmSlotForProc(hp), 'PXXWriteFrozenW');
    Exit;
  end;

  if decs = -3 then
  begin
    hp := WasmWriteHelper('PXXWriteCStr');
    if hp < 0 then Exit;
    WasmWriteValueArg(hp, 0, valNode);
    WasmCall(WasmSlotForProc(hp), 'PXXWriteCStr');
    Exit;
  end;

  tk := IntToTypeKind(IRTk[node]);

  if TypeIsFloat(tk) then
  begin
    { The float writers take the ADDRESS of a double, so the value has to be
      spilled. Not yet done here — a shadow-stack temp of its own is a small
      job and it is not what the milestone is about. Reported, not skipped. }
    WasmUnsupported('write of a float — the RTL writers take a double by '
                    + 'address and this arm does not spill one yet');
    Exit;
  end;

  if tk = tyVariant then
  begin
    WasmUnsupported('write of a variant — needs the slot ADDRESS, not its '
                    + 'value');
    Exit;
  end;

  if tk = tyChar then hp := WasmWriteHelper('PXXWriteCharW')
  else if tk = tyBoolean then hp := WasmWriteHelper('PXXWriteBoolW')
  else if tk = tyAnsiString then hp := WasmWriteHelper('PXXWriteStrMW')
  else if TypeIsFrozenString(tk) then hp := WasmWriteHelper('PXXWriteFrozenW')
  else if TypeIsOrdinal(tk) or (tk = tyUnknown) then
    hp := WasmWriteHelper('PXXWriteDecW')
  else
  begin
    WasmUnsupported('write of type kind ' + WasmIntStr(IRTk[node])
                    + ' has no RTL helper on this target');
    Exit;
  end;
  if hp < 0 then Exit;

  WasmWriteValueArg(hp, 0, valNode);
  if Procs[hp].Name = 'PXXWriteDecW' then
  begin
    { (v: Int64; uns: NativeInt; wid: NativeInt) — `uns` decides how the 64-bit
      pattern is read, and it must follow the value's OWN signedness, not the
      helper parameter's. tyUnknown is treated as signed, as everywhere else. }
    if (tk <> tyUnknown) and not TypeSigned(tk) then
      WasmWriteConstArg(hp, 1, 1)
    else
      WasmWriteConstArg(hp, 1, 0);
    WasmWriteConstArg(hp, 2, wid);
  end
  else
    WasmWriteConstArg(hp, 1, wid);
  if WasmBodyBroken then Exit;
  WasmCall(WasmSlotForProc(hp), Procs[hp].Name);
end;

{ Whole-record copy: PXXMemMove(dest, src, count) — the same RTL routine every
  other backend calls, and here without any of the register juggling, because
  wasm evaluates arguments straight onto the operand stack in order.

  This is the UNMANAGED arm only. A record with ARC fields lowers to
  IR_COPY_REC_MANAGED, a different op, which stays refused by name until this
  target has ARC — refusing it is correct, because a plain byte move of a
  managed record is a missed retain, i.e. a use-after-free later and far away. }
procedure WasmEmitCopyRec(node: Integer);
var mv: Integer;
begin
  mv := WasmWriteHelper('PXXMemMove');
  if mv < 0 then Exit;
  WasmWriteValueArg(mv, 0, IRA[node]);            { dest }
  WasmWriteValueArg(mv, 1, IRB[node]);            { src }
  WasmWriteConstArg(mv, 2, IRIVal[node]);         { count }
  if WasmBodyBroken then Exit;
  WasmCall(WasmSlotForProc(mv), 'PXXMemMove');
end;

{ Zero a block: destination address in IRA, byte count in IRIVal. Calls the
  same RTL routine the other backends use, for the same reason WasmEmitCopyRec
  calls PXXMemMove — the arguments go straight onto the operand stack in order.

  x86-64 carries a second arm here: when the node names a record with managed
  fields it releases those fields before zeroing, because zeroing an ARC field
  in place drops a reference without decrementing it. All 14 sites that build
  this node today pass REC_NONE, so that arm is not reachable from the current
  IR — but the guard is kept rather than assumed away. It costs one comparison,
  and "unreachable by inspection" is exactly the kind of claim that stops being
  true without anything going red. If it ever fires, the refusal names the real
  missing piece instead of silently leaking. }
procedure WasmEmitDefaultMem(node: Integer);
var mz: Integer;
begin
  if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
  begin
    WasmUnsupported('zeroing a record with managed fields — the ARC fields '
                    + 'must be released before the bytes go away');
    Exit;
  end;
  mz := WasmWriteHelper('PXXMemZero');
  if mz < 0 then Exit;
  WasmWriteValueArg(mz, 0, IRA[node]);        { dest }
  WasmWriteConstArg(mz, 1, IRIVal[node]);     { count }
  if WasmBodyBroken then Exit;
  WasmCall(WasmSlotForProc(mz), 'PXXMemZero');
end;

{ ===== frozen strings =====

  A `string[N]` / ShortString is not a VALUE on this target, it is a BUFFER: an
  8-byte length prefix (low word the length, high word zero) followed by the
  chars. So `s := 'hello'` cannot go through the scalar store path, which asks
  the slot for its wasm value type and correctly answers that it has none.

  Three source shapes, the same three every register backend handles:

      Char         length 1, the ordinal at +8
      AnsiString   a HANDLE: length at [h-8], chars AT h; nil means empty
      frozen       length at [src], chars at src+8

  and one rule they share: the length is CLAMPED to the destination's capacity,
  because `string[N]` TRUNCATES. That rule is not decoration — the register
  backends learned it as bug-pascal-shortstring-no-truncation-buffer-overrun,
  where the generic word store dropped the source ADDRESS into the field.

  Everything goes through locals rather than the operand stack: the destination
  and the source are each needed twice and wasm yields a value once. Fresh
  locals per SITE, for the reason WasmEmitGetMem allocates fresh ones — a
  source expression may itself contain a store.

  The nil-handle guard is a real `if`, not a `select`: select evaluates both
  arms, and the false arm here is a load from `handle - 8`, which for a nil
  handle is address 0xFFFFFFF8 and traps. This is the one place so far where
  wasm's eager `select` is the wrong tool, and it is worth naming because
  `select` is otherwise the cheaper answer to every two-way choice here. }
procedure WasmEmitFrozenStore(dstIsSym: Boolean; dstRef, valNode, cap: Integer);
var lDst, lSrc, lLen, mv: Integer; stk: TTypeKind; savedLVW: Boolean;
begin
  if cap <= 0 then cap := DEFAULT_STR_CAP;
  mv := WasmWriteHelper('PXXMemMove');
  if mv < 0 then Exit;
  stk := WasmStrTypeOf(valNode);
  lDst := WasmAddLocal(WT_I32, 'fzdst');
  lSrc := WasmAddLocal(WT_I32, 'fzsrc');
  lLen := WasmAddLocal(WT_I32, 'fzlen');

  { VALUE first, then the destination — the order the register backends use
    (they evaluate the value and spill it), so a side effect on either side
    sees the same world here as there. }
  WasmEmitValueAs(valNode, WT_I32, 'value assigned to a frozen string');
  WasmLocalSet(lSrc);
  if dstIsSym then WasmLValueAddr(dstRef)
  else
  begin
    savedLVW := InLValueWrite;
    InLValueWrite := True;
    WasmEmitValueAs(dstRef, WT_I32, 'address of a frozen string store');
    InLValueWrite := savedLVW;
  end;
  WasmLocalSet(lDst);
  if WasmBodyBroken then Exit;

  if stk = tyChar then
  begin
    { One i64.store writes BOTH words of the prefix, which is what keeps the
      high half zero without a second instruction. }
    WasmLocalGet(lDst); WasmI64Const(1);
    WasmMemOp($37, 'i64.store', 2, 0);
    WasmLocalGet(lDst); WasmLocalGet(lSrc);
    WasmMemOp($3A, 'i32.store8', 0, 8);
    Exit;
  end;

  if stk = tyAnsiString then
  begin
    WasmI32Const(0);
    WasmLocalSet(lLen);
    WasmLocalGet(lSrc);
    WasmIf(WT_VOID);
      WasmLocalGet(lSrc); WasmI32Const(8); WasmOp($6B, 'i32.sub');
      WasmMemOp($28, 'i32.load', 2, 0);
      WasmLocalSet(lLen);
    WasmEnd;
    { chars are AT the handle — no +8 }
  end
  else
  begin
    WasmLocalGet(lSrc);
    WasmMemOp($28, 'i32.load', 2, 0);
    WasmLocalSet(lLen);
    WasmLocalGet(lSrc); WasmI32Const(8); WasmOp($6A, 'i32.add');
    WasmLocalSet(lSrc);
  end;

  { len := min(len, cap). Both arms are plain values here, so select is right. }
  WasmI32Const(cap);
  WasmLocalGet(lLen);
  WasmLocalGet(lLen); WasmI32Const(cap); WasmOp($4A, 'i32.gt_s');
  WasmOp($1B, 'select');
  WasmLocalSet(lLen);

  WasmLocalGet(lDst);
  WasmLocalGet(lLen); WasmOp($AD, 'i64.extend_i32_u');
  WasmMemOp($37, 'i64.store', 2, 0);

  { PXXMemMove(dst + 8, chars, len) }
  WasmLocalGet(lDst); WasmI32Const(8); WasmOp($6A, 'i32.add');
  WasmLocalGet(lSrc);
  WasmLocalGet(lLen);
  WasmCall(WasmSlotForProc(mv), 'PXXMemMove');
end;

{ ===== managed (reference-counted) strings =====

  A managed string's slot holds a HANDLE — the address of the char data inside
  a heap block whose header sits below it: [kind:8][refcount:8][length:8][data].
  Reading one is a plain i32.load and has been supported since Phase 2, because
  a read takes no ownership. Writing one is not a store at all; it is three
  things in a fixed order:

    1. MATERIALISE a handle the destination will own (+1 held for the slot),
    2. PUBLISH it into the slot,
    3. RELEASE whatever the slot held before.

  The order is the aliasing rule, not a style choice: `s := s` and `s := t`
  where t aliases s both pass through here, and releasing first would free the
  block that step 1 is about to hand back. Every register backend does the same
  three steps in the same order (ir_codegen.inc:4988-5075); this is that
  sequence expressed in wasm, not a second policy.

  The scratch used by the Char shape lives just above the handler frames at the
  bottom of the frame, for the same reason those do: $sp moves during the call
  that reads it, so a byte written below $sp would be inside the callee. }

{ Scratch for spilling a Char before something can point at it — 16 bytes
  pushed on the SHADOW STACK, not reserved in the frame.

  The frame is the obvious place and it is wrong, measured: one reserved area
  per body means one address per site, and string operands NEST. `a + (b + s)`
  with two Char operands put the inner `b` at the same address as the outer
  `a`, and the outer's characters changed under it — the module validated, ran,
  and printed `BBS` for `ABS`. That is the exact failure class this backend
  exists to make impossible, arrived at by reserving storage per BODY for a
  thing whose lifetime is per EXPRESSION.

  A shadow-stack push nests by construction, which is why every register
  backend spills its Char operand onto the machine stack (the `charStackOff`
  parameter of EmitA64StringParts is an offset into exactly such a push). $sp
  is restored by the caller of this, and also by the exception unwind path,
  which restores it from $fp.

  16 rather than 8 so a callee's frame stays 16-aligned below ours. }
{ Slot `k` at the current nesting depth, allocated on first use. }
function WasmStrSlot(k: Integer): Integer;
begin
  if WasmStrPool[WasmStrDepth][k] < 0 then
    WasmStrPool[WasmStrDepth][k] :=
      WasmAddLocal(WT_I32, 'str' + WasmIntStr(WasmStrDepth)
                           + '_' + WasmIntStr(k));
  WasmStrSlot := WasmStrPool[WasmStrDepth][k];
end;

function WasmStrScratchPush(slot: Integer): Integer;
begin
  WasmStrScratchPush := slot;
  WasmGlobalGet(WasmGSp);
  WasmI32Const(16);
  WasmOp($6B, 'i32.sub');
  WasmLocalTee(WasmStrScratchPush);
  WasmGlobalSet(WasmGSp);
end;

procedure WasmStrScratchPop(scr: Integer);
begin
  WasmLocalGet(scr);
  WasmI32Const(16);
  WasmOp($6A, 'i32.add');
  WasmGlobalSet(WasmGSp);
end;

{ Leave on the stack an i32 handle whose +1 belongs to the caller of this
  routine. False means nothing was pushed and the body is already marked
  unsupported.

  The one discrimination worth naming is the last arm. A concat result or a
  function result arrives ALREADY owned — the callee built it with refcount 1
  and handed the reference over — so retaining it again leaks the block. The
  predicate that answers this is IRNodeOwnsManagedStr, shared with every
  register backend and forwarded ahead of this file in compiler.pas precisely
  so there is one answer rather than five. }
function WasmEmitOwnedStr(valNode: Integer): Boolean;
var sVal: AnsiString; si, hp, lv: Integer; stk: TTypeKind;
begin
  WasmEmitOwnedStr := False;
  hp := WasmWriteHelper('PXXStrFromLit');
  if hp < 0 then Exit;

  if IRKind[valNode] = IR_CONST_STR then
  begin
    { The literal's blob is a FROZEN string — [len:8][chars][nul] — so the
      chars start at +8 and the length is known here without a load. }
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    si := InternStr(sVal);
    WasmI32Const(Length(sVal));
    WasmDataAddr(Strs[si].Offset);
    WasmI32Const(8); WasmOp($6A, 'i32.add');
    WasmCall(WasmSlotForProc(hp), 'PXXStrFromLit');
    WasmEmitOwnedStr := True;
    Exit;
  end;

  stk := WasmStrTypeOf(valNode);

  if stk = tyChar then
  begin
    { The same shadow-stack push the binop path uses, for the same reason and
      by the same mechanism — this site cannot nest (a store's value is fully
      materialised before the slot is touched), but two spill mechanisms for
      one need is how the two drift. }
    lv := WasmStrScratchPush(WasmStrSlot(0));
    WasmLocalGet(lv);
    WasmEmitValueAs(valNode, WT_I32, 'character assigned to a managed string');
    if WasmBodyBroken then Exit;
    WasmMemOp($3A, 'i32.store8', 0, 0);
    WasmI32Const(1);
    WasmLocalGet(lv);
    WasmCall(WasmSlotForProc(hp), 'PXXStrFromLit');
    WasmStrScratchPop(lv);
    WasmEmitOwnedStr := True;
    Exit;
  end;

  if TypeIsFrozenString(stk) then
  begin
    { A frozen string EVALUATES TO ITS ADDRESS (WasmEmitValueAs), and that
      address is the [len:8][chars] blob — the same shape as a literal's, so
      the length comes from memory and the chars from +8. }
    lv := WasmStrLocZ;
    WasmEmitValueAs(valNode, WT_I32, 'frozen string assigned to a managed string');
    if WasmBodyBroken then Exit;
    WasmLocalSet(lv);
    WasmLocalGet(lv); WasmMemOp($28, 'i32.load', 2, 0);
    WasmLocalGet(lv); WasmI32Const(8); WasmOp($6A, 'i32.add');
    WasmCall(WasmSlotForProc(hp), 'PXXStrFromLit');
    WasmEmitOwnedStr := True;
    Exit;
  end;

  if stk = tyAnsiString then
  begin
    lv := WasmStrLocZ;
    WasmEmitValueAs(valNode, WT_I32, 'managed string assigned to a managed string');
    if WasmBodyBroken then Exit;
    WasmLocalSet(lv);
    if not IRNodeOwnsManagedStr(valNode) then
    begin
      hp := WasmWriteHelper('PXXStrIncRef');
      if hp < 0 then Exit;
      WasmLocalGet(lv);
      WasmCall(WasmSlotForProc(hp), 'PXXStrIncRef');
    end;
    WasmLocalGet(lv);
    WasmEmitOwnedStr := True;
    Exit;
  end;

  WasmUnsupported('value of type ' + WasmTypeKindName(stk)
                  + ' assigned to a managed string');
end;

{ materialise -> publish -> release-old. dstIsSym picks how the SLOT's address
  is reached: through the symbol (which routes by-ref parameters to the
  caller's slot via the ABI oracle, so `procedure P(var s: string)` publishes
  where it should) or through an already-lowered address expression. }
{ `b := a` on a DYNAMIC ARRAY. Pointer-sized, so the scalar path compiles it
  and the program even behaves — aliasing is correct, because a dynamic array
  IS a reference type and copying the handle is the semantics. What the scalar
  path omits is the refcount, and that is invisible in a diff: measured as an
  arena advancing 10512 bytes per 1000 iterations where the native build was
  flat at 1032, and at 9000 iterations the module exhausted linear memory and
  trapped. Nothing in the output ever looked wrong.

  Retain-then-publish-then-release, and the ORDER is the whole of it: releasing
  first would free the block `a` still points at when a and b are already the
  same handle (`a := a`), and retaining after publishing would lose the old
  handle. This is the shape riscv32's IR_STORE_SYM dyn arm uses and the reason
  it gives (bug-a-no-dyn-array-scope-exit-release-on-four-backends).

  THE RETAIN IS SKIPPED for a fresh function result, which arrives already
  carrying its +1 — retaining it too would pin the block forever. That is the
  same `IRKind = IR_CALL and IRA >= 0` test riscv32 makes; `IRA >= 0` is what
  separates a real call from a builtin, whose result is not a new reference. }
procedure WasmEmitDynStore(dstSym, valNode: Integer);
var hpRel, hpInc: Integer;
begin
  if WasmStrLocN < 0 then WasmStrLocN := WasmAddLocal(WT_I32, 'msnew');
  if WasmStrLocS < 0 then WasmStrLocS := WasmAddLocal(WT_I32, 'msslot');
  if WasmStrLocO < 0 then WasmStrLocO := WasmAddLocal(WT_I32, 'msold');
  hpRel := WasmWriteHelper('PXXDynArrayRelease');
  if hpRel < 0 then Exit;
  hpInc := WasmWriteHelper('PXXDynArrayIncRef');
  if hpInc < 0 then Exit;

  WasmEmitValueAs(valNode, WT_I32, 'dynamic-array assignment');
  if WasmBodyBroken then Exit;
  WasmLocalSet(WasmStrLocN);

  if not ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0)) then
  begin
    WasmLocalGet(WasmStrLocN);
    WasmCall(WasmSlotForProc(hpInc), 'PXXDynArrayIncRef');
  end;

  WasmLValueAddr(dstSym);
  WasmLocalSet(WasmStrLocS);

  WasmLocalGet(WasmStrLocS);
  WasmMemOp($28, 'i32.load', 2, 0);
  WasmLocalSet(WasmStrLocO);

  WasmLocalGet(WasmStrLocS);
  WasmLocalGet(WasmStrLocN);
  WasmMemOp($36, 'i32.store', 2, 0);

  { Element-aware, hence the descriptor: an `array of string` releases every
    element before the block. PXXDynArrayRelease ignores nil, so the
    first-assignment case needs no guard. }
  WasmLocalGet(WasmStrLocO);
  WasmDataAddr(GetOrAllocSymRTTI(dstSym));
  WasmCall(WasmSlotForProc(hpRel), 'PXXDynArrayRelease');
end;

procedure WasmEmitManagedStore(dstIsSym: Boolean; dstRef, valNode: Integer);
var hp: Integer; savedLVW: Boolean;
begin
  if WasmStrLocZ < 0 then WasmStrLocZ := WasmAddLocal(WT_I32, 'msval');
  if WasmStrLocN < 0 then WasmStrLocN := WasmAddLocal(WT_I32, 'msnew');
  if WasmStrLocS < 0 then WasmStrLocS := WasmAddLocal(WT_I32, 'msslot');
  if WasmStrLocO < 0 then WasmStrLocO := WasmAddLocal(WT_I32, 'msold');
  hp := WasmWriteHelper('PXXStrDecRef');
  if hp < 0 then Exit;

  { The three locals are reused across every managed store in a body rather
    than allocated per site, because a Pascal assignment is a STATEMENT: the
    value is fully materialised before the slot is touched, and no managed
    store can be nested inside another one's value expression. A store inside a
    CALLEE is a different frame and therefore different locals. }
  if not WasmEmitOwnedStr(valNode) then Exit;
  WasmLocalSet(WasmStrLocN);

  if dstIsSym then WasmLValueAddr(dstRef)
  else
  begin
    savedLVW := InLValueWrite;
    InLValueWrite := True;
    WasmEmitValueAs(dstRef, WT_I32, 'address of a managed string store');
    InLValueWrite := savedLVW;
  end;
  if WasmBodyBroken then Exit;
  WasmLocalSet(WasmStrLocS);

  WasmLocalGet(WasmStrLocS);
  WasmMemOp($28, 'i32.load', 2, 0);
  WasmLocalSet(WasmStrLocO);

  WasmLocalGet(WasmStrLocS);
  WasmLocalGet(WasmStrLocN);
  WasmMemOp($36, 'i32.store', 2, 0);

  { LAST, and PXXStrDecRef ignores nil, so an uninitialised slot needs no
    guard here — the frame is zeroed by the shadow stack's own initial state
    and a nil old handle is the normal first-assignment case. }
  WasmLocalGet(WasmStrLocO);
  WasmCall(WasmSlotForProc(hp), 'PXXStrDecRef');
end;

{ SetLength through ANY lvalue that is not a plain symbol — a record field, a
  var-param's field, an array element, a deref. IRA is already the SLOT-ADDRESS
  node (the frontend lowered the lvalue with IRLowerAddress), IRB the count, so
  there is no symbol to reconstruct and no shape to classify: the two operands
  push in the order PXXStrSetLen wants them.

  The address node is walked in WRITE position for the same reason every other
  destination is — if it bottoms out in an IR_LEA of a scalar managed string,
  the slot address is what PXXStrSetLen needs and the handle is what it must
  not get. }
procedure WasmEmitSetLenStr(node: Integer);
var savedLVW: Boolean;
begin
  savedLVW := InLValueWrite;
  InLValueWrite := True;
  WasmEmitValueAs(IRA[node], WT_I32, 'slot address of SetLength');
  InLValueWrite := savedLVW;
  WasmEmitValueAs(IRB[node], WT_I32, 'SetLength count');
  if WasmBodyBroken then Exit;
  if not WasmCallRtl('PXXStrSetLen') then Exit;
end;

procedure WasmEmitStmt(node, blk: Integer);
var pvt: Byte;
begin
  { Published for the VALUE emitters. A post-call exception check branches
    through this body's block nesting, and the call emitters — which run deep
    inside an expression — take no block argument and never will. }
  WasmCurBlk := blk;
  case IRKind[node] of
    IR_NOP, IR_BLOCK, IR_LABEL : ;
    IR_JUMP          : WasmEmitJump(node, blk);
    IR_TERMINATE     : WasmEmitTerminate(node, blk);
    IR_CALL          : WasmEmitCall(node, True);
    IR_CALL_IND      : WasmEmitCallInd(node, True);
    IR_VIRTUAL_CALL  : WasmEmitVirtualCall(node, True);
    IR_JUMP_IF_FALSE : WasmEmitJumpIfFalse(node, blk);
    IR_STORE_MEM     : WasmEmitStoreMem(node);
    IR_WRITE, IR_WRITELN : WasmEmitWrite(node);
    IR_COPY_REC      : WasmEmitCopyRec(node);
    IR_DEFAULT_MEM   : WasmEmitDefaultMem(node);
    IR_EXC_ENTER     : WasmEmitExcEnter(node);
    IR_EXC_LEAVE     : WasmEmitExcLeave(node);
    IR_RAISE         : WasmEmitRaise(node, blk);
    IR_EXC_STORE     : WasmEmitExcStore(node);
    IR_EXC_CLEAR     : WasmEmitExcClear;
    IR_EXC_MATCH     : WasmEmitExcMatch(node, blk, False);
    IR_EXC_MATCH_HIT : WasmEmitExcMatch(node, blk, True);
    IR_SETLEN_STR    : WasmEmitSetLenStr(node);
    IR_STORE_SYM :
      { A managed string's SLOT is pointer-sized and its stores are therefore
        scalar-shaped, which is exactly the trap: `m := 'lit'` through the
        scalar path stores the address of the literal's frozen [len][chars]
        blob AS IF it were a heap handle. The module validates, the program
        runs, and every later read of m is off by the 8-byte prefix — measured
        as `s := m` copying `0c 00 00 00 00 00 00 00 from ma` into a string[15]
        where FPC and the x86-64 build both give `from managed`.

        Assigning a managed string is not one store. It is materialise-from-
        literal (PXXStrFromLit), or retain, or move-without-retain for a value
        that already owns its reference, then release the old handle — and a
        var parameter publishes into the CALLER's slot, not the local one
        (ir_codegen.inc:4988-5060). That is a phase, and until it is done the
        honest answer is a refusal that names itself. READING a managed string
        stays supported: a load hands back the handle and takes no ownership. }
      if Syms[IRA[node]].IsArray and (Syms[IRA[node]].ArrLen = -1) then
        WasmEmitDynStore(IRA[node], IRB[node])
      else if Syms[IRA[node]].TypeKind = tyAnsiString then
        WasmEmitManagedStore(True, IRA[node], IRB[node])
      else if TypeIsFrozenString(Syms[IRA[node]].TypeKind) then
        WasmEmitFrozenStore(True, IRA[node], IRB[node], SymStrCap[IRA[node]])
      else if WasmSlotType(IRA[node], pvt) then
      begin
        WasmLValueAddr(IRA[node]);
        { The value is brought to the SLOT's width before the store, not
          after: `i: Integer; j: Int64; i := j` is a defined truncation in
          Pascal and an i32.store of an i64 in wasm, which is not an
          instruction. }
        WasmEmitValueAs(IRB[node], pvt,
                        'assignment to ' + WasmSymLabel(IRA[node]));
        if not WasmBodyBroken then
          WasmTypeStore(Syms[IRA[node]].TypeKind, pvt);
      end;
  else
    { Anything not yet handled is RECORDED rather than skipped. A skipped IR op
      is a program that compiles and computes the wrong answer, which is the
      failure class this target exists to make impossible. }
    if IRTopLevelStmt(node) then
      WasmUnsupported('statement IR op ' + WasmIntStr(IRKind[node]));
  end;
end;

{ Walk the body once, cutting it into basic blocks. Called TWICE with the same
  rule: `emit = False` counts the blocks and maps each label to one, `emit =
  True` emits the code. The rule lives in ONE procedure because two copies of
  it would drift, and a drift here does not fail to build — it makes the
  br_table's arm count disagree with the number of blocks actually emitted, so
  every jump lands one block off. That is a wrong answer with a valid module,
  which is the shape this file spends its comments trying to avoid.

  A block starts at a label, and at the statement after a jump. Adjacent labels
  share a block and a label straight after a jump reuses the block that jump
  opened, so the common `jump end; label else` pattern costs one block and not
  two — which matters, because block count is nesting depth and nesting depth
  is the one measured cap this scheme has. }
procedure WasmWalkBody(emit: Boolean);
var i, curBlk, nStmt: Integer; pending: Boolean;
begin
  curBlk := 0;
  nStmt := 0;
  pending := False;
  if not emit then
  begin
    WasmHasTerminate := False;
    WasmExcSites := 0;
    WasmExcHasHandler := False;
  end;
  for i := 0 to IRCount - 1 do
  begin
    if IRKind[i] = IR_LABEL then
    begin
      if (nStmt > 0) or pending then
      begin
        Inc(curBlk); nStmt := 0; pending := False;
        if emit then WasmEnd;
      end;
      if (not emit) and (IRIVal[i] >= 0) and (IRIVal[i] < MAX_IR) then
      begin
        WasmLabelBlock[IRIVal[i]] := curBlk;
        WasmLabelStamp[IRIVal[i]] := WasmBodySerial;
      end;
    end
    else if IRTopLevelStmt(i) then
    begin
      if pending then
      begin
        Inc(curBlk); nStmt := 0; pending := False;
        if emit then WasmEnd;
      end;
      Inc(nStmt);
      if (not emit) and (IRKind[i] = IR_EXC_ENTER) then
      begin
        WasmExcSlot[i] := WasmExcSites;
        Inc(WasmExcSites);
        WasmExcHasHandler := True;
      end;
      if emit then WasmEmitStmt(i, curBlk);
      if (IRKind[i] = IR_JUMP) or (IRKind[i] = IR_JUMP_IF_FALSE)
         or (IRKind[i] = IR_EXC_MATCH) or (IRKind[i] = IR_EXC_MATCH_HIT) then
        { A class test is a conditional jump wearing a different opcode, so it
          ends its basic block exactly as IR_JUMP_IF_FALSE does. Without this
          the arms of a multi-handler `except` share one block and the fallthrough
          runs the next arm's body. }
        pending := True
      else if IRKind[i] = IR_TERMINATE then
      begin
        { An early Exit branches OUT of the dispatch, so it needs one to exist.
          A body whose only control flow is a trailing `Exit;` would otherwise
          have a single basic block, no enclosing blocks, and nowhere for the
          branch to go — so the terminate both ends its block and forces the
          construction. }
        pending := True;
        WasmHasTerminate := True;
      end;
    end;
  end;
  if not emit then WasmBlockCount := curBlk + 1;
end;

{ Open the nested blocks and the br_table. Emitted only when the body actually
  branches. }
procedure WasmOpenDispatch;
var i: Integer;
begin
  WasmI32Const(0);
  WasmLocalSet(WasmLocalPc);
  WasmBlock(WT_VOID);                       { $exit }
  WasmLoop(WT_VOID);                        { $L }
  for i := 0 to WasmBlockCount - 1 do
    WasmBlock(WT_VOID);                     { B(n-1) .. B0 }
  WasmLocalGet(WasmLocalPc);
  { Arms 0..n-1 reach the blocks; the default reaches $exit, which from here is
    n blocks plus the loop plus one. It is what a $pc of n — the value nothing
    sets, because falling off the last block leaves the loop on its own — would
    take, and it is also the only safe answer for a $pc that is somehow out of
    range. }
  WasmBrTableSeq(WasmBlockCount, WasmBlockCount + 1);
  WasmEnd;                                  { closes B0; block 0's code follows }
end;

{ Close the dispatch. WasmWalkBody has already emitted the `end` that opens
  each block after the first, so what is left is the loop and $exit. }
procedure WasmCloseDispatch;
begin
  WasmEnd;                                  { loop }
  WasmEnd;                                  { $exit }
end;

{ ===== atomics =====

  `__pxxatomic_xchg/cas/add` — a read-modify-write on addr^ returning the OLD
  value. On this target it is a plain load, a plain modify and a plain store,
  and that is not a shortcut: **a wasm MVP module has exactly one thread of
  execution.** There is no other core, no interrupt, and no second agent that
  could observe the middle of the sequence, so the sequence is indivisible by
  construction rather than by a prefix.

  The argument is SEMANTIC, and riscv32 is the model for stating one and then
  stating where it stops (ir_codegen_riscv32.inc:3444: masking interrupts IS
  the atomic on a single-core part with no A extension, and it refuses on a
  multi-core one because the argument does not reach the other core). Here the
  premise is stronger and the refusal condition is the same shape:

  **THIS STOPS BEING TRUE THE DAY THIS TARGET GAINS THREADS.** The wasm threads
  proposal gives a module a `shared` memory and real concurrent agents, and
  every one of these sequences becomes a race — silently, because the code that
  is wrong is the code that is here. riscv32 can ask a capability table
  (`SocCoreCount`); there is nothing to ask here, because whether a module is
  threaded is a MODULE-LEVEL decision this compiler does not yet make. So there
  is no guard to write, only a condition to record — and it is recorded in
  `devdocs/dev/threading-model.md` as well as here, because the person who adds
  threads to this target will be reading a threading document and has no reason
  to open an atomics lowering.

  The 64-bit variants are refused: NativeInt is four bytes here, so a 64-bit
  read-modify-write is two i64 memory ops, and while the single-thread argument
  covers those too, nothing on this target generates them and an untested arm
  is worse than a named refusal.

  The intrinsic is typed Int64, so the old value is sign-extended to i64 —
  the same fold riscv32 does into a0:a1. }
procedure WasmEmitAtomic(node: Integer);
var argNode, nArgs, i: Integer;
    aAddr, aB, aC, aOld: Integer;
    op: Int64;
begin
  op := IRIVal[node];
  if (op = ATOMIC_XCHG64) or (op = ATOMIC_CAS64) or (op = ATOMIC_ADD64) then
  begin
    WasmUnsupported('__pxxatomic_*64 on a 32-bit target');
    Exit;
  end;

  aAddr := WasmAddLocal(WT_I32, 'ataddr');
  aB    := WasmAddLocal(WT_I32, 'atb');
  aC    := WasmAddLocal(WT_I32, 'atc');
  aOld  := WasmAddLocal(WT_I32, 'atold');

  { Args arrive as an IR_ARG chain: addr, then the operands. Each is evaluated
    once, in order, into its own local — the register backends push them and
    pop in reverse for the same reason. }
  nArgs := 0;
  argNode := IRA[node];
  while (argNode <> -1) and (nArgs < 3) do
  begin
    WasmEmitValueAs(IRA[argNode], WT_I32, 'atomic argument');
    if WasmBodyBroken then Exit;
    if nArgs = 0 then WasmLocalSet(aAddr)
    else if nArgs = 1 then WasmLocalSet(aB)
    else WasmLocalSet(aC);
    Inc(nArgs);
    argNode := IRB[argNode];
  end;
  if (argNode <> -1)
     or ((op = ATOMIC_CAS) and (nArgs <> 3))
     or ((op <> ATOMIC_CAS) and (nArgs <> 2)) then
  begin
    WasmUnsupported('atomic op ' + WasmIntStr(Integer(op)) + ' with '
                    + WasmIntStr(nArgs) + ' arguments');
    Exit;
  end;

  { old := addr^ — read once and kept, because it is both the result and, for
    CAS, the value the comparison is against. }
  WasmLocalGet(aAddr);
  WasmMemOp($28, 'i32.load', 2, 0);
  WasmLocalSet(aOld);

  if op = ATOMIC_CAS then
  begin
    { addr^ := newval, only when old = expected. A real `if`: a select would
      store unconditionally, which for a failed CAS is a write that must not
      happen — the one place a spurious store is observable even single
      threaded, because the caller's next read is the retry loop's condition. }
    WasmLocalGet(aOld); WasmLocalGet(aB); WasmOp($46, 'i32.eq');
    WasmIf(WT_VOID);
      WasmLocalGet(aAddr); WasmLocalGet(aC);
      WasmMemOp($36, 'i32.store', 2, 0);
    WasmEnd;
  end
  else if op = ATOMIC_ADD then
  begin
    WasmLocalGet(aAddr);
    WasmLocalGet(aOld); WasmLocalGet(aB); WasmOp($6A, 'i32.add');
    WasmMemOp($36, 'i32.store', 2, 0);
  end
  else   { ATOMIC_XCHG }
  begin
    WasmLocalGet(aAddr); WasmLocalGet(aB);
    WasmMemOp($36, 'i32.store', 2, 0);
  end;

  WasmLocalGet(aOld);
  WasmOp($AC, 'i64.extend_i32_s');
end;

{ ===== string operands: one value, split into (length, data pointer) =====

  Every RTL string routine takes a length and a POINTER TO THE CHARACTERS, and
  the three string-shaped things this target can produce reach those two
  differently:

    AnsiString   the value IS the character pointer; the length is the
                 NativeInt at handle-8 — i32 here, where x86-64 reads a qword —
                 and a nil handle has length 0 and must not be dereferenced.
    frozen       the value is a [len:8][chars] buffer: length at +0, chars at +8.
    Char         neither. It is a VALUE, so it has to be spilled to memory
                 before anything can point at it — one byte of frame scratch,
                 length 1.

  Same three rules as EmitA64StringParts (ir_codegen_aarch64.inc), which is
  where they are written down for the register backends; this is that table in
  wasm, not a second opinion about it. The Char arm is the one that is easy to
  talk yourself out of — the compare arm's comment over there says the AN_BINOP
  lowering already wraps a Char into a string — but the concat arm passes the
  raw operand type and the `charStackOff` parameter exists for exactly this, so
  it is implemented rather than assumed away.

  The node is evaluated EXACTLY ONCE, into valLoc, because an operand may be a
  call and the register backends spill it for the same reason. valLoc is also
  what the caller releases afterwards when the operand owned its reference. }
function WasmStrParts(node, scrLoc, scratchOfs: Integer;
                      valLoc, lenLoc, srcLoc: Integer): Boolean;
var tk: TTypeKind;
begin
  WasmStrParts := False;
  tk := WasmStrTypeOf(node);

  { The value is emitted BEFORE the three locals are written, and it may itself
    be a nested string expression using the next depth's slots — which is why
    the caller allocates these at ITS depth and hands them in, rather than this
    reaching for the pool while a nested emission is in flight. }
  WasmEmitValueAs(node, WT_I32, 'string operand');
  if WasmBodyBroken then Exit;
  { A managed string reached through a FIELD or an ELEMENT yields the address
    of the handle SLOT, not the handle — the same extra deref WasmEmitLength
    inserts for the same two shapes (ir_codegen.inc:7396). }
  if (tk = tyAnsiString)
     and ((IRKind[node] = IR_FIELD) or (IRKind[node] = IR_INDEX)) then
    WasmMemOp($28, 'i32.load', 2, 0);
  WasmLocalSet(valLoc);

  if tk = tyAnsiString then
  begin
    WasmLocalGet(valLoc); WasmLocalSet(srcLoc);
    WasmI32Const(0); WasmLocalSet(lenLoc);
    { A real `if`, not a select: select evaluates both arms and the false arm
      loads from handle-8, which for a nil handle is 0xFFFFFFF8 and traps. }
    WasmLocalGet(valLoc);
    WasmIf(WT_VOID);
      WasmLocalGet(valLoc); WasmI32Const(8); WasmOp($6B, 'i32.sub');
      WasmMemOp($28, 'i32.load', 2, 0);
      WasmLocalSet(lenLoc);
    WasmEnd;
    WasmStrParts := True;
    Exit;
  end;

  if TypeIsFrozenString(tk) then
  begin
    WasmLocalGet(valLoc); WasmMemOp($28, 'i32.load', 2, 0);
    WasmLocalSet(lenLoc);
    WasmLocalGet(valLoc); WasmI32Const(8); WasmOp($6A, 'i32.add');
    WasmLocalSet(srcLoc);
    WasmStrParts := True;
    Exit;
  end;

  if tk = tyChar then
  begin
    if scrLoc < 0 then
    begin
      WasmUnsupported('a Char string operand here has nowhere to spill — '
                      + 'the caller passed no scratch');
      Exit;
    end;
    WasmLocalGet(scrLoc);
    if scratchOfs > 0 then
    begin
      WasmI32Const(scratchOfs); WasmOp($6A, 'i32.add');
    end;
    WasmLocalSet(srcLoc);
    WasmLocalGet(srcLoc); WasmLocalGet(valLoc);
    WasmMemOp($3A, 'i32.store8', 0, 0);
    WasmI32Const(1); WasmLocalSet(lenLoc);
    WasmStrParts := True;
    Exit;
  end;

  WasmUnsupported('string operand of type ' + WasmTypeKindName(tk));
end;

{ Release an operand that OWNED its reference — a concat result or a call
  result, handed over at +1 by whoever built it. The register backends do this
  after the RTL call and before yielding the result
  (ir_codegen_aarch64.inc:1542), and without it `if F(x) = 'abc'` leaks F's
  string on every evaluation. A plain variable is NOT released: this expression
  never owned it. }
procedure WasmStrReleaseTemp(node, valLoc: Integer);
var hp: Integer;
begin
  if WasmStrTypeOf(node) <> tyAnsiString then Exit;
  if not IRNodeOwnsManagedStr(node) then Exit;
  hp := WasmWriteHelper('PXXStrDecRef');
  if hp < 0 then Exit;
  WasmLocalGet(valLoc);
  WasmCall(WasmSlotForProc(hp), 'PXXStrDecRef');
end;

{ `a + b` and the six comparisons, on either string kind.

  Concatenation and comparison are RTL CALLS on every target — there is no
  instruction for either — so the whole of this is: split both operands, push
  four arguments in the callee's order, call, spill the result, release any
  operand temp, yield.

  The argument orders are NOT the same and the types cannot catch a swap
  (all four are i32 here), so they are copied from the declarations rather
  than remembered:

      PXXStrConcat(lenA, srcA, srcB, lenB)     <- note: len,src,src,len
      PXXStrEq    (lenA, srcA, lenB, srcB)
      PXXStrCmp3  (lenA, srcA, lenB, srcB)

  Ordered comparison exists here on purpose. It reached NO cross backend for a
  long time: only =/<> were special-cased and `a < b` fell through to the
  integer compare, comparing two heap HANDLES, so `'zzz' < 'aaa'` answered by
  allocation order — silently, and identically wrongly, on four targets
  (bug-a-ordered-string-comparison-of-a-parameter-compares-handles-on-every-cross-target).
  This backend refuses rather than guesses, so it could not have shipped that
  bug — but it could have shipped the refusal forever, which is why the whole
  set lands at once.

  The result of a compare is Boolean, which WasmNodeResultType already answers
  for any compare op; PXXStrEq and PXXStrCmp3 return Int64, so the i64 they
  leave is folded to an i32 0/1 here rather than by the consumer. }
function WasmEmitStrBinop(node: Integer; op: TTokenKind): Boolean;
var lv, ll, ls, rv, rl, rs, hp, res, scr: Integer;
    left, right: Integer;
    ok: Boolean;
begin
  WasmEmitStrBinop := False;
  left := IRA[node];
  right := IRB[node];

  if WasmStrDepth >= WASM_STR_DEPTH then
  begin
    WasmUnsupported('string expression nested more than '
                    + WasmIntStr(WASM_STR_DEPTH) + ' deep');
    Exit;
  end;
  { Slots taken at THIS depth; operands emitted at the next one. The eight are
    laid out once here so the two arms below cannot disagree about which is
    which. }
  scr := WasmStrSlot(0);
  lv := WasmStrSlot(1); ll := WasmStrSlot(2); ls := WasmStrSlot(3);
  rv := WasmStrSlot(4); rl := WasmStrSlot(5); rs := WasmStrSlot(6);
  res := WasmStrSlot(7);

  if op = tkPlus then
  begin
    if IntToTypeKind(IRTk[node]) <> tyAnsiString then
    begin
      { `fz := a + b` with fz a string[N] builds the result in a stack buffer
        rather than on the heap (ir_codegen_aarch64.inc:1558) — a different
        shape with its own capacity rule, and refused by name until it is
        written rather than approximated with a heap concat that would be the
        wrong TYPE, not merely the wrong size. }
      WasmUnsupported('concatenation producing '
                      + WasmTypeKindName(IntToTypeKind(IRTk[node]))
                      + ' — a frozen result is built in place, not on the heap');
      Exit;
    end;
    hp := WasmWriteHelper('PXXStrConcat');
    if hp < 0 then Exit;
    WasmStrScratchPush(scr);
    Inc(WasmStrDepth);
    ok := WasmStrParts(left, scr, 0, lv, ll, ls)
          and WasmStrParts(right, scr, 8, rv, rl, rs);
    Dec(WasmStrDepth);
    if not ok then Exit;
    WasmLocalGet(ll); WasmLocalGet(ls);
    WasmLocalGet(rs); WasmLocalGet(rl);
    WasmCall(WasmSlotForProc(hp), 'PXXStrConcat');
    WasmLocalSet(res);
    WasmStrReleaseTemp(left, lv);
    WasmStrReleaseTemp(right, rv);
    WasmStrScratchPop(scr);
    WasmLocalGet(res);
    WasmEmitStrBinop := True;
    Exit;
  end;

  if (op = tkEq) or (op = tkNeq) then
    hp := WasmWriteHelper('PXXStrEq')
  else if (op = tkLt) or (op = tkLe)
          or (op = tkGt) or (op = tkGe) then
    hp := WasmWriteHelper('PXXStrCmp3')
  else
    Exit;                 { not an operator strings have — refused by the caller }
  if hp < 0 then Exit;

  WasmStrScratchPush(scr);
  Inc(WasmStrDepth);
  ok := WasmStrParts(left, scr, 0, lv, ll, ls)
        and WasmStrParts(right, scr, 8, rv, rl, rs);
  Dec(WasmStrDepth);
  if not ok then Exit;
  WasmLocalGet(ll); WasmLocalGet(ls);
  WasmLocalGet(rl); WasmLocalGet(rs);
  WasmCall(WasmSlotForProc(hp), Procs[hp].Name);

  { Both helpers return Int64. PXXStrEq gives 1/0 and PXXStrCmp3 gives -1/0/1,
    so every one of the six answers is "compare the returned i64 against 0"
    with the operator the source asked for — equality included, because
    `PXXStrEq(..) <> 0` IS `a = b`. }
  WasmI64Const(0);
  if op = tkEq then WasmOp($52, 'i64.ne')
  else if op = tkNeq then WasmOp($51, 'i64.eq')
  else if op = tkLt then WasmOp($53, 'i64.lt_s')
  else if op = tkLe then WasmOp($57, 'i64.le_s')
  else if op = tkGt then WasmOp($55, 'i64.gt_s')
  else WasmOp($59, 'i64.ge_s');
  WasmLocalSet(res);
  WasmStrReleaseTemp(left, lv);
  WasmStrReleaseTemp(right, rv);
  WasmStrScratchPop(scr);
  WasmLocalGet(res);
  WasmEmitStrBinop := True;
end;

{ ===== managed locals: zero at entry, release at exit =====

  A managed string local's slot is FRAME memory, and this target's frame is the
  shadow stack — whatever the previous call left there. The publish sequence
  reads the slot to find the handle it must release, so an unwritten slot hands
  stale bytes to PXXStrDecRef: measured as `Make` trapping on its very first
  `Make := 'one'`, because $fp+8 held a leftover from the caller's writeln.
  Every register backend zeroes these in its prologue for exactly this reason
  (ir_codegen.inc:10037, pasparser_expr.inc:170, and the four notes there, each
  one a bug where a slot was released before it was ever written). Those passes
  emit machine code through EmitZeroFrameSlot and cannot reach this target,
  which has its own prologue — so this is the same rule, expressed here.

  The two loops share their predicate ON PURPOSE. Zeroing a slot the exit does
  not release leaks; releasing a slot the entry does not zero is the trap
  above. They are the same set or they are a bug, so they are written as one
  procedure with a flag rather than two loops that can drift.

  The RESULT symbol is zeroed and NOT released: a function hands its result
  over already owned, so releasing it here would free the string the caller is
  about to read. That is i386's rule too (`i <> retSymIdx`,
  ir_codegen.inc:10154).

  Scalars only, for now. A record with a managed field, a static array of
  string and a variant local are each their own release shape, and every one of
  them is still refused by name elsewhere on this target — so the honest scope
  is what can actually be stored. }
procedure WasmEmitManagedLocals(release: Boolean; retSym: Integer);
var i, hp, hpDyn: Integer;
begin
  if CurProc < 0 then Exit;    { a program-body chunk: its variables are BSS,
                                 which the module's own memory image zeroes }
  hp := -1; hpDyn := -1;
  if release then
  begin
    hp := WasmWriteHelper('PXXStrDecRef');
    if hp < 0 then Exit;
    hpDyn := WasmWriteHelper('PXXDynArrayRelease');
    if hpDyn < 0 then Exit;
  end;
  { A DYNAMIC ARRAY local joins the same two loops, and the release takes a
    descriptor where a string's does not. Zeroing it matters for the same
    reason it matters for a string and for one more: the FIRST assignment to
    the slot reads the old handle to release it, so an unzeroed slot hands
    PXXDynArrayRelease whatever the previous call left on the shadow stack.
    A string local was already zeroed here; a dyn-array local was not, and it
    was the store arm's arrival that made that reachable. }
  for i := Procs[CurProc].ScopeBase to SymCount - 1 do
    if (Syms[i].Kind = skLocal) and not Syms[i].IsRef
       and (((Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray)
            or (Syms[i].IsArray and (Syms[i].ArrLen = -1))) then
    begin
      if release then
      begin
        if i = retSym then Continue;
        WasmSlotAddr(i);
        WasmMemOp($28, 'i32.load', 2, 0);
        if Syms[i].IsArray then
        begin
          WasmDataAddr(GetOrAllocSymRTTI(i));
          WasmCall(WasmSlotForProc(hpDyn), 'PXXDynArrayRelease');
        end
        else
          WasmCall(WasmSlotForProc(hp), 'PXXStrDecRef');
      end
      else
      begin
        WasmSlotAddr(i);
        WasmI32Const(0);
        WasmMemOp($36, 'i32.store', 2, 0);
      end;
    end;
end;

{ ===== the per-body entry point ===== }

procedure IREmitMachineCodeWasm32;
var
  i, sigIdx, nParams, retSym, psym, pvtI: Integer;
  pvt, resVt: Byte;
  rtk: TTypeKind;
  nRes: Integer;
  nm: AnsiString;
begin
  WasmBeginModuleOnce;

  { Reset the bringup flags FIRST: the signature is derived below and can
    itself refuse a type, so anything that records a reason must do so after
    the reset, not before it. }
  WasmBodyBroken := False;
  WasmBrokenReason := '';

  if CurProc >= 0 then
  begin
    nm := Procs[CurProc].Name;
    nParams := Procs[CurProc].ParamCount;
    if nParams > 32 then nParams := 32;
    nRes := 0;
    if Procs[CurProc].IsFunc then
    begin
      nRes := 1;
      if not WasmProcResult(CurProc, resVt) then resVt := WT_I32;
    end;
    retSym := Procs[CurProc].RetSymIdx;
    { The SAME slot and the SAME signature a caller would have reserved. If a
      call to this proc was emitted first, the slot already exists and this
      fills it in; the shape cannot differ, because both went through
      WasmSigForProc. }
    WasmCurSlot := WasmSlotForProc(CurProc);
  end
  else
  begin
    { A chunk of the program body — see WasmMainChunk. Named for what it is;
      the `main` a host calls is synthesised from these at write time. }
    if WasmMainChunkCount >= MAX_WASM_MAIN_CHUNKS then
      WasmFail('wasm: too many program-body chunks');
    nm := 'main$' + WasmIntStr(WasmMainChunkCount);
    nParams := 0;
    nRes := 0;
    retSym := -1;
    WasmCurSlot := WasmAddFunc(nm, WasmAddType([], []));
    WasmMainChunk[WasmMainChunkCount] := WasmCurSlot;
    Inc(WasmMainChunkCount);
  end;

  { Open the body session BEFORE naming params or adding locals: they now
    accumulate in the per-body buffers that WasmBodyBegin resets. }
  WasmBodyBegin;
  WasmExcTopLocal := -1;
  for i := 0 to 3 do WasmCRLocal[i] := -1;
  WasmCurNRes := nRes;
  if nRes = 1 then WasmCurResVt := resVt;

  for i := 0 to nParams - 1 do
    WasmAddParamName(Procs[CurProc].Params[i].Name);
  WasmLocalFp := WasmAddLocal(WT_I32, 'fp');

  { Pass one: cut the body into basic blocks and map every label to one. It
    must precede the $pc local, because whether $pc exists at all depends on
    whether this body branches. }
  Inc(WasmBodySerial);
  WasmWalkBody(False);
  WasmLocalPc := -1;
  WasmLocalSelf := -1;
  WasmStrLocN := -1;
  WasmStrLocS := -1;
  WasmStrLocO := -1;
  WasmStrLocZ := -1;
  WasmSetInLoc := -1;
  WasmSetInLoc64 := -1;
  WasmStrDepth := 0;
  for i := 0 to WASM_STR_DEPTH - 1 do
    for pvtI := 0 to WASM_STR_SLOTS - 1 do WasmStrPool[i][pvtI] := -1;
  { A handler frame's pad is a BLOCK NUMBER, so a body that owns one needs the
    br_table to branch through even in the degenerate case where its own
    control flow would not have produced a second block. }
  WasmNeedDispatch := (WasmBlockCount > 1) or WasmHasTerminate
                      or WasmExcHasHandler;
  if WasmNeedDispatch then
    WasmLocalPc := WasmAddLocal(WT_I32, 'pc');

  { FrameSize is final by the time a body reaches codegen — locals are
    allocated during lowering (symtab.inc), not here — so unlike the register
    backends there is no prologue to backpatch. Round up to 16 to keep the
    shadow stack aligned for anything that later cares. }
  { The handler frames sit BELOW the Pascal slots. A slot's address is
    `$fp + WasmCurFrame + Offset` with Offset negative from the frame top, so
    growing WasmCurFrame moves the slots up and opens exactly this much room at
    $fp — which is where WasmExcFrameAddr puts frame 0. }
  WasmCurFrame := ((FrameSize + WasmExcSites * WASM_EXCF_SIZE + 15) div 16) * 16;

  { prologue: $fp := $sp - frame ; $sp := $fp }
  WasmGlobalGet(WasmGSp);
  WasmI32Const(WasmCurFrame);
  WasmOp($6B, 'i32.sub');
  WasmLocalSet(WasmLocalFp);
  WasmLocalGet(WasmLocalFp);
  WasmGlobalSet(WasmGSp);

  { home the parameters into their frame slots. wasm hands them over as locals;
    everything downstream addresses them as memory, which is what makes IR_LEA,
    var params and records work unchanged. }
  if not WasmBodyBroken then
    for i := 0 to nParams - 1 do
      if Procs[CurProc].Params[i].SymIdx >= 0 then
      begin
        WasmSlotAddr(Procs[CurProc].Params[i].SymIdx);
        WasmLocalGet(i);
        { The slot's OWN type, not the parameter's declared one: they agree
          today, and the day they stop agreeing is the day a store of the wrong
          width silently corrupts the slot next door. }
        psym := Procs[CurProc].Params[i].SymIdx;
        { The same oracle query WasmLValueAddr asks, on the same SYMBOL, so the
          store here and the load back there cannot disagree about what is in
          the slot — they did when one read the proc's declaration record and
          the other the symbol. }
        if ABIParamSlotHoldsValueAddr(psym) then
          { The incoming value is an ADDRESS, so four bytes go into the slot
            whatever the slot was sized for. WasmLValueAddr reads them back
            with the matching i32.load. }
          WasmTypeStore(tyPointer, WT_I32)
        else if WasmSlotType(psym, pvt) then
          WasmTypeStore(Syms[psym].TypeKind, pvt);
      end;

  if not WasmBodyBroken then WasmEmitManagedLocals(False, retSym);

  if WasmNeedDispatch then WasmOpenDispatch;
  WasmWalkBody(True);
  if WasmNeedDispatch then WasmCloseDispatch;

  { Released BEFORE $sp is restored and before the result is loaded: the slots
    are addressed through $fp either way, but the result must be read after
    everything that could have freed a block, and it is the one slot this skips.
    The exception UNWIND path returns without passing here and therefore leaks —
    known, shared with xtensa, and filed as
    bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa. }
  if not WasmBodyBroken then WasmEmitManagedLocals(True, retSym);

  { epilogue: restore $sp, then leave the result on the operand stack }
  WasmLocalGet(WasmLocalFp);
  WasmI32Const(WasmCurFrame);
  WasmOp($6A, 'i32.add');
  WasmGlobalSet(WasmGSp);
  if (nRes = 1) and (retSym >= 0) then
  begin
    rtk := Syms[retSym].TypeKind;
    WasmEmitLoadSym(retSym);
    if (not WasmBodyBroken) and WasmScalarType(rtk, pvt) then
      WasmCoerce(rtk, pvt, resVt, 'function result');
  end;

  if WasmBodyBroken then
  begin
    { discard whatever was emitted and leave a body that traps if reached.
      `unreachable` is polymorphic, so this validates for any signature. }
    WasmBodyDiscard;
    WasmBodyUnreachable;
    Inc(WasmBrokenCount);
    { The list is capped, but the cap ANNOUNCES itself below. A report that
      silently stops listing is worse than one that lists nothing: it reads as
      a complete answer to `grep <name>` and returns no match for a body that
      is in fact broken. Measured the hard way — three functions trapped at run
      time after a grep of this report said they were fine. }
    if Length(WasmBrokenNames) < 65536 then
      WasmBrokenNames := WasmBrokenNames + '    ' + nm + ' — '
                         + WasmBrokenReason + Chr(10)
    else
      Inc(WasmBrokenUnlisted);
  end
  else
    Inc(WasmLoweredCount);

  WasmBodyTerminate;
  WasmBodyEnd(WasmCurSlot);

  { Every routine is exported for now. A later phase narrows this to what the
    host profile actually needs; until then an exported function is how the
    test harness reaches a body at all.

    Pascal names are not unique and wasm export names must be: overloads, two
    classes' methods of the same name, and — the case that found this — the
    anonymous bodies the frontend emits for typed-const initialisers, all
    called `main`. A colliding name is suffixed with its slot, so the FIRST
    routine of a given name keeps the plain name a test can reach it by and
    the rest stay addressable rather than being dropped. }
  if WasmExportTaken(nm) then
    WasmAddExport(nm + '$' + WasmIntStr(WasmCurSlot), WEK_FUNC,
                  WasmCurSlot)
  else
    WasmAddExport(nm, WEK_FUNC, WasmCurSlot);
end;

{ Printed once, from the module writer, before the .wasm is saved. Unconditional
  by design: a module with trapping holes must never look like a complete one. }
procedure WasmReportCoverage;
begin
  { TWO reports, because they are two different facts and only one of them is
    a defect. A body this backend could not lower is a hole in op coverage and
    the phase is not done. A DECLARATION-ONLY stub — an interface method with
    no implementation, named by the RTTI blob so a function index has to exist
    — is not a hole at all; it gets `unreachable` because calling it must trap,
    which is the correct code, not a placeholder for missing code.

    They used to share a line, and the cost was not cosmetic. Every program
    that links the interface RTTI carries three of these, so the headline said
    "op coverage is incomplete" on a module whose coverage was complete — and
    the phase-completion criterion for this backend is that the count reads N
    of N, which three permanent non-defects made unreachable by construction.
    A signal that can never go clean is a signal nobody reads.

    Both stay LISTED. The stub line is not a suppression: a function that traps
    at run time must be visible at compile time, and the day one of these is a
    real missing body rather than an interface declaration, it is on the page.
    What changed is which of the two claims "incomplete". }
  if (WasmBrokenCount = 0) and (WasmStubCount = 0) then Exit;
  if WasmBrokenCount > 0 then
  begin
    WriteLn('wasm32: ', WasmLoweredCount, ' of ',
            WasmLoweredCount + WasmBrokenCount,
            ' bodies lowered; ', WasmBrokenCount,
            ' emitted as `unreachable` (op coverage is incomplete):');
    Write(WasmBrokenNames);
    if WasmBrokenUnlisted > 0 then
      WriteLn('    ... and ', WasmBrokenUnlisted,
              ' more not listed (listing capped)');
  end
  else
    WriteLn('wasm32: ', WasmLoweredCount, ' of ', WasmLoweredCount,
            ' bodies lowered — op coverage is complete for this program.');
  if WasmStubCount > 0 then
  begin
    WriteLn('wasm32: ', WasmStubCount,
            ' declaration-only stub(s) trap if called (not a coverage gap):');
    Write(WasmStubNames);
  end;
end;

{ ===== the compiler's entry point =====

  Called from compiler.pas's writer arm. It lives here rather than beside the
  rest of the writer in wasmenc.inc so that wasmenc.inc keeps depending on
  nothing — see the note there. }
{ The memory map cannot be laid out when the module starts: BSSSize is not
  final until the last body has been lowered. So the two numbers that depend on
  it — the memory's minimum size and $sp's initial value — are written here,
  overwriting the placeholders WasmBeginModuleOnce installed. }
{ Copy Data[] into the module's one data segment, resolving the relocations
  the frontends recorded against it.

  Two of the three relocation tables are ours to resolve and the third is not:

    DataPtrFix   data->data pointers inside RTTI and layout blobs. An 8-byte
                 slot holding an absolute address; on a 32-bit target the ELF
                 writers put the address in the low dword and leave the high
                 dword zero, and so do we — the same shape, a different base.
    MethodFixups a code address in a VMT slot or an RTTI method entry. wasm has
                 no code addresses; these become TABLE INDICES. The same list
                 the ELF writers resolve to `entry + BodyAddr`, resolved to
                 something else — which is the whole reason this needed no
                 shared-file change: the frontends record a relocation, never
                 an address, because no address exists while Data[] is built.
    Fixups /     code->data and code->BSS references. These name a position in
    GlobFix      Code[], the register backends' instruction stream, which this
                 backend never writes to: it reaches a global through
                 WasmSlotAddr and emits the address inline. Inert here by
                 construction, not by omission.

  Data[] is patched IN PLACE and then copied. Patching a copy would leave the
  blob and the segment disagreeing about what was resolved, and this runs once,
  at write time, after the last emitter. }
procedure WasmFillData;
var i, pos, v: Integer;
begin
  WasmDataSegReset(WasmDataBase);
  if DataLen = 0 then Exit;
  for i := 0 to DataPtrFixCount - 1 do
  begin
    pos := DataPtrFix[i].DataPos;
    v := WasmDataBase + DataPtrFix[i].TargetOff;
    Data[pos]     := Byte(v and $FF);
    Data[pos + 1] := Byte((v shr 8) and $FF);
    Data[pos + 2] := Byte((v shr 16) and $FF);
    Data[pos + 3] := Byte((v shr 24) and $FF);
  end;
  { The slot is 8 bytes and the index goes in the low dword — where a 32-bit
    ELF target puts its address, and where an i32 load at slot*8 reads. The
    high dword is already zero and stays that way. }
  for i := 0 to MethodFixCount - 1 do
  begin
    pos := MethodFixups[i].DataPos;
    v := WasmTableIndex(MethodFixups[i].ProcIdx);
    Data[pos]     := Byte(v and $FF);
    Data[pos + 1] := Byte((v shr 8) and $FF);
    Data[pos + 2] := Byte((v shr 16) and $FF);
    Data[pos + 3] := Byte((v shr 24) and $FF);
  end;
  for i := 0 to DataLen - 1 do WasmDataSegByte(Data[i]);
end;

procedure WasmFinishMemory;
var top: Integer;
begin
  if WasmGSp < 0 then Exit;
  WasmDataBase := ((WASM_BSS_BASE + BSSSize + 15) div 16) * 16;
  WasmGlobInit[WasmGData] := WasmDataBase;
  WasmFillData;
  top := ((WasmDataBase + DataLen + 15) div 16) * 16 + WASM_STACK_BYTES;
  WasmGlobInit[WasmGSp] := top;
  WasmSetMemory((top + WASM_PAGE - 1) div WASM_PAGE, -1);
end;

{ Is this slot's function in the table — i.e. was it reserved because someone
  took its ADDRESS rather than because someone called it? }
function WasmSlotInTable(slot: Integer): Boolean;
var i: Integer;
begin
  WasmSlotInTable := False;
  { WasmTabElem holds SLOTS — the wasm index space is not closed until the
    module is written, so a slot is the only thing comparable here. }
  for i := 0 to WasmTabCount - 1 do
    if WasmTabElem[i] = slot then
    begin
      WasmSlotInTable := True;
      Exit;
    end;
end;

{ A slot reserved by a call or a table entry whose body never arrived. A
  declared wasm function with no body is not a module at all, so it gets the
  same `unreachable` the broken-body path uses — and the same report line,
  because a call that traps at run time must not be invisible at compile time.

  The two reasons are worth telling apart in the message. A CALLED body that
  never arrived is a gap: a forward declaration resolved elsewhere, or
  something the frontend elided. An ADDRESS-TAKEN one usually is not — an
  interface's method declarations have no bodies by construction, and the RTTI
  blob names them, so `IInterface._Release` appears here on every program that
  links the interface RTTI and nothing is wrong. Reporting both with the word
  "called" made a normal module look like it had three holes in it. }
procedure WasmFillEmptyBodies;
var i: Integer; why: AnsiString;
begin
  for i := 0 to WasmFuncCount - 1 do
    if WasmFuncCodeLen[i] = 0 then
    begin
      WasmBodyBegin;
      WasmBodyUnreachable;
      WasmBodyTerminate;
      WasmBodyEnd(i);
      { WHICH counter is the whole distinction. An ADDRESS-TAKEN body that never
        arrived is normal — an interface's method declarations have no bodies
        by construction and the RTTI blob names them. A CALLED one is a gap:
        a forward declaration resolved elsewhere, or something the frontend
        elided, and a call to it traps. }
      if WasmSlotInTable(i) then
      begin
        Inc(WasmStubCount);
        why := 'address taken, but no body was emitted — normal for a method '
             + 'DECLARED without an implementation, such as an interface''s';
        if Length(WasmStubNames) < 65536 then
          WasmStubNames := WasmStubNames + '    ' + WasmFuncName[i]
                           + ' — ' + why + Chr(10);
      end
      else
      begin
        Inc(WasmBrokenCount);
        why := 'declared and called, but no body was emitted';
        if Length(WasmBrokenNames) < 65536 then
          WasmBrokenNames := WasmBrokenNames + '    ' + WasmFuncName[i]
                             + ' — ' + why + Chr(10)
        else
          Inc(WasmBrokenUnlisted);
      end;
    end;
end;

{ `main`: the chunks above, called in the order the frontend emitted them.

  Emitted here rather than at the first chunk because the count is not known
  until the last body has been seen — a typed const declared late adds a chunk
  late. A program with no top-level code at all (a unit, or a slice built with
  -dWASM_NOMAIN and no const initialisers) gets no `main`, which is honest:
  there is nothing to run. }
procedure WasmEmitMainWrapper;
var i, slot, si, iov, fdw: Integer;
begin
  if WasmMainChunkCount = 0 then Exit;
  slot := WasmAddFunc('main', WasmAddType([], []));
  WasmBodyBegin;
  iov := -1;
  si := -1;
  fdw := -1;
  if ExceptionUsed then
  begin
    { The message is interned as an ordinary literal, so it lands in Data[]
      like every other one and needs no special segment. }
    si := InternStr('Unhandled exception' + Chr(10));
    iov := WasmAddLocal(WT_I32, 'iov');
    fdw := WasmHostImport('wasi_snapshot_preview1', 'fd_write',
                          [WT_I32, WT_I32, WT_I32, WT_I32], [WT_I32]);
  end;
  for i := 0 to WasmMainChunkCount - 1 do
  begin
    WasmCall(WasmMainChunk[i],
             'main$' + WasmIntStr(i));
    { AN UNHANDLED EXCEPTION MUST NOT LOOK LIKE SUCCESS. Every body propagates
      by returning with the flag set, so if it is still set here nothing caught
      it and this is the end of the line: say so on stderr and exit 217, the
      same code every other target uses (EXITCODE_UNHANDLED_EXCEPTION).

      Checked after EACH chunk rather than once at the end, because the chunks
      are the program's top-level statements in order and a raise in one must
      not let the next one run.

      Written through fd_write directly rather than through the RTL's console
      family: those write to fd 1 and this belongs on fd 2, and reaching for
      them here would make the wrapper depend on which RTL routines a given
      program happens to have pulled in.

      NOT the full x86-64 line. That one reads the object's class name and its
      `msg` field out of RTTI — `Unhandled exception: EFoo: bad thing` — and
      every field read there is range-guarded because raising a non-Exception
      must degrade rather than fault. Worth having, and it is a separate piece
      of work; a bare line with the right exit code is the honest version of
      it, where silence is not. }
    if ExceptionUsed then
    begin
      WasmGlobalGet(WasmExcPendGlobal);
      WasmIf(WT_VOID);
        { Scratch below $sp: this wrapper has no frame of its own, so the 16
          bytes under the stack pointer are nobody's. iov is 8 bytes at
          $sp-16, the nwritten word 4 bytes at $sp-8. }
        WasmGlobalGet(WasmGSp);
        WasmI32Const(16);
        WasmOp($6B, 'i32.sub');
        WasmLocalSet(iov);
        WasmLocalGet(iov);
        WasmDataAddr(Strs[si].Offset + 8);   { +8 skips the length prefix }
        WasmMemOp($36, 'i32.store', 2, 0);
        WasmLocalGet(iov);
        WasmI32Const(Strs[si].Len);
        WasmMemOp($36, 'i32.store', 2, 4);
        WasmI32Const(2);                     { fd 2 }
        WasmLocalGet(iov);
        WasmI32Const(1);                     { one iovec }
        WasmLocalGet(iov);
        WasmI32Const(8);
        WasmOp($6A, 'i32.add');              { where fd_write reports nwritten }
        WasmCallImport(fdw, 'fd_write');
        WasmOp($1A, 'drop');
        WasmI32Const(EXITCODE_UNHANDLED_EXCEPTION);
        WasmCallImport(WasmHostImport('wasi_snapshot_preview1', 'proc_exit',
                                      [WT_I32], []), 'proc_exit');
        WasmBodyUnreachable;
      WasmEnd;
    end;
  end;
  WasmBodyTerminate;
  WasmBodyEnd(slot);
  WasmAddExport('main', WEK_FUNC, slot);
  { AND `_start`, which is what a WASI COMMAND module is required to export.
    `main` is our own convention and is what the JS test harness calls; every
    real WASI host — wasmtime, wasmer, node's WASI — looks for `_start` and
    refuses to run a module without it. Two exports of one function costs a
    name and makes the same module runnable by both, which is the difference
    between a module a harness can drive and a module a host can run. }
  WasmAddExport('_start', WEK_FUNC, slot);
end;

procedure writeWasm(const outPath: AnsiString);
begin
  { ORDER MATTERS, and it is the reverse of the obvious one. WasmFinishMemory
    resolves the VMT relocations, and resolving one hands out a table index,
    and handing one out RESERVES A FUNCTION SLOT for a proc whose address is
    taken but which this backend may never have been asked to emit. So it must
    run BEFORE the empty-body pass, or those slots reach the code section as a
    zero-length body — `function body must end with END opcode`, at a byte
    offset, naming nothing. }
  WasmEmitMainWrapper;
  WasmFinishMemory;
  WasmFillEmptyBodies;
  WasmReportCoverage;
  if WasmFuncCount = 0 then
    WasmFail('wasm32: nothing to write — no code was generated for this module '
          + '(the module writer is present and tested via '
          + 'test/wasm/check_phase1.sh)');
  { An output path ending in .wat gets the TEXT module. asmtext_wasm.inc has
    been able to write it since Phase 1 and nothing in the compiler could ask
    for it — the oracle existed and was unreachable from the command line,
    which is precisely the state you discover while staring at
    `unable to read i32 leb128` with no way to see what you emitted. No flag:
    the extension already says which form is wanted, and a flag would be a
    second way to say the same thing. }
  if (Length(outPath) >= 4)
     and (Copy(outPath, Length(outPath) - 3, 4) = '.wat') then
    WasmWriteText(outPath)
  else
    WasmSaveModule(outPath);
end;
