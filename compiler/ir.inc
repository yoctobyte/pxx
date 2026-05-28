procedure IRReset;
begin
  IRCount := 0;
  IRLabelCount := 0;
end;

function IRAppend(kind, a, b, c: Integer; ival: Int64; tk: Integer): Integer;
begin
  if IRCount >= MAX_IR then Error('IR overflow');
  IRKind[IRCount] := kind;
  IRA[IRCount] := a;
  IRB[IRCount] := b;
  IRC[IRCount] := c;
  IRIVal[IRCount] := ival;
  IRTk[IRCount] := tk;
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
    IR_BLOCK: Result := 'block';
    IR_UNSUPPORTED: Result := 'unsupported';
    IR_IF: Result := 'if';
    IR_LABEL: Result := 'label';
    IR_JUMP: Result := 'jump';
    IR_JUMP_IF_FALSE: Result := 'jump_if_false';
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

procedure IRVerify;
var i: Integer;
begin
  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_CONST_INT, IR_CONST_STR, IR_NOP, IR_LABEL:
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
      end;

      IR_CALL:
      begin
        if (IRA[i] >= ProcCount) then
          Error('invalid IR proc reference in call');
        IRRequireOptionalNode(IRB[i], 'call first arg');
        IRRequireOptionalNode(IRC[i], 'call last arg');
      end;

      IR_WRITE:
        IRRequireNode(IRA[i], 'write');

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
        if not IRLabelExists(IRA[i]) then
          Error('invalid IR jump target');
      end;

      IR_JUMP_IF_FALSE:
      begin
        if not IRLabelExists(IRA[i]) then
          Error('invalid IR conditional jump target');
        IRRequireNode(IRB[i], 'jump condition');
      end;

      IR_UNSUPPORTED:
        begin end;

    else
      Error('unknown IR opcode');
    end;
  end;
end;

function IRLowerAST(node: Integer): Integer;
var left, right, seq, item, value, outNode, first, last: Integer;
    pairNode, condNode, elseNode: Integer;
    elseLabel, endLabel, endLabelNode: Integer;
begin
  if node = -1 then
  begin
    Result := -1;
    Exit;
  end;

  case ASTKind[node] of
    AN_INT_LIT, AN_BOOL_LIT:
      Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], ASTTk[node]);

    AN_STR_LIT:
      Result := IRAppend(IR_CONST_STR, ASTSOffset[node], ASTSLen[node], -1, 0, ASTTk[node]);

    AN_IDENT:
      Result := IRAppend(IR_LOAD_SYM, ASTIVal[node], -1, -1, 0, ASTTk[node]);

    AN_BINOP:
    begin
      left := IRLowerAST(ASTLeft[node]);
      right := IRLowerAST(ASTRight[node]);
      Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, ASTTk[node]);
    end;

    AN_ASSIGN:
    begin
      value := IRLowerAST(ASTRight[node]);
      if ASTKind[ASTLeft[node]] = AN_IDENT then
        Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]])
      else
        Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTKind[ASTLeft[node]], value, 0, ASTTk[node]);
    end;

    AN_CALL:
    begin
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        if first < 0 then first := value;
        last := value;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_CALL, ASTIVal[node], first, last, 0, ASTTk[node]);
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
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      last := IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      elseNode := -1;
      if ASTRight[pairNode] <> -1 then
        elseNode := IRLowerAST(ASTRight[pairNode]);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      if elseNode <> -1 then
        Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0)
      else
        Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_WRITE, AN_WRITELN:
    begin
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        if ASTKind[item] = AN_ARG then
          value := IRLowerAST(ASTLeft[item])
        else if ASTKind[item] = AN_PAIR then
          value := IRLowerAST(ASTLeft[item])
        else
          value := IRLowerAST(item);
        outNode := IRAppend(IR_WRITE, value, -1, -1, 0, IRTk[value]);
        if first < 0 then first := outNode;
        last := outNode;
        item := ASTRight[item];
      end;
      if ASTKind[node] = AN_WRITELN then
        Result := IRAppend(IR_WRITELN, first, last, -1, 0, 0)
      else
        Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
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
          item := IRLowerAST(ASTLeft[seq]);
          seq := ASTRight[seq];
        end
        else
        begin
          item := IRLowerAST(seq);
          seq := -1;
        end;
        if first < 0 then first := item;
        last := item;
      end;
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_SEQ:
    begin
      left := IRLowerAST(ASTLeft[node]);
      right := IRLowerAST(ASTRight[node]);
      Result := IRAppend(IR_BLOCK, left, right, -1, 0, 0);
    end;

  else
    Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTLeft[node], ASTRight[node], ASTIVal[node], ASTTk[node]);
  end;
end;

procedure IRDump;
var i: Integer;
begin
  writeln('IR count=', IRCount);
  for i := 0 to IRCount - 1 do
  begin
    write(i, ': ', IROpName(IRKind[i]),
          ' a=', IRA[i],
          ' b=', IRB[i],
          ' c=', IRC[i],
          ' ival=', IRIVal[i],
          ' tk=', IRTk[i]);
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
