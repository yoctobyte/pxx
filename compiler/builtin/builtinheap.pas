unit builtinheap;

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

function PXXAlloc(size: Int64; align: Integer): Pointer;
procedure PXXFree(p: Pointer);
function PXXRealloc(p: Pointer; newSize: Int64; align: Integer): Pointer;
function PXXStrFromLit(len: Int64; src: Pointer): Pointer;
function PXXStrConcat(lenA: Int64; srcA: Pointer; srcB: Pointer; lenB: Int64): Pointer;
function PXXStrLoadFile(path: Pointer): Pointer;
procedure PXXStrIncRef(p: Pointer);
procedure PXXStrDecRef(p: Pointer);
function PXXStrEq(lenA: Int64; srcA: Pointer; lenB: Int64; srcB: Pointer): Int64;

implementation


type
  PWord = ^Int64;   { machine-word access at an arbitrary address }
  PByte = ^Byte;    { byte access at an arbitrary address }

const
  HEAP_ARENA = 268435456;   { 256 MiB mmap chunk; anon pages fault in lazily }

var
  HeapPtr  : Int64;   { next free byte in the current arena (0 = none yet) }
  HeapEnd  : Int64;   { end address of the current arena }
  FreeList : Int64;   { head of the free list (payload address), 0 = empty }

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
end;

function PXXAlloc(size: Int64; align: Integer): Pointer;
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

function PXXRealloc(p: Pointer; newSize: Int64; align: Integer): Pointer;
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

{ Managed-string constructor: allocate a [refcount:8][length:8][data][nul]
  block and copy len bytes from src. Returns the data pointer (base+16) or
  nil for an empty string. Called from the emitted runtime shim
  (AnsiStrFromLiteralAddr); the shim holds the heap lock in threadsafe mode.
  Raw pointers only — this code IS the string runtime, so it must not use
  managed strings itself. }
function PXXStrFromLit(len: Int64; src: Pointer): Pointer;
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
function PXXStrConcat(lenA: Int64; srcA: Pointer; srcB: Pointer; lenB: Int64): Pointer;
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

{ Per-target syscall wrappers for the file-load helper. AArch64 has no plain
  open/lseek/read/close in the legacy slots, so it uses openat(AT_FDCWD=-100).
  i386/arm32 use 32-bit lseek (files < 2 GiB); good enough for source loads. }
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

function PXXSysLseek(fd, offset, whence: Int64): Int64;
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

function PXXSysRead(fd, buf, count: Int64): Int64;
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

function PXXSysClose(fd: Int64): Int64;
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

{ Byte-wise string equality for the cross targets' compare codegen. Operands are
  pre-decomposed into (length, data pointer) so it works uniformly for managed
  handles and inline strings. Returns 1 when equal, 0 otherwise. }
function PXXStrEq(lenA: Int64; srcA: Pointer; lenB: Int64; srcB: Pointer): Int64;
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

end.
