{ SPDX-License-Identifier: Zlib }
unit builtin;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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

function StrInt(v: Int64; width: Integer): AnsiString;
function StrQWord(v: QWord; width: Integer): AnsiString;
{ One Char as a string, right-justified to `width`. The Text-file write
  lowering needs it: a Char must NOT go through StrInt (that prints the
  ORDINAL — 120 for 'x'), which is why the ordinal arm there excludes
  tyChar. bug-p-writeln-text-rejects-char }
function StrChar(c: Char; width: Integer): AnsiString;
{ A STRING right-justified to `width`, and a Boolean as FPC's TRUE/FALSE right-
  justified the same way. The two formatters the write lowering was missing:
  writing either with a field width to a TEXT FILE silently DROPPED the width
  (TextStrArg handed the string straight through), and with a VARIABLE width to
  stdout it was refused outright — while the literal-width stdout path, which
  formats inline in codegen, had always handled both.
  bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit }
function StrStrW(const s: AnsiString; width: Integer): AnsiString;
function StrBool(b: Boolean; width: Integer): AnsiString;

{ ---- InterLocked* : FPC declares these in the `system` unit --------------

  So FPC source that uses them carries NO `uses` line, and requiring one meant
  such code did not compile as-is. They live here, the system-unit analogue,
  rather than only in lib/rtl/palatomic.pas
  (bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc).

  `uses palatomic` keeps working: a user RTL unit shadows a builtin of the same
  name, which is the documented rule and is what lets a program override any
  builtin. So both spellings resolve and neither is a duplicate definition.

  RETURN-VALUE CONTRACT, straight from palatomic and verified against FPC:
  Increment/Decrement return the value AFTER the operation, Exchange /
  ExchangeAdd / CompareExchange return the value BEFORE it. Every intrinsic
  returns the OLD value, so only the first two adjust.

  Excluded where the BACKEND cannot lower an atomic: riscv32 and xtensa have no
  IR_ATOMIC arm (x86-64 / i386 / arm32 / aarch64 do). The guard is on the CPU,
  not on PXX_ESP: gating on the ESP platform alone left plain `--target=riscv32`
  exposed, and because these bodies live in the builtin unit that EVERY program
  pulls, the failure was not "InterLocked is missing" but `unsupported node in
  IR codegen: atomic` on programs that never mention it — 15 riscv32 jobs that
  had nothing to do with atomics. Lifting the guard is
  bug-a-riscv32-and-xtensa-have-no-atomic-codegen. }
{$ifndef PXX_ESP}
{$ifndef CPURISCV32}
{$ifndef CPUXTENSA}
function InterLockedIncrement(var Target: LongInt): LongInt;
function InterLockedDecrement(var Target: LongInt): LongInt;
function InterLockedExchange(var Target: LongInt; Source: LongInt): LongInt;
function InterLockedExchangeAdd(var Target: LongInt; Source: LongInt): LongInt;
function InterLockedCompareExchange(var Target: LongInt;
                                    NewValue, Comperand: LongInt): LongInt;
{ 64-bit peers on 64-bit targets only: a 32-bit target has no
  single-instruction 64-bit read-modify-write and the intrinsic refuses at
  compile time, so the DECLARATIONS alone would break every 32-bit build.
  Same guard palatomic carries, and for the same measured reason. }
{$IFDEF CPU64}
function InterLockedIncrement64(var Target: Int64): Int64;
function InterLockedDecrement64(var Target: Int64): Int64;
function InterLockedExchange64(var Target: Int64; Source: Int64): Int64;
function InterLockedExchangeAdd64(var Target: Int64; Source: Int64): Int64;
function InterLockedCompareExchange64(var Target: Int64;
                                      NewValue, Comperand: Int64): Int64;
{$ENDIF}
{$endif}
{$endif}
{$endif}
function FloatToStr(v: Double): AnsiString;
function FloatToExpStr(v: Double): AnsiString;
function StrFloat(v: Double; width: Integer; decimals: Integer): AnsiString;
procedure Val(const s: AnsiString; var v: Int64; var code: Integer);
procedure ValQWord(const s: AnsiString; var v: QWord; var code: Integer);
procedure ValFloat(const s: AnsiString; var v: Double; var code: Integer);
function VariantToStr(const v: Variant): AnsiString;
function VariantTagName(t: Int64): AnsiString;
{ Variant -> SCALAR unboxing, the counterpart of IR_VAR_STORE/IR_VAR_BOX.
  Without these a variant reaching a scalar context (assignment, return,
  argument) was read as a raw 8-byte load and yielded the TAG, silently
  (bug-a-nilpy-variant-element-not-usable-as-scalar). Numeric/bool/char tags
  coerce between each other the way Pascal's Variant and Python's numeric
  tower both do; a STRING payload in a numeric context is a genuine type
  error and halts loudly rather than inventing a number. }
function VariantToInt64(const v: Variant): Int64;
function VariantToDouble(const v: Variant): Double;
function VariantToBool(const v: Variant): Boolean;
function VariantToChar(const v: Variant): Char;
{ Pascal Variant ARITHMETIC operand coercion — see the implementation. }
function PXXVarNumCoerce(src, dst: Pointer): Pointer;
{ Pascal Variant binop: PXXVarBinOp with the Pascal string rule applied first. }
function PXXVarBinOpPas(dest: Pointer; left: Pointer; right: Pointer; opTk: NativeInt; isCompare: NativeInt): Int64;
{ --strict-fpc ONLY: FPC's Variant->Char, which routes through the variant's
  STRING form and takes character 1 — Char(65) = '6', Char(122) = '1',
  Char(True) = 'T', Char(2.5) = '2'. The DEFAULT dialect uses VariantToChar
  above (Chr(n)); this exists so the conformance sweep can assert FPC parity.
  Selected by name at the lowering seam (IRLowerVariantAsScalar), which is why
  no strict flag has to be visible to the runtime.
  bug-p-variant-to-int-and-char-conversion-diverges-from-fpc }
function VariantToCharFPC(const v: Variant): Char;
function PCharToString(p: PChar): AnsiString;

{ A static `array[lo..hi] of Char` IS a string in FPC, in both directions, and
  these two are that conversion. `cap` is the array's element count.

  __pxxCharArrayToStr stops at the first #0 within cap and otherwise takes all
  cap characters -- FPC's rule, verified against 3.2.2: an
  `array[0..7] of Char` holding 'ABC'#0'EFGH' converts to the 3-character
  'ABC', while the same array holding eight non-NUL characters converts to all
  eight. So it is PCharToString with a hard length bound, not a plain memcpy.

  __pxxStrToCharArray copies Min(Length(s), cap) characters and ZERO-fills the
  rest, which is what makes `a := 'abc'` on an 8-element array leave
  `97 98 99 0 0 0 0 0` rather than five bytes of whatever was there.
  bug-p-a-char-array-is-not-a-string-in-any-direction }
function __pxxCharArrayToStr(p: PChar; cap: Integer): AnsiString;
procedure __pxxStrToCharArray(p: PChar; cap: Integer; const s: AnsiString);

{ WideChar -> UTF-8 conversion, backing the frontend's widechar-in-string-context
  lowering (`s := WideChar(u)`, `WideChar(u1)+WideChar(u2)`, a WideChar(x) passed
  to a string parameter). pxx's one string model is UTF-8 bytes, so a UTF-16 code
  unit converts at the boundary. The PAIR form is surrogate-aware: a high+low
  surrogate pair combines into one 4-byte code point (FPC's UTF-16 -> UTF-8
  conversion does the same); anything else encodes each unit independently.
  A LONE surrogate yields the empty string, matching FPC's conversion. }
function __pxxWideCharToUTF8(u: Integer): AnsiString;
function __pxxWideCharPairToUTF8(u1, u2: Integer): AnsiString;
{ UCS4Char -> UTF-8. Unlike the WideChar form above this takes a whole CODE
  POINT, so it covers the full range including the 4-byte encodings past the
  BMP, and it does NOT mask to $FFFF. A value that is not a code point — a lone
  surrogate, or past U+10FFFF — yields the empty string, matching what FPC's
  conversion does with an unpaired surrogate. }
function __pxxUCS4ToUTF8(u: Integer): AnsiString;

{ Substring intrinsic backing bare `Copy(s, index[, count])` on a string with no
  user `Copy` in scope — so frozen/managed string Copy works with no `uses`
  (the lib `sysutils.Copy` is the same routine for the explicit-uses path). FPC
  semantics: 1-based index clamped to >= 1, count clamped to the string end. }
function __pxxStrCopy(const s: AnsiString; index, count: Integer): AnsiString;

{ Bare `Delete(s, index, count)` / `Insert(src, s, index)` lower to these (see
  ParseStatementAST), so the standard in-place string mutators work with no
  `uses`. FPC semantics: 1-based index; Delete is a no-op when out of range;
  Insert clamps index into [1, Length(s)+1]. Built on __pxxStrCopy so the
  managed refcounting is the ordinary assignment path. }
procedure __pxxStrDelete(var s: AnsiString; index, count: Integer);
procedure __pxxStrInsert(const src: AnsiString; var s: AnsiString; index: Integer);

{ Published-method RTTI, backing FPC's `TObject.MethodAddress(name)` and
  `TObject.MethodName(addr)` with no `uses` (the parser rewrites those calls; see
  ParseLValueAST). FPC declares them on TObject in System, and fcl-fpcunit finds its
  Test* methods with `Self.MethodAddress(FName)`.

  The instance reaches its class RTTI through the backlink the compiler reserves one
  word BEFORE the VMT: [instance+0] is the VMT address, so the blob is at
  [[instance+0] - 8]. Blob layout is fixed by the RTTI_* constants in defs.inc:
  +0 name, +8 parent, +48 methCount, +56 meths; a method entry is 48 bytes
  {name, code, arity, retKind, paramKinds, flags} and only PUBLISHED entries
  (flags bit0) count for MethodAddress/MethodName. Names are INTERNED FROZEN
  STRINGS — the pointer targets an 8-byte
  length prefix with the chars at +8, NOT a bare char*.

  Own and inherited methods both resolve (the parent chain is walked). Matching is
  case-insensitive, as in FPC. nil / '' when there is no match. The richer surface
  (enumerate, bind-and-call) lives in the RTL's `rtti` unit. }
function __pxxMethodAddress(Instance: Pointer; const Name: AnsiString): Pointer;
function __pxxMethodName(Instance: Pointer; Address: Pointer): AnsiString;

{ FPC's TObject.GetInterface(const IID: TGUID; out Obj): Boolean — look an
  implemented interface up BY GUID at runtime and hand back the interface value.

  The class RTTI blob carries an interface table at +80/+88: one 24-byte entry per
  implemented interface that declared a GUID, holding the 16 raw GUID bytes followed
  by a pointer to that (class, interface) IMT. On a hit we write the 16-byte fat
  pointer {IMT, instance} — exactly what a pxx interface variable is — through Obj.

  IID and Obj are passed as untyped pointers so the builtin unit does not need TGuid
  in scope; the parser hands over their addresses. }
function __pxxGetInterface(Instance: Pointer; IID: Pointer; Obj: Pointer): Boolean;

{ Bare `Abs(x)` / `Sqr(x)` lower to these (see ParseFactor) so the System
  intrinsics work with no `uses` and the argument is evaluated once (the naive
  e*e / if e<0 fold would double-evaluate a side-effecting argument). }
function __pxxAbsInt(x: Int64): Int64;
function __pxxAbsDbl(d: Double): Double;
function __pxxSqrInt(x: Int64): Int64;
function __pxxSqrDbl(d: Double): Double;

{ Bare `UpCase(c)` / `Pos(sub, s)` lower to these (see ParseFactor) so the System
  intrinsics work with no `uses`. A `uses sysutils` Pos (or any user routine)
  shadows them at the call site. }
function __pxxUpCase(c: Char): Char;
function __pxxPos(const sub, s: AnsiString): Integer;

{ FPC System bit rotates (RolDWord/RorDWord/RolQWord/RorQWord), reached through
  a parser soft-alias like UpCase/Pos so no real proc of those names exists to
  shadow a user's own. n is masked to the width like FPC/x86 do. }
function __pxxRolDWord(v: Cardinal; n: Integer): Cardinal;
function __pxxRorDWord(v: Cardinal; n: Integer): Cardinal;
function __pxxRolQWord(v: QWord; n: Integer): QWord;
function __pxxRorQWord(v: QWord; n: Integer): QWord;

{ The heap allocator and managed-string helpers (PXXAlloc/Free/Realloc,
  PXXStr*) moved to the `builtinheap` unit so heap-only / string-only programs
  do not pull in the Str/Val/Variant routines below. }

{ System memory primitives (FPC keeps these in System, available with no
  `uses`): pulled via the bare-name token pre-scan like Str/Val, and reached
  through a parser soft-alias (bare `Move(`/`FillChar(` -> these hidden
  names) so NO real proc named Move/FillChar exists to shadow a user's own
  proc or a class method of the same name (that broke adventure's
  TGame.Move). Overlap-safe Move (memmove) and FillChar; plain byte loops —
  feature-move-fillchar-intrinsics tracks the optimized emission. }
{ System.Assert(cond[, msg]) — reached through a parser soft-alias (bare `Assert(` ->
  this hidden name), so NO real proc named Assert exists to shadow a user's own Assert or
  a method of the enclosing class. On failure it reports and halts with 227, FPC's
  assertion runtime error. The message is a defaulted parameter, so both arities work. }
{ FPC's assertion mechanism is a HOOK, not a fixed action: System's
  AssertErrorProc defaults to "print and run-error 227", and SysUtils REPLACES
  it with one that raises EAssertionFailed. That single indirection is the whole
  difference between `Assert` aborting and `Assert` being catchable, and it is
  why a no-sysutils program must keep the 227 behaviour — that is FPC's too.
  compat-pascal-assert-halts-instead-of-raising-eassertionfailed }
type
  TAssertErrorProc = procedure(const msg: AnsiString);
var
  AssertErrorProc: TAssertErrorProc;
procedure __pxxAssert(cond: Boolean; const msg: AnsiString = '');

procedure __pxxMove(const Source; var Dest; Count: Integer);
procedure __pxxFillChar(var X; Count: Integer; Value: Byte);
procedure __pxxFillDWord(var X; Count: Integer; Value: Cardinal);
function __pxxCompareByte(const Buf1, Buf2; Len: Int64): Int64;

{ FPC System PRNG surface (Random/Randomize/RandSeed), pulled via the bare-name
  token pre-scan like Str/Val. RandSeed IS the generator state (TP-style:
  writing it restarts the sequence, each call advances it); the generator is a
  xorshift32 — conformance tests seed it for reproducibility of their OWN run
  and never depend on FPC's exact sequence. A user declaration of any of these
  names shadows, like the other System names in this unit. }
var
  RandSeed: Cardinal;
  HwRandomProbe: Integer;   { CPUID cache: 0 unknown, 1 has RDRAND, 2 has not }

function Random(range: Int64): Int64;
procedure Randomize;

{ ---- Hardware entropy (tier 1) -----------------------------------------

  lib/rtl/random.pas has a HARD design mandate: one elegant .pas file, no
  per-arch {$ifdef} soup. Its tiers 2 (getrandom/urandom) and 3 (xoshiro256**)
  satisfy that because neither needs a special instruction. Tier 1 does, so the
  instruction lives behind these two entry points and the library reads as three
  one-line tier selections. feature-a-rdrand-cpuid-compiler-builtins

  __pxxHwRandom64 REPORTS SUCCESS rather than just handing back a value, and
  that is the whole point of the signature: RDRAND can fail — under load or
  entropy exhaustion it clears CF and leaves the destination ZERO. A caller that
  read the value alone would take a silent zero for entropy, which in the one
  context these instructions exist for is a catastrophic and invisible failure.
  So: False means "no entropy this time, retry a bounded number of times, then
  fall to tier 2".

  __pxxCpuHasHwRandom probes CPUID leaf 1 ECX bit 30 and caches the answer.
  The probe is mandatory, not decorative: the instruction is absent on plenty of
  cores and executing it there is #UD.

  x86-64 only so far. aarch64's MRS RNDR needs FEAT_RNG, which is OPTIONAL and
  needs its own ID_AA64ISAR0_EL1 probe plus system-register support in the a64
  assembler; arm32 and riscv32 have no user-mode instruction at all (the library
  stays on tier 2 there); ESP's RNG register is a Track S item and is only truly
  random with the RF clock enabled. Every non-x86-64 target answers False here,
  which routes the library to tier 2 — the correct answer, not a stub. }
function __pxxCpuHasHwRandom: Boolean;
function __pxxHwRandom64(var v: UInt64): Boolean;

{ FPC System.HexStr(Val, cnt): Val as cnt hex digits, truncating on the left
  (HexStr($1234, 2) = '34'), zero-padding on the right ('0012'). }
function HexStr(Val: Int64; cnt: Integer): AnsiString;

{ FPC System.RunError(n): report a runtime error and terminate with exit code
  n. FPC also prints the faulting address; there is no portable way to get a
  meaningful one here, so just the number. }
procedure RunError(errnum: Integer);

{ FPC System.Lo/Hi: the two halves of the value, SIZED BY THE ARGUMENT'S OWN
  TYPE — nibbles for a byte, bytes for a 16-bit type, words for a 32-bit one,
  longwords for a 64-bit one. One overload per integer type, because leaving a
  width out does not fall back to something sensible: it silently widens into
  the next overload and returns a plausible wrong number (hi(word($1234)) gave
  0 where FPC gives $12, and an Int64 argument was truncated into the Cardinal
  overload). Measured against FPC, including the two rows that read as warts:

    - ShortInt is NOT split into nibbles the way Byte is. FPC sign-extends it
      to 16 bits first, so hi(shortint(-86)) = $FF, not $A.
    - the halves are bit patterns, so a negative argument splits its two's
      complement and the results are unsigned. }
function Lo(v: Byte): Byte;
function Lo(v: ShortInt): Byte;
function Lo(v: Word): Byte;
function Lo(v: SmallInt): Byte;
function Lo(v: LongInt): Word;
function Lo(v: Cardinal): Word;
function Lo(v: Int64): Cardinal;
function Lo(v: QWord): Cardinal;
function Hi(v: Byte): Byte;
function Hi(v: ShortInt): Byte;
function Hi(v: Word): Byte;
function Hi(v: SmallInt): Byte;
function Hi(v: LongInt): Word;
function Hi(v: Cardinal): Word;
function Hi(v: Int64): Cardinal;
function Hi(v: QWord): Cardinal;

{ FPC System.Swap: exchange the two halves. Same per-type dispatch as Lo/Hi and
  the same reason for spelling every width out — but the sizes differ: Swap has
  no nibble form, a 1-byte argument widens to 16 bits and swaps ITS bytes
  (swap(byte($AB)) = $AB00, a Word), and the result keeps the argument's
  signedness (swap(shortint(-86)) = -21761). }
function Swap(v: Byte): Word;
function Swap(v: ShortInt): SmallInt;
function Swap(v: Word): Word;
function Swap(v: SmallInt): SmallInt;
function Swap(v: LongInt): LongInt;
function Swap(v: Cardinal): Cardinal;
function Swap(v: Int64): Int64;
function Swap(v: QWord): QWord;

{ FPC System.UniqueString(s): make the string's payload uniquely referenced so
  in-place writes (e.g. through a PChar into it) cannot alias another string. }
procedure UniqueString(var s: AnsiString);

implementation

{ Advance the xorshift32 state living in RandSeed. State 0 is a fixed point of
  xorshift, so it maps to an arbitrary nonzero constant (RandSeed = 0 and
  RandSeed = that constant give the same sequence — harmless). }
function __pxxRandNext32: Cardinal;
var x: Cardinal;
begin
  x := RandSeed;
  if x = 0 then x := 2463534242;
  x := x xor (x shl 13);
  x := x xor (x shr 17);
  x := x xor (x shl 5);
  RandSeed := x;
  Result := x;
end;

function Random(range: Int64): Int64;
var v: Int64;
begin
  if range <= 0 then
  begin
    Result := 0;
    Exit;
  end;
  v := ((Int64(__pxxRandNext32) shl 32) or Int64(__pxxRandNext32)) and
       $7FFFFFFFFFFFFFFF;
  Result := v mod range;
end;

procedure Randomize;
var
  ts: array[0..1] of Int64;
  r: Int64;
begin
  ts[0] := 0; ts[1] := 0; r := 0;
  { clock_gettime(CLOCK_MONOTONIC=1, @ts) via the raw-syscall intrinsic; the
    buffer is large enough for both the 64-bit and legacy 32-bit timespec
    layouts, and the raw bytes are only entropy — layout does not matter. }
{$ifdef CPUX86_64}
  r := __pxxrawsyscall(228, 1, Int64(@ts[0]), 0, 0, 0, 0);
{$endif}
{$ifdef CPUAARCH64}
  r := __pxxrawsyscall(113, 1, Int64(@ts[0]), 0, 0, 0, 0);
{$endif}
{$ifdef CPU_ARM32}
  r := __pxxrawsyscall(263, 1, Int64(@ts[0]), 0, 0, 0, 0);
{$endif}
{$ifdef CPU_I386}
  r := __pxxrawsyscall(265, 1, Int64(@ts[0]), 0, 0, 0, 0);
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  r := __pxxrawsyscall(403, 1, Int64(@ts[0]), 0, 0, 0, 0);  { clock_gettime64 }
{$endif}
{$endif}
  { No clock on a bare target (PXX_ESP): ts stays zero and the stack address
    below is the only entropy — Randomize is still callable, just weak there. }
  RandSeed := Cardinal(ts[0] xor ts[1] xor r xor Int64(@ts[0]));
end;

{ ---- Hardware entropy (tier 1) — see the interface note ---------------- }

{$ifdef CPUX86_64}
function __pxxCpuidRdrand: Boolean; assembler;
{$asmMode intel}
asm
  push rbx
  mov eax, 1
  xor ecx, ecx
  cpuid
  shr ecx, 30
  and ecx, 1
  mov eax, ecx
  pop rbx
end;

function __pxxHwRandom64(var v: UInt64): Boolean; assembler;
{$asmMode intel}
asm
  mov rcx, v
  xor edx, edx
  rdrand rax
  setc dl
  mov [rcx], rax
  mov eax, edx
end;
{$endif}

{$ifndef CPUX86_64}
function __pxxCpuidRdrand: Boolean;
begin
  Result := False;
end;

function __pxxHwRandom64(var v: UInt64): Boolean;
begin
  { Not "unimplemented": no user-mode hardware RNG instruction exists on this
    target, so False is the correct answer and routes the caller to tier 2. }
  v := 0;
  Result := False;
end;
{$endif}

function __pxxCpuHasHwRandom: Boolean;
begin
  { Cached: CPUID is serialising and the library asks this on its dispatch
    path. 0 = not probed yet, 1 = yes, 2 = no. Three states, one variable —
    two Booleans that must agree is how one of them ends up stale. }
  if HwRandomProbe = 0 then
  begin
    if __pxxCpuidRdrand then HwRandomProbe := 1 else HwRandomProbe := 2;
  end;
  Result := HwRandomProbe = 1;
end;

function HexStr(Val: Int64; cnt: Integer): AnsiString;
const
  digits = '0123456789ABCDEF';
var
  i: Integer;
begin
  if cnt < 0 then cnt := 0;
  SetLength(Result, cnt);
  for i := cnt downto 1 do
  begin
    Result[i] := digits[Integer(Val and $F) + 1];
    Val := Val shr 4;
  end;
end;

procedure RunError(errnum: Integer);
begin
  writeln('Runtime error ', errnum);
  Halt(errnum);
end;

{ Lo/Hi: halves sized by the argument's own type (see the interface note). A
  signed argument is split as the bit pattern it sign-extends to, which is what
  makes `and`/`shr` on the widened value the whole implementation. }
function Lo(v: Byte): Byte;
begin
  Result := Byte(v and $0F);
end;

function Lo(v: ShortInt): Byte;
begin
  Result := Byte(v and $FF);
end;

function Lo(v: Word): Byte;
begin
  Result := Byte(v and $FF);
end;

function Lo(v: SmallInt): Byte;
begin
  Result := Byte(v and $FF);
end;

function Lo(v: LongInt): Word;
begin
  Result := Word(v and $FFFF);
end;

function Lo(v: Cardinal): Word;
begin
  Result := Word(v and $FFFF);
end;

function Lo(v: Int64): Cardinal;
begin
  Result := Cardinal(v and $FFFFFFFF);
end;

function Lo(v: QWord): Cardinal;
begin
  Result := Cardinal(v and $FFFFFFFF);
end;

function Hi(v: Byte): Byte;
begin
  Result := Byte((v shr 4) and $0F);
end;

function Hi(v: ShortInt): Byte;
begin
  Result := Byte((v shr 8) and $FF);
end;

function Hi(v: Word): Byte;
begin
  Result := Byte((v shr 8) and $FF);
end;

function Hi(v: SmallInt): Byte;
begin
  Result := Byte((v shr 8) and $FF);
end;

function Hi(v: LongInt): Word;
begin
  Result := Word((v shr 16) and $FFFF);
end;

function Hi(v: Cardinal): Word;
begin
  Result := Word((v shr 16) and $FFFF);
end;

function Hi(v: Int64): Cardinal;
begin
  Result := Cardinal((v shr 32) and $FFFFFFFF);
end;

function Hi(v: QWord): Cardinal;
begin
  Result := Cardinal((v shr 32) and $FFFFFFFF);
end;

{ Swap: no nibble form — a 1-byte argument is swapped as the 16-bit value it
  widens to, and the result keeps the argument's signedness. }
function Swap(v: Byte): Word;
begin
  Result := Word(((v and $FF) shl 8) or ((v shr 8) and $FF));
end;

function Swap(v: ShortInt): SmallInt;
begin
  Result := SmallInt(((v and $FF) shl 8) or ((v shr 8) and $FF));
end;

function Swap(v: Word): Word;
begin
  Result := Word(((v and $FF) shl 8) or ((v shr 8) and $FF));
end;

function Swap(v: SmallInt): SmallInt;
begin
  Result := SmallInt(((v and $FF) shl 8) or ((v shr 8) and $FF));
end;

function Swap(v: LongInt): LongInt;
begin
  Result := LongInt(((v and $FFFF) shl 16) or ((v shr 16) and $FFFF));
end;

function Swap(v: Cardinal): Cardinal;
begin
  Result := ((v and $FFFF) shl 16) or ((v shr 16) and $FFFF);
end;

function Swap(v: Int64): Int64;
begin
  Result := Int64(((v and $FFFFFFFF) shl 32) or ((v shr 32) and $FFFFFFFF));
end;

function Swap(v: QWord): QWord;
begin
  Result := ((v and $FFFFFFFF) shl 32) or ((v shr 32) and $FFFFFFFF);
end;

procedure UniqueString(var s: AnsiString);
begin
  if s <> '' then
    s := __pxxStrCopy(s, 1, Length(s));
end;

procedure __pxxAssert(cond: Boolean; const msg: AnsiString = '');
begin
  if cond then Exit;
  { Installed hook wins (sysutils installs one that RAISES EAssertionFailed, so
    `try Assert(...) except` can run its handler). Unset — a program that does
    not use sysutils — keeps the print + Halt(227) below, which is exactly what
    FPC does in that case. }
  if Assigned(AssertErrorProc) then
  begin
    AssertErrorProc(msg);
    Exit;                          { a raising hook never returns; a print-only one may }
  end;
  if msg = '' then
    writeln('Assertion failed')
  else
    writeln('Assertion failed: ', msg);
  Halt(227);                       { FPC's assertion runtime error }
end;

function __pxxRolDWord(v: Cardinal; n: Integer): Cardinal;
begin
  n := n and 31;
  if n = 0 then Result := v
  else Result := (v shl n) or (v shr (32 - n));
end;

function __pxxRorDWord(v: Cardinal; n: Integer): Cardinal;
begin
  n := n and 31;
  if n = 0 then Result := v
  else Result := (v shr n) or (v shl (32 - n));
end;

function __pxxRolQWord(v: QWord; n: Integer): QWord;
begin
  n := n and 63;
  if n = 0 then Result := v
  else Result := (v shl n) or (v shr (64 - n));
end;

function __pxxRorQWord(v: QWord; n: Integer): QWord;
begin
  n := n and 63;
  if n = 0 then Result := v
  else Result := (v shr n) or (v shl (64 - n));
end;

procedure __pxxMove(const Source; var Dest; Count: Integer);
var s, d: PByte; i: Integer;
begin
  if Count <= 0 then Exit;
  s := PByte(@Source);
  d := PByte(@Dest);
  { Overlap-safe: when Dest is above Source and the ranges overlap, copy
    backward so we don't clobber not-yet-copied bytes (memmove, not memcpy). }
  if (Int64(d) > Int64(s)) and (Int64(d) < Int64(s) + Count) then
    for i := Count - 1 downto 0 do d[i] := s[i]
  else
    for i := 0 to Count - 1 do d[i] := s[i];
end;

procedure __pxxFillChar(var X; Count: Integer; Value: Byte);
var d: PByte; i: Integer;
begin
  d := PByte(@X);
  for i := 0 to Count - 1 do d[i] := Value;
end;

procedure __pxxFillDWord(var X; Count: Integer; Value: Cardinal);
var d: PInt32; i: Integer;
begin
  { FPC FillDWord: Count is in 4-byte units }
  d := PInt32(@X);
  for i := 0 to Count - 1 do d[i] := Integer(Value);
end;

function __pxxCompareByte(const Buf1, Buf2; Len: Int64): Int64;
var a, b: PByte; i: Int64;
begin
  { FPC System.CompareByte: 0 if equal, else sign of first difference }
  a := PByte(@Buf1);
  b := PByte(@Buf2);
  __pxxCompareByte := 0;
  for i := 0 to Len - 1 do
    if a[i] <> b[i] then
    begin
      __pxxCompareByte := Int64(a[i]) - Int64(b[i]);
      Exit;
    end;
end;


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
  if (p^.VType = 1) or (p^.VType = 2) then
    { VT_INT and VT_INT64 both hold an integer payload; VariantToInt64 already
      treats them alike — the str path must too, or a 64-bit-tagged int (e.g. a
      binop result) formats as the empty string. }
    Result := StrInt(p^.Payload, 0)
  else if p^.VType = 3 then
    Result := FloatToStr(PDouble(@p^.Payload)^)
  else if p^.VType = 4 then
    { VT_BOOL. Missing until 2026-08-13, so `s := v` on a boolean variant fell
      off this chain into the trailing '' — silently, while writeln(v) rendered
      True through the OTHER variant->text path. FPC prints True/False here.
      bug-a-variant-to-string-drops-the-boolean-tag }
    begin
      if p^.Payload <> 0 then Result := 'True' else Result := 'False';
    end
  else if p^.VType = 5 then
    Result := Chr(p^.Payload)
  else if p^.VType = 6 then
    Result := PAnsiString(@p^.Payload)^
  else if p^.VType = 8193 then
    { VT_PROMO_INT64: a promotable int too large for the inline tier. Its
      payload IS the exact decimal, held as a managed AnsiString — see
      compiler/builtin/promocore.pas. An inline-tier promo never reaches here;
      it is stored as an ordinary VT_INT64. }
    Result := PAnsiString(@p^.Payload)^
  else if p^.VType = 0 then
    Result := 'None'
  else
    Result := '';
end;


function VariantTagName(t: Int64): AnsiString;
begin
  if t = 0 then Result := 'None'
  else if (t = 1) or (t = 2) then Result := 'an integer'
  else if t = 3 then Result := 'a float'
  else if t = 4 then Result := 'a boolean'
  else if t = 5 then Result := 'a character'
  else if t = 6 then Result := 'a string'
  else if t = 7 then Result := 'an object'
  else if (t >= 8192) and (t <= 8199) then Result := 'a promotable integer'
  else Result := 'an unknown tag';
end;

{ Pascal Variant arithmetic converts a STRING or CHAR operand to a NUMBER, and
  raises EVariantError when the text is not numeric -- FPC's rule, and the same
  one VariantToInt64's VT_STRING arm below already implements for `i := v`. The
  binop path never called it, so `v('15') - 3` read the ANSISTRING HANDLE as an
  integer and answered a heap address, while `v('5') - 3` answered 50, the char
  ordinal (bug-p-variant-arithmetic-on-a-string-reads-the-payload-as-a-number).

  Returns src UNTOUCHED for every other tag, so the caller can call it
  unconditionally on both operands; dst is a caller-owned 16-byte scratch
  variant that outlives the operation. An integer-looking string coerces to
  VT_INT64 and a fractional one to VT_DOUBLE, which is what makes `'5' + 2.5`
  come out 7.5 rather than 7: the existing dispatch promotes to double as soon
  as either side carries VT_DOUBLE.

  NilPy does NOT come through here -- the emitter only calls it when
  PyProgramMode is off -- because Python's rules are different in every one of
  these cases ('5' * 3 is '555', '5' + 3 is a TypeError). }
function PXXVarNumCoerce(src, dst: Pointer): Pointer;
var
  p, d: PVariantRecord;
  txt: AnsiString;
  iv: Int64;
  dv: Double;
  vcode: Integer;
begin
  Result := src;
  p := PVariantRecord(src);
  if (p^.VType <> 5) and (p^.VType <> 6) then Exit;   { not VT_CHAR / VT_STRING }
  if p^.VType = 5 then
    txt := Chr(Byte(p^.Payload))                      { VT_CHAR: its one character, as text }
  else
    txt := PAnsiString(@p^.Payload)^;                 { VT_STRING }
  d := PVariantRecord(dst);
  Val(txt, iv, vcode);
  if vcode = 0 then
  begin
    d^.VType := 2;                                    { VT_INT64 }
    d^.Payload := iv;
    Result := dst;
    Exit;
  end;
  ValFloat(txt, dv, vcode);
  if vcode = 0 then
  begin
    d^.VType := 3;                                    { VT_DOUBLE }
    PDouble(@d^.Payload)^ := dv;
    Result := dst;
    Exit;
  end;
  writeln('Runtime error: EVariantError, cannot convert string to a number');
  Halt(219);
end;

function PXXVarBinOpPas(dest: Pointer; left: Pointer; right: Pointer; opTk: NativeInt; isCompare: NativeInt): Int64;
{ PASCAL's Variant binop. PXXVarBinOp is the raw dispatch that i386, arm32,
  aarch64 and riscv32 call for IR_VAR_BINOP; this wrapper puts FPC's rule in
  front of it, and the backends select it whenever the program is not NilPy.

  The rule has two halves and the raw dispatch gets both wrong:

    * `+` CONCATENATES only when BOTH operands are stringy. PXXVarBinOp takes
      its concat arm when EITHER is, so `'5' + 3` was '5' and `5 + '3'` was
      '3' — it rendered the stringy side and dropped the other.
    * every OTHER arithmetic operator converts a stringy operand to a number.
      PXXVarBinOp has no coercion at all, so `-`, `*` and `/` read the payload
      raw: a VT_CHAR's ordinal (`'5' - 3` = 50) and, far worse, a VT_STRING's
      ANSISTRING HANDLE — `'15' - 3` answered a heap address, a different one
      every run, on every target that routes through here.

  x86-64 hand-emits the same two halves in EmitVarBinOp and was fixed on
  2026-08-20 (bug-p-variant-arithmetic-on-a-string-reads-the-payload-as-a-number);
  this is the other four targets' half.

  NilPy must NOT reach this: Python's rules for these pairs are different in
  every case ('5' * 3 is '555', '5' + 3 is a TypeError). The choice is made at
  EMIT time from PyProgramMode, which is exactly what a shared runtime helper
  cannot see — so it is made by choosing WHICH helper to call, rather than by a
  runtime flag the frontend would have to set.
  bug-a-pxxvarbinop-carries-the-same-string-arithmetic-defect-as-x86-64-did }
var
  la, ra: TVariantRecord;
  lp, rp: Pointer;
  lStr, rStr: Boolean;
begin
  lp := left;
  rp := right;
  if isCompare = 0 then
  begin
    lStr := (PVariantRecord(left)^.VType = 5) or (PVariantRecord(left)^.VType = 6);
    rStr := (PVariantRecord(right)^.VType = 5) or (PVariantRecord(right)^.VType = 6);
    { tkPlus = 70. Both stringy and `+` is the one case that stays a concat;
      hand the raw dispatch the ORIGINAL operands so its string arm fires. }
    if not ((opTk = 70) and lStr and rStr) then
    begin
      lp := PXXVarNumCoerce(left, @la);
      rp := PXXVarNumCoerce(right, @ra);
    end;
  end;
  Result := PXXVarBinOp(dest, lp, rp, opTk, isCompare);
end;

function VariantToInt64(const v: Variant): Int64;
var
  p: PVariantRecord;
  vcode: Integer;
begin
  p := @v;
  if p^.VType = 4 then
    { VT_BOOL -> OLE's VARIANT_TRUE: True is -1, not 1. FPC's rule, adopted
      2026-08-13 (user) — it is self-consistent across the whole variant
      conversion table (Int64 -1, Byte 255, Double -1.0) and is what every OLE
      consumer expects. Scoped to the VARIANT conversion: Ord(True) and
      Integer(someBooleanVar) stay 1, exactly as in FPC.

      NilPy MUST NOT reach this: Python's True IS 1 (sum([True, True]) == 2),
      and pylib's four direct calls here were rerouted to pyvar_to_int in the
      same change. The lowering seam keeps every other NilPy path on pylib's
      helper set. bug-p-variant-to-int-and-char-conversion-diverges-from-fpc }
    begin
      if p^.Payload <> 0 then Result := -1 else Result := 0;
    end
  else if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 5) then
    Result := p^.Payload
  else if p^.VType = 3 then
    Result := Trunc(PDouble(@p^.Payload)^)
  else if p^.VType = 0 then
    Result := 0
  else if p^.VType = 8193 then
  begin
    { VT_PROMO_INT64 holds a value that did NOT fit the inline tier, so by
      construction it does not fit an Int64 either. Truncating it is the defect
      the promotable int exists to remove — assign to a PromoInt instead. }
    writeln('Runtime error: EVariantError, promotable integer ',
            PAnsiString(@p^.Payload)^, ' does not fit an Int64');
    Halt(219);
  end
  else if p^.VType = 6 then
  begin
    { VT_STRING. FPC PARSES it -- measured, not assumed: `i := v` with v='42'
      yields 42 and v='abc' raises EVariantError. NilPy does NOT come through
      here (it has pylib's pyvar_to_int, which raises a Python TypeError for
      any string); this helper is the Pascal path and follows Pascal. }
    Val(PAnsiString(@p^.Payload)^, Result, vcode);
    if vcode <> 0 then
    begin
      writeln('Runtime error: EVariantError, cannot convert string to integer');
      Halt(219);
    end;
  end
  else
  begin
    writeln('Runtime error: variant holds ', VariantTagName(p^.VType),
            ', an integer was required');
    Halt(219);
  end;
end;

function VariantToDouble(const v: Variant): Double;
var
  p: PVariantRecord;
  vcode: Integer;
begin
  p := @v;
  if p^.VType = 3 then
    Result := PDouble(@p^.Payload)^
  else if p^.VType = 4 then
    { VARIANT_TRUE = -1 here too — the whole point of adopting FPC's rule is
      that it is consistent across the table (Double(True) = -1.0). See
      VariantToInt64. }
    begin
      if p^.Payload <> 0 then Result := -1.0 else Result := 0.0;
    end
  else if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 5) then
    Result := p^.Payload
  else if p^.VType = 0 then
    Result := 0.0
  else if p^.VType = 6 then
  begin
    { FPC coerces a numeric string here too (v='2.5' -> 2.50, measured). }
    ValFloat(PAnsiString(@p^.Payload)^, Result, vcode);
    if vcode <> 0 then
    begin
      writeln('Runtime error: EVariantError, cannot convert string to float');
      Halt(219);
    end;
  end
  else
  begin
    writeln('Runtime error: variant holds ', VariantTagName(p^.VType),
            ', a float was required');
    Halt(219);
  end;
end;

function VariantToBool(const v: Variant): Boolean;
var
  p: PVariantRecord;
begin
  { PASCAL rules. This once carried Python's truthiness while NilPy was still
    routed through it; NilPy now has pylib's pyvar_to_bool. FPC RAISES for a
    string here (`b := v` with v='' is EVariantError, measured) rather than
    treating '' as false, and 0.0 is False. }
  p := @v;
  if p^.VType = 3 then
    Result := PDouble(@p^.Payload)^ <> 0.0
  else if p^.VType = 0 then
    Result := False
  else if (p^.VType = 6) or (p^.VType = 7) then
  begin
    writeln('Runtime error: EVariantError, cannot convert ',
            VariantTagName(p^.VType), ' to boolean');
    Halt(219);
    Result := False;
  end
  else
    Result := p^.Payload <> 0;
end;

function VariantToChar(const v: Variant): Char;
var
  p: PVariantRecord;
  s: AnsiString;
begin
  p := @v;
  if p^.VType = 6 then
  begin
    s := PAnsiString(@p^.Payload)^;
    if s = '' then Result := #0 else Result := s[1];
  end
  else
    Result := Chr(p^.Payload and $FF);
end;

function VariantToCharFPC(const v: Variant): Char;
{ See the interface note. Deliberately built ON TOP of VariantToStr rather than
  duplicating the tag walk: FPC's rule IS "render, then index", and the two
  staying in step is the whole point — the boolean row (Char(True) = 'T') only
  works because VariantToStr learned VT_BOOL in this same change. }
var
  p: PVariantRecord;
  s: AnsiString;
begin
  p := @v;
  if p^.VType = 0 then
  begin
    { FPC raises here, and its message names String rather than Char — the
      diagnostic leaks the intermediate step. Reproduced verbatim: under a
      parity flag the error text is part of the behaviour being matched. }
    writeln('Runtime error: EVariantTypeCastError, Could not convert variant ',
            'of type (Null) into type (String)');
    Halt(219);
  end;
  s := VariantToStr(v);
  if s = '' then Result := #0 else Result := s[1];
end;

function StrQWord(v: QWord; width: Integer): AnsiString;
{ StrInt's UNSIGNED sibling: a QWord >= 2^63 must not print with a minus sign
  (write(Text, q) routes here; the console writeln path has its own unsigned
  emitter). }
var
  digits: string;
  n: QWord;
  d: Integer;
begin
  digits := '';
  if v = 0 then
    digits := '0'
  else
  begin
    n := v;
    while n > 0 do
    begin
      d := Integer(n mod 10);
      digits := Chr(Ord('0') + d) + digits;
      n := n div 10;
    end;
  end;
  Result := digits;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

{$ifndef PXX_ESP}
{$ifndef CPURISCV32}
{$ifndef CPUXTENSA}
function InterLockedIncrement(var Target: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, 1)) + 1;
end;

function InterLockedDecrement(var Target: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, -1)) - 1;
end;

function InterLockedExchange(var Target: LongInt; Source: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_xchg(@Target, Source));
end;

function InterLockedExchangeAdd(var Target: LongInt; Source: LongInt): LongInt;
begin
  Result := LongInt(__pxxatomic_add(@Target, Source));
end;

function InterLockedCompareExchange(var Target: LongInt;
                                    NewValue, Comperand: LongInt): LongInt;
begin
  { ARGUMENT ORDER: FPC takes (new, expected), the intrinsic takes
    (expected, new). Swapping them is the whole point of the wrapper. }
  Result := LongInt(__pxxatomic_cas(@Target, Comperand, NewValue));
end;

{$IFDEF CPU64}
function InterLockedIncrement64(var Target: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, 1) + 1;
end;

function InterLockedDecrement64(var Target: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, -1) - 1;
end;

function InterLockedExchange64(var Target: Int64; Source: Int64): Int64;
begin
  Result := __pxxatomic_xchg64(@Target, Source);
end;

function InterLockedExchangeAdd64(var Target: Int64; Source: Int64): Int64;
begin
  Result := __pxxatomic_add64(@Target, Source);
end;

function InterLockedCompareExchange64(var Target: Int64;
                                      NewValue, Comperand: Int64): Int64;
begin
  Result := __pxxatomic_cas64(@Target, Comperand, NewValue);
end;
{$ENDIF}
{$endif}
{$endif}
{$endif}

function StrChar(c: Char; width: Integer): AnsiString;
{ One Char as a string, space-padded on the LEFT to `width` (width <= 1 = no
  padding), matching what StrInt/StrFloat do with their width argument.
  bug-p-writeln-text-rejects-char }
var r: AnsiString;
begin
  r := ' ';
  r[1] := c;
  while Length(r) < width do r := ' ' + r;
  StrChar := r;
end;

function StrStrW(const s: AnsiString; width: Integer): AnsiString;
{ see the interface comment. FPC pads on the LEFT and never truncates: a value
  wider than the field is written in full. }
var r: AnsiString;
begin
  r := s;
  while Length(r) < width do r := ' ' + r;
  StrStrW := r;
end;

function StrBool(b: Boolean; width: Integer): AnsiString;
begin
  if b then StrBool := StrStrW('TRUE', width)
  else StrBool := StrStrW('FALSE', width);
end;

function StrInt(v: Int64; width: Integer): AnsiString;
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
    if neg then
    begin
      { Low(Int64) has no positive counterpart (-n wraps to itself and the
        digit loop then produced just "-"): peel the last digit in the
        NEGATIVE domain first — Pascal div/mod truncate toward zero, so
        n mod 10 is in -9..0 and n div 10 moves toward zero. }
      d := -(n mod 10);
      digits := Chr(Ord('0') + d);
      n := -(n div 10);
    end;
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

function FloatToExpStr(v: Double): AnsiString;
{ Decimal exponent form, for magnitudes the Int64 digit split cannot hold. The
  mantissa is normalised into [1,10) and formatted by FloatToStr itself, which
  is then in range by construction — one formatting rule, not two. A mantissa
  of exactly `1.0` loses its `.0` so the result reads `1e+19` the way Python
  writes it rather than `1.0e+19`, and the exponent is padded to two digits for
  the same reason. }
var neg: Boolean; e, i: Integer; m, es: AnsiString;
begin
  { NaN and infinities first. FloatToStr's own header already warns that "the
    normalise loop in FloatToExpStr would not terminate on an infinity" — that
    guard was added THERE and never here, so every caller that reaches this
    routine first (Str with no width, and any magnitude the Int64 digit split
    cannot hold) hung instead: `Inf / 10.0` is still Inf, and a NaN fails both
    `>= 10.0` and `< 1.0` so it falls out with e = 0 and then formats garbage.
    Same spelling as FloatToStr, which is the one this delegates to anyway
    (bug-a-writeln-of-a-non-finite-double-hangs). }
  if v <> v then begin Result := 'NaN'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := 'Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  neg := v < 0;
  if neg then v := -v;
  e := 0;
  { DEAD END, do not retry as-is: normalising by binary decomposition of the
    exponent (step 256,128,…,1 through 10^step) was tried to cut the rounding
    these one-decade loops accumulate. It improved some values (1e-16, 1.5e-25
    became exact) and made others WORSE — 1e300 went from 1.000000000000001e+300
    to 9.999999999999995e+299, because dividing by an inexact 10^n lands the
    mantissa just under 1.0 and the settling step then borrows a decade. Any
    real fix has to round the DIGITS from an integer representation rather than
    scale the double first; that is the shortest-round-trip work recorded as
    step 3 on bug-nilpy-float-repr-loses-small-values-and-does-not-round-trip. }
  while v >= 10.0 do begin v := v / 10.0; e := e + 1; end;
  while (v > 0.0) and (v < 1.0) do begin v := v * 10.0; e := e - 1; end;
  m := FloatToStr(v);
  i := Length(m);
  if (i > 2) and (m[i] = '0') and (m[i - 1] = '.') then m := Copy(m, 1, i - 2);
  if e >= 0 then es := StrInt(e, 0) else es := StrInt(-e, 0);
  if Length(es) < 2 then es := '0' + es;
  if e >= 0 then Result := m + 'e+' + es else Result := m + 'e-' + es;
  if neg then Result := '-' + Result;
end;

function FloatToStr(v: Double): AnsiString;
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
  { NaN and infinities first — neither survives the Trunc/Frac split below, and
    the normalise loop in FloatToExpStr would not terminate on an infinity. }
  if v <> v then begin Result := 'NaN'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := 'Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  { Past Int64, Trunc SATURATES at High(Int64) and every digit below is then
    derived from the saturated value — `d` goes out of 0..9 and
    Chr(Ord('0') + d) emits a byte that is not a digit at all. `1e19` printed
    9223372036854775809.o72036854775808, i.e. invalid UTF-8 on stdout, and it
    is reachable from plain arithmetic rather than only from a literal
    (bug-nilpy-large-float-str-overruns-into-garbage). }
  if (v > 9.2e18) or (v < -9.2e18) then
  begin
    Result := FloatToExpStr(v);
    Exit;
  end;
  { ...and the MIRROR of that guard, which was missing. The split below keeps
    15 DECIMAL places, so a value smaller than one unit in the last of them has
    intpart 0 and rounds fracpart to 0 as well: `1e-20` and `1e-300` both
    printed `0.0`, destroying the value silently. Route those to the same
    exponential form the large end already uses. The threshold is exactly where
    the fixed form stops being able to represent anything, so every value that
    already rendered correctly still takes the old path and its output is
    byte-identical (bug-nilpy-float-repr-loses-small-values-and-does-not-round-trip).
    FloatToExpStr normalises the mantissa into [1,10) before calling back here,
    so it cannot re-enter this branch. }
  if (v <> 0.0) and (v < 1.0e-15) and (v > -1.0e-15) then
  begin
    Result := FloatToExpStr(v);
    Exit;
  end;
  { NOTE: -0.0 still prints as `0.0` here. `v < 0` is False for negative zero,
    so only the sign BIT distinguishes it, and this unit declares no pointer
    type to read it through. Left deliberately — it is a display divergence,
    not value loss, and is recorded on the ticket above. }
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

function StrFloat(v: Double; width: Integer; decimals: Integer): AnsiString;
{ Format a Double like write(v:width:decimals). decimals < 0 -> natural form
  (FloatToStr); decimals >= 0 -> fixed, round-to-nearest, exactly `decimals`
  fractional digits (0 -> rounded integer, no point). Then right-justify to
  width with spaces. Matches the writeln float formatter for normal-range values.

  width < 0 (only the `Str(F, S)` statement's no-width default passes it):
  FPC's default Str(Double) form — ` d.ddddddddddddddddE+eee`, 17 significant
  digits, a LEADING SPACE for non-negative (where the '-' would go), 3-digit
  signed exponent. fcl-json's float tests do `Str(F,S); Delete(S,1,1)` and
  compare against the DOM's output, so both sides must produce FPC's text. }
var
  neg: Boolean;
  pw, scaled, ip, fp: Int64;
  i, k: Integer;
  capped: Boolean;
  fv: Double;
  frac: string;
  e: Integer;
  m: Double;
  digs: AnsiString;
begin
  { NaN and infinities before any of the three formatting shapes. The
    width<0 branch below has its OWN normalise loops (a third copy, beside
    FloatToStr's and FloatToExpStr's), and `Inf / 10.0` is still Inf, so
    `Str(F, S)` on a non-finite value spun forever. The fixed-decimals branch
    does not hang but scales through Int64 and printed
    9223372036854775809.000000 for +Inf — a silent wrong number, which is the
    worse half of the same defect.

    Spelled as FPC does for Str: a LEADING SPACE where the sign would go for
    the non-negative forms, matching the rest of this routine's contract
    (bug-a-writeln-of-a-non-finite-double-hangs). }
  if v <> v then begin Result := ' Nan'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := ' Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  if (width < 0) and (decimals < 0) then
  begin
    neg := v < 0;
    if neg then v := -v;
    e := 0;
    if v = 0 then
      digs := '00000000000000000'
    else
    begin
      { EXACT digits, shared with the writeln path — this branch used to carry
        its own normalise-by-repeated-division loop (the "third copy" its own
        header names), which was adrift from the 16th digit AND disagreed with
        writeln's copy: 1e100 printed ...006 here and ...007 there. Two
        spellings of one conversion in one file, giving different answers.
        bug-a-writeln-float-exponent-form-not-correctly-rounded }
      PxxSciDigits17(v, scaled, e);
      digs := StrInt(scaled, 0);
      while Length(digs) < 17 do digs := '0' + digs;
    end;
    if neg then Result := '-' else Result := ' ';
    Result := Result + digs[1] + '.';
    for i := 2 to 17 do Result := Result + digs[i];
    if e < 0 then begin Result := Result + 'E-'; e := -e; end
    else Result := Result + 'E+';
    frac := StrInt(e, 0);
    while Length(frac) < 3 do frac := '0' + frac;
    Result := Result + frac;
    Exit;
  end;
  if width < 0 then width := 0;
  if decimals < 0 then
    Result := FloatToStr(v)
  else
  begin
    neg := v < 0;
    if neg then v := -v;
    { 10^decimals, and whether it even fits Int64 (it does not past 18) }
    pw := 1; capped := False;
    for i := 1 to decimals do
      if pw <= 922337203685477580 then pw := pw * 10 else capped := True;
    if (not capped) and (v * pw < 9.2e18) then
    begin
      { The single-scaled-multiply path, kept EXACTLY as it was for every case
        it can represent — one multiply, one rounding, and every value that
        printed correctly before still prints the identical text. }
      scaled := Trunc(v * pw + 0.5);      { half AWAY FROM ZERO, as FPC rounds }
      ip := scaled div pw;
      fp := scaled mod pw;
      Result := StrInt(ip, 0);
      if decimals > 0 then
      begin
        frac := StrInt(fp, 0);
        while Length(frac) < decimals do frac := '0' + frac;
        Result := Result + '.' + frac;
      end;
    end
    else if v >= 9.2e18 then
      { The integer part alone does not fit Int64, so there is no fixed form to
        build. FPC keeps going here for a while (it prints 1e60 in full) and
        then falls back to an exponent form whose exponent width depends on
        whether the value was typed Extended — chasing that exactly is not
        worth it, so pxx uses its own exponent spelling and the residual is
        recorded as compat-pascal-write-fixed-huge-magnitude-differs-from-fpc.
        Whatever it prints, it is a number rather than the overflow debris the
        single-multiply path produced. }
      Result := FloatToExpStr(v)
    else
    begin
      { SPLIT, because `v * 10^decimals` overflowed Int64 — `WriteLn(1e16:0:5)`
        did, and printed 92233720368547.75808, which is 2^63's digits with a
        point pushed in. Nothing warned.

        The integer part is exact in Int64 here (v < 2^63 was just checked) and
        `v - ip` is exact too, both operands being representable. The fraction
        is below 1, so scaling it by up to 10^18 cannot overflow — one multiply
        and one rounding, the same quality as the fast path above. Digits past
        the 18th are printed as zeros rather than guessed: a double carries no
        information there, and FPC pads the same way (measured: `0.1:0:20` is
        `0.10000000000000000000` on both). }
      ip := Trunc(v);
      fv := v - ip;
      k := decimals;
      if k > 18 then k := 18;
      pw := 1;
      for i := 1 to k do pw := pw * 10;
      fp := Trunc(fv * pw + 0.5);                          { as above }
      if fp >= pw then begin fp := 0; ip := ip + 1; end;   { .999.. rounded up }
      Result := StrInt(ip, 0);
      if decimals > 0 then
      begin
        frac := StrInt(fp, 0);
        while Length(frac) < k do frac := '0' + frac;
        while Length(frac) < decimals do frac := frac + '0';
        Result := Result + '.' + frac;
      end;
    end;
    if neg then Result := '-' + Result;
  end;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

procedure Val(const s: AnsiString; var v: Int64; var code: Integer);
var
  i, len, base, dv: Integer;
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
  { FPC's RADIX PREFIXES, which this accepted none of: `$ff`, `xFF`, `0xFF`
    (hex), `&17` (octal), `%1011` (binary). Val('$ff', v, code) answered 0 with
    code=1 where FPC answers 255 — and `$`-prefixed constants are how Pascal
    source spells hex, so a config parser reading them got a silent 0 and a
    code its caller usually ignores. A bare prefix with no digits keeps FPC's
    answer too: code = the position after it.
    bug-p-val-rejects-the-radix-prefixes }
  base := 10;
  if i <= len then
  begin
    if s[i] = '$' then begin base := 16; Inc(i); end
    else if (s[i] = 'x') or (s[i] = 'X') then begin base := 16; Inc(i); end
    else if s[i] = '&' then begin base := 8; Inc(i); end
    else if s[i] = '%' then begin base := 2; Inc(i); end
    else if (s[i] = '0') and (i < len) and ((s[i + 1] = 'x') or (s[i + 1] = 'X')) then
    begin base := 16; Inc(i, 2); end;
  end;
  while i <= len do
  begin
    c := s[i];
    dv := -1;
    if (c >= '0') and (c <= '9') then dv := Ord(c) - Ord('0')
    else if (c >= 'a') and (c <= 'f') then dv := Ord(c) - Ord('a') + 10
    else if (c >= 'A') and (c <= 'F') then dv := Ord(c) - Ord('A') + 10;
    if (dv >= 0) and (dv < base) then
    begin
      n := n * base + dv;
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

procedure ValQWord(const s: AnsiString; var v: QWord; var code: Integer);
{ Val() with a QWord destination: unsigned accumulation with RANGE DETECTION —
  '18446744073709551616' (High(QWord)+1) must set code<>0, and the plain Int64
  Val cannot know its caller's signedness (tint642's testqwordstr). The parser
  routes Val(s, q, code) here when the destination is tyUInt64. }
var
  i, len, d: Integer;
  started: Boolean;
  n: QWord;
  c: Char;
begin
  v := 0;
  code := 0;
  n := 0;
  started := False;
  len := Length(s);
  i := 1;
  while (i <= len) and (s[i] = ' ') do
    Inc(i);
  if (i <= len) and (s[i] = '+') then
    Inc(i);
  while i <= len do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      d := Ord(c) - Ord('0');
      { n*10 + d must fit: High(QWord) = 18446744073709551615 }
      if (n > QWord(1844674407370955161)) or
         ((n = QWord(1844674407370955161)) and (d > 5)) then
      begin
        code := i;
        v := 0;
        Exit;
      end;
      n := n * 10 + QWord(d);
      started := True;
      Inc(i);
    end
    else
      break;
  end;
  if (not started) or (i <= len) then
  begin
    code := i;
    v := 0;
    Exit;
  end;
  v := n;
  code := 0;
end;

procedure ValFloat(const s: AnsiString; var v: Double; var code: Integer);
{ Parse [sign] digits [.digits] [(e|E)[sign]digits] into a Double. code = 0 on
  success, else the 1-based position of the first offending character (FPC
  convention). Pure float arithmetic — no libc. }
var
  i, len, ndig: Integer;
  neg, eneg, started: Boolean;
  mant, scale: Double;
  exp, expval, d: Integer;
  c: Char;
begin
  v := 0;
  code := 0;
  mant := 0;
  neg := False;
  started := False;
  len := Length(s);
  i := 1;
  while (i <= len) and (s[i] = ' ') do Inc(i);
  if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  { integer part. NOTE: float literals (10.0/1.0) are used throughout — a plain
    integer literal assigned/multiplied into a Double currently misses the
    int->float conversion (see feature-int-to-float-assign); 0.0 is safe because
    its bit pattern is identical. }
  while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
  begin
    mant := mant * 10.0 + (Ord(s[i]) - Ord('0'));
    started := True;
    Inc(i);
  end;
  { fractional part }
  scale := 1.0;
  if (i <= len) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      mant := mant * 10.0 + (Ord(s[i]) - Ord('0'));
      scale := scale * 10.0;
      started := True;
      Inc(i);
    end;
  end;
  { exponent }
  exp := 0;
  eneg := False;
  if (i <= len) and ((s[i] = 'e') or (s[i] = 'E')) then
  begin
    Inc(i);
    if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
    begin
      eneg := s[i] = '-';
      Inc(i);
    end;
    ndig := 0;
    while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      exp := exp * 10 + (Ord(s[i]) - Ord('0'));
      Inc(ndig);
      Inc(i);
    end;
    if ndig = 0 then started := False;
  end;
  if (not started) or (i <= len) then
  begin
    code := i;
    v := 0;
    Exit;
  end;
  mant := mant / scale;
  if neg then mant := -mant;
  { apply exponent by repeated multiply/divide (exact powers of ten) }
  expval := exp;
  while expval > 0 do
  begin
    if eneg then mant := mant / 10.0 else mant := mant * 10.0;
    Dec(expval);
  end;
  v := mant;
  code := 0;
end;

function PCharToString(p: PChar): AnsiString;
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

function __pxxCharArrayToStr(p: PChar; cap: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  if p = nil then Exit;
  i := 0;
  while (i < cap) and (p[i] <> #0) do
  begin
    Result := Result + p[i];
    i := i + 1;
  end;
end;

procedure __pxxStrToCharArray(p: PChar; cap: Integer; const s: AnsiString);
var i, n: Integer;
begin
  if p = nil then Exit;
  n := Length(s);
  if n > cap then n := cap;
  i := 0;
  while i < n do
  begin
    p[i] := s[i + 1];
    i := i + 1;
  end;
  while i < cap do
  begin
    p[i] := #0;
    i := i + 1;
  end;
end;

function __pxxWideCharToUTF8(u: Integer): AnsiString;
var c: Char;
begin
  u := u and $FFFF;
  Result := '';
  if u < $80 then
  begin
    c := Chr(u);
    Result := Result + c;
  end
  else if u < $800 then
  begin
    c := Chr($C0 or (u shr 6));        Result := Result + c;
    c := Chr($80 or (u and $3F));      Result := Result + c;
  end
  else if (u >= $D800) and (u <= $DFFF) then
  begin
    { a lone UTF-16 surrogate is not a code point; FPC's conversion DROPS it
      (fpjson's MaybeAppendUnicode appends a stale high surrogate right after
      the pair path already emitted the combined code point — FPC yields
      nothing there, so must we) }
    Result := '';
  end
  else
  begin
    c := Chr($E0 or (u shr 12));           Result := Result + c;
    c := Chr($80 or ((u shr 6) and $3F));  Result := Result + c;
    c := Chr($80 or (u and $3F));          Result := Result + c;
  end;
end;

function __pxxWideCharPairToUTF8(u1, u2: Integer): AnsiString;
var cp: Integer; c: Char;
begin
  u1 := u1 and $FFFF;
  u2 := u2 and $FFFF;
  if (u1 >= $D800) and (u1 <= $DBFF) and (u2 >= $DC00) and (u2 <= $DFFF) then
  begin
    cp := $10000 + ((u1 - $D800) shl 10) + (u2 - $DC00);
    Result := '';
    c := Chr($F0 or (cp shr 18));           Result := Result + c;
    c := Chr($80 or ((cp shr 12) and $3F)); Result := Result + c;
    c := Chr($80 or ((cp shr 6) and $3F));  Result := Result + c;
    c := Chr($80 or (cp and $3F));          Result := Result + c;
  end
  else
    Result := __pxxWideCharToUTF8(u1) + __pxxWideCharToUTF8(u2);
end;

function __pxxUCS4ToUTF8(u: Integer): AnsiString;
var c: Char;
begin
  Result := '';
  if (u < 0) or (u > $10FFFF) then Exit;          { not a code point }
  if (u >= $D800) and (u <= $DFFF) then Exit;     { lone surrogate — see the decl }
  if u < $80 then
  begin
    c := Chr(u);                            Result := Result + c;
  end
  else if u < $800 then
  begin
    c := Chr($C0 or (u shr 6));             Result := Result + c;
    c := Chr($80 or (u and $3F));           Result := Result + c;
  end
  else if u < $10000 then
  begin
    c := Chr($E0 or (u shr 12));            Result := Result + c;
    c := Chr($80 or ((u shr 6) and $3F));   Result := Result + c;
    c := Chr($80 or (u and $3F));           Result := Result + c;
  end
  else
  begin
    c := Chr($F0 or (u shr 18));            Result := Result + c;
    c := Chr($80 or ((u shr 12) and $3F));  Result := Result + c;
    c := Chr($80 or ((u shr 6) and $3F));   Result := Result + c;
    c := Chr($80 or (u and $3F));           Result := Result + c;
  end;
end;

function __pxxStrCopy(const s: AnsiString; index, count: Integer): AnsiString;
var i, n, last: Integer; r: AnsiString;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  { Cap count to the chars available from index BEFORE forming `last`, so the
    2-arg form's sentinel count (MaxInt) cannot overflow `index + count - 1`. }
  if index > n then count := 0
  else if count > n - index + 1 then count := n - index + 1;
  last := index + count - 1;
  r := '';
  i := index;
  while i <= last do
  begin
    r := r + s[i];
    i := i + 1;
  end;
  Result := r;
end;

procedure __pxxStrDelete(var s: AnsiString; index, count: Integer);
begin
  if (count <= 0) or (index < 1) or (index > Length(s)) then Exit;
  { __pxxStrCopy clamps count to the string end, so an over-long count is fine. }
  s := __pxxStrCopy(s, 1, index - 1) + __pxxStrCopy(s, index + count, Length(s));
end;

procedure __pxxStrInsert(const src: AnsiString; var s: AnsiString; index: Integer);
begin
  if index < 1 then index := 1;
  if index > Length(s) + 1 then index := Length(s) + 1;
  s := __pxxStrCopy(s, 1, index - 1) + src + __pxxStrCopy(s, index, Length(s));
end;

function __pxxAbsInt(x: Int64): Int64;
begin
  if x < 0 then Result := -x else Result := x;
end;

function __pxxAbsDbl(d: Double): Double;
begin
  { NEGATIVE ZERO is not less than zero, so the `d < 0` test left its sign
    alone and Abs(-0.0) answered -0.0 — where FPC answers 0.0 and so does
    CPython's abs(). Negating unconditionally when the sign bit is set is the
    whole rule; `d = 0.0` is true for -0.0 too, which is what makes it
    reachable without a bit test.
    bug-nilpy-abs-keeps-the-sign-of-negative-zero-and-min-max-break-ties-backwards }
  if d < 0 then Result := -d
  else if (d = 0.0) then Result := 0.0
  else Result := d;
end;

function __pxxSqrInt(x: Int64): Int64;
begin
  Result := x * x;
end;

function __pxxSqrDbl(d: Double): Double;
begin
  Result := d * d;
end;

function __pxxUpCase(c: Char): Char;
begin
  if (c >= 'a') and (c <= 'z') then Result := Chr(Ord(c) - 32) else Result := c;
end;

function __pxxPos(const sub, s: AnsiString): Integer;
var i, j, n, m: Integer; ok: Boolean;
begin
  Result := 0;
  n := Length(s); m := Length(sub);
  if (m = 0) or (m > n) then Exit;
  for i := 1 to n - m + 1 do
  begin
    ok := True;
    for j := 1 to m do
      if s[i + j - 1] <> sub[j] then begin ok := False; Break; end;
    if ok then begin Result := i; Exit; end;
  end;
end;

type
  PPxxPtr_ = ^Pointer;
  PPxxInt_ = ^NativeInt;

const
  PXX_RTTI_PARENT    = 8;
  PXX_RTTI_METHCOUNT = 48;
  PXX_RTTI_METHS     = 56;
  PXX_RTTI_METHSIZE  = 48;   { {name,code,arity,retKind,paramKinds,flags} }
  PXX_RTTI_METH_FLAGS = 40;
  PXX_RTTI_METH_PUBLISHED = 1;

function __pxxRttiOf(Instance: Pointer): Pointer;
{ The class RTTI blob of an instance: [[instance+0] - 8]. nil when the class
  publishes nothing (no blob is emitted for it). }
var vmt: Pointer;
begin
  Result := nil;
  if Instance = nil then Exit;
  vmt := PPxxPtr_(Instance)^;
  if vmt = nil then Exit;
  Result := PPxxPtr_(PtrUInt(vmt) - 8)^;
end;

function __pxxRttiName(P: Pointer): AnsiString;
{ Blob names are interned FROZEN strings: 8-byte length prefix, chars at +8. }
var n, i: NativeInt; pc: PChar; s: AnsiString;
begin
  s := '';
  if P <> nil then
  begin
    n := PPxxInt_(P)^;
    if (n > 0) and (n < 1024) then
    begin
      pc := PChar(PtrUInt(P) + 8);
      i := 0;
      while i < n do
      begin
        s := s + pc^;
        pc := PChar(PtrUInt(pc) + 1);
        i := i + 1;
      end;
    end;
  end;
  Result := s;
end;

function __pxxInheritsFrom(Rtti, Other: Pointer): Boolean;
{ X.InheritsFrom(C): True when Rtti IS C or descends from it, walking the blob's
  parent chain. FPC's TObject.InheritsFrom is reflexive -- a class inherits from
  itself -- and so is this. nil never inherits from anything. }
var cur: Pointer;
begin
  Result := False;
  if (Rtti = nil) or (Other = nil) then Exit;
  cur := Rtti;
  while cur <> nil do
  begin
    if cur = Other then
    begin
      Result := True;
      Exit;
    end;
    cur := PPxxPtr_(PtrUInt(cur) + PXX_RTTI_PARENT)^;
  end;
end;

function __pxxClassName(Rtti: Pointer): AnsiString;
{ x.ClassName. Rtti is the class blob; its +0 field is a POINTER to the interned
  name (NOT the name itself -- __pxxRttiName wants that pointer, so deref first).
  Every class carries a blob now, so this answers for any class; nil only when the
  caller had no class at all. }
begin
  Result := '';
  if Rtti = nil then Exit;
  Result := __pxxRttiName(PPxxPtr_(Rtti)^);
end;

function __pxxSameNameCI(const a, b: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if Length(a) <> Length(b) then Exit;
  for i := 1 to Length(a) do
    if __pxxUpCase(a[i]) <> __pxxUpCase(b[i]) then Exit;
  Result := True;
end;

function __pxxMethodAddress(Instance: Pointer; const Name: AnsiString): Pointer;
var rtti, meths, e: Pointer; cnt, i: Integer;
begin
  Result := nil;
  rtti := __pxxRttiOf(Instance);
  while rtti <> nil do
  begin
    cnt := Integer(PPxxInt_(PtrUInt(rtti) + PXX_RTTI_METHCOUNT)^);
    meths := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_METHS)^;
    if (cnt > 0) and (meths <> nil) then
      for i := 0 to cnt - 1 do
      begin
        e := Pointer(PtrUInt(meths) + PtrUInt(i * PXX_RTTI_METHSIZE));
        { the table now holds every method; MethodAddress is published-only (FPC) }
        if (PPxxInt_(PtrUInt(e) + PXX_RTTI_METH_FLAGS)^ and PXX_RTTI_METH_PUBLISHED) = 0 then Continue;
        if __pxxSameNameCI(__pxxRttiName(PPxxPtr_(e)^), Name) then
        begin
          Result := PPxxPtr_(PtrUInt(e) + 8)^;
          Exit;
        end;
      end;
    rtti := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_PARENT)^;
  end;
end;

function __pxxMethodName(Instance: Pointer; Address: Pointer): AnsiString;
var rtti, meths, e: Pointer; cnt, i: Integer;
begin
  Result := '';
  if Address = nil then Exit;
  rtti := __pxxRttiOf(Instance);
  while rtti <> nil do
  begin
    cnt := Integer(PPxxInt_(PtrUInt(rtti) + PXX_RTTI_METHCOUNT)^);
    meths := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_METHS)^;
    if (cnt > 0) and (meths <> nil) then
      for i := 0 to cnt - 1 do
      begin
        e := Pointer(PtrUInt(meths) + PtrUInt(i * PXX_RTTI_METHSIZE));
        if (PPxxInt_(PtrUInt(e) + PXX_RTTI_METH_FLAGS)^ and PXX_RTTI_METH_PUBLISHED) = 0 then Continue;
        if PPxxPtr_(PtrUInt(e) + 8)^ = Address then
        begin
          Result := __pxxRttiName(PPxxPtr_(e)^);
          Exit;
        end;
      end;
    rtti := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_PARENT)^;
  end;
end;

const
  PXX_RTTI_IFCOUNT   = 80;
  PXX_RTTI_IFACES    = 88;
  PXX_RTTI_IFSIZE    = 32;   { {GUID:16, IMT ptr:8, interface id:8} }
  PXX_RTTI_IF_IMT    = 16;
  PXX_RTTI_IF_ID     = 24;

function __pxxGuidEq(a, b: Pointer): Boolean;
var pa, pb: PByte; i: Integer;
begin
  pa := PByte(a);
  pb := PByte(b);
  Result := True;
  for i := 0 to 15 do
    if pa[i] <> pb[i] then
    begin
      Result := False;
      Exit;
    end;
end;

function __pxxGetInterface(Instance: Pointer; IID: Pointer; Obj: Pointer): Boolean;
var
  rtti, ifaces, e: Pointer;
  outp: PPxxPtr_;
  cnt, i: Integer;
begin
  Result := False;
  if (Instance = nil) or (IID = nil) then Exit;
  rtti := __pxxRttiOf(Instance);
  while rtti <> nil do
  begin
    cnt := Integer(PPxxInt_(PtrUInt(rtti) + PXX_RTTI_IFCOUNT)^);
    ifaces := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_IFACES)^;
    if (cnt > 0) and (ifaces <> nil) then
      for i := 0 to cnt - 1 do
      begin
        e := Pointer(PtrUInt(ifaces) + PtrUInt(i * PXX_RTTI_IFSIZE));
        if __pxxGuidEq(e, IID) then
        begin
          if Obj <> nil then
          begin
            { a pxx interface value is ONE pointer: the instance (FPC's ABI).
              The IMT is recovered per call via __pxxIntfIMT. }
            outp := PPxxPtr_(Obj);
            outp^ := Instance;
          end;
          Result := True;
          Exit;
        end;
      end;
    rtti := PPxxPtr_(PtrUInt(rtti) + PXX_RTTI_PARENT)^;
  end;
end;

end.
