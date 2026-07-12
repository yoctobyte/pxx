{ SPDX-License-Identifier: MPL-2.0 }
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
procedure EmitSetccFloat(opTk: Integer); forward;

procedure IREmitNode386(node: Integer); forward;

procedure EmitLoadArgvPtr386;
{ On entry eax = argv index. Returns eax = argv[index] C-string pointer. }
begin
  EmitB($C1); EmitB($E0); EmitB($02);        { shl eax, 2 }
  EmitB($8B); EmitB($0D); EmitGlobRef(BSS_INITIAL_RSP); { mov ecx, [initial_sp] }
  EmitB($83); EmitB($C1); EmitB($04);        { add ecx, 4 (argv base) }
  EmitB($01); EmitB($C8);                    { add eax, ecx }
  EmitB($8B); EmitB($00);                    { mov eax, [eax] }
end;

procedure EmitArgvToAnsiString386;
{ On entry eax = argv index. Returns eax = managed string handle. }
var loopStart, donePos, procIdx: Integer;
begin
  EmitLoadArgvPtr386;                        { eax = src }
  EmitB($89); EmitB($C6);                    { mov esi, eax (src) }
  EmitB($31); EmitB($C9);                    { xor ecx, ecx (len) }
  loopStart := CodeLen;
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00); { cmp byte [esi+ecx], 0 }
  EmitB($0F); EmitB($84); donePos := CodeLen; EmitI32(0);
  EmitB($41);                                { inc ecx }
  EmitB($E9); EmitI32(loopStart - (CodeLen + 4));
  Patch32(donePos, CodeLen - (donePos + 4));
  EmitB($51);                                { push len }
  EmitB($56);                                { push src }
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
  EmitCallProc(procIdx);
  EmitB($81); EmitB($C4); EmitI32(8);
end;

procedure EmitArgvToFixedString386(dstIdx: Integer);
{ On entry eax = argv index. Copy argv[index] into fixed string dstIdx. }
var loopStart, donePos, capDone, copyLoop, copyDone: Integer;
begin
  EmitLoadArgvPtr386;                        { eax = src }
  EmitB($89); EmitB($C6);                    { mov esi, eax }
  EmitB($31); EmitB($C9);                    { xor ecx, ecx (len) }
  loopStart := CodeLen;
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00); { cmp byte [esi+ecx], 0 }
  EmitB($0F); EmitB($84); donePos := CodeLen; EmitI32(0);
  EmitB($41);                                { inc ecx }
  EmitB($E9); EmitI32(loopStart - (CodeLen + 4));
  Patch32(donePos, CodeLen - (donePos + 4));
  EmitB($81); EmitB($F9); EmitI32(256);      { cmp ecx, 256 }
  EmitB($0F); EmitB($8E); capDone := CodeLen; EmitI32(0); { jle cap_done }
  EmitB($B9); EmitI32(256);                  { mov ecx, 256 }
  Patch32(capDone, CodeLen - (capDone + 4));
  if Syms[dstIdx].Kind = skGlobal then
    begin EmitB($BF); EmitGlobRef(Syms[dstIdx].Offset); end
  else
    begin EmitB($8D); EmitB($BD); EmitI32(Syms[dstIdx].Offset); end;
  EmitB($89); EmitB($0F);                    { mov [edi], ecx }
  EmitB($C7); EmitB($47); EmitB($04); EmitI32(0); { mov dword [edi+4], 0 }
  EmitB($83); EmitB($C7); EmitB($08);        { add edi, 8 }
  copyLoop := CodeLen;
  EmitB($85); EmitB($C9);                    { test ecx, ecx }
  EmitB($0F); EmitB($84); copyDone := CodeLen; EmitI32(0);
  EmitB($8A); EmitB($06);                    { mov al, [esi] }
  EmitB($88); EmitB($07);                    { mov [edi], al }
  EmitB($46);                                { inc esi }
  EmitB($47);                                { inc edi }
  EmitB($49);                                { dec ecx }
  EmitB($E9); EmitI32(copyLoop - (CodeLen + 4));
  Patch32(copyDone, CodeLen - (copyDone + 4));
end;

procedure IREmitLeaveExceptionFrames386(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitB($8B); EmitB($04); EmitB($24);                  { mov eax, [esp] }
    EmitB($A3); EmitGlobRef(BSS_EXC_TOP);                { mov [BSS_EXC_TOP], eax }
    EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE_386);   { add esp, 32 }
  end;
end;

procedure EmitAcquireHeapLock386;
begin
  { i386 threadsafe heap locking lives in Pascal (builtinheap's PXXHeapSpin
    under PXX_TS_SOFTLOCK), taken inside PXXAlloc/PXXFree — so the codegen-side
    acquire is a no-op on this target. Kept as the structural mirror of
    x86-64's EmitAcquireHeapLock call sites. }
end;

procedure EmitReleaseHeapLock386;
begin
end;

procedure EmitIoLockStubs386;
{ --threadsafe statement-atomic console I/O, the i386 port of EmitIoLockStubs:
  a reentrant owner-tid spinlock (BSS_IO_OWNER = owning tid or 0, BSS_IO_DEPTH
  = owner's nesting depth) so a write argument calling a writing function
  cannot self-deadlock. gettid (224) via int 0x80 once per I/O statement.
  Clobbers eax/ecx/esi + flags — called only at statement boundaries, where the
  386 backend keeps no live evaluation registers. }
var spinStart, d: Integer;
begin
  IOLockAddr := CodeLen;
  EmitB($B8); EmitI32(224);                          { mov eax, 224 (gettid) }
  EmitB($CD); EmitB($80);                            { int 0x80 }
  EmitB($89); EmitB($C6);                            { mov esi, eax }
  EmitB($39); EmitB($35); EmitGlobRef(BSS_IO_OWNER); { cmp [IO_OWNER], esi }
  EmitB($74); EmitB(16);                             { je +16 (already ours -> depth bump, over the spin block) }
  spinStart := CodeLen;
  EmitB($31); EmitB($C0);                            { xor eax, eax (expect free) }
  EmitB($89); EmitB($F1);                            { mov ecx, esi (take with our tid) }
  EmitB($F0); EmitB($0F); EmitB($B1); EmitB($0D); EmitGlobRef(BSS_IO_OWNER); { lock cmpxchg [IO_OWNER], ecx }
  EmitB($74); EmitB(2);                              { je +2 (got it -> depth bump) }
  d := spinStart - (CodeLen + 2);
  EmitB($EB); EmitB(d and $FF);                      { jmp back to the spin retry }
  if CodeLen - spinStart <> 16 then
    Error('compiler error: i386 I/O lock spin block must be exactly 16 bytes (je +16 above)');
  EmitB($FF); EmitB($05); EmitGlobRef(BSS_IO_DEPTH); { inc dword [IO_DEPTH] }
  EmitB($C3);                                        { ret }

  IOUnlockAddr := CodeLen;
  EmitB($FF); EmitB($0D); EmitGlobRef(BSS_IO_DEPTH); { dec dword [IO_DEPTH] }
  EmitB($75); EmitB(8);                              { jnz +8 (still nested: keep ownership, over the clear) }
  EmitB($31); EmitB($C9);                            { xor ecx, ecx }
  EmitB($89); EmitB($0D); EmitGlobRef(BSS_IO_OWNER); { mov [IO_OWNER], ecx (release) }
  EmitB($C3);                                        { ret }
end;

procedure EmitHeapAllocLocked386;
{ eax = requested payload bytes. Returns payload pointer in eax. Mirrors
  EmitHeapAllocLocked: delegate to the Pascal PXXAlloc(size, align=8). i386
  internal ABI: push args left-to-right (arg0 deepest), caller pops. }
var procIdx: Integer;
begin
  EmitB($51);                         { push ecx (caller-saved) }
  EmitB($52);                         { push edx }
  EmitB($50);                         { push eax = arg0 (size) }
  EmitB($6A); EmitB($08);             { push 8  = arg1 (align) }
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(procIdx);                   { eax = pointer }
  EmitB($81); EmitB($C4); EmitI32(8); { add esp, 8 (pop args) }
  EmitB($5A);                         { pop edx }
  EmitB($59);                         { pop ecx }
end;

procedure EmitHeapFreeLocked386;
{ eax = payload pointer. Delegate to Pascal PXXFree(p). nil is ignored inside. }
var procIdx: Integer;
begin
  EmitB($51);                         { push ecx }
  EmitB($52);                         { push edx }
  EmitB($50);                         { push eax = arg0 (p) }
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(procIdx);
  EmitB($81); EmitB($C4); EmitI32(4); { add esp, 4 }
  EmitB($5A);                         { pop edx }
  EmitB($59);                         { pop ecx }
end;

procedure EmitStrIncRef386;
{ eax = managed-string handle. Retain (calls Pascal PXXStrIncRef). eax clobbered. }
var procIdx: Integer;
begin
  EmitB($50);                         { push eax (arg0 = p) }
  procIdx := FindProc('PXXStrIncRef');
  if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
  EmitCallProc(procIdx);
  EmitB($81); EmitB($C4); EmitI32(4); { add esp, 4 }
end;

procedure EmitStrDecRef386;
{ eax = managed-string handle. Release (calls Pascal PXXStrDecRef). eax clobbered. }
var procIdx: Integer;
begin
  EmitB($50);                         { push eax (arg0 = p) }
  procIdx := FindProc('PXXStrDecRef');
  if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
  EmitCallProc(procIdx);
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

procedure EmitWriteCStr386;
{ eax = PChar (NUL-terminated) -> strlen + write to stdout. Mirrors the x86-64
  EmitWriteCStr so write(PChar) prints the string, not the pointer value. }
begin
  EmitB($89); EmitB($C6);                 { mov esi, eax (buffer) }
  EmitB($31); EmitB($C9);                 { xor ecx, ecx (length) }
  { scan: }
  EmitB($80); EmitB($38); EmitB($00);     { cmp byte [eax], 0 }
  EmitB($74); EmitB($04);                 { je done (+4) }
  EmitB($40);                             { inc eax }
  EmitB($41);                             { inc ecx }
  EmitB($EB); EmitB($F7);                 { jmp scan (-9) }
  { done: }
  EmitB($89); EmitB($CA);                 { mov edx, ecx (count) }
  EmitB($89); EmitB($F1);                 { mov ecx, esi (buf) }
  EmitB($BB); EmitI32(STDOUT);            { mov ebx, 1 }
  EmitB($B8); EmitI32(4);                 { mov eax, 4 (write) }
  EmitB($CD); EmitB($80);                 { int 0x80 }
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

{ ---- Float support (SSE2). Value model: float-typed IR nodes leave their
  value in xmm0 (a second channel besides eax); spills go through an 8-byte
  stack slot. Float -> text goes through the portable builtinheap helpers
  (PXXWriteFloat*), not per-arch emitters. ---- }

procedure EmitFloatSpill386;
{ sub esp, 8 ; movsd [esp], xmm0 }
begin
  EmitB($83); EmitB($EC); EmitB($08);
  EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24);
end;

procedure EmitFloatUnspill386;
{ movsd xmm0, [esp] ; add esp, 8 }
begin
  EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);
  EmitB($83); EmitB($C4); EmitB($08);
end;

procedure EmitFloatCallWriter386(const name: AnsiString; decs: Integer);
{ Value in xmm0. Spill to a stack slot, pass its address (plus decimals for
  the fixed writer) to the builtinheap float writer. }
var procIdx: Integer;
begin
  EmitFloatSpill386;
  EmitB($89); EmitB($E0);                       { mov eax, esp (slot addr) }
  EmitB($50);                                   { push eax = arg0 (p) }
  if decs >= 0 then
  begin
    EmitB($68); EmitI32(decs);                  { push decimals = arg1 }
  end;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: float writer helper not found');
  EmitCallProc(procIdx);
  if decs >= 0 then
    begin EmitB($81); EmitB($C4); EmitI32(16); end  { args + slot }
  else
    begin EmitB($81); EmitB($C4); EmitI32(12); end;
end;

procedure EmitVarHelperCall386(const name: AnsiString);
{ eax = variant slot address; call helper(name)(eax), preserve eax. }
var procIdx: Integer;
begin
  EmitB($50);                                   { push eax (arg0 = v) }
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: variant helper not found');
  EmitCallProc(procIdx);
  EmitB($58);                                   { pop eax (restore addr) }
end;

procedure EmitLoadVariantAddr386(node: Integer);
{ Address of a variant slot for value-position variant nodes (mirrors
  EmitLoadVariantAddress on x86-64). }
var symIdx: Integer;
begin
  if IRKind[node] = IR_LOAD_SYM then
  begin
    symIdx := IRA[node];
    if Syms[symIdx].Kind = skGlobal then
      begin EmitB($B8); EmitGlobRef(Syms[symIdx].Offset); end          { mov eax, abs }
    else if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
      begin EmitAsm386(['mov eax, [ebp+%]', Syms[symIdx].Offset]); end  { mov eax, [ebp+off] }
    else
      begin EmitAsm386(['lea eax, [ebp+%]', Syms[symIdx].Offset]); end; { lea eax, [ebp+off] }
  end
  else if IRKind[node] = IR_LOAD_MEM then
    IREmitNode386(IRA[node])
  else
    IREmitNode386(node);
end;

function VariantTagForTk386(tk: TTypeKind; const what: AnsiString): Integer;
begin
  case tk of
    tyInteger, tyInt8, tyInt16, tyInt32: Result := VT_INT;
    tyInt64, tyNativeInt:                Result := VT_INT64;
    tyUInt8, tyUInt16, tyUInt32, tyUInt64,
    tyNativeUInt, tyPointer:             Result := VT_INT64;
    tyBoolean:                           Result := VT_BOOL;
    tyChar:                              Result := VT_CHAR;
    tyDouble, tySingle, tyExtended:      Result := VT_DOUBLE;
    tyString, tyAnsiString:              Result := VT_STRING;
  else
    Error(what + ': this scalar type not yet supported');
  end;
end;

procedure EmitVariantFill386(tag: Integer; payloadTk: TTypeKind);
{ eax = variant slot address; payload pushed on the stack: 8 bytes for a
  double (spilled xmm0), else 4 bytes (eax pushed). Clears the old value,
  stores tag + payload, leaves the slot address in eax. }
begin
  EmitVarHelperCall386('PXXVarClear');
  EmitB($C7); EmitB($00); EmitI32(tag);             { mov dword [eax], tag }
  EmitB($C7); EmitB($40); EmitB($04); EmitI32(0);   { mov dword [eax+4], 0 }
  if TypeIsFloat(payloadTk) then
  begin
    EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);  { movsd xmm0, [esp] }
    EmitB($83); EmitB($C4); EmitB($08);                          { add esp, 8 }
    EmitB($F2); EmitB($0F); EmitB($11); EmitB($40); EmitB($08);  { movsd [eax+8], xmm0 }
  end
  else
  begin
    EmitB($59);                                     { pop ecx (payload) }
    EmitB($89); EmitB($48); EmitB($08);             { mov [eax+8], ecx }
    if tag = VT_INT then
    begin
      { sign-extend the 32-bit payload into the high dword }
      EmitB($50);                                   { push eax (slot addr) }
      EmitB($89); EmitB($C8);                       { mov eax, ecx }
      EmitB($99);                                   { cdq (edx = sign) }
      EmitB($58);                                   { pop eax }
      EmitB($89); EmitB($50); EmitB($0C);           { mov [eax+12], edx }
    end
    else
      begin EmitB($C7); EmitB($40); EmitB($0C); EmitI32(0); end; { mov dword [eax+12], 0 }
  end;
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
    managed strings happens in the IR_STORE_MEM publish path, not here.
    Floats ride the 8-byte slot via xmm0; variants are addressed in place. }
  if not (TypeIsOrdinal(Syms[symIdx].TypeKind) or
          (Syms[symIdx].TypeKind in [tyString, tyAnsiString, tyPointer, tyClass,
           tySingle, tyDouble, tyExtended, tyVariant, tyRecord])) then
    Error('target i386: only ordinal/pointer/string variables supported yet');
end;

{ ---- 64-bit (Int64/UInt64) value model. Unlike the low-dword fat-slot model
  used for ordinary ordinals, true 8-byte values live in edx:eax (edx = high
  dword) while in flight, are stored/loaded as two dwords, and have their own
  arithmetic/shift/compare sequences below. Producers of a 64-bit-typed node
  leave edx:eax; consumers that only need 32 bits keep eax (correct
  truncation). ---- }

function Is64Bit386(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyInt64) or (tk = tyUInt64);
end;

procedure EmitNode64_386(node: Integer);
{ Emit node and guarantee its full 64-bit value sits in edx:eax. A 32-bit
  source is widened in place: sign-extend (cdq) when signed, else zero-extend. }
var ntk: TTypeKind;
begin
  IREmitNode386(node);
  ntk := IntToTypeKind(IRTk[node]);
  if not Is64Bit386(ntk) then
  begin
    if TypeSigned(ntk) then
      EmitB($99)                                  { cdq }
    else
      begin EmitB($31); EmitB($D2); end;          { xor edx, edx }
  end;
end;

procedure EmitwriteUInt64_386;
{ edx:eax = unsigned 64-bit value -> decimal on stdout. Long division by 10:
  divide the high dword, carry the remainder into the low dword. Digit string
  grows downward from the INTBUF tail; the count is bufend - edi. }
begin
  EmitAsm386([
    'mov ebx, eax',
    'mov esi, edx',
    'mov edi, @data', INTBUF_OFFSET + INTBUF_SIZE,
    '.loop:',
    'mov eax, esi',
    'xor edx, edx',
    'mov ecx, 10',
    'div ecx',
    'mov esi, eax',
    'mov eax, ebx',
    'div ecx',
    'mov ebx, eax',
    'add dl, 0x30',
    'dec edi',
    'mov [edi], dl',
    'mov eax, esi',
    'or eax, ebx',
    'jnz .loop',
    'mov edx, @data', INTBUF_OFFSET + INTBUF_SIZE,
    'sub edx, edi',
    'mov ecx, edi',
    'mov ebx, %', STDOUT,
    'mov eax, 4',
    'int 0x80'
  ]);
end;

procedure EmitwriteInt64_386;
{ edx:eax = signed 64-bit value -> decimal on stdout. }
var jnsOff: Integer;
begin
  EmitB($85); EmitB($D2);                          { test edx, edx }
  EmitB($79); jnsOff := CodeLen; EmitB(0);         { jns .positive }
  EmitB($F7); EmitB($D8);                          { neg eax }
  EmitB($83); EmitB($D2); EmitB($00);              { adc edx, 0 }
  EmitB($F7); EmitB($DA);                          { neg edx }
  EmitB($52);                                      { push edx (save value) }
  EmitB($50);                                      { push eax }
  EmitwriteSyscall(MINUS_OFFSET, 1);               { clobbers eax..edx }
  EmitB($58);                                      { pop eax }
  EmitB($5A);                                      { pop edx }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitwriteUInt64_386;
end;

procedure EmitUDivMod64Core_386(wantMod: Boolean);
{ Unsigned 64-bit divide. Precondition: the dividend is on the stack
  ([esp]=lo, [esp+4]=hi) and the divisor is in edx:eax. Restoring binary long
  division, 64 iterations, shifting the dividend's bits MSB-first into a running
  remainder. Postcondition: quotient (or remainder when wantMod) in edx:eax;
  the 8-byte dividend has been popped. Clobbers ebx, ecx, esi, edi. }
var loopOff, skip1, jaOff, skip2: Integer;
begin
  EmitB($52);                                      { push edx (D.hi) }
  EmitB($50);                                      { push eax (D.lo) }
  { stack: [esp]=D.lo [esp+4]=D.hi [esp+8]=N.lo [esp+12]=N.hi }
  EmitB($8B); EmitB($44); EmitB($24); EmitB($08);  { mov eax, [esp+8] (NQ.lo) }
  EmitB($8B); EmitB($54); EmitB($24); EmitB($0C);  { mov edx, [esp+12] (NQ.hi) }
  EmitB($31); EmitB($F6);                          { xor esi, esi (R.lo) }
  EmitB($31); EmitB($FF);                          { xor edi, edi (R.hi) }
  EmitB($B9); EmitI32(64);                         { mov ecx, 64 }
  loopOff := CodeLen;
  EmitB($D1); EmitB($E0);                          { shl eax, 1 }
  EmitB($D1); EmitB($D2);                          { rcl edx, 1 }
  EmitB($D1); EmitB($D6);                          { rcl esi, 1 }
  EmitB($D1); EmitB($D7);                          { rcl edi, 1 }
  EmitB($8B); EmitB($DF);                          { mov ebx, edi (R.hi) }
  EmitB($3B); EmitB($5C); EmitB($24); EmitB($04);  { cmp ebx, [esp+4] (D.hi) }
  EmitB($72); skip1 := CodeLen; EmitB(0);          { jb .skip }
  EmitB($77); jaOff := CodeLen; EmitB(0);          { ja .sub }
  EmitB($8B); EmitB($DE);                          { mov ebx, esi (R.lo) }
  EmitB($3B); EmitB($1C); EmitB($24);              { cmp ebx, [esp] (D.lo) }
  EmitB($72); skip2 := CodeLen; EmitB(0);          { jb .skip }
  Code[jaOff] := Byte(CodeLen - (jaOff + 1));       { .sub: }
  EmitB($2B); EmitB($34); EmitB($24);              { sub esi, [esp] }
  EmitB($1B); EmitB($7C); EmitB($24); EmitB($04);  { sbb edi, [esp+4] }
  EmitB($83); EmitB($C8); EmitB($01);              { or eax, 1 (set quotient bit) }
  Code[skip1] := Byte(CodeLen - (skip1 + 1));       { .skip: }
  Code[skip2] := Byte(CodeLen - (skip2 + 1));
  EmitB($49);                                      { dec ecx }
  EmitB($75); EmitB(Byte(loopOff - (CodeLen + 1))); { jnz .loop }
  EmitB($83); EmitB($C4); EmitB($10);              { add esp, 16 (pop D + N) }
  if wantMod then
  begin
    EmitB($89); EmitB($F0);                        { mov eax, esi (rem lo) }
    EmitB($89); EmitB($FA);                        { mov edx, edi (rem hi) }
  end;
end;

procedure EmitIDivMod64Core_386(wantMod: Boolean);
{ Signed 64-bit divide/mod with the same calling convention as the unsigned
  core. Truncated division: quotient sign = dividend xor divisor; remainder
  takes the dividend's sign. Operands are made non-negative in place, the
  unsigned core runs, then the result sign is applied. The 1-byte sign-flag
  state is stashed in INTBUF (free during arithmetic, single-threaded). }
var dpos, npos, doneOff: Integer;
begin
  EmitB($31); EmitB($DB);                          { xor ebx, ebx (flags) }
  EmitB($85); EmitB($D2);                          { test edx, edx (divisor sign) }
  EmitB($79); dpos := CodeLen; EmitB(0);           { jns .dpos }
  EmitB($F7); EmitB($D8);                          { neg eax }
  EmitB($83); EmitB($D2); EmitB($00);              { adc edx, 0 }
  EmitB($F7); EmitB($DA);                          { neg edx (abs divisor) }
  EmitB($83); EmitB($CB); EmitB($01);              { or ebx, 1 (quotient negate) }
  Code[dpos] := Byte(CodeLen - (dpos + 1));         { .dpos: }
  EmitB($8B); EmitB($34); EmitB($24);              { mov esi, [esp] (N.lo) }
  EmitB($8B); EmitB($7C); EmitB($24); EmitB($04);  { mov edi, [esp+4] (N.hi) }
  EmitB($85); EmitB($FF);                          { test edi, edi (dividend sign) }
  EmitB($79); npos := CodeLen; EmitB(0);           { jns .npos }
  EmitB($F7); EmitB($DE);                          { neg esi }
  EmitB($83); EmitB($D7); EmitB($00);              { adc edi, 0 }
  EmitB($F7); EmitB($DF);                          { neg edi (abs dividend) }
  EmitB($89); EmitB($34); EmitB($24);              { mov [esp], esi }
  EmitB($89); EmitB($7C); EmitB($24); EmitB($04);  { mov [esp+4], edi }
  EmitB($83); EmitB($CB); EmitB($02);              { or ebx, 2 (remainder negate) }
  EmitB($83); EmitB($F3); EmitB($01);              { xor ebx, 1 (flip quotient negate) }
  Code[npos] := Byte(CodeLen - (npos + 1));         { .npos: }
  EmitB($88); EmitB($1D); EmitDataRef(INTBUF_OFFSET); { mov [INTBUF], bl (stash flags) }
  EmitUDivMod64Core_386(wantMod);                  { result in edx:eax }
  EmitB($8A); EmitB($1D); EmitDataRef(INTBUF_OFFSET); { mov bl, [INTBUF] }
  if wantMod then
    begin EmitB($F6); EmitB($C3); EmitB($02); end  { test bl, 2 }
  else
    begin EmitB($F6); EmitB($C3); EmitB($01); end; { test bl, 1 }
  EmitB($74); doneOff := CodeLen; EmitB(0);        { jz .done }
  EmitB($F7); EmitB($D8);                          { neg eax }
  EmitB($83); EmitB($D2); EmitB($00);              { adc edx, 0 }
  EmitB($F7); EmitB($DA);                          { neg edx (apply sign) }
  Code[doneOff] := Byte(CodeLen - (doneOff + 1));   { .done: }
end;

procedure EmitBinop64_386(left, right, op: Integer; signedOp: Boolean);
{ Evaluate (left OP right) as a 64-bit operation. left is spilled to the stack
  ([esp]=lo, [esp+4]=hi); right is materialized into edx:eax. Arithmetic/bit
  ops leave the 64-bit result in edx:eax; comparisons leave 0/1 in eax. }
var skipOff: Integer;
begin
  EmitNode64_386(left);
  EmitB($52);                                      { push edx (left hi) }
  EmitB($50);                                      { push eax (left lo) }
  EmitNode64_386(right);                           { right -> edx:eax }

  if op = Ord(tkPlus) then
  begin
    EmitB($03); EmitB($04); EmitB($24);            { add eax, [esp] }
    EmitB($13); EmitB($54); EmitB($24); EmitB($04);{ adc edx, [esp+4] }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if op = Ord(tkMinus) then
  begin
    EmitB($8B); EmitB($0C); EmitB($24);            { mov ecx, [esp] (left lo) }
    EmitB($8B); EmitB($5C); EmitB($24); EmitB($04);{ mov ebx, [esp+4] (left hi) }
    EmitB($29); EmitB($C1);                        { sub ecx, eax }
    EmitB($19); EmitB($D3);                        { sbb ebx, edx }
    EmitB($89); EmitB($C8);                        { mov eax, ecx }
    EmitB($89); EmitB($DA);                        { mov edx, ebx }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if op = Ord(tkAnd) then
  begin
    EmitB($23); EmitB($04); EmitB($24);            { and eax, [esp] }
    EmitB($23); EmitB($54); EmitB($24); EmitB($04);{ and edx, [esp+4] }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if op = Ord(tkOr) then
  begin
    EmitB($0B); EmitB($04); EmitB($24);            { or eax, [esp] }
    EmitB($0B); EmitB($54); EmitB($24); EmitB($04);{ or edx, [esp+4] }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if op = Ord(tkXor) then
  begin
    EmitB($33); EmitB($04); EmitB($24);            { xor eax, [esp] }
    EmitB($33); EmitB($54); EmitB($24); EmitB($04);{ xor edx, [esp+4] }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if op = Ord(tkStar) then
  begin
    { A=left ([esp]=Alo,[esp+4]=Ahi), B=right (eax=Blo, edx=Bhi).
      result.lo:hi = Alo*Blo + ((Ahi*Blo + Alo*Bhi) << 32) (low 64). }
    EmitB($89); EmitB($D1);                        { mov ecx, edx (Bhi) }
    EmitB($0F); EmitB($AF); EmitB($0C); EmitB($24);{ imul ecx, [esp] (Bhi*Alo) }
    EmitB($89); EmitB($C3);                        { mov ebx, eax (Blo) }
    EmitB($0F); EmitB($AF); EmitB($44); EmitB($24); EmitB($04); { imul eax,[esp+4] (Blo*Ahi) }
    EmitB($01); EmitB($C1);                        { add ecx, eax (cross terms) }
    EmitB($89); EmitB($D8);                        { mov eax, ebx (Blo) }
    EmitB($F7); EmitB($24); EmitB($24);            { mul dword [esp] (Blo*Alo -> edx:eax) }
    EmitB($01); EmitB($CA);                        { add edx, ecx }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
  end
  else if (op = Ord(tkShl)) or (op = Ord(tkIdent)) or (op = Ord(tkShr)) then
  begin
    { shift count in eax (right.lo) -> cl; value = left from stack. }
    EmitB($89); EmitB($C1);                        { mov ecx, eax (count) }
    EmitB($58);                                    { pop eax (lo) }
    EmitB($5A);                                    { pop edx (hi) }
    if op = Ord(tkShl) then
    begin
      EmitB($0F); EmitB($A5); EmitB($C2);          { shld edx, eax, cl }
      EmitB($D3); EmitB($E0);                      { shl eax, cl }
      EmitB($F6); EmitB($C1); EmitB($20);          { test cl, 32 }
      EmitB($74); skipOff := CodeLen; EmitB(0);    { je .done }
      EmitB($89); EmitB($C2);                      { mov edx, eax }
      EmitB($31); EmitB($C0);                      { xor eax, eax }
      Code[skipOff] := Byte(CodeLen - (skipOff + 1));
    end
    else if (op = Ord(tkShr)) and signedOp then
    begin
      { C signed '>>' — arithmetic (sign-propagating) shift right }
      EmitB($0F); EmitB($AD); EmitB($D0);          { shrd eax, edx, cl }
      EmitB($D3); EmitB($FA);                      { sar edx, cl }
      EmitB($F6); EmitB($C1); EmitB($20);          { test cl, 32 }
      EmitB($74); skipOff := CodeLen; EmitB(0);    { je .done }
      EmitB($89); EmitB($D0);                      { mov eax, edx }
      EmitB($C1); EmitB($FA); EmitB($1F);          { sar edx, 31 (sign-fill) }
      Code[skipOff] := Byte(CodeLen - (skipOff + 1));
    end
    else
    begin
      { Pascal 'shr' (tkIdent) or C unsigned '>>' — logical shift right }
      EmitB($0F); EmitB($AD); EmitB($D0);          { shrd eax, edx, cl }
      EmitB($D3); EmitB($EA);                      { shr edx, cl }
      EmitB($F6); EmitB($C1); EmitB($20);          { test cl, 32 }
      EmitB($74); skipOff := CodeLen; EmitB(0);    { je .done }
      EmitB($89); EmitB($D0);                      { mov eax, edx }
      EmitB($31); EmitB($D2);                      { xor edx, edx }
      Code[skipOff] := Byte(CodeLen - (skipOff + 1));
    end;
  end
  else if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { dividend (left) is already at [esp]/[esp+4]; divisor (right) in edx:eax. }
    if signedOp then EmitIDivMod64Core_386(op = Ord(tkMod))
    else EmitUDivMod64Core_386(op = Ord(tkMod));
  end
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    EmitB($8B); EmitB($0C); EmitB($24);            { mov ecx, [esp] (left lo) }
    EmitB($31); EmitB($C1);                        { xor ecx, eax }
    EmitB($8B); EmitB($5C); EmitB($24); EmitB($04);{ mov ebx, [esp+4] (left hi) }
    EmitB($31); EmitB($D3);                        { xor ebx, edx }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 (before the flag-setting or) }
    EmitB($09); EmitB($D9);                        { or ecx, ebx (zero iff equal) }
    if op = Ord(tkEq) then
      begin EmitB($0F); EmitB($94); EmitB($C0); end   { sete al }
    else
      begin EmitB($0F); EmitB($95); EmitB($C0); end;  { setne al }
    EmitB($0F); EmitB($B6); EmitB($C0);            { movzx eax, al }
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkLe)) or
          (op = Ord(tkGt)) or (op = Ord(tkGe)) then
  begin
    { Compute left - right (or right - left) via (sub lo, sbb hi); the flags of
      the final sbb give the full 64-bit ordered comparison. setl/setb yields
      "first operand < second"; <= and >= are derived by negating. }
    EmitB($8B); EmitB($0C); EmitB($24);            { mov ecx, [esp] (left lo) }
    EmitB($8B); EmitB($5C); EmitB($24); EmitB($04);{ mov ebx, [esp+4] (left hi) }
    EmitB($83); EmitB($C4); EmitB($08);            { add esp, 8 }
    if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
    begin
      EmitB($29); EmitB($C8);                      { sub eax, ecx (right.lo-left.lo) }
      EmitB($19); EmitB($DA);                      { sbb edx, ebx (right.hi-left.hi) }
    end
    else
    begin
      EmitB($29); EmitB($C1);                      { sub ecx, eax (left.lo-right.lo) }
      EmitB($19); EmitB($D3);                      { sbb ebx, edx (left.hi-right.hi) }
    end;
    if signedOp then
      begin EmitB($0F); EmitB($9C); EmitB($C0); end   { setl al }
    else
      begin EmitB($0F); EmitB($92); EmitB($C0); end;  { setb al }
    if (op = Ord(tkLe)) or (op = Ord(tkGe)) then
      begin EmitB($34); EmitB($01); end;           { xor al, 1 }
    EmitB($0F); EmitB($B6); EmitB($C0);            { movzx eax, al }
  end
  else
    Error('target i386: 64-bit binop operator not yet supported');
end;

procedure IREmitNode386(node: Integer);
var
  valNode, si, left, right, op, procIdx, argNode, nArgs, argBytes, wid, sz, i, j, base: Integer;
  classIdx, elemSize, lo, hi, itemNode, p1, p2: Integer;
  vaNvw, vaK, vaO1, vaO2: Integer;
  vaTk: TTypeKind;   { holds IntToTypeKind(...) — keep it the enum so FPC's strict
                       enum/int boundary is satisfied (pxx erases it; FPC does not). }
  vaFwd: Boolean;
  vaOrder: array[0..127] of Integer;
  sVal: AnsiString;
  emsg: AnsiString;
  tk, lhsTk, rhsTk: TTypeKind;
  sgn, savedLValueWrite: Boolean;
  pNilLhs, pLoopLhs, pNilRhs, pLoopRhs, pCap, nextJmp, nextJmp2, falseJmp: Integer;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_ASM:
      begin
        { Inline asm block: replay the parse-time-captured text lines
          (AsmParseBodyText386, asmenc.inc) through the i386 text engine.
          Emitting here, at final code positions, makes label fixups and
          @glob relocations natively correct. Labels are block-scoped. }
        Asm386BlockBegin;
        for i := IRA[node] to IRA[node] + IRB[node] - 1 do
          Asm386ProcessInlineLine(i);
        Asm386BlockResolve;
      end;

    IR_CONST_INT:
      begin
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          { Float literal: IRIVal carries the raw double bits -> xmm0. }
          EmitB($68); EmitI32(Integer(IRIVal[node] shr 32));         { push hi }
          EmitB($68); EmitI32(Integer(IRIVal[node] and $FFFFFFFF));  { push lo }
          EmitFloatUnspill386;
          Exit;
        end;
        if Is64Bit386(IntToTypeKind(IRTk[node])) then
        begin
          { Full 64-bit literal -> edx:eax. }
          EmitB($B8); EmitI32(Integer(IRIVal[node] and $FFFFFFFF));   { mov eax, lo }
          EmitB($BA); EmitI32(Integer(IRIVal[node] shr 32));          { mov edx, hi }
          Exit;
        end;
        { Ordinary ordinals use the low-dword scalar model; keep constants
          consistent with the matching load/store paths. }
        EmitB($B8); EmitI32(IRIVal[node]);           { mov eax, imm32 }
      end;

    IR_CONST_STR:
      begin
        { Address of the interned [len:8][data] struct (inline tyString value). }
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitB($B8); EmitDataRef(Strs[si].Offset);    { mov eax, str_struct_addr }
      end;

    IR_CONST_DATA:
      begin
        { Absolute data address (sentinel-resolvable), see the x86-64 case. }
        EmitB($B8); EmitDataRef(Integer(IRIVal[node]));
      end;

    IR_LOAD_SYM:
      begin
        IREmit386CheckScalarSym(IRA[node], 'load');
        si := IRA[node];
        tk := Syms[si].TypeKind;
        if TypeIsFloat(tk) then
        begin
          { Float load -> xmm0 (Single widened to double). }
          if Syms[si].Kind = skGlobal then
          begin
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($10); EmitB($05); EmitGlobRef(Syms[si].Offset); end  { movss xmm0,[abs] }
            else
              begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($05); EmitGlobRef(Syms[si].Offset); end; { movsd xmm0,[abs] }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);  { mov eax, [ebp+off] }
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($10); EmitB($00); end  { movss xmm0,[eax] }
            else
              begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); end; { movsd xmm0,[eax] }
          end
          else
          begin
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[si].Offset); end  { movss xmm0,[ebp+off] }
            else
              begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[si].Offset); end; { movsd xmm0,[ebp+off] }
          end;
          if tk = tySingle then
            begin EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0); end;   { cvtss2sd xmm0, xmm0 }
          Exit;
        end;
        if tk = tyVariant then
        begin
          { Variant in value position = its slot address. }
          EmitLoadVariantAddr386(node);
          Exit;
        end;
        if tk = tyRecord then
        begin
          { Record in value position = its slot address (by-reference value model,
            like x86-64). The slot holds the record storage itself. }
          if Syms[si].Kind = skGlobal then
            begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end          { mov eax, slot addr }
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end  { mov eax, [ebp+off] = &record }
          else
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end; { lea eax, [ebp+off] }
          Exit;
        end;
        if Is64Bit386(tk) then
        begin
          { Full 8-byte load -> edx:eax (edx = high dword). }
          if Syms[si].Kind = skGlobal then
          begin
            EmitB($A1); EmitGlobRef(Syms[si].Offset);              { mov eax, [slot] }
            EmitB($8B); EmitB($15); EmitGlobRef(Syms[si].Offset + 4); { mov edx, [slot+4] }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);      { mov eax, [ebp+off] (addr) }
            EmitB($8B); EmitB($50); EmitB($04);                    { mov edx, [eax+4] }
            EmitB($8B); EmitB($00);                                { mov eax, [eax] }
          end
          else
          begin
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);      { mov eax, [ebp+off] }
            EmitB($8B); EmitB($95); EmitI32(Syms[si].Offset + 4);  { mov edx, [ebp+off+4] }
          end;
          Exit;
        end;
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
              begin EmitAsm386(['mov eax, [ebp+%]', Syms[si].Offset]); end;
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
          if (IRKind[valNode] = IR_CALL) and (IRA[valNode] = -Ord(tkArgStr)) then
          begin
            argNode := IRB[valNode];
            IREmitNode386(IRA[argNode]);                { eax = argv index }
            EmitArgvToAnsiString386;                    { eax = new handle }
          end
          else if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            j := InternStr(sVal);
            EmitB($68); EmitI32(Strs[j].Len);           { push len }
            EmitB($68); EmitDataRef(Strs[j].Offset + 8); { push src }
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNode386(valNode);                     { eax = char code }
            EmitB($50);                                 { push eax (char code) }
            EmitB($6A); EmitB($01);                     { push 1 (len) }
            EmitB($8D); EmitB($44); EmitB($24); EmitB($04); { lea eax, [esp+4] (ptr to char code) }
            EmitB($50);                                 { push eax (src) }
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
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
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
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
              procIdx := FindProc('PXXStrIncRef');
              if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
              EmitCallProc(procIdx);
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
            procIdx := FindProc('PXXStrDecRef');
            if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
            EmitCallProc(procIdx);
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
            procIdx := FindProc('PXXStrDecRef');
            if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(4);           { add esp, 4 }
            EmitB($58);                                   { pop eax (new handle) }
            if Syms[si].Kind = skGlobal then
              begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end   { mov [slot], eax }
            else
              begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end; { mov [ebp+off], eax }
          end;
          Exit;
        end;
        if (Syms[si].TypeKind = tyString) and not Syms[si].IsArray then
        begin
          { Frozen inline-string assignment (s := <string>): copy [len:8][chars]
            from the source into s's buffer. Without this the scalar store below
            dropped the source ADDRESS into s's slot, clobbering [len]. }
          valNode := IRB[node];
          IREmitNode386(valNode);                     { eax = source string addr (or char ordinal) }
          EmitB($50);                                 { push source/char }
          if Syms[si].Kind = skGlobal then
            begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end          { mov eax, globaddr }
          else if Syms[si].Kind = skParam then
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end  { mov eax, [ebp+off] (forwarded ptr) }
          else
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end; { lea eax, [ebp+off] }
          EmitB($89); EmitB($C7);                     { mov edi, eax (dst) }
          EmitB($5E);                                 { pop esi (src/char) }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            { esi = char ordinal -> [len=1][char] }
            EmitB($C7); EmitB($07); EmitI32(1);       { mov dword [edi], 1 }
            EmitB($C7); EmitB($47); EmitB($04); EmitI32(0); { mov dword [edi+4], 0 }
            EmitB($89); EmitB($F0);                   { mov eax, esi }
            EmitB($88); EmitB($47); EmitB($08);       { mov byte [edi+8], al }
            Exit;
          end;
          EmitB($8B); EmitB($0E);                     { mov ecx, [esi] (len lo) }
          EmitB($89); EmitB($0F);                     { mov [edi], ecx }
          EmitB($8B); EmitB($4E); EmitB($04);         { mov ecx, [esi+4] (len hi) }
          EmitB($89); EmitB($4F); EmitB($04);         { mov [edi+4], ecx }
          EmitB($8B); EmitB($0E);                     { mov ecx, [esi] (count) }
          EmitB($83); EmitB($C6); EmitB($08);         { add esi, 8 }
          EmitB($83); EmitB($C7); EmitB($08);         { add edi, 8 }
          EmitB($F3); EmitB($A4);                     { rep movsb }
          Exit;
        end;
        if Syms[IRA[node]].IsArray and (Syms[IRA[node]].ArrLen = -1) then
        begin
          { Whole dynamic-array handle assignment (`b := a`, `b := Copy(...)`).
            i386 dyn arrays are not refcounted here (no x86-64-style scope-exit
            retain/release), so a plain 4-byte handle store is correct: move the
            new data pointer into the slot. }
          si := IRA[node];
          IREmitNode386(IRB[node]);                              { eax = handle }
          if Syms[si].Kind = skGlobal then
            begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end  { mov [slot], eax }
          else
            begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end; { mov [ebp+off], eax }
          Exit;
        end;
        IREmit386CheckScalarSym(IRA[node], 'store');
        si := IRA[node];
        tk := Syms[si].TypeKind;
        if TypeIsFloat(tk) then
        begin
          IREmitNode386(IRB[node]);
          if not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
            begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end;   { cvtsi2sd xmm0, eax }
          if tk = tySingle then
            begin EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0); end;   { cvtsd2ss xmm0, xmm0 }
          if Syms[si].Kind = skGlobal then
          begin
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($11); EmitB($05); EmitGlobRef(Syms[si].Offset); end  { movss [abs],xmm0 }
            else
              begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($05); EmitGlobRef(Syms[si].Offset); end; { movsd [abs],xmm0 }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset);            { mov eax, [ebp+off] }
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($11); EmitB($00); end  { movss [eax],xmm0 }
            else
              begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($00); end; { movsd [eax],xmm0 }
          end
          else
          begin
            if tk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[si].Offset); end  { movss [ebp+off],xmm0 }
            else
              begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[si].Offset); end; { movsd [ebp+off],xmm0 }
          end;
          Exit;
        end;
        if Is64Bit386(tk) then
        begin
          EmitNode64_386(IRB[node]);                  { value -> edx:eax }
          if Syms[si].Kind = skGlobal then
          begin
            EmitB($A3); EmitGlobRef(Syms[si].Offset);                  { mov [slot], eax }
            EmitB($89); EmitB($15); EmitGlobRef(Syms[si].Offset + 4);  { mov [slot+4], edx }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset);          { mov ecx, [ebp+off] (addr) }
            EmitB($89); EmitB($01);                                    { mov [ecx], eax }
            EmitB($89); EmitB($51); EmitB($04);                        { mov [ecx+4], edx }
          end
          else
          begin
            EmitB($89); EmitB($85); EmitI32(Syms[si].Offset);          { mov [ebp+off], eax }
            EmitB($89); EmitB($95); EmitI32(Syms[si].Offset + 4);      { mov [ebp+off+4], edx }
          end;
          Exit;
        end;
        IREmitNode386(IRB[node]);
        { C double->int: a float RHS (in xmm0) stored into an integer slot must
          truncate (cvttsd2si), not reinterpret whatever is in eax. Mirrors the
          x86-64 IR_STORE_SYM fix; C-mode only. }
        if CProgramMode and TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
          begin EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0); end;   { cvttsd2si eax, xmm0 }
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
          { Dynamic array: slot holds the heap data pointer. Read position loads
            it (Length/indexing want the data ptr); WRITE position wants the
            SLOT's own address instead, so a SetLength target (or the outer
            level of a nested SetLength(a[i], n), which addresses the root
            symbol's own slot via a plain IR_LEA -- it does NOT bypass IR_LEA,
            despite what this comment used to claim) can publish a new handle
            into it. Previously this always loaded the handle regardless of
            InLValueWrite, so SetLength on the array itself wrote through the
            CURRENT (often nil) handle value instead of the slot, silently
            no-opping (or, one level down inside a nested array, computing a
            bogus small-integer "address" from a nil base plus an index stride
            and crashing on any index > 0) -- bug-nested-dynarray-cross-segfault.
            v1: no copy-on-write in write mode either way (single-owner arrays
            only). }
          if Syms[si].Kind = skGlobal then
          begin
            if InLValueWrite then
              begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end        { mov eax, slot addr }
            else
              begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end;       { mov eax, [slot] }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            { by-ref (var/out) named-dynarray param: the slot holds &caller_slot;
              load it (needed either way -- SetLength wants to publish through
              it, Length/indexing want to deref it once more). }
            EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); { mov eax, [ebp+off] = &caller_slot }
            if not InLValueWrite then
              begin EmitB($8B); EmitB($00); end;              { mov eax, [eax] = data ptr }
          end
          else if InLValueWrite then
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end  { lea eax, [ebp+off] }
          else
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end; { mov eax, [ebp+off] }
        end
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray then
        begin
          { Scalar managed string: reads need the heap handle; writes need the
            handle slot address so PXXStrUnique can publish a cloned handle.
            A by-ref param always yields the forwarded caller slot address; read
            Length/index paths add the final deref. }
          if Syms[si].Kind = skGlobal then
          begin
            if InLValueWrite then
              begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end        { mov eax, slot addr }
            else
              begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end;       { mov eax, [slot] }
          end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end  { caller slot addr }
          else if InLValueWrite then
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end  { lea eax, [ebp+off] }
          else
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end; { mov eax, [ebp+off] }
        end
        else if Syms[si].Kind = skGlobal then
        begin
          EmitB($B8); EmitGlobRef(Syms[si].Offset);          { mov eax, abs32 }
        end
        else if (Syms[si].Kind = skParam) and
                (Syms[si].IsRef or Syms[si].IsArray or
                 (Syms[si].TypeKind = tyString)) then
        begin
          { By-ref, open-array, or fixed-string param: the slot holds a
            pointer the caller passed (the array data / buffer / forwarded slot),
            so load the pointer itself, not the slot address. Mirrors x86-64. }
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

    IR_READLINE:
      begin
        procIdx := FindProc('PXXReadLine');
        if procIdx < 0 then Error('compiler error: PXXReadLine not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_DISCARD:
      begin
        procIdx := FindProc('PXXReadDiscard');
        if procIdx < 0 then Error('compiler error: PXXReadDiscard not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_VAR:
      begin
        { Parse one read/readln target from the shared line buffer via the
          portable builtin helpers (x86-64 keeps its asm path). A managed
          string wants its SLOT address, so force lvalue-write mode like the
          x86-64 branch does. }
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode386(IRA[node]);    { eax = slot address }
          InLValueWrite := savedLValueWrite;
          EmitB($50);                  { push slot addr }
          procIdx := FindProc('PXXReadVarStrM');
          if procIdx < 0 then Error('compiler error: PXXReadVarStrM not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(4);   { add esp, 4 }
        end
        else if tk = tyChar then
        begin
          IREmitNode386(IRA[node]);    { eax = target address }
          EmitB($50);
          procIdx := FindProc('PXXReadVarChar');
          if procIdx < 0 then Error('compiler error: PXXReadVarChar not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(4);
        end
        else if TypeIsOrdinal(tk) then
        begin
          IREmitNode386(IRA[node]);    { eax = target address }
          EmitB($50);                  { push dst }
          EmitB($B8); EmitI32(TypeSize(tk));    { mov eax, size }
          EmitB($50);                  { push sz }
          procIdx := FindProc('PXXReadVarInt');
          if procIdx < 0 then Error('compiler error: PXXReadVarInt not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);
        end
        else
          Error('target i386: read/readln target type not supported');
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. Same push order as the
          symbol path above. }
        IREmitNode386(IRA[node]);      { eax = slot address }
        EmitB($50);                    { push slot addr }
        IREmitNode386(IRB[node]);      { eax = new length }
        EmitB($50);                    { push n }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
        EmitCallProc(procIdx);
        EmitB($81); EmitB($C4); EmitI32(8); { add esp, 8 }
      end;

    IR_SETLEN_DYN:
      begin
        { Nested / record-or-class-field SetLength via the portable
          PXXDynSetLen(slotAddr, n, desc) helper. IRA = slot-address node,
          IRB = new length; descriptor allocated from the node metadata. }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := True;
        IREmitNode386(IRA[node]);              { eax = slot addr }
        InLValueWrite := savedLValueWrite;
        EmitB($50);                            { push slot addr }
        IREmitNode386(IRB[node]);              { eax = new length }
        EmitB($50);                            { push n }
        EmitB($68); EmitDataRef(GetOrAllocNodeDynDesc(node)); { push desc }
        procIdx := FindProc('PXXDynSetLen');
        if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
        EmitCallProc(procIdx);
        EmitB($81); EmitB($C4); EmitI32(12);   { add esp, 12 }
      end;

    IR_DYNUNIQUE:
      begin
        { Nested dyn-array copy-on-write. IRA = slot-address node. On a read just
          load the level's data pointer; on a write clone-if-shared via
          PXXDynArrayUnique(slotAddr, desc), publishing the unique handle and
          returning the data pointer. }
        IREmitNode386(IRA[node]);              { eax = slot addr }
        if InLValueWrite then
        begin
          EmitB($50);                          { push slot addr }
          EmitB($68); EmitDataRef(GetOrAllocDynUniqueDesc(node)); { push desc }
          procIdx := FindProc('PXXDynArrayUnique');
          if procIdx < 0 then Error('compiler error: PXXDynArrayUnique not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);  { add esp, 8 }
        end
        else
          begin EmitB($8B); EmitB($00); end;   { mov eax, [eax] }
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
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(procIdx);                            { eax = result }
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
            procIdx := FindProc('PXXStrEq');
            if procIdx < 0 then Error('compiler error: PXXStrEq not found');
            EmitCallProc(procIdx);                            { eax = 1/0 }
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

        lhsTk := IntToTypeKind(IRTk[left]);
        rhsTk := IntToTypeKind(IRTk[right]);
        if TypeIsFloat(lhsTk) or TypeIsFloat(rhsTk) or (op = Ord(tkSlash)) then
        begin
          IREmitNode386(left);
          if not TypeIsFloat(lhsTk) then
            begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end;   { cvtsi2sd xmm0, eax }
          EmitFloatSpill386;
          IREmitNode386(right);
          if TypeIsFloat(rhsTk) then
            begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($C8); end    { movsd xmm1, xmm0 }
          else
            begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C8); end;   { cvtsi2sd xmm1, eax }
          EmitFloatUnspill386;                                           { left -> xmm0 }

          if op = Ord(tkPlus) then
            begin EmitB($F2); EmitB($0F); EmitB($58); EmitB($C1); end    { addsd xmm0, xmm1 }
          else if op = Ord(tkMinus) then
            begin EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C1); end    { subsd xmm0, xmm1 }
          else if op = Ord(tkStar) then
            begin EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1); end    { mulsd xmm0, xmm1 }
          else if op = Ord(tkSlash) then
            begin EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C1); end    { divsd xmm0, xmm1 }
          else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                  (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
          begin
            EmitB($66); EmitB($0F); EmitB($2E); EmitB($C1);              { ucomisd xmm0, xmm1 }
            EmitSetccFloat(op);                                          { NaN-correct (PF) }
          end
          else
            Error('target i386: unsupported float binop');
          Exit;
        end;

        { 64-bit (Int64/UInt64) integer ops use the dedicated edx:eax path.
          A comparison carries a Boolean result tk, so key off the operands. }
        if Is64Bit386(tk) or Is64Bit386(lhsTk) or Is64Bit386(rhsTk) then
        begin
          EmitBinop64_386(left, right, op,
            not ((lhsTk = tyUInt64) or (rhsTk = tyUInt64)));
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
        else if op = Ord(tkDiv) then
        begin
          { unsigned dividend (Cardinal/LongWord, C unsigned int): zero edx + div }
          if TypeDivideUnsigned(lhsTk) then
            begin EmitB($31); EmitB($D2); EmitB($F7); EmitB($F1); end { xor edx,edx; div ecx }
          else
            begin EmitB($99); EmitB($F7); EmitB($F9); end;            { cdq; idiv ecx }
        end
        else if op = Ord(tkMod) then
        begin
          if TypeDivideUnsigned(lhsTk) then
            begin EmitB($31); EmitB($D2); EmitB($F7); EmitB($F1); end { xor edx,edx; div ecx }
          else
            begin EmitB($99); EmitB($F7); EmitB($F9); end;            { cdq; idiv ecx }
          EmitB($89); EmitB($D0);                    { mov eax, edx }
        end
        else if op = Ord(tkAnd) then begin EmitB($21); EmitB($C8); end   { and eax, ecx }
        else if op = Ord(tkOr) then begin EmitB($09); EmitB($C8); end    { or eax, ecx }
        else if op = Ord(tkXor) then begin EmitB($31); EmitB($C8); end   { xor eax, ecx }
        else if op = Ord(tkShl) then begin EmitB($D3); EmitB($E0); end   { shl eax, cl }
        else if op = Ord(tkIdent) then begin EmitB($D3); EmitB($E8); end { 'shr' parses as ident; shr eax, cl }
        else if op = Ord(tkShr) then begin EmitB($D3); EmitB($F8); end   { C signed >> (bug-c-signed-arith-shift-right); sar eax, cl (ModRM /7) }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitB($39); EmitB($C8);                    { cmp eax, ecx }
          { Unsigned operands (Cardinal/LongWord, C unsigned int) need unsigned
            setcc — mirrors the x86-64 cmpUnsigned path. Was hardcoded signed, so
            an inline `LongWord > 0` / C `(a-10u) > 0` compared signed. }
          EmitSetcc(op, not TypeCompareUnsigned(lhsTk, rhsTk));
        end
        else if op = Ord(tkIn) then
        begin
          { Set membership: eax = element, ecx = set address. Byte = element>>3,
            bit = element and 7. Result (0/1) -> eax. }
          EmitB($3D); EmitI32(255);                  { cmp eax, 255 }
          EmitB($0F); EmitB($87); nextJmp := CodeLen; EmitI32(0); { ja out-of-range }
          EmitB($89); EmitB($C2);                    { mov edx, eax }
          EmitB($C1); EmitB($EA); EmitB($03);        { shr edx, 3 (byte index) }
          EmitB($0F); EmitB($B6); EmitB($14); EmitB($11); { movzx edx, byte [ecx+edx] }
          EmitB($83); EmitB($E0); EmitB($07);        { and eax, 7 (bit index) }
          EmitB($89); EmitB($C1);                    { mov ecx, eax }
          EmitB($B8); EmitI32(1);                    { mov eax, 1 }
          EmitB($D3); EmitB($E0);                    { shl eax, cl }
          EmitB($85); EmitB($D0);                    { test eax, edx }
          EmitB($0F); EmitB($95); EmitB($C0);        { setnz al }
          EmitB($0F); EmitB($B6); EmitB($C0);        { movzx eax, al }
          EmitB($E9); falseJmp := CodeLen; EmitI32(0); { jmp done }
          Patch32(nextJmp, CodeLen - (nextJmp + 4));
          EmitB($B8); EmitI32(0);                    { mov eax, 0 }
          Patch32(falseJmp, CodeLen - (falseJmp + 4));
        end
        else
          Error('target i386: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New / class instantiation. Evaluate size -> eax, Alloc.
            For a class: set the VMT pointer at offset 0, then run the ctor and
            return Self in eax (mirrors the x86-64 path; i386 is all-stack cdecl,
            so args are pushed leftmost-deepest and the caller cleans up). }
          classIdx := IRC[node];
          EmitAcquireHeapLock386;
          argNode := IRB[node];          { size arg }
          IREmitNode386(IRA[argNode]);   { size -> eax }
          EmitHeapAllocLocked386;        { eax = payload pointer }
          EmitReleaseHeapLock386;
          if classIdx < REC_UCLASS_BASE then
            Exit;                        { plain GetMem: pointer already in eax }
          { VMT pointer at offset 0 (4 bytes; the 8-byte reserved slot's high
            dword stays zero, matching the data-blob layout). }
          EmitB($C7); EmitB($00); EmitDataRef(UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { mov dword [eax], VMT_addr }
          p1 := IRResolveCtorProc(node, classIdx);   { overload-resolved ctor }
          if p1 < 0 then
            Exit;                        { no ctor: instance pointer in eax }
          EmitB($50);                    { push eax (Self = param 0, deepest) }
          argBytes := 4;
          argNode := IRB[node];          { size arg }
          argNode := IRB[argNode];       { first explicit ctor arg }
          while argNode <> -1 do
          begin
            IREmitNode386(IRA[argNode]); { arg -> eax }
            EmitB($50);                  { push eax }
            Inc(argBytes, 4);
            argNode := IRB[argNode];
          end;
          EmitCallProc(p1);
          { Reload Self (deepest pushed slot) as the constructor result. }
          EmitB($8B); EmitB($84); EmitB($24); EmitI32(argBytes - 4); { mov eax, [esp+disp] }
          EmitB($81); EmitB($C4); EmitI32(argBytes);                 { add esp, argBytes }
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          EmitAcquireHeapLock386;
          argNode := IRB[node];          { pointer arg }
          IREmitNode386(IRA[argNode]);   { p -> eax }
          EmitHeapFreeLocked386;
          EmitReleaseHeapLock386;
          Exit;
        end;
        if procIdx = -102 then
        begin
          { SetLength(arr, n) for a depth-1 dynamic array via the portable
            PXXDynSetLen(slotAddr, n, desc) helper. SetLength on a managed
            AnsiString routes through PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];          { arg1 = array/string lvalue }
          valNode := IRB[argNode];       { arg2 = new length }
          left := IRA[argNode];          { IR_LEA or IR_LOAD_SYM node }
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            si := IRA[left];
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); { caller slot addr }
            end
            else if Syms[si].Kind = skGlobal then
              begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end
            else
              begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end;
            EmitB($50);                    { push slot addr }
            IREmitNode386(IRA[valNode]);   { eax = new length }
            EmitB($50);                    { push n }
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(8); { add esp, 8 }
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target i386: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target i386: SetLength only supports dynamic arrays yet');
          { arg0 = slot address. For a by-ref (var/out) param the slot holds
            &caller_slot, so load it; PXXDynSetLen resizes and publishes the new
            handle back into the caller's slot. }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end  { mov eax, [ebp+off] = &caller_slot }
          else if Syms[si].Kind = skGlobal then
            begin EmitB($B8); EmitGlobRef(Syms[si].Offset); end          { mov eax, slot addr }
          else
            begin EmitB($8D); EmitB($85); EmitI32(Syms[si].Offset); end; { lea eax, [ebp+off] }
          EmitB($50);                    { push slot addr }
          IREmitNode386(IRA[valNode]);   { eax = new length }
          EmitB($50);                    { push n }
          EmitB($68); EmitDataRef(GetOrAllocSymRTTI(si)); { push desc }
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(12); { add esp, 12 }
          Exit;
        end;
        if procIdx = -101 then
        begin
          { SetLength(s, n) on a frozen inline string: store n into the 8-byte
            length prefix at [buffer+0] (hi dword = 0, length < 4GB). The buffer
            is the symbol slot itself for a local/global; for a string param the
            slot holds a pointer P to the buffer. Mirrors x86-64 EmitStoreStrLen. }
          argNode := IRB[node];
          valNode := IRB[argNode];
          left := IRA[argNode];
          if IRKind[left] <> IR_LEA then
            Error('target i386: SetLength expects a string variable');
          si := IRA[left];
          IREmitNode386(IRA[valNode]);   { eax = new length }
          { ecx = buffer base address }
          if (Syms[si].Kind = skParam) and TypeIsFrozenString(Syms[si].TypeKind) then
            begin EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset); end  { mov ecx, [ebp+off] = P }
          else if Syms[si].Kind = skGlobal then
            begin EmitB($B9); EmitGlobRef(Syms[si].Offset); end          { mov ecx, buffer addr }
          else
            begin EmitB($8D); EmitB($8D); EmitI32(Syms[si].Offset); end; { lea ecx, [ebp+off] }
          EmitB($89); EmitB($01);                          { mov [ecx], eax (len lo) }
          EmitB($C7); EmitB($41); EmitB($04); EmitI32(0);  { mov dword [ecx+4], 0 (len hi) }
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          { Length(arr): IR_LEA auto-loaded the data pointer (handle); the
            element count lives at [handle-8] (0 when nil). }
          argNode := IRB[node];
          valNode := IRA[argNode];
          if (IntToTypeKind(IRTk[valNode]) = tyString) or
             ((IRKind[valNode] = IR_LEA) and
              (Syms[IRA[valNode]].TypeKind = tyString) and
              not Syms[IRA[valNode]].IsArray) or
             (((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LOAD_MEM)) and
              (IntToTypeKind(IRTk[valNode]) = tyPointer)) then
          begin
            { Frozen inline string: length is the 8-byte prefix at [buffer+0]. A
              frozen string reached through a pointer deref (`ps^`, `rec.pf^`)
              lowers to a bare pointer load whose value IS the buffer address;
              read the prefix there, mirroring x86-64's else catch-all. }
            IREmitNode386(valNode);      { eax = frozen buffer addr }
            EmitB($8B); EmitB($00);      { mov eax, [eax] }
            Exit;
          end;
          IREmitNode386(valNode);        { eax = handle (data ptr) or 0 }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) or
             ((IRKind[valNode] = IR_LEA) and (Syms[IRA[valNode]].Kind = skParam) and
              Syms[IRA[valNode]].IsRef and (Syms[IRA[valNode]].TypeKind = tyAnsiString) and
              not Syms[IRA[valNode]].IsArray) then
            begin EmitB($8B); EmitB($00); end;  { mov eax, [eax] (deref slot/&handle to handle) }
          EmitB($85); EmitB($C0);        { test eax, eax }
          EmitB($74); EmitB($03);        { jz +3 }
          EmitB($8B); EmitB($40); EmitB($F8); { mov eax, [eax-8] }
          Exit;
        end;
        if procIdx = -100 then
        begin
          { LoadFile(path, dst): path is a managed-string C string; dst is a
            managed AnsiString variable. }
          argNode := IRB[node];
          left := IRA[argNode];          { path node }
          valNode := IRB[argNode];       { arg2 }
          right := IRA[valNode];         { dst node }
          if not ((IRKind[right] = IR_LOAD_SYM) and
                  (Syms[IRA[right]].TypeKind = tyAnsiString)) then
            Error('target i386: LoadFile expects a managed-string destination');
          si := IRA[right];
          IREmitNode386(left);           { eax = path handle }
          EmitB($50);                    { push path }
          procIdx := FindProc('PXXStrLoadFile');
          if procIdx < 0 then Error('compiler error: PXXStrLoadFile not found');
          EmitCallProc(procIdx);              { eax = new handle }
          EmitB($81); EmitB($C4); EmitI32(4);
          EmitB($50);                    { push new }
          if Syms[si].Kind = skGlobal then
            begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset); { caller slot }
            EmitB($8B); EmitB($01);                           { old }
          end
          else
            begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end;
          procIdx := FindProc('PXXStrDecRef');
          if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
          EmitB($50);                    { push old }
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(4);
          EmitB($58);                    { pop new }
          if Syms[si].Kind = skGlobal then
            begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end
          else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset); { caller slot }
            EmitB($89); EmitB($01);                           { store new }
          end
          else
            begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end;
          Exit;
        end;
        if procIdx < 0 then
        begin
          j := -procIdx;
          if (j = Ord(tkOrd)) or (j = Ord(tkChr)) or
             (j = Ord(tkInteger_T)) or (j = Ord(tkLongWord_T)) or
             (j = Ord(tkChar_T)) or (j = Ord(tkBoolean_T)) or
             (j = Ord(tkString_T)) then
          begin
            { type-pun passthrough: evaluate the argument in place }
            argNode := IRB[node];
            IREmitNode386(IRA[argNode]);
            Exit;
          end;
          if j = Ord(tkArgCount) then
          begin
            EmitB($A1); EmitGlobRef(BSS_INITIAL_RSP); { mov eax, [initial_sp] }
            EmitB($8B); EmitB($00);                   { mov eax, [eax] argc }
            EmitB($83); EmitB($E8); EmitB($01);       { sub eax, 1 }
            Exit;
          end
          else if j = Ord(tkArgStr) then
          begin
            argNode := IRB[node];
            if argNode = -1 then
              Error('target i386: ArgStr expects an index');
            IREmitNode386(IRA[argNode]);      { eax = argv index }
            argNode := IRB[argNode];
            if argNode = -1 then
              Error('target i386: ParamStr expression must be assigned directly');
            valNode := IRA[argNode];
            { Managed-string dest (scalar `string` is tyAnsiString by default):
              build a heap AnsiString from argv[index] and publish it (release
              dst's old handle), mirroring LoadFile. The fixed-buffer emitter
              below is for a frozen string dest only. }
            if (IRKind[valNode] = IR_LOAD_SYM) and
               (Syms[IRA[valNode]].TypeKind = tyAnsiString) then
            begin
              si := IRA[valNode];
              EmitArgvToAnsiString386;         { eax (index) -> eax = new handle }
              EmitB($50);                      { push new }
              if Syms[si].Kind = skGlobal then
                begin EmitB($A1); EmitGlobRef(Syms[si].Offset); end
              else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
              begin
                EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset); { caller slot }
                EmitB($8B); EmitB($01);                           { old }
              end
              else
                begin EmitB($8B); EmitB($85); EmitI32(Syms[si].Offset); end;
              procIdx := FindProc('PXXStrDecRef');
              if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
              EmitB($50);                      { push old }
              EmitCallProc(procIdx);
              EmitB($81); EmitB($C4); EmitI32(4);
              EmitB($58);                      { pop new }
              if Syms[si].Kind = skGlobal then
                begin EmitB($A3); EmitGlobRef(Syms[si].Offset); end
              else if (Syms[si].Kind = skParam) and Syms[si].IsRef then
              begin
                EmitB($8B); EmitB($8D); EmitI32(Syms[si].Offset); { caller slot }
                EmitB($89); EmitB($01);                           { store new }
              end
              else
                begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end;
              Exit;
            end;
            if IRKind[valNode] <> IR_LEA then
              Error('target i386: ArgStr expects a string variable');
            EmitArgvToFixedString386(IRA[valNode]);
            Exit;
          end;
          if j = 200 then
          begin
            { int(x): float/Variant -> integer }
            argNode := IRB[node];
            valNode := IRA[argNode];
            if IntToTypeKind(IRTk[valNode]) = tyVariant then
            begin
              EmitLoadVariantAddr386(valNode);            { eax = slot addr }
              EmitB($8B); EmitB($08);                     { mov ecx, [eax] (tag low) }
              EmitB($83); EmitB($F9); EmitB(VT_DOUBLE);   { cmp ecx, VT_DOUBLE }
              EmitB($75); nextJmp := CodeLen; EmitB(0);   { jne .not_double }
              EmitB($F2); EmitB($0F); EmitB($10); EmitB($40); EmitB($08); { movsd xmm0,[eax+8] }
              EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0);             { cvttsd2si eax, xmm0 }
              EmitB($EB); nextJmp2 := CodeLen; EmitB(0);  { jmp .done }
              Code[nextJmp] := Byte(CodeLen - (nextJmp + 1));
              EmitB($8B); EmitB($40); EmitB($08);         { mov eax, [eax+8] (payload low) }
              Code[nextJmp2] := Byte(CodeLen - (nextJmp2 + 1));
              Exit;
            end;
            IREmitNode386(valNode);
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
              begin EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0); end;  { cvttsd2si eax, xmm0 }
            Exit;
          end
          else if (j = 203) or (j = 204) or (j = 205) or (j = 206) then
          begin
            { Float intrinsics: 203 Trunc, 204 Round, 205 Frac, 206 Int }
            argNode := IRB[node];
            valNode := IRA[argNode];
            IREmitNode386(valNode);
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
            begin
              if j = 203 then
              begin
                { Trunc -> Int64. cvttsd2si only yields a 32-bit result on i386
                  (no 64-bit GPR); cdq-extending it overflows any |x|>=2^31 to the
                  0x80000000 sentinel (breaks e.g. sqlite's double->u64 in %f
                  formatting). Do a true 64-bit truncating convert via x87 fisttp. }
                EmitB($83); EmitB($EC); EmitB($08);                        { sub esp, 8 }
                EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [esp], xmm0 }
                EmitB($DD); EmitB($04); EmitB($24);                        { fld qword [esp] }
                EmitB($DD); EmitB($0C); EmitB($24);                        { fisttp qword [esp] (truncate) }
                EmitB($8B); EmitB($04); EmitB($24);                        { mov eax, [esp] }
                EmitB($8B); EmitB($54); EmitB($24); EmitB($04);            { mov edx, [esp+4] }
                EmitB($83); EmitB($C4); EmitB($08);                        { add esp, 8 }
              end
              else if j = 204 then
              begin
                { Round -> Int64 via x87 fistp (uses the default round-to-nearest
                  control word), full 64-bit result in edx:eax. }
                EmitB($83); EmitB($EC); EmitB($08);                        { sub esp, 8 }
                EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [esp], xmm0 }
                EmitB($DD); EmitB($04); EmitB($24);                        { fld qword [esp] }
                EmitB($DF); EmitB($3C); EmitB($24);                        { fistp qword [esp] (round) }
                EmitB($8B); EmitB($04); EmitB($24);                        { mov eax, [esp] }
                EmitB($8B); EmitB($54); EmitB($24); EmitB($04);            { mov edx, [esp+4] }
                EmitB($83); EmitB($C4); EmitB($08);                        { add esp, 8 }
              end
              else if j = 205 then
              begin
                { Frac = x - trunc(x) }
                EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0);            { cvttsd2si eax, xmm0 }
                EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C8);            { cvtsi2sd xmm1, eax }
                EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C1);            { subsd xmm0, xmm1 }
              end
              else
              begin
                { Int = trunc as float }
                EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0);            { cvttsd2si eax, xmm0 }
                EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0);            { cvtsi2sd xmm0, eax }
              end;
            end
            else
            begin
              { integer argument }
              if j = 205 then
                begin EmitB($66); EmitB($0F); EmitB($EF); EmitB($C0); end  { pxor xmm0, xmm0 = 0.0 }
              else if j = 206 then
                begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end  { cvtsi2sd xmm0, eax }
              else
                EmitB($99);   { 203/204: eax already holds the value; cdq -> Int64 }
            end;
            Exit;
          end
          else if j = SPECIAL_IN then
          begin
            { x in [items]: items are constant single values or [lo..hi] ranges
              (IR_BLOCK, lo in IRA, hi in IRB). Accumulate membership in edx. }
            argNode := IRB[node];          { arg1 = test value }
            IREmitNode386(IRA[argNode]);   { eax = test value }
            EmitB($89); EmitB($C1);        { mov ecx, eax }
            EmitB($31); EmitB($D2);        { xor edx, edx (result) }
            argNode := IRB[argNode];       { first set item }
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                lo := Integer(IRIVal[IRA[itemNode]]);
                hi := Integer(IRIVal[IRB[itemNode]]);
                EmitB($81); EmitB($F9); EmitI32(lo);       { cmp ecx, lo }
                EmitB($0F); EmitB($8C); p1 := CodeLen; EmitI32(0); { jl skip }
                EmitB($81); EmitB($F9); EmitI32(hi);       { cmp ecx, hi }
                EmitB($0F); EmitB($8F); p2 := CodeLen; EmitI32(0); { jg skip }
                EmitB($BA); EmitI32(1);                    { mov edx, 1 }
                Patch32(p1, CodeLen - (p1 + 4));
                Patch32(p2, CodeLen - (p2 + 4));
              end
              else
              begin
                lo := Integer(IRIVal[itemNode]);
                EmitB($81); EmitB($F9); EmitI32(lo);       { cmp ecx, lo }
                EmitB($0F); EmitB($94); EmitB($C0);        { sete al }
                EmitB($0F); EmitB($B6); EmitB($C0);        { movzx eax, al }
                EmitB($09); EmitB($C2);                    { or edx, eax }
              end;
              argNode := IRB[argNode];
            end;
            EmitB($89); EmitB($D0);        { mov eax, edx }
            Exit;
          end
          else if j = Ord(tkSysOpen) then
          begin
            argNode := IRB[node];
            valNode := IRA[argNode];
            if IntToTypeKind(IRTk[valNode]) <> tyAnsiString then
              Error('target i386: SysOpen expects a managed AnsiString path');
            IREmitNode386(valNode);          { eax = path }
            EmitB($50);                      { push path }
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { eax = flags }
            EmitB($89); EmitB($C1);          { mov ecx, eax }
            EmitB($5B);                      { pop ebx path }
            EmitB($31); EmitB($D2);          { xor edx, edx mode }
            EmitB($B8); EmitI32(5);          { __NR_open }
            EmitB($CD); EmitB($80);
            Exit;
          end
          else if j = Ord(tkSysRead) then
          begin
            argNode := IRB[node];
            IREmitNode386(IRA[argNode]);     { fd }
            EmitB($50);
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { buf }
            EmitB($50);
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { count }
            EmitB($89); EmitB($C2);          { mov edx, eax }
            EmitB($59);                      { pop ecx buf }
            EmitB($5B);                      { pop ebx fd }
            EmitB($B8); EmitI32(3);          { __NR_read }
            EmitB($CD); EmitB($80);
            Exit;
          end
          else if j = Ord(tkSyswrite) then
          begin
            argNode := IRB[node];
            IREmitNode386(IRA[argNode]);     { fd }
            EmitB($50);
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { buf }
            EmitB($50);
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { count }
            EmitB($89); EmitB($C2);          { mov edx, eax }
            EmitB($59);                      { pop ecx buf }
            EmitB($5B);                      { pop ebx fd }
            EmitB($B8); EmitI32(4);          { __NR_write }
            EmitB($CD); EmitB($80);
            Exit;
          end
          else if j = Ord(tkSysClose) then
          begin
            argNode := IRB[node];
            IREmitNode386(IRA[argNode]);     { fd }
            EmitB($89); EmitB($C3);          { mov ebx, eax }
            EmitB($B8); EmitI32(6);          { __NR_close }
            EmitB($CD); EmitB($80);
            Exit;
          end
          else if j = Ord(tkSysFchmod) then
          begin
            argNode := IRB[node];
            IREmitNode386(IRA[argNode]);     { fd }
            EmitB($50);
            argNode := IRB[argNode];
            IREmitNode386(IRA[argNode]);     { mode }
            EmitB($89); EmitB($C1);          { mov ecx, eax }
            EmitB($5B);                      { pop ebx fd }
            EmitB($B8); EmitI32(94);         { __NR_fchmod }
            EmitB($CD); EmitB($80);
            Exit;
          end
          else if j = 210 then
          begin
            { bare `Eof` (stdin) -> PXXStdinEof: Boolean (portable builtin,
              shares the peek byte with PXXReadLine). }
            procIdx := FindProc('PXXStdinEof');
            if procIdx < 0 then Error('compiler error: PXXStdinEof not found');
            EmitCallProc(procIdx);
            Exit;
          end
          else
          begin
            ErrorIdent := 'builtin id ' + MangleSuffix(-procIdx);
            Error('target i386: builtin/special call not yet supported');
          end;
        end;
        if ProcExternal[procIdx] then
        begin
          { External C call (cdecl): args at [esp+0], [esp+4], ... (arg0 lowest);
            caller cleans the stack. Each arg occupies its natural cdecl width:
            8 bytes for double/extended and Int64/UInt64, 4 bytes for single
            (prototyped C `float`), int, char and pointer. Integer/pointer
            returns come back in eax, Int64/UInt64 in edx:eax (matching the
            internal 64-bit pair model), and float/double returns in st0 — which
            we bridge to xmm0 (the i386 float value model). The call site is
            16-byte aligned per SysV i386: save the caller esp, `and esp,-16`,
            reserve a 16-rounded frame holding the arg block plus the saved-esp
            slot, then restore esp from that slot after the call. The call goes
            through the external's GOT slot via the same FF/14/25 indirect-call
            encoding as x86-64; writeELF32 patches the abs32 operand to the slot
            VA and the dynamic linker fills it. }
          argNode := IRB[node];
          nArgs := 0;
          argBytes := 0;
          while argNode <> -1 do
          begin
            if nArgs < Procs[procIdx].ParamCount then
            begin
              tk := Procs[procIdx].Params[nArgs].TypeKind;
              if (tk = tyDouble) or (tk = tyExtended) or Is64Bit386(tk) then
                Inc(argBytes, 8)
              else
                Inc(argBytes, 4);
            end;
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if nArgs <> Procs[procIdx].ParamCount then
            Error('target i386: external call argument count mismatch');
          { Reserve a 16-rounded frame: arg block + 4-byte saved-esp slot. }
          base := ((argBytes + 4 + 15) div 16) * 16;
          EmitB($89); EmitB($E1);                        { mov ecx, esp }
          EmitB($83); EmitB($E4); EmitB($F0);            { and esp, -16 }
          EmitB($81); EmitB($EC); EmitI32(base);         { sub esp, base }
          EmitB($89); EmitB($8C); EmitB($24); EmitI32(argBytes); { mov [esp+argBytes], ecx }
          argNode := IRB[node];
          i := 0;
          sz := 0;                                       { running arg offset }
          while argNode <> -1 do
          begin
            tk := Procs[procIdx].Params[i].TypeKind;
            if (tk = tyDouble) or (tk = tyExtended) then
            begin
              IREmitNode386(IRA[argNode]);               { float -> xmm0 (double) }
              if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
                begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end; { cvtsi2sd xmm0, eax }
              EmitB($F2); EmitB($0F); EmitB($11); EmitB($84); EmitB($24); EmitI32(sz); { movsd [esp+off], xmm0 }
              Inc(sz, 8);
            end
            else if tk = tySingle then
            begin
              IREmitNode386(IRA[argNode]);               { -> xmm0 (double) }
              if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
                begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end; { cvtsi2sd xmm0, eax }
              EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);             { cvtsd2ss xmm0, xmm0 }
              EmitB($F3); EmitB($0F); EmitB($11); EmitB($84); EmitB($24); EmitI32(sz); { movss [esp+off], xmm0 }
              Inc(sz, 4);
            end
            else if Is64Bit386(tk) then
            begin
              IREmitNode386(IRA[argNode]);               { -> edx:eax }
              if not Is64Bit386(IntToTypeKind(IRTk[IRA[argNode]])) then
              begin
                if TypeSigned(IntToTypeKind(IRTk[IRA[argNode]])) then EmitB($99) { cdq }
                else begin EmitB($31); EmitB($D2); end;  { xor edx, edx }
              end;
              EmitB($89); EmitB($84); EmitB($24); EmitI32(sz);       { mov [esp+off], eax }
              EmitB($89); EmitB($94); EmitB($24); EmitI32(sz + 4);   { mov [esp+off+4], edx }
              Inc(sz, 8);
            end
            else
            begin
              IREmitNode386(IRA[argNode]);               { eax = arg }
              EmitB($89); EmitB($84); EmitB($24); EmitI32(sz);       { mov [esp+off], eax }
              Inc(sz, 4);
            end;
            Inc(i);
            argNode := IRB[argNode];
          end;
          EmitExternalIndirectCall(RegisterExternal(procIdx)); { call dword [GOT slot] }
          EmitB($8B); EmitB($A4); EmitB($24); EmitI32(argBytes); { mov esp, [esp+argBytes] }
          if Procs[procIdx].RetType = tySingle then
          begin
            EmitB($83); EmitB($EC); EmitB($04);          { sub esp, 4 }
            EmitB($D9); EmitB($5C); EmitB($24); EmitB($00); { fstp dword [esp] }
            EmitB($F3); EmitB($0F); EmitB($10); EmitB($04); EmitB($24); { movss xmm0, [esp] }
            EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0); { cvtss2sd xmm0, xmm0 }
            EmitB($83); EmitB($C4); EmitB($04);          { add esp, 4 }
          end
          else if TypeIsFloat(Procs[procIdx].RetType) then
          begin
            EmitB($83); EmitB($EC); EmitB($08);          { sub esp, 8 }
            EmitB($DD); EmitB($5C); EmitB($24); EmitB($00); { fstp qword [esp] }
            EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24); { movsd xmm0, [esp] }
            EmitB($83); EmitB($C4); EmitB($08);          { add esp, 8 }
          end;
          Exit;
        end;
        { Internal i386 convention: evaluate and push args left to right
          (leftmost ends up deepest, matching the callee's spill formula),
          call, then the caller pops the arg area. Result in eax.
          For a VARIADIC call ALL args are pushed in REVERSE index order so the
          whole block is FORWARD in memory (arg0 at [ebp+8], ascending). The
          callee then reads its named params with the FORWARD spill (ProcVariadic
          branch in parser.inc) and va_arg walks the tail forward from
          [ebp+8+namedBytes]. A non-variadic call keeps plain index order (the
          reversed spill). }
        vaNvw := 0;
        argNode := IRB[node];
        while argNode <> -1 do
        begin
          if vaNvw > 127 then Error('target i386: too many call arguments');
          vaOrder[vaNvw] := argNode; Inc(vaNvw); argNode := IRB[argNode];
        end;
        vaFwd := (procIdx >= 0) and ProcVariadic[procIdx];
        if vaFwd then
        begin
          vaO1 := 0; vaO2 := vaNvw - 1;
          while vaO1 < vaO2 do
          begin
            i := vaOrder[vaO1]; vaOrder[vaO1] := vaOrder[vaO2]; vaOrder[vaO2] := i;
            Inc(vaO1); Dec(vaO2);
          end;
        end;
        nArgs := 0;
        vaK := 0;
        argBytes := 0;
        if vaNvw > 0 then argNode := vaOrder[0] else argNode := -1;
        while argNode <> -1 do
        begin
          { param index of the current arg (vaOrder is reversed when vaFwd) }
          if vaFwd then nArgs := vaNvw - 1 - vaK else nArgs := vaK;
          IREmitNode386(IRA[argNode]);
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
             (Procs[procIdx].Params[nArgs].TypeKind = tySet) and
             (not Procs[procIdx].Params[nArgs].IsRef) and
             (not Procs[procIdx].Params[nArgs].IsArray) then
          begin
            { Set by-value param: eax is the 32-byte set address. Push high
              dwords first so byte 0 is at the callee's lowest arg address. }
            for i := 7 downto 0 do
            begin
              EmitB($8B); EmitB($50); EmitB(i * 4);    { mov edx, [eax+i*4] }
              EmitB($52);                              { push edx }
            end;
            Inc(argBytes, TypeSize(tySet));
            Inc(nArgs);
            Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
            Continue;
          end;
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
             Is64Bit386(Procs[procIdx].Params[nArgs].TypeKind) and
             (Procs[procIdx].Params[nArgs].IsArray or not Procs[procIdx].Params[nArgs].IsRef) then
          begin
            { 64-bit by-value param: widen the (possibly 32-bit) value to
              edx:eax, then push both dwords (lo at the lower address). }
            tk := IntToTypeKind(IRTk[IRA[argNode]]);
            if not Is64Bit386(tk) then
            begin
              if TypeSigned(tk) then EmitB($99)              { cdq }
              else begin EmitB($31); EmitB($D2); end;        { xor edx, edx }
            end;
            EmitB($52);                                { push edx (hi) }
            EmitB($50);                                { push eax (lo) }
            Inc(argBytes, 8);
            Inc(nArgs);
            Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
            Continue;
          end;
          if (procIdx >= 0) and (nArgs >= Procs[procIdx].ParamCount) and
             (Is64Bit386(IntToTypeKind(IRTk[IRA[argNode]])) or
              (IntToTypeKind(IRTk[IRA[argNode]]) = tyDouble)) then
          begin
            { Variadic tail 64-bit arg (int64/uint64 in edx:eax, double in xmm0):
              push both dwords, lo at the lower address. }
            vaTk := IntToTypeKind(IRTk[IRA[argNode]]);
            if vaTk = tyDouble then
            begin
              EmitB($83); EmitB($EC); EmitB($08);                         { sub esp, 8 }
              EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [esp], xmm0 }
            end
            else
            begin
              EmitB($52);                              { push edx (hi) }
              EmitB($50);                              { push eax (lo) }
            end;
            Inc(argBytes, 8);
            Inc(nArgs);
            Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
            Continue;
          end;
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) then
          begin
            if TypeIsFloat(Procs[procIdx].Params[nArgs].TypeKind) then
            begin
              if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
              begin
                EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); { cvtsi2sd xmm0, eax }
              end;
              if Procs[procIdx].Params[nArgs].TypeKind = tySingle then
              begin
                { xmm0 holds the value as DOUBLE bits; narrow to single before
                  pushing 4 bytes (movss alone would store the low dword of the
                  double bits = garbage). }
                EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0); { cvtsd2ss xmm0, xmm0 }
                EmitB($83); EmitB($EC); EmitB($04);             { sub esp, 4 }
                EmitB($F3); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movss [esp], xmm0 }
                Inc(argBytes, 4);
              end
              else
              begin
                EmitFloatSpill386;                              { push double slot }
                Inc(argBytes, 8);
              end;
              Inc(nArgs);
              Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
              Continue;
            end;
            if Procs[procIdx].Params[nArgs].TypeKind = tyAnsiString then
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
          Inc(argBytes, 4);
          Inc(nArgs);
          Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
        end;
        { Variadic callee: cdecl pushes all actual args right-to-left and the
          caller cleans `argBytes` (which counts them all), so a variadic call
          with more args than declared params marshals correctly — only strict
          equality blocked it. }
        if (vaNvw <> Procs[procIdx].ParamCount) and not ProcVariadic[procIdx] then
          Error('target i386: call argument count mismatch (defaults not supported yet)');
        if RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          { Aggregate result: pass the caller's hidden destination buffer in ecx
            (args already pushed; computing the address only touches eax). The
            callee copies Result there and returns the pointer in eax. }
          IREmitNode386(IRC[node]);                  { eax = hidden destination }
          EmitB($89); EmitB($C1);                    { mov ecx, eax }
        end;
        EmitCallProc(procIdx);                            { E8 rel32 + fixup, same as x86-64 }
        if argBytes > 0 then
        begin
          EmitB($81); EmitB($C4); EmitI32(argBytes); { add esp, argBytes }
        end;
        { Float result: the callee returned the bits in eax(:edx); move into xmm0
          for the SSE value model. A Single (eax) is widened to double. }
        if Procs[procIdx].RetType = tySingle then
        begin
          EmitB($66); EmitB($0F); EmitB($6E); EmitB($C0); { movd xmm0, eax }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0); { cvtss2sd xmm0, xmm0 }
        end
        else if TypeIsFloat(Procs[procIdx].RetType) then
        begin
          EmitB($52);                                     { push edx (hi) }
          EmitB($50);                                     { push eax (lo) }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24); { movsd xmm0, [esp] }
          EmitB($83); EmitB($C4); EmitB($08);             { add esp, 8 }
        end;
      end;

    IR_CALL_IND:
      begin
        { Indirect call through a proc-typed value. Same caller-cleanup cdecl
          push convention as IR_CALL; the callee address is evaluated last (args
          already on the stack, so a simple proc-var load can't disturb them)
          and reached via `call eax`. Args are marshalled by the SIGNATURE proc's
          param types — critically a 64-bit (int64) or double by-value param is 8
          bytes, not 4; pushing it as 4 shifts every following arg's stack slot
          in the callee (sqlite's VFS xRead/xWrite take an sqlite_int64 offset).
          A VARIADIC signature (fnptr = &fprintf, 00189) needs the same vaFwd
          arg-order reversal + variadic-tail 8-byte widening the direct IR_CALL
          path applies, otherwise the callee reads the format arg from the wrong
          stack slot and segfaults. }
        procIdx := Integer(IRIVal[node]);            { signature proc index }
        vaNvw := 0;
        argNode := IRB[node];
        while argNode <> -1 do
        begin
          if vaNvw > 127 then Error('target i386: too many call arguments');
          vaOrder[vaNvw] := argNode; Inc(vaNvw); argNode := IRB[argNode];
        end;
        vaFwd := (procIdx >= 0) and ProcVariadic[procIdx];
        if vaFwd then
        begin
          vaO1 := 0; vaO2 := vaNvw - 1;
          while vaO1 < vaO2 do
          begin
            i := vaOrder[vaO1]; vaOrder[vaO1] := vaOrder[vaO2]; vaOrder[vaO2] := i;
            Inc(vaO1); Dec(vaO2);
          end;
        end;
        argBytes := 0;
        vaK := 0;
        if vaNvw > 0 then argNode := vaOrder[0] else argNode := -1;
        while argNode <> -1 do
        begin
          if vaFwd then nArgs := vaNvw - 1 - vaK else nArgs := vaK;
          IREmitNode386(IRA[argNode]);
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
             Is64Bit386(Procs[procIdx].Params[nArgs].TypeKind) and
             (not Procs[procIdx].Params[nArgs].IsRef) then
          begin
            { 64-bit by-value param: widen a 32-bit value to edx:eax, push hi then lo. }
            tk := IntToTypeKind(IRTk[IRA[argNode]]);
            if not Is64Bit386(tk) then
            begin
              if TypeSigned(tk) then EmitB($99)              { cdq }
              else begin EmitB($31); EmitB($D2); end;        { xor edx, edx }
            end;
            EmitB($52);                              { push edx (hi) }
            EmitB($50);                              { push eax (lo) }
            Inc(argBytes, 8);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  (Procs[procIdx].Params[nArgs].TypeKind = tyDouble) and
                  (not Procs[procIdx].Params[nArgs].IsRef) then
          begin
            { double by-value param: value in xmm0 -> 8-byte stack slot. }
            if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
              begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end;  { cvtsi2sd xmm0, eax }
            EmitB($83); EmitB($EC); EmitB($08);                          { sub esp, 8 }
            EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24);  { movsd [esp], xmm0 }
            Inc(argBytes, 8);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  (Procs[procIdx].Params[nArgs].TypeKind = tySingle) and
                  (not Procs[procIdx].Params[nArgs].IsRef) then
          begin
            if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
              begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end;  { cvtsi2sd xmm0, eax }
            EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);              { cvtsd2ss xmm0, xmm0 }
            EmitB($83); EmitB($EC); EmitB($04);                          { sub esp, 4 }
            EmitB($F3); EmitB($0F); EmitB($11); EmitB($04); EmitB($24);  { movss [esp], xmm0 }
            Inc(argBytes, 4);
          end
          else if (procIdx >= 0) and (nArgs >= Procs[procIdx].ParamCount) and
                  (Is64Bit386(IntToTypeKind(IRTk[IRA[argNode]])) or
                   (IntToTypeKind(IRTk[IRA[argNode]]) = tyDouble)) then
          begin
            { variadic tail 64-bit arg (int64/uint64 in edx:eax, double in xmm0):
              push both dwords, lo at the lower address (mirrors direct IR_CALL). }
            if IntToTypeKind(IRTk[IRA[argNode]]) = tyDouble then
            begin
              EmitB($83); EmitB($EC); EmitB($08);                         { sub esp, 8 }
              EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [esp], xmm0 }
            end
            else
            begin
              EmitB($52);                            { push edx (hi) }
              EmitB($50);                            { push eax (lo) }
            end;
            Inc(argBytes, 8);
          end
          else
          begin
            EmitB($50);                              { push eax }
            Inc(argBytes, 4);
          end;
          Inc(vaK); if vaK >= vaNvw then argNode := -1 else argNode := vaOrder[vaK];
        end;
        IREmitNode386(IRA[node]);                    { eax = callee addr }
        if IRCallDest[node] >= 0 then
        begin
          { Aggregate / frozen-string result: the hidden caller-destination goes
            in ecx (the pxx indirect-result reg, what EmitAggregateDestStash
            reads). The callee address is already in eax and the dest IR_LEA also
            lands in eax, so park the callee on the stack across it. }
          EmitB($50);                                { push eax (callee) }
          IREmitNode386(IRCallDest[node]);           { eax = hidden destination }
          EmitB($89); EmitB($C1);                    { mov ecx, eax }
          EmitB($58);                                { pop eax (callee) }
        end;
        EmitB($FF); EmitB($D0);                      { call eax }
        if argBytes > 0 then
        begin
          EmitB($81); EmitB($C4); EmitI32(argBytes); { add esp, argBytes }
        end;
      end;

    IR_VIRTUAL_CALL:
      begin
        { VMT dispatch. IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot.
          cdecl: push args leftmost-deepest (Self is param 0, deepest), load the
          VMT pointer from [Self], call through [VMT + slot*8] (the data blob
          keeps 8-byte slots on every target; the 32-bit address sits in the low
          dword, so a 4-byte indirect call reads it). Caller cleans up. }
        procIdx := IRC[node];
        j := Integer(IRIVal[node]);                  { VMT slot }
        argBytes := 0;
        argNode := IRA[node];
        while argNode <> -1 do
        begin
          IREmitNode386(IRA[argNode]);               { eax = arg }
          EmitB($50);                                { push eax }
          Inc(argBytes, 4);
          argNode := IRB[argNode];
        end;
        if IRCallDest[node] >= 0 then
        begin
          { Aggregate / frozen-string result: load the hidden caller-destination
            into ecx BEFORE the Self fetch — the dest IR_LEA lands in eax, which
            the VMT dispatch below then reuses for Self. }
          IREmitNode386(IRCallDest[node]);           { eax = hidden destination }
          EmitB($89); EmitB($C1);                    { mov ecx, eax }
        end;
        EmitB($8B); EmitB($84); EmitB($24); EmitI32(argBytes - 4); { mov eax, [esp+disp] (Self) }
        EmitB($8B); EmitB($00);                      { mov eax, [eax] (VMT ptr) }
        EmitB($FF); EmitB($90); EmitI32(j * 8);      { call dword [eax + slot*8] }
        if argBytes > 0 then
        begin
          EmitB($81); EmitB($C4); EmitI32(argBytes); { add esp, argBytes }
        end;
      end;

    IR_PROCADDR:
      begin
        { @proc -> mov eax, imm32 (absolute code address, patched at finalize). }
        if ProcExternal[IRA[node]] then
          Error('@ on external routine not supported; wrap it in a local routine');
        EmitB($B8);                                  { mov eax, imm32 }
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI32(0);
      end;

    IR_COSWITCH:
      begin
        { __pxxcoswitch(pfrom, pto): cdecl — push pto then pfrom (pfrom ends at
          [esp+4], pto at [esp+8] as the stub expects), call the CoSwitch stub,
          drop the two args. }
        argNode := IRB[IRA[node]];                   { IR_ARG for pto }
        IREmitNode386(IRA[argNode]);                 { eax = pto }
        EmitB($50);                                  { push pto }
        argNode := IRA[node];                        { IR_ARG for pfrom }
        IREmitNode386(IRA[argNode]);                 { eax = pfrom }
        EmitB($50);                                  { push pfrom }
        EmitB($E8); EmitI32(CoSwitchAddr - (CodeLen + 4)); { call CoSwitch }
        EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
      end;

    IR_IO_LOCK:
      begin EmitB($E8); EmitI32(IOLockAddr - (CodeLen + 4)); end;   { call IO lock }

    IR_IO_UNLOCK:
      begin EmitB($E8); EmitI32(IOUnlockAddr - (CodeLen + 4)); end; { call IO unlock }

    IR_CLONE:
      begin
        { __pxxclone(flags, childStack, entry, arg, ctidptr): evaluate the five
          args left-to-right onto the stack (flags deepest — the stub's stack
          contract), call the bare clone+trampoline stub, drop the args, then
          widen the tid to the node's Int64 (cdq: a negative errno stays
          negative). 64-bit args (StackBase+size arithmetic) truncate to their
          low word here, which is exact on a 32-bit address space. }
        EnsureCloneStub;
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode386(IRA[argNode]);
          EmitB($50);                                { push eax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        EmitB($E8); EmitI32(CloneStubAddr - (CodeLen + 4));  { call clone stub }
        EmitB($81); EmitB($C4); EmitI32(nArgs * 4);  { add esp, nArgs*4 }
        EmitB($99);                                  { cdq (eax -> edx:eax) }
      end;

    IR_ATOMIC:
      begin
        { 32-bit atomic read-modify-write on addr^, mirroring the x86-64 shape
          (same opcodes minus REX). Old value in eax, widened to edx:eax for
          the node's Int64. The *64 variants need cmpxchg8b loops — rejected. }
        if (IRIVal[node] = ATOMIC_XCHG64) or (IRIVal[node] = ATOMIC_CAS64) or
           (IRIVal[node] = ATOMIC_ADD64) then
          Error('target i386: __pxxatomic_*64 not supported (32-bit target)');
        argNode := IRA[node];
        while argNode <> -1 do
        begin
          IREmitNode386(IRA[argNode]);
          EmitB($50);                                { push eax }
          argNode := IRB[argNode];
        end;
        case IRIVal[node] of
          ATOMIC_CAS:
            begin
              { stack (top..bottom): newval, expected, addr }
              EmitB($5A);                            { pop edx  (newval) }
              EmitB($58);                            { pop eax  (expected) }
              EmitB($59);                            { pop ecx  (addr) }
              EmitB($F0); EmitB($0F); EmitB($B1); EmitB($11); { lock cmpxchg [ecx], edx }
            end;                                     { eax = old *addr }
          ATOMIC_ADD:
            begin
              EmitB($58);                            { pop eax  (delta) }
              EmitB($59);                            { pop ecx  (addr) }
              EmitB($F0); EmitB($0F); EmitB($C1); EmitB($01); { lock xadd [ecx], eax }
            end;                                     { eax = old *addr }
          else { ATOMIC_XCHG }
            begin
              EmitB($58);                            { pop eax  (val) }
              EmitB($59);                            { pop ecx  (addr) }
              EmitB($87); EmitB($01);                { xchg [ecx], eax  (implicitly locked) }
            end;                                     { eax = old *addr }
        end;
        EmitB($99);                                  { cdq (eax -> edx:eax) }
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
        { Static-array / pointer / managed-string indexing. For managed strings
          in write position, clone-if-shared before returning the byte address. }
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);
        IREmitNode386(left);                          { base address -> eax }
        if (InLValueWrite and (IRKind[left] = IR_LEA) and
            Syms[IRA[left]].IsArray and (Syms[IRA[left]].ArrLen = -1)) then
        begin
          { Indexing INTO a dynamic-array symbol during a write (`g[i] := x`,
            or the base level of a nested SetLength(a[i], n)): the write-mode
            IR_LEA branch (added for a SetLength target that IS the array
            symbol itself) leaves eax one deref short of the data pointer --
            correct for THAT caller, but indexing always needs to read the
            array's own handle to use as a base; the real write happens at the
            computed element address further down. Deref once more (v1: no
            COW here either, matching the rest of this backend). }
          EmitB($8B); EmitB($00);                     { mov eax, [eax] = data ptr }
        end
        else if ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
            not Syms[IRA[left]].IsArray) or
           (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX)) and
            (IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)) then
        begin
          if InLValueWrite then
          begin
            EmitB($50);                               { push slot addr }
            procIdx := FindProc('PXXStrUnique');
            if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
            EmitCallProc(procIdx);                         { eax = unique handle }
            EmitB($81); EmitB($C4); EmitI32(4);       { add esp, 4 }
          end
          else if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].Kind = skParam) and
                  Syms[IRA[left]].IsRef then
            begin EmitB($8B); EmitB($00); end         { mov eax, [eax] (&handle -> handle) }
          else if (IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX) then
            begin EmitB($8B); EmitB($00); end;        { mov eax, [slot] = handle }
        end;
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
        if TypeIsFloat(tk) then
        begin
          if tk = tySingle then
          begin
            EmitB($F3); EmitB($0F); EmitB($10); EmitB($00);   { movss xmm0, [eax] }
            EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);   { cvtss2sd xmm0, xmm0 }
          end
          else
            begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); end; { movsd xmm0, [eax] }
          Exit;
        end;
        if (tk = tyString) or (tk = tyFixedString) or (tk = tyShortString) then
        begin
          { A frozen/inline-string value IS its buffer address. Deref'ing a
            pointer-to-frozen-string (typinfo NamePtr^) yields that address — a
            pointer-width (4-byte) load, not the TypeSize(tyString)=8 path (which
            classified it 64-bit and loaded edx:eax, diverging from x86-64).
            bug-cross-gate-masked-failures. }
          EmitB($8B); EmitB($00);                    { mov eax, [eax] (pointer width) }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass) or (tk = tyRecord)) then
          Error('target i386: load through pointer of this type not yet supported');
        if Is64Bit386(tk) or (tk = tyRecord) then
        begin
          { Full 8-byte load -> edx:eax (high dword first so the address in eax
            is still valid for the low load). tyRecord: TypeSize=8, so mirror the
            x86-64 8-byte `mov rax,[rax]` (a small by-value struct used as a
            scalar; over-read high bytes are ignored, same as x86-64). }
          EmitB($8B); EmitB($50); EmitB($04);        { mov edx, [eax+4] }
          EmitB($8B); EmitB($00);                    { mov eax, [eax] }
          Exit;
        end;
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
        if tk = tyString then
        begin
          { Frozen inline-string store through a pointer (e.g. PString(p)^ := s):
            copy the 8-byte length prefix, then rep movsb the `length` chars.
            Mirrors the x86-64 path. }
          valNode := IRB[node];
          IREmitNode386(valNode);                     { eax = source string addr }
          EmitB($50);                                 { push eax (source) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode386(IRA[node]);                   { eax = dest addr }
          InLValueWrite := savedLValueWrite;
          EmitB($89); EmitB($C7);                     { mov edi, eax }
          EmitB($5E);                                 { pop esi }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
            Error('target i386: char-to-inline-string store through pointer not yet supported');
          EmitB($8B); EmitB($0E);                     { mov ecx, [esi] (len lo) }
          EmitB($89); EmitB($0F);                     { mov [edi], ecx }
          EmitB($8B); EmitB($4E); EmitB($04);         { mov ecx, [esi+4] (len hi) }
          EmitB($89); EmitB($4F); EmitB($04);         { mov [edi+4], ecx }
          EmitB($8B); EmitB($0E);                     { mov ecx, [esi] (count) }
          EmitB($83); EmitB($C6); EmitB($08);         { add esi, 8 }
          EmitB($83); EmitB($C7); EmitB($08);         { add edi, 8 }
          EmitB($F3); EmitB($A4);                     { rep movsb }
          Exit;
        end;
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
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(8);         { add esp, 8 }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNode386(valNode);                     { eax = char code }
            EmitB($50);                                 { push eax (char code) }
            EmitB($6A); EmitB($01);                     { push 1 (len) }
            EmitB($8D); EmitB($44); EmitB($24); EmitB($04); { lea eax, [esp+4] (ptr to char code) }
            EmitB($50);                                 { push eax (src) }
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
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
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);
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
              procIdx := FindProc('PXXStrIncRef');
              if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
              EmitCallProc(procIdx);
              EmitB($58);                               { pop eax (restore handle) }
            end;
          end;
          EmitB($50);                                   { push eax (new handle) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode386(IRA[node]);                     { eax = slot address }
          InLValueWrite := savedLValueWrite;
          EmitB($89); EmitB($C7);                       { mov edi, eax }
          EmitB($8B); EmitB($37);                       { mov esi, [edi] (old) }
          EmitB($8B); EmitB($04); EmitB($24);           { mov eax, [esp] (new) }
          EmitB($89); EmitB($07);                       { mov [edi], eax }
          EmitB($89); EmitB($F0);                       { mov eax, esi (old) }
          procIdx := FindProc('PXXStrDecRef');
          if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
          EmitB($50);                                   { push eax (arg0 = old) }
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(4);           { add esp, 4 }
          EmitB($58);                                   { pop eax (new, discard) }
          Exit;
        end;
        if TypeIsFloat(tk) then
        begin
          IREmitNode386(IRB[node]);                  { value -> xmm0 }
          if not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
            begin EmitB($F2); EmitB($0F); EmitB($2A); EmitB($C0); end;   { cvtsi2sd xmm0, eax }
          EmitFloatSpill386;
          IREmitNode386(IRA[node]);                  { address -> eax }
          EmitFloatUnspill386;
          if tk = tySingle then
          begin
            EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);              { cvtsd2ss xmm0, xmm0 }
            EmitB($F3); EmitB($0F); EmitB($11); EmitB($00);              { movss [eax], xmm0 }
          end
          else
            begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($00); end;   { movsd [eax], xmm0 }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyClass) or (tk = tyUnknown)) then
          Error('target i386: store through pointer of this type not yet supported');
        if Is64Bit386(tk) then
        begin
          EmitNode64_386(IRB[node]);                 { value -> edx:eax }
          EmitB($52);                                { push edx (value hi) }
          EmitB($50);                                { push eax (value lo) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode386(IRA[node]);                  { address -> eax }
          InLValueWrite := savedLValueWrite;
          EmitB($59);                                { pop ecx (value lo) }
          EmitB($5A);                                { pop edx (value hi) }
          EmitB($89); EmitB($08);                    { mov [eax], ecx }
          EmitB($89); EmitB($50); EmitB($04);        { mov [eax+4], edx }
          Exit;
        end;
        IREmitNode386(IRB[node]);                    { value -> eax (or xmm0 if float) }
        { C double->int: a float RHS (in xmm0) into an integer field/element
          truncates (cvttsd2si) before the store. Mirrors IR_STORE_SYM. }
        if CProgramMode and TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
          begin EmitB($F2); EmitB($0F); EmitB($2C); EmitB($C0); end;   { cvttsd2si eax, xmm0 }
        EmitB($50);                                  { push eax }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := True;
        IREmitNode386(IRA[node]);                    { address -> eax }
        InLValueWrite := savedLValueWrite;
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
        procIdx := FindProc('PXXRecordRetain');
        if procIdx < 0 then Error('compiler error: PXXRecordRetain not found');
        EmitB($8B); EmitB($44); EmitB($24); EmitB($04); { mov eax, [esp+4] (src) }
        EmitB($50);                                  { push eax (arg0 recAddr) }
        EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
        EmitCallProc(procIdx);
        EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
        procIdx := FindProc('PXXRecordRelease');
        if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
        EmitB($8B); EmitB($04); EmitB($24);          { mov eax, [esp] (dest) }
        EmitB($50);                                  { push eax (arg0 recAddr) }
        EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
        EmitCallProc(procIdx);
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
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitB($8B); EmitB($04); EmitB($24);        { mov eax, [esp] (dest) }
          EmitB($50);                                { push eax (arg0) }
          EmitB($68); EmitDataRef(-(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE))); { push desc }
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);        { add esp, 8 }
          EmitB($5F);                                { pop edi (dest) }
        end
        else
          begin EmitB($89); EmitB($C7); end;         { mov edi, eax }
        EmitB($31); EmitB($C0);                      { xor eax, eax }
        EmitB($B9); EmitI32(IRIVal[node]);           { mov ecx, count }
        EmitB($F3); EmitB($AA);                      { rep stosb }
      end;

    IR_CLASSREF:
      begin EmitB($B8); EmitDataRef(-(CLASSREF_DATAREF_BASE + IRA[node])); end; { mov eax, class RTTI blob addr }

    IR_VMTADDR:
      begin EmitB($B8); EmitDataRef(UClsVMTOffset[IRA[node]]); end; { mov eax, class VMT addr (is/as identity) }

    IR_IMTADDR:
      begin EmitB($B8); EmitDataRef(IMTOff[IRA[node]]); end; { mov eax, interface method table addr }

    IR_SET_LIT:
      begin EmitB($B8); EmitDataRef(IRIVal[node]); end;   { mov eax, set-literal blob addr }

    IR_SET_COPY:
      begin
        { Copy the full 32-byte set from src (IRB) to dest (IRA). }
        IREmitNode386(IRB[node]);                    { eax = source addr }
        EmitB($50);                                  { push src }
        IREmitNode386(IRA[node]);                    { eax = dest addr }
        EmitB($89); EmitB($C7);                      { mov edi, eax }
        EmitB($5E);                                  { pop esi }
        EmitB($B9); EmitI32(32);                     { mov ecx, 32 }
        EmitB($F3); EmitB($A4);                      { rep movsb }
      end;

    IR_SET_BINOP:
      begin
        { Set +/-/* over 32 bytes = 8 dwords, into the BSS scratch (IRIVal).
          eax holds [lhs+i], ecx holds [rhs+i]; result -> [scratch+i]. }
        IREmitNode386(IRA[node]);                    { lhs addr }
        EmitB($50);                                  { push lhs }
        IREmitNode386(IRB[node]);                    { eax = rhs addr }
        EmitB($89); EmitB($C6);                      { mov esi, eax (rhs) }
        EmitB($5A);                                  { pop edx (lhs) }
        EmitB($BF); EmitGlobRef(IRIVal[node]);       { mov edi, scratch }
        for i := 0 to 7 do
        begin
          EmitB($8B); EmitB($42); EmitB(i * 4);      { mov eax, [edx+i*4] (lhs) }
          EmitB($8B); EmitB($4E); EmitB(i * 4);      { mov ecx, [esi+i*4] (rhs) }
          if IntToTokenKind(IRC[node]) = tkMinus then
          begin
            EmitB($F7); EmitB($D1);                  { not ecx }
            EmitB($21); EmitB($C8);                  { and eax, ecx }
          end
          else if IntToTokenKind(IRC[node]) = tkPlus then
            begin EmitB($09); EmitB($C8); end        { or eax, ecx }
          else if IntToTokenKind(IRC[node]) = tkStar then
            begin EmitB($21); EmitB($C8); end;       { and eax, ecx }
          EmitB($89); EmitB($47); EmitB(i * 4);      { mov [edi+i*4], eax }
        end;
        EmitB($B8); EmitGlobRef(IRIVal[node]);       { mov eax, scratch (result addr) }
      end;

    IR_SET_CMP:
      begin
        { Compare two 32-byte sets (8 dwords). ebx accumulates subset
          violations, edx accumulates differences (any set bit => unequal). }
        EmitB($53);                                  { push ebx }
        IREmitNode386(IRA[node]);                    { lhs addr }
        EmitB($50);                                  { push lhs }
        IREmitNode386(IRB[node]);                    { eax = rhs addr }
        EmitB($89); EmitB($C6);                      { mov esi, eax (rhs) }
        EmitB($5F);                                  { pop edi (lhs) }
        EmitB($31); EmitB($DB);                      { xor ebx, ebx (violations) }
        EmitB($31); EmitB($D2);                      { xor edx, edx (differences) }
        for i := 0 to 7 do
        begin
          EmitB($8B); EmitB($47); EmitB(i * 4);      { mov eax, [edi+i*4] (lhs) }
          EmitB($8B); EmitB($4E); EmitB(i * 4);      { mov ecx, [esi+i*4] (rhs) }
          { differences: edx |= (lhs xor rhs) — preserve the lhs dword in eax }
          EmitB($50);                                { push eax (save lhs dword) }
          EmitB($31); EmitB($C8);                    { xor eax, ecx }
          EmitB($09); EmitB($C2);                    { or edx, eax }
          EmitB($58);                                { pop eax (lhs dword) }
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            { lhs subset of rhs: lhs and not rhs must be 0 }
            EmitB($F7); EmitB($D1);                  { not ecx }
            EmitB($21); EmitB($C8);                  { and eax, ecx }
            EmitB($09); EmitB($C3);                  { or ebx, eax }
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            { rhs subset of lhs: rhs and not lhs must be 0 }
            EmitB($F7); EmitB($D0);                  { not eax }
            EmitB($21); EmitB($C1);                  { and ecx, eax }
            EmitB($09); EmitB($CB);                  { or ebx, ecx }
          end;
        end;
        { Build the Boolean result in eax from edx (differences) / ebx (viol). }
        if IRC[node] = Ord(tkEq) then
        begin
          EmitB($85); EmitB($D2);                    { test edx, edx }
          EmitB($0F); EmitB($94); EmitB($C0);        { sete al }
        end
        else if IRC[node] = Ord(tkNeq) then
        begin
          EmitB($85); EmitB($D2);                    { test edx, edx }
          EmitB($0F); EmitB($95); EmitB($C0);        { setne al }
        end
        else if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkGe)) then
        begin
          EmitB($85); EmitB($DB);                    { test ebx, ebx }
          EmitB($0F); EmitB($94); EmitB($C0);        { sete al (subset/superset) }
        end
        else { tkLt / tkGt: proper subset = subset AND unequal }
        begin
          EmitB($85); EmitB($DB);                    { test ebx, ebx }
          EmitB($0F); EmitB($94); EmitB($C0);        { sete al }
          EmitB($85); EmitB($D2);                    { test edx, edx }
          EmitB($0F); EmitB($95); EmitB($C1);        { setne cl }
          EmitB($20); EmitB($C8);                    { and al, cl }
        end;
        EmitB($0F); EmitB($B6); EmitB($C0);          { movzx eax, al }
        EmitB($5B);                                  { pop ebx }
      end;

    IR_RTTI_REG:
      begin EmitB($B8); EmitDataRef(-100); end;   { mov eax, RTTI-registry addr }

    IR_RESOURCES:
      begin EmitB($B8); EmitDataRef(-101); end;   { mov eax, resource-table addr }

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
        { i386 syscalls return a 32-bit value in eax. When the result is
          consumed as Int64/UInt64 (e.g. __pxxrawsyscall -> Int64), the edx:eax
          pair must be a valid 64-bit value matching x86-64 semantics: kernel
          error returns (-4095..-1, i.e. unsigned > 0xFFFFF000) sign-extend to a
          negative Int64; everything else (including high mmap addresses with
          bit31 set) zero-extends to a positive value. edx is dead after the
          trap, so this is unconditional (harmless for 32-bit consumers). }
        EmitB($3D); EmitI32(Integer($FFFFF000));    { cmp eax, 0xFFFFF000 }
        EmitB($77); EmitB($04);                     { ja .err (unsigned: error range) }
        EmitB($31); EmitB($D2);                     { xor edx, edx (zero-extend) }
        EmitB($EB); EmitB($02);                     { jmp .done }
        EmitB($99);                                 { .err: cdq (sign-extend) }
        EmitB($90);                                 { .done: nop (pad to jmp target) }
      end;

    IR_NEG:
      begin
        IREmitNode386(IRA[node]);
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          { flip the sign bit: xmm0 ^= 0x8000000000000000 }
          EmitB($68); EmitI32(Integer($80000000));   { push hi }
          EmitB($6A); EmitB($00);                    { push 0 (lo) }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($0C); EmitB($24);  { movsd xmm1, [esp] }
          EmitB($83); EmitB($C4); EmitB($08);        { add esp, 8 }
          EmitB($66); EmitB($0F); EmitB($57); EmitB($C1);              { xorpd xmm0, xmm1 }
        end
        else if Is64Bit386(IntToTypeKind(IRTk[node])) then
        begin
          { negate edx:eax: neg eax; adc edx,0; neg edx }
          EmitB($F7); EmitB($D8);                    { neg eax }
          EmitB($83); EmitB($D2); EmitB($00);        { adc edx, 0 }
          EmitB($F7); EmitB($DA);                    { neg edx }
        end
        else
          begin EmitB($F7); EmitB($D8); end;         { neg eax }
      end;

    IR_NOT:
      begin
        IREmitNode386(IRA[node]);
        if Is64Bit386(IntToTypeKind(IRTk[node])) then
        begin
          EmitB($F7); EmitB($D0);                    { not eax }
          EmitB($F7); EmitB($D2);                    { not edx }
        end
        else if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
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
          if IRC[node] = -3 then
          begin
            { write(PChar): runtime NUL-terminated C string (strlen + write). }
            IREmitNode386(valNode);
            EmitWriteCStr386;
          end
          else if tk = tyVariant then
          begin
            EmitLoadVariantAddr386(valNode);             { eax = slot addr }
            EmitB($50);                                  { push eax (arg0 = v) }
            procIdx := FindProc('PXXWriteVariant');
            if procIdx < 0 then Error('compiler error: PXXWriteVariant not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(4);          { add esp, 4 }
          end
          else if TypeIsFloat(tk) then
          begin
            IREmitNode386(valNode);                      { value -> xmm0 }
            j := IRC[node];                              { decimals }
            if j = -2 then EmitFloatCallWriter386('PXXWriteFloatNat', -1)
            else if j >= 0 then EmitFloatCallWriter386('PXXWriteFloatFixed', j)
            else EmitFloatCallWriter386('PXXWriteFloatSci', -1);
          end
          else if tk = tyChar then
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
          else if Is64Bit386(tk) then
          begin
            { 64-bit decimal. Field-width padding for 64-bit values is not yet
              wired; emit the plain form. }
            IREmitNode386(valNode);                  { edx:eax = value }
            if tk = tyUInt64 then EmitwriteUInt64_386
            else EmitwriteInt64_386;
          end
          else if TypeIsOrdinal(tk) or (tk = tyUnknown) then
          begin
            IREmitNode386(valNode);
            if (tk <> tyUnknown) and not TypeSigned(tk) then
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
              procIdx := FindProc('PXXStrDecRef');
              if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
              EmitCallProc(procIdx);
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

    IR_VAR_STORE:
      begin
        { IRA = dest addr, IRB = value/src addr, IRC = source TTypeKind ord. }
        tk := IntToTypeKind(IRC[node]);
        if tk = tyVariant then
        begin
          { ARC-correct 16-byte variant-to-variant copy (retain before
            release makes self-assignment safe). }
          EmitLoadVariantAddr386(IRB[node]);         { eax = src addr }
          EmitVarHelperCall386('PXXVarRetain');
          EmitB($50);                                { push src addr }
          IREmitNode386(IRA[node]);                  { eax = dest addr }
          EmitVarHelperCall386('PXXVarClear');
          EmitB($89); EmitB($C7);                    { mov edi, eax }
          EmitB($5E);                                { pop esi (src) }
          EmitB($B9); EmitI32(16);                   { mov ecx, 16 }
          EmitB($F3); EmitB($A4);                    { rep movsb }
        end
        else
        begin
          j := VariantTagForTk386(tk, 'Variant :=');
          if tk = tyString then
          begin
            IREmitNode386(IRB[node]);                { eax = inline string buffer }
            EmitB($50);                              { push eax }
            EmitB($8B); EmitB($08);                  { mov ecx, [eax] (len) }
            EmitB($83); EmitB($C0); EmitB($08);      { add eax, 8 (src) }
            EmitB($51);                              { push ecx (len) }
            EmitB($50);                              { push eax (src) }
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);                        { eax = new AnsiString }
            EmitB($81); EmitB($C4); EmitI32(8);      { add esp, 8 }
            EmitB($59);                              { pop ecx (drop buffer) }
            EmitB($50);                              { push payload }
          end
          else if tk = tyAnsiString then
          begin
            IREmitNode386(IRB[node]);                { eax = handle }
            EmitB($50);                              { push eax (arg0) }
            procIdx := FindProc('PXXStrIncRef');
            if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
            EmitCallProc(procIdx);
            EmitB($58);                              { pop eax }
            EmitB($50);                              { push payload }
          end
          else
          begin
            IREmitNode386(IRB[node]);                { scalar -> eax / double -> xmm0 }
            if TypeIsFloat(tk) then
              EmitFloatSpill386                      { 8-byte payload on the stack }
            else
              EmitB($50);                            { push payload }
          end;
          IREmitNode386(IRA[node]);                  { eax = dest addr }
          EmitVariantFill386(j, tk);
        end;
      end;

    IR_VAR_BOX:
      begin
        { Box a scalar into a temp variant (IRA = temp addr); addr -> eax. }
        tk := IntToTypeKind(IRC[node]);
        j := VariantTagForTk386(tk, 'Variant operand');
        if tk = tyString then
        begin
          IREmitNode386(IRB[node]);                  { eax = inline string buffer }
          EmitB($50);
          EmitB($8B); EmitB($08);                    { mov ecx, [eax] (len) }
          EmitB($83); EmitB($C0); EmitB($08);        { add eax, 8 (src) }
          EmitB($51);                                { push ecx (len) }
          EmitB($50);                                { push eax (src) }
          procIdx := FindProc('PXXStrFromLit');
          if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);
          EmitB($59);                                { pop ecx (drop buffer) }
          EmitB($50);                                { push payload }
        end
        else if tk = tyAnsiString then
        begin
          IREmitNode386(IRB[node]);
          EmitB($50);
          procIdx := FindProc('PXXStrIncRef');
          if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
          EmitCallProc(procIdx);
          EmitB($58);
          EmitB($50);                                { push payload }
        end
        else
        begin
          IREmitNode386(IRB[node]);
          if TypeIsFloat(tk) then
            EmitFloatSpill386
          else
            EmitB($50);                              { push payload }
        end;
        IREmitNode386(IRA[node]);                    { eax = temp addr }
        EmitVariantFill386(j, tk);                   { leaves addr in eax }
      end;

    IR_VAR_BINOP:
      begin
        { PXXVarBinOp(dest, left, right, opTk, isCompare); compare -> 0/1 in
          eax, arithmetic -> dest addr in eax. }
        sgn := IntToTypeKind(IRTk[node]) = tyBoolean;
        IREmitNode386(IRA[node]); EmitB($50);        { push left addr }
        IREmitNode386(IRB[node]); EmitB($50);        { push right addr }
        if sgn then
          begin EmitB($6A); EmitB($00); end          { push 0 (dest unused) }
        else
          begin EmitB($68); EmitGlobRef(Integer(IRIVal[node])); end; { push dest temp }
        EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov eax, [esp+8] (left) }
        EmitB($50);
        EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov eax, [esp+8] (right) }
        EmitB($50);
        EmitB($68); EmitI32(IRC[node]);              { push opTk }
        if sgn then
          begin EmitB($6A); EmitB($01); end          { push isCompare=1 }
        else
          begin EmitB($6A); EmitB($00); end;
        procIdx := FindProc('PXXVarBinOp');
        if procIdx < 0 then Error('compiler error: PXXVarBinOp not found');
        EmitCallProc(procIdx);
        EmitB($81); EmitB($C4); EmitI32(28);         { 5 args + 2 saved evals }
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
var i, lblId, pos, targetOffset, f, si, classIdx, sz, procIdx: Integer;
    tk: TTypeKind;
    LabelFixupCount: Integer;
begin
  { Clear only this body's labels ([0, IRLabelCount) — see IREmitMachineCode). }
  for i := 0 to IRLabelCount - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  { Nil-init hidden owning locals synthesised for materialised managed-string
    arguments. They are created during this body's IR lowering, after the
    parser's prologue zero-init pass, so they would otherwise hold stale stack
    bytes; an early-exit cleanup would then DecRef garbage and segfault.
    Main-program temps are skGlobal (BSS, already zeroed); only skLocal needs
    it. Mirrors the x86-64 path in IREmitMachineCode. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(Syms[i].RecName) > TARGET_PTR_SIZE) then
        begin
          { Managed-record temp: zero the full record (PXXMemZero) so every
            managed field starts nil, not just the first pointer-sized slot. }
          EmitB($8D); EmitB($85); EmitI32(Syms[i].Offset);          { lea eax, [ebp+off] }
          EmitB($50);                                               { push dest }
          EmitB($68); EmitI32(RecSize(Syms[i].RecName));            { push count }
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitCallProc(procIdx);
          EmitB($81); EmitB($C4); EmitI32(8);                       { add esp, 8 }
        end
        else
          begin EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0); end; { mov dword [ebp+off], 0 }
      end;

  for i := 0 to IRCount - 1 do
  begin
    DbgRecordRow(i);   { DWARF -g line table }
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
          IREmitNode386(IRB[i]);                     { condition -> eax (edx:eax if 64-bit) }
          { A 64-bit condition lives in edx:eax, so `test eax, eax` alone ignores the
            HIGH half: any nonzero value whose low dword happens to be zero (e.g.
            0xabcd00000000) tested as FALSE. `while (v)` / `if (v)` / `(v) ? :` all
            route through here, so this silently mis-branched — and crtl's printf
            hit it, which is how it surfaced (bug-32bit-truthiness-high-half).
            `or eax, edx` sets ZF iff BOTH halves are zero. }
          if Is64Bit386(IntToTypeKind(IRTk[IRB[i]])) then
          begin
            EmitB($09); EmitB($D0);                  { or eax, edx }
          end;
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

      IR_CALL_IND:
        begin
          if IRStmtRoot[i] then                      { statement-level indirect call }
            IREmitNode386(i);
        end;

      IR_VIRTUAL_CALL:
        begin
          if IRStmtRoot[i] then                      { statement-level virtual call }
            IREmitNode386(i);
        end;

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE_386); { sub esp, 32 }
          EmitB($A1); EmitGlobRef(BSS_EXC_TOP);                { mov eax, [BSS_EXC_TOP] }
          EmitB($89); EmitB($04); EmitB($24);                  { mov [esp], eax }
          EmitB($89); EmitB($E0);                              { mov eax, esp }
          EmitB($A3); EmitGlobRef(BSS_EXC_TOP);                { mov [BSS_EXC_TOP], eax }
          EmitB($8D); EmitB($44); EmitB($24); EmitB(EXC_JMP_OFFSET_386); { lea eax, [esp+EXC_JMP_OFFSET_386] }
          EmitB($E8); EmitI32(ExcSetJmpAddr - (CodeLen + 4));  { call ExcSetJmpAddr }
          EmitB($85); EmitB($C0);                              { test eax, eax }
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);                            { jnz rel32 }
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_LEAVE:
        begin
          IREmitLeaveExceptionFrames386(IRA[i]);
        end;

      IR_RAISE:
        begin
          if IRA[i] <> -1 then
          begin
            IREmitNode386(IRA[i]);
            EmitB($A3); EmitGlobRef(BSS_EXC_OBJ);
            classIdx := Integer(IRIVal[i]);
            EmitB($B8); EmitI32(classIdx);
            EmitB($A3); EmitGlobRef(BSS_EXC_CLS);
          end;
          EmitB($E8); EmitI32(ExcRaiseAddr - (CodeLen + 4));
        end;

      IR_EXC_STORE:
        begin
          si := IRA[i];
          tk := Syms[si].TypeKind;
          sz := TypeSize(tk);
          EmitB($A1); EmitGlobRef(BSS_EXC_OBJ); { mov eax, [BSS_EXC_OBJ] }
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
            if sz = 1 then
              begin EmitB($88); EmitB($85); EmitI32(Syms[si].Offset); end
            else if sz = 2 then
              begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end
            else
              begin EmitB($89); EmitB($85); EmitI32(Syms[si].Offset); end;
          end;
        end;

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitB($A1); EmitGlobRef(BSS_EXC_CLS); { mov eax, [BSS_EXC_CLS] }
          EmitB($3D); EmitI32(Integer(IRIVal[i])); { cmp eax, imm32 }
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);                            { jnz rel32 }
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_MATCH_HIT:
        begin
          lblId := IRA[i];
          EmitB($A1); EmitGlobRef(BSS_EXC_CLS); { mov eax, [BSS_EXC_CLS] }
          EmitB($3D); EmitI32(Integer(IRIVal[i])); { cmp eax, imm32 }
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($84);                            { jz rel32 }
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($84);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_CLEAR:
        begin
          EmitB($31); EmitB($C0); { xor eax, eax }
          EmitB($A3); EmitGlobRef(BSS_EXC_OBJ);
          EmitB($A3); EmitGlobRef(BSS_EXC_CLS);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNode386(i);

      IR_ZERO_SYM:
        begin
          { Nil-init a managed local so an early-exit / epilogue cleanup never
            DecRefs stale stack bytes. Scalars (and dyn-array handles) are one
            pointer; arrays of AnsiString / records-with-managed-fields zero the
            whole span. Mirrors the x86-64 IR_ZERO_SYM path. }
          si := IRA[i];
          if (Syms[si].Kind = skLocal) and SymNeedsZeroing(si, sz) then
          begin
            if sz = TARGET_PTR_SIZE then
              begin EmitB($C7); EmitB($85); EmitI32(Syms[si].Offset); EmitI32(0); end { mov dword [ebp+off], 0 }
            else if sz > 0 then
            begin
              EmitB($8D); EmitB($BD); EmitI32(Syms[si].Offset);  { lea edi, [ebp+off] }
              EmitB($31); EmitB($C0);                            { xor eax, eax }
              EmitB($B9); EmitI32(sz);                           { mov ecx, sz }
              EmitB($F3); EmitB($AA);                            { rep stosb }
            end;
          end;
        end;

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_LOAD_MEM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP,
      IR_ATOMIC, IR_CLONE, IR_CONST_DATA, { value-producing: emitted by the consuming store, like x86-64 }
      IR_SLOTADDR, IR_DYNUNIQUE, IR_FIELD, IR_INDEX: ; { operands, emitted by parents }
      { IR_LOAD_MEM: pure value node — statement-level emit re-runs its address
        operand (`*f()` calls f twice). See aarch64 note. }

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
