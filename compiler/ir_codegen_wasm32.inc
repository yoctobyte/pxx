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
  WasmGSp           : Integer = -1;   { the $sp global's index }
  WasmCurSlot       : Integer = -1;   { function slot being emitted }
  WasmCurFrame      : Integer = 0;    { this body's frame size, bytes }
  WasmLocalFp       : Integer = 0;    { local index of $fp }
  WasmLocalPc       : Integer = -1;   { local index of $pc, -1 if no dispatch }
  WasmBlockCount    : Integer = 0;    { basic blocks in the current body }
  WasmBodySerial    : Integer = 0;    { stamps WasmLabelStamp, see below }
  WasmHasTerminate  : Boolean = False;{ body contains an early Exit }
  WasmNeedDispatch  : Boolean = False;{ ... so the dispatch must exist }

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
    arrives in Phase 6. Exported so a test harness can inspect linear memory. }
  WasmSetMemory(1, -1);
  WasmAddExport('memory', WEK_MEM, 0);
  { The shadow-stack pointer. Exported so a harness can assert it balances —
    the property the Phase 5 prototype leans on. }
  for i := 0 to MAX_PROCS - 1 do
  begin
    WasmProcSlot[i] := -1;
    WasmProcTabIdx[i] := -1;
  end;
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
  if (Syms[si].Kind = skParam) and Syms[si].IsRef then
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
  if not WasmSlotType(si, vt) then Exit;
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
  if not WasmScalarType(got, gvt) then
  begin
    WasmUnsupported('value of type ' + WasmIntStr(Ord(got)) + ' in ' + ctx);
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
    handle is one more instruction and is not the hard part; what it points at
    is the heap, which is Phase 6. Refusing every array — which is what this
    did first — also refused `a[i]` on a plain `array[0..9] of Integer`, where
    nothing is on the heap at all. }
  if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
  begin
    WasmUnsupported('dynamic array ' + Syms[si].Name + ' — needs the heap, Phase 6');
    Exit;
  end;
  if (Syms[si].Kind = skParam) and Syms[si].IsArray and not Syms[si].IsRef then
  begin
    WasmUnsupported('open-array parameter ' + Syms[si].Name
                    + ' — the slot holds a heap handle, Phase 6');
    Exit;
  end;
  if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray then
  begin
    WasmUnsupported('address of managed string ' + Syms[si].Name
                    + ' — needs the heap, Phase 6');
    Exit;
  end;
  WasmLValueAddr(si);
end;

{ `a[i]` — base + (i - low) * elemSize, with the low bound in IRC and the
  element stride in IRIVal, both already resolved by the frontend. Same
  contract riscv32 reads (ir_codegen_riscv32.inc:1580); the arithmetic is
  identical and only the spilling is gone, because the base can simply sit on
  the operand stack while the index is computed.

  The managed-string shapes are refused: indexing a string in WRITE position is
  a copy-on-write call (PXXStrUnique), not address arithmetic, and getting that
  wrong stores a character into the handle slot rather than into the string —
  a bug riscv32 shipped and had to fix twice. It needs the heap regardless. }
procedure WasmEmitIndex(node: Integer);
var left, lo, elemSize: Integer;
begin
  left := IRA[node];
  lo := IRC[node];
  elemSize := Integer(IRIVal[node]);
  if ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString)
      and not Syms[IRA[left]].IsArray)
     or (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX))
         and (IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)) then
  begin
    WasmUnsupported('indexing a managed string — needs the heap, Phase 6');
    Exit;
  end;
  WasmEmitValueAs(left, WT_I32, 'array base');
  WasmEmitValueAs(IRB[node], WT_I32, 'array index');
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
  if not WasmScalarType(tk, vt) then
  begin
    WasmUnsupported('load through a pointer of type ' + WasmIntStr(IRTk[node]));
    Exit;
  end;
  WasmEmitValueAs(IRA[node], WT_I32, 'address of a load');
  if WasmBodyBroken then Exit;
  WasmTypeLoad(tk, vt);
end;

procedure WasmEmitStoreMem(node: Integer);
var tk: TTypeKind; vt: Byte;
begin
  tk := IntToTypeKind(IRTk[node]);
  if not WasmScalarType(tk, vt) then
  begin
    WasmUnsupported('store through a pointer of type ' + WasmIntStr(IRTk[node]));
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
  WasmEmitValueAs(IRA[node], WT_I32, 'address of a store');
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

{ Pure: the single width both operands are brought to, and its signedness.
  Shared by the planner and the type oracle so the two cannot disagree about
  what a binop yields. }
function WasmBinopWidth(node: Integer; var want: Byte; var sgn: Boolean): Boolean;
var tkA, tkB: TTypeKind; vtA, vtB, vtN: Byte;
begin
  WasmBinopWidth := False;
  tkA := WasmNodeResultType(IRA[node]);
  tkB := WasmNodeResultType(IRB[node]);
  if not WasmScalarType(tkA, vtA) then Exit;
  if not WasmScalarType(tkB, vtB) then Exit;
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
  what := 'binary operator ' + WasmIntStr(IRC[node]);
  if not WasmBinopWidth(node, want, sgn) then
  begin
    { Name the operand TYPES and IR KINDS, not just the operator. "operand type
      in binary operator 67" says a comparison was refused and nothing about
      which side or why; with the numbers the report is a diagnosis rather than
      a pointer to one. }
    WasmUnsupported(what + ': operand types '
                    + WasmIntStr(Ord(WasmNodeResultType(IRA[node]))) + '/'
                    + WasmIntStr(Ord(WasmNodeResultType(IRB[node])))
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
  else
    { An IR_CONST_INT carrying a float type would need f32.const/f64.const,
      whose immediates are raw IEEE bytes rather than a LEB — a different
      encoder, not a different opcode. Refused until there is a float constant
      to test it with. }
    WasmUnsupported('non-integer constant type ' + WasmIntStr(IRTk[node]));
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
    IR_INDEX     : WasmEmitIndex(node);
    IR_FIELD     : WasmEmitField(node);
    IR_LOAD_MEM  : WasmEmitLoadMem(node);
    IR_NEG       : WasmEmitUnary(node, True);
    IR_NOT       : WasmEmitUnary(node, False);
    IR_PROCADDR  : WasmEmitProcAddr(node);
    IR_CALL_IND  : WasmEmitCallInd(node, False);
    IR_VIRTUAL_CALL : WasmEmitVirtualCall(node, False);
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
  if Procs[p].Params[i].IsRef or Procs[p].Params[i].IsArray then
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
      WasmUnsupported('result of ' + Procs[p].Name + ' has no wasm value type');
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
    index (`-Ord(tkGetMem)`). Each is a small program, not a call, and each
    needs the heap — Phase 6.
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
  else if (p = -Ord(tkOrd)) and (IRB[node] <> -1) then
    WasmBuiltinResultType := WasmNodeResultType(IRA[IRB[node]])
  else
    WasmBuiltinResultType := IntToTypeKind(IRTk[node]);
end;

{ Builtins this backend can lower. Returns False for one it cannot, so the
  caller reports it by NAME rather than this function inventing a reason. }
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

procedure WasmEmitCall(node: Integer; isStmt: Boolean);
var p, argNode, i, nParams: Integer; pvt: Byte;
begin
  p := IRA[node];
  if p < 0 then
  begin
    if WasmEmitBuiltin(node, p, isStmt) then Exit;
    WasmUnsupported('builtin ' + WasmBuiltinName(p) + ' (IR_CALL with proc '
                    + 'index ' + WasmIntStr(p) + ')');
    Exit;
  end;
  if (p < Length(ProcExternal)) and ProcExternal[p] then
  begin
    WasmUnsupported('call to external ' + Procs[p].Name
                    + ' — needs a wasm import, Phase 6');
    Exit;
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
  WasmCall(WasmFuncIndex(WasmSlotForProc(p)), Procs[p].Name);
  { A function called for its side effect leaves its result on the operand
    stack, and wasm requires the stack to be empty at the end of a statement.
    `drop` is that requirement, not a tidy-up. }
  if isStmt and Procs[p].IsFunc then WasmOp($1A, 'drop');
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
    WasmProcTabIdx[p] := WasmTableAdd(WasmFuncIndex(WasmSlotForProc(p)));
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
var sigProc: Integer;
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

{ IR_TERMINATE is two statements wearing one opcode: `Halt(n)` when IRIVal is
  AN_HALT, and an early `Exit` otherwise (ir_codegen_riscv32.inc's arm makes the
  same split). Exit is a branch out of the dispatch to the epilogue, which is
  what every register backend spells as "jump to the procedure epilogue". Halt
  is a process-level operation with no wasm instruction at all — it needs WASI's
  proc_exit import, which is Phase 6 — so it is refused by name rather than
  quietly returning, which would turn `Halt(1)` into success. }
procedure WasmEmitTerminate(node, blk: Integer);
begin
  if IRIVal[node] = AN_HALT then
  begin
    WasmUnsupported('Halt — needs the WASI proc_exit import (Phase 6)');
    Exit;
  end;
  WasmBr(WasmDepthToExit(blk));
end;

procedure WasmEmitStmt(node, blk: Integer);
var pvt: Byte;
begin
  case IRKind[node] of
    IR_NOP, IR_BLOCK, IR_LABEL : ;
    IR_JUMP          : WasmEmitJump(node, blk);
    IR_TERMINATE     : WasmEmitTerminate(node, blk);
    IR_CALL          : WasmEmitCall(node, True);
    IR_CALL_IND      : WasmEmitCallInd(node, True);
    IR_VIRTUAL_CALL  : WasmEmitVirtualCall(node, True);
    IR_JUMP_IF_FALSE : WasmEmitJumpIfFalse(node, blk);
    IR_STORE_MEM     : WasmEmitStoreMem(node);
    IR_STORE_SYM :
      if WasmSlotType(IRA[node], pvt) then
      begin
        WasmLValueAddr(IRA[node]);
        { The value is brought to the SLOT's width before the store, not
          after: `i: Integer; j: Int64; i := j` is a defined truncation in
          Pascal and an i32.store of an i64 in wasm, which is not an
          instruction. }
        WasmEmitValueAs(IRB[node], pvt,
                        'assignment to ' + Syms[IRA[node]].Name);
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
  if not emit then WasmHasTerminate := False;
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
      if emit then WasmEmitStmt(i, curBlk);
      if (IRKind[i] = IR_JUMP) or (IRKind[i] = IR_JUMP_IF_FALSE) then
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

{ ===== the per-body entry point ===== }

procedure IREmitMachineCodeWasm32;
var
  i, sigIdx, nParams, retSym, psym: Integer;
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
  WasmNeedDispatch := (WasmBlockCount > 1) or WasmHasTerminate;
  if WasmNeedDispatch then
    WasmLocalPc := WasmAddLocal(WT_I32, 'pc');

  { FrameSize is final by the time a body reaches codegen — locals are
    allocated during lowering (symtab.inc), not here — so unlike the register
    backends there is no prologue to backpatch. Round up to 16 to keep the
    shadow stack aligned for anything that later cares. }
  WasmCurFrame := ((FrameSize + 15) div 16) * 16;

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
        if Procs[CurProc].Params[i].IsRef
           or Procs[CurProc].Params[i].IsArray then
          { The incoming value is an ADDRESS, so four bytes go into the slot
            whatever the slot was sized for. WasmLValueAddr reads them back
            with the matching i32.load. }
          WasmTypeStore(tyPointer, WT_I32)
        else if WasmSlotType(psym, pvt) then
          WasmTypeStore(Syms[psym].TypeKind, pvt);
      end;

  if WasmNeedDispatch then WasmOpenDispatch;
  WasmWalkBody(True);
  if WasmNeedDispatch then WasmCloseDispatch;

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
                  WasmFuncIndex(WasmCurSlot))
  else
    WasmAddExport(nm, WEK_FUNC, WasmFuncIndex(WasmCurSlot));
end;

{ Printed once, from the module writer, before the .wasm is saved. Unconditional
  by design: a module with trapping holes must never look like a complete one. }
procedure WasmReportCoverage;
begin
  if WasmBrokenCount = 0 then Exit;
  WriteLn('wasm32: ', WasmLoweredCount, ' of ',
          WasmLoweredCount + WasmBrokenCount,
          ' bodies lowered; ', WasmBrokenCount,
          ' emitted as `unreachable` (op coverage is incomplete):');
  Write(WasmBrokenNames);
  if WasmBrokenUnlisted > 0 then
    WriteLn('    ... and ', WasmBrokenUnlisted,
            ' more not listed (listing capped)');
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
var i, fi: Integer;
begin
  WasmSlotInTable := False;
  fi := WasmFuncIndex(slot);
  for i := 0 to WasmTabCount - 1 do
    if WasmTabElem[i] = fi then
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
      Inc(WasmBrokenCount);
      if WasmSlotInTable(i) then
        why := 'address taken, but no body was emitted — normal for a method '
             + 'DECLARED without an implementation, such as an interface''s'
      else
        why := 'declared and called, but no body was emitted';
      if Length(WasmBrokenNames) < 65536 then
        WasmBrokenNames := WasmBrokenNames + '    ' + WasmFuncName[i]
                           + ' — ' + why + Chr(10)
      else
        Inc(WasmBrokenUnlisted);
    end;
end;

{ `main`: the chunks above, called in the order the frontend emitted them.

  Emitted here rather than at the first chunk because the count is not known
  until the last body has been seen — a typed const declared late adds a chunk
  late. A program with no top-level code at all (a unit, or a slice built with
  -dWASM_NOMAIN and no const initialisers) gets no `main`, which is honest:
  there is nothing to run. }
procedure WasmEmitMainWrapper;
var i, slot: Integer;
begin
  if WasmMainChunkCount = 0 then Exit;
  slot := WasmAddFunc('main', WasmAddType([], []));
  WasmBodyBegin;
  for i := 0 to WasmMainChunkCount - 1 do
    WasmCall(WasmFuncIndex(WasmMainChunk[i]),
             'main$' + WasmIntStr(i));
  WasmBodyTerminate;
  WasmBodyEnd(slot);
  WasmAddExport('main', WEK_FUNC, WasmFuncIndex(slot));
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
