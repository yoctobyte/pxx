unit builtin;

{ Conversion helpers backing the Str and Val built-ins. The compiler pulls this
  unit in automatically, but only when a program actually uses Str or Val (a
  token pre-scan in ParseProgram), so programs that never call them pay nothing
  in code size. Pure Pascal — no syscalls, a small speed penalty versus inline
  asm, which is fine for these historic routines.

  - Str(x[:w[:d]], s) is rewritten by the parser to s := StrInt(x, w); the
    decimals field is parsed but ignored (integer Str only for now).
  - Val(s, n, code) is an ordinary call resolved straight to the Val below;
    it has no special ':' syntax, so it needs no parser rewrite.

  Dialect notes: plain functions, so named-result is fine but Result is used;
  strings are built by concatenation; no single-char-literal pitfalls remain. }

interface

function StrInt(v: Int64; width: Integer): string;
function FloatToStr(v: Double): string;
procedure Val(const s: string; var v: Int64; var code: Integer);
function VariantToStr(const v: Variant): AnsiString;
function PCharToString(p: PChar): string;

{ Heap allocator backing GetMem/New/class-new (PXXAlloc), FreeMem/Dispose (PXXFree),
  and ReallocMem (PXXRealloc). The compiler redirects those operations to these
  routines (see EmitHeapAllocLocked / EmitHeapFreeLocked in ir_codegen.inc), so
  every compiled program shares one mmap-backed Pascal heap. Block layout: an
  8-byte size header precedes each payload; freed blocks thread a singly linked
  free list through the first 8 bytes of their payload. align is accepted for ABI
  symmetry; payloads are always 8-aligned. }
function PXXAlloc(size: Int64; align: Integer): Pointer;
procedure PXXFree(p: Pointer);
function PXXRealloc(p: Pointer; newSize: Int64; align: Integer): Pointer;

implementation

type
  TVariantRecord = record
    VType: Int64;
    Payload: Int64;
  end;
  PVariantRecord = ^TVariantRecord;
  PDouble = ^Double;
  PAnsiString = ^AnsiString;

function VariantToStr(const v: Variant): AnsiString;
var
  p: PVariantRecord;
begin
  p := @v;
  if p^.VType = 1 then
    Result := StrInt(p^.Payload, 0)
  else if p^.VType = 3 then
    Result := FloatToStr(PDouble(@p^.Payload)^)
  else if p^.VType = 5 then
    Result := Chr(p^.Payload)
  else if p^.VType = 6 then
    Result := PAnsiString(@p^.Payload)^
  else if p^.VType = 0 then
    Result := 'None'
  else
    Result := '';
end;


function StrInt(v: Int64; width: Integer): string;
var
  neg: Boolean;
  digits: string;
  n: Int64;
  d: Integer;
begin
  digits := '';
  if v = 0 then
    digits := '0'
  else
  begin
    neg := v < 0;
    n := v;
    if neg then n := -n;
    while n > 0 do
    begin
      d := n mod 10;
      digits := Chr(Ord('0') + d) + digits;
      n := n div 10;
    end;
    if neg then digits := '-' + digits;
  end;
  Result := digits;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

function FloatToStr(v: Double): string;
{ Python-style natural decimal: [-]int.frac with trailing zeros trimmed but at
  least one fractional digit (5.0 -> "5.0"). Uses the Trunc/Frac/Round float
  intrinsics so all digit extraction is integer arithmetic. Mirrors the
  EmitWriteFloatNat codegen path used by writeln. }
var
  neg: Boolean;
  intpart, fracpart, divisor, rem, d: Int64;
  digits: string;
  i: Integer;
begin
  neg := v < 0;
  if neg then v := -v;
  intpart := Trunc(v);
  fracpart := Round(Frac(v) * 1000000000000000.0);   { scale fractional part to 15 digits }
  if fracpart >= 1000000000000000 then
  begin
    fracpart := fracpart - 1000000000000000;
    intpart := intpart + 1;
  end;
  Result := StrInt(intpart, 0);
  if neg then Result := '-' + Result;
  Result := Result + '.';
  digits := '';
  rem := fracpart;
  divisor := 100000000000000;                          { 1e14 }
  for i := 0 to 14 do
  begin
    d := rem div divisor;
    rem := rem mod divisor;
    digits := digits + Chr(Ord('0') + d);
    divisor := divisor div 10;
    if rem = 0 then break;                             { trailing zeros trimmed }
  end;
  Result := Result + digits;
end;

procedure Val(const s: string; var v: Int64; var code: Integer);
var
  i, len: Integer;
  neg, started: Boolean;
  n: Int64;
  c: Char;
begin
  v := 0;
  code := 0;
  n := 0;
  neg := False;
  started := False;
  len := Length(s);
  i := 1;
  while (i <= len) and (s[i] = ' ') do
    Inc(i);
  if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  while i <= len do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      n := n * 10 + (Ord(c) - Ord('0'));
      started := True;
      Inc(i);
    end
    else
      break;
  end;
  if (not started) or (i <= len) then
  begin
    { 1-based position of the first character that stopped the conversion }
    code := i;
    v := 0;
    Exit;
  end;
  if neg then n := -n;
  v := n;
  code := 0;
end;

function PCharToString(p: PChar): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  if p <> nil then
  begin
    i := 0;
    c := p[i];
    while c <> #0 do
    begin
      Result := Result + c;
      i := i + 1;
      c := p[i];
    end;
  end;
end;

{ ===== Heap allocator ===== }

type
  PWord = ^Int64;   { machine-word access at an arbitrary address }

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

end.
