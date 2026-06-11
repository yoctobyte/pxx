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

procedure EmitAcquireHeapLock386;
begin
  { i386 threadsafe heap locking not implemented yet; non-threadsafe = no-op.
    --threadsafe on i386 is rejected at the runtime guard. }
end;

procedure EmitReleaseHeapLock386;
begin
end;

procedure EmitHeapAllocLocked386;
{ eax = requested payload bytes. Returns payload pointer in eax. Mirrors
  EmitHeapAllocLocked: delegate to the Pascal PXXAlloc(size, align=8). i386
  internal ABI: push args left-to-right (arg0 deepest), caller pops. }
var pi: Integer;
begin
  EmitB($51);                         { push ecx (caller-saved) }
  EmitB($52);                         { push edx }
  EmitB($50);                         { push eax = arg0 (size) }
  EmitB($6A); EmitB($08);             { push 8  = arg1 (align) }
  pi := FindProc('PXXAlloc');
  if pi < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(pi);                   { eax = pointer }
  EmitB($81); EmitB($C4); EmitI32(8); { add esp, 8 (pop args) }
  EmitB($5A);                         { pop edx }
  EmitB($59);                         { pop ecx }
end;

procedure EmitHeapFreeLocked386;
{ eax = payload pointer. Delegate to Pascal PXXFree(p). nil is ignored inside. }
var pi: Integer;
begin
  EmitB($51);                         { push ecx }
  EmitB($52);                         { push edx }
  EmitB($50);                         { push eax = arg0 (p) }
  pi := FindProc('PXXFree');
  if pi < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(pi);
  EmitB($81); EmitB($C4); EmitI32(4); { add esp, 4 }
  EmitB($5A);                         { pop edx }
  EmitB($59);                         { pop ecx }
end;

procedure EmitStrIncRef386;
{ eax = managed-string handle. Retain (calls Pascal PXXStrIncRef). eax clobbered. }
var pi: Integer;
begin
  EmitB($50);                         { push eax (arg0 = p) }
  pi := FindProc('PXXStrIncRef');
  if pi < 0 then Error('compiler error: PXXStrIncRef not found');
  EmitCallProc(pi);
  EmitB($81); EmitB($C4); EmitI32(4); { add esp, 4 }
end;

procedure EmitStrDecRef386;
{ eax = managed-string handle. Release (calls Pascal PXXStrDecRef). eax clobbered. }
var pi: Integer;
begin
  EmitB($50);                         { push eax (arg0 = p) }
  pi := FindProc('PXXStrDecRef');
  if pi < 0 then Error('compiler error: PXXStrDecRef not found');
  EmitCallProc(pi);
  EmitB($81); EmitB($C4); EmitI32(4); { add esp, 4 }
end;

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
  { Ordinals plus pointer-sized handles (managed-string/pointer/class): the
    handle is a TARGET_PTR_SIZE scalar in the slot. Refcount bookkeeping for
    managed strings happens in the IR_STORE_MEM publish path, not here. }
  if not (TypeIsOrdinal(Syms[symIdx].TypeKind) or
          (Syms[symIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
    Error('target i386: only ordinal/pointer/string variables supported yet');
end;

procedure IREmitNode386(node: Integer);
var
  valNode, si, left, right, op, pi, argNode, nArgs, wid, sz, i, j, base: Integer;
  classIdx, elemSize, lo: Integer;
  sVal: AnsiString;
  emsg: AnsiString;
  tk, lhsTk, rhsTk: TTypeKind;
  sgn: Boolean;
  pNilLhs, pLoopLhs, pNilRhs, pLoopRhs, pCap, nextJmp, nextJmp2, falseJmp: Integer;
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

    IR_CONST_STR:
      begin
        { Address of the interned [len:8][data] struct (inline tyString value). }
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitB($B8); EmitDataRef(Strs[si].Offset);    { mov eax, str_struct_addr }
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
        si := IRA[node];
        if Syms[si].TypeKind = tyAnsiString then
        begin
          { Managed-string assignment to a variable: build the new handle, then
            publish into the slot (release old). }
          valNode := IRB[node];
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            j := InternStr(sVal);
            EmitB($68); EmitI32(Strs[j].Len);           { push len }
            EmitB($68); EmitDataRef(Strs[j].Offset + 8); { push src }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNode386(valNode);                     { eax = char code }
            EmitB($50);                                 { push eax (char code) }
            EmitB($6A); EmitB($01);                     { push 1 (len) }
            EmitB($8D); EmitB($44); EmitB($24); EmitB($04); { lea eax, [esp+4] (ptr to char code) }
            EmitB($50);                                 { push eax (src) }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
            EmitB($59);                                 { pop ecx (restore stack) }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyString then
          begin
            IREmitNode386(valNode);                     { eax = inline string buffer address }
            EmitB($50);                                 { push eax }
            EmitB($8B); EmitB($08);                     { mov ecx, [eax] (len) }
            EmitB($83); EmitB($C0); EmitB($08);         { add eax, 8 (src) }
            EmitB($51);                                 { push ecx (len) }
            EmitB($50);                                 { push eax (src) }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
            EmitB($59);                                 { pop ecx }
          end
          else
          begin
            IREmitNode386(valNode);                     { eax = source handle }
            if not (((IRKind[valNode] = IR_BINOP) and
                     (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
                    ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
            begin
              EmitB($50);                               { push eax (arg0) }
              pi := FindProc('PXXStrIncRef');
              if pi < 0 then Error('compiler error: PXXStrIncRef not found');
              EmitCallProc(pi);
              EmitB($58);                               { pop eax }
            end;
          end;

          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($50);                                           { push eax (new handle) }
            EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset);    { mov ecx, [ebp+off] (caller slot addr) }
            EmitB($8B); EmitB($01);                               { mov eax, [ecx] (old) }
            EmitB($50);                                           { push eax (old) }
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04);       { mov eax, [esp+4] (new) }
            EmitB($89); EmitB($01);                               { mov [ecx], eax }
            EmitB($58);                                           { pop eax (old) }
            EmitB($50);                                           { push eax (arg0 = old) }
            pi := FindProc('PXXStrDecRef');
            if pi < 0 then Error('compiler error: PXXStrDecRef not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(4);                   { add esp, 4 }
            EmitB($58);                                           { pop eax (new handle, discard) }
          end
          else
          begin
            EmitB($50);                                   { push new handle }
            { eax = old handle from slot }
            if Syms[si].Kind = skGlobal then
              begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end   { mov eax, [slot] }
            else
              begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end; { mov eax, [ebp+off] }
            EmitB($50);                                   { push eax (arg0 = old) }
            pi := FindProc('PXXStrDecRef');
            if pi < 0 then Error('compiler error: PXXStrDecRef not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(4);           { add esp, 4 }
            EmitB($58);                                   { pop eax (new handle) }
            if Syms[si].Kind = skGlobal then
              begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end   { mov [slot], eax }
            else
              begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end; { mov [ebp+off], eax }
          end;
          Exit;
        end;
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
        if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
        begin
          { Dynamic array: the slot holds the heap data pointer; load it (mov),
            so indexing/Length operate on the heap block. v1: no copy-on-write
            in write mode (single-owner arrays only). }
          if Syms[si].Kind = skGlobal then
            begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end          { mov eax, [slot] }
          else
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end; { mov eax, [ebp+off] }
        end
        else if Syms[si].Kind = skGlobal then
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

    IR_SLOTADDR:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
        begin
          EmitB($B8); EmitGlobRef(Syms[si].Offset);          { mov eax, abs32 }
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

        if (tk = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          { Managed-string concat: a + b -> PXXStrConcat(lenA, srcA, srcB, lenB).
            Each operand may be a managed handle, an inline tyString, or a char.
            Stack after both pushes: [esp]=rhs value, [esp+4]=lhs value. }
          IREmitNode386(left);  EmitB($50);            { push lhs value }
          IREmitNode386(right); EmitB($50);            { push rhs value }
          { ---- srcB / lenB from rhs at [esp] -> esi/edi ---- }
          EmitB($8B); EmitB($14); EmitB($24);          { mov edx, [esp] (rhs) }
          if IntToTypeKind(IRTk[right]) = tyAnsiString then
          begin
            EmitB($31); EmitB($C9);                    { xor ecx, ecx }
            EmitB($85); EmitB($D2);                    { test edx, edx }
            EmitB($74); EmitB($03);                    { jz +3 }
            EmitB($8B); EmitB($4A); EmitB($F8);        { mov ecx, [edx-8] }
          end
          else if IntToTypeKind(IRTk[right]) = tyString then
          begin
            EmitB($8B); EmitB($0A);                    { mov ecx, [edx] (len) }
            EmitB($83); EmitB($C2); EmitB($08);        { add edx, 8 (data) }
          end
          else
          begin
            EmitB($8D); EmitB($14); EmitB($24);        { lea edx, [esp] (char byte) }
            EmitB($B9); EmitI32(1);                    { mov ecx, 1 }
          end;
          EmitB($89); EmitB($D6);                      { mov esi, edx (srcB) }
          EmitB($89); EmitB($CF);                      { mov edi, ecx (lenB) }
          { ---- srcA / lenA from lhs at [esp+4] -> edx/ecx ---- }
          EmitB($8B); EmitB($54); EmitB($24); EmitB($04); { mov edx, [esp+4] (lhs) }
          if IntToTypeKind(IRTk[left]) = tyAnsiString then
          begin
            EmitB($31); EmitB($C9);                    { xor ecx, ecx }
            EmitB($85); EmitB($D2);                    { test edx, edx }
            EmitB($74); EmitB($03);                    { jz +3 }
            EmitB($8B); EmitB($4A); EmitB($F8);        { mov ecx, [edx-8] }
          end
          else if IntToTypeKind(IRTk[left]) = tyString then
          begin
            EmitB($8B); EmitB($0A);                    { mov ecx, [edx] (len) }
            EmitB($83); EmitB($C2); EmitB($08);        { add edx, 8 (data) }
          end
          else
          begin
            EmitB($8D); EmitB($54); EmitB($24); EmitB($04); { lea edx, [esp+4] }
            EmitB($B9); EmitI32(1);                    { mov ecx, 1 }
          end;
          { push PXXStrConcat(lenA=ecx, srcA=edx, srcB=esi, lenB=edi) }
          EmitB($51);                                  { push ecx (lenA) }
          EmitB($52);                                  { push edx (srcA) }
          EmitB($56);                                  { push esi (srcB) }
          EmitB($57);                                  { push edi (lenB) }
          pi := FindProc('PXXStrConcat');
          if pi < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(pi);                            { eax = result }
          EmitB($81); EmitB($C4); EmitI32(16);         { add esp, 16 }
          { release fresh BINOP operand temporaries; [esp]=rhs, [esp+4]=lhs }
          EmitB($50);                                  { push eax (save result) }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov eax, [esp+8] (lhs) }
            EmitStrDecRef386;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04); { mov eax, [esp+4] (rhs) }
            EmitStrDecRef386;
          end;
          EmitB($58);                                  { pop eax (result) }
          EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 (drop lhs,rhs) }
          Exit;
        end;

        if (tk = tyString) and (op = Ord(tkPlus)) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);

          IREmitNode386(left);  EmitB($50);            { push lhs value }
          IREmitNode386(right); EmitB($50);            { push rhs value }

          EmitB($81); EmitB($EC); EmitI32(272);         { sub esp, 272 }
          EmitB($89); EmitB($E3);                      { mov ebx, esp }

          if lhsTk = tyString then
          begin
            { mov eax, [ebx+276] (lhs) }
            EmitB($8B); EmitB($83); EmitI32(276);
            { mov edx, [eax] (len) }
            EmitB($8B); EmitB($10);
            { lea esi, [eax+8] }
            EmitB($8D); EmitB($70); EmitB($08);
            { lea edi, [ebx+8] }
            EmitB($8D); EmitB($7B); EmitB($08);
            { mov ecx, edx (len) }
            EmitB($89); EmitB($D1);
            { test ecx, ecx }
            EmitB($85); EmitB($C9);
            { jz done_left }
            EmitB($74); pNilLhs := CodeLen; EmitB(0);
            { loop: }
            pLoopLhs := CodeLen;
            EmitB($8A); EmitB($06);                    { mov al, [esi] }
            EmitB($88); EmitB($07);                    { mov [edi], al }
            EmitB($46);                                { inc esi }
            EmitB($47);                                { inc edi }
            EmitB($49);                                { dec ecx }
            EmitB($75); EmitB(Byte(pLoopLhs - (CodeLen + 1)));
            Code[pNilLhs] := Byte(CodeLen - (pNilLhs + 1));
          end
          else
          begin
            { mov edx, 1 (len) }
            EmitB($BA); EmitI32(1);
            { mov al, [ebx+276] (char) }
            EmitB($8A); EmitB($83); EmitI32(276);
            { mov [ebx+8], al }
            EmitB($88); EmitB($43); EmitB($08);
          end;

          if rhsTk = tyString then
          begin
            { mov eax, [ebx+272] (rhs) }
            EmitB($8B); EmitB($83); EmitI32(272);
            { mov ecx, [eax] (len) }
            EmitB($8B); EmitB($08);
            EmitB($51);                                { push ecx }
            { lea esi, [eax+8] }
            EmitB($8D); EmitB($70); EmitB($08);
            { lea edi, [ebx+8] }
            EmitB($8D); EmitB($7B); EmitB($08);
            { add edi, edx }
            EmitB($01); EmitB($D7);
            { test ecx, ecx }
            EmitB($85); EmitB($C9);
            { jz done_rhs }
            EmitB($74); pNilRhs := CodeLen; EmitB(0);
            { loop: }
            pLoopRhs := CodeLen;
            EmitB($8A); EmitB($06);                    { mov al, [esi] }
            EmitB($88); EmitB($07);                    { mov [edi], al }
            EmitB($46);                                { inc esi }
            EmitB($47);                                { inc edi }
            EmitB($49);                                { dec ecx }
            EmitB($75); EmitB(Byte(pLoopRhs - (CodeLen + 1)));
            Code[pNilRhs] := Byte(CodeLen - (pNilRhs + 1));
            EmitB($59);                                { pop ecx }
          end
          else
          begin
            { mov ecx, 1 (len) }
            EmitB($B9); EmitI32(1);
            { lea edi, [ebx+8] }
            EmitB($8D); EmitB($7B); EmitB($08);
            { add edi, edx }
            EmitB($01); EmitB($D7);
            { mov al, [ebx+272] (char) }
            EmitB($8A); EmitB($83); EmitI32(272);
            { mov [edi], al }
            EmitB($88); EmitB($07);
          end;

          { add edx, ecx (total_len) }
          EmitB($01); EmitB($CA);
          { mov eax, edx }
          EmitB($89); EmitB($D0);
          { cmp eax, 256 }
          EmitB($3D); EmitI32(256);
          { jle .cap }
          EmitB($7E); pCap := CodeLen; EmitB(0);
          { mov eax, 256 }
          EmitB($B8); EmitI32(256);
          { .cap: }
          Code[pCap] := Byte(CodeLen - (pCap + 1));
          { mov [ebx], eax }
          EmitB($89); EmitB($03);
          { mov dword [ebx+4], 0 }
          EmitB($C7); EmitB($43); EmitB($04); EmitI32(0);
          { mov eax, ebx (result address) }
          EmitB($89); EmitB($D8);
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString]) or
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString])) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNode386(left);  EmitB($50);            { push lhs value }
          IREmitNode386(right); EmitB($50);            { push rhs value }

          if (lhsTk = tyAnsiString) and (rhsTk = tyChar) then
          begin
            { mov ecx, [esp] }
            EmitB($8B); EmitB($0C); EmitB($24);
            { mov eax, [esp+4] }
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04);
            { test eax, eax }
            EmitB($85); EmitB($C0);
            { jz .not_equal }
            EmitB($0F); EmitB($84); nextJmp := CodeLen; EmitI32(0);
            { cmp dword [eax-8], 1 }
            EmitB($83); EmitB($78); EmitB($F8); EmitB($01);
            { jne .not_equal }
            EmitB($0F); EmitB($85); nextJmp2 := CodeLen; EmitI32(0);
            { movzx edx, byte [eax] }
            EmitB($0F); EmitB($B6); EmitB($10);
            { cmp edx, ecx }
            EmitB($39); EmitB($CA);
            { sete/setne al }
            if op = Ord(tkEq) then begin EmitB($0F); EmitB($94); EmitB($C0); end
            else begin EmitB($0F); EmitB($95); EmitB($C0); end;
            { movzx eax, al }
            EmitB($0F); EmitB($B6); EmitB($C0);
            { jmp .done }
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);

            Patch32(nextJmp, CodeLen - (nextJmp + 4));
            Patch32(nextJmp2, CodeLen - (nextJmp2 + 4));
            if op = Ord(tkNeq) then begin EmitB($B8); EmitI32(1); end else begin EmitB($B8); EmitI32(0); end;
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else if (lhsTk = tyChar) and (rhsTk = tyAnsiString) then
          begin
            { mov ecx, [esp] }
            EmitB($8B); EmitB($0C); EmitB($24);
            { mov eax, [esp+4] }
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04);
            { test ecx, ecx }
            EmitB($85); EmitB($C9);
            { jz .not_equal }
            EmitB($0F); EmitB($84); nextJmp := CodeLen; EmitI32(0);
            { cmp dword [ecx-8], 1 }
            EmitB($83); EmitB($79); EmitB($F8); EmitB($01);
            { jne .not_equal }
            EmitB($0F); EmitB($85); nextJmp2 := CodeLen; EmitI32(0);
            { movzx edx, byte [ecx] }
            EmitB($0F); EmitB($B6); EmitB($11);
            { cmp edx, eax }
            EmitB($39); EmitB($C2);
            { sete/setne al }
            if op = Ord(tkEq) then begin EmitB($0F); EmitB($94); EmitB($C0); end
            else begin EmitB($0F); EmitB($95); EmitB($C0); end;
            { movzx eax, al }
            EmitB($0F); EmitB($B6); EmitB($C0);
            { jmp .done }
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);

            Patch32(nextJmp, CodeLen - (nextJmp + 4));
            Patch32(nextJmp2, CodeLen - (nextJmp2 + 4));
            if op = Ord(tkNeq) then begin EmitB($B8); EmitI32(1); end else begin EmitB($B8); EmitI32(0); end;
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else if (lhsTk = tyString) and (rhsTk = tyChar) then
          begin
            { mov ecx, [esp] }
            EmitB($8B); EmitB($0C); EmitB($24);
            { mov eax, [esp+4] }
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04);
            { cmp dword [eax], 1 }
            EmitB($83); EmitB($38); EmitB($01);
            { jne .not_equal }
            EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);
            { movzx edx, byte [eax+8] }
            EmitB($0F); EmitB($B6); EmitB($50); EmitB($08);
            { cmp edx, ecx }
            EmitB($39); EmitB($CA);
            { sete/setne al }
            if op = Ord(tkEq) then begin EmitB($0F); EmitB($94); EmitB($C0); end
            else begin EmitB($0F); EmitB($95); EmitB($C0); end;
            { movzx eax, al }
            EmitB($0F); EmitB($B6); EmitB($C0);
            { jmp .done }
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);

            Patch32(nextJmp, CodeLen - (nextJmp + 4));
            if op = Ord(tkNeq) then begin EmitB($B8); EmitI32(1); end else begin EmitB($B8); EmitI32(0); end;
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else if (lhsTk = tyChar) and (rhsTk = tyString) then
          begin
            { mov ecx, [esp] }
            EmitB($8B); EmitB($0C); EmitB($24);
            { mov eax, [esp+4] }
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04);
            { cmp dword [ecx], 1 }
            EmitB($83); EmitB($09); EmitB($01);
            { jne .not_equal }
            EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);
            { movzx edx, byte [ecx+8] }
            EmitB($0F); EmitB($B6); EmitB($51); EmitB($08);
            { cmp edx, eax }
            EmitB($39); EmitB($C2);
            { sete/setne al }
            if op = Ord(tkEq) then begin EmitB($0F); EmitB($94); EmitB($C0); end
            else begin EmitB($0F); EmitB($95); EmitB($C0); end;
            { movzx eax, al }
            EmitB($0F); EmitB($B6); EmitB($C0);
            { jmp .done }
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);

            Patch32(nextJmp, CodeLen - (nextJmp + 4));
            if op = Ord(tkNeq) then begin EmitB($B8); EmitI32(1); end else begin EmitB($B8); EmitI32(0); end;
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else
          begin
            { Standard string equality: decompose each operand into (len, src) and call PXXStrEq }
            { rhs at [esp] -> esi=srcB, edi=lenB }
            EmitB($8B); EmitB($14); EmitB($24);          { mov edx, [esp] }
            if IntToTypeKind(IRTk[right]) = tyAnsiString then
            begin
              EmitB($31); EmitB($C9); EmitB($85); EmitB($D2);
              EmitB($74); EmitB($03); EmitB($8B); EmitB($4A); EmitB($F8);
            end
            else
            begin
              EmitB($8B); EmitB($0A); EmitB($83); EmitB($C2); EmitB($08);
            end;
            EmitB($89); EmitB($D6);                      { mov esi, edx }
            EmitB($89); EmitB($CF);                      { mov edi, ecx }
            { lhs at [esp+4] -> edx=srcA, ecx=lenA }
            EmitB($8B); EmitB($54); EmitB($24); EmitB($04);
            if IntToTypeKind(IRTk[left]) = tyAnsiString then
            begin
              EmitB($31); EmitB($C9); EmitB($85); EmitB($D2);
              EmitB($74); EmitB($03); EmitB($8B); EmitB($4A); EmitB($F8);
            end
            else
            begin
              EmitB($8B); EmitB($0A); EmitB($83); EmitB($C2); EmitB($08);
            end;
            EmitB($51);                                  { push ecx (lenA) }
            EmitB($52);                                  { push edx (srcA) }
            EmitB($57);                                  { push edi (lenB) }
            EmitB($56);                                  { push esi (srcB) }
            pi := FindProc('PXXStrEq');
            if pi < 0 then Error('compiler error: PXXStrEq not found');
            EmitCallProc(pi);                            { eax = 1/0 }
            EmitB($81); EmitB($C4); EmitI32(16);         { add esp, 16 }
            if op = Ord(tkNeq) then
              begin EmitB($83); EmitB($F0); EmitB($01); end; { xor eax, 1 }
          end;

          EmitB($50);                                  { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitB($8B); EmitB($44); EmitB($24); EmitB($08); EmitStrDecRef386;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitB($8B); EmitB($44); EmitB($24); EmitB($04); EmitStrDecRef386;
          end;
          EmitB($58);                                  { pop result }
          EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
          Exit;
        end;

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
        if pi = -Ord(tkGetMem) then
        begin
          { GetMem / New. Evaluate size -> eax, then Alloc. Class
            instantiation (VMT + constructor) is not supported on i386 yet. }
          classIdx := IRC[node];
          if classIdx >= REC_UCLASS_BASE then
            Error('target i386: class instantiation not yet supported');
          EmitAcquireHeapLock386;
          argNode := IRB[node];          { size arg }
          IREmitNode386(IRA[argNode]);   { size -> eax }
          EmitHeapAllocLocked386;        { eax = payload pointer }
          EmitReleaseHeapLock386;
          Exit;
        end;
        if pi = -Ord(tkFreeMem) then
        begin
          EmitAcquireHeapLock386;
          argNode := IRB[node];          { pointer arg }
          IREmitNode386(IRA[argNode]);   { p -> eax }
          EmitHeapFreeLocked386;
          EmitReleaseHeapLock386;
          Exit;
        end;
        if pi = -102 then
        begin
          { SetLength(arr, n) for a depth-1 dynamic array via the portable
            PXXDynSetLen(slotAddr, n, desc) helper. }
          argNode := IRB[node];          { arg1 = array lvalue (IR_LEA) }
          valNode := IRB[argNode];       { arg2 = new length }
          left := IRA[argNode];          { IR_LEA node }
          if IRKind[left] <> IR_LEA then
            Error('target i386: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target i386: SetLength only supports dynamic arrays yet');
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            Error('target i386: SetLength on a var-array parameter not yet supported');
          { arg0 = slot address }
          if Syms[si].Kind = skGlobal then
            begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end          { mov eax, slot addr }
          else
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end; { lea eax, [ebp+off] }
          EmitB($50);                    { push slot addr }
          IREmitNode386(IRA[valNode]);   { eax = new length }
          EmitB($50);                    { push n }
          EmitB($68); EmitDataRef(GetOrAllocSymRTTI(si)); { push desc }
          pi := FindProc('PXXDynSetLen');
          if pi < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(pi);
          EmitB($81); EmitB($C4); EmitI32(12); { add esp, 12 }
          Exit;
        end;
        if pi = -Ord(tkLength) then
        begin
          { Length(arr): IR_LEA auto-loaded the data pointer (handle); the
            element count lives at [handle-8] (0 when nil). }
          argNode := IRB[node];
          valNode := IRA[argNode];
          IREmitNode386(valNode);        { eax = handle (data ptr) or 0 }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) then
            begin EmitB($8B); EmitB($00); end;  { mov eax, [eax] (deref slot to handle) }
          EmitB($85); EmitB($C0);        { test eax, eax }
          EmitB($74); EmitB($03);        { jz +3 }
          EmitB($8B); EmitB($40); EmitB($F8); { mov eax, [eax-8] }
          Exit;
        end;
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
          if (pi >= 0) and (nArgs < Procs[pi].ParamCount) then
          begin
            if Procs[pi].Params[nArgs].TypeKind = tyAnsiString then
            begin
              if IntToTypeKind(IRTk[argNode]) = tyChar then
              begin
                EmitB($50);                                 { push eax (char code) }
                EmitB($6A); EmitB($01);                     { push 1 (len) }
                EmitB($8D); EmitB($44); EmitB($24); EmitB($04); { lea eax, [esp+4] (ptr to char code) }
                EmitB($50);                                 { push eax (src) }
                j := FindProc('PXXStrFromLit');
                if j < 0 then Error('compiler error: PXXStrFromLit not found');
                EmitCallProc(j);
                EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
                EmitB($59);                                 { pop ecx }
              end
              else if IntToTypeKind(IRTk[argNode]) = tyString then
              begin
                EmitB($50);                                 { push eax }
                EmitB($8B); EmitB($08);                     { mov ecx, [eax] (len) }
                EmitB($83); EmitB($C0); EmitB($08);         { add eax, 8 (src) }
                EmitB($51);                                 { push ecx (len) }
                EmitB($50);                                 { push eax (src) }
                j := FindProc('PXXStrFromLit');
                if j < 0 then Error('compiler error: PXXStrFromLit not found');
                EmitCallProc(j);
                EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
                EmitB($59);                                 { pop ecx }
              end;
            end;
          end;
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

    IR_FIELD:
      begin
        IREmitNode386(IRA[node]);                    { base address -> eax }
        j := Integer(IRIVal[node]);                  { field offset }
        if j <> 0 then
          begin EmitB($05); EmitI32(j); end;         { add eax, offset }
      end;

    IR_INDEX:
      begin
        { Static-array / pointer indexing. Managed strings and dynamic arrays
          (which need copy-on-write) aren't available on i386 yet, so no COW
          path here. base[index]: addr = base + (index - lo) * elemSize. }
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);
        IREmitNode386(left);                          { base address -> eax }
        EmitB($50);                                   { push eax }
        IREmitNode386(right);                         { index -> eax }
        if lo <> 0 then
          begin EmitB($2D); EmitI32(lo); end;         { sub eax, lo }
        if elemSize = 8 then
          begin EmitB($C1); EmitB($E0); EmitB($03); end          { shl eax, 3 }
        else if elemSize = 4 then
          begin EmitB($C1); EmitB($E0); EmitB($02); end          { shl eax, 2 }
        else if elemSize = 2 then
          begin EmitB($C1); EmitB($E0); EmitB($01); end          { shl eax, 1 }
        else if elemSize <> 1 then
          begin EmitB($69); EmitB($C0); EmitI32(elemSize); end;  { imul eax, eax, elemSize }
        EmitB($59);                                   { pop ecx (base) }
        EmitB($01); EmitB($C8);                       { add eax, ecx }
      end;

    IR_LOAD_MEM:
      begin
        IREmitNode386(IRA[node]);                    { address -> eax }
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass)) then
          Error('target i386: load through pointer of this type not yet supported');
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then begin EmitB($0F); EmitB($BE); EmitB($00); end { movsx eax, byte [eax] }
          else begin EmitB($0F); EmitB($B6); EmitB($00); end;       { movzx eax, byte [eax] }
        end
        else if sz = 2 then
        begin
          if sgn then begin EmitB($0F); EmitB($BF); EmitB($00); end { movsx eax, word [eax] }
          else begin EmitB($0F); EmitB($B7); EmitB($00); end;       { movzx eax, word [eax] }
        end
        else
        begin
          EmitB($8B); EmitB($00);                    { mov eax, [eax] (4-, low dword of 8-byte) }
        end;
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          { Managed-string assignment: produce the new handle in eax, then
            publish into the slot (store new, release old). i386 calls the
            Pascal helpers directly (no shim/lock; threadsafe is x86-64-only). }
          valNode := IRB[node];
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            si := InternStr(sVal);
            { PXXStrFromLit(len, src): push len then src (arg0 deepest). }
            EmitB($68); EmitI32(Strs[si].Len);          { push len }
            EmitB($68); EmitDataRef(Strs[si].Offset + 8); { push src }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNode386(valNode);                     { eax = char code }
            EmitB($50);                                 { push eax (char code) }
            EmitB($6A); EmitB($01);                     { push 1 (len) }
            EmitB($8D); EmitB($44); EmitB($24); EmitB($04); { lea eax, [esp+4] (ptr to char code) }
            EmitB($50);                                 { push eax (src) }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
            EmitB($59);                                 { pop ecx (restore stack) }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyString then
          begin
            IREmitNode386(valNode);                     { eax = inline string buffer address }
            EmitB($50);                                 { push eax }
            EmitB($8B); EmitB($08);                     { mov ecx, [eax] (len) }
            EmitB($83); EmitB($C0); EmitB($08);         { add eax, 8 (src) }
            EmitB($51);                                 { push ecx (len) }
            EmitB($50);                                 { push eax (src) }
            pi := FindProc('PXXStrFromLit');
            if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
            EmitB($59);                                 { pop ecx }
          end
          else
          begin
            IREmitNode386(valNode);                     { eax = source handle }
            { Retain unless the value is already a fresh refcount-1 owner
              (concat result, or a user-function result). }
            if not (((IRKind[valNode] = IR_BINOP) and
                     (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
                    ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
            begin
              EmitB($50);                               { push eax (arg0 = p) }
              pi := FindProc('PXXStrIncRef');
              if pi < 0 then Error('compiler error: PXXStrIncRef not found');
              EmitCallProc(pi);
              EmitB($58);                               { pop eax (restore handle) }
            end;
          end;
          EmitB($50);                                   { push eax (new handle) }
          IREmitNode386(IRA[node]);                     { eax = slot address }
          EmitB($89); EmitB($C7);                       { mov edi, eax }
          EmitB($8B); EmitB($37);                       { mov esi, [edi] (old) }
          EmitB($8B); EmitB($04); EmitB($24);           { mov eax, [esp] (new) }
          EmitB($89); EmitB($07);                       { mov [edi], eax }
          EmitB($89); EmitB($F0);                       { mov eax, esi (old) }
          pi := FindProc('PXXStrDecRef');
          if pi < 0 then Error('compiler error: PXXStrDecRef not found');
          EmitB($50);                                   { push eax (arg0 = old) }
          EmitCallProc(pi);
          EmitB($81); EmitB($C4); EmitI32(4);           { add esp, 4 }
          EmitB($58);                                   { pop eax (new, discard) }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown)) then
          Error('target i386: store through pointer of this type not yet supported');
        IREmitNode386(IRB[node]);                    { value -> eax }
        EmitB($50);                                  { push eax }
        IREmitNode386(IRA[node]);                    { address -> eax }
        EmitB($59);                                  { pop ecx (value) }
        sz := TypeSize(tk);
        if sz = 1 then begin EmitB($88); EmitB($08); end       { mov [eax], cl }
        else if sz = 2 then begin EmitB($66); EmitB($89); EmitB($08); end { mov [eax], cx }
        else begin EmitB($89); EmitB($08); end;                { mov [eax], ecx }
      end;

    IR_COPY_REC:
      begin
        { rep movsb IRIVal bytes from src (IRB) to dest (IRA). }
        IREmitNode386(IRB[node]);                    { eax = source }
        EmitB($50);                                  { push eax }
        IREmitNode386(IRA[node]);                    { eax = dest }
        EmitB($89); EmitB($C7);                      { mov edi, eax }
        EmitB($5E);                                  { pop esi (src) }
        EmitB($B9); EmitI32(IRIVal[node]);           { mov ecx, count }
        EmitB($F3); EmitB($A4);                      { rep movsb }
      end;

    IR_COPY_REC_MANAGED:
      begin
        { ARC-correct whole-record copy: retain src's managed fields, release
          dest's old ones (via the layout-RTTI helpers), then bulk-copy.
          Threadsafe locking is x86-64-only; i386 runs single-threaded. }
        IREmitNode386(IRB[node]);                    { eax = src }
        EmitB($50);                                  { push src  ([esp+4]) }
        IREmitNode386(IRA[node]);                    { eax = dest }
        EmitB($50);                                  { push dest ([esp])  }
        pi := FindProc('PXXRecordRetain');
        if pi < 0 then Error('compiler error: PXXRecordRetain not found');
        EmitB($8B); EmitB($44); EmitB($24); EmitB($04); { mov eax, [esp+4] (src) }
        EmitB($50);                                  { push eax (arg0 recAddr) }
        EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
        EmitCallProc(pi);
        EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
        pi := FindProc('PXXRecordRelease');
        if pi < 0 then Error('compiler error: PXXRecordRelease not found');
        EmitB($8B); EmitB($04); EmitB($24);          { mov eax, [esp] (dest) }
        EmitB($50);                                  { push eax (arg0 recAddr) }
        EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
        EmitCallProc(pi);
        EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
        EmitB($5F);                                  { pop edi (dest) }
        EmitB($5E);                                  { pop esi (src) }
        EmitB($B9); EmitI32(IRIVal[node]);           { mov ecx, count }
        EmitB($F3); EmitB($A4);                      { rep movsb }
      end;

    IR_DEFAULT_MEM:
      begin
        IREmitNode386(IRA[node]);                    { eax = destination }
        if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
        begin
          EmitB($50);                                { push dest }
          pi := FindProc('PXXRecordRelease');
          if pi < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitB($8B); EmitB($04); EmitB($24);        { mov eax, [esp] (dest) }
          EmitB($50);                                { push eax (arg0) }
          EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
          EmitCallProc(pi);
          EmitB($81); EmitB($C4); EmitI32(8);        { add esp, 8 }
          EmitB($5F);                                { pop edi (dest) }
        end
        else
          begin EmitB($89); EmitB($C7); end;         { mov edi, eax }
        EmitB($31); EmitB($C0);                      { xor eax, eax }
        EmitB($B9); EmitI32(IRIVal[node]);           { mov ecx, count }
        EmitB($F3); EmitB($AA);                      { rep stosb }
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
          else if tk = tyAnsiString then
          begin
            { write(1, data, [data-8]); nil handle -> skip. len is the low
              dword of the 8-byte length header. }
            IREmitNode386(valNode);                      { eax = handle }
            EmitB($85); EmitB($C0);                      { test eax, eax }
            EmitB($74); j := CodeLen; EmitB(0);          { jz done }
            EmitB($50);                                  { push eax (preserve) }
            EmitB($8B); EmitB($50); EmitB($F8);          { mov edx, [eax-8] (len) }
            EmitB($89); EmitB($C1);                      { mov ecx, eax (buf) }
            EmitB($BB); EmitI32(STDOUT);                 { mov ebx, 1 }
            EmitB($B8); EmitI32(4);                      { mov eax, 4 (write) }
            EmitB($CD); EmitB($80);                      { int 0x80 }
            EmitB($58);                                  { pop eax (handle) }
            if (IRKind[valNode] = IR_BINOP) and
               (IntToTypeKind(IRTk[valNode]) = tyAnsiString) then
            begin
              EmitB($50);                                { push eax (arg0) }
              pi := FindProc('PXXStrDecRef');
              if pi < 0 then Error('compiler error: PXXStrDecRef not found');
              EmitCallProc(pi);
              EmitB($81); EmitB($C4); EmitI32(4);        { add esp, 4 }
            end;
            Code[j] := Byte(CodeLen - (j + 1));          { patch jz done }
          end
          else if tk = tyString then
          begin
            { String-valued expression (address of a [len:8][chars] struct in eax) }
            IREmitNode386(valNode);                      { eax = address }
            EmitB($89); EmitB($C1);                      { mov ecx, eax }
            EmitB($83); EmitB($C1); EmitB($08);          { add ecx, 8 }
            EmitB($8B); EmitB($10);                      { mov edx, [eax] }
            EmitB($BB); EmitI32(STDOUT);                 { mov ebx, STDOUT }
            EmitB($B8); EmitI32(4);                      { mov eax, 4 (write) }
            EmitB($CD); EmitB($80);                      { int 0x80 }
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
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SLOTADDR, IR_FIELD, IR_INDEX: ; { operands, emitted by parents }

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
