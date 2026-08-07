{ SPDX-License-Identifier: Zlib }
unit builtinheap;

{ ESP (xtensa/bare riscv32) has no mmap and no OS heap of its own here; back the
  allocator with a fixed static arena instead. One marker for both ESP ISAs.
  HOSTED riscv32 (qemu-user linux) DOES have mmap and the linux syscall ABI (its
  read/write already use syscalls 63/64), so it must NOT take the static-arena
  path — a 64 KiB arena OOMs on any real workload (e.g. sqlite) and PXXAlloc then
  stores through a NULL base. Only bare-metal riscv32 (PXX_ESP_BARE) is ESP. }
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}{$endif}

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
  { Typed pointers for TVarRec's BOXED members. The union slot is pointer-sized, so a value
    wider than a pointer (a Double, an Int64, a ShortString) is stored BY ADDRESS -- and the
    field must be a typed pointer, not a bare Pointer, or `VExtended^` derefs to tyUnknown and
    every overload of the thing it is passed to fails to match. (That is exactly how fpjson's
    VarRecToJSON failed: "Mismatch in MatchProcCall: CreateJSON, arg[0] = 0".) }
  PVarRecInt64  = ^Int64;
  PVarRecDouble = ^Double;
  PVarRecStr    = ^string;

  TVarRec = record
    VType: NativeInt;
    VInteger: NativeInt;
    VAnsiString: Pointer;
    VBoolean: Boolean;
    VChar: Char;
    VPointer: Pointer;
    VPChar: Pointer;
    VInt64: PVarRecInt64;      { boxed: the union slot is only pointer-sized }
    VExtended: PVarRecDouble;  { likewise }
    { The rest of FPC's union. Adding a field here is SAFE and costs nothing:
      FixupTVarRecLayout overlays EVERY field after VType onto the single value slot, so the
      record stays a tag plus one pointer regardless of how many names are listed -- which is
      exactly what FPC's variant record is. These exist so code that reads an element BY TAG
      (fpjson's VarRecToJSON does, exhaustively) compiles; a tag this compiler never emits is
      simply a branch that never runs. }
    VObject: Pointer;
    VClass: Pointer;
    VString: PVarRecStr;       { FPC's PShortString; a string pointer here }
    VCurrency: PVarRecDouble;  { FPC's PCurrency; this RTL models Currency as Double }
    VVariant: Pointer;
    VInterface: Pointer;
    VWideChar: Word;
    VPWideChar: Pointer;
    VWideString: Pointer;
    VUnicodeString: Pointer;
    VQWord: PVarRecInt64;      { boxed }
  end;

const
  vtInteger    = 0;
  vtBoolean    = 1;
  vtChar       = 2;
  vtExtended   = 3;
  vtString     = 4;   { shortstring; unused with ansistrings }
  vtPointer    = 5;
  vtPChar      = 6;
  vtObject     = 7;
  vtClass      = 8;
  vtWideChar   = 9;
  vtPWideChar  = 10;
  vtAnsiString = 11;
  vtCurrency   = 12;
  vtVariant    = 13;
  vtInterface  = 14;
  vtWideString = 15;
  vtInt64      = 16;
  vtQWord      = 17;
  vtUnicodeString = 18;

function PXXAlloc(size: NativeInt; align: Integer): Pointer;
procedure PXXFree(p: Pointer);
function PXXRealloc(p: Pointer; newSize: NativeInt; align: Integer): Pointer;
{ Target-independent runtime: managed-string ARC helpers, mem copy/zero, and the
  dynamic-array SetLength. These use only PXXAlloc/PXXFree, so they build on
  every target including ESP. (PXXDynSetLen has an ESP-lean body that skips
  managed-element retain/release; same signature.) }
function PXXStrFromLit(len: NativeInt; src: Pointer): Pointer;
function PXXPCharOf(p: Pointer): Pointer;
{ The META word of a managed handle — BlockKind in the low byte, flags above.
  PXX_KIND_LEGACY (0) for nil and for any block whose creator did not stamp one,
  which every consumer must treat as "no information", never as an assertion.
  PXX_FLAG_ASCII is the one that pays: set, it means no byte is >= $80, so
  character positions equal byte positions and NilPy indexing stays O(1). Its
  ABSENCE means "unknown", not "non-ASCII" — a consumer must scan. }
function PXXHdrMeta(p: Pointer): Int64;
function PXXStrConcat(lenA: NativeInt; srcA: Pointer; srcB: Pointer; lenB: NativeInt): Pointer;
procedure PXXStrIncRef(p: Pointer);
procedure PXXStrDecRef(p: Pointer);
{ NilPy object reclamation (devdocs/dev/nilpy-object-reclamation.md): class
  instances created by NilPy code paths are refcounted like AnsiString handles.
  The instance pointer is base+16 of its own heap block, rc at [inst-16] — the
  same protocol as the string handles above. Pascal-created instances are NOT
  in this scheme; only allocations routed through PXXObjAlloc are. A headered
  instance is recognized at runtime by PXX_OBJ_MAGIC in the word at [inst-8]:
  a plain-GetMem instance has its allocator SIZE word there, always a multiple
  of 8, and the magic has low bits set — so the two populations cannot be
  confused, retain/release no-op on unheadered instances instead of corrupting
  a neighbour block, and PXXObjFree frees correctly either way. }
const
  { ---- managed-block header layout (devdocs/dev/managed-block-header.md) ----

      [kind:8][refcount:8][length:8][data...]      handle = block + PXX_HDR_SIZE

    From the HANDLE: length at -8, refcount at -16, **block base at -24**.
    Strings, dynamic arrays and objects all share this protocol (an object's
    third slot is the spare holding PXX_OBJ_MAGIC rather than a length).

    The kind word sits BELOW the refcount deliberately: length and refcount keep
    their handle-relative offsets, so the ~73 length reads and every
    retain/release blob across six backends are untouched, and only the free
    base moves. Use these constants rather than literals — the two `- 16`s that
    used to mean "refcount" and "block base" are now different addresses, and
    that is exactly the mistake this change can make silently.

    PHASE 1 writes PXX_KIND_LEGACY and never reads the word. Kinds arrive in
    phase 2 (feature-nilpy-text-string-kind), after this is pinned. }
  PXX_HDR_SIZE    = 24;   { total header bytes before the handle }
  PXX_HDR_META    = 0;    { offsets from the BLOCK BASE }
  PXX_HDR_RC      = 8;
  PXX_HDR_LEN     = 16;

  { ---- the META word ----
    BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8), bits 32-63 RESERVED.

    Everything meaningful lives in the LOW 32 BITS on purpose: a packed ILP32
    header would make this word 32 bits wide, and spending the upper half would
    foreclose that (feature-a-shrink-managed-header-on-32-bit). Do not widen a
    field past bit 31. }

  { BlockKind, bits 0-7. 0 = untagged: treat exactly as pre-phase-1 behaviour,
    which is what the x86-64 INLINE allocation paths still emit. An unknown
    kind must degrade to this, never assert. }
  PXX_KIND_LEGACY  = 0;
  PXX_KIND_BYTESTR = 1;   { Pascal AnsiString — Length counts BYTES (FPC-exact) }
  PXX_KIND_TEXTSTR = 2;   { NilPy str — public positions count CHARACTERS }
  PXX_KIND_DYNARRAY= 3;
  PXX_KIND_OBJECT  = 4;
  PXX_KIND_MAX     = 4;
  PXX_KIND_MASK    = $FF;

  { Flags, bits 8-15 }
  PXX_FLAG_STATIC   = $0100;   { .rodata, never freed — reserved, unused }
  PXX_FLAG_INTERNED = $0200;   { reserved, unused }
  PXX_FLAG_ASCII    = $0400;   { verified: no byte >= $80 }
  PXX_FLAG_EXTENDED = $0800;   { a side-table entry exists — the escape hatch }

  { KindData0, bits 16-23: text encoding. A small enum, NOT a codepage —
    CP_UTF8 (65001) would not fit, and this is the field pxx actually wants. }
  PXX_ENC_BYTES = 0;
  PXX_ENC_UTF8  = 1;
  PXX_ENC_UCS2  = 2;
  PXX_ENC_UCS4  = 3;
  PXX_ENC_SHIFT = 16;

  PXX_OBJ_MAGIC = $505942F1;   { low bits 001 — never an allocator size word }
  { RAW variant of the tag: a refcounted heap block that is NOT a class
    instance (no VMT at +0) — today only pybound_new's {code,recv} pairs.
    Release runs the finalize hook with raw=1 so the hook won't VMT-dispatch. }
  PXX_OBJ_MAGIC_RAW = $505942F9;
  { second RAW flavor: a pyeval closure object — finalized through the same
    hook with rawKind=2 (pylib forwards to pyeval's registry free) }
  PXX_OBJ_MAGIC_RAW2 = $505942E1;
type
  { Finalizer for a dying refcounted object, installed by pylib (which knows
    the container types). p = the object, raw = 1 for a RAW (VMT-less) block.
    Runs after rc hits 0 and before the block is freed; it releases the
    object's children recursively. nil = no finalizer (plain free). }
  TPXXObjFinalize = procedure(objp: Pointer; rawKind: NativeInt);
var
  PXXObjFinalizeHook: TPXXObjFinalize;
function PXXObjAlloc(size: NativeInt): Pointer;
function PXXObjAllocRaw(size: NativeInt): Pointer;
function PXXObjAllocRaw2(size: NativeInt): Pointer;
procedure PXXObjRetain(p: Pointer);
procedure PXXObjRelease(p: Pointer);
procedure PXXObjFree(p: Pointer);
{ TRUE iff p is a live PXX_OBJ_MAGIC_RAW block -- today that means exactly one
  thing, a pybound_new {code,recv} pair (see the constant's own comment) --
  so this doubles as "is this bare POINTER a bound-method/def-value object",
  usable anywhere only the unwrapped pointer survives (a callable-typed
  parameter boxed as Pointer, not Variant, loses the VType=8 tag that would
  normally answer this question).
  feature-nilpy-callable-value-unified-dispatch }
function PXXObjIsBoundPair(p: Pointer): Boolean;
{ COM/ARC interface ARC helpers dispatch through the IMT via an indirect call,
  which the ESP (xtensa/riscv32) backends cannot lower yet; ESP has no COM
  interfaces anyway, so exclude them there (their RegisterProc is likewise
  gated in parser.inc). }
{$ifndef PXX_ESP}
{ An interface VALUE is ONE pointer: the instance (FPC's ABI). The IMT — and so
  the _AddRef/_Release slots — is recovered from the instance's class RTTI blob
  by INTERFACE ID, which every call site knows statically. `p` is the address of
  the interface SLOT (the variable/field), `inst` a bare instance. }
function PXXIntfIMTOf(inst: Pointer; ifaceId: NativeInt): Pointer;
function PXXIntfAddRef(p: Pointer; ifaceId: NativeInt): NativeInt;
function PXXIntfRelease(p: Pointer; ifaceId: NativeInt): NativeInt;
function PXXIntfAddRefRaw(inst: Pointer; ifaceId: NativeInt): NativeInt;
procedure PXXIntfAssign(dest, src: Pointer; ifaceId: NativeInt);

{ ---- IInterface / TInterfacedObject: the COM root pair (FPC declares them in
  System) ----
  Declared HERE because builtinheap is pulled for every class-using program and
  is parsed before user declarations — so `TFoo = class(TInterfacedObject, IFoo)`,
  the single most-written FPC/Delphi interface idiom, resolves out of the box
  instead of silently building a parentless class whose ARC dispatch walks a
  garbage IMT slot (bug-pascal-tinterfacedobject-missing-silent-segfault).
  A COM-mode interface with no explicit parent implicitly derives IInterface
  (parser.inc), which is what reserves IMT slots 0..2 for QueryInterface /
  _AddRef / _Release — ARC releases through slot 2.
  NOTE: a user declaration of either name lands on a LATER UCls row and is
  shadowed by this one (FindUClass is first-match); the shapes are identical to
  FPC's, so that only matters if the user's version diverges from the FPC ABI. }
type
  HResult = LongInt;

  IInterface = interface
    ['{00000000-0000-0000-C000-000000000046}']   { the canonical IUnknown GUID }
    function QueryInterface(constref IID: TGuid; out Obj): HResult;
    function _AddRef: Integer;
    function _Release: Integer;
  end;
  IUnknown = IInterface;

  TInterfacedObject = class(TObject, IInterface)
    FRefCount: Integer;
    function QueryInterface(constref IID: TGuid; out Obj): HResult;
    function _AddRef: Integer;
    function _Release: Integer;
    { Virtual so a descendant's `destructor Destroy; override;` runs when the
      last interface reference drops (_Release dispatches Free -> Destroy). }
    destructor Destroy; virtual;
  end;
{$endif}
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
{ Exact 17-significant-digit decimal expansion of a finite non-zero |Double|.
  Exposed so builtin.pas's `Str(F, S)` shares the ONE correct implementation
  rather than carrying its own normalise loop (which disagreed with writeln's
  by a digit). See PxxSciDigits17's own header. }
procedure PxxSciDigits17(value: Double; var mant17: Int64; var decExp: Integer);
{$endif}
implementation


type
  PWord = ^NativeInt;  { pointer-sized machine-word access at an arbitrary
                         address: 8 bytes on 64-bit targets, 4 on 32-bit. Must
                         not be ^Int64 — on i386 that writes 8 bytes into a
                         4-byte handle/pointer slot and corrupts its neighbour. }
  PByte = ^Byte;    { byte access at an arbitrary address }
  PInt64 = ^Int64;  { qword access (dyn-array count header at [data-8]) }
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

{ Stamp a freshly allocated managed block's KIND word. Phase 1 writes
  "untagged", which every consumer must treat as today's behaviour; the debug
  build writes a witness instead so a free at the wrong base is caught at the
  free rather than as heap corruption later. Defined here, above every
  allocation site, because FPC requires declaration before use where pxx is lax
  — the seed build is the only way this change can be compiled at all. }
procedure PXXHdrInit(base: Int64);
begin
  PWord(base + PXX_HDR_META)^ := PXX_KIND_LEGACY;
end;

{ Stamp a block's meta word outright. Callers that know what they are building
  use this instead of PXXHdrInit; everything else stays untagged and behaves
  exactly as before. }
procedure PXXHdrSetMeta(base: Int64; meta: Int64);
begin
  PWord(base + PXX_HDR_META)^ := meta;
end;

{ The meta word for a freshly built managed STRING, given the OR of all its
  bytes. Kind stays LEGACY here: a byte string and a NilPy str are the same
  bytes and the same block, and which one it IS depends on the frontend that
  created it — the ASCII flag, by contrast, is a property of the bytes alone and
  is what makes character indexing O(1) for the overwhelmingly common string.
  Computing it costs one OR per byte in a loop that already touches every byte.
  (feature-nilpy-text-string-kind) }
function PXXStrMeta(orAll: Int64): Int64;
begin
  if (orAll and $80) = 0 then PXXStrMeta := PXX_KIND_LEGACY or PXX_FLAG_ASCII
  else PXXStrMeta := PXX_KIND_LEGACY;
end;

{ The meta word of a live handle, or PXX_KIND_LEGACY for nil. }
function PXXHdrMeta(p: Pointer): Int64;
begin
  if p = nil then PXXHdrMeta := PXX_KIND_LEGACY
  else PXXHdrMeta := PWord(Int64(p) - PXX_HDR_SIZE + PXX_HDR_META)^;
end;

{ Block base for a managed handle, and the ONLY thing that may be passed to
  PXXFree for one. Distinct from the refcount address at [p-16], which is a
  different slot now — conflating them is the mistake this change can make
  silently, so both have names. }
function PXXHdrBase(p: Pointer): Int64;
{$ifdef PXX_HEAP_DEBUG}
var hdrKind: Int64;
{$endif}
begin
{$ifdef PXX_HEAP_DEBUG}
  { 204 = invalid pointer operation. A bare Halt keeps this free of any I/O
    dependency at this depth in the heap; the halt SITE is the diagnosis —
    whoever called PXXHdrBase computed a handle whose block never came from a
    header initialiser, i.e. an offset is wrong.

    Phase 1 stamped a dedicated magic here; the meta word now carries real data,
    so the check became "is the kind byte a kind we know". Weaker against a wild
    pointer into live data, stronger where it matters: freed memory is $DD
    poison ($DD = 221 > PXX_KIND_MAX), so use-after-free is still caught. }
  if p <> nil then
  begin
    hdrKind := PWord(Int64(p) - PXX_HDR_SIZE + PXX_HDR_META)^ and PXX_KIND_MASK;
    if hdrKind > PXX_KIND_MAX then Halt(204);
  end;
{$endif}
  PXXHdrBase := Int64(p) - PXX_HDR_SIZE;
end;

function PXXHdrRC(p: Pointer): Int64;
begin
  PXXHdrRC := Int64(p) - PXX_HDR_SIZE + PXX_HDR_RC;   { = p - 16, unchanged }
end;

const
{$ifdef PXX_ESP}
  HEAP_ARENA = 65536;       { single 64 KiB static arena (fits ESP SRAM) }
{$else}
  HEAP_ARENA = 268435456;   { 256 MiB mmap chunk; anon pages fault in lazily }
{$endif}

const
  { Segregated free lists. Every allocation is already rounded up to a multiple of
    8, and the header at [p-8] stores that exact rounded size — so a freed block's
    size class is recoverable on free, and a bin holds blocks of EXACTLY one size.

    That is what makes alloc O(1): pop the head of bin[size], no walk, no
    size-mismatch reuse (first-fit used to hand a 200-byte block to a 16-byte
    request and never split it). Blocks of the same size also end up clustered,
    so locality comes for free — no profiling needed, the size is known at the
    call site.

    Sizes above the cap keep the old single first-fit list, whose walk is now over
    the RARE big blocks only. 64 bins x one word = 512 bytes of BSS, which the
    ESP static-arena build can afford too. }
  HEAP_BIN_MAX   = 512;                     { largest size with its own bin }
  HEAP_BIN_COUNT = HEAP_BIN_MAX div 8;      { 64: classes 8,16,...,512 }
  { -dPXX_HEAP_DEBUG only: how many freed blocks are held out of the free list
    before one is really reused. Big enough that a dangling read almost always
    lands on poison rather than on a recycled block; small enough that the ring
    is 8 KiB of BSS. }
  HEAP_QUAR_MAX  = 1024;
  HEAP_POISON    = $DD;                     { freed-payload fill byte }

var
  HeapPtr  : Int64;   { next free byte in the current arena (0 = none yet) }
  HeapEnd  : Int64;   { end address of the current arena }
  HeapLow  : Int64;   { lowest arena base ever mapped (0 = none yet) — with
                        HeapHigh, a conservative "is this plausibly one of our
                        heap payloads" range for the PXXObj* guards, which must
                        not deref header words of arbitrary values (a NilPy
                        None sentinel or boxed int reaching a retain would
                        otherwise fault reading [p-8]) }
  HeapHigh : Int64;   { highest arena end ever mapped }
  FreeList : Int64;   { head of the LARGE (> HEAP_BIN_MAX) free list, 0 = empty }
  { bin[i] holds blocks of exactly (i+1)*8 bytes. BSS-zeroed = all empty. }
  FreeBins : array[0..HEAP_BIN_COUNT-1] of Int64;
{$ifdef PXX_TS_SOFTLOCK}
  { --threadsafe on targets without x86-64's hand-emitted lock blobs (i386):
    a userspace spinlock guarding the allocator state (FreeList/HeapPtr/
    HeapEnd), taken INSIDE PXXAlloc/PXXFree so every entry — a codegen'd call
    site or another helper's internal allocation — is covered. Refcount ops
    use __pxxatomic_* instead of the lock (see PXXStrIncRef & friends).
    BSS-zeroed = free. }
  PXXHeapSpin : Integer;
{$endif}
{$ifdef PXX_HEAP_DEBUG}
  { ===== Debug heap: poison-on-free + quarantine =====
    Build with -dPXX_HEAP_DEBUG. Off by default and entirely inside ifdefs, so
    the shipped allocator is byte-identical without it.

    Why it exists: a use-after-free in this runtime presents as a PLAUSIBLE
    value, never as a fault. PXXAlloc zeroes a reused block, so a dangling read
    sees either zeros or whatever the block's new owner wrote — e.g. a freed
    TPyList whose header words had been recycled into a string, giving
    len() = 1751084129 (ASCII bytes read as an integer). Nothing in that number
    says "freed", which is what made
    bug-nilpy-slice-of-variant-local-returned-is-unusable cost three sessions.

    With this on, a freed payload is filled with $DD and held OUT of the free
    list for HEAP_QUAR_MAX further frees, so the dangling reader sees $DDDD...
    — an obviously absurd value at the point of the read rather than a plausible
    one far away. Two more bugs fall out of the same bookkeeping for free:
    a WRITE after free (the poison is verified when a block leaves quarantine)
    and a DOUBLE free (the payload is already fully poisoned on the way in). }
  HeapQuar      : array[0..HEAP_QUAR_MAX-1] of Int64;   { payload addrs }
  HeapQuarHead  : Integer;                 { index of the OLDEST entry }
  HeapQuarCount : Integer;
  { A report is RECORDED under the allocator lock and EMITTED after it is
    released — formatting a message can touch the heap, and doing that while
    holding the spinlock would deadlock the PXX_TS_SOFTLOCK build. }
  HeapDbgPend   : Integer;                 { 0 none, 1 double free, 2 write-after-free }
  HeapDbgAddr   : Int64;
{$endif}
  { A single shared, read-only NUL byte. PChar of an empty managed string (a nil
    handle) returns its address so the C boundary sees a valid empty C string, as
    FPC guarantees — never a nil dereference. BSS-zeroed, so it is always #0. }
  PXXEmptyChar : Char;
{$ifdef PXX_ESP}
  { 64 KiB static arena as Int64 cells so its base is 8-aligned (payloads sit
    at base+8, also 8-aligned). Handed out once; HeapMmap returns 0 after. }
  EspArena     : array[0..8191] of Int64;
  EspArenaUsed : Integer;
{$endif}

{ Anonymous mmap of len bytes; returns the base address (or the kernel's
  negative errno, which a subsequent access would fault on). }
function HeapMmap(len: Int64): Int64;
{$ifdef PXX_ESP}
var
  espZ: Int64;
{$endif}
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
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  { hosted linux (qemu-user): generic syscall ABI mmap = 222 (byte offset, 0 here).
    prot=PROT_READ|PROT_WRITE=3, flags=MAP_PRIVATE|MAP_ANONYMOUS=0x22=34. }
  Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0);
{$endif}
{$endif}
{$ifdef PXX_ESP}
  { Static arena: hand out the fixed buffer once (len is HEAP_ARENA here, so
    HeapEnd lines up). A second request means the arena is exhausted -> 0,
    which faults on the next access, signalling out-of-memory.
    Zero it on hand-out: an arena must be zero when PXXAlloc starts bumping
    through it (see the zero-init contract on PXXAlloc). The Linux path gets
    that free from MAP_ANONYMOUS; a static BSS buffer only gets it if startup
    zeroed .bss, which is not this unit's to assume. Once per boot. }
  if EspArenaUsed <> 0 then
    Result := 0
  else
  begin
    EspArenaUsed := 1;
    Result := Int64(@EspArena[0]);
    espZ := 0;
    while espZ < len do
    begin
      PWord(Result + espZ)^ := 0;
      espZ := espZ + SizeOf(NativeInt);
    end;
  end;
{$endif}
end;

{$ifdef PXX_ESP_IDF}
{ ESP-IDF profile (relocatable .o linked by idf.py): the pxx heap is backed by
  the IDF heap — calloc/free externals resolve to newlib/heap_caps at IDF link
  time. The hosted branch's linux mmap is an ecall that panics FreeRTOS
  (bug-esp-idf-heap-linux-mmap-ecall: any string literal passed to a `string`
  parameter allocates and died in HeapMmap); the bare-metal static arena is
  both tiny and redundant next to the SoC's real heap. calloc keeps PXXAlloc's
  zero-init contract; the same 8-byte size header as the native allocator
  preserves PXXRealloc's copy length. }
function calloc(n: NativeUInt; size: NativeUInt): Pointer; external;
procedure free(p: Pointer); external;

function PXXAlloc(size: NativeInt; align: Integer): Pointer;
var p: Int64;
begin
  if size <= 0 then size := 8;
  size := ((size + 7) div 8) * 8;
  p := Int64(calloc(1, NativeUInt(size + 8)));   { zeroed: keeps the contract }
  PWord(p)^ := size;                             { 8-byte size header }
  Result := Pointer(p + 8);                      { payload }
end;

procedure PXXFree(p: Pointer);
begin
  if p = nil then Exit;
  free(Pointer(Int64(p) - 8));
end;

function PXXRealloc(p: Pointer; newSize: NativeInt; align: Integer): Pointer;
var np: Pointer; oldSize: NativeInt;
begin
  np := PXXAlloc(newSize, align);
  if p <> nil then
  begin
    oldSize := NativeInt(PWord(Pointer(Int64(p) - 8))^);
    if oldSize > newSize then oldSize := newSize;
    PXXMemMove(np, p, oldSize);
    PXXFree(p);
  end;
  Result := np;
end;
{$else}
{$ifdef PXX_LIBC_HEAP}
{ Debug/diagnosis profile (-dPXX_LIBC_HEAP): back the pxx heap with dynamic
  libc malloc so VALGRIND (memcheck/massif) sees every allocation with its
  stack — the native arena/freelist allocator is invisible to it. Emitting the
  externals flips the ELF writer into dynamic mode (PT_INTERP + DT_NEEDED)
  automatically. Same 8-byte size header as the native allocator, calloc for
  the zero-init contract. HeapLow/HeapHigh become a coarse min/max envelope so
  PXXObjPlausible keeps working. NOT for production: no size-class bins, libc
  lock discipline instead of the pxx one. }
function pxx_libc_calloc(n: NativeUInt; size: NativeUInt): Pointer; cdecl; external 'libc.so.6' name 'calloc';
procedure pxx_libc_free(p: Pointer); cdecl; external 'libc.so.6' name 'free';

function PXXAlloc(size: NativeInt; align: Integer): Pointer;
var p: Int64;
begin
  if size <= 0 then size := 8;
  size := ((size + 7) div 8) * 8;
  p := Int64(pxx_libc_calloc(1, NativeUInt(size + 8)));
  PWord(p)^ := size;                             { 8-byte size header }
  Result := Pointer(p + 8);                      { payload }
  if (HeapLow = 0) or (p < HeapLow) then HeapLow := p;
  if p + size + 8 > HeapHigh then HeapHigh := p + size + 8;
end;

procedure PXXFree(p: Pointer);
begin
  if p = nil then Exit;
  pxx_libc_free(Pointer(Int64(p) - 8));
end;

function PXXRealloc(p: Pointer; newSize: NativeInt; align: Integer): Pointer;
var np: Pointer; oldSize: NativeInt;
begin
  np := PXXAlloc(newSize, align);
  if p <> nil then
  begin
    oldSize := NativeInt(PWord(Pointer(Int64(p) - 8))^);
    if oldSize > newSize then oldSize := newSize;
    PXXMemMove(np, p, oldSize);
    PXXFree(p);
  end;
  Result := np;
end;
{$else}
function PXXAlloc(size: NativeInt; align: Integer): Pointer;
var
  cur, prev, base, need, arena, i: Int64;
  bin: Integer;
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore: Int64;
{$endif}
begin
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore := 0;
  while Integer(__pxxatomic_xchg(@PXXHeapSpin, 1)) <> 0 do
    tsIgnore := tsIgnore + 1;
{$endif}
  if size <= 0 then size := 8;
  size := ((size + 7) div 8) * 8;          { round up to 8 }

  { Free-list nodes are payload addresses; the size header is at [cur-8] and the
    next link is parked in the payload at [cur]. A reused block holds stale bytes,
    so zero the span before handing it back — callers (managed refcount/length
    headers, zeroed dynarray/instance slots) assume fresh memory is zero, exactly
    like a bump block off a fresh mmap page. }

  { O(1) reuse for the common sizes: bin[class] holds blocks of EXACTLY this size,
    so the head is always an exact fit and there is nothing to walk. }
  if size <= HEAP_BIN_MAX then
  begin
    bin := Integer(size div 8) - 1;
    cur := FreeBins[bin];
    if cur <> 0 then
    begin
      FreeBins[bin] := PWord(cur)^;        { pop }
      i := 0;
      while i < size do
      begin
        PWord(cur + i)^ := 0;
        i := i + SizeOf(NativeInt);        { PWord writes one machine word: 8 on
                                             64-bit, 4 on 32-bit — must match the
                                             step or half the span is skipped }
      end;
      Result := Pointer(cur);
{$ifdef PXX_TS_SOFTLOCK}
      PXXHeapSpin := 0;
{$endif}
      Exit;
    end;
  end
  else
  begin
    { Large blocks keep the old first-fit list. The walk survives only here, where
      the blocks are rare. }
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
          i := i + SizeOf(NativeInt);
        end;
        Result := Pointer(cur);
{$ifdef PXX_TS_SOFTLOCK}
        PXXHeapSpin := 0;
{$endif}
        Exit;
      end;
      prev := cur;
      cur := PWord(cur)^;
    end;
  end;

  { Bump from the current arena, mapping a new one when it can't fit.

    Zero-init contract — PXXAlloc returns a ZEROED payload on BOTH paths, so a
    caller states one precondition and no more:
      - free-list reuse: explicitly zeroed above (the block holds stale bytes);
      - bump: the payload is virgin arena memory. HeapMmap *produces* a zeroed
        arena (MAP_ANONYMOUS on Linux; the ESP static arena is zeroed on
        hand-out), HeapPtr only ever moves forward, and a freed block never
        comes back this way — it returns through FreeList, which zeroes.
    Anything that changes the bump path (arena reuse, guard bytes, an arena from
    a source that is not zero) must re-produce the guarantee here, not push it
    back onto callers. }
  need := size + 8;                         { 8-byte size header + payload }
  if (HeapPtr = 0) or (HeapEnd - HeapPtr < need) then
  begin
    arena := need;
    if arena < HEAP_ARENA then arena := HEAP_ARENA;
    HeapPtr := HeapMmap(arena);
    HeapEnd := HeapPtr + arena;
    if (HeapLow = 0) or (HeapPtr < HeapLow) then HeapLow := HeapPtr;
    if HeapEnd > HeapHigh then HeapHigh := HeapEnd;
  end;
  base := HeapPtr;
  HeapPtr := HeapPtr + need;
  PWord(base)^ := size;                     { size header }
  Result := Pointer(base + 8);              { payload }
{$ifdef PXX_TS_SOFTLOCK}
  PXXHeapSpin := 0;
{$endif}
end;

{$ifdef PXX_HEAP_DEBUG}
function PXXSysWrite(fd, buf, count: NativeInt): Int64; forward;

{ Emit a pending report. Called with the allocator lock RELEASED — reporting
  formats a message and may itself touch the heap, and doing that under the
  spinlock would deadlock the PXX_TS_SOFTLOCK build against itself. }
const
  { The four report texts as CONSTANTS, indexed in place. They used to be
    assigned into a `msg: string` local, and that local is what hung the
    `--threadsafe -dPXX_HEAP_DEBUG` build: a managed local is finalized on the
    way out, the finalize enters the emitted string-release blob, and that blob
    takes the heap spinlock — which the caller is ALREADY holding, because
    EmitHeapFreeLocked calls PXXFree from inside the locked region and PXXFree
    ends here. One thread, one lock, taken twice: `lock xchg` spins forever.
    The routine's own header already says it must be callable with the
    allocator lock released; on x86-64 the lock is the hand-emitted one, which
    PXXFree cannot see, so the only safe rule is that this routine allocates
    NOTHING. Keep it that way — no managed local, no string temp.
    bug-a-threadsafe-plus-heap-debug-hangs-at-runtime }
  DBG_M1 = 'pxx-heap: DOUBLE FREE of 0x';
  DBG_M2 = 'pxx-heap: WRITE AFTER FREE in 0x';
  DBG_M3 = 'pxx-heap: RETAIN of a FREED object 0x';
  DBG_M4 = 'pxx-heap: RELEASE of a FREED object 0x';

procedure PXXDbgPutConst(kind: Integer);
{ One byte at a time out of a string CONSTANT — no managed temp anywhere. }
var i: NativeInt; b: Byte; r: Int64;
begin
  if kind = 1 then
    for i := 1 to Length(DBG_M1) do
    begin b := Byte(DBG_M1[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 2 then
    for i := 1 to Length(DBG_M2) do
    begin b := Byte(DBG_M2[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 3 then
    for i := 1 to Length(DBG_M3) do
    begin b := Byte(DBG_M3[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else
    for i := 1 to Length(DBG_M4) do
    begin b := Byte(DBG_M4[i]); r := PXXSysWrite(2, Int64(@b), 1); end;
end;

procedure PXXDbgFlush;
var i: NativeInt; b: Byte; r: Int64; v: Int64; d: Integer; kind: Integer;
begin
  if HeapDbgPend = 0 then Exit;
  kind := Integer(HeapDbgPend);
  HeapDbgPend := 0;
  PXXDbgPutConst(kind);
  { address in hex, high nibble first, no leading-zero suppression so the width
    is constant and greppable }
  i := (SizeOf(Pointer) * 8) - 4;
  while i >= 0 do
  begin
    v := HeapDbgAddr;
    d := Integer((v shr i) and 15);
    if d < 10 then b := Byte(48 + d) else b := Byte(87 + d);
    r := PXXSysWrite(2, Int64(@b), 1);
    i := i - 4;
  end;
  b := 10;
  r := PXXSysWrite(2, Int64(@b), 1);
end;

{ TRUE when a whole machine word reads as poison — i.e. the block it came from
  is in quarantine. Used on the object MAGIC word, which is never $DDDD... for
  a live object. }
function PXXDbgIsPoisonWord(w: Int64): Boolean;
var i: Integer; ok: Boolean;
begin
  ok := True;
  for i := 0 to SizeOf(Pointer) - 1 do
    if ((w shr (i * 8)) and 255) <> HEAP_POISON then ok := False;
  PXXDbgIsPoisonWord := ok;
end;

{ TRUE when the whole payload still reads as poison. }
function PXXDbgPoisonIntact(addr, sz: Int64): Boolean;
var i: Int64;
begin
  i := 0;
  while i < sz do
  begin
    if PByte(addr + i)^ <> HEAP_POISON then
    begin
      PXXDbgPoisonIntact := False;
      Exit;
    end;
    i := i + 1;
  end;
  PXXDbgPoisonIntact := True;
end;

{ Poison `addr` and put it in quarantine. Returns the block EVICTED by that
  push (which the caller must really free), or 0 while the ring is filling.
  The caller holds the allocator lock. }
function PXXDbgQuarantine(addr: Int64): Int64;
var sz, vic, vsz, i: Int64; slot: Integer;
begin
  sz := PWord(addr - 8)^;
  { A header we cannot trust (never allocated here, or already corrupted):
    poison only the one word the free list would overwrite anyway. }
  if (sz < 8) or (sz > (HeapHigh - HeapLow)) then sz := 8;

  { Freeing a block that is ALREADY entirely poison means it is still in
    quarantine — i.e. a double free. Report it and drop the second free, which
    is also what stops the ring holding one address twice. }
  if PXXDbgPoisonIntact(addr, sz) then
  begin
    HeapDbgPend := 1;
    HeapDbgAddr := addr;
    PXXDbgQuarantine := 0;
    Exit;
  end;

  vic := 0;
  if HeapQuarCount >= HEAP_QUAR_MAX then
  begin
    vic := HeapQuar[HeapQuarHead];
    { The victim has sat poisoned since it was freed. Anything that changed it
      wrote through a dangling pointer. }
    vsz := PWord(vic - 8)^;
    if (vsz < 8) or (vsz > (HeapHigh - HeapLow)) then vsz := 8;
    if not PXXDbgPoisonIntact(vic, vsz) then
    begin
      HeapDbgPend := 2;
      HeapDbgAddr := vic;
    end;
    HeapQuar[HeapQuarHead] := addr;
    HeapQuarHead := HeapQuarHead + 1;
    if HeapQuarHead >= HEAP_QUAR_MAX then HeapQuarHead := 0;
  end
  else
  begin
    slot := HeapQuarHead + HeapQuarCount;
    if slot >= HEAP_QUAR_MAX then slot := slot - HEAP_QUAR_MAX;
    HeapQuar[slot] := addr;
    HeapQuarCount := HeapQuarCount + 1;
  end;

  { Poison AFTER the victim was read out — the two blocks are distinct, but
    doing it in this order keeps the "in quarantine == fully poison" invariant
    the double-free check above relies on. }
  i := 0;
  while i < sz do
  begin
    PByte(addr + i)^ := HEAP_POISON;
    i := i + 1;
  end;
  PXXDbgQuarantine := vic;
end;
{$endif}

{$ifdef PXX_HEAP_DEBUG}
{ The free-list push, WITHOUT the lock — the caller holds it. Exists only for
  the debug heap, which runs a block through quarantine first and then releases
  the EVICTED victim through exactly this code. The default build keeps the
  push inline in PXXFree: a call per free is not worth paying for a facility
  that is off. }
procedure PXXFreePush(addr: Int64);
var
  sz: Int64;
  bin: Integer;
begin
  { The header carries the block's exact (already 8-rounded) size, so its size
    class is recoverable here — that is what lets alloc skip the walk entirely.
    Both pushes are O(1); the next link lives in the payload at [addr]. }
  sz := PWord(addr - 8)^;
  if (sz >= 8) and (sz <= HEAP_BIN_MAX) then
  begin
    bin := Integer(sz div 8) - 1;
    PWord(addr)^ := FreeBins[bin];
    FreeBins[bin] := addr;
  end
  else
  begin
    PWord(addr)^ := FreeList;               { large (or a header we cannot trust) }
    FreeList := addr;
  end;
end;
{$endif}

procedure PXXFree(p: Pointer);
var
  addr: Int64;
{$ifdef PXX_HEAP_DEBUG}
  victim: Int64;
{$else}
  sz: Int64;
  bin: Integer;
{$endif}
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore: Int64;
{$endif}
begin
  addr := Int64(p);
  if addr = 0 then Exit;
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore := 0;
  while Integer(__pxxatomic_xchg(@PXXHeapSpin, 1)) <> 0 do
    tsIgnore := tsIgnore + 1;
{$endif}
{$ifdef PXX_HEAP_DEBUG}
  { Poison and quarantine; only the EVICTED block (if any) really goes back on
    the free list. Returns 0 while the ring is still filling. }
  victim := PXXDbgQuarantine(addr);
  if victim <> 0 then PXXFreePush(victim);
{$else}
  { The header carries the block's exact (already 8-rounded) size, so its size
    class is recoverable here — that is what lets alloc skip the walk entirely.
    Both pushes are O(1); the next link lives in the payload at [addr]. }
  sz := PWord(addr - 8)^;
  if (sz >= 8) and (sz <= HEAP_BIN_MAX) then
  begin
    bin := Integer(sz div 8) - 1;
    PWord(addr)^ := FreeBins[bin];
    FreeBins[bin] := addr;
  end
  else
  begin
    PWord(addr)^ := FreeList;               { large (or a header we cannot trust) }
    FreeList := addr;
  end;
{$endif}
{$ifdef PXX_TS_SOFTLOCK}
  PXXHeapSpin := 0;
{$endif}
{$ifdef PXX_HEAP_DEBUG}
  PXXDbgFlush;                              { lock released — see PXXDbgFlush }
{$endif}
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
    i := i + SizeOf(NativeInt);              { one machine word per PWord copy —
                                               step 8 dropped every other word on
                                               32-bit (NativeInt=4) }
  end;
  PXXFree(p);
  Result := np;
end;
{$endif}
{$endif}  { PXX_ESP_IDF else: native allocator bodies }

{$ifdef PXX_ESP}
{ ESP lean dynamic array: unmanaged elements only (no per-element retain/release
  -- strings/records/nested arrays are not on ESP yet). Block layout matches the
  shared runtime: [refcount:word][length:word][data], handle = data pointer,
  length read at [handle-8]. desc layout: +4 elSize. }
procedure PXXDynArrayReleaseEsp(arrData: Pointer);
var rcAddr, rc: Int64;
begin
  if arrData = nil then Exit;
  rcAddr := PXXHdrRC(arrData);             { refcount — NOT the block base }
  rc := PWord(rcAddr)^ - 1;
  PWord(rcAddr)^ := rc;
  if rc <= 0 then PXXFree(Pointer(PXXHdrBase(arrData)));
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
  newBlock := PXXAlloc(PXX_HDR_SIZE + newLen * elSize, 8);
  PXXHdrInit(Int64(newBlock));
  PWord(Int64(newBlock) + PXX_HDR_RC)^ := 1;      { refcount }
  PWord(Int64(newBlock) + PXX_HDR_LEN)^ := newLen;          { length }
  newArrData := Pointer(Int64(newBlock) + PXX_HDR_SIZE);
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
  base, s, d, i, orAll, b: Int64;
begin
  if len <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(len + PXX_HDR_SIZE + 1, 8));   { +1 = nul terminator }
  PWord(base + PXX_HDR_RC)^ := 1;      { refcount }
  PWord(base + PXX_HDR_LEN)^ := len;   { length }
  d := base + PXX_HDR_SIZE;
  s := Int64(src);
  i := 0;
  orAll := 0;
  while i < len do
  begin
    b := PByte(s + i)^;
    PByte(d + i)^ := b;
    orAll := orAll or b;         { free: this loop already touches every byte }
    i := i + 1;
  end;
  PByte(d + len)^ := 0;         { nul terminator }
  PXXHdrSetMeta(base, PXXStrMeta(orAll));
  Result := Pointer(d);
end;

{ PChar/PAnsiChar of a managed string: the handle is already the NUL-terminated
  data pointer when non-empty, but an empty managed string is a nil handle. FPC
  guarantees PChar('') is a valid pointer to a static #0 byte (never nil), so a
  C/PAL call f(PChar(s)) on an empty s must not dereference nil. Substitute the
  shared empty #0 byte's address in that case. }
function PXXPCharOf(p: Pointer): Pointer;
begin
  if p = nil then
    Result := @PXXEmptyChar
  else
    Result := p;
end;

{ Managed-string concatenation: allocate a fresh block holding srcA[0..lenA)
  followed by srcB[0..lenB), nul-terminated. Returns the data pointer or nil
  for an empty result. Called from the AnsiStrConcatAddr shim under the heap
  lock. Raw pointers only. }
function PXXStrConcat(lenA: NativeInt; srcA: Pointer; srcB: Pointer; lenB: NativeInt): Pointer;
var
  total, base, d, s, i, orAll, b: Int64;
begin
  total := lenA + lenB;
  if total <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  base := Int64(PXXAlloc(total + PXX_HDR_SIZE + 1, 8));   { +1 = nul terminator }
  PWord(base + PXX_HDR_RC)^ := 1;        { refcount }
  PWord(base + PXX_HDR_LEN)^ := total;   { length }
  d := base + PXX_HDR_SIZE;
  orAll := 0;
  s := Int64(srcA);
  i := 0;
  while i < lenA do
  begin
    b := PByte(s + i)^;
    PByte(d + i)^ := b;
    orAll := orAll or b;
    i := i + 1;
  end;
  s := Int64(srcB);
  i := 0;
  while i < lenB do
  begin
    b := PByte(s + i)^;
    PByte(d + lenA + i)^ := b;
    orAll := orAll or b;
    i := i + 1;
  end;
  PByte(d + total)^ := 0;       { nul terminator }
  PXXHdrSetMeta(base, PXXStrMeta(orAll));
  Result := Pointer(d);
end;

function PXXSysRead(fd, buf, count: NativeInt): Int64;
begin
  Result := 0;   { xtensa (bare-only): no read syscall — dead stub there }
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
{$ifdef CPU_RISCV32}
  Result := __pxxrawsyscall(63, fd, buf, count);   { hosted linux (qemu-user) }
{$endif}
end;


function PXXSysWrite(fd, buf, count: NativeInt): Int64;
begin
  Result := 0;
{$ifdef CPUX86_64}
  Result := __pxxrawsyscall(1, fd, buf, count);
{$endif}
{$ifdef CPU_I386}
  Result := __pxxrawsyscall(4, fd, buf, count);
{$endif}
{$ifdef CPU_ARM32}
  Result := __pxxrawsyscall(4, fd, buf, count);
{$endif}
{$ifdef CPUAARCH64}
  Result := __pxxrawsyscall(64, fd, buf, count);
{$endif}
{$ifdef CPU_RISCV32}
  Result := __pxxrawsyscall(64, fd, buf, count);   { hosted linux (qemu-user) }
{$endif}
end;


{$ifndef PXX_ESP_BARE}
{ ===== Console input (read/readln) for the cross targets =====
  x86-64 keeps its hand-rolled asm path (EmitReadLine/EmitReadVarParse over the
  BSS_LINE_* scratch); the 32-bit/cross backends lower IR_READLINE /
  IR_READ_VAR / IR_READ_DISCARD to these portable helpers instead. Semantics
  mirror the x86-64 asm: one shared line buffer + cursor; a string target takes
  the rest of the line; a char one byte; integer kinds skip blanks then parse
  [-]digits. See feature-cross-readln-console-input. }
var
  PXXLineBuf: array[0..4095] of Byte;
  PXXLineLen: Int64;
  PXXLinePos: Int64;
  PXXPeekByte: Byte;      { pushed-back stdin byte held by PXXStdinEof }
  PXXPeekValid: Int64;

procedure PXXReadLine;
var n: Int64; b: Byte;
begin
  if PXXLinePos < PXXLineLen then Exit;   { unconsumed input on the line }
  PXXLinePos := 0;
  PXXLineLen := 0;
  while PXXLineLen < 4096 do
  begin
    { consume the byte Eof peeked (else it would be lost) before reading }
    if PXXPeekValid <> 0 then
    begin
      b := PXXPeekByte;
      PXXPeekValid := 0;
      n := 1;
    end
    else
      n := PXXSysRead(0, Int64(@b), 1);
    if n <= 0 then Break;                 { EOF / error: empty or short line }
    if b = 13 then Continue;              { skip \r }
    if b = 10 then Break;                 { \n ends the line (not stored) }
    PXXLineBuf[PXXLineLen] := b;
    PXXLineLen := PXXLineLen + 1;
  end;
end;

{ Bare `Eof` (stdin): not-eof while the line buffer holds unparsed content or a
  pushed-back byte; otherwise peek one byte (stashed for the next PXXReadLine).
  Mirrors the x86-64 EmitEof asm. }
function PXXStdinEof: Boolean;
var n: Int64;
begin
  if PXXLinePos < PXXLineLen then begin Result := False; Exit; end;
  if PXXPeekValid <> 0 then begin Result := False; Exit; end;
  n := PXXSysRead(0, Int64(@PXXPeekByte), 1);
  if n <= 0 then
    Result := True
  else
  begin
    PXXPeekValid := 1;
    Result := False;
  end;
end;

procedure PXXReadDiscard;
begin
  PXXLinePos := PXXLineLen;
end;

{ readln(s: AnsiString): rest of the line -> fresh managed string, published
  into the target slot (releases the old handle, nil-safe). }
procedure PXXReadVarStrM(slot: Pointer);
var len: Int64; oldp, newp: Pointer;
begin
  len := PXXLineLen - PXXLinePos;
  if len < 0 then len := 0;
  newp := PXXStrFromLit(len, @PXXLineBuf[PXXLinePos]);
  PXXLinePos := PXXLineLen;
  oldp := Pointer(PWord(slot)^);
  PWord(slot)^ := Int64(newp);
  PXXStrDecRef(oldp);
end;

{ readln(c: Char): one byte from the cursor, #0 when the line is exhausted. }
procedure PXXReadVarChar(dst: Pointer);
begin
  if PXXLinePos < PXXLineLen then
  begin
    PByte(dst)^ := PXXLineBuf[PXXLinePos];
    PXXLinePos := PXXLinePos + 1;
  end
  else
    PByte(dst)^ := 0;
end;

{ readln(i: <integer family>): skip blanks/tabs, optional '-', digits; store
  into dst at the target's width (sz = 1/2/4/8 bytes). }
procedure PXXReadVarInt(dst: Pointer; sz: NativeInt);
var v: Int64; neg: Boolean; b: Byte; d: Int64;
begin
  while (PXXLinePos < PXXLineLen) and
        ((PXXLineBuf[PXXLinePos] = 32) or (PXXLineBuf[PXXLinePos] = 9)) do
    PXXLinePos := PXXLinePos + 1;
  neg := False;
  if (PXXLinePos < PXXLineLen) and (PXXLineBuf[PXXLinePos] = 45) then
  begin
    neg := True;
    PXXLinePos := PXXLinePos + 1;
  end;
  v := 0;
  while PXXLinePos < PXXLineLen do
  begin
    b := PXXLineBuf[PXXLinePos];
    if (b < 48) or (b > 57) then Break;
    v := v * 10 + (b - 48);
    PXXLinePos := PXXLinePos + 1;
  end;
  if neg then v := -v;
  if sz = 1 then PByte(dst)^ := Byte(v)
  else if sz = 2 then
  begin
    PByte(dst)^ := Byte(v);
    PByte(Int64(dst) + 1)^ := Byte(v shr 8);
  end
  else if sz = 4 then
  begin
    d := Int64(dst);
    PByte(d)^ := Byte(v);
    PByte(d + 1)^ := Byte(v shr 8);
    PByte(d + 2)^ := Byte(v shr 16);
    PByte(d + 3)^ := Byte(v shr 24);
  end
  else
  begin
    d := Int64(dst);
    PByte(d)^ := Byte(v);
    PByte(d + 1)^ := Byte(v shr 8);
    PByte(d + 2)^ := Byte(v shr 16);
    PByte(d + 3)^ := Byte(v shr 24);
    PByte(d + 4)^ := Byte(v shr 32);
    PByte(d + 5)^ := Byte(v shr 40);
    PByte(d + 6)^ := Byte(v shr 48);
    PByte(d + 7)^ := Byte(v shr 56);
  end;
end;


{ ===== Console output helpers (hosted riscv32; portable) =====
  The riscv32 backend has no inline write codegen (its bare-metal ESP profile
  makes write/writeln a no-op); the HOSTED riscv32 leg lowers IR_WRITE /
  IR_WRITELN to these buffer-based helpers instead. Self-contained: they format
  into a local buffer and emit ONE PXXSysWrite — no write()-statement recursion
  (which would lower right back to the backend paths being implemented).
  Any backend could adopt them; see bug-riscv32-hosted-writeln-hello-hangs. }

procedure PXXWritePad(n: NativeInt);
var sp: Byte; r: Int64;
begin
  sp := 32;
  while n > 0 do
  begin
    r := PXXSysWrite(1, Int64(@sp), 1);
    n := n - 1;
  end;
end;

procedure PXXWriteCharW(c: NativeInt; wid: NativeInt);
var b: Byte; r: Int64;
begin
  if wid > 1 then PXXWritePad(wid - 1);
  b := Byte(c);
  r := PXXSysWrite(1, Int64(@b), 1);
end;

procedure PXXWriteNL;
var b: Byte; r: Int64;
begin
  b := 10;
  r := PXXSysWrite(1, Int64(@b), 1);
end;

{ [-]decimal of v (uns<>0: treat the 64-bit pattern as unsigned), right-aligned
  to wid (0 = none). }
procedure PXXWriteDecW(v: Int64; uns: NativeInt; wid: NativeInt);
var buf: array[0..23] of Byte; i, n: Integer; neg: Boolean; u: UInt64; t, d: Int64; r: Int64;
begin
  neg := False;
  if (uns = 0) and (v < 0) then
  begin
    neg := True;
    u := UInt64(-v);          { INT_MIN-safe: two's-complement negate }
  end
  else
    u := UInt64(v);
  i := 24;
  repeat
    { u div 10 without an unsigned 64-bit divide (the 32-bit backends only
      have SIGNED Int64 div): floor(u/10) = floor((u shr 1)/5) exactly, and
      u shr 1 < 2^63 makes the signed divide safe for the full u64 range. }
    t := Int64(u shr 1) div 5;
    d := Int64(u) - t * 10;   { 0..9 (wrap-consistent) }
    i := i - 1;
    buf[i] := 48 + Byte(d);
    u := UInt64(t);
  until u = 0;
  if neg then
  begin
    i := i - 1;
    buf[i] := 45;             { '-' }
  end;
  n := 24 - i;
  if wid > n then PXXWritePad(wid - n);
  r := PXXSysWrite(1, Int64(@buf[i]), n);
end;

{ TRUE/FALSE (FPC console form), right-aligned to wid. }
procedure PXXWriteBoolW(v: NativeInt; wid: NativeInt);
var buf: array[0..4] of Byte; n: Integer; r: Int64;
begin
  if v <> 0 then
  begin
    buf[0] := 84; buf[1] := 82; buf[2] := 85; buf[3] := 69;            { TRUE }
    n := 4;
  end
  else
  begin
    buf[0] := 70; buf[1] := 65; buf[2] := 76; buf[3] := 83; buf[4] := 69; { FALSE }
    n := 5;
  end;
  if wid > n then PXXWritePad(wid - n);
  r := PXXSysWrite(1, Int64(@buf[0]), n);
end;

{ Managed AnsiString handle (nil = empty), right-aligned to wid. }
procedure PXXWriteStrMW(p: Pointer; wid: NativeInt);
var len: Int64; r: Int64;
begin
  len := 0;
  if p <> nil then len := PWord(Int64(p) - 8)^;
  if wid > len then PXXWritePad(wid - len);
  if len > 0 then r := PXXSysWrite(1, Int64(p), len);
end;

{ Copy a NUL-terminated C string into a FROZEN string buffer (8-byte length
  prefix + chars), capped at 255 chars. ParamStr's hidden temp dest. }
procedure PXXCStrToFrozen(dst: Pointer; src: Pointer);
var len, i: Int64;
begin
  len := 0;
  if src <> nil then
    while (PByte(Int64(src) + len)^ <> 0) and (len < 255) do len := len + 1;
  PWord(dst)^ := len;
  PWord(Int64(dst) + 4)^ := 0;     { high half of the 8-byte length prefix }
  i := 0;
  while i < len do
  begin
    PByte(Int64(dst) + 8 + i)^ := PByte(Int64(src) + i)^;
    i := i + 1;
  end;
end;

{ Publish a managed handle into a string slot, releasing the old one. }
procedure PXXStrPublish(slot: Pointer; h: Pointer);
var oldp: Pointer;
begin
  oldp := Pointer(PWord(slot)^);
  PWord(slot)^ := Int64(h);
  PXXStrDecRef(oldp);
end;

{ Frozen string buffer (8-byte length prefix + chars), right-aligned to wid. }
procedure PXXWriteFrozenW(p: Pointer; wid: NativeInt);
var len: Int64; r: Int64;
begin
  len := PWord(p)^;
  if wid > len then PXXWritePad(wid - len);
  if len > 0 then r := PXXSysWrite(1, Int64(p) + 8, len);
end;

{ NUL-terminated C string (PChar), nil-safe. }
procedure PXXWriteCStr(p: Pointer);
var len: Int64; r: Int64;
begin
  if p = nil then Exit;
  len := 0;
  while PByte(Int64(p) + len)^ <> 0 do len := len + 1;
  if len > 0 then r := PXXSysWrite(1, Int64(p), len);
end;


{$endif}

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
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE + 1, 8));
  PXXHdrInit(base);
  PWord(base + PXX_HDR_RC)^ := 1;          { refcount }
  PWord(base + PXX_HDR_LEN)^ := size;      { length (corrected below) }
  d := base + PXX_HDR_SIZE;
  n := PXXSysRead(fd, d, size);
  if n < 0 then n := 0;
  PWord(base + PXX_HDR_LEN)^ := n;         { actual bytes read }
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
var rcAddr: Int64;
{$ifdef PXX_TS_SOFTLOCK}
    tsIgnore: Int64;
{$endif}
begin
  if p = nil then Exit;
  rcAddr := PXXHdrRC(p);
{$ifdef PXX_TS_SOFTLOCK}
  { threadsafe: atomic increment of the low refcount word (the count never
    approaches 2^32, so the 8-byte header's high dword stays zero). }
  tsIgnore := __pxxatomic_add(Pointer(rcAddr), 1);
{$else}
  PWord(rcAddr)^ := PWord(rcAddr)^ + 1;
{$endif}
end;

procedure PXXStrDecRef(p: Pointer);
var rcAddr, rc: Int64;
begin
  if p = nil then Exit;
  rcAddr := PXXHdrRC(p);
{$ifdef PXX_TS_SOFTLOCK}
  rc := __pxxatomic_add(Pointer(rcAddr), -1) - 1;   { returns the OLD value }
{$else}
  rc := PWord(rcAddr)^ - 1;
  PWord(rcAddr)^ := rc;
{$endif}
  { NOT Pointer(rcAddr): the refcount no longer sits at the block base — see
    the header note. This was one address before the kind word and is two now. }
  if rc = 0 then PXXFree(Pointer(PXXHdrBase(p)));
end;

{ NilPy object-reclamation primitives. An instance allocated here lives at
  base+16 of its own heap block: [rc:8][spare:8][instance data...], so the
  refcount sits at [inst-16] exactly like a managed string's — the same
  retain/release idiom (and the same threadsafe atomic) applies. The spare
  word at [inst-8] is reserved (zero); note it is NOT the RTTI backlink —
  that one lives before the VMT table, not before the instance.
  PXXObjRelease at rc=0 currently just frees the block; the recursive
  per-type finalizer (VMT `__finalize__` slot) is a later slice of
  feature-nilpy-object-reclamation and hooks in right before the free. }
{$ifdef PXX_OBJTRACE}
{ One line per refcount event, to stderr:  `objtrace <op> <hex addr> <rc>`.
  Ops: A alloc, R retain, r release, F free (rc reached 0).

  Build with -dPXX_OBJTRACE. Every bug in the NilPy object-reclamation family
  is the same question — who took a reference and who dropped it — and today
  that is answered by inferring backwards from a corrupted value. This answers
  it by reading the log:  `./prog 2>&1 | grep '<the address>'` gives the whole
  life of one object in order.

  Allocation-free on purpose: the line is built in a local byte buffer from
  character constants and emitted with ONE raw write. A trace that allocated
  would perturb the very heap it is reporting on, and would re-enter the
  allocator from inside PXXObjRelease -> PXXFree. }
procedure PXXObjTrace(op: NativeInt; p: Pointer; rc: Int64);
var buf: array[0..63] of Byte; n, i, d: Integer; v, r: Int64; neg: Boolean;
begin
  buf[0] := Ord('o'); buf[1] := Ord('b'); buf[2] := Ord('j');
  buf[3] := Ord('t'); buf[4] := Ord('r'); buf[5] := Ord('a');
  buf[6] := Ord('c'); buf[7] := Ord('e'); buf[8] := 32;
  buf[9] := Byte(op); buf[10] := 32;
  n := 11;
  buf[n] := Ord('0'); n := n + 1;
  buf[n] := Ord('x'); n := n + 1;
  i := (SizeOf(Pointer) * 8) - 4;
  v := Int64(p);
  while i >= 0 do
  begin
    d := Integer((v shr i) and 15);
    if d < 10 then buf[n] := Byte(48 + d) else buf[n] := Byte(87 + d);
    n := n + 1;
    i := i - 4;
  end;
  buf[n] := 32; n := n + 1;
  neg := rc < 0;
  if neg then rc := -rc;
  d := n;                                  { remember where the digits start }
  if rc = 0 then
  begin
    buf[n] := Ord('0'); n := n + 1;
  end
  else
    while rc > 0 do
    begin
      buf[n] := Byte(48 + Integer(rc mod 10));
      n := n + 1;
      rc := rc div 10;
    end;
  { the digits went out backwards — reverse them in place }
  i := n - 1;
  while d < i do
  begin
    v := buf[d]; buf[d] := buf[i]; buf[i] := Byte(v);
    d := d + 1; i := i - 1;
  end;
  if neg then
  begin
    buf[n] := Ord('-'); n := n + 1;        { sign trails; an rc below 0 is a bug anyway }
  end;
  buf[n] := 10; n := n + 1;
  r := PXXSysWrite(2, Int64(@buf[0]), n);
end;
{$endif}

function PXXObjAlloc(size: NativeInt): Pointer;
var base: Int64;
begin
  if size < 8 then size := 8;
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE, 8));
  PXXHdrInit(base);
  PWord(base + PXX_HDR_RC)^ := 1;                    { refcount }
  PWord(base + PXX_HDR_LEN)^ := PXX_OBJ_MAGIC;    { population tag, see the interface }
  Result := Pointer(base + PXX_HDR_SIZE);
{$ifdef PXX_OBJTRACE}
  PXXObjTrace(Ord('A'), Result, 1);
{$endif}
end;

function PXXObjAllocRaw(size: NativeInt): Pointer;
var base: Int64;
begin
  if size < 8 then size := 8;
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE, 8));
  PXXHdrInit(base);
  PWord(base + PXX_HDR_RC)^ := 1;                        { refcount }
  PWord(base + PXX_HDR_LEN)^ := PXX_OBJ_MAGIC_RAW;    { VMT-less block (bound pairs) }
  Result := Pointer(base + PXX_HDR_SIZE);
{$ifdef PXX_OBJTRACE}
  PXXObjTrace(Ord('A'), Result, 1);
{$endif}
end;

{ TRUE iff p can be one of our headered payloads: 8-aligned and inside the
  mapped-arena envelope with room for the 16-byte header below it. Values that
  fail are ints/sentinels/foreign pointers — the guards must not even READ
  their header words. }
function PXXObjPlausible(p: Pointer): Boolean;
begin
  PXXObjPlausible := (HeapLow <> 0) and ((Int64(p) and 7) = 0) and
                     (Int64(p) >= HeapLow + 24) and (Int64(p) < HeapHigh);
end;

function PXXObjIsBoundPair(p: Pointer): Boolean;
begin
  PXXObjIsBoundPair := (p <> nil) and PXXObjPlausible(p) and
                       (PWord(Int64(p) - 8)^ = PXX_OBJ_MAGIC_RAW);
end;

function PXXObjAllocRaw2(size: NativeInt): Pointer;
var base: Int64;
begin
  if size < 8 then size := 8;
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE, 8));
  PXXHdrInit(base);
  PWord(base + PXX_HDR_RC)^ := 1;                         { refcount }
  PWord(base + PXX_HDR_LEN)^ := PXX_OBJ_MAGIC_RAW2;    { pyeval closure object }
  Result := Pointer(base + PXX_HDR_SIZE);
{$ifdef PXX_OBJTRACE}
  PXXObjTrace(Ord('A'), Result, 1);
{$endif}
end;

procedure PXXObjRetain(p: Pointer);
var base, t: Int64;
{$ifdef PXX_TS_SOFTLOCK}
    tsIgnore: Int64;
{$endif}
begin
  if p = nil then Exit;
  if not PXXObjPlausible(p) then Exit;
  base := PXXHdrRC(p);            { refcount slot; the spare/magic is at base+8 }
  t := PWord(base + 8)^;
  if (t <> PXX_OBJ_MAGIC) and (t <> PXX_OBJ_MAGIC_RAW) and
     (t <> PXX_OBJ_MAGIC_RAW2) then
  begin
{$ifdef PXX_HEAP_DEBUG}
    { The magic reads as poison: this object is in quarantine, so somebody is
      retaining a pointer they already dropped. Without the debug heap this
      block would have been recycled and the magic would be whatever its new
      owner wrote — which is exactly why the ownership bugs in this runtime are
      invisible. Reported here rather than silently no-oped. }
    if PXXDbgIsPoisonWord(t) then
    begin
      HeapDbgPend := 3;
      HeapDbgAddr := Int64(p);
      PXXDbgFlush;
    end;
{$endif}
    Exit;                                  { not ours }
  end;
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore := __pxxatomic_add(Pointer(base), 1);
{$else}
  PWord(base)^ := PWord(base)^ + 1;
{$endif}
{$ifdef PXX_OBJTRACE}
  PXXObjTrace(Ord('R'), p, PWord(base)^);
{$endif}
end;

procedure PXXObjRelease(p: Pointer);
var base, rc, t: Int64;
begin
  if p = nil then Exit;
  if not PXXObjPlausible(p) then Exit;
  base := PXXHdrRC(p);            { refcount slot; the spare/magic is at base+8 }
  t := PWord(base + 8)^;
  if (t <> PXX_OBJ_MAGIC) and (t <> PXX_OBJ_MAGIC_RAW) and
     (t <> PXX_OBJ_MAGIC_RAW2) then
  begin
{$ifdef PXX_HEAP_DEBUG}
    { Releasing an object that is already in quarantine — a double release, the
      other half of the retain case above. }
    if PXXDbgIsPoisonWord(t) then
    begin
      HeapDbgPend := 4;
      HeapDbgAddr := Int64(p);
      PXXDbgFlush;
    end;
{$endif}
    Exit;                                  { not ours }
  end;
{$ifdef PXX_TS_SOFTLOCK}
  rc := __pxxatomic_add(Pointer(base), -1) - 1;   { returns the OLD value }
{$else}
  rc := PWord(base)^ - 1;
  PWord(base)^ := rc;
{$endif}
{$ifdef PXX_OBJTRACE}
  PXXObjTrace(Ord('r'), p, rc);
{$endif}
  if rc = 0 then
  begin
{$ifdef PXX_OBJTRACE}
    PXXObjTrace(Ord('F'), p, 0);
{$endif}
    { Run the type finalizer (releases children, recursing back through here)
      before the block goes away. Installed by pylib; nil in programs that
      never construct a refcounted object. }
    if PXXObjFinalizeHook <> nil then
    begin
      if t = PXX_OBJ_MAGIC_RAW then
        PXXObjFinalizeHook(p, 1)
      else if t = PXX_OBJ_MAGIC_RAW2 then
        PXXObjFinalizeHook(p, 2)
      else
        PXXObjFinalizeHook(p, 0);
    end;
    PXXFree(Pointer(PXXHdrBase(p)));
  end;
end;

{$ifndef PXX_ESP}
{ Forward only where the BODY exists — PXXClassFinalize is itself inside
  {$ifndef PXX_ESP}, so an unconditional forward left it unresolved on the
  ESP profile (test-emit-obj: "unresolved forward: PXXClassFinalize"). }
procedure PXXClassFinalize(inst: Pointer); forward;
{$endif}

{ Free an instance whichever population it belongs to: headered -> release
  (rc discipline), plain GetMem -> ordinary free. This is what the FreeMem
  tail of a `.Free` desugar lowers to in a NilPy compilation, so hand-written
  Pascal units (pyeval's TPyList arg lists, a user unit's obj.Free) stay
  correct when construction is rerouted through PXXObjAlloc.

  It owns the managed-field finalization for BOTH populations, and that is
  not a detail: the desugar used to emit PXXClassFinalize itself and then
  call here, so a headered instance was finalized twice — once inline, once
  again through PXXObjRelease's rc=0 hook (PyObjFinalize -> PXXClassFinalize).
  Every AnsiString field was released twice, so a string the CALLER still
  owned died at the second release (bug-heap-dict-literal-then-two-parses-
  corrupts: json.pas's `rd.FSrc := src` dropped the caller's own reference,
  and the freed block came back from the allocator while still in use).
  One destruction, one finalize:
    - headered -> PXXObjRelease only; it finalizes at rc=0 and NOT before, so
      an instance still referenced elsewhere also stops being finalized early;
    - plain GetMem -> finalize here, then free, exactly the old inline order. }
procedure PXXObjFree(p: Pointer);
begin
  if p = nil then Exit;
  if PXXObjPlausible(p) and (PWord(Int64(p) - 8)^ = PXX_OBJ_MAGIC) then
    PXXObjRelease(p)
  else
  begin
{$ifndef PXX_ESP}
    PXXClassFinalize(p);   { ESP has no class-layout finalizer to run }
{$endif}
    PXXFree(p);
  end;
end;

{ COM/ARC interface refcount helpers. `fatptr` is the ADDRESS of a 16-/8-byte
  interface fat pointer (word 0 = IMT, word 1 = instance). The IMT is the
  implementing class's Interface Method Table: a vector of code addresses,
  slot 1 = _AddRef, slot 2 = _Release (slot 0 = QueryInterface), so the call
  dispatches polymorphically into the concrete TInterfacedObject-derived method.
  Both are nil-safe (an uninitialised interface var is all-zero); _Release at
  zero frees the instance inside the dispatched method. }
{$ifndef PXX_ESP}
{ Blob offsets (see rtti_emit.inc / defs.inc RTTI_*): the class RTTI blob is at
  [[inst] - 8] (the backlink word before the VMT); its interface table is
  {GUID:16, IMT:8, id:8} entries. The parent chain is walked so an inherited
  implementation resolves. }
const
  PXXH_RTTI_PARENT  = 8;
  PXXH_RTTI_IFCOUNT = 80;
  PXXH_RTTI_IFACES  = 88;
  PXXH_RTTI_IFSIZE  = 32;
  PXXH_RTTI_IF_IMT  = 16;
  PXXH_RTTI_IF_ID   = 24;

function PXXIntfIMTOf(inst: Pointer; ifaceId: NativeInt): Pointer;
var rtti, ifaces, e, vmt: Pointer; cnt, i: NativeInt;
begin
  Result := nil;
  if inst = nil then Exit;
  vmt := Pointer(PWord(inst)^);
  if vmt = nil then Exit;
  rtti := Pointer(PWord(Pointer(Int64(vmt) - 8))^);
  while rtti <> nil do
  begin
    cnt := NativeInt(PWord(Pointer(Int64(rtti) + PXXH_RTTI_IFCOUNT))^);
    ifaces := Pointer(PWord(Pointer(Int64(rtti) + PXXH_RTTI_IFACES))^);
    if (cnt > 0) and (ifaces <> nil) then
      for i := 0 to cnt - 1 do
      begin
        e := Pointer(Int64(ifaces) + i * PXXH_RTTI_IFSIZE);
        if NativeInt(PWord(Pointer(Int64(e) + PXXH_RTTI_IF_ID))^) = ifaceId then
        begin
          Result := Pointer(PWord(Pointer(Int64(e) + PXXH_RTTI_IF_IMT))^);
          Exit;
        end;
      end;
    rtti := Pointer(PWord(Pointer(Int64(rtti) + PXXH_RTTI_PARENT))^);
  end;
end;

function PXXIntfAddRefRaw(inst: Pointer; ifaceId: NativeInt): NativeInt;
var imt: Pointer; fn: TPXXIntfMethod;
begin
  Result := 0;
  if inst = nil then Exit;
  imt := PXXIntfIMTOf(inst, ifaceId);
  if imt = nil then Exit;
  fn := TPXXIntfMethod(Pointer(PWord(Pointer(Int64(imt) + IMT_ADDREF_OFF))^));
  Result := fn(inst);
end;

function PXXIntfAddRef(p: Pointer; ifaceId: NativeInt): NativeInt;
var inst: Pointer;
begin
  Result := 0;
  if p = nil then Exit;
  inst := Pointer(PWord(p)^);
  Result := PXXIntfAddRefRaw(inst, ifaceId);
end;

function PXXIntfRelease(p: Pointer; ifaceId: NativeInt): NativeInt;
var imt, inst: Pointer; fn: TPXXIntfMethod;
begin
  Result := 0;
  if p = nil then Exit;
  inst := Pointer(PWord(p)^);
  if inst = nil then Exit;
  imt := PXXIntfIMTOf(inst, ifaceId);
  if imt = nil then Exit;
  fn := TPXXIntfMethod(Pointer(PWord(Pointer(Int64(imt) + IMT_RELEASE_OFF))^));
  Result := fn(inst);
end;

{ ARC-correct interface->interface assignment: retain the source, then release
  the old destination (this order is safe when dest and src alias), then copy the
  single-word value. }
procedure PXXIntfAssign(dest, src: Pointer; ifaceId: NativeInt);
begin
  PXXIntfAddRef(src, ifaceId);
  PXXIntfRelease(dest, ifaceId);
  PWord(dest)^ := PWord(src)^;
end;

{ GUID-keyed interface lookup for TInterfacedObject.QueryInterface — the same
  RTTI-blob walk as PXXIntfIMTOf, but matched on the 16-byte GUID at entry
  offset 0 instead of the interface id (a duplicate of builtin's
  __pxxGetInterface, which lives in a unit builtinheap must not depend on).
  Writes the instance pointer (an interface value IS the instance — FPC ABI)
  through objOut on a hit. }
function PXXTIOGetInterface(inst: Pointer; iid: Pointer; objOut: Pointer): NativeInt;
var
  vmt, rtti, ifaces, e: Pointer;
  cnt, i, j: NativeInt;
  pa, pb: PByte;
  same: Boolean;
begin
  Result := 0;
  if (inst = nil) or (iid = nil) then Exit;
  vmt := Pointer(PWord(inst)^);
  if vmt = nil then Exit;
  rtti := Pointer(PWord(Pointer(Int64(vmt) - 8))^);
  while rtti <> nil do
  begin
    cnt := NativeInt(PWord(Pointer(Int64(rtti) + PXXH_RTTI_IFCOUNT))^);
    ifaces := Pointer(PWord(Pointer(Int64(rtti) + PXXH_RTTI_IFACES))^);
    if (cnt > 0) and (ifaces <> nil) then
      for i := 0 to cnt - 1 do
      begin
        e := Pointer(Int64(ifaces) + i * PXXH_RTTI_IFSIZE);
        same := True;
        for j := 0 to 15 do
        begin
          pa := PByte(Int64(e) + j);
          pb := PByte(Int64(iid) + j);
          if pa^ <> pb^ then begin same := False; Break; end;
        end;
        if same then
        begin
          if objOut <> nil then PWord(objOut)^ := NativeInt(inst);
          Result := 1;
          Exit;
        end;
      end;
    rtti := Pointer(PWord(Pointer(Int64(rtti) + PXXH_RTTI_PARENT))^);
  end;
end;

function TInterfacedObject.QueryInterface(constref IID: TGuid; out Obj): HResult;
begin
  if PXXTIOGetInterface(Pointer(Self), @IID, @Obj) <> 0 then
    Result := 0
  else
    Result := HResult($80004002);   { E_NOINTERFACE }
end;

function TInterfacedObject._AddRef: Integer;
begin
  Self.FRefCount := Self.FRefCount + 1;
  Result := Self.FRefCount;
end;

function TInterfacedObject._Release: Integer;
begin
  Self.FRefCount := Self.FRefCount - 1;
  Result := Self.FRefCount;
  if Result = 0 then
    Self.Free;   { nil-guarded [virtual Destroy;] FreeMem — the Free desugar }
end;

destructor TInterfacedObject.Destroy;
begin
end;
{$endif}

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
var rcAddr: Int64;
{$ifdef PXX_TS_SOFTLOCK}
    tsIgnore: Int64;
{$endif}
begin
  if p = nil then Exit;
  rcAddr := PXXHdrRC(p);
{$ifdef PXX_TS_SOFTLOCK}
  tsIgnore := __pxxatomic_add(Pointer(rcAddr), 1);
{$else}
  PWord(rcAddr)^ := PWord(rcAddr)^ + 1;
{$endif}
end;

procedure PXXDynArrayReleaseDepth(arrData: Pointer; depth: Integer; baseKind: Integer; baseRecDesc: Pointer);
var
  rcAddr, rc, len: Int64;
  i: Int64;
  itemAddr: Pointer;
  elSize: Int64;
begin
  if arrData = nil then Exit;
  rcAddr := PXXHdrRC(arrData);            { refcount — NOT the block base }
{$ifdef PXX_TS_SOFTLOCK}
  rc := __pxxatomic_add(Pointer(rcAddr), -1) - 1;   { returns the OLD value }
{$else}
  rc := PWord(rcAddr)^ - 1;
  PWord(rcAddr)^ := rc;
{$endif}
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
    PXXFree(Pointer(PXXHdrBase(arrData)));
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

{ Element-aware release over a RAW element buffer of `len` elements — the exact
  mirror of PXXDynArrayRetainImmediate, and deliberately header-free: a STATIC
  array has no [refcount][length] prefix, so PXXDynArrayReleaseDepth (which
  decrements a header and may free the block) cannot serve it. Used by whole
  static-array assignment `b := a` to release the destination's old element
  handles before the bulk byte copy overwrites them.
  baseKind: 1 = AnsiString elements, 3 = record elements (walked via desc). }
procedure PXXArrayReleaseImmediate(arrData: Pointer; len: NativeInt; baseKind: Integer; baseRecDesc: Pointer);
var
  i: Int64;
  itemAddr: Pointer;
  elSize: Int64;
begin
  if arrData = nil then Exit;
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
    else if kind = 5 then
      memberSize := 16                   { Variant slot: [tag:8][payload:8] }
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
        5: { Variant field: release any managed/object payload, recursing
             through PXXObjRelease's finalizer for a held container
             (feature-nilpy-object-reclamation) }
          PXXVarClear(itemAddr);
        6: { NilPy class-typed field: drop the instance's ref on its child
             (magic-guarded — a Pascal instance stored here no-ops) }
          PXXObjRelease(Pointer(PWord(itemAddr)^));
      end;
      j := j + 1;
    end;

    memberPtr := memberPtr + 16;
    i := i + 1;
  end;
end;

procedure PXXClassFinalize(inst: Pointer);
{ Release a CLASS instance's managed fields on destruction, by its RUNTIME
  class: [inst] = VMT, [VMT-16] = the layout descriptor EmitLayoutRTTI emitted
  (nil = nothing to finalize). Runs between the user Destroy chain and FreeMem
  (the Free desugar inserts the call), matching FPC's FreeInstance timing.

  Two passes, split by lock discipline
  (bug-a-class-managed-fields-not-finalized-on-destroy):
  - kind 4 (COM interface): released FIRST, with NO heap lock held — the release
    runs the referenced object's destructor chain and self-locking FreeMem, so
    doing it under a lock would deadlock (the reverted cb2ed843 hit exactly
    that on the record path).
  - kinds 1-3 (string/dynarray/record): PXXRecordRelease, whose inner frees are
    self-locking on softlock targets and lock-free single-threaded. On x86-64
    --threadsafe the heap lock is the codegen BSS spinlock, unreachable from
    Pascal — skip the pass there (pre-existing benign leak) rather than race
    the allocator. PXXRecordRelease has no kind-4 case, so interfaces are not
    double-released. }
var
  vmt, desc: Pointer;
  memberCount, i, offset, kind, typeRef: Integer;
  memberPtr: Int64;
begin
  if inst = nil then Exit;
  vmt := Pointer(PWord(inst)^);
  if vmt = nil then Exit;
  desc := Pointer(PWord(Pointer(Int64(vmt) - 16))^);
  if desc = nil then Exit;

  memberCount := PInt32(Int64(desc) + 8)^;
  memberPtr := Int64(desc) + 12;
  i := 0;
  while i < memberCount do
  begin
    kind := PInt32(memberPtr + 4)^;
    if kind = 4 then
    begin
      offset := PInt32(memberPtr)^;
      typeRef := PInt32(memberPtr + 12)^;
      PXXIntfRelease(Pointer(Int64(inst) + offset), typeRef);
      PWord(Pointer(Int64(inst) + offset))^ := 0;
    end;
    memberPtr := memberPtr + 16;
    i := i + 1;
  end;

{$ifndef PXX_TS_HARDLOCK}
  PXXRecordRelease(inst, desc);
{$endif}
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

  newBlock := PXXAlloc(PXX_HDR_SIZE + len * elSize, 8);
  PXXHdrInit(Int64(newBlock));
  PWord(Int64(newBlock) + PXX_HDR_RC)^ := 1;
  PWord(Int64(newBlock) + PXX_HDR_LEN)^ := len;
  newArrData := Pointer(Int64(newBlock) + PXX_HDR_SIZE);

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

  newBlock := PXXAlloc(PXX_HDR_SIZE + newLen * elSize, 8);
  PXXHdrInit(Int64(newBlock));
  PWord(Int64(newBlock) + PXX_HDR_RC)^ := 1;
  PWord(Int64(newBlock) + PXX_HDR_LEN)^ := newLen;
  newArrData := Pointer(Int64(newBlock) + PXX_HDR_SIZE);

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

  newBase := PXXAlloc(newLen + PXX_HDR_SIZE + 1, 8);
  PXXHdrInit(Int64(newBase));
  PWord(Int64(newBase) + PXX_HDR_RC)^ := 1;        { refcount }
  PWord(Int64(newBase) + PXX_HDR_LEN)^ := newLen;  { length }
  newData := Pointer(Int64(newBase) + PXX_HDR_SIZE);

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

{ Dynamic-array Delete/Insert support. The compiler lowers Delete/Insert on a
  dynamic array into a fresh SetLength'd temp filled from the (still intact)
  old buffer via these helpers, then assigns the temp back — see
  AN_DYN_DELETE / AN_DYN_INSERT in ir.inc. Copying old-buffer -> new-buffer is
  never self-overlapping, so the forward-only PXXMemCopy applies in both
  directions of the shift. }

{ Element count of a dyn-array data block (0 for a nil/empty handle). }
function PXXDynLen(srcData: Pointer): NativeInt;
begin
  if srcData = nil then Result := 0
  else Result := PWord(Int64(srcData) - 8)^;
end;

{ Length after Delete(arr, index, count). FPC clamp semantics: index < 0 or
  >= len removes nothing; count is clamped to [0 .. len-index]. }
function PXXDynDelNewLen(srcData: Pointer; index: NativeInt; count: NativeInt): NativeInt;
var len, removed: Int64;
begin
  len := PXXDynLen(srcData);
  if (index < 0) or (index >= len) then removed := 0
  else
  begin
    removed := count;
    if removed > len - index then removed := len - index;
    if removed < 0 then removed := 0;
  end;
  Result := len - removed;
end;

{ Fill the fresh Delete destination (PXXDynDelNewLen elements): head
  [0..index) then tail [index+removed .. len), same clamping as above.
  Returns destData (a function so the lowering can store the result to link
  the call into the statement stream, like PXXMemCopy in AN_DYN_COPY). }
function PXXDynDelFill(destData: Pointer; srcData: Pointer; index: NativeInt; count: NativeInt; elemSize: NativeInt): Pointer;
var len, removed, headB, tailB: Int64; dummy: Pointer;
begin
  len := PXXDynLen(srcData);
  if (index < 0) or (index >= len) then removed := 0
  else
  begin
    removed := count;
    if removed > len - index then removed := len - index;
    if removed < 0 then removed := 0;
  end;
  Result := destData;
  if removed = 0 then
  begin
    if len > 0 then dummy := PXXMemCopy(destData, srcData, len * elemSize);
    Exit;
  end;
  headB := index * elemSize;
  tailB := (len - index - removed) * elemSize;
  if headB > 0 then dummy := PXXMemCopy(destData, srcData, headB);
  if tailB > 0 then
    dummy := PXXMemCopy(Pointer(Int64(destData) + headB),
                        Pointer(Int64(srcData) + headB + removed * elemSize), tailB);
end;

{ Fill the fresh Insert destination (len+1 elements): head [0..pos), a
  one-element gap at pos, tail [pos..len). pos = index clamped to [0..len]
  (FPC semantics). Returns the gap's address for the element store. }
function PXXDynInsFill(destData: Pointer; srcData: Pointer; index: NativeInt; elemSize: NativeInt): Pointer;
var len, headB, tailB: Int64; dummy: Pointer;
begin
  len := PXXDynLen(srcData);
  if index < 0 then index := 0;
  if index > len then index := len;
  headB := index * elemSize;
  tailB := (len - index) * elemSize;
  if headB > 0 then dummy := PXXMemCopy(destData, srcData, headB);
  if tailB > 0 then
    dummy := PXXMemCopy(Pointer(Int64(destData) + headB + elemSize),
                        Pointer(Int64(srcData) + headB), tailB);
  Result := Pointer(Int64(destData) + headB);
end;

type
  TPXXDivZeroProc = procedure;
var
  { Installed at startup by an exception-providing unit (future sysutils-style
    hook) to convert division by zero into a raised, catchable exception —
    mirrors FPC's System.ErrorProc design. Default nil = FPC-without-sysutils
    behavior below. BSS, so nil without any initialization code. }
  PXXDivZeroHook: TPXXDivZeroProc;

{ Integer div/mod by zero. The backend's pre-divide check calls this instead of
  letting the divide execute (x86 would raw-SIGFPE; ARM would silently yield 0).
  FPC behavior: "Runtime error 200" + exit code 200. Never returns unless a
  hook raises past it. }
procedure PXXDivZero;
begin
  if PXXDivZeroHook <> nil then PXXDivZeroHook();
  writeln('Runtime error 200 (division by zero)');
  Halt(200);
end;

var
  { Installed by sysutils' initialization to convert a {$Q+} arithmetic
    overflow into a raised, catchable EIntOverflow — same design as
    PXXDivZeroHook above. Default nil = FPC-without-sysutils behavior. }
  PXXOverflowHook: TPXXDivZeroProc;

{ {$Q+} overflow trap target: the checked add/sub/mul codegen branches here
  when the operation wrapped. FPC behavior: "Runtime error 215" + exit code
  215. Never returns unless a hook raises past it.
  feature-pascal-overflow-checks-q-plus. }
procedure PXXOverflow;
begin
  if PXXOverflowHook <> nil then PXXOverflowHook();
  writeln('Runtime error 215 (arithmetic overflow)');
  Halt(215);
end;

var
  { Installed by sysutils' initialization to convert a {$R+} range violation
    into a raised, catchable ERangeError — third of the hook family. }
  PXXRangeErrorHook: TPXXDivZeroProc;
  { 4th of the family: installed by sysutils to convert a {$I+} Text-I/O
    failure into a raised EInOutError (feature-pascal-io-checks-i-plus). }
  PXXIoErrorHook: TPXXDivZeroProc;

{ {$R+} range trap: FPC behavior 'Runtime error 201' + exit code 201.
  feature-pascal-range-checks-r-plus. }
procedure PXXRangeError;
begin
  if PXXRangeErrorHook <> nil then PXXRangeErrorHook();
  writeln('Runtime error 201 (range check error)');
  Halt(201);
end;

{ {$R+} narrowing-assignment guard: the parser wraps the assigned value in
  this call when the destination's ordinal range is narrower than the
  computed width. Pure Pascal, so every target gets range checks for free. }
function PXXRangeChkI64(v, lo, hi: Int64): Int64;
begin
  if (v < lo) or (v > hi) then PXXRangeError;
  Result := v;
end;

{ {$R+} dynamic-array index guard: count lives at [data-8] (the dyn-array
  header), nil = length 0. Returns the index unchanged when in range. }
function PXXDynIdxChkI64(dataPtr: Pointer; idx: Int64): Int64;
var cnt: Int64;
begin
  if dataPtr = nil then cnt := 0
  else cnt := PInt64(Int64(dataPtr) - 8)^;
  if (idx < 0) or (idx >= cnt) then PXXRangeError;
  Result := idx;
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
        { A side whose tag is neither string nor char (mixed string/number)
          compares unequal, unordered. }
        if not (((lTag = 5) or (lTag = 6)) and ((rTag = 5) or (rTag = 6))) then
        begin
          if opTk = 65 then Result := 1 else Result := 0; { tkNeq = 65 }
          Exit;
        end;

        if (lTag = 5) and (rTag = 5) then
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
          { String (or char-vs-string) comparison, lexicographic. A char side
            reads its payload as a 1-byte buffer at the slot, mirroring the
            concat arm below. }
          if lTag = 5 then
          begin
            lStr := Pointer(Int64(left) + 8);
            lLen := 1;
          end
          else
          begin
            lStr := Pointer(lVal);
            if lStr = nil then lLen := 0 else lLen := PWord(Int64(lStr) - 8)^;
          end;
          if rTag = 5 then
          begin
            rStr := Pointer(Int64(right) + 8);
            rLen := 1;
          end
          else
          begin
            rStr := Pointer(rVal);
            if rStr = nil then rLen := 0 else rLen := PWord(Int64(rStr) - 8)^;
          end;

          { resVal = -1 / 0 / +1 ordering: byte compare over the common
            prefix, then the shorter string orders first. }
          resVal := 0;
          lVal := 0;                      { reused as the byte index }
          while (resVal = 0) and (lVal < lLen) and (lVal < rLen) do
          begin
            rVal := Int64(PByte(Int64(lStr) + lVal)^) - Int64(PByte(Int64(rStr) + lVal)^);
            if rVal < 0 then resVal := -1
            else if rVal > 0 then resVal := 1;
            lVal := lVal + 1;
          end;
          if resVal = 0 then
          begin
            if lLen < rLen then resVal := -1
            else if lLen > rLen then resVal := 1;
          end;

          if opTk = 64 then Result := Int64(resVal = 0)
          else if opTk = 65 then Result := Int64(resVal <> 0)
          else if opTk = 66 then Result := Int64(resVal < 0)
          else if opTk = 67 then Result := Int64(resVal <= 0)
          else if opTk = 68 then Result := Int64(resVal > 0)
          else if opTk = 69 then Result := Int64(resVal >= 0)
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
  32-bit targets leave no stale high halves behind). Object payloads
  (VT_OBJECT 7 / VT_BOUNDMETHOD 8 / VT_PYCLOSURE 9 / VT_BOUNDFN 10) ride
  PXXObjRelease, whose PXX_OBJ_MAGIC guard makes it a no-op on
  manual-lifetime Pascal instances. A promo-block tag (8192..8199) rides in a
  variant as a managed AnsiString of its decimal — same release as VT_STRING
  (mirrors the x86-64 EmitVariantClear range test; this portable body
  previously missed it, a cross-target leak).

  THE OBJECT-TAG LIST LIVES IN FOUR PLACES and they must agree — this pair,
  the x86-64 EmitVariantClear/EmitVariantRetain (compiler/ir_codegen.inc),
  and PyVarSlotIsObj (compiler/builtin/pylib.pas). A tag added to the emitters
  but not here does not fail loudly: the slot is simply never released, and
  the only symptom is RSS. Tag 10 was missed here exactly that way, and it is
  what made an ESCAPING closure keep leaking after the object itself had been
  given a refcount — the caller's hidden-destination temp for a
  variant-returning call is re-prepared through this routine once per loop
  iteration (bug-nilpy-bound-fn-closure-objects-are-never-freed). }
begin
  if (PWord(v)^ = 6) or ((PWord(v)^ >= 8192) and (PWord(v)^ <= 8199)) then
    PXXStrDecRef(Pointer(PWord(Int64(v) + 8)^))
  else if (PWord(v)^ >= 7) and (PWord(v)^ <= 10) then
    PXXObjRelease(Pointer(PWord(Int64(v) + 8)^));
  PXXMemZero(v, 16);
end;

procedure PXXVarRetain(v: Pointer);
{ The exact mirror of PXXVarClear — see the four-places note there. }
begin
  if (PWord(v)^ = 6) or ((PWord(v)^ >= 8192) and (PWord(v)^ <= 8199)) then
    PXXStrIncRef(Pointer(PWord(Int64(v) + 8)^))
  else if (PWord(v)^ >= 7) and (PWord(v)^ <= 10) then
    PXXObjRetain(Pointer(PWord(Int64(v) + 8)^));
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

function PxxIntDDigits(pv: Pointer; emit: NativeInt): NativeInt; forward;

procedure PXXWriteUIntD(pv: Pointer);
{ Print a non-negative integral double in decimal (writeUInt, double domain).

  Past 2^53 the divide-down loop below cannot work: consecutive integers are no
  longer distinct doubles there, so `v / p` recovers the value's BINARY
  granularity rather than its decimal digits — 1e25 printed
  10000000000000002147483648, where the tail is 2^31 and no part of the number.
  Above that threshold the value is an exact integer of the form mant * 2^exp2
  with exp2 >= 0, so PxxIntDDigits expands it exactly in base-10^9 integer limbs
  and every digit emitted is a real digit.
  bug-a-write-fixed-emits-false-digits-past-1e22 }
var v, p, two53: Double; d, i: Integer; ch: Char; nd: NativeInt;
begin
  v := PDouble(pv)^;
  two53 := 1;
  for i := 1 to 53 do two53 := two53 * 2;
  if v >= two53 then
  begin
    nd := PxxIntDDigits(pv, 1);
    Exit;
  end;
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

procedure PXXWriteFloatFixed(p: Pointer; decimals: NativeInt; width: NativeInt);
{ [-]intpart.frac with exactly 'decimals' fractional digits (0 -> rounded
  integer, no point). Mirrors EmitWriteFloatFixed (x86-64), and must keep
  mirroring it: this is the i386 / arm32 / riscv32 route to the same output, so
  a program's text must not depend on which backend built it.

  The INTEGER AND FRACTIONAL parts are scaled SEPARATELY, for the same reason
  the x86-64 emitter does it: scaling the whole value by 10^decimals pushes it
  past the 53-bit mantissa long before it runs out of exponent, so the low
  digits become the scale's granularity rather than the number's — `267.5:0:20`
  printed 267.50000000000000524288, where 524288 is 2^19 and no part of the
  value (bug-b-writeln-float-with-17-decimals-prints-garbage).

  Splitting first keeps the product below 1e18, and digits past the 18th are
  printed as zeros rather than guessed: a double carries no information there,
  and FPC pads the same way. }
var x, pw, v, ip, rem, dv, r, two52, ipc: Double; d, fdigits: Integer; i: Int64; ch: Char;
    neg: Boolean; ndig, total: Int64;
begin
  { NON-FINITE first — see PXXWriteFloatSci. The digit loops here do not
    terminate on an infinity either, and on x86-64 the native twin does not hang
    but scales through Int64 and prints 9223372036854775809.000000, which is the
    silent half of the same defect. A fixed-decimals request cannot be honoured
    for a value with no digits, so the spelling wins over the field
    (bug-a-writeln-of-a-non-finite-double-hangs). }
  x := PDouble(p)^;
  if x <> x then
  begin
    write(' Nan');
    Exit;
  end;
  if x > 1.7976931348623157e308 then
  begin
    write(' Inf');
    Exit;
  end;
  if x < -1.7976931348623157e308 then
  begin
    write('-Inf');
    Exit;
  end;
  two52 := 1;
  i := 1;
  while i <= 52 do
  begin
    two52 := two52 * 2;
    i := i + 1;
  end;
  x := PDouble(p)^;
  neg := PByte(Int64(p) + 7)^ >= 128;
  if neg then x := -x;
  fdigits := decimals;
  if fdigits > 18 then fdigits := 18;
  pw := 1;
  i := 1;
  while i <= fdigits do
  begin
    pw := pw * 10;
    i := i + 1;
  end;
  { ip := trunc(x), by the round-even-then-correct-down trick used above }
  if x >= two52 then
    ip := x
  else
  begin
    r := x + two52;
    r := r - two52;
    if r > x then r := r - 1;
    ip := r;
  end;
  { rem := round-half-AWAY((x - ip) * pw). The fraction is below 1, so the
    product stays under 1e18 and every digit of it is a digit of the value; the
    +0.5-then-truncate is FPC's rounding rule for write(v:w:d), measured
    (0.5/1.5/2.5 at :0:0 print 1/2/3, not round-to-even's 0/2/2). x is
    non-negative here, the sign having been printed and removed. }
  v := (x - ip) * pw + 0.5;
  if v < two52 then
  begin
    r := v + two52;
    rem := r - two52;
    if rem > v then rem := rem - 1;      { round-even then correct down = trunc }
  end
  else
    rem := v;
  if rem >= pw then          { the fraction rounded up to 1.0 }
  begin
    rem := 0;
    ip := ip + 1;
  end;
  { FIELD WIDTH. Counted AFTER the rounding above, because a carry out of the
    fraction (9.96:0:1 -> 10.0) adds an integer digit and would otherwise pad
    one column too many. ip is a non-negative integral Double here, possibly
    past 2^63, so the digit count is taken in double arithmetic rather than
    through Int64 — the same reason this routine exists rather than the
    Int64-scaling native emitter.
    bug-a-aarch64-float-field-width-ignored }
  if width > 0 then
  begin
    if ip >= two52 * 2 then
      ndig := PxxIntDDigits(@ip, 0)      { exact, and it is what will be printed }
    else
    begin
      ndig := 1; ipc := ip;
      while ipc >= 10 do begin ipc := ipc / 10; ndig := ndig + 1; end;
    end;
    total := ndig;
    if neg then total := total + 1;
    if decimals > 0 then total := total + 1 + decimals;
    while total < width do
    begin
      write(' ');
      total := total + 1;
    end;
  end;
  if neg then write('-');
  if decimals <= 0 then      { fdigits = 0, so `rem >= pw` above IS the rounding }
  begin
    PXXWriteUIntD(@ip);
    Exit;
  end;
  PXXWriteUIntD(@ip);
  write('.');
  dv := pw / 10;
  i := 1;
  while i <= fdigits do
  begin
    d := Trunc(rem / dv);
    rem := rem - d * dv;
    ch := Chr(48 + d);
    write(ch);
    dv := dv / 10;
    i := i + 1;
  end;
  i := fdigits + 1;
  while i <= decimals do     { past what a double knows: zeros, not guesses }
  begin
    write('0');
    i := i + 1;
  end;
end;

{ ---- exact decimal expansion of a Double, string-free -------------------

  Every finite double IS a finite decimal, exactly: value = mant * 2^exp2 with
  mant a 53-bit integer, and 2^-k = 5^k * 10^-k, so the exact decimal form is
  the integer mant*5^k with the point pushed k places left (k = -exp2), or the
  plain integer mant*2^exp2 when exp2 >= 0. No approximation enters, so every
  digit produced is a real digit of the value.

  This is the same algorithm as `ExDecDigits`/`ExDecRound` in
  `lib/rtl/sysutils.pas` (and its `Py`-prefixed twin in
  `compiler/builtin/pylib.pas`), but it does NOT build a digit STRING: this
  layer is the allocator and has no IntToStr or AnsiString concat to lean on.
  Since the caller only ever wants 17 significant digits, and 17 digits max out
  at 99999999999999999 < 9.2e18, the answer fits an Int64 and the whole thing
  stays integer arithmetic. That also makes it usable from the write path
  without touching the heap.

  Replaces the repeated `x := x / 10` normalise loop that every float writer
  used to carry (four copies: the two native emitters, this one, and
  builtin.pas's Str). One rounding per iteration, ~100 of them for 1e100, put
  the error inside the 17 digits being printed — and for 1e200 it moved the
  EXPONENT, printing E+200 for a value just under it. FloatToExpStr's own
  comment already recorded that scaling the double first is a dead end and that
  "any real fix has to round the DIGITS from an integer representation".
  bug-a-writeln-float-exponent-form-not-correctly-rounded }
const
  PXX_SCI_LIMBS = 96;             { 9 digits each; the 767-digit worst case needs 86 }
  PXX_SCI_BASE  = 1000000000;     { 10^9 }
  PXX_SCI_P5_13 = 1220703125;     { 5^13  — largest 5^k with limb*5^k inside Int64 }
  PXX_SCI_P2_30 = 1073741824;     { 2^30 }
type
  TPxxSciBuf = array[0..PXX_SCI_LIMBS - 1] of Int64;

{ buf := buf * f, f small enough that limb*f + carry cannot leave Int64. }
procedure PxxSciMul(var buf: TPxxSciBuf; var n: Integer; f: Int64);
var i: Integer; t, carry: Int64;
begin
  { One division per limb, not two: a 64-bit div is ~30-90 cycles and this is
    the inner loop of the whole expansion (~10 passes over ~12 limbs for 1e100).
    q := t div BASE then t - q*BASE costs a multiply instead of a second div. }
  carry := 0;
  for i := 0 to n - 1 do
  begin
    t := buf[i] * f + carry;
    carry := t div PXX_SCI_BASE;
    buf[i] := t - carry * PXX_SCI_BASE;
  end;
  while (carry > 0) and (n < PXX_SCI_LIMBS) do
  begin
    t := carry div PXX_SCI_BASE;
    buf[n] := carry - t * PXX_SCI_BASE;
    carry := t;
    n := n + 1;
  end;
end;

{ Split a finite non-zero |value| into mant * 2^exp2, mant an integer. }
procedure PxxSciSplit(value: Double; var mant: Int64; var exp2: Integer);
var bits, frac: Int64; be: Integer;
begin
  bits := PInt64(@value)^;
  be := Integer((bits shr 52) and 2047);
  frac := bits and $000FFFFFFFFFFFFF;
  if be = 0 then
  begin
    mant := frac;                 { subnormal: no implicit leading 1 }
    exp2 := -1074;
  end
  else
  begin
    mant := frac or $0010000000000000;
    exp2 := be - 1075;
  end;
end;

{ The 17 leading significant digits of |value| as an integer, plus the decimal
  exponent of the FIRST digit (so value ~ d.dddd... * 10^decExp). Rounded
  half-to-EVEN on the exact remainder — the remainder here really is exact, so
  a tie is a genuine tie rather than an artifact of scaling. value must be
  finite and non-zero. }
procedure PxxSciDigits17(value: Double; var mant17: Int64; var decExp: Integer);
var
  buf: TPxxSciBuf;
  n, i, k, fracDigits, total, topLen, idx, dpos: Integer;
  mant, t, scale, rem, half: Int64;
  exp2: Integer;
  up, sawNonZero: Boolean;
begin
  PxxSciSplit(value, mant, exp2);
  for i := 0 to PXX_SCI_LIMBS - 1 do buf[i] := 0;
  buf[0] := mant mod PXX_SCI_BASE;
  buf[1] := mant div PXX_SCI_BASE;
  n := 2;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  fracDigits := 0;
  if exp2 >= 0 then
  begin
    k := exp2;
    while k >= 30 do begin PxxSciMul(buf, n, PXX_SCI_P2_30); k := k - 30; end;
    while k > 0 do begin PxxSciMul(buf, n, 2); k := k - 1; end;
  end
  else
  begin
    k := -exp2;
    fracDigits := k;
    while k >= 13 do begin PxxSciMul(buf, n, PXX_SCI_P5_13); k := k - 13; end;
    while k > 0 do begin PxxSciMul(buf, n, 5); k := k - 1; end;
  end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;

  { total decimal digits: the top limb unpadded, the rest nine each }
  topLen := 1; t := buf[n - 1];
  while t >= 10 do begin t := t div 10; topLen := topLen + 1; end;
  total := topLen + (n - 1) * 9;
  decExp := total - 1 - fracDigits;

  { Take the leading 17 digits. dpos counts digits already consumed from the
    most significant end; digit i of the whole number is read out of its limb. }
  mant17 := 0;
  dpos := 0;
  while dpos < 17 do
  begin
    if dpos < total then
    begin
      idx := total - 1 - dpos;          { 0-based index from the LOW end }
      scale := 1;
      for k := 1 to (idx mod 9) do scale := scale * 10;
      mant17 := mant17 * 10 + ((buf[idx div 9] div scale) mod 10);
    end
    else
      mant17 := mant17 * 10;            { value has fewer digits than 17 }
    dpos := dpos + 1;
  end;

  { Round on digit 18 and the exact tail beyond it. }
  if total > 17 then
  begin
    idx := total - 1 - 17;
    scale := 1;
    for k := 1 to (idx mod 9) do scale := scale * 10;
    rem := (buf[idx div 9] div scale) mod 10;
    up := False;
    if rem > 5 then up := True
    else if rem = 5 then
    begin
      sawNonZero := False;
      for i := 0 to total - 19 do
      begin
        idx := i;                       { every digit BELOW the round digit }
        scale := 1;
        for k := 1 to (idx mod 9) do scale := scale * 10;
        if ((buf[idx div 9] div scale) mod 10) <> 0 then
        begin sawNonZero := True; break; end;
      end;
      if sawNonZero then up := True
      else up := (mant17 mod 2) = 1;    { exact tie -> half to EVEN }
    end;
    if up then mant17 := mant17 + 1;
  end;

  { A carry out of the leading digit (99999... -> 100000...) drops one digit
    and moves the exponent. }
  half := 1;
  for k := 1 to 17 do half := half * 10;    { 10^17 }
  if mant17 >= half then
  begin
    mant17 := mant17 div 10;
    decExp := decExp + 1;
  end;
end;

function PxxIntDDigits(pv: Pointer; emit: NativeInt): NativeInt;
{ The EXACT decimal digits of a non-negative integral Double at or above 2^53:
  their count, and — when emit <> 0 — the digits themselves, most significant
  first. Same base-10^9 limb expansion as PxxSciDigits17, minus the rounding:
  nothing is dropped, so the answer is the whole number.

  Only the exp2 >= 0 half of the expansion is needed. A double is
  mant * 2^exp2 with mant 53 bits, so any value at or above 2^53 has exp2 >= 1
  — it is a plain integer times a power of two, and multiplying the limbs by
  two is all the conversion there is. Below 2^53 a caller must use the
  divide-down loop instead (this routine would be correct but pays a multiply
  per bit of a negative exp2 for a fraction that is all zeros).

  The count is what the field-width computation needs, and it cannot come from
  `while ipc >= 10 do ipc := ipc / 10` either: those divisions are inexact and
  can land the count one column off. }
var
  buf: TPxxSciBuf;
  n, i, k, topLen, idx, total, dpos, d: Integer;
  mant, t, scale: Int64;
  exp2: Integer;
  ch: Char;
begin
  PxxSciSplit(PDouble(pv)^, mant, exp2);
  for i := 0 to PXX_SCI_LIMBS - 1 do buf[i] := 0;
  buf[0] := mant mod PXX_SCI_BASE;
  buf[1] := mant div PXX_SCI_BASE;
  n := 2;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  k := exp2;
  while k >= 30 do begin PxxSciMul(buf, n, PXX_SCI_P2_30); k := k - 30; end;
  while k > 0 do begin PxxSciMul(buf, n, 2); k := k - 1; end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  topLen := 1; t := buf[n - 1];
  while t >= 10 do begin t := t div 10; topLen := topLen + 1; end;
  total := topLen + (n - 1) * 9;
  if emit <> 0 then
  begin
    dpos := 0;
    while dpos < total do
    begin
      idx := total - 1 - dpos;            { 0-based index from the LOW end }
      scale := 1;
      for k := 1 to (idx mod 9) do scale := scale * 10;
      d := Integer((buf[idx div 9] div scale) mod 10);
      ch := Chr(48 + d);
      write(ch);
      dpos := dpos + 1;
    end;
  end;
  PxxIntDDigits := total;
end;

procedure PXXWriteFloatSci(p: Pointer);
{ Pascal scientific notation <' '|'-'>d.<16 digits>E<'+'|'-'>ddd (17 significant
  digits, 3-digit exponent), matching FPC's Str(Double) field width and the
  x86-64 EmitWriteFloatSci. The mantissa is extracted MSD-first into a 17-digit
  integer so each step only truncates a value in [0,10) — preserves ~17 accurate
  digits, unlike one (x*1e16) multiply which overflows the 53-bit mantissa. One
  guard digit rounds half-up. Includes the leading-space positive sign. }
var x: Double; e, d, k: Integer; m, divisor: Int64; ch: Char;
begin
  x := PDouble(p)^;
  { NON-FINITE first — the normalise loops below never terminate on one:
    `Inf / 10` is still Inf, and a NaN compares false against both bounds so it
    escapes the loops only to format garbage. This is the portable twin of
    EmitWriteFloatSci (x86-64), which had the same hang and the same fix; every
    target that does NOT have a native emitter reaches this one, so i386 kept
    hanging after x86-64 was fixed.

    Checked before the sign write so NaN prints unsigned, as FPC does — a
    0.0/0.0 NaN carries a set sign bit and would otherwise render '-Nan'.
    Spelling matches sysutils' FloatToStr and the native emitter
    (bug-a-writeln-of-a-non-finite-double-hangs). }
  if x <> x then
  begin
    write(' Nan');
    Exit;
  end;
  if x > 1.7976931348623157e308 then
  begin
    write(' Inf');
    Exit;
  end;
  if x < -1.7976931348623157e308 then
  begin
    write('-Inf');
    Exit;
  end;
  if PByte(Int64(p) + 7)^ >= 128 then
  begin
    write('-');
    x := -x;
  end
  else
    write(' ');
  if x = 0 then
  begin
    write('0.0000000000000000E+000');
    Exit;
  end;
  { EXACT digits — see PxxSciDigits17. The normalise-by-repeated-division loop
    that used to live here was wrong from the 16th digit (one rounding per
    iteration, ~100 of them for 1e100) and for 1e200 produced the wrong
    EXPONENT. }
  PxxSciDigits17(x, m, e);
  for k := 16 downto 0 do
  begin
    divisor := 1;
    for d := 1 to k do divisor := divisor * 10;
    ch := Chr(48 + ((m div divisor) mod 10));
    write(ch);
    if k = 16 then write('.');
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
  else if (tag = 6) or ((tag >= 8192) and (tag <= 8199)) then
  { VT_STRING, or any tag in the promotable-int block: a promo too large for
    the inline tier rides in a variant as a managed AnsiString of its exact
    decimal, so it PRINTS through the same path. An inline-tier promo is stored
    as an ordinary VT_INT64 and never reaches here. }
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
