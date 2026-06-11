{ ===== IR -> i386 machine code (cross target, minimal and growing) =====

  Vertical slices of the target-parameterized backend
  (feature-target-i386). Deliberately NOT a fork of the 4k-line x86-64
  emitter: ops are added one by one as they are needed, and any IR
  construct this walker does not know is a hard compile error — a cross
  target must refuse, never mis-compile. The x86-64 path is untouched;
  IREmitMachineCode dispatches here when TargetArch = TARGET_I386.

  i386 conventions used: int 0x80 syscalls (eax=nr, ebx/ecx/edx args),
  absolute 4-byte data refs (EmitDataRef emits 4 bytes under this target,
  patched by writeELF32). Value model mirrors x86-64: expression results
  in eax; binop = eval left, push, eval right, mov ecx,eax, pop eax.
  Jump and setcc encodings are REX-free and identical to x86-64, so label
  handling and EmitSetcc are shared. }

procedure EmitSetcc(opTk: Integer; signed: Boolean); forward;

procedure IREmitNode386(node: Integer); forward;

procedure EmitwriteInt386;
{ eax = signed 32-bit value -> decimal on stdout. Transcription of
  symtab.inc EmitwriteInt to 32-bit registers and the int 0x80 write. }
var jnsOff, loopStart: Integer;
begin
  EmitB($85); EmitB($C0);                          { test eax, eax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);         { jns .positive }
  EmitB($F7); EmitB($D8);                          { neg eax }
  EmitB($50);                                      { push eax }
  EmitwriteSyscall(MINUS_OFFSET, 1);               { clobbers eax..edx }
  EmitB($58);                                      { pop eax }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($31); EmitB($C9);                          { xor ecx, ecx  (digit count) }
  EmitB($BB); EmitI32(10);                         { mov ebx, 10 }
  EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE); { mov edi, buf end }
  loopStart := CodeLen;
  EmitB($31); EmitB($D2);                          { xor edx, edx }
  EmitB($F7); EmitB($F3);                          { div ebx }
  EmitB($80); EmitB($C2); EmitB($30);              { add dl, '0' }
  EmitB($4F);                                      { dec edi }
  EmitB($88); EmitB($17);                          { mov [edi], dl }
  EmitB($41);                                      { inc ecx }
  EmitB($85); EmitB($C0);                          { test eax, eax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1))); { jnz .loop }
  { write(1, edi, ecx): eax=4, ebx=1, ecx=buf, edx=len }
  EmitB($89); EmitB($CA);                          { mov edx, ecx }
  EmitB($89); EmitB($F9);                          { mov ecx, edi }
  EmitB($BB); EmitI32(STDOUT);                     { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                          { mov eax, 4 }
  EmitB($CD); EmitB($80);                          { int 0x80 }
end;

procedure EmitwriteChar386;
{ eax = char byte value -> write 1 byte to stdout }
begin
  EmitB($BF); EmitDataRef(INTBUF_OFFSET);            { mov edi, INTBUF_OFFSET }
  EmitB($88); EmitB($07);                            { mov [edi], al }
  EmitB($B8); EmitI32(4);                            { mov eax, 4 (write) }
  EmitB($BB); EmitI32(STDOUT);                       { mov ebx, 1 }
  EmitB($B9); EmitDataRef(INTBUF_OFFSET);            { mov ecx, INTBUF_OFFSET }
  EmitB($BA); EmitI32(1);                            { mov edx, 1 }
  EmitB($CD); EmitB($80);                            { int 0x80 }
end;

procedure EmitwriteUInt386;
{ eax = unsigned 32-bit int -> decimal on stdout }
var loopStart: Integer;
begin
  EmitB($31); EmitB($C9);                                { xor ecx, ecx }
  EmitB($BB); EmitI32(10);                               { mov ebx, 10 }
  EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);  { mov edi, INTBUF_OFFSET + INTBUF_SIZE }
  loopStart := CodeLen;
  EmitB($31); EmitB($D2);                                { xor edx, edx }
  EmitB($F7); EmitB($F3);                                { div ebx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($4F);                                            { dec edi }
  EmitB($88); EmitB($17);                                { mov [edi], dl }
  EmitB($41);                                            { inc ecx }
  EmitB($85); EmitB($C0);                                { test eax, eax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  EmitB($89); EmitB($CA);                                { mov edx, ecx }
  EmitB($89); EmitB($F9);                                { mov ecx, edi }
  EmitB($BB); EmitI32(STDOUT);                           { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                                { mov eax, 4 }
  EmitB($CD); EmitB($80);                                { int 0x80 }
end;

procedure EmitwriteIntW386(width: Integer);
{ eax = signed 32-bit int -> right-aligned in field of min width chars }
var jnsOff, jleOff, jzOff, loopStart: Integer;
begin
  EmitB($31); EmitB($F6);                                { xor esi, esi }
  EmitB($85); EmitB($C0);                                { test eax, eax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);               { jns .positive }
  EmitB($F7); EmitB($D8);                                { neg eax }
  EmitB($46);                                            { inc esi }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($31); EmitB($C9);                                { xor ecx, ecx }
  EmitB($BB); EmitI32(10);                               { mov ebx, 10 }
  EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);  { mov edi, INTBUF_OFFSET + INTBUF_SIZE }
  loopStart := CodeLen;
  EmitB($31); EmitB($D2);                                { xor edx, edx }
  EmitB($F7); EmitB($F3);                                { div ebx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($4F);                                            { dec edi }
  EmitB($88); EmitB($17);                                { mov [edi], dl }
  EmitB($41);                                            { inc ecx }
  EmitB($85); EmitB($C0);                                { test eax, eax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  EmitB($57);                                            { push edi }
  EmitB($51);                                            { push ecx }
  EmitB($B8); EmitI32(width);                            { mov eax, width }
  EmitB($29); EmitB($C8);                                { sub eax, ecx }
  EmitB($29); EmitB($F0);                                { sub eax, esi }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($50);                                            { push eax }
  EmitB($B8); EmitI32(4);                                { mov eax, 4 }
  EmitB($BB); EmitI32(STDOUT);                           { mov ebx, 1 }
  EmitB($B9); EmitDataRef(SpacesOffset);                 { mov ecx, spaces }
  EmitB($5A);                                            { pop edx }
  EmitB($CD); EmitB($80);                                { int 0x80 }
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  EmitB($85); EmitB($F6);                                { test esi, esi }
  EmitB($74); jzOff := CodeLen; EmitB(0);                { jz .no_sign }
  EmitwriteSyscall(MINUS_OFFSET, 1);
  Code[jzOff] := Byte(CodeLen - (jzOff + 1));
  EmitB($5A);                                            { pop edx }
  EmitB($59);                                            { pop ecx }
  EmitB($BB); EmitI32(STDOUT);                           { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                                { mov eax, 4 }
  EmitB($CD); EmitB($80);                                { int 0x80 }
end;

procedure EmitwriteUIntW386(width: Integer);
{ eax = unsigned 32-bit int -> right-aligned in field of min width chars }
var jleOff, loopStart: Integer;
begin
  EmitB($31); EmitB($C9);                                { xor ecx, ecx }
  EmitB($BB); EmitI32(10);                               { mov ebx, 10 }
  EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);  { mov edi, INTBUF_OFFSET + INTBUF_SIZE }
  loopStart := CodeLen;
  EmitB($31); EmitB($D2);                                { xor edx, edx }
  EmitB($F7); EmitB($F3);                                { div ebx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($4F);                                            { dec edi }
  EmitB($88); EmitB($17);                                { mov [edi], dl }
  EmitB($41);                                            { inc ecx }
  EmitB($85); EmitB($C0);                                { test eax, eax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  EmitB($57);                                            { push edi }
  EmitB($51);                                            { push ecx }
  EmitB($B8); EmitI32(width);                            { mov eax, width }
  EmitB($29); EmitB($C8);                                { sub eax, ecx }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($50);                                            { push eax }
  EmitB($B8); EmitI32(4);                                { mov eax, 4 }
  EmitB($BB); EmitI32(STDOUT);                           { mov ebx, 1 }
  EmitB($B9); EmitDataRef(SpacesOffset);                 { mov ecx, spaces }
  EmitB($5A);                                            { pop edx }
  EmitB($CD); EmitB($80);                                { int 0x80 }
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  EmitB($5A);                                            { pop edx }
  EmitB($59);                                            { pop ecx }
  EmitB($BB); EmitI32(STDOUT);                           { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                                { mov eax, 4 }
  EmitB($CD); EmitB($80);                                { int 0x80 }
end;

procedure IREmit386CheckScalarSym(symIdx: Integer; const what: AnsiString);
{ "Fat slot" symbol model: the parser still lays out 8-byte slots (BSS and
  frame, 64-bit TypeSize), and i386 code reads/writes only the low 4 bytes.
  Sound because BSS is zeroed and 4-byte stores/loads are paired — the high
  half is never read. Only ordinal scalars fit that model; refuse the rest. }
begin
  if (symIdx < 0) or (symIdx >= SymCount) then
    Error('target i386: bad symbol in ' + what);
  if not (Syms[symIdx].Kind in [skGlobal, skLocal, skParam]) then
    Error('target i386: symbol kind not supported yet (' + what + ')');
  if Syms[symIdx].IsArray then
    Error('target i386: arrays not yet supported');
  if not TypeIsOrdinal(Syms[symIdx].TypeKind) then
    Error('target i386: only ordinal variables supported yet');
end;

procedure IREmitNode386(node: Integer);
var
  valNode, si, left, right, op, pi, argNode, nArgs, wid, sz, i, j, base: Integer;
  sVal: AnsiString;
  emsg: AnsiString;
  tk: TTypeKind;
  sgn: Boolean;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_CONST_INT:
      begin
        if (IRIVal[node] > 2147483647) or (IRIVal[node] < -2147483648) then
          Error('target i386: integer constant exceeds 32 bits');
        EmitB($B8); EmitI32(IRIVal[node]);           { mov eax, imm32 }
      end;

    IR_LOAD_SYM:
      begin
        IREmit386CheckScalarSym(IRA[node], 'load');
        si := IRA[node];
        tk := Syms[si].TypeKind;
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if Syms[si].Kind = skGlobal then
        begin
          if sz = 1 then
          begin
            if sgn then
              begin EmitB($0F); EmitB($BE); EmitB($05); EmitGlobRef(Syms[si].Offset); end
            else
              begin EmitB($0F); EmitB($B6); EmitB($05); EmitGlobRef(Syms[si].Offset); end;
          end
          else if sz = 2 then
          begin
            if sgn then
              begin EmitB($0F); EmitB($BF); EmitB($05); EmitGlobRef(Syms[si].Offset); end
            else
              begin EmitB($0F); EmitB($B7); EmitB($05); EmitGlobRef(Syms[si].Offset); end;
          end
          else
            begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end;
        end
        else
        begin
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);  { mov eax, [ebp+off] }
            if sz = 1 then
            begin
              if sgn then
                begin EmitB($0F); EmitB($BE); EmitB($00); end
              else
                begin EmitB($0F); EmitB($B6); EmitB($00); end;
            end
            else if sz = 2 then
            begin
              if sgn then
                begin EmitB($0F); EmitB($BF); EmitB($00); end
              else
                begin EmitB($0F); EmitB($B7); EmitB($00); end;
            end
            else
              begin EmitB($8B); EmitB($00); end;
          end
          else
          begin
            if sz = 1 then
            begin
              if sgn then
                begin EmitB($0F); EmitB($BE); EmitB($85); EmitI32(Syms[si].Offset); end
              else
                begin EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[si].Offset); end;
            end
            else if sz = 2 then
            begin
              if sgn then
                begin EmitB($0F); EmitB($BF); EmitB($85); EmitI32(Syms[si].Offset); end
              else
                begin EmitB($0F); EmitB($B7); EmitB($85); EmitI32(Syms[si].Offset); end;
            end
            else
              begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end;
          end;
        end;
      end;

    IR_STORE_SYM:
      begin
        IREmit386CheckScalarSym(IRA[node], 'store');
        IREmitNode386(IRB[node]);
        si := IRA[node];
        tk := Syms[si].TypeKind;
        sz := TypeSize(tk);
        if Syms[si].Kind = skGlobal then
        begin
          if sz = 1 then
            begin EmitB($A2); EmitGlobRef(Syms[si].Offset); end
          else if sz = 2 then
            begin EmitB($66); EmitB($A3); EmitGlobRef(Syms[si].Offset); end
          else
            begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end;
        end
        else
        begin
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($50);                                         { push eax }
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);  { mov eax, [ebp+off] }
            EmitB($59);                                         { pop ecx }
            if sz = 1 then
              begin EmitB($88); EmitB($08); end
            else if sz = 2 then
              begin EmitB($66); EmitB($89); EmitB($08); end
            else
              begin EmitB($89); EmitB($08); end;
          end
          else
          begin
            if sz = 1 then
              begin EmitB($88); EmitB($85); EmitI32(Syms[si].Offset); end
            else if sz = 2 then
              begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end
            else
              begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end;
          end;
        end;
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
        begin
          EmitB($B8); EmitGlobRef(Syms[si].Offset);          { mov eax, abs32 }
        end
        else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
        begin
          EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);  { mov eax, [ebp+off] }
        end
        else
        begin
          EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset);  { lea eax, [ebp+off] }
        end;
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);
        { tyUnknown: synthesized integer nodes (e.g. the for-loop increment)
          carry tk=0; x86-64 treats them as integers, so do we. }
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
          Error('target i386: non-integer binop not yet supported');
        IREmitNode386(left);
        EmitB($50);                                  { push eax }
        IREmitNode386(right);
        EmitB($89); EmitB($C1);                      { mov ecx, eax }
        EmitB($58);                                  { pop eax }
        if op = Ord(tkPlus) then begin EmitB($01); EmitB($C8); end       { add eax, ecx }
        else if op = Ord(tkMinus) then begin EmitB($29); EmitB($C8); end { sub eax, ecx }
        else if op = Ord(tkStar) then begin EmitB($0F); EmitB($AF); EmitB($C1); end { imul eax, ecx }
        else if op = Ord(tkDiv) then begin EmitB($99); EmitB($F7); EmitB($F9); end { cdq; idiv ecx }
        else if op = Ord(tkMod) then
        begin
          EmitB($99); EmitB($F7); EmitB($F9);        { cdq; idiv ecx }
          EmitB($89); EmitB($D0);                    { mov eax, edx }
        end
        else if op = Ord(tkAnd) then begin EmitB($21); EmitB($C8); end   { and eax, ecx }
        else if op = Ord(tkOr) then begin EmitB($09); EmitB($C8); end    { or eax, ecx }
        else if op = Ord(tkShl) then begin EmitB($D3); EmitB($E0); end   { shl eax, cl }
        else if op = Ord(tkIdent) then begin EmitB($D3); EmitB($E8); end { 'shr' parses as ident; shr eax, cl }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitB($39); EmitB($C8);                    { cmp eax, ecx }
          EmitSetcc(op, True);                       { REX-free; shared with x86-64 }
        end
        else
          Error('target i386: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi < 0 then
          Error('target i386: builtin/special call not yet supported');
        if ProcExternal[pi] then
          Error('target i386: external calls not yet supported');
        if TypeIsAggregate(Procs[pi].RetType) then
          Error('target i386: aggregate-valued results not yet supported');
        { Internal i386 convention: evaluate and push args left to right
          (leftmost ends up deepest, matching the callee's spill formula),
          call, then the caller pops the arg area. Result in eax. }
        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode386(IRA[argNode]);
          EmitB($50);                                { push eax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs <> Procs[pi].ParamCount then
          Error('target i386: call argument count mismatch (defaults not supported yet)');
        EmitCallProc(pi);                            { E8 rel32 + fixup, same as x86-64 }
        if nArgs > 0 then
        begin
          EmitB($81); EmitB($C4); EmitI32(nArgs * 4); { add esp, nArgs*4 }
        end;
      end;

    IR_SYSCALL:
      begin
        { Raw syscall (int 0x80): args (nr, a0..a5) pushed left-to-right,
          then loaded into eax, ebx, ecx, edx, esi, edi, ebp from the stack.
          ebp doubles as the frame pointer, so a full 6-arg syscall saves and
          restores it around the trap. Result stays in eax. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode386(IRA[argNode]);
          EmitB($50);                                { push eax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        base := 0;
        if nArgs = 7 then
        begin
          EmitB($55);                                { push ebp (save frame ptr) }
          base := 4;
        end;
        for i := 0 to nArgs - 1 do
        begin
          j := 0;                                    { eax }
          if i = 1 then j := 3                       { ebx }
          else if i = 2 then j := 1                  { ecx }
          else if i = 3 then j := 2                  { edx }
          else if i = 4 then j := 6                  { esi }
          else if i = 5 then j := 7                  { edi }
          else if i = 6 then j := 5;                 { ebp }
          EmitB($8B); EmitB($44 + (j shl 3)); EmitB($24);
          EmitB(base + (nArgs - 1 - i) * 4);         { mov reg, [esp+disp8] }
        end;
        EmitB($CD); EmitB($80);                      { int 0x80 }
        if nArgs = 7 then
          EmitB($5D);                                { pop ebp (restore frame ptr) }
        if nArgs > 0 then
        begin
          EmitB($81); EmitB($C4); EmitI32(nArgs * 4); { add esp, nArgs*4 }
        end;
      end;

    IR_NEG:
      begin
        IREmitNode386(IRA[node]);
        EmitB($F7); EmitB($D8);                      { neg eax }
      end;

    IR_NOT:
      begin
        IREmitNode386(IRA[node]);
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitB($F7); EmitB($D0);                    { not eax }
        end
        else
        begin
          EmitB($83); EmitB($F0); EmitB($01);        { xor eax, 1 }
        end;
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid := IRB[node];
        if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if (wid > 0) and (wid > Strs[si].Len) then
          begin
            EnsureSpaces;
            EmitB($B8); EmitI32(4);
            EmitB($BB); EmitI32(STDOUT);
            EmitB($B9); EmitDataRef(SpacesOffset);
            EmitB($BA); EmitI32(wid - Strs[si].Len);
            EmitB($CD); EmitB($80);
          end;
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else
        begin
          tk := IntToTypeKind(IRTk[node]);
          if tk = tyChar then
          begin
            IREmitNode386(valNode);
            if wid > 1 then
            begin
              EnsureSpaces;
              EmitB($50);
              EmitB($B8); EmitI32(4);
              EmitB($BB); EmitI32(STDOUT);
              EmitB($B9); EmitDataRef(SpacesOffset);
              EmitB($BA); EmitI32(wid - 1);
              EmitB($CD); EmitB($80);
              EmitB($58);
            end;
            EmitwriteChar386;
          end
          else if TypeIsOrdinal(tk) then
          begin
            IREmitNode386(valNode);
            if not TypeSigned(tk) then
            begin
              if wid > 0 then EmitwriteUIntW386(wid) else EmitwriteUInt386;
            end
            else
            begin
              if wid > 0 then EmitwriteIntW386(wid) else EmitwriteInt386;
            end;
          end
          else
            Error('target i386: write of this operand not yet supported');
        end;
      end;

    IR_WRITELN:
      EmitwriteSyscall(NEWLINE_OFFSET, 1);

    IR_TERMINATE:
      begin
        { Exit / Halt. Mirrors x86-64: Halt(n) = exit syscall with code;
          Exit inside a proc = inline epilogue (target-dispatched). }
        if IRIVal[node] = AN_HALT then
        begin
          if IRA[node] <> -1 then
          begin
            IREmitNode386(IRA[node]);                { code -> eax }
            EmitB($89); EmitB($C3);                  { mov ebx, eax }
            EmitB($B8); EmitI32(252);                { mov eax, 252 (exit_group) }
            EmitB($CD); EmitB($80);                  { int 0x80 }
          end
          else
            EmitExit(0);
        end
        else
        begin
          if CurProc >= 0 then
            EmitProcEpilog(Procs[CurProc].RetSymIdx)
          else
            EmitExit(0);
        end;
      end;

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

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNode386(IRB[i]);                     { condition -> eax }
          EmitB($85); EmitB($C0);                    { test eax, eax }
          EmitB($0F); EmitB($84);                    { jz rel32 }
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

      IR_CALL:
        begin
          if IRIVal[i] = 1 then                      { statement-level call }
            IREmitNode386(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNode386(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL: ; { operands, emitted by parents }

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
