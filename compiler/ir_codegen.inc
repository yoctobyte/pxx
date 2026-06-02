{ ===== Experimental IR Machine Code Generator ===== }

procedure IREmitCodeCall(addr: Integer);
begin
  EmitB($E8);
  EmitI32(addr - (CodeLen + 4));
end;

procedure EmitAcquireHeapLock;
var start: Integer;
begin
  if ThreadSafeMode then
  begin
    start := CodeLen;
    EmitB($B8); EmitI32(1);                         { mov eax, 1 }
    EmitB($F0); EmitB($87); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_LOCK); { lock xchg [BSS_HEAP_LOCK], eax }
    EmitB($85); EmitB($C0);                         { test eax, eax }
    EmitB($75); EmitB(Byte(start - (CodeLen + 1))); { jnz start }
  end;
end;

procedure EmitReleaseHeapLock;
begin
  if ThreadSafeMode then
  begin
    EmitB($C7); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_LOCK); EmitI32(0); { mov dword [BSS_HEAP_LOCK], 0 }
  end;
end;

procedure EmitHeapAllocLocked;
{ rax = requested payload bytes. Returns payload pointer in rax. Caller holds
  the heap lock when threading is enabled. Uses the GetMem block layout:
  [size:8][payload...]. }
var searchTop, pJzBump, pJaeTake, pJmpDone, pJbeNoGrow: Integer;
begin
  EmitB($53);                                     { push rbx }
  EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
  EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($08); { cmp rax, 8 }
  EmitB($73); EmitB($05);                         { jae +5 }
  EmitB($B8); EmitI32(8);                         { mov eax, 8 }
  EmitB($48); EmitB($89); EmitB($C1);             { mov rcx, rax }

  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { lea rsi, [FREE_LIST] }
  searchTop := CodeLen;
  EmitB($48); EmitB($8B); EmitB($16);             { mov rdx, [rsi] }
  EmitB($48); EmitB($85); EmitB($D2);             { test rdx, rdx }
  EmitB($74); pJzBump := CodeLen; EmitB(0);       { jz BUMP }
  EmitB($48); EmitB($8B); EmitB($42); EmitB($F8); { mov rax, [rdx-8] }
  EmitB($48); EmitB($39); EmitB($C8);             { cmp rax, rcx }
  EmitB($73); pJaeTake := CodeLen; EmitB(0);      { jae TAKE }
  EmitB($48); EmitB($89); EmitB($D6);             { mov rsi, rdx }
  EmitB($EB); EmitB(Byte(searchTop - (CodeLen + 1)));

  Code[pJaeTake] := Byte(CodeLen - (pJaeTake + 1));
  EmitB($48); EmitB($8B); EmitB($02);             { mov rax, [rdx] }
  EmitB($48); EmitB($89); EmitB($06);             { mov [rsi], rax }
  EmitB($48); EmitB($89); EmitB($D0);             { mov rax, rdx }
  EmitB($E9); pJmpDone := CodeLen; EmitI32(0);

  Code[pJzBump] := Byte(CodeLen - (pJzBump + 1));
  EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov rbx, [HEAP_PTR] }
  EmitB($48); EmitB($89); EmitB($D8);             { mov rax, rbx }
  EmitB($48); EmitB($01); EmitB($C8);             { add rax, rcx }
  EmitB($48); EmitB($83); EmitB($C0); EmitB($08); { add rax, 8 }
  EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  EmitB($0F); EmitB($86); pJbeNoGrow := CodeLen; EmitI32(0);

  EmitB($48); EmitB($89); EmitB($CE);             { mov rsi, rcx }
  EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
  EmitB($48); EmitB($81); EmitB($C6); EmitI32(HEAP_ARENA_SIZE);
  EmitB($51);                                     { push rcx }
  EmitMmapArena;
  EmitB($59);                                     { pop rcx }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  EmitB($48); EmitB($89); EmitB($C3);             { mov rbx, rax }
  EmitB($48); EmitB($89); EmitB($C2);             { mov rdx, rax }
  EmitB($48); EmitB($01); EmitB($F2);             { add rdx, rsi }
  EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_END);

  Patch32(pJbeNoGrow, CodeLen - (pJbeNoGrow + 4));
  EmitB($48); EmitB($89); EmitB($0B);             { mov [rbx], rcx }
  EmitB($48); EmitB($8D); EmitB($43); EmitB($08); { lea rax, [rbx+8] }
  EmitB($48); EmitB($89); EmitB($DA);             { mov rdx, rbx }
  EmitB($48); EmitB($01); EmitB($CA);             { add rdx, rcx }
  EmitB($48); EmitB($83); EmitB($C2); EmitB($08); { add rdx, 8 }
  EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);

  Patch32(pJmpDone, CodeLen - (pJmpDone + 4));
  EmitB($5B);                                     { pop rbx }
end;

procedure EmitHeapFreeLocked;
{ rax = payload pointer from EmitHeapAllocLocked/GetMem. Caller holds the heap
  lock when threading is enabled. nil is ignored. }
var pNil: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
  EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
  EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(BSS_FREE_LIST);
  EmitB($48); EmitB($89); EmitB($10);             { mov [rax], rdx }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_FREE_LIST);
  Code[pNil] := Byte(CodeLen - (pNil + 1));
end;

procedure EmitDynArrayRetain;
{ rax = dynamic-array data pointer. Preserve rax. }
var pNil: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
  EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
  if ThreadSafeMode then EmitB($F0);               { lock }
  EmitB($48); EmitB($FF); EmitB($40); EmitB($F0); { inc qword [rax-16] }
  Code[pNil] := Byte(CodeLen - (pNil + 1));
end;

procedure EmitDynArrayReleaseLocked;
{ rax = dynamic-array data pointer. Decrement its refcount and return the
  allocator payload to the free list at zero. Caller holds the heap lock when
  threading is enabled. }
var pNil, pNonZero: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
  EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
  if ThreadSafeMode then EmitB($F0);               { lock }
  EmitB($48); EmitB($FF); EmitB($48); EmitB($F0); { dec qword [rax-16] }
  EmitB($75); pNonZero := CodeLen; EmitB(0);      { jnz done }
  EmitB($48); EmitB($83); EmitB($E8); EmitB($10); { sub rax, 16 }
  EmitHeapFreeLocked;
  Code[pNil] := Byte(CodeLen - (pNil + 1));
  Code[pNonZero] := Byte(CodeLen - (pNonZero + 1));
end;

procedure EmitDynArrayRelease;
begin
  EmitAcquireHeapLock;
  EmitDynArrayReleaseLocked;
  EmitReleaseHeapLock;
end;

procedure IREmitLeaveExceptionFrames(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24); { mov rax, [rsp] }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE);
  end;
end;

procedure IREmitStoreCharAsString;
{ rdi = destination string buffer, rsi = char ordinal. Writes a 1-char string
  ([len:8=1][char]) directly into the destination, so a tyChar value can be
  assigned to a tyString slot. No allocation — the target buffer already exists.}
begin
  EmitB($48); EmitB($C7); EmitB($07); EmitI32(1); { mov qword [rdi], 1 }
  EmitB($40); EmitB($88); EmitB($77); EmitB($08); { mov byte [rdi+8], sil }
end;

procedure EmitReadLine;
{ Read one line from stdin (fd 0) into BSS_LINE_BUF, byte at a time, stopping at
  '\n' or EOF; '\r' is skipped. Sets BSS_LINE_LEN, resets BSS_LINE_POS. }
var loopStart, j1, j2: Integer;
begin
  EmitB($48); EmitB($C7); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_POS); EmitI32(0); { mov q[pos],0 }
  EmitB($48); EmitB($C7); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN); EmitI32(0); { mov q[len],0 }
  loopStart := CodeLen;
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_LINE_BUF);   { lea rsi,[buf] }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN);   { mov rax,[len] }
  EmitB($48); EmitB($01); EmitB($C6);                                          { add rsi,rax }
  MovRdiImm(0); MovRdxImm(1); MovRaxImm(SYS_READ); EmitSyscall;
  EmitB($48); EmitB($85); EmitB($C0);                                          { test rax,rax }
  EmitB($0F); EmitB($8E); j1 := CodeLen; EmitI32(0);                           { jle done }
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($0E);                              { movzx rcx,byte[rsi] }
  EmitB($48); EmitB($83); EmitB($F9); EmitB($0D);                              { cmp rcx,13 }
  EmitB($0F); EmitB($84); EmitI32(loopStart - (CodeLen + 4));                  { je loopStart (skip \r) }
  EmitB($48); EmitB($83); EmitB($F9); EmitB($0A);                              { cmp rcx,10 }
  EmitB($0F); EmitB($84); j2 := CodeLen; EmitI32(0);                           { je done (\n) }
  EmitB($48); EmitB($FF); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN);   { inc q[len] }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN);   { mov rax,[len] }
  EmitB($48); EmitB($3D); EmitI32(LINE_BUF_SIZE - 1);                          { cmp rax,BUFSIZE-1 }
  EmitB($0F); EmitB($8C); EmitI32(loopStart - (CodeLen + 4));                  { jl loopStart }
  Patch32(j1, CodeLen - (j1 + 4));
  Patch32(j2, CodeLen - (j2 + 4));
end;

procedure EmitReadVarParse(tk: TTypeKind);
{ rax = target address on entry. Parse a value from the line buffer at the
  cursor by type and store it; advance the cursor. tyString takes the rest of
  the line; tyChar one byte; integer kinds skip blanks then read [-]digits. }
var sz, skipLoop, digLoop, jDone, jStart, jAdv, jDigits, jNoSign: Integer;
    jEmpty, jSign, jDigEnd, jLt, jGt: Integer;
begin
  if tk = tyString then
  begin
    EmitB($48); EmitB($89); EmitB($C7);                                          { mov rdi,rax }
    EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_LINE_LEN);    { mov rcx,[len] }
    EmitB($48); EmitB($2B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_LINE_POS);    { sub rcx,[pos] }
    EmitB($48); EmitB($89); EmitB($0F);                                          { mov [rdi],rcx }
    EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_LINE_BUF);    { lea rsi,[buf] }
    EmitB($48); EmitB($03); EmitB($34); EmitB($25); EmitGlobRef(BSS_LINE_POS);    { add rsi,[pos] }
    EmitB($48); EmitB($83); EmitB($C7); EmitB($08);                              { add rdi,8 }
    EmitB($F3); EmitB($A4);                                                      { rep movsb }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN);    { mov rax,[len] }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_POS);    { mov [pos],rax }
    Exit;
  end;
  if tk = tyChar then
  begin
    EmitB($48); EmitB($89); EmitB($C7);                                          { mov rdi,rax }
    EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(BSS_LINE_POS);    { mov rdx,[pos] }
    EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_LINE_LEN);    { mov rcx,[len] }
    EmitB($31); EmitB($C0);                                                      { xor eax,eax }
    EmitB($48); EmitB($39); EmitB($CA);                                          { cmp rdx,rcx }
    EmitB($0F); EmitB($8D); jDone := CodeLen; EmitI32(0);                         { jge nochar }
    EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_LINE_BUF);    { lea rsi,[buf] }
    EmitB($48); EmitB($01); EmitB($D6);                                          { add rsi,rdx }
    EmitB($48); EmitB($0F); EmitB($B6); EmitB($06);                              { movzx rax,byte[rsi] }
    EmitB($48); EmitB($FF); EmitB($C2);                                          { inc rdx }
    EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_LINE_POS);    { mov [pos],rdx }
    Patch32(jDone, CodeLen - (jDone + 4));
    EmitB($88); EmitB($07);                                                      { mov [rdi],al }
    Exit;
  end;
  { integer family: r8 = negative flag, r9 = accumulator, rdx = cursor }
  EmitB($48); EmitB($89); EmitB($C7);                                            { mov rdi,rax }
  EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(BSS_LINE_POS);      { mov rdx,[pos] }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_LINE_LEN);      { mov rcx,[len] }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_LINE_BUF);      { lea rsi,[buf] }
  EmitB($4D); EmitB($31); EmitB($C0);                                            { xor r8,r8 (neg flag) }
  EmitB($4D); EmitB($31); EmitB($C9);                                            { xor r9,r9 (acc) }
  { skip whitespace }
  skipLoop := CodeLen;
  EmitB($48); EmitB($39); EmitB($CA);                                            { cmp rdx,rcx }
  EmitB($0F); EmitB($8D); jEmpty := CodeLen; EmitI32(0);                          { jge applysign (empty) }
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($20);                                { cmp rax,32 }
  EmitB($0F); EmitB($84); jAdv := CodeLen; EmitI32(0);                            { je advws }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($09);                                { cmp rax,9 }
  EmitB($0F); EmitB($85); jStart := CodeLen; EmitI32(0);                          { jne startsign }
  { advws: }
  Patch32(jAdv, CodeLen - (jAdv + 4));
  EmitB($48); EmitB($FF); EmitB($C2);                                            { inc rdx }
  EmitB($E9); EmitI32(skipLoop - (CodeLen + 4));                                  { jmp skipLoop }
  { startsign: }
  Patch32(jStart, CodeLen - (jStart + 4));
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($2D);                                { cmp rax,45 '-' }
  EmitB($0F); EmitB($85); jSign := CodeLen; EmitI32(0);                           { jne digits }
  EmitB($49); EmitB($C7); EmitB($C0); EmitI32(1);                                { mov r8,1 }
  EmitB($48); EmitB($FF); EmitB($C2);                                            { inc rdx }
  { digits: }
  Patch32(jSign, CodeLen - (jSign + 4));
  digLoop := CodeLen;
  EmitB($48); EmitB($39); EmitB($CA);                                            { cmp rdx,rcx }
  EmitB($0F); EmitB($8D); jDigEnd := CodeLen; EmitI32(0);                         { jge applysign }
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($30);                                { cmp rax,48 }
  EmitB($0F); EmitB($8C); jLt := CodeLen; EmitI32(0);                             { jl applysign }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($39);                                { cmp rax,57 }
  EmitB($0F); EmitB($8F); jGt := CodeLen; EmitI32(0);                             { jg applysign }
  EmitB($4D); EmitB($6B); EmitB($C9); EmitB($0A);                                { imul r9,r9,10 }
  EmitB($48); EmitB($83); EmitB($E8); EmitB($30);                                { sub rax,48 }
  EmitB($49); EmitB($01); EmitB($C1);                                            { add r9,rax }
  EmitB($48); EmitB($FF); EmitB($C2);                                            { inc rdx }
  EmitB($E9); EmitI32(digLoop - (CodeLen + 4));                                   { jmp digLoop }
  { applysign: }
  Patch32(jEmpty,  CodeLen - (jEmpty + 4));
  Patch32(jDigEnd, CodeLen - (jDigEnd + 4));
  Patch32(jLt,     CodeLen - (jLt + 4));
  Patch32(jGt,     CodeLen - (jGt + 4));
  EmitB($4D); EmitB($85); EmitB($C0);                                            { test r8,r8 }
  EmitB($0F); EmitB($84); jNoSign := CodeLen; EmitI32(0);                         { jz nosign }
  EmitB($49); EmitB($F7); EmitB($D9);                                            { neg r9 }
  { nosign: }
  Patch32(jNoSign, CodeLen - (jNoSign + 4));
  EmitB($4C); EmitB($89); EmitB($C8);                                            { mov rax,r9 }
  EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_LINE_POS);      { mov [pos],rdx }
  sz := TypeSize(tk);
  if sz = 1 then begin EmitB($88); EmitB($07); end                               { mov [rdi],al }
  else if sz = 2 then begin EmitB($66); EmitB($89); EmitB($07); end              { mov [rdi],ax }
  else if sz = 4 then begin EmitB($89); EmitB($07); end                          { mov [rdi],eax }
  else begin EmitB($48); EmitB($89); EmitB($07); end;                            { mov [rdi],rax }
end;

procedure EmitWriteVariant;
{ On entry rax = address of a 16-byte variant slot: [tag:8][payload:8].
  Reads the tag and dispatches to the matching scalar writer. Clobbers the
  caller-saved set like the other write helpers; balances its own stack. }
var pInt, pInt64, pBool, pDbl, pChar, jmpDefault, pEnd1, pEnd2: Integer;
begin
  EmitB($50);                                  { push rax            -> [rsp]=addr }
  EmitB($48); EmitB($8B); EmitB($00);          { mov rax, [rax]       ; tag }

  EmitB($48); EmitB($3D); EmitI32(VT_INT);     { cmp rax, VT_INT }
  EmitB($0F); EmitB($84); pInt := CodeLen; EmitI32(0);
  EmitB($48); EmitB($3D); EmitI32(VT_INT64);   { cmp rax, VT_INT64 }
  EmitB($0F); EmitB($84); pInt64 := CodeLen; EmitI32(0);
  EmitB($48); EmitB($3D); EmitI32(VT_BOOL);    { cmp rax, VT_BOOL }
  EmitB($0F); EmitB($84); pBool := CodeLen; EmitI32(0);
  EmitB($48); EmitB($3D); EmitI32(VT_DOUBLE);  { cmp rax, VT_DOUBLE }
  EmitB($0F); EmitB($84); pDbl := CodeLen; EmitI32(0);
  EmitB($48); EmitB($3D); EmitI32(VT_CHAR);    { cmp rax, VT_CHAR }
  EmitB($0F); EmitB($84); pChar := CodeLen; EmitI32(0);
  EmitB($E9); jmpDefault := CodeLen; EmitI32(0);   { default (empty/string/object): nothing }

  { integer/bool: payload as signed int64 }
  Patch32(pInt,   CodeLen - (pInt   + 4));
  Patch32(pInt64, CodeLen - (pInt64 + 4));
  Patch32(pBool,  CodeLen - (pBool  + 4));
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);   { mov rax, [rsp]   ; addr }
  EmitB($48); EmitB($8B); EmitB($40); EmitB($08);   { mov rax, [rax+8] ; payload }
  EmitwriteInt;
  EmitB($E9); pEnd1 := CodeLen; EmitI32(0);

  { double: payload bits -> xmm0 }
  Patch32(pDbl, CodeLen - (pDbl + 4));
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);   { mov rax, [rsp] }
  EmitB($48); EmitB($8B); EmitB($40); EmitB($08);   { mov rax, [rax+8] }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
  EmitWriteFloatNat;
  EmitB($E9); pEnd2 := CodeLen; EmitI32(0);

  { char: payload low byte }
  Patch32(pChar, CodeLen - (pChar + 4));
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);   { mov rax, [rsp] }
  EmitB($0F); EmitB($B6); EmitB($40); EmitB($08);   { movzx eax, byte [rax+8] }
  EmitwriteChar;

  { Lend }
  Patch32(jmpDefault, CodeLen - (jmpDefault + 4));
  Patch32(pEnd1, CodeLen - (pEnd1 + 4));
  Patch32(pEnd2, CodeLen - (pEnd2 + 4));
  EmitB($48); EmitB($83); EmitB($C4); EmitB($08);   { add rsp, 8       ; discard addr }
end;

procedure EmitSetcc(opTk: Integer; signed: Boolean);
{ Flags already set (cmp / comisd). Emit setcc al + movzx eax,al -> rax = 0/1.
  signed=True for integer cmp; False (unsigned/comisd) for double comisd. }
begin
  EmitB($0F);
  if signed then
  begin
    if      opTk = Ord(tkLt)  then EmitB($9C)   { setl  }
    else if opTk = Ord(tkLe)  then EmitB($9E)   { setle }
    else if opTk = Ord(tkGt)  then EmitB($9F)   { setg  }
    else if opTk = Ord(tkGe)  then EmitB($9D)   { setge }
    else if opTk = Ord(tkEq)  then EmitB($94)   { sete  }
    else if opTk = Ord(tkNeq) then EmitB($95)   { setne }
    else Error('Variant compare: unsupported operator');
  end
  else
  begin
    if      opTk = Ord(tkLt)  then EmitB($92)   { setb  }
    else if opTk = Ord(tkLe)  then EmitB($96)   { setbe }
    else if opTk = Ord(tkGt)  then EmitB($97)   { seta  }
    else if opTk = Ord(tkGe)  then EmitB($93)   { setae }
    else if opTk = Ord(tkEq)  then EmitB($94)   { sete  }
    else if opTk = Ord(tkNeq) then EmitB($95)   { setne }
    else Error('Variant compare: unsupported operator');
  end;
  EmitB($C0);                                  { ...al }
  EmitB($0F); EmitB($B6); EmitB($C0);          { movzx eax, al }
end;

procedure EmitVarBinOp(opTk, resultOff: Integer; isCompare: Boolean);
{ rdi = left variant addr, rsi = right variant addr. Closed double-dispatch:
  both integer-class -> integer op (preserves int); any VT_DOUBLE -> double op.
  isCompare -> Boolean 0/1 in rax; else Variant result at BSS[resultOff], addr in rax. }
var pDbl1, pDbl2, pDoneInt, pLi, pRi, pLd, pRd, pForceDbl: Integer;
begin
  { '/' is real division: always Double, like Pascal — skip the integer path. }
  pForceDbl := -1;
  if (not isCompare) and (opTk = Ord(tkSlash)) then
  begin
    EmitB($E9); pForceDbl := CodeLen; EmitI32(0);          { jmp Ldouble }
  end;
  EmitB($48); EmitB($8B); EmitB($07);                       { mov rax,[rdi]  (lTag) }
  EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_DOUBLE);     { cmp rax, VT_DOUBLE }
  EmitB($0F); EmitB($84); pDbl1 := CodeLen; EmitI32(0);     { je  Ldouble }
  EmitB($48); EmitB($8B); EmitB($06);                       { mov rax,[rsi]  (rTag) }
  EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_DOUBLE);
  EmitB($0F); EmitB($84); pDbl2 := CodeLen; EmitI32(0);     { je  Ldouble }

  { both integer-class }
  EmitB($48); EmitB($8B); EmitB($47); EmitB($08);           { mov rax,[rdi+8] }
  EmitB($48); EmitB($8B); EmitB($4E); EmitB($08);           { mov rcx,[rsi+8] }
  if isCompare then
  begin
    EmitB($48); EmitB($39); EmitB($C8);                     { cmp rax,rcx }
    EmitSetcc(opTk, True);
  end
  else
  begin
    if      opTk = Ord(tkPlus)  then begin EmitB($48); EmitB($01); EmitB($C8); end             { add  rax,rcx }
    else if opTk = Ord(tkMinus) then begin EmitB($48); EmitB($29); EmitB($C8); end             { sub  rax,rcx }
    else if opTk = Ord(tkStar)  then begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end { imul rax,rcx }
    else if opTk = Ord(tkDiv)   then begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end                       { cqo; idiv rcx -> quotient in rax }
    else if opTk = Ord(tkMod)   then begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); EmitB($48); EmitB($89); EmitB($D0); end  { cqo; idiv rcx; mov rax,rdx (remainder) }
    else if opTk = Ord(tkSlash) then { dead code: '/' is force-jumped to the double path above }
    else Error('Variant arithmetic: unsupported operator (string pending)');
    EmitB($48); EmitB($8D); EmitB($14); EmitB($25); EmitGlobRef(resultOff);       { lea rdx,[result] }
    EmitB($48); EmitB($C7); EmitB($02); EmitI32(VT_INT64);                        { mov qword[rdx],VT_INT64 }
    EmitB($48); EmitB($89); EmitB($42); EmitB($08);                               { mov [rdx+8],rax }
    EmitB($48); EmitB($89); EmitB($D0);                                           { mov rax,rdx }
  end;
  EmitB($E9); pDoneInt := CodeLen; EmitI32(0);              { jmp Ldone }

  { Ldouble: load both operands into xmm0/xmm1 }
  Patch32(pDbl1, CodeLen - (pDbl1 + 4));
  Patch32(pDbl2, CodeLen - (pDbl2 + 4));
  if pForceDbl >= 0 then Patch32(pForceDbl, CodeLen - (pForceDbl + 4));
  EmitB($48); EmitB($8B); EmitB($07);                       { mov rax,[rdi] }
  EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_DOUBLE);
  EmitB($75); pLi := CodeLen; EmitB(0);                     { jne  Lli }
  EmitB($F2); EmitB($0F); EmitB($10); EmitB($47); EmitB($08);            { movsd xmm0,[rdi+8] }
  EmitB($EB); pLd := CodeLen; EmitB(0);                     { jmp  Lldone }
  Code[pLi] := Byte(CodeLen - (pLi + 1));
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($47); EmitB($08);{ cvtsi2sd xmm0,[rdi+8] }
  Code[pLd] := Byte(CodeLen - (pLd + 1));
  EmitB($48); EmitB($8B); EmitB($06);                       { mov rax,[rsi] }
  EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_DOUBLE);
  EmitB($75); pRi := CodeLen; EmitB(0);                     { jne  Lri }
  EmitB($F2); EmitB($0F); EmitB($10); EmitB($4E); EmitB($08);            { movsd xmm1,[rsi+8] }
  EmitB($EB); pRd := CodeLen; EmitB(0);
  Code[pRi] := Byte(CodeLen - (pRi + 1));
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($4E); EmitB($08);{ cvtsi2sd xmm1,[rsi+8] }
  Code[pRd] := Byte(CodeLen - (pRd + 1));
  if isCompare then
  begin
    EmitB($66); EmitB($0F); EmitB($2F); EmitB($C1);          { comisd xmm0,xmm1 }
    EmitSetcc(opTk, False);
  end
  else if (opTk = Ord(tkDiv)) or (opTk = Ord(tkMod)) then
  begin
    { div/mod are integer operators: truncate the double operands to int64,
      integer-divide, store VT_INT64. (Pascal div/mod semantics.) }
    EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);                  { cvttsd2si rax, xmm0 }
    EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C9);                  { cvttsd2si rcx, xmm1 }
    EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9);                  { cqo; idiv rcx }
    if opTk = Ord(tkMod) then begin EmitB($48); EmitB($89); EmitB($D0); end;     { mov rax,rdx (remainder) }
    EmitB($48); EmitB($8D); EmitB($14); EmitB($25); EmitGlobRef(resultOff);      { lea rdx,[result] }
    EmitB($48); EmitB($C7); EmitB($02); EmitI32(VT_INT64);                       { mov qword[rdx],VT_INT64 }
    EmitB($48); EmitB($89); EmitB($42); EmitB($08);                              { mov [rdx+8],rax }
    EmitB($48); EmitB($89); EmitB($D0);                                          { mov rax,rdx }
  end
  else
  begin
    if      opTk = Ord(tkPlus)  then begin EmitB($F2); EmitB($0F); EmitB($58); EmitB($C1); end   { addsd }
    else if opTk = Ord(tkMinus) then begin EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C1); end   { subsd }
    else if opTk = Ord(tkStar)  then begin EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1); end   { mulsd }
    else if opTk = Ord(tkSlash) then begin EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C1); end   { divsd ('/' real division) }
    else Error('Variant arithmetic: unsupported operator');
    EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);                  { movq rax,xmm0 }
    EmitB($48); EmitB($8D); EmitB($14); EmitB($25); EmitGlobRef(resultOff);      { lea rdx,[result] }
    EmitB($48); EmitB($C7); EmitB($02); EmitI32(VT_DOUBLE);                      { mov qword[rdx],VT_DOUBLE }
    EmitB($48); EmitB($89); EmitB($42); EmitB($08);                             { mov [rdx+8],rax }
    EmitB($48); EmitB($89); EmitB($D0);                                         { mov rax,rdx }
  end;

  { Ldone: }
  Patch32(pDoneInt, CodeLen - (pDoneInt + 4));
end;

procedure IREmitNode(node: Integer);
var left, right, valNode, symIdx, si: Integer;
    op: TTokenKind;
    cmpUnsigned: Boolean;
    sVal: AnsiString;
    tk, lhsTk, rhsTk: TTypeKind;
    size: Integer;
    isSigned: Boolean;
    baseAddr, indexNode, lo, elemSize, offset, addressNode, valueNode: Integer;
    argNode, pathIdx, pi, specialId, classIdx, slot, cpi, i, jbePatch: Integer;
    searchTop, pJzBump, pJaeTake, pJmpDone, pJbeNoGrow, pFreeNil, pNotDouble, pDone: Integer;
    pDynZero, pDynNoOld, pDynKeepCopy: Integer;
    wid, decs: Integer;
    arg1Node, arg2Node, arg3Node, val1Node, val2Node: Integer;
    itemNode, trueCount, nextJmp, falseJmp: Integer;
    trueJumps: array[0..127] of Integer;
    raiseClass: Integer;
    intIdx, sseIdx, nArgs, mStack, padBytes, extIdx, restoreOff: Integer;
    argIsSse: array[0..15] of Boolean;
    argIsStack: array[0..15] of Boolean;
    argRegIdx: array[0..15] of Integer;
    argNodeArr: array[0..15] of Integer;
begin
  if node = -1 then Exit;
  
  case IRKind[node] of
    IR_NOP, IR_BLOCK:
      begin end;
      
    IR_CONST_INT:
      begin
        MovRaxImm(IRIVal[node]);
      end;
      
    IR_CONST_STR:
      begin
        { Intern the string literal and load it }
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitB($48); EmitB($B8); EmitDataRef(Strs[si].Offset);
      end;

    IR_PROCADDR:
      begin
        { @proc → mov rax, <absolute code address>, patched at finalize.
          External routines have no link-time address (resolved into the GOT
          by the dynamic linker); pass an internal wrapper instead. }
        if ProcExternal[IRA[node]] then
          Error('@ on external routine not supported; wrap it in a local routine');
        EmitB($48); EmitB($B8); { mov rax, imm64 }
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI64(0);
      end;

    IR_CLASSREF:
      begin
        { metaclass value → mov rax, <address of class ci's RTTI blob>.
          UClsRTTIOff is only known after EmitRTTI (runs post-parse), so emit a
          per-class sentinel data-ref patched to the real offset in compiler.pas
          (mirrors the -100 RTTI-registry / -101 resource-table sentinels). }
        EmitB($48); EmitB($B8); EmitDataRef(-(CLASSREF_DATAREF_BASE + IRA[node]));
      end;

    IR_SET_LIT:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(IRIVal[node]);
      end;
      
    IR_ASM:
      begin
        for i := 0 to IRB[node] - 1 do
        begin
          EmitB(AsmBytes[IRA[node] + i]);
        end;
      end;

    IR_RTTI_REG:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(-100);
      end;

    IR_RESOURCES:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(-101);
      end;
      
    IR_LOAD_SYM:
      begin
        EmitLoadVar(IRA[node]);
        { EmitLoadVar leaves floats in xmm0, but the IR value model carries
          floats as double bits in rax. Bridge xmm0 -> rax. }
        if TypeIsFloat(Syms[IRA[node]].TypeKind) then
          begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
      end;
      
    IR_STORE_SYM:
      begin
        symIdx := IRA[node];
        if Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
        begin
          IREmitNode(IRB[node]);                   { rax = new data pointer }
          EmitDynArrayRetain;
          EmitB($50);                             { push new data pointer }
          if Syms[symIdx].Kind = skGlobal then
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
          else
            begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
          EmitB($50);                             { push old data pointer }
          EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] }
          if Syms[symIdx].Kind = skGlobal then
            begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
          else
            begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
          EmitB($58);                             { pop rax = old data pointer }
          EmitDynArrayRelease;
          EmitB($58);                             { pop rax = new data pointer }
        end
        else if (Syms[symIdx].TypeKind = tyString) and not Syms[symIdx].IsArray then
        begin
          valueNode := IRB[node];
          if (IRKind[valueNode] = IR_CALL) and (IRA[valueNode] = -Ord(tkArgStr)) then
          begin
            argNode := IRB[valueNode];
            IREmitNode(IRA[argNode]); { rax = argv index }
            EmitArgvToString(symIdx);
          end
          else
          begin
            IREmitNode(valueNode); { rax = source string address (or char ordinal) }
            EmitB($50); { push source }
            if Syms[symIdx].Kind = skGlobal then
            begin
              EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset);
            end
            else if Syms[symIdx].Kind = skParam then
            begin
              EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset);
            end
            else
            begin
              EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset);
            end;
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            EmitB($5E);                         { pop rsi }
            if IntToTypeKind(IRTk[valueNode]) = tyChar then
              IREmitStoreCharAsString          { rsi = char ordinal -> [len=1][char] }
            else
            begin
              EmitB($48); EmitB($8B); EmitB($0E); { mov rcx, [rsi] }
              EmitB($48); EmitB($89); EmitB($0F); { mov [rdi], rcx }
              EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
              EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
              EmitB($F3); EmitB($A4);             { rep movsb }
            end;
          end;
        end
        else
        begin
          IREmitNode(IRB[node]);
          { IR carries floats as double bits in rax; EmitStoreVar reads xmm0.
            Bridge rax -> xmm0. }
          if TypeIsFloat(Syms[IRA[node]].TypeKind) then
            begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); end; { movq xmm0, rax }
          EmitStoreVar(IRA[node]);
        end;
      end;
      
    IR_LEA:
      begin
        symIdx := IRA[node];
        if Syms[symIdx].Kind = skGlobal then
        begin
          { Dynamic array slot holds a heap data pointer; load it (mov), not its
            address (lea), so indexing/Length operate on the heap block. }
          if Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
          else
            begin EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end;
        end
        else
        begin
          if (Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1)) or
             ((Syms[symIdx].Kind = skParam) and
              (Syms[symIdx].IsRef or Syms[symIdx].IsArray or
               (Syms[symIdx].TypeKind = tyString) or (Syms[symIdx].TypeKind = tySet))) then
          begin
            EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset);
          end
          else
          begin
            EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset);
          end;
        end;
      end;

    IR_INDEX:
      begin
        baseAddr := IRA[node];
        indexNode := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);
        
        IREmitNode(baseAddr);
        EmitB($50); { push rax }
        
        IREmitNode(indexNode); { rax = index }
        if lo <> 0 then
        begin
          EmitB($48); EmitB($2D); EmitI32(lo); { sub rax, lo }
        end;
        
        if elemSize = 8 then
        begin
          EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); { shl rax, 3 }
        end
        else if elemSize > 1 then
        begin
          EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
          EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); { imul rax, rcx }
        end;
        
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
      end;

    IR_FIELD:
      begin
        baseAddr := IRA[node];
        offset := Integer(IRIVal[node]);
        
        IREmitNode(baseAddr);
        EmitB($48); EmitB($05); EmitI32(offset); { add rax, offset }
      end;

    IR_LOAD_MEM:
      begin
        addressNode := IRA[node];
        IREmitNode(addressNode);
        
        tk := IntToTypeKind(IRTk[node]);
        size := TypeSize(tk);
        isSigned := TypeSigned(tk);
        
        if size = 1 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); { movsx rax, byte ptr [rax] }
          end
          else
          begin
            EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); { movzx rax, byte ptr [rax] }
          end;
        end
        else if size = 2 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); { movsx rax, word ptr [rax] }
          end
          else
          begin
            EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); { movzx rax, word ptr [rax] }
          end;
        end
        else if size = 4 then
        begin
          if isSigned then
          begin
            EmitB($48); EmitB($63); EmitB($00); { movsxd rax, dword ptr [rax] }
          end
          else
          begin
            EmitB($8B); EmitB($00); { mov eax, dword ptr [rax] }
          end;
        end
        else
        begin
          EmitB($48); EmitB($8B); EmitB($00); { mov rax, qword ptr [rax] }
        end;
      end;

    IR_STORE_MEM:
      begin
        addressNode := IRA[node];
        valueNode := IRB[node];

        tk := IntToTypeKind(IRTk[node]);
        size := TypeSize(tk);

        if tk = tyString then
        begin
          IREmitNode(valueNode); { rax = source string address (or char ordinal) }
          EmitB($50); { push source }

          IREmitNode(addressNode); { rax = destination address }

          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          EmitB($5E);                         { pop rsi }
          if IntToTypeKind(IRTk[valueNode]) = tyChar then
            IREmitStoreCharAsString          { rsi = char ordinal -> [len=1][char] }
          else
          begin
            EmitB($48); EmitB($8B); EmitB($0E); { mov rcx, [rsi] }
            EmitB($48); EmitB($89); EmitB($0F); { mov [rdi], rcx }
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
            EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
            EmitB($F3); EmitB($A4);             { rep movsb }
          end;
        end
        else
        begin
          IREmitNode(valueNode);
          EmitB($50); { push rax -- value }

          IREmitNode(addressNode); { rax = address }

          EmitB($59); { pop rcx -- value }

          if size = 1 then
        begin
          EmitB($88); EmitB($08); { mov byte ptr [rax], cl }
        end
        else if size = 2 then
        begin
          EmitB($66); EmitB($89); EmitB($08); { mov word ptr [rax], cx }
        end
        else if size = 4 then
        begin
          EmitB($89); EmitB($08); { mov dword ptr [rax], ecx }
        end
        else
        begin
          EmitB($48); EmitB($89); EmitB($08); { mov qword ptr [rax], rcx }
        end;
        end;
      end;
      
    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IntToTokenKind(IRC[node]);
        
        IREmitNode(left);
        EmitB($50); { push rax }
        
        IREmitNode(right);
        EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
        EmitB($58); { pop rax }
        
        if (IntToTypeKind(IRTk[node]) = tyString) and (op = tkPlus) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);

          EmitB($49); EmitB($89); EmitB($CA); { mov r10, rcx }
          EmitB($48); EmitB($81); EmitB($EC); EmitI32(272);
          EmitB($49); EmitB($89); EmitB($E3); { mov r11, rsp }

          if lhsTk = tyString then
          begin
            EmitB($4C); EmitB($8B); EmitB($00);
            EmitB($48); EmitB($8D); EmitB($70); EmitB($08);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($89); EmitB($C1);
            EmitB($48); EmitB($85); EmitB($C9);
            EmitB($74); EmitB(15);
            EmitB($8A); EmitB($16);
            EmitB($88); EmitB($17);
            EmitB($48); EmitB($FF); EmitB($C6);
            EmitB($48); EmitB($FF); EmitB($C7);
            EmitB($48); EmitB($FF); EmitB($C9);
            EmitB($EB); EmitB(Byte(-20));
          end
          else
          begin
            EmitB($49); EmitB($C7); EmitB($C0); EmitI32(1);
            EmitB($41); EmitB($88); EmitB($43); EmitB($08);
          end;

          if rhsTk = tyString then
          begin
            EmitB($4D); EmitB($8B); EmitB($0A);
            EmitB($49); EmitB($8D); EmitB($72); EmitB($08);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($01); EmitB($C7);
            EmitB($4C); EmitB($89); EmitB($CA);
            EmitB($48); EmitB($85); EmitB($D2);
            EmitB($74); EmitB(15);
            EmitB($8A); EmitB($06);
            EmitB($88); EmitB($07);
            EmitB($48); EmitB($FF); EmitB($C6);
            EmitB($48); EmitB($FF); EmitB($C7);
            EmitB($48); EmitB($FF); EmitB($CA);
            EmitB($EB); EmitB(Byte(-20));
          end
          else
          begin
            EmitB($49); EmitB($C7); EmitB($C1); EmitI32(1);
            EmitB($49); EmitB($8D); EmitB($7B); EmitB($08);
            EmitB($4C); EmitB($01); EmitB($C7);
            EmitB($44); EmitB($88); EmitB($17);
          end;

          EmitB($4B); EmitB($8D); EmitB($04); EmitB($08);
          EmitB($48); EmitB($3D); EmitI32(256);
          EmitB($7E); EmitB(7);
          EmitB($48); EmitB($C7); EmitB($C0); EmitI32(256);
          EmitB($49); EmitB($89); EmitB($03);
          EmitB($4C); EmitB($89); EmitB($D8);
        end
        else
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          if (lhsTk = tySingle) or (lhsTk = tyDouble) or (lhsTk = tyExtended) or
             (rhsTk = tySingle) or (rhsTk = tyDouble) or (rhsTk = tyExtended) or
             (op = tkSlash) then
          begin
            if not TypeIsFloat(lhsTk) then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C8); end  { cvtsi2sd xmm1, rax }
            else
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C8); end; { movq xmm1, rax }

            if not TypeIsFloat(rhsTk) then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C1); end  { cvtsi2sd xmm0, rcx }
            else
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C1); end; { movq xmm0, rcx }

            case op of
              tkPlus:  begin EmitB($F2); EmitB($0F); EmitB($58); EmitB($C1); end; { addsd xmm0, xmm1 }
              tkMinus:
                begin
                  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C8); { subsd xmm1, xmm0 }
                  EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
                end;
              tkStar:  begin EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1); end; { mulsd xmm0, xmm1 }
              tkSlash:
                begin
                  EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C8); { divsd xmm1, xmm0 }
                  EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
                end;
              tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
                begin
                  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C8); { ucomisd xmm1, xmm0 }
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end; { sete al }
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end; { setne al }
                    tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end; { setb al }
                    tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end; { setbe al }
                    tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end; { seta al }
                    tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end; { setae al }
                  end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
                end;
            end;

            if not ((op = tkEq) or (op = tkNeq) or (op = tkLt) or (op = tkLe) or (op = tkGt) or (op = tkGe)) then
            begin
              EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
            end;
          end
          else
          begin
            cmpUnsigned := TypeCompareUnsigned(IntToTypeKind(IRTk[left]), IntToTypeKind(IRTk[right]));

          case op of
          tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end; { add rax, rcx }
          tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end; { sub rax, rcx }
          tkStar:  begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end; { imul rax, rcx }
          
          tkDiv:
            begin
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
            end;
          tkMod:
            begin
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
              EmitB($48); EmitB($89); EmitB($D0); { mov rax, rdx }
            end;
          tkAnd:   begin EmitB($48); EmitB($21); EmitB($C8); end; { and rax, rcx }
          tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end; { or rax, rcx }
          tkIdent: begin EmitB($48); EmitB($D3); EmitB($E8); end; { shr rax, cl }
          tkShl:   begin EmitB($48); EmitB($D3); EmitB($E0); end; { shl rax, cl }

          tkIn:
            begin
              { rax = element value (LHS), rcx = set address (RHS) }
              EmitB($48); EmitB($3D); EmitI32(255); { cmp rax, 255 }
              EmitB($0F); EmitB($87); nextJmp := CodeLen; EmitI32(0); { ja out_of_range }
              
              EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
              EmitB($48); EmitB($C1); EmitB($EA); EmitB($03); { shr rdx, 3 }
              EmitB($49); EmitB($89); EmitB($C0); { mov r8, rax }
              EmitB($49); EmitB($83); EmitB($E0); EmitB($07); { and r8, 7 }
              
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($14); EmitB($11); { movzx rdx, byte [rcx+rdx] }
              
              MovRaxImm(1);
              EmitB($4C); EmitB($89); EmitB($C1); { mov rcx, r8 }
              EmitB($48); EmitB($D3); EmitB($E0); { shl rax, cl }
              EmitB($48); EmitB($85); EmitB($D0); { test rax, rdx }
              EmitB($0F); EmitB($95); EmitB($C0); { setnz al }
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
              EmitB($E9); falseJmp := CodeLen; EmitI32(0); { jmp exit }
              
              Patch32(nextJmp, CodeLen - (nextJmp + 4));
              MovRaxImm(0);
              Patch32(falseJmp, CodeLen - (falseJmp + 4));
            end;
          
          tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
            begin
              if ((op = tkEq) or (op = tkNeq)) and
                 ((IntToTypeKind(IRTk[left]) = tyString) or
                  (IntToTypeKind(IRTk[right]) = tyString)) then
              begin
                lhsTk := IntToTypeKind(IRTk[left]);
                rhsTk := IntToTypeKind(IRTk[right]);
                if (lhsTk = tyString) and (rhsTk = tyChar) then
                begin
                  { String = Char: rax = string struct, rcx = char ordinal.
                    Equal iff len=1 and the single byte matches. }
                  EmitB($51);                                                  { push rcx }
                  EmitB($48); EmitB($8B); EmitB($08);                          { mov rcx, [rax] }
                  EmitB($48); EmitB($83); EmitB($F9); EmitB($01);              { cmp rcx, 1 }
                  EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);      { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($48); EmitB($08);  { movzx rcx, byte [rax+8] }
                  EmitB($58);                                                  { pop rax }
                  EmitB($48); EmitB($39); EmitB($C1);                          { cmp rcx, rax }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  EmitB($59);                                                  { pop rcx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else if (lhsTk = tyChar) and (rhsTk = tyString) then
                begin
                  { Char = String: rax = char ordinal, rcx = string struct. }
                  EmitB($50);                                                  { push rax }
                  EmitB($48); EmitB($8B); EmitB($01);                          { mov rax, [rcx] }
                  EmitB($48); EmitB($83); EmitB($F8); EmitB($01);              { cmp rax, 1 }
                  EmitB($0F); EmitB($85); nextJmp := CodeLen; EmitI32(0);      { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($41); EmitB($08);  { movzx rax, byte [rcx+8] }
                  EmitB($5A);                                                  { pop rdx }
                  EmitB($48); EmitB($39); EmitB($D0);                          { cmp rax, rdx }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  EmitB($5A);                                                  { pop rdx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else
                  EmitStrCmpReg(op = tkEq);
              end
              else
              begin
                EmitB($48); EmitB($3B); EmitB($C1); { cmp rax, rcx }
                if cmpUnsigned then
                begin
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                    tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end;
                    tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end;
                    tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end;
                    tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end;
                  end;
                end
                else
                begin
                  case op of
                    tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                    tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                    tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end;
                    tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end;
                    tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end;
                    tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end;
                  end;
                end;
                EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
              end;
            end;
        else
          Error('Unsupported operator in IR codegen');
        end;
        end;
        end;
      end;
      
    IR_NEG:
      begin
        IREmitNode(IRA[node]);
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
          { Float value lives as double bits in rax; flip the sign bit. }
          begin EmitB($48); EmitB($0F); EmitB($BA); EmitB($F8); EmitB($3F); end { btc rax, 63 }
        else
          begin EmitB($48); EmitB($F7); EmitB($D8); end; { neg rax }
      end;
      
    IR_NOT:
      begin
        IREmitNode(IRA[node]);
        EmitB($48); EmitB($83); EmitB($F0); EmitB($01); { xor rax, 1 }
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid  := IRB[node];   { field width, 0 = none }
        decs := IRC[node];   { decimals, -1 = none }
        if IntToTypeKind(IRTk[node]) = tyVariant then
        begin
          { valNode lowers to the variant slot address; dispatch on the tag. }
          IREmitNode(valNode);
          EmitWriteVariant;
        end
        else if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          IREmitNode(valNode);                                        { double bits -> rax }
          EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
          if decs = -2 then EmitWriteFloatNat
          else if decs >= 0 then EmitWriteFloatFixed(decs)
          else EmitWriteFloatSci;
        end
        else if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if (wid > 0) and (wid > Strs[si].Len) then
          begin
            EnsureSpaces;
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
            MovRdxImm(wid - Strs[si].Len);
            MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
          end;
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else if ((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LEA)) and
                (IntToTypeKind(IRTk[valNode]) = tyString) then
        begin
          symIdx := IRA[valNode];
          if wid > 0 then
          begin
            { Runtime string width: pad with max(0, wid - len) spaces. }
            EnsureSpaces;
            EmitLoadStrLen(symIdx);              { rcx = len }
            MovRaxImm(wid);
            EmitB($48); EmitB($29); EmitB($C8);  { sub rax, rcx }
            EmitB($7E); EmitB(35);               { jle .skip_pad (35 bytes) }
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
            EmitB($48); EmitB($89); EmitB($C2);  { mov rdx, rax }
            MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
          end;
          EmitwriteStrVar(symIdx);
        end
        else if IntToTypeKind(IRTk[node]) = tyString then
        begin
          { String-valued expression (e.g. a function returning String):
            the value is the address of a [len][chars] struct in rax. }
          IREmitNode(valNode);
          EmitB($48); EmitB($89); EmitB($C6);              { mov rsi, rax }
          EmitB($48); EmitB($8B); EmitB($10);              { mov rdx, [rax] }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08);  { add rsi, 8 }
          MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
        end
        else
        begin
          IREmitNode(valNode);
          if IntToTypeKind(IRTk[node]) = tyChar then
            EmitwriteChar
          else if not TypeSigned(IntToTypeKind(IRTk[node])) then
          begin
            if wid > 0 then EmitwriteUIntW(wid) else EmitwriteUInt;
          end
          else
          begin
            if wid > 0 then EmitwriteIntW(wid) else EmitwriteInt;
          end;
        end;
      end;
      
    IR_CALL:
      begin
        pi := IRA[node];
        if pi >= 0 then
        begin
          if ProcExternal[pi] then
          begin
            { External C call — SysV AMD64 ABI. Integer/pointer args fill
              rdi,rsi,rdx,rcx,r8,r9; floating args fill xmm0..xmm7 (the two
              classes are counted independently); further args of each class
              spill to the stack, pushed right-to-left so the leftmost stack
              arg lies at the lowest address. Floats are carried as bits in
              rax. Internal Pascal calls use the all-integer path below. }
            argNode := IRB[node]; nArgs := 0;
            while argNode <> -1 do
            begin
              argNodeArr[nArgs] := IRA[argNode]; Inc(nArgs);
              argNode := IRB[argNode];
            end;
            intIdx := 0; sseIdx := 0; mStack := 0;
            for i := 0 to Procs[pi].ParamCount - 1 do
            begin
              if TypeIsFloat(Procs[pi].Params[i].TypeKind) then
              begin
                argIsSse[i] := True;
                if sseIdx < 8 then
                begin argIsStack[i] := False; argRegIdx[i] := sseIdx; Inc(sseIdx); end
                else begin argIsStack[i] := True; Inc(mStack); end;
              end
              else
              begin
                argIsSse[i] := False;
                if intIdx < 6 then
                begin argIsStack[i] := False; argRegIdx[i] := intIdx; Inc(intIdx); end
                else begin argIsStack[i] := True; Inc(mStack); end;
              end;
            end;
            extIdx := RegisterExternal(pi);
            { Align the stack and reserve the outgoing stack-arg area in one
              self-contained sequence (EmitCallProc's realign path cannot be
              used here — it would move rsp away from the stack args). Save the
              caller's rsp below the arg area so it survives the call (r11 is
              caller-saved, so spill it to the stack rather than trust it).
                mov r11, rsp ; and rsp, -16 ; push r11
              leaves rsp = aligned-8. At the call rsp must be 16-aligned, so
              with the saved-rsp slot plus mStack 8-byte args we pad by 8 when
              mStack is even. }
            EmitB($49); EmitB($89); EmitB($E3);             { mov r11, rsp }
            EmitB($48); EmitB($83); EmitB($E4); EmitB($F0); { and rsp, -16 }
            EmitB($41); EmitB($53);                         { push r11 }
            if (mStack and 1) = 0 then
            begin
              padBytes := 8;
              EmitB($48); EmitB($83); EmitB($EC); EmitB($08); { sub rsp, 8 }
            end
            else
              padBytes := 0;
            { Stack args, right-to-left (leftmost ends at the lowest address). }
            for i := Procs[pi].ParamCount - 1 downto 0 do
              if argIsStack[i] then
              begin
                IREmitNode(argNodeArr[i]); { -> rax }
                EmitB($50); { push rax }
              end;
            { Register args: push right-to-left, then pop left-to-right into the
              target registers (each arg evaluated once, no register clobber). }
            for i := Procs[pi].ParamCount - 1 downto 0 do
              if not argIsStack[i] then
              begin
                IREmitNode(argNodeArr[i]); { -> rax }
                EmitB($50); { push rax }
              end;
            for i := 0 to Procs[pi].ParamCount - 1 do
              if not argIsStack[i] then
              begin
                if argIsSse[i] then
                begin
                  EmitB($58); { pop rax }
                  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E);
                  EmitB($C0 + argRegIdx[i] * 8);           { movq xmm[n], rax }
                  if Procs[pi].Params[i].TypeKind = tySingle then
                  begin
                    EmitB($F2); EmitB($0F); EmitB($5A);
                    EmitB($C0 + argRegIdx[i] * 9);          { cvtsd2ss xmm[n],xmm[n] }
                  end;
                end
                else
                  case argRegIdx[i] of
                    0: EmitB($5F); { pop rdi }
                    1: EmitB($5E); { pop rsi }
                    2: EmitB($5A); { pop rdx }
                    3: EmitB($59); { pop rcx }
                    4: begin EmitB($41); EmitB($58); end; { pop r8 }
                    5: begin EmitB($41); EmitB($59); end; { pop r9 }
                  end;
              end;
            { Variadic ABI: AL = number of vector registers used. Set
              unconditionally (0 for all-integer calls) so variadic callees
              such as printf read the correct count. }
            EmitB($B8); EmitI32(sseIdx); { mov eax, sseIdx }
            EmitExternalIndirectCall(extIdx);
            { Restore the caller's rsp from the saved slot, which sits
              padBytes + mStack*8 above the current (post-call) rsp. }
            restoreOff := padBytes + mStack * 8;
            EmitB($48); EmitB($8B); EmitB($A4); EmitB($24); EmitI32(restoreOff); { mov rsp, [rsp+off] }
            if TypeIsFloat(Procs[pi].RetType) then
            begin
              { float/double returned in xmm0; bridge to rax bits. }
              EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
            end;
          end
          else
          begin
            { Internal Pascal call: all args in integer registers by index. }
            argNode := IRB[node];
            while argNode <> -1 do
            begin
              IREmitNode(IRA[argNode]); { -> rax }
              EmitB($50); { push rax }
              argNode := IRB[argNode];
            end;
            for i := Procs[pi].ParamCount - 1 downto 0 do
              case i of
                0: EmitB($5F); { pop rdi }
                1: EmitB($5E); { pop rsi }
                2: EmitB($5A); { pop rdx }
                3: EmitB($59); { pop rcx }
                4: begin EmitB($41); EmitB($58); end; { pop r8 }
                5: begin EmitB($41); EmitB($59); end; { pop r9 }
              end;
            if TypeIsAggregate(Procs[pi].RetType) then
            begin
              IREmitNode(IRC[node]);                   { rax = hidden destination }
              EmitB($49); EmitB($89); EmitB($C2);     { mov r10, rax }
            end;
            EmitCallProc(pi);
          end;
        end
        else if pi = -Ord(tkGetMem) then
        begin
          { GetMem with an 8-byte size header + free-list reuse.
            Block layout: [size:8][payload...]; the returned pointer is the
            payload (base+8), its size at payload-8. Freed blocks are threaded
            through a single free list (head BSS_FREE_LIST), the link kept in
            the freed payload's first 8 bytes. GetMem first-fits the list, else
            bump-allocates a fresh block (growing the arena via mmap when
            exhausted). No splitting/coalescing — proper allocator on the
            todo (see docs/todo.md). Class instantiation continues below, so
            both reuse and bump paths leave rax = payload. }
          EmitAcquireHeapLock;
          EmitB($53);                                     { push rbx }
          argNode := IRB[node]; { size arg }
          IREmitNode(IRA[argNode]); { Evaluate size -> rax }

          { Round up to a multiple of 8 and clamp to >= 8, so a freed block can
            always hold its 8-byte free-list link. rcx = N (payload size). }
          EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
          EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
          EmitB($48); EmitB($83); EmitB($F8); EmitB($08); { cmp rax, 8 }
          EmitB($73); EmitB($05);                         { jae +5 }
          EmitB($B8); EmitI32(8);                         { mov eax, 8 }
          EmitB($48); EmitB($89); EmitB($C1);             { mov rcx, rax }

          { Free-list first-fit. rsi = address of the slot pointing at the
            current node (starts at &BSS_FREE_LIST); rdx = current node. }
          EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { lea rsi, [BSS_FREE_LIST] }
          searchTop := CodeLen;
          EmitB($48); EmitB($8B); EmitB($16);             { mov rdx, [rsi]  (node) }
          EmitB($48); EmitB($85); EmitB($D2);             { test rdx, rdx }
          EmitB($74); pJzBump := CodeLen; EmitB(0);       { jz BUMP }
          EmitB($48); EmitB($8B); EmitB($42); EmitB($F8); { mov rax, [rdx-8]  (block size) }
          EmitB($48); EmitB($39); EmitB($C8);             { cmp rax, rcx }
          EmitB($73); pJaeTake := CodeLen; EmitB(0);      { jae TAKE  (size >= N) }
          EmitB($48); EmitB($89); EmitB($D6);             { mov rsi, rdx  (advance slot) }
          EmitB($EB); EmitB(Byte(searchTop - (CodeLen + 1))); { jmp search }
          { TAKE: unlink node, return payload }
          Code[pJaeTake] := Byte(CodeLen - (pJaeTake + 1));
          EmitB($48); EmitB($8B); EmitB($02);             { mov rax, [rdx]  (next) }
          EmitB($48); EmitB($89); EmitB($06);             { mov [rsi], rax  (*slot = next) }
          EmitB($48); EmitB($89); EmitB($D0);             { mov rax, rdx }
          EmitB($E9); pJmpDone := CodeLen; EmitI32(0);    { jmp DONE }

          { BUMP: fresh [size][payload] block at HEAP_PTR. }
          Code[pJzBump] := Byte(CodeLen - (pJzBump + 1));
          EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov rbx, [HEAP_PTR] }
          EmitB($48); EmitB($89); EmitB($D8);             { mov rax, rbx }
          EmitB($48); EmitB($01); EmitB($C8);             { add rax, rcx }
          EmitB($48); EmitB($83); EmitB($C0); EmitB($08); { add rax, 8   (block end) }
          EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END); { cmp rax, [HEAP_END] }
          EmitB($0F); EmitB($86); pJbeNoGrow := CodeLen; EmitI32(0); { jbe NOGROW }

          { Grow: mmap N + 8 + ARENA so this block fits; old tail abandoned.
            EmitMmapArena keeps rsi but clobbers rcx, so save N. }
          EmitB($48); EmitB($89); EmitB($CE);             { mov rsi, rcx }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
          EmitB($48); EmitB($81); EmitB($C6); EmitI32(HEAP_ARENA_SIZE); { add rsi, ARENA }
          EmitB($51);                                     { push rcx (save N) }
          EmitMmapArena;                                  { rax = base; rsi kept }
          EmitB($59);                                     { pop rcx (restore N) }
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov [HEAP_PTR], rax }
          EmitB($48); EmitB($89); EmitB($C3);             { mov rbx, rax }
          EmitB($48); EmitB($89); EmitB($C2);             { mov rdx, rax }
          EmitB($48); EmitB($01); EmitB($F2);             { add rdx, rsi  (base+len) }
          EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_END); { mov [HEAP_END], rdx }

          { NOGROW: base in rbx -> write header, advance HEAP_PTR, return payload. }
          Patch32(pJbeNoGrow, CodeLen - (pJbeNoGrow + 4));
          EmitB($48); EmitB($89); EmitB($0B);             { mov [rbx], rcx  (size header) }
          EmitB($48); EmitB($8D); EmitB($43); EmitB($08); { lea rax, [rbx+8]  (payload) }
          EmitB($48); EmitB($89); EmitB($DA);             { mov rdx, rbx }
          EmitB($48); EmitB($01); EmitB($CA);             { add rdx, rcx }
          EmitB($48); EmitB($83); EmitB($C2); EmitB($08); { add rdx, 8   (base+8+N) }
          EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov [HEAP_PTR], rdx }

          { DONE: rax = payload pointer }
          Patch32(pJmpDone, CodeLen - (pJmpDone + 4));
          EmitB($5B);                                     { pop rbx }
          EmitReleaseHeapLock;

          { Put instance pointer in rdi }
          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          
          { Initialize VMT pointer at offset 0 }
          classIdx := IRC[node];
          EmitB($48); EmitB($B8); EmitDataRef(UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { mov rax, VMT_addr }
          EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
          
          { Find constructor 'Create' of this class }
          slot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
          if slot >= 0 then
          begin
            cpi := UMthProc_[slot];
            
            { Push Self first }
            EmitB($57); { push rdi }
            
            { Push explicit constructor arguments }
            argNode := IRB[node]; { size arg }
            argNode := IRB[argNode]; { first explicit constructor arg }
            while argNode <> -1 do
            begin
              IREmitNode(IRA[argNode]); { evaluates arg -> rax }
              EmitB($50); { push rax }
              argNode := IRB[argNode];
            end;
            
            { Pop args into SysV ABI registers }
            for i := Procs[cpi].ParamCount-1 downto 0 do
              case i of
                0: EmitB($5F);
                1: EmitB($5E);
                2: EmitB($5A);
                3: EmitB($59);
                4: begin EmitB($41); EmitB($58); end;
                5: begin EmitB($41); EmitB($59); end;
              end;
              
            { Save Self on stack across the call }
            EmitB($57); { push rdi }
            
            EmitCallProc(cpi);
            
            { Restore Self into rax as the result of the constructor call }
            EmitB($58); { pop rax }
          end
          else
          begin
            { No constructor defined, just return the instance pointer in rax }
            EmitB($48); EmitB($89); EmitB($F8); { mov rax, rdi }
          end;
        end
        else if pi = -Ord(tkFreeMem) then
        begin
          { FreeMem(p): push the block onto the free list (link stored in the
            payload's first 8 bytes). nil is ignored. The size header at [p-8]
            is left intact so GetMem can size the block for reuse. }
          EmitAcquireHeapLock;
          argNode := IRB[node]; { pointer arg }
          IREmitNode(IRA[argNode]); { p -> rax }
          EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
          EmitB($74); pFreeNil := CodeLen; EmitB(0);      { jz over (nil: skip) }
          EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { mov rdx, [FREE_LIST] }
          EmitB($48); EmitB($89); EmitB($10);             { mov [rax], rdx  (p.next = head) }
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { mov [FREE_LIST], rax }
          Code[pFreeNil] := Byte(CodeLen - (pFreeNil + 1));
          EmitReleaseHeapLock;
        end
        else if pi = -103 then
        begin
          { ReallocMem(oldp, newsize) -> new pointer in rax.
            Bump-allocate a fresh [size][payload] block of newsize, copy
            min(oldsize, newsize) bytes from oldp (oldsize read from oldp's
            header; nil oldp => copy nothing), push the old block on the free
            list, return the new payload. Stack: [oldp] then [newp][oldp]. }
          EmitAcquireHeapLock;
          EmitB($53);                                     { push rbx }
          argNode := IRB[node];           { arg0 = oldp }
          IREmitNode(IRA[argNode]);       { rax = oldp }
          EmitB($50);                     { push rax (oldp) }
          argNode := IRB[argNode];        { arg1 = newsize }
          IREmitNode(IRA[argNode]);       { rax = newsize }

          { round up to 8, clamp >= 8 -> rcx (N) }
          EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
          EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
          EmitB($48); EmitB($83); EmitB($F8); EmitB($08); { cmp rax, 8 }
          EmitB($73); EmitB($05);                         { jae +5 }
          EmitB($B8); EmitI32(8);                         { mov eax, 8 }
          EmitB($48); EmitB($89); EmitB($C1);             { mov rcx, rax }

          { bump-allocate N + 8 (no free-list reuse for the new block) }
          EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov rbx, [HEAP_PTR] }
          EmitB($48); EmitB($89); EmitB($D8);             { mov rax, rbx }
          EmitB($48); EmitB($01); EmitB($C8);             { add rax, rcx }
          EmitB($48); EmitB($83); EmitB($C0); EmitB($08); { add rax, 8 }
          EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END); { cmp rax, [HEAP_END] }
          EmitB($0F); EmitB($86); pJbeNoGrow := CodeLen; EmitI32(0); { jbe NOGROW }
          EmitB($48); EmitB($89); EmitB($CE);             { mov rsi, rcx }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
          EmitB($48); EmitB($81); EmitB($C6); EmitI32(HEAP_ARENA_SIZE); { add rsi, ARENA }
          EmitB($51);                                     { push rcx }
          EmitMmapArena;                                  { rax = base; rsi kept }
          EmitB($59);                                     { pop rcx }
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov [HEAP_PTR], rax }
          EmitB($48); EmitB($89); EmitB($C3);             { mov rbx, rax }
          EmitB($48); EmitB($89); EmitB($C2);             { mov rdx, rax }
          EmitB($48); EmitB($01); EmitB($F2);             { add rdx, rsi }
          EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_END); { mov [HEAP_END], rdx }
          Patch32(pJbeNoGrow, CodeLen - (pJbeNoGrow + 4));
          EmitB($48); EmitB($89); EmitB($0B);             { mov [rbx], rcx  (header) }
          EmitB($48); EmitB($8D); EmitB($43); EmitB($08); { lea rax, [rbx+8]  (newp) }
          EmitB($48); EmitB($89); EmitB($DA);             { mov rdx, rbx }
          EmitB($48); EmitB($01); EmitB($CA);             { add rdx, rcx }
          EmitB($48); EmitB($83); EmitB($C2); EmitB($08); { add rdx, 8 }
          EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_PTR); { mov [HEAP_PTR], rdx }

          { rax = newp, rcx = newsize. Recover oldp, stack [newp][oldp]. }
          EmitB($5E);                                     { pop rsi (oldp) }
          EmitB($50);                                     { push rax (newp) }
          EmitB($56);                                     { push rsi (oldp) }

          { oldsize -> rdx (0 if oldp nil) }
          EmitB($48); EmitB($31); EmitB($D2);             { xor rdx, rdx }
          EmitB($48); EmitB($85); EmitB($F6);             { test rsi, rsi }
          EmitB($74); EmitB($04);                         { jz +4 }
          EmitB($48); EmitB($8B); EmitB($56); EmitB($F8); { mov rdx, [rsi-8] }
          { count = min(oldsize rdx, newsize rcx) -> rcx }
          EmitB($48); EmitB($39); EmitB($CA);             { cmp rdx, rcx }
          EmitB($73); EmitB($03);                         { jae +3 (rdx>=rcx: keep newsize) }
          EmitB($48); EmitB($89); EmitB($D1);             { mov rcx, rdx }
          { rep movsb from oldp([rsp]) to newp([rsp+8]) }
          EmitB($48); EmitB($8B); EmitB($34); EmitB($24); { mov rsi, [rsp]  (oldp) }
          EmitB($48); EmitB($8B); EmitB($7C); EmitB($24); EmitB($08); { mov rdi, [rsp+8]  (newp) }
          EmitB($F3); EmitB($A4);                         { rep movsb }

          { free old block (if non-nil): push on free list }
          EmitB($5E);                                     { pop rsi (oldp) }
          EmitB($48); EmitB($85); EmitB($F6);             { test rsi, rsi }
          EmitB($74); EmitB($13);                         { jz +19 }
          EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { mov rdx, [FREE_LIST] }
          EmitB($48); EmitB($89); EmitB($16);             { mov [rsi], rdx }
          EmitB($48); EmitB($89); EmitB($34); EmitB($25); EmitGlobRef(BSS_FREE_LIST); { mov [FREE_LIST], rsi }
          EmitB($58);                                     { pop rax (newp) -> result }
          EmitB($5B);                                     { pop rbx }
          EmitReleaseHeapLock;
        end
        else
        begin
          { Special/built-in calls }
          specialId := -pi;
          if specialId = Ord(tkLength) then
          begin
            arg1Node := IRB[node];
            val1Node := IRA[arg1Node];
            if (IRKind[val1Node] = IR_LEA) and Syms[IRA[val1Node]].IsArray
               and (Syms[IRA[val1Node]].ArrLen = -1) then
            begin
              { Dynamic array: IR_LEA already loaded the heap data pointer (or 0).
                Length lives at [ptr-8]; a nil array reports 0. }
              IREmitNode(val1Node);                          { rax = data ptr (or 0) }
              EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
              EmitB($74); jbePatch := CodeLen; EmitB(0);     { jz done (rax already 0) }
              EmitB($48); EmitB($8B); EmitB($40); EmitB($F8);{ mov rax, [rax-8] }
              Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
            end
            else
            begin
              IREmitNode(val1Node); { evaluates address -> rax }
              EmitB($48); EmitB($8B); EmitB($00); { mov rax, [rax] }
            end;
          end
          else if (specialId = Ord(tkOrd)) or (specialId = Ord(tkChr)) or
                  (specialId = Ord(tkInteger_T)) or (specialId = Ord(tkLongWord_T)) then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
          end
          else if specialId = 200 then
          begin
            { int(x): float/Variant -> integer }
            arg1Node := IRB[node];
            val1Node := IRA[arg1Node];
            IREmitNode(val1Node); { evaluates arg -> rax }
            if TypeIsFloat(IntToTypeKind(IRTk[val1Node])) then
            begin
              EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
              EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);   { cvttsd2si rax, xmm0 }
            end
            else if IntToTypeKind(IRTk[val1Node]) = tyVariant then
            begin
              EmitB($53);                                      { push rbx }
              EmitB($48); EmitB($89); EmitB($C3);              { mov rbx, rax }
              EmitB($48); EmitB($8B); EmitB($03);              { mov rax, [rbx]  ; tag }
              EmitB($48); EmitB($3D); EmitI32(VT_DOUBLE);      { cmp rax, VT_DOUBLE }
              EmitB($75); pNotDouble := CodeLen; EmitB(0);     { jne .not_double }
              EmitB($48); EmitB($8B); EmitB($43); EmitB($08);  { mov rax, [rbx+8] ; payload }
              EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
              EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);   { cvttsd2si rax, xmm0 }
              EmitB($EB); pDone := CodeLen; EmitB(0);          { jmp .done }
              { .not_double: }
              Code[pNotDouble] := Byte(CodeLen - (pNotDouble + 1));
              EmitB($48); EmitB($8B); EmitB($43); EmitB($08);  { mov rax, [rbx+8] ; payload }
              { .done: }
              Code[pDone] := Byte(CodeLen - (pDone + 1));
              EmitB($5B);                                      { pop rbx }
            end;
          end
          else if (specialId = 203) or (specialId = 204) or
                  (specialId = 205) or (specialId = 206) then
          begin
            { Float intrinsics: 203 Trunc(->Int64,toward zero), 204 Round(->Int64,
              nearest-even), 205 Frac(->Double), 206 Int(->Double, integer part). }
            arg1Node := IRB[node];
            val1Node := IRA[arg1Node];
            IREmitNode(val1Node);                                        { arg -> rax }
            if TypeIsFloat(IntToTypeKind(IRTk[val1Node])) then
            begin
              EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
              if specialId = 203 then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0); end   { cvttsd2si rax, xmm0 }
              else if specialId = 204 then
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($C0); end   { cvtsd2si rax, xmm0 }
              else if specialId = 206 then
              begin
                EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);           { cvttsd2si rax, xmm0 }
                EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C0);           { cvtsi2sd xmm0, rax }
                EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);           { movq rax, xmm0 }
              end
              else
              begin   { 205 Frac = x - trunc(x) }
                EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C8);           { cvttsd2si rcx, xmm0 }
                EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C9);           { cvtsi2sd xmm1, rcx }
                EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C1);                       { subsd xmm0, xmm1 }
                EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);           { movq rax, xmm0 }
              end;
            end
            else
            begin   { integer argument }
              if specialId = 205 then
              begin EmitB($48); EmitB($31); EmitB($C0); end                          { xor rax,rax (Frac(int)=0) }
              else if specialId = 206 then
              begin
                EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C0);           { cvtsi2sd xmm0, rax }
                EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);           { movq rax, xmm0 (Int(int) as double) }
              end;
              { 203/204 Trunc/Round of an integer: rax already holds it }
            end;
          end
          else if specialId = Ord(tkArgCount) then
          begin
            EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
            EmitB($48); EmitB($8B); EmitB($00);
            EmitB($48); EmitB($FF); EmitB($C8);
          end
          else if specialId = 100 then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            val2Node := IRA[arg2Node];
            if (IRKind[val1Node] = IR_LEA) and (IRKind[val2Node] = IR_LEA) then
              EmitLoadFile(IRA[val1Node], IRA[val2Node])
            else
              Error('LoadFile expects string variables in IR codegen');
          end
          else if specialId = 101 then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            if IRKind[val1Node] = IR_LEA then
            begin
              IREmitNode(IRA[arg2Node]);
              EmitStoreStrLen(IRA[val1Node]);
            end
            else
              Error('SetLength expects a string variable in IR codegen');
          end
          else if specialId = 102 then
          begin
            { Scalar dynamic-array SetLength. The allocator payload contains
              [refcount:8][length:8][data...]. Allocate-copy-free so growing
              and shrinking preserve min(old,new) elements. }
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val1Node := IRA[arg1Node];
            if IRKind[val1Node] <> IR_LEA then
              Error('SetLength expects an array variable in IR codegen');
            symIdx := IRA[val1Node];
            if (Syms[symIdx].ElemType = tyRecord) or (Syms[symIdx].ElemType = tyString) then
              Error('SetLength: dynamic array of record/string not yet supported');
            elemSize := TypeSize(Syms[symIdx].ElemType);

            IREmitNode(IRA[arg2Node]);      { rax = n }
            EmitB($50);                     { push n }
            EmitAcquireHeapLock;
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($8B); EmitB($34); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[symIdx].Offset); end;
            EmitB($56);                     { push old data pointer }
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] = n }
            EmitB($48); EmitB($85); EmitB($C0); { test rax, rax }
            EmitB($0F); EmitB($84); pDynZero := CodeLen; EmitI32(0);

            if elemSize = 8 then
              begin EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); end { shl rax, 3 }
            else if elemSize > 1 then
              begin
                EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
                EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);        { imul rax, rcx }
              end;
            EmitB($48); EmitB($83); EmitB($C0); EmitB($10); { add rax, 16 (header) }
            EmitHeapAllocLocked;            { rax = allocator payload / array base }
            EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($08); { mov rcx, [rsp+8] = n }
            EmitB($48); EmitB($C7); EmitB($00); EmitI32(1);  { mov qword [rax], 1 (refcount) }
            EmitB($48); EmitB($89); EmitB($48); EmitB($08);  { mov [rax+8], rcx (length) }
            EmitB($48); EmitB($8D); EmitB($78); EmitB($10);  { lea rdi, [rax+16] (new data) }
            EmitB($57);                     { push new data pointer }

            { Zero all new slots, then copy the preserved old prefix over it. }
            if elemSize = 8 then
              begin EmitB($48); EmitB($C1); EmitB($E1); EmitB($03); end
            else if elemSize > 1 then
              begin
                EmitB($48); EmitB($C7); EmitB($C0); EmitI32(elemSize);
                EmitB($48); EmitB($0F); EmitB($AF); EmitB($C8);
              end;
            EmitB($31); EmitB($C0);          { xor eax, eax }
            EmitB($F3); EmitB($AA);          { rep stosb }

            EmitB($48); EmitB($8B); EmitB($3C); EmitB($24);           { mov rdi, [rsp] = new data }
            EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi, [rsp+8] = old data }
            EmitB($48); EmitB($85); EmitB($F6);                       { test rsi, rsi }
            EmitB($0F); EmitB($84); pDynNoOld := CodeLen; EmitI32(0);
            EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);           { mov rcx, [rsi-8] = old length }
            EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($10); { mov rdx, [rsp+16] = n }
            EmitB($48); EmitB($39); EmitB($D1);                       { cmp rcx, rdx }
            EmitB($0F); EmitB($86); pDynKeepCopy := CodeLen; EmitI32(0); { jbe copy_size }
            EmitB($48); EmitB($89); EmitB($D1);                       { mov rcx, rdx }
            Patch32(pDynKeepCopy, CodeLen - (pDynKeepCopy + 4));
            if elemSize = 8 then
              begin EmitB($48); EmitB($C1); EmitB($E1); EmitB($03); end
            else if elemSize > 1 then
              begin
                EmitB($48); EmitB($C7); EmitB($C0); EmitI32(elemSize);
                EmitB($48); EmitB($0F); EmitB($AF); EmitB($C8);
              end;
            EmitB($F3); EmitB($A4);          { rep movsb }
            Patch32(pDynNoOld, CodeLen - (pDynNoOld + 4));

            EmitB($58);                     { pop rax = new data pointer }
            EmitB($5E);                     { pop rsi = old data pointer }
            EmitB($59);                     { pop rcx = n }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($48); EmitB($89); EmitB($F0);                       { mov rax, rsi }
            EmitDynArrayReleaseLocked;
            EmitB($E9); pJmpDone := CodeLen; EmitI32(0);

            { SetLength(a, 0): publish nil and release the old allocation. }
            Patch32(pDynZero, CodeLen - (pDynZero + 4));
            EmitB($5E);                     { pop rsi = old data pointer }
            EmitB($59);                     { pop rcx = n }
            EmitB($31); EmitB($C0);          { xor eax, eax }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($48); EmitB($89); EmitB($F0);                       { mov rax, rsi }
            EmitDynArrayReleaseLocked;

            Patch32(pJmpDone, CodeLen - (pJmpDone + 4));
            EmitReleaseHeapLock;
          end
          else if specialId = SPECIAL_IN then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }

            trueCount := 0;
            argNode := IRB[arg1Node];
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                lo := Integer(IRIVal[IRA[itemNode]]);
                elemSize := Integer(IRIVal[IRB[itemNode]]);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo);
                EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(elemSize);
                EmitB($0F); EmitB($8E);
                if trueCount >= 128 then Error('set expression too large');
                trueJumps[trueCount] := CodeLen; Inc(trueCount);
                EmitI32(0);
                Patch32(nextJmp, CodeLen - (nextJmp + 4));
              end
              else
              begin
                lo := Integer(IRIVal[itemNode]);
                EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo);
                EmitB($0F); EmitB($84);
                if trueCount >= 128 then Error('set expression too large');
                trueJumps[trueCount] := CodeLen; Inc(trueCount);
                EmitI32(0);
              end;
              argNode := IRB[argNode];
            end;

            MovRaxImm(0);
            EmitB($E9); falseJmp := CodeLen; EmitI32(0);
            for i := 0 to trueCount - 1 do
              Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
            MovRaxImm(1);
            Patch32(falseJmp, CodeLen - (falseJmp + 4));
          end
          else if specialId = Ord(tkSysOpen) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            
            val1Node := IRA[arg1Node];
            val2Node := IRA[arg2Node];
            
            if (IRKind[val1Node] = IR_LOAD_SYM) or (IRKind[val1Node] = IR_LEA) then
              symIdx := IRA[val1Node]
            else
              symIdx := -1;
              
            EmitTerminateString(symIdx);
            EmitLeaStrDataRdi(symIdx);
            
            IREmitNode(val2Node); { Evaluates flags -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            MovRaxImm(0); EmitB($48); EmitB($89); EmitB($C2);
            MovRaxImm(SYS_OPEN); EmitSyscall;
          end
          else if specialId = Ord(tkSysRead) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            arg3Node := IRB[arg2Node];
            
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            
            IREmitNode(IRA[arg2Node]); { evaluates address -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            
            IREmitNode(IRA[arg3Node]);
            EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
            
            MovRaxImm(SYS_READ); EmitSyscall;
          end
          else if specialId = Ord(tkSyswrite) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            arg3Node := IRB[arg2Node];
            
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            
            IREmitNode(IRA[arg2Node]); { evaluates address -> rax }
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            
            IREmitNode(IRA[arg3Node]);
            EmitB($48); EmitB($89); EmitB($C2); { mov rdx, rax }
            
            MovRaxImm(1); EmitSyscall;
          end
          else if specialId = Ord(tkSysClose) then
          begin
            arg1Node := IRB[node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            MovRaxImm(SYS_CLOSE); EmitSyscall;
          end
          else if specialId = Ord(tkArgStr) then
          begin
            { ArgStr(index, strVar): copy argv[index] into the string variable.
              arg1 = index expr, arg2 = string var (lowers to IR_LEA). }
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            val2Node := IRA[arg2Node];
            if (IRKind[val2Node] = IR_LEA) or (IRKind[val2Node] = IR_LOAD_SYM) then
              symIdx := IRA[val2Node]
            else
              Error('ArgStr expects a string variable in IR codegen');
            IREmitNode(IRA[arg1Node]);   { rax = index }
            EmitArgvToString(symIdx);
          end
          else if specialId = Ord(tkSysFchmod) then
          begin
            arg1Node := IRB[node];
            arg2Node := IRB[arg1Node];
            IREmitNode(IRA[arg1Node]);
            EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
            IREmitNode(IRA[arg2Node]);
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            MovRaxImm(91); EmitSyscall;
          end;
        end;
      end;
      
    IR_WRITELN:
      begin
        EmitwriteSyscall(NEWLINE_OFFSET, 1);
      end;

    IR_READLINE:
      begin
        EmitReadLine;
      end;

    IR_READ_VAR:
      begin
        IREmitNode(IRA[node]);   { rax = target address }
        EmitReadVarParse(IntToTypeKind(IRTk[node]));
      end;

    IR_VAR_STORE:
      begin
        { Box a scalar (or copy a whole variant) into a 16-byte variant slot.
          IRA = dest addr, IRB = value/src addr, IRC = source TTypeKind ord. }
        tk := IntToTypeKind(IRC[node]);
        if tk = tyVariant then
        begin
          { 16-byte variant-to-variant copy }
          IREmitNode(IRB[node]);                 { rax = src addr }
          EmitB($50);
          IREmitNode(IRA[node]);                 { rax = dest addr }
          EmitB($48); EmitB($89); EmitB($C7);    { mov rdi, rax }
          EmitB($5E);                            { pop rsi }
          EmitB($48); EmitB($C7); EmitB($C1); EmitI32(16); { mov rcx, 16 }
          EmitB($F3); EmitB($A4);                { rep movsb }
        end
        else
        begin
          { select VType tag from the source scalar kind }
          case tk of
            tyInteger, tyInt8, tyInt16, tyInt32: size := VT_INT;
            tyInt64, tyNativeInt:                size := VT_INT64;
            tyUInt8, tyUInt16, tyUInt32, tyUInt64,
            tyNativeUInt, tyPointer:             size := VT_INT64;
            tyBoolean:                           size := VT_BOOL;
            tyChar:                              size := VT_CHAR;
            tyDouble:                            size := VT_DOUBLE;
          else
            Error('Variant := this type not yet supported (scalar tags only; string/single/extended pending)');
          end;
          IREmitNode(IRB[node]);                 { rax = scalar value (float: double bits) }
          if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
          begin EmitB($48); EmitB($98); end;     { cdqe: sign-extend eax -> rax }
          EmitB($50);                            { push rax  (payload) }
          IREmitNode(IRA[node]);                 { rax = dest addr }
          EmitB($48); EmitB($89); EmitB($C7);    { mov rdi, rax }
          EmitB($59);                            { pop rcx   (payload) }
          EmitB($48); EmitB($C7); EmitB($07); EmitI32(size);  { mov qword [rdi], tag }
          EmitB($48); EmitB($89); EmitB($4F); EmitB($08);     { mov [rdi+8], rcx }
        end;
      end;

    IR_VAR_BOX:
      begin
        { Box a scalar into a temp variant (IRA=temp addr), return addr in rax. }
        tk := IntToTypeKind(IRC[node]);
        case tk of
          tyInteger, tyInt8, tyInt16, tyInt32: size := VT_INT;
          tyInt64, tyNativeInt:                size := VT_INT64;
          tyUInt8, tyUInt16, tyUInt32, tyUInt64,
          tyNativeUInt, tyPointer:             size := VT_INT64;
          tyBoolean:                           size := VT_BOOL;
          tyChar:                              size := VT_CHAR;
          tyDouble:                            size := VT_DOUBLE;
        else
          Error('Variant operand: this scalar type not yet supported (string/single/extended pending)');
        end;
        IREmitNode(IRB[node]);                 { rax = scalar value }
        if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
        begin EmitB($48); EmitB($98); end;     { cdqe }
        EmitB($50);                            { push payload }
        IREmitNode(IRA[node]);                 { rax = temp addr }
        EmitB($48); EmitB($89); EmitB($C7);    { mov rdi, rax }
        EmitB($59);                            { pop rcx }
        EmitB($48); EmitB($C7); EmitB($07); EmitI32(size);  { mov qword [rdi], tag }
        EmitB($48); EmitB($89); EmitB($4F); EmitB($08);     { mov [rdi+8], rcx }
        EmitB($48); EmitB($89); EmitB($F8);    { mov rax, rdi  (return addr) }
      end;

    IR_VAR_BINOP:
      begin
        IREmitNode(IRA[node]);                 { rax = left addr }
        EmitB($50);                            { push left }
        IREmitNode(IRB[node]);                 { rax = right addr }
        EmitB($48); EmitB($89); EmitB($C6);    { mov rsi, rax  (right) }
        EmitB($5F);                            { pop rdi       (left) }
        EmitVarBinOp(IRC[node], Integer(IRIVal[node]), IntToTypeKind(IRTk[node]) = tyBoolean);
      end;

    IR_COPY_REC:
      begin
        { full-record copy: rep movsb IRIVal bytes from src (IRB) to dest (IRA) }
        IREmitNode(IRB[node]);                 { rax = source address }
        EmitB($50);                            { push rsi-source }
        IREmitNode(IRA[node]);                 { rax = dest address }
        EmitB($48); EmitB($89); EmitB($C7);    { mov rdi, rax }
        EmitB($5E);                            { pop rsi }
        EmitB($48); EmitB($B9); EmitI64(IRIVal[node]); { movabs rcx, byte count }
        EmitB($F3); EmitB($A4);                { rep movsb }
      end;

    IR_SET_COPY:
      begin
        IREmitNode(IRB[node]);                 { rax = source address }
        EmitB($50);
        IREmitNode(IRA[node]);                 { rax = dest address }
        EmitB($48); EmitB($89); EmitB($C7);    { mov rdi, rax }
        EmitB($5E);                            { pop rsi }
        EmitB($48); EmitB($C7); EmitB($C1); EmitI32(32); { mov rcx, 32 }
        EmitB($F3); EmitB($A4);                { rep movsb }
      end;

    IR_SET_BINOP:
      begin
        IREmitNode(IRA[node]);                 { lhs address }
        EmitB($50);
        IREmitNode(IRB[node]);                 { rhs address }
        EmitB($48); EmitB($89); EmitB($C6);    { mov rsi, rax }
        EmitB($5A);                            { pop rdx = lhs }
        EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(IRIVal[node]); { lea rdi, scratch }
        for i := 0 to 3 do
        begin
          EmitB($48); EmitB($8B); EmitB($42); EmitB(i * 8); { mov rax, [rdx+off] }
          EmitB($48); EmitB($8B); EmitB($4E); EmitB(i * 8); { mov rcx, [rsi+off] }
          case IntToTokenKind(IRC[node]) of
            tkPlus: EmitB($48); { prefix for or below }
            tkStar: EmitB($48); { prefix for and below }
            tkMinus:
              begin
                EmitB($48); EmitB($F7); EmitB($D1);        { not rcx }
                EmitB($48); EmitB($21); EmitB($C8);        { and rax, rcx }
              end;
          end;
          if IntToTokenKind(IRC[node]) = tkPlus then
            begin EmitB($09); EmitB($C8); end               { or rax, rcx }
          else if IntToTokenKind(IRC[node]) = tkStar then
            begin EmitB($21); EmitB($C8); end;              { and rax, rcx }
          EmitB($48); EmitB($89); EmitB($47); EmitB(i * 8); { mov [rdi+off], rax }
        end;
        EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(IRIVal[node]); { lea rax, scratch }
      end;

    IR_SET_CMP:
      begin
        IREmitNode(IRA[node]);                 { lhs address }
        EmitB($50);
        IREmitNode(IRB[node]);                 { rhs address }
        EmitB($48); EmitB($89); EmitB($C6);    { mov rsi, rax }
        EmitB($5A);                            { pop rdx = lhs }
        EmitB($4D); EmitB($31); EmitB($C0);    { xor r8, r8: subset violations }
        EmitB($4D); EmitB($31); EmitB($C9);    { xor r9, r9: differences }
        for i := 0 to 3 do
        begin
          EmitB($48); EmitB($8B); EmitB($42); EmitB(i * 8); { mov rax, [rdx+off] }
          EmitB($48); EmitB($8B); EmitB($4E); EmitB(i * 8); { mov rcx, [rsi+off] }
          EmitB($49); EmitB($89); EmitB($C2);                { mov r10, rax }
          EmitB($49); EmitB($31); EmitB($CA);                { xor r10, rcx }
          EmitB($4D); EmitB($09); EmitB($D1);                { or r9, r10 }
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            EmitB($49); EmitB($89); EmitB($CA);              { mov r10, rcx }
            EmitB($49); EmitB($F7); EmitB($D2);              { not r10 }
            EmitB($4C); EmitB($21); EmitB($D0);              { and rax, r10 }
            EmitB($49); EmitB($09); EmitB($C0);              { or r8, rax }
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            EmitB($49); EmitB($89); EmitB($C2);              { mov r10, rax }
            EmitB($49); EmitB($F7); EmitB($D2);              { not r10 }
            EmitB($4C); EmitB($21); EmitB($D1);              { and rcx, r10 }
            EmitB($49); EmitB($09); EmitB($C8);              { or r8, rcx }
          end;
        end;
        if IRC[node] = Ord(tkEq) then
        begin
          EmitB($4D); EmitB($85); EmitB($C9);                { test r9, r9 }
          EmitB($0F); EmitB($94); EmitB($C0);                { sete al }
        end
        else if IRC[node] = Ord(tkNeq) then
        begin
          EmitB($4D); EmitB($85); EmitB($C9);                { test r9, r9 }
          EmitB($0F); EmitB($95); EmitB($C0);                { setne al }
        end
        else
        begin
          EmitB($4D); EmitB($85); EmitB($C0);                { test r8, r8 }
          EmitB($0F); EmitB($94); EmitB($C0);                { sete al }
          if (IRC[node] = Ord(tkLt)) or (IRC[node] = Ord(tkGt)) then
          begin
            EmitB($4D); EmitB($85); EmitB($C9);              { test r9, r9 }
            EmitB($0F); EmitB($95); EmitB($C1);              { setne cl }
            EmitB($20); EmitB($C8);                          { and al, cl }
          end;
        end;
        EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);      { movzx rax, al }
      end;

    IR_EXC_LEAVE:
      begin
        IREmitLeaveExceptionFrames(IRA[node]);
      end;

    IR_RAISE:
      begin
        if IRA[node] <> -1 then
        begin
          IREmitNode(IRA[node]);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
          raiseClass := Integer(IRIVal[node]);
          MovRaxImm(raiseClass);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
        end;
        IREmitCodeCall(ExcRaiseAddr);
      end;

    IR_EXC_STORE:
      begin
        EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        EmitStoreVar(IRA[node]);
      end;

    IR_EXC_CLEAR:
      begin
        MovRaxImm(0);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
      end;

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
        begin
          if IRA[node] <> -1 then
          begin
            IREmitNode(IRA[node]);
            EmitB($48); EmitB($89); EmitB($C7);
            MovRaxImm(SYS_EXIT);
            EmitSyscall;
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
    IR_VIRTUAL_CALL:
      begin
        { IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=VMT slot }
        pi := IRC[node];
        slot := Integer(IRIVal[node]);
        argNode := IRA[node];
        pathIdx := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]); { evaluates arg -> rax }
          EmitB($50); { push rax }
          argNode := IRB[argNode];
          Inc(pathIdx);
        end;
        for i := Procs[pi].ParamCount - 1 downto 0 do
          case i of
            0: EmitB($5F); { pop rdi  (Self) }
            1: EmitB($5E); { pop rsi }
            2: EmitB($5A); { pop rdx }
            3: EmitB($59); { pop rcx }
            4: begin EmitB($41); EmitB($58); end; { pop r8 }
            5: begin EmitB($41); EmitB($59); end; { pop r9 }
          end;
        { Virtual Method Table dispatch }
        EmitB($48); EmitB($8B); EmitB($07); { mov rax, [rdi]   -- load VMT pointer }
        EmitB($FF); EmitB($90); EmitI32(slot * 8); { call [rax + slot*8] }
      end;

  else
  begin
    writeln('Unsupported linear node in IR codegen! Kind=', IRKind[node], ' node=', node,
            ' IRA=', IRA[node], ' IRB=', IRB[node], ' IRC=', IRC[node], ' IRIVal=', IRIVal[node]);
    Error('Unsupported linear node in IR codegen');
  end;
  end;
end;

procedure IREmitMachineCode;
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
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($E9);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($E9);
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNode(IRB[i]); { evaluate condition -> rax }
          EmitB($48); EmitB($85); EmitB($C0); { test rax, rax }
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($84); { jz 32-bit rel }
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

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE);
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
          EmitB($48); EmitB($89); EmitB($04); EmitB($24);
          EmitB($48); EmitB($89); EmitB($E0);
          EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
          EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
          IREmitCodeCall(ExcSetJmpAddr);
          EmitB($85); EmitB($C0);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
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

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
          EmitB($48); EmitB($3D); EmitI32(Integer(IRIVal[i]));
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
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

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNode(i);
        end;

      IR_VIRTUAL_CALL:
        begin
          { Statement-level virtual (procedure) call — result discarded. }
          if IRStmtRoot[i] then
            IREmitNode(i);
        end;

      IR_STORE_SYM, IR_STORE_MEM, IR_WRITE, IR_WRITELN,
      IR_READLINE, IR_READ_VAR, IR_COPY_REC, IR_SET_COPY, IR_VAR_STORE,
      IR_EXC_LEAVE, IR_RAISE, IR_EXC_STORE, IR_EXC_CLEAR, IR_TERMINATE,
      IR_ASM:
        begin
          IREmitNode(i);
        end;
    end;
  end;

  { Patch forward jumps }
  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in IR codegen');
    Patch32(pos, targetOffset - (pos + 4));
  end;
end;

procedure CompileAST(node: Integer);
begin
  IRReset;
  IRLowerAST(node);
  IRVerify;
  if DumpIR then IRDump;
  IREmitMachineCode;
end;
