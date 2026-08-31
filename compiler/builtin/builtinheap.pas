{ SPDX-License-Identifier: Zlib }
unit builtinheap;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ BARE ESP (either ISA) has no mmap and no OS heap of its own here; back the
  allocator with a fixed static arena instead. One marker for both ESP ISAs.
  HOSTED riscv32 (qemu-user linux) DOES have mmap and the linux syscall ABI (its
  read/write already use syscalls 63/64), so it must NOT take the static-arena
  path — a 64 KiB arena OOMs on any real workload (e.g. sqlite) and PXXAlloc then
  stores through a NULL base. Only a BARE boot (PXX_ESP_BARE) is ESP for this
  purpose — under IDF, FreeRTOS supplies the heap, on xtensa as on riscv32. }
{ PROFILE, not ISA — the unit-side twin of util.inc's TargetIsEspClass, and it
  had the same defect: `{$ifdef CPU_XTENSA}{$define PXX_ESP}` unconditionally,
  so every {$ifndef PXX_ESP} body below was excluded on xtensa even under the
  IDF profile, where FreeRTOS supplies a heap and VFS supplies files. riscv32
  under IDF compiled all of them, which is the proof the bodies are fine on an
  ESP target. feature-a-complete-the-builtin-unit-on-the-esp-class-targets }
{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}

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
    { LONGINT, exactly as FPC declares it — not NativeInt, which is what this
      was. The union slot is pointer-sized either way (FixupTVarRecLayout
      right-sizes the record), so the width here buys no storage; what it
      decides is OVERLOAD BINDING at the reader. fpjson's VarRecToJSON does
      `vtInteger: Result := CreateJSON(VInteger)` against a set of four
      overloads — Integer, Int64, QWord, NativeInt — so a NativeInt-typed field
      bound the wrong one and `CreateJSONArray([1])[0]` came back a
      TJSONInt64Number where FPC gives a TJSONIntegerNumber. Silent, and in a
      real library's public factory.
      The tag side of the same agreement is in ir.inc's AN_VARREC_ARRAY: a
      pointer-wide native int now goes in as vtInt64, which is what FPC does on
      a 64-bit target (there NativeInt IS Int64), so nothing that used to fit
      this slot loses its top half.
      bug-p-array-of-const-integer-arm-picks-the-int64-overload }
    VInteger: Longint;
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
{ The cached ASCII answer: 1 yes, 0 no, -1 not looked yet. See PXX_FLAG_ASCII_KNOWN. }
function PXXStrAsciiCached(p: Pointer): Int64;
procedure PXXStrSetAscii(p: Pointer; isAscii: Boolean);
procedure PXXStrForgetAscii(p: Pointer);
function PXXStrConcat(lenA: NativeInt; srcA: Pointer; srcB: Pointer; lenB: NativeInt): Pointer;
{ ---- UTF-16 (WideString/UnicodeString) ----
  Storage is 2-byte code units and the header length is their BYTE count, which
  is what lets concat/compare/copy stay the byte-level routines above. The
  terminator is a 2-byte NUL, not a 1-byte one, so a PWideChar handed to a C
  API terminates where that API expects.

  These four are the whole runtime half: allocation with the wider terminator,
  and the two transcoders. Everything else a wide string needs -- refcounting,
  freeing, in-place append, block copy -- is byte-shaped and already exists.
  feature-unicodestring-model }
{ APPEND lenB bytes onto the managed string held in strSlot, in place when it
  can be. This is the destination-aware form PXXStrConcat cannot be: concat
  returns a fresh handle and never learns where the result is going, so it must
  copy the whole accumulation every time and `s += c` in a loop is O(n^2).
  Given the SLOT, the owner is known, so the bytes can be appended to the
  existing block when nothing else shares it and the block has room -- which is
  what makes the loop amortised O(1) per append, as CPython's is.
  Deciding this from the left operand's refcount ALONE would be a
  silent-wrong-value bug (`t := s + 'x'` with a refcount-1 s would grow s); the
  slot is what removes the guess. }
procedure PXXStrAppend(strSlot: Pointer; srcB: Pointer; lenB: NativeInt);
{ Word-at-a-time forward block copy; answers $80 if any byte copied had its high
  bit set (the one bit PXXStrMeta reads), else 0. Word loop only when both ends
  are machine-word aligned — ARM32 faults otherwise. }
function PXXBlockCopy(d: Int64; s: Int64; n: Int64): Int64;
procedure PXXStrIncRef(p: Pointer);
procedure PXXStrDecRef(p: Pointer);
{ NilPy object reclamation (devdocs/dev/nilpy-object-reclamation.md): class
  instances created by NilPy code paths are refcounted like AnsiString handles.
  The instance pointer is base+PXX_HDR_SIZE of its own heap block, rc at [inst-16] — the
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
  { Pascal WideString/UnicodeString -- fixed-width UTF-16. Length in the header
    stays a BYTE count exactly as for BYTESTR, so every existing memcpy,
    compare, retain/release and free path works on it unchanged; only the
    PUBLIC Length() halves it, and that lowers statically off the string's
    ELEMENT type (tyChar vs tyWideChar) rather than by consulting this tag.
    See feature-unicodestring-model. }
  PXX_KIND_WIDESTR = 5;
  PXX_KIND_MAX     = 5;
  PXX_KIND_MASK    = $FF;

  { Flags, bits 8-15 }
  { Built by the COMPILER, not by this allocator: the block lives in the data
    section in front of a pooled string literal (InternStr, emit.inc), its
    refcount is born saturated so no PXXStrDecRef can reach the free, and it
    carries no PXX_FLAG_APPENDABLE and no allocator size word worth trusting.
    Nothing here BRANCHES on it — every in-place path already refuses a shared
    block on its own terms (rc <= 1, plus APPENDABLE for the append). The flag
    is what makes such a block identifiable in a dump or a debugger, and the
    reason a `p` that never came from PXXAlloc can be sitting in this heap's
    protocol at all. bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython }
  PXX_FLAG_STATIC   = $0100;
  PXX_FLAG_INTERNED = $0200;   { reserved, unused }
  PXX_FLAG_ASCII    = $0400;   { verified: no byte >= $80 }
  { The ASCII bit ANSWERED. Without this, 0 means both "scanned, has high bytes"
    and "nobody looked", so a consumer had to rescan every time and NilPy's
    s[i] was O(n) per index — a plain indexing loop O(n^2), measured 2476x
    CPython at n=160k (bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-
    cpython). With it, PXX_FLAG_ASCII is authoritative and the scan happens once
    per string. Anything that MUTATES bytes must clear both bits; PXXStrUnique
    is the one place that can, because byte writes go through its COW. }
  PXX_FLAG_ASCII_KNOWN = $1000;
  PXX_FLAG_EXTENDED = $0800;   { a side-table entry exists — the escape hatch }
  { This block was allocated by PXXStrAppend with DELIBERATE spare capacity, so
    the allocator's size word below it is a capacity this code put there. Only
    then may an append write past the current length in place.

    The flag is what makes the append sound, and it is not belt-and-braces: the
    size word exists under every PXXAlloc block, but "the word below the base"
    is only meaningful for blocks this runtime allocated through that path. A
    handle that reached us some other way would answer with whatever bytes
    precede it, and a garbage-large answer passes `cap >= need` and writes off
    the end of the block. Trusting rc<=1 alone is not enough for the same
    reason. See bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython. }
  PXX_FLAG_APPENDABLE = $2000;

  { The refcount a compiler-built static block is born with, and the floor that
    identifies one at runtime. MUST equal MSTR_STATIC_RC in compiler/defs.inc —
    the same deliberate duplication as the header constants above (that file is
    included into the compiler; this one is COMPILED by it), pinned by
    test_static_string_literals asserting a runtime VALUE rather than the
    constants themselves, so a drift shows up as a wrong answer and not as a
    silent agreement.

    Read as a FLOOR, not as an equality, and the difference is what makes the
    guard safe to roll out one site at a time. x86-64 hand-emits its retain and
    release sequences and does not go through the two routines below, so for a
    while some operations on a static block are guarded and some are not. That
    cannot run away, because the guard un-arms itself: an unguarded decrement
    takes rc to FLOOR-1, at which point every guarded increment stops being
    skipped and behaves exactly as it does today. rc therefore oscillates just
    under the floor instead of drifting toward zero — bounded by the number of
    simultaneously live references, never by elapsed time.

    That distinction is worth stating because this ticket's own motivation says
    2^30 IS reachable: 2.5M literal stores a second for 400 seconds. True, and
    it is about *removing the increment unconditionally*, which nets -1 per
    store/overwrite cycle forever. A floor test is not that change. }
  PXX_STATIC_RC_FLOOR = $40000000;

  { KindData0, bits 16-23: text encoding. A small enum, NOT a codepage —
    CP_UTF8 (65001) would not fit, and this is the field pxx actually wants. }
  PXX_ENC_BYTES = 0;
  PXX_ENC_UTF8  = 1;
  PXX_ENC_UCS2  = 2;
  PXX_ENC_UCS4  = 3;
  PXX_ENC_SHIFT = 16;

  { MIRRORS compiler/defs.inc's VT_OBJ_FIRST / VT_OBJ_LAST — which variant tags
    carry a refcounted object. A builtin unit cannot see defs.inc, so the two
    numbers are written twice and MUST be changed together; the range exists so
    that is TWO numbers to keep in step instead of a list of four equality
    tests, which is what silently drifted (see the note in defs.inc, and
    PXXVarClear below for what the drift cost). }
  VT_OBJ_FIRST = 7;
  VT_OBJ_LAST  = 10;
  VT_STRING_TAG = 6;
  VT_PROMO_FIRST = 8192;   { promo-block tags ride as a managed AnsiString of the decimal }
  VT_PROMO_LAST  = 8199;

  PXX_OBJ_MAGIC = $505942F1;   { low bits 001 — never an allocator size word }
  { RAW variant of the tag: a refcounted heap block that is NOT a class
    instance (no VMT at +0) — today only pybound_new's {code,recv} pairs.
    Release runs the finalize hook with raw=1 so the hook won't VMT-dispatch. }
  PXX_OBJ_MAGIC_RAW = $505942F9;
  { second RAW flavor: a pyeval closure object — finalized through the same
    hook with rawKind=2 (pylib forwards to pyeval's registry free) }
  PXX_OBJ_MAGIC_RAW2 = $505942E1;
  { The runtime data layout THIS RTL implements. Twin of defs.inc's
    PXX_RTL_LAYOUT_VERSION — the compiler compares the two when it links this
    unit and refuses a mismatch. Bump BOTH together when a layout changes.
    bug-a-self-host-seed-has-no-versioned-rtl }
  PXX_RTL_LAYOUT_VERSION = 1;
type
  { Finalizer for a dying refcounted object, installed by pylib (which knows
    the container types). p = the object, raw = 1 for a RAW (VMT-less) block.
    Runs after rc hits 0 and before the block is freed; it releases the
    object's children recursively. nil = no finalizer (plain free). }
  TPXXObjFinalize = procedure(objp: Pointer; rawKind: NativeInt);
var
  { System.ExitCode. FPC declares it in System scope, so it is spelled without
    a unit qualifier anywhere in a program; builtinheap is linked into every
    binary and its interface names resolve bare, which makes this the cheapest
    honest home for it. Semantics, all four measured against FPC 3.2.2
    (feature-pascal-exitcode-finalization-halt):

      Halt(n)          ExitCode := n, then finalizations, then exit(ExitCode)
      Halt             ExitCode := 0 — it is Halt(0), NOT "exit with the
                       current ExitCode". The ticket asserted the latter;
                       `ExitCode := 9; Halt;` proves otherwise.
      falling off main finalizations, then exit(ExitCode)
      a finalization writing ExitCode CHANGES the process exit status — that
                       is the whole erroru.pp idiom: check the recorded code,
                       then zero it so an expected halt(100) exits 0. }
  ExitCode: Longint;

  { Set by pylib's INITIALIZATION section, so it is live for the whole run of
    any NilPy program. Do not go back to installing it from a constructor: it
    used to be set only by pylib/pyeval's CONTAINER constructors (pylist_new,
    pydict_new, pybound_new, bytes, the iterators), and the name is what hid
    that — "object finalize" reads as covering every object, while the
    installation covered lists, dicts, bytes and iterators. A program that
    built user-class instances and never a container therefore ran with this
    nil, and PXXObjRelease freed each instance BLOCK at rc=0 without releasing
    one managed field: 410 MB over 200k constructions, flat at 980 kB the
    moment an unrelated `dummy = [1]` was added. The per-constructor installs
    are kept as a belt on any profile whose unit initialization does not run.
    feature-nilpy-object-reclamation }
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
  gated in pasparser_*.inc). }
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
  (pasparser_*.inc), which is what reserves IMT slots 0..2 for QueryInterface /
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
function PXXStrCmp3(lenA: NativeInt; srcA: Pointer; lenB: NativeInt; srcB: Pointer): Int64;
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
{ Not on BARE ESP: file I/O, managed-element dynarray/record retain/release,
  variant, float formatting. Bare metal, hence PXX_ESP, is now the only profile
  that excludes them — under IDF both ESP ISAs get FreeRTOS's heap and VFS's
  files and compile every body below, which riscv32 has done all along and
  xtensa was wrongly locked out of until 2026-08-27.

  So this is a PROFILE statement, not a platform one: none of these bodies is
  unimplementable on an ESP chip. `file I/O` here means there is no filesystem
  under a bare boot to open. Do not read the list as "ESP cannot do this". }
{$ifndef PXX_ESP}
function PXXStrLoadFile(path: Pointer): Pointer;
procedure PXXRecordRetain(recAddr: Pointer; desc: Pointer);
procedure PXXRecordRelease(recAddr: Pointer; desc: Pointer);
{ The COM-interface half of the same walk, split out because of LOCK DISCIPLINE,
  not because interfaces are a different kind of member: releasing one runs the
  object's destructor chain and a self-locking FreeMem, so it must happen with
  NO heap lock held, while the string/dynarray/record half is emitted under it.
  Codegen therefore calls these two BEFORE EmitAcquireHeapLock and
  PXXRecordRetain/Release inside — the shape PXXClassFinalize already uses for a
  class instance. bug-a-a-record-copy-does-not-retain-an-interface-field }
procedure PXXRecordRetainIntf(recAddr: Pointer; desc: Pointer);
procedure PXXRecordReleaseIntf(recAddr: Pointer; desc: Pointer);
{ Initialize(x) / Finalize(x) over the SAME layout descriptor the scope-exit
  release already walks. The pair exists because scope-exit cleanup only covers
  variables the compiler declared: a record conjured from GetMem is just bytes
  to it, so its AnsiString field holds garbage until something puts it in a
  valid empty state. }
procedure PXXRecordInitialize(recAddr: Pointer; desc: Pointer);
procedure PXXRecordFinalize(recAddr: Pointer; desc: Pointer);
procedure PXXDynArrayRelease(arrData: Pointer; desc: Pointer);
function PXXDynArrayUnique(arrSlot: Pointer; desc: Pointer): Pointer;
function PXXVarBinOp(dest: Pointer; left: Pointer; right: Pointer; opTk: NativeInt; isCompare: NativeInt): Int64;
function PXXVarNot(dest: Pointer; src: Pointer): Int64;
function PXXVarStrAppend(dest: Pointer; right: Pointer): Int64;
procedure PXXVarClear(v: Pointer);
procedure PXXVarReleasePayload(v: Pointer);
procedure PXXVarRetain(v: Pointer);
procedure PXXWriteVariant(v: Pointer);
{ Exact 17-significant-digit decimal expansion of a finite non-zero |Double|.
  Exposed so builtin.pas's `Str(F, S)` shares the ONE correct implementation
  rather than carrying its own normalise loop (which disagreed with writeln's
  by a digit). See PxxSciDigits17's own header. }
procedure PxxSciDigits17(value: Double; var mant17: Int64; var decExp: Integer);
{$endif}
{ The program's normal exit path: run the unit finalizations and terminate with
  whatever ExitCode holds AFTERWARDS. Written as Pascal, and called from the
  main body's epilogue instead of a raw exit-syscall emission, so that
  "terminate with the value of a global" needs NO new per-arch emitter — the
  AN_HALT lowering already terminates with a computed value on all six
  backends, and this routine is just a Halt. The finalization runner is
  run-once guarded, so a Halt reached from inside a finalization does not
  re-enter it; it simply exits with the newer code, which is what FPC does. }
procedure PXXExitProcess;
{ TObject.Destroy's DEFAULT body: nothing to do. It exists so slot
  ROOT_VMT_DESTROY is never nil, which is what lets `Free` dispatch Destroy
  VIRTUALLY for every class instead of deciding at parse time from the
  receiver's STATIC type — `b.Free` through a `TBase` reference skipped the
  descendant's Destroy entirely when TBase declared none
  (bug-p-free-through-base-reference-skips-destroy).

  It lives in builtinHEAP rather than in `builtin` because tkClass already pulls
  builtinheap into every class-bearing program, so this costs nothing; putting it
  in `builtin` would have dragged that unit's ~43 KB into every program that
  calls Free. The receiver is spelled `Inst`, not `Self` — it is a plain
  procedure, and the VMT slot is what makes it a method (same convention as
  __pxxTObjectEquals and friends). }
procedure __pxxTObjectDestroy(Inst: Pointer);
implementation


type
  PWord = ^NativeInt;  { pointer-sized machine-word access at an arbitrary
                         address: 8 bytes on 64-bit targets, 4 on 32-bit. Must
                         not be ^Int64 — on i386 that writes 8 bytes into a
                         4-byte handle/pointer slot and corrupts its neighbour. }
  PByte = ^Byte;    { byte access at an arbitrary address }
  PInt64 = ^Int64;  { qword access (dyn-array count header at [data-8]) }
  PInt32 = ^Integer; { 32-bit integer access }
  PU16   = ^Word;   { 2-byte access, for UTF-16 code units. NOT `PWord` -- that
                      name is taken above and means ^NativeInt (8 bytes on
                      64-bit), which is the single easiest mistake to make in
                      this file: `PWord(d)^ := unit` compiles, writes eight
                      bytes, and silently clobbers the next three code units. }
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
  { KNOWN either way: this ran over every byte, so the answer is authoritative
    whichever way it came out. }
  if (orAll and $80) = 0 then
    PXXStrMeta := PXX_KIND_LEGACY or PXX_FLAG_ASCII_KNOWN or PXX_FLAG_ASCII
  else
    PXXStrMeta := PXX_KIND_LEGACY or PXX_FLAG_ASCII_KNOWN;
end;

{ The cached ASCII answer for a managed string handle: 1 = ASCII, 0 = has a byte
  >= $80, -1 = nobody has looked (the caller must scan, and should call
  PXXStrSetAscii with what it finds so the next caller does not).
  Every AnsiString handle in this runtime is a PXXAlloc'd block whose meta word
  PXXHdrInit zeroes, so the read is always of defined memory and an unstamped
  block answers -1 rather than garbage. }
function PXXStrAsciiCached(p: Pointer): Int64;
var meta: Int64;
begin
  if p = nil then begin PXXStrAsciiCached := 1; Exit; end;   { '' is ASCII, CPython's rule }
  meta := PXXHdrMeta(p);
  if (meta and PXX_FLAG_ASCII_KNOWN) = 0 then
  begin
    PXXStrAsciiCached := -1;
    Exit;
  end;
  if (meta and PXX_FLAG_ASCII) <> 0 then PXXStrAsciiCached := 1
  else PXXStrAsciiCached := 0;
end;

{ Record what a scan found, so it happens once per string rather than once per
  index. Safe to call on any managed handle; a nil handle has no header. }
procedure PXXStrSetAscii(p: Pointer; isAscii: Boolean);
var base, meta: Int64;
begin
  if p = nil then Exit;
  base := Int64(p) - PXX_HDR_SIZE;
  meta := PWord(base + PXX_HDR_META)^;
  meta := meta or PXX_FLAG_ASCII_KNOWN;
  if isAscii then meta := meta or PXX_FLAG_ASCII
  else meta := meta and (not PXX_FLAG_ASCII);
  PWord(base + PXX_HDR_META)^ := meta;
end;

{ Forget the cached ASCII answer — the bytes are about to change. }
procedure PXXStrForgetAscii(p: Pointer);
var base, meta: Int64;
begin
  if p = nil then Exit;
  base := Int64(p) - PXX_HDR_SIZE;
  meta := PWord(base + PXX_HDR_META)^;
  PWord(base + PXX_HDR_META)^ :=
    meta and (not (PXX_FLAG_ASCII_KNOWN or PXX_FLAG_ASCII));
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
{$if defined(PXX_ESP)}
  HEAP_ARENA = 65536;       { single 64 KiB static arena (fits ESP SRAM) }
{$elseif defined(CPU_WASM32)}
  { MUST equal the WasmArena byte size below. PXXAlloc rounds any request up to
    HEAP_ARENA and then sets HeapEnd := HeapPtr + arena, so a HEAP_ARENA larger
    than the real buffer would hand out a HeapEnd past its end and bump straight
    through it — the 256 MiB default would have done exactly that on a 1 MiB
    arena, reintroducing the corruption this arm exists to remove.
    1 MiB, not "a few": BSS feeds the module's declared minimum memory
    (WasmFinishMemory), builtinheap links into every program, and the wasm32
    lane measured hello-world at (memory 2) = 128 KiB today. 16 pages is
    headroom without taxing every module for space nobody is using. }
  HEAP_ARENA = 1048576;     { 1 MiB static arena; see WasmArena }
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
  CEN_BIG_MIN    = 65536;                   { -dPXX_ALLOC_BIG traces at or above this }
  { Span at which `rep stosb` starts beating the word loop in PXXMemZero. Swept
    on x86-64 (see the note there); a wrong value costs throughput, never
    correctness -- both arms zero the same bytes. }
  MEMZERO_REP_MIN = 64;
  { Span below which PXXAlloc's bin path zeroes INLINE rather than calling
    PXXMemZero. Not a rival implementation -- purely the call boundary; above it
    PXXMemZero decides everything. Swept on x86-64. }
  ALLOC_INLINE_ZERO_MAX = 64;
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
{$ifdef PXX_ALLOC_CENSUS}
  { ---- allocation census (-dPXX_ALLOC_CENSUS) ------------------------------
    How much does this program allocate, and of what size? This runtime could
    answer "was it read after free" (-dPXX_HEAP_DEBUG), "who retained it"
    (-dPXX_OBJTRACE) and "what did the compiler infer" (PXXDBG), and could not
    answer that one — so three sessions of
    bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython reached for
    callgrind instead, which is not installed on the box the work happens on
    (and perf is blocked there too: perf_event_paranoid = 4). A share quoted
    from an instrument nobody present can re-run is how that ticket ended up
    ranking its own follow-ups on numbers it could not reproduce.

    BSS-zeroed, so no initialiser and no startup hook. Counters only — there is
    deliberately NO call-site attribution: that needs either a caller tag
    threaded through every entry point or a stack walk, and both change what
    they measure. Sizes plus rates answer the question this was built for. }
  CensusAllocs : Int64;   { PXXAlloc calls }
  CensusFrees  : Int64;   { PXXFree calls }
  CensusBytes  : Int64;   { payload bytes handed out, after 8-rounding }
  CensusReuse  : Int64;   { served from a size bin — the O(1) path }
  CensusList   : Int64;   { served from the large first-fit list }
  CensusBump   : Int64;   { served by bumping the arena (never yet freed) }
  CensusArenas : Int64;   { HeapMmap calls }
  CensusNext   : Int64;   { allocs at which the next report fires; 0 = first }
  CensusBins   : array[0..HEAP_BIN_COUNT-1] of Int64;
{$endif}
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
  { Provenance for a WRITE AFTER FREE, all of it already known at detection and
    formerly discarded. The OFFSET is the useful one: it is relative to the
    payload address, which for a managed block IS the block base, so it reads
    straight off the header map -- 0 is PXX_HDR_META (and the free-list next
    link, which share that word), 8 is PXX_HDR_RC, 16 is PXX_HDR_LEN, and
    >= PXX_HDR_SIZE is the string/array payload. "Someone wrote here" and
    "someone wrote the LENGTH of a freed string" are different bugs. }
  HeapDbgSize   : Int64;                   { the victim's block size }
  HeapDbgOff    : Int64;                   { first byte that was not poison }
  HeapDbgVal    : Int64;                   { the machine word written there }
  { A window of the victim's bytes from the first broken one. The single most
    identifying field measured on this bug so far was a corrupt bin head that
    decoded to `Char` -- the WRITER'S DATA, naming the compiler's own token
    stream in one step. A freer PC says who let go; the payload says who
    scribbled, and the scribbler is the one being hunted. Static storage: this
    path may allocate nothing. }
  HeapDbgBytes  : array[0..15] of Byte;
  HeapDbgNBytes : Integer;
  HeapDbgStack  : array[0..31] of Int64;
  HeapDbgNStack : Integer;
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
{$ifdef CPU_WASM32}
  { 1 MiB static arena, Int64 cells so the base is 8-aligned. Same shape as the
    ESP arena above, for a different reason: wasm has no mmap to fail, and
    linear memory has NO PAGE PROTECTION -- address 0 is legal and reads as
    zero -- so an unassigned Result here does not fault, it hands out 8, 32,
    56... and silently overwrites the globals at WASM_BSS_BASE once ~1 KB has
    been allocated. The arena must be real storage, not a syscall result.
    Declaring it in BSS is also what makes the memory exist: the backend derives
    the module's declared page count from BSSSize (WasmFinishMemory), and BSS is
    never emitted into the file, so this costs declared address space at
    instantiation and not one byte of .wasm.
    bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero }
  WasmArena     : array[0..131071] of Int64;   { 131072 * 8 = HEAP_ARENA }
  WasmArenaUsed : Integer;
{$endif}

{$ifdef CPU_WASM32}
{ `external 'wasm'` is not a host module -- the wasm32 backend reads that
  reserved module name as THIS MACHINE and emits the instruction inline instead
  of declaring an import (ir_codegen_wasm32.inc, WasmInstrExtern). So this
  declaration costs no import, and a host that supplies nothing still runs it.

  memory.grow takes a PAGE count and returns the previous SIZE IN PAGES, or -1
  if it could not grow -- not the new size, and not a byte address. Getting
  that backwards yields a heap based inside the memory that was already in use,
  which is the failure this comment exists to prevent. }
function WasmMemoryGrow(pages: Integer): Integer;
  external 'wasm' name 'memory.grow';

{ The wasm arena's base, as one named thing -- the single expression HeapMmap's
  arm goes through. Defined ABOVE its caller, not merely somewhere in the file:
  FPC resolves in source order and the bootstrap seed build is the only thing
  that checks.

  It now grows linear memory rather than handing out the fixed BSS arena. The
  arena stays as the FIRST block, so a program that allocates less than a
  megabyte still never calls memory.grow -- and, more to the point, a host or a
  toolchain that refuses to grow keeps exactly the behaviour it had. Past that,
  each call takes fresh pages.

  Pages are 64 KiB and memory.grow returns the previous size in pages, so the
  base of what it just added is prev * 65536. New pages are ZERO by
  specification, which is what lets PXXAlloc's bump path keep its zero-init
  contract with no memset -- the same reasoning the BSS arena relied on, for
  the same reason.

  -1 on failure is passed straight through, because it is out of bounds on the
  first touch. Returning 0 here would be the bug the note below describes:
  address 0 is legal in linear memory, reads as zero, and has no page
  protection, so an out-of-memory heap would silently overwrite the globals and
  only trap thousands of allocations later. }
function WasmArenaBase(len: Int64): Int64;
var pages, prev: Integer;
begin
  if WasmArenaUsed = 0 then
  begin
    WasmArenaUsed := 1;
    if len <= 1048576 then
    begin
      Result := Int64(@WasmArena[0]);
      Exit;
    end;
  end;
  pages := Integer((len + 65535) div 65536);
  prev := WasmMemoryGrow(pages);
  if prev < 0 then Result := -1
  else Result := Int64(prev) * 65536;
end;
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
    32-bit targets use mmap2 (offset in pages; 0 either way).

    ONE exhaustive chain with a terminal arm, not a run of independent
    {$ifdef}/{$endif} blocks: as separate blocks a target matching none of them
    fell through to whatever the pre-chain default was -- here nothing at all,
    so Result was NEVER ASSIGNED and the function returned the return slot's
    leftover contents, which on wasm32 read as 0. Same defect and same fix as
    the five PXXSys* chains below (1ea3bdb85); this one is the instance with the
    largest blast radius, because its wrong answer is the base of the heap.

    PXX_ESP is tested FIRST: bare riscv32 defines both PXX_ESP and CPU_RISCV32,
    and the static arena is the arm it wants. }
{$if defined(PXX_ESP)}
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
{$elseif defined(CPU_WASM32)}
  { wasm32: BSS arena, same shape as PXX_ESP above, with two deliberate
    differences -- both of which are the whole reason this arm exists.

    NO ZEROING. wasm linear memory is zero at instantiation, so PXXAlloc's
    zero-init contract is satisfied for free. The ESP arm cannot assume that
    (it does not know whether startup zeroed .bss); we can. This is the one
    line that differs from the ESP shape and would otherwise read as an
    omission, so: it is deliberate.

    EXHAUSTION RETURNS -1, NOT 0. The ESP arm returns 0 because on that target
    0 faults on the next access and so reports out-of-memory for free. On wasm
    that idiom is precisely the bug -- 0 is a legal address, reads as zero, and
    has no page protection, so returning it hands out a heap that overwrites
    the globals and only traps thousands of allocations later, once the bump
    pointer leaves the declared memory. -1 is out of bounds on the first touch,
    which is the loud failure this target has no other way to produce.

    IT GROWS. WasmArenaBase hands out the fixed BSS arena for the first request
    that fits in it and calls memory.grow for everything after, so this arm is
    no longer a one-megabyte ceiling. That was the half this note reserved for
    the wasm32 lane: the module declaration never blocked growth (the backend
    already writes the no-maximum limits form), only the lack of a way to reach
    memory.grow from Pascal did, and `external 'wasm' name 'memory.grow'` is
    that way. Measured: compiler.pas under WASI trapped in PXXAlloc, three
    frames under EnsureTokCapacity, before this. }
  Result := WasmArenaBase(len);
{$elseif defined(CPUX86_64)}
  Result := __pxxrawsyscall(9, 0, len, 3, 34, -1, 0);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0);
{$elseif defined(CPU_RISCV32)}
  { hosted linux (qemu-user): generic syscall ABI mmap = 222 (byte offset, 0 here).
    prot=PROT_READ|PROT_WRITE=3, flags=MAP_PRIVATE|MAP_ANONYMOUS=0x22=34. }
  Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0);
{$elseif defined(CPU_XTENSA)}
  { hosted linux (qemu-user). TWO numbers differ from every arm above and BOTH
    were measured under qemu-xtensa 10.2.1, not read off a table:

      mmap2 = 80.  Xtensa has its OWN syscall numbering, the same one that puts
      read at 12 and write at 13 rather than the generic 63/64. Generic 222 --
      the number the riscv32 arm three lines up uses -- is `Unknown syscall 222`
      here; qemu names 80 as mmap2.

      MAP_ANONYMOUS = $800, so flags = MAP_PRIVATE|MAP_ANONYMOUS = $802 = 2050,
      NOT the 34 every other arm passes. Xtensa is one of the architectures with
      non-standard MAP_* values. This is the half that fails QUIETLY-ish: with
      34 the kernel sees MAP_PRIVATE|0x20 with no ANONYMOUS bit, tries to map
      fd -1, and returns EBADF -- a negative errno that PXXAlloc deliberately
      does not check, so it becomes the heap base and faults later.

    Until this arm existed xtensa fell through to the terminal `Result := -1`
    below, which is exactly what it looks like: SIGBUS at $FFFFFFFF on the first
    allocation. No hosted xtensa program that allocated anything had ever run.
    feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle }
  Result := __pxxrawsyscall(80, 0, len, 3, 2050, -1, 0);
{$else}
  { No arm for this target. -1, not 0: every caller reaches this through
    PXXAlloc, which does NOT check the result (deliberately -- on a hosted
    target a failed mmap returns a negative errno and the next access faults),
    so the returned value IS the base of the heap. 0 is the one value that
    fails silently on a target with no page protection, which is how wasm32
    shipped a heap at address zero.

    NOT {$error}, and this was measured rather than assumed: HeapMmap is
    compiled unconditionally -- it is NOT inside {$ifndef PXX_ESP_IDF} -- while
    the ESP-IDF profile redefines PXXAlloc to use calloc/free and never calls
    it. A compile-time refusal here would therefore break every xtensa and
    riscv32 IDF build over a function they do not use, and Track S is a live
    campaign. Terminal arms are chosen by reachability: {$error} where a
    missing arm cannot be reached at run time, a defined failure value where
    the routine is compiled into everything and called by almost nothing. }
  Result := -1;
{$endif}
end;{$ifdef PXX_ESP_IDF}
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
  { `(size + 7) and not 7`, not `((size + 7) div 8) * 8`: `div` by a literal is
    strength-reduced only at -O3, so at the -O2 DEFAULT every one of these
    lowered to a 64-bit `idiv` preceded by a zero-check on the constant 8. A
    sampling profile of the real -O2 compiler compiling a zero-byte .npy put
    11.4% of all in-.text samples on the three idivs in this file
    (perf-a-every-npy-compile-still-rebuilds-the-whole-nilpy-runtime). Every
    site is guarded non-negative just above, so mask and shift are exact --
    checked against `div` over 40,001 consecutive values and near 2^63, under
    both pxx and FPC. }
  if size <= 0 then size := 8;
  size := (size + 7) and (not NativeInt(7));
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
  size := (size + 7) and (not NativeInt(7));
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
{$ifdef PXX_ALLOC_CENSUS}
{ Defined after PXXSysWrite, which is what it writes through. Forward here
  because the trigger is inside PXXAlloc and the printer cannot be. }
procedure PXXCensusReport; forward;
{$ifdef PXX_ALLOC_BIG}
procedure PXXCensusBig(size: NativeInt); forward;
{$endif}
{$endif}
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
  size := (size + 7) and (not NativeInt(7));   { round up to 8 -- see the note at PXXAlloc }
{$ifdef PXX_ALLOC_CENSUS}
  CensusAllocs := CensusAllocs + 1;
  CensusBytes := CensusBytes + size;
  if size <= HEAP_BIN_MAX then
    CensusBins[Integer(size shr 3) - 1] := CensusBins[Integer(size shr 3) - 1] + 1;
{$ifdef PXX_ALLOC_BIG}
  { The census's bins stop at HEAP_BIN_MAX, so the allocations that actually
    consume the arenas are the ones it cannot see: on a 32-bit host building
    compiler.pas, 5931 of 19780 allocations are above the top bin and carry
    essentially all of the 4.4 GB. This prints those individually, which turns
    a total into a SEQUENCE -- a doubling series, a repeated constant and a
    slow ramp are three different bugs and the total cannot tell them apart. }
  if size >= CEN_BIG_MIN then PXXCensusBig(size);
{$endif}
{$endif}

  { Free-list nodes are payload addresses; the size header is at [cur-8] and the
    next link is parked in the payload at [cur]. A reused block holds stale bytes,
    so zero the span before handing it back — callers (managed refcount/length
    headers, zeroed dynarray/instance slots) assume fresh memory is zero, exactly
    like a bump block off a fresh mmap page. }

  { O(1) reuse for the common sizes: bin[class] holds blocks of EXACTLY this size,
    so the head is always an exact fit and there is nothing to walk. }
  if size <= HEAP_BIN_MAX then
  begin
    bin := Integer(size shr 3) - 1;
    cur := FreeBins[bin];
    if cur <> 0 then
    begin
      FreeBins[bin] := PWord(cur)^;        { pop }
{$ifdef PXX_ALLOC_CENSUS}
      CensusReuse := CensusReuse + 1;
{$endif}
      { Two arms, and the split is a CALL boundary, not a second zeroing
        algorithm: PXXMemZero owns the policy (it picks word loop vs `rep
        stosb` at MEMZERO_REP_MIN), and this arm exists only because a call to
        it costs more than the whole job for a span of one or two words. The
        loop that used to stand here unconditionally was the real defect --
        it never reached `rep stosb` at ANY size, so the reuse path paid a
        per-byte price that grew without bound. Measured, 3M allocs:
        call-always is 0.91x at 8 bytes and 0.92x at 32 (a real regression,
        old faster in 9 of 9 interleaved rounds) but 1.75x at 256 and 4.53x
        at 2048. }
      if size <= ALLOC_INLINE_ZERO_MAX then
      begin
        i := 0;
        while i < size do
        begin
          PWord(cur + i)^ := 0;
          i := i + SizeOf(NativeInt);        { PWord writes one machine word: 8 on
                                               64-bit, 4 on 32-bit — must match the
                                               step or half the span is skipped }
        end;
      end
      else PXXMemZero(Pointer(cur), size);
      Result := Pointer(cur);
{$ifdef PXX_TS_SOFTLOCK}
      PXXHeapSpin := 0;
{$endif}
{$ifdef PXX_ALLOC_CENSUS}
      if CensusAllocs >= CensusNext then PXXCensusReport;
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
{$ifdef PXX_ALLOC_CENSUS}
        CensusList := CensusList + 1;
{$endif}
        { PXXMemZero, not a hand-rolled word loop. The loop that used to be here
          (and in the bin path above) is the SECOND spelling of a primitive this
          unit already exports: PXXMemZero is `rep stosb` on x86-64 and falls
          back to the same word/byte pair everywhere else, so the loop bought
          nothing and cost the reuse path its whole per-byte budget. Measured:
          the pxx/FPC ratio on `b := nil; SetLength(b, N)` grew with N --
          1.32x at 32 bytes, 2.29x at 256, 4.62x at 2048 -- which is the
          signature of a per-BYTE cost, not per-call overhead. }
        PXXMemZero(Pointer(cur), size);
        Result := Pointer(cur);
{$ifdef PXX_TS_SOFTLOCK}
        PXXHeapSpin := 0;
{$endif}
{$ifdef PXX_ALLOC_CENSUS}
        if CensusAllocs >= CensusNext then PXXCensusReport;
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
{$ifdef PXX_ALLOC_CENSUS}
    CensusArenas := CensusArenas + 1;
{$endif}
    if (HeapLow = 0) or (HeapPtr < HeapLow) then HeapLow := HeapPtr;
    if HeapEnd > HeapHigh then HeapHigh := HeapEnd;
  end;
  base := HeapPtr;
  HeapPtr := HeapPtr + need;
  PWord(base)^ := size;                     { size header }
  Result := Pointer(base + 8);              { payload }
{$ifdef PXX_ALLOC_CENSUS}
  CensusBump := CensusBump + 1;
{$endif}
{$ifdef PXX_TS_SOFTLOCK}
  PXXHeapSpin := 0;
{$endif}
{$ifdef PXX_ALLOC_CENSUS}
  { Reported here and not on the reuse paths purely because this one already
    ends the routine; the trigger reads CensusAllocs, which every path bumped.
    Deliberately AFTER the spinlock is released: the printer takes no lock and
    must not run inside one — the same rule PXXDbgFlush's header states, and
    for the same reason (bug-a-threadsafe-plus-heap-debug-hangs-at-runtime). }
  if CensusAllocs >= CensusNext then PXXCensusReport;
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
  { Suffix labels for the write-after-free report. Separate constants rather
    than one formatted line for the same reason the four above are: this path
    may allocate NOTHING, so there is no string to build. }
  { A DECREF whose target refcount still reads as poison: the block was freed
    and something is still releasing a handle into it. Caught AT THE WRITE,
    where the HANDLE is known -- the eviction check can only report the victim
    long afterwards, by which time the handle that did it is gone. The object
    path has had this since DBG_M3/M4; strings never did, which is why 26 of
    these were reported as anonymous write-after-frees. }
  DBG_M8 = 'pxx-heap: DECREF of a FREED string 0x';
  { The other direction. No RETAIN of a freed string has been OBSERVED -- every
    one of the 26 arm32 reports was a decrement -- but the two guards in
    PXXStrIncRef/PXXStrDecRef already carry a comment saying they must move
    together, and guarding one arm while leaving the other to prose is how a
    sibling stays broken. It also makes an absence meaningful: with both armed,
    "only decrefs were reported" is a measurement rather than the shape of the
    instrument. }
  DBG_M9 = 'pxx-heap: RETAIN of a FREED string 0x';
  { Kinds 10/11: the dynamic-array half of the same protocol. PXXDynArrayIncRef
    and PXXDynArrayReleaseDepth decrement/increment the SAME [handle-16] slot
    as the string routines and carried NO poison check and no static-floor
    guard, which left them the only unguarded writer of a managed refcount
    once the string and object paths were both instrumented and both silent. }
  { Poor-man's backtrace: gdb on this box has no arm target and the guest
    carries no unwind info anyway, so the report emits RAW STACK WORDS and the
    resolving happens offline against the --map file. A word landing inside the
    code segment is a return address; the rest is noise and is meant to be. }
  DBG_M12 = ' stack=';
  DBG_M13 = '????????';   { the size word is not a plausible block size -- see PXXDbgFlush }
  DBG_M10 = 'pxx-heap: RELEASE of a FREED dynarray 0x';
  DBG_M11 = 'pxx-heap: RETAIN of a FREED dynarray 0x';
  DBG_M5 = '  size=0x';
  DBG_M6 = ' off=0x';
  DBG_M7 = ' val=0x';

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
  else if kind = 5 then
    for i := 1 to Length(DBG_M5) do
    begin b := Byte(DBG_M5[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 6 then
    for i := 1 to Length(DBG_M6) do
    begin b := Byte(DBG_M6[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 7 then
    for i := 1 to Length(DBG_M7) do
    begin b := Byte(DBG_M7[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 8 then
    for i := 1 to Length(DBG_M8) do
    begin b := Byte(DBG_M8[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 9 then
    for i := 1 to Length(DBG_M9) do
    begin b := Byte(DBG_M9[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 10 then
    for i := 1 to Length(DBG_M10) do
    begin b := Byte(DBG_M10[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 11 then
    for i := 1 to Length(DBG_M11) do
    begin b := Byte(DBG_M11[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 12 then
    for i := 1 to Length(DBG_M12) do
    begin b := Byte(DBG_M12[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 13 then
    for i := 1 to Length(DBG_M13) do
    begin b := Byte(DBG_M13[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else
    for i := 1 to Length(DBG_M4) do
    begin b := Byte(DBG_M4[i]); r := PXXSysWrite(2, Int64(@b), 1); end;
end;

{ Hex, high nibble first, no leading-zero suppression so the width is constant
  and greppable. `digits` is how many nibbles to emit. Factored out of
  PXXDbgFlush, which had this loop inline and now needs it four times -- one
  spelling, not five. }
procedure PXXDbgPutHex(v: Int64; digits: Integer);
var i: NativeInt; b: Byte; r: Int64; d: Integer;
begin
  i := (digits - 1) * 4;
  while i >= 0 do
  begin
    d := Integer((v shr i) and 15);
    if d < 10 then b := Byte(48 + d) else b := Byte(87 + d);
    r := PXXSysWrite(2, Int64(@b), 1);
    i := i - 4;
  end;
end;

procedure PXXDbgGrabStack(anchor: Int64);
{ Copy raw words upward from a local's address. The stack grows down, so higher
  addresses are older frames. No unwind is attempted and none is needed: a
  return address is recognised offline by falling inside the code segment. }
var i: Integer;
begin
  HeapDbgNStack := 32;
  for i := 0 to HeapDbgNStack - 1 do
    HeapDbgStack[i] := PWord(anchor + i * SizeOf(Pointer))^;
end;

procedure PXXDbgFlush;
var i: NativeInt; b: Byte; r: Int64; kind: Integer;
begin
  if HeapDbgPend = 0 then Exit;
  kind := Integer(HeapDbgPend);
  HeapDbgPend := 0;
  PXXDbgPutConst(kind);
  PXXDbgPutHex(HeapDbgAddr, SizeOf(Pointer) * 2);
  { A WRITE AFTER FREE carries its provenance; the other three kinds have none
    to carry, and printing empty fields for them would make a grep for `off=`
    match reports that never measured one. }
  { The stale-handle reports carry the victim's SIZE CLASS and nothing else:
    it is the field that JOINS them to the write-after-free rows above, which
    is the tie that was missing between a report naming a handle and a report
    naming a victim. Free to obtain -- the caller is already at the block. }
  if (kind = 8) or (kind = 9) or (kind = 10) or (kind = 11) then
  begin
    { The size word only MEANS anything if the thing we were handed is a real
      block. It is, for a genuinely stale handle whose block is still poisoned
      in quarantine -- that is the case this field exists for, because it JOINS
      these rows to the write-after-free rows by size class. It is NOT, for a
      FABRICATED pointer, and that turned out to be the arm32 case: the reported
      size read 0xdddddddd (the poison itself) and 0x44d95128. Printing those as
      a size class invites exactly the reading they cannot support, so an
      implausible word is reported as unknown instead of as a number.
      Plausible = nonzero, 8-aligned, and not larger than any block this
      allocator hands out in one piece. }
    PXXDbgPutConst(5);
    if (HeapDbgSize > 0) and (HeapDbgSize < $10000000) and
       ((HeapDbgSize and 7) = 0) and (not PXXDbgIsPoisonWord(HeapDbgSize)) then
      PXXDbgPutHex(HeapDbgSize, 8)
    else
      PXXDbgPutConst(13);
  end;
  if ((kind = 10) or (kind = 11)) and (HeapDbgNStack > 0) then
  begin
    PXXDbgPutConst(12);
    for i := 0 to HeapDbgNStack - 1 do
    begin
      if i > 0 then begin b := 32; r := PXXSysWrite(2, Int64(@b), 1); end;
      PXXDbgPutHex(HeapDbgStack[i], SizeOf(Pointer) * 2);
    end;
  end;
  if kind = 2 then
  begin
    PXXDbgPutConst(5); PXXDbgPutHex(HeapDbgSize, 8);
    PXXDbgPutConst(6); PXXDbgPutHex(HeapDbgOff, 8);
    PXXDbgPutConst(7); PXXDbgPutHex(HeapDbgVal, SizeOf(Pointer) * 2);
    { The bytes, hex then ASCII. This is the field that names the WRITER rather
      than the victim: printable text here is the scribbler's own data. }
    if HeapDbgNBytes > 0 then
    begin
      b := 32; r := PXXSysWrite(2, Int64(@b), 1);
      b := 91; r := PXXSysWrite(2, Int64(@b), 1);          { '[' }
      for i := 0 to HeapDbgNBytes - 1 do
      begin
        if i > 0 then begin b := 32; r := PXXSysWrite(2, Int64(@b), 1); end;
        PXXDbgPutHex(Int64(HeapDbgBytes[i]), 2);
      end;
      b := 93; r := PXXSysWrite(2, Int64(@b), 1);          { ']' }
      b := 32; r := PXXSysWrite(2, Int64(@b), 1);
      b := 34; r := PXXSysWrite(2, Int64(@b), 1);          { '"' }
      for i := 0 to HeapDbgNBytes - 1 do
      begin
        b := HeapDbgBytes[i];
        if (b < 32) or (b > 126) then b := 46;             { '.' }
        r := PXXSysWrite(2, Int64(@b), 1);
      end;
      b := 34; r := PXXSysWrite(2, Int64(@b), 1);
    end;
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

{ The offset of the first byte that is no longer poison, or -1 when the whole
  payload is intact. The offset is the diagnostic: relative to the payload
  address, which for a managed block is the block base, it names the FIELD that
  was written (0 = META and the free-list link, 8 = refcount, 16 = length,
  >= PXX_HDR_SIZE = the data). }
function PXXDbgPoisonFirstBad(addr, sz: Int64): Int64;
var i: Int64;
begin
  i := 0;
  while i < sz do
  begin
    if PByte(addr + i)^ <> HEAP_POISON then
    begin
      PXXDbgPoisonFirstBad := i;
      Exit;
    end;
    i := i + 1;
  end;
  PXXDbgPoisonFirstBad := -1;
end;

{ TRUE when the whole payload still reads as poison. One scan, not two
  spellings of it. }
function PXXDbgPoisonIntact(addr, sz: Int64): Boolean;
begin
  PXXDbgPoisonIntact := PXXDbgPoisonFirstBad(addr, sz) < 0;
end;

{ Poison `addr` and put it in quarantine. Returns the block EVICTED by that
  push (which the caller must really free), or 0 while the ring is filling.
  The caller holds the allocator lock. }
function PXXDbgQuarantine(addr: Int64): Int64;
var sz, vic, vsz, i, bad: Int64; slot: Integer;
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
    bad := PXXDbgPoisonFirstBad(vic, vsz);
    if bad >= 0 then
    begin
      HeapDbgPend := 2;
      HeapDbgAddr := vic;
      { Everything below was already known here and was being discarded. }
      HeapDbgSize := vsz;
      HeapDbgOff  := bad;
      HeapDbgVal  := PWord(vic + bad)^;
      HeapDbgNBytes := 0;
      i := bad;
      while (i < vsz) and (HeapDbgNBytes < 16) do
      begin
        HeapDbgBytes[HeapDbgNBytes] := PByte(vic + i)^;
        HeapDbgNBytes := HeapDbgNBytes + 1;
        i := i + 1;
      end;
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
    bin := Integer(sz shr 3) - 1;
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
{$ifdef PXX_ALLOC_CENSUS}
  { Counted after the nil guard, so `frees` is comparable with `allocs`: a nil
    free is not a free, and counting it would make live look negative. }
  CensusFrees := CensusFrees + 1;
{$endif}
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
    bin := Integer(sz shr 3) - 1;
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
  newSize := (newSize + 7) and (not NativeInt(7));
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
  { Same two calls as the hosted PXXDynSetLen below, for the same reason. Both
    helpers are forward-declared at the top of this unit, so the ESP arm is not
    obliged to hand-roll what the hosted one calls.
    feature-opt-bulk-copy-is-byte-at-a-time }
  PXXMemZero(newArrData, newLen * elSize);
  if oldData <> nil then
  begin
    oldLen := PWord(Int64(oldData) - 8)^;
    copyLen := oldLen;
    if newLen < copyLen then copyLen := newLen;
    PXXBlockCopy(Int64(newArrData), Int64(oldData), copyLen * elSize);
  end;
  PWord(arrSlot)^ := Int64(newArrData);
  PXXDynArrayReleaseEsp(oldData);
end;
{$endif}

{ Managed-string constructor: allocate a [refcount:8][length:8][data][nul]
  block and copy len bytes from src. Returns the data pointer (base+PXX_HDR_SIZE) or
  nil for an empty string. Called from the emitted runtime shim
  (AnsiStrFromLiteralAddr); the shim holds the heap lock in threadsafe mode.
  Raw pointers only — this code IS the string runtime, so it must not use
  managed strings itself. }
function PXXStrFromLit(len: NativeInt; src: Pointer): Pointer;
var
  base, s, d, i, orAll, b: Int64;
begin
{$ifdef PXX_NILPY_STR}
  { NilPy string model (decide-nilpy-none-str-representation): a zero-length
    NilPy string is a REAL block, so nil goes back to meaning only None and
    `"" is None` stops answering True. The define is set only for a NilPy
    compilation, so a Pascal program -- the self-host binary included --
    compiles the `len <= 0` arm below and keeps FPC's collapse untouched BY
    CONSTRUCTION rather than by audit. }
  if len < 0 then
{$else}
  if len <= 0 then
{$endif}
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

{ The bytes PXXAlloc actually handed out for a block, which is where the spare
  capacity for an in-place append comes from: PXXAlloc stores its (8-rounded)
  size in a word immediately below the payload it returns, and a string's block
  base IS that payload. No header change -- adding a capacity field would move
  PXX_HDR_SIZE and therefore every codegen offset for length and refcount. }
function PXXStrAllocSize(h: Pointer): Int64;
begin
  if h = nil then PXXStrAllocSize := 0
  else PXXStrAllocSize := PWord(Int64(h) - PXX_HDR_SIZE - 8)^;
end;

{ The ASCII answer for the RESULT of an append, given what the destination
  block already knew and the OR of the appended bytes. The append loop touches
  every appended byte anyway, so the cached answer can be MAINTAINED across a
  growth instead of dropped — which is the whole reason PXX_FLAG_ASCII_KNOWN
  exists, and dropping it made an accumulated all-ASCII string report
  IsAscii=false (bug-a-in-place-append-loses-the-ascii-kind-flag-on-growth).

  The truth table, and why each row is the only sound one:
  - an appended byte >= $80 makes the result definitely non-ASCII whatever the
    old block said, so the answer is KNOWN and the ASCII bit clear;
  - otherwise the result's ASCII-ness is exactly the old block's, INCLUDING
    "unknown" (both bits clear). Unknown must stay unknown: inventing ASCII for
    a block nobody scanned is the wrong-and-fast error test_managed_block_meta
    pins. }
{ ---- word-at-a-time block copy ------------------------------------------
  Every copy loop in this runtime moved ONE BYTE per iteration. Measured on
  uforth's core.fr suite (callgrind, 12.1e9 Ir): PXXAlloc + PXXStrFromLit +
  PXXFree = 28.5% and the pure copy routines another ~13%, on a workload whose
  remaining 2.28x-vs-CPython the ticket had already established is allocation
  and copy churn rather than any one pole.
  bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython

  ALIGNMENT IS NOT OPTIONAL HERE. ARM32 faults on an unaligned word access and
  the 32-bit targets generally may; so the word loop runs only when BOTH ends
  are machine-word aligned, and the byte loop is the tail and the fallback. In
  practice the aligned case is the common one: a string's data sits at
  base + PXX_HDR_SIZE with PXX_HDR_SIZE = 24 and base 8-aligned, so string-to-
  string copies qualify — but `d + lenA` in a two-segment concat does not
  unless lenA happens to be a multiple of the word size, which is exactly why
  each segment asks for itself rather than the routine asking once.
  Steps by SizeOf(NativeInt), never a literal 8: a hardcoded step copied every
  other word on 32-bit once already. }
function PXXWordStep: Int64;
begin
  PXXWordStep := SizeOf(NativeInt);
end;

{ Are both ends word-aligned, and is there enough to be worth the setup? }
function PXXWordCopyOk(d: Int64; s: Int64; n: Int64): Boolean;
begin
{$ifdef CPUX86_64}
  { x86 loads and stores a word at any address, so the alignment question does
    not arise -- only whether a whole word is left to move. Refusing the word
    loop on a misaligned pair here cost every Copy() of a byte array at an odd
    offset an 8x slower byte loop, for nothing. }
  PXXWordCopyOk := n >= SizeOf(NativeInt);
{$else}
{$ifdef CPU_I386}
  PXXWordCopyOk := n >= SizeOf(NativeInt);
{$else}
  PXXWordCopyOk := (n >= SizeOf(NativeInt)) and
                   (((d or s) and (SizeOf(NativeInt) - 1)) = 0);
{$endif}
{$endif}
end;

{ The high bit of every byte in a machine word — the word-wise form of the
  `orAll and $80` test PXXStrMeta does, so an ASCII scan folded into a word
  copy answers exactly what the byte loop answered.

  A CONST, not a function, and the difference was measured: this was an
  eight-iteration `m := (m shl 8) or $80` loop in a function called once per
  PXXBlockCopy, and a gdb-sampled profile of uforth put 5.1% of the program's
  ENTIRE runtime inside it — the fifth-hottest routine in a 134-routine profile,
  more than the whole compiled body of uforth.py. The loop was not folded and
  could not be: it loads and stores `m` and `i` through memory eight times, and
  our IR does not constant-fold a loop. bug-a-pxxhighbits-recomputes-a-compile-
  time-constant-in-a-loop.

  Keyed on CPU64/CPU32, which the lexer predefines for every target, rather than
  on a list of target names — the ENUMERATION is what goes stale, and a mask one
  word too wide is a silently wrong ASCII verdict rather than a build error. The
  32-bit value is deliberately only 4 bytes: PWord on a 32-bit target reads 4
  bytes, and a hardcoded 8-byte step in this same routine already copied every
  other word once. }
const
{$ifdef CPU64}
  PXX_HIGH_BITS = Int64($8080808080808080);
{$else}
  PXX_HIGH_BITS = Int64($80808080);
{$endif}

{ Copy n bytes forward, words first. Returns the OR of every byte COLLAPSED to
  the one bit PXXStrMeta looks at: $80 when any byte had its high bit set, else
  0. Callers that do not want the scan simply ignore the result. }
function PXXBlockCopy(d: Int64; s: Int64; n: Int64): Int64;
var i, w, acc: Int64;
begin
  acc := 0;
  i := 0;
  w := SizeOf(NativeInt);
  if PXXWordCopyOk(d, s, n) then
    while i + w <= n do
    begin
      PWord(d + i)^ := PWord(s + i)^;
      acc := acc or PWord(s + i)^;
      i := i + w;
    end;
  if (acc and PXX_HIGH_BITS) <> 0 then acc := $80 else acc := 0;
  while i < n do
  begin
    PByte(d + i)^ := PByte(s + i)^;
    acc := acc or PByte(s + i)^;
    i := i + 1;
  end;
  if (acc and $80) <> 0 then PXXBlockCopy := $80 else PXXBlockCopy := 0;
end;

function PXXStrAppendAsciiBits(oldMeta: Int64; orAll: Int64): Int64;
begin
  if (orAll and $80) <> 0 then
    PXXStrAppendAsciiBits := PXX_FLAG_ASCII_KNOWN
  else
    PXXStrAppendAsciiBits := oldMeta and (PXX_FLAG_ASCII_KNOWN or PXX_FLAG_ASCII);
end;


procedure PXXStrAppend(strSlot: Pointer; srcB: Pointer; lenB: NativeInt);
var
  h, oldLen, newLen, rc, cap, need, want, base, d, s2, i: Int64;
  orAll, oldMeta: Int64;
  newH: Pointer;
begin
  if strSlot = nil then Exit;
  if lenB <= 0 then Exit;
  h := PWord(strSlot)^;
  if h = 0 then
  begin
    PWord(strSlot)^ := Int64(PXXStrFromLit(lenB, srcB));
    Exit;
  end;
  oldLen := PWord(h - 8)^;
  rc := PWord(h - 16)^;
  newLen := oldLen + lenB;
  need := PXX_HDR_SIZE + newLen + 1;          { +1 = nul terminator }
  cap := PXXStrAllocSize(Pointer(h));
  oldMeta := PXXHdrMeta(Pointer(h));
  orAll := 0;

  { IN PLACE: sole owner, this code allocated the block's spare capacity (so
    the size word below it means what we think), and that capacity is enough. }
  if (rc <= 1) and ((oldMeta and PXX_FLAG_APPENDABLE) <> 0) and
     (cap >= need) then
  begin
    d := h + oldLen;
    orAll := PXXBlockCopy(d, Int64(srcB), lenB);
    PByte(h + newLen)^ := 0;
    PWord(h - 8)^ := newLen;
    { The bytes changed, but not unknowably: carry the answer forward rather
      than forgetting it. }
    PWord(h - PXX_HDR_SIZE + PXX_HDR_META)^ :=
      (oldMeta and (not (PXX_FLAG_ASCII_KNOWN or PXX_FLAG_ASCII))) or
      PXXStrAppendAsciiBits(oldMeta, orAll);
    Exit;
  end;

  { GROW: ask for double what is needed, so a loop of appends reallocates a
    logarithmic number of times instead of every iteration. That doubling is
    the whole difference between O(n) and O(n^2) for `s += c`; without it an
    exact-fit block is full again on the very next append. }
  want := need * 2;
  base := Int64(PXXAlloc(want, 8));
  PXXHdrInit(base);
  { Stamp APPENDABLE: this block, and only a block from here, carries spare
    capacity the size word describes. The ASCII bits are filled in below, once
    the appended bytes have been OR'd — the old half's answer comes from
    oldMeta, so the copy does not have to rescan what was already known. }
  PWord(base + PXX_HDR_META)^ := PXX_KIND_LEGACY or PXX_FLAG_APPENDABLE;
  PWord(base + PXX_HDR_RC)^ := 1;
  PWord(base + PXX_HDR_LEN)^ := newLen;
  d := base + PXX_HDR_SIZE;
  { the old half's ASCII answer comes from oldMeta, so its copy discards the
    scan; only the appended half's bytes are new information }
  PXXBlockCopy(d, h, oldLen);
  orAll := PXXBlockCopy(d + oldLen, Int64(srcB), lenB);
  PByte(d + newLen)^ := 0;
  PWord(base + PXX_HDR_META)^ := PXX_KIND_LEGACY or PXX_FLAG_APPENDABLE or
                                 PXXStrAppendAsciiBits(oldMeta, orAll);
  newH := Pointer(d);
  PWord(strSlot)^ := Int64(newH);
  PXXStrDecRef(Pointer(h));
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
  { one word per iteration where the ends allow it, byte tail otherwise, and
    the ASCII scan folded in — see PXXBlockCopy. Each segment asks for itself:
    `d + lenA` is only word-aligned when lenA happens to be a multiple of the
    word size. }
  orAll := PXXBlockCopy(d, Int64(srcA), lenA);
  orAll := orAll or PXXBlockCopy(d + lenA, Int64(srcB), lenB);
  PByte(d + total)^ := 0;       { nul terminator }
  PXXHdrSetMeta(base, PXXStrMeta(orAll));
  Result := Pointer(d);
end;

{ ---- UTF-16 string runtime (feature-unicodestring-model) ----

  A wide string is the SAME managed block as an AnsiString: 24-byte header,
  refcount at -16, byte length at -8, handle = block + PXX_HDR_SIZE. Only two
  things differ, and both are here rather than spread through the ARC paths:
  the data is 2-byte code units, and the terminator is a 2-byte NUL.

  The header length stays a BYTE count on purpose. It is what makes
  PXXStrIncRef/DecRef, PXXBlockCopy, the free path and every backend's
  retain/release blob work on a wide string with no second arm -- the exact
  "sibling arm" cost the stride objection predicted and that keeping bytes in
  the header avoids. Length() halving it is a FRONTEND lowering off the
  string's ELEMENT type, not a runtime tag lookup.

  No ASCII flag is stamped. PXX_FLAG_ASCII means "no byte >= $80", which for
  UTF-16 is true of any ASCII text and says nothing useful, while
  PXXStrAsciiCached's contract is about BYTE positions equalling CHARACTER
  positions -- false here for every string. Leaving it unset means "unknown",
  which is the honest answer and the one every consumer already handles. }

function PXXSysRead(fd, buf, count: NativeInt): Int64;
begin
{$if defined(CPUX86_64)}
  Result := __pxxrawsyscall(0, fd, buf, count);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(3, fd, buf, count);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(3, fd, buf, count);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(63, fd, buf, count);
{$elseif defined(CPU_RISCV32)}
  Result := __pxxrawsyscall(63, fd, buf, count);   { hosted linux (qemu-user) }
{$elseif defined(CPU_XTENSA)}
  { Track S's call, made 2026-08-29: 12 is __NR_read in XTENSA'S OWN table,
    measured under qemu-xtensa — not the generic numbering riscv32 uses two
    arms up, where read is 63. The previous `Result := 0` was the pre-chain
    default inherited by every unnamed target, and as that comment warned, 0
    here reads as EOF: a hosted xtensa program saw every file as empty and no
    error was raised. Bare/IDF xtensa never reaches this — the ESP PAL owns
    file I/O there.
    feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle }
  Result := __pxxrawsyscall(12, fd, buf, count);
{$else}
  { No arm. -1 is the POSIX failure value; a fall-through 0 would report EOF. }
  Result := -1;
{$endif}
end;


{$ifdef CPU_WASM32}
{ wasm has no syscall instruction, so the host is reached through an IMPORT —
  and `external 'lib' name 'sym'` already carries exactly the module/field pair
  a wasm import needs (ProcLibrary / ProcExtName). The wasm32 backend lowers
  this declaration to `(import "wasi_snapshot_preview1" "fd_write" ...)`. }
function __wasi_fd_write(fd: NativeInt; iovs: Pointer; iovsLen: NativeInt;
                         nwritten: Pointer): NativeInt;
  external 'wasi_snapshot_preview1' name 'fd_write';
{$endif}

function PXXSysWrite(fd, buf, count: NativeInt): Int64;
{$ifdef CPU_WASM32}
var iov: array[0..1] of Integer; nw: Integer;
{$endif}
begin
{$if defined(CPU_WASM32)}
  { One iovec: [ptr, len]. WASI returns an ERRNO, not a byte count — the count
    is written to *nwritten — so the two are not interchangeable and a caller
    reading the return value as a length would get 0 on success. }
  iov[0] := Integer(buf);
  iov[1] := Integer(count);
  nw := 0;
  if __wasi_fd_write(fd, @iov[0], 1, @nw) = 0 then Result := nw
  else Result := -1;
{$elseif defined(CPUX86_64)}
  Result := __pxxrawsyscall(1, fd, buf, count);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(4, fd, buf, count);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(4, fd, buf, count);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(64, fd, buf, count);
{$elseif defined(CPU_RISCV32)}
  Result := __pxxrawsyscall(64, fd, buf, count);   { hosted linux (qemu-user) }
{$elseif defined(CPU_XTENSA)}
  { As in PXXSysRead, and the same call: 13 is __NR_write in xtensa's own
    table (measured), NOT the 64 riscv32 uses two arms up. The previous
    `Result := 0` meant "wrote nothing, successfully", which is why a hosted
    WriteLn emitted its string through the inline syscall in codegen and then
    silently dropped the newline PXXWriteNL sends through here. }
  Result := __pxxrawsyscall(13, fd, buf, count);
{$else}
  { No arm. See PXXSysOpenRO. }
  Result := -1;
{$endif}
end;

{$ifdef PXX_ALLOC_CENSUS}
{ ---- allocation census report (-dPXX_ALLOC_CENSUS) -------------------------
  One block to stderr each time the allocation count reaches the next power of
  two. Geometric and not a fixed stride on purpose, and the reason is that
  there is no exit hook to report from: the program's last line is emitted by
  CODEGEN (EmitExit), not by this runtime, so a census that only printed at the
  end would need a change outside this file. Doubling thresholds mean the last
  report is always within 2x of the true total, a short program still gets one,
  a long one gets a growth CURVE rather than a single number — and a program
  that segfaults leaves its census behind, which a report-at-exit would not.

  Read it as: `live` is allocs minus frees, so a flat live with a climbing
  allocs is churn and a climbing live is retention. `reuse` versus `bump` says
  whether the free lists are doing their job. The size histogram is where the
  churn actually is.

  ALLOCATES NOTHING, and that is a hard requirement rather than tidiness: this
  runs from inside PXXAlloc, so an allocation here would re-enter the allocator,
  and a managed string temp would be finalized on the way out into the release
  blob which takes the heap lock. That is the hang PXXDbgFlush's header
  documents (bug-a-threadsafe-plus-heap-debug-hangs-at-runtime); the rules are
  the same here. Digits go out one byte at a time out of a local, and the label
  text is indexed in place out of constants.

  Cost when the define is OFF is zero — every counter and every trigger is
  inside the ifdef, so the shipped allocator is unchanged.
  bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython }
const
  CEN_HDR   = 'pxx-census: allocs=';
  CEN_FREE  = ' frees=';
  CEN_LIVE  = ' live=';
  CEN_BYTES = ' bytes=';
  CEN_REUSE = ' reuse=';
  CEN_LIST  = ' list=';
  CEN_BUMP  = ' bump=';
  CEN_AREN  = ' arenas=';
  CEN_SIZES = 'pxx-census: sizes';
  CEN_BIG   = 'pxx-big: ';
  CEN_BIGAT = ' at alloc ';

procedure PXXCensusPut(kind: Integer);
{ One byte at a time out of a string CONSTANT — no managed temp anywhere. }
var i: NativeInt; b: Byte; r: Int64;
begin
  if kind = 1 then
    for i := 1 to Length(CEN_HDR) do begin b := Byte(CEN_HDR[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 2 then
    for i := 1 to Length(CEN_FREE) do begin b := Byte(CEN_FREE[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 3 then
    for i := 1 to Length(CEN_LIVE) do begin b := Byte(CEN_LIVE[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 4 then
    for i := 1 to Length(CEN_BYTES) do begin b := Byte(CEN_BYTES[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 5 then
    for i := 1 to Length(CEN_REUSE) do begin b := Byte(CEN_REUSE[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 6 then
    for i := 1 to Length(CEN_LIST) do begin b := Byte(CEN_LIST[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 7 then
    for i := 1 to Length(CEN_BUMP) do begin b := Byte(CEN_BUMP[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 8 then
    for i := 1 to Length(CEN_AREN) do begin b := Byte(CEN_AREN[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 10 then
    for i := 1 to Length(CEN_BIG) do begin b := Byte(CEN_BIG[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else if kind = 11 then
    for i := 1 to Length(CEN_BIGAT) do begin b := Byte(CEN_BIGAT[i]); r := PXXSysWrite(2, Int64(@b), 1); end
  else
    for i := 1 to Length(CEN_SIZES) do begin b := Byte(CEN_SIZES[i]); r := PXXSysWrite(2, Int64(@b), 1); end;
end;

procedure PXXCensusNum(v: Int64);
{ Decimal, no padding. Built high digit first into a local byte array so the
  common case is one write; negatives cannot occur here but are printed rather
  than hidden, because a negative `live` is exactly the bug this would be used
  to find. }
var buf: array[0..23] of Byte; n, i: Integer; d: Int64; r: Int64; neg: Boolean;
begin
  neg := v < 0;
  if neg then v := -v;
  n := 0;
  if v = 0 then begin buf[0] := 48; n := 1; end
  else
    while v > 0 do
    begin
      d := v mod 10;
      buf[n] := Byte(48 + d);
      n := n + 1;
      v := v div 10;
    end;
  if neg then begin buf[n] := 45; n := n + 1; end;
  { buf holds the digits reversed; emit backwards. }
  i := n - 1;
  while i >= 0 do
  begin
    r := PXXSysWrite(2, Int64(@buf[i]), 1);
    i := i - 1;
  end;
end;

{$ifdef PXX_ALLOC_BIG}
procedure PXXCensusBig(size: NativeInt);
{ One line per allocation at or above CEN_BIG_MIN. Allocates nothing, for the
  same reason PXXCensusReport does not -- it runs from inside PXXAlloc. }
var b: Byte; r: Int64;
begin
  PXXCensusPut(10); PXXCensusNum(size);
  PXXCensusPut(11); PXXCensusNum(CensusAllocs);
  b := 10; r := PXXSysWrite(2, Int64(@b), 1);
end;
{$endif}

procedure PXXCensusReport;
var i: Integer; b: Byte; r: Int64;
begin
  { Advance the threshold FIRST. If anything below ever allocated, the trigger
    would otherwise still be armed and the report would recurse forever.

    Geometric at 1.125 rather than doubling, and the ratio is the whole
    usability of the tool. There is no exit hook, so the LAST report is the
    closest thing to a total and its error is the step size: doubling leaves it
    anywhere within 2x, which was measured to be too loose to A/B on — two runs
    of the same program differing by half their allocations produced last-report
    ranges that OVERLAPPED, so the honest reading was "no conclusion". At
    +1/8 the tail is within 12.5% and about 180 lines cover 1e9 allocations.
    Integer arithmetic throughout, and the +1 is what makes it move at all
    below 8. }
  if CensusNext = 0 then CensusNext := 1;
  while CensusAllocs >= CensusNext do
    CensusNext := CensusNext + (CensusNext div 8) + 1;

  PXXCensusPut(1); PXXCensusNum(CensusAllocs);
  PXXCensusPut(2); PXXCensusNum(CensusFrees);
  PXXCensusPut(3); PXXCensusNum(CensusAllocs - CensusFrees);
  PXXCensusPut(4); PXXCensusNum(CensusBytes);
  PXXCensusPut(5); PXXCensusNum(CensusReuse);
  PXXCensusPut(6); PXXCensusNum(CensusList);
  PXXCensusPut(7); PXXCensusNum(CensusBump);
  PXXCensusPut(8); PXXCensusNum(CensusArenas);
  b := 10; r := PXXSysWrite(2, Int64(@b), 1);

  PXXCensusPut(9);
  for i := 0 to HEAP_BIN_COUNT - 1 do
    if CensusBins[i] <> 0 then
    begin
      b := 32; r := PXXSysWrite(2, Int64(@b), 1);
      PXXCensusNum((i + 1) * 8);
      b := 58; r := PXXSysWrite(2, Int64(@b), 1);   { ':' }
      PXXCensusNum(CensusBins[i]);
    end;
  b := 10; r := PXXSysWrite(2, Int64(@b), 1);
end;
{$endif}



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
  PXXBlockCopy(Int64(dst) + 8, Int64(src), len);
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
{$if defined(CPUX86_64)}
  Result := __pxxrawsyscall(2, Int64(path), 0, 0);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(5, Int64(path), 0, 0);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(5, Int64(path), 0, 0);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(56, -100, Int64(path), 0, 0);
{$elseif defined(CPU_RISCV32)}
  { asm-generic, like aarch64 above: there is NO plain `open` in that table, so
    this is openat(AT_FDCWD = -100, path, O_RDONLY, 0). }
  Result := __pxxrawsyscall(56, -100, Int64(path), 0, 0);
{$elseif defined(CPU_XTENSA)}
  { xtensa's OWN table, measured under qemu-xtensa -strace: openat is 288, not
    the 56 riscv32 and aarch64 use. xtensa DOES still carry a legacy open (8),
    and this deliberately does not use it -- openat is what the other generic
    targets here issue, and the matching SysOpen builtin in
    ir_codegen_xtensa.inc lowers to openat for the same reason, so the two
    routes to a file descriptor on this target cannot drift apart. }
  Result := __pxxrawsyscall(288, -100, Int64(path), 0, 0);
{$else}
  { NO ARM FOR THIS TARGET — see the group comment above. Returning the POSIX
    failure value is the whole point: before this was one chain it was four
    separate {$ifdef}/{$endif} blocks with no terminal else and no pre-chain
    default, so an armless target left `Result` NEVER ASSIGNED and
    PXXStrLoadFile's `if fd < 0 then Exit` tested the return slot's leftover
    contents. }
  Result := -1;
{$endif}
end;

function PXXSysLseek(fd, offset, whence: NativeInt): Int64;
{$if defined(CPU_RISCV32)}
var res, r: Int64;   { STACK locals -- this group runs under the heap lock and
                       must allocate nothing (see the group comment). }
{$endif}
begin
{$if defined(CPUX86_64)}
  Result := __pxxrawsyscall(8, fd, offset, whence);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(19, fd, offset, whence);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(19, fd, offset, whence);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(62, fd, offset, whence);
{$elseif defined(CPU_RISCV32)}
  { rv32's 62 is _llseek(fd, off_hi, off_lo, loff_t *result, whence), NOT plain
    lseek -- rv32 has no plain lseek at all. The 3-arg form leaves the result
    pointer NULL and the kernel returns EINVAL, which is not a hypothesis:
    qemu-riscv32 -strace on test_cross_loadfile printed

      openat(AT_FDCWD,"test/hello.pas",O_RDONLY) = 3
      llseek(3,0,2,NULL,UNKNOWN)                 = -1 errno=22
      read(3,0x2b2ad050,-22)                     = -1 errno=14

    -- a size of -1 flowing into read as a count, and LoadFile publishing an
    EMPTY string with no error anywhere. This mirrors PalBackendSeek in
    lib/rtl/platform/posix/platform_backend.pas, which already carries the
    identical split and the identical reason; the two must not drift. }
  res := 0;
  r := __pxxrawsyscall(62, fd, (offset shr 32) and $FFFFFFFF,
                       offset and $FFFFFFFF, Int64(@res), whence);
  if r < 0 then Result := r else Result := res;
{$elseif defined(CPU_XTENSA)}
  { xtensa's own table again: lseek is 15. Same small-offset caveat as rv32. }
  Result := __pxxrawsyscall(15, fd, offset, whence);
{$else}
  { No arm — see PXXSysOpenRO. A garbage size here is the worse half of the
    defect: PXXStrLoadFile feeds it straight to PXXAlloc(size + hdr + 1). }
  Result := -1;
{$endif}
end;

function PXXSysClose(fd: NativeInt): Int64;
begin
{$if defined(CPUX86_64)}
  Result := __pxxrawsyscall(3, fd);
{$elseif defined(CPU_I386)}
  Result := __pxxrawsyscall(6, fd);
{$elseif defined(CPU_ARM32)}
  Result := __pxxrawsyscall(6, fd);
{$elseif defined(CPUAARCH64)}
  Result := __pxxrawsyscall(57, fd);
{$elseif defined(CPU_RISCV32)}
  Result := __pxxrawsyscall(57, fd);                { asm-generic }
{$elseif defined(CPU_XTENSA)}
  Result := __pxxrawsyscall(9, fd);                 { xtensa's own table }
{$else}
  { No arm — see PXXSysOpenRO. }
  Result := -1;
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
  at [p-16], length at [p-8]. PXXStrDecRef frees the block (base = p-16) when
  the count reaches zero. nil is ignored.

  Non-atomic in the DEFAULT build; under --threadsafe (PXX_TS_SOFTLOCK) the
  increments below use __pxxatomic_add. Corrected 2026-08-30: this said
  "NON-atomic — threadsafe mode is x86-64 only", and both halves had stopped
  being true — the ifdef'd body twelve lines down is atomic, and --threadsafe
  covers more than x86-64. For WHICH targets, see the gate in compiler.pas
  (the ThreadSafeMode target check); that condition is the authority and this
  comment deliberately does not repeat the list. }
procedure PXXStrIncRef(p: Pointer);
var rcAddr: Int64;
{$ifdef PXX_TS_SOFTLOCK}
    tsIgnore: Int64;
{$endif}
begin
  if p = nil then Exit;
  rcAddr := PXXHdrRC(p);
{$ifdef PXX_HEAP_DEBUG}
  { Mirror of the check in PXXStrDecRef -- see DBG_M9 for why this arm exists
    with nothing yet observed on it. }
  if PXXDbgIsPoisonWord(PWord(rcAddr)^) then
  begin
    HeapDbgPend := 9;
    HeapDbgAddr := Int64(p);
    { The allocator's size word sits immediately below the block it handed out,
      and a managed block's base IS that payload -- so this is the same size
      class the write-after-free rows report.
      RAW arithmetic, NOT PXXHdrBase: under PXX_HEAP_DEBUG that helper Halt(204)s
      on exactly the input we are here to report (a poisoned kind byte is > 
      PXX_KIND_MAX), so routing through it killed the process one line before
      PXXDbgFlush and this check read as SILENT on every target that calls the
      routine at all. }
    HeapDbgSize := PWord(Int64(p) - PXX_HDR_SIZE - 8)^;
    PXXDbgFlush;
    Exit;
  end;
{$endif}
  { A static literal block must never be WRITTEN, not merely never freed: it
    lives in the data section, so a store to it dirties a page shared with code
    (1600x under qemu — see the parent ticket) and defeats ever placing these
    blocks in a non-writable segment. The read below is already on this path;
    the guard costs a compare and a branch and removes a store. }
  if PWord(rcAddr)^ >= PXX_STATIC_RC_FLOOR then Exit;
{$ifdef PXX_TS_SOFTLOCK}
  { threadsafe: atomic increment of the low refcount word (the count never
    approaches 2^32, so the 8-byte header's high dword stays zero). The plain
    read above is sound under contention for the one thing it decides: a
    saturated block's count is immutable, and a real one cannot reach 2^30. }
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
{$ifdef PXX_HEAP_DEBUG}
  { The refcount still reads as poison, so this block is in quarantine and this
    handle is stale. Report and DROP the write: decrementing would corrupt the
    poison and turn a precise finding into an anonymous write-after-free found
    much later, which is exactly how these first showed up.
    Note the static guard below cannot catch this: poison is $DDDD..., which is
    NEGATIVE as a signed machine word and so never >= PXX_STATIC_RC_FLOOR. }
  if PXXDbgIsPoisonWord(PWord(rcAddr)^) then
  begin
    HeapDbgPend := 8;
    HeapDbgAddr := Int64(p);
    { The allocator's size word sits immediately below the block it handed out,
      and a managed block's base IS that payload -- so this is the same size
      class the write-after-free rows report.
      RAW arithmetic, NOT PXXHdrBase: under PXX_HEAP_DEBUG that helper Halt(204)s
      on exactly the input we are here to report (a poisoned kind byte is > 
      PXX_KIND_MAX), so routing through it killed the process one line before
      PXXDbgFlush and this check read as SILENT on every target that calls the
      routine at all. }
    HeapDbgSize := PWord(Int64(p) - PXX_HDR_SIZE - 8)^;
    PXXDbgFlush;
    Exit;
  end;
{$endif}
  { Saturated: no write, and no free to consider. Same guard as PXXStrIncRef —
    they must move together, because suppressing one direction only is what
    would let a static block's count drift. }
  if PWord(rcAddr)^ >= PXX_STATIC_RC_FLOOR then Exit;
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
  base+PXX_HDR_SIZE of its own heap block: [kind:8][rc:8][spare:8][instance data...], so the
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
procedure PXXRecordZeroManaged(recAddr: Pointer; desc: Pointer);
{ Store a valid EMPTY state into every managed member, releasing nothing.

  Two callers with opposite reasons for wanting it, which is why it is its own
  walk rather than folded into either:
  - Initialize: the incoming bytes are NOT references. Releasing them would
    decrement a refcount through whatever GetMem last left there.
  - Finalize, after PXXRecordRelease: what makes a second Finalize decrement
    nothing. Losing that turns the obvious double-Finalize into a heap
    corruption instead of a no-op.

  A zeroed slot IS the empty state for every managed kind here: a nil string
  handle is '' , a nil dyn-array handle is length 0, a nil interface/object
  reference is nil, and varEmpty is 0. Variants are zeroed as bytes rather than
  PXXVarClear'd for the Initialize reason above -- PXXVarClear reads the tag
  first, and on garbage that is a deref of a garbage pointer. }
var
  memberCount, i, j: Integer;
  memberPtr: Int64;
  offset, kind, arrayCount, typeRef: Integer;
  memberAddr, itemAddr: Pointer;
  subDesc: Pointer;
  memberSize, k: Int64;
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
    subDesc := Pointer(memberPtr + 12 + typeRef);
    if kind = 3 then memberSize := PInt32(Int64(subDesc) + 4)^
    else if kind = 5 then memberSize := 16   { Variant slot: [tag:8][payload:8] }
    else memberSize := SizeOf(Pointer);
    j := 0;
    while j < arrayCount do
    begin
      itemAddr := Pointer(Int64(memberAddr) + j * memberSize);
      case kind of
        1: PWord(itemAddr)^ := 0;                     { String handle }
        2: PWord(itemAddr)^ := 0;                     { DynArray handle }
        3: PXXRecordZeroManaged(itemAddr, subDesc);   { nested record }
        4: PWord(itemAddr)^ := 0;                     { COM interface }
        5: begin                                      { Variant: varEmpty = all zero }
             k := 0;
             while k < memberSize do
             begin
               PByte(Int64(itemAddr) + k)^ := 0;
               k := k + 1;
             end;
           end;
        6: PWord(itemAddr)^ := 0;                     { NilPy class reference }
      end;
      j := j + 1;
    end;
    memberPtr := memberPtr + 16;
    i := i + 1;
  end;
end;

procedure PXXRecordInitialize(recAddr: Pointer; desc: Pointer);
{ Initialize(x): put the managed members into a valid empty state WITHOUT
  releasing -- the incoming bytes are not references, which is the whole point.
  Unmanaged members are left alone (FPC does the same); a caller who wants the
  whole record cleared has FillChar, and FillChar over managed fields is the
  hazard this intrinsic exists to replace. }
begin
  PXXRecordZeroManaged(recAddr, desc);
end;

procedure PXXRecordFinalize(recAddr: Pointer; desc: Pointer);
{ Finalize(x): release each managed member's REFERENCE, then nil it.

  Releases a reference, not the object: a string at refcount 3 because copies
  exist goes to 2 and the copies stay valid. And it nils, so a second Finalize
  on the same storage decrements nothing. }
begin
  PXXRecordRelease(recAddr, desc);
  PXXRecordZeroManaged(recAddr, desc);
end;

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
  { Whichever path runs, the caller is about to WRITE bytes through the handle
    we return, so any cached ASCII answer stops being true. rc<=1 hands back the
    same block (mutated in place); the COW path copies through PXXStrFromLit,
    which stamps the flag from the OLD bytes. Both must forget it.

    This is ONE of several sites that mutate bytes, not the only one — the
    sentence that used to stand here said "the single choke point for byte
    mutation, which is what makes the cache sound", and on 2026-08-29 three
    separate bugs were fixed that had all been caused by believing it
    (8be3c6d06, df19c72a7, b71690c40). The invariant is per-site, so state it
    that way: EVERY site that mutates bytes in place must forget the answer.
    The current list is `grep PXXStrForgetAscii` plus the two hand-emitted
    x86-64 paths in ir_codegen.inc — the AnsiStrUniqueAddr blob, and the
    in-place SetLength resize that clears both bits itself. Run the grep; do not
    trust a count in a comment, this one's included.

    A note on the clause that also used to stand here, because it is the subtler
    trap: "PXXStrSetLen needs no such call: it always allocates a fresh block."
    That is TRUE of this Pascal routine — every non-collapsing path really does
    PXXAlloc + PXXHdrInit — and it was still the premise of a real bug, because
    x86-64 does not CALL PXXStrSetLen: it inlines the symbol-target resize, and
    that inline has an in-place arm (df19c72a7). A reader who checked the claim
    against PXXStrSetLen confirmed it and stopped. **The thing that gets checked
    was not the thing that was load-bearing** — so when a comment justifies an
    invariant by naming a routine, check the OPERATION's other implementations,
    not the routine.
    bug-a-the-comment-that-caused-three-bugs-survived-all-three-fixes }
  rc := PWord(oldHandle - 16)^;
  if rc <= 1 then
  begin
    PXXStrForgetAscii(Pointer(oldHandle));
    Result := Pointer(oldHandle);
    Exit;
  end;
  len := PWord(oldHandle - 8)^;
  newHandle := Int64(PXXStrFromLit(len, Pointer(oldHandle)));
  PWord(slotAddr)^ := newHandle;
  PXXStrDecRef(Pointer(oldHandle));
  PXXStrForgetAscii(Pointer(newHandle));
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

{ Three-way LEXICOGRAPHIC ordering for the cross targets' compare codegen —
  the `<` `<=` `>` `>=` counterpart of PXXStrEq above, same pre-decomposed
  (length, data) operand shape so managed handles and inline strings share it.
  Returns -1, 0 or +1.

  It exists because the cross backends that do not call it have NO
  ordered-string arm at all: only `=` / `<>` were special-cased, so `a < b`
  fell through to the ordinary integer compare and compared the two heap
  HANDLES — a silent wrong answer, `'zzz' < 'aaa'` reported by allocation
  order.
  bug-a-ordered-string-comparison-of-a-parameter-compares-handles-on-every-cross-target

  THE COUNT USED TO BE IN THIS SENTENCE AND THE COUNT WAS WRONG. It said "the
  four cross backends", meaning i386, arm32, aarch64 and riscv32 — and there
  were five. **Xtensa was never visited**, kept the bug for months, and was
  found only once a hosted xtensa profile could run a program and print the
  wrong answer. The count is deliberately gone rather than corrected to five:
  a number in a comment is a claim that goes stale silently, and the next
  target to land would have made "five" wrong the same way. Say which backends
  by the property that matters — whether they call this helper — so the
  sentence stays true as the set changes.
  bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle

  Bytes are compared UNSIGNED (x86-64's inline sequence uses repe cmpsb + the
  unsigned setcc family), and the shorter string sorts first when one is a
  prefix of the other. A nil handle arrives here as len 0, which is what makes
  '' the least element without a special case. }
function PXXStrCmp3(lenA: NativeInt; srcA: Pointer; lenB: NativeInt; srcB: Pointer): Int64;
var i, n, a, b, ca, cb: Int64;
begin
  n := lenA;
  if lenB < n then n := lenB;
  a := Int64(srcA);
  b := Int64(srcB);
  i := 0;
  while i < n do
  begin
    ca := PByte(a + i)^;
    cb := PByte(b + i)^;
    if ca <> cb then
    begin
      if ca < cb then Result := -1 else Result := 1;
      Exit;
    end;
    i := i + 1;
  end;
  if lenA < lenB then Result := -1
  else if lenA > lenB then Result := 1
  else Result := 0;
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
{$ifdef PXX_HEAP_DEBUG}
  { Same stale-handle check as PXXStrDecRef's. RAW arithmetic for the size word:
    PXXHdrBase Halt(204)s on a poisoned kind byte, which is this input exactly. }
  if PXXDbgIsPoisonWord(PWord(rcAddr)^) then
  begin
    HeapDbgPend := 11;
    HeapDbgAddr := Int64(p);
    HeapDbgSize := PWord(Int64(p) - PXX_HDR_SIZE - 8)^;
    PXXDbgGrabStack(Int64(@rcAddr));
    PXXDbgFlush;
    Exit;
  end;
{$endif}
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
{$ifdef PXX_HEAP_DEBUG}
  { Same stale-handle check as PXXStrDecRef's. RAW arithmetic for the size word:
    PXXHdrBase Halt(204)s on a poisoned kind byte, which is this input exactly. }
  if PXXDbgIsPoisonWord(PWord(rcAddr)^) then
  begin
    HeapDbgPend := 10;
    HeapDbgAddr := Int64(arrData);
    HeapDbgSize := PWord(Int64(arrData) - PXX_HDR_SIZE - 8)^;
    PXXDbgGrabStack(Int64(@rcAddr));
    PXXDbgFlush;
    Exit;
  end;
{$endif}
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
{$ifndef PXX_TS_HARDLOCK}
            { The record element's interface members. Skipped on x86-64
              --threadsafe: several callers of this walk (IR_SETLEN_DYN,
              IR_DYNUNIQUE) hold the codegen spinlock, and _Release re-enters it
              through FreeMem — the identical residual, for the identical
              reason, that ManagedElemKindLocked already keeps for kind-4
              ELEMENTS. Leak, not hang.
              bug-a-array-of-records-with-interface-fields-leaks-the-interfaces }
            PXXRecordReleaseIntf(itemAddr, baseRecDesc);
{$endif}
            PXXRecordRelease(itemAddr, baseRecDesc);
            i := i + 1;
          end;
        end;
      end
      else if baseKind = 4 then
      begin
        { COM interface elements: _Release each slot. Nil-safe per element, so a
          partly-filled array is fine, and UNLOCKED — _Release runs Destroy and
          the self-locking FreeMem, so no heap lock may be held here. Every
          caller of this walk is already outside the lock (scope-exit cleanup
          and PXXDynSetLen both call it unwrapped), which is what let the array
          family be fixed without the record/class lock-strategy decision. }
        i := 0;
        while i < len do
        begin
          itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
          PXXIntfRelease(itemAddr, Int64(baseRecDesc));
          i := i + 1;
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
          { A record ELEMENT's own COM interface members: the same split the
            scalar record copy uses. AddRef frees nothing, so the retain half
            needs no lock guard.
            bug-a-array-of-records-with-interface-fields-leaks-the-interfaces }
          PXXRecordRetainIntf(itemAddr, baseRecDesc);
          PXXRecordRetain(itemAddr, baseRecDesc);
          i := i + 1;
        end;
      end;
    end
    else if baseKind = 4 then
    begin
      { COM interface elements: _AddRef each slot. This is the half that makes
        SetLength SHRINK release exactly the dropped tail — the survivors are
        retained here, then the whole old array is released, so the net effect
        on an element that survived is zero and on a dropped one is one release. }
      i := 0;
      while i < len do
      begin
        itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
        PXXIntfAddRef(itemAddr, Int64(baseRecDesc));
        i := i + 1;
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
  baseKind: 1 = AnsiString, 3 = record (walked via desc), 4 = COM interface
  (baseRecDesc carries the interface id, not a pointer). }
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
{$ifndef PXX_TS_HARDLOCK}
        { The record element's interface members — see PXXDynArrayReleaseDepth
          for why this one arm is gated on x86-64 --threadsafe. }
        PXXRecordReleaseIntf(itemAddr, baseRecDesc);
{$endif}
        PXXRecordRelease(itemAddr, baseRecDesc);
        i := i + 1;
      end;
    end;
  end
  else if baseKind = 4 then
  begin
    { COM interface elements — the STATIC-array case: `keep: array[0..N] of IFoo`
      at scope exit, and the destination side of a whole-array assignment. }
    i := 0;
    while i < len do
    begin
      itemAddr := Pointer(Int64(arrData) + i * SizeOf(Pointer));
      PXXIntfRelease(itemAddr, Int64(baseRecDesc));
      i := i + 1;
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

procedure PXXRecordRetainIntf(recAddr: Pointer; desc: Pointer);
{ Kind-4 (COM interface) members only, recursing through kind-3 sub-records so a
  record holding a record holding an interface is counted once per copy. Runs
  UNLOCKED — see the interface declaration. AddRef cannot free anything, so this
  half is harmless in any order; it is split out to mirror the release side. }
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
    if kind = 4 then
      PXXIntfAddRef(memberAddr, typeRef)
    else if kind = 3 then
    begin
      subDesc := Pointer(memberPtr + 12 + typeRef);
      memberSize := PInt32(Int64(subDesc) + 4)^;
      j := 0;
      while j < arrayCount do
      begin
        itemAddr := Pointer(Int64(memberAddr) + j * memberSize);
        PXXRecordRetainIntf(itemAddr, subDesc);
        j := j + 1;
      end;
    end;
    memberPtr := memberPtr + 16;
    i := i + 1;
  end;
end;

procedure PXXRecordReleaseIntf(recAddr: Pointer; desc: Pointer);
{ The release half. Deliberately does NOT nil the slot: the copy path calls this
  on the DESTINATION before the bulk copy, and for `a := a` the source is the
  same memory — zeroing here would copy a nil over a live value. The caller
  either overwrites the slot (copy) or is discarding the storage (scope exit). }
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
    if kind = 4 then
      PXXIntfRelease(memberAddr, typeRef)
    else if kind = 3 then
    begin
      subDesc := Pointer(memberPtr + 12 + typeRef);
      memberSize := PInt32(Int64(subDesc) + 4)^;
      j := 0;
      while j < arrayCount do
      begin
        itemAddr := Pointer(Int64(memberAddr) + j * memberSize);
        PXXRecordReleaseIntf(itemAddr, subDesc);
        j := j + 1;
      end;
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

procedure __pxxTObjectDestroy(Inst: Pointer);
{ See the interface comment: TObject.Destroy's default body is empty. The
  managed-field sweep is NOT done here — PXXClassFinalize is injected by the
  Free desugar after the whole Destroy chain has run, which is FPC's
  FreeInstance timing. }
begin
end;

procedure PXXClassFinalizeManaged(inst: Pointer);
{ The kinds-1/2/3/5/6 half of PXXClassFinalize — string, dynarray, record,
  variant and NilPy-object fields — split out because it is the half whose LOCK
  DISCIPLINE differs from the kind-4 (COM interface) half above it, and the two
  therefore cannot share a caller on every target.

  Nothing here runs user code: the whole subtree is PXXStrDecRef,
  PXXDynArrayRelease, PXXRecordRelease, PXXVarClear and PXXObjRelease, all
  runtime, none of them taking a lock of its own on x86-64. That is what makes
  it safe to call with the heap lock ALREADY HELD, which is how the x86-64
  --threadsafe path reaches it: the lock there is the codegen BSS spinlock,
  unreachable from Pascal, so the acquire is emitted at the CALL SITE
  (ir_codegen.inc, HeapLockedCallProcIdx) rather than taken here.

  The kind-4 half must NOT be under the lock — it runs the referenced object's
  destructor chain and a self-locking FreeMem — which is the whole reason for
  the split. It stays in PXXClassFinalize, unlocked, exactly as before.

  It re-derives the descriptor from [inst] rather than taking it as a parameter
  because the emitted call site has only the instance pointer. Two loads.
  bug-a-threadsafe-on-x86-64-leaks-every-managed-class-field-and-it-is-not-benign }
var
  vmt, desc: Pointer;
begin
  if inst = nil then Exit;
  vmt := Pointer(PWord(inst)^);
  if vmt = nil then Exit;
  desc := Pointer(PWord(Pointer(Int64(vmt) - 16))^);
  if desc = nil then Exit;
  PXXRecordRelease(inst, desc);
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
  - kinds 1-3 (string/dynarray/record): PXXClassFinalizeManaged, whose inner
    frees are self-locking on softlock targets and lock-free single-threaded. On
    x86-64 --threadsafe the heap lock is the codegen BSS spinlock, unreachable
    from Pascal, so it is NOT reached from here — the Free desugar emits it as
    a SECOND call, under the emitted lock, instead (ir.inc; and see that proc's
    own comment). PXXRecordRelease has no kind-4 case, so interfaces are not
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
  PXXClassFinalizeManaged(inst);
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
  else if baseKind = 4 then
    { Kind 4 = COM INTERFACE elements. There is no sub-descriptor to point at,
      so the descriptor's typeRef word carries the INTERFACE ID instead — the
      same discriminated slot a CLASS layout descriptor already uses for its
      kind-4 members (rtti_emit.inc). It rides here in the baseRecDesc argument
      so the four element-walk helpers keep the arity every backend's codegen
      already emits.
      NEVER nil-guard a kind-4 arm on baseRecDesc: interface id 0 is a real id
      and would nil-check as "no descriptor". The kind-3 arms guard, kind 4
      must not. }
    baseRecDesc := Pointer(baseTypeRef)
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

  { The copy-on-write duplicate — every write to a shared dyn array lands here.
    feature-opt-bulk-copy-is-byte-at-a-time }
  PXXBlockCopy(Int64(newArrData), Int64(arrData), len * elSize);

  depth := PInt32(Int64(desc) + 8)^;
  baseKind := PInt32(Int64(desc) + 12)^;
  baseTypeRef := PInt32(Int64(desc) + 16)^;
  if baseKind = 3 then
    baseRecDesc := Pointer(Int64(desc) + 16 + baseTypeRef)
  else if baseKind = 4 then
    baseRecDesc := Pointer(baseTypeRef)   { interface id, see PXXDynArrayRelease }
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
{$ifdef CPUX86_64}
var bmR: Int64;
{$endif}
begin
{$ifdef CPUX86_64}
  bmR := __pxxblockmove(Int64(dst), Int64(src), n);   { rep movsb }
{$else}
  PXXBlockCopy(Int64(dst), Int64(src), n);   { the ASCII answer is not wanted here }
{$endif}
end;

{ Zero n bytes at dst. }
procedure PXXMemZero(dst: Pointer; n: NativeInt);
var d, i, w: Int64;
{$ifdef CPUX86_64}
    bmR: Int64;
{$endif}
begin
  d := Int64(dst);
{$ifdef CPUX86_64}
  { `rep stosb` pays a fixed microcode startup of tens of cycles before it moves
    a byte, so a SHORT span never earns it back -- the word loop below beats it
    outright until the span is long enough to amortise the start. Measured on
    `b := nil; SetLength(b, N)`, 3M iterations, rep-always against this
    threshold: 8B 0.88x, 32B 0.91x (i.e. rep-always was SLOWER), 256B 1.69x,
    2048B 4.59x. The dispatch lives HERE, in the one routine, rather than in
    each caller -- PXXAlloc's reuse paths used to hand-roll their own word loop
    for exactly this reason and thereby missed the large-span win entirely. }
  if n > MEMZERO_REP_MIN then
  begin
    bmR := __pxxblockfill(d, n, 0);   { rep stosb; a count <= 0 writes nothing }
    Exit;
  end;
{$endif}
  i := 0;
  w := SizeOf(NativeInt);
  { same alignment rule as PXXBlockCopy, with no source to agree with }
  if (n >= w) and ((d and (w - 1)) = 0) then
    while i + w <= n do
    begin
      PWord(d + i)^ := 0;
      i := i + w;
    end;
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
  else if baseKind = 4 then
    baseRecDesc := Pointer(baseTypeRef)   { interface id, see PXXDynArrayRelease }
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

  { PXXMemZero / PXXBlockCopy, not a byte loop. Both are defined above and both
    already move a machine word at a time (PXXMemZero is `rep stosb` on x86-64),
    so this is one call replacing a loop, not a new primitive.

    The old loops were worse than "one byte per iteration": each recomputed
    `newLen * elSize` in its own condition, so every byte cost a multiply as well
    as a load, a store and a compare. This is on the `Copy(arr)` path -- Copy
    lowers to SetLength-then-PXXMemCopy, so the zero-fill here ran byte-by-byte
    immediately before a `rep movsb` overwrote every byte of it.
    feature-opt-bulk-copy-is-byte-at-a-time }
  PXXMemZero(newArrData, newLen * elSize);

  if oldData <> nil then
  begin
    oldLen := PWord(Int64(oldData) - 8)^;
    copyLen := oldLen;
    if newLen < copyLen then copyLen := newLen;
    PXXBlockCopy(Int64(newArrData), Int64(oldData), copyLen * elSize);
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

{$ifdef PXX_NILPY_STR}
  { see PXXStrFromLit: NilPy zero-length strings do not collapse to nil. }
  if newLen < 0 then
{$else}
  if newLen <= 0 then
{$endif}
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
    { SetLength(s, n) on a string, on every target — the site this ticket's
      original list missed entirely, and plausibly the hottest of them.
      feature-opt-bulk-copy-is-byte-at-a-time }
    PXXBlockCopy(Int64(newData), Int64(oldData), copyLen);
  end;

  if newLen > copyLen then
    PXXMemZero(Pointer(Int64(newData) + copyLen), newLen - copyLen);
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
begin
  { One forward block copy in this unit, not two: on x86-64 that is the
    machine's own, and everywhere else PXXBlockCopy already moves a word at a
    time with a byte tail. PXXBlockCopy's return value is the ASCII scan the
    string paths ask for; nothing here wants it. }
{$ifdef CPUX86_64}
  Result := Pointer(__pxxblockmove(Int64(dest), Int64(src), n));
{$else}
  PXXBlockCopy(Int64(dest), Int64(src), n);
  Result := dest;
{$endif}
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

{ Fill the fresh destination for FPC's array-SPLICE Insert(srcArr, arr, index):
  head [0..pos) from the old buffer, then EVERY element of insData, then the
  tail [pos..len). pos = index clamped to [0..len], same as the one-element
  form. Returns destData -- there is no gap address to hand back, because the
  inserted elements are already in place when this returns; the caller's
  element retain then covers them along with the kept ones. }
function PXXDynInsArrFill(destData: Pointer; srcData: Pointer; insData: Pointer;
                          index: NativeInt; elemSize: NativeInt): Pointer;
var len, insLen, headB, insB, tailB: Int64; dummy: Pointer;
begin
  len := PXXDynLen(srcData);
  insLen := PXXDynLen(insData);
  if index < 0 then index := 0;
  if index > len then index := len;
  headB := index * elemSize;
  insB := insLen * elemSize;
  tailB := (len - index) * elemSize;
  if headB > 0 then dummy := PXXMemCopy(destData, srcData, headB);
  if insB > 0 then
    dummy := PXXMemCopy(Pointer(Int64(destData) + headB), insData, insB);
  if tailB > 0 then
    dummy := PXXMemCopy(Pointer(Int64(destData) + headB + insB),
                        Pointer(Int64(srcData) + headB), tailB);
  Result := destData;
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

type
  TPXXVariantErrorProc = procedure(const msg: AnsiString);
var
  { Installed by sysutils' initialization to turn a failed Variant conversion
    into a raised, catchable EVariantError — the same hook design as
    PXXDivZeroHook, for the same reason: the conversion helpers live in the
    builtin units, which have no exception class to raise, while the unit that
    HAS one cannot be assumed present. Default nil = print-and-halt, which is
    what every one of those sites did unconditionally before. }
  PXXVariantErrorHook: TPXXVariantErrorProc;

{ The one exit for "this Variant conversion cannot be done". Eight sites in
  builtin.pas each did `writeln(...); Halt(219)` inline, so a program doing the
  ordinary `try i := v; except on E: Exception do ... end` DIED instead of
  taking its handler — FPC catches it there, and the whole point of that try is
  that the text may not be numeric.

  msg is the text AFTER "EVariantError, " so both paths can shape it: the hook
  raises it as the exception message, and the fallback prints the line the
  sites used to print themselves. Never returns when a hook is installed —
  the raise leaves through the exception machinery. }
procedure PXXVariantError(const msg: AnsiString);
begin
  if PXXVariantErrorHook <> nil then PXXVariantErrorHook(msg);
  writeln('Runtime error: EVariantError, ', msg);
  Halt(219);
end;

var
  { Installed by sysutils' initialization to convert a FAILED `as` DOWNCAST into
    a raised, catchable EInvalidCast — same design as PXXDivZeroHook above.
    Default nil = print-and-halt below.

    The `as` trap used to be a bare Halt(1) emitted inline by the AN_AS_CAST
    lowering: no message, no exit code anyone could read, and — unlike every
    other checked operation in this family — nothing a `try ... except` could
    intercept. A failed safe downcast is the one shape `as` exists FOR, so the
    program that wrote the handler was the program that died silently.
    bug-a-a-failed-as-downcast-dies-silently-and-uncatchably }
  PXXInvalidCastHook: TPXXDivZeroProc;

{ Failed `as` downcast: the instance is not of the requested class. FPC raises
  EInvalidCast (Runtime error 219 without sysutils). Never returns unless a
  hook raises past it. }
procedure PXXInvalidCast;
begin
  if PXXInvalidCastHook <> nil then PXXInvalidCastHook();
  writeln('Runtime error 219 (invalid typecast)');
  Halt(219);
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

var
  { 5th of the family: installed by sysutils' initialization to turn a nil
    dereference CAUGHT AT THE CALL SITE into a catchable EAccessViolation.
    feature-a-emitted-nil-checks }
  PXXNilRefHook: TPXXDivZeroProc;

{ Nil-reference trap. 216 is FPC's code for a memory fault, and it is what
  --fpc-mem-errors reports for a real SIGSEGV, so the emitted check and the
  signal path agree on the number a program exits with — the difference is that
  this one fires BEFORE the fault, from ordinary call context, so a hook can
  raise past it and `try..except` runs.

  A hook slot rather than a hardwired writeln+Halt, and that is not decoration:
  on an MCU halting is usually wrong, and printing is usually fine but NOT
  always — a program driving a protocol-sensitive serial link has to be able to
  say "not on my UART". Default nil keeps FPC-without-sysutils behaviour. }
procedure PXXExitProcess;
begin
  Halt(ExitCode);
end;

procedure PXXNilRef;
begin
  if PXXNilRefHook <> nil then PXXNilRefHook();
  writeln('Runtime error 216 (nil reference)');
  Halt(216);
end;

{ NOTE there is no PXXNilChkPtr guard FUNCTION, and there was for one commit.
  Wrapping the pointer in a call — the shape PXXRangeChkI64 uses, and much the
  nicer code — costs a call on every checked site, which on a loop of 60M method
  calls measured 0.44s -> 0.65s. `inline` does not rescue it: inline v1 retains
  only single-expression bodies with no call in them, and the call is this body's
  entire purpose. So the compare and branch are built as IR at the call site
  (IRWrapNilChk in ir.inc) and only the cold arm lands here — 0.42s -> 0.43s.
  feature-a-emitted-nil-checks }

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

{ The bitwise operator set, named once. tkAnd = 30, tkOr = 31, tkShl = 103,
  tkXor = 117, tkShr = 119 — the TTokenKind ordinals from defs.inc, which the
  runtime cannot see.

  1119 is not a token: it is the out-of-band opcode PXXVarBinOpPas substitutes
  for tkShr, spelling "shift right, LOGICALLY". The runtime cannot see
  PyProgramMode, so the language split is made by the CALLER — Pascal enters
  through PXXVarBinOpPas and rewrites the opcode, NilPy enters PXXVarBinOp
  directly and keeps 119. Same seam, same reason, as the string rule that
  wrapper already carries. }
function VarOpIsBitwise(opTk: NativeInt): Boolean;
begin
  VarOpIsBitwise := (opTk = 30) or (opTk = 31) or (opTk = 103) or
                    (opTk = 117) or (opTk = 119) or (opTk = 1119);
end;

{ Apply one of them to two already-integral operands. Kept apart from its two
  call sites so the INTEGER arm and the FLOAT arm of PXXVarBinOp cannot drift
  the way this function and x86-64's EmitVarBinOp did.
  119 (`shr`) is ARITHMETIC (sign-extending), matching the `sar` x86-64 emits
  for NilPy and Python's `>>`; 1119 is LOGICAL, which is what Pascal's own
  `shr` does on a static Integer or Int64, so a Variant answers the same. FPC's
  Variant `shr` is a third thing — it narrows to 32 bits first, so
  `v(-12) shr 1` is 2147483642 there — and that narrowing is a behaviour we do
  not copy (decide-variant-bitwise-width, decided 2026-08-25, option 2).
  All of them agree on non-negative operands.
  bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical }
function VarBitwiseInt(lVal, rVal: Int64; opTk: NativeInt): Int64;
var r: Int64;
begin
  if opTk = 30 then r := lVal and rVal
  else if opTk = 31 then r := lVal or rVal
  else if opTk = 117 then r := lVal xor rVal
  else if opTk = 103 then r := lVal shl rVal
  else if opTk = 1119 then r := lVal shr rVal             { Pascal: logical shr }
  else if lVal < 0 then r := not ((not lVal) shr rVal)    { NilPy: arithmetic shr }
  else r := lVal shr rVal;
  VarBitwiseInt := r;
end;

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

  { 2. Numeric path.
    Re-read both payloads as the full 8 bytes of the slot. The reads at the top
    of this function go through PWord, which is pointer-sized — exactly right
    for the string arms above, where the payload IS a handle, and exactly wrong
    here: on a 32-bit target it takes 4 bytes, so -2 arrives as 4294967294 and
    every negative operand or result comes back zero-extended. The double arm
    already knew this (it reads through PDouble); the integer arm did not. }
  lVal := PInt64(Int64(left) + 8)^;
  rVal := PInt64(Int64(right) + 8)^;

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
    else if (opTk = 33) or (opTk = 34) or VarOpIsBitwise(opTk) then
    begin
      if VarOpIsBitwise(opTk) then
      begin
        { A BITWISE op with a float operand: FPC ROUNDS it to an integer first
          — `v(1.5) and v(10)` is 2, not the 0 that truncating gives. Same
          Round-not-Trunc rule VariantToInt64 already follows. div/mod below
          keep Pascal's truncation, which is a different operator rather than
          an inconsistency. }
        lVal := Round(lDbl);
        rVal := Round(rDbl);
        resVal := VarBitwiseInt(lVal, rVal, opTk);
      end
      else
      begin
        lVal := Trunc(lDbl);
        rVal := Trunc(rDbl);
        { The same pre-divide check an ordinary integer divide gets. Without it a
          variant `1 div 0` answered GARBAGE here (-1 on i386/arm32, 0 on aarch64
          -- whatever the target's divide instruction does with a zero divisor)
          while the identical program on plain Integers raised EDivByZero. FPC
          raises for both. bug-a-a-variant-div-by-zero-sigfpes-or-answers-garbage }
        if rVal = 0 then PXXDivZero;
        if opTk = 33 then resVal := lVal div rVal else resVal := lVal mod rVal;
      end;
      if PWord(dest)^ = 6 then
        PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
      PWord(dest)^ := 1;
      PInt64(Int64(dest) + 8)^ := resVal;   { full 8 bytes — see the note above }
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
      { Pre-divide check -- see the note in the double arm above. }
      if ((opTk = 33) or (opTk = 34)) and (rVal = 0) then PXXDivZero;
      if opTk = 70 then resVal := lVal + rVal
      else if opTk = 71 then resVal := lVal - rVal
      else if opTk = 72 then resVal := lVal * rVal
      else if opTk = 33 then resVal := lVal div rVal
      else if opTk = 34 then resVal := lVal mod rVal
      { The BITWISE ops. x86-64's inline EmitVarBinOp has had them for as long
        as NilPy has needed machine-word masking; this function — the dispatch
        every OTHER target uses — did not, so the if-chain ran off its end and
        stored whatever resVal happened to hold. `v(12) and v(10)` answered
        -524095488 on i386, 4358436 on aarch64 and 1082138624 on arm32, for the
        source that gives 8 on x86-64 and under FPC. One concept, two
        implementations, and only one of them was ever finished.
        bug-a-not-on-an-integer-variant-answers-a-boolean }
      else if VarOpIsBitwise(opTk) then resVal := VarBitwiseInt(lVal, rVal, opTk)
      else
      begin
        { and no silent fall-through ever again: an operator this function does
          not implement now SAYS so rather than returning the stack. }
        PXXVariantError('unsupported operator on a Variant');
        resVal := 0;
      end;

      if PWord(dest)^ = 6 then
        PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
      PWord(dest)^ := 1;
      PInt64(Int64(dest) + 8)^ := resVal;   { full 8 bytes — see the note above }
      Result := Int64(dest);
      Exit;
    end;
  end;
end;

{ Pascal's UNARY `not` on a Variant. Bitwise on an integer, logical on a
  Boolean — Pascal picks between the two from the operand's type, and on a
  Variant only the runtime TAG knows it. FPC dispatches exactly this way:
  `not v` is -13 for v=12 and False for v=True.

  Before this, `not v` was lowered as Python TRUTHINESS for every tag, so
  `not v` with v=12 answered False. Wrong twice over — the VALUE, and the
  result's TYPE, so `mask := not flags` handed a Boolean to everything
  downstream and nothing afterwards mentioned `not`. The Boolean rows agreeing
  is what hid it. NilPy keeps the truthiness lowering (Python's `not 12` IS
  False) and never calls this.
  bug-a-not-on-an-integer-variant-answers-a-boolean }
function PXXVarNot(dest: Pointer; src: Pointer): Int64;
var tag, v: Int64;
begin
  tag := PWord(src)^;
  { the destination may be a reused temp still holding a string handle }
  if PWord(dest)^ = 6 then
    PXXStrDecRef(Pointer(PWord(Int64(dest) + 8)^));
  if tag = 4 then                       { VT_BOOL }
  begin
    v := PInt64(Int64(src) + 8)^;
    PWord(dest)^ := 4;
    PInt64(Int64(dest) + 8)^ := Int64(v = 0);
  end
  else if (tag = 1) or (tag = 2) then   { VT_INT, VT_INT64 }
  begin
    v := PInt64(Int64(src) + 8)^;
    PWord(dest)^ := 1;
    PInt64(Int64(dest) + 8)^ := not v;
  end
  else if tag = 3 then                  { VT_DOUBLE }
  begin
    { round, then complement: FPC's `not v(1.5)` is -3, not -2. Same
      Round-not-Trunc rule as the bitwise binops above. Written directly now
      that `not Round(..)` is bitwise -- the local this used to round through
      was a workaround for
      bug-p-not-of-a-builtin-round-or-trunc-call-is-logical, since fixed. }
    PWord(dest)^ := 1;
    PInt64(Int64(dest) + 8)^ := not Round(PDouble(Int64(src) + 8)^);
  end
  else if tag = 0 then                  { VT_EMPTY / Null propagates }
  begin
    PWord(dest)^ := 0;
    PInt64(Int64(dest) + 8)^ := 0;
  end
  else
    PXXVariantError('`not` needs an ordinal Variant');
  Result := Int64(dest);
end;

{ `v := v + x` on a VARIANT slot, appended in place. Returns 1 when it handled
  the operation and 0 when the caller must fall back to the general
  PXXVarBinOp path.

  This is the variant twin of PXXStrAppend, and it is the one that matters for
  Nil-Python: a loop-carried `s` infers tyVariant, not tyAnsiString, so the
  typed-store append never sees it and every `s = s + c` went through
  PXXVarBinOp -> PXXStrConcat, allocating and copying the whole accumulation
  per iteration (bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-
  cpython, cause B — 62.5% of uforth's instructions).

  The payload word of a VT_STRING slot IS a managed handle slot, so appending
  into `dest + 8` is exactly the typed case with a tag word in front of it.

  Only string-into-string and char-into-string are taken; everything else —
  numbers, objects, an unset dest — answers 0 and keeps the general path, which
  stays the single definition of what `+` means on variants. }
function PXXVarStrAppend(dest: Pointer; right: Pointer): Int64;
var dTag, rTag: Int64; rp: Pointer; rLen: Int64;
begin
  Result := 0;
  if (dest = nil) or (right = nil) then Exit;
  dTag := PWord(dest)^;
  if dTag <> 6 then Exit;                        { VT_STRING }
  rTag := PWord(right)^;
  if rTag = 6 then
  begin
    rp := Pointer(PWord(Int64(right) + 8)^);
    if rp = nil then begin Result := 1; Exit; end;   { appending '' }
    rLen := PWord(Int64(rp) - 8)^;
  end
  else if rTag = 5 then                          { VT_CHAR: the byte is the
                                                   low end of the payload word }
  begin
    rp := Pointer(Int64(right) + 8);
    rLen := 1;
  end
  else Exit;
  PXXStrAppend(Pointer(Int64(dest) + 8), rp, rLen);
  Result := 1;
end;

procedure PXXVarClear(v: Pointer);
{ Release a string payload and zero the 16-byte slot (both words fully, so
  32-bit targets leave no stale high halves behind). Object payloads ride
  PXXObjRelease, whose PXX_OBJ_MAGIC guard makes it a no-op on manual-lifetime
  Pascal instances. A promo-block tag rides in a variant as a managed
  AnsiString of its decimal — same release as VT_STRING (this portable body
  once missed that, a cross-target leak).

  This is the PORTABLE half of a pair: x86-64 emits the same test inline
  (EmitVariantClear, compiler/ir_codegen.inc) and every other target calls
  here. So the two must agree, and they agree by both reading a RANGE whose
  bounds are two named numbers rather than a list of tags.

  What the old shape cost, since it is the reason for the range: the list used
  to be spelled out in four places, and a tag added to the emitters but not
  here does not fail loudly — the slot is simply never released and the only
  symptom is RSS. Tag 10 was missed here exactly that way, which is what made
  an ESCAPING closure keep leaking after the object itself had been given a
  refcount: the caller's hidden-destination temp for a variant-returning call
  is re-prepared through this routine once per loop iteration
  (bug-nilpy-bound-fn-closure-objects-are-never-freed,
  refactor-a-variant-object-tag-list-lives-in-four-places). }
begin
  PXXVarReleasePayload(v);
  PXXMemZero(v, 16);
end;

procedure PXXVarReleasePayload(v: Pointer);
{ PXXVarClear WITHOUT the zeroing — release the managed payload and leave the
  16 slot bytes alone.

  This is the half a variant-to-variant ASSIGNMENT wants, and calling the full
  PXXVarClear there was a real bug: the emitters do

      PXXVarRetain(src); PXXVarClear(dest); copy 16 bytes src -> dest

  and the retain-before-release makes the ALIASED case safe for the payload's
  REFCOUNT — which is what the comment at every one of those sites claimed was
  the whole story. It is not: when src and dest are the same slot, PXXMemZero
  wipes the bytes the copy is about to read, so `v := v` copied sixteen zeroes
  over itself and the variant came back Empty, on every target, where FPC leaves
  the value. It leaked too: the retain took the payload to +2, the release put
  it back to +1, and then nothing referenced it.

  Splitting the routine rather than branching on `src = dest` in six emitters:
  the zeroing was never wanted on this path in the FIRST place — the bytes are
  overwritten by the copy on the very next instruction — so removing it is the
  fix and a self-assignment then falls out as the degenerate case (retain +1,
  release -1, copy a slot onto itself) with no test to get wrong and no branch
  in the hot path. bug-a-a-variant-assigned-to-itself-becomes-empty }
begin
  if (PWord(v)^ = VT_STRING_TAG) or
     ((PWord(v)^ >= VT_PROMO_FIRST) and (PWord(v)^ <= VT_PROMO_LAST)) then
    PXXStrDecRef(Pointer(PWord(Int64(v) + 8)^))
  else if (PWord(v)^ >= VT_OBJ_FIRST) and (PWord(v)^ <= VT_OBJ_LAST) then
    PXXObjRelease(Pointer(PWord(Int64(v) + 8)^));
end;

procedure PXXVarRetain(v: Pointer);
{ The exact mirror of PXXVarClear — see the note there. }
begin
  if (PWord(v)^ = VT_STRING_TAG) or
     ((PWord(v)^ >= VT_PROMO_FIRST) and (PWord(v)^ <= VT_PROMO_LAST)) then
    PXXStrIncRef(Pointer(PWord(Int64(v) + 8)^))
  else if (PWord(v)^ >= VT_OBJ_FIRST) and (PWord(v)^ <= VT_OBJ_LAST) then
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
function PxxFracDigits(pv: Pointer; decimals: NativeInt; emit: NativeInt): NativeInt; forward;

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
  integer, no point), right-justified in `width` columns.

  Both halves are now EXACT. The integer part expands in base-10^9 limbs
  (PXXWriteUIntD -> PxxIntDDigits) and the fraction likewise (PxxFracDigits):
  a double is mant * 2^exp2 with both parts integral, so its decimal form is
  finite and every digit of it is a real digit of the value. Nothing is scaled
  through a Double any more, which is what used to bound the answer at ~16
  fraction digits and then pad with zeros — 1/3 at :0:30 printed
  0.333333333333333312 and twelve zeros where the value continues
  ...314829616256247 (bug-a-write-fixed-fraction-digits-past-16-are-invented,
  and bug-a-write-fixed-emits-false-digits-past-1e22 for the integer half).

  x86-64's EmitWriteFloatFixed is a shim onto this routine, and i386 / arm32 /
  aarch64 / riscv32 all call it, so there is ONE implementation and a program's
  text cannot depend on which backend built it. }
var x, ip, r, two52, ipc: Double; i: Int64; neg: Boolean; ndig, total: Int64;
begin
  { NON-FINITE first — see PXXWriteFloatSci. A fixed-decimals request cannot be
    honoured for a value with no digits, so the spelling wins over the field
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
  { ip := trunc(x), by round-even-then-correct-down }
  if x >= two52 then
    ip := x
  else
  begin
    r := x + two52;
    r := r - two52;
    if r > x then r := r - 1;
    ip := r;
  end;
  { Ask the fraction whether ROUNDING carries into the integer, before printing
    anything: a carry changes both the integer digits and the column count
    (9.96:0:1 -> 10.0). decimals <= 0 asks for zero fraction digits, which makes
    this exactly "round the integer half-away-from-zero". }
  if decimals > 0 then
  begin
    if PxxFracDigits(@x, decimals, 0) <> 0 then ip := ip + 1;
  end
  else
    if PxxFracDigits(@x, 0, 0) <> 0 then ip := ip + 1;
  { FIELD WIDTH, counted after that rounding. ip is a non-negative integral
    Double here, possibly past 2^63, so the digit count is taken exactly rather
    than through Int64. bug-a-aarch64-float-field-width-ignored }
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
  PXXWriteUIntD(@ip);
  if decimals <= 0 then Exit;
  write('.');
  ndig := PxxFracDigits(@x, decimals, 1);
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

function PxxFracDigits(pv: Pointer; decimals: NativeInt; emit: NativeInt): NativeInt;
{ The EXACT fraction digits of a finite non-negative Double, `decimals` of them,
  rounded HALF-AWAY-FROM-ZERO at the cut. Returns 1 when that rounding carried
  into the INTEGER part (9.96 at :0:1 -> 10.0), else 0. With emit <> 0 the
  digits are written; with emit = 0 nothing is written and only the carry is
  computed, which is what lets the caller fix up the integer part and the field
  width before printing anything.

  A double is mant * 2^exp2 exactly, and 2^-k = 5^k * 10^-k, so for exp2 < 0 the
  value is the INTEGER mant*5^k with the point pushed k places left — a finite
  decimal, every digit of it real. exp2 >= 0 means the value is an integer and
  the fraction is genuinely all zeros.

  This replaces `(x - ip) * 10^d` scaling, which could only ever be right for
  about 16 digits: 1/3 at :0:30 printed ...333333312 where the double's exact
  tail is ...333333314829616256247, and 0.1 at :0:25 printed twenty-four zeros
  where the value has 55511151... The old routine called that padding "past what
  a double knows", which was the false premise — the expansion below is what it
  knows.
  bug-a-write-fixed-fraction-digits-past-16-are-invented }
const
  PXX_FRAC_MAX = 1080;      { a subnormal's fraction is 1074 digits; nothing is longer }
var
  buf: TPxxSciBuf;
  dig: array[0..PXX_FRAC_MAX] of Byte;
  n, i, k, topLen, idx, total, keep, j, d: Integer;
  mant, t, scale: Int64;
  exp2: Integer;
  roundUp: Boolean;
  ch: Char;
begin
  PxxFracDigits := 0;
  PxxSciSplit(PDouble(pv)^, mant, exp2);
  if (exp2 >= 0) or (mant = 0) then
  begin
    { an integral (or zero) value: the fraction is all zeros, exactly }
    if emit <> 0 then
      for i := 1 to decimals do write('0');
    Exit;
  end;
  k := -exp2;                        { value = mant / 2^k = mant*5^k / 10^k }
  for i := 0 to PXX_SCI_LIMBS - 1 do buf[i] := 0;
  buf[0] := mant mod PXX_SCI_BASE;
  buf[1] := mant div PXX_SCI_BASE;
  n := 2;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  i := k;
  while i >= 13 do begin PxxSciMul(buf, n, PXX_SCI_P5_13); i := i - 13; end;
  while i > 0 do begin PxxSciMul(buf, n, 5); i := i - 1; end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  topLen := 1; t := buf[n - 1];
  while t >= 10 do begin t := t div 10; topLen := topLen + 1; end;
  total := topLen + (n - 1) * 9;     { digits of mant*5^k; the low k are the fraction }

  { fraction digit j (1-based, just right of the point) is the digit at 0-based
    index k-j from the LOW end; j > k has none, and j > total means the value's
    leading fraction digits are zeros. }
  keep := decimals;
  if keep > k then keep := k;
  if keep > PXX_FRAC_MAX then keep := PXX_FRAC_MAX;
  for j := 1 to keep do
  begin
    idx := k - j;
    if idx >= total then d := 0
    else
    begin
      scale := 1;
      for i := 1 to (idx mod 9) do scale := scale * 10;
      d := Integer((buf[idx div 9] div scale) mod 10);
    end;
    dig[j] := Byte(d);
  end;

  { half-away-from-zero: the first DROPPED digit decides. >= 5 means the dropped
    tail is >= one half of the last kept place, and an exact 0.5 tie rounds away
    from zero — so the single digit answers both cases. }
  roundUp := False;
  j := keep + 1;
  if (j <= k) and (decimals >= keep) then
  begin
    idx := k - j;
    if idx < total then
    begin
      scale := 1;
      for i := 1 to (idx mod 9) do scale := scale * 10;
      if Integer((buf[idx div 9] div scale) mod 10) >= 5 then roundUp := True;
    end;
  end;
  if roundUp then
  begin
    j := keep;
    while j >= 1 do
    begin
      if dig[j] < 9 then begin dig[j] := dig[j] + 1; Break; end;
      dig[j] := 0;
      j := j - 1;
    end;
    if j = 0 then PxxFracDigits := 1;     { carried out of the fraction }
  end;

  if emit <> 0 then
  begin
    for j := 1 to keep do
    begin
      ch := Chr(48 + dig[j]);
      write(ch);
    end;
    for j := keep + 1 to decimals do write('0');   { the value really does end }
  end;
end;

procedure PXXWriteFloatSci(p: Pointer; fracdigits: NativeInt; expdigits: NativeInt);
{ Pascal scientific notation <' '|'-'>d.<frac digits>E<'+'|'-'><exp digits>.

  `fracdigits` = digits after the point (16 -> FPC's 17-significant-digit Double
  form); `expdigits` = 3 for Double, 2 for Single, matching FPC.

  Both were HARDCODED at 16/3 until 2026-08-19, which made every "format this
  differently" request unrepresentable and was one bug with two faces:
  `write(d:W)` could not narrow the mantissa to the field, and a Single could not
  ask for its own 10-significant-digit, 2-digit-exponent form. The sibling
  PXXWriteFloatFixed already took (decimals, width); this one took neither, and
  that asymmetry WAS the defect
  ([[compat-pascal-writeln-of-a-single-uses-double-width]],
  [[bug-b-write-of-a-real-ignores-the-field-width-without-decimals]]).

  The mantissa is extracted MSD-first into a 17-digit integer so each step only
  truncates a value in [0,10) — preserves ~17 accurate digits, unlike one
  (x*1e16) multiply which overflows the 53-bit mantissa. One guard digit rounds
  half-up. Includes the leading-space positive sign. }
var x: Double; e, d, k, keep, drop: Integer; m, divisor, rem, limit: Int64; ch: Char;
begin
  { Clamp before use. FPC's own minimum is ONE fractional digit and it overflows
    the field rather than dropping below that (write(d:8) prints ' 3.3E-001',
    nine characters into a field of eight), so a narrow width widens the output
    instead of truncating the number. }
  if fracdigits < 1 then fracdigits := 1;
  if fracdigits > 16 then fracdigits := 16;
  if expdigits < 2 then expdigits := 2;
  if expdigits > 3 then expdigits := 3;
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
    write('0.');
    for k := 1 to fracdigits do write('0');
    write('E+');
    for k := 1 to expdigits do write('0');
    Exit;
  end;
  { EXACT digits — see PxxSciDigits17. The normalise-by-repeated-division loop
    that used to live here was wrong from the 16th digit (one rounding per
    iteration, ~100 of them for 1e100) and for 1e200 produced the wrong
    EXPONENT. }
  PxxSciDigits17(x, m, e);
  { Round the 17-digit mantissa to the requested significant-digit count. Done
    on the INTEGER rather than by scaling x, for the same reason the extraction
    is MSD-first: a second float rounding would lose the digits this routine
    exists to preserve. }
  keep := fracdigits + 1;
  drop := 17 - keep;
  if drop > 0 then
  begin
    divisor := 1;
    for d := 1 to drop do divisor := divisor * 10;
    rem := m mod divisor;
    m := m div divisor;
    if rem >= (divisor div 2) then m := m + 1;
    { Half-up can carry out of the kept width (9.99 -> 10.0), which is one digit
      too many AND one exponent too low; both must move together or the value
      changes by a factor of ten. }
    limit := 1;
    for d := 1 to keep do limit := limit * 10;
    if m >= limit then
    begin
      m := m div 10;
      e := e + 1;
    end;
  end;
  for k := keep - 1 downto 0 do
  begin
    divisor := 1;
    for d := 1 to k do divisor := divisor * 10;
    ch := Chr(48 + ((m div divisor) mod 10));
    write(ch);
    if k = keep - 1 then write('.');
  end;
  write('E');
  if e < 0 then
  begin
    write('-');
    e := -e;
  end
  else
    write('+');
  divisor := 1;
  for d := 1 to expdigits - 1 do divisor := divisor * 10;
  while divisor > 0 do
  begin
    ch := Chr(48 + ((e div divisor) mod 10));
    write(ch);
    divisor := divisor div 10;
  end;
end;

procedure PXXWriteVariant(v: Pointer);
{ Tag-dispatched write of a 16-byte variant slot; the runtime twin of
  x86-64's inline EmitWriteVariant: bool as True/False, int/int64 as a signed
  integer, double natural, char raw, string payload bytes.

  Two arms x86-64 has and this does not, deliberately: it spells an EMPTY slot
  `None` and an OBJECT slot `<object>`, both Python renderings. FPC prints
  nothing for a cleared Variant and RAISES for Null, so copying those spellings
  here would propagate a contested rendering to three more targets — that
  question is [[bug-a-a-null-variant-renders-as-none-in-pascal]] and settles in
  one place for all targets once it is answered. Measured 2026-08-24 across
  bool / int / negative int / double / char / string: after the bool arm below,
  Boolean was the ONLY tag the two renderers disagreed about. }
var tag, iv, len, i, s: Int64; ch: Char;
begin
  tag := PWord(v)^;
  if tag = 4 then                              { VT_BOOL }
  begin
    { Not as an integer. `writeln(v)` with v a Boolean Variant printed True and
      False on x86-64 and 1 and 0 on i386, arm32 and aarch64 — same source,
      same program, output that depends on the target, and the 1/0 form is not
      what FPC prints either. The Python spelling is the same word, so one arm
      serves both frontends.
      bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64 }
    iv := PWord(Int64(v) + 8)^;
    if iv <> 0 then write('True') else write('False');
  end
  else if (tag = 1) or (tag = 2) then          { VT_INT / VT_INT64 }
  begin
    { PInt64, NOT PWord. The payload of BOTH integer tags is a full Int64 (see
      defs.inc: VT_INT is "payload = sign-extended Int64"), and PWord is a
      MACHINE word — four bytes on i386 and arm32. Reading it as PWord threw
      away the high half of every integer variant on those two targets, so
      `v := 3000000000; v := v * 2` wrote 1705032704 and `v(1) shl 40` wrote 0,
      while x86-64 and aarch64 — where a machine word happens to BE eight bytes
      — printed both correctly. Silent, target-dependent, and invisible until a
      variant carried a value that did not fit 32 bits. The other three PWord
      reads in this routine are right as they are: a tag, a Boolean's 0/1, and a
      string HANDLE really are machine words.
      bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical }
    iv := PInt64(Int64(v) + 8)^;
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
