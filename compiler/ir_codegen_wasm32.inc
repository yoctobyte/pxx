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
    ... WasmStackTop       the shadow stack, growing DOWN from the top.

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

procedure WasmBeginModuleOnce;
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
  WasmGSp := WasmAddGlobal('sp', WT_I32, True, 65536);
  WasmAddExport('sp', WEK_GLOBAL, WasmGSp);
end;

{ Load the address of a slot onto the operand stack. A global's address is a
  constant; a local's is $fp plus a displacement, and this is the ONE place the
  sign convention is converted — Pascal records a local's Offset as NEGATIVE
  from the frame top (symtab.inc, `Offset := -FrameSize`) and $fp points at the
  frame BOTTOM, so the slot sits at $fp + (FrameSize - N). }
procedure WasmSlotAddr(si: Integer);
begin
  if Syms[si].Kind = skGlobal then
    WasmI32Const(WASM_BSS_BASE + Syms[si].Offset)
  else
  begin
    WasmLocalGet(WasmLocalFp);
    WasmI32Const(WasmCurFrame + Syms[si].Offset);
    WasmOp($6A, 'i32.add');
  end;
end;

function WasmEmitNode(node: Integer): TTypeKind; forward;

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

function WasmEmitLoadSym(si: Integer): TTypeKind;
var vt: Byte;
begin
  WasmEmitLoadSym := Syms[si].TypeKind;
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

function WasmEmitLea(node: Integer): TTypeKind;
var si: Integer;
begin
  WasmEmitLea := tyPointer;
  si := IRA[node];
  if Syms[si].IsArray then
  begin
    WasmUnsupported('address of array ' + Syms[si].Name);
    Exit;
  end;
  if Syms[si].TypeKind = tyAnsiString then
  begin
    WasmUnsupported('address of managed string ' + Syms[si].Name);
    Exit;
  end;
  WasmLValueAddr(si);
end;

{ A field's address: the base address plus a constant byte offset. IRIVal
  carries the offset, which the record layout has already resolved, so there is
  no record-shape knowledge in this backend at all — it is address arithmetic
  that happens to be spelled with a dot. }
function WasmEmitField(node: Integer): TTypeKind;
begin
  WasmEmitField := tyPointer;
  WasmEmitValueAs(IRA[node], WT_I32, 'record base address');
  if WasmBodyBroken then Exit;
  if Integer(IRIVal[node]) <> 0 then
  begin
    WasmI32Const(Integer(IRIVal[node]));
    WasmOp($6A, 'i32.add');
  end;
end;

function WasmEmitLoadMem(node: Integer): TTypeKind;
var tk: TTypeKind; vt: Byte;
begin
  tk := IntToTypeKind(IRTk[node]);
  WasmEmitLoadMem := tk;
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

function WasmEmitBinop(node: Integer): TTypeKind;
var
  op: TTokenKind;
  tkA, tkB: TTypeKind;
  vtA, vtB, vtN, want: Byte;
  sgn, isCmp: Boolean;
  what: AnsiString;
begin
  op := TTokenKind(IRC[node]);
  { Pascal spells `shr` as an IDENTIFIER — the lexer never produces tkShr for
    it, so an IR_BINOP carrying `shr` carries Ord(tkIdent) as its operator
    (compiler/ir.inc:8867 says so in as many words, and ir.inc:8878 performs
    exactly this substitution for the one consumer that existed before this
    backend). Doing it again here is the second arm of a double case, which is
    the shape devdocs/dev/normalise-dont-special-case.md says to fix at the
    source rather than duplicate — filed as
    bug-a-shr-reaches-the-ir-spelled-as-tkident. Until that lands, a backend
    that did NOT translate would not merely miss `shr`, it would mistake every
    `shr` for whatever it does with tkIdent. }
  if op = tkIdent then op := tkShr;
  WasmEmitBinop := tyInt32;
  tkA := IntToTypeKind(IRTk[IRA[node]]);
  tkB := IntToTypeKind(IRTk[IRB[node]]);
  what := 'binary operator ' + WasmIntStr(IRC[node]);
  if (not WasmScalarType(tkA, vtA)) or (not WasmScalarType(tkB, vtB))
     or (not WasmNodeType(node, vtN)) then
  begin
    WasmUnsupported('operand type in ' + what);
    Exit;
  end;

  { Both operands are brought to ONE width before the instruction, because wasm
    has no mixed-width arithmetic at all. The node's own recorded type joins the
    unification: it can only widen the result (WasmUnify never narrows), and
    including it stops a plan that would truncate a value the IR expects whole.
    For a comparison it contributes Boolean/i32, which changes nothing. }
  want := WasmUnify(WasmUnify(vtA, vtB), vtN);
  sgn := TypeSigned(tkA) or TypeSigned(tkB);

  WasmEmitValueAs(IRA[node], want, what);
  WasmEmitValueAs(IRB[node], want, what);
  if WasmBodyBroken then Exit;

  { Pascal `div` and `mod` lower to wasm div_s/rem_s, which TRAP on a zero
    divisor and on the INT_MIN div -1 overflow rather than raising. A trap is
    not a catchable Pascal exception, so the checked forms must arrive with the
    IR's own pre-check in front of them — removing that pre-check is a SEMANTIC
    change, not an optimisation (phase2-shadow-stack.md). The pre-check is a
    comparison and a branch, so div is not even reachable until Phase 3 lands,
    and when it arrives it arrives guarded. }
  if (want = WT_F32) or (want = WT_F64) then
    WasmFloatBinop(op, want = WT_F64, what)
  else
    WasmIntBinop(op, want = WT_I64, sgn, what);

  { A comparison consumes two operands of any width and yields i32 regardless;
    everything else yields the width it was computed at. }
  isCmp := (op = tkEq) or (op = tkNeq) or (op = tkLt)
           or (op = tkLe) or (op = tkGt) or (op = tkGe);
  if isCmp then WasmEmitBinop := tyBoolean
  else WasmEmitBinop := WasmRepType(want, sgn);
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

function WasmEmitUnary(node: Integer; isNeg: Boolean): TTypeKind;
var got: TTypeKind; vt: Byte;
begin
  WasmEmitUnary := tyInt32;
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
  if (not isNeg) and (got = tyBoolean) then WasmEmitUnary := tyBoolean
  else WasmEmitUnary := got;
end;

function WasmEmitConstInt(node: Integer): TTypeKind;
var vt: Byte;
begin
  WasmEmitConstInt := IntToTypeKind(IRTk[node]);
  if not WasmNodeType(node, vt) then
  begin
    WasmUnsupported('integer constant of type ' + WasmIntStr(IRTk[node]));
    Exit;
  end;
  if vt = WT_I64 then WasmI64Const(IRIVal[node])
  else if vt = WT_I32 then WasmI32Const(IRIVal[node])
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
  case IRKind[node] of
    IR_CONST_INT : WasmEmitNode := WasmEmitConstInt(node);
    IR_LOAD_SYM  : WasmEmitNode := WasmEmitLoadSym(IRA[node]);
    IR_BINOP     : WasmEmitNode := WasmEmitBinop(node);
    IR_LEA       : WasmEmitNode := WasmEmitLea(node);
    IR_FIELD     : WasmEmitNode := WasmEmitField(node);
    IR_LOAD_MEM  : WasmEmitNode := WasmEmitLoadMem(node);
    IR_NEG       : WasmEmitNode := WasmEmitUnary(node, True);
    IR_NOT       : WasmEmitNode := WasmEmitUnary(node, False);
  else
    WasmUnsupported('value IR op ' + WasmIntStr(IRKind[node]));
  end;
end;

{ ===== the per-body entry point ===== }

procedure IREmitMachineCodeWasm32;
var
  i, sigIdx, nParams, retSym, psym: Integer;
  pvt: Byte;
  rtk: TTypeKind;
  ptypes: array[0..31] of Byte;
  rtypes: array[0..0] of Byte;
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
    for i := 0 to nParams - 1 do
      if not WasmScalarType(Procs[CurProc].Params[i].TypeKind, ptypes[i]) then
      begin
        { A placeholder keeps the signature well-formed. The body is going to
          be discarded for `unreachable`, which is polymorphic and validates
          against any signature, so the placeholder only has to be legal — not
          right. }
        ptypes[i] := WT_I32;
        WasmUnsupported('parameter ' + Procs[CurProc].Params[i].Name
                        + ' has no wasm value type');
      end;
    if Procs[CurProc].IsFunc then
    begin
      nRes := 1;
      if not WasmScalarType(Procs[CurProc].RetType, rtypes[0]) then
      begin
        rtypes[0] := WT_I32;
        WasmUnsupported('result has no wasm value type');
      end;
    end
    else
      nRes := 0;
    retSym := Procs[CurProc].RetSymIdx;
  end
  else
  begin
    { the program body: no params, no result, and it is what the host calls }
    nm := 'main';
    nParams := 0;
    nRes := 0;
    retSym := -1;
  end;

  { Signature. The array-slice spellings keep WasmAddType's open-array
    parameters honest for the 0-param and 0-result cases. }
  if nParams = 0 then
  begin
    if nRes = 0 then sigIdx := WasmAddType([], [])
    else sigIdx := WasmAddType([], [rtypes[0]]);
  end
  else
    sigIdx := WasmAddTypeN(ptypes, nParams, rtypes, nRes);

  { Refuse a signature Phase 2 cannot honour, BEFORE emitting a body that would
    contradict it. This is the concrete form of the argument in CHARTER.md: on a
    register target, loading an Int64 slot with a 32-bit load produces a
    plausible wrong value far from the cause. Here the module simply fails to
    validate — `type mismatch in implicit return, expected [i64] but got [i32]`,
    with a byte offset. The bug is the same bug; the target is what makes it
    impossible to ship. }
  WasmCurSlot := WasmAddFunc(nm, sigIdx);
  for i := 0 to nParams - 1 do
    WasmAddParamName(WasmCurSlot, Procs[CurProc].Params[i].Name);
  WasmLocalFp := WasmAddLocal(WasmCurSlot, WT_I32, 'fp');

  { FrameSize is final by the time a body reaches codegen — locals are
    allocated during lowering (symtab.inc), not here — so unlike the register
    backends there is no prologue to backpatch. Round up to 16 to keep the
    shadow stack aligned for anything that later cares. }
  WasmCurFrame := ((FrameSize + 15) div 16) * 16;

  WasmBodyBegin;

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
        if WasmSlotType(psym, pvt) then
          WasmTypeStore(Syms[psym].TypeKind, pvt);
      end;

  for i := 0 to IRCount - 1 do
    case IRKind[i] of
      IR_NOP, IR_BLOCK, IR_LABEL : ;
      IR_STORE_MEM : WasmEmitStoreMem(i);
      IR_STORE_SYM :
        if WasmSlotType(IRA[i], pvt) then
        begin
          WasmLValueAddr(IRA[i]);
          { The value is brought to the SLOT's width before the store, not
            after: `i: Integer; j: Int64; i := j` is a defined truncation in
            Pascal and an i32.store of an i64 in wasm, which is not an
            instruction. }
          WasmEmitValueAs(IRB[i], pvt, 'assignment to ' + Syms[IRA[i]].Name);
          if not WasmBodyBroken then
            WasmTypeStore(Syms[IRA[i]].TypeKind, pvt);
        end;
    else
      { Anything not yet handled errors rather than being skipped. A skipped IR
        op is a program that compiles and computes the wrong answer, which is
        the failure class this target exists to make impossible. }
      if IRTopLevelStmt(i) then
        WasmUnsupported('statement IR op ' + WasmIntStr(IRKind[i]));
    end;

  { epilogue: restore $sp, then leave the result on the operand stack }
  WasmLocalGet(WasmLocalFp);
  WasmI32Const(WasmCurFrame);
  WasmOp($6A, 'i32.add');
  WasmGlobalSet(WasmGSp);
  if (nRes = 1) and (retSym >= 0) then
  begin
    rtk := WasmEmitLoadSym(retSym);
    if (not WasmBodyBroken) and WasmScalarType(rtk, pvt) then
      WasmCoerce(rtk, pvt, rtypes[0], 'function result');
  end;

  if WasmBodyBroken then
  begin
    { discard whatever was emitted and leave a body that traps if reached.
      `unreachable` is polymorphic, so this validates for any signature. }
    WasmBodyBegin;
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

  { Every routine is exported for now. Phase 4 narrows this to what the host
    profile actually needs; until then an exported function is how the test
    harness reaches a body at all. }
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
          ' emitted as `unreachable` (Phase 2 is incomplete):');
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
procedure WasmFinishMemory;
var top: Integer;
begin
  if WasmGSp < 0 then Exit;
  top := ((WASM_BSS_BASE + BSSSize + 15) div 16) * 16 + WASM_STACK_BYTES;
  WasmGlobInit[WasmGSp] := top;
  WasmSetMemory((top + WASM_PAGE - 1) div WASM_PAGE, -1);
end;

procedure writeWasm(const outPath: AnsiString);
begin
  WasmFinishMemory;
  WasmReportCoverage;
  if WasmFuncCount = 0 then
    WasmFail('wasm32: nothing to write — no code was generated for this module '
          + '(the module writer is present and tested via '
          + 'test/wasm/check_phase1.sh)');
  WasmSaveModule(outPath);
end;
