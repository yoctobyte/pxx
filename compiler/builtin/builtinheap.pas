unit builtinheap;

{ ESP (xtensa/riscv32) has no mmap and no OS heap of its own here; back the
  allocator with a fixed static arena instead. One marker for both ESP ISAs. }
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{ Heap allocator + managed-string runtime helpers, split out of `builtin` so a
  program that only needs the heap (New/Dispose/GetMem) or the managed-string
  runtime does not drag in the Str/Val/Variant conversion routines (which use
  features not yet available on every target). Pure raw-pointer / Int64 /
  __pxxrawsyscall code, so it compiles on all targets.

  - PXXAlloc/PXXFree/PXXRealloc back GetMem/New, FreeMem/Dispose, ReallocMem
    (see EmitHeapAllocLocked / EmitHeapFreeLocked in ir_codegen.inc). One
    mmap-backed pool; an 8-byte size header precedes each payload; freed blocks
    thread a singly linked free list through the first 8 bytes of their payload.
  - PXXStrFromLit/PXXStrConcat/PXXStrLoadFile are the bodies behind the emitted
    managed-string runtime shims (AnsiStr*Addr in EmitAnsiStringRuntime). }

interface

type
  { `array of const` element record, matching FPC's system.TVarRec on every
    target: a pointer-sized VType tag (8 bytes on 64-bit, 4 on i386) followed by
    the value union. The parser overlaps VAnsiString onto VInteger at the union
    offset (see FixupTVarRecLayout) and right-sizes the record, so a string
    element and an integer element share the 8-/4-byte value slot exactly as FPC
    lays them out. Only the two tags the asm emitter needs are wired today. }
  TVarRec = record
    VType: NativeInt;
    VInteger: NativeInt;
    VAnsiString: Pointer;
    VBoolean: Boolean;
    VChar: Char;
    VPointer: Pointer;
    VPChar: Pointer;
    VInt64: Pointer;      { PInt64 — value boxed because the union slot is pointer-sized }
    VExtended: Pointer;   { PDouble — likewise boxed }
  end;

const
  vtInteger    = 0;
  vtBoolean    = 1;
  vtChar       = 2;
  vtExtended   = 3;
  vtString     = 4;   { shortstring; unused with ansistrings }
  vtPointer    = 5;
  vtPChar      = 6;
  vtAnsiString = 11;
  vtInt64      = 16;

function PXXAlloc(size: NativeInt; align: Integer): Pointer;
procedure PXXFree(p: Pointer);
function PXXRealloc(p: Pointer; newSize: NativeInt; align: Integer): Pointer;
{ Target-independent runtime: managed-string ARC helpers, mem copy/zero, and the
  dynamic-array SetLength. These use only PXXAlloc/PXXFree, so they build on
  every target including ESP. (PXXDynSetLen has an ESP-lean body that skips
  managed-element retain/release; same signature.) }
function PXXStrFromLit(len: NativeInt; src: Pointer): Pointer;
function PXXStrConcat(lenA: NativeInt; srcA: Pointer; srcB: Pointer; lenB: NativeInt): Pointer;
procedure PXXStrIncRef(p: Pointer);
procedure PXXStrDecRef(p: Pointer);
function PXXIntfAddRef(fatptr: Pointer): NativeInt;
function PXXIntfRelease(fatptr: Pointer): NativeInt;
function PXXIntfAddRefRaw(imt, inst: Pointer): NativeInt;
procedure PXXIntfAssign(dest, src: Pointer);
function PXXStrUnique(strSlot: Pointer): Pointer;
function PXXStrEq(lenA: NativeInt; srcA: Pointer; lenB: NativeInt; srcB: Pointer): Int64;
procedure PXXStrSetLen(strSlot: Pointer; newLen: NativeInt);
procedure PXXMemMove(dst: Pointer; src: Pointer; n: NativeInt);
procedure PXXMemZero(dst: Pointer; n: NativeInt);
procedure PXXDynSetLen(arrSlot: Pointer; newLen: NativeInt; desc: Pointer);
{$ifdef CPU_XTENSA}
{ Xtensa software integer divide for ESP32 classic (LX6), which lacks the
  hardware divide option (it has multiply). Selected by --xtensa-cpu=lx6; the
  codegen routes div/mod here instead of quos/rems. Built from shift/sub/add/
  branch (+ mull for the modulo fixup) — none use the div/mod operators, so they
  cannot recurse into themselves. }
function __pxx_udivsi3(n: LongWord; d: LongWord): LongWord;
function __pxx_divsi3(a: Integer; b: Integer): Integer;
function __pxx_modsi3(a: Integer; b: Integer): Integer;
{$endif}
{ Not yet on ESP: file I/O, managed-element dynarray/record retain/release,
  variant, float formatting. }
{$ifndef PXX_ESP}
function PXXStrLoadFile(path: Pointer): Pointer;
procedure PXXRecordRetain(recAddr: Pointer; desc: Pointer);
procedure PXXRecordRelease(recAddr: Pointer; desc: Pointer);
procedure PXXDynArrayRelease(arrData: Pointer; desc: Pointer);
function PXXDynArrayUnique(arrSlot: Pointer; desc: Pointer): Pointer;
function PXXVarBinOp(dest: Pointer; left: Pointer; right: Pointer; opTk: NativeInt; isCompare: NativeInt): Int64;
procedure PXXVarClear(v: Pointer);
procedure PXXVarRetain(v: Pointer);
procedure PXXWriteVariant(v: Pointer);
{$endif}
implementation


type
  PWord = ^NativeInt;  { pointer-sized machine-word access at an arbitrary
                         address: 8 bytes on 64-bit targets, 4 on 32-bit. Must
                         not be ^Int64 — on i386 that writes 8 bytes into a
                         4-byte handle/pointer slot and corrupts its neighbour. }
  PByte = ^Byte;    { byte access at an arbitrary address }
  PInt32 = ^Integer; { 32-bit integer access }
  TPXXIntfMethod = function(AInst: Pointer): NativeInt;  { COM/ARC interface IMT
                       slot signature: _AddRef/_Release take only the implicit
                       Self in arg0 and return the new refcount. }

const
  { IMT slots are a fixed 8 bytes wide on every target (the parser lays out
    8-byte slots and the dispatch reads [[iface]+slot*8]); a 32-bit target stores
    its 4-byte code address in the low half. This is NOT SizeOf(Pointer). The fat
    pointer's own fields, by contrast, ARE pointer-sized. }
  IMT_ADDREF_OFF  = 8;    { slot 1 = _AddRef }
  IMT_RELEASE_OFF = 16;   { slot 2 = _Release }

const
{$ifdef PXX_ESP}
  HEAP_ARENA = 65536;       { single 64 KiB static arena (fits ESP SRAM) }
{$else}
  HEAP_ARENA = 268435456;   { 256 MiB mmap chunk; anon pages fault in lazily }
{$endif}

var
  HeapPtr  : Int64;   { next free byte in the current arena (0 = none yet) }
  HeapEnd  : Int64;   { end address of the current arena }
  FreeList : Int64;   { head of the free list (payload address), 0 = empty }
{$ifdef PXX_ESP}
  { 64 KiB static arena as Int64 cells so its base is 8-aligned (payloads sit
    at base+8, also 8-aligned). Handed out once; HeapMmap returns 0 after. }
  EspArena     : array[0..8191] of Int64;
  EspArenaUsed : Integer;
{$endif}

{ Anonymous mmap of len bytes; returns the base address (or the kernel's
  negative errno, which a subsequent access would fault on). }
function HeapMmap(len: Int64): Int64;
begin
  { mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    via the raw-syscall intrinsic so every target lowers it natively.
    32-bit targets use mmap2 (offset in pages; 0 either way). }
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(9, 0, len, 3, 34, -1, 0);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0);
{$endif}
{$ifdef PXX_ESP}
  { Static arena: hand out the fixed buffer once (len is HEAP_ARENA here, so
    HeapEnd lines up). A second request means the arena is exhausted -> 0,
    which faults on the next access, signalling out-of-memory. }
  if EspArenaUsed <> 0 then
    Result := 0
  else
  begin
    EspArenaUsed := 1;
    Result := Int64(@EspArena[0]);
  end;
{$endif}
end;

function PXXAlloc(size: NativeInt; align: Integer): Pointer;
var
  cur, prev, base, need, arena, i: Int64;
begin
  if size <= 0 then size := 8;
  size := ((size + 7) div 8) * 8;          { round up to 8 }

  { First-fit reuse: free-list nodes are payload addresses; the size header is
    at [cur-8] and the next link at [cur]. A reused block holds stale bytes, so
    zero the requested span — callers (managed refcount/length headers, zeroed
    dynarray/instance slots) assume fresh memory is zero, like a bump block off
    a fresh mmap page. }
  prev := 0;
  cur := FreeList;
  while cur <> 0 do
  begin
    if PWord(cur - 8)^ >= size then
    begin
      if prev = 0 then FreeList := PWord(cur)^
      else PWord(prev)^ := PWord(cur)^;
      i := 0;
      while i < size do
      begin
        PWord(cur + i)^ := 0;
        i := i + 8;
      end;
      Result := Pointer(cur);
      Exit;
    end;
    prev := cur;
    cur := PWord(cur)^;
  end;

  { Bump from the current arena, mapping a new one when it can't fit. }
  need := size + 8;                         { 8-byte size header + payload }
  if (HeapPtr = 0) or (HeapEnd - HeapPtr < need) then
  begin
    arena := need;
    if arena < HEAP_ARENA then arena := HEAP_ARENA;
    HeapPtr := HeapMmap(arena);
    HeapEnd := HeapPtr + arena;
  end;
  base := HeapPtr;
  HeapPtr := HeapPtr + need;
  PWord(base)^ := size;                     { size header }
  Result := Pointer(base + 8);              { payload }
end;

procedure PXXFree(p: Pointer);
var
  addr: Int64;
begin
  addr := Int64(p);
  if addr = 0 then Exit;
  PWord(addr)^ := FreeList;                 { next link in the payload }
  FreeList := addr;
end;

function PXXRealloc(p: Pointer; newSize: NativeInt; align: Integer): Pointer;
var
  addr, oldSize, i, src, dst: Int64;
  np: Pointer;
begin
  addr := Int64(p);
  if addr = 0 then
  begin
    Result := PXXAlloc(newSize, align);
    Exit;
  end;
  if newSize <= 0 then newSize := 8;
  newSize := ((newSize + 7) div 8) * 8;
  oldSize := PWord(addr - 8)^;
  if newSize <= oldSize then
  begin
    Result := p;                            { shrink/no-op: keep the block }
    Exit;
  end;
  np := PXXAlloc(newSize, align);
  dst := Int64(np);
  src := addr;
  i := 0;
  while i < oldSize do                       { oldSize is a multiple of 8 }
  begin
    PWord(dst + i)^ := PWord(src + i)^;
    i := i + 8;
  end;
  PXXFree(p);
  Result := np;
end;

{$ifdef PXX_ESP}
{ ESP lean dynamic array: unmanaged elements only (no per-element retain/release
  -- strings/records/nested arrays are not on ESP yet). Block layout matches the
  shared runtime: [refcount:word][length:word][data], handle = data pointer,
  length read at [handle-8]. desc layout: +4 elSize. }
procedure PXXDynArrayReleaseEsp(arrData: Pointer);
var block, rc: Int64;
begin
  if arrData = nil then Exit;
  block := Int64(arrData) - 16;            { refcount word at block base }
  rc := PWord(block)^ - 1;
  PWord(block)^ := rc;
  if rc <= 0 then PXXFree(Pointer(block));
end;

procedure PXXDynSetLen(arrSlot: Pointer; newLen: NativeInt; desc: Pointer);
var
  oldData, newBlock, newArrData: Pointer;
  oldLen, elSize, copyLen, i: Int64;
begin
  if (arrSlot = nil) or (desc = nil) then Exit;
  oldData := Pointer(PWord(arrSlot)^);
  elSize := PInt32(Int64(desc) + 4)^;
  if newLen <= 0 then
  begin
    PWord(arrSlot)^ := 0;
    PXXDynArrayReleaseEsp(oldData);
    Exit;
  end;
  newBlock := PXXAlloc(16 + newLen * elSize, 8);
  PWord(newBlock)^ := 1;                          { refcount }
  PWord(Int64(newBlock) + 8)^ := newLen;          { length }
  newArrData := Pointer(Int64(newBlock) + 16);
  i := 0;
  while i < newLen * elSize do
  begin
    PByte(Int64(newArrData) + i)^ := 0;
    i := i + 1;
  end;
  if oldData <> nil then
  begin
    oldLen := PWord(Int64(oldData) - 8)^;
    copyLen := oldLen;
    if newLen < copyLen then copyLen := newLen;
    i := 0;
    while i < copyLen * elSize do
    begin
      PByte(Int64(newArrData) + i)^ := PByte(Int64(oldData) + i)^;
      i := i + 1;
    end;
  end;
  PWord(arrSlot)^ := Int64(newArrData);
  PXXDynArrayReleaseEsp(oldData);
end;
{$endif}

{ Managed-string constructor: allocate a [refcount:8][length:8][data][nul]
  block and copy len bytes from src. Returns the data pointer (base+16) or
  nil for an empty string. Called from the emitted runtime shim
  (AnsiStrFromLiteralAddr); the shim holds the heap lock in threadsafe mode.
  Raw pointers only — this code IS the string runtime, so it must not use
  managed strings itself. }
function PXXStrFromLit(len: NativeInt; src: Pointer): Pointer;
var
  base, s, d, i: Int64;
begin
  if len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(len + 17, 8));
  PWord(base)^ := 1;            { refcount }
  PWord(base + 8)^ := len;      { length }
  d := base + 16;
  s := Int64(src);
  i := 0;
  while i < len do
  begin
    PByte(d + i)^ := PByte(s + i)^;
    i := i + 1;
  end;
  PByte(d + len)^ := 0;         { nul terminator }
  Result := Pointer(d);
end;

{ Managed-string concatenation: allocate a fresh block holding srcA[0..lenA)
  followed by srcB[0..lenB), nul-terminated. Returns the data pointer or nil
  for an empty result. Called from the AnsiStrConcatAddr shim under the heap
  lock. Raw pointers only. }
function PXXStrConcat(lenA: NativeInt; srcA: Pointer; srcB: Pointer; lenB: NativeInt): Pointer;
var
  total, base, d, s, i: Int64;
begin
  total := lenA + lenB;
  if total <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(total + 17, 8));
  PWord(base)^ := 1;            { refcount }
  PWord(base + 8)^ := total;    { length }
  d := base + 16;
  s := Int64(srcA);
  i := 0;
  while i < lenA do
  begin
    PByte(d + i)^ := PByte(s + i)^;
    i := i + 1;
  end;
  s := Int64(srcB);
  i := 0;
  while i < lenB do
  begin
    PByte(d + lenA + i)^ := PByte(s + i)^;
    i := i + 1;
  end;
  PByte(d + total)^ := 0;       { nul terminator }
  Result := Pointer(d);
end;

{$ifndef PXX_ESP}
{ Per-target syscall wrappers for the file-load helper. AArch64 has no plain
  open/lseek/read/close in the legacy slots, so it uses openat(AT_FDCWD=-100).
  i386/arm32 use 32-bit lseek (files < 2 GiB); good enough for source loads.
  ESP has no filesystem here, so the whole group is excluded. }
function PXXSysOpenRO(path: Pointer): Int64;
begin
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(2, Int64(path), 0, 0);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(5, Int64(path), 0, 0);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(5, Int64(path), 0, 0);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(56, -100, Int64(path), 0, 0);
{$endif}
end;

function PXXSysLseek(fd, offset, whence: NativeInt): Int64;
begin
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(8, fd, offset, whence);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(19, fd, offset, whence);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(19, fd, offset, whence);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(62, fd, offset, whence);
{$endif}
end;

function PXXSysRead(fd, buf, count: NativeInt): Int64;
begin
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(0, fd, buf, count);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(3, fd, buf, count);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(3, fd, buf, count);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(63, fd, buf, count);
{$endif}
end;

function PXXSysClose(fd: NativeInt): Int64;
begin
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(3, fd);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(6, fd);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(6, fd);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(57, fd);
{$endif}
end;

{ Read an entire file into a fresh managed string. path = nul-terminated
  managed-string data pointer (or nil). Returns the data pointer (refcount 1,
  length = bytes read, nul-terminated) or nil on open failure. Called from the
  AnsiStrLoadFileAddr shim under the heap lock. Raw pointers only. }
function PXXStrLoadFile(path: Pointer): Pointer;
var
  fd, size, base, d, n: Int64;
begin
  Result := nil;
  if path = nil then Exit;
  fd := PXXSysOpenRO(path);
  if fd < 0 then Exit;
  size := PXXSysLseek(fd, 0, 2);          { SEEK_END }
  PXXSysLseek(fd, 0, 0);                   { SEEK_SET }
  base := Int64(PXXAlloc(size + 17, 8));
  PWord(base)^ := 1;                       { refcount }
  PWord(base + 8)^ := size;                { length (corrected below) }
  d := base + 16;
  n := PXXSysRead(fd, d, size);
  if n < 0 then n := 0;
  PWord(base + 8)^ := n;                   { actual bytes read }
  PByte(d + n)^ := 0;                      { nul terminator }
  PXXSysClose(fd);
  Result := Pointer(d);
end;

{$endif}

{ Managed-string refcount retain/release for targets without the hand-emitted
  atomic blob (i386 and other cross targets). p = data pointer; refcount lives
  at [p-16], length at [p-8]. NON-atomic — threadsafe mode is x86-64 only and
  keeps its lock-prefixed inline version. PXXStrDecRef frees the block (base =
  p-16) when the count reaches zero. nil is ignored. }
procedure PXXStrIncRef(p: Pointer);
var base: Int64;
begin
  if p = nil then Exit;
  base := Int64(p) - 16;
  PWord(base)^ := PWord(base)^ + 1;
end;

procedure PXXStrDecRef(p: Pointer);
var base, rc: Int64;
begin
  if p = nil then Exit;
  base := Int64(p) - 16;
  rc := PWord(base)^ - 1;
  PWord(base)^ := rc;
  if rc = 0 then PXXFree(Pointer(base));
end;

{ COM/ARC interface refcount helpers. `fatptr` is the ADDRESS of a 16-/8-byte
  interface fat pointer (word 0 = IMT, word 1 = instance). The IMT is the
  implementing class's Interface Method Table: a vector of code addresses,
  slot 1 = _AddRef, slot 2 = _Release (slot 0 = QueryInterface), so the call
  dispatches polymorphically into the concrete TInterfacedObject-derived method.
  Both are nil-safe (an uninitialised interface var is all-zero); _Release at
  zero frees the instance inside the dispatched method. }
function PXXIntfAddRef(fatptr: Pointer): NativeInt;
var imt, inst: Pointer; fn: TPXXIntfMethod;
begin
  Result := 0;
  if fatptr = nil then Exit;
  inst := Pointer(PWord(Pointer(Int64(fatptr) + SizeOf(Pointer)))^);
  if inst = nil then Exit;
  imt := Pointer(PWord(fatptr)^);
  if imt = nil then Exit;
  fn := TPXXIntfMethod(Pointer(PWord(Pointer(Int64(imt) + IMT_ADDREF_OFF))^));
  Result := fn(inst);
end;

function PXXIntfRelease(fatptr: Pointer): NativeInt;
var imt, inst: Pointer; fn: TPXXIntfMethod;
begin
  Result := 0;
  if fatptr = nil then Exit;
  inst := Pointer(PWord(Pointer(Int64(fatptr) + SizeOf(Pointer)))^);
  if inst = nil then Exit;
  imt := Pointer(PWord(fatptr)^);
  if imt = nil then Exit;
  fn := TPXXIntfMethod(Pointer(PWord(Pointer(Int64(imt) + IMT_RELEASE_OFF))^));
  Result := fn(inst);
end;

{ _AddRef from a raw (IMT, instance) pair — used by class -> COM-interface
  assignment, where the new value is not yet stored as a fat pointer. }
function PXXIntfAddRefRaw(imt, inst: Pointer): NativeInt;
var fn: TPXXIntfMethod;
begin
  Result := 0;
  if (inst = nil) or (imt = nil) then Exit;
  fn := TPXXIntfMethod(Pointer(PWord(Pointer(Int64(imt) + IMT_ADDREF_OFF))^));
  Result := fn(inst);
end;

{ ARC-correct interface->interface assignment: retain the source reference, then
  release the old destination (this order is safe when dest and src alias), then
  copy the fat pointer (IMT word then instance word). }
procedure PXXIntfAssign(dest, src: Pointer);
begin
  PXXIntfAddRef(src);
  PXXIntfRelease(dest);
  PWord(dest)^ := PWord(src)^;
  PWord(Pointer(Int64(dest) + SizeOf(Pointer)))^ :=
    PWord(Pointer(Int64(src) + SizeOf(Pointer)))^;
end;

{ Ensure the managed AnsiString handle stored at strSlot is uniquely owned.
  Returns the data pointer to index/write. }
function PXXStrUnique(strSlot: Pointer): Pointer;
var slotAddr, oldHandle, newHandle, rc, len: Int64;
begin
  if strSlot = nil then
  begin
    Result := nil;
    Exit;
  end;
  slotAddr := Int64(strSlot);
  oldHandle := PWord(slotAddr)^;
  if oldHandle = 0 then
  begin
    Result := nil;
    Exit;
  end;
  rc := PWord(oldHandle - 16)^;
  if rc <= 1 then
  begin
    Result := Pointer(oldHandle);
    Exit;
  end;
  len := PWord(oldHandle - 8)^;
  newHandle := Int64(PXXStrFromLit(len, Pointer(oldHandle)));
  PWord(slotAddr)^ := newHandle;
  PXXStrDecRef(Pointer(oldHandle));
  Result := Pointer(newHandle);
end;

{ Byte-wise string equality for the cross targets' compare codegen. Operands are
  pre-decomposed into (length, data pointer) so it works uniformly for managed
  handles and inline strings. Returns 1 when equal, 0 otherwise. }
function PXXStrEq(lenA: NativeInt; srcA: Pointer; lenB: NativeInt; srcB: Pointer): Int64;
var i, a, b: Int64;
begin
  if lenA <> lenB then
  begin
    Result := 0;
    Exit;
  end;
  a := Int64(srcA);
  b := Int64(srcB);
  i := 0;
  while i < lenA do
  begin
    if PByte(a + i)^ <> PByte(b + i)^ then
    begin
      Result := 0;
      Exit;
    end;
    i := i + 1;
  end;
  Result := 1;
end;

{$ifndef PXX_ESP}
{ Managed-element dynarray + record retain/release (strings/records/nested
  arrays). Not on ESP yet -- the ESP dynarray (above) is unmanaged-element only. }
procedure PXXDynArrayIncRef(p: Pointer);
var base: Int64;
begin
  if p = nil then Exit;
  base := Int64(p) - 16;
  PWord(base)^ := PWord(base)^ + 1;
end;

procedure PXXDynArrayReleaseDepth(arrData: Pointer; depth: Integer; baseKind: Integer; baseRecDesc: Pointer);
var
  base, rc, len: Int64;
  i: Int64;
  itemAddr: Pointer;
  elSize: Int64;
begin
  if arrData = nil then Exit;
  base := Int64(arrData) - 16;
  rc := PWord(base)^ - 1;
  PWord(base)^ := rc;
  if rc = 0 then
  begin
    len := PWord(Int64(arrData) - 8)^;
    if depth > 1 then
    begin
      i := 0;
      while i < len do
      begin
        itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
        PXXDynArrayReleaseDepth(Pointer(PWord(itemAddr)^), depth - 1, baseKind, baseRecDesc);
        i := i + 1;
      end;
    end
    else
    begin
      if baseKind = 1 then
      begin
        i := 0;
        while i < len do
        begin
          itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
          PXXStrDecRef(Pointer(PWord(itemAddr)^));
          i := i + 1;
        end;
      end
      else if baseKind = 3 then
      begin
        if baseRecDesc <> nil then
        begin
          elSize := PInt32(Int64(baseRecDesc) + 4)^;
          i := 0;
          while i < len do
          begin
            itemAddr := Pointer(Int64(arrData) + i * elSize);
            PXXRecordRelease(itemAddr, baseRecDesc);
            i := i + 1;
          end;
        end;
      end;
    end;
    PXXFree(Pointer(base));
  end;
end;

procedure PXXDynArrayRetainImmediate(arrData: Pointer; len: NativeInt; depth: Integer; baseKind: Integer; baseRecDesc: Pointer);
var
  i: Int64;
  itemAddr: Pointer;
  elSize: Int64;
begin
  if arrData = nil then Exit;
  if depth > 1 then
  begin
    i := 0;
    while i < len do
    begin
      itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
      PXXDynArrayIncRef(Pointer(PWord(itemAddr)^));
      i := i + 1;
    end;
  end
  else
  begin
    if baseKind = 1 then
    begin
      i := 0;
      while i < len do
      begin
        itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
        PXXStrIncRef(Pointer(PWord(itemAddr)^));
        i := i + 1;
      end;
    end
    else if baseKind = 3 then
    begin
      if baseRecDesc <> nil then
      begin
        elSize := PInt32(Int64(baseRecDesc) + 4)^;
        i := 0;
        while i < len do
        begin
          itemAddr := Pointer(Int64(arrData) + i * elSize);
          PXXRecordRetain(itemAddr, baseRecDesc);
          i := i + 1;
        end;
      end;
    end;
  end;
end;

procedure PXXRecordRetain(recAddr: Pointer; desc: Pointer);
var
  memberCount, i, j: Integer;
  memberPtr: Int64;
  offset, kind, arrayCount, typeRef: Integer;
  memberAddr, itemAddr: Pointer;
  subDesc: Pointer;
  memberSize: Int64;
begin
  if (recAddr = nil) or (desc = nil) then Exit;
  memberCount := PInt32(Int64(desc) + 8)^;
  memberPtr := Int64(desc) + 12;

  i := 0;
  while i < memberCount do
  begin
    offset := PInt32(memberPtr)^;
    kind := PInt32(memberPtr + 4)^;
    arrayCount := PInt32(memberPtr + 8)^;
    typeRef := PInt32(memberPtr + 12)^;

    memberAddr := Pointer(Int64(recAddr) + offset);

    if kind = 3 then
    begin
      subDesc := Pointer(memberPtr + 12 + typeRef);
      memberSize := PInt32(Int64(subDesc) + 4)^;
    end
    else
    begin
      memberSize := SizeOf(Pointer);
    end;

    j := 0;
    while j < arrayCount do
    begin
      itemAddr := Pointer(Int64(memberAddr) + j * memberSize);
      case kind of
        1: { String }
          PXXStrIncRef(Pointer(PWord(itemAddr)^));
        2: { DynArray }
          PXXDynArrayIncRef(Pointer(PWord(itemAddr)^));
        3: { Record }
          PXXRecordRetain(itemAddr, subDesc);
      end;
      j := j + 1;
    end;

    memberPtr := memberPtr + 16;
    i := i + 1;
  end;
end;

procedure PXXRecordRelease(recAddr: Pointer; desc: Pointer);
var
  memberCount, i, j: Integer;
  memberPtr: Int64;
  offset, kind, arrayCount, typeRef: Integer;
  memberAddr, itemAddr: Pointer;
  subDesc: Pointer;
  memberSize: Int64;
begin
  if (recAddr = nil) or (desc = nil) then Exit;
  memberCount := PInt32(Int64(desc) + 8)^;
  memberPtr := Int64(desc) + 12;

  i := 0;
  while i < memberCount do
  begin
    offset := PInt32(memberPtr)^;
    kind := PInt32(memberPtr + 4)^;
    arrayCount := PInt32(memberPtr + 8)^;
    typeRef := PInt32(memberPtr + 12)^;

    memberAddr := Pointer(Int64(recAddr) + offset);

    if kind = 3 then
    begin
      subDesc := Pointer(memberPtr + 12 + typeRef);
      memberSize := PInt32(Int64(subDesc) + 4)^;
    end
    else
    begin
      memberSize := SizeOf(Pointer);
    end;

    j := 0;
    while j < arrayCount do
    begin
      itemAddr := Pointer(Int64(memberAddr) + j * memberSize);
      case kind of
        1: { String }
          PXXStrDecRef(Pointer(PWord(itemAddr)^));
        2: { DynArray }
          begin
            subDesc := Pointer(memberPtr + 12 + typeRef);
            PXXDynArrayRelease(Pointer(PWord(itemAddr)^), subDesc);
          end;
        3: { Record }
          PXXRecordRelease(itemAddr, subDesc);
      end;
      j := j + 1;
    end;

    memberPtr := memberPtr + 16;
    i := i + 1;
  end;
end;

procedure PXXDynArrayRelease(arrData: Pointer; desc: Pointer);
var
  depth, baseKind, baseTypeRef: Integer;
  baseRecDesc: Pointer;
begin
  if (arrData = nil) or (desc = nil) then Exit;
  depth := PInt32(Int64(desc) + 8)^;
  baseKind := PInt32(Int64(desc) + 12)^;
  baseTypeRef := PInt32(Int64(desc) + 16)^;
  if baseKind = 3 then
    baseRecDesc := Pointer(Int64(desc) + 16 + baseTypeRef)
  else
    baseRecDesc := nil;

  PXXDynArrayReleaseDepth(arrData, depth, baseKind, baseRecDesc);
end;

function PXXDynArrayUnique(arrSlot: Pointer; desc: Pointer): Pointer;
var
  arrData: Pointer;
  refCountPtr: PWord;
  lenPtr: PWord;
  rc, len, elSize, i: Int64;
  newBlock, newArrData: Pointer;
  depth, baseKind, baseTypeRef: Integer;
  baseRecDesc: Pointer;
begin
  Result := nil;
  if (arrSlot = nil) or (desc = nil) then Exit;
  arrData := Pointer(PWord(arrSlot)^);
  if arrData = nil then Exit;

  refCountPtr := PWord(Int64(arrData) - 16);
  rc := refCountPtr^;
  if rc <= 1 then
  begin
    Result := arrData;
    Exit;
  end;

  lenPtr := PWord(Int64(arrData) - 8);
  len := lenPtr^;
  elSize := PInt32(Int64(desc) + 4)^;

  newBlock := PXXAlloc(16 + len * elSize, 8);
  PWord(newBlock)^ := 1;
  PWord(Int64(newBlock) + 8)^ := len;
  newArrData := Pointer(Int64(newBlock) + 16);

  i := 0;
  while i < len * elSize do
  begin
    PByte(Int64(newArrData) + i)^ := PByte(Int64(arrData) + i)^;
    i := i + 1;
  end;

  depth := PInt32(Int64(desc) + 8)^;
  baseKind := PInt32(Int64(desc) + 12)^;
  baseTypeRef := PInt32(Int64(desc) + 16)^;
  if baseKind = 3 then
    baseRecDesc := Pointer(Int64(desc) + 16 + baseTypeRef)
  else
    baseRecDesc := nil;

  PXXDynArrayRetainImmediate(newArrData, len, depth, baseKind, baseRecDesc);
  PWord(arrSlot)^ := Int64(newArrData);
  PXXDynArrayRelease(arrData, desc);

  Result := newArrData;
end;
{$endif}

{ Forward byte copy (non-overlapping or dst < src). Used by cross backends that
  lack a single-instruction block move (e.g. ARM32) for whole-record copies. }
procedure PXXMemMove(dst: Pointer; src: Pointer; n: NativeInt);
var d, s, i: Int64;
begin
  d := Int64(dst);
  s := Int64(src);
  i := 0;
  while i < n do
  begin
    PByte(d + i)^ := PByte(s + i)^;
    i := i + 1;
  end;
end;

{ Zero n bytes at dst. }
procedure PXXMemZero(dst: Pointer; n: NativeInt);
var d, i: Int64;
begin
  d := Int64(dst);
  i := 0;
  while i < n do
  begin
    PByte(d + i)^ := 0;
    i := i + 1;
  end;
end;

{$ifndef PXX_ESP}
{ SetLength for a depth-1 dynamic array. arrSlot = address of the handle slot;
  newLen = requested element count; desc = the array's layout descriptor
  (+4 elSize, +8 depth, +12 baseKind, +16 baseTypeRef). Allocates a fresh
  [refcount:8][length:8][data] block, zeroes it, copies min(old,new) elements,
  retains the copied managed elements, publishes the new handle, and releases
  the old one. newLen <= 0 publishes nil. Target-independent — replaces the
  per-arch inline SetLength so i386/ARM32/AArch64 share one implementation.
  ESP uses the lean unmanaged-element PXXDynSetLen above instead. }
procedure PXXDynSetLen(arrSlot: Pointer; newLen: NativeInt; desc: Pointer);
var
  oldData, newBlock, newArrData: Pointer;
  oldLen, elSize, copyLen, i: Int64;
  depth, baseKind, baseTypeRef: Integer;
  baseRecDesc: Pointer;
begin
  if (arrSlot = nil) or (desc = nil) then Exit;
  oldData := Pointer(PWord(arrSlot)^);
  elSize := PInt32(Int64(desc) + 4)^;
  depth := PInt32(Int64(desc) + 8)^;
  baseKind := PInt32(Int64(desc) + 12)^;
  baseTypeRef := PInt32(Int64(desc) + 16)^;
  if baseKind = 3 then
    baseRecDesc := Pointer(Int64(desc) + 16 + baseTypeRef)
  else
    baseRecDesc := nil;

  if newLen <= 0 then
  begin
    PWord(arrSlot)^ := 0;
    PXXDynArrayRelease(oldData, desc);
    Exit;
  end;

  newBlock := PXXAlloc(16 + newLen * elSize, 8);
  PWord(newBlock)^ := 1;
  PWord(Int64(newBlock) + 8)^ := newLen;
  newArrData := Pointer(Int64(newBlock) + 16);

  i := 0;
  while i < newLen * elSize do
  begin
    PByte(Int64(newArrData) + i)^ := 0;
    i := i + 1;
  end;

  if oldData <> nil then
  begin
    oldLen := PWord(Int64(oldData) - 8)^;
    copyLen := oldLen;
    if newLen < copyLen then copyLen := newLen;
    i := 0;
    while i < copyLen * elSize do
    begin
      PByte(Int64(newArrData) + i)^ := PByte(Int64(oldData) + i)^;
      i := i + 1;
    end;
    PXXDynArrayRetainImmediate(newArrData, copyLen, depth, baseKind, baseRecDesc);
  end;

  PWord(arrSlot)^ := Int64(newArrData);
  PXXDynArrayRelease(oldData, desc);
end;
{$endif}

{ SetLength for a managed AnsiString. strSlot = address of the handle slot
  (holds the data pointer or nil); newLen = requested character count. Allocates
  a fresh [refcount:8][length:8][data][nul] block, copies min(old,new) chars,
  zero-fills the growth, nul-terminates, publishes the new handle, and releases
  the old one. newLen <= 0 publishes nil. Target-independent — lets the cross
  backends route SetLength(ansistring, n) through one shared implementation
  instead of the x86-64 inline resize. }
procedure PXXStrSetLen(strSlot: Pointer; newLen: NativeInt);
var
  oldData, newBase, newData: Pointer;
  oldLen, copyLen, i: Int64;
begin
  if strSlot = nil then Exit;
  oldData := Pointer(PWord(strSlot)^);

  if newLen <= 0 then
  begin
    PWord(strSlot)^ := 0;
    PXXStrDecRef(oldData);
    Exit;
  end;

  newBase := PXXAlloc(newLen + 17, 8);
  PWord(newBase)^ := 1;                       { refcount }
  PWord(Int64(newBase) + 8)^ := newLen;       { length }
  newData := Pointer(Int64(newBase) + 16);

  copyLen := 0;
  if oldData <> nil then
  begin
    oldLen := PWord(Int64(oldData) - 8)^;
    copyLen := oldLen;
    if newLen < copyLen then copyLen := newLen;
    i := 0;
    while i < copyLen do
    begin
      PByte(Int64(newData) + i)^ := PByte(Int64(oldData) + i)^;
      i := i + 1;
    end;
  end;

  i := copyLen;
  while i < newLen do
  begin
    PByte(Int64(newData) + i)^ := 0;
    i := i + 1;
  end;
  PByte(Int64(newData) + newLen)^ := 0;       { nul terminator }

  PWord(strSlot)^ := Int64(newData);
  PXXStrDecRef(oldData);
end;

{ Generic dynamic-array Copy support. The compiler can't express Copy(arr, ...)
  as one non-generic routine (element type varies), so it lowers Copy into a
  SetLength + raw byte copy of the element bytes, and these two helpers do the
  element-type-agnostic parts. Raw pointers only. }

{ Clamp a Copy element count to the source array's bounds. srcData = the dyn
  array's data pointer (or nil for an empty array); index/count are 0-based.
  Returns how many elements are actually available from `index` (0 if the
  index is past the end or the array is empty). }
function PXXClampLen(srcData: Pointer; index: NativeInt; count: NativeInt): NativeInt;
var len, avail: Int64;
begin
  if srcData = nil then len := 0 else len := PWord(Int64(srcData) - 8)^;
  if index < 0 then index := 0;
  if index >= len then begin Result := 0; Exit; end;
  avail := len - index;
  if count > avail then count := avail;
  if count < 0 then count := 0;
  Result := count;
end;

{ Raw forward byte copy. Copy always writes into a freshly allocated block, so
  source and destination never overlap. }
function PXXMemCopy(dest: Pointer; src: Pointer; n: NativeInt): Pointer;
var i: Int64;
begin
  i := 0;
  while i < n do
  begin
    PByte(Int64(dest) + i)^ := PByte(Int64(src) + i)^;
    i := i + 1;
  end;
  Result := dest;
end;

{$ifdef CPU_XTENSA}
{ Unsigned 32-bit divide: restoring shift-subtract. No div/mod operator used. }
function __pxx_udivsi3(n: LongWord; d: LongWord): LongWord;
var q, r, bit: LongWord; i: Integer;
begin
  q := 0;
  r := 0;
  if d = 0 then
  begin
    Result := 0;   { HW would trap; return 0 rather than loop forever }
    Exit;
  end;
  i := 31;
  while i >= 0 do
  begin
    r := r shl 1;
    bit := (n shr i) and 1;
    r := r or bit;
    if r >= d then
    begin
      r := r - d;
      q := q or (LongWord(1) shl i);
    end;
    i := i - 1;
  end;
  Result := q;
end;

{ Signed 32-bit divide: magnitude divide + sign fixup. }
function __pxx_divsi3(a: Integer; b: Integer): Integer;
var na, nb, q: LongWord; neg: Boolean;
begin
  neg := (a < 0) <> (b < 0);
  if a < 0 then na := LongWord(-a) else na := LongWord(a);
  if b < 0 then nb := LongWord(-b) else nb := LongWord(b);
  q := __pxx_udivsi3(na, nb);
  if neg then Result := -Integer(q) else Result := Integer(q);
end;

{ Signed 32-bit modulo: a - (a div b) * b. The multiply (mull) is present on
  LX6; only the divide option is missing. }
function __pxx_modsi3(a: Integer; b: Integer): Integer;
begin
  Result := a - __pxx_divsi3(a, b) * b;
end;
{$endif}

{$ifndef PXX_ESP}
{ Variant + float-formatting runtime (not on ESP yet). }
type
  PDouble = ^Double;

function PXXVarBinOp(dest: Pointer; left: Pointer; right: Pointer; opTk: NativeInt; isCompare: NativeInt): Int64;
var
  lTag, rTag, lVal, rVal, resVal: Int64;
  lDbl, rDbl, resDbl: Double;
  lStr, rStr, resStr: Pointer;
  lLen, rLen: Int64;
  lStrPtr, rStrPtr: Pointer;
begin
  lTag := PWord(left)^;
  rTag := PWord(right)^;
  lVal := PWord(Int64(left) + 8)^;
  rVal := PWord(Int64(right) + 8)^;

  { 1. String check }
  if (isCompare = 1) or (opTk = 70) then { tkPlus = 70 }
  begin
    if (lTag = 6) or (lTag = 5) or (rTag = 6) or (rTag = 5) then
    begin
      if isCompare = 1 then
      begin
        { Compare tags first }
        if lTag <> rTag then
        begin
          if opTk = 65 then Result := 1 else Result := 0; { tkNeq = 65 }
          Exit;
        end;
        
        { Tags are the same: string/string or char/char }
        if lTag = 5 then
        begin
          { Char comparison }
          if opTk = 64 then Result := Int64(lVal = rVal)
          else if opTk = 65 then Result := Int64(lVal <> rVal)
          else if opTk = 66 then Result := Int64(lVal < rVal)
          else if opTk = 67 then Result := Int64(lVal <= rVal)
          else if opTk = 68 then Result := Int64(lVal > rVal)
          else if opTk = 69 then Result := Int64(lVal >= rVal);
          Exit;
        end
        else
        begin
          { String comparison }
          lStr := Pointer(lVal);
          rStr := Pointer(rVal);
          if lStr = nil then lLen := 0 else lLen := PWord(Int64(lStr) - 8)^;
          if rStr = nil then rLen := 0 else rLen := PWord(Int64(rStr) - 8)^;
          
          resVal := PXXStrEq(lLen, lStr, rLen, rStr);
          if opTk = 64 then Result := resVal
          else if opTk = 65 then Result := 1 - resVal
          else Result := 0;
          Exit;
        end;
      end
      else
      begin
        { tkPlus: string concatenation }
        if lTag = 5 then
        begin
          lStrPtr := Pointer(Int64(left) + 8);
          lLen := 1;
        end
        else
        begin
          lStrPtr := Pointer(lVal);
          if lStrPtr = nil then lLen := 0 else lLen := PWord(Int64(lStrPtr) - 8)^;
        end;

        if rTag = 5 then
        begin
          rStrPtr := Pointer(Int64(right) + 8);
          rLen := 1;
        end
        else
        begin
          rStrPtr := Pointer(rVal);
          if rStrPtr = nil then rLen := 0 else rLen := PWord(Int64(rStrPtr) - 8)^;
        end;

        resStr := PXXStrConcat(lLen, lStrPtr, rStrPtr, rLen);
        if PWord(dest)^ = 6 then
          PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
        PWord(dest)^ := 6;
        PWord(Int64(dest) + 8)^ := Int64(resStr);
        Result := Int64(dest);
        Exit;
      end;
    end;
  end;

  { 2. Numeric path }
  if (lTag = 3) or (rTag = 3) or (opTk = 73) then { VT_DOUBLE = 3, tkSlash = 73 }
  begin
    { Read double payloads straight from the slot: on 32-bit targets lVal
      holds only the low machine word, so a bounce through @lVal would
      truncate the double. }
    if lTag = 3 then
      lDbl := PDouble(Int64(left) + 8)^
    else
      lDbl := lVal;

    if rTag = 3 then
      rDbl := PDouble(Int64(right) + 8)^
    else
      rDbl := rVal;

    if isCompare = 1 then
    begin
      if opTk = 64 then Result := Int64(lDbl = rDbl)
      else if opTk = 65 then Result := Int64(lDbl <> rDbl)
      else if opTk = 66 then Result := Int64(lDbl < rDbl)
      else if opTk = 67 then Result := Int64(lDbl <= rDbl)
      else if opTk = 68 then Result := Int64(lDbl > rDbl)
      else if opTk = 69 then Result := Int64(lDbl >= rDbl);
      Exit;
    end
    else if (opTk = 33) or (opTk = 34) then { tkDiv = 33, tkMod = 34 }
    begin
      lVal := Trunc(lDbl);
      rVal := Trunc(rDbl);
      if opTk = 33 then resVal := lVal div rVal else resVal := lVal mod rVal;
      if PWord(dest)^ = 6 then
        PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
      PWord(dest)^ := 1;
      PWord(Int64(dest) + 8)^ := resVal;
      Result := Int64(dest);
      Exit;
    end
    else
    begin
      if opTk = 70 then resDbl := lDbl + rDbl
      else if opTk = 71 then resDbl := lDbl - rDbl
      else if opTk = 72 then resDbl := lDbl * rDbl
      else if opTk = 73 then resDbl := lDbl / rDbl;

      if PWord(dest)^ = 6 then
        PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
      PWord(dest)^ := 3;
      PDouble(Int64(dest) + 8)^ := resDbl;
      Result := Int64(dest);
      Exit;
    end;
  end
  else
  begin
    { Both are integer-class }
    if isCompare = 1 then
    begin
      if opTk = 64 then Result := Int64(lVal = rVal)
      else if opTk = 65 then Result := Int64(lVal <> rVal)
      else if opTk = 66 then Result := Int64(lVal < rVal)
      else if opTk = 67 then Result := Int64(lVal <= rVal)
      else if opTk = 68 then Result := Int64(lVal > rVal)
      else if opTk = 69 then Result := Int64(lVal >= rVal);
      Exit;
    end
    else
    begin
      if opTk = 70 then resVal := lVal + rVal
      else if opTk = 71 then resVal := lVal - rVal
      else if opTk = 72 then resVal := lVal * rVal
      else if opTk = 33 then resVal := lVal div rVal
      else if opTk = 34 then resVal := lVal mod rVal;

      if PWord(dest)^ = 6 then
        PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
      PWord(dest)^ := 1;
      PWord(Int64(dest) + 8)^ := resVal;
      Result := Int64(dest);
      Exit;
    end;
  end;
end;

procedure PXXVarClear(v: Pointer);
{ Release a string payload and zero the 16-byte slot (both words fully, so
  32-bit targets leave no stale high halves behind). }
begin
  if PWord(v)^ = 6 then  { VT_STRING }
    PXXStrDecRef(Pointer(PWord(Int64(v) + 8)^));
  PXXMemZero(v, 16);
end;

procedure PXXVarRetain(v: Pointer);
begin
  if PWord(v)^ = 6 then  { VT_STRING }
    PXXStrIncRef(Pointer(PWord(Int64(v) + 8)^));
end;

{ ---- Float -> text writers (portable bodies for the cross targets, used in
  place of the per-arch EmitWriteFloat* emitters; x86-64 keeps its native
  ones and this code must match their output byte for byte).

  32-bit targets have no 64-bit integer registers, so all the scaling and
  digit extraction here stays in Double: every intermediate is an integral
  double below 2^53 (exactly representable), and each per-digit quotient is
  provably more than half an ulp below the next integer, so Trunc of the
  rounded quotient equals the exact integer digit.

  The i386/ARM32 internal call ABI passes every argument as one pointer-sized
  slot, so no helper here may take or return a Double; values cross procedure
  boundaries by address. Round-to-nearest-even (the cvtsd2si / fcvtns
  semantics) is done with the 2^52 add/sub trick, written as separate
  statements so no constant folding can collapse it. }

procedure PXXWriteUIntD(pv: Pointer);
{ Print a non-negative integral double in decimal (writeUInt, double domain). }
var v, p: Double; d: Integer; ch: Char;
begin
  v := PDouble(pv)^;
  p := 1;
  while p * 10 <= v do p := p * 10;
  while p >= 1 do
  begin
    d := Trunc(v / p);
    ch := Chr(48 + d);
    write(ch);
    v := v - d * p;
    p := p / 10;
  end;
end;

procedure PXXWriteFloatNat(p: Pointer);
{ Natural decimal: [-]int.frac, trailing zeros trimmed, at least one
  fractional digit. Mirrors EmitWriteFloatNat (x86-64). }
var x, ip, m, dv, r, two52, scale15: Double; d, i: Integer; ch: Char;
begin
  two52 := 1;
  for i := 1 to 52 do two52 := two52 * 2;
  scale15 := 1;
  for i := 1 to 15 do scale15 := scale15 * 10;
  x := PDouble(p)^;
  if PByte(Int64(p) + 7)^ >= 128 then  { sign bit (handles -0.0 too) }
  begin
    write('-');
    x := -x;
  end;
  { ip := trunc(x): round-even, then correct down }
  if x >= two52 then
    r := x
  else
  begin
    r := x + two52;
    r := r - two52;
  end;
  if r > x then r := r - 1;
  ip := r;
  { m := round-even((x - ip) * 1e15); the product is < 2^52 }
  m := (x - ip) * scale15;
  r := m + two52;
  m := r - two52;
  if m = scale15 then  { frac rounded up to 1.0: carry }
  begin
    m := 0;
    ip := ip + 1;
  end;
  PXXWriteUIntD(@ip);
  write('.');
  dv := scale15 / 10;  { 10^14 }
  for i := 0 to 14 do
  begin
    d := Trunc(m / dv);
    m := m - d * dv;
    ch := Chr(48 + d);
    write(ch);
    if (i < 14) and (m = 0) then Exit;
    dv := dv / 10;
  end;
end;

procedure PXXWriteFloatFixed(p: Pointer; decimals: NativeInt);
{ [-]intpart.frac with exactly 'decimals' fractional digits (0 -> rounded
  integer, no point). Mirrors EmitWriteFloatFixed (x86-64). }
var x, pw, v, ip, rem, dv, r, two52: Double; d: Integer; i: Int64; ch: Char;
begin
  two52 := 1;
  i := 1;
  while i <= 52 do
  begin
    two52 := two52 * 2;
    i := i + 1;
  end;
  x := PDouble(p)^;
  if PByte(Int64(p) + 7)^ >= 128 then
  begin
    write('-');
    x := -x;
  end;
  pw := 1;
  i := 1;
  while i <= decimals do
  begin
    pw := pw * 10;
    i := i + 1;
  end;
  { v := round-even(x * pw) }
  v := x * pw;
  if v < two52 then
  begin
    r := v + two52;
    v := r - two52;
  end;
  if decimals <= 0 then
  begin
    PXXWriteUIntD(@v);
    Exit;
  end;
  { exact integer split v = ip*pw + rem (correct the rounded quotient) }
  r := v / pw;
  if r < two52 then
  begin
    ip := r + two52;
    ip := ip - two52;
  end
  else
    ip := r;
  rem := v - ip * pw;
  if rem < 0 then
  begin
    ip := ip - 1;
    rem := rem + pw;
  end;
  if rem >= pw then
  begin
    ip := ip + 1;
    rem := rem - pw;
  end;
  PXXWriteUIntD(@ip);
  write('.');
  dv := pw / 10;
  i := 1;
  while i <= decimals do
  begin
    d := Trunc(rem / dv);
    rem := rem - d * dv;
    ch := Chr(48 + d);
    write(ch);
    dv := dv / 10;
    i := i + 1;
  end;
end;

procedure PXXWriteFloatSci(p: Pointer);
{ Pascal scientific notation <' '|'-'>d.<15 digits>E<'+'|'-'>ddd. Mirrors
  EmitWriteFloatSci (x86-64), including the leading-space positive sign. }
var x, m, dv, r, two52, scale15: Double; e, d, k: Integer; ch: Char;
begin
  two52 := 1;
  for k := 1 to 52 do two52 := two52 * 2;
  scale15 := 1;
  for k := 1 to 15 do scale15 := scale15 * 10;
  x := PDouble(p)^;
  if PByte(Int64(p) + 7)^ >= 128 then
  begin
    write('-');
    x := -x;
  end
  else
    write(' ');
  if x = 0 then
  begin
    write('0.000000000000000E+000');
    Exit;
  end;
  e := 0;
  while x >= 10 do
  begin
    x := x / 10;
    e := e + 1;
  end;
  while x < 1 do
  begin
    x := x * 10;
    e := e - 1;
  end;
  { m := round-even(x * 1e15): 16 significant digits. Above 2^52 the value
    is already integral, matching cvtsd2si exactly. }
  m := x * scale15;
  if m < two52 then
  begin
    r := m + two52;
    m := r - two52;
  end;
  dv := scale15;
  for k := 0 to 15 do
  begin
    d := Trunc(m / dv);
    m := m - d * dv;
    ch := Chr(48 + d);
    write(ch);
    if k = 0 then write('.');
    dv := dv / 10;
  end;
  write('E');
  if e < 0 then
  begin
    write('-');
    e := -e;
  end
  else
    write('+');
  d := e div 100;
  ch := Chr(48 + d);
  write(ch);
  e := e mod 100;
  d := e div 10;
  ch := Chr(48 + d);
  write(ch);
  d := e mod 10;
  ch := Chr(48 + d);
  write(ch);
end;

procedure PXXWriteVariant(v: Pointer);
{ Tag-dispatched write of a 16-byte variant slot; mirrors EmitWriteVariant
  (x86-64): int/int64/bool as signed integer, double natural, char raw,
  string payload bytes, empty/object nothing. }
var tag, iv, len, i, s: Int64; ch: Char;
begin
  tag := PWord(v)^;
  if (tag = 1) or (tag = 2) or (tag = 4) then  { VT_INT / VT_INT64 / VT_BOOL }
  begin
    iv := PWord(Int64(v) + 8)^;
    write(iv);
  end
  else if tag = 3 then  { VT_DOUBLE }
    PXXWriteFloatNat(Pointer(Int64(v) + 8))
  else if tag = 5 then  { VT_CHAR }
  begin
    ch := Chr(PByte(Int64(v) + 8)^);
    write(ch);
  end
  else if tag = 6 then  { VT_STRING }
  begin
    s := PWord(Int64(v) + 8)^;
    if s <> 0 then
    begin
      len := PWord(s - 8)^;
      i := 0;
      while i < len do
      begin
        ch := Chr(PByte(s + i)^);
        write(ch);
        i := i + 1;
      end;
    end;
  end;
end;
{$endif}

end.
