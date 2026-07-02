{ ===== Experimental IR Machine Code Generator ===== }

procedure IREmitNode(node: Integer); forward;

procedure IREmitCodeCall(addr: Integer);
begin
  EmitB($E8);
  EmitI32(addr - (CodeLen + 4));
end;

procedure EmitAcquireHeapLock;
begin
  if ThreadSafeMode then
    EmitAsmX64([
      'push rax',
    '.spin:',
      'mov eax, 1',
      'lock xchg [@glob], eax',  BSS_HEAP_LOCK,
      'test eax, eax',
      'jnz .spin',
      'pop rax'
    ]);
end;

procedure EmitReleaseHeapLock;
begin
  if ThreadSafeMode then
    EmitAsmX64(['mov dword [@glob], 0', BSS_HEAP_LOCK]);
end;

procedure EmitHeapAllocLocked;
{ rax = requested payload bytes. Returns payload pointer in rax. Caller holds
  the heap lock when threading is enabled. }
var procIdx: Integer;
begin
  EmitAsmX64([
    'push rsi', 'push rdi', 'push rcx', 'push rdx',
    'push r8', 'push r9', 'push r10', 'push r11',
    'mov rdi, rax',      { size }
    'mov rsi, %', 8       { alignment }
  ]);
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(procIdx);                               { rax = returned pointer }
  EmitAsmX64([
    'pop r11', 'pop r10', 'pop r9', 'pop r8',
    'pop rdx', 'pop rcx', 'pop rdi', 'pop rsi'
  ]);
end;

procedure EmitHeapFreeLocked;
{ rax = payload pointer from EmitHeapAllocLocked/GetMem. Caller holds the heap
  lock when threading is enabled. nil is ignored. }
var procIdx: Integer;
begin
  EmitAsmX64([
    'push rsi', 'push rdi', 'push rcx', 'push rdx',
    'push r8', 'push r9', 'push r10', 'push r11',
    'mov rdi, rax'   { pointer }
  ]);
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(procIdx);
  EmitAsmX64([
    'pop r11', 'pop r10', 'pop r9', 'pop r8',
    'pop rdx', 'pop rcx', 'pop rdi', 'pop rsi'
  ]);
end;

procedure EmitDynArrayRetainLocked;
{ rax = dynamic-array data pointer. Preserve rax. Caller holds the heap lock
  when threading is enabled. }
begin
  EmitAsmX64([
    'test rax, rax',
    'jz .done',
    'inc qword [rax-16]',
  '.done:'
  ]);
end;

procedure EmitDynArrayRetain;
{ rax = dynamic-array data pointer. Preserve rax. }
begin
  EmitAcquireHeapLock;
  EmitDynArrayRetainLocked;
  EmitReleaseHeapLock;
end;

procedure EmitAnsiStrRetainLocked;
{ rax = managed-string data pointer. Preserve rax. Caller holds the heap lock
  when threading is enabled. }
begin
  EmitAsmX64([
    'test rax, rax',
    'jz .done',
    'inc qword [rax-16]',
  '.done:'
  ]);
end;

procedure EmitDynArrayReleaseLocked;
{ rax = dynamic-array data pointer. Decrement its refcount and return the
  allocator payload to the free list at zero. Caller holds the heap lock when
  threading is enabled.

  jz/jnz targets are patched manually (not via EmitAsmX64's `.label` form)
  because they jump past EmitHeapFreeLocked's EmitCallProc -- a label can only
  be resolved within the SAME EmitAsmX64 call that defines it (its
  label/forward-jump table resets at the start of every call), and a proc call
  can't be expressed as an asmtext line. The straight-line instructions
  themselves are still readable text, not raw opcodes. }
var pNil, pNonZero: Integer;
begin
  EmitAsmX64(['test rax, rax']);
  EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
  if ThreadSafeMode then EmitAsmX64(['lock dec qword [rax-16]'])
  else EmitAsmX64(['dec qword [rax-16]']);
  EmitB($75); pNonZero := CodeLen; EmitB(0);      { jnz done }
  EmitAsmX64(['sub rax, %', 16]);
  EmitHeapFreeLocked;
  Code[pNil] := Byte(CodeLen - (pNil + 1));
  Code[pNonZero] := Byte(CodeLen - (pNonZero + 1));
end;

procedure EmitAnsiStrReleaseLocked;
{ rax = managed-string data pointer. Caller holds the heap lock when threading
  is enabled. See EmitDynArrayReleaseLocked for why the jumps are manually
  patched rather than via EmitAsmX64 labels. }
var pNil, pNonZero: Integer;
begin
  EmitAsmX64(['test rax, rax']);
  EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
  if ThreadSafeMode then EmitAsmX64(['lock dec qword [rax-16]'])
  else EmitAsmX64(['dec qword [rax-16]']);
  EmitB($75); pNonZero := CodeLen; EmitB(0);      { jnz done }
  EmitAsmX64(['sub rax, %', 16]);
  EmitHeapFreeLocked;
  Code[pNil] := Byte(CodeLen - (pNil + 1));
  Code[pNonZero] := Byte(CodeLen - (pNonZero + 1));
end;

procedure EmitManagedRecordRetain(recId: Integer);
var procIdx: Integer;
begin
  if recId < REC_UCLASS_BASE then Exit;
  if not RecordHasManagedFields(recId) then Exit;
  procIdx := FindProc('PXXRecordRetain');
  if procIdx < 0 then Error('compiler error: PXXRecordRetain not found');

  EmitAsmX64([
    'mov rdi, rbx',
    'mov rsi, @data', -(RECORD_RTTI_DATAREF_BASE + (recId - REC_UCLASS_BASE))  { desc }
  ]);
  EmitCallProc(procIdx);
end;

procedure EmitManagedRecordReleaseLocked(recId: Integer);
var procIdx: Integer;
begin
  if recId < REC_UCLASS_BASE then Exit;
  if not RecordHasManagedFields(recId) then Exit;
  procIdx := FindProc('PXXRecordRelease');
  if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');

  EmitAsmX64([
    'mov rdi, rbx',
    'mov rsi, @data', -(RECORD_RTTI_DATAREF_BASE + (recId - REC_UCLASS_BASE))  { desc }
  ]);
  EmitCallProc(procIdx);
end;

function GetOrAllocSymRTTI(symIdx: Integer): Integer;
var anonIdx, depth, baseKind, elSize, i: Integer;
begin
  if SymRTTIOff[symIdx] >= 0 then
  begin
    Result := SymRTTIOff[symIdx];
    Exit;
  end;

  if AnonDynArrayCount >= 8192 then Error('too many anonymous dynamic arrays');
  anonIdx := AnonDynArrayCount;
  AnonDynArrayOff[anonIdx] := DataLen;
  AnonDynArrayDepth[anonIdx] := SymDynDepth[symIdx];
  AnonDynArrayBaseTk[anonIdx] := Ord(Syms[symIdx].ElemType);
  AnonDynArrayBaseRec[anonIdx] := Syms[symIdx].ElemRecName;

  depth := SymDynDepth[symIdx];
  if Syms[symIdx].ElemType = tyAnsiString then
    baseKind := 1
  else if (Syms[symIdx].ElemType = tyRecord) and RecordHasManagedFields(Syms[symIdx].ElemRecName) then
    baseKind := 3
  else
    baseKind := 0;

  if depth > 1 then
    elSize := TARGET_PTR_SIZE
  else
  begin
    if baseKind = 1 then
      elSize := TARGET_PTR_SIZE
    else if baseKind = 3 then
      elSize := UClsSize_[Syms[symIdx].ElemRecName - REC_UCLASS_BASE]
    else if Syms[symIdx].ElemType = tyRecord then
      { Unmanaged record element: TypeSize(tyRecord) is only a pointer-width
        placeholder (8); the real stride is the full record size. Using 8 here
        under-allocates the dyn array (e.g. a 2-element `array of const`/TVarRec
        gets 16 bytes, so element 1 overruns into adjacent heap and is clobbered
        by the next allocation). }
      elSize := RecSize(Syms[symIdx].ElemRecName)
    else
      elSize := TypeSize(Syms[symIdx].ElemType);
  end;
  AnonDynArrayElSize[anonIdx] := elSize;

  for i := 0 to 19 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;

  SymRTTIOff[symIdx] := AnonDynArrayOff[anonIdx];
  Inc(AnonDynArrayCount);
  Result := SymRTTIOff[symIdx];
end;

{ Descriptor for an IR_SETLEN_DYN target. Symbol root -> reuse the symbol's
  descriptor; field/nested root -> allocate an anonymous 20-byte descriptor from
  the metadata carried on the node (IRC = depth, IRTk = base type, IRSetLenBaseRec
  = base record). Target-independent: shared by all backends. rtti_emit.inc fills
  in the populated descriptor using TARGET_PTR_SIZE. }
function GetOrAllocNodeDynDesc(node: Integer): Integer;
var anonIdx, depth, baseKind, elSize, i, symIdx, baseTk, baseRec: Integer;
begin
  symIdx := Integer(IRIVal[node]);
  if symIdx >= 0 then
  begin
    Result := GetOrAllocSymRTTI(symIdx);
    Exit;
  end;
  depth := IRC[node];
  baseTk := IRTk[node];
  baseRec := IRSetLenBaseRec[node];

  if AnonDynArrayCount >= 8192 then Error('too many anonymous dynamic arrays');
  anonIdx := AnonDynArrayCount;
  AnonDynArrayOff[anonIdx] := DataLen;
  AnonDynArrayDepth[anonIdx] := depth;
  AnonDynArrayBaseTk[anonIdx] := baseTk;
  AnonDynArrayBaseRec[anonIdx] := baseRec;

  if baseTk = Ord(tyAnsiString) then
    baseKind := 1
  else if (baseTk = Ord(tyRecord)) and RecordHasManagedFields(baseRec) then
    baseKind := 3
  else
    baseKind := 0;

  if depth > 1 then
    elSize := TARGET_PTR_SIZE
  else if baseKind = 1 then
    elSize := TARGET_PTR_SIZE
  else if baseKind = 3 then
    elSize := UClsSize_[baseRec - REC_UCLASS_BASE]
  else if baseTk = Ord(tyRecord) then
    elSize := RecSize(baseRec)
  else
    elSize := TypeSize(IntToTypeKind(baseTk));
  AnonDynArrayElSize[anonIdx] := elSize;

  for i := 0 to 19 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  Inc(AnonDynArrayCount);
  Result := AnonDynArrayOff[anonIdx];
end;

{ Descriptor for an IR_DYNUNIQUE node. The node already carries the resolved
  element metadata (IRB = depth, IRTk = base type, IRC = base record,
  IRIVal = element size); allocate an anonymous 20-byte descriptor from it.
  Target-independent. }
function GetOrAllocDynUniqueDesc(node: Integer): Integer;
var anonIdx, i: Integer;
begin
  if AnonDynArrayCount >= 8192 then Error('too many anonymous dynamic arrays');
  anonIdx := AnonDynArrayCount;
  AnonDynArrayOff[anonIdx] := DataLen;
  AnonDynArrayDepth[anonIdx] := IRB[node];
  AnonDynArrayBaseTk[anonIdx] := IRTk[node];
  AnonDynArrayBaseRec[anonIdx] := IRC[node];
  AnonDynArrayElSize[anonIdx] := Integer(IRIVal[node]);
  for i := 0 to 19 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  Inc(AnonDynArrayCount);
  Result := AnonDynArrayOff[anonIdx];
end;

procedure EmitDynArrayReleaseLockedForSym(symIdx: Integer);
var procIdx: Integer;
begin
  procIdx := FindProc('PXXDynArrayRelease');
  if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');

  EmitAsmX64(['mov rdi, rax', 'mov rsi, @data', GetOrAllocSymRTTI(symIdx)]);
  EmitCallProc(procIdx);
end;

procedure EmitDynArrayReleaseForSym(symIdx: Integer);
begin
  EmitAcquireHeapLock;
  EmitDynArrayReleaseLockedForSym(symIdx);
  EmitReleaseHeapLock;
end;

procedure EmitDynArrayReleaseLockedForNode(node: Integer);
{ rax = dynamic-array data pointer. Element-aware release using a descriptor
  derived from the node's own metadata (IRC = depth, IRTk = base type,
  IRSetLenBaseRec = base record), for a non-symbol target such as a record/class
  field. Caller holds the heap lock when threading is enabled. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXDynArrayRelease');
  if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');
  EmitAsmX64(['mov rdi, rax', 'mov rsi, @data', GetOrAllocNodeDynDesc(node)]);
  EmitCallProc(procIdx);
end;

procedure EmitDynArrayReleaseForNode(node: Integer);
begin
  EmitAcquireHeapLock;
  EmitDynArrayReleaseLockedForNode(node);
  EmitReleaseHeapLock;
end;

procedure EmitDynArrayUnique(symIdx: Integer; elemSize: Integer);
var procIdx: Integer;
begin
  procIdx := FindProc('PXXDynArrayUnique');
  if procIdx < 0 then Error('compiler error: PXXDynArrayUnique not found');

  EmitAcquireHeapLock;
  EmitAsmX64(['mov rdi, rax', 'mov rsi, @data', GetOrAllocSymRTTI(symIdx)]);
  EmitCallProc(procIdx);
  EmitReleaseHeapLock;
end;

procedure EmitAnsiStrFromLiteral;
var procIdx: Integer;
begin
  AnsiStrFromLiteralAddr := CodeLen;
  { Shim: keep the historical blob contract (rdi = len, rsi = src, every GPR
    except rax preserved) but delegate the body to the Pascal helper in
    builtin.pas. rdi/rsi are already the internal call convention's first two
    argument registers, so no marshalling is needed. The callee may clobber
    any caller-visible scratch register, hence the full save set (mirrors
    EmitHeapAllocLocked). The lock wraps the whole call in threadsafe mode. }
  EmitAsmX64([
    'push rbx', 'push rcx', 'push rdx', 'push rsi', 'push rdi',
    'push r8', 'push r9', 'push r10', 'push r11'
  ]);

  EmitAcquireHeapLock;
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit helper not found in builtin unit');
  EmitCallProc(procIdx);       { rax = managed string pointer (or nil) }
  EmitReleaseHeapLock;

  EmitAsmX64([
    'pop r11', 'pop r10', 'pop r9', 'pop r8',
    'pop rdi', 'pop rsi', 'pop rdx', 'pop rcx', 'pop rbx',
    'ret'
  ]);
end;

procedure EmitDiv0Stub;
{ Shared integer-div-by-zero abort stub: write the FPC-style runtime error to
  stdout (FPC prints runtime errors to output) and exit_group(200). Pure
  syscalls, no unit dependency — the fallback target for programs that do not
  pull builtinheap (whose PXXDivZero adds the raise-hook upgrade path). Emitted
  unconditionally on x86-64, right after the entry stub. }
var si: Integer;
begin
  Div0StubAddr := CodeLen;
  si := InternStr('Runtime error 200 (division by zero)' + Chr(10));
  EmitAsmX64([
    'mov rax, %', 1,                        { sys_write }
    'mov rdi, %', 1,                        { stdout }
    'mov rsi, @data', Strs[si].Offset + 8,  { message bytes }
    'mov rdx, %', Strs[si].Len,
    'syscall',
    'mov rax, %', 231,                      { sys_exit_group }
    'mov rdi, %', 200,
    'syscall'
  ]);
end;

procedure EmitDivZeroCheckX64;
{ Pre-divide zero check for integer div/mod (divisor in rcx): 2 instructions on
  the fall-through path next to a ~20+-cycle idiv. Calls PXXDivZero (message +
  Halt(200), hook-upgradable to a raised exception) when builtinheap is in the
  program, else the unit-free Div0StubAddr — both never return. Both call forms
  are exactly 5 bytes (E8 rel32), matching the jnz +5. Opt-out: --no-div-check. }
var procIdx, callStart: Integer;
begin
  if NoDivCheck then Exit;
  EmitAsmX64([
    'test rcx, rcx',
    'jnz +5'          { over the call below — must stay exactly 5 bytes }
  ]);
  callStart := CodeLen;
  procIdx := FindProc('PXXDivZero');
  if procIdx >= 0 then
    EmitCallProc(procIdx)
  else
    IREmitCodeCall(Div0StubAddr);
  if CodeLen - callStart <> 5 then
    Error('compiler error: div-zero check call must be exactly 5 bytes (jnz +5 would land mid-instruction)');
end;

procedure EmitAnsiStringRuntime;
var pNilUnique, pNilUnique2, pDone, pDone2,
    pConcatNil, pConcatDone, pFail, pLfDone: Integer;
begin
  EmitAnsiStrFromLiteral;

  AnsiStrRetainAddr := CodeLen;
  EmitAcquireHeapLock;
  EmitAnsiStrRetainLocked;
  EmitReleaseHeapLock;
  EmitB($C3);                                     { ret }

  AnsiStrReleaseAddr := CodeLen;
  EmitAsmX64(['push rax', 'push rcx', 'push rdx', 'push rsi', 'push rdi']);
  EmitAcquireHeapLock;
  EmitAnsiStrReleaseLocked;
  EmitReleaseHeapLock;
  EmitAsmX64(['pop rdi', 'pop rsi', 'pop rdx', 'pop rcx', 'pop rax', 'ret']);

  AnsiStrUniqueAddr := CodeLen;
  EmitAsmX64(['push rbx', 'push rcx', 'push rdx', 'push rsi', 'push rdi']);

  EmitAsmX64([
    'mov rbx, rax',   { rbx = variable address }
    'mov rdi, [rbx]', { rdi = string pointer }
    'test rdi, rdi'
  ]);
  EmitB($74); pNilUnique := CodeLen; EmitB(0);     { jz done_nil }

  EmitAsmX64([
    'mov rcx, [rdi-16]', { rcx = refcount }
    'cmp rcx, %', 1
  ]);
  EmitB($76); pNilUnique2 := CodeLen; EmitB(0);    { jbe done_keep }

  { Clone path }
  EmitAsmX64([
    'mov rsi, [rdi-8]', { rsi = length }
    'mov rdx, rsi',
    'mov rsi, rdi',
    'mov rdi, rdx'
  ]);
  IREmitCodeCall(AnsiStrFromLiteralAddr);          { rax = new string pointer }

  EmitAsmX64(['push rax', 'mov rax, rsi']);        { push new string; rax = old string }
  IREmitCodeCall(AnsiStrReleaseAddr);
  EmitAsmX64(['pop rax']);                         { pop rax (new string) }

  EmitAsmX64(['mov [rbx], rax']);
  { Now rax contains the new string pointer }
  EmitB($EB); pDone := CodeLen; EmitB(0);          { jmp done }

  { done_nil path }
  Patch8(pNilUnique, CodeLen - (pNilUnique + 1));
  EmitAsmX64(['xor eax, eax']);
  EmitB($EB); pDone2 := CodeLen; EmitB(0);         { jmp done }

  { done_keep path }
  Patch8(pNilUnique2, CodeLen - (pNilUnique2 + 1));
  EmitAsmX64(['mov rax, rdi']);

  { done }
  Patch8(pDone, CodeLen - (pDone + 1));
  Patch8(pDone2, CodeLen - (pDone2 + 1));
  EmitAsmX64(['pop rdi', 'pop rsi', 'pop rdx', 'pop rcx', 'pop rbx', 'ret']);

  { rsi/lhs data, rdi/lhs length, rdx/rhs data, rcx/rhs length -> rax/string }
  { Shim → PXXStrConcat(lenA, srcA, srcB, lenB). Caller already placed the
    args in rdi/rsi/rdx/rcx (the internal call convention's first four), so
    the body just saves scratch, takes the heap lock, and delegates. }
  AnsiStrConcatAddr := CodeLen;
  EmitAsmX64([
    'push rbx', 'push rcx', 'push rdx', 'push rsi', 'push rdi',
    'push r8', 'push r9', 'push r10', 'push r11'
  ]);

  EmitAcquireHeapLock;
  pConcatNil := FindProc('PXXStrConcat');
  if pConcatNil < 0 then Error('compiler error: PXXStrConcat helper not found in builtin unit');
  EmitCallProc(pConcatNil);  { rax = result data pointer (or nil) }
  EmitReleaseHeapLock;

  EmitAsmX64([
    'pop r11', 'pop r10', 'pop r9', 'pop r8',
    'pop rdi', 'pop rsi', 'pop rdx', 'pop rcx', 'pop rbx',
    'ret'
  ]);

  { Shim → PXXStrLoadFile(path). Caller passes the path data pointer in rdi
    (param 0). Save scratch, take the heap lock for the inner PXXAlloc, call. }
  AnsiStrLoadFileAddr := CodeLen;
  EmitAsmX64([
    'push rbx', 'push rcx', 'push rdx', 'push rsi', 'push rdi',
    'push r8', 'push r9', 'push r10', 'push r11'
  ]);

  EmitAcquireHeapLock;
  pFail := FindProc('PXXStrLoadFile');
  if pFail < 0 then Error('compiler error: PXXStrLoadFile helper not found in builtin unit');
  EmitCallProc(pFail);    { rax = managed string pointer (or nil) }
  EmitReleaseHeapLock;

  EmitAsmX64([
    'pop r11', 'pop r10', 'pop r9', 'pop r8',
    'pop rdi', 'pop rsi', 'pop rdx', 'pop rcx', 'pop rbx',
    'ret'
  ]);
end;

procedure EmitLoadManagedHandleRdi(symIdx: Integer);
{ Load a managed-string variable's handle (data pointer) into rdi. }
begin
  if Syms[symIdx].Kind = skGlobal then
    EmitAsmX64(['mov rdi, [@glob]', Syms[symIdx].Offset])
  else
  begin
    EmitAsmX64(['mov rdi, [rbp+%]', Syms[symIdx].Offset]);
    if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
      EmitAsmX64(['mov rdi, [rdi]']);
  end;
end;

procedure EmitPublishManagedString(dstIdx: Integer);
{ rax = a fresh managed string (refcount already 1). Publish it into the dst
  variable, releasing dst's old handle. Handles global, local, and IsRef-param
  destinations (the IsRef case derefs the slot to reach the caller's handle). }
begin
  EmitAsmX64(['push rax']);                         { push rax (new) }
  if (Syms[dstIdx].Kind = skParam) and Syms[dstIdx].IsRef then
  begin
    EmitAsmX64([
      'mov rcx, [rbp+%]', Syms[dstIdx].Offset,       { rcx = caller slot addr }
      'mov rax, [rcx]',                              { old }
      'push rax',
      'mov rax, [rsp+8]',                             { new }
      'mov [rcx], rax',
      'pop rax'                                       { old }
    ]);
    IREmitCodeCall(AnsiStrReleaseAddr);
    EmitAsmX64(['pop rax']);                          { new (discard) }
  end
  else
  begin
    if Syms[dstIdx].Kind = skGlobal then
      EmitAsmX64(['mov rax, [@glob]', Syms[dstIdx].Offset])   { old }
    else
      EmitAsmX64(['mov rax, [rbp+%]', Syms[dstIdx].Offset]); { old }
    EmitAsmX64(['push rax', 'mov rax, [rsp+8]']);      { push old; rax = new }
    if Syms[dstIdx].Kind = skGlobal then
      EmitAsmX64(['mov [@glob], rax', Syms[dstIdx].Offset])
    else
      EmitAsmX64(['mov [rbp+%], rax', Syms[dstIdx].Offset]); { new }
    EmitAsmX64(['pop rax']);                           { old }
    IREmitCodeCall(AnsiStrReleaseAddr);
    EmitAsmX64(['pop rax']);                           { new (discard) }
  end;
end;

procedure EmitLoadFileManaged(pathIdx, dstIdx: Integer);
{ Managed LoadFile: load the file via AnsiStrLoadFile, then publish the new
  managed string into dst (releasing dst's old handle). }
begin
  EmitLoadManagedHandleRdi(pathIdx);
  IREmitCodeCall(AnsiStrLoadFileAddr);             { rax = new managed string }
  EmitPublishManagedString(dstIdx);
end;

procedure EmitArgvToStringManaged(dstIdx: Integer);
{ On entry rax = argv index. Build a managed string from argv[index] (a C
  string) and publish it into dst (releasing dst's old handle). Managed
  counterpart of EmitArgvToString. }
var inRangePatch, doneOutPatch: Integer;
begin
  { Bounds check: out-of-range index (>= argc, or negative) publishes nil (empty
    string) instead of dereferencing a bad argv slot. argc is at [initial_rsp]. }
  EmitAsmX64([
    'mov rcx, [@glob]', BSS_INITIAL_RSP,   { mov rcx, [initial_rsp] }
    'mov rcx, [rcx]',                    { rcx = argc }
    'cmp rax, rcx'
  ]);
  EmitB($72); inRangePatch := CodeLen; EmitB(0);    { jb in_range }
  EmitAsmX64(['xor rax, rax']);                     { nil handle }
  EmitPublishManagedString(dstIdx);                  { dst := '' }
  EmitB($EB); doneOutPatch := CodeLen; EmitB(0);    { jmp done }
  Code[inRangePatch] := Byte(CodeLen - (inRangePatch + 1));
  EmitAsmX64([
    'shl rax, %', 3,
    'mov rcx, [@glob]', BSS_INITIAL_RSP,
    'add rcx, %', 8,
    'add rax, rcx',
    'mov rax, [rax]',   { argv[index] }
    'mov rsi, rax'       { src }
  ]);
  { strlen(rsi) -> rcx. NOT mechanically portable: the inline loop below uses
    [rsi+rcx] (SIB base+index register addressing, a form EmitAsmX64's memory
    operand grammar doesn't support -- [base+disp]/[base+%] only) and hardcoded
    (non-Patch-tracked) short jump deltas whose values depend on the loop
    body's exact byte length, so it must stay raw EmitB unchanged. }
  EmitAsmX64(['xor rcx, rcx']);
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitAsmX64(['mov rdi, rcx']);                     { length }
  IREmitCodeCall(AnsiStrFromLiteralAddr);           { rax = new managed string }
  EmitPublishManagedString(dstIdx);
  Code[doneOutPatch] := Byte(CodeLen - (doneOutPatch + 1));
end;

procedure EmitVariantClear;
{ rax = address of a 16-byte variant slot. Release a managed payload, then
  reset the slot to VT_EMPTY. Preserves the slot address in rax. The jne
  target is patched manually (not via EmitAsmX64's `.label` form) because it
  jumps past IREmitCodeCall -- see EmitDynArrayReleaseLocked. }
var pDone: Integer;
begin
  EmitAsmX64(['push rax', 'cmp qword [rax], %', VT_STRING]);
  EmitB($0F); EmitB($85); pDone := CodeLen; EmitI32(0); { jne done }
  EmitAsmX64(['mov rax, [rax+8]']);
  IREmitCodeCall(AnsiStrReleaseAddr);
  Patch32(pDone, CodeLen - (pDone + 4));
  EmitAsmX64([
    'pop rax',
    'mov qword [rax], %', VT_EMPTY,
    'mov qword [rax+8], %', 0
  ]);
end;

procedure EmitVariantRetain;
{ rax = address of a variant slot. Retain a managed payload. Preserves rax.
  See EmitVariantClear for why the jne target is patched manually. }
var pDone: Integer;
begin
  EmitAsmX64(['push rax', 'cmp qword [rax], %', VT_STRING]);
  EmitB($0F); EmitB($85); pDone := CodeLen; EmitI32(0); { jne done }
  EmitAsmX64(['mov rax, [rax+8]']);
  IREmitCodeCall(AnsiStrRetainAddr);
  Patch32(pDone, CodeLen - (pDone + 4));
  EmitAsmX64(['pop rax']);
end;

procedure EmitAnsiStrFromInlineString;
{ rax = inline string address ([len:8][chars]). Returns a managed string ptr. }
begin
  EmitAsmX64(['mov rdi, [rax]', 'lea rsi, [rax+8]']);
  IREmitCodeCall(AnsiStrFromLiteralAddr);
end;

procedure IREmitLeaveExceptionFrames(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
    EmitAsmX64([
      'mov rax, [rsp]',
      'mov [@glob], rax', BSS_EXC_TOP,
      'add rsp, %', EXC_FRAME_SIZE
    ]);
end;

procedure IREmitStoreCharAsString;
{ rdi = destination string buffer, rsi = char ordinal. Writes a 1-char string
  ([len:8=1][char]) directly into the destination, so a tyChar value can be
  assigned to a tyString slot. No allocation — the target buffer already exists.}
begin
  EmitAsmX64([
    'mov qword [rdi], %', 1,
    'mov byte [rdi+8], sil'
  ]);
end;

procedure EmitReadLine;
{ Read one line from stdin (fd 0) into BSS_LINE_BUF, byte at a time, stopping at
  '\n' or EOF; '\r' is skipped. Sets BSS_LINE_LEN, resets BSS_LINE_POS. }
var loopStart, j1, j2, jSkip, jPeek, jHave: Integer;
begin
  EmitAsmX64([
    'mov rax, [@glob]', BSS_LINE_POS,
    'mov rcx, [@glob]', BSS_LINE_LEN,
    'cmp rax, rcx'
  ]);
  EmitB($0F); EmitB($8C); jSkip := CodeLen; EmitI32(0);                         { jl skip }

  EmitAsmX64([
    'mov qword [@glob], 0', BSS_LINE_POS,
    'mov qword [@glob], 0', BSS_LINE_LEN
  ]);
  loopStart := CodeLen;
  EmitAsmX64([
    'lea rsi, [@glob]', BSS_LINE_BUF,
    'mov rax, [@glob]', BSS_LINE_LEN,
    'add rsi, rax'
  ]);
  { If Eof left a pushed-back byte, consume it here instead of reading, so the
    byte it peeked is not lost. Otherwise read one byte from stdin (fd 0). }
  EmitAsmX64([
    'mov rax, [@glob]', BSS_PEEK_VALID,
    'test rax, rax'
  ]);
  EmitB($74); jPeek := CodeLen; EmitB(0);                                       { jz doread }
  EmitAsmX64([
    'mov al, [@glob]', BSS_PEEK_BYTE,
    'mov [rsi], al',
    'mov qword [@glob], 0', BSS_PEEK_VALID,
    'mov rax, %', 1   { count }
  ]);
  EmitB($EB); jHave := CodeLen; EmitB(0);                                       { jmp havebyte }
  Code[jPeek] := Byte(CodeLen - (jPeek + 1));                                   { doread: }
  MovRdiImm(0); MovRdxImm(1); MovRaxImm(SYS_READ); EmitSyscall;
  Code[jHave] := Byte(CodeLen - (jHave + 1));                                   { havebyte: }
  EmitAsmX64(['test rax, rax']);
  EmitB($0F); EmitB($8E); j1 := CodeLen; EmitI32(0);                           { jle done }
  EmitAsmX64(['movzx rcx, byte [rsi]', 'cmp rcx, %', 13]);
  EmitB($0F); EmitB($84); EmitI32(loopStart - (CodeLen + 4));                  { je loopStart (skip \r) }
  EmitAsmX64(['cmp rcx, %', 10]);
  EmitB($0F); EmitB($84); j2 := CodeLen; EmitI32(0);                           { je done (\n) }
  EmitAsmX64([
    'inc qword [@glob]', BSS_LINE_LEN,
    'mov rax, [@glob]', BSS_LINE_LEN,
    'cmp rax, %', LINE_BUF_SIZE - 1
  ]);
  EmitB($0F); EmitB($8C); EmitI32(loopStart - (CodeLen + 4));                  { jl loopStart }
  Patch32(j1, CodeLen - (j1 + 4));
  Patch32(j2, CodeLen - (j2 + 4));
  Patch32(jSkip, CodeLen - (jSkip + 4));
end;

procedure EmitEof;
{ Standard-input Eof: rax := 1 if stdin is at end, else 0. Boolean result.
  Not-eof if the current line buffer still holds unparsed content (pos < len) or
  a pushed-back byte is already held. Otherwise peek one byte from fd 0: a read of
  <= 0 is EOF; a real byte is stashed in BSS_PEEK_BYTE (consumed by the next
  EmitReadLine read) and reported as not-eof. }
var jNotEof1, jNotEof2, jEof, jDone1, jDone2: Integer;
begin
  { pos < len -> not eof }
  EmitAsmX64([
    'mov rax, [@glob]', BSS_LINE_POS,
    'mov rcx, [@glob]', BSS_LINE_LEN,
    'cmp rax, rcx'
  ]);
  EmitB($0F); EmitB($8C); jNotEof1 := CodeLen; EmitI32(0);                      { jl noteof }
  { peek_valid -> not eof }
  EmitAsmX64([
    'mov rax, [@glob]', BSS_PEEK_VALID,
    'test rax, rax'
  ]);
  EmitB($0F); EmitB($85); jNotEof2 := CodeLen; EmitI32(0);                      { jnz noteof }
  { peek one byte into BSS_PEEK_BYTE }
  EmitAsmX64(['lea rsi, [@glob]', BSS_PEEK_BYTE]);
  MovRdiImm(0); MovRdxImm(1); MovRaxImm(SYS_READ); EmitSyscall;
  EmitAsmX64(['test rax, rax']);
  EmitB($0F); EmitB($8E); jEof := CodeLen; EmitI32(0);                          { jle eof }
  { got a byte: mark held, report not eof }
  EmitAsmX64([
    'mov qword [@glob], 1', BSS_PEEK_VALID,
    'xor rax, rax'
  ]);
  EmitB($EB); jDone1 := CodeLen; EmitB(0);                                      { jmp done }
  Patch32(jEof, CodeLen - (jEof + 4));                                          { eof: }
  EmitAsmX64(['mov rax, %', 1]);
  EmitB($EB); jDone2 := CodeLen; EmitB(0);                                      { jmp done }
  Patch32(jNotEof1, CodeLen - (jNotEof1 + 4));                                  { noteof: }
  Patch32(jNotEof2, CodeLen - (jNotEof2 + 4));
  EmitAsmX64(['xor rax, rax']);
  Code[jDone1] := Byte(CodeLen - (jDone1 + 1));                                 { done: }
  Code[jDone2] := Byte(CodeLen - (jDone2 + 1));
end;

procedure EmitReadVarParse(tk: TTypeKind);
{ rax = target address on entry. Parse a value from the line buffer at the
  cursor by type and store it; advance the cursor. tyString takes the rest of
  the line; tyChar one byte; integer kinds skip blanks then read [-]digits. }
var sz, skipLoop, digLoop, jDone, jStart, jAdv, jDigits, jNoSign: Integer;
    jEmpty, jSign, jDigEnd, jLt, jGt: Integer;
begin
  if tk = tyAnsiString then
  begin
    { Managed readln(s): build a managed string from the rest of the line and
      publish it into the target slot (rax = slot address), releasing the old
      handle. Without this a managed string target fell through to the integer
      parser below and wrote garbage into the 8-byte handle slot. }
    EmitAsmX64([
      'push rax',                        { target addr }
      'mov rax, [@glob]', BSS_LINE_LEN,
      'sub rax, [@glob]', BSS_LINE_POS,
      'mov rdi, rax',                    { length }
      'lea rsi, [@glob]', BSS_LINE_BUF,
      'add rsi, [@glob]', BSS_LINE_POS   { src }
    ]);
    IREmitCodeCall(AnsiStrFromLiteralAddr);                                        { rax = new managed handle }
    EmitAsmX64([
      'mov rcx, [@glob]', BSS_LINE_LEN,
      'mov [@glob], rcx', BSS_LINE_POS,  { consume line }
      'push rax',                        { new; stack: new,target }
      'mov rcx, [rsp+8]',                { target addr }
      'mov rax, [rcx]',                  { old handle }
      'push rax',                        { old; stack: old,new,target }
      'mov rax, [rsp+8]',                { new }
      'mov [rcx], rax'                   { store new }
    ]);
    EmitAsmX64(['pop rax']);             { old }
    IREmitCodeCall(AnsiStrReleaseAddr);                                            { release old (nil-safe) }
    EmitAsmX64(['pop rax', 'pop rax']);  { new, target (discard) }
    Exit;
  end;
  if tk = tyString then
  begin
    EmitAsmX64([
      'mov rdi, rax',
      'mov rcx, [@glob]', BSS_LINE_LEN,
      'sub rcx, [@glob]', BSS_LINE_POS,
      'mov [rdi], rcx',
      'lea rsi, [@glob]', BSS_LINE_BUF,
      'add rsi, [@glob]', BSS_LINE_POS,
      'add rdi, %', 8,
      'rep movsb',
      'mov rax, [@glob]', BSS_LINE_LEN,
      'mov [@glob], rax', BSS_LINE_POS
    ]);
    Exit;
  end;
  if tk = tyChar then
  begin
    EmitAsmX64([
      'mov rdi, rax',
      'mov rdx, [@glob]', BSS_LINE_POS,
      'mov rcx, [@glob]', BSS_LINE_LEN,
      'xor eax, eax',
      'cmp rdx, rcx'
    ]);
    EmitB($0F); EmitB($8D); jDone := CodeLen; EmitI32(0);                         { jge nochar }
    EmitAsmX64([
      'lea rsi, [@glob]', BSS_LINE_BUF,
      'add rsi, rdx',
      'movzx rax, byte [rsi]',
      'inc rdx',
      'mov [@glob], rdx', BSS_LINE_POS
    ]);
    Patch32(jDone, CodeLen - (jDone + 4));
    EmitAsmX64(['mov [rdi], al']);
    Exit;
  end;
  { integer family: r8 = negative flag, r9 = accumulator, rdx = cursor }
  EmitAsmX64([
    'mov rdi, rax',
    'mov rdx, [@glob]', BSS_LINE_POS,
    'mov rcx, [@glob]', BSS_LINE_LEN,
    'lea rsi, [@glob]', BSS_LINE_BUF,
    'xor r8, r8',    { neg flag }
    'xor r9, r9'     { acc }
  ]);
  { skip whitespace }
  skipLoop := CodeLen;
  EmitAsmX64(['cmp rdx, rcx']);
  EmitB($0F); EmitB($8D); jEmpty := CodeLen; EmitI32(0);                          { jge applysign (empty) }
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] -- SIB index, not mechanically portable }
  EmitAsmX64(['cmp rax, %', 32]);
  EmitB($0F); EmitB($84); jAdv := CodeLen; EmitI32(0);                            { je advws }
  EmitAsmX64(['cmp rax, %', 9]);
  EmitB($0F); EmitB($85); jStart := CodeLen; EmitI32(0);                          { jne startsign }
  { advws: }
  Patch32(jAdv, CodeLen - (jAdv + 4));
  EmitAsmX64(['inc rdx']);
  EmitB($E9); EmitI32(skipLoop - (CodeLen + 4));                                  { jmp skipLoop }
  { startsign: }
  Patch32(jStart, CodeLen - (jStart + 4));
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] -- SIB index, not mechanically portable }
  EmitAsmX64(['cmp rax, %', 45]);                                                { '-' }
  EmitB($0F); EmitB($85); jSign := CodeLen; EmitI32(0);                           { jne digits }
  EmitAsmX64(['mov r8, %', 1, 'inc rdx']);
  { digits: }
  Patch32(jSign, CodeLen - (jSign + 4));
  digLoop := CodeLen;
  EmitAsmX64(['cmp rdx, rcx']);
  EmitB($0F); EmitB($8D); jDigEnd := CodeLen; EmitI32(0);                         { jge applysign }
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($16);                    { movzx rax,byte[rsi+rdx] -- SIB index, not mechanically portable }
  EmitAsmX64(['cmp rax, %', 48]);
  EmitB($0F); EmitB($8C); jLt := CodeLen; EmitI32(0);                             { jl applysign }
  EmitAsmX64(['cmp rax, %', 57]);
  EmitB($0F); EmitB($8F); jGt := CodeLen; EmitI32(0);                             { jg applysign }
  EmitB($4D); EmitB($6B); EmitB($C9); EmitB($0A);                                { imul r9,r9,10 -- 3-operand imul+imm not supported, isolated single site }
  EmitAsmX64(['sub rax, %', 48, 'add r9, rax', 'inc rdx']);
  EmitB($E9); EmitI32(digLoop - (CodeLen + 4));                                   { jmp digLoop }
  { applysign: }
  Patch32(jEmpty,  CodeLen - (jEmpty + 4));
  Patch32(jDigEnd, CodeLen - (jDigEnd + 4));
  Patch32(jLt,     CodeLen - (jLt + 4));
  Patch32(jGt,     CodeLen - (jGt + 4));
  EmitAsmX64(['test r8, r8']);
  EmitB($0F); EmitB($84); jNoSign := CodeLen; EmitI32(0);                         { jz nosign }
  EmitAsmX64(['neg r9']);
  { nosign: }
  Patch32(jNoSign, CodeLen - (jNoSign + 4));
  EmitAsmX64(['mov rax, r9', 'mov [@glob], rdx', BSS_LINE_POS]);
  sz := TypeSize(tk);
  if sz = 1 then EmitAsmX64(['mov [rdi], al'])
  else if sz = 2 then EmitAsmX64(['mov [rdi], ax'])
  else if sz = 4 then EmitAsmX64(['mov [rdi], eax'])
  else EmitAsmX64(['mov [rdi], rax']);
end;

procedure EmitLoadVariantAddress(node: Integer);
var symIdx, addressNode: Integer;
begin
  if IRKind[node] = IR_LOAD_SYM then
  begin
    symIdx := IRA[node];
    if Syms[symIdx].Kind = skGlobal then
      EmitAsmX64(['lea rax, [@glob]', Syms[symIdx].Offset])
    else if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
      EmitAsmX64(['mov rax, [rbp+%]', Syms[symIdx].Offset])
    else
      EmitAsmX64(['lea rax, [rbp+%]', Syms[symIdx].Offset]);
  end
  else if IRKind[node] = IR_LOAD_MEM then
  begin
    addressNode := IRA[node];
    IREmitNode(addressNode);
  end
  else
  begin
    IREmitNode(node);
  end;
end;

procedure EmitWriteVariant;
{ On entry rax = address of a 16-byte variant slot: [tag:8][payload:8].
  Reads the tag and dispatches to the matching scalar writer. Clobbers the
  caller-saved set like the other write helpers; balances its own stack. }
var pInt, pInt64, pBool, pDbl, pChar, pStr, pNil, jmpDefault, pEnd1, pEnd2, pEnd3: Integer;
begin
  EmitAsmX64(['push rax', 'mov rax, [rax]']);  { [rsp]=addr; rax=tag }

  EmitAsmX64(['cmp rax, %', VT_INT]);
  EmitB($0F); EmitB($84); pInt := CodeLen; EmitI32(0);
  EmitAsmX64(['cmp rax, %', VT_INT64]);
  EmitB($0F); EmitB($84); pInt64 := CodeLen; EmitI32(0);
  EmitAsmX64(['cmp rax, %', VT_BOOL]);
  EmitB($0F); EmitB($84); pBool := CodeLen; EmitI32(0);
  EmitAsmX64(['cmp rax, %', VT_DOUBLE]);
  EmitB($0F); EmitB($84); pDbl := CodeLen; EmitI32(0);
  EmitAsmX64(['cmp rax, %', VT_CHAR]);
  EmitB($0F); EmitB($84); pChar := CodeLen; EmitI32(0);
  EmitAsmX64(['cmp rax, %', VT_STRING]);
  EmitB($0F); EmitB($84); pStr := CodeLen; EmitI32(0);
  EmitB($E9); jmpDefault := CodeLen; EmitI32(0);   { default (empty/object): nothing }

  { integer/bool: payload as signed int64 }
  Patch32(pInt,   CodeLen - (pInt   + 4));
  Patch32(pInt64, CodeLen - (pInt64 + 4));
  Patch32(pBool,  CodeLen - (pBool  + 4));
  EmitAsmX64(['mov rax, [rsp]', 'mov rax, [rax+8]']);   { addr; payload }
  EmitwriteInt;
  EmitB($E9); pEnd1 := CodeLen; EmitI32(0);

  { double: payload bits -> xmm0 }
  Patch32(pDbl, CodeLen - (pDbl + 4));
  EmitAsmX64(['mov rax, [rsp]', 'mov rax, [rax+8]', 'movq xmm0, rax']);
  EmitWriteFloatNat;
  EmitB($E9); pEnd2 := CodeLen; EmitI32(0);

  { char: payload low byte }
  Patch32(pChar, CodeLen - (pChar + 4));
  EmitAsmX64(['mov rax, [rsp]', 'movzx eax, byte [rax+8]']);
  EmitwriteChar;
  EmitB($E9); pEnd3 := CodeLen; EmitI32(0);

  { managed string: payload points after the refcount/length header }
  Patch32(pStr, CodeLen - (pStr + 4));
  EmitAsmX64([
    'mov rax, [rsp]',
    'mov rax, [rax+8]',
    'test rax, rax'
  ]);
  EmitB($0F); EmitB($84); pNil := CodeLen; EmitI32(0); { jz Lend }
  EmitAsmX64(['mov rsi, rax', 'mov rdx, [rax-8]']);
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;

  { Lend }
  Patch32(pNil, CodeLen - (pNil + 4));
  Patch32(jmpDefault, CodeLen - (jmpDefault + 4));
  Patch32(pEnd1, CodeLen - (pEnd1 + 4));
  Patch32(pEnd2, CodeLen - (pEnd2 + 4));
  Patch32(pEnd3, CodeLen - (pEnd3 + 4));
  EmitAsmX64(['add rsp, %', 8]);   { discard addr }
end;

procedure EmitSetcc(opTk: Integer; signed: Boolean);
{ Flags already set (cmp / comisd). Emit setcc al + movzx eax,al -> rax = 0/1.
  signed=True for integer cmp; False (unsigned/comisd) for double comisd. }
var mnem: AnsiString;
begin
  if signed then
  begin
    if      opTk = Ord(tkLt)  then mnem := 'setl al'
    else if opTk = Ord(tkLe)  then mnem := 'setle al'
    else if opTk = Ord(tkGt)  then mnem := 'setg al'
    else if opTk = Ord(tkGe)  then mnem := 'setge al'
    else if opTk = Ord(tkEq)  then mnem := 'sete al'
    else if opTk = Ord(tkNeq) then mnem := 'setne al'
    else begin Error('Variant compare: unsupported operator'); mnem := ''; end;
  end
  else
  begin
    if      opTk = Ord(tkLt)  then mnem := 'setb al'
    else if opTk = Ord(tkLe)  then mnem := 'setbe al'
    else if opTk = Ord(tkGt)  then mnem := 'seta al'
    else if opTk = Ord(tkGe)  then mnem := 'setae al'
    else if opTk = Ord(tkEq)  then mnem := 'sete al'
    else if opTk = Ord(tkNeq) then mnem := 'setne al'
    else begin Error('Variant compare: unsupported operator'); mnem := ''; end;
  end;
  EmitAsmX64([mnem, 'movzx eax, al']);
end;

procedure EmitVarBinOp(opTk, resultOff: Integer; isCompare: Boolean);
{ rdi = left variant addr, rsi = right variant addr. Closed double-dispatch:
  both integer-class -> integer op (preserves int); any VT_DOUBLE -> double op.
  isCompare -> Boolean 0/1 in rax; else Variant result at BSS[resultOff], addr in rax. }
var pDbl1, pDbl2, pDoneInt, pLi, pRi, pLd, pRd, pForceDbl: Integer;
    pIsStr1, pIsStr2, pIsStr3, pIsStr4, pNumericPath: Integer;
    pLhsOk, pRhsOk, pDiffTags1, pDiffTags2: Integer;
    pLhsStrCmp, pLhsCharCmp, pLhsDoneCmp, pLhsDone2Cmp, pLhsDone3Cmp, pLhsNilCmp: Integer;
    pRhsStrCmp, pRhsCharCmp, pRhsDoneCmp, pRhsDone2Cmp, pRhsDone3Cmp, pRhsNilCmp: Integer;
    pLhsStrConcat, pLhsCharConcat, pLhsDoneConcat, pLhsDone2Concat, pLhsDone3Concat, pLhsNilConcat: Integer;
    pRhsStrConcat, pRhsCharConcat, pRhsDoneConcat, pRhsDone2Concat, pRhsDone3Concat, pRhsNilConcat: Integer;
    pDoneStr1, pDoneStr2, pDoneStr3: Integer;
begin
  pIsStr1 := -1; pIsStr2 := -1; pIsStr3 := -1; pIsStr4 := -1;
  pNumericPath := -1;
  pDoneStr1 := -1; pDoneStr2 := -1; pDoneStr3 := -1;

  if isCompare or (opTk = Ord(tkPlus)) then
  begin
    { --- String check --- }
    EmitB($48); EmitB($8B); EmitB($07);                       { mov rax, [rdi] }
    EmitB($48); EmitB($3D); EmitI32(VT_STRING);               { cmp rax, VT_STRING }
    EmitB($0F); EmitB($84); pIsStr1 := CodeLen; EmitI32(0);   { je L_is_str_op }
    EmitB($48); EmitB($3D); EmitI32(VT_CHAR);                 { cmp rax, VT_CHAR }
    EmitB($0F); EmitB($84); pIsStr2 := CodeLen; EmitI32(0);   { je L_is_str_op }

    EmitB($48); EmitB($8B); EmitB($06);                       { mov rax, [rsi] }
    EmitB($48); EmitB($3D); EmitI32(VT_STRING);               { cmp rax, VT_STRING }
    EmitB($0F); EmitB($84); pIsStr3 := CodeLen; EmitI32(0);   { je L_is_str_op }
    EmitB($48); EmitB($3D); EmitI32(VT_CHAR);                 { cmp rax, VT_CHAR }
    EmitB($0F); EmitB($84); pIsStr4 := CodeLen; EmitI32(0);   { je L_is_str_op }

    { If we reach here, neither side is stringy -> go to numeric path }
    EmitB($E9); pNumericPath := CodeLen; EmitI32(0);          { jmp L_numeric_path }

    { L_is_str_op }
    Patch32(pIsStr1, CodeLen - (pIsStr1 + 4));
    Patch32(pIsStr2, CodeLen - (pIsStr2 + 4));
    Patch32(pIsStr3, CodeLen - (pIsStr3 + 4));
    Patch32(pIsStr4, CodeLen - (pIsStr4 + 4));

    if isCompare then
    begin
      { Compare tags first }
      EmitB($48); EmitB($8B); EmitB($07);                       { mov rax, [rdi] }
      EmitB($48); EmitB($8B); EmitB($0E);                       { mov rcx, [rsi] }
      
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_CHAR);
      EmitB($74); pLhsOk := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_STRING);
      EmitB($0F); EmitB($85); pDiffTags1 := CodeLen; EmitI32(0);   { jne L_diff_tags }
      
      { L_lhs_ok }
      Code[pLhsOk] := Byte(CodeLen - (pLhsOk + 1));
      EmitB($48); EmitB($83); EmitB($F9); EmitB(VT_CHAR);
      EmitB($74); pRhsOk := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F9); EmitB(VT_STRING);
      EmitB($0F); EmitB($85); pDiffTags2 := CodeLen; EmitI32(0);   { jne L_diff_tags }
      
      { L_rhs_ok }
      Code[pRhsOk] := Byte(CodeLen - (pRhsOk + 1));

      { Extract LHS details from rdi }
      EmitB($56);                                               { push rsi }
      EmitB($48); EmitB($8B); EmitB($07);                       { mov rax, [rdi] }
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_STRING);     { cmp rax, VT_STRING }
      EmitB($74); pLhsStrCmp := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_CHAR);       { cmp rax, VT_CHAR }
      EmitB($74); pLhsCharCmp := CodeLen; EmitB(0);
      
      EmitB($31); EmitB($F6);                                   { xor esi, esi }
      EmitB($31); EmitB($D2);                                   { xor edx, edx }
      EmitB($EB); pLhsDoneCmp := CodeLen; EmitB(0);
      
      Patch8(pLhsCharCmp, CodeLen - (pLhsCharCmp + 1));
      EmitB($48); EmitB($8D); EmitB($77); EmitB($08);           { lea rsi, [rdi+8] }
      EmitB($48); EmitB($C7); EmitB($C2); EmitI32(1);           { mov rdx, 1 }
      EmitB($EB); pLhsDone2Cmp := CodeLen; EmitB(0);
      
      Patch8(pLhsStrCmp, CodeLen - (pLhsStrCmp + 1));
      EmitB($48); EmitB($8B); EmitB($77); EmitB($08);           { mov rsi, [rdi+8] }
      EmitB($48); EmitB($85); EmitB($F6);                       { test rsi, rsi }
      EmitB($74); pLhsNilCmp := CodeLen; EmitB(0);
      EmitB($48); EmitB($8B); EmitB($56); EmitB($F8);           { mov rdx, [rsi-8] }
      EmitB($EB); pLhsDone3Cmp := CodeLen; EmitB(0);
      Patch8(pLhsNilCmp, CodeLen - (pLhsNilCmp + 1));
      EmitB($31); EmitB($F6);                                   { xor esi, esi }
      EmitB($31); EmitB($D2);                                   { xor edx, edx }
      
      Patch8(pLhsDoneCmp, CodeLen - (pLhsDoneCmp + 1));
      Code[pLhsDone2Cmp] := Byte(CodeLen - (pLhsDone2Cmp + 1));
      Code[pLhsDone3Cmp] := Byte(CodeLen - (pLhsDone3Cmp + 1));

      { Pop RHS Variant address to r8 }
      EmitB($41); EmitB($58);                                   { pop r8 }

      { Extract RHS details from r8 }
      EmitB($41); EmitB($8B); EmitB($00);                       { mov eax, [r8] }
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_STRING);     { cmp rax, VT_STRING }
      EmitB($74); pRhsStrCmp := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_CHAR);       { cmp rax, VT_CHAR }
      EmitB($74); pRhsCharCmp := CodeLen; EmitB(0);
      
      EmitB($31); EmitB($FF);                                   { xor edi, edi }
      EmitB($45); EmitB($31); EmitB($C9);                       { xor r9d, r9d }
      EmitB($EB); pRhsDoneCmp := CodeLen; EmitB(0);
      
      Patch8(pRhsCharCmp, CodeLen - (pRhsCharCmp + 1));
      EmitB($49); EmitB($8D); EmitB($78); EmitB($08);           { lea rdi, [r8+8] }
      EmitB($41); EmitB($C7); EmitB($C1); EmitI32(1);           { mov r9d, 1 }
      EmitB($EB); pRhsDone2Cmp := CodeLen; EmitB(0);
      
      Patch8(pRhsStrCmp, CodeLen - (pRhsStrCmp + 1));
      EmitB($49); EmitB($8B); EmitB($78); EmitB($08);           { mov rdi, [r8+8] }
      EmitB($48); EmitB($85); EmitB($FF);                       { test rdi, rdi }
      EmitB($74); pRhsNilCmp := CodeLen; EmitB(0);
      EmitB($4C); EmitB($8B); EmitB($4F); EmitB($F8);           { mov r9, [rdi-8] }
      EmitB($EB); pRhsDone3Cmp := CodeLen; EmitB(0);
      Patch8(pRhsNilCmp, CodeLen - (pRhsNilCmp + 1));
      EmitB($31); EmitB($FF);                                   { xor edi, edi }
      EmitB($45); EmitB($31); EmitB($C9);                       { xor r9d, r9d }
      
      Patch8(pRhsDoneCmp, CodeLen - (pRhsDoneCmp + 1));
      Code[pRhsDone2Cmp] := Byte(CodeLen - (pRhsDone2Cmp + 1));
      Code[pRhsDone3Cmp] := Byte(CodeLen - (pRhsDone3Cmp + 1));

      { Compare }
      EmitB($48); EmitB($89); EmitB($D1);                       { mov rcx, rdx }
      EmitB($4C); EmitB($39); EmitB($CA);                       { cmp rdx, r9 }
      EmitB($76); EmitB($03);                                   { jbe +3 }
      EmitB($4C); EmitB($89); EmitB($C9);                       { mov rcx, r9 }
      EmitB($48); EmitB($85); EmitB($C9);                       { test rcx, rcx }
      EmitB($74); EmitB($06);                                   { jz +6 }
      EmitB($F3); EmitB($A6);                                   { repe cmpsb }
      EmitB($74); EmitB($02);                                   { je +2 }
      EmitB($EB); EmitB($03);                                   { jmp +3 }
      EmitB($4C); EmitB($39); EmitB($CA);                       { cmp rdx, r9 }
      EmitSetcc(opTk, False);
      EmitB($E9); pDoneStr2 := CodeLen; EmitI32(0);             { jmp L_done_str }

      { L_diff_tags }
      Patch32(pDiffTags1, CodeLen - (pDiffTags1 + 4));
      Patch32(pDiffTags2, CodeLen - (pDiffTags2 + 4));
      if opTk = Ord(tkNeq) then
        MovRaxImm(1)
      else
        MovRaxImm(0);
      EmitB($E9); pDoneStr1 := CodeLen; EmitI32(0);             { jmp L_done_str }
    end
    else
    begin
      { LHS string/char details from rdi -> r8 (data), r9 (len) }
      EmitB($48); EmitB($8B); EmitB($07);                       { mov rax, [rdi] }
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_STRING);     { cmp rax, VT_STRING }
      EmitB($74); pLhsStrConcat := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_CHAR);       { cmp rax, VT_CHAR }
      EmitB($74); pLhsCharConcat := CodeLen; EmitB(0);
      
      EmitB($4D); EmitB($31); EmitB($C0);                       { xor r8, r8 }
      EmitB($4D); EmitB($31); EmitB($C9);                       { xor r9, r9 }
      EmitB($EB); pLhsDoneConcat := CodeLen; EmitB(0);
      
      Patch8(pLhsCharConcat, CodeLen - (pLhsCharConcat + 1));
      EmitB($4C); EmitB($8D); EmitB($47); EmitB($08);           { lea r8, [rdi+8] }
      EmitB($49); EmitB($C7); EmitB($C1); EmitI32(1);           { mov r9, 1 }
      EmitB($EB); pLhsDone2Concat := CodeLen; EmitB(0);
      
      Patch8(pLhsStrConcat, CodeLen - (pLhsStrConcat + 1));
      EmitB($48); EmitB($8B); EmitB($47); EmitB($08);           { mov rax, [rdi+8] }
      EmitB($48); EmitB($85); EmitB($C0);                       { test rax, rax }
      EmitB($74); pLhsNilConcat := CodeLen; EmitB(0);
      EmitB($48); EmitB($8B); EmitB($48); EmitB($F8);           { mov rcx, [rax-8] }
      EmitB($49); EmitB($89); EmitB($C0);                       { mov r8, rax }
      EmitB($49); EmitB($89); EmitB($C9);                       { mov r9, rcx }
      EmitB($EB); pLhsDone3Concat := CodeLen; EmitB(0);
      
      Patch8(pLhsNilConcat, CodeLen - (pLhsNilConcat + 1));
      EmitB($4D); EmitB($31); EmitB($C0);                       { xor r8, r8 }
      EmitB($4D); EmitB($31); EmitB($C9);                       { xor r9, r9 }
      
      Patch8(pLhsDoneConcat, CodeLen - (pLhsDoneConcat + 1));
      Code[pLhsDone2Concat] := Byte(CodeLen - (pLhsDone2Concat + 1));
      Code[pLhsDone3Concat] := Byte(CodeLen - (pLhsDone3Concat + 1));

      { RHS string/char details from rsi -> r10 (data), r11 (len) }
      EmitB($48); EmitB($8B); EmitB($06);                       { mov rax, [rsi] }
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_STRING);     { cmp rax, VT_STRING }
      EmitB($74); pRhsStrConcat := CodeLen; EmitB(0);
      EmitB($48); EmitB($83); EmitB($F8); EmitB(VT_CHAR);       { cmp rax, VT_CHAR }
      EmitB($74); pRhsCharConcat := CodeLen; EmitB(0);
      
      EmitB($4D); EmitB($31); EmitB($D2);                       { xor r10, r10 }
      EmitB($4D); EmitB($31); EmitB($DB);                       { xor r11, r11 }
      EmitB($EB); pRhsDoneConcat := CodeLen; EmitB(0);
      
      Patch8(pRhsCharConcat, CodeLen - (pRhsCharConcat + 1));
      EmitB($4C); EmitB($8D); EmitB($56); EmitB($08);           { lea r10, [rsi+8] }
      EmitB($49); EmitB($C7); EmitB($C3); EmitI32(1);           { mov r11, 1 }
      EmitB($EB); pRhsDone2Concat := CodeLen; EmitB(0);
      
      Patch8(pRhsStrConcat, CodeLen - (pRhsStrConcat + 1));
      EmitB($48); EmitB($8B); EmitB($46); EmitB($08);           { mov rax, [rsi+8] }
      EmitB($48); EmitB($85); EmitB($C0);                       { test rax, rax }
      EmitB($74); pRhsNilConcat := CodeLen; EmitB(0);
      EmitB($48); EmitB($8B); EmitB($48); EmitB($F8);           { mov rcx, [rax-8] }
      EmitB($49); EmitB($89); EmitB($C2);                       { mov r10, rax }
      EmitB($49); EmitB($89); EmitB($CB);                       { mov r11, rcx }
      EmitB($EB); pRhsDone3Concat := CodeLen; EmitB(0);
      
      Patch8(pRhsNilConcat, CodeLen - (pRhsNilConcat + 1));
      EmitB($4D); EmitB($31); EmitB($D2);                       { xor r10, r10 }
      EmitB($4D); EmitB($31); EmitB($DB);                       { xor r11, r11 }

      Patch8(pRhsDoneConcat, CodeLen - (pRhsDoneConcat + 1));
      Code[pRhsDone2Concat] := Byte(CodeLen - (pRhsDone2Concat + 1));
      Code[pRhsDone3Concat] := Byte(CodeLen - (pRhsDone3Concat + 1));

      EmitB($4C); EmitB($89); EmitB($C6);                       { mov rsi, r8 }
      EmitB($4C); EmitB($89); EmitB($CF);                       { mov rdi, r9 }
      EmitB($4C); EmitB($89); EmitB($D2);                       { mov rdx, r10 }
      EmitB($4C); EmitB($89); EmitB($D9);                       { mov rcx, r11 }
      IREmitCodeCall(AnsiStrConcatAddr);

      EmitB($50);                                                                   { push rax }
      EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(resultOff);       { lea rax,[result] }
      EmitVariantClear;
      EmitB($59);                                                                   { pop rcx }
      EmitB($48); EmitB($C7); EmitB($00); EmitI32(VT_STRING);                       { mov qword[rax],VT_STRING }
      EmitB($48); EmitB($89); EmitB($48); EmitB($08);                               { mov [rax+8],rcx }

      EmitB($E9); pDoneStr3 := CodeLen; EmitI32(0);             { jmp L_done_str }
    end;

  { L_numeric_path }
  if pNumericPath >= 0 then
    Patch32(pNumericPath, CodeLen - (pNumericPath + 4));
  end;

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

  { L_done_str: }
  if isCompare or (opTk = Ord(tkPlus)) then
  begin
    if isCompare then
    begin
      Patch32(pDoneStr1, CodeLen - (pDoneStr1 + 4));
      Patch32(pDoneStr2, CodeLen - (pDoneStr2 + 4));
    end
    else
    begin
      Patch32(pDoneStr3, CodeLen - (pDoneStr3 + 4));
    end;
  end;
end;

procedure EmitWriteCStr;
{ rax = pointer to NUL-terminated chars (a PChar). Compute its length and write
  it to stdout. x86-64 only — the targets that lack a hosted write syscall never
  reach a write path. Fully expressed through the EmitAsmX64 text assembler,
  including the strlen scan loop (back/forward label jumps). }
begin
  EmitAsmX64(['mov rsi, rax',        { rsi = buffer (kept for the write) }
              'xor rcx, rcx',        { rcx = length }
              'scan:',
              'cmp byte [rax], 0',   { rax = scan cursor, starts at buffer }
              'je done',
              'inc rax',
              'inc rcx',
              'jmp scan',
              'done:',
              'mov rdx, rcx',        { rdx = count }
              'mov rax, %', SYS_WRITE,
              'mov rdi, %', STDOUT,
              'syscall']);
end;

procedure IREmitNode(node: Integer);
var left, right, valNode, symIdx, si, nextJmp2, pNil: Integer;
    op: TTokenKind;
    cmpUnsigned, isAnsiStr, savedLValueWrite: Boolean;
    sVal: AnsiString;
    tk, lhsTk, rhsTk: TTypeKind;
    size: Integer;
    isSigned: Boolean;
    baseAddr, indexNode, lo, elemSize, offset, addressNode, valueNode: Integer;
    argNode, pathIdx, procIdx, specialId, classIdx, slot, cpi, i, jbePatch, anonIdx: Integer;
    asmGfK: Integer; asmGfFound: Boolean;
    searchTop, pJzBump, pJaeTake, pJmpDone, pJbeNoGrow, pFreeNil, pNotDouble, pDone: Integer;
    pAnsiAlloc, pAnsiShared, pAnsiTooSmall, pAnsiNoZeroGrow, pAnsiFastDone: Integer;
    pAnsiUseNeededNil, pAnsiUseNeededSmall, pAnsiMinDone, pAnsiCapDone: Integer;
    pDynZero, pDynNoOld, pDynKeepCopy, pDynNoRetain, pDynNoRetainCount: Integer;
    slDepth, slElemSize, slRetainTop, pSlRetainDone, slBaseRec: Integer;
    slBaseTk: TTypeKind;
    wid, decs: Integer;
    arg1Node, arg2Node, arg3Node, val1Node, val2Node: Integer;
    itemNode, trueCount, nextJmp, falseJmp: Integer;
    trueJumps: array[0..127] of Integer;
    raiseClass: Integer;
    intIdx, sseIdx, nArgs, mStack, padBytes, extIdx, restoreOff, vaPopN: Integer;
    argIsSse: array[0..127] of Boolean;
    argIsStack: array[0..127] of Boolean;
    argRegIdx: array[0..127] of Integer;
    argNodeArr: array[0..127] of Integer;
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
        { @proc -> load a function-pointer value. Internal routines use a
          finalized code-address fixup; imported routines load from the dynamic
          GOT on supported targets. }
        if ProcExternal[IRA[node]] then
        begin
          EmitExternalProcAddr(IRA[node]);
          Exit;
        end;
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

    IR_VMTADDR:
      { rax = address of class ci's VMT (the per-class identity stored at
        [instance+0]). VMT offsets are final at codegen (emitted during parse),
        so the data-ref is direct — same as instance construction. }
      begin EmitB($48); EmitB($B8); EmitDataRef(UClsVMTOffset[IRA[node]]); end;

    IR_IMTADDR:
      { rax = address of the (class,interface) IMT for fat-pointer construction. }
      begin EmitB($48); EmitB($B8); EmitDataRef(IMTOff[IRA[node]]); end;

    IR_SET_LIT:
      begin
        EmitB($48); EmitB($B8); EmitDataRef(IRIVal[node]);
      end;
      
    IR_ASM:
      { Blit the buffered bytes 1:1, except at a recorded global-var operand
        fixup: AsmParseOperand/EncModRMAbs couldn't call EmitGlobRef at parse
        time (AsmBytes offsets aren't final code positions), so they left a
        4-byte zero placeholder and a (AsmOff, BSSoff) entry in AsmGlobFix.
        Here CodeLen is finally correct, so call the real EmitGlobRef instead
        of copying those 4 placeholder bytes literally. }
      begin
        i := 0;
        while i < IRB[node] do
        begin
          asmGfFound := False;
          for asmGfK := 0 to AsmGlobFixCount - 1 do
            if AsmGlobFix[asmGfK].AsmOff = IRA[node] + i then
            begin
              EmitGlobRef(AsmGlobFix[asmGfK].BSSoff);
              asmGfFound := True;
            end;
          if asmGfFound then Inc(i, 4)
          else begin EmitB(AsmBytes[IRA[node] + i]); Inc(i); end;
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

    IR_SYSCALL:
      begin
        { Raw syscall: args (nr, a0..a5) evaluated left-to-right onto the
          stack, then popped into rax, rdi, rsi, rdx, r10, r8, r9 (Linux
          x86-64 syscall convention). Result stays in rax. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]);
          EmitB($50); { push rax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          case i of
            0: EmitB($58);                        { pop rax }
            1: EmitB($5F);                        { pop rdi }
            2: EmitB($5E);                        { pop rsi }
            3: EmitB($5A);                        { pop rdx }
            4: begin EmitB($41); EmitB($5A); end; { pop r10 }
            5: begin EmitB($41); EmitB($58); end; { pop r8 }
            6: begin EmitB($41); EmitB($59); end; { pop r9 }
          end;
        EmitB($0F); EmitB($05); { syscall }
      end;

    IR_COSWITCH:
      begin
        { __pxxcoswitch(pfrom, pto): evaluate both pointer args left-to-right
          onto the stack, pop into rdi (pfrom) / rsi (pto), then call the bare
          CoSwitch stub. }
        argNode := IRA[node];
        IREmitNode(IRA[argNode]);  EmitB($50);   { pfrom -> push rax }
        argNode := IRB[argNode];
        IREmitNode(IRA[argNode]);  EmitB($50);   { pto   -> push rax }
        EmitB($5E);                              { pop rsi = pto }
        EmitB($5F);                              { pop rdi = pfrom }
        IREmitCodeCall(CoSwitchAddr);
      end;

    IR_CLONE:
      begin
        { __pxxclone(flags, childStack, entry, arg, ctidptr): evaluate the five
          args left-to-right onto the stack, pop into the SysV arg regs
          rdi/rsi/rdx/rcx/r8 (the stub's input contract), then call the bare
          clone+trampoline stub. Result (child tid) stays in rax. The stub is
          emitted lazily (jmp-over) the first time we get here. }
        EnsureCloneStub;
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]);
          EmitB($50); { push rax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          case i of
            0: EmitB($5F);                        { pop rdi  (flags) }
            1: EmitB($5E);                        { pop rsi  (childStack) }
            2: EmitB($5A);                        { pop rdx  (entry) }
            3: EmitB($59);                        { pop rcx  (arg) }
            4: begin EmitB($41); EmitB($58); end; { pop r8   (ctidptr) }
          end;
        IREmitCodeCall(CloneStubAddr);
      end;

    IR_ATOMIC:
      begin
        { 32-bit atomic read-modify-write on addr^. Args evaluated left-to-right
          onto the stack; addr -> rcx, operands -> eax (+ edx for CAS). Old value
          returned in eax (auto zero-extends to rax). }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]);
          EmitB($50); { push rax }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        case IRIVal[node] of
          ATOMIC_CAS:
            begin
              { stack (top..bottom): newval, expected, addr }
              EmitB($5A);                 { pop rdx  (newval) }
              EmitB($58);                 { pop rax  (expected) }
              EmitB($59);                 { pop rcx  (addr) }
              EmitB($F0); EmitB($0F); EmitB($B1); EmitB($11); { lock cmpxchg [rcx], edx }
            end;                          { eax = old *addr }
          ATOMIC_ADD:
            begin
              { stack: delta, addr }
              EmitB($58);                 { pop rax  (delta) }
              EmitB($59);                 { pop rcx  (addr) }
              EmitB($F0); EmitB($0F); EmitB($C1); EmitB($01); { lock xadd [rcx], eax }
            end;                          { eax = old *addr }
          else { ATOMIC_XCHG }
            begin
              { stack: val, addr }
              EmitB($58);                 { pop rax  (val) }
              EmitB($59);                 { pop rcx  (addr) }
              EmitB($87); EmitB($01);     { xchg [rcx], eax  (implicitly locked) }
            end;                          { eax = old *addr }
        end;
      end;

    IR_YIELD:
      begin
        { Evaluate the yielded value into rax, store it into the instance's
          current slot, then CoSwitch back to the consumer. IRIVal = the
          generator's hidden self-pointer local sym idx. }
        IREmitNode(IRA[node]);                    { rax = value }
        { rcx = self }
        EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[IRIVal[node]].Offset); { mov rcx, [rbp+selfOff] }
        EmitB($48); EmitB($89); EmitB($41); EmitB(CO_OFF_CURRENT);              { mov [rcx+CURRENT], rax }
        EmitB($48); EmitB($8D); EmitB($79); EmitB(CO_OFF_GENCTX);               { lea rdi, [rcx+genctx]   (from) }
        EmitB($48); EmitB($8D); EmitB($71); EmitB(CO_OFF_CALLERCTX);            { lea rsi, [rcx+callerctx] (to) }
        IREmitCodeCall(CoSwitchAddr);
      end;

    IR_CALL_IND:
      begin
        cpi := IRIVal[node];                       { signature proc index }
        nArgs := Procs[cpi].ParamCount + IRC[node]; { + injected Self for method ptr }
        if (cpi >= 0) and ProcCdecl[cpi] then
        begin
          { System V (cdecl) indirect call through a `cdecl` proc-type value:
            integer/pointer args -> rdi,rsi,rdx,rcx,r8,r9; floating args ->
            xmm0..xmm7 (classes counted independently); callee through r11; the
            stack 16-byte-aligned at the call (libc SSE code requires it). Stack
            spill (>6 int / >8 float), by-value structs and varargs are not
            modelled yet. Lets a dlsym'd C function with float args call right. }
          intIdx := 0; sseIdx := 0;
          argNode := IRB[node]; i := 0;
          while argNode <> -1 do
          begin
            if i >= MAX_CALL_ARGS then Error('cdecl indirect call: too many arguments');
            argNodeArr[i] := IRA[argNode];
            { Self (i < IRC, injected for a method ptr) is a pointer -> int class. }
            if (i >= IRC[node]) and TypeIsFloat(Procs[cpi].Params[i - IRC[node]].TypeKind) then
            begin argIsSse[i] := True; Inc(sseIdx); end
            else begin argIsSse[i] := False; Inc(intIdx); end;
            argNode := IRB[argNode]; Inc(i);
          end;
          if intIdx > 6 then Error('cdecl indirect call: more than 6 integer args not supported yet');
          if sseIdx > 8 then Error('cdecl indirect call: more than 8 float args not supported yet');
          IREmitNode(IRA[node]); EmitB($50);       { push callee (deepest) }
          for i := nArgs - 1 downto 0 do
          begin
            IREmitNode(argNodeArr[i]); EmitB($50); { push arg }
          end;
          intIdx := 0; sseIdx := 0;
          for i := 0 to nArgs - 1 do
            if argIsSse[i] then
            begin
              EmitB($58);                          { pop rax }
              EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0 + sseIdx * 8); { movq xmm[n], rax }
              if (i >= IRC[node]) and (Procs[cpi].Params[i - IRC[node]].TypeKind = tySingle) then
                begin EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0 + sseIdx * 9); end; { cvtsd2ss xmm,xmm }
              Inc(sseIdx);
            end
            else
            begin
              case intIdx of
                0: EmitB($5F);                      { pop rdi }
                1: EmitB($5E);                      { pop rsi }
                2: EmitB($5A);                      { pop rdx }
                3: EmitB($59);                      { pop rcx }
                4: begin EmitB($41); EmitB($58); end; { pop r8 }
                5: begin EmitB($41); EmitB($59); end; { pop r9 }
              end;
              Inc(intIdx);
            end;
          { rsp now points at the callee. Align and call through it; the saved rsp
            (P, where [P]=callee) lives in the slot pushed below. }
          EmitB($49); EmitB($89); EmitB($E3);       { mov r11, rsp  (r11 = P) }
          EmitB($48); EmitB($83); EmitB($E4); EmitB($F0); { and rsp, -16 }
          EmitB($41); EmitB($53);                   { push r11  ([rsp]=P) }
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08); { sub rsp, 8  (16-align) }
          EmitB($B8); EmitI32(sseIdx);              { mov eax, #vector-regs (vararg ABI) }
          EmitB($4C); EmitB($8B); EmitB($5C); EmitB($24); EmitB($08); { mov r11, [rsp+8] = P }
          EmitB($4D); EmitB($8B); EmitB($1B);       { mov r11, [r11] = callee }
          EmitB($41); EmitB($FF); EmitB($D3);       { call r11 }
          EmitB($48); EmitB($8B); EmitB($64); EmitB($24); EmitB($08); { mov rsp, [rsp+8] = P }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08); { add rsp, 8  (pop callee) }
          if TypeIsFloat(Procs[cpi].RetType) then
          begin
            if Procs[cpi].RetType = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0); end; { cvtss2sd xmm0,xmm0 }
            EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
          end;
        end
        else
        begin
          { Internal Pascal convention (all args in integer registers, <=6).
            Evaluate the callee first and keep it deepest on the stack so arg
            evaluation cannot clobber it; pop args into the ABI registers, then
            pop the callee into r11 and call. }
          if nArgs > 6 then
            Error('indirect call with more than 6 parameters is not supported');
          IREmitNode(IRA[node]); EmitB($50);         { push rax = callee addr }
          argNode := IRB[node];
          while argNode <> -1 do
          begin
            IREmitNode(IRA[argNode]);
            EmitB($50);                              { push rax }
            argNode := IRB[argNode];
          end;
          for i := nArgs - 1 downto 0 do
            case i of
              0: EmitB($5F);                          { pop rdi }
              1: EmitB($5E);                          { pop rsi }
              2: EmitB($5A);                          { pop rdx }
              3: EmitB($59);                          { pop rcx }
              4: begin EmitB($41); EmitB($58); end;   { pop r8 }
              5: begin EmitB($41); EmitB($59); end;   { pop r9 }
            end;
          if IRCallDest[node] >= 0 then
          begin
            { aggregate / frozen-string result via the hidden dest in r10 }
            IREmitNode(IRCallDest[node]);
            EmitB($49); EmitB($89); EmitB($C2);       { mov r10, rax }
          end;
          EmitB($41); EmitB($5B);                     { pop r11 = callee }
          EmitB($41); EmitB($FF); EmitB($D3);         { call r11 }
        end;
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
          { Move semantics: a fresh user-function result already carries the +1
            destined for this owner (it was retained by the callee's
            `Result := X` and excluded from the callee's scope-exit release), so
            retaining again here would leak one reference. Intrinsic results
            (IRA < 0) keep the conservative retain. }
          if not ((IRKind[IRB[node]] = IR_CALL) and (IRA[IRB[node]] >= 0)) then
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
          EmitDynArrayReleaseForSym(symIdx);
          EmitB($58);                             { pop rax = new data pointer }
        end
        else if Syms[symIdx].TypeKind = tyAnsiString then
        begin
          valueNode := IRB[node];
          if (IRKind[valueNode] = IR_CALL) and (IRA[valueNode] = -Ord(tkArgStr)) then
          begin
            { managed ParamStr/ArgStr: build a managed string from argv[i] and
              publish into dst. The value-build path below would otherwise emit the
              1-arg ArgStr call, whose codegen expects the 2-arg statement form. }
            argNode := IRB[valueNode];
            IREmitNode(IRA[argNode]);   { rax = argv index }
            EmitArgvToStringManaged(symIdx);
          end
          else
          begin
          if IRKind[valueNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valueNode], IRB[valueNode]);
            si := InternStr(sVal);
            EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
            EmitB($48); EmitB($BF); EmitI64(Strs[si].Len);
            IREmitCodeCall(AnsiStrFromLiteralAddr);
          end
          else
          begin
            IREmitNode(valueNode);
            if IntToTypeKind(IRTk[valueNode]) = tyChar then
            begin
              EmitB($50);                                     { push rax (char code) }
              EmitB($48); EmitB($89); EmitB($E6);             { mov rsi, rsp }
              EmitB($48); EmitB($C7); EmitB($C7); EmitI32(1);  { mov rdi, 1 }
              IREmitCodeCall(AnsiStrFromLiteralAddr);
              EmitB($59);                                     { pop rcx (restore stack) }
            end
            else if TypeIsFrozenString(IntToTypeKind(IRTk[valueNode])) then
            begin
              { Any frozen inline string source (tyString, or a tyFixedString
                reached e.g. through a pointer deref `p^` that escapes the
                StrValTk value-kind normalisation) materialises into a managed
                handle. Without this a tyFixedString source fell through to the
                bogus retain path and stored an empty/garbage handle. }
              EmitAnsiStrFromInlineString;
            end
            else if not (((IRKind[valueNode] = IR_BINOP) and
                          (IntToTypeKind(IRTk[valueNode]) = tyAnsiString)) or
                         ((IRKind[valueNode] = IR_CALL) and (IRA[valueNode] >= 0))) then
            begin
              { A concat result (BINOP) or a fresh user-function result (IR_CALL,
                IRA >= 0) is already refcount 1 for this owner — move it instead
                of retaining, otherwise the handle leaks one reference. }
              IREmitCodeCall(AnsiStrRetainAddr);
            end;
          end;
          EmitB($50);                             { push new pointer }
          if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
          begin
            { by-ref (var/out) managed string: the param slot holds the ADDRESS
              of the caller's handle slot. Release the old handle there, publish
              the new one into the caller's slot — not the local param copy. }
            EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[symIdx].Offset); { mov rcx, [rbp+off] = caller slot addr }
            EmitB($48); EmitB($8B); EmitB($01);                               { mov rax, [rcx] = old }
            EmitB($50);                             { push old pointer }
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08);       { mov rax, [rsp+8] = new }
            EmitB($48); EmitB($89); EmitB($01);                               { mov [rcx], rax }
            EmitB($58);                             { pop rax = old pointer }
            IREmitCodeCall(AnsiStrReleaseAddr);
            EmitB($58);                             { pop rax = new pointer }
          end
          else
          begin
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($50);                             { push old pointer }
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($58);                             { pop rax = old pointer }
            IREmitCodeCall(AnsiStrReleaseAddr);
            EmitB($58);                             { pop rax = new pointer }
          end;
          end;
        end
        else if TypeIsFrozenString(Syms[symIdx].TypeKind) and not Syms[symIdx].IsArray then
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
            else if IntToTypeKind(IRTk[valueNode]) = tyAnsiString then
            begin
              { Managed source -> frozen inline dest (e.g. fx: string[N] := managedStr):
                rsi = handle (char pointer), length at [rsi-8]. Materialise into the
                inline [len][chars] buffer at rdi. nil handle -> empty string. }
              EmitB($48); EmitB($85); EmitB($F6);              { test rsi, rsi }
              EmitB($74); pNil := CodeLen; EmitB(0);            { jz empty }
              EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);  { mov rcx, [rsi-8] = len }
              EmitB($48); EmitB($89); EmitB($0F);              { mov [rdi], rcx (length word) }
              EmitB($48); EmitB($83); EmitB($C7); EmitB($08);  { add rdi, 8 (dest chars) }
              EmitB($F3); EmitB($A4);                           { rep movsb (rsi already at chars) }
              EmitB($EB); pDone := CodeLen; EmitB(0);           { jmp done }
              Code[pNil] := Byte(CodeLen - (pNil + 1));         { empty: }
              EmitB($48); EmitB($C7); EmitB($07); EmitI32(0);  { mov qword [rdi], 0 }
              Code[pDone] := Byte(CodeLen - (pDone + 1));       { done: }
            end
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
            A float-typed RHS is bit-copied (movq); an integer-typed RHS into a
            float slot is converted (cvtsi2sd) — `d := 1` / `d := n`. Branching on
            the VALUE node's type (not just the dest) keeps already-float RHS
            unchanged, avoiding the over-broad `+0.0` coercion that broke
            self-fixedpoint before. See feature-int-to-float-assign. }
          if TypeIsFloat(Syms[IRA[node]].TypeKind) then
          begin
            if TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); end  { movq xmm0, rax }
            else
              begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C0); end; { cvtsi2sd xmm0, rax }
          end;
          EmitStoreVar(IRA[node]);
        end;
      end;

    IR_LEA:
      begin
        symIdx := IRA[node];
        if Syms[symIdx].Kind = skGlobal then
        begin
          { Dynamic array slot holds a heap data pointer; load it (mov), not its
             address (lea), so indexing/Length operate on the heap block. A
             scalar AnsiString slot is likewise a heap pointer. But a *static*
             array of AnsiString is laid out inline: its symbol address is the
             array base, so it must use a plain lea (else branch). }
          if (Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1)) or
             ((Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray) then
          begin
            if InLValueWrite then
              begin EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end;
          end
          else
            begin EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end;
        end
        else
        begin
          if (Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1)) or
             ((Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray) or
             ((Syms[symIdx].Kind = skParam) and
              (Syms[symIdx].IsRef or Syms[symIdx].IsArray or
               TypeIsFrozenString(Syms[symIdx].TypeKind) or (Syms[symIdx].TypeKind = tySet))) then
          begin
            if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef and
               Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1) then
            begin
              { by-ref (var/out) named-dynamic-array param: the slot holds the
                ADDRESS of the caller's handle slot. Load it once → &caller_slot
                (what COW/SetLength want, a write); on a read deref once more to
                reach the data pointer (what Length/indexing want). }
              EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); { mov rax,[rbp+off] = &caller_slot }
              if not InLValueWrite then
                begin EmitB($48); EmitB($8B); EmitB($00); end;                  { mov rax,[rax] = data ptr }
            end
            else if InLValueWrite and (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef and
               (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
              { by-ref (var/out) managed string write: the param slot holds the
                ADDRESS of the caller's handle slot; load it so AnsiStrUnique/COW
                operate on the caller's handle in place, not the local param copy.
                (The read path is unchanged — handled via EmitLoadVar elsewhere.) }
              begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); end
            else if InLValueWrite and
               (((Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray) or
                (Syms[symIdx].IsArray and (Syms[symIdx].ArrLen = -1))) then
              { lea rax,[rbp+off]: address of a genuinely LOCAL slot (scalar
                AnsiString var, or a local dynamic array's handle slot -- both
                need their own address, not a dereference). Excluding IsArray
                from the TypeKind=tyAnsiString disjunct matters because an
                array symbol's TypeKind holds its ELEMENT type: without the
                guard, a var/out array-of-AnsiString PARAMETER (element type
                tyAnsiString, but IsArray -- its slot holds a FORWARDED
                pointer, not the data itself) wrongly matched here and got the
                address of its own local param slot instead of a dereference,
                silently discarding every write on return and reading/
                releasing whatever garbage the "old value" load found at that
                address (bug-var-array-of-ansistring-param-loses-writes).
                Mirrors the same not-IsArray guard already used two branches
                up (the scalar var/out AnsiString write path). }
              begin EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset); end
            else
              begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
          end
          else
          begin
            EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset);
          end;
        end;
      end;

    IR_DYNDATA:
      begin
        { Load the data pointer stored in a dyn-array slot (always a load, never
          a lea — used as the base of nested-array indexing regardless of
          InLValueWrite). }
        symIdx := IRA[node];
        if Syms[symIdx].Kind = skGlobal then
          begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
        else
          begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
      end;

    IR_ZERO_SYM:
      begin
        symIdx := IRA[node];
        if (Syms[symIdx].Kind = skLocal) and SymNeedsZeroing(symIdx, size) then
        begin
          if size = TARGET_PTR_SIZE then
          begin
            EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[symIdx].Offset); EmitI32(0); { mov qword [rbp+off], 0 }
          end
          else if size > 0 then
          begin
            EmitB($48); EmitB($8D); EmitB($BD); EmitI32(Syms[symIdx].Offset);  { lea rdi, [rbp+off] }
            EmitB($48); EmitB($31); EmitB($C0);                           { xor rax, rax }
            EmitB($48); EmitB($C7); EmitB($C1); EmitI32(size);            { mov rcx, size }
            EmitB($F3); EmitB($AA);                                       { rep stosb }
          end;
        end;
      end;

    IR_DEFAULT_MEM:
      begin
        IREmitNode(IRA[node]);                  { rax = destination address }
        if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
        begin
          EmitB($50);                           { preserve destination }
          EmitAcquireHeapLock;
          EmitB($48); EmitB($8B); EmitB($1C); EmitB($24); { mov rbx, [rsp] }
          EmitManagedRecordReleaseLocked(IRC[node]);
          EmitReleaseHeapLock;
          EmitB($5F);                           { pop rdi = destination }
        end
        else
          begin EmitB($48); EmitB($89); EmitB($C7); end; { mov rdi, rax }
        EmitB($48); EmitB($31); EmitB($C0);              { xor rax, rax }
        EmitB($48); EmitB($B9); EmitI64(IRIVal[node]);   { movabs rcx, byte count }
        EmitB($F3); EmitB($AA);                          { rep stosb }
      end;

    IR_SLOTADDR:
      begin
        { Address of a variable's slot, unconditionally (plain lea). Unlike
          IR_LEA this never auto-loads a dyn-array/AnsiString handle, so it is a
          safe base for IR_DYNUNIQUE in both read and write mode. }
        symIdx := IRA[node];
        if Syms[symIdx].Kind = skGlobal then
          begin EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
        else
          begin EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
      end;

    IR_DYNUNIQUE:
      begin
        { Nested-array copy-on-write. IRA gives the address of the slot holding
          this level's array handle. On a read, just load the data pointer; on a
          write (InLValueWrite, set across the whole LHS address chain), clone
          the level if it is shared, publishing the unique handle back into the
          slot, so a write through one alias never mutates the other. Recursion
          up the chain happens naturally: IRA is itself an IR_DYNUNIQUE / element
          address that was emitted under the same InLValueWrite. }
        IREmitNode(IRA[node]);                  { rax = slot address }
        if InLValueWrite then
        begin
          if AnonDynArrayCount >= 8192 then Error('too many anonymous dynamic arrays');
          AnonDynArrayOff[AnonDynArrayCount] := DataLen;
          AnonDynArrayDepth[AnonDynArrayCount] := IRB[node];
          AnonDynArrayBaseTk[AnonDynArrayCount] := IRTk[node];
          AnonDynArrayBaseRec[AnonDynArrayCount] := IRC[node];
          AnonDynArrayElSize[AnonDynArrayCount] := Integer(IRIVal[node]);

          for i := 0 to 19 do
          begin
            if DataLen >= MAX_DATA then Error('data overflow');
            Data[DataLen] := 0;
            Inc(DataLen);
          end;

          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax  (arrSlot) }
          EmitB($48); EmitB($BE); EmitDataRef(AnonDynArrayOff[AnonDynArrayCount]); { mov rsi, desc }

          Inc(AnonDynArrayCount);

          procIdx := FindProc('PXXDynArrayUnique');
          if procIdx < 0 then Error('compiler error: PXXDynArrayUnique not found');
          EmitAcquireHeapLock;
          EmitCallProc(procIdx);
          EmitReleaseHeapLock;
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($00); end;  { mov rax, [rax] }
      end;

    IR_INDEX:
      begin
        baseAddr := IRA[node];
        indexNode := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);

        IREmitNode(baseAddr);

        { COW check for managed strings and dynamic arrays. }
        isAnsiStr := False;
        if IRKind[baseAddr] = IR_LEA then
        begin
          symIdx := IRA[baseAddr];
          if (symIdx >= 0) and not Syms[symIdx].IsArray and
             (Syms[symIdx].TypeKind = tyAnsiString) then
            isAnsiStr := True;
        end
        else if ((IRKind[baseAddr] = IR_FIELD) or (IRKind[baseAddr] = IR_INDEX)) and
                (IRTk[baseAddr] = Ord(tyAnsiString)) and (elemSize = 1) then
        begin
          { Char-indexing a scalar AnsiString field or array element (s[i]) uses
            a 1-byte stride and needs copy-on-write. }
          isAnsiStr := True;
        end;

        if isAnsiStr and InLValueWrite then
        begin
          IREmitCodeCall(AnsiStrUniqueAddr);
        end
        else if isAnsiStr and ((IRKind[baseAddr] = IR_FIELD) or (IRKind[baseAddr] = IR_INDEX)) then
        begin
          { IR_FIELD/IR_INDEX yields the address of the managed-string slot. Reads
            need the heap data pointer stored in that slot; writes above
            deliberately pass the slot address to AnsiStrUnique. }
          EmitB($48); EmitB($8B); EmitB($00);     { mov rax,[rax] }
        end
        else if isAnsiStr and (IRKind[baseAddr] = IR_LEA) and
                (Syms[IRA[baseAddr]].Kind = skParam) and Syms[IRA[baseAddr]].IsRef then
        begin
          { by-ref managed string read: IR_LEA yields the forwarded slot address;
            deref to the handle so indexing uses the data pointer, not the slot.
            (Writes were handled above: AnsiStrUnique wants the slot address.) }
          EmitB($48); EmitB($8B); EmitB($00);     { mov rax,[rax] }
        end;
        if InLValueWrite and (IRKind[baseAddr] = IR_LEA) then
        begin
          symIdx := IRA[baseAddr];
          if (symIdx >= 0) and Syms[symIdx].IsArray and
             (Syms[symIdx].ArrLen = -1) then
            EmitDynArrayUnique(symIdx, elemSize);
        end;

        EmitB($50); { push rax }
        
        savedLValueWrite := InLValueWrite;
        InLValueWrite := False;
        IREmitNode(indexNode); { rax = index }
        InLValueWrite := savedLValueWrite;
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

        { A Single field/element is a 4-byte float; the IR value model carries
          floats as DOUBLE bits, so load the 4-byte single and widen (cvtss2sd),
          mirroring the per-variable Single load. Without this the raw 4-byte load
          treats single bits as the low dword of a double = garbage
          (bug-single-field-element-in-aggregate). }
        if tk = tySingle then
        begin
          EmitB($66); EmitB($0F); EmitB($6E); EmitB($00);       { movd xmm0, [rax] }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);       { cvtss2sd xmm0, xmm0 }
          EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
          Exit;
        end;

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

    IR_STORE_DYN:
      begin
        { ARC-correct whole dyn-array store into a slot ADDRESS (record/class
          field or nested sub-array). Mirrors the IR_STORE_SYM IDENT path: retain
          the new handle (unless it is a fresh function result already carrying
          +1), publish it into the slot, then element-aware release the old
          handle. The new handle is kept on the stack across the release call,
          which (like IR_STORE_SYM's release) leaves [rsp] intact. }
        valueNode := IRB[node];
        IREmitNode(valueNode);                       { rax = new data pointer }
        if not ((IRKind[valueNode] = IR_CALL) and (IRA[valueNode] >= 0)) then
          EmitDynArrayRetain;
        EmitB($50);                                  { push new }
        IREmitNode(IRA[node]);                       { rax = slot address }
        EmitB($50);                                  { push slot; [rsp+8]=new }
        EmitB($48); EmitB($8B); EmitB($00);          { mov rax, [rax]  (old) }
        EmitB($50);                                  { push old; [rsp+8]=slot,[rsp+16]=new }
        EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($10); { mov rax,[rsp+16] (new) }
        EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($08); { mov rcx,[rsp+8]  (slot) }
        EmitB($48); EmitB($89); EmitB($01);          { mov [rcx], rax  (slot := new) }
        EmitB($58);                                  { pop rax (old); [rsp]=slot,[rsp+8]=new }
        EmitDynArrayReleaseForNode(node);            { release old (preserves [rsp]) }
        EmitB($59);                                  { pop rcx (discard slot) }
        EmitB($58);                                  { pop rax (new = result) }
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

          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode(addressNode); { rax = destination address }
          InLValueWrite := savedLValueWrite;

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
        else if tk = tyAnsiString then
        begin
          if IRKind[valueNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valueNode], IRB[valueNode]);
            si := InternStr(sVal);
            EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
            EmitB($48); EmitB($BF); EmitI64(Strs[si].Len);
            IREmitCodeCall(AnsiStrFromLiteralAddr);
          end
          else
          begin
            IREmitNode(valueNode);
            if IntToTypeKind(IRTk[valueNode]) = tyChar then
            begin
              EmitB($50);                                     { push rax (char code) }
              EmitB($48); EmitB($89); EmitB($E6);             { mov rsi, rsp }
              EmitB($48); EmitB($C7); EmitB($C7); EmitI32(1);  { mov rdi, 1 }
              IREmitCodeCall(AnsiStrFromLiteralAddr);
              EmitB($59);                                     { pop rcx (restore stack) }
            end
            else if TypeIsFrozenString(IntToTypeKind(IRTk[valueNode])) then
            begin
              { Any frozen inline string source (tyString, or a tyFixedString
                reached e.g. through a pointer deref `p^` that escapes the
                StrValTk value-kind normalisation) materialises into a managed
                handle. Without this a tyFixedString source fell through to the
                bogus retain path and stored an empty/garbage handle. }
              EmitAnsiStrFromInlineString;
            end
            else if not (((IRKind[valueNode] = IR_BINOP) and
                          (IntToTypeKind(IRTk[valueNode]) = tyAnsiString)) or
                         ((IRKind[valueNode] = IR_CALL) and (IRA[valueNode] >= 0))) then
            begin
              { A concat result (BINOP) or a fresh user-function result (IR_CALL,
                IRA >= 0) is already refcount 1 for this owner — move it instead
                of retaining, otherwise the handle leaks one reference. }
              IREmitCodeCall(AnsiStrRetainAddr);
            end;
          end;
          EmitB($50); { push rax (new string) }
          
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode(addressNode); { rax = destination address }
          InLValueWrite := savedLValueWrite;
          
          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          EmitB($48); EmitB($8B); EmitB($37); { mov rsi, [rdi] }
          EmitB($48); EmitB($8B); EmitB($04); EmitB($24); { mov rax, [rsp] }
          EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
          
          EmitB($48); EmitB($89); EmitB($F0); { mov rax, rsi }
          IREmitCodeCall(AnsiStrReleaseAddr);
          EmitB($58); { pop rax (new string) }
        end
        else
        begin
          IREmitNode(valueNode);
          EmitB($50); { push rax -- value }

          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode(addressNode); { rax = address }
          InLValueWrite := savedLValueWrite;

          EmitB($59); { pop rcx -- value }

          { Integer value stored into a float field/element: convert (cvtsi2sd)
            rather than bit-copy. A float-typed value is already double-bits and
            falls through unchanged. Mirrors the IR_STORE_SYM path. See
            feature-int-to-float-assign. }
          if TypeIsFloat(tk) and not TypeIsFloat(IntToTypeKind(IRTk[valueNode])) then
          begin
            EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C9); { cvtsi2sd xmm1, rcx }
            EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C9); { movq rcx, xmm1 }
          end;

          { A Single field/element is a 4-byte float slot; the value in rcx is
            DOUBLE bits, so narrow to single (cvtsd2ss) before the 4-byte store —
            else the low dword of the double is stored = garbage. Mirrors the
            per-variable Single store (bug-single-field-element-in-aggregate). }
          if tk = tySingle then
          begin
            EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C9); { movq xmm1, rcx }
            EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C9);             { cvtsd2ss xmm1, xmm1 }
            EmitB($66); EmitB($0F); EmitB($7E); EmitB($C9);             { movd ecx, xmm1 }
          end;

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
        
        if (IntToTypeKind(IRTk[node]) = tyAnsiString) and (op = tkPlus) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          EmitB($50); { push lhs value }
          EmitB($51); { push rhs value }

          if rhsTk = tyAnsiString then
          begin
            EmitB($48); EmitB($8B); EmitB($14); EmitB($24); { mov rdx, [rsp] }
            EmitB($31); EmitB($C9);                         { xor ecx, ecx }
            EmitB($48); EmitB($85); EmitB($D2);             { test rdx, rdx }
            EmitB($74); EmitB($04);                         { jz +4 }
            EmitB($48); EmitB($8B); EmitB($4A); EmitB($F8); { mov rcx, [rdx-8] }
          end
          else if rhsTk = tyString then
          begin
            EmitB($48); EmitB($8B); EmitB($14); EmitB($24); { mov rdx, [rsp] }
            EmitB($48); EmitB($8B); EmitB($0A);             { mov rcx, [rdx] }
            EmitB($48); EmitB($83); EmitB($C2); EmitB($08); { add rdx, 8 }
          end
          else
          begin
            EmitB($48); EmitB($8D); EmitB($14); EmitB($24); { lea rdx, [rsp] }
            EmitB($B9); EmitI32(1);                         { mov ecx, 1 }
          end;

          if lhsTk = tyAnsiString then
          begin
            EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi, [rsp+8] }
            EmitB($31); EmitB($FF);                                     { xor edi, edi }
            EmitB($48); EmitB($85); EmitB($F6);                         { test rsi, rsi }
            EmitB($74); EmitB($04);                                     { jz +4 }
            EmitB($48); EmitB($8B); EmitB($7E); EmitB($F8);             { mov rdi, [rsi-8] }
          end
          else if lhsTk = tyString then
          begin
            EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi, [rsp+8] }
            EmitB($48); EmitB($8B); EmitB($3E);                         { mov rdi, [rsi] }
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08);             { add rsi, 8 }
          end
          else
          begin
            EmitB($48); EmitB($8D); EmitB($74); EmitB($24); EmitB($08); { lea rsi, [rsp+8] }
            EmitB($BF); EmitI32(1);                                     { mov edi, 1 }
          end;

          IREmitCodeCall(AnsiStrConcatAddr);
          EmitB($50); { preserve concat result while releasing owned children }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($10); { mov rax, [rsp+16] }
            IREmitCodeCall(AnsiStrReleaseAddr);
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] }
            IREmitCodeCall(AnsiStrReleaseAddr);
          end;
          EmitB($58);                                     { pop concat result }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($10); { add rsp, 16 }
        end
        else if (IntToTypeKind(IRTk[node]) = tyString) and (op = tkPlus) then
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
              EmitDivZeroCheckX64;
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
            end;
          tkMod:
            begin
              EmitDivZeroCheckX64;
              if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then
                begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
              else
                begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
              EmitB($48); EmitB($89); EmitB($D0); { mov rax, rdx }
            end;
          tkAnd:   begin EmitB($48); EmitB($21); EmitB($C8); end; { and rax, rcx }
          tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end; { or rax, rcx }
          tkXor:   begin EmitB($48); EmitB($31); EmitB($C8); end; { xor rax, rcx }
          { Logical `shr` on a <=32-bit operand: the value is sign-extended in rax,
            so a 64-bit shr leaks the sign bits down (bug-shr-signed-integer-width:
            Integer(-8) shr 1 gave a 64-bit result). Zero-extend the operand to 32
            bits first (`mov eax, eax` clears the upper half of rax) so the logical
            shift brings in zeros; genuine 64-bit operands shift as-is. `shl` has
            the analogous 32-bit-wrap gap (Integer(1) shl 31 should be
            -2147483648) but can't be fixed by an operand-width check until the
            Int64/UInt64 typecast propagates an 8-byte IRTk — otherwise
            `UInt64(1) shl 40` (IRTk understated to 32-bit) would wrongly truncate
            to 0. See bug-shl-signed-integer-width. }
          tkIdent:
            begin
              if TypeSize(IntToTypeKind(IRTk[left])) < 8 then
                begin EmitB($89); EmitB($C0); end;            { mov eax, eax (zero-extend) }
              EmitB($48); EmitB($D3); EmitB($E8);             { shr rax, cl }
            end;
          { C signed `>>` (bug-c-signed-arith-shift-right): arithmetic shift,
            sign-extending. Mirrors the logical `shr` case above but with a
            sign-extend (`cdqe`) instead of a zero-extend for a <8-byte
            operand, and `sar` instead of `shr` (ModRM /7 vs /5). }
          tkShr:
            begin
              if TypeSize(IntToTypeKind(IRTk[left])) < 8 then
                begin EmitB($48); EmitB($98); end;            { cdqe (sign-extend) }
              EmitB($48); EmitB($D3); EmitB($F8);             { sar rax, cl }
            end;
          { `shl` in a 64-bit register on a <8-byte operand leaves a value shifted
            into bit 31 looking positive (1 shl 31 read 2147483648, not
            -2147483648). Re-derive the narrow result from the low 32 bits: cdqe
            sign-extends for a signed operand, `mov eax,eax` zero-extends for an
            unsigned one. 64-bit operands (incl. UInt64(...) casts, now tagged
            8-byte by ir.inc) shift as-is. See bug-shl-signed-integer-width. }
          tkShl:
            begin
              EmitB($48); EmitB($D3); EmitB($E0);             { shl rax, cl }
              if TypeSize(IntToTypeKind(IRTk[left])) < 8 then
              begin
                if TypeSigned(IntToTypeKind(IRTk[left])) then
                  begin EmitB($48); EmitB($98); end           { cdqe }
                else
                  begin EmitB($89); EmitB($C0); end;          { mov eax, eax }
              end;
            end;

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
                 ((IntToTypeKind(IRTk[left]) = tyAnsiString) or
                  (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
              begin
                lhsTk := IntToTypeKind(IRTk[left]);
                rhsTk := IntToTypeKind(IRTk[right]);
                if (lhsTk = tyAnsiString) and (rhsTk = tyChar) then
                begin
                  EmitB($51);                                                  { push rcx }
                  EmitB($48); EmitB($85); EmitB($C0);
                  EmitB($0F); EmitB($84); nextJmp := CodeLen; EmitI32(0);      { jz not_equal }
                  EmitB($48); EmitB($8B); EmitB($48); EmitB($F8);              { mov rcx, [rax-8] }
                  EmitB($48); EmitB($83); EmitB($F9); EmitB($01);              { cmp rcx, 1 }
                  EmitB($0F); EmitB($85); nextJmp2 := CodeLen; EmitI32(0);     { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($08);              { movzx rcx, byte [rax] }
                  EmitB($58);                                                  { pop rax }
                  EmitB($48); EmitB($39); EmitB($C1);                          { cmp rcx, rax }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  Patch32(nextJmp2, CodeLen - (nextJmp2 + 4));
                  EmitB($59);                                                  { pop rcx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else if (lhsTk = tyChar) and (rhsTk = tyAnsiString) then
                begin
                  EmitB($50);                                                  { push rax }
                  EmitB($48); EmitB($85); EmitB($C9);
                  EmitB($0F); EmitB($84); nextJmp := CodeLen; EmitI32(0);      { jz not_equal }
                  EmitB($48); EmitB($8B); EmitB($41); EmitB($F8);              { mov rax, [rcx-8] }
                  EmitB($48); EmitB($83); EmitB($F8); EmitB($01);              { cmp rax, 1 }
                  EmitB($0F); EmitB($85); nextJmp2 := CodeLen; EmitI32(0);     { jne not_equal }
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($01);              { movzx rax, byte [rcx] }
                  EmitB($5A);                                                  { pop rdx }
                  EmitB($48); EmitB($39); EmitB($D0);                          { cmp rax, rdx }
                  if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
                  else begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);              { movzx rax, al }
                  EmitB($E9); falseJmp := CodeLen; EmitI32(0);                 { jmp end }
                  
                  Patch32(nextJmp, CodeLen - (nextJmp + 4));
                  Patch32(nextJmp2, CodeLen - (nextJmp2 + 4));
                  EmitB($5A);                                                  { pop rdx }
                  if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
                  Patch32(falseJmp, CodeLen - (falseJmp + 4));
                end
                else
                  EmitAnsiStrCmpReg(op = tkEq, lhsTk, rhsTk);
              end
              else if ((op = tkEq) or (op = tkNeq)) and
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
              else if ((op = tkLt) or (op = tkLe) or (op = tkGt) or (op = tkGe)) and
                  ((IntToTypeKind(IRTk[left]) = tyAnsiString) or
                   (IntToTypeKind(IRTk[left]) = tyString)) and
                  ((IntToTypeKind(IRTk[right]) = tyAnsiString) or
                   (IntToTypeKind(IRTk[right]) = tyString)) then
              begin
                EmitAnsiStrCmp3Reg(op, IntToTypeKind(IRTk[left]), IntToTypeKind(IRTk[right]));
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
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitB($48); EmitB($F7); EmitB($D0); { not rax }
        end
        else
        begin
          EmitB($48); EmitB($83); EmitB($F0); EmitB($01); { xor rax, 1 }
        end;
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid  := IRB[node];   { field width, 0 = none }
        decs := IRC[node];   { decimals, -1 = none }
        CurWriteFd := IRIVal[node]; if CurWriteFd = 0 then CurWriteFd := STDOUT;  { target fd (2 = StdErr) }
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
          else if decs >= 0 then EmitWriteFloatFixed(wid, decs)
          else EmitWriteFloatSci;
        end
        else if decs = -3 then
        begin
          { write(PChar): runtime NUL-terminated C string. }
          IREmitNode(valNode);
          EmitWriteCStr;
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
            MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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
            MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
          end;
          EmitwriteStrVar(symIdx);
        end
        else if IntToTypeKind(IRTk[node]) = tyAnsiString then
        begin
          IREmitNode(valNode);
          EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
          EmitB($74); pNil := CodeLen; EmitB(0);          { jz done }
          EmitB($50);                                     { preserve managed expression (handle) }
          if wid > 0 then
          begin
            { Field width: pad with max(0, wid - len) spaces before the string.
              rax = handle, length at [rax-8]. Mirrors the runtime tyString path. }
            EnsureSpaces;
            EmitB($48); EmitB($8B); EmitB($48); EmitB($F8); { mov rcx, [rax-8] = len }
            MovRaxImm(wid);
            EmitB($48); EmitB($29); EmitB($C8);            { sub rax, rcx }
            EmitB($7E); pDone := CodeLen; EmitB(0);         { jle skip_pad }
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset); { mov rsi, spaces }
            EmitB($48); EmitB($89); EmitB($C2);            { mov rdx, rax (pad count) }
            MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
            Code[pDone] := Byte(CodeLen - (pDone + 1));
          end;
          EmitB($48); EmitB($8B); EmitB($04); EmitB($24); { mov rax, [rsp] = handle (reload; syscall clobbered rax) }
          EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax }
          EmitB($48); EmitB($8B); EmitB($50); EmitB($F8); { mov rdx, [rax-8] }
          MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
          EmitB($58);                                     { restore managed expression }
          if (IRKind[valNode] = IR_BINOP) and (IntToTypeKind(IRTk[valNode]) = tyAnsiString) then
            IREmitCodeCall(AnsiStrReleaseAddr);
          Code[pNil] := Byte(CodeLen - (pNil + 1));
        end
        else if IntToTypeKind(IRTk[node]) = tyString then
        begin
          { String-valued expression (e.g. a function returning String):
            the value is the address of a [len][chars] struct in rax. }
          IREmitNode(valNode);
          EmitB($48); EmitB($89); EmitB($C6);              { mov rsi, rax }
          EmitB($48); EmitB($8B); EmitB($10);              { mov rdx, [rax] }
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08);  { add rsi, 8 }
          MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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
        procIdx := IRA[node];
        if procIdx >= 0 then
        begin
          if ProcExternal[procIdx] or ProcCdecl[procIdx] then
          begin
            { C call — SysV AMD64 ABI. Integer/pointer args fill
              rdi,rsi,rdx,rcx,r8,r9; floating args fill xmm0..xmm7 (the two
              classes are counted independently); further args of each class
              spill to the stack, pushed right-to-left so the leftmost stack
              arg lies at the lowest address. Floats are carried as bits in
              rax. Internal Pascal calls use the all-integer path below. }
            argNode := IRB[node]; nArgs := 0;
            while argNode <> -1 do
            begin
              if nArgs >= MAX_CALL_ARGS then Error('C call: too many arguments');
              argNodeArr[nArgs] := IRA[argNode]; Inc(nArgs);
              argNode := IRB[argNode];
            end;
            intIdx := 0; sseIdx := 0; mStack := 0;
            for i := 0 to nArgs - 1 do
            begin
              if i < Procs[procIdx].ParamCount then
                tk := Procs[procIdx].Params[i].TypeKind
              else
                tk := IntToTypeKind(IRTk[argNodeArr[i]]);
              if TypeIsFloat(tk) then
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
            for i := nArgs - 1 downto 0 do
              if argIsStack[i] then
              begin
                if i < Procs[procIdx].ParamCount then
                  tk := Procs[procIdx].Params[i].TypeKind
                else
                  tk := IntToTypeKind(IRTk[argNodeArr[i]]);
                if (IntToTypeKind(IRTk[argNodeArr[i]]) = tyVariant) and
                   (TypeIsOrdinal(tk) or TypeIsFloat(tk)) then
                begin
                  EmitLoadVariantAddress(argNodeArr[i]);
                  EmitB($48); EmitB($8B); EmitB($40); EmitB($08); { mov rax, [rax+8] }
                end
                else
                  IREmitNode(argNodeArr[i]);
                EmitB($50); { push rax }
              end;
            { Register args: push right-to-left, then pop left-to-right into the
              target registers (each arg evaluated once, no register clobber). }
            for i := nArgs - 1 downto 0 do
              if not argIsStack[i] then
              begin
                if i < Procs[procIdx].ParamCount then
                  tk := Procs[procIdx].Params[i].TypeKind
                else
                  tk := IntToTypeKind(IRTk[argNodeArr[i]]);
                if (IntToTypeKind(IRTk[argNodeArr[i]]) = tyVariant) and
                   (TypeIsOrdinal(tk) or TypeIsFloat(tk)) then
                begin
                  EmitLoadVariantAddress(argNodeArr[i]);
                  EmitB($48); EmitB($8B); EmitB($40); EmitB($08); { mov rax, [rax+8] }
                end
                else
                  IREmitNode(argNodeArr[i]);
                EmitB($50); { push rax }
              end;
            for i := 0 to nArgs - 1 do
              if not argIsStack[i] then
              begin
                if i < Procs[procIdx].ParamCount then
                  tk := Procs[procIdx].Params[i].TypeKind
                else
                  tk := IntToTypeKind(IRTk[argNodeArr[i]]);
                if argIsSse[i] then
                begin
                  EmitB($58); { pop rax }
                  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E);
                  EmitB($C0 + argRegIdx[i] * 8);           { movq xmm[n], rax }
                  if tk = tySingle then
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
            { Internal C function returning an aggregate (struct/union by value):
              pass the caller's hidden destination in r10, matching the pxx
              indirect-result convention its prologue stashes (EmitAggregateDestStash)
              and epilogue fills. External libc aggregate returns (true SysV sret)
              are not modelled here. Evaluate the dest into r10 before AL is set
              and the call is made; arg registers are already loaded above. }
            if (not ProcExternal[procIdx]) and RetViaHiddenDest(Procs[procIdx].RetType) then
            begin
              IREmitNode(IRC[node]);                  { rax = hidden destination }
              EmitB($49); EmitB($89); EmitB($C2);     { mov r10, rax }
            end;
            { Variadic ABI: AL = number of vector registers used. Set
              unconditionally (0 for all-integer calls) so variadic callees
              such as printf read the correct count. }
            EmitB($B8); EmitI32(sseIdx); { mov eax, sseIdx }
            if ProcExternal[procIdx] then
            begin
              extIdx := RegisterExternal(procIdx);
              EmitExternalIndirectCall(extIdx);
            end
            else
              EmitCallProc(procIdx);
            { Restore the caller's rsp from the saved slot, which sits
              padBytes + mStack*8 above the current (post-call) rsp. }
            restoreOff := padBytes + mStack * 8;
            EmitB($48); EmitB($8B); EmitB($A4); EmitB($24); EmitI32(restoreOff); { mov rsp, [rsp+off] }
            if TypeIsFloat(Procs[procIdx].RetType) then
            begin
              { float/double returned in xmm0; the value model carries doubles,
                so widen a single (C `float`) result before bridging to rax. }
              if Procs[procIdx].RetType = tySingle then
                begin EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0); end; { cvtss2sd xmm0, xmm0 }
              EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
            end;
          end
          else
          begin
            { Internal Pascal call: all args in integer registers by index. }
            argNode := IRB[node];
            i := 0;
            while argNode <> -1 do
            begin
              IREmitNode(IRA[argNode]); { -> rax }
              if (procIdx >= 0) and (i < Procs[procIdx].ParamCount) then
              begin
                if Procs[procIdx].Params[i].TypeKind = tyAnsiString then
                begin
                  if IntToTypeKind(IRTk[argNode]) = tyString then
                    EmitAnsiStrFromInlineString
                  else if IntToTypeKind(IRTk[argNode]) = tyChar then
                  begin
                    EmitB($50);                                     { push rax (char code) }
                    EmitB($48); EmitB($89); EmitB($E6);             { mov rsi, rsp }
                    EmitB($48); EmitB($C7); EmitB($C7); EmitI32(1);  { mov rdi, 1 }
                    IREmitCodeCall(AnsiStrFromLiteralAddr);
                    EmitB($59);                                     { pop rcx (restore stack) }
                  end;
                end;
              end;
              EmitB($50); { push rax }
              argNode := IRB[argNode];
              Inc(i);
            end;
            nArgs := i;   { args actually pushed (== ParamCount unless variadic) }
            { A variadic callee receives MORE args than declared params; pop all
              of them (up to 6) into SysV registers so its register-save prologue
              captures every variadic arg. nArgs == ParamCount for every
              non-variadic call, so Pascal / non-variadic codegen is unchanged. }
            if (procIdx >= 0) and ProcVariadic[procIdx] then
            begin
              vaPopN := nArgs; if vaPopN > 6 then vaPopN := 6;
              for i := vaPopN - 1 downto 0 do
                case i of
                  0: EmitB($5F); { pop rdi }
                  1: EmitB($5E); { pop rsi }
                  2: EmitB($5A); { pop rdx }
                  3: EmitB($59); { pop rcx }
                  4: begin EmitB($41); EmitB($58); end; { pop r8 }
                  5: begin EmitB($41); EmitB($59); end; { pop r9 }
                end;
            end
            { More than 6 params: all-stack internal convention — leave the
              left-to-right pushes in place for the callee (which reads
              [rbp+16+(n-1-i)*8]) and clean up after the call. The register
              pop loop below has no case arm past r9, so it used to pop the
              wrong (topmost) args into the registers and leak the rest
              (bug-many-param-call-corruption). }
            else if Procs[procIdx].ParamCount <= 6 then
              for i := Procs[procIdx].ParamCount - 1 downto 0 do
                case i of
                  0: EmitB($5F); { pop rdi }
                  1: EmitB($5E); { pop rsi }
                  2: EmitB($5A); { pop rdx }
                  3: EmitB($59); { pop rcx }
                  4: begin EmitB($41); EmitB($58); end; { pop r8 }
                  5: begin EmitB($41); EmitB($59); end; { pop r9 }
                end;
            if RetViaHiddenDest(Procs[procIdx].RetType) then
            begin
              IREmitNode(IRC[node]);                   { rax = hidden destination }
              EmitB($49); EmitB($89); EmitB($C2);     { mov r10, rax }
            end;
            EmitCallProc(procIdx);
            if (procIdx >= 0) and ProcVariadic[procIdx] then
            begin
              if nArgs > 6 then
              begin
                EmitB($48); EmitB($81); EmitB($C4);   { add rsp, (nArgs-6)*8 }
                EmitI32((nArgs - 6) * 8);
              end;
            end
            else if Procs[procIdx].ParamCount > 6 then
            begin
              EmitB($48); EmitB($81); EmitB($C4);     { add rsp, n*8 }
              EmitI32(Procs[procIdx].ParamCount * 8);
            end;
          end;
        end
        else if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem or class instantiation. Evaluate size -> rax, then Alloc. }
          EmitAcquireHeapLock;
          argNode := IRB[node]; { size arg }
          IREmitNode(IRA[argNode]); { size -> rax }
          EmitHeapAllocLocked;      { rax = payload pointer }
          EmitReleaseHeapLock;

          { Put instance pointer in rdi }
          EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
          
          { Initialize VMT pointer at offset 0 }
          classIdx := IRC[node];
          if classIdx >= REC_UCLASS_BASE then
          begin
            EmitB($48); EmitB($B8); EmitDataRef(UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { mov rax, VMT_addr }
            EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
            
            { Find constructor 'Create' of this class }
            slot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
            if slot >= 0 then
            begin
              cpi := UMthProc_[slot];
              
              { Push Self first }
              EmitB($57); { push rdi }
              
              { Push explicit constructor arguments. Param 0 is the implicit
                Self, so explicit args map to constructor params 1,2,... A frozen
                tyString / tyChar literal passed to a tyAnsiString param must be
                converted to a managed string the same way the normal internal
                call path does (lines below); the bespoke push loop used to omit
                this, so a base ctor invoked directly received a raw frozen
                pointer and read garbage (bug-ctor-managed-string-arg). }
              argNode := IRB[node]; { size arg }
              argNode := IRB[argNode]; { first explicit constructor arg }
              i := 1;
              while argNode <> -1 do
              begin
                IREmitNode(IRA[argNode]); { evaluates arg -> rax }
                if (i < Procs[cpi].ParamCount) and
                   (Procs[cpi].Params[i].TypeKind = tyAnsiString) then
                begin
                  if IntToTypeKind(IRTk[argNode]) = tyString then
                    EmitAnsiStrFromInlineString
                  else if IntToTypeKind(IRTk[argNode]) = tyChar then
                  begin
                    EmitB($50);                                     { push rax (char code) }
                    EmitB($48); EmitB($89); EmitB($E6);             { mov rsi, rsp }
                    EmitB($48); EmitB($C7); EmitB($C7); EmitI32(1);  { mov rdi, 1 }
                    IREmitCodeCall(AnsiStrFromLiteralAddr);
                    EmitB($59);                                     { pop rcx (restore stack) }
                  end;
                end;
                EmitB($50); { push rax }
                argNode := IRB[argNode];
                Inc(i);
              end;
              
              { Pop args into SysV ABI registers. More than 6 params: leave
                the pushes in place (all-stack convention; Self was pushed
                first = leftmost) and clean up after the call. }
              if Procs[cpi].ParamCount <= 6 then
                for i := Procs[cpi].ParamCount-1 downto 0 do
                  case i of
                    0: EmitB($5F);
                    1: EmitB($5E);
                    2: EmitB($5A);
                    3: EmitB($59);
                    4: begin EmitB($41); EmitB($58); end;
                    5: begin EmitB($41); EmitB($59); end;
                  end;

              if Procs[cpi].ParamCount > 6 then
              begin
                { Self (param 0, deepest slot) doubles as the saved result:
                  the callee only reads the arg slots, so it is still intact
                  after the call. }
                EmitCallProc(cpi);
                EmitB($48); EmitB($8B); EmitB($84); EmitB($24); { mov rax, [rsp+disp] }
                EmitI32((Procs[cpi].ParamCount - 1) * 8);
                EmitB($48); EmitB($81); EmitB($C4);             { add rsp, n*8 }
                EmitI32(Procs[cpi].ParamCount * 8);
              end
              else
              begin
                { Save Self across the call and return it as the constructor's
                  result (rax). Without this rax holds the constructor body's
                  garbage return, so `obj := T.Create` stores a bad pointer and a
                  later virtual call dereferences a wild VMT. rdi (= Self, arg0) is
                  unchanged by the push, so the callee still receives it. }
                EmitB($57); { push rdi }
                EmitCallProc(cpi);
                EmitB($58); { pop rax }
              end;
            end
            else
            begin
              { No constructor defined, just return the instance pointer in rax }
              EmitB($48); EmitB($89); EmitB($F8); { mov rax, rdi }
            end;
          end
          else
          begin
            { Plain GetMem: return the payload pointer in rax }
            EmitB($48); EmitB($89); EmitB($F8); { mov rax, rdi }
          end;
        end
        else if procIdx = -Ord(tkFreeMem) then
        begin
          { FreeMem(p): hand the payload back to the pure-Pascal allocator's
            Free, matching GetMem -> Alloc. nil is ignored inside Free. (Was a
            direct push onto the compiler's own BSS_FREE_LIST, which mismatched
            the mmap pool that Alloc now serves.) }
          EmitAcquireHeapLock;
          argNode := IRB[node]; { pointer arg }
          IREmitNode(IRA[argNode]); { p -> rax }
          EmitHeapFreeLocked;       { Free(rax) }
          EmitReleaseHeapLock;
        end
        else if procIdx = -103 then
        begin
          { ReallocMem(oldp, newsize) }
          EmitAcquireHeapLock;
          EmitB($53);                                     { push rbx }
          argNode := IRB[node];           { arg0 = oldp }
          IREmitNode(IRA[argNode]);       { rax = oldp }
          EmitB($50);                     { push rax (oldp) }
          argNode := IRB[argNode];        { arg1 = newsize }
          IREmitNode(IRA[argNode]);       { rax = newsize }

          EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax (newsize) }
          EmitB($5F);                                     { pop rdi (oldp) }
          EmitB($48); EmitB($C7); EmitB($C2); EmitI32(8);  { mov rdx, 8 (align) }

          procIdx := FindProc('PXXRealloc');
          if procIdx < 0 then Error('compiler error: Realloc helper not found in builtin unit');
          EmitCallProc(procIdx);                               { rax = new pointer }

          EmitB($5B);                                     { pop rbx }
          EmitReleaseHeapLock;
        end
        else
        begin
          { Special/built-in calls }
          specialId := -procIdx;
          if specialId = Ord(tkLength) then
          begin
            arg1Node := IRB[node];
            val1Node := IRA[arg1Node];
            if (IntToTypeKind(IRTk[val1Node]) = tyAnsiString) or
               ((IRKind[val1Node] = IR_LEA) and (Syms[IRA[val1Node]].TypeKind = tyAnsiString)) then
             begin
               IREmitNode(val1Node);                          { rax = data ptr (or 0) }
               if (IRKind[val1Node] = IR_LEA) and
                  (Syms[IRA[val1Node]].Kind = skParam) and Syms[IRA[val1Node]].IsRef then
                 { by-ref managed string: IR_LEA yields the forwarded slot address
                   (&handle); deref once to reach the handle before reading [-8]. }
                 begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
               if (IRKind[val1Node] = IR_FIELD) or (IRKind[val1Node] = IR_INDEX) then
                 { Managed string field or array element: yields the address of the
                   handle slot; deref once to reach the handle. }
                 begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
               EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
               EmitB($74); jbePatch := CodeLen; EmitB(0);     { jz done }
               EmitB($48); EmitB($8B); EmitB($40); EmitB($F8);{ mov rax, [rax-8] }
               Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
             end
             else if (IRKind[val1Node] = IR_LEA) and Syms[IRA[val1Node]].IsArray
                and ((Syms[IRA[val1Node]].ArrLen = -1) or
                     (Syms[IRA[val1Node]].Kind = skParam)) then
             begin
               { Dynamic-array variable (ArrLen=-1) or an `array of T` parameter.
                 In both cases the slot holds the heap data pointer whose header
                 word at [P-8] is the element count. }
               IREmitNode(val1Node);                          { rax = data ptr (or 0) }
               EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
               EmitB($74); jbePatch := CodeLen; EmitB(0);     { jz done (rax already 0) }
               EmitB($48); EmitB($8B); EmitB($40); EmitB($F8);{ mov rax, [rax-8] }
               Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
             end
             else if ((IRKind[val1Node] = IR_INDEX) or (IRKind[val1Node] = IR_FIELD)) and
                     (IntToTypeKind(IRTk[val1Node]) = tyPointer) then
             begin
               { Length of a dynamic-array handle held in a slot: a nested
                 sub-array element (IR_INDEX) or a record/class field (IR_FIELD).
                 val1Node is the ADDRESS of the handle slot; load the handle,
                 then read its header length word. }
               IREmitNode(val1Node);                          { rax = &handle }
               EmitB($48); EmitB($8B); EmitB($00);            { mov rax, [rax] = data ptr }
               EmitB($48); EmitB($85); EmitB($C0);            { test rax, rax }
               EmitB($74); jbePatch := CodeLen; EmitB(0);     { jz done }
               EmitB($48); EmitB($8B); EmitB($40); EmitB($F8);{ mov rax, [rax-8] }
               Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
             end
            else
            begin
              IREmitNode(val1Node); { evaluates address -> rax }
              EmitB($48); EmitB($8B); EmitB($00); { mov rax, [rax] }
            end;
          end
          else if specialId = 210 then
          begin
            { Eof (standard input), no args -> Boolean in rax. }
            EmitEof;
          end
          else if (specialId = Ord(tkOrd)) or (specialId = Ord(tkChr)) or
                  (specialId = Ord(tkInteger_T)) or (specialId = Ord(tkLongWord_T)) or
                  (specialId = Ord(tkChar_T)) or (specialId = Ord(tkBoolean_T)) or
                  (specialId = Ord(tkString_T)) then
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
            else if (IRKind[val2Node] = IR_LOAD_SYM) and
                    (Syms[IRA[val2Node]].TypeKind = tyAnsiString) then
              EmitLoadFileManaged(IRA[val1Node], IRA[val2Node])
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
            if (IRKind[val1Node] <> IR_LEA) and
               not ((IRKind[val1Node] = IR_LOAD_SYM) and
                    (Syms[IRA[val1Node]].TypeKind = tyAnsiString)) then
              Error('SetLength expects an array variable in IR codegen');
            symIdx := IRA[val1Node];
            if (Syms[symIdx].ElemType = tyString) and
               (Syms[symIdx].TypeKind <> tyAnsiString) then
              Error('SetLength: dynamic array of record/string not yet supported');
            if Syms[symIdx].ElemType = tyRecord then
              elemSize := RecSize(Syms[symIdx].ElemRecName)
            else
              elemSize := TypeSize(Syms[symIdx].ElemType);
            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
              elemSize := 1;

            IREmitNode(IRA[arg2Node]);      { rax = n }
            EmitB($50);                     { push n }
            EmitAcquireHeapLock;
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($8B); EmitB($34); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
              begin
                { by-ref (var/out) param: the slot holds the ADDRESS of the
                  caller's handle/data-pointer slot; deref to reach the old data
                  pointer, and (below) publish the new one into the caller's slot. }
                EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[symIdx].Offset); { mov rsi, [rbp+off] = caller slot addr }
                EmitB($48); EmitB($8B); EmitB($36);                               { mov rsi, [rsi] = old data ptr }
              end
            else
              begin EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[symIdx].Offset); end;
            EmitB($56);                     { push old data pointer }
            EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] = n }
            EmitB($48); EmitB($85); EmitB($C0); { test rax, rax }
            EmitB($0F); EmitB($84); pDynZero := CodeLen; EmitI32(0);

            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
            begin
              { Managed strings use the allocator payload size at [data-24] as
                capacity. Resize unique buffers in place when the request fits;
                otherwise allocate with geometric headroom so AppendChar is
                amortized. The visible length remains n. }
              EmitB($48); EmitB($8B); EmitB($34); EmitB($24);           { mov rsi, [rsp] = old data }
              EmitB($48); EmitB($85); EmitB($F6);                       { test rsi, rsi }
              EmitB($0F); EmitB($84); pAnsiAlloc := CodeLen; EmitI32(0); { jz alloc }
              EmitB($48); EmitB($83); EmitB($7E); EmitB($F0); EmitB($01); { cmp qword [rsi-16], 1 }
              EmitB($0F); EmitB($85); pAnsiShared := CodeLen; EmitI32(0); { jne alloc }
              EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] = n }
              EmitB($48); EmitB($83); EmitB($C0); EmitB($11);           { add rax, 17 = needed payload }
              EmitB($48); EmitB($3B); EmitB($46); EmitB($E8);           { cmp rax, [rsi-24] = capacity payload }
              EmitB($0F); EmitB($87); pAnsiTooSmall := CodeLen; EmitI32(0); { ja alloc }

              EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);           { mov rcx, [rsi-8] = old len }
              EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($08); { mov rdx, [rsp+8] = n }
              EmitB($48); EmitB($39); EmitB($CA);                       { cmp rdx, rcx }
              EmitB($0F); EmitB($86); pAnsiNoZeroGrow := CodeLen; EmitI32(0); { jbe no_zero }
              EmitB($48); EmitB($8D); EmitB($3C); EmitB($0E);           { lea rdi, [rsi+rcx] }
              EmitB($48); EmitB($89); EmitB($D1);                       { mov rcx, rdx }
              EmitB($48); EmitB($2B); EmitB($4E); EmitB($F8);           { sub rcx, [rsi-8] }
              EmitB($31); EmitB($C0);                                   { xor eax, eax }
              EmitB($F3); EmitB($AA);                                   { rep stosb }
              Patch32(pAnsiNoZeroGrow, CodeLen - (pAnsiNoZeroGrow + 4));
              EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($08); { mov rdx, [rsp+8] = n }
              EmitB($48); EmitB($89); EmitB($56); EmitB($F8);           { mov [rsi-8], rdx }
              EmitB($C6); EmitB($04); EmitB($16); EmitB(0);             { mov byte [rsi+rdx], 0 }
              EmitB($58);                                               { pop rax = old data }
              EmitB($59);                                               { pop rcx = n }
              EmitB($E9); pAnsiFastDone := CodeLen; EmitI32(0);         { jmp done/release-lock }

              Patch32(pAnsiAlloc, CodeLen - (pAnsiAlloc + 4));
              Patch32(pAnsiShared, CodeLen - (pAnsiShared + 4));
              Patch32(pAnsiTooSmall, CodeLen - (pAnsiTooSmall + 4));
              EmitB($48); EmitB($8B); EmitB($34); EmitB($24);           { mov rsi, [rsp] = old data }
              EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax, [rsp+8] = n }
              EmitB($48); EmitB($83); EmitB($C0); EmitB($11);           { add rax, 17 = needed payload }
              EmitB($48); EmitB($85); EmitB($F6);                       { test rsi, rsi }
              EmitB($0F); EmitB($84); pAnsiUseNeededNil := CodeLen; EmitI32(0); { jz use needed }
              EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);           { mov rcx, [rsi-8] = old length (NOT [rsi-24] block cap: a short string that reused an oversized freed block via first-fit would otherwise double the block size each grow -> 4M,8M,16M... OOM) }
              EmitB($48); EmitB($01); EmitB($C9);                       { add rcx, rcx  (geometric headroom from the LENGTH, decoupled from block size) }
              EmitB($48); EmitB($39); EmitB($C1);                       { cmp rcx, rax }
              EmitB($0F); EmitB($82); pAnsiUseNeededSmall := CodeLen; EmitI32(0); { jb use needed }
              EmitB($48); EmitB($89); EmitB($C8);                       { mov rax, rcx }
              EmitB($E9); pAnsiCapDone := CodeLen; EmitI32(0);          { jmp cap_done }
              Patch32(pAnsiUseNeededNil, CodeLen - (pAnsiUseNeededNil + 4));
              Patch32(pAnsiUseNeededSmall, CodeLen - (pAnsiUseNeededSmall + 4));
              EmitB($48); EmitB($83); EmitB($F8); EmitB($20);           { cmp rax, 32 }
              EmitB($0F); EmitB($83); pAnsiMinDone := CodeLen; EmitI32(0); { jae cap_done }
              EmitB($B8); EmitI32(32);                                  { mov eax, 32 }
              Patch32(pAnsiMinDone, CodeLen - (pAnsiMinDone + 4));
              Patch32(pAnsiCapDone, CodeLen - (pAnsiCapDone + 4));
            end
            else if elemSize = 8 then
              begin EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); end { shl rax, 3 }
            else if elemSize > 1 then
              begin
                EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
                EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);        { imul rax, rcx }
              end;
            if not ((Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray) then
              begin EmitB($48); EmitB($83); EmitB($C0); EmitB($10); end; { add rax, 16 (header) }
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
            if Syms[symIdx].IsArray and
               ((Syms[symIdx].ElemType = tyAnsiString) or
                ((Syms[symIdx].ElemType = tyRecord) and
                 RecordHasManagedFields(Syms[symIdx].ElemRecName))) then
            begin
              { The copied array prefix owns its own references. }
              EmitB($48); EmitB($8B); EmitB($3C); EmitB($24);           { mov rdi, [rsp] = new data }
              EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi, [rsp+8] = old data }
              EmitB($48); EmitB($85); EmitB($F6);                       { test rsi, rsi }
              EmitB($0F); EmitB($84); pDynNoRetain := CodeLen; EmitI32(0);
              EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);           { mov rcx, [rsi-8] = old length }
              EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($10); { mov rdx, [rsp+16] = n }
              EmitB($48); EmitB($39); EmitB($D1);                       { cmp rcx, rdx }
              EmitB($0F); EmitB($86); pDynKeepCopy := CodeLen; EmitI32(0);
              EmitB($48); EmitB($89); EmitB($D1);                       { mov rcx, rdx }
              Patch32(pDynKeepCopy, CodeLen - (pDynKeepCopy + 4));
              EmitB($48); EmitB($85); EmitB($C9);                       { test rcx, rcx }
              EmitB($0F); EmitB($84); pDynNoRetainCount := CodeLen; EmitI32(0);
              pDynKeepCopy := CodeLen;
              if Syms[symIdx].ElemType = tyAnsiString then
              begin
                EmitB($48); EmitB($8B); EmitB($07);                     { mov rax, [rdi] }
                EmitAnsiStrRetainLocked;
              end
              else
              begin
                EmitB($51);                                             { push rcx }
                EmitB($57);                                             { push rdi }
                EmitB($48); EmitB($89); EmitB($FB);                     { mov rbx, rdi }
                EmitManagedRecordRetain(Syms[symIdx].ElemRecName);
                EmitB($5F);                                             { pop rdi }
                EmitB($59);                                             { pop rcx }
              end;
              EmitB($48); EmitB($81); EmitB($C7);
              if Syms[symIdx].ElemType = tyRecord then EmitI32(RecSize(Syms[symIdx].ElemRecName))
              else EmitI32(8);                                         { add rdi, element size }
              EmitB($48); EmitB($FF); EmitB($C9);                       { dec rcx }
              EmitB($0F); EmitB($85); EmitI32(pDynKeepCopy - (CodeLen + 4));
              Patch32(pDynNoRetainCount, CodeLen - (pDynNoRetainCount + 4));
              Patch32(pDynNoRetain, CodeLen - (pDynNoRetain + 4));
            end;
            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
            begin
              EmitB($48); EmitB($8B); EmitB($3C); EmitB($24); { mov rdi, [rsp] }
              EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($10); { mov rcx, [rsp+16] }
              EmitB($C6); EmitB($04); EmitB($0F); EmitB(0); { mov byte [rdi+rcx], 0 }
            end;

            EmitB($58);                     { pop rax = new data pointer }
            EmitB($5E);                     { pop rsi = old data pointer }
            EmitB($59);                     { pop rcx = n }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
              begin
                EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[symIdx].Offset); { mov rcx, [rbp+off] = caller slot addr }
                EmitB($48); EmitB($89); EmitB($01);                               { mov [rcx], rax (new ptr -> caller slot) }
              end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($48); EmitB($89); EmitB($F0);                       { mov rax, rsi }
            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
              EmitAnsiStrReleaseLocked
            else
              EmitDynArrayReleaseLockedForSym(symIdx);
            EmitB($E9); pJmpDone := CodeLen; EmitI32(0);

            { SetLength(a, 0): publish nil and release the old allocation. }
            Patch32(pDynZero, CodeLen - (pDynZero + 4));
            EmitB($5E);                     { pop rsi = old data pointer }
            EmitB($59);                     { pop rcx = n }
            EmitB($31); EmitB($C0);          { xor eax, eax }
            if Syms[symIdx].Kind = skGlobal then
              begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[symIdx].Offset); end
            else if (Syms[symIdx].Kind = skParam) and Syms[symIdx].IsRef then
              begin
                EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[symIdx].Offset); { mov rcx, [rbp+off] = caller slot addr }
                EmitB($48); EmitB($89); EmitB($01);                               { mov [rcx], rax (nil -> caller slot) }
              end
            else
              begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[symIdx].Offset); end;
            EmitB($48); EmitB($89); EmitB($F0);                       { mov rax, rsi }
            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
              EmitAnsiStrReleaseLocked
            else
              EmitDynArrayReleaseLockedForSym(symIdx);

            Patch32(pJmpDone, CodeLen - (pJmpDone + 4));
            if (Syms[symIdx].TypeKind = tyAnsiString) and not Syms[symIdx].IsArray then
              Patch32(pAnsiFastDone, CodeLen - (pAnsiFastDone + 4));
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

            if (symIdx >= 0) and (Syms[symIdx].TypeKind = tyAnsiString) and
               not Syms[symIdx].IsArray then
              { managed string: the handle is the nul-terminated path; load it. }
              EmitLoadManagedHandleRdi(symIdx)
            else
            begin
              EmitTerminateString(symIdx);
              EmitLeaStrDataRdi(symIdx);
            end;

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
            { A managed-string destination takes the heap-building path; a frozen
              fixed/short string takes the inline-buffer path. Scalar `string` is
              tyAnsiString in managed mode, so this is the common case. }
            if Syms[symIdx].TypeKind = tyAnsiString then
              EmitArgvToStringManaged(symIdx)
            else
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
        CurWriteFd := IRIVal[node]; if CurWriteFd = 0 then CurWriteFd := STDOUT;  { newline to the same fd }
        EmitwriteSyscall(NEWLINE_OFFSET, 1);
      end;

    IR_READLINE:
      begin
        EmitReadLine;
      end;

    IR_READ_DISCARD:
      begin
        EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_LEN);   { mov rax,[len] }
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_LINE_POS);   { mov [pos],rax }
      end;

    IR_READ_VAR:
      begin
        { A managed-string target needs its SLOT address (&handle), not the
          loaded handle value: an AnsiString lea defaults to loading the handle
          in read context, so force lvalue-write mode to get the slot address
          for EmitReadVarParse's managed publish. }
        if IntToTypeKind(IRTk[node]) = tyAnsiString then
        begin
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNode(IRA[node]);   { rax = slot address }
          InLValueWrite := savedLValueWrite;
        end
        else
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
          { ARC-correct 16-byte variant-to-variant copy. Retain before release
            makes self-assignment safe. }
          IREmitNode(IRB[node]);                 { rax = src addr }
          EmitVariantRetain;
          EmitB($50);
          IREmitNode(IRA[node]);                 { rax = dest addr }
          EmitVariantClear;
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
            tyDouble, tySingle, tyExtended:      size := VT_DOUBLE;
            tyString, tyAnsiString:               size := VT_STRING;
          else
            Error('Variant := this type not yet supported');
          end;
          IREmitNode(IRB[node]);                 { rax = scalar value (float: double bits) }
          if tk = tyString then
            EmitAnsiStrFromInlineString
          else if tk = tyAnsiString then
            IREmitCodeCall(AnsiStrRetainAddr)
          else if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
          begin EmitB($48); EmitB($98); end;     { cdqe: sign-extend eax -> rax }
          EmitB($50);                            { push rax  (payload) }
          IREmitNode(IRA[node]);                 { rax = dest addr }
          EmitVariantClear;
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
          tyDouble, tySingle, tyExtended:      size := VT_DOUBLE;
          tyString, tyAnsiString:               size := VT_STRING;
        else
          Error('Variant operand: this scalar type not yet supported');
        end;
        IREmitNode(IRB[node]);                 { rax = scalar value }
        if tk = tyString then
          EmitAnsiStrFromInlineString
        else if tk = tyAnsiString then
          IREmitCodeCall(AnsiStrRetainAddr)
        else if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
        begin EmitB($48); EmitB($98); end;     { cdqe }
        EmitB($50);                            { push payload }
        IREmitNode(IRA[node]);                 { rax = temp addr }
        EmitVariantClear;
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

    IR_COPY_REC_MANAGED:
      begin
        { ARC-correct whole-record copy. Retain the source's managed fields,
          release the destination's old ones, then bulk-copy. Retaining before
          releasing makes self-assignment and shared fields safe. dest/src are
          parked on the stack so the retain/release helpers may clobber freely. }
        IREmitNode(IRB[node]);                 { rax = source address }
        EmitB($50);                            { push src      [rsp+16 below] }
        IREmitNode(IRA[node]);                 { rax = dest address }
        EmitB($50);                            { push dest     [rsp+8 below]  }
        EmitB($53);                            { push rbx      [rsp]          }

        EmitAcquireHeapLock;
        EmitB($48); EmitB($8B); EmitB($5C); EmitB($24); EmitB($10); { mov rbx, [rsp+16] = src }
        EmitManagedRecordRetain(IRC[node]);
        EmitB($48); EmitB($8B); EmitB($5C); EmitB($24); EmitB($08); { mov rbx, [rsp+8] = dest }
        EmitManagedRecordReleaseLocked(IRC[node]);
        EmitReleaseHeapLock;

        EmitB($5B);                            { pop rbx }
        EmitB($5F);                            { pop rdi = dest }
        EmitB($5E);                            { pop rsi = src }
        EmitB($48); EmitB($B9); EmitI64(IRIVal[node]); { movabs rcx, byte count }
        EmitB($F3); EmitB($A4);                { rep movsb (src -> dest) }
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          target slot-ADDRESS node, IRB = new length. Address-based, so a record/
          var-param field needs no symbol reconstruction. }
        IREmitNode(IRA[node]);                  { rax = slot address }
        EmitB($50);                             { push rax }
        IREmitNode(IRB[node]);                  { rax = n }
        EmitB($48); EmitB($89); EmitB($C6);     { mov rsi, rax (n) }
        EmitB($5F);                             { pop rdi (slot addr) }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
        EmitCallProc(procIdx);
      end;

    IR_SETLEN_DYN:
      begin
        { Nested SetLength on a target slot ADDRESS. Allocate a new
          [refcount:8][length:8][data] block of `count` elements, zero it, copy
          min(old,new) elements, retain copied sub-array handles or managed leaf
          values, then
          publish into the slot and recursively release the old block. No COW. }
        slDepth := IRC[node];
        symIdx := Integer(IRIVal[node]);
        { Element metadata comes from the root symbol for a symbol target, or
          from the node (IRTk = base type, IRSetLenBaseRec = base record) for a
          non-symbol target such as a record/class field. }
        if symIdx >= 0 then
        begin
          slBaseTk := Syms[symIdx].ElemType;
          slBaseRec := Syms[symIdx].ElemRecName;
        end
        else
        begin
          slBaseTk := IntToTypeKind(IRTk[node]);
          slBaseRec := IRSetLenBaseRec[node];
        end;
        if slDepth > 1 then
          slElemSize := 8
        else if slBaseTk = tyRecord then
          slElemSize := RecSize(slBaseRec)
        else
          slElemSize := TypeSize(slBaseTk);

        if AnonDynArrayCount >= 8192 then Error('too many anonymous dynamic arrays');
        anonIdx := AnonDynArrayCount;
        AnonDynArrayOff[anonIdx] := DataLen;
        AnonDynArrayDepth[anonIdx] := slDepth;
        AnonDynArrayBaseTk[anonIdx] := Ord(slBaseTk);
        AnonDynArrayBaseRec[anonIdx] := slBaseRec;
        AnonDynArrayElSize[anonIdx] := slElemSize;
        for i := 0 to 19 do
        begin
          if DataLen >= MAX_DATA then Error('data overflow');
          Data[DataLen] := 0;
          Inc(DataLen);
        end;
        Inc(AnonDynArrayCount);

        savedLValueWrite := InLValueWrite; InLValueWrite := True;
        IREmitNode(IRA[node]);                                 { rax = &slot }
        InLValueWrite := savedLValueWrite;
        EmitB($50);                                            { push &slot }

        IREmitNode(IRB[node]);                                 { rax = n }
        EmitB($50);                                            { push n }

        EmitAcquireHeapLock;

        EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax,[rsp+8] = &slot }
        EmitB($48); EmitB($8B); EmitB($30);                    { mov rsi,[rax] = old data ptr }
        EmitB($56);                                            { push old }

        EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax,[rsp+8] = n }
        EmitB($48); EmitB($85); EmitB($C0);                    { test rax,rax }
        EmitB($0F); EmitB($84); pDynZero := CodeLen; EmitI32(0); { jz zero }

        { size = n*elemSize + 16 }
        if slElemSize = 8 then
          begin EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); end
        else
          begin
            EmitB($48); EmitB($C7); EmitB($C1); EmitI32(slElemSize);
            EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);
          end;
        EmitB($48); EmitB($83); EmitB($C0); EmitB($10);        { add rax,16 }
        EmitHeapAllocLocked;                                   { rax = block base }
        EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($08); { mov rcx,[rsp+8] = n }
        EmitB($48); EmitB($C7); EmitB($00); EmitI32(1);        { mov qword [rax],1 (refcount) }
        EmitB($48); EmitB($89); EmitB($48); EmitB($08);        { mov [rax+8],rcx (length) }
        EmitB($48); EmitB($8D); EmitB($78); EmitB($10);        { lea rdi,[rax+16] (new data) }
        EmitB($57);                                            { push new data }

        { zero new data: rcx = n * elemSize bytes }
        EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($10); { mov rcx,[rsp+16] = n }
        if slElemSize = 8 then
          begin EmitB($48); EmitB($C1); EmitB($E1); EmitB($03); end
        else
          begin
            EmitB($48); EmitB($C7); EmitB($C0); EmitI32(slElemSize);
            EmitB($48); EmitB($0F); EmitB($AF); EmitB($C8);
          end;
        EmitB($48); EmitB($8B); EmitB($3C); EmitB($24);        { mov rdi,[rsp] = new data }
        EmitB($31); EmitB($C0);                                { xor eax,eax }
        EmitB($F3); EmitB($AA);                                { rep stosb }

        { copy old prefix: min(oldlen, n) elements }
        EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi,[rsp+8] = old }
        EmitB($48); EmitB($85); EmitB($F6);                    { test rsi,rsi }
        EmitB($0F); EmitB($84); pDynNoOld := CodeLen; EmitI32(0);
        EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);        { mov rcx,[rsi-8] = old len }
        EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($10); { mov rdx,[rsp+16] = n }
        EmitB($48); EmitB($39); EmitB($D1);                    { cmp rcx,rdx }
        EmitB($0F); EmitB($86); pDynKeepCopy := CodeLen; EmitI32(0); { jbe c1 }
        EmitB($48); EmitB($89); EmitB($D1);                    { mov rcx,rdx }
        Patch32(pDynKeepCopy, CodeLen - (pDynKeepCopy + 4));
        EmitB($48); EmitB($8B); EmitB($3C); EmitB($24);        { mov rdi,[rsp] = new data }
        if slElemSize = 8 then
          begin EmitB($48); EmitB($C1); EmitB($E1); EmitB($03); end
        else
          begin
            EmitB($48); EmitB($C7); EmitB($C0); EmitI32(slElemSize);
            EmitB($48); EmitB($0F); EmitB($AF); EmitB($C8);
          end;
        EmitB($F3); EmitB($A4);                                { rep movsb }
        Patch32(pDynNoOld, CodeLen - (pDynNoOld + 4));

        { Retain copied sub-array handles or managed leaf values. }
        if (slDepth > 1) or (slBaseTk = tyAnsiString) or
           ((slBaseTk = tyRecord) and
            RecordHasManagedFields(slBaseRec)) then
        begin
          EmitB($48); EmitB($8B); EmitB($74); EmitB($24); EmitB($08); { mov rsi,[rsp+8] = old }
          EmitB($48); EmitB($85); EmitB($F6);                  { test rsi,rsi }
          EmitB($0F); EmitB($84); pSlRetainDone := CodeLen; EmitI32(0);
          EmitB($48); EmitB($8B); EmitB($4E); EmitB($F8);      { mov rcx,[rsi-8] = old len }
          EmitB($48); EmitB($8B); EmitB($54); EmitB($24); EmitB($10); { mov rdx,[rsp+16] = n }
          EmitB($48); EmitB($39); EmitB($D1);                  { cmp rcx,rdx }
          EmitB($0F); EmitB($86); pDynKeepCopy := CodeLen; EmitI32(0);
          EmitB($48); EmitB($89); EmitB($D1);                  { mov rcx,rdx }
          Patch32(pDynKeepCopy, CodeLen - (pDynKeepCopy + 4));
          EmitB($48); EmitB($85); EmitB($C9);                  { test rcx,rcx }
          EmitB($0F); EmitB($84); pDynKeepCopy := CodeLen; EmitI32(0);
          EmitB($48); EmitB($8B); EmitB($3C); EmitB($24);      { mov rdi,[rsp] = new data }
          slRetainTop := CodeLen;
          if slDepth > 1 then
          begin
            EmitB($48); EmitB($8B); EmitB($07);                { mov rax,[rdi] }
            EmitDynArrayRetainLocked;
          end
          else if slBaseTk = tyAnsiString then
          begin
            EmitB($48); EmitB($8B); EmitB($07);                { mov rax,[rdi] }
            EmitAnsiStrRetainLocked;
          end
          else
          begin
            EmitB($51);                                         { push rcx }
            EmitB($57);                                         { push rdi }
            EmitB($48); EmitB($89); EmitB($FB);                { mov rbx,rdi }
            EmitManagedRecordRetain(slBaseRec);
            EmitB($5F);                                         { pop rdi }
            EmitB($59);                                         { pop rcx }
          end;
          EmitB($48); EmitB($81); EmitB($C7);
          EmitI32(slElemSize);                                 { add rdi,element size }
          EmitB($48); EmitB($FF); EmitB($C9);                  { dec rcx }
          EmitB($0F); EmitB($85); EmitI32(slRetainTop - (CodeLen + 4));
          Patch32(pDynKeepCopy, CodeLen - (pDynKeepCopy + 4));
          Patch32(pSlRetainDone, CodeLen - (pSlRetainDone + 4));
        end;

        { publish new data into the slot, release old block, result = new data }
        EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($18); { mov rcx,[rsp+24] = &slot }
        EmitB($48); EmitB($8B); EmitB($04); EmitB($24);        { mov rax,[rsp] = new data }
        EmitB($48); EmitB($89); EmitB($01);                    { mov [rcx],rax }
        EmitB($48); EmitB($8B); EmitB($44); EmitB($24); EmitB($08); { mov rax,[rsp+8] = old }
        EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
        EmitB($48); EmitB($BE); EmitDataRef(AnonDynArrayOff[anonIdx]); { mov rsi, desc }
        procIdx := FindProc('PXXDynArrayRelease');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');
        EmitCallProc(procIdx);
        EmitB($48); EmitB($8B); EmitB($04); EmitB($24);        { mov rax,[rsp] = new data (result) }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($20);        { add rsp,32 }
        EmitB($E9); pJmpDone := CodeLen; EmitI32(0);           { jmp done }

        { zero case (n == 0): publish nil, release old }
        Patch32(pDynZero, CodeLen - (pDynZero + 4));
        EmitB($48); EmitB($8B); EmitB($4C); EmitB($24); EmitB($10); { mov rcx,[rsp+16] = &slot }
        EmitB($31); EmitB($C0);                                { xor eax,eax }
        EmitB($48); EmitB($89); EmitB($01);                    { mov [rcx],rax (nil) }
        EmitB($48); EmitB($8B); EmitB($04); EmitB($24);        { mov rax,[rsp] = old }
        EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
        EmitB($48); EmitB($BE); EmitDataRef(AnonDynArrayOff[anonIdx]); { mov rsi, desc }
        procIdx := FindProc('PXXDynArrayRelease');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');
        EmitCallProc(procIdx);
        EmitB($48); EmitB($83); EmitB($C4); EmitB($18);        { add rsp,24 }

        Patch32(pJmpDone, CodeLen - (pJmpDone + 4));
        EmitReleaseHeapLock;
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
        procIdx := IRC[node];
        slot := Integer(IRIVal[node]);
        argNode := IRA[node];
        pathIdx := 0;
        while argNode <> -1 do
        begin
          IREmitNode(IRA[argNode]); { evaluates arg -> rax }
          { Managed-string param: convert an inline-string literal / char arg to a
            managed AnsiString, exactly as the direct IR_CALL path does. Without
            this the callee reads a raw rodata literal as a managed handle and the
            length is garbage. See bug-mixed-signature-vmt-misdispatch. }
          if (pathIdx < Procs[procIdx].ParamCount) and
             (Procs[procIdx].Params[pathIdx].TypeKind = tyAnsiString) then
          begin
            if IntToTypeKind(IRTk[argNode]) = tyString then
              EmitAnsiStrFromInlineString
            else if IntToTypeKind(IRTk[argNode]) = tyChar then
            begin
              EmitB($50);                                     { push rax (char code) }
              EmitB($48); EmitB($89); EmitB($E6);             { mov rsi, rsp }
              EmitB($48); EmitB($C7); EmitB($C7); EmitI32(1); { mov rdi, 1 }
              IREmitCodeCall(AnsiStrFromLiteralAddr);
              EmitB($59);                                     { pop rcx (restore stack) }
            end;
          end;
          EmitB($50); { push rax }
          argNode := IRB[argNode];
          Inc(pathIdx);
        end;
        if Procs[procIdx].ParamCount <= 6 then
          for i := Procs[procIdx].ParamCount - 1 downto 0 do
            case i of
              0: EmitB($5F); { pop rdi  (Self) }
              1: EmitB($5E); { pop rsi }
              2: EmitB($5A); { pop rdx }
              3: EmitB($59); { pop rcx }
              4: begin EmitB($41); EmitB($58); end; { pop r8 }
              5: begin EmitB($41); EmitB($59); end; { pop r9 }
            end
        else
        begin
          { All-stack convention: Self (param 0) is the deepest pushed slot;
            fetch it for the VMT load, args stay on the stack for the callee. }
          EmitB($48); EmitB($8B); EmitB($BC); EmitB($24); { mov rdi, [rsp+disp] }
          EmitI32((Procs[procIdx].ParamCount - 1) * 8);
        end;
        { Aggregate / frozen-string result: load the hidden caller-destination into
          r10 (the pxx indirect-result reg) before dispatch. The dest IR_LEA only
          uses rax, so the arg registers stay intact. }
        if IRCallDest[node] >= 0 then
        begin
          IREmitNode(IRCallDest[node]);
          EmitB($49); EmitB($89); EmitB($C2);     { mov r10, rax }
        end;
        { Virtual Method Table dispatch }
        EmitB($48); EmitB($8B); EmitB($07); { mov rax, [rdi]   -- load VMT pointer }
        EmitB($FF); EmitB($90); EmitI32(slot * 8); { call [rax + slot*8] }
        if Procs[procIdx].ParamCount > 6 then
        begin
          EmitB($48); EmitB($81); EmitB($C4);             { add rsp, n*8 }
          EmitI32(Procs[procIdx].ParamCount * 8);
        end;
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
var i, lblId, pos, targetOffset, f, procIdx: Integer;
    LabelFixupCount: Integer;
begin
  CurWriteFd := STDOUT;   { default write target; IR_WRITE/IR_WRITELN override per-statement (fd 2 for StdErr) }
  { DWARF -g: per-body line-row state, reset before any backend runs (each backend
    calls DbgRecordRow in its statement loop). }
  DwarfLastLine := 0;
  DwarfProcFirstRow := True;
  if TargetArch = TARGET_I386 then
  begin
    IREmitMachineCode386;
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    IREmitMachineCodeArm32;
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    IREmitMachineCodeAarch64;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    IREmitMachineCodeRISCV32;
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    IREmitMachineCodeXtensa;
    Exit;
  end;
  for i := 0 to MAX_IR - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  { Nil-init hidden owning locals synthesised for materialised managed-string
    arguments. They are created during this body's IR lowering, after the
    parser's prologue zero-init pass, so they would otherwise hold stale stack
    bytes and the first store's release-of-old would free garbage. Main-program
    temps are skGlobal (BSS, already zeroed), so only in-proc skLocal needs it. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(Syms[i].RecName) > TARGET_PTR_SIZE) then
        begin
          { Managed-record temp (e.g. a hidden aggregate-result dest): zero the
            full record so every managed field starts nil, not just the first
            qword. }
          EmitAsmX64([
            'lea rdi, [rbp+%]', Syms[i].Offset,
            'xor rax, rax',
            'mov rcx, %', RecSize(Syms[i].RecName),
            'rep stosb'
          ]);
        end
        else
          EmitAsmX64(['mov qword [rbp+%], 0', Syms[i].Offset]);
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
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($E9);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($E9);
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
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
          EmitAsmX64(['test rax, rax']);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($84); { jz 32-bit rel }
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($84);
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitAsmX64([
            'sub rsp, %', EXC_FRAME_SIZE,
            'mov rax, [@glob]', BSS_EXC_TOP,
            'mov [rsp], rax',
            'mov rax, rsp',
            'mov [@glob], rax', BSS_EXC_TOP,
            'lea rdi, [rsp+%]', EXC_JMP_OFFSET
          ]);
          IREmitCodeCall(ExcSetJmpAddr);
          EmitAsmX64(['test eax, eax']);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitAsmX64(['mov rax, [@glob]', BSS_EXC_CLS, 'cmp rax, %', Integer(IRIVal[i])]);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($85);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($85);
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(0);
          end;
        end;

      IR_EXC_MATCH_HIT:
        begin
          lblId := IRA[i];
          EmitAsmX64(['mov rax, [@glob]', BSS_EXC_CLS, 'cmp rax, %', Integer(IRIVal[i])]);
          if LabelPositions[lblId] <> -1 then
          begin
            EmitB($0F); EmitB($84);
            EmitI32(LabelPositions[lblId] - (CodeLen + 4));
          end
          else
          begin
            EmitB($0F); EmitB($84);
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
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

      IR_CALL_IND:
        begin
          { Statement-level indirect (proc-var) call — result discarded. }
          if IRStmtRoot[i] then
            IREmitNode(i);
        end;

      IR_STORE_SYM, IR_STORE_MEM, IR_STORE_DYN, IR_WRITE, IR_WRITELN,
      IR_READLINE, IR_READ_VAR, IR_READ_DISCARD, IR_COPY_REC, IR_COPY_REC_MANAGED, IR_SET_COPY, IR_VAR_STORE,
      IR_SETLEN_DYN, IR_SETLEN_STR, IR_DEFAULT_MEM, IR_ZERO_SYM,
      IR_EXC_LEAVE, IR_RAISE, IR_EXC_STORE, IR_EXC_CLEAR, IR_TERMINATE,
      IR_COSWITCH, IR_YIELD,
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
