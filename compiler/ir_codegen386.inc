{ ===== IR -> i386 machine code (cross target, minimal and growing) =====

  First vertical slice of the target-parameterized backend
  (feature-target-i386). Deliberately NOT a fork of the 4k-line x86-64
  emitter: ops are added one by one as they are needed, and any IR
  construct this walker does not know is a hard compile error — a cross
  target must refuse, never mis-compile. The x86-64 path is untouched;
  IREmitMachineCode dispatches here when TargetArch = TARGET_I386.

  i386 conventions used: int 0x80 syscalls (eax=nr, ebx/ecx/edx args),
  absolute 4-byte data refs (EmitDataRef emits 4 bytes under this target,
  patched by writeELF32). Jump encodings (E9 / 0F 8x rel32) are identical
  to x86-64, so label handling mirrors IREmitMachineCode. }

procedure IREmitNode386(node: Integer);
var
  valNode, si: Integer;
  sVal: AnsiString;
  emsg: AnsiString;
begin
  case IRKind[node] of
    IR_NOP, IR_CONST_STR, IR_BLOCK: ;

    IR_WRITE:
      begin
        valNode := IRA[node];
        if (IRKind[valNode] = IR_CONST_STR) and (IRB[node] <= 0) then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else
          Error('target i386: write of this operand not yet supported');
      end;

    IR_WRITELN:
      EmitwriteSyscall(NEWLINE_OFFSET, 1);

    else
      begin
        emsg := 'target i386: IR op not yet supported: ';
        emsg := emsg + IROpName(IRKind[node]);
        Error(emsg);
      end;
  end;
end;

procedure IREmitMachineCode386;
var i, lblId, pos, targetOffset, f: Integer;
    LabelPositions: array[0..MAX_IR-1] of Integer;
    LabelFixupPos: array[0..2047] of Integer;
    LabelFixupTarget: array[0..2047] of Integer;
    LabelFixupCount: Integer;
begin
  for i := 0 to MAX_IR - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_LABEL:
        begin
          lblId := Integer(IRIVal[i]);
          if (lblId >= 0) and (lblId < MAX_IR) then
            LabelPositions[lblId] := CodeLen;
        end;

      IR_JUMP:
        begin
          lblId := IRA[i];
          EmitB($E9);
          if LabelPositions[lblId] <> -1 then
            EmitI32(LabelPositions[lblId] - (CodeLen + 4))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_WRITE, IR_WRITELN:
        IREmitNode386(i);

      IR_NOP, IR_CONST_STR, IR_BLOCK: ;

      else
        IREmitNode386(i); { unknown statement op -> hard error inside }
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in i386 IR codegen');
    Patch32(pos, targetOffset - (pos + 4));
  end;
end;
