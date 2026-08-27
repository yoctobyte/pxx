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
  $fp + (FrameSize - N). That conversion happens in WasmSlotDisp and nowhere
  else. }

var
  WasmModuleStarted : Boolean = False;
  WasmGSp           : Integer = -1;   { the $sp global's index }
  WasmCurSlot       : Integer = -1;   { function slot being emitted }
  WasmCurFrame      : Integer = 0;    { this body's frame size, bytes }
  WasmLocalFp       : Integer = 0;    { local index of $fp }

{ Pascal type -> wasm value type. Only the Phase 2 subset; anything else is a
  loud Error rather than a plausible i32. }
function WasmValType(tk: TTypeKind): Byte;
begin
  if (tk = tyInt64) or (tk = tyUInt64) then WasmValType := WT_I64
  else if tk = tyDouble then WasmValType := WT_F64
  else if tk = tySingle then WasmValType := WT_F32
  else WasmValType := WT_I32;   { integers, booleans, chars, pointers }
end;

{ A frame slot's byte displacement from $fp. The one place the sign convention
  is converted; see the header note. }
function WasmSlotDisp(si: Integer): Integer;
begin
  if Syms[si].Kind = skGlobal then
    Error('wasm32: globals not implemented yet (Phase 2 does frame slots first)');
  WasmSlotDisp := WasmCurFrame + Syms[si].Offset;
end;

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

{ Load the address of a frame slot onto the operand stack. }
procedure WasmSlotAddr(si: Integer);
begin
  WasmLocalGet(WasmLocalFp);
  WasmI32Const(WasmSlotDisp(si));
  WasmBinop($6A, 'i32.add');
end;

procedure WasmEmitNode(node: Integer); forward;

procedure WasmEmitLoadSym(si: Integer);
begin
  WasmSlotAddr(si);
  WasmI32Load(2, 0);
end;

procedure WasmEmitBinop(node: Integer);
var op: TTokenKind;
begin
  op := TTokenKind(IRC[node]);
  WasmEmitNode(IRA[node]);
  WasmEmitNode(IRB[node]);
  { Phase 2 subset: signed 32-bit integer arithmetic. Signedness and the
    div-by-zero pre-check are deliberately NOT guessed here — see the open
    questions in phase2-shadow-stack.md. wasm div_s TRAPS on zero and on
    INT_MIN/-1, and a trap is not a catchable Pascal exception, so the checked
    forms arrive with their guard or not at all. }
  if op = tkPlus then WasmBinop($6A, 'i32.add')
  else if op = tkMinus then WasmBinop($6B, 'i32.sub')
  else if op = tkStar then WasmBinop($6C, 'i32.mul')
  else
    Error('wasm32: binary operator not implemented yet in Phase 2 (op '
          + WasmIntStr(IRC[node]) + ')');
end;

procedure WasmEmitNode(node: Integer);
begin
  if node < 0 then Error('wasm32: null node reference');
  case IRKind[node] of
    IR_CONST_INT : WasmI32Const(IRIVal[node]);
    IR_LOAD_SYM  : WasmEmitLoadSym(IRA[node]);
    IR_BINOP     : WasmEmitBinop(node);
  else
    Error('wasm32: IR op ' + WasmIntStr(IRKind[node])
          + ' not implemented yet (Phase 2 covers const/load/binop/store)');
  end;
end;

{ ===== the per-body entry point ===== }

procedure IREmitMachineCodeWasm32;
var
  i, sigIdx, nParams, retSym: Integer;
  ptypes: array[0..31] of Byte;
  rtypes: array[0..0] of Byte;
  nRes: Integer;
  nm: AnsiString;
begin
  WasmBeginModuleOnce;

  if CurProc >= 0 then
  begin
    nm := Procs[CurProc].Name;
    nParams := Procs[CurProc].ParamCount;
    for i := 0 to nParams - 1 do
      ptypes[i] := WasmValType(Procs[CurProc].Params[i].TypeKind);
    if Procs[CurProc].IsFunc then
    begin
      nRes := 1;
      rtypes[0] := WasmValType(Procs[CurProc].RetType);
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
  WasmBinop($6B, 'i32.sub');
  WasmLocalSet(WasmLocalFp);
  WasmLocalGet(WasmLocalFp);
  WasmGlobalSet(WasmGSp);

  { home the parameters into their frame slots. wasm hands them over as locals;
    everything downstream addresses them as memory, which is what makes IR_LEA,
    var params and records work unchanged. }
  for i := 0 to nParams - 1 do
    if Procs[CurProc].Params[i].SymIdx >= 0 then
    begin
      WasmSlotAddr(Procs[CurProc].Params[i].SymIdx);
      WasmLocalGet(i);
      WasmI32Store(2, 0);
    end;

  for i := 0 to IRCount - 1 do
    case IRKind[i] of
      IR_NOP, IR_BLOCK, IR_LABEL : ;
      IR_STORE_SYM :
        begin
          WasmSlotAddr(IRA[i]);
          WasmEmitNode(IRB[i]);
          WasmI32Store(2, 0);
        end;
    else
      { Anything not yet handled errors rather than being skipped. A skipped IR
        op is a program that compiles and computes the wrong answer, which is
        the failure class this target exists to make impossible. }
      if IRTopLevelStmt(IRKind[i]) then
        Error('wasm32: IR op ' + WasmIntStr(IRKind[i])
              + ' not implemented yet (Phase 2 is straight-line codegen)');
    end;

  { epilogue: restore $sp, then leave the result on the operand stack }
  WasmLocalGet(WasmLocalFp);
  WasmI32Const(WasmCurFrame);
  WasmBinop($6A, 'i32.add');
  WasmGlobalSet(WasmGSp);
  if (nRes = 1) and (retSym >= 0) then WasmEmitLoadSym(retSym);

  WasmBodyTerminate;
  WasmBodyEnd(WasmCurSlot);

  { Every routine is exported for now. Phase 4 narrows this to what the host
    profile actually needs; until then an exported function is how the test
    harness reaches a body at all. }
  WasmAddExport(nm, WEK_FUNC, WasmFuncIndex(WasmCurSlot));
end;
