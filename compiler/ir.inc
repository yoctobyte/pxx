{ SPDX-License-Identifier: MPL-2.0 }
function Shl8_(shift: Integer): Integer;
begin
  Shl8_ := 0;
  if shift = 0 then Shl8_ := 1
  else if shift = 1 then Shl8_ := 2
  else if shift = 2 then Shl8_ := 4
  else if shift = 3 then Shl8_ := 8
  else if shift = 4 then Shl8_ := 16
  else if shift = 5 then Shl8_ := 32
  else if shift = 6 then Shl8_ := 64
  else if shift = 7 then Shl8_ := 128;
end;

procedure IRReset;
begin
  IRCount := 0;
  IRLabelCount := 0;
  IRLoopStackDepth := 0;
  CurLowerLine := 0;
  CurLowerFile := 1;
end;

procedure EnsureIRCapacity(need: Integer);
{ Grow the per-IR-node parallel arrays so index `need-1` is in bounds. Doubling
  from a small base gives amortized-O(1) append; capacity never shrinks (IRReset
  only zeroes IRCount), so it settles at the largest single function body seen.
  ALL node-indexed arrays must grow in lockstep — a missed one is a silent
  out-of-bounds. See bug-pascal-ir-node-hard-limit-max-ir. }
var n: Integer;
begin
  if need <= IRCapacity then Exit;
  if IRCapacity = 0 then n := 65536 else n := IRCapacity;
  while n < need do n := n * 2;
  SetLength(IRKind, n);         SetLength(IRA, n);         SetLength(IRB, n);
  SetLength(IRC, n);            SetLength(IRIVal, n);      SetLength(IRTk, n);
  SetLength(IRCallDest, n);     SetLength(IRCtorProc, n);  SetLength(IRSetLenBaseRec, n);
  SetLength(IRStmtRoot, n);     SetLength(IRLine, n);      SetLength(IRFile, n);
  IRCapacity := n;
end;

function IRAppend(kind, a, b, c: Integer; ival: Int64; tk: Integer): Integer;
begin
  EnsureIRCapacity(IRCount + 1);
  IRKind[IRCount] := kind;
  IRA[IRCount] := a;
  IRB[IRCount] := b;
  IRC[IRCount] := c;
  IRIVal[IRCount] := ival;
  IRTk[IRCount] := tk;
  IRStmtRoot[IRCount] := False;
  IRLine[IRCount] := CurLowerLine;
  IRFile[IRCount] := CurLowerFile;
  IRCallDest[IRCount] := -1;
  IRCtorProc[IRCount] := -1;
  Result := IRCount;
  Inc(IRCount);
end;

function IROpName(kind: Integer): AnsiString;
begin
  case kind of
    IR_NOP: Result := 'nop';
    IR_CONST_INT: Result := 'const_int';
    IR_CONST_STR: Result := 'const_str';
    IR_LOAD_SYM: Result := 'load_sym';
    IR_STORE_SYM: Result := 'store_sym';
    IR_BINOP: Result := 'binop';
    IR_CALL: Result := 'call';
    IR_WRITE: Result := 'write';
    IR_WRITELN: Result := 'writeln';
    IR_READLINE: Result := 'readline';
    IR_READ_VAR: Result := 'read_var';
    IR_COPY_REC: Result := 'copy_rec';
    IR_COPY_REC_MANAGED: Result := 'copy_rec_managed';
    IR_DYNDATA: Result := 'dyndata';
    IR_SETLEN_DYN: Result := 'setlen_dyn';
    IR_SETLEN_STR: Result := 'setlen_str';
    IR_DYNUNIQUE: Result := 'dynunique';
    IR_SLOTADDR: Result := 'slotaddr';
    IR_ZERO_SYM: Result := 'zero_sym';
    IR_DEFAULT_MEM: Result := 'default_mem';
    IR_READ_DISCARD: Result := 'read_discard';
    IR_BLOCK: Result := 'block';
    IR_UNSUPPORTED: Result := 'unsupported';
    IR_IF: Result := 'if';
    IR_LABEL: Result := 'label';
    IR_JUMP: Result := 'jump';
    IR_JUMP_IF_FALSE: Result := 'jump_if_false';
    IR_NEG: Result := 'neg';
    IR_NOT: Result := 'not';
    IR_LEA: Result := 'lea';
    IR_INDEX: Result := 'index';
    IR_FIELD: Result := 'field';
    IR_LOAD_MEM: Result := 'load_mem';
    IR_STORE_MEM: Result := 'store_mem';
    IR_STORE_DYN: Result := 'store_dyn';
    IR_ARG: Result := 'arg';
    IR_EXC_ENTER: Result := 'exc_enter';
    IR_EXC_LEAVE: Result := 'exc_leave';
    IR_RAISE: Result := 'raise';
    IR_EXC_MATCH: Result := 'exc_match';
    IR_EXC_MATCH_HIT: Result := 'exc_match_hit';
    IR_EXC_STORE: Result := 'exc_store';
    IR_EXC_CLEAR: Result := 'exc_clear';
    IR_TERMINATE: Result := 'terminate';
    IR_VIRTUAL_CALL: Result := 'virtual_call';
    IR_ASM: Result := 'asm';
    IR_RTTI_REG: Result := 'rtti_reg';
    IR_RESOURCES: Result := 'resources';
    IR_SET_LIT: Result := 'set_lit';
    IR_SET_COPY: Result := 'set_copy';
    IR_SET_BINOP: Result := 'set_binop';
    IR_SET_CMP: Result := 'set_cmp';
    IR_VAR_STORE: Result := 'var_store';
    IR_VAR_BINOP: Result := 'var_binop';
    IR_VAR_BOX: Result := 'var_box';
    IR_SYSCALL: Result := 'syscall';
    IR_COSWITCH: Result := 'coswitch';
    IR_CLONE: Result := 'clone';
    IR_ATOMIC: Result := 'atomic';
    IR_YIELD: Result := 'yield';
    IR_CALL_IND: Result := 'call_ind';
    IR_CONST_DATA: Result := 'const_data';
    IR_MULHI: Result := 'mulhi';
    IR_FRAME: Result := 'frame';
    IR_ALLOCA: Result := 'alloca';
    IR_FPU_MASK: Result := 'fpu_mask';
  else
    Result := 'unknown';
  end;
end;

function IRNodeOK(idx: Integer): Boolean;
begin
  Result := (idx >= 0) and (idx < IRCount);
end;

function IRNewLabel: Integer;
begin
  Result := IRLabelCount;
  Inc(IRLabelCount);
end;

function IRLabelExists(labelId: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to IRCount - 1 do
    if (IRKind[i] = IR_LABEL) and (IRIVal[i] = labelId) then
      Result := True;
end;

procedure IRRequireNode(idx: Integer; const context: AnsiString);
begin
  if not IRNodeOK(idx) then
    Error('invalid IR node reference in ' + context);
end;

procedure IRRequireOptionalNode(idx: Integer; const context: AnsiString);
begin
  if (idx <> -1) and not IRNodeOK(idx) then
    Error('invalid optional IR node reference in ' + context);
end;

{ Local decimal int->string (AsmIntToStr lives in asmfront.inc, included after
  ir.inc, so not visible here). Only used by the --strict-ir diagnostic. }
function IRVerifyIntStr(v: Integer): AnsiString;
var neg: Boolean; u: Integer; r: AnsiString;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0; u := v; if neg then u := -u;
  r := '';
  while u > 0 do begin r := Chr(Ord('0') + (u mod 10)) + r; u := u div 10; end;
  if neg then r := '-' + r;
  Result := r;
end;

procedure IRVerify;
var i, lblId, op: Integer;
    seenLabel: array[0..MAX_IR-1] of Boolean;
begin
  { Only [0, IRLabelCount) can be read: seenLabel is indexed by label id and
    IRNewLabel hands out ids in that range (IRReset zeroes IRLabelCount per body).
    Clearing the full MAX_IR array was a 128KB per-body memset for nothing. }
  for i := 0 to IRLabelCount - 1 do
    seenLabel[i] := False;

  { Pass 1: populate seen labels and verify uniqueness }
  for i := 0 to IRCount - 1 do
  begin
    { High(TTypeKind), not the last kind spelled by name: this bound was
      hardcoded to Ord(tyBool8) and every new kind appended to the enum silently
      failed IR verification until someone edited it here. Adding a kind should
      not require finding this line. }
    if (IRTk[i] < 0) or (IRTk[i] > Ord(High(TTypeKind))) then
      Error('invalid type kind in IR node');

    if IRKind[i] = IR_LABEL then
    begin
      lblId := Integer(IRIVal[i]);
      if (lblId < 0) or (lblId >= MAX_IR) then
        Error('IR label ID out of bounds');
      if seenLabel[lblId] then
        Error('duplicate IR label definition');
      seenLabel[lblId] := True;
    end;
  end;

  { Pass 2: check all instructions and operand invariants }
  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_CONST_INT, IR_CONST_STR, IR_NOP, IR_LABEL, IR_ASM, IR_RTTI_REG, IR_SET_LIT, IR_RESOURCES,
      IR_FRAME:
        begin end;

      IR_LOAD_SYM:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid IR symbol reference in load_sym');

      IR_STORE_SYM:
      begin
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid IR symbol reference in store_sym');
        IRRequireNode(IRB[i], 'store_sym');
      end;

      IR_BINOP:
      begin
        IRRequireNode(IRA[i], 'binop left');
        IRRequireNode(IRB[i], 'binop right');
        op := IRC[i];
        if (op < 0) or ((op > Ord(tkShl)) and (op <> Ord(tkXor)) and (op <> Ord(tkShr))) then
          Error('invalid operator token kind in binop');
      end;

      IR_CALL:
      begin
        if (IRA[i] >= ProcCount) then
          Error('invalid IR proc reference in call');
        IRRequireOptionalNode(IRB[i], 'call first arg');
        if ABIRetViaHiddenDestProc(IRA[i]) then
          IRRequireNode(IRC[i], 'call aggregate destination');
        { Otherwise IRC = classIdx (record id for constructor/method dispatch),
          NOT a node. Args chain via IRB[argNode]. }
      end;

      IR_WRITE:
        IRRequireNode(IRA[i], 'write');

      IR_READLINE:
        begin end;

      IR_READ_VAR:
        IRRequireNode(IRA[i], 'read_var');

      IR_COPY_REC:
      begin
        IRRequireNode(IRA[i], 'copy_rec dest');
        IRRequireNode(IRB[i], 'copy_rec src');
      end;

      IR_COPY_REC_MANAGED:
      begin
        IRRequireNode(IRA[i], 'copy_rec_managed dest');
        IRRequireNode(IRB[i], 'copy_rec_managed src');
      end;

      IR_DEFAULT_MEM:
        IRRequireNode(IRA[i], 'default_mem dest');

      IR_ZERO_SYM:
        { IRA = symbol index of the slot to nil/zero (e.g. a managed lazy var
          before its initializer assign). Not a node reference. }
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in zero_sym');

      IR_READ_DISCARD:
        begin end;

      IR_DYNDATA:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in dyndata');

      IR_SETLEN_DYN:
      begin
        IRRequireNode(IRA[i], 'setlen_dyn target');
        IRRequireNode(IRB[i], 'setlen_dyn count');
      end;

      IR_SETLEN_STR:
      begin
        IRRequireNode(IRA[i], 'setlen_str target');
        IRRequireNode(IRB[i], 'setlen_str count');
      end;

      IR_DYNUNIQUE:
        { IRA = slot-address node; IRB carries the depth integer, not a node. }
        IRRequireNode(IRA[i], 'dynunique slot');

      IR_SLOTADDR:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in slotaddr');

      IR_SET_COPY, IR_SET_BINOP, IR_SET_CMP:
      begin
        IRRequireNode(IRA[i], 'set op left');
        IRRequireNode(IRB[i], 'set op right');
      end;

      IR_WRITELN, IR_BLOCK:
      begin
        IRRequireOptionalNode(IRA[i], 'block first');
        IRRequireOptionalNode(IRB[i], 'block last');
      end;

      IR_IF:
      begin
        IRRequireNode(IRA[i], 'if condition');
        IRRequireNode(IRB[i], 'if then');
        IRRequireOptionalNode(IRC[i], 'if else');
      end;

      IR_JUMP:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR jump target (label not defined)');
      end;

      IR_JUMP_IF_FALSE:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR conditional jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR conditional jump target (label not defined)');
        IRRequireNode(IRB[i], 'jump condition');
      end;

      IR_NEG, IR_NOT:
        IRRequireNode(IRA[i], 'unary operand');

      IR_LEA:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in lea');

      IR_INDEX:
      begin
        IRRequireNode(IRA[i], 'index base');
        IRRequireNode(IRB[i], 'index offset');
      end;

      IR_FIELD:
        IRRequireNode(IRA[i], 'field base');

      IR_LOAD_MEM:
        IRRequireNode(IRA[i], 'load_mem address');

      IR_STORE_MEM:
      begin
        IRRequireNode(IRA[i], 'store_mem address');
        IRRequireNode(IRB[i], 'store_mem value');
      end;

      IR_STORE_DYN:
      begin
        IRRequireNode(IRA[i], 'store_dyn slot address');
        IRRequireNode(IRB[i], 'store_dyn value');
      end;

      IR_ARG:
      begin
        IRRequireNode(IRA[i], 'arg value');
        IRRequireOptionalNode(IRB[i], 'next arg');
      end;

      IR_SYSCALL:
        IRRequireNode(IRA[i], 'syscall number arg');

      IR_COSWITCH:
        IRRequireNode(IRA[i], 'coswitch first arg');

      IR_CLONE:
        IRRequireNode(IRA[i], 'clone first arg');

      IR_ATOMIC:
        IRRequireNode(IRA[i], 'atomic addr arg');

      IR_YIELD:
        IRRequireNode(IRA[i], 'yield value');

      IR_CALL_IND:
      begin
        IRRequireNode(IRA[i], 'call_ind callee');
        IRRequireOptionalNode(IRB[i], 'call_ind first arg');
      end;

      IR_EXC_ENTER, IR_EXC_MATCH, IR_EXC_MATCH_HIT:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR exception jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR exception jump target (label not defined)');
      end;

      IR_EXC_LEAVE, IR_EXC_CLEAR:
        begin end;

      IR_RAISE:
        IRRequireOptionalNode(IRA[i], 'raise value');

      IR_EXC_STORE:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in exception store');

      IR_TERMINATE:
        IRRequireOptionalNode(IRA[i], 'terminate value');

      IR_VIRTUAL_CALL:
      begin
        IRRequireOptionalNode(IRA[i], 'virtual_call first arg');
        IRRequireOptionalNode(IRB[i], 'virtual_call last arg');
        if (IRC[i] < 0) or (IRC[i] >= ProcCount) then
          Error('invalid proc index in virtual_call');
      end;

      IR_PROCADDR:
        if (IRA[i] < 0) or (IRA[i] >= ProcCount) then
          Error('invalid proc index in procaddr');

      IR_CLASSREF:
        if (IRA[i] < 0) or (IRA[i] >= UClsCount) then
          Error('invalid class index in classref');

      IR_VMTADDR:
        if (IRA[i] < 0) or (IRA[i] >= UClsCount) then
          Error('invalid class index in vmtaddr');

      IR_IMTADDR:
        if (IRA[i] < 0) or (IRA[i] >= IMTCount) then
          Error('invalid IMT index in imtaddr');

      IR_UNSUPPORTED:
        { A frontend could not lower this AST node (ir.inc IRLowerAST /
          IRLowerAddress else-fallbacks). Under --strict-ir, fail loud: an
          IR_UNSUPPORTED node — even an unreferenced/dead one — means the
          program is already broken and reaching codegen with it produces a
          nondeterministic self-host miscompile (bug-selfhost-multifn-ifelse-
          miscompile). Default off so an in-development frontend is not broken.
          IRA[i] holds the offending AST kind (ASTKind, see the IRAppend calls
          at ~965 / ~5107). }
        if StrictIR then
          Error('IR_UNSUPPORTED: frontend could not lower AST node (kind ' +
                IRVerifyIntStr(IRA[i]) + ') — a frontend gap, would miscompile');

      IR_VAR_STORE:
      begin
        IRRequireNode(IRA[i], 'var_store dest');
        IRRequireNode(IRB[i], 'var_store value');
      end;

      IR_VAR_BINOP:
      begin
        IRRequireNode(IRA[i], 'var_binop left');
        IRRequireNode(IRB[i], 'var_binop right');
      end;

      IR_VAR_BOX:
      begin
        IRRequireNode(IRA[i], 'var_box dest');
        IRRequireNode(IRB[i], 'var_box value');
      end;

      IR_SET_SIGNAL:
      begin
        IRRequireNode(IRA[i], 'set_signal sig');
        IRRequireNode(IRB[i], 'set_signal handler');
      end;

      IR_IO_LOCK, IR_IO_UNLOCK:
        begin end;

      IR_CONST_DATA:
        begin end;

      IR_MULHI:
        begin
          IRRequireNode(IRA[i], 'mulhi a');
          IRRequireNode(IRB[i], 'mulhi b');
        end;

      IR_ALLOCA:
        IRRequireNode(IRA[i], 'alloca size');

      IR_FPU_MASK:
        if IRC[i] = 1 then IRRequireNode(IRA[i], 'fpu mask value');

    else
      Error('unknown IR opcode');
    end;
  end;
end;

function IRLowerAST(node: Integer): Integer; forward;
function IRVariantUnboxKind(target: TTypeKind): Boolean; forward;
function IRLowerVariantAsScalar(argAST: Integer; target: TTypeKind): Integer; forward;
function IRVariantAddr(argAST: Integer): Integer; forward;
function IRMethodRefCode(mref: Integer): Integer; forward;
function IRMaterializeIntfCast(node: Integer; doTrap: Boolean): Integer; forward;

procedure IRLowerCleanupToDepth(targetDepth: Integer);
var current, bodyNode, savedDepth: Integer;
begin
  current := ExceptionCodegenDepth;
  while current > targetDepth do
  begin
    IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
    bodyNode := ExceptionFinallyBody[current - 1];
    if bodyNode <> -1 then
    begin
      savedDepth := ExceptionCodegenDepth;
      ExceptionCodegenDepth := current - 1;
      IRLowerAST(bodyNode);
      ExceptionCodegenDepth := savedDepth;
    end;
    Dec(current);
  end;
end;

procedure IRMarkStatementNode(irNode: Integer);
begin
  if (irNode >= 0) and (irNode < IRCount) then
  begin
    if IRKind[irNode] = IR_CALL then
      IRIVal[irNode] := 1
    else if (IRKind[irNode] = IR_VIRTUAL_CALL) or (IRKind[irNode] = IR_CALL_IND) then
      IRStmtRoot[irNode] := True;
  end;
end;

{ A discarded MANAGED STRING result is an owned handle nobody stores, so nothing
  ever releases it: `flabel(7)` as a statement leaked ~32 bytes per call, for
  plain defs and methods alike (bug-nilpy-discarded-string-result-leaks).

  Bind it to a hidden temp belonging to THIS SITE and return the STORE. The
  managed store releases the slot's previous value before taking the new one, so
  a loop through this site keeps at most one handle alive and the scope-exit
  release frees the last — no new IR op (which every backend would then have to
  implement) and no ownership transfer to invent.

  Returning the store, rather than emitting it and keeping the call as the
  statement, is what keeps the call from being emitted TWICE: the store is
  itself a statement root and drags its operand tree in with it. Callers pass
  the result straight on to IRMarkStatementNode, which ignores a store. }
function IRDropManagedStrResult(irNode: Integer): Integer;
var tmp: Integer;
begin
  IRDropManagedStrResult := irNode;
  if (irNode < 0) or (irNode >= IRCount) then Exit;
  if not PyProgramMode then Exit;
  if IntToTypeKind(IRTk[irNode]) <> tyAnsiString then Exit;
  if not (((IRKind[irNode] = IR_CALL) and (IRA[irNode] >= 0)) or
          (IRKind[irNode] = IR_VIRTUAL_CALL) or (IRKind[irNode] = IR_CALL_IND)) then Exit;
  tmp := AllocVar('', tyAnsiString);
  IRDropManagedStrResult := IRAppend(IR_STORE_SYM, tmp, irNode, -1, 0, Ord(tyAnsiString));
end;

procedure IRDiscardValue(irNode: Integer);
{ A value computed at STATEMENT level and thrown away -- but which must still be
  EVALUATED, because the expression may contain calls.

  IRMarkStatementNode alone is not enough: the IR is emitted by walking from its roots,
  and the top-level emit loop only recognises certain statement kinds. A root that is
  neither a call nor a store is an ORPHAN and never gets emitted -- and the calls inside
  it go down with it. So `f() ^ 3;`, `(void)(f() + 1);` and `x = ((f() ^ K), 0);` all
  silently failed to call f(). The VALUES were right, which is why it stayed invisible;
  csmith found it through the comma form.

  Fix: force any other root into a hidden temp. A store IS a statement root, so it gets
  emitted and drags its whole operand tree -- calls included -- with it, in order. The
  temp is dead and -O drops the store.

  Use this ONLY where the value is genuinely discarded at statement level (statement-list
  items, a comma's left operand). Do NOT use it mid-expression -- appending a store while
  a caller is part-way through building an argument or init chain splices it into that
  chain and corrupts it. That is what IRMarkStatementNode stays for.

  C-mode only: Pascal has no value-discarding expression statement, so the self-host
  binary stays byte-identical. }
var mkTk: TTypeKind; mkTmp: Integer;
begin
  if (irNode < 0) or (irNode >= IRCount) then Exit;
  IRMarkStatementNode(irNode);
  if not CProgramMode then Exit;
  { Wrap ONLY a pure value node -- an operator whose result is thrown away but whose
    operands may call something. Crucially none of these kinds is emitted by the
    top-level statement loop, so the wrapping store cannot make an already-emitted
    statement (IR_STORE_*, IR_CALL, IR_WRITE, ...) run a SECOND time as an operand.
    An earlier revision wrapped every non-call root and did exactly that: it
    double-evaluated the store in `*va_arg(ap, double*) = 100.125;` and crashed. }
  if IRKind[irNode] = IR_LOAD_MEM then
  begin
    { `*f();` -- a discarded load THROUGH a call result. Do not wrap the load: an
      IR_LOAD_MEM root also turns up where the emit loop is already handling the
      surrounding statement (the va_arg builtins), and wrapping it there evaluated
      that statement twice and crashed b201. Marking the address operand is enough --
      it is the call, and that is the only side effect the load can have. }
    IRMarkStatementNode(IRA[irNode]);
    Exit;
  end;
  if (IRKind[irNode] <> IR_BINOP) and (IRKind[irNode] <> IR_NEG) and
     (IRKind[irNode] <> IR_NOT) then Exit;
  mkTk := IntToTypeKind(IRTk[irNode]);
  if TypeIsOrdinal(mkTk) or TypeIsFloat(mkTk) or (mkTk = tyPointer) then
  begin
    mkTmp := AllocVar('', mkTk);
    IRAppend(IR_STORE_SYM, mkTmp, irNode, -1, 0, Ord(mkTk));
  end;
end;

function NodeDynDepth(node: Integer): Integer;
{ Dynamic-array nesting of an expression's value: 0 if not a dyn array, else the
  remaining `array of` levels. m (array of array of T) is 2; m[i] is 1; m[i][j]
  is 0 (a base value). }
var bd: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
        Result := SymDynDepth[ASTIVal[node]];
    AN_FIELD:
      Result := RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
    AN_INDEX:
      begin
        bd := NodeDynDepth(ASTLeft[node]);
        if bd > 0 then Result := bd - 1
        else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
                (Syms[ASTIVal[ASTLeft[node]]].IsArray) and
                (Syms[ASTIVal[ASTLeft[node]]].ArrLen <> -1) and
                (SymElemDynDepth[ASTIVal[ASTLeft[node]]] > 0) then
          { Indexing a FIXED array whose element is a dynamic array
            (`array[..] of TA`): the element is a dyn array of this depth. }
          Result := SymElemDynDepth[ASTIVal[ASTLeft[node]]];
      end;
  end;
end;

function NodeDynBaseTk(node: Integer): TTypeKind;
{ Base element type of a (possibly nested) dynamic-array expression, walking to
  the root symbol or field. tyUnknown if not a dynamic array. }
begin
  Result := tyUnknown;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := Syms[ASTIVal[node]].ElemType
    else if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1) and
            (SymElemDynDepth[ASTIVal[node]] > 0) then
      { fixed array of a dyn-array element: element base type lives in ElemType }
      Result := Syms[ASTIVal[node]].ElemType;
  end
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldType(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseTk(ASTLeft[node]);
end;

function NodeIsManagedString(node: Integer): Boolean;
{ True if the lvalue node denotes a managed AnsiString (a string symbol, record/
  class field, indexed element, or pointer deref of one). Drives the address-
  based SetLength path (IR_SETLEN_STR) so a field / var-param field needs no
  symbol reconstruction. Frozen inline strings (tyString) return False. }
var rec: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      { A scalar managed-string variable — NOT a dynamic array of strings (whose
        symbol also carries tyAnsiString as its element type). }
      Result := (Syms[ASTIVal[node]].TypeKind = tyAnsiString) and
                not Syms[ASTIVal[node]].IsArray;
    AN_FIELD:
      { RecFieldType reports the ELEMENT type for an array field, so an
        `array of string` field also reads back tyAnsiString — exclude it via the
        field's dyn-array depth so only a scalar string field matches. }
      begin
        rec := ResolveNodeRec(ASTLeft[node]);
        if rec <> REC_NONE then
          Result := (RecFieldType(rec, GetASTIdentName(node)) = tyAnsiString) and
                    (RecFieldDynDepth(rec, GetASTIdentName(node)) = 0);
      end;
    AN_INDEX, AN_DEREF:
      { An indexed element / pointer deref of a managed string tags tyAnsiString,
        but indexing a multidimensional array (`s[i]` where s is `array of array
        of AnsiString`) yields a SUB-ARRAY that also tags tyAnsiString (its base
        element type). Require dyn depth 0 so only a true scalar string matches. }
      Result := (IntToTypeKind(ASTTk[node]) = tyAnsiString) and
                (NodeDynDepth(node) = 0);
  end;
end;

function NodeDynBaseRec(node: Integer): Integer;
{ Base element record id of a (possibly nested) dynamic-array expression. }
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].ElemRecName
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseRec(ASTLeft[node]);
end;

function NodeDynBaseSym(node: Integer): Integer;
{ Root dynamic-array symbol of a (possibly nested) index expression, or -1. }
begin
  Result := -1;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := ASTIVal[node];
  end
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseSym(ASTLeft[node]);
end;

function DynElemSize(depth: Integer; baseTk: TTypeKind; baseRec: Integer): Integer;
{ Stride of one element of a dynamic array at the given depth. depth>1 holds
  pointer-sized sub-array handles; depth=1 holds base elements. }
begin
  if depth > 1 then
    Result := TARGET_PTR_SIZE
  else if baseTk = tyRecord then
    Result := RecSize(baseRec)
  else
    Result := TypeSize(baseTk);
end;

function IRBitMask(width: Integer): Int64;
var i: Integer; m: Int64;
begin
  m := 0;
  for i := 0 to width - 1 do
    m := (m shl 1) or 1;
  Result := m;
end;

function IRBitStorageTk(bytes: Integer): TTypeKind;
begin
  if bytes <= 1 then Result := tyUInt8
  else if bytes = 2 then Result := tyUInt16
  else if bytes <= 4 then Result := tyUInt32
  else Result := tyUInt64;   { long-long bitfield: a >4-byte storage unit loads 8 bytes }
end;

function IRLowerBitFieldRead(fieldNode: Integer; storageAddr: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift: Integer; fieldName: AnsiString; value, maskNode: Integer;
    fieldTk: TTypeKind; signBit: Int64; sbNode: Integer;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  fieldTk := RecFieldType(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  value := IRAppend(IR_LOAD_MEM, storageAddr, -1, -1, 0, Ord(storageTk));
  if shift > 0 then
    value := IRAppend(IR_BINOP, value,
                      IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                      Ord(tkIdent), 0, Ord(storageTk));
  maskNode := IRAppend(IR_CONST_INT, -1, -1, -1, IRBitMask(width), Ord(storageTk));
  Result := IRAppend(IR_BINOP, value, maskNode, Ord(tkAnd), 0, Ord(storageTk));

  { A SIGNED bitfield stores a two's-complement value in `width` bits, so the mask
    above hands it back ZERO-extended: `signed f : 7` holding -5 reads as 123. C says
    -5. Sign-extend it branchlessly with (v xor signBit) - signBit -- no arithmetic
    shift, no new IR op, correct for every width.

    Applies to EVERY signed field, whatever its width: IRBitStorageTk always picks an
    UNSIGNED storage type (tyUInt8/16/32), so the load is zero-extended even when the
    field exactly fills its unit. Guarding on `width < storage bits` (as this first
    did) left `signed f : 8` in a one-byte unit reading -7 back as 249. An unsigned
    field must of course stay zero-extended.

    csmith found this on its fourth program, and every signed bitfield in every
    generated program was wrong. The C corpora (lua/sqlite/tcc) never caught it
    because their bitfields are unsigned -- the bug was invisible to a decade of
    real-world C. }
  { C integer promotion: a bitfield NARROWER than int reads as a SIGNED int —
    every value of a sub-int field fits, so both signed and unsigned sub-int fields
    promote to `int`, and downstream signed-vs-unsigned arithmetic (subtraction,
    modulo, division, comparison) is chosen from THIS node's type. The prior code
    sign-extended in the (unsigned) storage type and left the result tagged
    unsigned, so `bit.i % bit.u` did an UNSIGNED modulo (bf-sign-2.c, bitfld-1.c,
    the gcc-torture bitfield cluster). Do the whole extension in the 32-bit
    tyInteger domain: first re-mask to a clean zero-extended value (clears garbage
    above `width` left by a sub-int storage-width op), then sign-extend if the field
    is signed. Full-width (:32) and long-long bitfields can't fit in int, so they
    keep the storage-type extension path below. }
  if width < 32 then
  begin
    maskNode := IRAppend(IR_CONST_INT, -1, -1, -1, IRBitMask(width), Ord(tyInteger));
    Result := IRAppend(IR_BINOP, Result, maskNode, Ord(tkAnd), 0, Ord(tyInteger));
    if ((fieldTk = tyInt8) or (fieldTk = tyInt16) or (fieldTk = tyInt32) or
        (fieldTk = tyInt64) or (fieldTk = tyInteger) or (fieldTk = tyNativeInt)) then
    begin
      signBit := IRBitMask(width) - (IRBitMask(width) div 2);   { = 1 shl (width-1) }
      sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(tyInteger));
      Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkXor), 0, Ord(tyInteger));
      sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(tyInteger));
      Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkMinus), 0, Ord(tyInteger));
    end;
  end
  else if ((fieldTk = tyInt8) or (fieldTk = tyInt16) or (fieldTk = tyInt32) or
           (fieldTk = tyInt64) or (fieldTk = tyInteger) or (fieldTk = tyNativeInt)) then
  begin
    { Full-width / long-long signed bitfield: sign-extend in the storage type. }
    signBit := IRBitMask(width) - (IRBitMask(width) div 2);   { = 1 shl (width-1) }
    sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(storageTk));
    Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkXor), 0, Ord(storageTk));
    sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(storageTk));
    Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkMinus), 0, Ord(storageTk));
  end;
end;

function IRLowerBitFieldStore(fieldNode, rhsValue: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift, addr, oldVal, clearMask, newBits, maskedNew, maskNode: Integer;
    fieldName: AnsiString; mask, shiftedMask: Int64;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  addr := IRLowerAddress(fieldNode);
  mask := IRBitMask(width);
  shiftedMask := mask shl shift;
  oldVal := IRAppend(IR_LOAD_MEM, addr, -1, -1, 0, Ord(storageTk));
  clearMask := IRAppend(IR_BINOP, oldVal,
                        IRAppend(IR_CONST_INT, -1, -1, -1, not shiftedMask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  maskedNew := IRAppend(IR_BINOP, rhsValue,
                        IRAppend(IR_CONST_INT, -1, -1, -1, mask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  if shift > 0 then
    maskedNew := IRAppend(IR_BINOP, maskedNew,
                          IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                          Ord(tkShl), 0, Ord(storageTk));
  newBits := IRAppend(IR_BINOP, clearMask, maskedNew, Ord(tkOr), 0, Ord(storageTk));
  Result := IRAppend(IR_STORE_MEM, addr, newBits, -1, 0, Ord(storageTk));
end;

{ ===== PROMOTABLE INT lowering (feature-a-promotable-int stage 3) =====

  A promotable-int slot is two native machine words: the storage tag, then the
  inline payload (a machine int) or a managed AnsiString ref holding the
  serialized bignum. compiler/builtin/promocore.pas owns that layout and every
  operation on it.

  An rvalue is the slot ADDRESS, not the payload. Stage 2 used the payload —
  which is why stage 2 was small — but that model cannot survive a value that
  may be a bignum: the payload is then a pointer and any integer op on it
  computes garbage. So this follows the tyVariant model instead
  (decide-promoint-rvalue-representation, Option A): every operation is a
  runtime helper taking slot addresses, which also means all six backends work
  with no backend changes. The inline fast path lives INSIDE the helpers, so a
  value that never leaves int64 never touches the heap.

  Stage 4 (check elision) is what inlines the fast path back into the caller. }

{ An integer literal too wide for Int64, carrying its digit text.

  The tyInt64 test is load-bearing: a CHAR literal is also an AN_INT_LIT with a
  char-pool span (the case-of-string label path keys off exactly that), so
  "has a span" alone would misread `'a'` as a wide number. }
function IsWideIntLit(node: Integer): Boolean;
begin
  { tyPromoInt64 is the NilPy typing of the same wide literal (ints are
    arbitrary precision there); the span still carries the exact digits. }
  IsWideIntLit := (ASTKind[node] = AN_INT_LIT) and (ASTSLen[node] > 0) and
                  ((ASTTk[node] = Ord(tyInt64)) or (ASTTk[node] = Ord(tyPromoInt64)));
end;

{ `-<wide literal>`. The digit text the lexer preserved carries NO sign, and
  ASTIVal holds only the wrapped reading, so the negation has to be applied to
  the parsed bignum rather than to either of those. }
function IsWideNegLit(node: Integer): Boolean;
begin
  IsWideNegLit := (ASTKind[node] = AN_NEG) and IsWideIntLit(ASTLeft[node]);
end;

function PromoPayloadOffset(tk: TTypeKind): Integer;
begin
  PromoPayloadOffset := TypeSize(tk) div 2;
end;

{ Call a promocore runtime routine, given already-lowered argument nodes.

  IR_ARG nodes form a LINKED chain: IRB points at the next argument. Building
  them without that link produced a call that read its second argument from
  garbage and segfaulted with a perfectly plausible-looking IR dump — the arg
  nodes are all there, just not joined. }
function IRPromoCall(const fname: AnsiString; a0, a1, a2: Integer; retTk: TTypeKind): Integer;
var cpi, arg0, arg1, arg2: Integer;
begin
  cpi := FindProc(fname);
  if cpi < 0 then
    Error('promotable int: runtime helper ' + fname + ' not found (promocore unit not loaded)');
  arg0 := IRAppend(IR_ARG, a0, -1, -1, 0, Ord(tyPointer));
  arg1 := -1;
  arg2 := -1;
  if a1 >= 0 then
  begin
    arg1 := IRAppend(IR_ARG, a1, -1, -1, 0, IRTk[a1]);
    IRB[arg0] := arg1;
  end;
  if a2 >= 0 then
  begin
    arg2 := IRAppend(IR_ARG, a2, -1, -1, 0, IRTk[a2]);
    IRB[arg1] := arg2;
  end;
  IRPromoCall := IRAppendCall(cpi, arg0, -1, Ord(retTk));
end;

{ Three- and four-argument variants of IRPromoCall. Same linked IR_ARG chain
  (IRB = next argument) — see IRPromoCall for why that link is load-bearing. }
function IRPromoCall3(const fname: AnsiString; a0, a1, a2: Integer; retTk: TTypeKind): Integer;
var cpi, g0, g1, g2: Integer;
begin
  cpi := FindProc(fname);
  if cpi < 0 then Error('promotable int: runtime helper ' + fname + ' not found');
  g0 := IRAppend(IR_ARG, a0, -1, -1, 0, Ord(tyPointer));
  g1 := IRAppend(IR_ARG, a1, -1, -1, 0, Ord(tyPointer));
  g2 := IRAppend(IR_ARG, a2, -1, -1, 0, IRTk[a2]);
  IRB[g0] := g1; IRB[g1] := g2;
  IRPromoCall3 := IRAppendCall(cpi, g0, -1, Ord(retTk));
end;

function IRPromoCall4(const fname: AnsiString; a0, a1, a2, a3: Integer; retTk: TTypeKind): Integer;
var cpi, g0, g1, g2, g3: Integer;
begin
  cpi := FindProc(fname);
  if cpi < 0 then Error('promotable int: runtime helper ' + fname + ' not found');
  g0 := IRAppend(IR_ARG, a0, -1, -1, 0, Ord(tyPointer));
  g1 := IRAppend(IR_ARG, a1, -1, -1, 0, Ord(tyPointer));
  g2 := IRAppend(IR_ARG, a2, -1, -1, 0, Ord(tyPointer));
  g3 := IRAppend(IR_ARG, a3, -1, -1, 0, IRTk[a3]);
  IRB[g0] := g1; IRB[g1] := g2; IRB[g2] := g3;
  IRPromoCall4 := IRAppendCall(cpi, g0, -1, Ord(retTk));
end;

{ The OBJECT link of the variant-comparison chain below, in exactly the shape
  PXXPromoVarCmpTry already uses one link up: call a TRY that answers
  0 = not handled / 1 = False / 2 = True, and when it declines, run the
  comparison that was going to run anyway — untouched.

  Why a try and not a replacement, which is what the first three cuts were:
  `IR_VAR_BINOP` is not a routine to be swapped out. On x86-64 it is INLINE
  emitted code (EmitVarBinOp) carrying its own None-equality arm, its own
  char/string arms and its own numeric double-dispatch; builtinheap's
  PXXVarBinOp is a DIFFERENT implementation of the same operator for the other
  backends. Substituting either one for the whole fallback broke, in order:
  promotable ints, `is` vs `==`, char-vs-string, and `0 == None`. A try that
  declines cannot regress a case it never sees, and every non-object comparison
  now emits byte-for-byte the instruction it emitted before.

  What it buys: `a == xs[0]` reaches a user `__eq__`. The compile-time dunder
  arms key on both operands' STATIC class, so the dunder worked for two named
  locals and silently compared payloads the moment either side was a container
  element, a for-in variable or an unannotated parameter — which is where
  objects normally live in Python
  (bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant).

  `is` declines too: it lowers to the SAME tkEq node and is told apart only by
  PY_BINOP_IDENTITY, the marker the by-contents arms above already consult. }
function IRPyVarEqTry(left, right, item, node: Integer): Integer;
var cpi, g0, g1, g2, varIdx, elseLabel, endLabel, trySym: Integer;
begin
  IRPyVarEqTry := -1;
  if not isNilPy then Exit;
  if (item <> Ord(tkEq)) and (item <> Ord(tkNeq)) then Exit;
  if (node >= 0) and (ASTSLen[node] = PY_BINOP_IDENTITY) then Exit;
  cpi := FindProc('pyvar_eqv');
  if cpi < 0 then Exit;

  trySym := AllocVar('', tyInteger);
  g0 := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyPointer));
  g1 := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyPointer));
  g2 := IRAppend(IR_ARG,
          IRAppend(IR_CONST_INT, -1, -1, -1, Ord(item = Ord(tkNeq)), Ord(tyInt64)),
          -1, -1, 0, Ord(tyInt64));
  IRB[g0] := g1; IRB[g1] := g2;
  IRAppend(IR_STORE_SYM, trySym, IRAppendCall(cpi, g0, -1, Ord(tyInt64)),
           -1, 0, Ord(tyInteger));

  varIdx := AllocVar('', tyBoolean);
  elseLabel := IRNewLabel;
  endLabel := IRNewLabel;
  IRAppend(IR_JUMP_IF_FALSE, elseLabel,
           IRAppend(IR_LOAD_SYM, trySym, -1, -1, 0, Ord(tyInteger)), -1, 0, 0);
  IRAppend(IR_STORE_SYM, varIdx,
           IRAppend(IR_BINOP,
                    IRAppend(IR_LOAD_SYM, trySym, -1, -1, 0, Ord(tyInteger)),
                    IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                    Ord(tkMinus), 0, Ord(tyInteger)), -1, 0, Ord(tyBoolean));
  IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
  IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
  IRAppend(IR_STORE_SYM, varIdx,
           IRAppend(IR_VAR_BINOP, left, right, item, 0, Ord(tyBoolean)),
           -1, 0, Ord(tyBoolean));
  IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
  IRPyVarEqTry := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
end;

{ …and the plain fallback, wrapped so both call sites read the same. }
function IRPyVarEqFallback(left, right, item, node: Integer): Integer;
var r: Integer;
begin
  r := IRPyVarEqTry(left, right, item, node);
  if r >= 0 then IRPyVarEqFallback := r
  else IRPyVarEqFallback := IRAppend(IR_VAR_BINOP, left, right, item, 0, Ord(tyBoolean));
end;


{ A fresh promo temp slot, zeroed so its tag starts INLINE. }
function IRPromoTempSlot(var symOut: Integer): Integer;
var tmpSym: Integer;
begin
  tmpSym := AllocVar('', tyPromoInt64);
  { First-touch init: ONE prologue zero via the hidden-arg-temp machinery (the
    tag word reads PROMO_TAG_INLINE), not a per-visit PXXPromoInit statement.
    The per-visit init re-executed inside a loop and blindly re-tagged the slot
    INLINE while it still held last iteration's HEAP payload — orphaning one
    managed allocation per pass, which is what made uforth's empty DO LOOP grow
    without bound (bug-a-runtime-variant-heap-grows-unbounded; the boundary
    check runs `& 0xFFFFFFFFFFFFFFFF` every iteration). Every writer of an
    ALREADY-VALID slot (PXXPromoFromInt / FromStr / StoreBig) releases the old
    payload itself, so a zeroed first state is all the init must provide. }
  SymIsHiddenArgTemp[tmpSym] := True;
  symOut := tmpSym;
  IRPromoTempSlot := IRAppend(IR_SLOTADDR, tmpSym, -1, -1, 0, Ord(tyPointer));
end;

{ Initialise a promo slot from a literal form that cannot go through
  PXXPromoFromInt because its value does not fit 64 bits. Returns False when the
  node is not such a literal. }
function IRPromoInitFromLiteral(dstAddr, node: Integer): Boolean;
var litNode, zeroAddr, zeroSym, strSym: Integer;
begin
  IRPromoInitFromLiteral := False;
  if IsWideIntLit(node) then litNode := node
  else if IsWideNegLit(node) then litNode := ASTLeft[node]
  else Exit;
  { The digit text must reach PXXPromoFromStr through a hidden OWNING string
    local, not as a bare IR_CONST_STR argument: IRPromoCall builds its IR
    directly and bypasses the AST call path's materialised-managed-arg
    owning-local machinery, so the per-call refcount-1 handle had no owner and
    leaked one string per evaluation — a wide mask constant inside a loop grew
    the heap without bound (bug-a-runtime-variant-heap-grows-unbounded). The
    store releases the previous iteration's handle; scope exit releases the
    last. }
  strSym := AllocVar('', tyAnsiString);
  SymIsHiddenArgTemp[strSym] := True;
  IRMarkStatementNode(IRAppend(IR_STORE_SYM, strSym,
    IRAppend(IR_CONST_STR, ASTSOffset[litNode], ASTSLen[litNode],
             -1, 0, Ord(tyString)), -1, 0, Ord(tyAnsiString)));
  IRMarkStatementNode(IRPromoCall('PXXPromoFromStr', dstAddr,
                        IRAppend(IR_LOAD_SYM, strSym, -1, -1, 0, Ord(tyAnsiString)),
                        -1, tyUnknown));
  if IsWideNegLit(node) then
  begin
    { negate in place: dst := 0 - dst. A fresh temp slot is already inline 0. }
    zeroAddr := IRPromoTempSlot(zeroSym);
    IRMarkStatementNode(IRPromoCall('PXXPromoSub', dstAddr, zeroAddr, dstAddr, tyUnknown));
  end;
  IRPromoInitFromLiteral := True;
end;

{ Emit a promotable-int binop writing its result into dstAddr.

  Factored out so an ASSIGNMENT can hand it the TARGET's slot directly instead
  of computing into a temp and copying: `p := p + n` then costs one runtime call
  rather than three (init temp, add, copy). Aliasing dst with an operand is safe
  — every helper reads its operands into locals before storing. }
procedure IRPromoEmitBinop(dstAddr, node: Integer); forward;

{ The slot ADDRESS of an expression usable as a promotable int. A promo-typed
  expression already IS a slot; an ordinary integer expression is boxed into a
  fresh temp slot first, which is what makes `p + 1` and `p + n` work without
  any special case at the operator. }
function IRPromoAddrOf(node: Integer): Integer;
var tmpSym, addr, value: Integer;
begin
  { A wide LITERAL may itself be typed tyPromoInt64 (NilPy), but it is not a
    slot — it must take the boxing path below, where IRPromoInitFromLiteral
    consumes the digit text. Checked before the promo-typed branch, which
    would otherwise hand the wrapped machine constant back as a slot address. }
  if (not IsWideIntLit(node)) and (not IsWideNegLit(node)) and
     TypeIsPromoInt(IntToTypeKind(ASTTk[node])) then
  begin
    if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
       TypeIsPromoInt(Syms[ASTIVal[node]].TypeKind) and
       Syms[ASTIVal[node]].IsRef then
      { A promo PARAMETER is by-ref, like every other aggregate parameter: the
        slot lives in the caller's hidden temp and the cell here holds its
        ADDRESS. IR_LEA resolves through that (it is what `@n` already lowers
        to); IR_SLOTADDR would hand back the address OF THE CELL, i.e. a pointer
        to a pointer, and the runtime would read the address as a TAG word
        (bug-a-promoint-parameter-cannot-be-used-at-all). }
      IRPromoAddrOf := IRAppend(IR_LEA, ASTIVal[node], -1, -1, 0, Ord(tyPointer))
    else if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
       TypeIsPromoInt(Syms[ASTIVal[node]].TypeKind) then
      IRPromoAddrOf := IRAppend(IR_SLOTADDR, ASTIVal[node], -1, -1, 0, Ord(tyPointer))
    else
      { already lowered to a slot address by the binop path }
      IRPromoAddrOf := IRLowerAST(node);
    Exit;
  end;
  addr := IRPromoTempSlot(tmpSym);
  if not IRPromoInitFromLiteral(addr, node) then
  begin
    value := IRLowerAST(node);
    IRMarkStatementNode(IRPromoCall('PXXPromoFromInt', addr, value, -1, tyUnknown));
  end;
  IRPromoAddrOf := IRAppend(IR_SLOTADDR, tmpSym, -1, -1, 0, Ord(tyPointer));
end;

{ The mixed promo-with-machine-int form of this operator, if it has one. Only
  the operators where the right operand can stay a machine int; div/mod are
  excluded because their sign rules are worth keeping in ONE place. }
function PromoMixedHelper(op: TTokenKind): AnsiString;
begin
  PromoMixedHelper := '';
  if op = tkPlus then PromoMixedHelper := 'PXXPromoAddInt'
  else if op = tkMinus then PromoMixedHelper := 'PXXPromoSubInt'
  else if op = tkStar then PromoMixedHelper := 'PXXPromoMulInt';
end;

{ Which promocore helper implements this operator token. }
function PromoOpHelper(op: TTokenKind): AnsiString;
begin
  PromoOpHelper := '';
  if op = tkPlus then PromoOpHelper := 'PXXPromoAdd'
  else if op = tkMinus then PromoOpHelper := 'PXXPromoSub'
  else if op = tkStar then PromoOpHelper := 'PXXPromoMul'
  { NilPy's `//` and `%` FLOOR; Pascal's `div`/`mod` truncate. The two disagree
    only on negative operands, and disagreeing SILENTLY is exactly the failure
    mode here — `-7 % 3` answered -1 where Python says 2. Chosen by language
    mode at the one place every promo binop site already asks. }
  else if (op = tkDiv) and PyProgramMode then PromoOpHelper := 'PXXPromoFloorDiv'
  else if (op = tkMod) and PyProgramMode then PromoOpHelper := 'PXXPromoFloorMod'
  else if op = tkDiv then PromoOpHelper := 'PXXPromoDiv'
  else if op = tkMod then PromoOpHelper := 'PXXPromoMod'
  else if op = tkAnd then PromoOpHelper := 'PXXPromoAnd'
  else if op = tkOr then PromoOpHelper := 'PXXPromoOr'
  else if op = tkXor then PromoOpHelper := 'PXXPromoXor'
  else if op = tkShl then PromoOpHelper := 'PXXPromoShl'
  else if op = tkShr then PromoOpHelper := 'PXXPromoShr'
  { Pascal's `shr` is lexed as an IDENTIFIER — there is no tkShr token for it —
    and the term parser stores Ord(tkIdent) as the operator. That is the
    repo-wide convention (see IRLowerSetBitMutate and the shift arm of every
    backend), so it must not be "fixed" in the lexer; the promo path simply has
    to know it. Without this arm PromoOpHelper answered '' for `n shr k`, the
    promo branch declined the node, and the generic integer path shifted two
    SLOT ADDRESSES — then the promo store read the result as a slot and died in
    SlotTag. `shl` was fine because it has a real token, which is exactly why
    the pair looked like a one-operator bug.
    In a BINOP, tkIdent is only ever `shr`: the parser admits it solely when the
    identifier text is 'shr'. }
  else if op = tkIdent then PromoOpHelper := 'PXXPromoShr';
end;

{ Box a promotable-int-typed expression (or a wide literal) into a fresh
  variant temp and return the temp's ADDRESS — the shape the variant binop
  wants for a mixed `variant ⊕ promo` operand. An INLINE value becomes an
  ordinary VT_INT64 variant; only a heap value takes VT_PROMO_INT64. The temp
  is an ordinary variant local (prologue-zeroed, epilogue-cleared). }
function IRPromoBoxedVariantAddr(node: Integer): Integer;
var vSym: Integer;
begin
  vSym := AllocVar('', tyVariant);
  { PXXPromoToVariant CLEARS the destination first, which READS the old tag —
    a garbage tag releases a wild AnsiString. Flag the temp for the prologue
    nil-init pass like every other hidden variant temp. }
  SymIsHiddenArgTemp[vSym] := True;
  IRMarkStatementNode(IRPromoCall('PXXPromoToVariant',
                        IRAppend(IR_LEA, vSym, -1, -1, 0, Ord(tyPointer)),
                        IRPromoAddrOf(node), -1, tyUnknown));
  IRPromoBoxedVariantAddr := IRAppend(IR_LEA, vSym, -1, -1, 0, Ord(tyPointer));
end;

procedure IRPromoEmitBinop(dstAddr, node: Integer);
var lhsAddr, rhsAddr: Integer;
begin
  lhsAddr := IRPromoAddrOf(ASTLeft[node]);
  { RIGHT operand an ordinary integer and the operator has a mixed form: take
    the machine int directly instead of boxing it into a slot first. That is the
    shape almost all real code has — accumulators, counters, small constants. }
  if (not TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]]))) and
     (not IsWideIntLit(ASTRight[node])) and
     (not IsWideNegLit(ASTRight[node])) and
     (PromoMixedHelper(TTokenKind(ASTIVal[node])) <> '') then
    IRMarkStatementNode(IRPromoCall(PromoMixedHelper(TTokenKind(ASTIVal[node])),
                                    dstAddr, lhsAddr,
                                    IRLowerAST(ASTRight[node]), tyUnknown))
  else
  begin
    rhsAddr := IRPromoAddrOf(ASTRight[node]);
    IRMarkStatementNode(IRPromoCall(PromoOpHelper(TTokenKind(ASTIVal[node])),
                                    dstAddr, lhsAddr, rhsAddr, tyUnknown));
  end;
end;

function IRLowerAddress(node: Integer): Integer;
var baseNode, baseAddr, indexNode, lo, elemSize: Integer;
    rcSym, rcPi, rcArg, rcArg2: Integer;
    fieldName: AnsiString;
    isArr: Boolean;
    tk: TTypeKind;
    baseDynDepth, dynRootSym, dynBaseRec, slotAddrNode: Integer;
    dynBaseTk: TTypeKind;
    recName, aliasIdx: Integer;
begin
  { Address of an address-of: `&(&x)`. In valid C this only arises from array
    decay (`&arr` where arr is an array yields arr's address), so the address of
    that is the operand's own address. Collapse one level. }
  if ASTKind[node] = AN_ADDR then
  begin
    Result := IRLowerAddress(ASTLeft[node]);
    Exit;
  end;
  { A class/interface CAST is a pure reinterpret, so the address of the cast is
    the address of what was cast: `IFoo(List[i]).M` takes the address of the list
    slot, whose word IS the interface value (an interface value being a single
    instance pointer). Without this the cast-and-call form lowered an address of
    nothing. }
  if (ASTKind[node] = AN_CLASS_CAST) and (ASTLeft[node] >= 0) then
  begin
    if IsASTLValue(ASTLeft[node]) then
      Result := IRLowerAddress(ASTLeft[node])
    else
    begin
      { the cast operand is a VALUE (a getter result — `IFoo(List[i]).M`, where
        List[i] is an indexed property): materialise it into a hidden temp so the
        cast has an address to be taken of. }
      slotAddrNode := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, slotAddrNode, IRLowerAST(ASTLeft[node]), -1, 0, Ord(tyPointer));
      Result := IRAppend(IR_LEA, slotAddrNode, -1, -1, 0, Ord(tyPointer));
    end;
    Exit;
  end;
  { `&function` — a function's address IS the function-pointer value (C `&f == f`).
    The AN_PROCADDR value node already yields the code address. }
  if ASTKind[node] = AN_PROCADDR then
  begin
    Result := IRLowerAST(node);
    Exit;
  end;
  { address-of a compound literal: emit its init statements, then yield the
    temp's address (the temp IS an lvalue). }
  { A same-size lvalue TYPECAST as a var argument (FPC's "variable typecast":
    `ParseToken(..., Cardinal(FTokenLength), ...)` in Pascal Script) — the
    address is the underlying lvalue's; the cast changes only the static
    view. Peel the cast and recurse. }
  if (ASTKind[node] = AN_PTR_CAST) and (ASTLeft[node] >= 0) and
     ((ASTKind[ASTLeft[node]] = AN_IDENT) or (ASTKind[ASTLeft[node]] = AN_FIELD) or
      (ASTKind[ASTLeft[node]] = AN_INDEX) or (ASTKind[ASTLeft[node]] = AN_DEREF)) then
  begin
    Result := IRLowerAddress(ASTLeft[node]);
    Exit;
  end;
  if ASTKind[node] = AN_COMPOUND_LITERAL then
  begin
    IRMarkStatementNode(IRLowerAST(ASTLeft[node]));
    Result := IRAppend(IR_LEA, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
    Exit;
  end;
  if ASTKind[node] = AN_IDENT then
  begin
    Result := IRAppend(IR_LEA, ASTIVal[node], -1, -1, 0, Ord(tyPointer));
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    { Pointer indexing p[i]: base address is the pointer's VALUE (not &p), and
      the stride is the pointed-at element size. Arrays fall through below. }
    if (ASTKind[baseNode] = AN_IDENT) and
       (Syms[ASTIVal[baseNode]].TypeKind = tyPointer) and
       (not Syms[ASTIVal[baseNode]].IsArray) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      tk := Syms[ASTIVal[baseNode]].PtrElemTk;
      if tk = tyRecord then
        elemSize := RecSize(Syms[ASTIVal[baseNode]].PtrElemRec)
      else
        elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
      Exit;
    end;
    { Array compound literal indexing `(int[]){..}[i]`: the CL decays to a pointer
      whose VALUE is the temp's base address (IRLowerAST emits the init + IR_LEA);
      stride is the element size. Mirrors the AN_IDENT pointer path. }
    if (ASTKind[baseNode] = AN_COMPOUND_LITERAL) and Syms[ASTIVal[baseNode]].IsArray then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      tk := Syms[ASTIVal[baseNode]].ElemType;
      if tk = tyRecord then elemSize := RecSize(Syms[ASTIVal[baseNode]].ElemRecName)
      else elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
      Exit;
    end;
    { Pointer-typed class field indexing FField[i]: base is the field's VALUE
      (the pointer), stride is the pointed-at element size. Mirrors the AN_IDENT
      pointer path above for an AN_FIELD base. }
    if ASTKind[baseNode] = AN_FIELD then
    begin
      recName := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      if (RecFieldType(recName, fieldName) = tyPointer) and
         (not RecFieldIsArray(recName, fieldName)) then
      begin
        indexNode := IRLowerAST(ASTRight[node]);
        tk := RecFieldPtrElemTk(recName, fieldName);
        if tk = tyRecord then
          elemSize := RecSize(RecFieldPtrElemRec(recName, fieldName))
        else
          elemSize := TypeSize(tk);
        baseAddr := IRLowerAST(baseNode);   { field value = the pointer }
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
        Exit;
      end;
    end;
    { Typed-pointer-cast indexing PType(expr)[i]: base is the cast's pointer
      VALUE, stride is the cast's pointed-at element size (from the alias). }
    if ASTKind[baseNode] = AN_PTR_CAST then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      aliasIdx := ASTIVal[baseNode];
      if aliasIdx < 0 then
      begin
        { PChar(expr)[i] / built-in pointer-cast adapter (ASTIVal -2/-1): no
          alias entry, the pointed-at element is a char (byte stride). }
        tk := tyChar;
        elemSize := 1;
      end
      else
      begin
        tk := IntToTypeKind(AliasElemTk[aliasIdx]);
        if tk = tyRecord then
          elemSize := RecSize(AliasElemRec[aliasIdx])
        else
          elemSize := TypeSize(tk);
      end;
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
      Exit;
    end;
    { C array-of-pointer indexing followed by another subscript:
      `names[0][1]`. The base `names[0]` is a pointer VALUE stored inside an
      array slot; using IRLowerAddress(base) would index from the slot address
      itself. Load the pointer value, then index the pointed-to element type. }
    if CProgramMode and (ASTKind[baseNode] = AN_INDEX) and
       (IntToTypeKind(ASTTk[baseNode]) = tyPointer) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      tk := IntToTypeKind(ASTTk[node]);
      if tk = tyRecord then
        elemSize := RecSize(ResolveNodeRec(node))
      else
        elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, ASTTk[node]);
      Exit;
    end;
    { Computed pointer-value indexing, e.g. C `(cond ? a : b)[i]`. The base
      expression yields the pointer value; taking IRLowerAddress(base) would ask
      for the address of a non-lvalue expression such as AN_TERNARY. }
    if CProgramMode and
       (ASTKind[baseNode] <> AN_IDENT) and
       (ASTKind[baseNode] <> AN_FIELD) and
       (ASTKind[baseNode] <> AN_PTR_CAST) and
       (ASTKind[baseNode] <> AN_INDEX) and
       IRNodePointerBase(baseNode) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      elemSize := IRPointerStride(baseNode);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, ASTTk[node]);
      Exit;
    end;
    { Nested dynamic-array indexing: base is a nested dyn array (depth>=2) or a
      sub-array element (an AN_INDEX whose value is still a dyn array). The base
      handle is wrapped in IR_DYNUNIQUE, which loads the data pointer on a read
      and clones-if-shared (copy-on-write) on a write, decided by InLValueWrite
      at codegen time — exactly as the depth-1 path does for the outer array, so
      writing through one alias never mutates another at any depth. Plain depth-1
      arrays keep the path below. }
    baseDynDepth := NodeDynDepth(baseNode);
    if (baseDynDepth >= 2) or
       ((baseDynDepth = 1) and ((ASTKind[baseNode] = AN_INDEX) or
                                (ASTKind[baseNode] = AN_FIELD))) then
    begin
      { Base element metadata, walking to the root symbol OR record/class field
        (a dynamic-array field is just another handle slot). }
      dynBaseTk := NodeDynBaseTk(baseNode);
      dynBaseRec := NodeDynBaseRec(baseNode);
      elemSize := DynElemSize(baseDynDepth, dynBaseTk, dynBaseRec);
      { Address of the slot holding this level's array handle. For a variable
        root the slot is the variable itself; for a field root it is the field
        slot in the object; for a sub-array it is the element address in the
        parent's data (its own IR_DYNUNIQUE chain, so COW recurses upward). }
      if ASTKind[baseNode] = AN_IDENT then
        slotAddrNode := IRAppend(IR_SLOTADDR, ASTIVal[baseNode], -1, -1, 0, Ord(tyPointer))
      else
        slotAddrNode := IRLowerAddress(baseNode);
      baseAddr := IRAppend(IR_DYNUNIQUE, slotAddrNode, baseDynDepth, dynBaseRec,
                           elemSize, Ord(dynBaseTk));
      indexNode := IRLowerAST(ASTRight[node]);
      { {$R+}: bound a depth-1 dyn FIELD's index against the runtime count at
        [data-8] — the handle is re-read from the field slot for the arg
        (pure for an ident.field base; deeper shapes stay unchecked)
        (feature-pascal-range-checks-r-plus). }
      if ASTRChk[node] and (baseDynDepth = 1) and
         (ASTKind[baseNode] = AN_FIELD) and
         (ASTKind[ASTLeft[baseNode]] = AN_IDENT) then
      begin
        rcPi := FindProc('PXXDynIdxChkI64');
        if rcPi >= 0 then
        begin
          rcArg := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_MEM, IRLowerAddress(baseNode), -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
          IRB[rcArg] := IRAppend(IR_ARG, indexNode, -1, -1, 0, Ord(tyInt64));
          indexNode := IRAppendCall(rcPi, rcArg, -1, Ord(tyInt64));
        end;
      end;
      if baseDynDepth >= 2 then
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tyPointer))
      else
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(dynBaseTk));
      Exit;
    end;
    { Indexing a string LITERAL or untyped string const (AN_STR_LIT): its VALUE
      is a pointer to the frozen [len][data] blob (data at +8), and it has no
      addressable slot — so index it like a frozen string but with the literal's
      value as the base (lo=-7 puts index 1 at data[0]). Without this,
      IRLowerAddress(AN_STR_LIT) yields a wrong base and s[i] reads garbage / the
      whole string (bug-const-string-index-miscompiles). }
    if ASTKind[baseNode] = AN_STR_LIT then
    begin
      baseAddr := IRLowerAST(baseNode);
      indexNode := IRLowerAST(ASTRight[node]);
      { IR_INDEX addresses base + (index - lo): the literal's value points at the
        frozen [len8][data] blob, so data[0] is at base+8. Pascal is 1-based
        (s[1] -> data[0], lo=-7); C is 0-based ("lit"[0] -> data[0], lo=-8).
        Without the C offset, "1.3.1"[0] read base+7 (the length word's high
        byte, 0) instead of '1'. }
      if CProgramMode then
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, -8, 1, Ord(tyChar))
      else
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, -7, 1, Ord(tyChar));
      Exit;
    end;
    baseAddr := IRLowerAddress(baseNode);
    indexNode := IRLowerAST(ASTRight[node]);

    { {$R+}: bound the index — covers READS and WRITES alike, since every
      element access lowers its address here. Static 1-D arrays use the
      compile-time bounds; a depth-1 dynamic array asks the runtime count at
      [data-8] via PXXDynIdxChkI64 (the base is re-lowered as the arg — an
      AN_IDENT base has no side effects, so the duplicate emission is just a
      reload; other base shapes are left unchecked for now)
      (feature-pascal-range-checks-r-plus). }
    if ASTRChk[node] and (ASTKind[baseNode] = AN_IDENT) and
       (ASTIVal[baseNode] >= 0) then
    begin
      rcSym := ASTIVal[baseNode];
      { an OPEN-ARRAY param keeps AllocParam's ArrLen=1000 placeholder — its
        real length lives at [data-8] like a dyn array's, so it takes the
        runtime-checked branch below, not fake static bounds. }
      if Syms[rcSym].IsArray and (Syms[rcSym].ArrLen >= 0) and
         not ((Syms[rcSym].Kind = skParam) and (Syms[rcSym].ArrLen = 1000)) and
         (SymArrNDims[rcSym] <= 1) and (SymElemDynDepth[rcSym] = 0) then
        indexNode := IRWrapChkBounds(indexNode,
                       Syms[rcSym].ConstVal,
                       Syms[rcSym].ConstVal + Syms[rcSym].ArrLen - 1)
      else if Syms[rcSym].IsArray and
              ((Syms[rcSym].ArrLen = -1) or
               ((Syms[rcSym].Kind = skParam) and (Syms[rcSym].ArrLen = 1000))) and
              (SymElemDynDepth[rcSym] = 0) then
      begin
        rcPi := FindProc('PXXDynIdxChkI64');
        if rcPi >= 0 then
        begin
          rcArg := IRAppend(IR_ARG, IRLowerAddress(baseNode), -1, -1, 0, Ord(tyPointer));
          rcArg2 := IRAppend(IR_ARG, indexNode, -1, -1, 0, Ord(tyInt64));
          IRB[rcArg] := rcArg2;
          indexNode := IRAppendCall(rcPi, rcArg, -1, Ord(tyInt64));
        end;
      end;
    end
    else if ASTRChk[node] and (ASTKind[baseNode] = AN_FIELD) then
    begin
      { record/class FIELD static array: the parser already normalised the
        index to 0-based, and this path's IR lo stays 0 — so the check is
        [0, count-1] on the normalised index (r.arr[5] on array[1..3]
        raises in FPC). Dyn-array fields and N-D fields stay unchecked for
        now. }
      rcSym := ResolveNodeRec(ASTLeft[baseNode]);
      if (rcSym >= REC_UCLASS_BASE) then
      begin
        rcPi := FindUField(rcSym - REC_UCLASS_BASE, GetASTIdentName(baseNode));
        if (rcPi >= 0) and UFldIsArray[rcPi] and (UFldArrLen[rcPi] >= 0) and
           (UFldDynDepth[rcPi] = 0) and (UFldArrNDims[rcPi] <= 1) then
          indexNode := IRWrapChkBounds(indexNode, 0, UFldArrLen[rcPi] - 1)
        else if (rcPi >= 0) and UFldIsArray[rcPi] and (UFldDynDepth[rcPi] = 1) and
                (ASTKind[ASTLeft[baseNode]] = AN_IDENT) then
        begin
          { depth-1 DYN-ARRAY field: the field slot holds the handle; check
            against the runtime count at [data-8] (the slot address lowering
            is duplicated for the arg — pure for an ident.field base). }
          rcArg2 := FindProc('PXXDynIdxChkI64');
          if rcArg2 >= 0 then
          begin
            rcArg := IRAppend(IR_ARG,
                       IRAppend(IR_LOAD_MEM, IRLowerAddress(baseNode), -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
            IRB[rcArg] := IRAppend(IR_ARG, indexNode, -1, -1, 0, Ord(tyInt64));
            indexNode := IRAppendCall(rcArg2, rcArg, -1, Ord(tyInt64));
          end;
        end;
      end;
    end;

    isArr := IsNodeArray(baseNode);
    if ASTKind[baseNode] = AN_IDENT then
    begin
      tk := Syms[ASTIVal[baseNode]].TypeKind;
      recName := Syms[ASTIVal[baseNode]].RecName;
    end
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      recName := ResolveNodeRec(baseNode);
      tk := RecFieldType(ResolveNodeRec(ASTLeft[baseNode]), GetASTIdentName(baseNode));
    end
    else
    begin
      tk := IntToTypeKind(ASTTk[baseNode]);
      recName := ResolveNodeRec(baseNode);
    end;

    if isArr then
    begin
      if ASTKind[baseNode] = AN_IDENT then
      begin
        if Syms[ASTIVal[baseNode]].RecName = REC_TPARAM then
        begin
          tk := tyRecord;
          recName := REC_TPARAM;
        end
        else
        begin
          tk := Syms[ASTIVal[baseNode]].ElemType;
          recName := Syms[ASTIVal[baseNode]].ElemRecName;
        end;
      end;
    end;
    
    lo := 0;
    if (tk = tyAnsiString) and not isArr then
    begin
      lo := 1;
      elemSize := 1;
      tk := tyChar;
      recName := REC_NONE;
      { A pointer-deref string base (`p^[k]`, p: ^AnsiString): IRLowerAddress
        yields the ADDRESS p points at (the string's frame slot), not the loaded
        char-data handle the AN_IDENT path produces — so index off the string's
        VALUE (the handle) instead. Fixes bug-pascal-ptr-deref-string-index (a
        silent garbage read); unblocks `parallel for` ansistring capture. }
      if ASTKind[baseNode] = AN_DEREF then
        baseAddr := IRLowerAST(baseNode);
    end
    else if TypeIsFrozenString(tk) and not isArr then
    begin
      lo := -7;
      elemSize := 1;
      tk := tyChar;
      recName := REC_NONE;
    end
    else
    begin
      if tk = tyString then
      begin
        if (ASTKind[baseNode] = AN_IDENT) and (Syms[ASTIVal[baseNode]].Kind = skGlobal) then
          elemSize := STRING_CAP + 8
        else
          elemSize := LOCAL_STR_CAP + 8;
      end
      else if (tk = tyFixedString) or (tk = tyShortString) then
      begin
        { array-of-string[N] element stride: the per-element frozen slot size,
          from the array symbol's capacity (matches AllocArray's sizing). }
        if ASTKind[baseNode] = AN_IDENT then
          elemSize := FrozenStrSlotSize(tk, SymStrCap[ASTIVal[baseNode]])
        else
          elemSize := FrozenStrSlotSize(tk, 0);
      end
      else if tk = tyRecord then
        elemSize := RecSize(recName)
      else
        elemSize := TypeSize(tk);

      if ASTKind[baseNode] = AN_IDENT then
      begin
        if Syms[ASTIVal[baseNode]].RecName <> REC_TPARAM then
          lo := Syms[ASTIVal[baseNode]].ConstVal;
      end;
    end;

    { A depth-1 DYNAMIC array / open-array param whose element is a fixed-array
      ROW (`array of T`, T = array[lo..hi] of Base): d[i] must stride a whole
      row, not one base element (bug-pascal-openarray-of-array-param-marshal).
      The IR_INDEX result is the row's base address; a sub-index d[i][j] takes
      the branch below. }
    if isArr and (ASTKind[baseNode] = AN_IDENT) and (ASTIVal[baseNode] >= 0) and
       Syms[ASTIVal[baseNode]].IsArray and
       (SymDynElemRowLen[ASTIVal[baseNode]] > 0) then
    begin
      elemSize := elemSize * SymDynElemRowLen[ASTIVal[baseNode]];
      lo := 0;
    end;
    { Sub-index into a row: base is d[i] (an AN_INDEX over a row-element dyn
      array). Its address is the row base; index with the base element size and
      the row's OWN low bound (`array[1..3]` -> j-1). }
    if (ASTKind[baseNode] = AN_INDEX) and
       (ASTKind[ASTLeft[baseNode]] = AN_IDENT) and
       (ASTIVal[ASTLeft[baseNode]] >= 0) and
       Syms[ASTIVal[ASTLeft[baseNode]]].IsArray and
       (SymDynElemRowLen[ASTIVal[ASTLeft[baseNode]]] > 0) then
      lo := SymDynElemRowLo[ASTIVal[ASTLeft[baseNode]]];

    { A FIXED array whose element is a dynamic array (`array[..] of TA`) stores a
      pointer-sized handle per slot, regardless of the element base type's own
      size — override the stride so a[i] addresses the right slot, and tag the
      slot-address node tyPointer (like a nested dyn sub-array element) so Length
      / indexing treat a[i] as a dyn-array handle, not a base value. }
    if isArr and (ASTKind[baseNode] = AN_IDENT) and
       Syms[ASTIVal[baseNode]].IsArray and (Syms[ASTIVal[baseNode]].ArrLen <> -1) and
       (SymElemDynDepth[ASTIVal[baseNode]] > 0) then
    begin
      elemSize := TARGET_PTR_SIZE;
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, lo, elemSize, Ord(tyPointer));
      Exit;
    end;

    Result := IRAppend(IR_INDEX, baseAddr, indexNode, lo, elemSize, ASTTk[node]);
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseNode := ASTLeft[node];
    { A class-typed base holds a POINTER to the object, so the field offset must
      be applied to that pointer's VALUE, not to the address of the slot holding
      it. This is true for any class-typed base — a variable (a.b), a class-typed
      field (a.b.c), an index, etc. — so evaluate the base as a value when it is
      class-typed, and take its address only for embedded (record) bases. }
    if ASTTk[baseNode] = Ord(tyClass) then
      baseAddr := IRLowerAST(baseNode)
    else if ((ASTKind[baseNode] = AN_CALL) or (ASTKind[baseNode] = AN_VIRTUAL_CALL))
            and ((ASTTk[baseNode] = Ord(tyRecord)) or (ASTTk[baseNode] = Ord(tyVariant))) then
      { Record-returning call result used as a field base (f(args).field): the
        call's IR value is the address of its hidden aggregate-result temp
        (aggregates are returned by-reference), so use it directly rather than
        trying to take the address of a call node. }
      baseAddr := IRLowerAST(baseNode)
    else
      baseAddr := IRLowerAddress(baseNode);

    recName := ResolveNodeRec(baseNode);
    fieldName := GetASTIdentName(node);
    { A dynamic-array field slot holds a heap handle (pointer); tag the address
      node tyPointer so Length / indexing treat it as a handle slot, like a
      nested sub-array element. }
    if RecFieldDynDepth(recName, fieldName) > 0 then
      Result := IRAppend(IR_FIELD, baseAddr, -1, -1, RecFieldOffset(recName, fieldName), Ord(tyPointer))
    else
      Result := IRAppend(IR_FIELD, baseAddr, -1, -1, RecFieldOffset(recName, fieldName), ASTTk[node]);
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    Result := IRLowerAST(ASTLeft[node]);
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    { The cast result is the pointer value itself; use it as the address.
      IRLowerAST(inner) evaluates the integer/pointer expression -> rax = address. }
    Result := IRLowerAST(ASTLeft[node]);
  end
  else if (ASTKind[node] = AN_AS_CAST) and UClsIsInterface[Integer(ASTIVal[node])] then
  begin
    { `obj as IFoo` is an interface lvalue: the address of its fat-pointer temp. }
    Result := IRAppend(IR_LEA, IRMaterializeIntfCast(node, True), -1, -1, 0, Ord(tyPointer));
  end
  else if ((ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_VIRTUAL_CALL)) and
          ((ASTTk[node] = Ord(tyRecord)) or (ASTTk[node] = Ord(tyVariant)) or
           (ASTTk[node] = Ord(tyAnsiString)) or
           TypeIsFrozenString(IntToTypeKind(ASTTk[node]))) then
    { Aggregate/variant-returning call in an address position: its IR value IS
      the hidden-destination address (RetViaHiddenDest), so lower the call.

      STRING-returning calls join them. For a managed string the call's value is
      the HANDLE, and a handle is exactly what an index base wants — the same
      thing IR_LEA yields for a string variable in read position — so lowering
      the call gives the right base. For a frozen string the call already
      returns a hidden-destination ADDRESS, so it fits the original rule.

      Without this, indexing a string-returning METHOD call fell through to the
      IR_UNSUPPORTED tail: `c.GetS[1]`, and therefore `c.SomeStringProperty[1]`
      whose read specifier is a getter, refused to compile with "frontend could
      not lower AST node (kind 8)". A plain function call was already fine,
      which is what made it look like a property bug rather than a call-shape
      one. bug-p-index-getter-backed-string-property }
    Result := IRLowerAST(node)
  else
    Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTLeft[node], ASTRight[node], ASTIVal[node], ASTTk[node]);
end;

function IRBuildHiddenDest(procIdx: Integer): Integer;
{ Allocate the caller-owned scratch destination for a call that returns an
  aggregate / frozen string by hidden pointer, and return its IR_LEA address node.
  The direct-call path inlines this in IRAppendCall (IRC = the dest); virtual /
  indirect calls store the returned node in IRCallDest[callNode]. }
var scratchSym, savedRecId: Integer;
begin
  savedRecId := LastTypeRecId;
  if Procs[procIdx].RetType = tyRecord then LastTypeRecId := ProcRetRecId[procIdx];
  { A FIXED-ARRAY result needs a scratch of the WHOLE array, not of one element:
    Procs[].RetType carries the element kind, so AllocVar would reserve 4 bytes
    for a 12-byte answer and the callee's copy would run off the end. Byte array
    of the recorded size — the destination is only ever memcpy'd into and out of.
    bug-a-set-and-array-function-results-come-back-empty }
  if ProcRetFixedArrBytes[procIdx] > 0 then
    scratchSym := AllocArray('', tyUInt8, 0, ProcRetFixedArrBytes[procIdx] - 1)
  else
    scratchSym := AllocVar('', Procs[procIdx].RetType);
  LastTypeRecId := savedRecId;
  if (Procs[procIdx].RetType = tyRecord) and RecordHasManagedFields(ProcRetRecId[procIdx]) then
    SymIsHiddenArgTemp[scratchSym] := True;
  Result := IRAppend(IR_LEA, scratchSym, -1, -1, 0, Ord(tyPointer));
end;

function IRAppendCall(procIdx, firstArg, classIdx, tk: Integer): Integer;
var scratchSym, scratchAddr, savedRecId: Integer;
begin
  if ABIRetViaHiddenDestProc(procIdx) then
  begin
    { Aggregate (and frozen-string) calls return into caller-owned storage. IRC carries an IR_LEA
      node for that hidden destination; ordinary calls keep the class index. }
    savedRecId := LastTypeRecId;
    if Procs[procIdx].RetType = tyRecord then
      LastTypeRecId := ProcRetRecId[procIdx];
    { see IRBuildHiddenDest: a fixed-array result needs the whole array }
    if ProcRetFixedArrBytes[procIdx] > 0 then
      scratchSym := AllocArray('', tyUInt8, 0, ProcRetFixedArrBytes[procIdx] - 1)
    else
      scratchSym := AllocVar('', Procs[procIdx].RetType);
    LastTypeRecId := savedRecId;
    { This hidden aggregate-result temp is allocated during IR lowering, after the
      parser's prologue zero-init pass. If the call sits on a branch that is not
      taken (e.g. `Result := F(0); Exit` in an untaken early-exit), the temp is
      never filled, yet the proc's scope-exit cleanup would release its managed
      fields and free stack garbage. Mark it so codegen nil-inits its full extent
      before the body. }
    if (Procs[procIdx].RetType = tyRecord) and
       RecordHasManagedFields(ProcRetRecId[procIdx]) then
      SymIsHiddenArgTemp[scratchSym] := True;
    { A variant hidden-dest call OVERWRITES the temp raw (the callee copies 16
      bytes into [dest]), so a managed payload from the temp's previous life —
      the SAME sym on every trip through a loop — leaked once per call: ~40
      B/iter of bound pairs in the uforth env-build, and in PASCAL mode every
      pyeval host-call arg temp (PyHostCall's args.at() results, valgrind's
      top doloop record). The variant-slot protocol is mode-universal (tag-6
      payloads are managed refs even in frozen builds — the EmitVariantClear
      string arm predates all of this), so clear unconditionally. }
    if Procs[procIdx].RetType = tyVariant then
    begin
      { the temp is created mid-body, after the prologue zero-init pass — mark
        it so codegen nil-inits its extent, or the FIRST clear here would
        dispatch on a stale stack tag (the mid-body-local landmine) }
      SymIsHiddenArgTemp[scratchSym] := True;
      savedRecId := FindProc('PXXVarClear');
      if savedRecId >= 0 then
        IRIVal[IRAppend(IR_CALL, savedRecId,
                 IRAppend(IR_ARG,
                   IRAppend(IR_LEA, scratchSym, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer)),
                 -1, 0, Ord(tyUnknown))] := 1;
    end;
    scratchAddr := IRAppend(IR_LEA, scratchSym, -1, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_CALL, procIdx, firstArg, scratchAddr, 0, tk);
  end
  else
    Result := IRAppend(IR_CALL, procIdx, firstArg, classIdx, 0, tk);
end;

function IRResolveCtorProc(node, classIdx: Integer): Integer;
{ The ctor PROC a class-instantiation IR_CALL should call: the overload the
  frontend resolved from the argument types, or — when it recorded none — the
  legacy first-`Create`-by-name match. Every backend open-coded the latter, which
  is blind to overloads, so `TFoo.Create('x')` ran a parameterless Create and
  `TFoo.Create(1)` ran the string one. Shared here so all six backends agree. }
begin
  Result := -1;
  if (node >= 0) and (node < IRCount) then Result := IRCtorProc[node];
  if Result >= 0 then Exit;
  if classIdx >= REC_UCLASS_BASE then
  begin
    Result := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
    if Result >= 0 then Result := UMthProc_[Result];
  end;
end;

function IRNodePointerBase(node: Integer): Boolean;
begin
  Result := IntToTypeKind(ASTTk[node]) = tyPointer;
  if CProgramMode and not Result and
     (IntToTypeKind(ASTTk[node]) <> tyInt64) then
    Result := CNodeDecaysToPointer(node);
end;

function IRPointerStride(node: Integer): Integer;
var elemTk: TTypeKind; recId, aliasIdx: Integer; fieldName: AnsiString;
begin
  elemTk := tyUnknown;
  recId := REC_NONE;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1) then
    begin
      elemTk := Syms[ASTIVal[node]].ElemType;
      recId := Syms[ASTIVal[node]].ElemRecName;
    end
    else
    begin
      elemTk := Syms[ASTIVal[node]].PtrElemTk;
      recId := Syms[ASTIVal[node]].PtrElemRec;
    end;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if CProgramMode and RecFieldIsArray(recId, fieldName) and
       (RecFieldDynDepth(recId, fieldName) = 0) then
    begin
      elemTk := RecFieldType(recId, fieldName);
      recId := ResolveNodeRec(node);
    end
    else
    begin
      elemTk := RecFieldPtrElemTk(recId, fieldName);
      recId := RecFieldPtrElemRec(recId, fieldName);
    end;
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    aliasIdx := ASTIVal[node];
    if aliasIdx >= 0 then
    begin
      elemTk := IntToTypeKind(AliasElemTk[aliasIdx]);
      recId := AliasElemRec[aliasIdx];
    end;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if IRNodePointerBase(ASTLeft[node]) then
      Result := IRPointerStride(ASTLeft[node])
    else
      Result := IRPointerStride(ASTRight[node]);
    Exit;
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and IRNodePointerBase(ASTLeft[ASTRight[node]]) then
      Result := IRPointerStride(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and IRNodePointerBase(ASTRight[ASTRight[node]]) then
      Result := IRPointerStride(ASTRight[ASTRight[node]]);
    Exit;
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      elemTk := IntToTypeKind(ProcRetPtrElemTk[ASTIVal[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
  begin
    Result := IRPointerStride(ASTLeft[node]);
    Exit;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    { `*p` where p is a T**: the deref'd value is a T*, whose ptrdiff stride
      is T's size — pointer size while still more than two levels deep, else
      the base scalar/record size. Without this the case fell through to the
      size-1 default and `++*(p)` stepped BYTES (tcc's TOK_GET walks an int*
      through an int** and read tokens misaligned). }
    if (ASTLeft[node] >= 0) and (ASTKind[ASTLeft[node]] = AN_ADDR) then
    begin
      { `*(&x)` is x itself — same stride as x (tcc's `++*(&mp)` via the
        TOK_GET macro's argument substitution). }
      Result := IRPointerStride(ASTLeft[ASTLeft[node]]);
      Exit;
    end;
    if (ASTLeft[node] >= 0) and (ASTKind[ASTLeft[node]] = AN_IDENT) and
       (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyPointer) and
       (SymPtrDepth[ASTIVal[ASTLeft[node]]] >= 2) then
    begin
      if SymPtrDepth[ASTIVal[ASTLeft[node]]] > 2 then
        elemTk := tyPointer
      else
      begin
        elemTk := IntToTypeKind(SymPtrBaseTk[ASTIVal[ASTLeft[node]]]);
        recId := SymPtrBaseRec[ASTIVal[ASTLeft[node]]];
      end;
    end;
  end
  else if ASTKind[node] = AN_ASSIGN then
  begin
    Result := IRPointerStride(ASTLeft[node]);
    Exit;
  end
  else if ASTKind[node] = AN_ADDR then
  begin
    { `&arr[i]` is a pointer to arr's element, so its ptrdiff stride is the
      element size — which is exactly the indexed base's own stride. Derive it by
      recursing on the base rather than reading the AN_INDEX node's ASTTk (that
      was unreliable and regressed `&wide[204]` where wide is a `const u16*`).
      Other &-forms have no array element and keep the size-1 default. }
    if ASTKind[ASTLeft[node]] = AN_INDEX then
    begin
      Result := IRPointerStride(ASTLeft[ASTLeft[node]]);
      Exit;
    end;
  end;
  if elemTk = tyRecord then
    Result := RecSize(recId)
  else if elemTk = tyUnknown then
    Result := 1
  else
    Result := TypeSize(elemTk);
end;

function IsNodePChar(node: Integer): Boolean;
var tk: TTypeKind; procIdx, recId, symId: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  tk := IntToTypeKind(ASTTk[node]);
  if tk <> tyPointer then Exit;

  { 1. If it's a PChar cast node }
  if (ASTKind[node] = AN_PTR_CAST) and (ASTIVal[node] = -2) then
  begin
    Result := True;
    Exit;
  end;

  { 2. If it's an identifier }
  if ASTKind[node] = AN_IDENT then
  begin
    symId := ASTIVal[node];
    if (symId >= 0) and (symId < SymCount) then
    begin
      { feature-a-typeref-migrate-consumers lane 1: PtrElemTk read via
        SymTR[symId].PtrBaseTk (kept in sync by SymSyncTypeRef). }
      if (Syms[symId].TypeKind = tyPointer) and
         ((SymTR[symId].PtrBaseTk = Ord(tyChar)) or
          (SymTR[symId].PtrBaseTk = Ord(tyUInt8)) or
          (SymTR[symId].PtrBaseTk = Ord(tyInt8))) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 3. If it's a field access }
  if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    if recId <> REC_NONE then
    begin
      tk := RecFieldPtrElemTk(recId, GetASTIdentName(node));
      if (tk = tyChar) or (tk = tyUInt8) or (tk = tyInt8) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 4. If it's a function call (direct, or indirect through a proc-typed value:
       AN_CALL_IND stores the signature's Procs[] index in IVal, so the return
       pointer-element type reads the same way). }
  if (ASTKind[node] = AN_CALL) or (ASTKind[node] = AN_CALL_IND) then
  begin
    procIdx := ASTIVal[node];
    if (procIdx >= 0) and (procIdx < ProcCount) then
    begin
      if (ProcRetPtrElemTk[procIdx] = Ord(tyChar)) or
         (ProcRetPtrElemTk[procIdx] = Ord(tyUInt8)) or
         (ProcRetPtrElemTk[procIdx] = Ord(tyInt8)) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 5. If it's a binop pointer expression }
  if ASTKind[node] = AN_BINOP then
  begin
    if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyPointer then
      Result := IsNodePChar(ASTLeft[node])
    else
      Result := IsNodePChar(ASTRight[node]);
    Exit;
  end;
end;

{ Build the AST for PCharToString(pcharNode): an AN_CALL wrapping the pchar value
  as its argument, tagged with the helper's ACTUAL return kind (AnsiString in
  managed mode, frozen tyString under -uPXX_MANAGED_STRING — hardcoding tyString
  mislabels the managed handle as frozen and miscompiles the result). ONE builder
  for every PChar->managed-string conversion site (cast, assign, …) so the wrapper
  cannot drift between contexts. See
  refactor-centralize-managed-string-pchar-conversion. }
{ WrapPCharToString lives in parser.inc (near the other Wrap* helpers); the
  duplicate that used to sit here was an exact copy and tripped FPC's
  "overloaded functions have the same parameter list" — removed
  (bug-fpc-seed-helper-ordering-after-lua-c-frontend recurrence). }

function IsASTLValue(node: Integer): Boolean;
var symIdx: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    symIdx := ASTIVal[node];
    Result := (Syms[symIdx].Kind = skLocal) or
              (Syms[symIdx].Kind = skParam) or
              (Syms[symIdx].Kind = skGlobal);
  end
  else
    Result := (ASTKind[node] = AN_FIELD) or
              (ASTKind[node] = AN_INDEX) or
              (ASTKind[node] = AN_DEREF) or
              (ASTKind[node] = AN_COMPOUND_LITERAL);
end;

{ Source data address for a `var`/`out` open-array writeback temp (PendOAWB*).
  The temp is either the frame-local `[len:8][data]` byte buffer (SLOTADDR+8
  skips the header) or, for a large source array, a genuine managed dyn-array
  (its handle, IR_LEA, already points past its own length header) -- see
  bug-const-open-array-param-stack-copies-caller-frame. Syms[].ArrLen < 0 is
  the existing dynamic-array sentinel (AllocDynArray, symtab.inc), reused here
  rather than adding new parallel bookkeeping. }
function PendOAWBSrcAddr(tempSym: Integer): Integer;
begin
  if Syms[tempSym].ArrLen < 0 then
    Result := IRAppend(IR_LEA, tempSym, -1, -1, 0, Ord(tyPointer))
  else
    Result := IRAppend(IR_BINOP,
      IRAppend(IR_SLOTADDR, tempSym, -1, -1, 0, Ord(tyPointer)),
      IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
      Ord(tkPlus), 0, Ord(tyPointer));
end;

{ ===== {$MODE DELPHI}: a bare procvar in a VALUE context is CALLED ===========
  A procedural variable named where a VALUE is wanted must be called; taking its
  address is what `@fp` is for. `fp()` was already right, so the two spellings
  disagreed, and the wrong one is what Delphi-family code writes — every dynamic
  binding layer is "load a function pointer, wrap it in a function that calls
  it". The wrong value is a VALID POINTER, so nothing errors: Synapse handed
  `@TLS_method` to SSL_CTX_new and libssl died far away.

  DELPHI MODE ONLY, and that is the whole point of the flag. Measured against
  FPC 3.2.2, same program in each mode:

    context                          $MODE FPC / OBJFPC   $MODE DELPHI
    p := fp        (p: Pointer)      address              CALL
    Int64(fp)      (cast)            address              CALL
    Takes(fp)      (Pointer param)   address              CALL
    fp = nil / fp = fp2              address compare      CALL both
    Takes(fp)      (procvar param)   address              address
    Assigned(fp), @fp                address              address

  So FPC/OBJFPC never auto-call, and pxx must not either — this project targets
  FPC, with Delphi behaviour only under {$MODE DELPHI}.

  `sinkIsProcVar` is the caller's answer to "does this context want the procvar
  ITSELF?". Callers that cannot tell must pass True: suppressing is always safe,
  auto-calling when the sink wanted the pointer is a silent wrong value.
  bug-pascal-procvar-value-context-outside-assignment }
function IRProcVarAutoCall(n: Integer; sinkIsProcVar: Boolean): Integer;
var sym, sig, callNode: Integer;
begin
  Result := n;
  if sinkIsProcVar or (not DelphiMode) then Exit;
  if (n < 0) or (ASTKind[n] <> AN_IDENT) then Exit;   { `@fp` is AN_ADDR, `fp()` already AN_CALL_IND }
  sym := Integer(ASTIVal[n]);
  if (sym < 0) or (sym >= SymCount) then Exit;
  sig := SymProcSig[sym];
  if (sig < 0) or (sig >= ProcCount) then Exit;
  { A bare name supplies no arguments, so a signature WITH parameters can never
    be an auto-call; and a procedure has no value to yield. }
  if (Procs[sig].ParamCount <> 0) or (not Procs[sig].IsFunc) then Exit;
  callNode := AllocNode(AN_CALL_IND);
  ASTIVal[callNode] := sig;
  ASTLeft[callNode] := -1;                { no arguments }
  ASTRight[callNode] := n;                { callee = the procvar value }
  ASTTk[callNode] := Ord(Procs[sig].RetType);
  Result := callNode;
end;

function IRLowerCallArg(cpi: Integer; pathIdx: Integer; argAST: Integer; isRefArg: Boolean): Integer;
var argTk: TTypeKind;
    needTemp: Boolean;
    argIsWholeArray: Boolean;
    argRecId: Integer;
    savedLastTypeRecId: Integer;
    tmpSym: Integer;
    tmpAddr: Integer;
    srcAddr: Integer;
    value: Integer;
    caCount, caElemRec, caElemSz, caSym, savedRec, caArgSym: Integer;
    caElemTk: TTypeKind;
    caIdent, caCountLit, caArg1, caArg2, caSlCall, caNone: Integer;
    caRecName: Integer; caField: AnsiString; oaEligible: Boolean;
  coerceParamSym, coerceIntfCi, coerceCast: Integer;
  arcArg1, arcArg2, arcCall: Integer;
  pvSinkIsProcVar: Boolean;
begin
  { A by-VALUE OPEN ARRAY gets its OWN COPY — FPC's rule, and the one parameter
    kind pxx got wrong. `procedure P(x: array of Integer)` then `x[0] := 666`
    was visible to the caller, silently, because a dynamic-array argument passes
    its handle straight through
    (bug-a-open-array-value-parameter-aliases-instead-of-copying).

    Done HERE, not at the call sites: every call funnels through this function,
    while the parser builds argument lists in a dozen places (plain calls,
    method calls, inherited, indexed properties) and patching each would be the
    second path that stays broken.

    Four conditions, each load-bearing, and the measurements are on the ticket:
    - IsArray and NOT isRefArg — a `var`/`out` open array must keep aliasing,
      and already does.
    - DynDepth = 0 — a NAMED dynamic-array value param (`x: TIntArr`) passes the
      reference in FPC too, and pxx already agrees. Only a true open array
      (`array of T`) is the construct that copies.
    - not const — `const` cannot be written, so a copy would be pure cost. This
      is also what keeps the change free where it matters: every open-array
      parameter in the compiler's own source is `const`, so self-host never
      reaches this path.
    - the ARGUMENT carries a length header — a dynamic array, or an open-array
      PARAMETER being forwarded onward (that one is not optional: `Outer(x)`
      calling `Inner(x)` must give Inner its own copy, and FPC says so). A
      static-array argument already materialises a dyn temp on the way in
      (measured: it does not alias), so it needs nothing here.

    Spelled as the same AN_DYN_COPY node `Copy(a)` builds rather than a new
    lowering, so it inherits that path's allocation and temp lifetime. Nested
    and managed element types stay on the old path deliberately: AN_DYN_COPY
    byte-copies, so an `array of AnsiString` would duplicate handles without
    retaining them, and a wrong VALUE beats a double free until Copy itself
    learns element-aware retain (feature-dynarray-copy-nested-element-type). }
  if (not isRefArg) and (cpi >= 0) and (cpi < ProcCount) and
     (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (pathIdx < MAX_PROC_PARAMS) and
     Procs[cpi].Params[pathIdx].IsArray and
     (not Procs[cpi].Params[pathIdx].IsRef) and
     (ProcParamDynDepth[cpi * MAX_PROC_PARAMS + pathIdx] = 0) and
     (not ProcParamIsConst[cpi * MAX_PROC_PARAMS + pathIdx]) and
     OpenArrayCopyEligible(argAST) then
    argAST := MakeWholeDynCopy(argAST);

  { A by-VALUE SET or FROZEN-STRING param gets its OWN COPY too — the same rule
    as the open array above, on the two remaining parameter kinds that got it
    wrong. Measured against FPC:

        procedure MutSet(s: TSet);   begin s := s + [7]; end;
        procedure MutStr(s: TStr20); begin s := 'changed'; end;

    FPC leaves the caller's `s`/`t` untouched. pxx wrote straight through to
    them on x86-64, aarch64 and arm32 — silently, no error, the caller's value
    simply changed. riscv32 answered FPC's result, and that split is exactly the
    per-backend divergence table on [[bug-a-param-pointer-rule-divergence]]:
    the three targets whose "param slot holds a pointer" copy lists `tySet`
    deref the slot and so alias, the one that omits it does not.

    That ticket concluded the divergence was LATENT after a probe that only READ
    the set. It is not: writing to the parameter reaches it, and this is a live
    wrong-value bug on three of five targets. Corrected there.

    Fixed CALLER-side, in this one funnel, for the same reason the open-array
    copy is here — and because it is target-neutral: the callee receives a temp
    it may scribble on, whichever convention the backend uses for the slot. The
    copy is spelled as an ordinary `tmp := arg` ASSIGNMENT lowered through the
    normal path, which already knows how to copy both kinds (IR_SET_COPY for a
    set, the frozen-string store for a string[N]) — no second copy mechanism.

    `const` is the escape hatch, exactly as for open arrays: it cannot be
    written, so the copy would be pure cost. }
  if (not isRefArg) and (cpi >= 0) and (cpi < ProcCount) and
     (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (pathIdx < MAX_PROC_PARAMS) and
     { ProcParamExplicitByRef, not IsRef: a frozen-string VALUE param carries
       IsRef anyway — the ABI passes its slot by reference — and that is exactly
       the flag this array exists to tell apart from a source-level `var`/`out`.
       Keying on IsRef made the set half fire and left the string[N] half
       aliasing, which is how the distinction was found. }
     (not ProcParamExplicitByRef[cpi * MAX_PROC_PARAMS + pathIdx]) and
     (not Procs[cpi].Params[pathIdx].IsArray) and
     (not ProcParamIsConst[cpi * MAX_PROC_PARAMS + pathIdx]) and
     (((Procs[cpi].Params[pathIdx].TypeKind = tySet) and
       (IntToTypeKind(ASTTk[argAST]) = tySet)) or
      (TypeIsFrozenString(Procs[cpi].Params[pathIdx].TypeKind) and
       TypeIsFrozenString(IntToTypeKind(ASTTk[argAST])))) then
  begin
    if Procs[cpi].Params[pathIdx].TypeKind = tySet then
      tmpSym := AllocVar('', tySet)
    else
    begin
      { 255 covers every string[N], so a wider temp cannot truncate whatever
        frozen kind the source is. Mirrors the managed->frozen arm below.

        The two sides are matched by SHAPE (both frozen) rather than by exact
        kind, because they legitimately differ: a `string[20]` VARIABLE's node
        carries the legacy alias tyString (4) while the PARAMETER carries
        tyFixedString (26) — the frozen-kind migration's two spellings of one
        thing. An exact-kind test compiled fine and silently never fired, which
        is how this was found: the set half worked and the string half still
        aliased. An AnsiString argument is deliberately NOT matched here — it is
        a CONVERSION, and the managed->frozen arm below already materialises its
        own temp. }
      LastTypeStrCap := 255;
      tmpSym := AllocVar('', Procs[cpi].Params[pathIdx].TypeKind);
    end;
    caIdent := AllocNode(AN_IDENT);
    ASTIVal[caIdent] := tmpSym;
    ASTTk[caIdent] := Ord(Procs[cpi].Params[pathIdx].TypeKind);
    caSlCall := AllocNode(AN_ASSIGN);
    ASTLeft[caSlCall] := caIdent;
    ASTRight[caSlCall] := argAST;
    IRLowerAST(caSlCall);
    caIdent := AllocNode(AN_IDENT);
    ASTIVal[caIdent] := tmpSym;
    ASTTk[caIdent] := Ord(Procs[cpi].Params[pathIdx].TypeKind);
    argAST := caIdent;          { …and the ordinary arg lowering takes it from here }
  end;

  { {$MODE DELPHI}: a bare procvar ARGUMENT is called when the parameter wants a
    value, and passed as-is when the parameter is itself proc-typed — measured
    both ways against FPC. Computed with explicit ifs rather than a chained
    `or`, so Procs[cpi].Params[pathIdx] is never touched with an out-of-range
    index whatever the dialect's boolean-evaluation order. A var/out parameter
    binds the variable itself, never a call result, so it always suppresses. }
  pvSinkIsProcVar := True;
  if (not isRefArg) and (cpi >= 0) and (cpi < ProcCount) and
     (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) then
  begin
    { ProcParamProcSig, not the parameter's SYMBOL: a param symbol is a local
      that does not outlive the callee's scope, and RegisterProc leaves
      Params[].SymIdx = -1, so a caller has no way back to it. The per-proc
      parallel array persists — see the write site in parser.inc's param loop. }
    pvSinkIsProcVar := (ProcParamProcSig[cpi * MAX_PROC_PARAMS + pathIdx] >= 0);
  end;
  argAST := IRProcVarAutoCall(argAST, pvSinkIsProcVar);

  { A WideChar VALUE passed to a string parameter converts to its UTF-8
    encoding (fpjson's `UTF8Encode(WideChar(U1))`). Without this the 16-bit
    ordinal was retained AS A STRING POINTER by the managed-arg path — silent
    corruption, then a crash inside the callee. }
  if (cpi >= 0) and (not isRefArg) and
     (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     ((Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) or
      (Procs[cpi].Params[pathIdx].TypeKind = tyString)) and
     NodeIsWideCharVal(argAST) then
  begin
    Result := IRLowerCallArg(cpi, pathIdx, WrapWideCharToUTF8(argAST), isRefArg);
    Exit;
  end;
  { NilPy: a CONSTRUCTION in argument position (`join([... for ...])`,
    `exec(src, {"a": 1})`) has no binding to consume its rc=1 — the arg itself
    is a borrow — so it leaked whole containers per call. Spill it to a hidden
    OWNING tyClass temp: release the temp's previous occupant (same slot every
    trip through a loop; first use is nil'd by the mid-body watermark pass),
    store, pass the temp. Scope exit drops the last one
    (feature-nilpy-object-reclamation). Param 0 (a method receiver) is
    excluded: the for-in and method desugars route the SAME construction
    subtree through receiver position with their own binding plumbing, and
    spilling it there double-consumed the construction (test_nilpy_forin
    SIGSEGV). A bare `[...].method()` receiver still leaks — rare shape. }
  { Two owned-object shapes reach here as a construction-in-arg:
    (a) a class NEW (`SomeClass(...)`, an IR_CALL to GetMem, ASTRight = the
        user class), and
    (b) a builtin/user call that RETURNS an owned tyClass object — `list(src)`,
        `dict()`, a factory method — whose result is likewise rc=1 with no
        binding to consume it. `Frame(list(src))` stored the list in a field
        (retain -> rc=2) but never released the caller's original rc=1, leaking
        one container per call (uforth run_forth_word's `Frame(list(body))` —
        the top per-iteration doloop leak found via DHAT). Both spill to the
        same owning temp whose inline release-of-previous drops the prior trip's
        object each loop iteration. }
  if NilPyUserCode and (not isRefArg) and
     (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (ASTKind[argAST] = AN_CALL) and
     ( { A construction / tyClass-tagged arg keeps the pathIdx>=1 receiver guard:
         the for-in and method desugars route the SAME construction subtree
         through receiver position (pathIdx 0) with their own binding plumbing,
         and spilling it there double-consumes (test_nilpy_forin SIGSEGV). }
       ( (pathIdx >= 1) and
         ( ((Integer(ASTIVal[argAST]) = -Ord(tkGetMem)) and
            (Integer(ASTRight[argAST]) >= REC_UCLASS_BASE))
           or (IntToTypeKind(ASTTk[argAST]) = tyClass) ) )
       { An object-returning PROC call result (`pybytes_slice`, `pylist_slice`,
         `list`, a factory — ProcRetRecId set) is owned (+1) but in a value-arg
         position often carries a tyPointer tag rather than tyClass, so the
         checks above miss it and the owned rc=1 leaked — `bytes(mem[a:b])`,
         `len(mem[a:b])` (uforth `_snapshot_input_state` does 3x
         `bytes(memory[a:b])`/line; bug-nilpy-bytes-of-slice-leaks-intermediate).
         This is a genuine value argument, not a construction routed through a
         receiver, so it is safe to spill even at pathIdx 0 (bytes()/len() are
         free functions, not methods). All NilPy results are owned + the consumer
         borrows, so spill+release stays balanced regardless of the param tag. }
       or ((Integer(ASTIVal[argAST]) >= 0) and
           (ProcRetRecId[Integer(ASTIVal[argAST])] >= REC_UCLASS_BASE)) ) then
  begin
    tmpSym := AllocVar('', tyClass);
    if (Integer(ASTIVal[argAST]) = -Ord(tkGetMem)) and
       (Integer(ASTRight[argAST]) >= REC_UCLASS_BASE) then
      Syms[tmpSym].RecName := ASTRight[argAST]
    else
      Syms[tmpSym].RecName := REC_NONE;   { generic owned object; PXXObjRelease is magic-guarded }
    SymSyncTypeRef(tmpSym);
    value := IRLowerAST(argAST);
    arcCall := FindProc('PXXObjRelease');
    if arcCall >= 0 then
    begin
      arcArg1 := IRAppend(IR_ARG,
                   IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
      arcArg2 := IRAppendCall(arcCall, arcArg1, -1, Ord(tyUnknown));
      IRIVal[arcArg2] := 1;   { statement: emit for effect }
    end;
    IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0, Ord(tyClass));
    Exit;
  end;
  { C double->int argument coercion: a float argument passed to a named INTEGER
    parameter is truncated. Do it backend-agnostically by spilling the float to a
    hidden integer local — its IR_STORE_SYM reuses the double->int conversion
    already implemented on every target (cvttsd2si / fcvtzs / VFP vcvt / softfloat)
    — then passing that local. This covers all call paths (direct/indirect/
    variadic-named/virtual) on all backends without touching per-ABI arg
    marshalling. Variadic slots (pathIdx >= ParamCount) have no param and keep the
    double (C default promotion). }
  if CProgramMode and (not isRefArg) and (cpi >= 0) and
     (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (not TypeIsFloat(Procs[cpi].Params[pathIdx].TypeKind)) and
     TypeIsOrdinal(Procs[cpi].Params[pathIdx].TypeKind) and
     TypeIsFloat(IntToTypeKind(ASTTk[argAST])) then
  begin
    tmpSym := AllocVar('', Procs[cpi].Params[pathIdx].TypeKind);
    value := IRLowerAST(argAST);
    IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0,
             Ord(Procs[cpi].Params[pathIdx].TypeKind));
    Result := IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0,
                       Ord(Procs[cpi].Params[pathIdx].TypeKind));
    Exit;
  end;
  { C default argument promotion (C99 6.5.2.2p6): a `float` passed through the
    `...` of a variadic call must widen to `double`. Floats live in a register at
    double natural width, so on x86-64/aarch64 the xmm/vector value already
    marshals as 8 bytes and printf reads it fine; but the 32-bit variadic paths
    (i386/arm32/riscv32) slot a tySingle-tagged arg as 4 bytes, so printf reads a
    half-filled double (0.000000). Spill the single to a hidden tyDouble local and
    reload: the store-to-double slot keeps the value double-wide (dest-type
    conversion, same mechanism as a float<->float cast), so every backend then
    marshals a full 8-byte double. Variadic slot = pathIdx >= ParamCount.
    bug-c-float-vararg-promotion-32bit. }
  if CProgramMode and (not isRefArg) and (cpi >= 0) and ProcVariadic[cpi] and
     (pathIdx >= Procs[cpi].ParamCount) and
     (IntToTypeKind(ASTTk[argAST]) = tySingle) then
  begin
    tmpSym := AllocVar('', tyDouble);
    value := IRLowerAST(argAST);
    IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(tyDouble));
    Result := IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0, Ord(tyDouble));
    Exit;
  end;
  { A frozen-string concatenation used as a call argument builds its result in a
    272-byte buffer carved off the stack (`sub rsp, 272`, no restore), leaving the
    pointer at rsp. In a multi-argument call (a method's implicit Self plus the
    string is the common case) that punches a hole between the argument pushes, so
    the push/pop marshalling pops buffer bytes instead of the real arguments and
    corrupts the call. Spill it to a hidden local first — the automatic form of the
    `s := a + b; f(s)` workaround — and pass the local by ADDRESS: a frozen-string
    argument is the slot address (IR_LEA), not the loaded value, which for a local
    would be the inline length word. Managed AnsiString concat returns a heap
    handle (no stack temp), so this targets only frozen tyString. See
    bug-stack-corruption-inline-string-concat. }
  if (IntToTypeKind(ASTTk[argAST]) = tyString) and
     (ASTKind[argAST] = AN_BINOP) and (Integer(ASTIVal[argAST]) = Ord(tkPlus)) then
  begin
    tmpSym := AllocVar('', tyString);
    value := IRLowerAST(argAST);
    IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(tyString));
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyString));
    Exit;
  end;
  { A MANAGED string argument to a FROZEN-string parameter (Pascal Script's
    `CheckReserved(FLastUpToken: TbtString, ...)` into `Const S: ShortString`):
    the param wants a frozen slot ADDRESS, a managed handle is never the right
    layout. Convert through a hidden frozen temp — the store coerces
    managed -> frozen (the ordinary assignment path), the arg is the temp's
    slot address. Applies to var/out too: the callee sees a temp, matching
    FPC's implicit-conversion-then-by-ref-const semantics for `const`;
    genuine var/out params keep erroring in the front end's lvalue check. }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     TypeIsFrozenString(Procs[cpi].Params[pathIdx].TypeKind) and
     (IntToTypeKind(ASTTk[argAST]) = tyAnsiString) then
  begin
    if Procs[cpi].Params[pathIdx].TypeKind = tyString then
      tmpSym := AllocVar('', tyString)
    else
    begin
      LastTypeStrCap := 255;   { ShortString / string[N] params: 255 covers }
      tmpSym := AllocVar('', Procs[cpi].Params[pathIdx].TypeKind);
    end;
    { coerce via the ordinary ASSIGNMENT path (it owns managed->frozen):
      synthesize `tmp := arg` as AST and lower it }
    caIdent := AllocNode(AN_IDENT);
    ASTIVal[caIdent] := tmpSym;
    ASTTk[caIdent] := Ord(Procs[cpi].Params[pathIdx].TypeKind);
    caSlCall := AllocNode(AN_ASSIGN);
    ASTLeft[caSlCall] := caIdent;
    ASTRight[caSlCall] := argAST;
    IRLowerAST(caSlCall);
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
    Exit;
  end;
  { Scalar -> Variant boxing at a call boundary: a literal/scalar value passed
    to a Variant parameter goes through a hidden variant temp via the ordinary
    assignment path (IR_VAR_STORE owns the tagging), and the temp's ADDRESS is
    the argument — a variant arg is always passed by address (see the
    VariantToStr marshalling). Without this an `l.append(1)` hit
    IR_UNSUPPORTED on the raw AN_INT_LIT (feature-core-variant-arg-boxing). }
  { A variant RVALUE to a by-reference variant parameter. The parameter is
    passed by address and a call result has none, so it needs a slot: `pynone()`
    filled for an omitted `= None` reached the callee as the returned bytes
    read through a pointer. The boxing branch below skips this case by design —
    it fires only when the argument is NOT already a variant. }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyVariant) and
     (not Procs[cpi].Params[pathIdx].IsArray) and
     Procs[cpi].Params[pathIdx].IsRef and
     (IntToTypeKind(ASTTk[argAST]) = tyVariant) and
     ((ASTKind[argAST] = AN_CALL) or (ASTKind[argAST] = AN_VIRTUAL_CALL)) then
  begin
    tmpSym := AllocVar('', tyVariant);
    caIdent := AllocNode(AN_IDENT);
    ASTIVal[caIdent] := tmpSym;
    ASTTk[caIdent] := Ord(tyVariant);
    caSlCall := AllocNode(AN_ASSIGN);
    ASTLeft[caSlCall] := caIdent;
    ASTRight[caSlCall] := argAST;
    IRLowerAST(caSlCall);
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyVariant));
    Exit;
  end;

  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyVariant) and
     { an open `array of Variant` param carries the ELEMENT type in TypeKind —
       boxing the whole ARRAY (its handle) into a variant temp handed the
       callee &temp as the data pointer: Length read stack garbage and every
       element aliased the temp (bug-a-open-array-of-variant-silent-miscompile,
       the same TypeKind-is-the-element-type blindspot as tkLength/marshalling). }
     (not Procs[cpi].Params[pathIdx].IsArray) and
     ((IntToTypeKind(ASTTk[argAST]) <> tyVariant) or
      (not Procs[cpi].Params[pathIdx].IsRef)) then
  begin
    { Fires for const/by-value Variant params alike: a genuine `var Variant`
      given a non-variant arg is already type-invalid, so losing its
      write-back through the temp is not a supported case.
      A VARIANT arg to a BY-VALUE Variant param comes through here too: the
      temp is what gives it value semantics. `const v: Variant` is marked
      IsRef by the parser and keeps passing the caller's own address (no
      copy, FPC-style), and `var v: Variant` likewise — only the plain
      by-value form copies (bug-pascal-byvalue-variant-param). The synthesized
      `tmp := arg` lowers to the ARC-correct 16-byte IR_VAR_STORE, and tmp is
      an ordinary variant local, so the epilogue's PXXVarClear releases it. }
    tmpSym := AllocVar('', tyVariant);
    caIdent := AllocNode(AN_IDENT);
    ASTIVal[caIdent] := tmpSym;
    ASTTk[caIdent] := Ord(tyVariant);
    caSlCall := AllocNode(AN_ASSIGN);
    ASTLeft[caSlCall] := caIdent;
    { Python's `None` reaches here as the nil POINTER literal, which boxes to
      the integer 0 — `f(None)` then printed 0 where CPython prints None, and a
      callee testing `is None` never matched. The empty variant is what None
      means, and it is what an omitted `= None` default already fills. }
    if isNilPy and (ASTKind[argAST] = AN_INT_LIT) and (ASTIVal[argAST] = 0) and
       (IntToTypeKind(ASTTk[argAST]) = tyPointer) and (FindProc('pynone') >= 0) then
    begin
      caNone := AllocNode(AN_CALL);
      ASTIVal[caNone] := FindProc('pynone');
      ASTTk[caNone] := Ord(tyVariant);
      ASTLeft[caNone] := -1;
      ASTRight[caSlCall] := caNone;
    end
    else
      ASTRight[caSlCall] := argAST;
    IRLowerAST(caSlCall);
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyVariant));
    Exit;
  end;
  { Variant -> SCALAR at a call boundary, the mirror of the scalar->Variant
    boxing above: a variant argument given to a scalar parameter (`len(v)`,
    where v holds a string) otherwise passed the raw 8 bytes, i.e. the tag.
    By-reference params are excluded — there is no scalar slot to write back
    to. (bug-a-nilpy-variant-element-not-usable-as-scalar.) }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     (IntToTypeKind(ASTTk[argAST]) = tyVariant) and
     ((not Procs[cpi].Params[pathIdx].IsRef) or
      ProcParamIsConst[cpi * MAX_PROC_PARAMS + pathIdx]) and
     IRVariantUnboxKind(Procs[cpi].Params[pathIdx].TypeKind) then
  begin
    Result := IRLowerVariantAsScalar(argAST, Procs[cpi].Params[pathIdx].TypeKind);
    Exit;
  end;
  { NilPy: a VARIANT argument to a CLASS-typed parameter unboxes via pyvarobj
    (the VT_OBJECT payload) — the raw lowering passed the 16-byte variant's
    ADDRESS as the object pointer, and the callee dereferenced the TAG word
    (uforth EXECUTE: run_forth_word(word) with word straight from
    xt_table.get, a variant). Mirrors the scalar unbox block above. }
  if PyProgramMode and (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     (IntToTypeKind(ASTTk[argAST]) = tyVariant) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyClass) and
     (not Procs[cpi].Params[pathIdx].IsRef) then
  begin
    { pyvarobj_arg, not pyvarobj: the unwrap is TAG-CHECKED. Plain pyvarobj
      hands back the raw payload, so a variant holding a STRING bound to a
      class parameter was reinterpreted as an instance pointer and the callee
      dereferenced it — `tuple(v)`, `sorted(v)`, `bytes(v)`, `reversed(v)` and
      `sum(v)` all SEGFAULTED on an ordinary `for x in ["cab"]` receiver, and
      any pylib builtin added later without a Variant overload starts there too.
      The checked entry point raises TypeError instead, so the failure mode for
      the whole family is a Python-shaped error rather than a wild dereference.

      A separate routine rather than a check inside pyvarobj, because the
      runtime dispatch arms (`pyvarobj(v) is C ? ... : ...`) pass non-object
      variants on purpose and need the test to come back False.
      bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked }
    caSlCall := FindProc('pyvarobj_arg');
    if caSlCall < 0 then caSlCall := FindProc('pyvarobj');   { pre-pin pylib }
    if caSlCall < 0 then Error('variant unbox: pyvarobj builtin not loaded');
    caArg1 := IRAppend(IR_ARG, IRVariantAddr(argAST), -1, -1, 0, Ord(tyVariant));
    Result := IRAppendCall(caSlCall, caArg1, -1, Ord(tyPointer));
    Exit;
  end;
  { PROMO argument to a PROMO parameter: give the callee its OWN slot.

    A promo parameter is by-ref like every other aggregate parameter (see the
    IsRef promotion in parser.inc), so what crosses the call is an address —
    and Pascal value semantics then depend on that address naming a COPY, which
    is exactly what the record path does with a hidden temp and copy_rec. Promo
    needs PXXPromoCopy rather than a raw 16-byte copy: the heap tier's payload
    is a managed AnsiString and the copy has to RETAIN it (`dp^ := sp^`), or the
    callee's epilogue would release a string the caller still owns.

    Without the copy the callee wrote straight through to the caller's variable
    — `n := n + 1` inside the routine changed the caller's `v`.

    Copied unconditionally, including for a promo rvalue that already sits in a
    fresh temp: one redundant copy is worth the rule staying "the callee always
    gets its own slot", and the alternative is an aliasing question at every
    call site. }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     TypeIsPromoInt(Procs[cpi].Params[pathIdx].TypeKind) and
     TypeIsPromoInt(IntToTypeKind(ASTTk[argAST])) then
  begin
    caArg1 := IRPromoTempSlot(caSym);
    IRMarkStatementNode(IRPromoCall('PXXPromoCopy', caArg1,
                                    IRPromoAddrOf(argAST), -1, tyUnknown));
    Result := IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer));
    Exit;
  end;
  { An ORDINAL argument to a promo parameter: box it into the same kind of
    hidden temp, through PXXPromoFromInt — the identical lowering the widening
    assignment `p := 12` uses. TypesCompatible now admits this direction, so
    `f(12)` resolves; without the boxing here it would resolve and then hand the
    callee a machine int where it expects a {tag, payload} slot address.
    bug-a-promoint-parameter-rejects-literals-and-call-results }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     TypeIsPromoInt(Procs[cpi].Params[pathIdx].TypeKind) and
     TypeIsOrdinal(IntToTypeKind(ASTTk[argAST])) and
     (IntToTypeKind(ASTTk[argAST]) <> tyPointer) then
  begin
    caArg1 := IRPromoTempSlot(caSym);
    IRMarkStatementNode(IRPromoCall('PXXPromoFromInt', caArg1,
                                    IRLowerAST(argAST), -1, tyUnknown));
    Result := IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer));
    Exit;
  end;
  { PROMO argument to a POINTER parameter: pass the slot ADDRESS, which is what
    every promocore entry point takes.

    MUST come before the narrowing arm below. TypeIsOrdinal includes tyPointer
    (it is in the 15/16/17 group with tyNativeInt/tyNativeUInt), so the narrowing
    arm matches a Pointer parameter too and would hand the callee a value where
    it expects an address — measured: PXXPromoToInt64Wrap ran and the callee
    dereferenced the result into a segfault, with an IR dump that looked
    perfectly reasonable until the arg's source node was read.

    This is the path a frontend lowering uses to reach the promo runtime with an
    ordinary AN_CALL rather than hand-built IR: it is how `hex`/`bin`/`oct` of an
    arbitrary-precision int reach PXXPromoToBase
    (feature-nilpy-hex-bin-oct-over-a-big-int). }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     TypeIsPromoInt(IntToTypeKind(ASTTk[argAST])) and
     (not Procs[cpi].Params[pathIdx].IsRef) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) then
  begin
    Result := IRPromoAddrOf(argAST);
    Exit;
  end;
  { PROMO argument to a concrete int parameter: same mod-2^64 narrowing as the
    assignment path — the raw lowering would pass the slot ADDRESS. A POINTER
    parameter is handled above; it is ordinal by TypeIsOrdinal's reckoning but
    wants the address, not a narrowed value. }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     TypeIsPromoInt(IntToTypeKind(ASTTk[argAST])) and
     (not Procs[cpi].Params[pathIdx].IsRef) and
     TypeIsOrdinal(Procs[cpi].Params[pathIdx].TypeKind) then
  begin
    Result := IRPromoCall('PXXPromoToInt64Wrap', IRPromoAddrOf(argAST), -1, -1, tyInt64);
    Exit;
  end;
  { PROMO argument to a FLOAT parameter: widen through PXXPromoToDouble, which
    reads the true value off the limbs. Narrowing first and converting would
    approximate the value's LOW 64 BITS, so a bignum argument would arrive as a
    small float rather than a large one — silent, and the wrong kind of wrong. }
  if (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     TypeIsPromoInt(IntToTypeKind(ASTTk[argAST])) and
     (not Procs[cpi].Params[pathIdx].IsRef) and
     TypeIsFloat(Procs[cpi].Params[pathIdx].TypeKind) then
  begin
    Result := IRPromoCall('PXXPromoToDouble', IRPromoAddrOf(argAST), -1, -1, tyDouble);
    Exit;
  end;
  { `@obj.Method` given directly to a method-pointer parameter (`of object`
    record): materialise the 16-byte {Code, Data} pair into a hidden temp and
    pass its address — the record-param ABI. Mirrors the AN_ASSIGN methodref
    store; without this the raw AN_METHODREF is not a linear-lowerable node. }
  if (ASTKind[argAST] = AN_METHODREF) and (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyRecord) then
  begin
    savedLastTypeRecId := LastTypeRecId;
    LastTypeRecId := EnsureMethodPtrRec;
    tmpSym := AllocVar('', tyRecord);
    LastTypeRecId := savedLastTypeRecId;
    tmpAddr := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));
    value := IRMethodRefCode(argAST);   { VMT-resolved for a virtual method }
    IRAppend(IR_STORE_MEM, tmpAddr, value, -1, 0, Ord(tyPointer));   { Code @0 }
    srcAddr := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));
    value := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
    srcAddr := IRAppend(IR_BINOP, srcAddr, value, Ord(tkPlus), 0, Ord(tyPointer));
    value := IRLowerAST(ASTLeft[argAST]);                            { Data = Self }
    IRAppend(IR_STORE_MEM, srcAddr, value, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));
    Exit;
  end;
  { Implicit class -> interface coercion: a class argument given to an interface
    parameter is wrapped in the same fat-pointer build as an explicit `obj as
    IFoo`, then marshalled by the ordinary record-param ABI (re-entry below). }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyRecord) and
     (IntToTypeKind(ASTTk[argAST]) = tyClass) then
  begin
    coerceParamSym := ProcParamRecId[cpi * MAX_PROC_PARAMS + pathIdx];
    if (coerceParamSym >= REC_UCLASS_BASE) and
       UClsIsInterface[coerceParamSym - REC_UCLASS_BASE] then
    begin
      coerceIntfCi := coerceParamSym - REC_UCLASS_BASE;
      coerceCast := AllocNode(AN_AS_CAST);
      ASTLeft[coerceCast] := argAST;
      ASTIVal[coerceCast] := coerceIntfCi;
      ASTTk[coerceCast] := Ord(tyRecord);
      Result := IRLowerCallArg(cpi, pathIdx, coerceCast, isRefArg);
      Exit;
    end;
  end;
  { Static array -> `array of T` open param: copy the bounds-less static array into
    a fresh dyn array (with a length header) and pass that handle, so Length()/
    indexing over the param work. A `var` (by-ref) array param must alias the
    caller's array, not a copy. (Inlined here from the former TryStaticToOpenArray
    helper — kept in a helper historically to dodge a codegen landmine where the
    nested indexing expressions below lost sign-extension inside this large hot
    function; re-testing whether the sign-extension fixes this cycle cured it.) }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     Procs[cpi].Params[pathIdx].IsArray and (not Procs[cpi].Params[pathIdx].IsRef) and
     ((ASTKind[argAST] = AN_IDENT) or (ASTKind[argAST] = AN_FIELD)) then
  begin
    { Determine the static-array source — a whole 1-D static array, either a
      simple var or a record/class FIELD (synacode's Transform(State, BufLong):
      the field form used to fall through to a raw headerless address, so the
      callee's High() read garbage — the MD5 stack smash). Mirrors the var-path
      resolution below. }
    caArgSym := -1; caCount := -1; caElemTk := tyUnknown; caElemRec := REC_NONE;
    if ASTKind[argAST] = AN_IDENT then
    begin
      caArgSym := ASTIVal[argAST];
      if (caArgSym >= 0) and (caArgSym < SymCount) and Syms[caArgSym].IsArray and
         (Syms[caArgSym].ArrLen >= 0) and (Syms[caArgSym].Kind <> skParam) and
         (SymArrNDims[caArgSym] <= 1) then
      begin
        caElemTk := Syms[caArgSym].ElemType;
        caElemRec := Syms[caArgSym].ElemRecName;
        caCount := Syms[caArgSym].ArrLen;
      end;
    end
    else
    begin
      caRecName := ResolveNodeRec(ASTLeft[argAST]);
      caField := GetASTIdentName(argAST);
      if RecFieldIsArray(caRecName, caField) and
         (RecFieldArrLen(caRecName, caField) >= 0) and
         (RecFieldDynDepth(caRecName, caField) = 0) and
         (RecFieldArrNDims(caRecName, caField) <= 1) then
      begin
        caElemTk := RecFieldType(caRecName, caField);
        caElemRec := RecFieldRecId(caRecName, caField);
        caCount := RecFieldArrLen(caRecName, caField);
      end;
    end;
    if caCount >= 0 then
    begin
      if not ((caElemTk = tyRecord) and RecordHasManagedFields(caElemRec)) then
      begin
        if caElemTk = tyRecord then caElemSz := RecSize(caElemRec)
        else caElemSz := TypeSize(caElemTk);
        if caCount * caElemSz > MAX_OPEN_ARRAY_STACK_TEMP then
        begin
          { Large source array: a frame-local `[len:8][data]` buffer here would
            scale the CALLER's stack frame 1:1 with the array's declared size —
            harmless for a small array, a SIGSEGV risk for a big one (the
            caller's frame can exceed the ~8 MB default process stack).
            bug-const-open-array-param-stack-copies-caller-frame. Manufacture a
            genuine managed dyn-array-of-byte temp instead — heap-backed
            (bounded, independent of the source array's size) and released
            automatically by the routine's normal managed-local cleanup at
            scope exit, exactly like `array of const`'s TVarRec temp
            (AN_VARREC_ARRAY below) already relies on; its handle already has
            the `[len:8][data]` layout the open-array param expects, with no
            manual header bookkeeping needed. }
          caSym := AllocDynArray('', tyUInt8, 1);
          { SymIsHiddenArgTemp triggers the codegen PROLOGUE's one-time nil-
            init for this synthesized-mid-lowering local (runs once at
            function entry, before this call site's code -- including
            before a loop containing this call runs any iteration). No
            *inline* zero here on top of that: this call site's code can
            execute many times (a loop), and an inline zero right before
            each SetLength would orphan the PREVIOUS iteration's handle
            without releasing it -- SetLength itself already correctly
            resizes/reuses an existing non-nil handle (ordinary array-
            growing semantics), so trust it instead of re-zeroing. (First
            attempt at this fix did add an inline zero, copying
            AN_VARREC_ARRAY's pattern without noticing that literal's own
            call site can equally be inside a loop -- caught here via a
            50-iteration RSS-ceiling test leaking ~2 MB/call; fixed by
            removing the inline zero, not by chasing AN_VARREC_ARRAY.) }
          SymIsHiddenArgTemp[caSym] := True;
          { SetLength(caSym, caCount*caElemSz): synthesize the dyn-array
            SetLength (-102) intrinsic call, exactly as AN_VARREC_ARRAY does. }
          caIdent := AllocNode(AN_IDENT);
          ASTIVal[caIdent] := caSym; ASTTk[caIdent] := Ord(tyPointer);
          caCountLit := AllocNode(AN_INT_LIT);
          ASTIVal[caCountLit] := caCount * caElemSz; ASTTk[caCountLit] := Ord(tyInteger);
          caArg1 := AllocNode(AN_ARG); ASTLeft[caArg1] := caIdent;
          caArg2 := AllocNode(AN_ARG); ASTLeft[caArg2] := caCountLit;
          ASTRight[caArg1] := caArg2;
          caSlCall := AllocNode(AN_CALL); ASTIVal[caSlCall] := -102;
          ASTLeft[caSlCall] := caArg1;
          value := IRLowerAST(caSlCall);
          IRIVal[value] := 1;   { mark the SetLength IR_CALL as a statement to emit }
          IRAppend(IR_COPY_REC, IRAppend(IR_LEA, caSym, -1, -1, 0, Ord(tyPointer)),
            IRLowerAddress(argAST),
            -1, caCount * caElemSz, Ord(tyRecord));
          Result := IRAppend(IR_LEA, caSym, -1, -1, 0, Ord(tyPointer));
          Exit;
        end;
        { Copy the fixed array into a frame/BSS-local `[len:8][data]` buffer and
          pass `&data` — the open-array param reads its length at [data-8] and
          indexes `data`. A plain byte buffer (not a heap dyn array) auto-frees
          (it is reused at the same site / private per frame), so there is no
          per-call leak and recursion is safe; managed element handles are simply
          borrowed bytes (no per-element ARC), correct for a const/value param
          whose callee only reads them. }
        caSym := AllocArray('', tyUInt8, 0, 8 + caCount * caElemSz - 1);
        SymIsHiddenArgTemp[caSym] := True;
        { length header at buf[0..7] }
        IRAppend(IR_STORE_MEM,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, caCount, Ord(tyInteger)),
          -1, 0, Ord(tyPointer));
        { data := &buf + 8; copy the fixed array's elements into it }
        value := IRAppend(IR_BINOP,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        IRAppend(IR_COPY_REC, value,
          IRLowerAddress(argAST),
          -1, caCount * caElemSz, Ord(tyRecord));
        Result := IRAppend(IR_BINOP,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        Exit;
      end;
    end;
  end;
  { Static array -> `var`/`out` open-array param: a `var` open array must let the
    callee read AND write the caller's elements, and Length/High over it must
    work. A bare static-array address has no length header at [data-8], so High
    returns garbage (bug-var-open-array-fixed-arg-length). Pass a header'd dyn
    temp instead (copy the static array in), and register a copy-OUT so the
    callee's writes propagate back after the call (copy-in / copy-out aliasing —
    observably equal to true aliasing unless the callee reaches the same array by
    another path during the call). A function result in rax/xmm0 is preserved
    across the post-call writeback (the AN_CALL flush spills it to a temp).
    Element types with managed payloads are excluded (the value path excludes
    them too). The compiler's own source never feeds a static array to a var
    open-array param, so self-host / cross-bootstrap stay byte-identical (this
    path is not exercised there). }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     Procs[cpi].Params[pathIdx].IsArray and Procs[cpi].Params[pathIdx].IsRef and
     ((ASTKind[argAST] = AN_IDENT) or (ASTKind[argAST] = AN_FIELD)) and
     (PendOAWBCount <= 63) then
  begin
    { Determine the static-array source (a whole 1-D static array, either a
      simple var or a record/class field). Dynamic arrays and open-array params
      already carry a length header and are left alone. }
    oaEligible := False; caCount := 0; caElemTk := tyUnknown; caElemRec := REC_NONE;
    if ASTKind[argAST] = AN_IDENT then
    begin
      caArgSym := ASTIVal[argAST];
      if (caArgSym >= 0) and (caArgSym < SymCount) and Syms[caArgSym].IsArray and
         (Syms[caArgSym].ArrLen >= 0) and (Syms[caArgSym].Kind <> skParam) and
         (SymArrNDims[caArgSym] <= 1) then
      begin
        caElemTk := Syms[caArgSym].ElemType;
        caElemRec := Syms[caArgSym].ElemRecName;
        caCount := Syms[caArgSym].ArrLen;
        oaEligible := True;
      end;
    end
    else
    begin
      caRecName := ResolveNodeRec(ASTLeft[argAST]);
      caField := GetASTIdentName(argAST);
      if RecFieldIsArray(caRecName, caField) and
         (RecFieldArrLen(caRecName, caField) >= 0) and
         (RecFieldDynDepth(caRecName, caField) = 0) and
         (RecFieldArrNDims(caRecName, caField) <= 1) then
      begin
        caElemTk := RecFieldType(caRecName, caField);
        caElemRec := RecFieldRecId(caRecName, caField);
        caCount := RecFieldArrLen(caRecName, caField);
        oaEligible := True;
      end;
    end;
    { AnsiString elements ride the same copy-in/copy-out: the raw handle bytes
      move into the temp (no ARC — the temp is a byte buffer, so scope exit
      never DecRefs the elements), the callee assigns slots with normal ARC,
      and the copy-out moves the resulting handle set back over the caller's
      slots. Ownership transfers wholesale; refcounts stay balanced because
      the caller's stale copies are overwritten, never released or read.
      Records with managed FIELDS stay excluded (a field-wise release in the
      callee would need the copy-out to be field-aware). }
    if oaEligible and
       not ((caElemTk = tyRecord) and RecordHasManagedFields(caElemRec)) then
    begin
      if caElemTk = tyRecord then caElemSz := RecSize(caElemRec)
      else caElemSz := TypeSize(caElemTk);
      if caCount * caElemSz > MAX_OPEN_ARRAY_STACK_TEMP then
      begin
        { Large source array: same reasoning as the const/value path above —
          a heap-backed managed dyn-array temp instead of a frame-local
          buffer, so the caller's frame stays bounded regardless of the
          source array's size. The flush loops below (IRAppendCall,
          AN_CALL/AN_CALL_IND) detect this case by `Syms[temp].ArrLen < 0`
          (the dynamic-array sentinel) and copy back via the handle (IR_LEA)
          instead of the byte-buffer's SLOTADDR+8 convention. }
        caSym := AllocDynArray('', tyUInt8, 1);
        { No inline zero before SetLength here — see the matching comment in
          the const/value path above (this call site can equally be inside
          a loop; SymIsHiddenArgTemp's one-time prologue nil-init plus
          SetLength's own correct resize-of-existing-handle semantics is
          the right combination, not a per-visit re-zero). }
        SymIsHiddenArgTemp[caSym] := True;
        caIdent := AllocNode(AN_IDENT);
        ASTIVal[caIdent] := caSym; ASTTk[caIdent] := Ord(tyPointer);
        caCountLit := AllocNode(AN_INT_LIT);
        ASTIVal[caCountLit] := caCount * caElemSz; ASTTk[caCountLit] := Ord(tyInteger);
        caArg1 := AllocNode(AN_ARG); ASTLeft[caArg1] := caIdent;
        caArg2 := AllocNode(AN_ARG); ASTLeft[caArg2] := caCountLit;
        ASTRight[caArg1] := caArg2;
        caSlCall := AllocNode(AN_CALL); ASTIVal[caSlCall] := -102;
        ASTLeft[caSlCall] := caArg1;
        value := IRLowerAST(caSlCall);
        IRIVal[value] := 1;
        { copy-IN: static array (var or field) -> the dyn-array temp's data }
        IRAppend(IR_COPY_REC, IRAppend(IR_LEA, caSym, -1, -1, 0, Ord(tyPointer)),
          IRLowerAddress(argAST), -1, caCount * caElemSz, Ord(tyRecord));
        PendOAWBTemp[PendOAWBCount] := caSym;
        PendOAWBDest[PendOAWBCount] := argAST;
        PendOAWBSize[PendOAWBCount] := caCount * caElemSz;
        Inc(PendOAWBCount);
        Result := IRAppend(IR_LEA, caSym, -1, -1, 0, Ord(tyPointer));
        Exit;
      end;
      { Frame/BSS-local `[len:8][data]` buffer (same no-leak, recursion-safe shape
        as the const/value path above), plus a registered copy-OUT so the callee's
        writes propagate back to the caller's array after the call. }
      caSym := AllocArray('', tyUInt8, 0, 8 + caCount * caElemSz - 1);
      SymIsHiddenArgTemp[caSym] := True;
      IRAppend(IR_STORE_MEM,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, caCount, Ord(tyInteger)),
        -1, 0, Ord(tyPointer));
      value := IRAppend(IR_BINOP,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      { copy-IN: static array (var or field) -> buffer data }
      IRAppend(IR_COPY_REC, value, IRLowerAddress(argAST),
        -1, caCount * caElemSz, Ord(tyRecord));
      { register copy-OUT: buffer data -> the argument's address, after the call.
        The dest is the arg AST node, re-lowered (IRLowerAddress) at flush time. }
      PendOAWBTemp[PendOAWBCount] := caSym;
      PendOAWBDest[PendOAWBCount] := argAST;
      PendOAWBSize[PendOAWBCount] := caCount * caElemSz;
      Inc(PendOAWBCount);
      Result := IRAppend(IR_BINOP,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      Exit;
    end;
  end;
  { An `array of const` literal lowers to a freshly built dyn-array of TVarRec;
    its value is the data-pointer handle, passed straight through (never the
    record-by-value copy path below). }
  if (ASTKind[argAST] = AN_VARREC_ARRAY) or (ASTKind[argAST] = AN_ARRAY_CTOR) then
  begin
    Result := IRLowerAST(argAST);
    Exit;
  end;
  { `f((a, b))` -- a comma operator as an argument. Its value IS b, so evaluate a for
    its side effects and then lower b AS the argument, with the full parameter-aware
    treatment below. Unwrapping here rather than letting IRLowerAST handle the comma
    is what makes a STRUCT (or array, or string) survive the trip: a comma is not an
    lvalue, so the record-by-value path could not take its address and fell through to
    a scalar lowering, handing the callee a garbage pointer.

    csmith: `func_10(((*g_3), g_15), ...)` segfaulted, while `func_10(g_15, ...)` --
    the same struct, passed directly -- was fine. }
  while ASTKind[argAST] = AN_COMMA do
  begin
    { IRMarkStatementNode, exactly as the AN_COMMA arm of IRLowerAST does: the IR is
      walked from its roots, so a node evaluated purely for its side effects has to be
      marked or it is an orphan and never gets emitted at all -- `f((bump(), s))` would
      silently not call bump(). }
    IRDiscardValue(IRLowerAST(ASTLeft[argAST]));
    argAST := ASTRight[argAST];
  end;

  argTk := IntToTypeKind(ASTTk[argAST]);
  needTemp := False;
  argRecId := REC_NONE;
  { A whole array variable is never a record-by-value argument: its node carries
    the element's tyRecord tag, but the value is the array, not one record.
    Routing it through the record temp-copy path below would substitute a
    throwaway record temp for the real array slot whenever the element record is
    >8 bytes — corrupting e.g. SetLength's target (the array was lost, the temp
    resized). Only fires when the element record is large, so it stayed latent
    until a >8-byte (e.g. managed-field) record element appeared. }
  argIsWholeArray := (ASTKind[argAST] = AN_IDENT) and
     (Integer(ASTIVal[argAST]) >= 0) and (Integer(ASTIVal[argAST]) < SymCount) and
     Syms[ASTIVal[argAST]].IsArray;
  if (argTk = tyRecord) and not argIsWholeArray then
  begin
    argRecId := ResolveNodeRec(argAST);
    if CProgramMode then
      { C struct-by-value: a record param is by-ref ABI (8-byte pointer slot),
        so ALWAYS copy the record to a temp and pass &temp — true by-value with
        correct field access for any size. C-mode-gated -> Pascal byte-identical. }
      needTemp := True
    else if isRefArg then
    begin
      if not IsASTLValue(argAST) then
        needTemp := True
      else if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < MAX_PROC_PARAMS) and
              not ProcParamExplicitByRef[cpi * MAX_PROC_PARAMS + pathIdx] then
        { A plain (no var/const/out) record param over 8 bytes is promoted to
          by-ref purely for ABI efficiency (avoid a large by-value copy through
          registers/stack) -- `isRefArg` is True here for that reason alone, NOT
          because the user asked for aliasing. An lvalue argument passed
          straight through by address would let the callee mutate the CALLER's
          storage, breaking by-value semantics (bug-byvalue-record-managed-
          field-aliases-caller). ProcParamExplicitByRef is False only for this
          silently-promoted case (True for genuine var/out and for const,
          which correctly keep aliasing semantics), so force the same private-
          copy path used for a non-lvalue argument. }
        needTemp := True;
    end
    else
    begin
      if RecSize(argRecId) > 8 then
        needTemp := True;
    end;
  end;

  { A scalar non-lvalue (typically `nil`) given to a by-ref RECORD param —
    e.g. nil to a method-pointer param (fgl's SetOnKeyPtrCompare(nil)).
    Materialise a zeroed temp of the param's record type and store the scalar
    into its first pointer slot; the callee compares that slot (Proc <> nil). }
  if isRefArg and (not needTemp) and (argTk <> tyRecord) and
     (not IsASTLValue(argAST)) and (cpi >= 0) and (pathIdx >= 0) and
     (pathIdx < Procs[cpi].ParamCount) and (pathIdx < MAX_PROC_PARAMS) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyRecord) then
  begin
    savedLastTypeRecId := LastTypeRecId;
    LastTypeRecId := ProcParamRecId[cpi * MAX_PROC_PARAMS + pathIdx];
    if LastTypeRecId = REC_NONE then LastTypeRecId := EnsureMethodPtrRec;
    argRecId := LastTypeRecId;
    tmpSym := AllocVar('', tyRecord);
    LastTypeRecId := savedLastTypeRecId;
    IRAppend(IR_DEFAULT_MEM,
      IRAppend(IR_SLOTADDR, tmpSym, -1, -1, 0, Ord(tyPointer)),
      -1, REC_NONE, RecSize(argRecId), Ord(tyRecord));
    tmpAddr := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));
    value := IRLowerAST(argAST);
    IRAppend(IR_STORE_MEM, tmpAddr, value, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));
    Exit;
  end;

  if needTemp then
  begin
    savedLastTypeRecId := LastTypeRecId;
    LastTypeRecId := argRecId;
    tmpSym := AllocVar('', tyRecord);
    LastTypeRecId := savedLastTypeRecId;
    { A managed-field record temp is filled by IR_COPY_REC_MANAGED below, which
      RELEASES the destination's old managed fields before copying. This temp is
      allocated during IR lowering, after the parser's prologue zero-init pass,
      so without a nil-init its fields hold stack garbage and the release frees a
      bogus handle (double-free / heap corruption — crashes when the arg is a
      managed-record value, e.g. `f(g(x), …)` with g returning a managed record).
      Mark it so codegen nil-inits its full extent before the body, exactly like
      the hidden aggregate-result temp in IRAppendCall. }
    if RecordHasManagedFields(argRecId) then
      SymIsHiddenArgTemp[tmpSym] := True;

    tmpAddr := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));

    if IsASTLValue(argAST) then
      srcAddr := IRLowerAddress(argAST)
    else
      srcAddr := IRLowerAST(argAST);

    if RecordHasManagedFields(argRecId) then
      IRAppend(IR_COPY_REC_MANAGED, tmpAddr, srcAddr, argRecId, RecSize(argRecId), Ord(tyRecord))
    else
      IRAppend(IR_COPY_REC, tmpAddr, srcAddr, -1, RecSize(argRecId), Ord(tyRecord));

    { COM/ARC interface by-VALUE param: this private temp is an owning reference
      released at the caller's scope exit (EmitManagedLocalCleanup). Without a
      matching retain here the raw copy_rec above just aliases the caller's single
      reference, so the temp's scope-exit release double-drops it (silent
      use-after-free if the callee re-published the value, e.g. to a global). A
      `const` interface param never reaches this path — it stays a by-ref alias of
      the caller's slot (no copy, no refcount), matching FPC. }
    if (argRecId >= REC_UCLASS_BASE) and UClsIsInterface[argRecId - REC_UCLASS_BASE] and
       UClsIsComInterface[argRecId - REC_UCLASS_BASE] then
    begin
      arcArg1 := IRAppend(IR_ARG, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)), -1, -1, 0, Ord(tyPointer));
      arcArg2 := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, argRecId - REC_UCLASS_BASE, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
      IRB[arcArg1] := arcArg2;
      arcCall := IRAppendCall(FindProc('PXXIntfAddRef'), arcArg1, -1, Ord(tyNativeInt));
      IRIVal[arcCall] := 1;
    end;

    value := tmpAddr;
  end
  else
  begin
    if isRefArg then
    begin
      { A VARIANT argument travels by address, and a variant RVALUE — the
        `(v + 1)` in `(v + 1) * 2`, whose lowering is an IR_VAR_BINOP result —
        has none. Park it in a variant temp first, exactly as IRVariantAddr
        does for the other by-address paths; without this a nested variant
        operand hit IR_UNSUPPORTED
        (bug-a-nilpy-int-times-variant-in-sum-not-lowered). }
      if (argTk = tyVariant) and
         not (ASTKind[argAST] in [AN_IDENT, AN_FIELD, AN_INDEX, AN_DEREF, AN_CALL]) then
      begin
        value := IRVariantAddr(argAST);
        IRLowerCallArg := value;
        Exit;
      end;
      if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < MAX_PROC_PARAMS) and
         (ProcParamDynDepth[cpi * MAX_PROC_PARAMS + pathIdx] > 0) and
         (ASTKind[argAST] = AN_IDENT) and
         not ((Syms[ASTIVal[argAST]].Kind = skParam) and
              Syms[ASTIVal[argAST]].IsRef) then
        { var/out named-dynamic-array param: pass the ADDRESS of the caller's
          handle slot (&caller_slot) so SetLength can publish a resized handle
          back. IR_LEA over a dyn-array ident would instead yield the handle
          VALUE, so use IR_SLOTADDR explicitly (mirrors the by-ref AnsiString
          arg below). A forwarded by-ref param already holds &caller_slot in its
          slot, so it takes the IRLowerAddress path. }
        value := IRAppend(IR_SLOTADDR, ASTIVal[argAST], -1, -1, 0, Ord(tyPointer))
      else if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < MAX_PROC_PARAMS) and
         (ProcParamDynDepth[cpi * MAX_PROC_PARAMS + pathIdx] > 0) and
         (ASTKind[argAST] = AN_DEREF) then
      begin
        { `p^` (p: ^TArr) to a var/out named-dyn-array param. In this dialect a
          pointer-to-dyn-array holds the HANDLE (the array convention: @la and
          p^[i] both work on the data pointer), so there is no addressable
          handle SLOT to pass — but the callee's convention is &slot (it derefs
          once to reach the handle). IRLowerAddress handed it the handle
          directly, so the callee read element 0 as the handle and crashed
          (bug-parallel-for-captured-dynarray-var-arg-segfault: the parallel-for
          worker's capture accessor is exactly such a p^). Materialise a hidden
          slot: temp := handle, pass &temp. Element writes alias the shared
          buffer, so they propagate; a SetLength through the param lands in the
          temp only (resize-through-p^ has no home to publish to — same
          copy-in-no-copy-out shape as an open-array temp). A plain tyPointer
          temp on purpose: a dyn-array-typed local would DecRef the borrowed
          handle at scope exit. }
        tmpSym := AllocVar('', tyPointer);
        value := IRLowerAST(ASTLeft[argAST]);
        IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(tyPointer));
        value := IRAppend(IR_SLOTADDR, tmpSym, -1, -1, 0, Ord(tyPointer));
      end
      else if (cpi >= 0) and
         (ASTKind[argAST] = AN_IDENT) and
         (Syms[ASTIVal[argAST]].TypeKind = tyAnsiString) and
         { an ARRAY of AnsiString carries the element type in TypeKind — it is
           not a managed-string slot; a dyn array to a var open-array param
           passes its data-pointer VALUE (IRLowerAddress), matching the scalar-
           element arrays and the callee's [data-8] Length read. }
         not Syms[ASTIVal[argAST]].IsArray and
         not ((Syms[ASTIVal[argAST]].Kind = skParam) and
              Syms[ASTIVal[argAST]].IsRef) then
        value := IRAppend(IR_SLOTADDR, ASTIVal[argAST], -1, -1, 0, Ord(tyPointer))
      else
        value := IRLowerAddress(argAST);
    end
    else
    begin
      { `p^` (p: ^TArr) to a BY-VALUE dyn-array param: the callee wants the
        HANDLE, which is p's value — the mirror of the by-ref case above.
        IRLowerAST over the deref would load [handle], i.e. element 0
        (bug-parallel-for-captured-dynarray-var-arg-segfault, const/value arm). }
      if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < MAX_PROC_PARAMS) and
         (pathIdx < Procs[cpi].ParamCount) and
         (ProcParamDynDepth[cpi * MAX_PROC_PARAMS + pathIdx] > 0) and
         (ASTKind[argAST] = AN_DEREF) then
      begin
        Result := IRLowerAST(ASTLeft[argAST]);
        Exit;
      end;
      value := IRLowerAST(argAST);
      if (argTk = tyRecord) and ((ASTKind[argAST] = AN_CALL) or (ASTKind[argAST] = AN_BINOP)) then
        value := IRAppend(IR_LOAD_MEM, value, -1, -1, 0, ASTTk[argAST]);
      { Integer argument to a float parameter: convert. The call ABI carries a
        float as its IEEE bits; an integer value (raw bits in a GPR) would be
        misread by the callee as a float (e.g. V(1,1,1) into Double params gives
        0.0). Round-trip through a hidden float temp, whose STORE already does the
        int->float (cvtsi2sd) conversion uniformly on every target
        (feature-int-to-float-assign). }
      if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
         TypeIsFloat(Procs[cpi].Params[pathIdx].TypeKind) and
         (not TypeIsFloat(argTk)) and TypeIsOrdinal(argTk) then
      begin
        tmpSym := AllocVar('', Procs[cpi].Params[pathIdx].TypeKind);
        IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
        value := IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
      end;
    end;
  end;
  Result := value;
end;

function IsConstStrLitNode(n: Integer): Boolean;
{ A compile-time string-or-char literal (foldable in an ESP tyString concat). }
begin
  Result := (ASTKind[n] = AN_STR_LIT) or
            ((ASTKind[n] = AN_INT_LIT) and (IntToTypeKind(ASTTk[n]) = tyChar));
end;

function ConstStrLitValue(n: Integer): AnsiString;
{ The string value of a node accepted by IsConstStrLitNode. }
begin
  if ASTKind[n] = AN_STR_LIT then
    Result := GetTokenStrFromRaw(ASTSOffset[n], ASTSLen[n])
  else
  begin
    Result := '';
    AppendChar(Result, Chr(Integer(ASTIVal[n])));
  end;
end;

{ ===== Pascal case-statement label validation ============================
  Runs at AN_CASE lowering, before any IR is emitted. Checks every label
  against the selector's type (string vs ordinal), rejects inverted ranges
  (lo > hi) and any duplicate/overlapping label pair — FPC rejects all of
  these at compile time (bug-case-of-string-segfault-and-label-validation). }

{ Lexicographic 3-way compare; orders string labels exactly the way the
  runtime comparison (EmitAnsiStrCmp3Reg et al.) orders them: byte-wise on
  the common prefix, then by length. }
function CaseStrCmp3(const a, b: AnsiString): Integer;
var i, n: Integer;
begin
  n := Length(a);
  if Length(b) < n then n := Length(b);
  i := 1;
  while i <= n do
  begin
    if a[i] <> b[i] then
    begin
      if Ord(a[i]) < Ord(b[i]) then Result := -1 else Result := 1;
      Exit;
    end;
    Inc(i);
  end;
  if Length(a) < Length(b) then Result := -1
  else if Length(a) > Length(b) then Result := 1
  else Result := 0;
end;

{ One label's [lo,hi] interval (hi = lo for a plain label), typed per the
  selector. Also the type check: a string selector needs string-constant
  labels (a char literal counts — its source span is preserved so the
  lowering can rebuild the literal); an ordinal selector rejects multi-char
  string labels. }
procedure CaseLabelBounds(lab: Integer; isStr: Boolean;
                          var lo, hi: Int64; var slo, shi: AnsiString);
begin
  if isStr then
  begin
    if (not IsConstStrLitNode(lab)) or
       ((ASTKind[lab] = AN_INT_LIT) and (ASTSLen[lab] = 0)) then
      Error('case of string: label must be a string constant');
    slo := ConstStrLitValue(lab);
    shi := slo;
    if ASTRight[lab] <> -1 then
    begin
      if (not IsConstStrLitNode(ASTRight[lab])) or
         ((ASTKind[ASTRight[lab]] = AN_INT_LIT) and (ASTSLen[ASTRight[lab]] = 0)) then
        Error('case of string: label must be a string constant');
      shi := ConstStrLitValue(ASTRight[lab]);
    end;
    if StrictCase and (CaseStrCmp3(slo, shi) > 0) then
      Error('case range: lower bound is greater than upper bound');
  end
  else
  begin
    if ASTKind[lab] = AN_STR_LIT then
      Error('case label does not match the ordinal selector type');
    lo := ASTIVal[lab];
    hi := lo;
    if ASTRight[lab] <> -1 then
    begin
      if ASTKind[ASTRight[lab]] = AN_STR_LIT then
        Error('case label does not match the ordinal selector type');
      hi := ASTIVal[ASTRight[lab]];
    end;
    if StrictCase and (lo > hi) then
      Error('case range: lower bound is greater than upper bound');
  end;
end;

{ O(n^2) pairwise overlap check straight over the AST branch chain (no label
  arrays -- a case can be arbitrarily large). branchSeqHead = AN_SEQ chain of
  AN_PAIR(labels, stmt); the else branch has labels = -1. }
procedure IRValidateCaseLabels(branchSeqHead: Integer; isStr: Boolean);
var
  bs, ln, bs2, ln2: Integer;
  lo, hi, lo2, hi2: Int64;
  slo, shi, slo2, shi2: AnsiString;
  clash: Boolean;
begin
  lo := 0; hi := 0; lo2 := 0; hi2 := 0;
  bs := branchSeqHead;
  while bs <> -1 do
  begin
    if ASTLeft[bs] = -1 then ln := -1        { empty chain / else branch }
    else ln := ASTLeft[ASTLeft[bs]];
    while (ln <> -1) and (ASTLeft[ln] <> -1) do
    begin
      CaseLabelBounds(ASTLeft[ln], isStr, lo, hi, slo, shi);
      { against every label after this one -- FPC-parity duplicate/overlap
        rejection is opt-in (--strict-case); the lax dialect keeps first-match
        semantics for overlapping labels. The CaseLabelBounds walk above stays
        unconditional: it carries the selector-type checks the lowering needs. }
      if StrictCase then
      begin
        ln2 := ASTRight[ln];
        bs2 := bs;
        while bs2 <> -1 do
        begin
          while (ln2 <> -1) and (ASTLeft[ln2] <> -1) do
          begin
            CaseLabelBounds(ASTLeft[ln2], isStr, lo2, hi2, slo2, shi2);
            if isStr then
              clash := not ((CaseStrCmp3(shi, slo2) < 0) or (CaseStrCmp3(shi2, slo) < 0))
            else
              clash := not ((hi < lo2) or (hi2 < lo));
            if clash then
              Error('duplicate or overlapping case label');
            ln2 := ASTRight[ln2];
          end;
          bs2 := ASTRight[bs2];
          if bs2 = -1 then ln2 := -1
          else if ASTLeft[bs2] = -1 then ln2 := -1
          else ln2 := ASTLeft[ASTLeft[bs2]];
        end;
      end;
      ln := ASTRight[ln];
    end;
    bs := ASTRight[bs];
  end;
end;

{ The IR constant for one case-label value node: a string-case label becomes
  IR_CONST_STR from its preserved source span (char literals kept theirs, so
  a length-1 label still rebuilds); an ordinal label the usual IR_CONST_INT.
  Type mismatches were already rejected by IRValidateCaseLabels. }
function IRCaseLabelConst(lab: Integer; isStr: Boolean): Integer;
begin
  if isStr then
    Result := IRAppend(IR_CONST_STR, ASTSOffset[lab], ASTSLen[lab], -1, 0, Ord(tyString))
  else
    Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[lab], Ord(tyInteger));
end;

function IsClassDescOrSelf(c, target: Integer): Boolean;
{ True if class c is `target` or transitively descends it (closed-world walk of
  the compile-time parent chain). Drives the is/as VMT-set test. }
var cur: Integer;
begin
  Result := False;
  cur := c;
  while cur >= 0 do
  begin
    if cur = target then begin Result := True; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function IRExcStoreSlot(n: Integer): Integer;
{ Which runtime STATUS slot an IR_EXC_STORE reads. IRC selects it: 0 (the
  default, `on E: T do`) = the exception OBJECT; 1 (__pxxExceptAddr) = the RAISE
  SITE the raise stub recorded; 2/3/4 (__pxxSigCode/__pxxSigAddr/
  __pxxSigContext) = the siginfo fields the signal dispatch stub parked. Same
  load, different slot — which is why none of them needs a backend op, and why
  adding the signal three cost nothing in the six backends (they all route
  IR_EXC_STORE through this function).

  The op keeps its exception-era name; what it really means is "load a
  compiler-owned status slot". Worth renaming if a fourth family shows up. }
begin
  if IRC[n] = 1 then Result := BSS_EXC_ADDR
  else if IRC[n] = 2 then Result := BSS_SIG_CODE
  else if IRC[n] = 3 then Result := BSS_SIG_ADDR
  else if IRC[n] = 4 then Result := BSS_SIG_CTX
  else Result := BSS_EXC_OBJ;
end;

function UContextPCOffset: Integer;
{ Byte offset of the saved PROGRAM COUNTER inside the `ucontext_t` the kernel
  hands a SA_SIGINFO handler — the one fact behind __pxxSigPCPtr, and the only
  piece of per-arch signal-frame knowledge the compiler carries. Writing this
  word is what turns a fault into a catchable raise: point it at a Pascal proc
  that raises, return from the handler, and the kernel resumes THERE.

  MEASURED, not read off a header (feature-signal-siginfo-ucontext, 2026-08-13).
  A probe faulted two ways under each target's qemu — by WRITING $DEAD0000 and
  by CALLING it — and dumped every ucontext word equal to that sentinel. A word
  that matches in BOTH runs is a fault-address field; the one that matches ONLY
  when the fault was a jump is the saved PC. Each answer below also equals what
  the kernel's struct definitions predict, so two independent sources agree:

    x86-64   168 = uc_mcontext(40) + gregs[REG_RIP=16]*8
    aarch64  440 = uc_mcontext(176) + fault_address(8) + regs[31]*8 + sp(8)
    arm32     92 = uc_mcontext(20)  + arm_pc(72)
    i386      76 = uc_mcontext(20)  + gregs[REG_EIP=14]*4
    riscv32  160 = uc_mcontext(160) + sc_regs.pc, which is its first field

  xtensa never reaches here — the parser refuses every __pxxSig* on it, because
  FreeRTOS has no signal runtime at all. }
begin
  if TargetArch = TARGET_X86_64 then Result := 168
  else if TargetArch = TARGET_AARCH64 then Result := 440
  else if TargetArch = TARGET_ARM32 then Result := 92
  else if TargetArch = TARGET_I386 then Result := 76
  else if TargetArch = TARGET_RISCV32 then Result := 160
  else Result := -1;   { unreachable: the parser refused this target already }
end;

{ OPEN-WORLD is-a, at RUNTIME: given a symbol already holding an instance pointer,
  emit IR computing a Boolean temp = inst is a `targetCi` (or any descendant),
  by walking the RTTI blobs' PARENT CHAIN — the same __pxxInheritsFrom machinery
  x.InheritsFrom(C) uses, and reflexive like FPC's.

  This is what makes the check correct for classes the lowering site has never
  seen. Enumerating the descendant set instead only works when every descendant
  is already known, and units compile in dependency order — so a subclass declared
  in a LATER unit silently falls out of the set.

  Returns the Boolean temp's sym, or -1 when the walk is unavailable (no builtin
  unit — ESP) so the caller can fall back to its enumeration. Only meaningful for
  a CLASS target: interface membership (IMT) is not on the blob's parent chain. }
function IRClassMatchRuntime(instSym, targetCi: Integer): Integer;
var rvar, endLbl, znode, notnil, vmtSym, lv, blob: Integer;
    cmPi, cmArg1, cmArg2, cmCall: Integer;
begin
  Result := -1;
  if UClsIsInterface[targetCi] then Exit;
  cmPi := FindProc('__pxxInheritsFrom');
  if cmPi < 0 then Exit;

  rvar := AllocVar('', tyBoolean);
  vmtSym := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, rvar, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyBoolean)), -1, 0, Ord(tyBoolean));
  endLbl := IRNewLabel;

  { nil instance -> false }
  lv := IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer));
  znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
  notnil := IRAppend(IR_BINOP, lv, znode, Ord(tkNeq), 0, Ord(tyBoolean));
  IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);

  { vmt := [inst + 0]. A VMT-less instance (the implicit root TObject stores no
    table) stays false rather than dereferencing garbage. }
  IRAppend(IR_STORE_SYM, vmtSym,
           IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                    -1, -1, 0, Ord(tyPointer)),
           -1, 0, Ord(tyPointer));
  lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
  znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
  notnil := IRAppend(IR_BINOP, lv, znode, Ord(tkNeq), 0, Ord(tyBoolean));
  IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);

  { blob := [vmt - 8] — the RTTI backlink; hard 8 on every target (see AN_RTTIOF). }
  blob := IRAppend(IR_LOAD_MEM,
            IRAppend(IR_BINOP,
              IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer)),
              IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyPointer)),
              Ord(tkMinus), 0, Ord(tyPointer)),
            -1, -1, 0, Ord(tyPointer));
  IRAppend(IR_STORE_SYM, vmtSym, blob, -1, 0, Ord(tyPointer));
  lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
  znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
  notnil := IRAppend(IR_BINOP, lv, znode, Ord(tkNeq), 0, Ord(tyBoolean));
  IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);

  cmArg1 := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
  cmArg2 := IRAppend(IR_ARG, IRAppend(IR_CLASSREF, targetCi, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
  IRB[cmArg1] := cmArg2;
  cmCall := IRAppendCall(cmPi, cmArg1, -1, Ord(tyBoolean));
  IRAppend(IR_STORE_SYM, rvar, cmCall, -1, 0, Ord(tyBoolean));
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
  Result := rvar;
end;

{ Emit IR that evaluates `instExpr` once into a hidden pointer temp (returned in
  instSym) and computes a Boolean temp = (inst <> nil) and (VMT(inst) is the VMT
  of `targetCi` or any descendant). Returns the Boolean temp's sym index. The
  descendant set is enumerated here, at codegen, so classes declared after the
  is/as site are included (whole-program closed world). Shared by `is` and `as`. }
function IRLowerClassMatch(instExpr, targetCi: Integer; var instSym: Integer): Integer;
var rvar, instVal, endLbl, skipLbl, c, li, znode, notnil, vmtSym, lv, va, eq: Integer;
    cmPi, cmBlob, cmArg1, cmArg2, cmCall: Integer;
begin
  rvar := AllocVar('', tyBoolean);
  instSym := AllocVar('', tyPointer);
  vmtSym := AllocVar('', tyPointer);
  instVal := IRLowerAST(instExpr);
  IRAppend(IR_STORE_SYM, instSym, instVal, -1, 0, Ord(tyPointer));
  IRAppend(IR_STORE_SYM, rvar, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyBoolean)), -1, 0, Ord(tyBoolean));
  endLbl := IRNewLabel;
  { nil instance: leave rvar false }
  li := IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer));
  znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
  notnil := IRAppend(IR_BINOP, li, znode, Ord(tkNeq), 0, Ord(tyBoolean));
  IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);
  { OPEN-WORLD class match: the VMT-set enumeration below runs when the site's
    OWN unit lowers, so a subclass declared in a LATER unit (or the program) is
    not in the set — fpjson's `FList[Index] as TJSONData` Halt(1)-trapped on a
    program-declared TJSONNull subclass. For a CLASS target, walk the RTTI
    blobs' parent chain at runtime instead (__pxxInheritsFrom on
    blob = [[inst+0]-8], reflexive, same machinery x.InheritsFrom(C) uses) —
    correct for classes it has never seen. Interface targets keep the
    enumeration (IMT membership is not on the blob chain), as does any build
    without the builtin unit (ESP). }
  if (not UClsIsInterface[targetCi]) and (FindProc('__pxxInheritsFrom') >= 0) then
  begin
    cmPi := FindProc('__pxxInheritsFrom');
    { vmt := [inst + 0]; a VMT-LESS instance (the implicit root TObject stores
      no table) keeps rvar false — the old enumeration never dereferenced
      either, it only COMPARED. Without this guard the blob load below reads
      through garbage. }
    vmtSym := AllocVar('', tyPointer);
    IRAppend(IR_STORE_SYM, vmtSym,
             IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                      -1, -1, 0, Ord(tyPointer)),
             -1, 0, Ord(tyPointer));
    lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
    znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
    notnil := IRAppend(IR_BINOP, lv, znode, Ord(tkNeq), 0, Ord(tyBoolean));
    IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);
    { blob := [vmt - 8] — the RTTI backlink; hard 8 on every target (see AN_RTTIOF).
      A null backlink also keeps rvar false. }
    cmBlob := IRAppend(IR_LOAD_MEM,
                IRAppend(IR_BINOP,
                  IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer)),
                  IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyPointer)),
                  Ord(tkMinus), 0, Ord(tyPointer)),
                -1, -1, 0, Ord(tyPointer));
    IRAppend(IR_STORE_SYM, vmtSym, cmBlob, -1, 0, Ord(tyPointer));
    lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
    znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
    notnil := IRAppend(IR_BINOP, lv, znode, Ord(tkNeq), 0, Ord(tyBoolean));
    IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);
    cmArg1 := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
    cmArg2 := IRAppend(IR_ARG, IRAppend(IR_CLASSREF, targetCi, -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
    IRB[cmArg1] := cmArg2;
    cmCall := IRAppendCall(cmPi, cmArg1, -1, Ord(tyBoolean));
    IRAppend(IR_STORE_SYM, rvar, cmCall, -1, 0, Ord(tyBoolean));
    IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
    Result := rvar;
    Exit;
  end;
  { vmt := [inst+0] }
  IRAppend(IR_STORE_SYM, vmtSym,
           IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                    -1, -1, 0, Ord(tyPointer)),
           -1, 0, Ord(tyPointer));
  { Match set: for a class target, c is the class or a descendant; for an
    interface target, c is any class that implements it (directly or inherited,
    via FindIMT). So `obj is IFoo` is true iff obj's class implements IFoo. }
  for c := 0 to UClsCount - 1 do
    if (UClsVMTOffset[c] >= 0) and
       ( (UClsIsInterface[targetCi] and (FindIMT(c, targetCi) >= 0)) or
         ((not UClsIsInterface[targetCi]) and IsClassDescOrSelf(c, targetCi)) ) then
    begin
      lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
      va := IRAppend(IR_VMTADDR, c, -1, -1, 0, Ord(tyPointer));
      eq := IRAppend(IR_BINOP, lv, va, Ord(tkEq), 0, Ord(tyBoolean));
      skipLbl := IRNewLabel;
      IRAppend(IR_JUMP_IF_FALSE, skipLbl, eq, -1, 0, 0);
      IRAppend(IR_STORE_SYM, rvar, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyBoolean)), -1, 0, Ord(tyBoolean));
      IRAppend(IR_LABEL, -1, -1, -1, skipLbl, 0);
    end;
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
  Result := rvar;
end;

function IRMaterializeIntfCast(node: Integer; doTrap: Boolean): Integer;
{ Build the interface value for `obj as IFoo` (or an implicit class->interface
  coercion) into a hidden interface temp; return the temp's symbol.

  An interface VALUE is ONE pointer: the instance (FPC's ABI). So the "build" is
  just a store of the instance — what remains is the CHECK: a non-nil instance
  whose runtime class does not implement the interface is a bad cast and traps
  (Halt 1) when doTrap. nil -> nil, never traps. The implements test is the same
  closed-world VMT match `is` uses.

  Memoised in ASTLiftedVar: the interface-call path takes the value's address more
  than once, so this must build it once. }
var intfCi, tmpSym, instSym, instVal, endLbl, c, skipLbl, savedRec: Integer;
    li, vmtSym, lv, va, eq: Integer;
begin
  if ASTLiftedVar[node] >= 0 then begin Result := ASTLiftedVar[node]; Exit; end;
  intfCi := Integer(ASTIVal[node]);
  savedRec := LastTypeRecId;
  LastTypeRecId := REC_UCLASS_BASE + intfCi;
  tmpSym := AllocVar('', tyRecord);          { size = TARGET_PTR_SIZE }
  LastTypeRecId := savedRec;
  ASTLiftedVar[node] := tmpSym;

  instSym := AllocVar('', tyPointer);
  { The instance is a single pointer. A plain object/interface-var operand lowers
    straight to that pointer, but an interface `as`-cast operand lowers to the
    ADDRESS of its fat-pointer temp (see the AN_AS_CAST value path) — so a nested
    `(x as IA) as IB` would store the temp's address as the "instance" and the
    trap below would read the wrong word and Halt 1 on a valid cast. Deref it to
    recover the instance value. See bug-pascal-nested-interface-as-cast. }
  if (ASTKind[ASTLeft[node]] = AN_AS_CAST) and
     UClsIsInterface[Integer(ASTIVal[ASTLeft[node]])] then
    instVal := IRAppend(IR_LOAD_MEM, IRLowerAST(ASTLeft[node]), -1, -1, 0, Ord(tyPointer))
  else
    instVal := IRLowerAST(ASTLeft[node]);
  IRAppend(IR_STORE_SYM, instSym, instVal, -1, 0, Ord(tyPointer));

  { the value IS the instance }
  IRAppend(IR_STORE_MEM, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)),
           IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));

  { COM/ARC interface `as`-cast is a QueryInterface: it AddRefs the result, which
    lives as an owning reference until the enclosing routine's scope exit
    (EmitManagedLocalCleanup releases every skLocal COM-interface temp). Without
    the retain the temp just ALIASES the source's single reference, so the
    scope-exit release under-refcounts: the object is destroyed when the routine
    returns instead of at end-of-routine (bug-pascal-interface-finalization-crash),
    and a later release of the same object double-drops → SIGSEGV with a fuller
    graph. PXXIntfAddRef is nil-safe. Mirrors the by-value-param retain in
    IRLowerCallArg. A skLocal temp is released by EmitManagedLocalCleanup; a
    main-body temp is skGlobal (no scope-exit) so it is recorded here and released
    at program exit (bug-pascal-mainbody-ascast-temp-finalization-timing) — matching
    FPC's end-of-main lifetime. }
  if (intfCi >= 0) and (intfCi < UClsCount) and UClsIsComInterface[intfCi] and
     ((Syms[tmpSym].Kind = skLocal) or (Syms[tmpSym].Kind = skGlobal)) then
  begin
    li := IRAppend(IR_ARG, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)), -1, -1, 0, Ord(tyPointer));
    lv := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, intfCi, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
    IRB[li] := lv;
    va := IRAppendCall(FindProc('PXXIntfAddRef'), li, -1, Ord(tyNativeInt));
    IRIVal[va] := 1;
    if Syms[tmpSym].Kind = skGlobal then
    begin
      if MainBodyIntfTempCount > High(MainBodyIntfTempSym) then
        Error('too many main-body interface as-cast temps');
      MainBodyIntfTempSym[MainBodyIntfTempCount] := tmpSym;
      Inc(MainBodyIntfTempCount);
    end;
  end;

  if not doTrap then
  begin
    Result := tmpSym;
    Exit;
  end;

  endLbl := IRNewLabel;
  { nil instance: never traps. }
  li := IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer));
  IRAppend(IR_JUMP_IF_FALSE, endLbl,
           IRAppend(IR_BINOP, li, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                    Ord(tkNeq), 0, Ord(tyBoolean)), -1, 0, 0);
  { vmt := [inst]; matching any class that implements the interface = a good cast. }
  vmtSym := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, vmtSym,
           IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                    -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
  for c := 0 to UClsCount - 1 do
    if (UClsVMTOffset[c] >= 0) and (FindIMT(c, intfCi) >= 0) then
    begin
      lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
      va := IRAppend(IR_VMTADDR, c, -1, -1, 0, Ord(tyPointer));
      eq := IRAppend(IR_BINOP, lv, va, Ord(tkEq), 0, Ord(tyBoolean));
      skipLbl := IRNewLabel;
      IRAppend(IR_JUMP_IF_FALSE, skipLbl, eq, -1, 0, 0);
      IRAppend(IR_JUMP, endLbl, -1, -1, 0, 0);     { implements it -> no trap }
      IRAppend(IR_LABEL, -1, -1, -1, skipLbl, 0);
    end;
  { non-nil instance whose class implements no matching interface: a bad cast. }
  IRAppend(IR_TERMINATE, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), -1, -1, AN_HALT, 0);
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
  Result := tmpSym;
end;

function NodeIsInterface(node: Integer): Boolean;
{ True iff the node is an interface-typed value (a single instance pointer). }
var rec: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  if IntToTypeKind(ASTTk[node]) <> tyRecord then Exit;
  rec := ResolveNodeRec(node);
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
end;

function IRIntfInstanceWord(node: Integer): Integer;
{ The instance pointer of an interface value — which, an interface value BEING a
  single instance pointer (FPC's ABI), is just the value itself. Used for identity
  comparison. A non-interface operand (a nil literal) lowers to its plain value, so
  `iface = nil` compares against 0. }
begin
  if NodeIsInterface(node) then
    Result := IRAppend(IR_LOAD_MEM, IRLowerAddress(node), -1, -1, 0, Ord(tyPointer))
  else
    Result := IRLowerAST(node);
end;

{ Runtime mutation of one bit of a 32-byte set: set (isIncl) or clear bit `val`
  in the set at `setAddrNode`. The value is masked to 0..255 so the byte index
  always lands inside the 32-byte set — out-of-range elements are ignored, like
  the constant set-literal bake path. setAddrNode is an already-lowered address
  node; valNode is an already-lowered integer value. Emits the load/modify/store
  as a statement. Target-independent: only IR_BINOP / IR_LOAD_MEM / IR_STORE_MEM
  primitives, which every backend already implements. (`shr` is IR_BINOP with op
  Ord(tkIdent), matching the term parser.) }
procedure IRLowerSetBitMutate(setAddrNode, valNode: Integer; isIncl: Boolean);
var vTmp, ptrTmp, mask, curByte, newByte: Integer;
begin
  { Evaluate the value once. }
  vTmp := AllocVar('', tyInteger);
  IRAppend(IR_STORE_SYM, vTmp, valNode, -1, 0, Ord(tyInteger));
  { byteAddr := setAddr + ((val and 255) shr 3); cache in a pointer temp so the
    address is computed once and reused by the load and the store. }
  ptrTmp := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, ptrTmp,
    IRAppend(IR_BINOP, setAddrNode,
      IRAppend(IR_BINOP,
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, vTmp, -1, -1, 0, Ord(tyInteger)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 255, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 3, Ord(tyInteger)), Ord(tkIdent), 0, Ord(tyInteger)),
      Ord(tkPlus), 0, Ord(tyPointer)),
    -1, 0, Ord(tyPointer));
  { mask := 1 shl ((val and 255) and 7). }
  mask := IRAppend(IR_BINOP,
            IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
            IRAppend(IR_BINOP,
              IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, vTmp, -1, -1, 0, Ord(tyInteger)),
                IRAppend(IR_CONST_INT, -1, -1, -1, 255, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
              IRAppend(IR_CONST_INT, -1, -1, -1, 7, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
            Ord(tkShl), 0, Ord(tyInteger));
  curByte := IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, ptrTmp, -1, -1, 0, Ord(tyPointer)),
               -1, -1, 0, Ord(tyUInt8));
  if isIncl then
    newByte := IRAppend(IR_BINOP, curByte, mask, Ord(tkOr), 0, Ord(tyInteger))
  else
    newByte := IRAppend(IR_BINOP, curByte,
                 IRAppend(IR_NOT, mask, -1, -1, 0, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger));
  IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, ptrTmp, -1, -1, 0, Ord(tyPointer)),
    newByte, -1, 0, Ord(tyUInt8));
end;

{ Runtime `lo..hi` range into a set: a counter loop calling IRLowerSetBitMutate.
  lo/hi are already-lowered integer values. Always Include (set literals only
  add). }
procedure IRLowerSetRangeMutate(setSym, loNode, hiNode: Integer);
var iSym, hiSym, topLbl, endLbl: Integer;
begin
  iSym := AllocVar('', tyInteger);
  hiSym := AllocVar('', tyInteger);
  IRAppend(IR_STORE_SYM, iSym, loNode, -1, 0, Ord(tyInteger));
  IRAppend(IR_STORE_SYM, hiSym, hiNode, -1, 0, Ord(tyInteger));
  topLbl := IRNewLabel;
  endLbl := IRNewLabel;
  IRAppend(IR_LABEL, -1, -1, -1, topLbl, 0);
  { while i <= hi }
  IRAppend(IR_JUMP_IF_FALSE, endLbl,
    IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)),
      IRAppend(IR_LOAD_SYM, hiSym, -1, -1, 0, Ord(tyInteger)), Ord(tkLe), 0, Ord(tyBoolean)),
    -1, 0, 0);
  IRLowerSetBitMutate(IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
    IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)), True);
  { i := i + 1 }
  IRAppend(IR_STORE_SYM, iSym,
    IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)),
      IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), Ord(tkPlus), 0, Ord(tyInteger)),
    -1, 0, Ord(tyInteger));
  IRAppend(IR_JUMP, topLbl, -1, -1, 0, 0);
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
end;

{ Append a synthetic string literal to the raw TokChars pool and return an
  IR_CONST_STR node referencing it. Lets IR lowering emit string writes for
  text that is not in the user's source (e.g. Boolean TRUE/FALSE). }
function IRSyntheticConstStr(const s: AnsiString): Integer;
var k, off: Integer;
begin
  off := TokCharLen;
  if TokCharLen + Length(s) > STRING_CAP then Error('token char pool overflow');
  for k := 1 to Length(s) do
  begin
    TokChars[TokCharLen] := s[k];
    Inc(TokCharLen);
  end;
  Result := IRAppend(IR_CONST_STR, off, Length(s), -1, 0, Ord(tyString));
end;

{ Lower a Boolean `write` argument to a TRUE/FALSE string write, branching at
  runtime. Target-independent: emits IR_JUMP_IF_FALSE / IR_WRITE(const_str) /
  IR_JUMP / IR_LABEL, all of which every backend already handles, so the boolean
  output is FPC-correct on all targets at once. Returns the first node; writes
  the final node (the end label) into lastNode. wid = field width (-1 = none). }
function IRLowerBoolWrite(value, wid: Integer; var lastNode: Integer; fd: Integer): Integer;
var bFalse, bEnd: Integer;
begin
  bFalse := IRNewLabel;
  bEnd := IRNewLabel;
  Result := IRAppend(IR_JUMP_IF_FALSE, bFalse, value, -1, 0, 0);
  { Pascal/FPC renders TRUE/FALSE; the Nil-Python frontend renders Python's
    True/False. (ival = target fd, threaded for writeln(StdErr,..).) }
  if isNilPy then
    IRAppend(IR_WRITE, IRSyntheticConstStr('True'), wid, -1, fd, Ord(tyString))
  else
    IRAppend(IR_WRITE, IRSyntheticConstStr('TRUE'), wid, -1, fd, Ord(tyString));
  IRAppend(IR_JUMP, bEnd, -1, -1, 0, 0);
  IRAppend(IR_LABEL, -1, -1, -1, bFalse, 0);
  if isNilPy then
    IRAppend(IR_WRITE, IRSyntheticConstStr('False'), wid, -1, fd, Ord(tyString))
  else
    IRAppend(IR_WRITE, IRSyntheticConstStr('FALSE'), wid, -1, fd, Ord(tyString));
  lastNode := IRAppend(IR_LABEL, -1, -1, -1, bEnd, 0);
end;

{ Dispatch scan: walk the ENTIRE switch body (any depth — case/default labels are
  labels on arbitrarily nested statements, C 6.8.1) assigning each C marker an
  IR_LABEL and, for a case, emitting `if (sel == val) goto label`. Recurses into
  every construct EXCEPT a nested AN_SWITCH (its own cases belong to it). This is
  what lets Duff's device work: the case labels buried inside a do-while are found
  here and the body lowering (normal IRLowerAST) drops the IR_LABELs in place, so
  dispatch can jump straight into the loop. C markers carry ASTSLen=1 (distinct
  from a Pascal AN_CASE statement / the Default(T) node). }
procedure IRLowerCSwitchDispatchScan(node, selTmp, selTk: Integer; var defaultLabel: Integer);
var condNode, selSz: Integer; caseVal: Int64;
begin
  if node < 0 then Exit;
  if ASTKind[node] = AN_SWITCH then Exit;   { nested switch owns its own case labels }
  if (ASTKind[node] = AN_CASE) and (ASTSLen[node] = 1) then
  begin
    ASTSOffset[node] := IRNewLabel;
    { C 6.8.4.2: each case constant is CONVERTED to the promoted controlling
      type. quickjs switches a uint32_t tag over negative enum labels
      (JS_TAG_OBJECT = -1): the label must compare as 0xFFFFFFFF, not as a
      sign-extended 64-bit -1 that never matches a zero-extended selector. }
    caseVal := ASTIVal[node];
    selSz := TypeSize(IntToTypeKind(selTk));
    if (selSz < 8) and TypeCompareUnsigned(IntToTypeKind(selTk), IntToTypeKind(selTk)) and
       (caseVal < 0) then
      caseVal := caseVal and ((Int64(1) shl (selSz * 8)) - 1);
    condNode := IRAppend(IR_BINOP,
      IRAppend(IR_LOAD_SYM, selTmp, -1, -1, 0, selTk),
      IRAppend(IR_CONST_INT, -1, -1, -1, caseVal, selTk),
      Ord(tkNeq), 0, Ord(tyBoolean));
    IRAppend(IR_JUMP_IF_FALSE, ASTSOffset[node], condNode, -1, 0, 0);
    Exit;                                    { marker has no children of interest }
  end;
  if (ASTKind[node] = AN_DEFAULT) and (ASTSLen[node] = 1) then
  begin
    ASTSOffset[node] := IRNewLabel;
    defaultLabel := ASTSOffset[node];
    Exit;
  end;
  IRLowerCSwitchDispatchScan(ASTLeft[node], selTmp, selTk, defaultLabel);
  IRLowerCSwitchDispatchScan(ASTRight[node], selTmp, selTk, defaultLabel);
end;

{ Inline expansion (feature-inline-routines): clone a retained inline body from
  the reserved AST region into the LIVE pool, replacing each AN_INLINE_PARAM(i)
  placeholder with a fresh clone of the call's i-th argument AST (in InlineArgAST).
  The result is a normal live-pool subtree ready for IRLowerAST. }
function IRCloneInlineBody(node: Integer): Integer;
var r: Integer;
begin
  if node < 0 then begin IRCloneInlineBody := -1; Exit; end;
  if ASTKind[node] = AN_INLINE_PARAM then
  begin
    IRCloneInlineBody := CloneAST(InlineArgAST[ASTIVal[node]]);
    Exit;
  end;
  if ASTKind[node] = AN_INLINE_LOCAL then
  begin
    r := AllocNode(AN_IDENT);
    ASTIVal[r] := InlineLocalSym[ASTIVal[node]];
    ASTTk[r]   := ASTTk[node];
    IRCloneInlineBody := r;
    Exit;
  end;
  if ASTKind[node] = AN_INLINE_RESULT then
  begin
    r := AllocNode(AN_IDENT);
    ASTIVal[r] := InlineResultSym;
    ASTTk[r]   := ASTTk[node];
    IRCloneInlineBody := r;
    Exit;
  end;
  r := AllocNode(ASTKind[node]);
  ASTIVal[r]    := ASTIVal[node];
  ASTSOffset[r] := ASTSOffset[node];
  ASTSLen[r]    := ASTSLen[node];
  ASTTk[r]      := ASTTk[node];
  ASTLeft[r]    := IRCloneInlineBody(ASTLeft[node]);
  ASTRight[r]   := IRCloneInlineBody(ASTRight[node]);
  IRCloneInlineBody := r;
end;

{ Is an argument AST side-effect-free AND re-readable (so it can be substituted
  directly, even at several placeholder sites)? Literals and plain scalar idents
  qualify; the inline body is a pure expression that never writes caller state, so
  re-reading such an arg is idempotent. }
function InlineArgIsPure(argAST: Integer): Boolean;
var sidx: Integer;
begin
  InlineArgIsPure := False;
  if argAST < 0 then Exit;
  if ASTKind[argAST] = AN_INT_LIT then begin InlineArgIsPure := True; Exit; end;
  if ASTKind[argAST] = AN_IDENT then
  begin
    sidx := ASTIVal[argAST];
    if (sidx < 0) or (sidx >= SymCount) then Exit;
    if Syms[sidx].IsArray then Exit;
    InlineArgIsPure := True;
  end;
end;

{ Try to expand a direct call to an inline-eligible proc. Returns the IR value
  node of the spliced expression, or -1 if it cannot inline (arg count mismatch)
  — the caller then lowers a normal call. Pure args (literal / plain scalar ident)
  are substituted directly; any other arg expression is evaluated ONCE into a
  fresh scalar temp (left-to-right, before the body) and the placeholder bound to
  that temp — so evaluation order and side effects are preserved without
  re-evaluating a multiply-used param. }
function IRInlineExpand(callNode, cpi: Integer): Integer;
var item, n, clonedRoot, tsym, identNode, aval, resSym: Integer;
    rawArg: array[0..MAX_PROC_PARAMS-1] of Integer;
    boundAST: array[0..MAX_PROC_PARAMS-1] of Integer;
    ptk: TTypeKind; anyImpure: Boolean;
begin
  IRInlineExpand := -1;
  { Pass 1: collect args + validate count (no IR emitted yet). }
  n := 0;
  item := ASTLeft[callNode];
  anyImpure := False;
  while item <> -1 do
  begin
    if ASTKind[item] <> AN_ARG then Exit;
    if (ASTLeft[item] < 0) or (n >= MAX_PROC_PARAMS) then Exit;
    rawArg[n] := ASTLeft[item];
    if not InlineArgIsPure(rawArg[n]) then anyImpure := True;
    Inc(n);
    item := ASTRight[item];
  end;
  if n <> InlineParamCnt[cpi] then Exit;
  { A call-bearing body (non-leaf slice): every arg must be temp-captured —
    a direct-substituted pure arg's placeholder can sit AFTER the body's
    inner call, whose side effects may write the arg's variable. }
  if InlineBodyHasCall[cpi] then anyImpure := True;
  { Pass 2: bind each param INTO LOCALS. If EVERY arg is pure (side-effect-
    free, re-readable), substitute directly. If ANY arg has a side effect,
    capture EVERY arg into a fresh temp in left-to-right order first —
    otherwise a pure arg substituted into a body position would be read AFTER
    a later arg's side effect, breaking Pascal's left-to-right evaluation
    (e.g. Add(x, SetX(99))).

    THE REENTRANCY CONTRACT (root cause of the fuzz-found depth-1 silent -O3
    divergence, reduced to nested calls in a splice's ARGUMENT list): lowering
    an argument here — and later lowering the cloned body — can hit a call
    that re-enters this function, which rebinds every Inline* global. So this
    pass writes ONLY the local boundAST[]; the globals are published inside
    the CLONE WINDOW below, where nothing lowers (hence nothing re-enters)
    before the clone consumes them. Arg capture deliberately runs OUTSIDE the
    InliningActive bump: an argument's own calls inline at the current depth,
    exactly as they would as standalone expressions. }
  for n := 0 to InlineParamCnt[cpi] - 1 do
  begin
    if (not anyImpure) and InlineArgIsPure(rawArg[n]) then
      boundAST[n] := rawArg[n]
    else
    begin
      ptk := Procs[cpi].Params[n].TypeKind;
      tsym := AllocVar('', ptk);
      aval := IRLowerAST(rawArg[n]);
      { A FROZEN string value bound to a Pointer parameter needs the +8
        length-prefix skip — the same decay the ordinary call-argument path
        applies in the AN_CALL arm below (and the assign, binop and return paths
        each apply for their own position). Capturing the argument into a temp
        HERE bypasses all of them: the raw IR_CONST_STR landed in the pointer
        slot, so the callee received a pointer at the 8-byte length prefix
        instead of at char 0.

        Only reachable at -O3, because only a call-bearing retained body forces
        every argument to be temp-captured. `__pxx_open("/etc/localtime", 0, 0)`
        then opened garbage and returned -2, /etc/localtime never loaded, and
        localtime() silently reported UTC
        (bug-a-o3-inline-retention-substitutes-a-global-read-across-a-call —
        the slug describes the theory it was filed under, not this cause).

        Keyed on the LOWERED value's tk, exactly like the call path, so a
        managed tyAnsiString (already a char pointer) is correctly passed
        as-is. }
      if (ptk = tyPointer) and (aval >= 0) and (aval < IRCount) and
         (IntToTypeKind(IRTk[aval]) = tyString) then
        aval := IRAppend(IR_BINOP, aval,
                         IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                         Ord(tkPlus), 0, Ord(tyPointer));
      IRAppend(IR_STORE_SYM, tsym, aval, -1, 0, Ord(ptk));
      identNode := AllocNode(AN_IDENT);
      ASTIVal[identNode] := tsym;
      ASTTk[identNode]   := Ord(ptk);
      boundAST[n]        := identNode;
    end;
  end;
  { Clone window: publish the globals and consume them immediately — IRClone*
    performs no lowering, so no reentry can clobber them first. The Result
    temp is held in the LOCAL resSym across the (reentrant) body lowering. }
  Inc(InliningActive);
  for n := 0 to InlineParamCnt[cpi] - 1 do
    InlineArgAST[n] := boundAST[n];
  if InlineBodyIsStmt[cpi] then
  begin
    { Slice 2b: alloc a caller Result temp + a fresh caller local per callee
      local, clone the statement chain (placeholders → these syms), lower it
      (emits the statements), then yield a load of the Result temp. }
    resSym := AllocVar('', Procs[cpi].RetType);
    InlineResultSym := resSym;
    for n := 0 to InlineLocalCnt[cpi] - 1 do
      InlineLocalSym[n] := AllocVar('', IntToTypeKind(InlineLocalTk[cpi*MAX_INLINE_LOCALS + n]));
    clonedRoot := IRCloneInlineBody(InlineBodyRoot[cpi]);
    IRLowerAST(clonedRoot);
    IRInlineExpand := IRAppend(IR_LOAD_SYM, resSym, -1, -1, 0, Ord(Procs[cpi].RetType));
  end
  else
  begin
    clonedRoot := IRCloneInlineBody(InlineBodyRoot[cpi]);
    IRInlineExpand := IRLowerAST(clonedRoot);
  end;
  Dec(InliningActive);
end;

{ The stack-frame intrinsics all rest on ONE assumption: a linked frame-pointer
  chain, where [fp] is the caller's fp. Every pxx prologue builds one -- except on
  xtensa, whose register windows have no such chain. Refuse there rather than hand
  back a plausible-looking pointer into nothing. }
procedure IRRejectNoFramePointer(const what: AnsiString);
begin
  if TargetArch = TARGET_XTENSA then
    Error(what + ': the stack-frame intrinsics need a linked frame-pointer chain, and xtensa''s register windows have none');
end;

{ Where the saved CALLER frame pointer and the RETURN ADDRESS sit, relative to the
  current frame pointer. Read straight off EmitProcPrologue -- these two functions
  are the only place the frame layout is encoded, so a prologue change has exactly
  one other site to update.

  x86-64  push rbp; mov rbp,rsp            -> [fp+0] caller fp, [fp+8]  ret
  i386    push ebp; mov ebp,esp            -> [fp+0] caller fp, [fp+4]  ret
  arm32   push {fp,lr}; mov fp,sp          -> [fp+0] caller fp, [fp+4]  ret
  aarch64 stp x29,x30,[sp,#-16]!; mov x29,sp -> [fp+0] caller fp, [fp+8] ret
  riscv32 sw ra,[sp+12]; sw s0,[sp+8]; mv s0,sp

  riscv32 is the odd one: s0 is left pointing at the BOTTOM of the frame, not above
  the saved pair, so its links are at +8/+12 rather than +0/+PtrSize. Assuming the
  common layout here would have silently walked into the locals. }
function FramePrevFpOffset: Integer;
begin
  if TargetArch = TARGET_RISCV32 then Result := 8
  else Result := 0;
end;

function FrameRetAddrOffset: Integer;
begin
  if TargetArch = TARGET_RISCV32 then Result := 12
  else Result := TypeSize(tyPointer);
end;

function IRIoCheckedCallee(pi: Integer): Boolean;
{ {$I+}: true when pi is one of the textfile IO procs a PXXIoCheck must
  follow. Matched by NAME + a Text first parameter — interface and body can
  occupy separate Procs rows, so a cached-index compare missed the bound
  callee; the Text-param guard keeps a user's own same-named proc unchecked
  (feature-pascal-io-checks-i-plus). }
begin
  Result := False;
  if (pi < 0) or (pi >= ProcCount) then Exit;
  if not ((Procs[pi].ParamCount >= 1) and
          (Procs[pi].Params[0].TypeKind = tyRecord)) then Exit;
  if CaseEqual(Procs[pi].Name, 'Reset') or
     CaseEqual(Procs[pi].Name, 'Rewrite') or
     CaseEqual(Procs[pi].Name, 'Append') or
     CaseEqual(Procs[pi].Name, 'Close') or
     CaseEqual(Procs[pi].Name, 'CloseFile') or
     CaseEqual(Procs[pi].Name, 'Erase') or
     CaseEqual(Procs[pi].Name, 'TextWrite') or
     CaseEqual(Procs[pi].Name, 'TextWriteLn') or
     CaseEqual(Procs[pi].Name, 'TextReadLn') then
    Result := True;
end;

function IRWrapChkBounds(value: Integer; lo, hi: Int64): Integer;
{ Wrap an IR value in PXXRangeChkI64(v, lo, hi) — shared by the narrowing-
  store guard and the static-array index guard
  (feature-pascal-range-checks-r-plus). Passthrough without builtinheap. }
var pi, a1, a2, a3: Integer;
begin
  Result := value;
  pi := FindProc('PXXRangeChkI64');
  if pi < 0 then Exit;
  a1 := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyInt64));
  a2 := IRAppend(IR_ARG,
          IRAppend(IR_CONST_INT, -1, -1, -1, lo, Ord(tyInt64)), -1, -1, 0, Ord(tyInt64));
  a3 := IRAppend(IR_ARG,
          IRAppend(IR_CONST_INT, -1, -1, -1, hi, Ord(tyInt64)), -1, -1, 0, Ord(tyInt64));
  IRB[a1] := a2; IRB[a2] := a3;
  Result := IRAppendCall(pi, a1, -1, Ord(tyInt64));
end;

function IRWrapRangeChk(value: Integer; destTk: TTypeKind): Integer;
{ {$R+} narrowing-assignment guard: wrap the assigned value in a
  PXXRangeChkI64(v, lo, hi) call when the DEST's ordinal range is narrower
  than the 64-bit compute width. Pure-Pascal helper = portable to every
  target for free (feature-pascal-range-checks-r-plus). Non-narrow /
  non-integer destinations pass through untouched; so does a build without
  builtinheap (lax fallthrough). }
var lo, hi: Int64; pi, a1, a2, a3: Integer;
begin
  Result := value;
  case destTk of
    tyInt8:    begin lo := -128; hi := 127; end;
    tyUInt8:   begin lo := 0; hi := 255; end;
    tyInt16:   begin lo := -32768; hi := 32767; end;
    tyUInt16:  begin lo := 0; hi := 65535; end;
    tyInteger, tyInt32: begin lo := -2147483648; hi := 2147483647; end;
    tyUInt32:  begin lo := 0; hi := 4294967295; end;
    tyChar:    begin lo := 0; hi := 255; end;  { chr(300) := ch raises in FPC }
  else
    Exit;
  end;
  Result := IRWrapChkBounds(value, lo, hi);
end;

{ Code pointer for an AN_METHODREF (`@obj.Method`). For a NON-virtual method
  (ASTRight = -1) it is the static proc address. For a VIRTUAL method
  (ASTRight = VMT slot >= 0) it must be resolved through the object's VMT at
  runtime so `@baseref.VirtualMethod` captures the derived override, matching
  direct virtual dispatch: vmt = [self]; code = [vmt + slot*8]. Mirrors the
  IR_VIRTUAL_CALL codegen (mov rax,[rdi]; call [rax+slot*8]). }
function IRMethodRefCode(mref: Integer): Integer;
var selfVal, vmt, codeAddr, slotK: Integer;
begin
  if ASTRight[mref] < 0 then
  begin
    IRMethodRefCode := IRAppend(IR_PROCADDR, Integer(ASTIVal[mref]), -1, -1, 0, Ord(tyPointer));
    Exit;
  end;
  selfVal := IRLowerAST(ASTLeft[mref]);
  vmt := IRAppend(IR_LOAD_MEM, selfVal, -1, -1, 0, Ord(tyPointer));
  slotK := IRAppend(IR_CONST_INT, -1, -1, -1, ASTRight[mref] * 8, Ord(tyInteger));
  codeAddr := IRAppend(IR_BINOP, vmt, slotK, Ord(tkPlus), 0, Ord(tyPointer));
  IRMethodRefCode := IRAppend(IR_LOAD_MEM, codeAddr, -1, -1, 0, Ord(tyPointer));
end;

{ Resolve an AN_FIELD node to (record id, field index). Returns True and sets the
  out params when the base resolves to a user record and the named field exists.
  Used by the whole static-array FIELD assignment path. }
function faFldRecIdxHelper(fieldNode: Integer; var outRec, outIdx: Integer): Boolean;
begin
  outRec := ResolveNodeRec(ASTLeft[fieldNode]);
  outIdx := -1;
  if outRec >= REC_UCLASS_BASE then
    outIdx := FindUField(outRec - REC_UCLASS_BASE, GetASTIdentName(fieldNode));
  faFldRecIdxHelper := outIdx >= 0;
end;

function IRVariantUnboxKind(target: TTypeKind): Boolean;
{ Which scalar targets a tyVariant value may be unboxed into. Anything not
  listed keeps the pre-existing lowering (records, sets, classes, pointers —
  none of which a variant payload can stand in for). }
begin
  IRVariantUnboxKind :=
    TypeIsFloat(target) or (target = tyBoolean) or (target = tyChar) or
    (target = tyString) or (target = tyAnsiString) or
    (target = tyInteger) or (target = tyInt8) or (target = tyInt16) or
    (target = tyInt32) or (target = tyInt64) or (target = tyNativeInt) or
    (target = tyUInt8) or (target = tyUInt16) or (target = tyUInt32) or
    (target = tyUInt64) or (target = tyNativeUInt);
end;

function IRFindProc1ByArgTk(const name: AnsiString; tk: TTypeKind): Integer;
{ Pick a 1-argument overload by its parameter's type kind, across ALL units.
  FindProcOverload is scoped to CurrentUnitIdx, so it cannot see pylib's
  pystr_of from the main program being lowered. }
var i: Integer;
begin
  IRFindProc1ByArgTk := -1;
  for i := 0 to ProcCount - 1 do
    if (Procs[i].Name = name) and (Procs[i].ParamCount = 1) and
       (Procs[i].Params[0].TypeKind = tk) then
    begin
      IRFindProc1ByArgTk := i;
      Exit;
    end;
end;

{ Does this expression hand back an object reference that is ALREADY OWNED?
  A construction is rc=1 out of PXXObjAlloc and a call result carries the
  callee's return-retain, so retaining either again leaks one ref per call;
  everything else (a name, a field, an index) is a BORROW and must be retained
  by whoever keeps it. ONE predicate, because the assignment arms and the return
  arm state the same invariant — and drifted: the assign arms carried the
  exclusion, the return arm took an unconditional +1, so `return Node(...)`
  leaked ~78 bytes an iteration while `x = Node(...); return x` was flat
  (bug-nilpy-returning-a-construction-leaks-one-ref). }
{ The call must also YIELD A CLASS REFERENCE for its +1 to be the thing being
  asked about. A Python subscript is an AN_CALL too — `store[k]` lowers to a
  pylib accessor — but it returns a VARIANT, and the object pointer only appears
  when lowering unboxes that variant. Unboxing does not retain: the container
  still owns the reference, so the value is a BORROW wearing a call's clothes.
  Reading it as owned meant `return store[k]` skipped its return-retain, the
  caller's local released at scope exit, and the container's own reference died
  — uforth's block word set segfaulted on the first FLUSH after an UPDATE
  (bug-nilpy-a-borrowed-object-returned-through-a-call-is-over-released).
  The two assignment arms already tested the RHS type before consulting this, so
  the check only ever bites on the return arm, which did not. }
function IRNodeYieldsOwnedRef(n: Integer): Boolean;
begin
  IRNodeYieldsOwnedRef := (n >= 0) and
    ((ASTKind[n] = AN_CALL) or (ASTKind[n] = AN_VIRTUAL_CALL) or
     (ASTKind[n] = AN_INTF_CALL) or (ASTKind[n] = AN_CALL_IND) or
     (ASTKind[n] = AN_METACLASS_NEW)) and
    (IntToTypeKind(ASTTk[n]) = tyClass);
end;

function IRSrcIsCallable(n: Integer): Boolean;
{ Does this IR node yield something CALLABLE, whatever its type kind says? The
  one discriminator the backends' variant-boxing tag tables consult beyond the
  source TYPE KIND, so a boxed callable takes VT_CALLABLE_TAG instead of
  VT_INT64 (see defs.inc on that tag: tyPointer maps to VT_INT64, which is also
  what a plain integer wears, and that collision is why `(3 + 4)(x)` could not
  be refused).

  TWO shapes, and finding only the first is what a measurement caught:

  - IR_PROCADDR — a plain compiled def's entry point, `{"a": add}`.
  - a call to one of the callable CONSTRUCTORS — the pyboundfn_* / pyclosure_*
    chain a lambda or a capturing nested def lowers to. Its result is a heap
    callable OBJECT, and it reaches a variant here only in an ARGUMENT position
    (`apply2(lambda a, b: a - b, 6, 7)`), where PyBoxCallableValue deliberately
    does not run. Bound to a NAME first, the same lambda goes through
    pyvar_of_callable and lands as VT_PYCLOSURE/VT_BOUNDFN instead — an OWNING
    tag. This borrowed arm must NOT claim one of those: the slot would then
    release an object it never retained.

  So VT_CALLABLE means "the payload is callable and the slot does not own it",
  which is exactly the lifetime these values already had as VT_INT64 — the
  retagging changes what the guard can SEE, and nothing about who frees what.
  Run-time dispatch is unaffected either way: PyCallableObj tells a code address
  from a closure from a bound-fn by the object's MAGIC, never by the tag.

  ONE predicate, applied at all five boxing sites (x86-64 IR_VAR_STORE and
  IR_VAR_BOX, the i386 tag function's two callers, aarch64's two) — the sibling
  arm is the thing that stays wrong when a discrimination is written per-site. }
var nm: AnsiString;
begin
  IRSrcIsCallable := False;
  if n < 0 then Exit;
  if IRKind[n] = IR_PROCADDR then
  begin
    IRSrcIsCallable := True;
    Exit;
  end;
  if IRKind[n] <> IR_CALL then Exit;
  if (IRA[n] < 0) or (IRA[n] >= ProcCount) then Exit;
  { the same constructor set PyNodeIsCallableValue and PyBoxCallableValue list,
    minus pybound_new — that one already returns a tyVariant tagged 8 and never
    reaches a scalar boxing site. }
  nm := LowerCase(Procs[IRA[n]].Name);
  IRSrcIsCallable :=
    (nm = 'pyclosure_src_new') or (nm = 'pyclosure_src_cap') or
    (nm = 'pyclosure_setarity') or
    (nm = 'pyboundfn_new') or (nm = 'pyboundfn_bind') or
    (nm = 'pyboundfn_setown') or (nm = 'pyboundfn_setdefaults') or
    (nm = 'pyboundfn_bind_var') or (nm = 'pyboundfn_bind_obj') or
    (nm = 'pyboundfn_bind_cell');
end;

function IRNodeIsPyStr(n: Integer): Boolean;
{ A Python str operand: pxx spells a one-character literal tyChar, but Python
  has no character type -- "a" * 3 must repeat, not multiply a code point. }
var tk: TTypeKind;
begin
  IRNodeIsPyStr := False;
  if n < 0 then Exit;
  tk := IntToTypeKind(ASTTk[n]);
  IRNodeIsPyStr := (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar);
end;

{ A CHAR compared against a STRING with an ordering operator. pxx spells a
  one-character value tyChar, an ORDINAL, while the other side is a string
  POINTER -- so `<` compared a character code (~48-57) against an address and
  answered True for every pair, `>` False for every pair, whatever the
  characters actually were. `==`/`!=` escaped because they are routed to a
  content compare first, which is exactly why this survived: the equality tests
  people write first all pass.

  It silently breaks the commonest character-scanning idiom in Python --
  `while src[i] >= "0" and src[i] <= "9"` never enters, so hand-written
  tokenizers accumulate nothing and produce wrong tokens without any error
  (bug-nilpy-char-vs-string-literal-ordering-compares-an-address).

  Char-vs-char (both ordinals) and str-vs-str (both content) are already
  correct and must stay on their own paths -- this fires ONLY for the mixed
  pair, which routes through pycmp_v, where tags 5 and 6 share the text arm. }
function IRPyCharStrOrderClash(node: Integer): Boolean;
var lc, rc, ls, rs: Boolean; lt, rt: TTypeKind;
begin
  IRPyCharStrOrderClash := False;
  if not NilPyUserCode then Exit;
  if (ASTLeft[node] < 0) or (ASTRight[node] < 0) then Exit;
  lt := IntToTypeKind(ASTTk[ASTLeft[node]]);
  rt := IntToTypeKind(ASTTk[ASTRight[node]]);
  lc := lt = tyChar;
  rc := rt = tyChar;
  ls := (lt = tyString) or (lt = tyAnsiString);
  rs := (rt = tyString) or (rt = tyAnsiString);
  IRPyCharStrOrderClash := (lc and rs) or (ls and rc);
end;

{ A PROVABLE operand-type clash: one side is statically a str and the other
  statically a number, for an operator that accepts neither pairing. The
  runtime helpers already raise TypeError for this
  (bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math), but where both
  types are known at compile time the program is simply wrong and pxx can say
  so without running it.

  It WARNS rather than errors, by decision
  (decide-nilpy-mixed-type-operand-policy): `if False: 3 - "ab"` is legal
  CPython and compiles there, as does anything behind a version, platform or
  `if TYPE_CHECKING:` guard, and aborting on a vendored file that never
  executes the line costs more than it saves. -Werror is deliberately NOT the
  opt-in — it promotes every warning, far too blunt for this one check.

  Deliberately narrow. Only the str-vs-number pair is reported, because it is
  the one with no legal reading:
    - `*` is excluded entirely: `"ab" * 3` and `[0] * n` REPEAT.
    - `%` with a str on the left is excluded: that is printf formatting.
    - tyClass is not considered at all — `Path("a") / "b"` is pathlib's join,
      and an overloaded operator is not a clash.
  In NilPy nearly every value is a variant, so this sees roughly literals and
  annotated locals. That is the point: few cases, no false positives.

  NilPyUserCode, not isNilPy: the Pascal RTL units compiled into the same
  program are ordinary Pascal, where Char-vs-Integer arithmetic is legal
  (project_pyeval_arc_state_and_wiring_blocker — a whole-compilation flag must
  not police a unit the NilPy user did not write). }
function IRPyNumStrClash(node: Integer): Boolean;
var op: Integer; lStr, rStr, lNum, rNum: Boolean;
begin
  IRPyNumStrClash := False;
  if not NilPyUserCode then Exit;
  if (ASTLeft[node] < 0) or (ASTRight[node] < 0) then Exit;
  op := Integer(ASTIVal[node]);
  if (op <> Ord(tkMinus)) and (op <> Ord(tkSlash)) and (op <> Ord(tkDiv)) and
     (op <> Ord(tkMod)) and (op <> Ord(tkPlus)) and
     (op <> Ord(tkLt)) and (op <> Ord(tkLe)) and
     (op <> Ord(tkGt)) and (op <> Ord(tkGe)) then Exit;
  lStr := IRNodeIsPyStr(ASTLeft[node]);
  rStr := IRNodeIsPyStr(ASTRight[node]);
  { `"%d items" % n` is formatting, not modulo }
  if (op = Ord(tkMod)) and lStr then Exit;
  lNum := TypeIsPyNumeric(IntToTypeKind(ASTTk[ASTLeft[node]]));
  rNum := TypeIsPyNumeric(IntToTypeKind(ASTTk[ASTRight[node]]));
  IRPyNumStrClash := (lStr and rNum) or (lNum and rStr);
end;

function IRPyOpSpelling(op: Integer): AnsiString;
begin
  if op = Ord(tkMinus) then IRPyOpSpelling := '-'
  else if op = Ord(tkSlash) then IRPyOpSpelling := '/'
  else if op = Ord(tkDiv) then IRPyOpSpelling := '//'
  else if op = Ord(tkMod) then IRPyOpSpelling := '%'
  else if op = Ord(tkPlus) then IRPyOpSpelling := '+'
  else if op = Ord(tkLt) then IRPyOpSpelling := '<'
  else if op = Ord(tkLe) then IRPyOpSpelling := '<='
  else if op = Ord(tkGt) then IRPyOpSpelling := '>'
  else if op = Ord(tkGe) then IRPyOpSpelling := '>='
  else IRPyOpSpelling := '?';
end;

{ The operand type as PYTHON spells it — the warning names both sides, so
  `tyAnsiString` would be leaking pxx's own vocabulary into a NilPy diagnostic. }
function IRPyOperandTypeName(n: Integer): AnsiString;
var tk: TTypeKind;
begin
  tk := IntToTypeKind(ASTTk[n]);
  if (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar) then
    IRPyOperandTypeName := 'str'
  else if tk = tyBoolean then IRPyOperandTypeName := 'bool'
  else if (tk = tySingle) or (tk = tyDouble) or (tk = tyExtended) then
    IRPyOperandTypeName := 'float'
  else if TypeIsPyNumeric(tk) then IRPyOperandTypeName := 'int'
  else IRPyOperandTypeName := 'that type';
end;

function IRNodePyListRec(n: Integer): Integer;
{ The rec id when n is a TPyList, else -1. }
var ci: Integer;
begin
  IRNodePyListRec := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  ci := FindUClass('TPyList');
  if ci < 0 then Exit;
  if ResolveNodeRec(n) = REC_UCLASS_BASE + ci then
    IRNodePyListRec := REC_UCLASS_BASE + ci;
end;

function IRNodePyBytesRec(n: Integer): Integer;
{ The rec id when n is a TPyBytes, else -1. Sibling of IRNodePyListRec. }
var ci: Integer;
begin
  IRNodePyBytesRec := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  ci := FindUClass('TPyBytes');
  if ci < 0 then Exit;
  if ResolveNodeRec(n) = REC_UCLASS_BASE + ci then
    IRNodePyBytesRec := REC_UCLASS_BASE + ci;
end;

function IRNodePyDictRec(n: Integer): Integer;
{ The rec id when n is a TPyDict, else -1. Sibling of IRNodePyListRec. }
var ci: Integer;
begin
  IRNodePyDictRec := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  ci := FindUClass('TPyDict');
  if ci < 0 then Exit;
  if ResolveNodeRec(n) = REC_UCLASS_BASE + ci then
    IRNodePyDictRec := REC_UCLASS_BASE + ci;
end;

{ The Python "kind" of a STATICALLY typed operand, for the operator table in
  IRPyStaticPairUndefined. 0 means "not confidently classifiable" — a variant, a
  user class (which may define dunders), or anything else — and 0 always means
  "leave today's behaviour alone".
    1 = number (int/bool/float)   2 = str   3 = list/tuple   4 = dict   5 = bytes }
function IRPyOperandKind(n: Integer): Integer;
var tk: TTypeKind;
begin
  IRPyOperandKind := 0;
  if n < 0 then Exit;
  tk := IntToTypeKind(ASTTk[n]);
  if (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar) then
    IRPyOperandKind := 2
  else if TypeIsPyNumeric(tk) or (tk = tyBoolean) or
          (tk = tySingle) or (tk = tyDouble) or (tk = tyExtended) then
    IRPyOperandKind := 1
  else if IRNodePyListRec(n) >= 0 then IRPyOperandKind := 3
  else if IRNodePyDictRec(n) >= 0 then IRPyOperandKind := 4
  else if IRNodePyBytesRec(n) >= 0 then IRPyOperandKind := 5;
end;

{ Both operand types provable AND the pair undefined in Python for this
  operator. The mixed-type TypeError guard lives in the runtime pyvar_* helpers,
  which a binop with BOTH types known at compile time never reaches — so
  `3 - [1,2]` lowered to arithmetic on the container's HANDLE and printed a
  plausible number, and `3 < [1,2]` returned a clean True/False decided by an
  allocation address (bug-nilpy-static-typed-operands-skip-mixed-type-guard;
  108 of that sweep's 174 divergences share this root).

  DELIBERATELY NARROW: fires only when the two kinds DIFFER and both are
  confidently classified. Two reasons, both measured rather than assumed:

  - SAME-kind pairs are not safely rejectable here. pxx backs a Python `set`
    with TPyList, and `set([1,2,3]) - set([2])` WORKS today and must keep
    working — so "list minus list is undefined" would break set difference,
    which is a real regression for a real feature. Same-kind holes that remain
    (`"ab" - "ab"`, `[1] // [2]`) are recorded on the ticket rather than guessed
    at here.
  - kind 0 (user classes, variants) must never fire: a user class may define
    __sub__/__lt__, and the variant path already raises correctly.

  `"fmt" % args` is string formatting, not modulo, so a str on the left of % is
  exempt — the same carve-out IRPyNumStrClash makes. }
function IRPyStaticPairUndefined(node: Integer): Boolean;
var op, lk, rk: Integer;
begin
  IRPyStaticPairUndefined := False;
  if not NilPyUserCode then Exit;
  if (ASTLeft[node] < 0) or (ASTRight[node] < 0) then Exit;
  op := Integer(ASTIVal[node]);
  if (op <> Ord(tkMinus)) and (op <> Ord(tkSlash)) and (op <> Ord(tkDiv)) and
     (op <> Ord(tkMod)) and (op <> Ord(tkStar)) and
     (op <> Ord(tkLt)) and (op <> Ord(tkLe)) and
     (op <> Ord(tkGt)) and (op <> Ord(tkGe)) then Exit;
  lk := IRPyOperandKind(ASTLeft[node]);
  rk := IRPyOperandKind(ASTRight[node]);
  if (lk = 0) or (rk = 0) then Exit;
  if (op = Ord(tkMod)) and (lk = 2) then Exit;    { `"%d" % n` is formatting }
  if lk = rk then
  begin
    { SAME kind is mostly not rejectable here — see the note above: pxx backs a
      Python `set` with TPyList, so `list - list` may be a set difference and
      there is no static way to tell. STR is the exception: it carries no
      set-like alter ego, and `"ab" - "ab"` / `"ab" / "ab"` / `"ab" // "ab"` are
      undefined in Python while pxx quietly computed 0, 1.0 and 1 off the string
      HANDLES (bug-nilpy-same-kind-undefined-operators-still-compute — this is
      the safe slice that ticket identifies; the list/dict/bytes same-kind cases
      stay open there pending a set-vs-list distinction).
      Ordering is NOT included: `"aa" < "bb"` is perfectly defined, and `%` is
      already exempted above as formatting. }
    if (lk = 2) and
       ((op = Ord(tkMinus)) or (op = Ord(tkSlash)) or (op = Ord(tkDiv)) or
        (op = Ord(tkStar))) then
      { `"ab" * "ab"` belongs with the three above: str carries no set-like
        alter ego, Python raises "can't multiply sequence by non-int", and pxx
        multiplied the two string HANDLES and printed whatever address product
        fell out — a different garbage integer per run. }
      IRPyStaticPairUndefined := True;
    Exit;
  end;
  { MULTIPLY across DIFFERING kinds is defined in Python — `"ab" * 3` and
    `[1] * 3` are repetition, in either operand order — so it must never reach
    the differing-kind rejection below. It is admitted above only to be judged
    by the same-kind str rule. }
  if op = Ord(tkStar) then Exit;
  IRPyStaticPairUndefined := True;
end;

function IRNodeIsFloatThroughNeg(n: Integer): Boolean;
{ Is this operand floating point, seeing through unary minus? AN_NEG does not
  carry its operand's type, so `-x // y` with a float x looked integer and
  picked the integer floor-div helper, which then reinterpreted the double's
  bits. Only AN_NEG needs unwrapping -- every other operand shape the NilPy
  arithmetic layer produces carries its own ASTTk. }
begin
  while (n >= 0) and (ASTKind[n] = AN_NEG) and
        not TypeIsFloat(IntToTypeKind(ASTTk[n])) do
    n := ASTLeft[n];
  IRNodeIsFloatThroughNeg := (n >= 0) and TypeIsFloat(IntToTypeKind(ASTTk[n]));
end;

function IRVariantAddr(argAST: Integer): Integer;
{ The ADDRESS of a variant expression — variants are always marshalled by
  address (write, str(), unbox, parameter passing all want this).

  A variant RVALUE (an IR_VAR_BINOP result, say) has no address to take, so
  IRLowerAddress alone emitted IR_UNSUPPORTED — that, not the missing unbox,
  is why `print(xs[0] + 1)` failed to compile. Park such a value in a variant
  temp via the ordinary assignment path first: IR_VAR_STORE owns the 16-byte
  ARC-correct copy, and the temp is a plain variant local the epilogue clears.
  Same materialisation the Variant-parameter marshalling uses. }
var vaTmp, vaIdent, vaAsg: Integer;
begin
  if not (ASTKind[argAST] in [AN_IDENT, AN_FIELD, AN_INDEX, AN_DEREF, AN_CALL]) then
  begin
    vaTmp := AllocVar('', tyVariant);
    vaIdent := AllocNode(AN_IDENT);
    ASTIVal[vaIdent] := vaTmp;
    ASTTk[vaIdent] := Ord(tyVariant);
    vaAsg := AllocNode(AN_ASSIGN);
    ASTLeft[vaAsg] := vaIdent;
    ASTRight[vaAsg] := argAST;
    IRLowerAST(vaAsg);
    argAST := vaIdent;
  end;
  IRVariantAddr := IRLowerAddress(argAST);
end;

function IRLowerVariantAsScalar(argAST: Integer; target: TTypeKind): Integer;
{ Unbox a tyVariant expression into a scalar of `target`'s class by calling the
  matching builtin. Target-independent on purpose: routing through a runtime
  helper rather than a new IR op means all six backends get this for free and
  there is no per-backend tag dispatch to keep in sync
  (bug-a-nilpy-variant-element-not-usable-as-scalar).

  A variant argument is always passed BY ADDRESS — same marshalling the
  str()/write paths use, so a call-returning-Variant (`xs[0]`, whose result is
  an sret temp) works here exactly as it does there. }
var vuProc, vuAddr, vuArg: Integer;
    vuName: string;
    vuRet: TTypeKind;
begin
  { The helper SET is chosen here, at the lowering seam -- the helpers
    themselves stay pure. Python and Pascal disagree about a Variant in a
    scalar context (Python raises TypeError for a string or object in a
    numeric slot; Pascal's Variant is historically coercive), and no single
    helper can hold both specs, so NilPy has its own in pylib. }
  if PyProgramMode then
  begin
    { NilPy variants tag/lay out differently from Pascal Variants, so use the
      pylib helpers. A str target unboxes via pystr_of (spells every tag Python's
      way) — the Pascal VariantToStr misread a NilPy string variant and produced
      garbage when a list element (variant) was passed to a `str` parameter
      (bug-nilpy-variant-arg-to-str-param-garbage). }
    if (target = tyString) or (target = tyAnsiString) then
    begin vuName := 'pystr_of'; vuRet := tyAnsiString; end
    else if TypeIsFloat(target) then
    begin vuName := 'pyvar_to_float'; vuRet := tyDouble; end
    else if target = tyBoolean then
    begin vuName := 'pyvar_to_bool'; vuRet := tyBoolean; end
    else if target = tyChar then
    begin vuName := 'pyvar_to_char'; vuRet := tyChar; end
    else
    begin vuName := 'pyvar_to_int'; vuRet := tyInt64; end;
  end
  else if TypeIsFloat(target) then
  begin vuName := 'VariantToDouble'; vuRet := tyDouble; end
  else if target = tyBoolean then
  begin vuName := 'VariantToBool'; vuRet := tyBoolean; end
  else if target = tyChar then
  begin
    { --strict-fpc swaps in FPC's rule (render the variant, take character 1:
      Char(65) = '6') by picking a different HELPER NAME here. Doing it at the
      seam — the same place the Pascal/pylib helper sets already diverge — is
      what keeps the strict flag invisible to the runtime; the alternative was
      threading a compiler flag into builtin.pas.
      bug-p-variant-to-int-and-char-conversion-diverges-from-fpc }
    if StrictVariantChar then vuName := 'VariantToCharFPC'
    else vuName := 'VariantToChar';
    vuRet := tyChar;
  end
  else if (target = tyString) or (target = tyAnsiString) then
  { str() under NilPy is routed to pylib pystr_of by the -201 lowering before
    it reaches here; this is the Pascal path. }
  begin vuName := 'VariantToStr'; vuRet := tyAnsiString; end
  else
  begin vuName := 'VariantToInt64'; vuRet := tyInt64; end;

  { pystr_of is OVERLOADED (per argument type); a variant address must go to the
    tyVariant overload, not whichever FindProc returns first (the AnsiString one
    -> a variant handed to a string param crashed). The explicit str() lowering
    picks the same overload. }
  if vuName = 'pystr_of' then
    vuProc := IRFindProc1ByArgTk('pystr_of', tyVariant)
  else
    vuProc := FindProc(vuName);
  if vuProc < 0 then Error('variant unbox: ' + vuName + ' builtin not loaded');
  vuAddr := IRVariantAddr(argAST);
  vuArg := IRAppend(IR_ARG, vuAddr, -1, -1, 0, Ord(tyVariant));
  IRLowerVariantAsScalar := IRAppendCall(vuProc, vuArg, -1, Ord(vuRet));
end;

{ Whole STATIC-array assignment whose elements are MANAGED (AnsiString, or a
  record with managed fields): `b := a`, `rec.arr := other.arr`.

  A plain IR_COPY_REC would duplicate the element handles without adjusting a
  single refcount, and the scalar store path these arms used to fall back to
  does not copy an array at all — `b := a` silently produced all-empty strings
  and `a := a` destroyed a[0]
  (bug-a-static-array-of-managed-whole-assign-loses-data).

  Same ARC shape IR_COPY_REC_MANAGED uses for a record: retain the SOURCE's
  element handles, release the DESTINATION's old ones, then bulk-copy.
  Retain-before-release is what makes `a := a` and shared-handle elements safe.
  A static array carries no [refcount][length] header, so the element walks are
  the header-free PXXDynArrayRetainImmediate / PXXArrayReleaseImmediate pair
  over a raw buffer + explicit count. N-D arrays are stored flat, so the
  flattened element count is the right one.

  baseKind: 1 = AnsiString elements, 3 = record elements (walked via elemRec's
  layout descriptor). Returns the IR_COPY_REC node (the statement's value). }
function IRManagedArrayCopy(dstAST, srcAST, count, elemSize, baseKind, elemRec: Integer): Integer;
var maSrcTmp, maDstTmp, maFirst, maLast, maArg, maProc, maCall: Integer;

  { The trailing (baseKind, baseRecDesc) argument pair, identical in both calls.
    IR_CONST_DATA yields the layout blob's data address — the negative sentinel
    resolves to UClsRTTIOff at link fixup, as in AN_DYN_DELETE. }
  function AppendKindAndDesc(after: Integer): Integer;
  var kArg: Integer;
  begin
    kArg := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, baseKind, Ord(tyInteger)),
              -1, -1, 0, Ord(tyInteger));
    IRB[after] := kArg;
    if baseKind = 3 then
      IRB[kArg] := IRAppend(IR_ARG,
                     IRAppend(IR_CONST_DATA, -1, -1, -1,
                       -(RECORD_RTTI_DATAREF_BASE + (elemRec - REC_UCLASS_BASE)),
                       Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer))
    else
      IRB[kArg] := IRAppend(IR_ARG,
                     IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
    AppendKindAndDesc := kArg;
  end;

begin
  { Both addresses are parked in pointer temps: each is needed three times
    (retain, release, copy) and re-lowering an AN_INDEX/AN_FIELD base would
    re-evaluate its subscript. }
  maDstTmp := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, maDstTmp, IRLowerAddress(dstAST), -1, 0, Ord(tyPointer));
  maSrcTmp := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, maSrcTmp, IRLowerAddress(srcAST), -1, 0, Ord(tyPointer));

  { PXXDynArrayRetainImmediate(src, count, depth=1, baseKind, desc) }
  maProc := FindProc('PXXDynArrayRetainImmediate');
  if maProc < 0 then Error('compiler error: PXXDynArrayRetainImmediate not found');
  maFirst := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, maSrcTmp, -1, -1, 0, Ord(tyPointer)),
               -1, -1, 0, Ord(tyPointer));
  maLast := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, count, Ord(tyInteger)),
              -1, -1, 0, Ord(tyInteger));
  IRB[maFirst] := maLast;
  maArg := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
             -1, -1, 0, Ord(tyInteger));
  IRB[maLast] := maArg;                                  { depth = 1 }
  AppendKindAndDesc(maArg);
  maCall := IRAppendCall(maProc, maFirst, -1, Ord(tyNativeInt));
  IRIVal[maCall] := 1;   { statement-level: side-effect call }

  { PXXArrayReleaseImmediate(dst, count, baseKind, desc) }
  maProc := FindProc('PXXArrayReleaseImmediate');
  if maProc < 0 then Error('compiler error: PXXArrayReleaseImmediate not found');
  maFirst := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, maDstTmp, -1, -1, 0, Ord(tyPointer)),
               -1, -1, 0, Ord(tyPointer));
  maLast := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, count, Ord(tyInteger)),
              -1, -1, 0, Ord(tyInteger));
  IRB[maFirst] := maLast;
  AppendKindAndDesc(maLast);
  maCall := IRAppendCall(maProc, maFirst, -1, Ord(tyNativeInt));
  IRIVal[maCall] := 1;

  IRManagedArrayCopy := IRAppend(IR_COPY_REC,
    IRAppend(IR_LOAD_SYM, maDstTmp, -1, -1, 0, Ord(tyPointer)),
    IRAppend(IR_LOAD_SYM, maSrcTmp, -1, -1, 0, Ord(tyPointer)),
    -1, count * elemSize, Ord(tyRecord));
end;

procedure IRWidenOrdinalFloatBinop(node: Integer; wantTk: TTypeKind);
{ Re-type a float-producing binop whose operands supply NO float depth, so it
  yields what the assignment target asked for. ESP-only in effect: elsewhere
  such a node is already tyDouble and the size test below exits at once.

  Only when NEITHER operand is a float — with one, the operand's depth decides,
  which is the ESP design and is left alone (two Singles still make a Single).
  The recursion is bounded by the same float test: an ordinal subexpression is
  not a float binop, so integer arithmetic underneath is never re-typed.
  decide-esp-single-depth-division-into-a-declared-double }
begin
  if node < 0 then Exit;
  if not TypeIsFloat(wantTk) then Exit;
  if ASTKind[node] <> AN_BINOP then Exit;
  if not TypeIsFloat(IntToTypeKind(ASTTk[node])) then Exit;
  { OPERANDS FIRST, then this node — the order matters. `(1/3) * (1/3)` has two
    float operands, so a node-first rule refused to widen the product and then
    widened both divisions underneath it: the operands came back Double, the
    product stayed Single, and the store of a Single into a Double slot read
    0.0. Deciding after the recursion sees the operands as they will actually
    be. }
  IRWidenOrdinalFloatBinop(ASTLeft[node], wantTk);
  IRWidenOrdinalFloatBinop(ASTRight[node], wantTk);
  { A genuinely NARROWER float operand still blocks the widen — that is the ESP
    design and the point of the Single-target control: `s1 * s2` assigned to a
    Double stays a single multiply. An operand this walk just widened is no
    longer narrow, so it no longer blocks. }
  if (TypeSize(IntToTypeKind(ASTTk[node])) < TypeSize(wantTk)) and
     not (TypeIsFloat(IntToTypeKind(ASTTk[ASTLeft[node]])) and
          (TypeSize(IntToTypeKind(ASTTk[ASTLeft[node]])) < TypeSize(wantTk))) and
     not (TypeIsFloat(IntToTypeKind(ASTTk[ASTRight[node]])) and
          (TypeSize(IntToTypeKind(ASTTk[ASTRight[node]])) < TypeSize(wantTk))) then
    ASTTk[node] := Ord(wantTk);
end;

function IRLowerAST(node: Integer): Integer;
var left, right, seq, item, value, outNode, first, last, leftAddr, argNode, argVal, intCallNode, intArgSeq, argNode2, zeroVal, procIdx, zeroBytes: Integer;
    cfPi, cfArg, cfCall: Integer;   { class managed-field finalize before FreeMem }
    promoLhs, promoRhs, promoDst, promoSym, promoOp: Integer;   { promotable-int slot lowering }
    vuExitUnboxed: Boolean;         { `return <variant>` unboxed to a scalar result }
    vuArgProc, vuArgAddr, vuArgNode: Integer;   { `return <variant>` -> class via pyvarobj }
    fdName: string;                 { NilPy floor-div/mod helper being called }
    pvName: string;                 { NilPy variant-dispatch builtin }
    pvTk: TTypeKind;
    fdTk: TTypeKind;
    intfCallCi, intfSelfSym, intfImtSym: Integer;   { single-pointer interface call }
    frameNode, slotNode, bpAddr, addrAddr, bpVal, selfVal: Integer;
    pairNode, condNode, specialId, classIdx, slot, cpi, pathIdx: Integer;
    ctorArgCpi, ctorArgSlot: Integer;   { construction: coerce ctor args by the ctor's param types }
    dfltAST, dfltSym, dfltIdent, dfltAsgn: Integer;   { a filled default, materialised for IRLowerCallArg }
    isRefArg: Boolean; argTk: TTypeKind; callRetType: TTypeKind; callVal: Integer;
    lstNode, varNode: Integer;   { NilPy list-vs-variant equality }
    startLabel, elseLabel, endLabel, startLabelNode, endLabelNode: Integer;
    lhsNode, pair3, pair1, pair2, initNode, limitNode, isDownNode, bodyNode: Integer;
    foldOff, foldK: Integer;
    bLastNode: Integer;
    writeFd: Integer;
    foldStr: AnsiString;
    down: Boolean;
    varIdx, varIdx2: Integer;
    initValNode, storeNode, limitValNode, cmpNode, condJmpNode, bodyIRNode: Integer;
    loadVarNode2, constOneNode, stepNode, storeStepNode, jmpNode: Integer;
    hiddenArgSym: Integer; argIsManagedTemp: Boolean;
    continueLabel, continueLabelNode: Integer;
    branchSeq, branchPair, labelsHead, stmtNode, labelNode: Integer;
    clauseBodyLabel, nextClauseLabel, selectorValNode, selTmpSym, selTmpTk: Integer;
    ternTmp: Integer;
    swSelTmp, swDefault, swSeq, swMarker, swSelTk: Integer;
    rhsIsLValue: Boolean;
    isComIntf: Boolean;
    intfTmpImt, intfTmpInst: Integer;
    cv: Int64;
    constValNode, clauseBodyLabelNode, exitJmpNode, nextClauseLabelNode: Integer;
    beforeCount, handlerLabel, handlerNode, handlerNextLabel, savedDepth: Integer;
    raiseValueNode, raiseClass: Integer;
    excTargetCi, excBodyLabel, excDescCi: Integer;
    excObjSym, excMatched, excSkipLabel, excOwnTmp, excReleaseProc: Integer;
    eaSym: Integer;
    narrowSize: Integer; castIsSigned: Boolean;
    i, lbId, off, len, idx, itemNode, lo, hi, val1, elemSize: Integer;
    faFldRec, faFldIdx: Integer;   { whole static-array FIELD assignment }
    waBaseKind: Integer;   { whole static-array assignment: 0 = plain bytes, else IRManagedArrayCopy }

    slTargetAST, slCountAST, slRootSym, slDepth, slTargetAddr, slCountNode: Integer;
    slFldRec, slFldDepth, slFldBaseRec: Integer; slFldName: AnsiString; slFldBaseTk: TTypeKind;
    helperPi, wrapperArg, wrapperCall: Integer;
    lhsTk, lhsStoreTk, castTk: TTypeKind;
    lhsStrCap: Integer;
    rcSubLo, rcSubHi: Int64;
    vrCount, vrTmp, vrIdent, vrCountLit, vrArg1, vrArg2, vrSlCall: Integer;
    vrIdxLit, vrIndex, vrTag, elemAddr, vrSavedRecId, vrBoxSym: Integer;
    vrElemTk: TTypeKind;
    setAllConst: Boolean; setSym: Integer;
    dcSrcSym, dcElemRec, dcElemSz, dcIdxAst, dcCntAst, dcSrcTmp, dcIdxTmp: Integer;
    dcRetData, dcSrcAst: Integer;
    dcCntTmp, dcTempSym, dcTempIdent, dcCountIdent, dcSlArg1, dcSlArg2: Integer;
    dcSlCall, dcSetlenVal, dcDestData, dcSrcStart, dcNbytes, dcSavedRec: Integer;
    dcNewLenTmp, dcValTmp, dcGapTmp, dcZeroIdent: Integer;
    dcElemTk: TTypeKind;
    pendBase: Integer;
    mcCrefSym, mcInstSym, mcSize, mcVmt, mcAddr, mcSelfArg: Integer;
    dynLenTmp, dynLenPi: Integer;
    caseIsStr: Boolean;
begin
  if node = -1 then
  begin
    Result := -1;
    Exit;
  end;

  if ASTLine[node] <> 0 then
  begin
    CurLowerLine := ASTLine[node];
    CurLowerFile := ASTFile[node];   { DWARF -g: line and file travel together }
  end;

  case ASTKind[node] of
    AN_INT_LIT, AN_BOOL_LIT:
    begin
      { Reaching here means the literal is being materialised as a MACHINE int.
        A literal past UInt64 has no correct 64-bit reading, so this is where it
        is rejected — not in the lexer, which cannot know the target. A promo
        target consumes the digit text before this point and never arrives here
        (bug-a-integer-literal-out-of-range-wraps-silently). }
      if IsWideIntLit(node) and
         DecDigitsExceed(GetTokenStrFromRaw(ASTSOffset[node], ASTSLen[node]),
                         '18446744073709551615') then
        Error('number ' + GetTokenStrFromRaw(ASTSOffset[node], ASTSLen[node])
              + ' is out of range');
      { A promo-TYPED wide literal (NilPy) that still lands here is being read
        as a machine int; the wrapped bits are the right QWord reading, and the
        IR must not carry tyPromoInt64 on a plain constant. }
      if ASTTk[node] = Ord(tyPromoInt64) then
        Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], Ord(tyInt64))
      else
        Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], ASTTk[node]);
    end;

    AN_FLOAT_LIT:
      { IVal holds the IEEE 754 double bit pattern. The IR value model carries
        floats as bits in rax (binop/store move them to xmm via movq), so a float
        literal is just mov rax, imm64 — identical to IR_CONST_INT. ASTTk (tyDouble)
        is preserved so downstream nodes select the float path. }
      Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], ASTTk[node]);

    AN_STR_LIT:
      Result := IRAppend(IR_CONST_STR, ASTSOffset[node], ASTSLen[node], -1, 0, ASTTk[node]);

    AN_DEFAULT:
      { C switch-default MARKER (ASTSLen=1): drop its dispatch IR_LABEL in place.
        The bare Default(T) intrinsic node (ASTSLen=0) as an rvalue is still an
        error — it is only valid as an assignment target (IRLowerAddress). }
      if ASTSLen[node] = 1 then
        Result := IRAppend(IR_LABEL, -1, -1, -1, ASTSOffset[node], 0)
      else
        Error('default requires an assignment target');

    AN_ARRAY_CTOR:
    begin
      { `[e0, e1, ...]` for an `array of T` (scalar/string) parameter: build a heap
        dyn-array temp of T, SetLength(N), store each element through the normal
        element-assign path (type coercion + managed-string ARC), and yield the
        data-pointer handle as the open-array argument. Plain-element mirror of
        AN_VARREC_ARRAY. }
      vrElemTk := IntToTypeKind(ASTIVal[node]);
      vrCount := 0;
      item := ASTLeft[node];
      while item <> -1 do begin Inc(vrCount); item := ASTRight[item]; end;

      { fixed-array ROW element (`array of T`, T a named fixed array): the parse
        stashed the row shape on the node (ASTSOffset = row length, ASTSLen =
        row lo); hand it to AllocDynArray so the temp's stride and the element
        row-copies below are row-sized. }
      LastTypeDynElemRowLen := ASTSOffset[node];
      LastTypeDynElemRowLo  := ASTSLen[node];
      vrTmp := AllocDynArray('', vrElemTk, 1);
      { Managed local synthesised after the prologue zero-init pass — flag it for
        the codegen prologue nil-init and zero the handle slot here so SetLength
        sees nil (mirrors AN_VARREC_ARRAY). }
      SymIsHiddenArgTemp[vrTmp] := True;
      IRAppend(IR_DEFAULT_MEM,
        IRAppend(IR_SLOTADDR, vrTmp, -1, -1, 0, Ord(tyPointer)),
        -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));

      { SetLength(tmp, vrCount) }
      vrIdent := AllocNode(AN_IDENT);
      ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
      vrCountLit := AllocNode(AN_INT_LIT);
      ASTIVal[vrCountLit] := vrCount; ASTTk[vrCountLit] := Ord(tyInteger);
      vrArg1 := AllocNode(AN_ARG); ASTLeft[vrArg1] := vrIdent;
      vrArg2 := AllocNode(AN_ARG); ASTLeft[vrArg2] := vrCountLit;
      ASTRight[vrArg1] := vrArg2;
      vrSlCall := AllocNode(AN_CALL); ASTIVal[vrSlCall] := -102;
      ASTLeft[vrSlCall] := vrArg1;
      value := IRLowerAST(vrSlCall);
      IRIVal[value] := 1;   { mark the SetLength IR_CALL as a statement to emit }

      { tmp[i] := element, via the normal element-assign path. }
      i := 0;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        vrIdent := AllocNode(AN_IDENT);
        ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
        vrIdxLit := AllocNode(AN_INT_LIT);
        ASTIVal[vrIdxLit] := i; ASTTk[vrIdxLit] := Ord(tyInteger);
        vrIndex := AllocNode(AN_INDEX);
        ASTLeft[vrIndex] := vrIdent; ASTRight[vrIndex] := vrIdxLit;
        ASTTk[vrIndex] := Ord(vrElemTk);
        elemAddr := AllocNode(AN_ASSIGN);
        ASTLeft[elemAddr] := vrIndex;
        ASTRight[elemAddr] := ASTLeft[item];
        ASTTk[elemAddr] := Ord(vrElemTk);
        IRMarkStatementNode(IRLowerAST(elemAddr));
        Inc(i);
        item := ASTRight[item];
      end;

      Result := IRAppend(IR_LEA, vrTmp, -1, -1, 0, Ord(tyPointer));
    end;

    AN_VARREC_ARRAY:
    begin
      { Lower `[e0, e1, ...]` in an `array of const` position to a heap dyn-array
        of TVarRec and yield its data-pointer handle. Each element becomes one
        TVarRec: VType at offset 0, the value at the union offset
        (TARGET_PTR_SIZE). The callee walks it as an open array of records, with
        Length/High reading the dyn-array header word — no new codegen needed. }
      vrCount := 0;
      item := ASTLeft[node];
      while item <> -1 do begin Inc(vrCount); item := ASTRight[item]; end;

      vrSavedRecId := LastTypeRecId;
      LastTypeRecId := ASTIVal[node];        { TVarRecId }
      vrTmp := AllocDynArray('', tyRecord, 1);
      LastTypeRecId := vrSavedRecId;

      { This dyn-array temp is a managed local synthesised during lowering, after
        the parser's prologue zero-init pass, so flag it for the codegen prologue
        nil-init. The inline DEFAULT_MEM below only zeroes the slot when this
        literal is actually reached; if the `[...]` sits in a branch that is not
        taken, the slot would otherwise hold stale stack bytes and the function's
        managed-local cleanup would free a garbage handle. }
      SymIsHiddenArgTemp[vrTmp] := True;

      { Zero the handle slot (allocated after the prologue) so SetLength sees nil. }
      IRAppend(IR_DEFAULT_MEM,
        IRAppend(IR_SLOTADDR, vrTmp, -1, -1, 0, Ord(tyPointer)),
        -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));

      { SetLength(tmp, vrCount): synthesise the dyn-array SetLength (-102) call. }
      vrIdent := AllocNode(AN_IDENT);
      ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
      vrCountLit := AllocNode(AN_INT_LIT);
      ASTIVal[vrCountLit] := vrCount; ASTTk[vrCountLit] := Ord(tyInteger);
      vrArg1 := AllocNode(AN_ARG); ASTLeft[vrArg1] := vrIdent;
      vrArg2 := AllocNode(AN_ARG); ASTLeft[vrArg2] := vrCountLit;
      ASTRight[vrArg1] := vrArg2;
      vrSlCall := AllocNode(AN_CALL); ASTIVal[vrSlCall] := -102;
      ASTLeft[vrSlCall] := vrArg1;
      value := IRLowerAST(vrSlCall);
      IRIVal[value] := 1;   { mark the SetLength IR_CALL as a statement to emit }

      { Fill each element. }
      i := 0;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        vrIdent := AllocNode(AN_IDENT);
        ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
        vrIdxLit := AllocNode(AN_INT_LIT);
        ASTIVal[vrIdxLit] := i; ASTTk[vrIdxLit] := Ord(tyInteger);
        vrIndex := AllocNode(AN_INDEX);
        ASTLeft[vrIndex] := vrIdent; ASTRight[vrIndex] := vrIdxLit;
        ASTTk[vrIndex] := Ord(tyRecord);

        { Element tag from the element's static type. The value union is one
          pointer-sized slot, so types wider than a pointer (Int64 — also on
          64-bit where it fits, for uniformity — and floats) are boxed: stored in
          a hidden local and the slot holds a pointer to it (FPC's VInt64/
          VExtended convention). }
        vrElemTk := IntToTypeKind(ASTTk[ASTLeft[item]]);
        if (vrElemTk = tyString) or (vrElemTk = tyAnsiString) then
          vrTag := 11             { vtAnsiString }
        else if vrElemTk = tyBoolean then
          vrTag := 1              { vtBoolean }
        else if vrElemTk = tyChar then
          vrTag := 2              { vtChar }
        else if IsNodePChar(ASTLeft[item]) then
          vrTag := 6              { vtPChar — before the generic pointer tag; FPC
                                    boxes PChar(s) as VPChar, and consumers (fpjson's
                                    TJSONArray.Create) dispatch on it (b320) }
        else if vrElemTk = tyClass then
          vrTag := 7              { vtObject — a class INSTANCE; fell to vtInteger
                                    before, so consumers read a truncated pointer }
        else if vrElemTk = tyPointer then
          vrTag := 5              { vtPointer }
        else if (vrElemTk = tyInt64) or (vrElemTk = tyUInt64) then
          vrTag := 16             { vtInt64 (boxed) }
        else if (vrElemTk = tySingle) or (vrElemTk = tyDouble) or (vrElemTk = tyExtended) then
          vrTag := 3             { vtExtended (boxed) }
        else
          vrTag := 0;            { vtInteger }

        { VType := tag  (element offset 0) }
        elemAddr := IRLowerAddress(vrIndex);
        IRAppend(IR_STORE_MEM, elemAddr,
          IRAppend(IR_CONST_INT, -1, -1, -1, vrTag, Ord(tyNativeInt)),
          -1, 0, Ord(tyNativeInt));

        { value := elem  (element offset TARGET_PTR_SIZE) }
        elemAddr := IRLowerAddress(vrIndex);
        elemAddr := IRAppend(IR_BINOP, elemAddr,
          IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        if (vrTag = 16) or (vrTag = 3) then
        begin
          { Boxed value (Int64/float): a pointer-sized union slot can't hold a
            64-bit value on 32-bit targets, so store the element in a hidden local
            and put its address in the slot — FPC's VInt64/VExtended convention.
            The asm-text emitters (which build tyInt64 `%`-hole vectors like
            `['b %', LabelPositions[i] - CodeLen]`) dereference boxed Int64 holes,
            so this stays correct for both user `array of const` and internal asm.
            The local is unmanaged and written before any read — no nil-init. }
          vrBoxSym := AllocVar('', vrElemTk);
          IRAppend(IR_STORE_MEM,
            IRAppend(IR_SLOTADDR, vrBoxSym, -1, -1, 0, Ord(tyPointer)),
            IRLowerAST(ASTLeft[item]), -1, 0, Ord(vrElemTk));
          value := IRAppend(IR_SLOTADDR, vrBoxSym, -1, -1, 0, Ord(tyPointer));
        end
        else
        begin
          value := IRLowerAST(ASTLeft[item]);
          if vrElemTk = tyString then
            { vtAnsiString from a frozen (inline) string literal: its value points
              at the 8-byte length prefix, so skip to the NUL-terminated char data
              (InternStr terminates it), like FPC's VAnsiString. A runtime
              tyAnsiString value is ALREADY a char pointer (matches PChar(s), which
              only adjusts tyString), so it is stored as-is. }
            value := IRAppend(IR_BINOP, value,
              IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
              Ord(tkPlus), 0, Ord(tyPointer));
        end;
        IRAppend(IR_STORE_MEM, elemAddr, value, -1, 0, Ord(tyNativeInt));

        Inc(i);
        item := ASTRight[item];
      end;

      Result := IRAppend(IR_LEA, vrTmp, -1, -1, 0, Ord(tyPointer));
    end;

    AN_SET_CONST_REF:
      { Named set constant: the 32-byte mask was already baked into Data[] at
        declaration time; yield its address exactly like a baked set literal. }
      Result := IRAppend(IR_SET_LIT, -1, -1, -1, ASTIVal[node], Ord(tySet));

    AN_SET_LIT:
    begin
      { An all-constant set literal is baked into a 32-byte Data[] blob (the
        original fast path, kept byte-identical). The parser leaves a constant
        element as an AN_INT_LIT (a constant range as an AN_PAIR of two of them);
        any other element kind means a runtime value, so the whole literal is
        built at runtime into a zeroed set temp with Include/range loops. }
      setAllConst := True;
      argNode := ASTLeft[node];
      while argNode <> -1 do
      begin
        itemNode := ASTLeft[argNode];
        if ASTKind[itemNode] = AN_PAIR then
        begin
          if (ASTKind[ASTLeft[itemNode]] <> AN_INT_LIT) or
             (ASTKind[ASTRight[itemNode]] <> AN_INT_LIT) then setAllConst := False;
        end
        else if ASTKind[itemNode] <> AN_INT_LIT then
          setAllConst := False;
        argNode := ASTRight[argNode];
      end;

      if setAllConst then
      begin
        { Align DataLen to 8 bytes }
        while (DataLen mod 8) <> 0 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        idx := DataLen;
        for i := 0 to 31 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        argNode := ASTLeft[node];
        while argNode <> -1 do
        begin
          itemNode := ASTLeft[argNode];
          if ASTKind[itemNode] = AN_PAIR then
          begin
            lo := ASTIVal[ASTLeft[itemNode]];
            hi := ASTIVal[ASTRight[itemNode]];
            if lo < 0 then lo := 0;
            if hi > 255 then hi := 255;
            for val1 := lo to hi do
            begin
              Data[idx + (val1 div 8)] := Data[idx + (val1 div 8)] or Shl8_(val1 mod 8);
            end;
          end
          else
          begin
            val1 := ASTIVal[itemNode];
            if (val1 >= 0) and (val1 <= 255) then
            begin
              Data[idx + (val1 div 8)] := Data[idx + (val1 div 8)] or Shl8_(val1 mod 8);
            end;
          end;
          argNode := ASTRight[argNode];
        end;
        Result := IRAppend(IR_SET_LIT, -1, -1, -1, idx, ASTTk[node]);
      end
      else
      begin
        setSym := AllocVar('', tySet);
        IRAppend(IR_DEFAULT_MEM, IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
          -1, REC_NONE, 32, Ord(tySet));
        argNode := ASTLeft[node];
        while argNode <> -1 do
        begin
          itemNode := ASTLeft[argNode];
          if ASTKind[itemNode] = AN_PAIR then
            IRLowerSetRangeMutate(setSym, IRLowerAST(ASTLeft[itemNode]),
              IRLowerAST(ASTRight[itemNode]))
          else
            IRLowerSetBitMutate(IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
              IRLowerAST(itemNode), True);
          argNode := ASTRight[argNode];
        end;
        Result := IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tySet));
      end;
    end;

    AN_SET_SIGNAL:
      Result := IRAppend(IR_SET_SIGNAL, IRLowerAST(ASTLeft[node]),
                         IRLowerAST(ASTRight[node]), -1, 0, Ord(tyUnknown));

    AN_SET_INCL:
      IRLowerSetBitMutate(IRLowerAddress(ASTLeft[node]), IRLowerAST(ASTRight[node]), True);

    AN_SET_EXCL:
      IRLowerSetBitMutate(IRLowerAddress(ASTLeft[node]), IRLowerAST(ASTRight[node]), False);

    AN_DYN_COPY:
    begin
      { Copy(arr, index, count) over a dynamic array -> a fresh `array of T`.
        Element type/size come from the source symbol, so this is generic over T
        (what a non-generic RTL routine cannot express). Build: clamp the count
        to the source bounds (PXXClampLen), SetLength a fresh dyn-array local to
        that, then raw-copy count*elemSize bytes from source[index] (PXXMemCopy).
        Index is 0-based (FPC dynamic-array Copy semantics). The result behaves
        like a dyn-array variable read, so the caller's assignment retains it and
        the local's scope-exit release balances it. NOTE: a raw byte copy, so an
        array of a managed element type (AnsiString / managed record) is shallow
        — deep element copy is a later extension. }
      { The source may be a bare dyn-array SYMBOL or any dyn-array-typed
        EXPRESSION — an element of a nested array (`g[0]`), a record field
        (`r.items`). Element metadata therefore comes from the NODE, not from a
        symbol: NodeDynBaseTk / NodeDynBaseRec walk the ident / field / index
        chain to the root, which is the same pair IR_SETLEN_DYN already uses to
        support `SetLength(r.items, n)` and `SetLength(a[i], n)`. Reading it off
        `Syms[ASTIVal[...]]` is what forced the parser to demand a bare name
        (bug-p-copy-rejects-a-dynamic-array-expression-that-is-not-a-bare-name).
        A nested SOURCE is still refused in the parser, so the elements here are
        always base values, never sub-array handles. }
      dcSrcAst := ASTLeft[node];
      dcElemTk := NodeDynBaseTk(dcSrcAst);
      dcElemRec := NodeDynBaseRec(dcSrcAst);
      if dcElemTk = tyRecord then dcElemSz := RecSize(dcElemRec)
      else dcElemSz := TypeSize(dcElemTk);
      dcIdxAst := ASTLeft[ASTRight[node]];
      dcCntAst := ASTLeft[ASTRight[ASTRight[node]]];

      { Materialize source data pointer and index once. For a SYMBOL, IR_LEA in
        read context loads the handle = data pointer (feeding it straight into a
        call-arg position lowered it as an lvalue instead — the slot address — so
        it is parked in a temp). For an expression, an ordinary read of a
        dyn-array-typed element/field IS its handle, so IRLowerAST gives the same
        thing; kept as a separate arm rather than unifying, because the IR_LEA
        path is what the existing tests exercise. }
      dcSrcTmp := AllocVar('', tyPointer);
      if ASTKind[dcSrcAst] = AN_IDENT then
      begin
        dcSrcSym := ASTIVal[dcSrcAst];
        IRAppend(IR_STORE_SYM, dcSrcTmp,
          IRAppend(IR_LEA, dcSrcSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      end
      else
        IRAppend(IR_STORE_SYM, dcSrcTmp, IRLowerAST(dcSrcAst), -1, 0, Ord(tyPointer));
      dcIdxTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcIdxTmp, IRLowerAST(dcIdxAst), -1, 0, Ord(tyInteger));

      { clampedCount := PXXClampLen(srcData, index, count). }
      procIdx := FindProc('PXXClampLen');
      if procIdx < 0 then Error('compiler error: PXXClampLen not found');
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
                -1, -1, 0, Ord(tyInteger));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, IRLowerAST(dcCntAst), -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      dcCntTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcCntTmp, IRAppendCall(procIdx, first, -1, Ord(tyNativeInt)),
        -1, 0, Ord(tyInteger));

      { Fresh dyn-array local of the source element type. Lowering-time temp ->
        flag for the codegen-prologue nil-init (SymIsHiddenArgTemp) instead of
        an inline DEFAULT_MEM zero: the inline zero re-runs on every pass
        through this statement, wiping the previous pass's handle without a
        release (one block leaked per loop iteration — Copy-in-a-loop leak);
        with a prologue-nil'd slot the SetLength below releases the old handle
        itself. }
      dcSavedRec := LastTypeRecId;
      if dcElemTk = tyRecord then LastTypeRecId := dcElemRec;
      dcTempSym := AllocDynArray('', dcElemTk, 1);
      LastTypeRecId := dcSavedRec;
      SymIsHiddenArgTemp[dcTempSym] := True;

      { SetLength(temp, clampedCount) via the -102 dyn-array SetLength call. }
      dcTempIdent := AllocNode(AN_IDENT); ASTIVal[dcTempIdent] := dcTempSym;
      ASTTk[dcTempIdent] := Ord(tyPointer);
      dcCountIdent := AllocNode(AN_IDENT); ASTIVal[dcCountIdent] := dcCntTmp;
      ASTTk[dcCountIdent] := Ord(tyInteger);
      { Empty the temp FIRST (SetLength(temp, 0)): in a loop the slot still
        holds the previous pass's buffer, and PXXDynSetLen's grow path would
        copy + element-retain its contents into the fresh block — refs the raw
        fill below then overwrites (managed-element leak). From an empty
        handle the sizing SetLength copies nothing. }
      dcZeroIdent := AllocNode(AN_INT_LIT);
      ASTIVal[dcZeroIdent] := 0; ASTTk[dcZeroIdent] := Ord(tyInteger);
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcZeroIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcCountIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;

      { PXXMemCopy(destData, srcData + index*elemSize, clampedCount*elemSize).
        Materialize the dest data pointer into a temp first: lea on the dyn-array
        symbol must be evaluated here in read context (handle = data pointer);
        feeding it straight into the call-arg position lowered it as an lvalue
        (the slot address) instead, so the copy missed the data block. }
      procIdx := FindProc('PXXMemCopy');
      if procIdx < 0 then Error('compiler error: PXXMemCopy not found');
      dcDestData := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcDestData,
        IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      dcSrcStart := IRAppend(IR_BINOP,
        IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
          IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)), Ord(tkStar), 0, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      dcNbytes := IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, dcCntTmp, -1, -1, 0, Ord(tyInteger)),
        IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)), Ord(tkStar), 0, Ord(tyInteger));
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, dcSrcStart, -1, -1, 0, Ord(tyPointer));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, dcNbytes, -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      { Store the (ignored) result so the call is linked into the statement
        stream — a bare call whose result is unused is not emitted. }
      IRAppend(IR_STORE_SYM, dcDestData, IRAppendCall(procIdx, first, -1, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));

      { MANAGED elements: retain every handle now sitting in the fresh buffer.
        The copy above is a raw byte copy, so the temp's elements are the SOURCE's
        handles with no refcount adjustment — and the temp is element-aware
        released at scope exit, which then frees strings the source still owns.
        Measured, and only visible with the right tool: `b := Copy(a, 0, 2)` over
        an `array of AnsiString` then `b[0] := 'CHANGED'` printed the correct
        a[0] on a plain run and an EMPTY a[0] under -dPXX_HEAP_DEBUG, because the
        freed bytes still held the old text until something reused them
        (devdocs/dev/debugging-playbook.md — the expensive bugs produce a
        plausible wrong value, not a crash).

        This was latent, not new: the retain was accidentally supplied by
        IR_DYNUNIQUE's copy-on-write clone, which calls PXXDynArrayRetainImmediate
        on the block it clones. Removing the COW
        (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing) took the
        side effect away and exposed the missing retain underneath — the
        lowering's own note above ("shallow — deep element copy is a later
        extension") had said so all along.

        Same RetainImmediate-after-copy pattern as AN_DYN_DELETE below. The dest
        pointer is re-derived rather than reused: the PXXMemCopy call overwrote
        dcDestData with its own result to link the call into the statement
        stream. }
      if (dcElemTk = tyAnsiString) or
         ((dcElemTk = tyRecord) and RecordHasManagedFields(dcElemRec)) then
      begin
        procIdx := FindProc('PXXDynArrayRetainImmediate');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRetainImmediate not found');
        dcRetData := AllocVar('', tyPointer);
        IRAppend(IR_STORE_SYM, dcRetData,
          IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
        first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcRetData, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
        last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcCntTmp, -1, -1, 0, Ord(tyInteger)),
                  -1, -1, 0, Ord(tyInteger));
        IRB[first] := last;
        argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                     -1, -1, 0, Ord(tyInteger));
        IRB[last] := argNode; last := argNode;                 { depth = 1 }
        if dcElemTk = tyAnsiString then
        begin
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 1 (string) }
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = nil }
        end
        else
        begin
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 3, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 3 (record) }
          argNode := IRAppend(IR_ARG,
                       IRAppend(IR_CONST_DATA, -1, -1, -1,
                         -(RECORD_RTTI_DATAREF_BASE + (dcElemRec - REC_UCLASS_BASE)), Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = layout blob }
        end;
        dcSetlenVal := IRAppendCall(procIdx, first, -1, Ord(tyNativeInt));
        IRIVal[dcSetlenVal] := 1;   { statement-level: side-effect call }
      end;

      { Like a dyn-array variable read: lea on the dyn-array symbol loads the
        handle (pointer-sized), so tag it tyPointer (an element-typed tag would
        make the assignment store only the element's width and truncate the
        64-bit handle). }
      Result := IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer));
    end;

    AN_DYN_DELETE:
    begin
      { Delete(arr, index, count) over a dynamic array. AN_DYN_COPY's template:
        build a fresh dyn-array temp of the post-delete length, fill it from
        the still-intact old buffer (PXXDynDelFill: head + tail forward copies,
        old->new is never self-overlapping), and yield the temp's handle — the
        parser wraps this node in `arr := <this>`, whose dyn-array store
        retains the new handle and releases the old buffer. Non-managed
        element types only (parser-enforced): the raw byte copy shares element
        handles with the old buffer, whose element-aware release would dangle
        them. }
      dcSrcSym := ASTIVal[ASTLeft[node]];
      dcElemTk := Syms[dcSrcSym].ElemType;
      dcElemRec := Syms[dcSrcSym].ElemRecName;
      if dcElemTk = tyRecord then dcElemSz := RecSize(dcElemRec)
      else dcElemSz := TypeSize(dcElemTk);
      dcIdxAst := ASTLeft[ASTRight[node]];
      dcCntAst := ASTLeft[ASTRight[ASTRight[node]]];

      { Materialize source data pointer, index and count once. }
      dcSrcTmp := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcSrcTmp,
        IRAppend(IR_LEA, dcSrcSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      dcIdxTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcIdxTmp, IRLowerAST(dcIdxAst), -1, 0, Ord(tyInteger));
      dcCntTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcCntTmp, IRLowerAST(dcCntAst), -1, 0, Ord(tyInteger));

      { newLen := PXXDynDelNewLen(srcData, index, count) — FPC clamping. }
      procIdx := FindProc('PXXDynDelNewLen');
      if procIdx < 0 then Error('compiler error: PXXDynDelNewLen not found');
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
                -1, -1, 0, Ord(tyInteger));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcCntTmp, -1, -1, 0, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      dcNewLenTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcNewLenTmp, IRAppendCall(procIdx, first, -1, Ord(tyNativeInt)),
        -1, 0, Ord(tyInteger));

      { Fresh dyn-array local of the source element type, prologue-nil'd via
        SymIsHiddenArgTemp (not an inline zero, which would leak the previous
        pass's handle in a loop — see AN_DYN_COPY above);
        SetLength(temp, newLen) via the -102 dyn-array SetLength call. }
      dcSavedRec := LastTypeRecId;
      if dcElemTk = tyRecord then LastTypeRecId := dcElemRec;
      dcTempSym := AllocDynArray('', dcElemTk, 1);
      LastTypeRecId := dcSavedRec;
      SymIsHiddenArgTemp[dcTempSym] := True;
      dcTempIdent := AllocNode(AN_IDENT); ASTIVal[dcTempIdent] := dcTempSym;
      ASTTk[dcTempIdent] := Ord(tyPointer);
      dcCountIdent := AllocNode(AN_IDENT); ASTIVal[dcCountIdent] := dcNewLenTmp;
      ASTTk[dcCountIdent] := Ord(tyInteger);
      { Empty the temp FIRST (SetLength(temp, 0)): in a loop the slot still
        holds the previous pass's buffer, and PXXDynSetLen's grow path would
        copy + element-retain its contents into the fresh block — refs the raw
        fill below then overwrites (managed-element leak). From an empty
        handle the sizing SetLength copies nothing. }
      dcZeroIdent := AllocNode(AN_INT_LIT);
      ASTIVal[dcZeroIdent] := 0; ASTTk[dcZeroIdent] := Ord(tyInteger);
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcZeroIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcCountIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;

      { PXXDynDelFill(destData, srcData, index, count, elemSize). Result stored
        (ignored) so the call is linked into the statement stream, like
        PXXMemCopy in AN_DYN_COPY. }
      procIdx := FindProc('PXXDynDelFill');
      if procIdx < 0 then Error('compiler error: PXXDynDelFill not found');
      dcDestData := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcDestData,
        IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                -1, -1, 0, Ord(tyPointer));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode; last := argNode;
      argNode := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcCntTmp, -1, -1, 0, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode; last := argNode;
      argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      IRAppend(IR_STORE_SYM, dcDestData, IRAppendCall(procIdx, first, -1, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));

      { AnsiString elements: retain every element now sitting in the fresh
        buffer (raw byte copies share handles with the OLD buffer, whose
        element-aware release fires when the assignment wrapper replaces the
        array's handle). Kept elements gain the ref the new buffer owns; the
        deleted range gains none, so the old-buffer release frees exactly those. Mirrors PXXDynSetLen's
        RetainImmediate-after-copy pattern. }
      if (dcElemTk = tyAnsiString) or
         ((dcElemTk = tyRecord) and RecordHasManagedFields(dcElemRec)) then
      begin
        procIdx := FindProc('PXXDynArrayRetainImmediate');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRetainImmediate not found');
        first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
        last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcNewLenTmp, -1, -1, 0, Ord(tyInteger)),
                  -1, -1, 0, Ord(tyInteger));
        IRB[first] := last;
        argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                     -1, -1, 0, Ord(tyInteger));
        IRB[last] := argNode; last := argNode;                 { depth = 1 }
        if dcElemTk = tyAnsiString then
        begin
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 1 (string) }
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = nil }
        end
        else
        begin
          { Managed-field record elements: field-walk retain via the record's
            layout descriptor (IR_CONST_DATA yields the blob's data address —
            the sentinel resolves to UClsRTTIOff at link fixup). }
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 3, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 3 (record) }
          argNode := IRAppend(IR_ARG,
                       IRAppend(IR_CONST_DATA, -1, -1, -1,
                         -(RECORD_RTTI_DATAREF_BASE + (dcElemRec - REC_UCLASS_BASE)), Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = layout blob }
        end;
        dcSetlenVal := IRAppendCall(procIdx, first, -1, Ord(tyNativeInt));
        IRIVal[dcSetlenVal] := 1;   { statement-level: side-effect call }
      end;

      Result := IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer));
    end;

    AN_DYN_INSERT:
    begin
      { Insert(value, arr, index) over a dynamic array — same fresh-temp shape
        as AN_DYN_DELETE: (len+1)-element temp, head/tail copied around a gap
        at the clamped index (PXXDynInsFill returns the gap's address), value
        stored into the gap. Scalar/pointer element types only
        (parser-enforced). Right = AN_ARG chain [value, index]. }
      dcSrcSym := ASTIVal[ASTLeft[node]];
      dcElemTk := Syms[dcSrcSym].ElemType;
      dcElemRec := Syms[dcSrcSym].ElemRecName;
      if dcElemTk = tyRecord then dcElemSz := RecSize(dcElemRec)
      else dcElemSz := TypeSize(dcElemTk);
      dcCntAst := ASTLeft[ASTRight[node]];               { value }
      dcIdxAst := ASTLeft[ASTRight[ASTRight[node]]];     { index }

      { Evaluate the value first (source argument order — it may itself touch
        the array). Scalars go by value into an element-typed temp; a managed
        (AnsiString) temp is a lowering-time local flagged for the
        codegen-prologue nil-init so the ARC store's release-of-old sees nil
        (scope exit balances the store's retain). Records/sets are captured by
        ADDRESS (parser guarantees addressability) — safe across the rebuild:
        the old buffer stays intact until the assignment wrapper swaps the
        handle, so even `Insert(a[k], a, i)` reads valid memory. }
      if (dcElemTk = tyRecord) or (dcElemTk = tySet) then
      begin
        dcValTmp := AllocVar('', tyPointer);
        IRAppend(IR_STORE_SYM, dcValTmp, IRLowerAddress(dcCntAst), -1, 0, Ord(tyPointer));
      end
      else
      begin
        dcValTmp := AllocVar('', dcElemTk);
        if dcElemTk = tyAnsiString then SymIsHiddenArgTemp[dcValTmp] := True;
        IRAppend(IR_STORE_SYM, dcValTmp, IRLowerAST(dcCntAst), -1, 0, Ord(dcElemTk));
      end;

      dcSrcTmp := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcSrcTmp,
        IRAppend(IR_LEA, dcSrcSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      dcIdxTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcIdxTmp, IRLowerAST(dcIdxAst), -1, 0, Ord(tyInteger));

      { newLen := PXXDynLen(srcData) + 1. }
      procIdx := FindProc('PXXDynLen');
      if procIdx < 0 then Error('compiler error: PXXDynLen not found');
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      dcNewLenTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcNewLenTmp, IRAppendCall(procIdx, first, -1, Ord(tyNativeInt)),
        -1, 0, Ord(tyInteger));
      IRAppend(IR_STORE_SYM, dcNewLenTmp,
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, dcNewLenTmp, -1, -1, 0, Ord(tyInteger)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), Ord(tkPlus), 0, Ord(tyInteger)),
        -1, 0, Ord(tyInteger));

      { Fresh dyn-array local, prologue-nil'd via SymIsHiddenArgTemp (see
        AN_DYN_COPY); SetLength(temp, newLen). Record elements need the
        element REC id on the temp (descriptor / element size). }
      dcSavedRec := LastTypeRecId;
      if dcElemTk = tyRecord then LastTypeRecId := dcElemRec;
      dcTempSym := AllocDynArray('', dcElemTk, 1);
      LastTypeRecId := dcSavedRec;
      SymIsHiddenArgTemp[dcTempSym] := True;
      dcTempIdent := AllocNode(AN_IDENT); ASTIVal[dcTempIdent] := dcTempSym;
      ASTTk[dcTempIdent] := Ord(tyPointer);
      dcCountIdent := AllocNode(AN_IDENT); ASTIVal[dcCountIdent] := dcNewLenTmp;
      ASTTk[dcCountIdent] := Ord(tyInteger);
      { Empty the temp FIRST (SetLength(temp, 0)): in a loop the slot still
        holds the previous pass's buffer, and PXXDynSetLen's grow path would
        copy + element-retain its contents into the fresh block — refs the raw
        fill below then overwrites (managed-element leak). From an empty
        handle the sizing SetLength copies nothing. }
      dcZeroIdent := AllocNode(AN_INT_LIT);
      ASTIVal[dcZeroIdent] := 0; ASTTk[dcZeroIdent] := Ord(tyInteger);
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcZeroIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcCountIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;

      { gap := PXXDynInsFill(destData, srcData, index, elemSize). }
      procIdx := FindProc('PXXDynInsFill');
      if procIdx < 0 then Error('compiler error: PXXDynInsFill not found');
      dcDestData := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcDestData,
        IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                -1, -1, 0, Ord(tyPointer));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode; last := argNode;
      argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)),
                   -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      dcGapTmp := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcGapTmp, IRAppendCall(procIdx, first, -1, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));

      { AnsiString elements: retain every element now sitting in the fresh
        buffer (raw byte copies share handles with the OLD buffer, whose
        element-aware release fires when the assignment wrapper replaces the
        array's handle). Kept elements gain the ref the new buffer owns; the
        still-nil gap is a no-op for the retain walk (the ARC-aware gap store below adds the inserted value's ref itself). Mirrors PXXDynSetLen's
        RetainImmediate-after-copy pattern. }
      if (dcElemTk = tyAnsiString) or
         ((dcElemTk = tyRecord) and RecordHasManagedFields(dcElemRec)) then
      begin
        procIdx := FindProc('PXXDynArrayRetainImmediate');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRetainImmediate not found');
        first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
        last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcNewLenTmp, -1, -1, 0, Ord(tyInteger)),
                  -1, -1, 0, Ord(tyInteger));
        IRB[first] := last;
        argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                     -1, -1, 0, Ord(tyInteger));
        IRB[last] := argNode; last := argNode;                 { depth = 1 }
        if dcElemTk = tyAnsiString then
        begin
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 1 (string) }
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = nil }
        end
        else
        begin
          { Managed-field record elements — see AN_DYN_DELETE. The still-zero
            gap record is nil-field for the walk (retains nothing there); the
            IR_COPY_REC_MANAGED gap store below adds the inserted value's own
            field refs. }
          argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, 3, Ord(tyInteger)),
                       -1, -1, 0, Ord(tyInteger));
          IRB[last] := argNode; last := argNode;               { baseKind = 3 (record) }
          argNode := IRAppend(IR_ARG,
                       IRAppend(IR_CONST_DATA, -1, -1, -1,
                         -(RECORD_RTTI_DATAREF_BASE + (dcElemRec - REC_UCLASS_BASE)), Ord(tyPointer)),
                       -1, -1, 0, Ord(tyPointer));
          IRB[last] := argNode;                                { baseRecDesc = layout blob }
        end;
        dcSetlenVal := IRAppendCall(procIdx, first, -1, Ord(tyNativeInt));
        IRIVal[dcSetlenVal] := 1;   { statement-level: side-effect call }
      end;

      { Store the value into the gap. Scalars: element-width memory store (a
        tyAnsiString tag routes through IR_STORE_MEM's ARC path — retains the
        value for the array, releases the nil gap). Records/sets: raw
        element-size memory copy from the captured address (non-managed only,
        parser-enforced). }
      if (dcElemTk = tyRecord) and RecordHasManagedFields(dcElemRec) then
        { Managed-field record: ARC-correct copy — retain the source's fields,
          release the destination's (the gap is fresh zeros, so nil-safe), then
          bulk-copy. The retain is what the new buffer's ownership needs. }
        IRAppend(IR_COPY_REC_MANAGED, IRAppend(IR_LOAD_SYM, dcGapTmp, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_LOAD_SYM, dcValTmp, -1, -1, 0, Ord(tyPointer)), dcElemRec, dcElemSz, Ord(tyRecord))
      else if (dcElemTk = tyRecord) or (dcElemTk = tySet) then
        IRAppend(IR_COPY_REC, IRAppend(IR_LOAD_SYM, dcGapTmp, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_LOAD_SYM, dcValTmp, -1, -1, 0, Ord(tyPointer)), -1, dcElemSz, Ord(tyRecord))
      else
        IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, dcGapTmp, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_LOAD_SYM, dcValTmp, -1, -1, 0, Ord(dcElemTk)), -1, 0, Ord(dcElemTk));

      Result := IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer));
    end;

    AN_ASM:
      Result := IRAppend(IR_ASM, ASTLeft[node], ASTRight[node], -1, 0, Ord(tyUnknown));

    AN_IDENT:
    begin
      varIdx := ASTIVal[node];
      if Syms[varIdx].IsArray then
        { An ARRAY in rvalue position IS its base address (C's decay; the same
          handle Pascal passes). The node therefore has POINTER type — it used
          to carry ASTTk, the ELEMENT type, and an address node claiming to be a
          double is one the backend classifies as floating-point and routes to
          an xmm register. `(void*)A` on a `double A[]` then handed its callee
          whatever stale value sat in the integer register — a stack address —
          while the identical `int B[]` was correct only because tyInt32 happens
          to share the general-register class. `A == &A[0]` answered 0.
          bug-c-cast-of-a-float-element-array-to-a-pointer-yields-a-wrong-address }
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer))
      else if TypeIsFrozenString(Syms[varIdx].TypeKind) or (Syms[varIdx].TypeKind = tySet) then
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, ASTTk[node])
      else if TypeIsPromoInt(Syms[varIdx].TypeKind) and not Syms[varIdx].IsRef then
        { A promotable int IS its slot: the value may be a bignum, so an rvalue
          is the slot address, not a machine int (Option A, the tyVariant
          model). }
        Result := IRAppend(IR_SLOTADDR, varIdx, -1, -1, 0, Ord(tyPointer))
      else
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[node]);
    end;

    AN_INDEX, AN_FIELD, AN_DEREF:
    begin
      left := IRLowerAddress(node);
      if CProgramMode and (ASTKind[node] = AN_FIELD) and
         RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) and
         (RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) = 0) then
      begin
        { C fixed-array struct field (e.g. `char contents[N]`) decays to a pointer
          = the field's ADDRESS, exactly like an array variable (AN_IDENT IsArray
          -> IR_LEA above). Without this it would load the array's first bytes as a
          scalar value. }
        Result := left;
        IRTk[Result] := Ord(tyPointer);
      end
      else if CProgramMode and (ASTKind[node] = AN_FIELD) and
              (RecFieldBitWidth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) > 0) then
        Result := IRLowerBitFieldRead(node, left,
                                      RecFieldType(ResolveNodeRec(ASTLeft[node]),
                                                   GetASTIdentName(node)))
      else if (IntToTypeKind(ASTTk[node]) = tyString) or (IntToTypeKind(ASTTk[node]) = tySet) then
      begin
        { A frozen-string / set value IS its address (no load). Present the
          address node with the value's frozen-string tag, mirroring the AN_IDENT
          path above: otherwise it carries IRLowerAddress's tyPointer tag and a
          consumer (e.g. `m := p^` into a managed string) misreads the address as
          a raw pointer instead of a frozen inline string. }
        Result := left;
        if IntToTypeKind(ASTTk[node]) = tyString then
          IRTk[Result] := ASTTk[node];
      end
      else if NodeDynDepth(node) > 0 then
        { Dynamic-array handle read (e.g. `rec.arr`, a nested sub-array): the
          value is a pointer-sized heap handle. ASTTk tags it with the ELEMENT
          type (Integer etc.), so an element-typed load would emit a 4-byte
          movsxd and sign-extend-truncate the 64-bit handle — a corrupted pointer
          whose first refcount/deref segfaults. Force a full pointer-width load. }
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, Ord(tyPointer))
      else
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_PTR_CAST:
    begin
      { {$MODE DELPHI}: `Int64(fp)` / `PtrUInt(fp)` cast the procvar's CALL
        RESULT. A cast never wants the procvar itself — `@fp` is how you take
        the address — so the operand is not a procvar sink. }
      ASTLeft[node] := IRProcVarAutoCall(ASTLeft[node], False);
      castTk := IntToTypeKind(ASTTk[node]);
      if (castTk = tyString) or (castTk = tyAnsiString) then
      begin
        if IsNodePChar(ASTLeft[node]) and not CProgramMode then
        begin
          Result := IRLowerAST(WrapPCharToString(ASTLeft[node]));
          Exit;
        end;
      end;

      { PChar(managedString): the managed handle is already the NUL-terminated
        char pointer when non-empty, but an empty managed string is a nil handle —
        FPC guarantees PChar('') is a valid pointer to a static #0 byte, never nil.
        Route through PXXPCharOf, which substitutes that shared #0 byte for a nil
        handle, so a C/PAL call f(PChar(s)) on an empty s does not deref nil. The
        helper is registered whenever managed strings are in use (needHeapUnit);
        if absent (degenerate build) fall through to the bare reinterpret. }
      if (ASTIVal[node] = -2) and (ASTTk[ASTLeft[node]] = Ord(tyAnsiString)) then
      begin
        procIdx := FindProc('PXXPCharOf');
        if procIdx >= 0 then
        begin
          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := ASTLeft[node];
          ASTRight[wrapperArg] := -1;
          ASTTk[wrapperArg] := Ord(tyPointer);

          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := procIdx;
          ASTTk[wrapperCall] := Ord(tyPointer);
          ASTLeft[wrapperCall] := wrapperArg;
          ASTRight[wrapperCall] := -1;

          Result := IRLowerAST(wrapperCall);
          Exit;
        end;
      end;

      { A cast PType(expr) is purely a type-tag change — the value in rax is
        already the pointer. No load-through-memory here. }
      Result := IRLowerAST(ASTLeft[node]);
      { PChar(stringExpr): an inline-length string value points at its 8-byte
        length prefix; a C `const char*` needs the char data, which sits at +8
        (now guaranteed NUL-terminated by InternStr). Sentinel -2 in ASTIVal
        marks the PChar/PAnsiChar adapter; only adjust for inline-string
        operands so PChar(somePointer) stays a pure reinterpret. }
      if (ASTIVal[node] = -2) and (ASTTk[ASTLeft[node]] = Ord(tyString)) then
      begin
        right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
        Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, Ord(tyPointer));
      end
      else if (ASTIVal[node] = -1) or (ASTIVal[node] = -3) then
      begin
        { -3 = the WideChar value cast: identical width-truncating semantics
          here; only string contexts treat it specially (UTF-8 conversion). }
        { Builtin numeric/ordinal reinterpret (Int64/UInt64/Integer/Cardinal/...):
          re-tag the result IR node with the cast's width so width-sensitive ops
          (e.g. tkShl's 32-bit wrap) read the operand's real width. Without this,
          UInt64(1) lowers to the inner const's 32-bit IRTk and a shl-into-bit-31
          truncation would wrongly fire. See bug-shl-signed-integer-width. }
        castTk := IntToTypeKind(ASTTk[node]);
        { NativeInt/NativeUInt join Int64/UInt64 here when they ARE 64-bit
          (the pointer-sized pair is 4 bytes on a 32-bit target, where the
          narrowing branch below is the correct handler). Without them,
          `NativeUInt(rec.someInteger)` fell through to the in-place retag,
          which turns the operand's 4-byte field LOAD into an 8-byte one and
          drags in whatever field sits next in the record — the same hazard the
          float branch below documents. See bug-nativeuint-cast-widens-load. }
        { The SOURCE-side test asks "is the operand already 64 bits, so no widen
          is needed?" — and it must apply the same pointer-width rule the
          cast-side test above applies. It used to list tyNativeInt/tyNativeUInt
          unconditionally, which is only true on a 64-bit target: on i386/arm32
          a NativeInt is FOUR bytes, so `Int64(n)` took the "already wide"
          branch, skipped the widen, and fell through to the in-place retag —
          turning a 4-byte load into an 8-byte one and picking up whatever sat
          in the adjacent storage. Int64(5) read 4294967301.
          Silent, and the garbage moved with the stack layout. The IMPLICIT
          conversion (`q := n`) never came through here, which is why it stayed
          correct and hid this.
          bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit }
        if ((castTk = tyInt64) or (castTk = tyUInt64) or
            (((castTk = tyNativeInt) or (castTk = tyNativeUInt)) and
             (TypeSize(castTk) = 8)))
           and not ((IntToTypeKind(IRTk[Result]) = tyInt64) or
                    (IntToTypeKind(IRTk[Result]) = tyUInt64) or
                    (((IntToTypeKind(IRTk[Result]) = tyNativeInt) or
                      (IntToTypeKind(IRTk[Result]) = tyNativeUInt)) and
                     (TypeSize(IntToTypeKind(IRTk[Result])) = 8))) then
        begin
          { Widening numeric reinterpret 32->64 (e.g. Int64(someInteger)): on a
            32-bit target the inner value occupies one register and its high word
            is undefined; a bare re-tag tells consumers "this is 64-bit" but no
            sign/zero-extend ever runs (EmitNode64 widens only when the SOURCE tag
            is narrow). Force a real widen by adding 0: the inner node keeps its
            own narrow tag so the extend direction follows its signedness, and the
            sum carries the cast's 64-bit tag. No-op on 64-bit targets where the
            load is already full-width. See bug-i386-arm32-int64-conformance. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 0, ASTTk[node]);
          Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, ASTTk[node]);
        end
        else if CProgramMode and TypeIsOrdinal(castTk) and
                TypeIsOrdinal(IntToTypeKind(IRTk[Result])) and
                (IRTk[Result] <> ASTTk[node]) then
        begin
          { Do not retag a width-sensitive load in place. `(int)byte_field`
            must load one byte and then widen the value; changing the load node
            to Integer makes codegen read four bytes from the byte field. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 0, ASTTk[node]);
          Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, ASTTk[node]);
        end
        else
        begin
          { Narrowing (or same/narrower-width reinterpret) ordinal rvalue cast,
            e.g. byte(i)/word(i)/cardinal(i)/shortint(i): assigning to a
            variable of the narrower type truncates for free (the store only
            writes N bytes), but a bare rvalue cast has no store to piggyback
            on, so the full-width value would otherwise pass straight through
            unmasked. Force the width conversion explicitly: mask to the
            target width, then for signed targets re-derive the sign via the
            standard two's-complement identity (v xor signbit) - signbit,
            which correctly reinterprets the just-masked low N bits as signed
            regardless of what the wider source value looked like. }
          narrowSize := TypeSize(castTk);
          castIsSigned := (castTk = tyInteger) or (castTk = tyInt8) or
                          (castTk = tyInt16) or (castTk = tyInt32) or
                          (castTk = tyNativeInt);
          if (narrowSize < 8) and (castTk <> tyBoolean) and (castTk <> tyChar) and
             (castTk <> tyPointer) and TypeIsOrdinal(castTk) then
          begin
            right := IRAppend(IR_CONST_INT, -1, -1, -1,
                               (Int64(1) shl (narrowSize * 8)) - 1, ASTTk[node]);
            Result := IRAppend(IR_BINOP, Result, right, Ord(tkAnd), 0, ASTTk[node]);
            if castIsSigned then
            begin
              right := IRAppend(IR_CONST_INT, -1, -1, -1,
                                 Int64(1) shl (narrowSize * 8 - 1), ASTTk[node]);
              Result := IRAppend(IR_BINOP, Result, right, Ord(tkXor), 0, ASTTk[node]);
              right := IRAppend(IR_CONST_INT, -1, -1, -1,
                                 Int64(1) shl (narrowSize * 8 - 1), ASTTk[node]);
              Result := IRAppend(IR_BINOP, Result, right, Ord(tkMinus), 0, ASTTk[node]);
            end;
          end
          else if not TypeIsFloat(castTk) then
            IRTk[Result] := ASTTk[node]
          else
            { float<->float cast, e.g. `(float)*doubleptr` / `(double)*floatptr`.
              A reinterpret would be WRONG here: retagging the operand node in
              place changes a memory LOAD's width (8<->4 bytes) and reads garbage
              (bug-c-double-ptr-deref-narrow-to-single). The value already lives
              as double bits in a register at the operand's natural width, and a
              store to a single/double slot narrows/keeps by DEST type — so leave
              the operand untouched. (A float<->int cast never reaches here: it is
              routed to the -203 Trunc / -206 Int intrinsics above.) }
            ;
        end;
      end;
    end;

    AN_RTTI_REG:
    begin
      Result := IRAppend(IR_RTTI_REG, -1, -1, -1, 0, ASTTk[node]);
    end;

    AN_RESOURCES:
    begin
      Result := IRAppend(IR_RESOURCES, -1, -1, -1, 0, ASTTk[node]);
    end;

    AN_SYSCALL:
    begin
      { Args (nr, a0..a5) as an IR_ARG chain; backend moves them into the
        target's syscall registers and emits the native trap instruction. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_SYSCALL, first, -1, -1, 0, ASTTk[node]);
    end;

    AN_COSWITCH:
    begin
      { Two pointer args (pfrom, pto) as an IR_ARG chain; backend moves them into
        rdi/rsi and calls the bare CoSwitch stub. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_COSWITCH, first, -1, -1, 0, ASTTk[node]);
    end;

    AN_CLONE:
    begin
      { Five args (flags, childStack, entry, arg, ctidptr) as an IR_ARG chain;
        backend moves them into the SysV arg regs and calls the bare clone+
        trampoline stub. Result (child tid) in the accumulator. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_CLONE, first, -1, -1, 0, ASTTk[node]);
    end;

    AN_ATOMIC:
    begin
      { addr + operands as an IR_ARG chain; op carried in IRIVal. Backend emits a
        lock-prefixed 32-bit rmw and returns the old value. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_ATOMIC, first, -1, -1, ASTIVal[node], ASTTk[node]);
    end;

    AN_MULHI:
    begin
      { Unsigned 64x64->128, high half. Only the 64-bit targets have the
        instruction (x86-64 `mul`, aarch64 `umulh`); the 32-bit ones would need a
        multi-limb expansion, so reject here rather than in six backends. Portable
        code goes through lib/rtl's MulHiU64, which picks the Pascal fallback when
        CPU64 is not defined. }
      if not ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64)) then
        Error('__pxxmulhi_u64 requires a 64-bit target (x86-64 / aarch64); use MulHiU64 from lib/rtl for a portable path');
      Result := IRAppend(IR_MULHI, IRLowerAST(ASTLeft[node]),
                  IRLowerAST(ASTRight[node]), -1, 0, ASTTk[node]);
    end;

    AN_CLASS_VIRTUAL_CALL:
    begin
      { A VIRTUAL CLASS METHOD, dispatched on the RUNTIME class.

        Arg 0 is the metaclass Self -- the RTTI blob pointer -- NOT an instance, so
        IR_VIRTUAL_CALL cannot be reused: it loads the VMT from [Self + 0], which on a blob
        is the name pointer. The blob keeps its VMT at +24 (RTTI_CLS layout), so:

            vmt  := [Self + 24]
            code := [vmt + slot * PtrSize]
            call code(args)

        Ordinary loads and an IR_CALL_IND -- target-independent, no backend op. }
      cpi := ASTIVal[node];
      first := -1; last := -1;
      item := ASTLeft[node];
      pathIdx := 0;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode else IRB[last] := argNode;
        last := argNode;
        if pathIdx = 0 then selfVal := value;   { the blob }
        item := ASTRight[item];
        Inc(pathIdx);
      end;

      outNode := IRAppend(IR_BINOP, selfVal,
                   IRAppend(IR_CONST_INT, -1, -1, -1, 24, Ord(tyInteger)),
                   Ord(tkPlus), 0, Ord(tyPointer));
      value := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer));    { vmt }
      { slot * 8, NOT * PtrSize: the VMT (like the rest of the data blob) keeps 8-byte slots on
        EVERY target -- on 32-bit the address sits in the low dword and a pointer-sized load
        reads it. Scaling by TARGET_PTR_SIZE indexed the wrong entry on the ILP32 targets.
        This is the same convention IR_VIRTUAL_CALL's per-backend emit already uses. }
      outNode := IRAppend(IR_BINOP, value,
                   IRAppend(IR_CONST_INT, -1, -1, -1,
                            Integer(ASTSOffset[node]) * 8, Ord(tyInteger)),
                   Ord(tkPlus), 0, Ord(tyPointer));
      callVal := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer)); { code }

      Result := IRAppend(IR_CALL_IND, callVal, first, 0, cpi, ASTTk[node]);
      if ABIRetViaHiddenDestProc(cpi) then
        IRCallDest[Result] := IRBuildHiddenDest(cpi);
    end;

    AN_EXCEPTADDR:
    begin
      { The raise stub already parked the raise site in BSS_EXC_ADDR. Reading it is the
        same load IR_EXC_STORE does for the exception object — IRC=1 picks the slot — so
        no backend gets a new op. }
      eaSym := AllocVar('', tyPointer);
      IRAppend(IR_EXC_STORE, eaSym, -1, 1, 0, 0);
      Result := IRAppend(IR_LOAD_SYM, eaSym, -1, -1, 0, Ord(tyPointer));
    end;

    AN_SIGINFO:
    begin
      { The dispatch stub parked si_code / si_addr / ucontext* before calling the
        hook; ASTIVal picks which (0/1/2), mapping to IRC 2/3/4 — the same slot
        load AN_EXCEPTADDR uses. si_code is an ordinal (already sign-extended in
        the stub), the other two are addresses.

        ASTIVal 3 (__pxxSigPCPtr) is the ucontext slot PLUS the per-arch byte
        offset of the saved PC inside it — a plain pointer add on the loaded
        slot, so it still costs no backend anything. }
      eaSym := AllocVar('', IntToTypeKind(ASTTk[node]));
      if ASTIVal[node] = 3 then
        IRAppend(IR_EXC_STORE, eaSym, -1, 4, 0, 0)      { the ucontext pointer }
      else
        IRAppend(IR_EXC_STORE, eaSym, -1, ASTIVal[node] + 2, 0, 0);
      Result := IRAppend(IR_LOAD_SYM, eaSym, -1, -1, 0, ASTTk[node]);
      if ASTIVal[node] = 3 then
        Result := IRAppend(IR_BINOP, Result,
                    IRAppend(IR_CONST_INT, -1, -1, -1, UContextPCOffset, Ord(tyPointer)),
                    Ord(tkPlus), 0, Ord(tyPointer));
    end;

    AN_TYPEINFO:
      if ASTLeft[node] = 1 then
        { Widened TypeInfo(T): scalar/string/class/record, ASTIVal = the deduped
          TypeInfoReq index. Header address resolved post-EmitTypeInfoHeaders,
          same sentinel-then-fixup convention as the enum/class/record cases. }
        Result := IRAppend(IR_CONST_DATA, -1, -1, -1,
                    -(TYPEINFO_REQ_DATAREF_BASE + Integer(ASTIVal[node])), Ord(tyPointer))
      else
        { TypeInfo(TEnum) -> the address of the enum's RTTI blob. The offset is not known
          until EmitRTTI has run, so emit the sentinel and let the pre-link fixup pass
          resolve it (exactly as AN_CLASSREF does for a class). }
        Result := IRAppend(IR_CONST_DATA, -1, -1, -1,
                    -(ENUM_RTTI_DATAREF_BASE + Integer(ASTIVal[node])), Ord(tyPointer));

    AN_RTTIOF:
    begin
      { blob = [[instance + 0] - 8]: load the VMT pointer parked at the instance's
        +0, then the RTTI backlink word reserved immediately before the VMT.

        The offset is a HARD 8 on every target, not SizeOf(Pointer): the word the VMT
        allocator reserves ahead of the table is 8 bytes wide on 32-bit too (see the
        VMT-alloc sites in parser.inc/pyparser.inc, and __pxxRttiOf, which hardcodes
        -8 and is what the 32-bit ClassName path has always used). Using the pointer
        size here read 4 bytes too high on the ILP32 targets and returned garbage. }
      frameNode := IRAppend(IR_LOAD_MEM, IRLowerAST(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
      slotNode := IRAppend(IR_BINOP, frameNode,
                    IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyPointer)),
                    Ord(tkMinus), 0, Ord(tyPointer));
      Result := IRAppend(IR_LOAD_MEM, slotNode, -1, -1, 0, Ord(tyPointer));
    end;

    AN_FRAME:
    begin
      { get_frame. The one op the backends implement; everything else below is
        built out of it. }
      IRRejectNoFramePointer('get_frame');
      Result := IRAppend(IR_FRAME, -1, -1, -1, 0, Ord(tyPointer));
    end;

    AN_PCADDR:
    begin
      { get_pc_addr = the return address of the CURRENT function, which the
        prologue parked one word above the saved frame pointer: [fp + PtrSize].
        So it is a plain load off IR_FRAME -- no backend op of its own. }
      IRRejectNoFramePointer('get_pc_addr');
      frameNode := IRAppend(IR_FRAME, -1, -1, -1, 0, Ord(tyPointer));
      slotNode := IRAppend(IR_BINOP, frameNode,
                    IRAppend(IR_CONST_INT, -1, -1, -1, FrameRetAddrOffset, Ord(tyPointer)),
                    Ord(tkPlus), 0, Ord(tyPointer));
      Result := IRAppend(IR_LOAD_MEM, slotNode, -1, -1, 0, Ord(tyPointer));
    end;

    AN_CALLERINFO:
    begin
      { get_caller_stackinfo(var bp, var addr): step ONE frame up the saved-fp
        chain. Reads bp, then

          addr := [bp + PtrSize]   { return address into bp's caller }
          bp   := [bp]             { bp's caller's frame }

        in that ORDER -- addr is derived from the OLD bp, so overwriting bp first
        would hand back the wrong return address. Loads and stores only; the frame
        register itself is never named here, so no backend op is needed.

        The caller is expected to have checked bp <> nil; a nil bp faults, exactly
        as it does in FPC. }
      IRRejectNoFramePointer('get_caller_stackinfo');
      bpAddr := IRLowerAddress(ASTLeft[node]);       { &bp   }
      addrAddr := IRLowerAddress(ASTRight[node]);    { &addr }
      bpVal := IRAppend(IR_LOAD_MEM, bpAddr, -1, -1, 0, Ord(tyPointer));
      slotNode := IRAppend(IR_BINOP, bpVal,
                    IRAppend(IR_CONST_INT, -1, -1, -1, FrameRetAddrOffset, Ord(tyPointer)),
                    Ord(tkPlus), 0, Ord(tyPointer));
      IRAppend(IR_STORE_MEM, addrAddr,
        IRAppend(IR_LOAD_MEM, slotNode, -1, -1, 0, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));
      { re-load bp: the store above may have clobbered the accumulator }
      bpVal := IRAppend(IR_LOAD_MEM, bpAddr, -1, -1, 0, Ord(tyPointer));
      slotNode := IRAppend(IR_BINOP, bpVal,
                    IRAppend(IR_CONST_INT, -1, -1, -1, FramePrevFpOffset, Ord(tyPointer)),
                    Ord(tkPlus), 0, Ord(tyPointer));
      Result := IRAppend(IR_STORE_MEM, bpAddr,
        IRAppend(IR_LOAD_MEM, slotNode, -1, -1, 0, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));
    end;

    AN_YIELD:
    begin
      { value -> [self+CO_OFF_CURRENT], then CoSwitch(self+GENCTX -> self+CALLERCTX).
        IRIVal carries the generator self-pointer local sym idx. A record element
        does not fit the one-word current slot, so yield its ADDRESS instead — the
        stackful generator's frame keeps the record alive until the next resume,
        and the for-in desugar derefs the address into the loop variable. }
      if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord then
        value := IRLowerAddress(ASTLeft[node])
      else
        value := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_YIELD, value, -1, -1, ASTIVal[node], ASTTk[ASTLeft[node]]);
    end;

    AN_AWAIT:
    begin
      { Stackful (v1): documentary — `await E` evaluates exactly as `E`. The
        awaited call suspends on its own (reactor/CoYield). The stackless backend
        will instead split the state machine here. }
      Result := IRLowerAST(ASTLeft[node]);
    end;

    AN_STR_FROM_CHAR:
    begin
      { String(c): Left is the `__t := c` store (a 1-char string materialised into
        a hidden temp via the ordinary assignment path, frozen or managed); Right
        is the read of __t that yields the string value. No backend code — both
        sub-nodes are ordinary IR built at parse time. }
      { Mark the side-effect as a statement so a call-shaped Left (e.g. the
        synthesized ArgStr that fills a temp for inline ParamStr) is actually
        emitted; a store-shaped Left (String(c)) emits unconditionally, so the
        mark is a harmless no-op there. }
      IRMarkStatementNode(IRLowerAST(ASTLeft[node]));   { side-effect into hidden temp }
      Result := IRLowerAST(ASTRight[node]);
    end;

    AN_IS_TEST:
    begin
      varIdx := IRLowerClassMatch(ASTLeft[node], Integer(ASTIVal[node]), classIdx);
      Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
    end;

    AN_AS_CAST:
    begin
      if UClsIsInterface[Integer(ASTIVal[node])] then
      begin
        { `obj as IFoo`: yield the address of the materialised fat pointer (the
          aggregate-by-reference convention, like a record-returning call). }
        Result := IRAppend(IR_LEA, IRMaterializeIntfCast(node, True), -1, -1, 0, Ord(tyPointer));
        Exit;
      end;
      { Checked downcast: compute the match, then yield the instance typed as T.
        nil passes through (nil as T = nil); a non-nil mismatch traps (Halt). }
      varIdx := IRLowerClassMatch(ASTLeft[node], Integer(ASTIVal[node]), classIdx);
      endLabel := IRNewLabel;     { continue (yield instance) }
      elseLabel := IRNewLabel;    { trap }
      left := IRAppend(IR_LOAD_SYM, classIdx, -1, -1, 0, Ord(tyPointer));
      value := IRAppend(IR_BINOP, left, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                        Ord(tkNeq), 0, Ord(tyBoolean));
      IRAppend(IR_JUMP_IF_FALSE, endLabel, value, -1, 0, 0);   { nil -> pass through }
      right := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
      IRAppend(IR_JUMP_IF_FALSE, elseLabel, right, -1, 0, 0);  { non-nil mismatch -> trap }
      IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      IRAppend(IR_TERMINATE, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), -1, -1, AN_HALT, 0);
      IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_LOAD_SYM, classIdx, -1, -1, 0, Ord(tyClass));
    end;

    AN_CLASS_CAST:
    begin
      { Hard class reinterpret: the instance pointer is unchanged, only the
        static type. Pass the value through; .field/[i] on it resolve their
        offsets against the cast's class via ResolveNodeRec(AN_CLASS_CAST). }
      Result := IRLowerAST(ASTLeft[node]);
    end;

    AN_ADDR:
    begin
      { `@s` where s is a scalar MANAGED STRING: the address of the VARIABLE, not of its data.

        IR_LEA on such a symbol deliberately LOADS the handle rather than taking the address --
        the slot holds a heap pointer, and every consumer that wants "the string's bytes" (a
        by-ref pass, C interop) wants exactly that. But it makes `@s` return the data pointer,
        so `p: ^string; p := @s; p^` read the string's first 8 bytes AS IF they were a handle
        and segfaulted (bug-pascal-deref-managed-string-ptr).

        AN_SLOTADDR is precisely "the variable's own slot, no auto-deref", so `@` on a managed
        string ident uses it. Nothing else changes: the by-ref and lvalue-write paths do not go
        through AN_ADDR. }
      if (ASTKind[ASTLeft[node]] = AN_IDENT) and (ASTIVal[ASTLeft[node]] >= 0) and
         (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyAnsiString) and
         (not Syms[ASTIVal[ASTLeft[node]]].IsArray) then
      begin
        Result := IRAppend(IR_SLOTADDR, Integer(ASTIVal[ASTLeft[node]]), -1, -1, 0, Ord(tyPointer));
        Exit;
      end;

      Result := IRLowerAddress(ASTLeft[node]);
      { The address VALUE is a pointer no matter what it points at.
        IRLowerAddress tags its node with the pointee's type; for a float
        pointee (`&rec.dblField`, `&globalDouble`) that float tk leaked into
        C call-arg marshalling, whose float->int-param truncation then
        cvttsd2si'd the ADDRESS BITS — tcc's write_ldouble(ptr, &vtop->c.ld)
        received s=0 and crashed (feature-c-corpus-tcc, b190). Retag only the
        float case (minimal surface; ordinal-tagged addresses behave). }
      if CProgramMode and (Result >= 0) and
         TypeIsFloat(IntToTypeKind(IRTk[Result])) then
        IRTk[Result] := Ord(tyPointer);
    end;

    AN_SLOTADDR:
    begin
      { Address of the variable's OWN slot — no by-ref auto-deref (see defs). }
      Result := IRAppend(IR_SLOTADDR, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
    end;

    AN_COMPOUND_LITERAL:
    begin
      { C99 compound literal as a value: emit the init statement chain into the
        current block, then yield the temp's ADDRESS (records are carried by
        address in this IR, so by-value use / assignment RHS copy from it). }
      IRMarkStatementNode(IRLowerAST(ASTLeft[node]));
      Result := IRAppend(IR_LEA, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
    end;

    AN_PROCADDR:
    begin
      Result := IRAppend(IR_PROCADDR, Integer(ASTIVal[node]), -1, -1, 0, ASTTk[node]);
    end;

    AN_CLASSREF:
    begin
      { class index in IRA; codegen emits the RTTI-blob address (PClassRTTI). }
      Result := IRAppend(IR_CLASSREF, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
      { ASTRight = 1: a NilPy CLASS used as a VALUE. The blob address alone is
        an integer, and an integer payload is already how a compiled def, a
        pyeval closure and a lifted bound-fn all ride — so `cls(3)` could not
        tell a class from a function and jumped into the blob. Box it under its
        own tag instead; every downstream site (assignment to a variant, list
        element, dict value, argument, `cls(...)` through pyvar_callvN) then
        works with no further site of its own, which is the point of doing it
        HERE rather than at each of them. feature-nilpy-class-as-a-value }
      if ASTRight[node] = 1 then
      begin
        pathIdx := FindProc('PyBoxClassRef');
        if pathIdx < 0 then Error('Nil Python: PyBoxClassRef (pyeval) not loaded');
        Result := IRAppendCall(pathIdx,
                    IRAppend(IR_ARG, Result, -1, -1, 0, Ord(tyPointer)),
                    -1, Ord(tyVariant));
      end;
    end;

    AN_METHODREF:
    begin
      { Outside an assignment to a TMethod target we can only surface the code
        half; the proper 16-byte store lives in AN_ASSIGN. VMT-resolved for a
        virtual method so `@obj.VirtualMethod` in a value/arg position points at
        the override. }
      Result := IRMethodRefCode(node);
    end;

    AN_NEG:
    begin
      if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) then
      begin
        { `-p` on a promotable int: rewrite to `0 - p` so the ordinary promo
          binop path handles it. IR_NEG on the raw slot would negate the ADDRESS,
          and for a wide literal the digit text carries no sign — `x :=
          -18446744073709551616` gave 0 and `-x` segfaulted before this.
          Same rewrite the variant case below uses, for the same reason. }
        first := AllocNode(AN_INT_LIT);
        ASTIVal[first] := 0;
        ASTTk[first] := Ord(tyInteger);
        last := AllocNode(AN_BINOP);
        ASTIVal[last] := Ord(tkMinus);
        ASTLeft[last] := first;
        ASTRight[last] := ASTLeft[node];
        ASTTk[last] := ASTTk[ASTLeft[node]];
        Result := IRLowerAST(last);
        Exit;
      end;
      if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
      begin
        { `-v` on a variant: rewrite to `0 - v` so the existing IR_VAR_BINOP
          runtime tag dispatch decides the arithmetic. Unboxing to a fixed
          scalar here would have to guess int vs double and would print -7.0
          for an int payload; IR_NEG on the raw 8 bytes negated the TAG.
          (bug-a-nilpy-variant-element-not-usable-as-scalar.) }
        first := AllocNode(AN_INT_LIT);
        ASTIVal[first] := 0;
        ASTTk[first] := Ord(tyInteger);
        last := AllocNode(AN_BINOP);
        ASTIVal[last] := Ord(tkMinus);
        ASTLeft[last] := first;
        ASTRight[last] := ASTLeft[node];
        ASTTk[last] := Ord(tyVariant);
        Result := IRLowerAST(last);
        Exit;
      end;
      left := IRLowerAST(ASTLeft[node]);
      { Trust the LOWERED operand's type over the parse-time one: `//` on floats
        is spelled tkDiv, so the parser typed it integer and only the lowering
        knows it produced a double. Negating with the stale tag emitted an
        integer NEG over double bits. }
      if TypeIsFloat(IntToTypeKind(IRTk[left])) and
         not TypeIsFloat(IntToTypeKind(ASTTk[node])) then
        ASTTk[node] := IRTk[left];
      Result := IRAppend(IR_NEG, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_ALLOCA:
    begin
      left := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_ALLOCA, left, -1, -1, 0, Ord(tyPointer));
    end;

    AN_FPUMASK:
    begin
      { __pxxGetFPUMask / __pxxSetFPUMask. x86-64 only — the parser already
        refuses the intrinsic elsewhere, and this second guard is what keeps
        the promise that no other backend ever sees IR_FPU_MASK (the same
        arrangement IR_MULHI has for the 32-bit targets). }
      if TargetArch <> TARGET_X86_64 then
        Error('float-exception mask control is x86-64 only '
              + '(feature-float-exception-mask-control)');
      if ASTIVal[node] = 1 then
        left := IRLowerAST(ASTLeft[node])
      else
        left := -1;
      Result := IRAppend(IR_FPU_MASK, left, -1, ASTIVal[node], 0, Ord(tyInteger));
    end;

    AN_NOT:
    begin
      if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
      begin
        { `not v` is Python TRUTHINESS over the payload. The raw 8-byte load
          was the tag, which is non-zero for every typed value, so `not b` was
          False whatever b held. }
        left := IRLowerVariantAsScalar(ASTLeft[node], tyBoolean);
        ASTTk[node] := Ord(tyBoolean);
        Result := IRAppend(IR_NOT, left, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      left := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_NOT, left, -1, -1, 0, ASTTk[node]);
      { A bitwise complement of an UNSIGNED subword type truncates to its width
        (FPC: `not byte(1)` = 254, `not ord('a')` = 158). Every backend emits a
        full-register complement, so mask here in the shared IR — portable to
        all six targets. Signed subwords need nothing: their inputs are already
        sign-extended, so the full-width complement IS the sign-extension of
        the subword result. bug-pascal-not-of-ord-uses-boolean-negation. }
      case IntToTypeKind(ASTTk[node]) of
        tyUInt8:
          Result := IRAppend(IR_BINOP, Result,
                      IRAppend(IR_CONST_INT, -1, -1, -1, $FF, Ord(tyInteger)),
                      Ord(tkAnd), 0, ASTTk[node]);
        tyUInt16:
          Result := IRAppend(IR_BINOP, Result,
                      IRAppend(IR_CONST_INT, -1, -1, -1, $FFFF, Ord(tyInteger)),
                      Ord(tkAnd), 0, ASTTk[node]);
        tyUInt32:
          Result := IRAppend(IR_BINOP, Result,
                      IRAppend(IR_CONST_INT, -1, -1, -1, $FFFFFFFF, Ord(tyInt64)),
                      Ord(tkAnd), 0, ASTTk[node]);
      end;
    end;

    AN_BINOP:
    begin
      { {$MODE DELPHI}: `fp = nil` and `fp = fp2` compare the CALL RESULTS, not
        the addresses — measured against FPC, which does the opposite in
        FPC/OBJFPC mode. To compare addresses in Delphi mode you write `@fp`.
        A comparison never wants the procvar itself, so neither operand is a
        procvar sink. }
      if ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
         (ASTSLen[node] <> PAS_BINOP_ASSIGNED) then
      begin
        ASTLeft[node]  := IRProcVarAutoCall(ASTLeft[node], False);
        ASTRight[node] := IRProcVarAutoCall(ASTRight[node], False);
      end;

      { ORDERING a string against a Char: promote the Char to a 1-char string so
        the pair reaches the lexicographic compare. `=`/`<>` have hand-emitted
        mixed forms in every backend; `<` `<=` `>` `>=` never did, so the pair
        fell through to the ordinary integer compare and compared the string
        HANDLE (a heap pointer) against the char ordinal — always > for a
        non-empty string, always < for an empty one. Silently wrong, and it
        agreed with FPC often enough (nil handle <-> empty string) to look
        right: `'ab' < 'b'` was FALSE where FPC says TRUE
        (bug-p-string-char-relational-compares-lengths).
        Doing it here rather than in each backend's compare emitter fixes every
        target at once — WrapCharToStringExpr is the same `String(c)` desugar
        that `+` concat and the explicit cast already use, so no backend code.
        Pascal only: C compares chars as ints, and NilPy routes str ordering
        through pylib. }
      { A UCS4Char meeting a string in `+` or a comparison converts to its UTF-8
        ENCODING. Without this the kind is ordinal, so `'h' + c` took the
        ARITHMETIC path and produced Chr(104+233) — one wrong byte, silently.
        Handled before the tyChar block below because the wrap differs: a code
        point needs encoding, a byte needs only widening.
        feature-nilpy-text-string-kind }
      if (TTokenKind(ASTIVal[node]) in [tkPlus, tkLt, tkLe, tkGt, tkGe, tkEq, tkNeq]) and
         ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tyUCS4Char) or
          (IntToTypeKind(ASTTk[ASTRight[node]]) = tyUCS4Char)) then
      begin
        if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyUCS4Char) and
           (IntToTypeKind(ASTTk[ASTRight[node]]) in [tyString, tyAnsiString]) then
          ASTLeft[node] := WrapUCS4ToUTF8(ASTLeft[node])
        else if (IntToTypeKind(ASTTk[ASTRight[node]]) = tyUCS4Char) and
                (IntToTypeKind(ASTTk[ASTLeft[node]]) in [tyString, tyAnsiString]) then
          ASTRight[node] := WrapUCS4ToUTF8(ASTRight[node])
        { …and the CHAR pair, which is the one that bites: a ONE-character
          literal is spelled tyChar, so `'h' + c` has two ordinals and took the
          arithmetic path — Chr(104+233), one wrong byte. Both sides must become
          strings: the code point encodes, the byte only widens. }
        else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyUCS4Char) and
                (IntToTypeKind(ASTTk[ASTRight[node]]) = tyChar) then
        begin
          ASTLeft[node] := WrapUCS4ToUTF8(ASTLeft[node]);
          ASTRight[node] := WrapCharToStringExpr(ASTRight[node]);
        end
        else if (IntToTypeKind(ASTTk[ASTRight[node]]) = tyUCS4Char) and
                (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyChar) then
        begin
          ASTRight[node] := WrapUCS4ToUTF8(ASTRight[node]);
          ASTLeft[node] := WrapCharToStringExpr(ASTLeft[node]);
        end;
        { …and re-type the CONCAT node itself. Wrapping the operands is not
          enough: `('h' + c) + 'llo'` left the inner node still claiming tyChar,
          so the outer concat treated a 2-byte result as one byte and the whole
          expression came back 4 bytes instead of 6. Comparisons are excluded —
          their result is boolean, not a string.

          Reached ONLY when an operand really was a tyUCS4Char (the guard on the
          enclosing `if`). An earlier version re-typed on any tkPlus with a
          string operand and so fired for EVERY string concat in every frontend,
          which turned LOLCODE's SMOOSH into an infinite loop — a whole-program
          break from a change that looked local. }
        if TTokenKind(ASTIVal[node]) = tkPlus then
          ASTTk[node] := Ord(tyAnsiString);
      end;

      if (TTokenKind(ASTIVal[node]) in [tkLt, tkLe, tkGt, tkGe]) and
         not CProgramMode and not NilPyUserCode then
      begin
        if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyChar) and
           (IntToTypeKind(ASTTk[ASTRight[node]]) in [tyString, tyAnsiString]) then
          ASTLeft[node] := WrapCharToStringExpr(ASTLeft[node])
        else if (IntToTypeKind(ASTTk[ASTRight[node]]) = tyChar) and
                (IntToTypeKind(ASTTk[ASTLeft[node]]) in [tyString, tyAnsiString]) then
          ASTRight[node] := WrapCharToStringExpr(ASTRight[node]);
      end;

      { Both operand types provable and the pair meaningless: say so now rather
        than letting the runtime helper raise when (and if) the line executes.
        A warning, not an error — see IRPyNumStrClash. }
      { WARN first, then raise — in that order, and from ONE site. The raise arm
        below Exits, so putting it first swallowed the diagnostic for every pair
        it handled: test_nilpy_static_operand_clash counts six provable clashes
        and saw one, the `+` case, which is the only one of the six this arm
        does not claim (bug-n-static-operand-clash-diagnostic-and-guard-test-escaping).
        Combining the two predicates in the condition keeps it to exactly one
        warning per clash — IRPyNumStrClash and IRPyStaticPairUndefined overlap
        on the str-vs-number pairs, so warning inside each arm separately would
        double-report them. }
      if IRPyNumStrClash(node) or IRPyStaticPairUndefined(node) then
        WarnAt(ASTLine[node],
               'Nil Python: operator ''' + IRPyOpSpelling(Integer(ASTIVal[node])) +
               ''' is not defined for ' + IRPyOperandTypeName(ASTLeft[node]) +
               ' and ' + IRPyOperandTypeName(ASTRight[node]) +
               ' — both operand types are provable here, so this raises TypeError if it runs');
      { ...and where the pair is provably undefined, RAISE rather than compute.
        A genuine runtime TypeError via pylib, not a build abort, so
        `try: a - b / except TypeError:` — the normal Python way to probe for
        operator support — still compiles and runs its handler. }
      if IRPyStaticPairUndefined(node) then
      begin
        cpi := FindProc('PyUnsupportedOperandError');
        if cpi < 0 then Error('Nil Python: pylib (PyUnsupportedOperandError) not loaded');
        Result := IRAppendCall(cpi, -1, -1, ASTTk[node]);
        Exit;
      end;
      { Fold a compile-time concat of two string/char literals (`'a' + 'b'`) to a
        single interned literal — constant folding, target-independent. Besides
        avoiding a runtime concat, this is the correctness fix for
        bug-string-literal-concat-compare-segfault: a literal-concat appearing as
        a comparison operand (`x = 'a' + 'b'`) otherwise fed the runtime
        string-concat result into the hand-emitted string-compare path and
        crashed. A folded single literal behaves exactly like writing the literal
        on one line (the known-good form), so assignment and comparison agree.
        ESP needs it regardless (no frozen-string concat path). }
      if (Integer(ASTIVal[node]) = Ord(tkPlus)) and
         IsConstStrLitNode(ASTLeft[node]) and IsConstStrLitNode(ASTRight[node]) then
      begin
        foldStr := ConstStrLitValue(ASTLeft[node]) + ConstStrLitValue(ASTRight[node]);
        foldOff := TokCharLen;
        if TokCharLen + Length(foldStr) > STRING_CAP then Error('token char pool overflow');
        for foldK := 1 to Length(foldStr) do
        begin
          TokChars[TokCharLen] := foldStr[foldK];
          Inc(TokCharLen);
        end;
        { Tag the folded result tyString — a plain one-line literal's kind — not
          ASTTk[node]. The surrounding expression may be tyAnsiString (e.g. a
          Concat-synthesised `+` chain in managed mode); emitting the literal as
          tyAnsiString would make downstream managed paths treat this static
          literal pointer as a heap handle and release it -> crash at scope exit
          (regressed test_concat_intrinsic). As tyString it behaves exactly like
          any other string literal and is coerced to managed on use. }
        Result := IRAppend(IR_CONST_STR, foldOff, Length(foldStr), -1, 0, Ord(tyString));
        Exit;
      end;

      { Short-circuit boolean and/or (FPC default {$B-}): evaluate the right
        operand only when the left has not already decided the result. The parser
        tags a logical (both-operands-boolean) and/or with ASTTk = tyBoolean;
        bitwise integer and/or keep an ordinal type and fall through to the
        unconditional IR_BINOP below. The result is held in a temp (a local when
        inside a proc, so recursion stays reentrant); the right operand's IR is
        lowered AFTER the conditional jump, so it sits past the branch in the
        linear statement stream and is skipped at runtime. }
      if ((Integer(ASTIVal[node]) = Ord(tkAnd)) or (Integer(ASTIVal[node]) = Ord(tkOr))) and
         (IntToTypeKind(ASTTk[node]) = tyBoolean) then
      begin
        varIdx := AllocVar('', tyBoolean);
        endLabel := IRNewLabel;
        left := IRLowerAST(ASTLeft[node]);
        IRAppend(IR_STORE_SYM, varIdx, left, -1, 0, Ord(tyBoolean));
        value := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkAnd) then
        begin
          { left false -> skip right (result already false) }
          IRAppend(IR_JUMP_IF_FALSE, endLabel, value, -1, 0, 0);
          right := IRLowerAST(ASTRight[node]);
          IRAppend(IR_STORE_SYM, varIdx, right, -1, 0, Ord(tyBoolean));
          IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
        end
        else
        begin
          { left true -> skip right (result already true). Only JUMP_IF_FALSE
            exists, so branch to an "evaluate right" label when left is false,
            else jump straight to the end. }
          elseLabel := IRNewLabel;
          IRAppend(IR_JUMP_IF_FALSE, elseLabel, value, -1, 0, 0);
          IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
          IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
          right := IRLowerAST(ASTRight[node]);
          IRAppend(IR_STORE_SYM, varIdx, right, -1, 0, Ord(tyBoolean));
          IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
        end;
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      { Python's `s * n` repeats the text; Pascal has no such operator, so the
        string's HANDLE was multiplied as an integer and the result printed as
        a pointer (bug-a-nilpy-string-repeat-returns-a-pointer). Either operand
        order. }
      { `v * n` with a VARIANT operand: a string payload REPEATS and a numeric
        one MULTIPLIES, which cannot be decided here -- pymul_v dispatches on
        the tag. (An earlier attempt guessed "variant operand of * is a string"
        and was reverted; it miscompiled v * 2 on an int.) }
      if PyProgramMode and (Integer(ASTIVal[node]) = Ord(tkStar)) and
         ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
          (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant)) then
      begin
        cpi := FindProc('pymul_v');
        if cpi < 0 then Error('Nil Python: pymul_v (pylib) not loaded');
        left := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyVariant));
        right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyVariant));
        IRB[first] := last;
        ASTTk[node] := Ord(tyVariant);
        Result := IRAppendCall(cpi, first, -1, Ord(tyVariant));
        Exit;
      end;
      if PyProgramMode and (Integer(ASTIVal[node]) = Ord(tkStar)) and
         (IRNodeIsPyStr(ASTLeft[node]) <> IRNodeIsPyStr(ASTRight[node])) then
      begin
        if IRNodeIsPyStr(ASTLeft[node]) then
        begin argVal := ASTLeft[node]; item := ASTRight[node]; end
        else
        begin argVal := ASTRight[node]; item := ASTLeft[node]; end;
        { A non-integer repeat count is a TypeError in Python, and pystr_repeat
          takes an Int64: a DOUBLE arrived as its raw bit pattern, so `2.5 *
          "ab"` asked for ~4.6e18 copies and the program never came back — a
          hang, which an ordinary test run cannot even diff
          (bug-nilpy-float-times-string-hangs). Hand those to pymul_v, which
          already raises the right TypeError, instead of bounding a count that
          should never have been accepted. }
        { A PROMOTABLE INT count is an integer count, not a "non-integer" one:
          promo is deliberately not reported by TypeIsOrdinal, so
          `"ab" * <wide literal>` fell into the pymul_v arm meant for floats and
          produced an EMPTY string — silent. It narrows below instead, like any
          other integer count. }
        if (not TypeIsOrdinal(IntToTypeKind(ASTTk[item]))) and
           (not TypeIsPromoInt(IntToTypeKind(ASTTk[item]))) then
        begin
          cpi := FindProc('pymul_v');
          if cpi < 0 then Error('Nil Python: pymul_v (pylib) not loaded');
          left := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
          first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyVariant));
          right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
          last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyVariant));
          IRB[first] := last;
          ASTTk[node] := Ord(tyVariant);
          Result := IRAppendCall(cpi, first, -1, Ord(tyVariant));
          Exit;
        end;
        cpi := FindProc('pystr_repeat');
        if cpi < 0 then Error('Nil Python: pystr_repeat (pylib) not loaded');
        left := IRLowerCallArg(cpi, 0, argVal, Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, ASTTk[argVal]);
        { IRLowerCallArg, not a raw IRLowerAST: parameter 1 is an Int64, so a
          PROMO count narrows through PXXPromoToInt64Wrap there. Lowered raw it
          would hand pystr_repeat the slot ADDRESS as the count. }
        right := IRLowerCallArg(cpi, 1, item, Procs[cpi].Params[1].IsRef);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyInt64));
        IRB[first] := last;
        ASTTk[node] := Ord(tyAnsiString);
        Result := IRAppendCall(cpi, first, -1, Ord(tyAnsiString));
        Exit;
      end;
      { Python compares CONTAINERS by contents, not identity. `xs == ys` on two
        lists was a pointer compare and answered False for equal lists
        (bug-a-nilpy-container-equality-compares-identity). pylib's PyVarEq
        already compares strings by content, so the element rule is settled. }
      { Two RANGES compare by the SEQUENCE they represent, not by handle — so
        range(0) == range(2, 2, 3) is True and an equal pair built separately
        is too. Same failure the list rule above fixes, and it is checked first
        because a range is a class handle like any other and would otherwise
        fall into the pointer compare. }
      if PyProgramMode and (ASTSLen[node] <> PY_BINOP_IDENTITY) and
         ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
         (FindUClass('TPyRange') >= 0) and
         (ResolveNodeRec(ASTLeft[node]) = REC_UCLASS_BASE + FindUClass('TPyRange')) and
         (ResolveNodeRec(ASTRight[node]) = REC_UCLASS_BASE + FindUClass('TPyRange')) then
      begin
        cpi := FindProc('pyrange_eq');
        if cpi < 0 then Error('Nil Python: pyrange_eq (pylib) not loaded');
        left := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        right := IRLowerAST(ASTRight[node]);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyClass));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkNeq) then
          Result := IRAppend(IR_NOT, Result, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      if PyProgramMode and (ASTSLen[node] <> PY_BINOP_IDENTITY) and
         ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
         (IRNodePyListRec(ASTLeft[node]) >= 0) and
         (IRNodePyListRec(ASTLeft[node]) = IRNodePyListRec(ASTRight[node])) then
      begin
        cpi := FindProc('pylist_eq');
        if cpi < 0 then Error('Nil Python: pylist_eq (pylib) not loaded');
        left := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        right := IRLowerAST(ASTRight[node]);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyClass));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkNeq) then
          Result := IRAppend(IR_NOT, Result, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      { ORDERING two lists is LEXICOGRAPHIC in Python, and on this path it was a
        raw handle compare — so the answer came from the two objects' HEAP
        ADDRESSES and ignored their contents entirely. `[9,9] < [1,1]` answered
        True. It looked correct in the corpus only because a list literal
        written first is allocated first, so content order and address order
        usually coincide; `test_nilpy_mixed_type_operands`' `[1] < [1, 0]`
        passes for exactly that accidental reason
        (bug-nilpy-list-ordering-compares-heap-addresses).

        pylib's `pylist_cmp` already implements the real rule (element by
        element, then the shorter sequence first) and returns -1/0/1, so this is
        wiring — the same wiring `==`/`!=` got just above via pylist_eq, which
        is why equality was right while ordering was not. Compare its result
        against 0 with the SOURCE operator, which keeps <, <=, > and >= correct
        including at equality. }
      if PyProgramMode and
         ((Integer(ASTIVal[node]) = Ord(tkLt)) or (Integer(ASTIVal[node]) = Ord(tkLe)) or
          (Integer(ASTIVal[node]) = Ord(tkGt)) or (Integer(ASTIVal[node]) = Ord(tkGe))) and
         (IRNodePyListRec(ASTLeft[node]) >= 0) and
         (IRNodePyListRec(ASTLeft[node]) = IRNodePyListRec(ASTRight[node])) then
      begin
        cpi := FindProc('pylist_cmp');
        if cpi < 0 then Error('Nil Python: pylist_cmp (pylib) not loaded');
        left := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        right := IRLowerAST(ASTRight[node]);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyClass));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyInt64));
        Result := IRAppend(IR_BINOP, Result,
                           IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyInt64)),
                           Integer(ASTIVal[node]), 0, Ord(tyBoolean));
        Exit;
      end;
      { BYTES order lexicographically too, and had the identical hole: two
        statically-typed TPyBytes lowered to a raw handle compare, so
        `b"zz" < b"aa"` answered True off the heap addresses. `==` was already
        right (it consults contents on another path), which is exactly the
        asymmetry the list half of this bug had — equality correct, ordering
        answering from allocation order. Same wiring as the list arm above, with
        the new pybytes_cmp providing the -1/0/1 (bug-nilpy-list-ordering-
        compares-heap-addresses, the bytes half its Scope section asked to
        check). }
      if PyProgramMode and
         ((Integer(ASTIVal[node]) = Ord(tkLt)) or (Integer(ASTIVal[node]) = Ord(tkLe)) or
          (Integer(ASTIVal[node]) = Ord(tkGt)) or (Integer(ASTIVal[node]) = Ord(tkGe))) and
         (IRNodePyBytesRec(ASTLeft[node]) >= 0) and
         (IRNodePyBytesRec(ASTLeft[node]) = IRNodePyBytesRec(ASTRight[node])) then
      begin
        cpi := FindProc('pybytes_cmp');
        if cpi < 0 then Error('Nil Python: pybytes_cmp (pylib) not loaded');
        left := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        right := IRLowerAST(ASTRight[node]);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyClass));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyInt64));
        Result := IRAppend(IR_BINOP, Result,
                           IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyInt64)),
                           Integer(ASTIVal[node]), 0, Ord(tyBoolean));
        Exit;
      end;
      { Dicts compare by CONTENTS too, and for the same reason — this was still
        a pointer compare, so `{"k": 1} == {"k": 1}` answered False and
        `if cfg == defaults:` never fired
        (bug-nilpy-dict-equality-compares-identity). pydict_eq ignores
        insertion order, which is what Python's rule requires. }
      if PyProgramMode and (ASTSLen[node] <> PY_BINOP_IDENTITY) and
         ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
         (IRNodePyDictRec(ASTLeft[node]) >= 0) and
         (IRNodePyDictRec(ASTLeft[node]) = IRNodePyDictRec(ASTRight[node])) then
      begin
        cpi := FindProc('pydict_eq');
        if cpi < 0 then Error('Nil Python: pydict_eq (pylib) not loaded');
        left := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        right := IRLowerAST(ASTRight[node]);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyClass));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkNeq) then
          Result := IRAppend(IR_NOT, Result, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      { …and a list against a DYNAMICALLY-TYPED value: `key == cached_key`
        where the cache starts as None. Boxing a class operand into a variant
        for the scalar comparison below is not supported and reported as
        "Variant operand: this scalar type not yet supported", so the whole
        ordinary-Python idiom of caching a tuple against None failed to
        compile. A list never equals a non-list, which is the rule pylib's
        pylist_eq_v applies. }
      if PyProgramMode and (ASTSLen[node] <> PY_BINOP_IDENTITY) and
         ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
         (((IRNodePyListRec(ASTLeft[node]) >= 0) and
           (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant)) or
          ((IRNodePyListRec(ASTRight[node]) >= 0) and
           (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant))) then
      begin
        cpi := FindProc('pylist_eq_v');
        if cpi < 0 then Error('Nil Python: pylist_eq_v (pylib) not loaded');
        if IRNodePyListRec(ASTLeft[node]) >= 0 then
        begin
          lstNode := ASTLeft[node]; varNode := ASTRight[node];
        end
        else
        begin
          lstNode := ASTRight[node]; varNode := ASTLeft[node];
        end;
        { the variant parameter is `const`, i.e. passed by REFERENCE — lower it
          through IRLowerCallArg with the signature's own IsRef, as the
          neighbouring pylib calls do, or the callee reads the value as a
          pointer and dereferences garbage }
        left := IRLowerCallArg(cpi, 0, lstNode, Procs[cpi].Params[0].IsRef);
        right := IRLowerCallArg(cpi, 1, varNode, Procs[cpi].Params[1].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyClass));
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyVariant));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkNeq) then
          Result := IRAppend(IR_NOT, Result, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      { Python's `//` and `%` FLOOR; Pascal's div/mod TRUNCATE. Same tokens, so
        the language decides. Route both to the pylib helpers, which correct
        the quotient and the remainder TOGETHER -- fixing one alone would break
        the identity a = (a//b)*b + (a%b) for mixed signs.
        (bug-a-nilpy-floordiv-and-modulo-wrong-for-negatives.) }
      if PyProgramMode and
         ((Integer(ASTIVal[node]) = Ord(tkDiv)) or (Integer(ASTIVal[node]) = Ord(tkMod))) and
         ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
          (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant) or
          { a provable str-vs-number pair too, so `3 // "ab"` raises instead of
            dividing by a handle — see the block below and IRPyNumStrClash }
          IRPyNumStrClash(node)) then
      begin
        { A VARIANT operand -- which a for-in loop variable always is. The
          payload's type is unknown here, so the helper dispatches on the tag
          at runtime; without this the most ordinary Python loop
          (`for a in xs: a // 2`) silently kept Pascal's truncating result. The
          scalar-to-Variant boxing in IRLowerCallArg handles a mixed pair. }
        if Integer(ASTIVal[node]) = Ord(tkDiv) then
          fdName := 'pyfloordiv_v'
        else
          fdName := 'pyfloormod_v';
        cpi := FindProc(fdName);
        if cpi < 0 then Error('Nil Python: ' + fdName + ' (pylib) not loaded');
        left := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyVariant));
        right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyVariant));
        IRB[first] := last;
        ASTTk[node] := Ord(tyVariant);
        Result := IRAppendCall(cpi, first, -1, Ord(tyVariant));
        Exit;
      end;
      { The REST of the arithmetic and ordering family over a VARIANT operand.
        `*`, `//` and `%` got their tag dispatch above one bug at a time; `-`,
        `/` and the four orderings never did, so the operand's HANDLE was used
        as a number and `3 - "ab"` returned an address difference — a different
        plausible-looking value on every run
        (bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math). The
        helpers coerce through pyvar_to_int / pyvar_to_float, which RAISE
        TypeError for a tag Python will not accept, so the check is the
        coercion and costs nothing extra on the paths that were already correct.

        `=` / `<>` are NOT here: pyeq_v is value equality across tags and the
        container-equality blocks above already route them. `+` is not here
        either — it needs a str/list concat arm pyadd_v does not have yet, and
        is tracked separately. }
      if PyProgramMode and
         ((Integer(ASTIVal[node]) = Ord(tkMinus)) or
          (Integer(ASTIVal[node]) = Ord(tkSlash)) or
          (Integer(ASTIVal[node]) = Ord(tkPlus)) or
          (Integer(ASTIVal[node]) = Ord(tkLt)) or (Integer(ASTIVal[node]) = Ord(tkLe)) or
          (Integer(ASTIVal[node]) = Ord(tkGt)) or (Integer(ASTIVal[node]) = Ord(tkGe))) and
         ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
          (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant) or
          { ...and the STATICALLY provable clash, which reaches here with two
            ordinary scalar types and would otherwise compile to a raw IR_BINOP
            over the str's handle. The warning above says so at compile time;
            this makes the run agree with it. }
          IRPyNumStrClash(node) or
          { ...and a CHAR ordered against a STRING, which compared an ordinal
            with an address -- see IRPyCharStrOrderClash. Ordering operators
            only; `=`/`<>` already content-compare correctly. }
          (IRPyCharStrOrderClash(node) and
           ((Integer(ASTIVal[node]) = Ord(tkLt)) or (Integer(ASTIVal[node]) = Ord(tkLe)) or
            (Integer(ASTIVal[node]) = Ord(tkGt)) or (Integer(ASTIVal[node]) = Ord(tkGe))))) then
      begin
        { `+` is in this list too: pyadd_v concatenates two strs and two lists
          and adds two numbers, and coerces through pyvar_to_int otherwise, so
          a mixed pair raises instead of returning one operand. It was the last
          arm still answering `3 + "ab"` with "ab". }
        fdTk := tyBoolean;
        if Integer(ASTIVal[node]) = Ord(tkPlus) then
        begin
          if ASTSLen[node] = PY_BINOP_AUGADD then fdName := 'pyaugadd_v'
          else fdName := 'pyadd_v';
          fdTk := tyVariant;
        end
        else if Integer(ASTIVal[node]) = Ord(tkMinus) then
        begin fdName := 'pysub_v'; fdTk := tyVariant; end
        else if Integer(ASTIVal[node]) = Ord(tkSlash) then
        begin fdName := 'pytruediv_v'; fdTk := tyVariant; end
        else if Integer(ASTIVal[node]) = Ord(tkLt) then fdName := 'pylt_v'
        else if Integer(ASTIVal[node]) = Ord(tkLe) then fdName := 'pyle_v'
        else if Integer(ASTIVal[node]) = Ord(tkGt) then fdName := 'pygt_v'
        else fdName := 'pyge_v';
        cpi := FindProc(fdName);
        if cpi < 0 then Error('Nil Python: ' + fdName + ' (pylib) not loaded');
        { `const v: Variant` is by REFERENCE — lower through IRLowerCallArg with
          the signature's own IsRef, as the neighbouring pylib calls do, or the
          callee dereferences the value as a pointer. IRLowerCallArg also boxes
          a scalar operand of a mixed pair. }
        left := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyVariant));
        right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyVariant));
        IRB[first] := last;
        ASTTk[node] := Ord(fdTk);
        Result := IRAppendCall(cpi, first, -1, Ord(fdTk));
        Exit;
      end;
      { Python's `/` is TRUE division: always a float, and ZeroDivisionError on
        a zero divisor. Plain IEEE division gave neither — `3 / 0` produced a
        saturated Int64 that the large-float formatter then printed as garbage
        BYTES on stdout, and no `except` could see it
        (bug-nilpy-runtime-raised-errors-bypass-try-except).

        BOTH operands must be numbers. `Path("a") / "b"` is pathlib's join
        operator, and routing that here compiled a path handle as a Double and
        segfaulted — caught by test_nilpy_pathlib, which is exactly what that
        test is for.

        Routed through a helper, so every NUMERIC NilPy `/` is now a call: a real cost,
        accepted because the alternative is a silently wrong answer, and an
        inline zero test plus a raise is the only other way to get the
        exception out. Promotable-int operands are left on the old path — their
        rvalue is a frame SLOT ADDRESS (project_promotable_int_stages123), so
        handing one to a Double parameter would pass the address as a number. }
      if PyProgramMode and (Integer(ASTIVal[node]) = Ord(tkSlash)) and
         TypeIsPyNumeric(IntToTypeKind(ASTTk[ASTLeft[node]])) and
         TypeIsPyNumeric(IntToTypeKind(ASTTk[ASTRight[node]])) and
         (not TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]]))) and
         (not TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]]))) then
      begin
        cpi := FindProc('pytruediv_f');
        if cpi < 0 then Error('Nil Python: pytruediv_f (pylib) not loaded');
        left := IRLowerCallArg(cpi, 0, ASTLeft[node], False);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(tyDouble));
        right := IRLowerCallArg(cpi, 1, ASTRight[node], False);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(tyDouble));
        IRB[first] := last;
        ASTTk[node] := Ord(tyDouble);
        Result := IRAppendCall(cpi, first, -1, Ord(tyDouble));
        Exit;
      end;
      { ...but NOT when the result is an ARBITRARY-PRECISION int. pyfloordiv_i /
        pyfloormod_i take and return Int64, while the parser typed this node
        tyPromoInt64 (TypeDivideResult keeps promo) — so an enclosing promo
        operator read the returned VALUE as a slot ADDRESS and dereferenced it:
        `(o % 26) + 1` segfaulted in SlotTag for any o past Int64, while the
        same `%` as a whole statement was fine because the assignment path
        emits the helper directly. Falling through reaches the promo binop
        branch below, whose PXXPromoFloorDiv/FloorMod carry Python's sign rule.
        Both operands are checked, not just the node, so a promo operand cannot
        be narrowed into the Int64 helper either. }
      if PyProgramMode and
         ((Integer(ASTIVal[node]) = Ord(tkDiv)) or (Integer(ASTIVal[node]) = Ord(tkMod))) and
         (not TypeIsPromoInt(IntToTypeKind(ASTTk[node]))) and
         (not TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]]))) and
         (not TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]]))) then
      begin
        { Decide by the OPERANDS, not the node: `x // y` on floats is still
          tkDiv, which Pascal only ever spells for integers, so the node's own
          type kind is not float and would have picked the integer helper and
          reinterpreted the double bits as an int. }
        if IRNodeIsFloatThroughNeg(ASTLeft[node]) or
           IRNodeIsFloatThroughNeg(ASTRight[node]) then
        begin
          if Integer(ASTIVal[node]) = Ord(tkDiv) then
            fdName := 'pyfloordiv_f'
          else
            fdName := 'pyfloormod_f';
          fdTk := tyDouble;
          { tkDiv is an integer-only spelling in Pascal, so the parser left the
            node integer-typed. Consumers (write, assignment) read ASTTk, and
            would print the double's BITS. }
          ASTTk[node] := Ord(tyDouble);
        end
        else
        begin
          if Integer(ASTIVal[node]) = Ord(tkDiv) then
            fdName := 'pyfloordiv_i'
          else
            fdName := 'pyfloormod_i';
          fdTk := tyInt64;
        end;
        cpi := FindProc(fdName);
        if cpi < 0 then Error('Nil Python: ' + fdName + ' (pylib) not loaded');
        left := IRLowerCallArg(cpi, 0, ASTLeft[node], False);
        first := IRAppend(IR_ARG, left, -1, -1, 0, Ord(fdTk));
        right := IRLowerCallArg(cpi, 1, ASTRight[node], False);
        last := IRAppend(IR_ARG, right, -1, -1, 0, Ord(fdTk));
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, Ord(fdTk));
        Exit;
      end;
      { Operator overloading: a <op> b on a class/record operand resolves to a
        call to the registered operator proc (lhs, rhs), mirroring the direct
        backend. Args are passed by value (rdi=lhs, rsi=rhs). }
      cpi := FindOpOverload2(Integer(ASTIVal[node]), ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]),
                             ASTTk[ASTRight[node]], ResolveNodeRec(ASTRight[node]));
      if cpi >= 0 then
      begin
        left  := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, ASTTk[ASTLeft[node]]);
        right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
        last  := IRAppend(IR_ARG, right, -1, -1, 0, ASTTk[ASTRight[node]]);
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, ASTTk[node]);
      end
      else if ((NodeDynDepth(ASTLeft[node]) > 0) or (NodeDynDepth(ASTRight[node]) > 0)) and
              ((Integer(ASTIVal[node]) = Ord(tkPlus)) or (Integer(ASTIVal[node]) = Ord(tkMinus)) or
               (Integer(ASTIVal[node]) = Ord(tkStar)) or (Integer(ASTIVal[node]) = Ord(tkDiv))) then
        { An arithmetic operator with a dynamic-array operand otherwise fell through
          to the integer/pointer IR_BINOP, which added the two array handles and
          produced a wild pointer -> runtime SIGSEGV (bug-dynarray-concat-silent-
          miscompile). Reject it honestly. `a + b` array concat is a future feature
          (feature-dynarray-insert-delete / feature-copy-intrinsic). }
        Error('arithmetic operator not supported for dynamic arrays (`a + b` array concatenation is not implemented)')
      else if (not CProgramMode) and
              ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord) or
               (IntToTypeKind(ASTTk[ASTRight[node]]) = tyRecord)) and
              ((Integer(ASTIVal[node]) = Ord(tkPlus)) or (Integer(ASTIVal[node]) = Ord(tkMinus)) or
               (Integer(ASTIVal[node]) = Ord(tkStar)) or (Integer(ASTIVal[node]) = Ord(tkSlash)) or
               (Integer(ASTIVal[node]) = Ord(tkDiv)) or (Integer(ASTIVal[node]) = Ord(tkMod))) then
        { An arithmetic operator on a record operand with no registered overload
          otherwise fell through to the scalar IR_BINOP, adding the records'
          first qwords and producing garbage (or a wild pointer copy) at run
          time. Reject it honestly — comparisons are left alone (method-pointer
          `=`/`<>` are legitimate record compares), and C is exempt (struct
          pointer/array arithmetic tags operands tyRecord legitimately). }
        Error('no operator overload found for record operands (operator not declared, or its unit not compiled?)')
      else if ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
              (NodeIsInterface(ASTLeft[node]) or NodeIsInterface(ASTRight[node])) then
      begin
        { Interface identity: an interface value IS the instance pointer, so this
          is a plain pointer compare. `iface = nil` compares against 0. }
        left := IRIntfInstanceWord(ASTLeft[node]);
        right := IRIntfInstanceWord(ASTRight[node]);
        Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, Ord(tyBoolean));
      end
      else if (ASTIVal[node] <> Ord(tkIn)) and
              ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tySet) or
               (IntToTypeKind(ASTTk[ASTRight[node]]) = tySet)) then
      begin
        left := IRLowerAST(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        if (ASTIVal[node] = Ord(tkEq)) or (ASTIVal[node] = Ord(tkNeq)) or
           (ASTIVal[node] = Ord(tkLt)) or (ASTIVal[node] = Ord(tkLe)) or
           (ASTIVal[node] = Ord(tkGt)) or (ASTIVal[node] = Ord(tkGe)) then
          Result := IRAppend(IR_SET_CMP, left, right, Integer(ASTIVal[node]), 0, Ord(tyBoolean))
        else
        begin
          BSSSize := AlignTo(BSSSize, 8);
          idx := BSSSize;
          Inc(BSSSize, 32);
          Result := IRAppend(IR_SET_BINOP, left, right, Integer(ASTIVal[node]), idx, Ord(tySet));
        end;
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
              (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant) then
      begin
        { Variant operand: make both sides variant addresses (box a scalar side
          into a temp), then IR_VAR_BINOP. Comparison -> Boolean in rax;
          arithmetic -> a Variant result in a fresh BSS temp (addr in rax). }
        { IRVariantAddr, not IRLowerAddress: a variant RVALUE — a nested
          variant BINOP such as the `2 * v` in `total = total + 2 * v` — has no
          address, and taking one emitted IR_UNSUPPORTED for a plain
          accumulation loop over for-in variables
          (bug-a-nilpy-int-times-variant-in-sum-not-lowered). The helper parks
          such a value in a variant temp first. }
        if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
          left := IRVariantAddr(ASTLeft[node])
        else if IsWideIntLit(ASTLeft[node]) or IsWideNegLit(ASTLeft[node]) or
                TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) then
          { a wide literal / promo-typed operand: IR_VAR_BOX would box the
            WRAPPED machine int — route through the promo runtime instead so
            an over-Int64 value keeps its exact reading (VT_PROMO_INT64) }
          left := IRPromoBoxedVariantAddr(ASTLeft[node])
        else
        begin
          { box temp is a routine local (per-call/thread slot), not a shared
            global — consumed within this comparison, never outlives the frame
            (bug-variant-boxing-temp-global-shared). }
          value := AllocVar('', tyVariant);
          left := IRAppend(IR_VAR_BOX, IRAppend(IR_LEA, value, -1, -1, 0, Ord(tyPointer)),
                           IRLowerAST(ASTLeft[node]), Ord(IntToTypeKind(ASTTk[ASTLeft[node]])), 0, Ord(tyVariant));
        end;
        if IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant then
          right := IRVariantAddr(ASTRight[node])
        else if IsWideIntLit(ASTRight[node]) or IsWideNegLit(ASTRight[node]) or
                TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]])) then
          right := IRPromoBoxedVariantAddr(ASTRight[node])
        else
        begin
          { box temp is a routine local (per-call/thread slot), not a shared
            global (bug-variant-boxing-temp-global-shared). }
          value := AllocVar('', tyVariant);
          right := IRAppend(IR_VAR_BOX, IRAppend(IR_LEA, value, -1, -1, 0, Ord(tyPointer)),
                            IRLowerAST(ASTRight[node]), Ord(IntToTypeKind(ASTTk[ASTRight[node]])), 0, Ord(tyVariant));
        end;
        item := Integer(ASTIVal[node]);
        { A variant may hold a PROMOTABLE INT whose value does not fit 64 bits.
          Its payload is then a managed string, and the ordinary variant binop
          reads a payload as an integer — `v + w` returned pointer arithmetic, a
          silent wrong answer. Try the promo helper first and fall back to the
          existing path when neither side is promo-tagged, so ordinary variant
          semantics stay exactly where they live (per-backend codegen) instead
          of being reimplemented and drifting.

          Both operand ADDRESSES are parked in pointer temps first: an IR value
          node is a SUBTREE and referencing it twice RE-EMITS it, which for a
          boxed operand would evaluate the source expression a second time. }
        if FindProc('PXXPromoVarArithTry') >= 0 then
        begin
          promoSym := AllocVar('', tyPointer);
          IRAppend(IR_STORE_SYM, promoSym, left, -1, 0, Ord(tyPointer));
          left := IRAppend(IR_LOAD_SYM, promoSym, -1, -1, 0, Ord(tyPointer));
          promoSym := AllocVar('', tyPointer);
          IRAppend(IR_STORE_SYM, promoSym, right, -1, 0, Ord(tyPointer));
          right := IRAppend(IR_LOAD_SYM, promoSym, -1, -1, 0, Ord(tyPointer));
        end;
        if (item = Ord(tkEq)) or (item = Ord(tkNeq)) or (item = Ord(tkLt)) or
           (item = Ord(tkLe)) or (item = Ord(tkGt)) or (item = Ord(tkGe)) then
        begin
          promoOp := 0;
          if item = Ord(tkEq) then promoOp := 1
          else if item = Ord(tkNeq) then promoOp := 2
          else if item = Ord(tkLt) then promoOp := 3
          else if item = Ord(tkLe) then promoOp := 4
          else if item = Ord(tkGt) then promoOp := 5
          else if item = Ord(tkGe) then promoOp := 6;
          if FindProc('PXXPromoVarCmpTry') < 0 then
            Result := IRPyVarEqFallback(left, right, item, node)
          else
          begin
            { r: 0 = not handled, 1 = False, 2 = True }
            promoSym := AllocVar('', tyInteger);
            IRAppend(IR_STORE_SYM, promoSym,
                     IRPromoCall3('PXXPromoVarCmpTry', left, right,
                                  IRAppend(IR_CONST_INT, -1, -1, -1, promoOp, Ord(tyInteger)),
                                  tyInteger), -1, 0, Ord(tyInteger));
            varIdx := AllocVar('', tyBoolean);
            elseLabel := IRNewLabel;
            endLabel := IRNewLabel;
            IRAppend(IR_JUMP_IF_FALSE, elseLabel,
                     IRAppend(IR_LOAD_SYM, promoSym, -1, -1, 0, Ord(tyInteger)), -1, 0, 0);
            IRAppend(IR_STORE_SYM, varIdx,
                     IRAppend(IR_BINOP,
                              IRAppend(IR_LOAD_SYM, promoSym, -1, -1, 0, Ord(tyInteger)),
                              IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
                              Ord(tkMinus), 0, Ord(tyInteger)), -1, 0, Ord(tyBoolean));
            IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
            IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
            IRAppend(IR_STORE_SYM, varIdx,
                     IRPyVarEqFallback(left, right, item, node),
                     -1, 0, Ord(tyBoolean));
            IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
            Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
          end;
        end
        else
        begin
          BSSSize := AlignTo(BSSSize, 8);
          idx := BSSSize;
          Inc(BSSSize, 16);
          promoOp := 0;
          if item = Ord(tkPlus) then promoOp := 1
          else if item = Ord(tkMinus) then promoOp := 2
          else if item = Ord(tkStar) then promoOp := 3
          else if item = Ord(tkDiv) then promoOp := 4
          else if item = Ord(tkMod) then promoOp := 5
          else if item = Ord(tkAnd) then promoOp := 6
          else if item = Ord(tkOr) then promoOp := 7
          else if item = Ord(tkXor) then promoOp := 8
          { shl/shr through the promo runtime are NilPy-only: the runtime
            handles them even for two plain VT_INT64 operands (Python `1 << 64`
            promotes; Python >> is arithmetic, the native op is logical). A
            Pascal Variant shl keeps the native wrapping semantics. }
          else if (item = Ord(tkShl)) and PyProgramMode then promoOp := 9
          else if (item = Ord(tkShr)) and PyProgramMode then promoOp := 10;
          if (promoOp = 0) or (FindProc('PXXPromoVarArithTry') < 0) then
            Result := IRAppend(IR_VAR_BINOP, left, right, item, idx, Ord(tyVariant))
          else
          begin
            varIdx := AllocVar('', tyVariant);
            promoDst := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
            elseLabel := IRNewLabel;
            endLabel := IRNewLabel;
            IRAppend(IR_JUMP_IF_FALSE, elseLabel,
                     IRPromoCall4('PXXPromoVarArithTry', promoDst, left, right,
                                  IRAppend(IR_CONST_INT, -1, -1, -1, promoOp, Ord(tyInteger)),
                                  tyInteger), -1, 0, 0);
            IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
            IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
            IRAppend(IR_VAR_STORE, IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer)),
                     IRAppend(IR_VAR_BINOP, left, right, item, idx, Ord(tyVariant)),
                     Ord(tyVariant), 0, Ord(tyVariant));
            IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
            Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
            IRTk[Result] := Ord(tyVariant);
          end;
        end;
      end
      else
      begin
        if (ASTIVal[node] = Ord(tkMinus)) and
           IRNodePointerBase(ASTLeft[node]) and
           IRNodePointerBase(ASTRight[node]) then
        begin
          { Pointer difference `p - q` = (address_p - address_q) / sizeof(element)
            (C ptrdiff). Both operands are pointers; subtract addresses then divide
            by the element stride.

            Typed tyNativeInt, NOT tyInt64: `ptrdiff_t` is POINTER-WIDTH, so it
            is 8 bytes on a 64-bit target and 4 on ILP32. The hardcoded tyInt64
            made the node claim 8 bytes everywhere, and the variadic push
            believes the node's tag — so on i386/arm32 `printf("%d %d", p-q, 7)`
            pushed 8 bytes for a 4-byte value and EVERY later argument read one
            slot low: it printed `3 0`. The first value still came out right,
            which is what made it look like a library bug (three crtl string
            functions were the prime suspects).
            tyNativeInt is signed and pointer-width, so 64-bit codegen is
            unchanged and 32-bit gets the 4-byte push and a 32-bit divide.
            bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit }
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_BINOP, left, right, Ord(tkMinus), 0, Ord(tyNativeInt));
          elemSize := IRPointerStride(ASTLeft[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyNativeInt));
            { tkDiv = integer division (tkSlash is the float `/` path) }
            Result := IRAppend(IR_BINOP, Result, item, Ord(tkDiv), 0, Ord(tyNativeInt));
          end;
        end
        else if ((ASTIVal[node] = Ord(tkPlus)) or (ASTIVal[node] = Ord(tkMinus))) and
           IRNodePointerBase(ASTLeft[node]) and
           TypeIsOrdinal(IntToTypeKind(ASTTk[ASTRight[node]])) then
        begin
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          elemSize := IRPointerStride(ASTLeft[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyInteger));
            right := IRAppend(IR_BINOP, right, item, Ord(tkStar), 0, Ord(tyInteger));
          end;
          Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, Ord(tyPointer));
        end
        else if (ASTIVal[node] = Ord(tkPlus)) and
                TypeIsOrdinal(IntToTypeKind(ASTTk[ASTLeft[node]])) and
                IRNodePointerBase(ASTRight[node]) then
        begin
          left := IRLowerAST(ASTRight[node]);
          right := IRLowerAST(ASTLeft[node]);
          elemSize := IRPointerStride(ASTRight[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyInteger));
            right := IRAppend(IR_BINOP, right, item, Ord(tkStar), 0, Ord(tyInteger));
          end;
          Result := IRAppend(IR_BINOP, left, right, Ord(tkPlus), 0, Ord(tyPointer));
        end
        else if (TTokenKind(ASTIVal[node]) in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]) and
                (TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) or
                 TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]]))) then
        begin
          { PROMOTABLE INT comparison. The operands are slot ADDRESSES, so the
            ordinary integer compare would compare POINTERS — which silently
            "worked" for < and > by accident of stack layout and got = wrong.
            Route through the runtime and compare its -1/0/1 against zero. }
          promoLhs := IRPromoAddrOf(ASTLeft[node]);
          promoRhs := IRPromoAddrOf(ASTRight[node]);
          promoDst := IRPromoCall('PXXPromoCmp', promoLhs, promoRhs, -1, tyInteger);
          Result := IRAppend(IR_BINOP, promoDst,
                             IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyInteger)),
                             Integer(ASTIVal[node]), 0, Ord(tyBoolean));
        end
        else if TypeIsPromoInt(IntToTypeKind(ASTTk[node])) and
                (PromoOpHelper(TTokenKind(ASTIVal[node])) <> '') then
        begin
          { PROMOTABLE INT arithmetic. The result IS a slot address, so it
            composes — a nested `a*b + c` feeds this path again.

            When the RIGHT operand is an ordinary integer and the operator has a
            mixed form, call that instead of boxing it: `p + n` otherwise cost
            FIVE runtime calls (init temp, box n, init result, add, copy) and
            this collapses it to one. That is the shape almost all real code
            has — accumulators, counters, small constants. }
          promoDst := IRPromoTempSlot(promoSym);
          IRPromoEmitBinop(promoDst, node);
          Result := IRAppend(IR_SLOTADDR, promoSym, -1, -1, 0, Ord(tyPointer));
        end
        else
        begin
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          { C: a string literal in a binop is a char* VALUE (its address, past
            the 8-byte Pascal length prefix — same +8 as the store/call paths).
            Without this, `"abc" == (void*)0` hit the Pascal content-compare,
            which dereferences the NULL operand -> SIGSEGV. }
          if CProgramMode then
          begin
            if ASTKind[ASTLeft[node]] = AN_STR_LIT then
              left := IRAppend(IR_BINOP, left,
                               IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                               Ord(tkPlus), 0, Ord(tyPointer));
            if ASTKind[ASTRight[node]] = AN_STR_LIT then
              right := IRAppend(IR_BINOP, right,
                                IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                                Ord(tkPlus), 0, Ord(tyPointer));
          end;
          { {$Q+} arithmetic: ival=1 marks the op overflow-checked; codegen
            traps a wrapped result into PXXOverflow (RE 215 / EIntOverflow).
            Only ordinal +,-,* carry the tag (parser sets ASTQChk). }
          if ASTQChk[node] and TypeIsOrdinal(IntToTypeKind(ASTTk[node])) then
            Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 1, ASTTk[node])
          else
            Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, ASTTk[node]);
        end;
      end;
    end;

    AN_VAR_DECL:
    begin
      varIdx := ASTIVal[node];
      if SymNeedsZeroing(varIdx, zeroBytes) then
      begin
        IRAppend(IR_ZERO_SYM, varIdx, -1, -1, 0, Ord(Syms[varIdx].TypeKind));
      end;
      if ASTLeft[node] <> -1 then
        Result := IRLowerAST(ASTLeft[node])
      else
        Result := -1;
    end;

    AN_ASSIGN:
    begin
      { FPC/Delphi parity: a procedural VARIABLE named in a VALUE context is
        CALLED. Taking its address is what `@fp` is for, and `fp()` with explicit
        parens was already right — so the two spellings disagreed, and the wrong
        one is the one real Delphi code writes:

          function SslMethodTLS: PSSL_METHOD;
          begin ... Result := _SslMethodTLS;      { <- called by FPC }

        pxx yielded `@TLS_method` instead. The wrong value is a VALID POINTER, so
        nothing errors: Synapse handed it to SSL_CTX_new and libssl died far away
        dereferencing it as a method table.

        Rewritten HERE for the same reason the enum-identity check below lives
        here — every syntactic form of assignment funnels through this node, so
        one rule covers them all instead of ~20 assignment sites.

        The rule and its exceptions live in IRProcVarAutoCall — including that
        this is DELPHI-mode only: FPC and OBJFPC mode pass the address here, and
        that difference is measured, not assumed.
        bug-pascal-procvar-in-value-context-takes-address-instead-of-calling }
      { The LHS is the SINK. Only an identifier we can positively read tells us
        whether it is proc-typed; anything else (field, index, deref) is treated
        as a procvar sink, i.e. left alone, rather than guessed at. }
      ASTRight[node] := IRProcVarAutoCall(ASTRight[node],
                          (ASTKind[ASTLeft[node]] <> AN_IDENT) or
                          (Integer(ASTIVal[ASTLeft[node]]) < 0) or
                          (Integer(ASTIVal[ASTLeft[node]]) >= SymCount) or
                          (SymProcSig[Integer(ASTIVal[ASTLeft[node]])] >= 0));

      { FPC-parity: two enum TYPES are distinct types with no implicit conversion, so
        `aColor := banana` is an error, not a reinterpretation of the ordinal. It used to
        compile and store TFruit's 1 into a TColor, which reads back as green — a wrong
        VALUE, silently (tenum4; the same hole let a {$SCOPEDENUMS} program pick the
        shadowed member of the other enum). Checked here because every syntactic form of
        assignment funnels through this node.

        Identity is ident-level (SymEnumId, tagged at var decls and now at enum-member
        consts): both sides must actually KNOW their enum for this to fire, so an integer,
        a cast or a call result is left alone. A diagnostic, not a type system. }
      if (NodeEnumIdOf(ASTLeft[node]) >= 0) and (NodeEnumIdOf(ASTRight[node]) >= 0) and
         (NodeEnumIdOf(ASTLeft[node]) <> NodeEnumIdOf(ASTRight[node])) then
        ErrorAt(ASTLine[node], 'cannot assign a value of enum type ' +
              GetTokenStrFromRaw(EnumTypeNOff[NodeEnumIdOf(ASTRight[node])],
                                 EnumTypeNLen[NodeEnumIdOf(ASTRight[node])]) +
              ' to a variable of enum type ' +
              GetTokenStrFromRaw(EnumTypeNOff[NodeEnumIdOf(ASTLeft[node])],
                                 EnumTypeNLen[NodeEnumIdOf(ASTLeft[node])]));

      { @BodiedPascalProc into a `cdecl` proc-type var: the indirect cdecl call
        arm marshals TRUE SysV (floats in xmm0..7, int/sse classes counted
        independently, >6 ints spill to stack), but a bodied pxx proc's
        prologue receives the INTERNAL convention (every param in an integer
        register by position, >6 all-stack). The two coincide only for <=6
        integer/pointer params — beyond that the call silently mis-marshals
        (bug-cdecl-indirect-over-6-integer-args: the old loud reject was lost
        when stack spill landed for dlsym'd C targets). Reject the unsound
        binding loudly until bodied cdecl procs get a genuine SysV prologue;
        external (dlsym/C) values are unaffected. }
      if (not CProgramMode) and
         (ASTKind[ASTRight[node]] = AN_PROCADDR) and
         (ASTKind[ASTLeft[node]] = AN_IDENT) and
         { feature-a-typeref-migrate-consumers lane 1: SymProcSig read via
           SymTR[..].ProcSig (kept in sync by SymSyncTypeRef). }
         (Integer(ASTIVal[ASTLeft[node]]) >= 0) and
         (SymTR[ASTIVal[ASTLeft[node]]].ProcSig >= 0) and
         ProcCdecl[SymTR[ASTIVal[ASTLeft[node]]].ProcSig] and
         (Integer(ASTIVal[ASTRight[node]]) >= 0) and
         (not ProcExternal[ASTIVal[ASTRight[node]]]) then
      begin
        varIdx := ASTIVal[ASTRight[node]];   { the bodied target proc }
        if Procs[varIdx].ParamCount > 6 then
          ErrorAt(ASTLine[node], '@' + Procs[varIdx].Name +
            ' as a cdecl function pointer: a Pascal-bodied proc with more than 6 parameters is not SysV-callable yet (bug-cdecl-indirect-over-6-integer-args)');
        for varIdx2 := 0 to Procs[varIdx].ParamCount - 1 do
          if TypeIsFloat(Procs[varIdx].Params[varIdx2].TypeKind) and
             (not Procs[varIdx].Params[varIdx2].IsRef) then
            ErrorAt(ASTLine[node], '@' + Procs[varIdx].Name +
              ' as a cdecl function pointer: a Pascal-bodied proc with a by-value float parameter is not SysV-callable yet (bug-cdecl-indirect-over-6-integer-args)');
      end;

      { PROMOTABLE INT store. Handled before every other assignment shape so no
        integer path ever sees the {tag, payload} slot. A promo source is COPIED
        (which retains its managed heap payload); an ordinary integer source is
        boxed. Both go through promocore.pas, the only place that knows the
        layout. }
      if (ASTKind[ASTLeft[node]] = AN_IDENT) and (ASTIVal[ASTLeft[node]] >= 0) and
         TypeIsPromoInt(Syms[ASTIVal[ASTLeft[node]]].TypeKind) and
         True then
      begin
        varIdx := ASTIVal[ASTLeft[node]];
        { a by-ref promo PARAMETER names its slot through the cell, so the
          destination address is IR_LEA, not IR_SLOTADDR. This arm used to
          exclude IsRef outright, which was harmless while promo parameters did
          not work at all — once they did, `n := n + 1` fell through to a path
          that silently DROPPED the store. }
        if Syms[varIdx].IsRef then
          leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer))
        else
          leftAddr := IRAppend(IR_SLOTADDR, varIdx, -1, -1, 0, Ord(tyPointer));
        if IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant then
          { variant -> promotable int: the runtime reads whichever tier the
            variant holds (VT_INT64 inline, VT_PROMO_INT64 heap) }
          Result := IRPromoCall('PXXPromoFromVariant', leftAddr,
                                IRVariantAddr(ASTRight[node]), -1, tyUnknown)
        else if (ASTKind[ASTRight[node]] = AN_BINOP) and
                TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]])) and
                (PromoOpHelper(TTokenKind(ASTIVal[ASTRight[node]])) <> '') then
        begin
          { compute straight into the target — no temp, no copy }
          IRPromoEmitBinop(leftAddr, ASTRight[node]);
          Result := leftAddr;
        end
        else if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]])) then
          Result := IRPromoCall('PXXPromoCopy', leftAddr,
                                IRPromoAddrOf(ASTRight[node]), -1, tyUnknown)
        else if IRPromoInitFromLiteral(leftAddr, ASTRight[node]) then
          { a literal wider than Int64 (optionally negated): ASTIVal holds only
            the wrapped reading, so the exact value comes from the digit text }
          Result := leftAddr
        else
          Result := IRPromoCall('PXXPromoFromInt', leftAddr,
                                IRLowerAST(ASTRight[node]), -1, tyUnknown);
        Exit;
      end;

      { `x = (a, b)` -- a comma on the right-hand side. Its value IS b, so evaluate a
        for its side effects and then assign FROM b. Rewriting the node here (rather
        than letting IRLowerAST return the comma's value) is what makes a STRUCT survive:
        a record assignment copies from the source's ADDRESS, and a comma is not an
        lvalue, so `(*p) = (g, s);` took the address of nothing and segfaulted -- the
        same shape as the call-argument case fixed in b307, on the other side of the `=`.

        Right-nested, so peel one operand at a time. }
      while ASTKind[ASTRight[node]] = AN_COMMA do
      begin
        IRDiscardValue(IRLowerAST(ASTLeft[ASTRight[node]]));
        ASTRight[node] := ASTRight[ASTRight[node]];
      end;

      lhsTk := IntToTypeKind(ASTTk[ASTLeft[node]]);
      if (lhsTk = tyUnknown) and (ASTKind[ASTLeft[node]] = AN_IDENT) then
      begin
        varIdx := ASTIVal[ASTLeft[node]];
        if (varIdx >= 0) and (varIdx < SymCount) then
          lhsTk := Syms[varIdx].TypeKind;
      end;
      { `operator :=(a: TFoo): TDst` / Implicit — a record/class RHS assigned
        to a DIFFERENT-typed target converts through the overload
        (toperator11's `i := a`). Rewrite RHS to the conversion CALL and fall
        through to the ordinary assign of the result type. }
      if (lhsTk <> tyUnknown) and (lhsTk <> tyAuto) and
         (IntToTypeKind(ASTTk[ASTRight[node]]) <> lhsTk) then
      begin
        varIdx := FindOpOverload(Ord(tkAssign), ASTTk[ASTRight[node]],
                                 ResolveNodeRec(ASTRight[node]));
        { The result-type match must treat the frozen-string kinds as equivalent:
          the SAME `string[N]` type resolves to tyString in a var declaration but
          to tyFixedString as an operator return type, so a strict `RetType = lhsTk`
          missed a `class operator Implicit(...): string[N]` and left `s := t` as a
          raw record→string store — the shortstring's length byte was garbage and
          writeln(s) segfaulted (toperator93). A plain function returning string[N]
          already stored fine, so once the rewrite fires the ordinary frozen-string
          store handles the result. }
        if (varIdx >= 0) and
           ((Procs[varIdx].RetType = lhsTk) or
            (TypeIsFrozenString(Procs[varIdx].RetType) and TypeIsFrozenString(lhsTk))) then
        begin
          leftAddr := AllocNode(AN_ARG);
          ASTLeft[leftAddr] := ASTRight[node];
          slFldRec := AllocNode(AN_CALL);
          ASTIVal[slFldRec] := varIdx;
          ASTTk[slFldRec] := Ord(Procs[varIdx].RetType);
          ASTLeft[slFldRec] := leftAddr;
          ASTRight[node] := slFldRec;
        end;
      end;
      lhsStoreTk := lhsTk;
      lhsStrCap := 0;
      { ESP (xtensa/riscv32) treats Single as first-class, so a float-producing
        operator with NO float operand — `1 / 3` — takes the NATIVE depth, which
        is Single there. That is the right call for code that never asked for a
        Double, and the wrong one when the program did: a declared `Double` then
        quietly held 7 significant digits, and the same source gave different
        numbers on ESP than on every other target.

        So when neither operand supplies a depth, the TARGET's does (user,
        2026-08-11, decide-esp-single-depth-division-into-a-declared-double).
        A no-op everywhere else: every other backend already types such a binop
        tyDouble, so the widen has nothing to do. }
      IRWidenOrdinalFloatBinop(ASTRight[node], lhsTk);
      if ASTKind[ASTLeft[node]] = AN_FIELD then
      begin
        slFldRec := ResolveNodeRec(ASTLeft[ASTLeft[node]]);
        slFldName := GetASTIdentName(ASTLeft[node]);
        if slFldRec <> REC_NONE then
        begin
          lhsStoreTk := RecFieldType(slFldRec, slFldName);
          { `string[N]` field: capacity rides the store node's IVal so codegen
            clamps the copy to N (truncating shortstring assignment). }
          if lhsStoreTk = tyString then
            lhsStrCap := RecFieldStrCap(slFldRec, slFldName);
        end;
        if (lhsTk = tyUnknown) or (lhsTk = tyAuto) then
          lhsTk := lhsStoreTk;
      end
      else if (ASTKind[ASTLeft[node]] = AN_INDEX) and (lhsTk = tyString) and
              (ASTKind[ASTLeft[ASTLeft[node]]] = AN_IDENT) and
              TypeIsFrozenString(Syms[ASTIVal[ASTLeft[ASTLeft[node]]]].ElemType) then
        { `array[..] of string[N]` ELEMENT: same capacity clamp the record-field
          arm above has had all along. Without it `a[0] := s` copied the SOURCE
          length — writing past the element's N chars into its neighbour, and
          reading back with a length that is not the slot's. The declared
          capacity lives on the array symbol (SymStrCap), the way the element
          stride in IRLowerAddress reads it. }
        lhsStrCap := SymStrCap[ASTIVal[ASTLeft[ASTLeft[node]]]];
      if ASTKind[ASTRight[node]] = AN_DEFAULT then
      begin
        if (lhsTk = tyUnknown) or (lhsTk = tyAuto) then
          Error('default requires a known target type');
        ASTTk[ASTRight[node]] := Ord(lhsTk);
        if (lhsTk = tyRecord) or (lhsTk = tySet) or
           ((ASTKind[ASTLeft[node]] = AN_IDENT) and Syms[ASTIVal[ASTLeft[node]]].IsArray and
            not (Syms[ASTIVal[ASTLeft[node]]].ArrLen = -1)) then
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          if lhsTk = tyRecord then
          begin
            idx := ResolveNodeRec(ASTLeft[node]);
            elemSize := RecSize(idx);
            if RecordHasManagedFields(idx) then
              Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, idx, elemSize, Ord(lhsTk))
            else
              Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE, elemSize, Ord(lhsTk));
          end
          else if lhsTk = tySet then
            Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE, TypeSize(tySet), Ord(lhsTk))
          else
          begin
            varIdx := ASTIVal[ASTLeft[node]];
            { feature-a-typeref-migrate-consumers lane 1: ElemType/ElemRecName read
              via SymTR[varIdx].ElemTk/ElemRec (kept in sync by SymSyncTypeRef). }
            if SymTR[varIdx].ElemTk = Ord(tyRecord) then
              elemSize := RecSize(SymTR[varIdx].ElemRec)
            else
              elemSize := TypeSize(IntToTypeKind(SymTR[varIdx].ElemTk));
            Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE,
                               Syms[varIdx].ArrLen * elemSize, ASTTk[ASTLeft[node]]);
          end;
        end
        else
        begin
          if lhsTk = tyString then
            value := IRAppend(IR_CONST_STR, 0, 0, -1, 0, Ord(tyString))
          else
            value := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(lhsTk));
          if ASTKind[ASTLeft[node]] = AN_IDENT then
            Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]])
          else
          begin
            leftAddr := IRLowerAddress(ASTLeft[node]);
            Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(lhsStoreTk));
          end;
        end;
      end
      else
      begin
      if (lhsTk = tyString) or (lhsTk = tyAnsiString) then
      begin
        { A WideChar VALUE assigned to a string converts to its UTF-8 encoding
          (fpjson's `U := widechar(U1)`). Without this the 16-bit ordinal fell
          into the managed-assign path, which retained it AS A POINTER —
          silent memory corruption, then a crash. This catches both a
          `widechar(x)` cast node (NodeIsWideCharVal) AND a bare 2-byte-ordinal
          RHS — a `w: WideChar` variable read is a plain tyUInt16 ident (WideChar
          collapses to tyUInt16, no subtype marker), which the cast-only check
          missed → `s := w` crashed. Assigning any tyUInt16 to a string is only
          meaningful as a widechar (a genuine Word->string is invalid in FPC and
          nonsensical here); pxx's lax default converts rather than rejecting
          (strict-FPC parity would belong behind --strict-fpc). See
          bug-pascal-widechar-var-to-string-segfault. }
        if NodeIsWideCharVal(ASTRight[node]) or
           (IntToTypeKind(ASTTk[ASTRight[node]]) = tyUInt16) then
          ASTRight[node] := WrapWideCharToUTF8(ASTRight[node]);
        if IsNodePChar(ASTRight[node]) and not CProgramMode then
          ASTRight[node] := WrapPCharToString(ASTRight[node]);
      end;

      { NilPy-user class-local/global rebinding ARC
        (feature-nilpy-object-reclamation slice 4): retain the new value UNLESS
        it is a construction (whose rc=1 transfers to the binding), release the
        old value, then store — retain-first, so self-assignment is safe. The
        Pascal callees carry the nil check and the population-tag guard.
        Params are excluded on purpose: a param holds the CALLER's borrowed
        ref; releasing it on rebind (or at scope exit, where params are also
        skipped) would drop a ref the callee never owned. }
      { `d = None` (or any scalar) over a class binding: the old object's ref
        must still drop, then the sentinel stores raw through the generic path
        (the scope-exit release no-ops on it via the plausibility guard). }
      if NilPyUserCode and
         (ASTKind[ASTLeft[node]] = AN_IDENT) and
         (Integer(ASTIVal[ASTLeft[node]]) >= 0) and
         PyClassSymArcEligible(ASTIVal[ASTLeft[node]]) and
         (IntToTypeKind(ASTTk[ASTRight[node]]) in
            [tyInteger, tyInt8, tyInt16, tyInt32, tyInt64, tyNativeInt,
             tyBoolean, tyChar, tyDouble, tySingle]) then
      begin
        procIdx := FindProc('PXXObjRelease');
        if procIdx >= 0 then
        begin
          first := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_SYM, Integer(ASTIVal[ASTLeft[node]]), -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
          seq := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
          IRIVal[seq] := 1;   { statement: emit for effect; then fall through }
        end;
      end;

      if NilPyUserCode and
         (ASTKind[ASTLeft[node]] = AN_IDENT) and
         (Integer(ASTIVal[ASTLeft[node]]) >= 0) and
         PyClassSymArcEligible(ASTIVal[ASTLeft[node]]) and
         (IntToTypeKind(ASTTk[ASTRight[node]]) = tyClass) then
      begin
        varIdx := ASTIVal[ASTLeft[node]];
        intfTmpInst := AllocVar('', tyPointer);
        IRAppend(IR_STORE_SYM, intfTmpInst, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));
        { A construction OR any call result is OWNED (+1 already: rc=1 from
          PXXObjAlloc, or the callee's return-retain) — retaining it again
          would leak one ref per call. Only lvalue-ish sources are borrows. }
        if not IRNodeYieldsOwnedRef(ASTRight[node]) then
        begin
          procIdx := FindProc('PXXObjRetain');
          if procIdx < 0 then Error('Nil Python: PXXObjRetain (builtinheap) not loaded');
          first := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
          seq := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
          IRIVal[seq] := 1;   { statement: emit for effect }
        end;
        procIdx := FindProc('PXXObjRelease');
        if procIdx < 0 then Error('Nil Python: PXXObjRelease (builtinheap) not loaded');
        first := IRAppend(IR_ARG,
                   IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
        seq := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
        IRIVal[seq] := 1;
        Result := IRAppend(IR_STORE_SYM, varIdx,
                    IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)),
                    -1, 0, ASTTk[ASTLeft[node]]);
        Exit;
      end;

      { NilPy-user class FIELD store ARC (feature-nilpy-object-reclamation,
        field-store side pulled forward from slice 5): without it a `self.w = w`
        stores a raw pointer, and the local's scope-exit release frees the
        object out from under the field (uforth's word registry). Same
        ownership rules as the local arm: call/construction results are OWNED
        (no retain), lvalues are borrows (retain); the field's old value is
        released, retain-first order. Class-typed fields are not walked by the
        finalizer yet, so the field's ref leaks when the instance dies —
        leak-over-UAF until the finalizer grows a class-field kind. }
      if NilPyUserCode and
         (ASTKind[ASTLeft[node]] = AN_FIELD) and
         (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyClass) and
         (IntToTypeKind(ASTTk[ASTRight[node]]) = tyClass) then
      begin
        seq := AllocVar('', tyPointer);        { the value }
        IRAppend(IR_STORE_SYM, seq, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));
        varIdx := AllocVar('', tyPointer);     { the field slot address }
        IRAppend(IR_STORE_SYM, varIdx, IRLowerAddress(ASTLeft[node]), -1, 0, Ord(tyPointer));
        if not IRNodeYieldsOwnedRef(ASTRight[node]) then
        begin
          procIdx := FindProc('PXXObjRetain');
          if procIdx < 0 then Error('Nil Python: PXXObjRetain (builtinheap) not loaded');
          first := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_SYM, seq, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer));
          last := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
          IRIVal[last] := 1;
        end;
        procIdx := FindProc('PXXObjRelease');
        if procIdx < 0 then Error('Nil Python: PXXObjRelease (builtinheap) not loaded');
        first := IRAppend(IR_ARG,
                   IRAppend(IR_LOAD_MEM,
                     IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(tyPointer));
        last := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
        IRIVal[last] := 1;
        Result := IRAppend(IR_STORE_MEM,
                    IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                    IRAppend(IR_LOAD_SYM, seq, -1, -1, 0, Ord(tyPointer)),
                    -1, 0, Ord(tyPointer));
        Exit;
      end;

      { Class -> interface: build the CORBA fat pointer {IMT, instance} into the
        LHS. The IMT for (RHS static class, interface) is captured here; the
        instance pointer is the RHS value. (interface := interface falls through
        to the 16-byte record copy below.) }
      if lhsTk = tyRecord then
      begin
        varIdx := ResolveNodeRec(ASTLeft[node]);
        isComIntf := (varIdx >= REC_UCLASS_BASE) and
                     UClsIsInterface[varIdx - REC_UCLASS_BASE] and
                     UClsIsComInterface[varIdx - REC_UCLASS_BASE];
        { interface := nil — zero the whole fat pointer {nil, nil}. The RHS is a
          pointer/ordinal nil, not a class or interface, so it never reaches the
          record-copy path (which would dereference a bogus source). }
        if (varIdx >= REC_UCLASS_BASE) and UClsIsInterface[varIdx - REC_UCLASS_BASE] and
           (IntToTypeKind(ASTTk[ASTRight[node]]) <> tyClass) and
           (IntToTypeKind(ASTTk[ASTRight[node]]) <> tyRecord) then
        begin
          { COM/ARC: release the old reference before discarding the slot. }
          if isComIntf then
          begin
            first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
            argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, varIdx - REC_UCLASS_BASE, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
            IRB[first] := argNode;
            seq := IRAppendCall(FindProc('PXXIntfRelease'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;  { statement-level: side-effect call, result discarded }
          end;
          Result := IRAppend(IR_DEFAULT_MEM, IRLowerAddress(ASTLeft[node]),
                             -1, REC_NONE, RecSize(varIdx), Ord(tyRecord));
          Exit;
        end;
        if (varIdx >= REC_UCLASS_BASE) and UClsIsInterface[varIdx - REC_UCLASS_BASE] and
           (IntToTypeKind(ASTTk[ASTRight[node]]) = tyClass) then
        begin
          classIdx := ResolveNodeRec(ASTRight[node]);
          { A cast TO an interface type — `IFoo(p)`, `IFoo(List[i])` — is a hard
            REINTERPRET, not a class->interface coercion: FPC spells the recovery
            of an interface from a pointer-shaped container exactly this way, and
            it is only expressible at all because an interface value is a single
            pointer. Nothing to check, nothing to convert; the ARC assign below
            still retains it. }
          if (classIdx >= REC_UCLASS_BASE) and UClsIsInterface[classIdx - REC_UCLASS_BASE] then
            procIdx := 0
          else
          begin
            procIdx := FindIMT(classIdx - REC_UCLASS_BASE, varIdx - REC_UCLASS_BASE);
            if procIdx < 0 then Error('class does not implement the interface');
          end;
          { An interface value is ONE pointer: the instance. The IMT lookup
            (procIdx) is still done here purely to CHECK the class implements the
            interface at compile time. }
          if isComIntf then
          begin
            { COM/ARC class -> interface: retain the new reference, release the old
              slot, then publish. Retain-before-release keeps re-assigning the same
              object safe. }
            intfTmpInst := AllocVar('', tyPointer);
            IRAppend(IR_STORE_SYM, intfTmpInst, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));
            first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)), -1, -1, 0, Ord(tyPointer));
            argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, varIdx - REC_UCLASS_BASE, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
            IRB[first] := argNode;
            seq := IRAppendCall(FindProc('PXXIntfAddRefRaw'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;
            first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
            argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, varIdx - REC_UCLASS_BASE, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
            IRB[first] := argNode;
            seq := IRAppendCall(FindProc('PXXIntfRelease'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;
            Result := IRAppend(IR_STORE_MEM, IRLowerAddress(ASTLeft[node]),
                               IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
            Exit;
          end;
          value := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_STORE_MEM, IRLowerAddress(ASTLeft[node]), value, -1, 0, Ord(tyPointer));
          Exit;
        end;
        { COM/ARC interface -> interface (RHS is another interface lvalue):
          retain source, release old dest, copy the single-pointer value — all in
          the ARC-correct order inside PXXIntfAssign. }
        if isComIntf and
           ((ASTKind[ASTRight[node]] = AN_IDENT) or (ASTKind[ASTRight[node]] = AN_FIELD) or
            (ASTKind[ASTRight[node]] = AN_INDEX) or (ASTKind[ASTRight[node]] = AN_DEREF)) and
           (ResolveNodeRec(ASTRight[node]) >= REC_UCLASS_BASE) and
           UClsIsInterface[ResolveNodeRec(ASTRight[node]) - REC_UCLASS_BASE] then
        begin
          first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer));
          IRB[first] := argNode;
          seq := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, varIdx - REC_UCLASS_BASE, Ord(tyNativeInt)), -1, -1, 0, Ord(tyNativeInt));
          IRB[argNode] := seq;
          Result := IRAppendCall(FindProc('PXXIntfAssign'), first, -1, Ord(tyPointer));
          IRIVal[Result] := 1;
          Exit;
        end;
      end;

      { Whole-record copy: the scalar store paths move only a qword (8 bytes),
        which truncates records larger than 8 bytes. When the RHS is an lvalue,
        copy the full RecSize via IR_COPY_REC (rep movsb). }
      rhsIsLValue := (ASTKind[ASTRight[node]] = AN_IDENT) or
                     (ASTKind[ASTRight[node]] = AN_FIELD) or
                     (ASTKind[ASTRight[node]] = AN_INDEX) or
                     (ASTKind[ASTRight[node]] = AN_DEREF);
      if ASTKind[ASTRight[node]] = AN_METHODREF then
      begin
        { @obj.method assigned to a TMethod target: write the two pointers
          directly — Code at field+0, Data at field+TARGET_PTR_SIZE (8 on
          64-bit, 4 on i386/arm32, matching the user TMethod's Data offset). }
        left := ASTRight[node];
        leftAddr := IRLowerAddress(ASTLeft[node]);
        value := IRMethodRefCode(left);   { VMT-resolved for a virtual method }
        IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(tyPointer));
        right := IRLowerAddress(ASTLeft[node]);
        item := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
        outNode := IRAppend(IR_BINOP, right, item, Ord(tkPlus), 0, Ord(tyPointer));
        seq := IRLowerAST(ASTLeft[left]);
        Result := IRAppend(IR_STORE_MEM, outNode, seq, -1, 0, Ord(tyPointer));
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tySet) or
              ((ASTKind[ASTLeft[node]] = AN_IDENT) and
               (ASTIVal[ASTLeft[node]] >= 0) and
               (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tySet) and
               not Syms[ASTIVal[ASTLeft[node]]].IsArray) then
      begin
        { The symbol-TypeKind fallback is the SAME rule the record arm below
          carries, and this arm was the sibling that never got it: the
          function-name result form (`FuncName := [1, 4]`) leaves the LHS ASTTk
          unset (0), so a set-returning function fell through to the scalar
          store path and wrote the literal's ADDRESS into the 32-byte Result
          slot. Every set-returning function therefore answered the EMPTY set —
          silently, on every target, whatever the body did.
          bug-a-set-and-array-function-results-come-back-empty }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_SET_COPY, leftAddr, right, -1, 0, Ord(tySet));
      end
      else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
              Syms[ASTIVal[ASTLeft[node]]].IsArray and
              (Syms[ASTIVal[ASTLeft[node]]].ArrLen = -1) then
      begin
        value := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0,
                           ASTTk[ASTLeft[node]]);
      end
      else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
              (ASTIVal[ASTLeft[node]] >= 0) and
              Syms[ASTIVal[ASTLeft[node]]].IsArray and
              (Syms[ASTIVal[ASTLeft[node]]].ArrLen >= 0) and
              { N-D arrays are stored flat and ArrLen is the FLATTENED element
                count, so one IR_COPY_REC of ArrLen*elemSize copies the whole
                thing — the old `<= 1` guard sent `b := a` on a 2-D array to the
                scalar store path instead, which moved a single element's width
                and left the rest garbage (bug-nd-array-assign-copies-garbage). }
              (SymElemDynDepth[ASTIVal[ASTLeft[node]]] = 0) and
              { tyString elements stay on the scalar path: their slot width is
                decided at DECLARATION time (STRING_CAP+8 global vs
                LOCAL_STR_CAP+8 local, see AllocArray) and is not recoverable
                from the symbol here, so a byte count computed now would be
                wrong. tyFixedString/tyShortString DO carry their capacity
                (SymStrCap) and are handled below. }
              (Syms[ASTIVal[ASTLeft[node]]].ElemType <> tyString) and
              (not rhsIsLValue) and
              ((ASTKind[ASTRight[node]] = AN_CALL) or
               (ASTKind[ASTRight[node]] = AN_VIRTUAL_CALL)) and
              (ASTIVal[ASTRight[node]] >= 0) and
              (ASTIVal[ASTRight[node]] < MAX_PROCS) and
              (ProcRetFixedArrBytes[ASTIVal[ASTRight[node]]] > 0) then
      begin
        { `a := MkArr` — a whole static array from a CALL. The arm below wants an
          LVALUE on the right, and a call is not one, so this fell through to the
          scalar store and moved a single element's width: with the hidden
          destination in place the value stored was the DEST POINTER itself, and
          before it the callee's element 0. Either way `8 9 10` came back as one
          number and two zeros, silently.

          The call's value IS the hidden destination's address (see
          ABIRetViaHiddenDestProc), so this is the same IR_COPY_REC the
          array-to-array case emits, sourced from the call instead of from an
          address-of. bug-a-set-and-array-function-results-come-back-empty }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                           ProcRetFixedArrBytes[ASTIVal[ASTRight[node]]],
                           Ord(tyRecord));
      end
      else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
              (ASTIVal[ASTLeft[node]] >= 0) and
              Syms[ASTIVal[ASTLeft[node]]].IsArray and
              (Syms[ASTIVal[ASTLeft[node]]].ArrLen >= 0) and
              (SymElemDynDepth[ASTIVal[ASTLeft[node]]] = 0) and
              (Syms[ASTIVal[ASTLeft[node]]].ElemType <> tyString) and
              rhsIsLValue then
      begin
        { Whole static-array assignment (`b := a`). The scalar store path below
          moves only one element's width, leaving the rest of `b` as garbage
          (bug-fixed-array-assignment-no-copy). Copy the full ArrLen*elemSize
          via IR_COPY_REC, mirroring the whole-record path and the static-array
          arg-copy idiom above. MANAGED elements used to be excluded here and
          left to the scalar path, which does not copy an array at all — see
          IRManagedArrayCopy for that bug and the ARC shape that replaces it. }
        i := ASTIVal[ASTLeft[node]];
        if Syms[i].ElemType = tyRecord then elemSize := RecSize(Syms[i].ElemRecName)
        else if TypeIsFrozenString(Syms[i].ElemType) then
          { `array[..] of string[N]`: the slot is a length word + N chars, not
            TypeSize's default 8 — which copied only the first element. }
          elemSize := FrozenStrSlotSize(Syms[i].ElemType, SymStrCap[i])
        else elemSize := TypeSize(Syms[i].ElemType);
        waBaseKind := 0;
        if Syms[i].ElemType = tyAnsiString then waBaseKind := 1
        else if (Syms[i].ElemType = tyRecord) and
                RecordHasManagedFields(Syms[i].ElemRecName) then waBaseKind := 3;
        if waBaseKind = 0 then
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          right := IRLowerAddress(ASTRight[node]);
          Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                             Syms[i].ArrLen * elemSize, Ord(tyRecord));
        end
        else
          Result := IRManagedArrayCopy(ASTLeft[node], ASTRight[node],
                      Syms[i].ArrLen, elemSize, waBaseKind, Syms[i].ElemRecName);
      end
      else if (ASTKind[ASTLeft[node]] = AN_FIELD) and rhsIsLValue and
              (faFldRecIdxHelper(ASTLeft[node], faFldRec, faFldIdx)) and
              UFldIsArray[faFldIdx] and (UFldArrLen[faFldIdx] >= 0) and
              (UFldDynDepth[faFldIdx] = 0) and
              { see the tyString note on the variable branch above }
              (UFldTk[faFldIdx] <> Ord(tyString)) then
      begin
        { Whole static-array FIELD assignment (`rec.a := other.a`, or `Result.FArr
          := F` inside a record method). The AN_IDENT whole-array branch above only
          fires for a plain array VARIABLE; a static-array FIELD target fell through
          to the scalar store, which moved a single element's width and left the
          rest of the destination array untouched (tforin25: a record enumerator's
          `Result.FArr := F` copied only element 0). Copy the full
          ArrLen*elemSize via IR_COPY_REC, mirroring the variable path — managed
          elements through IRManagedArrayCopy, exactly as that branch does
          (`y.arr := x.arr` on an array-of-string field gave `[f0][][]`). }
        if UFldTk[faFldIdx] = Ord(tyRecord) then elemSize := RecSize(UFldRec_[faFldIdx])
        else if TypeIsFrozenString(IntToTypeKind(UFldTk[faFldIdx])) then
          elemSize := FrozenStrSlotSize(IntToTypeKind(UFldTk[faFldIdx]), UFldStrCap[faFldIdx])
        else elemSize := TypeSize(IntToTypeKind(UFldTk[faFldIdx]));
        waBaseKind := 0;
        if UFldTk[faFldIdx] = Ord(tyAnsiString) then waBaseKind := 1
        else if (UFldTk[faFldIdx] = Ord(tyRecord)) and
                RecordHasManagedFields(UFldRec_[faFldIdx]) then waBaseKind := 3;
        if waBaseKind = 0 then
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          right := IRLowerAddress(ASTRight[node]);
          Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                             UFldArrLen[faFldIdx] * elemSize, Ord(tyRecord));
        end
        else
          Result := IRManagedArrayCopy(ASTLeft[node], ASTRight[node],
                      UFldArrLen[faFldIdx], elemSize, waBaseKind, UFldRec_[faFldIdx]);
      end
      else if (ASTKind[ASTLeft[node]] = AN_INDEX) and
              (ASTKind[ASTLeft[ASTLeft[node]]] = AN_IDENT) and
              (ASTIVal[ASTLeft[ASTLeft[node]]] >= 0) and
              Syms[ASTIVal[ASTLeft[ASTLeft[node]]]].IsArray and
              (SymDynElemRowLen[ASTIVal[ASTLeft[ASTLeft[node]]]] > 0) and
              rhsIsLValue then
      begin
        { Whole-ROW store into a fixed-array-element dynamic array / open-array
          param: `d[i] := r` (r a static array of the row type). The scalar
          store path would move one base element; copy the full row
          (bug-pascal-openarray-of-array-param-marshal). d[i][j] := v has an
          AN_INDEX base, not AN_IDENT, so it keeps the scalar path. }
        i := ASTIVal[ASTLeft[ASTLeft[node]]];
        if Syms[i].ElemType = tyRecord then elemSize := RecSize(Syms[i].ElemRecName)
        else elemSize := TypeSize(Syms[i].ElemType);
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAddress(ASTRight[node]);
        Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                           SymDynElemRowLen[i] * elemSize, Ord(tyRecord));
      end
      else if CProgramMode and (ASTKind[ASTLeft[node]] = AN_FIELD) and
              (RecFieldBitWidth(ResolveNodeRec(ASTLeft[ASTLeft[node]]),
                                GetASTIdentName(ASTLeft[node])) > 0) then
      begin
        value := IRLowerAST(ASTRight[node]);
        lhsStoreTk := RecFieldType(ResolveNodeRec(ASTLeft[ASTLeft[node]]),
                                   GetASTIdentName(ASTLeft[node]));
        IRLowerBitFieldStore(ASTLeft[node], value, lhsStoreTk);
        Result := IRLowerBitFieldRead(ASTLeft[node], IRLowerAddress(ASTLeft[node]), lhsStoreTk);
      end
      else if (ASTKind[ASTLeft[node]] <> AN_IDENT) and
              (NodeDynDepth(ASTLeft[node]) > 0) then
      begin
        { Whole dynamic-array assignment into a non-IDENT lvalue (a record/object
          dyn-array field, or a nested sub-array slot). The source handle is
          pointer-sized; store all 8 bytes into the field address. Without this
          the generic scalar store below used the element width (truncating the
          8-byte handle to 4) and the field ended up holding the source's slot
          address rather than its handle -> segfault on the next index/Length.

          On x86-64 use the ARC-correct IR_STORE_DYN: retain the new handle and
          element-aware release the old one, matching the IR_STORE_SYM IDENT
          path. Without that retain, assigning a LOCAL dyn array to a field
          (`field := tmp`) shares the handle, and the local's scope-exit release
          frees the data the field still points at — managed-element strings come
          back empty, and a shrinking rebuild segfaults
          (bug-dynarray-managed-record-field-reassign). Other targets keep the
          bare handle store (share-semantics) for now; the new op is x86-64-only,
          so they never see it. }
        value := IRLowerAST(ASTRight[node]);
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if TargetArch = TARGET_X86_64 then
        begin
          Result := IRAppend(IR_STORE_DYN, leftAddr, value,
                             NodeDynDepth(ASTLeft[node]), -1,
                             Ord(NodeDynBaseTk(ASTLeft[node])));
          IRSetLenBaseRec[Result] := NodeDynBaseRec(ASTLeft[node]);
        end
        else
          Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(tyPointer));
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord) or
              ((ASTKind[ASTLeft[node]] = AN_IDENT) and
               (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyRecord)) then
      begin
        { A record-typed destination. The function-name result form
          (`FuncName := rec`) leaves the LHS ASTTk unset (0), so fall back to
          the symbol's TypeKind; without this the scalar store path below
          copies only the first qword and truncates the record. }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if rhsIsLValue then
          right := IRLowerAddress(ASTRight[node])
        else
          right := IRLowerAST(ASTRight[node]);
        if RecordHasManagedFields(ResolveNodeRec(ASTLeft[node])) then
          { ARC-correct copy: retain source managed fields, release the old
            destination ones, then bulk-copy. }
          Result := IRAppend(IR_COPY_REC_MANAGED, leftAddr, right,
                             ResolveNodeRec(ASTLeft[node]),
                             RecSize(ResolveNodeRec(ASTLeft[node])), Ord(tyRecord))
        else
          Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                             RecSize(ResolveNodeRec(ASTLeft[node])), Ord(tyRecord));
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
              ((ASTKind[ASTLeft[node]] = AN_IDENT) and
               (Integer(ASTIVal[ASTLeft[node]]) >= 0) and
               (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyVariant) and
               (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyUnknown)) then
      begin
        { Variant target. IRC carries the source kind: tyVariant => full 16-byte
          copy; any scalar kind => box it (tag + payload) via IR_VAR_STORE.
          The function-name result form (`FuncName := variantCall`) leaves the
          LHS ASTTk unset, exactly like the record arm above — without the
          symbol-TypeKind fallback it fell to the generic 8-byte store_sym, so
          a Variant FUNCTION forwarding another Variant call's result kept only
          whatever rax held: VType garbage, payload lost
          (bug-a-variant-fn-return-forward-nrvo-corruption). }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]])) then
        begin
          { promotable int -> variant. An INLINE value becomes an ordinary
            VT_INT64 variant, so the common case needs no new handling
            downstream; only a heap value takes the VT_PROMO_INT64 tag.
            Statement-marked HERE: when this assignment is synthesised as a
            SUBEXPRESSION (the call-arg scalar->Variant boxing temp), nothing
            else marks the call and codegen would silently skip it, leaving
            the temp VT_EMPTY (None). }
          Result := IRPromoCall('PXXPromoToVariant', leftAddr,
                                IRPromoAddrOf(ASTRight[node]), -1, tyUnknown);
          IRMarkStatementNode(Result);
        end
        else if IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant then
        begin
          if rhsIsLValue then
            right := IRLowerAddress(ASTRight[node])
          else
            right := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_VAR_STORE, leftAddr, right, Ord(tyVariant), 0, Ord(tyVariant));
        end
        else
        begin
          value := IRLowerAST(ASTRight[node]);
          { IRC is the SOURCE KIND the variant store boxes by, and it must
            describe the value that was actually produced — not what the AST
            expected. A literal-concat (`'p' + 'q'`) is folded above into a
            single IR_CONST_STR tagged tyString, deliberately (a static literal
            pointer must not be treated as a heap handle); the AST node stays
            tyAnsiString. Boxing it AS tyAnsiString read a length word that is
            not there, so `Show('p' + 'q')` handed over an EMPTY variant while
            `Show('pq')` and `s := 'p' + 'q'; Show(s)` were both correct —
            silently, in plain Pascal as well as NilPy.
            Taking the kind from the folded literal puts it on exactly the
            known-good one-line-literal path.
            bug-nilpy-adjacent-string-literals-concatenate-in-only-some-positions }
          if (IRKind[value] = IR_CONST_STR) and
             (IntToTypeKind(ASTTk[ASTRight[node]]) = tyAnsiString) then
            Result := IRAppend(IR_VAR_STORE, leftAddr, value,
                               Ord(IntToTypeKind(IRTk[value])), 0, Ord(tyVariant))
          else
            Result := IRAppend(IR_VAR_STORE, leftAddr, value,
                               Ord(IntToTypeKind(ASTTk[ASTRight[node]])), 0, Ord(tyVariant));
        end;
      end
      else
      begin
        { Variant SOURCE, scalar target — the mirror of the variant-target case
          above, and the one that was missing. Unboxing HERE, at the value, and
          then falling into the ordinary store keeps every downstream rule
          (ARC for a managed target, store width, the C-string skip below);
          before this the scalar store read the variant's first 8 bytes, i.e.
          the TAG, so `i := v` yielded 1 and a string target segfaulted on the
          tag as a handle (bug-a-nilpy-variant-element-not-usable-as-scalar). }
        if (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant) and
           IRVariantUnboxKind(IntToTypeKind(ASTTk[ASTLeft[node]])) then
          value := IRLowerVariantAsScalar(ASTRight[node], IntToTypeKind(ASTTk[ASTLeft[node]]))
        else if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTRight[node]])) and
                TypeIsOrdinal(lhsTk) then
          { PROMO source, concrete int target (a NilPy `int`-annotated variable
            reassigned with a masked expression, `n = n & 0xFFFFFFFFFFFFFFFF`):
            narrow with two's-complement WRAP (value mod 2^64). The raw store
            would write the slot ADDRESS; the checked narrowing would trap on
            exactly the masked intermediates the idiom is built from. }
          value := IRPromoCall('PXXPromoToInt64Wrap',
                               IRPromoAddrOf(ASTRight[node]), -1, -1, tyInt64)
        else
        value := IRLowerAST(ASTRight[node]);
        { A C string literal stored to a pointer must land on char 0, not the
          8-byte Pascal length prefix the literal's handle points at. Apply the
          same +8 skip the call-argument path uses (see the tyString->tyPointer
          marshalling in AN_CALL). C-mode only -> Pascal self-build unaffected. }
        if CProgramMode and (ASTKind[ASTRight[node]] = AN_STR_LIT) and
           (lhsTk = tyPointer) then
          value := IRAppend(IR_BINOP, value,
                            IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                            Ord(tkPlus), 0, Ord(tyPointer));
        { {$R+}: guard a narrowing store with the range-check helper — index
          bounds (reads AND writes) are handled centrally in IRLowerAddress
          (feature-pascal-range-checks-r-plus). }
        if ASTRChk[node] then
        begin
          if ASTKind[ASTLeft[node]] = AN_IDENT then
          begin
            { a named-SUBRANGE dest checks its declared lo..hi (T = 3..7);
              the retained alias bounds outrank the plain width table. }
            varIdx := ASTIVal[ASTLeft[node]];
            if (varIdx >= 0) and (varIdx < SymCount) and SymIsSub[varIdx] then
              value := IRWrapChkBounds(value, SymSubLo[varIdx], SymSubHi[varIdx])
            else
              value := IRWrapRangeChk(value, IntToTypeKind(ASTTk[ASTLeft[node]]));
          end
          else if (ASTKind[ASTLeft[node]] = AN_FIELD) and
                  (ResolveNodeRec(ASTLeft[ASTLeft[node]]) <> REC_NONE) and
                  RecFieldSubBounds(ResolveNodeRec(ASTLeft[ASTLeft[node]]),
                                    GetASTIdentName(ASTLeft[node]),
                                    rcSubLo, rcSubHi) then
            { subrange FIELD dest: its retained lo..hi outranks the width table }
            value := IRWrapChkBounds(value, rcSubLo, rcSubHi)
          else
            value := IRWrapRangeChk(value, lhsStoreTk);
        end;
        if ASTKind[ASTLeft[node]] = AN_IDENT then
        begin
          Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]]);
          { In C an assignment is an expression yielding the stored value, so load
            it back; this lets `g(p = x)` / `(p = x)->f` use the value. Pascal keeps
            the store node as the result -> self-build byte-identical. }
          if CProgramMode then
            Result := IRAppend(IR_LOAD_SYM, ASTIVal[ASTLeft[node]], -1, -1, 0, ASTTk[ASTLeft[node]]);
        end
        else
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, lhsStrCap, Ord(lhsStoreTk));
          if CProgramMode then
            Result := IRAppend(IR_LOAD_MEM, leftAddr, -1, -1, 0, Ord(lhsStoreTk));
        end;
      end;
      end;
    end;

    AN_HALT, AN_EXIT:
    begin
      beforeCount := IRCount;
      if ASTKind[node] = AN_HALT then
      begin
        if ASTLeft[node] <> -1 then
          value := IRLowerAST(ASTLeft[node])
        else
          value := -1;
        { FPC runs unit finalization sections on Halt too. The runner shell is
          registered lazily (this Halt may lower before later units parse);
          its body — reverse-order finalizers behind a run-once guard — is
          emitted after the main body (bug-unit-finalization-not-executed). }
        last := IRAppendCall(GetFiniRunnerProc, -1, -1, Ord(tyInteger));
        IRIVal[last] := 1;   { statement-level: side-effect call }
        last := IRAppend(IR_TERMINATE, value, -1, -1, AN_HALT, 0);
      end
      else if (CurProc < 0) and (ASTLeft[node] <> -1) then
      begin
        { `return <expr>` from a top-level C main (no enclosing proc): the value
          IS the process exit code, so terminate with it like Halt(expr). Pascal
          program-level Exit never carries a value, so this never fires in a
          self-build (byte-identical preserved). }
        value := IRLowerAST(ASTLeft[node]);
        last := IRAppendCall(GetFiniRunnerProc, -1, -1, Ord(tyInteger));
        IRIVal[last] := 1;   { statement-level: side-effect call }
        last := IRAppend(IR_TERMINATE, value, -1, -1, AN_HALT, 0);
      end
      else
      begin
        if ASTLeft[node] <> -1 then
        begin
          { `return <variant>` from a function with a SCALAR result: unbox
            before the store, and store with the RESULT symbol's kind — the
            plain path below stored with the variant's own ASTTk, so the
            8-byte load handed back the TAG
            (bug-a-nilpy-variant-element-not-usable-as-scalar). }
          vuExitUnboxed := (CurProc >= 0) and (Procs[CurProc].RetSymIdx >= 0) and
                           (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) and
                           IRVariantUnboxKind(Syms[Procs[CurProc].RetSymIdx].TypeKind);
          if vuExitUnboxed then
            value := IRLowerVariantAsScalar(ASTLeft[node],
                                            Syms[Procs[CurProc].RetSymIdx].TypeKind)
          else if PyProgramMode and (CurProc >= 0) and (Procs[CurProc].RetSymIdx >= 0) and
                  (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) and
                  (Syms[Procs[CurProc].RetSymIdx].TypeKind = tyClass) then
          begin
            { `return <variant>` from an Optional[class] function (`return
              self.d.get(k)`, whose 1-arg get yields a variant None or a boxed
              object): unbox to the object POINTER via pyvarobj (nil for None), so
              the tyClass result holds a real handle and `is None` works. Without
              it the variant's 8-byte tag was returned as the class pointer
              (bug-nilpy-variant-return-to-class-result). }
            vuArgProc := FindProc('pyvarobj');
            if vuArgProc < 0 then Error('variant->class return: pyvarobj not loaded');
            vuArgAddr := IRVariantAddr(ASTLeft[node]);
            vuArgNode := IRAppend(IR_ARG, vuArgAddr, -1, -1, 0, Ord(tyVariant));
            value := IRAppendCall(vuArgProc, vuArgNode, -1, Ord(tyPointer));
          end
          else if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) then
            { PROMOTABLE INT result value: its rvalue is the frame SLOT ADDRESS,
              so the generic lowering must not run — the Result stores below go
              through the promo runtime (box to a variant Result / wrap to an
              ordinal one), mirroring the AN_ASSIGN promo arms. Left unhandled,
              the caller received a dead frame's slot address as the value
              (uforth /STRING -> wild jump through the word list). }
            value := -1
          else
          value := IRLowerAST(ASTLeft[node]);
          { A C function returning `char*` (any pointer) that returns a string
            literal must yield the char data at Offset+8, not the frozen string's
            length prefix — the same +8 decay the call-argument and assign paths
            apply. Without it `const char *ver(void){ return "1.3.1"; }` returns a
            pointer at the length byte, so ver()[0] is 5 not '1' (zlib's version
            check). C-mode only; Pascal self-build unaffected. }
          if CProgramMode and (ASTKind[ASTLeft[node]] = AN_STR_LIT) and
             (CurProc >= 0) and (Procs[CurProc].RetType = tyPointer) then
            value := IRAppend(IR_BINOP, value,
                              IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                              Ord(tkPlus), 0, Ord(tyPointer));
          if (CurProc >= 0) and (Procs[CurProc].RetSymIdx >= 0) then
          begin
            varIdx := Procs[CurProc].RetSymIdx;
            if Syms[varIdx].TypeKind = tySet then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              last := IRAppend(IR_SET_COPY, leftAddr, value, -1, 0, Ord(tySet));
            end
            else if Syms[varIdx].TypeKind = tyRecord then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              { COPY_REC needs the SOURCE ADDRESS. For an lvalue record source
                IRLowerAST would emit IR_LOAD_SYM (first 8 bytes loaded as a
                value), which COPY_REC would then misread as a pointer and
                segfault. Take its address instead, mirroring assignment. }
              rhsIsLValue := (ASTKind[ASTLeft[node]] = AN_IDENT) or
                             (ASTKind[ASTLeft[node]] = AN_FIELD) or
                             (ASTKind[ASTLeft[node]] = AN_INDEX) or
                             (ASTKind[ASTLeft[node]] = AN_DEREF);
              if rhsIsLValue then
                right := IRLowerAddress(ASTLeft[node])
              else
                right := value;
              { feature-a-typeref-migrate-consumers lane 1: read via SymTR[varIdx].RecId
                (kept in sync with Syms[varIdx].RecName by SymSyncTypeRef) instead of
                the old parallel field directly. }
              if RecordHasManagedFields(SymTR[varIdx].RecId) then
                last := IRAppend(IR_COPY_REC_MANAGED, leftAddr, right,
                                 SymTR[varIdx].RecId,
                                 RecSize(SymTR[varIdx].RecId), Ord(tyRecord))
              else
                last := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                                 RecSize(SymTR[varIdx].RecId), Ord(tyRecord));
            end
            else if Syms[varIdx].TypeKind = tyVariant then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) then
              begin
                { promo -> variant Result: box (inline -> VT_INT64, heap ->
                  VT_PROMO), the same lowering the AN_ASSIGN variant-target
                  promo arm uses. Statement-marked or codegen skips it. }
                last := IRPromoCall('PXXPromoToVariant', leftAddr,
                                    IRPromoAddrOf(ASTLeft[node]), -1, tyUnknown);
                IRMarkStatementNode(last);
              end
              else if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
              begin
                rhsIsLValue := (ASTKind[ASTLeft[node]] = AN_IDENT) or
                               (ASTKind[ASTLeft[node]] = AN_FIELD) or
                               (ASTKind[ASTLeft[node]] = AN_INDEX) or
                               (ASTKind[ASTLeft[node]] = AN_DEREF);
                if rhsIsLValue then
                  right := IRLowerAddress(ASTLeft[node])
                else
                  right := value;
                last := IRAppend(IR_VAR_STORE, leftAddr, right, Ord(tyVariant), 0, Ord(tyVariant));
              end
              else
              begin
                last := IRAppend(IR_VAR_STORE, leftAddr, value,
                                 Ord(IntToTypeKind(ASTTk[ASTLeft[node]])), 0, Ord(tyVariant));
              end;
            end
            else if (Syms[varIdx].TypeKind = tyClass) and
                    NilPyUserCode then
            begin
              { Returning an object TRANSFERS ownership to the caller
                (feature-nilpy-object-reclamation slice 4): take +1 here,
                because a returned local's own ref dies in the callee's
                scope-exit release right after this. Call results are
                therefore OWNED at the caller, which must not retain them
                again (see the AN_ASSIGN arm). Guarded + magic-checked in
                the Pascal callee, so sentinels and Pascal instances no-op.
                The value must round-trip through a temp — re-emitting an IR
                value node re-evaluates its subtree (the b346 landmine). }
              seq := AllocVar('', tyPointer);
              IRAppend(IR_STORE_SYM, seq, value, -1, 0, Ord(tyPointer));
              { ...but only when the returned expression is a BORROW. A
                construction or another call's result is already owned and has
                no local binding, so nothing balances a second +1. }
              if not IRNodeYieldsOwnedRef(ASTLeft[node]) then
              begin
                procIdx := FindProc('PXXObjRetain');
                if procIdx < 0 then Error('Nil Python: PXXObjRetain (builtinheap) not loaded');
                first := IRAppend(IR_ARG,
                           IRAppend(IR_LOAD_SYM, seq, -1, -1, 0, Ord(tyPointer)),
                           -1, -1, 0, Ord(tyPointer));
                last := IRAppendCall(procIdx, first, -1, Ord(tyUnknown));
                IRIVal[last] := 1;
              end;
              last := IRAppend(IR_STORE_SYM, varIdx,
                        IRAppend(IR_LOAD_SYM, seq, -1, -1, 0, Ord(tyPointer)),
                        -1, 0, Ord(Syms[varIdx].TypeKind));
            end
            else if vuExitUnboxed then
              last := IRAppend(IR_STORE_SYM, varIdx, value, -1, 0,
                               Ord(Syms[varIdx].TypeKind))
            else if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[node]])) and
                    TypeIsOrdinal(Syms[varIdx].TypeKind) then
              { promo -> concrete-int Result: two's-complement wrap mod 2^64,
                the same narrowing the AN_ASSIGN store applies. }
              last := IRAppend(IR_STORE_SYM, varIdx,
                               IRPromoCall('PXXPromoToInt64Wrap',
                                           IRPromoAddrOf(ASTLeft[node]), -1, -1, tyInt64),
                               -1, 0, Ord(Syms[varIdx].TypeKind))
            else
              last := IRAppend(IR_STORE_SYM, varIdx, value, -1, 0, ASTTk[ASTLeft[node]]);
          end;
        end;
        IRLowerCleanupToDepth(0);
        last := IRAppend(IR_TERMINATE, -1, -1, -1, AN_EXIT, 0);
      end;
      if beforeCount < last then
        Result := IRAppend(IR_BLOCK, beforeCount, last, -1, 0, 0)
      else
        Result := last;
    end;

    AN_CALL:
    begin
      first := -1;
      last := -1;
      cpi := ASTIVal[node];
      item := ASTLeft[node];
      { Inline expansion (feature-inline-routines, -O2): splice a retained inline
        body in place of the call when the target is inline-eligible and all args
        are side-effect-free. Falls through to a normal call if IRInlineExpand
        declines (-1). A spliced body's inner calls may re-inline ONE level
        (InliningActive < 2, -O3): safe under the IRInlineExpand reentrancy
        contract (locals-first binding, globals only in the clone window);
        depth stays bounded and self-recursion terminates (level 2 lowers as
        a real call). -O2 keeps depth 0.
        FrameIntrinsicUsed disables the non-leaf cases: once a unit walks the
        saved-fp chain (get_frame / get_pc_addr / get_caller_stackinfo), the
        PHYSICAL frame count between a walker and its target is observable, and
        splicing a body away deletes a frame — so a body that itself uses an
        intrinsic, or that calls anything (which may reach one), stays a real
        call. Leaf retained bodies still inline: they add no frame to delete. }
      if (OptLevel >= 2) and (cpi >= 0) and (cpi < MAX_PROCS) and
         (InlineBodyRoot[cpi] >= 0) and
         (not (FrameIntrinsicUsed and
               (ProcFrameSensitive[cpi] or InlineBodyHasCall[cpi]))) and
         ((InliningActive = 0) or ((OptLevel >= 3) and (InliningActive < 2))) then
      begin
        outNode := IRInlineExpand(node, cpi);
        if outNode >= 0 then begin Result := outNode; Exit; end;
      end;
      { FreeMem on a CLASS instance (the tail of every Free/destroy desugar):
        release the instance's managed fields FIRST, by its RUNTIME class —
        PXXClassFinalize reads the layout descriptor at [[inst]-16] and no-ops
        when there is none. Runs after the user Destroy chain (which the desugar
        sequences before this call) and before the memory is freed, matching
        FPC's FreeInstance timing
        (bug-a-class-managed-fields-not-finalized-on-destroy). The call is NOT
        under the heap lock — the codegen's lock wrap covers only the FreeMem
        emission itself, which is exactly what the interface-release pass needs. }
      if (cpi = -Ord(tkFreeMem)) and (ASTLeft[node] >= 0) and
         (ASTLeft[ASTLeft[node]] >= 0) and
         (IntToTypeKind(ASTTk[ASTLeft[ASTLeft[node]]]) = tyClass) then
      begin
        { Pascal-mode only. In a NilPy compilation the finalize is PXXObjFree's
          job for BOTH populations (see its comment): emitting it here too
          finalized a headered instance twice — once inline, once again through
          PXXObjRelease's rc=0 hook — so every managed field was released twice
          and a caller-owned string died (bug-heap-dict-literal-then-two-parses-
          corrupts). It also finalized an instance that was still referenced,
          since the inline call cannot see the refcount. }
        if not isNilPy then
        begin
          cfPi := FindProc('PXXClassFinalize');
          if cfPi >= 0 then
          begin
            cfArg := IRAppend(IR_ARG, IRLowerAST(ASTLeft[ASTLeft[node]]), -1, -1, 0, Ord(tyPointer));
            cfCall := IRAppendCall(cfPi, cfArg, -1, Ord(tyNativeInt));
            IRIVal[cfCall] := 1;   { statement: emit for effect }
          end;
        end;
        { NilPy compilation: instances are constructed through PXXObjAlloc and
          live at base+16 of their block (feature-nilpy-object-reclamation), so
          the plain FreeMem here would free the wrong base. PXXObjFree
          discriminates by the [inst-8] population tag: headered -> release,
          plain GetMem (an instance a Pascal-mode unit allocated) -> ordinary
          free. Pascal-mode compilations keep the inline FreeMem arm. }
        if isNilPy then
        begin
          cfPi := FindProc('PXXObjFree');
          if cfPi < 0 then Error('Nil Python: PXXObjFree (builtinheap) not loaded');
          cfArg := IRAppend(IR_ARG, IRLowerAST(ASTLeft[ASTLeft[node]]), -1, -1, 0, Ord(tyPointer));
          Result := IRAppendCall(cfPi, cfArg, -1, Ord(tyNativeInt));
          IRIVal[Result] := 1;   { statement: emit for effect }
          Exit;
        end;
      end;
      if cpi = -102 then
      begin
        { SetLength. Nested dynamic arrays (root depth >= 2) take a
          dedicated path operating on the target slot ADDRESS with a depth-aware
          element stride. Plain depth-1 arrays fall through to the generic
          special-call lowering (managed strings/records + COW). }
        slTargetAST := ASTLeft[ASTLeft[node]];
        slCountAST  := ASTLeft[ASTRight[ASTLeft[node]]];
        { Managed AnsiString target reached through a non-symbol lvalue (record/
          class field, var-param field, index, deref): address the slot
          generically and resize via PXXStrSetLen. The address-based op needs no
          symbol reconstruction, so a field works like a plain variable
          (bug-setlength-record-field-via-var-param). A plain symbol target
          (AN_IDENT, incl a by-ref `var s: string` param) keeps the existing
          symbol path — on x86-64 that is the amortized in-place inline resize, so
          string-building stays O(n). Only tyAnsiString reaches here; frozen
          inline strings take the -101 store-length path. }
        if NodeIsManagedString(slTargetAST) and (ASTKind[slTargetAST] <> AN_IDENT) then
        begin
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_STR, slTargetAddr, slCountNode, -1, -1, Ord(tyAnsiString));
          Exit;
        end;
        slRootSym := NodeDynBaseSym(slTargetAST);
        { feature-a-typeref-migrate-consumers lane 1: SymDynDepth read via
          SymTR[..].DynDepth (kept in sync by SymSyncTypeRef). }
        if (slRootSym >= 0) and (SymTR[slRootSym].DynDepth >= 2) then
        begin
          slDepth := NodeDynDepth(slTargetAST);
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode, slDepth,
                             slRootSym, Ord(tyPointer));
          Exit;
        end;
        { Dynamic-array FIELD target (obj.field): no root symbol, so address the
          slot via the field and carry element metadata on the node. Covers any
          depth, including managed-string/record element leaves. }
        if ASTKind[slTargetAST] = AN_FIELD then
        begin
          slFldRec := ResolveNodeRec(ASTLeft[slTargetAST]);
          slFldName := GetASTIdentName(slTargetAST);
          slFldDepth := RecFieldDynDepth(slFldRec, slFldName);
          if slFldDepth > 0 then
          begin
            slFldBaseTk := RecFieldType(slFldRec, slFldName);
            slFldBaseRec := RecFieldRecId(slFldRec, slFldName);
            slTargetAddr := IRLowerAddress(slTargetAST);
            slCountNode := IRLowerAST(slCountAST);
            Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode,
                               slFldDepth, -1, Ord(slFldBaseTk));
            IRSetLenBaseRec[Result] := slFldBaseRec;
            Exit;
          end;
        end;
        { Nested sub-array SLOT reached through a non-array-symbol root — e.g.
          `SetLength(rec.matrix[i], n)`, where `matrix` is an `array of array of
          T` FIELD. The base symbol is the record (dyn depth 0) so the depth>=2
          symbol path above does not fire, and the target is an AN_INDEX (not a
          bare field) so the field path does not either. Use the slot-address
          path with leaf element metadata walked from the dyn-array base
          (NodeDynBaseTk/Rec handle the field+index chain). The array-symbol
          rooted nested case (`m[i]`) is already taken by the depth>=2 branch. }
        if (ASTKind[slTargetAST] = AN_INDEX) and (NodeDynDepth(slTargetAST) >= 1) then
        begin
          slDepth := NodeDynDepth(slTargetAST);
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode, slDepth,
                             -1, Ord(NodeDynBaseTk(slTargetAST)));
          IRSetLenBaseRec[Result] := NodeDynBaseRec(slTargetAST);
          Exit;
        end;
      end;
      { Ord()/Chr() are INTRINSICS (AN_CALL with a negative ASTIVal), dispatched
        before the proc-name hook further down, so a variant argument never
        reached it: `ord(v)` read the variant's first 8 bytes and returned the
        TAG -- ord("q") was 5, not 113. Silent. }
      if PyProgramMode and (cpi = -Ord(tkOrd)) and (ASTLeft[node] <> -1) and
         (IntToTypeKind(ASTTk[ASTLeft[ASTLeft[node]]]) = tyVariant) then
      begin
        procIdx := FindProc('pyord_v');
        if procIdx < 0 then Error('Nil Python: pyord_v (pylib) not loaded');
        value := IRVariantAddr(ASTLeft[ASTLeft[node]]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
        ASTTk[node] := Ord(tyInt64);
        Result := IRAppendCall(procIdx, argNode, -1, Ord(tyInt64));
        Exit;
      end;
      if cpi = -200 then
      begin
        { Nil Python int(). There was no lowering at all, so every argument fell
          through and int("42") handed back the string's POINTER
          (bug-a-nilpy-int-of-string-returns-a-pointer). }
        argVal := ASTLeft[item];
        argTk := IntToTypeKind(ASTTk[argVal]);
        if argTk = tyVariant then
        begin
          { pyint_v, not VariantToInt64: the variant may hold an
            arbitrary-precision int, and VariantToInt64 ABORTS on one
            (EVariantError, "does not fit an Int64") rather than answering the
            identity Python answers. pyint_v passes such a payload through and
            boxes everything else, so the result is a variant — which is what
            the parser now types this call (bug-nilpy-int-of-a-variant-held-
            bignum-raises). }
          procIdx := FindProc('pyint_v');
          if procIdx < 0 then Error('int: pyint_v (pylib) not loaded');
          value := IRVariantAddr(argVal);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(tyVariant));
          Exit;
        end;
        if argTk = tyChar then
        begin
          { A ONE-character literal is tyChar, not a string -- int("0") would
            otherwise fall through to the identity path and yield the character
            CODE, 48. Widen to a string and parse it like any other. }
          procIdx := FindProc('pystr_ofchar');
          if procIdx < 0 then Error('int: pystr_ofchar (pylib) not loaded');
          value := IRLowerAST(argVal);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyChar));
          value := IRAppendCall(procIdx, argNode, -1, Ord(tyAnsiString));
          procIdx := FindProc('pystr_to_int');
          if procIdx < 0 then Error('int: pystr_to_int (pylib) not loaded');
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(tyInt64));
          Exit;
        end;
        if ((argTk = tyString) or (argTk = tyAnsiString)) and
           TypeIsPromoInt(IntToTypeKind(ASTTk[node])) then
        begin
          { ...and the ARBITRARY-PRECISION form the parser now types this call
            as: the digits are data, so the only honest result type is one with
            no width. Produces a promo SLOT, whose address IS the value of a
            promo-typed expression here (see IRPromoAddrOf). }
          procIdx := FindProc('pystr_to_promo');
          if procIdx < 0 then Error('int: pystr_to_promo (pylib) not loaded');
          promoDst := IRPromoTempSlot(promoSym);
          value := IRLowerCallArg(procIdx, 1, argVal, Procs[procIdx].Params[1].IsRef);
          argNode := IRAppend(IR_ARG, promoDst, -1, -1, 0, Ord(tyPointer));
          value := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
          IRB[argNode] := value;
          IRMarkStatementNode(IRAppendCall(procIdx, argNode, -1, Ord(tyUnknown)));
          Result := IRAppend(IR_SLOTADDR, promoSym, -1, -1, 0, Ord(tyPointer));
          Exit;
        end;
        if (argTk = tyString) or (argTk = tyAnsiString) then
        begin
          { int("42") parses the TEXT. pystr_to_int reports a Python-shaped
            ValueError on junk rather than yielding a silent 0. }
          procIdx := FindProc('pystr_to_int');
          if procIdx < 0 then Error('int: pystr_to_int (pylib) not loaded');
          value := IRLowerCallArg(procIdx, 0, argVal, Procs[procIdx].Params[0].IsRef);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(tyInt64));
          Exit;
        end;
        { int(int) / int(bool) are already the value. int(float) never reaches
          here -- the parser routes it to the -203 Trunc intrinsic. }
        Result := IRLowerAST(argVal);
        Exit;
      end;
      if cpi = -201 then
      begin
        argVal := ASTLeft[item];
        argTk := IntToTypeKind(ASTTk[argVal]);
        { A string is already its own str(); a Boolean must print Python's
          True/False, not 1/0. Both went through the numeric formatter and
          produced a pointer and a digit respectively
          (bug-a-nilpy-str-of-string-and-bool). pystr_of already spells every
          type the Python way for f-strings -- reuse it rather than grow the
          intrinsic, picking the overload by ARGUMENT TYPE. }
        if (argTk = tyString) or (argTk = tyAnsiString) or (argTk = tyBoolean) or
           (argTk = tyChar) then
        begin
          if (argTk = tyString) or (argTk = tyAnsiString) then
            procIdx := IRFindProc1ByArgTk('pystr_of', tyAnsiString)
          else
            procIdx := IRFindProc1ByArgTk('pystr_of', argTk);
          if procIdx < 0 then Error('str: pystr_of (pylib) overload not found');
          value := IRLowerCallArg(procIdx, 0, argVal, Procs[procIdx].Params[0].IsRef);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(Procs[procIdx].RetType));
          Exit;
        end;
        if argTk = tyVariant then
        begin
          { pystr_of's Variant overload spells Python's True/False for VT_BOOL,
            which VariantToStr has no case for at all and renders as ''. }
          procIdx := -1;
          if PyProgramMode then procIdx := IRFindProc1ByArgTk('pystr_of', tyVariant);
          if procIdx >= 0 then
          begin
            value := IRVariantAddr(argVal);
            argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
            Result := IRAppendCall(procIdx, argNode, -1, Ord(Procs[procIdx].RetType));
            Exit;
          end;
          procIdx := FindProc('VariantToStr');
          if procIdx < 0 then Error('str: VariantToStr builtin not loaded');
          value := IRVariantAddr(argVal);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(tyAnsiString));
          Exit;
        end;
        if TypeIsFloat(argTk) then
        begin
          { str(float): format via the RTL FloatToStr (natural decimal). }
          procIdx := FindProc('FloatToStr');
          if procIdx < 0 then Error('str: builtin unit not loaded');
          value := IRLowerAST(argVal);                       { double bits in rax }
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyDouble));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(Procs[procIdx].RetType));
          Exit;
        end;
        value := IRLowerAST(argVal);

        procIdx := FindProc('StrInt');
        if procIdx < 0 then Error('str: builtin unit not loaded');

        argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
        first := argNode;

        zeroVal := IRAppend(IR_CONST_INT, 0, -1, -1, 0, Ord(tyInteger));
        argNode2 := IRAppend(IR_ARG, zeroVal, -1, -1, 0, Ord(tyInteger));
        IRB[argNode] := argNode2;

        Result := IRAppendCall(procIdx, first, -1, Ord(Procs[procIdx].RetType));
        Exit;
      end;
      { `len(v)` on a VARIANT: len is an OVERLOAD SET (list/dict/bytes/str) and
        a variant matches none, so resolution picked one and dereferenced e.g.
        a string as a list -- a segfault on the most ordinary Python loop,
        since a for-in variable is always a variant. pylen_v dispatches on the
        tag (and, for VT_OBJECT, on the class via `is`).
        (bug-a-len-of-variant-picks-wrong-overload) }
      { ProcUnitIdx <> -1: the call must have bound a UNIT routine. This rewrite
        is keyed on the proc's NAME, so a module-level `def len(x)` that has
        correctly won resolution would still be rewritten to pylib's pylen_v and
        never run — the third name-keyed surface the shadowing work had to
        cover, after the parser intrinsics and the overload demote
        (bug-nilpy-user-def-len-of-a-container-still-binds-the-builtin). }
      if PyProgramMode and (cpi >= 0) and (ProcUnitIdx[cpi] <> -1) and
         (ASTLeft[node] <> -1) and (ASTRight[ASTLeft[node]] = -1) and
         (IntToTypeKind(ASTTk[ASTLeft[ASTLeft[node]]]) = tyVariant) then
      begin
        pvName := '';
        pvTk := tyInt64;
        if Procs[cpi].Name = 'len' then pvName := 'pylen_v'
        else if Procs[cpi].Name = 'list' then
          begin pvName := 'pylist_v'; pvTk := tyClass; end
        else if Procs[cpi].Name = 'bool' then
          begin pvName := 'bool'; pvTk := tyBoolean; end;
        if pvName <> '' then
        begin
          procIdx := FindProc(pvName);
          if procIdx < 0 then Error('Nil Python: ' + pvName + ' (pylib) not loaded');
          { IRLowerCallArg, not IRVariantAddr: a helper that RETURNS a Variant
            needs the call-argument marshalling (hidden destination), which is
            what lets two such calls coexist in one statement. }
          value := IRLowerCallArg(procIdx, 0, ASTLeft[ASTLeft[node]], Procs[procIdx].Params[0].IsRef);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          ASTTk[node] := Ord(pvTk);
          Result := IRAppendCall(procIdx, argNode, -1, Ord(pvTk));
          Exit;
        end;
      end;
      pathIdx := 0;
      classIdx := -1;
      pendBase := PendOAWBCount;   { open-array copy-out writebacks added by this call's args }
      if cpi = -Ord(tkGetMem) then
        classIdx := ASTRight[node];
      { NilPy-user class construction goes through PXXObjAlloc so the instance
        carries the [inst-16] refcount header (rc = 1, owned by whatever binds
        it) — feature-nilpy-object-reclamation, design in
        devdocs/dev/nilpy-object-reclamation.md. Lowered target-independently
        (the AN_METACLASS_NEW idiom: alloc call, VMT stamp via IR_VMTADDR, ctor
        as an ordinary call), replacing the per-backend inline -tkGetMem arm for
        these nodes only. Gate is isNilPy — the WHOLE compilation, units
        included: pylib/pyeval-created instances (keys() results, host-call arg
        lists) escape into user variant slots, and the release paths cannot
        tell populations apart, so every instance in a NilPy program must carry
        the header. The units' manual `.Free` sites (FreeMem on the instance
        pointer — wrong base for a headered block) are converted to
        PXXObjRelease in pyeval; Pascal-mode compilations are untouched. }
      if (cpi = -Ord(tkGetMem)) and (classIdx >= REC_UCLASS_BASE) and
         isNilPy then
      begin
        procIdx := FindProc('PXXObjAlloc');
        if procIdx < 0 then Error('Nil Python: PXXObjAlloc (builtinheap) not loaded');
        { inst := PXXObjAlloc(size). The size arg is the first AN_ARG; ctor
          args hang off it (ASTRight chain), exactly as the inline path reads
          them. }
        value := IRLowerAST(ASTLeft[ASTLeft[node]]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyNativeInt));
        mcInstSym := AllocVar('', tyPointer);
        IRAppend(IR_STORE_SYM, mcInstSym,
                 IRAppendCall(procIdx, argNode, -1, Ord(tyPointer)),
                 -1, 0, Ord(tyPointer));
        { [inst+0] := VMT }
        IRAppend(IR_STORE_MEM,
                 IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
                 IRAppend(IR_VMTADDR, classIdx - REC_UCLASS_BASE, -1, -1, 0, Ord(tyPointer)),
                 -1, 0, Ord(tyPointer));
        { Ctor: the overload the frontend resolved from the arg types, else the
          first Create by name (same policy as IRResolveCtorProc). A class with
          no ctor (bare shell) is legal — alloc + stamp is the whole job. }
        slot := FindUCtorOverloadArgs(classIdx - REC_UCLASS_BASE, ASTRight[ASTLeft[node]]);
        if slot >= 0 then
          cpi := UMthProc_[slot]
        else
        begin
          cpi := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
          if cpi >= 0 then cpi := UMthProc_[cpi];
        end;
        if cpi >= 0 then
        begin
          mcSelfArg := IRAppend(IR_ARG,
                         IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
                         -1, -1, 0, Ord(tyClass));
          first := mcSelfArg; last := mcSelfArg;
          item := ASTRight[ASTLeft[node]];
          pathIdx := 1;
          while item <> -1 do
          begin
            { Param-aware arg lowering + the managed-string temp slot — the
              same shape as AN_METACLASS_NEW's ctor-arg loop, for the same
              reasons (see the comments there). }
            isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
            value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
            argIsManagedTemp :=
              (not isRefArg) and (pathIdx < Procs[cpi].ParamCount) and
              (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
              (ASTKind[ASTLeft[item]] <> AN_IDENT) and
              (ASTKind[ASTLeft[item]] <> AN_FIELD) and
              (ASTKind[ASTLeft[item]] <> AN_INDEX) and
              (ASTKind[ASTLeft[item]] <> AN_DEREF);
            if argIsManagedTemp then
            begin
              hiddenArgSym := AllocVar('', tyAnsiString);
              SymIsHiddenArgTemp[hiddenArgSym] := True;
              { no per-store DEFAULT_MEM — see the arg-temp paths above
                (bug-a-managed-string-arg-temp-leaks-on-loop-reuse) }
              IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
              value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
              argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
            end
            else
              argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
            IRB[last] := argNode;
            last := argNode;
            item := ASTRight[item];
            Inc(pathIdx);
          end;
          { runs for its side effect (fills the instance); result discarded }
          IRMarkStatementNode(IRAppendCall(cpi, first, -1, Ord(tyClass)));
        end;
        Result := IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, ASTTk[node]);
        Exit;
      end;
      while item <> -1 do
      begin
        { NilPy: a tyChar arg (`s[i]`, AN_INDEX/pystr_at) to a string parameter
          is turned into a real 1-char managed string HERE, before argIsManagedTemp
          and the arg-tk are read from ASTLeft[item] — so it joins the owning-arg-
          temp path (released) instead of the raw char being materialised inline by
          codegen with no owner (bug-n-nilpy-char-to-string-arg-leaks). Done in the
          loop, not IRLowerCallArg, because the owning-temp decision reads the
          ORIGINAL arg node. }
        if isNilPy and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           ((Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) or
            (Procs[cpi].Params[pathIdx].TypeKind = tyString)) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyChar) then
          ASTLeft[item] := WrapCharToPyStr(ASTLeft[item]);
        isRefArg := False;
        if cpi >= 0 then
        begin
          if (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef then
            isRefArg := True;
        end
        else
        begin
          specialId := -cpi;
          if specialId = Ord(tkLength) then
          begin
            { Force-address the Length arg only when it is an lvalue (string/array
              variable, field, element): the codegen reads its [-8] header from the
              slot. A non-lvalue string VALUE (a concat / function result) is
              lowered as a value instead — the codegen's tyAnsiString-value path
              reads the length from the handle directly. }
            if pathIdx = 0 then isRefArg := IsASTLValue(ASTLeft[item]);
          end
          else if (specialId = Ord(tkSysRead)) or (specialId = Ord(tkSyswrite)) then
          begin
            if pathIdx = 1 then isRefArg := True;
          end
          else if (specialId = Ord(tkGetMem)) and (pathIdx > 0) then
          begin
            classIdx := ASTRight[node];
            slot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
            if slot >= 0 then
            begin
              slot := UMthProc_[slot];
              if (pathIdx < Procs[slot].ParamCount) and Procs[slot].Params[pathIdx].IsRef then
                isRefArg := True;
            end;
          end;
        end;

        { Length(F()) where F returns a dynamic array: the call result is a heap
          handle (data ptr), not an lvalue, so the force-address path can't fire
          and the value path would deref it as an address ([rax]) and read the
          first element instead of the [-8] count. Bind the handle to a hidden
          dynamic-array local and hand its IR_LEA to the Length codegen — the same
          shape a dyn-array variable produces, so every backend's existing
          dyn-array Length path serves it. See bug-length-of-dynarray-call-result. }
        { Length(ps^) / Length(rec.pf^) over a managed string (ps: ^string): `@s`
          of a managed string yields the HANDLE (the heap data pointer) itself,
          so `ps` holds the handle and `ps^` IS that handle. Its address-lowering
          (IRLowerAddress AN_DEREF) collapses to a bare load of ps tagged
          tyPointer, which the Length codegen's catch-all then derefs once more
          ([handle]) and returns the first data word instead of the [handle-8]
          length (garbage). Lower it instead as the plain handle load retagged
          tyAnsiString: that is the same shape a managed-string VALUE produces, so
          every backend's tyAnsiString Length path (no extra deref -> test ->
          [-8]) serves it with no codegen change. Frozen `ps^` keeps tyString and
          is untouched; managed strings don't exist on ESP so riscv32/xtensa never
          see this. The deref is borrowed (ASTKind AN_DEREF is already excluded
          from the managed-temp owning path above), so no double-free. See
          bug-managed-length-via-pointer-deref. }
        if (cpi < 0) and (-cpi = Ord(tkLength)) and (pathIdx = 0) and
           (ASTKind[ASTLeft[item]] = AN_DEREF) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
        begin
          { `Length(ps^)` where ps: ^string. The commentary above describes the OLD model, in
            which `@s` yielded the HANDLE, so ps held the handle and `ps^` WAS it -- hence
            lowering ps itself and merely retagging it.

            `@s` now yields the address of the VARIABLE (its slot), which is what @ means and
            what makes `ps^` readable and writable at all. So ps is a slot address, and the
            handle must be LOADED from it. Retagging ps without the load returned the length
            of whatever the slot address happened to point at -- 0, in practice. }
          value := IRAppend(IR_LOAD_MEM,
                     IRLowerAST(ASTLeft[ASTLeft[item]]), -1, -1, 0, Ord(tyAnsiString));
        end
        else if (cpi < 0) and (-cpi = Ord(tkLength)) and (pathIdx = 0) and
           (ASTKind[ASTLeft[item]] = AN_CALL) and (ASTIVal[ASTLeft[item]] >= 0) and
           ProcRetIsDynArray[ASTIVal[ASTLeft[item]]] then
        begin
          dynLenPi := ASTIVal[ASTLeft[item]];
          dynLenTmp := AllocVar('', tyPointer);
          Syms[dynLenTmp].IsArray := True;
          Syms[dynLenTmp].ArrLen := -1;
          SymDynDepth[dynLenTmp] := 1;
          Syms[dynLenTmp].ElemType := ProcRetElemTk[dynLenPi];
          Syms[dynLenTmp].ElemRecName := ProcRetElemRec[dynLenPi];
          SymSyncTypeRef(dynLenTmp);
          callVal := IRLowerAST(ASTLeft[item]);
          IRAppend(IR_STORE_SYM, dynLenTmp, callVal, -1, 0, Ord(tyPointer));
          value := IRAppend(IR_LEA, dynLenTmp, -1, -1, 0, Ord(tyPointer));
        end
        else
        begin
          { A class instantiation `C(args)` is an IR_CALL to GetMem (cpi =
            -tkGetMem), so the arg-coercion in IRLowerCallArg — which keys on the
            callee's param types — never fired for the ctor's own arguments. A
            variant element (`C(lst[0])`) went to a str/scalar ctor param as its
            raw 8-byte tag, storing garbage. Coerce user args (pathIdx>0; the
            size arg at 0 fills self's slot) by the CTOR's param types, the same
            path a normal method call already uses. }
          ctorArgCpi := cpi;
          if (cpi = -Ord(tkGetMem)) and (pathIdx > 0) and
             (classIdx >= REC_UCLASS_BASE) then
          begin
            ctorArgSlot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
            if ctorArgSlot >= 0 then ctorArgCpi := UMthProc_[ctorArgSlot];
          end;
          value := IRLowerCallArg(ctorArgCpi, pathIdx, ASTLeft[item], isRefArg);
        end;

        { A materialised managed-string argument (a literal, concat, char/string
          coercion, or function result — anything that is not an existing lvalue)
          is refcount 1 with no owner, so passing it directly leaks one reference
          per call. Bind it to a hidden owning local and pass that by borrow: the
          local's store releases the previous value (loop reuse) and the epilog's
          managed-local release frees it at scope exit. Only fires under managed
          strings (tyAnsiString exists only with PXX_MANAGED_STRING), so the
          self-hosted compiler build is unaffected.

          The `cpi >= 0` gate excluded constructor calls entirely: a class
          instantiation lowers with cpi = -Ord(tkGetMem) (negative), so a
          string-literal argument to a constructor's `const s: string` param
          never got this materialization -- the raw, un-materialized value
          reached codegen tagged with its ORIGINAL (frozen tyString) type
          instead of a real managed handle, which every backend's by-value
          call-arg path then pushed as if it were already a heap pointer.
          Symptom: `Exception.Create('literal')` and any other constructor
          taking a string-literal argument read back an empty/garbage
          message field on EVERY target that supports managed strings (not
          just one backend -- confirmed on arm32/aarch64/i386 before finding
          this was the shared root cause, not a per-backend codegen gap).
          `slot` (the constructor's own proc index) is resolved fresh in the
          same iteration by the isRefArg block above, only when
          `-cpi = Ord(tkGetMem)` and `pathIdx > 0` (the SIZE pseudo-arg at
          pathIdx=0 is excluded, matching that block's own guard exactly, so
          this never reads slot from a stale earlier iteration). }
        argIsManagedTemp :=
          (not isRefArg) and
          (((cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
            (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString)) or
           ((cpi < 0) and (-cpi = Ord(tkGetMem)) and (pathIdx > 0) and
            (slot >= 0) and (pathIdx < Procs[slot].ParamCount) and
            (Procs[slot].Params[pathIdx].TypeKind = tyAnsiString))) and
          (ASTKind[ASTLeft[item]] <> AN_IDENT) and
          (ASTKind[ASTLeft[item]] <> AN_FIELD) and
          (ASTKind[ASTLeft[item]] <> AN_INDEX) and
          { A managed-string DEREF value (`p^`, p: ^AnsiString) is normally a
            borrow (excluded), but under isNilPy passing it directly to a
            `const AnsiString` param leaks one handle per call — the isNilPy
            arg lowering materialises an unowned copy that never releases
            (bug-a-nilpy-managed-deref-to-const-arg-leaks; plain Pascal `p^`-
            to-const is clean, so this fires under isNilPy only). Route it
            through the owning-temp path instead: the hidden local's STORE
            retains a proper +1 (release-of-old on loop reuse) and scope exit
            frees it — exactly the `mn := p^` bind the hot call sites used. }
          ((ASTKind[ASTLeft[item]] <> AN_DEREF) or isNilPy);

        { Auto const char* marshalling: a string argument passed to a Pointer
          parameter gets the same +8 length-prefix skip as an explicit PChar()
          cast, so C bindings pass a Pascal string without PChar() boilerplate.
          The string data at Offset+8 is NUL-terminated by InternStr. }
        if (not isRefArg) and (cpi >= 0) and
           (IntToTypeKind(IRTk[value]) = tyString) and
           (((pathIdx < Procs[cpi].ParamCount) and
             (Procs[cpi].Params[pathIdx].TypeKind = tyPointer)) or
            (ProcVariadic[cpi] and (pathIdx >= Procs[cpi].ParamCount))) then
        begin
          { A string passed to a Pointer param OR as a variadic arg (the callee's
            va_arg(char*) wants C char data, not the Pascal length prefix) gets the
            +8 length-prefix skip. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
          value := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        end
        else if (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
          { A managed string arg to a Pointer (const char*) param: the tyAnsiString
            value is ALREADY a char pointer (no inline length prefix), so pass it
            as-is — the dual of the frozen tyString +8 skip above. Scalar `string`
            resolves to tyAnsiString in managed mode, so this is the common path. }
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer))
        else if argIsManagedTemp then
        begin
          { Nil-init is handled ONCE at body head (BSS for main-body skGlobal,
            the codegen-prologue SymIsHiddenArgTemp pass for in-proc skLocal), so
            the STORE below sees a valid handle on every loop reuse and its
            release-of-old frees the previous iteration's materialised string.
            A per-store IR_DEFAULT_MEM here re-zeroed the slot before the STORE,
            dropping (leaking) that handle every iteration
            (bug-a-managed-string-arg-temp-leaks-on-loop-reuse). }
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { Default parameters: a call that omitted trailing args supplies each
        remaining param's constant default (ordinal/char/bool/enum, or a string
        literal). MatchProcCall already accepted the shorter arity
        (ProcArityMatches). }
      cpi := ASTIVal[node];
      if cpi >= 0 then
        while (pathIdx < Procs[cpi].ParamCount) and (pathIdx < MAX_PROC_PARAMS) and
              ProcParamHasDefault[cpi * MAX_PROC_PARAMS + pathIdx] do
        begin
          { A NilPy VARIANT parameter takes its default the same way it takes a
            written argument: as an AST literal handed to IRLowerCallArg, which
            boxes it into a variant temp and passes the temp's address. Built
            by hand here the value reached the callee as a raw ordinal or a
            frozen string handle, and the callee dereferenced it — a def's
            declared default was never what it actually ran with. }
          { A NON-CONSTANT NilPy default (`b=[]`, `b={}`, `b=w`) lives in a hidden
            global evaluated ONCE where the def statement stands, because that is
            when Python evaluates it — and it is what makes the shared-mutable-
            default idiom accumulate across calls. So the omitted argument READS
            that global; rebuilding a value here would hand out a fresh container
            per call and diverge on the accumulator idiom
            (bug-nilpy-non-constant-parameter-defaults-silently-become-none).
            Checked before every other flavour: the recorded ordinal/None flags
            are meaningless once a symbol is present. }
          if ProcParamDefaultSym[cpi * MAX_PROC_PARAMS + pathIdx] >= 0 then
          begin
            dfltAST := AllocNode(AN_IDENT);
            ASTIVal[dfltAST] := ProcParamDefaultSym[cpi * MAX_PROC_PARAMS + pathIdx];
            ASTTk[dfltAST] := Ord(Syms[ProcParamDefaultSym[cpi * MAX_PROC_PARAMS + pathIdx]].TypeKind);
            value := IRLowerCallArg(cpi, pathIdx, dfltAST, False);
            argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[dfltAST]);
          end
          else if (Procs[cpi].Params[pathIdx].TypeKind = tyVariant) and
             (not Procs[cpi].Params[pathIdx].IsArray) then
          begin
            if ProcParamDefaultIsFloat[cpi * MAX_PROC_PARAMS + pathIdx] then
          begin
            { a FLOAT default: the stored ordinal is its IEEE 754 bits }
            dfltAST := AllocNode(AN_FLOAT_LIT);
            ASTIVal[dfltAST] := ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx];
            ASTTk[dfltAST] := Ord(tyDouble);
            value := IRLowerCallArg(cpi, pathIdx, dfltAST, False);
          end
          else if ProcParamDefaultIsNone[cpi * MAX_PROC_PARAMS + pathIdx] then
            begin
              { `= None` is not the ordinal 0 it is recorded as. pynone()
                yields the empty variant, and its result needs a slot of its
                own: an rvalue has no address, and the parameter is passed by
                one. }
              dfltAST := AllocNode(AN_CALL);
              ASTIVal[dfltAST] := FindProc('pynone');
              if ASTIVal[dfltAST] < 0 then Error('Nil Python: pylib (pynone) not loaded');
              ASTTk[dfltAST] := Ord(tyVariant);
              ASTLeft[dfltAST] := -1;
              dfltSym := AllocVar('', tyVariant);
              dfltIdent := AllocNode(AN_IDENT);
              ASTIVal[dfltIdent] := dfltSym;
              ASTTk[dfltIdent] := Ord(tyVariant);
              dfltAsgn := AllocNode(AN_ASSIGN);
              ASTLeft[dfltAsgn] := dfltIdent;
              ASTRight[dfltAsgn] := dfltAST;
              IRLowerAST(dfltAsgn);
              value := IRAppend(IR_LEA, dfltSym, -1, -1, 0, Ord(tyVariant));
            end
            else
            begin
              if ProcParamDefaultIsStr[cpi * MAX_PROC_PARAMS + pathIdx] then
              begin
                dfltAST := AllocNode(AN_STR_LIT);
                ASTSOffset[dfltAST] := ProcParamDefaultSOff[cpi * MAX_PROC_PARAMS + pathIdx];
                ASTSLen[dfltAST] := ProcParamDefaultSLen[cpi * MAX_PROC_PARAMS + pathIdx];
                ASTTk[dfltAST] := Ord(tyString);
              end
              else if ProcParamDefaultIsBool[cpi * MAX_PROC_PARAMS + pathIdx] then
              begin
                { `b=True` is recorded as the ordinal 1; boxed as an INTEGER the
                  variant prints 1 instead of True. }
                dfltAST := AllocNode(AN_BOOL_LIT);
                ASTIVal[dfltAST] := ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx];
                ASTTk[dfltAST] := Ord(tyBoolean);
              end
              else
              begin
                dfltAST := AllocNode(AN_INT_LIT);
                ASTIVal[dfltAST] := ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx];
                ASTTk[dfltAST] := Ord(tyInteger);
              end;
              value := IRLowerCallArg(cpi, pathIdx, dfltAST, False);
            end;
            argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          end
          else if ProcParamDefaultIsStr[cpi * MAX_PROC_PARAMS + pathIdx] then
          begin
            { The default is a FROZEN literal (inline length prefix). A managed
              `string` param expects an AnsiString, so it needs the same hidden
              managed temp an explicitly-written literal arg gets above —
              IR_STORE_SYM performs the frozen -> managed conversion. Handing the
              raw literal over instead makes Length() read the prefix as data. }
            value := IRAppend(IR_CONST_STR, ProcParamDefaultSOff[cpi * MAX_PROC_PARAMS + pathIdx],
                              ProcParamDefaultSLen[cpi * MAX_PROC_PARAMS + pathIdx], -1, 0,
                              Ord(tyString));
            if Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString then
            begin
              hiddenArgSym := AllocVar('', tyAnsiString);
              SymIsHiddenArgTemp[hiddenArgSym] := True;
              { no per-store DEFAULT_MEM — see the arg-temp paths above
                (bug-a-managed-string-arg-temp-leaks-on-loop-reuse) }
              IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
              value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
              argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
            end
            else
              argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyString));
          end
          else if ProcParamDefaultIsFloat[cpi * MAX_PROC_PARAMS + pathIdx] then
          begin
            { a float literal is IR_CONST_INT carrying the IEEE bits, tagged
              tyDouble — the same lowering AN_FLOAT_LIT gets }
            value := IRAppend(IR_CONST_INT, -1, -1, -1,
                              ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx],
                              Ord(tyDouble));
            argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyDouble));
          end
          else if ProcParamDefaultIsSet[cpi * MAX_PROC_PARAMS + pathIdx] then
            { A SET default (`Options: TFormatOptions = DefaultFormat`). The value is not
              an ordinal: it is the Data[] OFFSET of the 32-byte mask baked at the
              declaration, so it must yield the mask's ADDRESS (IR_SET_LIT) -- exactly what
              a set literal written at the call site yields. Emitting IR_CONST_INT here
              passed the OFFSET itself as if it were the set, and the callee dereferenced
              it. }
            argNode := IRAppend(IR_ARG,
              IRAppend(IR_SET_LIT, -1, -1, -1, ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx],
                       Ord(tySet)),
              -1, -1, 0, Ord(tySet))
          else
            argNode := IRAppend(IR_ARG,
              IRAppend(IR_CONST_INT, -1, -1, -1, ProcParamDefaultVal[cpi * MAX_PROC_PARAMS + pathIdx],
                       Ord(Procs[cpi].Params[pathIdx].TypeKind)),
              -1, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
          if first < 0 then first := argNode else IRB[last] := argNode;
          last := argNode;
          Inc(pathIdx);
        end;
      if ASTLiftedVar[node] >= 0 then
      begin
        callRetType := Procs[ASTIVal[node]].RetType;
        callVal := IRAppendCall(ASTIVal[node], first, classIdx, Ord(callRetType));
        IRIVal[callVal] := 1;
        { The call ran for its side effect on the lifted var; the node's VALUE is that var.
          A RECORD is carried by ADDRESS in this IR, so it must be an IR_LEA — loading it
          like a scalar yields the first 8 bytes and any consumer then copies from a garbage
          address (an advanced-record constructor, `p := TPt.Create(3,4)`, segfaulted on
          exactly this). The interface path is unaffected: it tags the node tyPointer, and a
          fat interface pointer really is a value. }
        if IntToTypeKind(ASTTk[node]) = tyRecord then
          Result := IRAppend(IR_LEA, ASTLiftedVar[node], -1, -1, 0, Ord(tyPointer))
        else
          Result := IRAppend(IR_LOAD_SYM, ASTLiftedVar[node], -1, -1, 0, ASTTk[node]);
      end
      else
        Result := IRAppendCall(ASTIVal[node], first, classIdx, ASTTk[node]);
      { Class instantiation: carry the ctor the FRONTEND picked from the argument
        types. Backends resolve the ctor with a first-name-match that cannot see
        overloads, so without this an overloaded ctor set always ran whichever
        Create was declared first (bug-pascal-ctor-overload-first-match). The ctor
        args hang off the size arg: ASTLeft[node] = size AN_ARG, its ASTRight = the
        ctor arg list. }
      if (cpi = -Ord(tkGetMem)) and (classIdx >= REC_UCLASS_BASE) and
         (ASTLeft[node] >= 0) then
      begin
        slot := FindUCtorOverloadArgs(classIdx - REC_UCLASS_BASE, ASTRight[ASTLeft[node]]);
        if slot >= 0 then IRCtorProc[Result] := UMthProc_[slot];
      end;
      { copy-OUT the open-array writebacks this call's args registered (a static
        array passed to a `var`/`out` open-array param): temp data -> static
        array, after the call. Emitted by the linear IR_COPY_REC driver in append
        order, so it runs after the call. A function result lives in rax/xmm0 at
        this point and the COPY_REC would clobber it, so spill it to a temp before
        the writeback and reload it afterwards (the reload node has a higher index
        and therefore emits after the COPY_REC). }
      if PendOAWBCount > pendBase then
      begin
        if Procs[ASTIVal[node]].IsFunc then
        begin
          value := AllocVar('', IntToTypeKind(ASTTk[node]));
          IRAppend(IR_STORE_SYM, value, Result, -1, 0, ASTTk[node]);
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              PendOAWBSrcAddr(PendOAWBTemp[PendOAWBCount]),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
          Result := IRAppend(IR_LOAD_SYM, value, -1, -1, 0, ASTTk[node]);
        end
        else
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              PendOAWBSrcAddr(PendOAWBTemp[PendOAWBCount]),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
      end;
      { {$I+}: a Text-I/O call inside the region gets PXXIoCheck sequenced
        right after it — raises EInOutError (sysutils hook) / halts with the
        IO code when the operation failed (feature-pascal-io-checks-i-plus). }
      if ASTIChk[node] and IRIoCheckedCallee(cpi) then
      begin
        item := FindProc('PXXIoCheck');
        if item >= 0 then
          IRIVal[IRAppendCall(item, -1, -1, Ord(tyUnknown))] := 1;
      end;
    end;

    AN_CALL_IND:
    begin
      { Indirect call through a proc-typed value. Marshal args by the signature
        (ASTIVal = signature Procs[] index) and emit IR_CALL_IND (IRA = callee
        code address, IRB = args, IRIVal = sig, IRC = extra leading Self args:
        0 for a plain proc pointer, 1 for a method pointer). A method pointer is
        a 16-byte {Code@0, Data@8} record: load Self (Data) as arg0, call Code. }
      cpi := ASTIVal[node];
      first := -1; last := -1;
      pendBase := PendOAWBCount;   { open-array copy-out writebacks (see AN_CALL) }
      if ASTSLen[node] = 1 then
      begin
        { Method pointer: prepend Self loaded from the record's Data field. }
        leftAddr := IRLowerAddress(ASTRight[node]);          { addr of {Code,Data} }
        right := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
        outNode := IRAppend(IR_BINOP, leftAddr, right, Ord(tkPlus), 0, Ord(tyPointer));
        value := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer)); { Self = [addr+ptrsize] }
        first := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        last := first;
      end;
      item := ASTLeft[node];
      pathIdx := 0;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        { Same auto const char* marshalling the direct AN_CALL path applies: a
          frozen string literal handed to a Pointer param (or a variadic slot)
          needs the +8 length-prefix skip so the callee sees char data, not the
          Pascal length word. A managed string is already a char pointer, so it
          passes as-is. Without this, `p("literal")` through a `char*` function
          pointer passed the length prefix and the callee printed nothing. }
        if (not isRefArg) and (cpi >= 0) and
           (IntToTypeKind(IRTk[value]) = tyString) and
           (((pathIdx < Procs[cpi].ParamCount) and
             (Procs[cpi].Params[pathIdx].TypeKind = tyPointer)) or
            (ProcVariadic[cpi] and (pathIdx >= Procs[cpi].ParamCount))) then
        begin
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
          value := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        end
        else if (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer))
        else if (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
           (ASTKind[ASTLeft[item]] <> AN_IDENT) and
           (ASTKind[ASTLeft[item]] <> AN_FIELD) and
           (ASTKind[ASTLeft[item]] <> AN_INDEX) and
           { isNilPy: own a `p^` managed-string arg — see the identical clause
             above (bug-a-nilpy-managed-deref-to-const-arg-leaks). }
           ((ASTKind[ASTLeft[item]] <> AN_DEREF) or isNilPy) then
        begin
          { materialised managed-string arg through a proc variable: hidden
            owning local, pass by borrow — see AN_CALL / AN_VIRTUAL_CALL }
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          { No per-store IR_DEFAULT_MEM: the slot is nil-init'd ONCE at body head
            (SymIsHiddenArgTemp codegen pass / BSS), so STORE_SYM's release-of-old
            frees the previous iteration's materialised handle on every loop reuse.
            A per-store zero re-leaked it every trip
            (bug-a-managed-string-arg-temp-leaks-on-loop-reuse — same fix as the
            direct AN_CALL path, extended here to the CALL_IND / INTF_CALL /
            VIRTUAL_CALL / METACLASS_NEW arg paths). }
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      if ASTSLen[node] = 1 then
        { callee = Code field (record base address, offset 0). }
        callVal := IRAppend(IR_LOAD_MEM, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer))
      else
        callVal := IRLowerAST(ASTRight[node]);   { plain: load the code-address value }
      Result := IRAppend(IR_CALL_IND, callVal, first, ASTSLen[node], cpi, ASTTk[node]);
      if ABIRetViaHiddenDestProc(cpi) then
        IRCallDest[Result] := IRBuildHiddenDest(cpi);
      { copy-OUT the var/out open-array writebacks this call's args registered —
        the direct AN_CALL path already flushes these; the indirect path never
        did, so a static array / record field passed to a `var` open-array param
        through a proc VARIABLE silently lost the callee's writes (synacode's
        Transform(State, BufLong) — the MD5 wall). Same function-result spill
        discipline as AN_CALL. }
      if PendOAWBCount > pendBase then
      begin
        if (cpi >= 0) and Procs[cpi].IsFunc then
        begin
          value := AllocVar('', IntToTypeKind(ASTTk[node]));
          IRAppend(IR_STORE_SYM, value, Result, -1, 0, ASTTk[node]);
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              PendOAWBSrcAddr(PendOAWBTemp[PendOAWBCount]),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
          Result := IRAppend(IR_LOAD_SYM, value, -1, -1, 0, ASTTk[node]);
        end
        else
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              PendOAWBSrcAddr(PendOAWBTemp[PendOAWBCount]),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
      end;
    end;

    AN_INTF_CALL:
    begin
      { CORBA interface call. The interface value is a fat pointer {IMT@0,
        instance@8}. Self = [iface+8] (prepended like a method-pointer call);
        code = [[iface+0] + slot*8]. Marshal explicit args by the signature. }
      cpi := ASTIVal[node];
      { An interface value is ONE pointer: the instance. Self = [iface]. }
      intfCallCi := ResolveNodeRec(ASTRight[node]) - REC_UCLASS_BASE;
      intfSelfSym := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, intfSelfSym,
               IRAppend(IR_LOAD_MEM, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer)),
               -1, 0, Ord(tyPointer));
      { imt := PXXIntfIMTOf(self, intfCi) — resolved from the instance's RTTI blob,
        which is what lets the VALUE stay a single pointer. Done BEFORE the explicit
        args are marshalled so the helper call cannot clobber them. }
      intfImtSym := AllocVar('', tyPointer);
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, intfSelfSym, -1, -1, 0, Ord(tyPointer)),
                        -1, -1, 0, Ord(tyPointer));
      argNode := IRAppend(IR_ARG, IRAppend(IR_CONST_INT, -1, -1, -1, intfCallCi, Ord(tyNativeInt)),
                          -1, -1, 0, Ord(tyNativeInt));
      IRB[first] := argNode;
      IRAppend(IR_STORE_SYM, intfImtSym,
               IRAppendCall(FindProc('PXXIntfIMTOf'), first, -1, Ord(tyPointer)),
               -1, 0, Ord(tyPointer));

      value := IRAppend(IR_LOAD_SYM, intfSelfSym, -1, -1, 0, Ord(tyPointer));
      first := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
      last := first;
      { explicit args: signature params 1.. (param 0 is Self) }
      item := ASTLeft[node];
      pathIdx := 1;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        argIsManagedTemp :=
          (not isRefArg) and (pathIdx < Procs[cpi].ParamCount) and
          (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
          (ASTKind[ASTLeft[item]] <> AN_IDENT) and
          (ASTKind[ASTLeft[item]] <> AN_FIELD) and
          (ASTKind[ASTLeft[item]] <> AN_INDEX) and
          { A managed-string DEREF value (`p^`, p: ^AnsiString) is normally a
            borrow (excluded), but under isNilPy passing it directly to a
            `const AnsiString` param leaks one handle per call — the isNilPy
            arg lowering materialises an unowned copy that never releases
            (bug-a-nilpy-managed-deref-to-const-arg-leaks; plain Pascal `p^`-
            to-const is clean, so this fires under isNilPy only). Route it
            through the owning-temp path instead: the hidden local's STORE
            retains a proper +1 (release-of-old on loop reuse) and scope exit
            frees it — exactly the `mn := p^` bind the hot call sites used. }
          ((ASTKind[ASTLeft[item]] <> AN_DEREF) or isNilPy);
        if argIsManagedTemp then
        begin
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          { No per-store IR_DEFAULT_MEM: the slot is nil-init'd ONCE at body head
            (SymIsHiddenArgTemp codegen pass / BSS), so STORE_SYM's release-of-old
            frees the previous iteration's materialised handle on every loop reuse.
            A per-store zero re-leaked it every trip
            (bug-a-managed-string-arg-temp-leaks-on-loop-reuse — same fix as the
            direct AN_CALL path, extended here to the CALL_IND / INTF_CALL /
            VIRTUAL_CALL / METACLASS_NEW arg paths). }
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        IRB[last] := argNode; last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { code = [imt + slot*8] }
      value := IRAppend(IR_LOAD_SYM, intfImtSym, -1, -1, 0, Ord(tyPointer));
      right := IRAppend(IR_CONST_INT, -1, -1, -1, ASTSOffset[node] * 8, Ord(tyInteger));
      outNode := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
      callVal := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer));
      { IRC=0: the interface signature's ParamCount already counts Self (param 0),
        and Self is the first node in the arg chain, so no extra injected-Self. }
      Result := IRAppend(IR_CALL_IND, callVal, first, 0, cpi, ASTTk[node]);
      if ABIRetViaHiddenDestProc(cpi) then
        IRCallDest[Result] := IRBuildHiddenDest(cpi);
    end;

    AN_IF:
    begin
      pairNode := ASTRight[node];
      elseLabel := IRNewLabel;
      endLabel := IRNewLabel;
      condNode := IRLowerAST(ASTLeft[node]);
      first := condNode;
      last := IRAppend(IR_JUMP_IF_FALSE, elseLabel, condNode, -1, 0, 0);
      last := IRLowerAST(ASTLeft[pairNode]);
      IRMarkStatementNode(last);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      last := IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      if ASTRight[pairNode] <> -1 then
      begin
        last := IRLowerAST(ASTRight[pairNode]);
        IRMarkStatementNode(last);
      end;
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_INCDEC:
    begin
      { Pre/post ++/--. Evaluate the lvalue ADDRESS exactly once into a hidden
        pointer temp (so `a[i++]++` bumps i once), load the current value, stash
        the OLD value, store old±delta, and yield old (postfix) or the new stored
        value (prefix). Pointer operands step by element size. }
      left := ASTLeft[node];
      if not IsASTLValue(left) then Error('++/-- operand is not an lvalue');
      argTk := IntToTypeKind(ASTTk[left]);
      if argTk = tyUnknown then argTk := tyInteger;
      if argTk = tyPointer then foldK := ASTIVal[node] * IRPointerStride(left)
      else foldK := ASTIVal[node];
      varIdx := AllocVar('', tyPointer);                 { paddr = &lvalue, once }
      IRAppend(IR_STORE_SYM, varIdx, IRLowerAddress(left), -1, 0, Ord(tyPointer));
      slot := AllocVar('', argTk);                       { old value }
      IRAppend(IR_STORE_SYM, slot,
        IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(argTk)), -1, 0, Ord(argTk));
      IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk)),
                 IRAppend(IR_CONST_INT, -1, -1, -1, foldK, Ord(argTk)),
                 Ord(tkPlus), 0, Ord(argTk)), -1, 0, Ord(argTk));
      if ASTSOffset[node] = 1 then
        Result := IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk))   { postfix: old }
      else
        Result := IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                           -1, -1, 0, Ord(argTk));                     { prefix: new }
    end;

    AN_COMPOUND_ASSIGN:
    begin
      { Value-bearing assignment `lv = rhs` and compound `lv OP= rhs`. Lvalue
        address computed ONCE; for compound, current = *paddr, new = current OP
        rhs; store and yield the stored value (so `a = b = c` chains via the
        Right being another AN_COMPOUND_ASSIGN). }
      left := ASTLeft[node];
      if not IsASTLValue(left) then Error('assignment target is not an lvalue');
      argTk := IntToTypeKind(ASTTk[left]);
      if argTk = tyUnknown then argTk := tyInteger;
      varIdx := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, varIdx, IRLowerAddress(left), -1, 0, Ord(tyPointer));
      right := IRLowerAST(ASTRight[node]);
      if ASTIVal[node] = Ord(tkAssign) then
        value := right
      else
        value := IRAppend(IR_BINOP,
          IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(argTk)),
          right, ASTIVal[node], 0, Ord(argTk));
      slot := AllocVar('', argTk);                       { stored value, yielded }
      IRAppend(IR_STORE_SYM, slot, value, -1, 0, Ord(argTk));
      IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
               IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk)), -1, 0, Ord(argTk));
      Result := IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk));
    end;

    AN_COMMA:
    begin
      { C comma operator: evaluate Left for its side effects (discard the value),
        yield Right. Right-nested, so each Left peels one operand off the front. }
      IRDiscardValue(IRLowerAST(ASTLeft[node]));
      Result := IRLowerAST(ASTRight[node]);
    end;

    AN_TERNARY:
    begin
      { Value-bearing conditional `c ? a : b` / `if c then a else b`. Mirror the
        AN_IF control flow but store each arm into one hidden temp and yield a
        load of it — so the selected arm's side effects run (short-circuit) and
        the expression has a value. Scalar/ordinal/pointer/float result types
        (what C ternary and the if-expression yield); a managed-arm form would
        need the retain/release assign path and is deferred (slice 2). }
      pairNode := ASTRight[node];
      argTk := IntToTypeKind(ASTTk[node]);
      if argTk = tyUnknown then argTk := tyInteger;
      { A string-literal arm types as frozen tyString, which has inline [N]
        storage and no usable handle slot for a temp. In Pascal (managed-default)
        carry the result as a managed AnsiString — the per-arm assignment coerces
        the frozen literal into the managed temp and the load yields a real
        handle. In C a string literal is a frozen `char*` address, NOT a managed
        AnsiString; routing it through the ARC assign path builds a garbage
        handle the consumer derefs -> crash (the printf `(k=='X')?"0X":"0x"`
        segfault). So in C mode carry the arm as a plain pointer: the per-arm
        assignment stores the literal's address and the load yields the char*. }
      if argTk = tyString then
      begin
        if CProgramMode then argTk := tyPointer
        else argTk := tyAnsiString;
      end;
      if argTk = tyRecord then LastTypeRecId := ResolveNodeRec(ASTLeft[pairNode]);
      varIdx := AllocVar('', argTk);
      if argTk = tyRecord then
      begin
        Syms[varIdx].RecName := LastTypeRecId;
        SymSyncTypeRef(varIdx);
      end;
      { Managed/aggregate result temp: the per-arm AN_ASSIGN delegation below
        releases the dest's old managed fields before copy, so the temp must be
        nil-inited (allocated post-prologue) — same rule as other hidden temps. }
      if (argTk = tyAnsiString) or (argTk = tyString) or TypeIsAggregate(argTk) or
         (argTk = tyVariant) or TypeIsPromoInt(argTk) then
        SymIsHiddenArgTemp[varIdx] := True;
      elseLabel := IRNewLabel;
      endLabel := IRNewLabel;
      condNode := IRLowerAST(ASTLeft[node]);
      first := IRAppend(IR_JUMP_IF_FALSE, elseLabel, condNode, -1, 0, 0);
      { Each arm: lower `temp := arm` through the ordinary assignment path so
        scalar, string (ARC), and record (managed copy) results all work and the
        selected arm's side effects run (short-circuit). }
      lhsNode := AllocNode(AN_IDENT); ASTIVal[lhsNode] := varIdx; ASTTk[lhsNode] := Ord(argTk);
      argNode := AllocNode(AN_ASSIGN); ASTLeft[argNode] := lhsNode; ASTRight[argNode] := ASTLeft[pairNode];
      IRMarkStatementNode(IRLowerAST(argNode));
      IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      lhsNode := AllocNode(AN_IDENT); ASTIVal[lhsNode] := varIdx; ASTTk[lhsNode] := Ord(argTk);
      argNode := AllocNode(AN_ASSIGN); ASTLeft[argNode] := lhsNode; ASTRight[argNode] := ASTRight[pairNode];
      IRMarkStatementNode(IRLowerAST(argNode));
      IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      { Record values are carried by address in the IR value model (IR_COPY_REC
        takes source/dest addresses; every other record producer emits IR_LEA).
        IR_LOAD_SYM on a record local falls into EmitLoadVar's scalar path and
        loads the record's FIRST 8 BYTES instead — the consumer then used that
        field value as the source address (C `c = cond ? a : b` with struct
        arms copied from *(a.z): the sqlite CREATE TRIGGER NOMEM bug). }
      { A variant (16-byte {tag,payload}) is carried by ADDRESS like a record —
        an IR_LOAD_SYM scalar load would take only the first 8 bytes and the
        consumer would deref a truncated value (segfault). Yield its address. }
      if (argTk = tyRecord) or (argTk = tyVariant) then
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(argTk))
      else if TypeIsPromoInt(argTk) then
        { a promotable int's rvalue is its SLOT ADDRESS (the tyVariant model);
          a scalar load would hand the consumer the tag word }
        Result := IRAppend(IR_SLOTADDR, varIdx, -1, -1, 0, Ord(tyPointer))
      else
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(argTk));
    end;

    AN_SWITCH:
    begin
      endLabel := IRNewLabel;
      { selector evaluated once into a temp }
      value := IRLowerAST(ASTLeft[node]);
      first := value;
      if ASTTk[ASTLeft[node]] = 0 then swSelTk := Ord(tyInteger)
      else swSelTk := ASTTk[ASTLeft[node]];
      swSelTmp := AllocVar('', IntToTypeKind(swSelTk));
      IRAppend(IR_STORE_SYM, swSelTmp, value, -1, 0, swSelTk);
      { pass 1 — dispatch: give each case/default marker a label and, for a case,
        emit `if (sel == caseval) goto label` (via JUMP_IF_FALSE of `sel != val`). }
      swDefault := -1;
      IRLowerCSwitchDispatchScan(ASTRight[node], swSelTmp, swSelTk, swDefault);
      if swDefault >= 0 then IRAppend(IR_JUMP, swDefault, -1, -1, 0, 0)
      else IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      { pass 2 — lower the whole body normally (fallthrough by label ordering).
        C case/default markers lower to IR_LABEL in place (see the AN_CASE/AN_DEFAULT
        arms), so labels nested inside loops (Duff's device) land correctly and the
        dispatch above can jump straight into them. break -> end; continue is
        inherited so it targets the enclosing loop, giving a break-only scope. }
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      if IRLoopStackDepth > 0 then
        IRLoopStackContinue[IRLoopStackDepth] := IRLoopStackContinue[IRLoopStackDepth - 1]
      else
        IRLoopStackContinue[IRLoopStackDepth] := endLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      IRMarkStatementNode(IRLowerAST(ASTRight[node]));
      Dec(IRLoopStackDepth);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_WHILE:
    begin
      startLabel := IRNewLabel;
      endLabel := IRNewLabel;
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      condNode := IRLowerAST(ASTLeft[node]);
      last := IRAppend(IR_JUMP_IF_FALSE, endLabel, condNode, -1, 0, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := startLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      
      Dec(IRLoopStackDepth);
      
      last := IRAppend(IR_JUMP, startLabel, -1, -1, 0, 0);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, startLabelNode, endLabelNode, -1, 0, 0);
    end;

    AN_PARFOR:
      { `parallel for` -> lower the parse-time-synthesized PXXParallelFor call. }
      Result := IRLowerAST(ASTLeft[node]);

    AN_FOR:
    begin
      lhsNode := ASTLeft[node];
      pair3 := ASTRight[node];
      pair1 := ASTLeft[pair3];
      pair2 := ASTRight[pair3];
      
      initNode  := ASTLeft[pair1];
      limitNode := ASTRight[pair1];
      
      isDownNode := ASTLeft[pair2];
      bodyNode   := ASTRight[pair2];
      
      down := ASTIVal[isDownNode] = 1;
      varIdx := ASTIVal[lhsNode];
      
      initValNode := IRLowerAST(initNode);
      storeNode := IRAppend(IR_STORE_SYM, varIdx, initValNode, -1, 0, ASTTk[lhsNode]);
      
      limitValNode := IRLowerAST(limitNode);
      
      startLabel := IRNewLabel;
      endLabel := IRNewLabel;
      continueLabel := IRNewLabel;
      
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      
      condNode := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[lhsNode]);
      
      if down then
        cmpNode := IRAppend(IR_BINOP, condNode, limitValNode, Ord(tkGe), 0, Ord(tyBoolean))
      else
        cmpNode := IRAppend(IR_BINOP, condNode, limitValNode, Ord(tkLe), 0, Ord(tyBoolean));
        
      condJmpNode := IRAppend(IR_JUMP_IF_FALSE, endLabel, cmpNode, -1, 0, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := continueLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      bodyIRNode := IRLowerAST(bodyNode);
      IRMarkStatementNode(bodyIRNode);
      
      Dec(IRLoopStackDepth);
      
      continueLabelNode := IRAppend(IR_LABEL, -1, -1, -1, continueLabel, 0);
      
      loadVarNode2 := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[lhsNode]);
      constOneNode := IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger));
      
      if down then
        stepNode := IRAppend(IR_BINOP, loadVarNode2, constOneNode, Ord(tkMinus), 0, ASTTk[lhsNode])
      else
        stepNode := IRAppend(IR_BINOP, loadVarNode2, constOneNode, Ord(tkPlus), 0, ASTTk[lhsNode]);
        
      storeStepNode := IRAppend(IR_STORE_SYM, varIdx, stepNode, -1, 0, ASTTk[lhsNode]);
      
      jmpNode := IRAppend(IR_JUMP, startLabel, -1, -1, 0, 0);
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      
      Result := IRAppend(IR_BLOCK, storeNode, endLabelNode, -1, 0, 0);
    end;

    AN_REPEAT:
    begin
      startLabel := IRNewLabel;
      continueLabel := IRNewLabel;
      endLabel := IRNewLabel;
      
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := continueLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      bodyIRNode := IRLowerAST(ASTLeft[node]);
      IRMarkStatementNode(bodyIRNode);
      
      Dec(IRLoopStackDepth);
      
      continueLabelNode := IRAppend(IR_LABEL, -1, -1, -1, continueLabel, 0);
      
      condNode := IRLowerAST(ASTRight[node]);
      
      last := IRAppend(IR_JUMP_IF_FALSE, startLabel, condNode, -1, 0, 0);
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      
      Result := IRAppend(IR_BLOCK, startLabelNode, endLabelNode, -1, 0, 0);
    end;

    AN_CASE:
    begin
      { C switch-case MARKER (ASTSLen=1): dispatch already assigned its IR_LABEL
        (ASTSOffset) and emitted the compare; here we just drop the label in place
        so fallthrough / jump-into-loop lands correctly. Distinct from the Pascal
        AN_CASE statement handled below (which has a branch chain in ASTRight). }
      if ASTSLen[node] = 1 then
      begin
        Result := IRAppend(IR_LABEL, -1, -1, -1, ASTSOffset[node], 0);
        Exit;
      end;
      { GUARD-RAIL — this lowers `case` to a COMPARE-CHAIN: every clause target
        is an IR_LABEL reached by IR_JUMP_IF_FALSE/IR_JUMP. IROptDeadCode
        (ir.inc) depends on the invariant that EVERY control-transfer landing
        site is a stream IR_LABEL. If you ever rewrite this to a jump TABLE
        (computed `jmp [base + idx*8]` to a non-label target), that invariant
        breaks and -O1 dead-code elimination could delete a live landing site.
        Before doing so: emit an IR_LABEL at every table target, or gate
        IROptDeadCode off for bodies containing the computed jump. See
        devdocs/dev/optimization-architecture.md §2 (O1 safety policy). }
      selectorValNode := IRLowerAST(ASTLeft[node]);
      { A string-typed selector switches every label test from the ordinal
        path to full-string comparisons: labels stay string literals
        (IR_CONST_STR rebuilt from the preserved source span) and ranges are
        lexicographic (s >= lo) and (s <= hi). Char selectors keep the
        ordinal path. (bug-case-of-string-segfault-and-label-validation) }
      caseIsStr := IntToTypeKind(IRTk[selectorValNode]) in [tyString, tyAnsiString];

      { EVALUATE THE SELECTOR EXACTLY ONCE (Pascal requires it; FPC does it).

        This lowers to a COMPARE-CHAIN, and the selector value node is used as an
        operand of EVERY label test — but a value node is not a register, it is a
        subtree, and each backend re-EMITS it per use. So `case F(x) of` ran F once
        per label ELEMENT (a range costs two), stopping at the first match. It looked
        fine whenever the first label matched, which is exactly what hid it: pasmith's
        differential fuzzer filed ~510 divergences against FPC, and they were all this.

        Materialise into a temp and compare the temp. Skipped for a node that is
        already pure and free to re-emit (a symbol load or a constant), so the common
        `case i of` keeps byte-identical codegen. IR_LOAD_MEM is NOT in that set: its
        address subtree can contain a call. }
      if not ((IRKind[selectorValNode] = IR_LOAD_SYM) or
              (IRKind[selectorValNode] = IR_CONST_INT) or
              (IRKind[selectorValNode] = IR_CONST_STR)) then
      begin
        { A string selector is materialised into a MANAGED temp — including a FROZEN one
          (`case ss of` where ss: shortstring). The store converts frozen -> handle, so the
          temp's type, and therefore the tag on the load, is tyAnsiString. Tagging the load
          with the SOURCE's frozen kind instead made every later comparison read the heap
          handle as if it were an inline [len][chars] buffer (tcase0). }
        if caseIsStr then
        begin
          selTmpSym := AllocVar('', tyAnsiString);
          { managed temp: prologue nil-init so a scope-exit / skipped-branch
            release sees an empty handle, not stack garbage (the same rule every
            other managed hidden temp follows). }
          SymIsHiddenArgTemp[selTmpSym] := True;
          selTmpTk := Ord(tyAnsiString);
        end
        else
        begin
          selTmpSym := AllocVar('', IntToTypeKind(IRTk[selectorValNode]));
          selTmpTk := IRTk[selectorValNode];
        end;
        IRAppend(IR_STORE_SYM, selTmpSym, selectorValNode, -1, 0, IRTk[selectorValNode]);
        selectorValNode := IRAppend(IR_LOAD_SYM, selTmpSym, -1, -1, 0, selTmpTk);
      end;
      IRValidateCaseLabels(ASTRight[node], caseIsStr);
      endLabel := IRNewLabel;

      first := -1;
      last := -1;

      branchSeq := ASTRight[node];
      while branchSeq <> -1 do
      begin
        branchPair := ASTLeft[branchSeq];
        labelsHead := ASTLeft[branchPair];
        stmtNode   := ASTRight[branchPair];
        
        if labelsHead = -1 then
        begin
          { Else Clause }
          bodyIRNode := IRLowerAST(stmtNode);
          IRMarkStatementNode(bodyIRNode);
          if first < 0 then first := bodyIRNode;
          last := bodyIRNode;
        end
        else
        begin
          { Normal Clause }
          clauseBodyLabel := IRNewLabel;
          nextClauseLabel := IRNewLabel;
          
          labelNode := labelsHead;
          while labelNode <> -1 do
          begin
            if ASTRight[ASTLeft[labelNode]] <> -1 then
            begin
              { Range label lo..hi: enter the body when lo <= selector <= hi.
                Skip to elseLabel (this label-test's exit) when either bound
                fails; reaching the unconditional jump means in-range. }
              elseLabel := IRNewLabel;
              constValNode := IRCaseLabelConst(ASTLeft[labelNode], caseIsStr);
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkGe), 0, Ord(tyBoolean));
              condJmpNode := IRAppend(IR_JUMP_IF_FALSE, elseLabel, cmpNode, -1, 0, 0);
              if first < 0 then first := condJmpNode;
              constValNode := IRCaseLabelConst(ASTRight[ASTLeft[labelNode]], caseIsStr);
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkLe), 0, Ord(tyBoolean));
              IRAppend(IR_JUMP_IF_FALSE, elseLabel, cmpNode, -1, 0, 0);
              IRAppend(IR_JUMP, clauseBodyLabel, -1, -1, 0, 0);
              last := IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
            end
            else
            begin
              constValNode := IRCaseLabelConst(ASTLeft[labelNode], caseIsStr);
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkNeq), 0, Ord(tyBoolean));
              condJmpNode := IRAppend(IR_JUMP_IF_FALSE, clauseBodyLabel, cmpNode, -1, 0, 0);
              if first < 0 then first := condJmpNode;
              last := condJmpNode;
            end;

            labelNode := ASTRight[labelNode];
          end;
          
          exitJmpNode := IRAppend(IR_JUMP, nextClauseLabel, -1, -1, 0, 0);
          last := exitJmpNode;
          
          clauseBodyLabelNode := IRAppend(IR_LABEL, -1, -1, -1, clauseBodyLabel, 0);
          last := clauseBodyLabelNode;
          
          bodyIRNode := IRLowerAST(stmtNode);
          IRMarkStatementNode(bodyIRNode);
          last := bodyIRNode;
          
          exitJmpNode := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
          last := exitJmpNode;
          
          nextClauseLabelNode := IRAppend(IR_LABEL, -1, -1, -1, nextClauseLabel, 0);
          last := nextClauseLabelNode;
        end;
        
        branchSeq := ASTRight[branchSeq];
      end;
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      last := endLabelNode;
      
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_BREAK:
    begin
      if IRLoopStackDepth = 0 then Error('break outside loop');
      beforeCount := IRCount;
      IRLowerCleanupToDepth(IRLoopStackExceptionDepth[IRLoopStackDepth - 1]);
      jmpNode := IRAppend(IR_JUMP, IRLoopStackBreak[IRLoopStackDepth - 1], -1, -1, 0, 0);
      if beforeCount < jmpNode then
        Result := IRAppend(IR_BLOCK, beforeCount, jmpNode, -1, 0, 0)
      else
        Result := jmpNode;
    end;

    AN_CONTINUE:
    begin
      if IRLoopStackDepth = 0 then Error('continue outside loop');
      beforeCount := IRCount;
      IRLowerCleanupToDepth(IRLoopStackExceptionDepth[IRLoopStackDepth - 1]);
      jmpNode := IRAppend(IR_JUMP, IRLoopStackContinue[IRLoopStackDepth - 1], -1, -1, 0, 0);
      if beforeCount < jmpNode then
        Result := IRAppend(IR_BLOCK, beforeCount, jmpNode, -1, 0, 0)
      else
        Result := jmpNode;
    end;

    AN_RAISE:
    begin
      if ASTLeft[node] <> -1 then
      begin
        raiseValueNode := IRLowerAST(ASTLeft[node]);
        raiseClass := ResolveNodeRec(ASTLeft[node]);
        if raiseClass < REC_UCLASS_BASE then raiseClass := REC_NONE;
      end
      else
      begin
        raiseValueNode := -1;
        raiseClass := REC_NONE;
      end;
      Result := IRAppend(IR_RAISE, raiseValueNode, -1, -1, raiseClass, 0);
    end;

    AN_TRY_EXCEPT:
    begin
      handlerLabel := IRNewLabel;
      endLabel := IRNewLabel;
      { NilPy: an `except C as e` binder is a tyClass local created MID-body,
        so the proc-entry zero-init pass never saw it — but the scope-exit
        release arm (feature-nilpy-object-reclamation slice 4) reads its slot
        at every proc exit, including exits where no exception ever bound it.
        Nil the slot here, before the try body, so that release sees nil, not
        stale stack bytes (the t.c freelist-corruption repro). }
      if NilPyUserCode then
      begin
        handlerNode := ASTRight[node];
        while handlerNode <> -1 do
        begin
          if (ASTSOffset[handlerNode] >= 0) and
             (Syms[ASTSOffset[handlerNode]].TypeKind = tyClass) then
            IRAppend(IR_DEFAULT_MEM,
              IRAppend(IR_SLOTADDR, ASTSOffset[handlerNode], -1, -1, 0, Ord(tyPointer)),
              -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));
          handlerNode := ASTRight[handlerNode];
        end;
      end;
      first := IRAppend(IR_EXC_ENTER, handlerLabel, -1, -1, 0, 0);

      ExceptionFinallyBody[ExceptionCodegenDepth] := -1;
      Inc(ExceptionCodegenDepth);
      last := IRLowerAST(ASTLeft[node]);
      Dec(ExceptionCodegenDepth);

      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      last := IRAppend(IR_LABEL, -1, -1, -1, handlerLabel, 0);
      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);

      handlerNode := ASTRight[node];
      while handlerNode <> -1 do
      begin
        handlerNextLabel := -1;
        if ASTIVal[handlerNode] >= 0 then
        begin
          handlerNextLabel := IRNewLabel;
          { `on E: T` must catch T and every descendant of T (Delphi/FPC
            is-a semantics), not just an exact class match. ASTIVal here is
            recId-space (REC_UCLASS_BASE + ci); IsClassDescOrSelf walks raw
            UCls indices (same helper `is`/`as` use via IRLowerClassMatch).
            Emit one IR_EXC_MATCH_HIT (jump-to-body-on-match) per proper
            descendant, then the original exact-match IR_EXC_MATCH last so
            its existing fall-through-on-match still lands on the body. }
          excTargetCi := ASTIVal[handlerNode] - REC_UCLASS_BASE;
          excBodyLabel := IRNewLabel;
          { `on E: T` must catch T and every DESCENDANT of T (Delphi/FPC is-a
            semantics). Descendants used to be ENUMERATED here — which runs when
            the handler's own unit lowers, so an exception class declared in a
            unit compiled LATER was not in the set and silently escaped the
            handler (fpcunit's `on E: Exception do` missed fpjson's EJSON purely
            because of unit order; flipping `uses` flipped the behaviour).

            Ask the RUNTIME instead: materialize the in-flight exception object
            and walk its RTTI parent chain, exactly as `is`/`as` do. Correct for
            classes this site has never seen, so unit order stops mattering.

            IR_EXC_MATCH still follows, unchanged: it is what jumps to the NEXT
            handler when nothing matched (and its own exact-class test is simply
            subsumed by the reflexive walk). Falls back to the old enumeration
            where the walk is unavailable (no builtin unit — ESP). }
          excObjSym := AllocVar('', tyPointer);
          last := IRAppend(IR_EXC_STORE, excObjSym, -1, -1, 0, 0);
          excMatched := IRClassMatchRuntime(excObjSym, excTargetCi);
          if excMatched >= 0 then
          begin
            excSkipLabel := IRNewLabel;
            last := IRAppend(IR_JUMP_IF_FALSE, excSkipLabel,
                             IRAppend(IR_LOAD_SYM, excMatched, -1, -1, 0, Ord(tyBoolean)),
                             -1, 0, 0);
            last := IRAppend(IR_JUMP, excBodyLabel, -1, -1, 0, 0);
            last := IRAppend(IR_LABEL, -1, -1, -1, excSkipLabel, 0);
          end
          else
            for excDescCi := 0 to UClsCount - 1 do
              if (excDescCi <> excTargetCi) and IsClassDescOrSelf(excDescCi, excTargetCi) then
                last := IRAppend(IR_EXC_MATCH_HIT, excBodyLabel, -1, -1, REC_UCLASS_BASE + excDescCi, 0);
          last := IRAppend(IR_EXC_MATCH, handlerNextLabel, -1, -1, ASTIVal[handlerNode], 0);
          last := IRAppend(IR_LABEL, -1, -1, -1, excBodyLabel, 0);
        end;
        excOwnTmp := -1;
        if ASTSOffset[handlerNode] >= 0 then
          last := IRAppend(IR_EXC_STORE, ASTSOffset[handlerNode], -1, -1, 0, 0)
        else if NilPyUserCode then
        begin
          { No `except ... as e:` binder: the exception object still has the
            ONE owning reference its constructor gave it (raise transfers that
            reference, it does not add another), and when a handler binds it
            to a real local, that local's own scope-exit release is what
            finally drops it. With no binder, nothing anywhere holds a
            reference to release -- every caught exception leaked its object
            forever, and the leak did not care whether the exception was
            named (bug-nilpy-caught-exception-objects-are-never-freed). Store
            it into a hidden, release-only temp so IR_EXC_CLEAR below (which
            only zeroes bookkeeping globals, never releases) has something to
            hand to PXXObjRelease first. }
          excOwnTmp := AllocVar('', tyPointer);
          last := IRAppend(IR_EXC_STORE, excOwnTmp, -1, -1, 0, 0);
        end;
        last := IRLowerAST(ASTLeft[handlerNode]);
        IRMarkStatementNode(last);
        if excOwnTmp >= 0 then
        begin
          excReleaseProc := FindProc('PXXObjRelease');
          if excReleaseProc >= 0 then
          begin
            last := IRAppendCall(excReleaseProc,
                      IRAppend(IR_ARG,
                        IRAppend(IR_LOAD_SYM, excOwnTmp, -1, -1, 0, Ord(tyPointer)),
                        -1, -1, 0, Ord(tyPointer)),
                      -1, Ord(tyUnknown));
            IRIVal[last] := 1;   { statement: emit for effect, not a value }
            IRMarkStatementNode(last);
          end;
        end;
        last := IRAppend(IR_EXC_CLEAR, -1, -1, -1, 0, 0);
        last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
        if handlerNextLabel >= 0 then
          last := IRAppend(IR_LABEL, -1, -1, -1, handlerNextLabel, 0);
        handlerNode := ASTRight[handlerNode];
      end;
      last := IRAppend(IR_RAISE, -1, -1, -1, REC_NONE, 0);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_TRY_FINALLY:
    begin
      handlerLabel := IRNewLabel;
      endLabel := IRNewLabel;
      first := IRAppend(IR_EXC_ENTER, handlerLabel, -1, -1, 0, 0);

      ExceptionFinallyBody[ExceptionCodegenDepth] := ASTRight[node];
      Inc(ExceptionCodegenDepth);
      last := IRLowerAST(ASTLeft[node]);
      IRMarkStatementNode(last);
      Dec(ExceptionCodegenDepth);

      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);

      last := IRAppend(IR_LABEL, -1, -1, -1, handlerLabel, 0);
      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      savedDepth := ExceptionCodegenDepth;
      ExceptionCodegenDepth := savedDepth;
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      ExceptionCodegenDepth := savedDepth;
      last := IRAppend(IR_RAISE, -1, -1, -1, REC_NONE, 0);

      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_WRITE, AN_WRITELN:
    begin
      { --threadsafe: one write/writeln statement = one atomic emission.
        Bracket the whole statement with the reentrant I/O lock (also guards
        the shared INTBUF/LINE_BUF scratch). x86-64 only — --threadsafe
        atomics are x86-64-only today. }
      if ThreadSafeMode and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or (TargetArch = TARGET_AARCH64) or (TargetArch = TARGET_ARM32)) then
        IRAppend(IR_IO_LOCK, -1, -1, -1, 0, 0);
      first := -1;
      last := -1;
      { Target fd, threaded into each IR_WRITE/IR_WRITELN's ival slot so codegen
        emits the write syscalls against it. ASTIVal[node] = 0 means the default
        (stdout); writeln(StdErr,..) set it to 2 in the parser. }
      writeFd := ASTIVal[node];
      if writeFd = 0 then writeFd := STDOUT;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        { IR_WRITE: IRB = field width (0 = none), IRC = decimals (-1 = none),
          IRIVal = target fd, IRTk = the source expression type (write dispatch). }
        bLastNode := -1;
        if (ASTKind[item] = AN_ARG) and (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyBoolean) then
        begin
          { write(Boolean[:w]) -> FPC-style TRUE/FALSE text, branched at runtime. }
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRLowerBoolWrite(value, ASTIVal[item], bLastNode, writeFd);
        end
        else if (ASTKind[item] = AN_PAIR) and (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyBoolean) then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRLowerBoolWrite(value, -1, bLastNode, writeFd);
        end
        else if (ASTKind[item] <> AN_ARG) and (ASTKind[item] <> AN_PAIR) and
                (IntToTypeKind(ASTTk[item]) = tyBoolean) then
        begin
          value := IRLowerAST(item);
          outNode := IRLowerBoolWrite(value, -1, bLastNode, writeFd);
        end
        else if ASTKind[item] = AN_ARG then
        begin
          { A Variant arg writes its slot address; codegen reads tag+payload and
            dispatches at runtime (IRTk stays tyVariant). }
          if IntToTypeKind(ASTTk[ASTLeft[item]]) = tyVariant then
            value := IRVariantAddr(ASTLeft[item])
          else if IsWideIntLit(ASTLeft[item]) or IsWideNegLit(ASTLeft[item]) then
            { a wide literal must not reach the machine-int lowering (it would
              reject a value past UInt64); box it from its digit text }
            value := IRPromoAddrOf(ASTLeft[item])
          else
            value := IRLowerAST(ASTLeft[item]);
          if IsNodePChar(ASTLeft[item]) then
            { write(PChar): tag the IR_WRITE with the -3 decimals sentinel so
              codegen emits a runtime C-string (strlen + write) instead of
              printing the pointer value. }
            outNode := IRAppend(IR_WRITE, value, ASTIVal[item], -3, writeFd, Ord(tyPointer))
          else if TypeIsPromoInt(IntToTypeKind(ASTTk[ASTLeft[item]])) then
          begin
            { A promotable int PRINTS via the runtime, which renders whichever
              tier it is in — a bignum has no machine-int form to hand the
              integer writer. `value` is already the slot address (a wide
              literal was boxed above). }
            outNode := IRAppend(IR_WRITE,
                                IRPromoCall('PXXPromoToStr', value, -1, -1, tyAnsiString),
                                ASTIVal[item], ASTSOffset[item], writeFd, Ord(tyAnsiString));
          end
          else
            outNode := IRAppend(IR_WRITE, value, ASTIVal[item], ASTSOffset[item], writeFd, Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        end
        else if ASTKind[item] = AN_PAIR then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, IRTk[value]);
        end
        else if IntToTypeKind(ASTTk[item]) = tyVariant then
        begin
          value := IRVariantAddr(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, Ord(tyVariant));
        end
        else
        begin
          value := IRLowerAST(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, IRTk[value]);
        end;
        if first < 0 then first := outNode;
        if bLastNode >= 0 then last := bLastNode else last := outNode;
        item := ASTRight[item];
      end;
      if ASTKind[node] = AN_WRITELN then
        Result := IRAppend(IR_WRITELN, first, last, -1, writeFd, 0)
      else
        Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
      if ThreadSafeMode and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or (TargetArch = TARGET_AARCH64) or (TargetArch = TARGET_ARM32)) then
        IRAppend(IR_IO_UNLOCK, -1, -1, -1, 0, 0);
    end;

    AN_READLN, AN_READ:
    begin
      { Read one line from stdin, then parse each lvalue target from it by type.
        --threadsafe: same statement-atomic I/O lock as write/writeln (guards
        the shared LINE_BUF/LINE_POS/PEEK_* scratch too). }
      if ThreadSafeMode and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or (TargetArch = TARGET_AARCH64) or (TargetArch = TARGET_ARM32)) then
        IRAppend(IR_IO_LOCK, -1, -1, -1, 0, 0);
      first := IRAppend(IR_READLINE, -1, -1, -1, 0, 0);
      last := first;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAddress(ASTLeft[item]);   { target address }
        outNode := IRAppend(IR_READ_VAR, value, -1, -1, 0,
                            Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        last := outNode;
        item := ASTRight[item];
      end;
      if ASTKind[node] = AN_READLN then
      begin
        outNode := IRAppend(IR_READ_DISCARD, -1, -1, -1, 0, 0);
        last := outNode;
      end;
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
      if ThreadSafeMode and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) or (TargetArch = TARGET_AARCH64) or (TargetArch = TARGET_ARM32)) then
        IRAppend(IR_IO_UNLOCK, -1, -1, -1, 0, 0);
    end;

    AN_BLOCK:
    begin
      first := -1;
      last := -1;
      seq := ASTLeft[node];
      while seq <> -1 do
      begin
        if ASTKind[seq] = AN_SEQ then
        begin
          item := IRDropManagedStrResult(IRLowerAST(ASTLeft[seq]));
          IRDiscardValue(item);
          seq := ASTRight[seq];
        end
        else
        begin
          item := IRDropManagedStrResult(IRLowerAST(seq));
          IRDiscardValue(item);
          seq := -1;
        end;
        if first < 0 then first := item;
        last := item;
      end;
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_VIRTUAL_CALL:
    begin
      { AN_VIRTUAL_CALL layout:
          ASTIVal[node] = proc index   (for param signature)
          ASTRight[node] = VMT slot index
          ASTLeft[node]  = first AN_ARG (Self is arg 0, injected by parser) }
      first := -1;
      last := -1;
      cpi := ASTIVal[node];
      slot := ASTRight[node];
      item := ASTLeft[node];
      pathIdx := 0;
      while item <> -1 do
      begin
        isRefArg := False;
        if (pathIdx > 0) and (pathIdx < Procs[cpi].ParamCount) and
           Procs[cpi].Params[pathIdx].IsRef then
          isRefArg := True;
        { Self (pathIdx=0) is always passed by value (pointer). Real args go
          through the same IRLowerCallArg as a direct call so by-ref literals,
          static->open-array, class->interface coercion, and frozen-string concat
          marshal identically — a raw IRLowerAddress(literal) here produced a bad
          pointer (corrupt string length). See bug-mixed-signature-vmt-misdispatch. }
        if pathIdx = 0 then
          value := IRLowerAST(ASTLeft[item])
        else
          value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        { Same argument conversions as the direct AN_CALL path — the virtual
          path skipped them all, so a frozen concat ('ping' + CRLF) handed to a
          virtual method's AnsiString param arrived as a raw slot address
          (garbage length; blcksock's SendString hang), and a string literal
          to a Pointer param missed the +8 skip. }
        if (not isRefArg) and (pathIdx > 0) and
           (IntToTypeKind(IRTk[value]) = tyString) and
           (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) then
        begin
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
          value := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        end
        else if (not isRefArg) and (pathIdx > 0) and
           (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer))
        else if (not isRefArg) and (pathIdx > 0) and
           (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
           (ASTKind[ASTLeft[item]] <> AN_IDENT) and
           (ASTKind[ASTLeft[item]] <> AN_FIELD) and
           (ASTKind[ASTLeft[item]] <> AN_INDEX) and
           { isNilPy: own a `p^` managed-string arg — see the identical clause
             above (bug-a-nilpy-managed-deref-to-const-arg-leaks). }
           ((ASTKind[ASTLeft[item]] <> AN_DEREF) or isNilPy) then
        begin
          { materialised managed-string arg: bind to a hidden owning local and
            pass by borrow (ARC coercion + no per-call leak) — see AN_CALL }
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          { No per-store IR_DEFAULT_MEM: the slot is nil-init'd ONCE at body head
            (SymIsHiddenArgTemp codegen pass / BSS), so STORE_SYM's release-of-old
            frees the previous iteration's materialised handle on every loop reuse.
            A per-store zero re-leaked it every trip
            (bug-a-managed-string-arg-temp-leaks-on-loop-reuse — same fix as the
            direct AN_CALL path, extended here to the CALL_IND / INTF_CALL /
            VIRTUAL_CALL / METACLASS_NEW arg paths). }
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=VMT slot }
      Result := IRAppend(IR_VIRTUAL_CALL, first, last, cpi, slot, ASTTk[node]);
      { Aggregate / frozen-string result: the IR node has no free operand for the
        hidden caller-destination, so stash its IR_LEA in IRCallDest (codegen loads
        it into the per-target dest register before the dispatch). }
      if ABIRetViaHiddenDestProc(cpi) then
        IRCallDest[Result] := IRBuildHiddenDest(cpi);
    end;

    AN_METACLASS_NEW:
    begin
      { Metaclass-dispatched construction `classRefVar.Create(args)`.
          ASTRight   = classref value node (yields the dynamic class's RTTI blob)
          ASTIVal    = ctor proc idx (param signature)
          ASTSOffset = ctor VMT slot (-1 if the ctor is not virtual)
          ASTLeft    = AN_ARG chain of explicit ctor args (Self excluded)
        Allocate the DYNAMIC class read from the RTTI blob (size@16, vmt@24),
        stamp its VMT, then run the constructor through the stamped VMT — an
        ordinary virtual call once [inst+0] holds the right VMT. Built as
        target-independent IR (same idiom as is/as), so all backends share it. }
      cpi := ASTIVal[node];
      slot := ASTSOffset[node];

      { cref := <classref value> (the RTTI blob pointer). }
      mcCrefSym := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, mcCrefSym, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));

      { size := [cref+16] (RTTI instance size). }
      mcAddr := IRAppend(IR_BINOP,
                  IRAppend(IR_LOAD_SYM, mcCrefSym, -1, -1, 0, Ord(tyPointer)),
                  IRAppend(IR_CONST_INT, -1, -1, -1, 16, Ord(tyInteger)),
                  Ord(tkPlus), 0, Ord(tyPointer));
      mcSize := IRAppend(IR_LOAD_MEM, mcAddr, -1, -1, 0, Ord(tyInt64));

      { inst := GetMem(size) — plain alloc (classIdx = -1: no VMT stamp here). }
      mcInstSym := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, mcInstSym,
               IRAppend(IR_CALL, -Ord(tkGetMem),
                        IRAppend(IR_ARG, mcSize, -1, -1, 0, Ord(tyInteger)),
                        -1, 0, Ord(tyPointer)),
               -1, 0, Ord(tyPointer));

      { [inst+0] := [cref+24] (stamp the dynamic class's VMT). }
      mcAddr := IRAppend(IR_BINOP,
                  IRAppend(IR_LOAD_SYM, mcCrefSym, -1, -1, 0, Ord(tyPointer)),
                  IRAppend(IR_CONST_INT, -1, -1, -1, 24, Ord(tyInteger)),
                  Ord(tkPlus), 0, Ord(tyPointer));
      mcVmt := IRAppend(IR_LOAD_MEM, mcAddr, -1, -1, 0, Ord(tyInt64));
      IRAppend(IR_STORE_MEM,
               IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
               mcVmt, -1, 0, Ord(tyPointer));

      { Constructor call: Self (param 0) = inst, then the explicit args. }
      mcSelfArg := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyClass));
      first := mcSelfArg; last := mcSelfArg;
      item := ASTLeft[node];
      pathIdx := 1;
      while item <> -1 do
      begin
        { Lower each argument through IRLowerCallArg, exactly as AN_CALL / AN_VIRTUAL_CALL
          / AN_INTF_CALL do -- NOT with a raw IRLowerAST.

          IRLowerCallArg is PARAMETER-AWARE: it lowers the expression against the
          declared type of the parameter it is being passed to. A raw IRLowerAST only
          knows the expression, so it happened to agree for an Integer and disagreed for
          a `const s: string` -- which is why metaclass construction with a STRING
          argument segfaulted on every backend except x86-64, whose IR_ARG emit for a
          frozen string forgave the difference. An Integer argument worked everywhere all
          along, which is what made the bug look target-specific rather than
          argument-specific. }
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        argIsManagedTemp :=
          (not isRefArg) and (pathIdx < Procs[cpi].ParamCount) and
          (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
          (ASTKind[ASTLeft[item]] <> AN_IDENT) and
          (ASTKind[ASTLeft[item]] <> AN_FIELD) and
          (ASTKind[ASTLeft[item]] <> AN_INDEX) and
          { A managed-string DEREF value (`p^`, p: ^AnsiString) is normally a
            borrow (excluded), but under isNilPy passing it directly to a
            `const AnsiString` param leaks one handle per call — the isNilPy
            arg lowering materialises an unowned copy that never releases
            (bug-a-nilpy-managed-deref-to-const-arg-leaks; plain Pascal `p^`-
            to-const is clean, so this fires under isNilPy only). Route it
            through the owning-temp path instead: the hidden local's STORE
            retains a proper +1 (release-of-old on loop reuse) and scope exit
            frees it — exactly the `mn := p^` bind the hot call sites used. }
          ((ASTKind[ASTLeft[item]] <> AN_DEREF) or isNilPy);
        if argIsManagedTemp then
        begin
          { a managed-string temp must outlive the call; same hidden slot the other
            call paths allocate }
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          { No per-store IR_DEFAULT_MEM: the slot is nil-init'd ONCE at body head
            (SymIsHiddenArgTemp codegen pass / BSS), so STORE_SYM's release-of-old
            frees the previous iteration's materialised handle on every loop reuse.
            A per-store zero re-leaked it every trip
            (bug-a-managed-string-arg-temp-leaks-on-loop-reuse — same fix as the
            direct AN_CALL path, extended here to the CALL_IND / INTF_CALL /
            VIRTUAL_CALL / METACLASS_NEW arg paths). }
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;

      if slot >= 0 then
        { The call runs for its side effect (it fills the instance); its result
          is discarded, so flag it a statement root or it would be pruned. }
        IRMarkStatementNode(IRAppend(IR_VIRTUAL_CALL, first, last, cpi, slot, Ord(tyClass)))
      else
        IRMarkStatementNode(IRAppendCall(cpi, first, -1, Ord(tyClass)));

      { The construction value is the instance, not the ctor body's return. }
      Result := IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, ASTTk[node]);
    end;

    AN_LABEL:
    begin
      { Synthetic label (stackless generator transform): ASTSOffset = -1 sentinel,
        ASTIVal carries the GotoLabel slot index directly (no name match). }
      if ASTSOffset[node] = -1 then
      begin
        i := ASTIVal[node];
        if GotoLabelIRId[i] = -1 then GotoLabelIRId[i] := IRNewLabel;
        Result := IRAppend(IR_LABEL, -1, -1, -1, GotoLabelIRId[i], 0);
      end
      else
      begin
        off := ASTSOffset[node];
        len := ASTSLen[node];
        lbId := -1;
        for i := 0 to GotoLabelCount - 1 do
          if TokSlicesMatch(GotoLabelNOff[i], GotoLabelNLen[i], off, len) then
          begin
            if GotoLabelIRId[i] = -1 then
              GotoLabelIRId[i] := IRNewLabel;
            lbId := GotoLabelIRId[i];
            Break;
          end;
        if lbId = -1 then Error('AN_LABEL: undeclared label');
        Result := IRAppend(IR_LABEL, -1, -1, -1, lbId, 0);
      end;
    end;
    AN_GOTO:
    begin
      if ASTSOffset[node] = -1 then
      begin
        i := ASTIVal[node];
        if GotoLabelIRId[i] = -1 then GotoLabelIRId[i] := IRNewLabel;
        Result := IRAppend(IR_JUMP, GotoLabelIRId[i], -1, -1, 0, 0);
      end
      else
      begin
        off := ASTSOffset[node];
        len := ASTSLen[node];
        lbId := -1;
        for i := 0 to GotoLabelCount - 1 do
          if TokSlicesMatch(GotoLabelNOff[i], GotoLabelNLen[i], off, len) then
          begin
            if GotoLabelIRId[i] = -1 then
              GotoLabelIRId[i] := IRNewLabel;
            lbId := GotoLabelIRId[i];
            Break;
          end;
        if lbId = -1 then Error('AN_GOTO: undefined label');
        Result := IRAppend(IR_JUMP, lbId, -1, -1, 0, 0);
      end;
    end;
    AN_PAIR, AN_SEQ:
    begin
      left := IRDropManagedStrResult(IRLowerAST(ASTLeft[node]));
      IRMarkStatementNode(left);
      right := IRDropManagedStrResult(IRLowerAST(ASTRight[node]));
      IRMarkStatementNode(right);
      Result := IRAppend(IR_BLOCK, left, right, -1, 0, 0);
    end;

  else
    Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTLeft[node], ASTRight[node], ASTIVal[node], ASTTk[node]);
  end;
end;

procedure IRDump;
var i, blockNum: Integer;
    isLeader: array[0..MAX_IR-1] of Boolean;
    symIdx: Integer;
begin
  for i := 0 to MAX_IR - 1 do
    isLeader[i] := False;

  if IRCount > 0 then
    isLeader[0] := True;

  for i := 0 to IRCount - 1 do
  begin
    if IRKind[i] = IR_LABEL then
      isLeader[i] := True;
    if (IRKind[i] = IR_JUMP) or (IRKind[i] = IR_JUMP_IF_FALSE) then
    begin
      if i + 1 < IRCount then
        isLeader[i + 1] := True;
    end;
  end;

  writeln('IR count=', IRCount);
  blockNum := 0;
  for i := 0 to IRCount - 1 do
  begin
    if isLeader[i] then
    begin
      Inc(blockNum);
      writeln('--- BASIC BLOCK BB', blockNum, ' ---');
    end;
    write(i, ': ', IROpName(IRKind[i]),
          ' a=', IRA[i],
          ' b=', IRB[i],
          ' c=', IRC[i],
          ' ival=', IRIVal[i],
          ' tk=', IRTk[i]);
          
    if (IRKind[i] = IR_LOAD_SYM) or (IRKind[i] = IR_STORE_SYM) or (IRKind[i] = IR_LEA) then
    begin
      symIdx := IRA[i];
      if (symIdx >= 0) and (symIdx < SymCount) then
        write(' [sym=', Syms[symIdx].Name, ']');
    end;
    if IRKind[i] = IR_FIELD then
      write(' [offset=', IRIVal[i], ']');
    if IRKind[i] = IR_INDEX then
      write(' [lo=', IRC[i], ' size=', IRIVal[i], ']');
    writeln;
  end;
end;

procedure IRBuildAndMaybeDump(node: Integer);
begin
  if not DumpIR then Exit;
  IRReset;
  IRLowerAST(node);
  IRVerify;
  IRDump;
end;

{ DWARF -g: record a line-table row at the start address of IR instruction i when
  its source line changes. Called at the top of every backend's statement emit
  loop (defined here, before the per-arch ir_codegen_* files), so CodeLen is the
  address where this instruction's machine code begins. The first row of a proc
  body also drops an entry row at the proc's low_pc and marks the body row
  prologue_end, so `break <func>` skips the prologue cleanly. }
procedure DbgRecordRow(i: Integer);
begin
  if not DebugInfo then Exit;
  if (IRLine[i] = 0) or (IRLine[i] = DwarfLastLine) then Exit;
  if DwarfProcFirstRow and (CurProc >= 0) and (DwarfRowCount < MAX_DWARF_ROWS) then
  begin
    DwarfRowAddr[DwarfRowCount] := Procs[CurProc].BodyAddr;
    DwarfRowLine[DwarfRowCount] := IRLine[i];
    DwarfRowFile[DwarfRowCount] := IRFile[i];
    DwarfRowPrologueEnd[DwarfRowCount] := False;
    Inc(DwarfRowCount);
  end;
  if DwarfRowCount < MAX_DWARF_ROWS then
  begin
    DwarfRowAddr[DwarfRowCount] := CodeLen;
    DwarfRowLine[DwarfRowCount] := IRLine[i];
    DwarfRowFile[DwarfRowCount] := IRFile[i];
    DwarfRowPrologueEnd[DwarfRowCount] := DwarfProcFirstRow;
    Inc(DwarfRowCount);
    DwarfProcFirstRow := False;
  end;
  DwarfLastLine := IRLine[i];
end;

{ ================================================================= }
{  IR optimization pass pipeline (-O1+, shared across all backends) }
{ ================================================================= }
{ Full method + rationale: devdocs/dev/optimization-architecture.md.
  Runs on the shared IR after lowering, BEFORE any backend codegen, so ONE
  implementation optimizes every target (x86-64/i386/arm32/aarch64/riscv32/
  xtensa) AND every frontend (Pascal/C/Nil-Python/.asm) at once. Gated by
  OptLevel at the call site (CompileAST) — -O0 never runs it, so the -O0
  self-host byte-identity gate is untouched by construction. Each pass rewrites
  IR IN PLACE: dead nodes become IR_NOP (every backend already emits nothing
  for IR_NOP) and redundant jumps are dropped. It NEVER rewrites emitted
  machine bytes — branch fixups reference CodeLen and must not move. CompileAST
  runs once per procedure body (IRReset clears the array each time), so every
  pass here reasons over a single self-contained body: reachability and jump
  adjacency are local, with no cross-procedure boundary to special-case. }

function IRIsUncondTransfer(i: Integer): Boolean;
{ Nothing falls through these: control leaves and can only re-enter at a label.
  exit / return-from-proc lower to IR_TERMINATE, goto / break / continue /
  structured control-flow tails to IR_JUMP, raise to IR_RAISE. }
begin
  IRIsUncondTransfer :=
    (IRKind[i] = IR_JUMP) or (IRKind[i] = IR_TERMINATE) or (IRKind[i] = IR_RAISE);
end;

procedure IROptDeadCode;
{ Pass 1 — unreachable-code elimination. Walk the body tracking reachability.
  Code between an unconditional transfer and the next IR_LABEL owns no label,
  so nothing can jump INTO it and the transfer blocks fall-through -> provably
  unreachable; NOP it. Any IR_LABEL is a potential jump target, so it (and the
  code after) is reachable again. Labels are never removed. Operand/value nodes
  sit post-order-adjacent BEFORE their statement root, inside the same
  reachability region as that root, so a live statement never references a node
  that lands in a dead region.

  *** CORRECTNESS INVARIANT (why this is provably safe, hence -O1 not -O2) ***
  This pass is exact — no heuristic, no cost model — but it rests on ONE
  invariant: EVERY control-transfer landing site is a stream IR_LABEL. It holds
  today because PXX has NO computed/indirect jumps: `case` lowers to a
  compare-chain (see AN_CASE guard-rail), exception handlers land on the
  IR_EXC_ENTER label, goto targets are labels. If a future change introduces a
  jump TABLE or any computed `jmp reg`/`jmp [mem]` whose target is not a stream
  IR_LABEL, THIS PASS CAN DELETE A LIVE TARGET — re-gate it (skip bodies with
  the computed jump) or materialise an IR_LABEL at each such target first. This
  invariant is the line between -O1 (provably safe) and -O2 (experimental /
  side-effecting): keep it airtight or move the pass. See
  devdocs/dev/optimization-architecture.md §2. }
var i: Integer; reachable: Boolean;
begin
  reachable := True;
  for i := 0 to IRCount - 1 do
  begin
    if IRKind[i] = IR_LABEL then
      reachable := True
    else if not reachable then
      IRKind[i] := IR_NOP
    else if IRIsUncondTransfer(i) then
      reachable := False;
  end;
end;

procedure IROptRedundantJump;
{ Pass 2 — drop `jmp L; L:`. An unconditional jump whose target label is the
  very next statement (only IR_NOPs, e.g. freshly-killed dead code, in between)
  is a no-op: falling through reaches L identically. Frequent in if/loop
  lowering (a then-branch tail jump over an absent else). }
var i, j: Integer;
begin
  for i := 0 to IRCount - 1 do
    if IRKind[i] = IR_JUMP then
    begin
      j := i + 1;
      while (j < IRCount) and (IRKind[j] = IR_NOP) do Inc(j);
      if (j < IRCount) and (IRKind[j] = IR_LABEL) and (IRIVal[j] = IRA[i]) then
        IRKind[i] := IR_NOP;
    end;
end;

{ NOTE — IR-level constant folding + algebraic identities were implemented and
  MEASURED (2026-07-03), then REJECTED: zero fires on the whole compiler
  self-compile AND on synthetic tests. Reason: PXX already eliminates these
  upstream, so no const-const IR_BINOP (nor an x*1 / x+0 identity operand) ever
  reaches the IR for ANY frontend — Pascal folds source constants in ConstEval
  / AST, the C and Nil-Python frontends share the same AN_BINOP lowering, and
  that lowering guards pointer/index stride with `if elemSize > 1` (ir.inc
  ~3345/3359) so `index * 1` is never emitted. The passes were correct but pure
  dead weight (extra procs + self-host surface, no win), so they are not
  shipped — measured-not-speculative, same call as the rejected allocator bins.
  If a future IR pass (e.g. loop strength-reduction) starts PRODUCING
  const-const binops, revive const-fold then, gated the same way. }

procedure IROptWarnMissedFoldFire(const what: AnsiString);
{ Shared one-shot emit for the missed-optimization tripwire. `what` names the
  opportunity + which pass to revive. -Werror promotes to a hard error. }
begin
  Inc(WarnCount);
  WarnedMissedFold := True;
  if WarnAsError then
  begin
    writeln('pascal26: error: ', what, ' reached codegen — revive the matching IR ',
            'pass in IROptimize (feature-optimization-levels) (warning promoted by -Werror)');
    Halt(1);
  end;
  writeln('pascal26: warning: ', what, ' reached codegen — an IR pass now produces it; ',
          'revive the matching optimization in IROptimize (feature-optimization-levels)');
end;

procedure IROptWarnMissedFold;
{ Tripwire (runs LAST, after every other pass, so it also sees IR the passes
  themselves produced). Three optimizations were measured 0-fire and NOT shipped
  because PXX's frontends already eliminate them upstream — IR const-fold +
  algebraic identities (no foldable IR_BINOP reaches the IR), and if-false /
  if-true DCE (Pascal AND C fold const `if` conditions at AST time, so no
  IR_JUMP_IF_FALSE with a constant condition reaches the IR — measured on both
  frontends). If a future pass starts PRODUCING any of them, warn ONCE per
  compile so the matching pass gets revived instead of silently leaving cycles
  on the floor. Excludes const-const div/mod (`k div 0` legitimately survives to
  raise runtime error 200). Strength reduction (x*2^k -> shl) is separately
  deferred: also 0-fire (array access uses IR_INDEX, not an IR_BINOP multiply)
  AND width-unsafe on the current shl path (its <8-byte cdqe fixup corrupts
  offsets that overflow 32 bits). }
var i, op: Integer; bothConst, ident: Boolean;
begin
  if WarnedMissedFold then Exit;
  for i := 0 to IRCount - 1 do
  begin
    { const-condition branch -> would-be if-false / if-true DCE }
    if (IRKind[i] = IR_JUMP_IF_FALSE) and (IRKind[IRB[i]] = IR_CONST_INT) then
    begin
      IROptWarnMissedFoldFire('a constant-condition IR_JUMP_IF_FALSE (if-false/if-true DCE)');
      Exit;
    end;
    if IRKind[i] = IR_BINOP then
    begin
      op := IRC[i];
      bothConst := (IRKind[IRA[i]] = IR_CONST_INT) and (IRKind[IRB[i]] = IR_CONST_INT) and
                   ((op = Ord(tkPlus)) or (op = Ord(tkMinus)) or (op = Ord(tkStar)) or
                    (op = Ord(tkAnd)) or (op = Ord(tkOr)) or (op = Ord(tkXor)));
      ident := False;
      if (op = Ord(tkPlus)) or (op = Ord(tkOr)) or (op = Ord(tkXor)) then
        ident := ((IRKind[IRB[i]] = IR_CONST_INT) and (IRIVal[IRB[i]] = 0)) or
                 ((IRKind[IRA[i]] = IR_CONST_INT) and (IRIVal[IRA[i]] = 0))
      else if op = Ord(tkMinus) then
        ident := (IRKind[IRB[i]] = IR_CONST_INT) and (IRIVal[IRB[i]] = 0)
      else if op = Ord(tkStar) then
        ident := ((IRKind[IRB[i]] = IR_CONST_INT) and (IRIVal[IRB[i]] = 1)) or
                 ((IRKind[IRA[i]] = IR_CONST_INT) and (IRIVal[IRA[i]] = 1))
      else if op = Ord(tkAnd) then
        ident := ((IRKind[IRB[i]] = IR_CONST_INT) and (IRIVal[IRB[i]] = -1)) or
                 ((IRKind[IRA[i]] = IR_CONST_INT) and (IRIVal[IRA[i]] = -1))
      else if op = Ord(tkDiv) then
        ident := (IRKind[IRB[i]] = IR_CONST_INT) and (IRIVal[IRB[i]] = 1);
      if bothConst or ident then
      begin
        IROptWarnMissedFoldFire('a foldable IR_BINOP (const-const or identity operand; const-fold/identities)');
        Exit;
      end;
    end;
  end;
end;

procedure IROptimize;
{ Ordered -O1 IR pass pipeline. Dead-code first (its NOPs expose more
  jump-to-next-label pairs), then redundant-jump. IROptWarnMissedFold runs LAST
  as a tripwire (see its note + the const-fold NOTE above). New IR-level passes
  slot in before the tripwire — this is the shared, all-target, all-frontend
  home the optimization arc builds on. }
begin
  IROptDeadCode;
  IROptRedundantJump;
  { Opt-in only: with -O2 the default, inline produces foldable BINOPs on nearly
    every compile, so this dev tripwire would fire on ordinary builds. Run it only
    under --warn-missed-fold when re-measuring whether const-fold is worth reviving
    (feature-revive-const-fold-identity-pass). }
  if WarnMissedFold then IROptWarnMissedFold;
end;
